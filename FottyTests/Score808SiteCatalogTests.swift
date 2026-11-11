import XCTest
@testable import Fotty

final class Score808SiteCatalogTests: XCTestCase {
    private let widgetID = "e35d5dc2-ac62-48de-bb53-2946ecd35042"
    private let page = "https://www.score808live.tv/score808-live-football-scores-real-time-match-updates-results/"
    private var kickoff: Date { ISO8601DateFormatter().date(from: "2026-09-04T19:00:00Z")! }

    func testTransportAllowsExactPublicCalendarIncludingFoundationPathNormalization() {
        for text in ["https://core.service.elfsight.com/p/boot/?w=test&page=test",
                     "https://core.service.elfsight.com/p/boot?w=test", page] {
            XCTAssertTrue(Score808SiteResolver.allows(URL(string: text)!), text)
        }
        for text in ["http://core.service.elfsight.com/p/boot/", "https://core.service.elfsight.com/other/",
                     "https://core.service.elfsight.com.evil.test/p/boot/", "https://user:password@core.service.elfsight.com/p/boot/",
                     "https://score808live.tv.evil.test/player"] {
            XCTAssertFalse(Score808SiteResolver.allows(URL(string: text)!), text)
        }
    }

    func testCatalogBatchSharesFixedListingAndBootWithoutFetchingSelectedWatchPage() async throws {
        var row = event(); row["actions"] = actions("https://www.score808live.tv/fixture-player-only/")
        let fixture = Score808BatchFixtureReader(listing: Data("<div class='elfsight-app-\(widgetID)'></div>".utf8),
            configuration: try JSONSerialization.data(withJSONObject: configuration([row])))
        let client = Score808CatalogClient(reader: { try await fixture.read($0) })
        let requests = [batchRequest(), batchRequest(id: "alias", home: "Ipswich"), batchRequest(id: "unsupported", category: "cricket")]
        let rows = try await client.catalogMatches(for: requests, now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed, .unsupported])
        XCTAssertTrue(rows.allSatisfy { $0.providerEventID == nil }, "Calendar URLs never become durable source IDs")
        let urls = await fixture.requests()
        XCTAssertEqual(urls.count, 2); XCTAssertEqual(urls[0], Score808SiteResolver.listingPage)
        XCTAssertEqual(urls[1].host, "core.service.elfsight.com"); XCTAssertTrue(["/p/boot", "/p/boot/"].contains(urls[1].path))
        let query = URLComponents(url: urls[1], resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "w" })?.value, widgetID)
        XCTAssertEqual(query?.first(where: { $0.name == "page" })?.value, page)
        _ = try await client.catalogMatches(for: requests, now: kickoff.addingTimeInterval(1))
        let cached = await fixture.requests(); XCTAssertEqual(cached, urls)
    }

    func testCatalogBatchMissingAndMultipleWidgetsStayUnverifiedOrConflicting() async throws {
        let html = ["<!-- <div class='elfsight-app-\(widgetID)'></div> -->",
            "<div class='elfsight-app-\(widgetID)'></div><div class='elfsight-app-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'></div>"]
        for (index, listing) in html.enumerated() {
            let fixture = Score808BatchFixtureReader(listing: Data(listing.utf8), configuration: Data())
            let client = Score808CatalogClient(reader: { try await fixture.read($0) })
            let rows = try await client.catalogMatches(for: [batchRequest()], now: kickoff)
            XCTAssertEqual(rows.map(\.outcome), [index == 0 ? .needsVerification : .conflicting])
            let reads = await fixture.requests(); XCTAssertEqual(reads, [Score808SiteResolver.listingPage])
        }
    }

    func testCatalogBatchRetainsAliasTimeAndPublisherEndGuards() async throws {
        let fixture = Score808BatchFixtureReader(listing: Data("<div class='elfsight-app-\(widgetID)'></div>".utf8),
            configuration: try JSONSerialization.data(withJSONObject: configuration([event()])))
        let client = Score808CatalogClient(reader: { try await fixture.read($0) })
        let rows = try await client.catalogMatches(for: [batchRequest(), batchRequest(id: "other-alias", home: "Ipswich Rovers"),
            batchRequest(id: "wrong-time", start: kickoff.addingTimeInterval(301)),
            batchRequest(id: "wrong-side", home: "Liverpool", away: "Ipswich Town")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .needsVerification, .needsVerification, .needsVerification])
        let ended = try await client.catalogMatches(for: [batchRequest()], now: kickoff.addingTimeInterval(7200))
        XCTAssertEqual(ended.map(\.outcome), [.needsVerification], "The publisher's explicit end remains closed inside the late-lookup window")
    }

    func testCancelledCatalogBatchCannotCacheLateListingOrStartBoot() async throws {
        let started = expectation(description: "batch listing")
        let fixture = Score808BatchFixtureReader(listing: Data("<div class='elfsight-app-\(widgetID)'></div>".utf8),
            configuration: try JSONSerialization.data(withJSONObject: configuration([event()])), pauseListing: true, started: started)
        let client = Score808CatalogClient(reader: { try await fixture.read($0) }), request = batchRequest(), now = kickoff
        let operation = Task { try await client.catalogMatches(for: [request], now: now) }
        defer { operation.cancel() }
        await fulfillment(of: [started], timeout: 2)
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled batch cannot publish") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        let cancelled = await fixture.requests(); XCTAssertEqual(cancelled, [Score808SiteResolver.listingPage])
        await fixture.resumeListing()
        let retry = try await client.catalogMatches(for: [request], now: now.addingTimeInterval(1))
        XCTAssertEqual(retry.map(\.outcome), [.listed])
        let retried = await fixture.requests(); XCTAssertEqual(retried.filter { $0 == Score808SiteResolver.listingPage }.count, 2)
    }

    func testUnsupportedAndOversizedCatalogBatchMakesNoRequests() async throws {
        let fixture = Score808BatchFixtureReader(listing: Data(), configuration: Data())
        let client = Score808CatalogClient(reader: { try await fixture.read($0) })
        let rows = try await client.catalogMatches(for: [batchRequest(category: "cricket"),
            batchRequest(id: "too-early", start: kickoff.addingTimeInterval(1801))], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.unsupported, .unsupported])
        do { _ = try await client.catalogMatches(for: Array(repeating: batchRequest(), count: 257), now: kickoff); XCTFail("Bound") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
        let reads = await fixture.requests(); XCTAssertTrue(reads.isEmpty)
    }

    func testCatalogBatchInjectedBodiesStillRespectExistingByteBound() async throws {
        let fixture = Score808BatchFixtureReader(listing: Data(repeating: 32, count: Score808SiteCatalog.maximumDocumentBytes + 1), configuration: Data())
        let client = Score808CatalogClient(reader: { try await fixture.read($0) })
        do { _ = try await client.catalogMatches(for: [batchRequest()], now: kickoff); XCTFail("Bound") }
        catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
        let reads = await fixture.requests(); XCTAssertEqual(reads.count, 1)
    }

    func testOptInCurrentProviderDiscovery() async throws {
        guard ProcessInfo.processInfo.environment["FOTTY_SCORE808_LIVE_PROBE"] == "1" else {
            throw XCTSkip("Live provider checks are explicitly opt-in, not deterministic CI.")
        }
        let now = Date()
        guard now >= kickoff.addingTimeInterval(-1800), now < kickoff.addingTimeInterval(7200) else {
            throw XCTSkip("The reported live fixture has ended; do not fabricate current acceptance.")
        }
        let request = StreamPlaybackRequest(matchID: "score808-site-live-probe",
            displayTitle: "Ipswich Town vs Liverpool", homeTeam: "Ipswich Town", awayTeam: "Liverpool",
            category: "football", kickoffDate: kickoff)
        let session = try await Score808SiteResolver().resolve(for: request, now: now)
        XCTAssertEqual(session?.playableURL, URL(string: page))
        XCTAssertEqual(session?.diagnosticMetadata["manifest_result"], "matched_site_player_page")
    }

    func testDiscoversOnlyRealWidgetClassesAndDeduplicates() {
        let html = """
        <script>const example = '<div class="elfsight-app-11111111-1111-1111-1111-111111111111">';</script>
        <!-- <div class="elfsight-app-22222222-2222-2222-2222-222222222222"> -->
        <div class="layout elfsight-app-\(widgetID)" data-elfsight-app-lazy></div>
        <section class='elfsight-app-\(widgetID)'></section>
        <div class="elfsight-app-not-a-uuid"></div>
        """
        XCTAssertEqual(Score808SiteCatalog.widgetIDs(in: html), [widgetID])
        XCTAssertEqual(Score808SiteCatalog.widgetIDs(in: "elfsight-app-\(widgetID)"), [])
    }

    func testRegisteredCalendarRequiresSameWidgetAndLiteralEventAndKeepsPageConflictGuard() throws {
        let body = try JSONSerialization.data(withJSONObject: configuration([event()]))
        func selected(_ id: String, _ data: Data? = nil) -> URL? {
            Score808SiteCatalog.matchingWatchPage(in: data ?? body, widgetID: widgetID, homeTeam: "Ipswich Town",
                awayTeam: "Liverpool", kickoff: kickoff, now: kickoff, registeredEventID: id)
        }
        let id = "score808:\(widgetID):test-event"
        XCTAssertEqual(selected(id), URL(string: page))
        XCTAssertNil(selected("score808:\(widgetID):different-event"))
        XCTAssertNil(selected("score808:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:test-event"))
        var legacy = event(); legacy["id"] = 42
        let legacyBody = try JSONSerialization.data(withJSONObject: configuration([legacy]))
        XCTAssertNil(selected(id, legacyBody), "An unregistered numeric ID is not the registered source")
        XCTAssertEqual(match(legacyBody), URL(string: page), "Adding registry identity cannot break ordinary dated legacy lookup")
        var other = event(); other["id"] = "other-event"; other["name"] = "Arsenal vs Chelsea"
        XCTAssertNil(selected(id, try JSONSerialization.data(withJSONObject: configuration([event(), other]))),
            "The same article assigned to another current programme is still rejected")
    }

    func testPublishedTimezoneRollsOverIntoPreviousUTCDay() throws {
        XCTAssertEqual(try resolve([event()]), URL(string: page))
        XCTAssertEqual(try resolve([event()], home: "Ipswich", away: "Liverpool"), URL(string: page))
    }

    func testCurrentLiverpoolChelseaOmittedVisibilityUsesPublishedDefaultAndExactUTCDate() throws {
        let row = liverpoolChelseaEvent()
        let start = ISO8601DateFormatter().date(from: "2026-10-28T20:00:00Z")!
        XCTAssertNil(row["visible"])
        XCTAssertEqual(try resolve([row], home: "Liverpool", away: "Chelsea", requestKickoff: start,
            now: start.addingTimeInterval(3600)), URL(string: page))
        XCTAssertNil(try resolve([row], home: "Chelsea", away: "Liverpool", requestKickoff: start, now: start))
        XCTAssertNil(try resolve([row], home: "Liverpool", away: "Chelsea", requestKickoff: start.addingTimeInterval(86400), now: start))
        XCTAssertNil(try resolve([row], home: "Liverpool", away: "Chelsea", requestKickoff: start,
            now: start.addingTimeInterval(7200)), "The explicit publisher end still closes availability")
    }

    func testOmittedVisibilityDoesNotAdmitExplicitFalseNullOrMalformedValues() throws {
        let start = ISO8601DateFormatter().date(from: "2026-10-28T20:00:00Z")!
        let invalidValues: [Any] = [false, NSNull(), "true", 1, [Any](), [String: Any]()]
        for value in invalidValues {
            var row = liverpoolChelseaEvent()
            row["visible"] = value
            XCTAssertNil(try resolve([row], home: "Liverpool", away: "Chelsea", requestKickoff: start, now: start),
                         "Only an absent visibility field receives the published default")
        }
    }

    func testMissingVisibilityRetainsRepeatTimezoneDurationAndWatchActionGuards() throws {
        let start = ISO8601DateFormatter().date(from: "2026-10-28T20:00:00Z")!
        let changes: [[String: Any]] = [
            ["repeatPeriod": "weekly"], ["timeZone": "UTC"],
            ["end": date("2026-10-29", "05:01")],
            ["name": "Liverpool Women vs Chelsea"],
            ["actions": actions("https://score808live.tv.evil.test/watch/")],
            ["actions": [["type": "link", "text": "Watch Now", "primary": false,
                           "link": ["type": "url", "value": page]]]]
        ]
        for change in changes {
            var row = liverpoolChelseaEvent()
            row.merge(change) { _, next in next }
            XCTAssertNil(try resolve([row], home: "Liverpool", away: "Chelsea", requestKickoff: start, now: start))
        }
    }

    func testHistoricalArticleReuseDoesNotConfuseCurrentMatch() throws {
        var historical = event()
        historical["start"] = date("2026-08-30", "00:00")
        historical["end"] = date("2026-08-30", "02:00")
        historical["name"] = "Manchester United vs Ipswich Town"
        XCTAssertEqual(try resolve([historical, event()]), URL(string: page))
        XCTAssertNil(try resolve([historical]))
    }

    func testWrongSidesWrongTeamsAndNonSeniorSidesDoNotMatch() throws {
        XCTAssertNil(try resolve([event()], home: "Liverpool", away: "Ipswich Town"))
        XCTAssertNil(try resolve([event()], home: "Norwich", away: "Liverpool"))
        for name in ["Ipswich Town Women vs Liverpool", "Ipswich Town vs Liverpool U21", "Ipswich Town Liverpool", "Ipswich Town vs Liverpool vs Chelsea"] {
            var row = event()
            row["name"] = name
            XCTAssertNil(try resolve([row]), name)
        }
    }

    func testTimeBoundariesAndFiveMinuteKickoffTolerance() throws {
        XCTAssertNotNil(try resolve([event()], now: kickoff.addingTimeInterval(-30 * 60)))
        XCTAssertNil(try resolve([event()], now: kickoff.addingTimeInterval(-30 * 60 - 1)))
        XCTAssertNil(try resolve([event()], now: kickoff.addingTimeInterval(2 * 60 * 60)))
        XCTAssertNotNil(try resolve([event()], requestKickoff: kickoff.addingTimeInterval(5 * 60)))
        XCTAssertNil(try resolve([event()], requestKickoff: kickoff.addingTimeInterval(5 * 60 + 1)))

        var long = event()
        long["end"] = date("2026-09-05", "04:00")
        XCTAssertNotNil(try resolve([long], now: kickoff.addingTimeInterval(3 * 60 * 60)))
        XCTAssertNil(try resolve([long], now: kickoff.addingTimeInterval(3 * 60 * 60 + 1)))
        long["end"] = date("2026-09-05", "04:01")
        XCTAssertNil(try resolve([long]))
    }

    func testHiddenRecurringAndInvalidDatesFailClosed() throws {
        let invalidChanges: [[String: Any]] = [
            ["visible": false], ["visible": NSNull()], ["repeatPeriod": "weekly"],
            ["timeZone": "Unknown/Place"], ["timeZone": "UTC+05:00"],
            ["start": date("2026-02-30", "00:00")], ["start": date("2026-09-05", "24:00")],
            ["start": date("2026-9-5", "00:00")], ["end": date("2026-09-04", "23:59")],
            ["start": ["type": "date", "date": "2026-09-05", "time": "00:00"]]
        ]
        for changes in invalidChanges {
            var row = event()
            row.merge(changes) { _, new in new }
            XCTAssertNil(try resolve([row]), "Unexpectedly accepted \(changes.keys)")
        }
    }

    func testDuplicateMatchesAndConcurrentPageReuseAreAmbiguous() throws {
        XCTAssertNil(try resolve([event(), event()]))
        var other = event()
        other["name"] = "Real Betis vs Real Madrid"
        XCTAssertNil(try resolve([event(), other]))
        other["actions"] = actions("https://score808live.tv/score808-live-football-scores-real-time-match-updates-results")
        XCTAssertNil(try resolve([event(), other]))
        other["actions"] = actions("https://www.score808live.tv/another-match/")
        XCTAssertNotNil(try resolve([event(), other]))
    }

    func testOnlySafeExplicitScore808WatchActionsAreUsed() throws {
        for unsafe in [
            "http://www.score808live.tv/watch/", "https://score808live.tv.evil.test/watch/",
            "https://evil.test/", "//www.score808live.tv/watch/", "javascript:alert(1)",
            "https://user:password@www.score808live.tv/watch/", "https://www.score808live.tv:8080/watch/",
            "https://www.score808live.tv/watch/?redirect=https://evil.test", "https://www.score808live.tv/watch/#other",
            " https://www.score808live.tv/watch/", "https://www.score808live.tv\\@evil.test/watch/"
        ] {
            XCTAssertNil(Score808SiteCatalog.safeWatchPageURL(unsafe), unsafe)
            var row = event()
            row["actions"] = actions(unsafe)
            XCTAssertNil(try resolve([row]), unsafe)
        }
        let actionOverrides: [[String: Any]] = [["type": "download"], ["primary": false], ["text": "Buy tickets"]]
        for overrides in actionOverrides {
            var row = event()
            var action = actions(page)[0]
            action.merge(overrides) { _, new in new }
            row["actions"] = [action]
            XCTAssertNil(try resolve([row]))
        }
    }

    func testMalformedUnavailableOrOversizedConfigurationIsRejected() throws {
        let invalidOverrides: [[String: Any]] = [["status": 0], ["status": "1"], ["data": NSNull()]]
        for overrides in invalidOverrides {
            var payload = configuration([event()])
            payload.merge(overrides) { _, new in new }
            XCTAssertNil(match(try JSONSerialization.data(withJSONObject: payload)))
        }
        let disabled: [String: Any] = ["status": 1, "data": ["widgets": [widgetID: ["status": 0]]]]
        XCTAssertNil(match(try JSONSerialization.data(withJSONObject: disabled)))
        XCTAssertNil(match(Data("not json".utf8)))
        XCTAssertNil(match(Data(repeating: 32, count: Score808SiteCatalog.maximumDocumentBytes + 1)))
        XCTAssertNil(try resolve(Array(repeating: event(), count: Score808SiteCatalog.maximumEvents + 1)))
        let data = try JSONSerialization.data(withJSONObject: configuration([event()]))
        XCTAssertNil(Score808SiteCatalog.matchingWatchPage(
            in: data, widgetID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", homeTeam: "Ipswich Town",
            awayTeam: "Liverpool", kickoff: kickoff, now: kickoff
        ))
    }

    func testObservedVideoJSMarkupHasPlayerEvidence() {
        XCTAssertTrue(Score808SiteCatalog.playerEvidence(in: player()))
        XCTAssertTrue(Score808SiteCatalog.playerEvidence(in: player().replacingOccurrences(of: "application/x-mpegURL", with: "application/vnd.apple.mpegurl")))
    }

    func testGenericHTMLScriptsStubsAndMalformedPlayerDoNotProvePlayer() {
        let invalid = [
            "<html><body>Welcome to Score808</body></html>",
            "<div id='player'></div><script>jwplayer('player').setup({});</script>",
            "<script>const example = `\(player())`;</script>",
            "<script>\(player())",
            "<!-- \(player()) -->",
            player().replacingOccurrences(of: "data-setup='{}'", with: "data-setup='broken'"),
            player().replacingOccurrences(of: "data-setup='{}'", with: "data-setup='[]'"),
            player().replacingOccurrences(of: "data-setup='{}'", with: ""),
            player().replacingOccurrences(of: "id=\"my-video\"", with: "id=\"another-player\""),
            player().replacingOccurrences(of: "https://media.example.test/live/index.m3u8", with: "http://media.example.test/live/index.m3u8"),
            player().replacingOccurrences(of: "index.m3u8", with: "index.html"),
            player().replacingOccurrences(of: "application/x-mpegURL", with: "text/html"),
            player().replacingOccurrences(of: "</video-js>", with: ""),
            player().replacingOccurrences(of: " src=", with: " data-src="),
            player().replacingOccurrences(of: " src=", with: " src=bad src="),
            player() + String(repeating: " ", count: 1_000) + "<p>This stream is unavailable</p>"
        ]
        for html in invalid { XCTAssertFalse(Score808SiteCatalog.playerEvidence(in: html), String(html.prefix(120))) }
    }

    private func batchRequest(id: String = "score808-batch", home: String = "Ipswich Town", away: String = "Liverpool",
                              category: String = "football", start: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: id, displayTitle: "\(home) vs \(away)", homeTeam: home, awayTeam: away,
              category: category, kickoffDate: start ?? kickoff)
    }

    private func player() -> String {
        """
        <p><video-js id="my-video" class="vjs-default-skin vjs-big-play-centered" controls preload="auto" data-setup='{}'><source src="https://media.example.test/live/index.m3u8" type="application/x-mpegURL"></video-js></p>
        """
    }

    private func date(_ day: String, _ time: String) -> [String: String] {
        ["type": "datetime", "date": day, "time": time]
    }

    private func actions(_ url: String) -> [[String: Any]] {
        [["type": "link", "text": "Watch Now", "primary": true,
          "link": ["type": "url", "value": url, "target": "_self"]]]
    }

    private func event() -> [String: Any] {
        ["id": "test-event", "name": "Ipswich Town vs Liverpool",
         "start": date("2026-09-05", "00:00"), "end": date("2026-09-05", "02:00"),
         "timeZone": "Asia/Karachi", "visible": true, "repeatPeriod": "noRepeat",
         "actions": actions(page)]
    }

    private func liverpoolChelseaEvent() -> [String: Any] {
        // Current publisher shape observed 28 October: visibility is absent,
        // and the explicit Karachi date/time converts to 20:00 UTC on 28 Oct.
        ["id": "test-liverpool-chelsea", "name": " Liverpool vs Chelsea",
         "start": date("2026-10-29", "01:00"), "end": date("2026-10-29", "03:00"),
         "timeZone": "Asia/Karachi", "repeatPeriod": "noRepeat", "actions": actions(page)]
    }

    private func configuration(_ events: [[String: Any]]) -> [String: Any] {
        ["status": 1, "data": ["widgets": [widgetID: ["status": 1, "data": ["settings": [
            "selectedEventsProvider": "manual", "events": events
        ]]]]]]
    }

    private func resolve(
        _ events: [[String: Any]], home: String = "Ipswich Town", away: String = "Liverpool",
        requestKickoff: Date? = nil, now: Date? = nil
    ) throws -> URL? {
        Score808SiteCatalog.matchingWatchPage(
            in: try JSONSerialization.data(withJSONObject: configuration(events)), widgetID: widgetID,
            homeTeam: home, awayTeam: away, kickoff: requestKickoff ?? kickoff, now: now ?? kickoff
        )
    }

    private func match(_ data: Data) -> URL? {
        Score808SiteCatalog.matchingWatchPage(
            in: data, widgetID: widgetID, homeTeam: "Ipswich Town", awayTeam: "Liverpool", kickoff: kickoff, now: kickoff
        )
    }
}

/// Injected metadata only. A selected player URL or any other route fails the
/// test; no Score808, Elfsight or media network access is possible here.
private actor Score808BatchFixtureReader {
    let listing: Data
    let configuration: Data
    var pauseListing: Bool
    let started: XCTestExpectation?
    private var urls: [URL] = []
    init(listing: Data, configuration: Data, pauseListing: Bool = false, started: XCTestExpectation? = nil) {
        self.listing = listing; self.configuration = configuration; self.pauseListing = pauseListing; self.started = started
    }
    func read(_ url: URL) async throws -> Data {
        urls.append(url)
        if url == Score808SiteResolver.listingPage {
            if pauseListing { started?.fulfill(); try await Task.sleep(for: .seconds(60)) }
            return listing
        }
        guard url.host == "core.service.elfsight.com", ["/p/boot", "/p/boot/"].contains(url.path) else { throw URLError(.unsupportedURL) }
        return configuration
    }
    func requests() -> [URL] { urls }
    func resumeListing() { pauseListing = false }
}
