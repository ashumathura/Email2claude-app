import AppKit
import Carbon.HIToolbox
import Combine
import Email2ClaudeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private var store: ConfigStore!
    private var activity: ActivityStore!
    private var updates: UpdateManager!
    private var observers = Set<AnyCancellable>()
    private var busy = false {
        didSet { statusItem?.button?.alphaValue = busy ? 0.45 : 1 }
    }

    private static let keyCodes: [Action: Int] = [
        .reply: kVK_ANSI_R, .summary: kVK_ANSI_S, .research: kVK_ANSI_D,
        .custom1: kVK_ANSI_1, .custom2: kVK_ANSI_2, .pasteOnly: kVK_ANSI_C,
    ]
    private static let symbols: [Action: String] = [
        .reply: "arrowshape.turn.up.left", .summary: "checklist", .research: "magnifyingglass",
        .custom1: "sparkles", .custom2: "sparkles", .pasteOnly: "doc.on.clipboard",
    ]

    /// What a route lookup (or the user's answer) decided for one email.
    private struct Resolved {
        let target: ChatTarget
        let destination: Route
        let rule: String
    }

    // main.swift creates the delegate outside the main actor; every stored property has a default.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ConfigStore()
        activity = ActivityStore()
        updates = UpdateManager(store: store)
        updates.openSettings = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.toolTip = "eMail to Claude"
        buildMenu()
        // Rebuild the menu when action names change. @Published fires before the value is set,
        // so hop to the next main-queue turn to see the new config.
        store.$config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &observers)
        registerHotKeys()
        MailReader.sweepOldAttachmentFolders()
        // Ask about analytics before anything contacts the server or asks for permissions.
        DispatchQueue.main.async { [weak self] in self?.finishLaunching() }
    }

    private func finishLaunching() {
        if store.config.analyticsChoice == .unset && BackendConfig.isPackagedApp {
            store.config.analyticsChoice = PrivacyChoice.ask()
            store.config.analyticsChoiceDate = Date()
        }
        _ = ClaudeBridge.accessibilityGranted(prompt: true)
        updates.start()
    }

    /// The brand glyph from the app bundle, as a template image so macOS tints it for light and dark
    /// menu bars. Falls back to a system symbol when running outside the bundle (swift run).
    private static func menuBarIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 20, height: 20)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "envelope.arrow.triangle.branch", accessibilityDescription: "eMail to Claude")
    }

    private func icon(_ symbol: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: "eMail to Claude")
    }

    private func registerHotKeys() {
        var failed: [String] = []
        for action in Action.allCases {
            let registered = HotKeyCenter.shared.register(
                keyCode: Self.keyCodes[action] ?? 0, modifiers: optionKey | cmdKey
            ) { [weak self] in
                Task { @MainActor in self?.send(action) }
            }
            if !registered { failed.append(action.shortcutLabel) }
        }
        if !failed.isEmpty {
            alert("Some shortcuts are unavailable", "\(failed.joined(separator: ", ")) is already used by another app.")
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let sendMenu = NSMenu()
        for action in Action.allCases where store.config.isConfigured(action) {
            let item = NSMenuItem(
                title: store.config.name(for: action), action: #selector(menuSend(_:)),
                keyEquivalent: action.keyEquivalent)
            item.keyEquivalentModifierMask = [.option, .command]
            item.representedObject = action.rawValue
            item.image = icon(Self.symbols[action] ?? "envelope")
            item.target = self
            sendMenu.addItem(item)
        }
        let sendItem = NSMenuItem(title: "Send to Claude", action: nil, keyEquivalent: "")
        sendItem.image = icon("paperplane")
        sendItem.submenu = sendMenu
        menu.addItem(sendItem)

        menu.addItem(.separator())
        let update = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit eMail to Claude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuSend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        send(action)
    }

    @objc private func checkForUpdates() { updates.checkNow() }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(store: store, activity: activity, updates: updates) }
        settingsWindow?.show()
    }

    private func send(_ action: Action) {
        let config = store.config
        guard config.isConfigured(action) else {
            alert("This action isn't set up yet", "Give it a name and a prompt in Settings → Prompts.")
            return
        }
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let start = Date()
                let email = try MailReader.readSelectedEmail()
                Log.write("\(action.rawValue): read email in \(Log.seconds(since: start)) (\(email.body.count) chars, \(email.attachmentPaths.count) attachments)")
                // Claude may still be reading the files after the paste, so removal waits a little.
                defer { Self.removeAttachmentFolder(of: email, after: .seconds(120)) }
                guard let resolved = resolveTarget(for: email) else {
                    Self.removeAttachmentFolder(of: email, after: .zero)
                    return
                }

                // Paste-only sends the email alone; otherwise the prompt goes on top and, with
                // auto-send on, the message is submitted so Claude acts on it straight away.
                let mode = config.mode(for: action)
                // A route's standing instructions go after the action's prompt. Paste-only actions add
                // no prompt, so the route's instructions don't apply to them either.
                let instruction = mode == .prompt
                    ? PromptBuilder.compose(
                        actionPrompt: config.instruction(for: action),
                        routeInstructions: resolved.destination.instructions)
                    : ""
                try await ClaudeBridge.deliver(
                    email, to: resolved.target, instruction: instruction,
                    sendAutomatically: mode == .prompt && config.autoSend, config: config)

                if store.config.keepActivityLog {
                    activity.append(ActivityEntry(
                        subject: email.subject, sender: email.sender, messageID: email.messageID,
                        rule: resolved.rule, destination: resolved.destination,
                        actionName: config.name(for: action), mode: mode, prompt: instruction))
                }
                Log.write("\(action.rawValue): done in \(Log.seconds(since: start))")
            } catch {
                NSSound.beep()
                alert("eMail to Claude", error.localizedDescription)
            }
        }
    }

    /// Known route → its destination. No route → ask (unless the user chose never to be asked, in
    /// which case it's a new chat). nil means the user cancelled.
    private func resolveTarget(for email: Email) -> Resolved? {
        let newChat = Resolved(target: .newChat, destination: Route(domain: "", kind: .newChat), rule: "")
        if let route = Router.route(for: email, config: store.config) {
            return Resolved(target: route.target, destination: route, rule: route.domain)
        }
        guard let suggestion = Router.suggestion(for: email, config: store.config),
              store.config.askForUnknownRoutes
        else { return newChat }

        switch RouteChooser.ask(suggestion: suggestion, previewPrompt: store.config.instruction(for: .reply)) {
        case .save(let route):
            store.config.upsert(route)
            return Resolved(target: route.target, destination: route, rule: Router.normalizeRule(route.domain))
        case .once(let route):
            return Resolved(target: route.target, destination: route, rule: "")
        case .alwaysNewChat:
            store.config.askForUnknownRoutes = false
            return newChat
        case .cancel:
            return nil
        }
    }

    /// Deletes the temporary attachment files saved for an email.
    private static func removeAttachmentFolder(of email: Email, after delay: Duration) {
        guard let folder = email.attachmentFolder else { return }
        Task.detached {
            try? await Task.sleep(for: delay)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        panel.runModal()
    }
}
