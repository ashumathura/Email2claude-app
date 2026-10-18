import AppKit
import ApplicationServices

/// Best-effort access to the chat list in Claude's sidebar through the Accessibility API.
/// Claude is an Electron app with no scripting interface, so this walks its UI tree and
/// treats short text/button items in the left strip of the window as chat rows. The
/// heuristics in `isChatRow` are the part most likely to need tuning against the real app.
@MainActor
enum ClaudeSidebar {
    static let bundleID = "com.anthropic.claudefordesktop"

    private struct Item {
        let element: AXUIElement
        let title: String
        let path: [AXUIElement]  // ancestors, outermost first
    }

    private static let sidebarWidth: CGFloat = 340
    private static let rowRoles: Set<String> = ["AXButton", "AXLink", "AXStaticText", "AXRow", "AXCell", "AXMenuItem"]
    private static let chromeLabels: Set<String> = [
        "new chat", "chats", "projects", "artifacts", "search", "recents", "starred", "settings",
        "claude", "cowork", "code", "customize", "toggle sidebar", "close", "minimize", "zoom",
    ]

    static var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Chat titles currently visible in the sidebar, top to bottom. Empty if Claude isn't
    /// running, Accessibility isn't granted, or the layout isn't recognised.
    static func chatTitles() -> [String] {
        guard ClaudeBridge.accessibilityGranted(prompt: false), let app = runningApp else { return [] }
        var seen = Set<String>()
        return scan(app).map(\.title).filter { seen.insert($0).inserted }
    }

    /// Clicks the sidebar row with this title. Returns false if no such row was found.
    static func open(title: String) -> Bool {
        guard let app = runningApp, let item = scan(app).first(where: { $0.title == title }) else { return false }
        for candidate in [item.element] + item.path.reversed() {
            if AXUIElementPerformAction(candidate, kAXPressAction as CFString) == .success { return true }
        }
        return false
    }

    // MARK: - Tree walking

    private static func scan(_ app: NSRunningApplication) -> [Item] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its accessibility tree on request.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let focused = attribute(root, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement]
        guard let window = focused ?? windows?.first, let windowFrame = frame(of: window)
        else { return [] }

        var items: [Item] = []
        walk(window, path: [], depth: 0) { element, path in
            guard let title = label(of: element), let rect = frame(of: element),
                  isChatRow(title: title, role: role(of: element), rect: rect, window: windowFrame)
            else { return }
            items.append(Item(element: element, title: title, path: path))
        }
        return items.sorted { (frame(of: $0.element)?.minY ?? 0) < (frame(of: $1.element)?.minY ?? 0) }
    }

    private static func isChatRow(title: String, role: String?, rect: CGRect, window: CGRect) -> Bool {
        guard let role, rowRoles.contains(role) else { return false }
        guard (2...120).contains(title.count), !chromeLabels.contains(title.lowercased()) else { return false }
        return rect.minX < window.minX + sidebarWidth && rect.maxX < window.minX + sidebarWidth + 40
            && rect.minY > window.minY + 40 && rect.height > 8 && rect.height < 80
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
