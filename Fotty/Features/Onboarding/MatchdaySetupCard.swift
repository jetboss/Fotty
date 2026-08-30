import SwiftUI
import SwiftData

enum MatchdaySetupPolicy {
    static func shouldShow(dismissed: Bool, followedCount: Int, savedCount: Int) -> Bool {
        !dismissed && (followedCount == 0 || savedCount == 0)
    }
}

/// Optional, in-context setup. Watching never depends on completing it.
struct MatchdaySetupCard: View {
    @AppStorage("fotty.setup.dismissed.v1", store: Self.setupPreferences) private var dismissed = false
    @Query private var followedTeams: [FollowedTeamItem]
    @State private var saved = MyMatchdayStore.shared
    @State private var showsTeams = false

    private static let setupPreferences: UserDefaults = {
        #if DEBUG
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_SETUP_UI_TESTING"] == "1",
           let preferences = UserDefaults(suiteName: "com.jelani.Fotty.SetupUITests") {
            // Unlike a launch-argument override, this fixture remains writable
            // when the tester dismisses the card. Never alter the user's tips.
            preferences.removePersistentDomain(forName: "com.jelani.Fotty.SetupUITests")
            return preferences
        }
        #endif
        return .standard
    }()

    var body: some View {
      Group {
        if MatchdaySetupPolicy.shouldShow(
            dismissed: dismissed, followedCount: followedTeams.count,
            savedCount: saved.savedMatches.count
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make Fotty yours").font(.headline)
                        Text("Optional setup · saved on this device")
                            .font(.caption).foregroundStyle(FottyTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss setup tips")
                    .accessibilityIdentifier("setup-dismiss")
                }
                if followedTeams.isEmpty {
                    Button { showsTeams = true } label: {
                        Label("Follow a team", systemImage: "star")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("setup-follow")
                }
                if saved.savedMatches.isEmpty {
                    Label("Long-press a match and choose Save to My Matchday.", systemImage: "bookmark")
                        .font(.callout)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .bentoSurface()
            .tint(FottyTheme.accentText)
        }
      }
      .fullScreenCover(isPresented: $showsTeams) { TeamOnboardingView() }
    }
}
