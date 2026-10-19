import Foundation

/// Builds links that open a specific message in Apple Mail.
public enum MailLink {
    public static func url(messageID: String) -> URL? {
        let id = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !id.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://%3C\(encoded)%3E")
    }
}

/// One email sent to Claude.
public struct ActivityEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var subject: String
    public var sender: String
    public var messageID: String
    /// The route rule that matched ("acme.com"), or empty when none did.
    public var rule: String
    /// Where the email went. `destination.target` is what to open to get back to it.
    public var destination: Route
    public var actionName: String
    public var mode: ActionMode
    /// The prompt placed above the email; empty for paste-only.
    public var prompt: String

    public init(
        id: UUID = UUID(), date: Date = Date(), subject: String, sender: String, messageID: String,
        rule: String, destination: Route, actionName: String, mode: ActionMode, prompt: String
    ) {
        self.id = id
        self.date = date
        self.subject = subject
        self.sender = sender
        self.messageID = messageID
        self.rule = rule
        self.destination = destination
        self.actionName = actionName
        self.mode = mode
        self.prompt = prompt
    }

    public var mailURL: URL? { MailLink.url(messageID: messageID) }

    public var routeText: String {
        rule.isEmpty
            ? "No route · \(destination.destinationDescription)"
            : "\(rule) → \(destination.destinationDescription)"
    }

    /// New and incognito chats have nothing to go back to.
    public var canOpenChat: Bool {
        switch destination.target {
        case .link, .sidebar, .project: return true
        case .newChat, .incognito: return false
        }
    }

    /// Every word of the query must appear somewhere in the entry.
    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = [
            ISO8601DateFormatter().string(from: date), subject, sender, routeText, actionName, prompt,
        ].joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// Reads and writes the activity log: one JSON object per line, kept on this Mac only.
public enum ActivityFile {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func append(_ entry: ActivityEntry, to url: URL) throws {
        var line = try encoder.encode(entry)
        line.append(0x0A)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    /// Entries in file order. Lines that don't decode are skipped.
    public static func load(from url: URL) -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(ActivityEntry.self, from: Data($0)) }
    }
}
