import XCTest
import JavaScriptCore
import AVFoundation
import WebKit
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

    func testLateScore808DiscoveryUsesOnlyExplicitFootballWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(Score808LateDiscoveryPolicy.isLookupWindow(
            kickoffDate: now.addingTimeInterval(30 * 60), category: "football", at: now))
        XCTAssertFalse(Score808LateDiscoveryPolicy.isLookupWindow(
            kickoffDate: now.addingTimeInterval(30 * 60 + 1), category: "football", at: now))
        XCTAssertTrue(Score808LateDiscoveryPolicy.isLookupWindow(
            kickoffDate: now.addingTimeInterval(-3 * 60 * 60), category: "football", at: now))
        XCTAssertFalse(Score808LateDiscoveryPolicy.isLookupWindow(
            kickoffDate: now.addingTimeInterval(-3 * 60 * 60 - 1), category: "football", at: now))
        XCTAssertFalse(Score808LateDiscoveryPolicy.isLookupWindow(
            kickoffDate: now, category: "cricket", at: now))
        XCTAssertFalse(Score808LateDiscoveryPolicy.isLookupWindow(
            kickoffDate: nil, category: "football", at: now))
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
        XCTAssertTrue(script.contains("picture_in_picture_state"))
        XCTAssertTrue(script.contains("enterpictureinpicture"))
        XCTAssertTrue(script.contains("webkitpresentationmodechanged"))
        XCTAssertTrue(script.contains("within 20 seconds"))
        XCTAssertTrue(script.contains("vpn recommended"))
        XCTAssertTrue(script.contains("continue watching"))
        XCTAssertTrue(script.contains("file is ready for download"))
        XCTAssertTrue(script.contains("tap to proceed"))
        XCTAssertTrue(script.contains("window.confirm"))
        XCTAssertTrue(script.contains("candidate.querySelector('video, iframe')"))
        XCTAssertTrue(script.contains("fotty_set_content_mode"))
        XCTAssertTrue(script.contains("object-fit:"))
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

    func testCurrentChampionsLeagueOfficialFeedNamesResolveToReviewedClubs() {
        let officialNames = [
            "Club Brugge KV", "Como 1907", "FC Internazionale Milano", "FK Bodø/Glimt",
            "FK Shakhtar Donetsk", "Fenerbahçe SK", "Feyenoord Rotterdam", "Galatasaray SK",
            "Lille OSC", "PAE AEK", "Racing Club de Lens", "Real Betis Balompié",
            "SK Slavia Praha", "SSC Napoli", "Sabah FK", "Sporting Clube de Portugal",
            "ŠK Slovan Bratislava",
        ]
        for name in officialNames {
            XCTAssertTrue(
                FootballCompetitionCatalog.contains(name, in: .championsLeague),
                "Unrecognized official Champions League club: \(name)"
            )
        }
        XCTAssertEqual(
            FootballDataPolicy.normalizedTeamMatchKey("Sporting Clube de Portugal"),
            FootballDataPolicy.normalizedTeamMatchKey("Sporting CP")
        )
        XCTAssertEqual(
            FootballDataPolicy.normalizedTeamMatchKey("PAE AEK"),
            FootballDataPolicy.normalizedTeamMatchKey("AEK Athens")
        )
    }

    @MainActor
    func testOfficialChampionsLeagueScheduleCreatesTruthfulSourceFreeCatalogRows() throws {
        let kickoff = Date(timeIntervalSince1970: 1_788_885_900)
        let match = FootballMatch(
            id: 2001,
            apiFootballFixtureId: nil,
            utcDate: ISO8601DateFormatter().string(from: kickoff),
            status: .timed,
            matchday: 1,
            stage: "LEAGUE_STAGE",
            group: nil,
            homeTeam: FootballTeam(id: 1, name: "PAE AEK", shortName: nil, tla: nil, crest: "https://example.com/aek.png"),
            awayTeam: FootballTeam(id: 2, name: "LASK Linz", shortName: nil, tla: nil, crest: "https://example.com/lask.png"),
            score: MatchScore(winner: nil, duration: nil, fullTime: nil, halfTime: nil),
            competition: MatchCompetition(id: 2001, name: "UEFA Champions League", code: "CL", emblem: nil, country: nil),
            referees: nil,
            events: nil
        )

        let rows = AnalyticalDataEngine.officialScheduleEvents(
            from: [match],
            competition: .championsLeague
        )
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.id, "2001")
        XCTAssertEqual(row.homeName, "PAE AEK")
        XCTAssertEqual(row.awayName, "LASK Linz")
        XCTAssertEqual(row.kickoffDate, kickoff)
        XCTAssertTrue(row.sources?.isEmpty == true)
        XCTAssertFalse(MatchStartPolicy(event: row, now: kickoff.addingTimeInterval(-60)).canAttemptPlayback)
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

    func testOfficialFPLMapperIncludesActiveAndExplicitRecentFinishedFixtures() throws {
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
        let fetchedAt = try XCTUnwrap(CatalogISO8601DateParser.date("2026-08-23T16:10:00Z"))

        let mapped = OfficialFPLScoreProvider.mapLiveFixtures(
            fixtures,
            teams: teams,
            fetchedAt: fetchedAt
        )

        let match = try XCTUnwrap(mapped.first)
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped.last?.fixture.status, .fullTime)
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

    func testRecoveryPolicyPreservesAttemptBeforeConsideringFailover() {
        func input(
            reachable: Bool = true,
            nativeHandoff: Bool = false,
            webEmbed: Bool = true,
            forcedWebEmbed: Bool = false,
            stall: Bool = false,
            startupRetries: Int = 0,
            stallRetries: Int = 0,
            reason: String = "Playback failed to start"
        ) -> LivePlaybackRecoveryPolicy.Input {
            .init(
                reason: reason,
                countsAsStall: stall,
                isNetworkReachable: reachable,
                isNativeHandoff: nativeHandoff,
                isWebEmbed: webEmbed,
                isForcedWebEmbed: forcedWebEmbed,
                webStartupRetryCount: startupRetries,
                webStallRetryCount: stallRetries
            )
        }

        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(for: input(reachable: false)),
            .waitForNetwork(.network)
        )
        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(for: input(nativeHandoff: true, webEmbed: false)),
            .returnNativeHandoffToWeb(.startupTimeout)
        )
        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(for: input(webEmbed: false)),
            .tryWebFallback(.startupTimeout)
        )
        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(for: input(stall: true)),
            .retryWebStall(.stalled)
        )
        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(for: input()),
            .retryWebStartup(.startupTimeout)
        )
        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(for: input(startupRetries: 1)),
            .exhaustSource(.startupTimeout)
        )
        XCTAssertEqual(
            LivePlaybackRecoveryPolicy.action(
                for: input(reason: "Broadcast is unavailable")
            ),
            .exhaustSource(.providerUnavailable)
        )
    }

    func testTransportPolicyDistinguishesExpiredProviderCertificateFromEmptyCatalog() {
        let failure = StreamTransportFailurePolicy.makeFailure(
            providerName: "CoreMedia",
            code: .serverCertificateHasBadDate,
            technicalMessage: "The certificate for this server is invalid.",
            defaultCategory: .manifestUnreachable,
            defaultUserMessage: "No playable stream is available.",
            fallbackAllowed: true
        )

        XCTAssertEqual(failure.category, .providerSecurityFailure)
        XCTAssertEqual(
            failure.userMessage,
            StreamTransportFailurePolicy.secureConnectionUnavailableMessage
        )
        XCTAssertTrue(failure.retryable)
        XCTAssertEqual(failure.redactedMetadata["transport_result"], "provider_security_failure")
    }

    func testTransportPolicyRecognizesFoundationNSErrorWithoutURLErrorBridge() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.serverCertificateUntrusted.rawValue
        )

        XCTAssertEqual(
            StreamTransportFailurePolicy.urlErrorCode(from: error),
            .serverCertificateUntrusted
        )
    }

    func testTransportPolicyPreservesOrdinaryNetworkClassification() {
        let failure = StreamTransportFailurePolicy.makeFailure(
            providerName: "CoreMedia",
            code: .timedOut,
            technicalMessage: "Timed out.",
            defaultCategory: .manifestUnreachable,
            defaultUserMessage: "Try again.",
            fallbackAllowed: true
        )

        XCTAssertEqual(failure.category, .providerTimeout)
        XCTAssertEqual(failure.userMessage, "Try again.")
        XCTAssertTrue(failure.retryable)
    }

    func testTransportPolicyPrefersSecurityFailureWhenEveryEmbedFails() {
        let empty = StreamFailure(
            category: .providerReturnedEmpty,
            technicalMessage: "Empty player.",
            userMessage: "No playable stream is available.",
            retryable: true,
            fallbackAllowed: true
        )
        let security = StreamFailure(
            category: .providerSecurityFailure,
            technicalMessage: "Expired certificate.",
            userMessage: StreamTransportFailurePolicy.secureConnectionUnavailableMessage,
            retryable: true,
            fallbackAllowed: true
        )

        XCTAssertEqual(
            StreamTransportFailurePolicy.mostActionableFailure(in: [empty, security])?.category,
            .providerSecurityFailure
        )
    }

    func testDirectProviderFailureCopyDoesNotLeakOneProviderAsTheWholeSearch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Fotty/Core/Internal/HybridStreamProvider.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Score808 has not listed a matching player"))
        XCTAssertFalse(source.contains("Score808 could not be checked just now"))
        XCTAssertTrue(source.contains("checked the available broadcast sources"))
    }

    func testSourcePolicyKeepsNativeMediaOutOfWebEmbedPlayback() throws {
        let embed = StreamSource(
            url: try XCTUnwrap(URL(string: "https://provider.example/embed/game")),
            quality: "live",
            provider: "Provider"
        )
        let manifest = StreamSource(
            url: try XCTUnwrap(URL(string: "https://embed.provider.example/live/game.m3u8")),
            quality: "live",
            provider: "Embed Provider",
            headers: ["X-Fotty-Web-Embed": "true"]
        )
        let headerMarked = StreamSource(
            url: try XCTUnwrap(URL(string: "https://provider.example/watch/game")),
            quality: "live",
            provider: "Provider",
            headers: ["X-Fotty-Web-Embed": "true"]
        )

        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(embed))
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(manifest))
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(headerMarked))
    }

    @MainActor
    func testCSDeliveryModeIgnoresNestedURLShape() throws {
        let web = StreamSession(
            matchID: "routing", playableURL: try XCTUnwrap(URL(string:
                "https://addon.example/watch?url=https%3A%2F%2Fvideo.example%2Fmaster.m3u8")),
            streamType: .unknown, providerName: "CS1",
            requiredHeaders: ["X-Fotty-Web-Embed": "true"]
        )
        let native = StreamSession(
            matchID: "routing", playableURL: try XCTUnwrap(URL(string:
                "https://embed.addon.example/api/manifest?url=https%3A%2F%2Fvideo.example%2Fembed%2Fgame")),
            streamType: .hls, providerName: "CS2"
        )

        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(web.legacySource))
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(web))
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(native))

        let event = AnalyticalDataEngine.EventReference(
            id: "routing", title: "CS routing test", category: "football",
            date: 0, poster: nil, popular: false, teams: nil, sources: nil
        )
        let slot = MultiLiveSlot(event: event, sessions: [web, native])
        XCTAssertTrue(slot.isWebEmbed(web.legacySource))
        XCTAssertFalse(slot.isWebEmbed(native.legacySource))
    }

    func testDirectNativeRecoveryIsBoundedAndCannotInventAWebFallback() {
        var input = LivePlaybackRecoveryPolicy.Input(
            reason: "HTTP 503", countsAsStall: false, isNetworkReachable: true,
            isNativeHandoff: false, isWebEmbed: false, isForcedWebEmbed: false,
            webStartupRetryCount: 0, webStallRetryCount: 0, isDirectMedia: true
        )
        guard case .retryNativeStartup = LivePlaybackRecoveryPolicy.action(for: input) else {
            return XCTFail("Direct native media must retry its native transport")
        }
        input.nativeStartupRetryCount = 1
        guard case .exhaustSource = LivePlaybackRecoveryPolicy.action(for: input) else {
            return XCTFail("Native retry must be bounded")
        }
    }

    func testStructuredHTTPFailuresAreNotElapsedStartupTimeouts() {
        for (status, expected) in [
            (401, LivePlaybackFailureKind.accessDenied), (403, .accessDenied),
            (404, .providerUnavailable), (410, .providerUnavailable), (503, .sourceFailure)
        ] {
            XCTAssertEqual(LivePlaybackFailureKind.classify(
                reason: "Source failed to start", countsAsStall: false, isNetworkReachable: true,
                structuredFailure: .init(httpStatus: status)), expected, "HTTP \(status)")
        }
        XCTAssertEqual(LivePlaybackFailureKind.classify(
            reason: "No decoded frame before startup timeout", countsAsStall: false,
            isNetworkReachable: true, structuredFailure: .init()), .startupTimeout)
        XCTAssertEqual(LivePlaybackFailureKind.classify(
            reason: "CoreMedia code 404", countsAsStall: false, isNetworkReachable: true,
            structuredFailure: .init()), .unknown,
            "An untyped numerical code is neither an HTTP response nor an elapsed timeout")
        XCTAssertEqual(LivePlaybackFailureKind.classify(
            reason: "HTTP 404", countsAsStall: false, isNetworkReachable: true), .startupTimeout,
            "Callers outside the opted-in single-stream path retain their existing policy")
    }

    func testStructuredClientRejectionsDoNotBlindlyRetryNativeOrWebSources() {
        for status in [400, 401, 403, 404, 410, 429] {
            for web in [false, true] {
                let input = LivePlaybackRecoveryPolicy.Input(
                    reason: "Player item failed", countsAsStall: false, isNetworkReachable: true,
                    isNativeHandoff: false, isWebEmbed: web, isForcedWebEmbed: web,
                    webStartupRetryCount: 0, webStallRetryCount: 0, isDirectMedia: !web,
                    structuredFailure: .init(httpStatus: status))
                let expected: LivePlaybackFailureKind = [401, 403].contains(status) ? .accessDenied : .providerUnavailable
                XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: input), .exhaustSource(expected),
                    "HTTP \(status) must not reload the same rejected delivery; web=\(web)")
            }
        }
    }

    func testStructuredTransientAndDecodeFailuresKeepTheExistingRetryBudget() {
        var input = LivePlaybackRecoveryPolicy.Input(
            reason: "Player item failed", countsAsStall: false, isNetworkReachable: true,
            isNativeHandoff: false, isWebEmbed: false, isForcedWebEmbed: false,
            webStartupRetryCount: 0, webStallRetryCount: 0, isDirectMedia: true,
            structuredFailure: .init(httpStatus: 503))
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: input), .retryNativeStartup(.sourceFailure))
        input.nativeStartupRetryCount = 1
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: input), .exhaustSource(.sourceFailure))

        input.nativeStartupRetryCount = 0
        input.structuredFailure = .init(category: .decode)
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: input), .retryNativeStartup(.decodeFailure))
        input.nativeStartupRetryCount = 1
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: input), .exhaustSource(.decodeFailure))
        input.structuredFailure = .init(category: .unsupported)
        input.nativeStartupRetryCount = 0
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: input), .exhaustSource(.unsupportedSource))
    }

    func testStructuredRecoveryStillPreservesNetworkWaitAndOwnedWebHandoff() {
        let offline = LivePlaybackRecoveryPolicy.Input(
            reason: "Player item failed", countsAsStall: false, isNetworkReachable: false,
            isNativeHandoff: false, isWebEmbed: false, isForcedWebEmbed: false,
            webStartupRetryCount: 0, webStallRetryCount: 0, isDirectMedia: true,
            structuredFailure: .init(httpStatus: 403))
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: offline), .waitForNetwork(.network))
        let handoff = LivePlaybackRecoveryPolicy.Input(
            reason: "Player item failed", countsAsStall: false, isNetworkReachable: true,
            isNativeHandoff: true, isWebEmbed: false, isForcedWebEmbed: false,
            webStartupRetryCount: 0, webStallRetryCount: 0,
            structuredFailure: .init(httpStatus: 403))
        XCTAssertEqual(LivePlaybackRecoveryPolicy.action(for: handoff), .returnNativeHandoffToWeb(.accessDenied),
            "A rejected candidate cannot retire its already-owned web playback")
    }

    func testStructuredFailureUsesCurrentResponseEvidenceAndRejectsHistoricalObservations() {
        let historical = [
            "native_log_domain": "http", "native_log_code": "403",
            "relay_failure_stage": "upstream_response", "relay_failure_kind": "http_status",
            "relay_http_status": "404", "relay_request_http_status": "200",
            "relay_request_outcome": "succeeded"
        ]
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(historical), .init(),
            "The latest relay/log observation can have recovered; it is not the current cause")
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails([
            "native_error_domain": "coremedia", "native_error_code": "404",
            "native_log_domain": "http", "native_log_code": "403"
        ]), .init())
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails([
            "native_error_domain": "http", "native_error_code": "404",
            "native_log_domain": "http", "native_log_code": "403"
        ]), .init(httpStatus: 404), "The current error chain wins over historical log data")
        let currentRelay = ["relay_failure_stage": "upstream_response",
                            "relay_failure_kind": "http_status", "relay_http_status": "403"]
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(currentRelay,
            currentRelayFailure: true), .init(httpStatus: 403))
    }

    func testStructuredFailureRejectsConflictingAndMalformedResponseEvidence() {
        let preparation = ["preparation_stage": "contract_validation", "preparation_reason": "http_status",
                           "preparation_http_status": "404"]
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(preparation), .init(httpStatus: 404))
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(preparation.merging([
            "native_error_domain": "http", "native_error_code": "403"
        ]) { _, next in next }), .init(), "Conflicting causal codes remain unclassified")
        for invalid in ["+403", "0403", "403\n", "999", "https://private.invalid/403"] {
            XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(
                preparation.merging(["preparation_http_status": invalid]) { _, next in next }), .init())
        }
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(
            preparation.merging(["preparation_reason": "proxy_health_check"]) { _, next in next }), .init(),
            "A neighbouring diagnostic field cannot claim an HTTP cause")
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails(
            preparation.merging(["preparation_stage": "private_stage"]) { _, next in next }), .init())
    }

    func testStructuredDiagnosticCategoriesKeepDecodeUnsupportedAndNetworkDistinct() {
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails([
            "native_error_domain": "avfoundation", "native_error_code": String(AVError.Code.decodeFailed.rawValue)
        ]), .init(category: .decode))
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails([
            "native_error_domain": "avfoundation", "native_error_code": String(AVError.Code.decoderNotFound.rawValue)
        ]), .init(category: .unsupported))
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails([
            "preparation_stage": "url_preparation", "preparation_reason": "transport_error",
            "preparation_error_domain": "url", "preparation_error_code": String(URLError.networkConnectionLost.rawValue)
        ]), .init(category: .network))
        XCTAssertEqual(LivePlaybackStructuredFailure.fromDiagnosticDetails([
            "preparation_stage": "contract_validation", "preparation_reason": "unsupported_content_type"
        ]), .init(category: .unsupported))
    }

    @MainActor
    func testNativeFailureRejectsReplacedItemAndStaleAttemptBeforeRetry() throws {
        let session = StreamSession(matchID: "native-diagnostic", playableURL: URL(string: "https://example.com/live.m3u8")!,
                                    streamType: .hls, providerName: "CS1")
        let model = LivePlayerViewModel(event: makePlaybackTestEvent(), providedSessions: [session],
                                       prepareAudioSession: { .completed([]) })
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource)
        let discarded = AVPlayerItem(asset: AVMutableComposition())
        let current = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: current)
        let attempt = model.loadRequestID
        model.handleNativeItemFailure(discarded, source: source, requestID: attempt,
                                      trigger: .failedToPlayToEnd, reportedError: URLError(.networkConnectionLost))
        model.handleNativeItemFailure(current, source: source, requestID: UUID(),
                                      trigger: .failedToPlayToEnd, reportedError: URLError(.networkConnectionLost))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player?.currentItem === current)
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
    }

    @MainActor
    func testNativeFatalNotificationCannotUndoExplicitPause() throws {
        let session = StreamSession(matchID: "native-diagnostic", playableURL: URL(string: "https://example.com/live.m3u8")!,
                                    streamType: .hls, providerName: "CS1")
        let model = LivePlayerViewModel(event: makePlaybackTestEvent(), providedSessions: [session],
                                       prepareAudioSession: { .completed([]) })
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource)
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .playing(.native))
        model.togglePlayPause()
        let attempt = model.loadRequestID
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
                                      trigger: .failedToPlayToEnd, reportedError: URLError(.networkConnectionLost))
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
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

    func testPlaybackFailuresDoNotOpenFamilyCircuit() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://www.score808live.tv/embed/delta/example/1")),
            quality: "live",
            provider: "Score808 #1",
            headers: ["X-Fotty-Nexus-Source": "delta"]
        )

        LiveSourceHealthStore.recordFailure(for: source, wasStall: false, reason: "HTTP 403")
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))

        LiveSourceHealthStore.recordFailure(for: source, wasStall: false, reason: "HTTP 403")
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
        XCTAssertEqual(LiveSourceHealthStore.automaticCandidates(in: [source]).first?.id, source.id)
    }

    func testDecodedPlaybackSuccessRetainsCoarsePositiveHealthMemory() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://www.score808live.tv/embed/admin/example/1")),
            quality: "live",
            provider: "Score808 #1"
        )

        LiveSourceHealthStore.recordFailure(for: source, wasStall: false)
        LiveSourceHealthStore.recordFailure(for: source, wasStall: false)
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))

        LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: 4_200)
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "score808", host: "www.score808live.tv"))
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
    func testWebEmbedSuspendsInBackgroundAndResumesSameAttempt() async throws {
        let viewModel = try makeWebPlayerViewModel(webBackgroundSuspensionDelay: {})
        defer { viewModel.cleanup() }
        let attemptID = viewModel.loadRequestID
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)

        viewModel.transition(to: .playing(.webEmbed), phase: "Playing")
        viewModel.handleScenePhaseChange(.background)
        await Task.yield()

        XCTAssertEqual(viewModel.playbackState, .paused(.webEmbed))
        XCTAssertTrue(viewModel.shouldSuspendWebPlayback)
        XCTAssertEqual(viewModel.connectionPhase, "Paused (Background)")
        XCTAssertTrue(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(viewModel.loadRequestID, attemptID)
        XCTAssertEqual(viewModel.activeSource?.id, sourceID)

        viewModel.handleScenePhaseChange(.active)

        XCTAssertEqual(viewModel.playbackState, .playing(.webEmbed))
        XCTAssertEqual(viewModel.connectionPhase, "Playing")
        XCTAssertFalse(viewModel.shouldSuspendWebPlayback)
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(viewModel.loadRequestID, attemptID)
        XCTAssertEqual(viewModel.activeSource?.id, sourceID)
    }

    @MainActor
    func testWebPictureInPictureWinsBackgroundSuspensionRace() async throws {
        let viewModel = try makeWebPlayerViewModel(webBackgroundSuspensionDelay: {})
        defer { viewModel.cleanup() }
        let attemptID = viewModel.loadRequestID

        viewModel.transition(to: .playing(.webEmbed), phase: "Playing")
        viewModel.handleScenePhaseChange(.background)
        viewModel.handleWebPictureInPictureActivityChanged(true)
        await Task.yield()

        XCTAssertEqual(viewModel.playbackState, .playing(.webEmbed))
        XCTAssertEqual(viewModel.connectionPhase, "PiP Active")
        XCTAssertTrue(viewModel.isWebPictureInPictureActive)
        XCTAssertTrue(viewModel.isPictureInPictureActive)
        XCTAssertTrue(viewModel.keepsPlaybackAliveInBackground)
        XCTAssertFalse(viewModel.shouldSuspendWebPlayback)
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(viewModel.loadRequestID, attemptID)
    }

    @MainActor
    func testRetiredWebAttemptCannotClearOrActivateCurrentPictureInPicture() throws {
        let model = try makeWebPlayerViewModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        model.handleWebPictureInPictureActivityChanged(true, sourceID: source, requestID: UUID())
        model.handleWebPictureInPictureActivityChanged(true, sourceID: UUID(), requestID: attempt)
        XCTAssertFalse(model.isWebPictureInPictureActive)
        model.handleWebPictureInPictureActivityChanged(true, sourceID: source, requestID: attempt)
        XCTAssertTrue(model.isWebPictureInPictureActive)
        model.handleWebPictureInPictureActivityChanged(false, sourceID: source, requestID: UUID())
        model.handleWebPictureInPictureActivityChanged(false, sourceID: UUID(), requestID: attempt)
        XCTAssertTrue(model.isWebPictureInPictureActive,
                      "Teardown of a retired document must not clear current PiP ownership")
        model.handleWebPictureInPictureActivityChanged(false, sourceID: source, requestID: attempt)
        XCTAssertFalse(model.isWebPictureInPictureActive)
    }

    @MainActor
    func testWebPictureInPicturePreventsNativeHandoff() throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }
        let sourceID = try XCTUnwrap(viewModel.activeSource?.id)
        let requestID = viewModel.loadRequestID
        viewModel.isVideoReadyForDisplay = true
        viewModel.transition(to: .playing(.webEmbed), phase: "Playing")
        viewModel.handleWebPictureInPictureActivityChanged(true)

        viewModel.handleNativePlaybackCandidate(
            NativeWebPlaybackCandidate(
                url: try XCTUnwrap(URL(string: "https://example.com/live.m3u8")),
                headers: [:]
            ),
            sourceID: sourceID,
            requestID: requestID
        )

        XCTAssertNil(viewModel.nativeHandoffTask)
        XCTAssertTrue(viewModel.nativeCandidateLedger.isEmpty)
        XCTAssertEqual(viewModel.playbackState, .playing(.webEmbed))
    }

    @MainActor
    func testWebEmbedPlayPauseIssuesAnExplicitMediaCommand() throws {
        let viewModel = try makeWebPlayerViewModel()
        defer { viewModel.cleanup() }
        let attempt = viewModel.loadRequestID
        viewModel.transition(to: .playing(.webEmbed), phase: "Playing")

        viewModel.togglePlayPause()

        let pauseCommand = try XCTUnwrap(viewModel.webPlaybackCommand)
        XCTAssertFalse(pauseCommand.shouldPlay)
        XCTAssertEqual(viewModel.playbackState, .paused(.webEmbed))
        XCTAssertEqual(viewModel.loadRequestID, attempt, "Pause must not replace the WebKit document")

        viewModel.togglePlayPause()

        let playCommand = try XCTUnwrap(viewModel.webPlaybackCommand)
        XCTAssertTrue(playCommand.shouldPlay)
        XCTAssertNotEqual(playCommand.id, pauseCommand.id)
        XCTAssertEqual(viewModel.playbackState, .playing(.webEmbed))
        XCTAssertEqual(viewModel.loadRequestID, attempt, "Play resumes the same document")
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
    func testWebTransportRejectsStaleAndBackgroundEventsAndPreservesPauseThroughHandoff() async throws {
        let model = try makeWebPlayerViewModel(webBackgroundSuspensionDelay: {})
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
        await Task.yield()
        model.handleWebEmbedTransportState(.playing, sourceID: source, requestID: attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertTrue(model.shouldResumeAfterForeground)
    }

    @MainActor
    func testObservedCurrentPauseCancelsPendingHandoffButStalePauseCannot() async throws {
        let model = try makeWebPlayerViewModel()
        var release: CheckedContinuation<Void, Never>?
        defer { release?.resume(); model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        model.isVideoReadyForDisplay = true
        model.transition(to: .preparingNativeHandoff, phase: "Playing")
        var committed = false
        let pending = Task { @MainActor in
            await withCheckedContinuation { release = $0 }
            guard !Task.isCancelled, model.userWantsPlayback,
                  model.loadRequestID == request, model.activeSource?.id == source,
                  model.playbackState == .preparingNativeHandoff else { return }
            committed = true
        }
        model.nativeHandoffTask = pending
        for _ in 0..<1_000 {
            if release != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(release)
        model.handleWebEmbedTransportState(.paused, sourceID: UUID(), requestID: request)
        model.handleWebEmbedTransportState(.paused, sourceID: source, requestID: UUID())
        XCTAssertFalse(pending.isCancelled)
        XCTAssertTrue(model.userWantsPlayback)
        model.handleWebEmbedTransportState(.paused, sourceID: source, requestID: request)
        XCTAssertTrue(pending.isCancelled)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        release?.resume(); release = nil
        await pending.value
        XCTAssertFalse(committed, "Late preparation completion must not promote after the observed pause")
        let records = FottyQualityStore.shared.records().filter {
            $0.name == "playback_causal_evidence" && $0.details["attempt_id"] == request.uuidString
                && $0.details["diagnostic_phase"] == "web_transport"
        }
        XCTAssertEqual(records.count, 1, "Rejected stale callbacks must not create current-owner evidence")
        XCTAssertEqual(records.first?.details["diagnostic_result"], "paused")
        XCTAssertEqual(records.first?.details["playback_intent"], "true", "Evidence captures intent before mutation")
        XCTAssertNil(records.first?.details["variant_key"])
        XCTAssertNil(model.webPlaybackCommand, "Observation must not manufacture a Play/Pause command")
    }

    @MainActor
    func testMutedHandoffPreflightNeverConfiguresOrActivatesSharedAudio() async throws {
        var configured = 0, activated = 0
        let model = try makeWebPlayerViewModel(prepareAudioSession: { activated += 1; return .completed([]) },
            configureAudioSession: { configured += 1; return .completed([]) })
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        let result = await model.prepareMutedNativeHandoffAudio(sourceID: source, requestID: request)
        XCTAssertEqual(result, .completed([]))
        XCTAssertEqual(configured, 0)
        XCTAssertEqual(activated, 0)
        let stale = await model.prepareMutedNativeHandoffAudio(sourceID: source, requestID: UUID())
        XCTAssertEqual(stale, .cancelled)
        let wrongSource = await model.prepareMutedNativeHandoffAudio(sourceID: UUID(), requestID: request)
        XCTAssertEqual(wrongSource, .cancelled)
        let cancelled = Task { await model.prepareMutedNativeHandoffAudio(sourceID: source, requestID: request) }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertEqual(cancelledResult, .cancelled)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNil(model.webPlaybackCommand)
        model.togglePlayPause()
        let paused = await model.prepareMutedNativeHandoffAudio(sourceID: source, requestID: request)
        XCTAssertEqual(paused, .cancelled)
        model.cleanup()
        let retired = await model.prepareMutedNativeHandoffAudio(sourceID: source, requestID: request)
        XCTAssertEqual(retired, .cancelled)
        XCTAssertEqual(configured, 0)
        XCTAssertEqual(activated, 0)
    }

    @MainActor
    func testExactWebRetirementActivatesBeforeUnmuteWithoutPlayingAgain() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        let item = player.currentItem
        XCTAssertTrue(player.isMuted)
        XCTAssertNil(model.nativeHandoffAudioClaimTask)
        model.handleWebPlaybackRetired(sourceID: UUID(), requestID: request)
        XCTAssertNil(model.nativeHandoffAudioClaimTask)
        model.handleWebPlaybackRetired(sourceID: source, requestID: UUID())
        XCTAssertNil(model.nativeHandoffAudioClaimTask)
        model.handleWebPlaybackRetired(sourceID: source, requestID: request)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        XCTAssertTrue(player.isMuted)
        model.handleWebPlaybackRetired(sourceID: source, requestID: request)
        XCTAssertEqual(gate.pendingCount, 1, "Duplicate retirement must not restart the claim")
        gate.completeAll()
        await claim.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
    }

    @MainActor
    func testFailedHandoffAudioActivationDoesNotLiftMuteOrFailOver() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        gate.completeAll(.completed([.init(stage: .activation, code: -100)]))
        await claim.value
        XCTAssertTrue(player.isMuted)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertTrue(model.userWantsPlayback)
    }

    @MainActor
    func testLateHandoffAudioClaimCannotUndoPauseReplacementOrRevocation() async throws {
        for revocation in ["pause", "replacement", "item", "attempt", "focus"] {
            let gate = HandoffAudioPreparationGate()
            let (model, player) = try makeAdoptedHandoffModel(prepareAudio: gate.wait)
            defer { model.cleanup(); gate.completeAll() }
            model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
            let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
            await waitForHandoffAudio { gate.pendingCount == 1 }
            var replacement: HandoffAudioSpyPlayer?
            switch revocation {
            case "pause": model.togglePlayPause()
            case "replacement":
                model.setViewingAudioEnabled(false)
                let next = HandoffAudioSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
                model.player = next
                replacement = next
            case "item": player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
            case "attempt": model.cancelLoading()
            default: model.setViewingAudioEnabled(false)
            }
            gate.completeAll()
            await claim.value
            XCTAssertTrue((replacement ?? player).isMuted, revocation)
            XCTAssertEqual(player.playCount, 0, revocation)
            XCTAssertEqual(replacement?.playCount ?? 0, 0, revocation)
            if revocation == "pause" { XCTAssertFalse(model.userWantsPlayback) }
        }
    }

    @MainActor
    func testOldFocusClaimCannotLiftNewClaimMuteBeforeItsOwnActivation() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        let old = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        model.setViewingAudioEnabled(false)
        model.setViewingAudioEnabled(true)
        let current = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 2 }
        gate.completeFirst()
        await old.value
        XCTAssertTrue(player.isMuted)
        gate.completeAll()
        await current.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertEqual(player.playCount, 0)
    }

    @MainActor
    func testPausedHandoffFocusStaysPausedButExplicitAVKitPlayCanClaimAudioWithoutDuplicatePlay() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(audible: false, prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        XCTAssertNil(model.nativeHandoffAudioClaimTask)
        model.togglePlayPause()
        model.setViewingAudioEnabled(true)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertNil(model.nativeHandoffAudioClaimTask)
        XCTAssertEqual(gate.pendingCount, 0)
        XCTAssertTrue(player.isMuted)
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)
        session.controlsAreActive = true
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        gate.completeAll()
        await claim.value
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertEqual(player.playCount, 0, "AVKit already issued Play; audio claim cannot issue another")
    }

    @MainActor
    func testOrdinaryNativeStartStillActivatesRatherThanUsingCandidateConfiguration() async throws {
        var activated = 0, configured = 0
        let event = makePlaybackTestEvent()
        let session = StreamSession(matchID: event.id, playableURL: URL(string: "https://example.invalid/native.m3u8")!,
            streamType: .hls, providerName: "CS1", requiredHeaders: [:])
        let model = LivePlayerViewModel(event: event, providedSessions: [session],
            prepareAudioSession: { activated += 1; return .completed([]) },
            configureAudioSession: { configured += 1; return .completed([]) })
        defer { model.cleanup() }
        let player = HandoffAudioSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.player = player
        let started = await model.requestPlaybackStart(player: player)
        XCTAssertTrue(started)
        XCTAssertEqual(activated, 1)
        XCTAssertEqual(configured, 0)
        XCTAssertEqual(player.playCount, 1)
    }

    @MainActor
    func testOldResumeActivationCannotUnmuteAChangedAudioFocusClaim() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(audible: false, prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        let request = model.loadRequestID, item = player.currentItem
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: request)
        model.togglePlayPause()
        model.setViewingAudioEnabled(true)
        model.togglePlayPause()
        let resume = try XCTUnwrap(model.audioPreparationTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        model.setViewingAudioEnabled(false)
        model.setViewingAudioEnabled(true)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 2 }
        gate.completeFirst()
        await resume.value
        XCTAssertTrue(player.isMuted, "Old focus's successful Play gate cannot release the newer audio claim")
        XCTAssertEqual(player.playCount, 1, "The explicit Fotty Play remains exactly one command")
        gate.completeAll()
        await claim.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertEqual(player.playCount, 1)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertTrue(player.currentItem === item)
    }

    @MainActor
    func testSuccessfulPiPPreparationCanReleaseHeldHandoffAudioWithoutPlay() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        model.isPictureInPictureAvailable = true
        model.togglePictureInPicture()
        let pip = try XCTUnwrap(model.pictureInPicturePreparationTask)
        await waitForHandoffAudio { gate.pendingCount == 2 }
        gate.completeFirst(.cancelled)
        await claim.value
        XCTAssertTrue(player.isMuted)
        gate.completeAll()
        await pip.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertNotNil(model.pictureInPictureRequestID)
        XCTAssertEqual(player.playCount, 0)
    }

    @MainActor
    func testInlinePiPPlayingCanClaimHeldHandoffAudioWithoutDuplicatePlay() async throws {
        let gate = HandoffAudioPreparationGate()
        let (model, player) = try makeAdoptedHandoffModel(audible: false, prepareAudio: gate.wait)
        defer { model.cleanup(); gate.completeAll() }
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        model.togglePlayPause()
        model.setViewingAudioEnabled(true)
        model.isPictureInPictureActive = true
        model.handleNativeTimeControlStatusChanged(.playing)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        model.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertEqual(gate.pendingCount, 1, "Repeated PiP state cannot restart an in-flight audio claim")
        gate.completeAll()
        await claim.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(player.playCount, 0)
    }

    @MainActor
    func testUnavailableIsolationRetainsPlayingWebWithoutStartingAutomaticProbe() throws {
        let model = try makeWebPlayerViewModel(nativeAudioIsolationBackend:
            .init(isSupported: false, setDisconnected: { _, _ in XCTFail("Unavailable API called"); return false }))
        defer { model.cleanup() }
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        let request = model.loadRequestID, source = try XCTUnwrap(model.activeSource?.id)
        model.handleNativePlaybackCandidate(.init(url: URL(string: "https://example.invalid/live.m3u8")!, headers: [:]),
            sourceID: source, requestID: request)
        XCTAssertNil(model.nativeHandoffTask)
        XCTAssertTrue(model.nativeCandidateLedger.isEmpty)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertNil(model.webPlaybackCommand)
    }

    @MainActor
    func testCandidateIsolationAcknowledgementRejectsPauseReplacementAndCancellation() async throws {
        for revoke in ["pause", "item", "cancel", "cleanup"] {
            let gate = NativeAudioIsolationTestGate()
            let model = try makeWebPlayerViewModel(nativeAudioIsolationBackend: gate.backend)
            defer { model.cleanup(); gate.finishAll() }
            model.transition(to: .playing(.webEmbed), phase: "Playing")
            let player = HandoffAudioSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
            let preparing = Task { await model.prepareNativeCandidateAudioIsolation(player: player,
                sourceID: source, requestID: request) }
            await waitForHandoffAudio { gate.pendingCount == 1 }
            XCTAssertEqual(gate.calls, [true])
            XCTAssertEqual(player.playCount, 0)
            switch revoke {
            case "pause": model.togglePlayPause()
            case "item": player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
            case "cleanup": model.cleanup()
            default: model.cancelLoading()
            }
            gate.completeNext()
            let isolated = await preparing.value
            XCTAssertNil(isolated, "A stale disconnect ACK cannot admit candidate Play: \(revoke)")
            XCTAssertEqual(player.playCount, 0)
            XCTAssertNil(model.nativeHandoffSession)
        }
    }

    @MainActor
    func testAdoptedNativeWaitsForReconnectAndDisconnectWithoutReplacingOrPlaying() async throws {
        let gate = NativeAudioIsolationTestGate()
        let (model, player) = try await makeIsolatedAdoptedHandoff(gate: gate)
        defer { model.cleanup(); gate.finishAll() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID, item = player.currentItem
        model.handleWebPlaybackRetired(sourceID: source, requestID: request)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.pendingCount == 1 && gate.calls == [true, false] }
        XCTAssertTrue(player.isMuted)
        XCTAssertEqual(player.playCount, 0)
        gate.completeNext()
        await claim.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        let revoke = try XCTUnwrap(model.revokeViewingAudioForTransfer())
        XCTAssertTrue(player.isMuted)
        await waitForHandoffAudio { gate.calls == [true, false, true] }
        XCTAssertFalse(revoke.isSatisfied)
        gate.completeNext()
        let revoked = await revoke.wait()
        XCTAssertTrue(revoked)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
    }

    @MainActor
    func testLateAdoptedReconnectReconcilesPauseReplacementAndCleanupToDisconnected() async throws {
        for revoke in ["pause", "player", "item", "cancel", "cleanup"] {
            let gate = NativeAudioIsolationTestGate()
            let (model, player) = try await makeIsolatedAdoptedHandoff(gate: gate)
            defer { model.cleanup(); gate.finishAll() }
            let isolation = try XCTUnwrap(model.nativeAudioIsolation)
            model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
            let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
            await waitForHandoffAudio { gate.calls == [true, false] }
            switch revoke {
            case "pause": model.togglePlayPause()
            case "player": model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            case "item": player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
            case "cleanup": model.cleanup()
            default: model.cancelLoading()
            }
            XCTAssertTrue(player.isMuted)
            gate.completeNext()
            await waitForHandoffAudio { gate.calls == [true, false, true] }
            gate.completeNext()
            await claim.value
            let final = try XCTUnwrap(isolation.currentBarrier)
            let settled = await final.wait()
            XCTAssertTrue(settled)
            XCTAssertTrue(gate.disconnected)
            XCTAssertEqual(player.playCount, 0, revoke)
        }
    }

    @MainActor
    func testSelectedPiPPlayReconnectsIsolatedNativeWithoutDuplicatePlay() async throws {
        let gate = NativeAudioIsolationTestGate()
        let (model, player) = try await makeIsolatedAdoptedHandoff(gate: gate, audible: false)
        defer { model.cleanup(); gate.finishAll() }
        let item = player.currentItem, request = model.loadRequestID
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: request)
        model.togglePlayPause()
        model.setViewingAudioEnabled(true)
        XCTAssertEqual(gate.calls, [true], "Choosing a paused pane must not reconnect or start it")
        model.isPictureInPictureActive = true
        model.handleNativeTimeControlStatusChanged(.playing)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await waitForHandoffAudio { gate.calls == [true, false] }
        XCTAssertTrue(player.isMuted)
        gate.completeNext()
        await claim.value
        XCTAssertEqual(player.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, request)
    }

    @MainActor
    func testReturningIsolatedNativeToWebKeepsSuspensionUntilAckAndDoesNotMisattributeOldApiWork() async throws {
        let gate = NativeAudioIsolationTestGate()
        let (model, _) = try await makeIsolatedAdoptedHandoff(gate: gate)
        defer { model.cleanup(); gate.finishAll() }
        model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        await waitForHandoffAudio { gate.calls == [true, false] }
        model.resetFailoverTracking()
        model.loadCurrentSource()
        let newAttempt = model.loadRequestID, switching = try XCTUnwrap(model.loadTask)
        await waitForHandoffAudio { model.player == nil }
        XCTAssertTrue(model.shouldSuspendWebPlayback)
        model.handleScenePhaseChange(.active)
        XCTAssertTrue(model.shouldSuspendWebPlayback, "Foreground must not bypass native retirement")
        gate.completeNext()
        await waitForHandoffAudio { gate.calls == [true, false, true] }
        XCTAssertTrue(model.shouldSuspendWebPlayback)
        gate.completeNext()
        await switching.value
        XCTAssertFalse(model.shouldSuspendWebPlayback)
        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertEqual(model.loadRequestID, newAttempt)
        XCTAssertNil(model.webPlaybackCommand)
        let misattributed = FottyQualityStore.shared.records().filter {
            $0.details["attempt_id"] == newAttempt.uuidString
                && ["audio_isolation_requested", "audio_isolation_finished"].contains($0.details["diagnostic_phase"] ?? "")
        }
        XCTAssertTrue(misattributed.isEmpty, "Old controller reconciliation cannot borrow the new attempt's identity")
    }

    @MainActor
    func testSwitchingIsolatedHandoffToOrdinaryNativeAllocatesUnownedFreshPlayer() async throws {
        let gate = NativeAudioIsolationTestGate(), validation = HandoffAudioPreparationGate()
        let event = makePlaybackTestEvent()
        let web = StreamSession(matchID: event.id, playableURL: URL(string: "https://example.invalid/embed/old")!,
            streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        let native = StreamSession(matchID: event.id, playableURL: URL(string: "https://example.invalid/new.m3u8")!,
            streamType: .hls, providerName: "CS1", requiredHeaders: [:])
        let model = LivePlayerViewModel(event: event, providedSessions: [web, native],
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in _ = await validation.wait(); return .valid },
            nativeAudioIsolationBackend: gate.backend)
        defer { model.cleanup(); gate.finishAll(); validation.completeAll(.cancelled) }
        model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == web.id })
        let item = AVPlayerItem(asset: AVMutableComposition()), oldPlayer = AVPlayer()
        oldPlayer.replaceCurrentItem(with: item)
        let isolation = NativePlayerAudioIsolation(player: oldPlayer, item: item, backend: gate.backend)
        let initial = isolation.request(disconnected: true)
        await waitForHandoffAudio { gate.pendingCount == 1 }
        gate.completeNext()
        let isolated = await initial.wait()
        XCTAssertTrue(isolated)
        model.nativeHandoffSession = StreamSession(id: web.id, matchID: event.id,
            playableURL: URL(string: "https://example.invalid/adopted.m3u8")!, streamType: .hls,
            providerName: "Score808", requiredHeaders: [:])
        model.holdNativeHandoffAudioUntilWebRetirement()
        model.player = oldPlayer
        model.adoptNativeAudioIsolation(isolation)
        model.didApplyLandscape = true
        model.transition(to: .playing(.native), phase: "Playing")
        model.handleWebPlaybackRetired(sourceID: web.id, requestID: model.loadRequestID)
        await waitForHandoffAudio { gate.calls == [true, false] }
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        gate.completeNext()
        await claim.value
        model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == native.id }))
        await waitForHandoffAudio { validation.pendingCount == 1 }
        let fresh = try XCTUnwrap(model.player), loading = try XCTUnwrap(model.loadTask)
        XCTAssertFalse(fresh === oldPlayer, "A disconnected or pending old player cannot host an ordinary native source")
        XCTAssertNil(model.nativeAudioIsolation)
        XCTAssertEqual(gate.calls, [true, false, true])
        gate.completeNext()
        XCTAssertTrue(model.player === fresh)
        model.cleanup()
        validation.completeAll(.cancelled)
        await loading.value
    }

    func testExecutedNativeTransferMonitorContainsObservationsWithoutChangingMedia() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing', video); messages = []; video.muted = false; video.volume = 0.37; var transferMessages = []; frames = [{contentWindow:{postMessage:m => transferMessages.push(m)}}]")
        context.evaluateScript("window.__fottySetNativeTransferSuspended(true, true); emit('pause', video); emit('waiting', video); video.currentTime += 1; emit('timeupdate', video); clock += 60000; intervals.forEach(t => t.fn())")
        XCTAssertEqual(context.evaluateScript("messages.length")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("video.muted")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("video.volume")?.toDouble(), 0.37)
        XCTAssertEqual(context.evaluateScript("transferMessages.some(m => m.type === 'fotty_native_transfer_suspended' && m.suspended === true)")?.toBool(), true)

        context.evaluateScript("window.__fottySetNativeTransferSuspended(false)")
        XCTAssertEqual(context.evaluateScript("messages.length")?.toInt32(), 0, "Release ACK is not decoded recovery")
        context.evaluateScript("video.pause()")
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'transport_state').at(-1).reason")?.toString(), "paused", "Unknown Pause outside transfer remains observable")
        XCTAssertEqual(context.evaluateScript("transferMessages.some(m => m.type === 'fotty_native_transfer_suspended' && m.suspended === false)")?.toBool(), true)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Unexpected transfer monitor exception")
    }

    func testExecutedNativeTransferReleaseCannotUndoExplicitAppPause() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing', video); window.__fottySetNativeTransferSuspended(true); window.__fottySetPlaying(false); messages = []")
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), true)
        context.evaluateScript("window.__fottySetNativeTransferSuspended(false)")
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), true, "Monitor release must never call Play")
        context.evaluateScript("video.paused = false; emit('playing', video)")
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), true, "Existing explicit-Pause protection remains authoritative")
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'transport_state').at(-1).reason")?.toString(), "paused")
        XCTAssertNil(context.exception)
    }

    func testExecutedNativeTransferAcquireStillReportsQueuedProviderPause() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing', video); messages = []; window.__fottySetNativeTransferSuspended(true, false); video.pause()")
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'transport_state').at(-1).reason")?.toString(), "paused")
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), true)
        XCTAssertNil(context.exception)
    }

    func testExecutedWebAudioRevocationReadsBackVideoAndSeparateAudioWithoutTransportCommands() throws {
        let attempt = UUID(), request = UUID()
        let context = try makeWebMonitorContext(attemptID: attempt)
        context.evaluateScript("emit('playing', video); var ownerID=messages.find(m=>m.type==='playback_started').documentID; messages=[]; video.muted=false; video.volume=0.7; var audio={muted:false,defaultMuted:false,volume:0.8}; var originalQuery=document.querySelectorAll; document.querySelectorAll=s=>s==='video, audio'?[video,audio]:originalQuery(s)")
        context.evaluateScript("window.__fottyRevokeAudio('\(request.uuidString)','\(attempt.uuidString)',ownerID)")
        XCTAssertEqual(context.evaluateScript("video.muted && audio.muted && video.defaultMuted && audio.defaultMuted && video.volume===0 && audio.volume===0")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("messages.find(m=>m.type==='audio_revocation_ack').requestID")?.toString(), request.uuidString)
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("messages.some(m=>m.type==='transport_state')")?.toBool(), false)
        context.evaluateScript("window.__fottyRevokeAudio('\(request.uuidString)','\(attempt.uuidString)',ownerID)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testExecutedWebAudioRevocationDoesNotAckFailedReadbackOrInventAnOwner() throws {
        let attempt = UUID()
        let context = try makeWebMonitorContext(attemptID: attempt)
        context.evaluateScript("emit('playing', video); var ownerID=messages.find(m=>m.type==='playback_started').documentID; messages=[]; Object.defineProperty(video,'muted',{get:()=>false,set:()=>{}})")
        context.evaluateScript("window.__fottyRevokeAudio('\(UUID().uuidString)','\(attempt.uuidString)',ownerID)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 0)
        context.evaluateScript("window.__fottyRevokeAudio('\(UUID().uuidString)','\(attempt.uuidString)','other-owner')")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), false)
        XCTAssertNil(context.exception)
    }

    func testExecutedWebAudioRevocationRequiresActualClaimedChildAckAndRejectsLateOrWrongReceipts() throws {
        let attempt = UUID(), request = UUID()
        let context = try makeWebMonitorContext(attemptID: attempt)
        context.evaluateScript(#"""
        var forwarded=[];
        var playerFrame={isConnected:true,nodeType:1,src:'https://content.test/embed',
            style:{display:'block',visibility:'visible',opacity:'1'},closest:()=>null,
            contentWindow:{postMessage:m=>forwarded.push(m)},getBoundingClientRect:video.getBoundingClientRect};
        frames=[playerFrame]; intervals.forEach(t=>t.fn()); messages=[];
        """#)
        context.evaluateScript("sendWindowMessage({type:'fotty_media_event',message:{type:'playback_started',documentID:'child-owner',attemptID:'\(attempt.uuidString)'}},playerFrame.contentWindow); messages=[]; window.__fottyRevokeAudio('\(request.uuidString)','\(attempt.uuidString)','child-owner')")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 0, "The parent cannot claim its child was muted")
        XCTAssertEqual(context.evaluateScript("forwarded.filter(m=>m.type==='fotty_revoke_audio').length")?.toInt32(), 1)
        context.evaluateScript("var ack={type:'audio_revocation_ack',requestID:'\(request.uuidString)',attemptID:'\(attempt.uuidString)',documentID:'child-owner'}; sendWindowMessage({type:'fotty_media_event',message:Object.assign({},ack,{requestID:'wrong'})},playerFrame.contentWindow); sendWindowMessage({type:'fotty_media_event',message:ack},{})")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 0)
        context.evaluateScript("sendWindowMessage({type:'fotty_media_event',message:ack},playerFrame.contentWindow); sendWindowMessage({type:'fotty_media_event',message:ack},playerFrame.contentWindow)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 1)
        context.evaluateScript("messages=[]; window.__fottyRevokeAudio('\(UUID().uuidString)','\(attempt.uuidString)','child-owner'); ack.requestID=forwarded.filter(m=>m.type==='fotty_revoke_audio').at(-1).requestID; clock+=2001; sendWindowMessage({type:'fotty_media_event',message:ack},playerFrame.contentWindow)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 0)
        XCTAssertNil(context.exception)
    }

    func testExecutedWebAudioRevocationPropagatesToChildAndNestedFramesOnceWithoutPlaying() throws {
        let attempt = UUID(), request = UUID()
        let child = try makeWebMonitorContext(isChildFrame: true, attemptID: attempt)
        child.evaluateScript("window.parent.postMessage=m=>messages.push(m.message); sendWindowMessage({type:'fotty_frame_eligibility',eligible:true},window.parent); emit('playing',video); var ownerID=messages.find(m=>m.type==='playback_started').documentID; messages=[]; var nested=[]; frames=[{contentWindow:{postMessage:m=>nested.push(m)}}]")
        child.evaluateScript("sendWindowMessage({type:'fotty_revoke_audio',requestID:'\(request.uuidString)',attemptID:'\(attempt.uuidString)',ownerID:ownerID,deadline:clock+2000},window.parent)")
        XCTAssertEqual(child.evaluateScript("messages.filter(m=>m.type==='audio_revocation_ack').length")?.toInt32(), 1)
        XCTAssertEqual(child.evaluateScript("nested.filter(m=>m.type==='fotty_revoke_audio').length")?.toInt32(), 1)
        XCTAssertEqual(child.evaluateScript("video.paused")?.toBool(), false)
        XCTAssertEqual(child.evaluateScript("video.muted && video.volume===0")?.toBool(), true)
        XCTAssertNil(child.exception)
    }

    func testExecutedWebMonitorReportsBoundedStagesWithoutChangingTransport() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing', video); emit('waiting', video); emit('waiting', video)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'diagnostic_stage' && m.reason === 'media_ready').length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'diagnostic_stage' && m.reason === 'buffering').length")?.toInt32(), 1)
        context.evaluateScript("clock += 15000; intervals.forEach(t => t.fn()); video.currentTime += 1; emit('timeupdate', video); emit('waiting', video)")
        XCTAssertEqual(context.evaluateScript("messages.filter(m => m.type === 'diagnostic_stage' && m.reason === 'buffering').length")?.toInt32(), 2)
        XCTAssertFalse(context.evaluateScript("video.paused")?.toBool() ?? true)
        XCTAssertNil(context.exception)
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

    func testExecutedWebMonitorKeepsAppPauseAgainstProgrammaticRestartButAllowsProviderPlayTap() throws {
        let context = try makeWebMonitorContext()
        // The tap that reveals Fotty's controls happens immediately before the
        // app Pause button. It must not be mistaken for a later provider Play.
        context.evaluateScript("emit('playing', video); emit('pointerdown', video); window.__fottySetPlaying(false); messages = []")
        XCTAssertTrue(context.evaluateScript("video.paused")!.toBool())

        // A provider script restarting media is not user intent. The monitor
        // must immediately restore the paused state.
        context.evaluateScript("video.paused = false; emit('playing', video)")
        XCTAssertTrue(context.evaluateScript("video.paused")!.toBool())
        XCTAssertEqual(
            context.evaluateScript("messages.filter(m => m.type === 'transport_state').at(-1).reason")?.toString(),
            "paused"
        )

        // The provider's own visible Play control remains usable.
        context.evaluateScript("clock += 2000; emit('pointerdown', video); video.play()")
        XCTAssertFalse(context.evaluateScript("video.paused")!.toBool())
        XCTAssertEqual(
            context.evaluateScript("messages.filter(m => m.type === 'transport_state').at(-1).reason")?.toString(),
            "playing"
        )
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

    func testWebMonitorReportsPictureInPictureForConfirmedOwner() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing',video); messages=[];")

        context.evaluateScript("document.pictureInPictureElement=video; emit('enterpictureinpicture',video);")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).type")?.toString(), "picture_in_picture_state")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).reason")?.toString(), "active")

        context.evaluateScript("document.pictureInPictureElement=null; video.webkitPresentationMode='inline'; emit('leavepictureinpicture',video);")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).type")?.toString(), "picture_in_picture_state")
        XCTAssertEqual(context.evaluateScript("messages.at(-1).reason")?.toString(), "inactive")
        XCTAssertNil(context.exception)
    }

    @MainActor
    func testDiagnosticStagesRejectStaleAttemptsAndDoNotProvePlayback() {
        var stages: [FottyPlaybackStage] = []
        var starts = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(
            onDiagnosticStage: { stage, _ in stages.append(stage) },
            onPlaybackStarted: { _ in starts += 1 })
        let attempt = UUID()
        coordinator.loadedAttemptID = attempt
        coordinator.handlePlaybackMessage(["type": "diagnostic_stage", "reason": "media_ready",
                                           "attemptID": UUID().uuidString, "documentID": "player"])
        XCTAssertTrue(stages.isEmpty)
        for _ in 0..<2 {
            coordinator.handlePlaybackMessage(["type": "diagnostic_stage", "reason": "media_ready",
                                               "attemptID": attempt.uuidString, "documentID": "player"])
        }
        XCTAssertEqual(stages, [.mediaReady])
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(coordinator.hasReportedPlayback)
        coordinator.handlePlaybackMessage(["type": "playback_started", "attemptID": attempt.uuidString,
                                           "documentID": "player"])
        coordinator.handlePlaybackMessage(["type": "diagnostic_stage", "reason": "buffering",
                                           "attemptID": attempt.uuidString, "documentID": "ad"])
        XCTAssertEqual(stages, [.mediaReady, .decoded])
        coordinator.handlePlaybackMessage(["type": "diagnostic_stage", "reason": "buffering",
                                           "attemptID": attempt.uuidString, "documentID": "player"])
        XCTAssertEqual(stages.last, .buffering)
        coordinator.invalidateLoading()
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

    @MainActor
    func testWebBridgeScopesAndDeduplicatesPictureInPictureState() {
        var states: [Bool] = []
        let coordinator = LiveWebEmbedPlayerView.Coordinator(
            onPictureInPictureActiveChanged: { states.append($0) }
        )
        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "broadcast"])
        coordinator.handlePlaybackMessage([
            "type": "picture_in_picture_state", "documentID": "ad", "reason": "active"
        ])
        coordinator.handlePlaybackMessage([
            "type": "picture_in_picture_state", "documentID": "broadcast", "reason": "active"
        ])
        coordinator.handlePlaybackMessage([
            "type": "picture_in_picture_state", "documentID": "broadcast", "reason": "active"
        ])
        coordinator.handlePlaybackMessage([
            "type": "picture_in_picture_state", "documentID": "broadcast", "reason": "inactive"
        ])

        XCTAssertEqual(states, [true, false])
        XCTAssertFalse(coordinator.isPictureInPictureActive)
    }

    func testWebMonitorRejectsHiddenSmallAndAdvertisingVideosBeforeBroadcast() throws {
        for change in ["ad.ad=true", "ad.style={display:'none'}", "ad.getBoundingClientRect=()=>({left:0,top:0,right:16,bottom:16})"] {
            let context = try makeWebMonitorContext()
            context.evaluateScript("video.currentTime=0; var ad=Object.assign({},video,{currentTime:100,currentSrc:'https://ads.test/preroll.mp4'}); extraVideos=[ad]; \(change); emit('playing',ad);")
            XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='playback_started')")!.toBool(), change)
            context.evaluateScript("video.currentSrc='https://content.test/live.m3u8'; video.currentTime=1; emit('timeupdate',video);")
            XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='playback_started')")!.toBool(), change)
            XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='native_candidate' && m.url.includes('ads.test'))")!.toBool())
            XCTAssertNil(context.exception)
        }
    }

    func testWebMonitorPrerollCanYieldToBroadcastAndCannotDonateItsURL() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("video.ad=true; video.currentSrc='https://ads.test/preroll.mp4'; emit('playing',video);")
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='playback_started')")!.toBool())
        context.evaluateScript("video.ad=false; video.currentSrc='https://content.test/live.m3u8'; video.currentTime=2; emit('timeupdate',video);")
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='native_candidate' && m.url==='https://content.test/live.m3u8')")!.toBool())
        context.evaluateScript("video.ad=true; video.currentSrc='https://ads.test/midroll.mp4'; video.currentTime=3; intervals.forEach(t=>t.fn());")
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='playback_released')")!.toBool())
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='native_candidate' && m.url.includes('ads.test'))")!.toBool())
        XCTAssertNil(context.exception)
    }

    func testWebMonitorResourceTrafficCannotDonateNativeCandidate() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("video.currentSrc='blob:opaque-broadcast'; emit('playing',video); performance.getEntriesByType=()=>[{name:'https://unrelated.test/video.m3u8'}]; intervals.forEach(t=>t.fn());")
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='native_candidate')")!.toBool())
        context.evaluateScript("video.currentSrc='https://content.test/owned.m3u8'; video.currentTime+=1; emit('timeupdate',video);")
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='native_candidate').at(-1).url")?.toString(), "https://content.test/owned.m3u8")
        XCTAssertNil(context.exception)
    }

    func testWebMonitorMSERequiresPlayerAPIToOwnTheSelectedElement() throws {
        for engine in ["jw", "vjs"] {
            let context = try makeWebMonitorContext()
            context.evaluateScript("video.currentSrc='blob:actual-media'; var ownsContainer=false; var container={id:'owned-player',contains:v=>v===video};")
            if engine == "jw" {
                context.evaluateScript("video.closest=s=>s==='.jwplayer'?container:null; window.jwplayer=()=>({getContainer:()=>ownsContainer?container:{},getPlaylistItem:()=>({file:'https://content.test/bound.m3u8'})});")
            } else {
                context.evaluateScript("video.closest=s=>s==='.video-js'?container:null; window.videojs={getPlayer:()=>({el:()=>ownsContainer?container:{},currentSource:()=>({src:'https://content.test/bound.m3u8'})})};")
            }
            context.evaluateScript("emit('playing',video);")
            XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='native_candidate')")!.toBool(), engine)
            context.evaluateScript("ownsContainer=true; video.currentTime+=1; emit('timeupdate',video);")
            XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='native_candidate').at(-1).url")?.toString(), "https://content.test/bound.m3u8", engine)
            XCTAssertNil(context.exception)
        }
    }

    func testDirectScore808ChildCannotOwnPlaybackButStillPausesItsMedia() throws {
        let context = try makeWebMonitorContext(isScore808Site: true, isChildFrame: true)
        context.evaluateScript("video.currentTime=4; emit('playing',video); window.__fottySetPlaybackSuspended(true);")
        XCTAssertTrue(context.evaluateScript("window.__fottyPlaybackMonitorInstalled")!.toBool())
        XCTAssertTrue(context.evaluateScript("video.paused")!.toBool())
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='playback_started'||m.type==='native_candidate')")!.toBool())
        XCTAssertNil(context.exception)
    }

    func testWebMonitorFiltersChildFramesAndReleasesRemovedFrameOwnership() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript(#"""
        var adFrame = {nodeType:1,isConnected:true,src:'https://ads.test/embed',contentWindow:{postMessage:()=>{}},closest:()=>null,
          getBoundingClientRect:()=>({left:0,top:0,right:16,bottom:16})};
        var playerFrame=Object.assign({},adFrame,{src:'https://content.test/embed',contentWindow:{postMessage:()=>{}},getBoundingClientRect:video.getBoundingClientRect});
        frames=[adFrame,playerFrame];
        sendWindowMessage({type:'fotty_media_event',message:{type:'playback_started',documentID:'ad'}},adFrame.contentWindow);
        sendWindowMessage({type:'fotty_media_event',message:{type:'stream_failed',documentID:'unconfirmed',reason:'stream is unavailable'}},playerFrame.contentWindow);
        sendWindowMessage({type:'fotty_media_event',message:{type:'playback_started',documentID:'match'}},playerFrame.contentWindow);
        """#)
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.documentID==='ad')")!.toBool())
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='stream_failed')")!.toBool())
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='playback_started' && m.documentID==='match')")!.toBool())
        context.evaluateScript("frames=[]; intervals.forEach(t=>t.fn());")
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='playback_released' && m.documentID==='match')")!.toBool())
        XCTAssertNil(context.exception)
    }

    func testWebMonitorPreservesOwnerWhenDocumentHidesBeforeSuspension() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing',video); messages=[]; document.hidden=true; window.__fottySetPlaybackSuspended(true); clock+=60000; intervals.forEach(t=>t.fn());")
        XCTAssertTrue(context.evaluateScript("video.paused")!.toBool())
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='playback_released'||m.type==='stream_failed')")!.toBool())
        context.evaluateScript("document.hidden=false; window.__fottySetPlaybackSuspended(false); clock+=2000; intervals.forEach(t=>t.fn());")
        XCTAssertFalse(context.evaluateScript("video.paused")!.toBool())
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='playback_released'||m.type==='stream_failed')")!.toBool())
        context.evaluateScript("video.currentTime+=1; emit('timeupdate',video);")
        XCTAssertNil(context.exception)
    }

    func testWebMonitorEndedRetainedPlayerYieldsToAdvancingReplacement() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript("emit('playing',video); var previous=video; previous.ended=true; video=Object.assign({},previous,{ended:false,currentTime:0}); extraVideos=[previous]; intervals.forEach(t=>t.fn()); video.currentTime=1; emit('timeupdate',video);")
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='playback_released')")!.toBool())
        XCTAssertEqual(context.evaluateScript("messages.filter(m=>m.type==='playback_started').length")?.toInt32(), 2)
        XCTAssertNil(context.exception)
    }

    func testWebMonitorIgnoresPageAdErrorButReportsOwnedPlayerError() throws {
        let context = try makeWebMonitorContext()
        context.evaluateScript(#"""
        emit('playing',video); messages=[];
        var playerContainer={querySelector:()=>null};
        var errorElement={textContent:'Media source unavailable',nodeType:1,closest:()=>null,
          getBoundingClientRect:()=>({width:200,height:30})};
        video.closest=s=>s==='.jwplayer, .video-js'?playerContainer:null;
        document.querySelector=()=>errorElement;
        document.body.innerText='stream is unavailable';
        observers.forEach(fn=>fn());
        """#)
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='stream_failed')")!.toBool())
        context.evaluateScript("playerContainer.querySelector=()=>errorElement; observers.forEach(fn=>fn());")
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='stream_failed')")!.toBool())
        XCTAssertNil(context.exception)
    }

    @MainActor
    func testWebBridgeAllowsReplacementOnlyAfterCurrentDocumentReleases() {
        var starts = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackStarted: { _ in starts += 1 })
        coordinator.handlePlaybackMessage(["type":"playback_started", "documentID":"first"])
        coordinator.handlePlaybackMessage(["type":"playback_released", "documentID":"unrelated"])
        XCTAssertEqual(coordinator.playbackDocumentID, "first")
        coordinator.handlePlaybackMessage(["type":"playback_started", "documentID":"second"])
        XCTAssertEqual(starts, 1)
        coordinator.handlePlaybackMessage(["type":"playback_released", "documentID":"first"])
        XCTAssertNil(coordinator.playbackDocumentID)
        XCTAssertNotNil(coordinator.pendingFailureTask, "Replacement startup remains bounded")
        coordinator.handlePlaybackMessage(["type":"playback_started", "documentID":"second"])
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(coordinator.playbackDocumentID, "second")
        XCTAssertNil(coordinator.pendingFailureTask)
    }

    @MainActor
    func testReusedWebPlayerReplacesMonitorForBothProviderSwitchDirections() throws {
        let controller = WKUserContentController()
        for (address, siteMode) in [
            ("https://www.score808live.tv/match/", true),
            ("https://shared-provider.example/embed/123", false),
            ("https://www.score808live.tv/match/", true)
        ] {
            LiveWebEmbedPlayerView.configurePlaybackMonitor(
                in: controller,
                url: try XCTUnwrap(URL(string: address)),
                isMuted: false,
                providerControlsAudio: true,
                isSuspended: false
            )
            XCTAssertEqual(controller.userScripts.count, 1, "Old provider rules must not accumulate")
            let script = try XCTUnwrap(controller.userScripts.first)
            XCTAssertTrue(script.source.contains("var score808Site = \(siteMode ? "true" : "false");"))
            XCTAssertEqual(script.injectionTime, .atDocumentStart)
            XCTAssertFalse(script.isForMainFrameOnly)
        }
    }

    @MainActor
    func testWebBridgeAcceptsOnlyReviewedCommittedDocumentsAndExactDeliveryIdentity() throws {
        let coordinator = LiveWebEmbedPlayerView.Coordinator()
        let original = try XCTUnwrap(URL(string: "https://player.example.test/embed?id=one"))
        coordinator.beginLoading(url: original, referer: original.absoluteString, attemptID: UUID())
        defer { coordinator.invalidateLoading() }

        XCTAssertTrue(coordinator.acceptCommittedDocument(original))
        let redirect = try XCTUnwrap(URL(string: "https://player.example.test/watch?id=two"))
        XCTAssertTrue(coordinator.acceptCommittedDocument(redirect), "An admitted same-origin HTTP redirect owns its committed document, not the old request path")
        XCTAssertEqual(coordinator.committedDocumentURL, redirect)
        XCTAssertFalse(coordinator.acceptCommittedDocument(try XCTUnwrap(URL(string: "https://unreviewed.example.test/watch"))))
        XCTAssertFalse(coordinator.acceptCommittedDocument(try XCTUnwrap(URL(string: "http://player.example.test/watch"))))
        XCTAssertFalse(coordinator.acceptCommittedDocument(try XCTUnwrap(URL(string: "https://player.example.test/ad.html"))))
        XCTAssertEqual(coordinator.committedDocumentURL, redirect)

        XCTAssertTrue(LiveWebEmbedPlayerView.Coordinator.sameDocumentURL(redirect, URL(string: redirect.absoluteString + "#controls")))
        XCTAssertFalse(LiveWebEmbedPlayerView.Coordinator.sameDocumentURL(redirect, original))
        XCTAssertFalse(LiveWebEmbedPlayerView.Coordinator.sameDocumentURL(redirect, URL(string: "https://player.example.test/watch?id=three")))
        XCTAssertFalse(LiveWebEmbedPlayerView.Coordinator.sameDocumentURL(redirect, URL(string: "https://player.example.test:8443/watch?id=two")))
    }

    func testWebMonitorTagsCurrentAttemptAndRejectsOldChildAttemptBeforeOwnership() throws {
        let attempt = UUID()
        let context = try makeWebMonitorContext(attemptID: attempt)
        context.evaluateScript("emit('playing',video);")
        XCTAssertEqual(context.evaluateScript("messages.find(m=>m.type==='playback_started').attemptID")?.toString(), attempt.uuidString)
        context.evaluateScript(#"""
        messages=[];
        var playerFrame={isConnected:true,nodeType:1,src:'https://content.test/embed',
          style:{display:'block',visibility:'visible',opacity:'1'},closest:()=>null,
          contentWindow:{postMessage:()=>{}},getBoundingClientRect:video.getBoundingClientRect};
        frames=[playerFrame]; intervals.forEach(t=>t.fn());
        sendWindowMessage({type:'fotty_media_event',message:{type:'playback_started',documentID:'old-child',attemptID:'old-attempt'}},playerFrame.contentWindow);
        """#)
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.documentID==='old-child')")!.toBool())
        context.evaluateScript("sendWindowMessage({type:'fotty_media_event',message:{type:'playback_started',documentID:'current-child',attemptID:'\(attempt.uuidString)'}},playerFrame.contentWindow);")
        XCTAssertEqual(context.evaluateScript("messages.find(m=>m.documentID==='current-child').attemptID")?.toString(), attempt.uuidString)
        XCTAssertNil(context.exception)
    }

    func testWebTeardownScriptSuspendsMainChildAndNestedChildWithOrWithoutTopMonitor() throws {
        for topMonitorAvailable in [true, false] {
            let context = try makeWebMonitorContext()
            context.evaluateScript(#"""
            emit('playing',video);
            var forwarded=[];
            frames=[{contentWindow:{postMessage:message=>forwarded.push(message)}}];
            """#)
            if !topMonitorAvailable { context.evaluateScript("delete window.__fottySetPlaybackSuspended;") }
            context.evaluateScript(LiveWebEmbedPlayerView.teardownScript)
            XCTAssertTrue(context.evaluateScript("video.paused")!.toBool())
            XCTAssertTrue(context.evaluateScript("forwarded.some(m=>m.type==='fotty_set_suspended'&&m.suspended===true)")!.toBool())
            let forwarded = try XCTUnwrap(context.evaluateScript("JSON.stringify(forwarded[0])")?.toString())

            let child = try makeWebMonitorContext(isChildFrame: true)
            child.evaluateScript("var nestedMessages=[]; frames=[{contentWindow:{postMessage:m=>nestedMessages.push(m)}}];")
            child.evaluateScript("sendWindowMessage(\(forwarded),window.parent);")
            XCTAssertTrue(child.evaluateScript("video.paused")!.toBool(), "The actual child monitor must receive and apply teardown suspension")
            XCTAssertTrue(child.evaluateScript("nestedMessages.some(m=>m.type==='fotty_set_suspended'&&m.suspended===true)")!.toBool(), "Suspension propagates beyond one frame level")
            XCTAssertNil(context.exception)
            XCTAssertNil(child.exception)
        }
    }

    @MainActor
    func testWebTeardownCancelsDeadlineBeforeNativePauseClosesPresentationAndReleasesDelegates() throws {
        var failures = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackStalled: { _ in failures += 1 })
        let view = TeardownRecordingWebView()
        coordinator.webView = view
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        coordinator.beginLoading(
            url: try XCTUnwrap(URL(string: "https://player.example.test/embed")), referer: "", attemptID: UUID()
        )
        let staleDeadline = try XCTUnwrap(coordinator.startupFailureTask)
        view.beforeNativePause = {
            XCTAssertNil(coordinator.startupFailureTask)
            XCTAssertNil(coordinator.pendingFailureTask)
            XCTAssertFalse(coordinator.isAcceptingMessages)
        }
        LiveWebEmbedPlayerView.dismantleUIView(view, coordinator: coordinator)
        XCTAssertEqual(view.events, ["pause-all-media", "close-presentations", "stop-loading"])
        XCTAssertNil(view.navigationDelegate)
        XCTAssertNil(view.uiDelegate)
        XCTAssertNil(coordinator.webView)
        staleDeadline.perform()
        XCTAssertEqual(failures, 0)
    }

    @MainActor
    func testReusedWebBridgeRejectsOldAttemptMessagesEvenForTheSameURL() throws {
        var starts = 0
        var taps = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(
            onSurfaceTapped: { taps += 1 }, onPlaybackStarted: { _ in starts += 1 }
        )
        let url = try XCTUnwrap(URL(string: "https://player.example.test/embed"))
        let oldAttempt = UUID()
        coordinator.beginLoading(url: url, referer: "", attemptID: oldAttempt)
        let oldDeadline = try XCTUnwrap(coordinator.startupFailureTask)
        let currentAttempt = UUID()
        coordinator.beginLoading(url: url, referer: "", attemptID: currentAttempt)
        defer { coordinator.invalidateLoading() }

        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "old", "attemptID": oldAttempt.uuidString])
        coordinator.handlePlaybackMessage(["type": "surface_tapped", "attemptID": oldAttempt.uuidString])
        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "missing-token"])
        oldDeadline.perform()
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(taps, 0)
        XCTAssertFalse(coordinator.hasReportedFailure)
        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "current", "attemptID": currentAttempt.uuidString])
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(coordinator.playbackDocumentID, "current")
        XCTAssertNil(coordinator.startupFailureTask)
    }

    @MainActor
    func testNativeWebStartupDeadlineReportsNoDocumentOrJavaScriptProgressOnlyOnce() throws {
        var failures: [String] = []
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackStalled: { failures.append($0) })
        coordinator.beginLoading(
            url: try XCTUnwrap(URL(string: "https://player.example.test/embed")), referer: "", attemptID: UUID()
        )
        defer { coordinator.invalidateLoading() }
        let deadline = try XCTUnwrap(coordinator.startupFailureTask)
        deadline.perform()
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].contains("Startup timeout"))
        XCTAssertNil(coordinator.startupFailureTask)
        deadline.perform()
        XCTAssertEqual(failures.count, 1)
    }

    @MainActor
    func testNativeWebStartupDeadlineStopsForDecodedPauseSuspensionAndDismantle() throws {
        let url = try XCTUnwrap(URL(string: "https://player.example.test/embed"))
        for stopReason in ["decode", "pause", "suspend", "dismantle"] {
            var failures = 0
            let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackStalled: { _ in failures += 1 })
            let attempt = UUID()
            coordinator.beginLoading(url: url, referer: "", attemptID: attempt)
            let deadline = try XCTUnwrap(coordinator.startupFailureTask)
            switch stopReason {
            case "decode":
                coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "owner", "attemptID": attempt.uuidString])
                coordinator.handlePlaybackMessage(["type": "picture_in_picture_state", "documentID": "owner", "reason": "active", "attemptID": attempt.uuidString])
            case "pause": coordinator.playbackCommandWillApply(WebPlaybackCommand(id: UUID(), shouldPlay: false))
            case "suspend":
                coordinator.lastSuspended = true
                coordinator.playbackSuspensionChanged(true)
            default: coordinator.invalidateLoading()
            }
            deadline.perform()
            XCTAssertEqual(failures, 0, stopReason)
            XCTAssertNil(coordinator.startupFailureTask, stopReason)
            if stopReason == "decode" { XCTAssertTrue(coordinator.isPictureInPictureActive) }
            if stopReason == "suspend" {
                coordinator.lastSuspended = false
                coordinator.playbackSuspensionChanged(false)
                try XCTUnwrap(coordinator.startupFailureTask).perform()
                XCTAssertEqual(failures, 1, "Foreground startup is bounded without counting background time")
            }
            coordinator.invalidateLoading()
        }
    }

    @MainActor
    func testNativeWebNavigationFailuresBelongOnlyToCurrentNonCancelledNavigation() throws {
        var failures = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackStalled: { _ in failures += 1 })
        let view = WKWebView()
        let url = try XCTUnwrap(URL(string: "https://player.example.test/embed"))
        coordinator.beginLoading(url: url, referer: "", attemptID: UUID())
        defer { coordinator.invalidateLoading() }
        let oldNavigation = try makeOfflineNavigation(in: view)
        let currentNavigation = try makeOfflineNavigation(in: view)
        coordinator.activeNavigation = currentNavigation
        coordinator.webView(view, didFailProvisionalNavigation: oldNavigation, withError: URLError(.timedOut))
        coordinator.webView(view, didFailProvisionalNavigation: currentNavigation, withError: URLError(.cancelled))
        XCTAssertNil(coordinator.pendingFailureTask)
        coordinator.webView(view, didFailProvisionalNavigation: currentNavigation, withError: URLError(.cannotFindHost))
        let pending = try XCTUnwrap(coordinator.pendingFailureTask)
        pending.perform()
        XCTAssertEqual(failures, 1)

        coordinator.beginLoading(url: url, referer: "", attemptID: UUID())
        coordinator.activeNavigation = try makeOfflineNavigation(in: view)
        coordinator.webView(view, didFail: currentNavigation, withError: URLError(.networkConnectionLost))
        pending.perform()
        XCTAssertEqual(failures, 1, "A prior document cannot fail the replaced source attempt")
        XCTAssertNil(coordinator.pendingFailureTask)
        coordinator.webView(view, didFail: coordinator.activeNavigation, withError: URLError(.networkConnectionLost))
        try XCTUnwrap(coordinator.pendingFailureTask).perform()
        XCTAssertEqual(failures, 2)
    }

    @MainActor
    func testApprovedProviderNavigationReprovesPlaybackButOldAdmissionCannotCrossSourceSwitch() throws {
        var pipStates: [Bool] = []
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPictureInPictureActiveChanged: { pipStates.append($0) })
        let view = WKWebView()
        let original = try XCTUnwrap(URL(string: "https://player.example.test/embed?source=one"))
        let currentAttempt = UUID()
        coordinator.beginLoading(url: original, referer: "", attemptID: currentAttempt)
        defer { coordinator.invalidateLoading() }
        coordinator.activeNavigation = try makeOfflineNavigation(in: view)
        XCTAssertTrue(coordinator.acceptCommittedDocument(original))
        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "owner", "attemptID": currentAttempt.uuidString])
        coordinator.handlePlaybackMessage(["type": "picture_in_picture_state", "documentID": "owner", "reason": "active", "attemptID": currentAttempt.uuidString])
        let replacement = try makeOfflineNavigation(in: view)
        XCTAssertTrue(coordinator.admitMainNavigationRequest(try XCTUnwrap(URL(string: "https://player.example.test/embed?auth=renewed"))))
        coordinator.webView(view, didStartProvisionalNavigation: replacement)
        XCTAssertTrue(coordinator.activeNavigation === replacement)
        XCTAssertFalse(coordinator.hasReportedPlayback)
        XCTAssertFalse(coordinator.isAcceptingMessages)
        XCTAssertNotNil(coordinator.startupFailureTask)
        XCTAssertFalse(coordinator.isPictureInPictureActive)
        XCTAssertEqual(pipStates, [true, false], "The old document cannot leave a false active-PiP claim after replacement")

        let stale = try makeOfflineNavigation(in: view)
        XCTAssertTrue(coordinator.admitMainNavigationRequest(original))
        coordinator.beginLoading(url: original, referer: "", attemptID: UUID())
        let newSourceNavigation = try makeOfflineNavigation(in: view)
        coordinator.activeNavigation = newSourceNavigation
        XCTAssertTrue(coordinator.admitMainNavigationRequest(original), "A new source can already have an admitted request when the old callback arrives")
        coordinator.webView(view, didStartProvisionalNavigation: replacement)
        XCTAssertTrue(coordinator.activeNavigation === newSourceNavigation, "The prior owned WKNavigation cannot consume a new source's admission ticket")
        coordinator.webView(view, didFail: replacement, withError: URLError(.timedOut))
        XCTAssertNil(coordinator.pendingFailureTask)
        XCTAssertTrue(coordinator.acceptCommittedDocument(original))
        let newProviderNavigation = try makeOfflineNavigation(in: view)
        coordinator.webView(view, didStartProvisionalNavigation: newProviderNavigation)
        XCTAssertTrue(coordinator.activeNavigation === newProviderNavigation, "The current admission remains available to its new navigation")
        coordinator.webView(view, didStartProvisionalNavigation: stale)
        XCTAssertTrue(coordinator.activeNavigation === newProviderNavigation, "Admission belongs to its load generation and is single-use")
        XCTAssertFalse(coordinator.admitMainNavigationRequest(try XCTUnwrap(URL(string: "https://unknown.example.test/embed"))))
    }

    @MainActor
    func testUnknownOldProviderStartCannotStealNewSelectedSourceBeforeFirstCommit() throws {
        let coordinator = LiveWebEmbedPlayerView.Coordinator()
        let view = WKWebView()
        let oldURL = try XCTUnwrap(URL(string: "https://player.example.test/embed?source=old"))
        coordinator.beginLoading(url: oldURL, referer: "", attemptID: UUID())
        coordinator.activeNavigation = try makeOfflineNavigation(in: view)
        XCTAssertTrue(coordinator.acceptCommittedDocument(oldURL))
        let unknownOldProviderNavigation = try makeOfflineNavigation(in: view)
        XCTAssertTrue(coordinator.admitMainNavigationRequest(try XCTUnwrap(URL(string: "https://player.example.test/watch?source=old"))))
        // B was approved but has never reached didStart, so it is not retired.
        let newURL = try XCTUnwrap(URL(string: "https://player.example.test/embed?source=new"))
        coordinator.beginLoading(url: newURL, referer: "", attemptID: UUID())
        defer { coordinator.invalidateLoading() }
        let selectedNavigation = try makeOfflineNavigation(in: view)
        coordinator.activeNavigation = selectedNavigation
        XCTAssertTrue(coordinator.admitMainNavigationRequest(newURL))
        coordinator.webView(view, didStartProvisionalNavigation: unknownOldProviderNavigation)
        XCTAssertTrue(coordinator.activeNavigation === selectedNavigation)
        XCTAssertFalse(coordinator.isAcceptingMessages)
        coordinator.webView(view, didFail: unknownOldProviderNavigation, withError: URLError(.timedOut))
        XCTAssertNil(coordinator.pendingFailureTask)
        coordinator.webView(view, didStartProvisionalNavigation: selectedNavigation)
        XCTAssertTrue(coordinator.activeNavigation === selectedNavigation)
        XCTAssertTrue(coordinator.acceptCommittedDocument(newURL), "The intended selected load still owns its first commit")
        XCTAssertEqual(coordinator.committedDocumentURL, newURL)
        XCTAssertTrue(coordinator.isAcceptingMessages)
    }

    @MainActor
    func testWebProcessTerminationRecoversOnlyTheOwningViewAndPreservesExplicitPause() async throws {
        var failures = 0
        var pipStates: [Bool] = []
        let coordinator = LiveWebEmbedPlayerView.Coordinator(
            onPlaybackStalled: { _ in failures += 1 },
            onPictureInPictureActiveChanged: { pipStates.append($0) }
        )
        let view = WKWebView()
        let unrelatedView = WKWebView()
        coordinator.webView = view
        let attempt = UUID()
        coordinator.beginLoading(
            url: try XCTUnwrap(URL(string: "https://player.example.test/embed")), referer: "", attemptID: attempt
        )
        defer { coordinator.invalidateLoading() }
        coordinator.handlePlaybackMessage(["type": "playback_started", "documentID": "owner", "attemptID": attempt.uuidString])
        coordinator.handlePlaybackMessage(["type": "picture_in_picture_state", "documentID": "owner", "reason": "active", "attemptID": attempt.uuidString])
        coordinator.webViewWebContentProcessDidTerminate(unrelatedView)
        XCTAssertNil(coordinator.pendingFailureTask)
        coordinator.playbackCommandWillApply(WebPlaybackCommand(id: UUID(), shouldPlay: false))
        coordinator.webViewWebContentProcessDidTerminate(view)
        XCTAssertEqual(pipStates, [true, false], "Terminated media cannot keep a false active-PiP claim")
        XCTAssertNil(coordinator.pendingFailureTask)
        XCTAssertEqual(failures, 0, "Process loss must not revoke the user's pause and start another source")
        coordinator.playbackCommandWillApply(WebPlaybackCommand(id: UUID(), shouldPlay: true))
        let resumed = expectation(description: "Queued UIView command leaves update before recovery")
        DispatchQueue.main.async { resumed.fulfill() }
        await fulfillment(of: [resumed], timeout: 1)
        try XCTUnwrap(coordinator.pendingFailureTask).perform()
        XCTAssertEqual(failures, 1)
    }

    @MainActor
    func testScore808MonitorIgnoresAdvertisingVideoAndUnrelatedNativeResource() throws {
        let context = try makeWebMonitorContext(isScore808Site: true)
        context.evaluateScript("""
        var ad = Object.assign({}, video, {currentTime:100,currentSrc:'https://ads.example.test/ad.mp4'});
        emit('timeupdate', ad);
        """)
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='playback_started')")!.toBool())
        context.evaluateScript("""
        video.currentSrc = 'https://media.example.test/live.m3u8';
        video.currentTime = 1;
        emit('timeupdate',video);
        performance.getEntriesByType = () => [{name:'https://ads.example.test/ad.mp4'}];
        clock += 500; video.currentTime += 1; intervals.forEach(t=>t.fn());
        """)
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='playback_started')")!.toBool())
        XCTAssertFalse(context.evaluateScript("messages.some(m=>m.type==='native_candidate' && m.url.includes('ads.example'))")!.toBool())
        XCTAssertTrue(context.evaluateScript("messages.some(m=>m.type==='native_candidate' && m.url==='https://media.example.test/live.m3u8')")!.toBool())
        XCTAssertNil(context.exception)
    }

    @MainActor
    func testWebEmbedContentModeChangesWithoutReloadingPlayback() throws {
        let context = try makeWebMonitorContext()
        XCTAssertEqual(
            context.evaluateScript("video.style.values['object-fit']")?.toString(),
            "contain"
        )

        context.evaluateScript(
            "sendWindowMessage({type:'fotty_set_content_mode',fill:true}, window)"
        )

        XCTAssertEqual(
            context.evaluateScript("video.style.values['object-fit']")?.toString(),
            "cover"
        )
        XCTAssertNil(context.exception)
    }

    @MainActor
    private func makeOfflineNavigation(in webView: WKWebView) throws -> WKNavigation {
        // WKNavigation's public NSObject initializer does not construct its
        // underlying WebKit API object. Use a real, wholly offline page load so
        // identity/delegate tests also have a valid native object lifetime.
        let navigation = try XCTUnwrap(webView.loadHTMLString(
            "<!doctype html><html><head><title>Offline fixture</title></head><body></body></html>",
            baseURL: nil
        ))
        webView.stopLoading()
        return navigation
    }

    private func makeWebMonitorContext(isScore808Site: Bool = false, isChildFrame: Bool = false, attemptID: UUID? = nil) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        var window = this; window.top = window; window.parent = window;
        window.innerWidth = 320; window.innerHeight = 180;
        window.getComputedStyle = node => node.style || {display:'block',visibility:'visible',opacity:'1'};
        var clock = 1000; Date.now = () => clock;
        var messages = [], listeners = {}, timers = [], intervals = [];
        var location = {href:'https://example.test/player'};
        var navigator = {userAgent:'test'};
        // JSContext has no browser URL class. These ownership tests use only
        // absolute URLs; relative URL normalization is not simulated here.
        function URL(value) {
            if (typeof value !== 'string' || !(value.startsWith('https://') || value.startsWith('http://'))) throw new Error('absolute URL required');
            this.href = value;
        }
        window.webkit = {messageHandlers:{fottyPlayerBridge:{postMessage:m => messages.push(m)}}};
        var windowListeners = {};
        window.addEventListener = (type, fn) => (windowListeners[type] ||= []).push(fn);
        function sendWindowMessage(data, source) { (windowListeners.message || []).forEach(fn=>fn({data,source})); }
        var performance = {getEntriesByType:() => []};
        function emit(type, target) { (listeners[type] || []).forEach(l => l.fn({target:target})); }
        var video = {
            paused:false, ended:false, currentTime:1, currentSrc:'', readyState:4,
            videoWidth:320, videoHeight:180, tagName:'VIDEO', isConnected:true, nodeType:1,
            style:{values:{},setProperty:function(name,value){this.values[name]=value;}},
            getBoundingClientRect:()=>({left:0,top:0,right:320,bottom:180,width:320,height:180}),
            closest:function(selector){return this.ad && selector.includes('data-ad') ? {} : null;},
            setAttribute:function(){},
            getAttribute:function(){return null;}, querySelectorAll:()=>[],
            pause:function(){this.paused=true; emit('pause', this);},
            play:function(){
                if (!this.rejectPlay) { this.paused=false; emit('playing', this); }
                return {then:(ok, bad) => this.rejectPlay ? bad() : ok(), catch:function(){}};
            }
        };
        var frames = [], extraVideos = [];
        var document = {
            hidden:false, body:{innerText:''}, documentElement:{},
            querySelectorAll:s => s === 'iframe' ? frames : s === 'video' || s === 'video, audio' ? [video,...extraVideos] : s === '#my-video video, video#my-video_html5_api' ? [video] : [],
            querySelector:() => null,
            addEventListener:(t, fn, options) => (listeners[t] ||= []).push({fn,options})
        };
        var observers=[];
        function MutationObserver(fn) {observers.push(fn);this.observe = function(){};}
        function setTimeout(fn, delay) {timers.push({fn,delay});}
        function setInterval(fn, delay) {intervals.push({fn,delay});}
        var lastClick;
        function clickAnchor(target, href) {
            lastClick = {target:{closest:() => ({target,href})}, prevented:false, stopped:false,
                preventDefault:function(){this.prevented=true;}, stopImmediatePropagation:function(){this.stopped=true;}};
            for (var listener of listeners.click) { listener.fn(lastClick); if(lastClick.stopped) break; }
        }
        """#)
        if isChildFrame { context.evaluateScript("window.top={}; window.parent={postMessage:()=>{}};") }
        if isScore808Site { context.evaluateScript("video.currentTime = 0;") }
        context.evaluateScript(LiveWebEmbedPlayerView.playbackMonitorScript(isMuted: true, providerControlsAudio: true, isSuspended: false, isScore808Site: isScore808Site, attemptID: attemptID))
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
    func testPiPCapableNativePlayerSurvivesBackgroundCallbackRace() throws {
        let viewModel = try makeNativePlayerViewModel()
        defer { viewModel.cleanup() }
        let item = AVPlayerItem(url: try XCTUnwrap(URL(string: "https://example.com/live.m3u8")))
        let player = AVPlayer(playerItem: item)
        viewModel.player = player
        viewModel.handlePictureInPictureAvailabilityChanged(true)
        viewModel.transition(to: .playing(.native), phase: "Playing")

        // iOS can send scene background before AVKit reports PiP active.
        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.playbackState, .playing(.native))
        XCTAssertEqual(viewModel.connectionPhase, "Starting PiP")
        XCTAssertTrue(viewModel.keepsPlaybackAliveInBackground)
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)
        XCTAssertEqual(player.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)

        viewModel.handlePictureInPictureFailure("PiP could not start", isBackgrounded: true)
        XCTAssertEqual(viewModel.playbackState, .paused(.native))
        XCTAssertTrue(viewModel.shouldResumeAfterForeground)
    }

    @MainActor
    func testSystemPiPPlayPauseSynchronizesNativePlaybackState() throws {
        let viewModel = try makeNativePlayerViewModel()
        defer { viewModel.cleanup() }
        viewModel.transition(to: .playing(.native), phase: "Playing")
        viewModel.handlePictureInPictureActivityChanged(true)

        viewModel.handleNativeTimeControlStatusChanged(.paused)
        XCTAssertEqual(viewModel.playbackState, .paused(.native))
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)

        viewModel.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertEqual(viewModel.playbackState, .playing(.native))
        XCTAssertEqual(viewModel.connectionPhase, "PiP Active")
        XCTAssertFalse(viewModel.shouldResumeAfterForeground)
    }

    @MainActor
    func testReferenceHLSMaintainsOneAttemptDuringSoak() async throws {
#if FOTTY_PLAYBACK_SOAK && !targetEnvironment(simulator)
        let referenceURL = try XCTUnwrap(URL(
            string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
        ))
        let referenceSession = StreamSession(
            matchID: "fotty-physical-soak",
            title: "Fotty Physical Playback Soak",
            playableURL: referenceURL,
            streamType: .hls,
            providerName: "Score808 Reference",
            requiredHeaders: [:],
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

        #if FOTTY_PLAYBACK_SOAK_SHORT
        let defaultSoakDurationSeconds = 20
        #elseif targetEnvironment(macCatalyst)
        let defaultSoakDurationSeconds = 120
        #else
        let defaultSoakDurationSeconds = 20
        #endif
        let requestedSoakDuration = ProcessInfo.processInfo.environment["FOTTY_PLAYBACK_SOAK_SECONDS"]
            .flatMap(Int.init)
        let soakDurationSeconds = requestedSoakDuration ?? defaultSoakDurationSeconds
        XCTAssertTrue(
            (20...600).contains(soakDurationSeconds),
            "FOTTY_PLAYBACK_SOAK_SECONDS must be between 20 and 600 seconds"
        )

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

        XCTAssertTrue(source.contains("Button { sendQuery(prompt) } label:"))
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
        XCTAssertNotNil(now.addingTimeInterval(72 * 3_600).liveKickoffRelativeSnippet(relativeTo: now))
        XCTAssertNil(now.addingTimeInterval(72 * 3_600 + 1).liveKickoffRelativeSnippet(relativeTo: now))
        XCTAssertNil(now.addingTimeInterval(-36 * 3_600 - 1).liveKickoffRelativeSnippet(relativeTo: now))
    }

    @MainActor
    func testCatalogRetainsExactlyThreeFutureDaysAndRejectsAnythingLater() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let edge = makeScheduleEvent(id: "three-day-edge", kickoff: now.addingTimeInterval(72 * 3_600))
        let later = makeScheduleEvent(id: "after-three-days", kickoff: now.addingTimeInterval(72 * 3_600 + 1))

        XCTAssertTrue(edge.passesNearTermLiveListWindow(at: now))
        XCTAssertFalse(later.passesNearTermLiveListWindow(at: now))
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
    func testNativeCandidateDiscoveryIsPassiveInSingleAndWatchTwo() throws {
        for context: ViewingPlaybackContext in [.single, .watchTwo(engine: .web)] {
            var validations = 0
            let model = try makeExplicitTransferTestModel(validate: { _, _ in
                validations += 1
                return .invalid("Discovery must never validate media")
            })
            defer { model.cleanup() }
            model.setViewingPlaybackContext(context)
            let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
            let candidate = NativeWebPlaybackCandidate(url: URL(string: "https://example.invalid/passive.m3u8")!, headers: [:])

            model.handleNativePlaybackCandidate(candidate, sourceID: source, requestID: request)

            XCTAssertEqual(validations, 0)
            XCTAssertNil(model.player)
            XCTAssertNil(model.nativeHandoffTask)
            XCTAssertNil(model.nativeHandoffSession)
            XCTAssertFalse(model.isNativePlaybackTransferInProgress)
            XCTAssertTrue(model.nativeCandidateLedger.isEmpty)
            XCTAssertEqual(model.loadRequestID, request)
            XCTAssertEqual(model.activeSource?.id, source)
            XCTAssertEqual(model.playbackState, .playing(.webEmbed))
            XCTAssertNil(model.webPlaybackCommand)
            XCTAssertEqual(model.canRequestNativePlaybackTransfer, context == .single)
        }
    }

    @MainActor
    func testWatchTwoRejectsExplicitNativeTransferBeforeValidationOrDecoderCreation() throws {
        var validations = 0
        let model = try makeExplicitTransferTestModel(validate: { _, _ in
            validations += 1
            return .invalid("Watch Two must not start a native transfer")
        })
        defer { model.cleanup() }
        model.setViewingPlaybackContext(.watchTwo(engine: .web))
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        model.handleNativePlaybackCandidate(.init(url: URL(string: "https://example.invalid/watch-two.m3u8")!, headers: [:]),
            sourceID: source, requestID: request)

        model.requestNativePlaybackTransfer()

        XCTAssertFalse(model.canRequestNativePlaybackTransfer)
        XCTAssertFalse(model.isNativePlaybackTransferInProgress)
        XCTAssertNil(model.nativeHandoffTask)
        XCTAssertNil(model.player)
        XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
    }

    @MainActor
    func testIncompatibleManualLoadAndRecoveryCallbackPreserveOwnedWatchTwoAttempt() throws {
        let model = try makeExplicitTransferTestModel(includeNative: true)
        defer { model.cleanup() }
        XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .web)))
        let originalIndex = model.currentSourceIndex
        let nativeIndex = try XCTUnwrap(model.sessions.firstIndex { $0.streamType == .hls })
        let nativeSource = model.sessions[nativeIndex].legacySource
        let originalSource = try XCTUnwrap(model.activeSource)
        let request = model.loadRequestID
        let nativeScore = LiveSourceHealthStore.score(for: nativeSource)
        let originalScore = LiveSourceHealthStore.score(for: originalSource)

        model.selectSourceManually(at: nativeIndex)
        XCTAssertEqual(model.currentSourceIndex, originalIndex)
        // A stale UI/raw index must also be fenced by actual load admission.
        model.currentSourceIndex = nativeIndex
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        model.handleSourceStartupFailure(nativeSource, reason: "Provider reports this broadcast is unavailable",
            expectedRequestID: request)

        XCTAssertEqual(model.currentSourceIndex, originalIndex)
        XCTAssertEqual(model.activeSource?.id, originalSource.id)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.player)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertNil(model.lastFailureReason)
        XCTAssertEqual(LiveSourceHealthStore.score(for: nativeSource), nativeScore)
        XCTAssertEqual(LiveSourceHealthStore.score(for: originalSource), originalScore)
    }

    @MainActor
    func testWatchTwoAutomaticRecoveryDoesNotTryOrPenalizeOtherEngineSource() throws {
        let model = try makeExplicitTransferTestModel(includeNative: true)
        defer { model.cleanup() }
        XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .web)))
        let original = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        let native = try XCTUnwrap(model.sessions.first { $0.streamType == .hls }).legacySource
        let nativeScore = LiveSourceHealthStore.score(for: native)

        model.handleSourceStartupFailure(original, reason: "Provider reports this broadcast is unavailable",
            expectedRequestID: request)

        XCTAssertEqual(model.activeSource?.id, original.id)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.player)
        XCTAssertEqual(model.failedSourceIDs, [original.id], "Only the actually attempted failed source is penalized")
        XCTAssertFalse(model.failedSourceIDs.contains(native.id))
        XCTAssertEqual(LiveSourceHealthStore.score(for: native), nativeScore)
        XCTAssertEqual(model.playbackState, .failed)
    }

    @MainActor
    func testNativeWatchTwoRecoveryCannotForceOpaqueSourceIntoWebEngine() throws {
        let event = makePlaybackTestEvent()
        let session = StreamSession(matchID: event.id, title: "Opaque Native Route",
            playableURL: URL(string: "https://example.invalid/opaque-live")!, streamType: .unknown,
            providerName: "Score808")
        let model = LivePlayerViewModel(event: event, providedSessions: [session], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("No audio activation expected"); return .completed([]) },
            configureAudioSession: { XCTFail("No audio configuration expected"); return .completed([]) },
            validateNativeSource: { _, _ in XCTFail("No media validation expected"); return .invalid("Unexpected validation") })
        defer { model.cleanup() }
        XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .native)))
        model.transition(to: .playing(.native), phase: "Playing")
        let source = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        let score = LiveSourceHealthStore.score(for: source)

        model.handleSourceStartupFailure(source, reason: "Startup timeout: no decoded video", expectedRequestID: request)

        XCTAssertFalse(model.forceWebEmbedSourceIDs.contains(source.id))
        XCTAssertFalse(model.isUsingWebEmbed)
        XCTAssertEqual(model.sessions[model.currentSourceIndex].id, source.id)
        XCTAssertEqual(model.activeSource?.id, source.id)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.player)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertEqual(LiveSourceHealthStore.score(for: source), score)
        XCTAssertEqual(model.playbackState, .failed)
    }

    @MainActor
    func testOriginalWebReturnForWatchTwoPreservesAcceptedPauseAndExactEndpoint() async throws {
        let gate = NativeAudioIsolationTestGate()
        let (model, player) = try await makeIsolatedAdoptedHandoff(gate: gate)
        defer { model.cleanup(); gate.finishAll() }
        let original = model.sessions[model.currentSourceIndex]
        model.togglePlayPause()
        XCTAssertFalse(model.userWantsPlayback)

        model.setViewingPlaybackContext(.watchTwo(engine: .web))
        let load = try XCTUnwrap(model.loadTask)
        await load.value

        XCTAssertNil(model.nativeHandoffSession)
        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertEqual(model.sessions[model.currentSourceIndex].id, original.id)
        XCTAssertEqual(model.sessions[model.currentSourceIndex].playableURL, original.playableURL)
        XCTAssertEqual(model.activeSession?.playableURL, original.playableURL)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertTrue(model.isWebPlaybackUserPaused)
        XCTAssertEqual(model.webPlaybackCommand?.shouldPlay, false)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertEqual(player.playCount, 0)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
    }

    @MainActor
    func testExplicitRetryRenewsFailedNativeRetirementBeforeUnblockingOriginalWeb() async throws {
        let gate = NativeAudioIsolationTestGate()
        let (model, _) = try await makeIsolatedAdoptedHandoff(gate: gate)
        defer { model.cleanup(); gate.finishAll() }
        let original = model.sessions[model.currentSourceIndex]
        model.handleWebPlaybackRetired(sourceID: original.id, requestID: model.loadRequestID)
        await waitForHandoffAudio { gate.calls == [true, false] && gate.pendingCount == 1 }
        model.setViewingPlaybackContext(.watchTwo(engine: .web))
        let firstLoad = try XCTUnwrap(model.loadTask)
        gate.completeNext()
        await waitForHandoffAudio { gate.calls == [true, false, true] && gate.pendingCount == 1 }
        gate.completeNext(false)
        await firstLoad.value
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertTrue(model.shouldSuspendWebPlayback)
        let failedAttempt = model.loadRequestID

        model.selectSourceManually(at: model.currentSourceIndex)
        let retry = try XCTUnwrap(model.loadTask)
        await waitForHandoffAudio { gate.calls == [true, false, true, true] && gate.pendingCount == 1 }
        XCTAssertNotEqual(model.loadRequestID, failedAttempt)
        XCTAssertEqual(model.sessions[model.currentSourceIndex].id, original.id)
        XCTAssertEqual(model.sessions[model.currentSourceIndex].playableURL, original.playableURL)
        XCTAssertTrue(model.shouldSuspendWebPlayback, "An explicit retry is not a successful retirement ACK")
        gate.completeNext()
        await retry.value

        XCTAssertFalse(model.shouldSuspendWebPlayback)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
    }

    @MainActor
    func testNativeTransferRequiresExactHeldSuspensionAcknowledgement() async throws {
        let validation = ExplicitTransferValidationGate()
        let model = try makeExplicitTransferTestModel(validate: { _, _ in await validation.wait() })
        defer { model.cleanup(); validation.finishAll() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        model.handleNativePlaybackCandidate(.init(url: URL(string: "https://example.invalid/transfer.m3u8")!, headers: [:]),
            sourceID: source, requestID: request)
        model.requestNativePlaybackTransfer()
        let task = try XCTUnwrap(model.nativeHandoffTask)
        await waitForHandoffAudio { validation.pendingCount == 1 }
        // This simulates the ownership boundary, not AVAsset readiness/decoding.
        let id = try XCTUnwrap(model.beginNativeTransferSuspension(sourceID: source, requestID: request))
        XCTAssertTrue(model.nativeTransferIsCurrent(id, sourceID: source, requestID: request))
        XCTAssertFalse(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request))
        model.handleNativeTransferSuspensionChanged(UUID(), suspended: true, sourceID: source, requestID: request)
        model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: UUID(), requestID: request)
        model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: source, requestID: UUID())
        XCTAssertFalse(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request))

        model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: source, requestID: request)
        let acknowledged = await model.waitForNativeTransferSuspension(id, sourceID: source, requestID: request)
        XCTAssertTrue(acknowledged)
        XCTAssertTrue(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request))
        model.handleNativeTransferSuspensionChanged(id, suspended: false, sourceID: source, requestID: request)
        XCTAssertFalse(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request),
                       "A released interruption cannot authorize a delayed candidate Play")
        XCTAssertNil(model.player)
        XCTAssertNil(model.nativeHandoffSession)
        XCTAssertEqual(validation.callCount, 1)
        model.cancelNativePlaybackTransfer()
        validation.finishAll()
        await task.value
    }

    @MainActor
    func testNativeTransferAcknowledgementCannotOutlivePauseContextAttemptOrCancellation() async throws {
        for revoke in ["pause", "context", "attempt", "cancel", "cleanup"] {
            let validation = ExplicitTransferValidationGate()
            let model = try makeExplicitTransferTestModel(validate: { _, _ in await validation.wait() })
            defer { model.cleanup(); validation.finishAll() }
            let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
            model.handleNativePlaybackCandidate(.init(url: URL(string: "https://example.invalid/revoked-transfer.m3u8")!, headers: [:]),
                sourceID: source, requestID: request)
            model.requestNativePlaybackTransfer()
            let task = try XCTUnwrap(model.nativeHandoffTask)
            await waitForHandoffAudio { validation.pendingCount == 1 }
            let id = try XCTUnwrap(model.beginNativeTransferSuspension(sourceID: source, requestID: request))
            model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: source, requestID: request)
            XCTAssertTrue(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request))
            switch revoke {
            case "pause": model.togglePlayPause()
            case "context": model.setViewingPlaybackContext(.watchTwo(engine: .web))
            case "attempt": model.loadCurrentSource(ignoringCircuitBreaker: true)
            case "cleanup": model.cleanup()
            default: model.cancelNativePlaybackTransfer()
            }
            model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: source, requestID: request)
            XCTAssertFalse(model.nativeTransferIsCurrent(id, sourceID: source, requestID: request), revoke)
            XCTAssertFalse(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request), revoke)
            let accepted = await model.waitForNativeTransferSuspension(id, sourceID: source, requestID: request)
            XCTAssertFalse(accepted, revoke)
            validation.finishAll()
            await task.value
            XCTAssertNil(model.player, "A revoked acknowledgement must not create/Play a native candidate: \(revoke)")
            XCTAssertNil(model.nativeHandoffSession)
            XCTAssertEqual(validation.callCount, 1)
            if revoke == "pause" { XCTAssertFalse(model.userWantsPlayback) }
        }
    }

    @MainActor
    func testContextChangeAndCancellationSynchronouslyPauseRegisteredNativeCandidate() async throws {
        for revoke in ["context", "cancel"] {
            let validation = ExplicitTransferValidationGate()
            let model = try makeExplicitTransferTestModel(validate: { _, _ in await validation.wait() })
            defer { model.cleanup(); validation.finishAll() }
            let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
            model.handleNativePlaybackCandidate(.init(url: URL(string: "https://example.invalid/cancel-transfer.m3u8")!, headers: [:]),
                sourceID: source, requestID: request)
            model.requestNativePlaybackTransfer()
            let task = try XCTUnwrap(model.nativeHandoffTask)
            await waitForHandoffAudio { validation.pendingCount == 1 }
            // Simulate only candidate registration/suspension ownership. The
            // empty local item is not a ready or decoding native stream.
            let id = try XCTUnwrap(model.beginNativeTransferSuspension(sourceID: source, requestID: request))
            let candidate = NativeTransferCancellationSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            XCTAssertTrue(model.registerNativeTransferCandidate(candidate, transferID: id,
                sourceID: source, requestID: request))
            model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: source, requestID: request)
            XCTAssertEqual(candidate.pauseCount, 0)
            XCTAssertTrue(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request))

            if revoke == "context" { model.setViewingPlaybackContext(.watchTwo(engine: .web)) }
            else { model.cancelNativePlaybackTransfer() }

            // No yield/await: revocation must stop this decoder before the
            // caller can mount or promote any replacement Web surface.
            XCTAssertEqual(candidate.pauseCount, 1, revoke)
            XCTAssertFalse(model.isNativePlaybackTransferInProgress)
            XCTAssertFalse(model.canRequestNativePlaybackTransfer)
            model.handleNativeTransferSuspensionChanged(id, suspended: true, sourceID: source, requestID: request)
            XCTAssertFalse(model.nativeTransferSuspensionAcknowledged(id, sourceID: source, requestID: request))
            XCTAssertFalse(model.registerNativeTransferCandidate(candidate, transferID: id,
                sourceID: source, requestID: request), "A late callback cannot reacquire the revoked decoder")
            validation.finishAll()
            await task.value
            XCTAssertEqual(candidate.playCount, 0)
            XCTAssertNil(model.player)
            XCTAssertNil(model.nativeHandoffSession)
        }
    }

    private final class NativeTransferCancellationSpyPlayer: AVPlayer {
        private let counterLock = NSLock()
        private var pauses = 0
        private var plays = 0
        var pauseCount: Int { counterLock.lock(); defer { counterLock.unlock() }; return pauses }
        var playCount: Int { counterLock.lock(); defer { counterLock.unlock() }; return plays }
        override func pause() { counterLock.lock(); defer { counterLock.unlock() }; pauses += 1 }
        override func play() { counterLock.lock(); defer { counterLock.unlock() }; plays += 1 }
    }

    @MainActor
    private final class ExplicitTransferValidationGate {
        private var pending: [CheckedContinuation<StreamContractValidator.ValidationResult, Never>] = []
        private(set) var callCount = 0
        private var completed = false
        var pendingCount: Int { pending.count }
        func wait() async -> StreamContractValidator.ValidationResult {
            callCount += 1
            if completed { return .invalid("Controlled validation ended") }
            return await withCheckedContinuation { pending.append($0) }
        }
        func finishAll() {
            completed = true
            let completions = pending; pending.removeAll()
            completions.forEach { $0.resume(returning: .invalid("Controlled validation ended")) }
        }
    }

    @MainActor
    private func makeExplicitTransferTestModel(includeNative: Bool = false,
        validate: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult = { _, _ in
            XCTFail("This policy test must not validate or fetch media")
            return .invalid("Unexpected preparation")
        }) throws -> LivePlayerViewModel {
        let event = makePlaybackTestEvent()
        var sessions = [StreamSession(matchID: event.id, title: "Original Web",
            playableURL: URL(string: "https://example.invalid/original-web")!, streamType: .unknown,
            providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])]
        if includeNative {
            sessions.append(StreamSession(matchID: event.id, title: "Direct Native",
                playableURL: URL(string: "https://example.invalid/direct.m3u8")!, streamType: .hls,
                providerName: "Score808"))
        }
        let model = LivePlayerViewModel(event: event, providedSessions: sessions, ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Policy test must not activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Policy test must not configure audio"); return .completed([]) },
            validateNativeSource: validate,
            nativeAudioIsolationBackend: .init(isSupported: true, setDisconnected: { _, _ in
                XCTFail("Policy test must not change native audio participation"); return false
            }))
        let webIndex = try XCTUnwrap(model.sessions.firstIndex { LivePlaybackSourcePolicy.isWebEmbed($0) })
        model.currentSourceIndex = webIndex
        model.didApplyLandscape = true
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        return model
    }

    @MainActor
    func testUnstartedWebAudioRevocationDoesNotInventADocumentAcknowledgement() throws {
        let model = try makeExplicitTransferTestModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        XCTAssertFalse(model.didStartPlayback)

        XCTAssertNil(model.revokeViewingAudioForTransfer())

        XCTAssertFalse(model.isViewingAudioEnabled)
        XCTAssertNil(model.webAudioRevocationID)
        XCTAssertNil(model.captureWebAudioRevocationWaiter())
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertNil(model.player)
        XCTAssertNil(model.webPlaybackCommand)
    }

    @MainActor
    func testSingleAudioRetirementDoesNotWaitForAnUncreatedWebDocument() async throws {
        let model = try await makeMountedWebAudioRevocationModel(mounted: false)
        defer { model.cleanup() }
        XCTAssertTrue(model.didStartPlayback, "A selected/started attempt is not a mounted WebKit document")
        _ = model.revokeViewingAudioForTransfer()
        XCTAssertNil(model.captureWebAudioRevocationWaiter())
        XCTAssertNil(model.webAudioRevocationID)
    }

    @MainActor
    func testMountedWebAudioOwnerSurvivesReturnToSinglePlayback() async throws {
        let model = try await makeMountedWebAudioRevocationModel(mounted: false)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        model.setViewingPlaybackContext(.watchTwo(engine: .web))
        model.handleWebPlaybackMounted(sourceID: source, requestID: request)
        model.setViewingPlaybackContext(.single)
        model.cancelLoading()
        _ = model.revokeViewingAudioForTransfer()
        let wait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        model.handleWebPlaybackRetired(sourceID: source, requestID: request)
        let retired = await wait()
        XCTAssertTrue(retired, "Changing layout cannot erase an actual mounted audio owner")
    }

    @MainActor
    func testSingleAudioRetirementUsesMountedOwnerAfterLogicalAttemptCancellation() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        let source = try XCTUnwrap(model.activeSource?.id), mountedAttempt = model.loadRequestID
        model.cancelLoading()
        XCTAssertNotEqual(model.loadRequestID, mountedAttempt)
        _ = model.revokeViewingAudioForTransfer()
        let wait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        var notifications = 0
        model.onSingleWebAudioRetired = { notifications += 1 }
        model.cleanup()
        model.handleWebPlaybackRetired(sourceID: source, requestID: model.loadRequestID)
        XCTAssertEqual(notifications, 0)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter())
        model.handleWebPlaybackRetired(sourceID: source, requestID: mountedAttempt)
        let retired = await wait()
        XCTAssertTrue(retired)
        XCTAssertEqual(notifications, 1)
        model.handleWebPlaybackRetired(sourceID: source, requestID: mountedAttempt)
        XCTAssertEqual(notifications, 1, "Duplicate teardown cannot trigger another focus claim")
        XCTAssertFalse(model.isViewingAudioEnabled)
        XCTAssertNil(model.player)
    }

    @MainActor
    func testExactWebAudioRevocationAcknowledgementPreservesPlayingAndPausedTransport() async throws {
        for paused in [false, true] {
            let model = try await makeMountedWebAudioRevocationModel()
            defer { model.cleanup() }
            if paused { model.togglePlayPause() }
            let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
            let state = model.playbackState, command = model.webPlaybackCommand?.id
            let wanted = model.userWantsPlayback
            XCTAssertNil(model.revokeViewingAudioForTransfer())
            let id = try XCTUnwrap(model.webAudioRevocationID)
            let wait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
            XCTAssertFalse(model.isViewingAudioEnabled)
            XCTAssertTrue(model.webMute)

            model.handleWebAudioRevocationAcknowledged(id, sourceID: source, requestID: request)
            let acknowledged = await wait()

            XCTAssertTrue(acknowledged)
            XCTAssertNil(model.captureWebAudioRevocationWaiter())
            XCTAssertEqual(model.activeSource?.id, source)
            XCTAssertEqual(model.loadRequestID, request)
            XCTAssertEqual(model.playbackState, state)
            XCTAssertEqual(model.userWantsPlayback, wanted)
            XCTAssertEqual(model.isWebPlaybackUserPaused, paused)
            XCTAssertEqual(model.webPlaybackCommand?.id, command, "A mute ACK must not synthesize Play or Pause")
            XCTAssertNil(model.player)
            XCTAssertNil(model.nativeHandoffTask)
            XCTAssertNil(model.nativeHandoffSession)
            XCTAssertEqual(model.autoFailoverCount, 0)
            XCTAssertTrue(model.failedSourceIDs.isEmpty)
        }
    }

    @MainActor
    func testWrongWebAudioAcknowledgementsKeepCapturedWaitPendingAndCancellationIsFast() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        _ = model.revokeViewingAudioForTransfer()
        let id = try XCTUnwrap(model.webAudioRevocationID)
        let wait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())

        model.handleWebAudioRevocationAcknowledged(UUID(), sourceID: source, requestID: request)
        model.handleWebAudioRevocationAcknowledged(id, sourceID: UUID(), requestID: request)
        model.handleWebAudioRevocationAcknowledged(id, sourceID: source, requestID: UUID())
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter(), "Wrong identity must not mark the current lease acknowledged")
        let pending = Task { await wait() }
        pending.cancel()
        let cancelled = await pending.value
        XCTAssertFalse(cancelled, "A cancelled pending lease must not wait for its three-second deadline")
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter())

        model.handleWebAudioRevocationAcknowledged(id, sourceID: source, requestID: request)
        let acknowledged = await wait()
        XCTAssertTrue(acknowledged, "Capturing/cancelling one waiter does not cancel the owned acknowledgement")
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertNil(model.webPlaybackCommand)
        XCTAssertNil(model.player)
    }

    @MainActor
    func testCapturedOldWebAudioLeaseSettlesOnlyFromItsExactTeardownAfterSourceReplacement() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        defer { model.cleanup() }
        let oldSource = try XCTUnwrap(model.activeSource?.id), oldRequest = model.loadRequestID
        _ = model.revokeViewingAudioForTransfer()
        let oldID = try XCTUnwrap(model.webAudioRevocationID)
        let oldWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        model.selectSourceManually(at: (model.currentSourceIndex + 1) % model.sessions.count)
        let replacement = try XCTUnwrap(model.loadTask)
        await replacement.value
        let newSource = try XCTUnwrap(model.activeSource?.id), newRequest = model.loadRequestID
        model.handleWebPlaybackMounted(sourceID: newSource, requestID: newRequest)
        XCTAssertNotEqual(newSource, oldSource)
        XCTAssertNotEqual(newRequest, oldRequest)
        _ = model.revokeViewingAudioForTransfer()
        let newID = try XCTUnwrap(model.webAudioRevocationID)
        let newWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        XCTAssertNotEqual(newID, oldID)

        model.handleWebAudioRevocationAcknowledged(oldID, sourceID: oldSource, requestID: oldRequest)
        model.handleWebPlaybackRetired(sourceID: oldSource, requestID: newRequest)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter(), "An old/stale ACK cannot settle the new document's lease")
        let cancelledOldWait = Task { await oldWait() }
        cancelledOldWait.cancel()
        let oldWaitWasCancelled = await cancelledOldWait.value
        XCTAssertFalse(oldWaitWasCancelled)

        // Actual old teardown is allowed to settle the closure captured before
        // replacement, without touching the replacement's source or transport.
        model.handleWebPlaybackRetired(sourceID: oldSource, requestID: oldRequest)
        let oldRetired = await oldWait()
        XCTAssertTrue(oldRetired)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter())
        XCTAssertEqual(model.webAudioRevocationID, newID)
        XCTAssertEqual(model.activeSource?.id, newSource)
        XCTAssertEqual(model.loadRequestID, newRequest)
        model.handleWebAudioRevocationAcknowledged(newID, sourceID: newSource, requestID: newRequest)
        let newAcknowledged = await newWait()
        XCTAssertTrue(newAcknowledged)
        XCTAssertNil(model.player)
        XCTAssertNil(model.webPlaybackCommand)
    }

    @MainActor
    func testCapturedWebAudioLeaseCanFinishFromActualTeardownAfterModelCleanup() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        _ = model.revokeViewingAudioForTransfer()
        let id = try XCTUnwrap(model.webAudioRevocationID)
        let wait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        model.cleanup()
        let retiredRequest = model.loadRequestID
        XCTAssertTrue(model.isPlaybackSessionRetired)
        XCTAssertNil(model.webAudioRevocationID)

        model.handleWebAudioRevocationAcknowledged(id, sourceID: source, requestID: request)
        model.handleWebPlaybackRetired(sourceID: source, requestID: request)
        let acknowledged = await wait()

        XCTAssertTrue(acknowledged, "Exact WK teardown must release a captured old-owner waiter even after cleanup")
        XCTAssertTrue(model.isPlaybackSessionRetired)
        XCTAssertFalse(model.isViewingAudioEnabled)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.loadRequestID, retiredRequest)
        XCTAssertNil(model.player)
        XCTAssertNil(model.nativeHandoffTask)
        XCTAssertNil(model.nativeHandoffSession)
        XCTAssertNil(model.webAudioRevocationID)
    }

    @MainActor
    func testReenablingWebAudioRejectsLateDOMMuteAcknowledgement() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        _ = model.revokeViewingAudioForTransfer()
        let oldID = try XCTUnwrap(model.webAudioRevocationID)
        let oldWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())

        model.setViewingAudioEnabled(true)
        model.handleWebAudioRevocationAcknowledged(oldID, sourceID: source, requestID: request)

        XCTAssertTrue(model.isViewingAudioEnabled)
        XCTAssertNil(model.webAudioRevocationID)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter(),
                        "Re-enabling audio revokes DOM-ACK authorization, not the unresolved old-owner retirement lease")
        let cancelled = Task { await oldWait() }
        cancelled.cancel()
        let didAcceptCancelledClaim = await cancelled.value
        XCTAssertFalse(didAcceptCancelledClaim)
        // A later revocation has its own authorization; the old DOM ACK is
        // not transferable merely because the source/attempt are unchanged.
        _ = model.revokeViewingAudioForTransfer()
        let newID = try XCTUnwrap(model.webAudioRevocationID)
        let newWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        XCTAssertNotEqual(newID, oldID)
        model.handleWebAudioRevocationAcknowledged(oldID, sourceID: source, requestID: request)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter())
        model.handleWebAudioRevocationAcknowledged(newID, sourceID: source, requestID: request)
        let acknowledged = await newWait()
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNil(model.webPlaybackCommand)
        XCTAssertNil(model.player)
    }

    @MainActor
    private func makeMountedWebAudioRevocationModel(mounted: Bool = true) async throws -> LivePlayerViewModel {
        let event = makePlaybackTestEvent()
        let sessions = (1...2).map { index in
            StreamSession(matchID: event.id, title: "Web Audio Route \(index)",
                playableURL: URL(string: "https://example.invalid/web-audio-\(index)")!,
                streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        }
        let model = LivePlayerViewModel(event: event, providedSessions: sessions, ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Web ACK test must not activate native audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Web ACK test must not configure native audio"); return .completed([]) },
            validateNativeSource: { _, _ in XCTFail("Web ACK test must not fetch native media"); return .invalid("Unexpected validation") })
        model.didApplyLandscape = true
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let load = try XCTUnwrap(model.loadTask)
        await load.value
        // Simulate the mounted/current transport role. No WK document or media
        // is created here, so these units do not claim DOM or audible proof.
        XCTAssertTrue(model.didStartPlayback)
        if mounted {
            model.handleWebPlaybackMounted(sourceID: try XCTUnwrap(model.activeSource?.id), requestID: model.loadRequestID)
        }
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        return model
    }

    @MainActor
    func testCurrentWebMuteAcknowledgementCannotSkipPendingPriorAttemptTeardown() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        defer { model.cleanup() }
        let oldSource = try XCTUnwrap(model.activeSource?.id), oldRequest = model.loadRequestID
        _ = model.revokeViewingAudioForTransfer()
        _ = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        model.selectSourceManually(at: (model.currentSourceIndex + 1) % model.sessions.count)
        let replacement = try XCTUnwrap(model.loadTask)
        await replacement.value
        let currentSource = try XCTUnwrap(model.activeSource?.id), currentRequest = model.loadRequestID
        model.handleWebPlaybackMounted(sourceID: currentSource, requestID: currentRequest)
        _ = model.revokeViewingAudioForTransfer()
        let currentID = try XCTUnwrap(model.webAudioRevocationID)
        let aggregateWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())

        model.handleWebAudioRevocationAcknowledged(currentID, sourceID: currentSource, requestID: currentRequest)

        XCTAssertNotNil(model.captureWebAudioRevocationWaiter(),
                        "An ACK for A2 must not let a coordinator retry skip A1's unretired Web owner")
        let cancelledAggregate = Task { await aggregateWait() }
        cancelledAggregate.cancel()
        let cancelled = await cancelledAggregate.value
        XCTAssertFalse(cancelled)
        model.handleWebPlaybackRetired(sourceID: oldSource, requestID: currentRequest)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter(), "A mismatched teardown must not settle A1")

        model.handleWebPlaybackRetired(sourceID: oldSource, requestID: oldRequest)
        let allAcknowledged = await aggregateWait()

        XCTAssertTrue(allAcknowledged)
        XCTAssertNil(model.captureWebAudioRevocationWaiter())
        XCTAssertEqual(model.loadRequestID, currentRequest)
        XCTAssertEqual(model.activeSource?.id, currentSource)
        XCTAssertFalse(model.isViewingAudioEnabled)
        XCTAssertNil(model.player)
        XCTAssertNil(model.webPlaybackCommand)
    }

    @MainActor
    func testSameAttemptRetryMuteAcknowledgementSettlesSupersededAndCurrentWaiters() async throws {
        let model = try await makeMountedWebAudioRevocationModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        _ = model.revokeViewingAudioForTransfer()
        let supersededWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        _ = model.revokeViewingAudioForTransfer()
        let currentID = try XCTUnwrap(model.webAudioRevocationID)
        let currentWait = try XCTUnwrap(model.captureWebAudioRevocationWaiter())
        model.handleWebAudioRevocationAcknowledged(currentID, sourceID: source, requestID: UUID())
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter())

        model.handleWebAudioRevocationAcknowledged(currentID, sourceID: source, requestID: request)
        let supersededAcknowledged = await supersededWait()
        let currentAcknowledged = await currentWait()

        XCTAssertTrue(supersededAcknowledged, "The exact still-current document is quiet for all of its superseded tickets")
        XCTAssertTrue(currentAcknowledged)
        XCTAssertNil(model.captureWebAudioRevocationWaiter())
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertFalse(model.isViewingAudioEnabled)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNil(model.player)
        XCTAssertNil(model.webPlaybackCommand)
    }

    @MainActor
    func testDisabledSingleWebPaneKeepsManagedAudioUntilItsOwnershipReturns() throws {
        let model = try makeExplicitTransferTestModel()
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        let state = model.playbackState
        XCTAssertTrue(model.isViewingAudioEnabled)
        XCTAssertFalse(model.shouldManageWebAudio(inWatchTwo: false))
        XCTAssertTrue(model.shouldManageWebAudio(inWatchTwo: true))

        model.setViewingAudioEnabled(false)

        XCTAssertTrue(model.shouldManageWebAudio(inWatchTwo: false),
                      "A pane retained alone must not undo a pending old-owner mute")
        XCTAssertTrue(model.shouldManageWebAudio(inWatchTwo: true))
        model.setViewingAudioEnabled(true)
        XCTAssertFalse(model.shouldManageWebAudio(inWatchTwo: false))
        XCTAssertTrue(model.shouldManageWebAudio(inWatchTwo: true))
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.playbackState, state)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNil(model.webPlaybackCommand)
        XCTAssertNil(model.player)
        XCTAssertNil(model.nativeHandoffTask)
    }

    @MainActor
    private func makeWebPlayerViewModel(
        webBackgroundSuspensionDelay: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(750))
        },
        prepareAudioSession: @escaping @MainActor () async -> MediaAudioSessionPreparation = { .completed([]) },
        configureAudioSession: @escaping @MainActor () async -> MediaAudioSessionPreparation = { .completed([]) },
        nativeAudioIsolationBackend: NativePlayerAudioIsolationBackend? = nil
    ) throws -> LivePlayerViewModel {
        let session = StreamSession(
            matchID: "fotty-playback-race",
            title: "Playback Race Test",
            playableURL: try XCTUnwrap(URL(string: "https://www.score808live.tv/embed/admin/fotty-test/1")),
            streamType: .unknown,
            providerName: "Score808",
            requiredHeaders: [
                "X-Fotty-Web-Embed": "true"
            ],
            qualityLabel: "Web"
        )
        return LivePlayerViewModel(
            event: makePlaybackTestEvent(),
            providedSessions: [session],
            webBackgroundSuspensionDelay: webBackgroundSuspensionDelay,
            prepareAudioSession: prepareAudioSession,
            configureAudioSession: configureAudioSession,
            nativeAudioIsolationBackend: nativeAudioIsolationBackend
                ?? .init(isSupported: true, setDisconnected: { _, _ in true })
        )
    }

    @MainActor
    private func makeAdoptedHandoffModel(audible: Bool = true,
        prepareAudio: @escaping @MainActor () async -> MediaAudioSessionPreparation
    ) throws -> (LivePlayerViewModel, HandoffAudioSpyPlayer) {
        let model = try makeWebPlayerViewModel(prepareAudioSession: prepareAudio)
        let selected = try XCTUnwrap(model.activeSession)
        // Simulate only a verified adoption's ownership boundary. No URL is
        // requested and no decode/validation success is claimed by these tests.
        model.nativeHandoffSession = StreamSession(id: selected.id, matchID: selected.matchID,
            playableURL: try XCTUnwrap(URL(string: "https://example.invalid/verified-handoff.m3u8")),
            streamType: .hls, providerName: selected.providerName, requiredHeaders: [:])
        let player = HandoffAudioSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.setViewingAudioEnabled(audible)
        model.holdNativeHandoffAudioUntilWebRetirement()
        model.player = player
        XCTAssertTrue(player.isMuted, "Adoption must preserve the retirement barrier across player.didSet")
        model.isVideoReadyForDisplay = true
        model.didApplyLandscape = true
        model.transition(to: .playing(.native), phase: "Playing")
        return (model, player)
    }

    @MainActor
    private func makeIsolatedAdoptedHandoff(gate: NativeAudioIsolationTestGate, audible: Bool = true) async throws
        -> (LivePlayerViewModel, HandoffAudioSpyPlayer) {
        let model = try makeWebPlayerViewModel(nativeAudioIsolationBackend: gate.backend)
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        model.setViewingAudioEnabled(audible)
        let selected = try XCTUnwrap(model.activeSession)
        let player = HandoffAudioSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        let preparing = Task { await model.prepareNativeCandidateAudioIsolation(player: player,
            sourceID: selected.id, requestID: model.loadRequestID) }
        await waitForHandoffAudio { gate.pendingCount == 1 }
        gate.completeNext()
        let preparedIsolation = await preparing.value
        let isolation = try XCTUnwrap(preparedIsolation)
        // Only ownership is simulated; local composition is not decode proof.
        model.nativeHandoffSession = StreamSession(id: selected.id, matchID: selected.matchID,
            playableURL: URL(string: "https://example.invalid/adopted.m3u8")!, streamType: .hls,
            providerName: selected.providerName, requiredHeaders: [:])
        model.holdNativeHandoffAudioUntilWebRetirement()
        model.player = player
        model.adoptNativeAudioIsolation(isolation)
        model.isVideoReadyForDisplay = true
        model.didApplyLandscape = true
        model.transition(to: .playing(.native), phase: "Playing")
        return (model, player)
    }

    @MainActor
    private func waitForHandoffAudio(_ predicate: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("The controlled handoff audio boundary was not reached", file: file, line: line)
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
        return LivePlayerViewModel(event: makePlaybackTestEvent(), providedSessions: [session],
                                   prepareAudioSession: { .completed([]) })
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

@MainActor
private final class HandoffAudioPreparationGate {
    private var pending: [CheckedContinuation<MediaAudioSessionPreparation, Never>] = []
    var pendingCount: Int { pending.count }
    func wait() async -> MediaAudioSessionPreparation {
        await withCheckedContinuation { pending.append($0) }
    }
    func completeFirst(_ result: MediaAudioSessionPreparation = .completed([])) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: result)
    }
    func completeAll(_ result: MediaAudioSessionPreparation = .completed([])) {
        while !pending.isEmpty { completeFirst(result) }
    }
}

private final class HandoffAudioSpyPlayer: AVPlayer {
    private(set) var playCount = 0
    override func play() { playCount += 1 }
}

/// Shared only by the focused policy/coordinator tests. No real media/audio API.
@MainActor
final class NativeAudioIsolationTestGate {
    private(set) var calls: [Bool] = []
    private(set) var disconnected = false
    private var pending: [(Bool, CheckedContinuation<Bool, Never>)] = []
    private var completesFutureCalls = false
    var pendingCount: Int { pending.count }
    var backend: NativePlayerAudioIsolationBackend {
        .init(isSupported: true, setDisconnected: { [self] _, flag in
            calls.append(flag)
            if completesFutureCalls { disconnected = flag; return true }
            return await withCheckedContinuation { pending.append((flag, $0)) }
        })
    }
    func completeNext(_ success: Bool = true) {
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        if success { disconnected = next.0 }
        next.1.resume(returning: success)
    }
    func finishAll() {
        completesFutureCalls = true
        while !pending.isEmpty { completeNext() }
    }
}

final class FottyQualityStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "FottyQualityStoreTests"

    func testNativePresentationLifecycleFieldsRetainOnlyFiniteEventsAndPrivateSafeScalars() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "native-presentation-records")
        let id = UUID().uuidString
        for event in NativeFullscreenLifecycleEvent.allCases {
            let details = ["native_presentation_id": id, "native_presentation_event": event.rawValue,
                           "native_pip_active": "true", "native_app_backgrounded": "false"]
            store.record(category: .playback, name: "native_presentation_lifecycle", outcome: .info,
                         details: details.merging(["private_url": "https://private.invalid/media?secret=owner"]) { first, _ in first })
            XCTAssertEqual(try XCTUnwrap(store.records().last?.details), details)
        }
        let restarted = FottyQualityStore(defaults: defaults, storageKey: "native-presentation-records")
        XCTAssertEqual(Set(restarted.records().compactMap { $0.details["native_presentation_event"] }),
                       Set(NativeFullscreenLifecycleEvent.allCases.map(\.rawValue)))
        XCTAssertFalse(store.exportJSON().contains("private.invalid"))
        for details in [
            ["native_presentation_id": "private-owner", "native_presentation_event": "private-event",
             "native_pip_active": "1", "native_app_backgrounded": "yes"],
            ["native_presentation_id": "https://private.invalid", "native_presentation_event": "https://private.invalid",
             "native_pip_active": "TRUE", "native_app_backgrounded": "unknown"]
        ] {
            store.record(category: .playback, name: "native_presentation_lifecycle", outcome: .info, details: details)
            XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
        }
    }

    func testDiagnosticFieldsOnlyRetainReviewedStagesAndNumericCodes() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "stage-records")
        store.record(category: .playback, name: "playback_stage", outcome: .info,
                     details: ["stage": "document_failure", "platform_error_code": "-1009",
                               "last_observed_stage": "private-provider-error"])
        let details = try XCTUnwrap(store.records().first?.details)
        XCTAssertEqual(details["stage"], "document_failure")
        XCTAssertEqual(details["platform_error_code"], "-1009")
        XCTAssertNil(details["last_observed_stage"])
    }

    func testNativeAndRelayDiagnosticFieldsRequireTypedBoundedValues() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "native-stage-records")
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: [
            "native_failure_trigger": "failed_to_play_to_end", "native_error_domain": "avfoundation",
            "native_error_code": "-11819", "native_underlying_domain": "url", "native_underlying_code": "-1005",
            "native_error_depth": "3", "native_log_domain": "coremedia", "native_log_code": "-12966",
            "relay_failure_stage": "upstream_response", "relay_failure_kind": "http_status",
            "relay_http_status": "503", "relay_failure_age_ms": "21", "relay_error_code": "-1001"
        ])
        XCTAssertEqual(try XCTUnwrap(store.records().first?.details).count, 13)
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: [
            "native_failure_trigger": "private-owner", "native_error_domain": "private-domain",
            "native_error_code": String(Int.max), "native_underlying_domain": "account123",
            "native_underlying_code": "secret", "native_error_depth": "8", "native_log_domain": "https://private.example",
            "native_log_code": String(Int.min), "relay_failure_stage": "secret", "relay_failure_kind": "not-admitted",
            "relay_http_status": "999", "relay_failure_age_ms": "-1", "relay_error_code": String(Int.max)
        ])
        XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
    }

    func testRelayRequestSnapshotFieldsSurviveLocalRestartWithoutTransportSecrets() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "relay-request-records")
        let relay = UUID(), resource = UUID(), request = UUID()
        var receipt = LocalStreamProxyRequestReceipt(relayID: relay, requestID: request, resourceID: resource,
            method: .get, resourceCategory: .media, categoryBasis: .response, startedAt: 100)
        receipt.observedAt = 101; receipt.httpStatus = 403; receipt.outcome = .failed
        let snapshot = LocalStreamProxyRequestSnapshot(relayID: relay, requests: [receipt], evictedCount: 0, observedAt: 102)
        let failure = LocalStreamProxyFailureEvidence(stage: .upstreamResponse, kind: .httpStatus,
            statusCode: 403, errorCode: nil, recordedAt: Date(), relayID: relay, requestID: request,
            resourceID: resource, resourceCategory: .media)
        let details = snapshot.qualityDetails().merging(failure.qualityDetails()) { _, value in value }
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: details)
        let restarted = FottyQualityStore(defaults: defaults, storageKey: "relay-request-records")
        XCTAssertEqual(try XCTUnwrap(restarted.records().last?.details), details)
        XCTAssertEqual(details["relay_id"], relay.uuidString)
        XCTAssertEqual(details["relay_failure_resource_id"], resource.uuidString)
        XCTAssertEqual(details["relay_request_elapsed_ms"], "1000")
        XCTAssertFalse(details.description.contains("://"))
    }

    func testRelayRequestSnapshotFieldsRejectPrivateIdentifiersUnknownEnumsAndUnboundedValues() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "relay-request-invalid-records")
        let invalid = ["relay_id": "private-owner", "relay_request_id": "secret-account",
            "relay_resource_id": "https://private.invalid/source", "relay_failure_request_id": "invalid",
            "relay_failure_resource_id": "invalid", "relay_observed_failure_request_id": "invalid",
            "relay_observed_failure_resource_id": "invalid", "relay_request_method": "POST",
            "relay_resource_category": "secret-provider", "relay_failure_resource_category": "segment-private",
            "relay_resource_basis": "trustworthy", "relay_request_outcome": "decoded",
            "relay_request_phase": "private-stage", "relay_request_http_status": "999",
            "relay_request_age_ms": "NaN", "relay_request_elapsed_ms": "-1",
            "relay_retained_request_count": "33", "relay_evicted_request_count": String(Int.max),
            "relay_retained_in_flight_count": "-1", "relay_retained_completed_count": "33",
            "relay_retained_failed_count": "999", "relay_retained_cancelled_count": "private-owner",
            "relay_same_resource_later_completed": "probably"]
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: invalid)
        XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
    }

    func testNativeHLSIssueFieldsRetainOnlyFiniteObservedCategories() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "native-hls-records")
        let receipt = ["native_hls_issue": "segment_uri_changed",
                       "native_log_hls_issue": "segment_duration_changed"]
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: receipt)
        XCTAssertEqual(try XCTUnwrap(store.records().last?.details), receipt)
        store.record(category: .playback, name: "source_failure", outcome: .failure,
                     details: ["native_hls_issue": "https://private.example?token=secret",
                               "native_log_hls_issue": "media entry URL private-owner"])
        XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
    }

    func testNativeStartupWaitingReceiptRetainsOnlyBoundedScalarsAndKnownStates() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "native-startup-records")
        let receipt = [
            "native_startup_elapsed_ms": "20001", "native_startup_deadline_ms": "20000",
            "native_item_status": "ready", "native_time_control": "waiting",
            "native_wait_reason": "minimize_stalls", "native_buffer_empty": "true",
            "native_buffer_full": "false", "native_likely_to_keep_up": "false"
        ]
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: receipt)
        XCTAssertEqual(try XCTUnwrap(store.records().last?.details), receipt)
        let restarted = FottyQualityStore(defaults: defaults, storageKey: "native-startup-records")
        XCTAssertEqual(try XCTUnwrap(restarted.records().last?.details), receipt)
        for invalid in ["-1", "3600001", "NaN", "Infinity", String(Int.max)] {
            store.record(category: .playback, name: "source_failure", outcome: .failure, details: [
                "native_startup_elapsed_ms": invalid, "native_startup_deadline_ms": invalid,
                "native_item_status": "private-provider", "native_time_control": "account-name",
                "native_wait_reason": "https://private.invalid/stream", "native_buffer_empty": "1",
                "native_buffer_full": "yes", "native_likely_to_keep_up": "unknown"
            ])
            XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
        }
    }

    func testPreItemDiagnosticReceiptSurvivesLocalRingRestartWithoutRawErrorData() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "preparation-records")
        let error = NSError(domain: NSURLErrorDomain, code: URLError.secureConnectionFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "https://private.invalid/token-owner",
                NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -9807)])
        let preparation = PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .transportError,
                                                         error: error).qualityDetails
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: preparation)
        let restarted = FottyQualityStore(defaults: defaults, storageKey: "preparation-records")
        let details = try XCTUnwrap(restarted.records().first?.details)
        XCTAssertEqual(details, preparation)
        XCTAssertEqual(details["preparation_error_domain"], "url")
        XCTAssertEqual(details["preparation_underlying_code"], "-9807")
        XCTAssertNil(details["native_failure_trigger"])
        XCTAssertFalse(details.description.contains("private.invalid"))
        XCTAssertFalse(details.description.contains("owner"))
        store.record(category: .playback, name: "source_failure", outcome: .failure, details:
            PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .httpStatus, httpStatus: 503).qualityDetails)
        XCTAssertEqual(restarted.records().last?.details["preparation_http_status"], "503")
    }

    func testPreItemRingRejectsUnreviewedStagesReasonsDomainsAndUnboundedCodes() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "preparation-invalid-records")
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: [
            "preparation_stage": "private-provider", "preparation_reason": "account-name",
            "preparation_error_domain": "private-owner", "preparation_error_code": String(Int.max),
            "preparation_underlying_domain": "private-server", "preparation_underlying_code": "secret",
            "preparation_error_depth": "5", "preparation_http_status": "999"
        ])
        XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
    }

    func testWatchCorrelationLinksRetriesAndSourceChangesWithoutChangingSession() {
        var context = FottyPlaybackCorrelation()
        let session = context.sessionID
        let first = UUID(), retry = UUID(), nextSource = UUID()
        context.beginAttempt(first)
        XCTAssertEqual(context.attemptNumber, 1)
        XCTAssertNil(context.previousAttemptID)
        context.beginAttempt(first)
        XCTAssertEqual(context.attemptNumber, 1, "Duplicate observations are not new attempts")
        context.beginAttempt(retry)
        XCTAssertEqual(context.previousAttemptID, first)
        context.beginAttempt(nextSource)
        XCTAssertEqual(context.previousAttemptID, retry)
        XCTAssertEqual(context.attemptNumber, 3)
        XCTAssertEqual(context.sessionID, session)
        XCTAssertNotEqual(FottyPlaybackCorrelation().sessionID, session)
    }

    func testEndpointKeysMatchAcrossFreshSourceIDsButDistinguishDeliveryVariants() throws {
        func source(_ query: String) throws -> StreamSource {
            StreamSource(url: try XCTUnwrap(URL(string: "https://example.com/watch?id=42&server=" + query)),
                         quality: "HD", provider: "Broadcast (1)")
        }
        let first = try source("one"), same = try source("one"), other = try source("two")
        XCTAssertNotEqual(first.id, same.id)
        XCTAssertEqual(FottyPlaybackQualityDetails.variantKey(for: first),
                       FottyPlaybackQualityDetails.variantKey(for: same))
        XCTAssertNotEqual(FottyPlaybackQualityDetails.variantKey(for: first),
                          FottyPlaybackQualityDetails.variantKey(for: other))
    }

    func testOneWatchLinksDiscoveryAndTwoAttemptsButOnlyCountsTheSustainedAttemptOnce() {
        let store = FottyQualityStore(defaults: defaults, storageKey: "sustained-watch")
        let parent = UUID(), discovery = UUID(), early = UUID(), sustained = UUID()
        var correlation = FottyPlaybackCorrelation(sessionID: parent)
        store.record(category: .playback, name: "watch_discovery_started", outcome: .info,
                     details: ["watch_session_id": parent.uuidString, "attempt_id": discovery.uuidString])
        for id in [early, sustained] {
            correlation.beginAttempt(id)
            let details = correlation.details.merging(["attempt_id": id.uuidString]) { _, new in new }
            store.record(category: .playback, name: "attempt_started", outcome: .info, details: details)
            store.record(category: .playback, name: "decoded_progress", outcome: .success, details: details)
            if id == sustained {
                for _ in 0..<2 {
                    store.record(category: .playback, name: "native_continuity_90s", outcome: .success, details: details)
                }
            }
        }
        let summary = store.summary()
        XCTAssertEqual(summary.playbackAttempts, 2)
        XCTAssertEqual(summary.provenPlaybackStarts, 2)
        XCTAssertEqual(summary.sustainedNativeAttempts, 1)
        XCTAssertTrue(store.records().allSatisfy { $0.details["watch_session_id"] == parent.uuidString })
        XCTAssertEqual(store.records().last?.details["previous_attempt_id"], early.uuidString)
    }

    func testCorrelatedRecordsRetainOpaqueIdentityWithoutURLOrHeaderSecrets() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://example.com/private-path/watch?signature=private-value")),
            quality: "HD", provider: "Broadcast (1)",
            headers: ["Authorization": "Bearer private-credential"])
        var context = FottyPlaybackCorrelation()
        let first = UUID(), second = UUID()
        context.beginAttempt(first)
        context.beginAttempt(second)
        let details = FottyPlaybackQualityDetails.make(
            source: source, mode: "web_embed", route: "single", attemptID: second,
            correlation: context, deviceFamily: "ipad",
            additional: ["watch_session_id": "cannot_override", "url": source.url.absoluteString])
        let store = FottyQualityStore(defaults: defaults, storageKey: "correlated-records")
        store.record(category: .playback, name: "attempt_started", outcome: .info, details: details)
        let retained = try XCTUnwrap(store.records().first?.details)
        XCTAssertEqual(retained["watch_session_id"], context.sessionID.uuidString)
        XCTAssertEqual(retained["previous_attempt_id"], first.uuidString)
        XCTAssertEqual(retained["attempt_number"], "2")
        XCTAssertEqual(retained["source_id"], source.id.uuidString)
        XCTAssertEqual(retained["device_family"], "ipad")
        XCTAssertNotNil(retained["variant_key"])
        let exported = store.exportJSON()
        for secret in ["example.com", "private-path", "private-value", "private-credential"] {
            XCTAssertFalse(exported.contains(secret))
        }
    }

    func testStaleCorrelationCannotBeAttachedToAnotherAttempt() throws {
        var context = FottyPlaybackCorrelation()
        context.beginAttempt(UUID())
        let source = StreamSource(url: try XCTUnwrap(URL(string: "https://example.com/watch")),
                                  quality: "HD", provider: "CS 1")
        let details = FottyPlaybackQualityDetails.make(source: source, mode: "web_embed", route: "single",
                                                      attemptID: UUID(), correlation: context)
        XCTAssertNil(details["watch_session_id"])
        XCTAssertNil(details["previous_attempt_id"])
    }

    func testMalformedCorrelationDetailsCannotBecomeStoredIdentifiers() throws {
        let store = FottyQualityStore(defaults: defaults, storageKey: "malformed-correlation")
        store.record(category: .playback, name: "source_failure", outcome: .failure, details: [
            "watch_session_id": "personal-name", "source_id": "account_123",
            "previous_attempt_id": "password", "variant_key": "private_path",
            "device_family": "Jelani_iPad", "os_version": "private-text",
            "attempt_number": "-1", "failure_kind": "startupTimeout"
        ])
        XCTAssertEqual(try XCTUnwrap(store.records().first?.details), ["failure_kind": "startupTimeout"])
    }

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

    func testSharedPlaybackDetailsIdentifyMultiViewWithoutPrivateContext() throws {
        let attemptID = UUID()
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://example.com/private-token/stream.m3u8")),
            quality: "HD",
            provider: "CS 2"
        )
        let details = FottyPlaybackQualityDetails.make(
            source: source,
            mode: "web_embed",
            route: "multiview",
            attemptID: attemptID,
            sourceKey: "cs_0123456789abcdef01234567", // gitleaks:allow — synthetic redaction-contract fixture
            additional: [
                "failure_kind": "startup_timeout",
                "route": "do_not_override",
                "url": source.url.absoluteString
            ]
        )

        XCTAssertEqual(details["mode"], "web_embed")
        XCTAssertEqual(details["route"], "multiview")
        XCTAssertEqual(details["attempt_id"], attemptID.uuidString)
        XCTAssertEqual(details["source_key"], "cs_0123456789abcdef01234567")
        XCTAssertEqual(details["failure_kind"], "startup_timeout")

        let store = FottyQualityStore(defaults: defaults, storageKey: "multiview-records")
        store.record(
            category: .playback,
            name: "terminal_failure",
            outcome: .failure,
            details: details
        )
        let retained = try XCTUnwrap(store.records().first?.details)
        XCTAssertEqual(retained["route"], "multiview")
        XCTAssertEqual(retained["source_key"], "cs_0123456789abcdef01234567")
        XCTAssertNil(retained["url"])
        XCTAssertFalse(store.exportJSON().contains("private-token"))
    }

    func testSharedPlaybackDetailsRejectMalformedCommunitySourceKey() throws {
        let source = StreamSource(
            url: try XCTUnwrap(URL(string: "https://example.com/stream.m3u8")),
            quality: "HD",
            provider: "CS 1"
        )
        let details = FottyPlaybackQualityDetails.make(
            source: source,
            mode: "native",
            route: "multiview",
            attemptID: UUID(),
            sourceKey: "cs_private@example.com"
        )

        XCTAssertNil(details["source_key"])
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

    func testQualitySummaryCountsAttemptOutcomesInsteadOfRawPlaybackEvents() {
        let attemptID = UUID().uuidString
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let records = [
            FottyQualityRecord(id: UUID(), timestamp: now, category: .playback,
                name: "attempt_started", outcome: .info, durationMilliseconds: nil,
                details: ["attempt_id": attemptID], appVersion: "2.0.1", appBuild: "104"),
            FottyQualityRecord(id: UUID(), timestamp: now.addingTimeInterval(1), category: .playback,
                name: "decoded_progress", outcome: .success, durationMilliseconds: 900,
                details: ["attempt_id": attemptID], appVersion: "2.0.1", appBuild: "104"),
            FottyQualityRecord(id: UUID(), timestamp: now.addingTimeInterval(2), category: .playback,
                name: "decoded_progress", outcome: .success, durationMilliseconds: 1_200,
                details: ["attempt_id": attemptID], appVersion: "2.0.1", appBuild: "104"),
            FottyQualityRecord(id: UUID(), timestamp: now.addingTimeInterval(3), category: .playback,
                name: "in_place_recovery", outcome: .recovered, durationMilliseconds: nil,
                details: ["attempt_id": attemptID], appVersion: "2.0.1", appBuild: "104"),
            FottyQualityRecord(id: UUID(), timestamp: now.addingTimeInterval(4), category: .playback,
                name: "terminal_failure", outcome: .failure, durationMilliseconds: nil,
                details: ["attempt_id": attemptID], appVersion: "2.0.1", appBuild: "104")
        ]

        let summary = FottyQualityStore.summarize(records)
        XCTAssertEqual(summary.playbackAttempts, 1)
        XCTAssertEqual(summary.provenPlaybackStarts, 1)
        XCTAssertEqual(summary.recoveredPlaybackEvents, 1)
        XCTAssertEqual(summary.terminalPlaybackFailures, 1)
        XCTAssertEqual(summary.medianStartupMilliseconds, 900)
    }

    func testQualityStorePrunesWholePlaybackAttemptCohorts() throws {
        var currentDate = Date(timeIntervalSince1970: 2_000_000_000)
        let store = FottyQualityStore(defaults: defaults, storageKey: "cohort-records", now: { currentDate })
        for index in 0..<126 {
            let attemptID = "attempt-\(index)"
            store.record(category: .playback, name: "attempt_started", outcome: .info,
                         details: ["attempt_id": attemptID])
            currentDate.addTimeInterval(1)
            store.record(category: .playback, name: "decoded_progress", outcome: .success,
                         details: ["attempt_id": attemptID])
            currentDate.addTimeInterval(1)
        }
        let groups = Dictionary(grouping: store.records(), by: { $0.details["attempt_id"] })
        XCTAssertEqual(store.records().count, 250)
        XCTAssertTrue(groups.values.allSatisfy { $0.count == 2 })
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

    func testOwnerStatusNeverAttributesOlderBuildEvidenceToCurrentRelease() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let performance = FottyPerformanceStore(defaults: defaults, now: { now })
        let records = [
            FottyQualityRecord(
                id: UUID(), timestamp: now.addingTimeInterval(-60), category: .playback,
                name: "terminal_failure", outcome: .failure, durationMilliseconds: nil,
                details: [:], appVersion: "2.0.0", appBuild: "93"
            ),
            FottyQualityRecord(
                id: UUID(), timestamp: now.addingTimeInterval(-30), category: .playback,
                name: "attempt_started", outcome: .info, durationMilliseconds: nil,
                details: [:], appVersion: "2.0.0", appBuild: "94"
            ),
            FottyQualityRecord(
                id: UUID(), timestamp: now.addingTimeInterval(-10), category: .playback,
                name: "decoded_progress", outcome: .success, durationMilliseconds: 1_200,
                details: ["mode": "native"], appVersion: "2.0.0", appBuild: "94"
            )
        ]
        defaults.set(try JSONEncoder().encode(records), forKey: "owner-status-records")
        let store = FottyQualityStore(
            defaults: defaults,
            storageKey: "owner-status-records",
            now: { now },
            performanceStore: performance
        )

        let status = store.ownerStatusSnapshot(appVersion: "2.0.0", appBuild: "94")

        XCTAssertEqual(status.retainedRecordCount, 3)
        XCTAssertEqual(status.olderBuildRecordCount, 1)
        XCTAssertEqual(status.currentBuildSummary.recordCount, 2)
        XCTAssertEqual(status.currentBuildSummary.playbackAttempts, 1)
        XCTAssertEqual(status.currentBuildSummary.provenPlaybackStarts, 1)
        XCTAssertEqual(status.currentBuildSummary.terminalPlaybackFailures, 0)
        XCTAssertEqual(status.currentBuildSummary.medianStartupMilliseconds, 1_200)
        XCTAssertEqual(status.lastCurrentBuildRecordAt, now.addingTimeInterval(-10))
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

@MainActor
private final class TeardownRecordingWebView: WKWebView {
    var events: [String] = []
    var beforeNativePause: (() -> Void)?

    override func pauseAllMediaPlayback(completionHandler: (@MainActor () -> Void)?) {
        beforeNativePause?()
        events.append("pause-all-media")
        completionHandler?()
    }

    override func closeAllMediaPresentations(completionHandler: (@MainActor () -> Void)?) {
        events.append("close-presentations")
        completionHandler?()
    }

    override func stopLoading() {
        events.append("stop-loading")
    }
}

final class MultiLivePanelChromeLayoutTests: XCTestCase {
    func testFocusSidebarSeparatesIdentityFromSourceAndAudioInsteadOfCompressingOneRow() {
        for width: CGFloat in [320, 375, 599] {
            let layout = MultiLivePanelChromeLayout.layout(width: width, isAccessibilitySize: false)
            XCTAssertEqual(layout, .stacked)
            XCTAssertEqual(layout.rowCount, 2)
            XCTAssertEqual(layout.reservedHeight(controlHeight: 44), 107)
        }
        for width: CGFloat in [600, 820, 1180] {
            let layout = MultiLivePanelChromeLayout.layout(width: width, isAccessibilitySize: false)
            XCTAssertEqual(layout, .inline)
            XCTAssertEqual(layout.reservedHeight(controlHeight: 44), 57)
        }
    }

    func testAccessibilityChromeAddsControlRowAndReservesScaledHeightWithoutShrinkingTargets() {
        for width: CGFloat in [320, 600, 1180] {
            let layout = MultiLivePanelChromeLayout.layout(width: width, isAccessibilitySize: true)
            XCTAssertEqual(layout, .accessibility)
            XCTAssertEqual(layout.rowCount, 3)
            XCTAssertEqual(layout.reservedHeight(controlHeight: 88), 289)
            XCTAssertEqual(layout.reservedHeight(controlHeight: 20), 157, "The 44-point minimum is independent of a small text category")
        }
    }

    func testFittedVideoDoesNotCompressOrChangeAllocatedPanelChromeWidth() {
        let allocatedWidth: CGFloat = 820
        let availableHeight: CGFloat = 250
        let layout = MultiLivePanelChromeLayout.layout(width: allocatedWidth, isAccessibilitySize: false)
        let videoHeight = min(max(0, availableHeight - layout.reservedHeight(controlHeight: 44)), allocatedWidth * 9 / 16)
        let videoWidth = min(allocatedWidth, videoHeight * 16 / 9)
        XCTAssertLessThan(videoWidth, 600, "The height-fitted video can be narrower than an otherwise wide panel")
        XCTAssertEqual(layout, .inline, "Header composition must keep the allocated width, not the narrower fitted video width")
        XCTAssertLessThanOrEqual(videoHeight + layout.reservedHeight(controlHeight: 44), availableHeight)
    }
}

final class FootballCompetitionAliasLookupTests: XCTestCase {
    func testCatalogLookupsMatchReviewedScansForEveryNameAndAlias() {
        let allClubs = FootballCompetitionCatalog.snapshots.values.flatMap(\.clubs)
            + FootballCompetitionCatalog.additionalClubIdentities
        let names = Set(allClubs.flatMap { [$0.name] + $0.aliases }).union([
            "", "  ", "FC", "Unknown Athletic", "Norwich City", "Livingston", "Partick",
            "  MANCHESTER UTD FC  ", "Nott’m Forest", "Málaga CF", "Malaga CF",
            "Fenerbahçe SK", "Fenerbahce SK", "ŠK Slovan Bratislava", "S\u{030C}K Slovan Bratislava",
            "Arsenal U18", "Arsenal U19", "Arsenal U21", "Arsenal U23", "Arsenal U17",
            "Arsenal Under-21", "Arsenal under 23", "Arsenal Women", "Arsenal Ladies",
            "Arsenal Youth", "Arsenal Academy", "Arsenal Reserve", "Arsenal Reserves",
        ])
        for name in names.sorted() {
            let canonicalID = referenceCanonicalClubID(for: name, clubs: allClubs)
            XCTAssertEqual(FootballCompetitionCatalog.canonicalClubID(for: name), canonicalID, name)
            XCTAssertEqual(FootballCompetitionCatalog.canonicalTeamKey(name), canonicalID ?? legacyNormalizedKey(name), name)
            for competition in FootballCompetitionID.allCases {
                XCTAssertEqual(
                    FootballCompetitionCatalog.officialName(for: name, in: competition),
                    legacyOfficialName(for: name, clubs: FootballCompetitionCatalog.snapshot(competition).clubs),
                    "\(competition): \(name)"
                )
            }
        }
    }

    func testLookupPreservesAmbiguousAliasesFirstMatchAndRepeatedCanonicalClubs() {
        let first = FootballCompetitionClub(name: "First United", aliases: ["Shared", "First Utd", "Allowed U17"])
        let repeated = FootballCompetitionClub(name: "First United FC", aliases: ["Shared", "Other Alias"])
        let second = FootballCompetitionClub(name: "Second City", aliases: ["Shared"])
        let repeatedLookup = FootballCompetitionCatalog.ClubAliasLookup(clubs: [first, repeated])
        XCTAssertEqual(repeatedLookup.canonicalClubID(for: "shared"), "firstunited")
        XCTAssertEqual(repeatedLookup.officialName(for: "shared"), first.name)

        for clubs in [[first, repeated, second], [second, repeated, first]] {
            let lookup = FootballCompetitionCatalog.ClubAliasLookup(clubs: clubs)
            for name in ["shared", "First Utd FC", "Other Alias", "Allowed U17", "Shared U21", "Shared Women", "Unknown"] {
                XCTAssertEqual(lookup.canonicalClubID(for: name), referenceCanonicalClubID(for: name, clubs: clubs), name)
                XCTAssertEqual(lookup.officialName(for: name), legacyOfficialName(for: name, clubs: clubs), name)
            }
            XCTAssertNil(lookup.canonicalClubID(for: "shared"), "Two distinct canonical clubs remain ambiguous")
            XCTAssertEqual(lookup.officialName(for: "shared"), clubs.first?.name, "Competition lookup retains its first match")
            XCTAssertEqual(lookup.canonicalClubID(for: "Allowed U17"), "firstunited", "Do not broaden the existing non-senior guard")
        }
    }

    private func referenceCanonicalClubID(for rawName: String, clubs: [FootballCompetitionClub]) -> String? {
        guard !legacyIsNonSeniorTeam(rawName) else { return nil }
        let key = legacyNormalizedKey(rawName)
        let literal = legacyNormalizedKey(rawName, preservingClubWords: true)
        let exactClubs = clubs.filter { club in
            ([club.name] + club.aliases).contains { legacyNormalizedKey($0, preservingClubWords: true) == literal }
        }
        let matchedClubs = exactClubs.isEmpty ? clubs.filter { club in
            ([club.name] + club.aliases).contains { legacyNormalizedKey($0) == key }
        } : exactClubs
        let matches = Set(matchedClubs.map { $0.canonicalID ?? legacyNormalizedKey($0.name) })
        return matches.count == 1 ? matches.first : nil
    }

    private func legacyOfficialName(for rawName: String, clubs: [FootballCompetitionClub]) -> String? {
        guard !legacyIsNonSeniorTeam(rawName) else { return nil }
        let key = legacyNormalizedKey(rawName)
        return clubs.first { club in
            ([club.name] + club.aliases).contains { legacyNormalizedKey($0) == key }
        }?.name
    }

    private func legacyIsNonSeniorTeam(_ value: String) -> Bool {
        let pattern = #"\b(?:u(?:18|19|21|23)|under[ -]?(?:18|19|21|23)|women|ladies|youth|academy|reserves?)\b"#
        return value.lowercased().range(of: pattern, options: .regularExpression) != nil
    }

    private func legacyNormalizedKey(_ value: String, preservingClubWords: Bool = false) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let ignored: Set<String> = preservingClubWords ? [] : ["fc", "afc", "cf", "ac", "club", "sc", "sv", "rc", "rcd", "ud", "losc", "ogc", "estac", "stade", "olympique", "and"]
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignored.contains($0.lowercased()) }
            .map { $0.lowercased() == "utd" ? "united" : $0.lowercased() }
            .joined()
    }
}
