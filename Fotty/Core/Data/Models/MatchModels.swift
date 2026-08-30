import Foundation

// MARK: - Fotty Internal Match Models

public enum FottyMatchStatus: String, Codable, CaseIterable {
    case scheduled
    case preMatch
    case live
    case halfTime
    case fullTime
    case extraTime
    case penalties
    case postponed
    case cancelled
    case abandoned
    case unknown
    
    public var isLive: Bool {
        [.live, .halfTime, .extraTime, .penalties].contains(self)
    }
    
    public var isFinished: Bool {
        [.fullTime, .abandoned].contains(self)
    }
}

public enum FottyEventType: String, Codable {
    case goal
    case penalty
    case ownGoal
    case yellowCard
    case redCard
    case substitution
    case varDecision
    case kickoff
    case halfTime
    case fullTime
    case injuryTime
    case unknown
}

public struct FottyFixture: Codable, Identifiable, Hashable {
    public let id: String
    /// API-Football fixture id when known (use for Match Hub); `id` may be football-data.org for schedule rows.
    public let apiFootballFixtureId: String?
    public let utcDate: Date
    public let status: FottyMatchStatus
    public let competition: FottyCompetition
    public let venue: FottyVenue?
    public let matchday: Int?
    /// API-Football league round label (e.g. "Group A - 1") when available.
    public let roundLabel: String?
    public let lastUpdated: Date
    /// Live elapsed minutes from provider status when match is in play.
    public let elapsedMinutes: Int?
    public let extraMinutes: Int?
    
    public init(
        id: String,
        utcDate: Date,
        status: FottyMatchStatus,
        competition: FottyCompetition,
        venue: FottyVenue?,
        matchday: Int?,
        apiFootballFixtureId: String? = nil,
        roundLabel: String? = nil,
        lastUpdated: Date = Date(),
        elapsedMinutes: Int? = nil,
        extraMinutes: Int? = nil
    ) {
        self.id = id
        self.apiFootballFixtureId = apiFootballFixtureId
        self.utcDate = utcDate
        self.status = status
        self.competition = competition
        self.venue = venue
        self.matchday = matchday
        self.roundLabel = roundLabel
        self.lastUpdated = lastUpdated
        self.elapsedMinutes = elapsedMinutes
        self.extraMinutes = extraMinutes
    }

    public var hubFixtureId: String { apiFootballFixtureId ?? id }

    /// Provider identifiers are aliases of the schedule identity, not a second
    /// identity that may silently replace navigation, alerts, or playback state.
    public var identityAliases: Set<String> {
        var aliases: Set<String> = ["canonical:\(id)"]
        if let apiFootballFixtureId, !apiFootballFixtureId.isEmpty {
            aliases.insert("api-football:\(apiFootballFixtureId)")
        }
        return aliases
    }
}

public struct FottyFixtureIdentity: Codable, Hashable {
    public let canonicalID: String
    public let matchKey: String
    public let providerAliases: Set<String>

    /// The one id carried by notification, Match Center, and playback routes.
    /// Provider ids remain lookup aliases and never replace this value.
    public var routeID: String { canonicalID }

    public func resolves(_ candidateID: String) -> Bool {
        let candidate = candidateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        if candidate == canonicalID || candidate == "canonical:\(canonicalID)" {
            return true
        }
        if candidate.contains(":") {
            return providerAliases.contains(candidate)
        }
        return providerAliases.contains { alias in
            alias.split(separator: ":", maxSplits: 1).last.map(String.init) == candidate
        }
    }

    public func matches(homeTeam: String, awayTeam: String, kickoff: Date) -> Bool {
        matchKey == FootballDataPolicy.canonicalFixtureMatchKey(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            kickoff: kickoff
        )
    }
}

public struct FottyTeam: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let shortName: String?
    public let crestURL: URL?
    public let color: String?
    
    public var displayName: String { shortName ?? name }
}

public struct FottyScore: Codable, Hashable {
    public let home: Int
    public let away: Int
    public let aggregateHome: Int?
    public let aggregateAway: Int?
    // Using a simple struct instead of tuple for Codable compliance
    public let periodScores: [String: PeriodScore]?
}

public struct PeriodScore: Codable, Hashable {
    public let home: Int
    public let away: Int
}

public struct FottyCompetition: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let country: String?
    public let emblemURL: URL?
}

/// Disambiguates generic league names (e.g. multiple national "Premier League" competitions).
public enum LeagueDisplayFormatting {
    public static func audienceFacing(leagueName: String?, country: String?) -> String {
        let trimmedName = (leagueName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Unknown Competition" }
        let trimmedCountry = country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCountry.isEmpty else { return trimmedName }
        let countryLabels: [String: [String]] = [
            "england": ["england", "english"],
            "scotland": ["scotland", "scottish"],
            "spain": ["spain", "spanish"],
            "italy": ["italy", "italian"],
            "germany": ["germany", "german"],
            "france": ["france", "french"],
            "netherlands": ["netherlands", "dutch"],
            "portugal": ["portugal", "portuguese"],
            "belgium": ["belgium", "belgian"],
            "united states": ["united states", "usa", "american"]
        ]
        let normalizedName = trimmedName.lowercased()
        let normalizedCountry = trimmedCountry.lowercased()
        let labels = countryLabels[normalizedCountry] ?? [normalizedCountry]
        if labels.contains(where: normalizedName.contains) { return trimmedName }
        return "\(trimmedCountry) · \(trimmedName)"
    }
}

extension FottyCompetition {
    public var audienceFacingName: String {
        LeagueDisplayFormatting.audienceFacing(leagueName: name, country: country)
    }
}

public struct FottyVenue: Codable, Hashable {
    public let name: String
    public let city: String?
}

public struct FottyMatchEvent: Codable, Identifiable, Hashable {
    public let id: String
    public let type: FottyEventType
    public let minute: Int
    public let extraMinute: Int?
    public let teamId: String
    public let player: String?
    public let assist: String?
    public let detail: String?
}

public struct FottyLineup: Codable, Hashable {
    public let teamId: String
    public let formation: String?
    public let startingXi: [FottyPlayer]
    public let substitutes: [FottyPlayer]
    public let coach: String?
}

public struct FottyPlayer: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let number: Int?
    public let position: String?
    public let x: Int?
    public let y: Int?
}

public struct FottyStatistic: Codable, Hashable {
    public let type: String
    public let homeValue: String
    public let awayValue: String
    public let homePercentage: Double
}

// MARK: - UI Composite Models

public struct FottyTeamNewsItem: Codable, Identifiable, Hashable {
    public let id: String
    public let teamName: String
    public let title: String
    public let source: String?
    public let url: URL?
    public let publishedAt: Date?
}

public struct MatchHubData: Codable {
    public let fixture: FottyFixture
    public let homeTeam: FottyTeam
    public let awayTeam: FottyTeam
    public let score: FottyScore
    public let events: [FottyMatchEvent]
    public let homeLineup: FottyLineup?
    public let awayLineup: FottyLineup?
    public let statistics: [FottyStatistic]
    public let teamNews: [FottyTeamNewsItem]
    public let lastUpdated: Date
    public let dataQuality: DataQualityStatus
    
    public enum DataQualityStatus: String, Codable {
        case official
        case verified
        case degraded
        case stale
        case fallback
    }
}

extension MatchHubData {
    public var identity: FottyFixtureIdentity {
        FottyFixtureIdentity(
            canonicalID: fixture.id,
            matchKey: FootballDataPolicy.canonicalFixtureMatchKey(
                homeTeam: homeTeam.name,
                awayTeam: awayTeam.name,
                kickoff: fixture.utcDate
            ),
            providerAliases: fixture.identityAliases
        )
    }
}

public struct MatchInsightsData: Codable {
    public let fixtureId: String
    public let homeForm: [String]
    public let awayForm: [String]
    public let headToHead: [FottyFixture]?
    public let keyInsights: [String]
    public let momentum: [Double]
    public let winProbability: WinProbability?
    public let lastUpdated: Date
}

public struct WinProbability: Codable {
    public let home: Double
    public let draw: Double
    public let away: Double
}
