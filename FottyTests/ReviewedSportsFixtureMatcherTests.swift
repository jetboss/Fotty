import XCTest
@testable import Fotty

final class ReviewedSportsFixtureMatcherTests: XCTestCase {
    func testOfficialLongClubNamesDoNotLoseActualBroadcastSources() {
        for pair in [["Bologna FC 1909", "Bologna"], ["Stade Rennais FC 1901", "Rennes"],
                     ["SV 07 Elversberg", "Elversberg"], ["VfB Stuttgart", "Stuttgart"],
                     ["Olympique Lyonnais", "Lyon"], ["Bayer 04 Leverkusen", "Leverkusen"],
                     ["RCD Espanyol de Barcelona", "Espanyol"], ["Parma Calcio 1913", "Parma"]] {
            XCTAssertNotNil(FootballCompetitionCatalog.canonicalClubID(for: pair[0]), pair[0])
            XCTAssertEqual(FootballCompetitionCatalog.canonicalClubID(for: pair[0]),
                           FootballCompetitionCatalog.canonicalClubID(for: pair[1]), pair.joined(separator: " / "))
        }
        XCTAssertNotEqual(FootballCompetitionCatalog.canonicalClubID(for: "Paris FC"),
                          FootballCompetitionCatalog.canonicalClubID(for: "Paris Saint-Germain"))
        XCTAssertNil(FootballCompetitionCatalog.canonicalClubID(for: "Bologna U19"))
        XCTAssertNil(FootballCompetitionCatalog.canonicalClubID(for: "Bologna Women"))
    }

    private typealias Matcher = ReviewedSportsFixtureMatcher
    private let kickoff = Date(timeIntervalSince1970: 1_800_000_000)

    func testSharedIdentityAcceptsReviewedAliasesWithoutRequiringACSSpecificID() throws {
        let requested = try XCTUnwrap(Matcher.requestIdentity(for: request()))
        let row = candidate(id: "reviewed-second-source:fixture", target: "reviewed-second-source:video",
                            title: "Everton vs Hull City", cast: ["Everton", "Hull City"], sport: "soccer")
        let identity = try XCTUnwrap(row.identity)
        XCTAssertEqual(identity.sport, requested.sport)
        XCTAssertEqual(identity.pair, requested.pair)
        XCTAssertEqual(identity.effectiveID, "reviewed-second-source:video")
        XCTAssertEqual(identity.resourceType, "tv")
        XCTAssertEqual(Matcher.select(for: requested, from: [row]), .matched(0))
        XCTAssertEqual(Matcher.select(for: request(), from: [row]), .matched(0))
    }

    func testRequestRequiresAnExplicitDateRecognizedSportAndCompleteDistinctPair() {
        let undated = StreamPlaybackRequest(matchID: "fixture", displayTitle: "Hull City vs Everton",
            homeTeam: "Hull City", awayTeam: "Everton", category: "football")
        XCTAssertNil(Matcher.requestIdentity(for: undated))
        for value in [request(sport: "unreviewed sport"), request(home: "TBD"),
                      request(away: "Hull City"), request(title: "Hull City vs Everton | Women's football")] {
            XCTAssertNil(Matcher.requestIdentity(for: value))
            XCTAssertEqual(Matcher.select(for: value, from: [candidate()]), .missing)
        }
    }

    func testLiveTitleCannotReplaceMissingExplicitCandidateDate() {
        XCTAssertNil(Matcher.fixtureIdentity(sport: "football", cast: ["Hull City", "Everton"],
            title: "LIVE: Hull City vs Everton", kickoff: nil, effectiveID: "video", resourceType: "tv"))
    }

    func testBothTeamsSportAndInclusiveFifteenMinuteWindowRemainRequired() {
        let invalid = [candidate(id: "partial", cast: ["Hull City", "Chelsea"]),
                       candidate(id: "other-sport", sport: "cricket"),
                       candidate(id: "too-late", offset: 901),
                       candidate(id: "too-early", offset: -901)]
        XCTAssertEqual(Matcher.select(for: request(), from: invalid), .missing)
        for offset in [-900.0, 900.0] {
            XCTAssertEqual(Matcher.select(for: request(), from: [candidate(offset: offset)]), .matched(0))
        }
    }

    func testTitleAndCastKeepIndependentSquadEvidenceAcrossTeamOrder() {
        let women = candidate(title: "Everton W vs Hull City W", cast: ["Hull City AFC", "Everton FC"])
        XCTAssertNotNil(women.identity)
        XCTAssertEqual(Matcher.select(for: request(), from: [women]), .missing)
        XCTAssertEqual(Matcher.select(for: request(home: "Hull City AFC Women", away: "Everton FC Women"),
                                      from: [women]), .matched(0))
        let titleQualifiedRequest = request(title: "Hull City W vs Everton W")
        XCTAssertEqual(Matcher.select(for: titleQualifiedRequest, from: [women]), .matched(0))
        XCTAssertEqual(Matcher.select(for: titleQualifiedRequest, from: [candidate()]), .missing)
        for suffix in ["U19", "Under 21", "Reserves", "Academy"] {
            let row = candidate(title: "Hull City \(suffix) vs Everton \(suffix)")
            XCTAssertEqual(Matcher.select(for: request(), from: [row]), .missing, suffix)
        }
    }

    func testContradictoryOrAmbiguousParticipantEvidenceFailsClosed() {
        let rejected = [
            candidate(title: "Hull City vs Everton", cast: ["Arsenal", "Tottenham"]),
            candidate(title: "Hull City U19 vs Everton U19", cast: ["Hull City Women", "Everton Women"]),
            candidate(title: "Hull City vs Everton | Women's football"),
            candidate(title: "Hull City vs Everton vs Arsenal")
        ]
        XCTAssertTrue(rejected.allSatisfy { $0.identity == nil })
        XCTAssertEqual(Matcher.select(for: request(), from: rejected), .missing)
        let unknown = candidate(cast: ["Unreviewed Town", "Unreviewed Rovers"])
        XCTAssertEqual(Matcher.select(for: request(home: "Unreviewed Town FC", away: "Unreviewed Rovers AFC"),
                                      from: [unknown]), .missing)
    }

    func testMalformedMetadataOrEffectiveTargetSiblingRemainsConflictEvidenceInEitherOrder() {
        let exact = candidate(id: "exact", target: "shared")
        let malformed = [Matcher.Candidate(metadataID: "exact", effectiveID: "different", identity: nil),
                         Matcher.Candidate(metadataID: "other", effectiveID: "shared", identity: nil)]
        for other in malformed {
            for rows in [[exact, other], [other, exact]] {
                XCTAssertEqual(Matcher.select(for: request(), from: rows), .conflicting)
            }
        }
        let unrelated = Matcher.Candidate(metadataID: "unrelated", effectiveID: "unrelated", identity: nil)
        XCTAssertEqual(Matcher.select(for: request(), from: [unrelated, exact]), .matched(1))
    }

    func testMetadataAndEffectiveTargetConflictsIncludeDateSportSquadTypeAndRoute() {
        let exact = candidate(id: "exact", target: "shared")
        let conflicts = [candidate(id: "exact", target: "redirected"),
                         candidate(id: "other", target: "shared", offset: 86_400),
                         candidate(id: "other", target: "shared", sport: "cricket"),
                         candidate(id: "other", target: "shared", title: "Hull City W vs Everton W"),
                         candidate(id: "other", target: "shared", resourceType: "movie")]
        for other in conflicts {
            for rows in [[exact, other], [other, exact]] {
                XCTAssertEqual(Matcher.select(for: request(), from: rows), .conflicting)
            }
        }
    }

    func testEquivalentDuplicateMetadataReturnsFirstOriginalIndexButDistinctIDsRemainConflicting() {
        let first = candidate(id: "same", target: "shared")
        let equivalent = candidate(id: "same", target: "shared", title: "Everton FC vs Hull City AFC",
                                   cast: ["Everton FC", "Hull City AFC"], sport: "soccer")
        let unrelated = candidate(id: "other-fixture", cast: ["Arsenal", "Tottenham"])
        XCTAssertEqual(Matcher.select(for: request(), from: [unrelated, first, equivalent]), .matched(1))
        XCTAssertEqual(Matcher.select(for: request(), from: [equivalent, first]), .matched(0))
        let anotherID = candidate(id: "another", target: "shared")
        XCTAssertEqual(Matcher.select(for: request(), from: [first, anotherID]), .conflicting)
    }

    private func request(home: String = "Hull City AFC", away: String = "Everton FC",
                         sport: String = "football", title: String? = nil) -> StreamPlaybackRequest {
        StreamPlaybackRequest(matchID: "fixture", displayTitle: title ?? "\(home) vs \(away)",
                              homeTeam: home, awayTeam: away, category: sport, kickoffDate: kickoff)
    }

    private func candidate(id: String = "reviewed-fixture", target: String? = nil,
                           offset: TimeInterval = 0, title: String? = nil,
                           cast: [String] = ["Hull City", "Everton"], sport: String = "football",
                           resourceType: String = "tv") -> Matcher.Candidate {
        let effectiveID = target ?? id
        let identity = Matcher.fixtureIdentity(sport: sport, cast: cast,
            title: title ?? cast.joined(separator: " vs "), kickoff: kickoff.addingTimeInterval(offset),
            effectiveID: effectiveID, resourceType: resourceType)
        return Matcher.Candidate(metadataID: id, effectiveID: effectiveID, identity: identity)
    }
}
