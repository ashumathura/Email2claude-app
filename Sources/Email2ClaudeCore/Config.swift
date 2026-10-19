import Foundation

public enum DestinationKind: String, Codable, CaseIterable, Identifiable {
    case chat, project, newChat, incognito

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat: return "Existing chat"
        case .project: return "New chat in a project"
        case .newChat: return "New chat"
        case .incognito: return "Incognito chat"
        }
    }
}

public enum ChatTarget: Equatable {
    case link(URL)
    case sidebar(title: String)
    case project(name: String, link: URL?)
    case newChat
    case incognito
}

public struct Route: Codable, Equatable, Identifiable {
    /// "company.com" (also matches subdomains) or a full address "jane@gmail.com" for one person.
    public var domain: String
    public var kind: DestinationKind
    /// Chat title (kind .chat) or project name (kind .project).
    public var name: String?
    /// A claude.ai or claude:// link to the chat or project. Preferred over the name when present.
    public var url: String?

    public var id: String { domain }

    public init(domain: String, kind: DestinationKind = .newChat, name: String? = nil, url: String? = nil) {
        self.domain = domain
        self.kind = kind
        self.name = name
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case domain, kind, name, url
        // Written by earlier versions, which routed on full addresses.
        case address, chatTitle, chatURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTitle = try c.decodeIfPresent(String.self, forKey: .chatTitle)
        let legacyURL = try c.decodeIfPresent(String.self, forKey: .chatURL)
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
            ?? c.decodeIfPresent(String.self, forKey: .address) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? legacyTitle
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? legacyURL
        kind = try c.decodeIfPresent(DestinationKind.self, forKey: .kind)
            ?? ((legacyTitle ?? legacyURL) != nil ? .chat : .newChat)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(domain, forKey: .domain)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(url, forKey: .url)
    }

    /// True when the rule names one address rather than a whole domain.
    public var isAddressRule: Bool { domain.contains("@") && !domain.hasPrefix("@") }

    public var target: ChatTarget {
        let link = url.flatMap { ChatLink.appURL(from: $0) }
        let label = name?.trimmingCharacters(in: .whitespaces) ?? ""
        switch kind {
        case .chat:
            if let link { return .link(link) }
            return label.isEmpty ? .newChat : .sidebar(title: label)
        case .project:
            return link == nil && label.isEmpty ? .newChat : .project(name: label, link: link)
        case .newChat: return .newChat
        case .incognito: return .incognito
        }
    }

    /// What the settings list shows under the domain.
    public var destinationDescription: String {
        let label = name?.trimmingCharacters(in: .whitespaces) ?? ""
        switch kind {
        case .chat: return label.isEmpty ? (url ?? "Existing chat") : label
        case .project: return "New chat in project: " + (label.isEmpty ? (url ?? "") : label)
        case .newChat: return "New chat each time"
        case .incognito: return "Incognito chat"
        }
    }
}

/// User overrides for one action slot. Nil fields mean "use the default".
public struct ActionSetting: Codable, Equatable {
    public var name: String?
    public var mode: ActionMode?
    public var prompt: String?

    public init(name: String? = nil, mode: ActionMode? = nil, prompt: String? = nil) {
        self.name = name
        self.mode = mode
        self.prompt = prompt
    }

    var isEmpty: Bool { name == nil && mode == nil && prompt == nil }
}

public struct Config: Codable, Equatable {
    public var routes: [Route]
    /// Per-action overrides, keyed by `Action.rawValue`.
    public var actions: [String: ActionSetting]
    /// Submit automatically after pasting, for actions that add a prompt.
    public var autoSend: Bool
    /// When no route matches: ask where to send it (true) or always start a new chat (false).
    public var askForUnknownRoutes: Bool
    /// Keep a local log of every email sent to Claude.
    public var keepActivityLog: Bool
    /// Minimum seconds to let Claude load a chat before pasting.
    public var openDelay: Double

    public init(
        routes: [Route] = [],
        actions: [String: ActionSetting] = [:],
        autoSend: Bool = true,
        askForUnknownRoutes: Bool = true,
        keepActivityLog: Bool = true,
        openDelay: Double = 1.0
    ) {
        self.routes = routes
        self.actions = actions
        self.autoSend = autoSend
        self.askForUnknownRoutes = askForUnknownRoutes
        self.keepActivityLog = keepActivityLog
        self.openDelay = openDelay
    }

    private enum CodingKeys: String, CodingKey {
        case routes, actions, autoSend, askForUnknownRoutes, keepActivityLog, openDelay
        // Written by earlier versions: one reply prompt, then a prompt per action.
        case instruction, instructions
    }

    public init(from decoder: Decoder) throws {
        let d = Config()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? d.routes
        actions = try c.decodeIfPresent([String: ActionSetting].self, forKey: .actions) ?? d.actions
        autoSend = try c.decodeIfPresent(Bool.self, forKey: .autoSend) ?? d.autoSend
        askForUnknownRoutes = try c.decodeIfPresent(Bool.self, forKey: .askForUnknownRoutes) ?? d.askForUnknownRoutes
        keepActivityLog = try c.decodeIfPresent(Bool.self, forKey: .keepActivityLog) ?? d.keepActivityLog
        openDelay = try c.decodeIfPresent(Double.self, forKey: .openDelay) ?? d.openDelay
        var legacy = try c.decodeIfPresent([String: String].self, forKey: .instructions) ?? [:]
        if let single = try c.decodeIfPresent(String.self, forKey: .instruction), legacy[Action.reply.rawValue] == nil {
            legacy[Action.reply.rawValue] = single
        }
        for (key, prompt) in legacy where actions[key]?.prompt == nil {
            var setting = actions[key] ?? ActionSetting()
            setting.prompt = prompt
            actions[key] = setting
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(routes, forKey: .routes)
        try c.encode(actions, forKey: .actions)
        try c.encode(autoSend, forKey: .autoSend)
        try c.encode(askForUnknownRoutes, forKey: .askForUnknownRoutes)
        try c.encode(keepActivityLog, forKey: .keepActivityLog)
        try c.encode(openDelay, forKey: .openDelay)
    }

    // MARK: Actions

    public func name(for action: Action) -> String { actions[action.rawValue]?.name ?? action.defaultName }
    public func mode(for action: Action) -> ActionMode { actions[action.rawValue]?.mode ?? action.defaultMode }
    public func instruction(for action: Action) -> String { actions[action.rawValue]?.prompt ?? action.defaultInstruction }

    /// An action appears in the menu once it has a name, and a prompt if it uses one.
    public func isConfigured(_ action: Action) -> Bool {
        let named = !name(for: action).trimmingCharacters(in: .whitespaces).isEmpty
        let hasPrompt = !instruction(for: action).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return named && (mode(for: action) == .pasteOnly || hasPrompt)
    }

    public mutating func setName(_ name: String, for action: Action) {
        update(action) { $0.name = name == action.defaultName ? nil : name }
    }

    public mutating func setMode(_ mode: ActionMode, for action: Action) {
        update(action) { $0.mode = mode == action.defaultMode ? nil : mode }
    }

    public mutating func setInstruction(_ text: String, for action: Action) {
        update(action) { $0.prompt = text == action.defaultInstruction ? nil : text }
    }

    public mutating func resetAction(_ action: Action) { actions[action.rawValue] = nil }

    private mutating func update(_ action: Action, _ change: (inout ActionSetting) -> Void) {
        var setting = actions[action.rawValue] ?? ActionSetting()
        change(&setting)
        actions[action.rawValue] = setting.isEmpty ? nil : setting
    }

    public static func load(from url: URL) -> Config {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }
        return config
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Adds a route, replacing any existing one for the same domain.
    public mutating func upsert(_ route: Route) {
        var route = route
        route.domain = Router.normalizeRule(route.domain)
        routes.removeAll { Router.normalizeRule($0.domain) == route.domain }
        routes.append(route)
    }
}
