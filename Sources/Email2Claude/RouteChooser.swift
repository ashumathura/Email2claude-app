import AppKit
import SwiftUI
import Email2ClaudeCore

enum ChooserResult {
    case save(Route)
    case once(Route)
    case cancel
}

/// The modal window shown when an email's To address has no route yet.
@MainActor
enum RouteChooser {
    static func ask(address: String) -> ChooserResult {
        var result = ChooserResult.cancel
        let domain = Router.domain(of: address) ?? address

        let view = RouteEditorView(
            title: "New recipient",
            subtitle: "There's no Claude destination yet for mail to \(address). Choose one and eMail to Claude will remember it.",
            initial: Route(domain: domain, kind: .newChat),
            offersOnce: true,
            loadChats: { ClaudeSidebar.chatTitles() },
            onSave: { result = .save($0); NSApp.stopModal() },
            onOnce: { result = .once($0); NSApp.stopModal() },
            onCancel: { result = .cancel; NSApp.stopModal() })

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled]
        window.title = "eMail to Claude"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
    }
}
