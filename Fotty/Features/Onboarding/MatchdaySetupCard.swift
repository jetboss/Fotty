import SwiftUI
import SwiftData

enum MatchdaySetupPolicy {
    static func shouldShow(dismissed: Bool, followedCount: Int, savedCount: Int) -> Bool {
        !dismissed && (followedCount == 0 || savedCount == 0)
    }
}

/// Optional, in-context setup. Watching never depends on completing it.
struct MatchdaySetupCard: View {
    @AppStorage(SportsInterestPreferences.storageKey) private var followedSportsRaw = SportsInterestPreferences.emptyValue
    @AppStorage("fotty.setup.dismissed.v1", store: Self.setupPreferences) private var dismissed = false
    @Query private var followedTeams: [FollowedTeamItem]
    @Query private var followedLeagues: [FollowedLeagueItem]
    @State private var saved = MyMatchdayStore.shared
    @State private var showsInterests = false

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
            dismissed: dismissed, followedCount: followedTeams.count + followedLeagues.count + SportsInterestPreferences.canonicalIDs(from: followedSportsRaw).count,
            savedCount: saved.savedMatches.count
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make Fotty yours").font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Sports, competitions and teams")
                            .font(.caption).foregroundStyle(FottyTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FottyPressButtonStyle())
                    .accessibilityLabel("Dismiss setup tips")
                    .accessibilityIdentifier("setup-dismiss")
                }
                if followedTeams.isEmpty && followedLeagues.isEmpty && SportsInterestPreferences.canonicalIDs(from: followedSportsRaw).isEmpty {
                    Button { showsInterests = true } label: {
                        Label("Choose your interests", systemImage: "slider.horizontal.3")
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FottyPressButtonStyle())
                    .accessibilityIdentifier("setup-follow")
                }
                if saved.savedMatches.isEmpty {
                    Label("Use a match’s menu to Save to My Matchday.", systemImage: "bookmark")
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
      .fullScreenCover(isPresented: $showsInterests) { NavigationStack { SettingsManageLeaguesView() } }
    }
}
