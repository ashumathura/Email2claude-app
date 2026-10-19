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

/// Maps who an email was sent to (a whole domain, or one address) onto a Claude destination.
/// Used from Settings and from the prompt shown when an email has no route yet.
struct RouteEditorView: View {
    enum MatchType: String, CaseIterable, Identifiable {
        case domain, address
        var id: String { rawValue }
    }

    let title: String
    let subtitle: String
    /// The address that triggered the prompt. Prefills the field when switching to "One email address".
    let suggestedAddress: String?
    let offersOnce: Bool
    let loadChats: () -> [String]
    let onSave: (Route) -> Void
    let onOnce: ((Route) -> Void)?
    let onNeverAsk: (() -> Void)?
    let onCancel: () -> Void

    @State private var matchType: MatchType
    @State private var matchText: String
    @State private var kind: DestinationKind
    @State private var name: String
    @State private var url: String
    @State private var chats: [String]
    @State private var neverAsk = false

    init(
        title: String, subtitle: String, initial: Route, suggestedAddress: String? = nil, offersOnce: Bool,
        loadChats: @escaping () -> [String],
        onSave: @escaping (Route) -> Void, onOnce: ((Route) -> Void)? = nil,
        onNeverAsk: (() -> Void)? = nil, onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.suggestedAddress = suggestedAddress
        self.offersOnce = offersOnce
        self.loadChats = loadChats
        self.onSave = onSave
        self.onOnce = onOnce
        self.onNeverAsk = onNeverAsk
        self.onCancel = onCancel
        _matchType = State(initialValue: initial.isAddressRule ? .address : .domain)
        _matchText = State(initialValue: Router.normalizeRule(initial.domain))
        _kind = State(initialValue: initial.kind)
        _name = State(initialValue: initial.name ?? "")
        _url = State(initialValue: initial.url ?? "")
        _chats = State(initialValue: loadChats())
    }

    // MARK: Derived values

    private var ruleValue: String { Router.normalizeRule(matchText) }

    private var ruleError: String? {
        let value = ruleValue
        guard !value.isEmpty else { return nil }
        if value.contains(" ") { return "Remove the spaces." }
        switch matchType {
        case .domain:
            return value.contains("@") ? "Enter just the domain, like company.com." : nil
        case .address:
            let parts = value.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
                ? nil : "Enter a full address, like name@company.com."
        }
    }

    private var draft: Route {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let usesDetails = kind == .chat || kind == .project
        return Route(
            domain: ruleValue, kind: kind,
            name: usesDetails && !trimmedName.isEmpty ? trimmedName : nil,
            url: usesDetails && !trimmedURL.isEmpty ? trimmedURL : nil)
    }

    private var linkIsValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || ChatLink.appURL(from: trimmed) != nil
    }

    private var isValid: Bool {
        guard !ruleValue.isEmpty, ruleError == nil, linkIsValid else { return false }
        switch kind {
        case .chat, .project: return draft.name != nil || draft.url != nil
        case .newChat, .incognito: return true
        }
    }

    private var chatChoices: [String] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || chats.contains(trimmed) ? chats : [trimmed] + chats
    }

    private var whoPhrase: String {
        switch matchType {
        case .domain: return "anyone at " + (ruleValue.isEmpty ? "company.com" : ruleValue)
        case .address: return ruleValue.isEmpty ? "name@company.com" : ruleValue
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    Picker("Match", selection: $matchType) {
                        Text("Anyone at a domain").tag(MatchType.domain)
                        Text("One email address").tag(MatchType.address)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField(
                        matchType == .domain ? "Domain" : "Email address", text: $matchText,
                        prompt: Text(matchType == .domain ? "company.com" : "name@company.com"))
                    if let ruleError {
                        Text(ruleError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("When an email is sent to…")
                } footer: {
                    Text(matchType == .domain
                         ? "Matches everyone at this domain, so mail to you or to any colleague goes to the same place. Subdomains match too."
                         : "Matches only this exact address. It takes priority over a domain route.")
                }
                .disabled(neverAsk)

                Section {
                    Picker("Send it to", selection: $kind) {
                        ForEach(DestinationKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    details
                } header: {
                    Text("…put it in Claude")
                } footer: {
                    Text(kind.summary)
                }
                .disabled(neverAsk)

                if !neverAsk {
                    Section {
                        Text("Emails sent to **\(whoPhrase)** go to: **\(draft.destinationDescription)**")
                    } header: {
                        Text("Result")
                    }
                }

                if offersOnce {
                    Section {
                        Toggle("Don't ask again. Always start a new chat when no route matches.", isOn: $neverAsk)
                    } footer: {
                        Text("You can turn asking back on in Settings → Routes.")
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: matchType) { newValue in
                switch newValue {
                case .address where !matchText.contains("@"): matchText = suggestedAddress ?? ""
                case .domain where matchText.contains("@"): matchText = Router.domain(of: matchText) ?? ""
                default: break
                }
            }

            footer
        }
        .frame(width: 540, height: min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 60))
        .tint(Brand.accent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
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
            if neverAsk, let onNeverAsk {
                Button("Always Use a New Chat", action: onNeverAsk)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                if offersOnce, let onOnce {
                    Button("Just This Once") { onOnce(draft) }.disabled(!isValid)
                }
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
