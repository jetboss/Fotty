import Foundation
import Observation
import UserNotifications

/// Scheduled time is not proof of a working broadcast. Keep that distinction
/// identical in the countdown, accessibility actions and playback entry points.
@MainActor
struct MatchStartPolicy {
    static let playbackLead: TimeInterval = 120
    static let reminderLead: TimeInterval = 300
    let event: AnalyticalDataEngine.EventReference
    var now = Date()
    var status: FootballMatch.MatchStatus? = nil
    var discoveryIndex: FixtureStreamDiscoveryIndex? = nil
    var broadcastRegistry: BroadcastRegistryClient? = nil

    var hasUnconfirmedFixtureStart: Bool {
        event.cricketFixture?.verified == false || event.sportsFixture?.verified == false
    }
    var hasUnconfirmedCricketStart: Bool { event.cricketFixture?.verified == false }

    var isStopped: Bool {
        if VerifiedFixtureTerminalPolicy.state(for: event, at: now) != nil { return true }
        if let status { return !status.isUpcoming && !status.isLive }
        if event.cricketFixture?.status.stopsPlayback == true { return true }
        if event.sportsFixture?.status.stopsPlayback == true { return true }
        return status.map { !$0.isUpcoming && !$0.isLive } ?? false
    }

    private var hasStartedVerifiedCoverage: Bool {
        let enabled = (discoveryIndex ?? .shared).enabledProviderCodes
        guard enabled.contains(ReviewedTVPlaylistClient.providerCode), !event.hasCatalogIdentityConflict else { return false }
        let request = StreamPlaybackRequest(event: event)
        return (broadcastRegistry ?? .shared).lookup(for: request, enabledProviderCodes: [ReviewedTVPlaylistClient.providerCode], at: now).contains {
            $0.link?.matchMethod == .channelAssignment && $0.broadcast.start.map { $0 <= now } == true
                && ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch($0), at: now) != nil
        }
    }

    var upcomingStart: Date? {
        guard !event.isBroadcastChannel, !isStopped, !hasUnconfirmedFixtureStart, !hasStartedVerifiedCoverage, status?.isLive != true,
              event.cricketFixture?.isLive(at: now) != true,
              event.sportsFixture?.isLive(at: now) != true,
              let date = event.kickoffDate, date > now else { return nil }
        return date
    }

    /// Timing only: Match Center may need to rematch an official fixture to a
    /// catalog descriptor, so source existence is checked separately by its UI.
    var timingAllowsPlayback: Bool {
        guard !isStopped else { return false }
        if event.isBroadcastChannel || status?.isLive == true || event.cricketFixture?.isLive(at: now) == true
            || event.sportsFixture?.isLive(at: now) == true { return true }
        // A disputed kickoff cannot invent availability without a descriptor.
        if hasUnconfirmedFixtureStart { return false }
        if hasStartedVerifiedCoverage { return true }
        guard let start = event.kickoffDate else { return true }
        return start.timeIntervalSince(now) <= Self.playbackLead
    }

    var canAttemptPlayback: Bool {
        timingAllowsPlayback && (SportsTVStation.canResolve(event, discoveryIndex: discoveryIndex)
            || CricketChannelPlaybackPolicy.canResolve(event, discoveryIndex: discoveryIndex)
            || !BroadcastRegistryWatchPolicy.matches(for: StreamPlaybackRequest(event: event),
                enabledProviderCodes: (discoveryIndex ?? .shared).enabledProviderCodes,
                discoveryIndex: discoveryIndex, at: now).isEmpty
            || hasFreshDiscoveredCandidate)
    }

    private var hasFreshDiscoveredCandidate: Bool {
        guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel else { return false }
        return ((discoveryIndex ?? .shared).summary(for: StreamPlaybackRequest(event: event), at: now)?
            .compatibleCandidateCount ?? 0) > 0
    }

    var title: String {
        if status?.isFinished != true, status != .cancelled,
           let terminal = VerifiedFixtureTerminalPolicy.state(for: event, at: now) { return terminal.title }
        if let fixture = event.sportsFixture, status == nil, fixture.status.stopsPlayback {
            switch fixture.status {
            case .finished: return "Finished"
            case .cancelled: return "Cancelled"
            case .postponed: return "Postponed"
            default: break
            }
        }
        if let cricket = event.cricketFixture, status == nil, cricket.status.stopsPlayback {
            switch cricket.status {
            case .finished: return "Finished"
            case .cancelled: return "Cancelled"
            case .postponed: return "Postponed"
            default: break
            }
        }
        if let status, isStopped { return status.displayText }
        if hasUnconfirmedFixtureStart { return "Start unconfirmed" }
        if let start = upcomingStart { return Self.startLabel(start, now: now) }
        if SportsTVStation.canResolve(event, discoveryIndex: discoveryIndex) { return "Watch" }
        if CricketChannelPlaybackPolicy.canResolve(event, discoveryIndex: discoveryIndex) { return "Watch channel" }
        if !BroadcastRegistryWatchPolicy.matches(for: StreamPlaybackRequest(event: event),
            enabledProviderCodes: (discoveryIndex ?? .shared).enabledProviderCodes,
            discoveryIndex: discoveryIndex, at: now).isEmpty { return "Watch" }
        if hasFreshDiscoveredCandidate { return "Watch" }
        return event.kickoffDate == nil && !event.isBroadcastChannel ? "Time TBC" : "No stream listed"
    }

    /// A countdown only inside the last hour; otherwise the local clock time,
    /// with the weekday (or date) when it is not today.
    static func startLabel(_ start: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let interval = start.timeIntervalSince(now)
        if interval <= 3600 { return "Starts in \(countdown(interval))" }
        let time = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        if calendar.isDate(start, inSameDayAs: now) { return "Starts \(start.formatted(time))" }
        let day = interval < 6 * 86_400
            ? Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
            : Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        return "Starts \(start.formatted(day)) \(start.formatted(time))"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        if seconds >= 86_400 { return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        if seconds > 300 { return "\(Int(ceil(Double(seconds) / 60)))m" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func currentStatus(for event: AnalyticalDataEngine.EventReference, scores: LiveScoreService, now: Date = Date()) -> FootballMatch.MatchStatus? {
        if let terminal = VerifiedFixtureTerminalPolicy.state(for: event, at: now) {
            return terminal == .finished ? .finished : .cancelled
        }
        guard event.normalizedCategory == "football",
              let match = scores.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) else { return nil }
        return scores.currentStatus(for: match, at: now)
    }
}

struct MatchReminderRecord: Codable, Equatable, Identifiable {
    let snapshot: SavedMatchRecord
    let fireDate: Date
    var id: String { snapshot.id }
    var requestID: String { Self.requestID(eventID: id) }
    static let prefix = "fotty.match-reminder."

    static func requestID(eventID: String) -> String {
        prefix + Data(eventID.utf8).base64EncodedString()
    }

    @MainActor
    static func make(event: AnalyticalDataEngine.EventReference, now: Date) -> Self? {
        guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
              !MatchStartPolicy(event: event, now: now).hasUnconfirmedFixtureStart,
              let start = event.kickoffDate else { return nil }
        let fireDate = start.addingTimeInterval(-MatchStartPolicy.reminderLead)
        guard fireDate > now else { return nil }
        return .init(snapshot: SavedMatchRecord(event: event, savedAt: now), fireDate: fireDate)
    }

    @MainActor
    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Match starts soon"
        content.body = "\(snapshot.event.displayTitle) is scheduled to start in 5 minutes."
        content.sound = .default
        content.userInfo = ["matchID": id, "route": "match-reminder", "fireDate": fireDate.timeIntervalSince1970]
        // An absolute UTC calendar date survives time-zone and daylight-saving
        // changes. Include seconds; never round a five-minute alert to a minute.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: requestID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
}

@MainActor
protocol MatchReminderNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ identifiers: [String])
}

@MainActor
struct SystemMatchReminderNotifications: MatchReminderNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func pendingRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Device-local explicit opt-ins. Saves/follows never call enable. A serialized
/// notification queue plus per-match revisions prevents a delayed permission or
/// add response from resurrecting a reminder the user already cancelled.
@MainActor @Observable
final class MatchReminderStore {
    static let shared = MatchReminderStore()
    static let maximumReminders = 32 // leave room for FPL and other app alerts
    private(set) var records: [MatchReminderRecord]
    private(set) var busyIDs = Set<String>()
    private(set) var permission: UNAuthorizationStatus = .notDetermined
    private(set) var failedIDs = Set<String>()
    private let defaults: UserDefaults
    private let key: String
    private let client: any MatchReminderNotificationClient
    private let matchday: MyMatchdayStore
    private let clock: () -> Date
    private var revisions: [String: Int] = [:]
    private var pendingIntentEvents: [String: AnalyticalDataEngine.EventReference] = [:]
    private var tail: Task<Void, Never>?

    enum Result: Equatable {
        case scheduled, cancelled, denied, tooLate, limitReached, failed
        var message: String {
            switch self {
            case .scheduled: return "Reminder set for 5 minutes before. Saved to My Matchday."
            case .cancelled: return "Reminder off. The match stays saved."
            case .denied: return "Notifications are off. Enable them in Settings to receive reminders."
            case .tooLate: return "Already within five minutes, or the start time is unconfirmed. Follow the countdown here."
            case .limitReached: return "Your reminder list is full. Cancel another reminder first."
            case .failed: return "The reminder could not be scheduled. Please try again."
            }
        }
    }

    init(defaults: UserDefaults = .standard, key: String = "fotty.match-reminders.v1",
         client: (any MatchReminderNotificationClient)? = nil, matchday: MyMatchdayStore? = nil,
         clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.key = key
        self.client = client ?? SystemMatchReminderNotifications()
        self.matchday = matchday ?? .shared
        self.clock = clock
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([MatchReminderRecord].self, from: $0) } ?? []
        var seen = Set<String>()
        records = Array(decoded.filter { seen.insert($0.id).inserted }.prefix(Self.maximumReminders))
    }

    func contains(_ eventID: String) -> Bool { records.contains { $0.id == eventID } }
    /// The row's canonical identity may differ from the device-local opt-in
    /// that created its notification. Keep that opaque request ID stable.
    func record(for event: AnalyticalDataEngine.EventReference) -> MatchReminderRecord? {
        records.filter { SavedMatchContinuityPolicy.corresponds($0.snapshot, to: event) }
            .min { $0.snapshot.savedAt < $1.snapshot.savedAt }
    }

    func eventForIntent(_ event: AnalyticalDataEngine.EventReference) -> AnalyticalDataEngine.EventReference {
        let pending = pendingIntentEvents.values.map { SavedMatchRecord(event: $0, savedAt: .distantPast) }
            .filter { SavedMatchContinuityPolicy.corresponds($0, to: event) }
        let saved = record(for: event)?.snapshot ?? matchday.record(for: event)
            ?? (pending.count == 1 ? pending.first : nil)
        guard let saved, let current = SavedMatchContinuityPolicy.currentEvent(for: saved, in: [event]) else { return event }
        return current
    }
    /// Presentation receipts may reverse only their own accepted intent, not a
    /// later cancel/enable cycle from another row showing the same match.
    func intentRevision(for eventID: String) -> Int { revisions[eventID] ?? 0 }
    var notificationsAllowed: Bool { Self.allowed(permission) }
    private static func allowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    func enable(_ event: AnalyticalDataEngine.EventReference) async -> Result {
        let event = eventForIntent(event)
        let revision = (revisions[event.id] ?? 0) + 1
        revisions[event.id] = revision
        busyIDs.insert(event.id)
        pendingIntentEvents[event.id] = event
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await self.performEnable(event, revision: revision)
        }
        tail = Task { _ = await task.value }
        let result = await task.value
        if revisions[event.id] == revision {
            busyIDs.remove(event.id)
            pendingIntentEvents.removeValue(forKey: event.id)
        }
        return result
    }

    private func performEnable(_ event: AnalyticalDataEngine.EventReference, revision: Int) async -> Result {
        guard revisions[event.id] == revision else { return .cancelled }
        guard MatchReminderRecord.make(event: event, now: clock()) != nil else { return .tooLate }
        permission = await client.authorizationStatus()
        guard revisions[event.id] == revision else { return .cancelled }
        if permission == .notDetermined {
            do {
                guard try await client.requestAuthorization() else { permission = .denied; return .denied }
                permission = await client.authorizationStatus()
            } catch { return .failed }
        }
        guard revisions[event.id] == revision else { return .cancelled }
        guard notificationsAllowed else { return .denied }
        let pending = await client.pendingRequests()
        guard revisions[event.id] == revision else { return .cancelled }
        guard let record = MatchReminderRecord.make(event: event, now: clock()) else { return .tooLate }
        let activeCount = records.filter { $0.fireDate > clock() && $0.id != event.id }.count
        guard activeCount < Self.maximumReminders,
              pending.filter({ $0.identifier != record.requestID }).count < 60 else { return .limitReached }
        do { try await client.add(record.request) } catch { return .failed }
        guard revisions[event.id] == revision else { client.remove([record.requestID]); return .cancelled }
        if let _ = matchday.save(event).errorMessage {
            // A reminder promises that the match is also in My Matchday. Never
            // leave a scheduled notification behind when that durable save fails.
            client.remove([record.requestID])
            return .failed
        }
        records.removeAll { $0.id == event.id || $0.fireDate <= clock() }
        records.append(record)
        failedIDs.remove(event.id)
        persist()
        return .scheduled
    }

    func cancel(_ eventID: String) {
        revisions[eventID, default: 0] += 1
        records.removeAll { $0.id == eventID }
        busyIDs.remove(eventID)
        pendingIntentEvents.removeValue(forKey: eventID)
        failedIDs.remove(eventID)
        client.remove([MatchReminderRecord.requestID(eventID: eventID)])
        persist()
    }

    /// A legacy install can contain opt-ins under both the provider and the
    /// canonical ID. Turning this logical reminder off revokes every proven
    /// corresponding request; passive catalog refresh never deletes them.
    func cancel(for event: AnalyticalDataEngine.EventReference) {
        var ids = Set(records.filter { SavedMatchContinuityPolicy.corresponds($0.snapshot, to: event) }.map(\.id))
        ids.formUnion(pendingIntentEvents.values.filter {
            SavedMatchContinuityPolicy.corresponds(SavedMatchRecord(event: $0, savedAt: .distantPast), to: event)
        }.map(\.id))
        ids.insert(eventForIntent(event).id)
        ids.forEach { cancel($0) }
    }

    /// A private backup deliberately excludes notification authorization and
    /// scheduled reminders. Restoring a different local setup therefore turns
    /// off existing match reminders instead of attaching them to restored data.
    func cancelAllForRestore() {
        let identifiers = records.map(\.requestID)
        // A cancelled row may still display Undo. Restoring local data revokes
        // that old receipt too, even though it no longer has an active record.
        for id in Set(revisions.keys).union(records.map(\.id)).union(busyIDs) { revisions[id, default: 0] += 1 }
        records.removeAll()
        busyIDs.removeAll()
        pendingIntentEvents.removeAll()
        failedIDs.removeAll()
        client.remove(identifiers)
        persist()
    }

    /// Only unique, identity-consistent exact IDs may update snapshots. Missing
    /// or conflicting rows are not cancellation evidence. No permission prompt.
    func reconcile(events: [AnalyticalDataEngine.EventReference],
                   shouldContinue: @escaping @MainActor () -> Bool = { true },
                   status: @escaping @MainActor (AnalyticalDataEngine.EventReference) -> FootballMatch.MatchStatus? = { _ in nil }) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled, shouldContinue() else { return }
            // A queued enable may still be awaiting permission or system add.
            // Derive evidence from its completed record, not the empty list
            // that existed when this reconciliation was first enqueued.
            var fresh: [String: AnalyticalDataEngine.EventReference] = [:]
            var statuses: [String: FootballMatch.MatchStatus] = [:]
            for record in self.records {
                if let current = SavedMatchContinuityPolicy.currentEvent(for: record.snapshot, in: events) {
                    fresh[record.id] = current
                }
                let event = fresh[record.id] ?? record.snapshot.event
                if let value = status(event) { statuses[record.id] = value }
            }
            await self.performReconcile(fresh: fresh, statuses: statuses, shouldContinue: shouldContinue)
        }
        tail = task
        await task.value
    }

    private func performReconcile(fresh: [String: AnalyticalDataEngine.EventReference], statuses: [String: FootballMatch.MatchStatus],
                                  shouldContinue: @MainActor () -> Bool) async {
        guard shouldContinue(), !Task.isCancelled else { return }
        let authorization = await client.authorizationStatus()
        guard shouldContinue(), !Task.isCancelled else { return }
        let pending = await client.pendingRequests()
        guard shouldContinue(), !Task.isCancelled else { return }
        permission = authorization
        let known = Set(records.map(\.requestID))
        client.remove(pending.filter { $0.identifier.hasPrefix(MatchReminderRecord.prefix) && !known.contains($0.identifier) }.map(\.identifier))
        var pendingCount = pending.filter { !$0.identifier.hasPrefix(MatchReminderRecord.prefix) }.count
        for original in records {
            guard shouldContinue(), !Task.isCancelled else { return }
            guard contains(original.id) else { continue }
            let revision = revisions[original.id] ?? 0
            let event = fresh[original.id] ?? original.snapshot.event
            let state = MatchStartPolicy(event: event, now: clock(), status: statuses[original.id])
            if fresh[original.id] != nil, VerifiedFixtureTerminalPolicy.state(for: event, at: state.now) != nil,
               matchday.contains(eventID: original.id) {
                // The global saved pass may have run before a pending enable
                // created its bookmark. Preserve accepted terminal facts there
                // before revoking the reminder; do not remove the bookmark.
                matchday.reconcile(events: [event], at: clock())
            }
            if state.isStopped || state.hasUnconfirmedFixtureStart || state.status?.isLive == true
                || event.sportsFixture?.isLive(at: state.now) == true || event.cricketFixture?.isLive(at: state.now) == true
                || event.isBroadcastChannel || event.kickoffDate == nil {
                cancel(original.id)
                continue
            }
            guard let start = event.kickoffDate else { continue }
            if start < clock().addingTimeInterval(-36 * 3600) { cancel(original.id); continue }
            let changedDate = original.snapshot.event.kickoffDate != event.kickoffDate
            let updated = MatchReminderRecord(snapshot: SavedMatchRecord(event: event, savedAt: original.snapshot.savedAt,
                previousDate: changedDate ? original.snapshot.date : original.snapshot.previousDate),
                fireDate: start.addingTimeInterval(-MatchStartPolicy.reminderLead))
            let scheduleChanged = updated.fireDate != original.fireDate
            if updated != original {
                records.removeAll { $0.id == original.id }
                records.append(updated)
                if matchday.contains(eventID: original.id) { matchday.reconcile(events: [event], at: clock()) }
                if scheduleChanged { client.remove([original.requestID]) }
            }
            guard notificationsAllowed, updated.fireDate > clock() else {
                // Never enqueue overdue notifications on foreground/relaunch.
                // A delivered reminder remains tappable unless actually revoked.
                if !notificationsAllowed || scheduleChanged { client.remove([updated.requestID]) }
                continue
            }
            pendingCount += 1
            let existing = pending.first { $0.identifier == updated.requestID }
            let existingFire = existing?.content.userInfo["fireDate"] as? Double
            if !scheduleChanged, existingFire == updated.fireDate.timeIntervalSince1970 {
                failedIDs.remove(original.id)
                continue
            }
            guard pendingCount <= 60 else { failedIDs.insert(original.id); continue }
            do {
                guard shouldContinue(), !Task.isCancelled else { return }
                try await client.add(updated.request)
                guard shouldContinue(), !Task.isCancelled else {
                    await restoreInterruptedReconcile(original, updated: updated, revision: revision,
                        pending: pending.first { $0.identifier == original.requestID })
                    return
                }
                if (revisions[original.id] ?? 0) != revision { client.remove([updated.requestID]) }
                else { failedIDs.remove(original.id) }
            } catch {
                guard shouldContinue(), !Task.isCancelled else {
                    await restoreInterruptedReconcile(original, updated: updated, revision: revision,
                        pending: pending.first { $0.identifier == original.requestID })
                    return
                }
                if (revisions[original.id] ?? 0) == revision { failedIDs.insert(original.id) }
            }
        }
        persist()
    }

    /// The OS notification add has no cancellation transaction. If a background
    /// lease expires during that submitted operation, remove the late request.
    /// Accepted schedule facts remain accepted; an obsolete prior fire time
    /// must never be restored. The current revision waits for a safe retry.
    private func restoreInterruptedReconcile(_ original: MatchReminderRecord, updated: MatchReminderRecord, revision: Int,
                                             pending: UNNotificationRequest?) async {
        client.remove([original.requestID])
        guard (revisions[original.id] ?? 0) == revision, contains(original.id) else { return }
        failedIDs.insert(original.id)
        // A missing-request repair with unchanged verified timing may restore
        // only its own already-proven future request. A reschedule cannot.
        if updated.fireDate == original.fireDate, let pending,
           pending.content.userInfo["fireDate"] as? Double == updated.fireDate.timeIntervalSince1970,
           updated.fireDate > clock(), notificationsAllowed {
            try? await client.add(pending)
            if (revisions[original.id] ?? 0) != revision { client.remove([original.requestID]) }
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Short-lived row feedback, not a provider blacklist. An explicit retry always
/// gets a real resolver attempt; nothing polls streams in the background.
@MainActor @Observable
final class MatchPlaybackFeedback {
    static let shared = MatchPlaybackFeedback()
    private(set) var notReadyIDs = Set<String>()
    func attempting(_ id: String) { notReadyIDs.remove(id) }
    func notReady(_ id: String) {
        if notReadyIDs.count >= 100 { notReadyIDs.removeAll() }
        notReadyIDs.insert(id)
    }
}
