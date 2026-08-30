import SwiftUI

public struct FPLWildcardGeneratorView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @State private var selectedProfile: FPLOptimizedSquad.Profile = .balanced
    @State private var generatedSquads: [FPLOptimizedSquad] = []
    @State private var lockedPlayerIDs = Set<Int>()
    @State private var excludedPlayerIDs = Set<Int>()
    @State private var isShowingConstraints = false
    @State private var saveMessage: String?

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 14) {
            headerCard
            if let squad = selectedSquad {
                summaryCard(squad)
                playerList(squad)
            } else {
                emptyCard
            }
        }
        .onAppear {
            generatedSquads = viewModel.optimizedSquads
        }
        .onChange(of: viewModel.optimizedSquads.count) { _, _ in
            if lockedPlayerIDs.isEmpty && excludedPlayerIDs.isEmpty {
                generatedSquads = viewModel.optimizedSquads
            }
        }
        .sheet(isPresented: $isShowingConstraints) {
            FPLSquadConstraintsSheet(
                scores: viewModel.playerScores,
                lockedPlayerIDs: $lockedPlayerIDs,
                excludedPlayerIDs: $excludedPlayerIDs
            ) {
                regenerate()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Legal squad optimizer", systemImage: "wand.and.rays")
                    .font(.headline.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
                Spacer()
                Text("LOCAL DRAFT · MODELED")
                    .font(.fottyScaled(size: 8, weight: .black))
                    .foregroundStyle(FottyTheme.accentText)
            }

            Text("Generates safe, balanced and aggressive 15-player drafts within the official position, club and budget rules. It optimizes Fotty's \(viewModel.coachProfile.planningHorizon)-gameweek model; it is not an expected-points guarantee.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                ForEach(FPLOptimizedSquad.Profile.allCases) { profile in
                    let selected = profile == selectedProfile
                    Button(profile.rawValue) { selectedProfile = profile }
                        .font(.caption.weight(.black))
                        .foregroundStyle(selected ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? FottyTheme.accent : FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Button {
                    isShowingConstraints = true
                } label: {
                    Label("Locks \(lockedPlayerIDs.count) • Exclusions \(excludedPlayerIDs.count)", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(FottyTheme.accentText)

                Button("Regenerate") { regenerate() }
                    .buttonStyle(.borderedProminent)
                    .tint(FottyTheme.accentText)
            }
            .font(.caption.weight(.bold))
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryCard(_ squad: FPLOptimizedSquad) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(squad.profile.rawValue.uppercased()) DRAFT")
                        .font(.caption.weight(.black))
                        .foregroundStyle(FottyTheme.accentText)
                    Text("£\((Double(squad.cost) / 10).formatted(.number.precision(.fractionLength(1))))m • \(squad.projectedPoints.formatted(.number.precision(.fractionLength(1)))) modeled XI points")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("Projection covers the selected planning horizon, including the captain multiplier.")
                        .font(.caption2)
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                Spacer()
                Label(squad.validation.isValid ? "LEGAL" : "INVALID", systemImage: squad.validation.isValid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.fottyScaled(size: 9, weight: .black))
                    .foregroundStyle(squad.validation.isValid ? FottyTheme.success : FottyTheme.error)
            }

            Text(squad.explanation)
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)

            Button {
                let saved = viewModel.updateUserSquad(picks: squad.picks)
                saveMessage = saved
                    ? "Saved as a manager-and-season local Fotty draft. Official FPL was not changed."
                    : (viewModel.draftErrorMessage ?? "The draft could not be saved.")
            } label: {
                Label("Save as Local Draft", systemImage: "square.and.arrow.down.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .background(FottyTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!squad.validation.isValid)

            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(squad.validation.isValid ? FottyTheme.success : FottyTheme.error)
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerList(_ squad: FPLOptimizedSquad) -> some View {
        let playerByID = Dictionary(uniqueKeysWithValues: viewModel.playerScores.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: 9) {
            Text("STARTING XI")
                .font(.caption.weight(.black))
                .foregroundStyle(FottyTheme.textTertiary)
            ForEach(squad.picks.filter { $0.position <= 11 }.sorted { $0.position < $1.position }, id: \.element) { pick in
                if let score = playerByID[pick.element] { playerRow(score, pick: pick) }
            }
            Text("BENCH")
                .font(.caption.weight(.black))
                .foregroundStyle(FottyTheme.textTertiary)
                .padding(.top, 6)
            ForEach(squad.picks.filter { $0.position > 11 }.sorted { $0.position < $1.position }, id: \.element) { pick in
                if let score = playerByID[pick.element] { playerRow(score, pick: pick) }
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerRow(_ score: PlayerScore, pick: FPLPick) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(score.player.webName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    if pick.isCaptain { marker("C") }
                    if pick.isViceCaptain { marker("VC") }
                    if lockedPlayerIDs.contains(score.id) {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(FottyTheme.accentText)
                    }
                }
                Text("\(score.team.shortName) • \(score.player.positionName) • \(score.player.formattedCost)")
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textTertiary)
            }
            Spacer()
            Text(score.player.officialExpectedPointsNext.map { "FPL estimate \($0.formatted(.number.precision(.fractionLength(1))))" } ?? "Modeled estimate")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .padding(9)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func marker(_ text: String) -> some View {
        Text(text)
            .font(.fottyScaled(size: 8, weight: .black))
            .foregroundStyle(FottyTheme.textOnAccent)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(FottyTheme.accent)
            .clipShape(Capsule())
    }

    private var emptyCard: some View {
        VStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(FottyTheme.accentText)
            Text("No legal draft was found")
                .font(.headline.weight(.black))
                .foregroundStyle(FottyTheme.textPrimary)
            Text("Relax one or more player locks/exclusions or refresh the official player pool.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var selectedSquad: FPLOptimizedSquad? {
        generatedSquads.first { $0.profile == selectedProfile }
    }

    private func regenerate() {
        guard let bootstrap = viewModel.bootstrap else { return }
        let start = viewModel.gameweekPhase == .planning
            ? (viewModel.currentGameweek?.id ?? viewModel.nextGameweek?.id ?? 1)
            : (viewModel.nextGameweek?.id ?? ((viewModel.currentGameweek?.id ?? 0) + 1))
        let budget = viewModel.managerSummary?.lastDeadlineValue
            ?? bootstrap.gameSettings?.squadTotalSpend
            ?? 1_000
        generatedSquads = FPLSquadOptimizer.generate(
            scores: viewModel.playerScores,
            fixtures: viewModel.fixtures,
            elementTypes: bootstrap.elementTypes,
            settings: bootstrap.gameSettings,
            startGameweek: start,
            horizon: viewModel.coachProfile.planningHorizon,
            budget: budget,
            lockedPlayerIDs: lockedPlayerIDs,
            excludedPlayerIDs: excludedPlayerIDs
        )
        saveMessage = nil
    }
}

private struct FPLSquadConstraintsSheet: View {
    let scores: [PlayerScore]
    @Binding var lockedPlayerIDs: Set<Int>
    @Binding var excludedPlayerIDs: Set<Int>
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [PlayerScore] {
        if searchText.isEmpty { return scores }
        return scores.filter {
            $0.player.webName.localizedCaseInsensitiveContains(searchText)
                || $0.team.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { score in
                HStack {
                    VStack(alignment: .leading) {
                        Text(score.player.webName).font(.subheadline.weight(.bold))
                        Text("\(score.team.shortName) • \(score.player.positionName) • \(score.player.formattedCost)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        toggleLock(score.id)
                    } label: {
                        Image(systemName: lockedPlayerIDs.contains(score.id) ? "lock.fill" : "lock.open")
                    }
                    .buttonStyle(.borderless)
                    .tint(FottyTheme.accentText)
                    Button {
                        toggleExclusion(score.id)
                    } label: {
                        Image(systemName: excludedPlayerIDs.contains(score.id) ? "nosign" : "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .tint(FottyTheme.error)
                }
            }
            .searchable(text: $searchText, prompt: "Search players")
            .navigationTitle("Draft Constraints")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        lockedPlayerIDs.removeAll()
                        excludedPlayerIDs.removeAll()
                    }
                }
            }
        }
    }

    private func toggleLock(_ id: Int) {
        excludedPlayerIDs.remove(id)
        if lockedPlayerIDs.contains(id) { lockedPlayerIDs.remove(id) } else { lockedPlayerIDs.insert(id) }
    }

    private func toggleExclusion(_ id: Int) {
        lockedPlayerIDs.remove(id)
        if excludedPlayerIDs.contains(id) { excludedPlayerIDs.remove(id) } else { excludedPlayerIDs.insert(id) }
    }
}
