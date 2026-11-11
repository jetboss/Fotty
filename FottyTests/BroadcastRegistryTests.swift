import XCTest
@testable import Fotty

@MainActor
final class BroadcastRegistryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_361_600)
    private let broadcastID = "br:" + String(repeating: "a", count: 64)

    func testWillowWBBLProgrammeRequiresReviewedDomesticIdentityAndCurrentOfficialStatus() throws {
        func makeEvent(competition: String = "wbbl", status: CricketFixtureCatalog.Status = .live,
                       age: TimeInterval = 0, suffix: String = " Women") -> EventReference {
            let home = "Hobart Hurricanes" + suffix, away = "Melbourne Renegades" + suffix
            let metadata = CricketFixtureMetadata(fixtureID: "ca:40629", competitionID: competition,
                competitionName: "Women's Big Bash League", format: .t20, status: status,
                observedAt: now.addingTimeInterval(-age), verified: true, homeTeamID: "ca:96", awayTeamID: "ca:101", matchOrdinal: 9)
            return .init(id: "cricket-fixture:ca:40629", title: "\(home) vs \(away)", category: "cricket",
                date: Int64(now.addingTimeInterval(-7200).timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), cricketFixture: metadata)
        }
        var programme = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "d", count: 64), streamID: "reviewed-tv:willow-main",
            resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket", title: "Hobart Hurricanes vs. Melbourne Renegades",
            participants: ["Hobart Hurricanes Women", "Melbourne Renegades Women"], start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(3600), competitionID: "wbbl", squad: .init(gender: .women, ageGroup: "senior"),
            format: .t20, channelID: CricketBroadcastChannel.willow.canonicalID,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        func matches(_ event: EventReference, _ broadcast: BroadcastRegistrySnapshot.Broadcast) throws -> Int {
            let source = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket", status: .available,
                observedAt: now, expiresAt: now.addingTimeInterval(600))
            let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID, providerCode: "reviewedtv",
                state: .listed, matchMethod: .programme, fixtureFingerprint: fingerprint(event), expiresAt: now.addingTimeInterval(600))
            let snapshot = try validate(.init(schemaVersion: 1, revision: "wbbl", generatedAt: now,
                providers: [source], broadcasts: [broadcast], links: [link]))
            return snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["reviewedtv"], at: now).count
        }
        XCTAssertEqual(try matches(makeEvent(), programme), 1)
        XCTAssertEqual(try matches(makeEvent(competition: "icc"), programme), 0)
        XCTAssertEqual(try matches(makeEvent(status: .finished), programme), 0)
        XCTAssertEqual(try matches(makeEvent(age: 601), programme), 0)
        XCTAssertEqual(try matches(makeEvent(suffix: ""), programme), 0)
        programme.matchOrdinal = 8
        XCTAssertEqual(try matches(makeEvent(), programme), 0)
    }

    func testCurrentCricketRegistryAndFixtureReceiptsFromIndependentRefreshes() async throws {
        let payload = #"""
{"fixture":{"coverage":[{"competitionId":"icc","status":"unavailable","checkedAt":"2026-10-03T04:51:20.153Z","nextStart":"2026-10-03T05:00:00.000Z","expectedFixtureCount":69,"competitionName":"International cricket","fixtureCount":69}],"complete":true,"schemaVersion":1,"checkedAt":"2026-11-04T10:15:19.955Z","revision":"a4fdc34bce4d54b6093a2b0086185415fa421fea278eb0687764ae2c832613aa","fixtures":[{"status":"live","home":{"id":"icc:1:21","name":"United Arab Emirates"},"source":{"name":"ICC","url":"https://www.icc-cricket.com/matches/275772","observedAt":"2026-11-04T10:15:19.955Z","verification":"verified"},"away":{"name":"Oman","id":"icc:1:28"},"competitionName":"ICC CWC League 2, 2023-27","id":"icc:275772","format":"ODI","context":{"phase":"in-play","battingTeamID":"icc:1:28","innings":[{"overs":"50.0","teamID":"icc:1:21","wickets":8,"number":1,"runs":226},{"overs":"10.3","teamID":"icc:1:28","wickets":3,"number":2,"runs":28}],"message":"Second Innings : Oman need 199 runs in 237 balls at 5.03 rpo","target":227,"bowlingTeamID":"icc:1:21","currentInnings":2},"start":"2026-11-04T05:30:00.000Z","competitionId":"icc"}],"sourceStatus":"partial"},"registry":{"broadcasts":[{"verification":"undated","scope":"cricket","providerCode":"communitysports","participants":["United Arab Emirates","Oman"],"expiresAt":"2026-11-04T13:40:19.850Z","title":"🔴 LIVE: United Arab Emirates vs Oman","providerEventID":"nuvio_sport_sktech_sktech_ev_fancode_4250521","id":"br:f92af78bdc7adea68e4e15d24480446619117836855b4fc6787f7ce0b203492d","start":"2026-11-04T09:31:43.399Z","kind":"event","resourceType":"tv","streamID":"nuvio_sport_sktech_sktech_ev_fancode_4250521","issues":[],"sport":"cricket","observedAt":"2026-11-04T09:40:19.850Z","startBasis":"current-listing"}],"schemaVersion":1,"generatedAt":"2026-11-04T10:19:03.717Z","revision":"db2a0371d7e83e41b91b5e24bcb544b1937d7807dbc3f0729fa49f60d5bc9e5e","providers":[{"observedAt":"2026-11-04T09:40:19.850Z","complete":false,"providerCode":"communitysports","scope":"cricket","expiresAt":"2026-11-04T13:40:19.850Z","nextAttemptAt":"2026-11-04T10:20:19.850Z","status":"partial","lastSuccessAt":"2026-11-04T09:40:19.850Z"}],"links":[{"providerCode":"communitysports","fixtureID":"cricket-fixture:icc:275772","matchMethod":"current-event","broadcastID":"br:f92af78bdc7adea68e4e15d24480446619117836855b4fc6787f7ce0b203492d","state":"listed","fixtureFingerprint":{"sport":"cricket","participants":["United Arab Emirates","Oman"],"fixtureID":"cricket-fixture:icc:275772","competitionID":"icc","format":"ODI","start":"2026-11-04T05:30:00.000Z"},"expiresAt":"2026-11-04T10:25:19.955Z"}]}}
"""#.data(using: .utf8)!
        struct Receipts: Decodable { let fixture: CricketFixtureCatalog.Snapshot; let registry: BroadcastRegistrySnapshot }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try XCTUnwrap(BroadcastRegistrySnapshot.date(text))
        }
        let checked = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-04T10:19:15Z"))
        for age: TimeInterval in [60, 240, 300, 599, 601] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            var fixture = try XCTUnwrap(object["fixture"] as? [String: Any])
            var rows = try XCTUnwrap(fixture["fixtures"] as? [[String: Any]])
            var source = try XCTUnwrap(rows[0]["source"] as? [String: Any])
            source["observedAt"] = stamp(checked.addingTimeInterval(-age))
            rows[0]["source"] = source; fixture["fixtures"] = rows; object["fixture"] = fixture
            let receipts = try decoder.decode(Receipts.self, from: JSONSerialization.data(withJSONObject: object))
            let event = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: receipts.fixture, at: checked).first)
            XCTAssertTrue(try XCTUnwrap(event.cricketFixture).verified)
            XCTAssertNotNil(ReviewedSportsFixtureMatcher.requestIdentity(for: .init(event: event)))
            let matches = receipts.registry.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: checked)
            XCTAssertEqual(matches.count, age > 600 ? 0 : 1,
                "Independent fresh official/registry fetches must retain Watch; official age \(age)")
            let domain = "Fotty.CurrentCricketReceipt.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            defaults.set(try JSONSerialization.data(withJSONObject: object["registry"]!), forKey: "Fotty.BroadcastRegistry.accepted.v1")
            let client = BroadcastRegistryClient(defaults: defaults, fetch: { _ in throw URLError(.notConnectedToInternet) })
            let cached = await client.loadCached(at: checked)
            XCTAssertNotNil(cached)
            let index = FixtureStreamDiscoveryIndex()
            index.updateEnabledProviders(["communitysports"], revision: 1)
            XCTAssertEqual(client.lookup(for: .init(event: event), enabledProviderCodes: index.enabledProviderCodes, at: checked).count,
                age > 600 ? 0 : 1)
            let action = CurrentEventBroadcastPolicy.action(for: event, in: [event], at: checked, discoveryIndex: index, registry: client)
            XCTAssertEqual(action != nil, age < 600, "Normal Watch must agree with the registry")
            if age == 601 {
                let request = StreamPlaybackRequest(event: event)
                XCTAssertFalse(LiveStreamResolver.needsCurrentCricketRegistry(request, providerCode: "communitysports", at: checked))
                XCTAssertTrue(LiveStreamResolver.isUnassociatedCurrentCricketMiss(CommunitySportsAddonError.matchNotFound,
                    request: request, providerCode: "communitysports", registered: [], at: checked),
                    "Expired local authority cannot withdraw a separately refreshed cloud listing")
                XCTAssertNil(action, "Pending authority must not itself enable playback")
            }
            if age == 300 {
                // Replay the actual cold-start ordering: preflight begins while
                // the shared owner is still fetching this valid association.
                let coldDomain = "Fotty.CurrentCricketCold.\(UUID().uuidString)"
                let coldDefaults = try XCTUnwrap(UserDefaults(suiteName: coldDomain))
                defer { coldDefaults.removePersistentDomain(forName: coldDomain) }
                let began = expectation(description: "registry owner started")
                var requests = 0
                var finish: CheckedContinuation<(Data, URLResponse), Error>?
                var endpoint: URL?
                let cold = BroadcastRegistryClient(defaults: coldDefaults, fetch: { request in
                    requests += 1; endpoint = request.url
                    return try await withCheckedThrowingContinuation { continuation in
                        finish = continuation; began.fulfill()
                    }
                })
                let owner = Task { await cold.refresh(at: checked, force: true) }
                await fulfillment(of: [began], timeout: 2)
                XCTAssertTrue(cold.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: checked).isEmpty)
                let joined = Task { await LiveStreamResolver.optionalRegistryMatches(for: .init(event: event),
                    providerCode: "communitysports", registry: cold, at: checked) }
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(requests, 1, "Preflight must join the existing registry owner")
                finish?.resume(returning: (try JSONSerialization.data(withJSONObject: object["registry"]!),
                    HTTPURLResponse(url: try XCTUnwrap(endpoint), statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!))
                finish = nil
                _ = await owner.value
                let resolved = await joined.value
                XCTAssertEqual(resolved.count, 1, "CS must see the exact ID instead of a generated-clock catalog miss")
                XCTAssertEqual(requests, 1)

                // An unassociated catalog miss is not a negative observation of
                // this literal ID; a subsequent registry arrival retains Watch.
                let pending = FixtureStreamDiscoveryIndex()
                pending.updateEnabledProviders(["communitysports"], revision: 1)
                let request = StreamPlaybackRequest(event: event)
                let ticket = try XCTUnwrap(pending.begin(for: request, providerCode: "communitysports", preflight: true, at: checked))
                XCTAssertTrue(LiveStreamResolver.isUnassociatedCurrentCricketMiss(CommunitySportsAddonError.matchNotFound,
                    request: request, providerCode: "communitysports", registered: [], at: checked))
                pending.abandon(ticket)
                XCTAssertEqual(BroadcastRegistryWatchPolicy.eligible(resolved, for: request,
                    discoveryIndex: pending, at: checked.addingTimeInterval(1)).count, 1)
                XCTAssertNotNil(CurrentEventBroadcastPolicy.action(for: event, in: [event],
                    at: checked.addingTimeInterval(1), discoveryIndex: pending, registry: cold))
                for failure in [CommunitySportsAddonError.conflictingMatch, .streamEntriesEmpty,
                    .streamAdmissionRejected(entryCount: 1), .httpFailure(statusCode: 403, stage: .metadata)] {
                    XCTAssertFalse(LiveStreamResolver.isUnassociatedCurrentCricketMiss(failure,
                        request: request, providerCode: "communitysports", registered: [], at: checked))
                }
                XCTAssertFalse(LiveStreamResolver.isUnassociatedCurrentCricketMiss(CommunitySportsAddonError.matchNotFound,
                    request: request, providerCode: "communitysports", registered: resolved, at: checked))
                XCTAssertFalse(LiveStreamResolver.isUnassociatedCurrentCricketMiss(CommunitySportsAddonError.matchNotFound,
                    request: request, providerCode: "plaviosports", registered: [], at: checked))
            }
        }
    }

    func testExactAssociationUsesCanonicalFixtureAndEnabledSourceWithoutInventingPlayback() throws {
        let event = football(), request = StreamPlaybackRequest(event: event)
        let snapshot = try validated()
        XCTAssertTrue(snapshot.lookup(for: request, enabledProviderCodes: [], at: now).isEmpty)
        let match = try XCTUnwrap(snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).first)
        XCTAssertEqual(match.broadcast.providerEventID, "source_event")
        XCTAssertEqual(match.link?.fixtureID, event.id)
        XCTAssertTrue(match.matches(request: request, providerCode: "communitysports",
            providerEventID: "source_event", streamID: "source_stream", at: now))
        XCTAssertFalse(match.matches(request: request, providerCode: "plaviosports",
            providerEventID: "source_event", streamID: "source_stream", at: now))
        XCTAssertFalse(match.matches(request: request, providerCode: "communitysports",
            providerEventID: "different_event", streamID: "source_stream", at: now))
        XCTAssertNil(event.cricketFixture)
    }

    func testChangedDateSquadStatusOrHeldAuthorityCannotBorrowLink() throws {
        let snapshot = try validated()
        for event in [football(offset: -7_200), football(women: true), football(status: .finished), football(verified: false)] {
            XCTAssertTrue(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        }
        XCTAssertTrue(snapshot.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"],
            at: now.addingTimeInterval(600)).isEmpty, "Expiry is not renewed by reading cached metadata")
    }

    func testSourceIdentityMustRemainExactAfterCloudAssociation() throws {
        let snapshot = try validated(), request = StreamPlaybackRequest(event: football())
        let match = try XCTUnwrap(snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).first)
        XCTAssertTrue(match.admitsFreshIdentity(sport: "football", participants: ["Chelsea", "Arsenal"],
            start: request.kickoffDate!, providerEventID: "source_event", streamID: "source_stream", at: now))
        XCTAssertFalse(match.admitsFreshIdentity(sport: "football", participants: ["Arsenal", "Chelsea"],
            start: request.kickoffDate!.addingTimeInterval(1), providerEventID: "source_event", streamID: "source_stream", at: now))
        XCTAssertFalse(match.admitsFreshIdentity(sport: "football", participants: ["Arsenal Women", "Chelsea Women"],
            start: request.kickoffDate!, providerEventID: "source_event", streamID: "source_stream", at: now))
    }

    func testVerifiedEarlyLimitedOversCoverageRequiresRegistryAndFreshOriginalIdentity() throws {
        let start = now.addingTimeInterval(-3_600)
        for format in [CricketFixtureCatalog.Format.odi, .t20] {
            let metadata = CricketFixtureMetadata(fixtureID: "icc:274148", competitionID: "icc", competitionName: "ICC",
                format: format, status: .live, observedAt: now, verified: true, homeTeamID: "icc:pak", awayTeamID: "icc:sl")
            let event = EventReference(id: "cricket-fixture:icc:274148", title: "Pakistan vs Sri Lanka", category: "cricket",
                date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "Pakistan", badge: nil), away: .init(name: "Sri Lanka", badge: nil)), cricketFixture: metadata)
            for lead: TimeInterval in [901, 1_800, 3_600] {
                let sourceStart = start.addingTimeInterval(-lead)
                let record = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
                    providerEventID: "early_event", streamID: "early_event", resourceType: "tv", scope: "cricket",
                    kind: .event, sport: "cricket", title: event.displayTitle, participants: ["Pakistan", "Sri Lanka"],
                    start: sourceStart, format: format, observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
                let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID, providerCode: "communitysports",
                    state: .listed, matchMethod: .exact, fixtureFingerprint: fingerprint(event), expiresAt: record.expiresAt,
                    startRelation: "early-coverage")
                let snapshot = try validate(.init(schemaVersion: 1, revision: "early-coverage", generatedAt: now,
                    providers: [coverage(scope: "cricket")], broadcasts: [record], links: [link]))
                let request = StreamPlaybackRequest(event: event)
                let match = try XCTUnwrap(snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).first)
                XCTAssertEqual(match.link?.fixtureFingerprint.start, start)
                XCTAssertEqual(match.broadcast.start, sourceStart)
                XCTAssertTrue(match.admitsFreshIdentity(sport: "cricket", participants: ["Pakistan", "Sri Lanka"], start: sourceStart,
                    providerEventID: "early_event", streamID: "early_event", format: format.rawValue, at: now))
                for delta: TimeInterval in [-1, 1, lead] {
                    XCTAssertFalse(match.admitsFreshIdentity(sport: "cricket", participants: ["Pakistan", "Sri Lanka"], start: sourceStart.addingTimeInterval(delta),
                        providerEventID: "early_event", streamID: "early_event", format: format.rawValue, at: now))
                }
                XCTAssertFalse(match.admitsFreshIdentity(sport: "cricket", participants: ["Pakistan Women", "Sri Lanka Women"], start: sourceStart,
                    providerEventID: "early_event", streamID: "early_event", format: format.rawValue, at: now))
                XCTAssertFalse(match.admitsFreshIdentity(sport: "cricket", participants: ["Pakistan", "Sri Lanka"], start: sourceStart,
                    providerEventID: "changed_event", streamID: "early_event", format: format.rawValue, at: now))
                var payload = try object(snapshot), links = payload["links"] as! [[String: Any]]
                links[0].removeValue(forKey: "startRelation"); payload["links"] = links
                XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
                    .lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty)
                var rows = payload["broadcasts"] as! [[String: Any]]
                links[0]["startRelation"] = "early-coverage"; payload["links"] = links
                for date in [start.addingTimeInterval(-3_601), start.addingTimeInterval(1_800)] {
                    rows[0]["start"] = stamp(date); payload["broadcasts"] = rows
                    XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
                        .lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty)
                }
            }
        }
    }

    func testFreshPremierLeagueFixtureIdentityDoesNotNeedATodayStatusChangeForWatch() throws {
        let kickoff = now.addingTimeInterval(-180), oldStatus = now.addingTimeInterval(-14 * 3_600)
        let row = SportsFixtureCatalog.Fixture(id: "sports-fixture:premier-league:560623", sport: "football", start: stamp(kickoff),
            status: .scheduled, eventKind: .match, title: "Manchester City FC vs Brighton & Hove Albion FC",
            competitionId: "premier-league", competitionName: "Premier League",
            participants: [.init(id: "65", name: "Manchester City FC"), .init(id: "397", name: "Brighton & Hove Albion FC")],
            squad: .init(gender: .men, ageGroup: "senior"),
            source: .init(name: "football-data.org", url: "https://api.football-data.org/v4/matches", observedAt: stamp(now), updatedAt: stamp(oldStatus)))
        let official = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: stamp(now), revision: "fresh-identity",
            sourceStatus: .verified, fixtures: [row], coverage: [.init(sport: "football", competitionId: "premier-league", competitionName: "Premier League",
                status: .covered, checkedAt: stamp(now), fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)])
        let event = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: official, at: now).first)
        let identity = try XCTUnwrap(event.sportsFixture)
        XCTAssertEqual(identity.observedAt, oldStatus)
        XCTAssertEqual(identity.identityReceipt, now)
        XCTAssertFalse(identity.isLive(at: now), "A current fixture fetch does not manufacture LIVE")
        let source = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports", providerEventID: "city_brighton",
            streamID: "city_brighton", resourceType: "tv", scope: "football", kind: .event, sport: "football",
            title: "Manchester City vs Brighton & Hove Albion", participants: ["Manchester City", "Brighton & Hove Albion"], start: kickoff,
            observedAt: now, expiresAt: now.addingTimeInterval(3_600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID, providerCode: "communitysports", state: .listed,
            matchMethod: .exact, fixtureFingerprint: fingerprint(event), expiresAt: now.addingTimeInterval(1_800))
        let snapshot = try validate(.init(schemaVersion: 1, revision: "pl-late-start", generatedAt: now,
            providers: [.init(providerCode: "communitysports", scope: "football", status: .available, observedAt: now, lastSuccessAt: now, expiresAt: source.expiresAt)],
            broadcasts: [source], links: [link]))
        XCTAssertEqual(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now).count, 1)
        XCTAssertTrue(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now.addingTimeInterval(1_801)).isEmpty)
        let encoded = try JSONEncoder().encode(identity), decoded = try JSONDecoder().decode(SportsFixtureMetadata.self, from: encoded)
        XCTAssertEqual(decoded.identityReceipt, now)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]); legacy.removeValue(forKey: "identityObservedAt")
        let old = try JSONDecoder().decode(SportsFixtureMetadata.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(old.identityReceipt, oldStatus)
    }

    func testGenericChannelCannotSupplyFixtureOrProgrammeAssociation() throws {
        let channel = CricketChannelCatalog.event(for: .willow, in: [])
        let record = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "willow_network", streamID: "willow_network", resourceType: "tv", scope: "networks",
            kind: .channel, sport: "cricket", title: "Willow Cricket", participants: [],
            channelID: channel.id, observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .undated, issues: [])
        let snapshot = try validate(.init(schemaVersion: 1, revision: "test", generatedAt: now,
            providers: [coverage(scope: "networks")], broadcasts: [record], links: []))
        let matches = snapshot.lookup(for: .init(event: channel), enabledProviderCodes: ["communitysports"], at: now)
        XCTAssertEqual(matches.count, 1)
        XCTAssertNil(matches.first?.link)
        let stationReceipt = try XCTUnwrap(matches.first).decisionReceipt(at: now)
        XCTAssertEqual(stationReceipt.confidence, .explicitStation)
        XCTAssertEqual(stationReceipt.provenance, .stationTune)
        XCTAssertEqual(stationReceipt.edition, channel.id)
        XCTAssertNil(stationReceipt.fixtureID)
        XCTAssertEqual(stationReceipt.access.entitlement, .unknown)
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 4)), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        var malformed = try object(snapshot)
        malformed["links"] = try object(try validated())["links"]
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(malformed), at: now),
            "A generic channel must not gain a fabricated fixture link")
    }

    func testTestPeriodRetainsExactDayOrdinalAndOriginalWholeMatchStart() throws {
        let event = cricket(day: 4), request = StreamPlaybackRequest(event: event)
        let sourceStart = now.addingTimeInterval(-3_600)
        let fixtureFingerprint = fingerprint(event)
        let record = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "test_day4", streamID: "test_day4", resourceType: "tv", scope: "cricket", kind: .event,
            sport: "cricket", title: "3rd Test day-4 : South Africa vs Australia", participants: ["South Africa", "Australia"],
            start: sourceStart, competitionID: "icc", format: .test, matchOrdinal: 3, day: 4,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID, providerCode: "communitysports",
            state: .listed, matchMethod: .testPeriod, fixtureFingerprint: fixtureFingerprint, expiresAt: now.addingTimeInterval(600))
        let snapshot = try validate(.init(schemaVersion: 1, revision: "test-day4", generatedAt: now,
            providers: [coverage(scope: "cricket")], broadcasts: [record], links: [link]))
        let match = try XCTUnwrap(snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).first)
        XCTAssertNotEqual(sourceStart, request.kickoffDate)
        XCTAssertTrue(match.admitsFreshIdentity(sport: "cricket", participants: ["South Africa", "Australia"],
            start: sourceStart, providerEventID: "test_day4", streamID: "test_day4", format: "Test", matchOrdinal: 3, day: 4, at: now))
        XCTAssertFalse(match.admitsFreshIdentity(sport: "cricket", participants: ["South Africa", "Australia"],
            start: sourceStart, providerEventID: "test_day4", streamID: "test_day4", format: "Test", matchOrdinal: 3, day: 3, at: now))
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 3)), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 4, ordinal: 2)), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
    }

    func testMalformedUnknownDuplicateDanglingAndUnboundedPayloadsAreRejected() throws {
        let original = try object(try validated())
        var cases = [[String: Any]]()
        var next = original; next["schemaVersion"] = 2; cases.append(next)
        next = original; next["providers"] = (original["providers"] as! [Any]) + (original["providers"] as! [Any]); cases.append(next)
        next = original; next["broadcasts"] = (original["broadcasts"] as! [Any]) + (original["broadcasts"] as! [Any]); cases.append(next)
        next = original; next["links"] = (original["links"] as! [Any]) + (original["links"] as! [Any]); cases.append(next)
        next = original; var providers = next["providers"] as! [[String: Any]]; providers[0]["providerCode"] = "unreviewed"; next["providers"] = providers; cases.append(next)
        next = original; var records = next["broadcasts"] as! [[String: Any]]; records[0]["streamID"] = "https://media.example/secret.m3u8"; next["broadcasts"] = records; cases.append(next)
        next = original; records = next["broadcasts"] as! [[String: Any]]; records[0]["issues"] = ["invented-claim"]; next["broadcasts"] = records; cases.append(next)
        next = original; var links = next["links"] as! [[String: Any]]; links[0]["broadcastID"] = "br:" + String(repeating: "b", count: 64); next["links"] = links; cases.append(next)
        for value in cases { XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)) }
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: Data(repeating: 32, count: BroadcastRegistrySnapshot.maximumBytes + 1), at: now))
    }

    func testFailedCoverageAndUnverifiedLinksDoNotHideHealthySiblingOrGrantWatch() throws {
        let accepted = try validated()
        for state in ["needsVerification", "conflicting"] {
            var value = try object(accepted), links = value["links"] as! [[String: Any]]
            links[0]["state"] = state; value["links"] = links
            XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
                .lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        }
        var value = try object(accepted), providers = value["providers"] as! [[String: Any]]
        providers[0]["status"] = "failed"; providers[0]["failure"] = "source-unavailable"
        providers[0].removeValue(forKey: "lastSuccessAt"); value["providers"] = providers
        XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
            .lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        providers[0]["lastSuccessAt"] = providers[0]["observedAt"]; value["providers"] = providers
        let retained = try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
        XCTAssertEqual(retained.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).count, 1,
            "A failed refresh preserves the unexpired accepted identity for fresh descriptor resolution")
        XCTAssertTrue(retained.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"],
            at: now.addingTimeInterval(601)).isEmpty, "Reading a retained listing cannot renew its expiry")
        value = try object(accepted); providers = value["providers"] as! [[String: Any]]
        providers[0]["status"] = "partial"; value["providers"] = providers
        XCTAssertEqual(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
            .lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).count, 1)
    }

    func testCompetingCanonicalOwnersVetoOnlyTheirAmbiguousBroadcast() throws {
        var payload = try object(try validated()), links = payload["links"] as! [[String: Any]]
        var duplicate = links[0], fingerprint = duplicate["fixtureFingerprint"] as! [String: Any]
        fingerprint["fixtureID"] = "sports-fixture:champions-league:competing"
        duplicate["fixtureID"] = fingerprint["fixtureID"]; duplicate["fixtureFingerprint"] = fingerprint
        links.append(duplicate)
        var records = payload["broadcasts"] as! [[String: Any]], sibling = records[0], siblingLink = links[0]
        sibling["id"] = "br:" + String(repeating: "b", count: 64)
        sibling["providerEventID"] = "healthy_source"; sibling["streamID"] = "healthy_stream"
        siblingLink["broadcastID"] = sibling["id"]; records.append(sibling); links.append(siblingLink)
        payload["broadcasts"] = records; payload["links"] = links
        let snapshot = try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
        let matches = snapshot.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.broadcast.providerEventID, "healthy_source")
    }

    func testRetainedConflictingDiagnosticRowsCannotDiscardHealthySibling() throws {
        var value = try object(try validated()), records = value["broadcasts"] as! [[String: Any]]
        var programme = records[0]
        programme["id"] = "br:" + String(repeating: "b", count: 64)
        programme["providerEventID"] = "malformed_programme"; programme["streamID"] = "malformed_programme"
        programme["kind"] = "programme"; programme["verification"] = "conflicting"
        programme["issues"] = ["missing-programme", "missing-participants"]
        programme["participants"] = ["Arsenal", "Arsenal"]; programme.removeValue(forKey: "start")
        var channel = records[0]
        channel["id"] = "br:" + String(repeating: "c", count: 64)
        channel["providerEventID"] = "malformed_channel"; channel["streamID"] = "malformed_channel"
        channel["kind"] = "channel"; channel["verification"] = "conflicting"; channel["issues"] = ["identity-conflict"]
        var interval = records[0]
        interval["id"] = "br:" + String(repeating: "d", count: 64)
        interval["providerEventID"] = "malformed_interval"; interval["streamID"] = "malformed_interval"
        interval["verification"] = "conflicting"; interval["issues"] = ["time-conflict"]
        interval["end"] = stamp(now.addingTimeInterval(-7_200))
        records += [programme, channel, interval]; value["broadcasts"] = records
        let accepted = try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
        XCTAssertEqual(accepted.broadcasts.count, 4, "Diagnostic facts retain their bounded literal source identity")
        XCTAssertEqual(accepted.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).count, 1)
        programme["verification"] = "dated"; records[1] = programme; value["broadcasts"] = records
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now),
            "Only explicitly quarantined diagnostics may retain an incomplete programme shape")
    }

    func testCurrentListingNegativeDiagnosticLinksDoNotDiscardUnrelatedWatchAssociations() throws {
        for failure in ["conflicting-source", "unsupported-Test"] {
            var payload = try currentListingWire(), rows = payload["broadcasts"] as! [[String: Any]]
            var links = payload["links"] as! [[String: Any]]
            links[1]["state"] = "conflicting"
            if failure == "conflicting-source" {
                rows[1]["verification"] = "conflicting"; rows[1]["issues"] = ["catalog-conflict"]
                links[1]["reason"] = "catalog-conflict"
            } else {
                var receipt = links[1]["fixtureFingerprint"] as! [String: Any]
                receipt["format"] = "Test"; links[1]["fixtureFingerprint"] = receipt
                links[1]["reason"] = "format-conflict"
            }
            payload["broadcasts"] = rows; payload["links"] = links
            let snapshot = try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
            XCTAssertEqual(snapshot.broadcasts.count, 2, "Retain the bounded negative diagnostic")
            XCTAssertEqual(snapshot.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).count, 1,
                "A cricket diagnostic must not discard an unrelated healthy Watch association")
            XCTAssertTrue(snapshot.lookup(for: .init(event: limitedOversFixture()), enabledProviderCodes: ["communitysports"], at: now).isEmpty, failure)
        }
    }

    func testListedCurrentEventWireStillRequiresItsExactMarkerClockAndLimitedOversAuthority() throws {
        let original = try currentListingWire()
        let snapshot = try BroadcastRegistrySnapshot.validated(from: bytes(original), at: now)
        XCTAssertEqual(snapshot.lookup(for: .init(event: limitedOversFixture()), enabledProviderCodes: ["communitysports"], at: now).count, 1)
        for failure in ["missing-marker", "missing-clock", "missing-format", "unsupported-Test", "dated-source"] {
            var payload = original, rows = payload["broadcasts"] as! [[String: Any]], links = payload["links"] as! [[String: Any]]
            switch failure {
            case "missing-marker": rows[1].removeValue(forKey: "startBasis")
            case "missing-clock": rows[1].removeValue(forKey: "start")
            case "dated-source": rows[1]["verification"] = "dated"
            default:
                var receipt = links[1]["fixtureFingerprint"] as! [String: Any]
                if failure == "missing-format" { receipt.removeValue(forKey: "format"); receipt.removeValue(forKey: "matchOrdinal") }
                else { receipt["format"] = "Test" }
                links[1]["fixtureFingerprint"] = receipt
            }
            payload["broadcasts"] = rows; payload["links"] = links
            XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now), failure)
        }
    }

    func testMonotonicAcceptanceRejectsReplayAndReceiptRenewal() throws {
        let accepted = try validated()
        var old = try object(accepted); old["generatedAt"] = stamp(now.addingTimeInterval(-1))
        XCTAssertEqual(accepted.accepting(try BroadcastRegistrySnapshot.validated(from: bytes(old), at: now)), accepted)
        var sameGeneration = try object(accepted); sameGeneration["revision"] = "mutated-envelope"
        XCTAssertEqual(accepted.accepting(try BroadcastRegistrySnapshot.validated(from: bytes(sameGeneration), at: now)), accepted)
        var renewal = try object(accepted), rows = renewal["broadcasts"] as! [[String: Any]]
        var renewedLinks = renewal["links"] as! [[String: Any]]
        renewal["generatedAt"] = stamp(now.addingTimeInterval(1)); rows[0]["expiresAt"] = stamp(now.addingTimeInterval(700))
        renewedLinks[0]["expiresAt"] = stamp(now.addingTimeInterval(700)); renewal["broadcasts"] = rows; renewal["links"] = renewedLinks
        let reconciled = accepted.accepting(try BroadcastRegistrySnapshot.validated(from: bytes(renewal), at: now))
        XCTAssertEqual(reconciled.generatedAt, now.addingTimeInterval(1))
        XCTAssertEqual(reconciled.broadcasts, accepted.broadcasts)
        XCTAssertEqual(reconciled.links, accepted.links, "A newer envelope cannot renew a rejected observation's association")
        XCTAssertTrue(reconciled.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"],
            at: now.addingTimeInterval(650)).isEmpty)
        var empty = try object(accepted); empty["generatedAt"] = stamp(now.addingTimeInterval(1)); empty["broadcasts"] = []; empty["links"] = []
        let candidate = try BroadcastRegistrySnapshot.validated(from: bytes(empty), at: now)
        XCTAssertEqual(accepted.accepting(candidate), candidate, "A new valid complete empty registry is meaningful")
    }

    func testRegressingObservationKeepsPriorFactsAndLinksWithoutBlockingFreshSibling() throws {
        let original = try validated()
        var body = try object(original), rows = body["broadcasts"] as! [[String: Any]], links = body["links"] as! [[String: Any]]
        body["generatedAt"] = stamp(now.addingTimeInterval(1))
        rows[0]["observedAt"] = stamp(now.addingTimeInterval(-60)); rows[0]["expiresAt"] = stamp(now.addingTimeInterval(540))
        links[0]["expiresAt"] = stamp(now.addingTimeInterval(540)); links[0]["state"] = "conflicting"
        var fresh = rows[0], freshLink = links[0]
        fresh["id"] = "br:" + String(repeating: "b", count: 64)
        fresh["providerEventID"] = "new_delivery"; fresh["streamID"] = "new_delivery"
        fresh["observedAt"] = stamp(now.addingTimeInterval(1)); fresh["expiresAt"] = stamp(now.addingTimeInterval(601))
        freshLink["broadcastID"] = fresh["id"]; freshLink["state"] = "listed"; freshLink["expiresAt"] = fresh["expiresAt"]
        var providers = body["providers"] as! [[String: Any]]
        providers[0]["observedAt"] = fresh["observedAt"]; providers[0]["expiresAt"] = fresh["expiresAt"]
        body["providers"] = providers
        body["broadcasts"] = rows + [fresh]; body["links"] = links + [freshLink]
        let candidate = try BroadcastRegistrySnapshot.validated(from: bytes(body), at: now)
        let accepted = original.accepting(candidate)
        XCTAssertEqual(accepted.generatedAt, candidate.generatedAt)
        XCTAssertEqual(accepted.broadcasts.first { $0.id == broadcastID }, original.broadcasts.first)
        XCTAssertEqual(accepted.links.filter { $0.broadcastID == broadcastID }, original.links,
            "Rejected source observations cannot import replacement associations")
        XCTAssertEqual(accepted.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).count, 2)
        XCTAssertEqual(accepted.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"],
            at: now.addingTimeInterval(600)).map(\.broadcast.providerEventID), ["new_delivery"])
        XCTAssertNoThrow(try BroadcastRegistrySnapshot.validated(from: accepted.encoded(), at: now))
    }

    func testRetainedObservationCannotDuplicateFreshSiblingIdentityOrImportNewLinks() throws {
        let original = try validated()
        var body = try object(original), rows = body["broadcasts"] as! [[String: Any]], links = body["links"] as! [[String: Any]]
        body["generatedAt"] = stamp(now.addingTimeInterval(1))
        var fresh = rows[0], freshLink = links[0]
        fresh["id"] = "br:" + String(repeating: "b", count: 64)
        fresh["observedAt"] = stamp(now.addingTimeInterval(1)); fresh["expiresAt"] = stamp(now.addingTimeInterval(601))
        freshLink["broadcastID"] = fresh["id"]; freshLink["expiresAt"] = fresh["expiresAt"]
        rows[0]["providerEventID"] = "regressing_changed_event"; rows[0]["streamID"] = "regressing_changed_stream"
        rows[0]["observedAt"] = stamp(now.addingTimeInterval(-60))
        body["broadcasts"] = rows + [fresh]; body["links"] = links + [freshLink]
        let candidate = try BroadcastRegistrySnapshot.validated(from: bytes(body), at: now)
        let accepted = original.accepting(candidate)
        XCTAssertEqual(accepted.generatedAt, candidate.generatedAt)
        XCTAssertEqual(accepted.broadcasts, candidate.broadcasts.filter { $0.id != broadcastID })
        XCTAssertEqual(accepted.links, candidate.links.filter { $0.broadcastID != broadcastID })
        XCTAssertNoThrow(try BroadcastRegistrySnapshot.validated(from: accepted.encoded(), at: now))
    }

    func testMissingOptionalSourceLeagueAndSquadDoNotVetoButExplicitConflictsDo() throws {
        let request = StreamPlaybackRequest(event: football())
        var value = try object(try validated()), rows = value["broadcasts"] as! [[String: Any]]
        rows[0].removeValue(forKey: "competitionID"); rows[0].removeValue(forKey: "squad"); value["broadcasts"] = rows
        XCTAssertEqual(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
            .lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).count, 1)
        rows[0]["competitionID"] = "champions-league"; value["broadcasts"] = rows
        XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
            .lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        rows[0].removeValue(forKey: "competitionID"); rows[0]["squad"] = ["gender": "women", "ageGroup": "senior"]; value["broadcasts"] = rows
        XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(value), at: now)
            .lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty)
    }

    func testWholeTestExactStartDoesNotRequireOptionalDailyContext() throws {
        let event = cricket(day: 4, includesContext: false), request = StreamPlaybackRequest(event: event)
        let record = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "whole_test", streamID: "whole_test", resourceType: "tv", scope: "cricket",
            kind: .event, sport: "cricket", title: "3rd Test : South Africa vs Australia",
            participants: ["South Africa", "Australia"], start: event.kickoffDate,
            competitionID: "icc", format: .test, matchOrdinal: 3,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID,
            providerCode: "communitysports", state: .listed, matchMethod: .exact,
            fixtureFingerprint: fingerprint(event), expiresAt: record.expiresAt)
        let snapshot = try validate(.init(schemaVersion: 1, revision: "whole-test", generatedAt: now,
            providers: [coverage(scope: "cricket")], broadcasts: [record], links: [link]))
        let match = try XCTUnwrap(snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).first)
        XCTAssertTrue(match.admitsFreshIdentity(sport: "cricket", participants: ["South Africa", "Australia"],
            start: event.kickoffDate!, providerEventID: "whole_test", streamID: "whole_test", format: "Test",
            matchOrdinal: 3, at: now))
        XCTAssertEqual(snapshot.lookup(for: .init(event: cricket(day: 5)),
            enabledProviderCodes: ["communitysports"], at: now).count, 1,
            "A day change does not change a source explicitly dated to the original whole-Test kickoff")
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 4, ordinal: 2)),
            enabledProviderCodes: ["communitysports"], at: now).isEmpty, "A known ordinal conflict still vetoes the source")

        for source in ["daily_start", "day_qualifier"] {
            var payload = try object(snapshot), rows = payload["broadcasts"] as! [[String: Any]]
            if source == "daily_start" { rows[0]["start"] = stamp(now.addingTimeInterval(-3_600)) }
            else { rows[0]["day"] = 4 }
            payload["broadcasts"] = rows
            XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
                .lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty,
                "A daily occurrence must not borrow the exact whole-Test route")
        }
    }

    func testDailyTestPeriodStillRequiresCompleteCurrentOfficialAuthority() throws {
        let event = cricket(day: 4), sourceStart = now.addingTimeInterval(-3_600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "daily_test", streamID: "daily_test", resourceType: "tv", scope: "cricket",
            kind: .event, sport: "cricket", title: "3rd Test day-4 : South Africa vs Australia",
            participants: ["South Africa", "Australia"], start: sourceStart, competitionID: "icc", format: .test,
            matchOrdinal: 3, day: 4, observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID,
            providerCode: "communitysports", state: .listed, matchMethod: .testPeriod,
            fixtureFingerprint: fingerprint(event), expiresAt: record.expiresAt)
        let snapshot = try validate(.init(schemaVersion: 1, revision: "daily-test", generatedAt: now,
            providers: [coverage(scope: "cricket")], broadcasts: [record], links: [link]))
        XCTAssertEqual(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now).count, 1)
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 4, includesContext: false)),
            enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        for key in ["day", "matchOrdinal", "end"] {
            var payload = try object(snapshot), links = payload["links"] as! [[String: Any]]
            var receipt = links[0]["fixtureFingerprint"] as! [String: Any]; receipt.removeValue(forKey: key)
            links[0]["fixtureFingerprint"] = receipt; payload["links"] = links
            XCTAssertTrue(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
                .lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        }
    }

    func testDatedTestProgrammeUsesPublishedDailyPeriodWithoutReplacingOfficialStart() throws {
        let event = cricket(day: 4), sourceStart = now.addingTimeInterval(-3_600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "dated_programme", streamID: "dated_programme", resourceType: "tv", scope: "cricket",
            kind: .programme, sport: "cricket", title: "3rd Test day-4 : South Africa vs Australia",
            participants: ["South Africa", "Australia"], start: sourceStart, end: now.addingTimeInterval(3_600),
            competitionID: "icc", format: .test, matchOrdinal: 3, day: 4, channelID: CricketBroadcastChannel.willow.canonicalID,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID, providerCode: "communitysports",
            state: .listed, matchMethod: .programme, fixtureFingerprint: fingerprint(event), expiresAt: now.addingTimeInterval(600))
        let snapshot = try validate(.init(schemaVersion: 1, revision: "programme", generatedAt: now,
            providers: [coverage(scope: "cricket")], broadcasts: [record], links: [link]))
        XCTAssertEqual(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now).count, 1)
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 3)), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        XCTAssertTrue(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["communitysports"], at: now.addingTimeInterval(600)).isEmpty)
        var tooLong = try object(snapshot), rows = tooLong["broadcasts"] as! [[String: Any]]
        rows[0]["expiresAt"] = stamp(now.addingTimeInterval(601)); tooLong["broadcasts"] = rows
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(tooLong), at: now),
            "Programme evidence has its own short lifetime, independent of stable event listings")
    }

    func testWillowLimitedOversProgrammeCanBeginDuringTheOfficialMatchWithoutChangingKickoff() throws {
        for format in [CricketFixtureCatalog.Format.odi, .t20] {
            let event = limitedOversFixture(format: format), request = StreamPlaybackRequest(event: event)
            let snapshot = try limitedOversProgrammeSnapshot(event: event)
            let match = try XCTUnwrap(snapshot.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: now).first)
            let programmeStart = now.addingTimeInterval(-3_600)
            XCTAssertEqual(match.broadcast.start, programmeStart)
            XCTAssertEqual(match.link?.fixtureFingerprint.start, event.kickoffDate)
            XCTAssertEqual(programmeStart.timeIntervalSince(event.kickoffDate!), 3_600,
                "A later linear programme interval is not a conflicting official kickoff")
            XCTAssertEqual(match.broadcast.format, format)
            XCTAssertEqual(match.broadcast.matchOrdinal, 3)
            XCTAssertEqual(match.link?.fixtureFingerprint.matchOrdinal, 3,
                "The independent official ordinal must corroborate the programme's reported match number")
            XCTAssertTrue(match.matches(request: request, providerCode: "reviewedtv",
                providerEventID: match.broadcast.providerEventID, streamID: ReviewedTVPlaylistClient.providerEventID, at: now))
            XCTAssertTrue(match.admitsFreshIdentity(sport: "cricket", participants: ["Afghanistan", "Zimbabwe"],
                start: programmeStart, providerEventID: match.broadcast.providerEventID,
                streamID: ReviewedTVPlaylistClient.providerEventID, format: format.rawValue, matchOrdinal: 3, at: now))
            XCTAssertFalse(match.admitsFreshIdentity(sport: "cricket", participants: ["Afghanistan", "Zimbabwe"],
                start: event.kickoffDate!, providerEventID: match.broadcast.providerEventID,
                streamID: ReviewedTVPlaylistClient.providerEventID, format: format.rawValue, matchOrdinal: 3, at: now),
                "The official kickoff cannot replace a freshly changed source programme interval")
        }
    }

    func testWillowLimitedOversProgrammeRequiresFreshExactOfficialMatchAndFormat() throws {
        let event = limitedOversFixture(), snapshot = try limitedOversProgrammeSnapshot(event: event)
        for changed in [limitedOversFixture(status: .finished), limitedOversFixture(status: .scheduled),
                        limitedOversFixture(observedOffset: -601), limitedOversFixture(format: .t20), limitedOversFixture(ordinal: 4),
                        limitedOversFixture(home: "Afghanistan Women", away: "Zimbabwe Women"),
                        limitedOversFixture(away: "Ireland"), limitedOversFixture(kickoffOffset: -12 * 3_600 - 1)] {
            XCTAssertTrue(snapshot.lookup(for: .init(event: changed), enabledProviderCodes: ["reviewedtv"], at: now).isEmpty,
                "A retained programme must not override fresh official identity or status")
        }
        XCTAssertTrue(snapshot.lookup(for: .init(event: event), enabledProviderCodes: [], at: now).isEmpty)
        XCTAssertTrue(snapshot.lookup(for: .init(event: event), enabledProviderCodes: ["reviewedtv"],
            at: now.addingTimeInterval(600)).isEmpty, "Programme expiry remains finite")
    }

    func testWillowLimitedOversProgrammeCannotBorrowEndedFutureOrMismatchedGuideEvidence() throws {
        let event = limitedOversFixture(), request = StreamPlaybackRequest(event: event)
        let original = try object(try limitedOversProgrammeSnapshot(event: event))
        for failure in ["ended", "future", "format", "ordinal", "opponent", "stale"] {
            var payload = original, rows = payload["broadcasts"] as! [[String: Any]], links = payload["links"] as! [[String: Any]]
            switch failure {
            case "ended":
                rows[0]["end"] = stamp(now.addingTimeInterval(-1))
                rows[0]["observedAt"] = stamp(now.addingTimeInterval(-600))
                rows[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
                links[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
            case "future": rows[0]["start"] = stamp(now.addingTimeInterval(1))
            case "format": rows[0]["format"] = "T20"
            case "ordinal": rows[0]["matchOrdinal"] = 4
            case "opponent": rows[0]["participants"] = ["Afghanistan", "Ireland"]
            default:
                rows[0]["observedAt"] = stamp(now.addingTimeInterval(-601))
                rows[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
                links[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
            }
            payload["broadcasts"] = rows; payload["links"] = links
            let changed = try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
            XCTAssertTrue(changed.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: now).isEmpty, failure)
        }
    }

    func testCurrentGuideQualifiesEnabledCSChannelIndependentlyOfTVPlaybackOptIn() throws {
        let snapshot = try programmeChannelSnapshot(), request = StreamPlaybackRequest(event: cricket(day: 4))
        let csOnly = snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now)
        let derived = try XCTUnwrap(csOnly.first)
        XCTAssertEqual(csOnly.count, 1)
        XCTAssertEqual(derived.broadcast.providerCode, "communitysports")
        XCTAssertEqual(derived.broadcast.kind, .channel)
        XCTAssertNil(derived.link, "No fabricated source link is added to the public registry")
        XCTAssertEqual(derived.programmeAuthority?.broadcast.providerCode, "reviewedtv")
        XCTAssertEqual(derived.broadcast.observedAt, now.addingTimeInterval(-3_600))
        XCTAssertEqual(derived.availabilityObservedAt, now)
        XCTAssertEqual(derived.acceptanceExpiresAt, now.addingTimeInterval(600))
        XCTAssertTrue(derived.matches(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_willow_main", streamID: "nuvio_sport_willow_main", at: now))
        let both = snapshot.lookup(for: request, enabledProviderCodes: ["reviewedtv", "communitysports"], at: now)
        XCTAssertEqual(Set(both.map { $0.broadcast.providerCode }), ["reviewedtv", "communitysports"])
        XCTAssertEqual(snapshot.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: now)
            .map { $0.broadcast.providerCode }, ["reviewedtv"])
        XCTAssertTrue(snapshot.lookup(for: request, enabledProviderCodes: [], at: now).isEmpty)
        XCTAssertFalse(String(decoding: try snapshot.encoded(), as: UTF8.self).contains("programmeAuthority"),
            "Derived provenance is never persisted as a collected fact")
    }

    func testGuideChannelJoinRequiresBothOriginalCurrentFactsAndTheExactFixture() throws {
        let snapshot = try programmeChannelSnapshot(), request = StreamPlaybackRequest(event: cricket(day: 4))
        XCTAssertTrue(snapshot.lookup(for: .init(event: cricket(day: 3)), enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        for failure in ["no_guide", "expired_guide", "expired_channel", "wrong_channel", "wrong_day", "wrong_teams"] {
            var payload = try object(snapshot), records = payload["broadcasts"] as! [[String: Any]], providers = payload["providers"] as! [[String: Any]]
            var links = payload["links"] as! [[String: Any]]
            let guide = records.firstIndex { $0["providerCode"] as? String == "reviewedtv" }!
            let channel = records.firstIndex { $0["providerCode"] as? String == "communitysports" }!
            switch failure {
            case "no_guide": records.remove(at: guide); links = []
            case "expired_guide":
                records[guide]["observedAt"] = stamp(now.addingTimeInterval(-601))
                records[guide]["expiresAt"] = stamp(now.addingTimeInterval(-1))
                links[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
                let index = providers.firstIndex { $0["providerCode"] as? String == "reviewedtv" }!
                providers[index]["observedAt"] = stamp(now.addingTimeInterval(-601))
                providers[index]["expiresAt"] = stamp(now.addingTimeInterval(-1))
            case "expired_channel":
                records[channel]["expiresAt"] = stamp(now.addingTimeInterval(-1))
                let index = providers.firstIndex { $0["providerCode"] as? String == "communitysports" }!
                providers[index]["expiresAt"] = stamp(now.addingTimeInterval(-1))
            case "wrong_channel":
                records[channel]["channelID"] = CricketBroadcastChannel.foxCricket.canonicalID
                // Willow's typed US proof cannot be copied onto another station.
                records[channel].removeValue(forKey: "stationMarket")
            case "wrong_day": records[guide]["day"] = 3
            default: records[guide]["participants"] = ["South Africa Women", "Australia Women"]
            }
            payload["broadcasts"] = records; payload["providers"] = providers; payload["links"] = links
            let changed = try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
            XCTAssertTrue(changed.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty, failure)
        }
    }

    func testProgrammeChannelJoinRequiresExplicitUSMarketBeforeGrantingFixtureWatch() throws {
        let snapshot = try programmeChannelSnapshot(), request = StreamPlaybackRequest(event: cricket(day: 4))
        let channelRequest = StreamPlaybackRequest(event: CricketChannelCatalog.event(for: .willow, in: []))
        var unknown = try object(snapshot), rows = unknown["broadcasts"] as! [[String: Any]]
        let source = rows.firstIndex { $0["providerCode"] as? String == "communitysports" }!
        rows[source].removeValue(forKey: "stationMarket"); unknown["broadcasts"] = rows
        let withoutMarket = try BroadcastRegistrySnapshot.validated(from: bytes(unknown), at: now)
        XCTAssertTrue(withoutMarket.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty)
        XCTAssertEqual(withoutMarket.lookup(for: channelRequest, enabledProviderCodes: ["communitysports"], at: now).count, 1,
            "An unknown/other regional network remains independently browsable")
        for market in ["UK", "Unknown", "us", "USA"] {
            rows[source]["stationMarket"] = market; unknown["broadcasts"] = rows
            XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(unknown), at: now), market)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { input in
                let text = try input.singleValueContainer().decode(String.self)
                guard let value = BroadcastRegistrySnapshot.date(text) else { throw BroadcastRegistrySnapshot.ValidationError.invalidRecord }
                return value
            }
            let unvalidated = try decoder.decode(BroadcastRegistrySnapshot.self, from: bytes(unknown))
            XCTAssertTrue(unvalidated.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).isEmpty,
                "An unknown market cannot acquire private programme proof even before wire validation")
        }
    }

    func testTypedUSNetworkProofRetainsItsFetchedCohortWithoutInventingNetworkScope() throws {
        let snapshot = try programmeChannelSnapshot(), request = StreamPlaybackRequest(event: cricket(day: 4))
        for scope in ["cricket", "live", "networks"] {
            var body = try object(snapshot), rows = body["broadcasts"] as! [[String: Any]], providers = body["providers"] as! [[String: Any]]
            let source = rows.firstIndex { $0["providerCode"] as? String == "communitysports" }!
            let provider = providers.firstIndex { $0["providerCode"] as? String == "communitysports" }!
            rows[source]["scope"] = scope; providers[provider]["scope"] = scope
            body["broadcasts"] = rows; body["providers"] = providers
            let admitted = try BroadcastRegistrySnapshot.validated(from: bytes(body), at: now)
            let derived = try XCTUnwrap(admitted.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now).first)
            XCTAssertEqual(derived.broadcast.scope, scope)
            XCTAssertEqual(derived.broadcast.stationMarket, "US")
        }
    }

    func testNewGuideOpportunityOutranksOnlyAnOlderNegativeWithoutRenewingChannelFacts() throws {
        let snapshot = try programmeChannelSnapshot(), request = StreamPlaybackRequest(event: cricket(day: 4))
        let matches = snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now)
        let index = FixtureStreamDiscoveryIndex(); index.updateEnabledProviders(["communitysports"], revision: 1)
        let old = now.addingTimeInterval(-300)
        let first = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: old))
        index.complete(first, sessions: [], at: old)
        XCTAssertEqual(BroadcastRegistryWatchPolicy.eligible(matches, for: request, discoveryIndex: index, at: now).count, 1)
        XCTAssertEqual(matches[0].broadcast.observedAt, now.addingTimeInterval(-3_600))
        let later = now.addingTimeInterval(1)
        let second = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: later))
        index.complete(second, sessions: [], at: later)
        XCTAssertTrue(BroadcastRegistryWatchPolicy.eligible(matches, for: request, discoveryIndex: index, at: later).isEmpty)
        XCTAssertTrue(snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: now.addingTimeInterval(600)).isEmpty)
    }

    private func programmeChannelSnapshot() throws -> BroadcastRegistrySnapshot {
        let event = cricket(day: 4)
        let programme = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "b", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "c", count: 64), streamID: ReviewedTVPlaylistClient.providerEventID,
            resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket", title: "South Africa vs Australia, 3rd Test Day 4",
            participants: ["South Africa", "Australia"], start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(3_600),
            competitionID: "icc", format: .test, matchOrdinal: 3, day: 4, channelID: CricketBroadcastChannel.willow.canonicalID,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let channel = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "nuvio_sport_willow_main", streamID: "nuvio_sport_willow_main", resourceType: "tv", scope: "networks",
            kind: .channel, sport: "cricket", title: "Willow Cricket", participants: [], channelID: CricketBroadcastChannel.willow.canonicalID,
            stationMarket: "US", observedAt: now.addingTimeInterval(-3_600), expiresAt: now.addingTimeInterval(3_600), verification: .undated, issues: [])
        let guide = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket", status: .available,
            observedAt: now, expiresAt: programme.expiresAt)
        let source = BroadcastRegistrySnapshot.Provider(providerCode: "communitysports", scope: "networks", status: .available,
            observedAt: channel.observedAt, expiresAt: channel.expiresAt)
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: programme.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .programme, fixtureFingerprint: fingerprint(event), expiresAt: programme.expiresAt)
        return try validate(.init(schemaVersion: 1, revision: "programme-channels", generatedAt: now,
            providers: [guide, source], broadcasts: [programme, channel], links: [link]))
    }

    func testClientFailureRetainsOriginalReceiptAndCancellationCanRetry() async throws {
        let suite = "Fotty.BroadcastRegistryTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let payload = try validated().encoded()
        var calls = 0, failure: Error?
        let client = BroadcastRegistryClient(defaults: defaults) { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/api/live/broadcasts")
            XCTAssertNil(request.httpBody)
            if let failure { throw failure }
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
        }
        let firstResult = await client.refresh(at: now)
        let first = try XCTUnwrap(firstResult)
        failure = URLError(.notConnectedToInternet)
        let failed = await client.refresh(at: now.addingTimeInterval(1), force: true)
        XCTAssertEqual(failed, first)
        XCTAssertEqual(failed?.broadcasts.first?.observedAt, now)
        _ = await client.refresh(at: now.addingTimeInterval(2))
        XCTAssertEqual(calls, 2)
        failure = CancellationError()
        _ = await client.refresh(at: now.addingTimeInterval(3), force: true)
        failure = nil
        _ = await client.refresh(at: now.addingTimeInterval(4))
        XCTAssertEqual(calls, 4, "A cancelled owner cannot retain a completed refresh throttle")
        let restored = BroadcastRegistryClient(defaults: defaults) { _ in XCTFail("Cache load must not fetch"); throw URLError(.unknown) }
        XCTAssertNil(restored.cachedSnapshot(at: now.addingTimeInterval(5)), "A row getter must not decode a cold multi-megabyte cache")
        let loaded = await restored.loadCached(at: now.addingTimeInterval(5))
        XCTAssertEqual(loaded, first)
        XCTAssertEqual(restored.cachedSnapshot(at: now.addingTimeInterval(5)), first)
        XCTAssertEqual(restored.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"],
            at: now.addingTimeInterval(5)).count, 1, "Prepared row lookup shares the same validated association")
        XCTAssertTrue(restored.cachedSnapshot(at: now.addingTimeInterval(601))?
            .lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now.addingTimeInterval(601)).isEmpty == true)
    }

    func testClientRejectsUnsafeFinalResponseAndHTTPErrorWithoutCaching() async throws {
        for code in [200, 503] {
            let suite = "Fotty.BroadcastRegistryTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let payload = try validated().encoded()
            let client = BroadcastRegistryClient(defaults: defaults) { request in
                (payload, HTTPURLResponse(url: code == 200 ? URL(string: "https://elsewhere.example/api/live/broadcasts")! : request.url!,
                    statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
            let result = await client.refresh(at: now)
            XCTAssertNil(result)
            XCTAssertNil(client.cachedSnapshot(at: now))
        }
    }

    func testEdgeParticipantLimitAndHarmlessEmojiTextPreserveHealthySibling() throws {
        var payload = try object(try validated())
        var rows = payload["broadcasts"] as! [[String: Any]]
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        for (offset, title) in ["Long participant", "Family 👨\u{200D}👩\u{200D}👧\u{200D}👦", "England " + england].enumerated() {
            var diagnostic = rows[0]
            diagnostic["id"] = "br:" + String(repeating: String(offset + 1), count: 64)
            diagnostic["providerEventID"] = "display_\(offset)"
            diagnostic["streamID"] = "display_\(offset)"
            diagnostic["title"] = title
            if offset == 0 { diagnostic["participants"] = [String(repeating: "A", count: 171), "Other Team"] }
            rows.append(diagnostic)
        }
        payload["broadcasts"] = rows
        let accepted = try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now)
        XCTAssertEqual(accepted.broadcasts.count, 4)
        XCTAssertEqual(accepted.broadcasts[1].participants[0].count, 171)
        XCTAssertEqual(accepted.broadcasts[3].title, "England " + england)
        XCTAssertEqual(accepted.lookup(for: .init(event: football()), enabledProviderCodes: ["communitysports"], at: now).count, 1,
            "An unmatched observation must not erase the existing exact association")
        rows[1]["participants"] = [String(repeating: "A", count: 257), "Other Team"]
        payload["broadcasts"] = rows
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now))
    }

    func testDisplayTextRejectsC1AndBidiWhileReferenceIDsStillRejectFormatScalars() throws {
        let original = try object(try validated())
        for scalar in ["\u{0085}", "\u{061C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202E}", "\u{2066}", "\u{2069}"] {
            var payload = original, rows = payload["broadcasts"] as! [[String: Any]]
            rows[0]["title"] = "Fixture" + scalar + "Title"
            payload["broadcasts"] = rows
            XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now))
        }
        for scalar in ["\u{0085}", "\u{200D}", "\u{E0067}"] {
            var payload = original, rows = payload["broadcasts"] as! [[String: Any]]
            rows[0]["providerEventID"] = "source" + scalar + "event"
            payload["broadcasts"] = rows
            XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: bytes(payload), at: now))
        }
    }

    private func football(offset: TimeInterval = -3_600, women: Bool = false,
                          status: SportsFixtureCatalog.Status = .live, verified: Bool = true) -> EventReference {
        let home = women ? "Arsenal Women" : "Arsenal", away = women ? "Chelsea Women" : "Chelsea"
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:arsenal-chelsea", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "\(home) vs \(away)",
            participants: [.init(id: "arsenal", name: home), .init(id: "chelsea", name: away)],
            squad: .init(gender: women ? .women : .men, ageGroup: "senior"), status: status, observedAt: now, verified: verified)
        return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), sportsFixture: metadata)
    }

    private func cricket(day: Int, ordinal: Int = 3, includesContext: Bool = true) -> EventReference {
        let start = now.addingTimeInterval(-3 * 86_400), end = start.addingTimeInterval(5 * 86_400)
        let context = CricketMatchContext(innings: [.init(number: 1, teamID: "icc:1:7", runs: 300, wickets: 5)],
            currentInnings: 1, day: day, matchOrdinal: ordinal, matchEndsAt: stamp(end), phase: .inPlay)
        let metadata = CricketFixtureMetadata(fixtureID: "icc:269792", competitionID: "icc", competitionName: "ICC",
            format: .test, status: .live, observedAt: now, verified: true, context: includesContext ? context : nil,
            homeTeamID: "icc:1:7", awayTeamID: "icc:1:1")
        return .init(id: "cricket-fixture:icc:269792", title: "South Africa vs Australia", category: "cricket",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "South Africa", badge: nil), away: .init(name: "Australia", badge: nil)), cricketFixture: metadata)
    }

    private func limitedOversFixture(format: CricketFixtureCatalog.Format = .odi,
                                     status: CricketFixtureCatalog.Status = .live,
                                     observedOffset: TimeInterval = 0, home: String = "Afghanistan", away: String = "Zimbabwe",
                                     kickoffOffset: TimeInterval = -7_200, ordinal: Int? = 3) -> EventReference {
        let metadata = CricketFixtureMetadata(fixtureID: "icc:limited-overs", competitionID: "icc", competitionName: "ICC",
            format: format, status: status, observedAt: now.addingTimeInterval(observedOffset), verified: true,
            homeTeamID: "icc:afg", awayTeamID: "icc:zim", matchOrdinal: ordinal)
        return .init(id: "cricket-fixture:icc:limited-overs", title: "\(home) vs \(away)", category: "cricket",
            date: Int64(now.addingTimeInterval(kickoffOffset).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), cricketFixture: metadata)
    }

    private func limitedOversProgrammeSnapshot(event: EventReference) throws -> BroadcastRegistrySnapshot {
        let programme = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "d", count: 64),
            streamID: ReviewedTVPlaylistClient.providerEventID, resourceType: "tv", scope: "cricket", kind: .programme,
            sport: "cricket", title: "Afghanistan vs. Zimbabwe", participants: ["Afghanistan", "Zimbabwe"],
            start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(3_600), format: event.cricketFixture?.format,
            matchOrdinal: 3, channelID: CricketBroadcastChannel.willow.canonicalID,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let guide = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket", status: .available,
            observedAt: now, expiresAt: programme.expiresAt)
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: programme.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .programme, fixtureFingerprint: fingerprint(event), expiresAt: programme.expiresAt)
        return try validate(.init(schemaVersion: 1, revision: "limited-overs-programme", generatedAt: now,
            providers: [guide], broadcasts: [programme], links: [link]))
    }

    private func currentListingWire() throws -> [String: Any] {
        var payload = try object(try validated())
        var rows = payload["broadcasts"] as! [[String: Any]], links = payload["links"] as! [[String: Any]]
        var providers = payload["providers"] as! [[String: Any]]
        let event = limitedOversFixture(), id = "br:" + String(repeating: "b", count: 64)
        let sourceID = "nuvio_sport_sktech_sktech_ev_fancode_4250335"
        rows.append(["id": id, "providerCode": "communitysports", "providerEventID": sourceID, "streamID": sourceID,
                     "resourceType": "tv", "scope": "cricket", "kind": "event", "sport": "cricket",
                     "title": "🔴 LIVE: Afghanistan vs Zimbabwe", "participants": ["Afghanistan", "Zimbabwe"],
                     "start": stamp(now.addingTimeInterval(-60)), "startBasis": "current-listing",
                     "observedAt": stamp(now), "expiresAt": stamp(now.addingTimeInterval(600)),
                     "verification": "undated", "issues": [String]()])
        providers.append(["providerCode": "communitysports", "scope": "cricket", "status": "available",
                          "observedAt": stamp(now), "lastSuccessAt": stamp(now), "expiresAt": stamp(now.addingTimeInterval(600))])
        links.append(["fixtureID": event.id, "broadcastID": id, "providerCode": "communitysports", "state": "listed",
                      "matchMethod": "current-event", "expiresAt": stamp(now.addingTimeInterval(600)),
                      "fixtureFingerprint": ["fixtureID": event.id, "sport": "cricket", "start": stamp(event.kickoffDate!),
                                             "participants": ["Afghanistan", "Zimbabwe"], "format": "ODI", "matchOrdinal": 3,
                                             "competitionID": "icc"]])
        payload["broadcasts"] = rows; payload["links"] = links; payload["providers"] = providers
        return payload
    }

    private func coverage(scope: String = "football") -> BroadcastRegistrySnapshot.Provider {
        .init(providerCode: "communitysports", scope: scope, status: .available, observedAt: now,
            lastSuccessAt: now, expiresAt: now.addingTimeInterval(600))
    }
    private func fingerprint(_ event: EventReference) -> BroadcastRegistrySnapshot.Fingerprint {
        .init(fixtureID: event.id, sport: event.normalizedCategory, start: event.kickoffDate!,
            participants: [event.homeName, event.awayName], competitionID: event.competitionID ?? event.cricketFixture?.competitionID,
            squad: event.sportsFixture?.squad, format: event.cricketFixture?.format,
            matchOrdinal: event.cricketFixture?.matchOrdinal ?? event.cricketFixture?.context?.matchOrdinal, day: event.cricketFixture?.context?.day,
            end: event.cricketFixture?.context?.matchEndsAt.flatMap(BroadcastRegistrySnapshot.date))
    }
    private func validated() throws -> BroadcastRegistrySnapshot {
        let event = football()
        let broadcast = BroadcastRegistrySnapshot.Broadcast(id: broadcastID, providerCode: "communitysports",
            providerEventID: "source_event", streamID: "source_stream", resourceType: "tv", scope: "football", kind: .event,
            sport: "football", title: event.displayTitle, participants: [event.homeName, event.awayName], start: event.kickoffDate,
            competitionID: event.competitionID, squad: event.sportsFixture?.squad,
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcastID, providerCode: "communitysports",
            state: .listed, matchMethod: .exact, fixtureFingerprint: fingerprint(event), expiresAt: now.addingTimeInterval(600))
        return try validate(.init(schemaVersion: 1, revision: "test", generatedAt: now,
            providers: [coverage()], broadcasts: [broadcast], links: [link]))
    }
    private func validate(_ value: BroadcastRegistrySnapshot) throws -> BroadcastRegistrySnapshot {
        try BroadcastRegistrySnapshot.validated(from: value.encoded(), at: now)
    }
    private func object(_ value: BroadcastRegistrySnapshot) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
    }
    private func bytes(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
