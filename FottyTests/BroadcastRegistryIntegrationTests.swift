import XCTest
@testable import Fotty

@MainActor
final class BroadcastRegistryIntegrationTests: XCTestCase {
    // Adapter selectors use their production current-receipt clock. Keep this
    // in-memory fixture current, with all programme dates explicitly supplied.
    private var now: Date { Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60) }

    func testCloudCohortCoverageCannotSuppressUnrepresentedOrFailedLocalSport() {
        let clock = now
        let football = StreamPlaybackRequest(matchID: "football", displayTitle: "Arsenal vs Chelsea", homeTeam: "Arsenal",
            awayTeam: "Chelsea", category: "football", kickoffDate: clock)
        let cricket = StreamPlaybackRequest(matchID: "cricket", displayTitle: "India vs England", homeTeam: "India",
            awayTeam: "England", category: "cricket", kickoffDate: clock)
        func coverage(_ scope: String, _ status: BroadcastRegistrySnapshot.CoverageStatus = .available,
                      complete: Bool = true) -> BroadcastRegistrySnapshot.Provider {
            .init(providerCode: "plaviosports", scope: scope, status: status, complete: complete,
                observedAt: clock, expiresAt: clock.addingTimeInterval(600))
        }
        func hasLocalLane(_ providers: [BroadcastRegistrySnapshot.Provider], requests: [StreamPlaybackRequest]) -> Bool {
            let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "scope-test", generatedAt: clock,
                providers: providers, broadcasts: [], links: [])
            return FixtureSourceCatalogCollector.lanes(registrySnapshot: snapshot, requests: requests, at: clock).contains {
                    $0.providerCode == "plaviosports" && $0.origin == .local
                }
        }
        XCTAssertTrue(hasLocalLane([coverage("football", .partial, complete: false), coverage("cricket", .failed, complete: false)],
            requests: [football, cricket]))
        XCTAssertTrue(hasLocalLane([coverage("football")], requests: [football, cricket]), "Complete football cannot claim cricket")
        XCTAssertTrue(hasLocalLane([coverage("networks")], requests: [cricket]), "Channels do not cover fixture discovery")
        XCTAssertTrue(hasLocalLane([coverage("live")], requests: [football]), "A generic scope is not an admitted all-sport contract")
        XCTAssertTrue(hasLocalLane([coverage("football")], requests: []), "Missing request context cannot justify suppressing a provider")
        XCTAssertFalse(hasLocalLane([coverage("football")], requests: [football]))
        XCTAssertFalse(hasLocalLane([coverage("football"), coverage("cricket", .empty)], requests: [football, cricket]))
    }

    func testRegisteredASSelectsOnlyAdvertisedIDAndRejectsChangedSourceDate() throws {
        let clock = now, kickoff = clock.addingTimeInterval(-3_600)
        let id = "plaviohdtv-sfly-streamed:football-arsenal-chelsea-1"
        let request = try registered(provider: "plaviosports", id: id, at: clock, kickoff: kickoff)
        let first = PlavioSportsCatalogEntry(id: id, type: "tv", name: "Arsenal vs Chelsea",
            description: "Arsenal vs Chelsea\n" + text(kickoff, "d MMM yyyy · HH:mm 'UTC'"), genres: ["Sports"])
        let sibling = PlavioSportsCatalogEntry(id: id + "-other", type: "tv", name: first.name,
            description: first.description, genres: first.genres)
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request, from: [sibling, first]), .matched(first))
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request, from: [sibling]), .missing)
        let changed = PlavioSportsCatalogEntry(id: id, type: "tv", name: first.name,
            description: "Arsenal vs Chelsea\n" + text(kickoff.addingTimeInterval(60), "d MMM yyyy · HH:mm 'UTC'"), genres: ["Sports"])
        XCTAssertEqual(PlavioSportsAddonClient.selectMatch(for: request, from: [changed]), .conflicting)
    }

    func testRegisteredFSDoesNotChooseAnotherSamePairDelivery() throws {
        let clock = now, kickoff = clock.addingTimeInterval(-3_600), id = "dlstreams:event:aaaaaaaaaaaa"
        let request = try registered(provider: "flixstreams", id: id, at: clock, kickoff: kickoff)
        let description = "Category: All Soccer Events ⚽\nDate: \(text(kickoff, "yyyy-MM-dd")) (UTC)\nTime: \(text(kickoff, "HH:mm"))\nChannels: Example Sports"
        let first = FlixStreamsCatalogEntry(id: id, type: "tv", name: "⚽ England - Premier League : Arsenal vs Chelsea",
            description: description, genres: ["Live TV", "Sports", "All Soccer Events ⚽"])
        let sibling = FlixStreamsCatalogEntry(id: "dlstreams:event:bbbbbbbbbbbb", type: "tv", name: first.name,
            description: description, genres: first.genres)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request, from: [sibling, first]), .matched(first))
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request, from: [sibling]), .missing)
        let wrong = FlixStreamsCatalogEntry(id: id, type: "tv", name: "⚽ England - Premier League : Arsenal Women vs Chelsea Women",
            description: description, genres: first.genres)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request, from: [wrong]), .conflicting)
    }

    func testCNCObservationHashIsNotAnExecutableCatalogID() throws {
        let clock = now, kickoff = clock.addingTimeInterval(-3_600)
        let request = try registered(provider: "cncsports", id: "cnc-observation:" + String(repeating: "a", count: 64), at: clock, kickoff: kickoff)
        let actual = CNCSportsCatalogEntry(id: "cnc:AAA", name: "Arsenal vs Chelsea")
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request, from: [actual]).isEmpty)
    }

    func testRegistryAssociationNeverExtendsDescriptorLease() throws {
        let clock = now, kickoff = clock.addingTimeInterval(-3_600)
        let request = try registered(provider: "plaviosports", id: "plaviohdtv-sfly-streamed:football-arsenal-chelsea-1", at: clock, kickoff: kickoff)
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "plaviosports",
            providerEventID: request.registryMatch!.broadcast.providerEventID, streamID: request.registryMatch!.broadcast.streamID,
            manifestRevision: "test", verifiedAt: clock, expiresAt: clock.addingTimeInterval(90), at: clock))
        XCTAssertFalse(binding.matches(request: request, providerCode: "plaviosports", at: clock.addingTimeInterval(90)))
        XCTAssertTrue(request.registryMatch!.matches(request: request, providerCode: "plaviosports",
            providerEventID: binding.providerEventID, streamID: binding.streamID, at: clock.addingTimeInterval(90)),
            "A stable listing can permit a new resolution while the old descriptor stays expired")
    }

    func testRegistryWatchPolicySharesNewerNegativeVetoWithoutHidingHealthyProvider() throws {
        let clock = now, kickoff = clock.addingTimeInterval(-3_600)
        let first = try registered(provider: "communitysports", id: "nuvio_sport_registered", at: clock, kickoff: kickoff)
        let second = try registered(provider: "plaviosports", id: "plaviohdtv-sfly-streamed:football-arsenal-chelsea-1", at: clock, kickoff: kickoff)
        let matches = [first.registryMatch!, second.registryMatch!], index = FixtureStreamDiscoveryIndex()
        let empty = try XCTUnwrap(index.begin(for: first, providerCode: "communitysports", preflight: false,
            at: clock.addingTimeInterval(1)))
        index.complete(empty, sessions: [], at: clock.addingTimeInterval(1))
        XCTAssertEqual(BroadcastRegistryWatchPolicy.eligible(matches, for: first, discoveryIndex: index,
            at: clock.addingTimeInterval(1)).map { $0.broadcast.providerCode }, ["plaviosports"])
        let failure = try XCTUnwrap(index.begin(for: first, providerCode: "plaviosports", preflight: false,
            at: clock.addingTimeInterval(2)))
        index.complete(failure, sessions: [], failure: StreamFailure(providerName: "AS1", category: .manifestUnreachable,
            technicalMessage: "Descriptor unavailable", userMessage: "Broadcast unconfirmed", retryable: true, fallbackAllowed: true),
            at: clock.addingTimeInterval(2))
        XCTAssertEqual(BroadcastRegistryWatchPolicy.eligible(matches, for: first, discoveryIndex: index,
            at: clock.addingTimeInterval(2)).map { $0.broadcast.providerCode }, ["plaviosports"],
            "An unconfirmed fetch cannot withdraw an unexpired exact listing")
        let rejection = try XCTUnwrap(index.begin(for: first, providerCode: "plaviosports", preflight: false,
            at: clock.addingTimeInterval(3)))
        index.complete(rejection, sessions: [], failure: LiveStreamResolver.communitySportsFailure(from: .conflictingMatch),
            at: clock.addingTimeInterval(3))
        XCTAssertTrue(BroadcastRegistryWatchPolicy.eligible(matches, for: first, discoveryIndex: index,
            at: clock.addingTimeInterval(3)).isEmpty)
        let newer = try registered(provider: "communitysports", id: "nuvio_sport_registered", at: clock.addingTimeInterval(4), kickoff: kickoff)
        XCTAssertEqual(BroadcastRegistryWatchPolicy.eligible([newer.registryMatch!], for: newer, discoveryIndex: index,
            at: clock.addingTimeInterval(4)).count, 1, "A genuinely newer source observation can permit another normal Watch attempt")
    }

    func testTVAssignmentsRetainEachMatchedChannelAndOriginalCoverageClock() throws {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try footballTV(channelLabel: "TV2", clock: clock)
        let second = try footballTV(channelLabel: "TV7", clock: clock)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "tv-assignments", generatedAt: clock,
            providers: first.snapshot.providers, broadcasts: first.snapshot.broadcasts + second.snapshot.broadcasts,
            links: first.snapshot.links + second.snapshot.links)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let accepted = try BroadcastRegistrySnapshot.validated(from: encoder.encode(snapshot), at: clock)
        let request = StreamPlaybackRequest(event: first.event)
        let matches = accepted.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: clock)
        XCTAssertEqual(Set(matches.map(\.broadcast.streamID)), Set(snapshot.broadcasts.map(\.streamID)))
        XCTAssertEqual(matches.count, 2)
        for match in matches {
            XCTAssertEqual(match.broadcast.start, first.event.kickoffDate?.addingTimeInterval(-1_800))
            XCTAssertNil(match.broadcast.end, "A channel assignment does not invent a programme end")
            XCTAssertNotNil(ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(match), at: clock))
            let binding = StreamEventBinding(request: request.usingRegistryMatch(match), providerCode: "reviewedtv",
                providerEventID: match.broadcast.providerEventID, streamID: match.broadcast.streamID,
                manifestRevision: "tv-assignment-test", verifiedAt: clock,
                expiresAt: clock.addingTimeInterval(90), at: clock)
            XCTAssertNotNil(binding)
            XCTAssertEqual(first.event.kickoffDate, clock.addingTimeInterval(-600))
        }
        XCTAssertTrue(accepted.lookup(for: request, enabledProviderCodes: [], at: clock).isEmpty)
    }

    func testTVAssignmentTimingExceptionCannotEscapeItsReviewedStationOrFixture() throws {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        for lead: TimeInterval in [-1, 3_601] {
            let candidate = try footballTV(channelLabel: "TV2", clock: clock, coverageLead: lead)
            XCTAssertTrue(candidate.snapshot.lookup(for: .init(event: candidate.event),
                enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
        }
        let candidate = try footballTV(channelLabel: "TV2", clock: clock)
        let original = candidate.snapshot.broadcasts[0]
        let link = candidate.snapshot.links[0]
        func changed(_ record: BroadcastRegistrySnapshot.Broadcast, using alternateLink: BroadcastRegistrySnapshot.Link? = nil) -> BroadcastRegistrySnapshot {
            .init(schemaVersion: 1, revision: "changed-tv", generatedAt: clock,
                  providers: candidate.snapshot.providers, broadcasts: [record], links: [alternateLink ?? link])
        }
        var wrong = original; wrong.stationMarket = "AR"
        XCTAssertTrue(changed(wrong).lookup(for: .init(event: candidate.event), enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
        wrong = original; wrong.channelID = "sports-channel:unreviewed"
        XCTAssertTrue(changed(wrong).lookup(for: .init(event: candidate.event), enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
        wrong = original; wrong.competitionID = "champions-league"
        XCTAssertTrue(changed(wrong).lookup(for: .init(event: candidate.event), enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
        wrong = original; wrong.start = original.start?.addingTimeInterval(-86_400)
        XCTAssertTrue(changed(wrong).lookup(for: .init(event: candidate.event), enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
        XCTAssertTrue(candidate.snapshot.lookup(for: .init(event: candidate.event), enabledProviderCodes: ["reviewedtv"],
            at: clock.addingTimeInterval(601)).isEmpty)
        let genericLink = BroadcastRegistrySnapshot.Link(fixtureID: link.fixtureID, broadcastID: link.broadcastID,
            providerCode: link.providerCode, state: .listed, matchMethod: .exact,
            fixtureFingerprint: link.fixtureFingerprint, expiresAt: link.expiresAt)
        XCTAssertTrue(changed(original, using: genericLink).lookup(for: .init(event: candidate.event),
            enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
    }

    func testLegacyStaleTVAssignmentsPreserveFiveListedMatchesWithoutBorrowingAChannel() throws {
        let clock = now
        let tv = try footballTV(channelLabel: "TV2", clock: clock.addingTimeInterval(-660))
        let cs = try registered(provider: "communitysports", id: "cs_live", at: clock,
                                kickoff: clock.addingTimeInterval(-600))
        let healthy = try XCTUnwrap(cs.registryMatch)
        func makeWire(relation: String?, tvState: BroadcastRegistrySnapshot.LinkState = .needsVerification) -> BroadcastRegistrySnapshot {
            var rows: [BroadcastRegistrySnapshot.Broadcast] = []
            var links: [BroadcastRegistrySnapshot.Link] = []
            for index in 0..<25 {
                let isTV = index < 20
                let seed = isTV ? tv.snapshot.broadcasts[0] : healthy.broadcast
                let hash = String(format: "%064x", index)
                let fixtureID = "sports-fixture:premier-league:test-\(index)"
                let teams = ["Home \(index)", "Away \(index)"]
                let id = "br:" + hash
                let identifier = isTV ? "reviewed-tv:assignment:" + hash : "cs_\(index)"
                rows.append(.init(id: id, providerCode: seed.providerCode, providerEventID: identifier,
                    streamID: isTV ? seed.streamID : identifier, resourceType: "tv", scope: "football", kind: .event,
                    sport: "football", title: teams.joined(separator: " vs "), participants: teams, start: seed.start,
                    competitionID: seed.competitionID, squad: seed.squad, channelID: seed.channelID,
                    stationMarket: seed.stationMarket, observedAt: seed.observedAt, expiresAt: seed.expiresAt,
                    verification: .dated, issues: []))
                links.append(.init(fixtureID: fixtureID, broadcastID: id, providerCode: seed.providerCode,
                    state: isTV ? tvState : .listed, matchMethod: isTV ? .channelAssignment : .exact,
                    fixtureFingerprint: .init(fixtureID: fixtureID, sport: "football", start: clock.addingTimeInterval(-600),
                        participants: teams, competitionID: "premier-league", squad: .init(gender: .men, ageGroup: "senior")),
                    expiresAt: seed.expiresAt, reason: isTV && tvState != .listed ? "stale-source" : nil,
                    startRelation: isTV ? relation : nil))
            }
            return .init(schemaVersion: 1, revision: "mixed-stale-tv", generatedAt: clock,
                         providers: [tv.snapshot.providers[0], healthy.provider], broadcasts: rows, links: links)
        }
        for relation in [nil, "channel-coverage"] as [String?] {
            let snapshot = try BroadcastRegistrySnapshot.validated(from: registryData(makeWire(relation: relation)), at: clock)
            let index = BroadcastRegistrySnapshot.LookupIndex(snapshot: snapshot)
            XCTAssertEqual(snapshot.links.filter { $0.state == .needsVerification }.count, 20)
            for link in snapshot.links {
                let f = link.fixtureFingerprint
                let metadata = SportsFixtureMetadata(fixtureID: f.fixtureID, sport: "football",
                    competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                    title: f.participants.joined(separator: " vs "),
                    participants: f.participants.map { .init(id: $0, name: $0) }, squad: try XCTUnwrap(f.squad),
                    status: .live, observedAt: clock, verified: true)
                let event = EventReference(id: f.fixtureID, title: metadata.title, category: "football",
                    date: Int64(f.start.timeIntervalSince1970), poster: nil, popular: false,
                    teams: .init(home: .init(name: f.participants[0], badge: nil),
                                 away: .init(name: f.participants[1], badge: nil)), sportsFixture: metadata)
                let found = index.lookup(for: .init(event: event), enabledProviderCodes: ["reviewedtv", "communitysports"], at: clock)
                XCTAssertEqual(found.map(\.broadcast.id), link.state == .listed ? [link.broadcastID] : [])
            }
        }
        let isolated = try BroadcastRegistrySnapshot.validated(from: registryData(makeWire(relation: "early-coverage")), at: clock)
        XCTAssertEqual(isolated.links.count, 5)
        XCTAssertEqual(isolated.providers.first { $0.providerCode == "reviewedtv" }?.status, .partial)
        for invalid in [makeWire(relation: nil, tvState: .listed), makeWire(relation: "early-coverage", tvState: .listed)] {
            XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: registryData(invalid), at: clock)) {
                XCTAssertEqual($0 as? BroadcastRegistrySnapshot.ValidationError, .danglingLink)
            }
        }
    }

    func testPartialNegativeTVAnnotationRefreshPreservesColdAndWarmMatchActions() async throws {
        let clock = now
        let first = try footballTV(channelLabel: "TV2", clock: clock.addingTimeInterval(-2), fixtureKickoff: clock.addingTimeInterval(-600))
        let second = try footballTV(channelLabel: "TV3", clock: clock, fixtureKickoff: first.event.kickoffDate)
        let mixed = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "mixed-annotations", generatedAt: clock,
            providers: second.snapshot.providers, broadcasts: first.snapshot.broadcasts + second.snapshot.broadcasts,
            links: first.snapshot.links + second.snapshot.links)
        var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: registryData(mixed)) as? [String: Any])
        var links = try XCTUnwrap(wire["links"] as? [[String: Any]])
        links[0]["state"] = "needsVerification"
        links[0]["reason"] = ["unexpected": true]
        wire["links"] = links
        let payload = try JSONSerialization.data(withJSONObject: wire)
        for warm in [false, true] {
            let domain = "Fotty.MixedTV.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            if warm { defaults.set(try registryData(first.snapshot), forKey: "Fotty.BroadcastRegistry.accepted.v1") }
            let client = BroadcastRegistryClient(defaults: defaults, fetch: { request in
                (payload, try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
            })
            let refreshed = await client.refresh(at: clock, force: true)
            XCTAssertEqual(refreshed?.revision, mixed.revision)
            XCTAssertEqual(refreshed?.providers.first?.status, .partial)
            XCTAssertEqual(refreshed?.providers.first?.complete, false)
            XCTAssertEqual(refreshed?.links.map(\.broadcastID), [second.snapshot.broadcasts[0].id])
            let index = FixtureStreamDiscoveryIndex()
            index.updateEnabledProviders(["reviewedtv"], revision: 1)
            let shown = CurrentEventBroadcastPolicy.action(for: second.event, in: [second.event], at: clock,
                discoveryIndex: index, registry: client)
            let projected = CurrentEventBroadcastPolicy.actionForCurrentEvent(second.event, at: clock,
                discoveryIndex: index, registry: client)
            XCTAssertEqual(shown?.event.id, second.event.id)
            XCTAssertEqual(projected?.event.id, shown?.event.id)
            XCTAssertEqual(shown?.evidence, .programmeAssignment)
            XCTAssertEqual(projected?.evidence, .programmeAssignment)
            XCTAssertNil(CurrentEventBroadcastPolicy.actionForCurrentEvent(second.event, at: clock.addingTimeInterval(601),
                discoveryIndex: index, registry: client))
            index.updateEnabledProviders([], revision: 2)
            XCTAssertNil(CurrentEventBroadcastPolicy.actionForCurrentEvent(second.event, at: clock,
                discoveryIndex: index, registry: client))
        }
        var missingParent = links
        missingParent[0]["broadcastID"] = "br:" + String(repeating: "f", count: 64)
        wire["links"] = missingParent
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: JSONSerialization.data(withJSONObject: wire), at: clock)) {
            XCTAssertEqual($0 as? BroadcastRegistrySnapshot.ValidationError, .danglingLink)
        }
        wire["links"] = links + [links[0]]
        XCTAssertThrowsError(try BroadcastRegistrySnapshot.validated(from: JSONSerialization.data(withJSONObject: wire), at: clock)) {
            XCTAssertEqual($0 as? BroadcastRegistrySnapshot.ValidationError, .duplicateIdentity)
        }
    }

    func testProgrammeDecisionKeepsEditionEvidenceSeparateFromTerritorialEntitlement() throws {
        let fixture = try footballTV(channelLabel: "TV2", clock: now)
        let original = fixture.snapshot, request = StreamPlaybackRequest(event: fixture.event)
        func match(_ access: BroadcastRegistrySnapshot.ProgrammeAccess?) -> BroadcastRegistryMatch {
            var link = original.links[0]
            link.access = access
            return .init(broadcast: original.broadcasts[0], link: link, provider: original.providers[0])
        }
        let historical = match(nil)
        let unknown = historical.decisionReceipt(at: now)
        XCTAssertEqual(unknown.fixtureID, fixture.event.id)
        XCTAssertEqual(unknown.edition, historical.broadcast.channelID)
        XCTAssertEqual(unknown.guideMarket, "UY")
        XCTAssertEqual(unknown.provenance, .espnEdition)
        XCTAssertEqual(unknown.confidence, .confirmedAssignment)
        XCTAssertEqual(unknown.access.entitlement, .unknown)
        XCTAssertEqual(unknown.access.territory, .unknown)
        XCTAssertNil(unknown.mediaExpiresAt)
        XCTAssertEqual(unknown.evidenceExpiresAt, historical.link?.expiresAt)
        for (entitlement, use, territory) in [
            (BroadcastRegistrySnapshot.ProgrammeAccess.Entitlement.denied, BroadcastRegistrySnapshot.ProgrammeAccess.Use.eventPlayback, BroadcastRegistrySnapshot.ProgrammeAccess.Territory.worldwide),
            (.blackout, .eventPlayback, .worldwide), (.cleared, .stationOnly, .worldwide),
            (.cleared, .eventPlayback, .restricted), (.unknown, .unknown, .unknown)
        ] {
            let denied = match(.init(entitlement: entitlement, use: use, territory: territory,
                reviewID: "test-policy", expiresAt: now.addingTimeInterval(60)))
            XCTAssertNil(ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(denied), at: now))
            XCTAssertEqual(denied.decisionReceipt(at: now).confidence, .unverified)
        }
        let permit = match(.init(entitlement: .cleared, use: .eventPlayback, territory: .worldwide,
            reviewID: "test-policy", expiresAt: now.addingTimeInterval(60)))
        XCTAssertNotNil(ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(permit), at: now))
        XCTAssertEqual(permit.acceptanceExpiresAt, now.addingTimeInterval(60))
        XCTAssertNil(ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(permit), at: now.addingTimeInterval(60)))
        var unreviewedEdition = historical.broadcast
        unreviewedEdition.stationMarket = "PE"
        let unreviewed = BroadcastRegistryMatch(broadcast: unreviewedEdition, link: historical.link, provider: historical.provider)
        XCTAssertFalse(unreviewed.permitsAutomaticProgramme(at: now))
        XCTAssertEqual(unreviewed.decisionReceipt(at: now).confidence, .unverified)
        var unreviewedSport = historical.broadcast
        unreviewedSport.competitionID = "new-competition"
        XCTAssertFalse(BroadcastRegistryMatch(broadcast: unreviewedSport, link: historical.link,
            provider: historical.provider).permitsAutomaticProgramme(at: now))
        var noGuide = historical.link!
        noGuide = .init(fixtureID: noGuide.fixtureID, broadcastID: noGuide.broadcastID, providerCode: noGuide.providerCode,
            state: .needsVerification, matchMethod: .channelAssignment, fixtureFingerprint: noGuide.fixtureFingerprint,
            expiresAt: noGuide.expiresAt, reason: "missing-programme", startRelation: "channel-coverage")
        let uncertain = BroadcastRegistryMatch(broadcast: historical.broadcast, link: noGuide, provider: historical.provider)
        XCTAssertNil(ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(uncertain), at: now))
        XCTAssertEqual(uncertain.decisionReceipt(at: now).confidence, .unverified)
    }

    func testForegroundTVPlanRetainsEnabledVerifiedFixtureBeforeProgrammeRefresh() throws {
        let fixture = try footballTV(channelLabel: "TV2", clock: now,
            fixtureID: "sports-fixture:premier-league:deferred-only")
        let request = StreamPlaybackRequest(event: fixture.event)
        XCTAssertFalse(CuratedStreamSourceCatalog.discoveryPlan(for: request,
            enabledProviderCodes: ["reviewedtv"]).optionalSources.contains { $0.providerCode == "reviewedtv" })
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: request,
            enabledProviderCodes: ["reviewedtv"], allowDeferredTVLookup: true).optionalSources.contains { $0.providerCode == "reviewedtv" })
        XCTAssertFalse(CuratedStreamSourceCatalog.discoveryPlan(for: request,
            enabledProviderCodes: [], allowDeferredTVLookup: true).optionalSources.contains { $0.providerCode == "reviewedtv" })
    }

    func testPlaybackRefreshReplacesExpiredOrMissingTVAssignmentWithFreshExactTV2() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now)
        for cached in [false, true] {
            let domain = "Fotty.TVRefresh.\(UUID().uuidString)", gate = RegistryFetchGate()
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { gate.fail(CancellationError()); defaults.removePersistentDomain(forName: domain) }
            if cached {
                let old = try footballTV(channelLabel: "TV2", clock: clock.addingTimeInterval(-660),
                    fixtureKickoff: fixture.event.kickoffDate)
                defaults.set(try registryData(old.snapshot), forKey: "Fotty.BroadcastRegistry.accepted.v1")
            }
            let client = BroadcastRegistryClient(defaults: defaults, fetch: { try await gate.fetch($0) })
            _ = await client.loadCached(at: clock)
            let request = StreamPlaybackRequest(event: fixture.event)
            XCTAssertTrue(client.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
            let refresh = Task { await client.refreshForPlayback(at: clock) }
            await fulfillment(of: [gate.started], timeout: 2)
            gate.succeed(try registryData(fixture.snapshot))
            _ = await refresh.value
            let match = try XCTUnwrap(client.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: clock).first)
            XCTAssertEqual(match.broadcast.channelID, ReviewedTVPlaylistClient.channel(forProviderName: "TV2")?.channelID)
            XCTAssertNotNil(ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(match), at: clock))
            XCTAssertEqual(gate.requests, 1)
            XCTAssertNil(client.lastRefreshFailure)
        }
    }

    func testDeferredTVLaneUsesCanonicalVerifiedCricketIdentityWithoutAdmittingTerminalFixture() {
        let clock = now, rawID = "icc:deferred-only"
        for (verified, status) in [(true, CricketFixtureCatalog.Status.live), (false, .live), (true, .finished)] {
            let metadata = CricketFixtureMetadata(fixtureID: rawID, competitionID: "icc", competitionName: "ICC",
                format: .odi, status: status, observedAt: clock, verified: verified,
                homeTeamID: "india", awayTeamID: "england")
            let event = EventReference(id: CricketFixtureCatalog.fixtureIDPrefix + rawID,
                title: "India vs England", category: "cricket", date: Int64(clock.timeIntervalSince1970) - 60,
                poster: nil, popular: false, teams: .init(home: .init(name: "India", badge: nil),
                    away: .init(name: "England", badge: nil)), cricketFixture: metadata)
            let plan = CuratedStreamSourceCatalog.discoveryPlan(for: .init(event: event),
                enabledProviderCodes: ["reviewedtv"], allowDeferredTVLookup: true, at: clock)
            XCTAssertEqual(plan.optionalSources.contains { $0.providerCode == "reviewedtv" }, verified && status == .live)
        }
    }

    func testPlaybackRefreshJoinsInflightOwnerWithoutDuplicateFetch() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now), gate = RegistryFetchGate()
        let domain = "Fotty.TVJoin.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { gate.fail(CancellationError()); defaults.removePersistentDomain(forName: domain) }
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { try await gate.fetch($0) })
        let owner = Task { await client.refresh(at: clock, force: true) }
        await fulfillment(of: [gate.started], timeout: 2)
        let joined = Task { await client.refreshForPlayback(at: clock) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(gate.requests, 1)
        gate.succeed(try registryData(fixture.snapshot))
        _ = await owner.value
        let result = await joined.value
        XCTAssertEqual(result?.revision, fixture.snapshot.revision)
        XCTAssertEqual(gate.requests, 1)
        XCTAssertFalse(client.isRefreshing)
    }

    func testCancelledPlaybackJoinDoesNotCancelExistingRegistryOwner() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now), gate = RegistryFetchGate()
        let domain = "Fotty.TVCancelJoin.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { gate.fail(CancellationError()); defaults.removePersistentDomain(forName: domain) }
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { try await gate.fetch($0) })
        let owner = Task { await client.refresh(at: clock, force: true) }
        await fulfillment(of: [gate.started], timeout: 2)
        let joined = Task { await client.refreshForPlayback(at: clock) }
        for _ in 0..<20 { await Task.yield() }
        joined.cancel()
        let cancelled = await joined.value
        XCTAssertNil(cancelled)
        XCTAssertTrue(client.isRefreshing)
        XCTAssertEqual(gate.requests, 1)
        gate.succeed(try registryData(fixture.snapshot))
        _ = await owner.value
        XCTAssertEqual(client.lookup(for: .init(event: fixture.event), enabledProviderCodes: ["reviewedtv"], at: clock).count, 1)
        XCTAssertFalse(client.isRefreshing)
    }

    func testPlaybackJoinTimeoutLeavesExistingOwnerRunning() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now), gate = RegistryFetchGate()
        let domain = "Fotty.TVJoinTimeout.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { gate.fail(CancellationError()); defaults.removePersistentDomain(forName: domain) }
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { try await gate.fetch($0) })
        let owner = Task { await client.refresh(at: clock, force: true) }
        await fulfillment(of: [gate.started], timeout: 2)

        _ = await client.refreshForPlayback(at: clock, maximumWait: .zero)

        XCTAssertEqual(client.lastRefreshFailure, .joinTimeout)
        XCTAssertTrue(client.isRefreshing)
        XCTAssertEqual(gate.requests, 1)
        gate.succeed(try registryData(fixture.snapshot))
        _ = await owner.value
        XCTAssertNil(client.lastRefreshFailure)
    }

    func testPlaybackRefreshReservationDoesNotForceAnotherFetchInsideThirtySeconds() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now)
        let domain = "Fotty.TVRefreshReservation.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let bytes = try registryData(fixture.snapshot)
        var requests = 0
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { request in
            requests += 1
            return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
        })
        _ = await client.refreshForPlayback(at: clock)
        _ = await client.refreshForPlayback(at: clock.addingTimeInterval(29))
        XCTAssertEqual(requests, 1)
        _ = await client.refreshForPlayback(at: clock.addingTimeInterval(30))
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(client.snapshot?.broadcasts.first?.expiresAt, fixture.snapshot.broadcasts.first?.expiresAt)
    }

    func testPlaybackRefreshFailureOrRollbackCannotRenewExpiredTVAssignment() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now)
        for failure in ["network", "validation", "rollback"] {
            let domain = "Fotty.TVFailedRefresh.\(UUID().uuidString)", gate = RegistryFetchGate()
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { gate.fail(CancellationError()); defaults.removePersistentDomain(forName: domain) }
            let old = try footballTV(channelLabel: "TV2", clock: clock.addingTimeInterval(-660),
                fixtureKickoff: fixture.event.kickoffDate)
            defaults.set(try registryData(old.snapshot), forKey: "Fotty.BroadcastRegistry.accepted.v1")
            let client = BroadcastRegistryClient(defaults: defaults, fetch: { try await gate.fetch($0) })
            _ = await client.loadCached(at: clock)
            let refresh = Task { await client.refreshForPlayback(at: clock) }
            await fulfillment(of: [gate.started], timeout: 2)
            if failure == "network" { gate.fail(URLError(.notConnectedToInternet)) }
            else if failure == "validation" { gate.succeed(Data("{\"invalid\":true}".utf8)) }
            else {
                let rollback = try footballTV(channelLabel: "TV2", clock: clock.addingTimeInterval(-720),
                    fixtureKickoff: fixture.event.kickoffDate)
                gate.succeed(try registryData(rollback.snapshot))
            }
            _ = await refresh.value
            XCTAssertTrue(client.lookup(for: .init(event: fixture.event), enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
            XCTAssertEqual(client.snapshot?.generatedAt, old.snapshot.generatedAt)
            XCTAssertEqual(client.snapshot?.broadcasts.first?.expiresAt, old.snapshot.broadcasts.first?.expiresAt)
            switch failure {
            case "network": XCTAssertEqual(client.lastRefreshFailure, .network)
            case "validation": XCTAssertEqual(client.lastRefreshFailure, .validation)
            default: XCTAssertEqual(client.lastRefreshFailure, .rejectedSnapshot)
            }
        }
    }

    func testPlaybackRefreshAdvancesFreshTVDespiteUnrelatedRegressingCSObservation() async throws {
        let clock = now, freshTV = try footballTV(channelLabel: "TV2", clock: clock)
        let oldTV = try footballTV(channelLabel: "TV2", clock: clock.addingTimeInterval(-660),
            fixtureKickoff: freshTV.event.kickoffDate)
        let csRequest = try registered(provider: "communitysports", id: "nuvio_sport_regression_fixture",
            at: clock.addingTimeInterval(-300), kickoff: freshTV.event.kickoffDate!)
        let priorCS = try XCTUnwrap(csRequest.registryMatch), priorLink = try XCTUnwrap(priorCS.link)
        let baseline = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "before-source-regression",
            generatedAt: clock.addingTimeInterval(-300), providers: oldTV.snapshot.providers + [priorCS.provider],
            broadcasts: oldTV.snapshot.broadcasts + [priorCS.broadcast], links: oldTV.snapshot.links + [priorLink])
        let row = priorCS.broadcast
        let regressed = BroadcastRegistrySnapshot.Broadcast(id: row.id, providerCode: row.providerCode,
            providerEventID: row.providerEventID, streamID: row.streamID, resourceType: row.resourceType,
            scope: row.scope, kind: row.kind, sport: row.sport, title: row.title, participants: row.participants,
            start: row.start, observedAt: clock.addingTimeInterval(-600), expiresAt: clock,
            verification: row.verification, issues: row.issues)
        let regressedLink = BroadcastRegistrySnapshot.Link(fixtureID: priorLink.fixtureID, broadcastID: priorLink.broadcastID,
            providerCode: priorLink.providerCode, state: .listed, matchMethod: priorLink.matchMethod,
            fixtureFingerprint: priorLink.fixtureFingerprint, expiresAt: clock)
        let candidate = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "fresh-tv-old-cs",
            generatedAt: clock, providers: freshTV.snapshot.providers + [.init(providerCode: "communitysports",
                scope: "football", status: .available, observedAt: clock, expiresAt: clock.addingTimeInterval(600))],
            broadcasts: freshTV.snapshot.broadcasts + [regressed], links: freshTV.snapshot.links + [regressedLink])
        let domain = "Fotty.TVIsolatedRegression.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(try registryData(baseline), forKey: "Fotty.BroadcastRegistry.accepted.v1")
        let candidateData = try registryData(candidate)
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { request in
            (candidateData, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
        })
        _ = await client.loadCached(at: clock)
        XCTAssertTrue(client.lookup(for: .init(event: freshTV.event), enabledProviderCodes: ["reviewedtv"], at: clock).isEmpty)
        let result = await client.refreshForPlayback(at: clock)
        XCTAssertNil(client.lastRefreshFailure)
        XCTAssertEqual(result?.generatedAt, clock)
        XCTAssertEqual(client.lookup(for: .init(event: freshTV.event), enabledProviderCodes: ["reviewedtv"], at: clock).count, 1)
        XCTAssertEqual(result?.broadcasts.first { $0.id == row.id }, row)
        XCTAssertEqual(result?.links.filter { $0.broadcastID == row.id }, [priorLink])
        let persisted = try XCTUnwrap(defaults.data(forKey: "Fotty.BroadcastRegistry.accepted.v1"))
        let restored = try BroadcastRegistrySnapshot.validated(from: persisted, at: clock)
        XCTAssertEqual(restored, result)
        XCTAssertTrue(restored.lookup(for: csRequest, enabledProviderCodes: ["communitysports"],
            at: clock.addingTimeInterval(301)).isEmpty, "Reconciliation must not renew the retained CS observation")
    }

    func testASPublishesWhileTVLaneJoinsHeldRegistryRefresh() async throws {
        let clock = now, fixture = try footballTV(channelLabel: "TV2", clock: now), gate = RegistryFetchGate()
        let domain = "Fotty.TVParallel.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { gate.fail(CancellationError()); defaults.removePersistentDomain(forName: domain) }
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { try await gate.fetch($0) })
        let owner = Task { await client.refresh(at: clock, force: true) }
        await fulfillment(of: [gate.started], timeout: 2)
        let request = StreamPlaybackRequest(event: fixture.event)
        let asChoice = StreamSession(matchID: request.matchID, playableURL: URL(string: "https://example.invalid/as.m3u8")!,
            streamType: .hls, providerName: "AS1")
        let tvChoice = StreamSession(matchID: request.matchID, playableURL: URL(string: "https://example.invalid/tv.m3u8")!,
            streamType: .hls, providerName: "TV2")
        let snapshots = RegistryChoiceSnapshots(), first = expectation(description: "AS publishes before the TV refresh completes")
        let asOutcome = discoveryOutcome([asChoice]), tvOutcome = discoveryOutcome([tvChoice]), empty = discoveryOutcome([])
        let discovery = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [
                { publish in publish(.partialSession(asChoice)); return asOutcome },
                { _ in
                    _ = await client.refreshForPlayback(at: clock)
                    let matches = await client.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: clock)
                    return matches.isEmpty ? empty : tvOutcome
                }
            ], deadline: .seconds(3), onSessions: { choices in
                await snapshots.append(choices)
                if choices.count == 1 { first.fulfill() }
            })
        }
        await fulfillment(of: [first], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        let early = await snapshots.all()
        XCTAssertEqual(early.map { $0.map(\.id) }, [[asChoice.id]])
        XCTAssertTrue(client.isRefreshing)
        XCTAssertEqual(gate.requests, 1)
        gate.succeed(try registryData(fixture.snapshot))
        _ = await owner.value
        let report = await discovery.value
        XCTAssertEqual(report.sessions.map(\.id), [asChoice.id, tvChoice.id])
        XCTAssertEqual(gate.requests, 1)
    }

    func testOptInProductionRegistrySnapshotPassesActualNativeWireValidation() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FOTTY_REGISTRY_SNAPSHOT_PATH"]
            ?? environment["TEST_RUNNER_FOTTY_REGISTRY_SNAPSHOT_PATH"], !path.isEmpty else {
            throw XCTSkip("No opt-in production registry snapshot supplied; offline wire-contract gate not executed")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawDate = try XCTUnwrap(document["generatedAt"] as? String)
        let stamp = try XCTUnwrap(BroadcastRegistrySnapshot.date(rawDate))
        let accepted = try BroadcastRegistrySnapshot.validated(from: data, at: stamp)
        XCTAssertEqual(accepted.generatedAt, stamp)
        XCTAssertFalse(accepted.providers.isEmpty)
    }

    func testOptInProductionRegistryRefreshReconcilesSavedBaselineWithoutLosingFreshTV() async throws {
        let environment = ProcessInfo.processInfo.environment
        func path(_ name: String) -> String? { environment[name] ?? environment["TEST_RUNNER_" + name] }
        guard let snapshotPath = path("FOTTY_REGISTRY_SNAPSHOT_PATH"), !snapshotPath.isEmpty,
              let baselinePath = path("FOTTY_REGISTRY_BASELINE_PREFERENCES_PATH"), !baselinePath.isEmpty else {
            throw XCTSkip("No opt-in production registry/baseline pair supplied; saved-cache reconciliation gate not executed")
        }
        let body = try Data(contentsOf: URL(fileURLWithPath: snapshotPath))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let clock = try XCTUnwrap((document["generatedAt"] as? String).flatMap(BroadcastRegistrySnapshot.date))
        let candidate = try BroadcastRegistrySnapshot.validated(from: body, at: clock)
        let preferences = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(contentsOf: URL(fileURLWithPath: baselinePath)), options: [], format: nil) as? [String: Any])
        let baselineData = try XCTUnwrap(preferences["Fotty.BroadcastRegistry.accepted.v1"] as? Data)
        let baseline = try BroadcastRegistrySnapshot.validated(from: baselineData, at: clock, cached: true)
        let priorRows = Dictionary(uniqueKeysWithValues: baseline.broadcasts.map { ($0.id, $0) })
        let regressions = candidate.broadcasts.filter { next in
            guard let prior = priorRows[next.id] else { return false }
            return next.observedAt < prior.observedAt
                || next.observedAt == prior.observedAt && next.expiresAt > prior.expiresAt
        }
        let freshTV = try XCTUnwrap(candidate.broadcasts.first { next in
            next.providerCode == "reviewedtv" && next.expiresAt > clock
                && priorRows[next.id].map { next.observedAt > $0.observedAt } == true
        })
        let domain = "Fotty.ProductionRegistryReconciliation.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(baselineData, forKey: "Fotty.BroadcastRegistry.accepted.v1")
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { request in
            (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
        })
        let refreshed = await client.refreshForPlayback(at: clock)
        let result = try XCTUnwrap(refreshed)
        XCTAssertNil(client.lastRefreshFailure)
        XCTAssertEqual(result.generatedAt, candidate.generatedAt)
        XCTAssertEqual(result.broadcasts.first { $0.id == freshTV.id }, freshTV)
        for regressed in regressions {
            let prior = try XCTUnwrap(priorRows[regressed.id])
            XCTAssertEqual(result.broadcasts.first { $0.id == regressed.id }, prior)
            XCTAssertEqual(result.links.filter { $0.broadcastID == regressed.id },
                baseline.links.filter { $0.broadcastID == regressed.id })
        }
        if regressions.isEmpty {
            // Live snapshots need not repeat the historical regression. Keep
            // the real-pair checks above, then inject the older observation
            // into a separate in-memory copy and require both rows to survive.
            let linked = Set(candidate.links.map(\.broadcastID))
            let row = try XCTUnwrap(candidate.broadcasts.first {
                $0.providerCode != "reviewedtv" && $0.kind == .event && $0.startBasis == nil
                    && !linked.contains($0.id) && priorRows[$0.id] != nil
            })
            let prior = try XCTUnwrap(priorRows[row.id])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var controlled = document
            var rows = try XCTUnwrap(controlled["broadcasts"] as? [[String: Any]])
            let target = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == row.id })
            rows[target]["observedAt"] = formatter.string(from: prior.observedAt.addingTimeInterval(-1))
            rows[target]["expiresAt"] = formatter.string(from: prior.expiresAt.addingTimeInterval(-1))
            controlled["broadcasts"] = rows
            let withRegression = try BroadcastRegistrySnapshot.validated(from: JSONSerialization.data(withJSONObject: controlled), at: clock)
            XCTAssertLessThan(try XCTUnwrap(withRegression.broadcasts.first { $0.id == row.id }).observedAt, prior.observedAt)
            let isolated = baseline.accepting(withRegression)
            XCTAssertEqual(isolated.generatedAt, candidate.generatedAt)
            XCTAssertEqual(isolated.broadcasts.first { $0.id == row.id }, prior)
            XCTAssertEqual(isolated.links.filter { $0.broadcastID == row.id }, baseline.links.filter { $0.broadcastID == row.id })
            XCTAssertEqual(isolated.broadcasts.first { $0.id == freshTV.id }, freshTV)
        }
    }

    private final class RegistryFetchGate {
        let started = XCTestExpectation(description: "Registry fetch owner started")
        private(set) var requests = 0
        private var request: URLRequest?
        private var pending: CheckedContinuation<(Data, URLResponse), Error>?
        func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests += 1
            guard pending == nil else { throw URLError(.resourceUnavailable) }
            self.request = request
            return try await withCheckedThrowingContinuation {
                pending = $0
                started.fulfill()
            }
        }
        func succeed(_ data: Data) {
            guard let request, let pending else { return }
            self.pending = nil
            pending.resume(returning: (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!))
        }
        func fail(_ error: Error) {
            let current = pending; pending = nil; current?.resume(throwing: error)
        }
    }

    private actor RegistryChoiceSnapshots {
        private var values: [[StreamSession]] = []
        func append(_ sessions: [StreamSession]) { values.append(sessions) }
        func all() -> [[StreamSession]] { values }
    }

    private func registryData(_ snapshot: BroadcastRegistrySnapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func discoveryOutcome(_ sessions: [StreamSession]) -> StreamResolutionOutcome {
        let diagnostic = StreamAttemptDiagnostics(attemptID: "registry-join-test", matchID: "registry-join-test",
            matchTitle: "Synthetic fixture", finalState: .readyToPlay, createdAt: Date(), completedAt: Date(),
            timeline: [], providerAttempts: [])
        return .success(.init(attemptID: "registry-join-test", sessions: sessions, diagnostics: diagnostic))
    }

    private func footballTV(channelLabel: String, clock: Date, coverageLead: TimeInterval? = nil,
        fixtureKickoff: Date? = nil, fixtureID: String = "sports-fixture:premier-league:arsenal-chelsea") throws
        -> (snapshot: BroadcastRegistrySnapshot, event: EventReference) {
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: channelLabel))
        let kickoff = fixtureKickoff ?? clock.addingTimeInterval(-600)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        // Default positive fixtures describe same-UTC-date coverage, including
        // when this clock-sensitive integration suite runs just after midnight.
        let lead = coverageLead ?? min(1_800, kickoff.timeIntervalSince(utc.startOfDay(for: kickoff)))
        let metadata = SportsFixtureMetadata(fixtureID: fixtureID, sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "Arsenal vs Chelsea",
            participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: clock, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: String(channelLabel.suffix(1)), count: 64),
            providerCode: "reviewedtv", providerEventID: "reviewed-tv:assignment:" + String(repeating: "d", count: 64),
            streamID: channel.streamID, resourceType: "tv", scope: "football", kind: .event, sport: "football",
            title: metadata.title, participants: ["Arsenal", "Chelsea"], start: kickoff.addingTimeInterval(-lead),
            competitionID: metadata.competitionID, squad: metadata.squad, channelID: channel.channelID, stationMarket: "UY",
            observedAt: clock, expiresAt: clock.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .channelAssignment, fixtureFingerprint: .init(fixtureID: event.id, sport: "football",
                start: kickoff, participants: ["Arsenal", "Chelsea"], competitionID: metadata.competitionID, squad: metadata.squad),
            expiresAt: record.expiresAt, startRelation: "channel-coverage")
        return (.init(schemaVersion: 1, revision: "tv-assignment", generatedAt: clock,
            providers: [.init(providerCode: "reviewedtv", scope: "football", status: .available,
                observedAt: clock, expiresAt: record.expiresAt)], broadcasts: [record], links: [link]), event)
    }

    private func registered(provider: String, id: String, at clock: Date, kickoff: Date) throws -> StreamPlaybackRequest {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:arsenal-chelsea", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "Arsenal vs Chelsea",
            participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: clock, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: provider,
            providerEventID: id, streamID: id, resourceType: "tv", scope: "football", kind: .event, sport: "football",
            title: metadata.title, participants: ["Arsenal", "Chelsea"], start: kickoff, observedAt: clock,
            expiresAt: clock.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: provider,
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: kickoff,
                participants: ["Arsenal", "Chelsea"], competitionID: "premier-league", squad: metadata.squad), expiresAt: record.expiresAt)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "integration", generatedAt: clock,
            providers: [.init(providerCode: provider, scope: "football", status: .available, observedAt: clock, expiresAt: record.expiresAt)],
            broadcasts: [record], links: [link])
        let canonical = StreamPlaybackRequest(event: event)
        let match = try XCTUnwrap(snapshot.lookup(for: canonical, enabledProviderCodes: [provider], at: clock).first)
        return canonical.usingRegistryMatch(match)
    }

    private func text(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
