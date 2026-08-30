import Foundation

// MARK: - Bootstrap rules and chips

public struct FPLGameSettings: Decodable, Sendable {
    public let squadPlay: Int?
    public let squadSize: Int?
    public let squadTeamLimit: Int?
    public let squadTotalSpend: Int?
    public let transfersCap: Int?
    public let maxExtraFreeTransfers: Int?
    public let currencyMultiplier: Int?

    public var maximumFreeTransfers: Int {
        max(1, (maxExtraFreeTransfers ?? 4) + 1)
    }

    enum CodingKeys: String, CodingKey {
        case squadPlay = "squad_squadplay"
        case squadSize = "squad_squadsize"
        case squadTeamLimit = "squad_team_limit"
        case squadTotalSpend = "squad_total_spend"
        case transfersCap = "transfers_cap"
        case maxExtraFreeTransfers = "max_extra_free_transfers"
        case currencyMultiplier = "ui_currency_multiplier"
    }
}

public struct FPLChipDefinition: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let number: Int
    public let startEvent: Int
    public let stopEvent: Int
    public let chipType: String

    enum CodingKeys: String, CodingKey {
        case id, name, number
        case startEvent = "start_event"
        case stopEvent = "stop_event"
        case chipType = "chip_type"
    }
}

// MARK: - Official manager history

public struct FPLManagerHistoryResponse: Decodable, Sendable {
    public let current: [FPLGameweekHistory]
    public let past: [FPLPastSeason]
    public let chips: [FPLChipUsage]
}

public struct FPLPastSeason: Decodable, Sendable {
    public let seasonName: String
    public let totalPoints: Int
    public let rank: Int?

    enum CodingKeys: String, CodingKey {
        case seasonName = "season_name"
        case totalPoints = "total_points"
        case rank
    }
}

public struct FPLChipUsage: Decodable, Sendable {
    public let name: String
    public let time: String?
    public let event: Int
}

// MARK: - Official event-live response

public struct FPLEventLiveResponse: Decodable, Sendable {
    public let elements: [FPLLiveElement]
}

public struct FPLLiveElement: Decodable, Identifiable, Sendable {
    public let id: Int
    public let stats: FPLLivePlayerStats
    public let explain: [FPLLiveFixtureExplanation]
    public let modified: Bool?
}

public struct FPLLivePlayerStats: Decodable, Sendable {
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
    public let defensiveContribution: Int?
    public let totalPoints: Int
    public let played: Bool?

    enum CodingKeys: String, CodingKey {
        case minutes, assists, saves, bonus, bps, played
        case goalsScored = "goals_scored"
        case cleanSheets = "clean_sheets"
        case goalsConceded = "goals_conceded"
        case yellowCards = "yellow_cards"
        case redCards = "red_cards"
        case defensiveContribution = "defensive_contribution"
        case totalPoints = "total_points"
    }
}

public struct FPLLiveFixtureExplanation: Decodable, Sendable {
    public let fixture: Int
    public let stats: [FPLLivePointsExplanation]
}

public struct FPLLivePointsExplanation: Decodable, Sendable {
    public let identifier: String
    public let points: Int
    public let value: Int
    public let pointsModification: Int?

    enum CodingKeys: String, CodingKey {
        case identifier, points, value
        case pointsModification = "points_modification"
    }
}

// MARK: - Official element summary

public struct FPLElementSummaryResponse: Decodable, Sendable {
    public let fixtures: [FPLElementFixture]
    public let history: [FPLElementHistory]
    public let historyPast: [FPLElementPastSeason]

    enum CodingKeys: String, CodingKey {
        case fixtures, history
        case historyPast = "history_past"
    }
}

public struct FPLElementFixture: Decodable, Identifiable, Sendable {
    public let id: Int
    public let event: Int?
    public let eventName: String?
    public let isHome: Bool
    public let difficulty: Int
    public let kickoffTime: String?
    public let teamH: Int
    public let teamA: Int

    enum CodingKeys: String, CodingKey {
        case id, event, difficulty
        case eventName = "event_name"
        case isHome = "is_home"
        case kickoffTime = "kickoff_time"
        case teamH = "team_h"
        case teamA = "team_a"
    }
}

public struct FPLElementHistory: Decodable, Identifiable, Sendable {
    public var id: Int { fixture }
    public let fixture: Int
    public let round: Int
    public let opponentTeam: Int
    public let wasHome: Bool
    public let kickoffTime: String
    public let totalPoints: Int
    public let minutes: Int
    public let starts: Int
    public let goalsScored: Int
    public let assists: Int
    public let cleanSheets: Int
    public let bonus: Int
    public let bps: Int
    public let expectedGoals: String
    public let expectedAssists: String
    public let expectedGoalInvolvements: String
    public let defensiveContribution: Int?
    public let value: Int

    enum CodingKeys: String, CodingKey {
        case fixture, round, minutes, starts, assists, bonus, bps, value
        case opponentTeam = "opponent_team"
        case wasHome = "was_home"
        case kickoffTime = "kickoff_time"
        case totalPoints = "total_points"
        case goalsScored = "goals_scored"
        case cleanSheets = "clean_sheets"
        case expectedGoals = "expected_goals"
        case expectedAssists = "expected_assists"
        case expectedGoalInvolvements = "expected_goal_involvements"
        case defensiveContribution = "defensive_contribution"
    }
}

public struct FPLElementPastSeason: Decodable, Sendable {
    public let seasonName: String
    public let totalPoints: Int
    public let minutes: Int
    public let starts: Int
    public let goalsScored: Int
    public let assists: Int
    public let expectedGoals: String
    public let expectedAssists: String
    public let expectedGoalInvolvements: String
    public let startCost: Int
    public let endCost: Int

    enum CodingKeys: String, CodingKey {
        case minutes, starts, assists
        case seasonName = "season_name"
        case totalPoints = "total_points"
        case goalsScored = "goals_scored"
        case expectedGoals = "expected_goals"
        case expectedAssists = "expected_assists"
        case expectedGoalInvolvements = "expected_goal_involvements"
        case startCost = "start_cost"
        case endCost = "end_cost"
    }
}

// MARK: - Data provenance and gameweek phase

public enum FPLDataSource: String, Codable, Sendable {
    case network = "Official FPL network"
    case memoryCache = "Recent in-memory cache"
    case diskSnapshot = "Saved device snapshot"
}

public struct FPLResourceMetadata: Codable, Sendable, Equatable {
    public let source: FPLDataSource
    public let fetchedAt: Date
    public let endpoint: String

    public var age: TimeInterval {
        max(0, Date().timeIntervalSince(fetchedAt))
    }

    public var shortAgeDescription: String {
        let seconds = Int(age)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

public struct FPLResource<Value: Sendable>: Sendable {
    public let value: Value
    public let metadata: FPLResourceMetadata
}

public enum FPLGameweekPhase: String, Codable, Sendable {
    case planning = "Pre-deadline planning"
    case locked = "Deadline passed"
    case live = "Matches in progress"
    case review = "Gameweek review"
    case unavailable = "Gameweek unavailable"

    public static func resolve(
        gameweek: FPLGameweek?,
        fixtures: [FPLFixture],
        now: Date = Date()
    ) -> FPLGameweekPhase {
        guard let gameweek else { return .unavailable }
        if gameweek.isBeforeDeadline(at: now) { return .planning }
        if gameweek.finished || gameweek.dataChecked == true { return .review }

        let eventFixtures = fixtures.filter { $0.event == gameweek.id }
        if eventFixtures.contains(where: { fixture in
            fixture.finished || (fixture.kickoffDate.map { $0 <= now } ?? false)
        }) {
            return .live
        }
        return .locked
    }
}
