import XCTest
@testable import Fotty

@MainActor
final class SportsCatalogRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_600_000)

    private func event(_ id: String, at date: Date? = nil) -> EventReference {
        .init(id: id, title: "\(id) Home vs \(id) Away", category: "football",
              date: Int64((date ?? now).timeIntervalSince1970), poster: nil, popular: false,
              teams: nil)
    }

    /// A current sports schedule whose one match starts within Home's window.
    private func sports(_ id: String, at clock: Date? = nil) -> SportsFixtureCatalog.Snapshot {
        ScheduleTestFixtures.sports(kickoff: (clock ?? now).addingTimeInterval(3600), checkedAt: clock ?? now, ids: [id])
    }

    // MARK: Refresh mechanics (schedule lanes since the shared catalog closed)

    func testConcurrentRefreshCallersJoinOneScheduleRefresh() async {
        var fetches = 0
        var blocks = true
        var release: CheckedContinuation<Void, Never>?
        let entered = XCTestExpectation(description: "first schedule fetch entered")
        let model = MatchListViewModel(refreshSports: {
            fetches += 1
            if blocks { await withCheckedContinuation { release = $0; entered.fulfill() } }
            return self.sports("joined")
        }, now: { self.now })
        let first = Task { await model.refresh() }
        await fulfillment(of: [entered], timeout: 5)
        let second = Task { () -> Bool in
            await model.refresh()
            return model.matches.contains { $0.id == "sports-fixture:nba:joined" }
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fetches, 1)
        blocks = false
        release?.resume()
        await first.value
        let secondSawResult = await second.value
        XCTAssertTrue(secondSawResult, "A joined caller returns only after the in-flight refresh published")
        XCTAssertEqual(fetches, 1, "Joined callers do not start a second fetch")
        await model.refresh()
        XCTAssertEqual(fetches, 2, "A later refresh after completion fetches again")
    }

    func testForegroundRefreshIsBoundedButChecksImmediatelyAfterTimeAway() async {
        var clock = now
        var calls = 0
        let model = MatchListViewModel(refreshSports: { calls += 1; return self.sports("current", at: clock) },
                                       now: { clock })
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 1)
        clock = now.addingTimeInterval(10)
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 1, "Cold launch and rapid scene changes share the same request")
        clock = now.addingTimeInterval(91)
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 2)
    }

    func testCancelledRefreshAllowsImmediateRetryAndPublishesNothingLate() async {
        var calls = 0
        var release: CheckedContinuation<Void, Never>?
        let began = expectation(description: "schedule request")
        let model = MatchListViewModel(refreshSports: {
            calls += 1
            if calls == 1 { await withCheckedContinuation { release = $0; began.fulfill() } }
            return self.sports(calls == 1 ? "late" : "retried")
        }, now: { self.now })
        model.matches = [event("saved")]
        let task = Task { await model.refresh() }
        await fulfillment(of: [began], timeout: 2)
        task.cancel()
        release?.resume()
        await task.value
        XCTAssertFalse(model.matches.contains { $0.id == "sports-fixture:nba:late" },
                       "A cancelled refresh cannot publish its late schedule")
        XCTAssertFalse(model.isRefreshing)
        await model.refreshIfNeeded()
        XCTAssertEqual(calls, 2, "Cancellation does not spend the foreground throttle")
        XCTAssertEqual(model.matches.map(\.id), ["sports-fixture:nba:retried"])
    }

    func testRefreshReplacesRowsRestoredFromCacheEvenWhenNoScheduleChanged() async {
        let model = MatchListViewModel(refreshSports: { nil }, now: { self.now })
        model.matches = [event("cached-before-27-october")]
        await model.refresh()
        XCTAssertTrue(model.matches.isEmpty, "Home rows come only from the current schedules")
        XCTAssertNil(model.catalogNotice(at: now), "No schedule failure is shown as a refresh error")
    }

    func testOnlyAStaleCPLScheduleProducesTheHomeNotice() {
        let model = MatchListViewModel(now: { self.now })
        XCTAssertNil(model.catalogNotice(at: now, displaysCPLSchedule: false))
        XCTAssertEqual(model.catalogNotice(at: now, displaysCPLSchedule: true), "CPL start times may have changed.",
                       "Without a fresh CPL receipt, displayed CPL times are flagged")
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
        XCTAssertEqual(elapsed.broadcastTiming(at: now), .available)
        XCTAssertEqual(HomeSportsDiscovery(events: rows, now: now).items.first { $0.event.id == elapsed.id }?.phase, .listedNow)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: elapsed, at: now), .awaitingConfirmation)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: elapsed, in: rows, at: now))
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: future.event(), at: now), .upcoming)

        let provider = EventReference(id: "nfl-provider", title: "Seattle Seahawks vs Los Angeles Rams", category: "american-football",
            date: Int64(now.addingTimeInterval(-3600).timeIntervalSince1970), poster: nil, popular: false,
            teams: nil)
        XCTAssertEqual(provider.broadcastTiming(at: now), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: provider, at: now), .awaitingConfirmation,
                       "A provider listing must not claim confirmed live play")
        let channel = EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: channel, at: now), .channel)
        let unknownTime = EventReference(id: "unknown", title: "India vs West Indies", category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: unknownTime, at: now), .timeToBeConfirmed)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: event("official"), at: now, status: .inPlay), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: event("official"), at: now, status: .scheduled), .awaitingConfirmation)
    }

    func testVerifiedScheduleReplacesStaleProviderRows() async throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first)
        let time = fixture.kickoff.addingTimeInterval(-1800)
        let planned = fixture.event()
        let stale = EventReference(id: "old-provider", title: planned.title, category: "cricket", date: planned.date,
            poster: nil, popular: false, teams: planned.teams)
        let model = MatchListViewModel(refreshSchedule: {
                self.cplSnapshot([fixture], checkedAt: time)
            }, now: { time })
        model.matches = [stale]
        await model.refresh()
        XCTAssertEqual(model.matches.map(\.id), [fixture.id])
    }

    func testReplayedScheduleCannotReplaceCPLWithOlderOrUnverifiedSchedule() async throws {
        for status in [CPLSchedule.SourceStatus.verified, .lastKnownGood] {
            let original = CPLSchedule.Fixture(1,
                ISO8601DateFormatter().string(from: now.addingTimeInterval(7200)), .trinbago, .saintLucia)
            var schedule = cplSnapshot([original])
            let model = MatchListViewModel(refreshSchedule: { schedule }, now: { self.now })
            await model.refresh()
            let changed = CPLSchedule.Fixture(1,
                ISO8601DateFormatter().string(from: now.addingTimeInterval(9000)), .trinbago, .saintLucia)
            schedule = cplSnapshot([changed], checkedAt: now.addingTimeInterval(status == .verified ? -60 : 60),
                                   status: status)
            await model.refresh()

            XCTAssertEqual(model.cplScheduleCheckedAt, now)
            XCTAssertEqual(model.cplScheduleSourceStatus, .verified)
            XCTAssertEqual(model.matches.first { $0.id == original.id }?.kickoffDate, original.kickoff)
        }
    }

    func testLastKnownGoodCPLScheduleNeverClaimsCurrentVerification() async throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first { $0.kickoff > now })
        let model = MatchListViewModel(
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

    func testRainDelayedCPLSharesEightHourDiscoveryAndExpiryWindow() {
        let row = EventReference(id: "cpl-2026-test", title: "Trinbago Knight Riders vs Guyana Amazon Warriors",
            category: "cricket", date: Int64(now.addingTimeInterval(-7 * 3600).timeIntervalSince1970),
            poster: nil, popular: false, teams: nil)
        XCTAssertEqual(row.estimatedMatchDuration, CatalogTimingPolicy.cplWindow)
        XCTAssertFalse(row.isPastEstimatedMatchWindow(at: now))
        XCTAssertEqual(HomeSportsDiscovery(events: [row], now: now).items.first?.phase, .listedNow)
        XCTAssertTrue(row.isPastEstimatedMatchWindow(at: now.addingTimeInterval(3600)))
        XCTAssertTrue(HomeSportsDiscovery(events: [row], now: now.addingTimeInterval(3600)).items.isEmpty)
    }
}
