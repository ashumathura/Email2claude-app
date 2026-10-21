import AppKit
import Email2ClaudeCore

enum MailError: LocalizedError {
    case notRunning
    case noSelection
    case script(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Mail is not running."
        case .noSelection: return "No email is selected in Mail."
        case .script(let message): return "Mail scripting failed: \(message)"
        }
    }
}

/// Reads the selected message from Mail.app over Apple Events.
/// The first run triggers the system's Automation permission prompt.
enum MailReader {
    private static let folderPrefix = "Email2Claude-"

    /// Removes attachment folders left behind by a crash or quit, once they are an hour old.
    static func sweepOldAttachmentFolders() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-3600)
        let folders = (try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in folders where folder.lastPathComponent.hasPrefix(folderPrefix) {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (modified ?? .distantPast) < cutoff { try? fm.removeItem(at: folder) }
        }
    }

    static func readSelectedEmail() throws -> Email {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first != nil
        else { throw MailError.notRunning }

        // First look at who and what is selected, so a conversation (Mail's stack of messages) can be
        // told from several different emails.
        let overview = try run(overviewScript)
        guard overview.numberOfItems >= 3, let items = overview.atIndex(2), items.numberOfItems > 0
        else { throw MailError.noSelection }
        let selected = Int(overview.atIndex(1)?.int32Value ?? 1)
        let messages: [SelectedMessage] = (1...items.numberOfItems).compactMap { index in
            guard let item = items.atIndex(index) else { return nil }
            let recipients: [String] = {
                guard let list = item.atIndex(4), list.numberOfItems > 0 else { return [] }
                return (1...list.numberOfItems).compactMap { list.atIndex($0)?.stringValue }
            }()
            return SelectedMessage(
                sender: item.atIndex(1)?.stringValue ?? "", subject: item.atIndex(2)?.stringValue ?? "",
                date: item.atIndex(3)?.dateValue, recipients: recipients)
        }
        var ownAddresses: [String] = []
        if let list = overview.atIndex(3), list.numberOfItems > 0 {
            ownAddresses = (1...list.numberOfItems).compactMap { list.atIndex($0)?.stringValue }
        }
        let plan = MailThread.plan(for: messages, ownAddresses: ownAddresses)

        // Attachments are saved here for the paste, readable by this user only, then removed.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(folderPrefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let result: NSAppleEventDescriptor
        do {
            result = try run(script(saveDir: dir.path, primary: plan.primary + 1, attachmentSources: plan.attachmentSources.map { $0 + 1 }))
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        guard result.numberOfItems >= 7 else {
            try? FileManager.default.removeItem(at: dir)
            throw MailError.noSelection
        }

        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        func list(_ i: Int) -> [String] {
            guard let d = result.atIndex(i), d.numberOfItems > 0 else { return [] }
            return (1...d.numberOfItems).compactMap { d.atIndex($0)?.stringValue }
        }
        return Email(
            sender: text(1), subject: text(2), date: text(3),
            to: list(4), cc: list(5), body: text(6), attachmentPaths: list(7), messageID: text(8),
            attachmentFolder: dir, accountAddresses: list(9),
            selectionCount: plan.isThread ? 1 : selected,
            threadSize: plan.isThread ? messages.count : 1)
    }

    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var errorInfo: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) else {
            let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw MailError.script(message)
        }
        return result
    }

    /// The count of selected messages, then for each (up to 30) its sender, subject, date and recipients, then
    /// the addresses of the account the first one is in.
    private static let overviewScript = """
        tell application "Mail"
            set sel to selection
            set total to count of sel
            if total is 0 then return {}
            set shown to total
            if shown > 30 then set shown to 30
            set infos to {}
            repeat with i from 1 to shown
                set m to item i of sel
                set recips to {}
                try
                    set recips to address of every to recipient of m
                end try
                set end of infos to {(sender of m), (subject of m), (date received of m), recips}
            end repeat
            set acctAddrs to {}
            try
                set acctAddrs to email addresses of (account of mailbox of (item 1 of sel))
            end try
            return {total, infos, acctAddrs}
        end tell
        """

    /// Reads message number `primary` of the selection, and saves the attachments of the messages in
    /// `attachmentSources`, skipping small inline images (signature logos, tracking pixels), which cost
    /// a save and a paste each. Recipients and attachment lists come in single Apple Events, not loops.
    private static func script(saveDir: String, primary: Int, attachmentSources: [Int]) -> String {
        let dir = saveDir.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let sources = attachmentSources.map(String.init).joined(separator: ", ")
        return """
        tell application "Mail"
            set sel to selection
            if (count of sel) is 0 then return {}
            set m to item \(primary) of sel
            set toList to address of every to recipient of m
            set ccList to address of every cc recipient of m
            set mid to ""
            try
                set mid to message id of m
            end try
            set acctAddrs to {}
            try
                set acctAddrs to email addresses of (account of mailbox of m)
            end try
            set savedPaths to {}
            set n to 0
            repeat with idx in {\(sources)}
                set srcMsg to item (contents of idx) of sel
                repeat with a in (every mail attachment of srcMsg)
                    try
                        set tinyImage to false
                        try
                            if (MIME type of a) starts with "image/" and (file size of a) < 15000 then set tinyImage to true
                        end try
                        if not tinyImage then
                            set n to n + 1
                            set p to "\(dir)/" & n & "-" & (name of a)
                            save a in (POSIX file p)
                            set end of savedPaths to p
                        end if
                    end try
                end repeat
            end repeat
            return {(sender of m), (subject of m), ((date received of m) as string), toList, ccList, (content of m), savedPaths, mid, acctAddrs}
        end tell
        """
    }
}
