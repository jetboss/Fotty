import Foundation

public enum FPLSeasonIdentifier {
    public static func currentLabel(at date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let startYear = month >= 7 ? year : year - 1
        return String(format: "%04d-%02d", startYear, (startYear + 1) % 100)
    }

    public static func label(from events: [FPLGameweek], fallback: Date = Date()) -> String {
        guard let firstDeadline = events.compactMap(\.deadlineDate).min() else {
            return currentLabel(at: fallback)
        }
        return currentLabel(at: firstDeadline)
    }
}

// MARK: - FPL Bootstrap Static Response

public struct FPLBootstrapResponse: Decodable, Sendable {
    public let events: [FPLGameweek]
    public let elements: [FPLPlayer]
    public let teams: [FPLTeam]
    public let elementTypes: [FPLElementType]
    public let totalPlayers: Int
    public let gameSettings: FPLGameSettings?
    public let chips: [FPLChipDefinition]?
    
    enum CodingKeys: String, CodingKey {
        case events
        case elements
        case teams
        case elementTypes = "element_types"
        case totalPlayers = "total_players"
        case gameSettings = "game_settings"
        case chips
    }
}

// MARK: - Gameweek

public struct FPLGameweek: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let deadlineTime: String
    public let deadlineTimeEpoch: Int
    public let averageEntryScore: Int?
    public let finished: Bool
    public let isPrevious: Bool
    public let isCurrent: Bool
    public let isNext: Bool
    public let mostSelected: Int?
    public let mostTransferredIn: Int?
    public let topElement: Int?
    public let transfersMade: Int?
    public let mostCaptained: Int?
    public let dataChecked: Bool?
    public let canManage: Bool?
    public let released: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, name, finished
        case deadlineTime = "deadline_time"
        case deadlineTimeEpoch = "deadline_time_epoch"
        case averageEntryScore = "average_entry_score"
        case isPrevious = "is_previous"
        case isCurrent = "is_current"
        case isNext = "is_next"
        case mostSelected = "most_selected"
        case mostTransferredIn = "most_transferred_in"
        case topElement = "top_element"
        case transfersMade = "transfers_made"
        case mostCaptained = "most_captained"
        case dataChecked = "data_checked"
        case canManage = "can_manage"
        case released
    }

    public var deadlineDate: Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: deadlineTime) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: deadlineTime)
    }

    public func isBeforeDeadline(at date: Date = Date()) -> Bool {
        guard let deadlineDate else { return false }
        return date < deadlineDate
    }
}

// MARK: - Player (Element)

public struct FPLPlayer: Decodable, Identifiable, Sendable {
    public let id: Int
    public let code: Int?
    public let photo: String?
    public let webName: String
    public let firstName: String
    public let secondName: String
    public let team: Int
    public let teamCode: Int
    public let elementType: Int
    public let nowCost: Int
    public let costChangeEvent: Int
    public let costChangeEventFall: Int
    public let selectedByPercent: String
    public let form: String
    public let pointsPerGame: String
    public let totalPoints: Int
    public let eventPoints: Int
    public let minutes: Int
    public let goalsScored: Int
    public let assists: Int
    public let cleanSheets: Int
    public let goalsConceded: Int
    public let yellowCards: Int
    public let redCards: Int
    public let saves: Int
    public let bonus: Int
    public let bps: Int
    public let influence: String
    public let creativity: String
    public let threat: String
    public let ictIndex: String
    public let starts: Int
    public let transfersInEvent: Int
    public let transfersOutEvent: Int
    public let status: String
    public let news: String
    public let chanceOfPlayingThisRound: Int?
    public let chanceOfPlayingNextRound: Int?
    public let expectedGoals: String?
    public let expectedAssists: String?
    public let expectedGoalInvolvements: String?
    public let expectedGoalsConceded: String?
    public let expectedPointsThis: String?
    public let expectedPointsNext: String?
    public let expectedGoalsPer90: Double?
    public let expectedAssistsPer90: Double?
    public let expectedGoalInvolvementsPer90: Double?
    public let expectedGoalsConcededPer90: Double?
    public let defensiveContribution: Int?
    public let defensiveContributionPer90: Double?
    public let priceChangeCalibrating: Bool?
    public let priceChangeHourlyRate: Int?
    public let priceChangePercent: String?
    public let priceChangeProjections: [FPLPriceChangeProjection]?
    public let priceChangeLockedUntil: String?
    public let penaltiesOrder: Int?
    public let directFreekicksOrder: Int?
    public let cornersAndIndirectFreekicksOrder: Int?
    public let canSelect: Bool?
    public let canTransact: Bool?
    public let removed: Bool?
    
    public var xGValue: Double { Double(expectedGoals ?? "0") ?? 0.0 }
    public var xAValue: Double { Double(expectedAssists ?? "0") ?? 0.0 }
    public var xGIValue: Double { Double(expectedGoalInvolvements ?? "0") ?? 0.0 }
    public var xGCValue: Double { Double(expectedGoalsConceded ?? "0") ?? 0.0 }
    public var officialExpectedPointsNext: Double? { expectedPointsNext.flatMap(Double.init) }
    public var officialPriceChangePercent: Double? { priceChangePercent.flatMap(Double.init) }
    
    public var formattedCost: String {
        String(format: "£%.1fm", Double(nowCost) / 10.0)
    }
    
    public var positionName: String {
        switch elementType {
        case 1: return "GKP"
        case 2: return "DEF"
        case 3: return "MID"
        case 4: return "FWD"
        default: return "???"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, code, photo, team, status, news, minutes, bonus, bps
        case webName = "web_name"
        case firstName = "first_name"
        case secondName = "second_name"
        case teamCode = "team_code"
        case elementType = "element_type"
        case nowCost = "now_cost"
        case costChangeEvent = "cost_change_event"
        case costChangeEventFall = "cost_change_event_fall"
        case selectedByPercent = "selected_by_percent"
        case form
        case pointsPerGame = "points_per_game"
        case totalPoints = "total_points"
        case eventPoints = "event_points"
        case goalsScored = "goals_scored"
        case assists
        case cleanSheets = "clean_sheets"
        case goalsConceded = "goals_conceded"
        case yellowCards = "yellow_cards"
        case redCards = "red_cards"
        case saves
        case influence, creativity, threat
        case ictIndex = "ict_index"
        case starts
        case transfersInEvent = "transfers_in_event"
        case transfersOutEvent = "transfers_out_event"
        case chanceOfPlayingThisRound = "chance_of_playing_this_round"
        case chanceOfPlayingNextRound = "chance_of_playing_next_round"
        case expectedGoals = "expected_goals"
        case expectedAssists = "expected_assists"
        case expectedGoalInvolvements = "expected_goal_involvements"
        case expectedGoalsConceded = "expected_goals_conceded"
        case expectedPointsThis = "ep_this"
        case expectedPointsNext = "ep_next"
        case expectedGoalsPer90 = "expected_goals_per_90"
        case expectedAssistsPer90 = "expected_assists_per_90"
        case expectedGoalInvolvementsPer90 = "expected_goal_involvements_per_90"
        case expectedGoalsConcededPer90 = "expected_goals_conceded_per_90"
        case defensiveContribution = "defensive_contribution"
        case defensiveContributionPer90 = "defensive_contribution_per_90"
        case priceChangeCalibrating = "price_change_calibrating"
        case priceChangeHourlyRate = "price_change_hourly_rate"
        case priceChangePercent = "price_change_percent"
        case priceChangeProjections = "price_change_projections"
        case priceChangeLockedUntil = "price_change_locked_until"
        case penaltiesOrder = "penalties_order"
        case directFreekicksOrder = "direct_freekicks_order"
        case cornersAndIndirectFreekicksOrder = "corners_and_indirect_freekicks_order"
        case canSelect = "can_select"
        case canTransact = "can_transact"
        case removed
    }
}

public struct FPLPriceChangeProjection: Decodable, Sendable {
    public let offset: Int
    public let projectedPercent: String
    public let likelihood: Int

    public var projectedPercentValue: Double {
        Double(projectedPercent) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case offset, likelihood
        case projectedPercent = "projected_percent"
    }
}

// MARK: - Team

public struct FPLTeam: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let shortName: String
    public let code: Int
    public let strength: Int?
    public let strengthOverallHome: Int?
    public let strengthOverallAway: Int?
    public let strengthAttackHome: Int?
    public let strengthAttackAway: Int?
    public let strengthDefenceHome: Int?
    public let strengthDefenceAway: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, code, strength
        case shortName = "short_name"
        case strengthOverallHome = "strength_overall_home"
        case strengthOverallAway = "strength_overall_away"
        case strengthAttackHome = "strength_attack_home"
        case strengthAttackAway = "strength_attack_away"
        case strengthDefenceHome = "strength_defence_home"
        case strengthDefenceAway = "strength_defence_away"
    }
}

// MARK: - Element Type (Position)

public struct FPLElementType: Decodable, Identifiable, Sendable {
    public let id: Int
    public let singularName: String
    public let singularNameShort: String
    public let pluralName: String
    public let pluralNameShort: String
    public let squadSelect: Int?
    public let squadMinPlay: Int?
    public let squadMaxPlay: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case singularName = "singular_name"
        case singularNameShort = "singular_name_short"
        case pluralName = "plural_name"
        case pluralNameShort = "plural_name_short"
        case squadSelect = "squad_select"
        case squadMinPlay = "squad_min_play"
        case squadMaxPlay = "squad_max_play"
    }
}

// MARK: - Fixture

public struct FPLFixture: Decodable, Identifiable, Sendable {
    public let id: Int
    public let event: Int?
    public let finished: Bool
    public let started: Bool?
    public let finishedProvisional: Bool?
    public let minutes: Int?
    public let kickoffTime: String?
    public let teamH: Int
    public let teamA: Int
    public let teamHScore: Int?
    public let teamAScore: Int?
    public let teamHDifficulty: Int
    public let teamADifficulty: Int

    public var kickoffDate: Date? {
        guard let kickoffTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: kickoffTime) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: kickoffTime)
    }

    public var isActivelyPlaying: Bool {
        started == true && !finished && finishedProvisional != true
    }
    
    enum CodingKeys: String, CodingKey {
        case id, event, finished, started, minutes
        case finishedProvisional = "finished_provisional"
        case kickoffTime = "kickoff_time"
        case teamH = "team_h"
        case teamA = "team_a"
        case teamHScore = "team_h_score"
        case teamAScore = "team_a_score"
        case teamHDifficulty = "team_h_difficulty"
        case teamADifficulty = "team_a_difficulty"
    }
}

// MARK: - Manager Summary

public struct FPLManagerSummary: Decodable, Identifiable, Sendable {
    public let id: Int
    public let firstName: String
    public let lastName: String
    public let name: String
    public let summaryOverallPoints: Int?
    public let summaryOverallRank: Int?
    public let summaryEventPoints: Int?
    public let summaryEventRank: Int?
    public let currentEvent: Int?
    public let startedEvent: Int?
    public let lastDeadlineBank: Int?
    public let lastDeadlineValue: Int?
    public let lastDeadlineTotalTransfers: Int?
    public let leagues: FPLManagerLeaguesContainer?
    
    public var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, leagues
        case firstName = "player_first_name"
        case lastName = "player_last_name"
        case summaryOverallPoints = "summary_overall_points"
        case summaryOverallRank = "summary_overall_rank"
        case summaryEventPoints = "summary_event_points"
        case summaryEventRank = "summary_event_rank"
        case currentEvent = "current_event"
        case startedEvent = "started_event"
        case lastDeadlineBank = "last_deadline_bank"
        case lastDeadlineValue = "last_deadline_value"
        case lastDeadlineTotalTransfers = "last_deadline_total_transfers"
    }
}

public struct FPLManagerLeaguesContainer: Decodable, Sendable {
    public let classic: [FPLLeagueSummary]
}

public struct FPLLeagueSummary: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let leagueType: String?
    public let entryRank: Int?
    public let entryLastRank: Int?

    public var isPrivateMiniLeague: Bool {
        leagueType == "x"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case leagueType = "league_type"
        case entryRank = "entry_rank"
        case entryLastRank = "entry_last_rank"
    }
}

// MARK: - Manager Picks

public struct FPLManagerPicks: Codable, Sendable {
    public let activeChip: String?
    public let entryHistory: FPLGameweekHistory?
    public let picks: [FPLPick]
    public let automaticSubs: [FPLAutomaticSub]

    public init(
        activeChip: String?,
        entryHistory: FPLGameweekHistory?,
        picks: [FPLPick],
        automaticSubs: [FPLAutomaticSub] = []
    ) {
        self.activeChip = activeChip
        self.entryHistory = entryHistory
        self.picks = picks
        self.automaticSubs = automaticSubs
    }
    
    enum CodingKeys: String, CodingKey {
        case activeChip = "active_chip"
        case entryHistory = "entry_history"
        case picks
        case automaticSubs = "automatic_subs"
    }
}

public struct FPLGameweekHistory: Codable, Sendable {
    public let event: Int?
    public let points: Int?
    public let totalPoints: Int?
    public let rank: Int?
    public let overallRank: Int?
    public let bank: Int?
    public let value: Int?
    public let eventTransfers: Int?
    public let eventTransfersCost: Int?
    public let pointsOnBench: Int?

    public init(
        event: Int?,
        points: Int?,
        totalPoints: Int?,
        rank: Int?,
        overallRank: Int?,
        bank: Int?,
        value: Int?,
        eventTransfers: Int?,
        eventTransfersCost: Int?,
        pointsOnBench: Int?
    ) {
        self.event = event
        self.points = points
        self.totalPoints = totalPoints
        self.rank = rank
        self.overallRank = overallRank
        self.bank = bank
        self.value = value
        self.eventTransfers = eventTransfers
        self.eventTransfersCost = eventTransfersCost
        self.pointsOnBench = pointsOnBench
    }
    
    enum CodingKeys: String, CodingKey {
        case event, points, rank, bank, value
        case totalPoints = "total_points"
        case overallRank = "overall_rank"
        case eventTransfers = "event_transfers"
        case eventTransfersCost = "event_transfers_cost"
        case pointsOnBench = "points_on_bench"
    }
}

public struct FPLPick: Codable, Identifiable, Sendable, Equatable {
    public var id: Int { element }
    public let element: Int
    public let position: Int
    public let multiplier: Int
    public let isCaptain: Bool
    public let isViceCaptain: Bool
    public let purchasePrice: Int?
    public let sellingPrice: Int?
    public let elementType: Int?
    
    public init(
        element: Int,
        position: Int,
        multiplier: Int,
        isCaptain: Bool,
        isViceCaptain: Bool,
        purchasePrice: Int? = nil,
        sellingPrice: Int? = nil,
        elementType: Int? = nil
    ) {
        self.element = element
        self.position = position
        self.multiplier = multiplier
        self.isCaptain = isCaptain
        self.isViceCaptain = isViceCaptain
        self.purchasePrice = purchasePrice
        self.sellingPrice = sellingPrice
        self.elementType = elementType
    }
    
    enum CodingKeys: String, CodingKey {
        case element, position, multiplier
        case isCaptain = "is_captain"
        case isViceCaptain = "is_vice_captain"
        case purchasePrice = "purchase_price"
        case sellingPrice = "selling_price"
        case elementType = "element_type"
    }
}

public struct FPLAutomaticSub: Codable, Sendable, Equatable {
    public let entry: Int?
    public let elementIn: Int
    public let elementOut: Int
    public let event: Int?

    enum CodingKeys: String, CodingKey {
        case entry, event
        case elementIn = "element_in"
        case elementOut = "element_out"
    }
}

// MARK: - League Standings Response

public struct FPLLeagueStandingsResponse: Decodable, Sendable {
    public let league: FPLLeagueDetail
    public let standings: FPLLeagueStandingsTable

    public init(league: FPLLeagueDetail, standings: FPLLeagueStandingsTable) {
        self.league = league
        self.standings = standings
    }
}

public struct FPLLeagueDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let created: String
    public let leagueType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, created
        case leagueType = "league_type"
    }
}

public struct FPLLeagueStandingsTable: Decodable, Sendable {
    public let results: [FPLLeagueStandingEntry]
    public let hasNext: Bool
    public let page: Int

    public init(results: [FPLLeagueStandingEntry], hasNext: Bool, page: Int) {
        self.results = results
        self.hasNext = hasNext
        self.page = page
    }

    enum CodingKeys: String, CodingKey {
        case results, page
        case hasNext = "has_next"
    }
}

public struct FPLLeagueStandingEntry: Decodable, Identifiable, Sendable {
    public var id: Int { entry }
    public let entry: Int
    public let entryName: String
    public let playerName: String
    public let rank: Int
    public let lastRank: Int
    public let total: Int
    public let eventTotal: Int

    public var managerName: String { playerName }

    enum CodingKeys: String, CodingKey {
        case entry, rank, total
        case entryName = "entry_name"
        case playerName = "player_name"
        case lastRank = "last_rank"
        case eventTotal = "event_total"
    }
}

// MARK: - Player Picker Context

public struct PlayerPickerContext: Identifiable, Sendable {
    public var id: String { "\(position)-\(elementType)-\(currentElementId)" }
    public let position: Int
    public let elementType: Int
    public let currentElementId: Int
    
    public init(position: Int, elementType: Int, currentElementId: Int) {
        self.position = position
        self.elementType = elementType
        self.currentElementId = currentElementId
    }
}
