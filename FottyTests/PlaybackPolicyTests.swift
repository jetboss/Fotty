import XCTest
import JavaScriptCore
import AVFoundation
@testable import Fotty

final class PlaybackPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LiveSourceHealthStore.resetForTesting()
    }

    override func tearDown() {
        LiveSourceHealthStore.resetForTesting()
        super.tearDown()
    }

    func testWebEmbedStartupWindowAllowsSlowProviderNegotiation() {
        XCTAssertGreaterThanOrEqual(LivePlaybackPolicy.webStartupFailureSeconds, 20)
        XCTAssertGreaterThan(
            LivePlaybackPolicy.webStallFailureSeconds,
            LivePlaybackPolicy.webStartupFailureSeconds
        )
        XCTAssertTrue(
            LivePlaybackPolicy.isExplicitProviderRejection(
                "Provider reports this broadcast is unavailable"
            )
        )
        XCTAssertFalse(
            LivePlaybackPolicy.isExplicitProviderRejection(
                "Startup timeout: no decoded video"
            )
        )
    }

    @MainActor
    func testCatalogBroadcastTimingDoesNotLabelUpcomingOrOldListingsLive() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(makeScheduleEvent(id: "future", kickoff: now.addingTimeInterval(60)).broadcastTiming(at: now), .upcoming)
        XCTAssertEqual(makeScheduleEvent(id: "recent", kickoff: now.addingTimeInterval(-3600)).broadcastTiming(at: now), .live)
        XCTAssertEqual(makeScheduleEvent(id: "football-window-ended", kickoff: now.addingTimeInterval(-2 * 3600)).broadcastTiming(at: now), .available)
        XCTAssertEqual(makeScheduleEvent(id: "old", kickoff: now.addingTimeInterval(-5 * 3600)).broadcastTiming(at: now), .available)
        XCTAssertEqual(CatalogBroadcastTiming.upcoming.actionLabel, "Open broadcast")
        XCTAssertEqual(CatalogBroadcastTiming.available.actionLabel, "Open broadcast")
        XCTAssertEqual(CatalogBroadcastTiming.live.actionLabel, "Watch live")
    }

    func testCanonicalFallbackRejectsFamiliesWithoutAMaintainedRouteContract() {
        XCTAssertTrue(AnalyticalDataEngine.supportsCanonicalEmbedFallback(sourceCode: "hotel"))
        XCTAssertTrue(AnalyticalDataEngine.supportsCanonicalEmbedFallback(sourceCode: "delta"))
        XCTAssertFalse(AnalyticalDataEngine.supportsCanonicalEmbedFallback(sourceCode: "echo"))
        XCTAssertFalse(AnalyticalDataEngine.supportsCanonicalEmbedFallback(sourceCode: "admin"))
    }

    func testDeferredOpaqueProviderFailureUsesTruthfulStartupTimeoutBoundary() {
        let deferred = LivePlaybackPolicy.deferredStartupFailureReason(
            "Unknown provider error"
        )

        XCTAssertTrue(deferred.localizedCaseInsensitiveContains("startup timeout"))
        XCTAssertTrue(deferred.contains("20"))
        XCTAssertEqual(
            LivePlaybackFailureKind.classify(
                reason: deferred,
                countsAsStall: false,
                isNetworkReachable: true
            ),
            .startupTimeout
        )

        let explicit = "Provider reports this broadcast is unavailable"
        XCTAssertEqual(
            LivePlaybackPolicy.deferredStartupFailureReason(explicit),
            explicit
        )
    }

    func testWebEmbedMonitorScriptParsesAndContainsBackgroundSuspensionContract() throws {
        let script = LiveWebEmbedPlayerView.playbackMonitorScript(
            isMuted: false,
            providerControlsAudio: true,
            isSuspended: false
        )
        let encoded = try JSONSerialization.data(withJSONObject: script, options: [.fragmentsAllowed])
        let scriptLiteral = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let context = try XCTUnwrap(JSContext())

        context.evaluateScript("new Function(\(scriptLiteral))")

        XCTAssertNil(context.exception, context.exception?.toString() ?? "JavaScript parse failed")
        XCTAssertTrue(script.contains("fotty_set_suspended"))
        XCTAssertTrue(script.contains("media.pause()"))
        XCTAssertTrue(script.contains("within 20 seconds"))
        XCTAssertTrue(script.contains("vpn recommended"))
        XCTAssertTrue(script.contains("continue watching"))
        XCTAssertTrue(script.contains("window.confirm"))
        XCTAssertTrue(script.contains("candidate.querySelector('video, iframe')"))
    }

    @MainActor
    func testCatalogChoicesPreferDistinctBroadcastsAndPreserveProviderDiversity() {
        let admin = [
            makeCandidate(source: "admin", number: 1, language: "English - Sky Sports", hd: true, viewers: 20_000),
            makeCandidate(source: "admin", number: 2, language: "English - Sky Sports", hd: false, viewers: 1_000),
            makeCandidate(source: "admin", number: 3, language: "English - Sky Sport 8", hd: true, viewers: 1_500),
        ]
        let delta = [
            makeCandidate(source: "delta", number: 1, language: "English", hd: true, viewers: 200),
        ]
        let golf = [
            makeCandidate(source: "golf", number: 1, language: "English", hd: true, viewers: 2_500),
        ]

        let selected = AnalyticalDataEngine.curatedPlaybackCandidates(
            from: [admin, delta, golf],
            limit: 4
        )

        XCTAssertEqual(selected.map(\.sourceCode), ["admin", "delta", "golf", "admin"])
        XCTAssertEqual(selected.map(\.streamNo), [1, 1, 1, 3])
        XCTAssertFalse(selected.contains { $0.streamNo == 2 && $0.sourceCode == "admin" })
    }

    @MainActor
    func testCanonicalFallbackCreatesOnlyOneChoiceForMaintainedFamilies() {
        let event = AnalyticalDataEngine.EventReference(
            id: "fixture-1",
            title: "Home vs Away",
            category: "football",
            date: nil,
            poster: nil,
            popular: nil,
            teams: nil,
            sources: [
                NexusASource(source: "admin", id: "event-admin"),
                NexusASource(source: "delta", id: "event-delta"),
            ]
        )

        let fallback = AnalyticalDataEngine.fallbackEmbedSources(for: event)

        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(Set(fallback.compactMap { $0.headers["X-Fotty-Nexus-Source"] }), ["delta"])
        XCTAssertTrue(fallback.allSatisfy { $0.url.path.hasSuffix("/1") })
        XCTAssertFalse(fallback.contains { StreamPluginProviderMatching.isP2PLike($0) })
    }

    @MainActor
    private func makeCandidate(
        source: String,
        number: Int,
        language: String,
        hd: Bool,
        viewers: Int
    ) -> AnalyticalDataEngine.StreamCandidate {
        AnalyticalDataEngine.StreamCandidate(
            sourceCode: source,
            streamNo: number,
            language: language,
            isHD: hd,
            heatTier: nil,
            embedURL: "https://embed.st/embed/\(source)/event/\(number)",
            catalogProvider: "test",
            viewers: viewers
        )
    }

    func testLiveScoreScopeIsPremierLeagueOnlyForNow() {
        XCTAssertEqual(FootballDataPolicy.activeLiveScoreCompetitions, [.premierLeague])
        XCTAssertEqual(FootballDataPolicy.apiFootballLiveFilter, "39")
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-23T12:00:00Z")!
        let query = FootballDataPolicy.apiFootballLiveQuery(at: referenceDate)
        XCTAssertNil(query["live"])
        XCTAssertEqual(query["league"], "39")
        XCTAssertEqual(query["season"], "2026")
        XCTAssertEqual(query["date"], "2026-08-23")
        XCTAssertEqual(FootballDataPolicy.footballDataLiveLeagues, [.premierLeague])
        XCTAssertEqual(
            FootballDataPolicy.plannedLiveScoreCompetitions,
            [.premierLeague, .championsLeague]
        )
    }

    func testAPIFootballLiveStatusesRejectFinishedAndScheduledFixtures() {
        for status in ["1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE"] {
            XCTAssertTrue(FootballDataPolicy.isAPIFootballLiveStatus(status))
        }
        for status in ["NS", "TBD", "FT", "AET", "PEN", "PST", "CANC", "ABD", "AWD", "WO"] {
            XCTAssertFalse(FootballDataPolicy.isAPIFootballLiveStatus(status))
        }
    }

    func testSingleLeagueLiveQueryUsesTheCredentialedWorkerBoundary() {
        let query = FootballDataPolicy.apiFootballLiveQuery(
            at: Date(timeIntervalSince1970: 1_787_500_000)
        )

        XCTAssertNotNil(query["league"])
        XCTAssertNotNil(query["season"])
        XCTAssertNotNil(query["date"])
        XCTAssertTrue(
            APIFootballProvider.shouldUseLiveScoreProxy(
                apiKey: "",
                path: "/fixtures",
                query: query
            )
        )
        XCTAssertFalse(
            APIFootballProvider.shouldUseLiveScoreProxy(
                apiKey: "client-secret-should-not-be-required",
                path: "/fixtures",
                query: query
            )
        )
    }

    func testOnlyExplicitFullMatchHubRefreshAllowsProviderEnrichment() {
        XCTAssertFalse(MatchHubRefreshPolicy.automatic.allowsProviderEnrichment)
        XCTAssertFalse(MatchHubRefreshPolicy.liveScoreOnly.allowsProviderEnrichment)
        XCTAssertTrue(MatchHubRefreshPolicy.full.allowsProviderEnrichment)
    }

    func testFallbackFeedModesAreExplicit() {
        XCTAssertFalse(LiveScoreFeedMode.officialFPL.usesDelayedData)
        XCTAssertEqual(LiveScoreFeedMode.officialFPL.statusQualifier, "Official FPL")
        XCTAssertFalse(LiveScoreFeedMode.live.usesDelayedData)
        XCTAssertTrue(LiveScoreFeedMode.delayedFallback.usesDelayedData)
        XCTAssertTrue(LiveScoreFeedMode.quotaFallback.usesDelayedData)
        XCTAssertTrue(LiveScoreFeedMode.quotaFallback.isQuotaReserved)
        XCTAssertFalse(LiveScoreFeedMode.delayedFallback.isQuotaReserved)
    }

    func testTeamMatchingNormalizesCrossProviderClubAliases() {
        let aliases = [
            ("Man City", "Manchester City FC"),
            ("Man Utd", "Manchester United FC"),
            ("Spurs", "Tottenham Hotspur FC"),
            ("Nott'm Forest", "Nottingham Forest FC"),
            ("Brighton", "Brighton & Hove Albion FC"),
            ("Coventry", "Coventry City FC"),
            ("Hull", "Hull City AFC"),
            ("West Ham", "West Ham United FC"),
            ("Wolves", "Wolverhampton Wanderers FC"),
        ]
        for (fpl, schedule) in aliases {
            XCTAssertEqual(
                FootballDataPolicy.normalizedTeamMatchKey(fpl),
                FootballDataPolicy.normalizedTeamMatchKey(schedule)
            )
        }
    }

    func testPremierLeagueCatalogMatchesOfficial2026SeasonMembership() {
        XCTAssertEqual(PremierLeagueClubCatalog.seasonLabel, "2026/27")
        XCTAssertEqual(Set(PremierLeagueClubCatalog.officialClubNames), [
            "AFC Bournemouth", "Arsenal", "Aston Villa", "Brentford",
            "Brighton & Hove Albion", "Chelsea", "Coventry City", "Crystal Palace",
            "Everton", "Fulham", "Hull City", "Ipswich Town", "Leeds United",
            "Liverpool", "Manchester City", "Manchester United", "Newcastle United",
            "Nottingham Forest", "Sunderland", "Tottenham Hotspur",
        ])
        XCTAssertEqual(PremierLeagueClubCatalog.officialClubNames.count, 20)
        XCTAssertTrue(PremierLeagueClubCatalog.contains("Coventry City FC"))
        XCTAssertTrue(PremierLeagueClubCatalog.contains("Spurs"))
        XCTAssertEqual(PremierLeagueClubCatalog.officialName(for: "Spurs"), "Tottenham Hotspur")
        XCTAssertFalse(PremierLeagueClubCatalog.contains("Norwich City"))
        XCTAssertNil(PremierLeagueClubCatalog.officialName(for: "Norwich City"))
        XCTAssertFalse(PremierLeagueClubCatalog.contains("West Ham United"))
        XCTAssertFalse(PremierLeagueClubCatalog.contains("Arsenal U21"))
    }

    func testPremierLeagueNewsInferenceUsesTheSameCurrentCatalog() {
        XCTAssertTrue(TeamNewsService.inferLeagueTopics(for: ["Coventry City"]).contains("Premier League"))
        XCTAssertFalse(TeamNewsService.inferLeagueTopics(for: ["Norwich City"]).contains("Premier League"))
        XCTAssertFalse(TeamNewsService.inferLeagueTopics(for: ["West Ham United"]).contains("Premier League"))
    }

    func testSeasonCatalogCoversEveryManagedCompetitionAndExpiresClosed() {
        let expectedCounts: [FootballCompetitionID: Int] = [
            .premierLeague: 20,
            .laLiga: 20,
            .serieA: 20,
            .bundesliga: 18,
            .ligue1: 18,
            .championsLeague: 36,
            .europaLeague: 36,
        ]
        XCTAssertEqual(Set(FootballCompetitionCatalog.snapshots.keys), Set(FootballCompetitionID.allCases))
        for (competition, expectedCount) in expectedCounts {
            let snapshot = FootballCompetitionCatalog.snapshot(competition)
            XCTAssertEqual(snapshot.expectedClubCount, expectedCount)
            XCTAssertEqual(snapshot.clubs.count, expectedCount)
            XCTAssertEqual(Set(snapshot.officialClubNames.map { $0.lowercased() }).count, expectedCount)
        }
        XCTAssertTrue(FootballCompetitionCatalog.isFresh(at: FootballCompetitionCatalog.validThrough))
        XCTAssertFalse(FootballCompetitionCatalog.isFresh(at: FootballCompetitionCatalog.validThrough.addingTimeInterval(1)))
        let providerBootstrap = FootballCompetitionCatalog.providerBootstrap()
        XCTAssertEqual(providerBootstrap["Champions League"]?.count, 36)
        XCTAssertEqual(providerBootstrap["UEFA Champions League"]?.count, 36)
        XCTAssertEqual(providerBootstrap["Europa League"]?.count, 36)
    }

    func testOtherDomesticCatalogsUseCurrentSeasonReplacements() {
        let examples: [(FootballCompetitionID, current: String, old: String)] = [
            (.laLiga, "Málaga CF", "Girona"),
            (.serieA, "Frosinone", "Empoli"),
            (.bundesliga, "Schalke 04", "Wolfsburg"),
            (.ligue1, "Troyes", "Nantes"),
        ]
        for example in examples {
            XCTAssertTrue(FootballCompetitionCatalog.contains(example.current, in: example.0))
            XCTAssertFalse(FootballCompetitionCatalog.contains(example.old, in: example.0))
        }
        XCTAssertTrue(TeamNewsService.inferLeagueTopics(for: ["Málaga CF"]).contains("La Liga"))
        XCTAssertFalse(TeamNewsService.inferLeagueTopics(for: ["Girona"]).contains("La Liga"))
    }

    func testFixtureWindowNeverWidensWhenTheRequestedRangeIsEmpty() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let range = start...start.addingTimeInterval(3_600)
        let values = [
            start.addingTimeInterval(-60),
            start,
            start.addingTimeInterval(1_800),
            start.addingTimeInterval(3_600),
            start.addingTimeInterval(3_601),
        ]
        XCTAssertEqual(
            FootballFixtureWindowPolicy.filter(values, dateRange: range, kickoff: { $0 }),
            Array(values[1...3])
        )
        XCTAssertTrue(
            FootballFixtureWindowPolicy.filter(
                [start.addingTimeInterval(-86_400)],
                dateRange: range,
                kickoff: { $0 }
            ).isEmpty
        )
    }

    @MainActor
    func testSportsAndLeagueVocabularyAlwaysUsesRealProductNames() {
        XCTAssertEqual(AnalyticalDataEngine.categoryDisplayName(for: "football"), "Football")
        XCTAssertEqual(AnalyticalDataEngine.categoryDisplayName(for: "basketball"), "Basketball")
        XCTAssertEqual(AnalyticalDataEngine.categoryDisplayName(for: "cricket"), "Cricket")
        XCTAssertEqual(AnalyticalDataEngine.FootballLeagueTab.premierLeague.displayName, "Premier League")
        XCTAssertEqual(AnalyticalDataEngine.FootballLeagueTab.championsLeague.displayName, "Champions League")
    }

    @MainActor
    func testPremierLeagueFilterRequiresTwoCurrentSeniorClubs() {
        XCTAssertEqual(
            AnalyticalDataEngine.footballLeagueTab(for: makeLeagueEvent(
                id: "coventry-arsenal", title: "Coventry City vs Arsenal",
                home: "Coventry City", away: "Arsenal"
            )),
            .premierLeague
        )
        XCTAssertEqual(
            AnalyticalDataEngine.footballLeagueTab(for: makeLeagueEvent(
                id: "norwich-leeds", title: "Norwich City vs Leeds United",
                home: "Norwich City", away: "Leeds United"
            )),
            .other
        )
        XCTAssertEqual(
            AnalyticalDataEngine.footballLeagueTab(for: makeLeagueEvent(
                id: "english-premier-league-norwich-leeds",
                title: "English Premier League · Norwich City vs Leeds United",
                home: "Norwich City", away: "Leeds United"
            )),
            .other,
            "A provider label cannot override a conflict with current club membership"
        )
        XCTAssertEqual(
            AnalyticalDataEngine.footballLeagueTab(for: makeLeagueEvent(
                id: "fa-cup-arsenal-chelsea", title: "FA Cup · Arsenal vs Chelsea",
                home: "Arsenal", away: "Chelsea"
            )),
            .other,
            "Two Premier League clubs can meet outside the Premier League"
        )
        XCTAssertEqual(
            AnalyticalDataEngine.footballLeagueTab(for: makeLeagueEvent(
                id: "ucl-arsenal-chelsea", title: "UEFA Champions League · Arsenal vs Chelsea",
                home: "Arsenal", away: "Chelsea"
            )),
            .championsLeague
        )
    }

    @MainActor
    func testSharedProviderFootballIdentityVectorsMatchIOSClassifier() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vectorsURL = repositoryRoot
            .appendingPathComponent("shared/reference-data/provider-football-identity-vectors.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: vectorsURL))
        let root = try XCTUnwrap(object as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])

        for vector in cases {
            let name = try XCTUnwrap(vector["name"] as? String)
            let event = try XCTUnwrap(vector["event"] as? [String: Any])
            let teams = try XCTUnwrap(event["teams"] as? [String: Any])
            let home = try XCTUnwrap((teams["home"] as? [String: Any])?["name"] as? String)
            let away = try XCTUnwrap((teams["away"] as? [String: Any])?["name"] as? String)
            let sourceIDs = event["sourceIds"] as? [String] ?? []
            let reference = AnalyticalDataEngine.EventReference(
                id: try XCTUnwrap(event["id"] as? String),
                title: event["title"] as? String,
                category: event["category"] as? String,
                date: nil,
                poster: nil,
                popular: nil,
                teams: NexusATeams(
                    home: NexusATeam(name: home, badge: nil),
                    away: NexusATeam(name: away, badge: nil)
                ),
                sources: sourceIDs.enumerated().map { index, id in
                    NexusASource(source: "vector-\(index)", id: id)
                }
            )
            let classification = AnalyticalDataEngine.footballLeagueClassification(for: reference)
            XCTAssertEqual(classification.tab.rawValue, vector["expectedCompetition"] as? String, name)
            XCTAssertEqual(classification.isIdentityConflict, vector["expectedIdentityConflict"] as? Bool, name)
        }
    }

    @MainActor
    func testKickoffMatchedOfficialFixtureCompetitionOverridesCatalogGuess() {
        let cupLabeledEvent = makeLeagueEvent(
            id: "fa-cup-arsenal-chelsea",
            title: "FA Cup · Arsenal vs Chelsea",
            home: "Arsenal",
            away: "Chelsea"
        )
        let officialPremierLeagueMatch = FootballMatch(
            id: 42,
            apiFootballFixtureId: nil,
            utcDate: "2026-08-30T13:00:00Z",
            status: .timed,
            matchday: 3,
            stage: nil,
            group: nil,
            homeTeam: FootballTeam(id: 1, name: "Arsenal", shortName: nil, tla: nil, crest: nil),
            awayTeam: FootballTeam(id: 2, name: "Chelsea", shortName: nil, tla: nil, crest: nil),
            score: MatchScore(winner: nil, duration: "REGULAR", fullTime: nil, halfTime: nil),
            competition: MatchCompetition(
                id: 2021,
                name: "Premier League",
                code: "PL",
                emblem: nil,
                country: "England"
            ),
            referees: nil,
            events: nil
        )

        XCTAssertEqual(AnalyticalDataEngine.footballLeagueTab(for: cupLabeledEvent), .other)
        XCTAssertEqual(
            AnalyticalDataEngine.footballLeagueTab(
                for: cupLabeledEvent,
                officialMatch: officialPremierLeagueMatch
            ),
            .premierLeague
        )
    }

    @MainActor
    func testDomesticLeagueFiltersRejectPriorSeasonMembershipDespiteProviderLabel() {
        let examples: [(title: String, home: String, away: String, expected: AnalyticalDataEngine.FootballLeagueTab)] = [
            ("La Liga · Málaga vs Real Madrid", "Málaga CF", "Real Madrid", .laLiga),
            ("La Liga · Girona vs Real Madrid", "Girona", "Real Madrid", .other),
            ("Serie A · Frosinone vs Juventus", "Frosinone", "Juventus", .serieA),
            ("Serie A · Empoli vs Juventus", "Empoli", "Juventus", .other),
            ("Bundesliga · Schalke vs Bayern", "Schalke 04", "Bayern Munich", .bundesliga),
            ("Bundesliga · Wolfsburg vs Bayern", "Wolfsburg", "Bayern Munich", .other),
            ("Ligue 1 · Troyes vs PSG", "Troyes", "PSG", .ligue1),
            ("Ligue 1 · Nantes vs PSG", "Nantes", "PSG", .other),
        ]
        for (index, example) in examples.enumerated() {
            XCTAssertEqual(
                AnalyticalDataEngine.footballLeagueTab(for: makeLeagueEvent(
                    id: "domestic-\(index)",
                    title: example.title,
                    home: example.home,
                    away: example.away
                )),
                example.expected,
                example.title
            )
        }
    }

    @MainActor
    private func makeLeagueEvent(
        id: String,
        title: String,
        home: String,
        away: String
    ) -> AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(
            id: id,
            title: title,
            category: "football",
            date: nil,
            poster: nil,
            popular: nil,
            teams: NexusATeams(
                home: NexusATeam(name: home, badge: nil),
                away: NexusATeam(name: away, badge: nil)
            ),
            sources: []
        )
    }

    func testCanonicalFixtureIdentityIsIndependentOfDeviceTimeZone() {
        let kickoff = Date(timeIntervalSince1970: 1_787_520_600)
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }

        NSTimeZone.default = TimeZone(identifier: "America/Port_of_Spain")!
        let caribbeanKey = FootballDataPolicy.canonicalFixtureMatchKey(
            homeTeam: "Man City",
            awayTeam: "Spurs",
            kickoff: kickoff
        )
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        let tokyoKey = FootballDataPolicy.canonicalFixtureMatchKey(
            homeTeam: "Manchester City FC",
            awayTeam: "Tottenham Hotspur FC",
            kickoff: kickoff
        )

        XCTAssertEqual(caribbeanKey, tokyoKey)
    }

    func testFixtureIdentityPreservesCanonicalAndProviderAliases() {
        let fixture = FottyFixture(
            id: "schedule-42",
            utcDate: Date(timeIntervalSince1970: 1_787_520_600),
            status: .scheduled,
            competition: FottyCompetition(id: "2021", name: "Premier League", country: "England", emblemURL: nil),
            venue: nil,
            matchday: 3,
            apiFootballFixtureId: "98765"
        )

        XCTAssertTrue(fixture.identityAliases.contains("canonical:schedule-42"))
        XCTAssertTrue(fixture.identityAliases.contains("api-football:98765"))
        XCTAssertEqual(fixture.hubFixtureId, "98765")
    }

    func testCatalogRouteIdentityMatchesColdLaunchProviderIDsWithoutFuzzyNames() {
        let eventID = "nottingham-forest-vs-leeds-united-2570504"

        XCTAssertTrue(CatalogRouteIdentity.matches(eventID: eventID, requestedID: eventID))
        XCTAssertTrue(CatalogRouteIdentity.matches(eventID: eventID, requestedID: "catalog:\(eventID)"))
        XCTAssertTrue(CatalogRouteIdentity.matches(eventID: "catalog:\(eventID)", requestedID: eventID))
        XCTAssertTrue(CatalogRouteIdentity.matches(eventID: "Team%20A", requestedID: "team a"))
        XCTAssertFalse(CatalogRouteIdentity.matches(eventID: eventID, requestedID: "another-match-1"))
        XCTAssertFalse(CatalogRouteIdentity.matches(eventID: "", requestedID: ""))
    }

    @MainActor
    func testMatchHubCatalogFallbackRequestCarriesOnlyTheTypedRouteIdentity() {
        let request = MatchHubViewModel.catalogRouteRequest(fixtureID: "catalog-match-42")

        XCTAssertEqual(request.matchID, "catalog-match-42")
        XCTAssertEqual(request.displayTitle, "Live match")
        XCTAssertTrue(request.homeTeam.isEmpty)
        XCTAssertTrue(request.awayTeam.isEmpty)
        XCTAssertTrue(request.category.isEmpty)
        XCTAssertNil(request.kickoffDate)
        XCTAssertNil(request.preferredEvent)
    }

    @MainActor
    func testCanonicalIdentitySurvivesCatalogScoreFPLNotificationAndPlaybackBoundaries() {
        let kickoff = Date(timeIntervalSince1970: 1_787_520_600)
        let identity = FottyFixtureIdentity(
            canonicalID: "42",
            matchKey: FootballDataPolicy.canonicalFixtureMatchKey(
                homeTeam: "Manchester City FC",
                awayTeam: "Tottenham Hotspur FC",
                kickoff: kickoff
            ),
            providerAliases: [
                "canonical:42",
                "catalog:stream-match-42",
                "api-football:98765",
                "official-fpl:314"
            ]
        )

        XCTAssertTrue(identity.resolves("42"))
        XCTAssertTrue(identity.resolves("canonical:42"))
        XCTAssertTrue(identity.resolves("stream-match-42"))
        XCTAssertTrue(identity.resolves("api-football:98765"))
        XCTAssertTrue(identity.resolves("314"))
        XCTAssertTrue(identity.matches(homeTeam: "Man City", awayTeam: "Spurs", kickoff: kickoff))

        let match = FootballMatch(
            id: 42,
            apiFootballFixtureId: 98_765,
            utcDate: ISO8601DateFormatter().string(from: kickoff),
            status: .inPlay,
            matchday: 3,
            stage: nil,
            group: nil,
            homeTeam: FootballTeam(id: 1, name: "Manchester City FC", shortName: "Man City", tla: "MCI", crest: nil),
            awayTeam: FootballTeam(id: 2, name: "Tottenham Hotspur FC", shortName: "Spurs", tla: "TOT", crest: nil),
            score: MatchScore(winner: nil, duration: nil, fullTime: ScoreDetail(home: 1, away: 0), halfTime: nil),
            competition: MatchCompetition(id: 2021, name: "Premier League", code: "PL", emblem: nil, country: "England"),
            referees: nil,
            events: nil
        )
        let catalogFallback = AnalyticalDataEngine.EventReference(from: match)
        XCTAssertEqual(catalogFallback.id, identity.routeID)

        let playback = StreamPlaybackRequest(
            matchID: identity.routeID,
            displayTitle: "Man City vs Spurs",
            homeTeam: "Man City",
            awayTeam: "Spurs",
            category: "football",
            kickoffDate: kickoff,
            preferredEvent: catalogFallback
        )
        XCTAssertEqual(playback.matchID, identity.routeID)

        MatchNavigationStore.shared.open(matchID: identity.routeID)
        XCTAssertEqual(MatchNavigationStore.shared.pendingMatchID, identity.routeID)
        MatchNavigationStore.shared.pendingMatchID = nil
    }

    func testOfficialFPLMapperIncludesOnlyActivelyPlayingFixture() throws {
        let fixtureJSON = """
        [
          {"id":1,"event":2,"kickoff_time":"2026-08-23T15:00:00Z","team_h":1,"team_a":2,"team_h_score":2,"team_a_score":1,"team_h_difficulty":3,"team_a_difficulty":4,"finished":false,"started":true,"finished_provisional":false,"minutes":67},
          {"id":2,"event":2,"kickoff_time":"2026-08-23T17:00:00Z","team_h":1,"team_a":2,"team_h_score":0,"team_a_score":0,"team_h_difficulty":3,"team_a_difficulty":4,"finished":false,"started":false,"finished_provisional":false,"minutes":0},
          {"id":3,"event":2,"kickoff_time":"2026-08-23T12:00:00Z","team_h":1,"team_a":2,"team_h_score":1,"team_a_score":1,"team_h_difficulty":3,"team_a_difficulty":4,"finished":false,"started":true,"finished_provisional":true,"minutes":90}
        ]
        """
        let teamsJSON = """
        [
          {"id":1,"name":"Man City","short_name":"MCI","code":43,"strength":5,"strength_overall_home":5,"strength_overall_away":5,"strength_attack_home":5,"strength_attack_away":5,"strength_defence_home":5,"strength_defence_away":5},
          {"id":2,"name":"Spurs","short_name":"TOT","code":6,"strength":4,"strength_overall_home":4,"strength_overall_away":4,"strength_attack_home":4,"strength_attack_away":4,"strength_defence_home":4,"strength_defence_away":4}
        ]
        """
        let fixtures = try JSONDecoder().decode([FPLFixture].self, from: Data(fixtureJSON.utf8))
        let teams = try JSONDecoder().decode([FPLTeam].self, from: Data(teamsJSON.utf8))
        let fetchedAt = Date(timeIntervalSince1970: 1_787_500_000)

        let mapped = OfficialFPLScoreProvider.mapLiveFixtures(
            fixtures,
            teams: teams,
            fetchedAt: fetchedAt
        )

        let match = try XCTUnwrap(mapped.first)
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(match.fixture.id, "900000001")
        XCTAssertEqual(match.fixture.competition.id, "39")
        XCTAssertEqual(match.fixture.elapsedMinutes, 67)
        XCTAssertEqual(match.score.home, 2)
        XCTAssertEqual(match.score.away, 1)
        XCTAssertEqual(match.dataQuality, .official)
        XCTAssertEqual(match.lastUpdated, fetchedAt)
    }

    func testLiveScoreScopeRecognizesBothProviderIdsForPremierLeague() {
        XCTAssertTrue(
            FootballDataPolicy.supportsLiveScores(
                competitionId: 39,
                competitionName: "Premier League",
                country: "England"
            )
        )
        XCTAssertTrue(
            FootballDataPolicy.supportsLiveScores(
                competitionId: 2021,
                competitionName: "Premier League",
                competitionCode: "PL",
                country: "England"
            )
        )
    }

    func testLiveScoreScopeRejectsChampionsLeagueAndOtherPremierLeagues() {
        XCTAssertFalse(
            FootballDataPolicy.supportsLiveScores(
                competitionId: 2,
                competitionName: "UEFA Champions League"
            )
        )
        XCTAssertFalse(
            FootballDataPolicy.supportsLiveScores(
                competitionId: 501,
                competitionName: "Premier League",
                country: "Scotland"
            )
        )
        XCTAssertFalse(
            FootballDataPolicy.supportsLiveScores(
                competitionId: nil,
                competitionName: "Premier League 2",
                country: "England"
            )
        )
        XCTAssertFalse(
            FootballDataPolicy.supportsLiveScores(
                competitionId: nil,
                competitionName: "Premier League Cup",
                country: "England"
            )
        )
        XCTAssertTrue(
            FootballDataPolicy.supportsLiveScores(
                competitionId: nil,
                competitionName: "English Premier League",
                country: "England"
            )
        )
    }

    func testMissingScoreNoticeRequiresConfirmedCoveredFixture() {
        let premierLeague = MatchCompetition(
            id: 39,
            name: "Premier League",
            code: "PL",
            emblem: nil,
            country: "England",
        )
        let premierLeagueTwo = MatchCompetition(
            id: nil,
            name: "Premier League 2",
            code: nil,
            emblem: nil,
            country: "England",
        )

        XCTAssertTrue(
            FootballDataPolicy.hasConfirmedLiveScoreCoverage(competition: premierLeague)
        )
        XCTAssertFalse(
            FootballDataPolicy.hasConfirmedLiveScoreCoverage(competition: premierLeagueTwo)
        )
        XCTAssertFalse(
            FootballDataPolicy.hasConfirmedLiveScoreCoverage(competition: nil)
        )
    }

    func testLiveScorePollingRunsOnlyInsidePremierLeagueMatchWindow() {
        let now = Date(timeIntervalSince1970: 1_787_500_000)
        let premierLeague = FottyCompetition(
            id: "39",
            name: "Premier League",
            country: "England",
            emblemURL: nil
        )
        let championsLeague = FottyCompetition(
            id: "2",
            name: "UEFA Champions League",
            country: nil,
            emblemURL: nil
        )

        XCTAssertTrue(
            FootballDataPolicy.shouldPollLiveScores(
                fixtures: [makeFixture(competition: premierLeague, kickoff: now, status: .live)],
                at: now
            )
        )
        XCTAssertTrue(
            FootballDataPolicy.shouldPollLiveScores(
                fixtures: [
                    makeFixture(
                        competition: premierLeague,
                        kickoff: now.addingTimeInterval(4 * 60),
                        status: .scheduled
                    )
                ],
                at: now
            )
        )
        XCTAssertFalse(
            FootballDataPolicy.shouldPollLiveScores(
                fixtures: [makeFixture(competition: championsLeague, kickoff: now, status: .live)],
                at: now
            )
        )
        XCTAssertFalse(
            FootballDataPolicy.shouldPollLiveScores(
                fixtures: [
                    makeFixture(
                        competition: premierLeague,
                        kickoff: now.addingTimeInterval(2 * 60 * 60),
                        status: .scheduled
                    )
                ],
                at: now
            )
        )
    }

    private func makeFixture(
        competition: FottyCompetition,
        kickoff: Date,
        status: FottyMatchStatus
    ) -> FottyFixture {
        FottyFixture(
            id: UUID().uuidString,
            utcDate: kickoff,
            status: status,
            competition: competition,
            venue: nil,
            matchday: nil
        )
    }

    func testReachableStartupTimeoutIsNotReportedAsNetworkLoss() {
        let kind = LivePlaybackFailureKind.classify(
            reason: "Source timed out before the first frame",
            countsAsStall: false,
            isNetworkReachable: true
        )

        XCTAssertEqual(kind, .startupTimeout)
    }

    func testOfflineStateWinsOverPlaybackReason() {
        let kind = LivePlaybackFailureKind.classify(
            reason: "Source failed to start",
            countsAsStall: false,
            isNetworkReachable: false
        )

        XCTAssertEqual(kind, .network)
    }

    func testExplicitStallIsClassifiedAsStall() {
        let kind = LivePlaybackFailureKind.classify(
            reason: "Playback stopped advancing",
            countsAsStall: true,
            isNetworkReachable: true
        )

        XCTAssertEqual(kind, .stalled)
    }

    func testExplicitProviderRejectionHasTruthfulFailureBoundary() {
        let kind = LivePlaybackFailureKind.classify(
            reason: "Broadcast is unavailable",
            countsAsStall: false,
            isNetworkReachable: true
        )

        XCTAssertEqual(kind, .providerUnavailable)
        XCTAssertEqual(kind.title, "Broadcast Unavailable")
        XCTAssertTrue(kind.terminalMessage.localizedCaseInsensitiveContains("provider"))
        XCTAssertFalse(kind.terminalMessage.localizedCaseInsensitiveContains("internet"))
    }

    func testPlayerProviderAllowlistHonorsEnabledModules() {
        XCTAssertEqual(
            StreamPluginProviderMatching.allowedPlayerProviderCodes(
                enabledCodes: ["SCORE808", "retired-provider"]
            ),
            ["score808"]
        )
    }

    func testP2PShapeNeverPassesActivePlayerFilter() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://example.com/proxy/acestream/channel.m3u8")),
            quality: "HD",
            provider: "Score808"
        )

        XCTAssertFalse(StreamPluginProviderMatching.isActivePlayerSource(source))
    }

    func testCatalogSourceFamiliesMatchActivePlaybackModules() {
        XCTAssertEqual(
            StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: "admin"),
            "streamex"
        )
        XCTAssertEqual(
            StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: "hotel"),
            "score808"
        )
        XCTAssertEqual(
            StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: "echo"),
            "streamex"
        )
        XCTAssertEqual(
            StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: "india"),
            "streamex"
        )
    }

    func testCircuitBreakerSkipsFamilyAfterTwoConsecutiveFailures() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://embed.st/embed/delta/example/1")),
            quality: "live",
            provider: "StreamEx #1",
            headers: ["X-Fotty-Nexus-Source": "delta"]
        )

        LiveSourceHealthStore.recordFailure(for: source, wasStall: false, reason: "HTTP 403")
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))

        LiveSourceHealthStore.recordFailure(for: source, wasStall: false, reason: "HTTP 403")
        XCTAssertTrue(LiveSourceHealthStore.isTemporarilyUnavailable(source))
        XCTAssertTrue(LiveSourceHealthStore.automaticCandidates(in: [source]).isEmpty)
    }

    func testDecodedPlaybackSuccessClosesProviderCircuit() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://embed.st/embed/admin/example/1")),
            quality: "live",
            provider: "StreamEx #1",
            headers: ["X-Fotty-Nexus-Source": "admin"]
        )

        LiveSourceHealthStore.recordFailure(for: source, wasStall: false)
        LiveSourceHealthStore.recordFailure(for: source, wasStall: false)
        XCTAssertTrue(LiveSourceHealthStore.isTemporarilyUnavailable(source))

        LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: 4_200)
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "admin"))
        XCTAssertEqual(LiveSourceHealthStore.automaticCandidates(in: [source]).first?.id, source.id)
    }

    func testWebPlaybackRecoveryWindowIsBoundedButNotEager() {
        XCTAssertGreaterThanOrEqual(LivePlaybackPolicy.webStallFailureSeconds, 30)
        XCTAssertGreaterThanOrEqual(LivePlaybackPolicy.webRecoveryGraceSeconds, 5)
        XCTAssertLessThanOrEqual(
            LivePlaybackPolicy.webStallFailureSeconds + LivePlaybackPolicy.webRecoveryGraceSeconds,
            45
        )
    }

    func testUnifiedPlaybackStateDerivesLoadingAndPlayingWithoutContradictions() {
        XCTAssertFalse(LivePlaybackState.idle.isLoading)
        XCTAssertFalse(LivePlaybackState.idle.isPlaying)
        XCTAssertTrue(LivePlaybackState.connecting(.webEmbed).isLoading)
        XCTAssertFalse(LivePlaybackState.connecting(.webEmbed).isPlaying)
        XCTAssertFalse(LivePlaybackState.playing(.webEmbed).isLoading)
        XCTAssertTrue(LivePlaybackState.playing(.webEmbed).isPlaying)
        XCTAssertFalse(LivePlaybackState.preparingNativeHandoff.isLoading)
        XCTAssertTrue(LivePlaybackState.preparingNativeHandoff.isPlaying)
        XCTAssertFalse(LivePlaybackState.paused(.native).isLoading)
        XCTAssertFalse(LivePlaybackState.paused(.native).isPlaying)
        XCTAssertFalse(LivePlaybackState.failed.isLoading)
        XCTAssertFalse(LivePlaybackState.failed.isPlaying)
    }

    @MainActor
    func testStaleFailureFromReloadedSameSourceCannotReplaceCurrentAttempt() async throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)
        let staleAttemptID = viewModel.loadRequestID
        viewModel.handleWebEmbedPlaybackStarted(
            sourceID: sourceID,
            requestID: staleAttemptID,
            startupLatencyMs: 500
        )

        viewModel.loadCurrentSource()
        await Task.yield()
        let currentAttemptID = viewModel.loadRequestID
        XCTAssertNotEqual(currentAttemptID, staleAttemptID)
        viewModel.handleWebEmbedPlaybackStarted(
            sourceID: sourceID,
            requestID: currentAttemptID,
            startupLatencyMs: 450
        )

        viewModel.handleWebEmbedFailure(
            sourceID: sourceID,
            requestID: staleAttemptID,
            reason: "Playback stalled on an obsolete attempt"
        )

        XCTAssertEqual(viewModel.loadRequestID, currentAttemptID)
        XCTAssertEqual(viewModel.currentSourceIndex, 0)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.failedSourceIDs.isEmpty)
    }

    @MainActor
    func testOfflineFailurePreservesCurrentAttemptForRecovery() async throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)
        let attemptID = viewModel.loadRequestID
        viewModel.handleWebEmbedPlaybackStarted(
            sourceID: sourceID,
            requestID: attemptID,
            startupLatencyMs: 500
        )

        viewModel.isNetworkReachable = false
        viewModel.handleWebEmbedFailure(
            sourceID: sourceID,
            requestID: attemptID,
            reason: "Network connection interrupted"
        )

        XCTAssertEqual(viewModel.loadRequestID, attemptID)
        XCTAssertEqual(viewModel.currentSourceIndex, 0)
        XCTAssertTrue(viewModel.pendingRetryAfterNetworkRestore)
        XCTAssertTrue(viewModel.failedSourceIDs.isEmpty)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.connectionPhase, "Waiting For Network")
    }

    @MainActor
    func testCurrentAttemptRecoveryClearsTransientFailureState() async throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)
        let attemptID = viewModel.loadRequestID
        viewModel.error = "Transient interruption"
        viewModel.transition(to: .paused(.webEmbed), phase: "Interrupted")

        viewModel.handleWebEmbedPlaybackRecovered(sourceID: sourceID, requestID: attemptID)

        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.connectionPhase, "Playing")
    }

    @MainActor
    func testNetworkRestorationKeepsTheSameWebAttemptAndBroadcast() async throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)
        let attemptID = viewModel.loadRequestID
        viewModel.handleWebEmbedPlaybackStarted(
            sourceID: sourceID,
            requestID: attemptID,
            startupLatencyMs: 500
        )
        viewModel.isNetworkReachable = false
        viewModel.pendingRetryAfterNetworkRestore = true

        viewModel.handleNetworkReachabilityChange(true)

        XCTAssertEqual(viewModel.loadRequestID, attemptID)
        XCTAssertEqual(viewModel.activeSource?.id, sourceID)
        XCTAssertEqual(viewModel.currentSourceIndex, 0)
        XCTAssertEqual(viewModel.autoFailoverCount, 0)
        XCTAssertFalse(viewModel.pendingRetryAfterNetworkRestore)
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertNil(viewModel.error)
    }

    @MainActor
    func testNativeHandoffFailureReturnsToSameWebBroadcastBeforeFailover() async throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        let webSession = try XCTUnwrap(viewModel.activeSession)
        let nativeSession = StreamSession(
            id: webSession.id,
            matchID: webSession.matchID,
            title: webSession.title,
            playableURL: try XCTUnwrap(URL(string: "https://example.com/native.m3u8")),
            streamType: .hls,
            providerName: webSession.providerName,
            requiredHeaders: [:],
            qualityLabel: "Native"
        )
        viewModel.nativeHandoffSession = nativeSession
        viewModel.transition(to: .playing(.native), phase: "Playing")
        let requestBeforeFailure = viewModel.loadRequestID

        viewModel.handleSourceStartupFailure(
            nativeSession.legacySource,
            reason: "Player item failed after native handoff",
            expectedRequestID: requestBeforeFailure
        )
        await Task.yield()

        XCTAssertNil(viewModel.nativeHandoffSession)
        XCTAssertTrue(viewModel.forceWebEmbedSourceIDs.contains(webSession.id))
        XCTAssertEqual(viewModel.currentSourceIndex, 0)
        XCTAssertEqual(viewModel.autoFailoverCount, 0)
        XCTAssertEqual(viewModel.activeSource?.id, webSession.id)
        XCTAssertTrue(viewModel.failedSourceIDs.isEmpty)
    }

    @MainActor
    func testWebEmbedSuspendsInBackgroundAndResumesSameAttempt() throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }
        let attemptID = viewModel.loadRequestID
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)

        viewModel.transition(to: .playing(.webEmbed), phase: "Playing")
        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.playbackState, .paused(.webEmbed))
        XCTAssertEqual(viewModel.connectionPhase, "Paused (Background)")
        XCTAssertTrue(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(viewModel.loadRequestID, attemptID)
        XCTAssertEqual(viewModel.activeSource?.id, sourceID)

        viewModel.handleScenePhaseChange(.active)

        XCTAssertEqual(viewModel.playbackState, .playing(.webEmbed))
        XCTAssertEqual(viewModel.connectionPhase, "Playing")
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(viewModel.loadRequestID, attemptID)
        XCTAssertEqual(viewModel.activeSource?.id, sourceID)
    }

    @MainActor
    func testWebEmbedPlayPauseIssuesAnExplicitMediaCommand() throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }
        viewModel.transition(to: .playing(.webEmbed), phase: "Playing")

        viewModel.togglePlayPause()

        let pauseCommand = try XCTUnwrap(viewModel.webPlaybackCommand)
        XCTAssertFalse(pauseCommand.shouldPlay)
        XCTAssertEqual(viewModel.playbackState, .paused(.webEmbed))

        viewModel.togglePlayPause()

        let playCommand = try XCTUnwrap(viewModel.webPlaybackCommand)
        XCTAssertTrue(playCommand.shouldPlay)
        XCTAssertNotEqual(playCommand.id, pauseCommand.id)
        XCTAssertEqual(viewModel.playbackState, .playing(.webEmbed))
    }

    func testWebTransportControlsUseABoundedAutoHideDelay() {
        XCTAssertEqual(LivePlaybackPolicy.webControlAutoHideSeconds, 4)
    }

    @MainActor
    func testProviderPauseAndResumeSynchronizeWithoutIssuingAnotherCommand() throws {
        let model = try makeWebPlayerViewModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        model.showControls = false
        model.handleWebEmbedTransportState(.paused, sourceID: source, requestID: attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertTrue(model.showControls)
        XCTAssertNil(model.webPlaybackCommand)
        model.revealWebControlsFromProviderTap()
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        model.handleWebEmbedPlaybackRecovered(sourceID: source, requestID: attempt)
        model.handleWebEmbedFailure(sourceID: source, requestID: attempt, reason: "Playback stalled")
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertEqual(model.autoFailoverCount, 0)
        model.handleWebEmbedTransportState(.playing, sourceID: source, requestID: attempt)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertNil(model.webPlaybackCommand)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
    }

    @MainActor
    func testWebTransportRejectsStaleAndBackgroundEventsAndPreservesPauseThroughHandoff() throws {
        let model = try makeWebPlayerViewModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        model.isVideoReadyForDisplay = true
        model.transition(to: .preparingNativeHandoff, phase: "Playing")
        model.handleWebEmbedTransportState(.paused, sourceID: source, requestID: UUID())
        XCTAssertEqual(model.playbackState, .preparingNativeHandoff)
        model.handleWebEmbedTransportState(.paused, sourceID: UUID(), requestID: attempt)
        XCTAssertEqual(model.playbackState, .preparingNativeHandoff)
        model.handleWebEmbedTransportState(.paused, sourceID: source, requestID: attempt)
        model.finishNativeHandoffPreparation(sourceID: source, requestID: attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        model.handleScenePhaseChange(.background)
        model.handleScenePhaseChange(.active)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        model.handleScenePhaseChange(.background)
        model.handleWebEmbedTransportState(.playing, sourceID: source, requestID: attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertTrue(model.shouldResumeAfterForeground)
    }

    func testExecutedWebMonitorReportsProviderTransportAndPreservesClickHandlers() throws {
        let context = try makeWebMonitorContext()
        XCTAssertEqual(context.evaluateScript("timers.some(t => t.delay === 20000)")?.toBool(), true)
        context.evaluateScript("emit('playing', video)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'transport_state').at(-1).reason")?.toString(), "playing")
        context.evaluateScript("video.pause()")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).reason")?.toString(), "paused")
        context.evaluateScript("video.play()")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).reason")?.toString(), "playing")
        context.evaluateScript("video.pause(); messages = []; clock += 60000; intervals.forEach(t => t.fn())")
        XCTAssertEqual(context.evaluateScript("messages.some(m => m.type === 'stream_failed')")?.toBool(), false)
        context.evaluateScript("window.__fottySetPlaying(true); intervals.forEach(t => t.fn())")
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("messages.some(m => m.type === 'stream_failed')")?.toBool(), false)
        context.evaluateScript("clickAnchor('_blank', '#play')")
        XCTAssertEqual(context.evaluateScript("lastClick.prevented")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("lastClick.stopped")?.toBool(), false, "Do not swallow a provider's JS control handler")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).type")?.toString(), "surface_tapped")
        XCTAssertEqual(context.evaluateScript("listeners.click.some(l => l.options.passive === true)")?.toBool(), true)
        context.evaluateScript("clickAnchor('_blank', 'https://doubleclick.test/ad.html')")
        XCTAssertEqual(context.evaluateScript("lastClick.stopped")?.toBool(), true)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Unexpected monitor exception")
    }

    func testExecutedWebMonitorRejectsFailedPlayAndIgnoresOtherMediaAndBackgroundPauses() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing', video); video.pause(); messages = []; video.rejectPlay = true; window.__fottySetPlaying(true)")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).reason")?.toString(), "paused")
        context.evaluateScript("messages = []; emit('pause', {paused:true, tagName:'VIDEO'}); window.__fottySetPlaybackSuspended(true)")
        XCTAssertEqual(context.evaluateScript("messages.length")?.toInt32(), 0)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Unexpected monitor exception")
    }

    func testWebMonitorTracksReplacementAndRewoundPlayheadsWithoutFalseStalls() throws {
        for replaceElement in [false, true] {
            let context = try makeWebMonitorContext()
            context.evaluateScript("video.currentTime=300; emit('playing',video); messages=[];")
            if replaceElement {
                context.evaluateScript("video.isConnected=false; video=Object.assign({},video,{isConnected:true,currentTime:1});")
            } else {
                context.evaluateScript("video.currentTime=1;")
            }
            context.evaluateScript("for(let n=0;n<40;n++){clock+=1000; video.currentTime+=1; emit('timeupdate',video); intervals.forEach(t=>t.fn());}")
            XCTAssertEqual(context.evaluateScript("messages.some(m=>m.type==='stream_failed')")?.toBool(), false)
            // A replacement that subsequently freezes must still fail the watchdog.
            context.evaluateScript("clock+=31000; intervals.forEach(t=>t.fn());")
            XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='stream_failed').length")?.toInt32(), 1)
            context.evaluateScript("video.currentTime+=1; emit('timeupdate',video);")
            XCTAssertEqual(context.evaluateScript("messages.at(-1).type")?.toString(), "playback_recovered")
            XCTAssertNil(context.exception)
        }
    }

    func testWebMonitorScopesErrorsAndProgressToTheConfirmedVideo() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing',video); messages=[]; emit('error',{tagName:'VIDEO',error:{code:4}});")
        XCTAssertEqual(context.evaluateScript("messages.length")?.toInt32(), 0)
        context.evaluateScript("video.error={code:3}; emit('error',video);")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).type")?.toString(), "stream_failed")
        context.evaluateScript("video.currentTime+=1; emit('timeupdate',video); video.pause(); messages=[];")
        context.evaluateScript("var auxiliary=Object.assign({},video,{paused:false,currentTime:999}); document.querySelectorAll=s=>s==='video'?[video,auxiliary]:[]; clock+=60000; intervals.forEach(t=>t.fn());")
        XCTAssertEqual(context.evaluateScript("messages.some(m=>m.type==='stream_failed')")?.toBool(), false, "An auxiliary video cannot turn an intentional pause into a stall")
        XCTAssertNil(context.exception)
    }

    @MainActor
    func testWebBridgeRejectsFailuresAndRecoveryFromUnrelatedDocuments() {
        var recoveries = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(
            onSurfaceTapped: nil, onTransportStateChanged: nil, onPlaybackStarted: nil,
            onPlaybackStalled: nil, onPlaybackRecovered: { recoveries += 1 }, onNativeCandidateDiscovered: nil
        )
        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "broadcast"])
        coordinator.handlePlaybackMessage(["type": "stream_failed", "documentID": "ad", "reason": "Media error 4"])
        XCTAssertNil(coordinator.pendingFailureTask)
        coordinator.handlePlaybackMessage(["type": "stream_failed", "reason": "Media error 4"])
        XCTAssertNil(coordinator.pendingFailureTask)
        coordinator.handlePlaybackMessage(["type": "stream_failed", "documentID": "broadcast", "reason": "Media error 3"])
        XCTAssertNotNil(coordinator.pendingFailureTask)
        coordinator.handlePlaybackMessage(["type": "playback_recovered", "documentID": "ad"])
        XCTAssertNotNil(coordinator.pendingFailureTask)
        XCTAssertEqual(recoveries, 0)
        coordinator.handlePlaybackMessage(["type": "playback_recovered", "documentID": "broadcast"])
        XCTAssertNil(coordinator.pendingFailureTask)
        XCTAssertEqual(recoveries, 1)
    }

    private func makeWebMonitorContext() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        var window = this; window.top = window; window.parent = window;
        var clock = 1000; Date.now = () => clock;
        var messages = [], listeners = {}, timers = [], intervals = [];
        var location = {href:'https://example.test/player'};
        var navigator = {userAgent:'test'};
        window.webkit = {messageHandlers:{fottyPlayerBridge:{postMessage:m => messages.push(m)}}};
        window.addEventListener = function() {};
        var performance = {getEntriesByType:() => []};
        function emit(type, target) { (listeners[type] || []).forEach(l => l.fn({target:target})); }
        var video = {
            paused:false, ended:false, currentTime:1, currentSrc:'', readyState:4,
            videoWidth:320, videoHeight:180, tagName:'VIDEO', isConnected:true,
            setAttribute:function(){},
            pause:function(){this.paused=true; emit('pause', this);},
            play:function(){
                if (!this.rejectPlay) { this.paused=false; emit('playing', this); }
                return {then:(ok, bad) => this.rejectPlay ? bad() : ok(), catch:function(){}};
            }
        };
        var document = {
            hidden:false, body:{innerText:''}, documentElement:{},
            querySelectorAll:s => s === 'video' || s === 'video, audio' ? [video] : [],
            querySelector:() => null,
            addEventListener:(t, fn, options) => (listeners[t] ||= []).push({fn,options})
        };
        function MutationObserver() {this.observe = function(){};}
        function setTimeout(fn, delay) {timers.push({fn,delay});}
        function setInterval(fn, delay) {intervals.push({fn,delay});}
        var lastClick;
        function clickAnchor(target, href) {
            lastClick = {target:{closest:() => ({target,href})}, prevented:false, stopped:false,
                preventDefault:function(){this.prevented=true;}, stopImmediatePropagation:function(){this.stopped=true;}};
            for (var listener of listeners.click) { listener.fn(lastClick); if(lastClick.stopped) break; }
        }
        """#)
        context.evaluateScript(LiveWebEmbedPlayerView.playbackMonitorScript(isMuted: true, providerControlsAudio: true, isSuspended: false))
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Monitor must execute, not just parse")
        return context
    }

    @MainActor
    func testTransientInactiveSceneDoesNotForcePictureInPicture() throws {
        let viewModel = try makeNativePlayerViewModel()
        defer { viewModel.cleanup() }
        viewModel.isPictureInPictureAvailable = true
        viewModel.transition(to: .playing(.native), phase: "Playing")

        viewModel.handleScenePhaseChange(.inactive)

        XCTAssertNil(viewModel.pictureInPictureRequestID)
        XCTAssertEqual(viewModel.playbackState, .playing(.native))
        XCTAssertEqual(viewModel.connectionPhase, "Playing")
    }

    @MainActor
    func testPictureInPictureStopAndFailureClearBackgroundContinuity() throws {
        let viewModel = try makeNativePlayerViewModel()
        defer { viewModel.cleanup() }
        viewModel.handlePictureInPictureAvailabilityChanged(true)
        viewModel.transition(to: .playing(.native), phase: "Playing")

        viewModel.togglePictureInPicture()
        XCTAssertTrue(viewModel.keepsPlaybackAliveInBackground)

        viewModel.handlePictureInPictureFailure("PiP could not start", isBackgrounded: true)
        XCTAssertFalse(viewModel.keepsPlaybackAliveInBackground)
        XCTAssertNil(viewModel.lastPictureInPictureRequestAt)
        XCTAssertEqual(viewModel.playbackState, .paused(.native))
        XCTAssertEqual(viewModel.connectionPhase, "Paused (Background)")
        XCTAssertTrue(viewModel.shouldResumeAfterForeground)

        viewModel.transition(to: .playing(.native), phase: "Playing")
        viewModel.handlePictureInPictureActivityChanged(true)
        XCTAssertTrue(viewModel.keepsPlaybackAliveInBackground)
        XCTAssertEqual(viewModel.connectionPhase, "PiP Active")

        viewModel.handlePictureInPictureActivityChanged(false, isBackgrounded: true)
        XCTAssertFalse(viewModel.keepsPlaybackAliveInBackground)
        XCTAssertNil(viewModel.lastPictureInPictureRequestAt)
        XCTAssertEqual(viewModel.playbackState, .paused(.native))
        XCTAssertEqual(viewModel.connectionPhase, "Paused (Background)")
        XCTAssertTrue(viewModel.shouldResumeAfterForeground)
    }

    @MainActor
    func testActiveNativePictureInPictureKeepsPlayerRunningWhenAppBackgrounds() throws {
        let viewModel = try makeNativePlayerViewModel()
        defer { viewModel.cleanup() }
        let player = AVPlayer()
        viewModel.player = player
        viewModel.handlePictureInPictureAvailabilityChanged(true)
        viewModel.transition(to: .playing(.native), phase: "Playing")
        viewModel.handlePictureInPictureActivityChanged(true)

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.playbackState, .playing(.native))
        XCTAssertEqual(viewModel.connectionPhase, "PiP Active")
        XCTAssertTrue(viewModel.keepsPlaybackAliveInBackground)
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(player.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
    }

    @MainActor
    func testReferenceHLSMaintainsOneAttemptDuringSoak() async throws {
#if FOTTY_PLAYBACK_SOAK && !targetEnvironment(simulator)
        let referenceSession = StreamSession(
            matchID: "fotty-physical-soak",
            title: "Fotty Physical Playback Soak",
            playableURL: StreamPipelineKnownGoodURLs.appleBipbopMaster,
            streamType: .hls,
            providerName: "StreamEx Reference",
            requiredHeaders: ["X-Fotty-Nexus-Source": "admin"],
            qualityLabel: "Apple HLS"
        )
        let viewModel = LivePlayerViewModel(
            event: makePlaybackTestEvent(),
            providedSessions: [referenceSession]
        )
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        viewModel.player?.isMuted = true
        viewModel.player?.volume = 0
        let startupDeadline = Date().addingTimeInterval(25)
        while viewModel.isLoading, viewModel.error == nil, Date() < startupDeadline {
            viewModel.player?.isMuted = true
            viewModel.player?.volume = 0
            try await Task.sleep(for: .milliseconds(250))
        }

        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
        viewModel.player?.isMuted = true
        let attemptID = viewModel.loadRequestID
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)
        let originalItem = try XCTUnwrap(viewModel.player?.currentItem)
        let startSeconds = viewModel.player?.currentTime().seconds ?? 0
        var furthestSecond = startSeconds
        var advancingSamples = 0
        var waitingSamples = 0
        var pausedSamples = 0

        #if targetEnvironment(macCatalyst)
        let soakDurationSeconds = 120
        #else
        let soakDurationSeconds = 20
        #endif

        for _ in 0..<soakDurationSeconds {
            try await Task.sleep(for: .seconds(1))
            XCTAssertEqual(viewModel.loadRequestID, attemptID)
            XCTAssertEqual(viewModel.activeSource?.id, sourceID)
            XCTAssertTrue(viewModel.player?.currentItem === originalItem)
            XCTAssertNil(viewModel.error)
            let currentSecond = viewModel.player?.currentTime().seconds ?? 0
            if currentSecond > furthestSecond + 0.1 { advancingSamples += 1 }
            furthestSecond = max(furthestSecond, currentSecond)
            switch viewModel.player?.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate: waitingSamples += 1
            case .paused: pausedSamples += 1
            default: break
            }
        }

        print(
            "[PlaybackSoak] progress=\(furthestSecond - startSeconds)s "
                + "advancingSamples=\(advancingSamples) waitingSamples=\(waitingSamples) "
                + "pausedSamples=\(pausedSamples) rate=\(viewModel.player?.rate ?? -1)"
        )
        // A physical XCTest host may suspend media after its short foreground
        // window. Decode/progress proves the media path; unchanged identity and
        // zero failover for the full soak prove Fotty did not drop the attempt.
        XCTAssertGreaterThan(furthestSecond - startSeconds, 5)
        XCTAssertGreaterThan(advancingSamples, 0)
        XCTAssertEqual(viewModel.autoFailoverCount, 0)
#else
        throw XCTSkip("Enable only for an intentional device or Catalyst soak with -DFOTTY_PLAYBACK_SOAK.")
#endif
    }

    func testTeamFollowKeyIsStableAcrossCaseAndPunctuation() {
        XCTAssertEqual(
            TeamFollowKey.make(name: "  Manchester United F.C. ", category: "football"),
            "football|manchester-united-f-c"
        )
    }

    func testSpoilerProtectedAlertsNeverExposeScore() {
        let goal = MatchAlertContent.make(
            kind: .goal(home: 3, away: 2),
            homeTeam: "Chelsea",
            awayTeam: "Fulham",
            competition: "Premier League",
            spoilerProtected: true
        )
        let fullTime = MatchAlertContent.make(
            kind: .fullTime(home: 3, away: 2),
            homeTeam: "Chelsea",
            awayTeam: "Fulham",
            competition: "Premier League",
            spoilerProtected: true
        )

        for content in [goal, fullTime] {
            XCTAssertFalse(content.title.contains("3"))
            XCTAssertFalse(content.body.contains("3"))
            XCTAssertFalse(content.title.localizedCaseInsensitiveContains("goal"))
            XCTAssertFalse(content.body.localizedCaseInsensitiveContains("goal"))
        }
    }

    func testUnprotectedFullTimeAlertContainsTheResult() {
        let content = MatchAlertContent.make(
            kind: .fullTime(home: 3, away: 2),
            homeTeam: "Chelsea",
            awayTeam: "Fulham",
            competition: "Premier League",
            spoilerProtected: false
        )

        XCTAssertEqual(content.title, "Full time")
        XCTAssertEqual(content.body, "Chelsea 3–2 Fulham")
    }

    func testFPLWidgetAndMatchNotificationDeepLinksHaveTypedDestinations() throws {
        let fplURL = try XCTUnwrap(URL(string: "fotty://fpl"))
        let matchURL = try XCTUnwrap(URL(string: "fotty://match/schedule-42"))
        let liveURL = try XCTUnwrap(URL(string: "fotty://live/schedule-42"))

        XCTAssertEqual(FottyDeepLinkDestination.parse(fplURL), .fpl)
        XCTAssertEqual(FottyDeepLinkDestination.parse(matchURL), .match("schedule-42"))
        XCTAssertEqual(
            FottyDeepLinkDestination.parse(liveURL),
            .survivingLivePlayer("schedule-42")
        )
        XCTAssertNil(FottyDeepLinkDestination.parse(URL(string: "https://example.com")!))
    }

    func testDeadlineWidgetSmallAndMediumExposeOfficialSourceAndTypedRoute() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let widgetURL = projectRoot
            .appendingPathComponent("FottyLiveActivityExtension")
            .appendingPathComponent("FottyFPLDeadlineWidget.swift")
        let source = try String(contentsOf: widgetURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".supportedFamilies([.systemSmall, .systemMedium])"))
        XCTAssertTrue(source.contains("if family == .systemSmall"))
        XCTAssertTrue(source.contains("Label(entry.sourceStatus, systemImage: \"checkmark.shield.fill\")"))
        XCTAssertTrue(source.contains(".widgetURL(URL(string: \"fotty://fpl\"))"))
    }

    func testCoachQuickPromptsUseFocusDismissedSendPath() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coachURL = projectRoot
            .appendingPathComponent("Fotty")
            .appendingPathComponent("Features/FPL/Views/Components/FPLAICoachView.swift")
        let source = try String(contentsOf: coachURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Button(prompt) { sendQuery(prompt) }"))
        let functionStart = try XCTUnwrap(source.range(of: "private func sendQuery(_ query: String)"))
        let firstMessage = try XCTUnwrap(
            source.range(
                of: "viewModel.sendCoachQuestion",
                range: functionStart.upperBound..<source.endIndex
            )
        )
        let preMessagePath = source[functionStart.lowerBound..<firstMessage.lowerBound]
        XCTAssertTrue(preMessagePath.contains("isComposerFocused = false"))
    }

    @MainActor
    func testLiveActivityReturnLinkRevealsSurvivingPlayerOrFallsBackToMatch() throws {
        let store = MatchNavigationStore.shared
        if let activeMatchID = store.activeLivePlayerMatchID {
            store.livePlayerDidDisappear(matchID: activeMatchID)
        }
        store.pendingMatchID = nil
        defer {
            store.livePlayerDidDisappear(matchID: "schedule-42")
            store.pendingMatchID = nil
        }

        let liveURL = try XCTUnwrap(URL(string: "fotty://live/schedule-42"))
        store.open(url: liveURL)
        XCTAssertEqual(store.pendingMatchID, "schedule-42")

        store.pendingMatchID = nil
        store.livePlayerDidAppear(matchID: "schedule-42")
        store.open(url: liveURL)
        XCTAssertNil(store.pendingMatchID)

        store.livePlayerDidDisappear(matchID: "schedule-42")
        store.open(url: liveURL)
        XCTAssertEqual(store.pendingMatchID, "schedule-42")
    }

    func testFootballStatusNormalizationTrimsProviderWhitespace() {
        XCTAssertEqual(FootballNormalizer.normalizeStatus("  in_play\n"), .live)
        XCTAssertEqual(FootballNormalizer.normalizeStatus(" ht "), .halfTime)
        XCTAssertEqual(FootballNormalizer.normalizeStatus(" CANC "), .cancelled)
    }

    func testMalformedProviderDateIsRejectedInsteadOfBecomingNow() {
        XCTAssertNil(FootballNormalizer.parseISO8601Date("not-a-date"))
        XCTAssertNil(FootballNormalizer.parseISO8601Date("   "))
        XCTAssertNotNil(FootballNormalizer.parseISO8601Date("2026-08-22T16:00:00Z"))
        XCTAssertNotNil(FootballNormalizer.parseISO8601Date("2026-08-22T16:00:00.123Z"))
    }

    func testKickoffWindowsHaveStableBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(now.addingTimeInterval(6 * 3_600).isWithinStartingSoonWindow(relativeTo: now))
        XCTAssertFalse(now.isWithinStartingSoonWindow(relativeTo: now))
        XCTAssertFalse(now.addingTimeInterval(-1).isWithinStartingSoonWindow(relativeTo: now))
        XCTAssertNil(now.addingTimeInterval(48 * 3_600 + 1).liveKickoffRelativeSnippet(relativeTo: now))
        XCTAssertNil(now.addingTimeInterval(-36 * 3_600 - 1).liveKickoffRelativeSnippet(relativeTo: now))
    }

    @MainActor
    func testHomeScheduleExcludesFinishedMatchesWhileRecentCatalogRetainsThem() {
        let now = Date()
        let finished = makeScheduleEvent(id: "finished", kickoff: now.addingTimeInterval(-4 * 3_600))
        let inPlay = makeScheduleEvent(id: "in-play", kickoff: now.addingTimeInterval(-45 * 60))
        let upcoming = makeScheduleEvent(id: "upcoming", kickoff: now.addingTimeInterval(2 * 3_600))

        let schedule = HomeMatchPriority.homeScheduleCandidates(
            from: [finished, inPlay, upcoming],
            scoreService: .shared
        )

        XCTAssertEqual(
            Set(schedule.map(\.id)),
            ["schedule-policy-in-play", "schedule-policy-upcoming"]
        )
        XCTAssertTrue(finished.passesNearTermLiveListWindow(at: now))
    }

    func testLeagueDisplayIncludesCountryOnlyWhenNeeded() {
        XCTAssertEqual(
            LeagueDisplayFormatting.audienceFacing(leagueName: "Premier League", country: "England"),
            "England · Premier League"
        )
        XCTAssertEqual(
            LeagueDisplayFormatting.audienceFacing(leagueName: "English Premier League", country: "England"),
            "English Premier League"
        )
        XCTAssertEqual(
            LeagueDisplayFormatting.audienceFacing(leagueName: "   ", country: "England"),
            "Unknown Competition"
        )
    }

    func testDenseTeamNamesRemainRecognizable() {
        XCTAssertEqual(MatchCardFormatting.denseTeamName("Atlético Bucaramanga"), "Atlético Bucaramanga")
        XCTAssertEqual(MatchCardFormatting.denseTeamName("América de Cali"), "América de Cali")
        XCTAssertEqual(MatchCardFormatting.denseTeamName("CD Guadalajara"), "CD Guadalajara")
        XCTAssertEqual(MatchCardFormatting.denseTeamName("Leicester City"), "Leicester")
        XCTAssertEqual(MatchCardFormatting.denseTeamName("Sheffield Wednesday"), "Sheff Wed")
        XCTAssertEqual(MatchCardFormatting.compactTeamName("América de Cali"), "América de Cali")
    }

    @MainActor
    func testMultiViewTimingRequiresLiveOrImminentKickoff() {
        let now = Date()
        let imminent = makeScheduleEvent(id: "multi-imminent", kickoff: now.addingTimeInterval(2 * 60))
        let tooEarly = makeScheduleEvent(id: "multi-too-early", kickoff: now.addingTimeInterval(2 * 3_600))
        let inPlay = makeScheduleEvent(id: "multi-in-play", kickoff: now.addingTimeInterval(-20 * 60))

        XCTAssertTrue(
            HomeMatchPriority.isMultiViewTimingEligible(
                imminent,
                scoreService: .shared,
                now: now
            )
        )
        XCTAssertFalse(
            HomeMatchPriority.isMultiViewTimingEligible(
                tooEarly,
                scoreService: .shared,
                now: now
            )
        )
        XCTAssertTrue(
            HomeMatchPriority.isMultiViewTimingEligible(
                inPlay,
                scoreService: .shared,
                now: now
            )
        )
    }

    @MainActor
    func testMyMatchdaySavePersistsThePlayableCatalogSnapshot() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FottyTests.MyMatchday"))
        let key = "saved-match-persistence"
        defaults.removeObject(forKey: key)
        defer { defaults.removeObject(forKey: key) }

        let event = AnalyticalDataEngine.EventReference(
            id: "arsenal-liverpool",
            title: "Arsenal vs Liverpool",
            category: "football",
            date: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1_000),
            poster: nil,
            popular: true,
            teams: NexusATeams(
                home: NexusATeam(name: "Arsenal", badge: "https://example.com/arsenal.png"),
                away: NexusATeam(name: "Liverpool", badge: "https://example.com/liverpool.png")
            ),
            sources: [NexusASource(source: "echo", id: "123")]
        )

        let store = MyMatchdayStore(defaults: defaults, storageKey: key)
        store.save(event)

        let reloaded = MyMatchdayStore(defaults: defaults, storageKey: key)
        let restored = try XCTUnwrap(reloaded.savedMatches.first?.event)
        XCTAssertEqual(restored.id, event.id)
        XCTAssertEqual(restored.homeName, "Arsenal")
        XCTAssertEqual(restored.awayName, "Liverpool")
        XCTAssertEqual(restored.sources?.first?.source, "echo")
        XCTAssertEqual(restored.sources?.first?.id, "123")

        reloaded.remove(eventID: event.id)
        XCTAssertTrue(reloaded.savedMatches.isEmpty)
    }

    @MainActor
    func testMyMatchdayPrunesOnlyMatchesOlderThanItsContinuityWindow() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FottyTests.MyMatchday.Prune"))
        let key = "saved-match-pruning"
        defaults.removeObject(forKey: key)
        defer { defaults.removeObject(forKey: key) }

        let store = MyMatchdayStore(defaults: defaults, storageKey: key)
        let now = Date()
        let old = AnalyticalDataEngine.EventReference(
            id: "old",
            title: "Old Match",
            category: "football",
            date: Int64(now.addingTimeInterval(-37 * 3600).timeIntervalSince1970),
            poster: nil,
            popular: false,
            teams: nil,
            sources: nil
        )
        let current = AnalyticalDataEngine.EventReference(
            id: "current",
            title: "Current Match",
            category: "football",
            date: Int64(now.addingTimeInterval(-35 * 3600).timeIntervalSince1970),
            poster: nil,
            popular: false,
            teams: nil,
            sources: nil
        )
        store.save(old)
        store.save(current)

        store.pruneExpiredMatches(relativeTo: now)

        XCTAssertFalse(store.contains(eventID: "old"))
        XCTAssertTrue(store.contains(eventID: "current"))
    }

    @MainActor
    private func makeWebPlayerViewModel() throws -> LivePlayerViewModel {
        let session = StreamSession(
            matchID: "fotty-playback-race",
            title: "Playback Race Test",
            playableURL: try XCTUnwrap(URL(string: "https://embed.st/embed/admin/fotty-test/1")),
            streamType: .unknown,
            providerName: "StreamEx",
            requiredHeaders: [
                "X-Fotty-Nexus-Source": "admin",
                "X-Fotty-Web-Embed": "true"
            ],
            qualityLabel: "Web"
        )
        return LivePlayerViewModel(event: makePlaybackTestEvent(), providedSessions: [session])
    }

    @MainActor
    private func makeNativePlayerViewModel() throws -> LivePlayerViewModel {
        let session = StreamSession(
            matchID: "fotty-native-lifecycle",
            title: "Native Lifecycle Test",
            playableURL: try XCTUnwrap(URL(string: "https://example.com/fotty-test.m3u8")),
            streamType: .hls,
            providerName: "Native Test",
            requiredHeaders: [:],
            qualityLabel: "Native"
        )
        return LivePlayerViewModel(event: makePlaybackTestEvent(), providedSessions: [session])
    }

    @MainActor
    private func makePlaybackTestEvent() -> AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(
            id: "fotty-playback-test-event",
            title: "Fotty Playback Test",
            category: "football",
            date: Int64(Date().timeIntervalSince1970 * 1_000),
            poster: nil,
            popular: false,
            teams: nil,
            sources: nil
        )
    }

    @MainActor
    private func makeScheduleEvent(
        id: String,
        kickoff: Date
    ) -> AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(
            id: "schedule-policy-\(id)",
            title: "Schedule Home \(id) vs Schedule Away \(id)",
            category: "football",
            date: Int64(kickoff.timeIntervalSince1970 * 1_000),
            poster: nil,
            popular: false,
            teams: NexusATeams(
                home: NexusATeam(name: "Schedule Home \(id)", badge: nil),
                away: NexusATeam(name: "Schedule Away \(id)", badge: nil)
            ),
            sources: nil
        )
    }
}

final class FottyQualityStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "FottyQualityStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testQualityStoreRejectsPrivateAndFreeFormDetails() {
        let store = FottyQualityStore(defaults: defaults, storageKey: "records")
        store.record(
            category: .playback,
            name: "decoded_progress",
            outcome: .success,
            durationMilliseconds: 1_250,
            details: [
                "mode": "web_embed",
                "url": "https://private.example/stream.m3u8",
                "source": "https://private.example",
                "prompt": "My manager id is 123"
            ]
        )

        let record = store.records().first
        XCTAssertEqual(record?.details, ["mode": "web_embed"])
        XCTAssertFalse(store.exportJSON().contains("private.example"))
        XCTAssertFalse(store.exportJSON().contains("My manager id is 123"))
    }

    func testQualityStoreBoundsHistoryAndSummarizesReleaseEvidence() {
        var currentDate = Date(timeIntervalSince1970: 2_000_000_000)
        let store = FottyQualityStore(
            defaults: defaults,
            storageKey: "records",
            now: { currentDate }
        )
        for index in 0..<260 {
            store.record(
                category: .playback,
                name: index.isMultiple(of: 2) ? "attempt_started" : "decoded_progress",
                outcome: index.isMultiple(of: 2) ? .info : .success,
                durationMilliseconds: index.isMultiple(of: 2) ? nil : index * 10,
                details: ["mode": "native"]
            )
            currentDate.addTimeInterval(1)
        }

        let records = store.records()
        let summary = store.summary()
        XCTAssertEqual(records.count, 250)
        XCTAssertEqual(summary.recordCount, 250)
        XCTAssertEqual(summary.playbackAttempts, 125)
        XCTAssertEqual(summary.provenPlaybackStarts, 125)
        XCTAssertNotNil(summary.medianStartupMilliseconds)
        XCTAssertTrue(store.exportJSON().contains("\"summary\""))
    }

    func testQualityStoreDropsExpiredRecords() {
        var currentDate = Date(timeIntervalSince1970: 2_000_000_000)
        let store = FottyQualityStore(
            defaults: defaults,
            storageKey: "records",
            now: { currentDate }
        )
        store.record(category: .fpl, name: "refresh", outcome: .success)
        currentDate.addTimeInterval(15 * 24 * 60 * 60)

        XCTAssertTrue(store.records().isEmpty)
    }
}

final class LiveActivityPolicyTests: XCTestCase {
    func testNativePlaybackWithoutUsefulMatchStateDoesNotCreateLiveActivity() {
        XCTAssertFalse(
            FottyLiveActivityPolicy.shouldPresent(
                isWebEmbed: false,
                isPlaying: true,
                isLoading: false,
                hasError: false,
                supportsPictureInPicture: true,
                hasActivePictureInPicture: true,
                hasUsefulMatchState: false
            )
        )
    }

    func testWebEmbedNeverCreatesPlaybackLiveActivity() {
        XCTAssertFalse(
            FottyLiveActivityPolicy.shouldPresent(
                isWebEmbed: true,
                isPlaying: true,
                isLoading: false,
                hasError: false,
                supportsPictureInPicture: false,
                hasActivePictureInPicture: false
            )
        )
    }

    func testReadyNativePictureInPicturePlaybackCanPresent() {
        XCTAssertTrue(
            FottyLiveActivityPolicy.shouldPresent(
                isWebEmbed: false,
                isPlaying: true,
                isLoading: false,
                hasError: false,
                supportsPictureInPicture: true,
                hasActivePictureInPicture: true
            )
        )
    }

    func testBackgroundedPlaybackWithoutPictureInPictureIsRemoved() {
        XCTAssertFalse(
            FottyLiveActivityPolicy.shouldPresent(
                isWebEmbed: false,
                isPlaying: true,
                isLoading: false,
                hasError: false,
                supportsPictureInPicture: true,
                hasActivePictureInPicture: false
            )
        )
    }

    func testForegroundCapabilityWithoutActivePictureInPictureDoesNotPresent() {
        XCTAssertFalse(
            FottyLiveActivityPolicy.shouldPresent(
                isWebEmbed: false,
                isPlaying: true,
                isLoading: false,
                hasError: false,
                supportsPictureInPicture: true,
                hasActivePictureInPicture: false
            )
        )
    }
}

@MainActor
final class LiveScoreServiceTests: XCTestCase {
    override func tearDown() {
        LiveScoreService.shared.installScoreboardFixturesForTesting([])
        super.tearDown()
    }

    func testCatalogAliasReceivesMatchedScoreAndMinute() {
        let match = makeMatch(
            home: "New England Revolution",
            away: "New York City FC",
            homeGoals: 1,
            awayGoals: 1
        )
        LiveScoreService.shared.installScoreboardFixturesForTesting(
            [match],
            minuteLabels: ["new england revolution|new york city fc": "68'"]
        )

        let score = LiveScoreService.shared.scoreForMatch(
            home: "New England",
            away: "New York City"
        )

        XCTAssertEqual(score?.homeGoals, 1)
        XCTAssertEqual(score?.awayGoals, 1)
        XCTAssertEqual(score?.minute, "68'")
    }

    func testIdentityWordsDoNotCollapseManchesterClubsTogether() {
        LiveScoreService.shared.installScoreboardFixturesForTesting([
            makeMatch(
                home: "Manchester United",
                away: "Arsenal",
                homeGoals: 2,
                awayGoals: 0
            )
        ])

        XCTAssertNil(
            LiveScoreService.shared.scoreForMatch(
                home: "Manchester City",
                away: "Arsenal"
            )
        )
    }

    func testScheduledFixtureDoesNotDisplayFakeNilNilScoreAsZeroZero() {
        let match = makeMatch(
            home: "Liverpool",
            away: "Chelsea",
            homeGoals: 0,
            awayGoals: 0,
            status: .scheduled
        )
        LiveScoreService.shared.installScoreboardFixturesForTesting([match])

        XCTAssertNil(
            LiveScoreService.shared.scoreForMatch(home: "Liverpool", away: "Chelsea")
        )
    }

    func testOutOfScopeCompetitionDoesNotDisplayAProviderScore() {
        let match = makeMatch(
            home: "Real Madrid",
            away: "Barcelona",
            homeGoals: 2,
            awayGoals: 1,
            competitionId: 2,
            competitionName: "UEFA Champions League",
            competitionCountry: nil
        )
        LiveScoreService.shared.installScoreboardFixturesForTesting([match])

        XCTAssertNil(
            LiveScoreService.shared.scoreForMatch(home: "Real Madrid", away: "Barcelona")
        )
    }

    func testCatalogKickoffRejectsAnOlderFixtureBetweenTheSameTeams() {
        let match = makeMatch(
            home: "Nottingham Forest",
            away: "Leeds United",
            homeGoals: 0,
            awayGoals: 1,
            status: .finished
        )
        LiveScoreService.shared.installScoreboardFixturesForTesting([match])

        let differentMatchKickoff = Date(timeIntervalSince1970: 1_777_142_400)
        XCTAssertNil(
            LiveScoreService.shared.scoreForMatch(
                home: "Nottingham Forest",
                away: "Leeds United",
                near: differentMatchKickoff
            )
        )
    }

    func testCatalogKickoffAcceptsTheSameScheduledFixture() {
        let match = makeMatch(
            home: "Nottingham Forest",
            away: "Leeds United",
            homeGoals: 2,
            awayGoals: 1
        )
        LiveScoreService.shared.installScoreboardFixturesForTesting([match])
        let matchingKickoff = try! XCTUnwrap(
            FootballNormalizer.parseISO8601Date("2026-08-23T18:00:00Z")
        )

        XCTAssertEqual(
            LiveScoreService.shared.scoreForMatch(
                home: "Nottingham Forest",
                away: "Leeds United",
                near: matchingKickoff
            )?.homeGoals,
            2
        )
    }

    private func makeMatch(
        home: String,
        away: String,
        homeGoals: Int,
        awayGoals: Int,
        status: FootballMatch.MatchStatus = .inPlay,
        competitionId: Int = 39,
        competitionName: String = "Premier League",
        competitionCountry: String? = "England"
    ) -> FootballMatch {
        FootballMatch(
            id: 1,
            apiFootballFixtureId: 1,
            utcDate: "2026-08-23T18:00:00Z",
            status: status,
            matchday: nil,
            stage: nil,
            group: nil,
            homeTeam: FootballTeam(id: 1, name: home, shortName: nil, tla: nil, crest: nil),
            awayTeam: FootballTeam(id: 2, name: away, shortName: nil, tla: nil, crest: nil),
            score: MatchScore(
                winner: nil,
                duration: "REGULAR",
                fullTime: ScoreDetail(home: homeGoals, away: awayGoals),
                halfTime: nil
            ),
            competition: MatchCompetition(
                id: competitionId,
                name: competitionName,
                code: nil,
                emblem: nil,
                country: competitionCountry
            ),
            referees: nil,
            events: nil
        )
    }
}
