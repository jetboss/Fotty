import Foundation
import XCTest
@testable import Fotty

final class SportsWidgetSnapshotTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func match(phase: SportsWidgetSnapshot.Phase = .live, statusOffset: TimeInterval = 0,
                       scoreOffset: TimeInterval = 0, badge: String? = nil,
                       category: String = "football") -> SportsWidgetSnapshot.Match {
        .init(id: "match/one", homeName: "Liverpool", awayName: "Chelsea", category: category, competition: "Premier League",
            kickoff: now.addingTimeInterval(-900), phase: phase, statusObservedAt: now.addingTimeInterval(statusOffset),
            scoreText: "1–1", scoreObservedAt: now.addingTimeInterval(scoreOffset), homeBadgeFile: badge, awayBadgeFile: nil)
    }
    func testRoundTripAndSourcesFPLAreNotPartOfSnapshot() throws {
        let snapshot = SportsWidgetSnapshot(createdAt: now, matches: [match()])
        let data = try XCTUnwrap(snapshot.validatedData())
        XCTAssertEqual(SportsWidgetSnapshot.decode(data), snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in ["sources", "streamURL", "headers", "cookies", "fpl", "managerID"] { XCTAssertFalse(text.contains(forbidden)) }
    }
    func testSharedRowValidationDoesNotRelaxWholeSnapshotDecoding() throws {
        XCTAssertTrue(SportsWidgetSnapshot.isValidMatch(match(), createdAt: now))
        let unsupported = match(category: "darts")
        XCTAssertFalse(SportsWidgetSnapshot.isValidMatch(unsupported, createdAt: now))
        let snapshot = SportsWidgetSnapshot(createdAt: now, matches: [unsupported])
        XCTAssertNil(snapshot.validatedData())
        XCTAssertNil(SportsWidgetSnapshot.decode(try JSONEncoder().encode(snapshot)))
    }
    func testElapsedScheduledStartNeverBecomesLive() {
        XCTAssertEqual(match(phase: .scheduled).effectivePhase(at: now), .unconfirmed)
        XCTAssertNil(match(phase: .scheduled).currentScore(at: now))
    }
    func testStaleLiveStatusAndScoreLoseCurrentClaimsSeparately() {
        XCTAssertEqual(match(statusOffset: -1801).effectivePhase(at: now), .unconfirmed)
        XCTAssertNil(match(statusOffset: -1801).currentScore(at: now))
        XCTAssertEqual(match(scoreOffset: -121).effectivePhase(at: now), .live)
        XCTAssertNil(match(scoreOffset: -121).currentScore(at: now))
        XCTAssertEqual(match().currentScore(at: now), "1–1")
    }
    func testSnapshotExpiresAndReceiptIsNotRenewedByDecode() throws {
        let snapshot = SportsWidgetSnapshot(createdAt: now, matches: [match()])
        let decoded = try XCTUnwrap(SportsWidgetSnapshot.decode(try XCTUnwrap(snapshot.validatedData())))
        XCTAssertTrue(decoded.isFresh(at: now.addingTimeInterval(1800)))
        XCTAssertFalse(decoded.isFresh(at: now.addingTimeInterval(1801)))
        XCTAssertEqual(decoded.createdAt, now)
        XCTAssertTrue(decoded.expiryDates.contains(now.addingTimeInterval(121)))
        XCTAssertTrue(decoded.expiryDates.contains(now.addingTimeInterval(1801)))
    }
    func testBadgesCannotEscapeSharedSportsDirectory() {
        for path in ["../FPL.png", "folder/logo.png", "https://example.test/logo.png", ".hidden.png", "a.svg", "a.png?x"] {
            XCTAssertFalse(SportsWidgetSnapshot.validBadgeFile(path), path)
            XCTAssertNil(SportsWidgetSnapshot(createdAt: now, matches: [match(badge: path)]).validatedData())
        }
        XCTAssertTrue(SportsWidgetSnapshot.validBadgeFile("liverpool-123.png"))
    }
    func testUnknownPayloadFieldsDuplicateRowsAndOversizeRejected() throws {
        let good = try XCTUnwrap(SportsWidgetSnapshot(createdAt: now, matches: [match()]).validatedData())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        json["fpl"] = ["managerID": 123]
        XCTAssertNil(SportsWidgetSnapshot.decode(try JSONSerialization.data(withJSONObject: json)))
        XCTAssertNil(SportsWidgetSnapshot(createdAt: now, matches: [match(), match()]).validatedData())
        XCTAssertNil(SportsWidgetSnapshot.decode(Data(repeating: 0, count: 32769)))
    }
    func testDeepLinkIsContextOnlyAndEncodesOpaqueIDAsOnePathComponent() {
        XCTAssertEqual(match().deepLink?.absoluteString, "fotty://matchday/match%2Fone")
        XCTAssertFalse(match().deepLink?.absoluteString.contains("Watch") == true)
    }
}
