import SwiftUI
import SwiftData

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

    private let leagues = [
        "English Premier League", "Spanish La Liga", "Italian Serie A",
        "German Bundesliga", "French Ligue 1", "MLS"
    ]
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchKey: String { "\(selectedLeague)|\(query)|\(retryID)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Matchday, your teams").font(.title2.bold())
                    Text("Follow teams to add their fixtures to My Matchday. You can change this anytime in Settings.")
                        .font(.body).foregroundStyle(FottyTheme.textSecondary)
                    TextField("Search for a club", text: $searchText)
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
                                TeamGridItem(team: team, isFollowed: isTeamFollowed(team.name)) {
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
                    Button("Done") {
                        if saveChanges() { dismiss() }
                    }
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
        suggestedTeams = teams.map { OnboardingTeamSuggestion(name: $0.displayName, badgeURL: $0.badgeURL) }
    }

    private func isTeamFollowed(_ name: String) -> Bool {
        followedTeams.contains { $0.teamName.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func toggleFollow(_ suggestion: OnboardingTeamSuggestion) {
        if let existing = followedTeams.first(where: { $0.teamName.caseInsensitiveCompare(suggestion.name) == .orderedSame }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FollowedTeamItem(
                key: TeamFollowKey.make(name: suggestion.name, category: "football"),
                teamName: suggestion.name, sportCategory: "football",
                alertsEnabled: true, createdAt: Date()
            ))
        }
        if saveChanges() { HapticManager.impact(.light) }
    }

    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveError = "Please try again. Your changes haven't been saved yet."
            return false
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
                AsyncImage(url: team.badgeURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "shield").resizable().scaledToFit()
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .frame(width: 52, height: 52)
                Text(team.name)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Label(isFollowed ? "Following" : "Follow", systemImage: isFollowed ? "checkmark.circle.fill" : "plus.circle")
                    .font(.caption)
            }
            .foregroundStyle(isFollowed ? FottyTheme.accentText : FottyTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(10)
            .background(FottyTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(team.name)
        .accessibilityValue(isFollowed ? "Following" : "Not followed")
        .accessibilityHint(isFollowed ? "Unfollow this team" : "Follow this team")
    }
}

struct OnboardingTeamSuggestion: Identifiable {
    var id: String { name.lowercased() }
    let name: String
    let badgeURL: URL?
}
