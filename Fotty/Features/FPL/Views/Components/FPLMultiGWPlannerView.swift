import SwiftUI

public struct FPLMultiGWPlannerView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var gameweekMinimumWidth: CGFloat = 96
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @State private var selectedGameweek = 0
    @State private var horizon = 5
    @State private var pendingScenarioRoute: FPLDraftRoute?
    @State private var scenarioName = ""
    @State private var isNamingScenario = false
    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 14) {
            plannerHeader
            routeCard
            savedScenariosCard
            squadProjectionCard
            chipInventoryCard
            assumptionsCard
        }
        .onAppear {
            horizon = viewModel.coachProfile.planningHorizon
        }
        .onChange(of: planningWeeks) { _, weeks in
            selectedGameweek = min(selectedGameweek, max(0, weeks.count - 1))
        }
    }

    private var plannerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerLayout {
                Label("Multi-gameweek planner", systemImage: "calendar.badge.clock")
                    .font(.headline.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Picker("Horizon", selection: $horizon) {
                    Text("5 GW").tag(5)
                    Text("8 GW").tag(8)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 150)
                .onChange(of: horizon) { _, newValue in
                    var profile = viewModel.coachProfile
                    profile.planningHorizon = newValue
                    viewModel.updateCoachProfile(profile)
                    selectedGameweek = min(selectedGameweek, newValue - 1)
                }
            }

            Text(planningWeeks.isEmpty
                 ? "No upcoming gameweek is available. Refresh FPL to continue."
                 : "Compare your squad and transfer options across \(planningWeeks.count) gameweeks. Later weeks use Fotty estimates.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(planningWeeks.enumerated()), id: \.element) { item in
                        let selected = selectedGameweek == item.offset
                        Button("GW\(item.element)") {
                            selectedGameweek = item.offset
                        }
                        .font(.caption.weight(.black))
                        .foregroundStyle(selected ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .background(selected ? FottyTheme.accent : FottyTheme.surfaceElevated)
                        .clipShape(Capsule())
                        .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusXL))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TRANSFER ROUTES")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textTertiary)
                Spacer()
                if let freeTransfers = viewModel.freeTransferEstimate {
                    Text("~\(freeTransfers.count) FT • verify in FPL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(FottyTheme.accentText)
                }
            }

            ForEach(viewModel.planningRoutes) { route in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(route.name)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(FottyTheme.textPrimary)
                        Spacer()
                        Text(signed(route.projectedGain) + " modeled pts")
                            .font(.caption.weight(.black))
                            .foregroundStyle(route.projectedGain > 0 ? FottyTheme.success : FottyTheme.textSecondary)
                    }
                    if route.transfers.isEmpty {
                        Text("No transfer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FottyTheme.textSecondary)
                    } else {
                        ForEach(route.transfers) { transfer in
                            HStack {
                                Text("\(transfer.playerOut.player.webName) → \(transfer.playerIn.player.webName)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(FottyTheme.textPrimary)
                                Spacer()
                                Text(transfer.costDelta == 0 ? "same price" : signedCost(transfer.costDelta))
                                    .font(.caption2)
                                    .foregroundStyle(FottyTheme.textTertiary)
                            }
                        }
                    }
                    Text(route.hitCost > 0 ? "Includes -\(route.hitCost) transfer cost. \(route.explanation)" : route.explanation)
                        .font(.caption2)
                        .foregroundStyle(FottyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: gameweekMinimumWidth), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(route.weeklyProjectedGain.keys.sorted(), id: \.self) { gameweek in
                            Text("GW\(gameweek) \(signed(route.weeklyProjectedGain[gameweek] ?? 0))")
                                .font(FottyTheme.typeCaption.weight(.semibold))
                                .foregroundStyle(FottyTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(FottyTheme.surfaceSubtle)
                                .clipShape(Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Text(route.hitCost == 0
                         ? "No points hit to recover"
                         : route.breakEvenGameweek.map { "Modeled hit break-even: GW\($0)" } ?? "The hit does not break even inside this horizon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(route.breakEvenGameweek == nil && route.hitCost > 0 ? FottyTheme.accentText : FottyTheme.textSecondary)
                    Button {
                        pendingScenarioRoute = route
                        scenarioName = route.name
                        isNamingScenario = true
                    } label: {
                        Label("Save scenario", systemImage: "bookmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Saves this modeled route locally for comparison. It does not change official FPL.")
                }
                .padding(12)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .alert("Save planning scenario", isPresented: $isNamingScenario) {
            TextField("Scenario name", text: $scenarioName)
            Button("Save") {
                if let route = pendingScenarioRoute {
                    viewModel.saveScenario(name: scenarioName, route: route, gameweek: startGameweek)
                }
                pendingScenarioRoute = nil
            }
            Button("Cancel", role: .cancel) {
                pendingScenarioRoute = nil
            }
        } message: {
            Text("Saved only on this device. Fotty will not submit transfers to official FPL.")
        }
    }

    @ViewBuilder
    private var savedScenariosCard: some View {
        if !viewModel.savedScenarios.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SAVED SCENARIOS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textTertiary)
                ForEach(viewModel.savedScenarios) { scenario in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(scenario.name)
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(FottyTheme.textPrimary)
                                Text("GW\(scenario.gameweek) • \(scenario.routeName) • \(scenario.modelVersion)")
                                    .font(.caption2)
                                    .foregroundStyle(FottyTheme.textTertiary)
                            }
                            Spacer()
                            Text(signed(scenario.projectedGain))
                                .font(.caption.weight(.black))
                                .foregroundStyle(scenario.projectedGain > 0 ? FottyTheme.success : FottyTheme.textSecondary)
                            Button(role: .destructive) {
                                viewModel.removeScenario(id: scenario.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(FottyPressButtonStyle())
                            .accessibilityLabel("Delete \(scenario.name)")
                        }
                        Text(scenario.transfers.isEmpty ? "Roll transfer" : scenario.transfers.joined(separator: " • "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FottyTheme.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: gameweekMinimumWidth), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(scenario.weeklyProjectedGain.keys.sorted(), id: \.self) { gameweek in
                                Text("GW\(gameweek) \(signed(scenario.weeklyProjectedGain[gameweek] ?? 0))")
                                    .font(FottyTheme.typeCaption.weight(.semibold))
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Text(scenario.downside)
                            .font(.caption2)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                    .padding(11)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(15)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var squadProjectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CURRENT SQUAD • \(selectedTargetGameweek.map { "GW\($0)" } ?? "NO UPCOMING WEEK")")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textTertiary)
                Spacer()
                Text(selectedGameweek == 0 ? "official/model blend" : "Fotty estimate")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selectedGameweek == 0 ? FottyTheme.accentText : FottyTheme.textSecondary)
            }

            ForEach(squadProjections.prefix(15)) { projection in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(projection.player.webName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                        Text("\(projection.player.positionName) • \(projection.player.formattedCost) • xMins \(projection.expectedMinutes[startGameweek + selectedGameweek] ?? 0) • \(projection.confidence.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                    Spacer()
                    Text((projection.gameweekPoints[startGameweek + selectedGameweek] ?? 0).formatted(.number.precision(.fractionLength(1))))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("pts")
                        .font(.caption2)
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var chipInventoryCard: some View {
        let definitions = viewModel.bootstrap?.chips ?? []
        let usages = viewModel.managerHistory?.chips
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("OFFICIAL CHIP WINDOWS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(FottyTheme.textTertiary)
                Spacer()
                Text(selectedTargetGameweek.map { "Planning GW\($0)" } ?? "No target week")
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textTertiary)
            }
            if definitions.isEmpty {
                Text("Chip definitions are not present in this FPL snapshot.")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
            } else {
                ForEach(definitions) { chip in
                    let availability = FPLChipAvailabilityPolicy.availability(chip: chip,
                        targetGameweek: selectedTargetGameweek, events: viewModel.bootstrap?.events ?? [],
                        usages: usages, managerStartedEvent: viewModel.managerSummary?.startedEvent)
                    VStack(alignment: .leading, spacing: 3) {
                     HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chipName(chip.name))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            Text("GW\(chip.startEvent)–GW\(chip.stopEvent) • allocation \(chip.number)")
                                .font(.caption2)
                                .foregroundStyle(FottyTheme.textTertiary)
                        }
                        Spacer()
                        Text(availability.status.rawValue)
                            .font(.fottyScaled(size: 9, weight: .black))
                            .foregroundStyle(availability.status == .eligible ? FottyTheme.success : FottyTheme.textTertiary)
                     }
                     Text(availability.explanation)
                        .font(.caption2)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var assumptionsCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Planning assumptions", systemImage: "info.circle.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(FottyTheme.accentText)
            Text(viewModel.freeTransferEstimate?.explanation ?? "Fotty could not estimate free transfers from the public history.")
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)
            Text("Selling prices and pending transfers may be unavailable. Confirm cost and deadline in official FPL.")
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)
            Text("Expected minutes are estimates, not confirmed lineups.")
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var startGameweek: Int {
        viewModel.planningGameweek
    }

    private var planningWeeks: [Int] {
        FPLPlanningBounds.gameweeks(start: startGameweek, horizon: horizon, events: viewModel.bootstrap?.events ?? [])
    }

    private var selectedTargetGameweek: Int? {
        planningWeeks.indices.contains(selectedGameweek) ? planningWeeks[selectedGameweek] : nil
    }

    private var squadProjections: [FPLPlayerProjection] {
        guard !planningWeeks.isEmpty else { return [] }
        let ids = Set(viewModel.picks?.picks.map(\.element) ?? [])
        return (viewModel.bootstrap?.elements ?? [])
            .filter { ids.contains($0.id) }
            .map {
                FPLProjectionEngine.project(
                    player: $0,
                    fixtures: viewModel.fixtures,
                    startGameweek: startGameweek,
                    horizon: planningWeeks.count
                )
            }
            .sorted {
                ($0.gameweekPoints[startGameweek + selectedGameweek] ?? 0)
                    > ($1.gameweekPoints[startGameweek + selectedGameweek] ?? 0)
            }
    }

    private func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(1)))
    }

    private func signedCost(_ value: Int) -> String {
        let amount = Double(abs(value)) / 10
        return "\(value > 0 ? "+" : "-")£\(amount.formatted(.number.precision(.fractionLength(1))))m"
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: "")
    }

    private func chipName(_ raw: String) -> String {
        switch normalized(raw) {
        case "wildcard": return "Wildcard"
        case "freehit": return "Free Hit"
        case "bboost": return "Bench Boost"
        case "3xc": return "Triple Captain"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
