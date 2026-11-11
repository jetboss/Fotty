import XCTest
@testable import Fotty

final class PlavioSportsAddonTests: XCTestCase {
    private let kickoff = ISO8601DateFormatter().date(from: "2026-10-23T21:30:00Z")!
    private let fixtureID = "plaviohdtv-sfly-streamed:football-gimnasia-platense-20749"
    private let delivery = "https://papacito.cfd/live/fixture/index.m3u8?ft=fixture%2Bsignature%2Fvalue"

    private var roxieNow: Date { ISO8601DateFormatter().date(from: "2026-10-31T15:30:00Z")! }
    private var roxieID: String { "plaviohdtv-roxie-ev-soccer-streams-11-fixture" }
    private var roxieDelivery: String { "https://admin2.formaturamaxi.com.br/fixture.m3u8" }
    private func roxieRow(id: String? = nil, name: String = "Manchester City vs Brighton",
        description: String = "Starts October 31, 2026 8:00 AM (site time) · 1 channel") -> PlavioSportsCatalogEntry {
        .init(id: id ?? roxieID, name: name, description: description, genres: ["Football"])
    }
    @MainActor private func roxieContext(status: SportsFixtureCatalog.Status = .live,
        observed: Date? = nil, competition: String = "premier-league") -> (StreamPlaybackRequest, SportsFixtureCatalog.Snapshot) {
        let start = roxieNow.addingTimeInterval(-1800), stamp = ISO8601DateFormatter()
        let fixture = SportsFixtureCatalog.Fixture(id: "sports-fixture:" + competition + ":roxie-fixture", sport: "football",
            start: stamp.string(from: start), status: status, eventKind: .match, title: "Manchester City FC vs Brighton & Hove Albion FC",
            competitionId: competition, competitionName: competition == "premier-league" ? "Premier League" : "UEFA Champions League",
            participants: [.init(id: "football-data:65", name: "Manchester City FC", role: "home"),
                           .init(id: "football-data:397", name: "Brighton & Hove Albion FC", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), source: .init(name: "football-data.org", url: "https://api.football-data.org/v4/matches",
                observedAt: stamp.string(from: observed ?? roxieNow), updatedAt: stamp.string(from: observed ?? roxieNow)))
        let snapshot = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: stamp.string(from: roxieNow),
            revision: "roxie-regression", sourceStatus: .verified, fixtures: [fixture], coverage: [
                .init(sport: "football", competitionId: competition, competitionName: fixture.competitionName, status: .covered,
                    checkedAt: fixture.source.observedAt, fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)])
        let metadata = SportsFixtureMetadata(fixtureID: fixture.id, sport: "football", competitionID: competition,
            competitionName: fixture.competitionName, eventKind: .match, title: fixture.title, participants: fixture.participants,
            squad: fixture.squad, status: status, observedAt: observed ?? roxieNow, verified: true,
            identityObservedAt: observed ?? roxieNow)
        let event = AnalyticalDataEngine.EventReference(id: fixture.id, title: fixture.title, category: "football",
            date: Int64(start.timeIntervalSince1970 * 1000), poster: nil, popular: false,
            teams: .init(home: .init(name: fixture.participants[0].name, badge: nil), away: .init(name: fixture.participants[1].name, badge: nil)), sportsFixture: metadata, competitionID: competition)
        return (.init(event: event), snapshot)
    }
    @MainActor func testRoxieUsesOfficialLiveIdentityWithoutConvertingItsSiteClock() throws {
        for competition in ["premier-league", "champions-league"] {
            let (request, snapshot) = roxieContext(competition: competition)
            XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow()], official: snapshot, at: roxieNow), .matched(roxieRow()))
            XCTAssertEqual(request.kickoffDate, roxieNow.addingTimeInterval(-1800), "The provider wall clock never rewrites official kickoff")
            XCTAssertEqual(PlavioSportsAddonClient.roxieIdentity(roxieRow())?.wallClock, "08:00AM")
        }
    }
    @MainActor func testRoxieRejectsStaleFinishedOrMissingOfficialAuthority() {
        for status in [SportsFixtureCatalog.Status.finished, .cancelled, .postponed, .unknown] {
            let (request, snapshot) = roxieContext(status: status)
            XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow()], official: snapshot, at: roxieNow), .missing)
        }
        let (request, snapshot) = roxieContext(observed: roxieNow.addingTimeInterval(-1801))
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow()], official: snapshot, at: roxieNow), .missing)
        let (fresh, _) = roxieContext()
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: fresh, from: [roxieRow()], official: nil, at: roxieNow), .missing)
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: self.request(), from: [roxieRow()], official: snapshot, at: roxieNow), .missing)
    }
    @MainActor func testRoxieRejectsWrongDatesSquadsReplaysAndAmbiguousProviderIDs() {
        let (request, snapshot) = roxieContext()
        let rejected = [roxieRow(description: "Starts November 1, 2026 8:00 AM (site time) · 1 channel"),
            roxieRow(name: "Manchester City Women vs Brighton Women"), roxieRow(name: "Manchester City U21 vs Brighton U21"),
            roxieRow(name: "Manchester City vs Brighton Highlights")]
        for row in rejected { XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [row], official: snapshot, at: roxieNow), .missing) }
        let sibling = roxieRow(id: roxieID + "-second")
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow(), sibling], official: snapshot, at: roxieNow), .conflicting)
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow(), roxieRow(name: "Manchester City vs Chelsea")], official: snapshot, at: roxieNow), .conflicting)
        XCTAssertNil(PlavioSportsAddonClient.roxieIdentity(roxieRow(description: "Starts February 31, 2026 8:00 AM (site time) · 1 channel")))
    }
    @MainActor func testRoxieRejectsMultipleOfficialFixturesForThePairOnThatDate() {
        let (request, snapshot) = roxieContext(); let old = snapshot.fixtures[0]
        let other = SportsFixtureCatalog.Fixture(id: old.id + "-second", sport: old.sport, start: old.start, status: old.status,
            eventKind: old.eventKind, title: old.title, competitionId: old.competitionId, competitionName: old.competitionName,
            participants: old.participants, squad: old.squad, source: old.source)
        let ambiguous = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: snapshot.checkedAt,
            revision: "ambiguous", sourceStatus: .verified, fixtures: [old, other], coverage: snapshot.coverage)
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow()], official: ambiguous, at: roxieNow), .conflicting)
    }
    @MainActor func testRoxieKeepsScheduledStatusAndRejectsFreshPollWithStaleLiveStatus() {
        let (scheduled, scheduledSnapshot) = roxieContext(status: .scheduled)
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: scheduled, from: [roxieRow()], official: scheduledSnapshot, at: roxieNow), .matched(roxieRow()))
        XCTAssertFalse(scheduled.preferredEvent!.sportsFixture!.isLive(at: roxieNow), "A source listing cannot manufacture LIVE")
        let (request, snapshot) = roxieContext(); let old = snapshot.fixtures[0]
        let source = SportsFixtureCatalog.Source(name: old.source.name, url: old.source.url, observedAt: old.source.observedAt,
            updatedAt: ISO8601DateFormatter().string(from: roxieNow.addingTimeInterval(-1801)))
        let staleLive = SportsFixtureCatalog.Fixture(id: old.id, sport: old.sport, start: old.start, status: .live, eventKind: old.eventKind,
            title: old.title, competitionId: old.competitionId, competitionName: old.competitionName, participants: old.participants, squad: old.squad, source: source)
        let stale = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: snapshot.checkedAt, revision: "stale-live",
            sourceStatus: .verified, fixtures: [staleLive], coverage: snapshot.coverage)
        XCTAssertEqual(PlavioSportsAddonClient.selectRoxieMatch(for: request, from: [roxieRow()], official: stale, at: roxieNow), .conflicting)
    }

    func testReviewedRoxieDeliveryKeepsTransportAndHeaderBoundaries() throws {
        XCTAssertTrue(PlavioSportsAddonClient.isAdmittedDelivery(URL(string: roxieDelivery)!))
        XCTAssertEqual(try sessions([["url": roxieDelivery, "behaviorHints": ["notWebReady": true]]]).count, 1,
            "Stremio notWebReady is a browser hint, not a native HLS prohibition")
        for url in [roxieDelivery.replacingOccurrences(of: "https:", with: "http:"), roxieDelivery + "?ft=token",
            roxieDelivery + "#fragment", roxieDelivery.replacingOccurrences(of: "/fixture", with: "/nested/fixture"),
            roxieDelivery.replacingOccurrences(of: "/fixture", with: "/%66ixture"),
            roxieDelivery.replacingOccurrences(of: ".br/", with: ".br:8443/"),
            roxieDelivery.replacingOccurrences(of: "admin2.", with: "other."),
            roxieDelivery.replacingOccurrences(of: "//admin2", with: "//user:pass@admin2") ] {
            XCTAssertFalse(PlavioSportsAddonClient.isAdmittedDelivery(URL(string: url)!), url)
        }
        XCTAssertTrue(try sessions([["url": roxieDelivery, "behaviorHints": ["proxyHeaders": ["request": ["Cookie": "private"]]]]]).isEmpty)
    }
    @MainActor func testRoxieResolvesThroughSameIDMetadataAndExistingSessionBinding() async throws {
        let (request, snapshot) = roxieContext(); let row = roxieRow()
        let session = try fixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [["id": row.id, "type": "tv", "name": row.name,
            "description": row.description!, "genres": ["Football"]]]]), for: footballCatalogPath)
        PlavioFixtureProtocol.setResponse(try .json(["meta": ["id": row.id, "type": "tv", "name": row.name,
            "description": "Starts October 31, 2026 8:00 AM (site time)", "genres": ["Football"]]]), for: "/meta/tv/" + row.id + ".json")
        PlavioFixtureProtocol.setResponse(try .json(["streams": [["url": roxieDelivery, "behaviorHints": ["notWebReady": false]]]]),
            for: "/stream/tv/" + row.id + ".json")
        let client = PlavioSportsAddonClient(session: session, officialSnapshot: { _ in snapshot })
        let batch = try await client.catalogMatches(for: [request], now: roxieNow)
        XCTAssertEqual(batch.first?.outcome, .listed)
        let resolved = try await client.resolve(for: request, now: roxieNow, forceRefresh: true)
        XCTAssertEqual(resolved.map(\.providerName), ["AS1"])
        XCTAssertTrue(resolved.first?.requiresGuardedRelay == true)
        XCTAssertEqual(resolved.first?.eventBinding?.providerEventID, row.id)
        XCTAssertEqual(resolved.first?.diagnosticMetadata["match_method"], "official_fixture_pair_civil_date")
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }.count, 1)
    }

    func testPlavioLiveMigrationAcceptsObservedTVOnlyManifestAndRejectsRetiredIdentity() throws {
        var manifest = footballManifestJSON()
        manifest["id"] = "community.plaviohd.private"
        manifest["version"] = "2.1.5"
        manifest["types"] = ["tv"]
        manifest["resources"] = ["stream", "meta", "catalog"].map {
            ["name": $0, "types": ["tv"], "idPrefixes": ["plaviohdtv-"]] as [String: Any]
        }
        manifest["behaviorHints"] = ["configurable": true]
        XCTAssertEqual(try PlavioSportsAddonClient.validateManifest(data: data(manifest)).version, "2.1.5")
        manifest["id"] = "community.plaviohd"
        XCTAssertThrowsError(try PlavioSportsAddonClient.validateManifest(data: data(manifest)))
        XCTAssertFalse(PlavioSportsAddonClient.isSafeMetadataURL(URL(string: "https://hd.plavio.site/manifest.json")!))
        XCTAssertTrue(PlavioSportsAddonClient.isSafeMetadataURL(URL(string: "https://addon.plavio.site/catalog/tv/plaviohd-cricket.json")!))
    }

    func testObservedAdvancedManifestContractIsAdmittedWithoutConfigurationOrEPGAssumptions() throws {
        let manifest = try PlavioSportsAddonClient.validateManifest(data: data(manifestJSON()))
        XCTAssertEqual(manifest.id, "community.plaviohd.private")
        XCTAssertEqual(manifest.version, "1.9.56")
        XCTAssertEqual(manifest.resources.first { $0.name == "stream" }?.idPrefixes, ["tt", "plaviohdtv-"])
        XCTAssertEqual(PlavioSportsAddonClient.manifestURL.absoluteString, "https://addon.plavio.site/manifest.json")
        XCTAssertEqual(PlavioSportsAddonClient.catalogID, "plaviohd-live-sports")
    }

    func testDedicatedFootballManifestIsAcceptedWithoutMakingArbitraryCatalogsDiscoverable() throws {
        for includeLegacy in [true, false] {
            let contract = try PlavioSportsAddonClient.validateManifest(data: data(footballManifestJSON(includeLegacy: includeLegacy)))
            XCTAssertEqual(contract.version, "1.9.82")
            XCTAssertEqual(contract.catalogs.filter { $0.id == PlavioSportsAddonClient.footballCatalogID }.count, 1)
        }
        for catalogs: [[String: Any]] in [
            [["id": "plaviohd-soccer", "type": "tv"]],
            [["id": "plaviohd-football", "type": "movie"], ["id": "plaviohd-live-sports", "type": "tv"]],
            [["id": "plaviohd-football", "type": "tv"], ["id": "plaviohd-football", "type": "tv"],
             ["id": "plaviohd-live-sports", "type": "tv"]]
        ] {
            var contract = footballManifestJSON(); contract["catalogs"] = catalogs
            XCTAssertThrowsError(try PlavioSportsAddonClient.validateManifest(data: data(contract)))
        }
    }

    // Current production 1.9.82 advertises this catalog but returned no rows in
    // the reviewed window. The dated rows below are synthetic copies of the
    // existing accepted contract: they prove dispatch, never live availability.
    func testDedicatedFootballCatalogIsPreferredWithoutReadingGenericLiveChannels() async throws {
        let session = try fixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: footballCatalogPath)
        let result = try await PlavioSportsAddonClient(session: session).resolve(for: request(), now: kickoff, forceRefresh: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.diagnosticMetadata["addon_version"], "1.9.82")
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath, streamPath])
        XCTAssertEqual(result.first?.eventBinding?.providerEventID, fixtureID)
    }

    func testDedicatedFootballCatalogRetainsTheSameAdvertisedIDMetadataJoin() async throws {
        let session = try liveFixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [liveEntryJSON()]]), for: footballCatalogPath)
        let result = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest(), forceRefresh: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath, liveMetaPath, liveStreamPath])
        XCTAssertTrue(PlavioFixtureProtocol.hosts.allSatisfy { $0 == "addon.plavio.site" })
        XCTAssertEqual(result.first?.eventBinding?.streamID, liveFixtureID)
    }

    func testEmptyDedicatedFootballCatalogCannotBorrowGenericChannelAvailability() async throws {
        let session = try fixtureSession(manifest: .json(footballManifestJSON()), catalog: .json(["metas": [
            ["id": "plaviohdtv-generic-channel", "type": "tv", "name": "Sports channel", "genres": ["Sports"]]
        ]]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": []]), for: footballCatalogPath)
        do {
            _ = try await PlavioSportsAddonClient(session: session).resolve(for: request(), now: kickoff, forceRefresh: true)
            XCTFail("No exact fixture has been published")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath])
    }

    func testDedicatedFootballCatalogKeepsDuplicateIdentityConflictsFatal() async throws {
        let session = try fixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON(),
            ["id": fixtureID, "type": "tv", "name": "Different Club vs Another Club", "description": "LIVE", "genres": ["Sports"]]
        ]]), for: footballCatalogPath)
        do {
            _ = try await PlavioSportsAddonClient(session: session).resolve(for: request(), now: kickoff, forceRefresh: true)
            XCTFail("A legacy catalog cannot erase a dedicated catalog conflict")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath])
    }

    func testNewFootballCatalogDoesNotReuseTheStillFreshLegacyLiveCache() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, manifestTTL: 1)
        let now = kickoff.addingTimeInterval(-3600)
        _ = try await client.resolve(for: request(), now: now)
        PlavioFixtureProtocol.setResponse(try .json(footballManifestJSON()), for: "/manifest.json")
        PlavioFixtureProtocol.setResponse(try .json(["metas": []]), for: footballCatalogPath)
        do {
            _ = try await client.resolve(for: request(), now: now.addingTimeInterval(2))
            XCTFail("A different catalog ID has no inherited positive snapshot")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == footballCatalogPath }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/catalog/tv/plaviohd-live-sports.json" }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == streamPath }.count, 1)
    }

    func testLateLegacyCatalogCompletionCannotOverwriteTheDedicatedFootballCache() async throws {
        let old = PlavioFixtureGate("old legacy catalog")
        let session = try fixtureSession(catalog: .controlled(old))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, manifestTTL: 0)
        let now = kickoff.addingTimeInterval(-3600)
        let oldTask = Task { try await client.resolve(for: request(), now: now) }
        defer { oldTask.cancel(); old.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [old.started], timeout: 2)
        PlavioFixtureProtocol.setResponse(try .json(footballManifestJSON()), for: "/manifest.json")
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: footballCatalogPath)
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(1))
        old.respond(try .json(["metas": []]))
        do { _ = try await oldTask.value; XCTFail("Original lookup has no fixture") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        PlavioFixtureProtocol.setResponse(.status(503), for: footballCatalogPath)
        let cached = try await client.resolve(for: request(), now: now.addingTimeInterval(2))
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == footballCatalogPath }.count, 1)
    }

    func testManifestValidatesEveryAdvancedResourceAndExactStreamNamespace() throws {
        let badResources: [Any] = [
            [["name": "stream", "types": ["tv"], "idPrefixes": ["tt"]], resource("catalog", types: ["tv"])],
            [["name": "stream", "types": ["movie"], "idPrefixes": ["plaviohdtv-"]], resource("catalog", types: ["tv"])],
            [resource("stream"), ["name": "catalog", "types": ["tv"]]],
            [resource("stream"), ["name": "catalog", "types": ["tv"], "idPrefixes": ["https://unsafe.example/"]]],
            [resource("stream"), ["name": "catalog", "types": ["sport"], "idPrefixes": ["plaviohdtv-"]]],
            [resource("stream"), resource("catalog", types: ["tv"]), resource("unsupported")],
            [resource("stream"), resource("catalog", types: ["tv"]), resource("stream")],
            ["stream", "catalog"], [NSNull()]
        ]
        for resources in badResources {
            var manifest = manifestJSON(); manifest["resources"] = resources
            XCTAssertThrowsError(try PlavioSportsAddonClient.validateManifest(data: data(manifest)))
        }
        let mutations: [[String: Any]] = [["id": "community.lookalike"], ["version": "https://private.example/token"],
                                        ["types": ["sport"]], ["catalogs": []],
                                        ["behaviorHints": ["configurationRequired": true]]]
        for mutation in mutations {
            let manifest = manifestJSON().merging(mutation, uniquingKeysWith: { _, new in new })
            XCTAssertThrowsError(try PlavioSportsAddonClient.validateManifest(data: data(manifest)))
        }
    }

    func testOnlyExplicitTwoLineEnglishUTCDescriptionSuppliesKickoff() throws {
        let valid = entry()
        XCTAssertEqual(PlavioSportsAddonClient.explicitKickoff(for: valid), kickoff)
        for description in [nil, "LIVE", valid.name, "23 Oct 2026 · 21:30 UTC", valid.name + "\nLIVE",
                            valid.name + "\n23 Oct · 21:30 UTC", valid.name + "\n23 Oct 2026 · 21:30",
                            valid.name + "\n23 Oct 2026 · 21:30 GMT", valid.name + "\n23 Oct 2026 · 21:30 UTC\n",
                            valid.name + "\n31 Feb 2026 · 21:30 UTC", valid.name + "\n23 Oct 2026 · 24:30 UTC",
                            "Other teams\n23 Oct 2026 · 21:30 UTC", valid.name + "\r\n23 Oct 2026 · 21:30 UTC"] {
            let row = PlavioSportsCatalogEntry(id: fixtureID, name: valid.name, description: description)
            XCTAssertNil(PlavioSportsAddonClient.explicitKickoff(for: row), description ?? "missing")
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [row]), .missing)
        }
    }

    func testExactTeamsFootballNamespaceAndFifteenMinuteBoundAreRequired() {
        let row = entry()
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [row]), .matched(row))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(home: "Platense", away: "Gimnasia y Esgrima de Mendoza"), from: [row]), .matched(row))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(kickoff: kickoff.addingTimeInterval(900)), from: [row]), .matched(row))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(kickoff: kickoff.addingTimeInterval(901)), from: [row]), .missing)
        for candidate in [
            entry(id: "plaviohdtv-sfly-streamed:cricket-gimnasia-platense-20749"),
            entry(id: "plaviohdtv-flix-dlstreams:event:opaque"),
            entry(name: "Gimnasia y Esgrima de Mendoza vs Other Club"),
            entry(name: "Gimnasia y Esgrima de Mendoza Women vs Platense Women"),
            entry(name: "Gimnasia y Esgrima de Mendoza U19 vs Platense U19"),
            entry(name: "TBC vs Platense"), entry(type: "movie"), entry(genres: ["FOOTBALL"])
        ] {
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [candidate]), .missing)
        }
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(category: "cricket"), from: [row]), .missing)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(category: "basketball"), from: [row]), .missing)
    }

    func testConflictingDuplicateIDsAndMalformedIdentityRowsVetoMatching() throws {
        let row = entry()
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [row, row]), .matched(row))
        for conflicting in [entry(name: "Different Club vs Another Club"), entry(description: "LIVE"),
                            entry(type: "movie"), entry(hasMalformedIdentity: true)] {
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [row, conflicting]), .conflicting)
        }
        let malformed = try JSONDecoder().decode(PlavioSportsCatalogEntry.self,
            from: data(["id": fixtureID, "name": NSNull(), "description": "LIVE", "genres": ["Sports"]]))
        XCTAssertEqual(malformed.id, fixtureID)
        XCTAssertTrue(malformed.hasMalformedIdentity)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [row, malformed]), .conflicting)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request(), from: [row, entry(id: fixtureID + "-other")]), .conflicting)
    }

    func testLiveRowRequiresLiteralPublisherJoinAndNeverSuppliesItsOwnDate() throws {
        let row = liveEntry()
        let publisher = try publisherRows([publisherJSON().merging([
            "popular": true, "sources": ["admin": "ignored"], "unrelated": ["safe": "ignored"]
        ], uniquingKeysWith: { _, new in new })])
        XCTAssertNil(PlavioSportsAddonClient.explicitKickoff(for: row))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: liveRequest(), from: [row]), .missing)
        XCTAssertEqual(try PlavioSportsAddonClient.corroboratableLiveIDs(for: liveRequest(), from: [row]), [livePublisherID])
        XCTAssertEqual(try PlavioSportsAddonClient.corroboratableLiveIDs(for: liveRequest(), from: [row, row]), [livePublisherID])
        XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row], publisher: publisher), .matched(row))
        XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(home: "Manchester City", away: "Aston Villa"),
            from: [row], publisher: publisher), .matched(row))
        let wrongID = try publisherRows([publisherJSON().merging(["id": livePublisherID + "-other"],
            uniquingKeysWith: { _, new in new })])
        XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row], publisher: wrongID), .missing)
    }

    func testLiveCorroborationBoundsDistinctLiteralPublisherIDsBeforeFetching() throws {
        let second = liveEntry(id: liveFixtureID + "-second")
        let third = liveEntry(id: liveFixtureID + "-third")
        XCTAssertEqual(Set(try PlavioSportsAddonClient.corroboratableLiveIDs(for: liveRequest(), from: [liveEntry(), second])),
            Set([livePublisherID, livePublisherID + "-second"]))
        XCTAssertThrowsError(try PlavioSportsAddonClient.corroboratableLiveIDs(for: liveRequest(), from: [liveEntry(), second, third])) {
            XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
        }
    }

    func testLivePublisherDateRetainsInclusiveFifteenMinuteBoundary() throws {
        let row = liveEntry()
        for offset in [-900, 0, 900] {
            let publisher = try publisherRows([publisherJSON().merging([
                "date": 1_792_841_400_000 + Int64(offset) * 1_000
            ], uniquingKeysWith: { _, new in new })])
            XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row], publisher: publisher), .matched(row))
        }
        for offset in [-901, 901] {
            let publisher = try publisherRows([publisherJSON().merging([
                "date": 1_792_841_400_000 + Int64(offset) * 1_000
            ], uniquingKeysWith: { _, new in new })])
            XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row], publisher: publisher), .missing)
        }
    }

    func testLivePublisherRejectsMissingMalformedDateCategoryAndConflictingParticipantEvidence() throws {
        let row = liveEntry()
        var missingDate = publisherJSON(); missingDate.removeValue(forKey: "date")
        let badRows: [[String: Any]] = [
            missingDate,
            publisherJSON().merging(["date": NSNull()], uniquingKeysWith: { _, new in new }),
            publisherJSON().merging(["date": "1792841400000"], uniquingKeysWith: { _, new in new }),
            publisherJSON().merging(["category": "cricket"], uniquingKeysWith: { _, new in new }),
            publisherJSON().merging(["title": "Aston Villa vs Other Club"], uniquingKeysWith: { _, new in new }),
            publisherJSON().merging(["teams": ["home": ["name": "Aston Villa"], "away": ["name": "Other Club"]]],
                uniquingKeysWith: { _, new in new }),
            publisherJSON().merging(["teams": ["home": ["name": "Aston Villa Women"], "away": ["name": "Manchester City Women"]]],
                uniquingKeysWith: { _, new in new }),
            publisherJSON().merging(["title": "Aston Villa U19 vs Manchester City U19",
                "teams": ["home": ["name": "Aston Villa U19"], "away": ["name": "Manchester City U19"]]],
                uniquingKeysWith: { _, new in new })
        ]
        for bad in badRows {
            XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row],
                publisher: try publisherRows([bad])), .missing)
        }
        XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(category: "cricket"),
            from: [row], publisher: try publisherRows([publisherJSON()])), .missing)
    }

    func testLiveCatalogShapePrefixAndSquadEvidenceCannotBeInferredFromPublisher() throws {
        let row = liveEntry()
        let publisher = try publisherRows([publisherJSON()])
        let badRows = [
            liveEntry(id: "plaviohdtv-other:" + livePublisherID),
            liveEntry(name: "Aston Villa Women vs Manchester City Women"),
            liveEntry(name: "Aston Villa U19 vs Manchester City U19"),
            liveEntry(description: row.name + "\nLIVE"),
            liveEntry(description: row.name + "\nLIVE NOW\nPopular match\nSources: Admin, Golf, Hotel\n"),
            liveEntry(description: "Other Club vs Manchester City\nLIVE NOW\nPopular match\nSources: Admin, Golf, Hotel"),
            PlavioSportsCatalogEntry(id: liveFixtureID, type: "movie", name: row.name,
                description: row.description, genres: ["Sports"]),
            PlavioSportsCatalogEntry(id: liveFixtureID, name: row.name,
                description: row.description, genres: ["FOOTBALL"])
        ]
        for bad in badRows {
            XCTAssertEqual(try PlavioSportsAddonClient.corroboratableLiveIDs(for: liveRequest(), from: [bad]), [])
            XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [bad], publisher: publisher), .missing)
        }
    }

    func testLiveMalformedASDuplicateVetoesBeforeCorroborationInEitherOrder() throws {
        let row = liveEntry()
        let malformed = try JSONDecoder().decode(PlavioSportsCatalogEntry.self, from: data([
            "id": liveFixtureID, "type": "tv", "name": NSNull(), "description": "LIVE NOW", "genres": ["Sports"]
        ]))
        let publisher = try publisherRows([publisherJSON()])
        for sibling in [malformed, liveEntry(name: "Different Club vs Another Club"),
                        liveEntry(description: row.name + "\nLIVE")] {
            for rows in [[row, sibling], [sibling, row]] {
                XCTAssertThrowsError(try PlavioSportsAddonClient.corroboratableLiveIDs(for: liveRequest(), from: rows)) {
                    XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
                }
                XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: rows, publisher: publisher), .conflicting)
            }
        }
    }

    func testLivePublisherDuplicateConflictVetoesInBothOrdersWithoutErasingMalformedSibling() throws {
        let row = liveEntry()
        let valid = publisherJSON()
        var noDate = valid; noDate.removeValue(forKey: "date")
        let badRows: [[String: Any]] = [
            noDate,
            valid.merging(["date": 1_792_842_301_000], uniquingKeysWith: { _, new in new }),
            valid.merging(["category": "cricket"], uniquingKeysWith: { _, new in new }),
            valid.merging(["title": "Different Club vs Another Club"], uniquingKeysWith: { _, new in new }),
            valid.merging(["teams": NSNull()], uniquingKeysWith: { _, new in new })
        ]
        XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row],
            publisher: try publisherRows([valid, valid])), .matched(row))
        for bad in badRows {
            for duplicates in [[valid, bad], [bad, valid]] {
                XCTAssertEqual(PlavioSportsAddonClient.selectLiveMatch(for: liveRequest(), from: [row],
                    publisher: try publisherRows(duplicates)), .conflicting)
            }
        }
    }

    func testReviewedHLSKeepsSignedQueryOpaqueIdentityAndOrdinaryGuardedRelay() throws {
        let sessions = try sessions([["url": delivery, "behaviorHints": ["notWebReady": false]]])
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.playableURL.absoluteString, delivery)
        XCTAssertEqual(session.streamType, .hls)
        XCTAssertEqual(session.providerName, "AS1")
        XCTAssertEqual(session.diagnosticMetadata["source_family"], "plaviosports")
        XCTAssertEqual(session.diagnosticMetadata["manifest_result"], "exact_fixture_match")
        XCTAssertEqual(session.diagnosticMetadata["addon_version"], "1.9.56")
        XCTAssertEqual(session.diagnosticMetadata["source_key"]?.count, 27)
        XCTAssertTrue(session.diagnosticMetadata["source_key"]?.hasPrefix("ps_") == true)
        XCTAssertTrue(session.requiresLocalProxy)
        XCTAssertTrue(session.legacySource.requiresLocalProxy)
        XCTAssertTrue(session.requiredHeaders.isEmpty)
        XCTAssertTrue(session.legacySource.headers.isEmpty)
        XCTAssertNil(session.nativeOriginProfile)
        XCTAssertNil(session.nativePlaylistProfile)
        XCTAssertFalse(session.diagnosticMetadata.description.contains("papacito"))
        XCTAssertFalse(session.diagnosticMetadata.description.contains("signature"))
        XCTAssertFalse(session.diagnosticMetadata.description.contains("https://"))
        let badVersion = PlavioSportsAddonClient.makeSessions(from: try decodeStreams([["url": delivery]]),
            request: request(), addOnVersion: "https://private.example/token")
        XCTAssertEqual(badVersion.first?.diagnosticMetadata["addon_version"], "unknown")
    }

    func testInitialDeliveryRejectsUnsafeOriginsPortsPathsAndUnreviewedQueryContracts() throws {
        for url in [
            "http://papacito.cfd/live/fixture/index.m3u8?ft=value",
            "https://papacito.cfd:8443/live/fixture/index.m3u8?ft=value",
            "https://papacito.cfd.evil.example/live/fixture/index.m3u8?ft=value",
            "https://cdn.papacito.cfd/live/fixture/index.m3u8?ft=value",
            "https://papacito.cfd./live/fixture/index.m3u8?ft=value",
            "https://127.0.0.1/live/fixture/index.m3u8?ft=value",
            "https://user@papacito.cfd/live/fixture/index.m3u8?ft=value",
            "https://user:secret@papacito.cfd/live/fixture/index.m3u8?ft=value",
            "https://papacito.cfd/live/fixture/index.mp4?ft=value",
            "https://papacito.cfd/live/index.m3u8?ft=value",
            "https://papacito.cfd/live/fixture/extra/index.m3u8?ft=value",
            "https://papacito.cfd/live//index.m3u8?ft=value",
            "https://papacito.cfd/live/fixture%2Fextra/index.m3u8?ft=value",
            "https://papacito.cfd/live/fixture%5Cextra/index.m3u8?ft=value",
            "https://papacito.cfd/live/../index.m3u8?ft=value",
            "https://papacito.cfd/live/fixture/index.m3u8",
            "https://papacito.cfd/live/fixture/index.m3u8?ft=",
            "https://papacito.cfd/live/fixture/index.m3u8?FT=value",
            "https://papacito.cfd/live/fixture/index.m3u8?ft=value&ft=second",
            "https://papacito.cfd/live/fixture/index.m3u8?ft=value&token=other",
            "https://papacito.cfd/live/fixture/index.m3u8?ft=value#player"
        ] {
            XCTAssertTrue(try sessions([["url": url]]).isEmpty, url)
        }
        XCTAssertEqual(try sessions([["url": delivery.replacingOccurrences(of: "papacito.cfd/", with: "papacito.cfd:443/")]]).count, 1)
    }

    func testPlaceholderExternalP2PDRMAndMalformedHeaderContractsCannotBecomeOptions() throws {
        let rejected: [[String: Any]] = [
            ["url": "https://www.google.com"], ["url": "https://sports.highfly.to/health"],
            ["url": "magnet:?xt=urn:btih:fixture"], ["url": delivery, "externalUrl": "https://example.com"],
            ["url": delivery, "infoHash": "fixture"], ["url": delivery, "drm": ["license": "fixture"]],
            ["url": delivery, "behaviorHints": ["notWebReady": "false"]],
            ["url": delivery, "behaviorHints": ["notWebReady": NSNull()]],
            ["url": delivery, "behaviorHints": NSNull()],
            ["url": delivery, "behaviorHints": ["proxyHeaders": ["request": NSNull()]]],
            ["url": delivery, "behaviorHints": ["proxyHeaders": ["request": ["Authorization": "private"]]]],
            ["url": delivery, "behaviorHints": ["proxyHeaders": ["request": ["User-Agent": "unreviewed"]]]],
            ["url": delivery, "behaviorHints": ["proxyHeaders": ["response": ["Access-Control-Allow-Origin": "*"]]]],
            ["url": delivery, "behaviorHints": ["proxyHeaders": ["request": ["Cookie": 7]]]]
        ]
        for row in rejected { XCTAssertTrue(try sessions([row]).isEmpty) }
        XCTAssertEqual(try sessions([["url": delivery, "behaviorHints": ["proxyHeaders": ["request": [:], "response": [:]]]]]).count, 1)
    }

    func testDeduplicationCapsSixRealDeliveriesAndKeysSurviveReordering() throws {
        let variants = (0..<8).map { ["url": delivery + String($0)] }
        let first = try sessions([variants[0], ["url": "https://www.google.com"], variants[0]] + variants)
        XCTAssertEqual(first.map(\.providerName), ["AS1", "AS2", "AS3", "AS4", "AS5", "AS6"])
        XCTAssertEqual(first.count, 6)
        XCTAssertEqual(Set(first.compactMap { $0.diagnosticMetadata["source_key"] }).count, 6)
        let reordered = try sessions(Array(variants.prefix(6).reversed()))
        XCTAssertEqual(first.compactMap { $0.diagnosticMetadata["source_key"] },
                       Array(reordered.compactMap { $0.diagnosticMetadata["source_key"] }.reversed()))
    }

    func testMetadataOriginAndEphemeralConfigurationRemainBoundedAndCredentialFree() {
        XCTAssertTrue(PlavioSportsAddonClient.isSafeMetadataURL(PlavioSportsAddonClient.manifestURL))
        for raw in ["http://addon.plavio.site/manifest.json", "https://addon.plavio.site:8443/manifest.json",
                    "https://addon.plavio.site.evil.example/manifest.json", "https://user:secret@addon.plavio.site/manifest.json",
                    "https://addon.plavio.site/manifest.json?account=private", "https://addon.plavio.site/manifest.json#other"] {
            XCTAssertFalse(PlavioSportsAddonClient.isSafeMetadataURL(URL(string: raw)!))
        }
        let config = PlavioSportsAddonClient.makeConfiguration()
        XCTAssertEqual(config.timeoutIntervalForRequest, 7)
        XCTAssertEqual(config.timeoutIntervalForResource, 12)
        XCTAssertFalse(config.waitsForConnectivity)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
    }

    func testResolutionUsesExactManifestCatalogAndStreamRoutesWithStageTimeouts() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let result = try await client.resolve(for: request())
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", "/catalog/tv/plaviohd-live-sports.json", streamPath])
        XCTAssertEqual(PlavioFixtureProtocol.timeouts, [7, 7, 11])
        XCTAssertTrue(PlavioFixtureProtocol.hosts.allSatisfy { $0 == "addon.plavio.site" })
        XCTAssertEqual(PlavioFixtureProtocol.userAgents, Array(repeating: "Fotty/2.0 Stremio-Compatible", count: 3))
    }

    func testLiveResolutionUsesOneAdvertisedSameIDMetaWithoutClosedPublisher() async throws {
        let session = try liveFixtureSession(catalog: .json(["metas": [liveEntryJSON(), liveEntryJSON()]]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let result = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest())
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.providerName, "AS1")
        XCTAssertEqual(result.first?.diagnosticMetadata["source_family"], "plaviosports")
        XCTAssertTrue(result.first?.requiredHeaders.isEmpty == true)
        XCTAssertTrue(result.first?.requiresLocalProxy == true)
        XCTAssertNil(result.first?.nativeOriginProfile)
        XCTAssertNil(result.first?.nativePlaylistProfile)
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", "/catalog/tv/plaviohd-live-sports.json",
            liveMetaPath, liveStreamPath])
        XCTAssertEqual(PlavioFixtureProtocol.timeouts, [7, 7, 7, 11])
        XCTAssertTrue(PlavioFixtureProtocol.hosts.allSatisfy { $0 == "addon.plavio.site" })
        let metadata = try XCTUnwrap(PlavioFixtureProtocol.requests.first { $0.url?.path == liveMetaPath })
        XCTAssertEqual(metadata.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(metadata.value(forHTTPHeaderField: "User-Agent"), "Fotty/2.0 Stremio-Compatible")
        for header in ["Authorization", "Cookie", "Origin", "Referer"] {
            XCTAssertNil(metadata.value(forHTTPHeaderField: header))
        }
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains("/api/matches/all"))
    }

    func testLiveMetadataWrongIdentityDateOrAdditionalAuthorityCannotRequestStreams() async throws {
        let mutations: [[String: Any]] = [
            ["id": liveFixtureID + "-other"], ["type": "movie"],
            ["name": "Other Club vs Manchester City", "description": "Other Club vs Manchester City\n24 Oct 2026 · 11:30 UTC"],
            ["name": "Aston Villa Women vs Manchester City Women", "description": "Aston Villa Women vs Manchester City Women\n24 Oct 2026 · 11:30 UTC"],
            ["name": "Aston Villa U19 vs Manchester City U19", "description": "Aston Villa U19 vs Manchester City U19\n24 Oct 2026 · 11:30 UTC"],
            ["description": "Aston Villa vs Manchester City\n24 Oct 2026 · 11:31 UTC"],
            ["description": "Aston Villa vs Manchester City\n25 Oct 2026 · 11:30 UTC"],
            ["description": "Aston Villa vs Manchester City\nLIVE NOW"],
            ["description": "Aston Villa vs Manchester City\n24 Oct 2026 · 11:30 GMT"],
            ["genres": ["Cricket"]], ["released": "2026-10-25T11:30:00Z"],
            ["releaseInfo": "2026-10-25"], ["date": 1_792_841_400_000],
            ["startTime": "2026-10-24T11:30:00Z"], ["kickoff": "2026-10-24T11:30:00Z"],
            ["videos": []], ["behaviorHints": ["defaultVideoId": "other"]]
        ]
        for mutation in mutations {
            let meta = liveMetaJSON().merging(mutation, uniquingKeysWith: { _, new in new })
            let session = try liveFixtureSession(metadata: .json(["meta": meta]))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest()); XCTFail("Uncorroborated LIVE row") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch, String(describing: mutation.keys)) }
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveStreamPath))
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains("/api/matches/all"))
        }
    }

    func testConflictingLiveCatalogSiblingsCannotBeRepairedByMetadata() async throws {
        let first = liveEntryJSON()
        let siblings: [[String: Any]] = [["id": liveFixtureID, "name": 7],
            first.merging(["name": "Different Club vs Another Club"], uniquingKeysWith: { _, new in new }),
            first.merging(["description": "Aston Villa vs Manchester City\nLIVE"], uniquingKeysWith: { _, new in new }),
            first.merging(["id": liveFixtureID + "-other"], uniquingKeysWith: { _, new in new })]
        for sibling in siblings {
            for rows in [[first, sibling], [sibling, first]] {
                let session = try liveFixtureSession(catalog: .json(["metas": rows]))
                defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
                do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest()); XCTFail("Conflicting catalog") }
                catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
                XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveMetaPath))
                XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveStreamPath))
            }
        }
    }

    func testLiveMetadataCancellationCannotContinueToStreamRequest() async throws {
        let metadata = PlavioFixtureGate("metadata request")
        let session = try liveFixtureSession(metadata: .controlled(metadata))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let task = Task { try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest()) }
        defer { task.cancel(); metadata.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [metadata.started], timeout: 2)
        task.cancel()
        metadata.respond(try .json(["meta": liveMetaJSON()]))
        do { _ = try await task.value; XCTFail("Cancelled lookup must not yield a source") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveStreamPath))
    }

    func testLiveMetadataOversizeAndMalformedRootCannotReachStreamRequest() async throws {
        let cases: [(PlavioFixtureProtocol.Response, CommunitySportsAddonError)] = [
            (.body(Data(repeating: 32, count: 512 * 1024 + 1)), .invalidResponse),
            (try .json(["matches": []]), .invalidJSON(stage: .metadata)),
            (try .json(["meta": ["id": liveFixtureID, "name": "Aston Villa vs Manchester City"]]), .invalidJSON(stage: .metadata)),
            (.status(503), .httpFailure(statusCode: 503, stage: .metadata))
        ]
        for (response, expected) in cases {
            let session = try liveFixtureSession(metadata: response)
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest()); XCTFail("Invalid metadata response") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, expected) }
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveStreamPath))
        }
    }

    func testLiveMetadataCorroborationIsNotBorrowedFromPreviousResolution() async throws {
        let session = try liveFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = Date(timeIntervalSince1970: 1_792_841_400)
        _ = try await client.resolve(for: liveRequest(), now: now)
        PlavioFixtureProtocol.setResponse(.status(503), for: liveMetaPath)
        do { _ = try await client.resolve(for: liveRequest(), now: now.addingTimeInterval(1)); XCTFail("Fresh advertised metadata required") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .metadata)) }
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == liveMetaPath }.count, 2)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == liveStreamPath }.count, 1)
    }

    @MainActor
    func testObservedTwoLineLiveCupRowUsesSameAdvertisedMetaUTCAndExistingDelivery() async throws {
        let id = "plaviohdtv-sfly-streamed:football-liverpool-chelsea-reviewed"
        let name = "Liverpool vs Chelsea"
        let start = ISO8601DateFormatter().date(from: "2026-10-28T20:00:00Z")!
        let fixture = SportsFixtureMetadata(fixtureID: "sports-fixture:carabao-cup:reviewed",
            sport: "football", competitionID: "carabao-cup", competitionName: "Carabao Cup", eventKind: .match,
            title: name, participants: [.init(id: "liverpool", name: "Liverpool"), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: start, verified: true)
        let event = EventReference(id: fixture.fixtureID, title: name, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Liverpool", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: fixture, competitionID: "carabao-cup")
        let metaPath = "/meta/tv/" + id + ".json", targetStream = "/stream/tv/" + id + ".json"
        PlavioFixtureProtocol.configure([
            "/manifest.json": try .json(manifestJSON(version: "1.9.82")),
            "/catalog/tv/plaviohd-live-sports.json": try .json(["metas": [
                ["id": id, "type": "tv", "name": name, "description": name + "\nLIVE NOW", "genres": ["Sports"]]]]),
            metaPath: try .json(["meta": ["id": id, "type": "tv", "name": name,
                "description": name + "\n28 Oct 2026 · 20:00 UTC"]]),
            targetStream: try .json(["streams": [["url": delivery]]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlavioFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let result = try await PlavioSportsAddonClient(session: session).resolve(for: StreamPlaybackRequest(event: event), now: start)
        XCTAssertEqual(result.map(\.providerName), ["AS1"])
        XCTAssertEqual(result.first?.matchID, event.id)
        XCTAssertEqual(result.first?.requiredHeaders, [:])
        XCTAssertTrue(result.first?.requiresGuardedRelay == true)
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", "/catalog/tv/plaviohd-live-sports.json", metaPath, targetStream])
        XCTAssertTrue(PlavioFixtureProtocol.hosts.allSatisfy { $0 == "addon.plavio.site" })
    }

    func testLiveMetadataRequiresAdvertisedTVNamespaceAndRetainsHLSAdmission() async throws {
        for resource in [nil, self.resource("meta", types: ["movie"]),
                         ["name": "meta", "types": ["tv"], "idPrefixes": ["tt"]]] as [[String: Any]?] {
            var manifest = manifestJSON()
            var resources = (manifest["resources"] as! [[String: Any]]).filter { $0["name"] as? String != "meta" }
            if let resource { resources.append(resource) }
            manifest["resources"] = resources
            let session = try liveFixtureSession(manifest: .json(manifest))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest()); XCTFail("Unadvertised metadata") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidManifest) }
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveMetaPath))
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveStreamPath))
        }
        let session = try liveFixtureSession(streams: .json(["streams": [
            ["url": "http://papacito.cfd/live/fixture/index.m3u8?ft=fixture"],
            ["url": "https://other.example/live/fixture/index.m3u8?ft=fixture"],
            ["url": delivery, "behaviorHints": ["proxyHeaders": ["request": ["Cookie": "unreviewed"]]]]
        ]]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: liveRequest()); XCTFail("Unsafe deliveries") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 3)) }
    }

    func testUnsupportedSportUnqualifiedCricketAndMissingKickoffDoNotStartMetadataRequests() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let missingDate = StreamPlaybackRequest(matchID: "fixture", displayTitle: "Gimnasia y Esgrima de Mendoza vs Platense",
            homeTeam: "Gimnasia y Esgrima de Mendoza", awayTeam: "Platense", category: "football")
        for candidate in [request(category: "basketball"), request(category: "cricket"), missingDate] {
            do { _ = try await client.resolve(for: candidate); XCTFail("Unsupported lookup must fail closed") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertTrue(PlavioFixtureProtocol.paths.isEmpty)
    }

    func testBadManifestAndConflictingCatalogNeverRequestStreams() async throws {
        for invalidManifest in [true, false] {
            var manifest = manifestJSON()
            if invalidManifest { manifest["id"] = "community.other" }
            let rows = invalidManifest ? [entryJSON()] : [entryJSON(), ["id": fixtureID, "name": 7]]
            let session = try fixtureSession(manifest: .json(manifest), catalog: .json(["metas": rows]))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: request()); XCTFail("Unsafe lookup") }
            catch {
                XCTAssertEqual(error as? CommunitySportsAddonError, invalidManifest ? .invalidManifest : .conflictingMatch)
            }
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(streamPath))
        }
    }

    func testMalformedStreamSiblingsDoNotEraseValidChoiceAndAllRejectedRetainsAdmissionFailure() async throws {
        let rows: [Any] = [NSNull(), "bad-row", ["url": 7], ["url": delivery, "infoHash": "fixture"], ["url": delivery]]
        let session = try fixtureSession(streams: .json(["streams": rows]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let accepted = try await client.resolve(for: request())
        XCTAssertEqual(accepted.count, 1)
        PlavioFixtureProtocol.setResponse(try .json(["streams": Array(rows.prefix(4))]), for: streamPath)
        do { _ = try await client.resolve(for: request()); XCTFail("All entries are unsupported") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 4)) }
        PlavioFixtureProtocol.setResponse(try .json(["streams": []]), for: streamPath)
        do { _ = try await client.resolve(for: request()); XCTFail("Empty stream list") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamEntriesEmpty) }
    }

    func testStreamScanIsBoundedAtOneHundredRowsIncludingMalformedSiblings() async throws {
        let rows: [Any] = Array(repeating: NSNull(), count: 100) + [["url": delivery]]
        let session = try fixtureSession(streams: .json(["streams": rows]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: request()); XCTFail("Past scan boundary") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 100)) }
    }

    func testOversizeResponseAndMalformedStreamContainerAreBoundedFailures() async throws {
        for response in [PlavioFixtureProtocol.Response.body(Data(repeating: 32, count: 512 * 1024 + 1)),
                         try .json(["streams": "not-an-array"])] {
            let session = try fixtureSession(streams: response)
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: request()); XCTFail("Invalid response") }
            catch {
                let actual = error as? CommunitySportsAddonError
                XCTAssertTrue(actual == .invalidResponse || actual == .invalidJSON(stage: .streams))
            }
        }
    }

    func testResolutionAttachesOnlyTheExactAdvertisedEventBinding() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let request = request()
        let resolved = try await PlavioSportsAddonClient(session: session).resolve(for: request, now: kickoff, forceRefresh: true)
        let binding = try XCTUnwrap(resolved.first?.eventBinding)
        XCTAssertEqual(binding.providerEventID, fixtureID)
        XCTAssertEqual(binding.streamID, fixtureID)
        XCTAssertTrue(binding.matches(request: request, providerCode: PlavioSportsAddonClient.providerCode, at: kickoff))
        XCTAssertEqual(binding.expiresAt, kickoff.addingTimeInterval(StreamEventBinding.metadataLifetime))
        XCTAssertNil(resolved.first?.expiryTime)
        XCTAssertNil(try sessions([["url": delivery]]).first?.eventBinding,
            "Static conversion cannot manufacture a match association")
    }

    func testExplicitRefreshBypassesManifestAndNegativeCatalogWithoutWaitingForTTL() async throws {
        let session = try fixtureSession(catalog: .json(["metas": []]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = kickoff.addingTimeInterval(-3600)
        do { _ = try await client.resolve(for: request(), now: now); XCTFail("Not published") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        PlavioFixtureProtocol.setResponse(try .json(manifestJSON(version: "published")), for: "/manifest.json")
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: "/catalog/tv/plaviohd-live-sports.json")
        let count = PlavioFixtureProtocol.requests.count
        let result = try await client.resolve(for: request(), now: now.addingTimeInterval(1), forceRefresh: true)
        XCTAssertEqual(result.first?.diagnosticMetadata["addon_version"], "published")
        let freshRequests = Array(PlavioFixtureProtocol.requests.dropFirst(count))
        XCTAssertEqual(freshRequests.map { $0.url?.path ?? "" }, ["/manifest.json", "/catalog/tv/plaviohd-live-sports.json", streamPath])
        XCTAssertTrue(freshRequests.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache" })
    }

    func testCachedMissingMetaCapabilityRevalidatesOnceThenKeepsTheExactIDJoin() async throws {
        var oldManifest = manifestJSON()
        oldManifest["resources"] = [resource("stream"), resource("catalog", types: ["tv"])]
        let session = try liveFixtureSession(manifest: .json(oldManifest))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let request = liveRequest()
        let now = try XCTUnwrap(request.kickoffDate)
        do { _ = try await client.resolve(for: request, now: now); XCTFail("Metadata not advertised yet") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidManifest) }
        PlavioFixtureProtocol.setResponse(try .json(manifestJSON(version: "published")), for: "/manifest.json")
        let result = try await client.resolve(for: request, now: now.addingTimeInterval(1))
        XCTAssertEqual(result.first?.diagnosticMetadata["addon_version"], "published")
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == liveMetaPath }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == liveStreamPath }.count, 1)
    }

    @MainActor
    func testCachedFootballOnlyManifestCanDiscoverNewlyAdvertisedCricketCatalog() async throws {
        let session = try cricketFixtureSession(manifest: .json(manifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = cricketKickoff.addingTimeInterval(-60)
        _ = try await client.resolve(for: request(), now: now)
        PlavioFixtureProtocol.setResponse(try .json(cricketManifestJSON()), for: "/manifest.json")
        let result = try await client.resolve(for: officialCricketRequest(), now: now.addingTimeInterval(1))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == cricketCatalogPath }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == cricketStreamPath }.count, 1)
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(liveMetaPath))
    }

    func testExactEmptyDescriptorRevalidatesOnceAndSeesLatePublishedStream() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponses([
            try .json(["streams": []]), try .json(["streams": [["url": delivery]]])
        ], for: streamPath)
        let result = try await PlavioSportsAddonClient(session: session).resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.count, 1)
        let descriptors = PlavioFixtureProtocol.requests.filter { $0.url?.path == streamPath }
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertNil(descriptors.first?.value(forHTTPHeaderField: "Cache-Control"))
        XCTAssertEqual(descriptors.last?.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testStillEmptyDescriptorStopsAfterOneRevalidation() async throws {
        let session = try fixtureSession(streams: .json(["streams": []]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        do {
            _ = try await PlavioSportsAddonClient(session: session).resolve(for: request(), now: kickoff)
            XCTFail("Still pending")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamEntriesEmpty) }
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == streamPath }.count, 2)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
    }

    func testForcedCatalogKeepsUnrelatedMalformedRowLocal() async throws {
        let bad: [String: Any] = ["id": "plaviohdtv-unrelated", "type": "tv", "name": NSNull(), "description": "LIVE"]
        let session = try fixtureSession(catalog: .json(["metas": [bad, entryJSON()]]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let result = try await PlavioSportsAddonClient(session: session).resolve(for: request(), now: kickoff, forceRefresh: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == streamPath }.count, 1)
    }

    func testCancelledForcedCatalogCannotReplacePriorAcceptedCache() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        _ = try await client.resolve(for: request(), now: kickoff)
        let gate = PlavioFixtureGate("forced catalog cancelled")
        PlavioFixtureProtocol.setResponse(.controlled(gate), for: "/catalog/tv/plaviohd-live-sports.json")
        let task = Task { try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1), forceRefresh: true) }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        task.cancel(); gate.respond(try .json(["metas": []]))
        do { _ = try await task.value; XCTFail("Cancelled refresh") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        PlavioFixtureProtocol.setResponse(.status(503), for: "/catalog/tv/plaviohd-live-sports.json")
        let retained = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(2))
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/catalog/tv/plaviohd-live-sports.json" }.count, 2)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == streamPath }.count, 2)
    }

    func testPositiveCatalogTwoMinutesAndManifestThirtyMinutesCacheWithoutStreamCaching() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        _ = try await client.resolve(for: request(), now: now)
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(119))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == streamPath }.count, 2)
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(120))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count, 2)
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(1800))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
    }

    func testEmptyCatalogOnlyCachesFifteenSecondsAndFailedRefreshCannotReuseExpiredData() async throws {
        let session = try fixtureSession(catalog: .json(["metas": []]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        for age in [0.0, 14.0] {
            do { _ = try await client.resolve(for: request(), now: now.addingTimeInterval(age)); XCTFail("Empty") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count, 1)
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: "/catalog/tv/plaviohd-live-sports.json")
        let recovered = try await client.resolve(for: request(), now: now.addingTimeInterval(15))
        XCTAssertEqual(recovered.count, 1)
        PlavioFixtureProtocol.setResponse(.status(503), for: "/catalog/tv/plaviohd-live-sports.json")
        do { _ = try await client.resolve(for: request(), now: now.addingTimeInterval(135)); XCTFail("Expired") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .catalog)) }
    }

    func testOlderCatalogCompletionCannotOverwriteNewerAcceptedCache() async throws {
        let older = PlavioFixtureGate("old catalog")
        let session = try fixtureSession(catalog: .controlled(older))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let oldTask = Task { try await client.resolve(for: request(), now: now) }
        defer { oldTask.cancel(); older.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [older.started], timeout: 2)
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: "/catalog/tv/plaviohd-live-sports.json")
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(1))
        older.respond(try .json(["metas": []]))
        do { _ = try await oldTask.value; XCTFail("Original caller gets its own empty result") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        PlavioFixtureProtocol.setResponse(.status(503), for: "/catalog/tv/plaviohd-live-sports.json")
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(2))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count, 2)
    }

    func testOlderManifestCompletionCannotOverwriteNewerAcceptedVersion() async throws {
        let older = PlavioFixtureGate("old manifest")
        let session = try fixtureSession(manifest: .controlled(older))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let oldTask = Task { try await client.resolve(for: request(), now: now) }
        defer { oldTask.cancel(); older.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [older.started], timeout: 2)
        PlavioFixtureProtocol.setResponse(try .json(manifestJSON(version: "newer")), for: "/manifest.json")
        let newer = try await client.resolve(for: request(), now: now.addingTimeInterval(1))
        XCTAssertEqual(newer.first?.diagnosticMetadata["addon_version"], "newer")
        older.respond(try .json(manifestJSON(version: "older")))
        let oldResult = try await oldTask.value
        XCTAssertEqual(oldResult.first?.diagnosticMetadata["addon_version"], "older")
        PlavioFixtureProtocol.setResponse(.status(503), for: "/manifest.json")
        let retained = try await client.resolve(for: request(), now: now.addingTimeInterval(2))
        XCTAssertEqual(retained.first?.diagnosticMetadata["addon_version"], "newer")
    }

    func testObservedCricketCatalogAndCurrentManifestAreSeparatelyReviewed() throws {
        let manifest = try PlavioSportsAddonClient.validateManifest(data: data(cricketManifestJSON()))
        XCTAssertEqual(manifest.version, "1.9.57")
        XCTAssertEqual(manifest.catalogs.filter { $0.id == PlavioSportsAddonClient.cricketCatalogID }.count, 1)
        XCTAssertEqual(PlavioSportsAddonClient.cricketCatalogID, "plaviohd-cricket")
        XCTAssertTrue(PlavioSportsAddonClient.supports(category: "cricket"))
        XCTAssertFalse(PlavioSportsAddonClient.supports(category: "tennis"))
        // The existing older football manifest remains valid, but is not an
        // advertisement of cricket support (the resolver tests that gate).
        XCTAssertNoThrow(try PlavioSportsAddonClient.validateManifest(data: data(manifestJSON())))
    }

    func testObservedCricketNameAndPairDescriptionSupplyOnlyExplicitUTC() throws {
        let row = try JSONDecoder().decode(PlavioSportsCatalogEntry.self, from: data(cricketEntryJSON()))
        XCTAssertFalse(row.hasMalformedIdentity)
        XCTAssertEqual(row.name, "Bangladesh vs West Indies - 1st Test Day 1")
        XCTAssertEqual(PlavioSportsAddonClient.explicitKickoff(for: row), cricketKickoff)
        let padded = cricketEntry(date: "01 Nov 2026 · 04:00 UTC")
        XCTAssertEqual(PlavioSportsAddonClient.explicitKickoff(for: padded),
                       ISO8601DateFormatter().date(from: "2026-11-01T04:00:00Z"))
        let unpadded = cricketEntry(date: "1 Nov 2026 · 04:00 UTC")
        XCTAssertEqual(PlavioSportsAddonClient.explicitKickoff(for: unpadded),
                       PlavioSportsAddonClient.explicitKickoff(for: padded))
    }

    @MainActor
    func testInitialTestDayMatchesCanonicalVerifiedFixtureAtExactUTC() throws {
        let row = cricketEntry()
        let requested = officialCricketRequest()
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row]), .matched(row))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row, row]), .matched(row))
        // Cricket dates are not borrowed from nearby events within football's
        // fifteen-minute tolerance.
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(
            kickoff: cricketKickoff.addingTimeInterval(1)), from: [row]), .missing)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(
            kickoff: cricketKickoff.addingTimeInterval(86400)), from: [row]), .missing)
    }

    @MainActor
    func testCricketRequestFormatOrdinalAndSquadMustAgreeWithSource() throws {
        let row = cricketEntry()
        for requested in [
            officialCricketRequest(format: .t20), officialCricketRequest(format: .odi),
            officialCricketRequest(format: .unknown),
            officialCricketRequest(competition: "2nd Test, West Indies in Bangladesh"),
            officialCricketRequest(competition: "1st Test Day 2, West Indies in Bangladesh"),
            officialCricketRequest(competition: "1st Test Day 6, West Indies in Bangladesh"),
            officialCricketRequest(competition: "2st Test, West Indies in Bangladesh"),
            officialCricketRequest(competition: "1st ODI, West Indies in Bangladesh"),
            officialCricketRequest(home: "Bangladesh Women", away: "West Indies Women"),
            officialCricketRequest(home: "Bangladesh U19", away: "West Indies U19"),
            officialCricketRequest(verified: false), officialCricketRequest(conflicted: true)
        ] {
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row]), .missing)
        }
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(
            competition: "1st Test, West Indies in Bangladesh"), from: [row]), .matched(row))
    }

    func testExplicitCricketRequestSuffixRetainsOrdinalAndNeverInfersItFromOpaqueID() {
        let row = cricketEntry(id: "plaviohdtv-sfly-streamed:cricket-misleading-t5d5",
                               qualifier: "3rd T20I")
        let requested = explicitCricketRequest(qualifier: "3rd T20I")
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row]), .matched(row))
        for qualifier in ["1st T20I", "2nd T20I", "3rd Test", "3rd Test Day 1", "3rd ODI", "3st T20I"] {
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: explicitCricketRequest(qualifier: qualifier),
                                                             from: [row]), .missing)
        }
        let generic = request(home: "Bangladesh", away: "West Indies", category: "cricket", kickoff: cricketKickoff)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: generic, from: [row]), .missing)
    }

    @MainActor
    func testObservedNewZealandIndiaThirdT20IUsesExplicitDateAndOrdinal() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-27T07:00:00Z")!
        let row = cricketEntry(id: "plaviohdtv-sfly-streamed:cricket-nz-ind-t20i3",
            pair: "New Zealand vs India", qualifier: "3rd T20I", date: "27 Oct 2026 · 07:00 UTC")
        let requested = officialCricketRequest(home: "New Zealand", away: "India", format: .t20,
            competition: "New Zealand in India, 3rd T20I", kickoff: date)
        XCTAssertEqual(PlavioSportsAddonClient.explicitKickoff(for: row), date)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row]), .matched(row))
        let wrongOrdinal = cricketEntry(id: row.id, pair: "New Zealand vs India", qualifier: "2nd T20I",
            date: "27 Oct 2026 · 07:00 UTC")
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [wrongOrdinal]), .missing)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row, wrongOrdinal]), .conflicting)
        let nextDatedMatch = cricketEntry(id: "plaviohdtv-sfly-streamed:cricket-nz-ind-t20i4",
            pair: "New Zealand vs India", qualifier: "4th T20I", date: "30 Oct 2026 · 07:00 UTC")
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [nextDatedMatch]), .missing)
    }

    @MainActor
    func testLaterTestDaysAreHeldEvenWhenTheirDailyUTCIsExact() {
        for day in 2...5 {
            let row = cricketEntry(id: "plaviohdtv-sfly-streamed:cricket-ban-wi-t1d\(day)",
                                   qualifier: "1st Test Day \(day)")
            XCTAssertEqual(PlavioSportsAddonClient.explicitKickoff(for: row), cricketKickoff)
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(), from: [row]), .missing)
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: explicitCricketRequest(
                qualifier: "1st Test Day \(day)"), from: [row]), .missing)
        }
    }

    @MainActor
    func testCricketSameIDOrdinalDayAndMalformedSiblingsVetoBothOrderings() throws {
        let row = cricketEntry()
        let malformed = try JSONDecoder().decode(PlavioSportsCatalogEntry.self,
            from: data(["id": row.id, "type": "tv", "name": NSNull(), "genres": ["Cricket"]]))
        let siblings = [cricketEntry(qualifier: "2nd Test Day 1"), cricketEntry(qualifier: "1st Test Day 2"),
                        cricketEntry(qualifier: "1st T20I"), cricketEntry(qualifier: "1st Test Day 6"),
                        cricketEntry(qualifier: "1th Test Day 1"),
                        cricketEntry(date: "29 Oct 2026 · 04:00 UTC"),
                        cricketEntry(date: "28 Oct 2026 · 04:00 GMT"), malformed]
        for sibling in siblings {
            for rows in [[row, sibling], [sibling, row]] {
                XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(), from: rows), .conflicting)
            }
        }
        let otherID = cricketEntry(id: row.id + "-other")
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(),
                                                         from: [row, otherID]), .conflicting)
    }

    @MainActor
    func testCricketWomenAndYouthNamesAreNotErasedBySuffixParsing() {
        for squad in [" Women", " U19"] {
            let home = "Bangladesh" + squad, away = "West Indies" + squad
            let row = cricketEntry(pair: "\(home) vs \(away)")
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(home: home, away: away),
                                                             from: [row]), .matched(row))
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: officialCricketRequest(), from: [row]), .missing)
        }
        let contradictory = cricketEntry(name: "Bangladesh vs West Indies - 1st Test Day 1",
                                         pair: "Bangladesh Women vs West Indies Women")
        XCTAssertNil(PlavioSportsAddonClient.explicitKickoff(for: contradictory))
    }

    @MainActor
    func testCricketChannelsWrongNamespaceAndUnknownSuffixesRemainUnmatchable() {
        let requested = officialCricketRequest()
        for row in [
            cricketEntry(id: "plaviohdtv-sfly-leaf:now-sky3434", name: "(FHD) : SKY SPORTS CRICKET"),
            cricketEntry(id: fixtureID), cricketEntry(qualifier: "1st Test"),
            cricketEntry(qualifier: "1st Test Day 0"), cricketEntry(qualifier: "1st Test Day 6"),
            cricketEntry(qualifier: "1st ODI"), cricketEntry(qualifier: "1st T20I Highlights"),
            cricketEntry(qualifier: "1st Test Day 1 - Live"), cricketEntry(genres: ["Sports"])
        ] {
            XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: requested, from: [row]), .missing)
        }
    }

    func testCricketDateDescriptionCannotUseMissingYearLocalZoneImpossibleDateOrHiddenControls() {
        for date in ["LIVE NOW", "28 Oct · 04:00 UTC", "28 Oct 2026 · 04:00", "28 Oct 2026 · 04:00 GMT",
                     "31 Feb 2026 · 04:00 UTC", "28 Oct 2026 · 24:00 UTC", "028 Oct 2026 · 04:00 UTC",
                     "28 Oct 2026 · 04:00 UTC\r", "28 Oct 2026 · 04:00 UTC\n"] {
            XCTAssertNil(PlavioSportsAddonClient.explicitKickoff(for: cricketEntry(date: date)), date)
        }
        XCTAssertNil(PlavioSportsAddonClient.explicitKickoff(for: cricketEntry(pair: "Bangladesh\r vs West Indies")))
    }

    @MainActor
    func testCurrentCricketEnvelopeUsesOnlyAdvertisedCatalogAndUnchangedHLSAdmission() async throws {
        let session = try cricketFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let sources = try await PlavioSportsAddonClient(session: session).resolve(for: officialCricketRequest())
        XCTAssertEqual(sources.map(\.providerName), ["AS1"])
        XCTAssertEqual(sources.first?.diagnosticMetadata["addon_version"], "1.9.57")
        XCTAssertEqual(PlavioFixtureProtocol.paths,
                       ["/manifest.json", cricketCatalogPath, cricketStreamPath])
        XCTAssertTrue(sources.first?.requiresGuardedRelay == true)
        XCTAssertEqual(sources.first?.requiredHeaders, [:])
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains("/api/matches/all"))
        PlavioFixtureProtocol.setResponse(try .json(["streams": [["url": "https://addon.plavio.site/upcoming.html"]]]),
                                         for: cricketStreamPath)
        do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: officialCricketRequest()); XCTFail("Placeholder is not HLS") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 1)) }
    }

    @MainActor
    func testUnadvertisedOrDuplicateCricketCatalogCannotBorrowFootballManifestScope() async throws {
        for advertised in [0, 2] {
            var manifest = cricketManifestJSON()
            manifest["catalogs"] = [["id": PlavioSportsAddonClient.catalogID, "type": "tv"]]
                + Array(repeating: ["id": PlavioSportsAddonClient.cricketCatalogID, "type": "tv"], count: advertised)
            let session = try cricketFixtureSession(manifest: .json(manifest))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            do { _ = try await PlavioSportsAddonClient(session: session).resolve(for: officialCricketRequest()); XCTFail("Cricket was not uniquely advertised") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidManifest) }
            XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json"])
        }
    }

    @MainActor
    func testCricketAndFootballPositiveCatalogCachesCannotLeakAcrossSports() async throws {
        let session = try cricketFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = cricketKickoff
        let cricket = try await client.resolve(for: officialCricketRequest(), now: now)
        let football = try await client.resolve(for: request(), now: now.addingTimeInterval(1))
        XCTAssertEqual(cricket.count, 1); XCTAssertEqual(football.count, 1)
        PlavioFixtureProtocol.setResponse(.status(503), for: cricketCatalogPath)
        PlavioFixtureProtocol.setResponse(.status(503), for: "/catalog/tv/plaviohd-live-sports.json")
        _ = try await client.resolve(for: officialCricketRequest(), now: now.addingTimeInterval(119))
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(119))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == cricketCatalogPath }.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/catalog/tv/plaviohd-live-sports.json" }.count, 1)
        do { _ = try await client.resolve(for: officialCricketRequest(), now: now.addingTimeInterval(120)); XCTFail("Expired cricket cache") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .catalog)) }
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(120))
    }

    @MainActor
    func testCricketNegativeCacheExpiresWithoutEvictingFootballPositiveCache() async throws {
        let session = try cricketFixtureSession(catalog: .json(["metas": []]))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = cricketKickoff
        _ = try await client.resolve(for: request(), now: now)
        for age in [0.0, 14.0] {
            do { _ = try await client.resolve(for: officialCricketRequest(), now: now.addingTimeInterval(age)); XCTFail("Empty cricket") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == cricketCatalogPath }.count, 1)
        PlavioFixtureProtocol.setResponse(try .json(currentCricketCatalogJSON()), for: cricketCatalogPath)
        _ = try await client.resolve(for: officialCricketRequest(), now: now.addingTimeInterval(15))
        PlavioFixtureProtocol.setResponse(.status(503), for: "/catalog/tv/plaviohd-live-sports.json")
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(15))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/catalog/tv/plaviohd-live-sports.json" }.count, 1)
    }

    @MainActor
    func testConcurrentFootballCatalogDoesNotInvalidateCricketCacheGeneration() async throws {
        let pending = PlavioFixtureGate("cricket catalog")
        let session = try cricketFixtureSession(catalog: .controlled(pending))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let now = cricketKickoff
        let cricketRequest = officialCricketRequest()
        let task = Task { try await client.resolve(for: cricketRequest, now: now) }
        defer { task.cancel(); pending.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [pending.started], timeout: 2)
        _ = try await client.resolve(for: request(), now: now.addingTimeInterval(1))
        pending.respond(try .json(currentCricketCatalogJSON()))
        _ = try await task.value
        PlavioFixtureProtocol.setResponse(.status(503), for: cricketCatalogPath)
        _ = try await client.resolve(for: cricketRequest, now: now.addingTimeInterval(2))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == cricketCatalogPath }.count, 1)
    }

    @MainActor
    func testCancelledOrDisabledCricketResolutionCannotRequestStreamsOrPublishCache() async throws {
        let pending = PlavioFixtureGate("cancelled cricket catalog")
        let session = try cricketFixtureSession(catalog: .controlled(pending))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session)
        let requested = officialCricketRequest()
        let now = cricketKickoff
        let task = Task { try await client.resolve(for: requested, now: now) }
        defer { task.cancel(); pending.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [pending.started], timeout: 2)
        task.cancel() // Parent source-disable cancels its in-flight resolver.
        pending.respond(try .json(currentCricketCatalogJSON()))
        do { _ = try await task.value; XCTFail("Cancelled source must not be offered") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(cricketStreamPath))
        PlavioFixtureProtocol.setResponse(try .json(currentCricketCatalogJSON()), for: cricketCatalogPath)
        _ = try await client.resolve(for: requested, now: now.addingTimeInterval(1))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == cricketCatalogPath }.count, 2)
    }

    func testDLHDOriginalDatedSectionRepairsOnlyTheObservedFootballEnvelope() throws {
        let originals = try dlhdOriginals(dlhdHTML() + dlhdHTML(header: "Tuesday 28th April 2026 - Schedule Time UK GMT",
            title: "England - League Cup : Other Club vs Another Club"))
        XCTAssertEqual(originals.first?.kickoff, dlhdKickoff)
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()], originals: originals),
                       .matched(dlhdEntry()))
        XCTAssertNil(PlavioSportsAddonClient.explicitKickoff(for: dlhdEntry()))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: dlhdRequest(), from: [dlhdEntry()]), .missing)
        for row in [dlhdEntry(id: "plaviohdtv-roxie-ev-fixture1"), dlhdEntry(genres: ["Sports"]),
                    dlhdEntry(name: "England - League Cup : Everton Women vs Newcastle United Women"),
                    dlhdEntry(name: "England - League Cup : Everton U19 vs Newcastle United U19"),
                    dlhdEntry(description: "Starts 19:45 (UK time)"), dlhdEntry(description: "LIVE NOW")] {
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [row], originals: originals), .missing)
        }
    }

    func testDLHDNeverBorrowsRequestDayYearTimezoneOrProducerEarlyMorningHeuristic() throws {
        for header in ["Thursday 29h Oct - Schedule Time UK GMTT", "Thursday 29h Oct 2026 - Schedule Time UK",
                       "Wednesday 29h Oct 2026 - Schedule Time UK GMTT", "Tuesday 31st Feb 2026 - Schedule Time UK GMT",
                       "Thursday 29h Oct 2026 - Schedule Time UK BST"] {
            let originals = try dlhdOriginals(dlhdHTML(header: header))
            XCTAssertNil(originals.first?.kickoff, header)
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()], originals: originals), .missing)
        }
        let early = try dlhdOriginals(dlhdHTML(clock: "03:45"))
        XCTAssertNil(early.first?.kickoff)
        let wrongDay = dlhdRequest(kickoff: dlhdKickoff.addingTimeInterval(24 * 3600))
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: wrongDay, from: [dlhdEntry()],
            originals: try dlhdOriginals(dlhdHTML())), .missing)
    }

    func testDLHDAmbiguousOriginalSectionsAndSameIDCatalogConflictsVetoBothOrders() throws {
        let original = dlhdHTML()
        for sibling in [original, dlhdHTML(header: "Tuesday 28th April 2026 - Schedule Time UK GMT"),
                        dlhdHTML(clock: "20:45"), dlhdHTML(header: "Date not published")] {
            for html in [original + sibling, sibling + original] {
                XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()],
                    originals: try dlhdOriginals(html)), .conflicting)
            }
        }
        let originals = try dlhdOriginals(original)
        for sibling in [dlhdEntry(name: "England - League Cup : Other Club vs Another Club"),
                        dlhdEntry(description: "Starts 20:45 (UK time) · 28 channels"),
                        dlhdEntry(hasCompetingDateAuthority: true), dlhdEntry(genres: ["Sports"])] {
            for rows in [[dlhdEntry(), sibling], [sibling, dlhdEntry()]] {
                XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: rows, originals: originals), .conflicting)
            }
        }
        for rows in [[dlhdEntry(), dlhdEntry(description: "Starts 19:45 (UK time) · 18 channels")],
                     [dlhdEntry(description: "Starts 19:45 (UK time) · 18 channels"), dlhdEntry()]] {
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: rows, originals: originals), .matched(rows[0]),
                           "A changed display count cannot create a second fixture identity")
        }
    }

    func testDLHDUKClockCannotSilentlyReinterpretOriginalGMTDuringBritishSummerTime() throws {
        let originals = try dlhdOriginals(dlhdHTML(header: "Thursday 29th Oct 2026 - Schedule Time UK GMT"))
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()], originals: originals), .matched(dlhdEntry()))
        let summer = try dlhdOriginals(dlhdHTML(header: "Wednesday 29th Jul 2026 - Schedule Time UK GMT"))
        let summerKickoff = ISO8601DateFormatter().date(from: "2026-07-29T19:45:00Z")!
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(kickoff: summerKickoff),
            from: [dlhdEntry()], originals: summer), .conflicting)
    }

    func testDLHDHiddenTemplateAndInactiveAncestorsCannotSupplyOrVetoScheduleFacts() throws {
        let stale = dlhdHTML(header: "Tuesday 28th April 2026 - Schedule Time UK GMT")
        for (open, close) in [("<template>", "</template>"), ("<div hidden>", "</div>"),
            ("<div inert>", "</div>"), ("<div aria-hidden='true'>", "</div>"),
            ("<div style='display:none'>", "</div>"), ("<noscript>", "</noscript>"), ("<textarea>", "</textarea>")] {
            let originals = try dlhdOriginals(open + stale + close + dlhdHTML())
            XCTAssertEqual(originals.count, 1, open)
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()], originals: originals),
                           .matched(dlhdEntry()), open)
        }
        for unterminated in ["<script>", "<style>", "<!--"] {
            let originals = try dlhdOriginals(dlhdHTML() + unterminated + stale)
            XCTAssertEqual(originals.count, 1, unterminated)
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()], originals: originals),
                           .matched(dlhdEntry()), unterminated)
            XCTAssertThrowsError(try dlhdOriginals(unterminated + dlhdHTML()), unterminated)
        }
    }

    func testDLHDClosedDayOrCategoryCannotDonateDateToUndatedSiblingEvent() throws {
        let category = """
        <div class="schedule__category"><span class="card__meta">All Soccer Events</span>
        <div class="schedule__event"><span class="schedule__time">19:45</span>
        <span class="schedule__eventTitle">England - League Cup : Everton vs Newcastle United</span></div></div>
        """
        let afterClosedDay = """
        <section class="schedule__day"><h2 class="schedule__dayTitle">Thursday 29h Oct 2026 - Schedule Time UK GMTT</h2></section>
        \(category)
        """
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()],
            originals: try dlhdOriginals(afterClosedDay)), .missing)
        let outsideCategory = """
        <section class="schedule__day"><h2 class="schedule__dayTitle">Thursday 29h Oct 2026 - Schedule Time UK GMTT</h2>
        <div class="schedule__category"><span class="card__meta">All Soccer Events</span></div>
        <div class="schedule__event"><span class="schedule__time">19:45</span>
        <span class="schedule__eventTitle">England - League Cup : Everton vs Newcastle United</span></div></section>
        """
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()],
            originals: try dlhdOriginals(outsideCategory)), .missing)
        let malformedVisibleDay = dlhdHTML().replacingOccurrences(of: "</section>", with: "")
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()],
            originals: try dlhdOriginals(malformedVisibleDay)), .missing)
    }

    func testDLHDMalformedVisibleSamePairStillVetoesAfterStructuralVisibilityFiltering() throws {
        let malformed = dlhdHTML(header: "Date not published")
        for html in [dlhdHTML() + malformed, malformed + dlhdHTML()] {
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(), from: [dlhdEntry()],
                originals: try dlhdOriginals(html)), .conflicting)
        }
    }

    @MainActor
    func testDLHDCompetitionConflictAndFifteenMinuteBoundRemainEnforced() throws {
        let originals = try dlhdOriginals(dlhdHTML())
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(kickoff: dlhdKickoff.addingTimeInterval(900)),
            from: [dlhdEntry()], originals: originals), .matched(dlhdEntry()))
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: dlhdRequest(kickoff: dlhdKickoff.addingTimeInterval(901)),
            from: [dlhdEntry()], originals: originals), .missing)
        let event = EventReference(id: "official-cup-fixture", title: "Everton vs Newcastle United", category: "football",
            date: Int64(dlhdKickoff.timeIntervalSince1970 * 1000), poster: nil, popular: false, teams: nil,
            competitionID: "premier-league")
        let wrongCompetition = StreamPlaybackRequest(matchID: event.id, displayTitle: event.title!, homeTeam: "Everton",
            awayTeam: "Newcastle United", category: "football", kickoffDate: dlhdKickoff, preferredEvent: event)
        XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: wrongCompetition, from: [dlhdEntry()], originals: originals), .conflicting)
    }

    func testDLHDUsesExactASMetaAndOneFixedMetadataOnlyOriginalRouteBeforeStreams() async throws {
        let session = try dlhdFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let sessions = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff, forceRefresh: true)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.eventBinding?.providerEventID, dlhdID)
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath, dlhdMetaPath, "/", dlhdStreamPath])
        XCTAssertEqual(PlavioFixtureProtocol.hosts, ["addon.plavio.site", "addon.plavio.site", "addon.plavio.site", "thedaddy.pk", "addon.plavio.site"])
        XCTAssertEqual(PlavioFixtureProtocol.requests.first { $0.url?.host == "thedaddy.pk" }?.value(forHTTPHeaderField: "Accept"), "text/html")
    }

    func testDLHDNewMetaDatesChangedIdentityAndDuplicateCatalogCannotReachOriginalOrStreams() async throws {
        for mutation: [String: Any] in [["description": "Starts 20:45 (UK time) · 28 channels"],
            ["name": "England - League Cup : Everton Women vs Newcastle United Women"], ["released": "2026-10-29T19:45:00Z"],
            ["id": dlhdID + "other"], ["genres": ["Sports"]]] {
            var meta = dlhdEntryJSON(); meta.merge(mutation, uniquingKeysWith: { _, new in new })
            let session = try dlhdFixtureSession(metadata: .json(["meta": meta]))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
            do { _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff); XCTFail("Changed meta is a veto") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains("/"))
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(dlhdStreamPath))
        }
    }

    func testDLHDMetadataMayOmitOnlyTheDisplayChannelCount() async throws {
        for description in ["Starts 19:45 (UK time)", "Starts 19:45 (UK time) · 18 channels"] {
            var meta = dlhdEntryJSON(); meta["description"] = description
            let session = try dlhdFixtureSession(metadata: .json(["meta": meta]))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
            let result = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff, forceRefresh: true)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.eventBinding?.providerEventID, dlhdID)
            XCTAssertTrue(PlavioFixtureProtocol.paths.contains("/"), "The original dated schedule is still required")
        }
        for description in ["Starts 20:45 (UK time)", "Starts 19:45 (UTC)", "LIVE NOW",
                            "Starts 19:45 (UK time) · 0 channels", "Starts 19:45 (UK time)\nOther match"] {
            var meta = dlhdEntryJSON(); meta["description"] = description
            let session = try dlhdFixtureSession(metadata: .json(["meta": meta]))
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
            do { _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff); XCTFail("Conflicting/malformed time must stay rejected") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(dlhdStreamPath))
        }
    }

    @MainActor
    func testDLHDReviewedOfficialLeagueIdentityDoesNotRejectAnOtherwiseExactFixture() throws {
        for (label, competition) in [("France - Ligue 1", "ligue-1"), ("Germany - Bundesliga", "bundesliga"),
                                      ("Italy - Serie A", "serie-a"), ("Spain - La Liga", "la-liga")] {
            let row = dlhdEntry(name: label + " : Everton vs Newcastle United")
            let originals = try dlhdOriginals(dlhdHTML(title: label + " : Everton vs Newcastle United"))
            let base = dlhdRequest()
            let event = EventReference(id: base.matchID, title: "Everton vs Newcastle United", category: "football",
                date: Int64(dlhdKickoff.timeIntervalSince1970 * 1000), poster: nil, popular: false, teams: nil,
                competitionID: competition)
            let request = StreamPlaybackRequest(matchID: event.id, displayTitle: event.title!, homeTeam: "Everton",
                awayTeam: "Newcastle United", category: "football", kickoffDate: dlhdKickoff, preferredEvent: event)
            XCTAssertEqual(PlavioSportsAddonClient.selectDLHDMatch(for: request, from: [row], originals: originals), .matched(row), label)
        }
    }

    func testDLHDOriginalPublicAddressAndExactOriginAreRequired() async throws {
        for value in ["http://thedaddy.pk/", "https://thedaddy.pk:8443/", "https://thedaddy.pk.evil.example/",
                      "https://thedaddy.pk/other", "https://thedaddy.pk/?x=1", "https://user@thedaddy.pk/",
                      "https://thedaddy.pk/#fragment", "https://thedaddy.pk/%2f"] {
            XCTAssertFalse(PlavioSportsAddonClient.isSafeDLHDOriginalURL(URL(string: value)!))
        }
        XCTAssertTrue(PlavioSportsAddonClient.isSafeDLHDOriginalURL(PlavioSportsAddonClient.dlhdOriginalScheduleURL))
        let session = try dlhdFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1", "127.0.0.1"] })
        do { _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff); XCTFail("Mixed/private DNS must be rejected") }
        catch { XCTAssertEqual((error as? URLError)?.code, .cannotFindHost) }
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains("/"))
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(dlhdStreamPath))
    }

    func testDLHDOriginalFiveMinuteCacheSurvivesASForceRefreshWithoutRepeatedPageReads() async throws {
        let session = try dlhdFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff, forceRefresh: true)
        PlavioFixtureProtocol.setResponse(.status(503), for: "/")
        _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff.addingTimeInterval(120), forceRefresh: true)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/" }.count, 1)
        do {
            _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff.addingTimeInterval(301), forceRefresh: true)
            XCTFail("An expired original snapshot cannot hide a failed read")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .catalog)) }
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == dlhdStreamPath }.count, 2)
    }

    func testDLHDCachedMissGetsAtMostOneTargetedOriginalRefresh() async throws {
        let session = try dlhdFixtureSession(original: .body(Data(dlhdHTML(title: "England - League Cup : Other Club vs Another Club").utf8)))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        do { _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff); XCTFail("No original match") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        PlavioFixtureProtocol.setResponse(.body(Data(dlhdHTML().utf8)), for: "/")
        let sessions = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff.addingTimeInterval(1))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/" }.count, 2)
    }

    @MainActor
    func testDLHDCancelledOriginalCannotCacheOrRequestStreams() async throws {
        let pending = PlavioFixtureGate("cancelled original schedule")
        let session = try dlhdFixtureSession(original: .controlled(pending))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let task = Task { try await client.resolve(for: dlhdRequest(), now: dlhdKickoff) }
        defer { task.cancel(); pending.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [pending.started], timeout: 2)
        task.cancel(); pending.respond(.body(Data(dlhdHTML().utf8)))
        do { _ = try await task.value; XCTFail("Cancelled original cannot publish") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(dlhdStreamPath))
        PlavioFixtureProtocol.setResponse(.body(Data(dlhdHTML().utf8)), for: "/")
        _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff.addingTimeInterval(1))
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/" }.count, 2)
    }

    @MainActor
    func testDLHDOlderOriginalCompletionCannotOverwriteNewerAcceptedSchedule() async throws {
        let pending = PlavioFixtureGate("older original schedule")
        let session = try dlhdFixtureSession(original: .controlled(pending))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let old = Task { try await client.resolve(for: dlhdRequest(), now: dlhdKickoff) }
        defer { old.cancel(); pending.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [pending.started], timeout: 2)
        PlavioFixtureProtocol.setResponse(.body(Data(dlhdHTML().utf8)), for: "/")
        _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff.addingTimeInterval(1), forceRefresh: true)
        pending.respond(.body(Data(dlhdHTML(title: "England - League Cup : Other Club vs Another Club").utf8)))
        do { _ = try await old.value; XCTFail("Old response has no exact event") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        PlavioFixtureProtocol.setResponse(.status(503), for: "/")
        _ = try await client.resolve(for: dlhdRequest(), now: dlhdKickoff.addingTimeInterval(2), forceRefresh: true)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == "/" }.count, 2)
    }

    func testBatchCatalogSharesOneSnapshotAndLeavesExactMetadataJoinsPending() async throws {
        let session = try dlhdFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON(), liveEntryJSON(), dlhdEntryJSON()]]), for: footballCatalogPath)
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let rows = try await client.catalogMatches(for: [request(), liveRequest(), dlhdRequest()], now: dlhdKickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .needsVerification, .needsVerification])
        XCTAssertEqual(rows.map(\.providerEventID), [fixtureID, liveFixtureID, dlhdID])
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath, "/"])
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
        _ = try await client.catalogMatches(for: [request(), liveRequest(), dlhdRequest()], now: dlhdKickoff.addingTimeInterval(1))
        XCTAssertEqual(PlavioFixtureProtocol.paths.count, 3)
    }

    func testBatchCatalogMapsSeveralDatedFootballFixturesWithoutPerFixtureFetches() async throws {
        var other = entryJSON(); other["id"] = fixtureID + "-other"; other["name"] = "Arsenal vs Liverpool"
        other["description"] = "Arsenal vs Liverpool\n23 Oct 2026 · 21:30 UTC"
        let session = try fixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON(), other]]), for: footballCatalogPath)
        let second = StreamPlaybackRequest(matchID: "second", displayTitle: "Arsenal vs Liverpool", homeTeam: "Arsenal",
            awayTeam: "Liverpool", category: "football", kickoffDate: kickoff)
        let rows = try await PlavioSportsAddonClient(session: session).catalogMatches(for: [request(), second], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed])
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath])
    }

    func testBatchCatalogPreservesMalformedSiblingDateSquadAndUnsupportedOutcomes() async throws {
        var bad = entryJSON(); bad["name"] = "Different Club vs Another Club"; bad["description"] = "LIVE"
        let session = try fixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON(), bad]]), for: footballCatalogPath)
        let client = PlavioSportsAddonClient(session: session)
        let rows = try await client.catalogMatches(for: [request(), request(kickoff: kickoff.addingTimeInterval(901)),
            request(home: "Gimnasia y Esgrima de Mendoza Women", away: "Platense Women"), request(category: "unsupported")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.conflicting, .notListed, .notListed, .unsupported])
        XCTAssertTrue(rows.allSatisfy { $0.providerEventID == nil })
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
    }

    @MainActor
    func testBatchCatalogReadsFootballAndReviewedCricketOnceEachWithoutStreamWork() async throws {
        let session = try cricketFixtureSession()
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let rows = try await PlavioSportsAddonClient(session: session).catalogMatches(
            for: [request(), officialCricketRequest(), request(category: "cricket")], now: cricketKickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed, .unsupported])
        XCTAssertEqual(PlavioFixtureProtocol.paths,
            ["/manifest.json", "/catalog/tv/plaviohd-live-sports.json", cricketCatalogPath])
    }

    func testBatchDLHDDateConflictCannotBecomeAnExactListingOrFetchMetadata() async throws {
        let session = try dlhdFixtureSession(original: .body(Data((dlhdHTML() +
            dlhdHTML(header: "Tuesday 28th April 2026 - Schedule Time UK GMT")).utf8)))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let rows = try await client.catalogMatches(for: [dlhdRequest()], now: dlhdKickoff)
        XCTAssertEqual(rows.first?.outcome, .conflicting)
        XCTAssertNil(rows.first?.providerEventID)
        XCTAssertEqual(PlavioFixtureProtocol.paths, ["/manifest.json", footballCatalogPath, "/"])
    }

    func testBatchOriginalReadFailureIsNotAnAbsentFixture() async throws {
        let session = try dlhdFixtureSession(original: .status(503))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let rows = try await client.catalogMatches(for: [dlhdRequest()], now: dlhdKickoff)
        XCTAssertEqual(rows.first?.outcome, .failed(.manifestUnreachable))
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
    }

    @MainActor
    func testBatchFailedCricketCatalogKeepsHealthyFootballAndViceVersa() async throws {
        for failedPath in [cricketCatalogPath, "/catalog/tv/plaviohd-live-sports.json"] {
            let session = try cricketFixtureSession()
            defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
            PlavioFixtureProtocol.setResponse(.status(503), for: failedPath)
            let rows = try await PlavioSportsAddonClient(session: session).catalogMatches(
                for: [request(), officialCricketRequest()], now: cricketKickoff)
            XCTAssertEqual(rows.map(\.outcome), failedPath == cricketCatalogPath
                ? [.listed, .failed(.manifestUnreachable)] : [.failed(.manifestUnreachable), .listed])
            XCTAssertFalse(PlavioFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
        }
    }

    func testBatchFailedDLHDOriginalDoesNotDiscardIndependentDatedFootballListing() async throws {
        let session = try dlhdFixtureSession(original: .status(503))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON(), dlhdEntryJSON()]]), for: footballCatalogPath)
        let client = PlavioSportsAddonClient(session: session, originalScheduleResolver: { _ in ["1.1.1.1"] })
        let rows = try await client.catalogMatches(for: [request(), dlhdRequest()], now: dlhdKickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .failed(.manifestUnreachable)])
        XCTAssertEqual(rows.first?.providerEventID, fixtureID)
        XCTAssertNil(rows.last?.providerEventID)
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
    }

    @MainActor
    func testCancelledBatchASCatalogDoesNotCacheOrPublishSourceEvidence() async throws {
        let pending = PlavioFixtureGate("cancelled batch AS catalog")
        let session = try fixtureSession(manifest: .json(footballManifestJSON()))
        defer { session.invalidateAndCancel(); PlavioFixtureProtocol.reset() }
        PlavioFixtureProtocol.setResponse(.controlled(pending), for: footballCatalogPath)
        let client = PlavioSportsAddonClient(session: session)
        let task = Task { try await client.catalogMatches(for: [request()], now: kickoff) }
        defer { task.cancel(); pending.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [pending.started], timeout: 2)
        task.cancel(); pending.respond(try .json(["metas": [entryJSON()]]))
        do { _ = try await task.value; XCTFail("Cancelled source batch") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertFalse(PlavioFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
        PlavioFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: footballCatalogPath)
        let rows = try await client.catalogMatches(for: [request()], now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(rows.first?.outcome, .listed)
        XCTAssertEqual(PlavioFixtureProtocol.paths.filter { $0 == footballCatalogPath }.count, 2)
    }

    /// Opt-in physical client/relay/decoder evidence only. No fixture insertion.
    @MainActor
    func testReviewedPlavioDeliveryDecodesThroughGuardedRelayOnPhysicalDevice() async throws {
        #if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
        try await ReviewedAddonPhysicalCanary.run(on: self, source: .plavio)
        #else
        throw XCTSkip("Requires the explicit FOTTY_REVIEWED_ADDON_CANARY flag on a physical iOS device; no playback pass.")
        #endif
    }

    private var streamPath: String { "/stream/tv/" + fixtureID + ".json" }
    private var cricketKickoff: Date { ISO8601DateFormatter().date(from: "2026-10-28T04:00:00Z")! }
    private var cricketID: String { "plaviohdtv-sfly-streamed:cricket-ban-wi-t1d1" }
    private var cricketCatalogPath: String { "/catalog/tv/plaviohd-cricket.json" }
    private var cricketStreamPath: String { "/stream/tv/" + cricketID + ".json" }

    private func cricketEntry(id: String? = nil, name: String? = nil, pair: String = "Bangladesh vs West Indies",
                              qualifier: String = "1st Test Day 1", date: String = "28 Oct 2026 · 04:00 UTC",
                              genres: [String] = ["Cricket"]) -> PlavioSportsCatalogEntry {
        .init(id: id ?? cricketID, name: name ?? (pair + " - " + qualifier),
              description: pair + "\n" + date, genres: genres)
    }

    private func cricketEntryJSON(_ row: PlavioSportsCatalogEntry? = nil) -> [String: Any] {
        let row = row ?? cricketEntry()
        return ["id": row.id, "type": row.type!, "name": row.name, "description": row.description!, "genres": row.genres!]
    }

    private func currentCricketCatalogJSON() -> [String: Any] {
        // Faithful 1.9.57 TV envelope: the daily Test sibling and generic
        // channel remain visible to the matcher; neither is a stream claim.
        ["metas": [
            ["id": "plaviohdtv-sfly-leaf:now-sky3434", "type": "tv", "name": "(FHD) : SKY SPORTS CRICKET",
             "description": "Live IPTV Recording\nLive on NOW-SKY3434\nLIVE NOW", "genres": ["Cricket"]],
            cricketEntryJSON(),
            cricketEntryJSON(cricketEntry(id: "plaviohdtv-sfly-streamed:cricket-ban-wi-t1d2",
                qualifier: "1st Test Day 2", date: "29 Oct 2026 · 04:00 UTC"))
        ]]
    }

    @MainActor
    func testPlavioLiveCNCCricketUsesExactDatedOfficialLimitedOversFixture() {
        let start = ISO8601DateFormatter().date(from: "2026-11-05T04:40:00Z")!
        let row = PlavioSportsCatalogEntry(id: "plaviohdtv-cnc-playztv-86",
            name: "Adelaide Strikers Women vs Brisbane Heat Women", description: "Starts 2026-11-05 04:40 UTC", genres: ["Cricket"])
        let request = officialCricketRequest(home: "Adelaide Strikers Women", away: "Brisbane Heat Women",
            format: .t20, competition: "WBBL", kickoff: start)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request, from: [row]), .matched(row))
        let wrongTime = officialCricketRequest(home: "Adelaide Strikers Women", away: "Brisbane Heat Women",
            format: .t20, competition: "WBBL", kickoff: start.addingTimeInterval(3600))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: wrongTime, from: [row]), .missing)
        XCTAssertFalse(PlavioSportsAddonClient.supportsCNCOfficialCricket(officialCricketRequest()))
        XCTAssertFalse(PlavioSportsAddonClient.supportsCNCOfficialCricket(officialCricketRequest(format: .odi, verified: false)))
        let conflicting = PlavioSportsCatalogEntry(id: row.id, name: row.name,
            description: "Starts 2026-11-06 04:40 UTC", genres: ["Cricket"])
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request, from: [row, conflicting]), .conflicting)
        let invalid = PlavioSportsCatalogEntry(id: row.id, name: row.name,
            description: "Starts 2026-02-30 04:40 UTC", genres: ["Cricket"])
        XCTAssertNil(PlavioSportsAddonClient.cncCricketIdentity(invalid))
    }

    func testPlavioLiveCricketDeliveryKeepsNarrowHeadersAndPath() {
        let url = URL(string: "https://dai-fancode.pages.dev/mumbai/fixture/index.m3u8")!
        let headers = ["Referer": "https://fancode.com/", "User-Agent": "ReactNativeVideo/9.11.1"]
        XCTAssertTrue(PlavioSportsAddonClient.admitsCricketDelivery(url, headers: headers))
        XCTAssertFalse(PlavioSportsAddonClient.admitsCricketDelivery(url, headers: [:]))
        XCTAssertFalse(PlavioSportsAddonClient.admitsCricketDelivery(url, headers: headers.merging(["Cookie":"private"], uniquingKeysWith: { _, b in b })))
        XCTAssertFalse(PlavioSportsAddonClient.admitsCricketDelivery(URL(string: "http://dai-fancode.pages.dev/mumbai/fixture/index.m3u8")!, headers: headers))
        XCTAssertFalse(PlavioSportsAddonClient.admitsCricketDelivery(URL(string: "https://dai-fancode.pages.dev/other/fixture/index.m3u8")!, headers: headers))
        XCTAssertNotEqual(PlavioSportsAddonClient.sourceKey(url: url), PlavioSportsAddonClient.sourceKey(url: url, headers: headers))
    }

    private func explicitCricketRequest(qualifier: String = "1st Test Day 1") -> StreamPlaybackRequest {
        .init(matchID: "existing-cricket", displayTitle: "Bangladesh vs West Indies - " + qualifier,
              homeTeam: "Bangladesh", awayTeam: "West Indies", category: "cricket", kickoffDate: cricketKickoff)
    }

    @MainActor
    private func officialCricketRequest(home: String = "Bangladesh", away: String = "West Indies",
                                        format: CricketFixtureCatalog.Format = .test,
                                        competition: String = "West Indies in Bangladesh Test Series",
                                        kickoff: Date? = nil, verified: Bool = true,
                                        conflicted: Bool = false) -> StreamPlaybackRequest {
        let kickoff = kickoff ?? cricketKickoff
        let receipt = CricketFixtureMetadata(fixtureID: "reviewed-existing-fixture", competitionID: "icc",
            competitionName: competition, format: format, status: .scheduled, observedAt: kickoff,
            verified: verified)
        let title = "\(competition) · \(home) vs \(away)"
        let event = EventReference(id: CricketFixtureCatalog.fixtureIDPrefix + receipt.fixtureID, title: title,
            category: "cricket", date: Int64(kickoff.timeIntervalSince1970 * 1000), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
            hasCatalogIdentityConflict: conflicted, cricketFixture: receipt)
        return .init(matchID: event.id, displayTitle: title, homeTeam: home, awayTeam: away, category: "cricket",
                     kickoffDate: kickoff, preferredEvent: event)
    }

    private var footballCatalogPath: String { "/catalog/tv/" + PlavioSportsAddonClient.footballCatalogID + ".json" }

    private var dlhdID: String { "plaviohdtv-dlhd-ev-fixture1" }
    private var dlhdMetaPath: String { "/meta/tv/" + dlhdID + ".json" }
    private var dlhdStreamPath: String { "/stream/tv/" + dlhdID + ".json" }
    private var dlhdKickoff: Date { ISO8601DateFormatter().date(from: "2026-10-29T19:45:00Z")! }

    private func dlhdRequest(kickoff: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: "fotty-existing-dlhd-fixture", displayTitle: "Everton vs Newcastle United",
              homeTeam: "Everton", awayTeam: "Newcastle United", category: "football", kickoffDate: kickoff ?? dlhdKickoff)
    }

    private func dlhdEntry(id: String? = nil,
        name: String = "England - League Cup : Everton 🏴󠁧󠁢󠁥󠁮󠁧󠁿 vs Newcastle United 🏴󠁧󠁢󠁥󠁮󠁧󠁿",
        description: String = "Starts 19:45 (UK time) · 28 channels", genres: [String] = ["Football"],
        hasCompetingDateAuthority: Bool = false) -> PlavioSportsCatalogEntry {
        .init(id: id ?? dlhdID, name: name, description: description, genres: genres,
              hasCompetingDateAuthority: hasCompetingDateAuthority)
    }

    private func dlhdEntryJSON() -> [String: Any] {
        let row = dlhdEntry()
        return ["id": row.id, "type": "tv", "name": row.name, "description": row.description!, "genres": row.genres!]
    }

    // Minimal structural copy of the public Daddy day/category/event contract
    // observed29Oct23:57UTC, with event/channel IDs deliberately omitted. It
    // is finished-event schema evidence, never a current playback pin.
    private func dlhdHTML(header: String = "Thursday 29h Oct 2026 - Schedule Time UK GMTT",
        title: String = "⚽ England - League Cup : Everton 🏴󠁧󠁢󠁥󠁮󠁧󠁿 vs Newcastle United 🏴󠁧󠁢󠁥󠁮󠁧󠁿",
        clock: String = "19:45") -> String {
        """
        <section class="schedule__day"><h2 class="schedule__dayTitle">\(header)</h2>
        <div class="schedule__category"><span class="card__meta">All Soccer Events ⚽</span>
        <div class="schedule__event"><span class="schedule__time">\(clock)</span>
        <span class="schedule__eventTitle">\(title)</span><div class="schedule__channels"></div></div></div></section>
        """
    }

    private func dlhdOriginals(_ html: String) throws -> [PlavioSportsAddonClient.DLHDOriginalFixture] {
        try PlavioSportsAddonClient.dlhdOriginalFixtures(data: Data(html.utf8))
    }

    private func dlhdFixtureSession(metadata: PlavioFixtureProtocol.Response? = nil,
        original: PlavioFixtureProtocol.Response? = nil) throws -> URLSession {
        PlavioFixtureProtocol.configure([
            "/manifest.json": try .json(footballManifestJSON()),
            footballCatalogPath: try .json(["metas": [dlhdEntryJSON()]]),
            dlhdMetaPath: try metadata ?? .json(["meta": dlhdEntryJSON()]),
            "/": original ?? .body(Data(dlhdHTML().utf8)),
            dlhdStreamPath: try .json(["streams": [["url": delivery]]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlavioFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func footballManifestJSON(includeLegacy: Bool = true) -> [String: Any] {
        var manifest = manifestJSON(version: "1.9.82")
        var catalogs: [[String: Any]] = [["id": PlavioSportsAddonClient.footballCatalogID, "type": "tv"]]
        if includeLegacy { catalogs.append(["id": PlavioSportsAddonClient.catalogID, "type": "tv"]) }
        manifest["catalogs"] = catalogs
        return manifest
    }

    private func cricketManifestJSON() -> [String: Any] {
        var manifest = manifestJSON(version: "1.9.57")
        manifest["catalogs"] = [["id": PlavioSportsAddonClient.catalogID, "type": "tv"],
                                ["id": PlavioSportsAddonClient.cricketCatalogID, "type": "tv"]]
        return manifest
    }

    private func cricketFixtureSession(manifest: PlavioFixtureProtocol.Response? = nil,
                                       catalog: PlavioFixtureProtocol.Response? = nil) throws -> URLSession {
        PlavioFixtureProtocol.configure([
            "/manifest.json": try manifest ?? .json(cricketManifestJSON()),
            cricketCatalogPath: try catalog ?? .json(currentCricketCatalogJSON()),
            "/catalog/tv/plaviohd-live-sports.json": try .json(["metas": [entryJSON()]]),
            cricketStreamPath: try .json(["streams": [["name": "AS", "url": delivery,
                "behaviorHints": ["notWebReady": false]]]]),
            streamPath: try .json(["streams": [["url": delivery]]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlavioFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private var livePublisherID: String { "aston-villa-manchester-city-2026-10-24-1130" }
    private var liveFixtureID: String { "plaviohdtv-sfly-streamed:" + livePublisherID }
    private var liveStreamPath: String { "/stream/tv/" + liveFixtureID + ".json" }
    private var liveMetaPath: String { "/meta/tv/" + liveFixtureID + ".json" }

    private func liveRequest(home: String = "Aston Villa", away: String = "Manchester City",
                             category: String = "football") -> StreamPlaybackRequest {
        .init(matchID: "fotty-existing-villa-city", displayTitle: "\(home) vs \(away)",
              homeTeam: home, awayTeam: away, category: category,
              kickoffDate: Date(timeIntervalSince1970: 1_792_841_400))
    }

    private func liveEntry(id: String? = nil, name: String = "Aston Villa vs Manchester City",
                           description: String? = nil) -> PlavioSportsCatalogEntry {
        .init(id: id ?? liveFixtureID, name: name,
              description: description ?? (name + "\nLIVE NOW\nPopular match\nSources: Admin, Golf, Hotel"))
    }

    private func liveEntryJSON() -> [String: Any] {
        let row = liveEntry()
        return ["id": row.id, "type": "tv", "name": row.name, "description": row.description!, "genres": ["Sports"]]
    }

    private func liveMetaJSON() -> [String: Any] {
        ["id": liveFixtureID, "type": "tv", "name": "Aston Villa vs Manchester City",
         "description": "Aston Villa vs Manchester City\n24 Oct 2026 · 11:30 UTC"]
    }

    private func publisherJSON() -> [String: Any] {
        ["id": livePublisherID, "title": "Aston Villa vs Manchester City", "category": "football",
         "date": Int64(1_792_841_400_000),
         "teams": ["home": ["name": "Aston Villa"], "away": ["name": "Manchester City"]]]
    }

    private func publisherRows(_ rows: [[String: Any]]) throws -> [PlavioPublisherFixture] {
        try JSONDecoder().decode([PlavioPublisherFixture].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    private func liveFixtureSession(metadata: PlavioFixtureProtocol.Response? = nil,
                                    catalog: PlavioFixtureProtocol.Response? = nil,
                                    manifest: PlavioFixtureProtocol.Response? = nil,
                                    streams: PlavioFixtureProtocol.Response? = nil) throws -> URLSession {
        PlavioFixtureProtocol.configure([
            "/manifest.json": try manifest ?? .json(manifestJSON()),
            "/catalog/tv/plaviohd-live-sports.json": try catalog ?? .json(["metas": [liveEntryJSON()]]),
            liveMetaPath: try metadata ?? .json(["meta": liveMetaJSON()]),
            liveStreamPath: try streams ?? .json(["streams": [["url": delivery, "behaviorHints": ["notWebReady": false]]]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlavioFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func request(home: String = "Gimnasia y Esgrima de Mendoza", away: String = "Platense",
                         category: String = "football", kickoff: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: "fotty-existing-match", displayTitle: "\(home) vs \(away)", homeTeam: home, awayTeam: away,
              category: category, kickoffDate: kickoff ?? self.kickoff)
    }

    private func entry(id: String? = nil, type: String = "tv", name: String = "Gimnasia y Esgrima de Mendoza vs Platense",
                       description: String? = nil, genres: [String] = ["Sports"], hasMalformedIdentity: Bool = false) -> PlavioSportsCatalogEntry {
        .init(id: id ?? fixtureID, type: type, name: name,
              description: description ?? (name + "\n23 Oct 2026 · 21:30 UTC"), genres: genres,
              hasMalformedIdentity: hasMalformedIdentity)
    }

    private func entryJSON() -> [String: Any] {
        ["id": fixtureID, "type": "tv", "name": entry().name, "description": entry().description!, "genres": ["Sports"]]
    }

    private func resource(_ name: String, types: [String] = ["movie", "series", "tv"]) -> [String: Any] {
        ["name": name, "types": types, "idPrefixes": ["tt", "plaviohdtv-"]]
    }

    private func manifestJSON(version: String = "1.9.56") -> [String: Any] {
        ["id": "community.plaviohd.private", "version": version, "types": ["movie", "series", "tv"],
         "resources": [resource("stream"), resource("subtitles", types: ["movie", "series"]),
                       resource("meta"), resource("catalog", types: ["tv"])],
         "catalogs": [["id": "plaviohd-live-sports", "type": "tv"]], "behaviorHints": ["configurable": true]]
    }

    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    private func decodeStreams(_ rows: [[String: Any]]) throws -> [PlavioSportsStreamEntry] {
        rows.compactMap { row in
            guard let data = try? data(row) else { return nil }
            return try? JSONDecoder().decode(PlavioSportsStreamEntry.self, from: data)
        }
    }

    private func sessions(_ rows: [[String: Any]]) throws -> [StreamSession] {
        PlavioSportsAddonClient.makeSessions(from: try decodeStreams(rows), request: request(), addOnVersion: "1.9.56")
    }

    private func fixtureSession(manifest: PlavioFixtureProtocol.Response? = nil,
                                catalog: PlavioFixtureProtocol.Response? = nil,
                                streams: PlavioFixtureProtocol.Response? = nil) throws -> URLSession {
        PlavioFixtureProtocol.configure([
            "/manifest.json": try manifest ?? .json(manifestJSON()),
            "/catalog/tv/plaviohd-live-sports.json": try catalog ?? .json(["metas": [entryJSON()]]),
            streamPath: try streams ?? .json(["streams": [["url": delivery, "behaviorHints": ["notWebReady": false]]]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlavioFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}


/// All adapter requests terminate here. Tests never contact an add-on or media.
private final class PlavioFixtureProtocol: URLProtocol {
    enum Response {
        case body(Data), failure(Error), status(Int), controlled(PlavioFixtureGate)
        static func json(_ object: [String: Any]) throws -> Response {
            .body(try JSONSerialization.data(withJSONObject: object))
        }
    }
    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var recordedPaths: [String] = []
    private static var recordedTimeouts: [TimeInterval] = []
    private static var recordedHosts: [String] = []
    private static var recordedUserAgents: [String] = []
    private static var recordedRequests: [URLRequest] = []
    private static var responseQueues: [String: [Response]] = [:]
    static var paths: [String] { lock.lock(); defer { lock.unlock() }; return recordedPaths }
    static var timeouts: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recordedTimeouts }
    static var hosts: [String] { lock.lock(); defer { lock.unlock() }; return recordedHosts }
    static var userAgents: [String] { lock.lock(); defer { lock.unlock() }; return recordedUserAgents }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recordedRequests }
    static func configure(_ values: [String: Response]) {
        lock.lock(); responses = values; responseQueues = [:]; recordedPaths = []; recordedTimeouts = []; recordedHosts = []; recordedUserAgents = []; recordedRequests = []; lock.unlock()
    }
    static func reset() { configure([:]) }
    static func setResponse(_ response: Response, for path: String) {
        lock.lock(); responses[path] = response; responseQueues.removeValue(forKey: path); lock.unlock()
    }
    static func setResponses(_ values: [Response], for path: String) {
        lock.lock(); responseQueues[path] = values; lock.unlock()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let path = request.url?.path ?? ""
        Self.recordedPaths.append(path); Self.recordedTimeouts.append(request.timeoutInterval)
        Self.recordedHosts.append(request.url?.host ?? "")
        Self.recordedUserAgents.append(request.value(forHTTPHeaderField: "User-Agent") ?? "")
        Self.recordedRequests.append(request)
        let response: Response
        if var queue = Self.responseQueues[path], !queue.isEmpty {
            response = queue.removeFirst(); Self.responseQueues[path] = queue
        } else { response = Self.responses[path] ?? .failure(URLError(.fileDoesNotExist)) }
        Self.lock.unlock()
        complete(response)
    }
    private func complete(_ result: Response) {
        switch result {
        case .body(let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        case .status(let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .controlled(let gate): gate.start { [weak self] response in self?.complete(response) }
        }
    }
    override func stopLoading() {}
}

private final class PlavioFixtureGate {
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((PlavioFixtureProtocol.Response) -> Void)?
    private var pending: PlavioFixtureProtocol.Response?
    init(_ name: String) { started = XCTestExpectation(description: name) }
    func start(_ completion: @escaping (PlavioFixtureProtocol.Response) -> Void) {
        lock.lock(); let pending = self.pending; self.pending = nil
        if pending == nil { self.completion = completion }
        lock.unlock(); started.fulfill()
        if let pending { completion(pending) }
    }
    func respond(_ response: PlavioFixtureProtocol.Response) {
        lock.lock(); let completion = self.completion; self.completion = nil
        if completion == nil { pending = response }
        lock.unlock(); completion?(response)
    }
}
