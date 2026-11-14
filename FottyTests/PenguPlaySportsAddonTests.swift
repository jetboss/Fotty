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
        // Two listings of the same game are both the right game.
        XCTAssertEqual(try Client.select(request: request(), rows: [live, row(live.name, id: "pp-live:ppv~other")], now: kickoff).id, live.id)
    }

    func testProviderFinishedMatchWithdrawsSameIDButPreservesIndependentLiveListing() throws {
        let match = request(home: "Kuwait", away: "Syria", sport: "football")
        let live = row("🔴 LIVE: Kuwait vs Syria", id: "pp-live:aksports~one")
        let ended = Client.Row(id: live.id, name: "📺 Kuwait vs Syria", released: live.released,
            description: "International Friendly Games\nSoccer\nFinished — a replay may still be available\nKickoff: Nov 13, 12:30")
        for stale in [[ended], [live, ended], [ended, live]] {
            XCTAssertThrowsError(try Client.select(request: match, rows: stale, now: kickoff))
        }
        let other = row("🔴 LIVE: Kuwait vs Syria", id: "pp-live:second~two")
        XCTAssertEqual(try Client.select(request: match, rows: [ended, live, other], now: kickoff).id, other.id)
    }

    func testCurrentMetadataWithdrawsStaleSearchBeforeAnyDescriptorIsOpened() async throws {
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"meta","types":["tv"],"idPrefixes":["pp-live:"]},"catalog"],"catalogs":[{"type":"tv","id":"pp-live-football"}]}"#
        let row = #"{"id":"pp-live:aksports~one","type":"tv","name":"📺 Kuwait vs Syria","released":"2026-11-12T00:00:00.000Z""#
        let fetched = PenguPlayLockedValue<[String]>([])
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let client = Client(configuration: { self.manifestURL }, fetch: { request in
            let url = try XCTUnwrap(request.url)
            fetched.mutate { $0.append(url.path) }
            let body: String
            if url == self.manifestURL { body = manifest }
            else if url.path.contains("/catalog/") { body = "{\"metas\":[" + row + "}]}" }
            else if url.path.contains("/meta/") {
                body = "{\"meta\":" + row + #","description":"Soccer\nFinished — a replay may still be available"}}"#
            } else { XCTFail("A terminal fixture cannot authorize a stream lookup"); body = "{}" }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        }, enabled: { true }, current: { $0 }, validate: { _ in },
            receiptSink: { receipt in receipts.mutate { $0.append(receipt) } })
        do {
            _ = try await client.resolve(for: request(home: "Kuwait", away: "Syria", sport: "football"), now: kickoff)
            XCTFail("Expected the current source status to veto the stale search result")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(fetched.value.filter { $0.contains("/meta/") }.count, 1)
        XCTAssertFalse(fetched.value.contains { $0.contains("/stream/") })
        let receipt = try XCTUnwrap(receipts.value.last)
        XCTAssertEqual(receipt.unreadResponses, 1, "A metadata veto leaves the selected listing’s stream response unread")
        XCTAssertEqual(receipt.readResponses, 0)
        XCTAssertEqual(receipt.knownEmptyResponses, 0)
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
                    "https://127.0.0.1/a.m3u8"] {
            XCTAssertFalse(Client.admitsDelivery(URL(string: bad)!), bad)
        }
        func delivery(_ headers: String) throws -> Client.Delivery {
            try JSONDecoder().decode(Client.Delivery.self, from: Data(#"{"url":"https://cdn.example.com/a.m3u8","behaviorHints":{"proxyHeaders":{"request":\#(headers)}}}"#.utf8))
        }
        XCTAssertEqual(Client.requestHeaders(try delivery(#"{"referer":"https://site.example/","User-Agent":"UA"}"#)),
                       ["Referer": "https://site.example/", "User-Agent": "UA"])
        XCTAssertNil(Client.requestHeaders(try delivery(#"{"Cookie":"secret"}"#)))
        // A Referer is provenance, not a destination: plain-http values are forwarded,
        // and unknown header names are dropped instead of refusing the stream.
        XCTAssertEqual(Client.requestHeaders(try delivery(#"{"Referer":"http://site.example/","X-Thing":"1"}"#)),
                       ["Referer": "http://site.example/"])
        XCTAssertTrue(Client.admitsDelivery(URL(string: "https://cdn.example.com/hls/master?sig=abc")!),
                      "A live playlist without an .m3u8 suffix is still tried")
    }

    func testEveryListingOfTheGameContributesStreams() async throws {
        let root = manifestURL.deletingLastPathComponent().absoluteString
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],"catalogs":[{"type":"tv","id":"pp-live-hockey"}]}"#
        let catalog = #"{"metas":[{"id":"pp-live:daddylive~one","type":"tv","name":"🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning","released":"2026-11-12T00:00:00.000Z","genres":["🏒 Hockey"]},{"id":"pp-live:ppv~two","type":"tv","name":"📺 Buffalo Sabres x Tampa Bay Lightning","released":"2026-11-12T00:00:00.000Z","genres":["🏒 Hockey"]}]}"#
        func streams(_ host: String, _ count: Int) -> String {
            #"{"streams":["# + (1...count).map { #"{"name":"PenguPlay","url":"https://\#(host)/live/\#($0)/index.m3u8"}"# }.joined(separator: ",") + "]}"
        }
        let client = Client(configuration: { self.manifestURL }, fetch: { urlRequest in
            let url = urlRequest.url!.absoluteString
            let body = url == self.manifestURL.absoluteString ? manifest
                : url.hasPrefix(root + "catalog/tv/pp-live-hockey/search=") ? catalog
                : url == root + "stream/tv/" + Client.encodedComponent("pp-live:daddylive~one") + ".json" ? streams("one.example.com", 4)
                : url == root + "stream/tv/" + Client.encodedComponent("pp-live:ppv~two") + ".json" ? streams("two.example.com", 7) : "{}"
            return (Data(body.utf8), HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil,
                                                     headerFields: ["Content-Type": "application/json"])!)
        }, enabled: { true }, current: { $0 }, validate: { _ in })
        let sessions = try await client.resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 11, "Two listings of one game are not a conflict, and no cap of 6 applies")
        XCTAssertEqual(Set(sessions.compactMap { $0.eventBinding?.providerEventID }), ["pp-live:daddylive~one", "pp-live:ppv~two"])
        let admission = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "stream_admission" && $0.details["source_family"] == "penguplay" })
        XCTAssertEqual(admission.details["admitted_count"], "11")
        XCTAssertEqual(admission.details["offered_count"], "11")
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
        XCTAssertEqual(sessions.map(\.providerName), ["PP1", "PP2"], "Actual guarded media response decides content, not its suffix")
        XCTAssertEqual(sessions.first?.requiredHeaders, ["Referer": "https://site.example/"])
        XCTAssertEqual(sessions.first?.requiresGuardedRelay, true)
        XCTAssertTrue(fetched.value.allSatisfy { $0.hasPrefix(root) }, "Every request stays on the owner's configured link")
        let records = FottyQualityStore.shared.records()
        let admission = try XCTUnwrap(records.last { $0.name == "stream_admission" && $0.details["source_family"] == "penguplay" })
        XCTAssertEqual(admission.details["offered_count"], "2", "Counts survive the diagnostic allowlist")
        XCTAssertEqual(admission.details["admitted_count"], "2")
        XCTAssertEqual(admission.details["admission_reconciled"], "yes")
        let lookup = try XCTUnwrap(records.last { $0.name == "penguplay_lookup" })
        XCTAssertEqual(lookup.details["result"], "admitted")
        XCTAssertFalse(lookup.details.values.contains { $0.contains("http") || $0.contains("Sabres") })
    }

    func testMixedNoticeMalformedAndNullMetadataCannotEraseValidSibling() async throws {
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},"catalog"],"catalogs":[{"type":"tv","id":"pp-live-hockey"}]}"#
        let catalog = #"{"metas":[{"id":"pp-live:daddylive~one","type":"tv","name":"Buffalo Sabres vs Tampa Bay Lightning","released":"2026-11-12T00:00:00.000Z"}]}"#
        let streams = #"{"streams":[{"title":"You must sign in","url":"https://pengu.uk/web/index.html"},7,{"url":"https://cdn.example.com/play.php","behaviorHints":null,"drm":null},{"url":"https://cdn.example.com/play.php","headers":null},{"url":"https://cdn.example.com/locked","drm":"widevine"}]}"#
        let client = Client(configuration: { self.manifestURL }, fetch: { r in
            let url = try XCTUnwrap(r.url)
            let body = url == self.manifestURL ? manifest : url.path.contains("/stream/") ? streams : catalog
            return (Data(body.utf8),HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!)
        }, enabled:{true},current:{$0},validate:{_ in})
        let sessions = try await client.resolve(for: request(),now:kickoff)
        XCTAssertEqual(sessions.count,1); XCTAssertEqual(sessions[0].requiresGuardedRelay, true)
        let row = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "stream_admission" && $0.details["source_family"] == "penguplay" })
        XCTAssertEqual(row.details["offered_count"],"5"); XCTAssertEqual(row.details["admitted_count"],"1")
        for reason in ["sign_in","no_url","duplicate","drm"] { XCTAssertEqual(row.details["admission_" + reason + "_count"],"1") }
        XCTAssertEqual(row.details["admission_reconciled"],"yes")
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

    func testDeliveryLabelsDecodeIndependentlyWithoutChangingAdmissionFields() throws {
        func decode(_ body: String) throws -> Client.Delivery {
            try JSONDecoder().decode(Client.Delivery.self, from: Data(body.utf8))
        }
        let malformedName = try decode(#"{"name":7,"title":"Buffalo Sabres vs Tampa Bay Lightning","url":"https://cdn.example.com/one.m3u8"}"#)
        XCTAssertNil(malformedName.name)
        XCTAssertEqual(malformedName.title, "Buffalo Sabres vs Tampa Bay Lightning")
        XCTAssertEqual(malformedName.requestedHeaders, [:])
        let malformedTitle = try decode(#"{"name":"Buffalo Sabres vs Tampa Bay Lightning","title":{"private":"value"},"url":"https://cdn.example.com/two.m3u8"}"#)
        XCTAssertEqual(malformedTitle.name, "Buffalo Sabres vs Tampa Bay Lightning")
        XCTAssertNil(malformedTitle.title)
        XCTAssertEqual(malformedTitle.requestedHeaders, [:])
        let absent = try decode(#"{"url":"https://cdn.example.com/three.m3u8"}"#)
        XCTAssertNil(absent.name); XCTAssertNil(absent.title)
    }

    func testLookupEvidenceCountsMultipleListingsAndKeepsContradictionOutOfRanking() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let generation = UUID()
        let first = #"{"streams":[{"name":"Buffalo Sabres vs Tampa Bay Lightning","title":"Boston Bruins vs Toronto Maple Leafs","url":"https://cdn.example.com/first.m3u8?token=private-token-sentinel"},{"name":7,"title":"Buffalo Sabres vs Tampa Bay Lightning","url":"https://cdn.example.com/second.m3u8"},{"url":"https://cdn.example.com/second.m3u8"},7]}"#
        let client = evidenceClient(streams: [first, #"{"streams":[]}"#], generation: { _ in generation },
            sink: { receipt in receipts.mutate { $0.append(receipt) } })
        let sessions = try await client.resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["PP1", "PP2"])
        XCTAssertEqual(sessions.map { $0.playableURL.lastPathComponent }, ["first.m3u8", "second.m3u8"],
                       "Metadata contradiction is evidence, never a new sort or refusal rule")
        let receipt = try XCTUnwrap(receipts.value.last)
        XCTAssertEqual(receipts.value.count, 1)
        XCTAssertEqual(receipt.configurationGeneration, generation)
        XCTAssertEqual(receipt.readResponses, 2)
        XCTAssertEqual(receipt.knownEmptyResponses, 1)
        XCTAssertEqual(receipt.unreadResponses, 0)
        XCTAssertEqual(receipt.observedEntries, 4)
        XCTAssertEqual(receipt.uniqueObservedContracts, 2)
        XCTAssertEqual(receipt.admitted, 2)
        XCTAssertEqual(receipt.dispositions["duplicate"], 1)
        XCTAssertEqual(receipt.dispositions["no_url"], 1)
        XCTAssertEqual(receipt.deliveries.map(\.disposition), ["admitted", "admitted", "duplicate", "no_url"])
        XCTAssertEqual(receipt.deliveries[0].comparison, .contradicts)
        XCTAssertTrue(receipt.deliveries[0].hasName); XCTAssertTrue(receipt.deliveries[0].hasTitle)
        XCTAssertEqual(receipt.deliveries[1].comparison, .agrees)
        XCTAssertFalse(receipt.deliveries[1].hasName); XCTAssertTrue(receipt.deliveries[1].hasTitle)
        XCTAssertEqual(receipt.deliveries[2].comparison, .noParseableTeams)
        XCTAssertTrue(receipt.isReconciled)
        for session in sessions {
            let provenance = try XCTUnwrap(session.deliveryProvenance)
            XCTAssertEqual(provenance.lookupID, receipt.lookupID)
            XCTAssertEqual(provenance.configurationGeneration, generation)
            XCTAssertTrue(receipt.deliveries.contains { $0.listing == provenance.listing && $0.contract == provenance.contract
                && $0.sourceID == session.id && $0.disposition == "admitted" })
            XCTAssertNil(session.deliveryTransportContext, "Discovery cannot invent the playback cookie snapshot")
        }
        XCTAssertTrue(receipt.deliveries.filter { $0.disposition != "admitted" }.allSatisfy { $0.sourceID == nil },
                      "A duplicate or refused sibling is not the selected source")
        let suiteName = "PenguPlayEvidencePrivacy-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FottyQualityStore(defaults: defaults, now: { receipt.finishedAt })
        store.recordProviderLookup(receipt)
        XCTAssertEqual(store.records().filter { $0.name == "provider_lookup" }.count, 1)
        let serialized = String(decoding: try JSONEncoder().encode(store.records()), as: UTF8.self)
        for privateValue in ["private-token-sentinel", "cdn.example.com", "first.m3u8", "Buffalo", "Boston", "pp-live:lane~"] {
            XCTAssertFalse(serialized.contains(privateValue), privateValue)
        }
    }

    func testReceiptUsesEffectiveHeadersAfterHarmlessHintsAreDropped() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let body = #"{"streams":[{"url":"https://cdn.example.com/headers.m3u8","headers":{"Accept":"video/*","Referer":"https://origin.example.com/watch"}}]}"#
        let client = evidenceClient(streams: [body], sink: { receipt in receipts.mutate { $0.append(receipt) } })
        let sessions = try await client.resolve(for: request(), now: kickoff)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.requiredHeaders, ["Referer": "https://origin.example.com/watch"])
        let provenance = try XCTUnwrap(session.deliveryProvenance)
        let receipt = try XCTUnwrap(receipts.value.last)
        let delivery = try XCTUnwrap(receipt.deliveries.first)
        XCTAssertEqual(delivery.contract, provenance.contract,
                       "Receipt identity uses the headers that playback receives, not discarded hints")
        XCTAssertEqual(delivery.contract, LiveSourceHealthStore.deliveryContractFingerprint(for: session))
        XCTAssertEqual(delivery.sourceID, session.id)
        XCTAssertEqual(delivery.disposition, "admitted")
        XCTAssertTrue(receipt.isReconciled)
    }

    func testRepeatedLookupsHaveSeparateIDsAndStableContractFingerprints() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([]), generation = UUID()
        let client = evidenceClient(streams: [#"{"streams":[{"url":"https://cdn.example.com/repeated.m3u8"}]}"#],
            generation: { _ in generation }, sink: { receipt in receipts.mutate { $0.append(receipt) } })
        let first = try await client.resolve(for: request(), now: kickoff)
        let second = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(receipts.value.count, 2)
        XCTAssertNotEqual(receipts.value[0].lookupID, receipts.value[1].lookupID)
        XCTAssertEqual(receipts.value[0].observedEntries, 1)
        XCTAssertEqual(receipts.value[1].observedEntries, 1)
        XCTAssertEqual(first.first?.deliveryProvenance?.contract, second.first?.deliveryProvenance?.contract)
        XCTAssertEqual(first.first?.deliveryProvenance?.listing, second.first?.deliveryProvenance?.listing)
        XCTAssertNotEqual(first.first?.deliveryProvenance?.lookupID, second.first?.deliveryProvenance?.lookupID)
    }

    func testPartialStreamReadKeepsGoodListingAndSeparatesUnreadFromEmpty() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let client = evidenceClient(streams: [#"{"streams":[{"url":"https://cdn.example.com/good.m3u8"}]}"#,
                                             #"{"streams":[]}"#, #"{"streams":[]}"#], failures: [1],
            sink: { receipt in receipts.mutate { $0.append(receipt) } })
        let sessions = try await client.resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        let receipt = try XCTUnwrap(receipts.value.last)
        XCTAssertEqual(receipt.readResponses, 2)
        XCTAssertEqual(receipt.unreadResponses, 1)
        XCTAssertEqual(receipt.knownEmptyResponses, 1)
        XCTAssertEqual(receipt.observedEntries, 1, "Unread responses are not fabricated as empty or offered streams")
        XCTAssertEqual(receipt.admitted, 1)
        XCTAssertEqual(receipt.completion, "partial")
        XCTAssertTrue(receipt.isReconciled)
    }

    func testEntirelyUnreadStreamResponsesDoNotBecomeKnownEmpty() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let client = evidenceClient(streams: [#"{"streams":[]}"#], failures: [0],
            sink: { receipt in receipts.mutate { $0.append(receipt) } })
        do { _ = try await client.resolve(for: request(), now: kickoff); XCTFail("Expected failed descriptor") } catch {}
        let receipt = try XCTUnwrap(receipts.value.last)
        XCTAssertEqual(receipt.readResponses, 0)
        XCTAssertEqual(receipt.unreadResponses, 1)
        XCTAssertEqual(receipt.knownEmptyResponses, 0)
        XCTAssertEqual(receipt.observedEntries, 0)
        XCTAssertEqual(receipt.completion, "failed")
        XCTAssertFalse(receipt.isReconciled, "There is no observed stream response to reconcile")
    }

    func testEvidenceCountsFullResponseBeforeExistingScanAndSessionLimits() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let body = "{\"streams\":[" + (0..<101).map { #"{"url":"https://cdn.example.com/limited/\#($0).m3u8"}"# }.joined(separator: ",") + "]}"
        let client = evidenceClient(streams: [body], sink: { receipt in receipts.mutate { $0.append(receipt) } })
        let sessions = try await client.resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 100)
        let receipt = try XCTUnwrap(receipts.value.last)
        XCTAssertEqual(receipt.observedEntries, 101)
        XCTAssertEqual(receipt.admitted, 100)
        XCTAssertEqual(receipt.dispositions["limit"], 1)
        XCTAssertTrue(receipt.isTruncated)
        XCTAssertLessThanOrEqual(receipt.deliveries.count, 64)
        XCTAssertTrue(receipt.isReconciled)
    }

    func testConfigurationGenerationChangeWithdrawsPendingLookupEvenWhenURLReturnsToSameValue() async throws {
        let receipts = PenguPlayLockedValue<[ProviderLookupReceipt]>([])
        let calls = PenguPlayLockedValue(0), original = UUID(), replacement = UUID()
        let client = evidenceClient(streams: [#"{"streams":[{"url":"https://cdn.example.com/config.m3u8"}]}"#],
            generation: { _ in
                var value = original
                calls.mutate { count in count += 1; value = count == 1 ? original : replacement }
                return value
            }, sink: { receipt in receipts.mutate { $0.append(receipt) } })
        do { _ = try await client.resolve(for: request(), now: kickoff); XCTFail("Old configuration must not publish sources") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        let receipt = try XCTUnwrap(receipts.value.last)
        XCTAssertEqual(receipt.configurationGeneration, original)
        XCTAssertEqual(receipt.admitted, 0)
        XCTAssertEqual(receipt.completion, "failed")
        XCTAssertTrue(receipt.isReconciled)
    }

    private func evidenceClient(streams: [String], failures: Set<Int> = [],
                                generation: Client.Generation? = nil,
                                sink: @escaping Client.ReceiptSink) -> Client {
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},"catalog"],"catalogs":[{"type":"tv","id":"pp-live-hockey"}]}"#
        let rows = streams.indices.map { #"{"id":"pp-live:lane~\#($0)","type":"tv","name":"Buffalo Sabres vs Tampa Bay Lightning","released":"2026-11-12T00:00:00.000Z"}"# }
        let catalog = "{\"metas\":[" + rows.joined(separator: ",") + "]}"
        let root = manifestURL.deletingLastPathComponent().absoluteString
        let streamURLs = streams.indices.map { root + "stream/tv/" + Client.encodedComponent("pp-live:lane~\($0)") + ".json" }
        return Client(configuration: { self.manifestURL }, fetch: { request in
            let url = try XCTUnwrap(request.url)
            let body: String
            if url == self.manifestURL { body = manifest }
            else if let index = streamURLs.firstIndex(of: url.absoluteString) {
                if failures.contains(index) { throw URLError(.timedOut) }
                body = streams[index]
            } else { body = catalog }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
        }, enabled: { true }, current: { $0 }, validate: { _ in }, programmeChannels: { _ in [] },
            generation: generation, receiptSink: sink)
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
        XCTAssertNil(sessions.first?.deliveryProvenance, "A generic channel tile has no current programme identity")
    }
}

/// Minimal thread-safe box for test closures.
final class PenguPlayLockedValue<T>: @unchecked Sendable {
    private var stored: T; private let lock = NSLock()
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}
