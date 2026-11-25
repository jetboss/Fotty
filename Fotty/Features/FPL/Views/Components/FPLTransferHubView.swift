import SwiftUI

public struct FPLTransferHubView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var staging: FPLTransferStagingState?
    @State private var stagingMessage: String?
    @State private var activePickerContext: PlayerPickerContext? = nil
    @State private var showSuccessBanner: Bool = false
    private var transferLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }
    
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

    private var stagedPicks: [FPLPick] { staging?.picks ?? [] }

    private var sourceBaseline: FPLTransferStagingBaseline? {
        viewModel.transferStagingBaseline
    }

    private var planContext: FPLTransferPlanContext? {
        guard let bootstrap = viewModel.bootstrap, let staging else { return nil }
        return FPLTransferPlanContext(picks: staging.picks, players: bootstrap.elements,
                                      elementTypes: bootstrap.elementTypes, gameSettings: bootstrap.gameSettings,
                                      budgetLimit: staging.baseline.budgetLimit)
    }

    private var canSaveStaging: Bool {
        sourceBaseline != nil && staging?.hasConflict == false
            && staging?.baseline.budgetLimit != nil && stagedValidation?.isValid == true
    }
    
    // Budget Calculations
    private var originalPicksByElement: [Int: FPLPick] {
        Dictionary((staging?.baseline.picks ?? []).map { ($0.element, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var originalTransferBudgetTenths: Int {
        staging?.baseline.budgetLimit ?? 0
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
        staging?.baseline.budgetLimit != nil && currentSquadCostTenths > originalTransferBudgetTenths
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
        guard let original = staging?.baseline.picks else { return 0 }
        let origIds = Set(original.map(\.element))
        let currentIds = Set(stagedPicks.map(\.element))
        return origIds.subtracting(currentIds).count
    }
    
    private var transferHitCost: Int? {
        guard let freeTransfers = viewModel.freeTransferEstimate else { return nil }
        return FPLTransferRules.estimatedHitCost(
            transferCount: transfersCount,
            assumedFreeTransfers: freeTransfers.count,
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
            budgetLimit: staging?.baseline.budgetLimit
        )
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Workspace Header & Multi-Transfer Action Bar
            transferWorkspaceHeader

            FPLTransferLabView(viewModel: viewModel, onStageRoute: stageRoute)
                .disabled(staging?.hasConflict != false || sourceBaseline == nil)
            
            // Success Notification Banner
            if showSuccessBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.fottyScaled(size: 16, weight: .bold))
                        .foregroundStyle(FottyTheme.success)
                    
                    Text("Local transfer draft saved. Confirm it in official FPL.")
                        .font(.fottyScaled(size: 13, weight: .bold))
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
                .disabled(staging?.hasConflict != false || sourceBaseline == nil)
            
            // AI Recommended Transfers with 1-Tap Execution
            aiRecommendationsSection
                .disabled(staging?.hasConflict != false || sourceBaseline == nil)
        }
        .onAppear { synchronizeStaging() }
        .onChange(of: sourceBaseline) { _, _ in synchronizeStaging() }
        .onReceive(NotificationCenter.default.publisher(for: FottyPrivateBackupService.restoredNotification)) { _ in
            // Restore explicitly replaces local plans, including when the same
            // manager is reconnected and its public ID does not change.
            staging = nil
            activePickerContext = nil
            showSuccessBanner = false
            stagingMessage = nil
        }
        .onChange(of: viewModel.managerId) { _, _ in
            staging = nil
            activePickerContext = nil
            showSuccessBanner = false
            stagingMessage = nil
            synchronizeStaging()
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
            if staging?.hasConflict == true {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Squad data changed", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text("Your draft was kept after the squad changed. Review it or reset to the latest squad; either choice can be undone.")
                        .font(.caption)
                    ViewThatFits(in: .horizontal) {
                        HStack { conflictActions }
                        VStack(alignment: .leading) { conflictActions }
                    }
                }
                .foregroundStyle(FottyTheme.textPrimary)
                .padding(12)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let stagingMessage {
                Label(stagingMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            if let error = viewModel.draftErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.error)
            }
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.fottyScaled(size: 18, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("Local Transfer Draft")
                        .font(.fottyScaled(size: 18, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                
                Spacer()
                
            }

            HStack {
                if staging?.canUndo == true {
                    Button("Undo", systemImage: "arrow.uturn.backward") { editStaging { $0.undo() } }
                        .accessibilityLabel("Undo last staging change")
                }
                if staging?.hasChanges == true {
                    Button("Reset", systemImage: "arrow.counterclockwise") { editStaging { $0.reset() } }
                        .accessibilityLabel("Reset staging to the latest displayed squad")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            
            Text("Saved on this device. \(viewModel.freeTransferEstimate.map { "Estimated free transfers: \($0.count)." } ?? "Free transfers are unknown.") Confirm cost and affordability in official FPL.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)

            // Draft status bar (changes, estimated point cost, estimated bank)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 12) {
                // Transfers Made
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRANSFERS")
                        .font(.fottyScaled(size: 9, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    
                    Text("\(transfersCount) Drafted")
                        .font(.fottyScaled(size: 16, weight: .black))
                        .foregroundStyle(transfersCount > 0 ? FottyTheme.accentText : FottyTheme.textPrimary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Point Cost / Hit
                VStack(alignment: .leading, spacing: 2) {
                    Text("EST. POINT COST")
                        .font(.fottyScaled(size: 9, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    
                    Text(transferHitCost.map { $0 > 0 ? "-\($0) pts" : "0 pts est." } ?? "Unknown")
                        .font(.fottyScaled(size: 16, weight: .black))
                        .foregroundStyle((transferHitCost ?? 0) > 0 ? FottyTheme.error : FottyTheme.textPrimary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Bank Remaining
                VStack(alignment: .leading, spacing: 2) {
                    Text("EST. BANK")
                        .font(.fottyScaled(size: 9, weight: .black))
                        .foregroundStyle(FottyTheme.textTertiary)
                    
                    Text(staging?.baseline.budgetLimit == nil ? "Unknown" : "£\(String(format: "%.1f", bankMillion))m")
                        .font(.fottyScaled(size: 16, weight: .black))
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
                        .font(.fottyScaled(size: 12))
                        .foregroundStyle(FottyTheme.error)
                    
                    Text("Over budget by £\(String(format: "%.1f", abs(bankMillion)))m using current prices and available selling values.")
                        .font(.fottyScaled(size: 11, weight: .medium))
                        .foregroundStyle(FottyTheme.error)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.error.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !clubViolations.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.fottyScaled(size: 12))
                        .foregroundStyle(FottyTheme.error)
                    
                    Text("Club limit exceeded: maximum 3 players — \(clubViolations.joined(separator: ", "))")
                        .font(.fottyScaled(size: 11, weight: .medium))
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
                if staging?.hasChanges == true {
                    Button {
                        HapticManager.impact(.heavy)
                        applyAllTransfersToSquad()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.fottyScaled(size: 14, weight: .black))
                            
                            Text("Save Local Squad Draft")
                                .font(.fottyScaled(size: 13, weight: .black))
                        }
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSaveStaging ? FottyTheme.accent : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: isOverBudget ? .clear : FottyTheme.accent.opacity(0.4), radius: 6, y: 3)
                    }
                    .disabled(!canSaveStaging)
                    .buttonStyle(FottyPressButtonStyle(cornerRadius: 12))
                }
            }
            if staging?.baseline.budgetLimit == nil {
                Text("Load current manager data to confirm your budget.")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
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
                Text("STAGED SQUAD · TAP A PLAYER TO REPLACE")
                    .font(.fottyScaled(size: 11, weight: .black))
                    .foregroundStyle(FottyTheme.textSecondary)
                
                Spacer()
                
                Text("\(stagedPicks.count) / 15 Players")
                    .font(.fottyScaled(size: 11, weight: .bold))
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
                .font(.fottyScaled(size: 10, weight: .black))
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
                                .font(.fottyScaled(size: 14, weight: .bold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            
                            if pick.position > 11 {
                                Text("BENCH")
                                    .font(.fottyScaled(size: 8, weight: .black))
                                    .foregroundStyle(FottyTheme.textTertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(FottyTheme.surface)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        transferLayout {
                            TeamIdentityLabel(
                                teamName: score.team.name,
                                badgeURL: score.team.badgeURL,
                                badgeSize: 18,
                                font: .system(size: 11, weight: .medium),
                                foregroundColor: FottyTheme.textSecondary
                            )
                            Text("• \(score.player.formattedCost)")
                            
                            if let nextFixture = score.upcomingFixtures.first {
                                Text("•")
                                let opp = nextFixture.opponent.shortName
                                let loc = nextFixture.isHome ? "(H)" : "(A)"
                                Text("vs \(opp) \(loc)")
                                    .font(.fottyScaled(size: 11, weight: .bold))
                                    .foregroundStyle(nextFixture.difficulty <= 2 ? FottyTheme.success : (nextFixture.difficulty >= 4 ? FottyTheme.accentText : FottyTheme.textSecondary))
                            }
                        }
                        .font(.fottyScaled(size: 11, weight: .medium))
                        .foregroundStyle(FottyTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Quick Status Indicator / Chevron
                    HStack(spacing: 6) {
                        Text(score.player.formattedCost)
                            .font(.fottyScaled(size: 13, weight: .bold))
                            .foregroundStyle(FottyTheme.accentText)
                        Image(systemName: "chevron.right")
                            .font(.fottyScaled(size: 11, weight: .bold))
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                }
                .padding(12)
                .background(FottyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FottyTheme.border.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: 12))
        }
    }
    
    // MARK: - Fotty model transfer shortlist
    
    private var aiRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.fottyScaled(size: 16, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("Fotty Model Shortlist")
                        .font(.fottyScaled(size: 15, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                
                Spacer()
                
                Text("MODEL RATING")
                    .font(.fottyScaled(size: 9, weight: .black))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
            }
            
            if viewModel.transferRecs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.fottyScaled(size: 32))
                        .foregroundStyle(FottyTheme.success)
                    
                    Text("No candidate currently clears Fotty's rating threshold. This does not prove the squad is optimal.")
                        .font(.fottyScaled(size: 13, weight: .medium))
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
            transferLayout {
                // OUT Player
                HStack(spacing: 8) {
                    FPLOfficialShirtImageView(
                        teamCode: rec.playerOut.team.code,
                        isGoalkeeper: rec.playerOut.player.elementType == 1,
                        size: 32
                    )
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OUT")
                            .font(.fottyScaled(size: 8, weight: .black))
                            .foregroundStyle(FottyTheme.error)
                        Text(rec.playerOut.player.webName)
                            .font(.fottyScaled(size: 13, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text(rec.playerOut.player.formattedCost)
                            .font(.fottyScaled(size: 10))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.error.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.right")
                    .font(.fottyScaled(size: 12, weight: .bold))
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
                            .font(.fottyScaled(size: 8, weight: .black))
                            .foregroundStyle(FottyTheme.success)
                        Text(rec.playerIn.player.webName)
                            .font(.fottyScaled(size: 13, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text(rec.playerIn.player.formattedCost)
                            .font(.fottyScaled(size: 10))
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
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("+\(String(format: "%.1f", rec.scoreUplift)) rating difference")
                        .font(.fottyScaled(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                }
                
                Spacer()
                
                let costDiff = rec.costDelta
                Text(costDiff > 0 ? "Est. bank: +\(String(format: "£%.1fm", Double(costDiff)/10.0))" : (costDiff < 0 ? "Est. cost: \(String(format: "£%.1fm", Double(abs(costDiff))/10.0))" : "Same price"))
                    .font(.fottyScaled(size: 11, weight: .bold))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            
            Text(rec.reason)
                .font(.fottyScaled(size: 11, weight: .medium))
                .foregroundStyle(FottyTheme.textSecondary)
            
            // Add a single modeled move to the local draft
            Button {
                HapticManager.impact(.medium)
                applySingleRecommendation(rec)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("Add This Move to Draft")
                        .font(.fottyScaled(size: 12, weight: .black))
                }
                .foregroundStyle(FottyTheme.textOnAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 10)
                .background(FottyTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: 10))
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Actions

    @ViewBuilder
    private var conflictActions: some View {
        Button("Keep staged plan") { editStaging { $0.keepStagedPlan() } }
        Button("Reset to latest squad") { editStaging { $0.reset() } }
    }

    private func synchronizeStaging(resetAfterSave: Bool = false) {
        guard let managerID = viewModel.managerId, let sourceBaseline else { return }
        let season = FPLSeasonIdentifier.currentLabel()
        var state: FPLTransferStagingState
        if resetAfterSave {
            state = FPLTransferStagingState(managerID: managerID, season: season, baseline: sourceBaseline)
        } else if let existing = staging, existing.managerID == managerID, existing.season == season {
            state = existing
            state.synchronize(with: sourceBaseline)
        } else {
            state = viewModel.transferStagingStore.load(managerID: managerID, season: season, baseline: sourceBaseline)
        }
        staging = state
        viewModel.transferStagingStore.save(state)
    }

    private func editStaging(_ edit: (inout FPLTransferStagingState) -> Void) {
        guard var state = staging, state.managerID == viewModel.managerId,
              state.season == FPLSeasonIdentifier.currentLabel() else { return }
        edit(&state)
        staging = state
        viewModel.transferStagingStore.save(state)
        stagingMessage = nil
        showSuccessBanner = false
    }
    
    private func commitReplacement(for position: Int, with newElementId: Int) {
        guard let idx = stagedPicks.firstIndex(where: { $0.position == position }) else { return }
        let oldPick = stagedPicks[idx]
        var proposed = stagedPicks
        proposed[idx] = FPLPick(
            element: newElementId,
            position: oldPick.position,
            multiplier: oldPick.multiplier,
            isCaptain: oldPick.isCaptain,
            isViceCaptain: oldPick.isViceCaptain,
            elementType: getScore(for: newElementId)?.player.elementType
        )
        editStaging { $0.stage(proposed) }
    }
    
    private func applyAllTransfersToSquad() {
        synchronizeStaging()
        guard canSaveStaging, let staging, viewModel.saveTransferStaging(staging) else { return }
        synchronizeStaging(resetAfterSave: true)
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
        synchronizeStaging()
        guard staging?.hasConflict == false else { return }
        if route.transfers.isEmpty {
            editStaging { $0.reset() }
            return
        }
        guard let proposed = planContext?.validatedPicks(for: route.transfers) else {
            stagingMessage = "This route does not fit your current staged squad or available budget. Your staged moves are unchanged."
            return
        }
        editStaging { $0.stage(proposed) }
    }
    
    private func applySingleRecommendation(_ rec: TransferRecommendation) {
        synchronizeStaging()
        guard staging?.hasConflict == false else { return }
        guard let proposed = planContext?.validatedPicks(for: [rec]) else {
            stagingMessage = "This move does not fit your current staged squad or available budget. Your staged moves are unchanged."
            return
        }
        editStaging { $0.stage(proposed) }
    }
}
