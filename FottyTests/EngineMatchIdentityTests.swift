import XCTest
@testable import Fotty

final class EngineMatchIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_361_600)

    private func identity(_ sport: String, _ home: String, _ away: String,
                          _ kickoff: Date, _ effectiveID: String) -> MatchIdentity.FixtureIdentity {
        MatchIdentity.FixtureIdentity(sport: sport,
                                      pair: MatchIdentity.pairKey(home: home, away: away, sport: sport)!,
                                      kickoff: kickoff, effectiveID: effectiveID)
    }

    func testNormalizedFoldsCaseDiacriticsWidthAndAmpersand() {
        XCTAssertEqual(MatchIdentity.normalized("Manchester United"), "manchester united")
        XCTAssertEqual(MatchIdentity.normalized("St. Pauli"), "st pauli")
        XCTAssertEqual(MatchIdentity.normalized("A & B"), "a and b")
        XCTAssertEqual(MatchIdentity.normalized("São Paulo"), "sao paulo")
    }

    func testSportKeyMapsAliasesAndRejectsUnknown() {
        XCTAssertEqual(MatchIdentity.sportKey("football"), "football")
        XCTAssertEqual(MatchIdentity.sportKey("soccer"), "football")
        XCTAssertEqual(MatchIdentity.sportKey("Ice Hockey"), "hockey")
        XCTAssertEqual(MatchIdentity.sportKey("american football"), "american-football")
        XCTAssertEqual(MatchIdentity.sportKey("formula 1"), "motorsport")
        XCTAssertEqual(MatchIdentity.sportKey("curling"), "")
    }

    func testBaseTeamNameStripsSquadTokens() {
        XCTAssertEqual(MatchIdentity.baseTeamName("Arsenal Women"), "arsenal")
        XCTAssertEqual(MatchIdentity.baseTeamName("Chelsea W.F.C."), "chelsea f c")
        XCTAssertEqual(MatchIdentity.baseTeamName("Man United U21"), "man united")
        XCTAssertEqual(MatchIdentity.baseTeamName("Lyon Ladies"), "lyon")
        XCTAssertEqual(MatchIdentity.baseTeamName("Paris Saint-Germain"), "paris saint germain")
    }

    func testSquadQualifiersNormalizeWomenAndReserves() {
        XCTAssertEqual(MatchIdentity.squadQualifiers("Arsenal Women"), ["women"])
        XCTAssertEqual(MatchIdentity.squadQualifiers("Arsenal W"), ["women"])
        XCTAssertEqual(MatchIdentity.squadQualifiers("Lyon Ladies"), ["women"])
        XCTAssertEqual(MatchIdentity.squadQualifiers("Man United Reserves"), ["reserves"])
        XCTAssertEqual(MatchIdentity.squadQualifiers("Chelsea U21"), ["u21"])
        XCTAssertEqual(MatchIdentity.squadQualifiers("Arsenal"), [])
    }

    func testTitleTeamsParsesSingleVsSeparator() {
        XCTAssertEqual(MatchIdentity.titleTeams("Chelsea vs Arsenal"), .pair("Chelsea", "Arsenal"))
        XCTAssertEqual(MatchIdentity.titleTeams("Chelsea v Arsenal"), .pair("Chelsea", "Arsenal"))
        XCTAssertEqual(MatchIdentity.titleTeams("Chelsea versus Arsenal"), .pair("Chelsea", "Arsenal"))
        XCTAssertEqual(MatchIdentity.titleTeams("LIVE: Chelsea vs Arsenal"), .pair("Chelsea", "Arsenal"))
        XCTAssertEqual(MatchIdentity.titleTeams("Upcoming: A @ B"), .pair("A", "B"))
    }

    func testTitleTeamsRejectsAmbiguityAndAbsence() {
        XCTAssertEqual(MatchIdentity.titleTeams("Chelsea"), .absent)
        XCTAssertEqual(MatchIdentity.titleTeams("Chelsea vs Arsenal vs Spurs"), .ambiguous)
        XCTAssertEqual(MatchIdentity.titleTeams("Premier League · Chelsea vs Arsenal"), .ambiguous)
        XCTAssertEqual(MatchIdentity.titleTeams("Chelsea - Arsenal"), .absent)
    }

    func testCricketContextParsesFormatOrdinalAndDay() {
        XCTAssertEqual(MatchIdentity.cricketContext("3rd Test day 3: South Africa vs Australia"),
                       .init(format: "Test", ordinal: 3, day: 3))
        XCTAssertEqual(MatchIdentity.cricketContext("1st T20: India vs Pakistan"),
                       .init(format: "T20", ordinal: 1, day: nil))
        XCTAssertEqual(MatchIdentity.cricketContext("2nd ODI"),
                       .init(format: "ODI", ordinal: 2, day: nil))
        XCTAssertNil(MatchIdentity.cricketContext("A football match"))
    }

    func testCricketContextDayWithoutOrdinal() {
        XCTAssertEqual(MatchIdentity.cricketContext("Test day 5"),
                       .init(format: "Test", ordinal: nil, day: 5))
    }

    func testPairKeyIsSortedAndRejectsPlaceholders() {
        XCTAssertEqual(MatchIdentity.pairKey(home: "Arsenal", away: "Chelsea", sport: "football"),
                       ["arsenal", "chelsea"])
        XCTAssertEqual(MatchIdentity.pairKey(home: "Chelsea", away: "Arsenal", sport: "football"),
                       ["arsenal", "chelsea"])
        XCTAssertNil(MatchIdentity.pairKey(home: "TBD", away: "Chelsea", sport: "football"))
        XCTAssertNil(MatchIdentity.pairKey(home: "Chelsea", away: "Chelsea", sport: "football"))
    }

    func testTeamKeyKeepsSquadQualifiersDistinct() {
        XCTAssertEqual(MatchIdentity.teamKey("Arsenal Women", sport: "football"), "arsenal|women")
        XCTAssertEqual(MatchIdentity.teamKey("Arsenal", sport: "football"), "arsenal")
        XCTAssertNotEqual(MatchIdentity.teamKey("Arsenal Women", sport: "football"),
                          MatchIdentity.teamKey("Arsenal", sport: "football"))
    }

    func testSelectMatchesExactSportPairAndKickoff() {
        let candidate = MatchIdentity.CandidateIdentity(
            metadataID: "a", effectiveID: "stream-a",
            identity: identity("football", "Chelsea", "Arsenal", now, "stream-a"))
        XCTAssertEqual(MatchIdentity.select(sport: "football",
                                            pair: MatchIdentity.pairKey(home: "Chelsea", away: "Arsenal", sport: "football")!,
                                            kickoff: now, from: [candidate]),
                       .matched(0))
    }

    func testSelectRejectsWrongSportPairOrKickoff() {
        let wrongSport = MatchIdentity.CandidateIdentity(
            metadataID: "a", effectiveID: "s", identity: identity("cricket", "Chelsea", "Arsenal", now, "s"))
        let wrongPair = MatchIdentity.CandidateIdentity(
            metadataID: "a", effectiveID: "s", identity: identity("football", "Chelsea", "Spurs", now, "s"))
        let wrongKickoff = MatchIdentity.CandidateIdentity(
            metadataID: "a", effectiveID: "s", identity: identity("football", "Chelsea", "Arsenal", now.addingTimeInterval(3600), "s"))
        let pair = MatchIdentity.pairKey(home: "Chelsea", away: "Arsenal", sport: "football")!
        XCTAssertEqual(MatchIdentity.select(sport: "football", pair: pair, kickoff: now, from: [wrongSport]), .missing)
        XCTAssertEqual(MatchIdentity.select(sport: "football", pair: pair, kickoff: now, from: [wrongPair]), .missing)
        XCTAssertEqual(MatchIdentity.select(sport: "football", pair: pair, kickoff: now, from: [wrongKickoff]), .missing)
    }

    func testSelectRejectsConflictingSibling() {
        let good = MatchIdentity.CandidateIdentity(
            metadataID: "shared", effectiveID: "s",
            identity: identity("football", "Chelsea", "Arsenal", now, "s"))
        let contradictory = MatchIdentity.CandidateIdentity(
            metadataID: "shared", effectiveID: "s",
            identity: identity("football", "Chelsea", "Spurs", now, "s"))
        let pair = MatchIdentity.pairKey(home: "Chelsea", away: "Arsenal", sport: "football")!
        XCTAssertEqual(MatchIdentity.select(sport: "football", pair: pair, kickoff: now, from: [good, contradictory]),
                       .conflicting)
    }

    func testSelectRejectsMultipleDistinctMatches() {
        let a = MatchIdentity.CandidateIdentity(
            metadataID: "a", effectiveID: "sa", identity: identity("football", "Chelsea", "Arsenal", now, "sa"))
        let b = MatchIdentity.CandidateIdentity(
            metadataID: "b", effectiveID: "sb", identity: identity("football", "Chelsea", "Arsenal", now, "sb"))
        let pair = MatchIdentity.pairKey(home: "Chelsea", away: "Arsenal", sport: "football")!
        XCTAssertEqual(MatchIdentity.select(sport: "football", pair: pair, kickoff: now, from: [a, b]),
                       .conflicting)
    }
}
