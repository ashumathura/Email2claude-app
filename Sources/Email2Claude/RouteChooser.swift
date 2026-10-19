import AppKit
import SwiftUI
import Email2ClaudeCore

enum ChooserResult {
    case save(Route)
    case once(Route)
    case alwaysNewChat
    case cancel
}

/// The modal window shown when an email matches no route yet.
@MainActor
enum RouteChooser {
    /// - Parameter previewPrompt: the action prompt the preview shows standing instructions being added to.
    static func ask(suggestion: Router.RouteSuggestion, previewPrompt: String) -> ChooserResult {
        var result = ChooserResult.cancel
        let address = suggestion.address(for: suggestion.field) ?? ""
        let domain = Router.domain(of: address) ?? address
        let subtitle = suggestion.field == .from
            ? "There's no Claude destination yet for mail received from \(address). Choose one and eMail to Claude will remember it."
            : "There's no Claude destination yet for mail sent to \(address). Choose one and eMail to Claude will remember it."

        let view = RouteEditorView(
            title: "No route for this email yet",
            subtitle: subtitle,
            initial: Route(domain: domain, matchOn: suggestion.field, kind: .newChat),
            suggestions: suggestion,
            offersOnce: true,
            previewPrompt: previewPrompt,
            loadChats: { ClaudeSidebar.chatTitles() },
            onSave: { result = .save($0); NSApp.stopModal() },
            onOnce: { result = .once($0); NSApp.stopModal() },
            onNeverAsk: { result = .alwaysNewChat; NSApp.stopModal() },
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
