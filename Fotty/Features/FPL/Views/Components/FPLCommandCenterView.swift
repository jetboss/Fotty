import SwiftUI

public struct FPLCommandCenterView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    let onNavigate: (FPLCommandCenterAction.Destination) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentWidth: CGFloat = 0

    public init(
        viewModel: FPLAdvisorViewModel,
        onNavigate: @escaping (FPLCommandCenterAction.Destination) -> Void
    ) {
        self.viewModel = viewModel
        self.onNavigate = onNavigate
    }

    public var body: some View {
        Group {
            if contentWidth >= 760 && !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 16) {
                    decisionColumn.frame(minWidth: 420, maxWidth: .infinity)
                    supportingColumn.frame(minWidth: 300, maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    decisionColumn
                    supportingColumn
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    private var decisionColumn: some View {
        VStack(spacing: 14) {
            phaseCard
            if let state = viewModel.commandCenterState {
                if !state.warnings.isEmpty { warningCard(state.warnings) }
                actionList(state.actions)
            }
            if viewModel.gameweekPhase == .planning { reminderCard }
        }
    }

    private var supportingColumn: some View {
        VStack(spacing: 14) {
            if let state = viewModel.commandCenterState, !state.metrics.isEmpty { metricGrid(state.metrics) }
            evidenceStrip
            if let review = viewModel.gameweekReviews.first { reviewCard(review) }
            if viewModel.gameweekPhase == .planning, let lesson = latestReviewedDecision {
                carriedLessonCard(lesson)
            }
        }
    }

    private var latestReviewedDecision: FPLDecisionJournalEntry? {
        viewModel.decisionJournalEntries
            .filter { $0.outcome != .pending && !$0.outcomeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func carriedLessonCard(_ entry: FPLDecisionJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("LESSON CARRIED INTO THIS PLAN", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption.weight(.black))
                .foregroundStyle(FottyTheme.accentText)
            Text(entry.title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(FottyTheme.textPrimary)
            Text(entry.outcomeNote)
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("GW\(entry.gameweek) • \(entry.outcome.rawValue) • review the process, not only the points")
                .font(.caption2)
                .foregroundStyle(FottyTheme.textTertiary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
    }

    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(phaseLabel, systemImage: phaseSymbol)
                        .font(.caption.weight(.black))
                        .foregroundStyle(phaseColor)
                    Text(viewModel.commandCenterState?.title.replacingOccurrences(of: " Command Center", with: "") ?? "Your FPL gameweek")
                        .font(.title3.weight(.black))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(viewModel.commandCenterState?.subtitle ?? "Refresh official FPL data to build today's decision list.")
                        .font(.subheadline)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: phaseSymbol)
                    .font(.fottyScaled(size: 22, weight: .bold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 46, height: 46)
                    .background(phaseColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
            }

            if let validation = viewModel.squadValidation {
                Label(
                    validation.isValid ? "Squad meets FPL rules" : "Draft needs \(validation.issues.filter { $0.severity == .error }.count) fix(es)",
                    systemImage: validation.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(validation.isValid ? FottyTheme.success : FottyTheme.error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [phaseColor.opacity(0.16), FottyTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(phaseColor.opacity(0.25), lineWidth: 1))
    }

    private func metricGrid(_ metrics: [FPLCommandCenterMetric]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3),
            spacing: 8
        ) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.label == "EST. FT" ? "Estimated free transfers" : metric.label.localizedCapitalized)
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metric.value)
                        .font(.fottyScaled(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = metric.detail {
                        Text(detail)
                            .font(FottyTheme.typeCaption)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .padding(11)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(FottyTheme.border, lineWidth: 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gameweek snapshot")
    }

    private func warningCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needs attention", systemImage: "exclamationmark.shield.fill")
                .font(.subheadline.weight(.black))
                .foregroundStyle(FottyTheme.accentText)
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(FottyTheme.liveAccent).frame(width: 5, height: 5).padding(.top, 6)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.liveAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionList(_ actions: [FPLCommandCenterAction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your next move")
                .font(.caption.weight(.black))
                .foregroundStyle(FottyTheme.textTertiary)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    onNavigate(action.destination)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol)
                            .font(.fottyScaled(size: 16, weight: .bold))
                            .foregroundStyle(FottyTheme.accentText)
                            .frame(width: 34, height: 34)
                            .background(FottyTheme.accent.opacity(0.1))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(FottyTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                    .padding(12)
                    .background(index == 0 ? FottyTheme.accent.opacity(0.10) : FottyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(index == 0 ? FottyTheme.accent.opacity(0.45) : FottyTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var evidenceStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.primaryFreshness?.source == .diskSnapshot ? "externaldrive.badge.exclamationmark" : "checkmark.circle.fill")
                .foregroundStyle(viewModel.primaryFreshness?.source == .diskSnapshot ? FottyTheme.accentText : FottyTheme.success)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.primaryFreshness?.source.rawValue ?? "Official FPL snapshot unavailable")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(viewModel.primaryFreshness.map { "Updated \($0.shortAgeDescription) • picks from GW\(viewModel.picksGameweek ?? 0)" } ?? "Pull to refresh")
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textTertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var reminderCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(FottyTheme.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Deadline safety net")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(viewModel.alertStatusMessage ?? "Schedule private on-device alerts 24 hours and 2 hours before the deadline.")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            Spacer()
            Button("Enable") {
                Task { await viewModel.scheduleDeadlineAlerts() }
            }
            .font(.caption.weight(.black))
            .foregroundStyle(FottyTheme.textOnAccent)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(FottyTheme.accent)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reviewCard(_ review: FPLGameweekReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Latest confirmed review", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
                Spacer()
                Text("GW\(review.gameweek)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.accentText)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0)), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 12) {
                reviewStat("Points", "\(review.points)")
                reviewStat("Bench points", "\(review.pointsOnBench)")
                reviewStat("Transfer hits", "\(review.transferCost)")
                reviewStat("Overall rank", review.overallRank.map { "#\($0)" } ?? "—")
            }
        }
        .padding(14)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func reviewStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(FottyTheme.typeCaption).foregroundStyle(FottyTheme.textTertiary)
            Text(value).font(.caption.weight(.black)).foregroundStyle(FottyTheme.textPrimary)
        }
    }

    private var phaseLabel: String { viewModel.gameweekPhase.rawValue.uppercased() }

    private var phaseSymbol: String {
        switch viewModel.gameweekPhase {
        case .planning: return "checklist"
        case .locked: return "lock.fill"
        case .live: return "bolt.fill"
        case .review: return "checkmark.seal.fill"
        case .unavailable: return "questionmark.circle"
        }
    }

    private var phaseColor: Color {
        switch viewModel.gameweekPhase {
        case .planning: return FottyTheme.accentText
        case .locked: return FottyTheme.accentText
        case .live: return FottyTheme.success
        case .review: return FottyTheme.success
        case .unavailable: return FottyTheme.textTertiary
        }
    }
}
