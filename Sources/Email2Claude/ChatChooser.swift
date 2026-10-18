import AppKit
import Email2ClaudeCore

enum ChooserResult {
    case save(Route)
    case newChatOnce
    case cancel
}

/// The dialog that maps a To address to a Claude chat.
@MainActor
enum ChatChooser {
    private static let newChatTitle = "New chat each time"

    /// - Parameters:
    ///   - address: pre-filled and locked when asking about an unknown address; nil lets the user type one.
    ///   - offerOnce: adds a "New chat just this once" button (used from the hotkey flow).
    static func ask(address: String?, current: Route? = nil, offerOnce: Bool) -> ChooserResult {
        let addressField = NSTextField(frame: NSRect(x: 0, y: 92, width: 340, height: 24))
        addressField.placeholderString = "Recipient address, or @domain.com"
        addressField.stringValue = address ?? current?.address ?? ""
        addressField.isEditable = address == nil

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 58, width: 340, height: 26), pullsDown: false)
        popup.addItem(withTitle: newChatTitle)
        let titles = ClaudeSidebar.chatTitles()
        if !titles.isEmpty { popup.menu?.addItem(.separator()) }
        titles.forEach { popup.addItem(withTitle: $0) }
        if let saved = current?.chatTitle, !titles.contains(saved) { popup.addItem(withTitle: saved) }
        popup.selectItem(withTitle: current?.chatTitle ?? newChatTitle)

        let hint = NSTextField(labelWithString: titles.isEmpty
            ? "Couldn't read Claude's chat list. Open Claude, or paste a chat link below."
            : "Chats from Claude's sidebar:")
        hint.frame = NSRect(x: 0, y: 36, width: 340, height: 16)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let linkField = NSTextField(frame: NSRect(x: 0, y: 4, width: 340, height: 24))
        linkField.placeholderString = "Optional: chat link (https://claude.ai/chat/…) — overrides the list"
        linkField.stringValue = current?.chatURL ?? ""

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 120))
        [addressField, popup, hint, linkField].forEach(box.addSubview)

        let panel = NSAlert()
        panel.messageText = address == nil ? "Route an address to a Claude chat" : "New recipient: \(address!)"
        panel.informativeText = address == nil
            ? "Emails sent to this address will be pasted into the chat you pick."
            : "This To address has no chat yet. Pick one and the app remembers it."
        panel.accessoryView = box
        panel.addButton(withTitle: "Save")
        if offerOnce { panel.addButton(withTitle: "New chat just this once") }
        panel.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        let response = panel.runModal()
        let once = offerOnce && response == .alertSecondButtonReturn
        if once { return .newChatOnce }
        guard response == .alertFirstButtonReturn else { return .cancel }

        let typedAddress = addressField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !typedAddress.isEmpty else { return .cancel }
        let link = linkField.stringValue.trimmingCharacters(in: .whitespaces)
        let title = popup.titleOfSelectedItem == newChatTitle ? nil : popup.titleOfSelectedItem
        return .save(Route(address: typedAddress, chatTitle: title, chatURL: link.isEmpty ? nil : link))
    }
}
