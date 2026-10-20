import Foundation

/// Claude's sidebar rows, sorted into something a person can pick from.
///
/// The accessibility tree gives one flat list of row labels: Claude's own navigation (New, Scheduled,
/// Design, Pinned, View all), projects, a "Toggle sessions for <project>" button after each project,
/// the chats inside that project, and then the recent chats. This sorts them: navigation and toggle
/// buttons are dropped, and chats are grouped under the project they sit in, with the rest last.
public struct ChatList: Equatable {
    public struct Group: Equatable, Identifiable {
        /// nil for chats that aren't inside a project (the recent chats).
        public var project: String?
        public var chats: [String]
        public var id: String { project ?? "" }
    }

    /// Project groups in sidebar order, then the chats that aren't in a project.
    public var groups: [Group]
    public var projects: [String]

    public var chats: [String] { groups.flatMap(\.chats) }
    public var isEmpty: Bool { chats.isEmpty }

    public init(groups: [Group] = [], projects: [String] = []) {
        self.groups = groups
        self.projects = projects
    }

    static let toggleLead = "toggle sessions for "

    /// Sidebar rows that are Claude's own navigation, not chats.
    static let navigationLabels: Set<String> = [
        "new", "new chat", "scheduled", "design", "pinned", "view all", "recents", "projects", "chats",
        "artifacts", "search", "starred", "customize", "dispatch", "cowork", "code", "claude", "settings",
    ]

    /// Labels that end a project's run of chats, so what follows is not inside it.
    private static let sectionBreaks: Set<String> = ["pinned", "view all", "recents", "chats"]

    /// True when the rows look like Claude's Code sidebar, which has repositories with sessions and
    /// "New session in <repo>" buttons, and a Routines entry, instead of Chat's projects and chats.
    public static func looksLikeCodeSidebar(_ rows: [String]) -> Bool {
        rows.contains { row in
            let lower = row.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "routines" || lower.hasPrefix("new session in ")
        }
    }

    public static func parse(_ rows: [String]) -> ChatList {
        let labels = rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        var projects: [String] = []
        for label in labels where label.lowercased().hasPrefix(toggleLead) {
            let name = String(label.dropFirst(toggleLead.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !projects.contains(name) { projects.append(name) }
        }

        var order: [String?] = []
        var chatsByProject: [String?: [String]] = [:]
        var seen = Set<String>()
        var current: String?
        for label in labels {
            let lower = label.lowercased()
            if lower.hasPrefix(toggleLead) {
                current = String(label.dropFirst(toggleLead.count)).trimmingCharacters(in: .whitespaces)
            } else if sectionBreaks.contains(lower) {
                current = nil
            } else if navigationLabels.contains(lower) {
                continue
            } else if projects.contains(label) {
                current = label
            } else if seen.insert(label).inserted {
                if chatsByProject[current] == nil { order.append(current) }
                chatsByProject[current, default: []].append(label)
            }
        }

        let ordered = order.filter { $0 != nil } + order.filter { $0 == nil }
        let groups = ordered.map { Group(project: $0, chats: chatsByProject[$0] ?? []) }
        return ChatList(groups: groups, projects: projects)
    }
}
