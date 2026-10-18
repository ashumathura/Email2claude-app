import AppKit
import Email2ClaudeCore

/// Settings window: the list of To address → Claude chat routes.
@MainActor
final class RoutesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let load: () -> Config
    private let save: (Config) -> Void
    private var routes: [Route] { load().routes }

    init(load: @escaping () -> Config, save: @escaping (Config) -> Void) {
        self.load = load
        self.save = save
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Email2Claude — Routes"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI(in: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        table.reloadData()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI(in window: NSWindow) {
        for (id, title, width) in [("address", "To address", 220.0), ("chat", "Claude chat", 300.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(edit)
        table.target = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let add = NSButton(title: "Add…", target: self, action: #selector(add))
        let editButton = NSButton(title: "Edit…", target: self, action: #selector(edit))
        let remove = NSButton(title: "Remove", target: self, action: #selector(remove))
        let buttons = NSStackView(views: [add, editButton, remove])
        buttons.spacing = 8

        let stack = NSStackView(views: [scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { routes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let route = routes[row]
        let text = tableColumn?.identifier.rawValue == "address" ? route.address : route.chatDescription
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    // MARK: - Actions

    @objc private func add() {
        guard case .save(let route) = ChatChooser.ask(address: nil, offerOnce: false) else { return }
        var config = load()
        config.upsert(route)
        save(config)
        table.reloadData()
    }

    @objc private func edit() {
        guard table.selectedRow >= 0 else { return }
        let existing = routes[table.selectedRow]
        guard case .save(let route) = ChatChooser.ask(address: nil, current: existing, offerOnce: false) else { return }
        var config = load()
        config.routes.removeAll { $0 == existing }
        config.upsert(route)
        save(config)
        table.reloadData()
    }

    @objc private func remove() {
        guard table.selectedRow >= 0 else { return }
        let existing = routes[table.selectedRow]
        var config = load()
        config.routes.removeAll { $0 == existing }
        save(config)
        table.reloadData()
    }
}
