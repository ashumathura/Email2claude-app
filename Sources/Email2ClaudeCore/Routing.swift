import Foundation

public enum Router {
    /// Pulls the bare address out of "Name <a@b.com>" and lowercases it.
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = s.lastIndex(of: "<"), let close = s.lastIndex(of: ">"), open < close {
            s = String(s[s.index(after: open)..<close])
        }
        return s.lowercased()
    }

    static func matches(rule: String, address: String) -> Bool {
        let rule = rule.trimmingCharacters(in: .whitespaces).lowercased()
        if rule.hasPrefix("@") { return address.hasSuffix(rule) }
        return rule == address
    }

    /// The route matching one of the To recipients, if any.
    public static func route(for email: Email, config: Config) -> Route? {
        for raw in email.to {
            let address = normalize(raw)
            if let route = config.routes.first(where: { matches(rule: $0.address, address: address) }) {
                return route
            }
        }
        return nil
    }

    /// The first To address, when no route covers any To recipient. This is what the app asks about.
    public static func unknownAddress(for email: Email, config: Config) -> String? {
        guard route(for: email, config: config) == nil else { return nil }
        return email.to.first.map(normalize)
    }
}

public enum ChatLink {
    /// Converts https://claude.ai/chat/<id> into the desktop app's claude:// form.
    /// claude:// links pass through unchanged. Returns nil for anything else.
    public static func appURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed), let scheme = comps.scheme?.lowercased()
        else { return nil }
        switch scheme {
        case "claude":
            return comps.url
        case "https" where comps.host?.lowercased() == "claude.ai":
            comps.scheme = "claude"
            return comps.url
        default:
            return nil
        }
    }
}
