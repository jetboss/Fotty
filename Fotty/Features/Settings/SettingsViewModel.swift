import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    // These are consumed by LiveScoreService when it schedules match events.
    @AppStorage("settings.notif.kickoff") var notifKickoff = true
    @AppStorage("settings.notif.goals") var notifGoals = true
    @AppStorage("settings.notif.fulltime") var notifFulltime = true
    @AppStorage("settings.spoiler.protection") var notificationSpoilerProtection = false
}
