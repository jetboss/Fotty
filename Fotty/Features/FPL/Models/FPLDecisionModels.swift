import Foundation
import Observation

public struct FPLSquadValidationIssue: Identifiable, Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
    }

    public let code: String
    public let message: String
    public let severity: Severity
    public var id: String { "\(severity.rawValue):\(code):\(message)" }
}

public struct FPLSquadValidationReport: Codable, Sendable, Equatable {
    public let issues: [FPLSquadValidationIssue]
    public let totalCost: Int
    public let budgetLimit: Int?
    public let formation: String?

    public var isValid: Bool {
        !issues.contains(where: { $0.severity == .error })
    }
}

public struct FPLFreeTransferEstimate: Codable, Sendable, Equatable {
    public let count: Int
    public let targetGameweek: Int
    public let explanation: String
    public let isExact: Bool
}

public enum FPLProjectionConfidence: String, Codable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

public enum FPLProjectionSource: String, Codable, Sendable {
    case officialBlend = "Official/Fotty blend"
    case fottyEstimate = "Fotty estimate"
}

public struct FPLPlayerProjection: Identifiable, Sendable {
    public let player: FPLPlayer
    public let gameweekPoints: [Int: Double]
    public let expectedMinutes: [Int: Int]
    public let sourceByGameweek: [Int: FPLProjectionSource]
    public let total: Double
    public let confidence: FPLProjectionConfidence
    public let modelVersion: String
    public let assumptions: [String]
    public var id: Int { player.id }
}

public struct FPLLiveSquadPlayer: Identifiable, Sendable {
    public let pick: FPLPick
    public let player: FPLPlayer
    public let team: FPLTeam
    public let stats: FPLLivePlayerStats
    public let effectiveMultiplier: Int
    public let multipliedPoints: Int
    public let hasFixtureRemaining: Bool
    public var id: Int { player.id }

    public var isProjectedSubstitute: Bool {
        pick.position > 11 && effectiveMultiplier > 0
    }
}

public struct FPLLiveSquadSummary: Sendable {
    public let gameweek: Int
    /// Nil means unknown. A partial feed must never manufacture a zero total.
    public let totalPoints: Int?
    public let officialCurrentPoints: Int?
    public let publishedLineupPoints: Int?
    public let hasCompleteScoringData: Bool
    public let transferCost: Int
    public let playersPlayed: Int
    public let playersRemaining: Int
    public let officialBonus: Int
    public let automaticSubs: [FPLAutomaticSub]
    public let projectedAutomaticSubs: [FPLAutomaticSub]
    public let projectedCaptainElementID: Int?
    public let rows: [FPLLiveSquadPlayer]
    public let isFinal: Bool

    public var pointsAreProjected: Bool {
        hasCompleteScoringData && !isFinal
            && automaticSubs.isEmpty
            && (!projectedAutomaticSubs.isEmpty || projectedCaptainElementID != nil)
    }

    public var displayedAutomaticSubs: [FPLAutomaticSub] {
        automaticSubs.isEmpty ? projectedAutomaticSubs : automaticSubs
    }

    public var projectionLabel: String {
        switch (!projectedAutomaticSubs.isEmpty, projectedCaptainElementID != nil) {
        case (true, true): return "projected autosubs and captaincy"
        case (true, false): return "projected autosubs"
        case (false, true): return "projected captaincy"
        case (false, false): return "official points"
        }
    }
}

public struct FPLCommandCenterAction: Identifiable, Sendable {
    public enum Destination: String, Sendable {
        case squad
        case transfers
        case captain
        case live
        case coach
        case leagues
        case planner
    }

    public let title: String
    public let detail: String
    public let symbol: String
    public let priority: Int
    public let destination: Destination
    public var id: String { "\(destination.rawValue):\(title)" }
}

public struct FPLCommandCenterState: Sendable {
    public let phase: FPLGameweekPhase
    public let title: String
    public let subtitle: String
    public let metrics: [FPLCommandCenterMetric]
    public let actions: [FPLCommandCenterAction]
    public let warnings: [String]
}

public struct FPLCommandCenterMetric: Identifiable, Sendable, Equatable {
    public let label: String
    public let value: String
    public let detail: String?
    public var id: String { label }
}

public struct FPLMatchdayPlayerContext: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let teamName: String
    public let isStarter: Bool
    public let isCaptain: Bool
    public let isViceCaptain: Bool
    public let livePoints: Int?
    public let minutes: Int?
    public let hasFixtureRemaining: Bool?
}

public struct FPLMatchdayContextSnapshot: Codable, Sendable, Equatable {
    public let managerID: Int
    public let gameweek: Int?
    public let phase: FPLGameweekPhase
    public let players: [FPLMatchdayPlayerContext]
    public let updatedAt: Date
}

public struct FPLMatchInvolvement: Sendable, Equatable {
    public let players: [FPLMatchdayPlayerContext]

    public var starterCount: Int { players.filter(\.isStarter).count }
    public var benchCount: Int { players.count - starterCount }
    public var captainName: String? { players.first(where: \.isCaptain)?.name }

    public var compactLabel: String {
        if let captainName {
            return "Captain \(captainName) · \(players.count) in squad"
        }
        if starterCount > 0, benchCount > 0 {
            return "\(starterCount) starting · \(benchCount) bench"
        }
        if starterCount > 0 {
            return "\(starterCount) starter\(starterCount == 1 ? "" : "s")"
        }
        return "\(benchCount) on bench"
    }
}

/// A device-local bridge between the official FPL workspace and match discovery.
/// Home and Matchday read this snapshot without owning another FPL network client.
@MainActor
@Observable
public final class FPLMatchdayContextStore {
    public static let shared = FPLMatchdayContextStore()

    public private(set) var snapshot: FPLMatchdayContextSnapshot?

    private let defaults: UserDefaults
    private let storageKey: String
    private let maximumSnapshotAge: TimeInterval

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "fotty.fpl.matchday-context",
        maximumSnapshotAge: TimeInterval = 21 * 24 * 60 * 60
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maximumSnapshotAge = maximumSnapshotAge

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(FPLMatchdayContextSnapshot.self, from: data),
           Date().timeIntervalSince(decoded.updatedAt) <= maximumSnapshotAge {
            snapshot = decoded
        } else {
            snapshot = nil
            defaults.removeObject(forKey: storageKey)
        }
    }

    public func update(
        managerID: Int,
        gameweek: Int?,
        phase: FPLGameweekPhase,
        picks: [FPLPick],
        players: [FPLPlayer],
        teams: [FPLTeam],
        live: FPLLiveSquadSummary? = nil,
        now: Date = Date()
    ) {
        let playerByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let teamByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        let liveByID = Dictionary(uniqueKeysWithValues: (live?.rows ?? []).map { ($0.player.id, $0) })
        let contextPlayers = picks.compactMap { pick -> FPLMatchdayPlayerContext? in
            guard let player = playerByID[pick.element],
                  let team = teamByID[player.team] else { return nil }
            let liveRow = liveByID[player.id]
            return FPLMatchdayPlayerContext(
                id: player.id,
                name: player.webName,
                teamName: team.name,
                isStarter: pick.position <= 11 || pick.multiplier > 0,
                isCaptain: pick.isCaptain,
                isViceCaptain: pick.isViceCaptain,
                livePoints: liveRow?.multipliedPoints,
                minutes: liveRow?.stats.minutes,
                hasFixtureRemaining: liveRow?.hasFixtureRemaining
            )
        }
        guard !contextPlayers.isEmpty else { return }

        let updated = FPLMatchdayContextSnapshot(
            managerID: managerID,
            gameweek: gameweek,
            phase: phase,
            players: contextPlayers,
            updatedAt: now
        )
        snapshot = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func clear(managerID: Int? = nil) {
        if let managerID, snapshot?.managerID != managerID { return }
        snapshot = nil
        defaults.removeObject(forKey: storageKey)
    }

    public func involvement(homeTeam: String, awayTeam: String) -> FPLMatchInvolvement? {
        guard let snapshot,
              Date().timeIntervalSince(snapshot.updatedAt) <= maximumSnapshotAge else {
            return nil
        }
        let homeKey = FootballDataPolicy.normalizedTeamMatchKey(homeTeam)
        let awayKey = FootballDataPolicy.normalizedTeamMatchKey(awayTeam)
        let involved = snapshot.players.filter { player in
            let playerTeamKey = FootballDataPolicy.normalizedTeamMatchKey(player.teamName)
            return playerTeamKey == homeKey || playerTeamKey == awayKey
        }
        guard !involved.isEmpty else { return nil }
        return FPLMatchInvolvement(
            players: involved.sorted {
                if $0.isCaptain != $1.isCaptain { return $0.isCaptain }
                if $0.isStarter != $1.isStarter { return $0.isStarter }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        )
    }
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

public struct FPLDraftRoute: Identifiable, Sendable {
    public let name: String
    public let transfers: [TransferRecommendation]
    public let hitCost: Int
    public let projectedGain: Double
    public let weeklyProjectedGain: [Int: Double]
    public let breakEvenGameweek: Int?
    public let modelVersion: String
    public let explanation: String
    public let downside: String
    public let verificationItems: [String]
    public var id: String { name }
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

    public init(
        id: String = UUID().uuidString,
        managerID: Int,
        gameweek: Int,
        name: String,
        route: FPLDraftRoute,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.managerID = managerID
        self.gameweek = gameweek
        self.name = name
        self.routeName = route.name
        self.transfers = route.transfers.map {
            "\($0.playerOut.player.webName) → \($0.playerIn.player.webName)"
        }
        self.hitCost = route.hitCost
        self.projectedGain = route.projectedGain
        self.weeklyProjectedGain = route.weeklyProjectedGain
        self.breakEvenGameweek = route.breakEvenGameweek
        self.modelVersion = route.modelVersion
        self.downside = route.downside
        self.verificationItems = route.verificationItems
        self.createdAt = createdAt
    }
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

public struct FPLOptimizedSquad: Identifiable, Sendable {
    public enum Profile: String, CaseIterable, Sendable, Identifiable {
        case safe = "Safe"
        case balanced = "Balanced"
        case aggressive = "Aggressive"
        public var id: String { rawValue }
    }

    public let profile: Profile
    public let picks: [FPLPick]
    public let projectedPoints: Double
    public let cost: Int
    public let validation: FPLSquadValidationReport
    public let explanation: String
    public var id: String { profile.rawValue }
}
