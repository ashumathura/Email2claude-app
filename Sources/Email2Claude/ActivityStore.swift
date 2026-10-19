import AppKit
import Email2ClaudeCore

/// The activity log shown in Settings. Entries live in a file on this Mac and nowhere else.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var entries: [ActivityEntry]

    let url: URL

    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Email2Claude/activity.jsonl")
        entries = ActivityFile.load(from: url).sorted { $0.date > $1.date }
    }

    func append(_ entry: ActivityEntry) {
        try? ActivityFile.append(entry, to: url)
        entries.insert(entry, at: 0)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
        entries = []
    }

    func revealInFinder() {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
