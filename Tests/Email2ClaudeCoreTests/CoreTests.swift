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

    func testActions() {
        XCTAssertEqual(Set(Action.allCases.map(\.keyEquivalent)).count, Action.allCases.count)
        XCTAssertFalse(Action.pasteOnly.sendsAutomatically)
        XCTAssertTrue(Action.reply.sendsAutomatically)
        XCTAssertEqual(Action.reply.shortcutLabel, "⌥⌘R")
        XCTAssertEqual(Action.pasteOnly.defaultInstruction, "")
    }

    func testInstructionOverrides() {
        var config = Config()
        XCTAssertEqual(config.instruction(for: .summary), Action.summary.defaultInstruction)
        config.setInstruction("Mine", for: .summary)
        XCTAssertEqual(config.instruction(for: .summary), "Mine")
        config.setInstruction(Action.summary.defaultInstruction, for: .summary)
        XCTAssertTrue(config.instructions.isEmpty)
    }

    // MARK: Persistence

    func testConfigRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2c-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Config()
        config.upsert(Route(domain: "a.com", kind: .project, name: "P", url: "https://claude.ai/project/1"))
        config.setInstruction("X", for: .reply)
        try config.save(to: url)
        XCTAssertEqual(Config.load(from: url), config)
    }

    func testPartialJSONUsesDefaults() throws {
        let partial = try JSONDecoder().decode(Config.self, from: Data(#"{"autoSend":false}"#.utf8))
        XCTAssertFalse(partial.autoSend)
        XCTAssertEqual(partial.openDelay, 1.0)
    }

    func testLegacyRoutesStillDecode() throws {
        let json = #"{"routes":[{"address":"@acme.com","chatTitle":"Acme chat"},{"address":"x@y.com"}],"instruction":"old"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.routes[0].kind, .chat)
        XCTAssertEqual(config.routes[0].name, "Acme chat")
        XCTAssertEqual(config.routes[1].kind, .newChat)
        let email = Email(sender: "", subject: "", date: "", to: ["bob@acme.com"], cc: [], body: "", attachmentPaths: [])
        XCTAssertEqual(Router.route(for: email, config: config)?.name, "Acme chat")
    }
}
