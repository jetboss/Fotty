import XCTest
@testable import Fotty

@MainActor
final class MatchHubRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_600_000)

    private final class Loader: MatchHubDataLoading {
        var requests = 0
        var operation: () async throws -> MatchHubSnapshot
        init(_ operation: @escaping () async throws -> MatchHubSnapshot) { self.operation = operation }
        func matchHubSnapshot(fixtureId: String, policy: MatchHubRefreshPolicy) async throws -> MatchHubSnapshot {
            requests += 1
            return try await operation()
        }
    }

    private func snapshot(goals: Int, at date: Date? = nil, id: String = "test-match",
                          kickoff: Date? = nil, competition: FottyCompetition? = nil) -> MatchHubSnapshot {
        let time = date ?? now
        let fixture = FottyFixture(id: id, utcDate: kickoff ?? now.addingTimeInterval(-1800), status: .live,
            competition: competition ?? .init(id: "39", name: "Premier League", country: "England", emblemURL: nil), venue: nil, matchday: nil)
        let data = MatchHubData(fixture: fixture,
            homeTeam: .init(id: "a", name: "Arsenal", shortName: nil, crestURL: nil, color: nil),
            awayTeam: .init(id: "b", name: "Chelsea", shortName: nil, crestURL: nil, color: nil),
            score: .init(home: goals, away: 0, aggregateHome: nil, aggregateAway: nil, periodScores: nil),
            events: [], homeLineup: nil, awayLineup: nil, statistics: [], teamNews: [], lastUpdated: time, dataQuality: .official)
        let insight = MatchInsightsData(fixtureId: fixture.id, homeForm: [], awayForm: [], headToHead: nil,
            keyInsights: ["Goals: \(goals)"], momentum: [], winProbability: nil, lastUpdated: time)
        return MatchHubSnapshot(match: data, insights: insight)
    }

    func testWholeRefreshPublishesScoreAndInsightsFromSamePacket() async {
        var next = snapshot(goals: 0)
        let loader = Loader { next }
        let model = MatchHubViewModel(fixtureId: "test-match", repository: loader, lookupCatalog: { _ in nil },
                                     now: { self.now }, startsAutomatically: false)
        await model.refresh()
        next = snapshot(goals: 2, at: now.addingTimeInterval(1))
        await model.refresh()
        XCTAssertEqual(loader.requests, 2)
        XCTAssertEqual(model.hubData?.score.home, 2)
        XCTAssertEqual(model.insights?.keyInsights, ["Goals: 2"])
        XCTAssertEqual(model.hubData?.lastUpdated, model.insights?.lastUpdated)
        XCTAssertFalse(model.isRefreshing)
    }

    func testFailedRefreshKeepsCompletePacketAndExplainsFailure() async {
        let initial = snapshot(goals: 1)
        let loader = Loader { initial }
        let model = MatchHubViewModel(fixtureId: "test-match", repository: loader, lookupCatalog: { _ in nil },
                                     now: { self.now }, startsAutomatically: false)
        await model.refresh()
        loader.operation = { throw URLError(.notConnectedToInternet) }
        await model.refresh()
        XCTAssertEqual(model.hubData?.score.home, 1)
        XCTAssertEqual(model.insights?.keyInsights, ["Goals: 1"])
        XCTAssertNotNil(model.refreshNotice)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderSnapshotCannotRewindScoreOrInsights() async {
        var next = snapshot(goals: 2)
        let loader = Loader { next }
        let model = MatchHubViewModel(fixtureId: "test-match", repository: loader, lookupCatalog: { _ in nil },
                                     now: { self.now }, startsAutomatically: false)
        await model.refresh()
        next = snapshot(goals: 0, at: now.addingTimeInterval(-90))
        await model.refresh()
        XCTAssertEqual(model.hubData?.score.home, 2)
        XCTAssertEqual(model.insights?.keyInsights, ["Goals: 2"])
        XCTAssertNotNil(model.refreshNotice)
    }

    func testPauseInvalidatesLatePublicationEvenWhenLoaderIgnoresCancellation() async {
        let began = expectation(description: "request")
        var continuation: CheckedContinuation<MatchHubSnapshot, Error>?
        let loader = Loader {
            try await withCheckedThrowingContinuation { continuation = $0; began.fulfill() }
        }
        let model = MatchHubViewModel(fixtureId: "test-match", repository: loader, lookupCatalog: { _ in nil },
                                     now: { self.now }, startsAutomatically: false)
        let task = Task { await model.refresh() }
        await fulfillment(of: [began], timeout: 2)
        model.pauseDataRefresh()
        continuation?.resume(returning: snapshot(goals: 3))
        await task.value
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isRefreshing)
    }

    func testMismatchedInsightTimestampIsNotPublished() async {
        let match = snapshot(goals: 1)
        let old = snapshot(goals: 0, at: now.addingTimeInterval(-60))
        let loader = Loader { MatchHubSnapshot(match: match.match, insights: old.insights) }
        let model = MatchHubViewModel(fixtureId: "test-match", repository: loader, lookupCatalog: { _ in nil },
                                     now: { self.now }, startsAutomatically: false)
        await model.refresh()
        XCTAssertNil(model.snapshot)
        XCTAssertNotNil(model.errorMessage)
    }

    func testCheckedScheduleRouteSurvivesProviderEnrichmentID() {
        let scheduled = snapshot(goals: 0).match
        let api = snapshot(goals: 2, id: "12345").match
        let merged = MatchHubSnapshot.preservingRoute(api, expected: scheduled, routeID: "test-match")
        XCTAssertEqual(merged.fixture.id, "test-match")
        XCTAssertEqual(merged.fixture.apiFootballFixtureId, "12345")
        XCTAssertEqual(merged.score.home, 2)
        XCTAssertTrue(merged.identity.resolves("test-match"))
        XCTAssertTrue(merged.identity.resolves("12345"))
        XCTAssertEqual(MatchHubSnapshot.preservingRoute(api, expected: nil, routeID: "test-match").fixture.id, "12345")
    }

    func testRoutePreservationRejectsSameDayDifferentKickoffOrCompetition() {
        let scheduled = snapshot(goals: 0).match
        let later = snapshot(goals: 2, id: "12345", kickoff: scheduled.fixture.utcDate.addingTimeInterval(3600)).match
        XCTAssertEqual(later.identity.matchKey, scheduled.identity.matchKey, "A day key alone cannot authorize another kickoff")
        let wrongCompetition = snapshot(goals: 2, id: "12345",
            competition: .init(id: "45", name: "FA Cup", country: "England", emblemURL: nil)).match
        let wrongCountry = snapshot(goals: 2, id: "12345",
            competition: .init(id: "180", name: "Premier League", country: "Scotland", emblemURL: nil)).match
        for received in [later, wrongCompetition, wrongCountry] {
            let result = MatchHubSnapshot.preservingRoute(received, expected: scheduled, routeID: "test-match")
            XCTAssertEqual(result.fixture.id, "12345")
            XCTAssertFalse(result.identity.resolves("test-match"))
        }
    }

    func testRoutePreservationHasBoundedKickoffToleranceAndKnownCompetitionAliases() {
        let scheduled = snapshot(goals: 0).match
        for (offset, expectedID) in [(900.0, "test-match"), (901, "12345")] {
            let received = snapshot(goals: 2, id: "12345", kickoff: scheduled.fixture.utcDate.addingTimeInterval(offset),
                competition: .init(id: "2021", name: "English Premier League", country: "England", emblemURL: nil)).match
            XCTAssertEqual(MatchHubSnapshot.preservingRoute(received, expected: scheduled, routeID: "test-match").fixture.id, expectedID)
        }
    }

    func testLateNilFallbackCannotOverwriteNewSuccessfulOwner() async {
        let began = expectation(description: "fallback")
        var continuation: CheckedContinuation<EventReference?, Never>?
        var lookups = 0
        let loader = Loader { throw URLError(.badServerResponse) }
        let model = MatchHubViewModel(fixtureId: "test-match", repository: loader, lookupCatalog: { _ in
            lookups += 1
            if lookups > 1 { return nil }
            return await withCheckedContinuation { continuation = $0; began.fulfill() }
        }, now: { self.now }, startsAutomatically: false)
        let old = Task { await model.refresh() }
        await fulfillment(of: [began], timeout: 2)
        let ready = snapshot(goals: 2)
        loader.operation = { ready }
        await model.refresh()
        continuation?.resume(returning: nil)
        await old.value
        XCTAssertEqual(model.hubData?.score.home, 2)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isRefreshing)
    }

}
