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
    static func readSelectedEmail() throws -> Email {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first != nil
        else { throw MailError.notRunning }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Email2Claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let source = script(saveDir: dir.path)
        var errorInfo: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) else {
            let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw MailError.script(message)
        }
        guard result.numberOfItems >= 7 else { throw MailError.noSelection }

        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        func list(_ i: Int) -> [String] {
            guard let d = result.atIndex(i), d.numberOfItems > 0 else { return [] }
            return (1...d.numberOfItems).compactMap { d.atIndex($0)?.stringValue }
        }
        return Email(
            sender: text(1), subject: text(2), date: text(3),
            to: list(4), cc: list(5), body: text(6), attachmentPaths: list(7))
    }

    private static func script(saveDir: String) -> String {
        let dir = saveDir.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Mail"
            set sel to selection
            if (count of sel) is 0 then return {}
            set m to item 1 of sel
            set toList to {}
            repeat with r in (to recipients of m)
                set end of toList to (address of r)
            end repeat
            set ccList to {}
            repeat with r in (cc recipients of m)
                set end of ccList to (address of r)
            end repeat
            set savedPaths to {}
            set n to 0
            repeat with a in (mail attachments of m)
                try
                    set n to n + 1
                    set p to "\(dir)/" & n & "-" & (name of a)
                    save a in (POSIX file p)
                    set end of savedPaths to p
                end try
            end repeat
            return {(sender of m), (subject of m), ((date received of m) as string), toList, ccList, (content of m), savedPaths}
        end tell
        """
    }
}
