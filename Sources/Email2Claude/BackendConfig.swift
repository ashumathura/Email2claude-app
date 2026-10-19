import Foundation

enum BackendConfig {
    /// The Supabase Edge Function that records check-ins, checks licenses and hands out updates.
    /// It needs no credentials; nothing secret is shipped in the app.
    static let checkinURL = URL(string: "https://yomgyukfzlnjxcvdsivw.supabase.co/functions/v1/checkin")!

    /// Where the privacy policy is published. Windows show a link once this is set.
    static let privacyPolicyURL: URL? = nil

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// False when run from `swift run` rather than the packaged app, so development runs
    /// don't show up in the usage data or offer to replace themselves.
    static var isPackagedApp: Bool { Bundle.main.bundleIdentifier != nil }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
