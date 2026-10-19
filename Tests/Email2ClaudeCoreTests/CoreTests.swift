import XCTest
@testable import Email2ClaudeCore

final class CoreTests: XCTestCase {
    private func email(to: [String], cc: [String] = []) -> Email {
        Email(sender: "Bob <bob@x.com>", subject: "Hi", date: "today",
              to: to, cc: cc, body: "Body", attachmentPaths: ["/tmp/a/invoice.pdf"])
    }

    // MARK: Routing

    func testNormalize() {
        XCTAssertEqual(Router.normalize("Ann Lee <Ann@Work.COM>"), "ann@work.com")
        XCTAssertEqual(Router.normalizeRule(" @Acme.COM "), "acme.com")
        XCTAssertEqual(Router.domain(of: "a@b.co.uk"), "b.co.uk")
        XCTAssertNil(Router.domain(of: "nodomain"))
    }

    func testDomainRouteMatchesAnyPersonAndSubdomains() {
        let config = Config(routes: [Route(domain: "acme.com", kind: .project, name: "Acme")])
        for to in ["me@acme.com", "Jane <jane@Acme.com>", "x@mail.acme.com"] {
            XCTAssertEqual(Router.route(for: email(to: [to]), config: config)?.name, "Acme", to)
        }
        XCTAssertNil(Router.route(for: email(to: ["x@notacme.com"]), config: config))
        XCTAssertNil(Router.route(for: email(to: ["x@other.com"]), config: config))
    }

    func testAnyToRecipientCanMatch() {
        let config = Config(routes: [Route(domain: "acme.com", kind: .newChat)])
        XCTAssertNotNil(Router.route(for: email(to: ["me@mine.com", "jane@acme.com"]), config: config))
    }

    func testAddressRuleBeatsDomainRule() {
        var config = Config()
        config.upsert(Route(domain: "gmail.com", kind: .chat, name: "Everyone"))
        config.upsert(Route(domain: "Jane@Gmail.com", kind: .chat, name: "Jane"))
        XCTAssertEqual(Router.route(for: email(to: ["jane@gmail.com"]), config: config)?.name, "Jane")
        XCTAssertEqual(Router.route(for: email(to: ["bob@gmail.com"]), config: config)?.name, "Everyone")
    }

    func testOnlyToIsMatchedNotCc() {
        let config = Config(routes: [Route(domain: "acme.com")])
        XCTAssertNil(Router.route(for: email(to: ["z@other.com"], cc: ["dev@acme.com"]), config: config))
    }

    func testUnknownAddress() {
        let config = Config(routes: [Route(domain: "known.com")])
        XCTAssertEqual(Router.unknownAddress(for: email(to: ["New <New@X.com>", "other@x.com"]), config: config), "new@x.com")
        XCTAssertNil(Router.unknownAddress(for: email(to: ["a@known.com"]), config: config))
    }

    func testUpsertReplacesSameDomain() {
        var config = Config()
        config.upsert(Route(domain: " @A.com ", kind: .chat, name: "one"))
        config.upsert(Route(domain: "a.com", kind: .incognito))
        XCTAssertEqual(config.routes, [Route(domain: "a.com", kind: .incognito)])
    }

    // MARK: Targets

    func testTargets() {
        XCTAssertEqual(Route(domain: "a", kind: .chat, name: "T", url: "https://claude.ai/chat/1").target,
                       .link(URL(string: "claude://claude.ai/chat/1")!))
        XCTAssertEqual(Route(domain: "a", kind: .chat, name: "T").target, .sidebar(title: "T"))
        XCTAssertEqual(Route(domain: "a", kind: .chat, url: "garbage").target, .newChat)
        XCTAssertEqual(Route(domain: "a", kind: .project, name: "P").target, .project(name: "P", link: nil))
        XCTAssertEqual(Route(domain: "a", kind: .project, url: "https://claude.ai/project/9").target,
                       .project(name: "", link: URL(string: "claude://claude.ai/project/9")!))
        XCTAssertEqual(Route(domain: "a", kind: .project).target, .newChat)
        XCTAssertEqual(Route(domain: "a", kind: .incognito).target, .incognito)
    }

    func testChatLink() {
        XCTAssertEqual(ChatLink.appURL(from: "https://claude.ai/chat/abc")?.absoluteString, "claude://claude.ai/chat/abc")
        XCTAssertEqual(ChatLink.appURL(from: "claude://claude.ai/chat/abc")?.absoluteString, "claude://claude.ai/chat/abc")
        XCTAssertNil(ChatLink.appURL(from: "https://example.com/chat/abc"))
    }

    // MARK: Prompt & actions

    func testPrompt() {
        let text = email(to: ["me@x.com"]).prompt(instruction: "Reply please")
        XCTAssertTrue(text.hasPrefix("Reply please\n\nFrom: Bob <bob@x.com>"))
        XCTAssertTrue(text.contains("Attachments: invoice.pdf"))
        XCTAssertTrue(email(to: ["me@x.com"]).prompt(instruction: "").hasPrefix("From: Bob"))
    }

    func testActionSlots() {
        XCTAssertEqual(Action.allCases.count, 6)
        XCTAssertEqual(Set(Action.allCases.map(\.keyEquivalent)).count, 6)
        XCTAssertEqual(Action.reply.shortcutLabel, "⌥⌘R")
        XCTAssertEqual(Action.custom1.shortcutLabel, "⌥⌘1")
        XCTAssertEqual(Action.pasteOnly.defaultMode, .pasteOnly)
    }

    func testActionDefaultsAndOverrides() {
        var config = Config()
        XCTAssertEqual(config.name(for: .summary), "Summary & Next Steps")
        XCTAssertEqual(config.mode(for: .summary), .prompt)
        XCTAssertEqual(config.instruction(for: .summary), Action.summary.defaultInstruction)

        config.setName("Brief", for: .summary)
        config.setMode(.pasteOnly, for: .summary)
        config.setInstruction("Mine", for: .summary)
        XCTAssertEqual(config.name(for: .summary), "Brief")
        XCTAssertEqual(config.mode(for: .summary), .pasteOnly)
        XCTAssertEqual(config.instruction(for: .summary), "Mine")

        config.setName("Summary & Next Steps", for: .summary)
        config.setMode(.prompt, for: .summary)
        config.setInstruction(Action.summary.defaultInstruction, for: .summary)
        XCTAssertTrue(config.actions.isEmpty, "defaults are not stored")
    }

    func testResetAction() {
        var config = Config()
        config.setName("X", for: .reply)
        config.resetAction(.reply)
        XCTAssertEqual(config.name(for: .reply), "Draft a Reply")
    }

    func testIsConfigured() {
        var config = Config()
        XCTAssertTrue(config.isConfigured(.reply))
        XCTAssertTrue(config.isConfigured(.pasteOnly))
        XCTAssertFalse(config.isConfigured(.custom1), "custom slots start empty")
        config.setName("Translate", for: .custom1)
        XCTAssertFalse(config.isConfigured(.custom1), "a prompt action needs a prompt")
        config.setInstruction("Translate to Dutch", for: .custom1)
        XCTAssertTrue(config.isConfigured(.custom1))
        config.setInstruction("", for: .custom1)
        config.setMode(.pasteOnly, for: .custom1)
        XCTAssertTrue(config.isConfigured(.custom1), "paste-only needs only a name")
    }

    // MARK: Persistence

    func testConfigRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2c-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Config()
        config.upsert(Route(domain: "a.com", kind: .project, name: "P", url: "https://claude.ai/project/1"))
        config.setInstruction("X", for: .reply)
        config.setName("Custom", for: .custom2)
        config.askForUnknownRoutes = false
        try config.save(to: url)
        XCTAssertEqual(Config.load(from: url), config)
    }

    func testPartialJSONUsesDefaults() throws {
        let partial = try JSONDecoder().decode(Config.self, from: Data(#"{"autoSend":false}"#.utf8))
        XCTAssertFalse(partial.autoSend)
        XCTAssertEqual(partial.openDelay, 1.0)
        XCTAssertTrue(partial.askForUnknownRoutes)
        XCTAssertTrue(partial.keepActivityLog)
    }

    func testLegacyRoutesStillDecode() throws {
        let json = #"{"routes":[{"address":"@acme.com","chatTitle":"Acme chat"},{"address":"x@y.com"}],"instruction":"old"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.routes[0].kind, .chat)
        XCTAssertEqual(config.routes[0].name, "Acme chat")
        XCTAssertEqual(config.routes[1].kind, .newChat)
        let email = Email(sender: "", subject: "", date: "", to: ["bob@acme.com"], cc: [], body: "", attachmentPaths: [])
        XCTAssertEqual(Router.route(for: email, config: config)?.name, "Acme chat")
        XCTAssertEqual(config.instruction(for: .reply), "old", "legacy prompt text carries over")
        XCTAssertEqual(config.name(for: .reply), "Draft a Reply")
    }

    // MARK: Activity log

    func testMailLink() {
        XCTAssertEqual(MailLink.url(messageID: "ABC@host.com")?.absoluteString, "message://%3CABC%40host.com%3E")
        XCTAssertEqual(MailLink.url(messageID: " <ABC@host.com> ")?.absoluteString, "message://%3CABC%40host.com%3E")
        XCTAssertNil(MailLink.url(messageID: "  "))
    }

    private func entry(subject: String, sender: String = "bob@x.com", rule: String = "acme.com",
                       destination: Route = Route(domain: "acme.com", kind: .project, name: "Acme"),
                       action: String = "Draft a Reply") -> ActivityEntry {
        ActivityEntry(subject: subject, sender: sender, messageID: "id@x", rule: rule,
                      destination: destination, actionName: action, mode: .prompt, prompt: "Do it")
    }

    func testActivitySearch() {
        let e = entry(subject: "Quarterly Invoice")
        XCTAssertTrue(e.matches(""))
        XCTAssertTrue(e.matches("invoice"))
        XCTAssertTrue(e.matches("INVOICE bob acme"))
        XCTAssertTrue(e.matches("project"), "searches the route text")
        XCTAssertTrue(e.matches("reply"), "searches the action name")
        XCTAssertFalse(e.matches("invoice zebra"))
    }

    func testActivityRouteText() {
        XCTAssertEqual(entry(subject: "s").routeText, "acme.com → New chat in project: Acme")
        let none = entry(subject: "s", rule: "", destination: Route(domain: "", kind: .newChat))
        XCTAssertEqual(none.routeText, "No route · New chat each time")
        XCTAssertTrue(entry(subject: "s").canOpenChat)
        XCTAssertFalse(none.canOpenChat)
        XCTAssertFalse(entry(subject: "s", destination: Route(domain: "a", kind: .incognito)).canOpenChat)
    }

    func testActivityFileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2c-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ActivityFile.load(from: url), [])
        let first = entry(subject: "One"), second = entry(subject: "Two")
        try ActivityFile.append(first, to: url)
        try ActivityFile.append(second, to: url)
        try Data("not json\n".utf8).appendTo(url)
        let loaded = ActivityFile.load(from: url)
        XCTAssertEqual(loaded.map(\.subject), ["One", "Two"])
        XCTAssertEqual(loaded[0].destination, first.destination)
    }
}

private extension Data {
    func appendTo(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}
