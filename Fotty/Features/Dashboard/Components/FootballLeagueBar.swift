import SwiftUI

struct FootballLeagueBar: View {
    let leagues: [AnalyticalDataEngine.FootballLeagueTab]
    @Binding var selectedLeague: AnalyticalDataEngine.FootballLeagueTab
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FottyTheme.spacingSM) {
                ForEach(leagues) { league in
                    DashboardTabButton(
                        text: league.displayName,
                        isSelected: selectedLeague == league,
                        icon: { leagueIcon(for: league) }
                    ) {
                        withAnimation(FottyTheme.springSnappy) {
                            selectedLeague = league
                        }
                    }
                }
            }
            .padding(.horizontal, FottyTheme.spacingMD)
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func leagueIcon(for league: AnalyticalDataEngine.FootballLeagueTab) -> some View {
        if let url = league.badgeURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color.white.opacity(0.1)
            }
            .frame(width: 14, height: 14)
        } else {
            Image(systemName: "shield.fill")
                .font(.fottyScaled(size: 10))
        }
    }
}
