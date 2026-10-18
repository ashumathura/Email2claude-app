import Foundation

public struct Route: Codable, Equatable {
    /// Full address ("me@work.com") or a domain wildcard ("@acme.com").
    public var address: String
    /// A claude.ai chat link or a claude:// link.
    public var chatURL: String

    public init(address: String, chatURL: String) {
        self.address = address
        self.chatURL = chatURL
    }
}

public struct Config: Codable, Equatable {
    public var routes: [Route]
    /// Used when no route matches. nil means "start a new chat".
    public var defaultChatURL: String?
    /// Text placed above the email so Claude knows what to do with it.
    public var instruction: String
    public var autoSend: Bool
    /// Seconds to wait after opening a chat before pasting.
    public var openDelay: Double

    public init(
        routes: [Route] = [],
        defaultChatURL: String? = nil,
        instruction: String = "Below is an email I received. Read it, use any earlier context in this conversation, and respond to it.",
        autoSend: Bool = true,
        openDelay: Double = 1.5
    ) {
        self.routes = routes
        self.defaultChatURL = defaultChatURL
        self.instruction = instruction
        self.autoSend = autoSend
        self.openDelay = openDelay
    }

    public init(from decoder: Decoder) throws {
        let d = Config()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? d.routes
        defaultChatURL = try c.decodeIfPresent(String.self, forKey: .defaultChatURL)
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
}
