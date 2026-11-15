import Foundation

/// Retains the existing FPL backup wire format after the planning workspace is
/// retired. These values carry saved data only; they do not load a manager,
/// schedule notifications, make recommendations or contact Coach services.
struct FPLLocalSquadDraft: Codable, Sendable, Equatable {
    let picks: [FPLPick]
    let basedOnGameweek: Int?
    let targetGameweek: Int?
    let budgetLimit: Int?
}

public struct FPLGameweekReview: Identifiable, Codable, Sendable, Equatable {
    public let gameweek: Int
    public let points: Int
    public let overallRank: Int?
    public let transferCost: Int
    public let pointsOnBench: Int
    public let captainName: String?
    public let captainPoints: Int?
    public let topScorerName: String?
    public let topScorerPoints: Int?
    public let recordedAt: Date
    public var id: Int { gameweek }
}

public struct FPLCoachProfile: Codable, Sendable, Equatable {
    public enum RiskStyle: String, Codable, CaseIterable, Sendable, Identifiable {
        case cautious = "Cautious"
        case balanced = "Balanced"
        case aggressive = "Aggressive"
        public var id: String { rawValue }
    }

    public var riskStyle: RiskStyle
    public var planningHorizon: Int
    public var avoidHits: Bool

    public static let `default` = FPLCoachProfile(
        riskStyle: .balanced,
        planningHorizon: 5,
        avoidHits: true
    )
}

public struct FPLSavedScenario: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let managerID: Int
    public let gameweek: Int
    public let name: String
    public let routeName: String
    public let transfers: [String]
    public let hitCost: Int
    public let projectedGain: Double
    public let weeklyProjectedGain: [Int: Double]
    public let breakEvenGameweek: Int?
    public let modelVersion: String
    public let downside: String
    public let verificationItems: [String]
    public let createdAt: Date
}

public struct FPLDecisionJournalEntry: Identifiable, Codable, Sendable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case roll = "Roll transfer"
        case transfer = "Transfer"
        case captain = "Captain"
        case lineup = "Lineup"
        case chip = "Chip"
        case strategy = "Strategy"

        public var id: String { rawValue }

        public var symbol: String {
            switch self {
            case .roll: return "arrow.uturn.forward"
            case .transfer: return "arrow.left.arrow.right"
            case .captain: return "c.circle.fill"
            case .lineup: return "person.3.fill"
            case .chip: return "wand.and.stars"
            case .strategy: return "brain.head.profile"
            }
        }
    }

    public enum Outcome: String, Codable, CaseIterable, Sendable, Identifiable {
        case pending = "Pending"
        case worked = "Worked"
        case mixed = "Mixed"
        case missed = "Missed"
        case abandoned = "Not used"

        public var id: String { rawValue }
    }

    public let id: String
    public let managerID: Int
    public let gameweek: Int
    public let kind: Kind
    public let title: String
    public let rationale: String
    public let expectedOutcome: String
    public let source: String
    public let estimatedPointCost: Int?
    public let createdAt: Date
    public var outcome: Outcome
    public var outcomeNote: String
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        managerID: Int,
        gameweek: Int,
        kind: Kind,
        title: String,
        rationale: String,
        expectedOutcome: String,
        source: String,
        estimatedPointCost: Int? = nil,
        createdAt: Date = Date(),
        outcome: Outcome = .pending,
        outcomeNote: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.managerID = managerID
        self.gameweek = gameweek
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.expectedOutcome = expectedOutcome
        self.source = source
        self.estimatedPointCost = estimatedPointCost
        self.createdAt = createdAt
        self.outcome = outcome
        self.outcomeNote = outcomeNote
        self.updatedAt = updatedAt
    }
}
