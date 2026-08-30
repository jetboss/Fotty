import SwiftUI

struct InsightsHubTab: View {
    let data: MatchHubData
    let providers: [String]
    @State private var insights: MatchInsightsData?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
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
                        .font(.system(size: 12, weight: .medium))
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .refreshable {
            await loadInsights(forceRefresh: true)
        }
        .task(id: "\(data.fixture.id)-\(data.lastUpdated.timeIntervalSince1970)") {
            await loadInsights(forceRefresh: false)
        }
    }

    private var shouldExplainLineupAvailability: Bool {
        guard !data.fixture.status.isFinished else { return false }
        let secondsUntilKickoff = data.fixture.utcDate.timeIntervalSinceNow
        return data.fixture.status.isLive || secondsUntilKickoff < 3 * 3600
    }

    private var lineupAvailabilityCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.fottyScaled(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
            VStack(alignment: .leading, spacing: 3) {
                Text("Lineups not available in Fotty yet")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text("Confirmed teams usually appear close to kickoff.")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
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

    private func loadInsights(forceRefresh: Bool) async {
        isLoading = true
        loadError = nil
        do {
            let loadedInsights = try await FootballRepository.shared.getMatchInsights(
                fixtureId: data.fixture.id,
                policy: forceRefresh ? .full : .automatic
            )
            guard !Task.isCancelled else { return }
            insights = loadedInsights
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Match insights could not be refreshed. Check your connection and try again."
        }
        guard !Task.isCancelled else { return }
        isLoading = false
    }
}

struct MatchHubTeamNewsSection: View {
    let headlines: [FottyTeamNewsItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(FottyTheme.accentText)
                Text("MATCH NEWS")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(headlines) { item in
                    if let url = item.url {
                        Link(destination: url) {
                            teamNewsRow(item)
                        }
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
            Text(item.teamName.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(FottyTheme.textTertiary)
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(.leading)
            if let source = item.source {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

struct DataUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(FottyTheme.textTertiary)

            Text(title)
                .font(.system(size: 14, weight: .bold))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
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
                Text("MATCH NOTES")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black))
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
                            .font(.system(size: 14, weight: .medium))
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
