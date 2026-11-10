import SwiftData
import XCTest
@testable import Fotty

final class SportsPersonalizationTests: XCTestCase {
    func testWholeSportStorageIsAdditiveBoundedAndOffForExistingInstalls() throws {
        let suite = "Fotty.WholeSportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(12345, forKey: "fotty.user.fplManagerId")
        XCTAssertEqual(Set(SportsInterestPreferences.orderedIDs), SportsHandoffIdentity.supportedSports.union(["darts"]))
        XCTAssertEqual(SportsInterestPreferences.supportedIDs.count, 13)
        XCTAssertEqual(SportsHandoffIdentity.supportedSports.count, 12)
        XCTAssertTrue(try SportsInterestPreferences.validatedIDs(in: defaults).isEmpty)
        XCTAssertNil(defaults.object(forKey: SportsInterestPreferences.storageKey))
        for sport in SportsInterestPreferences.orderedIDs {
            try SportsInterestPreferences.setEnabled(sport, enabled: true, in: defaults)
        }
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: defaults), SportsInterestPreferences.supportedIDs)
        XCTAssertEqual(defaults.integer(forKey: "fotty.user.fplManagerId"), 12345)
        XCTAssertFalse(defaults.bool(forKey: "fotty.sports-sync.v1.enabled"))
        XCTAssertThrowsError(try SportsInterestPreferences.setEnabled("unreviewed", enabled: true, in: defaults))
    }

    func testLocalDartsInterestRoundTripsAndCanBeRemovedWithoutChangingOtherSports() throws {
        let suite = "Fotty.WholeSportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try SportsInterestPreferences.setEnabled("cricket", enabled: true, in: defaults)
        try SportsInterestPreferences.setEnabled("darts", enabled: true, in: defaults)
        let encoded = try XCTUnwrap(defaults.string(forKey: SportsInterestPreferences.storageKey))
        XCTAssertEqual(SportsInterestPreferences.decodedIDs(from: encoded), ["cricket", "darts"])
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: defaults), ["cricket", "darts"])
        try SportsInterestPreferences.setEnabled("darts", enabled: false, in: defaults)
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: defaults), ["cricket"])
    }

    func testWholeSportWriteFailureAndMalformedStorageCannotErasePreviousChoices() throws {
        let suite = "Fotty.WholeSportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try SportsInterestPreferences.setEnabled("cricket", enabled: true, in: defaults)
        let accepted = defaults.string(forKey: SportsInterestPreferences.storageKey)
        XCTAssertThrowsError(try SportsInterestPreferences.setEnabled("tennis", enabled: true, in: defaults,
            writer: { _, _, _ in throw CocoaError(.fileWriteUnknown) }))
        XCTAssertThrowsError(try SportsInterestPreferences.setEnabled("tennis", enabled: true, in: defaults,
            writer: { _, _, _ in }))
        XCTAssertEqual(defaults.string(forKey: SportsInterestPreferences.storageKey), accepted)
        for invalid in ["not-json", "[\"unreviewed\"]", "[\"cricket\",\"cricket\"]"] {
            defaults.set(invalid, forKey: SportsInterestPreferences.storageKey)
            XCTAssertThrowsError(try SportsInterestPreferences.setEnabled("tennis", enabled: true, in: defaults))
            XCTAssertEqual(defaults.string(forKey: SportsInterestPreferences.storageKey), invalid)
        }
    }

    @MainActor
    func testEveryReviewedWholeSportMatchesOnlyItsExactCategoryAndKeepsExistingFollows() throws {
        let team = FollowedTeamItem(key: "football|liverpool", teamName: "Liverpool", sportCategory: "football")
        let league = FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        for sport in SportsInterestPreferences.orderedIDs {
            let selected = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league], sports: [sport])
            XCTAssertTrue(selected.teamKeys.contains("football|liverpool"))
            XCTAssertTrue(selected.leagueIDs.contains("cpl"))
            for category in SportsInterestPreferences.orderedIDs {
                let fixture = event("unmarked-\(category)", "Example A vs Example B", category)
                XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selected), sport == category)
            }
            XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(
                event: event("conflict-\(sport)", "Example A vs Example B", sport, conflict: true), selection: selected))
        }
        let channel = event("willow", "Willow Cricket", "cricket", date: nil)
        XCTAssertTrue(channel.isBroadcastChannel)
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: channel,
            selection: SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [], sports: ["cricket"])))
    }

    @MainActor
    func testSameCountWholeSportEditsInvalidatePreparedHomeIdentityWithoutChangingOldSelection() {
        let cricket = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [], sports: ["cricket"])
        let tennis = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [], sports: ["tennis"])
        XCTAssertNotEqual(homeFactsKey(cricket), homeFactsKey(tennis))
        XCTAssertEqual(cricket.sportIDs, ["cricket"])
        XCTAssertEqual(SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: []).sportIDs, [])
        XCTAssertTrue(HomeInterestPreferences.isActive(enabled: true, selectedInterestCount: cricket.sportIDs.count))
        XCTAssertEqual(SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [], sports: ["unknown"]).sportIDs, [])
    }

    @MainActor
    func testCooperativeProjectionCheckpointRejectsChangedRevisionAndCancellation() async {
        var revision = 1
        let superseded = Task { @MainActor in
            await HomeProjectionWorkPolicy.checkpoint { revision == 1 }
        }
        revision = 2
        let supersededResult = await superseded.value
        XCTAssertFalse(supersededResult)

        let cancelled = Task { @MainActor in
            await HomeProjectionWorkPolicy.checkpoint { true }
        }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertFalse(cancelledResult)

        let currentResult = await HomeProjectionWorkPolicy.checkpoint { revision == 2 }
        XCTAssertTrue(currentResult)
    }

    func testHomeInterestPreferenceDefaultsToBroadCatalogAndFailsOpenWithoutSelections() {
        XCTAssertTrue(HomeInterestPreferences.shouldInclude(
            isFollowed: false,
            enabled: false,
            selectedInterestCount: 3
        ))
        XCTAssertTrue(HomeInterestPreferences.shouldInclude(
            isFollowed: false,
            enabled: true,
            selectedInterestCount: 0
        ))
        XCTAssertFalse(HomeInterestPreferences.shouldInclude(
            isFollowed: false,
            enabled: true,
            selectedInterestCount: 3
        ))
        XCTAssertTrue(HomeInterestPreferences.shouldInclude(
            isFollowed: true,
            enabled: true,
            selectedInterestCount: 3
        ))
    }

    func testReviewedAliasesShareKeysButDifferentSquadsNeverDo() {
        XCTAssertEqual(TeamFollowKey.make(name: "Manchester United", category: "football"),
                       TeamFollowKey.make(name: "Man Utd", category: "soccer"))
        XCTAssertEqual(TeamFollowKey.make(name: "Barbados Royals", category: "cricket"),
                       TeamFollowKey.make(name: "Barbados Tridents", category: "cricket"))
        XCTAssertEqual(TeamFollowKey.make(name: "LA Lakers", category: "basketball"),
                       TeamFollowKey.make(name: "Los Angeles Lakers", category: "basketball"))
        for name in ["Manchester United Women", "Manchester United U21", "Manchester United II", "Manchester United B", "Manchester United Reserves"] {
            XCTAssertNotEqual(TeamFollowKey.make(name: name, category: "football"),
                              TeamFollowKey.make(name: "Manchester United", category: "football"), name)
        }
        XCTAssertNotEqual(TeamFollowKey.make(name: "Manchester City", category: "football"),
                          TeamFollowKey.make(name: "Manchester United", category: "football"))
        XCTAssertNotEqual(TeamFollowKey.make(name: "Chelsea", category: "volleyball"),
                          TeamFollowKey.make(name: "Chelsea", category: "football"))
        XCTAssertNil(SportsTeamIdentity.known(name: "Trinbago Knight Riders Women", category: "cricket"))
        XCTAssertNil(SportsTeamIdentity.known(name: "Trinbago Knight Riders vs Barbados Royals", category: "cricket"))
    }

    @MainActor
    func testSearchCarriesCanonicalMultisportNamesAndBadgesWithoutNetwork() throws {
        for (query, name, sport) in [("Lakers", "Los Angeles Lakers", "basketball"),
                                    ("Dodgers", "Los Angeles Dodgers", "baseball"),
                                    ("Barbados Royals", "Barbados Tridents", "cricket"),
                                    ("Man Utd", "Manchester United", "football")] {
            let result = try XCTUnwrap(TeamBrandService.followableCatalogSearch(query: query, badges: [:]).first)
            XCTAssertEqual(result.displayName, name)
            XCTAssertEqual(result.sportCategory, sport)
            XCTAssertEqual(result.id, TeamFollowKey.make(name: name, category: sport))
            if sport != "football" { XCTAssertNotNil(result.badgeURL) }
        }
    }

    @MainActor
    func testProviderMetadataNotQueryOrSharedBadgeDefinesFollowIdentity() throws {
        let data = Data(#"{"teams":[{"strTeam":"Villarreal","strSport":"Soccer","strBadge":"https://example.com/shared.png"},{"strTeam":"Villarreal II","strSport":"Soccer","strBadge":"https://example.com/shared.png"},{"strTeam":"Villarreal Women","strSport":"Soccer","strBadge":"https://example.com/shared.png"},{"strTeam":"Los Angeles Dodgers","strSport":"Baseball"},{"strTeam":"Unknown missing sport","strBadge":"https://example.com/shared.png"}]}"#.utf8)
        let teams = try TeamBrandService.followableTeams(from: data)
        XCTAssertEqual(teams.count, 4)
        XCTAssertEqual(Set(teams.map(\.id)).count, 4)
        XCTAssertEqual(teams.first { $0.displayName == "Los Angeles Dodgers" }?.sportCategory, "baseball")
        XCTAssertTrue(teams.contains { $0.displayName == "Villarreal II" })
        XCTAssertTrue(teams.contains { $0.displayName == "Villarreal Women" })
    }

    @MainActor
    func testLegacyWrongSportAndAliasFollowsMatchCorrectFixturesBeforeMigration() {
        let oldLakers = FollowedTeamItem(key: "football|los-angeles-lakers", teamName: "Los Angeles Lakers", sportCategory: "football")
        let oldUnited = FollowedTeamItem(key: "football|man-utd", teamName: "Man Utd", sportCategory: "football")
        let oldCPL = FollowedTeamItem(key: "football|barbados-royals", teamName: "Barbados Royals", sportCategory: "football")
        let keys = SportsPersonalizationPolicy.followedTeamKeys([oldLakers, oldUnited, oldCPL])
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: event("nba-lakers", "LA Lakers vs Boston Celtics", "basketball"), teamKeys: keys, leagueItems: []))
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: event("united", "Manchester United vs Chelsea", "football"), teamKeys: keys, leagueItems: []))
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: event("cpl-barbados", "Barbados Tridents vs Trinbago Knight Riders", "cricket"), teamKeys: keys, leagueItems: []))
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: event("reserve", "Manchester United U21 vs Chelsea U21", "football"), teamKeys: keys, leagueItems: []))
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: event("wrong-sport", "Los Angeles Lakers vs Boston Celtics", "football"), teamKeys: keys, leagueItems: []))
    }

    @MainActor
    func testPreparedSelectionMatchesLegacyPoliciesAcrossSportsAndRejectedIdentities() {
        let teams = [
            FollowedTeamItem(key: "legacy-united", teamName: "Man Utd", sportCategory: "football"),
            FollowedTeamItem(key: "legacy-lakers", teamName: "Los Angeles Lakers", sportCategory: "football"),
            FollowedTeamItem(key: "legacy-cpl", teamName: "Barbados Royals", sportCategory: "football")
        ]
        let leagues = [
            FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket"),
            FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball"),
            FollowedLeagueItem(id: "unknown", leagueName: "Unknown", sportCategory: "baseball")
        ]
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: teams, leagues: leagues)
        let keys = SportsPersonalizationPolicy.followedTeamKeys(teams)
        let cases: [(AnalyticalDataEngine.EventReference, Bool)] = [
            (event("united", "Manchester United vs Chelsea", "football"), true),
            (event("nba-lakers", "LA Lakers vs Boston Celtics", "basketball"), true),
            (event("cpl-barbados", "Barbados Tridents vs Trinbago Knight Riders", "cricket"), true),
            (event("nba-unknown", "Example vs Another", "basketball"), true),
            (event("reserve", "Manchester United U21 vs Chelsea U21", "football"), false),
            (event("women", "Manchester United Women vs Chelsea Women", "football"), false),
            (event("wrong-sport", "Los Angeles Lakers vs Boston Celtics", "football"), false),
            (event("nba-conflict", "LA Lakers vs Boston Celtics", "basketball", conflict: true), false),
            (event("willow", "Willow Cricket", "cricket", date: nil), false),
            (event("cpl-news", "CPL news and interviews", "cricket"), false),
            (event("opaque", "Example vs Another", "baseball"), false)
        ]
        XCTAssertEqual(selection.teamKeys, keys)
        XCTAssertEqual(selection.leagueIDs, ["cpl", "nba"])
        for (fixture, expected) in cases {
            let legacy = SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: keys, leagueItems: leagues)
            XCTAssertEqual(legacy, expected, fixture.id)
            XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection), legacy, fixture.id)
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection),
                           SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: leagues), fixture.id)
        }
    }

    @MainActor
    func testPreparedSelectionHonorsOfficialCompetitionOverProviderMarkers() {
        let fixture = event("mls-preview", "Chelsea vs Arsenal", "football")
        let official = FootballMatch(
            id: 101, apiFootballFixtureId: nil, utcDate: "2026-09-30T19:00:00Z", status: .scheduled,
            matchday: nil, stage: nil, group: nil,
            homeTeam: .init(id: 61, name: "Chelsea", shortName: "Chelsea", tla: "CHE", crest: nil),
            awayTeam: .init(id: 57, name: "Arsenal", shortName: "Arsenal", tla: "ARS", crest: nil),
            score: .init(winner: nil, duration: nil, fullTime: nil, halfTime: nil),
            competition: .init(id: 2021, name: "Premier League", code: "PL", emblem: nil, country: "England"),
            referees: nil, events: nil
        )
        let mls = FollowedLeagueItem(id: "mls", leagueName: "MLS", sportCategory: "football")
        let premier = FollowedLeagueItem(id: "premier-league", leagueName: "Premier League", sportCategory: "football")
        for (leagues, expected) in [([mls], false), ([premier], true)] {
            let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: leagues)
            XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection, officialMatch: official), expected)
            XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection, officialMatch: official),
                           SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: [], leagueItems: leagues, officialMatch: official))
        }
    }

    @MainActor
    func testFootballLeagueFollowsRejectBareSharedClubRosterInference() {
        let premier = FollowedLeagueItem(id: "premier-league", leagueName: "Premier League", sportCategory: "football")
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [premier])
        for (home, away) in [("Aston Villa", "Crystal Palace"), ("Villa", "Palace")] {
            let fixture = leagueFollowPair(home: home, away: away)
            let classification = AnalyticalDataEngine.footballLeagueClassification(for: fixture)
            XCTAssertEqual(classification.tab, .premierLeague, "The catalog-browsing classifier is unchanged")
            XCTAssertEqual(classification.evidence, .rosterInference)
            XCTAssertNil(SportsPersonalizationPolicy.league(for: fixture))
            XCTAssertNil(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: [premier]))
            XCTAssertNil(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection))
            XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: [], leagueItems: [premier]))
            XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection))
        }

        let followedVilla = FollowedTeamItem(key: "villa", teamName: "Aston Villa", sportCategory: "football")
        let teamSelection = SportsPersonalizationPolicy.prepareSelection(teams: [followedVilla], leagues: [])
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: leagueFollowPair(), selection: teamSelection),
                      "Explicit team follows must not depend on competition inference")
    }

    @MainActor
    func testCarabaoInterestIsExplicitAndKeepsLeagueAndClubFollowsIndependent() throws {
        let cup = try XCTUnwrap(SportsPersonalizationPolicy.leagues.first { $0.id == "carabao-cup" })
        XCTAssertEqual(cup.name, "Carabao Cup")
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:carabao-cup:test-liverpool-chelsea", sport: "football",
            competitionID: cup.id, competitionName: cup.name, eventKind: .match, title: "Liverpool vs Chelsea",
            participants: [.init(id: "test-liverpool", name: "Liverpool", role: "home"),
                           .init(id: "test-chelsea", name: "Chelsea", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: Date(), verified: true)
        let fixture = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football", date: 1_800_000_000,
            poster: nil, popular: false, teams: .init(home: .init(name: "Liverpool", badge: nil), away: .init(name: "Chelsea", badge: nil)),
            sources: [], sportsFixture: metadata, competitionID: cup.id)
        let league = FollowedLeagueItem(id: cup.id, leagueName: cup.name, sportCategory: cup.sportCategory)
        let cupSelection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [league])
        let premier = FollowedLeagueItem(id: "premier-league", leagueName: "Premier League", sportCategory: "football")
        let champions = FollowedLeagueItem(id: "champions-league", leagueName: "Champions League", sportCategory: "football")
        let oldSelection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [premier, champions])
        XCTAssertEqual(SportsPersonalizationPolicy.league(for: fixture)?.id, cup.id)
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: cupSelection))
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: oldSelection))
        XCTAssertEqual(oldSelection.leagueIDs, ["premier-league", "champions-league"], "A new option must not broaden existing preferences")
        let team = FollowedTeamItem(key: "football|liverpool", teamName: "Liverpool", sportCategory: "football")
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture,
            selection: SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [])))
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture,
            selection: SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [], sports: ["football"])))
        let barePair = leagueFollowPair(home: "Liverpool", away: "Chelsea")
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: barePair, selection: cupSelection),
                       "Shared clubs alone are never Carabao competition evidence")
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: barePair, selection: oldSelection),
                       "Shared PL clubs alone must still not become PL-follow evidence")
    }

    @MainActor
    func testFootballLeagueFollowsPreserveExplicitAndOfficialSamePairEvidence() {
        let premier = FollowedLeagueItem(id: "premier-league", leagueName: "Premier League", sportCategory: "football")
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [premier])
        let explicit = leagueFollowPair(title: "Premier League · Aston Villa vs Crystal Palace")
        let official = FootballMatch(
            id: 102, apiFootballFixtureId: nil, utcDate: "2027-01-15T08:00:00Z", status: .scheduled,
            matchday: nil, stage: nil, group: nil,
            homeTeam: .init(id: 58, name: "Aston Villa", shortName: "Villa", tla: "AVL", crest: nil),
            awayTeam: .init(id: 354, name: "Crystal Palace", shortName: "Palace", tla: "CRY", crest: nil),
            score: .init(winner: nil, duration: nil, fullTime: nil, halfTime: nil),
            competition: .init(id: 2021, name: "Premier League", code: "PL", emblem: nil, country: "England"),
            referees: nil, events: nil
        )
        XCTAssertEqual(AnalyticalDataEngine.footballLeagueClassification(for: explicit).evidence, .providerMarker)
        let cases: [(AnalyticalDataEngine.EventReference, FootballMatch?)] = [(explicit, nil), (leagueFollowPair(), official)]
        for (fixture, match) in cases {
            XCTAssertEqual(SportsPersonalizationPolicy.league(for: fixture, officialMatch: match)?.id, "premier-league")
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: [premier], officialMatch: match), "Premier League")
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection, officialMatch: match), "Premier League")
            XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: [], leagueItems: [premier], officialMatch: match))
            XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection, officialMatch: match))
        }
    }

    @MainActor
    func testPreparedSelectionInvalidatesSameCountEditsAndDoesNotRetainMutableModels() {
        let team = FollowedTeamItem(key: "old-united", teamName: "Manchester United", sportCategory: "football")
        let competition = FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball")
        let original = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [competition])

        team.teamName = "Liverpool"
        let changedTeam = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [competition])
        XCTAssertNotEqual(original.identity, changedTeam.identity)
        XCTAssertNotEqual(original.teamKeys, changedTeam.teamKeys)
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: event("united", "Manchester United vs Chelsea", "football"), selection: original))
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: event("united", "Manchester United vs Chelsea", "football"), selection: changedTeam))

        competition.id = "cpl"
        competition.leagueName = "Caribbean Premier League"
        competition.sportCategory = "cricket"
        let changedLeague = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [competition])
        XCTAssertNotEqual(changedTeam.identity, changedLeague.identity)
        XCTAssertEqual(original.leagueIDs, ["nba"])
        XCTAssertEqual(changedLeague.leagueIDs, ["cpl"])
        XCTAssertEqual(changedLeague.identity.teams.count, original.identity.teams.count)
        XCTAssertEqual(changedLeague.identity.competitions.count, original.identity.competitions.count)
    }

    @MainActor
    func testSelectionIdentityIsOrderIndependentButIncludesNameAndSportEdits() {
        let first = FollowedTeamItem(key: "first", teamName: "Chelsea", sportCategory: "football")
        let second = FollowedTeamItem(key: "second", teamName: "Barbados Royals", sportCategory: "cricket")
        let nba = FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball")
        let cpl = FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        let identity = SportsPersonalizationPolicy.selectionIdentity(teams: [first, second], leagues: [nba, cpl])
        XCTAssertEqual(identity, SportsPersonalizationPolicy.selectionIdentity(teams: [second, first], leagues: [cpl, nba]))
        first.sportCategory = "volleyball"
        XCTAssertNotEqual(identity, SportsPersonalizationPolicy.selectionIdentity(teams: [first, second], leagues: [nba, cpl]))
        first.sportCategory = "football"
        nba.leagueName = "Unrecognized replacement"
        XCTAssertNotEqual(identity, SportsPersonalizationPolicy.selectionIdentity(teams: [first, second], leagues: [nba, cpl]))
    }

    @MainActor
    func testPreparedSelectionPreservesEveryVerifiedCPLFixtureIncludingKnockouts() {
        let cpl = FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [cpl])
        for fixture in CPLSchedule.fixtures.map({ $0.event() }) {
            XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection), fixture.id)
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection),
                           SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: [cpl]), fixture.id)
        }
    }

    @MainActor
    func testHomeFactsCacheEvaluatesInitialAndInitiallyEmptyCatalogs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [])
        let key = homeFactsKey(selection)
        let items = HomeSportsDiscovery(events: [event("first", "Example vs Another", "football", date: 1_800_003_600)], now: now).items
        var evaluations = 0
        let evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts = { item in
            evaluations += 1
            return self.homeFacts(for: item, selection: selection)
        }

        let initial = HomePersonalizationFactsCache.rebuilding(key: key, items: items, previous: nil, evaluate: evaluate)
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(Set(initial.facts(matching: key).keys), ["first"])

        let empty = HomePersonalizationFactsCache.rebuilding(key: key, items: [], previous: nil, evaluate: evaluate)
        XCTAssertTrue(empty.facts(matching: key).isEmpty)
        XCTAssertEqual(evaluations, 1)
        let loaded = HomePersonalizationFactsCache.rebuilding(key: key, items: items, previous: empty, evaluate: evaluate)
        XCTAssertEqual(evaluations, 2)
        XCTAssertEqual(loaded.facts(matching: key), initial.facts(matching: key))
    }

    @MainActor
    func testHomeFactsCacheReusesFactsWhileClockChangesActualDiscoveryPhase() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = event("clock-cpl", "Trinbago Knight Riders vs Barbados Royals", "cricket", date: 1_800_000_060)
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [
            FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        ])
        let key = homeFactsKey(selection)
        let before = HomeSportsDiscovery(events: [fixture], now: now)
        let after = HomeSportsDiscovery(events: [fixture], now: now.addingTimeInterval(120))
        XCTAssertEqual(try XCTUnwrap(before.items.first).phase, .upcoming)
        XCTAssertEqual(try XCTUnwrap(after.items.first).phase, .listedNow)
        XCTAssertFalse(try XCTUnwrap(after.items.first).hasConfirmedLiveStatus)
        var evaluations = 0
        let evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts = { item in
            evaluations += 1
            return self.homeFacts(for: item, selection: selection)
        }

        let initial = HomePersonalizationFactsCache.rebuilding(key: key, items: before.items, previous: nil, evaluate: evaluate)
        let advanced = HomePersonalizationFactsCache.rebuilding(key: key, items: after.items, previous: initial, evaluate: evaluate)
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(advanced.facts(matching: key), initial.facts(matching: key))
        XCTAssertEqual(advanced.facts(matching: key)[fixture.id]?.isFollowed, true)
        XCTAssertEqual(advanced.facts(matching: key)[fixture.id]?.isCPL, true)
    }

    @MainActor
    func testHomeFactsCacheRejectsPendingRevisionAndRecomputesSameIDReplacement() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [
            FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball")
        ])
        let originalKey = homeFactsKey(selection)
        let replacementKey = homeFactsKey(selection, contentRevision: 2)
        let originalItems = HomeSportsDiscovery(events: [event("nba-same-id", "LA Lakers vs Boston Celtics", "basketball", date: 1_800_003_600)], now: now).items
        let replacementItems = HomeSportsDiscovery(events: [event("nba-same-id", "Trinbago Knight Riders vs Barbados Royals", "cricket", date: 1_800_003_600)], now: now).items
        var evaluations = 0
        let evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts = { item in
            evaluations += 1
            return self.homeFacts(for: item, selection: selection)
        }
        let original = HomePersonalizationFactsCache.rebuilding(key: originalKey, items: originalItems, previous: nil, evaluate: evaluate)
        let originalFact = try XCTUnwrap(original.facts(matching: originalKey)["nba-same-id"])
        XCTAssertEqual(originalFact, HomePersonalizationFacts(isFollowed: true, isMajorLeague: true, isCPL: false))

        // A new owner revision can arrive while the old discovery is still visible.
        // Looking up that pending revision must neither expose nor retag old facts.
        XCTAssertTrue(original.facts(matching: replacementKey).isEmpty)
        XCTAssertEqual(original.key, originalKey)
        XCTAssertEqual(original.facts(matching: originalKey)["nba-same-id"], originalFact)
        XCTAssertEqual(evaluations, 1)

        let replacement = HomePersonalizationFactsCache.rebuilding(key: replacementKey, items: replacementItems, previous: original, evaluate: evaluate)
        XCTAssertEqual(evaluations, 2)
        XCTAssertEqual(replacement.facts(matching: replacementKey)["nba-same-id"],
                       HomePersonalizationFacts(isFollowed: false, isMajorLeague: false, isCPL: true))
        XCTAssertTrue(replacement.facts(matching: originalKey).isEmpty)
    }

    @MainActor
    func testHomeFactsCacheRecomputesWhenOfficialCompetitionScoreRevisionChanges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [
            FollowedLeagueItem(id: "premier-league", leagueName: "Premier League", sportCategory: "football")
        ])
        let items = HomeSportsDiscovery(events: [event("same-fixture", "Chelsea vs Arsenal", "football", date: 1_800_003_600)], now: now).items
        let originalKey = homeFactsKey(selection)
        let changedKey = homeFactsKey(selection, scoreRevisionMilliseconds: 2)
        var official = FootballMatch(
            id: 101, apiFootballFixtureId: nil, utcDate: "2027-01-15T09:00:00Z", status: .scheduled,
            matchday: nil, stage: nil, group: nil,
            homeTeam: .init(id: 61, name: "Chelsea", shortName: "Chelsea", tla: "CHE", crest: nil),
            awayTeam: .init(id: 57, name: "Arsenal", shortName: "Arsenal", tla: "ARS", crest: nil),
            score: .init(winner: nil, duration: nil, fullTime: nil, halfTime: nil),
            competition: .init(id: 2021, name: "Premier League", code: "PL", emblem: nil, country: "England"),
            referees: nil, events: nil
        )
        var evaluations = 0
        let evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts = { item in
            evaluations += 1
            return self.homeFacts(for: item, selection: selection, officialMatch: official)
        }
        let original = HomePersonalizationFactsCache.rebuilding(key: originalKey, items: items, previous: nil, evaluate: evaluate)
        XCTAssertEqual(original.facts(matching: originalKey)["same-fixture"]?.isFollowed, true)
        official = FootballMatch(
            id: official.id, apiFootballFixtureId: nil, utcDate: official.utcDate, status: official.status,
            matchday: nil, stage: nil, group: nil, homeTeam: official.homeTeam, awayTeam: official.awayTeam,
            score: official.score,
            competition: .init(id: 2014, name: "La Liga", code: "PD", emblem: nil, country: "Spain"),
            referees: nil, events: nil
        )
        XCTAssertTrue(original.facts(matching: changedKey).isEmpty)
        let refreshed = HomePersonalizationFactsCache.rebuilding(key: changedKey, items: items, previous: original, evaluate: evaluate)
        XCTAssertEqual(evaluations, 2)
        XCTAssertEqual(refreshed.facts(matching: changedKey)["same-fixture"]?.isFollowed, false)
    }

    @MainActor
    func testHomeFactsCacheInvalidatesEverySameCountSelectionIdentityEdit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let team = FollowedTeamItem(key: "united", teamName: "Manchester United", sportCategory: "football")
        let league = FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball")
        let originalSelection = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league])
        let originalKey = homeFactsKey(originalSelection)
        let items = HomeSportsDiscovery(events: [event("united", "Manchester United vs Chelsea", "football", date: 1_800_003_600)], now: now).items
        var evaluations = 0
        let original = HomePersonalizationFactsCache.rebuilding(key: originalKey, items: items, previous: nil) { item in
            evaluations += 1
            return self.homeFacts(for: item, selection: originalSelection)
        }
        var editedSelections: [SportsPersonalizationPolicy.PreparedSelection] = []
        team.teamName = "Liverpool"
        editedSelections.append(SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league]))
        team.teamName = "Manchester United"
        team.sportCategory = "cricket"
        editedSelections.append(SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league]))
        team.sportCategory = "football"
        league.id = "wnba"
        editedSelections.append(SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league]))
        league.id = "nba"
        league.leagueName = "Unrecognized replacement"
        editedSelections.append(SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league]))
        league.leagueName = "NBA"
        league.sportCategory = "hockey"
        editedSelections.append(SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league]))

        for selection in editedSelections {
            XCTAssertEqual(selection.identity.teams.count, originalSelection.identity.teams.count)
            XCTAssertEqual(selection.identity.competitions.count, originalSelection.identity.competitions.count)
            let changedKey = homeFactsKey(selection)
            XCTAssertNotEqual(changedKey, originalKey)
            XCTAssertTrue(original.facts(matching: changedKey).isEmpty)
            let refreshed = HomePersonalizationFactsCache.rebuilding(key: changedKey, items: items, previous: original) { item in
                evaluations += 1
                return self.homeFacts(for: item, selection: selection)
            }
            XCTAssertEqual(refreshed.facts(matching: changedKey)["united"],
                           items.first.map { homeFacts(for: $0, selection: selection) })
        }
        XCTAssertEqual(evaluations, 1 + editedSelections.count)
        XCTAssertEqual(original.key, originalKey)
        XCTAssertEqual(original.facts(matching: originalKey)["united"]?.isFollowed, true)
    }

    @MainActor
    func testHomeFactsCacheEvaluatesMissingIDsAndPrunesRemovedItemsWithoutReevaluatingReorder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [])
        let key = homeFactsKey(selection)
        let items = HomeSportsDiscovery(events: [
            event("first", "One vs Two", "football", date: 1_800_003_600),
            event("second", "Three vs Four", "football", date: 1_800_007_200)
        ], now: now).items
        var evaluatedIDs: [String] = []
        let evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts = { item in
            evaluatedIDs.append(item.id)
            return self.homeFacts(for: item, selection: selection)
        }
        let initial = HomePersonalizationFactsCache.rebuilding(key: key, items: Array(items.prefix(1)), previous: nil, evaluate: evaluate)
        let expanded = HomePersonalizationFactsCache.rebuilding(key: key, items: items, previous: initial, evaluate: evaluate)
        XCTAssertEqual(evaluatedIDs, ["first", "second"])
        XCTAssertEqual(Set(expanded.facts(matching: key).keys), ["first", "second"])
        let reordered = HomePersonalizationFactsCache.rebuilding(key: key, items: Array(items.reversed()), previous: expanded, evaluate: evaluate)
        XCTAssertEqual(evaluatedIDs, ["first", "second"])
        XCTAssertEqual(reordered.facts(matching: key), expanded.facts(matching: key))
        let removed = HomePersonalizationFactsCache.rebuilding(key: key, items: Array(items.suffix(1)), previous: reordered, evaluate: evaluate)
        XCTAssertEqual(evaluatedIDs, ["first", "second"])
        XCTAssertEqual(Set(removed.facts(matching: key).keys), ["second"])
    }

    func testHomeStillAppliesInterestRestrictionAtPresentationBoundary() throws {
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("selectionIdentity: personalizationSelectionIdentity"))
        XCTAssertTrue(source.contains("guard applyingHomeInterests, isHomeInterestRestrictionActive else { return true }"))
        XCTAssertTrue(source.contains("let personalization = personalizationContext"))
        XCTAssertFalse(source.contains("leagueScoped.filter(isEventFollowed(_:))"))
    }

    @MainActor
    func testMigrationDeduplicatesAliasesPreservesMuteAndRepairsKnownWrongSport() throws {
        let context = try context()
        context.insert(FollowedTeamItem(key: "football|man-utd", teamName: "Man Utd", sportCategory: "football", alertsEnabled: false, createdAt: Date(timeIntervalSince1970: 1)))
        context.insert(FollowedTeamItem(key: "football|manchester-united", teamName: "Manchester United", sportCategory: "football", createdAt: Date(timeIntervalSince1970: 2)))
        context.insert(FollowedTeamItem(key: "football|los-angeles-lakers", teamName: "Los Angeles Lakers", sportCategory: "football"))
        try context.save()
        try SportsPersonalizationStore.migrateTeamIdentities(in: context)
        var saved = try freshTeams(context)
        XCTAssertEqual(saved.count, 2)
        let united = try XCTUnwrap(saved.first { $0.teamName == "Manchester United" })
        XCTAssertEqual(united.alertsEnabled, false)
        XCTAssertEqual(united.createdAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(saved.first { $0.teamName == "Los Angeles Lakers" }?.sportCategory, "basketball")
        try SportsPersonalizationStore.migrateTeamIdentities(in: context)
        saved = try freshTeams(context)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(Set(saved.map(\.key)).count, 2)
    }

    @MainActor
    func testViewContextFollowIsImmediatelyVisibleCanonicalAndPreservesExistingAlertChoice() throws {
        let context = try context()
        let identity = try XCTUnwrap(SportsTeamIdentity.known(name: "Man Utd", category: "football"))
        try SportsPersonalizationStore.setFollowFromView(identity, enabled: true, in: context)
        let first = try XCTUnwrap(context.fetch(FetchDescriptor<FollowedTeamItem>()).first)
        XCTAssertEqual(first.teamName, identity.displayName)
        first.alertsEnabled = false
        try context.save()
        try SportsPersonalizationStore.setFollowFromView(identity, enabled: true, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FollowedTeamItem>()).count, 1)
        XCTAssertEqual(try freshTeams(context).first?.alertsEnabled, false)
        try SportsPersonalizationStore.setFollowFromView(identity, enabled: false, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FollowedTeamItem>()).isEmpty)
        XCTAssertTrue(try freshTeams(context).isEmpty)
    }

    @MainActor
    func testViewContextFollowFailurePreservesSavedAndUnrelatedPendingChanges() throws {
        let context = try context()
        let identity = try XCTUnwrap(SportsTeamIdentity.known(name: "Liverpool", category: "football"))
        try SportsPersonalizationStore.setFollowFromView(identity, enabled: true, in: context)
        let fail: (ModelContext) throws -> Void = { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertThrowsError(try SportsPersonalizationStore.setFollowFromView(identity, enabled: false, in: context, save: fail))
        XCTAssertEqual(try context.fetch(FetchDescriptor<FollowedTeamItem>()).map(\.teamName), [identity.displayName])
        let pending = FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        context.insert(pending)
        XCTAssertThrowsError(try SportsPersonalizationStore.setFollowFromView(identity, enabled: false, in: context, save: fail))
        XCTAssertTrue(context.hasChanges, "Preflight failure must not roll back somebody else's editor")
        XCTAssertTrue(try context.fetch(FetchDescriptor<FollowedLeagueItem>()).contains { $0 === pending })
        XCTAssertEqual(try freshTeams(context).map(\.teamName), [identity.displayName])
    }

    @MainActor
    func testFollowWriteAndRemovalSurviveNewContextAndKeepOtherTeams() throws {
        let context = try context()
        let lakers = try XCTUnwrap(SportsTeamIdentity.known(name: "Lakers", category: "basketball")
                                  ?? SportsTeamIdentity.known(name: "Los Angeles Lakers", category: "basketball"))
        let dodgers = try XCTUnwrap(SportsTeamIdentity.known(name: "Los Angeles Dodgers", category: "baseball"))
        try SportsPersonalizationStore.setFollow(lakers, enabled: true, in: context)
        try SportsPersonalizationStore.setFollow(dodgers, enabled: true, in: context)
        try SportsPersonalizationStore.setFollow(lakers, enabled: true, in: context)
        XCTAssertEqual(try freshTeams(context).count, 2)
        try SportsPersonalizationStore.removeTeams(keys: [lakers.id], in: context)
        XCTAssertEqual(try freshTeams(context).map(\.key), [dodgers.id])
    }

    @MainActor
    func testFailedWritesKeepSavedChoicesAndUnrelatedPendingWork() throws {
        let context = try context()
        let united = try XCTUnwrap(SportsTeamIdentity.known(name: "Man Utd", category: "football"))
        try SportsPersonalizationStore.setFollow(united, enabled: true, in: context)
        let pending = FollowedTeamItem(key: "football|pending", teamName: "Pending team", sportCategory: "football")
        context.insert(pending)
        enum Failure: Error { case disk }
        let fail: (ModelContext) throws -> Void = { _ in throw Failure.disk }
        XCTAssertThrowsError(try SportsPersonalizationStore.removeTeams(keys: [united.id], in: context, save: fail))
        XCTAssertThrowsError(try SportsPersonalizationStore.setAlerts(false, teamKeys: [united.id], in: context, save: fail))
        XCTAssertTrue(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FollowedTeamItem>()).contains { $0 === pending })
        let saved = try freshTeams(context)
        XCTAssertEqual(saved.map(\.key), [united.id])
        XCTAssertEqual(saved.first?.alertsEnabled, true)
    }

    @MainActor
    func testFailedMigrationDoesNotPartlyRenameOrRemoveLegacyRows() throws {
        let context = try context()
        context.insert(FollowedTeamItem(key: "old-united", teamName: "Man Utd", sportCategory: "football"))
        context.insert(FollowedTeamItem(key: "old-lakers", teamName: "Los Angeles Lakers", sportCategory: "football"))
        try context.save()
        enum Failure: Error { case disk }
        XCTAssertThrowsError(try SportsPersonalizationStore.migrateTeamIdentities(in: context, save: { _ in throw Failure.disk }))
        let saved = try freshTeams(context)
        XCTAssertEqual(Set(saved.map(\.key)), ["old-united", "old-lakers"])
        XCTAssertTrue(saved.allSatisfy { $0.sportCategory == "football" })
    }

    @MainActor
    func testLeaguePreferenceHasAnActualMatchdayEffectAndCanBeRemoved() throws {
        let context = try context()
        let cpl = try XCTUnwrap(SportsPersonalizationPolicy.leagues.first { $0.id == "cpl" })
        let fixture = CPLSchedule.fixtures[0].event()
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: [], leagueItems: []))
        try SportsPersonalizationStore.setLeague(cpl, enabled: true, in: context)
        let leagues = try ModelContext(context.container).fetch(FetchDescriptor<FollowedLeagueItem>())
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: [], leagueItems: leagues))
        XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: leagues), "Caribbean Premier League")
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: event("willow", "Willow Cricket", "cricket", date: nil), teamKeys: [], leagueItems: leagues))
        try SportsPersonalizationStore.setLeague(cpl, enabled: false, in: context)
        XCTAssertTrue(try ModelContext(context.container).fetch(FetchDescriptor<FollowedLeagueItem>()).isEmpty)
    }

    @MainActor
    func testEveryVerifiedCPLFixtureIncludingKnockoutsMatchesTheCPLInterest() throws {
        let cpl = try XCTUnwrap(SportsPersonalizationPolicy.leagues.first { $0.id == "cpl" })
        let saved = FollowedLeagueItem(id: cpl.id, leagueName: cpl.name,
                                       sportCategory: cpl.sportCategory, country: cpl.country)
        let fixtures = CPLSchedule.fixtures.map { $0.event() }

        XCTAssertEqual(fixtures.count, 39)
        XCTAssertTrue(fixtures.allSatisfy {
            SportsPersonalizationPolicy.isFollowed(event: $0, teamKeys: [], leagueItems: [saved])
        })
        XCTAssertTrue(fixtures.contains { $0.id == "cpl-2026-29" })
    }

    @MainActor
    func testCurrentSevenPMFixtureSurvivesInterestFilteringIntoHomeLiveSection() throws {
        let cpl = try XCTUnwrap(SportsPersonalizationPolicy.leagues.first { $0.id == "cpl" })
        let saved = FollowedLeagueItem(id: cpl.id, leagueName: cpl.name,
                                       sportCategory: cpl.sportCategory, country: cpl.country)
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first { $0.number == 29 }).event()
        let now = try XCTUnwrap(fixture.kickoffDate).addingTimeInterval(5 * 60)
        let schedule = HomeSportsDiscovery(events: [fixture], now: now)
        let selectedItems = schedule.items.filter {
            SportsPersonalizationPolicy.isFollowed(event: $0.event, teamKeys: [], leagueItems: [saved])
        }
        let sections = schedule.homeSections(
            from: selectedItems,
            diverseUpcoming: false,
            featuredLiveLimit: 3,
            upcomingHorizon: CatalogTimingPolicy.personalizedHomeUpcomingHorizon,
            upcomingLimit: 3
        )

        XCTAssertEqual(sections.featuredLive.map(\.id), ["cpl-2026-29"])
        XCTAssertTrue(sections.moreLive.isEmpty)
    }

    @MainActor
    func testViewContextLeagueToggleIsImmediatelyVisibleAndRollsBackFailure() throws {
        let context = try context()
        let cpl = try XCTUnwrap(SportsPersonalizationPolicy.leagues.first { $0.id == "cpl" })

        try SportsPersonalizationStore.setLeagueFromView(cpl, enabled: true, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FollowedLeagueItem>()).map(\.id), ["cpl"])

        enum Failure: Error { case disk }
        XCTAssertThrowsError(try SportsPersonalizationStore.setLeagueFromView(
            cpl, enabled: false, in: context, save: { _ in throw Failure.disk }
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<FollowedLeagueItem>()).map(\.id), ["cpl"])
    }

    @MainActor
    func testLeagueMarkersAreExactSportScopedAndUnambiguous() {
        XCTAssertEqual(SportsPersonalizationPolicy.league(for: event("nba-123", "Los Angeles Lakers vs Boston Celtics", "basketball"))?.id, "nba")
        XCTAssertEqual(SportsPersonalizationPolicy.league(for: event("wnba-123", "Seattle Storm vs Las Vegas Aces", "basketball"))?.id, "wnba")
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("nbafake-123", "Example vs Another", "basketball")))
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("nba-wnba-123", "Example vs Another", "basketball")))
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("nba-123", "Example vs Another", "baseball")))
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("opaque", "Los Angeles Lakers vs Boston Celtics", "basketball")))
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("nba-123", "Example vs Another", "basketball", conflict: true)))
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("wcpl-123", "Trinbago Knight Riders Women vs Barbados Royals Women", "cricket")))
        XCTAssertNil(SportsPersonalizationPolicy.league(for: event("cpl-123", "CPL news and interviews", "cricket")))
        let premier = FollowedLeagueItem(id: "premier-league", leagueName: "Premier League", sportCategory: "football")
        XCTAssertNil(SportsPersonalizationPolicy.followedLeagueName(for: CPLSchedule.fixtures[0].event(), in: [premier]))
    }

    @MainActor
    func testFailedLeagueSelectionDoesNotClaimPersistence() throws {
        let context = try context()
        let league = try XCTUnwrap(SportsPersonalizationPolicy.leagues.first { $0.id == "nba" })
        enum Failure: Error { case disk }
        XCTAssertThrowsError(try SportsPersonalizationStore.setLeague(league, enabled: true, in: context, save: { _ in throw Failure.disk }))
        XCTAssertTrue(try ModelContext(context.container).fetch(FetchDescriptor<FollowedLeagueItem>()).isEmpty)
    }

    @MainActor
    func testInterestsEditorStartsInSavedSportWithoutSelectingOrRemovingChoices() {
        let cpl = FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket")
        let choices = [cpl]
        XCTAssertEqual(HomeInterestsEditorPolicy.initialSport(sports: [], leagues: choices, teams: []), "cricket")
        XCTAssertEqual(HomeInterestsEditorPolicy.initialTeamLeague(sport: "cricket", followedLeagues: choices), "Caribbean Premier League")
        XCTAssertEqual(HomeInterestsEditorPolicy.initialSport(sports: ["darts"], leagues: [], teams: []), "darts")
        XCTAssertEqual(HomeInterestsEditorPolicy.initialSport(sports: [], leagues: [], teams: []), "football")
        XCTAssertNil(HomeInterestsEditorPolicy.initialTeamLeague(sport: "tennis", followedLeagues: choices))
        XCTAssertEqual(choices.map(\.id), ["cpl"])
    }

    @MainActor
    func testInterestsEditorSeedsReviewedTeamCatalogAndPreservesExistingInitializerDefault() {
        let wnba = FollowedLeagueItem(id: "wnba", leagueName: "WNBA", sportCategory: "basketball")
        XCTAssertEqual(HomeInterestsEditorPolicy.initialTeamLeague(sport: "basketball", followedLeagues: [wnba]), "WNBA")
        XCTAssertEqual(HomeInterestsEditorPolicy.initialTeamLeague(sport: "football", followedLeagues: [wnba]), "English Premier League")
        XCTAssertEqual(TeamOnboardingCatalog.validatedInitialLeague(nil), "English Premier League")
        XCTAssertEqual(TeamOnboardingCatalog.validatedInitialLeague("unknown"), "English Premier League")
        XCTAssertEqual(TeamOnboardingCatalog.validatedInitialLeague("Caribbean Premier League"), "Caribbean Premier League")
        XCTAssertEqual(Set(TeamOnboardingCatalog.options.map(\.name)).count, TeamOnboardingCatalog.options.count)
    }

    @MainActor
    func testInterestsPreviewImmediatelyReflectsChangedSportWithSameSelectionCount() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = event("future-football", "Liverpool vs Chelsea", "football", date: 1_800_003_600)
        let second = event("future-cricket", "West Indies vs England", "cricket", date: 1_800_007_200)
        let channel = event("willow-channel", "Willow Cricket", "cricket", date: nil)
        let conflicting = event("conflicting-cricket", "West Indies vs England", "cricket", date: 1_800_010_800, conflict: true)
        let events = [channel, conflicting, second, first]
        XCTAssertEqual(HomeInterestsEditorPolicy.previewItems(events: events, teams: [], leagues: [], sports: ["football"],
            onlySelected: true, now: now).map(\.id), ["future-football"])
        let cricket = HomeInterestsEditorPolicy.previewItems(events: events, teams: [], leagues: [], sports: ["cricket"],
            onlySelected: true, now: now)
        XCTAssertEqual(cricket.map(\.id), ["future-cricket"])
        XCTAssertEqual(cricket.first?.phase, .upcoming)
        XCTAssertEqual(events.count, 4)
        XCTAssertTrue(events.first { $0.id == "conflicting-cricket" }?.hasCatalogIdentityConflict == true)
    }

    @MainActor
    func testInterestsPreviewUsesPersonalizedWindowAndFailsOpenForEmptySelection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = event("soon-baseball", "Los Angeles Dodgers vs New York Mets", "baseball", date: 1_800_003_600)
        let nextDay = event("tomorrow-cricket", "West Indies vs England", "cricket", date: 1_800_086_400)
        let beyondWindow = event("later-cricket", "West Indies vs England", "cricket", date: 1_800_345_600)
        XCTAssertEqual(HomeInterestsEditorPolicy.previewItems(events: [nextDay, soon], teams: [], leagues: [], sports: [],
            onlySelected: true, now: now).map(\.id), ["soon-baseball"])
        XCTAssertEqual(HomeInterestsEditorPolicy.previewItems(events: [beyondWindow, nextDay, soon], teams: [], leagues: [], sports: ["cricket"],
            onlySelected: true, now: now).map(\.id), ["tomorrow-cricket"])
        XCTAssertTrue(HomeInterestsEditorPolicy.previewItems(events: [soon], teams: [], leagues: [], sports: [],
            onlySelected: false, now: now, limit: 0).isEmpty)
    }

    @MainActor
    func testInterestsPreviewKeepsCanonicalTeamSelectionSeparateFromWholeSport() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let united = FollowedTeamItem(key: "legacy-united", teamName: "Man Utd", sportCategory: "football")
        let chosen = event("chosen", "Manchester United vs Chelsea", "football", date: 1_800_007_200)
        let other = event("other", "Liverpool vs Arsenal", "football", date: 1_800_003_600)
        XCTAssertEqual(HomeInterestsEditorPolicy.previewItems(events: [other, chosen], teams: [united], leagues: [], sports: [],
            onlySelected: true, now: now).map(\.id), ["chosen"])
        XCTAssertEqual(HomeInterestsEditorPolicy.previewItems(events: [other, chosen], teams: [united], leagues: [], sports: ["football"],
            onlySelected: true, now: now).map(\.id), ["other", "chosen"])
        XCTAssertEqual(HomeInterestsEditorPolicy.selectionNames(sports: ["cricket"], leagues: [], teams: [united]), ["Cricket", "Manchester United"])
        XCTAssertEqual(united.teamName, "Man Utd")
        XCTAssertEqual(united.key, "legacy-united")
    }

    @MainActor
    func testInterestsPreviewDoesNotPromoteTerminalHeldOrPostponedFixtures() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func fixture(_ id: String, status: CricketFixtureCatalog.Status, verified: Bool) -> AnalyticalDataEngine.EventReference {
            .init(id: id, title: "West Indies vs England", category: "cricket", date: 1_800_003_600,
                  poster: nil, popular: false, teams: nil, sources: [],
                  cricketFixture: .init(fixtureID: id, competitionID: "icc", competitionName: "International cricket",
                    format: .t20, status: status, observedAt: now, verified: verified))
        }
        // Each is a separate snapshot of this fixture, not contradictory status
        // rows for the same teams and exact kickoff in one catalog projection.
        for event in [fixture("finished", status: .finished, verified: true),
                      fixture("cancelled", status: .cancelled, verified: true),
                      fixture("postponed", status: .postponed, verified: true),
                      fixture("held", status: .scheduled, verified: false)] {
            XCTAssertTrue(HomeInterestsEditorPolicy.previewItems(events: [event], teams: [], leagues: [], sports: ["cricket"],
                onlySelected: true, now: now, limit: 10).isEmpty, event.id)
        }
        let rows = HomeInterestsEditorPolicy.previewItems(events: [fixture("scheduled", status: .scheduled, verified: true)],
            teams: [], leagues: [], sports: ["cricket"],
            onlySelected: true, now: now, limit: 10)
        XCTAssertEqual(rows.map(\.id), ["scheduled"])
        XCTAssertEqual(rows.first?.isOnNow, false)
    }

    @MainActor
    private func homeFactsKey(_ selection: SportsPersonalizationPolicy.PreparedSelection,
                              contentRevision: Int = 1, scoreRevisionMilliseconds: Int64 = 1) -> HomePersonalizationFactsKey {
        .init(contentRevision: contentRevision, scoreRevisionMilliseconds: scoreRevisionMilliseconds,
              selectionIdentity: selection.identity)
    }

    @MainActor
    private func homeFacts(for item: HomeSportsDiscovery.Item,
                           selection: SportsPersonalizationPolicy.PreparedSelection,
                           officialMatch: FootballMatch? = nil) -> HomePersonalizationFacts {
        .init(isFollowed: SportsPersonalizationPolicy.isFollowed(event: item.event, selection: selection, officialMatch: officialMatch),
              isMajorLeague: SportsTeamIdentity.sharedMajorLeague(home: item.event.homeName, away: item.event.awayName, category: item.sport) != nil,
              isCPL: item.event.isCPLFixture)
    }

    @MainActor
    private func context() throws -> ModelContext {
        let schema = Schema([FollowedTeamItem.self, FollowedLeagueItem.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @MainActor
    private func freshTeams(_ context: ModelContext) throws -> [FollowedTeamItem] {
        try ModelContext(context.container).fetch(FetchDescriptor<FollowedTeamItem>())
    }

    @MainActor
    private func leagueFollowPair(home: String = "Aston Villa", away: String = "Crystal Palace",
                                  title: String? = nil) -> AnalyticalDataEngine.EventReference {
        .init(id: "opaque-football-pair", title: title ?? "\(home) vs \(away)", category: "football",
              date: 1_800_000_000, poster: nil, popular: false,
              teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
              sources: [.init(source: "delta", id: "opaque-pair-source")])
    }

    @MainActor
    private func event(_ id: String, _ title: String, _ category: String,
                       date: Int64? = 1_788_552_000, conflict: Bool = false) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: title, category: category, date: date, poster: nil, popular: false,
              teams: nil, sources: [], hasCatalogIdentityConflict: conflict)
    }
}
