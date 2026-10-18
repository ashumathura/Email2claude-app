import Foundation

/// What the user wants Claude to do with the email.
public enum Action: String, Codable, CaseIterable, Identifiable {
    case reply, summary, research, pasteOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reply: return "Draft a Reply"
        case .summary: return "Summary & Next Steps"
        case .research: return "Deep Dive & Research"
        case .pasteOnly: return "Paste Only"
        }
    }

    public var detail: String {
        switch self {
        case .reply: return "Claude drafts a reply to the email thread."
        case .summary: return "Summary, action items and proposed next steps."
        case .research: return "Summary and action items, plus research on the topic for extra context."
        case .pasteOnly: return "Pastes the email and stops, so you can add your own request before sending."
        }
    }

    /// Pressed together with ⌥⌘.
    public var keyEquivalent: String {
        switch self {
        case .reply: return "r"
        case .summary: return "s"
        case .research: return "d"
        case .pasteOnly: return "c"
        }
    }

    public var shortcutLabel: String { "⌥⌘" + keyEquivalent.uppercased() }

    /// Paste Only never submits; the others submit when auto-send is on.
    public var sendsAutomatically: Bool { self != .pasteOnly }

    public var defaultInstruction: String {
        switch self {
        case .reply:
            return "Below is an email I received. Using everything you know from earlier in this conversation, draft a reply I can send. Match the tone of the thread, answer every question that was asked, and keep it concise. Give me the draft, plus a short note only if you had to assume something."
        case .summary:
            return "Below is an email thread. Please give me: 1) a short summary, 2) the action items (who, what, and by when if stated), and 3) proposed next steps. Use earlier context from this conversation where it helps."
        case .research:
            return "Below is an email thread. Please give me a short summary and the action items, then research the topics, people and organisations involved (use web search) so I have more context to work with. List your sources and flag anything you could not verify. Finish with proposed next steps."
        case .pasteOnly:
            return ""
        }
    }
}
