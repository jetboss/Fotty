import XCTest
@testable import Fotty

@MainActor
final class SportsCatalogRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_600_000)

    private func event(_ id: String, at date: Date? = nil) -> EventReference {
        .init(id: id, title: "\(id) Home vs \(id) Away", category: "football",
              date: Int64((date ?? now).timeIntervalSince1970), poster: nil, popular: false,
              teams: nil, sources: [.init(source: "delta", id: id)])
    }

    private func snapshot(_ rows: [EventReference], at date: Date? = nil, partial: Bool = false) -> LiveCatalogSnapshot {
        .init(events: rows, checkedAt: date ?? now, source: "controlled", respondingFeeds: 1,
              attemptedFeeds: partial ? 2 : 1, isPartial: partial)
    }

    private func cplSnapshot(
        _ fixtures: [CPLSchedule.Fixture],
        checkedAt: Date? = nil,
        status: CPLSchedule.SourceStatus = .verified
    ) -> CPLSchedule.Snapshot {
        .init(revision: "test", checkedAt: checkedAt ?? now, fixtures: fixtures, sourceStatus: status)
    }

    private func cplPayload() throws -> Data {
        let formatter = ISO8601DateFormatter()
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "competitionId": "cpl", "season": 2026, "revision": "test-current",
            "checkedAt": formatter.string(from: now), "sourceStatus": "verified", "fixtureCount": 2,
            "fixtures": [
                ["number": 1, "upstreamId": "official-1", "start": formatter.string(from: now.addingTimeInterval(3600)),
                 "team1": "trinbago", "team2": "guyana"],
                ["number": 2, "upstreamId": "official-2", "start": formatter.string(from: now.addingTimeInterval(7200)),
                 "stage": "Final"]
            ]
        ])
    }

    func testCancelledCPLRequestDoesNotThrottleTheNextVisibleOwner() async throws {
        for cancellation in [CancellationError() as Error, URLError(.cancelled) as Error] {
            let suite = "Fotty.CPLCancelledRequest.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let payload = try cplPayload()
            var requests = 0
            let updater = CPLScheduleUpdater(defaults: defaults) { request in
                requests += 1
                if requests == 1 { throw cancellation }
                return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let cancelled = await updater.refresh(now: now)
            XCTAssertNil(cancelled)
            let subsequent = await updater.refresh(now: now.addingTimeInterval(1))
            XCTAssertEqual(requests, 2, "Cancellation did not complete a source check")
            XCTAssertEqual(subsequent?.revision, "test-current")
        }
    }

    func testCancelledCPLTaskCannotPublishLateSuccessOrHoldAttemptThrottle() async throws {
        let suite = "Fotty.CPLCancelledTask.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let payload = try cplPayload()
        var requests = 0
        let updater = CPLScheduleUpdater(defaults: defaults) { request in
            requests += 1
            if requests == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cancelledOwner = Task { await updater.refresh(now: self.now) }
        let cancelled = await cancelledOwner.value
        XCTAssertNil(cancelled)
        XCTAssertNil(updater.cachedSnapshot(now: now), "A response arriving after owner cancellation must not be committed")
        let subsequent = await updater.refresh(now: now.addingTimeInterval(1))
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(subsequent?.revision, "test-current")
    }

    func testOrdinaryCPLFailuresAndSuccessKeepThirtyMinuteSourceCadence() async throws {
        for result in ["transport", "http", "malformed", "success"] {
            let suite = "Fotty.CPLAttemptCadence.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let valid = try cplPayload()
            var requests = 0
            let updater = CPLScheduleUpdater(defaults: defaults) { request in
                requests += 1
                if result == "transport" { throw URLError(.notConnectedToInternet) }
                let payload = result == "malformed" ? Data("{}".utf8) : valid
                let status = result == "http" ? 503 : 200
                return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            _ = await updater.refresh(now: now)
            _ = await updater.refresh(now: now.addingTimeInterval(1799))
            XCTAssertEqual(requests, 1, result)
            _ = await updater.refresh(now: now.addingTimeInterval(1800))
            XCTAssertEqual(requests, 2, "\(result) preserves the reviewed source cadence")
        }
    }

    func testMatchdaySourceFreeCPLAwaitsConfirmationAndProviderBroadcastsStayUnverified() throws {
        let formatter = ISO8601DateFormatter()
        let past = CPLSchedule.Fixture(1, formatter.string(from: now.addingTimeInterval(-3600)), .trinbago, .guyana)
        let future = CPLSchedule.Fixture(2, formatter.string(from: now.addingTimeInterval(3600)), .antigua, .jamaica)
        let rows = CPLSchedule.merging(into: [], fixtures: [past, future], at: now)
        let elapsed = try XCTUnwrap(rows.first { $0.id == past.id })
        XCTAssertTrue(elapsed.sources?.isEmpty == true)
        XCTAssertEqual(elapsed.broadcastTiming(at: now), .available)
        XCTAssertEqual(HomeSportsDiscovery(events: rows, now: now).items.first { $0.event.id == elapsed.id }?.phase, .listedNow)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: elapsed, at: now), .awaitingConfirmation)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: elapsed, in: rows, at: now))
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: future.event(), at: now), .upcoming)

        let provider = EventReference(id: "nfl-provider", title: "Seattle Seahawks vs Los Angeles Rams", category: "american-football",
            date: Int64(now.addingTimeInterval(-3600).timeIntervalSince1970), poster: nil, popular: false,
            teams: nil, sources: [.init(source: "delta", id: "nfl-provider")])
        XCTAssertEqual(provider.broadcastTiming(at: now), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: provider, at: now), .listedNow,
                       "A provider listing must not claim confirmed live play")
        let channel = EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil, sources: [.init(source: "delta", id: "willow")])
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: channel, at: now), .channel)
        let unknownTime = EventReference(id: "unknown", title: "India vs West Indies", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil, sources: [])
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: unknownTime, at: now), .timeToBeConfirmed)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: event("official"), at: now, status: .inPlay), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: event("official"), at: now, status: .scheduled), .awaitingConfirmation)
    }

    func testValidEmptyIsDistinctFromMissingOrErrorShapedJSON() throws {
        XCTAssertTrue(try AnalyticalDataEngine.decodeMatches(from: Data("[]".utf8)).isEmpty)
        XCTAssertTrue(try AnalyticalDataEngine.decodeMatches(from: Data("{\"matches\":[]}".utf8)).isEmpty)
        for body in ["{}", "{\"error\":\"offline\"}", "{\"matches\":null}"] {
            XCTAssertThrowsError(try AnalyticalDataEngine.decodeMatches(from: Data(body.utf8)))
        }
    }

    func testNormalizedBroadcastContractPreservesPartialMirrorEvidenceAndConflictRows() throws {
        let stamp = ISO8601DateFormatter().string(from: now)
        let rows: [[String: Any]] = [
            ["id": "same", "title": "Arsenal vs Chelsea", "category": "football", "date": Int(now.timeIntervalSince1970), "sources": [["source": "delta", "id": "advertised"]]],
            ["id": "same", "title": "Different vs Teams", "category": "football", "date": Int(now.timeIntervalSince1970), "sources": []],
        ]
        let body: [String: Any] = ["schemaVersion": 1, "observedAt": stamp, "independentFamilies": 1, "providers": [
            ["id": "nexus-primary", "family": "nexus", "outcome": "unavailable", "matches": []],
            ["id": "nexus-mirror", "family": "nexus", "outcome": "partial", "matches": rows],
            ["id": "nexus-backup", "family": "nexus", "outcome": "empty", "matches": []],
        ]]
        let decoded = try AnalyticalDataEngine.decodeBroadcastCatalog(from: JSONSerialization.data(withJSONObject: body), at: now)
        XCTAssertNil(decoded[0].events)
        XCTAssertEqual(decoded[1].events?.count, 2)
        let snapshot = try LiveCatalogSnapshot.combine(decoded, at: now)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.respondingFeeds, 2)
        XCTAssertTrue(snapshot.events.contains(where: \.hasCatalogIdentityConflict))
    }

    func testNormalizedBroadcastContractRejectsStaleUnknownDuplicateAndForgedAuthority() throws {
        let stamp = ISO8601DateFormatter().string(from: now)
        let providers: [[String: Any]] = ["nexus-primary", "nexus-mirror", "nexus-backup"].map {
            ["id": $0, "family": "nexus", "outcome": "empty", "matches": []]
        }
        let base: [String: Any] = ["schemaVersion": 1, "observedAt": stamp, "independentFamilies": 1, "providers": providers]
        var variants: [[String: Any]] = []
        var v = base; v["schemaVersion"] = 2; variants.append(v)
        v = base; v["observedAt"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(-121)); variants.append(v)
        v = base; v["independentFamilies"] = 3; variants.append(v)
        v = base; v["providers"] = [providers[0], providers[0], providers[2]]; variants.append(v)
        var invalid = providers
        invalid[0] = ["id": "nexus-primary", "family": "nexus", "outcome": "available", "matches": [
            ["id": "forged", "title": "Home vs Away", "_fottyIdentityConflict": true]
        ]]
        v = base; v["providers"] = invalid; variants.append(v)
        for body in variants {
            XCTAssertThrowsError(try AnalyticalDataEngine.decodeBroadcastCatalog(from: JSONSerialization.data(withJSONObject: body), at: now))
        }
        let decoded = try AnalyticalDataEngine.decodeBroadcastCatalog(from: JSONSerialization.data(withJSONObject: base), at: now)
        XCTAssertTrue(try LiveCatalogSnapshot.combine(decoded, at: now).events.isEmpty)
    }

    func testConflictTombstoneSurvivesFeedCombinationAndPartialRefresh() async throws {
        let original = event("reused")
        let changed = EventReference(id: original.id, title: "Different Home vs Different Away", category: "football",
            date: original.date, poster: nil, popular: false, teams: nil, sources: [.init(source: "golf", id: "wrong")])
        var next = snapshot([original])
        let model = MatchListViewModel(fetchSnapshot: { next }, now: { self.now })
        await model.refresh()
        next = try LiveCatalogSnapshot.combine([
            .init(source: "first", events: [original]), .init(source: "other", events: [changed]),
            .init(source: "down", events: nil)
        ], at: now)
        guard case .conflicting = CatalogPlaybackIdentity.selection(for: StreamPlaybackRequest(event: original), in: next.events) else {
            return XCTFail("A conflict must not become a missing event")
        }
        await model.refresh()
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: original, in: model.playbackCatalog, at: now))
        XCTAssertEqual(model.identityConflicts.count, 1)
    }

    func testErrorOnlyCancellationDoesNotPublishIndependentSchedule() async {
        let model = MatchListViewModel(fetchSnapshot: { throw CancellationError() },
            refreshSchedule: { self.cplSnapshot(CPLSchedule.fixtures) }, now: { self.now })
        model.matches = [event("kept")]
        await model.refresh()
        XCTAssertEqual(model.matches.map(\.id), ["kept"])
        XCTAssertFalse(model.refreshFailed)
    }

    func testVerifiedScheduleAfterFeedFailureDoesNotBorrowStaleSources() async throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first)
        let time = fixture.kickoff.addingTimeInterval(-1800)
        let planned = fixture.event(sources: [])
        let stale = EventReference(id: "old-provider", title: planned.title, category: "cricket", date: planned.date,
            poster: nil, popular: false, teams: planned.teams, sources: [.init(source: "delta", id: "stale")])
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.notConnectedToInternet) },
            refreshSchedule: {
                self.cplSnapshot([fixture], checkedAt: time)
            }, now: { time })
        model.matches = [stale]
        await model.refresh()
        XCTAssertTrue(model.refreshFailed)
        XCTAssertEqual(model.matches.map(\.id), [fixture.id])
        XCTAssertTrue(model.matches.allSatisfy { $0.sources?.isEmpty != false })
        XCTAssertNil(model.lastCatalogCheck)
    }

    func testCPLScheduleFreshnessIsIndependentFromCatalogFreshness() async throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first { $0.kickoff > now })
        let freshModel = MatchListViewModel(
            fetchSnapshot: { self.snapshot([]) },
            refreshSchedule: { self.cplSnapshot([fixture]) },
            now: { self.now }
        )

        await freshModel.refresh()
        XCTAssertTrue(freshModel.isCPLScheduleFresh(at: now))
        XCTAssertNil(freshModel.catalogNotice(at: now))

        var onFetch: (() -> Void)?
        let staleModel = MatchListViewModel(
            fetchSnapshot: { onFetch?(); return self.snapshot([]) },
            refreshSchedule: {
                self.cplSnapshot(
                    [fixture],
                    checkedAt: self.now.addingTimeInterval(-CPLSchedule.verificationFreshnessWindow - 1)
                )
            },
            now: { self.now }
        )
        await staleModel.refresh()
        XCTAssertFalse(staleModel.isCPLScheduleFresh(at: now))
        XCTAssertEqual(
            staleModel.catalogNotice(at: now),
            "CPL start times may have changed."
        )
        XCTAssertNil(staleModel.catalogNotice(at: now, displaying: [event("football-only")]),
                     "A CPL-only warning must not appear while browsing football")
        XCTAssertNil(staleModel.catalogNotice(at: now, displaying: []),
                     "An empty filtered view does not display stale CPL fixtures")
        for visible in [[fixture.event()], [event("football-only")], []] {
            let containsCPL = visible.contains(where: \.isCPLFixture)
            XCTAssertEqual(staleModel.catalogNotice(at: now, displaysCPLSchedule: containsCPL),
                           staleModel.catalogNotice(at: now, displaying: visible),
                           "Reusing identity facts must not change warning scope")
        }
        XCTAssertEqual(staleModel.catalogNotice(at: now, displaysCPLSchedule: true),
                       "CPL start times may have changed.")
        XCTAssertNil(freshModel.catalogNotice(at: now, displaysCPLSchedule: true))
        XCTAssertEqual(freshModel.catalogNotice(at: now.addingTimeInterval(CPLSchedule.verificationFreshnessWindow + 1),
                                              displaysCPLSchedule: true),
                       "CPL start times may have changed.",
                       "Cached fixture identity must never cache schedule freshness")
        onFetch = {
            XCTAssertTrue(staleModel.isRefreshing)
            XCTAssertEqual(staleModel.catalogNotice(at: self.now), "CPL start times may have changed.",
                           "Starting a retry must not hide known stale schedule data")
        }
        await staleModel.refresh()
        onFetch = nil
    }

    func testReplayedProviderReceiptCannotHoldBackCPLCorrectionOrLendStaleSources() async throws {
        for correctedHours in [1.5, 2.5] {
            let original = CPLSchedule.Fixture(1,
                ISO8601DateFormatter().string(from: now.addingTimeInterval(7200)), .trinbago, .saintLucia)
            let planned = original.event()
            let provider = EventReference(id: "provider-cpl", title: planned.title, category: "cricket",
                date: planned.date, poster: nil, popular: false, teams: planned.teams,
                sources: [.init(source: "delta", id: "stale-cpl-stream")])
            let unrelated = event("other-sport")
            var check = now
            var schedule = cplSnapshot([original])
            let model = MatchListViewModel(fetchSnapshot: {
                self.snapshot([provider, unrelated], at: check)
            }, refreshSchedule: { schedule }, now: { self.now })
            await model.refresh()
            let old = try XCTUnwrap(model.matches.first { $0.id == original.id })
            let saved = SavedMatchRecord(event: old, savedAt: now)
            XCTAssertEqual(old.sources?.first?.id, "stale-cpl-stream")

            let receipt = now.addingTimeInterval(60)
            let corrected = CPLSchedule.Fixture(1,
                ISO8601DateFormatter().string(from: now.addingTimeInterval(correctedHours * 3600)),
                .trinbago, .saintLucia)
            check = now.addingTimeInterval(-60)
            schedule = cplSnapshot([corrected], checkedAt: receipt)
            await model.refresh()

            let current = try XCTUnwrap(model.matches.first { $0.id == original.id })
            XCTAssertEqual(model.lastCatalogCheck, now, "An old provider receipt is not a new catalog check")
            XCTAssertEqual(model.cplScheduleCheckedAt, receipt)
            XCTAssertEqual(model.cplScheduleSourceStatus, .verified)
            XCTAssertEqual(current.kickoffDate, corrected.kickoff)
            XCTAssertTrue(current.sources?.isEmpty == true)
            XCTAssertFalse(model.matches.contains { $0.id == provider.id })
            XCTAssertEqual(model.matches.first { $0.id == unrelated.id }?.sources?.first?.id,
                           unrelated.sources?.first?.id)
            XCTAssertEqual(SavedMatchContinuityPolicy.currentEvent(for: saved, in: model.playbackCatalog)?.kickoffDate,
                           corrected.kickoff, "Saved/reminded identity must resolve the corrected kickoff")
        }
    }

    func testReplayedProviderCannotReplaceCPLWithOlderOrUnverifiedSchedule() async throws {
        for status in [CPLSchedule.SourceStatus.verified, .lastKnownGood] {
            let original = CPLSchedule.Fixture(1,
                ISO8601DateFormatter().string(from: now.addingTimeInterval(7200)), .trinbago, .saintLucia)
            var check = now
            var schedule = cplSnapshot([original])
            let model = MatchListViewModel(fetchSnapshot: { self.snapshot([], at: check) },
                refreshSchedule: { schedule }, now: { self.now })
            await model.refresh()
            let changed = CPLSchedule.Fixture(1,
                ISO8601DateFormatter().string(from: now.addingTimeInterval(9000)), .trinbago, .saintLucia)
            check = now.addingTimeInterval(-60)
            schedule = cplSnapshot([changed], checkedAt: now.addingTimeInterval(status == .verified ? -60 : 60),
                                   status: status)
            await model.refresh()

            XCTAssertEqual(model.cplScheduleCheckedAt, now)
            XCTAssertEqual(model.cplScheduleSourceStatus, .verified)
            XCTAssertEqual(model.matches.first { $0.id == original.id }?.kickoffDate, original.kickoff)
            XCTAssertEqual(model.lastCatalogCheck, now)
        }
    }

    func testLastKnownGoodCPLScheduleNeverClaimsCurrentVerification() async throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first { $0.kickoff > now })
        let model = MatchListViewModel(
            fetchSnapshot: { self.snapshot([]) },
            refreshSchedule: {
                self.cplSnapshot([fixture], status: .lastKnownGood)
            },
            now: { self.now }
        )

        await model.refresh()
        XCTAssertEqual(model.cplScheduleSourceStatus, .lastKnownGood)
        XCTAssertFalse(model.isCPLScheduleFresh(at: now))
        XCTAssertNotNil(model.catalogNotice(at: now))
    }

    func testCombiningWaitedFeedsPreservesCoverageAndValidEmpty() throws {
        let combined = try LiveCatalogSnapshot.combine([
            .init(source: "first", events: [event("a")]),
            .init(source: "second", events: [event("b")]),
            .init(source: "down", events: nil)
        ], at: now)
        XCTAssertEqual(Set(combined.events.map(\.id)), ["a", "b"])
        XCTAssertTrue(combined.isPartial)
        XCTAssertEqual(combined.respondingFeeds, 2)
        XCTAssertEqual(combined.attemptedFeeds, 3)
        let empty = try LiveCatalogSnapshot.combine([.init(source: "valid", events: [])], at: now)
        XCTAssertFalse(empty.isPartial)
        XCTAssertTrue(empty.events.isEmpty)
        XCTAssertThrowsError(try LiveCatalogSnapshot.combine([.init(source: "down", events: nil)]))
    }

    func testCompletedFallbackConflictSurvivesPendingSiblingAtDeadline() throws {
        let original = event("reused")
        let conflicting = EventReference(id: original.id, title: "Different Home vs Different Away", category: "football",
            date: original.date, poster: nil, popular: false, teams: nil, sources: [])
        let accumulator = LiveCatalogAccumulator(sources: ["first", "fallback", "pending"])
        accumulator.record([original], source: "first")
        accumulator.record([conflicting], source: "fallback", fallbackPart: "live")
        // Upcoming and the third mirror never finish. Already completed evidence
        // must still be available when the owning lookup deadline stops them.
        let result = try LiveCatalogSnapshot.combine(accumulator.observations, at: now)
        XCTAssertTrue(result.isPartial)
        guard case .conflicting = CatalogPlaybackIdentity.selection(for: StreamPlaybackRequest(event: original), in: result.events) else {
            return XCTFail("The observed conflict was lost behind an unfinished sibling")
        }
    }

    func testFailedRefreshRetainsRowsAndReceiptButShowsFailure() async {
        var fail = false
        let first = snapshot([event("saved")])
        let model = MatchListViewModel(fetchSnapshot: {
            if fail { throw URLError(.notConnectedToInternet) }
            return first
        }, now: { self.now })
        await model.refresh()
        fail = true
        await model.refresh()
        XCTAssertEqual(model.matches.map(\.id), ["saved"])
        XCTAssertEqual(model.lastCatalogCheck, now)
        XCTAssertTrue(model.refreshFailed)
        XCTAssertNotNil(model.catalogNotice(at: now))
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isRefreshing)
    }

    func testAuthoritativeEmptyClearsPreviousRowsButPartialRetainsOmissions() async {
        var next = snapshot([event("saved")])
        let model = MatchListViewModel(fetchSnapshot: { next }, now: { self.now })
        await model.refresh()
        next = snapshot([event("new")], partial: true)
        await model.refresh()
        XCTAssertEqual(Set(model.matches.map(\.id)), ["saved", "new"])
        XCTAssertTrue(model.isPartialCatalog)
        next = snapshot([])
        await model.refresh()
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertFalse(model.refreshFailed)
        XCTAssertFalse(model.isPartialCatalog)
        XCTAssertNil(model.error)
    }

    func testOverlappingRefreshIsCoalescedEvenWithExistingRows() async {
        let began = expectation(description: "catalog request")
        var continuation: CheckedContinuation<LiveCatalogSnapshot, Error>?
        var calls = 0
        let model = MatchListViewModel(fetchSnapshot: {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0; began.fulfill() }
        }, now: { self.now })
        model.matches = [event("cached")]
        let first = Task { await model.refresh() }
        await fulfillment(of: [began], timeout: 2)
        XCTAssertTrue(model.isRefreshing)
        XCTAssertFalse(model.isLoading)
        await model.refresh()
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: snapshot([event("fresh")]))
        await first.value
        XCTAssertEqual(model.matches.map(\.id), ["fresh"])
    }

    func testForegroundRefreshIsBoundedButChecksImmediatelyAfterTimeAway() async {
        var clock = now
        var calls = 0
        let model = MatchListViewModel(fetchSnapshot: {
            calls += 1
            return self.snapshot([self.event("current")], at: clock)
        }, now: { clock })
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 1)
        clock = now.addingTimeInterval(10)
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 1, "Cold launch and rapid scene changes share the same request")
        clock = now.addingTimeInterval(601)
        XCTAssertNil(model.catalogNotice(at: clock), "Age alone is silent while automatic refresh catches up")
        XCTAssertEqual(model.lastCatalogCheck, now, "Suppressing routine copy must not invent a new receipt")
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.lastCatalogCheck, clock)
    }

    func testForegroundFailurePreservesWarningAndOldReceiptUntilSuccessfulCheck() async {
        var clock = now
        var fails = false
        var calls = 0
        let model = MatchListViewModel(fetchSnapshot: {
            calls += 1
            if fails { throw URLError(.notConnectedToInternet) }
            return self.snapshot([self.event("kept")], at: clock)
        }, now: { clock })
        await model.refreshIfNeeded()
        clock = now.addingTimeInterval(900)
        fails = true
        await model.refreshIfNeeded()
        XCTAssertTrue(model.refreshFailed)
        XCTAssertEqual(model.lastCatalogCheck, now)
        XCTAssertEqual(model.catalogNotice(at: clock), "Couldn't refresh. Broadcasts may have changed.")
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 2, "A failed refresh must not turn scene changes into a retry storm")
        fails = false
        clock = clock.addingTimeInterval(90)
        await model.refreshIfNeeded()
        XCTAssertFalse(model.refreshFailed)
        XCTAssertNil(model.catalogNotice(at: clock))
        XCTAssertEqual(model.lastCatalogCheck, clock)
    }

    func testCancellationAllowsImmediateForegroundRetryAndPartialStaysOffCustomerUI() async {
        var calls = 0
        let model = MatchListViewModel(fetchSnapshot: {
            calls += 1
            if calls == 1 { throw CancellationError() }
            return self.snapshot([self.event("kept")], partial: true)
        }, now: { self.now })
        model.matches = [event("cached")]
        XCTAssertNil(model.catalogNotice(at: now), "A warm cache is not itself a user-facing error")
        await model.refreshIfNeeded()
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(model.isPartialCatalog, "Partial mirror coverage remains available as internal telemetry")
        XCTAssertNil(model.catalogNotice(at: now), "A mirror miss is not proof of missing user-visible content")
        XCTAssertEqual(Set(model.matches.map(\.id)), ["cached", "kept"])
    }

    func testRepeatedPartialReceiptsRemainSilentForCustomers() async {
        var clock = now
        let model = MatchListViewModel(fetchSnapshot: {
            self.snapshot([self.event("kept")], at: clock, partial: true)
        }, now: { clock })

        await model.refresh()
        XCTAssertNil(model.catalogNotice(at: clock))

        await model.refresh()
        XCTAssertNil(model.catalogNotice(at: clock))

        clock = now.addingTimeInterval(60)
        await model.refresh()
        XCTAssertTrue(model.isPartialCatalog)
        XCTAssertNil(model.catalogNotice(at: clock), "A new partial receipt must not create permanent Home furniture")
    }

    func testCancellationRejectsLateProviderAndSchedulePublication() async {
        let began = expectation(description: "catalog request")
        var continuation: CheckedContinuation<LiveCatalogSnapshot, Error>?
        let model = MatchListViewModel(fetchSnapshot: {
            try await withCheckedThrowingContinuation { continuation = $0; began.fulfill() }
        }, now: { self.now })
        model.matches = [event("saved")]
        let task = Task { await model.refresh() }
        await fulfillment(of: [began], timeout: 2)
        task.cancel()
        continuation?.resume(returning: snapshot([event("late")]))
        await task.value
        XCTAssertEqual(model.matches.map(\.id), ["saved"])
        XCTAssertNil(model.lastCatalogCheck)
        XCTAssertFalse(model.refreshFailed)
        XCTAssertFalse(model.isRefreshing)
    }

    func testOlderReceiptCannotRewindAcceptedCatalog() async {
        var next = snapshot([event("new")])
        let model = MatchListViewModel(fetchSnapshot: { next }, now: { self.now })
        await model.refresh()
        next = snapshot([event("old")], at: now.addingTimeInterval(-60))
        await model.refresh()
        XCTAssertEqual(model.matches.map(\.id), ["new"])
        XCTAssertEqual(model.lastCatalogCheck, now)
    }

    func testRainDelayedCPLSharesEightHourDiscoveryAndExpiryWindow() {
        let row = EventReference(id: "cpl-2026-test", title: "Trinbago Knight Riders vs Guyana Amazon Warriors",
            category: "cricket", date: Int64(now.addingTimeInterval(-7 * 3600).timeIntervalSince1970),
            poster: nil, popular: false, teams: nil, sources: [])
        XCTAssertEqual(row.estimatedMatchDuration, CatalogTimingPolicy.cplWindow)
        XCTAssertFalse(row.isPastEstimatedMatchWindow(at: now))
        XCTAssertEqual(HomeSportsDiscovery(events: [row], now: now).items.first?.phase, .listedNow)
        XCTAssertTrue(row.isPastEstimatedMatchWindow(at: now.addingTimeInterval(3600)))
        XCTAssertTrue(HomeSportsDiscovery(events: [row], now: now.addingTimeInterval(3600)).items.isEmpty)
    }
}
