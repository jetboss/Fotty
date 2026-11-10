import XCTest
import SwiftUI
import UserNotifications
@testable import Fotty

@MainActor
final class MatchReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ id: String = "match", start: Date?, source: Bool = true, channel: Bool = false) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: channel ? "Willow Cricket" : "Home Club vs Away Club", category: channel ? "cricket" : "football",
              date: start.map { Int64($0.timeIntervalSince1970) }, poster: nil, popular: nil, teams: nil)
    }

    private func harness() throws -> ReminderHarness { try ReminderHarness(now: now) }

    func testPresentationIntentRevisionTracksSameMatchABAWithoutAffectingOtherMatches() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event("one", start: now.addingTimeInterval(7_200))
        XCTAssertEqual(h.store.intentRevision(for: match.id), 0)
        let first = await h.store.enable(match)
        XCTAssertEqual(first, .scheduled)
        let receipt = h.store.intentRevision(for: match.id)
        XCTAssertEqual(receipt, 1)
        _ = await h.store.enable(event("two", start: now.addingTimeInterval(7_200)))
        XCTAssertEqual(h.store.intentRevision(for: match.id), receipt)
        h.store.cancel(match.id)
        XCTAssertEqual(h.store.intentRevision(for: match.id), receipt + 1)
        _ = await h.store.enable(match)
        XCTAssertTrue(h.store.contains(match.id))
        XCTAssertEqual(h.store.intentRevision(for: match.id), receipt + 2,
                       "An identical reminder is still newer intent than the old Undo receipt")
        h.store.cancel(match.id)
        let cancelledReceipt = h.store.intentRevision(for: match.id)
        h.store.cancelAllForRestore()
        XCTAssertGreaterThan(h.store.intentRevision(for: match.id), cancelledReceipt,
                             "A data restore invalidates Undo even for a previously cancelled reminder")
    }

    private func queuedFootballFixture(_ status: SportsFixtureCatalog.Status, verified: Bool = true) -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:queued", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Bournemouth vs Liverpool",
            participants: [.init(id: "bournemouth", name: "Bournemouth", role: "home"),
                           .init(id: "liverpool", name: "Liverpool", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: verified)
        return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(7200).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Bournemouth", badge: nil), away: .init(name: "Liverpool", badge: nil)),
            sportsFixture: metadata, competitionID: metadata.competitionID)
    }

    func testUnverifiedSportsStartNeverPromptsOrCreatesReminder() async throws {
        let h = try harness(); defer { h.clean() }
        let held = queuedFootballFixture(.scheduled, verified: false)
        XCTAssertTrue(MatchStartPolicy(event: held, now: now).hasUnconfirmedFixtureStart)
        XCTAssertNil(MatchStartPolicy(event: held, now: now).upcomingStart)
        let result = await h.store.enable(held)
        XCTAssertEqual(result, .tooLate)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 0)
    }

    func testSportsStartHoldRevokesReminderAndPreservesBookmark() async throws {
        let h = try harness(); defer { h.clean() }
        let confirmed = queuedFootballFixture(.scheduled)
        let result = await h.store.enable(confirmed)
        XCTAssertEqual(result, .scheduled)
        await h.store.reconcile(events: [queuedFootballFixture(.scheduled, verified: false)])
        XCTAssertFalse(h.store.contains(confirmed.id))
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.matchday.contains(eventID: confirmed.id))
    }

    func testCountdownAndPlayBoundaries() {
        for (seconds, canPlay, title) in [(7200.0, false, "Starts in 2h 0m"), (301, false, "Starts in 6m"),
            (300, false, "Starts in 5:00"), (121, false, "Starts in 2:01"), (120, true, "Starts in 2:00"),
            (1, true, "Starts in 0:01"), (0, true, "No stream listed")] {
            let policy = MatchStartPolicy(event: event(start: now.addingTimeInterval(seconds)), now: now)
            XCTAssertEqual(policy.timingAllowsPlayback, canPlay, "\(seconds)")
            XCTAssertFalse(policy.canAttemptPlayback, "Timing alone never offers Watch without a resolvable source")
            XCTAssertEqual(policy.title, title)
        }
        XCTAssertEqual(MatchStartPolicy.countdown(86_400 + 7200), "1d 2h")
        XCTAssertEqual(MatchStartPolicy.countdown(0.01), "0:01")
    }

    func testChannelsUnknownTimesAndSourceFreeSchedulesRemainHonest() {
        let channel = event(start: now.addingTimeInterval(7200), channel: true)
        XCTAssertNil(MatchStartPolicy(event: channel, now: now).upcomingStart)
        XCTAssertTrue(MatchStartPolicy(event: channel, now: now).timingAllowsPlayback)
        XCTAssertNil(MatchReminderRecord.make(event: channel, now: now))
        let unknown = event(start: nil)
        XCTAssertNil(MatchStartPolicy(event: unknown, now: now).upcomingStart)
        XCTAssertEqual(MatchStartPolicy(event: unknown, now: now).title, "Time TBC")
        XCTAssertNil(MatchReminderRecord.make(event: unknown, now: now))
        let noSource = event(start: now.addingTimeInterval(120), source: false)
        XCTAssertFalse(MatchStartPolicy(event: noSource, now: now).canAttemptPlayback)
        XCTAssertEqual(MatchStartPolicy(event: noSource, now: now).title, "Starts in 2:00")
    }

    func testOfficialStoppedStatusOverridesTimerButLiveCanOverrideFutureCatalog() {
        let match = event(start: now.addingTimeInterval(3600))
        for status: FootballMatch.MatchStatus in [.cancelled, .postponed, .suspended, .finished, .awarded] {
            let policy = MatchStartPolicy(event: match, now: now, status: status)
            XCTAssertNil(policy.upcomingStart)
            XCTAssertFalse(policy.timingAllowsPlayback)
        }
        let live = MatchStartPolicy(event: match, now: now, status: .inPlay)
        XCTAssertTrue(live.timingAllowsPlayback)
        XCTAssertNil(live.upcomingStart)
    }

    func testClockEntersPreciseWindowAndStopsSecondTicksAtStart() {
        let dates = Array(MatchCountdownSchedule(kickoff: now.addingTimeInterval(302))
            .entries(from: now, mode: .normal).prefix(5))
        XCTAssertEqual(dates.map { $0.timeIntervalSince(now) }, [0, 2, 3, 4, 5])
        let end = Array(MatchCountdownSchedule(kickoff: now.addingTimeInterval(1))
            .entries(from: now, mode: .normal).prefix(3))
        XCTAssertEqual(end.map { $0.timeIntervalSince(now) }, [0, 1, 61])
    }

    func testNotificationUsesAbsoluteUTCAndSafeMatchdayPayload() throws {
        let record = try XCTUnwrap(MatchReminderRecord.make(event: event("match/with spaces", start: now.addingTimeInterval(900)), now: now))
        let request = record.request
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(trigger.dateComponents.date, now.addingTimeInterval(600))
        XCTAssertEqual(request.content.userInfo["route"] as? String, "match-reminder")
        XCTAssertEqual(request.content.userInfo["matchID"] as? String, "match/with spaces")
        XCTAssertTrue(request.content.body.contains("scheduled to start in 5 minutes"))
        XCTAssertFalse(request.content.body.contains("watch now"))
        XCTAssertNotEqual(MatchReminderRecord.requestID(eventID: "a/b"), MatchReminderRecord.requestID(eventID: "ab"))
    }

    func testSavingAloneIsSilentAndExplicitReminderPersistsOnce() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        h.matchday.save(match)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 0)
        let result = await h.store.enable(match)
        XCTAssertEqual(result, .scheduled)
        XCTAssertTrue(h.matchday.contains(eventID: match.id))
        _ = await h.store.enable(match)
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertEqual(h.store.records.count, 1)
        let restored = MatchReminderStore(defaults: h.defaults, client: h.client, matchday: h.matchday, clock: { h.clock.now })
        XCTAssertTrue(restored.contains(match.id))
        await restored.reconcile(events: [match])
        XCTAssertEqual(h.client.requests.count, 1)
        h.store.cancel(match.id)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.matchday.contains(eventID: match.id), "Bell cancellation must not remove the bookmark")
    }

    func testDeniedPermissionDoesNotClaimReminderOrSaveMatch() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .denied
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .denied)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.matchday.savedMatches.isEmpty)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 0)
    }

    func testPermissionPromptOnlyFollowsOptInAndLatePermissionDoesNotScheduleOverdueAlert() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .notDetermined
        let match = event(start: now.addingTimeInterval(600))
        await h.store.reconcile(events: [match])
        XCTAssertEqual(h.client.prompts, 0)
        h.client.onPrompt = { h.clock.now = self.now.addingTimeInterval(301) }
        let result = await h.store.enable(match)
        XCTAssertEqual(result, .tooLate)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 1)
    }

    func testLateUnknownAndChannelOptInsNeverGenerateImmediateNotifications() async throws {
        let h = try harness(); defer { h.clean() }
        for match in [event(start: now.addingTimeInterval(300)), event(start: now.addingTimeInterval(-60)),
            event(start: nil), event(start: now.addingTimeInterval(7200), channel: true)] {
            let result = await h.store.enable(match)
            XCTAssertEqual(result, .tooLate)
        }
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testCancellationDuringPermissionCannotResurrectReminder() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .notDetermined
        h.client.onPrompt = { h.store.cancel("match") }
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.matchday.savedMatches.isEmpty)
    }

    func testCancelBeforePermissionCheckReturnsDoesNotShowSystemPrompt() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .notDetermined
        h.client.onStatus = { h.store.cancel("match") }
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(h.client.prompts, 0)
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testCancellationWhileSystemAddIsInFlightRemovesLateCompletion() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.onAdd = { _ in h.store.cancel("match") }
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.records.isEmpty)
    }

    func testTerminalReceiptQueuedDuringPermissionOrAddReconcilesTheCompletedOptInAndNewBookmark() async throws {
        for stage in ["permission", "add"] {
            let h = try harness(); defer { h.clean() }
            let entered = expectation(description: "enable suspended in \(stage)")
            let gate = ReminderSuspension(entered: entered)
            if stage == "permission" {
                h.client.permission = .notDetermined
                h.client.beforePromptReturn = { await gate.pause() }
            } else {
                h.client.beforeAddReturn = { _ in await gate.pause() }
            }
            let scheduled = queuedFootballFixture(.scheduled)
            let cancelled = queuedFootballFixture(.cancelled)
            let enabling = Task { @MainActor in await h.store.enable(scheduled) }
            await fulfillment(of: [entered], timeout: 2)
            XCTAssertTrue(h.store.records.isEmpty)
            XCTAssertFalse(h.matchday.contains(eventID: scheduled.id))
            // Production's global saved pass can run while the permission/add
            // owner has not yet created its promised bookmark.
            h.matchday.reconcile(events: [cancelled], at: h.clock.now)
            let enqueued = expectation(description: "terminal reconciliation enqueued")
            var statusReads = 0
            let reconciling = Task { @MainActor in
                enqueued.fulfill()
                await h.store.reconcile(events: [cancelled]) { current in
                    statusReads += 1
                    XCTAssertEqual(current.sportsFixture?.status, .cancelled)
                    XCTAssertTrue(h.store.contains(scheduled.id), "Evidence is derived after the queued enable completes")
                    return .scheduled
                }
            }
            // The task fulfils and enters the MainActor reconciliation without
            // an intervening suspension; its queue wait keeps enable paused.
            await fulfillment(of: [enqueued], timeout: 2)
            XCTAssertTrue(h.store.records.isEmpty)
            gate.resume()
            let enabled = await enabling.value
            await reconciling.value
            XCTAssertEqual(enabled, .scheduled)
            XCTAssertEqual(statusReads, 1)
            XCTAssertTrue(h.client.requests.isEmpty)
            XCTAssertFalse(h.store.contains(scheduled.id))
            XCTAssertTrue(h.matchday.contains(eventID: scheduled.id), "Cancellation revokes the reminder, not its new bookmark")
            XCTAssertEqual(h.matchday.savedMatches.first?.sportsFixture?.status, .cancelled)
            XCTAssertEqual(h.matchday.savedMatches.first?.sportsFixture?.observedAt, now)
        }
    }

    func testQueuedReconciliationWithoutUniqueFixtureEvidenceDoesNotCancelPendingOptIn() async throws {
        for evidence in ["missing", "conflicting"] {
            let h = try harness(); defer { h.clean() }
            let entered = expectation(description: "add suspended for \(evidence) control")
            let gate = ReminderSuspension(entered: entered)
            h.client.beforeAddReturn = { _ in await gate.pause() }
            let scheduled = queuedFootballFixture(.scheduled)
            let cancelled = queuedFootballFixture(.cancelled)
            let unrelated = EventReference(id: cancelled.id, title: "Different Club vs Another Club", category: "football",
                date: cancelled.date, poster: nil, popular: false,
                teams: .init(home: .init(name: "Different Club", badge: nil), away: .init(name: "Another Club", badge: nil)))
            let current = evidence == "missing" ? [] : [cancelled, unrelated]
            let enabling = Task { @MainActor in await h.store.enable(scheduled) }
            await fulfillment(of: [entered], timeout: 2)
            let enqueued = expectation(description: "\(evidence) reconciliation enqueued")
            var statusReads = 0
            let reconciling = Task { @MainActor in
                enqueued.fulfill()
                await h.store.reconcile(events: current) { event in
                    statusReads += 1
                    XCTAssertEqual(event.sportsFixture?.status, .scheduled, "A missing/conflicting ID falls back to the owner's snapshot")
                    return .scheduled
                }
            }
            await fulfillment(of: [enqueued], timeout: 2)
            gate.resume()
            let enabled = await enabling.value
            await reconciling.value
            XCTAssertEqual(enabled, .scheduled)
            XCTAssertEqual(statusReads, 1)
            XCTAssertTrue(h.store.contains(scheduled.id))
            XCTAssertEqual(h.client.requests.count, 1)
            XCTAssertEqual(h.client.adds, 1, "An unchanged queued pass does not schedule a second request")
            XCTAssertEqual(h.matchday.savedMatches.first?.sportsFixture?.status, .scheduled)
        }
    }

    func testUnsaveRevokesReminderWithoutTouchingOtherMatches() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event("one", start: now.addingTimeInterval(7200)))
        _ = await h.store.enable(event("two", start: now.addingTimeInterval(7200)))
        h.matchday.remove(eventID: "one")
        XCTAssertFalse(h.store.contains("one"))
        XCTAssertFalse(h.matchday.contains(eventID: "one"))
        XCTAssertTrue(h.store.contains("two"))
        XCTAssertEqual(h.client.requests.count, 1)
    }

    func testCancellationDuringRescheduleCannotRecreateSystemRequest() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        h.client.onAdd = { _ in h.store.cancel("match") }
        await h.store.reconcile(events: [event(start: now.addingTimeInterval(10_800))])
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.records.isEmpty)
    }

    func testEarlierRescheduleSkipsMissedReminderAndUnknownTimeRevokesIt() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        await h.store.reconcile(events: [event(start: now.addingTimeInterval(240))])
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.store.records.first?.fireDate, now.addingTimeInterval(-60))
        await h.store.reconcile(events: [event(start: nil)])
        XCTAssertTrue(h.store.records.isEmpty)
    }

    func testConcurrentOptInsConvergeToOneRequest() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        async let first = h.store.enable(match)
        async let second = h.store.enable(match)
        _ = await (first, second)
        XCTAssertEqual(h.store.records.count, 1)
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertTrue(h.store.busyIDs.isEmpty)
    }

    func testRescheduleReplacesRequestUpdatesSavedSnapshotAndDoesNotDuplicate() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        let changed = event(start: now.addingTimeInterval(10_800))
        await h.store.reconcile(events: [changed])
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertEqual(h.store.records.first?.fireDate, now.addingTimeInterval(10_500))
        XCTAssertEqual(h.matchday.savedMatches.first?.event.kickoffDate, changed.kickoffDate)
        let adds = h.client.adds
        await h.store.reconcile(events: [changed])
        XCTAssertEqual(h.client.adds, adds, "An unchanged catalog refresh must not reschedule the same alert")
    }

    func testPostponedCancelledAndAlreadyLiveMatchesRevokePendingReminder() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        for status: FootballMatch.MatchStatus in [.postponed, .cancelled, .inPlay, .finished] {
            _ = await h.store.enable(match)
            await h.store.reconcile(events: []) { _ in status }
            XCTAssertTrue(h.client.requests.isEmpty)
            XCTAssertFalse(h.store.contains(match.id))
        }
    }

    func testHeldCricketStartRevokesItsReminderButKeepsTheSavedMatch() async throws {
        let h = try harness(); defer { h.clean() }
        let start = now.addingTimeInterval(7200)
        func cricket(verified: Bool) -> EventReference {
            .init(id: "cricket-fixture:icc:reminded", title: "India U19 vs Australia U19", category: "cricket",
                date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "India U19", badge: nil), away: .init(name: "Australia U19", badge: nil)), cricketFixture: .init(fixtureID: "icc:reminded", competitionID: "icc",
                    competitionName: "U19 internationals", format: .odi, status: .scheduled,
                    observedAt: now, verified: verified))
        }
        let accepted = cricket(verified: true)
        let result = await h.store.enable(accepted)
        XCTAssertEqual(result, .scheduled)
        XCTAssertTrue(h.store.contains(accepted.id))
        let held = cricket(verified: false)
        await h.store.reconcile(events: [held])
        XCTAssertFalse(h.store.contains(accepted.id))
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.matchday.contains(eventID: accepted.id))
        let retry = await h.store.enable(held)
        XCTAssertEqual(retry, .tooLate)
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testVerifiedTerminalFixtureEvidenceRevokesOptInWithoutRemovingSavedMatch() async throws {
        for kind in ["sports", "cricket"] {
            for terminal in ["finished", "cancelled"] {
                let h = try harness(); defer { h.clean() }
                let start = now.addingTimeInterval(7200)
                let formatter = ISO8601DateFormatter()
                func fixtureEvents(_ status: String) -> [EventReference] {
                    let receipt = formatter.string(from: h.clock.now)
                    let sourceURL = "https://example.com/official-fixtures"
                    if kind == "sports" {
                        let fixture = SportsFixtureCatalog.Fixture(id: "sports-fixture:mlb:reminded", sport: "baseball",
                            start: formatter.string(from: start), status: SportsFixtureCatalog.Status(rawValue: status)!,
                            eventKind: .match, title: "Seattle Mariners vs New York Yankees", competitionId: "mlb", competitionName: "MLB",
                            participants: [.init(id: "sea", name: "Seattle Mariners"), .init(id: "nyy", name: "New York Yankees")],
                            squad: .init(gender: .men, ageGroup: "senior"),
                            source: .init(name: "Official fixture", url: sourceURL, observedAt: receipt))
                        let snapshot = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: receipt,
                            revision: "reminder-\(status)", sourceStatus: .verified, fixtures: [fixture],
                            coverage: [.init(sport: "baseball", competitionId: "mlb", competitionName: "MLB", status: .covered,
                                checkedAt: receipt, fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)])
                        return status == "scheduled"
                            ? SportsFixtureCatalog.merging(into: [], snapshot: snapshot, at: h.clock.now)
                            : SportsFixtureCatalog.terminalEvents(from: snapshot)
                    }
                    let fixture = CricketFixtureCatalog.Fixture(id: "wi-reminded", start: formatter.string(from: start), format: .odi,
                        status: CricketFixtureCatalog.Status(rawValue: status)!, competitionId: "west-indies", competitionName: "West Indies ODI",
                        home: .init(id: "wi", name: "West Indies"), away: .init(id: "ind", name: "India"),
                        source: .init(name: "Official fixture", url: sourceURL, observedAt: receipt))
                    let snapshot = CricketFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: receipt,
                        revision: "reminder-\(status)", sourceStatus: .verified, fixtures: [fixture],
                        coverage: [.init(competitionId: "west-indies", competitionName: "West Indies ODI", status: .covered,
                            checkedAt: receipt, fixtureCount: 1, expectedFixtureCount: nil, nextStart: nil)])
                    return status == "scheduled"
                        ? CricketFixtureCatalog.merging(into: [], snapshot: snapshot, at: h.clock.now)
                        : CricketFixtureCatalog.terminalEvents(from: snapshot)
                }
                let scheduled = try XCTUnwrap(fixtureEvents("scheduled").first)
                let result = await h.store.enable(scheduled)
                XCTAssertEqual(result, .scheduled)
                XCTAssertEqual(h.client.requests.count, 1)
                h.clock.now = now.addingTimeInterval(12 * 3600)
                let ended = try XCTUnwrap(fixtureEvents(terminal).first)
                // Production performs saved reconciliation first, then reminder reconciliation.
                h.matchday.reconcile(events: [ended], at: h.clock.now)
                await h.store.reconcile(events: [ended])
                XCTAssertTrue(h.client.requests.isEmpty, "\(kind)/\(terminal)")
                XCTAssertFalse(h.store.contains(scheduled.id))
                XCTAssertTrue(h.matchday.contains(eventID: scheduled.id), "Revoking an alert is not removing a bookmark")
                XCTAssertEqual(h.client.prompts, 0, "No system permission/delivery activity is needed for reconciliation")
                let saved = try XCTUnwrap(h.matchday.savedMatches.first).event
                XCTAssertEqual(saved.sportsFixture?.observedAt ?? saved.cricketFixture?.observedAt, h.clock.now)
                XCTAssertEqual(MatchdayEventStatePolicy.section(for: saved, at: h.clock.now), .recent)
            }
        }
    }

    func testVerifiedFutureFootballCancellationRevokesReminderDespiteLaggingScheduledScore() async throws {
        for score: FootballMatch.MatchStatus in [.scheduled, .timed] {
            let h = try harness(); defer { h.clean() }
            let start = now.addingTimeInterval(7200)
            func fixture(_ status: SportsFixtureCatalog.Status, verified: Bool = true) -> EventReference {
                let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:cancelled", sport: "football",
                    competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                    title: "Bournemouth vs Liverpool",
                    participants: [.init(id: "bournemouth", name: "Bournemouth", role: "home"),
                                   .init(id: "liverpool", name: "Liverpool", role: "away")],
                    squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: verified)
                return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
                    date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
                    teams: .init(home: .init(name: "Bournemouth", badge: nil), away: .init(name: "Liverpool", badge: nil)),
                    sportsFixture: metadata, competitionID: metadata.competitionID)
            }
            let scheduled = fixture(.scheduled)
            let optIn = await h.store.enable(scheduled)
            XCTAssertEqual(optIn, .scheduled)
            XCTAssertEqual(h.client.requests.count, 1)
            let cancelled = fixture(.cancelled)
            XCTAssertEqual(VerifiedFixtureTerminalPolicy.state(for: cancelled, at: now), .cancelled)
            let policy = MatchStartPolicy(event: cancelled, now: now, status: score)
            XCTAssertEqual(policy.status, score, "The raw score contract remains unchanged")
            XCTAssertTrue(policy.isStopped)
            XCTAssertNil(policy.upcomingStart)
            XCTAssertFalse(policy.timingAllowsPlayback)
            XCTAssertFalse(policy.canAttemptPlayback)
            XCTAssertEqual(policy.title, "Cancelled")
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: cancelled, at: now, status: score), .recent)
            h.matchday.reconcile(events: [cancelled], at: h.clock.now)
            await h.store.reconcile(events: [cancelled]) { _ in score }
            XCTAssertTrue(h.client.requests.isEmpty)
            XCTAssertFalse(h.store.contains(scheduled.id))
            XCTAssertTrue(h.matchday.contains(eventID: scheduled.id))
            XCTAssertEqual(h.matchday.savedMatches.first?.sportsFixture?.status, .cancelled)
            XCTAssertEqual(h.client.prompts, 0)

            let control = MatchStartPolicy(event: fixture(.cancelled, verified: false), now: now, status: score)
            XCTAssertNil(VerifiedFixtureTerminalPolicy.state(for: control.event))
            XCTAssertFalse(control.isStopped, "Unverified typed state keeps its existing score precedence")
            XCTAssertNil(control.upcomingStart, "A scheduled score enum does not verify the held fixture's kickoff")
            XCTAssertEqual(control.title, "Start unconfirmed")
            XCTAssertEqual(MatchStartPolicy(event: scheduled, now: now, status: score).upcomingStart, start)
        }
    }

    func testVerifiedTerminalPlaybackPolicyPreservesLiveAndRawFinalLabels() {
        let start = now.addingTimeInterval(-3600)
        func fixture(_ status: SportsFixtureCatalog.Status, verified: Bool = true) -> EventReference {
            let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:ended", sport: "football",
                competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                title: "Bournemouth vs Liverpool",
                participants: [.init(id: "bournemouth", name: "Bournemouth"), .init(id: "liverpool", name: "Liverpool")],
                squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: verified)
            return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
                date: Int64(start.timeIntervalSince1970), poster: nil, popular: false, teams: nil, sportsFixture: metadata, competitionID: metadata.competitionID)
        }
        for score: FootballMatch.MatchStatus in [.inPlay, .paused, .scheduled, .timed, .postponed, .suspended] {
            let ended = MatchStartPolicy(event: fixture(.finished), now: now, status: score)
            XCTAssertTrue(ended.isStopped)
            XCTAssertFalse(ended.canAttemptPlayback)
            XCTAssertEqual(ended.title, "Finished")
            let existingCanPlay = score.isUpcoming || score.isLive
            XCTAssertEqual(MatchStartPolicy(event: fixture(.live), now: now, status: score).timingAllowsPlayback, existingCanPlay)
            XCTAssertEqual(MatchStartPolicy(event: fixture(.finished, verified: false), now: now, status: score).timingAllowsPlayback, score.isLive,
                           "An unverified start plays only on a live score, never on its listed time")
            XCTAssertEqual(MatchStartPolicy(event: fixture(.postponed), now: now, status: score).timingAllowsPlayback, existingCanPlay,
                           "This terminal-only repair does not change postponed-only source ordering")
        }
        for score: FootballMatch.MatchStatus in [.finished, .awarded, .cancelled] {
            XCTAssertEqual(MatchStartPolicy(event: fixture(.finished), now: now, status: score).title, score.displayText)
        }
        let cricket = CricketFixtureMetadata(fixtureID: "wi-terminal", competitionID: "west-indies",
            competitionName: "West Indies ODI", format: .odi, status: .cancelled, observedAt: now, verified: true)
        let cancelledCricket = EventReference(id: "cricket-fixture:wi-terminal", title: "West Indies vs India", category: "cricket",
            date: Int64(now.addingTimeInterval(7200).timeIntervalSince1970), poster: nil, popular: false, teams: nil, cricketFixture: cricket)
        XCTAssertTrue(MatchStartPolicy(event: cancelledCricket, now: now, status: .scheduled).isStopped)
        XCTAssertNil(MatchStartPolicy(event: cancelledCricket, now: now, status: .scheduled).upcomingStart)
        XCTAssertEqual(MatchStartPolicy(event: cancelledCricket, now: now, status: .scheduled).title, "Cancelled")
    }

    func testMissingCatalogIsNotCancellationAndRelaunchDoesNotRecreateDueAlert() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        _ = await h.store.enable(match)
        await h.store.reconcile(events: [])
        XCTAssertTrue(h.store.contains(match.id))
        XCTAssertEqual(h.client.requests.count, 1)
        h.clock.now = now.addingTimeInterval(7000)
        h.client.requests.removeAll() // the system has fired the alert
        await h.store.reconcile(events: [])
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testRevokedPermissionAndFailedSchedulingRemainTruthful() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        h.client.failAdd = true
        let failed = await h.store.enable(match)
        XCTAssertEqual(failed, .failed)
        XCTAssertFalse(h.store.contains(match.id))
        h.client.failAdd = false
        _ = await h.store.enable(match)
        h.client.permission = .denied
        await h.store.reconcile(events: [])
        XCTAssertFalse(h.store.notificationsAllowed)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.contains(match.id), "Retain explicit intent, but never show it as deliverable with permission off")
        h.client.permission = .authorized
        await h.store.reconcile(events: [])
        XCTAssertEqual(h.client.requests.count, 1)
    }

    func testReminderCapLeavesRoomForFPLAndNeverRemovesUnrelatedNotifications() async throws {
        let h = try harness(); defer { h.clean() }
        let fpl = UNNotificationRequest(identifier: "fotty.fpl.deadline.2.120", content: UNMutableNotificationContent(), trigger: nil)
        h.client.requests[fpl.identifier] = fpl
        for index in 0..<MatchReminderStore.maximumReminders {
            let result = await h.store.enable(event("m\(index)", start: now.addingTimeInterval(7200)))
            XCTAssertEqual(result, .scheduled)
        }
        let overflow = await h.store.enable(event("overflow", start: now.addingTimeInterval(7200)))
        XCTAssertEqual(overflow, .limitReached)
        await h.store.reconcile(events: [])
        XCTAssertNotNil(h.client.requests[fpl.identifier])
        XCTAssertEqual(h.client.requests.count, MatchReminderStore.maximumReminders + 1)
    }

    func testReminderRouteTargetsMatchdayNotPlayerOrMatchCenter() throws {
        let navigation = MatchNavigationStore.shared
        defer { navigation.pendingMatchID = nil; navigation.pendingReminderID = nil }
        let url = try XCTUnwrap(URL(string: "fotty://matchday/catalog-123"))
        XCTAssertEqual(FottyDeepLinkDestination.parse(url), .matchday("catalog-123"))
        navigation.pendingMatchID = "old"
        navigation.open(url: url)
        XCTAssertEqual(navigation.pendingReminderID, "catalog-123")
        XCTAssertNil(navigation.pendingMatchID)
        XCTAssertNil(navigation.activeLivePlayerMatchID)
    }

    func testFPLDestinationClearsCompetingMatchRoutes() throws {
        let navigation = MatchNavigationStore.shared
        defer {
            navigation.pendingMatchID = nil
            navigation.pendingReminderID = nil
            navigation.pendingFPL = false
        }
        navigation.pendingMatchID = "old-match"
        navigation.pendingReminderID = "old-reminder"

        navigation.openFPL()

        XCTAssertTrue(navigation.pendingFPL)
        XCTAssertNil(navigation.pendingMatchID)
        XCTAssertNil(navigation.pendingReminderID)
        XCTAssertEqual(
            FottyDeepLinkDestination.parse(try XCTUnwrap(URL(string: "fotty://fpl"))),
            .fpl
        )
    }

    func testMatchCenterCannotBeginPrematureResolutionEvenViaDirectAction() {
        let match = event(start: Date().addingTimeInterval(7200))
        let model = MatchHubViewModel(testEvent: match)
        model.watchLive()
        XCTAssertFalse(model.isFindingStream)
        XCTAssertFalse(model.showPlayer)
        XCTAssertNil(model.playerEvent)
        XCTAssertTrue(model.streamSessions.isEmpty)
    }

    func testFailureFeedbackIsPerEventAndExplicitRetryClearsIt() {
        let feedback = MatchPlaybackFeedback()
        feedback.notReady("one")
        XCTAssertFalse(feedback.notReadyIDs.contains("two"))
        feedback.attempting("one")
        XCTAssertTrue(feedback.notReadyIDs.isEmpty)
    }

    func testCountdownControlsRenderNonblankInBothModesAndNarrowLargeText() throws {
        for (width, scheme, size) in [(320.0, ColorScheme.dark, DynamicTypeSize.large),
            (375.0, .dark, .large), (375.0, .light, .large),
            (375.0, .light, .accessibility2), (820.0, .dark, .large), (820.0, .light, .large)] {
            let content = VStack(alignment: .leading, spacing: 14) {
                Text("Now & next").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                ForEach([7200.0, 280, 110, -10], id: \.self) { offset in
                    let match = self.event("qa-\(offset)", start: Date().addingTimeInterval(offset))
                    if let item = HomeSportsDiscovery(events: [match]).items.first {
                        HomeDiscoveryRow(item: item, isSaved: false, onOpen: {}, onSave: {})
                            .environment(LiveScoreService.shared)
                    }
                    Divider()
                }
            }
            .padding(16).frame(width: width)
            .background(FottyTheme.background)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let image = try FottyHostedViewSnapshot.image(content, width: width, scheme: scheme, type: size)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertLessThan(image.size.height, 2200)
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16)
            let attachment = XCTAttachment(image: image)
            attachment.name = "countdown-\(Int(width))-\(scheme)-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCompactRowOnlyStacksWhenWidthOrAccessibilityRequiresIt() {
        XCTAssertTrue(MatchRowLayout.fitsBeside(width: 250, informationMinimum: 150, actionWidth: 88))
        XCTAssertFalse(MatchRowLayout.fitsBeside(width: 249, informationMinimum: 150, actionWidth: 88))
        XCTAssertTrue(MatchRowLayout.fitsBeside(width: 343, informationMinimum: 150, actionWidth: 140))
        XCTAssertTrue(MatchRowLayout.fitsBeside(width: 788, informationMinimum: 150, actionWidth: 140))
        XCTAssertFalse(MatchRowLayout.fitsBeside(width: 788, informationMinimum: 150, actionWidth: 88, forceStack: true))
    }

    func testActualHomeAndLineupKeepWatchOnTheRightWithoutAnExtraStrip() throws {
        for width in [320.0, 375, 820] {
            for scheme: ColorScheme in [.light, .dark] {
                let match = event("compact-live", start: Date().addingTimeInterval(-10))
                let item = try XCTUnwrap(HomeSportsDiscovery(events: [match]).items.first)
                let rows = [
                    AnyView(HomeDiscoveryRow(item: item, isSaved: false, onOpen: {}, onSave: {}, alternateActionTitle: "Watch")),
                    AnyView(LiveEventCard(event: match, onWatchTap: {}, alternateActionTitle: "Watch", onSaveTap: {})),
                    AnyView(LiveEventCard(event: event("compact-channel", start: nil, channel: true), onWatchTap: {}, alternateActionTitle: "Watch", onSaveTap: {}))
                ]
                for (index, row) in rows.enumerated() {
                    let content = row.padding(.horizontal, 16).frame(width: width)
                        .background(FottyTheme.background).environment(LiveScoreService.shared)
                        .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .large)
                    let image: UIImage
                    if index == 0 {
                        // Home's native More menu needs a UIKit hierarchy;
                        // ImageRenderer draws an unsupported-control symbol.
                        image = try FottyHostedViewSnapshot.image(content, width: width, scheme: scheme, type: .large)
                    } else {
                        let renderer = ImageRenderer(content: content)
                        renderer.scale = 1
                        image = try XCTUnwrap(renderer.uiImage)
                    }
                    XCTAssertLessThan(image.size.height, 150, "Normal live rows must not reserve another action strip")
                    let gold = try accentBounds(in: image)
                    XCTAssertGreaterThan(gold.minX, width * 0.55, "Watch must be beside, not below, the teams")
                    XCTAssertEqual(gold.midY, image.size.height / 2, accuracy: 3)
                    XCTAssertGreaterThanOrEqual(gold.height, 43)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "compact-\(["home", "lineup", "channel"][index])-\(Int(width))-\(scheme)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testLineupRendersUpcomingLongNamesChannelsAndLargeText() throws {
        for (width, size) in [(343.0, DynamicTypeSize.large), (343.0, .accessibility2), (788.0, .large)] {
            let longMatch = AnalyticalDataEngine.EventReference(id: "compact-cpl",
                title: "St Kitts and Nevis Patriots vs Trinbago Knight Riders", category: "cricket",
                date: Int64(Date().addingTimeInterval(7200).timeIntervalSince1970), poster: nil,
                popular: nil, teams: nil)
            let content = VStack(spacing: 12) {
                LiveEventCard(event: longMatch, onSaveTap: {})
                LiveEventCard(event: event("channel", start: nil, channel: true), onWatchTap: {}, onSaveTap: {})
            }
            .padding(16).frame(width: width).background(FottyTheme.background)
            .environment(LiveScoreService.shared).environment(\.dynamicTypeSize, size).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertLessThan(image.size.height, 1000)
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16)
            let attachment = XCTAttachment(image: image)
            attachment.name = "compact-variety-\(Int(width))-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testScheduleRowCountdownDoesNotReserveATeamNameSizedActionColumn() throws {
        let start = now.addingTimeInterval(17 * 3600 + 20 * 60)
        let match = AnalyticalDataEngine.EventReference(id: "schedule-layout-women",
            title: "Zimbabwe Women vs West Indies Women", category: "cricket",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Zimbabwe Women", badge: nil),
                         away: .init(name: "West Indies Women", badge: nil)))
        let item = try XCTUnwrap(HomeSportsDiscovery(events: [match], now: now).items.first)
        for width in [320.0, 375, 430, 788] {
            for scheme: ColorScheme in [.light, .dark] {
                let row = HomeScheduleRow(item: item, presentation: .init(item: item), now: now,
                    isSaved: false, onOpen: {}, onSave: {})
                let content = row.padding(.horizontal, 16).frame(width: width)
                    .background(FottyTheme.background).environment(LiveScoreService.shared)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .large)
                let image = try FottyHostedViewSnapshot.image(content, width: width, scheme: scheme, type: .large)
                XCTAssertEqual(image.size.width, width, accuracy: 1)
                XCTAssertLessThan(image.size.height, 130,
                                  "Normal text must not become a four-line team column beside the countdown")
                let attachment = XCTAttachment(image: image)
                attachment.name = "schedule-women-\(Int(width))-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testScheduleRowLongCompetitionAndAccessibilityTextCanGrowWithoutShrinking() throws {
        let match = AnalyticalDataEngine.EventReference(id: "schedule-layout-cpl",
            title: "St Kitts and Nevis Patriots vs Trinbago Knight Riders", category: "cricket",
            date: Int64(now.addingTimeInterval(2 * 86400).timeIntervalSince1970), poster: nil,
            popular: false, teams: nil)
        let item = try XCTUnwrap(HomeSportsDiscovery(events: [match], now: now).items.first)
        for (width, size) in [(320.0, DynamicTypeSize.accessibility2), (430.0, .accessibility5), (788.0, .large)] {
            let content = HomeScheduleRow(item: item, presentation: .init(item: item),
                now: now, isSaved: false, onOpen: {}, onSave: {})
                .padding(16).frame(width: width).background(FottyTheme.background)
                .environment(LiveScoreService.shared).environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .dark)
            let image = try FottyHostedViewSnapshot.image(content, width: width, scheme: .dark, type: size)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertLessThan(image.size.height, 1000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "schedule-reflow-\(Int(width))-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testChannelRowUsesOneIdentityLineAndKeepsWatchBesideIt() throws {
        for width in [320.0, 375, 788] {
            let row = LiveEventCard(event: event("channel-layout", start: nil, channel: true), onWatchTap: {}, alternateActionTitle: "Watch")
            let renderer = ImageRenderer(content: row.padding(.horizontal, 16).frame(width: width)
                .background(FottyTheme.background).environment(LiveScoreService.shared)
                .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertLessThanOrEqual(image.size.height, 86, "Do not repeat channel type/status in another two lines")
            let button = try accentBounds(in: image)
            XCTAssertGreaterThan(button.minX, width * 0.55)
            XCTAssertGreaterThanOrEqual(button.height, 43)
            let attachment = XCTAttachment(image: image)
            attachment.name = "channel-row-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testHostedScheduleRowExpandsForAccessibilityTextInsteadOfShrinking() throws {
        let match = event("hosted-schedule", start: now.addingTimeInterval(7200), source: false)
        let item = try XCTUnwrap(HomeSportsDiscovery(events: [match], now: now).items.first)
        for width in [320.0, 430, 788] {
            let row = HomeScheduleRow(item: item, presentation: .init(item: item), now: now,
                isSaved: false, onOpen: {}, onSave: {})
                .padding(.horizontal, 16).environment(LiveScoreService.shared)
            // Off-screen ImageRenderer does not emulate the host's text traits
            // or focus-owned controls. Measure the actual hosted SwiftUI row.
            let normalSize = hostedSize(row.environment(\.dynamicTypeSize, .large), width: width, category: .large)
            let expandedSize = hostedSize(row.environment(\.dynamicTypeSize, .accessibility3),
                                          width: width, category: .accessibilityExtraLarge)
            XCTAssertEqual(normalSize.width, width, accuracy: 1)
            XCTAssertLessThanOrEqual(expandedSize.width, width + 1)
            let text = Text("Upcoming match").font(.subheadline)
            let normalText = hostedSize(text.environment(\.dynamicTypeSize, .large), width: width, category: .large)
            let expandedText = hostedSize(text.environment(\.dynamicTypeSize, .accessibility3),
                                          width: width, category: .accessibilityExtraLarge)
            if expandedText.height > normalText.height + 0.5 {
                XCTAssertGreaterThan(expandedSize.height, normalSize.height,
                                     "Larger hosted text must expand/reflow, never shrink to the normal row")
            } else {
                XCTAssertGreaterThanOrEqual(expandedSize.height, normalSize.height,
                                            "Stacking must not shrink when off-screen Catalyst does not enlarge semantic fonts")
            }
        }
    }

    private func hostedSize<Content: View>(_ content: Content, width: CGFloat,
                                          category: UIContentSizeCategory) -> CGSize {
        let host = UIHostingController(rootView: content)
        host.loadViewIfNeeded()
        host.traitOverrides.preferredContentSizeCategory = category
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 2_000)
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: width, height: 2_000))
    }

    private func accentBounds(in image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<height {
            var runStart: Int?
            for x in 0...width {
                let offset = (y * width + x) * 4
                let isGold = x < width && pixels[offset] > 220 && pixels[offset + 1] > 140
                    && pixels[offset + 1] < 230 && pixels[offset + 2] < 90 && pixels[offset + 3] > 240
                if isGold {
                    if runStart == nil { runStart = x }
                } else if let start = runStart {
                    // Identify the filled button, not gold LIVE text or badge
                    // details. Its continuous fill is wider than any glyph.
                    if x - start >= 32 { xs += [start, x - 1]; ys.append(y) }
                    runStart = nil
                }
            }
        }
        let x = try XCTUnwrap(xs.min()), y = try XCTUnwrap(ys.min())
        return CGRect(x: x, y: y, width: try XCTUnwrap(xs.max()) - x + 1, height: try XCTUnwrap(ys.max()) - y + 1)
    }

    func testUpcomingHomeInformationIsNotRenderedAsADisabledButton() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains(".disabled(!MatchStartPolicy"))
        XCTAssertTrue(source.contains("A future fixture is readable information"))
    }
}

@MainActor
private final class ReminderClock { var now: Date; init(_ now: Date) { self.now = now } }

@MainActor
private final class ReminderHarness {
    let suite = "FottyTests.Reminders.\(UUID().uuidString)"
    let defaults: UserDefaults
    let client = FakeReminderNotifications()
    let matchday: MyMatchdayStore
    let clock: ReminderClock
    let store: MatchReminderStore
    init(now: Date) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        matchday = MyMatchdayStore(defaults: defaults)
        clock = ReminderClock(now)
        let clock = self.clock
        store = MatchReminderStore(defaults: defaults, client: client, matchday: matchday, clock: { clock.now })
        let reminderStore = store
        matchday.onRemove = { [weak reminderStore] in reminderStore?.cancel($0) }
    }
    func clean() {
        client.onPrompt = nil
        client.onAdd = nil
        client.onStatus = nil
        client.beforePromptReturn = nil
        client.beforeAddReturn = nil
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class ReminderSuspension {
    private let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(entered: XCTestExpectation) { self.entered = entered }
    func pause() async {
        guard !released else { entered.fulfill(); return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func resume() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FakeReminderNotifications: MatchReminderNotificationClient {
    var permission: UNAuthorizationStatus = .authorized
    var requests: [String: UNNotificationRequest] = [:]
    var prompts = 0
    var adds = 0
    var failAdd = false
    var onPrompt: (() -> Void)?
    var onStatus: (() -> Void)?
    var onAdd: ((UNNotificationRequest) -> Void)?
    var beforePromptReturn: (@MainActor () async -> Void)?
    var beforeAddReturn: (@MainActor (UNNotificationRequest) async -> Void)?
    func authorizationStatus() async -> UNAuthorizationStatus { onStatus?(); return permission }
    func requestAuthorization() async throws -> Bool {
        prompts += 1
        onPrompt?()
        await beforePromptReturn?()
        permission = .authorized
        return true
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws {
        adds += 1
        onAdd?(request)
        await beforeAddReturn?(request)
        if failAdd { throw NSError(domain: "ReminderTest", code: 1) }
        requests[request.identifier] = request
    }
    func remove(_ identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
}
