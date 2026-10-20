import AppKit
import SwiftUI
import Email2ClaudeCore

private enum SettingsTabID: String, CaseIterable, Identifiable {
    case routes, prompts, activity, general, account, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: return "Routes"
        case .prompts: return "Prompts"
        case .activity: return "Activity"
        case .general: return "General"
        case .account: return "License & Privacy"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .routes: return "arrow.triangle.branch"
        case .prompts: return "text.bubble"
        case .activity: return "clock.arrow.circlepath"
        case .general: return "gearshape"
        case .account: return "key"
        case .about: return "heart"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var activity: ActivityStore
    @ObservedObject var updates: UpdateManager
    @State private var tab: SettingsTabID = .routes

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: min(700, (NSScreen.main?.visibleFrame.height ?? 800) - 60))
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Brand.accent)
        .onAppear { jumpToLicenseIfAsked() }
        .onChange(of: updates.showLicenseTab) { _ in jumpToLicenseIfAsked() }
    }

    private func jumpToLicenseIfAsked() {
        guard updates.showLicenseTab else { return }
        tab = .account
        updates.showLicenseTab = false
    }

    /// A toolbar-style tab bar inside the window, with room above it and one background all the way down.
    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTabID.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 19))
                        Text(item.title).font(.caption)
                    }
                    .foregroundStyle(tab == item ? Brand.accent : Color.secondary)
                    .frame(width: 108, height: 54)
                    .background(
                        tab == item ? Brand.accent.opacity(0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .routes: RoutesTab(store: store)
        case .prompts: PromptsTab(store: store, openGeneral: { tab = .general })
        case .activity: ActivityTab(activity: activity)
        case .general: GeneralTab(store: store)
        case .account: AccountTab(store: store, updates: updates)
        case .about: AboutTab()
        }
    }
}

private extension View {
    /// Secondary text on a tinted box. The system's .secondary grey nearly fades into the tint,
    /// so use the primary colour at reduced strength instead.
    func calloutNote(_ font: Font = .callout) -> some View {
        self.font(font).foregroundStyle(Color.primary.opacity(0.78))
    }
}

/// A tinted box for explanations.
private struct Callout<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Routes

private struct RoutesTab: View {
    @ObservedObject var store: ConfigStore
    @State private var selection: String?
    @State private var editor: EditorItem?
    @State private var testAddress = ""
    @State private var testField: MatchField = .to
    @State private var showsHelp = false

    private struct EditorItem: Identifiable {
        let id = UUID()
        let route: Route
        let isNew: Bool
    }

    private var selectedRoute: Route? {
        store.config.routes.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader("Routes", subtitle: "Decide which Claude chat each email goes to, so Claude remembers each client or topic.") {
                Button { editor = EditorItem(route: Route(domain: ""), isNew: true) } label: {
                    Label("Add route", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            TipBox(.info) {
                Text("**3 rules:** a full address beats a domain · higher in the list wins · no match, the app asks.")
                    .font(.callout)
                Spacer(minLength: 8)
                Button("How routes work") { showsHelp = true }
                    .popover(isPresented: $showsHelp, arrowEdge: .bottom) { explainer.padding(16).frame(width: 440) }
            }

            routeList

            Text("Double-click a route to edit it. Select one and press Delete to remove it.")
                .font(.caption).foregroundStyle(.secondary)

            tester

            Toggle(isOn: $store.config.askForUnknownRoutes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask where to send emails that have no route").fontWeight(.semibold)
                    Text(store.config.askForUnknownRoutes
                         ? "A window asks what should happen with an email that has none."
                         : "Emails without a route start a new chat without asking.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .sheet(item: $editor) { item in
            RouteEditorView(
                title: item.isNew ? "Add Route" : "Edit Route",
                subtitle: "Choose which emails this applies to, and where Claude should receive them.",
                initial: item.route,
                offersOnce: false,
                previewPrompt: store.config.instruction(for: .reply),
                loadChats: { ClaudeSidebar.loadChatList() },
                onSave: { route in
                    if item.isNew { store.config.upsert(route) } else { store.config.replace(item.route, with: route) }
                    var saved = route
                    saved.domain = Router.normalizeRule(route.domain)
                    selection = saved.id
                    editor = nil
                },
                onCancel: { editor = nil })
        }
    }

    private var routeList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("When an email is…").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Drag to reorder. Higher wins.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
            List(selection: $selection) {
                ForEach(store.config.routes) { route in
                    RouteRow(
                        route: route,
                        overlaps: store.config.routes.filter { Router.overlaps(route, $0) },
                        onEdit: { editor = EditorItem(route: route, isNew: false) })
                        .tag(route.id)
                        .contextMenu {
                            Button("Edit…") { editor = EditorItem(route: route, isNew: false) }
                            Button("Delete", role: .destructive) { remove(route) }
                        }
                }
                .onMove { store.config.routes.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onDeleteCommand { if let route = selectedRoute { remove(route) } }
            .overlay {
                if store.config.routes.isEmpty {
                    Text("No routes yet.\nThey are added when you send an email that has none, or with Add route.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 150)
        .background(Look.card, in: RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous).stroke(Look.border))
        .clipShape(RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous))
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How routes work").font(.headline)
            Text("A route decides where an email goes in Claude. Each route looks at one field, and matches either a whole domain or one address:")
                .fixedSize(horizontal: false, vertical: true)
            ExampleRow(
                symbol: "tray.and.arrow.down", title: "From: mail you receive",
                example: "anna@company.com", result: "Claude chat “Anna”",
                note: "a domain like company.com covers everyone at that company")
            ExampleRow(
                symbol: "paperplane", title: "To: mail you send",
                example: "company.com", result: "Claude project “Company”",
                note: "a client you write to and hear from needs one From route and one To route")
            Text("A full address beats a domain. Otherwise the route higher in the list wins, so drag to reorder. No match: the app asks, or starts a new chat.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shows which route an email would get, so the order and the precedence rules can be checked.
    private var tester: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Test your routes").font(.headline)
                HStack(spacing: 10) {
                    Text("Email address").fontWeight(.medium)
                    TextField("", text: $testAddress, prompt: Text("anna@company.com"))
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $testField) {
                        Text("Sent to").tag(MatchField.to)
                        Text("Received from").tag(MatchField.from)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                TipBox(.info) {
                    Text(testResult).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var testResult: LocalizedStringKey {
        let address = testAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return "Type an address and choose whether you send to it or receive from it, to see which route applies." }
        let email = testField == .from
            ? Email(sender: address, subject: "", date: "", to: [], cc: [], body: "", attachmentPaths: [])
            : Email(sender: "", subject: "", date: "", to: [address], cc: [], body: "", attachmentPaths: [])
        guard let hit = Router.match(for: email, config: store.config) else {
            return store.config.askForUnknownRoutes
                ? "**No match.** The app would ask where to send it."
                : "**No match.** It would start a new chat."
        }
        let number = (store.config.routes.firstIndex { $0.id == hit.route.id } ?? 0) + 1
        let kind = hit.route.isAddressRule ? "address" : "domain"
        let who = hit.route.isAddressRule ? hit.route.domain : "anyone at " + hit.route.domain
        let verb = hit.route.matchOn == .to ? "send to" : "receive from"
        return "**Match:** mail you \(verb) \(who) goes to **\(hit.route.destinationChip)** (route \(number), matched by \(kind))."
    }

    private func remove(_ route: Route) {
        store.config.routes.removeAll { $0.id == route.id }
        if selection == route.id { selection = nil }
    }
}

private struct ExampleRow: View {
    let symbol: String
    let title: String
    let example: String
    let result: String
    var note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text("Email matching **\(example)** → \(result)")
                if let note { Text(note).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct RouteRow: View {
    let route: Route
    let overlaps: [Route]
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.matchOn == .to ? "paperplane" : "tray.and.arrow.down")
                .font(.system(size: 15))
                .foregroundStyle(Brand.accent)
                .frame(width: 34, height: 34)
                .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("goes to").foregroundStyle(.secondary)
                    Chip(text: route.destinationChip)
                    if route.instructions?.isEmpty == false {
                        Text("with a route prompt").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !overlaps.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Overlaps with " + overlaps.map(\.domain).joined(separator: ", ") + ". The one higher in the list wins.")
            }
            Button("Edit", action: onEdit).controlSize(.small)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    /// "Mail you send to anyone at acme.com", in plain words.
    private var headline: String {
        let verb = route.matchOn == .to ? "send to" : "receive from"
        return "Mail you \(verb) " + (route.isAddressRule ? "" : "anyone at ") + route.domain
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @ObservedObject var store: ConfigStore
    let openGeneral: () -> Void
    @State private var selected: Action? = .reply

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                Section {
                    ForEach(Action.allCases) { action in
                        ActionRow(name: store.config.name(for: action), placeholder: action.placeholderName,
                                  shortcut: action.shortcutLabel, configured: store.config.isConfigured(action))
                            .tag(action)
                    }
                } header: {
                    Text("Your \(Action.allCases.count) actions")
                }
            }
            .listStyle(.sidebar)
            .frame(width: 250)

            Divider()

            ActionDetail(store: store, action: selected ?? .reply, openGeneral: openGeneral)
                .id(selected)
        }
    }
}

private struct ActionRow: View {
    let name: String
    let placeholder: String
    let shortcut: String
    let configured: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? placeholder : name)
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                if !configured {
                    Text("Set up: add a name and a prompt").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            ShortcutChip(text: shortcut)
        }
        .padding(.vertical, 3)
    }
}

private struct ActionDetail: View {
    @ObservedObject var store: ConfigStore
    let action: Action
    let openGeneral: () -> Void

    private var name: Binding<String> {
        Binding(get: { store.config.name(for: action) }, set: { store.config.setName($0, for: action) })
    }
    private var mode: Binding<ActionMode> {
        Binding(get: { store.config.mode(for: action) }, set: { store.config.setMode($0, for: action) })
    }
    private var prompt: Binding<String> {
        Binding(get: { store.config.instruction(for: action) }, set: { store.config.setInstruction($0, for: action) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                menuItemSection
                modeSection
                if mode.wrappedValue == .prompt { promptSection }
                HStack {
                    Button("Reset to Default") { store.config.resetAction(action) }
                        .disabled(store.config.actions[action.rawValue] == nil)
                    Spacer()
                }
            }
            .padding(24)
        }
    }

    private func titled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private var menuItemSection: some View {
        titled("Menu item") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Name")
                        TextField("", text: name, prompt: Text(action.placeholderName))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 260)
                    }
                    Divider()
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutChip(text: action.shortcutLabel)
                    }
                }
            }
            if store.config.isConfigured(action) {
                Text("Shown under Send to Claude in the menu bar.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This action appears in the menu once it has a name\(mode.wrappedValue == .prompt ? " and a prompt" : "").")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var modeSection: some View {
        titled("What happens to the email") {
            HStack(alignment: .top, spacing: 10) {
                OptionCard(
                    title: ActionMode.pasteOnly.title,
                    detail: "You type your own message. Nothing is sent for you.",
                    selected: mode.wrappedValue == .pasteOnly) { mode.wrappedValue = .pasteOnly }
                OptionCard(
                    title: ActionMode.prompt.title,
                    detail: "Your prompt goes above the email, then both are sent to the routed chat.",
                    selected: mode.wrappedValue == .prompt) { mode.wrappedValue = .prompt }
            }
            if mode.wrappedValue == .prompt {
                TipBox(.info) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.config.autoSend
                             ? "**Auto-send is on**, so Claude starts working straight away. The email's From, To, Cc, date, subject, body and attachments are always included."
                             : "**Auto-send is off**, so the message waits in Claude's message box until you press Return. The email's From, To, Cc, date, subject, body and attachments are always included.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Change in General", action: openGeneral)
                    }
                }
            } else {
                TipBox(.info) {
                    Text("The email is pasted into the routed Claude chat and nothing else happens. Type your own request in Claude, then press Return. Its From, To, Cc, date, subject, body and attachments are included.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var promptSection: some View {
        titled("Prompt") {
            TextEditor(text: prompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Look.border))
            HStack(spacing: 8) {
                Text("Start from:").font(.callout).foregroundStyle(.secondary)
                ForEach([Action.reply, .summary, .research], id: \.self) { preset in
                    Button(preset.defaultName) { prompt.wrappedValue = preset.defaultInstruction }
                        .controlSize(.small)
                }
            }
            Text("Placed above the email in Claude. The route prompt, if the route has one, follows it.")
                .font(.caption).foregroundStyle(.secondary)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What Claude receives").font(.headline)
                    receivesRow("1", "This prompt", tinted: true)
                    receivesRow("2", "The route prompt (if any)", tinted: false)
                    receivesRow("3", "The email: From, To, Cc, date, subject, body and attachments", tinted: false)
                }
            }
        }
    }

    private func receivesRow(_ number: String, _ text: String, tinted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.callout.weight(.semibold)).foregroundStyle(Brand.accent)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            tinted ? Brand.accent.opacity(0.10) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Activity

private struct ActivityTab: View {
    @ObservedObject var activity: ActivityStore
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var confirmClear = false

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", today = "Today"
        var id: String { rawValue }
    }

    private var rows: [ActivityEntry] {
        activity.entries.filter { entry in
            entry.matches(query) && (filter == .all || Calendar.current.isDateInToday(entry.date))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader("Activity", subtitle: "What you sent to Claude and where it went. Stored only on this Mac.") {
                Chip(text: "🔒 Private to this Mac")
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search subject, sender, route or prompt", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text("\(rows.count) of \(activity.entries.count)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }

            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            row(entry)
                            Divider()
                        }
                    }
                }
                .overlay {
                    if activity.entries.isEmpty {
                        Text("Nothing here yet.\nEmails you send to Claude are listed here.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    } else if rows.isEmpty {
                        Text("No matches.").foregroundStyle(.secondary)
                    }
                }
                Text("Tip: click an email to open it in Mail, or a route to open its chat in Claude.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))
            }
            .background(Look.card, in: RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous).stroke(Look.border))
            .clipShape(RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous))

            HStack {
                Text("Switch the log off in General if you would rather not keep one.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show Log File") { activity.revealInFinder() }
                Button("Clear Log…") { confirmClear = true }
                    .disabled(activity.entries.isEmpty)
            }
        }
        .padding(24)
        .alert("Clear the activity log?", isPresented: $confirmClear) {
            Button("Clear Log", role: .destructive) { activity.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the list in this app. Your emails and Claude chats are not touched.")
        }
    }

    private static let whenWidth: CGFloat = 96
    private static let fromWidth: CGFloat = 120
    private static let sentToWidth: CGFloat = 210
    private static let actionWidth: CGFloat = 110

    private var header: some View {
        HStack(spacing: 12) {
            Text("When").frame(width: Self.whenWidth, alignment: .leading)
            Text("Email").frame(maxWidth: .infinity, alignment: .leading)
            Text("From").frame(width: Self.fromWidth, alignment: .leading)
            Text("Sent to").frame(width: Self.sentToWidth, alignment: .leading)
            Text("Action").frame(width: Self.actionWidth, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func row(_ entry: ActivityEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Calendar.current.isDateInToday(entry.date) ? "Today" : entry.date.formatted(date: .abbreviated, time: .omitted))
                Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: Self.whenWidth, alignment: .leading)

            Group {
                if let url = entry.mailURL {
                    Button(entry.subject.isEmpty ? "(no subject)" : entry.subject) { NSWorkspace.shared.open(url) }
                        .buttonStyle(.link)
                        .help("Open this email in Mail")
                } else {
                    Text(entry.subject.isEmpty ? "(no subject)" : entry.subject)
                }
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.sender).lineLimit(1).truncationMode(.tail)
                .frame(width: Self.fromWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                if entry.canOpenChat {
                    Button { openChat(entry) } label: { Chip(text: entry.destination.destinationChip) }
                        .buttonStyle(.plain)
                        .help("Open this chat or project in Claude")
                } else {
                    Chip(text: entry.destination.destinationChip)
                }
                Text(entry.rule.isEmpty ? "No route" : "\(entry.destination.matchOn.title) \(entry.rule)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            .frame(width: Self.sentToWidth, alignment: .leading)

            Text(entry.actionName).lineLimit(2)
                .help(entry.prompt.isEmpty ? "Pasted the email only" : entry.prompt)
                .frame(width: Self.actionWidth, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func openChat(_ entry: ActivityEntry) {
        Task {
            do {
                try await ClaudeBridge.reveal(entry.destination.target)
            } catch {
                let panel = NSAlert()
                panel.messageText = "MailtoChat"
                panel.informativeText = error.localizedDescription
                panel.runModal()
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    @State private var accessibility = ClaudeBridge.accessibilityGranted(prompt: false)

    var body: some View {
        Form {
            Section {
                Toggle("Send to Claude automatically", isOn: $store.config.autoSend)
            } footer: {
                Text("For actions that add a prompt, the message is submitted right after pasting. Actions set to paste the email only never submit.")
            }

            Section {
                Toggle("Warn when several emails are selected", isOn: $store.config.warnMultipleSelection)
            } footer: {
                Text("MailtoChat sends one email at a time: the first one selected in Mail. With this on, you're told when you selected more and can cancel.")
            }

            Section {
                Toggle("Keep an activity log", isOn: $store.config.keepActivityLog)
            } footer: {
                Text("Records the date, subject, sender, route and prompt of each email on this Mac only. See the Activity tab.")
            }

            Section {
                LabeledContent("Wait for Claude to load a chat") {
                    HStack {
                        Slider(value: $store.config.openDelay, in: 0.4...3, step: 0.1).frame(width: 160)
                        Text(String(format: "%.1fs", store.config.openDelay))
                            .monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                }
            } header: {
                Text("Speed")
            } footer: {
                Text("A shorter wait is faster but can paste before the chat has finished opening. New chats ignore this.")
            }

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 6) {
                        Image(systemName: accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibility ? .green : .orange)
                        Text(accessibility ? "Allowed" : "Not allowed")
                    }
                }
                HStack {
                    Button("Recheck") { accessibility = ClaudeBridge.accessibilityGranted(prompt: false) }
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility lets MailtoChat read Claude's chat list and paste into it.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - License & Privacy

private struct AccountTab: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var updates: UpdateManager
    @State private var confirmErase = false
    @State private var confirmRemove = false
    @State private var email = ""
    @State private var registering = false
    @State private var registerError: String?

    private var choice: Binding<AnalyticsChoice> {
        Binding(
            get: { store.config.analyticsChoice == .shared ? .shared : .notShared },
            set: { newValue in
                store.config.analyticsChoice = newValue
                store.config.analyticsChoiceDate = Date()
                updates.syncConsent()
            })
    }

    private var lastChecked: String {
        store.config.lastUpdateCheck?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet"
    }

    var body: some View {
        Form {
            if store.config.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty { getKeySection }

            Section {
                TextField("License key", text: $store.config.licenseKey, prompt: Text("EMC-XXXXX-XXXXX-XXXXX-XXXXX"))
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: store.config.licenseKey) { _ in updates.licenseKeyEdited() }
                if !store.config.licenseEmail.isEmpty {
                    LabeledContent("Issued to", value: store.config.licenseEmail)
                }
                LabeledContent("Status") { licenseStatus }
                if !store.config.licenseKey.isEmpty || !store.config.licenseEmail.isEmpty {
                    Button("Remove License…", role: .destructive) { confirmRemove = true }
                }
            } header: {
                Text("License")
            } footer: {
                Text("Your license is checked as soon as you enter it, and then about once a week when the app looks for updates. A valid license lets you download updates. The app itself keeps working either way.")
            }

            Section {
                LabeledContent("Installed version", value: BackendConfig.appVersion)
                LabeledContent("Last checked", value: lastChecked)
                HStack {
                    Button("Check for Updates Now") { updates.checkNow() }
                        .disabled(updates.busy)
                    if updates.busy { ProgressView().controlSize(.small) }
                }
                if !updates.status.isEmpty {
                    Text(updates.status).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("The app checks once a week and asks before it downloads anything. Updating restarts the app.")
            }

            Section {
                LocalPromiseBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Analytics", selection: choice) {
                    Text("Share analytics").tag(AnalyticsChoice.shared)
                    Text("Don't share analytics").tag(AnalyticsChoice.notShared)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Callout {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is stored on the server")
                            .font(.headline)
                        ForEach(store.config.analyticsChoice == .shared ? PrivacyText.sharedItems : PrivacyText.minimalItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) { Text("•"); Text(item) }
                        }
                    }
                }
                Button("Erase My Data on the Server…") { confirmErase = true }
                if let url = BackendConfig.privacyPolicyURL { Link("Privacy policy", destination: url) }
            } header: {
                Text("Privacy")
            } footer: {
                Text("This only covers update, license and usage information. Switching to \"Don't share\" removes the analytics fields from the server right away.")
            }
        }
        .formStyle(.grouped)
        .alert("Remove the license from this Mac?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { updates.removeLicense() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The key and the email address it was issued to are forgotten here, and updates stop until you add a key again. The app keeps working. The key stays valid, so you can enter it again or get one with your email address.")
        }
        .alert("Erase your data on the server?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) { Task { await updates.erase() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes everything stored about this install, including your device ID and the email address linked to your license, and starts a new device ID. Your license key itself stays valid.")
        }
    }

    private var getKeySection: some View {
        Section {
            HStack {
                TextField("Email address", text: $email, prompt: Text("you@example.com"))
                    .disabled(registering)
                    .onSubmit(getKey)
                Button("Get Free License Key", action: getKey)
                    .disabled(!EmailAddress.isPlausible(email) || registering)
                if registering { ProgressView().controlSize(.small) }
            }
            if let registerError {
                Label(registerError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        } header: {
            Text("Get a free license key")
        } footer: {
            Text(PrivacyText.emailNote)
        }
    }

    private func getKey() {
        guard EmailAddress.isPlausible(email), !registering else { return }
        registering = true
        registerError = nil
        Task {
            do { try await updates.registerLicense(email: email) } catch { registerError = error.localizedDescription }
            registering = false
        }
    }

    @ViewBuilder private var licenseStatus: some View {
        switch store.config.lastLicenseStatus {
        case "valid":
            Label("Valid", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case "missing":
            Label("No key entered", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .some(let other):
            Label(other == "expired" ? "Expired" : other == "revoked" ? "No longer active" : "Not valid", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .none:
            Text("Not checked yet").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: ConfigStore, activity: ActivityStore, updates: UpdateManager) {
        let view = SettingsView(store: store, activity: activity, updates: updates)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "MailtoChat Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}
