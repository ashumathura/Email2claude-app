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
    /// - Parameter previewPrompt: the action prompt the preview shows the route prompt being added to.
    /// - Parameter email: the email being sent, shown at the top so it is clear what is being routed.
    static func ask(email: Email, suggestion: Router.RouteSuggestion, previewPrompt: String) -> ChooserResult {
        var result = ChooserResult.cancel
        let address = suggestion.address(for: suggestion.field) ?? ""
        let domain = Router.domain(of: address) ?? address
        let subject = email.subject.isEmpty ? "(no subject)" : email.subject
        let subtitle = "\(email.sender)\n“\(subject)”\nThere's no route for it yet. Choose what should happen."

        let view = RouteEditorView(
            title: "Where should this email go?",
            subtitle: subtitle,
            initial: Route(domain: domain, matchOn: suggestion.field, kind: .newChat),
            suggestions: suggestion,
            offersOnce: true,
            previewPrompt: previewPrompt,
            loadChats: { ClaudeSidebar.loadChatList() },
            onSave: { result = .save($0); NSApp.stopModal() },
            onOnce: { result = .once($0); NSApp.stopModal() },
            onNeverAsk: { result = .alwaysNewChat; NSApp.stopModal() },
            onCancel: { result = .cancel; NSApp.stopModal() })

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled]
        window.title = "MailtoChat"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
    }
}
