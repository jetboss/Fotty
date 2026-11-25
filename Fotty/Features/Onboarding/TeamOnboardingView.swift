import SwiftUI
import SwiftData

enum TeamOnboardingCatalog {
    struct Option: Identifiable {
        let name: String
        let sport: String
        let competitionID: String
        var id: String { name }
    }

    static let options: [Option] = [
        .init(name: "English Premier League", sport: "football", competitionID: "premier-league"),
        .init(name: "Spanish La Liga", sport: "football", competitionID: "la-liga"),
        .init(name: "Italian Serie A", sport: "football", competitionID: "serie-a"),
        .init(name: "German Bundesliga", sport: "football", competitionID: "bundesliga"),
        .init(name: "French Ligue 1", sport: "football", competitionID: "ligue-1"),
        .init(name: "MLS", sport: "football", competitionID: "mls"),
        .init(name: "Caribbean Premier League", sport: "cricket", competitionID: "cpl"),
        .init(name: "NBA", sport: "basketball", competitionID: "nba"),
        .init(name: "WNBA", sport: "basketball", competitionID: "wnba"),
        .init(name: "MLB", sport: "baseball", competitionID: "mlb"),
        .init(name: "NHL", sport: "hockey", competitionID: "nhl")
    ]

    static func validatedInitialLeague(_ proposed: String?) -> String {
        options.first { $0.name == proposed }?.name ?? "English Premier League"
    }
}

struct TeamOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var followedTeams: [FollowedTeamItem]
    @StateObject private var brandService = TeamBrandService.shared
    @State private var searchText = ""
    @State private var selectedLeague = "English Premier League"
    @State private var suggestedTeams: [OnboardingTeamSuggestion] = []
    @State private var isLoading = false
    @State private var retryID = UUID()
    @State private var loadID = UUID()
    @State private var saveError: String?

    private let leagues = TeamOnboardingCatalog.options.map(\.name)

    init(initialLeague: String? = nil) {
        _selectedLeague = State(initialValue: TeamOnboardingCatalog.validatedInitialLeague(initialLeague))
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchKey: String { "\(selectedLeague)|\(query)|\(retryID)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Matchday, your teams")
                        .font(.title2.bold())
                        .foregroundStyle(FottyTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Favorite teams can shape your Home and add their fixtures to My Matchday. You can change this anytime in Settings.")
                        .font(.body).foregroundStyle(FottyTheme.textSecondary)
                    if LocalDataStore.shared.isUsingVolatileFallback {
                        LocalPersistenceWarning()
                    }
                    TextField("Search teams across sports", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .accessibilityIdentifier("follow-team-search")

                    if query.isEmpty {
                        Picker("League", selection: $selectedLeague) {
                            ForEach(leagues, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }

                    if isLoading {
                        ProgressView("Loading teams…").frame(maxWidth: .infinity)
                    } else if suggestedTeams.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(query.isEmpty ? "Teams aren't available right now" : "No matching teams")
                                .font(.headline)
                            Text(query.isEmpty
                                 ? "Check your connection and try again. You can still browse matches without following a team."
                                 : "Try another spelling or clear the search to browse a league. A connection problem can also prevent results.")
                            Button("Try again") { retryID = UUID() }.frame(minHeight: 44)
                            if !query.isEmpty {
                                Button("Clear search") { searchText = "" }.frame(minHeight: 44)
                            }
                        }
                        .font(.callout)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 100))],
                            alignment: .leading, spacing: 20
                        ) {
                            ForEach(suggestedTeams) { team in
                                TeamGridItem(team: team, isFollowed: isTeamFollowed(team)) {
                                    toggleFollow(team)
                                }
                            }
                        }
                    }

                    Text("\(followedTeams.count) \(followedTeams.count == 1 ? "team" : "teams") followed")
                        .font(.callout)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .padding(20)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FottyTheme.background)
            .navigationTitle("Follow teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: searchKey) { await loadTeams() }
            .alert("Couldn't save your teams", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        .tint(FottyTheme.accentText)
    }

    @MainActor
    private func loadTeams() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        loadID = request
        let requestedQuery = query
        let requestedLeague = selectedLeague
        suggestedTeams = []
        isLoading = true
        defer { if loadID == request { isLoading = false } }
        guard !AppRuntime.isAutomatedTesting else { return }
        if !requestedQuery.isEmpty {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
        let teams = requestedQuery.isEmpty
            ? await brandService.fetchLeagueCatalog(leagueName: requestedLeague)
            : await brandService.searchCatalog(query: requestedQuery)
        guard !Task.isCancelled, loadID == request else { return }
        suggestedTeams = teams.map { OnboardingTeamSuggestion(name: $0.displayName, sportCategory: $0.sportCategory, badgeURL: $0.badgeURL) }
    }

    private func isTeamFollowed(_ suggestion: OnboardingTeamSuggestion) -> Bool {
        SportsPersonalizationPolicy.followedTeamKeys(followedTeams).contains(suggestion.id)
    }

    private func toggleFollow(_ suggestion: OnboardingTeamSuggestion) {
        guard !LocalDataStore.shared.isUsingVolatileFallback else {
            saveError = "Favorite teams cannot be saved while Fotty is using temporary storage. Restart Fotty and try again."
            return
        }
        do {
            try SportsPersonalizationStore.setFollow(suggestion.identity, enabled: !isTeamFollowed(suggestion), in: modelContext)
            HapticManager.impact(.light)
        } catch {
            saveError = "The change wasn't saved. Your previous choices are kept; please try again."
        }
    }
}

struct TeamGridItem: View {
    let team: OnboardingTeamSuggestion
    let isFollowed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                TeamBadgeWindow(
                    teamName: team.name,
                    badgeURL: team.badgeURL,
                    size: 52,
                    triggerSearch: true
                )
                Text(team.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(team.sportCategory.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                Label(isFollowed ? "Following" : "Follow", systemImage: isFollowed ? "checkmark.circle.fill" : "plus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFollowed ? FottyTheme.accentText : FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isFollowed ? FottyTheme.accentText : FottyTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(10)
            .background(FottyTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isFollowed ? FottyTheme.accentText : FottyTheme.border, lineWidth: isFollowed ? 1.5 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(FottyPressButtonStyle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.name), \(team.sportCategory.replacingOccurrences(of: "-", with: " "))")
        .accessibilityValue(isFollowed ? "Following" : "Not followed")
        .accessibilityAddTraits(isFollowed ? .isSelected : [])
        .accessibilityHint(isFollowed ? "Unfollow this team" : "Follow this team")
    }
}

struct OnboardingTeamSuggestion: Identifiable {
    var id: String { TeamFollowKey.make(name: name, category: sportCategory) }
    let name: String
    let sportCategory: String
    let badgeURL: URL?
    var identity: SportsTeamIdentity { .init(displayName: name, sportCategory: sportCategory, badgeURL: badgeURL) }
}
