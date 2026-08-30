import Foundation

// MARK: - API-Football Provider
// Implementation of the FootballProvider protocol using api-football.com v3

public class APIFootballProvider: FootballProvider {
    public let name = "API-Football"
    
    private let baseURL = "https://v3.football.api-sports.io"
    private let apiKey: String
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public func fetchFixtures(date: Date) async throws -> [FottyFixture] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        
        let response: APIFootballFixtureResponseV3 = try await performRequest(path: "/fixtures", query: ["date": dateStr])
        return response.response.compactMap { mapFixture($0) }
    }
    
    public func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData {
        try await fetchFixtureDetails(fixtureId: fixtureId, includeLineupsAndStats: true)
    }

    /// `includeLineupsAndStats: false` — single `/fixtures?id=` call (score + events only).
    public func fetchFixtureDetails(fixtureId: String, includeLineupsAndStats: Bool) async throws -> MatchHubData {
        let response: APIFootballFixtureResponseV3 = try await performRequest(path: "/fixtures", query: ["id": fixtureId])
        guard let rawMatch = response.response.first else {
            throw FootballProviderError.invalidFixtureId(fixtureId)
        }
        guard includeLineupsAndStats else {
            guard let match = mapToMatchHubData(rawMatch) else {
                throw FootballProviderError.malformedData
            }
            return match
        }
        async let lineupsTask = fetchLineups(fixtureId: fixtureId)
        async let statisticsTask = fetchFixtureStatistics(fixtureId: fixtureId)
        let (lineupRows, statRows) = await (lineupsTask, statisticsTask)
        let homeId = String(rawMatch.teams.home.id)
        let awayId = String(rawMatch.teams.away.id)
        let homeLineup = lineupRows.first(where: { String($0.team.id) == homeId }).map(Self.mapFottyLineup)
        let awayLineup = lineupRows.first(where: { String($0.team.id) == awayId }).map(Self.mapFottyLineup)
        let mergedStats = Self.mergeStatistics(homeTeamId: homeId, awayTeamId: awayId, rows: statRows)
        guard let match = mapToMatchHubData(
            rawMatch,
            homeLineup: homeLineup,
            awayLineup: awayLineup,
            statistics: mergedStats
        ) else {
            throw FootballProviderError.malformedData
        }
        return match
    }
    
    public func fetchLiveScores() async throws -> [MatchHubData] {
        let response: APIFootballFixtureResponseV3 = try await performRequest(
            path: "/fixtures",
            query: FootballDataPolicy.apiFootballLiveQuery()
        )
        return response.response
            .filter {
                FootballDataPolicy.isAPIFootballLiveStatus($0.fixture.status.short)
                    && FootballDataPolicy.supportsLiveScores(
                    competitionId: $0.league.id,
                    competitionName: $0.league.name,
                    country: $0.league.country
                )
            }
            .compactMap { mapToMatchHubData($0) }
    }

    public func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData] {
        let response: APIFootballFixtureResponseV3 = try await performRequest(path: "/fixtures", query: [
            "league": leagueId,
            "season": season
        ])
        return response.response.compactMap { mapToMatchHubData($0) }
    }

    public func fetchStandings(competitionId: String) async throws -> [FottyCompetition] {
        // Implementation for standings...
        return []
    }
    
    public func fetchTeamForm(teamId: String) async throws -> [String] {
        // Implementation for team form...
        return []
    }
    
    public func checkHealth() async -> Bool {
        do {
            let _: APIFootballStatusResponseV3 = try await performRequest(path: "/status")
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Private Helpers & Mapping

    static func shouldUseLiveScoreProxy(
        apiKey: String,
        path: String,
        query: [String: String]
    ) -> Bool {
        guard apiKey.isEmpty, path == "/fixtures" else { return false }
        if query["live"] != nil { return true }
        // A single enabled league uses league/season/date because API-Football's
        // `live` parameter is intended for its multi-league form. The Worker
        // owns that current-season query and credential in both cases.
        return query["league"] != nil && query["season"] != nil && query["date"] != nil
    }
    
    private func performRequest<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        let usesLiveScoreProxy = Self.shouldUseLiveScoreProxy(
            apiKey: apiKey,
            path: path,
            query: query
        )

        let requestBase: String
        if usesLiveScoreProxy, let proxyBase = Config.footballProxyBaseURL {
            requestBase = proxyBase
                .appendingPathComponent("api/football/live")
                .absoluteString
        } else {
            guard !apiKey.isEmpty else {
                throw FootballProviderError.unauthorized
            }
            requestBase = baseURL + path
        }

        guard var components = URLComponents(string: requestBase) else {
            throw FootballProviderError.unknown
        }
        if !query.isEmpty && !usesLiveScoreProxy {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw FootballProviderError.unknown
        }
        var request = URLRequest(url: url)
        if !usesLiveScoreProxy {
            request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FootballProviderError.unknown
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw FootballProviderError.unauthorized
        }
        if httpResponse.statusCode == 429 { throw FootballProviderError.rateLimited }
        if !(200...299).contains(httpResponse.statusCode) { throw FootballProviderError.serverError(httpResponse.statusCode) }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[APIFootballProvider] Decoding Error: \(error)")
            throw FootballProviderError.malformedData
        }
    }
    
    private func mapFixture(_ raw: APIFootballFixtureRawV3) -> FottyFixture? {
        guard let kickoffDate = FootballNormalizer.parseISO8601Date(raw.fixture.date) else {
            return nil
        }
        let fixtureId = String(raw.fixture.id)
        return FottyFixture(
            id: fixtureId,
            utcDate: kickoffDate,
            status: FootballNormalizer.normalizeStatus(raw.fixture.status.short),
            competition: FottyCompetition(
                id: String(raw.league.id),
                name: raw.league.name,
                country: raw.league.country,
                emblemURL: URL(string: raw.league.logo ?? "")
            ),
            venue: normalizedVenue(raw.fixture.venue),
            matchday: raw.league.round.flatMap { Int($0.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) },
            apiFootballFixtureId: fixtureId,
            roundLabel: raw.league.round,
            elapsedMinutes: raw.fixture.status.elapsed,
            extraMinutes: raw.fixture.status.extra
        )
    }
    
    private func mapToMatchHubData(
        _ raw: APIFootballFixtureRawV3,
        homeLineup: FottyLineup? = nil,
        awayLineup: FottyLineup? = nil,
        statistics: [FottyStatistic] = []
    ) -> MatchHubData? {
        guard let fixture = mapFixture(raw) else { return nil }
        
        let homeTeam = FottyTeam(
            id: String(raw.teams.home.id),
            name: raw.teams.home.name,
            shortName: nil,
            crestURL: URL(string: raw.teams.home.logo ?? ""),
            color: nil
        )
        
        let awayTeam = FottyTeam(
            id: String(raw.teams.away.id),
            name: raw.teams.away.name,
            shortName: nil,
            crestURL: URL(string: raw.teams.away.logo ?? ""),
            color: nil
        )
        
        let score = FottyScore(
            home: raw.goals.home ?? 0,
            away: raw.goals.away ?? 0,
            aggregateHome: nil,
            aggregateAway: nil,
            periodScores: [
                "HT": PeriodScore(home: raw.score.halftime.home ?? 0, away: raw.score.halftime.away ?? 0),
                "FT": PeriodScore(home: raw.score.fulltime.home ?? 0, away: raw.score.fulltime.away ?? 0)
            ]
        )
        
        let events = (raw.events ?? []).enumerated().map { index, event in
            let playerName = event.player.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return FottyMatchEvent(
                id: "\(raw.fixture.id)-\(event.time.elapsed)-\(event.time.extra ?? 0)-\(event.team.id)-\(event.type)-\(playerName)-\(index)",
                type: FootballNormalizer.normalizeEventType(event.type, detail: event.detail),
                minute: event.time.elapsed,
                extraMinute: event.time.extra,
                teamId: String(event.team.id),
                player: event.player.name,
                assist: event.assist.name,
                detail: event.detail
            )
        }
        
        return MatchHubData(
            fixture: fixture,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            score: score,
            events: events,
            homeLineup: homeLineup,
            awayLineup: awayLineup,
            statistics: statistics,
            teamNews: [],
            lastUpdated: Date(),
            dataQuality: .verified
        )
    }

    private func normalizedVenue(_ venue: APIFootballVenueV3) -> FottyVenue? {
        let name = venue.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let city = venue.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FottyVenue(name: name, city: city?.isEmpty == false ? city : nil)
    }

    private func fetchLineups(fixtureId: String) async -> [APIFootballLineup] {
        do {
            let decoded: APIFootballResponseWrapper<APIFootballLineup> = try await performRequest(
                path: "/fixtures/lineups",
                query: ["fixture": fixtureId]
            )
            return decoded.response
        } catch {
            print("[APIFootballProvider] Lineups unavailable for \(fixtureId): \(error.localizedDescription)")
            return []
        }
    }

    private func fetchFixtureStatistics(fixtureId: String) async -> [APIFootballStatistics] {
        do {
            let decoded: APIFootballResponseWrapper<APIFootballStatistics> = try await performRequest(
                path: "/fixtures/statistics",
                query: ["fixture": fixtureId]
            )
            return decoded.response
        } catch {
            print("[APIFootballProvider] Statistics unavailable for \(fixtureId): \(error.localizedDescription)")
            return []
        }
    }

    private static func mapFottyLineup(_ raw: APIFootballLineup) -> FottyLineup {
        let coachName = raw.coach.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FottyLineup(
            teamId: String(raw.team.id),
            formation: raw.formation,
            startingXi: raw.startXI.map { mapFottyPlayer($0) },
            substitutes: raw.substitutes.map { mapFottyPlayer($0) },
            coach: (coachName?.isEmpty == false) ? coachName : nil
        )
    }

    private static func mapFottyPlayer(_ entry: APIFootballLineupPlayer) -> FottyPlayer {
        let p = entry.player
        let grid = parseGridPosition(p.grid)
        return FottyPlayer(
            id: String(p.id),
            name: p.name,
            number: p.number,
            position: p.pos,
            x: grid?.column,
            y: grid?.line
        )
    }

    /// API-Sports tactical grid `line:column` (e.g. `4:3`). We store column as `x`, line as `y` for pitch layout.
    private static func parseGridPosition(_ grid: String?) -> (line: Int, column: Int)? {
        guard let grid = grid?.trimmingCharacters(in: .whitespacesAndNewlines), !grid.isEmpty else { return nil }
        let parts = grid.split(separator: ":").map(String.init).compactMap(Int.init)
        guard parts.count == 2 else { return nil }
        return (line: parts[0], column: parts[1])
    }

    private static func mergeStatistics(homeTeamId: String, awayTeamId: String, rows: [APIFootballStatistics]) -> [FottyStatistic] {
        let homeRow = rows.first { String($0.team.id) == homeTeamId }
        let awayRow = rows.first { String($0.team.id) == awayTeamId }
        guard let homeStats = homeRow?.statistics else { return [] }
        let awayByType = Dictionary(uniqueKeysWithValues: (awayRow?.statistics ?? []).map { ($0.type, $0.value) })

        return homeStats.map { item in
            let awayWrapped = awayByType[item.type]
            let awayValue = awayWrapped.flatMap { $0 }
            let hStr = stringFromStatValue(item.value)
            let aStr = stringFromStatValue(awayValue)
            let pct = homeStatProportion(home: item.value, away: awayValue)
            return FottyStatistic(type: item.type, homeValue: hStr, awayValue: aStr, homePercentage: pct)
        }
    }

    private static func stringFromStatValue(_ value: APIFootballStatValue?) -> String {
        guard let value else { return "—" }
        switch value {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "—" : t
        case .int(let i): return "\(i)"
        case .double(let d):
            if d.rounded() == d { return String(format: "%.0f", d) }
            return String(format: "%.1f", d)
        case .null: return "—"
        }
    }

    private static func doubleFromStatValue(_ value: APIFootballStatValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
            if let v = Double(t) { return v }
            if let slash = t.firstIndex(of: "/") {
                let left = t[..<slash]
                let right = t[t.index(after: slash)...]
                if let num = Double(left), let den = Double(right), den > 0 {
                    return num / den
                }
            }
            return nil
        case .null: return nil
        }
    }

    private static func homeStatProportion(home: APIFootballStatValue?, away: APIFootballStatValue?) -> Double {
        if let h = doubleFromStatValue(home), let a = doubleFromStatValue(away), h + a > 0 {
            return h / (h + a)
        }
        return 0.5
    }

}

// MARK: - Raw API Models (Private)

private struct APIFootballFixtureResponseV3: Decodable {
    let response: [APIFootballFixtureRawV3]
}

private struct APIFootballStatusResponseV3: Decodable {
    let response: APIFootballStatusDataV3
}

private struct APIFootballStatusDataV3: Decodable {
    let account: APIFootballAccountV3
}

private struct APIFootballAccountV3: Decodable {
    let firstname: String
}

private struct APIFootballFixtureRawV3: Decodable {
    let fixture: APIFootballFixtureInfoV3
    let league: APIFootballLeagueV3
    let teams: APIFootballTeamsV3
    let goals: APIFootballGoalsV3
    let score: APIFootballScoreV3
    let events: [APIFootballEventV3]?
}

private struct APIFootballFixtureInfoV3: Decodable {
    let id: Int
    let date: String
    let status: APIFootballStatusV3
    let venue: APIFootballVenueV3
}

private struct APIFootballStatusV3: Decodable {
    let short: String
    let elapsed: Int?
    let extra: Int?
}

private struct APIFootballVenueV3: Decodable {
    let name: String?
    let city: String?
}

private struct APIFootballLeagueV3: Decodable {
    let id: Int
    let name: String
    let country: String?
    let logo: String?
    let round: String?
}

private struct APIFootballTeamsV3: Decodable {
    let home: APIFootballTeamV3
    let away: APIFootballTeamV3
}

private struct APIFootballTeamV3: Decodable {
    let id: Int
    let name: String
    let logo: String?
}

private struct APIFootballGoalsV3: Decodable {
    let home: Int?
    let away: Int?
}

private struct APIFootballScoreV3: Decodable {
    let halftime: APIFootballGoalsV3
    let fulltime: APIFootballGoalsV3
}

private struct APIFootballEventV3: Decodable {
    let time: APIFootballTimeV3
    let team: APIFootballTeamIdV3
    let player: APIFootballPlayerV3
    let assist: APIFootballPlayerV3
    let type: String
    let detail: String?
}

private struct APIFootballTimeV3: Decodable {
    let elapsed: Int
    let extra: Int?
}

private struct APIFootballTeamIdV3: Decodable {
    let id: Int
}

private struct APIFootballPlayerV3: Decodable {
    let name: String?
}
