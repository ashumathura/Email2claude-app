import Foundation

public struct Email: Equatable {
    public var sender: String
    public var subject: String
    public var date: String
    public var to: [String]
    public var cc: [String]
    public var body: String
    /// Absolute paths of attachments already saved to disk.
    public var attachmentPaths: [String]

    public init(
        sender: String, subject: String, date: String,
        to: [String], cc: [String], body: String, attachmentPaths: [String]
    ) {
        self.sender = sender
        self.subject = subject
        self.date = date
        self.to = to
        self.cc = cc
        self.body = body
        self.attachmentPaths = attachmentPaths
    }

    /// The text pasted into Claude.
    public func prompt(instruction: String) -> String {
        var lines: [String] = []
        if !instruction.isEmpty { lines += [instruction, ""] }
        lines.append("From: \(sender)")
        lines.append("To: \(to.joined(separator: ", "))")
        if !cc.isEmpty { lines.append("Cc: \(cc.joined(separator: ", "))") }
        lines.append("Date: \(date)")
        lines.append("Subject: \(subject)")
        lines += ["", body]
        if !attachmentPaths.isEmpty {
            let names = attachmentPaths.map { ($0 as NSString).lastPathComponent }
            lines += ["", "Attachments: \(names.joined(separator: ", "))"]
        }
        return lines.joined(separator: "\n")
    }
}
