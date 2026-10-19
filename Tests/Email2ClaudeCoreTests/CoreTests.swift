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

    // MARK: From routes and precedence

    private func received(from sender: String, to: [String] = ["me@mine.com"], account: [String] = ["me@mine.com"]) -> Email {
        Email(sender: sender, subject: "Hi", date: "today", to: to, cc: [], body: "Body",
              attachmentPaths: [], accountAddresses: account)
    }

    func testFromRouteMatchesSenderWhateverToSays() {
        let config = Config(routes: [Route(domain: "acme.com", matchOn: .from, kind: .project, name: "Acme")])
        XCTAssertEqual(Router.route(for: received(from: "Jane <jane@acme.com>"), config: config)?.name, "Acme")
        XCTAssertEqual(Router.route(for: received(from: "x@mail.acme.com"), config: config)?.name, "Acme")
        XCTAssertNil(Router.route(for: received(from: "jane@other.com"), config: config))
    }

    func testFromRuleDoesNotLookAtTo() {
        let config = Config(routes: [Route(domain: "acme.com", matchOn: .from, kind: .newChat)])
        XCTAssertNil(Router.route(for: received(from: "me@mine.com", to: ["jane@acme.com"]), config: config))
    }

    func testToRuleDoesNotLookAtFrom() {
        let config = Config(routes: [Route(domain: "acme.com", matchOn: .to, kind: .newChat)])
        XCTAssertNil(Router.route(for: received(from: "jane@acme.com"), config: config))
    }

    func testOneClientNeedsOneRulePerDirection() {
        let config = Config(routes: [
            Route(domain: "acme.com", matchOn: .from, kind: .chat, name: "Acme"),
            Route(domain: "acme.com", matchOn: .to, kind: .chat, name: "Acme"),
        ])
        XCTAssertNotNil(Router.route(for: received(from: "jane@acme.com"), config: config))
        XCTAssertNotNil(Router.route(for: received(from: "me@mine.com", to: ["jane@acme.com"]), config: config))
    }

    func testAddressRuleBeatsDomainRuleAcrossFields() {
        let config = Config(routes: [
            Route(domain: "acme.com", matchOn: .from, kind: .chat, name: "Everyone"),
            Route(domain: "jane@acme.com", matchOn: .to, kind: .chat, name: "Jane"),
        ])
        let email = received(from: "bob@acme.com", to: ["jane@acme.com"])
        XCTAssertEqual(Router.route(for: email, config: config)?.name, "Jane")
    }

    func testListOrderDecidesBetweenEqualRules() {
        let mail = received(from: "jane@mail.acme.com")
        var config = Config(routes: [
            Route(domain: "mail.acme.com", matchOn: .from, kind: .chat, name: "Specific"),
            Route(domain: "acme.com", matchOn: .from, kind: .chat, name: "General"),
        ])
        XCTAssertEqual(Router.route(for: mail, config: config)?.name, "Specific")
        config.routes.reverse()
        XCTAssertEqual(Router.route(for: mail, config: config)?.name, "General", "reordering changes the winner")
    }

    func testMatchReportsTheAddressThatMatched() {
        let config = Config(routes: [Route(domain: "acme.com", matchOn: .from, kind: .newChat)])
        let hit = Router.match(for: received(from: "Jane <Jane@Acme.com>"), config: config)
        XCTAssertEqual(hit?.address, "jane@acme.com")
        XCTAssertEqual(hit?.route.matchOn, .from)
    }

    func testOverlapsFlagsNestedDomainsOnTheSameField() {
        let a = Route(domain: "acme.com", matchOn: .from), b = Route(domain: "mail.acme.com", matchOn: .from)
        XCTAssertTrue(Router.overlaps(a, b))
        XCTAssertFalse(Router.overlaps(a, Route(domain: "mail.acme.com", matchOn: .to)), "different fields")
        XCTAssertFalse(Router.overlaps(a, Route(domain: "jane@acme.com", matchOn: .from)), "an address rule beats a domain on purpose")
        XCTAssertFalse(Router.overlaps(a, Route(domain: "other.com", matchOn: .from)))
        XCTAssertFalse(Router.overlaps(a, a))
    }

    func testSuggestionOffersSenderForReceivedMail() {
        let suggestion = Router.suggestion(for: received(from: "Jane <jane@acme.com>"), config: Config())
        XCTAssertEqual(suggestion?.field, .from)
        XCTAssertEqual(suggestion?.fromAddress, "jane@acme.com")
        XCTAssertEqual(suggestion?.toAddress, "me@mine.com")
    }

    func testSuggestionOffersRecipientForSentMail() {
        let sent = received(from: "Me <me@mine.com>", to: ["jane@acme.com"])
        XCTAssertEqual(Router.suggestion(for: sent, config: Config())?.field, .to)
    }

    func testSuggestionDefaultsToToWhenTheAccountIsUnknown() {
        let unknown = received(from: "jane@acme.com", account: [])
        XCTAssertEqual(Router.suggestion(for: unknown, config: Config())?.field, .to)
        let noRecipient = Email(sender: "jane@acme.com", subject: "", date: "", to: [], cc: [], body: "", attachmentPaths: [])
        XCTAssertEqual(Router.suggestion(for: noRecipient, config: Config())?.field, .from)
    }

    func testNoSuggestionWhenARouteMatches() {
        let config = Config(routes: [Route(domain: "acme.com", matchOn: .from)])
        XCTAssertNil(Router.suggestion(for: received(from: "jane@acme.com"), config: config))
    }

    // MARK: Route instructions

    func testInstructionsAreAddedAfterTheActionPrompt() {
        let text = PromptBuilder.compose(actionPrompt: "Draft a reply.", routeInstructions: "  Reply formally, in Dutch.  ")
        XCTAssertEqual(text, "Draft a reply.\n\nStanding instructions for this client:\nReply formally, in Dutch.")
    }

    func testRoutesWithoutInstructionsLeaveThePromptAlone() {
        XCTAssertEqual(PromptBuilder.compose(actionPrompt: "Draft a reply.", routeInstructions: nil), "Draft a reply.")
        XCTAssertEqual(PromptBuilder.compose(actionPrompt: "Draft a reply.", routeInstructions: "   "), "Draft a reply.")
    }

    func testInstructionsWorkWithoutAnActionPrompt() {
        XCTAssertEqual(PromptBuilder.compose(actionPrompt: "", routeInstructions: "Be brief."),
                       "Standing instructions for this client:\nBe brief.")
    }

    func testRouteFieldAndInstructionsSurviveSaving() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2c-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Config()
        config.upsert(Route(domain: "acme.com", matchOn: .from, kind: .project, name: "Acme", instructions: "Formal Dutch."))
        try config.save(to: url)
        let loaded = Config.load(from: url)
        XCTAssertEqual(loaded.routes.first?.matchOn, .from)
        XCTAssertEqual(loaded.routes.first?.instructions, "Formal Dutch.")
    }

    func testRoutesWrittenBeforeFromRoutingAreToRoutes() throws {
        let json = #"{"routes":[{"domain":"acme.com","kind":"chat","name":"Acme"}]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.routes.first?.matchOn, .to)
        XCTAssertNil(config.routes.first?.instructions)
    }

    func testUpsertReplacesSameDomain() {
        var config = Config()
        config.upsert(Route(domain: " @A.com ", kind: .chat, name: "one"))
        config.upsert(Route(domain: "a.com", kind: .incognito))
        XCTAssertEqual(config.routes, [Route(domain: "a.com", kind: .incognito)])
    }

    func testEditingARouteKeepsItsPlaceInTheList() {
        var config = Config(routes: [Route(domain: "a.com"), Route(domain: "b.com"), Route(domain: "c.com")])
        config.replace(Route(domain: "b.com"), with: Route(domain: "B2.com", matchOn: .from, kind: .incognito))
        XCTAssertEqual(config.routes.map(\.domain), ["a.com", "b2.com", "c.com"])
        XCTAssertEqual(config.routes[1].matchOn, .from)
    }

    func testEditingARouteOntoAnotherReplacesThatOne() {
        var config = Config(routes: [Route(domain: "a.com"), Route(domain: "b.com"), Route(domain: "c.com")])
        config.replace(Route(domain: "c.com"), with: Route(domain: "a.com", kind: .incognito))
        XCTAssertEqual(config.routes.map(\.domain), ["b.com", "a.com"], "the edited route keeps its own place")
        XCTAssertEqual(config.routes.count, 2)
        XCTAssertEqual(config.routes.filter { $0.domain == "a.com" }.count, 1)
        XCTAssertEqual(config.routes.first { $0.domain == "a.com" }?.kind, .incognito)
    }

    func testUpsertKeepsFromAndToRoutesApart() {
        var config = Config()
        config.upsert(Route(domain: "a.com", matchOn: .to, kind: .chat, name: "to"))
        config.upsert(Route(domain: "a.com", matchOn: .from, kind: .chat, name: "from"))
        XCTAssertEqual(config.routes.count, 2)
        config.upsert(Route(domain: "A.com", matchOn: .from, kind: .chat, name: "from2"))
        XCTAssertEqual(config.routes.count, 2)
        XCTAssertEqual(config.routes.first { $0.matchOn == .from }?.name, "from2")
        XCTAssertNotEqual(config.routes[0].id, config.routes[1].id)
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
        XCTAssertEqual(ChatLink.appURL(from: "https://chatgpt.com/c/abc")?.absoluteString, "https://chatgpt.com/c/abc")
        XCTAssertEqual(ChatLink.appURL(from: "  https://example.com/chat/abc\n")?.absoluteString, "https://example.com/chat/abc")
        XCTAssertNil(ChatLink.appURL(from: "not a link"))
        XCTAssertNil(ChatLink.appURL(from: "ftp://example.com/x"))
        XCTAssertNil(ChatLink.appURL(from: "https://"))
    }

    func testWebTargetsOpenInTheBrowser() throws {
        let web = Route(domain: "a.com", kind: .chat, name: nil, url: "https://chatgpt.com/c/abc")
        XCTAssertEqual(web.target.webURL?.absoluteString, "https://chatgpt.com/c/abc")
        let claude = Route(domain: "a.com", kind: .chat, name: nil, url: "https://claude.ai/chat/abc")
        XCTAssertNil(claude.target.webURL, "claude.ai links still open in the desktop app")
        let project = Route(domain: "a.com", kind: .project, name: "P", url: "https://chatgpt.com/g/g-p-1/project")
        XCTAssertNotNil(project.target.webURL)
        XCTAssertNil(ChatTarget.newChat.webURL)
        XCTAssertNil(ChatTarget.sidebar(title: "x").webURL)
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
        XCTAssertEqual(config.instruction(for: .reply), "old", "the original single prompt becomes the reply prompt")
        XCTAssertEqual(config.name(for: .reply), "Draft a Reply")

        let perAction = try JSONDecoder().decode(
            Config.self, from: Data(#"{"instructions":{"summary":"sum","reply":"rep"}}"#.utf8))
        XCTAssertEqual(perAction.instruction(for: .summary), "sum")
        XCTAssertEqual(perAction.instruction(for: .reply), "rep")
    }

    // MARK: Check-in and updates

    func testVersionOrdering() {
        XCTAssertTrue(AppVersion.isNewer("0.10.0", than: "0.9.2"))
        XCTAssertTrue(AppVersion.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(AppVersion.isNewer("1.0.0", than: "1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertEqual(AppVersion.compare("2.0.1", "2.0.1"), .orderedSame)
        XCTAssertTrue(Checkin.meetsMinimum(system: "14.1", minimum: "13.0"))
        XCTAssertFalse(Checkin.meetsMinimum(system: "12.7.4", minimum: "13.0"))
        XCTAssertTrue(Checkin.meetsMinimum(system: "13.0", minimum: nil))
    }

    func testRequestUsesSnakeCaseKeys() throws {
        let request = CheckinRequest(
            deviceId: "11111111-1111-1111-1111-111111111111", event: .updateCheck, analytics: true,
            wantsUpdate: true, appVersion: "0.1.0", macosVersion: "14.1", osLanguage: "en-NL", licenseKey: "EMC-1")
        let object = try JSONSerialization.jsonObject(with: Checkin.encoder.encode(request)) as? [String: Any]
        XCTAssertEqual(object?["device_id"] as? String, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(object?["event"] as? String, "update_check")
        XCTAssertEqual(object?["wants_update"] as? Bool, true)
        XCTAssertEqual(object?["macos_version"] as? String, "14.1")
        XCTAssertEqual(object?["os_language"] as? String, "en-NL")
        XCTAssertEqual(object?["license_key"] as? String, "EMC-1")
        XCTAssertNotNil(object?["app_version"])
    }

    func testResponseDecoding() throws {
        let full = #"{"ok":true,"license":"valid","latest_version":"0.2.0","update":{"version":"0.2.0","notes":null,"sha256":"ab","min_macos":"13.0","url":"https://x.supabase.co/signed?token=1"}}"#
        let response = try Checkin.decoder.decode(CheckinResponse.self, from: Data(full.utf8))
        XCTAssertEqual(response.license, "valid")
        XCTAssertEqual(response.update?.version, "0.2.0")
        XCTAssertEqual(response.update?.minMacos, "13.0")
        XCTAssertNil(response.update?.notes)
        XCTAssertNil(response.updateBlocked)

        let blocked = #"{"ok":true,"license":"missing","latest_version":"0.2.0","update_blocked":{"version":"0.2.0","reason":"missing"}}"#
        let withheld = try Checkin.decoder.decode(CheckinResponse.self, from: Data(blocked.utf8))
        XCTAssertNil(withheld.update)
        XCTAssertEqual(withheld.updateBlocked?.reason, "missing")

        let plain = try Checkin.decoder.decode(CheckinResponse.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertNil(plain.license)
    }

    func testEmailAddressCheck() {
        XCTAssertTrue(EmailAddress.isPlausible("jane@acme.com"))
        XCTAssertTrue(EmailAddress.isPlausible("  Jane.Doe+news@mail.acme.co.uk "))
        XCTAssertFalse(EmailAddress.isPlausible(""))
        XCTAssertFalse(EmailAddress.isPlausible("jane"))
        XCTAssertFalse(EmailAddress.isPlausible("jane@acme"))
        XCTAssertFalse(EmailAddress.isPlausible("@acme.com"))
        XCTAssertFalse(EmailAddress.isPlausible("jane@@acme.com"))
        XCTAssertFalse(EmailAddress.isPlausible("jane doe@acme.com"))
        XCTAssertFalse(EmailAddress.isPlausible("jane@acme..com"))
        XCTAssertFalse(EmailAddress.isPlausible("jane@acme.c"))
        XCTAssertEqual(EmailAddress.normalize("  Jane@Acme.COM "), "jane@acme.com")
    }

    func testRegisterRequestAndResponse() throws {
        var request = CheckinRequest(
            deviceId: "11111111-1111-1111-1111-111111111111", event: .open, analytics: false,
            wantsUpdate: false, appVersion: "0.1.3", macosVersion: "14.1", osLanguage: "en", licenseKey: "")
        request.action = "register"
        request.email = "jane@acme.com"
        let object = try JSONSerialization.jsonObject(with: Checkin.encoder.encode(request)) as? [String: Any]
        XCTAssertEqual(object?["action"] as? String, "register")
        XCTAssertEqual(object?["email"] as? String, "jane@acme.com")

        let json = #"{"ok":true,"license":"valid","license_key":"EMC-AAAAA-BBBBB-CCCCC-DDDDD"}"#
        let response = try Checkin.decoder.decode(CheckinResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.licenseKey, "EMC-AAAAA-BBBBB-CCCCC-DDDDD")
    }

    func testLicenseEmailPersistsAndOldConfigsDefault() throws {
        var config = Config()
        XCTAssertEqual(config.licenseEmail, "")
        XCTAssertFalse(config.emailPromptShown)
        config.licenseEmail = "jane@acme.com"
        config.emailPromptShown = true
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: data), config)
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"licenseKey":"EMC-1"}"#.utf8))
        XCTAssertEqual(old.licenseEmail, "")
        XCTAssertFalse(old.emailPromptShown)
    }

    func testDonationRequestAppearsOnceAfterTwentyEmails() throws {
        var config = Config()
        var shown: [Int] = []
        for n in 1...60 where config.recordDelivery() { shown.append(n) }
        XCTAssertEqual(shown, [21], "once, on the delivery after the 20th")
        XCTAssertTrue(config.donatePromptShown)

        // The count and the shown flag survive a restart, and old configs start at zero.
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.emailsSent, 60)
        XCTAssertTrue(decoded.donatePromptShown)
        var restarted = decoded
        XCTAssertFalse(restarted.recordDelivery())
        let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertEqual(old.emailsSent, 0)
        XCTAssertFalse(old.donatePromptShown)
    }

    func testPrivacyAndLicenseSettingsPersist() throws {
        var config = Config()
        XCTAssertEqual(config.analyticsChoice, .unset, "nothing is shared until the user answers")
        config.analyticsChoice = .shared
        config.licenseKey = "EMC-AAAAA"
        config.lastLicenseStatus = "valid"
        config.lastUpdateCheck = Date(timeIntervalSince1970: 1_800_000_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2c-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.save(to: url)
        XCTAssertEqual(Config.load(from: url), config)
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
        XCTAssertEqual(entry(subject: "s").routeText, "To acme.com → New chat in project: Acme")
        let fromRoute = entry(subject: "s", destination: Route(domain: "acme.com", matchOn: .from, kind: .newChat))
        XCTAssertEqual(fromRoute.routeText, "From acme.com → New chat each time")
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
