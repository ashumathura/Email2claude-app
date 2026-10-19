import AppKit
import SwiftUI
import Email2ClaudeCore

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            RoutesTab(store: store)
                .tabItem { Label("Routes", systemImage: "arrow.triangle.branch") }
            PromptsTab(store: store)
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 660, height: 480)
        .tint(Brand.accent)
    }
}

// MARK: - Routes

private struct RoutesTab: View {
    @ObservedObject var store: ConfigStore
    @State private var selection: String?
    @State private var editor: EditorItem?

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
            Text("eMail to Claude looks at the domain in an email's To field and sends it to the destination you choose here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(store.config.routes) { route in
                    RouteRow(route: route).tag(route.id)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if store.config.routes.isEmpty {
                    Text("No routes yet.\nThey are added when you send an email to a new domain, or with +.")
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
                Button("Edit…") {
                    if let route = selectedRoute { editor = EditorItem(route: route, isNew: false) }
                }
                .disabled(selectedRoute == nil)
            }
        }
        .padding(20)
        .sheet(item: $editor) { item in
            RouteEditorView(
                title: item.isNew ? "Add Route" : "Edit Route",
                subtitle: "Choose the domain and where Claude should receive its emails.",
                initial: item.route,
                offersOnce: false,
                loadChats: { ClaudeSidebar.chatTitles() },
                onSave: { route in
                    if !item.isNew { store.config.routes.removeAll { $0.id == item.route.id } }
                    store.config.upsert(route)
                    selection = Router.normalizeRule(route.domain)
                    editor = nil
                },
                onCancel: { editor = nil })
        }
    }

    private func remove() {
        guard let route = selectedRoute else { return }
        store.config.routes.removeAll { $0.id == route.id }
        selection = nil
    }
}

private struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.domain).font(.body.weight(.medium))
                Text(route.destinationDescription).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @ObservedObject var store: ConfigStore
    @State private var action: Action = .reply

    private var text: Binding<String> {
        Binding(
            get: { store.config.instruction(for: action) },
            set: { store.config.setInstruction($0, for: action) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Action", selection: $action) {
                ForEach(Action.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(action.detail)
                    Spacer()
                    Text(action.shortcutLabel)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .foregroundStyle(.secondary)
            }

            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator))

            HStack {
                Text(action == .pasteOnly
                     ? "Optional text placed above the email. Paste Only never sends it for you."
                     : "This text is placed above the email in Claude.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Default") { store.config.setInstruction(action.defaultInstruction, for: action) }
                    .disabled(store.config.instruction(for: action) == action.defaultInstruction)
            }
        }
        .padding(20)
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
                Text("Draft a Reply, Summary and Deep Dive are submitted right away. Paste Only never submits, so you can add your own request first.")
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

// MARK: - Window

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: ConfigStore) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
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
