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

    var isStopped: Bool {
        status.map { !$0.isUpcoming && !$0.isLive } ?? false
    }

    var upcomingStart: Date? {
        guard !event.isBroadcastChannel, !isStopped, status?.isLive != true,
              let date = event.kickoffDate, date > now else { return nil }
        return date
    }

    /// Timing only: Match Center may need to rematch an official fixture to a
    /// catalog descriptor, so source existence is checked separately by its UI.
    var timingAllowsPlayback: Bool {
        guard !isStopped else { return false }
        if event.isBroadcastChannel || status?.isLive == true { return true }
        guard let start = event.kickoffDate else { return true }
        return start.timeIntervalSince(now) <= Self.playbackLead
    }

    var canAttemptPlayback: Bool {
        timingAllowsPlayback && StreamPluginProviderMatching.hasActiveCatalogSource(event)
    }

    var title: String {
        if let status, isStopped { return status.displayText }
        if let start = upcomingStart { return "Starts in \(Self.countdown(start.timeIntervalSince(now)))" }
        guard StreamPluginProviderMatching.hasActiveCatalogSource(event) else {
            return event.kickoffDate == nil && !event.isBroadcastChannel ? "Time TBC" : "No stream listed"
        }
        if event.isBroadcastChannel { return "Watch channel" }
        return event.kickoffDate == nil ? "Check streams" : "Watch"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        if seconds >= 86_400 { return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        if seconds > 300 { return "\(Int(ceil(Double(seconds) / 60)))m" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func currentStatus(for event: AnalyticalDataEngine.EventReference, scores: LiveScoreService, now: Date = Date()) -> FootballMatch.MatchStatus? {
        guard event.normalizedCategory == "football",
              let match = scores.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) else { return nil }
        return HomeSportsDiscovery.recentStatus(match.status, refreshedAt: scores.lastRefresh,
            liveFeedAvailable: scores.feedMode != .unavailable && scores.feedMode != .inactive, now: now)
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
        guard !event.isBroadcastChannel, let start = event.kickoffDate else { return nil }
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
    var notificationsAllowed: Bool { Self.allowed(permission) }
    private static func allowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    func enable(_ event: AnalyticalDataEngine.EventReference) async -> Result {
        let revision = (revisions[event.id] ?? 0) + 1
        revisions[event.id] = revision
        busyIDs.insert(event.id)
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await self.performEnable(event, revision: revision)
        }
        tail = Task { _ = await task.value }
        let result = await task.value
        if revisions[event.id] == revision { busyIDs.remove(event.id) }
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
        records.removeAll { $0.id == event.id || $0.fireDate <= clock() }
        records.append(record)
        failedIDs.remove(event.id)
        matchday.save(event)
        persist()
        return .scheduled
    }

    func cancel(_ eventID: String) {
        revisions[eventID, default: 0] += 1
        records.removeAll { $0.id == eventID }
        busyIDs.remove(eventID)
        failedIDs.remove(eventID)
        client.remove([MatchReminderRecord.requestID(eventID: eventID)])
        persist()
    }

    /// Only exact catalog IDs may update snapshots. Missing rows in a failed or
    /// partial feed are NOT cancellation evidence. No fetch or permission prompt.
    func reconcile(events: [AnalyticalDataEngine.EventReference],
                   status: (AnalyticalDataEngine.EventReference) -> FootballMatch.MatchStatus? = { _ in nil }) async {
        var fresh: [String: AnalyticalDataEngine.EventReference] = [:]
        for event in events { fresh[event.id] = event }
        var statuses: [String: FootballMatch.MatchStatus] = [:]
        for record in records {
            let event = fresh[record.id] ?? record.snapshot.event
            if let value = status(event) { statuses[record.id] = value }
        }
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await self.performReconcile(fresh: fresh, statuses: statuses)
        }
        tail = task
        await task.value
    }

    private func performReconcile(fresh: [String: AnalyticalDataEngine.EventReference], statuses: [String: FootballMatch.MatchStatus]) async {
        permission = await client.authorizationStatus()
        let pending = await client.pendingRequests()
        let known = Set(records.map(\.requestID))
        client.remove(pending.filter { $0.identifier.hasPrefix(MatchReminderRecord.prefix) && !known.contains($0.identifier) }.map(\.identifier))
        var pendingCount = pending.filter { !$0.identifier.hasPrefix(MatchReminderRecord.prefix) }.count
        for original in records {
            guard contains(original.id) else { continue }
            let revision = revisions[original.id] ?? 0
            let event = fresh[original.id] ?? original.snapshot.event
            let state = MatchStartPolicy(event: event, now: clock(), status: statuses[original.id])
            if state.isStopped || state.status?.isLive == true || event.isBroadcastChannel || event.kickoffDate == nil {
                cancel(original.id)
                continue
            }
            guard let start = event.kickoffDate else { continue }
            if start < clock().addingTimeInterval(-36 * 3600) { cancel(original.id); continue }
            let updated = MatchReminderRecord(snapshot: SavedMatchRecord(event: event, savedAt: original.snapshot.savedAt),
                fireDate: start.addingTimeInterval(-MatchStartPolicy.reminderLead))
            if updated != original {
                records.removeAll { $0.id == original.id }
                records.append(updated)
                if matchday.contains(eventID: original.id) { matchday.save(event) }
                client.remove([original.requestID])
            }
            guard notificationsAllowed, updated.fireDate > clock() else {
                // Never enqueue overdue notifications on foreground/relaunch.
                // A delivered reminder remains tappable unless actually revoked.
                if !notificationsAllowed || updated != original { client.remove([updated.requestID]) }
                continue
            }
            pendingCount += 1
            let existing = pending.first { $0.identifier == updated.requestID }
            let existingFire = existing?.content.userInfo["fireDate"] as? Double
            if updated == original, existingFire == updated.fireDate.timeIntervalSince1970 {
                failedIDs.remove(original.id)
                continue
            }
            guard pendingCount <= 60 else { failedIDs.insert(original.id); continue }
            do {
                try await client.add(updated.request)
                if (revisions[original.id] ?? 0) != revision { client.remove([updated.requestID]) }
                else { failedIDs.remove(original.id) }
            } catch {
                if (revisions[original.id] ?? 0) == revision { failedIDs.insert(original.id) }
            }
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
