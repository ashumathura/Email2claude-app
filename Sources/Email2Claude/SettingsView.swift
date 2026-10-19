import AppKit
import SwiftUI
import Email2ClaudeCore

private enum SettingsTabID: String, CaseIterable, Identifiable {
    case routes, prompts, activity, general, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: return "Routes"
        case .prompts: return "Prompts"
        case .activity: return "Activity"
        case .general: return "General"
        case .account: return "License & Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .routes: return "arrow.triangle.branch"
        case .prompts: return "text.bubble"
        case .activity: return "clock.arrow.circlepath"
        case .general: return "gearshape"
        case .account: return "key"
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
                    .frame(width: 118, height: 54)
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
        case .prompts: PromptsTab(store: store)
        case .activity: ActivityTab(activity: activity)
        case .general: GeneralTab(store: store)
        case .account: AccountTab(store: store, updates: updates)
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
    @State private var testFrom = ""
    @State private var testTo = ""

    private struct EditorItem: Identifiable {
        let id = UUID()
        let route: Route
        let isNew: Bool
    }

    private var selectedRoute: Route? {
        store.config.routes.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            explainer

            List(selection: $selection) {
                ForEach(store.config.routes) { route in
                    RouteRow(
                        route: route,
                        overlaps: store.config.routes.filter { Router.overlaps(route, $0) })
                        .tag(route.id)
                }
                .onMove { store.config.routes.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if store.config.routes.isEmpty {
                    Text("No routes yet.\nThey are added when you send an email that has none, or with +.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Button { editor = EditorItem(route: Route(domain: ""), isNew: true) } label: {
                    Image(systemName: "plus")
                }
                Button(action: remove) { Image(systemName: "minus") }
                    .disabled(selectedRoute == nil)
                Spacer()
                Text("Drag to reorder. Higher wins.").font(.caption).foregroundStyle(.secondary)
                Button("Edit…") {
                    if let route = selectedRoute { editor = EditorItem(route: route, isNew: false) }
                }
                .disabled(selectedRoute == nil)
            }

            tester

            VStack(alignment: .leading, spacing: 3) {
                Toggle("Ask where to send emails that have no route", isOn: $store.config.askForUnknownRoutes)
                Text(store.config.askForUnknownRoutes
                     ? "A window asks the first time you send an email that has none, and remembers your answer."
                     : "Emails without a route always start a new chat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .sheet(item: $editor) { item in
            RouteEditorView(
                title: item.isNew ? "Add Route" : "Edit Route",
                subtitle: "Choose which emails this applies to, and where Claude should receive them.",
                initial: item.route,
                offersOnce: false,
                previewPrompt: store.config.instruction(for: .reply),
                loadChats: { ClaudeSidebar.chatTitles() },
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

    private var explainer: some View {
        Callout {
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
                    .calloutNote()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shows which route an email would get, so the order and the precedence rules can be checked.
    private var tester: some View {
        DisclosureGroup("Test your routes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("From", text: $testFrom, prompt: Text("anna@company.com"))
                    TextField("To", text: $testTo, prompt: Text("you@yourcompany.com"))
                }
                .textFieldStyle(.roundedBorder)
                Text(testResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var testResult: LocalizedStringKey {
        guard !testFrom.isEmpty || !testTo.isEmpty else { return "Type a sender and a recipient to see which route would apply." }
        let email = Email(
            sender: testFrom, subject: "", date: "", to: testTo.isEmpty ? [] : [testTo], cc: [], body: "", attachmentPaths: [])
        guard let hit = Router.match(for: email, config: store.config) else {
            return store.config.askForUnknownRoutes
                ? "No route matches. The app would ask where to send it."
                : "No route matches. It would start a new chat."
        }
        let kind = hit.route.isAddressRule ? "address" : "domain"
        return "**\(hit.route.matchOn.title) \(hit.route.domain)** (\(kind)) matches \(hit.address), so it goes to: **\(hit.route.destinationDescription)**."
    }

    private func remove() {
        guard let route = selectedRoute else { return }
        store.config.routes.removeAll { $0.id == route.id }
        selection = nil
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
                if let note { Text(note).calloutNote() }
            }
        }
    }
}

private struct RouteRow: View {
    let route: Route
    let overlaps: [Route]

    private var instructionsLine: String? {
        let line = route.instructions?.split(whereSeparator: \.isNewline).first.map(String.init)
        return line?.isEmpty == false ? line : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(route.domain).font(.body.weight(.medium))
                    chip(route.matchOn.title)
                    chip(route.isAddressRule ? "Address" : "Domain")
                }
                Text(route.destinationDescription).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1)
                if let instructionsLine {
                    Label(instructionsLine, systemImage: "text.quote")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !overlaps.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Overlaps with " + overlaps.map(\.domain).joined(separator: ", ") + ". The one higher in the list wins.")
            }
        }
        .padding(.vertical, 3)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @ObservedObject var store: ConfigStore
    @State private var selected: Action? = .reply

    var body: some View {
        HStack(spacing: 0) {
            List(Action.allCases, selection: $selected) { action in
                ActionRow(name: store.config.name(for: action), placeholder: action.placeholderName,
                          shortcut: action.shortcutLabel, configured: store.config.isConfigured(action))
                    .tag(action)
            }
            .listStyle(.sidebar)
            .frame(width: 240)

            Divider()

            ActionDetail(store: store, action: selected ?? .reply)
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
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? placeholder : name)
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                if !configured {
                    Text("Not in the menu yet").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(shortcut).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ActionDetail: View {
    @ObservedObject var store: ConfigStore
    let action: Action

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
        Form {
            Section {
                TextField("Name", text: name, prompt: Text(action.placeholderName))
                LabeledContent("Shortcut") {
                    Text(action.shortcutLabel)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            } header: {
                Text("Menu item")
            } footer: {
                if store.config.isConfigured(action) {
                    Text("Shown under Send to Claude in the menu bar.")
                } else {
                    Text("This action appears in the menu once it has a name\(mode.wrappedValue == .prompt ? " and a prompt" : "").")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("After pasting", selection: mode) {
                    ForEach(ActionMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Callout { explanation }
            } header: {
                Text("What happens to the email")
            }

            if mode.wrappedValue == .prompt {
                Section {
                    TextEditor(text: prompt)
                        .font(.body)
                        .frame(minHeight: 120)
                } header: {
                    Text("Prompt")
                } footer: {
                    Text("Placed above the email in Claude.")
                }
            }

            Section {
                Button("Reset to Default") { store.config.resetAction(action) }
                    .disabled(store.config.actions[action.rawValue] == nil)
            }
        }
        .formStyle(.grouped)
    }

    /// Spells out what the chosen mode does, including the effect of the auto-send setting.
    @ViewBuilder private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch mode.wrappedValue {
            case .pasteOnly:
                Label("The email is pasted into the routed Claude chat, and nothing else happens.", systemImage: "doc.on.clipboard")
                Text("Nothing is sent. Type your own request in Claude, then press Return.")
                    .calloutNote()
            case .prompt:
                Label("Your prompt is placed above the email, and both are pasted into the routed Claude chat.", systemImage: "text.bubble")
                if store.config.autoSend {
                    Text("Then it is sent right away, so Claude starts working on it immediately.")
                        .calloutNote()
                } else {
                    Text("Auto-send is off, so it waits in Claude's message box until you press Return.")
                        .calloutNote()
                }
                Text("Turn auto-send on or off in General.").calloutNote(.caption)
            }
            Text("Either way, the email's From, To, Cc, date, subject, body and attachments are included.")
                .calloutNote(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Activity

private struct ActivityTab: View {
    @ObservedObject var activity: ActivityStore
    @State private var query = ""
    @State private var confirmClear = false

    private var rows: [ActivityEntry] { activity.entries.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search subject, sender, route or prompt", text: $query)
                    .textFieldStyle(.roundedBorder)
                Text("\(rows.count) of \(activity.entries.count)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }

            Table(rows) {
                TableColumn("Date") { entry in
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .width(min: 110, ideal: 130, max: 170)
                TableColumn("Subject") { entry in
                    if let url = entry.mailURL {
                        Button(entry.subject.isEmpty ? "(no subject)" : entry.subject) {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.link)
                        .help("Open this email in Mail")
                    } else {
                        Text(entry.subject.isEmpty ? "(no subject)" : entry.subject)
                    }
                }
                TableColumn("From") { entry in
                    Text(entry.sender).lineLimit(1)
                }
                TableColumn("Claude route") { entry in
                    if entry.canOpenChat {
                        Button(entry.routeText) { openChat(entry) }
                            .buttonStyle(.link)
                            .help("Open this chat or project in Claude")
                    } else {
                        Text(entry.routeText)
                    }
                }
                TableColumn("Prompt") { entry in
                    Text(entry.actionName)
                        .help(entry.prompt.isEmpty ? "Pasted the email only" : entry.prompt)
                }
                .width(min: 90, ideal: 120)
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

            HStack {
                Text("Stored only on this Mac. Click a subject to open the email in Mail, or a route to open its chat in Claude.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show Log File") { activity.revealInFinder() }
                Button("Clear Log…") { confirmClear = true }
                    .disabled(activity.entries.isEmpty)
            }
        }
        .padding(20)
        .alert("Clear the activity log?", isPresented: $confirmClear) {
            Button("Clear Log", role: .destructive) { activity.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the list in this app. Your emails and Claude chats are not touched.")
        }
    }

    private func openChat(_ entry: ActivityEntry) {
        Task {
            do {
                try await ClaudeBridge.reveal(entry.destination.target)
            } catch {
                let panel = NSAlert()
                panel.messageText = "eMail to Claude"
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
                Text("Accessibility lets eMail to Claude read Claude's chat list and paste into it.")
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
            Section {
                TextField("License key", text: $store.config.licenseKey, prompt: Text("EMC-XXXXX-XXXXX-XXXXX-XXXXX"))
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Status") { licenseStatus }
            } header: {
                Text("License")
            } footer: {
                Text("Your license is checked about once a week, when the app looks for updates. A valid license lets you download updates. The app itself keeps working either way.")
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
        .alert("Erase your data on the server?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) { Task { await updates.erase() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes everything stored about this install, including your device ID, and starts a new one. Your license key stays valid.")
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
        window.title = "eMail to Claude Settings"
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
