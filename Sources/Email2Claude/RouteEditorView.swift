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

/// Maps who an email was sent to, or came from (a whole domain, or one address), onto a Claude
/// destination. Used from Settings and from the prompt shown when an email has no route yet.
struct RouteEditorView: View {
    enum MatchType: String, CaseIterable, Identifiable {
        case domain, address
        var id: String { rawValue }
    }

    let title: String
    let subtitle: String
    /// The addresses in the email that triggered the prompt. They prefill the field when the
    /// user switches between To and From, or between a domain and one address.
    let suggestions: Router.RouteSuggestion?
    let offersOnce: Bool
    /// The prompt that the preview shows the standing instructions being added to.
    let previewPrompt: String
    let loadChats: () -> [String]
    let onSave: (Route) -> Void
    let onOnce: ((Route) -> Void)?
    let onNeverAsk: (() -> Void)?
    let onCancel: () -> Void

    @State private var field: MatchField
    @State private var matchType: MatchType
    @State private var matchText: String
    @State private var lastSuggested: String?
    @State private var kind: DestinationKind
    @State private var name: String
    @State private var url: String
    @State private var instructions: String
    @State private var chats: [String]
    @State private var neverAsk = false

    init(
        title: String, subtitle: String, initial: Route, suggestions: Router.RouteSuggestion? = nil,
        offersOnce: Bool, previewPrompt: String = Action.reply.defaultInstruction,
        loadChats: @escaping () -> [String],
        onSave: @escaping (Route) -> Void, onOnce: ((Route) -> Void)? = nil,
        onNeverAsk: (() -> Void)? = nil, onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.suggestions = suggestions
        self.offersOnce = offersOnce
        self.previewPrompt = previewPrompt
        self.loadChats = loadChats
        self.onSave = onSave
        self.onOnce = onOnce
        self.onNeverAsk = onNeverAsk
        self.onCancel = onCancel
        let type: MatchType = initial.isAddressRule ? .address : .domain
        let text = Router.normalizeRule(initial.domain)
        _field = State(initialValue: initial.matchOn)
        _matchType = State(initialValue: type)
        _matchText = State(initialValue: text)
        _lastSuggested = State(initialValue: Self.suggestedText(suggestions, initial.matchOn, type))
        _kind = State(initialValue: initial.kind)
        _name = State(initialValue: initial.name ?? "")
        _url = State(initialValue: initial.url ?? "")
        _instructions = State(initialValue: initial.instructions ?? "")
        _chats = State(initialValue: loadChats())
    }

    // MARK: Derived values

    private static func suggestedText(_ suggestions: Router.RouteSuggestion?, _ field: MatchField, _ type: MatchType) -> String? {
        guard let address = suggestions?.address(for: field) else { return nil }
        return type == .address ? address : Router.domain(of: address)
    }

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
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesDetails = kind == .chat || kind == .project
        return Route(
            domain: ruleValue, matchOn: field, kind: kind,
            name: usesDetails && !trimmedName.isEmpty ? trimmedName : nil,
            url: usesDetails && !trimmedURL.isEmpty ? trimmedURL : nil,
            instructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions)
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

    /// Exactly what Claude would receive for a made-up email, with the standing instructions in place.
    private var preview: String {
        let sample = Email(
            sender: "Anna de Vries <anna@example.com>", subject: "Question about the quote", date: "Mon, 5 May 2026",
            to: ["you@example.com"], cc: [], body: "(the text of the email)", attachmentPaths: [])
        let prompt = PromptBuilder.compose(actionPrompt: previewPrompt, routeInstructions: draft.instructions)
        return sample.prompt(instruction: prompt)
    }

    /// When the field or match type changes, move a prefilled value along with it, but never
    /// overwrite something the user typed.
    private func refreshText() {
        let new = Self.suggestedText(suggestions, field, matchType)
        if matchText.isEmpty || matchText == lastSuggested {
            matchText = new ?? ""
        } else if matchType == .domain, matchText.contains("@") {
            matchText = Router.domain(of: matchText) ?? ""
        } else if matchType == .address, !matchText.contains("@") {
            matchText = new ?? ""
        }
        lastSuggested = new
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    Picker("Email field", selection: $field) {
                        ForEach(MatchField.allCases) { option in
                            Text(option == .to ? "Sent to (To)" : "Received from (From)").tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
                    Text("When an email is…")
                } footer: {
                    Text((field == .to
                          ? "To looks at who the email was sent to. "
                          : "From looks at who the email came from, which is what you want for mail you receive. ")
                         + (matchType == .domain
                            ? "A domain covers everyone there, subdomains too."
                            : "One address takes priority over a domain rule. To cover both directions with a client, add one From route and one To route."))
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

                Section {
                    TextEditor(text: $instructions)
                        .font(.body)
                        .frame(minHeight: 60)
                    DisclosureGroup("Preview what Claude receives") {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Standing instructions (optional)")
                } footer: {
                    Text("Added to the prompt every time this route is used, after the action's own prompt, for example “Always reply formally, in Dutch.” Actions that only paste the email aren't affected.")
                }
                .disabled(neverAsk)

                if !neverAsk {
                    Section {
                        Text("Emails **\(field.phrase)** **\(whoPhrase)** go to: **\(draft.destinationDescription)**")
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
            .onChange(of: matchType) { _ in refreshText() }
            .onChange(of: field) { _ in refreshText() }

            footer
        }
        .frame(width: 560, height: min(740, (NSScreen.main?.visibleFrame.height ?? 800) - 60))
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
