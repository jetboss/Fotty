import Foundation
import SwiftUI
import Combine

private struct FPLCoachRequestContext: Equatable {
    let season: String
    let managerSelectionID: UUID
    let managerID: Int?
    let gameweek: Int?
    let publishedGameweek: Int?
    let planningGameweek: Int
    let phase: FPLGameweekPhase
    let selectedPicks: [FPLPick]?
    let publishedPicks: [FPLPick]?
    let squadSource: String
    let planningBank: Int
    let freeTransfers: Int?
    let profile: FPLCoachProfile
    let rivalID: Int?
}

@MainActor
public final class FPLAdvisorViewModel: ObservableObject {
    /// Opt-in, Debug-only shell data for deterministic UI accessibility tests.
    /// Generic XCTest launches do not enable this fixture.
    public let usesAutomatedTestFixture: Bool

    @AppStorage("fotty.user.fplManagerId") public var storedManagerId: Int = 0 {
        didSet {
            let normalized = storedManagerId > 0 ? storedManagerId : nil
            if normalized != managerId {
                managerId = normalized
            }
        }
    }
    
    @Published public var managerId: Int?
    @Published private(set) var requiresManagerConfirmation = false
    @Published public var isLoading: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var errorMessage: String? = nil
    // Data State
    @Published public var bootstrap: FPLBootstrapResponse?
    @Published public var managerSummary: FPLManagerSummary?
    @Published public var picks: FPLManagerPicks?
    /// Published scoring evidence never contains edits made in Fotty.
    @Published public private(set) var officialPicks: FPLManagerPicks?
    @Published private(set) var savedSquadDraft: FPLLocalSquadDraft?
    @Published public var picksGameweek: Int?
    @Published public var currentGameweek: FPLGameweek?
    @Published public var nextGameweek: FPLGameweek?
    @Published public var fixtures: [FPLFixture] = []
    @Published public var managerHistory: FPLManagerHistoryResponse?
    @Published public var eventLive: FPLEventLiveResponse?
    @Published public var resourceMetadata: [String: FPLResourceMetadata] = [:]
    @Published public var gameweekPhase: FPLGameweekPhase = .unavailable
    
    // Computed Advisor State
    @Published public var playerScores: [PlayerScore] = []
    @Published public var transferRecs: [TransferRecommendation] = []
    @Published public var captainRecs: [CaptainRecommendation] = []
    @Published public var priceAlerts: [PriceChangeAlert] = []
    @Published public var fixtureGrid: [TeamFixtureRow] = []
    @Published public var fixtureGameweeks: [Int] = []
    @Published public var squadValidation: FPLSquadValidationReport?
    @Published public var freeTransferEstimate: FPLFreeTransferEstimate?
    @Published public var liveSquadSummary: FPLLiveSquadSummary?
    @Published private(set) var matchdayRefreshFailed = false
    @Published public var commandCenterState: FPLCommandCenterState?
    @Published public var planningRoutes: [FPLDraftRoute] = []
    @Published public var savedScenarios: [FPLSavedScenario] = []
    @Published public var optimizedSquads: [FPLOptimizedSquad] = []
    @Published public var gameweekReviews: [FPLGameweekReview] = []
    @Published public var coachProfile: FPLCoachProfile = .default
    @Published public var elementSummaries: [Int: FPLElementSummaryResponse] = [:]
    @Published private(set) var elementSummaryErrors: [Int: String] = [:]
    @Published private(set) var loadingElementSummaries: Set<Int> = []
    @Published private(set) var evidenceRevision = UUID()
    @Published public var draftErrorMessage: String?
    @Published public var alertStatusMessage: String?
    
    // League / Rival State
    @Published public var selectedLeagueId: Int? = nil
    @Published public var leagueStandings: FPLLeagueStandingsResponse? = nil
    @Published public var isLeagueLoading: Bool = false
    @Published public var isLoadingMoreLeagueStandings: Bool = false
    @Published public var leagueErrorMessage: String? = nil
    @Published public var rivalPicks: FPLManagerPicks? = nil
    @Published public var rivalManagerName: String? = nil
    @Published public var selectedRivalID: Int? = nil
    @Published public var rivalGapAnalysis: RivalGapAnalysis? = nil
    @Published public var isRivalLoading: Bool = false
    @Published public var rivalErrorMessage: String? = nil
    @Published public var isShowingRivalSheet: Bool = false
    private var selectedRivalEntry: FPLLeagueStandingEntry?
    private var selectedRivalLeagueID: Int?
    private var rivalLoadTask: Task<FPLResource<FPLManagerPicks>, Error>?
    private var rivalPrimaryEvidenceRevision: UUID?

    var rivalComparisonNeedsRefresh: Bool {
        guard let comparison = rivalGapAnalysis, let checkedAt = comparison.checkedAt else { return true }
        return rivalErrorMessage != nil || comparison.gameweek != currentGameweek?.id
            || scoringSnapshotNeedsRefresh || rivalPrimaryEvidenceRevision != evidenceRevision
            || selectedRivalLeagueID != selectedLeagueId
            || (!comparison.isFinalComparison && now().timeIntervalSince(checkedAt) > 90)
    }

    var rivalComparisonStatus: String {
        if isRivalLoading { return "UPDATING" }
        guard let comparison = rivalGapAnalysis else { return "CHOOSE RIVAL" }
        if rivalComparisonNeedsRefresh { return "LAST COMPLETE" }
        return comparison.isFinalComparison ? "FINAL" : "PROVISIONAL"
    }
    @Published public var isCustomDraft: Bool = false
    
    // AI Coach Chat History State
    @Published public var coachMessages: [AICoachMessage] = []
    @Published var coachInputDraft = ""
    @Published private(set) var isCoachThinking = false
    @Published var coachStatusMessage: String?
    @Published var comparisonPlayer1ID: Int?
    @Published var comparisonPlayer2ID: Int?
    @Published public var decisionJournalEntries: [FPLDecisionJournalEntry] = []
    
    private var loadRequestID = UUID()
    private var leagueRequestID = UUID()
    private var rivalRequestID = UUID()
    private(set) var managerSelectionID = UUID()
    private var draftBudgetLimit: Int?
    private let workspacePersistence: FPLWorkspacePersistence
    private let managerSeasonStore: FPLManagerSeasonStore
    private var elementSummaryRequests: [Int: UUID] = [:]
    private var elementSummaryTasks: [Int: Task<FPLResource<FPLElementSummaryResponse>, Error>] = [:]
    private var elementSummaryTaskIdentities: [Int: String] = [:]
    let transferStagingStore: FPLTransferStagingStore
    private let matchdayContext: FPLMatchdayContextStore
    private let dataProvider: any FPLAdvisorDataProviding
    private let now: @Sendable () -> Date
    private var fixtureShowsPublishedSquad = false
    private var coachRequestID: UUID?
    private var coachRequestTask: Task<Void, Never>?
    private var coachRequestRequiresCloudConsent = true

    private func loadCustomDraft() -> FPLLocalSquadDraft? {
        if usesAutomatedTestFixture { return savedSquadDraft }
        return workspacePersistence.loadDraft(managerID: managerId)
    }

    var hasUnverifiedLegacyWorkspace: Bool { workspacePersistence.hasUnverifiedLegacyWorkspace }

    var planningGameweek: Int {
        gameweekPhase == .planning
            ? (currentGameweek?.id ?? nextGameweek?.id ?? 1)
            : (nextGameweek?.id ?? ((currentGameweek?.id ?? 0) + 1))
    }

    private var currentWorkspaceSeason: String? {
        guard !requiresManagerConfirmation, let bootstrap, !bootstrap.events.isEmpty else { return nil }
        let season = FPLSeasonIdentifier.label(from: bootstrap.events)
        guard season == FPLSeasonIdentifier.currentLabel(at: now()),
              storedManagerId <= 0 || !managerSeasonStore.needsConfirmation(managerID: storedManagerId, at: now()) else { return nil }
        return season
    }

    @discardableResult
    private func acceptsWorkspaceMutation() -> Bool {
        // The bounded UI fixture represents an already confirmed current-season
        // workspace. Keep it independent of persisted manager IDs and wall-clock
        // season rollover so interaction tests never mutate or fetch real data.
        if usesAutomatedTestFixture { return true }
        guard currentWorkspaceSeason != nil else {
            if storedManagerId > 0 { requestManagerConfirmation() }
            draftErrorMessage = "Refresh and confirm your current-season team before changing this plan. Existing saved work is unchanged."
            return false
        }
        return true
    }

    var squadSourceTitle: String {
        if isCustomDraft {
            return savedSquadDraft?.targetGameweek.map { "Local draft · for GW\($0)" } ?? "Local draft"
        }
        return picksGameweek.map { "Published squad · GW\($0)" } ?? "Published squad unavailable"
    }

    var squadSourceExplanation: String {
        if isCustomDraft {
            let updated = savedSquadDraft?.basedOnGameweek.map { (picksGameweek ?? 0) > $0 } ?? false
            return (updated ? "A newer published squad is available. " : "")
                + "Your draft is saved on this device. Live points still use the published lineup."
        }
        return "Official-app changes appear here after FPL publishes the deadline squad. Editing here saves a separate local draft."
    }

    var planningBank: Int {
        guard isCustomDraft, let picks, let bootstrap else {
            return officialPicks?.entryHistory?.bank ?? managerSummary?.lastDeadlineBank ?? 0
        }
        let players = Dictionary(uniqueKeysWithValues: bootstrap.elements.map { ($0.id, $0) })
        let cost = picks.picks.reduce(0) { $0 + ($1.sellingPrice ?? players[$1.element]?.nowCost ?? 0) }
        return (savedSquadDraft?.budgetLimit ?? draftBudgetLimit ?? cost) - cost
    }

    var wildcardBudget: FPLWildcardBudget {
        FPLWildcardBudget.resolve(publishedPicks: officialPicks, publishedGameweek: picksGameweek,
            managerSummary: managerSummary, players: bootstrap?.elements ?? [],
            savedDraftBudgetLimit: savedSquadDraft?.budgetLimit, draftBudgetLimit: draftBudgetLimit,
            settings: bootstrap?.gameSettings)
    }

    /// Identity-checked source shared by the staging UI and its final save gate.
    var transferStagingBaseline: FPLTransferStagingBaseline? {
        guard let managerId, managerId > 0,
              !requiresManagerConfirmation,
              usesAutomatedTestFixture || managerSummary?.id == managerId,
              let bootstrap, let picks = picks?.picks,
              FPLPlanningBounds.targetGameweek(explicit: planningGameweek, planningGameweek: planningGameweek,
                events: bootstrap.events) != nil,
              currentWorkspaceSeason != nil else { return nil }
        let published = officialPicks?.picks ?? []
        let budget = FPLTransferPlanContext.budgetLimit(
            picks: published, players: bootstrap.elements,
            bank: officialPicks?.entryHistory?.bank
                ?? (managerSummary?.currentEvent == picksGameweek ? managerSummary?.lastDeadlineBank : nil)
        ) ?? (isCustomDraft ? savedSquadDraft?.budgetLimit : nil)
        return FPLTransferStagingBaseline(
            picks: published.isEmpty ? picks : FPLTransferStagingBaseline.priced(picks, using: published),
            publishedPicks: published, publishedGameweek: picksGameweek,
            targetGameweek: planningGameweek, budgetLimit: budget)
    }

    /// Shared by initial/foreground loads and the live refresh. Never deletes a draft.
    func applyPublishedSquad(_ published: FPLManagerPicks?, gameweek: Int?) {
        if let published, let gameweek, gameweek >= (picksGameweek ?? 0) {
            officialPicks = published
            picksGameweek = gameweek
        }
        savedSquadDraft = loadCustomDraft()
        let showPublished = usesAutomatedTestFixture
            ? fixtureShowsPublishedSquad
            : workspacePersistence.shouldShowPublishedSquad(managerID: managerId)
        if let draft = savedSquadDraft, !showPublished || officialPicks == nil {
            picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: draft.picks)
            isCustomDraft = true
        } else {
            picks = officialPicks
            isCustomDraft = false
        }
    }

    func showPublishedSquad() {
        guard managerId != nil, officialPicks != nil else { return }
        if usesAutomatedTestFixture { fixtureShowsPublishedSquad = true }
        else { workspacePersistence.setShowsPublishedSquad(true, managerID: managerId) }
        applyPublishedSquad(nil, gameweek: nil)
        draftErrorMessage = nil
        recalculateRecommendations()
    }

    func showSavedDraft() {
        guard managerId != nil, loadCustomDraft() != nil else { return }
        if usesAutomatedTestFixture { fixtureShowsPublishedSquad = false }
        else { workspacePersistence.setShowsPublishedSquad(false, managerID: managerId) }
        applyPublishedSquad(nil, gameweek: nil)
        draftErrorMessage = nil
        recalculateRecommendations()
    }
    
    public func loadSavedCoachMessages() {
        coachMessages = workspacePersistence.loadCoachMessages(managerID: managerId)
    }
    
    public func saveCoachMessages() {
        guard !usesAutomatedTestFixture else { return }
        workspacePersistence.saveCoachMessages(coachMessages, managerID: managerId)
    }
    
    public func addCoachMessage(_ msg: AICoachMessage) {
        coachMessages.append(msg)
        saveCoachMessages()
    }
    
    public func clearCoachHistory() {
        cancelCoachRequest()
        coachMessages.removeAll()
        guard !usesAutomatedTestFixture else { return }
        workspacePersistence.clearCoachMessages(managerID: managerId)
    }
    
    public convenience init(draftDefaults: UserDefaults = .standard) {
        self.init(draftDefaults: draftDefaults, dataProvider: FPLService.shared)
    }

    init(
        draftDefaults: UserDefaults,
        dataProvider: any FPLAdvisorDataProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.dataProvider = dataProvider
        self.now = now
        self.workspacePersistence = FPLWorkspacePersistence(defaults: draftDefaults)
        self.managerSeasonStore = FPLManagerSeasonStore(defaults: draftDefaults)
        self.matchdayContext = draftDefaults === UserDefaults.standard
            ? .shared : FPLMatchdayContextStore(defaults: draftDefaults)
        self._storedManagerId = AppStorage(wrappedValue: 0, "fotty.user.fplManagerId", store: draftDefaults)
        #if DEBUG
        usesAutomatedTestFixture = ProcessInfo.processInfo.environment["FOTTY_FPL_UI_TESTING"] == "1"
        #else
        usesAutomatedTestFixture = false
        #endif

        self.transferStagingStore = FPLTransferStagingStore(
            defaults: draftDefaults, persists: !usesAutomatedTestFixture
        )

        if let legacyManagerId = workspacePersistence.legacyManagerID(currentStoredID: storedManagerId) {
            storedManagerId = legacyManagerId
        }
        self.managerId = usesAutomatedTestFixture
            ? 9_999_999
            : (storedManagerId > 0 ? storedManagerId : nil)
        self.requiresManagerConfirmation = !usesAutomatedTestFixture && storedManagerId > 0
            && managerSeasonStore.needsConfirmation(managerID: storedManagerId, at: now())
        migrateLegacyLocalDataIfNeeded()
        loadSavedCoachMessages()
        if usesAutomatedTestFixture {
            gameweekPhase = .planning
#if DEBUG
            configurePopulatedUIFixture()
#endif
            let fixtureCard = FPLCoachCardPayload(
                answer: "The test response remains readable at large text sizes.",
                confidence: "high",
                evidence: ["Deterministic on-device UI-test fixture."],
                downside: ["No manager account or network request is used."],
                verifyBeforeDeadline: ["Complete the decision in official FPL before the deadline."],
                source: FPLSmartCoachResult.Source.rulesEngine.rawValue,
                model: "Fotty UI fixture",
                officialDataStatus: "Test fixture",
                verifiedAt: Date(timeIntervalSince1970: 0),
                usage: .zero
            )
            coachMessages = [
                AICoachMessage(
                    sender: .coach,
                    text: fixtureCard.answer,
                    date: Date(timeIntervalSince1970: 0),
                    tag: "Test fixture",
                    coachCard: fixtureCard
                )
            ]
        } else if storedManagerId > 0 {
            coachProfile = FPLCoachProfileStore.load(managerID: storedManagerId)
            gameweekReviews = FPLReviewStore.load(managerID: storedManagerId)
            decisionJournalEntries = FPLDecisionJournalStore.load(managerID: storedManagerId)
            savedScenarios = FPLScenarioStore.load(managerID: storedManagerId)
        }
    }
    
#if DEBUG
    /// Synthetic, bounded data exercises real layouts without using a manager or API.
    private func configurePopulatedUIFixture() {
        do {
            func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
                try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
            }
            let names = ["Test Keeper", "Test Double-Name", "Test Defender B", "Test Defender", "Long Defender", "Test Centreback", "Test Midfielder A", "Test Midfielder", "Test Midfielder B", "Test Forward", "Test Striker", "Bench Keeper", "Bench Midfielder", "Long Bench Name", "Bench Forward"]
            let positions = [1, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 1, 3, 3, 4]
            let teamObjects: [[String: Any]] = (1...6).map {
                ["id": $0, "code": $0, "name": "Test Club \($0)", "short_name": "T\($0)"]
            }
            var playerObjects: [[String: Any]] = names.enumerated().map { index, name in
                var player: [String: Any] = [
                    "id": index + 1, "web_name": name, "first_name": "Test", "second_name": name,
                    "team": index % 6 + 1, "team_code": index % 6 + 1, "element_type": positions[index],
                    "now_cost": 50, "selected_by_percent": "14.2", "form": "4.5", "points_per_game": "5.0",
                    "influence": "20.0", "creativity": "15.0", "threat": "30.0", "ict_index": "8.0",
                    "status": "a", "news": "", "ep_next": "5.4", "minutes": 90, "starts": 1,
                    "event_points": 5, "total_points": 5
                ]
                for key in ["cost_change_event", "cost_change_event_fall", "goals_scored", "assists", "clean_sheets", "goals_conceded", "yellow_cards", "red_cards", "saves", "bonus", "bps", "transfers_in_event", "transfers_out_event"] {
                    player[key] = 0
                }
                return player
            }
            var replacement = playerObjects[1]
            replacement["id"] = 16
            replacement["web_name"] = "Replacement Defender"
            playerObjects.append(replacement)
            let deadline = Date().addingTimeInterval(48 * 3600)
            let event: [String: Any] = [
                "id": 2, "name": "Gameweek 2", "deadline_time": ISO8601DateFormatter().string(from: deadline),
                "deadline_time_epoch": Int(deadline.timeIntervalSince1970), "finished": false,
                "is_previous": false, "is_current": false, "is_next": true
            ]
            let data = try decode(FPLBootstrapResponse.self, [
                "events": [event], "elements": playerObjects, "teams": teamObjects,
                "element_types": [], "total_players": 1000
            ])
            var fixtureObjects: [[String: Any]] = []
            for gameweek in 2...6 {
                for home in stride(from: 1, through: 5, by: 2) {
                    fixtureObjects.append([
                        "id": gameweek * 10 + home, "event": gameweek, "finished": false,
                        "team_h": home, "team_a": home + 1, "team_h_difficulty": gameweek - 1,
                        "team_a_difficulty": 7 - gameweek
                    ])
                }
            }
            bootstrap = data
            currentGameweek = data.events.first
            nextGameweek = data.events.first
            fixtures = try decode([FPLFixture].self, fixtureObjects)
            managerSummary = try decode(FPLManagerSummary.self, [
                "id": 9_999_999, "name": "UI test squad", "player_first_name": "Test", "player_last_name": "Manager",
                "summary_overall_points": 95, "summary_overall_rank": 123456, "summary_event_points": 95, "current_event": 1
            ])
            let selection = names.indices.map { index in
                FPLPick(element: index + 1, position: index + 1, multiplier: index < 11 ? (index == 9 ? 2 : 1) : 0, isCaptain: index == 9, isViceCaptain: index == 10, elementType: positions[index])
            }
            picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: selection)
            officialPicks = picks
            picksGameweek = 1
            playerScores = FPLAdvisorEngine.scoreAllPlayers(players: data.elements, teams: data.teams, fixtures: fixtures, events: data.events)
            captainRecs = FPLAdvisorEngine.getCaptainRecommendations(picks: selection, allScores: playerScores)
            fixtureGameweeks = Array(2...6)
            fixtureGrid = FPLAdvisorEngine.buildFixtureGrid(teams: data.teams, fixtures: fixtures, events: data.events)
            commandCenterState = FPLCommandCenterState(
                phase: .planning, title: "Plan for gameweek 2", subtitle: "Synthetic UI data · no team changes are submitted",
                metrics: [.init(label: "EST. FT", value: "2", detail: "Verify in official FPL"), .init(label: "CAPTAIN", value: "Test Forward", detail: "Fotty recommendation"), .init(label: "BANK", value: "£1.5m", detail: "Official snapshot")],
                actions: [.init(title: "Check your starting eleven", detail: "Review your captain, bench order and upcoming opponents", symbol: "person.3.fill", priority: 1, destination: .squad), .init(title: "Compare captain options", detail: "See the evidence behind the ranking", symbol: "c.circle.fill", priority: 2, destination: .captain)],
                warnings: []
            )
        } catch {
            assertionFailure("Invalid FPL UI fixture: \(error)")
        }
    }
#endif

    public func setManagerId(_ id: Int) {
        guard id > 0 else { return }
        // Invalidate in-flight work and clear the previous team's visible state.
        // Manager-scoped drafts and history remain saved for a later reconnect.
        clearManagerId()
        storedManagerId = id
        managerId = id
        managerSeasonStore.confirm(managerID: id, at: now())
        requiresManagerConfirmation = false
        migrateLegacyLocalDataIfNeeded()
        loadSavedCoachMessages()
        coachProfile = FPLCoachProfileStore.load(managerID: id)
        gameweekReviews = FPLReviewStore.load(managerID: id)
        decisionJournalEntries = FPLDecisionJournalStore.load(managerID: id)
        savedScenarios = FPLScenarioStore.load(managerID: id)
        Task {
            guard self.managerId == id else { return }
            await loadData()
        }
    }
    
    public func clearManagerId() {
        cancelCoachRequest()
        cancelRivalRefresh(clearSelection: true)
        managerSeasonStore.clear()
        requiresManagerConfirmation = false
        invalidateElementSummaryRequests()
        let clearedManagerID = managerId
        loadRequestID = UUID()
        leagueRequestID = UUID()
        rivalRequestID = UUID()
        managerSelectionID = UUID()
        storedManagerId = 0
        managerId = nil
        isLoading = false
        isRefreshing = false
        errorMessage = nil
        bootstrap = nil
        currentGameweek = nil
        nextGameweek = nil
        managerSummary = nil
        picks = nil
        officialPicks = nil
        savedSquadDraft = nil
        picksGameweek = nil
        playerScores = []
        transferRecs = []
        captainRecs = []
        priceAlerts = []
        fixtureGrid = []
        fixtureGameweeks = []
        fixtures = []
        managerHistory = nil
        eventLive = nil
        resourceMetadata = [:]
        gameweekPhase = .unavailable
        squadValidation = nil
        freeTransferEstimate = nil
        liveSquadSummary = nil
        matchdayRefreshFailed = false
        commandCenterState = nil
        planningRoutes = []
        savedScenarios = []
        optimizedSquads = []
        gameweekReviews = []
        coachProfile = .default
        elementSummaries = [:]
        elementSummaryErrors = [:]
        evidenceRevision = UUID()
        draftErrorMessage = nil
        alertStatusMessage = nil
        draftBudgetLimit = nil
        leagueStandings = nil
        selectedLeagueId = nil
        isLeagueLoading = false
        isLoadingMoreLeagueStandings = false
        leagueErrorMessage = nil
        rivalGapAnalysis = nil
        rivalPicks = nil
        rivalManagerName = nil
        isShowingRivalSheet = false
        selectedRivalID = nil
        isRivalLoading = false
        rivalErrorMessage = nil
        isCustomDraft = false
        coachMessages = []
        coachInputDraft = ""
        isCoachThinking = false
        comparisonPlayer1ID = nil
        comparisonPlayer2ID = nil
        decisionJournalEntries = []
        matchdayContext.clear(managerID: clearedManagerID)
    }

    private func migrateLegacyLocalDataIfNeeded() {
        workspacePersistence.migrateLegacyWorkspace(managerID: managerId)
    }

    /// Restore/rollover is not the explicit user identity-confirmation action.
    func requestManagerConfirmation(managerID: Int? = nil) {
        let previous = managerID ?? self.managerId ?? (storedManagerId > 0 ? storedManagerId : nil)
        clearManagerId()
        if let previous, previous > 0 {
            storedManagerId = previous
            self.managerId = previous
            requiresManagerConfirmation = true
        }
    }
    
    public func loadData(isRefresh: Bool = false) async {
        await loadData(isRefresh: isRefresh, isMatchdayRefresh: false)
    }

    private func loadData(isRefresh: Bool, isMatchdayRefresh: Bool) async {
        guard let id = managerId, id > 0 else { return }
        if !usesAutomatedTestFixture, storedManagerId > 0,
           managerSeasonStore.needsConfirmation(managerID: id, at: now()) {
            if !requiresManagerConfirmation { requestManagerConfirmation(managerID: id) }
            return
        }
        let requestID = UUID()
        loadRequestID = requestID
        let selectionID = managerSelectionID
        let requestedSeason = FPLSeasonIdentifier.currentLabel(at: now())
        let refreshStartedAt = Date()
        let priorGameweekID = currentGameweek?.id
        let priorPhase = gameweekPhase
        isRefreshing = isRefresh || isMatchdayRefresh
        isLoading = !isRefreshing

        if isRefresh {
            invalidateElementSummaryRequests()
            await dataProvider.clearCache()
        }
        errorMessage = nil
        defer {
            if self.loadRequestID == requestID {
                self.isLoading = false
                self.isRefreshing = false
            }
        }
        
        do {
            async let bootstrapTask = dataProvider.fetchBootstrapResource(
                maximumAge: FPLMatchdayRefreshPolicy.bootstrapMaximumAge(gameweek: currentGameweek, now: now())
            )
            async let fixturesTask = dataProvider.fetchFixturesResource()
            async let summaryTask = dataProvider.fetchManagerSummaryResource(id: id)
            async let historyTask = dataProvider.fetchManagerHistoryResource(id: id)

            let (bootstrapResource, fixtureResource, summaryResource, historyResource) = try await (
                bootstrapTask,
                fixturesTask,
                summaryTask,
                historyTask
            )
            guard !Task.isCancelled, loadRequestID == requestID,
                  managerSelectionID == selectionID, managerId == id else { return }

            let bData = bootstrapResource.value
            let fData = fixtureResource.value
            let summaryData = summaryResource.value
            var fetchedMetadata = [
                "bootstrap": bootstrapResource.metadata,
                "fixtures": fixtureResource.metadata,
                "manager": summaryResource.metadata,
                "history": historyResource.metadata
            ]

            let officialCurrent = bData.events.first(where: { $0.isCurrent })
            let officialNext = bData.events.first(where: { $0.isNext })
            // Keep a visible live result through full-time/data_checked. A new
            // official-current ID still advances it; an ordinary reopen keeps
            // the existing next-planning-week selection behavior.
            let retainVisibleCurrent = isMatchdayRefresh && priorGameweekID == officialCurrent?.id
            let activeGameweek = officialCurrent?.finished == true && !retainVisibleCurrent
                ? (officialNext ?? officialCurrent)
                : (officialCurrent ?? officialNext)
            let fetchedPhase = FPLGameweekPhase.resolve(
                gameweek: activeGameweek,
                fixtures: fData,
                now: now()
            )

            var fetchedOfficialPicks: FPLManagerPicks?
            var fetchedPicksGameweek: Int?
            var fetchedEventLive: FPLEventLiveResponse?
            if let gameweekID = activeGameweek?.id {
                do {
                    let picksResource = try await dataProvider.fetchPicksResource(
                        managerId: id,
                        gameweek: gameweekID
                    )
                    fetchedOfficialPicks = picksResource.value
                    fetchedPicksGameweek = gameweekID
                    fetchedMetadata["picks"] = picksResource.metadata
                } catch {
                    if gameweekID > 1,
                       let previous = try? await dataProvider.fetchPicksResource(
                        managerId: id,
                        gameweek: gameweekID - 1
                       ) {
                        fetchedOfficialPicks = previous.value
                        fetchedPicksGameweek = gameweekID - 1
                        fetchedMetadata["picks"] = previous.metadata
                    }
                }

                if fetchedPhase != .planning,
                   let liveResource = try? await dataProvider.fetchEventLiveResource(gameweek: gameweekID) {
                    fetchedEventLive = liveResource.value
                    fetchedMetadata["eventLive"] = liveResource.metadata
                }
            }
            guard !Task.isCancelled, loadRequestID == requestID,
                  managerSelectionID == selectionID, managerId == id else { return }

            if isMatchdayRefresh,
               !FPLMatchdayRefreshPolicy.canPublishRefresh(fetchedMetadata, phase: fetchedPhase, now: now()) {
                throw URLError(.resourceUnavailable)
            }
            if isMatchdayRefresh, fetchedPhase != .planning,
               fetchedPicksGameweek != activeGameweek?.id {
                throw URLError(.resourceUnavailable)
            }
            if fetchedPhase != .planning,
               !FPLMatchdayRefreshPolicy.hasCurrentScoringResources(fetchedMetadata, now: now()) {
                if isMatchdayRefresh {
                    // Atomic publication: retain every old value AND original
                    // timestamp, instead of refreshing points over old fixtures.
                    throw URLError(.resourceUnavailable)
                }
                fetchedEventLive = nil
                fetchedMetadata.removeValue(forKey: "eventLive")
            }

            guard requestedSeason == FPLSeasonIdentifier.currentLabel(at: now()),
                  FPLSeasonIdentifier.label(from: bData.events) == requestedSeason else {
                if storedManagerId > 0 { requestManagerConfirmation(managerID: id) }
                throw URLError(.resourceUnavailable)
            }
            let previousPlayers = Dictionary(uniqueKeysWithValues: (bootstrap?.elements ?? []).map { ($0.id, $0) })
            let retainedHistoryIDs = Set(bData.elements.compactMap { player -> Int? in
                guard let old = previousPlayers[player.id], old.firstName == player.firstName,
                      old.secondName == player.secondName, old.team == player.team else { return nil }
                return player.id
            })
            if Set(elementSummaries.keys).union(elementSummaryTasks.keys).contains(where: { !retainedHistoryIDs.contains($0) }) {
                invalidateElementSummaryRequests()
            }
            elementSummaries = elementSummaries.filter { retainedHistoryIDs.contains($0.key) }
            elementSummaryErrors = elementSummaryErrors.filter { retainedHistoryIDs.contains($0.key) }
            for playerID in retainedHistoryIDs {
                let key = "element-\(playerID)"
                fetchedMetadata[key] = resourceMetadata[key]
            }
            self.bootstrap = bData
            self.decisionJournalEntries = FPLDecisionJournalStore.load(managerID: id, season: requestedSeason)
            self.fixtures = fData
            self.managerSummary = summaryData
            self.managerHistory = historyResource.value
            // Preserve provenance if a transient failure leaves the previous
            // published squad in place. A fallback must not roll a newer squad back.
            if (fetchedPicksGameweek ?? 0) < (picksGameweek ?? 0) || fetchedOfficialPicks == nil {
                fetchedMetadata["picks"] = resourceMetadata["picks"]
            }
            self.resourceMetadata = fetchedMetadata
            self.currentGameweek = activeGameweek
            self.nextGameweek = officialNext
            self.gameweekPhase = fetchedPhase
            self.eventLive = fetchedEventLive
            self.matchdayRefreshFailed = false
            self.evidenceRevision = UUID()

            let scores = FPLAdvisorEngine.scoreAllPlayers(
                players: bData.elements,
                teams: bData.teams,
                fixtures: fData,
                events: bData.events
            )
            self.playerScores = scores
            let catalogByID = Dictionary(uniqueKeysWithValues: bData.elements.map { ($0.id, $0) })

            if let official = fetchedOfficialPicks {
                let squadCost = official.picks.reduce(0) { $0 + (catalogByID[$1.element]?.nowCost ?? 0) }
                self.draftBudgetLimit = max(
                    bData.gameSettings?.squadTotalSpend ?? 1_000,
                    squadCost + (summaryData.lastDeadlineBank ?? official.entryHistory?.bank ?? 0)
                )
            } else {
                self.draftBudgetLimit = summaryData.lastDeadlineValue
                    ?? bData.gameSettings?.squadTotalSpend
                    ?? 1_000
            }
            applyPublishedSquad(fetchedOfficialPicks, gameweek: fetchedPicksGameweek)
            if self.picks == nil {
                let start = activeGameweek?.id ?? officialNext?.id ?? 1
                let budget = bData.gameSettings?.squadTotalSpend ?? 1_000
                let generated = FPLSquadOptimizer.generate(
                    profiles: [.balanced],
                    scores: scores,
                    fixtures: fData,
                    elementTypes: bData.elementTypes,
                    settings: bData.gameSettings,
                    startGameweek: start,
                    horizon: coachProfile.planningHorizon,
                    budget: budget,
                    events: bData.events
                ).first
                self.picks = generated.map {
                    FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: $0.picks)
                }
                self.isCustomDraft = generated != nil
                self.draftBudgetLimit = budget
            }

            self.priceAlerts = FPLAdvisorEngine.getPriceAlerts(allScores: scores)
            self.fixtureGrid = FPLAdvisorEngine.buildFixtureGrid(
                teams: bData.teams,
                fixtures: fData,
                events: bData.events,
                count: 5
            )
            let planningStart = gameweekPhase == .planning
                ? (activeGameweek?.id ?? officialNext?.id ?? 1)
                : (officialNext?.id ?? ((activeGameweek?.id ?? 0) + 1))
            self.fixtureGameweeks = FPLPlanningBounds.gameweeks(start: planningStart, horizon: 5, events: bData.events)
            self.freeTransferEstimate = FPLFreeTransferEstimator.estimate(
                history: historyResource.value,
                targetGameweek: planningStart,
                startedEvent: summaryData.startedEvent,
                maximum: bData.gameSettings?.maximumFreeTransfers ?? FPLTransferRules.maximumBankedFreeTransfers
            )
            recalculateRecommendations(rebuildOptimizer: !isMatchdayRefresh
                || priorGameweekID != activeGameweek?.id || priorPhase != fetchedPhase)
            await refreshSelectedRivalAfterPrimarySnapshot()

            if !isMatchdayRefresh {
                await recordLatestConfirmedReview(
                    managerID: id,
                    requestID: requestID,
                    bootstrap: bData,
                    fixtures: fData,
                    history: historyResource.value
                )
            }
            guard !Task.isCancelled, loadRequestID == requestID, managerId == id else { return }

            let classicLeagues = summaryData.leagues?.classic ?? []
            if !isMatchdayRefresh,
               let firstLeague = classicLeagues.first(where: \.isPrivateMiniLeague) ?? classicLeagues.first {
                self.selectedLeagueId = firstLeague.id
                await loadLeagueStandings(leagueId: firstLeague.id)
            }
            guard !Task.isCancelled, loadRequestID == requestID, managerId == id else { return }
            FottyQualityStore.shared.record(
                category: .fpl,
                name: "refresh",
                outcome: .success,
                durationMilliseconds: Int(Date().timeIntervalSince(refreshStartedAt) * 1_000),
                details: [
                    "feed": self.primaryFreshness?.source.rawValue ?? "unknown",
                    "result": self.isCustomDraft ? "local_draft" : "official_squad"
                ]
            )
        } catch {
            guard !Task.isCancelled, loadRequestID == requestID, managerId == id else { return }
            if isMatchdayRefresh {
                self.matchdayRefreshFailed = true
                self.errorMessage = "Could not refresh the complete FPL snapshot. Showing the previous update; retrying automatically."
            } else if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
                self.errorMessage = "Fantasy Premier League is unavailable while this device is offline."
            } else {
                self.errorMessage = "Could not load that FPL manager. Check the manager ID and try again."
            }
            FottyQualityStore.shared.record(
                category: .fpl,
                name: "refresh",
                outcome: .failure,
                durationMilliseconds: Int(Date().timeIntervalSince(refreshStartedAt) * 1_000),
                details: [
                    "reason_code": (error as? URLError)?.code == .notConnectedToInternet ? "offline" : "load_failed"
                ]
            )
        }
    }

    private func recordLatestConfirmedReview(
        managerID: Int,
        requestID: UUID,
        bootstrap: FPLBootstrapResponse,
        fixtures: [FPLFixture],
        history: FPLManagerHistoryResponse
    ) async {
        guard let season = currentWorkspaceSeason,
              FPLSeasonIdentifier.label(from: bootstrap.events) == season,
              let completed = bootstrap.events
            .filter({ $0.finished && $0.dataChecked == true })
            .max(by: { $0.id < $1.id }),
              history.current.contains(where: { $0.event == completed.id }) else { return }
        do {
            async let picksResource = dataProvider.fetchPicksResource(
                managerId: managerID,
                gameweek: completed.id
            )
            async let liveResource = dataProvider.fetchEventLiveResource(gameweek: completed.id)
            let (officialPicks, officialLive) = try await (picksResource, liveResource)
            guard !Task.isCancelled, loadRequestID == requestID, managerId == managerID,
                  currentWorkspaceSeason == season else { return }
            let summary = FPLDecisionEngine.liveSquadSummary(
                gameweek: completed,
                picks: officialPicks.value,
                live: officialLive.value,
                players: bootstrap.elements,
                teams: bootstrap.teams,
                fixtures: fixtures
            )
            if let review = FPLDecisionEngine.review(
                gameweek: completed.id,
                picks: officialPicks.value,
                live: summary,
                history: history,
                players: bootstrap.elements
            ) {
                gameweekReviews = FPLReviewStore.upsert(review, managerID: managerID, season: season)
            }
        } catch {
            // The next refresh can retry. A review is never synthesized without
            // both the confirmed manager history and official event-live data.
        }
    }
    
    public func loadLeagueStandings(leagueId: Int, page: Int = 1, appending: Bool = false) async {
        guard page >= 1 else { return }
        guard let season = currentWorkspaceSeason else {
            leagueErrorMessage = "Refresh and confirm your current-season team before loading this league."
            return
        }
        let requestID = UUID()
        leagueRequestID = requestID
        self.selectedLeagueId = leagueId
        self.leagueErrorMessage = nil
        if appending {
            self.isLoadingMoreLeagueStandings = true
        } else {
            self.isLeagueLoading = true
            self.leagueStandings = nil
        }
        defer {
            if leagueRequestID == requestID {
                self.isLeagueLoading = false
                self.isLoadingMoreLeagueStandings = false
            }
        }
        do {
            let res = try await FPLService.shared.fetchLeagueStandings(leagueId: leagueId, page: page)
            guard !Task.isCancelled, leagueRequestID == requestID, selectedLeagueId == leagueId,
                  currentWorkspaceSeason == season else { return }
            if appending, let current = leagueStandings {
                let existingEntries = current.standings.results
                let existingIDs = Set(existingEntries.map(\.entry))
                let newEntries = res.standings.results.filter { !existingIDs.contains($0.entry) }
                self.leagueStandings = FPLLeagueStandingsResponse(
                    league: res.league,
                    standings: FPLLeagueStandingsTable(
                        results: existingEntries + newEntries,
                        hasNext: res.standings.hasNext,
                        page: res.standings.page
                    )
                )
            } else {
                self.leagueStandings = res
            }
        } catch {
            guard !Task.isCancelled, leagueRequestID == requestID, currentWorkspaceSeason == season else { return }
            self.leagueErrorMessage = "Could not load this league. Check your connection and try again."
        }
    }

    public func loadNextLeagueStandingsPage() async {
        guard let leagueId = selectedLeagueId,
              let table = leagueStandings?.standings,
              table.hasNext,
              !isLoadingMoreLeagueStandings else { return }
        await loadLeagueStandings(leagueId: leagueId, page: table.page + 1, appending: true)
    }
    
    public func inspectRival(entry: FPLLeagueStandingEntry) async {
        guard entry.entry != managerId else { return }
        guard let season = currentWorkspaceSeason,
              let managerID = managerId, let gameweek = currentGameweek,
              let standings = leagueStandings?.standings.results,
              let leagueID = selectedLeagueId else {
            rivalErrorMessage = "Load a current gameweek and mini-league before choosing a rival."
            return
        }
        guard gameweekPhase != .planning else {
            rivalErrorMessage = "Rival squads publish after the gameweek deadline. Standings remain available before then."
            return
        }
        rivalLoadTask?.cancel()
        if selectedRivalID != entry.entry || selectedRivalLeagueID != leagueID {
            rivalGapAnalysis = nil
            rivalPicks = nil
        }
        selectedRivalEntry = entry
        selectedRivalLeagueID = leagueID
        selectedRivalID = entry.entry
        rivalManagerName = "\(entry.entryName) (\(entry.managerName))"
        isShowingRivalSheet = true
        guard let ownPicks = officialPicks, picksGameweek == gameweek.id,
              let bootstrap, let live = eventLive,
              FPLMatchdayRefreshPolicy.hasCurrentScoringResources(resourceMetadata, now: now()),
              !scoringSnapshotNeedsRefresh else {
            rivalErrorMessage = "Refresh your gameweek first. A rival comparison needs the same current scoring data for both teams."
            isRivalLoading = false
            rivalRequestID = UUID()
            return
        }
        guard let myEntry = standings.first(where: { $0.entry == managerID }) ?? managerStandingFallback() else {
            rivalErrorMessage = "Your standings were not available. Refresh the mini-league before comparing."
            isRivalLoading = false
            rivalRequestID = UUID()
            return
        }
        let input = FPLRivalSnapshotInput(managerID: managerID, rivalID: entry.entry,
            gameweek: gameweek, ownPicks: ownPicks, bootstrap: bootstrap,
            live: live, fixtures: fixtures, metadata: resourceMetadata)
        let capturedScores = playerScores
        let capturedPhase = gameweekPhase
        let primaryRequestID = loadRequestID
        let primaryEvidenceRevision = evidenceRevision
        isRivalLoading = true
        rivalErrorMessage = nil
        let selectionID = managerSelectionID
        let requestID = UUID()
        rivalRequestID = requestID
        let provider = dataProvider
        let task = Task { try await provider.fetchPicksResource(managerId: entry.entry, gameweek: gameweek.id) }
        rivalLoadTask = task
        defer {
            if rivalRequestID == requestID { isRivalLoading = false; rivalLoadTask = nil }
        }
        func stillOwnsComparison() -> Bool {
            !Task.isCancelled && !task.isCancelled && managerSelectionID == selectionID
                && rivalRequestID == requestID && managerId == managerID
                && selectedRivalID == entry.entry && selectedLeagueId == leagueID
                && currentGameweek?.id == gameweek.id && picksGameweek == gameweek.id
                && currentWorkspaceSeason == season
                && loadRequestID == primaryRequestID
                && FPLMatchdayRefreshPolicy.scoringKeys.allSatisfy { resourceMetadata[$0] == input.metadata[$0] }
                && evidenceRevision == primaryEvidenceRevision && !scoringSnapshotNeedsRefresh
        }
        do {
            let resource = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard stillOwnsComparison() else { return }
            let snapshot = try FPLRivalScoringSnapshot.make(input: input, rival: resource, now: now())
            rivalPicks = resource.value
            rivalPrimaryEvidenceRevision = primaryEvidenceRevision
            rivalGapAnalysis = FPLAdvisorEngine.analyzeRivalGap(myEntry: myEntry, rivalEntry: entry,
                myPicks: ownPicks.picks, rivalPicks: resource.value.picks, allScores: capturedScores,
                gameweek: gameweek.id, phase: capturedPhase, eventLive: live, fixtures: input.fixtures,
                scoringSnapshot: snapshot)
            rebuildDecisionState(rebuildOptimizer: false)
        } catch {
            guard stillOwnsComparison() else { return }
            rivalErrorMessage = rivalGapAnalysis == nil
                ? "A complete, current rival squad is not available. Refresh the gameweek and try again."
                : "Could not update the rival comparison. The last complete comparison is still shown."
        }
    }

    /// Called once by the existing primary-snapshot owner; never starts a poller.
    func refreshSelectedRivalAfterPrimarySnapshot() async {
        guard let selectedRivalEntry, selectedRivalLeagueID == selectedLeagueId else { return }
        let entry = leagueStandings?.standings.results.first { $0.entry == selectedRivalEntry.entry } ?? selectedRivalEntry
        await inspectRival(entry: entry)
    }

    /// Invalidates even providers which finish after cancellation.
    func cancelRivalRefresh(clearSelection: Bool = false) {
        rivalRequestID = UUID()
        rivalLoadTask?.cancel()
        rivalLoadTask = nil
        isRivalLoading = false
        if clearSelection {
            selectedRivalEntry = nil
            rivalPrimaryEvidenceRevision = nil
            selectedRivalLeagueID = nil
            selectedRivalID = nil
            rivalManagerName = nil
            rivalPicks = nil
            rivalGapAnalysis = nil
            rivalErrorMessage = nil
        }
    }

    private func managerStandingFallback() -> FPLLeagueStandingEntry? {
        guard let managerId, let managerSummary,
              let total = managerSummary.summaryOverallPoints,
              let eventTotal = managerSummary.summaryEventPoints else { return nil }
        let league = managerSummary.leagues?.classic.first(where: { $0.id == selectedLeagueId })
        return FPLLeagueStandingEntry(
            entry: managerId,
            entryName: managerSummary.name,
            playerName: managerSummary.fullName,
            rank: league?.entryRank ?? managerSummary.summaryOverallRank ?? 0,
            lastRank: league?.entryLastRank ?? 0,
            total: total,
            eventTotal: eventTotal
        )
    }
    
    // MARK: - Squad Customization & Recalculation
    
    @discardableResult
    public func updateUserSquad(picks: [FPLPick]) -> Bool {
        saveUserSquad(picks: picks, transferBudget: nil)
    }

    @discardableResult
    func saveTransferStaging(_ staging: FPLTransferStagingState) -> Bool {
        guard staging.managerID == managerId, staging.season == FPLSeasonIdentifier.currentLabel(),
              !staging.hasConflict, staging.baseline == transferStagingBaseline,
              let budget = staging.baseline.budgetLimit else {
            draftErrorMessage = "The squad or budget changed. Review the latest data in Transfer Lab before saving."
            return false
        }
        return saveUserSquad(
            picks: FPLTransferStagingBaseline.priced(staging.picks, using: staging.baseline.picks),
            transferBudget: budget)
    }

    private func saveUserSquad(picks: [FPLPick], transferBudget: Int?) -> Bool {
        guard acceptsWorkspaceMutation() else { return false }
        guard let bootstrap, managerId != nil, !requiresManagerConfirmation else {
            draftErrorMessage = "Load your manager and player data before saving a draft."
            return false
        }
        guard FPLPlanningBounds.targetGameweek(explicit: planningGameweek, planningGameweek: planningGameweek,
                events: bootstrap.events) != nil else {
            draftErrorMessage = "No valid upcoming gameweek is available for this draft. Refresh the official calendar."
            return false
        }
        let effectiveBudget = transferBudget ?? (isCustomDraft ? (savedSquadDraft?.budgetLimit ?? draftBudgetLimit) : draftBudgetLimit)
        let validation = FPLSquadValidator.validate(
            picks: picks,
            players: bootstrap.elements,
            elementTypes: bootstrap.elementTypes,
            gameSettings: bootstrap.gameSettings,
            budgetLimit: effectiveBudget
        )
        guard validation.isValid else {
            self.draftErrorMessage = validation.issues.first(where: { $0.severity == .error })?.message
            return false
        }
        let draft = FPLLocalSquadDraft(
            picks: picks,
            basedOnGameweek: transferBudget != nil ? picksGameweek : (isCustomDraft ? (savedSquadDraft?.basedOnGameweek ?? picksGameweek) : picksGameweek),
            targetGameweek: planningGameweek,
            budgetLimit: effectiveBudget
        )
        do {
            if !usesAutomatedTestFixture {
                try workspacePersistence.saveDraft(draft, managerID: managerId)
            }
            fixtureShowsPublishedSquad = false
        } catch {
            draftErrorMessage = "This draft could not be saved. Your previous squad is unchanged."
            return false
        }
        self.draftErrorMessage = nil
        self.squadValidation = validation
        savedSquadDraft = draft
        self.picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: picks)
        self.isCustomDraft = true
        recalculateRecommendations()
        return true
    }
    
    @discardableResult
    public func replacePlayer(oldElementId: Int, newScore: PlayerScore) -> Bool {
        guard let currentPicks = picks?.picks,
              let targetIndex = currentPicks.firstIndex(where: { $0.element == oldElementId }) else {
            draftErrorMessage = "That player is no longer in the displayed squad. Refresh the selection and try again."
            return false
        }
        
        var updated = currentPicks
        let oldPick = currentPicks[targetIndex]
        updated[targetIndex] = FPLPick(
            element: newScore.player.id,
            position: oldPick.position,
            multiplier: oldPick.multiplier,
            isCaptain: oldPick.isCaptain,
            isViceCaptain: oldPick.isViceCaptain,
            elementType: newScore.player.elementType
        )
        
        return updateUserSquad(picks: updated)
    }
    
    public func replacePlayers(swaps: [(oldId: Int, newScore: PlayerScore)]) {
        guard let currentPicks = picks?.picks else { return }
        var updated = currentPicks
        for swap in swaps {
            if let targetIndex = updated.firstIndex(where: { $0.element == swap.oldId }) {
                let oldPick = updated[targetIndex]
                updated[targetIndex] = FPLPick(
                    element: swap.newScore.player.id,
                    position: oldPick.position,
                    multiplier: oldPick.multiplier,
                    isCaptain: oldPick.isCaptain,
                    isViceCaptain: oldPick.isViceCaptain,
                    elementType: swap.newScore.player.elementType
                )
            }
        }
        updateUserSquad(picks: updated)
    }
    
    public func setCaptain(elementId: Int) {
        guard let currentPicks = picks?.picks else { return }
        let previousCaptainID = currentPicks.first(where: \.isCaptain)?.element
        let selectedWasVice = currentPicks.first(where: { $0.element == elementId })?.isViceCaptain == true
        let updated = currentPicks.map { pick -> FPLPick in
            if pick.element == elementId {
                return FPLPick(
                    element: pick.element,
                    position: pick.position,
                    multiplier: 2,
                    isCaptain: true,
                    isViceCaptain: false,
                    purchasePrice: pick.purchasePrice,
                    sellingPrice: pick.sellingPrice,
                    elementType: pick.elementType
                )
            } else if pick.isCaptain || (selectedWasVice && pick.element == previousCaptainID) {
                return FPLPick(
                    element: pick.element,
                    position: pick.position,
                    multiplier: 1,
                    isCaptain: false,
                    isViceCaptain: selectedWasVice,
                    purchasePrice: pick.purchasePrice,
                    sellingPrice: pick.sellingPrice,
                    elementType: pick.elementType
                )
            }
            return pick
        }
        updateUserSquad(picks: updated)
    }
    
    public func resetToAITemplate() {
        if let suggested = optimizedSquads.first(where: { $0.profile == .balanced }) ?? optimizedSquads.first {
            _ = updateUserSquad(picks: suggested.picks)
        }
    }
    
    public func recalculateRecommendations(rebuildOptimizer: Bool = false) {
        guard let currentPicks = self.picks else { return }
        let bank = planningBank
        self.transferRecs = FPLAdvisorEngine.getTransferRecommendations(
            picks: currentPicks.picks,
            allScores: playerScores,
            bank: bank
        )
        self.captainRecs = FPLAdvisorEngine.getCaptainRecommendations(
            picks: currentPicks.picks,
            allScores: playerScores
        )
        rebuildDecisionState(rebuildOptimizer: rebuildOptimizer)
    }

    public func rebuildDecisionState(rebuildOptimizer: Bool) {
        guard let bootstrap else { return }
        let state = FPLAdvisorDerivedStateBuilder.build(
            input: FPLAdvisorDerivedStateInput(
                bootstrap: bootstrap,
                fixtures: fixtures,
                phase: gameweekPhase,
                currentGameweek: currentGameweek,
                planningStartGameweek: planningGameweek,
                displayedPicks: picks,
                publishedPicks: officialPicks,
                publishedPicksGameweek: picksGameweek,
                eventLive: eventLive,
                playerScores: playerScores,
                transferRecommendations: transferRecs,
                freeTransfers: freeTransferEstimate,
                managerHistory: managerHistory,
                managerSummary: managerSummary,
                coachProfile: coachProfile,
                isCustomDraft: isCustomDraft,
                draftBudgetLimit: draftBudgetLimit,
                savedDraftBudgetLimit: savedSquadDraft?.budgetLimit,
                existingValidation: squadValidation
            ),
            rebuildOptimizer: rebuildOptimizer
        )
        squadValidation = state.validation
        liveSquadSummary = state.liveSquadSummary
        planningRoutes = state.planningRoutes
        commandCenterState = state.commandCenter
        if let optimizedSquads = state.optimizedSquads {
            self.optimizedSquads = optimizedSquads
        }

        if !usesAutomatedTestFixture, let managerId, let officialPicks {
            matchdayContext.update(
                managerID: managerId,
                gameweek: picksGameweek ?? currentGameweek?.id,
                phase: gameweekPhase,
                picks: officialPicks.picks,
                players: bootstrap.elements,
                teams: bootstrap.teams,
                live: liveSquadSummary
            )
        }

    }

    public func saveScenario(name: String, route: FPLDraftRoute, gameweek: Int) {
        guard acceptsWorkspaceMutation(), let bootstrap,
              FPLPlanningBounds.targetGameweek(explicit: gameweek, planningGameweek: planningGameweek, events: bootstrap.events) != nil else { return }
        guard let managerId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenario = FPLSavedScenario(
            managerID: managerId,
            gameweek: gameweek,
            name: String((trimmed.isEmpty ? route.name : trimmed).prefix(48)),
            route: route
        )
        savedScenarios = FPLScenarioStore.upsert(scenario)
    }

    public func removeScenario(id: String) {
        guard acceptsWorkspaceMutation(), let managerId else { return }
        savedScenarios = FPLScenarioStore.remove(id: id, managerID: managerId)
    }

    public func fetchElementSummary(playerID: Int, forceRefresh: Bool = false) async -> FPLElementSummaryResponse? {
        guard !Task.isCancelled, !requiresManagerConfirmation,
              let season = currentWorkspaceSeason,
              bootstrap?.elements.contains(where: { $0.id == playerID }) == true else { return nil }
        let key = "element-\(playerID)"
        if !forceRefresh, let cached = elementSummaries[playerID],
           FPLPlayerEvidencePolicy.isCurrent(resourceMetadata[key], at: now()) { return cached }
        guard !usesAutomatedTestFixture else { return elementSummaries[playerID] }
        let selection = managerSelectionID
        let playerIdentity = bootstrap?.elements.first { $0.id == playerID }.map { "\($0.firstName)|\($0.secondName)|\($0.team)" }
        let taskIdentity = "\(season)|\(playerIdentity ?? "")"
        let requestID: UUID
        let task: Task<FPLResource<FPLElementSummaryResponse>, Error>
        if !forceRefresh, elementSummaryTaskIdentities[playerID] == taskIdentity,
           let existing = elementSummaryTasks[playerID], let id = elementSummaryRequests[playerID] {
            task = existing
            requestID = id
        } else {
            elementSummaryTasks[playerID]?.cancel()
            requestID = UUID()
            elementSummaryRequests[playerID] = requestID
            elementSummaryTaskIdentities[playerID] = taskIdentity
            let provider = dataProvider
            task = Task {
                try await provider.fetchElementSummaryResource(playerId: playerID,
                    maximumAge: forceRefresh ? 0 : FPLPlayerEvidencePolicy.maximumAge)
            }
            elementSummaryTasks[playerID] = task
        }
        loadingElementSummaries.insert(playerID)
        defer {
            if elementSummaryRequests[playerID] == requestID {
                elementSummaryTasks[playerID] = nil
                elementSummaryTaskIdentities[playerID] = nil
                loadingElementSummaries.remove(playerID)
            }
        }
        do {
            let resource = try await task.value
            guard !Task.isCancelled, managerSelectionID == selection,
                  elementSummaryRequests[playerID] == requestID,
                  currentWorkspaceSeason == season,
                  bootstrap?.elements.first(where: { $0.id == playerID }).map({ "\($0.firstName)|\($0.secondName)|\($0.team)" }) == playerIdentity else { return nil }
            guard resource.metadata.endpoint == "element-summary/\(playerID)/",
                  resourceMetadata[key].map({ resource.metadata.fetchedAt >= $0.fetchedAt }) ?? true else {
                elementSummaryErrors[playerID] = "A mismatched or older history update was rejected."
                return elementSummaries[playerID]
            }
            elementSummaries[playerID] = resource.value
            resourceMetadata[key] = resource.metadata
            elementSummaryErrors[playerID] = FPLPlayerEvidencePolicy.isCurrent(resource.metadata, at: now())
                ? nil : "Showing saved history; a current update could not be checked."
            return resource.value
        } catch {
            guard !Task.isCancelled, managerSelectionID == selection,
                  elementSummaryRequests[playerID] == requestID else { return nil }
            elementSummaryErrors[playerID] = elementSummaries[playerID] == nil
                ? "Player history could not be loaded. Try refreshing."
                : "History refresh failed. Showing the previous update."
            return elementSummaries[playerID]
        }
    }

    private func invalidateElementSummaryRequests() {
        elementSummaryTasks.values.forEach { $0.cancel() }
        elementSummaryTasks.removeAll()
        elementSummaryRequests.removeAll()
        elementSummaryTaskIdentities.removeAll()
        loadingElementSummaries.removeAll()
    }

    func cancelPlayerHistoryChecks(except selected: Set<Int> = []) {
        for id in Array(elementSummaryTasks.keys) where !selected.contains(id) {
            elementSummaryTasks.removeValue(forKey: id)?.cancel()
            elementSummaryRequests[id] = nil
            elementSummaryTaskIdentities[id] = nil
            loadingElementSummaries.remove(id)
        }
    }

    func playerHistoryStatus(playerID: Int) -> String {
        if loadingElementSummaries.contains(playerID) { return "Checking official history…" }
        if let error = elementSummaryErrors[playerID] { return error }
        guard let metadata = resourceMetadata["element-\(playerID)"] else { return "History not checked yet." }
        return "\(FPLPlayerEvidencePolicy.isCurrent(metadata, at: now()) ? "Checked" : "Last checked") · \(metadata.shortAgeDescription)"
    }

    public func refreshMatchdayData() async {
        guard !usesAutomatedTestFixture, !isLoading, !isRefreshing, managerId != nil else { return }
        await loadData(isRefresh: false, isMatchdayRefresh: true)
    }

    public func updateCoachProfile(_ profile: FPLCoachProfile) {
        guard acceptsWorkspaceMutation() else { return }
        coachProfile = profile
        if let managerId {
            FPLCoachProfileStore.save(profile, managerID: managerId)
        }
        rebuildDecisionState(rebuildOptimizer: true)
    }

    public func scheduleDeadlineAlerts() async {
        guard let gameweek = currentGameweek, gameweekPhase == .planning else {
            alertStatusMessage = "No upcoming planning deadline is available."
            return
        }
        do {
            let count = try await FPLAlertScheduler.scheduleDeadlineReminders(for: gameweek)
            alertStatusMessage = count > 0
                ? "Scheduled \(count) deadline reminder\(count == 1 ? "" : "s")."
                : "Notifications are disabled or the reminder times have passed."
        } catch {
            alertStatusMessage = "Could not schedule deadline reminders."
        }
    }

    public var primaryFreshness: FPLResourceMetadata? {
        resourceMetadata["picks"]
            ?? resourceMetadata["manager"]
            ?? resourceMetadata["bootstrap"]
    }

    var scoringFreshness: FPLResourceMetadata? {
        let resources = FPLMatchdayRefreshPolicy.scoringKeys.compactMap { resourceMetadata[$0] }
        guard resources.count == FPLMatchdayRefreshPolicy.scoringKeys.count else { return nil }
        return resources.min { $0.fetchedAt < $1.fetchedAt }
    }

    /// Presentation only: never recalculate retained points from failed inputs.
    /// A confirmed final result remains final even when it is no longer recent.
    var scoringSnapshotNeedsRefresh: Bool {
        liveSquadSummary?.isFinal != true && (matchdayRefreshFailed
            || !FPLMatchdayRefreshPolicy.hasCurrentScoringResources(resourceMetadata, now: now()))
    }

    var scoringSnapshotAgeDescription: String? {
        guard let metadata = scoringFreshness else { return nil }
        let seconds = Int(max(0, now().timeIntervalSince(metadata.fetchedAt)))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    @discardableResult
    public func recordDecision(
        kind: FPLDecisionJournalEntry.Kind,
        title: String,
        rationale: String,
        expectedOutcome: String,
        source: String,
        estimatedPointCost: Int? = nil,
        targetGameweek: Int? = nil
    ) -> Bool {
        guard acceptsWorkspaceMutation(), let managerId, !requiresManagerConfirmation, let bootstrap,
              let gameweek = FPLPlanningBounds.targetGameweek(explicit: targetGameweek,
                planningGameweek: planningGameweek, events: bootstrap.events) else { return false }
        let season = FPLSeasonIdentifier.label(from: bootstrap.events)
        guard season == FPLSeasonIdentifier.currentLabel(at: now()) else { return false }
        let entry = FPLDecisionJournalEntry(
            managerID: managerId,
            gameweek: gameweek,
            kind: kind,
            title: title,
            rationale: rationale,
            expectedOutcome: expectedOutcome,
            source: source,
            estimatedPointCost: estimatedPointCost
        )
        decisionJournalEntries = FPLDecisionJournalStore.upsert(entry, managerID: managerId, season: season)
        return decisionJournalEntries.contains { $0.id == entry.id }
    }

    public func recordRouteDecision(_ route: FPLDraftRoute) {
        guard let target = route.weeklyProjectedGain.keys.min() else { return }
        let moveDescription = route.transfers.isEmpty
            ? "Roll the transfer"
            : route.transfers.map { "\($0.playerOut.player.webName) → \($0.playerIn.player.webName)" }.joined(separator: ", ")
        recordDecision(
            kind: route.transfers.isEmpty ? .roll : .transfer,
            title: route.name,
            rationale: "\(moveDescription). \(route.explanation)",
            expectedOutcome: "Modeled \(route.projectedGain >= 0 ? "+" : "")\(route.projectedGain.formatted(.number.precision(.fractionLength(1)))) points over \(coachProfile.planningHorizon) gameweeks after the estimated hit.",
            source: "Transfer Lab",
            estimatedPointCost: route.hitCost,
            targetGameweek: target
        )
    }

    @discardableResult
    public func recordCoachDecision(_ card: FPLCoachCardPayload) -> Bool {
        if let checked = card.verifiedAt,
           FPLSeasonIdentifier.currentLabel(at: checked) != currentWorkspaceSeason {
            coachStatusMessage = "Recheck this older-season recommendation before saving a current plan."
            return false
        }
        let receipt = card.verifiedAt.map { "Evidence checked \($0.formatted(date: .abbreviated, time: .shortened))." }
            ?? "Original evidence date not recorded; recheck before acting."
        return recordDecision(
            kind: .strategy,
            title: "Smart Coach recommendation",
            rationale: "\(receipt) \(card.answer)",
            expectedOutcome: card.verifyBeforeDeadline.first ?? "Revisit this advice after the gameweek.",
            source: card.source
        )
    }

    public func updateDecisionOutcome(
        id: String,
        outcome: FPLDecisionJournalEntry.Outcome,
        note: String = ""
    ) {
        guard acceptsWorkspaceMutation(), let season = currentWorkspaceSeason, let managerId,
              let existing = decisionJournalEntries.first(where: { $0.id == id }) else { return }
        var updated = existing
        updated.outcome = outcome
        updated.outcomeNote = note
        updated.updatedAt = Date()
        decisionJournalEntries = FPLDecisionJournalStore.upsert(updated, managerID: managerId, season: season)
    }

    public func removeDecision(id: String) {
        guard acceptsWorkspaceMutation(), let season = currentWorkspaceSeason, let managerId else { return }
        decisionJournalEntries = FPLDecisionJournalStore.remove(id: id, managerID: managerId, season: season)
    }

    private var coachRequestContext: FPLCoachRequestContext {
        FPLCoachRequestContext(
            season: FPLSeasonIdentifier.currentLabel(at: now()),
            managerSelectionID: managerSelectionID, managerID: managerId,
            gameweek: currentGameweek?.id, publishedGameweek: picksGameweek,
            planningGameweek: planningGameweek, phase: gameweekPhase,
            selectedPicks: picks?.picks, publishedPicks: officialPicks?.picks,
            squadSource: squadSourceTitle, planningBank: planningBank,
            freeTransfers: freeTransferEstimate?.count, profile: coachProfile,
            rivalID: selectedRivalID
        )
    }

    /// The workspace owns pending replies, so leaving the tab does not lose them.
    /// Clearing history, disconnecting or disabling consent invalidates the reply.
    @discardableResult
    func sendCoachQuestion(
        _ input: String,
        operation: (@MainActor (String, [AICoachMessage]) async throws -> FPLSmartCoachResult)? = nil
    ) -> Task<Void, Never>? {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isCoachThinking, !requiresManagerConfirmation else { return nil }
        guard usesAutomatedTestFixture || currentWorkspaceSeason != nil else {
            coachStatusMessage = "Refresh and confirm your current-season team before asking Coach."
            return nil
        }
        let cloudAllowed = usesAutomatedTestFixture || workspacePersistence.hasSmartCoachConsent
        coachRequestRequiresCloudConsent = cloudAllowed
        let requestID = UUID()
        let context = coachRequestContext
        coachRequestID = requestID
        isCoachThinking = true
        coachStatusMessage = nil
        addCoachMessage(AICoachMessage(sender: .user, text: query, gameweek: context.gameweek, tag: "Question"))
        let history = coachMessages

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                // An old task must never clear a newer request's loading state.
                if self.coachRequestID == requestID {
                    self.coachRequestID = nil
                    self.coachRequestTask = nil
                    self.isCoachThinking = false
                }
            }
            do {
                let result: FPLSmartCoachResult
                if !cloudAllowed {
                    result = await self.deterministicCoachResult(query: query) ?? FPLSmartCoachResult(
                        answer: "Cloud Coach is off. I can explain points and supported FPL rules on this device. Enable Cloud Coach for strategic player advice.",
                        confidence: "bounded", evidence: ["No request was sent off this device."],
                        assumptions: ["This question needs evidence or judgment beyond the on-device rules."],
                        actions: ["Enable Cloud Coach only if you want to share the listed team context."],
                        model: nil, verifiedAt: nil, officialDataStatus: "Not checked", source: .localFallback, usage: .zero)
                }
                else if let operation { result = try await operation(query, history) }
                else { result = try await self.askSmartCoach(query: query, history: history) }
                guard self.acceptsCoachReply(requestID, context: context) else { return }
                self.addCoachResult(result, gameweek: context.gameweek)
            } catch {
                guard self.acceptsCoachReply(requestID, context: context) else { return }
                guard !(error is CancellationError),
                      (error as? URLError)?.code != .cancelled else {
                    self.coachStatusMessage = "The request was cancelled. You can ask again."
                    return
                }
                FottyQualityStore.shared.record(
                    category: .coach, name: "model_request", outcome: .failure,
                    details: ["source": "deepseek", "fallback": "local"]
                )
                let fallback = await self.localCoachFallback(query: query, history: history)
                guard self.acceptsCoachReply(requestID, context: context) else { return }
                self.addCoachResult(fallback, gameweek: context.gameweek)
                self.coachStatusMessage = "Showing on-device guidance: \(error.localizedDescription)"
            }
        }
        coachRequestTask = task
        return task
    }

    func cancelCoachRequest() {
        coachRequestID = nil
        coachRequestTask?.cancel()
        coachRequestTask = nil
        isCoachThinking = false
        coachStatusMessage = nil
    }

    private func acceptsCoachReply(_ id: UUID, context: FPLCoachRequestContext) -> Bool {
        guard coachRequestID == id, !Task.isCancelled else { return false }
        guard !coachRequestRequiresCloudConsent || usesAutomatedTestFixture || workspacePersistence.hasSmartCoachConsent else {
            coachStatusMessage = "Cloud coach is off. The pending reply was discarded."
            return false
        }
        guard coachRequestContext == context else {
            coachStatusMessage = "Your team, gameweek or plan changed while the coach was answering. Please ask again so the advice uses the current context."
            return false
        }
        return true
    }

    private func addCoachResult(_ result: FPLSmartCoachResult, gameweek: Int?) {
        addCoachMessage(AICoachMessage(
            sender: .coach, text: result.answer, gameweek: gameweek,
            tag: "\(result.source.rawValue) • \(result.confidence.capitalized) confidence",
            coachCard: result.cardPayload
        ))
    }

    private func deterministicCoachResult(query: String) async -> FPLSmartCoachResult? {
        await FPLAICoachService.deterministicResultIfApplicable(
            userQuery: query, managerSummary: managerSummary, currentGw: currentGameweek,
            picks: officialPicks, scores: playerScores, freeTransfers: freeTransferEstimate,
            live: liveSquadSummary, players: bootstrap?.elements ?? [],
            settings: bootstrap?.gameSettings,
            freshness: FPLAICoachService.isScoringQuery(query) ? scoringFreshness : primaryFreshness,
            publishedGameweek: picksGameweek
        )
    }

    func localCoachFallback(query: String, history: [AICoachMessage]) async -> FPLSmartCoachResult {
        // Error recovery must retain the same published-facts and freshness rules.
        if let fact = await deterministicCoachResult(query: query) { return fact }
        let source = squadSourceTitle
        let local = await FPLAICoachService.askCoach(
            userQuery: query, history: history, managerSummary: managerSummary,
            currentGw: currentGameweek, picks: picks, scores: playerScores,
            recs: transferRecs, captains: captainRecs, rivalGap: rivalGapAnalysis,
            freeTransfers: freeTransferEstimate, live: liveSquadSummary,
            players: bootstrap?.elements ?? []
        )
        return FPLSmartCoachResult(
            answer: "_Advice based on \(source.lowercased())._\n\n" + local,
            confidence: "bounded",
            evidence: ["Current device squad, player ratings, captain shortlist, transfer shortlist, and selected rival context."],
            assumptions: ["The local fallback did not refresh server-side official data or use DeepSeek."],
            actions: ["Confirm availability, free transfers, selling prices, and final changes in official FPL."],
            model: nil, verifiedAt: primaryFreshness?.fetchedAt,
            officialDataStatus: primaryFreshness?.source.displayName ?? "Saved FPL data",
            source: .localFallback, usage: .zero
        )
    }

    public func askSmartCoach(query: String, history: [AICoachMessage]) async throws -> FPLSmartCoachResult {
        #if DEBUG
        if usesAutomatedTestFixture {
            return FPLSmartCoachResult(
                answer: "The test response remains readable at large text sizes.",
                confidence: "high",
                evidence: ["Deterministic on-device UI-test fixture."],
                assumptions: ["No manager account or network request is used."],
                actions: ["Complete the decision in official FPL before the deadline."],
                model: "Fotty UI fixture",
                verifiedAt: Date(timeIntervalSince1970: 0),
                officialDataStatus: "Test fixture",
                source: .rulesEngine,
                usage: .zero
            )
        }
        #endif
        guard currentWorkspaceSeason != nil, let managerId, let managerSummary else {
            throw FPLSmartCoachError.service("Load an FPL manager before asking the coach.")
        }
        let context = coachRequestContext
        if let deterministic = await deterministicCoachResult(query: query) {
            guard !Task.isCancelled, coachRequestContext == context else { throw CancellationError() }
            return deterministic
        }
        guard !Task.isCancelled, coachRequestContext == context else { throw CancellationError() }
        guard workspacePersistence.hasSmartCoachConsent else {
            throw FPLSmartCoachError.service("Cloud Coach is off. Enable it before sending strategic questions.")
        }
        let result = try await FPLSmartCoachService.ask(
            query: query,
            managerID: managerId,
            manager: managerSummary,
            phase: gameweekPhase,
            profile: coachProfile,
            picks: picks,
            squadSource: squadSourceTitle,
            isLocalDraft: isCustomDraft,
            scores: playerScores,
            fixtures: fixtures,
            planningStartGameweek: context.planningGameweek,
            transferRecommendations: transferRecs,
            captainRecommendations: captainRecs,
            freeTransfers: freeTransferEstimate,
            validation: squadValidation,
            routes: planningRoutes,
            live: liveSquadSummary,
            rivalID: selectedRivalID,
            rival: rivalGapAnalysis,
            reviews: gameweekReviews,
            freshness: resourceMetadata,
            history: history
        )
        guard !Task.isCancelled, coachRequestContext == context else { throw CancellationError() }
        return result
    }
}
