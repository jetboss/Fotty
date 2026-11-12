import XCTest
@testable import Fotty

final class PenguPlaySportsAddonTests: XCTestCase {
    private typealias Client = PenguPlaySportsAddonClient
    private let kickoff = ISO8601DateFormatter().date(from: "2026-11-12T00:00:00Z")!
    private let manifestURL = URL(string: "https://pengu.uk/%7B%22source_live-sports%22%3A%22checked%22%7D/manifest.json")!

    private func request(home: String = "Buffalo Sabres", away: String = "Tampa Bay Lightning", sport: String = "hockey") -> StreamPlaybackRequest {
        StreamPlaybackRequest(matchID: "sports-fixture:nhl:1", displayTitle: "\(home) vs \(away)",
                              homeTeam: home, awayTeam: away, category: sport, kickoffDate: kickoff)
    }
    private func row(_ name: String, id: String = "pp-live:daddylive~dHY2fDI5NWVh", released: String = "2026-11-12T00:00:00.000Z") -> Client.Row {
        .init(id: id, name: name, released: released, genres: ["🏒 Hockey"])
    }

    func testCatalogNamesBecomeExactPairs() {
        XCTAssertEqual(Client.pairTitle("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning"), "Buffalo Sabres vs Tampa Bay Lightning")
        XCTAssertEqual(Client.pairTitle("📺 New York Rangers vs. Calgary Flames"), "New York Rangers vs Calgary Flames")
        XCTAssertEqual(Client.pairTitle("🔴 LIVE: Inter Bogotá x América de Cali"), "Inter Bogotá vs América de Cali")
        XCTAssertNil(Client.pairTitle("🔴 LIVE: Fox Cricket"), "A channel is never a fixture")
        XCTAssertNil(Client.pairTitle("A - B - C"), "Ambiguous names fail closed")
    }

    func testSelectionNeedsBothTeamsSportAndExactKickoff() throws {
        let live = row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning")
        XCTAssertEqual(try Client.select(request: request(), rows: [live], now: kickoff).id, live.id)
        for wrong in [row("🔴 LIVE: Buffalo Sabres - Boston Bruins", id: "pp-live:x~1"),
                      row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning", id: "pp-live:x~2", released: "2026-11-13T00:00:00.000Z"),
                      row("🔴 LIVE: Fox Cricket", id: "pp-live:x~3"),
                      row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning", id: "https://evil.example/x")] {
            XCTAssertThrowsError(try Client.select(request: request(), rows: [wrong], now: kickoff), wrong.name)
        }
        // Two different listings of the same game cannot be told apart.
        XCTAssertThrowsError(try Client.select(request: request(), rows: [live, row(live.name, id: "pp-live:ppv~other")], now: kickoff))
    }

    func testWBBLShortNamesMatchOnlyUnambiguousCities() throws {
        XCTAssertEqual(Client.searchTerms("Sydney Thunder Women", "Perth Scorchers Women"),
                       ["Perth Scorchers", "Perth Scorchers Women", "Sydney Thunder", "Sydney Thunder Women"])
        let wbbl = request(home: "Sydney Thunder Women", away: "Perth Scorchers Women", sport: "cricket")
        let live = row("🔴 LIVE: Sydney Thunder W vs Perth W", id: "pp-live:wbbl~1")
        XCTAssertEqual(try Client.select(request: wbbl, rows: [live], now: kickoff).id, live.id)
        // The squad word still counts, and the two-team cities never shorten.
        XCTAssertThrowsError(try Client.select(request: wbbl, rows: [row("🔴 LIVE: Sydney Thunder vs Perth", id: "pp-live:bbl~1")], now: kickoff))
        let stars = request(home: "Melbourne Stars Women", away: "Perth Scorchers Women", sport: "cricket")
        XCTAssertThrowsError(try Client.select(request: stars, rows: [row("🔴 LIVE: Melbourne W vs Perth W", id: "pp-live:wbbl~2")], now: kickoff))
    }

    func testLiveTVManifestAndSignInPlaceholder() throws {
        let manifest = try JSONDecoder().decode(Client.Manifest.self, from: Data("""
        {"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["movie","series","tv"],"idPrefixes":["tt","pp-live:"]},
         {"name":"meta","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],
         "catalogs":[{"type":"tv","id":"pp-live-now"},{"type":"tv","id":"pp-live-hockey"}]}
        """.utf8))
        XCTAssertTrue(Client.hasLiveTV(manifest))
        let off = try JSONDecoder().decode(Client.Manifest.self, from: Data("""
        {"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["movie","series","tv"],"idPrefixes":["tt","pp-live:"]}],"catalogs":[]}
        """.utf8))
        XCTAssertFalse(Client.hasLiveTV(off), "Live TV switched off in the owner's configuration")
        let placeholder = try JSONDecoder().decode(Client.Delivery.self, from: Data("""
        {"name":"PenguPlay","title":"You must sign in","url":"https://pengu.uk/web/index.html"}
        """.utf8))
        XCTAssertTrue(Client.isSignInPlaceholder(placeholder))
    }

    func testDeliveryAndHeaderAdmission() throws {
        XCTAssertTrue(Client.admitsDelivery(URL(string: "https://cdn.example.com/live/index.m3u8?token=x")!))
        for bad in ["http://cdn.example.com/a.m3u8", "https://user:pw@cdn.example.com/a.m3u8",
                    "https://cdn.example.com/a.mp4", "https://127.0.0.1/a.m3u8"] {
            XCTAssertFalse(Client.admitsDelivery(URL(string: bad)!), bad)
        }
        func delivery(_ headers: String) throws -> Client.Delivery {
            try JSONDecoder().decode(Client.Delivery.self, from: Data(#"{"url":"https://cdn.example.com/a.m3u8","behaviorHints":{"proxyHeaders":{"request":\#(headers)}}}"#.utf8))
        }
        XCTAssertEqual(Client.requestHeaders(try delivery(#"{"referer":"https://site.example/","User-Agent":"UA"}"#)),
                       ["Referer": "https://site.example/", "User-Agent": "UA"])
        XCTAssertNil(Client.requestHeaders(try delivery(#"{"Cookie":"secret"}"#)))
        XCTAssertNil(Client.requestHeaders(try delivery(#"{"Referer":"http://site.example/"}"#)))
    }

    func testResolveUsesOnlyTheOwnersLinkAndReturnsGuardedHLS() async throws {
        let root = manifestURL.deletingLastPathComponent().absoluteString
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],"catalogs":[{"type":"tv","id":"pp-live-hockey"}]}"#
        let catalog = #"{"metas":[{"id":"pp-live:daddylive~dHY2fDI5NWVh","type":"tv","name":"🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning","released":"2026-11-12T00:00:00.000Z","genres":["🏒 Hockey"]}]}"#
        let streams = #"{"streams":[{"name":"PenguPlay","url":"https://cdn.example.com/live/index.m3u8","behaviorHints":{"proxyHeaders":{"request":{"Referer":"https://site.example/"}}}},{"name":"PenguPlay","url":"https://cdn.example.com/file.mp4"}]}"#
        let request = self.request()
        let fetched = PenguPlayLockedValue<[String]>([])
        let client = Client(configuration: { self.manifestURL }, fetch: { urlRequest in
            let url = urlRequest.url!.absoluteString
            fetched.mutate { $0.append(url) }
            let body = url == self.manifestURL.absoluteString ? manifest
                : url.hasPrefix(root + "catalog/tv/pp-live-hockey/search=") ? catalog
                : url == root + "stream/tv/" + Client.encodedComponent("pp-live:daddylive~dHY2fDI5NWVh") + ".json" ? streams : "{}"
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        }, enabled: { true }, current: { $0 }, validate: { _ in })
        let sessions = try await client.resolve(for: request, now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["PP1"], "The mp4 delivery is not admitted")
        XCTAssertEqual(sessions.first?.requiredHeaders, ["Referer": "https://site.example/"])
        XCTAssertEqual(sessions.first?.requiresGuardedRelay, true)
        XCTAssertTrue(fetched.value.allSatisfy { $0.hasPrefix(root) }, "Every request stays on the owner's configured link")
        let records = FottyQualityStore.shared.records()
        let admission = try XCTUnwrap(records.last { $0.name == "penguplay_delivery_admission" })
        XCTAssertEqual(admission.details["addon_stream_entry_count"], "2", "Counts survive the diagnostic allowlist")
        XCTAssertEqual(admission.details["candidate_count"], "1")
        XCTAssertEqual(admission.details["addon_admission_rejected_count"], "1")
        let lookup = try XCTUnwrap(records.last { $0.name == "penguplay_lookup" })
        XCTAssertEqual(lookup.details["result"], "admitted")
        XCTAssertFalse(lookup.details.values.contains { $0.contains("http") || $0.contains("Sabres") })
    }

    func testLookupReceiptNamesTheStageThatStopped() async throws {
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],"catalogs":[{"type":"tv","id":"pp-live-hockey"}]}"#
        let client = Client(configuration: { self.manifestURL }, fetch: { urlRequest in
            let body = urlRequest.url == self.manifestURL ? manifest : #"{"metas":[]}"#
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        }, enabled: { true }, current: { $0 }, validate: { _ in }, programmeChannels: { _ in [] })
        do { _ = try await client.resolve(for: request(), now: kickoff); XCTFail("No catalog row means no match") } catch {}
        let lookup = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "penguplay_lookup" })
        XCTAssertEqual(lookup.details["result"], "stopped_at_programme_channel", "No reviewed programme, no channel fallback")
    }

    func testStreamFailureRecordsItsShape() async throws {
        let root = manifestURL.deletingLastPathComponent().absoluteString
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],"catalogs":[{"type":"tv","id":"pp-live-cricket"}]}"#
        let full = #"{"metas":[{"id":"pp-live:dl~fox","type":"tv","name":"🔴 LIVE: Fox Cricket","released":"2026-11-12T00:00:00.000Z"}]}"#
        let client = Client(configuration: { self.manifestURL }, fetch: { urlRequest in
            let url = urlRequest.url!.absoluteString
            if url.hasPrefix(root + "stream/") { throw FottyBoundedHTTPClient.Failure.httpStatus(429) }
            let body = url == self.manifestURL.absoluteString ? manifest : full
            return (Data(body.utf8), HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }, enabled: { true }, current: { $0 }, validate: { _ in }, programmeChannels: { _ in [] })
        let tile = StreamPlaybackRequest(matchID: CricketBroadcastChannel.foxCricket.canonicalID, displayTitle: "Fox Cricket",
                                         homeTeam: "Fox Cricket", awayTeam: "", category: "cricket", kickoffDate: nil)
        do { _ = try await client.resolve(for: tile, now: kickoff); XCTFail("429 has no streams") } catch {}
        let lookup = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "penguplay_lookup" })
        XCTAssertEqual(lookup.details["result"], "stopped_at_streams")
        XCTAssertEqual(lookup.details["reason_code"], "http_429")
    }

    func testMissReasonNamesWhyNoRowMatched() throws {
        let wbbl = request(home: "Melbourne Renegades Women", away: "Sydney Sixers Women", sport: "cricket")
        let id = try XCTUnwrap(ReviewedSportsFixtureMatcher.requestIdentity(for: wbbl))
        func reason(_ rows: [Client.Row]) -> String {
            ReviewedSportsFixtureMatcher.missReason(for: id, parsed: rows.map { Client.identity($0, sport: "cricket") })
        }
        XCTAssertEqual(reason([]), "no_rows")
        XCTAssertEqual(reason([row("🔴 LIVE: WBBL")]), "unreadable_rows")
        XCTAssertEqual(reason([row("🔴 LIVE: Sydney Thunder W vs Perth W")]), "teams_differ", "Today's mislabelled listing")
        XCTAssertEqual(reason([row("🔴 LIVE: Melbourne Renegades W vs Sydney Sixers W", released: "2026-11-12T03:00:00.000Z")]), "kickoff_differs")
        XCTAssertEqual(reason([row("🔴 LIVE: Melbourne Renegades vs Sydney Sixers")]), "squad_differs")
        XCTAssertEqual(reason([row("🔴 LIVE: Melbourne Renegades W vs Hobart W")]), "one_team_matches")
    }

    func testKickoffOffsetReportsTheClosestSamePairRow() throws {
        let id = try XCTUnwrap(ReviewedSportsFixtureMatcher.requestIdentity(for: request()))
        let early = Client.identity(row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning", id: "pp-live:x~1",
            released: "2026-11-11T23:30:00.000Z"), sport: "hockey")
        let other = Client.identity(row("🔴 LIVE: Buffalo Sabres - Boston Bruins", id: "pp-live:x~2"), sport: "hockey")
        XCTAssertEqual(ReviewedSportsFixtureMatcher.kickoffOffsetMinutes(for: id, parsed: [other, early]), -30)
        XCTAssertNil(ReviewedSportsFixtureMatcher.kickoffOffsetMinutes(for: id, parsed: [other]))
    }

    func testChannelRowNeedsExactChannelTitle() throws {
        let fox = row("🔴 LIVE: Fox Cricket", id: "pp-live:dl~fox")
        let rows = [row("🔴 LIVE: WBBL", id: "pp-live:dl~wbbl"), row("📺 Fox Cricket", id: "pp-live:dl~old"), fox]
        XCTAssertEqual(try Client.selectChannel(.foxCricket, rows: rows).id, fox.id)
        XCTAssertThrowsError(try Client.selectChannel(.willow, rows: rows), "A competition row never stands in for a channel")
        XCTAssertThrowsError(try Client.selectChannel(.foxCricket, rows: rows + [row("🔴 LIVE: Fox Cricket HD", id: "pp-live:dl~fox2")]),
                             "Two live Fox rows cannot be told apart")
    }

    private func cricketClient(programme: Set<CricketBroadcastChannel>, fetched: PenguPlayLockedValue<[String]>) -> Client {
        let root = manifestURL.deletingLastPathComponent().absoluteString
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],"catalogs":[{"type":"tv","id":"pp-live-cricket"}]}"#
        let full = #"{"metas":[{"id":"pp-live:dl~wbbl","type":"tv","name":"🔴 LIVE: WBBL","released":"2026-11-12T00:00:00.000Z"},{"id":"pp-live:dl~fox","type":"tv","name":"🔴 LIVE: Fox Cricket","released":"2026-11-12T00:00:00.000Z"}]}"#
        let streams = #"{"streams":[{"url":"https://cdn.example.com/fox/index.m3u8"}]}"#
        return Client(configuration: { self.manifestURL }, fetch: { urlRequest in
            let url = urlRequest.url!.absoluteString
            fetched.mutate { $0.append(url) }
            let body = url == self.manifestURL.absoluteString ? manifest
                : url == root + "catalog/tv/pp-live-cricket.json" ? full
                : url.hasPrefix(root + "catalog/tv/pp-live-cricket/search=") ? #"{"metas":[]}"#
                : url == root + "stream/tv/" + Client.encodedComponent("pp-live:dl~fox") + ".json" ? streams : "{}"
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        }, enabled: { true }, current: { $0 }, validate: { _ in }, programmeChannels: { _ in programme })
    }

    func testFixtureUsesFoxRowOnlyWithReviewedProgramme() async throws {
        let fixture = request(home: "Melbourne Renegades Women", away: "Sydney Sixers Women", sport: "cricket")
        let fetched = PenguPlayLockedValue<[String]>([])
        let sessions = try await cricketClient(programme: [.foxCricket], fetched: fetched).resolve(for: fixture, now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["PP1"])
        XCTAssertEqual(sessions.first?.eventBinding?.providerEventID, "pp-live:dl~fox")
        XCTAssertEqual(sessions.first?.eventBinding?.matchesIdentity(request: fixture, providerCode: "penguplay"), true)
        do {
            _ = try await cricketClient(programme: [], fetched: fetched).resolve(for: fixture, now: kickoff)
            XCTFail("Without a reviewed programme the Fox channel is not this game")
        } catch {}
        do {
            _ = try await cricketClient(programme: [.foxCricket, .willow], fetched: fetched).resolve(for: fixture, now: kickoff)
            XCTFail("Two programme channels are ambiguous")
        } catch {}
    }

    func testFoxCricketTileUsesThePenguPlayChannel() async throws {
        let tile = StreamPlaybackRequest(matchID: CricketBroadcastChannel.foxCricket.canonicalID, displayTitle: "Fox Cricket",
                                         homeTeam: "Fox Cricket", awayTeam: "", category: "cricket", kickoffDate: nil)
        XCTAssertEqual(CricketBroadcastChannel.identifying(request: tile), .foxCricket)
        let fetched = PenguPlayLockedValue<[String]>([])
        let sessions = try await cricketClient(programme: [], fetched: fetched).resolve(for: tile, now: kickoff)
        XCTAssertEqual(sessions.first?.eventBinding?.providerEventID, "pp-live:dl~fox")
        XCTAssertFalse(fetched.value.contains { $0.contains("search=") }, "A channel tile never searches team names")
    }
}

/// Minimal thread-safe box for test closures.
final class PenguPlayLockedValue<T>: @unchecked Sendable {
    private var stored: T; private let lock = NSLock()
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}
