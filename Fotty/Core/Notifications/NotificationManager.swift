import Foundation
import UserNotifications
import Observation
import UIKit
import MetricKit

enum FottyDeepLinkDestination: Equatable {
    case fpl
    case match(String)
    case matchday(String)
    case survivingLivePlayer(String)

    static func parse(_ url: URL) -> FottyDeepLinkDestination? {
        guard url.scheme?.lowercased() == "fotty" else { return nil }
        switch url.host?.lowercased() {
        case "fpl":
            return .fpl
        case "match":
            guard let id = routeID(in: url) else { return nil }
            return .match(id)
        case "matchday":
            guard let id = routeID(in: url) else { return nil }
            return .matchday(id)
        case "live":
            guard let id = routeID(in: url) else { return nil }
            return .survivingLivePlayer(id)
        default:
            return nil
        }
    }

    private static func routeID(in url: URL) -> String? {
        guard let component = url.pathComponents.dropFirst().first else { return nil }
        let raw = (component.removingPercentEncoding ?? component)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return raw
    }
}

@MainActor
@Observable
final class MatchNavigationStore {
    static let shared = MatchNavigationStore()

    var pendingMatchID: String?
    var pendingReminderID: String?
    var pendingFPL = false
    private(set) var activeLivePlayerMatchID: String?

    private init() {}

    func open(matchID: String) {
        let trimmed = matchID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingFPL = false
        pendingMatchID = trimmed
    }

    func openReminder(eventID: String) {
        let id = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        pendingFPL = false
        pendingMatchID = nil
        pendingReminderID = id
    }

    func openFPL() {
        pendingMatchID = nil
        pendingReminderID = nil
        pendingFPL = true
    }

    func open(url: URL) {
        guard let destination = FottyDeepLinkDestination.parse(url) else { return }
        switch destination {
        case .match(let matchID):
            open(matchID: matchID)
        case .matchday(let eventID):
            openReminder(eventID: eventID)
        case .survivingLivePlayer(let matchID):
            // ActivityKit foregrounds a surviving player on its own. After a
            // process termination there is no player to reveal, so the same
            // return link must fall back to useful match context instead of
            // merely opening Fotty's last tab.
            guard activeLivePlayerMatchID != matchID else { return }
            open(matchID: matchID)
        case .fpl:
            openFPL()
        }
    }

    func livePlayerDidAppear(matchID: String) {
        let trimmed = matchID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeLivePlayerMatchID = trimmed
    }

    func livePlayerDidDisappear(matchID: String) {
        guard activeLivePlayerMatchID == matchID else { return }
        activeLivePlayerMatchID = nil
    }
}

enum MatchAlertPreferences {
    private static let enabledTeamKeys = "fotty.notifications.enabledTeamKeys"

    static func synchronize(from followedTeams: [FollowedTeamItem]) {
        let keys = followedTeams.compactMap { team -> String? in
            let category = team.sportCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard category == "football" || category == "soccer",
                  team.alertsEnabled ?? true else { return nil }
            return TeamFollowKey.make(name: team.teamName, category: "football")
        }
        UserDefaults.standard.set(Array(Set(keys)).sorted(), forKey: enabledTeamKeys)
    }

    static func allows(homeTeam: String, awayTeam: String) -> Bool {
        let enabled = Set(UserDefaults.standard.stringArray(forKey: enabledTeamKeys) ?? [])
        guard !enabled.isEmpty else { return false }
        return enabled.contains(TeamFollowKey.make(name: homeTeam, category: "football"))
            || enabled.contains(TeamFollowKey.make(name: awayTeam, category: "football"))
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "settings.notif.kickoff": true,
            "settings.notif.goals": true,
            "settings.notif.fulltime": true,
            "settings.spoiler.protection": false
        ])
    }
}

struct MatchAlertContent: Equatable {
    enum Kind: Equatable {
        case kickoff
        case goal(home: Int, away: Int)
        case fullTime(home: Int, away: Int)
    }

    let title: String
    let body: String

    static func make(
        kind: Kind,
        homeTeam: String,
        awayTeam: String,
        competition: String,
        spoilerProtected: Bool
    ) -> MatchAlertContent {
        switch kind {
        case .kickoff:
            return MatchAlertContent(
                title: "Match started",
                body: "\(homeTeam) vs \(awayTeam) is now live."
            )
        case .goal(let home, let away):
            if spoilerProtected {
                return MatchAlertContent(
                    title: "Match update",
                    body: "There is a new event in \(homeTeam) vs \(awayTeam)."
                )
            }
            return MatchAlertContent(
                title: "GOAL · \(homeTeam) \(home)–\(away) \(awayTeam)",
                body: "Goal scored in \(competition)."
            )
        case .fullTime(let home, let away):
            if spoilerProtected {
                return MatchAlertContent(
                    title: "Match finished",
                    body: "\(homeTeam) vs \(awayTeam) has finished. Open Fotty for the result."
                )
            }
            return MatchAlertContent(
                title: "Full time",
                body: "\(homeTeam) \(home)–\(away) \(awayTeam)"
            )
        }
    }
}

final class FottyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MatchAlertPreferences.registerDefaults()
        UNUserNotificationCenter.current().delegate = self
        FottyMetricSubscriber.shared.start()
        SportsReminderBackgroundRefresh.shared.registerAtLaunch()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let userInfo = response.notification.request.content.userInfo
        let route = userInfo["route"] as? String
        if route == "fpl-deadline" {
            await MainActor.run { MatchNavigationStore.shared.openFPL() }
            return
        }
        guard let matchID = userInfo["matchID"] as? String else { return }
        let isReminder = route == "match-reminder"
        await MainActor.run {
            if isReminder { MatchNavigationStore.shared.openReminder(eventID: matchID) }
            else { MatchNavigationStore.shared.open(matchID: matchID) }
        }
    }
}

/// Receives Apple's field performance summaries without uploading or retaining
/// raw diagnostics. Two bounded, dated summaries can be shared only through
/// the existing explicit diagnostic export/feedback consent.
final class FottyMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = FottyMetricSubscriber()

    private let lock = NSLock()
    private var isStarted = false

    private override init() {}

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted, !AppRuntime.isAutomatedTesting else { return }
        isStarted = true
        _ = FottyPerformanceStore.shared.summary()
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let ratio = payload.animationMetrics?.scrollHitchTimeRatio.value else { continue }
            FottyPerformanceStore.shared.record(
                windowStart: payload.timeStampBegin, windowEnd: payload.timeStampEnd,
                reportedBuild: payload.metaData?.applicationBuildVersion,
                includesMultipleVersions: payload.includesMultipleApplicationVersions,
                scrollHitchRatio: ratio
            )
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let hangs = payload.hangDiagnostics, !hangs.isEmpty else { continue }
            let durations = hangs.map { $0.hangDuration.converted(to: .seconds).value }
            guard durations.allSatisfy({ $0.isFinite && $0 >= 0 }), let longest = durations.max() else { continue }
            let builds = Set(hangs.map { $0.metaData.applicationBuildVersion })
            FottyPerformanceStore.shared.record(
                windowStart: payload.timeStampBegin, windowEnd: payload.timeStampEnd,
                reportedBuild: builds.count == 1 ? builds.first : nil,
                includesMultipleVersions: builds.count > 1,
                hangCount: hangs.count, longestHangSeconds: longest
            )
        }
    }
}

@MainActor
@Observable
class NotificationManager {
    static let shared = NotificationManager()
    
    var permissionStatus: UNAuthorizationStatus = .notDetermined
    
    private init() {
        checkPermissionStatus()
    }
    
    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.permissionStatus = settings.authorizationStatus
            }
        }
    }
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            checkPermissionStatus()
            return granted
        } catch {
            print("[NotificationManager] Request failed: \(error)")
            return false
        }
    }
    
    /// Trigger an alert for a match event
    func scheduleMatchAlert(
        title: String,
        body: String,
        matchID: String,
        category: String = "MATCH_EVENT"
    ) {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["matchID": matchID]
        content.categoryIdentifier = category
        
        // Trigger immediately (Local Notification as Alert)
        let request = UNNotificationRequest(
            identifier: "fotty.alert.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to add notification: \(error)")
            }
        }
    }
}
