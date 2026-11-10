import XCTest
import UserNotifications
@testable import Fotty

@MainActor
final class SportsReminderBackgroundRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ id: String = "sports-fixture:premier-league:one", hours: Double = 2,
                       category: String = "football", status: SportsFixtureCatalog.Status = .scheduled,
                       verified: Bool = true) -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: id, sport: category, competitionID: "premier-league",
            competitionName: "Premier League", eventKind: .match, title: "Arsenal vs Chelsea",
            participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: verified)
        return .init(id: id, title: metadata.title, category: category,
            date: Int64(now.addingTimeInterval(hours * 3600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata, competitionID: metadata.competitionID)
    }

    func testDefaultOffRegistersOnlyOnceAndNeverFetchesOrSchedules() throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]
        h.service.registerAtLaunch(); h.service.registerAtLaunch()
        h.service.scheduleIfNeeded()
        let task = FakeSportsRefreshTask(); h.service.handle(task)
        XCTAssertFalse(h.service.isEnabled)
        XCTAssertEqual(h.scheduler.registrations, 1)
        XCTAssertTrue(h.scheduler.submissions.isEmpty)
        XCTAssertEqual(h.client.authorizationChecks, 0)
        XCTAssertEqual(h.client.refreshCalls, 0)
        XCTAssertEqual(task.results, [true])
    }

    func testEnabledWithoutFutureRemindersStillSchedulesAndFetchesNothing() throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        let task = FakeSportsRefreshTask(); h.service.handle(task)
        XCTAssertTrue(h.scheduler.submissions.isEmpty)
        XCTAssertEqual(h.client.refreshCalls, 0)
        XCTAssertEqual(task.results, [true])
    }

    func testOptInSchedulesOneBoundedRequestAndDisableCancelsOnlyThisLane() throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        XCTAssertEqual(h.scheduler.submissions, [now.addingTimeInterval(15 * 60)])
        XCTAssertEqual(h.scheduler.pending.count, 1)
        h.service.scheduleIfNeeded()
        XCTAssertEqual(h.scheduler.pending.count, 1)
        h.service.setEnabled(false)
        XCTAssertTrue(h.scheduler.pending.isEmpty)
        XCTAssertFalse(h.defaults.bool(forKey: SportsReminderBackgroundRefresh.preferenceKey))
    }

    func testRegistrationAndSubmissionFailuresAreObservableWithoutChangingOptIn() throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]; h.scheduler.registrationResult = false
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        XCTAssertTrue(h.service.schedulingUnavailable)
        XCTAssertTrue(h.service.isEnabled)
        XCTAssertTrue(h.scheduler.submissions.isEmpty)
        let other = try BackgroundRefreshHarness(now: now); defer { other.clean() }
        other.client.events = [event()]; other.scheduler.rejectSubmit = true
        other.service.registerAtLaunch(); other.service.setEnabled(true)
        XCTAssertTrue(other.service.schedulingUnavailable)
        XCTAssertTrue(other.service.isEnabled)
    }

    func testDeniedNotificationPermissionNeverPromptsOrFetchesMetadata() async throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]; h.client.allowed = false
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        let done = expectation(description: "task finished")
        let task = FakeSportsRefreshTask(); task.onComplete = { done.fulfill() }
        h.service.handle(task)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(h.client.authorizationChecks, 1)
        XCTAssertEqual(h.client.refreshCalls, 0)
        XCTAssertEqual(h.client.reconcileCalls, 0)
        XCTAssertEqual(task.results, [false])
    }

    func testSuccessfulRunUsesOnlyRelevantExistingMetadataAndCompletesExactlyOnce() async throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]; h.client.updated = [event(hours: 3)]
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        let done = expectation(description: "task finished")
        let task = FakeSportsRefreshTask(); task.onComplete = { done.fulfill() }
        h.service.handle(task)
        await fulfillment(of: [done], timeout: 2)
        task.expire()
        XCTAssertEqual(task.results, [true])
        XCTAssertEqual(h.client.requestedScopes, [.sports])
        XCTAssertEqual(h.client.reconciled.map(\.id), h.client.updated.map(\.id))
        XCTAssertEqual(h.scheduler.pending.count, 1)
    }

    func testScopePlanningSeparatesCPLFromOtherCricketAndNeverInventsStreamWork() {
        let cricket = EventReference(id: "icc-one", title: "West Indies vs India", category: "cricket",
            date: Int64(now.addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil)
        let cpl = CPLSchedule.Fixture(1, ISO8601DateFormatter().string(from: now.addingTimeInterval(3600)), .trinbago, .guyana).event()
        let channel = EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: -3_600_000,
            poster: nil, popular: false, teams: nil)
        XCTAssertEqual(SportsReminderBackgroundRefresh.scopes(for: [event(), cricket, cpl, channel]), [.sports, .cricket, .cpl])
        XCTAssertTrue(SportsReminderBackgroundRefresh.scopes(for: [channel]).isEmpty)
    }

    func testExpirationDuringAuthorizationCompletesFalseWithoutAnyLaterFetch() async throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]
        let entered = expectation(description: "authorization suspended"), drained = expectation(description: "authorization returned")
        let gate = BackgroundRefreshGate(entered)
        h.client.beforeAuthorization = { await gate.wait(); drained.fulfill() }
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        let task = FakeSportsRefreshTask(); h.service.handle(task)
        await fulfillment(of: [entered], timeout: 2)
        task.expire(); task.expire(); gate.release()
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(task.results, [false])
        XCTAssertEqual(h.client.refreshCalls, 0)
        XCTAssertEqual(h.client.reconcileCalls, 0)
    }

    func testExpirationAndDuplicateRunsCannotPublishLateMetadataOrOverlapDrainingWork() async throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        h.client.events = [event()]; h.client.updated = [event(hours: 3)]
        let entered = expectation(description: "provider suspended"), drained = expectation(description: "provider returned")
        let gate = BackgroundRefreshGate(entered)
        h.client.beforeRefresh = { await gate.wait(); drained.fulfill() }
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        let task = FakeSportsRefreshTask(); h.service.handle(task)
        await fulfillment(of: [entered], timeout: 2)
        let duplicate = FakeSportsRefreshTask(); h.service.handle(duplicate)
        XCTAssertEqual(duplicate.results, [false])
        task.expire()
        let whileDraining = FakeSportsRefreshTask(); h.service.handle(whileDraining)
        XCTAssertEqual(whileDraining.results, [false])
        gate.release(); await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(task.results, [false])
        XCTAssertEqual(h.client.refreshCalls, 1)
        XCTAssertEqual(h.client.reconcileCalls, 0)
    }

    func testDisablingDuringProviderAwaitRevokesTheLeaseWithoutCancellingReminderIntent() async throws {
        let h = try BackgroundRefreshHarness(now: now); defer { h.clean() }
        let original = event(); h.client.events = [original]
        let entered = expectation(description: "provider suspended"), drained = expectation(description: "provider returned")
        let gate = BackgroundRefreshGate(entered)
        h.client.beforeRefresh = { await gate.wait(); drained.fulfill() }
        h.service.registerAtLaunch(); h.service.setEnabled(true)
        let task = FakeSportsRefreshTask(); h.service.handle(task)
        await fulfillment(of: [entered], timeout: 2)
        h.service.setEnabled(false); gate.release()
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(task.results, [false])
        XCTAssertTrue(h.scheduler.pending.isEmpty)
        XCTAssertEqual(h.client.events.map(\.id), [original.id])
        XCTAssertEqual(h.client.reconcileCalls, 0)
    }

    func testCancellationDuringNotificationAuthorizationOrPendingReadCannotMutateReminders() async throws {
        for stage in ["authorization", "pending"] {
            let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
            _ = await h.store.enable(event())
            let original = h.store.records
            let entered = expectation(description: "notification client suspended"), gate = BackgroundRefreshGate(entered)
            if stage == "authorization" { h.notifications.beforeAuthorization = { await gate.wait() } }
            else { h.notifications.beforePending = { await gate.wait() } }
            var current = true
            let operation = Task { await h.store.reconcile(events: [event(hours: 3)], shouldContinue: { current }) }
            await fulfillment(of: [entered], timeout: 2)
            current = false; gate.release(); await operation.value
            XCTAssertEqual(h.store.records, original)
            XCTAssertEqual(h.notifications.requests.values.first?.content.userInfo["fireDate"] as? Double, original.first?.fireDate.timeIntervalSince1970)
            XCTAssertEqual(h.notifications.prompts, 0)
        }
    }

    func testExpirationDuringRescheduledNotificationAddKeepsAcceptedTimePendingWithoutRestoringObsoleteAlert() async throws {
        for userCancelled in [false, true] {
            let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
            _ = await h.store.enable(event())
            let accepted = event(hours: 3)
            let entered = expectation(description: "notification add suspended"), gate = BackgroundRefreshGate(entered)
            h.notifications.beforeAdd = { await gate.wait() }
            var current = true
            let operation = Task { await h.store.reconcile(events: [accepted], shouldContinue: { current }) }
            await fulfillment(of: [entered], timeout: 2)
            current = false
            if userCancelled { h.store.cancel(event().id) }
            gate.release(); await operation.value
            if userCancelled {
                XCTAssertTrue(h.store.records.isEmpty)
                XCTAssertTrue(h.notifications.requests.isEmpty)
            } else {
                XCTAssertEqual(h.store.records.first?.snapshot.event.kickoffDate, accepted.kickoffDate)
                XCTAssertEqual(h.store.records.first?.fireDate, now.addingTimeInterval(3 * 3600 - 300))
                XCTAssertEqual(h.matchday.savedMatches.first?.event.kickoffDate, accepted.kickoffDate)
                XCTAssertTrue(h.notifications.requests.isEmpty, "The known-obsolete two-hour alert must not return")
                XCTAssertTrue(h.store.failedIDs.contains(accepted.id))
                await h.store.reconcile(events: [accepted])
                XCTAssertEqual(h.notifications.requests.values.first?.content.userInfo["fireDate"] as? Double,
                               now.addingTimeInterval(3 * 3600 - 300).timeIntervalSince1970)
                XCTAssertFalse(h.store.failedIDs.contains(accepted.id))
            }
        }
    }

    func testCancellationAndQueuedReenableAfterInterruptedAddOwnTheNewReminderRevision() async throws {
        let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
        _ = await h.store.enable(event())
        let entered = expectation(description: "notification add suspended"), gate = BackgroundRefreshGate(entered)
        h.notifications.beforeAdd = { await gate.wait() }
        var current = true
        let old = Task { await h.store.reconcile(events: [event(hours: 3)], shouldContinue: { current }) }
        await fulfillment(of: [entered], timeout: 2)
        current = false; h.store.cancel(event().id)
        let replacement = event(hours: 4)
        let replacementTask = Task { await h.store.enable(replacement) }
        gate.release(); await old.value
        let result = await replacementTask.value
        XCTAssertEqual(result, .scheduled)
        XCTAssertEqual(h.store.records.first?.snapshot.event.kickoffDate, replacement.kickoffDate)
        XCTAssertEqual(h.notifications.requests.values.first?.content.userInfo["fireDate"] as? Double,
                       now.addingTimeInterval(4 * 3600 - 300).timeIntervalSince1970)
        XCTAssertFalse(h.store.failedIDs.contains(replacement.id))
    }

    func testMissingOrUnrelatedMetadataPreservesReminderAndNoOverdueAlertIsRecreated() async throws {
        let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
        _ = await h.store.enable(event())
        let original = h.store.records
        await h.store.reconcile(events: [], shouldContinue: { true })
        XCTAssertEqual(h.store.records, original)
        h.now = now.addingTimeInterval(7100)
        h.notifications.requests.removeAll()
        await h.store.reconcile(events: [], shouldContinue: { true })
        XCTAssertTrue(h.notifications.requests.isEmpty)
        XCTAssertEqual(h.notifications.prompts, 0)
    }

    func testInterruptedAddRollbackDoesNotRecreateAnOriginalAlertThatBecameOverdueWhileWaiting() async throws {
        let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
        _ = await h.store.enable(event())
        let entered = expectation(description: "notification add suspended"), gate = BackgroundRefreshGate(entered)
        h.notifications.beforeAdd = { await gate.wait() }
        var current = true
        let operation = Task { await h.store.reconcile(events: [event(hours: 3)], shouldContinue: { current }) }
        await fulfillment(of: [entered], timeout: 2)
        h.now = now.addingTimeInterval(7000)
        current = false; gate.release(); await operation.value
        XCTAssertTrue(h.notifications.requests.isEmpty)
        XCTAssertTrue(h.store.contains(event().id), "Expiry does not revoke the user's explicit reminder intent")
    }

    func testFreshTerminalMetadataCancelsOnlyTheExistingMatchReminderAndRetainsBookmark() async throws {
        let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
        _ = await h.store.enable(event())
        await h.store.reconcile(events: [event(status: .cancelled)], shouldContinue: { true })
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.notifications.requests.isEmpty)
        XCTAssertTrue(h.matchday.contains(eventID: event().id))
    }

    func testVerifiedCurrentTypedLiveStatusNeverSchedulesAnAlreadyStartedReminderEvenWithoutFootballPolling() async throws {
        let h = try BackgroundReminderStoreHarness(now: now); defer { h.clean() }
        _ = await h.store.enable(event())
        await h.store.reconcile(events: [event(status: .live)], shouldContinue: { true })
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.notifications.requests.isEmpty)
        XCTAssertTrue(h.matchday.contains(eventID: event().id))
    }
}

@MainActor private final class FakeSportsRefreshTask: SportsReminderRefreshTask {
    var expiration: (@MainActor () -> Void)?
    var results: [Bool] = []
    var onComplete: (() -> Void)?
    func onExpiration(_ handler: @escaping @MainActor () -> Void) { expiration = handler }
    func complete(success: Bool) { results.append(success); onComplete?() }
    func expire() { expiration?() }
}

@MainActor private final class FakeSportsRefreshScheduler: SportsReminderRefreshScheduler {
    var registrations = 0, submissions: [Date] = [], pending: [Date] = []
    var registrationResult = true, rejectSubmit = false
    func register(_ handler: @escaping @MainActor (any SportsReminderRefreshTask) -> Void) -> Bool { registrations += 1; return registrationResult }
    func submit(earliest: Date) throws {
        if rejectSubmit { throw URLError(.notConnectedToInternet) }
        submissions.append(earliest); pending = [earliest]
    }
    func cancelPending() { pending.removeAll() }
}

@MainActor private final class FakeSportsRefreshClient: SportsReminderRefreshClient {
    var events: [EventReference] = [], updated: [EventReference] = [], reconciled: [EventReference] = []
    var requestedScopes = Set<SportsReminderRefreshScope>()
    var allowed = true, authorizationChecks = 0, refreshCalls = 0, reconcileCalls = 0
    var beforeAuthorization: (@MainActor () async -> Void)?, beforeRefresh: (@MainActor () async -> Void)?
    func pendingReminders(at now: Date) -> [EventReference] { events }
    func notificationsAllowed() async -> Bool { authorizationChecks += 1; await beforeAuthorization?(); return allowed }
    func refresh(scopes: Set<SportsReminderRefreshScope>, at now: Date) async -> [EventReference] {
        refreshCalls += 1; requestedScopes = scopes; await beforeRefresh?(); return updated
    }
    func reconcile(events: [EventReference], shouldContinue: @escaping @MainActor () -> Bool) async {
        guard shouldContinue() else { return }; reconcileCalls += 1; reconciled = events
    }
}

@MainActor private final class BackgroundRefreshHarness {
    let suite = "FottyTests.BackgroundReminders.\(UUID().uuidString)"
    let defaults: UserDefaults
    let scheduler = FakeSportsRefreshScheduler(), client = FakeSportsRefreshClient()
    let service: SportsReminderBackgroundRefresh
    init(now: Date) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        service = SportsReminderBackgroundRefresh(defaults: defaults, scheduler: scheduler, client: client, clock: { now })
    }
    func clean() { service.setEnabled(false); defaults.removePersistentDomain(forName: suite) }
}

@MainActor private final class BackgroundRefreshGate {
    let entered: XCTestExpectation
    var continuation: CheckedContinuation<Void, Never>?, released = false
    init(_ entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0; entered.fulfill() }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class BackgroundReminderNotifications: MatchReminderNotificationClient {
    var requests: [String: UNNotificationRequest] = [:], prompts = 0
    var beforeAuthorization: (@MainActor () async -> Void)?, beforePending: (@MainActor () async -> Void)?, beforeAdd: (@MainActor () async -> Void)?
    func authorizationStatus() async -> UNAuthorizationStatus { await beforeAuthorization?(); return .authorized }
    func requestAuthorization() async throws -> Bool { prompts += 1; return true }
    func pendingRequests() async -> [UNNotificationRequest] { await beforePending?(); return Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws { await beforeAdd?(); requests[request.identifier] = request }
    func remove(_ identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
}

@MainActor private final class BackgroundReminderStoreHarness {
    let suite = "FottyTests.BackgroundReminderStore.\(UUID().uuidString)"
    let defaults: UserDefaults, notifications = BackgroundReminderNotifications(), matchday: MyMatchdayStore
    var now: Date
    lazy var store = MatchReminderStore(defaults: defaults, client: notifications, matchday: matchday, clock: { [unowned self] in self.now })
    init(now: Date) throws {
        self.now = now; defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); matchday = MyMatchdayStore(defaults: defaults)
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}
