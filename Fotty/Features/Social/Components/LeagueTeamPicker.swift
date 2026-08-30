import SwiftUI
import SwiftData

struct LeagueTeamPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]

    @State private var searchText = ""
    @State private var selectedLeague = "Premier League"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var teams: [SocialTeamSuggestion] = []

    private let brandService = TeamBrandService.shared

    private let leagues = [
        "Premier League",
        "Champions League",
        "La Liga",
        "Serie A",
        "Bundesliga",
        "Ligue 1",
        "MLS",
        "Eredivisie"
    ]

    private var filteredTeams: [SocialTeamSuggestion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return teams }
        return teams.filter { $0.teamName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            searchField
                .padding(.horizontal, FottyTheme.spacingMD)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(leagues, id: \.self) { league in
                        leagueChip(league)
                    }
                }
                .padding(.horizontal, FottyTheme.spacingMD)
            }

            if isLoading {
                ProgressView("Loading current club catalog…")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .tint(FottyTheme.accentText)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Teams Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: loadTeamsForSelectedLeague)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(.horizontal, FottyTheme.spacingMD)
            } else if filteredTeams.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)],
                    spacing: 20
                ) {
                    ForEach(filteredTeams) { team in
                        teamCell(team)
                    }
                }
                .padding(FottyTheme.spacingMD)
                .background(FottyTheme.surface.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG))
                .padding(.horizontal, FottyTheme.spacingMD)
            }
        }
        .task(id: selectedLeague) {
            await loadTeams(for: selectedLeague)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FottyTheme.textTertiary)
            TextField("Search teams…", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                .accessibilityLabel("Clear team search")
            }
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FottyTheme.border, lineWidth: 1))
    }

    private func leagueChip(_ league: String) -> some View {
        Button {
            selectedLeague = league
        } label: {
            Text(league)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedLeague == league ? FottyTheme.accent : FottyTheme.surfaceElevated)
                .foregroundStyle(selectedLeague == league ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(FottyTheme.border, lineWidth: selectedLeague == league ? 0 : 1))
        }
        .accessibilityAddTraits(selectedLeague == league ? .isSelected : [])
    }

    private func teamCell(_ team: SocialTeamSuggestion) -> some View {
        let isFollowed = followedTeams.contains { $0.key == team.followKey }

        return Button {
            toggleFollow(team)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(FottyTheme.surfaceElevated)
                        .frame(width: 64, height: 64)

                    if let url = team.badgeURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else if phase.error != nil {
                                Image(systemName: "sportscourt").foregroundStyle(FottyTheme.textTertiary)
                            } else {
                                ProgressView().tint(FottyTheme.accentText)
                            }
                        }
                        .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "sportscourt")
                            .font(.title2)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }

                    if isFollowed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(FottyTheme.accentText)
                            .background(Circle().fill(.white))
                            .offset(x: 22, y: -22)
                    }
                }

                Text(team.teamName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isFollowed ? FottyTheme.accent.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("\(team.teamName), \(isFollowed ? "followed" : "not followed")")
        .accessibilityHint(isFollowed ? "Unfollows this team" : "Follows this team")
    }

    private func toggleFollow(_ team: SocialTeamSuggestion) {
        if let existing = followedTeams.first(where: { $0.key == team.followKey }) {
            modelContext.delete(existing)
            FottyLogger.shared.log(.featureUsage, message: "Unfollowed team: \(team.teamName)")
        } else {
            modelContext.insert(
                FollowedTeamItem(
                    key: team.followKey,
                    teamName: team.teamName,
                    sportCategory: team.sportCategory,
                    badgeURLString: team.badgeURL?.absoluteString,
                    alertsEnabled: true
                )
            )
            FottyLogger.shared.log(.featureUsage, message: "Followed team: \(team.teamName)")
        }

        do {
            try modelContext.save()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = "Your follow could not be saved. Please try again."
        }
    }

    private func loadTeamsForSelectedLeague() {
        Task { await loadTeams(for: selectedLeague) }
    }

    private func loadTeams(for league: String) async {
        isLoading = true
        errorMessage = nil

        let catalog = await brandService.fetchLeagueCatalog(leagueName: catalogLeagueName(for: league))
        guard !Task.isCancelled, selectedLeague == league else { return }

        teams = catalog.map { team in
            let followKey = TeamFollowKey.make(name: team.displayName, category: "football")
            return SocialTeamSuggestion(
                id: "\(followKey)::\(league.lowercased())",
                followKey: followKey,
                teamName: team.displayName,
                sportCategory: "football",
                kickoff: nil,
                leagueName: league,
                badgeURL: team.badgeURL
            )
        }
        isLoading = false

        if teams.isEmpty {
            errorMessage = "The live club catalog for \(league) could not be loaded."
        }
    }

    private func catalogLeagueName(for league: String) -> String {
        switch league {
        case "Premier League": return "English Premier League"
        case "Champions League": return "UEFA Champions League"
        case "La Liga": return "Spanish La Liga"
        case "Serie A": return "Italian Serie A"
        case "Bundesliga": return "German Bundesliga"
        case "Ligue 1": return "French Ligue 1"
        case "MLS": return "American Major League Soccer"
        case "Eredivisie": return "Dutch Eredivisie"
        default: return league
        }
    }
}
