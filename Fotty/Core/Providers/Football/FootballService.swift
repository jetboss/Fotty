import os.log
import Foundation

private let serviceLogger = Logger(subsystem: "com.jelani.Fotty", category: "FootballService")

// MARK: - Football Schedule Service
// Uses football-data.org v4 API (free tier: 10 req/min, six European leagues).

actor FootballService {
    
    static let shared = FootballService()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    private let apiKey: String
    private let proxyBaseURL: URL?
    private let prefersProxy: Bool
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
    private var footballProxyFailure: Error?
    
    init(
        session: URLSession? = nil,
        apiKey: String = Config.footballAPIKey,
        proxyBaseURL: URL? = Config.footballProxyBaseURL,
        prefersProxy: Bool = Config.prefersFootballDataProxy
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "X-Auth-Token": apiKey,
            "Accept": "application/json"
        ]
        self.session = session ?? URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.apiKey = apiKey
        self.proxyBaseURL = proxyBaseURL
        self.prefersProxy = prefersProxy
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
            // An empty verified window is valid, not a reason to fan out six
            // additional requests or try an unconfigured premium provider.
            return response.matches
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            // Keyless installations have no independent direct transport. A
            // proxy outage must retain its real error, not become noAPIKey.
            guard !apiKey.isEmpty else { throw error }
            serviceLogger.error("Global /matches failed; using configured per-competition fallback.")
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
        formatter.timeZone = TimeZone(identifier: "UTC")
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
        formatter.timeZone = TimeZone(identifier: "UTC")
        
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
        if prefersProxy {
            if let until = footballProxyCooldownUntil, Date() < until {
                if apiKey.isEmpty { throw footballProxyFailure ?? FootballError.invalidResponse }
            } else {
                do {
                    let proxied: T = try await requestViaFootballProxy(path: path, query: query)
                    footballProxyCooldownUntil = nil
                    footballProxyFailure = nil
                    return proxied
                } catch {
                    try Task.checkCancellation()
                    if error is CancellationError || (error as? URLError)?.code == .cancelled {
                        throw error
                    }
                    footballProxyCooldownUntil = Date().addingTimeInterval(60)
                    footballProxyFailure = error
                    if apiKey.isEmpty {
                        throw error
                    }
                }
            }
        }

        guard !apiKey.isEmpty else {
            throw FootballError.noAPIKey
        }

        guard var components = URLComponents(string: baseURL + path) else {
            throw FootballError.invalidURL
        }
        
        if !query.isEmpty {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
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
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Token")
        let (data, response) = try await session.data(for: request)
        
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
        
        let decoded = try decoder.decode(T.self, from: data)
        cache[cacheKey] = (data, Date())
        return decoded
    }

    /// Routes football-data.org match feeds through Fotty Web so the API key stays server-side.
    private func requestViaFootballProxy<T: Decodable>(path: String, query: [String: String]) async throws -> T {
        guard path == "/matches" || path.hasPrefix("/competitions/"),
              path.hasSuffix("/matches") || path == "/matches" else {
            throw FootballError.invalidURL
        }
        guard let base = proxyBaseURL else {
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
            components?.queryItems = proxyQuery.keys.sorted().map { URLQueryItem(name: $0, value: proxyQuery[$0]) }
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

        let decoded = try decoder.decode(T.self, from: data)
        cache[cacheKey] = (data, Date())
        return decoded
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
    private let refreshDateKey = "fotty.cache.teamBadges.lastRefresh"
    private let badgeRefreshFreshnessInterval: TimeInterval = 24 * 60 * 60
    private var hasBootstrapped = false
    private var lastBootstrapAttempt: Date?
    private let bootstrapRetryInterval: TimeInterval = 120
    private let badgeDefaults: UserDefaults
    private let badgeNow: () -> Date
    private let bootstrapRefresh: (@MainActor () async -> Int)?
    
    /// The free SportsDB catalog is intentionally limited to leagues that do
    /// not have a complete bundled/league-level source. Sending one request
    /// per football club caused cold-start 429s and incomplete badge grids.
    private let sportsDBLeagues: [String] = [
        "Argentinian LNB", "Caribbean Premier League", "Indian Premier League"
    ]

    /// One metadata request per league returns the complete current badge
    /// catalog. Source-controlled aliases below keep provider naming exact.
    private let espnBadgeLeagues: [(sport: String, league: String)] = [
        ("soccer", "eng.1"), ("soccer", "esp.1"), ("soccer", "ita.1"),
        ("soccer", "ger.1"), ("soccer", "fra.1"),
        ("soccer", "eng.2"), ("soccer", "esp.2"), ("soccer", "ita.2"),
        ("soccer", "ger.2"), ("soccer", "fra.2"),
        ("soccer", "usa.1"), ("soccer", "mex.1"),
        ("soccer", "uefa.champions"), ("soccer", "uefa.europa"),
        ("soccer", "aut.1"), ("soccer", "nor.1"), ("soccer", "isr.1"),
        ("football", "nfl"), ("football", "college-football"), ("football", "cfl")
    ]
    
    private var inFlightResolutions: [String: Task<URL?, Error>] = [:]
    
    private convenience init() {
        self.init(defaults: .standard, now: Date.init)
    }

    /// Tests isolate preferences, time and transport without touching providers.
    init(defaults: UserDefaults, now: @escaping () -> Date,
         bootstrapRefresh: (@MainActor () async -> Int)? = nil) {
        badgeDefaults = defaults
        badgeNow = now
        self.bootstrapRefresh = bootstrapRefresh
        seedSafetyNet()
        loadFromPersistentCache()
    }

    /// Exact current names/artwork from ESPN's existing NBA/MLB image catalog,
    /// verified 2026-08-27. Static fallbacks: no new runtime catalog API request.
    nonisolated static let majorLeagueBadgeURLs: [String: URL] = {
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
            ],
            "wnba": [
                "atlanta dream": "atl", "chicago sky": "chi", "connecticut sun": "con",
                "dallas wings": "dal", "golden state valkyries": "gs", "indiana fever": "ind",
                "las vegas aces": "lv", "los angeles sparks": "la", "minnesota lynx": "min",
                "new york liberty": "ny", "phoenix mercury": "phx", "portland fire": "por",
                "seattle storm": "sea", "toronto tempo": "tor", "washington mystics": "wsh"
            ],
            "nhl": [
                "anaheim ducks": "ana", "boston bruins": "bos", "buffalo sabres": "buf",
                "calgary flames": "cgy", "carolina hurricanes": "car", "chicago blackhawks": "chi",
                "colorado avalanche": "col", "columbus blue jackets": "cbj", "dallas stars": "dal",
                "detroit red wings": "det", "edmonton oilers": "edm", "florida panthers": "fla",
                "los angeles kings": "la", "minnesota wild": "min", "montreal canadiens": "mtl",
                "nashville predators": "nsh", "new jersey devils": "nj", "new york islanders": "nyi",
                "new york rangers": "nyr", "ottawa senators": "ott", "philadelphia flyers": "phi",
                "pittsburgh penguins": "pit", "san jose sharks": "sj", "seattle kraken": "sea",
                "st louis blues": "stl", "st. louis blues": "stl", "tampa bay lightning": "tb",
                "toronto maple leafs": "tor", "utah mammoth": "utah", "vancouver canucks": "van",
                "vegas golden knights": "vgk", "washington capitals": "wsh", "winnipeg jets": "wpg"
            ]
        ]
        var badges: [String: URL] = [:]
        for (league, teams) in leagues {
            for (name, code) in teams {
                badges[name] = URL(string: "https://a.espncdn.com/i/teamlogos/\(league)/500/\(code).png")
            }
        }

        // Current CPL names used by the source-controlled 2026 schedule. Keep
        // ampersand/provider wording aliases exact rather than fuzzy-matching.
        let cpl: [String: String] = [
            "antigua & barbuda falcons": "https://r2.thesportsdb.com/images/media/team/badge/fwozcu1752736011.png",
            "antigua and barbuda falcons": "https://r2.thesportsdb.com/images/media/team/badge/fwozcu1752736011.png",
            "barbados tridents": "https://r2.thesportsdb.com/images/media/team/badge/kg9ypo1786962015.png",
            "barbados royals": "https://r2.thesportsdb.com/images/media/team/badge/kg9ypo1786962015.png",
            "guyana amazon warriors": "https://r2.thesportsdb.com/images/media/team/badge/amct1d1641785128.png",
            "jamaica kingsmen": "https://r2.thesportsdb.com/images/media/team/badge/7a48ht1786962002.png",
            "saint lucia kings": "https://r2.thesportsdb.com/images/media/team/badge/981c6z1752736461.png",
            "st lucia kings": "https://r2.thesportsdb.com/images/media/team/badge/981c6z1752736461.png",
            "st kitts & nevis patriots": "https://r2.thesportsdb.com/images/media/team/badge/t2zoaz1641785142.png",
            "st kitts and nevis patriots": "https://r2.thesportsdb.com/images/media/team/badge/t2zoaz1641785142.png",
            "trinbago knight riders": "https://r2.thesportsdb.com/images/media/team/badge/c8zwd61641785158.png"
        ]
        for (name, rawURL) in cpl {
            if let url = URL(string: rawURL) { badges[name] = url }
        }

        let cfl: [String: String] = [
            "bc lions": "https://r2.thesportsdb.com/images/media/team/badge/ysxssy1424732039.png",
            "calgary stampeders": "https://r2.thesportsdb.com/images/media/team/badge/lksemj1565196917.png",
            "edmonton elks": "https://r2.thesportsdb.com/images/media/team/badge/ehy8wx1770834697.png",
            "hamilton tiger-cats": "https://r2.thesportsdb.com/images/media/team/badge/qtwsuq1424727420.png",
            "hamilton tiger cats": "https://r2.thesportsdb.com/images/media/team/badge/qtwsuq1424727420.png",
            "montreal alouettes": "https://r2.thesportsdb.com/images/media/team/badge/8m9v4n1770835125.png",
            "ottawa redblacks": "https://r2.thesportsdb.com/images/media/team/badge/k8wjz71546002654.png",
            "ottawa red blacks": "https://r2.thesportsdb.com/images/media/team/badge/k8wjz71546002654.png",
            "saskatchewan roughriders": "https://r2.thesportsdb.com/images/media/team/badge/xrdull1630952245.png",
            "toronto argonauts": "https://r2.thesportsdb.com/images/media/team/badge/5a57ou1628555372.png",
            "winnipeg blue bombers": "https://r2.thesportsdb.com/images/media/team/badge/4bo4wj1561667273.png"
        ]
        for (name, rawURL) in cfl {
            if let url = URL(string: rawURL) { badges[name] = url }
        }
        return badges
    }()

    /// Short provider names such as "Bulldogs" are ambiguous outside their
    /// sport. Keep these event-only fallbacks scoped by category rather than
    /// putting them in the global team-name dictionary.
    private static let sportSpecificBadgeURLs: [String: [String: URL]] = {
        let rugby: [String: String] = [
            "bulldogs": "https://r2.thesportsdb.com/images/media/team/badge/ggzq4e1768487178.png",
            "broncos": "https://r2.thesportsdb.com/images/media/team/badge/yjgl741768487372.png",
            "titans": "https://r2.thesportsdb.com/images/media/team/badge/4qqmp81646347724.png",
            "dolphins": "https://r2.thesportsdb.com/images/media/team/badge/tyoy421672068536.png",
            "rabbitohs": "https://r2.thesportsdb.com/images/media/team/badge/0m4unp1552072677.png",
            "roosters": "https://r2.thesportsdb.com/images/media/team/badge/by299w1646347883.png",
            "warriors": "https://r2.thesportsdb.com/images/media/team/badge/w8b9kw1646347767.png",
            "sea eagles": "https://r2.thesportsdb.com/images/media/team/badge/oke63j1768508683.png",
            "cowboys": "https://r2.thesportsdb.com/images/media/team/badge/q6xu7c1646347820.png",
            "raiders": "https://r2.thesportsdb.com/images/media/team/badge/54ebov1768508580.png",
            "sharks": "https://r2.thesportsdb.com/images/media/team/badge/qn3n5r1552073088.png",
            "storm": "https://r2.thesportsdb.com/images/media/team/badge/hpdn401646347751.png",
            "dragons": "https://r2.thesportsdb.com/images/media/team/badge/2dcs6y1646347870.png",
            "eels": "https://r2.thesportsdb.com/images/media/team/badge/5tvma21646347846.png",
            "panthers": "https://r2.thesportsdb.com/images/media/team/badge/zjh0jo1771495164.png",
            "wests tigers": "https://r2.thesportsdb.com/images/media/team/badge/cs6i6f1646347894.png"
        ]
        return [
            "rugby": rugby.compactMapValues { URL(string: $0) }
        ]
    }()

    static func sportSpecificBadgeURL(for teamName: String, category: String) -> URL? {
        let sportKey = category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let teamKey = teamName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return sportSpecificBadgeURLs[sportKey]?[teamKey]
    }

    static func mergingBadgeCache(_ cached: [String: String], into seed: [String: URL]) -> [String: URL] {
        var lookup = seed
        for (key, value) in cached {
            guard let url = URL(string: value), let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()), url.host != nil else { continue }
            lookup[key] = url
        }
        return lookup
    }
    
    private nonisolated static var safetyNetBadgeURLs: [String: URL] {
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
        
        var lookup: [String: URL] = [:]
        for (name, urlStr) in safety {
            if let url = URL(string: urlStr) {
                lookup[name] = url
            }
        }
        lookup.merge(Self.majorLeagueBadgeURLs) { _, bundled in bundled }
        return lookup
    }

    private func seedSafetyNet() {
        teamBadgeURLsByLookup = Self.safetyNetBadgeURLs
    }

    /// Fresh remote entries replace older remote cache entries. Publisher
    /// priority follows the configured order, never task completion order.
    /// Source-controlled safety nets remain intentional overrides; a missing or
    /// failed remote league must not erase previously accepted branding.
    nonisolated static func refreshedBadgeCache(
        existing: [String: URL], publishers: [[String: URL]], protected: [String: URL]
    ) -> [String: URL] {
        var result = existing
        var refreshedKeys = Set<String>()
        for publisher in publishers {
            for (key, url) in publisher {
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                      refreshedKeys.insert(key).inserted else { continue }
                result[key] = url
            }
        }
        result.merge(protected) { _, intentionalOverride in intentionalOverride }
        return result
    }

    nonisolated static func validatedBadgeEntries(_ entries: [String: URL]) -> [String: URL] {
        entries.filter { _, url in
            ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
        }
    }
    
    func badgeURL(for teamName: String, triggerSearch: Bool = false) -> URL? {
        let key = Self.normalizedKey(teamName)
        guard !key.isEmpty else { return nil }

        if let url = teamBadgeURLsByLookup[key] {
            return url
        }
        
        let stripped = Self.stripTeamNameSuffixes(key)
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
        let key = Self.normalizedKey(teamName)
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
        let now = badgeNow()
        if let refreshedAt = badgeDefaults.object(forKey: refreshDateKey) as? Date,
           (0..<badgeRefreshFreshnessInterval).contains(now.timeIntervalSince(refreshedAt)) {
            hasBootstrapped = true
            return
        }
        if let lastBootstrapAttempt,
           (0..<bootstrapRetryInterval).contains(now.timeIntervalSince(lastBootstrapAttempt)) {
            return
        }
        lastBootstrapAttempt = now
        let count: Int
        if let bootstrapRefresh { count = await bootstrapRefresh() }
        else { count = await refreshAll() }
        hasBootstrapped = count > 0
        if count > 0 { badgeDefaults.set(badgeNow(), forKey: refreshDateKey) }
    }
    
    func forceRefresh() async {
        _ = await refreshAll()
    }
    
    @discardableResult
    func refreshAll() async -> Int {
        isLoading = true
        defer { isLoading = false }
        
        let sportsDBLeagues = sportsDBLeagues
        let espnBadgeLeagues = espnBadgeLeagues
        let publishers = await withTaskGroup(of: (Int, [String: URL]).self,
                                             returning: [[String: URL]].self) { group in
            var publishers = Array(repeating: [String: URL](), count: sportsDBLeagues.count + espnBadgeLeagues.count)
            for (index, league) in sportsDBLeagues.enumerated() {
                group.addTask { (index, await Self.fetchLeagueBadges(leagueName: league)) }
            }
            for (index, league) in espnBadgeLeagues.enumerated() {
                group.addTask {
                    (sportsDBLeagues.count + index, await Self.fetchESPNLeagueBadges(sport: league.sport, league: league.league))
                }
            }
            for await leagueLookup in group {
                publishers[leagueLookup.0] = Self.validatedBadgeEntries(leagueLookup.1)
            }
            return publishers
        }
        let remoteResolvedCount = publishers.reduce(0) { $0 + $1.count }
        // A one-off search may have resolved another club during the await.
        // Merge into current state, not the pre-request snapshot, so that useful
        // independently completed work cannot be lost by this publication.
        let allLookups = Self.refreshedBadgeCache(existing: teamBadgeURLsByLookup, publishers: publishers,
                                                protected: Self.safetyNetBadgeURLs)
        // The existing bundled/persisted snapshot remains available while this
        // refresh runs. Publish once so dozens of league completions cannot
        // repeatedly invalidate every badge consumer during the first scroll.
        self.teamBadgeURLsByLookup = allLookups
        saveToPersistentCache()
        if remoteResolvedCount > 0 {
            badgeDefaults.set(badgeNow(), forKey: refreshDateKey)
        }
        return remoteResolvedCount
    }
    
    // MARK: - Onboarding Helpers
    
    struct CatalogTeam: Identifiable {
        let displayName: String
        let sportCategory: String
        let badgeURL: URL?
        var identity: SportsTeamIdentity {
            .init(displayName: displayName, sportCategory: sportCategory, badgeURL: badgeURL)
        }
        var id: String { identity.id }
    }
    
    // MARK: - League Bootstrapping
    // TheSportsDB free key limits 'search_all_teams' to 10 results.
    // We bootstrap the major leagues to ensure 100% membership.
    private let leagueBootstrap = FootballCompetitionCatalog.providerBootstrap()

    func fetchLeagueCatalog(leagueName: String) async -> [CatalogTeam] {
        if let bootstrappedNames = leagueBootstrap[leagueName] {
            if !hasBootstrapped { await bootstrapIfNeeded() }
            return bootstrappedNames.map { name in
                CatalogTeam(displayName: name, sportCategory: "football", badgeURL: badgeURL(for: name))
            }
            .sorted { $0.displayName < $1.displayName }
        }
        if leagueName == "Caribbean Premier League" {
            return CPLTeam.allCases.map {
                CatalogTeam(displayName: $0.rawValue, sportCategory: "cricket", badgeURL: badgeURL(for: $0.rawValue))
            }.sorted { $0.displayName < $1.displayName }
        }
        let majorTeams = SportsTeamIdentity.majorTeams.filter { $0.league == leagueName.lowercased() }
        if !majorTeams.isEmpty {
            return majorTeams.map { .init(displayName: $0.identity.displayName,
                                         sportCategory: $0.identity.sportCategory, badgeURL: $0.identity.badgeURL) }
        }
        return await fetchFollowableTeams(endpoint: "search_all_teams.php", query: .init(name: "l", value: leagueName))
    }
    
    func searchCatalog(query: String) async -> [CatalogTeam] {
        guard query.count >= 2 else { return [] }
        let local = Self.followableCatalogSearch(query: query, badges: teamBadgeURLsByLookup)
        if !local.isEmpty { return local }
        // Provider results carry their own name and sport. A badge lookup alone
        // cannot establish the identity of the query or distinguish shared logos.
        return await fetchFollowableTeams(endpoint: "searchteams.php", query: .init(name: "t", value: query))
    }

    static func followableCatalogSearch(query: String, badges: [String: URL]) -> [CatalogTeam] {
        let terms = SportsTeamIdentity.normalized(query).split(separator: " ")
        guard !terms.isEmpty else { return [] }
        let football = FootballCompetitionCatalog.snapshots.values.flatMap(\.clubs)
            + FootballCompetitionCatalog.additionalClubIdentities
        let names = football.flatMap { [$0.name] + $0.aliases }
            + CPLTeam.allCases.flatMap(SportsTeamIdentity.cplNames)
            + SportsTeamIdentity.majorTeams.flatMap(\.aliases)
        var results: [String: CatalogTeam] = [:]
        for name in names {
            let normalized = SportsTeamIdentity.normalized(name)
            guard terms.allSatisfy({ normalized.contains($0) }),
                  let identity = SportsTeamIdentity.known(name: name) else { continue }
            let badge = badges[identity.displayName.lowercased()] ?? badges[name.lowercased()] ?? identity.badgeURL
            results[identity.id] = .init(displayName: identity.displayName,
                                         sportCategory: identity.sportCategory, badgeURL: badge)
        }
        return results.values.sorted { $0.displayName < $1.displayName }
    }

    static func followableTeams(from data: Data) throws -> [CatalogTeam] {
        let payload = try JSONDecoder().decode(SportsDBResponse.self, from: data)
        var results: [String: CatalogTeam] = [:]
        for team in payload.teams ?? [] {
            guard let name = team.strTeam?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !["home", "away", "tbd", "tbc", "unknown"].contains(SportsTeamIdentity.normalized(name)),
                  let rawSport = team.strSport, let sport = SportsTeamIdentity.sport(rawSport) else { continue }
            let known = SportsTeamIdentity.known(name: name, category: sport)
            let badge = team.strBadge.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
            let result = CatalogTeam(displayName: known?.displayName ?? name, sportCategory: sport, badgeURL: badge ?? known?.badgeURL)
            results[result.id] = result
        }
        return results.values.sorted { $0.displayName < $1.displayName }
    }

    private func fetchFollowableTeams(endpoint: String, query: URLQueryItem) async -> [CatalogTeam] {
        guard var components = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/3/\(endpoint)") else { return [] }
        components.queryItems = [query]
        guard let url = components.url else { return [] }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode), data.count <= 2_000_000 else { return [] }
            return try Self.followableTeams(from: data)
        } catch { return [] }
    }
    
    private nonisolated static func fetchLeagueBadges(leagueName: String) async -> [String: URL] {
        var lookup: [String: URL] = [:]
        guard var components = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/3/search_all_teams.php") else { return lookup }
        components.queryItems = [URLQueryItem(name: "l", value: leagueName)]
        guard let url = components.url else { return lookup }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return lookup }
            let payload = try JSONDecoder().decode(SportsDBResponse.self, from: data)
            guard let teams = payload.teams else { return lookup }
            
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

    private nonisolated static func fetchESPNLeagueBadges(sport: String, league: String) async -> [String: URL] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/teams?limit=1000") else {
            return [:]
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [:] }
            let payload = try JSONDecoder().decode(ESPNTeamCatalogResponse.self, from: data)
            let teams = payload.sports?.first?.leagues?.first?.teams ?? []
            var lookup: [String: URL] = [:]

            for wrapped in teams {
                guard let badgeString = wrapped.team.logos?.first?.href,
                      let badgeURL = URL(string: badgeString) else { continue }
                let names = [
                    wrapped.team.displayName,
                    wrapped.team.shortDisplayName,
                    wrapped.team.abbreviation
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                for name in names {
                    let key = normalizedKey(name)
                    if !key.isEmpty { lookup[key] = badgeURL }
                }
            }

            // Expand an exact provider hit to every source-controlled spelling
            // of that club. We deliberately do not use fuzzy substring matches.
            for snapshot in FootballCompetitionCatalog.snapshots.values {
                for club in snapshot.clubs {
                    let names = [club.name] + club.aliases
                    guard let badgeURL = names.lazy.compactMap({ lookup[normalizedKey($0)] }).first else { continue }
                    for name in names {
                        let key = normalizedKey(name)
                        if !key.isEmpty { lookup[key] = badgeURL }
                    }
                }
            }

            return lookup
        } catch {
            return [:]
        }
    }
    
    private func searchTeamBadge(teamName: String) async -> URL? {
        guard var components = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/3/searchteams.php") else { return nil }
        components.queryItems = [URLQueryItem(name: "t", value: teamName)]
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(SportsDBResponse.self, from: data)
            guard let teams = payload.teams else { return nil }
            guard let team = teams.first(where: {
                looksLikeSameTeam(
                    search: teamName,
                    primaryName: $0.strTeam ?? "",
                    alternateNames: [$0.strTeamShort, $0.strTeamAlternate]
                )
            }) else { return nil }
            
            if let badgeStr = team.strBadge, let badgeURL = URL(string: badgeStr) {
                let mainKey = Self.normalizedKey(team.strTeam ?? teamName)
                var updated = teamBadgeURLsByLookup
                updated[mainKey] = badgeURL
                let candidates = [team.strTeam, team.strTeamShort, team.strTeamAlternate].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                for name in candidates {
                    let key = Self.normalizedKey(name)
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
        let q = Self.normalizedKey(search)
        guard !q.isEmpty else { return false }
        let primary = Self.normalizedKey(primaryName)
        guard !primary.isEmpty else { return false }
        if q == primary { return true }
        let extras = alternateNames.compactMap { $0 }.map { Self.normalizedKey($0) }.filter { !$0.isEmpty }
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
    
    private nonisolated static func stripTeamNameSuffixes(_ name: String) -> String {
        let suffixes: Set<Substring> = ["fc", "cf", "afc", "ac", "sc", "united", "city", "rovers", "town", "athletic", "wanderers"]
        return name.split(whereSeparator: \.isWhitespace)
            .filter { !suffixes.contains($0) }
            .joined(separator: " ")
    }

    private nonisolated static func normalizedKey(_ rawValue: String) -> String {
        rawValue.lowercased()
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: ".", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func saveToPersistentCache() {
        let stringMap = teamBadgeURLsByLookup.reduce(into: [String: String]()) { acc, pair in
            acc[pair.key] = pair.value.absoluteString
        }
        badgeDefaults.set(stringMap, forKey: cacheKey)
    }
    
    private func loadFromPersistentCache() {
        // One-time purge of potentially corrupted/stale 1.5 cache
        let purgeKey = "fotty.cache.purge.v1.6.01"
        if !badgeDefaults.bool(forKey: purgeKey) {
            badgeDefaults.removeObject(forKey: cacheKey)
            badgeDefaults.set(true, forKey: purgeKey)
            serviceLogger.info("Performed one-time legacy cache purge.")
        }

        guard let stringMap = badgeDefaults.dictionary(forKey: cacheKey) as? [String: String] else { return }
        // A sparse persisted cache must not erase freshly bundled safety nets.
        self.teamBadgeURLsByLookup = Self.mergingBadgeCache(stringMap, into: teamBadgeURLsByLookup)
        // Existing valid cache predates the freshness key. Treat it as fresh
        // once so an app upgrade does not perform a multi-league bootstrap
        // while the owner is making the first catalog gesture.
        if badgeDefaults.object(forKey: refreshDateKey) == nil, !stringMap.isEmpty {
            badgeDefaults.set(badgeNow(), forKey: refreshDateKey)
        }
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
    let strSport: String?
}

private struct ESPNTeamCatalogResponse: Decodable {
    struct Sport: Decodable {
        struct League: Decodable {
            struct WrappedTeam: Decodable {
                struct Team: Decodable {
                    struct Logo: Decodable { let href: String? }
                    let displayName: String?
                    let shortDisplayName: String?
                    let abbreviation: String?
                    let logos: [Logo]?
                }
                let team: Team
            }
            let teams: [WrappedTeam]?
        }
        let leagues: [League]?
    }
    let sports: [Sport]?
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
