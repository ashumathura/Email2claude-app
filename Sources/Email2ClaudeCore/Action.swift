import Foundation

/// What happens to the email once it reaches the Claude chat.
public enum ActionMode: String, Codable, CaseIterable, Identifiable {
    case pasteOnly, prompt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pasteOnly: return "Paste the email only"
        case .prompt: return "Add a prompt to the email"
        }
    }
}

/// The slots shown in the menu and bound to ⌥⌘ shortcuts. The name, mode and prompt of each
/// slot are editable (see `Config`); the values here are the defaults.
public enum Action: String, Codable, CaseIterable, Identifiable {
    case reply, summary, research, custom1, custom2, pasteOnly

    public var id: String { rawValue }

    public var defaultName: String {
        switch self {
        case .reply: return "Draft a Reply"
        case .summary: return "Summary & Next Steps"
        case .research: return "Deep Dive & Research"
        case .custom1, .custom2: return ""
        case .pasteOnly: return "Paste Only"
        }
    }

    /// Shown in empty name fields, so unset custom slots are recognisable.
    public var placeholderName: String {
        switch self {
        case .custom1: return "Custom action 1"
        case .custom2: return "Custom action 2"
        default: return defaultName
        }
    }

    public var defaultMode: ActionMode { self == .pasteOnly ? .pasteOnly : .prompt }

    /// Pressed together with ⌥⌘.
    public var keyEquivalent: String {
        switch self {
        case .reply: return "r"
        case .summary: return "s"
        case .research: return "d"
        case .custom1: return "1"
        case .custom2: return "2"
        case .pasteOnly: return "c"
        }
    }

    public var shortcutLabel: String { "⌥⌘" + keyEquivalent.uppercased() }

    public var defaultInstruction: String {
        switch self {
        case .reply:
            return "Below is an email I received. Using everything you know from earlier in this conversation, draft a reply I can send. Match the tone of the thread, answer every question that was asked, and keep it concise. Give me the draft, plus a short note only if you had to assume something."
        case .summary:
            return "Below is an email thread. Please give me: 1) a short summary, 2) the action items (who, what, and by when if stated), and 3) proposed next steps. Use earlier context from this conversation where it helps."
        case .research:
            return "Below is an email thread. Please give me a short summary and the action items, then research the topics, people and organisations involved (use web search) so I have more context to work with. List your sources and flag anything you could not verify. Finish with proposed next steps."
        case .custom1, .custom2, .pasteOnly:
            return ""
        }
    }
}
