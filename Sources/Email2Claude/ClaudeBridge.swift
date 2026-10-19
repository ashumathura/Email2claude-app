import AppKit
import Email2ClaudeCore

enum ClaudeError: LocalizedError {
    case notInstalled
    case noAccessibility
    case chatNotFound(String)
    case projectNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "The Claude desktop app was not found."
        case .noAccessibility:
            return "Accessibility permission is required to paste into Claude. Enable eMail to Claude in System Settings → Privacy & Security → Accessibility."
        case .chatNotFound(let title):
            return "Couldn't find the chat “\(title)” in Claude's sidebar. Scroll it into view, or route this domain by chat link instead."
        case .projectNotFound(let name):
            return "Couldn't find the project “\(name)” in Claude. Add the project's link in Settings → Routes for a more reliable match."
        }
    }
}

/// Drives the Claude desktop app: opens the right chat, then pastes with synthetic keystrokes.
/// Claude has no scripting API, so this is UI automation and depends on its input box having focus.
@MainActor
enum ClaudeBridge {
    private enum Key {
        static let v: CGKeyCode = 9
        static let n: CGKeyCode = 45
        static let `return`: CGKeyCode = 36
    }

    nonisolated static func accessibilityGranted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func deliver(_ email: Email, to target: ChatTarget, action: Action, config: Config) async throws {
        guard accessibilityGranted(prompt: true) else { throw ClaudeError.noAccessibility }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeSidebar.bundleID)
        else { throw ClaudeError.notInstalled }

        let saved = PasteboardSnapshot.capture()
        defer { saved.restore() }
        var mark = Date()
        func lap(_ step: String) {
            Log.write("  \(step): \(Log.seconds(since: mark))")
            mark = Date()
        }

        await waitForModifiersReleased()
        try await openChat(target, appURL: appURL)
        lap("open chat")
        await waitForInputReady(minimumDelay: minimumLoadDelay(for: target, config: config))
        lap("wait for input")

        let text = email.prompt(instruction: config.instruction(for: action))
        paste(string: text)
        await waitForPasteToSettle(characters: text.count)
        lap("paste \(text.count) chars")

        for path in email.attachmentPaths {
            paste(fileURL: URL(fileURLWithPath: path))
            try await Task.sleep(for: .milliseconds(300))
        }
        if !email.attachmentPaths.isEmpty {
            try await Task.sleep(for: .seconds(uploadWait(for: email.attachmentPaths)))
            lap("attach \(email.attachmentPaths.count) files")
        }

        if action.sendsAutomatically && config.autoSend { press(Key.return) }
        try await Task.sleep(for: .milliseconds(300))  // let the last paste land before restoring the clipboard
    }

    // MARK: - Opening the destination

    private static func openChat(_ target: ChatTarget, appURL: URL) async throws {
        let activation = NSWorkspace.OpenConfiguration()
        activation.activates = true
        switch target {
        case .link(let url):
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: activation)
        case .sidebar(let title):
            try await activate(appURL)
            guard ClaudeSidebar.open(title: title) else { throw ClaudeError.chatNotFound(title) }
        case .project(let name, let link):
            if let link {
                _ = try await NSWorkspace.shared.open([link], withApplicationAt: appURL, configuration: activation)
            } else {
                try await activate(appURL)
                guard await ClaudeSidebar.openProject(named: name) else { throw ClaudeError.projectNotFound(name) }
            }
        case .incognito:
            _ = try await NSWorkspace.shared.open([ChatLink.incognitoURL], withApplicationAt: appURL, configuration: activation)
        case .newChat:
            try await activate(appURL)
            press(Key.n, flags: .maskCommand)
        }
    }

    private static func activate(_ appURL: URL) async throws {
        let activation = NSWorkspace.OpenConfiguration()
        activation.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: activation)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != ClaudeSidebar.bundleID {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(250))
    }

    // MARK: - Waiting, adaptively

    /// Navigating to a link, project or sidebar row needs time to load; a new chat does not.
    private static func minimumLoadDelay(for target: ChatTarget, config: Config) -> Double {
        if case .newChat = target { return 0.3 }
        return config.openDelay
    }

    /// Waits for the minimum load time, then until a text input has focus (up to 3 s more).
    /// The minimum matters: while a chat is still loading, the previous chat's input can have focus.
    private static func waitForInputReady(minimumDelay: Double) async {
        try? await Task.sleep(for: .seconds(minimumDelay))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, ClaudeSidebar.focusedInputLength() == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Large pastes take a while to render. Polls the input's length until it stops changing;
    /// if the accessibility tree isn't readable, falls back to a delay that scales with the text.
    private static func waitForPasteToSettle(characters: Int) async {
        guard ClaudeSidebar.focusedInputLength() != nil else {
            try? await Task.sleep(for: .milliseconds(min(2000, 300 + characters / 30)))
            return
        }
        var last = -1
        var stable = 0
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
            let length = ClaudeSidebar.focusedInputLength() ?? last
            if length == last && length > 0 {
                stable += 1
                if stable >= 2 { return }
            } else {
                stable = 0
                last = length
            }
        }
    }

    /// Submitting while files are still uploading does nothing, so give big attachments time.
    private static func uploadWait(for paths: [String]) -> Double {
        let bytes = paths.compactMap { (try? FileManager.default.attributesOfItem(atPath: $0))?[.size] as? Int }.reduce(0, +)
        return min(10, 0.4 + Double(bytes) / 4_000_000)
    }

    private static func waitForModifiersReleased() async {
        let held: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        for _ in 0..<50 where !NSEvent.modifierFlags.intersection(held).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Input

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
