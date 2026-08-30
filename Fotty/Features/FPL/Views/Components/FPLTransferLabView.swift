import SwiftUI

public struct FPLTransferLabView: View {
    @ObservedObject private var viewModel: FPLAdvisorViewModel
    private let onStageRoute: (FPLDraftRoute) -> Void
    @State private var selectedRouteID: String?
    @State private var statusMessage: String?

    public init(
        viewModel: FPLAdvisorViewModel,
        onStageRoute: @escaping (FPLDraftRoute) -> Void
    ) {
        self.viewModel = viewModel
        self.onStageRoute = onStageRoute
    }

    private var selectedRoute: FPLDraftRoute? {
        let requested = selectedRouteID.flatMap { id in
            viewModel.planningRoutes.first(where: { $0.id == id })
        }
        return requested
            ?? viewModel.planningRoutes.max(by: { $0.projectedGain < $1.projectedGain })
            ?? viewModel.planningRoutes.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("TRANSFER LAB", systemImage: "flask.fill")
                        .font(FottyTheme.typeSectionTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("Compare doing nothing, one move, and a two-move route on the same modeled horizon.")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Text("\(viewModel.coachProfile.planningHorizon) GW")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
            }

            if viewModel.planningRoutes.isEmpty {
                Text("Load a valid squad to compare transfer routes.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                    ForEach(viewModel.planningRoutes) { route in
                        routeChoice(route)
                    }
                }

                if let route = selectedRoute {
                    routeDetail(route)
                }
            }

            Text("Projections are Fotty estimates. Free transfers, selling prices, and submitted changes must be confirmed in official FPL.")
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textTertiary)

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.success)
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous)
                .strokeBorder(FottyTheme.border, lineWidth: 1)
        }
        .onAppear {
            if selectedRouteID == nil {
                selectedRouteID = selectedRoute?.id
            }
        }
    }

    private func routeChoice(_ route: FPLDraftRoute) -> some View {
        let selected = route.id == selectedRoute?.id
        return Button {
            HapticManager.selection()
            selectedRouteID = route.id
            statusMessage = nil
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(route.name)
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(selected ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
                    .lineLimit(2)
                Text("\(route.transfers.count) move\(route.transfers.count == 1 ? "" : "s")")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(selected ? FottyTheme.textOnAccent.opacity(0.75) : FottyTheme.textSecondary)
                Text("\(route.projectedGain >= 0 ? "+" : "")\(route.projectedGain.formatted(.number.precision(.fractionLength(1)))) pts")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(selected ? FottyTheme.textOnAccent : (route.projectedGain > 0 ? FottyTheme.success : FottyTheme.textSecondary))
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(10)
            .background(selected ? FottyTheme.accent : FottyTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                    .strokeBorder(selected ? Color.clear : FottyTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(route.name), \(route.transfers.count) moves, modeled \(route.projectedGain.formatted(.number.precision(.fractionLength(1)))) points, estimated hit \(route.hitCost)")
        .accessibilityHint("Shows this route's evidence and downside")
    }

    private func routeDetail(_ route: FPLDraftRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                labMetric("MOVES", "\(route.transfers.count)")
                labMetric("EST. HIT", route.hitCost == 0 ? "0" : "-\(route.hitCost)")
                labMetric("NET MODEL", "\(route.projectedGain >= 0 ? "+" : "")\(route.projectedGain.formatted(.number.precision(.fractionLength(1))))")
            }

            if route.transfers.isEmpty {
                Label("Keep the current squad", systemImage: "pause.circle.fill")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
            } else {
                ForEach(route.transfers) { transfer in
                    HStack(spacing: 8) {
                        Text(transfer.playerOut.player.webName)
                            .foregroundStyle(FottyTheme.error)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                        Text(transfer.playerIn.player.webName)
                            .foregroundStyle(FottyTheme.success)
                        Spacer(minLength: 4)
                    }
                    .font(FottyTheme.typeAction)
                    .accessibilityElement(children: .combine)
                }
            }

            Text(route.explanation)
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("WEEK-BY-WEEK NET EFFECT")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(route.weeklyProjectedGain.keys.sorted(), id: \.self) { gameweek in
                        let value = route.weeklyProjectedGain[gameweek] ?? 0
                        Text("GW\(gameweek) \(value >= 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(1))))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(value >= 0 ? FottyTheme.success : FottyTheme.accentText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(FottyTheme.surfaceSubtle)
                            .clipShape(Capsule())
                    }
                }
                Text(route.hitCost == 0
                     ? "No points hit to recover"
                     : route.breakEvenGameweek.map { "Modeled hit break-even: GW\($0)" } ?? "No modeled break-even inside this horizon")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            Label("Downside", systemImage: "exclamationmark.triangle.fill")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.accentText)
            Text(route.downside)
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)

            Label("Verify before deadline", systemImage: "checklist")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.accentText)
            ForEach(Array(route.verificationItems.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "circle")
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            HStack(spacing: 8) {
                Button {
                    onStageRoute(route)
                    statusMessage = route.transfers.isEmpty
                        ? "Current squad restored in the local draft."
                        : "Route staged below. Review legality before saving."
                } label: {
                    Label(route.transfers.isEmpty ? "Use roll baseline" : "Stage route", systemImage: "arrow.down.circle.fill")
                        .font(FottyTheme.typeAction)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(FottyTheme.accentText)

                Button {
                    viewModel.recordRouteDecision(route)
                    statusMessage = "Route saved to the Decision Journal."
                } label: {
                    Image(systemName: "bookmark.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(FottyTheme.accentText)
                .accessibilityLabel("Save route to Decision Journal")
            }
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
    }

    private func labMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textTertiary)
            Text(value)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(8)
        .background(FottyTheme.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
