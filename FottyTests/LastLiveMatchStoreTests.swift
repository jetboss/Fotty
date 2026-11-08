import Foundation
import XCTest
@testable import Fotty

@MainActor
final class LastLiveMatchStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var domains: [String] = []

    override func tearDown() {
        for domain in domains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        domains = []
        super.tearDown()
    }

    private func defaults(enabled: Bool = true) throws -> UserDefaults {
        let domain = "Fotty.LastLiveMatchTests.\(UUID().uuidString)"
        domains.append(domain)
        let value = try XCTUnwrap(UserDefaults(suiteName: domain))
        if enabled { value.set(true, forKey: LastLiveMatchStore.enablementKey) }
        return value
    }

    private func event(id: String = "fixture", home: String = "Liverpool", away: String = "Chelsea",
                       category: String = "football", offset: TimeInterval = -900,
                       competition: String? = "premier-league", title: String? = nil,
                       conflict: Bool = false, sources: [NexusASource]? = [.init(source: "admin", id: "private-route")],
                       cricket: CricketFixtureMetadata? = nil, sports: SportsFixtureMetadata? = nil) -> EventReference {
        .init(id: id, title: title ?? "\(home) vs \(away)", category: category,
              date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970),
              poster: "https://example.test/private-artwork", popular: false,
              teams: .init(home: .init(name: home, badge: "https://example.test/home-badge"),
                           away: .init(name: away, badge: "https://example.test/away-badge")),
              sources: sources, hasCatalogIdentityConflict: conflict, cricketFixture: cricket,
              sportsFixture: sports, competitionID: competition)
    }

    private func cricket(status: CricketFixtureCatalog.Status = .live, receiptOffset: TimeInterval = 0,
                         verified: Bool = true, format: CricketFixtureCatalog.Format = .t20,
                         label: String = "West Indies vs England · 1st T20I") -> EventReference {
        let metadata = CricketFixtureMetadata(fixtureID: "series-game-one", competitionID: "icc",
            competitionName: "ICC", format: format, status: status,
            observedAt: now.addingTimeInterval(receiptOffset), verified: verified,
            providerObservedAt: now)
        return event(id: CricketFixtureCatalog.fixtureIDPrefix + metadata.fixtureID,
            home: "West Indies", away: "England", category: "cricket", competition: "icc", title: label, cricket: metadata)
    }

    private func baseball(status: SportsFixtureCatalog.Status = .live, receiptOffset: TimeInterval = 0,
                          verified: Bool = true, gender: SportsFixtureCatalog.Squad.Gender = .men,
                          ageGroup: String = "senior", awayID: String = "brewers",
                          eventKind: SportsFixtureCatalog.EventKind = .match, sport: String = "baseball") -> EventReference {
        let id = SportsFixtureCatalog.fixtureIDPrefix + "mlb:game-one"
        let metadata = SportsFixtureMetadata(fixtureID: id, sport: sport, competitionID: "mlb",
            competitionName: "MLB", eventKind: eventKind, title: "Mets vs Brewers",
            participants: [.init(id: "mets", name: "Mets", role: "home"),
                           .init(id: awayID, name: "Brewers", role: "away")],
            squad: .init(gender: gender, ageGroup: ageGroup), status: status,
            observedAt: now.addingTimeInterval(receiptOffset), verified: verified,
            providerObservedAt: now)
        return event(id: id, home: "Mets", away: "Brewers", category: "baseball", competition: "mlb", sports: metadata)
    }

    @discardableResult
    private func confirm(_ event: EventReference, in store: LastLiveMatchStore) throws -> LastLiveMatchStore.PlaybackTicket {
        let ticket = try XCTUnwrap(store.beginPlayback(of: event))
        XCTAssertTrue(store.confirmDecodedPlayback(ticket))
        return ticket
    }

    func testDisabledByDefaultAndBeginningAloneNeverPersists() throws {
        let preferences = try defaults(enabled: false)
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        XCTAssertFalse(store.isEnabled)
        XCTAssertNil(store.beginPlayback(of: event()))
        XCTAssertNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
        store.isEnabled = true
        XCTAssertNotNil(store.beginPlayback(of: event()))
        XCTAssertNil(store.record)
        XCTAssertNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
    }

    func testDecodedConfirmationPersistsOneIdentityAndSurvivesColdLaunch() throws {
        let preferences = try defaults()
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        let ticket = try confirm(event(), in: store)
        XCTAssertFalse(store.confirmDecodedPlayback(ticket), "A consumed callback must not rewrite history")
        let relaunched = LastLiveMatchStore(defaults: preferences, now: { self.now.addingTimeInterval(60) })
        XCTAssertEqual(relaunched.record, store.record)
        XCTAssertEqual(relaunched.eligibleEvent(in: [event()], status: { _ in .inPlay })?.id, "fixture")
    }

    func testPersistedPayloadContainsNoTransportArtworkStatusOrOtherPrivateState() throws {
        let preferences = try defaults()
        preferences.set("untouched", forKey: "unrelated.preference")
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        try confirm(baseball(), in: store)
        let data = try XCTUnwrap(preferences.data(forKey: LastLiveMatchStore.storageKey))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in ["private-route", "example.test", "sources", "poster", "badge", "headers",
                          "cookie", "status", "observedAt", "providerEventIDs", "managerID", "fpl"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        XCTAssertLessThanOrEqual(data.count, LastLiveMatchRecord.maximumPayloadBytes)
        XCTAssertEqual(preferences.string(forKey: "unrelated.preference"), "untouched")
    }

    func testReplacementRejectsLateOwnerAndStoresOnlyConfirmedReplacement() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        let first = try XCTUnwrap(store.beginPlayback(of: event()))
        let second = try XCTUnwrap(store.beginPlayback(of: event(id: "next", away: "Arsenal")))
        store.cancelPlayback(first)
        XCTAssertFalse(store.confirmDecodedPlayback(first))
        XCTAssertTrue(store.confirmDecodedPlayback(second))
        XCTAssertEqual(store.record?.eventID, "next")
    }

    func testCancelledUnconfirmedReplacementDoesNotEraseLastSuccessfulMatch() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(event(), in: store)
        let replacement = try XCTUnwrap(store.beginPlayback(of: event(id: "next", away: "Arsenal")))
        store.cancelPlayback(replacement)
        XCTAssertFalse(store.confirmDecodedPlayback(replacement))
        XCTAssertEqual(store.record?.eventID, "fixture")
    }

    func testClearAndOptOutRevokePendingCallbacksAndRemoveDurableRecord() throws {
        let preferences = try defaults()
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        let first = try confirm(event(), in: store)
        store.clear()
        XCTAssertFalse(store.confirmDecodedPlayback(first))
        let second = try XCTUnwrap(store.beginPlayback(of: event()))
        store.clear()
        XCTAssertFalse(store.confirmDecodedPlayback(second))
        let third = try XCTUnwrap(store.beginPlayback(of: event()))
        store.isEnabled = false
        XCTAssertFalse(store.confirmDecodedPlayback(third))
        XCTAssertNil(store.record)
        XCTAssertNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
        XCTAssertFalse(LastLiveMatchStore(defaults: preferences, now: { self.now }).isEnabled)
    }

    func testRetentionDoesNotTurnTheStoredIdentityIntoLiveAuthority() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(event(), in: store)
        XCTAssertNil(store.eligibleEvent(in: [event()]), "Elapsed kickoff is not LIVE")
        XCTAssertNil(store.eligibleEvent(in: [event()], status: { _ in .scheduled }))
        XCTAssertNil(store.eligibleEvent(in: [], status: { _ in .inPlay }), "Absence cannot fall back to a saved event")
        XCTAssertNotNil(store.record, "Temporary absence need not erase the identity")
    }

    func testExpiryAndFutureClockCorruptionClearOnReload() throws {
        let preferences = try defaults()
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        try confirm(event(), in: store)
        XCTAssertNotNil(LastLiveMatchStore(defaults: preferences, now: { self.now.addingTimeInterval(LastLiveMatchRecord.lifetime - 1) }).record)
        XCTAssertNil(LastLiveMatchStore(defaults: preferences, now: { self.now.addingTimeInterval(LastLiveMatchRecord.lifetime) }).record)
        XCTAssertNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
        try confirm(event(), in: store)
        XCTAssertNil(LastLiveMatchStore(defaults: preferences, now: { self.now.addingTimeInterval(-31) }).record)
    }

    func testExpiredEligibilityIsPureAndPruningPreservesNewPendingOwner() throws {
        let preferences = try defaults()
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        try confirm(event(), in: store)
        let saved = store.record, data = preferences.data(forKey: LastLiveMatchStore.storageKey)
        let expiredAt = now.addingTimeInterval(LastLiveMatchRecord.lifetime)
        let freshMatch = event(id: "pending", away: "Arsenal", offset: LastLiveMatchRecord.lifetime - 60)
        let pending = try XCTUnwrap(store.beginPlayback(of: freshMatch, now: expiredAt))
        XCTAssertNil(store.eligibleEvent(in: [event()], at: expiredAt, status: { _ in .inPlay }))
        XCTAssertEqual(store.record, saved, "Rendering eligibility must not mutate observed state")
        XCTAssertEqual(preferences.data(forKey: LastLiveMatchStore.storageKey), data)
        XCTAssertFalse(store.pruneExpiredRecord(at: now.addingTimeInterval(LastLiveMatchRecord.lifetime - 1)))
        XCTAssertTrue(store.pruneExpiredRecord(at: expiredAt))
        XCTAssertNil(store.record)
        XCTAssertNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
        XCTAssertFalse(store.pruneExpiredRecord(at: expiredAt))
        XCTAssertTrue(store.confirmDecodedPlayback(pending, now: expiredAt), "Expiry of the old record must not cancel the new owner's capture")
        XCTAssertEqual(store.record?.eventID, freshMatch.id)
        XCTAssertEqual(store.record?.confirmedAt, expiredAt)
        XCTAssertNotNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
    }

    func testChangedOpponentDateCategoryCompetitionAndSquadCannotReturn() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(event(), in: store)
        for changed in [event(away: "Arsenal"), event(category: "basketball"),
                        event(offset: -900 + 901), event(offset: -900 - 901), event(offset: 86_400),
                        event(competition: "champions-league"), event(competition: nil),
                        event(home: "Liverpool U21", away: "Chelsea U21"),
                        event(title: "Liverpool vs Chelsea Women"), event(conflict: true)] {
            XCTAssertNil(store.eligibleEvent(in: [changed], status: { _ in .inPlay }), changed.displayTitle)
        }
        XCTAssertNil(store.eligibleEvent(in: [event(), event(away: "Arsenal")], status: { _ in .inPlay }))
    }

    func testFreshCurrentResultRetainsOnlyItsOwnDeliveryNotStoredSource() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(event(), in: store)
        let fresh = event(id: "fresh-catalog-id", sources: [.init(source: "hotel", id: "fresh-route")])
        let current = try XCTUnwrap(store.eligibleEvent(in: [fresh], status: { _ in .inPlay }))
        XCTAssertEqual(current.id, "fresh-catalog-id")
        XCTAssertEqual(current.sources?.first?.id, "fresh-route")
        XCTAssertEqual(store.record?.eventID, "fixture")
    }

    func testCricketRequiresFreshVerifiedExplicitLiveReceipt() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(cricket(), in: store)
        XCTAssertNotNil(store.eligibleEvent(in: [cricket()]))
        XCTAssertNotNil(store.eligibleEvent(in: [cricket(receiptOffset: -CricketFixtureCatalog.statusFreshness)]))
        for current in [cricket(status: .scheduled), cricket(status: .unknown), cricket(status: .finished),
                        cricket(status: .cancelled), cricket(status: .postponed), cricket(verified: false),
                        cricket(receiptOffset: -CricketFixtureCatalog.statusFreshness - 1), cricket(receiptOffset: 301)] {
            XCTAssertNil(store.eligibleEvent(in: [current], status: { _ in .inPlay }))
        }
    }

    func testCricketFormatOrdinalAndSquadLabelStayPartOfIdentity() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(cricket(), in: store)
        for current in [cricket(format: .odi), cricket(label: "West Indies vs England · 2nd T20I"),
                        cricket(label: "West Indies vs England Women · 1st T20I"),
                        cricket(label: "West Indies vs England · Test Day 2")] {
            XCTAssertNil(store.eligibleEvent(in: [current]))
        }
    }

    func testSportsReceiptIdentityAndTerminalFactsCannotBeOverriddenByScore() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(baseball(), in: store)
        XCTAssertNotNil(store.eligibleEvent(in: [baseball()]))
        for current in [baseball(status: .scheduled), baseball(status: .finished), baseball(status: .cancelled),
                        baseball(status: .postponed), baseball(verified: false),
                        baseball(receiptOffset: -SportsFixtureCatalog.statusFreshness - 1), baseball(receiptOffset: 301),
                        baseball(gender: .women), baseball(ageGroup: "u21"), baseball(awayID: "another-team"),
                        baseball(eventKind: .session), baseball(sport: "football")] {
            XCTAssertNil(store.eligibleEvent(in: [current], status: { _ in .inPlay }))
        }
    }

    func testFootballFinishedCancelledPostponedSuspendedAndUnavailableScoreCannotReturn() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        try confirm(event(), in: store)
        for status: FootballMatch.MatchStatus in [.finished, .awarded, .cancelled, .postponed, .suspended, .timed] {
            XCTAssertNil(store.eligibleEvent(in: [event()], status: { _ in status }))
        }
        XCTAssertNotNil(store.eligibleEvent(in: [event()], status: { _ in .paused }), "Verified half-time remains live")
    }

    func testChannelsUndatedConflictingPlaceholderAndUnrelatedCategoriesAreNotRemembered() throws {
        let store = LastLiveMatchStore(defaults: try defaults(), now: { self.now })
        let undated = EventReference(id: "undated", title: "Liverpool vs Chelsea", category: "football", date: nil,
            poster: nil, popular: nil, teams: event().teams, sources: event().sources)
        for invalid in [undated, event(conflict: true), event(home: "Home", away: "Away"),
                        event(home: "Liverpool", away: "Liverpool"), event(category: "unrelated"),
                        event(category: "cricket", title: "Willow Cricket"), event(offset: 121),
                        event(id: "https://example.test/private-route"), baseball(sport: "football")] {
            XCTAssertNil(store.beginPlayback(of: invalid))
        }
    }

    func testMalformedOversizedUnknownAndTransportLikeStoredPayloadsAreRemoved() throws {
        let preferences = try defaults()
        let store = LastLiveMatchStore(defaults: preferences, now: { self.now })
        try confirm(baseball(), in: store)
        let original = try XCTUnwrap(preferences.data(forKey: LastLiveMatchStore.storageKey))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var unknown = base; unknown["streamURL"] = "https://private.test/media"
        var wrongVersion = base; wrongVersion["version"] = 2
        var unsafeTitle = base; unsafeTitle["title"] = "https://private.test/title"
        var unsafeNested = base
        var sports = try XCTUnwrap(base["sportsIdentity"] as? [String: Any]); sports["sourceURL"] = "https://private.test/media"
        unsafeNested["sportsIdentity"] = sports
        let invalids = try [unknown, wrongVersion, unsafeTitle, unsafeNested].map { try JSONSerialization.data(withJSONObject: $0) }
            + [Data("[]".utf8), Data(repeating: 0, count: LastLiveMatchRecord.maximumPayloadBytes + 1)]
        for data in invalids {
            preferences.set(data, forKey: LastLiveMatchStore.storageKey)
            XCTAssertNil(LastLiveMatchStore(defaults: preferences, now: { self.now }).record)
            XCTAssertNil(preferences.data(forKey: LastLiveMatchStore.storageKey))
        }
    }
}
