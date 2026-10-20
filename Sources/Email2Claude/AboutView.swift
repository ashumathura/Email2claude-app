import AppKit
import SwiftUI

/// The About tab in Settings: why the app exists, how to support it, and how to get help.
struct AboutTab: View {
    static let contactEmail = "ashu.mathura@gmail.com"

    static let story = [
        "I was getting frustrated pasting emails from different email accounts, by hand, into the right Claude projects and chats, just to get replies and summaries with the right context.",
        "I looked for ways to automate it and tried a few existing tools, but they weren't right for me, and they were expensive.",
        "So I decided to build my own. It worked out surprisingly well.",
        "I wanted to share it with the world, and with everyone who runs into the same challenge and wants to work smarter, not harder.",
    ]

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FormSection("Why I built this") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 16) {
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MailtoChat").font(.title2.weight(.bold))
                                    if !version.isEmpty {
                                        Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
                                    }
                                }
                                ForEach(Self.story, id: \.self) { paragraph in
                                    Text(paragraph).fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Ashu").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(18)
                }

                TitledGroup("Support the app") {
                    TipBox(.warning, symbol: "heart.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Donate.message).fixedSize(horizontal: false, vertical: true)
                            Text(Donate.linkLead).foregroundStyle(.secondary)
                            Link(Donate.url.absoluteString, destination: Donate.url)
                            Button("Donate on Revolut") { Donate.open() }
                                .buttonStyle(.borderedProminent)
                            Text(Donate.privacyNote).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                FormSection("Get help") {
                    FormRow("User manual", detail: "Each screen explained with pictures, plus troubleshooting.") {
                        Button("Open the user manual") { NSWorkspace.shared.open(BackendConfig.manualURL) }
                    }
                    RowDivider()
                    FormRow("Contact support", detail: "Something not working, or an idea to share? Write to \(Self.contactEmail).") {
                        Button("Send an email") {
                            if let url = URL(string: "mailto:\(Self.contactEmail)") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
