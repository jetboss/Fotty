import Foundation

/// One accepted own-team snapshot plus one rival's published picks. No second
/// live feed, draft squad, standings total or independent polling loop is used
/// as a substitute for scoring evidence.
struct FPLRivalSnapshotInput: Sendable {
    let managerID: Int
    let rivalID: Int
    let gameweek: FPLGameweek
    let ownPicks: FPLManagerPicks
    let bootstrap: FPLBootstrapResponse
    let live: FPLEventLiveResponse
    let fixtures: [FPLFixture]
    let metadata: [String: FPLResourceMetadata]
}

public struct FPLRivalScoringSnapshot: Sendable {
    let own: FPLLiveSquadSummary
    let rival: FPLLiveSquadSummary
    /// Oldest contributing scoring resource, not response completion time.
    let checkedAt: Date

    enum Failure: Error { case mismatchedIdentity, staleEvidence, incompleteScoring }

    static func make(input: FPLRivalSnapshotInput, rival: FPLResource<FPLManagerPicks>,
                     now: Date) throws -> Self {
        let gameweek = input.gameweek.id
        guard input.managerID > 0, input.rivalID > 0, input.managerID != input.rivalID,
              input.ownPicks.entryHistory?.event == gameweek,
              rival.value.entryHistory?.event == gameweek,
              input.metadata["picks"]?.endpoint == "entry/\(input.managerID)/event/\(gameweek)/picks/",
              input.metadata["eventLive"]?.endpoint == "event/\(gameweek)/live/",
              rival.metadata.endpoint == "entry/\(input.rivalID)/event/\(gameweek)/picks/" else {
            throw Failure.mismatchedIdentity
        }
        let age = now.timeIntervalSince(rival.metadata.fetchedAt)
        guard FPLMatchdayRefreshPolicy.hasCurrentScoringResources(input.metadata, now: now),
              rival.metadata.source != .diskSnapshot, age >= -5, age <= 90 else { throw Failure.staleEvidence }
        let ownSummary = FPLDecisionEngine.liveSquadSummary(gameweek: input.gameweek, picks: input.ownPicks,
            live: input.live, players: input.bootstrap.elements, teams: input.bootstrap.teams, fixtures: input.fixtures)
        let rivalSummary = FPLDecisionEngine.liveSquadSummary(gameweek: input.gameweek, picks: rival.value,
            live: input.live, players: input.bootstrap.elements, teams: input.bootstrap.teams, fixtures: input.fixtures)
        guard ownSummary.hasCompleteScoringData, rivalSummary.hasCompleteScoringData,
              ownSummary.totalPoints != nil, rivalSummary.totalPoints != nil else { throw Failure.incompleteScoring }
        let timestamps = FPLMatchdayRefreshPolicy.scoringKeys.compactMap { input.metadata[$0]?.fetchedAt }
            + [rival.metadata.fetchedAt]
        return .init(own: ownSummary, rival: rivalSummary, checkedAt: timestamps.min() ?? now)
    }
}
