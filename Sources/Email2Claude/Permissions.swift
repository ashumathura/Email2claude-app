import AppKit
import ApplicationServices

enum Permissions {
    /// Whether this app may control Mail. nil when it can't be told, for example because Mail isn't running.
    static func mailAutomation() -> Bool? {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
        guard let descriptor = target.aeDesc else { return nil }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false)
        if status == 0 { return true }
        if status == -1743 { return false }  // errAEEventNotPermitted
        return nil
    }
}
