import Foundation

/// Injectable official-resource boundary; FPLAdvisorViewModel remains the only
/// owner of the visible snapshot, manager selection and request revisions.
protocol FPLAdvisorDataProviding: Sendable {
    func clearCache() async
    func fetchBootstrapResource(maximumAge: TimeInterval) async throws -> FPLResource<FPLBootstrapResponse>
    func fetchFixturesResource() async throws -> FPLResource<[FPLFixture]>
    func fetchManagerSummaryResource(id: Int) async throws -> FPLResource<FPLManagerSummary>
    func fetchManagerHistoryResource(id: Int) async throws -> FPLResource<FPLManagerHistoryResponse>
    func fetchPicksResource(managerId: Int, gameweek: Int) async throws -> FPLResource<FPLManagerPicks>
    func fetchEventLiveResource(gameweek: Int) async throws -> FPLResource<FPLEventLiveResponse>
    func fetchElementSummaryResource(playerId: Int, maximumAge: TimeInterval) async throws -> FPLResource<FPLElementSummaryResponse>
}

extension FPLAdvisorDataProviding {
    func fetchElementSummaryResource(playerId: Int, maximumAge: TimeInterval) async throws -> FPLResource<FPLElementSummaryResponse> {
        throw URLError(.resourceUnavailable)
    }
}

extension FPLService: FPLAdvisorDataProviding {}

enum FPLMatchdayRefreshPolicy {
    static let interval: TimeInterval = 60
    static let scoringKeys = ["bootstrap", "fixtures", "picks", "eventLive"]

    /// A fallback snapshot is useful offline, but it cannot authorize a newly
    /// calculated live total alongside independently refreshed resources.
    static func hasCurrentScoringResources(_ metadata: [String: FPLResourceMetadata], now: Date) -> Bool {
        scoringKeys.allSatisfy { key in
            guard let resource = metadata[key], resource.source != .diskSnapshot else { return false }
            let age = now.timeIntervalSince(resource.fetchedAt)
            return age >= -5 && age <= 90
        }
    }

    static func bootstrapMaximumAge(gameweek: FPLGameweek?, now: Date) -> TimeInterval {
        if let deadline = gameweek?.deadlineDate, deadline.timeIntervalSince(now) > 5 * 60 {
            return 300
        }
        return interval
    }

    static func canPublishRefresh(
        _ metadata: [String: FPLResourceMetadata], phase: FPLGameweekPhase, now: Date
    ) -> Bool {
        let limits: [String: TimeInterval] = [
            "bootstrap": phase == .planning ? 330 : 90,
            "fixtures": 90, "manager": 330, "history": 330
        ]
        guard limits.allSatisfy({ key, maximumAge in
            guard let resource = metadata[key], resource.source != .diskSnapshot else { return false }
            let age = now.timeIntervalSince(resource.fetchedAt)
            return age >= -5 && age <= maximumAge
        }) else { return false }
        return phase == .planning || hasCurrentScoringResources(metadata, now: now)
    }
}
