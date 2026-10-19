import AppKit
import SwiftUI
import Email2ClaudeCore

/// The wording used in the first-run question and in Settings, so the two never disagree.
enum PrivacyText {
    static let sharedItems = [
        "A random device ID, and the dates you first and last used the app",
        "The app version, your macOS version and your language",
        "Your IP address, and the country and city it points to",
        "Your license key",
    ]
    static let minimalItems = [
        "A random device ID, and the dates you first and last used the app",
        "Nothing else: no IP address, location, versions or language are stored",
    ]
    static let footer = "Optional, and no feature depends on it. In both cases the app sends your license key and versions when it checks for updates, so it can check your license and offer a compatible update; they are only stored if you share analytics, and your IP address is not stored either. Data is kept with Supabase in the EU (Ireland). You can change your choice or erase your data at any time in Settings → License & Privacy."
}

/// The first-run question. Two equal choices, none preselected.
struct PrivacyChoiceView: View {
    let onChoose: (AnalyticsChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Help improve eMail to Claude?").font(.title2.weight(.semibold))
                    Text("The app checks for updates and your license about once a week. Choose what else, if anything, you're happy to share.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                card(
                    title: "Share analytics", items: PrivacyText.sharedItems,
                    detail: "Used to understand how the app is used and to give support.",
                    button: "Share Analytics", choice: .shared)
                card(
                    title: "Don't share analytics", items: PrivacyText.minimalItems,
                    detail: "Enough to check updates and your license.",
                    button: "Don't Share", choice: .notShared)
            }

            Text(PrivacyText.footer)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = BackendConfig.privacyPolicyURL {
                Link("Read the privacy policy", destination: url).font(.caption)
            }
        }
        .padding(24)
        .frame(width: 660)
        .tint(Brand.accent)
    }

    private func card(title: String, items: [String], detail: String, button: String, choice: AnalyticsChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(button) { onChoose(choice) }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(choice == .notShared ? .cancelAction : nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
enum PrivacyChoice {
    /// Blocks until the user picks. Pressing Esc counts as "Don't share".
    static func ask() -> AnalyticsChoice {
        var choice = AnalyticsChoice.notShared
        let view = PrivacyChoiceView { picked in
            choice = picked
            NSApp.stopModal()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled]
        window.title = "eMail to Claude"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return choice
    }
}
