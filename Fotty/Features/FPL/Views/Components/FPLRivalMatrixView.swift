import SwiftUI

/// The user-facing Rival Race Centre. The legacy type name remains so existing
/// navigation call sites do not fork another rival surface.
public struct FPLRivalMatrixView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var metricMinimumWidth: CGFloat = 118
    @ObservedObject private var viewModel: FPLAdvisorViewModel
    let onOpenLeagues: (() -> Void)?
    private var rivalRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    public init(viewModel: FPLAdvisorViewModel, onOpenLeagues: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenLeagues = onOpenLeagues
    }

    private var candidateRivals: [FPLLeagueStandingEntry] {
        Array((viewModel.leagueStandings?.standings.results ?? [])
            .filter { $0.entry != viewModel.managerId }
            .prefix(8))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.gameweekPhase == .planning {
                preDeadlineState
            } else if let gap = viewModel.rivalGapAnalysis {
                raceContent(gap)
            } else if viewModel.isRivalLoading {
                loadingState
            } else {
                rivalPicker
            }

            if let error = viewModel.rivalErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.accentText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FottyTheme.liveAccent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous)
                .strokeBorder(FottyTheme.border, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Label("RIVAL RACE CENTRE", systemImage: "flag.checkered.2.crossed")
                    .font(FottyTheme.typeSectionTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text("Compare one rival using the same gameweek scoring data as your team.")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(phaseLabel)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
            }
        }
    }

    private var phaseLabel: String {
        viewModel.gameweekPhase == .planning ? "PRE-DEADLINE" : viewModel.rivalComparisonStatus
    }

    private var preDeadlineState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.fottyScaled(size: 30, weight: .bold))
                .foregroundStyle(FottyTheme.accentText)
            Text("Rival squads are hidden until the deadline")
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)
            Text("Mini-league standings are available now. Come back after the deadline to compare published captains, unique players, live points, and players remaining.")
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
            if let onOpenLeagues {
                Button("Open mini-leagues", action: onOpenLeagues).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().tint(FottyTheme.accentText)
            Text("Loading the selected published squad…")
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    private var rivalPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE A RIVAL")
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textTertiary)

            if candidateRivals.isEmpty {
                Text("Choose a mini-league to find a rival.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88)
                if let onOpenLeagues {
                    Button("Open mini-leagues", action: onOpenLeagues).frame(minHeight: 44)
                }
            } else {
                ForEach(candidateRivals) { entry in
                    Button {
                        Task { await viewModel.inspectRival(entry: entry) }
                    } label: {
                        rivalRowLayout {
                            Text("#\(entry.rank)")
                                .font(FottyTheme.typeAction)
                                .foregroundStyle(FottyTheme.accentText)
                                .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 0 : 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.entryName)
                                    .font(FottyTheme.typeModuleTitle)
                                    .foregroundStyle(FottyTheme.textPrimary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                Text("\(entry.managerName) • \(entry.total) pts")
                                    .font(FottyTheme.typeMeta)
                                    .foregroundStyle(FottyTheme.textSecondary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            }
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(FottyTheme.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 52)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
                    }
                    .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusMD))
                    .accessibilityLabel("Compare with \(entry.entryName), managed by \(entry.managerName), rank \(entry.rank), \(entry.total) points")
                }
            }
        }
    }

    private func raceContent(_ gap: RivalGapAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.isRivalLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(FottyTheme.accentText)
                    Text("Updating both sides of this comparison…").font(FottyTheme.typeMeta)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.rivalName)
                        .font(FottyTheme.typeModuleTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                        .lineLimit(2)
                    Text(gap.strategyMode.rawValue.replacingOccurrences(of: " MODE", with: ""))
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.accentText)
                }
                Spacer()
                Menu {
                    ForEach(candidateRivals) { entry in
                        Button("#\(entry.rank) · \(entry.entryName)") {
                            Task { await viewModel.inspectRival(entry: entry) }
                        }
                    }
                } label: {
                    Label("Change", systemImage: "person.2.fill")
                        .font(FottyTheme.typeAction)
                        .frame(minHeight: 44)
                }
                .tint(FottyTheme.accentText)
                .accessibilityHint("Choose another manager from the loaded league page")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: metricMinimumWidth), spacing: 8)], spacing: 8) {
                metric("STANDINGS GAP", signedGap(gap.pointDeficit), "last loaded · \(gapDetail(gap.pointDeficit))")
                metric("GW \(gap.gameweek) GAP", signedGap(gap.gameweekDeficit), "you \(gap.myGameweekPoints) · rival \(gap.rivalGameweekPoints)")
                metric("PLAYERS LEFT", "\(gap.myPlayersRemaining)–\(gap.rivalPlayersRemaining)", "you–rival · active players, not fixtures")
                metric("SHARED", "\(gap.sharedPlayers.count)", "squad players")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(gap.scoringLabel)
                Text("GW totals include transfer hits: you −\(gap.myTransferCost), rival −\(gap.rivalTransferCost).")
                if let checkedAt = gap.checkedAt {
                    Text("Scoring evidence checked \(checkedAt.formatted(date: .abbreviated, time: .shortened)).")
                }
                Text("The standings gap is a separately loaded league snapshot, not a live overall rank.")
            }
            .font(FottyTheme.typeCaption)
            .foregroundStyle(FottyTheme.textSecondary)

            Text("Based on the last loaded standings: \(gap.tacticalAdvice)")
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.accent.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))

            captainClash(gap)

            if gap.hasOfficialLiveSnapshot {
                liveSwing(gap)
            }

            playerSection(
                title: "Your unique players",
                subtitle: "Players in your published squad only; bench players may not score",
                players: gap.myDifferentials,
                color: FottyTheme.success,
                empty: "No unique players in the two published squads."
            )
            playerSection(
                title: "Rival threats",
                subtitle: "Players in the rival's published squad only; bench players may not score",
                players: gap.rivalThreats,
                color: FottyTheme.accentText,
                empty: "The rival has no unique players in this comparison."
            )

            Label(
                "Both squads use one gameweek snapshot and the same substitution, captaincy and transfer-hit rules. Projections are labeled; Fotty does not estimate effective ownership or live rank.",
                systemImage: "checkmark.shield.fill"
            )
            .font(FottyTheme.typeCaption)
            .foregroundStyle(FottyTheme.textTertiary)
        }
    }

    private func metric(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textTertiary)
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(FottyTheme.textPrimary)
            Text(detail)
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(10)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
        .accessibilityElement(children: .combine)
    }

    private func captainClash(_ gap: RivalGapAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CAPTAIN CLASH", systemImage: "c.circle.fill")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.accentText)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    captain("YOU", gap.myCaptainName ?? "No scoring captain", FottyTheme.success)
                    Image(systemName: gap.myCaptainName == gap.rivalCaptainName ? "equal.circle.fill" : "arrow.left.arrow.right.circle.fill")
                        .foregroundStyle(FottyTheme.textTertiary)
                        .accessibilityHidden(true)
                    captain("RIVAL", gap.rivalCaptainName ?? "No scoring captain", FottyTheme.accentText)
                }
                VStack(spacing: 8) {
                    captain("YOU", gap.myCaptainName ?? "No scoring captain", FottyTheme.success)
                    captain("RIVAL", gap.rivalCaptainName ?? "No scoring captain", FottyTheme.accentText)
                }
            }
            Text("Scoring multipliers: you ×\(gap.myCaptainMultiplier), rival ×\(gap.rivalCaptainMultiplier). \(gap.pointsAreProjected ? "Includes projected captain replacement." : "From the published scoring lineup.")")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
    }

    private func captain(_ label: String, _ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textTertiary)
            Text(name)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func liveSwing(_ gap: RivalGapAnalysis) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(FottyTheme.accentText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("UNIQUE-PLAYER POINTS SWING")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text("You \(gap.myUniqueLivePoints) • Rival \(gap.rivalUniqueLivePoints) points. Excludes shared players and transfer hits; this is not the full GW gap.")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            Spacer()
            Text("\(gap.uniquePlayerSwing >= 0 ? "+" : "")\(gap.uniquePlayerSwing)")
                .font(.title3.weight(.black))
                .foregroundStyle(gap.uniquePlayerSwing >= 0 ? FottyTheme.success : FottyTheme.error)
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
        .accessibilityElement(children: .combine)
    }

    private func playerSection(
        title: String,
        subtitle: String,
        players: [PlayerScore],
        color: Color,
        empty: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(color)
            Text(subtitle)
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textSecondary)
            if players.isEmpty {
                Text(empty)
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
            } else {
                ForEach(players) { player in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.player.webName)
                                .font(FottyTheme.typeAction)
                                .foregroundStyle(FottyTheme.textPrimary)
                            HStack(spacing: 4) {
                                TeamIdentityLabel(
                                    teamName: player.team.shortName,
                                    badgeURL: player.team.badgeURL,
                                    badgeSize: 18,
                                    font: FottyTheme.typeCaption,
                                    foregroundColor: FottyTheme.textSecondary
                                )
                                Text("• \(player.player.positionName) • \(player.player.formattedCost)")
                                    .font(FottyTheme.typeCaption)
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        Spacer()
                        Text(player.player.selectedByPercent + "%")
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                    .padding(10)
                    .background(color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func signedGap(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func gapDetail(_ value: Int) -> String {
        if value > 0 { return "rival ahead" }
        if value < 0 { return "you ahead" }
        return "level"
    }
}
