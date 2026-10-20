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

    // MARK: Matching

    /// The route that won for an email, and the address in the email that it matched.
    public struct RouteMatch: Equatable {
        public let route: Route
        public let address: String
    }

    /// The addresses a route looks at: the To recipients, or the sender.
    private static func candidates(of email: Email, for field: MatchField) -> [String] {
        switch field {
        case .to: return email.to.map(normalize)
        case .from: return [normalize(email.sender)].filter { $0.contains("@") }
        }
    }

    /// Finds the route for an email. A rule for a full address beats a domain rule, so one person at a
    /// shared domain (gmail.com) can be split out. Among rules of the same kind, the one higher in the
    /// list wins. A To rule looks at the To recipients; a From rule looks at the sender.
    public static func match(for email: Email, config: Config) -> RouteMatch? {
        for wantAddressRules in [true, false] {
            for route in config.routes where route.isAddressRule == wantAddressRules {
                if let hit = candidates(of: email, for: route.matchOn).first(where: { matches(rule: route.domain, address: $0) }) {
                    return RouteMatch(route: route, address: hit)
                }
            }
        }
        return nil
    }

    public static func route(for email: Email, config: Config) -> Route? {
        match(for: email, config: config)?.route
    }

    /// True when two domain rules on the same field can match the same address, as acme.com and
    /// mail.acme.com do. The one higher in the list wins. Full-address rules beat domain rules on
    /// purpose, so a domain rule and an address rule are not an overlap.
    public static func overlaps(_ a: Route, _ b: Route) -> Bool {
        guard a.id != b.id, a.matchOn == b.matchOn, !a.isAddressRule, !b.isAddressRule else { return false }
        let x = normalizeRule(a.domain), y = normalizeRule(b.domain)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.hasSuffix("." + y) || y.hasSuffix("." + x)
    }

    // MARK: Unknown senders

    /// What to offer when no route matches: the sender for mail the user received, the first
    /// recipient for mail the user sent.
    public struct RouteSuggestion: Equatable {
        public var field: MatchField
        public var fromAddress: String?
        public var toAddress: String?

        public func address(for field: MatchField) -> String? {
            field == .from ? fromAddress : toAddress
        }
    }

    public static func suggestion(for email: Email, config: Config) -> RouteSuggestion? {
        guard match(for: email, config: config) == nil else { return nil }
        let from = candidates(of: email, for: .from).first
        let to = candidates(of: email, for: .to).first
        guard from != nil || to != nil else { return nil }

        // Mail that the user sent has one of the account's own addresses as sender. If that can't
        // be told, keep the long-standing default of looking at who it was sent to.
        let own = Set(email.accountAddresses.map(normalize))
        var field: MatchField = own.isEmpty || from.map(own.contains) == true ? .to : .from
        if field == .to && to == nil { field = .from }
        if field == .from && from == nil { field = .to }
        return RouteSuggestion(field: field, fromAddress: from, toAddress: to)
    }
}

/// Puts a route's prompt into the action's prompt.
public enum PromptBuilder {
    /// The action's prompt, then the route's instructions, introduced by a label. Routes without
    /// instructions leave the prompt exactly as it was.
    public static func compose(actionPrompt: String, routeInstructions: String?) -> String {
        let extra = routeInstructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !extra.isEmpty else { return actionPrompt }
        let block = "Route prompt (applies to this sender or domain):\n" + extra
        let action = actionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return action.isEmpty ? block : action + "\n\n" + block
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
