import Foundation

/// What is known about one selected message before any of them is read in full.
public struct SelectedMessage: Equatable {
    public var sender: String
    public var subject: String
    public var date: Date?
    /// The addresses it was sent to.
    public var recipients: [String]

    public init(sender: String, subject: String, date: Date? = nil, recipients: [String] = []) {
        self.sender = sender
        self.subject = subject
        self.date = date
        self.recipients = recipients
    }
}

/// Which selected message is read, and which messages the attachments come from.
public struct ThreadPlan: Equatable {
    /// Zero-based index of the message that is read and sent.
    public var primary: Int
    /// Zero-based indices of the messages whose attachments are included.
    public var attachmentSources: [Int]
    /// The selection is one conversation (several messages, one thread).
    public var isThread: Bool
}

/// Mail shows a conversation as one stack, but selecting the stack selects every message in it. The
/// messages count as one email when they share a subject (ignoring Re:, Fwd: and the like) and are
/// connected through the people on them. Senders can differ within a thread, so they are not compared.
public enum MailThread {
    static let maxMessages = 30

    /// The subject without reply and forward prefixes, in lower case, with single spaces.
    public static func normalizedSubject(_ subject: String) -> String {
        var text = subject
        let prefix = try! NSRegularExpression(
            pattern: #"^\s*(?:re|fw|fwd|aw|wg|sv|vs|antw|tr|rv|enc)(?:\[\d+\])?\s*:\s*"#, options: [.caseInsensitive])
        while true {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = prefix.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { break }
            text.removeSubrange(swiftRange)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// `ownAddresses` (the user's own, which are on almost every message) are left out of the comparison.
    public static func plan(for messages: [SelectedMessage], ownAddresses: [String] = []) -> ThreadPlan {
        let first = ThreadPlan(primary: 0, attachmentSources: [0], isThread: false)
        guard messages.count > 1 else { return first }
        let considered = Array(messages.prefix(maxMessages))

        let subject = normalizedSubject(considered[0].subject)
        guard !subject.isEmpty, considered.allSatisfy({ normalizedSubject($0.subject) == subject }) else { return first }

        let own = Set(ownAddresses.map(Router.normalize))
        let people = considered.map { message in
            Set(([message.sender] + message.recipients).map(Router.normalize)).subtracting(own).subtracting([""])
        }
        // Every message must be reachable from the first through shared people.
        var reached: Set<Int> = [0]
        var queue = [0]
        while let current = queue.popLast() {
            for other in people.indices where !reached.contains(other) && !people[current].isDisjoint(with: people[other]) {
                reached.insert(other)
                queue.append(other)
            }
        }
        guard reached.count == considered.count else { return first }

        // The newest by date; without dates, or on a tie, the earlier one in the list.
        var newest = 0
        for index in considered.indices.dropFirst() {
            if let date = considered[index].date, date > (considered[newest].date ?? .distantPast) { newest = index }
        }
        return ThreadPlan(primary: newest, attachmentSources: Array(considered.indices), isThread: true)
    }
}
