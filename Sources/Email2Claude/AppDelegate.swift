import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import Email2ClaudeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private var store: ConfigStore!
    private var activity: ActivityStore!
    private var updates: UpdateManager!
    private let popover = NSPopover()
    private let menuState = MenuState()
    private var busy = false {
        didSet {
            statusItem?.button?.alphaValue = busy ? 0.45 : 1
            menuState.busy = busy
        }
    }

    private static let keyCodes: [Action: Int] = [
        .reply: kVK_ANSI_R, .summary: kVK_ANSI_S, .research: kVK_ANSI_D,
        .custom1: kVK_ANSI_1, .custom2: kVK_ANSI_2, .pasteOnly: kVK_ANSI_C,
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
        statusItem.button?.toolTip = "MailtoChat"
        setUpPanel()
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
        // A free license key needs an email address: ask once, right after the privacy choice.
        if BackendConfig.isPackagedApp && store.config.licenseKey.isEmpty && !store.config.emailPromptShown {
            EmailSignup.show(updates: updates) { [weak self] in
                self?.store.config.emailPromptShown = true
                self?.finishStartup()
            }
        } else {
            finishStartup()
        }
    }

    private func finishStartup() {
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
        return NSImage(systemSymbolName: "envelope.arrow.triangle.branch", accessibilityDescription: "MailtoChat")
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

    /// The menu-bar icon opens a panel (like OneDrive's) instead of a menu: the actions are listed
    /// directly, with the app's own commands below a divider. It updates itself when settings change.
    private func setUpPanel() {
        let view = MenuPanelView(
            store: store, state: menuState,
            onSend: { [weak self] action in
                self?.closePanel()
                // Let the panel finish closing so focus is back where it was before the email is read.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.send(action) }
            },
            onCheckUpdates: { [weak self] in self?.closePanel(); self?.updates.checkNow() },
            onSettings: { [weak self] in self?.closePanel(); self?.showSettings() },
            onSupport: { [weak self] in self?.closePanel(); Donate.showDialog() },
            onQuit: { NSApp.terminate(nil) })
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
    }

    @objc private func togglePanel() {
        if popover.isShown {
            closePanel()
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePanel() { popover.performClose(nil) }

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
                if email.selectionCount > 1, config.warnMultipleSelection, !confirmFirstEmailOnly(email) {
                    Self.removeAttachmentFolder(of: email, after: .zero)
                    return
                }
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
                // After the 20th email, the next delivery asks once for a donation. It waits a moment so the
                // paste has finished, and runs apart from this task so it never blocks the next send.
                if store.config.recordDelivery() {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        Donate.showDialog()
                    }
                }
            } catch {
                NSSound.beep()
                alert("MailtoChat", error.localizedDescription)
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

    /// Several emails are selected but only the first is sent. Returns false if the user cancels.
    private func confirmFirstEmailOnly(_ email: Email) -> Bool {
        let panel = NSAlert()
        panel.messageText = "\(email.selectionCount) emails are selected"
        panel.informativeText = "MailtoChat sends one email at a time, so only the first one will go to Claude:\n\n“\(email.subject)”"
        panel.addButton(withTitle: "Send First Email")
        panel.addButton(withTitle: "Cancel")
        panel.showsSuppressionButton = true
        panel.suppressionButton?.title = "Don't warn me again"
        NSApp.activate(ignoringOtherApps: true)
        let send = panel.runModal() == .alertFirstButtonReturn
        if panel.suppressionButton?.state == .on { store.config.warnMultipleSelection = false }
        return send
    }

    private func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        panel.runModal()
    }
}
