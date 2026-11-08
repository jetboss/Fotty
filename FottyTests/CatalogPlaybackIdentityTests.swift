import XCTest
@testable import Fotty

@MainActor
final class CatalogPlaybackIdentityTests: XCTestCase {
    private let kickoff = Date(timeIntervalSince1970: 1_788_548_400)

    func testReviewedChannelBindingsCannotCrossWillowFoxOrFixtureClaims() throws {
        for channel in CricketBroadcastChannel.allCases {
            let canonical = CricketChannelCatalog.event(for: channel, in: [])
            let expected = StreamPlaybackRequest(event: canonical)
            let admitted = try XCTUnwrap(binding(for: expected, providerEventID: "nuvio_sport_network",
                                                 streamID: "nuvio_sport_network"))
            XCTAssertTrue(admitted.matches(request: expected, providerCode: "communitysports", at: kickoff))
            XCTAssertNil(admitted.kickoffDate)
            let session = StreamSession(matchID: expected.matchID, playableURL: URL(string: "https://media.example/channel.m3u8")!,
                streamType: .hls, providerName: "CS1", createdAt: kickoff, eventBinding: admitted)
            XCTAssertEqual(session.eventBinding, admitted)
            let other = CricketBroadcastChannel.allCases.first { $0 != channel }!
            XCTAssertFalse(admitted.matches(request: .init(event: CricketChannelCatalog.event(for: other, in: [])),
                                            providerCode: "communitysports", at: kickoff))
            let fixtureImpersonation = event(id: canonical.id, home: "India", away: "Australia", category: "cricket",
                                             title: canonical.title)
            XCTAssertNil(binding(for: .init(event: fixtureImpersonation)),
                         "A named dated fixture cannot use the reserved channel identity through fixture fallback")
            let titleImpersonation = StreamPlaybackRequest(matchID: canonical.id, displayTitle: "Willow 2",
                homeTeam: "Willow 2", awayTeam: "", category: "cricket")
            XCTAssertNil(binding(for: titleImpersonation))
            XCTAssertFalse(admitted.matches(request: titleImpersonation, providerCode: "communitysports", at: kickoff))
            XCTAssertNil(binding(for: request(home: "India", away: "Australia", category: "cricket", undated: true)))
            XCTAssertFalse(admitted.isCurrent(at: kickoff.addingTimeInterval(90)), "Channel bindings keep their finite metadata lease")
        }
    }

    func testCanonicalCricketChannelDiscoveryAndActionRespectCSOptInWithoutFixtureAuthority() throws {
        for channel in CricketBroadcastChannel.allCases {
            let row = CricketChannelCatalog.event(for: channel, in: [])
            let request = StreamPlaybackRequest(event: row)
            let enabled: Set<String> = ["communitysports", "plaviosports", "cncsports", "flixstreams", "streamvix", "score808"]
            let plan = CuratedStreamSourceCatalog.discoveryPlan(for: request, enabledProviderCodes: enabled, at: kickoff)
            XCTAssertEqual(plan.optionalSources.map(\.providerCode), ["communitysports"])
            XCTAssertFalse(plan.usesSharedCatalog)
            XCTAssertFalse(plan.score808SiteEligible)
            let disabled = CuratedStreamSourceCatalog.discoveryPlan(for: request,
                enabledProviderCodes: enabled.subtracting(["communitysports"]), at: kickoff)
            XCTAssertTrue(disabled.optionalSources.isEmpty)
            let index = FixtureStreamDiscoveryIndex()
            index.updateEnabledProviders([], revision: 1)
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: row, in: [], at: kickoff, discoveryIndex: index))
            index.updateEnabledProviders(["communitysports"], revision: 2)
            let action = try XCTUnwrap(CurrentEventBroadcastPolicy.action(for: row, in: [], at: kickoff, discoveryIndex: index))
            XCTAssertEqual(action.event.id, channel.canonicalID)
            XCTAssertFalse(action.isChannelFallback, "Explicit channel navigation is not a fixture-to-channel claim")
            XCTAssertNil(action.event.kickoffDate)
            XCTAssertNil(action.event.teams)
            index.updateEnabledProviders([], revision: 3, invalidating: "communitysports")
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: row, in: [], at: kickoff, discoveryIndex: index))
            let willow2 = EventReference(id: "cricket-channel:willow2", title: "Willow 2", category: "cricket",
                date: nil, poster: nil, popular: false, teams: nil, sources: [])
            XCTAssertFalse(CricketChannelPlaybackPolicy.canResolve(willow2, discoveryIndex: index))
            XCTAssertNil(binding(for: .init(event: willow2)))
        }
    }

    func testRegisteredPrimaryAssociationSelectsOnlyItsAdvertisedProviderRowAndKeepsRealSources() throws {
        let official = registeredOfficialFixture(providerAlias: false), request = StreamPlaybackRequest(event: official)
        let association = registeredPrimaryAssociation(for: official)
        let selected = event(id: "registered-provider-event", home: "Chelsea")
        let sibling = event(id: "unrelated-provider-event", home: "Chelsea")
        guard case .matched(let result) = CatalogPlaybackIdentity.registeredSelection(for: request, in: [sibling, selected],
            catalogObservedAt: kickoff, association: association, at: kickoff) else { return XCTFail("Expected the exact registered current provider row") }
        XCTAssertEqual(result.id, selected.id)
        XCTAssertEqual(result.sources?.map { $0.source + ":" + $0.id }, selected.sources?.map { $0.source + ":" + $0.id })
        XCTAssertEqual(request.matchID, official.id)
        XCTAssertEqual(request.kickoffDate, official.kickoffDate)
        guard case .missing = CatalogPlaybackIdentity.selection(for: request, in: [selected]) else {
            return XCTFail("Ordinary recovery still requires a previously accepted unmarked provider alias")
        }
        guard case .missing = CatalogPlaybackIdentity.registeredSelection(for: request, in: [sibling],
            catalogObservedAt: kickoff, association: association, at: kickoff) else {
            return XCTFail("An equivalent pair under another provider ID cannot replace the registered lookup")
        }
    }

    func testRegisteredPrimaryAssociationRejectsChangedSourceClockSquadAndReusedID() {
        let official = registeredOfficialFixture(), request = StreamPlaybackRequest(event: official)
        let association = registeredPrimaryAssociation(for: official)
        let good = event(id: "registered-provider-event", home: "Chelsea")
        let quarantined = EventReference(id: good.id, title: good.title, category: good.category, date: good.date,
            poster: good.poster, popular: good.popular, teams: good.teams, sources: good.sources, hasCatalogIdentityConflict: true)
        let conflictingCompetition = EventReference(id: good.id, title: good.title, category: good.category, date: good.date,
            poster: good.poster, popular: good.popular, teams: good.teams, sources: good.sources, competitionID: "champions-league")
        let cases = [[event(id: good.id, home: "Chelsea", date: kickoff.addingTimeInterval(1))],
                     [event(id: good.id, home: "Chelsea", away: "Arsenal")],
                     [event(id: good.id, home: "Chelsea Women", away: "Liverpool Women")],
                     [good, event(id: good.id, home: "Chelsea", away: "Arsenal")], [quarantined], [conflictingCompetition]]
        for rows in cases {
            guard case .conflicting = CatalogPlaybackIdentity.registeredSelection(for: request, in: rows,
                catalogObservedAt: kickoff, association: association, at: kickoff) else {
                return XCTFail("Registered ID must not hide a changed exact source identity or conflicting sibling")
            }
        }
        let substitutedStream = registeredPrimaryAssociation(for: official, streamID: "different-stream")
        guard case .conflicting = CatalogPlaybackIdentity.registeredSelection(for: request, in: [good],
            catalogObservedAt: kickoff, association: substitutedStream, at: kickoff) else {
            return XCTFail("A StreamEx event cannot manufacture a different advertised stream identity")
        }
    }

    func testRegisteredPrimaryAssociationRequiresFreshCatalogAndCurrentCanonicalFixture() {
        let official = registeredOfficialFixture(), association = registeredPrimaryAssociation(for: official)
        let row = event(id: "registered-provider-event", home: "Chelsea")
        for receipt in [kickoff.addingTimeInterval(-180), kickoff.addingTimeInterval(1)] {
            guard case .conflicting = CatalogPlaybackIdentity.registeredSelection(for: .init(event: official), in: [row],
                catalogObservedAt: receipt, association: association, at: kickoff) else {
                return XCTFail("A stale or future primary-catalog receipt is not a fresh admitted lookup")
            }
        }
        for changed in [registeredOfficialFixture(status: .finished), registeredOfficialFixture(verified: false),
                        registeredOfficialFixture(women: true)] {
            guard case .conflicting = CatalogPlaybackIdentity.registeredSelection(for: .init(event: changed), in: [row],
                catalogObservedAt: kickoff, association: association, at: kickoff) else {
                return XCTFail("The association must be rechecked against current terminal/squad/verification facts")
            }
        }
        let later = kickoff.addingTimeInterval(601)
        guard case .conflicting = CatalogPlaybackIdentity.registeredSelection(for: .init(event: official), in: [row],
            catalogObservedAt: later, association: association, at: later) else {
            return XCTFail("A newly read directory cannot renew expired registry source/link evidence")
        }
    }

    func testNamesCannotAdmitWrongOpponentDespitePopularityAndSources() {
        let wrong = event(away: "Chelsea", popular: true)
        XCTAssertNil(select([wrong]))
        XCTAssertNil(select([event(home: "Norwich City")]))
        XCTAssertEqual(select([wrong, event(id: "correct")])?.id, "correct")
    }

    func testBothTeamsAndBoundedKickoffAreMandatoryForFallback() {
        for offset: TimeInterval in [-86_400, 86_400, -901, 901] {
            XCTAssertNil(select([event(date: kickoff.addingTimeInterval(offset))]), "offset \(offset)")
        }
        for offset: TimeInterval in [-900, 900] {
            XCTAssertNotNil(select([event(date: kickoff.addingTimeInterval(offset))]))
        }
        XCTAssertNil(select([event(undated: true)]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: request(undated: true), in: [event()]))
    }

    func testAmbiguousFixturePairFailsClosedInsteadOfPopularityRanking() {
        let events = [event(id: "first"), event(id: "second", popular: true)]
        XCTAssertNil(select(events))
        XCTAssertNil(select(Array(events.reversed())))
        guard case .conflicting = CatalogPlaybackIdentity.selection(for: request(), in: events) else {
            return XCTFail("Ambiguity must not be treated as missing and recover a stale preferred row")
        }
    }

    func testVenueOrderAndSportCannotBeReversedOrIgnored() {
        XCTAssertNil(select([event(home: "Liverpool", away: "Ipswich Town")]))
        XCTAssertNil(select([event(category: "basketball")]))
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(for: request(category: "soccer"), in: [event()]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: request(category: ""), in: [event()]))
    }

    func testSeniorReserveWomensAndYouthIdentitiesRemainDistinct() {
        for suffix in ["Women", "W", "U21", "Under 21", "Reserves", "II", "B", "2"] {
            XCTAssertNil(select([event(home: "Ipswich Town \(suffix)")]), suffix)
            XCTAssertNil(select([event(away: "Liverpool \(suffix)")]), suffix)
        }
        for title in ["Ipswich Town vs Liverpool Women", "U21 Ipswich Town vs Liverpool", "Ipswich Town vs Liverpool Reserves"] {
            XCTAssertNil(select([event(title: title)]), "Senior team fields cannot override title: \(title)")
        }
        let reserve = event(home: "Ipswich Town U21", away: "Liverpool U21")
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Ipswich Town U21", away: "Liverpool U21"), in: [reserve]))
    }

    func testCanonicalAliasesAreWholeClubIdentitiesNotWordOverlap() {
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Ipswich", away: "Liverpool FC"), in: [event()]))
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Man Utd", away: "Spurs"),
            in: [event(home: "Manchester United", away: "Tottenham Hotspur")]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Manchester City", away: "Spurs"),
            in: [event(home: "Manchester United", away: "Tottenham Hotspur")]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Paris FC", away: "Liverpool"),
            in: [event(home: "Paris Saint-Germain")]))
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Türkiye", away: "South Korea"),
            in: [event(home: "Turkey", away: "Korea Republic")]))
    }

    func testUnknownClubsRequireWholeNamesAndDoNotLoseQualifiers() {
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Café United", away: "Harbour Town"),
            in: [event(home: "Cafe United", away: "Harbour Town")]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(
            for: request(home: "Cafe United", away: "Harbour Town"),
            in: [event(home: "Cafe City", away: "Harbour Town")]))
        XCTAssertNil(select([event(home: "Home", away: "Away")]))
    }

    func testColdLaunchExactProviderIDDoesNotRequireInventedTeamsOrDate() {
        let cold = StreamPlaybackRequest(matchID: "catalog:fixture", displayTitle: "Match",
            homeTeam: "", awayTeam: "", category: "", kickoffDate: nil)
        XCTAssertEqual(CatalogPlaybackIdentity.matchingEvent(for: cold, in: [event(undated: true)])?.id, "fixture")
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: cold, in: [event(id: "other")]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: cold, in: [event(), event(id: "catalog:fixture")]))
    }

    func testCatalogDedupQuarantinesConflictingIDsAndMergesOnlyEquivalentSources() throws {
        let conflict = AnalyticalDataEngine.deduplicateMatches([event(), event(away: "Chelsea")])
        XCTAssertEqual(conflict.count, 1)
        let quarantined = try XCTUnwrap(conflict.first)
        XCTAssertTrue(quarantined.hasCatalogIdentityConflict)
        XCTAssertTrue(quarantined.sources?.isEmpty == true)
        XCTAssertTrue(AnalyticalDataEngine.browsableCatalogEvents(from: conflict).isEmpty)
        XCTAssertFalse(quarantined.passesNearTermLiveListWindow(at: kickoff))
        XCTAssertNil(quarantined.homeBadgeURL)
        XCTAssertNil(quarantined.awayBadgeURL)
        XCTAssertEqual(AnalyticalDataEngine.footballLeagueClassification(for: quarantined).reasonCode, "conflicting_catalog_identity")
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: request(id: "fixture"), in: conflict))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: quarantined), in: [event()]))
        let restored = try JSONDecoder().decode(AnalyticalDataEngine.EventReference.self, from: JSONEncoder().encode(quarantined))
        XCTAssertTrue(restored.hasCatalogIdentityConflict)
        XCTAssertTrue(restored.sources?.isEmpty == true)
        XCTAssertTrue(AnalyticalDataEngine.deduplicateMatches([restored, event()]).first?.hasCatalogIdentityConflict == true)
        let sourceA = event()
        let sourceB = AnalyticalDataEngine.EventReference(id: sourceA.id, title: sourceA.title,
            category: sourceA.category, date: sourceA.date, poster: nil, popular: nil, teams: sourceA.teams,
            sources: [NexusASource(source: "hotel", id: "another-provider-event")])
        let mirrors = AnalyticalDataEngine.deduplicateMatches([sourceA, sourceB, sourceA])
        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors.first?.sources?.map(\.source), ["admin", "hotel"])
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(for: request(id: "fixture"), in: mirrors))
    }

    func testCatalogDedupMergesDifferentProviderIDsForOneReviewedFixture() throws {
        let schedule = AnalyticalDataEngine.EventReference(
            id: "2001", title: "Fenerbahçe SK vs AS Roma", category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: true,
            teams: .init(home: .init(name: "Fenerbahçe SK", badge: nil), away: .init(name: "AS Roma", badge: nil)),
            sources: []
        )
        let provider = AnalyticalDataEngine.EventReference(
            id: "ppv-fenerbahce-vs-roma", title: "Fenerbahce - Roma", category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: true,
            teams: .init(home: .init(name: "Fenerbahce", badge: nil), away: .init(name: "Roma", badge: nil)),
            sources: [.init(source: "golf", id: "1042")]
        )

        let merged = AnalyticalDataEngine.deduplicateMatches([schedule, provider])
        let fixture = try XCTUnwrap(merged.first)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(fixture.id, provider.id, "The source-backed provider row should remain the actionable representative")
        XCTAssertEqual(fixture.sources?.map(\.id), ["1042"])

        let later = AnalyticalDataEngine.EventReference(
            id: "later", title: provider.title, category: provider.category,
            date: Int64(kickoff.addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: true,
            teams: provider.teams, sources: provider.sources
        )
        XCTAssertEqual(AnalyticalDataEngine.deduplicateMatches([schedule, later]).count, 2)
    }

    func testFootballCatalogDedupUsesCanonicalClubIdentityWithoutLosingCompetitionOrSquad() {
        func row(_ id: String, home: String, away: String, title: String? = nil,
                 competition: String? = "premier-league", offset: Double = 0) -> EventReference {
            .init(id: id, title: title ?? "\(home) vs \(away)", category: "football",
                date: Int64(kickoff.addingTimeInterval(offset).timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
                sources: [], competitionID: competition)
        }
        let short = row("short", home: "Arsenal", away: "Leeds United")
        let officialName = row("long", home: "Arsenal FC", away: "Leeds United FC")
        XCTAssertEqual(AnalyticalDataEngine.deduplicateMatches([short, officialName]).count, 1)
        for other in [row("cup", home: "Arsenal FC", away: "Leeds United FC", competition: "fa-cup"),
                      row("unmarked", home: "Arsenal", away: "Leeds United", competition: nil),
                      row("later", home: "Arsenal", away: "Leeds United", offset: 86400),
                      row("youth", home: "Arsenal", away: "Leeds United", title: "Arsenal vs Leeds United U19"),
                      row("women", home: "Arsenal", away: "Leeds United", title: "Arsenal vs Leeds United Women")] {
            XCTAssertEqual(AnalyticalDataEngine.deduplicateMatches([short, other]).count, 2, other.id)
        }
    }

    func testExactIDDoesNotOverrideContradictorySuppliedFixtureContext() {
        let dated = request(id: "fixture")
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(for: dated, in: [event()]))
        for wrong in [event(away: "Chelsea"), event(date: kickoff.addingTimeInterval(86_400)),
                      event(undated: true), event(category: "basketball")] {
            XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: dated, in: [wrong, event(id: "other")] ))
        }
        XCTAssertNotNil(CatalogPlaybackIdentity.matchingEvent(for: request(id: "fixture", undated: true), in: [event(undated: true)]))
    }

    func testQuarantinedPreferredEventCannotStartAnyProviderLane() async throws {
        let quarantined = try XCTUnwrap(AnalyticalDataEngine.deduplicateMatches([event(), event(away: "Chelsea")]).first)
        let outcome = await LiveStreamResolver().resolvePlayback(for: StreamPlaybackRequest(event: quarantined))
        guard case .failure(let failure, let diagnostics) = outcome else {
            return XCTFail("A quarantined listing must fail before shared or independent provider discovery")
        }
        XCTAssertEqual(failure.category, .invalidMatchMapping)
        XCTAssertFalse(failure.fallbackAllowed)
        XCTAssertTrue(diagnostics.providerAttempts.isEmpty)
        do {
            _ = try await HybridStreamProvider().resolvePrioritizedSources(for: quarantined)
            XCTFail("Legacy direct resolution must reject the same quarantine")
        } catch ProcessorError.invalidData {
            // Expected preflight rejection; no transport or provider is invoked.
        }
    }

    func testChannelSelectionRemainsExactIDAndNeverClaimsAMatchProgramme() {
        let channel = event(id: "fox-channel", category: "cricket", undated: true, title: "Fox Cricket")
        let channelRequest = StreamPlaybackRequest(event: channel)
        XCTAssertEqual(CatalogPlaybackIdentity.matchingEvent(for: channelRequest, in: [channel])?.id, "fox-channel")
        let otherID = event(id: "different-fox", category: "cricket", undated: true, title: "Fox Cricket")
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: channelRequest, in: [otherID]))
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: request(category: "cricket"), in: [channel]))
    }

    func testExactIDPreservesSingleEventSportsWithoutUsingNameFallback() {
        let race = AnalyticalDataEngine.EventReference(id: "grand-prix", title: "Formula 1 Grand Prix",
            category: "motorsports", date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: nil,
            teams: nil, sources: [NexusASource(source: "delta", id: "race")])
        let raceRequest = StreamPlaybackRequest(event: race)
        XCTAssertEqual(CatalogPlaybackIdentity.matchingEvent(for: raceRequest, in: [race])?.id, "grand-prix")
        let unknownID = StreamPlaybackRequest(matchID: "unknown", displayTitle: raceRequest.displayTitle,
            homeTeam: raceRequest.homeTeam, awayTeam: raceRequest.awayTeam, category: raceRequest.category,
            kickoffDate: kickoff)
        XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: unknownID, in: [race]))
    }

    func testThreeGenericEnglishRoutesRemainAvailable() {
        let candidates = (1...3).map { candidate(number: $0) }
        let selected = AnalyticalDataEngine.curatedPlaybackCandidates(from: [candidates], limit: 12)
        XCTAssertEqual(selected.map(\.streamNo), [1, 2, 3])
        XCTAssertEqual(Set(selected.map(\.embedURL)).count, 3)
    }

    func testSameLabelSDFallbackRemainsAfterPreferredHDFails() {
        let hd = candidate(number: 1, hd: true), sd = candidate(number: 2, hd: false)
        let selected = AnalyticalDataEngine.curatedPlaybackCandidates(from: [[sd, hd]], limit: 6)
        var attempted: [String] = []
        let available = selected.first { option in
            attempted.append(option.embedURL)
            return option.embedURL == sd.embedURL
        }
        XCTAssertEqual(attempted, [hd.embedURL, sd.embedURL])
        XCTAssertEqual(available?.embedURL, sd.embedURL)
    }

    func testExactMirrorDuplicatesCollapseButQueryPathCaseAndFamilyRemain() {
        let url = "https://player.example/Live?channel=1"
        let items = [candidate(url: url, mirror: "first"), candidate(url: url, mirror: "second"),
                     candidate(url: "https://player.example/Live?channel=2"),
                     candidate(url: "https://player.example/live?channel=1"),
                     candidate(source: "hotel", url: url)]
        let selected = AnalyticalDataEngine.curatedPlaybackCandidates(from: [items], limit: 12)
        XCTAssertEqual(selected.count, 4)
        XCTAssertEqual(selected.filter { $0.sourceCode == "admin" && $0.embedURL == url }.count, 1)
    }

    func testFamilyFairnessAppliesAcrossDescriptorsAndEveryRound() {
        let admin = (1...10).map { candidate(number: $0) }
        let delta = (1...2).map { candidate(source: "delta", number: $0) }
        let hotel = (1...2).map { candidate(source: "hotel", number: $0) }
        let groups = [Array(admin.prefix(3)), Array(admin.dropFirst(3)), delta, hotel]
        let selected = AnalyticalDataEngine.curatedPlaybackCandidates(from: groups, limit: 6)
        XCTAssertEqual(selected.map(\.sourceCode), ["admin", "delta", "hotel", "admin", "delta", "hotel"])
        XCTAssertEqual(selected.map(\.streamNo), [1, 1, 1, 2, 2, 2])
        XCTAssertTrue(AnalyticalDataEngine.curatedPlaybackCandidates(from: groups, limit: 0).isEmpty)
    }

    func testFinalDeliveryDedupNeverUsesRedactedURLsOrIgnoresHeaders() {
        let first = StreamDeliveryIdentity(url: URL(string: "https://player.example/Live?channel=1")!, headers: ["Referer": "https://first.example/"])
        let same = StreamDeliveryIdentity(url: URL(string: "https://player.example/Live?channel=1")!, headers: ["Referer": "https://first.example/"])
        let otherChannel = StreamDeliveryIdentity(url: URL(string: "https://player.example/Live?channel=2")!, headers: ["Referer": "https://first.example/"])
        let otherHeaders = StreamDeliveryIdentity(url: URL(string: "https://player.example/Live?channel=1")!, headers: ["Referer": "https://second.example/"])
        XCTAssertEqual(Set([first, same, otherChannel, otherHeaders]).count, 3)
    }

    func testReviewedSourceAliasesHaveStableNativeCanonicalIDs() {
        let aliases = [("VfB Stuttgart", "Stuttgart", "vfbstuttgart"),
                       ("Red Bull New York", "New York Red Bulls", "redbullnewyork"),
                       ("D.C. United", "DC United", "dcunited"),
                       ("Real Sociedad", "Real Sociedad de Fútbol", "realsociedad"),
                       ("Udinese", "Udinese Calcio", "udinese")]
        for (canonical, alias, expectedID) in aliases {
            for name in [canonical, alias] {
                XCTAssertEqual(FootballCompetitionCatalog.canonicalClubID(for: name), expectedID, name)
                XCTAssertEqual(FootballCompetitionCatalog.canonicalTeamKey(name), expectedID, name)
            }
        }
        for competition in [FootballCompetitionID.bundesliga, .championsLeague] {
            XCTAssertTrue(FootballCompetitionCatalog.contains("VfB Stuttgart", in: competition))
            XCTAssertTrue(FootballCompetitionCatalog.contains("Stuttgart", in: competition))
        }
        for competition in FootballCompetitionID.allCases {
            for name in ["Red Bull New York", "New York Red Bulls", "D.C. United", "DC United"] {
                XCTAssertFalse(FootballCompetitionCatalog.contains(name, in: competition), name)
            }
        }
        XCTAssertTrue(FootballCompetitionCatalog.contains("Real Sociedad de Fútbol", in: .laLiga))
        XCTAssertTrue(FootballCompetitionCatalog.contains("Real Sociedad de Fútbol", in: .europaLeague))
        XCTAssertTrue(FootballCompetitionCatalog.contains("Udinese Calcio", in: .serieA))
        for name in ["Real Sociedad de Fútbol", "Udinese Calcio"] {
            XCTAssertFalse(FootballCompetitionCatalog.contains(name, in: .premierLeague), name)
        }
        let ambiguous = FootballCompetitionCatalog.ClubAliasLookup(clubs: [
            .init(name: "Alpha United", aliases: ["Shared Alias"]),
            .init(name: "Beta United", aliases: ["Shared Alias"])
        ])
        XCTAssertNil(ambiguous.canonicalClubID(for: "Shared Alias"))
    }

    func testReviewedSourceAliasesMatchInBothDirectionsWithoutExactProviderIDs() {
        for (canonical, alias) in [("VfB Stuttgart", "Stuttgart"),
                                   ("Red Bull New York", "New York Red Bulls"),
                                   ("D.C. United", "DC United"),
                                   ("Real Sociedad", "Real Sociedad de Fútbol"),
                                   ("Udinese", "Udinese Calcio")] {
            for (requested, supplied) in [(canonical, alias), (alias, canonical)] {
                for offset: TimeInterval in [-900, 0, 900] {
                    let homeRequest = request(home: requested, away: "Harbour Town")
                    let homeEvent = event(id: "reviewed", home: supplied, away: "Harbour Town",
                                          date: kickoff.addingTimeInterval(offset))
                    XCTAssertEqual(CatalogPlaybackIdentity.matchingEvent(for: homeRequest, in: [homeEvent])?.id,
                                   "reviewed", "\(requested), offset \(offset)")
                    let awayRequest = request(home: "Harbour Town", away: requested)
                    let awayEvent = event(id: "reviewed", home: "Harbour Town", away: supplied,
                                          date: kickoff.addingTimeInterval(offset))
                    XCTAssertEqual(CatalogPlaybackIdentity.matchingEvent(for: awayRequest, in: [awayEvent])?.id,
                                   "reviewed", "\(requested), offset \(offset)")
                }
            }
        }
    }

    func testReviewedAliasesPreserveOpponentVenueSportAndKickoffGuards() {
        for (canonical, alias) in [("VfB Stuttgart", "Stuttgart"),
                                   ("Red Bull New York", "New York Red Bulls"),
                                   ("D.C. United", "DC United"),
                                   ("Real Sociedad", "Real Sociedad de Fútbol"),
                                   ("Udinese", "Udinese Calcio")] {
            let expected = request(home: canonical, away: "Harbour Town")
            var invalid = [event(home: alias, away: "Other Town"),
                           event(home: "Harbour Town", away: alias),
                           event(home: alias, away: "Harbour Town", category: "basketball"),
                           event(home: alias, away: "Harbour Town", undated: true),
                           event(home: alias, away: "Harbour Town", title: "\(alias) vs Harbour Town Women")]
            for offset: TimeInterval in [-86_400, -901, 901, 86_400] {
                invalid.append(event(home: alias, away: "Harbour Town", date: kickoff.addingTimeInterval(offset)))
            }
            for candidate in invalid {
                XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: expected, in: [candidate]), canonical)
            }
            for suffix in ["Women", "W", "U17", "U21", "Under 21", "Reserves", "II", "B", "2"] {
                let squad = "\(alias) \(suffix)"
                XCTAssertNil(FootballCompetitionCatalog.canonicalClubID(for: squad), squad)
                XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: expected,
                    in: [event(home: squad, away: "Harbour Town")]), squad)
            }
        }
    }

    func testReviewedAliasesStillFailClosedOnAmbiguityAndConflictingExactIDs() {
        for (canonical, alias) in [("VfB Stuttgart", "Stuttgart"),
                                   ("Red Bull New York", "New York Red Bulls"),
                                   ("D.C. United", "DC United"),
                                   ("Real Sociedad", "Real Sociedad de Fútbol"),
                                   ("Udinese", "Udinese Calcio")] {
            let expected = request(home: canonical, away: "Harbour Town")
            let first = event(id: "first", home: canonical, away: "Harbour Town")
            let second = event(id: "second", home: alias, away: "Harbour Town", popular: true)
            for candidates in [[first, second], [second, first]] {
                guard case .conflicting = CatalogPlaybackIdentity.selection(for: expected, in: candidates) else {
                    XCTFail("Reviewed aliases must not rank away ambiguity: \(canonical)")
                    continue
                }
            }
            let wrongExact = event(id: expected.matchID, home: alias, away: "Other Town")
            guard case .conflicting = CatalogPlaybackIdentity.selection(for: expected, in: [wrongExact, first]) else {
                XCTFail("An alias must not bypass contradictory exact-ID metadata: \(canonical)")
                continue
            }
        }
    }

    func testEventBindingKeepsExactRequestAndShortMetadataFreshness() throws {
        let expected = request()
        let binding = try XCTUnwrap(binding(for: expected))
        XCTAssertEqual(binding.fixtureID, expected.matchID)
        XCTAssertEqual(binding.sport, "football")
        XCTAssertEqual(binding.kickoffDate, kickoff)
        XCTAssertEqual(binding.expiresAt, kickoff.addingTimeInterval(90), "A long URL lease cannot renew fixture evidence")
        XCTAssertTrue(binding.matches(request: expected, providerCode: "communitysports", at: kickoff))
        XCTAssertTrue(binding.isCurrent(at: kickoff.addingTimeInterval(89)))
        XCTAssertFalse(binding.isCurrent(at: kickoff.addingTimeInterval(90)))
        XCTAssertFalse(binding.matches(request: expected, providerCode: "plaviosports", at: kickoff))
        XCTAssertFalse(binding.matches(request: request(id: "another-fixture"), providerCode: "communitysports", at: kickoff))
        XCTAssertFalse(binding.matches(request: request(away: "Chelsea"), providerCode: "communitysports", at: kickoff))
        XCTAssertFalse(binding.matches(request: request(category: "cricket"), providerCode: "communitysports", at: kickoff))
        XCTAssertFalse(binding.matches(request: request(home: "Ipswich Town Women", away: "Liverpool Women"),
                                       providerCode: "communitysports", at: kickoff))
        let rescheduled = StreamPlaybackRequest(matchID: expected.matchID, displayTitle: expected.displayTitle,
            homeTeam: expected.homeTeam, awayTeam: expected.awayTeam, category: expected.category,
            kickoffDate: kickoff.addingTimeInterval(60))
        XCTAssertFalse(binding.matches(request: rescheduled, providerCode: "communitysports", at: kickoff))
        let shorter = try XCTUnwrap(self.binding(for: expected, expiresAt: kickoff.addingTimeInterval(20)))
        XCTAssertEqual(shorter.expiresAt, kickoff.addingTimeInterval(20))
    }

    func testEventBindingRejectsUnsafeOrUnverifiableReferences() {
        XCTAssertNil(binding(for: request(undated: true)))
        XCTAssertNil(binding(for: request(home: "Home", away: "Away")))
        XCTAssertNil(binding(providerCode: "arbitrary-addon"))
        for invalid in ["", "https://provider.example/private?token=secret", "event\nAuthorization", "event#fragment"] {
            XCTAssertNil(binding(providerEventID: invalid), invalid)
            XCTAssertNil(binding(streamID: invalid), invalid)
        }
        XCTAssertNil(binding(verifiedAt: kickoff.addingTimeInterval(31)))
        XCTAssertNil(binding(verifiedAt: kickoff.addingTimeInterval(-91)))
        XCTAssertNil(binding(expiresAt: kickoff))
        XCTAssertNil(binding(manifestRevision: "https://provider.example/manifest.json"))
    }

    func testEventBindingRejectsChangedCompetitionAndQuarantine() throws {
        func preferred(_ competition: String, conflict: Bool = false) -> StreamPlaybackRequest {
            let row = EventReference(id: "official-fixture", title: "Ipswich Town vs Liverpool", category: "football",
                date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "Ipswich Town", badge: nil), away: .init(name: "Liverpool", badge: nil)),
                sources: [], hasCatalogIdentityConflict: conflict, competitionID: competition)
            return StreamPlaybackRequest(event: row)
        }
        let bound = try XCTUnwrap(binding(for: preferred("premier-league")))
        XCTAssertFalse(bound.matches(request: preferred("carabao-cup"), providerCode: "communitysports", at: kickoff))
        XCTAssertFalse(bound.matches(request: preferred("premier-league", conflict: true),
                                     providerCode: "communitysports", at: kickoff))
        XCTAssertNil(binding(for: preferred("premier-league", conflict: true)))
    }

    func testSessionBindingCannotCrossSourceAndIsExcludedFromSavedJSON() throws {
        let expected = request()
        let bound = try XCTUnwrap(binding(for: expected))
        func session(provider: String = "CS1", matchID: String = "official-fixture") -> StreamSession {
            StreamSession(matchID: matchID, playableURL: URL(string: "https://media.example/live.m3u8")!,
                streamType: .hls, providerName: provider, canRefresh: true, createdAt: kickoff, eventBinding: bound)
        }
        let original = session()
        XCTAssertEqual(original.eventBinding, bound)
        XCTAssertNil(session(provider: "AS1").eventBinding)
        XCTAssertNil(session(provider: "Unreviewed CS1 title").eventBinding)
        XCTAssertNil(session(matchID: "other").eventBinding)
        XCTAssertNil(original.recordingEventBinding(bound, for: request(away: "Chelsea"), at: kickoff).eventBinding)
        XCTAssertNil(original.recordingEventBinding(bound, for: expected, at: kickoff.addingTimeInterval(90)).eventBinding)
        let encoded = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["eventBinding"])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("nuvio_sport_fixture"))
        let restored = try JSONDecoder().decode(StreamSession.self, from: encoded)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertNil(restored.eventBinding, "Saved metadata must resolve and bind the exact provider again")
    }

    func testReviewedDiscoveryPlanDoesNotRequireMasterCatalogSources() {
        let row = EventReference(id: "official-fixture", title: "Ipswich Town vs Liverpool", category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Ipswich Town", badge: nil), away: .init(name: "Liverpool", badge: nil)),
            sources: [])
        let plan = CuratedStreamSourceCatalog.discoveryPlan(for: StreamPlaybackRequest(event: row),
            enabledProviderCodes: ["communitysports", "plaviosports", "flixstreams", "arbitrary-addon"], at: kickoff)
        XCTAssertFalse(plan.usesSharedCatalog)
        XCTAssertFalse(plan.score808SiteEligible)
        XCTAssertEqual(plan.optionalSources.map(\.provider), [.communitySports, .plavioSports, .flixStreams])
        let disabled = CuratedStreamSourceCatalog.discoveryPlan(for: request(), enabledProviderCodes: [], at: kickoff)
        XCTAssertTrue(disabled.optionalSources.isEmpty)
    }

    func testReviewedPlanPreservesScoreOnlySharedDiscoveryAndExistingWindow() {
        let beforeWindow = kickoff.addingTimeInterval(-Score808LateDiscoveryPolicy.lookupLeadTime - 1)
        let scoreOnly = CuratedStreamSourceCatalog.discoveryPlan(for: request(), enabledProviderCodes: ["score808"], at: beforeWindow)
        XCTAssertEqual(scoreOnly.sharedCatalogProviderCodes, ["score808"])
        XCTAssertTrue(scoreOnly.usesSharedCatalog, "The hotel catalog route remains available before late-site discovery")
        XCTAssertFalse(scoreOnly.score808SiteEligible)
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: request(), enabledProviderCodes: ["score808"], at: kickoff).score808SiteEligible)
        let defaults = Set(CuratedStreamSourceCatalog.all.filter(\.defaultEnabled).map(\.providerCode))
        let defaultPlan = CuratedStreamSourceCatalog.discoveryPlan(for: request(), enabledProviderCodes: defaults, at: kickoff)
        XCTAssertEqual(defaultPlan.sharedCatalogProviderCodes, ["streamex", "score808"])
        XCTAssertTrue(defaultPlan.optionalSources.isEmpty, "A new plan must not enable optional sources")
        let undated = CuratedStreamSourceCatalog.discoveryPlan(for: request(undated: true),
            enabledProviderCodes: ["streamex", "communitysports", "plaviosports"], at: kickoff)
        XCTAssertTrue(undated.usesSharedCatalog)
        XCTAssertTrue(undated.optionalSources.isEmpty, "Dated exact optional lookup must not invent fixture authority")
        let cricket = CuratedStreamSourceCatalog.discoveryPlan(for: request(category: "cricket"),
            enabledProviderCodes: ["cncsports", "streamvix", "score808"], at: kickoff)
        XCTAssertTrue(cricket.optionalSources.isEmpty)
        XCTAssertFalse(cricket.score808SiteEligible)
    }

    func testExpiredBindingRetainsLookupIdentityWithoutClaimingFreshMetadata() throws {
        let expected = request()
        let previous = try XCTUnwrap(binding(for: expected))
        let later = kickoff.addingTimeInterval(120)
        XCTAssertTrue(previous.matchesIdentity(request: expected, providerCode: "communitysports"))
        XCTAssertFalse(previous.matches(request: expected, providerCode: "communitysports", at: later))
        let old = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/old.m3u8")!, streamType: .hls,
            providerName: "CS1", expiryTime: later.addingTimeInterval(300), canRefresh: true,
            createdAt: kickoff, eventBinding: previous)
        XCTAssertNil(old.renewingDelivery(from: old, for: expected, at: later),
            "An expired metadata receipt cannot masquerade as a fresh descriptor response")
        let current = try XCTUnwrap(renewalBinding(for: expected, at: later))
        let fresh = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/current.m3u8")!, streamType: .hls,
            providerName: "CS1", canRefresh: true, createdAt: later, eventBinding: current)
        XCTAssertNotNil(old.renewingDelivery(from: fresh, for: expected, at: later),
            "Metadata expiry must not prevent an exact fresh lookup; it is not transport revocation")
    }

    func testRenewalPreservesSelectedSourceIdentityAndAdoptsOnlyFreshDeliveryFields() throws {
        let expected = request(), now = kickoff.addingTimeInterval(10)
        let old = StreamSession(matchID: expected.matchID, title: "Original source",
            playableURL: URL(string: "https://media.example/old.m3u8")!, streamType: .hls,
            providerName: "CS2", requiredHeaders: ["User-Agent": "Old Player"], qualityLabel: "old",
            expiryTime: kickoff.addingTimeInterval(60), leaseID: "old-lease", canRefresh: true,
            createdAt: kickoff, eventBinding: try XCTUnwrap(binding(for: expected)))
        let current = try XCTUnwrap(renewalBinding(for: expected, at: now))
        let fresh = StreamSession(matchID: expected.matchID, title: "Fresh source",
            playableURL: URL(string: "https://media.example/new.m3u8")!, streamType: .hls,
            providerName: "CS3", requiredHeaders: ["User-Agent": "Fresh Player"], qualityLabel: "HD",
            expiryTime: now.addingTimeInterval(300), leaseID: "fresh-lease", canRefresh: true,
            diagnosticMetadata: ["route": "reviewed"], createdAt: now, eventBinding: current)
        let renewed = try XCTUnwrap(old.renewingDelivery(from: fresh, for: expected, at: now))
        XCTAssertEqual(renewed.id, old.id)
        XCTAssertEqual(renewed.providerName, "CS2", "The selected opaque source label must not be relabelled")
        XCTAssertEqual(renewed.matchID, expected.matchID)
        XCTAssertEqual(renewed.playableURL, fresh.playableURL)
        XCTAssertEqual(renewed.requiredHeaders, fresh.requiredHeaders)
        XCTAssertEqual(renewed.expiryTime, fresh.expiryTime)
        XCTAssertEqual(renewed.leaseID, fresh.leaseID)
        XCTAssertEqual(renewed.qualityLabel, "HD")
        XCTAssertEqual(renewed.eventBinding, current)
        XCTAssertEqual(renewed.createdAt, now)
        XCTAssertEqual(renewed.lastRefreshAt, now)
        XCTAssertEqual(old.playableURL.absoluteString, "https://media.example/old.m3u8",
            "Renewing a value must not mutate another attempt's captured session")
    }

    func testRenewalCannotCarryAnOldTransportGrantToTheFreshDelivery() throws {
        let expected = request(), now = kickoff.addingTimeInterval(10)
        let manifest = URL(string: "https://nuviosports.xyz/manifest.json")!
        let oldHeaders = ["Referer": "https://embed.example/player", "Origin": "https://embed.example",
                          "User-Agent": "Fixture Player"]
        var oldComponents = URLComponents(string: "https://nuviosports.xyz/api/manifest")!
        oldComponents.queryItems = [
            URLQueryItem(name: "url", value: "https://643t8a.7odxv0l067ka.net:8443/live/master.m3u8?lease=old"),
            URLQueryItem(name: "referer", value: oldHeaders["Referer"]),
            URLQueryItem(name: "origin", value: oldHeaders["Origin"])]
        let oldURL = try XCTUnwrap(oldComponents.url)
        let oldProfile = try XCTUnwrap(LocalStreamProxyOriginProfile.communitySports(deliveryURL: oldURL,
            manifestURL: manifest, sourceHint: "daddylive", headers: oldHeaders))
        let old = StreamSession(matchID: expected.matchID, playableURL: oldURL, streamType: .hls,
            providerName: "CS1", requiredHeaders: oldHeaders, canRefresh: true, createdAt: kickoff,
            nativeOriginProfile: oldProfile, eventBinding: try XCTUnwrap(binding(for: expected)))
        XCTAssertEqual(old.nativeOriginProfile, oldProfile)

        let freshHeaders = ["Referer": "https://embed.st/", "Origin": "https://embed.st",
                            "User-Agent": "Fresh Fixture Player"]
        var freshComponents = URLComponents(string: "https://nuviosports.xyz/api/manifest.m3u8")!
        freshComponents.queryItems = [
            URLQueryItem(name: "url", value: "https://lb1.strmd.st/live/variant.m3u8?lease=fresh"),
            URLQueryItem(name: "referer", value: freshHeaders["Referer"]),
            URLQueryItem(name: "origin", value: freshHeaders["Origin"])]
        let freshURL = try XCTUnwrap(freshComponents.url)
        let freshProfile = try XCTUnwrap(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: freshURL,
            manifestURL: manifest, sourceHint: "streamedpk", headers: freshHeaders))
        let fresh = StreamSession(matchID: expected.matchID, playableURL: freshURL, streamType: .hls,
            providerName: "CS1", requiredHeaders: freshHeaders, canRefresh: true, createdAt: now,
            nativePlaylistProfile: freshProfile, requiresGuardedRelay: true,
            eventBinding: try XCTUnwrap(renewalBinding(for: expected, at: now)))
        let renewed = try XCTUnwrap(old.renewingDelivery(from: fresh, for: expected, at: now))
        XCTAssertNil(renewed.nativeOriginProfile, "The prior exceptional-port grant must not transfer")
        XCTAssertEqual(renewed.nativePlaylistProfile, freshProfile)
        XCTAssertEqual(renewed.requiredHeaders, freshHeaders)
        XCTAssertTrue(renewed.requiresGuardedRelay == true)

        var renewedOriginComponents = oldComponents
        renewedOriginComponents.queryItems?[0] = URLQueryItem(name: "url",
            value: "https://643t8a.7odxv0l067ka.net:8443/live/master.m3u8?lease=fresh")
        let renewedOriginURL = try XCTUnwrap(renewedOriginComponents.url)
        let renewedOriginProfile = try XCTUnwrap(LocalStreamProxyOriginProfile.communitySports(
            deliveryURL: renewedOriginURL, manifestURL: manifest, sourceHint: "daddylive", headers: oldHeaders))
        XCTAssertNotEqual(renewedOriginProfile, oldProfile)
        let originSession = StreamSession(matchID: expected.matchID, playableURL: renewedOriginURL,
            streamType: .hls, providerName: "CS1", requiredHeaders: oldHeaders, canRefresh: true,
            createdAt: now, nativeOriginProfile: renewedOriginProfile,
            eventBinding: try XCTUnwrap(renewalBinding(for: expected, at: now)))
        let freshOrigin = try XCTUnwrap(renewed.renewingDelivery(from: originSession, for: expected, at: now))
        XCTAssertEqual(freshOrigin.nativeOriginProfile, renewedOriginProfile)
        XCTAssertNil(freshOrigin.nativePlaylistProfile)

        let ordinary = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/ordinary.m3u8")!, streamType: .hls,
            providerName: "CS1", canRefresh: true, createdAt: now,
            eventBinding: try XCTUnwrap(renewalBinding(for: expected, at: now)))
        let unprivileged = try XCTUnwrap(freshOrigin.renewingDelivery(from: ordinary, for: expected, at: now))
        XCTAssertNil(unprivileged.nativeOriginProfile)
        XCTAssertNil(unprivileged.nativePlaylistProfile, "Fresh metadata without a grant cannot inherit its predecessor's")
        XCTAssertFalse(unprivileged.requiresGuardedRelay == true)
    }

    func testRenewalRejectsDifferentProviderEventStreamDateAndSquad() throws {
        let expected = request(), now = kickoff.addingTimeInterval(10)
        let old = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/old.m3u8")!, streamType: .hls,
            providerName: "CS1", canRefresh: true, createdAt: kickoff,
            eventBinding: try XCTUnwrap(binding(for: expected)))
        let rescheduled = StreamPlaybackRequest(matchID: expected.matchID, displayTitle: expected.displayTitle,
            homeTeam: expected.homeTeam, awayTeam: expected.awayTeam, category: expected.category,
            kickoffDate: kickoff.addingTimeInterval(60))
        let changes: [(StreamPlaybackRequest, String, String, String, String)] = [
            (expected, "plaviosports", "AS1", "nuvio_sport_fixture", "nuvio_sport_fixture"),
            (expected, "communitysports", "CS1", "nuvio_sport_other", "nuvio_sport_fixture"),
            (expected, "communitysports", "CS1", "nuvio_sport_fixture", "nuvio_sport_other"),
            (request(id: "other-fixture"), "communitysports", "CS1", "nuvio_sport_fixture", "nuvio_sport_fixture"),
            (rescheduled, "communitysports", "CS1", "nuvio_sport_fixture", "nuvio_sport_fixture"),
            (request(home: "Ipswich Town Women", away: "Liverpool Women"), "communitysports", "CS1",
             "nuvio_sport_fixture", "nuvio_sport_fixture")
        ]
        for (changed, provider, name, eventID, streamID) in changes {
            let nextBinding = try XCTUnwrap(renewalBinding(for: changed, providerCode: provider,
                providerEventID: eventID, streamID: streamID, at: now))
            let fresh = StreamSession(matchID: changed.matchID,
                playableURL: URL(string: "https://media.example/fresh.m3u8")!, streamType: .hls,
                providerName: name, canRefresh: true, createdAt: now, eventBinding: nextBinding)
            XCTAssertNil(old.renewingDelivery(from: fresh, for: expected, at: now),
                "Renewal must reject changed identity: \(provider), \(eventID), \(streamID), \(changed.displayTitle)")
        }
    }

    func testRenewalRejectsEndpointChangeMissingBindingAndExpiredFreshLease() throws {
        let expected = request(), now = kickoff.addingTimeInterval(10)
        let old = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/old.m3u8")!, streamType: .hls,
            providerName: "CS1", canRefresh: true, createdAt: kickoff,
            eventBinding: try XCTUnwrap(binding(for: expected)))
        let nextBinding = try XCTUnwrap(renewalBinding(for: expected, at: now))
        let web = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://player.example/embed/fresh")!, streamType: .unknown,
            providerName: "CS1", canRefresh: true, createdAt: now, eventBinding: nextBinding)
        XCTAssertNil(old.renewingDelivery(from: web, for: expected, at: now))
        let unbound = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/fresh.m3u8")!, streamType: .hls,
            providerName: "CS1", canRefresh: true, createdAt: now)
        XCTAssertNil(old.renewingDelivery(from: unbound, for: expected, at: now))
        let expiredLease = StreamSession(matchID: expected.matchID,
            playableURL: URL(string: "https://media.example/expired.m3u8")!, streamType: .hls,
            providerName: "CS1", expiryTime: now.addingTimeInterval(-1), canRefresh: true,
            createdAt: now, eventBinding: nextBinding)
        XCTAssertNil(old.renewingDelivery(from: expiredLease, for: expected, at: now),
            "A fresh fixture binding cannot revive an explicitly expired media lease")
    }

    func testSignedDeliveryTokenRotationDoesNotChangeTheSelectedDescriptorChoice() {
        func choice(_ url: String, key: String, scope: String = "delivery", name: String = "AS1") -> StreamSession {
            StreamSession(matchID: "fixture", playableURL: URL(string: url)!, streamType: .hls,
                providerName: name, qualityLabel: "HD",
                diagnosticMetadata: ["source_key": key, "source_key_scope": scope])
        }
        let old = choice("https://media.example/live/game.m3u8?ft=expired", key: "old-hash")
        let fresh = choice("https://media.example/live/game.m3u8?ft=renewed", key: "new-hash")
        XCTAssertTrue(LiveStreamResolver.isSameDescriptorChoice(fresh, as: old))
        XCTAssertFalse(LiveStreamResolver.isSameDescriptorChoice(
            choice("https://media.example/live/another-game.m3u8?ft=renewed", key: "new-hash"), as: old))
        XCTAssertFalse(LiveStreamResolver.isSameDescriptorChoice(
            choice("https://other.example/live/game.m3u8?ft=renewed", key: "new-hash"), as: old))
        let upstream = choice("https://media.example/api/manifest?source=one", key: "one", scope: "upstream", name: "CS1")
        XCTAssertTrue(LiveStreamResolver.isSameDescriptorChoice(
            choice("https://media.example/api/manifest.m3u8?source=one", key: "one", scope: "upstream", name: "CS1"), as: upstream))
        XCTAssertFalse(LiveStreamResolver.isSameDescriptorChoice(
            choice("https://media.example/api/manifest?source=two", key: "two", scope: "upstream", name: "CS1"), as: upstream))
    }

    func testFlixRenewalChoiceKeepsChannelPathProviderLabelAndBindingIdentity() throws {
        let expected = request(), now = kickoff.addingTimeInterval(10)
        let oldBinding = try XCTUnwrap(binding(for: expected, providerCode: "flixstreams",
            providerEventID: "dlstreams:event:aaaaaaaaaaaa", streamID: "dlstreams:event:aaaaaaaaaaaa"))
        let prefix = "https://free.flixnest.app/dlstreams/stream/dlstreams%3Achannel%3A"
        func choice(_ channel: String = "870", token: String, label: String = "FS1",
                    bound: StreamEventBinding? = nil) -> StreamSession {
            StreamSession(matchID: expected.matchID, playableURL: URL(string: prefix + channel + ".m3u8?t=" + token)!,
                streamType: .hls, providerName: label, qualityLabel: "Live video", createdAt: kickoff,
                eventBinding: bound ?? oldBinding)
        }
        let old = choice(token: "old"), rotated = choice(token: "fresh")
        XCTAssertTrue(LiveStreamResolver.isSameDescriptorChoice(rotated, as: old))
        XCTAssertFalse(LiveStreamResolver.isSameDescriptorChoice(choice("871", token: "fresh"), as: old))
        XCTAssertFalse(LiveStreamResolver.isSameDescriptorChoice(choice(token: "fresh", label: "FS2"), as: old),
            "Response-local label reordering remains fail-closed in this narrow change")
        let wrongIdentity = try XCTUnwrap(renewalBinding(for: expected, providerCode: "flixstreams",
            providerEventID: "dlstreams:event:bbbbbbbbbbbb", streamID: "dlstreams:event:bbbbbbbbbbbb", at: now))
        XCTAssertNil(old.renewingDelivery(from: choice(token: "fresh", bound: wrongIdentity), for: expected, at: now))
    }

    private func registeredOfficialFixture(status: SportsFixtureCatalog.Status = .live, verified: Bool = true,
                                           women: Bool = false, providerAlias: Bool = true) -> EventReference {
        let home = women ? "Chelsea Women" : "Chelsea", away = women ? "Liverpool Women" : "Liverpool"
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:registered", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "\(home) vs \(away)", participants: [.init(id: "home", name: home), .init(id: "away", name: away)],
            squad: .init(gender: women ? .women : .men, ageGroup: "senior"), status: status, observedAt: kickoff, verified: verified,
            providerEventIDs: providerAlias ? ["registered-provider-event"] : nil)
        return .init(id: metadata.fixtureID, title: metadata.title, category: "football", date: Int64(kickoff.timeIntervalSince1970),
            poster: nil, popular: false, teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
            sources: [], sportsFixture: metadata, competitionID: "premier-league")
    }

    private func registeredPrimaryAssociation(for event: EventReference, streamID: String = "registered-provider-event") -> BroadcastRegistryMatch {
        let id = "br:" + String(repeating: "c", count: 64)
        let record = BroadcastRegistrySnapshot.Broadcast(id: id, providerCode: "streamex",
            providerEventID: "registered-provider-event", streamID: streamID, resourceType: "tv", scope: "football", kind: .event,
            sport: "football", title: event.displayTitle, participants: [event.homeName, event.awayName], start: event.kickoffDate,
            observedAt: kickoff, expiresAt: kickoff.addingTimeInterval(600), verification: .dated, issues: [])
        let fingerprint = BroadcastRegistrySnapshot.Fingerprint(fixtureID: event.id, sport: "football", start: event.kickoffDate!,
            participants: [event.homeName, event.awayName], competitionID: event.competitionID, squad: event.sportsFixture?.squad)
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: id, providerCode: "streamex", state: .listed,
            matchMethod: .exact, fixtureFingerprint: fingerprint, expiresAt: kickoff.addingTimeInterval(600))
        let provider = BroadcastRegistrySnapshot.Provider(providerCode: "streamex", scope: "football", status: .available,
            observedAt: kickoff, expiresAt: kickoff.addingTimeInterval(600))
        return .init(broadcast: record, link: link, provider: provider)
    }

    private func renewalBinding(
        for request: StreamPlaybackRequest, providerCode: String = "communitysports",
        providerEventID: String = "nuvio_sport_fixture", streamID: String = "nuvio_sport_fixture", at now: Date
    ) -> StreamEventBinding? {
        StreamEventBinding(request: request, providerCode: providerCode, providerEventID: providerEventID,
            streamID: streamID, manifestRevision: "1.3.0", verifiedAt: now,
            expiresAt: now.addingTimeInterval(90), at: now)
    }

    private func binding(
        for request: StreamPlaybackRequest? = nil, providerCode: String = "communitysports",
        providerEventID: String = "nuvio_sport_fixture", streamID: String = "nuvio_sport_fixture",
        manifestRevision: String = "1.2.0", verifiedAt: Date? = nil, expiresAt: Date? = nil
    ) -> StreamEventBinding? {
        StreamEventBinding(request: request ?? self.request(), providerCode: providerCode,
            providerEventID: providerEventID, streamID: streamID, manifestRevision: manifestRevision,
            verifiedAt: verifiedAt ?? kickoff, expiresAt: expiresAt ?? kickoff.addingTimeInterval(3600), at: kickoff)
    }

    private func select(_ events: [AnalyticalDataEngine.EventReference]) -> AnalyticalDataEngine.EventReference? {
        CatalogPlaybackIdentity.matchingEvent(for: request(), in: events)
    }

    private func request(id: String = "official-fixture", home: String = "Ipswich Town", away: String = "Liverpool",
                         category: String = "football", undated: Bool = false) -> StreamPlaybackRequest {
        StreamPlaybackRequest(matchID: id, displayTitle: "\(home) vs \(away)", homeTeam: home, awayTeam: away,
            category: category, kickoffDate: undated ? nil : kickoff)
    }

    private func event(id: String = "fixture", home: String = "Ipswich Town", away: String = "Liverpool",
                       category: String = "football", date: Date? = nil, undated: Bool = false,
                       title: String? = nil, popular: Bool = false) -> AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(id: id, title: title ?? "\(home) vs \(away)", category: category,
            date: undated ? nil : Int64((date ?? kickoff).timeIntervalSince1970), poster: nil, popular: popular,
            teams: NexusATeams(home: NexusATeam(name: home, badge: nil), away: NexusATeam(name: away, badge: nil)),
            sources: [NexusASource(source: "admin", id: "provider-event")])
    }

    private func candidate(source: String = "admin", number: Int = 1, hd: Bool = true,
                           url: String? = nil, mirror: String = "test") -> AnalyticalDataEngine.StreamCandidate {
        AnalyticalDataEngine.StreamCandidate(sourceCode: source, streamNo: number, language: "English", isHD: hd,
            heatTier: nil, embedURL: url ?? "https://player.example/\(source)/event/\(number)", catalogProvider: mirror)
    }
}
