import SwiftUI

public struct FPLLiveTrackerView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    let onOpenPlan: (() -> Void)?

    public init(viewModel: FPLAdvisorViewModel, onOpenPlan: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenPlan = onOpenPlan
    }

    public var body: some View {
        VStack(spacing: 14) {
            if let summary = viewModel.liveSquadSummary {
                scoreCard(summary)
                playerList(summary)
                automaticSubs(summary)
            } else {
                unavailableCard
                if viewModel.gameweekPhase == .planning, let onOpenPlan {
                    Button("Back to your plan", action: onOpenPlan).frame(minHeight: 44)
                }
            }
            sourceCard
        }
        .task(id: viewModel.gameweekPhase.rawValue) {
            guard viewModel.gameweekPhase == .locked || viewModel.gameweekPhase == .live else { return }
            while !Task.isCancelled {
                await viewModel.refreshMatchdayData()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func scoreCard(_ summary: FPLLiveSquadSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    !summary.hasCompleteScoringData ? "INCOMPLETE PLAYER DATA" : (summary.pointsAreProjected ? "PROVISIONAL FPL TOTAL" : (summary.isFinal ? "OFFICIAL RESULT" : "OFFICIAL LIVE")),
                    systemImage: summary.pointsAreProjected ? "arrow.triangle.2.circlepath" : (summary.isFinal ? "checkmark.seal.fill" : "bolt.fill")
                )
                    .font(.caption.weight(.black))
                    .foregroundStyle(summary.isFinal ? FottyTheme.success : FottyTheme.accentText)
                Spacer()
                Text("GW\(summary.gameweek)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(summary.totalPoints.map(String.init) ?? "—")
                    .font(.fottyScaled(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(summary.pointsAreProjected ? "projected points" : "points")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FottyTheme.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summary.hasCompleteScoringData ? "\(summary.playersRemaining)" : "—")
                        .font(.title3.weight(.black))
                        .foregroundStyle(summary.playersRemaining > 0 ? FottyTheme.accentText : FottyTheme.textPrimary)
                    Text("FIXTURES LEFT")
                        .font(.fottyScaled(size: 8, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }

            HStack(spacing: 0) {
                metric("PLAYED", summary.hasCompleteScoringData ? "\(summary.playersPlayed)/\(summary.rows.count)" : "—")
                Spacer()
                metric("BONUS IN TOTAL", summary.hasCompleteScoringData ? "+\(summary.officialBonus)" : "—")
                Spacer()
                metric("AUTOSUBS", summary.hasCompleteScoringData ? "\(summary.displayedAutomaticSubs.count)" : "—")
                Spacer()
                metric("STATUS", !summary.hasCompleteScoringData ? "INCOMPLETE" : (summary.pointsAreProjected ? "PROVISIONAL" : (summary.isFinal ? "FINAL" : "UPDATING")))
            }

            if !summary.hasCompleteScoringData {
                Text("Some official player statistics are missing. Any total shown is the published official snapshot; autosub projections and player totals wait for complete data.")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if summary.pointsAreProjected, let officialPoints = summary.officialCurrentPoints,
               let totalPoints = summary.totalPoints {
                HStack(spacing: 10) {
                    autosubScore("OFFICIAL CURRENT", points: officialPoints)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    autosubScore("PROVISIONAL TOTAL", points: totalPoints)
                    Spacer(minLength: 0)
                    Text(String(format: "%+d", totalPoints - officialPoints))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(FottyTheme.success)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(FottyTheme.success.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(11)
                .background(FottyTheme.surface.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(projectionExplanation(summary))
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [FottyTheme.liveAccent.opacity(0.14), FottyTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(FottyTheme.liveAccent.opacity(0.25), lineWidth: 1))
    }

    private func autosubScore(_ label: String, points: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.fottyScaled(size: 8, weight: .black))
                .foregroundStyle(FottyTheme.textTertiary)
            Text("\(points)")
                .font(.title3.weight(.black))
                .foregroundStyle(FottyTheme.textPrimary)
        }
    }

    private func playerList(_ summary: FPLLiveSquadSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(!summary.hasCompleteScoringData ? "AVAILABLE PLAYER DATA" : (summary.pointsAreProjected ? "PROJECTED SCORING XI" : "SCORING XI"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textTertiary)
                Spacer()
                Text("Official points • minutes • BPS")
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textTertiary)
            }

            ForEach(summary.rows) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(row.player.webName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            if row.pick.isCaptain {
                                badge(summary.projectedCaptainElementID == row.player.id ? "VC→C" : "C", color: FottyTheme.accentText)
                            } else if row.pick.isViceCaptain {
                                badge(summary.projectedCaptainElementID == row.player.id ? "VC→C" : "VC", color: FottyTheme.surfaceElevated)
                            }
                            if row.isProjectedSubstitute {
                                badge("SUB", color: FottyTheme.accentText.opacity(0.28))
                            }
                        }
                        Text("\(row.team.shortName) • \(row.stats.minutes)m • BPS \(row.stats.bps)\(row.stats.bonus > 0 ? " • +\(row.stats.bonus) bonus" : "")")
                            .font(.caption2)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(row.multipliedPoints)")
                            .font(.title3.weight(.black))
                            .foregroundStyle(FottyTheme.textPrimary)
                        Text(row.hasFixtureRemaining ? "fixture left" : status(for: row))
                            .font(.fottyScaled(size: 8, weight: .bold))
                            .foregroundStyle(row.hasFixtureRemaining ? FottyTheme.accentText : FottyTheme.textTertiary)
                    }
                }
                .padding(11)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func automaticSubs(_ summary: FPLLiveSquadSummary) -> some View {
        if !summary.displayedAutomaticSubs.isEmpty {
            let names = Dictionary(uniqueKeysWithValues: (viewModel.bootstrap?.elements ?? []).map { ($0.id, $0.webName) })
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    summary.pointsAreProjected ? "PROJECTED AUTOMATIC SUBSTITUTIONS" : "OFFICIAL AUTOMATIC SUBSTITUTIONS",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.accentText)
                ForEach(Array(summary.displayedAutomaticSubs.enumerated()), id: \.offset) { _, substitution in
                    Text("\(names[substitution.elementOut] ?? "Player \(substitution.elementOut)") → \(names[substitution.elementIn] ?? "Player \(substitution.elementIn)")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                if summary.pointsAreProjected {
                    Text("Provisional until official FPL publishes its automatic substitutions or completes the gameweek data check.")
                        .font(.caption2)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }

    private func projectionExplanation(_ summary: FPLLiveSquadSummary) -> String {
        var parts = [String]()
        if !summary.projectedAutomaticSubs.isEmpty {
            parts.append("formation-safe bench replacements after the outgoing player's fixtures are complete")
        }
        if summary.projectedCaptainElementID != nil {
            parts.append("vice-captain promotion after the captain's non-appearance is confirmed")
        }
        return "Fotty's provisional total includes " + parts.joined(separator: " and ") + ". Official FPL remains the final authority."
    }

    private var unavailableCard: some View {
        VStack(spacing: 12) {
            Image(systemName: emptySymbol)
                .font(.fottyScaled(size: 34, weight: .bold))
                .foregroundStyle(FottyTheme.accentText)
            Text(emptyTitle)
                .font(.headline.weight(.black))
                .foregroundStyle(FottyTheme.textPrimary)
            Text(emptyDetail)
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var sourceCard: some View {
        HStack(spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(FottyTheme.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text("No simulated points or effective ownership")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(sourceDetail)
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            Spacer()
        }
        .padding(11)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.fottyScaled(size: 8, weight: .black)).foregroundStyle(FottyTheme.textTertiary)
            Text(value).font(.caption.weight(.black)).foregroundStyle(FottyTheme.textPrimary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.fottyScaled(size: 8, weight: .black))
            .foregroundStyle(text == "C" ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(color)
            .clipShape(Capsule())
    }

    private func status(for row: FPLLiveSquadPlayer) -> String {
        if viewModel.liveSquadSummary?.isFinal == true { return "final" }
        if row.stats.played == true || row.stats.minutes > 0 { return "played" }
        return "not played"
    }

    private var emptySymbol: String {
        switch viewModel.gameweekPhase {
        case .planning: return "calendar.badge.clock"
        case .locked: return "lock.fill"
        default: return "arrow.clockwise.circle"
        }
    }

    private var emptyTitle: String {
        switch viewModel.gameweekPhase {
        case .planning: return "Live points begin after the deadline"
        case .locked: return "Official event data is waiting for kickoff"
        default: return "Official live data is not available"
        }
    }

    private var emptyDetail: String {
        switch viewModel.gameweekPhase {
        case .planning: return "Use your plan to settle transfers and captaincy. Live points appear after the deadline when official FPL data becomes available."
        case .locked: return "Your published team is locked. Pull to refresh once matches begin."
        default: return "Pull down to check official FPL data again. Fotty will not show a live total without that evidence."
        }
    }

    private var sourceDetail: String {
        if viewModel.liveSquadSummary?.pointsAreProjected == true {
            return "Official event-live points plus Fotty's deterministic bench-order and captaincy rules. Pending changes remain labeled provisional."
        }
        if let metadata = viewModel.resourceMetadata["eventLive"] {
            return "Event-live snapshot: \(metadata.source.rawValue), updated \(metadata.shortAgeDescription)."
        }
        return "Official event-live points, bonus and automatic substitutions appear only when that endpoint is available."
    }
}
