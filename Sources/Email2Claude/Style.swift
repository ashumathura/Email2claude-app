import AppKit
import SwiftUI

/// The shared look of the Settings screens and the route windows: cards on the window background,
/// chips, and tip boxes. Colors come from the system or from `Brand.accent`, so they follow light and dark mode.
enum Look {
    static let cardRadius: CGFloat = 12
    static let page = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
}

/// A page title with a one-line explanation, and an optional button at the trailing edge.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// White (in dark mode, raised grey) rounded box with a thin border, for a group of related content.
struct Card<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.card, in: RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.cardRadius, style: .continuous).stroke(Look.border))
    }
}

/// A small rounded label, for a destination or a status.
struct Chip: View {
    let text: String
    var tint: Color = Brand.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// A tinted box for a tip, a warning or a good-news message.
struct TipBox<Content: View>: View {
    enum Tone {
        case info, warning, success

        var tint: Color {
            switch self {
            case .info: return Brand.accent
            case .warning: return .orange
            case .success: return .green
            }
        }
    }

    let tone: Tone
    let symbol: String?
    let content: Content

    init(_ tone: Tone = .info, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tone.tint)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tone.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tone.tint.opacity(0.35)))
    }
}

/// A choice shown as a card with a radio dot, a title and a one-line explanation.
struct OptionCard: View {
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Brand.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    if let detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Brand.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Brand.accent : Look.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small label for a keyboard shortcut.
struct ShortcutChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Look.border))
    }
}

/// A setting with a switch on the right and a short explanation under its title, in a card.
struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

/// A heading with cards under it.
struct TitledGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
    }
}

// MARK: - Grouped rows (the look of macOS System Settings)

/// A heading, a rounded group of rows, and a small note under it.
struct FormSection<Content: View>: View {
    let title: String?
    var note: String?
    var noteIsWarning = false
    let content: Content

    init(_ title: String? = nil, note: String? = nil, noteIsWarning: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.noteIsWarning = noteIsWarning
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).padding(.leading, 2)
            }
            FormGroup { content }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(noteIsWarning ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// The rounded white (dark: raised grey) box that holds rows separated by hairlines.
struct FormGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Look.border.opacity(0.6)))
    }
}

/// A hairline between two rows of a group.
struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

/// One row of a group: the label (and a line of explanation) on the left, its control on the right.
struct FormRow<Control: View>: View {
    let label: String
    var detail: String?
    let control: Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
    }
}

/// A radio choice as a row: a dot, a title and a line of explanation.
struct RadioRow: View {
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Brand.accent : Color.secondary)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A pop-up button for a row: the system menu look, sized to its content.
struct RowPicker<Value: Hashable, Options: View>: View {
    @Binding var selection: Value
    let options: Options

    init(selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        _selection = selection
        self.options = options()
    }

    var body: some View {
        Picker("", selection: $selection) { options }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
    }
}

/// A multi-line text box with a thin border, for prompts.
struct PromptEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 70

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
    }
}
