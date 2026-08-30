import os.log
import Foundation

private let serviceLogger = Logger(subsystem: "com.jelani.Fotty", category: "FootballService")

// MARK: - Football Schedule Service
// Uses football-data.org v4 API (free tier: 10 req/min, PL + CL included)

actor FootballService {
    
    static let shared = FootballService()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = "https://api.football-data.org/v4"
    
    // Cache
    private var cache: [String: (data: Data, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 60 // 1 minute for live data
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    /// Time until which we should stop making requests due to rate limiting
    private var cooldownUntil: Date?
    private var footballProxyCooldownUntil: Date?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "X-Auth-Token": Config.footballAPIKey,
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }
    
    // MARK: - Matches

    /// Global v4 feed: `GET /matches?dateFrom=&dateTo=&status=`
    func fetchGlobalMatches(
        from: Date,
        to: Date,
        statuses: [String]? = nil,
        limit: Int? = nil
    ) async throws -> [FootballMatch] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var query: [String: String] = [
            "dateFrom": formatter.string(from: from),
            "dateTo": formatter.string(from: to)
        ]
        if let statuses, !statuses.isEmpty {
            query["status"] = statuses.joined(separator: ",")
        }
        if let limit {
            query["limit"] = String(limit)
        }

        do {
            let response: FootballMatchesResponse = try await request(path: "/matches", query: query)
            if !response.matches.isEmpty {
                return response.matches
            }
        } catch {
            serviceLogger.error("Global /matches failed (\(error.localizedDescription, privacy: .public)); using per-competition fallback.")
        }

        return try await fetchMatchesAcrossCompetitions(from: from, to: to, statuses: statuses, limit: limit)
    }

    /// Competition-scoped v4 feed. Unlike `fetchGlobalMatches`, this never fans
    /// out to every supported competition when the upstream request is empty.
    func fetchMatches(
        leagues: [League],
        from: Date,
        to: Date,
        statuses: [String]? = nil,
        limit: Int? = nil
    ) async throws -> [FootballMatch] {
        guard !leagues.isEmpty else { return [] }
        return try await fetchMatchesAcrossCompetitions(
            leagues: leagues,
            from: from,
            to: to,
            statuses: statuses,
            limit: limit
        )
    }

    private func fetchMatchesAcrossCompetitions(
        leagues: [League] = League.allCases,
        from: Date,
        to: Date,
        statuses: [String]?,
        limit: Int?
    ) async throws -> [FootballMatch] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var collected: [FootballMatch] = []
        for league in leagues {
            var query: [String: String] = [
                "dateFrom": formatter.string(from: from),
                "dateTo": formatter.string(from: to)
            ]
            if let statuses, !statuses.isEmpty {
                query["status"] = statuses.joined(separator: ",")
            }
            if let limit {
                query["limit"] = String(limit)
            }
            let response: FootballMatchesResponse = try await request(
                path: "/competitions/\(league.rawValue)/matches",
                query: query
            )
            collected.append(contentsOf: response.matches)
        }
        return collected
    }
    
    /// Get upcoming matches for a specific league
    func upcomingMatches(league: League, limit: Int = 15) async throws -> [FootballMatch] {
        let response: FootballMatchesResponse = try await request(
            path: "/competitions/\(league.rawValue)/matches",
            query: [
                "status": "SCHEDULED,TIMED,IN_PLAY,PAUSED",
                "limit": "\(limit)"
            ]
        )
        return response.matches
    }
    
    /// Get recent results for a league
    func recentResults(league: League, limit: Int = 10) async throws -> [FootballMatch] {
        let response: FootballMatchesResponse = try await request(
            path: "/competitions/\(league.rawValue)/matches",
            query: [
                "status": "FINISHED",
                "limit": "\(limit)"
            ]
        )
        return response.matches
    }
    
    /// Get matches for a date range
    func matches(league: League, from: Date, to: Date) async throws -> [FootballMatch] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let response: FootballMatchesResponse = try await request(
            path: "/competitions/\(league.rawValue)/matches",
            query: [
                "dateFrom": formatter.string(from: from),
                "dateTo": formatter.string(from: to)
            ]
        )
        return response.matches
    }
    
    /// Get currently live or paused matches for the active live-score competitions.
    /// Fallback chain: Sportmonks Pro → API-Football → football-data.org
    func fetchLiveScores(leagues: [League] = FootballDataPolicy.footballDataLiveLeagues) async throws -> [FootballMatch] {
        // 1. Try Sportmonks Pro (paid, full coverage)
        do {
            let proMatches = try await fetchLiveScoresFromFootballPro()
                .filter { FootballDataPolicy.supportsLiveScores(competition: $0.competition) }
            if !proMatches.isEmpty { return proMatches }
        } catch {
            serviceLogger.error("Pro API failed (\(error.localizedDescription, privacy: .public)), trying API-Football…")
        }
        
        // 2. Try API-Football (free, scoped coverage, single request)
        do {
            let apiFootballMatches = try await fetchLiveScoresFromAPIFootball()
            if !apiFootballMatches.isEmpty { return apiFootballMatches }
            serviceLogger.info("API-Football returned 0 live matches, trying football-data.org…")
        } catch {
            serviceLogger.error("API-Football failed (\(error.localizedDescription, privacy: .public)), trying football-data.org…")
        }
        
        // 3. Fallback to football-data.org (free, 6 European leagues only)
        return try await fetchLiveScoresFromFootballData(leagues: leagues)
    }
    
    /// Fetches currently live fixtures only for Fotty's active score competitions.
    func fetchLiveScoresFromAPIFootball() async throws -> [FootballMatch] {
        guard !Config.apiFootballKey.isEmpty else {
            throw FootballError.noAPIKey
        }
        guard let url = FootballDataPolicy.apiFootballLiveURL(host: Config.apiFootballHost) else {
            throw FootballError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.apiFootballKey, forHTTPHeaderField: "x-apisports-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FootballError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                throw FootballError.rateLimited
            }
            throw FootballError.httpError(httpResponse.statusCode)
        }
        
        let decoded = try JSONDecoder().decode(APIFootballResponse.self, from: data)
        let matches = decoded.response
            .filter {
                FootballDataPolicy.isAPIFootballLiveStatus($0.fixture.status.short)
                    && FootballDataPolicy.supportsLiveScores(
                    competitionId: $0.league.id,
                    competitionName: $0.league.name,
                    country: $0.league.country
                )
            }
            .compactMap { mapAPIFootballFixture($0) }
        serviceLogger.info("API-Football returned \(matches.count) scoped live matches")
        return matches
    }
    
    /// Map an API-Football fixture to our internal FootballMatch model
    func mapAPIFootballFixture(_ fixture: APIFootballFixture) -> FootballMatch? {
        let homeTeam = fixture.teams.home
        let awayTeam = fixture.teams.away
        
        let status: FootballMatch.MatchStatus
        switch fixture.fixture.status.short.uppercased() {
        case "1H", "2H", "ET", "LIVE": status = .inPlay
        case "HT", "BT": status = .paused
        case "FT", "AET", "PEN": status = .finished
        default: status = .scheduled
        }
        
        let events = fixture.events?.enumerated().compactMap { (index, event) -> FootballMatchEvent? in
            let type: FootballMatchEvent.EventType
            switch event.type.lowercased() {
            case "goal": type = .goal
            case "card":
                type = event.detail.lowercased().contains("red") ? .redCard : .yellowCard
            case "subst": type = .substitution
            case "var": type = .varDecision
            default: return nil
            }
            
            let uniqueId = (fixture.fixture.id << 16) | (index & 0xFFFF)
            return FootballMatchEvent(
                id: uniqueId,
                teamId: event.team.id,
                minute: event.time.elapsed,
                extraMinute: event.time.extra,
                type: type,
                player: event.player.name,
                assist: event.assist.name,
                info: event.detail,
                sortOrder: index
            )
        }
        
        return FootballMatch(
            id: fixture.fixture.id,
            apiFootballFixtureId: fixture.fixture.id,
            utcDate: fixture.fixture.date ?? "",
            status: status,
            matchday: nil,
            stage: nil,
            group: nil,
            homeTeam: FootballTeam(
                id: homeTeam.id,
                name: homeTeam.name,
                shortName: homeTeam.name,
                tla: nil,
                crest: homeTeam.logo
            ),
            awayTeam: FootballTeam(
                id: awayTeam.id,
                name: awayTeam.name,
                shortName: awayTeam.name,
                tla: nil,
                crest: awayTeam.logo
            ),
            score: MatchScore(
                winner: (fixture.goals.home ?? 0) > (fixture.goals.away ?? 0) ? "HOME_TEAM" :
                        (fixture.goals.away ?? 0) > (fixture.goals.home ?? 0) ? "AWAY_TEAM" : "DRAW",
                duration: "REGULAR",
                fullTime: ScoreDetail(home: fixture.goals.home ?? 0, away: fixture.goals.away ?? 0),
                halfTime: ScoreDetail(
                    home: fixture.score.halftime.home ?? 0,
                    away: fixture.score.halftime.away ?? 0
                )
            ),
            competition: MatchCompetition(
                id: fixture.league.id,
                name: fixture.league.name,
                code: "",
                emblem: fixture.league.logo,
                country: fixture.league.country
            ),
            referees: nil,
            events: events
        )
    }
    
    /// Fetches live matches from football-data.org free tier by querying each league.
    func fetchLiveScoresFromFootballData(leagues: [League] = FootballDataPolicy.footballDataLiveLeagues) async throws -> [FootballMatch] {
        var allMatches: [FootballMatch] = []
        let todayStr = Self.dateFormatter.string(from: Date())
        
        await withTaskGroup(of: [FootballMatch].self) { group in
            for league in leagues {
                group.addTask {
                    do {
                        let response: FootballMatchesResponse = try await self.request(
                            path: "/competitions/\(league.rawValue)/matches",
                            query: [
                                "status": "IN_PLAY,PAUSED,FINISHED",
                                "dateFrom": todayStr,
                                "dateTo": todayStr
                            ]
                        )
                        return response.matches
                    } catch {
                        serviceLogger.warning("Free API \(league.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }
            for await leagueMatches in group {
                allMatches.append(contentsOf: leagueMatches)
            }
        }
        
        serviceLogger.info("football-data.org returned \(allMatches.count) matches across \(leagues.count) leagues")
        return allMatches
    }

    
    /// Fetches all currently live fixtures across all leagues from Football Pro.
    func fetchLiveScoresFromFootballPro() async throws -> [FootballMatch] {
        let path = "/fixtures/livescores"
        let query = ["include": "participants;scores;league;league.country;state;time;events;events.type"]
        
        let response: FootballProFixtureResponse = try await requestPro(path: path, query: query)
        
        // Map Sportmonks v3 fixtures to our internal FootballMatch model
        return response.data.compactMap { (fixture: FootballProFixture) -> FootballMatch? in
            guard let participants = fixture.participants, participants.count >= 2 else { return nil }
            
            let homeParticipant = participants.first { $0.meta?.location == "home" } ?? participants[0]
            let awayParticipant = participants.first { $0.meta?.location == "away" } ?? participants[1]
            
            let homeGoals = fixture.scores?
                .filter { $0.description == "CURRENT" && $0.participant_id == homeParticipant.id }
                .first?.score.goals ?? 0
            
            let awayGoals = fixture.scores?
                .filter { $0.description == "CURRENT" && $0.participant_id == awayParticipant.id }
                .first?.score.goals ?? 0
            
            return FootballMatch(
                id: fixture.id,
                apiFootballFixtureId: nil,
                utcDate: "", // Not critical for live scoring
                status: mapProStatus(fixture.state?.short_name ?? ""),
                matchday: nil,
                stage: nil,
                group: nil,
                homeTeam: FootballTeam(id: homeParticipant.id, name: homeParticipant.name, shortName: homeParticipant.name, tla: nil, crest: homeParticipant.image_path?.absoluteString),
                awayTeam: FootballTeam(id: awayParticipant.id, name: awayParticipant.name, shortName: awayParticipant.name, tla: nil, crest: awayParticipant.image_path?.absoluteString),
                score: MatchScore(
                    winner: homeGoals > awayGoals ? "HOME_TEAM" : (awayGoals > homeGoals ? "AWAY_TEAM" : "DRAW"),
                    duration: "REGULAR",
                    fullTime: ScoreDetail(home: homeGoals, away: awayGoals),
                    halfTime: nil
                ),
                competition: MatchCompetition(
                    id: fixture.league?.id ?? 0,
                    name: fixture.league?.name ?? "",
                    code: "",
                    emblem: fixture.league?.image_path?.absoluteString,
                    country: fixture.league?.country?.name
                ),
                referees: nil,
                events: fixture.events?.compactMap { event in
                    // Create a globally unique ID by combining fixture and event IDs
                    // This prevents crashes from duplicate event IDs from the API
                    let uniqueId = (fixture.id << 16) | (event.id & 0xFFFF)
                    return FootballMatchEvent(
                        id: uniqueId,
                        teamId: event.team_id ?? 0,
                        minute: event.minute,
                        extraMinute: event.extra_minute,
                        type: mapProEventType(event.type),
                        player: event.player_name,
                        assist: event.related_player_name,
                        info: event.info,
                        sortOrder: event.sort_order ?? 0
                    )
                }
            )
        }
    }
    
    private func mapProEventType(_ type: FootballProEventType?) -> FootballMatchEvent.EventType {
        guard let name = type?.name?.lowercased() else { return .other }
        if name.contains("goal") { return .goal }
        if name.contains("yellow card") { return .yellowCard }
        if name.contains("red card") { return .redCard }
        if name.contains("substitution") { return .substitution }
        if name.contains("var") { return .varDecision }
        return .other
    }
    
    private func mapProStatus(_ status: String) -> FootballMatch.MatchStatus {
        switch status.uppercased() {
        case "LIVE", "1H", "2H", "HT": return .inPlay
        case "PAUSED": return .paused
        case "FT": return .finished
        default: return .scheduled
        }
    }
    
    private func requestPro<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        let baseURL = "https://\(Config.footballProHost)/api/v3/football"
        guard var components = URLComponents(string: baseURL + path) else {
            throw FootballError.invalidURL
        }
        
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = components.url else {
            throw FootballError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.rapidAPIKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(Config.footballProHost, forHTTPHeaderField: "X-RapidAPI-Host")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FootballError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                throw FootballError.rateLimited
            }
            throw FootballError.httpError(httpResponse.statusCode)
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    /// Get competition branding plus all registered teams for the current season.
    func competitionBrandingAndTeams(competitionCode: String) async throws -> (competition: MatchCompetition, teams: [FootballTeam]) {
        let response: CompetitionTeamsResponse = try await request(
            path: "/competitions/\(competitionCode)/teams"
        )
        return (response.competition, response.teams)
    }
    
    /// Get competition branding plus table teams via standings (lighter payload than /teams).
    func competitionBrandingAndStandingsTeams(competitionCode: String) async throws -> (competition: MatchCompetition, teams: [FootballTeam]) {
        let response: CompetitionStandingsResponse = try await request(
            path: "/competitions/\(competitionCode)/standings"
        )
        
        let flattened = response.standings.flatMap(\.table).map(\.team)
        guard !flattened.isEmpty else {
            return try await competitionBrandingAndTeams(competitionCode: competitionCode)
        }
        
        var deduped: [FootballTeam] = []
        var seenKeys: Set<String> = []
        for team in flattened {
            let key: String
            if let id = team.id {
                key = "id:\(id)"
            } else {
                key = "name:\((team.name ?? team.shortName ?? team.tla ?? "").lowercased())"
            }
            if seenKeys.insert(key).inserted {
                deduped.append(team)
            }
        }
        
        return (response.competition, deduped)
    }

    // MARK: - Networking
    
    private func request<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        if Config.prefersFootballDataProxy,
           footballProxyCooldownUntil.map({ Date() >= $0 }) ?? true {
            do {
                let proxied: T = try await requestViaFootballProxy(path: path, query: query)
                footballProxyCooldownUntil = nil
                return proxied
            } catch {
                footballProxyCooldownUntil = Date().addingTimeInterval(60)
                if Config.footballAPIKey.isEmpty {
                    throw error
                }
            }
        }

        guard !Config.footballAPIKey.isEmpty else {
            throw FootballError.noAPIKey
        }

        guard var components = URLComponents(string: baseURL + path) else {
            throw FootballError.invalidURL
        }
        
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = components.url else {
            throw FootballError.invalidURL
        }
        
        // Check cooldown
        if let cooldownUntil = cooldownUntil, Date() < cooldownUntil {
            serviceLogger.warning("Rate limit cooldown in effect until \(cooldownUntil, privacy: .public)")
            throw FootballError.rateLimited
        }
        
        let cacheKey = url.absoluteString
        
        // Check cache
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return try decoder.decode(T.self, from: cached.data)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FootballError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                // Set cooldown for 60 seconds
                cooldownUntil = Date().addingTimeInterval(60)
                serviceLogger.error("Hit rate limit. Cooling down for 60s.")
                throw FootballError.rateLimited
            }
            throw FootballError.httpError(httpResponse.statusCode)
        }
        
        // Update cache
        cache[cacheKey] = (data, Date())
        
        return try decoder.decode(T.self, from: data)
    }

    /// Routes football-data.org match feeds through Fotty Web so the API key stays server-side.
    private func requestViaFootballProxy<T: Decodable>(path: String, query: [String: String]) async throws -> T {
        guard path == "/matches" || path.hasPrefix("/competitions/"),
              path.hasSuffix("/matches") || path == "/matches" else {
            throw FootballError.invalidURL
        }
        guard let base = Config.footballProxyBaseURL else {
            throw FootballError.invalidURL
        }

        var proxyQuery = query
        if path != "/matches" {
            let parts = path.split(separator: "/").map(String.init)
            // /competitions/{code}/matches
            if parts.count >= 3 {
                proxyQuery["competition"] = parts[1]
            }
        }

        var components = URLComponents(url: base.appendingPathComponent("api/football/matches/"), resolvingAgainstBaseURL: false)
        if !proxyQuery.isEmpty {
            components?.queryItems = proxyQuery.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw FootballError.invalidURL
        }

        let cacheKey = "proxy:\(url.absoluteString)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return try decoder.decode(T.self, from: cached.data)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FootballError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FootballError.httpError(httpResponse.statusCode)
        }

        cache[cacheKey] = (data, Date())
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - API-Football Deep Analytics (Data Fortress)

    func fetchMatchStatistics(fixtureId: Int) async throws -> [APIFootballStatistics] {
        let urlString = "https://\(Config.apiFootballHost)/fixtures/statistics?fixture=\(fixtureId)"
        return try await fetchAPIFootballData(urlString: urlString)
    }

    func fetchMatchLineups(fixtureId: Int) async throws -> [APIFootballLineup] {
        let urlString = "https://\(Config.apiFootballHost)/fixtures/lineups?fixture=\(fixtureId)"
        return try await fetchAPIFootballData(urlString: urlString)
    }

    func fetchMatchEvents(fixtureId: Int) async throws -> [APIFootballEvent] {
        let urlString = "https://\(Config.apiFootballHost)/fixtures/events?fixture=\(fixtureId)"
        return try await fetchAPIFootballData(urlString: urlString)
    }

    func fetchAPIFootballLiveMatches() async throws -> [APIFootballFixture] {
        guard let url = FootballDataPolicy.apiFootballLiveURL(host: Config.apiFootballHost) else {
            throw FootballError.invalidURL
        }
        let response: APIFootballResponse = try await fetchAPIFootballDataFull(urlString: url.absoluteString)
        return response.response.filter {
            FootballDataPolicy.isAPIFootballLiveStatus($0.fixture.status.short)
                && FootballDataPolicy.supportsLiveScores(
                competitionId: $0.league.id,
                competitionName: $0.league.name,
                country: $0.league.country
            )
        }
    }

    private func fetchAPIFootballDataFull<T: Decodable>(urlString: String) async throws -> T {
        guard !Config.apiFootballKey.isEmpty else { throw FootballError.noAPIKey }
        guard let url = URL(string: urlString) else { throw FootballError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.apiFootballKey, forHTTPHeaderField: "x-apisports-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw FootballError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchAPIFootballData<T: Decodable>(urlString: String) async throws -> [T] {
        guard !Config.apiFootballKey.isEmpty else { throw FootballError.noAPIKey }
        guard let url = URL(string: urlString) else { throw FootballError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.apiFootballKey, forHTTPHeaderField: "x-apisports-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw FootballError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(APIFootballResponseWrapper<T>.self, from: data)
        return decoded.response
    }
}

private struct CompetitionTeamsResponse: Decodable {
    let competition: MatchCompetition
    let teams: [FootballTeam]
}

private struct CompetitionStandingsResponse: Decodable {
    let competition: MatchCompetition
    let standings: [CompetitionStanding]
}

private struct CompetitionStanding: Decodable {
    let table: [CompetitionTableEntry]
}

private struct CompetitionTableEntry: Decodable {
    let team: FootballTeam
}

// MARK: - Errors

enum FootballError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case rateLimited
    case noAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "Server error (\(code))"
        case .rateLimited: return "Rate limited — try again in a minute"
        case .noAPIKey: return "Football API key not configured"
        }
    }
}

// MARK: - Team News (RSS)

struct TeamNewsHeadline: Identifiable, Hashable {
    enum TopicType: String, Hashable {
        case team
        case league
    }
    
    let id: String
    let teamName: String
    let topicType: TopicType
    let title: String
    let source: String?
    let publishedAt: Date?
    let url: URL?
}

actor TeamNewsService {
    static let shared = TeamNewsService()
    
    private let session: URLSession
    private var cache: [String: (items: [TeamNewsHeadline], timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 300
    private static let preferredLeagueOrder = [
        "Premier League",
        "Champions League",
        "La Liga",
        "Serie A",
        "Bundesliga",
        "Ligue 1",
        "MLS"
    ]
    private static let managedCompetitionIDs: [FootballCompetitionID] = [
        .premierLeague, .championsLeague, .laLiga, .serieA, .bundesliga, .ligue1
    ]
    private static let managedLeagueInferenceRules: [(league: String, aliases: [String])] =
    managedCompetitionIDs.compactMap { competitionID in
        guard let snapshot = FootballCompetitionCatalog.snapshots[competitionID] else { return nil }
        return (snapshot.displayName, snapshot.searchAliases)
    }
    private static let leagueInferenceRules: [(league: String, aliases: [String])] =
        managedLeagueInferenceRules + [
        (
            "MLS",
            [
                "inter miami", "la galaxy", "lafc", "new york city", "new york red bulls",
                "atlanta united", "seattle sounders", "portland timbers", "austin fc",
                "toronto fc", "vancouver whitecaps"
            ]
        )
    ]
    
    private static let rfc822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
    
    private static let fallbackRfc822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }
    
    func headlines(
        for teamNames: [String],
        leagueTopics: [String] = [],
        perTeamLimit: Int = 3,
        perLeagueLimit: Int = 2,
        totalLimit: Int = 12
    ) async throws -> [TeamNewsHeadline] {
        let normalizedTeams = teamNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizedLeagues = leagueTopics
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !normalizedTeams.isEmpty || !normalizedLeagues.isEmpty else { return [] }
        
        var merged: [TeamNewsHeadline] = []
        
        for team in normalizedTeams {
            let cacheKey = "team:\(team.lowercased())"
            if let cached = cache[cacheKey],
               Date().timeIntervalSince(cached.timestamp) < cacheDuration {
                merged.append(contentsOf: cached.items.prefix(perTeamLimit))
                continue
            }
            
            let fetched = try await fetchHeadlines(
                for: team,
                topicType: .team,
                query: "\"\(team)\" football club news",
                limit: perTeamLimit
            )
            cache[cacheKey] = (fetched, Date())
            merged.append(contentsOf: fetched)
        }
        
        for league in normalizedLeagues where perLeagueLimit > 0 {
            let cacheKey = "league:\(league.lowercased())"
            if let cached = cache[cacheKey],
               Date().timeIntervalSince(cached.timestamp) < cacheDuration {
                merged.append(contentsOf: cached.items.prefix(perLeagueLimit))
                continue
            }
            
            let fetched = try await fetchHeadlines(
                for: league,
                topicType: .league,
                query: "\(league) football league news",
                limit: perLeagueLimit
            )
            cache[cacheKey] = (fetched, Date())
            merged.append(contentsOf: fetched)
        }
        
        let deduped = dedupe(merged)
            .sorted { lhs, rhs in
                let lhsDate = lhs.publishedAt ?? .distantPast
                let rhsDate = rhs.publishedAt ?? .distantPast
                return lhsDate > rhsDate
            }
        
        return Array(deduped.prefix(totalLimit))
    }

    /// Headlines scoped to a single fixture — avoids unrelated league/table stories in Match Hub.
    func matchHeadlines(
        homeTeam: String,
        awayTeam: String,
        competitionName: String?,
        isLive: Bool,
        limit: Int = 6
    ) async throws -> [TeamNewsHeadline] {
        let home = homeTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = awayTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !home.isEmpty, !away.isEmpty else { return [] }

        let competition = competitionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var queries: [String] = []
        if !competition.isEmpty {
            queries.append("\"\(home)\" \"\(away)\" \(competition) football news when:7d")
        }
        queries.append("\"\(home)\" \"\(away)\" football news when:7d")
        queries.append("\"\(home)\" football club news when:3d")
        queries.append("\"\(away)\" football club news when:3d")

        var merged: [TeamNewsHeadline] = []
        for query in queries {
            let batch = try await fetchHeadlines(
                for: home,
                topicType: .team,
                query: query,
                limit: 4
            )
            merged.append(contentsOf: batch)
            if dedupe(merged).count >= limit * 2 { break }
        }

        let filtered = dedupe(merged).filter {
            isRelevantToMatch(
                $0,
                homeTeam: home,
                awayTeam: away,
                competitionName: competition.isEmpty ? nil : competition,
                isLive: isLive
            )
        }
        .map { headline in
            TeamNewsHeadline(
                id: headline.id,
                teamName: resolveMatchTopicLabel(
                    title: headline.title,
                    homeTeam: home,
                    awayTeam: away,
                    competitionName: competition.isEmpty ? nil : competition
                ),
                topicType: headline.topicType,
                title: headline.title,
                source: headline.source,
                publishedAt: headline.publishedAt,
                url: headline.url
            )
        }
        .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

        return Array(filtered.prefix(limit))
    }
    
    nonisolated static func inferLeagueTopics(for teamNames: [String]) -> [String] {
        let normalizedTeams = teamNames
            .map { normalizedLookupString($0) }
            .filter { !$0.isEmpty }
        
        guard !normalizedTeams.isEmpty else { return [] }
        
        var inferred = Set<String>()
        for team in normalizedTeams {
            for rule in leagueInferenceRules {
                if rule.aliases.contains(where: { team.contains(normalizedLookupString($0)) }) {
                    inferred.insert(rule.league)
                }
            }
        }
        
        return inferred.sorted { lhs, rhs in
            let lhsIndex = preferredLeagueOrder.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = preferredLeagueOrder.firstIndex(of: rhs) ?? Int.max
            if lhsIndex == rhsIndex {
                return lhs < rhs
            }
            return lhsIndex < rhsIndex
        }
    }
    
    private nonisolated static func normalizedLookupString(_ rawValue: String) -> String {
        rawValue
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    private func fetchHeadlines(
        for topicName: String,
        topicType: TeamNewsHeadline.TopicType,
        query: String,
        limit: Int
    ) async throws -> [TeamNewsHeadline] {
        guard var components = URLComponents(string: "https://news.google.com/rss/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        
        guard let url = components.url else {
            return []
        }
        
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        
        let parser = TeamNewsRSSParser()
        let items = parser.parse(data: data)
        
        let mapped = items.compactMap { item -> TeamNewsHeadline? in
            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            let identifier = (item.link?.absoluteString ?? "\(topicName)|\(trimmedTitle)")
                .lowercased()
            
            return TeamNewsHeadline(
                id: identifier,
                teamName: topicName,
                topicType: topicType,
                title: trimmedTitle,
                source: item.source,
                publishedAt: parseDate(item.pubDate),
                url: item.link
            )
        }
        
        guard limit > 0 else { return [] }
        return Array(mapped.prefix(limit))
    }

    private func isRelevantToMatch(
        _ headline: TeamNewsHeadline,
        homeTeam: String,
        awayTeam: String,
        competitionName: String?,
        isLive: Bool
    ) -> Bool {
        let title = Self.normalizedLookupString(headline.title)
        let home = Self.normalizedLookupString(homeTeam)
        let away = Self.normalizedLookupString(awayTeam)
        let competition = competitionName.map(Self.normalizedLookupString) ?? ""

        let mentionsHome = titleContainsTeam(title, team: home)
        let mentionsAway = titleContainsTeam(title, team: away)
        guard mentionsHome || mentionsAway else { return false }

        let blockedLeagues = ["premier league", "serie a", "bundesliga", "ligue 1", "mls", "champions league", "europa league"]
        for league in blockedLeagues where !competition.contains(Self.normalizedLookupString(league)) {
            if title.contains(Self.normalizedLookupString(league)) { return false }
        }

        let junkPhrases = [
            "standings", "league table", "table —", "table -",
            "where to watch", "live stream", "tv channel",
            "predictions:", "prediction:", "betting odds",
            "lineups, score", "lineups score predictions"
        ]
        if junkPhrases.contains(where: { title.contains($0) }) { return false }
        if isLive && (title.contains("predictions") || title.contains("preview")) { return false }

        if !competition.isEmpty {
            let compTokens = competition.split(separator: " ").map(String.init).filter { $0.count > 3 }
            let mentionsCompetition = compTokens.contains(where: { title.contains($0) })
            if mentionsHome && mentionsAway { return true }
            if mentionsCompetition { return true }
            if isLive { return mentionsHome || mentionsAway }
        }

        return true
    }

    private func titleContainsTeam(_ title: String, team: String) -> Bool {
        if team.isEmpty { return false }
        if title.contains(team) { return true }
        let tokens = team.split(separator: " ").map(String.init).filter { $0.count > 3 }
        guard !tokens.isEmpty else { return false }
        return tokens.contains(where: { title.contains($0) })
    }

    private func resolveMatchTopicLabel(
        title: String,
        homeTeam: String,
        awayTeam: String,
        competitionName: String?
    ) -> String {
        let normalizedTitle = Self.normalizedLookupString(title)
        let mentionsHome = titleContainsTeam(normalizedTitle, team: Self.normalizedLookupString(homeTeam))
        let mentionsAway = titleContainsTeam(normalizedTitle, team: Self.normalizedLookupString(awayTeam))
        if mentionsHome && mentionsAway {
            return competitionName ?? "Match"
        }
        if mentionsAway { return awayTeam }
        if mentionsHome { return homeTeam }
        return homeTeam
    }
    
    private func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        if let parsed = Self.rfc822Formatter.date(from: rawValue) {
            return parsed
        }
        return Self.fallbackRfc822Formatter.date(from: rawValue)
    }
    
    private func dedupe(_ input: [TeamNewsHeadline]) -> [TeamNewsHeadline] {
        var byID: [String: TeamNewsHeadline] = [:]
        for item in input {
            if byID[item.id] == nil {
                byID[item.id] = item
            }
        }
        return Array(byID.values)
    }
}

private struct TeamNewsRSSItem {
    var title: String = ""
    var source: String?
    var pubDate: String?
    var link: URL?
}

private final class TeamNewsRSSParser: NSObject, XMLParserDelegate {
    private var items: [TeamNewsRSSItem] = []
    private var currentItem: TeamNewsRSSItem?
    private var currentText = ""
    
    func parse(data: Data) -> [TeamNewsRSSItem] {
        items = []
        currentItem = nil
        currentText = ""
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentText = ""
        if elementName.lowercased() == "item" {
            currentItem = TeamNewsRSSItem()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard var item = currentItem else {
            currentText = ""
            return
        }
        
        switch element {
        case "title":
            if !text.isEmpty { item.title = text }
        case "source":
            if !text.isEmpty { item.source = text }
        case "pubdate":
            if !text.isEmpty { item.pubDate = text }
        case "link":
            if let url = URL(string: text), !text.isEmpty { item.link = url }
        case "item":
            items.append(item)
            currentItem = nil
            currentText = ""
            return
        default:
            break
        }
        
        currentItem = item
        currentText = ""
    }
}

// MARK: - Team Brand Service
// Central service for managing team branding assets (badges, colors) across the app.
// Consolidates fetching from TheSportsDB and other providers with a persistent cache.
@MainActor
class TeamBrandService: ObservableObject {
    static let shared = TeamBrandService()
    
    @Published private(set) var teamBadgeURLsByLookup: [String: URL] = [:]
    @Published private(set) var isLoading = false
    
    private let cacheKey = "fotty.cache.teamBadges"
    private var hasBootstrapped = false
    
    private var sportsDBLeagues: [String] = [
        "English Premier League", "Spanish La Liga", "Italian Serie A", "German Bundesliga", "French Ligue 1",
        "NBA", "WNBA", "MLB", "Argentinian LNB", "IPL Cricket"
    ]
    
    private var inFlightResolutions: [String: Task<URL?, Error>] = [:]
    
    private init() {
        seedSafetyNet()
        loadFromPersistentCache()
    }

    /// Exact current names/artwork from ESPN's existing NBA/MLB image catalog,
    /// verified 2026-08-27. Static fallbacks: no new runtime catalog API request.
    static let majorLeagueBadgeURLs: [String: URL] = {
        let leagues: [String: [String: String]] = [
            "nba": [
                "atlanta hawks": "atl", "boston celtics": "bos", "brooklyn nets": "bkn",
                "charlotte hornets": "cha", "chicago bulls": "chi", "cleveland cavaliers": "cle",
                "dallas mavericks": "dal", "denver nuggets": "den", "detroit pistons": "det",
                "golden state warriors": "gs", "houston rockets": "hou", "indiana pacers": "ind",
                "la clippers": "lac", "los angeles clippers": "lac", "los angeles lakers": "lal",
                "memphis grizzlies": "mem", "miami heat": "mia", "milwaukee bucks": "mil",
                "minnesota timberwolves": "min", "new orleans pelicans": "no", "new york knicks": "ny",
                "oklahoma city thunder": "okc", "orlando magic": "orl", "philadelphia 76ers": "phi",
                "phoenix suns": "phx", "portland trail blazers": "por", "sacramento kings": "sac",
                "san antonio spurs": "sa", "toronto raptors": "tor", "utah jazz": "utah", "washington wizards": "wsh"
            ],
            "mlb": [
                "arizona diamondbacks": "ari", "athletics": "ath", "atlanta braves": "atl",
                "baltimore orioles": "bal", "boston red sox": "bos", "chicago cubs": "chc",
                "chicago white sox": "chw", "cincinnati reds": "cin", "cleveland guardians": "cle",
                "colorado rockies": "col", "detroit tigers": "det", "houston astros": "hou",
                "kansas city royals": "kc", "los angeles angels": "laa", "los angeles dodgers": "lad",
                "miami marlins": "mia", "milwaukee brewers": "mil", "minnesota twins": "min",
                "new york mets": "nym", "new york yankees": "nyy", "philadelphia phillies": "phi",
                "pittsburgh pirates": "pit", "san diego padres": "sd", "san francisco giants": "sf",
                "seattle mariners": "sea", "st louis cardinals": "stl", "tampa bay rays": "tb",
                "texas rangers": "tex", "toronto blue jays": "tor", "washington nationals": "wsh"
            ]
        ]
        var badges: [String: URL] = [:]
        for (league, teams) in leagues {
            for (name, code) in teams {
                badges[name] = URL(string: "https://a.espncdn.com/i/teamlogos/\(league)/500/\(code).png")
            }
        }
        return badges
    }()

    static func mergingBadgeCache(_ cached: [String: String], into seed: [String: URL]) -> [String: URL] {
        var lookup = seed
        for (key, value) in cached {
            guard let url = URL(string: value), let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()), url.host != nil else { continue }
            lookup[key] = url
        }
        return lookup
    }
    
    private func seedSafetyNet() {
        // High-priority safety net for major teams to ensure instant branding after cache purges
        let nba = "https://a.espncdn.com/combiner/i?img=/i/teamlogos/nba/500/"
        let wnba = "https://a.espncdn.com/combiner/i?img=/i/teamlogos/wnba/500/"
        let l = "https://a.espncdn.com/combiner/i?img=/i/teamlogos/leagues/500/wnba.png"

        let safety: [String: String] = [
            "los angeles lakers": nba + "lal.png", "new york knicks": nba + "ny.png",
            "golden state warriors": nba + "gs.png", "philadelphia 76ers": nba + "phi.png",
            "boston celtics": nba + "bos.png", "chicago bulls": nba + "chi.png",
            "oklahoma city thunder": nba + "okc.png", "minnesota timberwolves": nba + "min.png",
            "san antonio spurs": nba + "sa.png", "dallas mavericks": nba + "dal.png",
            "new york liberty": wnba + "ny.png", "las vegas aces": wnba + "lv.png",
            "los angeles sparks": wnba + "la.png", "chicago sky": wnba + "chi.png",
            "seattle storm": wnba + "sea.png", "indiana fever": wnba + "ind.png",
            "portland fire": l, "toronto tempo": wnba + "tor.png"
        ]
        
        for (name, urlStr) in safety {
            if let url = URL(string: urlStr) {
                teamBadgeURLsByLookup[name] = url
            }
        }
        teamBadgeURLsByLookup.merge(Self.majorLeagueBadgeURLs) { _, bundled in bundled }
    }
    
    func badgeURL(for teamName: String, triggerSearch: Bool = false) -> URL? {
        let key = normalizedKey(teamName)
        guard !key.isEmpty else { return nil }

        if let url = teamBadgeURLsByLookup[key] {
            return url
        }
        
        let stripped = stripTeamNameSuffixes(key)
        if let url = teamBadgeURLsByLookup[stripped] {
            return url
        }

        // Intentionally no dictionary "fuzzy" pass: prefix/substring checks routinely
        // cross-wire unrelated clubs (e.g. Livingston → Liverpool, Partick → Parma).
        
        if triggerSearch {
            Task { _ = await resolveBadgeURL(for: teamName) }
        }
        
        return nil
    }
    
    func resolveBadgeURL(for teamName: String) async -> URL? {
        let key = normalizedKey(teamName)
        guard !key.isEmpty else { return nil }
        
        if let url = badgeURL(for: teamName) { return url }
        if let inFlight = inFlightResolutions[key] { return try? await inFlight.value }
        
        let task = Task<URL?, Error> {
            if let searchedURL = await searchTeamBadge(teamName: teamName) {
                return searchedURL
            }
            return nil
        }
        
        inFlightResolutions[key] = task
        do {
            let result = try await task.value
            inFlightResolutions[key] = nil
            return result
        } catch {
            inFlightResolutions[key] = nil
            return nil
        }
    }
    
    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        await forceRefresh()
        hasBootstrapped = true
    }
    
    func forceRefresh() async {
        // High-priority bootstrap for critical leagues to avoid "Cold Start"
        let priorityLeagues = ["NBA", "WNBA", "MLB", "English Premier League"]
        for league in priorityLeagues {
            _ = await fetchLeagueCatalog(leagueName: league)
        }
        
        await refreshAll()
    }
    
    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        
        var allLookups: [String: URL] = teamBadgeURLsByLookup
        await withTaskGroup(of: [String: URL].self) { group in
            for league in sportsDBLeagues {
                group.addTask { await self.fetchLeagueBadges(leagueName: league) }
            }
            for await leagueLookup in group {
                for (key, url) in leagueLookup {
                    if allLookups[key] == nil { allLookups[key] = url }
                }
            }
        }
        self.teamBadgeURLsByLookup = allLookups
        saveToPersistentCache()
    }
    
    // MARK: - Onboarding Helpers
    
    struct CatalogTeam: Identifiable {
        let id: String
        let displayName: String
        let badgeURL: URL?
    }
    
    // MARK: - League Bootstrapping
    // TheSportsDB free key limits 'search_all_teams' to 10 results.
    // We bootstrap the major leagues to ensure 100% membership.
    private let leagueBootstrap = FootballCompetitionCatalog.providerBootstrap()

    func fetchLeagueCatalog(leagueName: String) async -> [CatalogTeam] {
        if let bootstrappedNames = leagueBootstrap[leagueName] {
            var results: [CatalogTeam] = []
            
            // Fetch in parallel to avoid sequential delay
            await withTaskGroup(of: CatalogTeam?.self) { group in
                for name in bootstrappedNames {
                    group.addTask {
                        if let url = await self.resolveBadgeURL(for: name) {
                            return CatalogTeam(id: url.absoluteString, displayName: name, badgeURL: url)
                        }
                        let leagueKey = FootballDataPolicy.normalizedTeamMatchKey(leagueName)
                        let teamKey = FootballDataPolicy.normalizedTeamMatchKey(name)
                        return CatalogTeam(
                            id: "competition:\(leagueKey):\(teamKey)",
                            displayName: name,
                            badgeURL: nil
                        )
                    }
                }
                
                for await team in group {
                    if let team = team { results.append(team) }
                }
            }
            
            if !results.isEmpty {
                return results.sorted { $0.displayName < $1.displayName }
            }
        }
        
        // Fallback to the generic search (limited to 10 by API)
        let lookup = await fetchLeagueBadges(leagueName: leagueName)
        
        // Deduplicate by URL: If multiple names point to the same badge, they are aliases.
        var uniqueTeamsByURL: [URL: CatalogTeam] = [:]
        
        for (name, url) in lookup {
            // Favor the longest name as the "official" display name (e.g., "Arsenal" over "Ars")
            if let existing = uniqueTeamsByURL[url] {
                if name.count > existing.displayName.count {
                    uniqueTeamsByURL[url] = CatalogTeam(id: url.absoluteString, displayName: name.capitalized, badgeURL: url)
                }
            } else {
                uniqueTeamsByURL[url] = CatalogTeam(id: url.absoluteString, displayName: name.capitalized, badgeURL: url)
            }
        }
        
        return uniqueTeamsByURL.values.sorted { $0.displayName < $1.displayName }
    }
    
    func searchCatalog(query: String) async -> [CatalogTeam] {
        guard query.count >= 2 else { return [] }
        let normalizedQuery = normalizedKey(query)
        let cachedMatches = teamBadgeURLsByLookup.filter { $0.key.contains(normalizedQuery) }
        
        var uniqueResults: [URL: CatalogTeam] = [:]
        
        for (name, url) in cachedMatches {
            if let existing = uniqueResults[url] {
                if name.count > existing.displayName.count {
                    uniqueResults[url] = CatalogTeam(id: url.absoluteString, displayName: name.capitalized, badgeURL: url)
                }
            } else {
                uniqueResults[url] = CatalogTeam(id: url.absoluteString, displayName: name.capitalized, badgeURL: url)
            }
        }
        
        if !uniqueResults.isEmpty {
            return uniqueResults.values.sorted { $0.displayName < $1.displayName }
        }
        
        // If not in cache, trigger a remote search
        if let url = await resolveBadgeURL(for: query) {
            return [CatalogTeam(id: url.absoluteString, displayName: query.capitalized, badgeURL: url)]
        }
        
        return []
    }
    
    private func fetchLeagueBadges(leagueName: String) async -> [String: URL] {
        var lookup: [String: URL] = [:]
        guard var components = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/3/search_all_teams.php") else { return lookup }
        components.queryItems = [URLQueryItem(name: "l", value: leagueName)]
        guard let url = components.url else { return lookup }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SportsDBResponse.self, from: data)
            guard let teams = response.teams else { return lookup }
            
            for team in teams {
                guard let badgeStr = team.strBadge, let badgeURL = URL(string: badgeStr) else { continue }
                let candidates = [team.strTeam, team.strTeamShort, team.strTeamAlternate].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                for name in candidates {
                    let key = normalizedKey(name)
                    if !key.isEmpty { lookup[key] = badgeURL }
                }
            }
            return lookup
        } catch {
            return lookup
        }
    }
    
    private func searchTeamBadge(teamName: String) async -> URL? {
        guard var components = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/3/searchteams.php") else { return nil }
        components.queryItems = [URLQueryItem(name: "t", value: teamName)]
        guard let url = components.url else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SportsDBResponse.self, from: data)
            guard let teams = response.teams else { return nil }
            guard let team = teams.first(where: {
                looksLikeSameTeam(
                    search: teamName,
                    primaryName: $0.strTeam ?? "",
                    alternateNames: [$0.strTeamShort, $0.strTeamAlternate]
                )
            }) else { return nil }
            
            if let badgeStr = team.strBadge, let badgeURL = URL(string: badgeStr) {
                let mainKey = normalizedKey(team.strTeam ?? teamName)
                var updated = teamBadgeURLsByLookup
                updated[mainKey] = badgeURL
                let candidates = [team.strTeam, team.strTeamShort, team.strTeamAlternate].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                for name in candidates {
                    let key = normalizedKey(name)
                    if !key.isEmpty { updated[key] = badgeURL }
                }
                self.teamBadgeURLsByLookup = updated
                saveToPersistentCache()
                return badgeURL
            }
        } catch { }
        return nil
    }

    /// True when `search` plausibly refers to the same club as `primaryName` / alternates (not Parma for "Partick Thistle").
    private func looksLikeSameTeam(search: String, primaryName: String, alternateNames: [String?]) -> Bool {
        let q = normalizedKey(search)
        guard !q.isEmpty else { return false }
        let primary = normalizedKey(primaryName)
        guard !primary.isEmpty else { return false }
        if q == primary { return true }
        let extras = alternateNames.compactMap { $0 }.map { normalizedKey($0) }.filter { !$0.isEmpty }
        if extras.contains(q) { return true }
        let spacedPrimary = " \(primary) "
        for ex in extras where ex.count >= 3 {
            if q == ex { return true }
            if spacedPrimary.contains(" \(ex) ") { return true }
        }
        let tokens = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if tokens.count >= 2 {
            return tokens.filter { $0.count >= 2 }.allSatisfy { spacedPrimary.contains(" \($0) ") }
        }
        guard let w = tokens.first else { return false }
        if w.count >= 4 {
            return spacedPrimary.contains(" \(w) ")
        }
        return primary == w || extras.contains(w)
    }
    
    private func stripTeamNameSuffixes(_ name: String) -> String {
        name.replacingOccurrences(of: "\\b(fc|cf|afc|ac|sc|united|city|rovers|town|athletic|wanderers)\\b", with: " ", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizedKey(_ rawValue: String) -> String {
        rawValue.lowercased()
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func saveToPersistentCache() {
        let stringMap = teamBadgeURLsByLookup.reduce(into: [String: String]()) { acc, pair in
            acc[pair.key] = pair.value.absoluteString
        }
        UserDefaults.standard.set(stringMap, forKey: cacheKey)
    }
    
    private func loadFromPersistentCache() {
        // One-time purge of potentially corrupted/stale 1.5 cache
        let purgeKey = "fotty.cache.purge.v1.6.01"
        if !UserDefaults.standard.bool(forKey: purgeKey) {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.set(true, forKey: purgeKey)
            serviceLogger.info("Performed one-time legacy cache purge.")
        }

        guard let stringMap = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] else { return }
        // A sparse persisted cache must not erase freshly bundled safety nets.
        self.teamBadgeURLsByLookup = Self.mergingBadgeCache(stringMap, into: teamBadgeURLsByLookup)
    }
}

private struct SportsDBResponse: Decodable {
    let teams: [SportsDBTeam]?
}

private struct SportsDBTeam: Decodable {
    let strTeam: String?
    let strTeamShort: String?
    let strTeamAlternate: String?
    let strBadge: String?
}

// MARK: - API-Football Models

struct APIFootballResponse: Decodable {
    let response: [APIFootballFixture]
}

struct APIFootballFixture: Decodable {
    let fixture: APIFootballFixtureInfo
    let league: APIFootballLeague
    let teams: APIFootballTeams
    let goals: APIFootballGoals
    let score: APIFootballScore
    let events: [APIFootballEvent]?
}

struct APIFootballFixtureInfo: Decodable {
    let id: Int
    let date: String?
    let status: APIFootballStatus
}

struct APIFootballStatus: Decodable {
    let long: String
    let short: String
    let elapsed: Int?
}

struct APIFootballLeague: Decodable {
    let id: Int
    let name: String
    let country: String?
    let logo: String?
}

struct APIFootballTeams: Decodable {
    let home: APIFootballTeam
    let away: APIFootballTeam
}

struct APIFootballTeam: Decodable {
    let id: Int
    let name: String
    let logo: String?
}

struct APIFootballGoals: Decodable {
    let home: Int?
    let away: Int?
}

struct APIFootballScore: Decodable {
    let halftime: APIFootballGoals
    let fulltime: APIFootballGoals
}

struct APIFootballEvent: Decodable {
    let time: APIFootballEventTime
    let team: APIFootballEventTeam
    let player: APIFootballEventPlayer
    let assist: APIFootballEventPlayer
    let type: String
    let detail: String
}

struct APIFootballEventTime: Decodable {
    let elapsed: Int
    let extra: Int?
}

struct APIFootballEventTeam: Decodable {
    let id: Int
    let name: String
}

struct APIFootballEventPlayer: Decodable {
    let id: Int?
    let name: String?
}
