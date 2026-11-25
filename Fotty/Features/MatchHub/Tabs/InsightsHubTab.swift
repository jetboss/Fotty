import SwiftUI

struct MatchHubLineupAvailabilityCopy: Equatable {
    let title: String
    let message: String?

    static func presentation(status: FottyMatchStatus, kickoff: Date, at now: Date) -> Self {
        let isUpcoming = (status == .scheduled || status == .preMatch) && kickoff > now
        return Self(
            title: "Lineups unavailable",
            message: isUpcoming ? "Confirmed teams usually appear close to kickoff." : nil
        )
    }
}

struct InsightsHubTab: View {
    let data: MatchHubData
    let insights: MatchInsightsData?
    let isLoading: Bool
    let loadError: String?

    var body: some View {
        LazyVStack(spacing: 20) {
                if data.homeLineup != nil && data.awayLineup != nil {
                    lineupsSection
                } else if shouldExplainLineupAvailability {
                    lineupAvailabilityCard
                }

                if !data.statistics.isEmpty {
                    MatchStatisticsView(stats: data.statistics)
                        .padding(.horizontal)
                }

                if !data.events.isEmpty {
                    MatchTimelineView(events: data.events)
                        .padding(.horizontal)
                }

                if let loadError, !isLoading, insights != nil {
                    Text("Could not refresh: \(loadError)")
                        .font(FottyTheme.typeMeta)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(FottyTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                if let insights {
                    if !insights.keyInsights.isEmpty {
                        AISummaryCard(insights: insights.keyInsights, isLive: data.fixture.status.isLive)
                            .padding(.horizontal)
                    }

                    if !insights.momentum.isEmpty {
                        MomentumChartView(momentum: insights.momentum)
                            .padding(.horizontal)
                    }

                } else if isLoading {
                    FootballLoadingView(size: 40)
                        .padding(.vertical, 24)
                } else if let loadError, data.fixture.status.isLive {
                    DataUnavailableView(
                        title: "Insights unavailable",
                        message: loadError
                    )
                }

                if !data.teamNews.isEmpty {
                    MatchHubTeamNewsSection(headlines: data.teamNews)
                        .padding(.horizontal)
                }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var shouldExplainLineupAvailability: Bool {
        guard !data.fixture.status.isFinished else { return false }
        let secondsUntilKickoff = data.fixture.utcDate.timeIntervalSinceNow
        return data.fixture.status.isLive || secondsUntilKickoff < 3 * 3600
    }

    private var lineupAvailabilityCard: some View {
        let copy = MatchHubLineupAvailabilityCopy.presentation(
            status: data.fixture.status, kickoff: data.fixture.utcDate, at: .now
        )
        return HStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.fottyScaled(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.title)
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = copy.message {
                    Text(message)
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var lineupsSection: some View {
        if let home = data.homeLineup, let away = data.awayLineup {
            TacticalPitchView(
                homeLineup: home,
                awayLineup: away,
                homeTeam: data.homeTeam,
                awayTeam: data.awayTeam
            )
            .padding(.horizontal)
        } else {
            EmptyView()
        }
    }

}

struct MatchHubTeamNewsSection: View {
    let headlines: [FottyTeamNewsItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(FottyTheme.accentText)
                Text("Match news")
                    .font(FottyTheme.typeModuleTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(headlines) { item in
                    if let url = item.url {
                        Link(destination: url) {
                            teamNewsRow(item)
                        }
                        .buttonStyle(FottyPressButtonStyle())
                    } else {
                        teamNewsRow(item)
                    }
                    if item.id != headlines.last?.id {
                        Divider().opacity(0.2)
                    }
                }
            }
            .background(FottyTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private func teamNewsRow(_ item: FottyTeamNewsItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TeamIdentityLabel(
                teamName: item.teamName,
                badgeSize: 18,
                font: FottyTheme.typeMeta.weight(.semibold),
                foregroundColor: FottyTheme.textTertiary,
                triggerSearch: true
            )
            Text(item.title)
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let source = item.source {
                Text(source)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct DataUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(FottyTheme.textTertiary)

            Text(title)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)

            Text(message)
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}

struct AISummaryCard: View {
    let insights: [String]
    var isLive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.blue)
                Text("Match notes")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(FottyTheme.typeMeta.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.blue)
                        Text(insight)
                            .font(FottyTheme.typeBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                            .foregroundStyle(FottyTheme.textPrimary)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
