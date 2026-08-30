import Foundation

/// Filters a provider response to the exact caller-requested window. Empty
/// windows remain empty; production must never widen to unrelated season data.
enum FootballFixtureWindowPolicy {
    static func filter<Value>(
        _ values: [Value],
        dateRange: ClosedRange<Date>,
        kickoff: (Value) -> Date
    ) -> [Value] {
        values.filter { dateRange.contains(kickoff($0)) }
    }
}

enum LiveScoreFeedMode: String, Sendable {
    case inactive
    case officialFPL
    case live
    case delayedFallback
    case quotaFallback
    case unavailable

    var usesDelayedData: Bool {
        self == .delayedFallback || self == .quotaFallback
    }

    var isQuotaReserved: Bool { self == .quotaFallback }

    var statusQualifier: String? {
        switch self {
        case .officialFPL: return "Official FPL"
        case .delayedFallback, .quotaFallback: return "Delayed"
        default: return nil
        }
    }
}

/// Documents which provider backs each Fotty surface and how often we call it.
/// See `FootballRepository` for TTLs and cooldowns.
enum FootballDataPolicy {
    enum LiveScoreCompetition: CaseIterable, Equatable {
        case premierLeague
        case championsLeague

        var apiFootballLeagueId: String {
            switch self {
            case .premierLeague: return "39"
            case .championsLeague: return "2"
            }
        }

        var footballDataLeague: League {
            switch self {
            case .premierLeague: return .premierLeague
            case .championsLeague: return .championsLeague
            }
        }

        var footballDataCompetitionId: Int {
            switch self {
            case .premierLeague: return 2021
            case .championsLeague: return 2001
            }
        }

        var displayName: String {
            switch self {
            case .premierLeague: return "Premier League"
            case .championsLeague: return "Champions League"
            }
        }
    }

    /// Product decision: live-score quota is Premier League-only for now.
    /// API-Football rejects a single league id in `live`, so one competition uses
    /// a dated league/season query and filters it to active statuses. Multiple
    /// competitions can use its hyphenated `live=39-2` form.
    static let activeLiveScoreCompetitions: [LiveScoreCompetition] = [.premierLeague]
    static let plannedLiveScoreCompetitions: [LiveScoreCompetition] = [.premierLeague, .championsLeague]

    static var apiFootballLiveFilter: String {
        activeLiveScoreCompetitions
            .map(\.apiFootballLeagueId)
            .joined(separator: "-")
    }

    static func apiFootballLiveQueryItems(at date: Date = Date()) -> [URLQueryItem] {
        let ids = activeLiveScoreCompetitions.map(\.apiFootballLeagueId)
        if ids.count == 1, let onlyId = ids.first {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let season = month >= 7 ? year : year - 1
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return [
                URLQueryItem(name: "league", value: onlyId),
                URLQueryItem(name: "season", value: String(season)),
                URLQueryItem(name: "date", value: formatter.string(from: date)),
            ]
        }
        return [URLQueryItem(name: "live", value: ids.joined(separator: "-"))]
    }

    static func apiFootballLiveQuery(at date: Date = Date()) -> [String: String] {
        Dictionary(uniqueKeysWithValues: apiFootballLiveQueryItems(at: date).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    static func apiFootballLiveURL(host: String, at date: Date = Date()) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/fixtures"
        components.queryItems = apiFootballLiveQueryItems(at: date)
        return components.url
    }

    static func isAPIFootballLiveStatus(_ status: String) -> Bool {
        switch status.uppercased() {
        case "1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE": return true
        default: return false
        }
    }

    static var footballDataLiveLeagues: [League] {
        activeLiveScoreCompetitions.map(\.footballDataLeague)
    }

    static var liveScoreCoverageLabel: String {
        activeLiveScoreCompetitions.map(\.displayName).joined(separator: " + ")
    }

    /// Stable cross-provider team key. Official FPL intentionally uses familiar
    /// display names such as "Man City" and "Spurs", while schedule providers
    /// often return full legal club names.
    static func normalizedTeamMatchKey(_ name: String) -> String {
        FootballCompetitionCatalog.canonicalTeamKey(name)
    }

    /// Stable provider-independent identity key. UTC day ordinals avoid a
    /// device-time-zone changing the same fixture's identity across screens.
    static func canonicalFixtureMatchKey(
        homeTeam: String,
        awayTeam: String,
        kickoff: Date
    ) -> String {
        let utcDay = Int(floor(kickoff.timeIntervalSince1970 / 86_400))
        return "\(normalizedTeamMatchKey(homeTeam))|\(normalizedTeamMatchKey(awayTeam))|\(utcDay)"
    }

    /// Avoid spending a live-provider request when the broad cached schedule
    /// proves no covered match can currently be live.
    static func shouldPollLiveScores(fixtures: [FottyFixture], at now: Date = Date()) -> Bool {
        fixtures.contains { fixture in
            guard supportsLiveScores(competition: fixture.competition) else { return false }
            if fixture.status.isLive { return true }

            switch fixture.status {
            case .scheduled, .preMatch, .unknown:
                let pollingStart = fixture.utcDate.addingTimeInterval(-5 * 60)
                let pollingEnd = fixture.utcDate.addingTimeInterval(3 * 60 * 60)
                return pollingStart...pollingEnd ~= now
            case .live, .halfTime, .extraTime, .penalties:
                return true
            case .fullTime, .postponed, .cancelled, .abandoned:
                return false
            }
        }
    }

    /// Accepts both providers' ids and uses names only as a defensive fallback.
    /// A generic "Premier League" from another country must not consume score quota.
    static func supportsLiveScores(
        competitionId: Int?,
        competitionName: String?,
        competitionCode: String? = nil,
        country: String? = nil
    ) -> Bool {
        if let competitionId {
            return activeLiveScoreCompetitions.contains(where: {
                $0.apiFootballLeagueId == String(competitionId)
                    || $0.footballDataCompetitionId == competitionId
            })
        }

        let normalizedCode = competitionCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let normalizedCode,
           activeLiveScoreCompetitions.contains(where: { $0.footballDataLeague.rawValue == normalizedCode }) {
            return true
        }

        let normalizedName = competitionName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let normalizedCountry = country?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalizedName.isEmpty else { return false }

        return activeLiveScoreCompetitions.contains { competition in
            switch competition {
            case .premierLeague:
                // Name fallback is deliberately exact. Broad schedule feeds
                // also contain competitions such as Premier League 2 and the
                // Premier League Cup; treating those as the senior competition
                // makes Home promise a score Fotty never intended to cover.
                let acceptedNames: Set<String> = [
                    "premier league",
                    "english premier league",
                    "england premier league",
                ]
                return acceptedNames.contains(normalizedName)
                    && (normalizedCountry.isEmpty || normalizedCountry == "england")
            case .championsLeague:
                let acceptedNames: Set<String> = [
                    "champions league",
                    "uefa champions league",
                ]
                return acceptedNames.contains(normalizedName)
            }
        }
    }

    static func supportsLiveScores(competition: FottyCompetition) -> Bool {
        supportsLiveScores(
            competitionId: Int(competition.id),
            competitionName: competition.name,
            country: competition.country
        )
    }

    /// Missing-score UI is allowed only when schedule identity has confirmed
    /// that the fixture belongs to a covered competition. Catalog team names
    /// are not sufficient evidence: youth/reserve teams can share a senior
    /// Premier League club name and would otherwise inherit a false promise.
    static func hasConfirmedLiveScoreCoverage(competition: MatchCompetition?) -> Bool {
        guard let competition else { return false }
        return supportsLiveScores(competition: competition)
    }

    static func supportsLiveScores(competition: MatchCompetition) -> Bool {
        supportsLiveScores(
            competitionId: competition.id,
            competitionName: competition.name,
            competitionCode: competition.code,
            country: competition.country
        )
    }

    /// Live scores on Dashboard / Arena live rows — official FPL fixtures first,
    /// then scoped API-Football and football-data fallbacks.
    static var liveScoresProvider: String {
        "Official FPL → API-Football (\(liveScoreCoverageLabel)) → football-data.org"
    }
    /// Schedule / “Starting soon” / Analysis tab — football-data.org `GET /matches` (~1 call / 15 min).
    static let scheduleProvider = "football-data.org"
    /// Match Hub scores + events — API-Football `/fixtures?id=` for score-supported competitions only.
    static var matchHubScoresProvider: String { "API-Football (\(liveScoreCoverageLabel))" }
    /// Lineups, formations, team news — TheSportsDB (no API-Football quota).
    static let enrichmentsProvider = "TheSportsDB"
    /// Emergency only when schedule is empty — same narrow live-score allowlist (2h cooldown).
    static var premiumFallbackProvider: String { "API-Football \(liveScoreCoverageLabel) (emergency)" }
}
