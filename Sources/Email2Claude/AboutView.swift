import AppKit
import SwiftUI

/// The About tab in Settings: why the app exists, how to support it, and how to get in touch.
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
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MailtoChat").font(.title3.weight(.semibold))
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
                .padding(.vertical, 4)
            } header: {
                Text("Why I built this")
            }

            DonateSection()

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Feel free to drop me a line with feedback, support questions or feature requests.")
                        .fixedSize(horizontal: false, vertical: true)
                    Link(Self.contactEmail, destination: URL(string: "mailto:\(Self.contactEmail)")!)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Get in touch")
            }
        }
        .formStyle(.grouped)
    }
}
