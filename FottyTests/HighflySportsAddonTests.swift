import XCTest
@testable import Fotty

final class HighflySportsAddonTests: XCTestCase {
    private let kickoff = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!
    private func request() -> StreamPlaybackRequest {
        .init(matchID: "official-synthetic", displayTitle: "Arsenal vs Everton", homeTeam: "Arsenal",
              awayTeam: "Everton", category: "football", kickoffDate: kickoff)
    }
    private func row(id: String = "streamed:synthetic", name: String = "Arsenal vs Everton",
                     date: String = "10 Nov 2026 · 18:00 UTC") -> HighflySportsAddonClient.Row {
        .init(id: id, name: name, description: name + "\n" + date, releaseInfo: date, category: "football")
    }

    func testExactFixtureAndDuplicateRowsDoNotInventProgrammeIdentity() throws {
        let good = row()
        XCTAssertEqual(try HighflySportsAddonClient.select(request: request(), rows: [good, good], now: kickoff), good)
        for bad in [row(name: "Arsenal Women vs Everton Women"), row(name: "Sky Sports Premier League"),
                    row(date: "11 Nov 2026 · 18:00 UTC"), row(date: "10 Nov 2026 · 18:16 UTC"),
                    row(date: "10 Nov 2026 · 18:00"), row(id: "recap:synthetic")] {
            XCTAssertThrowsError(try HighflySportsAddonClient.select(request: request(), rows: [bad], now: kickoff))
        }
    }

    func testEveryScheduledSportUsesItsOwnHighflyCatalog() {
        for (category, catalog) in [("football", "sports_football"), ("cricket", "sports_cricket"),
                                    ("basketball", "sports_basketball"), ("baseball", "sports_baseball"),
                                    ("hockey", "sports_hockey"), ("american-football", "sports_american_football"),
                                    ("NFL", "sports_american_football"), ("NBA", "sports_basketball")] {
            XCTAssertTrue(HighflySportsAddonClient.supports(category: category), category)
            XCTAssertEqual(HighflySportsAddonClient.catalogID(forSport: category), catalog)
        }
        // No Fotty schedule exists to match these against.
        for category in ["rugby", "fight", "golf", "motorsport", "tennis", "darts", "other"] {
            XCTAssertFalse(HighflySportsAddonClient.supports(category: category), category)
        }
    }

    func testHockeyRowMatchesTheOfficialScheduleFixture() throws {
        let start = ISO8601DateFormatter().date(from: "2026-11-11T00:00:00Z")!
        let nhl = StreamPlaybackRequest(matchID: "sports-fixture:nhl:synthetic", displayTitle: "Montreal Canadiens vs Minnesota Wild",
            homeTeam: "Montreal Canadiens", awayTeam: "Minnesota Wild", category: "hockey", kickoffDate: start)
        let date = "11 Nov 2026 · 00:00 UTC", name = "Montreal Canadiens vs Minnesota Wild"
        let good = HighflySportsAddonClient.Row(id: "streamed:nhl", name: name, description: name + "\n" + date,
            releaseInfo: date, category: "hockey")
        XCTAssertEqual(try HighflySportsAddonClient.select(request: nhl, rows: [good], now: start), good)
        let swapped = HighflySportsAddonClient.Row(id: "streamed:other", name: "Ottawa Senators vs Washington Capitals",
            description: "Ottawa Senators vs Washington Capitals\n" + date, releaseInfo: date, category: "hockey")
        XCTAssertThrowsError(try HighflySportsAddonClient.select(request: nhl, rows: [swapped], now: start))
    }

    func testMalformedSiblingVetoIsLocalToItsIdentity() throws {
        let good = row()
        let malformed = HighflySportsAddonClient.Row(id: good.id, name: good.name, description: "LIVE",
                                                      releaseInfo: "LIVE", category: "football")
        XCTAssertThrowsError(try HighflySportsAddonClient.select(request: request(), rows: [good, malformed], now: kickoff))
        XCTAssertEqual(try HighflySportsAddonClient.select(request: request(), rows: [good, row(id: "streamed:other", name: "Unknown Channel")], now: kickoff), good)
        XCTAssertNil(HighflySportsAddonClient.identity(row(date: "30 Feb 2026 · 18:00 UTC")))
    }

    @MainActor
    func testTestDayUsesVerifiedOrdinalDayAndOriginalFixture() throws {
        let start = ISO8601DateFormatter().date(from: "2026-11-09T04:30:00Z")!
        let now = start.addingTimeInterval(86400)
        func fixture(day: Int, ordinal: Int, verified: Bool = true) -> StreamPlaybackRequest {
            let metadata = CricketFixtureMetadata(fixtureID: "synthetic-test", competitionID: "icc",
                competitionName: "Test Series", format: .test, status: .live, observedAt: now, verified: verified,
                context: .init(innings: [], day: day, matchOrdinal: ordinal))
            let event = EventReference(id: "cricket-fixture:synthetic-test", title: "Pakistan vs Sri Lanka", category: "cricket",
                date: Int64(start.timeIntervalSince1970 * 1000), poster: nil, popular: false,
                teams: .init(home: .init(name: "Pakistan", badge: nil), away: .init(name: "Sri Lanka", badge: nil)), cricketFixture: metadata)
            return .init(event: event)
        }
        let item = HighflySportsAddonClient.Row(id: "sf:test", name: "Pakistan vs Sri Lanka - 1st Test Day 2",
            description: "Pakistan vs Sri Lanka\n10 Nov 2026 · 05:00 UTC", releaseInfo: "10 Nov 2026 · 05:00 UTC", category: "cricket")
        XCTAssertEqual(try HighflySportsAddonClient.select(request: fixture(day: 2, ordinal: 1), rows: [item], now: now), item)
        for invalid in [fixture(day: 1, ordinal: 1), fixture(day: 2, ordinal: 2), fixture(day: 2, ordinal: 1, verified: false)] {
            XCTAssertThrowsError(try HighflySportsAddonClient.select(request: invalid, rows: [item], now: now))
        }
        XCTAssertThrowsError(try HighflySportsAddonClient.select(request: fixture(day: 2, ordinal: 1), rows: [item], now: now.addingTimeInterval(86400)))
    }

    func testDeliveryAndRenewalIdentityRetainTransportAndOriginLimits() {
        let free = URL(string: "https://papacito.cfd/m3u/synthetic/index.m3u8?ft=synthetic-signature")!
        let premium = URL(string: "https://papacito.cfd/m3u/synthetic/index.m3u8?token=synthetic-new-signature")!
        XCTAssertTrue(HighflySportsAddonClient.admitsDelivery(free))
        XCTAssertTrue(HighflySportsAddonClient.admitsDelivery(premium))
        XCTAssertEqual(HighflySportsAddonClient.stableChoiceKey(free), HighflySportsAddonClient.stableChoiceKey(premium))
        for value in ["http://papacito.cfd/m3u/a/index.m3u8?ft=x", "https://papacito.cfd:8443/m3u/a/index.m3u8?ft=x",
                      "https://example.com/m3u/a/index.m3u8?ft=x", "https://127.0.0.1/m3u/a/index.m3u8?ft=x",
                      "https://papacito.cfd/m3u/a/index.m3u8?ft=x&token=y", "https://papacito.cfd/m3u/a/index.m3u8?ft=",
                      "https://papacito.cfd/m3u/a/index.m3u8?url=https://example.com", "https://papacito.cfd/m3u/%2e%2e/index.m3u8?ft=x"] {
            XCTAssertFalse(HighflySportsAddonClient.admitsDelivery(URL(string: value)!))
        }
    }

    func testHeadersExternalAndDRMContractsAreNotSilentlyDropped() throws {
        for json in [#"{"url":"https://example.com/a","behaviorHints":{"proxyHeaders":{}}}"#,
                     #"{"url":"https://example.com/a","headers":{"Authorization":"synthetic"}}"#,
                     #"{"externalUrl":"https://example.com/a"}"#, #"{"url":"https://example.com/a","drm":"clearkey"}"#] {
            XCTAssertFalse(try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(json.utf8)).supported)
        }
        XCTAssertTrue(try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self,
            from: Data(#"{"url":"https://example.com/a","behaviorHints":{"notWebReady":true}}"#.utf8)).supported)
    }

    func testCodesNormalizeOnlyForTheirOwnProvider() throws {
        let code = "00000000-0000-0000-0000-000000000000"
        XCTAssertEqual(try AccountSourceSetup.highfly.validatedLink(code).host, "premium.highfly.to")
        XCTAssertEqual(try AccountSourceSetup.highfly.validatedLink(code + ".0000000000000000").host, "sports.highfly.to")
        XCTAssertThrowsError(try AccountSourceSetup.highfly.validatedLink("https://pengu.uk/" + code + "/manifest.json"))
        XCTAssertThrowsError(try AccountSourceSetup.highfly.validatedLink("https://premium.highfly.to.evil.example/manifest.json"))
    }

    func testFreeAndPremiumResolveThroughSameIDMetadataAndGuardedRelay() async throws {
        for premium in [false, true] {
            let transport = HighflyTestTransport(premium: premium)
            let sessions = try await client(transport).resolve(for: request(), now: kickoff)
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions.first?.providerName, "HF1")
            XCTAssertEqual(sessions.first?.eventBinding?.resourceType, "sport")
            XCTAssertTrue(sessions.first?.requiresGuardedRelay == true)
            XCTAssertTrue(sessions.first?.canRefresh == true)
            XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(sessions[0]))
            let counts = await transport.counts()
            XCTAssertEqual(counts.meta, 1); XCTAssertEqual(counts.stream, 1)
        }
    }

    func testOwnerAccountSourceLeadsAutomaticChoice() {
        let names = ["AS1", "CS1", "Score808", "HF2", "LS1", "HF1"]
        let sources = names.map {
            StreamSession(matchID: "account-order", playableURL: URL(string: "https://example.invalid/\($0).m3u8")!,
                          streamType: .hls, providerName: $0).legacySource
        }
        let ranked = LiveSourceHealthStore.ranked(sources)
        XCTAssertEqual(ranked.prefix(2).map(\.provider), ["HF1", "HF2"], "The owner's paid source is the first choice")
        XCTAssertEqual(Set(ranked.dropFirst(2).map(\.provider)), ["AS1", "CS1", "Score808", "LS1"])
    }

    func testConflictingMetaNeverRequestsStream() async throws {
        let transport = HighflyTestTransport(mode: .conflictingMeta)
        do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("Conflict admitted") }
        catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        let counts = await transport.counts()
        XCTAssertEqual(counts.stream, 0)
    }

    func testOptOutAndChangedAccountDiscardInFlightResult() async throws {
        for mode in [HighflyTestTransport.Mode.disable, .changeAccount] {
            let transport = HighflyTestTransport(mode: mode)
            do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("Stale account admitted") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        }
    }

    func testOneRejectedDestinationDoesNotRemoveValidSibling() async throws {
        let transport = HighflyTestTransport(mode: .badSibling)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertFalse(sessions[0].playableURL.path.contains("rejected"))
    }

    func testTransportErrorsDoNotExposeConfiguredURL() async throws {
        let transport = HighflyTestTransport(mode: .transportError)
        do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("Unexpected success") }
        catch { XCTAssertFalse(error.localizedDescription.contains("synthetic-account")) }
    }

    private func client(_ transport: HighflyTestTransport) -> HighflySportsAddonClient {
        HighflySportsAddonClient(configuration: { await transport.configuration() }, fetch: { try await transport.fetch($0) },
            enabled: { await transport.enabled() }, current: { $0 }, validate: { url in
                if url.path.contains("rejected") { throw CommunitySportsAddonError.unsafeResponse }
            })
    }
}

private actor HighflyTestTransport {
    enum Mode: Sendable { case normal, conflictingMeta, disable, changeAccount, badSibling, transportError }
    private let premium: Bool
    private let mode: Mode
    private var streamCount = 0
    private var metaCount = 0
    init(premium: Bool = false, mode: Mode = .normal) { self.premium = premium; self.mode = mode }
    func configuration() -> URL? {
        URL(string: "https://\(premium ? "premium" : "sports").highfly.to/\(mode == .changeAccount && streamCount > 0 ? "changed" : "synthetic-account")/manifest.json")!
    }
    func enabled() -> Bool { !(mode == .disable && streamCount > 0) }
    func counts() -> (meta: Int, stream: Int) { (metaCount, streamCount) }
    func fetch(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        if mode == .transportError { throw NSError(domain: url.absoluteString, code: 1) }
        let row: [String: Any] = ["id": "streamed:synthetic", "type": "sport", "name": "Arsenal vs Everton",
            "description": "Arsenal vs Everton\n10 Nov 2026 · 18:00 UTC", "releaseInfo": "10 Nov 2026 · 18:00 UTC", "category": "football"]
        let body: [String: Any]
        if url.lastPathComponent == "manifest.json" {
            body = ["id": premium ? "community.sports.streamed.premium" : "community.sports.fly", "version": "1.3.0",
                "resources": ["catalog", "meta", "stream"].map { ["name": $0, "types": ["sport"], "idPrefixes": ["streamed:"]] },
                "catalogs": [["id": "sports_football", "type": "sport"]]]
        } else if url.path.contains("/catalog/") {
            body = ["metas": url.absoluteString.contains("skip=") ? [] : [row]]
        } else if url.path.contains("/meta/") {
            metaCount += 1
            var meta = row
            if mode == .conflictingMeta { meta["name"] = "Different fixture" }
            body = ["meta": meta]
        } else {
            streamCount += 1
            let key = premium ? "token" : "ft"
            var deliveries: [[String: Any]] = [["url": "https://sports.highfly.to/tip.m3u8"],
                ["url": "https://papacito.cfd/m3u/synthetic/index.m3u8?\(key)=synthetic", "behaviorHints": ["notWebReady": true]]]
            if mode == .badSibling { deliveries.insert(["url": "https://papacito.cfd/m3u/rejected/index.m3u8?\(key)=synthetic"], at: 0) }
            body = ["streams": deliveries]
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
