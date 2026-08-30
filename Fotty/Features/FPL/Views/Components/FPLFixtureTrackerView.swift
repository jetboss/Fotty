import SwiftUI

public struct FPLFixtureTrackerView: View {
    let grid: [TeamFixtureRow]
    let gameweeks: [Int]
    @ScaledMetric(relativeTo: .caption) private var cellWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 62
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var teamWidth: CGFloat = 54

    public init(grid: [TeamFixtureRow], gameweeks: [Int]) {
        self.grid = grid
        self.gameweeks = gameweeks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Difficulty: 1 easiest · 5 hardest. H = home, A = away.")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
            if grid.isEmpty || gameweeks.isEmpty {
                Text("Fixtures will appear when official FPL data is available. Pull down to refresh.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
            } else {
                Label("Swipe across for later gameweeks", systemImage: "arrow.left.and.right")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                HStack(alignment: .top, spacing: 6) {
                    // Club names stay visible while looking ahead horizontally.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Team").frame(height: headerHeight)
                        ForEach(grid) { row in
                            Text(row.team.shortName)
                                .frame(height: rowHeight)
                                .accessibilityLabel(row.team.name)
                        }
                    }
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .frame(width: teamWidth, alignment: .leading)

                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                ForEach(gameweeks, id: \.self) { gameweek in
                                    Text("GW \(gameweek)")
                                        .font(FottyTheme.typeMeta)
                                        .foregroundStyle(FottyTheme.textSecondary)
                                        .frame(width: cellWidth, height: headerHeight)
                                }
                            }
                            ForEach(grid) { row in
                                HStack(spacing: 6) {
                                    ForEach(Array(gameweeks.enumerated()), id: \.offset) { index, gameweek in
                                        if row.fixtures.indices.contains(index), let fixture = row.fixtures[index] {
                                            VStack(spacing: 3) {
                                                Text("\(fixture.opponent.shortName) · \(fixture.isHome ? "H" : "A")")
                                                Text("\(fixture.difficulty)/5").font(.caption2.weight(.semibold))
                                            }
                                            .font(FottyTheme.typeCaption)
                                            .foregroundStyle(FottyFixtureDifficulty.foreground(fixture.difficulty))
                                            .frame(width: cellWidth, height: rowHeight)
                                            .background(FottyFixtureDifficulty.background(fixture.difficulty))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(row.team.name), gameweek \(gameweek), \(fixture.opponent.name), \(fixture.isHome ? "home" : "away"), \(FottyFixtureDifficulty.label(fixture.difficulty))")
                                        } else {
                                            Text("—")
                                                .foregroundStyle(FottyTheme.textSecondary)
                                                .frame(width: cellWidth, height: rowHeight)
                                                .background(FottyTheme.surface)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .accessibilityLabel("\(row.team.name), gameweek \(gameweek), no listed fixture")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }
}
