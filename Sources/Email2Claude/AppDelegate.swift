import AppKit
import Carbon.HIToolbox
import Email2ClaudeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var busy = false

    private let configURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Email2Claude/config.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "envelope.arrow.triangle.branch", accessibilityDescription: "Email2Claude")
        buildMenu()

        hotKey = HotKey(keyCode: kVK_ANSI_C, modifiers: optionKey | cmdKey) { [weak self] in
            self?.sendSelectedEmail()
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
        menu.addItem(withTitle: "Send selected email to Claude (⌥⌘C)", action: #selector(menuSend), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Add Route…", action: #selector(addRoute), keyEquivalent: "")
        menu.addItem(withTitle: "Set Default Chat…", action: #selector(setDefaultChat), keyEquivalent: "")
        menu.addItem(withTitle: "Open config.json", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        statusItem.menu = menu
    }

    @objc private func menuSend() { sendSelectedEmail() }

    private func sendSelectedEmail() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let email = try MailReader.readSelectedEmail()
                try await ClaudeBridge.deliver(email, config: Config.load(from: configURL))
            } catch {
                NSSound.beep()
                alert("Email2Claude", error.localizedDescription)
            }
        }
    }

    @objc private func addRoute() {
        let address = NSTextField(frame: NSRect(x: 0, y: 30, width: 320, height: 24))
        address.placeholderString = "Recipient address, or @domain.com"
        let link = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        link.placeholderString = "Claude chat link (https://claude.ai/chat/…)"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        box.addSubview(address)
        box.addSubview(link)

        let panel = NSAlert()
        panel.messageText = "Add route"
        panel.informativeText = "Emails to this address are pasted into that chat."
        panel.accessoryView = box
        panel.addButton(withTitle: "Save")
        panel.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .alertFirstButtonReturn else { return }

        guard ChatLink.appURL(from: link.stringValue) != nil, !address.stringValue.isEmpty else {
            return alert("Invalid route", "Enter an address and a claude.ai/chat/… link.")
        }
        var config = Config.load(from: configURL)
        config.routes.removeAll { $0.address.lowercased() == address.stringValue.lowercased() }
        config.routes.append(Route(address: address.stringValue, chatURL: link.stringValue))
        save(config)
    }

    @objc private func setDefaultChat() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Claude chat link, empty = always start a new chat"
        let panel = NSAlert()
        panel.messageText = "Default chat"
        panel.informativeText = "Used when no route matches the email's recipients."
        panel.accessoryView = field
        panel.addButton(withTitle: "Save")
        panel.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .alertFirstButtonReturn else { return }

        var config = Config.load(from: configURL)
        config.defaultChatURL = field.stringValue.isEmpty ? nil : field.stringValue
        save(config)
    }

    @objc private func openConfig() { NSWorkspace.shared.open(configURL) }

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
