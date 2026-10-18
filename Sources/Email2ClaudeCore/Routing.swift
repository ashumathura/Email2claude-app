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

    /// Lowercases a rule and drops a leading "@" so "@Acme.com" and "acme.com" are the same rule.
    public static func normalizeRule(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("@") { s.removeFirst() }
        return s
    }

    public static func domain(of address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let domain = String(address[address.index(after: at)...])
        return domain.isEmpty ? nil : domain
    }

    static func matches(rule: String, address: String) -> Bool {
        let rule = normalizeRule(rule)
        guard !rule.isEmpty else { return false }
        if rule.contains("@") { return rule == address }
        guard let domain = domain(of: address) else { return false }
        return domain == rule || domain.hasSuffix("." + rule)
    }

    /// The route for this email. Looks only at the To recipients, in order; a rule for a full
    /// address beats a domain rule, so one person at a shared domain (gmail.com) can be split out.
    public static func route(for email: Email, config: Config) -> Route? {
        let addresses = email.to.map(normalize)
        for address in addresses {
            if let route = config.routes.first(where: { $0.isAddressRule && matches(rule: $0.domain, address: address) }) {
                return route
            }
        }
        for address in addresses {
            if let route = config.routes.first(where: { matches(rule: $0.domain, address: address) }) {
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
    /// Opens a fresh incognito chat. Unverified: depends on the desktop app honouring ?incognito.
    public static let incognitoURL = URL(string: "claude://claude.ai/new?incognito")!

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
