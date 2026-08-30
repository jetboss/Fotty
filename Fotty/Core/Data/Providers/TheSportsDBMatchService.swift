import Foundation

/// Lineups, formations, and event metadata from TheSportsDB (v1 free key or v2 premium).
actor TheSportsDBMatchService {
    static let shared = TheSportsDBMatchService()
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0) ?? .current

    private let session: URLSession
    private var eventIDCache: [String: String] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    func enrich(_ hub: MatchHubData) async -> MatchHubData {
        guard let eventID = await resolveEventID(for: hub) else {
            let newsOnly = await fetchMatchNews(hub: hub)
            guard !newsOnly.isEmpty else { return hub }
            return MatchHubData(
                fixture: hub.fixture,
                homeTeam: hub.homeTeam,
                awayTeam: hub.awayTeam,
                score: hub.score,
                events: hub.events,
                homeLineup: hub.homeLineup,
                awayLineup: hub.awayLineup,
                statistics: hub.statistics,
                teamNews: newsOnly,
                lastUpdated: Date(),
                dataQuality: [.official, .verified].contains(hub.dataQuality) ? hub.dataQuality : .fallback
            )
        }

        async let lineupsTask = fetchLineups(eventID: eventID, hub: hub)
        async let newsTask = fetchMatchNews(hub: hub)
        let (lineups, news) = await (lineupsTask, newsTask)

        let homeLineup = hub.homeLineup ?? lineups.home
        let awayLineup = hub.awayLineup ?? lineups.away
        let enrichedEvents = hub.events.isEmpty ? lineups.timelineEvents : hub.events
        let usedFallback = hub.homeLineup == nil || hub.awayLineup == nil

        return MatchHubData(
            fixture: hub.fixture,
            homeTeam: hub.homeTeam,
            awayTeam: hub.awayTeam,
            score: hub.score,
            events: enrichedEvents,
            homeLineup: homeLineup,
            awayLineup: awayLineup,
            statistics: hub.statistics,
            teamNews: news,
            lastUpdated: Date(),
            dataQuality: usedFallback && hub.dataQuality != .official ? .fallback : hub.dataQuality
        )
    }

    // MARK: - Event resolution

    private func resolveEventID(for hub: MatchHubData) async -> String? {
        let cacheKey = "\(hub.fixture.id)|\(hub.homeTeam.name)|\(hub.awayTeam.name)"
        if let cached = eventIDCache[cacheKey] { return cached }

        let apiFootballID = hub.fixture.apiFootballFixtureId ?? hub.fixture.id
        if let byAPI = await searchEventByAPIFootballId(apiFootballID, date: hub.fixture.utcDate) {
            eventIDCache[cacheKey] = byAPI
            return byAPI
        }

        let homeNames = teamSearchNames(hub.homeTeam)
        let awayNames = teamSearchNames(hub.awayTeam)
        for home in homeNames {
            for away in awayNames {
                if let fromSearch = await searchEventID(
                    home: home,
                    away: away,
                    date: hub.fixture.utcDate,
                    apiFootballFixtureID: apiFootballID
                ) {
                    eventIDCache[cacheKey] = fromSearch
                    return fromSearch
                }
            }
        }
        return nil
    }

    private func searchEventByAPIFootballId(_ apiFootballID: String, date: Date) async -> String? {
        guard !apiFootballID.isEmpty, apiFootballID != "0" else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        for dayOffset in [-1, 0, 1] {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let day = dayFormatter.string(from: dayDate)
            guard let payload = await requestV1(path: "eventsday.php", query: ["d": day, "s": "Soccer"]),
                  let events = payload["event"] as? [[String: Any]] else { continue }
            if let match = events.first(where: { ($0["idAPIfootball"] as? String) == apiFootballID }),
               let eventID = match["idEvent"] as? String {
                return eventID
            }
        }
        return nil
    }

    private func searchEventID(home: String, away: String, date: Date, apiFootballFixtureID: String) async -> String? {
        let slug = "\(slugify(home))_vs_\(slugify(away))"
        if let payload = await requestV1(path: "searchevents.php", query: ["e": slug]),
           let events = payload["event"] as? [[String: Any]] {
            if let matched = pickBestEvent(events, date: date, apiFootballID: apiFootballFixtureID) {
                return matched
            }
        }

        let day = dayFormatter.string(from: date)
        if let payload = await requestV1(path: "eventsday.php", query: ["d": day, "s": "Soccer"]),
           let events = payload["event"] as? [[String: Any]] {
            if let matched = pickBestEvent(events, date: date, apiFootballID: apiFootballFixtureID, home: home, away: away) {
                return matched
            }
        }
        return nil
    }

    private func teamSearchNames(_ team: FottyTeam) -> [String] {
        var names: [String] = [team.name]
        if let short = team.shortName, !short.isEmpty, short != team.name {
            names.append(short)
        }
        let key = team.name.lowercased()
        if key.contains("barcel") || key.contains("barça") || key.contains("barca") {
            names.append(contentsOf: ["Barcelona", "FC Barcelona"])
        }
        if key.contains("betis") {
            names.append(contentsOf: ["Real Betis", "Betis"])
        }
        if key.contains("real madrid") || key == "real" {
            names.append("Real Madrid")
        }
        if key.contains("man city") || key.contains("manchester city") {
            names.append(contentsOf: ["Manchester City", "Man City"])
        }
        if key.contains("man united") || key.contains("manchester united") {
            names.append(contentsOf: ["Manchester United", "Man United"])
        }
        return Array(Set(names))
    }

    /// Resolves API-Football fixture id from TheSportsDB event metadata (no API-Football quota).
    func resolveAPIFootballFixtureId(home: String, away: String, date: Date) async -> String? {
        let cacheKey = "af|\(home)|\(away)|\(Int(date.timeIntervalSince1970))"
        if let cached = eventIDCache[cacheKey], !cached.isEmpty, cached.allSatisfy({ $0.isNumber }) {
            return cached
        }

        if let payload = await requestV1(path: "searchevents.php", query: ["e": "\(slugify(home))_vs_\(slugify(away))"]),
           let events = payload["event"] as? [[String: Any]],
           let id = pickBestAPIFootballId(events, date: date, home: home, away: away) {
            eventIDCache[cacheKey] = id
            return id
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        let day = dayFormatter.string(from: date)
        if let payload = await requestV1(path: "eventsday.php", query: ["d": day, "s": "Soccer"]),
           let events = payload["event"] as? [[String: Any]],
           let id = pickBestAPIFootballId(events, date: date, home: home, away: away) {
            eventIDCache[cacheKey] = id
            return id
        }
        return nil
    }

    private func pickBestAPIFootballId(
        _ events: [[String: Any]],
        date: Date,
        home: String,
        away: String
    ) -> String? {
        let calendar = Calendar(identifier: .gregorian)
        let targetDay = calendar.dateComponents(in: Self.utcTimeZone, from: date).day

        let filtered = events.filter { row in
            guard let homeName = row["strHomeTeam"] as? String,
                  let awayName = row["strAwayTeam"] as? String,
                  let apiId = row["idAPIfootball"] as? String,
                  !apiId.isEmpty, apiId != "0" else { return false }
            let homeMatch = namesMatch(homeName, home)
            let awayMatch = namesMatch(awayName, away)
            if !(homeMatch && awayMatch) { return false }
            if let dateEvent = row["dateEvent"] as? String,
               let eventDate = ISO8601DateFormatter().date(from: dateEvent + "T12:00:00Z") ?? dayFormatter.date(from: dateEvent) {
                return calendar.dateComponents(in: Self.utcTimeZone, from: eventDate).day == targetDay
            }
            return true
        }

        return (filtered.first ?? events.first)?["idAPIfootball"] as? String
    }

    private func pickBestEvent(
        _ events: [[String: Any]],
        date: Date,
        apiFootballID: String,
        home: String? = nil,
        away: String? = nil
    ) -> String? {
        if let byAPI = events.first(where: { ($0["idAPIfootball"] as? String) == apiFootballID }),
           let id = byAPI["idEvent"] as? String {
            return id
        }

        let calendar = Calendar(identifier: .gregorian)
        let targetDay = calendar.dateComponents(in: Self.utcTimeZone, from: date).day

        let filtered = events.filter { row in
            guard let homeName = row["strHomeTeam"] as? String,
                  let awayName = row["strAwayTeam"] as? String else { return false }
            if let home, let away {
                let homeMatch = namesMatch(homeName, home)
                let awayMatch = namesMatch(awayName, away)
                if !(homeMatch && awayMatch) { return false }
            }
            if let dateEvent = row["dateEvent"] as? String,
               let eventDate = ISO8601DateFormatter().date(from: dateEvent + "T12:00:00Z") ?? dayFormatter.date(from: dateEvent) {
                return calendar.dateComponents(in: Self.utcTimeZone, from: eventDate).day == targetDay
            }
            return true
        }

        return (filtered.first ?? events.first)?["idEvent"] as? String
    }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Lineups & timeline

    private struct LineupBundle {
        var home: FottyLineup?
        var away: FottyLineup?
        var timelineEvents: [FottyMatchEvent] = []
    }

    private func fetchLineups(eventID: String, hub: MatchHubData) async -> LineupBundle {
        if Config.theSportsDBPrefersV2,
           let v2Rows = await requestV2Lineup(eventID: eventID),
           !v2Rows.isEmpty {
            return mapLineupRows(v2Rows, hub: hub, formations: await fetchFormations(eventID: eventID))
        }

        guard let payload = await requestV1(path: "lookuplineup.php", query: ["id": eventID]),
              let rows = payload["lineup"] as? [[String: Any]],
              !rows.isEmpty else {
            return LineupBundle()
        }
        let formations = await fetchFormations(eventID: eventID)
        return mapLineupRows(rows, hub: hub, formations: formations)
    }

    private func fetchFormations(eventID: String) async -> (home: String?, away: String?) {
        guard let payload = await requestV1(path: "lookupevent.php", query: ["id": eventID]),
              let event = payload["events"] as? [[String: Any]],
              let first = event.first else {
            return (nil, nil)
        }
        let home = (first["strHomeFormation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = (first["strAwayFormation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            home?.isEmpty == false ? home : nil,
            away?.isEmpty == false ? away : nil
        )
    }

    private func mapLineupRows(
        _ rows: [[String: Any]],
        hub: MatchHubData,
        formations: (home: String?, away: String?)
    ) -> LineupBundle {
        var homeStarters: [FottyPlayer] = []
        var homeSubs: [FottyPlayer] = []
        var awayStarters: [FottyPlayer] = []
        var awaySubs: [FottyPlayer] = []

        for row in rows {
            let name = (row["strPlayer"] as? String) ?? "Player"
            let number = (row["intSquadNumber"] as? String).flatMap(Int.init)
            let position = row["strPosition"] as? String
            let player = FottyPlayer(
                id: (row["idPlayer"] as? String) ?? UUID().uuidString,
                name: name,
                number: number,
                position: position,
                x: nil,
                y: nil
            )
            let isHome = (row["strHome"] as? String)?.lowercased() == "yes"
            let isSub = (row["strSubstitute"] as? String)?.lowercased() == "yes"
            if isHome {
                if isSub { homeSubs.append(player) } else { homeStarters.append(player) }
            } else {
                if isSub { awaySubs.append(player) } else { awayStarters.append(player) }
            }
        }

        var bundle = LineupBundle()
        if !homeStarters.isEmpty {
            bundle.home = FottyLineup(
                teamId: hub.homeTeam.id,
                formation: formations.home ?? inferFormation(from: homeStarters),
                startingXi: homeStarters,
                substitutes: homeSubs,
                coach: nil
            )
        }
        if !awayStarters.isEmpty {
            bundle.away = FottyLineup(
                teamId: hub.awayTeam.id,
                formation: formations.away ?? inferFormation(from: awayStarters),
                startingXi: awayStarters,
                substitutes: awaySubs,
                coach: nil
            )
        }
        return bundle
    }

    private func requestV2Lineup(eventID: String) async -> [[String: Any]]? {
        guard let data = await requestV2(path: "lookup/event_lineup/\(eventID)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let lineup = json["lineup"] as? [[String: Any]] { return lineup }
        if let lookup = json["lookup"] as? [[String: Any]] { return lookup }
        return nil
    }

    private func inferFormation(from starters: [FottyPlayer]) -> String? {
        var buckets: [String: Int] = [:]
        for player in starters {
            let key = (player.position ?? "").lowercased()
            if key.contains("goal") { buckets["GK", default: 0] += 1 }
            else if key.contains("def") { buckets["DEF", default: 0] += 1 }
            else if key.contains("mid") { buckets["MID", default: 0] += 1 }
            else if key.contains("for") || key.contains("strik") || key.contains("wing") {
                buckets["FWD", default: 0] += 1
            }
        }
        let def = buckets["DEF", default: 0]
        let mid = buckets["MID", default: 0]
        let fwd = buckets["FWD", default: 0]
        guard def > 0, mid > 0, fwd > 0 else { return nil }
        return "\(def)-\(mid)-\(fwd)"
    }

    // MARK: - Team news

    private func fetchMatchNews(hub: MatchHubData) async -> [FottyTeamNewsItem] {
        let headlines = (try? await TeamNewsService.shared.matchHeadlines(
            homeTeam: hub.homeTeam.name,
            awayTeam: hub.awayTeam.name,
            competitionName: hub.fixture.competition.audienceFacingName,
            isLive: hub.fixture.status.isLive,
            limit: 6
        )) ?? []
        return headlines.map {
            FottyTeamNewsItem(
                id: $0.id,
                teamName: $0.teamName,
                title: $0.title,
                source: $0.source,
                url: $0.url,
                publishedAt: $0.publishedAt
            )
        }
    }

    // MARK: - HTTP

    private func requestV1(path: String, query: [String: String]) async -> [String: Any]? {
        guard var components = URLComponents(
            string: "https://www.thesportsdb.com/api/v1/json/\(Config.theSportsDBAPIKey)/\(path)"
        ) else { return nil }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func requestV2(path: String) async -> Data? {
        guard let url = URL(string: "https://www.thesportsdb.com/api/v2/json/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(Config.theSportsDBAPIKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "_"
        }
        return String(allowed)
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func namesMatch(_ a: String, _ b: String) -> Bool {
        let left = a.lowercased().replacingOccurrences(of: "fc", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.lowercased().replacingOccurrences(of: "fc", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return left.contains(right) || right.contains(left)
    }
}
