import Foundation
import XCTest
@testable import Fotty

@MainActor
final class SportsHandoffTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(id: String = "fixture", home: String = "Liverpool", away: String = "Chelsea",
                       category: String = "football", offset: TimeInterval = -900,
                       conflict: Bool = false, title: String? = nil, competition: String? = nil) -> EventReference {
        EventReference(id: id, title: title ?? "\(home) vs \(away)", category: category,
            date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970), poster: "https://example.test/poster",
            popular: false, teams: .init(home: .init(name: home, badge: "https://example.test/home"),
                away: .init(name: away, badge: "https://example.test/away")), hasCatalogIdentityConflict: conflict,
            competitionID: competition)
    }

    func testTransportRoundTripContainsNoSourceArtworkOrFPLData() throws {
        let identity = try SportsHandoffIdentity.make(event: event(), now: now)
        let payload = try identity.encodedPayload(now: now)
        XCTAssertEqual(try SportsHandoffIdentity.decode(payload: payload, now: now), identity)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        for key in ["sources", "streamURL", "headers", "cookies", "poster", "badge", "fpl", "managerID"] {
            XCTAssertNil(json[key], key)
        }
        let text = try XCTUnwrap(String(data: payload, encoding: .utf8))
        XCTAssertFalse(text.contains("private-route"))
        XCTAssertFalse(text.contains("example.test"))
    }

    func testLocalDartsInterestDoesNotExpandHandoffWireContract() {
        XCTAssertTrue(SportsInterestPreferences.supportedIDs.contains("darts"))
        XCTAssertFalse(SportsHandoffIdentity.supportedSports.contains("darts"))
        XCTAssertThrowsError(try SportsHandoffIdentity.make(event: event(category: "darts"), now: now))
    }

    func testPayloadExpiresAndRejectsFutureOrExtendedLifetime() throws {
        let payload = try SportsHandoffIdentity.make(event: event(), now: now).encodedPayload(now: now)
        XCTAssertNoThrow(try SportsHandoffIdentity.decode(payload: payload, now: now.addingTimeInterval(599)))
        XCTAssertThrowsError(try SportsHandoffIdentity.decode(payload: payload, now: now.addingTimeInterval(600)))
        for (field, value) in [("issuedAt", now.addingTimeInterval(31).timeIntervalSinceReferenceDate),
                               ("expiresAt", now.addingTimeInterval(601).timeIntervalSinceReferenceDate)] {
            XCTAssertThrowsError(try SportsHandoffIdentity.decode(payload: modified(payload, field: field, value: value), now: now))
        }
    }

    func testMalformedOversizedUnknownAndURLFieldsFailClosed() throws {
        let payload = try SportsHandoffIdentity.make(event: event(), now: now).encodedPayload(now: now)
        XCTAssertThrowsError(try SportsHandoffIdentity.decode(payload: Data("[]".utf8), now: now))
        XCTAssertThrowsError(try SportsHandoffIdentity.decode(payload: Data(repeating: 0, count: 8193), now: now))
        for (key, value) in [("version", 2 as Any), ("managerID", 123), ("streamURL", "https://private.test/live"),
                              ("category", "fpl"), ("homeName", "https://private.test/name"),
                              ("eventID", String(repeating: "x", count: 201)), ("awayName", "Chelsea\n")] {
            XCTAssertThrowsError(try SportsHandoffIdentity.decode(payload: modified(payload, field: key, value: value), now: now), key)
        }
    }

    func testReceiverRequiresCurrentScheduleReceipt() throws {
        let identity = try SportsHandoffIdentity.make(event: event(), now: now)
        let current = EventReference(id: "fixture", title: "Liverpool vs Chelsea", category: "football",
            date: event().date, poster: nil, popular: nil, teams: event().teams)
        XCTAssertEqual(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: [current], scheduleCheckedAt: now, now: now)?.id, current.id)
        // A schedule receipt is current for its 30 min status freshness, with
        // 5 min of clock skew; outside that window the handoff is refused.
        XCTAssertNotNil(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: [current],
            scheduleCheckedAt: now.addingTimeInterval(-ScheduleReceiptPolicy.freshness), now: now))
        XCTAssertNotNil(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: [current],
            scheduleCheckedAt: now.addingTimeInterval(ScheduleReceiptPolicy.clockSkew), now: now))
        for receipt in [now.addingTimeInterval(-ScheduleReceiptPolicy.freshness - 1),
                        now.addingTimeInterval(ScheduleReceiptPolicy.clockSkew + 1)] {
            XCTAssertNil(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: [current], scheduleCheckedAt: receipt, now: now))
        }
        XCTAssertNil(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: [], scheduleCheckedAt: now, now: now))
    }

    func testReceiverCannotFallThroughContradictoryIDOrChooseAmbiguousNames() throws {
        let identity = try SportsHandoffIdentity.make(event: event(), now: now)
        for catalog in [[event(away: "Arsenal"), event(id: "different")],
                        [event(category: "basketball")], [event(offset: 86400)], [event(conflict: true)],
                        [event(id: "first"), event(id: "second")], [event(home: "Liverpool U21", away: "Chelsea U21")]] {
            XCTAssertNil(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: catalog, scheduleCheckedAt: now, now: now))
        }
    }

    func testCompetitionAndCricketSquadDoNotDisappearOnReceiver() throws {
        let football = try SportsHandoffIdentity.make(event: event(competition: "premier-league"), now: now)
        XCTAssertNil(SportsHandoffMatchPolicy.confirmationEvent(for: football, in: [event(competition: "fa-cup")], scheduleCheckedAt: now, now: now))
        XCTAssertNil(SportsHandoffMatchPolicy.confirmationEvent(for: football, in: [event()], scheduleCheckedAt: now, now: now))
        let women = event(home: "New Zealand", away: "South Africa", category: "cricket", title: "New Zealand vs South Africa Women")
        let identity = try SportsHandoffIdentity.make(event: women, now: now)
        XCTAssertNil(SportsHandoffMatchPolicy.confirmationEvent(for: identity,
            in: [event(home: "New Zealand", away: "South Africa", category: "cricket")], scheduleCheckedAt: now, now: now))
        XCTAssertEqual(SportsHandoffMatchPolicy.confirmationEvent(for: identity, in: [women], scheduleCheckedAt: now, now: now)?.id, women.id)
    }

    func testUndatedMatchAndConflictingPublisherAreRejected() {
        let undated = EventReference(id: "fixture", title: "Liverpool vs Chelsea", category: "football", date: nil,
            poster: nil, popular: nil, teams: event().teams)
        XCTAssertThrowsError(try SportsHandoffIdentity.make(event: undated, now: now))
        XCTAssertThrowsError(try SportsHandoffIdentity.make(event: event(conflict: true), now: now))
    }

    func testPublisherIsDormantUntilExplicitOfferAndStopOrExpiryClears() throws {
        let client = RecordingPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        XCTAssertFalse(publisher.isOffering)
        XCTAssertEqual(client.published.count, 0)
        try publisher.offer(event: event(), now: now)
        XCTAssertTrue(publisher.isOffering)
        XCTAssertEqual(client.published.count, 1)
        publisher.expireIfNeeded(now: now.addingTimeInterval(600))
        XCTAssertFalse(publisher.isOffering)
        try publisher.offer(event: event(), now: now)
        publisher.stop()
        XCTAssertNil(publisher.offeredIdentity)
        XCTAssertGreaterThanOrEqual(client.invalidations, 3)
    }

    func testActivityAcceptsOnlyOneWhitelistPayloadAndMatchingType() throws {
        let payload = try SportsHandoffIdentity.make(event: event(), now: now).encodedPayload(now: now)
        let activity = NSUserActivity(activityType: SportsHandoffIdentity.activityType)
        activity.userInfo = [SportsHandoffIdentity.payloadKey: payload]
        XCTAssertNoThrow(try SportsHandoffIdentity.decode(activity: activity, now: now))
        activity.userInfo?["fpl"] = 123
        XCTAssertThrowsError(try SportsHandoffIdentity.decode(activity: activity, now: now))
        let wrong = NSUserActivity(activityType: "com.jelani.Fotty.fpl")
        wrong.userInfo = [SportsHandoffIdentity.payloadKey: payload]
        XCTAssertThrowsError(try SportsHandoffIdentity.decode(activity: wrong, now: now))
    }

    private func modified(_ payload: Data, field: String, value: Any) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        object[field] = value
        return try JSONSerialization.data(withJSONObject: object)
    }

    private final class RecordingPublisher: SportsHandoffActivityPublishing {
        var published: [SportsHandoffIdentity] = []
        var invalidations = 0
        func publish(identity: SportsHandoffIdentity, payload: Data) { published.append(identity) }
        func invalidate() { invalidations += 1 }
    }
}
