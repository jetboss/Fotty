import SwiftUI

public struct FPLTransferHubView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    
    // Multi-Transfer Workspace State
    @State private var stagedPicks: [FPLPick] = []
    @State private var transferredOutIds: Set<Int> = []
    @State private var activePickerContext: PlayerPickerContext? = nil
    @State private var showSuccessBanner: Bool = false
    
    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }
    
    private var allScores: [PlayerScore] {
        viewModel.playerScores
    }
    
    private var allTeams: [FPLTeam] {
        viewModel.bootstrap?.teams ?? []
    }
    
    private func getScore(for elementId: Int) -> PlayerScore? {
        allScores.first(where: { $0.player.id == elementId })
    }
    
    // Budget Calculations
    private var originalPicksByElement: [Int: FPLPick] {
        Dictionary(uniqueKeysWithValues: (viewModel.picks?.picks ?? []).map { ($0.element, $0) })
    }

    private var originalTransferBudgetTenths: Int {
        let bank = viewModel.planningBank
        let sellingValue = (viewModel.picks?.picks ?? []).reduce(0) { sum, pick in
            sum + (pick.sellingPrice ?? getScore(for: pick.element)?.player.nowCost ?? 0)
        }
        return sellingValue + bank
    }

    private var currentSquadCostTenths: Int {
        stagedPicks.reduce(0) { sum, pick in
            if let original = originalPicksByElement[pick.element] {
                return sum + (original.sellingPrice ?? getScore(for: pick.element)?.player.nowCost ?? 0)
            }
            return sum + (getScore(for: pick.element)?.player.nowCost ?? 0)
        }
    }
    
    private var bankMillion: Double {
        Double(originalTransferBudgetTenths - currentSquadCostTenths) / 10.0
    }
    
    private var isOverBudget: Bool {
        currentSquadCostTenths > originalTransferBudgetTenths
    }
    
    // Club Limit Enforcement (Max 3 per club)
    private var clubViolations: [String] {
        var countMap: [Int: Int] = [:]
        for pick in stagedPicks {
            if let score = getScore(for: pick.element) {
                countMap[score.player.team, default: 0] += 1
            }
        }
        var violations: [String] = []
        for (teamId, count) in countMap where count > 3 {
            if let t = allTeams.first(where: { $0.id == teamId }) {
                violations.append("\(t.shortName) (\(count)/3)")
            }
        }
        return violations
    }
    
    // Transfers Count & Point Cost
    private var transfersCount: Int {
        guard let original = viewModel.picks?.picks else { return 0 }
        let origIds = Set(original.map(\.element))
        let currentIds = Set(stagedPicks.map(\.element))
        return origIds.subtracting(currentIds).count
    }
    
    private var transferHitCost: Int {
        FPLTransferRules.estimatedHitCost(
            transferCount: transfersCount,
            assumedFreeTransfers: viewModel.freeTransferEstimate?.count ?? 1,
            gameweek: viewModel.currentGameweek
        )
    }

    private var stagedValidation: FPLSquadValidationReport? {
        guard let bootstrap = viewModel.bootstrap, stagedPicks.count == 15 else { return nil }
        return FPLSquadValidator.validate(
            picks: stagedPicks,
            players: bootstrap.elements,
            elementTypes: bootstrap.elementTypes,
            gameSettings: bootstrap.gameSettings,
            budgetLimit: originalTransferBudgetTenths
        )
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Workspace Header & Multi-Transfer Action Bar
            transferWorkspaceHeader

            FPLTransferLabView(viewModel: viewModel, onStageRoute: stageRoute)
            
            // Success Notification Banner
            if showSuccessBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FottyTheme.success)
                    
                    Text("Local transfer draft saved. Confirm it in official FPL.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    
                    Spacer()
                }
                .padding(12)
                .background(FottyTheme.success.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FottyTheme.success.opacity(0.4), lineWidth: 1))
            }
            
            // Interactive 15-Man Transfer Roster Canvas
            stagedSquadCanvas
            
            // AI Recommended Transfers with 1-Tap Execution
            aiRecommendationsSection
        }
        .onAppear {
            if stagedPicks.isEmpty, let picks = viewModel.picks?.picks {
                stagedPicks = picks
            }
        }
        .onChange(of: viewModel.picks?.picks) { _, newPicks in
            if let p = newPicks {
                stagedPicks = p
                transferredOutIds.removeAll()
            }
        }
        .sheet(item: $activePickerContext) { ctx in
            FPLPlayerPickerSheet(
                positionType: ctx.elementType,
                currentElementId: ctx.currentElementId,
                scores: allScores,
                teams: allTeams
            ) { selectedScore in
                commitReplacement(for: ctx.position, with: selectedScore.player.id)
                return nil // Staged only; the Save action validates the complete draft.
            }
        }
    }
    
    // MARK: - Transfer Workspace Header & Live Validation
    
    private var transferWorkspaceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            FPLSquadSourceNotice(viewModel: viewModel)
            if let error = viewModel.draftErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.error)
            }
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("Local Transfer Draft")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                
                Spacer()
                
                if transfersCount > 0 {
                    Button {
                        HapticManager.impact(.light)
                        if let orig = viewModel.picks?.picks {
                            stagedPicks = orig
                            transferredOutIds.removeAll()
                        }
                    } label: {
                        Text("Reset All")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(FottyTheme.error)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(FottyTheme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("Fotty does not change your official FPL squad. Point cost uses the public-history estimate of \(viewModel.freeTransferEstimate?.count ?? 1) free transfer(s); verify that count and selling prices in official FPL.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)

            // Draft status bar (changes, estimated point cost, estimated bank)
            HStack(spacing: 12) {
                // Transfers Made
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRANSFERS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    
                    Text("\(transfersCount) Drafted")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(transfersCount > 0 ? FottyTheme.accentText : FottyTheme.textPrimary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Point Cost / Hit
                VStack(alignment: .leading, spacing: 2) {
                    Text("EST. POINT COST")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    
                    Text(transferHitCost > 0 ? "-\(transferHitCost) pts" : "0 pts (Free)")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(transferHitCost > 0 ? FottyTheme.error : FottyTheme.success)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Bank Remaining
                VStack(alignment: .leading, spacing: 2) {
                    Text("EST. BANK")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    
                    Text("£\(String(format: "%.1f", bankMillion))m")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(isOverBudget ? FottyTheme.error : FottyTheme.success)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Warnings (Over budget or Club limit exceeded)
            if isOverBudget {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(FottyTheme.error)
                    
                    Text("Over budget by £\(String(format: "%.1f", abs(bankMillion)))m using current prices and available selling values.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FottyTheme.error)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.error.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !clubViolations.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(FottyTheme.error)
                    
                    Text("Club Limit Exceeded: Max 3 players allowed per team — \(clubViolations.joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FottyTheme.error)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.error.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let issue = stagedValidation?.issues.first(where: { $0.severity == .error }) {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FottyTheme.error)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FottyTheme.error.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Local draft actions
            HStack(spacing: 10) {
                if !transferredOutIds.isEmpty {
                    Button {
                        HapticManager.impact(.medium)
                        smartAutoCompleteOpenSlots()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text("Auto-Fill Open Slots")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FottyTheme.accent, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                
                if transfersCount > 0 {
                    Button {
                        HapticManager.impact(.heavy)
                        applyAllTransfersToSquad()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 14, weight: .black))
                            
                            Text("Save \(transfersCount) Changes as Draft")
                                .font(.system(size: 13, weight: .black))
                        }
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(stagedValidation?.isValid == true ? FottyTheme.accent : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: isOverBudget ? .clear : FottyTheme.accent.opacity(0.4), radius: 6, y: 3)
                    }
                    .disabled(stagedValidation?.isValid != true)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Staged Squad Roster Canvas
    
    private var stagedSquadCanvas: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR SQUAD (TAP '✖' TO SELL OR QUEUE TRANSFERS)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(FottyTheme.textSecondary)
                
                Spacer()
                
                Text("\(stagedPicks.count) / 15 Players")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
            }
            
            // Group by Position: GKP (1), DEF (2), MID (3), FWD (4)
            VStack(spacing: 8) {
                positionSectionRow(title: "Goalkeepers", elementType: 1)
                positionSectionRow(title: "Defenders", elementType: 2)
                positionSectionRow(title: "Midfielders", elementType: 3)
                positionSectionRow(title: "Forwards", elementType: 4)
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private func positionSectionRow(title: String, elementType: Int) -> some View {
        let positionPicks = stagedPicks.filter { pick in
            getScore(for: pick.element)?.player.elementType == elementType
        }
        
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(FottyTheme.textTertiary)
                .padding(.leading, 4)
            
            ForEach(positionPicks) { pick in
                transferPlayerRow(pick: pick, elementType: elementType)
            }
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func transferPlayerRow(pick: FPLPick, elementType: Int) -> some View {
        let isTransferredOut = transferredOutIds.contains(pick.element)
        let isGK = elementType == 1
        
        if let score = getScore(for: pick.element) {
            Button {
                HapticManager.impact(.light)
                activePickerContext = PlayerPickerContext(
                    position: pick.position,
                    elementType: elementType,
                    currentElementId: pick.element
                )
            } label: {
                HStack(spacing: 12) {
                    // Official FPL CDN Shirt
                    FPLOfficialShirtImageView(
                        teamCode: score.team.code,
                        isGoalkeeper: isGK,
                        size: 38
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(score.player.webName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isTransferredOut ? FottyTheme.textTertiary : FottyTheme.textPrimary)
                                .strikethrough(isTransferredOut)
                            
                            if pick.position > 11 {
                                Text("BENCH")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(FottyTheme.textTertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(FottyTheme.surface)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Text("\(score.team.name) • \(score.player.formattedCost)")
                            
                            if let nextFixture = score.upcomingFixtures.first {
                                Text("•")
                                let opp = nextFixture.opponent.shortName
                                let loc = nextFixture.isHome ? "(H)" : "(A)"
                                Text("vs \(opp) \(loc)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(nextFixture.difficulty <= 2 ? FottyTheme.success : (nextFixture.difficulty >= 4 ? FottyTheme.accentText : FottyTheme.textSecondary))
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FottyTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Quick Status Indicator / Chevron
                    HStack(spacing: 6) {
                        if isTransferredOut {
                            Text("Pick In")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(FottyTheme.success)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(FottyTheme.success)
                        } else {
                            Text(score.player.formattedCost)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(FottyTheme.accentText)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(FottyTheme.textTertiary)
                        }
                    }
                }
                .padding(12)
                .background(isTransferredOut ? FottyTheme.error.opacity(0.08) : FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isTransferredOut ? FottyTheme.error.opacity(0.3) : FottyTheme.border.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Fotty model transfer shortlist
    
    private var aiRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("Fotty Model Shortlist")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                
                Spacer()
                
                Text("MODEL RATING")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
            }
            
            if viewModel.transferRecs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(FottyTheme.success)
                    
                    Text("No candidate currently clears Fotty's rating threshold. This does not prove the squad is optimal.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(viewModel.transferRecs) { rec in
                    aiTransferCard(rec)
                }
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private func aiTransferCard(_ rec: TransferRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // OUT vs IN Matchup Cards
            HStack(spacing: 10) {
                // OUT Player
                HStack(spacing: 8) {
                    FPLOfficialShirtImageView(
                        teamCode: rec.playerOut.team.code,
                        isGoalkeeper: rec.playerOut.player.elementType == 1,
                        size: 32
                    )
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OUT")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(FottyTheme.error)
                        Text(rec.playerOut.player.webName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .lineLimit(1)
                        Text(rec.playerOut.player.formattedCost)
                            .font(.system(size: 10))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.error.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FottyTheme.textTertiary)
                
                // IN Player
                HStack(spacing: 8) {
                    FPLOfficialShirtImageView(
                        teamCode: rec.playerIn.team.code,
                        isGoalkeeper: rec.playerIn.player.elementType == 1,
                        size: 32
                    )
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("IN")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(FottyTheme.success)
                        Text(rec.playerIn.player.webName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .lineLimit(1)
                        Text(rec.playerIn.player.formattedCost)
                            .font(.system(size: 10))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.success.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Uplift & Reason
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("+\(String(format: "%.1f", rec.scoreUplift)) rating difference")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                }
                
                Spacer()
                
                let costDiff = rec.costDelta
                Text(costDiff > 0 ? "Bank: +\(String(format: "£%.1fm", Double(costDiff)/10.0))" : (costDiff < 0 ? "Cost: \(String(format: "£%.1fm", Double(abs(costDiff))/10.0))" : "Same Price"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            
            Text(rec.reason)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FottyTheme.textSecondary)
            
            // Add a single modeled move to the local draft
            Button {
                HapticManager.impact(.medium)
                applySingleRecommendation(rec)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("Add This Move to Draft")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(FottyTheme.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(FottyTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Actions
    
    private func commitReplacement(for position: Int, with newElementId: Int) {
        guard let idx = stagedPicks.firstIndex(where: { $0.position == position }) else { return }
        let oldPick = stagedPicks[idx]
        stagedPicks[idx] = FPLPick(
            element: newElementId,
            position: oldPick.position,
            multiplier: oldPick.multiplier,
            isCaptain: oldPick.isCaptain,
            isViceCaptain: oldPick.isViceCaptain
        )
        transferredOutIds.remove(oldPick.element)
    }
    
    private func applyAllTransfersToSquad() {
        guard viewModel.updateUserSquad(picks: stagedPicks) else { return }
        transferredOutIds.removeAll()
        withAnimation {
            showSuccessBanner = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation {
                    showSuccessBanner = false
                }
            }
        }
    }

    private func stageRoute(_ route: FPLDraftRoute) {
        guard let original = viewModel.picks?.picks else { return }
        if route.transfers.isEmpty {
            stagedPicks = original
            transferredOutIds.removeAll()
            return
        }

        var staged = original
        var replaced = Set<Int>()
        for transfer in route.transfers {
            guard let index = staged.firstIndex(where: { $0.element == transfer.playerOut.player.id }) else { continue }
            let outgoing = staged[index]
            guard !staged.contains(where: { $0.element == transfer.playerIn.player.id }) else { continue }
            staged[index] = FPLPick(
                element: transfer.playerIn.player.id,
                position: outgoing.position,
                multiplier: outgoing.multiplier,
                isCaptain: outgoing.isCaptain,
                isViceCaptain: outgoing.isViceCaptain,
                elementType: transfer.playerIn.player.elementType
            )
            replaced.insert(outgoing.element)
        }
        stagedPicks = staged
        transferredOutIds = replaced
    }
    
    private func applySingleRecommendation(_ rec: TransferRecommendation) {
        showSuccessBanner = false
        guard viewModel.replacePlayer(oldElementId: rec.playerOut.player.id, newScore: rec.playerIn) else { return }
        if let updated = viewModel.picks?.picks {
            stagedPicks = updated
        }
        withAnimation {
            showSuccessBanner = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation {
                    showSuccessBanner = false
                }
            }
        }
    }
    
    private func smartAutoCompleteOpenSlots() {
        let openPositions = stagedPicks.filter { transferredOutIds.contains($0.element) }
        guard !openPositions.isEmpty else { return }
        
        let currentSquad = stagedPicks.filter { !transferredOutIds.contains($0.element) }
        var usedIds = Set(currentSquad.map(\.element))
        
        var clubCounts: [Int: Int] = [:]
        for pick in currentSquad {
            if let score = getScore(for: pick.element) {
                clubCounts[score.player.team, default: 0] += 1
            }
        }
        
        var currentTotalCost = currentSquad.reduce(0) { sum, pick in
            sum + (getScore(for: pick.element)?.player.nowCost ?? 0)
        }
        
        var slotIndex = 0
        for pick in openPositions {
            slotIndex += 1
            guard let oldScore = getScore(for: pick.element) else { continue }
            let neededType = oldScore.player.elementType
            let remainingSlots = openPositions.count - slotIndex
            let maxAllowedForThisPlayer = (1000 - currentTotalCost) - (remainingSlots * 40)
            
            let candidates = allScores.filter { score in
                score.player.elementType == neededType &&
                !usedIds.contains(score.player.id) &&
                (clubCounts[score.player.team] ?? 0) < 3 &&
                score.player.nowCost <= maxAllowedForThisPlayer
            }.sorted { $0.compositeScore > $1.compositeScore }
            
            if let best = candidates.first ?? allScores.filter({ $0.player.elementType == neededType && !usedIds.contains($0.player.id) && (clubCounts[$0.player.team] ?? 0) < 3 }).sorted(by: { $0.compositeScore > $1.compositeScore }).first {
                usedIds.insert(best.player.id)
                clubCounts[best.player.team, default: 0] += 1
                currentTotalCost += best.player.nowCost
                
                if let idx = stagedPicks.firstIndex(where: { $0.position == pick.position }) {
                    stagedPicks[idx] = FPLPick(
                        element: best.player.id,
                        position: pick.position,
                        multiplier: pick.multiplier,
                        isCaptain: pick.isCaptain,
                        isViceCaptain: pick.isViceCaptain
                    )
                }
            }
        }
        transferredOutIds.removeAll()
    }
}
