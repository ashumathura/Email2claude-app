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
    /// The prompt that the preview shows the route prompt being added to.
    let previewPrompt: String
    let loadChats: () -> ClaudeSidebar.ChatListResult
    /// What the Refresh button reads with: the same list, retried while Claude's sidebar settles.
    private let reloadChats: () -> ClaudeSidebar.ChatListResult = { ClaudeSidebar.reloadChatList() }
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
    @State private var chatList: ChatList
    @State private var chatsProblem: String?
    @State private var chatsLoadedAt: Date
    @State private var isRefreshing = false
    /// Not in the picker, so the project name is typed.
    @State private var typingProjectName: Bool
    /// When an email has no route yet: what should happen with it.
    @State private var outcome: Outcome = .once
    @State private var showsAppliesTo = false

    /// The three things that can happen with an email that has no route.
    private enum Outcome: String, CaseIterable, Identifiable {
        case once, save, never

        var id: String { rawValue }

        var title: String {
            switch self {
            case .once: return "Send this one email"
            case .save: return "Send it, and remember for next time"
            case .never: return "Always use a new chat, and stop asking"
            }
        }

        var detail: String {
            switch self {
            case .once: return "Nothing is saved. The next similar email asks again."
            case .save: return "Saves a route, so similar emails go there without asking."
            case .never: return "Emails with no route skip this window and start a new chat."
            }
        }

        var button: String {
            switch self {
            case .once: return "Send"
            case .save: return "Send and save route"
            case .never: return "Send to a New Chat"
            }
        }
    }

    init(
        title: String, subtitle: String, initial: Route, suggestions: Router.RouteSuggestion? = nil,
        offersOnce: Bool, previewPrompt: String = Action.reply.defaultInstruction,
        loadChats: @escaping () -> ClaudeSidebar.ChatListResult,
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
        let loaded = loadChats()
        _chatList = State(initialValue: loaded.list)
        _chatsProblem = State(initialValue: loaded.problem)
        _chatsLoadedAt = State(initialValue: loaded.date)
        let savedProject = (initial.name ?? "").trimmingCharacters(in: .whitespaces)
        _showsAppliesTo = State(initialValue: text.isEmpty)
        _typingProjectName = State(
            initialValue: initial.kind == .project && (loaded.list.projects.isEmpty
                || (!savedProject.isEmpty && !loaded.list.projects.contains(savedProject))))
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
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesDetails = kind == .chat || kind == .project
        return Route(
            domain: ruleValue, matchOn: field, kind: kind,
            name: usesDetails && !trimmedName.isEmpty ? trimmedName : nil,
            url: usesDetails && !trimmedURL.isEmpty ? trimmedURL : nil,
            instructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions)
    }

    private var linkIsValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || ChatLink.appURL(from: trimmed) != nil
    }

    /// The destination is complete: a link that parses, and a chat or project when one is needed.
    private var destinationValid: Bool {
        guard linkIsValid else { return false }
        switch kind {
        case .chat, .project: return draft.name != nil || draft.url != nil
        case .newChat, .incognito: return true
        }
    }

    private var isValid: Bool {
        !ruleValue.isEmpty && ruleError == nil && destinationValid
    }

    /// Whether the main button can be pressed. Only saving needs a rule.
    private var canSubmit: Bool {
        guard offersOnce else { return isValid }
        switch outcome {
        case .once: return destinationValid
        case .save: return isValid
        case .never: return true
        }
    }

    /// The chat saved on this route, if Claude's current sidebar doesn't list it (scrolled out of view, or renamed).
    private var savedChatNotListed: String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || chatList.chats.contains(trimmed) ? nil : trimmed
    }

    private func refreshChats() {
        isRefreshing = true
        // The read can take a couple of seconds when Claude has just changed view, so it runs off the main thread.
        let reload = reloadChats
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = reload()
            DispatchQueue.main.async {
                chatList = loaded.list
                chatsProblem = loaded.problem
                chatsLoadedAt = loaded.date
                isRefreshing = false
            }
        }
    }

    private var chatsStatus: Text {
        if let chatsProblem { return Text(chatsProblem) }
        if kind == .project {
            let time = chatsLoadedAt.formatted(date: .omitted, time: .standard)
            let count = chatList.projects.count
            return count == 0
                ? Text("No projects found in Claude's sidebar. Pin one there, refresh, or type its name.")
                : Text("Updated \(time): \(count) project\(count == 1 ? "" : "s")")
        }
        let count = chatList.chats.count
        let time = chatsLoadedAt.formatted(date: .omitted, time: .standard)
        let projects = chatList.projects.count
        let scope = projects > 0 ? " in \(projects) project\(projects == 1 ? "" : "s") and recents" : ""
        return Text("Updated \(time): \(count) chat\(count == 1 ? "" : "s")\(scope)")
    }

    private var whoPhrase: String {
        switch matchType {
        case .domain: return "anyone at " + (ruleValue.isEmpty ? "company.com" : ruleValue)
        case .address: return ruleValue.isEmpty ? "name@company.com" : ruleValue
        }
    }

    /// Exactly what Claude would receive for a made-up email, with the route prompt in place.
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
            if offersOnce { outcomePicker }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if offersOnce {
                        switch outcome {
                        case .once:
                            destinationSection
                            promptSection
                        case .save:
                            appliesToSection
                            destinationSection
                            promptSection
                            resultSection
                        case .never:
                            TipBox(.info, symbol: "info.circle") {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("From now on, emails that have no route skip this window and start a new chat in Claude. This email goes to a new chat too.")
                                    Text("You can turn asking back on in Settings → Routes.").foregroundStyle(.secondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        matchSection
                        destinationSection
                        promptSection
                        resultSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .onChange(of: matchType) { _ in refreshText() }
            .onChange(of: field) { _ in refreshText() }

            footer
        }
        .frame(width: 560, height: min(740, (NSScreen.main?.visibleFrame.height ?? 800) - 60))
        .tint(Brand.accent)
    }

    // MARK: Sections

    /// The choice that comes first for an email with no route: what should happen with it.
    private var outcomePicker: some View {
        VStack(spacing: 8) {
            ForEach(Outcome.allCases) { option in
                let selected = outcome == option
                Button { outcome = option } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Brand.accent : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.body.weight(.semibold))
                            Text(option.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selected ? Brand.accent.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Brand.accent : Color.secondary.opacity(0.3)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// A heading with its content in a card.
    private func titledCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Card {
                VStack(alignment: .leading, spacing: 10) { content() }
            }
        }
    }

    /// The rule fields, as they appear when a route is edited in Settings.
    private var matchSection: some View {
        titledCard("When an email is…") {
            matchControls
            matchFooter
        }
    }

    /// The same fields for a new route saved from an email: one line, with the controls behind it.
    private var appliesToSection: some View {
        titledCard("Remember it for") {
            DisclosureGroup(isExpanded: $showsAppliesTo) {
                VStack(alignment: .leading, spacing: 10) {
                    matchControls
                    matchFooter
                }
                .padding(.top, 8)
            } label: {
                Text("Applies to: mail **\(field.phrase)** **\(whoPhrase)**")
            }
        }
    }

    @ViewBuilder private var matchControls: some View {
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
        fieldLabel(matchType == .domain ? "Domain" : "Email address")
        TextField(
            "", text: $matchText,
            prompt: Text(matchType == .domain ? "company.com" : "name@company.com"))
            .textFieldStyle(.roundedBorder)
        if let ruleError {
            Text(ruleError).font(.caption).foregroundStyle(.red)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.callout.weight(.medium))
    }

    private var matchFooter: some View {
        Text((field == .to
              ? "To looks at who the email was sent to. "
              : "From looks at who the email came from, which is what you want for mail you receive. ")
             + (matchType == .domain
                ? "A domain covers everyone there, subdomains too."
                : "One address takes priority over a domain rule. To cover both directions with a client, add one From route and one To route."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The four places an email can go, as cards. The chosen one opens its own fields.
    private var destinationSection: some View {
        titledCard(offersOnce ? "Where should it go?" : "…put it in Claude") {
            VStack(spacing: 8) {
                ForEach(DestinationKind.allCases) { option in
                    let selected = kind == option
                    VStack(alignment: .leading, spacing: 12) {
                        Button { kind = option } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(selected ? Brand.accent : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(.body.weight(.semibold))
                                    Text(option.summary).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if option == .chat { Chip(text: "Best for people", tint: .orange) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        if selected { details }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selected ? Brand.accent.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Brand.accent : Look.border))
                }
            }
        }
    }

    private var promptSection: some View {
        titledCard("Route prompt (optional)") {
            TextEditor(text: $instructions)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Look.border))
            Text(offersOnce && outcome == .once
                 ? "Added after the action's prompt for this email only. Actions set to paste only don't use it."
                 : "Added after the action's prompt every time an email uses this route, so one action can behave differently per sender or domain. Example: “Always reply formally, in Dutch.” Actions set to paste only don't use it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Preview what Claude receives") {
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
        }
    }

    private var resultSection: some View {
        TipBox(.info) {
            Text("**Result:** Emails **\(field.phrase)** **\(whoPhrase)** go to: **\(draft.destinationDescription)**")
                .fixedSize(horizontal: false, vertical: true)
        }
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
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Chat")
                Picker("Chat", selection: $name) {
                    Text(chatList.isEmpty ? "No chats found" : "Choose a chat…").tag("")
                    if let saved = savedChatNotListed {
                        Section("Saved on this route") { Text(saved).tag(saved) }
                    }
                    ForEach(chatList.groups) { group in
                        Section(group.project.map { "In project: \($0)" } ?? (chatList.projects.isEmpty ? "Chats" : "Recent chats")) {
                            ForEach(group.chats, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                .labelsHidden()
                refreshRow(buttonTitle: "Refresh Chat List")
                linkField(placeholder: "https://claude.ai/chat/…", label: "Or paste a chat link")
            }
        case .project:
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Project")
                if chatList.projects.isEmpty {
                    TextField("", text: $name, prompt: Text("Exactly as shown in Claude"))
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Project", selection: projectSelection) {
                        Text("Choose a project…").tag("")
                        ForEach(chatList.projects, id: \.self) { Text($0).tag($0) }
                        Divider()
                        Text("Other (type its name)…").tag(Self.otherProject)
                    }
                    .labelsHidden()
                    if showsTypedProjectName {
                        TextField("", text: $name, prompt: Text("Exactly as shown in Claude"))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                refreshRow(buttonTitle: "Refresh Project List")
                linkField(placeholder: "https://claude.ai/project/…", label: "Or paste a project link")
            }
        case .newChat, .incognito:
            EmptyView()
        }
    }

    private static let otherProject = "\u{1}other"

    /// The name is typed when the user chose Other, or when it isn't one of the listed projects.
    private var showsTypedProjectName: Bool {
        typingProjectName || (!name.isEmpty && !chatList.projects.contains(name))
    }

    /// The project picker's value: a listed project, or "Other" while the name is typed.
    private var projectSelection: Binding<String> {
        Binding(
            get: { showsTypedProjectName ? Self.otherProject : name },
            set: { choice in
                if choice == Self.otherProject {
                    typingProjectName = true
                    if chatList.projects.contains(name) { name = "" }
                } else {
                    typingProjectName = false
                    name = choice
                }
            })
    }

    private func refreshRow(buttonTitle: String) -> some View {
        HStack(spacing: 8) {
            Button { refreshChats() } label: {
                Label(buttonTitle, systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(isRefreshing)
            if isRefreshing { ProgressView().controlSize(.small) }
            chatsStatus
                .font(.caption)
                .foregroundStyle(chatsProblem == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func linkField(placeholder: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label + " (most reliable)")
            TextField("", text: $url, prompt: Text(placeholder + " (optional)"), axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            if !linkIsValid {
                Text("That doesn't look like a claude.ai link.").font(.caption).foregroundStyle(.red)
            } else if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("A link is the most reliable way to find it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            Button(offersOnce ? outcome.button : "Save", action: submit)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func submit() {
        guard offersOnce else { return onSave(draft) }
        switch outcome {
        case .once: onOnce?(draft)
        case .save: onSave(draft)
        case .never: onNeverAsk?()
        }
    }

}
