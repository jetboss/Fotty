import Foundation
import XCTest
@testable import Fotty

@MainActor
final class UCLReportedScoreTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-29T17:32:10Z")!
    private var publisherDate: Date { now.addingTimeInterval(-300) }
    private var score: UCLReportedScore { .init(home: 2, away: 0, publisherUpdatedAt: stamp(publisherDate)) }
    private let teams: [SportsFixtureCatalog.Participant] = [
        .init(id: "football-data:86", name: "Real Madrid CF", role: "home"),
        .init(id: "football-data:4", name: "Borussia Dortmund", role: "away")
    ]
    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func fixture(score: UCLReportedScore? = nil, competition: String = "champions-league",
                         status: SportsFixtureCatalog.Status = .live, receipt: Date? = nil,
                         verification: SportsFixtureCatalog.Source.Verification = .verified) -> SportsFixtureCatalog.Fixture {
        .init(id: "sports-fixture:\(competition):575377", sport: "football", start: stamp(now.addingTimeInterval(-3_600)),
              status: status, eventKind: .match, title: "Real Madrid CF vs Borussia Dortmund",
              competitionId: competition, competitionName: "UEFA Champions League", participants: teams,
              squad: .init(gender: .men, ageGroup: "senior"),
              source: .init(name: "football-data.org", url: "https://api.football-data.org/v4/matches",
                observedAt: stamp(receipt ?? now), updatedAt: stamp(publisherDate), verification: verification), reportedScore: score)
    }

    private func snapshot(_ fixtures: [SportsFixtureCatalog.Fixture], receipt: Date? = nil,
                          unavailable: Bool = false) -> SportsFixtureCatalog.Snapshot {
        .init(schemaVersion: 1, complete: true, checkedAt: stamp(receipt ?? now), revision: "reported-cl-score-test",
              sourceStatus: unavailable ? .partial : .verified, fixtures: fixtures,
              coverage: [.init(sport: "football", competitionId: "champions-league", competitionName: "UEFA Champions League",
                status: unavailable ? .unavailable : .covered, checkedAt: stamp(receipt ?? now), fixtureCount: fixtures.count,
                pendingFixtureCount: 0, nextStart: nil)])
    }

    private func event(score: UCLReportedScore? = nil, receiptOffset: TimeInterval = 0, verified: Bool = true,
                       status: SportsFixtureCatalog.Status = .live, competition: String = "champions-league",
                       gender: SportsFixtureCatalog.Squad.Gender = .men, ageGroup: String = "senior",
                       participants: [SportsFixtureCatalog.Participant]? = nil, conflict: Bool = false,
                       id: String? = nil) -> EventReference {
        let fixtureID = "sports-fixture:\(competition):575377"
        return .init(id: id ?? fixtureID, title: "Real Madrid CF vs Borussia Dortmund", category: "football",
            date: Int64(now.addingTimeInterval(-3_600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0].name, badge: nil), away: .init(name: teams[1].name, badge: nil)),
            sources: [], hasCatalogIdentityConflict: conflict,
            sportsFixture: .init(fixtureID: fixtureID, sport: "football", competitionID: competition,
                competitionName: "UEFA Champions League", eventKind: .match, title: "Real Madrid CF vs Borussia Dortmund",
                participants: participants ?? teams, squad: .init(gender: gender, ageGroup: ageGroup), status: status,
                observedAt: publisherDate, verified: verified, reportedScore: score,
                reportedScoreObservedAt: now.addingTimeInterval(receiptOffset)), competitionID: competition)
    }

    func testOptionalReportedScoreUsesOriginalPublisherDateAndDoesNotCreateAStreamOrLiveFeed() throws {
        let original = snapshot([fixture(score: score)])
        let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(original), now: now)
        let projected = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: now).first)
        XCTAssertEqual(UCLReportedScorePolicy.score(for: projected, at: now), score)
        XCTAssertEqual(projected.sportsFixture?.reportedScoreObservedAt, now)
        XCTAssertEqual(projected.sportsFixture?.reportedScore?.publisherDate, publisherDate)
        XCTAssertTrue(projected.sources?.isEmpty == true)
        XCTAssertFalse(FootballDataPolicy.supportsLiveScores(competitionId: 2001, competitionName: "UEFA Champions League"))
        let restored = try JSONDecoder().decode(EventReference.self, from: JSONEncoder().encode(projected))
        XCTAssertEqual(restored.sportsFixture, projected.sportsFixture)
    }

    func testFinishedUCLReportedScoreRemainsReadableWithoutAddingAPlaybackFixture() async throws {
        let final = UCLReportedScore(home: 3, away: 1, publisherUpdatedAt: stamp(publisherDate))
        let manifest = snapshot([fixture(score: final, status: .finished)])
        let model = MatchListViewModel(refreshSports: { manifest }, now: { self.now })
        await model.refresh()

        XCTAssertTrue(model.playbackCatalog.isEmpty)
        let current = try XCTUnwrap(CurrentSportsMatchContextPolicy.event(for: event(score: score),
            in: model.matchContextCatalog, at: now))
        XCTAssertEqual(current.sportsFixture?.status, .finished)
        XCTAssertEqual(UCLReportedScorePolicy.score(for: current, at: now), final)
        XCTAssertTrue(current.sources?.isEmpty == true)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: current, in: model.playbackCatalog, at: now))
        XCTAssertTrue(model.playbackCatalog.isEmpty)
    }

    func testLegacyFixtureAndMetadataHaveNoReportedScoreRatherThanZero() throws {
        let decoded = try JSONDecoder().decode(SportsFixtureCatalog.Fixture.self, from: JSONEncoder().encode(fixture()))
        XCTAssertNil(decoded.reportedScore)
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(event().sportsFixture))) as? [String: Any])
        metadata.removeValue(forKey: "reportedScore"); metadata.removeValue(forKey: "reportedScoreObservedAt")
        let legacy = try JSONDecoder().decode(SportsFixtureMetadata.self, from: JSONSerialization.data(withJSONObject: metadata))
        XCTAssertNil(legacy.reportedScore)
        XCTAssertNil(legacy.reportedScoreObservedAt)
    }

    func testActualFutureUCLNullableShapeNeverCreatesZeroZeroOrDropsFixture() throws {
        let base = snapshot([fixture(status: .scheduled)])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        var rows = try XCTUnwrap(json["fixtures"] as? [[String: Any]])
        rows[0]["reportedScore"] = ["home": NSNull(), "away": NSNull(), "publisherUpdatedAt": stamp(publisherDate)]
        json["fixtures"] = rows
        let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now)
        XCTAssertEqual(accepted.fixtures.count, 1)
        XCTAssertEqual(accepted.fixtures[0].status, .scheduled)
        XCTAssertNil(accepted.fixtures[0].reportedScore)
    }

    func testBadOptionalScoreIsDiscardedWithoutRejectingFixture() throws {
        let base = snapshot([fixture(score: score)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        for invalid: Any in [NSNull(), "bad-score", ["home": 2],
                            ["home": "2", "away": 0, "publisherUpdatedAt": stamp(publisherDate)],
                            ["home": -1, "away": 0, "publisherUpdatedAt": stamp(publisherDate)],
                            ["home": 2, "away": 0, "publisherUpdatedAt": stamp(now)]] {
            var body = object, row = try XCTUnwrap((object["fixtures"] as? [[String: Any]])?.first)
            row["reportedScore"] = invalid; body["fixtures"] = [row]
            let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: body), now: now)
            XCTAssertNil(accepted.fixtures[0].reportedScore)
            XCTAssertEqual(accepted.fixtures[0].source.observedAt, stamp(now))
            XCTAssertEqual(accepted.fixtures[0].status, .live)
        }
    }

    func testOnlyVerifiedCurrentExactSeniorUCLFixtureCanPresentReportedGoals() {
        XCTAssertNotNil(UCLReportedScorePolicy.score(for: event(score: score), at: now))
        let boundary = UCLReportedScore(home: 2, away: 0, publisherUpdatedAt: stamp(now.addingTimeInterval(-1_800)))
        XCTAssertNotNil(UCLReportedScorePolicy.score(for: event(score: boundary, receiptOffset: -1_800), at: now))
        let foreign = [SportsFixtureCatalog.Participant(id: "football-data:86", name: "Real Madrid CF", role: "home"),
                       .init(id: "unreviewed:4", name: "Borussia Dortmund", role: "away")]
        for invalid in [event(score: score, receiptOffset: -1_801), event(score: score, receiptOffset: 301),
                        event(score: score, verified: false), event(score: score, status: .scheduled),
                        event(score: score, status: .cancelled), event(score: score, competition: "premier-league"),
                        event(score: score, gender: .women), event(score: score, ageGroup: "u19"),
                        event(score: score, participants: foreign), event(score: score, conflict: true),
                        event(score: score, id: "unrelated-route")] {
            XCTAssertNil(UCLReportedScorePolicy.score(for: invalid, at: now))
        }
    }

    func testExplicitZeroIsPreservedButPublisherTimeCannotBeFabricatedOrFutureDated() {
        let zero = UCLReportedScore(home: 0, away: 0, publisherUpdatedAt: stamp(publisherDate))
        XCTAssertEqual(UCLReportedScorePolicy.score(for: event(score: zero), at: now)?.home, 0)
        for published in [now.addingTimeInterval(301), now.addingTimeInterval(-4 * 86_400)] {
            let value = UCLReportedScore(home: 2, away: 0, publisherUpdatedAt: stamp(published))
            XCTAssertNil(UCLReportedScorePolicy.score(for: event(score: value), at: now))
        }
        XCTAssertFalse(UCLReportedScore(home: 2, away: 0, publisherUpdatedAt: "2026-10-29T17:00:00").isWellFormed)
    }

    func testHeldFallbackPreservesReportedFactsButCannotPresentThemAsFresh() throws {
        let old = snapshot([fixture(score: score)])
        let current = snapshot([], receipt: now.addingTimeInterval(60), unavailable: true)
        let retained = SportsFixtureCatalog.accepting(current, over: old)
        XCTAssertEqual(retained.fixtures.first?.reportedScore, score)
        XCTAssertEqual(retained.fixtures.first?.source.observedAt, stamp(now))
        let projected = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: retained, at: now).first)
        XCTAssertNil(UCLReportedScorePolicy.score(for: projected, at: now))
    }

    func testNewSuccessfulSameFixtureWithoutScoreClearsPriorOptionalGoals() throws {
        let old = snapshot([fixture(score: score)])
        let updatedAt = now.addingTimeInterval(60)
        let candidate = snapshot([fixture(receipt: updatedAt)], receipt: updatedAt)
        let accepted = SportsFixtureCatalog.accepting(candidate, over: old)
        XCTAssertEqual(accepted.fixtures.count, 1)
        XCTAssertNil(accepted.fixtures[0].reportedScore)
        let projected = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: updatedAt).first)
        XCTAssertNil(projected.sportsFixture?.reportedScore)
        XCTAssertNil(UCLReportedScorePolicy.score(for: projected, at: updatedAt))
        XCTAssertEqual(projected.sportsFixture?.status, .live)
    }

    func testMalformedCachedOptionalScoreDoesNotInvalidateExistingMetadata() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(event(score: score).sportsFixture))) as? [String: Any])
        json["reportedScore"] = ["home": "bad"]
        let restored = try JSONDecoder().decode(SportsFixtureMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.reportedScore)
        XCTAssertEqual(restored.fixtureID, event().sportsFixture?.fixtureID)
        XCTAssertEqual(restored.observedAt, publisherDate)
    }
}
