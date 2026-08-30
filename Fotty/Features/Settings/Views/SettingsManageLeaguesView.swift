import SwiftUI
import SwiftData

struct SettingsManageLeaguesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FollowedLeagueItem.leagueName, order: .forward) private var followedLeagues: [FollowedLeagueItem]
    
    private let availableLeagues = [
        ("Premier League", "football", "England"),
        ("La Liga", "football", "Spain"),
        ("Serie A", "football", "Italy"),
        ("Bundesliga", "football", "Germany"),
        ("Ligue 1", "football", "France"),
        ("Champions League", "football", "Europe"),
        ("MLS", "football", "USA"),
        ("NBA", "basketball", "USA"),
        ("WNBA", "basketball", "USA")
    ]
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            
            List {
                Section {
                    ForEach(availableLeagues, id: \.0) { league in
                        LeagueRow(
                            name: league.0,
                            category: league.1,
                            country: league.2,
                            isFollowed: followedLeagues.contains(where: { $0.leagueName == league.0 }),
                            onToggle: { toggleLeague(league) }
                        )
                    }
                } header: {
                    Text("Available Leagues")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .listRowBackground(FottyTheme.surface.opacity(0.5))
                .listRowSeparatorTint(FottyTheme.border)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Favorite Leagues")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func toggleLeague(_ league: (String, String, String)) {
        if let existing = followedLeagues.first(where: { $0.leagueName == league.0 }) {
            modelContext.delete(existing)
        } else {
            let newItem = FollowedLeagueItem(
                id: league.0.lowercased().replacingOccurrences(of: " ", with: "-"),
                leagueName: league.0,
                sportCategory: league.1,
                country: league.2
            )
            modelContext.insert(newItem)
        }
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

struct LeagueRow: View {
    let name: String
    let category: String
    let country: String
    let isFollowed: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FottyTheme.textPrimary)
                    Text("\(category.capitalized) • \(country)")
                        .font(.system(size: 12))
                        .foregroundColor(FottyTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: isFollowed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isFollowed ? FottyTheme.success : FottyTheme.textTertiary)
                    .font(.system(size: 22))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
