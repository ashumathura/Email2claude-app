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
    /// The promise that matters most, shown wherever the analytics choice is.
    static let localTitle = "Your emails never leave your Mac"
    static let localBody = "Your emails, attachments and prompts are never sent to the developer or to any server of ours. They go straight from Mail into the Claude app on this Mac, and nowhere else. Once they are in Claude, Claude handles them under its own terms, exactly as if you had pasted them yourself."

    static let footer = "This choice is only about usage information, and no feature depends on it. In both cases the app sends your license key and versions when it checks for updates, so it can check your license and offer a compatible update; they are only stored if you share analytics, and your IP address is not stored either. Data is kept with Supabase in the EU (Ireland). You can change your choice or erase your data at any time in Settings → License & Privacy."
}

/// A prominent reminder that email content stays on this Mac.
struct LocalPromiseBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26))
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(PrivacyText.localTitle).font(.headline)
                Text(PrivacyText.localBody)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.accent.opacity(0.35)))
    }
}

/// The first-run question. Two equal choices, none preselected.
///
/// The explanation scrolls if the screen is short, but the two buttons live in a fixed bar at the
/// bottom, so a choice is always on screen and never clipped.
struct PrivacyChoiceView: View {
    let onChoose: (AnalyticsChoice) -> Void

    /// Fits small displays: never taller than the visible screen.
    private var windowHeight: CGFloat {
        min(740, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    LocalPromiseBanner()

                    Text("Optionally, choose what else you're happy to share:")
                        .font(.callout.weight(.medium))

                    HStack(alignment: .top, spacing: 14) {
                        card(
                            title: "Share analytics", items: PrivacyText.sharedItems,
                            detail: "Used to understand how the app is used and to give support.")
                        card(
                            title: "Don't share analytics", items: PrivacyText.minimalItems,
                            detail: "Enough to check updates and your license.")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Text(PrivacyText.footer)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = BackendConfig.privacyPolicyURL {
                        Link("Read the privacy policy", destination: url).font(.caption)
                    }
                }
                .padding(24)
            }

            Divider()

            // Same order and equal weight as the cards above; neither is preselected.
            HStack(spacing: 14) {
                Button("Share Analytics") { onChoose(.shared) }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Don't Share") { onChoose(.notShared) }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 680, height: windowHeight)
        .tint(Brand.accent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Help improve eMail to Claude?").font(.title2.weight(.semibold))
                Text("The app checks for updates and your license about once a week. Choose what else, if anything, you're happy to share.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(title: String, items: [String], detail: String) -> some View {
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
