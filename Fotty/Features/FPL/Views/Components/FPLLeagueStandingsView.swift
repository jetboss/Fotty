import SwiftUI

public struct FPLLeagueStandingsView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    private var leagues: [FPLLeagueSummary] {
        viewModel.managerSummary?.leagues?.classic ?? []
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            leagueSelector
            standingsHeader
            standingsContent
        }
    }

    @ViewBuilder
    private var leagueSelector: some View {
        if !leagues.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(leagues) { league in
                        let isSelected = viewModel.selectedLeagueId == league.id
                        Button {
                            HapticManager.impact(.light)
                            Task {
                                await viewModel.loadLeagueStandings(leagueId: league.id)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(league.name)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(league.isPrivateMiniLeague ? "Mini-league" : "FPL league")
                                    if let rank = league.entryRank {
                                        Text("• #\(rank)")
                                    }
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSelected ? FottyTheme.textOnAccent.opacity(0.8) : FottyTheme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? FottyTheme.accent : FottyTheme.surface)
                            .foregroundStyle(isSelected ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.clear : FottyTheme.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(league.name), \(league.isPrivateMiniLeague ? "mini-league" : "FPL league")\(league.entryRank.map { ", rank \($0)" } ?? "")")
                    }
                }
            }
        }
    }

    private var standingsHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .foregroundStyle(FottyTheme.accentText)
                Text("OFFICIAL FPL STANDINGS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
            }

            Spacer()

            if let table = viewModel.leagueStandings?.standings {
                Text("Page \(table.page) • \(table.results.count) shown")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var standingsContent: some View {
        if viewModel.isLeagueLoading {
            loadingState
        } else if let message = viewModel.leagueErrorMessage,
                  viewModel.leagueStandings == nil {
            errorState(message)
        } else if let table = viewModel.leagueStandings?.standings {
            standingsTable(table)
        } else {
            emptyState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(FottyTheme.accentText)
            Text("Loading league standings…")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FottyTheme.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                guard let leagueId = viewModel.selectedLeagueId else { return }
                Task { await viewModel.loadLeagueStandings(leagueId: leagueId) }
            }
            .buttonStyle(.borderedProminent)
            .tint(FottyTheme.accentText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        Text(leagues.isEmpty ? "No FPL leagues were returned for this manager." : "Select a league to see its standings.")
            .font(.caption)
            .foregroundStyle(FottyTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private func standingsTable(_ table: FPLLeagueStandingsTable) -> some View {
        let firstTotal = table.results.first?.total ?? 0

        return VStack(spacing: 6) {
            tableHeader

            ForEach(table.results) { entry in
                standingRow(entry, firstTotal: firstTotal)
            }

            if let message = viewModel.leagueErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(FottyTheme.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }

            if table.hasNext {
                Button {
                    Task { await viewModel.loadNextLeagueStandingsPage() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isLoadingMoreLeagueStandings {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isLoadingMoreLeagueStandings ? "Loading…" : "Load 50 more")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(FottyTheme.accentText)
                .disabled(viewModel.isLoadingMoreLeagueStandings)
            }
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("RANK").frame(width: 48, alignment: .leading)
            Text("MANAGER & SQUAD")
            Spacer()
            Text("GW").frame(width: 36, alignment: .trailing)
            Text("TOT").frame(width: 44, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(FottyTheme.textTertiary)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func standingRow(_ entry: FPLLeagueStandingEntry, firstTotal: Int) -> some View {
        let isMe = entry.entry == viewModel.managerId
        let gapToLeader = entry.total - firstTotal

        return Button {
            guard !isMe else { return }
            HapticManager.impact(.light)
            Task { await viewModel.inspectRival(entry: entry) }
        } label: {
            HStack {
                rankView(entry, isMe: isMe)
                    .frame(width: 48, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.entryName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .lineLimit(1)
                        if isMe {
                            Text("YOU")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(FottyTheme.textOnAccent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(FottyTheme.accent)
                                .clipShape(Capsule())
                        } else if entry.entry == viewModel.selectedRivalID {
                            Text("RIVAL")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(FottyTheme.textOnAccent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(FottyTheme.liveAccent)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 4) {
                        Text(entry.managerName)
                            .lineLimit(1)
                        if gapToLeader < 0 {
                            Text("• \(gapToLeader) pts to 1st")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                }

                Spacer()

                Text("\(entry.eventTotal)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(width: 36, alignment: .trailing)

                Text("\(entry.total)")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(12)
            .background(isMe ? FottyTheme.accent.opacity(0.12) : FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isMe ? FottyTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isMe)
        .accessibilityLabel("Rank \(entry.rank), \(entry.entryName), managed by \(entry.managerName), \(entry.eventTotal) gameweek points, \(entry.total) total points")
        .accessibilityHint(isMe ? "This is your team" : "Selects this manager for the Rival Race Centre")
    }

    private func rankView(_ entry: FPLLeagueStandingEntry, isMe: Bool) -> some View {
        HStack(spacing: 4) {
            Text("#\(entry.rank)")
                .font(.subheadline.weight(.black))
                .foregroundStyle(isMe ? FottyTheme.accentText : FottyTheme.textPrimary)

            if entry.lastRank > entry.rank {
                rankDelta(entry.lastRank - entry.rank, rising: true)
            } else if entry.lastRank > 0, entry.lastRank < entry.rank {
                rankDelta(entry.rank - entry.lastRank, rising: false)
            }
        }
    }

    private func rankDelta(_ value: Int, rising: Bool) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "triangle.fill")
                .rotationEffect(rising ? .zero : .degrees(180))
            Text("\(value)")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(rising ? FottyTheme.success : FottyTheme.error)
    }
}
