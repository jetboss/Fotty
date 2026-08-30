import Foundation

// MARK: - Football Provider Protocol
// Any external API (API-Football, Sportmonks, etc.) must implement this protocol
// to be usable by the Fotty Repository.

public protocol FootballProvider {
    var name: String { get }
    
    // Core Fetching Methods
    func fetchFixtures(date: Date) async throws -> [FottyFixture]
    func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData
    func fetchLiveScores() async throws -> [MatchHubData]
    func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData]
    func fetchStandings(competitionId: String) async throws -> [FottyCompetition] // Placeholder for structured standings
    func fetchTeamForm(teamId: String) async throws -> [String]
    
    // Status & Health
    func checkHealth() async -> Bool
}

public enum FootballProviderError: Error, LocalizedError {
    case rateLimited
    case serverError(Int)
    case malformedData
    case staleData
    case invalidFixtureId(String)
    case unauthorized
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .rateLimited: return "API rate limit reached. Retrying shortly..."
        case .serverError(let code): return "Provider server error (Code: \(code))."
        case .malformedData: return "Received invalid data from provider."
        case .staleData: return "The provider snapshot is too old for live scores."
        case .invalidFixtureId(let id): return "Fixture ID \(id) not found by provider."
        case .unauthorized: return "API key invalid or expired."
        case .unknown: return "An unknown error occurred in the data provider."
        }
    }
}
