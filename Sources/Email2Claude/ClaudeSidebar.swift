import AppKit
import ApplicationServices

/// Best-effort access to Claude's UI through the Accessibility API. Claude is an Electron app with
/// no scripting interface, so this walks its UI tree. The heuristics here (sidebar width, row
/// sizes, which roles count as rows) are the part most likely to need tuning against the real app.
enum ClaudeSidebar {
    static let bundleID = "com.anthropic.claudefordesktop"

    struct Item {
        let element: AXUIElement
        let title: String
        let rect: CGRect
        let window: CGRect
        let path: [AXUIElement]  // ancestors, outermost first
    }

    private static let sidebarWidth: CGFloat = 340
    private static let rowRoles: Set<String> = ["AXButton", "AXLink", "AXStaticText", "AXRow", "AXCell", "AXMenuItem"]
    private static let inputRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    private static let chromeLabels: Set<String> = [
        "new chat", "chats", "projects", "artifacts", "search", "recents", "starred", "settings",
        "claude", "cowork", "code", "customize", "toggle sidebar", "close", "minimize", "zoom",
    ]

    enum Scope { case sidebar, window }

    static var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    // MARK: - Chats and projects

    /// What reading the sidebar produced, with a plain-language reason when there is nothing to show.
    struct ChatListResult {
        var list: ChatList
        var problem: String?
        var date = Date()
    }

    /// The chats currently visible in Claude's sidebar, grouped by project. Empty, with a reason, if
    /// Claude isn't running, Accessibility isn't granted, or the layout isn't recognised.
    static func loadChatList() -> ChatListResult {
        guard ClaudeBridge.accessibilityGranted(prompt: false) else {
            return ChatListResult(
                list: ChatList(),
                problem: "MailtoChat needs Accessibility permission to read Claude's chat list. Turn it on in System Settings.")
        }
        guard let app = runningApp else {
            return ChatListResult(list: ChatList(), problem: "Claude isn't running. Open the Claude app, then refresh.")
        }
        let list = ChatList.parse(collect(app, scope: .sidebar).filter(isChatRow).map(\.title))
        return ChatListResult(
            list: list,
            problem: list.isEmpty ? "Claude is open, but no chats were found. Keep its sidebar visible, then refresh." : nil)
    }

    /// Clicks the sidebar row with this title. Returns false if no such row was found.
    static func open(title: String) -> Bool {
        guard let app = runningApp,
              let item = collect(app, scope: .sidebar).first(where: { isChatRow($0) && $0.title == title })
        else { return false }
        return press(item)
    }

    /// Goes to the Projects page and clicks the project with this name.
    static func openProject(named name: String) async -> Bool {
        guard let app = runningApp else { return false }
        if let nav = collect(app, scope: .sidebar).first(where: { $0.title.lowercased() == "projects" }) {
            _ = press(nav)
        }
        try? await Task.sleep(for: .milliseconds(700))
        let wanted = name.lowercased()
        guard let row = collect(app, scope: .window).first(where: {
            let title = $0.title.lowercased()
            return title == wanted || title.hasPrefix(wanted + "\n")
        }) else { return false }
        return press(row)
    }

    // MARK: - Input box

    /// Length of the text in Claude's focused input box, or nil if no text input has focus
    /// (or the accessibility tree isn't available). Doubles as an "input is ready" check.
    static func focusedInputLength() -> Int? {
        guard let app = runningApp else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let focused = attribute(root, kAXFocusedUIElementAttribute) else { return nil }
        let element = focused as! AXUIElement
        guard let role = role(of: element), inputRoles.contains(role) else { return nil }
        return (attribute(element, kAXValueAttribute) as? String)?.count ?? 0
    }

    // MARK: - Tree walking

    private static func collect(_ app: NSRunningApplication, scope: Scope) -> [Item] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its accessibility tree on request.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let focused = attribute(root, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement]
        guard let window = focused ?? windows?.first, let windowFrame = frame(of: window) else { return [] }

        var items: [Item] = []
        walk(window, path: [], depth: 0) { element, path in
            guard let role = role(of: element), rowRoles.contains(role),
                  let title = label(of: element), let rect = frame(of: element) else { return }
            if scope == .sidebar, rect.minX >= windowFrame.minX + sidebarWidth || rect.maxX >= windowFrame.minX + sidebarWidth + 40 {
                return
            }
            items.append(Item(element: element, title: title, rect: rect, window: windowFrame, path: path))
        }
        return items.sorted { $0.rect.minY < $1.rect.minY }
    }

    private static func isChatRow(_ item: Item) -> Bool {
        (2...120).contains(item.title.count) && !chromeLabels.contains(item.title.lowercased())
            && item.rect.minY > item.window.minY + 40 && item.rect.height > 8 && item.rect.height < 80
    }

    /// Presses the element, or one of its nearest ancestors if the label sits on a child.
    private static func press(_ item: Item) -> Bool {
        for candidate in [item.element] + item.path.reversed().prefix(3) {
            if AXUIElementPerformAction(candidate, kAXPressAction as CFString) == .success { return true }
        }
        return false
    }

    private static func walk(
        _ element: AXUIElement, path: [AXUIElement], depth: Int,
        visit: (AXUIElement, [AXUIElement]) -> Void
    ) {
        guard depth < 30 else { return }
        visit(element, path)
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children { walk(child, path: path + [element], depth: depth + 1, visit: visit) }
    }

    // MARK: - Attribute helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    private static func label(of element: AXUIElement) -> String? {
        for name in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            if let text = (attribute(element, name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty { return text }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
