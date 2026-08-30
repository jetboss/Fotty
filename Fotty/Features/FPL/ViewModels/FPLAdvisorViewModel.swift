import Foundation
import SwiftUI
import Combine

struct FPLLocalSquadDraft: Codable {
    let picks: [FPLPick]
    let basedOnGameweek: Int?
    let targetGameweek: Int?
    let budgetLimit: Int?
}

private struct FPLCoachRequestContext: Equatable {
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
    @Published public var commandCenterState: FPLCommandCenterState?
    @Published public var planningRoutes: [FPLDraftRoute] = []
    @Published public var savedScenarios: [FPLSavedScenario] = []
    @Published public var optimizedSquads: [FPLOptimizedSquad] = []
    @Published public var gameweekReviews: [FPLGameweekReview] = []
    @Published public var coachProfile: FPLCoachProfile = .default
    @Published public var elementSummaries: [Int: FPLElementSummaryResponse] = [:]
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
    private let draftDefaults: UserDefaults
    private let matchdayContext: FPLMatchdayContextStore
    private var fixtureShowsPublishedSquad = false
    private var coachRequestID: UUID?
    private var coachRequestTask: Task<Void, Never>?

    private var customDraftStorageKey: String? {
        managerId.map { "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.\($0).customDraftPicks" }
    }

    private var coachMessagesStorageKey: String? {
        managerId.map { "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.\($0).coachMessages" }
    }
    
    private func loadCustomDraft() -> FPLLocalSquadDraft? {
        if usesAutomatedTestFixture { return savedSquadDraft }
        guard let key = customDraftStorageKey else { return nil }
        let legacy = draftDefaults.data(forKey: key).flatMap { try? JSONDecoder().decode([FPLPick].self, from: $0) }
        if let data = draftDefaults.data(forKey: key + ".context"),
           let draft = try? JSONDecoder().decode(FPLLocalSquadDraft.self, from: data),
           legacy == nil || legacy == draft.picks {
            return draft
        }
        // Keep the build-43 array readable, including when returning to TestFlight.
        guard let picks = legacy,
              !picks.isEmpty else { return nil }
        return FPLLocalSquadDraft(picks: picks, basedOnGameweek: nil, targetGameweek: nil, budgetLimit: nil)
    }

    var planningGameweek: Int {
        gameweekPhase == .planning
            ? (currentGameweek?.id ?? nextGameweek?.id ?? 1)
            : (nextGameweek?.id ?? ((currentGameweek?.id ?? 0) + 1))
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

    /// Shared by initial/foreground loads and the live refresh. Never deletes a draft.
    func applyPublishedSquad(_ published: FPLManagerPicks?, gameweek: Int?) {
        if let published, let gameweek, gameweek >= (picksGameweek ?? 0) {
            officialPicks = published
            picksGameweek = gameweek
        }
        savedSquadDraft = loadCustomDraft()
        let showPublished = usesAutomatedTestFixture ? fixtureShowsPublishedSquad
            : (customDraftStorageKey.map { draftDefaults.bool(forKey: $0 + ".showPublished") } ?? false)
        if let draft = savedSquadDraft, !showPublished || officialPicks == nil {
            picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: draft.picks)
            isCustomDraft = true
        } else {
            picks = officialPicks
            isCustomDraft = false
        }
    }

    func showPublishedSquad() {
        guard let key = customDraftStorageKey, officialPicks != nil else { return }
        if usesAutomatedTestFixture { fixtureShowsPublishedSquad = true }
        else { draftDefaults.set(true, forKey: key + ".showPublished") }
        applyPublishedSquad(nil, gameweek: nil)
        draftErrorMessage = nil
        recalculateRecommendations()
    }

    func showSavedDraft() {
        guard let key = customDraftStorageKey, loadCustomDraft() != nil else { return }
        if usesAutomatedTestFixture { fixtureShowsPublishedSquad = false }
        else { draftDefaults.set(false, forKey: key + ".showPublished") }
        applyPublishedSquad(nil, gameweek: nil)
        draftErrorMessage = nil
        recalculateRecommendations()
    }
    
    public func loadSavedCoachMessages() {
        coachMessages = []
        guard let coachMessagesStorageKey else { return }
        guard let data = draftDefaults.data(forKey: coachMessagesStorageKey),
              let decoded = try? JSONDecoder().decode([AICoachMessage].self, from: data) else {
            return
        }
        self.coachMessages = decoded
    }
    
    public func saveCoachMessages() {
        guard !usesAutomatedTestFixture else { return }
        guard let coachMessagesStorageKey else { return }
        guard let data = try? JSONEncoder().encode(coachMessages) else { return }
        draftDefaults.set(data, forKey: coachMessagesStorageKey)
    }
    
    public func addCoachMessage(_ msg: AICoachMessage) {
        coachMessages.append(msg)
        saveCoachMessages()
    }
    
    public func clearCoachHistory() {
        cancelCoachRequest()
        coachMessages.removeAll()
        guard !usesAutomatedTestFixture, let coachMessagesStorageKey else { return }
        draftDefaults.removeObject(forKey: coachMessagesStorageKey)
    }
    
    public init(draftDefaults: UserDefaults = .standard) {
        self.draftDefaults = draftDefaults
        self.matchdayContext = draftDefaults === UserDefaults.standard
            ? .shared : FPLMatchdayContextStore(defaults: draftDefaults)
        self._storedManagerId = AppStorage(wrappedValue: 0, "fotty.user.fplManagerId", store: draftDefaults)
        #if DEBUG
        usesAutomatedTestFixture = ProcessInfo.processInfo.environment["FOTTY_FPL_UI_TESTING"] == "1"
        #else
        usesAutomatedTestFixture = false
        #endif

        if storedManagerId <= 0,
           let legacyValue = draftDefaults.string(forKey: "fotty.fpl.managerId"),
           let legacyManagerId = Int(legacyValue),
           legacyManagerId > 0 {
            storedManagerId = legacyManagerId
            draftDefaults.removeObject(forKey: "fotty.fpl.managerId")
        }
        self.managerId = usesAutomatedTestFixture
            ? 9_999_999
            : (storedManagerId > 0 ? storedManagerId : nil)
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
        commandCenterState = nil
        planningRoutes = []
        savedScenarios = []
        optimizedSquads = []
        gameweekReviews = []
        coachProfile = .default
        elementSummaries = [:]
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
        guard let customDraftStorageKey, let coachMessagesStorageKey else { return }
        let defaults = draftDefaults
        let legacyDraftKey = "fotty.fpl.customDraftPicks"
        let legacyCoachKey = "fotty.fpl.coachMessages"

        if defaults.data(forKey: customDraftStorageKey) == nil,
           let legacyDraft = defaults.data(forKey: legacyDraftKey) {
            defaults.set(legacyDraft, forKey: customDraftStorageKey)
        }
        if defaults.data(forKey: coachMessagesStorageKey) == nil,
           let legacyMessages = defaults.data(forKey: legacyCoachKey) {
            defaults.set(legacyMessages, forKey: coachMessagesStorageKey)
        }
        defaults.removeObject(forKey: legacyDraftKey)
        defaults.removeObject(forKey: legacyCoachKey)
    }
    
    public func loadData(isRefresh: Bool = false) async {
        guard let id = managerId, id > 0 else { return }
        let requestID = UUID()
        loadRequestID = requestID
        let refreshStartedAt = Date()
        
        if isRefresh {
            isRefreshing = true
            await FPLService.shared.clearCache()
        } else {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if self.loadRequestID == requestID {
                self.isLoading = false
                self.isRefreshing = false
            }
        }
        
        do {
            async let bootstrapTask = FPLService.shared.fetchBootstrapResource()
            async let fixturesTask = FPLService.shared.fetchFixturesResource()
            async let summaryTask = FPLService.shared.fetchManagerSummaryResource(id: id)
            async let historyTask = FPLService.shared.fetchManagerHistoryResource(id: id)

            let (bootstrapResource, fixtureResource, summaryResource, historyResource) = try await (
                bootstrapTask,
                fixturesTask,
                summaryTask,
                historyTask
            )
            guard !Task.isCancelled, loadRequestID == requestID, managerId == id else { return }

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
            let activeGameweek = officialCurrent?.finished == true
                ? (officialNext ?? officialCurrent)
                : (officialCurrent ?? officialNext)
            let fetchedPhase = FPLGameweekPhase.resolve(
                gameweek: activeGameweek,
                fixtures: fData
            )

            var fetchedOfficialPicks: FPLManagerPicks?
            var fetchedPicksGameweek: Int?
            var fetchedEventLive: FPLEventLiveResponse?
            if let gameweekID = activeGameweek?.id {
                do {
                    let picksResource = try await FPLService.shared.fetchPicksResource(
                        managerId: id,
                        gameweek: gameweekID
                    )
                    fetchedOfficialPicks = picksResource.value
                    fetchedPicksGameweek = gameweekID
                    fetchedMetadata["picks"] = picksResource.metadata
                } catch {
                    if gameweekID > 1,
                       let previous = try? await FPLService.shared.fetchPicksResource(
                        managerId: id,
                        gameweek: gameweekID - 1
                       ) {
                        fetchedOfficialPicks = previous.value
                        fetchedPicksGameweek = gameweekID - 1
                        fetchedMetadata["picks"] = previous.metadata
                    }
                }

                if fetchedPhase != .planning,
                   let liveResource = try? await FPLService.shared.fetchEventLiveResource(gameweek: gameweekID) {
                    fetchedEventLive = liveResource.value
                    fetchedMetadata["eventLive"] = liveResource.metadata
                }
            }
            guard !Task.isCancelled, loadRequestID == requestID, managerId == id else { return }

            self.bootstrap = bData
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
                    budget: budget
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
            self.fixtureGameweeks = Array(planningStart..<(planningStart + 5))
            self.freeTransferEstimate = FPLFreeTransferEstimator.estimate(
                history: historyResource.value,
                targetGameweek: planningStart,
                startedEvent: summaryData.startedEvent,
                maximum: bData.gameSettings?.maximumFreeTransfers ?? FPLTransferRules.maximumBankedFreeTransfers
            )
            recalculateRecommendations()
            rebuildDecisionState(rebuildOptimizer: true)

            await recordLatestConfirmedReview(
                managerID: id,
                requestID: requestID,
                bootstrap: bData,
                fixtures: fData,
                history: historyResource.value
            )
            guard !Task.isCancelled, loadRequestID == requestID, managerId == id else { return }

            let classicLeagues = summaryData.leagues?.classic ?? []
            if let firstLeague = classicLeagues.first(where: \.isPrivateMiniLeague) ?? classicLeagues.first {
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
            if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
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
        guard let completed = bootstrap.events
            .filter({ $0.finished && $0.dataChecked == true })
            .max(by: { $0.id < $1.id }),
              history.current.contains(where: { $0.event == completed.id }) else { return }
        do {
            async let picksResource = FPLService.shared.fetchPicksResource(
                managerId: managerID,
                gameweek: completed.id
            )
            async let liveResource = FPLService.shared.fetchEventLiveResource(gameweek: completed.id)
            let (officialPicks, officialLive) = try await (picksResource, liveResource)
            guard !Task.isCancelled, loadRequestID == requestID, managerId == managerID else { return }
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
                gameweekReviews = FPLReviewStore.upsert(review, managerID: managerID)
            }
        } catch {
            // The next refresh can retry. A review is never synthesized without
            // both the confirmed manager history and official event-live data.
        }
    }
    
    public func loadLeagueStandings(leagueId: Int, page: Int = 1, appending: Bool = false) async {
        guard page >= 1 else { return }
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
            guard !Task.isCancelled, leagueRequestID == requestID, selectedLeagueId == leagueId else { return }
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
            guard !Task.isCancelled, leagueRequestID == requestID else { return }
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
        guard let gwId = currentGameweek?.id,
              let standings = leagueStandings?.standings.results else {
            rivalErrorMessage = "Load a current gameweek and mini-league before choosing a rival."
            return
        }
        guard gameweekPhase != .planning else {
            rivalErrorMessage = "Rival squads publish after the gameweek deadline. Standings remain available before then."
            return
        }
        isRivalLoading = true
        rivalErrorMessage = nil
        self.rivalManagerName = "\(entry.entryName) (\(entry.managerName))"
        self.selectedRivalID = entry.entry
        let selectionID = managerSelectionID
        let requestID = UUID()
        rivalRequestID = requestID
        defer { if rivalRequestID == requestID { isRivalLoading = false } }

        let myEntry = standings.first(where: { $0.entry == managerId })
            ?? managerStandingFallback()
        
        do {
            let rivalPicksData = try await FPLService.shared.fetchPicks(managerId: entry.entry, gameweek: gwId)
            guard !Task.isCancelled, managerSelectionID == selectionID, rivalRequestID == requestID else { return }
            self.rivalPicks = rivalPicksData
            
            if let myE = myEntry, let myP = officialPicks, picksGameweek == gwId {
                self.rivalGapAnalysis = FPLAdvisorEngine.analyzeRivalGap(
                    myEntry: myE,
                    rivalEntry: entry,
                    myPicks: myP.picks,
                    rivalPicks: rivalPicksData.picks,
                    allScores: playerScores,
                    gameweek: gwId,
                    phase: gameweekPhase,
                    eventLive: eventLive,
                    fixtures: fixtures
                )
            } else {
                self.rivalGapAnalysis = nil
                self.rivalErrorMessage = "Your position was not available in the loaded league page."
            }
            rebuildDecisionState(rebuildOptimizer: false)
            
            self.isShowingRivalSheet = true
        } catch {
            guard !Task.isCancelled, managerSelectionID == selectionID, rivalRequestID == requestID else { return }
            self.rivalGapAnalysis = nil
            self.rivalErrorMessage = "That published rival squad is not available yet. Try again after the deadline or refresh the league."
        }
    }

    private func managerStandingFallback() -> FPLLeagueStandingEntry? {
        guard let managerId, let managerSummary else { return nil }
        let league = managerSummary.leagues?.classic.first(where: { $0.id == selectedLeagueId })
        return FPLLeagueStandingEntry(
            entry: managerId,
            entryName: managerSummary.name,
            playerName: managerSummary.fullName,
            rank: league?.entryRank ?? managerSummary.summaryOverallRank ?? 0,
            lastRank: league?.entryLastRank ?? 0,
            total: managerSummary.summaryOverallPoints ?? 0,
            eventTotal: managerSummary.summaryEventPoints ?? 0
        )
    }
    
    // MARK: - Squad Customization & Recalculation
    
    @discardableResult
    public func updateUserSquad(picks: [FPLPick]) -> Bool {
        guard let bootstrap, let key = customDraftStorageKey else {
            draftErrorMessage = "Load your manager and player data before saving a draft."
            return false
        }
        let validation = FPLSquadValidator.validate(
            picks: picks,
            players: bootstrap.elements,
            elementTypes: bootstrap.elementTypes,
            gameSettings: bootstrap.gameSettings,
            budgetLimit: isCustomDraft ? (savedSquadDraft?.budgetLimit ?? draftBudgetLimit) : draftBudgetLimit
        )
        guard validation.isValid else {
            self.draftErrorMessage = validation.issues.first(where: { $0.severity == .error })?.message
            return false
        }
        let draft = FPLLocalSquadDraft(
            picks: picks,
            basedOnGameweek: isCustomDraft ? (savedSquadDraft?.basedOnGameweek ?? picksGameweek) : picksGameweek,
            targetGameweek: planningGameweek,
            budgetLimit: isCustomDraft ? (savedSquadDraft?.budgetLimit ?? draftBudgetLimit) : draftBudgetLimit
        )
        do {
            let encoded = try JSONEncoder().encode(picks)
            let context = try JSONEncoder().encode(draft)
            if !usesAutomatedTestFixture {
                draftDefaults.set(encoded, forKey: key)
                draftDefaults.set(context, forKey: key + ".context")
                draftDefaults.set(false, forKey: key + ".showPublished")
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
    
    public func recalculateRecommendations() {
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
        rebuildDecisionState(rebuildOptimizer: false)
    }

    public func rebuildDecisionState(rebuildOptimizer: Bool) {
        guard let bootstrap else { return }
        let planningStart = gameweekPhase == .planning
            ? (currentGameweek?.id ?? nextGameweek?.id ?? 1)
            : (nextGameweek?.id ?? ((currentGameweek?.id ?? 0) + 1))

        if let currentPicks = picks {
            squadValidation = FPLSquadValidator.validate(
                picks: currentPicks.picks,
                players: bootstrap.elements,
                elementTypes: bootstrap.elementTypes,
                gameSettings: bootstrap.gameSettings,
                budgetLimit: isCustomDraft ? (savedSquadDraft?.budgetLimit ?? draftBudgetLimit) : nil
            )
        }
        // Never combine an older fallback lineup or a local plan with this
        // game's live statistics, even while the draft is visible in Squad.
        if let currentGameweek, picksGameweek == currentGameweek.id,
           let officialPicks, let eventLive {
            liveSquadSummary = FPLDecisionEngine.liveSquadSummary(
                gameweek: currentGameweek,
                picks: officialPicks,
                live: eventLive,
                players: bootstrap.elements,
                teams: bootstrap.teams,
                fixtures: fixtures
            )
        } else {
            liveSquadSummary = nil
        }

        planningRoutes = FPLPlannerEngine.routes(
            recommendations: transferRecs,
            fixtures: fixtures,
            startGameweek: planningStart,
            horizon: coachProfile.planningHorizon,
            freeTransfers: freeTransferEstimate,
            gameweek: currentGameweek
        )
        commandCenterState = FPLDecisionEngine.commandCenter(
            phase: gameweekPhase,
            gameweek: currentGameweek,
            picks: gameweekPhase == .planning ? picks : (picksGameweek == currentGameweek?.id ? officialPicks : nil),
            scores: playerScores,
            validation: squadValidation,
            freeTransfers: freeTransferEstimate,
            live: liveSquadSummary,
            history: managerHistory
        )

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

        if rebuildOptimizer {
            let budget = draftBudgetLimit
                ?? managerSummary?.lastDeadlineValue
                ?? bootstrap.gameSettings?.squadTotalSpend
                ?? 1_000
            optimizedSquads = FPLSquadOptimizer.generate(
                scores: playerScores,
                fixtures: fixtures,
                elementTypes: bootstrap.elementTypes,
                settings: bootstrap.gameSettings,
                startGameweek: planningStart,
                horizon: coachProfile.planningHorizon,
                budget: budget
            )
        }
    }

    public func saveScenario(name: String, route: FPLDraftRoute, gameweek: Int) {
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
        guard let managerId else { return }
        savedScenarios = FPLScenarioStore.remove(id: id, managerID: managerId)
    }

    public func fetchElementSummary(playerID: Int) async -> FPLElementSummaryResponse? {
        if let cached = elementSummaries[playerID] { return cached }
        guard !usesAutomatedTestFixture else { return nil }
        do {
            let resource = try await FPLService.shared.fetchElementSummaryResource(playerId: playerID)
            elementSummaries[playerID] = resource.value
            resourceMetadata["element-\(playerID)"] = resource.metadata
            return resource.value
        } catch {
            return nil
        }
    }

    public func refreshMatchdayData() async {
        guard !isLoading, !isRefreshing, let managerId,
              let gameweek = currentGameweek,
              gameweekPhase != .planning else { return }
        let selectionID = managerSelectionID
        let loadID = loadRequestID
        do {
            async let liveResource = FPLService.shared.fetchEventLiveResource(gameweek: gameweek.id)
            async let picksResource = FPLService.shared.fetchPicksResource(
                managerId: managerId,
                gameweek: gameweek.id
            )
            let (live, officialPicks) = try await (liveResource, picksResource)
            guard !Task.isCancelled, managerSelectionID == selectionID, loadRequestID == loadID,
                  self.managerId == managerId, self.currentGameweek?.id == gameweek.id else { return }
            eventLive = live.value
            applyPublishedSquad(officialPicks.value, gameweek: gameweek.id)
            resourceMetadata["eventLive"] = live.metadata
            resourceMetadata["picks"] = officialPicks.metadata
            gameweekPhase = FPLGameweekPhase.resolve(gameweek: gameweek, fixtures: fixtures)
            recalculateRecommendations()
            rebuildDecisionState(rebuildOptimizer: false)
        } catch {
            // Keep the last labeled snapshot on screen. Pull-to-refresh remains
            // available and the next timer tick will retry.
        }
    }

    public func updateCoachProfile(_ profile: FPLCoachProfile) {
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
        guard let live = resourceMetadata["eventLive"], let picks = resourceMetadata["picks"] else { return nil }
        return live.fetchedAt < picks.fetchedAt ? live : picks
    }

    public func recordDecision(
        kind: FPLDecisionJournalEntry.Kind,
        title: String,
        rationale: String,
        expectedOutcome: String,
        source: String,
        estimatedPointCost: Int? = nil
    ) {
        guard let managerId else { return }
        let gameweek = currentGameweek?.id ?? nextGameweek?.id ?? 1
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
        decisionJournalEntries = FPLDecisionJournalStore.upsert(entry, managerID: managerId)
    }

    public func recordRouteDecision(_ route: FPLDraftRoute) {
        let moveDescription = route.transfers.isEmpty
            ? "Roll the transfer"
            : route.transfers.map { "\($0.playerOut.player.webName) → \($0.playerIn.player.webName)" }.joined(separator: ", ")
        recordDecision(
            kind: route.transfers.isEmpty ? .roll : .transfer,
            title: route.name,
            rationale: "\(moveDescription). \(route.explanation)",
            expectedOutcome: "Modeled \(route.projectedGain >= 0 ? "+" : "")\(route.projectedGain.formatted(.number.precision(.fractionLength(1)))) points over \(coachProfile.planningHorizon) gameweeks after the estimated hit.",
            source: "Transfer Lab",
            estimatedPointCost: route.hitCost
        )
    }

    public func recordCoachDecision(_ card: FPLCoachCardPayload) {
        recordDecision(
            kind: .strategy,
            title: "Smart Coach recommendation",
            rationale: card.answer,
            expectedOutcome: card.verifyBeforeDeadline.first ?? "Revisit this advice after the gameweek.",
            source: card.source
        )
    }

    public func updateDecisionOutcome(
        id: String,
        outcome: FPLDecisionJournalEntry.Outcome,
        note: String = ""
    ) {
        guard let managerId,
              let existing = decisionJournalEntries.first(where: { $0.id == id }) else { return }
        var updated = existing
        updated.outcome = outcome
        updated.outcomeNote = note
        updated.updatedAt = Date()
        decisionJournalEntries = FPLDecisionJournalStore.upsert(updated, managerID: managerId)
    }

    public func removeDecision(id: String) {
        guard let managerId else { return }
        decisionJournalEntries = FPLDecisionJournalStore.remove(id: id, managerID: managerId)
    }

    private var coachRequestContext: FPLCoachRequestContext {
        FPLCoachRequestContext(
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
        guard !query.isEmpty, !isCoachThinking,
              usesAutomatedTestFixture || draftDefaults.bool(forKey: "fotty.fpl.smartCoachConsent") else { return nil }
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
                if let operation { result = try await operation(query, history) }
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
        guard usesAutomatedTestFixture || draftDefaults.bool(forKey: "fotty.fpl.smartCoachConsent") else {
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
            officialDataStatus: primaryFreshness?.source.rawValue ?? "Device snapshot",
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
        guard let managerId, let managerSummary else {
            throw FPLSmartCoachError.service("Load an FPL manager before asking the coach.")
        }
        let context = coachRequestContext
        if let deterministic = await deterministicCoachResult(query: query) {
            guard !Task.isCancelled, coachRequestContext == context else { throw CancellationError() }
            return deterministic
        }
        guard !Task.isCancelled, coachRequestContext == context else { throw CancellationError() }
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
