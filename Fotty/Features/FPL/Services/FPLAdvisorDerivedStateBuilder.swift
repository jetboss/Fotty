import Foundation

/// Immutable input for the FPL workspace's derived planning and live state.
/// The view model remains the single mutable owner and applies the result.
struct FPLAdvisorDerivedStateInput {
    let bootstrap: FPLBootstrapResponse
    let fixtures: [FPLFixture]
    let phase: FPLGameweekPhase
    let currentGameweek: FPLGameweek?
    let planningStartGameweek: Int
    let displayedPicks: FPLManagerPicks?
    let publishedPicks: FPLManagerPicks?
    let publishedPicksGameweek: Int?
    let eventLive: FPLEventLiveResponse?
    let playerScores: [PlayerScore]
    let transferRecommendations: [TransferRecommendation]
    let freeTransfers: FPLFreeTransferEstimate?
    let managerHistory: FPLManagerHistoryResponse?
    let managerSummary: FPLManagerSummary?
    let coachProfile: FPLCoachProfile
    let isCustomDraft: Bool
    let draftBudgetLimit: Int?
    let savedDraftBudgetLimit: Int?
    let existingValidation: FPLSquadValidationReport?
}

struct FPLAdvisorDerivedState {
    let validation: FPLSquadValidationReport?
    let liveSquadSummary: FPLLiveSquadSummary?
    let planningRoutes: [FPLDraftRoute]
    let commandCenter: FPLCommandCenterState
    let optimizedSquads: [FPLOptimizedSquad]?
}

enum FPLAdvisorDerivedStateBuilder {
    static func build(
        input: FPLAdvisorDerivedStateInput,
        rebuildOptimizer: Bool
    ) -> FPLAdvisorDerivedState {
        let validation = input.displayedPicks.map {
            FPLSquadValidator.validate(
                picks: $0.picks,
                players: input.bootstrap.elements,
                elementTypes: input.bootstrap.elementTypes,
                gameSettings: input.bootstrap.gameSettings,
                budgetLimit: input.isCustomDraft
                    ? (input.savedDraftBudgetLimit ?? input.draftBudgetLimit)
                    : nil
            )
        } ?? input.existingValidation

        // Never combine an older fallback lineup or a local plan with this
        // game's live statistics, even while the draft is visible in Squad.
        let liveSummary: FPLLiveSquadSummary?
        if let gameweek = input.currentGameweek,
           input.publishedPicksGameweek == gameweek.id,
           let publishedPicks = input.publishedPicks,
           let eventLive = input.eventLive {
            liveSummary = FPLDecisionEngine.liveSquadSummary(
                gameweek: gameweek,
                picks: publishedPicks,
                live: eventLive,
                players: input.bootstrap.elements,
                teams: input.bootstrap.teams,
                fixtures: input.fixtures
            )
        } else {
            liveSummary = nil
        }

        let publishedBudget = input.publishedPicks.flatMap {
            FPLTransferPlanContext.budgetLimit(
                picks: $0.picks, players: input.bootstrap.elements,
                bank: $0.entryHistory?.bank
                    ?? (input.managerSummary?.currentEvent == input.publishedPicksGameweek ? input.managerSummary?.lastDeadlineBank : nil))
        }

        let routes = FPLPlannerEngine.routes(
            recommendations: input.transferRecommendations,
            fixtures: input.fixtures,
            startGameweek: input.planningStartGameweek,
            horizon: input.coachProfile.planningHorizon,
            freeTransfers: input.freeTransfers,
            gameweek: input.currentGameweek,
            context: input.displayedPicks.map { displayed in
                FPLTransferPlanContext(
                    picks: input.publishedPicks.map { published in
                        FPLTransferStagingBaseline.priced(displayed.picks, using: published.picks)
                    } ?? displayed.picks,
                    players: input.bootstrap.elements,
                    elementTypes: input.bootstrap.elementTypes,
                    gameSettings: input.bootstrap.gameSettings,
                    budgetLimit: publishedBudget
                        ?? (input.isCustomDraft ? (input.savedDraftBudgetLimit ?? input.draftBudgetLimit) : nil)
                )
            },
            events: input.bootstrap.events
        )
        let commandCenter = FPLDecisionEngine.commandCenter(
            phase: input.phase,
            gameweek: input.currentGameweek,
            picks: input.phase == .planning
                ? input.displayedPicks
                : (input.publishedPicksGameweek == input.currentGameweek?.id ? input.publishedPicks : nil),
            scores: input.playerScores,
            validation: validation,
            freeTransfers: input.freeTransfers,
            live: liveSummary,
            history: input.managerHistory
        )

        let optimizedSquads: [FPLOptimizedSquad]?
        if rebuildOptimizer {
            let budget = FPLWildcardBudget.resolve(publishedPicks: input.publishedPicks,
                publishedGameweek: input.publishedPicksGameweek, managerSummary: input.managerSummary,
                players: input.bootstrap.elements, savedDraftBudgetLimit: input.savedDraftBudgetLimit,
                draftBudgetLimit: input.draftBudgetLimit, settings: input.bootstrap.gameSettings).amount
            optimizedSquads = FPLSquadOptimizer.generate(
                scores: input.playerScores,
                fixtures: input.fixtures,
                elementTypes: input.bootstrap.elementTypes,
                settings: input.bootstrap.gameSettings,
                startGameweek: input.planningStartGameweek,
                horizon: input.coachProfile.planningHorizon,
                budget: budget,
                events: input.bootstrap.events
            )
        } else {
            optimizedSquads = nil
        }

        return FPLAdvisorDerivedState(
            validation: validation,
            liveSquadSummary: liveSummary,
            planningRoutes: routes,
            commandCenter: commandCenter,
            optimizedSquads: optimizedSquads
        )
    }
}
