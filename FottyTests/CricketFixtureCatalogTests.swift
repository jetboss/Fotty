import XCTest
@testable import Fotty

@MainActor
final class CricketFixtureCatalogTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-30T14:00:00Z")!

    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func fixture(_ id: String = "india-wi-2", status: CricketFixtureCatalog.Status = .live,
                         format: CricketFixtureCatalog.Format = .odi, hours: Double = -5.5,
                         competition: String = "west-indies", observedAt: Date? = nil,
                         verification: CricketFixtureCatalog.Source.Verification? = nil) -> CricketFixtureCatalog.Fixture {
        .init(id: id, start: stamp(now.addingTimeInterval(hours * 3600)), format: format, status: status,
              competitionId: competition, competitionName: "West Indies tour of India",
              home: .init(id: "india-men", name: "India"), away: .init(id: "wi-men", name: "West Indies"),
              source: .init(name: "Official fixtures", url: "https://www.icc-cricket.com/fixtures-results",
                            observedAt: stamp(observedAt ?? now), verification: verification))
    }
    private func snapshot(_ rows: [CricketFixtureCatalog.Fixture],
                          status: CricketFixtureCatalog.SourceStatus = .verified,
                          checkedAt: Date? = nil, unavailable: [String] = []) -> CricketFixtureCatalog.Snapshot {
        let competitions = Set(rows.map(\.competitionId)).union(unavailable).union(["west-indies"])
        let coverage = competitions.sorted().map { id in
            CricketFixtureCatalog.Coverage(competitionId: id, competitionName: id,
                status: unavailable.contains(id) ? .unavailable : .covered,
                checkedAt: stamp(checkedAt ?? now), fixtureCount: rows.filter { $0.competitionId == id }.count,
                expectedFixtureCount: nil, nextStart: nil)
        }
        return .init(schemaVersion: 1, complete: true, checkedAt: stamp(checkedAt ?? now), revision: "test-1",
                     sourceStatus: status, fixtures: rows, coverage: coverage)
    }
    private func provider(_ id: String = "provider-india-wi", home: String = "India", away: String = "West Indies",
                          hours: Double = -5.5, sport: String = "cricket", title: String? = nil) -> EventReference {
        .init(id: id, title: title ?? "\(home) vs \(away)", category: sport,
              date: Int64(now.addingTimeInterval(hours * 3600).timeIntervalSince1970), poster: nil, popular: false,
              teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)))
    }

    func testCompleteValidatedPayloadAndOldEventJSONCompatibility() throws {
        let valid = snapshot([fixture()])
        XCTAssertEqual(try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(valid), now: now), valid)
        let old = Data(#"{"id":"old","category":"cricket","title":"India vs West Indies"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(EventReference.self, from: old).cricketFixture)
        let event = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: valid, at: now).first)
        let restored = try JSONDecoder().decode(EventReference.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(restored.cricketFixture, event.cricketFixture)
    }

    func testOfficialLimitedOversOrdinalSurvivesWireValidationCanonicalProjectionAndSavedEventRoundtrip() throws {
        for format in [CricketFixtureCatalog.Format.odi, .t20] {
            for ordinal in [1, 5, 99] {
                let raw = try ordinalPayload(format: format, value: ordinal)
                let accepted = try CricketFixtureCatalog.validatedSnapshot(from: raw, now: now)
                XCTAssertEqual(accepted.fixtures.first?.matchOrdinal, ordinal)
                let event = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: accepted, at: now).first)
                XCTAssertEqual(event.id, "cricket-fixture:india-wi-2")
                XCTAssertEqual(event.cricketFixture?.matchOrdinal, ordinal)
                XCTAssertNil(event.cricketFixture?.context, "An ordinal does not manufacture a scorecard or Test-day context")
                let restored = try JSONDecoder().decode(EventReference.self, from: JSONEncoder().encode(event))
                XCTAssertEqual(restored.cricketFixture?.matchOrdinal, ordinal)
                XCTAssertEqual(restored.cricketFixture?.format, format)
            }
        }
    }

    func testMissingOrMalformedAdditiveOrdinalDoesNotLoseAnOtherwiseValidFixtureOrInventAnOrdinal() throws {
        let invalidValues: [Any?] = [nil, NSNull(), "5", true, 0, -1, 100, 1.5]
        for format in [CricketFixtureCatalog.Format.odi, .t20] {
            for value in invalidValues {
                let accepted = try CricketFixtureCatalog.validatedSnapshot(from: ordinalPayload(format: format, value: value), now: now)
                XCTAssertEqual(accepted.fixtures.count, 1)
                XCTAssertNil(accepted.fixtures[0].matchOrdinal)
                let event = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: accepted, at: now).first)
                XCTAssertNil(event.cricketFixture?.matchOrdinal)
                XCTAssertEqual(event.cricketFixture?.status, .live)
            }
        }
        for format in [CricketFixtureCatalog.Format.test, .t10] {
            let decoded = try JSONDecoder().decode(CricketFixtureCatalog.Snapshot.self,
                from: ordinalPayload(format: format, value: 5))
            XCTAssertNil(decoded.fixtures.first?.matchOrdinal, "The additive limited-overs property cannot replace Test context or qualify an unreviewed format")
        }
    }

    func testSavedLimitedOversMetadataValidatesOptionalOrdinalWithoutBreakingLegacyCaches() throws {
        for format in [CricketFixtureCatalog.Format.odi, .t20] {
            let metadata = CricketFixtureMetadata(fixtureID: "icc:fixture", competitionID: "icc", competitionName: "International cricket",
                format: format, status: .live, observedAt: now, verified: true, matchOrdinal: 5)
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
            let invalidValues: [Any?] = [nil, NSNull(), "5", true, 0, 100, 2.5]
            for value in invalidValues {
                var raw = original; raw["matchOrdinal"] = value
                let decoded = try JSONDecoder().decode(CricketFixtureMetadata.self, from: JSONSerialization.data(withJSONObject: raw))
                XCTAssertNil(decoded.matchOrdinal)
                XCTAssertEqual(decoded.fixtureID, metadata.fixtureID); XCTAssertEqual(decoded.status, .live)
                XCTAssertTrue(decoded.verified)
            }
            XCTAssertEqual(try JSONDecoder().decode(CricketFixtureMetadata.self,
                from: JSONSerialization.data(withJSONObject: original)).matchOrdinal, 5)
        }
    }

    private func ordinalPayload(format: CricketFixtureCatalog.Format, value: Any?) throws -> Data {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot([fixture(format: format)]))) as? [String: Any])
        var rows = try XCTUnwrap(raw["fixtures"] as? [[String: Any]])
        rows[0]["matchOrdinal"] = value; raw["fixtures"] = rows
        return try JSONSerialization.data(withJSONObject: raw)
    }

    func testPartialOrMalformedPayloadCannotReplaceAtomicReceipt() throws {
        let valid = try JSONEncoder().encode(snapshot([fixture()]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        for change in ["complete", "fixtures", "coverage", "checkedAt"] {
            var invalid = json
            invalid.removeValue(forKey: change)
            XCTAssertThrowsError(try CricketFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: invalid), now: now))
        }
        json["complete"] = false
        XCTAssertThrowsError(try CricketFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now))
        XCTAssertThrowsError(try CricketFixtureCatalog.validatedSnapshot(from: Data(repeating: 32, count: CricketFixtureCatalog.maximumPayloadBytes + 1), now: now))
    }

    func testMissingFixtureCountDuplicateIdentityOrMissingTimezoneRejected() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot([fixture()]))) as? [String: Any])
        json["fixtures"] = []
        XCTAssertThrowsError(try CricketFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now))
        XCTAssertThrowsError(try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(snapshot([fixture(), fixture()])), now: now))
        XCTAssertNil(CricketFixtureCatalog.date("2026-09-30T08:30:00"))
        XCTAssertEqual(CricketFixtureCatalog.date("2026-09-30T04:30:00-04:00"), CricketFixtureCatalog.date("2026-09-30T08:30:00Z"))
    }

    func testODIAndMultiDayTestUseFreshExplicitStatusWithoutGuessedEnd() throws {
        for (format, hours) in [(CricketFixtureCatalog.Format.odi, -7.0), (.test, -72.0)] {
            let rows = CricketFixtureCatalog.merging(into: [], snapshot: snapshot([fixture(format: format, hours: hours)]), at: now)
            let row = try XCTUnwrap(rows.first)
            XCTAssertNil(row.estimatedMatchDuration)
            XCTAssertFalse(row.isPastEstimatedMatchWindow(at: now))
            XCTAssertTrue(row.passesNearTermLiveListWindow(at: now))
            XCTAssertEqual(row.broadcastTiming(at: now), .live)
            XCTAssertEqual(HomeSportsDiscovery(events: rows, now: now).items.first?.phase, .live)
            XCTAssertEqual(HomeSportsDiscovery(events: rows, now: now).activities.first { $0.id == "cricket" }?.onNow, 1)
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: row, in: rows, at: now), "A live fixture is not proof of a stream")
        }
    }

    func testStaleLiveReceiptAndUnknownPastStatusNeverAdvertiseLive() {
        for row in [fixture(observedAt: now.addingTimeInterval(-1801)), fixture(status: .unknown)] {
            let events = CricketFixtureCatalog.merging(into: [provider()], snapshot: snapshot([row]), at: now)
            XCTAssertEqual(HomeSportsDiscovery(events: events, now: now).items.first?.phase, .unconfirmed)
            XCTAssertEqual(events.first?.broadcastTiming(at: now), .available)
        }
        let cached = CricketFixtureCatalog.merging(into: [], snapshot: snapshot([fixture()], status: .lastKnownGood), at: now)
        XCTAssertEqual(HomeSportsDiscovery(events: cached, now: now).items.first?.phase, .unconfirmed)
    }

    func testVerifiedCricketTerminalFactsHaveTheSameQualifiedPolicyPrecedence() throws {
        for terminal in [CricketFixtureCatalog.Status.finished, .cancelled] {
            let event = try XCTUnwrap(CricketFixtureCatalog.terminalEvents(from: snapshot([fixture(status: terminal)])).first)
            for score: FootballMatch.MatchStatus in [.inPlay, .paused, .scheduled, .timed, .postponed, .suspended] {
                XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: score), .recent)
            }
            let metadata = try XCTUnwrap(event.cricketFixture)
            let unverified = CricketFixtureMetadata(fixtureID: metadata.fixtureID, competitionID: metadata.competitionID,
                competitionName: metadata.competitionName, format: metadata.format, status: metadata.status,
                observedAt: metadata.observedAt, verified: false)
            let control = EventReference(id: event.id, title: event.title, category: event.category, date: event.date,
                poster: nil, popular: false, teams: event.teams, cricketFixture: unverified)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: control, at: now, status: .inPlay), .live)
        }
        let live = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: snapshot([fixture()]), at: now).first)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: live, at: now), .live)
    }

    func testSavedCricketMetadataRoundtripRelaunchAndLegacyCompatibility() throws {
        let suite = "Fotty.SavedCricketMetadata.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let event = try XCTUnwrap(CricketFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(format: .test, hours: -72)]), at: now).first)
        let saved = SavedMatchRecord(event: event, savedAt: now)
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedMatchRecord.self, from: encoded)
        XCTAssertEqual(decoded.cricketFixture, event.cricketFixture)
        XCTAssertEqual(decoded.event.cricketFixture?.format, .test)
        XCTAssertEqual(decoded.event.cricketFixture?.observedAt, now)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: decoded.event, at: now), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: decoded.event, at: now.addingTimeInterval(1801)), .awaitingConfirmation,
                       "Saving/relaunch must not renew a stale live receipt")
        let store = MyMatchdayStore(defaults: defaults)
        XCTAssertEqual(store.save(event), .saved)
        let relaunched = try XCTUnwrap(MyMatchdayStore(defaults: defaults).savedMatches.first)
        XCTAssertEqual(relaunched.event.cricketFixture, event.cricketFixture)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "cricketFixture")
        let oldRecord = try JSONDecoder().decode(SavedMatchRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(oldRecord.cricketFixture, "Existing saved JSON remains decodable without migration")
        XCTAssertEqual(oldRecord.id, saved.id)
    }

    func testSavedCricketTerminalFactsReconcileFromTheScheduleWithoutInventedSources() async throws {
        for terminal in [CricketFixtureCatalog.Status.finished, .cancelled] {
            let suite = "Fotty.TerminalCricketJourney.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = MyMatchdayStore(defaults: defaults)
            var clock = now
            var manifest = snapshot([fixture()])
            let model = MatchListViewModel(refreshCricket: { manifest }, now: { clock }, matchdayStore: store)
            await model.refresh()
            let live = try XCTUnwrap(model.matches.first)
            XCTAssertEqual(store.save(live), .saved)
            let savedAt = store.savedMatches.first?.savedAt
            XCTAssertEqual(live.cricketFixture?.status, .live)
            clock = now.addingTimeInterval(60)
            manifest = snapshot([fixture(status: terminal, observedAt: clock)], checkedAt: clock)
            await model.refresh()
            XCTAssertTrue(model.matches.isEmpty, "Terminal facts belong to saved reconciliation, not playable listings")
            let saved = try XCTUnwrap(store.savedMatches.first)
            XCTAssertEqual(saved.cricketFixture?.status, terminal)
            XCTAssertEqual(saved.cricketFixture?.observedAt, clock)
            XCTAssertEqual(saved.savedAt, savedAt)
            XCTAssertEqual(saved.homeBadge, live.teams?.home?.badge)
            XCTAssertEqual(saved.awayBadge, live.teams?.away?.badge)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: saved.event, at: clock), .recent)
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: saved.event, in: model.playbackCatalog, at: clock))
            XCTAssertEqual(MyMatchdayStore(defaults: defaults).savedMatches.first?.cricketFixture, saved.cricketFixture)
        }
    }

    func testCricketSavedFallbackKeepsPostponementFormatAndCohortIdentity() throws {
        let suite = "Fotty.SavedCricketCohort.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MyMatchdayStore(defaults: defaults)
        let postponed = try XCTUnwrap(CricketFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .postponed, format: .test, hours: -40)]), at: now).first)
        XCTAssertEqual(store.save(postponed), .saved)
        store.reconcile(events: [], at: now)
        let saved = try XCTUnwrap(store.savedMatches.first)
        XCTAssertEqual(saved.cricketFixture, postponed.cricketFixture)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: saved.event, at: now), .timeToBeConfirmed)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: saved.event, in: [], at: now))

        let conflicting = try XCTUnwrap(CricketFixtureCatalog.terminalEvents(from:
            snapshot([fixture(status: .finished, format: .test, hours: -40, competition: "icc")])).first)
        XCTAssertEqual(conflicting.id, saved.id)
        XCTAssertNil(SavedMatchContinuityPolicy.currentEvent(for: saved, in: [conflicting]))
        store.reconcile(events: [conflicting], at: now)
        XCTAssertEqual(store.savedMatches.first, saved, "A reused fixture ID cannot cross cricket coverage cohorts")
    }

    func testMissingUnavailableFallbackAndDedicatedCPLEvidenceDoNotCancelSavedCricket() throws {
        let suite = "Fotty.MissingCricketEvidence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MyMatchdayStore(defaults: defaults)
        let live = try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: snapshot([fixture()]), at: now).first)
        XCTAssertEqual(store.save(live), .saved)
        let original = store.savedMatches
        for candidate in [snapshot([fixture(status: .finished)], status: .partial, unavailable: ["west-indies"]),
                          snapshot([fixture(status: .cancelled)], status: .lastKnownGood),
                          snapshot([fixture(status: .finished, competition: "cpl")])] {
            XCTAssertTrue(CricketFixtureCatalog.terminalEvents(from: candidate).isEmpty)
            store.reconcile(events: CricketFixtureCatalog.terminalEvents(from: candidate), at: now)
            XCTAssertEqual(store.savedMatches, original)
        }
        store.reconcile(events: [], at: now)
        XCTAssertEqual(store.savedMatches, original, "Absence is not verified cancellation")
    }

    func testGenericChannelRemainsSeparateAndDoesNotProveFixtureWatch() throws {
        let channel = EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: nil, poster: nil,
            popular: false, teams: nil)
        let rows = CricketFixtureCatalog.merging(into: [channel], snapshot: snapshot([fixture()]), at: now)
        let official = try XCTUnwrap(rows.first { $0.cricketFixture != nil })
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: official, in: rows, at: now))
    }

    func testPartialRetainsUnavailableCompetitionWithoutRefreshingItsLiveReceipt() throws {
        let old = snapshot([fixture(observedAt: now.addingTimeInterval(-3600))], checkedAt: now.addingTimeInterval(-3600))
        let candidate = snapshot([fixture("icc-current", competition: "icc")], status: .partial, unavailable: ["west-indies"])
        let accepted = CricketFixtureCatalog.accepting(candidate, over: old)
        XCTAssertEqual(Set(accepted.fixtures.map(\.id)), ["india-wi-2", "icc-current"])
        let events = CricketFixtureCatalog.merging(into: [], snapshot: accepted, at: now)
        let retained = try XCTUnwrap(events.first { $0.cricketFixture?.competitionID == "west-indies" })
        XCTAssertFalse(retained.cricketFixture?.isLive(at: now) == true)
        XCTAssertEqual(try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(accepted), now: now, reconciledCache: true), accepted)
    }

    func testIsolatedConflictDoesNotHideFreshVerifiedRowsOrCertifyHeldRows() throws {
        let heldReceipt = now.addingTimeInterval(-3600)
        let held = fixture("held", hours: -2, competition: "icc", observedAt: heldReceipt, verification: .held)
        let live = fixture("live", hours: -1, competition: "icc", verification: .verified)
        let future = fixture("future-held", status: .scheduled, hours: 1, competition: "icc",
                             observedAt: heldReceipt, verification: .held)
        let candidate = snapshot([held, live, future], status: .partial, unavailable: ["icc"])
        let validated = try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(candidate), now: now)
        let events = CricketFixtureCatalog.merging(into: [], snapshot: validated, at: now)
        let discovery = HomeSportsDiscovery(events: events, now: now)
        XCTAssertEqual(discovery.items.first { $0.id.hasSuffix(":live") }?.phase, .live)
        XCTAssertEqual(discovery.items.first { $0.id.hasSuffix(":held") }?.phase, .unconfirmed)
        XCTAssertEqual(discovery.items.first { $0.id.hasSuffix(":future-held") }?.phase, .unconfirmed)
        XCTAssertEqual(discovery.activities.first { $0.id == "cricket" }?.confirmedLive, 1)
        XCTAssertEqual(events.first { $0.id.hasSuffix(":held") }?.cricketFixture?.observedAt, heldReceipt)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: try XCTUnwrap(events.first { $0.id.hasSuffix(":live") }),
                                                        in: events, at: now), "A verified live fixture does not manufacture a stream")
        XCTAssertEqual(try JSONDecoder().decode(CricketFixtureCatalog.Snapshot.self,
                                                from: JSONEncoder().encode(validated)), validated)
    }

    func testExplicitRowReceiptCannotOverrideWholeCollectionFailureOrLiveFreshness() throws {
        for status in [CricketFixtureCatalog.SourceStatus.lastKnownGood, .unavailable] {
            let rows = CricketFixtureCatalog.merging(into: [],
                snapshot: snapshot([fixture(verification: .verified)], status: status, unavailable: ["west-indies"]), at: now)
            XCTAssertEqual(HomeSportsDiscovery(events: rows, now: now).items.first?.phase, .unconfirmed)
        }
        let stale = fixture(competition: "icc", observedAt: now.addingTimeInterval(-1801), verification: .verified)
        let rows = CricketFixtureCatalog.merging(into: [], snapshot: snapshot([stale], status: .partial, unavailable: ["icc"]), at: now)
        XCTAssertEqual(HomeSportsDiscovery(events: rows, now: now).items.first?.phase, .unconfirmed)
        let terminal = fixture(status: .finished, competition: "icc", verification: .verified)
        XCTAssertEqual(CricketFixtureCatalog.terminalEvents(from: snapshot([terminal], status: .partial, unavailable: ["icc"])).count, 1)
        XCTAssertTrue(CricketFixtureCatalog.terminalEvents(from:
            snapshot([fixture(status: .finished, competition: "icc", verification: .held)], status: .partial,
                     unavailable: ["icc"])).isEmpty)
    }

    func testUnknownVerificationAndContradictoryHeldCoverageAreRejectedButLegacyStillDecodes() throws {
        let encoded = try JSONEncoder().encode(snapshot([fixture()]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var rows = try XCTUnwrap(json["fixtures"] as? [[String: Any]])
        var source = try XCTUnwrap(rows[0]["source"] as? [String: Any])
        XCTAssertNil(source["verification"])
        let invalidValues: [Any] = ["unreviewed", "held", NSNull()]
        for value in invalidValues {
            source["verification"] = value
            rows[0]["source"] = source
            json["fixtures"] = rows
            XCTAssertThrowsError(try CricketFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now))
        }
        XCTAssertNoThrow(try CricketFixtureCatalog.validatedSnapshot(from: encoded, now: now))
    }

    func testNewEnvelopeCannotReplayOlderExplicitRowReceiptOverAcceptedFacts() {
        let old = snapshot([fixture(competition: "icc", verification: .verified)], status: .partial, unavailable: ["icc"])
        let replay = fixture(competition: "icc", observedAt: now.addingTimeInterval(-60), verification: .verified)
        let candidate = snapshot([replay], status: .partial, checkedAt: now.addingTimeInterval(60), unavailable: ["icc"])
        XCTAssertEqual(CricketFixtureCatalog.accepting(candidate, over: old), old)
    }

    func testCacheOnlyUnavailableRowsLoseExplicitAuthorityWithoutRenewingFacts() throws {
        for status in [CricketFixtureCatalog.Status.live, .finished] {
            let oldRow = fixture(status: status, competition: "icc", observedAt: now.addingTimeInterval(-60), verification: .verified)
            let old = snapshot([oldRow], status: .partial, checkedAt: now.addingTimeInterval(-60), unavailable: ["icc"])
            let candidate = snapshot([], status: .partial, unavailable: ["icc"])
            let accepted = CricketFixtureCatalog.accepting(candidate, over: old)
            let row = try XCTUnwrap(accepted.fixtures.first)
            XCTAssertEqual(row.source.verification, .held)
            XCTAssertEqual(row.source.observedAt, oldRow.source.observedAt)
            XCTAssertEqual(row.start, oldRow.start)
            XCTAssertEqual(row.status, oldRow.status)
            XCTAssertTrue(CricketFixtureCatalog.terminalEvents(from: accepted).isEmpty)
            XCTAssertEqual(try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(accepted), now: now,
                                                                      reconciledCache: true), accepted)
        }
    }

    func testNewEnvelopeCannotEraseOrResurrectRowsWithAnOlderEmptyCohortReceipt() {
        let rows = snapshot([fixture(verification: .verified)])
        let oldEmpty = CricketFixtureCatalog.Snapshot(schemaVersion: 1, complete: true,
            checkedAt: stamp(now.addingTimeInterval(60)), revision: "new-envelope-old-empty", sourceStatus: .partial,
            fixtures: [], coverage: [.init(competitionId: "west-indies", competitionName: "West Indies", status: .covered,
                checkedAt: stamp(now.addingTimeInterval(-60)), fixtureCount: 0, expectedFixtureCount: 0, nextStart: nil)])
        XCTAssertEqual(CricketFixtureCatalog.accepting(oldEmpty, over: rows), rows)

        let empty = snapshot([], checkedAt: now.addingTimeInterval(60))
        let oldRows = snapshot([fixture()], checkedAt: now.addingTimeInterval(120))
        let replay = CricketFixtureCatalog.Snapshot(schemaVersion: 1, complete: true,
            checkedAt: oldRows.checkedAt, revision: "new-envelope-old-rows", sourceStatus: .partial,
            fixtures: oldRows.fixtures, coverage: rows.coverage)
        XCTAssertEqual(CricketFixtureCatalog.accepting(replay, over: empty), empty)
    }

    func testUnavailableEmptyCohortCannotRewindWatermarkBeforeLaterReplay() throws {
        let empty = snapshot([], checkedAt: now)
        let candidate = CricketFixtureCatalog.Snapshot(schemaVersion: 1, complete: true,
            checkedAt: stamp(now.addingTimeInterval(60)), revision: "unavailable-empty", sourceStatus: .partial,
            fixtures: [], coverage: [.init(competitionId: "west-indies", competitionName: "West Indies", status: .unavailable,
                checkedAt: stamp(now.addingTimeInterval(-120)), fixtureCount: 0, expectedFixtureCount: nil, nextStart: nil)])
        let accepted = CricketFixtureCatalog.accepting(candidate, over: empty)
        XCTAssertEqual(accepted.coverage.first?.checkedAt, stamp(now))
        XCTAssertEqual(accepted.coverage.first?.status, .unavailable)
        let replay = snapshot([fixture(observedAt: now.addingTimeInterval(-60))], checkedAt: now.addingTimeInterval(120))
        let olderCoverage = CricketFixtureCatalog.Snapshot(schemaVersion: 1, complete: true,
            checkedAt: replay.checkedAt, revision: "older-nonempty", sourceStatus: .partial, fixtures: replay.fixtures,
            coverage: [.init(competitionId: "west-indies", competitionName: "West Indies", status: .covered,
                checkedAt: stamp(now.addingTimeInterval(-60)), fixtureCount: 1, expectedFixtureCount: 1, nextStart: nil)])
        XCTAssertEqual(CricketFixtureCatalog.accepting(olderCoverage, over: accepted), accepted)
        XCTAssertEqual(try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(accepted),
                                                                  now: now.addingTimeInterval(120), reconciledCache: true), accepted)
    }

    func testUnavailableOlderAndFallbackResponsesCannotEraseCachedFixtures() {
        let cached = snapshot([fixture()])
        for candidate in [snapshot([], status: .unavailable, unavailable: ["west-indies"]),
                          snapshot([], status: .lastKnownGood), snapshot([], checkedAt: now.addingTimeInterval(-60))] {
            XCTAssertEqual(CricketFixtureCatalog.accepting(candidate, over: cached), cached)
        }
        XCTAssertTrue(CricketFixtureCatalog.accepting(snapshot([]), over: cached).fixtures.isEmpty,
                      "A complete verified empty competition is meaningful")
    }

    func testStableIdentityCannotChangeParticipantsOrRegressTerminalStatus() {
        let original = fixture()
        let changed = CricketFixtureCatalog.Fixture(id: original.id, start: original.start, format: original.format, status: original.status,
            competitionId: original.competitionId, competitionName: original.competitionName,
            home: .init(id: "india-women", name: "India Women"), away: original.away, source: original.source)
        let cached = snapshot([original])
        XCTAssertEqual(CricketFixtureCatalog.accepting(snapshot([changed]), over: cached), cached)
        let ended = snapshot([fixture(status: .finished)])
        XCTAssertEqual(CricketFixtureCatalog.accepting(snapshot([fixture(status: .live)]), over: ended), ended)
    }

    func testNoStaleSourcesBorrowedWhenOnlyScheduleRefreshSucceeds() async throws {
        let manifest = snapshot([fixture()])
        let model = MatchListViewModel(refreshCricket: { manifest }, now: { self.now })
        model.matches = [provider()]
        await model.refresh()
        XCTAssertEqual(model.matches.count, 1)
        XCTAssertEqual(HomeSportsDiscovery(events: model.matches, now: now).items.first?.phase, .live)
    }

    func testReplayedScheduleReceiptStillRejectsCricketIdentityChange() async throws {
        let original = fixture(status: .scheduled, hours: 2)
        var manifest = snapshot([original])
        let model = MatchListViewModel(refreshCricket: { manifest }, now: { self.now })
        await model.refresh()
        let receipt = now.addingTimeInterval(60)
        let impostor = CricketFixtureCatalog.Fixture(id: original.id, start: stamp(now.addingTimeInterval(9000)),
            format: original.format, status: original.status, competitionId: original.competitionId,
            competitionName: original.competitionName, home: original.home,
            away: .init(id: "australia-men", name: "Australia"),
            source: .init(name: original.source.name, url: original.source.url, observedAt: stamp(receipt)))
        manifest = snapshot([impostor], checkedAt: receipt)
        await model.refresh()

        XCTAssertEqual(model.cricketFixtureSnapshot?.fixtures, [original])
        let retained = try XCTUnwrap(model.matches.first { $0.cricketFixture != nil })
        XCTAssertEqual(retained.kickoffDate, original.kickoff)
        XCTAssertEqual(retained.awayName, original.away.name)
    }

    func testPollingCadenceAdaptsWithoutInferringLiveFromSchedule() {
        XCTAssertEqual(CricketFixtureCatalog.pollingInterval(snapshot: snapshot([fixture(status: .scheduled, hours: 30)]), now: now), 4 * 3600)
        XCTAssertEqual(CricketFixtureCatalog.pollingInterval(snapshot: snapshot([fixture(status: .scheduled, hours: 2)]), now: now), 15 * 60)
        XCTAssertEqual(CricketFixtureCatalog.pollingInterval(snapshot: snapshot([fixture(status: .scheduled, hours: 0.25)]), now: now), 5 * 60)
        let events = CricketFixtureCatalog.merging(into: [], snapshot: snapshot([fixture(status: .scheduled)]), at: now)
        XCTAssertEqual(HomeSportsDiscovery(events: events, now: now).items.first?.phase, .unconfirmed)
    }

    func testAcceptedPartialQuietCoverageRetriesUnavailableCohortAfterFiveMinutes() async throws {
        let suite = "Fotty.PartialCricketRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let partial = snapshot([fixture(status: .scheduled, hours: 30)], status: .partial, unavailable: ["icc"])
        XCTAssertEqual(CricketFixtureCatalog.pollingInterval(snapshot: partial, now: now), 5 * 60)
        var payload = try JSONEncoder().encode(partial)
        var requests = 0
        let updater = CricketFixtureUpdater(defaults: defaults) { request in
            requests += 1
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let accepted = await updater.refresh(now: now)
        XCTAssertEqual(accepted, partial, "A complete partial receipt is admitted without erasing other cohorts")
        _ = await updater.refresh(now: now.addingTimeInterval(299))
        XCTAssertEqual(requests, 1)
        let recovered = snapshot([fixture(status: .scheduled, hours: 30),
            fixture("icc-future", status: .scheduled, hours: 32, competition: "icc")], checkedAt: now.addingTimeInterval(300))
        payload = try JSONEncoder().encode(recovered)
        let refreshed = await updater.refresh(now: now.addingTimeInterval(300))
        XCTAssertEqual(requests, 2, "A quiet remaining schedule must not delay an unavailable cohort for four hours")
        XCTAssertEqual(refreshed, recovered)
        XCTAssertEqual(CricketFixtureCatalog.pollingInterval(snapshot: refreshed, now: now.addingTimeInterval(300)), 4 * 3600)
    }

    func testRejectedUpdateAndRelaunchPreserveLastKnownGoodCache() async throws {
        let suite = "Fotty.CricketFixtureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let valid = snapshot([fixture()])
        var payload = try JSONEncoder().encode(valid)
        var requests = 0
        let updater = CricketFixtureUpdater(defaults: defaults) { request in
            requests += 1
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let first = await updater.refresh(now: now)
        XCTAssertEqual(first, valid)
        payload = Data(#"{"error":"partial upstream data"}"#.utf8)
        let rejected = await updater.refresh(now: now.addingTimeInterval(1), force: true)
        XCTAssertEqual(rejected, valid)
        XCTAssertEqual(CricketFixtureUpdater(defaults: defaults).cachedSnapshot(now: now), valid)
        _ = await updater.refresh(now: now.addingTimeInterval(2))
        XCTAssertEqual(requests, 2, "Routine Home polls do not duplicate fixture requests")
    }

    func testQuietCacheRetriesHTTPFailureFallbackAndMalformedResponseAfterFiveMinutes() async throws {
        for failure in ["http", "fallback", "malformed"] {
            let suite = "Fotty.CricketFixtureRetryTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let valid = snapshot([fixture(status: .scheduled, hours: 30)])
            var payload = try JSONEncoder().encode(valid)
            var httpStatus = 200
            var requests = 0
            let updater = CricketFixtureUpdater(defaults: defaults) { request in
                requests += 1
                return (payload, HTTPURLResponse(url: request.url!, statusCode: httpStatus, httpVersion: nil, headerFields: nil)!)
            }
            let first = await updater.refresh(now: now)
            XCTAssertEqual(first, valid)
            if failure == "http" { httpStatus = 503 }
            if failure == "fallback" { payload = try JSONEncoder().encode(snapshot([], status: .lastKnownGood)) }
            if failure == "malformed" { payload = Data(#"{"error":"partial"}"#.utf8) }
            let failedAt = now.addingTimeInterval(1)
            let failed = await updater.refresh(now: failedAt, force: true)
            XCTAssertEqual(failed, valid)
            _ = await updater.refresh(now: failedAt.addingTimeInterval(299))
            XCTAssertEqual(requests, 2, "\(failure) must obey its five-minute cooldown")
            _ = await updater.refresh(now: failedAt.addingTimeInterval(300))
            XCTAssertEqual(requests, 3, "\(failure) must not inherit a four-hour quiet-schedule wait")
        }
    }

    func testCancellationClearsQuietCadenceAndExistingRetryCooldown() async throws {
        for usesURLError in [false, true] {
            let suite = "Fotty.CricketFixtureCancelTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let valid = snapshot([fixture(status: .scheduled, hours: 30)])
            let payload = try JSONEncoder().encode(valid)
            var nextError: Error?
            var requests = 0
            let updater = CricketFixtureUpdater(defaults: defaults) { request in
                requests += 1
                if let nextError { throw nextError }
                return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            _ = await updater.refresh(now: now)
            nextError = URLError(.badServerResponse)
            _ = await updater.refresh(now: now.addingTimeInterval(1), force: true)
            if usesURLError { nextError = URLError(.cancelled) }
            else { nextError = CancellationError() }
            _ = await updater.refresh(now: now.addingTimeInterval(2), force: true)
            nextError = nil
            let afterCancellation = await updater.refresh(now: now.addingTimeInterval(3))
            XCTAssertEqual(afterCancellation, valid)
            XCTAssertEqual(requests, 4, "Cancellation must permit an immediate later owner, even on a quiet day")
        }
    }
}

@MainActor
final class OptionalSourceLookupPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let enabled: Set<String> = ["communitysports"]

    func testWatchRequiresConfirmedDeliveryAndPendingStatesAreNoninteractive() {
        let ready: [FixtureSourceLookupPresentation.State] = [
            .init(currentCandidateCount: 1, previouslyFound: false, isChecking: false),
            .init(currentCandidateCount: 0, previouslyFound: false, isChecking: false, catalogListedProviderCount: 1),
            .init(currentCandidateCount: 0, previouslyFound: true, isChecking: true,
                  hasConfirmedAvailability: true)
        ]
        for state in ready {
            XCTAssertTrue(state.canWatch)
            XCTAssertEqual(state.title, "Watch")
            XCTAssertEqual(state.symbol, "play.fill")
            XCTAssertEqual(state.accessibilityLabel(matchTitle: "India vs New Zealand"), "Watch India vs New Zealand")
            XCTAssertEqual(state.detailsMessage(canWatchHere: false), state.detailsMessage(canWatchHere: true))
            XCTAssertTrue(state.detailsMessage(canWatchHere: true).contains("Choose Watch"))
        }
        let pending: [(FixtureSourceLookupPresentation.State, String)] = [
            (.init(currentCandidateCount: 0, previouslyFound: false, isChecking: false), "Broadcast unconfirmed"),
            (.init(currentCandidateCount: 0, previouslyFound: true, isChecking: false), "Broadcast unconfirmed"),
            (.init(currentCandidateCount: 0, previouslyFound: false, isChecking: true), "Finding a broadcast…"),
            (.init(currentCandidateCount: 0, previouslyFound: false, isChecking: false,
                   hasCompletedLookup: true), "Broadcast unavailable"),
            (.init(currentCandidateCount: 0, previouslyFound: false, isChecking: false,
                   hasCompletedLookup: true, hasLookupFailure: true), "Broadcast unconfirmed")
        ]
        for (state, title) in pending {
            XCTAssertFalse(state.canWatch)
            XCTAssertEqual(state.title, title)
            XCTAssertEqual(state.detailsTitle, title)
            XCTAssertEqual(state.accessibilityLabel(matchTitle: "India vs New Zealand"), "India vs New Zealand, \(title)")
            XCTAssertFalse(state.detailsMessage(canWatchHere: true).contains("Choose Watch"))
            XCTAssertFalse(state.detailsMessage(canWatchHere: true).contains("Check streams"))
        }
    }

    func testSharedFixtureFirstPresentationRequiresEnabledReviewedSourcesAndKeepsWatchHonest() throws {
        let row = cricket(), index = FixtureStreamDiscoveryIndex()
        XCTAssertNil(FixtureSourceLookupPresentation.state(for: row, at: now, discoveryIndex: index))
        XCTAssertNil(FixtureSourceLookupPresentation.state(for: row, at: now,
            enabledProviderCodes: ["future-provider"], discoveryIndex: index))
        let state = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now,
            enabledProviderCodes: enabled, discoveryIndex: index))
        XCTAssertEqual(state.title, "Broadcast unconfirmed")
        XCTAssertEqual(state.symbol, "tv.slash")
        XCTAssertEqual(state.accessibilityLabel(matchTitle: row.displayTitle), "\(row.displayTitle), Broadcast unconfirmed")
        XCTAssertFalse(state.canWatch)
        XCTAssertEqual(state.currentCandidateCount, 0)
        XCTAssertFalse(state.previouslyFound)
        XCTAssertFalse(MatchStartPolicy(event: row, now: now, discoveryIndex: index).canAttemptPlayback)
        let details = CatalogEventDetailsPresentation.broadcast(for: row, now: now,
            enabledProviderCodes: enabled, discoveryIndex: index)
        XCTAssertEqual(details.title, state.detailsTitle)
        XCTAssertEqual(details.message, "Broadcast availability hasn't been confirmed.")
        XCTAssertEqual(details.symbol, "tv.slash")
        XCTAssertFalse(details.message.contains("Check streams"))
        for blocked in [cricket(status: .finished), cricket(status: .unknown), cricket(verified: false),
                        cricket(offset: nil), cricket(home: "TBC"), sports(verified: false)] {
            XCTAssertNil(FixtureSourceLookupPresentation.state(for: blocked, at: now,
                enabledProviderCodes: enabled, discoveryIndex: index))
        }
    }

    func testDiscoveryAndDetailsStayConsistentAcrossCandidateExpiryAndRecheckGap() throws {
        let row = cricket(), request = StreamPlaybackRequest(event: row), index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(enabled, revision: 1)
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_fixture", streamID: "nuvio_sport_fixture", manifestRevision: "1",
            verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
        let session = StreamSession(matchID: row.id, playableURL: URL(string: "https://media.example/test.m3u8")!,
            streamType: .hls, providerName: "CS1", createdAt: now, eventBinding: binding)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
        index.complete(ticket, sessions: [session], at: now)
        let fresh = CatalogEventDetailsPresentation.broadcast(for: row, now: now, canWatchHere: true,
            enabledProviderCodes: enabled, discoveryIndex: index)
        XCTAssertEqual(fresh.title, "Ready to watch")
        XCTAssertTrue(fresh.message.contains("Choose Watch"))
        for seconds in [60.0, 89.0, 90.0] {
            let time = now.addingTimeInterval(seconds)
            let state = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: time, discoveryIndex: index))
            XCTAssertEqual(state.currentCandidateCount, 0)
            XCTAssertTrue(state.previouslyFound)
            XCTAssertTrue(state.canWatch, "An undisproved availability fact survives a short delivery-URL expiry")
            XCTAssertTrue(state.hasConfirmedAvailability)
            XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: time))
            let details = CatalogEventDetailsPresentation.broadcast(for: row, now: time, canWatchHere: true,
                enabledProviderCodes: enabled, discoveryIndex: index)
            XCTAssertEqual(details.title, state.detailsTitle)
            XCTAssertTrue(details.message.contains("Choose Watch"))
            XCTAssertFalse(details.message.contains("Check streams"))
        }
        let expired = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row,
            at: now.addingTimeInterval(300), discoveryIndex: index))
        XCTAssertFalse(expired.canWatch)
        XCTAssertEqual(expired.title, "Broadcast unconfirmed")
        index.updateEnabledProviders([], revision: 2)
        XCTAssertNil(FixtureSourceLookupPresentation.state(for: row, at: now.addingTimeInterval(301), discoveryIndex: index))
        XCTAssertEqual(CatalogEventDetailsPresentation.broadcast(for: row, now: now.addingTimeInterval(301),
            enabledProviderCodes: [], discoveryIndex: index).title, "Broadcast not listed")
    }

    func testConfirmedAvailabilityNeverReusesExpiredURLOrCrossesSquadDate() throws {
        let row = cricket(), request = StreamPlaybackRequest(event: row), index = FixtureStreamDiscoveryIndex()
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_fixture", streamID: "nuvio_sport_fixture", manifestRevision: "1",
            verifiedAt: now, expiresAt: now.addingTimeInterval(10), at: now))
        let session = StreamSession(matchID: row.id, playableURL: URL(string: "https://media.example/short.m3u8")!,
            streamType: .hls, providerName: "CS1", expiryTime: now.addingTimeInterval(10), createdAt: now, eventBinding: binding)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(ticket, sessions: [session], at: now)
        let state = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now.addingTimeInterval(10),
            enabledProviderCodes: enabled, discoveryIndex: index))
        XCTAssertTrue(state.previouslyFound)
        XCTAssertTrue(state.canWatch)
        XCTAssertTrue(state.hasConfirmedAvailability)
        XCTAssertEqual(state.currentCandidateCount, 0)
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(10)))
        for changed in [cricket(offset: -600), cricket(home: "Afghanistan Women")] {
            let other = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: changed, at: now.addingTimeInterval(10),
                enabledProviderCodes: enabled, discoveryIndex: index))
            XCTAssertFalse(other.previouslyFound)
            XCTAssertEqual(other.currentCandidateCount, 0)
            XCTAssertFalse(other.canWatch)
            XCTAssertFalse(other.hasConfirmedAvailability)
        }
    }

    func testAutomaticLookupStatusDistinguishesCheckingEmptyFailureAndUncheckedLane() throws {
        let row = cricket(), request = StreamPlaybackRequest(event: row)
        let index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(enabled, revision: 1)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        let checking = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now, discoveryIndex: index))
        XCTAssertFalse(checking.canWatch)
        XCTAssertEqual(checking.title, "Finding a broadcast…")
        index.complete(ticket, sessions: [], at: now)
        let empty = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now, discoveryIndex: index))
        XCTAssertEqual(empty.title, "Broadcast unavailable")
        XCTAssertTrue(empty.hasCompletedLookup)
        XCTAssertFalse(empty.hasLookupFailure)

        let failedTicket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(failedTicket, sessions: [], failure: StreamFailure(providerName: "CS1",
            category: .manifestUnreachable, technicalMessage: "Metadata unavailable",
            userMessage: "Broadcast unconfirmed", retryable: true, fallbackAllowed: true), at: now)
        let failed = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now, discoveryIndex: index))
        XCTAssertFalse(failed.canWatch)
        XCTAssertEqual(failed.title, "Broadcast unconfirmed")
        XCTAssertTrue(failed.hasLookupFailure)

        let partial = FixtureStreamDiscoveryIndex()
        partial.updateEnabledProviders(["communitysports", "plaviosports"], revision: 1)
        let completedCS = try XCTUnwrap(partial.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        partial.complete(completedCS, sessions: [], at: now)
        let uncheckedSibling = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now, discoveryIndex: partial))
        XCTAssertFalse(uncheckedSibling.canWatch)
        XCTAssertFalse(uncheckedSibling.hasCompletedLookup)
        XCTAssertEqual(uncheckedSibling.title, "Broadcast unconfirmed", "One empty lane cannot claim every enabled lane is empty")
    }

    func testUpcomingFixtureRetainsCountdownAndGenericChannelRetainsIndependentWatch() {
        let upcoming = cricket(status: .scheduled, offset: 60)
        let index = FixtureStreamDiscoveryIndex()
        XCTAssertNotNil(check(upcoming), "The existing preflight window remains eligible")
        XCTAssertNil(FixtureSourceLookupPresentation.state(for: upcoming, at: now,
            enabledProviderCodes: enabled, discoveryIndex: index))
        XCTAssertNotNil(MatchStartPolicy(event: upcoming, now: now, discoveryIndex: index).upcomingStart)
        let channel = EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil)
        XCTAssertTrue(channel.isBroadcastChannel)
        XCTAssertNil(FixtureSourceLookupPresentation.state(for: channel, at: now,
            enabledProviderCodes: enabled, discoveryIndex: index))
        let channelIndex = FixtureStreamDiscoveryIndex()
        channelIndex.updateEnabledProviders(enabled, revision: 1)
        let channelAction = CurrentEventBroadcastPolicy.action(for: channel, in: [channel], at: now, discoveryIndex: channelIndex)
        XCTAssertNotNil(channelAction)
        XCTAssertTrue(channelAction.map { MatchStartPolicy(event: $0.event, now: now, discoveryIndex: channelIndex).canAttemptPlayback } == true,
                      "The canonical channel the action opens is playable")
    }

    func testFreshSourceFreeOfficialCricketOffersCheckWithoutInventingWatch() throws {
        let row = cricket()
        let admitted = try XCTUnwrap(check(row))
        XCTAssertEqual(admitted.id, row.id)
        XCTAssertEqual(admitted.cricketFixture, row.cricketFixture)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now))
        XCTAssertFalse(MatchStartPolicy(event: row, now: now).canAttemptPlayback)
        XCTAssertEqual(MatchStartPolicy(event: row, now: now).title, "No stream listed")
    }

    func testCheckRequiresOptInAndDoesNotReplacePrimaryWatch() {
        let row = cricket()
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row], enabledProviderCodes: [], at: now))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row], enabledProviderCodes: ["future-provider"], at: now))
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: row, in: [row],
            enabledProviderCodes: [" COMMUNITYSPORTS "], at: now))
    }

    func testAdditionalOptInOffersItsReviewedFootballAndCricketScopes() {
        let football = sports()
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: football, in: [football],
            enabledProviderCodes: ["plaviosports"], at: now))
        let cricket = cricket()
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: cricket, in: [cricket],
            enabledProviderCodes: ["plaviosports"], at: now))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: football, in: [football],
            enabledProviderCodes: [], at: now, phase: .completion))
    }

    func testDefaultScore808OffersSourceFreeVerifiedCupFreshWatchWithoutClaimingAListing() throws {
        let defaults = StreamPluginRegistry.bundledCatalog(savedStates: [:]).plugins
        let codes = Set(defaults.filter(\.isEnabled).map(\.providerCode))
        XCTAssertTrue(codes.contains("score808"))
        XCTAssertFalse(codes.contains("communitysports"))
        XCTAssertFalse(codes.contains("plaviosports"))
        let row = cup()
        let admitted = try XCTUnwrap(OptionalSourceLookupPolicy.event(for: row, in: [row],
            enabledProviderCodes: codes, at: now))
        XCTAssertEqual(admitted.sportsFixture, row.sportsFixture)
        XCTAssertEqual(admitted.competitionID, "carabao-cup")
        XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now,
            discoveryIndex: freshWatchIndex(codes), catalogIndex: FixtureCatalogAvailabilityIndex())?.evidence,
            .freshLookupOpportunity, "Watch runs the resolver; it never claims a listing")
        // The existing resolver dispatch uses this same football/window rule;
        // the request needs no primary descriptor or optional-source opt-in.
        let request = StreamPlaybackRequest(event: admitted)
        XCTAssertTrue(Score808LateDiscoveryPolicy.isLookupWindow(kickoffDate: request.kickoffDate,
            category: request.category, at: now))
    }

    func testScore808OnlyCupCheckRetainsProviderConsentAndFootballScope() {
        let row = cup()
        for codes: Set<String> in [[], ["future-provider"]] {
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row],
                enabledProviderCodes: codes, at: now))
        }
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: row, in: [row],
            enabledProviderCodes: [" SCORE808 "], at: now))
        for otherSport in [cricket(), sports(sport: "basketball")] {
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: otherSport, in: [otherSport],
                enabledProviderCodes: ["score808"], at: now))
        }
    }

    func testScore808OnlyCupCheckRejectsHeldStaleStoppedAndOutOfWindowReceipts() {
        let invalid = [
            cup(verified: false),
            cup(offset: -SportsFixtureMetadata.unconfirmedLiveWindow,
                observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1)),
            cup(observedAt: now.addingTimeInterval(301)),
            cup(offset: -Score808LateDiscoveryPolicy.lookupTailTime - 1),
            cup(offset: MatchStartPolicy.playbackLead + 1, status: .scheduled),
            cup(offset: -VerifiedFixtureStartingPolicy.grace - 1, status: .scheduled)
        ] + [SportsFixtureCatalog.Status.finished, .cancelled, .postponed, .unknown].map { cup(status: $0) }
        for row in invalid {
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row],
                enabledProviderCodes: ["score808"], at: now, status: .inPlay), row.displayTitle)
        }
        let edge = cup(observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness))
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: edge, in: [edge],
            enabledProviderCodes: ["score808"], at: now))
        // One missed fixture refresh keeps a started LIVE row eligible (unconfirmed).
        let staleLive = cup(observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1))
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: staleLive, in: [staleLive],
            enabledProviderCodes: ["score808"], at: now))
        let upcoming = cup(offset: MatchStartPolicy.playbackLead, status: .scheduled)
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: upcoming, in: [upcoming],
            enabledProviderCodes: ["score808"], at: now))
        let starting = cup(offset: -1, status: .scheduled)
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: starting, in: [starting],
            enabledProviderCodes: ["score808"], at: now))
        XCTAssertFalse(starting.sportsFixture?.isLive(at: now) ?? true)
    }

    func testScore808OnlyCupCheckRequiresUnchangedUniqueOfficialIdentity() {
        let row = cup()
        let variants = [
            cup(id: "provider-liverpool-chelsea"),
            cup(fixtureID: "sports-fixture:premier-league:liverpool-chelsea"),
            cup(offset: -7_200),
            cup(home: "Liverpool U21", squad: .init(gender: .men, ageGroup: "u21")),
            cup(squad: .init(gender: .women, ageGroup: "senior")),
            cup(home: "Arsenal", homeID: "arsenal"),
            cup(conflict: true)
        ]
        for current in variants {
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [current],
                enabledProviderCodes: ["score808"], at: now))
        }
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row, row],
            enabledProviderCodes: ["score808"], at: now))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [],
            enabledProviderCodes: ["score808"], at: now))
        let correctedName = cup(home: "Liverpool FC")
        XCTAssertEqual(OptionalSourceLookupPolicy.event(for: row, in: [correctedName],
            enabledProviderCodes: ["score808"], at: now)?.homeName, "Liverpool FC",
            "Accepted display-name corrections retain the stable official participant identity")
    }

    func testScore808OnlyCupCompletionRechecksConsentAndCurrentReceipt() throws {
        let row = cup()
        let refreshed = cup()
        let completion = try XCTUnwrap(OptionalSourceLookupPolicy.event(for: row, in: [refreshed],
            enabledProviderCodes: ["score808"], at: now, phase: .completion))
        XCTAssertEqual(completion.sportsFixture, row.sportsFixture)
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [refreshed],
            enabledProviderCodes: [], at: now, phase: .completion))
        for current in [cup(verified: false), cup(status: .finished),
                        cup(offset: -SportsFixtureMetadata.unconfirmedLiveWindow,
                            observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1))] {
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [current],
                enabledProviderCodes: ["score808"], at: now, phase: .completion))
        }
    }

    func testCompletionKeepsAnExactCSResultWhenPrimaryDescriptorArrivesDuringLookup() throws {
        let initial = cricket()
        XCTAssertNotNil(check(initial))
        let refreshed = cricket()
        let admitted = try XCTUnwrap(OptionalSourceLookupPolicy.event(for: initial, in: [refreshed],
            enabledProviderCodes: enabled, at: now, phase: .completion))
        XCTAssertEqual(admitted.id, initial.id)
        XCTAssertEqual(admitted.cricketFixture, initial.cricketFixture)
    }

    func testCompletionStillRejectsDisabledStaleConflictingAndStoppedFixtures() {
        let initial = cricket()
        let refreshed = cricket()
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: initial, in: [refreshed],
            enabledProviderCodes: [], at: now, phase: .completion))
        let stale = cricket(observedAt: now.addingTimeInterval(-CricketFixtureCatalog.statusFreshness - 1))
        let conflicting = cricket(conflict: true)
        for current in [stale, conflicting, cricket(verified: false)] {
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: initial, in: [current],
                enabledProviderCodes: enabled, at: now, phase: .completion))
        }
        for state: CricketFixtureCatalog.Status in [.finished, .cancelled, .postponed, .unknown] {
            let current = cricket(status: state)
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: initial, in: [current],
                enabledProviderCodes: enabled, at: now, status: .inPlay, phase: .completion))
        }
    }

    func testCheckRequiresTheUniqueCurrentCatalogFixtureAndReturnsItsReceipt() throws {
        let stale = cricket(observedAt: now.addingTimeInterval(-CricketFixtureCatalog.statusFreshness - 1))
        let current = cricket()
        XCTAssertNil(check(stale))
        let admitted = try XCTUnwrap(OptionalSourceLookupPolicy.event(for: stale, in: [current],
            enabledProviderCodes: enabled, at: now))
        XCTAssertEqual(admitted.cricketFixture?.observedAt, now)
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: current, in: [], enabledProviderCodes: enabled, at: now))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: current, in: [current, current],
            enabledProviderCodes: enabled, at: now))
        let changedStart = cricket(offset: 3_600)
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: current, in: [changedStart],
            enabledProviderCodes: enabled, at: now))
        let changedIdentity = cricket(id: "cricket-fixture:different-official-id", fixtureID: "different-official-id")
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: current, in: [changedIdentity],
            enabledProviderCodes: enabled, at: now), "A similar other fixture is not this official fixture")
    }

    func testConflictHeldAndUnsupportedOfficialProvenanceCannotOfferCheck() {
        XCTAssertNil(check(cricket(conflict: true)))
        XCTAssertNil(check(cricket(verified: false)))
        XCTAssertNil(check(cricket(id: "provider-row")))
        XCTAssertNil(check(cricket(category: "football")))
        XCTAssertNil(check(cricket(includeMetadata: false)))
        let current = cricket(conflict: true)
        let requested = cricket()
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: requested, in: [current],
            enabledProviderCodes: enabled, at: now))
    }

    func testCricketLiveReceiptUsesExistingFreshnessAndClockSkewBoundaries() {
        XCTAssertNotNil(check(cricket(observedAt: now.addingTimeInterval(-CricketFixtureCatalog.statusFreshness))))
        XCTAssertNil(check(cricket(observedAt: now.addingTimeInterval(-CricketFixtureCatalog.statusFreshness - 1))))
        XCTAssertNotNil(check(cricket(observedAt: now.addingTimeInterval(300))))
        XCTAssertNil(check(cricket(observedAt: now.addingTimeInterval(301))))
        XCTAssertNotNil(check(cricket(offset: -72 * 3_600, format: .test)),
            "Fresh explicit Test-match status must not acquire a guessed T20/football end")
    }

    func testScheduledCricketUsesExistingLeadButNeverInfersLiveFromElapsedStart() {
        for offset in [0.0, MatchStartPolicy.playbackLead] {
            XCTAssertNotNil(check(cricket(status: .scheduled, offset: offset)))
        }
        XCTAssertNil(check(cricket(status: .scheduled, offset: MatchStartPolicy.playbackLead + 1)))
        XCTAssertNil(check(cricket(status: .scheduled, offset: MatchStartPolicy.playbackLead + 1), status: .inPlay))
        XCTAssertNil(check(cricket(status: .scheduled, offset: -1)))
        XCTAssertNil(check(cricket(status: .scheduled, offset: -1), status: .inPlay),
            "A separate score cannot promote elapsed scheduled provenance into accepted current state")
        XCTAssertNil(check(cricket(status: .scheduled, offset: 60,
            observedAt: now.addingTimeInterval(-CricketFixtureCatalog.statusFreshness - 1))))
    }

    func testCricketTerminalUnknownAndExternalStoppedStatusesVetoCheck() {
        for state: CricketFixtureCatalog.Status in [.finished, .cancelled, .postponed, .unknown] {
            XCTAssertNil(check(cricket(status: state)))
            XCTAssertNil(check(cricket(status: state), status: .inPlay))
        }
        for state: FootballMatch.MatchStatus in [.finished, .cancelled, .postponed, .suspended] {
            XCTAssertNil(check(cricket(), status: state))
        }
    }

    func testChannelsUnknownStartsAndPlaceholderTeamsCannotOfferCheck() {
        XCTAssertNil(check(cricket(offset: nil)))
        XCTAssertNil(check(cricket(title: "Willow Cricket")))
        for name in ["", "Home", "Away", "TBC", "TBD", "Unknown", "Teams to be confirmed", "Zimbabwe"] {
            XCTAssertNil(check(cricket(home: name)), name)
        }
    }

    func testFreshNamedOfficialSportsMatchOffersOnlyOptionalCheck() throws {
        let row = sports()
        let admitted = try XCTUnwrap(check(row))
        XCTAssertEqual(admitted.sportsFixture, row.sportsFixture)
        XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now,
            discoveryIndex: freshWatchIndex(enabled), catalogIndex: FixtureCatalogAvailabilityIndex())?.evidence,
            .freshLookupOpportunity)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now,
            discoveryIndex: freshWatchIndex([]), catalogIndex: FixtureCatalogAvailabilityIndex()),
            "With no enabled discovery source there is nothing to look up")
        XCTAssertNotNil(check(sports(status: .scheduled, offset: MatchStartPolicy.playbackLead)))
        XCTAssertNil(check(sports(status: .scheduled, offset: MatchStartPolicy.playbackLead + 1)))
        let starting = sports(status: .scheduled, offset: -1)
        XCTAssertNotNil(check(starting))
        XCTAssertFalse(starting.sportsFixture?.isLive(at: now) ?? true)
        XCTAssertNil(check(sports(status: .scheduled, offset: -VerifiedFixtureStartingPolicy.grace)))
    }

    /// Leeds–Tottenham 7 Nov: after a relaunch every local index is empty and
    /// the cloud registry may omit the match. Watch must still reach the
    /// resolver, whose exact adapters decide whether a stream exists.
    func testLiveSportsFixtureOffersFreshWatchAtColdStartWithoutClaimingABroadcast() throws {
        let row = sports(), index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(enabled, revision: 1)
        let state = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now,
            enabledProviderCodes: enabled, discoveryIndex: index, catalogIndex: FixtureCatalogAvailabilityIndex(),
            registry: BroadcastRegistryClient(defaults: UserDefaults(suiteName: "cold-start-\(UUID().uuidString)")!)))
        XCTAssertTrue(state.canWatch, "A live supported fixture offers Watch at cold start")
        XCTAssertTrue(state.canOfferFreshWatch)
        XCTAssertEqual(state.currentCandidateCount, 0, "No compatible broadcast is claimed")
        XCTAssertEqual(state.catalogListedProviderCount, 0)
        XCTAssertEqual(state.title, "Watch")
        XCTAssertEqual(state.detailsTitle, "Look for a broadcast")
        XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now, discoveryIndex: index,
            catalogIndex: FixtureCatalogAvailabilityIndex())?.evidence, .freshLookupOpportunity)
        let cricketState = FixtureSourceLookupPresentation.state(for: cricket(), at: now,
            enabledProviderCodes: enabled, discoveryIndex: index)
        XCTAssertNotEqual(cricketState?.canOfferFreshWatch, true, "Cricket keeps its existing evidence-first rule")
    }

    func testDefinitiveEmptyLookupWithholdsFreshWatchOnlyUntilItAges() throws {
        let row = sports(), index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(enabled, revision: 1)
        let request = StreamPlaybackRequest(event: row)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(ticket, sessions: [], failure: nil, at: now)
        let empty = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: now,
            enabledProviderCodes: enabled, discoveryIndex: index, catalogIndex: FixtureCatalogAvailabilityIndex()))
        XCTAssertFalse(empty.canWatch, "A just-completed empty lookup is reported honestly")
        XCTAssertEqual(empty.statusTitle, "Broadcast unavailable")
        let later = now.addingTimeInterval(FixtureStreamDiscoveryIndex.positiveLifetime + 1)
        XCTAssertTrue(try XCTUnwrap(FixtureSourceLookupPresentation.state(for: row, at: later,
            enabledProviderCodes: enabled, discoveryIndex: index, catalogIndex: FixtureCatalogAvailabilityIndex())).canWatch,
            "The negative ages out with the discovery lifetime and Watch returns")
    }

    func testSportsReceiptUsesExistingFreshnessAndPreservesTerminalVeto() {
        XCTAssertNotNil(check(sports(observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness))))
        // One missed fixture refresh mid-match keeps the live fixture eligible
        // for an exact lookup (never displayed as confirmed LIVE) until the
        // four-hour window from kickoff ends.
        let stale = sports(observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1))
        XCTAssertNotNil(check(stale))
        XCTAssertFalse(stale.sportsFixture?.isLive(at: now) ?? true)
        XCTAssertTrue(stale.sportsFixture?.isUnconfirmedLive(at: now, kickoff: try XCTUnwrap(stale.kickoffDate)) ?? false)
        XCTAssertNil(check(sports(offset: -SportsFixtureMetadata.unconfirmedLiveWindow,
            observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1))))
        XCTAssertNil(check(sports(status: .scheduled, offset: -3_600,
            observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1))),
            "Only a LIVE receipt gains the unconfirmed grace")
        XCTAssertNotNil(check(sports(observedAt: now.addingTimeInterval(300))))
        XCTAssertNil(check(sports(observedAt: now.addingTimeInterval(301))))
        XCTAssertNil(check(sports(status: .scheduled, offset: 60,
            observedAt: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1))))
        for state: SportsFixtureCatalog.Status in [.finished, .cancelled, .postponed, .unknown] {
            XCTAssertNil(check(sports(status: state), status: .inPlay))
        }
    }

    func testSportsRequiresAcceptedCanonicalNamedMatchProvenance() {
        XCTAssertNil(check(sports(verified: false)))
        XCTAssertNil(check(sports(id: "provider-row")))
        XCTAssertNil(check(sports(fixtureID: "sports-fixture:other-league:match")))
        XCTAssertNil(check(sports(sport: "kabaddi")))
        XCTAssertNil(check(sports(eventKind: .session)))
        XCTAssertNil(check(sports(eventKind: .tournament)))
        XCTAssertNil(check(sports(participants: [.init(id: "one", name: "Arsenal")])))
        XCTAssertNil(check(sports(participants: [.init(id: "one", name: "Leeds United"),
                                               .init(id: "two", name: "Chelsea")])))
        XCTAssertNil(check(sports(home: "TBC")))
        XCTAssertNil(check(sports(offset: nil)))
    }

    private func check(_ event: EventReference, status: FootballMatch.MatchStatus? = nil) -> EventReference? {
        OptionalSourceLookupPolicy.event(for: event, in: [event], enabledProviderCodes: enabled, at: now, status: status)
    }

    private func cricket(
        id: String = "cricket-fixture:afghanistan-zimbabwe",
        fixtureID: String = "afghanistan-zimbabwe",
        status: CricketFixtureCatalog.Status = .live,
        offset: TimeInterval? = -3_600,
        observedAt: Date? = nil,
        verified: Bool = true,
        category: String = "cricket",
        home: String = "Afghanistan",
        title: String? = nil,
        conflict: Bool = false,
        includeMetadata: Bool = true,
        format: CricketFixtureCatalog.Format = .odi
    ) -> EventReference {
        let metadata = CricketFixtureMetadata(fixtureID: fixtureID, competitionID: "icc",
            competitionName: "ICC international cricket", format: format, status: status,
            observedAt: observedAt ?? now, verified: verified)
        return .init(id: id, title: title ?? "\(home) vs Zimbabwe", category: category,
            date: offset.map { Int64(now.addingTimeInterval($0).timeIntervalSince1970) },
            poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: "Zimbabwe", badge: nil)), hasCatalogIdentityConflict: conflict,
            cricketFixture: includeMetadata ? metadata : nil)
    }

    private func sports(
        id: String = "sports-fixture:premier-league:arsenal-chelsea",
        fixtureID: String = "sports-fixture:premier-league:arsenal-chelsea",
        status: SportsFixtureCatalog.Status = .live,
        offset: TimeInterval? = -3_600,
        observedAt: Date? = nil,
        verified: Bool = true,
        sport: String = "football",
        home: String = "Arsenal",
        eventKind: SportsFixtureCatalog.EventKind = .match,
        participants: [SportsFixtureCatalog.Participant]? = nil,
        competitionID: String = "premier-league",
        competitionName: String = "Premier League"
    ) -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: fixtureID, sport: sport,
            competitionID: competitionID, competitionName: competitionName, eventKind: eventKind,
            title: "Arsenal vs Chelsea", participants: participants ?? [.init(id: "arsenal", name: "Arsenal"),
                .init(id: "chelsea", name: "Chelsea")], squad: .init(gender: .men, ageGroup: "senior"),
            status: status, observedAt: observedAt ?? now, verified: verified)
        return .init(id: id, title: "Arsenal vs Chelsea", category: sport,
            date: offset.map { Int64(now.addingTimeInterval($0).timeIntervalSince1970) }, poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata, competitionID: competitionID)
    }

    /// Explicit, order-independent enablement for Watch-gate assertions.
    private func freshWatchIndex(_ codes: Set<String>) -> FixtureStreamDiscoveryIndex {
        let index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(codes, revision: 1)
        return index
    }

    private func cup(
        id: String = "sports-fixture:carabao-cup:liverpool-chelsea",
        fixtureID: String = "sports-fixture:carabao-cup:liverpool-chelsea",
        offset: TimeInterval = -3_600,
        status: SportsFixtureCatalog.Status = .live,
        observedAt: Date? = nil,
        verified: Bool = true,
        home: String = "Liverpool",
        homeID: String = "liverpool",
        squad: SportsFixtureCatalog.Squad = .init(gender: .men, ageGroup: "senior"),
        conflict: Bool = false
    ) -> EventReference {
        let title = "\(home) vs Chelsea"
        let metadata = SportsFixtureMetadata(fixtureID: fixtureID, sport: "football",
            competitionID: "carabao-cup", competitionName: "Carabao Cup", eventKind: .match,
            title: title, participants: [.init(id: homeID, name: home), .init(id: "chelsea", name: "Chelsea")],
            squad: squad, status: status, observedAt: observedAt ?? now, verified: verified)
        return .init(id: id, title: title, category: "football",
            date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: "Chelsea", badge: nil)), hasCatalogIdentityConflict: conflict, sportsFixture: metadata,
            competitionID: "carabao-cup")
    }
}

@MainActor
final class CricketChannelCatalogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testIndependentInventorySurvivesEmptyMasterWithoutInventingFixturesOrSources() {
        let inventory = CricketChannelCatalog.merging(into: [])
        XCTAssertEqual(inventory.map(\.id), CricketBroadcastChannel.allCases.map(\.canonicalID))
        for event in inventory {
            XCTAssertTrue(event.isBroadcastChannel)
            XCTAssertNil(event.date)
            XCTAssertNil(event.teams)
            XCTAssertNil(event.cricketFixture)
            XCTAssertNil(event.sportsFixture)
            XCTAssertNil(event.competitionID)
        }
        let discovery = HomeSportsDiscovery(events: inventory, now: now)
        XCTAssertTrue(discovery.items.isEmpty)
        XCTAssertEqual(discovery.channels.count, 2)
        XCTAssertEqual(HomeSportsSearch.results(in: discovery, query: "Willow channel").map(\.id), [CricketBroadcastChannel.willow.canonicalID])
        XCTAssertEqual(HomeSportsSearch.results(in: discovery, query: "Fox Cricket").map(\.id), [CricketBroadcastChannel.foxCricket.canonicalID])
    }

    func testTaintedAndContradictoryChannelRowsCannotDonateSources() {
        let metadata = CricketFixtureMetadata(fixtureID: "fixture", competitionID: "icc", competitionName: "ICC",
            format: .test, status: .live, observedAt: now, verified: true)
        let rows = [
            row("conflict", "Willow Cricket", conflict: true),
            row("fixture", "Willow Cricket", metadata: metadata),
            row("teams", "Willow Cricket", teams: .init(home: .init(name: "India", badge: nil), away: .init(name: "Australia", badge: nil))),
            row(CricketBroadcastChannel.willow.canonicalID, "Fox Cricket"),
            row("other-category", "Willow Cricket", category: "football")
        ]
        XCTAssertEqual(CricketChannelCatalog.merging(into: rows).filter(\.isBroadcastChannel).count, 2)
        for row in rows { XCTAssertNil(CricketChannelCatalog.canonicalEvent(for: row, in: rows)) }
    }

    func testCanonicalRequestRequiresExplicitChannelIdentityAndNoFixtureClaims() {
        let canonical = CricketChannelCatalog.event(for: .willow, in: [])
        XCTAssertEqual(CricketBroadcastChannel.identifying(request: .init(event: canonical)), .willow)
        XCTAssertEqual(CricketBroadcastChannel.identifying(title: "📺 Willow Cricket"), .willow)
        XCTAssertEqual(CricketBroadcastChannel.identifying(title: "📺 FOX Cricket"), .foxCricket)
        for title in ["Willow 2", "📺 Willow 2 Cricket", "📺 Cr FOX Cricket 501", "Willow Cricket vs Fox Cricket"] {
            XCTAssertNil(CricketBroadcastChannel.identifying(title: title))
        }
        for request in [
            StreamPlaybackRequest(event: row("provider-id", "Willow Cricket")),
            .init(matchID: canonical.id, displayTitle: canonical.displayTitle, homeTeam: canonical.homeName, awayTeam: "Australia", category: "cricket"),
            .init(matchID: canonical.id, displayTitle: "Fox Cricket", homeTeam: "Fox Cricket", awayTeam: "", category: "cricket"),
            .init(matchID: canonical.id, displayTitle: canonical.displayTitle, homeTeam: canonical.homeName, awayTeam: "", category: "football"),
            .init(matchID: canonical.id, displayTitle: canonical.displayTitle, homeTeam: canonical.homeName, awayTeam: "", category: "cricket", kickoffDate: now),
            .init(event: row(canonical.id, canonical.displayTitle, conflict: true))
        ] { XCTAssertNil(CricketBroadcastChannel.identifying(request: request)) }
    }

    private func row(_ id: String, _ title: String, category: String = "cricket",
                     conflict: Bool = false, metadata: CricketFixtureMetadata? = nil,
                     teams: NexusATeams? = nil) -> EventReference {
        .init(id: id, title: title, category: category, date: -3_600_000,
            poster: nil, popular: false, teams: teams,
            hasCatalogIdentityConflict: conflict, cricketFixture: metadata)
    }
}
