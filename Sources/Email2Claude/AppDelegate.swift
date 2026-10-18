import AppKit
import Carbon.HIToolbox
import Email2ClaudeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var routesWindow: RoutesWindowController?
    private var busy = false

    private let configURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Email2Claude/config.json")

    // main.swift creates the delegate outside the main actor; every stored property has a default.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "envelope.arrow.triangle.branch", accessibilityDescription: "Email2Claude")
        buildMenu()

        hotKey = HotKey(keyCode: kVK_ANSI_C, modifiers: optionKey | cmdKey) { [weak self] in
            Task { @MainActor in self?.sendSelectedEmail() }
        }
        if hotKey == nil {
            alert("Could not register ⌥⌘C", "Another app may already own this shortcut.")
        }
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? Config().save(to: configURL)
        }
        _ = ClaudeBridge.accessibilityGranted(prompt: true)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let items: [(String, Selector, String)] = [
            ("Send selected email to Claude (⌥⌘C)", #selector(menuSend), ""),
            ("Routes…", #selector(showRoutes), ","),
            ("Open config.json", #selector(openConfig), ""),
        ]
        for (title, action, key) in items {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuSend() { sendSelectedEmail() }

    @objc private func showRoutes() {
        if routesWindow == nil {
            routesWindow = RoutesWindowController(
                load: { [unowned self] in Config.load(from: configURL) },
                save: { [unowned self] in save($0) })
        }
        routesWindow?.show()
    }

    @objc private func openConfig() { NSWorkspace.shared.open(configURL) }

    private func sendSelectedEmail() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let email = try MailReader.readSelectedEmail()
                var config = Config.load(from: configURL)
                guard let target = resolveTarget(for: email, config: &config) else { return }
                try await ClaudeBridge.deliver(email, to: target, config: config)
            } catch {
                NSSound.beep()
                alert("Email2Claude", error.localizedDescription)
            }
        }
    }

    /// Known To address → its chat. Unknown → ask, and remember the answer. nil means the user cancelled.
    private func resolveTarget(for email: Email, config: inout Config) -> ChatTarget? {
        if let route = Router.route(for: email, config: config) { return route.target }
        guard let address = Router.unknownAddress(for: email, config: config) else { return .newChat }
        switch ChatChooser.ask(address: address, offerOnce: true) {
        case .save(let route):
            config.upsert(route)
            save(config)
            return route.target
        case .newChatOnce:
            return .newChat
        case .cancel:
            return nil
        }
    }

    private func save(_ config: Config) {
        do { try config.save(to: configURL) } catch { alert("Could not save config", error.localizedDescription) }
    }

    private func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        panel.runModal()
    }
}
