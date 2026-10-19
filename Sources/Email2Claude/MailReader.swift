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
            to: list(4), cc: list(5), body: text(6), attachmentPaths: list(7), messageID: text(8))
    }

    /// Fetches recipients and attachment lists in single Apple Events instead of looping, and skips
    /// small inline images (signature logos, tracking pixels), which cost a save and a paste each.
    private static func script(saveDir: String) -> String {
        let dir = saveDir.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Mail"
            set sel to selection
            if (count of sel) is 0 then return {}
            set m to item 1 of sel
            set toList to address of every to recipient of m
            set ccList to address of every cc recipient of m
            set mid to ""
            try
                set mid to message id of m
            end try
            set savedPaths to {}
            set n to 0
            repeat with a in (every mail attachment of m)
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
            return {(sender of m), (subject of m), ((date received of m) as string), toList, ccList, (content of m), savedPaths, mid}
        end tell
        """
    }
}
