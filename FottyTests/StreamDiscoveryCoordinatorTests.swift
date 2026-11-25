import XCTest
@testable import Fotty

final class FixtureProviderPreflightScheduleTests: XCTestCase {
    func testInterleavedFixturesEachVisitEveryProviderInsteadOfAliasingGlobalCursor() {
        var rotation = FixtureProviderPreflightSchedule()
        let providers = ["cs", "as", "fs", "sv"]
        var visits: [String: Set<String>] = [:]
        for _ in 0..<2 {
            for fixture in ["first", "second"] {
                visits[fixture, default: []].formUnion(rotation.takeProviders(for: fixture, available: providers))
            }
        }
        XCTAssertEqual(visits["first"], Set(providers))
        XCTAssertEqual(visits["second"], Set(providers))
        var triple = FixtureProviderPreflightSchedule()
        let six = providers + ["cnc", "score808"]
        var rounds: [String: Set<String>] = [:]
        for _ in 0..<3 { for fixture in ["a", "b", "c"] {
            rounds[fixture, default: []].formUnion(triple.takeProviders(for: fixture, available: six))
        } }
        XCTAssertTrue(rounds.values.allSatisfy { $0 == Set(six) })
    }

    func testRevocationReorderAndCapacityKeepBoundedIndependentProgress() {
        var rotation = FixtureProviderPreflightSchedule(capacity: 2)
        XCTAssertEqual(rotation.takeProviders(for: "a", available: ["cs", "as", "fs"]), ["cs", "as"])
        XCTAssertEqual(rotation.takeProviders(for: "a", available: ["as", "fs", "sv"]), ["fs", "as"])
        _ = rotation.takeProviders(for: "b", available: ["cs"])
        _ = rotation.takeProviders(for: "c", available: ["as"])
        XCTAssertEqual(rotation.retainedFixtureCount, 2)
        XCTAssertEqual(rotation.takeProviders(for: "a", available: ["sv", "fs"]), ["sv", "fs"])
        XCTAssertTrue(rotation.takeProviders(for: "a", available: []).isEmpty)
        XCTAssertEqual(rotation.retainedFixtureCount, 1)
    }
}

final class FixtureStreamPreflightScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_548_400)

    func testCatalogTaskReplacementPreservesRotationAndReservedDeadline() {
        var schedule = FixtureStreamPreflightSchedule()
        XCTAssertEqual(schedule.takeNextID(from: ["first", "second"], at: now), "first")
        let reserved = schedule.nextDueAt
        // A replacement task sees the same view state. A catalog refresh at
        // 89seconds must neither repeat the first row nor add another90seconds.
        XCTAssertNil(schedule.takeNextID(from: ["first", "second"], at: now.addingTimeInterval(89)))
        XCTAssertEqual(schedule.nextDueAt, reserved)
        XCTAssertEqual(schedule.delay(at: now.addingTimeInterval(89)), 1)
        XCTAssertEqual(schedule.takeNextID(from: ["first", "second"], at: now.addingTimeInterval(90)), "second")
        XCTAssertEqual(schedule.takeNextID(from: ["first", "second"], at: now.addingTimeInterval(180)), "first")
    }

    func testReorderRemovalAndNewFixturesDoNotRestartAtFirstCatalogRow() {
        var schedule = FixtureStreamPreflightSchedule()
        XCTAssertEqual(schedule.takeNextID(from: ["a", "b", "c"], at: now), "a")
        XCTAssertEqual(schedule.takeNextID(from: ["c", "a", "b"], at: now.addingTimeInterval(90)), "b")
        // Removed b is dropped; new d joins the tail behind pending c and a.
        XCTAssertEqual(schedule.takeNextID(from: ["d", "a", "c"], at: now.addingTimeInterval(180)), "c")
        XCTAssertEqual(schedule.takeNextID(from: ["d", "a", "c"], at: now.addingTimeInterval(270)), "a")
        XCTAssertEqual(schedule.takeNextID(from: ["d", "a", "c"], at: now.addingTimeInterval(360)), "d")
    }

    func testCancellationReservationSurvivesEmptyCatalogAndClockRegression() {
        var schedule = FixtureStreamPreflightSchedule()
        XCTAssertNil(schedule.takeNextID(from: [], at: now))
        XCTAssertEqual(schedule.takeNextID(from: ["a", "a", "b"], at: now), "a")
        // A cancelled lookup still spent its start opportunity. Losing all
        // rows or moving the wall clock back cannot release that reservation.
        XCTAssertNil(schedule.takeNextID(from: [], at: now.addingTimeInterval(10)))
        XCTAssertNil(schedule.takeNextID(from: ["b"], at: now.addingTimeInterval(-1)))
        XCTAssertNil(schedule.takeNextID(from: ["b"], at: now.addingTimeInterval(89)))
        XCTAssertEqual(schedule.takeNextID(from: ["b"], at: now.addingTimeInterval(90)), "b")
        XCTAssertEqual(schedule.delay(at: now.addingTimeInterval(300)), 90,
                       "An ineligible/playing screen must not poll in a tight loop after a due time passes")
    }
}

@MainActor
final class FixtureStreamDiscoveryIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_548_400)

    func testPriorFindSurvivesTheSixtyNinetyGapWithoutReusingExpiredSessions() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
        index.complete(ticket, sessions: [try session(for: request)], at: now)
        XCTAssertNotNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(59)))
        for seconds in [60.0, 89.0] {
            let time = now.addingTimeInterval(seconds)
            XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: time))
            let state = try XCTUnwrap(index.summary(for: request, at: time)?.providers.first)
            XCTAssertEqual(state.compatibleCandidateCount, 0)
            XCTAssertEqual(state.outcome, .stale)
            XCTAssertEqual(state.lastCandidateFoundAt, now)
            XCTAssertNil(index.begin(for: request, providerCode: "communitysports", preflight: true, at: time))
        }
        let recheck = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true,
                                              at: now.addingTimeInterval(90)))
        XCTAssertEqual(index.summary(for: request, at: now.addingTimeInterval(90))?.providers.first?.lastCandidateFoundAt, now)
        index.abandon(recheck)
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(90)))
        XCTAssertEqual(index.summary(for: request, at: now.addingTimeInterval(90))?.providers.first?.lastCandidateFoundAt, now,
                       "Cancelling a recheck may preserve a prior find, not the old delivery or an in-flight lease")
        XCTAssertFalse(index.summary(for: request, at: now.addingTimeInterval(90))?.isChecking ?? true)
    }

    func testConfirmedReadinessSurvivesDescriptorGapAndExpiresAfterFiveMinutes() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
        index.complete(ticket, sessions: [try session(for: request)], at: now)
        for seconds in [59.0, 60.0, 89.0, 90.0, 299.0, 300.0] {
            let at = now.addingTimeInterval(seconds)
            let provider = try XCTUnwrap(index.summary(for: request, at: at)?.providers.first)
            XCTAssertEqual(provider.hasRecentlyConfirmedBroadcast(at: at), seconds < 300)
            if seconds >= 60 {
                XCTAssertEqual(provider.compatibleCandidateCount, 0)
                XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: at),
                             "Stable availability cannot extend a descriptor/binding or lend its URL to a new attempt")
            }
        }
    }

    func testEmptyOrDefinitiveFailedRecheckClearsConfirmedReadinessWithoutErasingDescriptiveHistory() throws {
        for failed in [false, true] {
            let index = FixtureStreamDiscoveryIndex(), request = request()
            let first = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
            index.complete(first, sessions: [try session(for: request)], at: now)
            let at = now.addingTimeInterval(90)
            let recheck = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: at))
            let checking = try XCTUnwrap(index.summary(for: request, at: at)?.providers.first)
            XCTAssertEqual(checking.outcome, .checking)
            XCTAssertTrue(checking.hasRecentlyConfirmedBroadcast(at: at))
            index.complete(recheck, sessions: [], failure: failed ? failure(.invalidMatchMapping) : nil, at: at)
            let completed = try XCTUnwrap(index.summary(for: request, at: at)?.providers.first)
            XCTAssertFalse(completed.hasRecentlyConfirmedBroadcast(at: at))
            XCTAssertNil(completed.lastConfirmedAvailableAt)
            XCTAssertEqual(completed.lastCandidateFoundAt, now)
            XCTAssertEqual(completed.outcome, failed ? .failed(.invalidMatchMapping) : .empty)
            XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: at))
        }
    }

    func testUnconfirmedRecheckPreservesOnlyTheOriginalAvailabilityReceipt() throws {
        let failures = [failure(.providerTimeout), failure(.manifestUnreachable), failure(.manifestInvalid),
            LiveStreamResolver.communitySportsFailure(from: .httpFailure(statusCode: 503, stage: .streams)),
            LiveStreamResolver.communitySportsFailure(from: .transportFailure(code: URLError.serverCertificateUntrusted.rawValue, stage: .metadata)),
            LiveStreamResolver.communitySportsFailure(from: .invalidJSON(stage: .metadata))]
        for failed in failures {
            let index = FixtureStreamDiscoveryIndex(), request = request()
            let first = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
            index.complete(first, sessions: [try session(for: request)], at: now)
            let at = now.addingTimeInterval(20)
            let retry = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: at))
            index.complete(retry, sessions: [], failure: failed, at: at)
            let summary = try XCTUnwrap(index.summary(for: request, at: at)?.providers.first)
            XCTAssertTrue(summary.hasRecentlyConfirmedBroadcast(at: at))
            XCTAssertEqual(summary.lastConfirmedAvailableAt, now)
            XCTAssertNil(summary.availabilityWithdrawalAt)
            XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: at),
                         "An unconfirmed recheck must not retain an old delivery")
            XCTAssertTrue(summary.hasRecentlyConfirmedBroadcast(at: now.addingTimeInterval(299)))
            XCTAssertFalse(summary.hasRecentlyConfirmedBroadcast(at: now.addingTimeInterval(300)),
                           "A transient failure cannot renew the original five-minute receipt")
        }
    }

    func testDefinitiveWithdrawalSurvivesPendingAndUnconfirmedRechecks() throws {
        let negatives = [failure(.providerReturnedEmpty), failure(.invalidMatchMapping), failure(.providerSecurityFailure),
            LiveStreamResolver.communitySportsFailure(from: .unsafeResponse),
            LiveStreamResolver.communitySportsFailure(from: .streamAdmissionRejected(entryCount: 2)),
            LiveStreamResolver.communitySportsFailure(from: .httpFailure(statusCode: 404, stage: .streams))]
        for negative in negatives {
            let index = FixtureStreamDiscoveryIndex(), request = request()
            let first = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
            index.complete(first, sessions: [], failure: negative, at: now)
            let at = now.addingTimeInterval(20)
            let retry = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: at))
            XCTAssertEqual(index.summary(for: request, at: at)?.providers.first?.availabilityWithdrawalAt, now)
            index.complete(retry, sessions: [], failure: failure(.providerTimeout), at: at)
            let summary = try XCTUnwrap(index.summary(for: request, at: at)?.providers.first)
            XCTAssertEqual(summary.availabilityWithdrawalAt, now)
            XCTAssertFalse(summary.hasRecentlyConfirmedBroadcast(at: at))
            let cancelledAt = now.addingTimeInterval(30)
            let cancelled = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: cancelledAt))
            index.abandon(cancelled)
            XCTAssertEqual(index.summary(for: request, at: cancelledAt)?.providers.first?.availabilityWithdrawalAt, now)
        }
    }

    func testClockRollbackCannotReestablishReadinessFromAnOlderConfirmedDescriptor() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(ticket, sessions: [try session(for: request)], at: now)
        _ = index.summary(for: request, at: now.addingTimeInterval(120))
        let rolledBack = now.addingTimeInterval(90)
        let state = try XCTUnwrap(index.summary(for: request, at: rolledBack)?.providers.first)
        XCTAssertEqual(state.outcome, .stale)
        XCTAssertEqual(state.compatibleCandidateCount, 0)
        XCTAssertNil(state.lastCandidateFoundAt)
        XCTAssertFalse(state.hasRecentlyConfirmedBroadcast(at: rolledBack))
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: rolledBack))
    }

    func testTestDayRolloverFencesPendingAndConfirmedSourceEvidenceWhileBreakChangesDoNot() throws {
        func testRequest(day: Int, ordinal: Int = 3, phase: CricketMatchContext.Phase = .inPlay) -> StreamPlaybackRequest {
            let home = "icc:1:7", away = "icc:1:1"
            let context = CricketMatchContext(innings: [.init(number: 1, teamID: home, runs: 100, wickets: 2)],
                currentInnings: 1, day: day, session: 2, matchOrdinal: ordinal,
                matchEndsAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(2 * 86_400)), phase: phase)
            let metadata = CricketFixtureMetadata(fixtureID: "icc:269792", competitionID: "icc",
                competitionName: "Australia in South Africa, 3 Test Series, 2026", format: .test,
                status: .live, observedAt: now, verified: true, context: context, homeTeamID: home, awayTeamID: away)
            return StreamPlaybackRequest(event: .init(id: "cricket-fixture:icc:269792", title: "South Africa vs Australia",
                category: "cricket", date: Int64(now.addingTimeInterval(-3 * 86_400).timeIntervalSince1970),
                poster: nil, popular: false,
                teams: .init(home: .init(name: "South Africa", badge: nil), away: .init(name: "Australia", badge: nil)), cricketFixture: metadata, competitionID: "icc"))
        }
        let index = FixtureStreamDiscoveryIndex(), day3 = testRequest(day: 3), day4 = testRequest(day: 4)
        let original = try XCTUnwrap(index.begin(for: day3, providerCode: "communitysports", preflight: false, at: now))
        let oldSession = try session(for: day3)
        index.complete(original, sessions: [oldSession], at: now)
        XCTAssertNotNil(index.cachedSessions(for: testRequest(day: 3, phase: .lunch), providerCode: "communitysports", at: now))
        for changed in [day4, testRequest(day: 3, ordinal: 2)] {
            XCTAssertNil(index.summary(for: changed, at: now))
            XCTAssertNil(index.cachedSessions(for: changed, providerCode: "communitysports", at: now))
            XCTAssertFalse(oldSession.eventBinding?.matches(request: changed, providerCode: "communitysports", at: now) ?? true)
        }
        let next = try XCTUnwrap(index.begin(for: day4, providerCode: "communitysports", preflight: false, at: now))
        index.complete(next, sessions: [oldSession], at: now)
        let rejected = try XCTUnwrap(index.summary(for: day4, at: now)?.providers.first)
        XCTAssertEqual(rejected.compatibleCandidateCount, 0)
        XCTAssertFalse(rejected.hasRecentlyConfirmedBroadcast(at: now), "A late Day3 descriptor cannot become Day4 readiness")
    }

    func testRotatingFixturesRetainSeparateBoundedPriorFindsWithoutResettingCooldown() throws {
        let index = FixtureStreamDiscoveryIndex(capacity: 3), first = request(id: "first")
        let start = try XCTUnwrap(index.begin(for: first, providerCode: "communitysports", preflight: true, at: now))
        index.complete(start, sessions: [try session(for: first)], at: now)
        for (offset, id) in [(90.0, "second"), (180.0, "third")] {
            let time = now.addingTimeInterval(offset), next = request(id: id)
            let ticket = try XCTUnwrap(index.begin(for: next, providerCode: "communitysports", preflight: true, at: time))
            index.complete(ticket, sessions: [], at: time)
            XCTAssertEqual(index.summary(for: first, at: time)?.providers.first?.lastCandidateFoundAt, now)
            XCTAssertNil(index.cachedSessions(for: first, providerCode: "communitysports", at: time))
            XCTAssertNil(index.summary(for: next, at: time)?.providers.first?.lastCandidateFoundAt,
                         "A sibling fixture cannot borrow the first fixture's find")
            XCTAssertNil(index.begin(for: first, providerCode: "communitysports", preflight: true,
                                     at: time.addingTimeInterval(89)))
        }
        XCTAssertEqual(index.retainedRecordCount, 3)
        XCTAssertNil(index.summary(for: first, at: now.addingTimeInterval(FixtureStreamDiscoveryIndex.priorFoundLifetime))?
            .providers.first?.lastCandidateFoundAt)
    }

    func testRevokedEnablementInvalidatesPositiveAndLateSnapshotCannotRestoreIt() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        XCTAssertFalse(index.hasLoadedProviderEnablement)
        XCTAssertTrue(index.enabledProviderCodes.isEmpty)
        index.updateEnabledProviders(["communitysports"], revision: 1)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
        index.complete(ticket, sessions: [try session(for: request)], at: now)
        index.updateEnabledProviders([], revision: 3, invalidating: "communitysports")
        index.updateEnabledProviders(["communitysports"], revision: 2)
        XCTAssertTrue(index.enabledProviderCodes.isEmpty)
        XCTAssertNil(index.summary(for: request, at: now))
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now))
        index.complete(ticket, sessions: [try session(for: request)], at: now)
        XCTAssertNil(index.summary(for: request, at: now))
        index.updateEnabledProviders(["communitysports"], revision: 4)
        XCTAssertNil(index.begin(for: request, providerCode: "communitysports", preflight: true,
                                 at: now.addingTimeInterval(89)), "A source toggle cannot replenish proactive requests")
        XCTAssertNotNil(index.begin(for: request, providerCode: "communitysports", preflight: false,
                                    at: now.addingTimeInterval(89)), "Explicit manual checking retains its existing separate admission")
    }

    func testNewManualGenerationSupersedesCompletionAndAbandonFromOlderRequest() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let old = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        let current = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.abandon(old)
        let stale = try session(for: request, suffix: "old")
        index.complete(old, sessions: [stale], at: now)
        XCTAssertTrue(index.summary(for: request, at: now)?.isChecking == true)
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now))
        let expected = try session(for: request, suffix: "current")
        index.complete(current, sessions: [expected], at: now)
        index.complete(old, sessions: [stale], at: now)
        index.abandon(current)
        XCTAssertEqual(index.cachedSessions(for: request, providerCode: "communitysports", at: now)?.map(\.id), [expected.id])
        XCTAssertEqual(index.summary(for: request, at: now)?.providers.first?.outcome, .candidates)
    }

    func testExactRequestKeyPreservesOpponentDateSquadAndCricketFormat() throws {
        let index = FixtureStreamDiscoveryIndex(), original = request()
        let ticket = try XCTUnwrap(index.begin(for: original, providerCode: "communitysports", preflight: false, at: now))
        index.complete(ticket, sessions: [try session(for: original)], at: now)
        for changed in [request(away: "Chelsea"), request(kickoff: now.addingTimeInterval(60)),
                        request(home: "Ipswich Town Women", away: "Liverpool Women"),
                        request(competition: "carabao-cup"), request(gender: .women)] {
            XCTAssertNil(index.cachedSessions(for: changed, providerCode: "communitysports", at: now))
            XCTAssertNil(index.summary(for: changed, at: now))
        }
        let cricket = request(id: "cricket-fixture:format", home: "England", away: "India", sport: "cricket", format: .t20)
        let cricketTicket = try XCTUnwrap(index.begin(for: cricket, providerCode: "communitysports", preflight: false, at: now))
        index.complete(cricketTicket, sessions: [try session(for: cricket)], at: now)
        let otherFormat = request(id: "cricket-fixture:format", home: "England", away: "India", sport: "cricket", format: .odi)
        XCTAssertNil(index.cachedSessions(for: otherFormat, providerCode: "communitysports", at: now))
        XCTAssertNil(index.summary(for: otherFormat, at: now))
    }

    func testPositiveExpiryBindingExpiryAndClockRegressionCannotExtendCache() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(ticket, sessions: [try session(for: request)], at: now)
        XCTAssertNotNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(59)))
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(60)))
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(1)))
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(-1)))
        let short = FixtureStreamDiscoveryIndex()
        let shortTicket = try XCTUnwrap(short.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        short.complete(shortTicket, sessions: [try session(for: request, expiresAt: now.addingTimeInterval(20))], at: now)
        XCTAssertNil(short.cachedSessions(for: request, providerCode: "communitysports", at: now.addingTimeInterval(20)))
        XCTAssertEqual(short.summary(for: request, at: now.addingTimeInterval(20))?.compatibleCandidateCount, 0)
        XCTAssertEqual(short.summary(for: request, at: now.addingTimeInterval(20))?.providers.first?.outcome, .stale)
    }

    func testNegativeObservationNeverBlocksManualRetryWhenStreamAppearsLater() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
        index.complete(ticket, sessions: [], failure: failure(.providerReturnedEmpty), at: now)
        XCTAssertEqual(index.summary(for: request, at: now)?.providers.first?.outcome, .failed(.providerReturnedEmpty))
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now))
        let retry = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(retry, sessions: [try session(for: request)], at: now)
        XCTAssertEqual(index.summary(for: request, at: now)?.compatibleCandidateCount, 1)
        XCTAssertEqual(index.summary(for: request, at: now)?.providers.first?.outcome, .candidates,
                       "A discovered candidate is not decoded playback or guaranteed availability")
        XCTAssertNotNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now))
    }

    func testUnboundReviewedChoiceCanBeSummarizedButCannotBeReused() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        let choice = try session(for: request, bound: false)
        index.complete(ticket, sessions: [choice], failure: failure(.providerTimeout), at: now)
        XCTAssertEqual(index.summary(for: request, at: now)?.compatibleCandidateCount, 1)
        XCTAssertEqual(index.summary(for: request, at: now)?.providers.first?.failureCategory, .providerTimeout)
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now))
        let wrong = try session(for: self.request(id: "other"))
        let again = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        let otherProvider = StreamSession(matchID: request.matchID, playableURL: choice.playableURL,
            streamType: .hls, providerName: "AS1", createdAt: now)
        let unchecked = StreamSession(matchID: request.matchID, playableURL: choice.playableURL,
            streamType: .hls, providerName: "CS1", validationStatus: .pending, createdAt: now)
        index.complete(again, sessions: [wrong, otherProvider, unchecked], at: now)
        XCTAssertEqual(index.summary(for: request, at: now)?.compatibleCandidateCount, 0)
    }

    func testExplicitEmptyDescriptorRemainsEmptyButRejectedDeliveryKeepsFailure() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        for (reason, outcome) in [("stream_entries_empty", FixtureStreamDiscoveryIndex.Outcome.empty),
                                  ("no_admitted_stream_delivery", .failed(.providerReturnedEmpty))] {
            let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
            let result = StreamFailure(providerName: "CS1", category: .providerReturnedEmpty,
                technicalMessage: "Descriptor result", userMessage: "No stream yet", retryable: true,
                fallbackAllowed: true, redactedMetadata: ["manifest_result": reason])
            index.complete(ticket, sessions: [], failure: result, at: now)
            XCTAssertEqual(index.summary(for: request, at: now)?.providers.first?.outcome, outcome)
            XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: now))
        }
    }

    func testPreflightProviderCooldownInflightAndInvalidationDoNotBlockManual() throws {
        let index = FixtureStreamDiscoveryIndex(), request = request()
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now))
        XCTAssertNil(index.begin(for: self.request(id: "other"), providerCode: "communitysports", preflight: true,
                                 at: now.addingTimeInterval(90)), "In-flight same-provider work must not be duplicated")
        index.complete(ticket, sessions: [], at: now.addingTimeInterval(90))
        XCTAssertNil(index.begin(for: request, providerCode: "communitysports", preflight: true,
                                 at: now.addingTimeInterval(90)), "Fresh completion suppresses preflight")
        let manual = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false,
                                              at: now.addingTimeInterval(90)))
        index.invalidate(providerCode: "communitysports")
        index.complete(manual, sessions: [try session(for: request)], at: now.addingTimeInterval(90))
        XCTAssertNil(index.summary(for: request, at: now.addingTimeInterval(90)))
        XCTAssertNil(index.begin(for: request, providerCode: "communitysports", preflight: true,
                                 at: now.addingTimeInterval(179)), "Invalidation does not reset provider cooldown")
        XCTAssertNotNil(index.begin(for: request, providerCode: "communitysports", preflight: true,
                                    at: now.addingTimeInterval(180)))
    }

    func testHourlyPreflightBudgetSurvivesRecordEvictionAndAllowsManual() throws {
        let index = FixtureStreamDiscoveryIndex(capacity: 2)
        for number in 0..<24 {
            let time = now.addingTimeInterval(Double(number * 90))
            let request = request(id: "fixture-\(number)")
            let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: time))
            index.complete(ticket, sessions: [], at: time)
            XCTAssertLessThanOrEqual(index.retainedRecordCount, 2)
        }
        let request = request(id: "over-budget"), attempted = now.addingTimeInterval(24 * 90)
        XCTAssertNil(index.begin(for: request, providerCode: "communitysports", preflight: true, at: attempted))
        let manual = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: attempted))
        index.abandon(manual)
        XCTAssertNotNil(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now.addingTimeInterval(3600)))
        XCTAssertLessThanOrEqual(index.retainedRecordCount, 2)
    }

    func testDailyPreflightBudgetIsSeparateFromHourlyWindow() throws {
        let index = FixtureStreamDiscoveryIndex()
        for number in 0..<96 {
            let seconds = Double(number / 24 * 3600 + number % 24 * 90)
            let time = now.addingTimeInterval(seconds), request = request(id: "daily-\(number)")
            let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: true, at: time))
            index.complete(ticket, sessions: [], at: time)
        }
        let request = request(id: "tomorrow")
        XCTAssertNil(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now.addingTimeInterval(4 * 3600)))
        XCTAssertNotNil(index.begin(for: request, providerCode: "communitysports", preflight: true, at: now.addingTimeInterval(86_400)))
        XCTAssertLessThanOrEqual(index.retainedRecordCount, 24)
    }

    private func request(
        id: String = "fixture", home: String = "Ipswich Town", away: String = "Liverpool",
        sport: String = "football", kickoff: Date? = nil, competition: String? = nil,
        gender: SportsFixtureCatalog.Squad.Gender? = nil, format: CricketFixtureCatalog.Format? = nil
    ) -> StreamPlaybackRequest {
        let start = kickoff ?? now, title = "\(home) vs \(away)"
        let sports = gender.map { gender in
            SportsFixtureMetadata(fixtureID: id, sport: sport, competitionID: competition ?? "premier-league",
                competitionName: "League", eventKind: .match, title: title,
                participants: [.init(id: "home", name: home), .init(id: "away", name: away)],
                squad: .init(gender: gender, ageGroup: "senior"), status: .live, observedAt: now, verified: true)
        }
        let cricket = format.map { format in
            CricketFixtureMetadata(fixtureID: "format", competitionID: "icc", competitionName: "ICC",
                format: format, status: .live, observedAt: now, verified: true)
        }
        let event = EventReference(id: id, title: title, category: sport, date: Int64(start.timeIntervalSince1970),
            poster: nil, popular: false, teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), cricketFixture: cricket, sportsFixture: sports, competitionID: competition)
        return StreamPlaybackRequest(event: event)
    }

    private func session(
        for request: StreamPlaybackRequest, suffix: String = "stream", bound: Bool = true, expiresAt: Date? = nil
    ) throws -> StreamSession {
        let binding = bound ? try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_fixture", streamID: "nuvio_sport_fixture", manifestRevision: "1.0.0",
            verifiedAt: now, expiresAt: expiresAt ?? now.addingTimeInterval(90), at: now)) : nil
        return StreamSession(matchID: request.matchID, playableURL: URL(string: "https://media.example/\(suffix).m3u8")!,
            streamType: .hls, providerName: "CS1", expiryTime: expiresAt, createdAt: now, eventBinding: binding)
    }

    private func failure(_ category: StreamFailureCategory) -> StreamFailure {
        StreamFailure(providerName: "CS1", category: category, technicalMessage: "Metadata result",
            userMessage: "No stream yet", retryable: true, fallbackAllowed: true)
    }
}

final class StreamDiscoveryCoordinatorTests: XCTestCase {
    private var originalHealth: [String: Any] = [:]
    override func setUp() {
        super.setUp()
        originalHealth = Dictionary(uniqueKeysWithValues: ["fotty.live.sourceHealth.v1", "fotty.live.lastGoodProvider.v1"].compactMap { key in
            UserDefaults.standard.object(forKey: key).map { (key, $0) }
        })
        LiveSourceHealthStore.resetForTesting()
    }
    override func tearDown() {
        LiveSourceHealthStore.resetForTesting()
        for (key, value) in originalHealth { UserDefaults.standard.set(value, forKey: key) }
        originalHealth = [:]
        super.tearDown()
    }
    private final class ExpiringChoiceClock: @unchecked Sendable {
        private let lock = NSLock()
        private var first = true
        private let initial: Date
        init(initial: Date) { self.initial = initial }
        func now() -> Date {
            lock.lock(); defer { lock.unlock() }
            defer { first = false }
            return first ? initial : initial.addingTimeInterval(2)
        }
    }

    private actor IncrementalSnapshots {
        private var values: [[StreamSession]] = []

        func append(_ sessions: [StreamSession]) { values.append(sessions) }
        func all() -> [[StreamSession]] { values }
    }

    /// Tests always release this gate after a bounded expectation wait, even
    /// when the expected first publication is missing. No sleeping lane is
    /// needed to establish the ordering under test.
    private actor IncrementalReleaseGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private func session(_ name: String) -> StreamSession {
        StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/\(name)")!,
                      streamType: .unknown, providerName: name)
    }

    private func outcome(_ sessions: [StreamSession], failure: StreamFailure? = nil) -> StreamResolutionOutcome {
        let diagnostics = StreamAttemptDiagnostics(attemptID: "test", matchID: "test",
            matchTitle: "Home v Away", finalState: failure == nil ? .readyToPlay : .failed,
            createdAt: Date(), completedAt: Date(), timeline: [], providerAttempts: [])
        if let failure { return .failure(failure, diagnostics) }
        return .success(StreamResolutionSuccess(attemptID: "test", sessions: sessions, diagnostics: diagnostics))
    }

    func testKnownMediaExpiryIsRecheckedBeforeTheFirstChoiceCanBePublished() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000), clock = ExpiringChoiceClock(initial: now)
        let expiring = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/expiring.m3u8")!,
            streamType: .hls, providerName: "unmeasured-expiry-regression", expiryTime: now.addingTimeInterval(1))
        let first = outcome([expiring]), empty = outcome([]), snapshots = IncrementalSnapshots()
        let report = await StreamDiscoveryCoordinator.collect(lanes: [
            { _ in first },
            { _ in try? await Task.sleep(for: .seconds(60)); return empty }
        ], deadline: .milliseconds(100), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(10),
            clock: { clock.now() }, onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertTrue(published.isEmpty, "A choice admitted before its expiry cannot mount after the discovery hold")
        XCTAssertTrue(report.sessions.isEmpty)
        XCTAssertTrue(report.reachedDeadline)
    }

    func testOnlyForegroundSingleCSOrTVLaneGetsTimeForBoundedMetadataTransport() {
        XCTAssertEqual(StreamDiscoveryCoordinator.defaultDeadline, .seconds(18))
        XCTAssertEqual(StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: false,
            optionalProviderCodes: ["communitysports", "plaviosports"]), .seconds(18))
        XCTAssertEqual(StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: true,
            optionalProviderCodes: ["plaviosports", "flixstreams"]), .seconds(18))
        XCTAssertEqual(StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: false,
            optionalProviderCodes: ["reviewedtv"]), .seconds(18))
        XCTAssertEqual(StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: true,
            optionalProviderCodes: ["reviewedtv"]), .seconds(32))
        let singleCS = StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: true,
            optionalProviderCodes: ["communitysports", "plaviosports"])
        XCTAssertEqual(singleCS, .seconds(32))
        XCTAssertEqual(singleCS, .seconds(CommunitySportsAddonClient.streamTransportDeadline + 8),
            "The parent must accommodate the existing24s stream transport plus bounded metadata")
    }

    func testSingleCSBudgetRetainsLateValidChoiceWhileSiblingPublishesBeforeIt() async {
        // Scale the production budgets20x. Four seconds of metadata plus a20s
        // stream response crosses the former18s owner, within the32s owner.
        let divisor = 20
        let budget = StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: true,
            optionalProviderCodes: ["communitysports", "plaviosports"]) / divisor
        let first = session("AS1"), late = session("CS1")
        let firstOutcome = outcome([first]), lateOutcome = outcome([late]), empty = outcome([])
        let snapshots = IncrementalSnapshots()
        let firstPublished = expectation(description: "Working sibling publishes while CS still resolves")
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [
                { publish in publish(.partialSession(first)); return firstOutcome },
                { _ in
                    do {
                        try await Task.sleep(for: Duration.seconds(4) / divisor)
                        try await Task.sleep(for: Duration.seconds(20) / divisor)
                    } catch { return empty }
                    return lateOutcome
                }
            ], deadline: budget, preferDirectInitialChoice: true,
                initialChoiceGrace: Duration.seconds(6) / divisor, onSessions: { choices in
                    await snapshots.append(choices)
                    if choices.count == 1 { firstPublished.fulfill() }
                })
        }
        await fulfillment(of: [firstPublished], timeout: 1)
        let early = await snapshots.all()
        XCTAssertEqual(early.map { $0.map(\.id) }, [[first.id]])
        let result = await task.value
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id], [first.id, late.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id, late.id])
        XCTAssertFalse(result.reachedDeadline)
        XCTAssertEqual(result.exitReason, .completed)
    }

    func testCancellingExtendedSingleDiscoveryCleansChildrenAndRejectsLateChoice() async {
        let first = session("AS1"), late = session("cancelled-CS1")
        let firstOutcome = outcome([first]), lateOutcome = outcome([late])
        let snapshots = IncrementalSnapshots()
        let firstPublished = expectation(description: "First sibling is already visible")
        let childStopped = expectation(description: "CS child is cancelled without waiting32seconds")
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [
                { publish in publish(.partialSession(first)); return firstOutcome },
                { publish in
                    defer { childStopped.fulfill() }
                    try? await Task.sleep(for: .seconds(60))
                    publish(.session(late))
                    return lateOutcome
                }
            ], deadline: StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: true,
                optionalProviderCodes: ["communitysports"]), onSessions: { choices in
                    await snapshots.append(choices)
                    firstPublished.fulfill()
                })
        }
        await fulfillment(of: [firstPublished], timeout: 1)
        task.cancel()
        let result = await task.value
        await fulfillment(of: [childStopped], timeout: 1)
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id])
        XCTAssertEqual(result.exitReason, .cancelled)
    }

    func testExtendedSingleDeadlineCleansChildrenWithoutLosingPublishedSibling() async {
        let first = session("AS1"), late = session("deadline-CS1")
        let firstOutcome = outcome([first]), lateOutcome = outcome([late]), snapshots = IncrementalSnapshots()
        let childStopped = expectation(description: "The owning deadline cancels the unfinished CS child")
        let budget = StreamDiscoveryCoordinator.discoveryDeadline(singleStreamDiscovery: true,
            optionalProviderCodes: ["communitysports"]) / 1000
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in publish(.partialSession(first)); return firstOutcome },
            { publish in
                defer { childStopped.fulfill() }
                try? await Task.sleep(for: .seconds(60))
                publish(.session(late))
                return lateOutcome
            }
        ], deadline: budget, onSessions: { await snapshots.append($0) })
        await fulfillment(of: [childStopped], timeout: 1)
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id])
        XCTAssertTrue(result.reachedDeadline)
        XCTAssertEqual(result.exitReason, .deadline)
        XCTAssertEqual(result.incompleteLanes, 1)
    }

    func testFastIndependentProvidersRetainBothChoices() async {
        let a = session("shared"), b = session("site")
        let one = outcome([a]), two = outcome([b])
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in publish(.session(a)); return one },
            { publish in publish(.session(b)); return two }
        ])
        XCTAssertEqual(Set(result.sessions.map(\.providerName)), ["shared", "site"])
        XCTAssertFalse(result.reachedDeadline)
    }

    func testSameURLWithDistinctRequiredHeadersRetainsBothDeliveries() async {
        let url = URL(string: "https://example.test/player")!
        let a = StreamSession(matchID: "test", playableURL: url, streamType: .unknown, providerName: "a",
                              requiredHeaders: ["Referer": "https://example.test/match-a"])
        let b = StreamSession(matchID: "test", playableURL: url, streamType: .unknown, providerName: "b",
                              requiredHeaders: ["Referer": "https://example.test/match-b"])
        let one = outcome([a, b])
        let result = await StreamDiscoveryCoordinator.collect(lanes: [{ publish in
            publish(.session(a)); publish(.session(b)); return one
        }])
        XCTAssertEqual(result.sessions.count, 2)
    }

    func testPartialChoiceSurvivesSlowLaneAndIsDeduplicated() async {
        let a = session("shared"), one = outcome([])
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in
                publish(.session(a)); publish(.session(a))
                try? await Task.sleep(for: .seconds(60))
                return one
            }
        ], deadline: .seconds(1), choiceGrace: .milliseconds(10))
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertFalse(result.reachedDeadline)
    }

    func testDeadlinePreservesAlreadyReportedTrustFailure() async {
        let failure = StreamFailure(providerName: "Shared", category: .providerSecurityFailure,
            technicalMessage: "Expired certificate", userMessage: "Cannot connect safely",
            retryable: true, fallbackAllowed: true)
        let finished = outcome([], failure: failure)
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in
                publish(.failure(failure))
                try? await Task.sleep(for: .seconds(60))
                return finished
            }
        ], deadline: .milliseconds(10))
        XCTAssertTrue(result.reachedDeadline)
        XCTAssertEqual(StreamTransportFailurePolicy.mostActionableFailure(in: result.failures)?.category,
                       .providerSecurityFailure)
    }

    func testMountedWatchCollectsLateBackupAfterEveryLaneHasResponded() async {
        let primary = session("primary"), backup = session("backup")
        let complete = outcome([])
        let report = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in publish(.session(primary)); return complete },
            { publish in
                publish(.fairOpportunity)
                try? await Task.sleep(for: .milliseconds(60))
                if !Task.isCancelled { publish(.session(backup)) }
                return complete
            }
        ], deadline: .seconds(1), choiceGrace: .milliseconds(5), preferDirectInitialChoice: true,
            initialChoiceGrace: .zero, onSessions: { _ in })
        XCTAssertEqual(Set(report.sessions.map(\.id)), [primary.id, backup.id])
    }

    func testFastSharedPageCannotCancelPendingDirectDiscovery() async {
        let a = session("shared"), b = session("site")
        let one = outcome([a]), two = outcome([b])
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in publish(.session(a)); return one },
            { publish in
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return one }
                publish(.session(b)); return two
            }
        ], deadline: .seconds(1), choiceGrace: .milliseconds(5))
        XCTAssertEqual(Set(result.sessions.map(\.providerName)), ["shared", "site"])
    }

    func testCancelledParentDoesNotWaitForDeadline() async {
        let finished = outcome([])
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [{ _ in
                try? await Task.sleep(for: .seconds(60))
                return finished
            }])
        }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.sessions.isEmpty)
    }

    func testFirstWebChoiceWaitsForDirectDeliveryWithoutDroppingEitherSource() async {
        let web = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/embed/score")!,
            streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        let native = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/direct.m3u8")!,
            streamType: .hls, providerName: "CS1")
        let webResult = outcome([web]), directResult = outcome([native]), snapshots = IncrementalSnapshots()
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in publish(.session(web)); return webResult },
            { _ in try? await Task.sleep(for: .milliseconds(20)); return directResult }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(200),
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.first?.map(\.id), [web.id, native.id], "The first model can rank both choices, not get stuck on HTML")
        XCTAssertEqual(result.sessions.map(\.id), [web.id, native.id])
    }

    func testExactMatchSuccessPublishesBeforeSlowSiblingWithoutHostHistory() async {
        let fixture = "direct-proof-" + UUID().uuidString
        let proven = StreamSession(matchID: fixture, playableURL: URL(string: "https://fresh.test/live.m3u8")!,
            streamType: .hls, providerName: "CS1")
        LiveSourceHealthStore.recordMatchOutcome(.sustained, for: proven.legacySource, fixtureID: fixture, watchID: UUID())
        XCTAssertTrue(StreamDiscoveryCoordinator.hasCurrentDirectEvidence(proven, at: Date()))
        let snapshots = IncrementalSnapshots(), ready = outcome([proven]), empty = outcome([])
        _ = await StreamDiscoveryCoordinator.collect(lanes: [
            { _ in ready }, { _ in
                try? await Task.sleep(for: .milliseconds(80))
                let initial = await snapshots.all()
                XCTAssertEqual(initial.first?.map(\.id), [proven.id])
                return empty
            }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .seconds(1),
            onSessions: { await snapshots.append($0) })
    }

    func testWrongProgrammeCannotWinIncrementalWatchButOtherLaneStillPublishes() async {
        let wrong = session("wrong-programme"), valid = session("other-programme")
        LiveSourceHealthStore.recordMatchOutcome(.wrongProgramme, for: wrong.legacySource,
            fixtureID: wrong.matchID, watchID: UUID())
        let snapshots = IncrementalSnapshots(), bad = outcome([wrong]), good = outcome([valid])
        _ = await StreamDiscoveryCoordinator.collect(lanes: [
            { _ in bad }, { _ in try? await Task.sleep(for: .milliseconds(30)); return good }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .zero,
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertFalse(published.isEmpty)
        XCTAssertTrue(published.allSatisfy { !$0.contains(where: { $0.id == wrong.id }) })
        XCTAssertEqual(published.last?.map(\.id), [valid.id])
    }

    func testReturnWatchWaitsForSustainedProviderBeyondNormalGrace() async {
        let fixture = "return-" + UUID().uuidString
        let early = StreamSession(matchID: fixture, playableURL: URL(string: "https://early.test/watch")!,
            streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        let stable = StreamSession(matchID: fixture, playableURL: URL(string: "https://stable.test/live.m3u8")!,
            streamType: .hls, providerName: "CS4")
        LiveSourceHealthStore.recordMatchOutcome(.sustained, for: stable.legacySource, fixtureID: fixture, watchID: UUID())
        XCTAssertEqual(LiveSourceHealthStore.sustainedMatchProviders(for: fixture), ["communitysports"])
        let web = outcome([early]), direct = outcome([stable]), snapshots = IncrementalSnapshots()
        _ = await StreamDiscoveryCoordinator.collect(lanes: [
            { _ in web }, { _ in try? await Task.sleep(for: .milliseconds(60)); return direct }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(5),
            sustainedProviderLanes: [1], onSessions: { await snapshots.append($0) })
        let first = await snapshots.all().first ?? []
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions(first).first?.id, stable.id)
    }

    func testKnownStallCannotMountBeforeLaterMatchBackup() async {
        let stalled = session("recentStall"), backup = session("lateBackup")
        LiveSourceHealthStore.recordMatchOutcome(.stalled, for: stalled.legacySource,
            fixtureID: stalled.matchID, watchID: UUID())
        let early = outcome([stalled]), late = outcome([backup]), snapshots = IncrementalSnapshots()
        _ = await StreamDiscoveryCoordinator.collect(lanes: [
            { _ in early }, { _ in try? await Task.sleep(for: .milliseconds(60)); return late }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(5),
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.first?.map(\.id), [stalled.id, backup.id])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions(published.first ?? []).first?.id, backup.id)
    }

    func testUnprovenEarlyDirectChoiceWaitsForLaterAlternativeDuringInitialGrace() async {
        let first = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/early-unproven.m3u8")!,
            streamType: .hls, providerName: "FS1")
        let later = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/later-choice.m3u8")!,
            streamType: .hls, providerName: "CS5")
        let firstOutcome = outcome([first]), laterOutcome = outcome([later]), snapshots = IncrementalSnapshots()
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { _ in firstOutcome },
            { _ in try? await Task.sleep(for: .milliseconds(20)); return laterOutcome }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(200),
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.first?.map(\.id), [first.id, later.id])
        XCTAssertEqual(result.sessions.count, 2)
    }

    func testEarlyDiagnosticsDoNotConsumeInitialCandidateGrace() async {
        let web = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/embed/delayed")!,
            streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        let direct = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/direct-delayed.m3u8")!,
            streamType: .hls, providerName: "CS5")
        let diagnostic = StreamEventRecord(name: .provider1ValidationFailed, matchID: "test", matchTitle: "Test",
            providerName: "CS", attemptID: "test", currentState: .failed)
        let webResult = outcome([web]), directResult = outcome([direct]), snapshots = IncrementalSnapshots()
        _ = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in
                publish(.event(diagnostic))
                try? await Task.sleep(for: .milliseconds(100))
                return webResult
            },
            { _ in try? await Task.sleep(for: .milliseconds(125)); return directResult }
        ], deadline: .seconds(1), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(50),
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.first?.map(\.id), [web.id, direct.id], "Diagnostics before a candidate must not use its grace period")
    }

    func testFirstWebGraceExpiresWithoutWaitingForHungIndependentLane() async {
        let web = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/embed/score")!,
            streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        let webResult = outcome([web]), empty = outcome([]), snapshots = IncrementalSnapshots()
        let published = expectation(description: "Web fallback is released by its finite initial grace")
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [
                { _ in webResult }, { _ in try? await Task.sleep(for: .seconds(60)); return empty }
            ], deadline: .milliseconds(200), preferDirectInitialChoice: true, initialChoiceGrace: .milliseconds(20),
                onSessions: { choices in await snapshots.append(choices); published.fulfill() })
        }
        await fulfillment(of: [published], timeout: 1)
        let current = await snapshots.all()
        XCTAssertEqual(current.first?.map(\.id), [web.id])
        task.cancel()
        _ = await task.value
    }

    func testOnlyWebLaneCompletesImmediatelyWithoutInitialGrace() async {
        let web = StreamSession(matchID: "test", playableURL: URL(string: "https://example.test/embed/score")!,
            streamType: .unknown, providerName: "Score808", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        let webResult = outcome([web]), snapshots = IncrementalSnapshots()
        let result = await StreamDiscoveryCoordinator.collect(lanes: [{ _ in webResult }],
            preferDirectInitialChoice: true, initialChoiceGrace: .seconds(60), onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[web.id]])
        XCTAssertEqual(result.exitReason, .completed)
    }

    func testIncrementalPartialChoicePublishesBeforeLateLaneCompletes() async {
        let first = session("first"), late = session("late")
        let firstOutcome = outcome([first]), lateOutcome = outcome([late])
        let gate = IncrementalReleaseGate(), snapshots = IncrementalSnapshots()
        let firstPublished = expectation(description: "First choice is visible while the late lane is still pending")
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [
                { publish in publish(.partialSession(first)); return firstOutcome },
                { _ in await gate.wait(); return lateOutcome }
            ], deadline: .seconds(3), onSessions: { choices in
                await snapshots.append(choices)
                if choices.count == 1 { firstPublished.fulfill() }
            })
        }
        await fulfillment(of: [firstPublished], timeout: 1)
        let whilePending = await snapshots.all()
        XCTAssertEqual(whilePending.map { $0.map(\.id) }, [[first.id]])
        await gate.open()
        let result = await task.value
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id], [first.id, late.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id, late.id])
        XCTAssertEqual(result.exitReason, .completed)
    }

    func testIncrementalSnapshotsDeduplicateDeliveriesButPreserveDistinctRequiredHeaders() async {
        let url = URL(string: "https://example.test/same-player")!
        let first = StreamSession(matchID: "test", playableURL: url, streamType: .unknown,
            providerName: "first", requiredHeaders: ["Referer": "https://example.test/first"])
        let duplicate = StreamSession(matchID: "test", playableURL: url, streamType: .unknown,
            providerName: "duplicate-label", requiredHeaders: ["Referer": "https://example.test/first"])
        let differentHeaders = StreamSession(matchID: "test", playableURL: url, streamType: .unknown,
            providerName: "second", requiredHeaders: ["Referer": "https://example.test/second"])
        let completed = outcome([duplicate, differentHeaders, first])
        let snapshots = IncrementalSnapshots()
        let result = await StreamDiscoveryCoordinator.collect(lanes: [{ publish in
            publish(.partialSession(first))
            publish(.session(duplicate))
            publish(.partialSession(differentHeaders))
            publish(.session(first))
            return completed
        }], onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id], [first.id, differentHeaders.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id, differentHeaders.id])
        XCTAssertEqual(result.sessions.map(\.requiredHeaders), [first.requiredHeaders, differentHeaders.requiredHeaders])
    }

    func testTerminalOnlyChoicesPublishOneSnapshotBeforeReturningReport() async {
        let first = session("terminal-first"), second = session("terminal-second")
        let completed = outcome([first, second])
        let snapshots = IncrementalSnapshots()
        let result = await StreamDiscoveryCoordinator.collect(lanes: [{ _ in completed }],
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id, second.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(result.exitReason, .completed)
    }

    func testCancelledDiscoveryCannotPublishLateChoicesFromCancelledLane() async {
        let late = session("cancelled-late"), completed = outcome([]), lateOutcome = outcome([late])
        let snapshots = IncrementalSnapshots()
        let laneStarted = expectation(description: "Discovery lane has started before cancellation")
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [{ publish in
                laneStarted.fulfill()
                try? await Task.sleep(for: .seconds(60))
                // A dependency can finish after cancellation. Its buffered
                // update and terminal result must not revive this owner.
                publish(.session(late))
                return lateOutcome
            }, { _ in completed }], onSessions: { await snapshots.append($0) })
        }
        await fulfillment(of: [laneStarted], timeout: 1)
        task.cancel()
        let result = await task.value
        let published = await snapshots.all()
        XCTAssertTrue(published.isEmpty)
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertEqual(result.exitReason, .cancelled)
    }

    func testCancellingAfterFirstSnapshotDoesNotPublishOrReplaceWithLateChoice() async {
        let first = session("retained-first"), late = session("cancelled-alternative")
        let firstOutcome = outcome([first]), lateOutcome = outcome([late])
        let snapshots = IncrementalSnapshots()
        let firstPublished = expectation(description: "First choice has been admitted")
        let task = Task {
            await StreamDiscoveryCoordinator.collect(lanes: [
                { publish in publish(.partialSession(first)); return firstOutcome },
                { publish in
                    try? await Task.sleep(for: .seconds(60))
                    publish(.session(late))
                    return lateOutcome
                }
            ], onSessions: { choices in
                await snapshots.append(choices)
                firstPublished.fulfill()
            })
        }
        await fulfillment(of: [firstPublished], timeout: 1)
        task.cancel()
        let result = await task.value
        let published = await snapshots.all()
        XCTAssertEqual(published.map { $0.map(\.id) }, [[first.id]])
        XCTAssertEqual(result.sessions.map(\.id), [first.id])
        XCTAssertEqual(result.exitReason, .cancelled)
    }

    func testEmptyAndFailureCompletionDoNotPublishFalseChoices() async {
        let failure = StreamFailure(providerName: "Empty", category: .providerReturnedEmpty,
            technicalMessage: "Empty catalog", userMessage: "No stream yet",
            retryable: true, fallbackAllowed: false)
        let empty = outcome([]), failed = outcome([], failure: failure)
        let snapshots = IncrementalSnapshots()
        let result = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in publish(.fairOpportunity); return empty },
            { publish in publish(.failure(failure)); return failed }
        ], onSessions: { await snapshots.append($0) })
        let noLanes = await StreamDiscoveryCoordinator.collect(lanes: [],
            onSessions: { await snapshots.append($0) })
        let published = await snapshots.all()
        XCTAssertTrue(published.isEmpty)
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertTrue(noLanes.sessions.isEmpty)
        XCTAssertEqual(result.exitReason, .completed)
        XCTAssertEqual(result.failures.count, 2)
    }

    func testCSHTTPOutageRemainsLocalEvidenceWhenSiblingPlays() async throws {
        let attemptID = UUID().uuidString
        let failure = LiveStreamResolver.communitySportsFailure(from: .httpFailure(statusCode: 530, stage: .manifest))
        XCTAssertEqual(failure.category, .manifestUnreachable)
        let failedEvent = StreamEventRecord(name: .provider1ValidationFailed, matchID: "private-fixture",
            matchTitle: "Private Home v Private Away", providerName: "CS", attemptID: attemptID,
            currentState: .failed, failureCategory: failure.category, redactedMetadata: failure.redactedMetadata)
        let failedAttempt = StreamProviderAttemptLog(providerName: "CS", responseTimeMs: 207,
            resolvedStreamType: .unknown, urlShape: "same_origin_addon", requiredHeaders: false,
            validationResult: "failed", manifestResult: failure.redactedMetadata["manifest_result"],
            finalFailureCategory: failure.category)
        let ready = outcome([session("Score808")])
        let broken = outcome([], failure: failure)
        let report = await StreamDiscoveryCoordinator.collect(lanes: [
            { publish in
                publish(.event(failedEvent)); publish(.attempt(failedAttempt)); return broken
            },
            { _ in ready }
        ])
        XCTAssertEqual(report.sessions.count, 1)
        let suite = "CS-discovery-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        CommunitySportsDiscoveryQuality.record(report, attemptID: attemptID, store: store)
        let record = try XCTUnwrap(store.records().first)
        XCTAssertEqual(record.name, "source_discovery_result")
        XCTAssertEqual(record.outcome, .failure)
        XCTAssertEqual(record.durationMilliseconds, 207)
        XCTAssertEqual(record.details["platform_error_code"], "530")
        XCTAssertEqual(record.details["result"], "manifest_http_failure")
        XCTAssertEqual(record.details["source_family"], "communitysports")
        XCTAssertEqual(record.details["attempt_id"], attemptID)
        XCTAssertFalse(store.exportJSON().contains("Private Home"))
        XCTAssertFalse(store.exportJSON().contains("private-fixture"))
        XCTAssertFalse(store.exportJSON().contains("example.test"))
    }

    func testCSTransportTimeoutAndMalformedJSONAreDifferentFailures() {
        let timeout = LiveStreamResolver.communitySportsFailure(from:
            .transportFailure(code: URLError.timedOut.rawValue, stage: .catalog))
        XCTAssertEqual(timeout.category, .providerTimeout)
        XCTAssertEqual(timeout.redactedMetadata["manifest_result"], "catalog_transport_failure")
        XCTAssertEqual(timeout.redactedMetadata["platform_error_code"], "-1001")
        let malformed = LiveStreamResolver.communitySportsFailure(from: .invalidJSON(stage: .streams))
        XCTAssertEqual(malformed.category, .manifestInvalid)
        XCTAssertEqual(malformed.redactedMetadata["manifest_result"], "streams_invalid_json")
        XCTAssertNil(malformed.redactedMetadata["platform_error_code"])
    }

    func testCSDiscoveryReceiptDoesNotInventDisabledOrDecodedEvidence() throws {
        let id = UUID().uuidString
        XCTAssertNil(CommunitySportsDiscoveryQuality.receipt(.init(), attemptID: id))
        var report = StreamDiscoveryCoordinator.Report()
        report.attempts = [.init(providerName: "CS", responseTimeMs: 123,
            resolvedStreamType: .hls, urlShape: "same_origin_addon", requiredHeaders: false,
            validationResult: "exact_match_admitted", manifestResult: "exact_fixture_match")]
        let receipt = try XCTUnwrap(CommunitySportsDiscoveryQuality.receipt(report, attemptID: id))
        XCTAssertEqual(receipt.outcome, .success)
        XCTAssertEqual(receipt.details["result"], "exact_fixture_match")
        XCTAssertEqual(receipt.details["stage"], "preparing")
        XCTAssertNil(receipt.details["source_key"])
        XCTAssertNil(CommunitySportsDiscoveryQuality.receipt(report, attemptID: "personal-name"))
    }

    func testCSCancelledDiscoveryIsNotAnOutageAndDeadlineRemainsDistinct() throws {
        let id = UUID().uuidString
        var report = StreamDiscoveryCoordinator.Report()
        report.timeline = [.init(name: .provider1Started, matchID: "fixture", matchTitle: "Home v Away",
            providerName: "CS", attemptID: id, currentState: .resolving)]
        report.exitReason = .cancelled
        let cancelled = try XCTUnwrap(CommunitySportsDiscoveryQuality.receipt(report, attemptID: id))
        XCTAssertEqual(cancelled.outcome, .info)
        XCTAssertEqual(cancelled.details["result"], "discovery_cancelled")
        XCTAssertNil(cancelled.details["failure_kind"])
        report.exitReason = .deadline
        report.reachedDeadline = true
        let deadline = try XCTUnwrap(CommunitySportsDiscoveryQuality.receipt(report, attemptID: id))
        XCTAssertEqual(deadline.outcome, .failure)
        XCTAssertEqual(deadline.details["result"], "discovery_deadline")
        XCTAssertEqual(deadline.details["failure_kind"], "provider_timeout")
        report.exitReason = .choiceGrace
        report.reachedDeadline = false
        XCTAssertEqual(CommunitySportsDiscoveryQuality.receipt(report, attemptID: id)?.outcome, .info)
    }

    func testCSMissingFixtureAndUnsafeResponseRetainExistingClassification() {
        XCTAssertEqual(LiveStreamResolver.communitySportsFailure(from: .matchNotFound).category, .providerReturnedEmpty)
        XCTAssertEqual(LiveStreamResolver.communitySportsFailure(from: .unsafeResponse).category, .providerSecurityFailure)
        XCTAssertEqual(LiveStreamResolver.communitySportsFailure(from: .conflictingMatch).category, .invalidMatchMapping)
    }

    func testCSUnsafeMetadataStageAndFixedReasonReachTheLocalQualityReceiptWithoutPrivateContext() throws {
        let cases: [(CommunitySportsRequestStage, CommunitySportsUnsafeMetadataReason)] = [
            (.manifest, .redirect), (.catalog, .requestOrigin), (.catalog, .responseOrigin),
            (.catalog, .searchRoute), (.streams, .streamID), (.streams, .streamIDEmpty),
            (.streams, .streamIDPrefix), (.streams, .streamIDLength), (.streams, .streamIDCharacters)
        ]
        let suite = "CS-safety-stage-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        for (stage, reason) in cases {
            let id = UUID().uuidString
            let error = CommunitySportsAddonError.unsafeMetadata(stage: stage, reason: reason)
            XCTAssertTrue(error.isSecurityRejection)
            let failure = LiveStreamResolver.communitySportsFailure(from: error)
            let expected = "\(stage.rawValue)_unsafe_\(reason.rawValue)" + (reason == .streamIDCharacters ? "_unresolved" : "")
            XCTAssertEqual(failure.category, .providerSecurityFailure)
            XCTAssertEqual(failure.redactedMetadata, ["manifest_result": expected])
            XCTAssertFalse(failure.retryable)
            var report = StreamDiscoveryCoordinator.Report()
            report.attempts = [.init(providerName: "CS", responseTimeMs: 183, resolvedStreamType: .unknown,
                urlShape: "same_origin_addon", requiredHeaders: false, validationResult: "failed",
                manifestResult: failure.redactedMetadata["manifest_result"], finalFailureCategory: failure.category)]
            report.timeline = [.init(name: .provider1ValidationFailed, matchID: "private-fixture",
                matchTitle: "Private Home vs Private Away", providerName: "CS", attemptID: id,
                currentState: .failed, failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata.merging(["private_url": "https://private.invalid/?token=secret"],
                    uniquingKeysWith: { _, new in new }))]
            CommunitySportsDiscoveryQuality.record(report, attemptID: id, store: store)
            let record = try XCTUnwrap(store.records().last)
            XCTAssertEqual(record.outcome, .failure)
            XCTAssertEqual(record.details["result"], expected)
            XCTAssertEqual(record.details["failure_kind"], "provider_security_failure")
            XCTAssertNil(record.details["private_url"])
        }
        XCTAssertFalse(store.exportJSON().contains("private.invalid"))
        XCTAssertFalse(store.exportJSON().contains("Private Home"))
        XCTAssertTrue(CommunitySportsAddonError.unsafeResponse.isSecurityRejection)
    }

    func testCSInvalidCharacterReceiptCarriesOnlyOneSafeUnicodeCodePoint() throws {
        let suite = "CS-scalar-diagnostic-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        for (scalar, expectedSuffix) in [(UInt32(0x003A), "_u003A"), (0x200B, "_u200B"),
                                         (0x0041, "_unresolved"), (0xD800, "_unresolved")] {
            let failure = LiveStreamResolver.communitySportsFailure(from:
                .unsafeMetadata(stage: .streams, reason: .streamIDCharacters, invalidScalar: scalar))
            let expected = "streams_unsafe_stream_id_characters" + expectedSuffix
            XCTAssertEqual(failure.redactedMetadata, ["manifest_result": expected])
            XCTAssertEqual(failure.category, .providerSecurityFailure)
            let id = UUID().uuidString
            var report = StreamDiscoveryCoordinator.Report()
            report.attempts = [.init(providerName: "CS", responseTimeMs: 213, resolvedStreamType: .unknown,
                urlShape: "same_origin_addon", requiredHeaders: false, validationResult: "failed",
                manifestResult: failure.redactedMetadata["manifest_result"], finalFailureCategory: failure.category)]
            CommunitySportsDiscoveryQuality.record(report, attemptID: id, store: store)
            XCTAssertEqual(store.records().last?.details["result"], expected)
        }
        let unrelated = LiveStreamResolver.communitySportsFailure(from:
            .unsafeMetadata(stage: .manifest, reason: .redirect, invalidScalar: 0x003A))
        XCTAssertEqual(unrelated.redactedMetadata, ["manifest_result": "manifest_unsafe_redirect"])
        XCTAssertFalse(store.exportJSON().contains("nuvio_sport_"))
    }

    func testCSTypedCertificateFailuresPreserveSecurityClassification() {
        for code in [URLError.secureConnectionFailed, .serverCertificateHasBadDate,
                     .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
                     .serverCertificateNotYetValid] {
            let failure = LiveStreamResolver.communitySportsFailure(from:
                .transportFailure(code: code.rawValue, stage: .manifest))
            XCTAssertEqual(failure.category, .providerSecurityFailure)
            XCTAssertEqual(failure.userMessage, StreamTransportFailurePolicy.secureConnectionUnavailableMessage)
            XCTAssertEqual(failure.redactedMetadata["platform_error_code"], String(code.rawValue))
            XCTAssertEqual(failure.redactedMetadata["manifest_result"], "manifest_transport_failure")
        }
    }

    func testCancellingPendingSiblingDoesNotEraseFinishedCSOutage() throws {
        let id = UUID().uuidString
        let failure = LiveStreamResolver.communitySportsFailure(from: .httpFailure(statusCode: 530, stage: .manifest))
        var report = StreamDiscoveryCoordinator.Report()
        report.exitReason = .cancelled
        report.attempts = [.init(providerName: "CS", responseTimeMs: 200, resolvedStreamType: .unknown,
            urlShape: "same_origin_addon", requiredHeaders: false, validationResult: "failed",
            manifestResult: failure.redactedMetadata["manifest_result"], finalFailureCategory: failure.category)]
        report.timeline = [.init(name: .provider1ValidationFailed, matchID: "fixture", matchTitle: "Home v Away",
            providerName: "CS", attemptID: id, currentState: .failed,
            failureCategory: failure.category, redactedMetadata: failure.redactedMetadata)]
        let receipt = try XCTUnwrap(CommunitySportsDiscoveryQuality.receipt(report, attemptID: id))
        XCTAssertEqual(receipt.outcome, .failure)
        XCTAssertEqual(receipt.details["result"], "manifest_http_failure")
        XCTAssertEqual(receipt.details["platform_error_code"], "530")
        XCTAssertEqual(receipt.details["failure_kind"], "manifest_unreachable")
    }
}

@MainActor
final class FixtureCatalogAvailabilityIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func request(_ id: String = "one", kickoff: Date? = nil, observedAt: Date? = nil,
                         home: String = "Arsenal FC", status: SportsFixtureCatalog.Status = .live,
                         verified: Bool = true, conflict: Bool = false) -> StreamPlaybackRequest {
        let fixtureID = "sports-fixture:premier-league:\(id)"
        let metadata = SportsFixtureMetadata(fixtureID: fixtureID, sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "\(home) vs Chelsea FC", participants: [.init(id: "home", name: home), .init(id: "away", name: "Chelsea FC")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: observedAt ?? now, verified: verified)
        return .init(event: .init(id: fixtureID, title: metadata.title, category: "football",
            date: Int64((kickoff ?? now.addingTimeInterval(-600)).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: "Chelsea FC", badge: nil)),
            hasCatalogIdentityConflict: conflict, sportsFixture: metadata))
    }

    private func index(_ codes: Set<String> = ["communitysports", "plaviosports"], capacity: Int = 256) -> FixtureCatalogAvailabilityIndex {
        let index = FixtureCatalogAvailabilityIndex(capacity: capacity)
        index.updateEnabledProviders(codes, revision: 1)
        return index
    }

    func testCatalogListingSurvivesSiblingFailureWithoutCreatingWatchOrSession() throws {
        let index = index(), fixture = request(), streams = FixtureStreamDiscoveryIndex()
        index.replaceFixtures([fixture], at: now)
        let cs = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        let asTicket = try XCTUnwrap(index.begin(providerCode: "plaviosports", at: now))
        index.complete(cs, matches: [.init(matchID: fixture.matchID, outcome: .listed, providerEventID: "nuvio_sport_one")], at: now)
        index.fail(asTicket, category: .manifestUnreachable, at: now)
        let summary = try XCTUnwrap(index.summary(for: fixture, at: now))
        XCTAssertEqual(summary.listedProviderCount, 1)
        XCTAssertTrue(summary.needsVerification)
        XCTAssertFalse(summary.isChecking)
        XCTAssertEqual(summary.providers.first { $0.providerCode == "plaviosports" }?.outcome, .failed(.manifestUnreachable))
        XCTAssertNil(streams.cachedSessions(for: fixture, providerCode: "communitysports", at: now))
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: try XCTUnwrap(fixture.preferredEvent),
            in: [try XCTUnwrap(fixture.preferredEvent)], at: now, discoveryIndex: streams))
    }

    func testPartialProviderFailureDoesNotEraseItsOtherFixtureListing() throws {
        let index = index(), first = request(), second = request("second")
        index.replaceFixtures([first, second], at: now)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        index.complete(ticket, matches: [.init(matchID: first.matchID, outcome: .listed, providerEventID: "nuvio_sport_one"),
            .init(matchID: second.matchID, outcome: .failed(.providerTimeout))], at: now)
        XCTAssertEqual(index.summary(for: first, at: now)?.listedProviderCount, 1)
        XCTAssertEqual(index.summary(for: second, at: now)?.providers.first?.outcome, .failed(.providerTimeout))
        XCTAssertEqual(index.summary(for: second, at: now)?.listedProviderCount, 0)
    }

    func testExpiryRetainsOnlyDescriptivePriorListingAcrossRefreshAndCancellation() throws {
        let index = index(), fixture = request()
        index.replaceFixtures([fixture], at: now)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        index.complete(ticket, matches: [.init(matchID: fixture.matchID, outcome: .listed, providerEventID: "nuvio_sport_one")], at: now)
        XCTAssertEqual(index.summary(for: fixture, at: now.addingTimeInterval(119))?.listedProviderCount, 1)
        let expired = try XCTUnwrap(index.summary(for: fixture, at: now.addingTimeInterval(120)))
        XCTAssertEqual(expired.listedProviderCount, 0)
        XCTAssertTrue(expired.previouslyListed)
        XCTAssertNil(expired.providers.first?.providerEventID)
        XCTAssertTrue(expired.needsVerification)
        XCTAssertNil(index.begin(providerCode: "communitysports", at: now.addingTimeInterval(299)))
        let recheck = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now.addingTimeInterval(300)))
        XCTAssertTrue(index.summary(for: fixture, at: now.addingTimeInterval(300))?.isChecking == true)
        index.abandon(recheck)
        XCTAssertTrue(index.summary(for: fixture, at: now.addingTimeInterval(301))?.previouslyListed == true)
        XCTAssertFalse(index.summary(for: fixture, at: now.addingTimeInterval(901))?.previouslyListed ?? true)
    }

    func testRevocationReenablementAndDelayedSnapshotsCannotRestoreSourceEvidenceOrBudget() throws {
        let index = index(), fixture = request()
        index.replaceFixtures([fixture], at: now)
        let old = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        index.updateEnabledProviders(["plaviosports"], revision: 2)
        index.updateEnabledProviders(["communitysports", "plaviosports"], revision: 3)
        index.complete(old, matches: [.init(matchID: fixture.matchID, outcome: .listed)], at: now)
        XCTAssertNil(index.summary(for: fixture, at: now))
        index.updateEnabledProviders(["communitysports"], revision: 1)
        XCTAssertEqual(index.enablementRevision, 3)
        XCTAssertEqual(index.enabledProviderCodes, ["communitysports", "plaviosports"])
        XCTAssertNil(index.begin(providerCode: "communitysports", at: now.addingTimeInterval(299)))
        let current = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now.addingTimeInterval(300)))
        index.complete(current, matches: [.init(matchID: fixture.matchID, outcome: .listed)], at: now.addingTimeInterval(300))
        XCTAssertEqual(index.summary(for: fixture, at: now.addingTimeInterval(300))?.listedProviderCount, 1)
    }

    func testRotatingFixtureRescheduleAndTerminalReceiptFenceOnlyAffectedIdentities() throws {
        let index = index(), first = request(), second = request("second")
        index.replaceFixtures([first, second], at: now)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        let corrected = request(kickoff: now.addingTimeInterval(-900))
        index.replaceFixtures([corrected, second], at: now)
        index.complete(ticket, matches: [.init(matchID: first.matchID, outcome: .listed, providerEventID: "nuvio_sport_one"),
            .init(matchID: second.matchID, outcome: .listed, providerEventID: "nuvio_sport_two")], at: now)
        XCTAssertNil(index.summary(for: first, at: now))
        XCTAssertNil(index.summary(for: corrected, at: now))
        XCTAssertEqual(index.summary(for: second, at: now)?.listedProviderCount, 1)
        index.replaceFixtures([corrected, request("second", status: .finished)], at: now)
        XCTAssertNil(index.summary(for: second, at: now))
        XCTAssertEqual(index.retainedRecordCount, 0)
        index.replaceFixtures([request(home: "Liverpool FC")], at: now)
        XCTAssertNil(index.summary(for: first, at: now))
    }

    func testContradictoryDuplicateOrReusedProviderIdentityCannotProduceListing() throws {
        let first = request(), second = request("second")
        for matches: [FixtureSourceCatalogMatch] in [
            [.init(matchID: first.matchID, outcome: .listed), .init(matchID: first.matchID, outcome: .notListed)],
            [.init(matchID: first.matchID, outcome: .listed, providerEventID: "same"),
             .init(matchID: second.matchID, outcome: .listed, providerEventID: "same")]
        ] {
            let index = index(); index.replaceFixtures([first, second], at: now)
            let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
            index.complete(ticket, matches: matches, at: now)
            XCTAssertEqual(index.summary(for: first, at: now)?.providers.first?.outcome, .conflicting)
            XCTAssertEqual(index.summary(for: first, at: now)?.listedProviderCount, 0)
        }
        let index = index(); index.replaceFixtures([first], at: now)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        index.complete(ticket, matches: [.init(matchID: first.matchID, outcome: .listed,
            providerEventID: "https://example.invalid/private?token=never-retained")], at: now)
        XCTAssertEqual(index.summary(for: first, at: now)?.providers.first?.outcome, .needsVerification)
        XCTAssertNil(index.summary(for: first, at: now)?.providers.first?.providerEventID)
    }

    func testAuthorityBoundsRejectHeldTerminalConflictingDuplicateAndUnknownProvider() {
        let index = index(capacity: 2), first = request(), second = request("second"), third = request("third")
        index.replaceFixtures([first, second, third], at: now)
        XCTAssertEqual(index.fixtureCount, 2)
        XCTAssertNil(index.begin(providerCode: "unreviewed", at: now))
        for candidate in [request(status: .finished), request(status: .cancelled), request(status: .postponed),
            request(verified: false), request(conflict: true), request(observedAt: now.addingTimeInterval(-1801))] {
            index.replaceFixtures([candidate], at: now)
            XCTAssertEqual(index.fixtureCount, 0)
        }
        index.replaceFixtures([first, first], at: now)
        XCTAssertEqual(index.fixtureCount, 0)
        index.replaceFixtures([first], at: now)
        XCTAssertNil(index.summary(for: first, at: now.addingTimeInterval(-1)), "Clock rollback cannot renew any catalog observation")
    }

    func testAllEnabledReviewedProvidersHaveSeparateBoundedMetadataState() throws {
        let codes = Set(CuratedStreamSourceCatalog.all.map(\.providerCode)), index = index(codes), fixture = request()
        index.replaceFixtures([fixture], at: now)
        for code in codes {
            let ticket = try XCTUnwrap(index.begin(providerCode: code, at: now))
            index.complete(ticket, matches: [.init(matchID: fixture.matchID, outcome: .unsupported)], at: now)
        }
        XCTAssertEqual(index.summary(for: fixture, at: now)?.providers.count, codes.count)
        XCTAssertEqual(index.retainedRecordCount, codes.count)
        XCTAssertEqual(index.summary(for: fixture, at: now)?.listedProviderCount, 0)
    }

    func testFuturePlanningUsesScheduleReceiptFreshnessWithoutExtendingLiveOrWatchAuthority() throws {
        let index = index(["communitysports"])
        let future = request(kickoff: now.addingTimeInterval(7 * 86400),
            observedAt: now.addingTimeInterval(-2 * 3600), status: .scheduled)
        index.replaceFixtures([future], at: now)
        XCTAssertEqual(index.fixtureCount, 1)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        index.complete(ticket, matches: [.init(matchID: future.matchID, outcome: .listed)], at: now)
        XCTAssertEqual(index.summary(for: future, at: now)?.listedProviderCount, 1)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: try XCTUnwrap(future.preferredEvent),
            in: [try XCTUnwrap(future.preferredEvent)], at: now, discoveryIndex: FixtureStreamDiscoveryIndex()))
        let transition = self.index(["communitysports"])
        let nearStart = request(kickoff: now.addingTimeInterval(60),
            observedAt: now.addingTimeInterval(-2 * 3600), status: .scheduled)
        transition.replaceFixtures([nearStart], at: now)
        let delayed = try XCTUnwrap(transition.begin(providerCode: "communitysports", at: now))
        transition.complete(delayed, matches: [.init(matchID: nearStart.matchID, outcome: .listed)],
            at: now.addingTimeInterval(61))
        XCTAssertNil(transition.summary(for: nearStart, at: now.addingTimeInterval(61)))
        XCTAssertEqual(transition.retainedRecordCount, 0,
            "A planning receipt cannot cross kickoff and keep its wider freshness while live status is unconfirmed")
        for rejected in [request(observedAt: now.addingTimeInterval(-2 * 3600)),
            request(kickoff: now.addingTimeInterval(7 * 86400),
                observedAt: now.addingTimeInterval(-SportsSearchSchedule.receiptFreshness - 1), status: .scheduled),
            request(kickoff: now.addingTimeInterval(SportsSearchSchedule.futureHorizon + 1), status: .scheduled)] {
            index.replaceFixtures([rejected], at: now)
            XCTAssertEqual(index.fixtureCount, 0)
        }

        let cricketFixture = CricketFixtureMetadata(fixtureID: "icc:planning", competitionID: "west-indies",
            competitionName: "West Indies in India, 3 T20I Series", format: .t20, status: .scheduled,
            observedAt: now.addingTimeInterval(-2 * 3600), verified: true, homeTeamID: "india", awayTeamID: "wi")
        let cricket = StreamPlaybackRequest(event: .init(id: "cricket-fixture:icc:planning",
            title: "West Indies in India, 3 T20I Series · India vs West Indies", category: "cricket",
            date: Int64(now.addingTimeInterval(7 * 86400).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "India", badge: nil), away: .init(name: "West Indies", badge: nil)), cricketFixture: cricketFixture))
        index.replaceFixtures([cricket], at: now)
        XCTAssertEqual(index.fixtureCount, 1, "Scheduled cricket uses the same existing planning receipt window")
    }

    func testFreshScheduledPastStartIsNeutralInventoryWhileTerminalAndEstimatedEndRemainBlocked() throws {
        let index = index(["communitysports"])
        let scheduled = request(kickoff: now.addingTimeInterval(-300), status: .scheduled)
        index.replaceFixtures([scheduled], at: now)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
        index.complete(ticket, matches: [.init(matchID: scheduled.matchID, outcome: .listed)], at: now)
        XCTAssertEqual(index.summary(for: scheduled, at: now)?.listedProviderCount, 1)
        XCTAssertEqual(scheduled.preferredEvent?.sportsFixture?.status, .scheduled)
        XCTAssertFalse(scheduled.preferredEvent?.sportsFixture?.isLive(at: now) ?? true)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: try XCTUnwrap(scheduled.preferredEvent),
            in: [try XCTUnwrap(scheduled.preferredEvent)], at: now, discoveryIndex: FixtureStreamDiscoveryIndex()))
        for rejected in [request(status: .finished), request(status: .postponed),
            request(kickoff: now.addingTimeInterval(-300), observedAt: now.addingTimeInterval(-1801), status: .scheduled)] {
            index.replaceFixtures([rejected], at: now)
            XCTAssertEqual(index.fixtureCount, 0)
        }
        let endedCPL = CPLSchedule.Fixture(1,
            ISO8601DateFormatter().string(from: now.addingTimeInterval(-CatalogTimingPolicy.cplWindow - 1)),
            .trinbago, .guyana).event()
        index.replaceFixtures([.init(event: endedCPL)], at: now)
        XCTAssertEqual(index.fixtureCount, 0, "A source catalog cannot reopen an elapsed existing CPL window")
    }

    func testReviewedUnicodeOpaqueIDsRemainListedButURLsAndControlTextAreNotRetained() throws {
        let fixture = request()
        for providerID in ["nuvio_sport_éΩ中١", "nuvio_sport_" + String(repeating: "中", count: 220)] {
            let index = index(["communitysports"])
            index.replaceFixtures([fixture], at: now)
            let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
            index.complete(ticket, matches: [.init(matchID: fixture.matchID, outcome: .listed, providerEventID: providerID)], at: now)
            XCTAssertEqual(index.summary(for: fixture, at: now)?.listedProviderCount, 1)
            XCTAssertEqual(index.summary(for: fixture, at: now)?.providers.first?.providerEventID, providerID)
        }
        for invalid in ["https://example.invalid/private?token=private", "http:private", "nuvio_sport_\nsecret",
            "nuvio_sport_\u{0000}secret", "nuvio_sport_" + String(repeating: "中", count: 240)] {
            let index = index(["communitysports"])
            index.replaceFixtures([fixture], at: now)
            let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
            index.complete(ticket, matches: [.init(matchID: fixture.matchID, outcome: .listed, providerEventID: invalid)], at: now)
            XCTAssertEqual(index.summary(for: fixture, at: now)?.listedProviderCount, 0)
            XCTAssertNil(index.summary(for: fixture, at: now)?.providers.first?.providerEventID)
        }
    }

    func testDailyLogicalSnapshotBudgetSurvivesRepeatedToggleAndFreshFixtureReceipts() throws {
        let index = index(["communitysports"])
        for attempt in 0..<96 {
            let time = now.addingTimeInterval(Double(attempt) * 300)
            index.replaceFixtures([request(observedAt: time)], at: time)
            let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: time))
            index.abandon(ticket)
        }
        let later = now.addingTimeInterval(96 * 300)
        index.updateEnabledProviders([], revision: 2)
        index.updateEnabledProviders(["communitysports"], revision: 3)
        index.replaceFixtures([request(observedAt: later)], at: later)
        XCTAssertNil(index.begin(providerCode: "communitysports", at: later))
        let tomorrow = now.addingTimeInterval(86_400)
        index.replaceFixtures([request(observedAt: tomorrow)], at: tomorrow)
        XCTAssertNotNil(index.begin(providerCode: "communitysports", at: tomorrow))
    }
}
