import Foundation
import BackgroundTasks
import UserNotifications
import Observation

enum SportsReminderRefreshScope: Hashable, Sendable { case sports, cricket, cpl }

@MainActor
protocol SportsReminderRefreshTask: AnyObject {
    func onExpiration(_ handler: @escaping @MainActor () -> Void)
    func complete(success: Bool)
}

@MainActor
protocol SportsReminderRefreshScheduler {
    func register(_ handler: @escaping @MainActor (any SportsReminderRefreshTask) -> Void) -> Bool
    func submit(earliest: Date) throws
    func cancelPending()
}

@MainActor
protocol SportsReminderRefreshClient {
    func pendingReminders(at now: Date) -> [EventReference]
    func notificationsAllowed() async -> Bool
    func refresh(scopes: Set<SportsReminderRefreshScope>, at now: Date) async -> [EventReference]
    func reconcile(events: [EventReference], shouldContinue: @escaping @MainActor () -> Bool) async
}

/// Opportunistic local maintenance of existing explicit sports reminders.
/// iOS chooses whether/when this runs; no push service or background timer.
@MainActor
@Observable
final class SportsReminderBackgroundRefresh {
    static let shared = SportsReminderBackgroundRefresh()
    static let identifier = "com.jelani.Fotty.sports-reminder-refresh"
    static let preferenceKey = "fotty.sports-reminders.background-refresh.v1"
    static let disclosure = "When iOS allows, refreshes existing sports reminders for changed or cancelled fixtures. iOS may delay or disable checks, and force-quitting Fotty can prevent them. Opening Fotty still refreshes schedules. No streams or FPL data are checked."
    static let minimumDelay: TimeInterval = 15 * 60

    private let defaults: UserDefaults
    private let scheduler: any SportsReminderRefreshScheduler
    private let client: any SportsReminderRefreshClient
    private let clock: () -> Date
    @ObservationIgnored private var registrationAttempted = false
    private(set) var isRegistered = false
    private(set) var schedulingUnavailable = false
    @ObservationIgnored private var active: Run?
    @ObservationIgnored private var draining = Set<UUID>()
    var isEnabled: Bool { defaults.bool(forKey: Self.preferenceKey) }

    private final class Run {
        let id = UUID()
        let handle: any SportsReminderRefreshTask
        var task: Task<Void, Never>?
        init(_ handle: any SportsReminderRefreshTask) { self.handle = handle }
    }

    init(defaults: UserDefaults = .standard, scheduler: (any SportsReminderRefreshScheduler)? = nil,
         client: (any SportsReminderRefreshClient)? = nil, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.scheduler = scheduler ?? SystemSportsReminderRefreshScheduler()
        self.client = client ?? SystemSportsReminderRefreshClient()
        self.clock = clock
    }

    /// Called synchronously from didFinishLaunching, once even when opted out.
    /// Apple requires registration before launch completes for every listed ID.
    func registerAtLaunch() {
        guard !registrationAttempted else { return }
        registrationAttempted = true
        isRegistered = scheduler.register { [weak self] task in
            guard let self else { task.complete(success: false); return }
            self.handle(task)
        }
        schedulingUnavailable = !isRegistered
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.preferenceKey)
        if !enabled {
            scheduler.cancelPending()
            if let run = active { expire(run.id) }
        } else { scheduleIfNeeded() }
    }

    /// Root calls on scene-background/reminder changes. Replaces only our one
    /// pending request; earliest is a lower bound, never a promised run time.
    func scheduleIfNeeded() {
        scheduler.cancelPending()
        guard isRegistered, isEnabled, !client.pendingReminders(at: clock()).isEmpty else { return }
        do {
            try scheduler.submit(earliest: clock().addingTimeInterval(Self.minimumDelay))
            schedulingUnavailable = false
        } catch { schedulingUnavailable = true }
    }

    func handle(_ handle: any SportsReminderRefreshTask) {
        guard active == nil, draining.isEmpty else { handle.complete(success: false); return }
        guard isEnabled, !client.pendingReminders(at: clock()).isEmpty else {
            handle.complete(success: true)
            scheduleIfNeeded()
            return
        }
        let run = Run(handle)
        let runID = run.id
        active = run
        draining.insert(runID)
        handle.onExpiration { [weak self] in self?.expire(runID) }
        run.task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.draining.remove(runID) }
            guard await self.client.notificationsAllowed(), self.owns(runID), !Task.isCancelled else {
                self.finish(runID, success: false)
                return
            }
            let scopes = Self.scopes(for: self.client.pendingReminders(at: self.clock()))
            guard !scopes.isEmpty, self.owns(runID), !Task.isCancelled else {
                self.finish(runID, success: true)
                return
            }
            let events = await self.client.refresh(scopes: scopes, at: self.clock())
            guard self.owns(runID), !Task.isCancelled else { return }
            await self.client.reconcile(events: events, shouldContinue: { [weak self] in self?.owns(runID) == true })
            self.finish(runID, success: !Task.isCancelled)
        }
    }

    private func owns(_ id: UUID) -> Bool { isEnabled && active?.id == id }

    private func expire(_ id: UUID) {
        guard let run = active, run.id == id else { return }
        active = nil
        run.task?.cancel()
        run.handle.complete(success: false)
        scheduleIfNeeded()
    }

    private func finish(_ id: UUID, success: Bool) {
        guard let run = active, run.id == id else { return }
        active = nil
        run.handle.complete(success: success && isEnabled)
        scheduleIfNeeded()
    }

    static func scopes(for events: [EventReference]) -> Set<SportsReminderRefreshScope> {
        Set(events.filter { !$0.hasCatalogIdentityConflict && !$0.isBroadcastChannel }.map {
            if $0.isCPLFixture { return .cpl }
            return $0.normalizedCategory == "cricket" ? .cricket : .sports
        })
    }
}

@MainActor
private struct SystemSportsReminderRefreshClient: SportsReminderRefreshClient {
    func pendingReminders(at now: Date) -> [EventReference] {
        MatchReminderStore.shared.records.filter { $0.fireDate > now }.map { $0.snapshot.event }
    }
    func notificationsAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return [.authorized, .provisional, .ephemeral].contains(status)
    }
    func refresh(scopes: Set<SportsReminderRefreshScope>, at now: Date) async -> [EventReference] {
        await withTaskGroup(of: [EventReference].self) { group in
            if scopes.contains(.sports) {
                group.addTask { @MainActor in
                    let snapshot = await SportsFixtureUpdater.shared.refresh(now: now)
                    let current = Date()
                    let freshIDs = Set((snapshot?.fixtures ?? []).filter {
                        SportsSearchSchedule.isFresh(SportsFixtureCatalog.date($0.source.observedAt), at: current)
                    }.map(\.id))
                    return (SportsFixtureCatalog.merging(into: [], snapshot: snapshot, at: current)
                        + SportsFixtureCatalog.upcomingSearchEvents(from: snapshot, at: current)
                        + SportsFixtureCatalog.terminalEvents(from: snapshot)).filter {
                        $0.sportsFixture?.verified == true
                            && freshIDs.contains($0.id)
                    }
                }
            }
            if scopes.contains(.cricket) {
                group.addTask { @MainActor in
                    let snapshot = await CricketFixtureUpdater.shared.refresh(now: now)
                    let current = Date()
                    return (CricketFixtureCatalog.merging(into: [], snapshot: snapshot, at: current)
                        + CricketFixtureCatalog.upcomingSearchEvents(from: snapshot, at: current)
                        + CricketFixtureCatalog.terminalEvents(from: snapshot)).filter {
                        $0.cricketFixture?.verified == true
                            && SportsSearchSchedule.isFresh($0.cricketFixture?.observedAt, at: current)
                    }
                }
            }
            if scopes.contains(.cpl) {
                group.addTask { @MainActor in
                    guard let snapshot = await CPLScheduleUpdater.shared.refresh(now: now),
                          snapshot.isFreshlyVerified(at: Date()) else { return [] }
                    return CPLSchedule.merging(into: [], fixtures: snapshot.fixtures, at: Date())
                }
            }
            var events: [EventReference] = []
            for await value in group { if !Task.isCancelled { events += value } }
            return AnalyticalDataEngine.deduplicateMatches(events)
        }
    }
    func reconcile(events: [EventReference], shouldContinue: @escaping @MainActor () -> Bool) async {
        await MatchReminderStore.shared.reconcile(events: events, shouldContinue: shouldContinue)
    }
}

@MainActor
private struct SystemSportsReminderRefreshScheduler: SportsReminderRefreshScheduler {
    func register(_ handler: @escaping @MainActor (any SportsReminderRefreshTask) -> Void) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return BGTaskScheduler.shared.register(forTaskWithIdentifier: SportsReminderBackgroundRefresh.identifier, using: .main) { task in
            MainActor.assumeIsolated { handler(SystemSportsReminderRefreshTask(task)) }
        }
        #else
        return false
        #endif
    }
    func submit(earliest: Date) throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let request = BGAppRefreshTaskRequest(identifier: SportsReminderBackgroundRefresh.identifier)
        request.earliestBeginDate = earliest
        try BGTaskScheduler.shared.submit(request)
        #endif
    }
    func cancelPending() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: SportsReminderBackgroundRefresh.identifier)
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
@MainActor
private final class SystemSportsReminderRefreshTask: SportsReminderRefreshTask {
    let task: BGTask
    init(_ task: BGTask) { self.task = task }
    func onExpiration(_ handler: @escaping @MainActor () -> Void) {
        task.expirationHandler = { Task { @MainActor in handler() } }
    }
    func complete(success: Bool) { task.setTaskCompleted(success: success) }
}
#endif
