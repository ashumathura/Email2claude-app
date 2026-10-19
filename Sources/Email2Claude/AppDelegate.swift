import AppKit
import Carbon.HIToolbox
import Email2ClaudeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private var store: ConfigStore!
    private var busy = false {
        didSet { statusItem?.button?.alphaValue = busy ? 0.45 : 1 }
    }

    private static let keyCodes: [Action: Int] = [
        .reply: kVK_ANSI_R, .summary: kVK_ANSI_S, .research: kVK_ANSI_D, .pasteOnly: kVK_ANSI_C,
    ]
    private static let symbols: [Action: String] = [
        .reply: "arrowshape.turn.up.left", .summary: "checklist",
        .research: "magnifyingglass", .pasteOnly: "doc.on.clipboard",
    ]

    // main.swift creates the delegate outside the main actor; every stored property has a default.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ConfigStore()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.toolTip = "eMail to Claude"
        buildMenu()
        registerHotKeys()
        _ = ClaudeBridge.accessibilityGranted(prompt: true)
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
        for action in Action.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuSend(_:)), keyEquivalent: action.keyEquivalent)
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

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(store: store) }
        settingsWindow?.show()
    }

    private func send(_ action: Action) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let start = Date()
                let email = try MailReader.readSelectedEmail()
                Log.write("\(action.rawValue): read email in \(Log.seconds(since: start)) (\(email.body.count) chars, \(email.attachmentPaths.count) attachments)")
                guard let target = resolveTarget(for: email) else { return }
                try await ClaudeBridge.deliver(email, to: target, action: action, config: store.config)
                Log.write("\(action.rawValue): done in \(Log.seconds(since: start))")
            } catch {
                NSSound.beep()
                alert("eMail to Claude", error.localizedDescription)
            }
        }
    }

    /// Known domain → its destination. Unknown → ask, and remember the answer. nil means cancelled.
    private func resolveTarget(for email: Email) -> ChatTarget? {
        if let route = Router.route(for: email, config: store.config) { return route.target }
        guard let address = Router.unknownAddress(for: email, config: store.config) else { return .newChat }
        switch RouteChooser.ask(address: address) {
        case .save(let route):
            store.config.upsert(route)
            return route.target
        case .once(let route):
            return route.target
        case .cancel:
            return nil
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
