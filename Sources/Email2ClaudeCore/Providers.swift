import Foundation

/// The chat service a route sends email to. Each one has its own addresses, features and timing.
public enum ChatProvider: String, Codable, CaseIterable, Identifiable {
    case claude, chatgpt, gemini

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    /// The Mac app, when the service has one. Gemini is web only. The ChatGPT identifier is unverified.
    public var desktopBundleID: String? {
        switch self {
        case .claude: return "com.anthropic.claudefordesktop"
        case .chatgpt: return "com.openai.chat"
        case .gemini: return nil
        }
    }

    public var hasDesktopApp: Bool { desktopBundleID != nil }

    public var newChatURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/new")!
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        }
    }

    /// A chat that isn't saved to history. Gemini has no address for it. Both addresses are unverified.
    public var incognitoURL: URL? {
        switch self {
        case .claude: return URL(string: "https://claude.ai/new?incognito")
        case .chatgpt: return URL(string: "https://chatgpt.com/?temporary-chat=true")
        case .gemini: return nil
        }
    }

    public var incognitoTitle: String { self == .chatgpt ? "Temporary chat" : "Incognito chat" }

    /// Gemini has no projects.
    public var supportedKinds: [DestinationKind] {
        self == .gemini ? [.chat, .newChat] : DestinationKind.allCases.filter { $0 != .incognito || incognitoURL != nil }
    }

    public func title(for kind: DestinationKind) -> String {
        kind == .incognito ? incognitoTitle : kind.title
    }

    public var chatLinkExample: String {
        switch self {
        case .claude: return "https://claude.ai/chat/…"
        case .chatgpt: return "https://chatgpt.com/c/…"
        case .gemini: return "https://gemini.google.com/app/…"
        }
    }

    public var projectLinkExample: String {
        switch self {
        case .claude: return "https://claude.ai/project/…"
        case .chatgpt: return "https://chatgpt.com/g/…/project"
        case .gemini: return ""
        }
    }

    /// Seconds to let a page of this service load in the browser before pasting. Web pages can't be
    /// inspected the way the Claude app can, so this is a fixed wait.
    public var webLoadDelay: Double { self == .gemini ? 4.0 : 3.0 }

    /// How this service's links start, for hints and error messages.
    public var linkHost: String {
        switch self {
        case .claude: return "claude.ai"
        case .chatgpt: return "chatgpt.com"
        case .gemini: return "gemini.google.com"
        }
    }

    /// True when `link` is an address of this service. Claude also accepts claude:// links.
    public func accepts(link: String) -> Bool {
        guard let url = ChatLink.appURL(from: link) else { return false }
        if self == .claude, url.scheme?.lowercased() == "claude" { return true }
        return ChatProvider.matching(url) == self
    }

    /// Which service a web address belongs to, if it is one of ours.
    public static func matching(_ url: URL) -> ChatProvider? {
        guard let host = url.host?.lowercased() else { return nil }
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("claude.ai") { return .claude }
        if on("chatgpt.com") || on("chat.openai.com") { return .chatgpt }
        if on("gemini.google.com") { return .gemini }
        return nil
    }
}
