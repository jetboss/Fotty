import Foundation
import XCTest
@testable import Fotty

@MainActor
final class CricketMatchContextTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-29T17:21:44Z")!
    private let homeID = "icc:1:1188", awayID = "icc:1:10"

    // Exact normalized shape of the admitted ICC274661 receipt. This is a
    // deterministic parser fixture, not evidence of a current score or stream.
    private var score: CricketMatchContext {
        CricketMatchContext(innings: [
            .init(number: 1, teamID: homeID, runs: 221, wickets: 7, overs: "20.0"),
            .init(number: 2, teamID: awayID, runs: 88, wickets: 5, overs: "11.0")
        ], currentInnings: 2, phase: .inPlay,
           message: "Second Innings : Zimbabwe need 134 runs in 54 balls at 14.88 rpo", target: 222)
    }

    private func fixture(context: CricketMatchContext? = nil, format: CricketFixtureCatalog.Format = .t20,
                         status: CricketFixtureCatalog.Status = .live,
                         observedAt: Date? = nil, verification: CricketFixtureCatalog.Source.Verification = .verified) -> CricketFixtureCatalog.Fixture {
        .init(id: "icc:274661", start: stamp(now.addingTimeInterval(-3_600)), format: format, status: status,
              competitionId: "icc", competitionName: "Zimbabwe in UAE, 3 T20I Series, 2026",
              home: .init(id: homeID, name: "Afghanistan"), away: .init(id: awayID, name: "Zimbabwe"),
              source: .init(name: "ICC", url: "https://www.icc-cricket.com/matches/274661",
                            observedAt: stamp(observedAt ?? now), verification: verification), context: context)
    }

    private func snapshot(_ fixtures: [CricketFixtureCatalog.Fixture], checkedAt: Date? = nil,
                          unavailable: Bool = false) -> CricketFixtureCatalog.Snapshot {
        .init(schemaVersion: 1, complete: true, checkedAt: stamp(checkedAt ?? now), revision: "score-context-test",
              sourceStatus: unavailable ? .partial : .verified, fixtures: fixtures,
              coverage: [.init(competitionId: "icc", competitionName: "International cricket",
                  status: unavailable ? .unavailable : .covered, checkedAt: stamp(checkedAt ?? now),
                  fixtureCount: fixtures.count, expectedFixtureCount: nil, nextStart: nil)])
    }

    private func event(context: CricketMatchContext? = nil, receiptOffset: TimeInterval = 0,
                       verified: Bool = true, status: CricketFixtureCatalog.Status = .live,
                       format: CricketFixtureCatalog.Format = .t20, home: String? = "icc:1:1188",
                       away: String? = "icc:1:10", fixtureID: String = "icc:274661",
                       eventID: String? = nil, category: String = "cricket", conflict: Bool = false,
                       title: String = "Afghanistan vs Zimbabwe") -> EventReference {
        .init(id: eventID ?? CricketFixtureCatalog.fixtureIDPrefix + fixtureID, title: title,
            category: category, date: Int64(now.addingTimeInterval(-3_600).timeIntervalSince1970),
            poster: nil, popular: false, teams: .init(home: .init(name: "Afghanistan", badge: nil),
                away: .init(name: "Zimbabwe", badge: nil)), sources: [], hasCatalogIdentityConflict: conflict,
            cricketFixture: .init(fixtureID: fixtureID, competitionID: "icc", competitionName: "ICC",
                format: format, status: status, observedAt: now.addingTimeInterval(receiptOffset), verified: verified,
                context: context, homeTeamID: home, awayTeamID: away))
    }

    private func stamp(_ value: Date) -> String { ISO8601DateFormatter().string(from: value) }

    func testPublishedTestOrdinalAndEndAreOptionalAndRoundTripWithoutInventingDailyStart() throws {
        var context = score
        context.day = 4; context.session = 2; context.matchOrdinal = 3
        context.matchEndsAt = stamp(now.addingTimeInterval(86_400))
        let testEvent = event(context: context, format: .test)
        XCTAssertEqual(CricketMatchContextPolicy.context(for: testEvent, at: now)?.matchOrdinal, 3)
        XCTAssertEqual(CricketMatchContextPolicy.context(for: testEvent, at: now)?.day, 4)
        XCTAssertEqual(testEvent.kickoffDate, now.addingTimeInterval(-3_600))
        let roundTrip = try JSONDecoder().decode(CricketMatchContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(roundTrip, context)
        XCTAssertNil(CricketMatchContextPolicy.context(for: event(context: context, format: .t20), at: now))
        for invalidEnd in [stamp(now.addingTimeInterval(-7_200)), stamp(now.addingTimeInterval(7 * 86_400)),
                           "2026-10-30", "2026-10-30T15:30:00+00:00"] {
            var invalid = context; invalid.matchEndsAt = invalidEnd
            XCTAssertNil(CricketMatchContextPolicy.context(for: event(context: invalid, format: .test), at: now))
        }
        for ordinal in [0, 100] {
            var invalid = context; invalid.matchOrdinal = ordinal
            XCTAssertNil(invalid.validated(format: .test, homeTeamID: homeID, awayTeamID: awayID))
        }
        var legacy = context; legacy.matchOrdinal = nil; legacy.matchEndsAt = nil
        XCTAssertNotNil(CricketMatchContextPolicy.context(for: event(context: legacy, format: .test), at: now))
    }

    func testTestDayIdentityChangesOnPublishedDayButNotLunchOrScoreRefresh() {
        var dayThree = score; dayThree.day = 3; dayThree.matchOrdinal = 3
        dayThree.matchEndsAt = stamp(now.addingTimeInterval(86_400))
        var lunch = dayThree; lunch.phase = .lunch
        var dayFour = dayThree; dayFour.day = 4
        let old = event(context: dayThree, format: .test).cricketFixture?.broadcastDayIdentity
        XCTAssertEqual(old, event(context: lunch, format: .test).cricketFixture?.broadcastDayIdentity)
        XCTAssertNotEqual(old, event(context: dayFour, format: .test).cricketFixture?.broadcastDayIdentity)
        XCTAssertNil(event(context: score, format: .t20).cricketFixture?.broadcastDayIdentity)
    }

    func testRetainedPresentationUsesCurrentScoreInsteadOfFrozenPlayerEvent() throws {
        let old = event(context: score)
        let newer = CricketMatchContext(innings: [
            .init(number: 1, teamID: homeID, runs: 221, wickets: 7, overs: "20.0"),
            .init(number: 2, teamID: awayID, runs: 134, wickets: 5, overs: "15.0")
        ], currentInnings: 2, phase: .inPlay, target: 222)
        let current = event(context: newer)
        let selected = try XCTUnwrap(CurrentSportsMatchContextPolicy.event(for: old, in: [current], at: now))
        XCTAssertEqual(selected.cricketFixture?.context, newer)
        XCTAssertNotEqual(selected.cricketFixture?.context, old.cricketFixture?.context)
        XCTAssertNil(CurrentSportsMatchContextPolicy.event(for: old, in: [], at: now))
        XCTAssertNil(CurrentSportsMatchContextPolicy.event(for: old, in: [event(context: newer, conflict: true)], at: now))
        XCTAssertNil(CurrentSportsMatchContextPolicy.event(for: old, in: [event(context: nil)], at: now),
                     "A new scoreless receipt must not replay the old score")
    }

    func testFinishedCricketContextRemainsReadableWithoutRestoringPlayback() async throws {
        var final = score; final.phase = .finished
        let manifest = snapshot([fixture(context: final, status: .finished)])
        let model = MatchListViewModel(refreshCricket: { manifest }, now: { self.now })
        await model.refresh()

        XCTAssertTrue(model.playbackCatalog.isEmpty, "Finished scorecards cannot become playable listings")
        let current = try XCTUnwrap(CurrentSportsMatchContextPolicy.event(for: event(context: score),
            in: model.matchContextCatalog, at: now))
        XCTAssertEqual(current.cricketFixture?.status, .finished)
        XCTAssertEqual(current.cricketFixture?.context, final)
        XCTAssertTrue(current.sources?.isEmpty == true)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: current, in: model.playbackCatalog, at: now))
        XCTAssertTrue(model.playbackCatalog.isEmpty, "Reading context must be side-effect free")

        // Even an unreconciled active row with that same accepted identity must
        // not shadow its current result, or be changed by the read-only union.
        let old = event(context: score)
        model.matches = [old]
        XCTAssertEqual(model.matchContextCatalog.count, 1)
        XCTAssertEqual(model.matchContextCatalog.first?.cricketFixture?.status, .finished)
        XCTAssertEqual(model.playbackCatalog.first?.cricketFixture?.status, .live)
    }

    func testCurrentCricketContextRequiresAcceptedTypedIdentityAndMatchingSquadFormatAndTeams() {
        let current = event(context: score)
        let untyped = EventReference(id: "untyped-cricket", title: current.title, category: "cricket", date: current.date,
            poster: nil, popular: false, teams: current.teams, sources: [])
        let women = EventReference(id: "women-cricket", title: "Afghanistan Women vs Zimbabwe Women", category: "cricket",
            date: current.date, poster: nil, popular: false, teams: current.teams, sources: [])
        for previous in [untyped, women, event(context: score, format: .odi),
                         event(context: score, home: awayID, away: homeID), event(context: score, home: nil),
                         event(context: score, title: "Afghanistan U19 vs Zimbabwe U19"),
                         event(context: score, fixtureID: "icc:123")] {
            XCTAssertNil(CurrentSportsMatchContextPolicy.event(for: previous, in: [current], at: now))
        }
        XCTAssertNotNil(CurrentSportsMatchContextPolicy.event(for: event(context: nil), in: [current], at: now),
                        "An accepted fixture may gain a first current score without borrowing a different identity")
    }

    func testAdmittedOptionalContextProjectsAndSurvivesNativeCacheRoundTrip() throws {
        let data = try JSONEncoder().encode(snapshot([fixture(context: score)]))
        let accepted = try CricketFixtureCatalog.validatedSnapshot(from: data, now: now)
        XCTAssertEqual(accepted.fixtures.first?.context, score)
        let projected = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: accepted, at: now).first)
        XCTAssertEqual(projected.cricketFixture?.homeTeamID, homeID)
        XCTAssertEqual(projected.cricketFixture?.awayTeamID, awayID)
        XCTAssertEqual(CricketMatchContextPolicy.context(for: projected, at: now), score)
        let restored = try JSONDecoder().decode(EventReference.self, from: JSONEncoder().encode(projected))
        XCTAssertEqual(restored.cricketFixture, projected.cricketFixture)
        XCTAssertEqual(restored.cricketFixture?.observedAt, now)
        XCTAssertTrue(restored.sources?.isEmpty == true, "Score context must not create a broadcast")
    }

    func testLegacyFixtureAndMetadataDecodeWithoutContextOrNewIdentityFields() throws {
        let legacyFixture = fixture()
        XCTAssertNil(try JSONDecoder().decode(CricketFixtureCatalog.Fixture.self,
            from: JSONEncoder().encode(legacyFixture)).context)
        let metadata = try XCTUnwrap(event().cricketFixture)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        for key in ["context", "homeTeamID", "awayTeamID"] { json.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(CricketFixtureMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.context)
        XCTAssertNil(old.homeTeamID)
        XCTAssertNil(old.awayTeamID)
        XCTAssertEqual(old.status, .live)
    }

    func testMalformedOptionalContextIsOmittedWithoutRejectingOrChangingFixture() throws {
        let encoded = try JSONEncoder().encode(snapshot([fixture(context: score)]))
        let baseline = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let fixtureRows = try XCTUnwrap(baseline["fixtures"] as? [[String: Any]])
        let valid = try XCTUnwrap(fixtureRows.first?["context"] as? [String: Any])
        var missingRuns = valid
        var innings = try XCTUnwrap(valid["innings"] as? [[String: Any]])
        innings[0].removeValue(forKey: "runs"); missingRuns["innings"] = innings
        var wrongTeam = valid; innings = try XCTUnwrap(valid["innings"] as? [[String: Any]])
        innings[0]["teamID"] = "icc:1:other"; wrongTeam["innings"] = innings
        var unknownPhase = valid; unknownPhase["phase"] = "invented-phase"
        var invalidOvers = valid; innings = try XCTUnwrap(valid["innings"] as? [[String: Any]])
        innings[0]["overs"] = "11.6"; invalidOvers["innings"] = innings
        var duplicate = valid; innings = try XCTUnwrap(valid["innings"] as? [[String: Any]])
        innings[1]["number"] = 1; duplicate["innings"] = innings
        for context: Any in [missingRuns, wrongTeam, unknownPhase, invalidOvers, duplicate, NSNull(), "bad-context"] {
            var body = baseline, row = fixtureRows[0]
            row["context"] = context; body["fixtures"] = [row]
            let accepted = try CricketFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: body), now: now)
            XCTAssertEqual(accepted.fixtures.count, 1)
            XCTAssertNil(accepted.fixtures[0].context)
            XCTAssertEqual(accepted.fixtures[0].id, "icc:274661")
            XCTAssertEqual(accepted.fixtures[0].status, .live)
            XCTAssertEqual(accepted.fixtures[0].source.observedAt, stamp(now))
        }
    }

    func testOnlyFreshVerifiedExactFixtureContextIsPresented() {
        XCTAssertNotNil(CricketMatchContextPolicy.context(for: event(context: score), at: now))
        XCTAssertNotNil(CricketMatchContextPolicy.context(for: event(context: score, receiptOffset: -600), at: now))
        for invalid in [event(context: score, receiptOffset: -601), event(context: score, receiptOffset: 301),
                        event(context: score, verified: false), event(context: score, home: nil),
                        event(context: score, away: nil), event(context: score, home: "icc:1:another"),
                        event(context: score, fixtureID: "unsupported:274661"),
                        event(context: score, eventID: "unrelated-provider-event"),
                        event(context: score, category: "football"), event(context: score, conflict: true),
                        event(context: score, title: "Willow Cricket"), event(context: score, format: .unknown)] {
            XCTAssertNil(CricketMatchContextPolicy.context(for: invalid, at: now))
        }
    }

    func testHeldFallbackRetainsScoreFactsAndOriginalReceiptButHidesContext() throws {
        let original = snapshot([fixture(context: score)])
        let unavailable = snapshot([], checkedAt: now.addingTimeInterval(60), unavailable: true)
        let retained = CricketFixtureCatalog.accepting(unavailable, over: original)
        XCTAssertEqual(retained.fixtures.first?.context, score)
        XCTAssertEqual(retained.fixtures.first?.source.observedAt, stamp(now))
        XCTAssertEqual(retained.fixtures.first?.source.verification, .held)
        let projected = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: retained, at: now).first)
        XCTAssertFalse(try XCTUnwrap(projected.cricketFixture).verified)
        XCTAssertNil(CricketMatchContextPolicy.context(for: projected, at: now))
    }

    func testFreshSameFixtureWithoutScoresClearsContextInsteadOfRenewingOldScores() throws {
        let original = snapshot([fixture(context: score)])
        let checkedAt = now.addingTimeInterval(60)
        let current = snapshot([fixture(observedAt: checkedAt)], checkedAt: checkedAt)
        let accepted = CricketFixtureCatalog.accepting(current, over: original)
        XCTAssertNil(accepted.fixtures.first?.context)
        let previousEvent = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: original, at: now).first)
        let updated = try XCTUnwrap(CricketFixtureCatalog.merging(into: [previousEvent], snapshot: accepted, at: checkedAt).first)
        XCTAssertEqual(updated.id, previousEvent.id)
        XCTAssertEqual(updated.cricketFixture?.observedAt, checkedAt)
        XCTAssertEqual(updated.cricketFixture?.status, .live)
        XCTAssertNil(updated.cricketFixture?.context)
        XCTAssertNil(CricketMatchContextPolicy.context(for: updated, at: checkedAt))
    }

    func testMalformedCachedContextCannotInvalidateItsExistingFixtureMetadata() throws {
        let metadata = try XCTUnwrap(event(context: score).cricketFixture)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        json["context"] = ["innings": "bad-array"]
        let decoded = try JSONDecoder().decode(CricketFixtureMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.context)
        XCTAssertEqual(decoded.fixtureID, metadata.fixtureID)
        XCTAssertEqual(decoded.observedAt, metadata.observedAt)
        XCTAssertEqual(decoded.status, .live)
    }

    func testTestInningsRemainDistinctWhenTheSameTeamBatsAgain() {
        let test = CricketMatchContext(innings: [
            .init(number: 1, teamID: homeID, runs: 329, wickets: 10, overs: "82.3"),
            .init(number: 2, teamID: awayID, runs: 429, wickets: 10, overs: "125.1"),
            .init(number: 3, teamID: homeID, runs: 140, wickets: 4, overs: "47.0")
        ], currentInnings: 3, day: 3, session: 3, phase: .stumps,
           message: "Stumps, Day 3 - South Africa lead by 40 runs")
        XCTAssertEqual(test.validated(format: .test, homeTeamID: homeID, awayTeamID: awayID)?.innings.count, 3)
        let current = CricketMatchContextPolicy.context(for: event(context: test, format: .test), at: now)
        XCTAssertEqual(current?.phase, .stumps)
        XCTAssertEqual(current?.innings.map(\.number), [1, 2, 3])
        XCTAssertNil(test.validated(format: .t20, homeTeamID: homeID, awayTeamID: awayID))
    }

    func testOversAreBallNotationAndMissingScoresNeverBecomeZero() {
        for overs in ["11.5", "20.0", "20", "0.0"] {
            let context = CricketMatchContext(innings: [.init(number: 1, teamID: homeID, runs: 0, wickets: 0, overs: overs)])
            XCTAssertNotNil(context.validated(format: .t20, homeTeamID: homeID, awayTeamID: awayID), overs)
        }
        for overs in ["11.6", "20.1", "21.0", "-1.0", "11.25", "NaN", "", " 11.0"] {
            let context = CricketMatchContext(innings: [.init(number: 1, teamID: homeID, runs: 0, wickets: 0, overs: overs)])
            XCTAssertNil(context.validated(format: .t20, homeTeamID: homeID, awayTeamID: awayID), overs)
        }
        XCTAssertNil(CricketMatchContext(innings: []).validated(format: .t20, homeTeamID: homeID, awayTeamID: awayID))
        XCTAssertThrowsError(try JSONDecoder().decode(CricketMatchContext.self,
            from: Data(#"{"innings":[{"number":1,"teamID":"icc:1:1188","wickets":0}]}"#.utf8)))
    }

    func testContextNeverPromotesScheduledCancelledOrConflictingTerminalStatus() {
        for status: CricketFixtureCatalog.Status in [.scheduled, .cancelled, .postponed, .unknown, .finished] {
            XCTAssertNil(CricketMatchContextPolicy.context(for: event(context: score, status: status), at: now))
        }
        var final = score; final.phase = .finished
        XCTAssertNotNil(CricketMatchContextPolicy.context(for: event(context: final, status: .finished), at: now))
        XCTAssertNil(CricketMatchContextPolicy.context(for: event(context: final, status: .live), at: now))
        XCTAssertEqual(event(context: score, status: .scheduled).cricketFixture?.status, .scheduled)
    }

    func testForeignBattingTeamInvalidTargetAndUnsafeMessageAreOmitted() {
        var wrongBatting = score; wrongBatting.battingTeamID = homeID
        var sameBowling = score; sameBowling.battingTeamID = awayID; sameBowling.bowlingTeamID = awayID
        var missingCurrent = score; missingCurrent.currentInnings = nil
        var unsafe = score; unsafe.message = "<script>example</script>"
        var extraDay = score; extraDay.day = 1
        var testOnlyPhase = score; testOnlyPhase.phase = .tea
        var previousInnings = score; previousInnings.currentInnings = 1
        let missingFirst = CricketMatchContext(innings: [.init(number: 2, teamID: awayID, runs: 1, wickets: 0)])
        let repeatedLimitedTeam = CricketMatchContext(innings: [
            .init(number: 1, teamID: homeID, runs: 1, wickets: 0), .init(number: 2, teamID: homeID, runs: 2, wickets: 0)])
        for context in [wrongBatting, sameBowling, missingCurrent, unsafe, extraDay, testOnlyPhase,
                        previousInnings, missingFirst, repeatedLimitedTeam] {
            XCTAssertNil(context.validated(format: .t20, homeTeamID: homeID, awayTeamID: awayID))
        }
    }
}
