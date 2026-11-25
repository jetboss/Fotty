import XCTest
@testable import Fotty

@MainActor
final class FPLRivalSnapshotTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_788_000_000)

    func testBothSidesShareAutosubsCaptainReplacementAndTransferHitsInsteadOfStandingsEventTotal() throws {
        let fixture = try RivalFixture(instant: instant, finished: true)
        let snapshot = try FPLRivalScoringSnapshot.make(input: fixture.input(at: instant),
            rival: fixture.rivalResource(at: instant), now: instant)
        XCTAssertTrue(snapshot.own.pointsAreProjected)
        XCTAssertTrue(snapshot.rival.pointsAreProjected)
        XCTAssertEqual(snapshot.own.projectedCaptainElementID, 14)
        XCTAssertTrue(snapshot.own.projectedAutomaticSubs.contains { $0.elementIn == 2 && $0.elementOut == 1 })
        XCTAssertEqual(snapshot.own.transferCost, 4)
        XCTAssertEqual(snapshot.rival.transferCost, 8)
        XCTAssertEqual(snapshot.own.totalPoints, 59)
        XCTAssertEqual(snapshot.rival.totalPoints, 60)
        let analysis = fixture.analysis(snapshot: snapshot)
        XCTAssertEqual(analysis.myGameweekPoints, 59)
        XCTAssertEqual(analysis.rivalGameweekPoints, 60)
        XCTAssertEqual(analysis.gameweekDeficit, 1)
        XCTAssertEqual(analysis.myCaptainName, "P14")
        XCTAssertEqual(analysis.rivalCaptainName, "P14")
        XCTAssertEqual(analysis.myCaptainMultiplier, 2)
        XCTAssertEqual(analysis.rivalCaptainMultiplier, 3)
        XCTAssertEqual(analysis.myPlayersRemaining, 0)
        XCTAssertFalse(analysis.isFinalComparison)
    }

    func testFinalityRequiresCheckedGameweekAndTimestampUsesOldestContributingEvidence() throws {
        let fixture = try RivalFixture(instant: instant, finished: true, checked: true)
        let input = fixture.input(at: instant.addingTimeInterval(-30))
        let snapshot = try FPLRivalScoringSnapshot.make(input: input,
            rival: fixture.rivalResource(at: instant), now: instant)
        XCTAssertEqual(snapshot.checkedAt, instant.addingTimeInterval(-30))
        XCTAssertTrue(fixture.analysis(snapshot: snapshot).isFinalComparison)
        XCTAssertFalse(snapshot.own.pointsAreProjected)
        XCTAssertEqual(snapshot.own.totalPoints, 59)
        XCTAssertEqual(snapshot.rival.totalPoints, 60)
        XCTAssertEqual(snapshot.own.officialCurrentPoints, 63, "Published GW points remain before hits")
        XCTAssertEqual(snapshot.rival.officialCurrentPoints, 68)
    }

    func testPublishedAndMissingPublishedPointsDeductHitsExactlyOnceIncludingNegativeNet() throws {
        let fixture = try RivalFixture(instant: instant)
        func summary(points: Int?, cost: Int) -> FPLLiveSquadSummary {
            let picks = FPLManagerPicks(activeChip: nil, entryHistory: .init(event: 1, points: points,
                totalPoints: nil, rank: nil, overallRank: nil, bank: 0, value: 1_000,
                eventTransfers: 3, eventTransfersCost: cost, pointsOnBench: 0), picks: fixture.own.picks)
            return FPLDecisionEngine.liveSquadSummary(gameweek: fixture.bootstrap.events[0], picks: picks,
                live: fixture.live, players: fixture.bootstrap.elements, teams: fixture.bootstrap.teams, fixtures: fixture.fixtures)
        }
        let published = summary(points: 50, cost: 4)
        XCTAssertFalse(published.pointsAreProjected)
        XCTAssertEqual(published.officialCurrentPoints, 50)
        XCTAssertEqual(published.officialPointsBeforeTransfers, 50)
        XCTAssertEqual(published.officialNetPoints, 46)
        XCTAssertEqual(published.totalPoints, 46)
        let missing = summary(points: nil, cost: 4)
        XCTAssertNil(missing.officialPointsBeforeTransfers)
        XCTAssertEqual(missing.projectionBaselineLabel, "DERIVED LINEUP NET")
        XCTAssertEqual(missing.totalPoints, missing.publishedLineupPoints, "Derived net fallback must not lose the hit twice")
        XCTAssertEqual(summary(points: 2, cost: 8).totalPoints, -6)
    }

    func testProjectionComparesNetWithNetAndKeepsDerivedFallbackExplicit() throws {
        let fixture = try RivalFixture(instant: instant, finished: true)
        func summary(raw: Int?) -> FPLLiveSquadSummary {
            let picks = FPLManagerPicks(activeChip: nil, entryHistory: .init(event: 1, points: raw,
                totalPoints: nil, rank: nil, overallRank: nil, bank: 0, value: 1_000,
                eventTransfers: 2, eventTransfersCost: 4, pointsOnBench: 0), picks: fixture.own.picks)
            return FPLDecisionEngine.liveSquadSummary(gameweek: fixture.bootstrap.events[0], picks: picks,
                live: fixture.live, players: fixture.bootstrap.elements, teams: fixture.bootstrap.teams, fixtures: fixture.fixtures)
        }
        let published = summary(raw: 50)
        XCTAssertEqual(published.officialPointsBeforeTransfers, 50)
        XCTAssertEqual(published.officialNetPoints, 46)
        XCTAssertEqual(published.totalPoints, 59)
        XCTAssertEqual(published.projectionPointChange, 13)
        XCTAssertEqual(published.projectionBaselineLabel, "PUBLISHED NET")
        let fallback = summary(raw: nil)
        XCTAssertNil(fallback.officialPointsBeforeTransfers)
        XCTAssertEqual(fallback.officialNetPoints, 41)
        XCTAssertEqual(fallback.totalPoints, 59)
        XCTAssertEqual(fallback.projectionPointChange, 18)
        XCTAssertEqual(fallback.projectionBaselineLabel, "DERIVED LINEUP NET")
        XCTAssertTrue(fallback.scoringBasisDescription.contains("Calculated"))
        XCTAssertEqual(summary(raw: 90).projectionPointChange, -27, "Negative changes must remain negative for the loss presentation")
    }

    func testIncompleteSummarySeparatesPublishedRawAndNetFromUnavailableEvidence() throws {
        let fixture = try RivalFixture(instant: instant, omitPlayer: 14)
        for raw in [Optional(50), nil] {
            let picks = FPLManagerPicks(activeChip: nil, entryHistory: .init(event: 1, points: raw,
                totalPoints: nil, rank: nil, overallRank: nil, bank: 0, value: 1_000,
                eventTransfers: 2, eventTransfersCost: 4, pointsOnBench: 0), picks: fixture.own.picks)
            let summary = FPLDecisionEngine.liveSquadSummary(gameweek: fixture.bootstrap.events[0], picks: picks,
                live: fixture.live, players: fixture.bootstrap.elements, teams: fixture.bootstrap.teams, fixtures: fixture.fixtures)
            XCTAssertFalse(summary.hasCompleteScoringData)
            XCTAssertNil(summary.publishedLineupPoints)
            XCTAssertNil(summary.projectionPointChange)
            XCTAssertEqual(summary.officialPointsBeforeTransfers, raw)
            XCTAssertEqual(summary.officialNetPoints, raw.map { $0 - 4 })
            XCTAssertEqual(summary.totalPoints, raw.map { $0 - 4 })
            XCTAssertTrue(summary.scoringBasisDescription.contains(raw == nil ? "No published GW total" : "published net contribution is 46"))
        }
    }

    func testDirectTotalQuestionsUseRulesButFutureAndHistoricalStrategiesDoNot() {
        for query in ["What are my total points?", "What is my total?", "Show my current points", "What's my live gameweek score?", "Check my points"] {
            XCTAssertTrue(FPLAICoachService.isScoringQuery(query), query)
        }
        for query in ["What is my projected total next week?", "Predict my gameweek points", "What are my expected points?", "Who should I captain?", "What were my points last gameweek?"] {
            XCTAssertFalse(FPLAICoachService.isScoringQuery(query), query)
        }
    }

    func testNativeCoachDistinguishesPublishedPointsFromFinalNetAndProvisionalHitCost() async throws {
        for checked in [false, true] {
            let fixture = try RivalFixture(instant: instant, finished: true, checked: checked)
            let scoring = FPLDecisionEngine.liveSquadSummary(gameweek: fixture.bootstrap.events[0], picks: fixture.own,
                live: fixture.live, players: fixture.bootstrap.elements, teams: fixture.bootstrap.teams, fixtures: fixture.fixtures)
            let answer = await FPLAICoachService.askCoach(userQuery: "What is my current total?",
                managerSummary: fixture.summary, currentGw: fixture.bootstrap.events[0], picks: fixture.own,
                scores: [], recs: [], captains: [], rivalGap: nil, live: scoring, players: fixture.bootstrap.elements)
            XCTAssertTrue(answer.contains(checked ? "63 points before transfers" : "50 points before transfers"))
            XCTAssertTrue(answer.contains(checked ? "59 net points" : "59 points"))
            XCTAssertTrue(answer.contains("4-point transfer cost"))
        }
        let missing = try RivalFixture(instant: instant, omitPlayer: 14)
        let scoring = FPLDecisionEngine.liveSquadSummary(gameweek: missing.bootstrap.events[0], picks: missing.own,
            live: missing.live, players: missing.bootstrap.elements, teams: missing.bootstrap.teams, fixtures: missing.fixtures)
        let answer = await FPLAICoachService.askCoach(userQuery: "What is my current total?",
            managerSummary: missing.summary, currentGw: missing.bootstrap.events[0], picks: missing.own,
            scores: [], recs: [], captains: [], rivalGap: nil, live: scoring, players: missing.bootstrap.elements)
        XCTAssertTrue(answer.contains("50 points before transfers"))
        XCTAssertTrue(answer.contains("incomplete"))
    }

    func testCoachUsesSummaryBoundRawBasisRatherThanUnrelatedPicksArgument() async throws {
        let fixture = try RivalFixture(instant: instant, finished: true)
        let scoring = FPLDecisionEngine.liveSquadSummary(gameweek: fixture.bootstrap.events[0], picks: fixture.own,
            live: fixture.live, players: fixture.bootstrap.elements, teams: fixture.bootstrap.teams, fixtures: fixture.fixtures)
        let unrelated = try RivalFixture(instant: instant, gameweek: 2, finished: true, checked: true)
        for passedPicks in [Optional(unrelated.own), nil] {
            let answer = await FPLAICoachService.askCoach(userQuery: "What are my total points?",
                managerSummary: fixture.summary, currentGw: fixture.bootstrap.events[0], picks: passedPicks,
                scores: [], recs: [], captains: [], rivalGap: nil, live: scoring, players: fixture.bootstrap.elements)
            XCTAssertTrue(answer.contains("50 points before transfers"))
            XCTAssertFalse(answer.contains("63 points before transfers"))
            XCTAssertTrue(answer.contains("59 points"))
        }
    }

    func testRejectsWrongManagerWrongGameweekDiskFallbackStaleAndMissingPlayerEvidence() throws {
        let fixture = try RivalFixture(instant: instant)
        let input = fixture.input(at: instant)
        let wrongManager = FPLResource(value: fixture.rival, metadata: FPLResourceMetadata(source: .network,
            fetchedAt: instant, endpoint: "entry/999/event/1/picks/"))
        XCTAssertThrowsError(try FPLRivalScoringSnapshot.make(input: input, rival: wrongManager, now: instant))
        let wrongGW = try RivalFixture(instant: instant, gameweek: 2)
        XCTAssertThrowsError(try FPLRivalScoringSnapshot.make(input: input, rival: wrongGW.rivalResource(at: instant), now: instant))
        XCTAssertThrowsError(try FPLRivalScoringSnapshot.make(input: input,
            rival: fixture.rivalResource(at: instant, source: .diskSnapshot), now: instant))
        XCTAssertThrowsError(try FPLRivalScoringSnapshot.make(input: input,
            rival: fixture.rivalResource(at: instant.addingTimeInterval(-91)), now: instant))
        XCTAssertThrowsError(try FPLRivalScoringSnapshot.make(input: fixture.input(at: instant.addingTimeInterval(-91)),
            rival: fixture.rivalResource(at: instant), now: instant))
        let missing = try RivalFixture(instant: instant, omitPlayer: 14)
        XCTAssertThrowsError(try FPLRivalScoringSnapshot.make(input: missing.input(at: instant),
            rival: missing.rivalResource(at: instant), now: instant))
    }

    func testOwnerKeepsLastCompleteComparisonOnFailureAndRefreshesOnlyTheSelectedRival() async throws {
        let (model, provider, fixture) = try await loadedModel()
        await model.inspectRival(entry: fixture.rivalEntry)
        let original = try XCTUnwrap(model.rivalGapAnalysis)
        XCTAssertEqual(model.rivalComparisonStatus, "PROVISIONAL")
        await assertRequests(provider, 1)
        await provider.setFailure(true)
        await model.refreshSelectedRivalAfterPrimarySnapshot()
        XCTAssertEqual(model.rivalGapAnalysis?.myGameweekPoints, original.myGameweekPoints)
        XCTAssertEqual(model.rivalGapAnalysis?.checkedAt, original.checkedAt)
        XCTAssertEqual(model.rivalComparisonStatus, "LAST COMPLETE")
        XCTAssertNotNil(model.rivalErrorMessage)
        XCTAssertFalse(model.isRivalLoading)
        await assertRequests(provider, 2)
        await provider.setFailure(false)
        await model.refreshSelectedRivalAfterPrimarySnapshot()
        XCTAssertNil(model.rivalErrorMessage)
        XCTAssertEqual(model.rivalComparisonStatus, "PROVISIONAL")
        await assertRequests(provider, 3)
    }

    func testOwnerRetainsVisibleComparisonWhileUpdatingAndRejectsCanceledLateCompletion() async throws {
        let (model, provider, fixture) = try await loadedModel()
        await model.inspectRival(entry: fixture.rivalEntry)
        let original = model.rivalGapAnalysis?.checkedAt
        await provider.holdNextRival()
        let pending = Task { await model.refreshSelectedRivalAfterPrimarySnapshot() }
        await provider.waitUntilHeld()
        XCTAssertTrue(model.isRivalLoading)
        XCTAssertNotNil(model.rivalGapAnalysis)
        model.cancelRivalRefresh(clearSelection: true)
        await provider.releaseRival()
        await pending.value
        XCTAssertNotNil(original)
        XCTAssertNil(model.rivalGapAnalysis)
        XCTAssertNil(model.selectedRivalID)
        XCTAssertFalse(model.isRivalLoading)
    }

    func testOlderRivalCannotOverwriteNewlySelectedRival() async throws {
        let (model, provider, fixture) = try await loadedModel()
        await provider.holdNextRival()
        let older = Task { await model.inspectRival(entry: fixture.rivalEntry) }
        await provider.waitUntilHeld()
        let newer = fixture.entry(id: 9_999_983, name: "New rival")
        await model.inspectRival(entry: newer)
        XCTAssertEqual(model.selectedRivalID, newer.entry)
        XCTAssertTrue(model.rivalGapAnalysis?.rivalName.contains("New rival") == true)
        await provider.releaseRival()
        await older.value
        XCTAssertEqual(model.selectedRivalID, newer.entry)
        XCTAssertTrue(model.rivalGapAnalysis?.rivalName.contains("New rival") == true)
    }

    func testCallerCancellationRejectsProviderWhichIgnoresCancellation() async throws {
        let (model, provider, fixture) = try await loadedModel()
        await provider.holdNextRival()
        let pending = Task { await model.inspectRival(entry: fixture.rivalEntry) }
        await provider.waitUntilHeld()
        pending.cancel()
        await provider.releaseRival()
        await pending.value
        XCTAssertNil(model.rivalGapAnalysis)
        XCTAssertFalse(model.isRivalLoading)
    }

    func testPlayerHistoryMetadataDoesNotInvalidateUnrelatedRivalRequest() async throws {
        let (model, provider, fixture) = try await loadedModel()
        await provider.holdNextRival()
        let pending = Task { await model.inspectRival(entry: fixture.rivalEntry) }
        await provider.waitUntilHeld()
        model.resourceMetadata["element-3"] = .init(source: .network, fetchedAt: instant, endpoint: "element-summary/3/")
        await provider.releaseRival()
        await pending.value
        XCTAssertNotNil(model.rivalGapAnalysis)
        XCTAssertNil(model.rivalErrorMessage)
    }

    func testLateComparisonIsRejectedAfterManagerGameweekOrPrimaryEvidenceChanges() async throws {
        for change in 0..<3 {
            let (model, provider, fixture) = try await loadedModel()
            await provider.holdNextRival()
            let pending = Task { await model.inspectRival(entry: fixture.rivalEntry) }
            await provider.waitUntilHeld()
            if change == 0 { model.managerId = 12345 }
            if change == 1 { model.currentGameweek = try RivalFixture(instant: instant, gameweek: 2).bootstrap.events[0] }
            if change == 2 {
                model.resourceMetadata["fixtures"] = FPLResourceMetadata(source: .network,
                    fetchedAt: instant.addingTimeInterval(1), endpoint: "fixtures/")
            }
            await provider.releaseRival()
            await pending.value
            XCTAssertNil(model.rivalGapAnalysis)
            XCTAssertFalse(model.isRivalLoading)
        }
    }

    func testSeasonBoundaryRejectsLateRivalEvenWhileScoringResourcesAreUnderNinetySecondsOld() async throws {
        let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-06-30T23:59:30Z"))
        let clock = RivalTestClock(before)
        let (model, provider, fixture) = try await loadedModel(at: before, clock: clock)
        XCTAssertEqual(FPLSeasonIdentifier.label(from: fixture.bootstrap.events), "2026-27")
        await provider.holdNextRival()
        let pending = Task { await model.inspectRival(entry: fixture.rivalEntry) }
        await provider.waitUntilHeld()
        clock.set(before.addingTimeInterval(61))
        XCTAssertEqual(FPLSeasonIdentifier.currentLabel(at: clock.now()), "2027-28")
        XCTAssertTrue(FPLMatchdayRefreshPolicy.hasCurrentScoringResources(model.resourceMetadata, now: clock.now()))
        await provider.releaseRival()
        await pending.value
        XCTAssertNil(model.rivalGapAnalysis)
        XCTAssertFalse(model.isRivalLoading)
    }

    func testPlanningAndStalePrimaryDataDoNotRequestRivalOrClaimLive() async throws {
        let (model, provider, fixture) = try await loadedModel()
        model.gameweekPhase = .planning
        await model.inspectRival(entry: fixture.rivalEntry)
        await assertRequests(provider, 0)
        model.gameweekPhase = .live
        model.resourceMetadata["fixtures"] = FPLResourceMetadata(source: .diskSnapshot,
            fetchedAt: instant, endpoint: "fixtures/")
        await model.inspectRival(entry: fixture.rivalEntry)
        await assertRequests(provider, 0)
        XCTAssertNil(model.rivalGapAnalysis)
        XCTAssertNotEqual(model.rivalComparisonStatus, "LIVE")
        XCTAssertNotNil(model.rivalErrorMessage)
    }

    private func assertRequests(_ provider: RivalProvider, _ expected: Int) async {
        let actual = await provider.rivalRequestCount()
        XCTAssertEqual(actual, expected)
    }

    private func loadedModel(at dateOverride: Date? = nil, clock: RivalTestClock? = nil) async throws -> (FPLAdvisorViewModel, RivalProvider, RivalFixture) {
        let date = dateOverride ?? instant
        let fixture = try RivalFixture(instant: date, finished: true)
        let provider = RivalProvider(fixture: fixture, instant: date)
        let suite = "FottyRivalSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let model = FPLAdvisorViewModel(draftDefaults: defaults, dataProvider: provider, now: { clock?.now() ?? date })
        model.managerId = fixture.managerID
        await model.loadData()
        model.selectedLeagueId = 1
        let league: FPLLeagueDetail = try RivalFixture.decode(["id": 1, "name": "Test league", "created": "2026-08-01"])
        model.leagueStandings = .init(league: league,
            standings: .init(results: [fixture.ownEntry, fixture.rivalEntry], hasNext: false, page: 1))
        return (model, provider, fixture)
    }
}

private final class RivalTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func set(_ date: Date) { lock.lock(); defer { lock.unlock() }; self.date = date }
}

private struct RivalFixture: Sendable {
    let managerID = 9_999_981
    let rivalID = 9_999_982
    let bootstrap: FPLBootstrapResponse
    let fixtures: [FPLFixture]
    let own: FPLManagerPicks
    let rival: FPLManagerPicks
    let live: FPLEventLiveResponse
    let summary: FPLManagerSummary
    let history: FPLManagerHistoryResponse
    var ownEntry: FPLLeagueStandingEntry { entry(id: managerID, name: "Own team") }
    var rivalEntry: FPLLeagueStandingEntry { entry(id: rivalID, name: "Rival team") }

    static func decode<T: Decodable>(_ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    init(instant: Date, gameweek: Int = 1, finished: Bool = false, checked: Bool = false, omitPlayer: Int? = nil) throws {
        let positions = [1, 1] + Array(repeating: 2, count: 5) + Array(repeating: 3, count: 5) + Array(repeating: 4, count: 3)
        let players: [[String: Any]] = positions.enumerated().map { index, position in
            ["id": index + 1, "web_name": "P\(index + 1)", "first_name": "Player", "second_name": "\(index + 1)",
             "team": index % 5 + 1, "team_code": index % 5 + 1, "element_type": position,
             "now_cost": 50, "cost_change_event": 0, "cost_change_event_fall": 0, "selected_by_percent": "10",
             "form": "4", "points_per_game": "4", "total_points": 10, "event_points": 0, "minutes": 180,
             "goals_scored": 0, "assists": 0, "clean_sheets": 0, "goals_conceded": 0, "yellow_cards": 0,
             "red_cards": 0, "saves": 0, "bonus": 0, "bps": 0, "influence": "0", "creativity": "0",
             "threat": "0", "ict_index": "0", "starts": 2, "transfers_in_event": 0, "transfers_out_event": 0,
             "status": "a", "news": "", "can_select": true]
        }
        let formatter = ISO8601DateFormatter()
        func event(_ id: Int, next: Bool = false) -> [String: Any] {
            let deadline = instant.addingTimeInterval(next ? 604_800 : -7_200)
            return ["id": id, "name": "Gameweek \(id)", "deadline_time": formatter.string(from: deadline),
                "deadline_time_epoch": Int(deadline.timeIntervalSince1970), "finished": !next && checked,
                "data_checked": !next && checked, "is_previous": false, "is_current": !next, "is_next": next]
        }
        bootstrap = try Self.decode(["events": [event(gameweek), event(gameweek + 1, next: true)],
            "elements": players, "teams": (1...5).map { ["id": $0, "code": $0, "name": "Team \($0)", "short_name": "T\($0)"] as [String: Any] },
            "element_types": [], "total_players": 15])
        fixtures = try Self.decode((1...5).map { team -> [String: Any] in
            ["id": team, "event": gameweek, "team_h": team, "team_a": team % 5 + 1,
             "finished": finished, "finished_provisional": finished, "started": true,
             "kickoff_time": formatter.string(from: instant.addingTimeInterval(-3_600)),
             "team_h_difficulty": 3, "team_a_difficulty": 3]
        })
        func picks(captain: Int, multiplier: Int, hit: Int, points: Int) -> FPLManagerPicks {
            let order = [1, 3, 4, 5, 8, 9, 10, 11, 13, 14, 15, 2, 6, 7, 12]
            return .init(activeChip: multiplier == 3 ? "3xc" : nil, entryHistory: .init(event: gameweek,
                points: points, totalPoints: 100, rank: 1, overallRank: 1, bank: 250, value: 1_000,
                eventTransfers: 3, eventTransfersCost: hit, pointsOnBench: 8),
                picks: order.enumerated().map { offset, id in
                    FPLPick(element: id, position: offset + 1, multiplier: id == captain ? multiplier : (offset < 11 ? 1 : 0),
                        isCaptain: id == captain, isViceCaptain: id == (captain == 13 ? 14 : 15), elementType: nil)
                })
        }
        own = picks(captain: 13, multiplier: 2, hit: 4, points: checked ? 63 : 50)
        rival = picks(captain: 14, multiplier: 3, hit: 8, points: checked ? 68 : 51)
        live = try Self.decode(["elements": (1...15).filter { $0 != omitPlayer }.map { id -> [String: Any] in
            let absent = id == 1 || id == 13
            return ["id": id, "stats": ["minutes": absent ? 0 : 90, "goals_scored": 0, "assists": 0,
                "clean_sheets": 0, "goals_conceded": 0, "yellow_cards": 0, "red_cards": 0, "saves": 0,
                "bonus": 0, "bps": 0, "total_points": absent ? 0 : (id == 2 ? 8 : 5), "played": !absent],
                "explain": [], "modified": false]
        }])
        summary = try Self.decode(["id": 9_999_981, "name": "Test manager", "player_first_name": "Test",
            "player_last_name": "Manager", "last_deadline_bank": 250, "summary_overall_points": 100,
            "summary_event_points": 50, "summary_overall_rank": 1])
        history = try Self.decode(["current": [], "past": [], "chips": []])
    }

    func entry(id: Int, name: String) -> FPLLeagueStandingEntry {
        .init(entry: id, entryName: name, playerName: name, rank: 1, lastRank: 1, total: 100, eventTotal: 999)
    }
    func input(at date: Date) -> FPLRivalSnapshotInput {
        let gw = bootstrap.events[0]
        let endpoints = ["bootstrap": "bootstrap-static/", "fixtures": "fixtures/",
            "picks": "entry/\(managerID)/event/\(gw.id)/picks/", "eventLive": "event/\(gw.id)/live/"]
        return .init(managerID: managerID, rivalID: rivalID, gameweek: gw, ownPicks: own,
            bootstrap: bootstrap, live: live, fixtures: fixtures,
            metadata: endpoints.mapValues { .init(source: .network, fetchedAt: date, endpoint: $0) })
    }
    func rivalResource(at date: Date, source: FPLDataSource = .network) -> FPLResource<FPLManagerPicks> {
        .init(value: rival, metadata: .init(source: source, fetchedAt: date,
            endpoint: "entry/\(rivalID)/event/\(bootstrap.events[0].id)/picks/"))
    }
    func analysis(snapshot: FPLRivalScoringSnapshot) -> RivalGapAnalysis {
        FPLAdvisorEngine.analyzeRivalGap(myEntry: ownEntry, rivalEntry: rivalEntry, myPicks: own.picks,
            rivalPicks: rival.picks, allScores: FPLAdvisorEngine.scoreAllPlayers(players: bootstrap.elements,
                teams: bootstrap.teams, fixtures: fixtures, events: bootstrap.events),
            gameweek: bootstrap.events[0].id, phase: .live, eventLive: live, fixtures: fixtures, scoringSnapshot: snapshot)
    }
}

/// Ignores cancellation on purpose: the real owner must reject late responses.
private actor RivalProvider: FPLAdvisorDataProviding {
    private let fixture: RivalFixture
    private let instant: Date
    private var failure = false
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var requests = 0
    init(fixture: RivalFixture, instant: Date) { self.fixture = fixture; self.instant = instant }
    func setFailure(_ fail: Bool) { failure = fail }
    func rivalRequestCount() -> Int { requests }
    func holdNextRival() { holdNext = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func releaseRival() { held?.resume(); held = nil }
    func clearCache() {}
    private func resource<T: Sendable>(_ value: T, _ endpoint: String) -> FPLResource<T> {
        .init(value: value, metadata: .init(source: .network, fetchedAt: instant, endpoint: endpoint))
    }
    func fetchBootstrapResource(maximumAge: TimeInterval) -> FPLResource<FPLBootstrapResponse> { resource(fixture.bootstrap, "bootstrap-static/") }
    func fetchFixturesResource() -> FPLResource<[FPLFixture]> { resource(fixture.fixtures, "fixtures/") }
    func fetchManagerSummaryResource(id: Int) -> FPLResource<FPLManagerSummary> { resource(fixture.summary, "entry/\(id)/") }
    func fetchManagerHistoryResource(id: Int) -> FPLResource<FPLManagerHistoryResponse> { resource(fixture.history, "entry/\(id)/history/") }
    func fetchEventLiveResource(gameweek: Int) -> FPLResource<FPLEventLiveResponse> { resource(fixture.live, "event/\(gameweek)/live/") }
    func fetchPicksResource(managerId: Int, gameweek: Int) async throws -> FPLResource<FPLManagerPicks> {
        if managerId == fixture.managerID { return resource(fixture.own, "entry/\(managerId)/event/\(gameweek)/picks/") }
        requests += 1
        let shouldFail = failure
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0; waiting?.resume(); waiting = nil }
        }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return resource(fixture.rival, "entry/\(managerId)/event/\(gameweek)/picks/")
    }
}
