import Foundation
import UserNotifications

public struct FPLDeadlineReminder: Identifiable, Sendable, Equatable {
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
}

public enum FPLAlertScheduler {
    public static func reminderPlan(
        for gameweek: FPLGameweek,
        now: Date = Date()
    ) -> [FPLDeadlineReminder] {
        guard let deadline = gameweek.deadlineDate, deadline > now else { return [] }
        let offsets: [(TimeInterval, String)] = [
            (24 * 60 * 60, "24 hours"),
            (2 * 60 * 60, "2 hours")
        ]
        return offsets.compactMap { offset, label in
            let fireDate = deadline.addingTimeInterval(-offset)
            guard fireDate > now else { return nil }
            return FPLDeadlineReminder(
                id: "fotty.fpl.deadline.\(gameweek.id).\(Int(offset))",
                fireDate: fireDate,
                title: "\(gameweek.name) deadline in \(label)",
                body: "Review availability, transfers, captain and saved Fotty drafts before confirming in official FPL."
            )
        }
    }

    public static func scheduleDeadlineReminders(
        for gameweek: FPLGameweek,
        center: UNUserNotificationCenter = .current()
    ) async throws -> Int {
        let allowed = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        guard allowed else { return 0 }
        let plan = reminderPlan(for: gameweek)
        center.removePendingNotificationRequests(
            withIdentifiers: [
                "fotty.fpl.deadline.\(gameweek.id).86400",
                "fotty.fpl.deadline.\(gameweek.id).7200"
            ]
        )
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(
                UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            )
        }
        return plan.count
    }
}

@MainActor
public enum FPLCoachProfileStore {
    public static func load(managerID: Int, season: String = FPLSeasonIdentifier.currentLabel()) -> FPLCoachProfile {
        guard let data = UserDefaults.standard.data(forKey: key(managerID: managerID, season: season)),
              let value = try? JSONDecoder().decode(FPLCoachProfile.self, from: data) else {
            return .default
        }
        return value
    }

    public static func save(
        _ profile: FPLCoachProfile,
        managerID: Int,
        season: String = FPLSeasonIdentifier.currentLabel()
    ) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key(managerID: managerID, season: season))
    }

    private static func key(managerID: Int, season: String) -> String {
        "fotty.fpl.\(season).manager.\(managerID).coachProfile"
    }
}
