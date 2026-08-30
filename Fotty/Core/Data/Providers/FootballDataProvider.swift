import Foundation

/// football-data.org v4 — supplemental fixtures via `GET /matches` and competition feeds.
public final class FootballDataProvider: FootballProvider {
    public let name = "football-data.org"

    public init() {}

    /// One football-data.org call for a date window (schedules; free tier may be delayed vs live).
    public func fetchSchedule(in range: ClosedRange<Date>) async throws -> [MatchHubData] {
        let matches = try await FootballService.shared.fetchGlobalMatches(
            from: range.lowerBound,
            to: range.upperBound
        )
        return matches.compactMap(mapMatchHubData)
    }

    public func fetchFixtures(date: Date) async throws -> [FottyFixture] {
        let calendar = Calendar(identifier: .gregorian)
        let from = calendar.startOfDay(for: date)
        let to = calendar.date(byAdding: .day, value: 1, to: from) ?? from
        let matches = try await FootballService.shared.fetchGlobalMatches(from: from, to: to)
        return matches.compactMap(mapFixture)
    }

    public func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData {
        throw FootballProviderError.invalidFixtureId(fixtureId)
    }

    public func fetchLiveScores() async throws -> [MatchHubData] {
        let matches = try await FootballService.shared.fetchMatches(
            leagues: FootballDataPolicy.footballDataLiveLeagues,
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            to: Date(),
            statuses: ["IN_PLAY", "PAUSED"]
        )
        return matches
            .filter { FootballDataPolicy.supportsLiveScores(competition: $0.competition) }
            .compactMap(mapMatchHubData)
    }

    public func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData] {
        guard let league = League(rawValue: leagueId) else { return [] }
        let matches = try await FootballService.shared.upcomingMatches(league: league, limit: 40)
        return matches.compactMap(mapMatchHubData)
    }

    public func fetchStandings(competitionId: String) async throws -> [FottyCompetition] { [] }

    public func fetchTeamForm(teamId: String) async throws -> [String] { [] }

    public func checkHealth() async -> Bool {
        do {
            _ = try await FootballService.shared.fetchGlobalMatches(
                from: Date(),
                to: Date(),
                statuses: ["SCHEDULED"],
                limit: 1
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Mapping

    private func mapFixture(_ match: FootballMatch) -> FottyFixture? {
        guard let date = match.matchDate else { return nil }
        let roundLabel = match.group.map { "Group \($0)" } ?? match.stage
        return FottyFixture(
            id: String(match.id),
            utcDate: date,
            status: mapStatus(match.status),
            competition: FottyCompetition(
                id: String(match.competition.id ?? 0),
                name: match.competition.audienceFacingName,
                country: match.competition.country,
                emblemURL: match.competition.emblemURL
            ),
            venue: nil,
            matchday: match.matchday,
            apiFootballFixtureId: match.apiFootballFixtureId.map(String.init),
            roundLabel: roundLabel
        )
    }

    private func mapMatchHubData(_ match: FootballMatch) -> MatchHubData? {
        guard let fixture = mapFixture(match) else { return nil }
        let home = FottyTeam(
            id: String(match.homeTeam.id ?? 0),
            name: match.homeTeam.name ?? "Home",
            shortName: match.homeTeam.shortName,
            crestURL: match.homeTeam.crest.flatMap(URL.init(string:)),
            color: nil
        )
        let away = FottyTeam(
            id: String(match.awayTeam.id ?? 0),
            name: match.awayTeam.name ?? "Away",
            shortName: match.awayTeam.shortName,
            crestURL: match.awayTeam.crest.flatMap(URL.init(string:)),
            color: nil
        )
        let score = FottyScore(
            home: match.score.fullTime?.home ?? 0,
            away: match.score.fullTime?.away ?? 0,
            aggregateHome: nil,
            aggregateAway: nil,
            periodScores: [
                "HT": PeriodScore(home: match.score.halfTime?.home ?? 0, away: match.score.halfTime?.away ?? 0),
                "FT": PeriodScore(home: match.score.fullTime?.home ?? 0, away: match.score.fullTime?.away ?? 0)
            ]
        )
        let events = (match.events ?? []).map { event in
            FottyMatchEvent(
                id: String(event.id),
                type: mapEventType(event.type),
                minute: event.minute,
                extraMinute: event.extraMinute,
                teamId: String(event.teamId),
                player: event.player,
                assist: event.assist,
                detail: event.info
            )
        }
        return MatchHubData(
            fixture: fixture,
            homeTeam: home,
            awayTeam: away,
            score: score,
            events: events,
            homeLineup: nil,
            awayLineup: nil,
            statistics: [],
            teamNews: [],
            lastUpdated: Date(),
            dataQuality: .fallback
        )
    }

    private func mapStatus(_ status: FootballMatch.MatchStatus) -> FottyMatchStatus {
        switch status {
        case .scheduled, .timed: return .scheduled
        case .inPlay: return .live
        case .paused: return .halfTime
        case .finished, .awarded: return .fullTime
        case .postponed: return .postponed
        case .cancelled, .suspended: return .cancelled
        }
    }

    private func mapEventType(_ type: FootballMatchEvent.EventType) -> FottyEventType {
        switch type {
        case .goal: return .goal
        case .yellowCard: return .yellowCard
        case .redCard: return .redCard
        case .substitution: return .substitution
        case .varDecision: return .varDecision
        case .other: return .unknown
        }
    }
}

/// Premier League-only score adapter over the official public FPL JSON surface.
/// This is an unlicensed product dependency, not a commercial live-data feed;
/// callers must retain provenance/freshness labels and a separate fallback.
public final class OfficialFPLScoreProvider: FootballProvider {
    public let name = "Official FPL"

    private let service: FPLService
    private let fixtureFreshnessLimit: TimeInterval = 180
    private let bootstrapFreshnessLimit: TimeInterval = 7 * 24 * 60 * 60

    public init(service: FPLService = .shared) {
        self.service = service
    }

    public func fetchLiveScores() async throws -> [MatchHubData] {
        async let fixturesTask = service.fetchFixturesResource()
        async let bootstrapTask = service.fetchBootstrapResource()
        let (fixtures, bootstrap) = try await (fixturesTask, bootstrapTask)

        guard fixtures.metadata.age <= fixtureFreshnessLimit,
              fixtures.metadata.source != .diskSnapshot else {
            throw FootballProviderError.staleData
        }
        guard bootstrap.metadata.age <= bootstrapFreshnessLimit,
              !fixtures.value.isEmpty,
              !bootstrap.value.teams.isEmpty else {
            throw FootballProviderError.staleData
        }

        return Self.mapLiveFixtures(
            fixtures.value,
            teams: bootstrap.value.teams,
            fetchedAt: fixtures.metadata.fetchedAt
        )
    }

    static func mapLiveFixtures(
        _ fixtures: [FPLFixture],
        teams: [FPLTeam],
        fetchedAt: Date
    ) -> [MatchHubData] {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        return fixtures.compactMap { fixture in
            guard fixture.isActivelyPlaying,
                  let kickoff = fixture.kickoffDate,
                  let home = teamsByID[fixture.teamH],
                  let away = teamsByID[fixture.teamA] else {
                return nil
            }

            let matchFixture = FottyFixture(
                id: String(900_000_000 + fixture.id),
                utcDate: kickoff,
                status: .live,
                competition: FottyCompetition(
                    id: "39",
                    name: "Premier League",
                    country: "England",
                    emblemURL: nil
                ),
                venue: nil,
                matchday: fixture.event,
                roundLabel: fixture.event.map { "Gameweek \($0)" },
                lastUpdated: fetchedAt,
                elapsedMinutes: fixture.minutes,
                extraMinutes: nil
            )
            let score = FottyScore(
                home: fixture.teamHScore ?? 0,
                away: fixture.teamAScore ?? 0,
                aggregateHome: nil,
                aggregateAway: nil,
                periodScores: nil
            )

            return MatchHubData(
                fixture: matchFixture,
                homeTeam: FottyTeam(
                    id: String(home.id),
                    name: home.name,
                    shortName: home.shortName,
                    crestURL: nil,
                    color: nil
                ),
                awayTeam: FottyTeam(
                    id: String(away.id),
                    name: away.name,
                    shortName: away.shortName,
                    crestURL: nil,
                    color: nil
                ),
                score: score,
                events: [],
                homeLineup: nil,
                awayLineup: nil,
                statistics: [],
                teamNews: [],
                lastUpdated: fetchedAt,
                dataQuality: .official
            )
        }
    }

    public func fetchFixtures(date: Date) async throws -> [FottyFixture] {
        (try await fetchLiveScores()).map(\.fixture).filter {
            Calendar.current.isDate($0.utcDate, inSameDayAs: date)
        }
    }

    public func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData {
        if let fixture = (try await fetchLiveScores()).first(where: { $0.fixture.id == fixtureId }) {
            return fixture
        }
        throw FootballProviderError.invalidFixtureId(fixtureId)
    }

    public func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData] { [] }
    public func fetchStandings(competitionId: String) async throws -> [FottyCompetition] { [] }
    public func fetchTeamForm(teamId: String) async throws -> [String] { [] }

    public func checkHealth() async -> Bool {
        do {
            _ = try await service.fetchFixturesResource()
            return true
        } catch {
            return false
        }
    }
}
