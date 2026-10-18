import SwiftUI
import Email2ClaudeCore

extension DestinationKind {
    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .project: return "folder"
        case .newChat: return "square.and.pencil"
        case .incognito: return "eye.slash"
        }
    }

    var summary: String {
        switch self {
        case .chat: return "Every email goes into one conversation, so Claude builds up context over time."
        case .project: return "Each email starts a new chat inside the project, which shares the project's knowledge."
        case .newChat: return "Each email starts a fresh chat."
        case .incognito: return "Each email starts a private chat that isn't saved to your history."
        }
    }
}

/// Maps a recipient domain to a Claude destination. Used from Settings and from the prompt that
/// appears when an email goes to a domain without a route.
struct RouteEditorView: View {
    let title: String
    let subtitle: String
    let offersOnce: Bool
    let loadChats: () -> [String]
    let onSave: (Route) -> Void
    let onOnce: ((Route) -> Void)?
    let onCancel: () -> Void

    @State private var domain: String
    @State private var kind: DestinationKind
    @State private var name: String
    @State private var url: String
    @State private var chats: [String]

    init(
        title: String, subtitle: String, initial: Route, offersOnce: Bool,
        loadChats: @escaping () -> [String],
        onSave: @escaping (Route) -> Void, onOnce: ((Route) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.offersOnce = offersOnce
        self.loadChats = loadChats
        self.onSave = onSave
        self.onOnce = onOnce
        self.onCancel = onCancel
        _domain = State(initialValue: initial.domain)
        _kind = State(initialValue: initial.kind)
        _name = State(initialValue: initial.name ?? "")
        _url = State(initialValue: initial.url ?? "")
        _chats = State(initialValue: loadChats())
    }

    private var draft: Route {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let usesDetails = kind == .chat || kind == .project
        return Route(
            domain: Router.normalizeRule(domain), kind: kind,
            name: usesDetails && !trimmedName.isEmpty ? trimmedName : nil,
            url: usesDetails && !trimmedURL.isEmpty ? trimmedURL : nil)
    }

    private var linkIsValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || ChatLink.appURL(from: trimmed) != nil
    }

    private var isValid: Bool {
        guard !draft.domain.isEmpty, linkIsValid else { return false }
        switch kind {
        case .chat, .project: return draft.name != nil || draft.url != nil
        case .newChat, .incognito: return true
        }
    }

    private var chatChoices: [String] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || chats.contains(trimmed) ? chats : [trimmed] + chats
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    TextField("Domain", text: $domain, prompt: Text("company.com"))
                } header: {
                    Text("When an email is addressed to")
                } footer: {
                    Text("Matches everyone at this domain, so mail to you or to a colleague goes to the same place. Enter a full address to match one person only.")
                }

                Section {
                    Picker("Send to", selection: $kind) {
                        ForEach(DestinationKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    details
                } header: {
                    Text("Claude destination")
                } footer: {
                    Text(kind.summary)
                }
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: 520, height: 540)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var details: some View {
        switch kind {
        case .chat:
            Picker("Chat", selection: $name) {
                Text(chatChoices.isEmpty ? "No chats found" : "Choose a chat…").tag("")
                ForEach(chatChoices, id: \.self) { Text($0).tag($0) }
            }
            Button("Refresh Chat List") { chats = loadChats() }
                .buttonStyle(.link)
            linkField(placeholder: "https://claude.ai/chat/…", label: "Chat link")
        case .project:
            TextField("Project name", text: $name, prompt: Text("Exactly as shown in Claude"))
            linkField(placeholder: "https://claude.ai/project/…", label: "Project link")
        case .newChat, .incognito:
            EmptyView()
        }
    }

    private func linkField(placeholder: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: $url, prompt: Text(placeholder + " (optional)"))
            if !linkIsValid {
                Text("That doesn't look like a claude.ai link.").font(.caption).foregroundStyle(.red)
            } else if url.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("A link is the most reliable way to find it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            if offersOnce, let onOnce {
                Button("Just This Once") { onOnce(draft) }.disabled(!isValid)
            }
            Button("Save") { onSave(draft) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
