import AppKit
import SwiftUI

/// The donation request, worded once so the menu and Settings always say the same thing.
enum Donate {
    static let url = URL(string: "https://revolut.me/ashu_m")!

    static let title = "Enjoying the app?"
    static let message = "If you like the app: it's free for now, but to keep it free I'd appreciate your donation. Thank you very much!"
    static let linkLead = "Follow this link to send me money on Revolut:"
    static let privacyNote = "The link opens in your browser. The app sends nothing to Revolut."

    static func open() { NSWorkspace.shared.open(url) }

    /// A short dialog from the menu: asks once, opens the link only if the user chooses to.
    @MainActor static func showDialog() {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = "\(message)\n\n\(linkLead)\n\(url.absoluteString)\n\n\(privacyNote)"
        panel.icon = NSApp.applicationIconImage
        panel.addButton(withTitle: "Donate on Revolut")
        panel.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .alertFirstButtonReturn { open() }
    }
}
