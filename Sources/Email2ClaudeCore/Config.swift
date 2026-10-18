import Foundation

public struct Route: Codable, Equatable {
    /// Full To address ("me@work.com") or a domain wildcard ("@acme.com").
    public var address: String
    /// Title of the chat as shown in Claude's sidebar.
    public var chatTitle: String?
    /// A claude.ai chat link or claude:// link. Preferred over the title when present.
    public var chatURL: String?

    public init(address: String, chatTitle: String? = nil, chatURL: String? = nil) {
        self.address = address
        self.chatTitle = chatTitle
        self.chatURL = chatURL
    }

    public var target: ChatTarget {
        if let link = chatURL, let url = ChatLink.appURL(from: link) { return .link(url) }
        if let title = chatTitle, !title.isEmpty { return .sidebar(title: title) }
        return .newChat
    }

    /// What the settings list shows in the "Chat" column.
    public var chatDescription: String {
        switch target {
        case .link(let url): return chatTitle.map { "\($0) (link)" } ?? url.absoluteString
        case .sidebar(let title): return title
        case .newChat: return "New chat each time"
        }
    }
}

public enum ChatTarget: Equatable {
    case link(URL)
    case sidebar(title: String)
    case newChat
}

public struct Config: Codable, Equatable {
    public var routes: [Route]
    /// Text placed above the email so Claude knows what to do with it.
    public var instruction: String
    public var autoSend: Bool
    /// Seconds to wait after opening a chat before pasting.
    public var openDelay: Double

    public init(
        routes: [Route] = [],
        instruction: String = "Below is an email I received. Read it, use any earlier context in this conversation, and respond to it.",
        autoSend: Bool = true,
        openDelay: Double = 1.5
    ) {
        self.routes = routes
        self.instruction = instruction
        self.autoSend = autoSend
        self.openDelay = openDelay
    }

    public init(from decoder: Decoder) throws {
        let d = Config()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? d.routes
        instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? d.instruction
        autoSend = try c.decodeIfPresent(Bool.self, forKey: .autoSend) ?? d.autoSend
        openDelay = try c.decodeIfPresent(Double.self, forKey: .openDelay) ?? d.openDelay
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

    /// Adds a route, replacing any existing one for the same address.
    public mutating func upsert(_ route: Route) {
        let key = route.address.trimmingCharacters(in: .whitespaces).lowercased()
        routes.removeAll { $0.address.trimmingCharacters(in: .whitespaces).lowercased() == key }
        routes.append(Route(address: key, chatTitle: route.chatTitle, chatURL: route.chatURL))
    }
}
