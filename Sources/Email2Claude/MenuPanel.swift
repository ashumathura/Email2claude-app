import AppKit
import SwiftUI
import Email2ClaudeCore

/// Read by the panel so it can show that an email is being sent.
@MainActor
final class MenuState: ObservableObject {
    @Published var busy = false
}

extension Action {
    /// The symbol shown beside the action in the menu-bar panel.
    var menuSymbol: String {
        switch self {
        case .reply: return "arrowshape.turn.up.left"
        case .summary: return "checklist"
        case .research: return "magnifyingglass"
        case .custom1, .custom2: return "sparkles"
        case .pasteOnly: return "doc.on.clipboard"
        }
    }
}

/// What opens from the menu-bar icon: the actions listed directly, then the app's own commands.
struct MenuPanelView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: MenuState
    let onSend: (Action) -> Void
    let onCheckUpdates: () -> Void
    let onSettings: () -> Void
    let onSupport: () -> Void
    let onQuit: () -> Void

    private var actions: [Action] { Action.allCases.filter { store.config.isConfigured($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)

            Text("Send to Claude")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            if actions.isEmpty {
                Text("No actions are set up yet. Give one a name and a prompt in Settings → Prompts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            } else {
                VStack(spacing: 2) {
                    ForEach(actions) { action in
                        ActionRow(
                            symbol: action.menuSymbol, title: store.config.name(for: action),
                            shortcut: action.shortcutLabel, disabled: state.busy
                        ) { onSend(action) }
                    }
                }
            }

            Divider().padding(.vertical, 8)
            HStack(spacing: 4) {
                IconButton(symbol: "arrow.triangle.2.circlepath", label: "Check for Updates", action: onCheckUpdates)
                IconButton(symbol: "gearshape", label: "Settings", action: onSettings)
                IconButton(symbol: "heart", label: "Support the App", action: onSupport)
                Spacer(minLength: 0)
                IconButton(symbol: "power", label: "Quit MailtoChat", action: onQuit)
            }
        }
        .padding(12)
        .frame(width: 300)
        .tint(Brand.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
            Text("MailtoChat").font(.headline)
            Spacer(minLength: 0)
            if state.busy {
                ProgressView().controlSize(.small)
                Text("Sending…").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("v" + BackendConfig.appVersion).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct ActionRow: View {
    let symbol: String
    let title: String
    let shortcut: String
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 26, height: 26)
                    .background(Brand.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                hovering && !disabled ? Brand.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(shortcut)")
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .background(
                    hovering ? Color.primary.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
