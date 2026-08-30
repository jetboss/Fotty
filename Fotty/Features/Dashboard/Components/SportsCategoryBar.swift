import SwiftUI

struct SportsCategoryBar: View {
    let categories: [String]
    @Binding var selectedCategory: String
    
    var body: some View {
        CompactHomeFilterBar(
            categories: categories,
            selectedCategory: $selectedCategory,
            leagues: [],
            selectedLeague: .constant(.all),
            showsLeagueMenu: false,
            selectedCricketFilter: .constant(.all)
        )
    }
}

/// Compact sport + league menus — replaces dual pill rails.
struct CompactHomeFilterBar: View {
    let categories: [String]
    @Binding var selectedCategory: String
    let leagues: [AnalyticalDataEngine.FootballLeagueTab]
    @Binding var selectedLeague: AnalyticalDataEngine.FootballLeagueTab
    var showsSportMenu: Bool = true
    var showsLeagueMenu: Bool = true
    @Binding var selectedCricketFilter: CricketCatalogFilter
    
    var body: some View {
        HStack(spacing: 10) {
          if showsSportMenu {
            Picker(selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Label(
                        AnalyticalDataEngine.categoryDisplayName(for: category),
                        systemImage: AnalyticalDataEngine.sportIconName(for: category)
                    )
                    .tag(category)
                }
            } label: {
                filterChip(
                    title: AnalyticalDataEngine.categoryDisplayName(for: selectedCategory),
                    systemImage: AnalyticalDataEngine.sportIconName(for: selectedCategory)
                )
            }
            .pickerStyle(.menu)
            .accessibilityLabel(
                "Sport filter"
            )
            .accessibilityValue(AnalyticalDataEngine.categoryDisplayName(for: selectedCategory))
            .accessibilityHint("Choose which sport appears in the match schedule")
          }
            
            if showsLeagueMenu, !leagues.isEmpty {
                Picker(selection: $selectedLeague) {
                    ForEach(leagues) { league in
                        Text(league.displayName)
                            .tag(league)
                    }
                } label: {
                    filterChip(title: selectedLeague.displayName, systemImage: "trophy")
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Competition filter")
                .accessibilityValue(selectedLeague.displayName)
                .accessibilityHint("Choose which football competition appears in the match schedule")
            }
            
            if selectedCategory == "cricket" {
                Picker(selection: $selectedCricketFilter) {
                    ForEach(CricketCatalogFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                } label: {
                    filterChip(title: selectedCricketFilter.displayName, systemImage: "trophy")
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Cricket filter")
                .accessibilityIdentifier("cricket-filter")
                .accessibilityValue(selectedCricketFilter.displayName)
                .accessibilityHint("Choose all cricket, CPL fixtures, or cricket channels")
            }

            Spacer(minLength: 0)
        }
    }
    
    private func filterChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.fottyScaled(size: 11, weight: .semibold))
            Text(title)
                .font(.fottyScaled(size: 13, weight: .semibold))
                .lineLimit(2)
            Image(systemName: "chevron.down")
                .font(.fottyScaled(size: 9, weight: .bold))
                .foregroundStyle(FottyTheme.textTertiary)
        }
        .foregroundStyle(FottyTheme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(FottyTheme.border, lineWidth: 0.5)
        )
    }
}
