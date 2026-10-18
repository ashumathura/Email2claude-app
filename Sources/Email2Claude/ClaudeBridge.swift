import AppKit
import Email2ClaudeCore

enum ClaudeError: LocalizedError {
    case notInstalled
    case noAccessibility
    case chatNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "The Claude desktop app was not found."
        case .chatNotFound(let title):
            return "Couldn't find the chat “\(title)” in Claude's sidebar. Scroll it into view, or route this address by chat link instead."
        case .noAccessibility:
            return "Accessibility permission is required to paste into Claude. Enable Email2Claude in System Settings → Privacy & Security → Accessibility."
        }
    }
}

/// Drives the Claude desktop app: opens the right chat, then pastes with synthetic keystrokes.
/// Claude has no scripting API, so this is UI automation and depends on its input box having focus.
@MainActor
enum ClaudeBridge {
    private static let bundleID = ClaudeSidebar.bundleID

    private enum Key {
        static let v: CGKeyCode = 9
        static let n: CGKeyCode = 45
        static let `return`: CGKeyCode = 36
    }

    static func accessibilityGranted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func deliver(_ email: Email, to target: ChatTarget, config: Config) async throws {
        guard accessibilityGranted(prompt: true) else { throw ClaudeError.noAccessibility }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { throw ClaudeError.notInstalled }

        let saved = PasteboardSnapshot.capture()
        defer { saved.restore() }

        await waitForModifiersReleased()
        try await openChat(target, appURL: appURL, config: config)
        try await Task.sleep(for: .seconds(config.openDelay))

        // Text first, then each attachment as a file paste so Claude attaches it.
        paste(string: email.prompt(instruction: config.instruction))
        for path in email.attachmentPaths {
            try await Task.sleep(for: .milliseconds(600))
            paste(fileURL: URL(fileURLWithPath: path))
        }
        if config.autoSend {
            try await Task.sleep(for: .milliseconds(1200 + 400 * email.attachmentPaths.count))
            press(Key.return)
        }
        try await Task.sleep(for: .milliseconds(500))  // let the last paste land before restoring the clipboard
    }

    private static func openChat(_ target: ChatTarget, appURL: URL, config: Config) async throws {
        let activation = NSWorkspace.OpenConfiguration()
        activation.activates = true
        switch target {
        case .link(let url):
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: activation)
        case .sidebar(let title):
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: activation)
            try await Task.sleep(for: .milliseconds(800))
            guard ClaudeSidebar.open(title: title) else { throw ClaudeError.chatNotFound(title) }
        case .newChat:
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: activation)
            try await Task.sleep(for: .milliseconds(500))
            press(Key.n, flags: .maskCommand)  // new chat
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func waitForModifiersReleased() async {
        let held: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        for _ in 0..<40 where !NSEvent.modifierFlags.intersection(held).isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func paste(string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        press(Key.v, flags: .maskCommand)
    }

    private static func paste(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
        press(Key.v, flags: .maskCommand)
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Saves and restores everything on the general pasteboard so the user's clipboard survives.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture() -> PasteboardSnapshot {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }
}
