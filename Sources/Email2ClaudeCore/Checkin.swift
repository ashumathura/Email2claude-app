import Foundation

/// What the user agreed to share. `unset` until the first-run question has been answered.
public enum AnalyticsChoice: String, Codable, CaseIterable, Identifiable {
    case unset, shared, notShared

    public var id: String { rawValue }
}

/// Orders dotted version numbers: "0.10.0" > "0.9.2".
public enum AppVersion {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

/// The body sent to the `checkin` function. Encode with `Checkin.encoder`.
public struct CheckinRequest: Codable, Equatable {
    public enum Event: String, Codable { case open, updateCheck = "update_check", consentChange = "consent_change" }

    public var deviceId: String
    public var event: Event
    /// "erase" deletes everything stored for this device.
    public var action: String?
    public var analytics: Bool
    public var wantsUpdate: Bool
    public var appVersion: String
    public var macosVersion: String
    public var osLanguage: String
    public var licenseKey: String

    public init(
        deviceId: String, event: Event, action: String? = nil, analytics: Bool, wantsUpdate: Bool,
        appVersion: String, macosVersion: String, osLanguage: String, licenseKey: String
    ) {
        self.deviceId = deviceId
        self.event = event
        self.action = action
        self.analytics = analytics
        self.wantsUpdate = wantsUpdate
        self.appVersion = appVersion
        self.macosVersion = macosVersion
        self.osLanguage = osLanguage
        self.licenseKey = licenseKey
    }
}

public struct UpdateInfo: Codable, Equatable {
    public var version: String
    public var notes: String?
    public var sha256: String
    public var minMacos: String?
    /// A short-lived signed download link, only present when the license passed.
    public var url: URL
}

public struct BlockedUpdate: Codable, Equatable {
    public var version: String
    /// Why the download was withheld: missing, invalid, revoked or expired.
    public var reason: String
}

public struct CheckinResponse: Codable, Equatable {
    public var license: String?
    public var latestVersion: String?
    public var update: UpdateInfo?
    public var updateBlocked: BlockedUpdate?
}

public enum Checkin {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// "13.2.1" style strings: is `current` at least `minimum`?
    public static func meetsMinimum(system current: String, minimum: String?) -> Bool {
        guard let minimum, !minimum.isEmpty else { return true }
        return AppVersion.compare(current, minimum) != .orderedAscending
    }

    /// A readable explanation for a withheld update.
    public static func explain(licenseStatus reason: String) -> String {
        switch reason {
        case "missing": return "no license key has been entered"
        case "expired": return "the license has expired"
        case "revoked": return "the license is no longer active"
        default: return "the license key isn't valid"
        }
    }
}
