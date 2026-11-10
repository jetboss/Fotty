import XCTest
import SwiftUI
@testable import Fotty

final class SportsSearchDiscoveryTests: XCTestCase {
    func testRecentSearchesAreBoundedCaseInsensitiveAndExplicitlyClearable() {
        var raw = SportsSearchHistory.emptyValue
        XCTAssertEqual(SportsSearchHistory.queries(from: raw), [])
        raw = SportsSearchHistory.recording("  Chelsea\nBrighton  ", in: raw)
        raw = SportsSearchHistory.recording("Cricket", in: raw)
        raw = SportsSearchHistory.recording("CHELSEA BRIGHTON", in: raw)
        XCTAssertEqual(SportsSearchHistory.queries(from: raw), ["CHELSEA BRIGHTON", "Cricket"])
        XCTAssertEqual(SportsSearchHistory.recording(" \n\t ", in: raw), raw)
        for index in 0..<12 { raw = SportsSearchHistory.recording("Team \(index)", in: raw) }
        XCTAssertEqual(SportsSearchHistory.queries(from: raw), (4..<12).reversed().map { "Team \($0)" })
        XCTAssertEqual(SportsSearchHistory.queries(from: SportsSearchHistory.emptyValue), [])
    }

    func testRecentSearchesRejectMalformedOrExcessiveStorageAndBoundQueryLength() {
        XCTAssertTrue(SportsSearchHistory.queries(from: "not-json").isEmpty)
        XCTAssertTrue(SportsSearchHistory.queries(from: "{\"query\":\"Chelsea\"}").isEmpty)
        XCTAssertTrue(SportsSearchHistory.queries(from: String(repeating: " ", count: 4_097)).isEmpty)
        let long = String(repeating: "🏏", count: 200)
        let raw = SportsSearchHistory.recording(long, in: SportsSearchHistory.emptyValue)
        XCTAssertEqual(SportsSearchHistory.queries(from: raw).first?.count, 120)
        XCTAssertEqual(SportsSearchHistory.storageKey, "fotty.search.recentQueries.v1")
        XCTAssertFalse(SportsSearchHistory.storageKey.contains("sync"))
    }

    func testMalformedHistoryCanRecoverWithoutGrowingOrRetainingDuplicateAliases() {
        let raw = SportsSearchHistory.recording("Bogotá", in: "[\"BOGOTA\",\"Cricket\",\"cricket\",\"\"]")
        XCTAssertEqual(SportsSearchHistory.queries(from: raw), ["Bogotá", "Cricket"])
        XCTAssertEqual(SportsSearchHistory.queries(from:
            SportsSearchHistory.recording("Tennis", in: "broken")), ["Tennis"])
    }

    @MainActor
    func testSearchInterestShortcutsUseExistingIdentitiesWithoutInventingListings() throws {
        let team = FollowedTeamItem(key: "football|chelsea", teamName: "Chelsea", sportCategory: "football")
        let duplicate = FollowedTeamItem(key: "old-key", teamName: "Chelsea", sportCategory: "football")
        let cpl = FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        let unknown = FollowedLeagueItem(id: "unknown", leagueName: "Unreviewed", sportCategory: "cricket")
        let shortcuts = SportsSearchShortcuts.following(teams: [team, duplicate], leagues: [cpl, unknown],
                                                       sports: ["cricket", "tennis", "unreviewed"])
        XCTAssertEqual(shortcuts.map(\.id), ["team-football|chelsea", "league-cpl", "sport-cricket", "sport-tennis"])
        XCTAssertEqual(shortcuts.first?.team?.displayName, "Chelsea")
        XCTAssertEqual(shortcuts.first?.query, "Chelsea")
        XCTAssertTrue(HomeSportsSearch.results(in: HomeSportsDiscovery(events: []), query: "Chelsea").isEmpty,
                      "An interest shortcut is not a match, source or proof of current coverage")
    }

    @MainActor
    func testSearchCanFollowOnlyExactReviewedTeamNamesNotArbitraryQueries() throws {
        let known = try XCTUnwrap(SportsSearchShortcuts.verifiedTeam(for: "  Chelsea "))
        XCTAssertEqual(known.id, "football|chelsea")
        XCTAssertNil(SportsSearchShortcuts.verifiedTeam(for: "Chelsea vs Brighton"))
        XCTAssertNil(SportsSearchShortcuts.verifiedTeam(for: "not-a-real-reviewed-club-938471"))
        XCTAssertNil(SportsSearchShortcuts.verifiedTeam(for: ""))
    }

    @MainActor
    func testCanonicalInterestShortcutFindsExactProviderAliasWithoutCrossSportOrSquadGuessing() throws {
        let team = FollowedTeamItem(key: "legacy-united", teamName: "Man Utd", sportCategory: "football")
        let shortcut = try XCTUnwrap(SportsSearchShortcuts.following(teams: [team], leagues: [], sports: []).first)
        XCTAssertEqual(shortcut.query, "Manchester United")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, title: String, sport: String) -> EventReference {
            .init(id: id, title: title, category: sport, date: Int64(now.addingTimeInterval(3_600).timeIntervalSince1970),
                  poster: nil, popular: nil, teams: nil)
        }
        let alias = event("senior-alias", title: "Man Utd vs Chelsea", sport: "football")
        let otherSport = event("other-sport", title: "Man Utd vs Chelsea", sport: "basketball")
        let reserve = event("reserve", title: "Man Utd U21 vs Chelsea U21", sport: "football")
        let index = HomeSportsSearch.prepare(in: .init(events: [alias, otherSport, reserve], now: now))
        XCTAssertEqual(index.results(query: shortcut.query).map(\.id), [alias.id])
        XCTAssertEqual(Set(index.results(query: "Man Utd").map(\.id)), Set([alias.id, otherSport.id, reserve.id]),
                       "Ordinary raw-text search remains available; only canonical enrichment needs exact reviewed identity")
    }

    @MainActor
    func testReviewedAliasQueryFindsCanonicalTeamWithoutPromotingOtherSportsOrSquads() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, home: String, sport: String = "football") -> EventReference {
            .init(id: id, title: "\(home) vs Chelsea", category: sport,
                  date: Int64(now.addingTimeInterval(3_600).timeIntervalSince1970),
                  poster: nil, popular: nil, teams: nil)
        }
        let senior = event("senior-canonical", home: "Manchester United")
        let otherSport = event("basketball-canonical", home: "Manchester United", sport: "basketball")
        let reserve = event("reserve-canonical", home: "Manchester United U21")
        let women = event("women-canonical", home: "Manchester United Women")
        let index = HomeSportsSearch.prepare(in: .init(events: [senior, otherSport, reserve, women], now: now))

        for query in ["Man Utd", "  mAn \n UTD "] {
            XCTAssertEqual(index.results(query: query).map(\.id), [senior.id], query)
        }
        XCTAssertTrue(index.results(query: "Unknown United").isEmpty)
        XCTAssertTrue(index.results(query: "Man Utd Chelsea").isEmpty,
                      "Compound text must not turn a partial reviewed alias into an identity guess")
    }

    @MainActor
    func testReviewedAliasFallbackKeepsLiteralMatchesAndResultOrder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, home: String, sport: String = "football", offset: TimeInterval = 3_600) -> EventReference {
            .init(id: id, title: "\(home) vs Chelsea", category: sport,
                  date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970),
                  poster: nil, popular: nil, teams: nil)
        }
        let canonical = event("canonical", home: "Manchester United")
        let alias = event("literal", home: "Man Utd", offset: 7_200)
        let otherSport = event("literal-other-sport", home: "Man Utd", sport: "basketball")
        let reserve = event("literal-reserve", home: "Man Utd U21")
        let unrelated = event("unrelated", home: "Arsenal")
        let discovery = HomeSportsDiscovery(events: [canonical, alias, otherSport, reserve, unrelated], now: now)
        let index = HomeSportsSearch.prepare(in: discovery)
        let expectedIDs = discovery.items.filter { $0.id != unrelated.id }.map(\.id)

        XCTAssertEqual(index.results(query: "Man Utd").map(\.id), expectedIDs,
                       "Exact alias fallback adds the canonical row without removing or reordering literal results")
        XCTAssertEqual(index.results(query: "Man Utd").filter { $0.id == alias.id }.count, 1,
                       "A row satisfying both matching paths is emitted only once")
    }

    @MainActor
    func testReviewedAliasFallbackDoesNotBypassExactFootballLeagueScope() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let senior = EventReference(id: "league-senior", title: "Manchester United vs Chelsea", category: "football",
                                    date: Int64(now.addingTimeInterval(3_600).timeIntervalSince1970),
                                    poster: nil, popular: nil, teams: nil)
        let textOnly = EventReference(id: "league-title-only", title: "Premier League showcase", category: "football",
                                      date: Int64(now.addingTimeInterval(3_600).timeIntervalSince1970),
                                      poster: nil, popular: nil, teams: nil)
        let index = HomeSportsSearch.prepare(in: .init(events: [senior, textOnly], now: now)) {
            $0.id == senior.id ? "Premier League" : "Champions League"
        }

        XCTAssertEqual(index.results(query: "Man Utd").map(\.id), [senior.id])
        XCTAssertEqual(index.results(query: "PREMIER LEAGUE").map(\.id), [senior.id],
                       "An exact competition query still requires its normalized league, not title text")
        XCTAssertEqual(index.results(query: "Champions League").map(\.id), [textOnly.id])
    }

    @MainActor
    func testSearchFindsHomesSourceFreeOfficialFootballFixtureWithLegalClubSuffixes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func official(_ id: String, sport: String = "football", home: String = "Ipswich Town FC",
                      away: String = "Nottingham Forest FC",
                      squad: SportsFixtureCatalog.Squad = .init(gender: .men, ageGroup: "senior")) -> EventReference {
            let participants: [SportsFixtureCatalog.Participant] = [
                .init(id: "\(id)-home", name: home, role: "home"),
                .init(id: "\(id)-away", name: away, role: "away")
            ]
            let metadata = SportsFixtureMetadata(fixtureID: id, sport: sport,
                competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                title: "\(home) vs \(away)", participants: participants, squad: squad,
                status: .scheduled, observedAt: now, verified: true)
            return .init(id: id, title: metadata.title, category: sport,
                         date: Int64(now.addingTimeInterval(3 * 3_600).timeIntervalSince1970),
                         poster: nil, popular: nil,
                         teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), sportsFixture: metadata, competitionID: "premier-league")
        }
        let senior = official("official-senior")
        let otherSport = official("official-other-sport", sport: "basketball")
        let reserve = official("official-reserve", away: "Nottingham Forest FC U21",
                               squad: .init(gender: .men, ageGroup: "u21"))
        let women = official("official-women", home: "Ipswich Town Women FC", away: "Nottingham Forest Women FC",
                             squad: .init(gender: .women, ageGroup: "senior"))
        let discovery = HomeSportsDiscovery(events: [senior, otherSport, reserve, women], now: now)
        let homeRow = try XCTUnwrap(discovery.items.first { $0.id == senior.id })
        XCTAssertEqual(MatchCardFormatting.denseTeamName(homeRow.event.homeName), "Ipswich Town")
        XCTAssertEqual(MatchCardFormatting.denseTeamName(homeRow.event.awayName), "Nottingham Forest")
        XCTAssertFalse(MatchStartPolicy(event: homeRow.event, now: now).canAttemptPlayback,
                       "An official future fixture is searchable without a playable source")

        let index = HomeSportsSearch.prepare(in: discovery) { _ in "Premier League" }
        for query in ["Nottm forest", "Nott'm Forest", "Forest"] {
            XCTAssertEqual(index.results(query: query).filter { $0.id == senior.id }.count, 1, query)
        }
        XCTAssertEqual(index.results(query: "Nottm forest").map(\.id), [senior.id],
                       "Legal-suffix normalization must not add another sport or non-senior squad")
        XCTAssertEqual(index.results(query: "Ipswich").filter { $0.id == senior.id }.count, 1)

        // Typed squad evidence can distinguish receipts whose provider names
        // omit their women's/youth suffix. It must veto the new senior join.
        let metadataWomen = official("metadata-women", squad: .init(gender: .women, ageGroup: "senior"))
        let metadataYouth = official("metadata-youth", squad: .init(gender: .men, ageGroup: "u21"))
        for event in [metadataWomen, metadataYouth] {
            let qualified = HomeSportsSearch.prepare(in: .init(events: [event], now: now))
            XCTAssertTrue(qualified.results(query: "Nottm forest").isEmpty, event.id)
        }
    }

    func testVisibleMatchActionsKeepWatchDirectAndDoNotEnableAutomaticReminders() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rows = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"), encoding: .utf8)
        let search = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Search/SearchView.swift"), encoding: .utf8)
        let details = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Dashboard/CatalogEventDetailsView.swift"), encoding: .utf8)
        XCTAssertTrue(rows.contains("struct CatalogMatchActionsMenu: View"))
        XCTAssertTrue(rows.contains(".accessibilityIdentifier(\"match-more-"))
        XCTAssertTrue(rows.contains("Label(\"Saved\", systemImage: \"checkmark.circle\")"))
        XCTAssertTrue(rows.contains("onWatch: onOpen"), "More must not become a compulsory detour before Watch")
        XCTAssertTrue(search.contains(".onSubmit(of: .search) { rememberQuery() }"))
        XCTAssertTrue(search.contains("setFollowFromView(identity, enabled: true"))
        XCTAssertFalse(search.contains("MatchReminderStore.shared.enable"))
        XCTAssertTrue(details.contains("onWatch: onWatch, alternateActionTitle: alternateActionTitle"))
    }
}

final class FieldPerformanceFeedbackTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var time = Date(timeIntervalSince1970: 2_000_000_000)
    private var store: FottyPerformanceStore!

    override func setUp() {
        super.setUp()
        suite = "FottyFieldPerformanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        time = Date(timeIntervalSince1970: 2_000_000_000)
        store = FottyPerformanceStore(defaults: defaults, now: { self.time })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        store = nil
        defaults = nil
        super.tearDown()
    }

    private func scroll(endOffset: TimeInterval = -10, ratio: Double = 0.02, build: String? = "93", mixed: Bool = false) {
        store.record(windowStart: time.addingTimeInterval(endOffset - 3_600),
                     windowEnd: time.addingTimeInterval(endOffset), reportedBuild: build,
                     includesMultipleVersions: mixed, scrollHitchRatio: ratio)
    }

    func testMissingAndUnattributedLegacyMetricsAreNotZeroFailures() {
        defaults.set(0.5, forKey: "fotty.performance.scrollHitchRatio")
        defaults.set(4, forKey: "fotty.performance.hangCount")
        XCTAssertEqual(store.summary().availability, "not_available")
        XCTAssertNil(store.summary().scroll)
        XCTAssertNil(store.summary().hangs)
        XCTAssertNil(defaults.object(forKey: "fotty.performance.hangCount"))
    }

    func testMeasurementWindowAndReportedBuildSurviveDelayedDelivery() throws {
        scroll(build: "81", mixed: true)
        let sample = try XCTUnwrap(store.summary().scroll)
        XCTAssertEqual(sample.reportedBuild, "81", "Never substitute the installed build")
        XCTAssertTrue(sample.includesMultipleVersions)
        XCTAssertEqual(sample.windowEnd, time.addingTimeInterval(-10))
        XCTAssertEqual(sample.receivedAt, time)
        XCTAssertEqual(sample.scrollHitchRatio, 0.02)
        XCTAssertNil(sample.hangCount)
    }

    func testOlderArrivalCannotReplaceNewerMeasurement() {
        scroll(ratio: 0.02)
        scroll(endOffset: -100, ratio: 0.4)
        XCTAssertEqual(store.summary().scroll?.scrollHitchRatio, 0.02)
    }

    func testRejectsInvalidNumbersAndImpossibleWindows() {
        for ratio in [Double.nan, .infinity, -0.1, 1_001] { scroll(ratio: ratio) }
        scroll(endOffset: 10)
        store.record(windowStart: time, windowEnd: time.addingTimeInterval(-5),
                     reportedBuild: "93", includesMultipleVersions: false, scrollHitchRatio: 0.1)
        store.record(windowStart: time.addingTimeInterval(-60), windowEnd: time,
                     reportedBuild: "93", includesMultipleVersions: false,
                     hangCount: 0, longestHangSeconds: 2)
        XCTAssertEqual(store.summary().availability, "not_available")
    }

    func testRetainsOnlyTwoSmallSummariesAndExpiresThem() {
        for _ in 0..<500 { scroll() }
        store.record(windowStart: time.addingTimeInterval(-60), windowEnd: time,
                     reportedBuild: "93", includesMultipleVersions: false,
                     hangCount: 2, longestHangSeconds: 1.3)
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("fotty.performance.summary.v1.") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertLessThan(keys.compactMap { defaults.data(forKey: $0)?.count }.reduce(0, +), 4_096)
        time.addTimeInterval(15 * 24 * 60 * 60)
        XCTAssertEqual(store.summary().availability, "not_available")
        XCTAssertTrue(keys.allSatisfy { defaults.object(forKey: $0) == nil })
    }

    func testClearRemovesBothHistoriesAndRejectsLatePreClearReports() {
        scroll()
        let quality = FottyQualityStore(defaults: defaults, now: { self.time }, performanceStore: store)
        quality.record(category: .playback, name: "attempt_started", outcome: .info)
        quality.clear()
        XCTAssertTrue(quality.records().isEmpty)
        scroll() // A delayed Apple window from before Clear must not repopulate it.
        XCTAssertEqual(store.summary().availability, "not_available")
        time.addTimeInterval(7_200)
        scroll()
        XCTAssertEqual(store.summary().availability, "available")
    }

    func testCorruptStoredDataIsDiscardedWithoutBreakingFeedback() {
        defaults.set(Data("not JSON".utf8), forKey: "fotty.performance.summary.v1.scroll")
        defaults.set(Data(repeating: 0, count: 3_000), forKey: "fotty.performance.summary.v1.hangs")
        XCTAssertEqual(store.summary().availability, "not_available")
        XCTAssertNil(defaults.data(forKey: "fotty.performance.summary.v1.scroll"))
    }

    func testExportIsOptInAndDoesNotCarryArbitraryMetadata() throws {
        scroll(build: "https://private.example/token")
        store.record(windowStart: time.addingTimeInterval(-60), windowEnd: time,
                     reportedBuild: nil, includesMultipleVersions: true,
                     hangCount: 3, longestHangSeconds: 2.5)
        let quality = FottyQualityStore(defaults: defaults, now: { self.time }, performanceStore: store)
        let json = quality.exportJSON()
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let performance = try XCTUnwrap(payload["performance"] as? [String: Any])
        XCTAssertEqual(performance["availability"] as? String, "available")
        XCTAssertFalse(json.contains("private.example"))
        XCTAssertFalse(json.contains("callStackTree"))
        XCTAssertNil(store.summary().scroll?.reportedBuild)
        XCTAssertTrue(store.summary().hangs?.includesMultipleVersions == true)
        var report = FottyFeedbackReport(area: "General", expected: "Open Home", actual: "Hesitation",
                                         version: "2.0.0 (93)", device: "Test device", system: "iOS", date: time)
        XCTAssertFalse(report.text.contains("scrollHitchRatio"))
        report.diagnostics = json
        XCTAssertTrue(report.text.contains("scrollHitchRatio"))
        report.diagnostics = nil
        XCTAssertFalse(report.text.contains("scrollHitchRatio"))
    }

    func testContextualFeedbackSeedsAnEmptyDraftButNeverOverwritesWork() {
        let seeded = FottyFeedbackDraftSeed.resolved(
            existingExpected: "",
            existingActual: "",
            suggestedExpected: " Watch a live broadcast. ",
            suggestedActual: " Playback stopped. "
        )
        XCTAssertEqual(seeded.expected, "Watch a live broadcast.")
        XCTAssertEqual(seeded.actual, "Playback stopped.")

        let preserved = FottyFeedbackDraftSeed.resolved(
            existingExpected: "My unfinished report",
            existingActual: "",
            suggestedExpected: "Different context",
            suggestedActual: "Different failure"
        )
        XCTAssertEqual(preserved.expected, "My unfinished report")
        XCTAssertEqual(preserved.actual, "")
    }
}

@MainActor
final class SportLoadingTests: XCTestCase {
    private let categories = ["football", "cricket", "basketball", "tennis", "baseball",
                              "american-football", "rugby", "hockey", "motorsport", "fight", "all-sports",
                              "table-tennis", "golf", "darts", "volleyball", "handball", "lacrosse", "cycling", "other"]

    private func event(title: String = "Arsenal vs Real Madrid", category: String = "football",
                       offset: Int64 = 0, home: String = "Arsenal") -> EventReference {
        .init(id: "motion-fixture", title: title, category: category, date: 1_800_000_000 + offset,
              poster: nil, popular: nil,
              teams: .init(home: .init(name: home, badge: nil), away: .init(name: "Real Madrid", badge: nil)))
    }

    func testEachCatalogSportHasDistinctArtworkAndRugbyIsNotNFL() {
        let profiles = categories.map { SportMotionProfile.profile(for: $0) }
        XCTAssertEqual(Set(profiles.map(\.style)).count, categories.count)
        XCTAssertEqual(Set(profiles.map(\.style)), Set(SportMotionStyle.allCases),
                       "The native contact sheets must include every artwork style")
        XCTAssertEqual(SportMotionProfile.profile(for: "rugby").displayName, "rugby")
        XCTAssertEqual(SportMotionProfile.profile(for: "rugby-union").style, .rugby)
        XCTAssertEqual(SportMotionProfile.profile(for: "NFL").style, .americanFootball)
        XCTAssertEqual(SportMotionProfile.profile(for: "volleyball").style, .volleyball)
        XCTAssertNil(SportMotionProfile.profile(for: "cricket", competition: .championsLeague).competition)
        XCTAssertEqual(SportMotionProfile.profile(for: "football", competition: .championsLeague).competition, .championsLeague)
    }

    func testChampionsLeagueTreatmentRequiresSpecificEvidence() {
        XCTAssertNil(SportMotionContext.competition(for: event(), officialMatch: nil), "Famous teams are not competition evidence")
        XCTAssertEqual(SportMotionContext.competition(for: event(title: "UEFA Champions League: Arsenal vs Real Madrid"), officialMatch: nil), .championsLeague)
        XCTAssertEqual(SportMotionContext.competition(for: event(title: "UCL Arsenal vs Real Madrid"), officialMatch: nil), .championsLeague)
        XCTAssertEqual(SportMotionContext.competition(for: event(title: "UEFA Champions League AFC Bournemouth vs Real Madrid", home: "AFC Bournemouth"), officialMatch: nil), .championsLeague)
        for title in ["AFC Champions League", "UEFA Champions League U19", "UEFA Youth League",
                      "UEFA Women's Champions League", "Champions League", "UCL academy", "uclothing"] {
            XCTAssertNil(SportMotionContext.competition(for: event(title: title), officialMatch: nil), title)
        }
        XCTAssertNil(SportMotionContext.competition(for: event(title: "UCL", category: "cricket"), officialMatch: nil))
    }

    func testOfficialMotionEvidenceChecksTeamsAndKickoffAndWinsOverProviderText() throws {
        let data = Data(#"""
        {"id":10,"utcDate":"2027-01-15T08:00:00Z","status":"TIMED",
         "homeTeam":{"name":"Arsenal"},"awayTeam":{"name":"Real Madrid"},
         "score":{},"competition":{"id":2001,"code":"CL","name":"UEFA Champions League"}}
        """#.utf8)
        let official = try JSONDecoder().decode(FootballMatch.self, from: data)
        XCTAssertEqual(official.matchDate?.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(SportMotionContext.competition(for: event(), officialMatch: official), .championsLeague)
        XCTAssertNil(SportMotionContext.competition(for: event(offset: 3600), officialMatch: official))
        XCTAssertNil(SportMotionContext.competition(for: event(home: "Chelsea"), officialMatch: official))
        XCTAssertNil(SportMotionContext.competition(for: event(title: "Arsenal U19 vs Real Madrid U19"), officialMatch: official))
        let domestic = try JSONDecoder().decode(FootballMatch.self, from: Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"id\":2001,\"code\":\"CL\",\"name\":\"UEFA Champions League\"",
                                  with: "\"id\":2021,\"code\":\"PL\",\"name\":\"Premier League\"").utf8))
        XCTAssertNil(SportMotionContext.competition(for: event(title: "UCL Arsenal vs Real Madrid"), officialMatch: domestic))
    }

    func testPoseIsBoundedContinuousAndStillWhenMotionIsDisabled() {
        for style in SportMotionStyle.allCases {
            let first = SportMotionPose(style: style, elapsed: 0, animated: true)
            let last = SportMotionPose(style: style, elapsed: SportMotionPose.duration - 0.00001, animated: true)
            XCTAssertEqual(first.x, last.x, accuracy: 0.01, style.rawValue)
            XCTAssertEqual(first.lift, last.lift, accuracy: 0.01, style.rawValue)
            XCTAssertEqual(first.squash, last.squash, accuracy: 0.01, style.rawValue)
            for index in 0...240 {
                let elapsed = Double(index) / 100
                let frame = SportMotionPose(style: style, elapsed: elapsed, animated: true)
                XCTAssertLessThanOrEqual(abs(frame.x), 18.001, style.rawValue)
                XCTAssertTrue((0...20.001).contains(frame.lift), style.rawValue)
                XCTAssertTrue((0...0.05001).contains(frame.squash), style.rawValue)
                let still = SportMotionPose(style: style, elapsed: elapsed, animated: false)
                XCTAssertEqual(still.x, 0); XCTAssertEqual(still.lift, 0)
                XCTAssertEqual(still.rotation, 0); XCTAssertEqual(still.phase, 0)
            }
            XCTAssertTrue(SportMotionPose(style: style, elapsed: .infinity, animated: true).x.isFinite)
            XCTAssertTrue(SportMotionPose(style: style, elapsed: .nan, animated: true).lift.isFinite)
        }
    }

    func testEquipmentRendersAndMovesInBothAppearances() throws {
        func differences(_ lhs: Data, _ rhs: Data) -> [Int] {
            XCTAssertEqual(lhs.count, rhs.count)
            return zip(lhs, rhs).map { abs(Int($0) - Int($1)) }
        }
        func assertSameFrame(_ lhs: Data, _ rhs: Data, _ label: String) {
            let delta = differences(lhs, rhs)
            // Observed native gradient rounding: 115 / 76,800 channels differ
            // by one level, with identical geometry. Permit only tiny rounding;
            // movement or changed artwork still fails this comparison.
            XCTAssertLessThanOrEqual(delta.max() ?? 0, 1, label)
            XCTAssertLessThanOrEqual(Double(delta.reduce(0, +)) / Double(max(1, delta.count)), 0.005, label)
        }
        let profiles = categories.map { SportMotionProfile.profile(for: $0) }
            + [SportMotionProfile.profile(for: "football", competition: .championsLeague)]
        for scheme in [ColorScheme.dark, .light] {
            let background = scheme == .dark ? Color(white: 0.06) : .white
            for profile in profiles {
                let category = profile.competition == .championsLeague ? "Champions League" : profile.displayName
                func render(_ time: Double, animated: Bool = true) throws -> Data {
                    let content = SportMotionArtwork(profile: profile, elapsed: time, animated: animated)
                        .frame(width: 160, height: 120).background(background).environment(\.colorScheme, scheme)
                    let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
                    let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
                    XCTAssertGreaterThan(Set(pixels).count, 40, "\(category) must not be a blank Canvas")
                    // Compare decoded pixels, not PNG encoder metadata.
                    return pixels
                }
                let movement = differences(try render(0), try render(0.6))
                XCTAssertGreaterThan(Double(movement.reduce(0, +)) / Double(movement.count), 0.25, "\(category) must actually move")
                let stillA = try render(0, animated: false), stillB = try render(1.1, animated: false)
                assertSameFrame(stillA, stillB, "\(category) must stay still in \(scheme)")
                assertSameFrame(try render(0), try render(SportMotionPose.duration), "\(category): no jump at loop boundary")
            }
        }
    }

    func testMotionContactSheetsForVisualReview() throws {
        let profiles = categories.map { SportMotionProfile.profile(for: $0) }
            + [SportMotionProfile.profile(for: "football", competition: .championsLeague)]
        let phases = [0.0, 0.6, 1.2, 1.8]
        for scheme in [ColorScheme.dark, .light] {
            // ImageRenderer has no public contrast-trait override; the SDK's
            // colorSchemeContrast environment is read-only. Do not label a
            // normal render as Increase Contrast evidence or use private SPI.
            for contrast in [ColorSchemeContrast.standard] {
                for inline in [false, true] {
                    // Keep each attachment bounded while retaining all sports
                    // and four actual native animation phases for visual QA.
                    for start in stride(from: 0, to: profiles.count, by: 10) {
                        let page = Array(profiles[start..<min(start + 10, profiles.count)])
                        let cellWidth: CGFloat = inline ? 52 : 160
                        let cellHeight: CGFloat = inline ? 52 : 120
                        // Match StreamResolutionPanel's 18.5-point loading size
                        // inside its 52×52 slot, preserving the artwork's 4:3 ratio.
                        let artWidth: CGFloat = inline ? 18.5 * 2.8 : 160
                        let artHeight: CGFloat = inline ? 18.5 * 2.1 : 120
                        let content = VStack(alignment: .leading, spacing: 8) {
                            Text("\(inline ? "Inline 52×52" : "Artwork 160×120") · \(scheme == .dark ? "Dark" : "Light") · \(contrast == .increased ? "Increased contrast" : "Standard contrast")")
                                .font(.system(size: 14, weight: .semibold))
                            HStack(spacing: 4) {
                                Text("Sport").frame(width: 100, alignment: .leading)
                                ForEach(phases, id: \.self) { time in
                                    Text(String(format: "%.1f s", time)).frame(width: cellWidth)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            ForEach(Array(page.enumerated()), id: \.offset) { _, profile in
                                HStack(spacing: 4) {
                                    Text(profile.competition == .championsLeague ? "Champions\nLeague" : profile.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(width: 100, alignment: .leading)
                                    ForEach(phases, id: \.self) { time in
                                        SportMotionArtwork(profile: profile, elapsed: time)
                                            .frame(width: artWidth, height: artHeight)
                                            .frame(width: cellWidth, height: cellHeight)
                                            .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .foregroundStyle(scheme == .dark ? Color.white : .black)
                        .background(scheme == .dark ? Color(white: 0.06) : .white)
                        .environment(\.colorScheme, scheme)
                        let renderer = ImageRenderer(content: content)
                        renderer.scale = 1
                        let image = try XCTUnwrap(renderer.uiImage)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "sport-motion-\(inline ? "inline52" : "normal")-\(scheme == .dark ? "dark" : "light")-\(contrast == .increased ? "increased" : "standard")-page\(start / 10 + 1)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    func testInlineEquipmentRemainsVisibleAndMovesAtItsActualPanelScale() throws {
        let profiles = categories.map { SportMotionProfile.profile(for: $0) }
            + [SportMotionProfile.profile(for: "football", competition: .championsLeague)]
        for scheme in [ColorScheme.dark, .light] {
            for profile in profiles {
                let frames = try [0.0, 0.6, 1.2, 1.8].map { time -> Data in
                    let content = SportMotionArtwork(profile: profile, elapsed: time)
                        .frame(width: 18.5 * 2.8, height: 18.5 * 2.1)
                        .frame(width: 52, height: 52)
                        .background(scheme == .dark ? Color(white: 0.06) : .white)
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, 52, accuracy: 0.01)
                    XCTAssertEqual(image.size.height, 52, accuracy: 0.01)
                    let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
                    XCTAssertGreaterThan(Set(pixels).count, 16, "\(profile.displayName): inline artwork must render")
                    return pixels
                }
                let first = try XCTUnwrap(frames.first)
                let largestChangedChannels = frames.dropFirst().map { frame in
                    zip(first, frame).filter { abs(Int($0.0) - Int($0.1)) > 1 }.count
                }.max() ?? 0
                XCTAssertGreaterThan(largestChangedChannels, 24,
                    "\(profile.displayName) in \(scheme) must visibly change, beyond gradient rounding, at inline scale")
            }
        }
    }
}

final class BetaUsabilityTests: XCTestCase {
    func testKickoffClashesDefaultOffAndPersistSeparatelyFromReminders() throws {
        let suite = "KickoffClashTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(MatchdayPreferences.showsKickoffClashes(in: defaults))
        defaults.set(true, forKey: "settings.notif.kickoff")
        defaults.set(true, forKey: MatchdayPreferences.showKickoffClashesKey)
        XCTAssertTrue(MatchdayPreferences.showsKickoffClashes(in: try XCTUnwrap(UserDefaults(suiteName: suite))))
        defaults.set(false, forKey: MatchdayPreferences.showKickoffClashesKey)
        XCTAssertFalse(MatchdayPreferences.showsKickoffClashes(in: defaults))
        XCTAssertTrue(defaults.bool(forKey: "settings.notif.kickoff"))
    }

    func testOptionalClashesGateBothDisplayAndCachedDetection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Social/ArenaDiscoveryView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("if showKickoffClashes, let conflict = matchdayProjection.conflicts.first"))
        XCTAssertTrue(source.contains("showKickoffClashes ? makeKickoffConflicts(from: rows, now: now) : []"))
        XCTAssertTrue(source.contains("showKickoffClashes: showKickoffClashes"))
    }

    func testEverydayBrowsingStateKeysRemainDistinctAndSceneScoped() {
        let keys = [
            BrowsingStateKey.homeSport,
            BrowsingStateKey.homeFootballLeague,
            BrowsingStateKey.homeCricketFilter,
            BrowsingStateKey.homeFollowingOnly,
            BrowsingStateKey.homeScrollOffset,
            BrowsingStateKey.homeFullLineupScrollOffset,
            BrowsingStateKey.searchQuery,
            BrowsingStateKey.searchScrollOffset,
            BrowsingStateKey.matchdayScrollOffset
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("fotty.") })
        XCTAssertTrue(HomeInterestPreferences.onlyShowSelectedKey.hasPrefix("fotty."))
        XCTAssertFalse(keys.contains(HomeInterestPreferences.onlyShowSelectedKey))
    }

    func testPublicBrandNamesTheAllSportsProductWithoutRenamingTechnicalContracts() throws {
        XCTAssertEqual(FottyBrand.shortName, "Fotty")
        XCTAssertEqual(FottyBrand.wordmark, "FOTTY")
        XCTAssertEqual(FottyBrand.displayName, "Fotty Sports Hub")
        XCTAssertEqual(FottyBrand.descriptor, "SPORTS HUB")

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let plistData = try Data(contentsOf: root.appendingPathComponent("Fotty/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, FottyBrand.displayName)
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.first?["CFBundleURLName"] as? String, "com.jelani.Fotty")
        XCTAssertEqual(urlTypes.first?["CFBundleURLSchemes"] as? [String], ["fotty"])

        let plistSource = String(decoding: plistData, as: UTF8.self)
        XCTAssertTrue(plistSource.contains("<string>com.jelani.Fotty</string>"))
        XCTAssertTrue(plistSource.contains("<string>fotty</string>"))
        XCTAssertTrue(plistSource.contains("com.jelani.fotty.private-backup"))

        let extensionData = try Data(contentsOf: root.appendingPathComponent("FottyLiveActivityExtension/Info.plist"))
        let extensionPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: extensionData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(extensionPlist["CFBundleDisplayName"] as? String, FottyBrand.displayName)

        let project = try String(
            contentsOf: root.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.jelani.Fotty.LiveActivityExtension"))
        XCTAssertTrue(project.contains("name: Fotty"), "Target and scheme identity should remain stable")

        let webManifestData = try Data(contentsOf: root.appendingPathComponent("web/public/manifest.json"))
        let webManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: webManifestData) as? [String: Any]
        )
        XCTAssertEqual(webManifest["name"] as? String, FottyBrand.displayName)
        XCTAssertEqual(webManifest["short_name"] as? String, FottyBrand.wordmark)
    }

    func testGlobalSportsSearchIsReachableAndCannotCreateACompetingFeed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"),
            encoding: .utf8
        )
        let search = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Search/SearchView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(dashboard.contains("SearchView("))
        XCTAssertTrue(dashboard.contains("accessibilityIdentifier(\"home-search\")"))
        XCTAssertTrue(search.contains("let discovery: HomeSportsDiscovery"))
        XCTAssertFalse(search.contains("AnalyticalDataEngine.allLiveEvents"))
    }

    @MainActor
    func testMajorLeagueBadgeFallbackSurvivesSparseAndInvalidCachedData() throws {
        let seed = TeamBrandService.majorLeagueBadgeURLs
        XCTAssertEqual(seed.values.filter { $0.path.contains("/mlb/") }.count, 30)
        XCTAssertEqual(Set(seed.values.filter { $0.path.contains("/nba/") }).count, 30)
        XCTAssertEqual(Set(seed.values.filter { $0.path.contains("/wnba/") }).count, 15)
        XCTAssertEqual(Set(seed.values.filter { $0.path.contains("/nhl/") }).count, 32)
        XCTAssertEqual(seed["new york yankees"]?.lastPathComponent, "nyy.png")
        XCTAssertEqual(seed["houston astros"]?.lastPathComponent, "hou.png")
        XCTAssertEqual(seed["st louis cardinals"]?.lastPathComponent, "stl.png")
        XCTAssertEqual(seed["utah mammoth"]?.lastPathComponent, "utah.png")
        XCTAssertEqual(seed["trinbago knight riders"]?.host, "r2.thesportsdb.com")
        XCTAssertEqual(seed["barbados tridents"], seed["barbados royals"])
        XCTAssertEqual(seed["bc lions"]?.host, "r2.thesportsdb.com")
        XCTAssertEqual(seed["hamilton tiger cats"], seed["hamilton tiger-cats"])
        let cached = ["chelsea": "https://example.test/chelsea.png", "new york yankees": "not-a-web-url", "houston astros": "file:///private/badge.png"]
        let merged = TeamBrandService.mergingBadgeCache(cached, into: seed)
        XCTAssertEqual(merged["new york yankees"], seed["new york yankees"])
        XCTAssertEqual(merged["houston astros"], seed["houston astros"])
        XCTAssertNotNil(merged["chelsea"])
        XCTAssertEqual(merged.count, seed.count + 1)
    }

    @MainActor
    func testTeamBadgeWindowAlwaysHasATruthfulFallback() throws {
        XCTAssertEqual(TeamBadgeWindow.displayName(for: "   "), "Team")
        XCTAssertEqual(TeamBadgeWindow.fallbackInitials(for: "Chelsea"), "CHE")
        XCTAssertEqual(TeamBadgeWindow.fallbackInitials(for: "Trinbago Knight Riders"), "TK")
        XCTAssertEqual(TeamBadgeWindow.countryFlagURL(for: "England")?.lastPathComponent, "gb-eng.png")
        XCTAssertNil(TeamBadgeWindow.countryFlagURL(for: "New England Revolution"), "Club names must not be mistaken for national teams")

        let brokenProvider = URL(string: "https://provider.invalid/missing.webp")!
        let knownBrand = URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/102.png")!
        XCTAssertEqual(
            TeamBadgeWindow.candidateURLs(explicit: brokenProvider, country: nil, brand: knownBrand),
            [brokenProvider, knownBrand],
            "A failed provider badge must be able to fall through to the known team brand"
        )
        XCTAssertEqual(
            TeamBadgeWindow.candidateURLs(explicit: knownBrand, country: nil, brand: knownBrand),
            [knownBrand],
            "Duplicate badge candidates should only be fetched once"
        )

        let fplTeam = try JSONDecoder().decode(
            FPLTeam.self,
            from: Data(#"{"id": 4, "name": "Chelsea", "short_name": "CHE", "code": 8}"#.utf8)
        )
        XCTAssertEqual(
            fplTeam.badgeURL?.absoluteString,
            "https://resources.premierleague.com/premierleague/badges/100/t8.png"
        )
    }

    @MainActor
    func testCatalogBadgeDecodeIsBoundedForScrollPerformance() throws {
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 1_024, height: 640)).image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_024, height: 640))
        }
        let data = try XCTUnwrap(artwork.pngData())
        let decoded = try XCTUnwrap(FottyImageDecoder.decode(data))
        let pixels = try XCTUnwrap(decoded.cgImage)

        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), FottyImageDecoder.maximumPixelDimension)
        XCTAssertGreaterThan(min(pixels.width, pixels.height), 0)
    }

    func testCatalogScrollUsesStableLazyRowsWithoutAbsoluteOffsetTracking() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"),
            encoding: .utf8
        )
        let rows = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(dashboard.contains("LazyVStack(alignment: .leading, spacing: FottyTheme.spacingMD)"))
        XCTAssertTrue(dashboard.contains("HomeSportsDiscovery.displayRows(items, columns: columns, section: section)"))
        XCTAssertTrue(dashboard.contains("let entries = homeEntries(sections: sections"), "Project before entering lazy content so width is a parent dependency")
        XCTAssertTrue(dashboard.contains("ForEach(entries)"), "Headers and rows share one stable lazy identity sequence")
        XCTAssertTrue(dashboard.contains("ForEach(row.items)"), "Each one/two-fixture lazy row preserves item identity")
        XCTAssertTrue(dashboard.contains("rowPresentations[item.id]"))
        XCTAssertFalse(dashboard.contains(".onScrollGeometryChange"))
        XCTAssertFalse(dashboard.contains(".scrollPosition("))
        XCTAssertFalse(dashboard.contains("homeScrollOffset"))
        XCTAssertFalse(rows.contains("now: item.now"), "A cached catalog timestamp must never freeze visible countdown controls")
        XCTAssertTrue(rows.contains("now: Date? = nil"), "Production controls retain their local live timeline")
        XCTAssertTrue(rows.contains("homeBrandURL"))
        XCTAssertTrue(rows.contains("brandURL: brand"))
        XCTAssertTrue(rows.contains("brandLookupResolved: true"))
        XCTAssertFalse(rows.contains("@Environment(LiveScoreService.self)"))
    }

    func testHomeMatchBoundariesRemainVisibleInCompactAndWideLayouts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(dashboard.range(of: "private func discoveryRow("))
        let end = try XCTUnwrap(dashboard.range(of: "private var fullLineup:", range: start.upperBound..<dashboard.endIndex))
        let wrapper = dashboard[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(wrapper.contains("Divider().overlay(FottyTheme.borderStrong)"))
        XCTAssertTrue(wrapper.contains(".padding(.top, wide || index == 0 ? 0 : -FottyTheme.spacingMD)"),
                      "Only compact sibling rows join into the approved section surface")
        XCTAssertTrue(wrapper.contains(".background(FottyTheme.surface)"),
                      "Compact and wide matches both need visible grouping")
        XCTAssertTrue(wrapper.contains("HomeMatchGroupShape(isFirst: wide || index == 0"))
        XCTAssertTrue(wrapper.contains("isLast: wide || index == row.total - 1"))
        XCTAssertTrue(wrapper.contains(".allowsHitTesting(false)"), "Decorative borders must not intercept match controls")
        XCTAssertTrue(wrapper.contains("homeScheduleRow(item)"), "Keep the existing match identity and action owner")
        XCTAssertFalse(wrapper.contains(".font("), "Separation must not change typography")
        XCTAssertFalse(wrapper.contains(".onTapGesture"), "Separation must not add another playback gesture")
    }

    func testBadgeRefreshCannotFanOutAcrossEveryCatalogRow() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let components = try String(
            contentsOf: root.appendingPathComponent("Fotty/Design/Components.swift"), encoding: .utf8
        )
        let pipeline = try String(
            contentsOf: root.appendingPathComponent("Fotty/Core/Images/FottyImagePipeline.swift"), encoding: .utf8
        )
        let service = try String(
            contentsOf: root.appendingPathComponent("Fotty/Core/Providers/Football/FootballService.swift"), encoding: .utf8
        )

        XCTAssertFalse(components.contains("@ObservedObject private var brandService"))
        XCTAssertTrue(pipeline.contains("actor FottyImagePipeline"))
        XCTAssertTrue(pipeline.contains("if var existing = inFlight[url]"))
        XCTAssertTrue(pipeline.contains("cancelWaiter(waiterID, for: url)"))
        let loop = try XCTUnwrap(service.range(of: "for await leagueLookup in group"))
        let publication = try XCTUnwrap(service.range(of: "self.teamBadgeURLsByLookup = allLookups"))
        XCTAssertLessThan(loop.lowerBound, publication.lowerBound)
        XCTAssertFalse(service[loop.lowerBound..<publication.lowerBound].contains("teamBadgeURLsByLookup ="))
        XCTAssertTrue(service.contains("badgeRefreshFreshnessInterval: TimeInterval = 24 * 60 * 60"))
        XCTAssertTrue(service.contains("private nonisolated static func fetchESPNLeagueBadges"))
        XCTAssertFalse(service.contains("replacingOccurrences(of: \"\\\\s+\""))
    }

    func testCatalogPerformanceFoundationStaysMeasurableAndOffMainActor() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let projection = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/HomeProjectionCoordinator.swift"), encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/MatchListViewModel.swift"), encoding: .utf8
        )
        let notifications = try String(
            contentsOf: root.appendingPathComponent("Fotty/Core/Notifications/NotificationManager.swift"), encoding: .utf8
        )

        XCTAssertTrue(projection.contains("beginInterval(\"CatalogProjection\")"))
        XCTAssertTrue(viewModel.contains("@ModelActor\nprivate actor MatchCatalogCacheWriter"))
        XCTAssertFalse(viewModel.contains("withAnimation(.easeInOut) {\n            self.matches = nearTerm"))
        XCTAssertTrue(notifications.contains("final class FottyMetricSubscriber"))
        XCTAssertTrue(notifications.contains("!AppRuntime.isAutomatedTesting"))
        XCTAssertFalse(notifications.contains("jsonRepresentation"), "Raw MetricKit payloads must not be retained on the 256 GB workstation or test devices")
    }

    func testCatalogRowsOnlySearchForChannelFallbackWhenCPLNeedsIt() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8
        )
        let functionStart = try XCTUnwrap(dashboard.range(of: "private func cplChannelActionTitle"))
        let functionEnd = try XCTUnwrap(dashboard.range(of: "private func canOpenBroadcast", range: functionStart.upperBound..<dashboard.endIndex))
        let implementation = dashboard[functionStart.lowerBound..<functionEnd.lowerBound]
        XCTAssertTrue(implementation.contains("guard event.isCPLFixture"))
        XCTAssertTrue(implementation.contains("broadcastAction(for: event)"))
    }

    @MainActor
    func testLiveProviderBadgeTokensResolveToTheRealImageEndpoint() throws {
        let token = "opaque badge/token+"
        let resolved = try XCTUnwrap(AnalyticalDataEngine.imageURL(from: token))
        XCTAssertEqual(resolved.scheme, "https")
        XCTAssertEqual(resolved.host, "streamed.pk")
        XCTAssertEqual(resolved.path, "/api/images/badge/opaque badge/token+.webp")
        XCTAssertTrue(resolved.absoluteString.hasSuffix(".webp"))

        let direct = try XCTUnwrap(AnalyticalDataEngine.imageURL(from: "https://example.test/team.png"))
        XCTAssertEqual(direct.absoluteString, "https://example.test/team.png")
    }

    @MainActor
    func testAmbiguousShortTeamBadgesStayScopedToTheirSport() throws {
        let rugby = AnalyticalDataEngine.EventReference(
            id: "rugby-bulldogs",
            title: "Bulldogs vs. Broncos",
            category: "rugby",
            date: nil,
            poster: nil,
            popular: nil,
            teams: .init(
                home: .init(name: "Bulldogs", badge: nil),
                away: .init(name: "Broncos", badge: nil)
            ))
        XCTAssertEqual(rugby.homeBadgeURL?.lastPathComponent, "ggzq4e1768487178.png")
        XCTAssertEqual(rugby.awayBadgeURL?.lastPathComponent, "yjgl741768487372.png")
        XCTAssertNil(
            TeamBrandService.sportSpecificBadgeURL(for: "Bulldogs", category: "american-football"),
            "A rugby short name must not cross-wire a different sport"
        )
    }

    @MainActor
    func testSportMotionProfilesStayTruthfulAcrossTheCatalog() {
        XCTAssertEqual(SportMotionProfile.profile(for: "all-sports").style, .multiSport)
        XCTAssertEqual(SportMotionProfile.profile(for: "football").style, .football)
        XCTAssertEqual(SportMotionProfile.profile(for: "cricket").style, .cricket)
        XCTAssertEqual(SportMotionProfile.profile(for: "tennis").style, .tennis)
        XCTAssertEqual(SportMotionProfile.profile(for: "NBA").style, .basketball)
        XCTAssertEqual(SportMotionProfile.profile(for: "MLB").style, .baseball)
        XCTAssertEqual(SportMotionProfile.profile(for: "NHL").style, .hockey)
        XCTAssertEqual(SportMotionProfile.profile(for: "NFL").style, .americanFootball)
        XCTAssertEqual(SportMotionProfile.profile(for: "motor-sports").style, .motorsport)
        XCTAssertEqual(SportMotionProfile.profile(for: "volleyball").style, .volleyball)
        XCTAssertEqual(SportMotionProfile.profile(for: "table-tennis").style, .tableTennis)
        XCTAssertEqual(SportMotionProfile.profile(for: "golf").style, .golf)
        XCTAssertEqual(SportMotionProfile.profile(for: "darts").style, .darts)
        XCTAssertEqual(SportMotionProfile.profile(for: "handball").style, .handball)
        XCTAssertEqual(SportMotionProfile.profile(for: "lacrosse").style, .lacrosse)
        XCTAssertEqual(SportMotionProfile.profile(for: "cycling").style, .cycling)
        XCTAssertEqual(SportMotionProfile.profile(for: "college").style, .generic)
    }

    func testMotionPolicyHonorsAccessibilityPowerAndAppState() {
        XCTAssertTrue(FottyMotionPolicy.allowsContinuousMotion(reduceMotion: false, lowPowerMode: false, sceneIsActive: true))
        XCTAssertFalse(FottyMotionPolicy.allowsContinuousMotion(reduceMotion: true, lowPowerMode: false, sceneIsActive: true))
        XCTAssertFalse(FottyMotionPolicy.allowsContinuousMotion(reduceMotion: false, lowPowerMode: true, sceneIsActive: true))
        XCTAssertFalse(FottyMotionPolicy.allowsContinuousMotion(reduceMotion: false, lowPowerMode: false, sceneIsActive: false))
    }

    func testWatchEntryPointsPresentFeedbackBeforeResolving() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let paths = [
            "Fotty/Features/Dashboard/SportsDashboardView.swift",
            "Fotty/Features/MatchHub/MatchHubViewModel.swift",
            "Fotty/Features/Player/ViewingSessionCoordinator.swift"
        ]

        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("StreamResolutionPresentation.waitForFeedbackFrame()"), path)
            XCTAssertTrue(source.contains("isFindingStream &&") || source.contains("singleSourceDiscoveryEventID == event.id"),
                          "Repeated Watch taps must not restart the same lookup: \(path)")
        }
        for path in ["Fotty/Features/Dashboard/SportsDashboardView.swift", "Fotty/Features/Social/ArenaDiscoveryView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("viewing.watchSingle(event, admission:"),
                          "Single Watch delegates current admission until after scene-owned feedback: \(path)")
        }
    }

    func testSportAwareLoadingReplacesGenericAndObsoletePlayerWaitingUI() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        let resolver = try String(contentsOf: root.appendingPathComponent("Fotty/Core/UI/Shared/StreamResolutionOverlay.swift"), encoding: .utf8)
        let playerLoading = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Player/Components/LoadingStateOverlay.swift"), encoding: .utf8)
        let multiPlayer = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Player/MultiLivePlayerView.swift"), encoding: .utf8)

        XCTAssertTrue(dashboard.contains("SportLoadingView(category: selectedSportTab"))
        XCTAssertTrue(resolver.contains("SportLoadingView(category: sportCategory"))
        XCTAssertTrue(playerLoading.contains("SportLoadingView("))
        XCTAssertTrue(playerLoading.contains("category: viewModel.event.normalizedCategory"))
        XCTAssertTrue(multiPlayer.contains("SportLoadingView(category: slot.event.normalizedCategory"))
        XCTAssertTrue(multiPlayer.contains("SportLoadingView(category: HomeSportsDiscovery.allSports"))
        XCTAssertTrue(multiPlayer.contains(".allowsHitTesting(false)"), "Decorative loading must not acquire the player's taps")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Fotty/Features/Dashboard/PlaybackWarmupView.swift").path
        ))
    }

    func testInlineResolutionUsesInsetsAndNoBlockingDimmerAtEveryEntryPoint() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let panel = try String(contentsOf: root.appendingPathComponent("Fotty/Core/UI/Shared/StreamResolutionOverlay.swift"), encoding: .utf8)
        XCTAssertTrue(panel.contains("struct StreamResolutionPanel"))
        XCTAssertTrue(panel.contains("stream-resolution-cancel"))
        XCTAssertFalse(panel.contains("ignoresSafeArea()"), "Lookup must not intercept the whole catalog")
        XCTAssertFalse(panel.contains("technicalSummary"), "Provider diagnostics are not everyday loading copy")
        XCTAssertFalse(panel.contains("\\.colorScheme, .dark"), "Browsing feedback must honor app appearance")
        for path in ["Fotty/Features/Dashboard/SportsDashboardView.swift",
                     "Fotty/Features/Social/ArenaDiscoveryView.swift",
                     "Fotty/Features/MatchHub/MatchHubView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"), path)
            XCTAssertTrue(source.contains("StreamResolutionPanel("), path)
            XCTAssertFalse(source.contains("StreamResolutionOverlay("), path)
        }
        let home = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        for entry in ["watchEvent(_ event:", "watchSelectedInMultiView()", "toggleMultiSelection(for event:"] {
            let definition = try XCTUnwrap(home.range(of: "private func \(entry)"))
            let body = String(home[definition.upperBound...].prefix(400))
            XCTAssertTrue(body.contains("guard !isFindingAnyStream else { return }"), entry)
        }
        XCTAssertTrue(home.contains("multiResolutionTitles = events.map(eventTitle(_:))"),
                      "The lookup panel must keep the pair it actually requested, not a refreshed selection")
        XCTAssertTrue(home.contains(".disabled(selectedMultiEventIDs.count != 2 || isFindingAnyStream)"))
        XCTAssertTrue(home.contains("if isFindingAnyStream { cancelCurrentResolution() }"),
                      "A modal destination must revoke the older lookup before presenting")
        XCTAssertTrue(home.contains("presentModal { showsSearch = true }"))
        XCTAssertTrue(home.contains("presentModal { showsAllSports = true }"))
        XCTAssertTrue(home.contains("presentModal { selectedHighlightsMatch = match }"))
        let matchday = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Social/ArenaDiscoveryView.swift"), encoding: .utf8)
        XCTAssertTrue(matchday.contains("if isFindingStream { cancelStreamResolution() }"))
        XCTAssertTrue(matchday.contains("presentModal { selectedCatalogEvent = event }"))
    }

    @MainActor
    func testInlinePanelAndReminderConfirmationReflowAtNarrowAndAccessibilityWidths() {
        for width in [288.0, 388.0, 704.0] {
            let panel = StreamResolutionPanel(sportCategory: "cricket",
                statusMessage: "Looking for a playable stream…",
                subtitle: "Trinbago Knight Riders vs Saint Lucia Kings", isMultiStream: false,
                multiTitles: [], onCancel: {})
            let normal = UIHostingController(rootView: panel.environment(\.dynamicTypeSize, .large))
                .sizeThatFits(in: CGSize(width: width, height: 2_000))
            let expanded = UIHostingController(rootView: panel.environment(\.dynamicTypeSize, .accessibility3))
                .sizeThatFits(in: CGSize(width: width, height: 2_000))
            XCTAssertEqual(normal.width, width, accuracy: 1, "Panel width \(width): normal \(normal), accessibility \(expanded)")
            XCTAssertEqual(expanded.width, width, accuracy: 1, "Panel width \(width): normal \(normal), accessibility \(expanded)")
            XCTAssertTrue(normal.height.isFinite && normal.height >= 68, "Panel width \(width): \(normal)")
            // Offscreen Catalyst hosting does not necessarily enlarge semantic
            // fonts when only the SwiftUI environment changes. Calibrate the
            // host separately: require growth when it supplies larger text;
            // otherwise verify stacking never shrinks the proposed layout.
            let text = Text("Stream lookup").font(.subheadline)
            let normalText = UIHostingController(rootView: text.environment(\.dynamicTypeSize, .large))
                .sizeThatFits(in: CGSize(width: width, height: 2_000))
            let expandedText = UIHostingController(rootView: text.environment(\.dynamicTypeSize, .accessibility3))
                .sizeThatFits(in: CGSize(width: width, height: 2_000))
            if expandedText.height > normalText.height + 0.5 {
                XCTAssertGreaterThan(expanded.height, normal.height,
                    "Larger host text must reflow: width \(width), normal \(normal), accessibility \(expanded)")
            } else {
                XCTAssertGreaterThanOrEqual(expanded.height, normal.height,
                    "Stacking must retain the full layout when host font sizes do not change")
            }

            let notice = FottyInlineFeedback(title: "Reminder set", detail: "5 minutes before. Saved to My Matchday.",
                onUndo: {}, onDismiss: {}).environment(\.dynamicTypeSize, .accessibility3)
            let size = UIHostingController(rootView: notice).sizeThatFits(in: CGSize(width: width, height: 2_000))
            XCTAssertEqual(size.width, width, accuracy: 1, "Feedback width \(width): \(size)")
            XCTAssertTrue(size.height.isFinite && size.height >= 88, "Stacked text/actions retain their touch regions: width \(width), \(size)")
        }
    }

    func testBadgeProviderCatalogUsesCurrentLeagueNames() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Core/Providers/Football/FootballService.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Caribbean Premier League"))
        XCTAssertTrue(source.contains("Indian Premier League"))
        XCTAssertFalse(source.contains("\"IPL Cricket\""))
        XCTAssertTrue(source.contains("(\"soccer\", \"eng.1\")"))
        XCTAssertTrue(source.contains("(\"soccer\", \"mex.1\")"))
        XCTAssertTrue(source.contains("(\"football\", \"college-football\")"))
        XCTAssertTrue(source.contains("(\"football\", \"cfl\")"))
        XCTAssertTrue(source.contains("fetchESPNLeagueBadges"))
        XCTAssertFalse(source.contains("let priorityLeagues"), "Cold start must not fan out into one request per football club")

        let allAliases = FootballCompetitionID.allCases.flatMap {
            FootballCompetitionCatalog.snapshot($0).searchAliases
        }
        for providerAlias in ["LASK Linz", "Viking FK", "NK Celje", "Hapoel Be'er", "RB Salzburg"] {
            XCTAssertTrue(allAliases.contains(providerAlias), "Missing exact badge-provider alias: \(providerAlias)")
        }
    }

    func testMajorTeamNameSurfacesUseTheSharedBadgeContract() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let expectations: [(String, String)] = [
            ("Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift", "TeamBadgeWindow("),
            ("Fotty/Features/Player/Components/PlaybackControlsOverlay.swift", "TeamBadgeWindow("),
            ("Fotty/Features/Insights/Views/TacticalPitchView.swift", "TeamIdentityLabel("),
            ("Fotty/Features/Social/Components/LeagueTeamPicker.swift", "TeamBadgeWindow("),
            ("Fotty/Features/Settings/SettingsManageFollowsView.swift", "TeamBadgeWindow("),
            ("Fotty/Features/FPL/Views/Components/FPLFixtureTrackerView.swift", "badgeURL: row.team.badgeURL"),
            ("Fotty/Features/FPL/Views/Components/FPLSquadPitchView.swift", "badgeURL: score.team.badgeURL")
        ]

        for (path, contract) in expectations {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains(contract), "\(path) must keep the shared team-badge presentation")
        }
    }

    func testAppearanceHasDedicatedDestinationAndEngineeringIsNotInSettings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Settings/SettingsScreen.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("SettingsAppearanceView()"))
        XCTAssertTrue(source.contains("title: \"Appearance\""))
        XCTAssertTrue(source.contains("settings-appearance-screen"))
        XCTAssertFalse(source.contains("debugEngineeringSection"))
        XCTAssertFalse(source.contains("SettingsSection(title: \"Engineering\")"))
        XCTAssertFalse(source.contains("StreamPipelineValidationView()"))
    }

    func testRetiredSocialMockAndDebugProductsStayOutOfTheProductionGraph() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let retiredPaths = [
            "Fotty/Core/Cloud/SocialCloudStore.swift",
            "Fotty/Core/Testing/MockMatchService.swift",
            "Fotty/Core/Internal/StreamPipelineValidationService.swift",
            "Fotty/Features/Social/SocialHubView.swift",
            "Fotty/Features/Social/Components/DirectChatView.swift",
            "Fotty/Features/Social/Components/MatchChatView.swift",
            "Fotty/Features/Insights/Views/InsightsHubView.swift",
            "Fotty/Features/Insights/Views/YouTubeHighlightsView.swift",
            "Fotty/Features/Player/Components/LiveStreamDebugSheet.swift",
            "Fotty/Features/Settings/Views/StreamPipelineValidationView.swift"
        ]
        for path in retiredPaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "\(path) is retired and must not return to the production target")
        }

        let appSource = try String(contentsOf: root.appendingPathComponent("Fotty/App/FottyApp.swift"), encoding: .utf8)
        let dashboardSource = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        let settingsSource = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Settings/SettingsScreen.swift"), encoding: .utf8)
        let infoPlist = try String(contentsOf: root.appendingPathComponent("Fotty/Info.plist"), encoding: .utf8)
        XCTAssertFalse(appSource.contains("SocialCloudStore"))
        XCTAssertFalse(dashboardSource.contains("SocialCloudStore"))
        XCTAssertFalse(settingsSource.contains("SettingsProfileEditView"))
        XCTAssertFalse(infoPlist.contains("NSPhotoLibraryUsageDescription"))

        let settingsComponents = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Settings/Components/SettingsComponents.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(settingsComponents.contains("SettingsProfileHeader"))
    }

    func testDiscoveryIsUniversalAndFPLToolsExposeTheirEvidenceLevel() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let helpSource = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Settings/Views/SettingsSupportViews.swift"), encoding: .utf8)
        let fplSource = try String(contentsOf: root.appendingPathComponent("Fotty/Features/FPL/Views/FPLMainView.swift"), encoding: .utf8)
        XCTAssertTrue(helpSource.contains("FPL is an optional power tool"))
        for label in ["Official data", "Official fixtures", "Published data", "On-device plan", "Projection", "Estimate", "Advanced solver"] {
            XCTAssertTrue(fplSource.contains("\"\(label)\""), "FPL tools must preserve the \(label) trust label")
        }
        XCTAssertTrue(fplSource.contains("Plans stay in Fotty"))
        XCTAssertTrue(fplSource.contains("Confirm changes in official FPL"))
    }

    func testPersistenceFailureCannotSilentlyPretendToSave() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let storeSource = try String(contentsOf: root.appendingPathComponent("Fotty/Core/Persistence/LocalDataStore.swift"), encoding: .utf8)
        let settingsSource = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Settings/SettingsScreen.swift"), encoding: .utf8)
        let componentsSource = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Settings/Components/SettingsComponents.swift"), encoding: .utf8)
        XCTAssertTrue(storeSource.contains("isUsingVolatileFallback"))
        XCTAssertTrue(settingsSource.contains("LocalPersistenceWarning"))
        XCTAssertTrue(componentsSource.contains("Changes cannot be saved"))
        XCTAssertTrue(componentsSource.contains("settings-persistence-warning"))
    }

    func testPrivacyManifestMatchesTheActiveCoachBoundary() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appendingPathComponent("Fotty/Resources/PrivacyInfo.xcprivacy"), encoding: .utf8)
        for dataType in ["UserID", "DeviceID", "OtherUserContent"] {
            XCTAssertTrue(manifest.contains("NSPrivacyCollectedDataType\(dataType)"))
        }
        XCTAssertTrue(manifest.contains("NSPrivacyCollectedDataTypeLinked"))
        XCTAssertFalse(manifest.contains("NSPrivacyCollectedDataTypeLinkedToUser"))
        XCTAssertFalse(manifest.contains("NSPrivacyCollectedDataTypeUserContent"))
        XCTAssertFalse(manifest.contains("NSPrivacyCollectedDataTypeUsageData"))
    }

    func testUIClubNamesPreserveTheirIdentity() {
        for name in ["Internacional de Bogotá", "Estudiantes de La Plata", "Coventry City", "Deportivo Alavés"] {
            XCTAssertEqual(MatchCardFormatting.compactTeamName(name), name)
            XCTAssertEqual(MatchCardFormatting.denseTeamName(name), name)
        }
        XCTAssertEqual(MatchCardFormatting.denseTeamName("Manchester United"), "Man United")
        XCTAssertEqual(MatchCardFormatting.compactTeamName("  Coventry City FC  "), "Coventry City")
    }

    @MainActor
    func testUIBroadcastLabelsDoNotPromiseFutureMatchesAreLive() {
        XCTAssertEqual(LiveEventCard.broadcastActionLabel(isLive: true), "Watch live")
        XCTAssertEqual(LiveEventCard.broadcastActionLabel(isLive: false), "Watch")
    }

    @MainActor
    func testUIPointsLabelsIdentifyTheGameweekAndSource() {
        XCTAssertEqual(FPLMainView.pointsLabel(live: nil, officialGameweek: 1), "GW 1 points · official")
        XCTAssertEqual(FPLMainView.pointsLabel(live: nil, officialGameweek: nil), "Official points")
        for (isFinal, projected, expected) in [(true, false, "final"), (false, false, "live"), (false, true, "projected")] {
            let summary = FPLLiveSquadSummary(gameweek: 2, totalPoints: 64, officialCurrentPoints: 50, publishedLineupPoints: 50, hasCompleteScoringData: true, transferCost: 0, playersPlayed: 11, playersRemaining: 0, officialBonus: 0, automaticSubs: [], projectedAutomaticSubs: [], projectedCaptainElementID: projected ? 42 : nil, rows: [], isFinal: isFinal)
            XCTAssertEqual(FPLMainView.pointsLabel(live: summary, officialGameweek: 1), "GW 2 points · \(expected)")
        }
        let incomplete = FPLLiveSquadSummary(gameweek: 2, totalPoints: nil, officialCurrentPoints: nil, publishedLineupPoints: nil, hasCompleteScoringData: false, transferCost: 0, playersPlayed: 0, playersRemaining: 0, officialBonus: 0, automaticSubs: [], projectedAutomaticSubs: [], projectedCaptainElementID: nil, rows: [], isFinal: false)
        XCTAssertEqual(FPLMainView.pointsLabel(live: incomplete, officialGameweek: 1), "GW 2 points · incomplete data")
    }

    @MainActor
    func testUIFixtureDifficultyTextMeetsNormalTextContrast() {
        func luminance(_ color: Color) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        for difficulty in 0...5 {
            let foreground = luminance(FottyFixtureDifficulty.foreground(difficulty))
            let background = luminance(FottyFixtureDifficulty.background(difficulty))
            let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.5, "Difficulty \(difficulty)")
        }
        XCTAssertEqual(FottyFixtureDifficulty.label(2), "Difficulty 2 of 5")
        XCTAssertEqual(FottyFixtureDifficulty.label(0), "Difficulty not rated")
    }

    @MainActor
    func testUIFPLSessionPreservesToolUntilExplicitReset() async throws {
        let suite = "FottyCoachSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        let model = FPLAdvisorViewModel(draftDefaults: defaults)
        XCTAssertNil(model.sendCoachQuestion("Wait for a current workspace"))
        // Navigation retention starts with a loaded current-season workspace,
        // not a disconnected model. The operation below remains fully mocked.
        let deadline = "\(FPLSeasonIdentifier.currentLabel().prefix(4))-08-21T17:30:00Z"
        let calendarFixture: [String: Any] = [
            "events": [["id": 1, "name": "Gameweek 1", "deadline_time": deadline,
                        "deadline_time_epoch": Int(try XCTUnwrap(ISO8601DateFormatter().date(from: deadline)).timeIntervalSince1970),
                        "finished": false, "is_previous": false, "is_current": true, "is_next": false]],
            "elements": [], "teams": [], "element_types": [], "total_players": 0
        ]
        model.bootstrap = try JSONDecoder().decode(FPLBootstrapResponse.self,
            from: JSONSerialization.data(withJSONObject: calendarFixture))
        let session = FPLWorkspaceSession(viewModel: model)
        let started = expectation(description: "Pending Coach question")
        var reply: CheckedContinuation<Void, Never>?
        let request = try XCTUnwrap(model.sendCoachQuestion("Test pending question") { _, _ in
            await withCheckedContinuation {
                reply = $0
                started.fulfill()
            }
            throw CancellationError()
        })
        await fulfillment(of: [started], timeout: 2)
        session.workspace = .tools
        session.selectedTool = .captain
        session.scrollOffsets["Tools/Captain"] = 200
        model.coachInputDraft = "Should I keep my captain?"
        _ = FPLMainView(session: session)
        _ = FPLMainView(session: session)
        XCTAssertTrue(session.viewModel === model)
        XCTAssertEqual(session.workspace, .tools)
        XCTAssertEqual(session.selectedTool, .captain)
        XCTAssertEqual(session.scrollOffsets["Tools/Captain"], 200)
        XCTAssertEqual(model.coachInputDraft, "Should I keep my captain?")
        XCTAssertTrue(model.isCoachThinking)
        session.resetNavigation()
        XCTAssertEqual(session.workspace, .gameweek)
        XCTAssertNil(session.selectedTool)
        XCTAssertTrue(session.scrollOffsets.isEmpty)
        XCTAssertTrue(model.isCoachThinking, "Navigation changes must not cancel a valid question")
        model.cancelCoachRequest()
        reply?.resume()
        await request.value
    }

    func testManagerIDAcceptsNumbersAndOfficialTeamLinks() {
        for input in [
            "123456", "  123456\n", "000123456",
            "https://fantasy.premierleague.com/entry/123456/event/2",
            "https://fantasy.premierleague.com/entry/123456/history/",
            "fantasy.premierleague.com/entry/123456/event/2",
            "https://FANTASY.PREMIERLEAGUE.COM/entry/123456/",
            "http://fantasy.premierleague.com/a/entry/123456",
            "https://fantasy.premierleague.com/api/entry/123456/?x=1#test"
        ] {
            XCTAssertEqual(FPLManagerIDParser.parse(input), 123456, input)
        }
    }

    func testManagerIDRejectsInvalidAndUntrustedLinksWithoutFetchingThem() {
        for input in [
            "", "0", "-1", "+12", "1.5", "12 34", "１２３", "9999999999999999999999999999",
            "https://example.com/entry/123/",
            "https://fantasy.premierleague.com.example.com/entry/123/",
            "https://fantasy.premierleague.com@evil.example/entry/123/",
            "https://user:password@fantasy.premierleague.com/entry/123/",
            "https://fantasy.premierleague.com:444/entry/123/",
            "file://fantasy.premierleague.com/entry/123/",
            "https://fantasy.premierleague.com/leagues/123/",
            "https://fantasy.premierleague.com/entry/",
            "https://fantasy.premierleague.com/entry/0/",
            "https://fantasy.premierleague.com/?entry=123"
        ] {
            XCTAssertNil(FPLManagerIDParser.parse(input), input)
        }
    }

    @MainActor
    func testInvalidManagerInputNeverStartsLookup() async {
        var calls = 0
        let model = FPLManagerConnectionModel { id in
            calls += 1
            return Self.identity(id)
        }
        await model.lookup("not a team")
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isChecking)
        XCTAssertNil(model.identity)
    }

    @MainActor
    func testManagerLookupFailureCanRetryTheSameID() async {
        var calls = 0
        let previousSelection = UserDefaults.standard.object(forKey: "fotty.user.fplManagerId") as? Int
        let model = FPLManagerConnectionModel { id in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return Self.identity(id)
        }
        await model.lookup("123")
        XCTAssertNil(model.identity)
        XCTAssertTrue(model.errorMessage?.contains("offline") == true)
        XCTAssertFalse(model.isChecking)
        await model.lookup("123")
        XCTAssertEqual(model.identity?.id, 123)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isChecking)
        // Checking a team isn't consent to replace the connected manager.
        XCTAssertEqual(UserDefaults.standard.object(forKey: "fotty.user.fplManagerId") as? Int, previousSelection)
    }

    @MainActor
    func testLateManagerLookupCannotReplaceANewerTeam() async {
        let firstStarted = expectation(description: "First lookup started")
        var firstReply: CheckedContinuation<FPLManagerIdentity, Error>?
        let model = FPLManagerConnectionModel { id in
            if id == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    firstReply = continuation
                    firstStarted.fulfill()
                }
            }
            return Self.identity(id)
        }
        let first = Task { await model.lookup("1") }
        await fulfillment(of: [firstStarted], timeout: 2)
        await model.lookup("2")
        firstReply?.resume(returning: Self.identity(1))
        await first.value
        XCTAssertEqual(model.identity?.id, 2)
        XCTAssertFalse(model.isChecking)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testCancellingLookupPreventsLateErrorFromRestoringFailureState() async {
        let started = expectation(description: "Lookup started")
        var reply: CheckedContinuation<FPLManagerIdentity, Error>?
        let model = FPLManagerConnectionModel { _ in
            try await withCheckedThrowingContinuation { continuation in
                reply = continuation
                started.fulfill()
            }
        }
        let task = Task { await model.lookup("1") }
        await fulfillment(of: [started], timeout: 2)
        model.reset()
        task.cancel()
        reply?.resume(throwing: URLError(.badServerResponse))
        await task.value
        XCTAssertNil(model.identity)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isChecking)
    }

    @MainActor
    func testMismatchedLookupIdentityIsNotOfferedForConfirmation() async {
        let model = FPLManagerConnectionModel { _ in Self.identity(99) }
        await model.lookup("123")
        XCTAssertNil(model.identity)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testAlreadyCancelledLookupDoesNotResetANewIdentityOrFetch() async {
        var calls = 0
        let model = FPLManagerConnectionModel { id in
            calls += 1
            return Self.identity(id)
        }
        await model.lookup("2")
        let ready = expectation(description: "Cancelled task ready")
        var resume: CheckedContinuation<Void, Never>?
        let task = Task {
            await withCheckedContinuation { continuation in
                resume = continuation
                ready.fulfill()
            }
            await model.lookup("1")
        }
        await fulfillment(of: [ready], timeout: 2)
        task.cancel()
        resume?.resume()
        await task.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.identity?.id, 2)
    }

    func testFeedbackIncludesBuildAndContextButDiagnosticsAreOptIn() {
        var report = FottyFeedbackReport(
            area: "Playback", expected: "  Resume the match  ", actual: "The picture stayed still",
            version: "2.0.0 (34)", device: "iPhone", system: "iOS 27", date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(report.text.contains("2.0.0 (34)"))
        XCTAssertTrue(report.text.contains("iPhone"))
        XCTAssertTrue(report.text.contains("1970-01-01T00:00:00Z"))
        XCTAssertTrue(report.text.contains("expected:\nResume the match"))
        XCTAssertFalse(report.text.contains("Optional on-device diagnostics"))
        report.diagnostics = "{\"recordCount\":0}"
        XCTAssertTrue(report.text.contains("included by the tester"))
        XCTAssertTrue(report.text.contains("recordCount"))
    }

    func testSetupCanBeDismissedAndDoesNotRequireFPLToUseTheApp() {
        XCTAssertTrue(MatchdaySetupPolicy.shouldShow(dismissed: false, followedCount: 0, savedCount: 0))
        XCTAssertFalse(MatchdaySetupPolicy.shouldShow(dismissed: true, followedCount: 0, savedCount: 0))
        XCTAssertFalse(MatchdaySetupPolicy.shouldShow(dismissed: true, followedCount: 1, savedCount: 2))
        XCTAssertFalse(MatchdaySetupPolicy.shouldShow(dismissed: false, followedCount: 1, savedCount: 2))
    }

    func testDiscoveryAndMatchdayDoNotPromoteOrDependOnFPL() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for path in [
            "Fotty/Features/Dashboard/SportsDashboardView.swift",
            "Fotty/Features/Dashboard/HomeCatalogProjectionPolicies.swift",
            "Fotty/Features/Dashboard/HomeProjectionCoordinator.swift",
            "Fotty/Features/Dashboard/CatalogEventDetailsView.swift",
            "Fotty/Features/Dashboard/Components/HeroMatchCarousel.swift",
            "Fotty/Features/Dashboard/Components/LiveEventCard.swift",
            "Fotty/Features/Dashboard/Components/HomeSportsDiscovery.swift",
            "Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift",
            "Fotty/Features/Onboarding/MatchdaySetupCard.swift",
            "Fotty/Features/Social/ArenaDiscoveryView.swift",
            "Fotty/Features/MatchHub/Tabs/InsightsHubTab.swift"
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(source.contains("FPL"), path)
            XCTAssertFalse(source.contains("fplContext"), path)
        }
    }

    func testMatchdayDoesNotRebuildTheCatalogAndRootNavigationUsesRealSystemTabs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let matchday = try String(
            contentsOf: root.appendingPathComponent("Fotty/Features/Social/ArenaDiscoveryView.swift"),
            encoding: .utf8
        )
        let tabs = try String(
            contentsOf: root.appendingPathComponent("Fotty/App/MainTabView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(matchday.contains(".task(id: matchdayProjectionKey)"))
        XCTAssertTrue(matchday.contains("MatchdayProjection"))
        XCTAssertTrue(matchday.contains("MatchdayProjection\")"))
        XCTAssertFalse(matchday.contains(".onScrollGeometryChange"))
        XCTAssertFalse(matchday.contains("sorted(by: matchSort)"))
        XCTAssertTrue(tabs.contains("TabView(selection: $selectedTab)"))
        XCTAssertEqual(tabs.components(separatedBy: ".tabItem {").count - 1, MainTabView.Tab.allCases.count,
                       "Every root destination must be a real native tab item")
        XCTAssertTrue(tabs.contains(".toolbarVisibility(isTabBarVisible ? .visible : .hidden, for: .tabBar)"))
        XCTAssertTrue(tabs.contains(".tabBarMinimizeBehavior(.onScrollDown)"),
                      "The configured native tab bar should use the system's compact glass behavior")
        XCTAssertFalse(tabs.contains("FottyTabDock"), "Do not layer a second custom dock beneath the native tab bar")
        XCTAssertTrue(tabs.contains(".ignoresSafeArea(selectedTab == .fpl ? [] : .keyboard, edges: .bottom)"),
                      "Inline FPL editors must retain native software-keyboard avoidance")
    }

    @MainActor
    func testCricketChannelIsNotACPLMatchOrAnUnknownTimeFixture() {
        let willow = cricketEvent(title: "Willow Cricket", date: -3_600_000)
        XCTAssertTrue(willow.isBroadcastChannel)
        XCTAssertEqual(willow.homeName, "Willow Cricket")
        XCTAssertEqual(willow.awayName, "")
        XCTAssertEqual(willow.displayTitle, "Willow Cricket")
        XCTAssertFalse(willow.isCPLFixture)
        XCTAssertEqual(willow.broadcastTiming(), .available)
        XCTAssertFalse(willow.isPastEstimatedMatchWindow())
        XCTAssertFalse(CricketCatalogFilter.cpl.includes(willow))
        XCTAssertTrue(CricketCatalogFilter.channels.includes(willow))
        XCTAssertFalse(cricketEvent(title: "India vs Australia", date: nil).isBroadcastChannel)
        XCTAssertFalse(cricketEvent(title: "Willow Cricket vs Fox Cricket", date: nil).isBroadcastChannel)
    }

    @MainActor
    func testCPLIdentityRequiresCricketAndExplicitCompetitionOrTwoTeams() {
        XCTAssertTrue(cricketEvent(title: "Trinbago Knight Riders vs Barbados Royals", date: nil).isCPLFixture)
        XCTAssertTrue(cricketEvent(title: "St. Lucia Kings vs Antigua Falcons", date: nil).isCPLFixture)
        XCTAssertTrue(cricketEvent(title: "CPL Final", date: nil).isCPLFixture)
        XCTAssertFalse(cricketEvent(title: "Trinbago Knight Riders news", date: nil).isCPLFixture)
        XCTAssertFalse(cricketEvent(title: "India vs Australia", date: nil).isCPLFixture)
        let football = AnalyticalDataEngine.EventReference(id: "test-football", title: "CPL Final", category: "football", date: nil, poster: nil, popular: nil, teams: nil)
        XCTAssertFalse(football.isCPLFixture)
    }

    func testCPLTeamMatchingRetainsLegacyAliasAndBoundaryBehavior() {
        let aliases = CPLTeam.allCases.flatMap { legacyCPLAliases(for: $0) }
        var inputs = aliases.flatMap { alias in
            [alias, alias.uppercased(), "Preview: \(alias)!",
             alias.replacingOccurrences(of: " ", with: "..."),
             "x\(alias)", "\(alias)x", "\(alias) vs \(alias)"]
        }
        for home in CPLTeam.allCases {
            for away in CPLTeam.allCases {
                inputs.append("\(home.rawValue) vs \(away.rawValue)")
            }
        }
        inputs += ["", "CPL Final", "India vs Australia", "Trinbago Knight Rider",
                   "Trínbago Knight Riders", "Antígua Falcons", "St. Lucia Kings",
                   "Antigua&&Barbuda Falcons", "Antigua&BarbudaFalcons",
                   "Antigua Falcons vs Antigua and Barbuda Falcons",
                   "Trinbago\u{00a0}Knight\nRiders / Barbados-Royals",
                   "Trinbago\u{200d}Knight\u{200d}Riders; Guyana Amazon Warriors"]

        for _ in 0..<3 {
            for text in inputs {
                let legacyDistinctTeams = CPLTeam.allCases.filter { legacyCPLTeamMatches($0, in: text) }.count >= 2
                XCTAssertEqual(CPLTeam.containsTwoDistinctTeams(in: text), legacyDistinctTeams, text)
            }
        }
    }

    @MainActor
    func testCPLFixtureClassificationRetainsLegacyRulesAcrossRepeatedQueries() {
        typealias Input = (title: String?, category: String?, home: String?, away: String?)
        let aliases = CPLTeam.allCases.flatMap { legacyCPLAliases(for: $0) }
        var inputs: [Input] = aliases.flatMap { alias -> [Input] in
            [(alias, "cricket", nil, nil),
             ("\(alias) news", "cricket", nil, nil),
             ("\(alias) vs \(alias)", "cricket", nil, nil),
             ("\(alias) vs Guyana Amazon Warriors", "cricket", nil, nil),
             (nil, "cricket", alias, "Guyana Amazon Warriors")]
        }
        for channel in ["Willow", "Willow TV", "Willow Cricket", "Willow HD", "Willow 2", "Fox Cricket", "Fox Cricket HD"] {
            inputs.append((channel, "CRICKET", "Trinbago Knight Riders", "Barbados Royals"))
        }
        for category in [nil, "football", "soccer", "", " cricket "] as [String?] {
            inputs.append(("CPL Final", category, "Trinbago Knight Riders", "Barbados Royals"))
        }
        inputs += [(nil, "cricket", nil, nil),
                   ("Caribbean Premier League final", "CrIcKeT", nil, nil),
                   ("CPL Final", "cricket", nil, nil),
                   ("[cPl]-highlights", "cricket", nil, nil),
                   ("CPL2 / XCPL / CPL_", "cricket", nil, nil),
                   ("Caribbean-Premier-League", "cricket", nil, nil),
                   ("Trínbago Knight Riders vs Barbados Royals", "cricket", nil, nil),
                   ("St. Lucia Kings / Antigua Falcons", "cricket", nil, nil),
                   ("Antigua Falcons vs Antigua and Barbuda Falcons", "cricket", nil, nil),
                   ("Willow Cricket vs Fox Cricket", "cricket", nil, nil),
                   ("India vs Australia", "cricket", nil, nil),
                   ("Preview", "cricket", "Trinbago Knight Riders", "Barbados Royals"),
                   ("C", "cricket", "PL", nil)]

        for _ in 0..<3 {
            for (index, input) in inputs.enumerated() {
                let teams: NexusATeams? = input.home != nil || input.away != nil
                    ? .init(home: input.home.map { .init(name: $0, badge: nil) },
                            away: input.away.map { .init(name: $0, badge: nil) }) : nil
                let event = AnalyticalDataEngine.EventReference(
                    id: "legacy-cpl-\(index)", title: input.title, category: input.category,
                    date: nil, poster: nil, popular: nil, teams: teams)
                XCTAssertEqual(event.isCPLFixture, legacyIsCPLFixture(event), "Case \(index): \(input)")
            }
        }
    }

    @MainActor
    func testCricketTimingDoesNotExpireAtFootballFullTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let started = Int64(now.addingTimeInterval(-3 * 3600).timeIntervalSince1970)
        let cpl = cricketEvent(title: "CPL · Trinbago Knight Riders vs Barbados Tridents", date: started)
        XCTAssertEqual(cpl.broadcastTiming(at: now), .live)
        XCTAssertFalse(cpl.isPastEstimatedMatchWindow(at: now))
        XCTAssertFalse(cpl.isPastEstimatedMatchWindow(at: now.addingTimeInterval(3 * 3600)))
        XCTAssertFalse(cpl.isPastEstimatedMatchWindow(at: now.addingTimeInterval(5 * 3600 - 1)))
        XCTAssertTrue(cpl.isPastEstimatedMatchWindow(at: now.addingTimeInterval(5 * 3600)))
        let testMatch = cricketEvent(title: "India vs Australia, 1st Test", date: started)
        XCTAssertEqual(testMatch.broadcastTiming(at: now), .available)
        XCTAssertFalse(testMatch.isPastEstimatedMatchWindow(at: now.addingTimeInterval(48 * 3600)))
    }

    @MainActor
    func testSavedChannelSurvivesNegativeProviderDateAndRelaunch() throws {
        let suite = "Fotty.CricketPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let willow = cricketEvent(title: "Willow Cricket", date: -3_600_000)
        let store = MyMatchdayStore(defaults: defaults)
        store.save(willow)
        XCTAssertTrue(store.contains(eventID: willow.id))
        XCTAssertTrue(MyMatchdayStore(defaults: defaults).contains(eventID: willow.id))
    }

    @MainActor
    func testCPLSchedulePreservesVenueTimeZonesAndJulyOpponentCorrection() throws {
        XCTAssertEqual(CPLSchedule.fixtures.count, 39)
        XCTAssertEqual(Set(CPLSchedule.fixtures.map(\.id)).count, 39)
        for fixture in CPLSchedule.fixtures { XCTAssertNotNil(ISO8601DateFormatter().date(from: fixture.start)) }
        let jamaica = CPLSchedule.fixtures[3]
        XCTAssertEqual(ISO8601DateFormatter().string(from: jamaica.kickoff), "2026-08-12T00:00:00Z")
        XCTAssertEqual(CPLSchedule.fixtures[19].away, .jamaica)
        XCTAssertEqual(CPLSchedule.fixtures[21].away, .guyana)
        XCTAssertEqual(CPLSchedule.fixtures[18].away, .barbados)
        XCTAssertEqual(CPLSchedule.fixtures[18].away?.rawValue, "Barbados Tridents")
        let final = try XCTUnwrap(CPLSchedule.fixtures.first { $0.stage == "Final" })
        XCTAssertEqual(final.home, .antigua)
        XCTAssertEqual(final.away, .jamaica)
        XCTAssertEqual(final.event().homeName, "Antigua & Barbuda Falcons")
        XCTAssertEqual(final.event().awayName, "Jamaica Kingsmen")
        XCTAssertTrue(final.event().title?.contains("Final") == true)
        XCTAssertEqual(final.event().cplCompetitionLabel, "CPL Final")
    }

    @MainActor
    func testUnresolvedCPLStageDoesNotInventOpponentTeams() {
        let stage = CPLSchedule.Fixture(1, "2027-09-01T19:00:00-04:00", stage: "Final", season: 2027)
        let event = stage.event()
        XCTAssertEqual(event.displayTitle, "CPL Final")
        XCTAssertNil(event.teams)
        XCTAssertFalse(HomeDiscoveryRow.showsTeamBadges(for: event))
        XCTAssertFalse(event.displayTitle.contains("Teams to be confirmed"))
    }

    @MainActor
    func testCPLRemoteManifestMatchesBundledFallbackAndRejectsPartialUpdates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let manifestURL = root.appendingPathComponent("web/public/data/cpl-2026-fixtures.json")
        let data = try Data(contentsOf: manifestURL)
        let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let checkedAt = try XCTUnwrap(manifestObject["checkedAt"] as? String)
        let validationDate = try XCTUnwrap(ISO8601DateFormatter().date(from: checkedAt))
        let snapshot = try CPLSchedule.validatedSnapshot(from: data, now: validationDate)
        XCTAssertEqual(Config.cplScheduleManifestURL?.absoluteString, "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/cricket/cpl-fixtures")
        XCTAssertEqual(snapshot.sourceStatus, .lastKnownGood)
        XCTAssertFalse(snapshot.isFreshlyVerified(at: validationDate))
        XCTAssertEqual(snapshot.fixtures.count, CPLSchedule.fixtures.count)
        for (remote, bundled) in zip(snapshot.fixtures, CPLSchedule.fixtures) {
            XCTAssertEqual(remote.number, bundled.number)
            XCTAssertEqual(remote.kickoff, bundled.kickoff)
            XCTAssertEqual(Set([remote.home, remote.away].compactMap { $0 }), Set([bundled.home, bundled.away].compactMap { $0 }))
            XCTAssertEqual(remote.stage, bundled.stage)
        }

        var partial = manifestObject
        var records = try XCTUnwrap(partial["fixtures"] as? [[String: Any]])
        records.removeLast()
        partial["fixtures"] = records
        let partialData = try JSONSerialization.data(withJSONObject: partial)
        XCTAssertThrowsError(try CPLSchedule.validatedSnapshot(from: partialData, now: validationDate)) { error in
            XCTAssertEqual(error as? CPLSchedule.ValidationError, .invalidFixtureCount)
        }

        var verified = manifestObject
        verified["sourceStatus"] = "verified"
        verified["checkedAt"] = checkedAt
        let verifiedData = try JSONSerialization.data(withJSONObject: verified)
        let verifiedSnapshot = try CPLSchedule.validatedSnapshot(from: verifiedData, now: validationDate)
        XCTAssertEqual(verifiedSnapshot.sourceStatus, .verified)
        XCTAssertTrue(verifiedSnapshot.isFreshlyVerified(at: validationDate))
        XCTAssertTrue(verifiedSnapshot.isFreshlyVerified(
            at: validationDate.addingTimeInterval(CPLSchedule.verificationFreshnessWindow)
        ))
        XCTAssertFalse(verifiedSnapshot.isFreshlyVerified(
            at: validationDate.addingTimeInterval(CPLSchedule.verificationFreshnessWindow + 1)
        ))

        verified["sourceStatus"] = "unknown"
        let unknownStatusData = try JSONSerialization.data(withJSONObject: verified)
        XCTAssertThrowsError(try CPLSchedule.validatedSnapshot(from: unknownStatusData, now: validationDate)) { error in
            XCTAssertEqual(error as? CPLSchedule.ValidationError, .invalidHeader)
        }

        let fallback = CPLSchedule.Snapshot(
            revision: "old-fallback",
            checkedAt: validationDate.addingTimeInterval(60),
            fixtures: snapshot.fixtures,
            sourceStatus: .lastKnownGood
        )
        XCTAssertTrue(CPLScheduleUpdater.shouldKeepCached(verifiedSnapshot, over: fallback))
        let newerVerified = CPLSchedule.Snapshot(
            revision: "same-content",
            checkedAt: validationDate.addingTimeInterval(60),
            fixtures: snapshot.fixtures,
            sourceStatus: .verified
        )
        XCTAssertFalse(CPLScheduleUpdater.shouldKeepCached(verifiedSnapshot, over: newerVerified))
    }

    @MainActor
    func testCPLRemoteManifestAcceptsAReviewedFutureSeasonAndNewFranchise() throws {
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "competitionId": "cpl",
            "season": 2027,
            "fixtureCount": 2,
            "revision": "2027-reviewed",
            "checkedAt": "2027-07-01T00:00:00Z",
            "sourceStatus": "verified",
            "teamNames": ["tobago": "Tobago Test XI"],
            "fixtures": [
                ["number": 1, "upstreamId": "200001", "start": "2027-08-01T23:00:00Z", "team1": "trinbago", "team2": "tobago"],
                ["number": 2, "upstreamId": "200002", "start": "2027-09-01T23:00:00Z", "stage": "Final"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-07-01T00:00:00Z"))
        let snapshot = try CPLSchedule.validatedSnapshot(from: data, now: now)
        XCTAssertEqual(snapshot.season, 2027)
        XCTAssertEqual(snapshot.fixtures.map(\.id), ["cpl-2027-1", "cpl-2027-2"])
        XCTAssertEqual(snapshot.fixtures[0].awayName, "Tobago Test XI")
        XCTAssertTrue(CPLSchedule.isManagedFixtureID(snapshot.fixtures[0].id))
    }

    @MainActor
    func testCPLStageOnlyRefreshCannotEraseKnownPlayoffParticipants() throws {
        let known = try XCTUnwrap(CPLSchedule.fixtures.first { $0.stage == "Final" })
        let unresolved = CPLSchedule.Fixture(
            known.number,
            "2026-09-20T20:00:00-04:00",
            stage: "Final",
            season: known.season
        )
        let preserved = try XCTUnwrap(CPLSchedule.preservingKnownPlayoffParticipants(
            in: [unresolved],
            from: [known]
        ).first)
        XCTAssertEqual(preserved.home, .antigua)
        XCTAssertEqual(preserved.away, .jamaica)
        XCTAssertEqual(preserved.stage, "Final")
        XCTAssertEqual(preserved.start, "2026-09-20T20:00:00-04:00",
                       "The newer verified kickoff must survive participant preservation")
    }

    @MainActor
    func testCPLCompletedFixtureDoesNotLingerIntoFollowingDay() {
        let fixture = CPLSchedule.fixtures[18]
        let duringRainDelayWindow = CPLSchedule.merging(into: [], at: fixture.kickoff.addingTimeInterval(7 * 3600))
        XCTAssertTrue(duringRainDelayWindow.contains { $0.id == fixture.id })

        let followingMorning = CPLSchedule.merging(into: [], at: fixture.kickoff.addingTimeInterval(9 * 3600))
        XCTAssertFalse(followingMorning.contains { $0.id == fixture.id })
        XCTAssertTrue(followingMorning.contains { $0.id == CPLSchedule.fixtures[19].id })
    }

    func testFootballFixtureProgressOnlyDuringAnActualScheduleCheck() {
        let now = Date(timeIntervalSince1970: 1_788_600_000)
        let expired = now.addingTimeInterval(-FootballScheduleFreshnessPolicy.maximumAge - 1)
        func shows(_ checking: Bool, _ verified: Date?, failed: Bool = false) -> Bool {
            FootballScheduleFreshnessPolicy.showsRefreshProgress(isCheckingSchedule: checking,
                lastVerifiedAt: verified, refreshFailed: failed, now: now)
        }
        XCTAssertFalse(shows(false, nil, failed: true))
        XCTAssertFalse(shows(false, expired))
        XCTAssertFalse(shows(false, now, failed: true))
        XCTAssertFalse(shows(true, now))
        XCTAssertTrue(shows(true, nil))
        XCTAssertTrue(shows(true, expired))
        XCTAssertTrue(shows(true, now, failed: true))
        XCTAssertFalse(shows(true, now.addingTimeInterval(-FootballScheduleFreshnessPolicy.maximumAge)))
    }

    @MainActor
    func testCPLScheduleNeverBorrowsWillowSourcesAndExpiresAfterSeason() {
        let fixture = CPLSchedule.fixtures[18]
        let willow = cricketEvent(title: "Willow Cricket", date: nil)
        let schedule = CPLSchedule.merging(into: [willow], at: fixture.kickoff)
        XCTAssertTrue(schedule.contains { $0.id == willow.id })
        XCTAssertEqual(schedule.first { $0.id == fixture.id }?.broadcastTiming(at: fixture.kickoff), .available)
        let expired = CPLSchedule.merging(into: schedule, at: CPLSchedule.fixtures[38].kickoff.addingTimeInterval(48 * 3600))
        XCTAssertEqual(expired.map(\.id), [willow.id])
    }

    @MainActor
    private func cricketEvent(title: String, date: Int64?) -> AnalyticalDataEngine.EventReference {
        .init(id: "test-\(title)", title: title, category: "cricket", date: date, poster: nil, popular: nil, teams: nil)
    }

    private func legacyCPLAliases(for team: CPLTeam) -> [String] {
        switch team {
        case .antigua: return [team.rawValue, "Antigua and Barbuda Falcons", "Antigua Falcons"]
        case .barbados: return [team.rawValue, "Barbados Royals"]
        case .saintLucia: return [team.rawValue, "St Lucia Kings"]
        case .stKitts: return [team.rawValue, "St Kitts and Nevis Patriots", "Saint Kitts and Nevis Patriots", "St Kitts Nevis Patriots"]
        default: return [team.rawValue]
        }
    }

    private func legacyCPLTeamMatches(_ team: CPLTeam, in text: String) -> Bool {
        func normalized(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "&", with: "and")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let haystack = " " + normalized(text) + " "
        return legacyCPLAliases(for: team).contains { haystack.contains(" " + normalized($0) + " ") }
    }

    @MainActor
    private func legacyIsCPLFixture(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        guard (event.category ?? "").lowercased() == "cricket" else { return false }
        let channelName = (event.title ?? "").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        guard !["willow", "willowtv", "willowcricket", "willowhd", "willow2", "foxcricket", "foxcrickethd"].contains(channelName) else {
            return false
        }
        let text = [event.title, event.teams?.home?.name, event.teams?.away?.name]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("caribbean premier league") || text.range(of: #"\bcpl\b"#, options: .regularExpression) != nil {
            return true
        }
        return CPLTeam.allCases.filter { legacyCPLTeamMatches($0, in: text) }.count >= 2
    }

    func testHelpKeepsBackgroundAlertsAndOfficialFPLActionsTruthful() {
        XCTAssertTrue(FottyHelpContent.matchAlerts.contains("not background push"))
        XCTAssertTrue(FottyHelpContent.matchAlerts.contains("Premier League"))
        XCTAssertTrue(FottyHelpContent.deadlineAlerts.contains("scheduled"))
        XCTAssertTrue(FottyHelpContent.fplDrafts.contains("Confirm any real changes in official FPL"))
        XCTAssertTrue(FottyHelpContent.scores.contains("Other competitions can still have broadcasts"))
        XCTAssertTrue(FottyHelpContent.fplPoints.contains("Provisional"))
    }

    func testManagerClearResetsLoadingAndErrorAndKeepsDraftStorage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/FPL/ViewModels/FPLAdvisorViewModel.swift"), encoding: .utf8)
        let body = try XCTUnwrap(source.components(separatedBy: "public func clearManagerId()").dropFirst().first)
            .components(separatedBy: "private func migrateLegacyLocalDataIfNeeded").first ?? ""
        for reset in ["isLoading = false", "isRefreshing = false", "errorMessage = nil", "bootstrap = nil", "managerId = nil", "rivalPicks = nil", "managerSelectionID = UUID()", "coachInputDraft = \"\"", "isCoachThinking = false", "comparisonPlayer1ID = nil", "comparisonPlayer2ID = nil"] {
            XCTAssertTrue(body.contains(reset), reset)
        }
        XCTAssertFalse(body.contains("removeObject"))
    }

    private static func identity(_ id: Int) -> FPLManagerIdentity {
        FPLManagerIdentity(id: id, teamName: "Test team \(id)", managerName: "Test manager", sourceDescription: "Test fixture")
    }
}

@MainActor
final class UsabilityPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testInlineContextRetainsOnlyItsExactEventAndResetsOnReuse() {
        var context = CatalogInlineContextState()
        XCTAssertFalse(context.isExpanded(for: "first"))
        context.toggle(for: "first")
        XCTAssertTrue(context.isExpanded(for: "first"))
        XCTAssertFalse(context.isExpanded(for: "second"), "A recycled row must not show another event's details")
        context.toggle(for: "first")
        XCTAssertFalse(context.isExpanded(for: "first"))
        context.toggle(for: "second")
        XCTAssertTrue(context.isExpanded(for: "second"))
        context.reset()
        XCTAssertNil(context.eventID)
    }

    func testInlineContextIsReadOnlyAndKeepsOneExistingActionOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Dashboard/CatalogEventDetailsView.swift"), encoding: .utf8)
        let inline = try XCTUnwrap(source.components(separatedBy: "struct CatalogInlineEventContext: View {").last?
            .components(separatedBy: "struct CatalogEventDetailsView: View {").first)
        XCTAssertTrue(inline.contains("CatalogEventDetailsPresentation.broadcast(for: event"))
        XCTAssertTrue(inline.contains("policy.hasUnconfirmedFixtureStart"))
        XCTAssertTrue(inline.contains("!event.isBroadcastChannel"))
        XCTAssertTrue(inline.contains("Button(\"More details\", action: onMoreDetails)"))
        for mutation in ["MatchReminderStore", "savedMatches.toggle", "onWatch?()", "viewing.open", "resolve(for:"] {
            XCTAssertFalse(inline.contains(mutation), "Inline reading must not duplicate Watch, Save or Remind: \(mutation)")
        }
    }

    func testHomeSearchInlineContextDoesNotReplaceDirectWatchOrResetTheContainer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rows = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"), encoding: .utf8)
        XCTAssertTrue(rows.contains("onWatch: onOpen"))
        XCTAssertTrue(rows.contains("onDetails: inlineDetailsAction"))
        XCTAssertTrue(rows.contains(".onChange(of: item.id) { _, _ in inlineContext.reset() }"))
        XCTAssertTrue(rows.contains("Shows or hides schedule and broadcast information in this list"))
        XCTAssertFalse(rows.contains("selectedCatalogEvent ="))
        XCTAssertFalse(rows.contains("proxy.scrollTo"), "A row disclosure must not move the browsing container")
    }

    func testMatchdayVisibleActionsDoNotAddControlsToPassiveSelectionCards() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let card = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Dashboard/Components/LiveEventCard.swift"), encoding: .utf8)
        XCTAssertTrue(card.contains("rowActions: visibleMatchActions"))
        XCTAssertTrue(card.contains("guard onDetailsTap != nil else { return nil }"))
        XCTAssertTrue(card.contains("canSave: onSaveTap != nil && !event.hasCatalogIdentityConflict"))
        XCTAssertTrue(card.contains("onSave: { onSaveTap?() }"))
        XCTAssertTrue(card.contains(".onChange(of: event.id) { _, _ in inlineContext.reset() }"))
        let matchday = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Social/ArenaDiscoveryView.swift"), encoding: .utf8)
        XCTAssertTrue(matchday.contains("onDetailsTap: { presentModal { selectedCatalogEvent = event } }"))
        XCTAssertTrue(matchday.contains("onSaveTap: { toggleSavedMatch(event) }"))
    }

    func testUpcomingEmptyCopyUsesTheSameWindowAsTheHomeProjection() {
        XCTAssertEqual(HomeUpcomingPresentationPolicy.horizon(personalized: false), 6 * 3_600)
        XCTAssertEqual(HomeUpcomingPresentationPolicy.horizon(personalized: true), 72 * 3_600)
        XCTAssertEqual(HomeUpcomingPresentationPolicy.emptyMessage(sport: "cricket", personalized: true,
            hasCurrentEvents: false), "No cricket events are starting in the next 3 days.")
        XCTAssertEqual(HomeUpcomingPresentationPolicy.emptyMessage(sport: nil, personalized: false,
            hasCurrentEvents: true), "Nothing else is starting in the next 6 hours.")
        XCTAssertEqual(HomeUpcomingPresentationPolicy.emptyMessage(sport: nil, personalized: true,
            hasCurrentEvents: true), "No other matches from your interests are scheduled in the next 3 days.")
    }

    func testDetailsChannelFallbackKeepsProgrammeUnconfirmedAndTerminalVeto() {
        let presentation = CatalogEventDetailsPresentation.broadcast(for: event(offset: -60), now: now,
            canWatchHere: true, isChannelFallback: true)
        XCTAssertEqual(presentation.title, "Cricket channel available")
        XCTAssertTrue(presentation.message.contains("programme on air is not confirmed"))
        XCTAssertFalse(presentation.message.contains("No supported stream"))
        let stopped = CatalogEventDetailsPresentation.broadcast(for: event(offset: -60), now: now,
            status: .finished, canWatchHere: true, isChannelFallback: true)
        XCTAssertEqual(stopped.symbol, "tv.slash", "A channel cannot revive a finished fixture")
    }

    func testMissingSourceAndUnknownStartDoNotPromiseAPlaybackTime() {
        let future = CatalogEventDetailsPresentation.broadcast(for: event(offset: 3_600), now: now)
        XCTAssertEqual(future.title, "Broadcast not listed")
        let unknown = CatalogEventDetailsPresentation.broadcast(for: event(offset: nil), now: now)
        XCTAssertTrue(unknown.message.contains("scheduled start is not confirmed"))
        XCTAssertFalse(unknown.message.contains("closer"))
    }

    func testFinishedMatchAndIdentityConflictCannotAdvertiseALiveBroadcast() {
        let stopped = CatalogEventDetailsPresentation.broadcast(for:
            event(offset: -60), now: now, status: .finished)
        XCTAssertEqual(stopped.title, "FT")
        XCTAssertEqual(stopped.symbol, "tv.slash")
        let quarantined = EventReference(id: "quarantined", title: "A vs B", category: "football", date: nil,
            poster: nil, popular: false, teams: nil,
            hasCatalogIdentityConflict: true)
        XCTAssertEqual(CatalogEventDetailsPresentation.broadcast(for: quarantined, now: now).title,
            "Listing needs an update")
    }

    func testLiveSourceFreeDetailsDoNotTellUsersToWaitForAPastStart() {
        let presentation = CatalogEventDetailsPresentation.broadcast(for: event(offset: -60), now: now, status: .inPlay)
        XCTAssertEqual(presentation.title, "Broadcast not listed")
        XCTAssertTrue(presentation.message.contains("right now"))
        XCTAssertFalse(presentation.message.contains("closer to the scheduled start"))
    }

    private func event(offset: TimeInterval?) -> EventReference {
        .init(id: "usability-fixture", title: "A vs B", category: "football",
            date: offset.map { Int64(now.addingTimeInterval($0).timeIntervalSince1970) },
            poster: nil, popular: false, teams: nil)
    }
}

@MainActor
final class HomeDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshCatalogWatchIsAnAttemptRatherThanAPlaybackReadinessClaim() {
        let listed = FixtureSourceLookupPresentation.State(currentCandidateCount: 0, previouslyFound: false,
            isChecking: false, catalogListedProviderCount: 1)
        XCTAssertTrue(listed.canWatch)
        XCTAssertEqual(listed.title, "Watch")
        XCTAssertEqual(listed.symbol, "play.fill")
        XCTAssertEqual(listed.detailsTitle, "Broadcast listed")
        XCTAssertEqual(listed.detailsMessage(canWatchHere: true), "Choose Watch to find and open the current broadcast.")
        XCTAssertEqual(listed.accessibilityLabel(matchTitle: "Arsenal vs Chelsea"), "Watch Arsenal vs Chelsea")
        let old = FixtureSourceLookupPresentation.State(currentCandidateCount: 0, previouslyFound: true,
            isChecking: false, catalogPreviouslyListed: true)
        XCTAssertFalse(old.canWatch)
        XCTAssertEqual(old.detailsTitle, "Broadcast unconfirmed")
        let ready = FixtureSourceLookupPresentation.State(currentCandidateCount: 1, previouslyFound: false,
            isChecking: false, catalogListedProviderCount: 1)
        XCTAssertEqual(ready.detailsTitle, "Ready to watch", "A listing must not be described as a validated delivery")
    }

    func testTestLifecycleDoesNotClaimActivePlayWithoutFreshPhase() throws {
        for row in [testCricket(phase: nil), testCricket(phase: .lunch,
            observedAt: now.addingTimeInterval(-CricketMatchContextPolicy.freshness - 1))] {
            let activity = try XCTUnwrap(CricketActivityPresentationPolicy.activity(for: row, at: now))
            XCTAssertEqual(activity.state, .ongoing)
            XCTAssertEqual(activity.title, "Test in progress")
            XCTAssertTrue(activity.suppressesLiveBadge)
            let item = HomeSportsDiscovery.Item(event: row, phase: .live, officialStatus: nil, now: now)
            XCTAssertFalse(item.hasConfirmedLiveStatus)
            XCTAssertEqual(item.prominentStatusLabel, "Test in progress")
            XCTAssertNil(HomeDiscoveryRow.Presentation(item: item).liveDetail)
        }
    }

    func testFreshCricketBreaksShareHonestLabelsWithoutRevokingBroadcast() throws {
        for phase: CricketMatchContext.Phase in [.lunch, .tea, .stumps, .matchBreak, .inningsBreak, .interrupted] {
            let row = testCricket(phase: phase)
            let activity = try XCTUnwrap(CricketActivityPresentationPolicy.activity(for: row, at: now))
            XCTAssertEqual(activity.title, phase.title)
            XCTAssertTrue(activity.suppressesLiveBadge)
            let item = HomeSportsDiscovery.Item(event: row, phase: .live, officialStatus: nil, now: now)
            XCTAssertEqual(item.prominentStatusLabel, phase.title)
            XCTAssertFalse(item.hasConfirmedLiveStatus)
            XCTAssertNil(HomeDiscoveryRow.Presentation(item: item).liveDetail)
            // A cricket fixture's Watch comes from a found exact candidate.
            let request = StreamPlaybackRequest(event: row), index = FixtureStreamDiscoveryIndex()
            index.updateEnabledProviders(["communitysports"], revision: 1)
            let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
                providerEventID: "nuvio_sport_test", streamID: "nuvio_sport_test", manifestRevision: "1",
                verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
            let session = StreamSession(matchID: row.id, playableURL: URL(string: "https://media.example/test-break.m3u8")!,
                streamType: .hls, providerName: "CS1", createdAt: now, eventBinding: binding)
            let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
            index.complete(ticket, sessions: [session], at: now)
            XCTAssertNotNil(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now, discoveryIndex: index),
                "An interval must not revoke the listed broadcast or stop its mounted player")
        }
        let active = testCricket(phase: .inPlay)
        XCTAssertEqual(CricketActivityPresentationPolicy.activity(for: active, at: now)?.state, .inPlay)
        XCTAssertTrue(HomeSportsDiscovery.Item(event: active, phase: .live, officialStatus: nil, now: now).hasConfirmedLiveStatus)
        XCTAssertNil(CricketActivityPresentationPolicy.activity(for: testCricket(phase: .stumps, status: .finished), at: now))
    }

    private func testCricket(phase: CricketMatchContext.Phase?, observedAt: Date? = nil,
                            status: CricketFixtureCatalog.Status = .live) -> EventReference {
        let home = "icc:1:7", away = "icc:1:1"
        let context = phase.map { CricketMatchContext(
            innings: [.init(number: 1, teamID: home, runs: 329, wickets: 10, overs: "82.3")],
            currentInnings: 1, day: 4, phase: $0) }
        let metadata = CricketFixtureMetadata(fixtureID: "icc:269792", competitionID: "icc",
            competitionName: "ICC international cricket", format: .test, status: status,
            observedAt: observedAt ?? now, verified: true, context: context,
            homeTeamID: home, awayTeamID: away)
        return .init(id: "cricket-fixture:icc:269792", title: "South Africa vs Australia", category: "cricket",
            date: Int64(now.addingTimeInterval(-3 * 86_400).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "South Africa", badge: nil), away: .init(name: "Australia", badge: nil)), cricketFixture: metadata)
    }

    private func event(_ id: String, sport: String = "football", offset: TimeInterval? = 0, home: String? = nil, away: String = "Visitors") -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: "\(home ?? id) vs \(away)", category: sport,
              date: offset.map { Int64(now.addingTimeInterval($0).timeIntervalSince1970) },
              poster: nil, popular: false,
              teams: .init(home: .init(name: home ?? id, badge: nil), away: .init(name: away, badge: nil)))
    }

    private func cricketFixture(
        _ id: String,
        status: CricketFixtureCatalog.Status,
        verified: Bool,
        offset: TimeInterval) -> AnalyticalDataEngine.EventReference {
        let metadata = CricketFixtureMetadata(
            fixtureID: id,
            competitionID: "west-indies",
            competitionName: "West Indies cricket",
            format: .odi,
            status: status,
            observedAt: now,
            verified: verified
        )
        return .init(
            id: "cricket-fixture:\(id)",
            title: "India vs West Indies",
            category: "cricket",
            date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970),
            poster: nil,
            popular: false,
            teams: .init(home: .init(name: "India", badge: nil), away: .init(name: "West Indies", badge: nil)),
            cricketFixture: metadata,
            competitionID: metadata.competitionID
        )
    }

    func testHomeCountsEventsNotSourceVariantsAndKeepsEveryRealSource() throws {
        let first = event("a", offset: -60, home: "City")
        let duplicate = event("b", offset: -60, home: " city ")
        let schedule = HomeSportsDiscovery(events: [duplicate, first], now: now, status: { _ in .inPlay })
        XCTAssertEqual(schedule.items.map(\.id), ["a"])
        XCTAssertEqual(schedule.activities.first { $0.id == "football" }?.onNow, 1)
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([first, duplicate]).map(\.id), ["a"])
    }

    func testStartedSourceLessCPLCountsAsOnNowFromItsListedStart() {
        let cpl = event(
            "cpl-2026-current",
            sport: "cricket",
            offset: -3600,
            home: "St Kitts & Nevis Patriots",
            away: "Saint Lucia Kings"
        )
        let schedule = HomeSportsDiscovery(events: [cpl], now: now)
        XCTAssertTrue(schedule.items.first?.isOnNow == true)
        XCTAssertEqual(schedule.items.first?.statusLabel, cpl.kickoffDate?.arenaKickoffDetailLine())
        XCTAssertEqual(schedule.activities.first { $0.id == "cricket" }?.onNow, 1)
        XCTAssertEqual(schedule.activities.first { $0.id == "cricket" }?.summary(at: now), "1 listed")
    }

    func testSportActivityScopeKeepsCricketTileConsistentWithCPLAndChannels() throws {
        let international = cricketFixture("india-west-indies", status: .live, verified: true, offset: -900)
        let cpl = event("cpl-current", sport: "cricket", offset: -600,
                        home: "Trinbago Knight Riders", away: "Barbados Tridents")
        let willow = AnalyticalDataEngine.EventReference(
            id: "willow", title: "Willow Cricket", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil)
        let football = event("football-live", offset: -60, home: "Arsenal", away: "Chelsea")
        let schedule = HomeSportsDiscovery(events: [international, cpl, willow, football], now: now) {
            $0.id == football.id ? .inPlay : nil
        }

        func activities(filter: CricketCatalogFilter) -> [HomeSportsDiscovery.SportActivity] {
            let scope = HomeSportActivityScope(
                selectedSport: "cricket",
                selectedFootballLeague: .all,
                selectedCricketFilter: filter,
                showFollowedOnly: false,
                restrictToHomeInterests: false
            )
            return schedule.activities(
                scopedItems: schedule.items.filter {
                    scope.includes($0, footballLeague: .all, isFollowed: false)
                },
                scopedChannels: schedule.channels.filter { scope.includes(channel: $0) }
            )
        }

        XCTAssertEqual(activities(filter: .all).first { $0.id == "cricket" }?.summary(at: now), "1 live")
        XCTAssertEqual(activities(filter: .cpl).first { $0.id == "cricket" }?.summary(at: now), "1 listed")
        XCTAssertEqual(activities(filter: .channels).first { $0.id == "cricket" }?.summary(at: now), "1 channel")
        XCTAssertEqual(activities(filter: .cpl).first { $0.id == "football" }?.summary(at: now), "1 live",
                       "A cricket subfilter must not alter another sport's honest summary")
    }

    func testSportActivityScopeAppliesHomeInterestsToEverySportAndHidesChannels() {
        let cricket = cricketFixture("india-west-indies", status: .live, verified: true, offset: -900)
        let football = event("football-live", offset: -60, home: "Arsenal", away: "Chelsea")
        let baseball = event("baseball-next", sport: "baseball", offset: 1800,
                             home: "Yankees", away: "Mets")
        let willow = AnalyticalDataEngine.EventReference(
            id: "willow", title: "Willow Cricket", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil)
        let schedule = HomeSportsDiscovery(events: [cricket, football, baseball, willow], now: now) {
            $0.id == football.id ? .inPlay : nil
        }
        let scope = HomeSportActivityScope(
            selectedSport: HomeSportsDiscovery.allSports,
            selectedFootballLeague: .all,
            selectedCricketFilter: .all,
            showFollowedOnly: false,
            restrictToHomeInterests: true
        )
        let activities = schedule.activities(
            scopedItems: schedule.items.filter {
                scope.includes($0, footballLeague: .all, isFollowed: $0.id == football.id)
            },
            scopedChannels: schedule.channels.filter { scope.includes(channel: $0) }
        )

        XCTAssertEqual(activities.first { $0.id == "football" }?.summary(at: now), "1 live")
        XCTAssertEqual(activities.first { $0.id == "cricket" }?.summary(at: now), "Nothing listed")
        XCTAssertEqual(activities.first { $0.id == "baseball" }?.summary(at: now), "Nothing listed")
    }

    func testUnverifiedFutureCricketDoesNotAdvertiseAConfidentCountdown() throws {
        let held = cricketFixture("held-future", status: .scheduled, verified: false, offset: 3600)
        let schedule = HomeSportsDiscovery(events: [held], now: now)
        let item = try XCTUnwrap(schedule.items.first)

        XCTAssertEqual(item.phase, .unconfirmed)
        XCTAssertEqual(item.statusLabel, "Start unconfirmed")
        XCTAssertEqual(schedule.activities.first { $0.id == "cricket" }?.summary(at: now), "Time TBC")
        XCTAssertTrue(schedule.homeSections(from: schedule.items, diverseUpcoming: false, featuredLiveLimit: 3).upcoming.isEmpty)
    }

    func testHomeNonTeamEventsDoNotInventAnOpponent() {
        for (title, sport) in [("TNA Impact", "fight"), ("Grand Prix qualifying", "motorsports")] {
            let event = AnalyticalDataEngine.EventReference(id: "single-event", title: title, category: sport, date: nil, poster: nil, popular: nil, teams: nil)
            XCTAssertEqual(event.displayTitle, title)
        }
        XCTAssertEqual(event("fixture", home: "Arsenal", away: "Chelsea").displayTitle, "Arsenal vs Chelsea")
        XCTAssertEqual(AnalyticalDataEngine.categoryDisplayName(for: "american-football"), "American football")
        XCTAssertEqual(AnalyticalDataEngine.sportIconName(for: "american-football"), "american.football.fill")
    }

    func testPlaybackActionsIdentifyTheirEventWithoutLosingActionMeaning() {
        let fixture = event("fixture", home: "Arsenal", away: "Chelsea")
        let otherFixture = event("other", home: "Liverpool", away: "Everton")
        let channelTitle = "Willow Cricket"
        XCTAssertEqual(MatchActionAccessibility.playbackLabel(
            title: "Watch", eventTitle: fixture.displayTitle, isChannel: false, isRetry: false
        ), "Watch Arsenal vs Chelsea")
        XCTAssertNotEqual(MatchActionAccessibility.playbackLabel(
            title: "Watch", eventTitle: fixture.displayTitle, isChannel: false, isRetry: false
        ), MatchActionAccessibility.playbackLabel(
            title: "Watch", eventTitle: otherFixture.displayTitle, isChannel: false, isRetry: false
        ))
        for title in ["Retry", "Not ready · Retry"] {
            XCTAssertEqual(MatchActionAccessibility.playbackLabel(
                title: title, eventTitle: fixture.displayTitle, isChannel: false, isRetry: true
            ), "\(title) Arsenal vs Chelsea")
        }
        XCTAssertEqual(MatchActionAccessibility.playbackLabel(
            title: "Watch", eventTitle: channelTitle, isChannel: true, isRetry: false
        ), "Watch channel Willow Cricket")
        XCTAssertEqual(MatchActionAccessibility.playbackLabel(
            title: "Retry", eventTitle: channelTitle, isChannel: true, isRetry: true
        ), "Retry Willow Cricket")
        XCTAssertEqual(MatchActionAccessibility.playbackLabel(
            title: "Open channel", eventTitle: fixture.displayTitle, isChannel: false, isRetry: false
        ), "Open channel Arsenal vs Chelsea")
    }

    func testHomeSportsUseRecognizableEquipmentArtwork() {
        XCTAssertNil(SportIdentity.artwork(for: HomeSportsDiscovery.allSports))
        XCTAssertEqual(SportIdentity.artwork(for: "football"), "⚽️")
        XCTAssertEqual(SportIdentity.artwork(for: "cricket"), "🏏")
        XCTAssertEqual(SportIdentity.artwork(for: "basketball"), "🏀")
        XCTAssertEqual(SportIdentity.artwork(for: "baseball"), "⚾️")
        XCTAssertEqual(SportIdentity.artwork(for: "tennis"), "🎾")
        XCTAssertEqual(SportIdentity.artwork(for: "american-football"), "🏈")
        XCTAssertEqual(SportIdentity.artwork(for: "fight"), "🥊")
    }

    func testGlobalSearchUsesHomesCatalogAcrossSportsLeaguesFixturesAndChannels() {
        let chelsea = event("chelsea-brighton", offset: 900, home: "Chelsea", away: "Brighton")
        let bogota = event("bogota", sport: "basketball", offset: 1_800, home: "Internacional de Bogotá")
        let cpl = event("cpl-2026-final", sport: "cricket", offset: 2_700,
                        home: "Trinbago Knight Riders", away: "Barbados Royals")
        let willow = AnalyticalDataEngine.EventReference(
            id: "willow", title: "Willow Cricket", category: "cricket", date: nil,
            poster: nil, popular: nil, teams: nil)
        let schedule = HomeSportsDiscovery(events: [chelsea, bogota, cpl, willow], now: now)
        let league: (AnalyticalDataEngine.EventReference) -> String? = {
            $0.id == chelsea.id ? "Premier League" : nil
        }

        XCTAssertEqual(HomeSportsSearch.results(in: schedule, query: "chelsea brighton", leagueName: league).map(\.id), [chelsea.id])
        XCTAssertEqual(HomeSportsSearch.results(in: schedule, query: "PREMIER LEAGUE", leagueName: league).map(\.id), [chelsea.id])
        XCTAssertEqual(HomeSportsSearch.results(in: schedule, query: "Bogota").map(\.id), [bogota.id])
        XCTAssertEqual(HomeSportsSearch.results(in: schedule, query: "CPL").map(\.id), [cpl.id])
        XCTAssertEqual(HomeSportsSearch.results(in: schedule, query: "channel").map(\.id), [willow.id])
        XCTAssertTrue(HomeSportsSearch.results(in: schedule, query: "   ").isEmpty)
    }

    func testHomeDeduplicationPreservesDoubleheadersDifferentSportsAndUnknownTeams() {
        let one = event("a", home: "City")
        let later = event("b", offset: 3600, home: "City")
        let otherSport = event("c", sport: "basketball", home: "City")
        let unknown1 = event("d", offset: nil, home: "Home", away: "Away")
        let unknown2 = event("e", offset: nil, home: "Home", away: "Away")
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([one, later, otherSport, unknown1, unknown2]).count, 5)
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([one, one]).count, 1)
    }

    func testHomeDeduplicationCollapsesOnlyExactReviewedTeamAliases() throws {
        let short = event(
            "provider-short",
            offset: -60,
            home: "Alaves",
            away: "Osasuna")
        let official = event(
            "provider-official",
            offset: -60,
            home: "Deportivo Alavés",
            away: "CA Osasuna")
        let similarlyNamedUnknown = event(
            "provider-unknown",
            offset: -60,
            home: "Deportivo Alaves B",
            away: "Osasuna")

        let events = HomeSportsDiscovery.uniqueEvents([short, official, similarlyNamedUnknown])
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.contains { $0.id == similarlyNamedUnknown.id })
    }

    func testHomeChannelsAndUnknownStartsStayOffNowWhileTrustedCPLUsesItsListedStart() {
        let willow = AnalyticalDataEngine.EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: -3_600_000, poster: nil, popular: nil, teams: nil)
        let snapshot = event("cpl-2026-test", sport: "cricket", offset: -3600, home: "Trinbago Knight Riders", away: "Barbados Tridents")
        let unknownCricket = event("test-match", sport: "cricket", offset: -3600)
        let unknownStart = event("undated", offset: nil)
        let noSource = event("source-free", offset: -60)
        let schedule = HomeSportsDiscovery(events: [willow, snapshot, unknownCricket, unknownStart, noSource], now: now)
        XCTAssertEqual(schedule.channels.map(\.id), ["willow"])
        XCTAssertEqual(schedule.items.count, 4)
        XCTAssertTrue(schedule.items.first { $0.id == snapshot.id }?.isOnNow == true)
        XCTAssertTrue(schedule.items.filter { $0.id != snapshot.id }.allSatisfy { !$0.isOnNow })
        XCTAssertEqual(schedule.activities.first { $0.id == "cricket" }?.onNow, 1)
        XCTAssertEqual(schedule.featured(from: schedule.items, diverse: true).map(\.id), [snapshot.id])
        XCTAssertEqual(schedule.items.first { $0.id == snapshot.id }?.actionTitle, "No stream listed")
    }

    func testHomeOfficialStatusOverridesEstimatedTimingAndExpiredEventsDisappear() {
        let past = event("expired", offset: -3 * 3600)
        let finished = event("finished", offset: -60)
        let cancelled = event("cancelled", offset: 60)
        let postponed = event("postponed", offset: 3600)
        let live = event("live", offset: -3 * 3600)
        let schedule = HomeSportsDiscovery(events: [past, finished, cancelled, postponed, live], now: now) {
            ["finished": .finished, "cancelled": .cancelled, "postponed": .postponed, "live": .inPlay][$0.id]
        }
        XCTAssertEqual(Set(schedule.items.map(\.id)), ["live", "postponed"])
        XCTAssertEqual(schedule.items.first { $0.id == "live" }?.phase, .live)
        XCTAssertEqual(schedule.items.first { $0.id == "live" }?.statusLabel, "In play")
        XCTAssertEqual(schedule.items.first { $0.id == "postponed" }?.statusLabel, "Postponed")
        XCTAssertEqual(schedule.items.first { $0.id == "postponed" }?.phase, .unconfirmed)
    }

    func testHomeFeaturedHasThreeSportsBeforeRepeatingOneAndStableTies() {
        let events = [event("football-2", offset: 600), event("football-1", offset: 600), event("basketball", sport: "basketball", offset: 1200), event("cricket", sport: "cricket", offset: 1800), event("far", sport: "tennis", offset: 7 * 3600)]
        let schedule = HomeSportsDiscovery(events: events, now: now)
        let featured = schedule.featured(from: schedule.items, diverse: true)
        XCTAssertEqual(featured.map(\.id), ["football-1", "basketball", "cricket"])
        let reversed = HomeSportsDiscovery(events: events.reversed(), now: now)
        XCTAssertEqual(reversed.featured(from: reversed.items, diverse: true).map(\.id), featured.map(\.id))
        let football = schedule.scopedItems(sport: "football")
        XCTAssertEqual(schedule.featured(from: football, diverse: false).count, 2)
        XCTAssertTrue(schedule.scopedItems(sport: "rugby").isEmpty)
        XCTAssertEqual(schedule.scopedItems(sport: HomeSportsDiscovery.allSports).count, 5)
        let active = HomeSportsDiscovery(events: [
            event("earlier-other", sport: "other", offset: -1200),
            event("football", offset: -300), event("basketball", sport: "basketball", offset: -600),
            event("baseball", sport: "baseball", offset: -900)
        ], now: now, status: { _ in .inPlay })
        XCTAssertEqual(active.featured(from: active.items, diverse: true).map(\.sport), ["football", "basketball", "baseball"])
    }

    func testHomeKeepsLowerPriorityLiveEventsReachableUnderMoreLive() {
        let live = (1...5).map {
            event("live-\($0)", offset: TimeInterval(-$0 * 60))
        }
        let upcoming = (1...5).map {
            event("upcoming-\($0)", offset: TimeInterval($0 * 300))
        }
        let schedule = HomeSportsDiscovery(events: live + upcoming, now: now,
            status: { $0.id.hasPrefix("live-") ? .inPlay : nil })
        let sections = schedule.homeSections(from: schedule.items, diverseUpcoming: false, featuredLiveLimit: 3)

        XCTAssertEqual(sections.featuredLive.map(\.id), ["live-5", "live-4", "live-3"])
        XCTAssertEqual(sections.moreLive.map(\.id), ["live-2", "live-1"])
        XCTAssertEqual(Set((sections.featuredLive + sections.moreLive).map(\.id)), Set(live.map(\.id)))
        XCTAssertEqual(sections.upcoming.count, 3)
        XCTAssertTrue(sections.upcoming.allSatisfy { !$0.isOnNow })
    }

    func testTailoredHomePinsNextClubAndPromotesItsConfirmedLiveFixture() {
        let other = event("other", home: "Arsenal")
        let club = event("club", home: "Liverpool")
        let tomorrow = event("tomorrow", offset: 86400, home: "Liverpool")
        let schedule = HomeSportsDiscovery(events: [other, club, tomorrow], now: now)
        let keys: Set<String> = [TeamFollowKey.make(name: "Liverpool", category: "football")]
        func item(_ event: AnalyticalDataEngine.EventReference, _ phase: HomeSportsDiscovery.Item.Phase) -> HomeSportsDiscovery.Item {
            .init(event: event, phase: phase, officialStatus: nil, now: now)
        }
        for limit in [3, 4] {
            let base = [item(other, .live), item(tomorrow, .upcoming)]
            let sections = schedule.homeSections(from: base, diverseUpcoming: false, featuredLiveLimit: limit, followedTeamKeys: keys)
            XCTAssertEqual(sections.featuredLive.first?.id, other.id)
            XCTAssertEqual(sections.nextClub?.id, tomorrow.id)
            XCTAssertFalse(sections.upcoming.contains { $0.id == tomorrow.id })
            let during = schedule.homeSections(from: base + [item(club, .live)], diverseUpcoming: false, featuredLiveLimit: limit, followedTeamKeys: keys)
            XCTAssertEqual(during.spotlight?.id, club.id)
            XCTAssertEqual(during.clubBelowSpotlight?.id, tomorrow.id)
            let quiet = schedule.homeSections(from: [item(other, .listedNow), item(tomorrow, .upcoming)],
                diverseUpcoming: false, featuredLiveLimit: limit, followedTeamKeys: keys)
            XCTAssertEqual(quiet.spotlight?.id, tomorrow.id)
            XCTAssertNil(quiet.clubBelowSpotlight)
            XCTAssertEqual(quiet.remainingFeatured.map(\.id), [other.id])
            let filtered = schedule.homeSections(from: [item(other, .live)], diverseUpcoming: false,
                featuredLiveLimit: limit, followedTeamKeys: keys)
            XCTAssertNil(filtered.nextClub)
        }
    }

    func testHomeLiveSectionRespectsDeviceSpecificProminenceLimit() {
        let live = (1...6).map {
            event("live-\($0)", offset: TimeInterval(-$0 * 60))
        }
        let schedule = HomeSportsDiscovery(events: live, now: now, status: { _ in .inPlay })

        let phone = schedule.homeSections(from: schedule.items, diverseUpcoming: true, featuredLiveLimit: 3)
        let pad = schedule.homeSections(from: schedule.items, diverseUpcoming: true, featuredLiveLimit: 4)

        XCTAssertEqual(phone.featuredLive.count, 3)
        XCTAssertEqual(phone.moreLive.count, 3)
        XCTAssertEqual(pad.featuredLive.count, 4)
        XCTAssertEqual(pad.moreLive.count, 2)
    }

    func testPersonalizedHomeShowsThreeDaysChronologicallyWithinDeviceLimit() {
        let events = [
            event("first", sport: "cricket", offset: 25 * 3600),
            event("second", offset: 36 * 3600),
            event("third", sport: "basketball", offset: 48 * 3600),
            event("fourth", offset: 60 * 3600),
            event("edge", sport: "baseball", offset: 72 * 3600),
            event("outside", offset: 72 * 3600 + 1)
        ]
        let schedule = HomeSportsDiscovery(events: events, now: now)

        let phone = schedule.homeSections(
            from: schedule.items,
            diverseUpcoming: false,
            featuredLiveLimit: 3,
            upcomingHorizon: CatalogTimingPolicy.personalizedHomeUpcomingHorizon,
            upcomingLimit: 3
        )
        let pad = schedule.homeSections(
            from: schedule.items,
            diverseUpcoming: false,
            featuredLiveLimit: 4,
            upcomingHorizon: CatalogTimingPolicy.personalizedHomeUpcomingHorizon,
            upcomingLimit: 4
        )

        XCTAssertEqual(phone.upcoming.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(pad.upcoming.map(\.id), ["first", "second", "third", "fourth"])
        XCTAssertFalse((phone.upcoming + pad.upcoming).contains { $0.id == "outside" })
        XCTAssertEqual(
            schedule.featured(
                from: schedule.items,
                diverse: false,
                upcomingHorizon: CatalogTimingPolicy.personalizedHomeUpcomingHorizon,
                limit: 10
            ).map(\.id),
            ["first", "second", "third", "fourth", "edge"]
        )
    }

    func testUpcomingAvailabilityEqualizationDoesNotChangeBroadLiveOrUnfollowedRanking() {
        for personalized in [false, true] {
            for followed in [false, true] {
                for upcoming in [false, true] {
                    let rank = HomeUpcomingPresentationPolicy.availabilityRank(
                        equalizeSelectedInterests: personalized, isFollowed: followed, isUpcoming: upcoming)
                    XCTAssertEqual(rank, personalized && followed && upcoming ? 0 : 1)
                }
            }
        }
    }

    func testHomePriorityIsComputedOncePerItemOutsideTheSortComparator() {
        let events = (1...40).map {
            event("rank-\($0)", offset: TimeInterval($0))
        }
        let items = HomeSportsDiscovery(events: events, now: now).items
        var evaluations = 0
        let ordered = HomeSportsDiscovery.prioritized(items) { item in
            evaluations += 1
            return .init(phase: 1, relevance: item.id == "rank-40" ? 0 : 1, available: 0)
        }

        XCTAssertEqual(evaluations, items.count)
        XCTAssertEqual(ordered.first?.id, "rank-40")
    }

    func testHomeAudienceRelevanceKeepsMajorMatchesAheadOfUnrelatedListings() {
        XCTAssertEqual(
            SportsTeamIdentity.sharedMajorLeague(
                home: "Chicago White Sox", away: "Detroit Tigers", category: "baseball"
            ),
            "mlb"
        )
        XCTAssertNil(
            SportsTeamIdentity.sharedMajorLeague(
                home: "Marietta Pioneers", away: "Capital Crusaders", category: "american-football"
            )
        )
        let followedChampionsLeague = HomeSportsDiscovery.relevanceRank(
            sport: "football", footballLeague: .championsLeague, isFollowed: true, isCPL: false
        )
        let premierLeague = HomeSportsDiscovery.relevanceRank(
            sport: "football", footballLeague: .premierLeague, isFollowed: false, isCPL: false
        )
        let championsLeague = HomeSportsDiscovery.relevanceRank(
            sport: "football", footballLeague: .championsLeague, isFollowed: false, isCPL: false
        )
        let cpl = HomeSportsDiscovery.relevanceRank(
            sport: "cricket", footballLeague: nil, isFollowed: false, isCPL: true
        )
        let topEuropeanLeague = HomeSportsDiscovery.relevanceRank(
            sport: "football", footballLeague: .laLiga, isFollowed: false, isCPL: false
        )
        let otherSport = HomeSportsDiscovery.relevanceRank(
            sport: "basketball", footballLeague: nil, isFollowed: false, isCPL: false
        )
        let majorLeagueSport = HomeSportsDiscovery.relevanceRank(
            sport: "baseball", footballLeague: nil, isFollowed: false, isCPL: false,
            isMajorLeague: true
        )
        let otherFootball = HomeSportsDiscovery.relevanceRank(
            sport: "football", footballLeague: .other, isFollowed: false, isCPL: false
        )

        XCTAssertEqual(
            [followedChampionsLeague, premierLeague, championsLeague, cpl, topEuropeanLeague, majorLeagueSport, otherSport, otherFootball],
            [0, 1, 2, 3, 4, 8, 9, 10]
        )
        XCTAssertEqual(
            HomeSportsDiscovery.relevanceRank(
                sport: "football", footballLeague: .other, isFollowed: true, isCPL: false
            ),
            3,
            "An explicit follow remains a strong preference without becoming a global importance claim"
        )
    }

    func testHomeLaterListIsBoundedHasNoDuplicatesAndRespectsLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -4 * 3600)!
        let day = calendar.startOfDay(for: now).addingTimeInterval(18 * 3600)
        let futureEvents = (1...7).map { i in
            AnalyticalDataEngine.EventReference(id: "later-\(i)", title: "Team \(i) vs Visitors", category: "football", date: Int64(day.addingTimeInterval(Double(i) * 3600).timeIntervalSince1970), poster: nil, popular: nil, teams: nil)
        }
        let schedule = HomeSportsDiscovery(events: futureEvents, now: day)
        let featured = schedule.featured(from: schedule.items, diverse: true)
        let later = schedule.later(from: schedule.items, excluding: featured, calendar: calendar)
        XCTAssertEqual(later.title, "Later today")
        XCTAssertEqual(later.items.map(\.id), ["later-4", "later-5"])
        let tomorrow = schedule.later(from: Array(schedule.items.suffix(1)), excluding: [], calendar: calendar)
        XCTAssertEqual(tomorrow.title, "Coming up")
        XCTAssertEqual(tomorrow.items.map(\.id), ["later-7"])
    }

    func testBroadHomeLaterKeepsItsExistingTwoDayBoundary() {
        let retained = HomeSportsDiscovery(
            events: [event("forty-seven-hours", offset: 47 * 3600)],
            now: now
        )
        let excluded = HomeSportsDiscovery(
            events: [event("forty-nine-hours", offset: 49 * 3600)],
            now: now
        )

        XCTAssertEqual(retained.later(from: retained.items, excluding: []).items.map(\.id), ["forty-seven-hours"])
        XCTAssertTrue(excluded.later(from: excluded.items, excluding: []).items.isEmpty)
    }

    func testHomeActivityGridIsBoundedAndKeepsSelectedOverflowSportVisible() {
        let sports = ["football", "basketball", "cricket", "baseball", "tennis", "hockey", "rugby", "fight"]
        let schedule = HomeSportsDiscovery(events: sports.map { event($0, sport: $0, offset: 300) }, now: now)
        XCTAssertEqual(schedule.visibleActivities(selectedSport: HomeSportsDiscovery.allSports).count, 5)
        let selected = schedule.visibleActivities(selectedSport: "rugby")
        XCTAssertEqual(selected.count, 5)
        XCTAssertTrue(selected.contains { $0.id == "rugby" })
        let empty = HomeSportsDiscovery(events: [], now: now)
        XCTAssertEqual(empty.activities.first?.summary(at: now), "Nothing listed")
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testHomeSportSelectionRevalidatesSameCountCatalogReplacement() {
        let model = MatchListViewModel(refreshSchedule: { nil })
        model.matches = [event("hockey", sport: "hockey"), event("cricket", sport: "cricket")]
        let oldCount = model.matches.count
        let oldSports = model.sportsTabs
        XCTAssertEqual(HomeSportSelectionPolicy.validatedSelection("hockey", availableSports: oldSports), "hockey")

        model.matches = [event("basketball", sport: "basketball"), event("cricket", sport: "cricket")]

        XCTAssertEqual(model.matches.count, oldCount, "Count alone cannot detect this replacement")
        XCTAssertNotEqual(model.sportsTabs, oldSports)
        XCTAssertEqual(HomeSportSelectionPolicy.validatedSelection("hockey", availableSports: model.sportsTabs), HomeSportsDiscovery.allSports)
        XCTAssertEqual(HomeSportSelectionPolicy.validatedSelection("cricket", availableSports: model.sportsTabs), "cricket")
        XCTAssertEqual(HomeSportSelectionPolicy.validatedSelection(HomeSportsDiscovery.allSports, availableSports: model.sportsTabs), HomeSportsDiscovery.allSports)
    }

    func testHomeSelectionWaitsForAvailabilityInsteadOfResettingDuringAnEmptyLoad() {
        XCTAssertEqual(HomeSportSelectionPolicy.validatedSelection("hockey", availableSports: []), "hockey")
    }

    func testHomeSportsOverflowIsOnlyForCompactPhones() {
        XCTAssertFalse(SportActivityGrid.showsAllSports(expanded: false, regularWidth: false, isPad: false))
        XCTAssertTrue(SportActivityGrid.showsAllSports(expanded: true, regularWidth: false, isPad: false))
        XCTAssertTrue(SportActivityGrid.showsAllSports(expanded: false, regularWidth: true, isPad: false))
        XCTAssertTrue(SportActivityGrid.showsAllSports(expanded: false, regularWidth: false, isPad: true), "Split View keeps every iPad sport visible in additional rows")
    }

    func testSportGridFillsWidthWithEqualCellsIncludingPartialLastRow() {
        let layout = SportTileGridLayout(minimumTileWidth: 94)
        var grid = layout.metrics(width: 920, count: 11)
        grid.tileHeight = 112
        XCTAssertEqual(grid.columns, 9)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.size.width, 920)
        XCTAssertEqual(grid.size.height, 230)
        XCTAssertEqual(grid.origin(at: 8).x + grid.tileWidth, 920, accuracy: 0.01)
        XCTAssertEqual(grid.origin(at: 9), CGPoint(x: 0, y: 118))
        XCTAssertEqual(grid.origin(at: 10).x, grid.tileWidth + 6)
        XCTAssertEqual(layout.metrics(width: 343, count: 6).columns, 3)
        XCTAssertEqual(SportTileGridLayout(minimumTileWidth: 210).metrics(width: 343, count: 6).columns, 1)
        XCTAssertEqual(SportTileGridLayout(minimumTileWidth: 210).metrics(width: 920, count: 11).columns, 4)
    }

    func testWideLayoutUsesAvailableWidthAndProtectsLargeText() {
        for width: CGFloat in [0, 375, 430, 600, 820, 932, 999, .nan, .infinity] {
            XCTAssertFalse(FottyLayoutPolicy.usesColumns(width: width), "Width \(width)")
        }
        for width: CGFloat in [1000, 1180, 1366] {
            XCTAssertTrue(FottyLayoutPolicy.usesColumns(width: width))
            XCTAssertFalse(FottyLayoutPolicy.usesColumns(width: width, accessibilitySize: true))
        }
    }

    func testAdaptiveCatalogRowsPreserveEveryFixtureAndItsOrder() {
        let items = HomeSportsDiscovery(events: (0..<7).map { event("wide-\($0)", offset: Double($0 * 60)) }, now: now).items
        for columns in [0, 1, 2] {
            let rows = FottyLayoutPolicy.rows(items, columns: columns)
            XCTAssertEqual(rows.flatMap(\.items).map(\.id), items.map(\.id))
            XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        }
        let wide = FottyLayoutPolicy.rows(items, columns: 2)
        XCTAssertEqual(wide.map { $0.items.count }, [2, 2, 2, 1])
        XCTAssertTrue(FottyLayoutPolicy.rows(Array(items.prefix(0)), columns: 2).isEmpty)
    }

    func testHomeKickoffTransitionPartitionsFixturesAndReplacesOnlyChangedRows() throws {
        let events = [
            event("cpl-2026-today", sport: "cricket", offset: 3900),
            event("cpl-2026-next", sport: "cricket", offset: 7500),
            event("cpl-2026-tomorrow", sport: "cricket", offset: 25 * 3600)
        ]
        let before = HomeSportsDiscovery(events: events, now: now)
        let after = HomeSportsDiscovery(events: events, now: now.addingTimeInterval(6000))
        let initial = before.homeSections(from: before.items, diverseUpcoming: false, featuredLiveLimit: 4)
        let updated = after.homeSections(from: after.items, diverseUpcoming: false, featuredLiveLimit: 4)
        XCTAssertTrue(initial.featuredLive.isEmpty)
        XCTAssertEqual(updated.featuredLive.map(\.id), [events[0].id])
        XCTAssertEqual(updated.upcoming.map(\.id), [events[1].id])
        XCTAssertEqual(after.activities.first { $0.id == "cricket" }?.onNow, 1)
        XCTAssertEqual(updated.featuredLive.first?.actionTitle, "No stream listed")
        XCTAssertEqual(updated.upcoming.first?.actionTitle, "Starts in 25m")
        let originalRow = try XCTUnwrap(HomeSportsDiscovery.displayRows(initial.upcoming, columns: 2, section: "upcoming").first)
        let liveRow = try XCTUnwrap(HomeSportsDiscovery.displayRows(updated.featuredLive, columns: 1, section: "live").first)
        XCTAssertNotEqual(originalRow.id, liveRow.id)
        // Even a one-card row needs a new layout identity across the breakpoint.
        XCTAssertNotEqual(liveRow.id, HomeSportsDiscovery.displayRows(updated.featuredLive, columns: 2, section: "live").first?.id)
        XCTAssertNotEqual(liveRow.id, HomeSportsDiscovery.displayRows(updated.featuredLive, columns: 1, section: "upcoming").first?.id)
        let nextTick = HomeSportsDiscovery(events: events, now: now.addingTimeInterval(6060))
        let nextSections = nextTick.homeSections(from: nextTick.items, diverseUpcoming: false, featuredLiveLimit: 4)
        XCTAssertEqual(liveRow.id, HomeSportsDiscovery.displayRows(nextSections.featuredLive, columns: 1, section: "live").first?.id,
                       "Routine clock ticks must not recreate every row or reset scrolling")
        let later = after.later(from: after.items, excluding: updated.upcoming)
        XCTAssertEqual(later.items.map(\.id), [events[2].id])
    }

    func testHomeClockWakesAtKickoffWithoutMakingEveryRowTickEachSecond() {
        XCTAssertEqual(HomeSportsDiscovery.nextClockDelay(events: [], now: now), 60)
        XCTAssertEqual(HomeSportsDiscovery.nextClockDelay(events: [event("future", offset: 3600)], now: now), 60)
        XCTAssertEqual(HomeSportsDiscovery.nextClockDelay(events: [event("imminent", offset: 7)], now: now), 7)
        XCTAssertEqual(HomeSportsDiscovery.nextClockDelay(events: [event("started", offset: -1)], now: now), 60)
    }

    func testTabletSportsGridBalancesRowsWithoutNarrowingTiles() {
        let layout = SportTileGridLayout(minimumTileWidth: 142, balancesRows: true)
        let landscape = layout.metrics(width: 1148, count: 10)
        XCTAssertEqual(landscape.columns, 5, "Ten sports must not become nine plus an orphan")
        XCTAssertEqual(landscape.rows, 2)
        XCTAssertGreaterThanOrEqual(landscape.tileWidth, 142)
        for count in 2...15 {
            let grid = layout.metrics(width: 1148, count: count)
            XCTAssertGreaterThanOrEqual(grid.tileWidth, 142)
            if grid.rows > 1 { XCTAssertNotEqual(count % grid.columns, 1, "Avoid orphan tile for \(count) sports") }
            XCTAssertEqual(grid.origin(at: grid.columns - 1).x + grid.tileWidth, 1148, accuracy: 0.01)
        }
    }

    func testSportGridHandlesEmptyAndUnspecifiedSizeProposals() {
        let phone = SportTileGridLayout(minimumTileWidth: 94, maximumColumns: 3)
        XCTAssertEqual(phone.metrics(width: 398, count: 6).columns, 3,
                       "Pro Max must retain the approved three-column phone composition")
        XCTAssertEqual(phone.metrics(width: 206, count: 6).columns, 2)
        let layout = SportTileGridLayout(minimumTileWidth: 94)
        XCTAssertEqual(layout.metrics(width: 920, count: 0).size, CGSize(width: 920, height: 0))
        for width: CGFloat? in [nil, .infinity, .nan] {
            let grid = layout.metrics(width: width, count: 4)
            XCTAssertEqual(grid.columns, 1)
            XCTAssertEqual(grid.tileWidth, 94)
        }
        XCTAssertEqual(layout.metrics(width: 0, count: 4).tileWidth, 0)
        XCTAssertEqual(layout.metrics(width: -10, count: 4).columns, 1)
    }

    func testSportGridMeasuresTheTallestTileAcrossEveryRow() throws {
        let content = SportTileGridLayout(minimumTileWidth: 94) {
            ForEach([44.0, 60.0, 124.0], id: \.self) { height in
                Color.gray.frame(minHeight: height, maxHeight: .infinity)
            }
        }.frame(width: 206)
        let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
        XCTAssertEqual(image.size.width, 206, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 254, accuracy: 0.01, "Both rows must use 124 points, even though the tallest cell is alone in the last row")
    }

    @MainActor
    func testCompactPhoneSportsGridStaysWithinTwoShortRows() throws {
        let sports = ["football", "cricket", "baseball", "fight", "american-football"]
        let schedule = HomeSportsDiscovery(events: sports.map { event($0, sport: $0, offset: 300) }, now: now)
        let content = SportActivityGrid(discovery: schedule, selectedSport: .constant(HomeSportsDiscovery.allSports),
                                        showsMoreLink: false, isPad: false)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.dynamicTypeSize, .large)
            .frame(width: 361)
            .background(FottyTheme.background)
            .environment(\.colorScheme, .dark)
        let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
        let evidence = XCTAttachment(image: image)
        evidence.name = "compact-phone-sports-grid"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertLessThanOrEqual(image.size.height, 190,
                                 "Phone sports controls must not consume the old poster-sized grid height")
        XCTAssertGreaterThan(image.size.height, 88, "Keep two real rows with usable touch targets")
    }

    func testHomeStaleOrUnavailableScoresCannotKeepActivityLive() {
        XCTAssertEqual(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now.addingTimeInterval(-240), liveFeedAvailable: true, now: now), .inPlay)
        XCTAssertNil(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now.addingTimeInterval(-601), liveFeedAvailable: true, now: now))
        XCTAssertNil(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now, liveFeedAvailable: false, now: now))
        XCTAssertNil(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: nil, liveFeedAvailable: true, now: now))
        XCTAssertEqual(HomeSportsDiscovery.recentStatus(.finished, refreshedAt: nil, liveFeedAvailable: false, now: now), .finished)
        XCTAssertEqual(HomeSportsDiscovery.recentStatus(.postponed, refreshedAt: nil, liveFeedAvailable: false, now: now), .postponed)
    }

    func testAppearanceDefaultsToDarkAndSupportsExplicitLightOrSystem() {
        XCTAssertEqual(FottyAppearance.saved(""), .dark)
        XCTAssertEqual(FottyAppearance.saved("invalid"), .dark)
        XCTAssertEqual(FottyAppearance.saved("light").colorScheme, .light)
        XCTAssertEqual(FottyAppearance.saved("dark").colorScheme, .dark)
        XCTAssertNil(FottyAppearance.saved("system").colorScheme)
        let suite = "FottyAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(FottyAppearance.light.rawValue, forKey: FottyAppearance.storageKey)
        let reloaded = UserDefaults(suiteName: suite)!
        XCTAssertEqual(FottyAppearance.saved(reloaded.string(forKey: FottyAppearance.storageKey) ?? ""), .light)
    }

    @MainActor
    func testSportIdentityUsesAvailableEquipmentSymbolsAcrossCatalogVariants() {
        let expected = [
            "all": "square.grid.2x2.fill",
            "football": "soccerball",
            "soccer": "soccerball",
            "basketball": "basketball.fill",
            "NBA": "basketball.fill",
            "baseball": "baseball.fill",
            "MLB": "baseball.fill",
            "cricket": "cricket.ball.fill",
            "tennis": "tennisball.fill",
            "table tennis": "figure.table.tennis",
            "hockey": "hockey.puck.fill",
            "American Football": "american.football.fill",
            "nfl": "american.football.fill",
            "rugby union": "figure.rugby",
            "boxing": "figure.boxing",
            "f1": "flag.checkered",
            "darts": "scope",
            "golf": "figure.golf",
            "volleyball": "volleyball.fill",
            "college sports": "graduationcap.fill"
        ]
        for (sport, symbol) in expected {
            XCTAssertEqual(SportIdentity.symbol(for: sport), symbol)
            XCTAssertEqual(AnalyticalDataEngine.sportIconName(for: sport), symbol)
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing equipment artwork for \(sport)")
        }
    }

    func testSportIdentityHasOneStableFallbackInsteadOfEmojiArtwork() {
        XCTAssertEqual(SportIdentity.symbol(for: "unknown-sport"), "sportscourt.fill")
        XCTAssertEqual(SportIdentity.symbol(for: "all-sports"), "square.grid.2x2.fill")
        XCTAssertEqual(SportIdentity.symbol(for: "motor_sports"), "flag.checkered")
        XCTAssertNotEqual(SportIdentity.symbol(for: "American Football"), SportIdentity.symbol(for: "football"))
    }

    func testTwoMatchEligibilityIsSinglePassAndStopsAfterSecondCandidate() {
        let cases: [[Bool]] = [[], [false], [true], [false, true],
                              [true, true], [false, true, false, true, true]]
        for candidates in cases {
            var visited: [Int] = []
            let actual = TwoMatchSelectionPolicy.hasTwoCandidates(in: candidates.indices) { index in
                visited.append(index)
                return candidates[index]
            }
            XCTAssertEqual(actual, candidates.filter { $0 }.count >= 2)
            let second = candidates.indices.filter { candidates[$0] }.dropFirst().first
            XCTAssertEqual(visited, Array(candidates.indices.prefix(second.map { $0 + 1 } ?? candidates.count)))
        }
    }

    func testTwoMatchEligibilityVisitsNoCandidateCatalogOnlyOnce() {
        var calls = 0
        XCTAssertFalse(TwoMatchSelectionPolicy.hasTwoCandidates(in: 0..<3_000) { _ in
            calls += 1
            return false
        })
        XCTAssertEqual(calls, 3_000)
    }

    func testTwoMatchSelectionPreservesOrderAndCapsAtTwo() {
        var selection: [String] = []
        selection = TwoMatchSelectionPolicy.toggled(selection, eventID: "first")
        selection = TwoMatchSelectionPolicy.toggled(selection, eventID: "second")
        XCTAssertEqual(selection, ["first", "second"])
        XCTAssertEqual(TwoMatchSelectionPolicy.position(of: "second", in: selection), 2)

        XCTAssertEqual(
            TwoMatchSelectionPolicy.toggled(selection, eventID: "third"),
            ["first", "second"],
            "A third tap must not silently replace either chosen match"
        )
        XCTAssertEqual(TwoMatchSelectionPolicy.toggled(selection, eventID: "first"), ["second"])
    }

    @MainActor
    func testHomeShowsTeamIdentityButDoesNotInventOpponentsForChannelsOrEvents() {
        func cricketEvent(title: String, date: Int64?) -> AnalyticalDataEngine.EventReference {
            .init(id: title, title: title, category: "cricket", date: date, poster: nil, popular: nil, teams: nil)
        }
        XCTAssertTrue(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "India vs Australia", date: nil)))
        XCTAssertTrue(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "Trinbago Knight Riders vs Barbados Royals", date: nil)))
        XCTAssertFalse(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "Willow Cricket", date: nil)))
        XCTAssertFalse(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "CPL Final", date: nil)))
    }

    func testHomeIdentityAndAppearanceRenderAtNarrowAndIPadWidths() throws {
        let schedule = HomeSportsDiscovery(events: [
            event("football", sport: "football", offset: -60, home: "Home Test Club", away: "Visiting Test Club"),
            event("basketball", sport: "basketball", offset: 300),
            event("baseball", sport: "baseball", offset: 600),
            event("cricket", sport: "cricket", offset: 900),
            event("tennis", sport: "tennis", offset: 900),
            event("hockey", sport: "hockey", offset: 900),
            event("american-football", sport: "american-football", offset: 900),
            event("motorsports", sport: "motorsports", offset: 900),
            event("fight", sport: "fight", offset: 900)
        ], now: now)
        let item = try XCTUnwrap(schedule.items.first)
        for (label, width, scheme, type) in [
            ("ipad-landscape-light", 1180.0, ColorScheme.light, DynamicTypeSize.large),
            ("ipad-landscape-dark", 1180.0, ColorScheme.dark, DynamicTypeSize.large),
            ("ipad-light", 820.0, ColorScheme.light, DynamicTypeSize.large),
            ("ipad-dark", 820.0, ColorScheme.dark, DynamicTypeSize.large),
            ("ipad-light-large-type", 820.0, ColorScheme.light, DynamicTypeSize.accessibility2),
            ("narrow-light-large-type", 375.0, ColorScheme.light, DynamicTypeSize.accessibility2)
        ] {
            let content = VStack(alignment: .leading, spacing: 16) {
                Text("Home").font(FottyTheme.typeScreenTitle).foregroundStyle(FottyTheme.textPrimary)
                SportActivityGrid(discovery: schedule, selectedSport: .constant("football"), isPad: width > 600)
                Text("Now & next").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                HomeDiscoveryRow(item: item, now: now, isSaved: false, onOpen: {}, onSave: {})
                    .environment(LiveScoreService.shared)
            }
            .padding(16)
            .frame(width: width)
            .background(FottyTheme.background)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, type)
            .environment(\.horizontalSizeClass, width > 600 ? .regular : .compact)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, label)
            XCTAssertEqual(image.size.width, width, accuracy: 1, label)
            XCTAssertLessThan(image.size.height, 3000, label)
            let attachment = XCTAttachment(image: image)
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testBrandedPressFeedbackHasDistinctStatesWithoutChangingRenderedBounds() throws {
        for scheme in [ColorScheme.light, .dark] {
            func render(pressed: Bool, enabled: Bool) throws -> UIImage {
                let content = Label("Watch", systemImage: "play.fill")
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent, in: RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
                    .modifier(FottyPressFeedback(isPressed: pressed))
                    .environment(\.isEnabled, enabled)
                    .padding(8)
                    .background(FottyTheme.surface)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                return try XCTUnwrap(renderer.uiImage)
            }
            let resting = try render(pressed: false, enabled: true)
            let pressed = try render(pressed: true, enabled: true)
            let disabled = try render(pressed: false, enabled: false)
            let disabledPressed = try render(pressed: true, enabled: false)
            XCTAssertEqual(resting.size, pressed.size, "Feedback must not resize the rendered label")
            XCTAssertGreaterThanOrEqual(resting.size.height - 16, 44)
            // Compare normalized pixels, not PNG compression/metadata. The
            // encoded byte stream can differ while the visible control does not.
            let restingPixels = try FottyVisualPixelComparison.Pixels(image: resting)
            let disabledPixels = try FottyVisualPixelComparison.Pixels(image: disabled)
            XCTAssertFalse(try FottyVisualPixelComparison.compare(restingPixels,
                .init(image: pressed)).matches)
            XCTAssertFalse(try FottyVisualPixelComparison.compare(restingPixels,
                disabledPixels).matches)
            let disabledComparison = try FottyVisualPixelComparison.compare(disabledPixels,
                .init(image: disabledPressed))
            XCTAssertTrue(disabledComparison.matches,
                          "Disabled controls never look pressed: \(disabledComparison.description)")
            for (name, image) in [("resting", resting), ("pressed", pressed), ("disabled", disabled)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "control-\(scheme)-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testSettingsPressSurfaceDiffersFromItsGroupInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let group = UIColor(FottyTheme.surface).resolvedColor(with: traits)
            let pressed = UIColor(FottyTheme.surfaceSubtle).resolvedColor(with: traits)
            XCTAssertNotEqual(group, pressed, "A pressed Settings row must differ from its enclosing group")
        }
    }

    func testNativeTabBarIncludesSportsTVAlongsideHomeAndMatchday() {
        XCTAssertEqual(MainTabView.Tab.allCases.map(\.displayName), ["Home", "TV", "Matchday", "FPL", "Settings"])
    }

    func testIncreasedContrastImprovesSecondaryInkAndBorderVisibility() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let standard = UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.accessibilityContrast = .normal
            }
            let increased = standard.modifyingTraits { $0.accessibilityContrast = .high }
            for token in [FottyTheme.textSecondary, FottyTheme.textTertiary, FottyTheme.border, FottyTheme.borderStrong] {
                let normal = UIColor(token).resolvedColor(with: standard)
                let high = UIColor(token).resolvedColor(with: increased)
                XCTAssertNotEqual(normal, high, "Custom reading/chrome tokens must respond to Increase Contrast")
            }
        }
    }

    func testBroadcastSourceRowsRenderSelectedRetryAndCSStatesAtNarrowAndWideWidths() throws {
        let session = StreamSession(
            matchID: "ui-source-sample",
            title: "Live cricket broadcast with a long option description",
            playableURL: try XCTUnwrap(URL(string: "https://example.invalid/sample.m3u8")),
            streamType: .hls,
            providerName: "CS2"
        )
        for width in [320.0, 820.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let content = VStack(spacing: 12) {
                    SessionRow(session: session, displayNumber: 2, isActive: true, isFailed: false, action: {})
                    SessionRow(session: session, displayNumber: 2, isActive: true, isFailed: true, action: {})
                    SessionRow(session: session, displayNumber: 2, isActive: false, isFailed: false, action: {})
                }
                .padding(12)
                .frame(width: width)
                .background(FottyTheme.background)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, size)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, width, accuracy: 0.5)
                XCTAssertGreaterThan(image.size.height, 3 * 44)
                let attachment = XCTAttachment(image: image)
                attachment.name = "source-rows-\(Int(width))-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testDedicatedAppearanceChoicesRenderAtPhoneAndIPadWidths() throws {
        for (label, width, scheme, appearance) in [
            ("appearance-ipad-light", 820.0, ColorScheme.light, FottyAppearance.light),
            ("appearance-phone-dark", 375.0, ColorScheme.dark, FottyAppearance.dark)
        ] {
            let content = SettingsAppearanceOptions(appearance: .constant(appearance.rawValue))
                .padding(.vertical, 16)
                .frame(width: width, height: 720, alignment: .top)
                .background(FottyTheme.background)
                .environment(\.colorScheme, scheme)
            // Render the actual choice component; offscreen UIKit ScrollViews
            // can be empty on Catalyst. Reject background-only false positives.
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, label)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16, "\(label) must contain rendered choices, not just a background")
            let attachment = XCTAttachment(image: image)
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testAppearancePaletteContrastInBothModes() {
        func rgba(_ color: Color, _ style: UIUserInterfaceStyle) -> [Double] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a))
            return [Double(r), Double(g), Double(b), Double(a)]
        }
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        func contrast(_ first: [Double], _ second: [Double]) -> Double {
            let a = luminance(first), b = luminance(second)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        for style in [UIUserInterfaceStyle.dark, .light] {
            let base = rgba(FottyTheme.background, style)
            for color in [FottyTheme.textPrimary, FottyTheme.textSecondary, FottyTheme.accentText] {
                XCTAssertGreaterThanOrEqual(contrast(rgba(color, style), base), 7, "Home reading contrast, \(style.rawValue)")
            }
            for surface in [FottyTheme.background, FottyTheme.surface, FottyTheme.surfaceSubtle, FottyTheme.surfaceElevated] {
                for color in [FottyTheme.textPrimary, FottyTheme.textSecondary, FottyTheme.textTertiary, FottyTheme.accentText, FottyTheme.success, FottyTheme.error] {
                    XCTAssertGreaterThanOrEqual(contrast(rgba(color, style), rgba(surface, style)), 4.5, "Body/status text, \(style.rawValue)")
                }
            }
            XCTAssertGreaterThanOrEqual(contrast(rgba(FottyTheme.accent, style), rgba(FottyTheme.textOnAccent, style)), 7)
            XCTAssertGreaterThanOrEqual(contrast(rgba(FottyTheme.error, style), rgba(FottyTheme.textOnError, style)), 4.5)
            for difficulty in 0...5 {
                XCTAssertGreaterThanOrEqual(contrast(rgba(FottyFixtureDifficulty.foreground(difficulty), style), rgba(FottyFixtureDifficulty.background(difficulty), style)), 4.5)
            }
            for selected in [true, false] {
                let surface = rgba(SportActivityGrid.tileBackground(selected: selected), style)
                let painted = (0..<3).map { surface[$0] * surface[3] + base[$0] * (1 - surface[3]) }
                XCTAssertGreaterThanOrEqual(contrast(rgba(SportActivityGrid.tileForeground, style), painted), 7, "Selected: \(selected), style: \(style.rawValue)")
            }
        }
    }
}

// MARK: - Empty football schedule windows and real source failures

@MainActor
final class FootballScheduleEmptyWindowTests: XCTestCase {
    private let window = Date(timeIntervalSince1970: 2_000_000_000)...Date(timeIntervalSince1970: 2_000_086_400)

    func testVerifiedEmptyGlobalWindowIsCachedWithoutCompetitionFanout() async throws {
        let fixture = FootballScheduleNetworkFixture(replies: [.empty])
        defer { fixture.finish() }
        let service = fixture.service()

        let first = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)
        let cached = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)

        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(cached.isEmpty)
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 1, "A valid empty result is not a reason to fan out over six competitions.")
        // URL.path omits a final separator; URLComponents retains the actual
        // request path sent to the Worker.
        XCTAssertEqual(requests.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path },
                       "/api/football/matches/")
        let items = requests.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        XCTAssertEqual(items.map(\.name), ["dateFrom", "dateTo"], "Canonical query order keeps identical windows in the same cache entry.")
        XCTAssertFalse(items.contains { $0.name == "competition" })
    }

    func testKeylessProxyFailurePreservesHTTPErrorDuringCooldown() async {
        let fixture = FootballScheduleNetworkFixture(replies: [.http(status: 502, body: Data())])
        defer { fixture.finish() }
        let service = fixture.service()

        for _ in 0..<2 {
            do {
                _ = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)
                XCTFail("An upstream failure must not masquerade as a successful empty schedule.")
            } catch {
                assertHTTPError(error, status: 502)
            }
        }
        XCTAssertEqual(fixture.requests.count, 1, "The second lookup must reuse the real failure during proxy cooldown.")
    }

    func testMalformedSuccessfulProxyResponseRemainsADecodingFailure() async {
        let fixture = FootballScheduleNetworkFixture(replies: [.http(status: 200, body: Data("{\"matches\":null}".utf8))])
        defer { fixture.finish() }
        let service = fixture.service()

        for _ in 0..<2 {
            do {
                _ = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)
                XCTFail("HTTP 200 does not validate a malformed matches payload.")
            } catch {
                XCTAssertTrue(error is DecodingError, "Preserve the decode failure, not a missing-key error: \(error)")
            }
        }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testCancelledProxyRequestDoesNotSuppressTheNextAttempt() async throws {
        let fixture = FootballScheduleNetworkFixture(replies: [.failure(.cancelled), .empty])
        defer { fixture.finish() }
        let service = fixture.service()

        do {
            _ = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)
            XCTFail("Transport cancellation must propagate.")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }

        let recovered = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)
        XCTAssertTrue(recovered.isEmpty)
        XCTAssertEqual(fixture.requests.count, 2, "Cancellation is not an upstream failure and must not poison the proxy cooldown.")
    }

    func testConfiguredDirectFallbackPreservesAuthenticationAndCachesRecovery() async throws {
        let fixture = FootballScheduleNetworkFixture(replies: [.http(status: 502, body: Data()), .empty])
        defer { fixture.finish() }
        let service = fixture.service(apiKey: "football-schedule-test-key")

        let recovered = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)
        let cached = try await service.fetchGlobalMatches(from: window.lowerBound, to: window.upperBound)

        XCTAssertTrue(recovered.isEmpty)
        XCTAssertTrue(cached.isEmpty)
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 2, "One failed proxy and one successful direct request; neither empty response needs a league sweep.")
        XCTAssertEqual(requests.first?.url?.host, fixture.host)
        let direct = requests.last
        XCTAssertEqual(direct?.url?.host, "api.football-data.org")
        XCTAssertEqual(direct?.url?.path, "/v4/matches")
        XCTAssertEqual(direct?.value(forHTTPHeaderField: "X-Auth-Token"), "football-schedule-test-key")
        let items = direct?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        XCTAssertEqual(items.map(\.name), ["dateFrom", "dateTo"])
    }

    func testRepositoryCachesVerifiedEmptyScheduleWithoutPremiumRequests() async throws {
        let loader = FootballScheduleLoaderProbe(replies: [.fixtures([])])
        let provider = FootballSchedulePremiumProbe()
        let repository = FootballRepository(scheduleLoader: { try loader.load($0) }, primaryProvider: provider)

        let first = try await repository.getScheduleFixtures(dateRange: window)
        let cached = try await repository.getScheduleFixtures(dateRange: window)

        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(loader.calls, 1)
        XCTAssertEqual(provider.calls, 0, "Automatic schedule lookups cannot spend API-Football quota to fill an empty window.")
    }

    func testRepositoryTreatsADiscoveryFilteredEmptyScheduleAsValid() async throws {
        let unsupported = unsupportedCompetitionFixture()
        XCTAssertFalse(Config.Arena.discoveryIncludes(competition: unsupported.fixture.competition))
        let loader = FootballScheduleLoaderProbe(replies: [.fixtures([unsupported])])
        let provider = FootballSchedulePremiumProbe()
        let repository = FootballRepository(scheduleLoader: { try loader.load($0) }, primaryProvider: provider)

        let filtered = try await repository.getScheduleFixtures(dateRange: window)
        let cached = try await repository.getScheduleFixtures(dateRange: window)

        XCTAssertTrue(filtered.isEmpty)
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(loader.calls, 1, "The validated source succeeded even though discovery excludes all its rows.")
        XCTAssertEqual(provider.calls, 0)
    }

    func testRepositorySourceFailurePropagatesAndDoesNotCacheFalseEmpty() async throws {
        let loader = FootballScheduleLoaderProbe(replies: [.httpFailure(502), .httpFailure(502), .fixtures([])])
        let provider = FootballSchedulePremiumProbe()
        let repository = FootballRepository(scheduleLoader: { try loader.load($0) }, primaryProvider: provider)

        for _ in 0..<2 {
            do {
                _ = try await repository.getScheduleFixtures(dateRange: window)
                XCTFail("A failed source is not a valid empty fixture window.")
            } catch {
                assertHTTPError(error, status: 502)
            }
        }
        XCTAssertEqual(loader.calls, 2, "A failure must leave the successful-list cache unpopulated.")
        let recovered = try await repository.getScheduleFixtures(dateRange: window)
        let cached = try await repository.getScheduleFixtures(dateRange: window)
        XCTAssertTrue(recovered.isEmpty)
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(loader.calls, 3)
        XCTAssertEqual(provider.calls, 0, "Source failures must propagate without silently sweeping premium leagues.")
    }

    private func assertHTTPError(_ error: Error, status: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let footballError = error as? FootballError, case .httpError(let actual) = footballError else {
            XCTFail("Expected HTTP \(status), got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, status, file: file, line: line)
    }

    private func unsupportedCompetitionFixture() -> MatchHubData {
        let competition = FottyCompetition(id: "999999", name: "Fixture Test Regional Cup", country: nil, emblemURL: nil)
        return MatchHubData(
            fixture: FottyFixture(id: "empty-window-filter-test", utcDate: window.lowerBound, status: .scheduled,
                                  competition: competition, venue: nil, matchday: nil),
            homeTeam: FottyTeam(id: "test-home", name: "Fixture Home", shortName: nil, crestURL: nil, color: nil),
            awayTeam: FottyTeam(id: "test-away", name: "Fixture Away", shortName: nil, crestURL: nil, color: nil),
            score: FottyScore(home: 0, away: 0, aggregateHome: nil, aggregateAway: nil, periodScores: nil),
            events: [], homeLineup: nil, awayLineup: nil, statistics: [], teamNews: [],
            lastUpdated: window.lowerBound, dataQuality: .official
        )
    }
}

/// This session intercepts *all* its requests, including direct fallback. No DNS
/// lookup or public endpoint is used. Unique hosts also isolate concurrent tests.
private final class FootballScheduleNetworkFixture {
    let host = "\(UUID().uuidString.lowercased()).football-schedule.test"
    private let session: URLSession

    init(replies: [FootballScheduleStubRegistry.Reply]) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FootballScheduleStubProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [FootballScheduleStubRegistry.routeHeader: host]
        session = URLSession(configuration: configuration)
        FootballScheduleStubRegistry.shared.register(host: host, replies: replies)
    }

    var requests: [URLRequest] { FootballScheduleStubRegistry.shared.requests(host: host) }

    func service(apiKey: String = "") -> FootballService {
        FootballService(session: session, apiKey: apiKey, proxyBaseURL: URL(string: "https://\(host)"), prefersProxy: true)
    }

    func finish() {
        session.invalidateAndCancel()
        FootballScheduleStubRegistry.shared.remove(host: host)
    }
}

/// All mutable registry state is protected by the lock, including registration,
/// response consumption, and observations. No unsynchronized static closures.
private final class FootballScheduleStubRegistry: @unchecked Sendable {
    static let shared = FootballScheduleStubRegistry()
    static let routeHeader = "X-Fotty-Schedule-Test-Route"

    enum Reply: Sendable {
        case http(status: Int, body: Data)
        case failure(URLError.Code)
        static var empty: Reply { .http(status: 200, body: Data("{\"matches\":[]}".utf8)) }
    }

    private struct Entry {
        var replies: [Reply]
        var requests: [URLRequest] = []
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func register(host: String, replies: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        entries[host] = Entry(replies: replies)
    }

    func remove(host: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: host)
    }

    func requests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return entries[host]?.requests ?? []
    }

    func next(for request: URLRequest) -> Reply {
        lock.lock(); defer { lock.unlock() }
        let host = request.value(forHTTPHeaderField: Self.routeHeader) ?? request.url?.host ?? ""
        guard var entry = entries[host] else { return .failure(.unsupportedURL) }
        entry.requests.append(request)
        let reply = entry.replies.isEmpty ? .failure(.resourceUnavailable) : entry.replies.removeFirst()
        entries[host] = entry
        return reply
    }
}

private final class FootballScheduleStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch FootballScheduleStubRegistry.shared.next(for: request) {
        case .http(let status, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": "application/json"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

private final class FootballScheduleLoaderProbe: @unchecked Sendable {
    enum Reply {
        case fixtures([MatchHubData])
        case httpFailure(Int)
    }
    private let lock = NSLock()
    private var replies: [Reply]
    private var count = 0

    init(replies: [Reply]) { self.replies = replies }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    func load(_ range: ClosedRange<Date>) throws -> [MatchHubData] {
        lock.lock()
        count += 1
        let reply = replies.isEmpty ? .httpFailure(599) : replies.removeFirst()
        lock.unlock()
        switch reply {
        case .fixtures(let fixtures): return fixtures
        case .httpFailure(let status): throw FootballError.httpError(status)
        }
    }
}

private final class FootballSchedulePremiumProbe: FootballProvider, @unchecked Sendable {
    let name = "Schedule tests: premium must not be used"
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    private func record() { lock.lock(); count += 1; lock.unlock() }

    func fetchFixtures(date: Date) async throws -> [FottyFixture] { record(); return [] }
    func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData { record(); throw FootballProviderError.unknown }
    func fetchLiveScores() async throws -> [MatchHubData] { record(); return [] }
    func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData] { record(); return [] }
    func fetchStandings(competitionId: String) async throws -> [FottyCompetition] { record(); return [] }
    func fetchTeamForm(teamId: String) async throws -> [String] { record(); return [] }
    func checkHealth() async -> Bool { record(); return true }
}
