import Foundation

/// A random ID that tells one install from another. Kept in Application Support rather than the
/// Keychain, so updates to a differently signed build never trigger a Keychain prompt.
enum DeviceID {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Email2Claude/device-id")
    }

    static func current() -> String {
        if let saved = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: trimmed) != nil { return trimmed.lowercased() }
        }
        let new = UUID().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? new.write(to: url, atomically: true, encoding: .utf8)
        return new
    }

    /// Forget this ID, so the next check-in starts a fresh, unrelated record.
    static func reset() { try? FileManager.default.removeItem(at: url) }
}
