import Foundation

struct MatchHubSnapshot {
    let match: MatchHubData
    let insights: MatchInsightsData
    static let routeKickoffTolerance: TimeInterval = 15 * 60

    /// Preserve a checked schedule route when enrichment uses another provider
    /// ID. Team identity, a bounded kickoff and compatible competition evidence
    /// are required; a shared UTC day or cache alias alone cannot admit a match.
    static func preservingRoute(_ match: MatchHubData, expected: MatchHubData?, routeID: String) -> MatchHubData {
        guard !match.identity.resolves(routeID), let expected,
              expected.identity.resolves(routeID), expected.identity.matchKey == match.identity.matchKey,
              abs(expected.fixture.utcDate.timeIntervalSince(match.fixture.utcDate)) <= routeKickoffTolerance,
              compatibleCompetition(expected.fixture.competition, match.fixture.competition) else { return match }
        let old = match.fixture
        let fixture = FottyFixture(id: expected.fixture.id, utcDate: old.utcDate, status: old.status,
            competition: old.competition, venue: old.venue, matchday: old.matchday,
            apiFootballFixtureId: old.apiFootballFixtureId ?? old.id, roundLabel: old.roundLabel,
            lastUpdated: old.lastUpdated, elapsedMinutes: old.elapsedMinutes, extraMinutes: old.extraMinutes)
        return MatchHubData(fixture: fixture, homeTeam: match.homeTeam, awayTeam: match.awayTeam,
            score: match.score, events: match.events, homeLineup: match.homeLineup, awayLineup: match.awayLineup,
            statistics: match.statistics, teamNews: match.teamNews, lastUpdated: match.lastUpdated, dataQuality: match.dataQuality)
    }

    private static func compatibleCompetition(_ expected: FottyCompetition, _ received: FottyCompetition) -> Bool {
        func normalized(_ value: String?) -> String {
            (value ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        func competitionName(_ value: String) -> String {
            switch normalized(value) {
            case "english premier league", "england premier league": return "premier league"
            case "uefa champions league": return "champions league"
            default: return normalized(value)
            }
        }
        let expectedCountry = normalized(expected.country), receivedCountry = normalized(received.country)
        guard expectedCountry.isEmpty || receivedCountry.isEmpty || expectedCountry == receivedCountry else { return false }
        let expectedName = competitionName(expected.name), receivedName = competitionName(received.name)
        return !expectedName.isEmpty && expectedName == receivedName
    }
}

protocol MatchHubDataLoading {
    func matchHubSnapshot(fixtureId: String, policy: MatchHubRefreshPolicy) async throws -> MatchHubSnapshot
}

extension FootballRepository: MatchHubDataLoading {}
