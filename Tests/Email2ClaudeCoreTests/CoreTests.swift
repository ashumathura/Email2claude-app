import XCTest
@testable import Email2ClaudeCore

final class CoreTests: XCTestCase {
    private func email(to: [String], cc: [String] = []) -> Email {
        Email(sender: "Bob <bob@x.com>", subject: "Hi", date: "today",
              to: to, cc: cc, body: "Body", attachmentPaths: ["/tmp/a/invoice.pdf"])
    }

    func testNormalize() {
        XCTAssertEqual(Router.normalize("Ann Lee <Ann@Work.COM>"), "ann@work.com")
        XCTAssertEqual(Router.normalize(" a@b.com "), "a@b.com")
    }

    func testExactAndDomainRoutes() {
        let config = Config(routes: [
            Route(address: "sales@acme.com", chatTitle: "A"),
            Route(address: "@acme.com", chatTitle: "B"),
        ])
        XCTAssertEqual(Router.route(for: email(to: ["Sales@Acme.com"]), config: config)?.chatTitle, "A")
        XCTAssertEqual(Router.route(for: email(to: ["dev@acme.com"]), config: config)?.chatTitle, "B")
        XCTAssertNil(Router.route(for: email(to: ["z@other.com"]), config: config))
    }

    func testOnlyToIsMatchedNotCc() {
        let config = Config(routes: [Route(address: "dev@acme.com", chatTitle: "B")])
        XCTAssertNil(Router.route(for: email(to: ["z@other.com"], cc: ["dev@acme.com"]), config: config))
    }

    func testUnknownAddress() {
        let config = Config(routes: [Route(address: "known@x.com", chatTitle: "K")])
        XCTAssertEqual(Router.unknownAddress(for: email(to: ["New <New@X.com>", "other@x.com"]), config: config), "new@x.com")
        XCTAssertNil(Router.unknownAddress(for: email(to: ["known@x.com"]), config: config))
    }

    func testTargetPrefersLinkOverTitle() {
        XCTAssertEqual(Route(address: "a", chatTitle: "T", chatURL: "https://claude.ai/chat/1").target,
                       .link(URL(string: "claude://claude.ai/chat/1")!))
        XCTAssertEqual(Route(address: "a", chatTitle: "T").target, .sidebar(title: "T"))
        XCTAssertEqual(Route(address: "a", chatURL: "garbage").target, .newChat)
    }

    func testUpsertReplacesSameAddress() {
        var config = Config()
        config.upsert(Route(address: " A@B.com ", chatTitle: "one"))
        config.upsert(Route(address: "a@b.com", chatTitle: "two"))
        XCTAssertEqual(config.routes, [Route(address: "a@b.com", chatTitle: "two")])
    }

    func testChatLink() {
        XCTAssertEqual(ChatLink.appURL(from: "https://claude.ai/chat/abc")?.absoluteString, "claude://claude.ai/chat/abc")
        XCTAssertEqual(ChatLink.appURL(from: "claude://claude.ai/chat/abc")?.absoluteString, "claude://claude.ai/chat/abc")
        XCTAssertNil(ChatLink.appURL(from: "https://example.com/chat/abc"))
    }

    func testPrompt() {
        let text = email(to: ["me@x.com"]).prompt(instruction: "Reply please")
        XCTAssertTrue(text.hasPrefix("Reply please\n\nFrom: Bob <bob@x.com>"))
        XCTAssertTrue(text.contains("Attachments: invoice.pdf"))
    }

    func testConfigRoundTripAndPartialJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2c-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Config(); config.routes = [Route(address: "a@b.com", chatTitle: "X")]
        try config.save(to: url)
        XCTAssertEqual(Config.load(from: url), config)
        let partial = try JSONDecoder().decode(Config.self, from: Data(#"{"autoSend":false}"#.utf8))
        XCTAssertFalse(partial.autoSend)
        XCTAssertEqual(partial.openDelay, 1.5)
    }
}
