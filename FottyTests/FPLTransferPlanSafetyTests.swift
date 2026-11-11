import XCTest
@testable import Fotty

final class FPLTransferPlanSafetyTests: XCTestCase {
    @MainActor
    func testStagingAndUndoSurviveRecreatedWorkspace() throws {
        let defaults = isolatedDefaults()
        let baseline = baseline()
        let store = FPLTransferStagingStore(defaults: defaults)
        var state = store.load(managerID: 42, season: "2026-27", baseline: baseline)
        state.stage(replacing(3, with: 16, in: state.picks))
        store.save(state)

        let recreated = FPLTransferStagingStore(defaults: defaults)
        var restored = recreated.load(managerID: 42, season: "2026-27", baseline: baseline)
        XCTAssertEqual(restored.picks, state.picks)
        XCTAssertTrue(restored.hasChanges)
        XCTAssertTrue(restored.canUndo)
        restored.undo()
        XCTAssertEqual(restored.picks, baseline.picks)
        XCTAssertFalse(restored.hasChanges)
    }

    func testUnchangedRefreshAndLiveMultipliersDoNotEraseStaging() {
        let baseline = baseline()
        var state = FPLTransferStagingState(managerID: 42, season: "2026-27", baseline: baseline)
        state.stage(replacing(3, with: 16, in: state.picks))
        let staged = state.picks
        let livePicks = baseline.picks.map {
            FPLPick(element: $0.element, position: $0.position, multiplier: 0,
                    isCaptain: $0.isCaptain, isViceCaptain: $0.isViceCaptain)
        }
        let liveBaseline = FPLTransferStagingBaseline(picks: livePicks, publishedPicks: livePicks,
                                                     publishedGameweek: 1, targetGameweek: 2, budgetLimit: 760)
        state.synchronize(with: liveBaseline)
        XCTAssertEqual(state.picks, staged)
        XCTAssertFalse(state.hasConflict)
    }

    func testNewPublishedSquadRequiresChoiceAndResetCanBeUndone() {
        var state = FPLTransferStagingState(managerID: 42, season: "2026-27", baseline: baseline())
        state.stage(replacing(3, with: 16, in: state.picks))
        let unfinished = state.picks
        let latest = baseline(picks: replacing(4, with: 17, in: validPicks()), week: 2)
        state.synchronize(with: latest)
        XCTAssertEqual(state.picks, unfinished)
        XCTAssertTrue(state.hasConflict)

        state.reset()
        XCTAssertEqual(state.picks, latest.picks)
        XCTAssertFalse(state.hasConflict)
        state.undo()
        XCTAssertEqual(state.picks, unfinished)
        XCTAssertTrue(state.hasConflict)
        state.keepStagedPlan()
        XCTAssertEqual(state.picks, unfinished)
        XCTAssertFalse(state.hasConflict)
        XCTAssertEqual(state.baseline, latest)
    }

    func testCleanStagingFollowsNewSourceAndDeadlineChangesConflictWithDirtyPlan() {
        var state = FPLTransferStagingState(managerID: 42, season: "2026-27", baseline: baseline())
        let latest = baseline(week: 2)
        state.synchronize(with: latest)
        XCTAssertFalse(state.hasChanges)
        XCTAssertFalse(state.hasConflict)
        XCTAssertEqual(state.baseline, latest)
        state.stage(replacing(3, with: 16, in: state.picks))
        state.synchronize(with: baseline(week: 3))
        XCTAssertTrue(state.hasChanges)
        XCTAssertTrue(state.hasConflict)
    }

    @MainActor
    func testStorageDoesNotRestoreAnotherManagerOrSeasonEvenWithMiskeyedData() throws {
        let defaults = isolatedDefaults()
        let store = FPLTransferStagingStore(defaults: defaults)
        var state = store.load(managerID: 42, season: "2026-27", baseline: baseline())
        state.stage(replacing(3, with: 16, in: state.picks))
        store.save(state)
        XCTAssertFalse(store.load(managerID: 43, season: "2026-27", baseline: baseline()).hasChanges)
        XCTAssertFalse(store.load(managerID: 42, season: "2027-28", baseline: baseline()).hasChanges)
        defaults.set(try JSONEncoder().encode(state), forKey: FPLTransferStagingStore.key(managerID: 43, season: "2026-27"))
        XCTAssertFalse(store.load(managerID: 43, season: "2026-27", baseline: baseline()).hasChanges)
        XCTAssertEqual(store.load(managerID: 42, season: "2026-27", baseline: baseline()).picks, state.picks)
    }

    func testUndoIsBoundedAndResetRestoresBaseline() {
        var state = FPLTransferStagingState(managerID: 42, season: "2026-27", baseline: baseline())
        for id in 16...35 {
            state.stage(replacing(state.picks[1].element, with: id, in: state.picks))
        }
        XCTAssertEqual(state.history.count, 10)
        let edited = state.picks
        state.reset()
        XCTAssertFalse(state.hasChanges)
        state.undo()
        XCTAssertEqual(state.picks, edited)
    }

    func testIndividuallyAffordableMovesCannotOverspendAsPair() throws {
        let fixture = try fixture(firstCost: 60, secondCost: 60)
        let context = context(fixture, bank: 10)
        let first = try recommendation(3, to: 16, fixture: fixture)
        let second = try recommendation(4, to: 17, fixture: fixture)
        XCTAssertNotNil(context.validatedPicks(for: [first]))
        XCTAssertNotNil(context.validatedPicks(for: [second]))
        XCTAssertNil(context.validatedPicks(for: [first, second]))
        XCTAssertFalse(routes([first, second], context: context).contains { $0.transfers.count == 2 })
    }

    func testCombinedClubQuotaIsCheckedAndLaterLegalPairIsRetained() throws {
        let fixture = try fixture(firstTeam: 6, secondTeam: 6)
        let context = context(fixture, bank: 10)
        let first = try recommendation(3, to: 16, fixture: fixture)
        let second = try recommendation(4, to: 17, fixture: fixture)
        let alternate = try recommendation(4, to: 18, fixture: fixture)
        XCTAssertNotNil(context.validatedPicks(for: [first]))
        XCTAssertNotNil(context.validatedPicks(for: [second]))
        XCTAssertNil(context.validatedPicks(for: [first, second]))
        let pair = try XCTUnwrap(routes([first, second, alternate], context: context).first { $0.transfers.count == 2 })
        XCTAssertEqual(pair.transfers.map(\.id), [first.id, alternate.id])
        XCTAssertNotNil(context.validatedPicks(for: pair.transfers))
    }

    func testBudgetSearchSkipsInvalidPairAndUsesAvailableSellingPrice() throws {
        let fixture = try fixture(firstCost: 60, secondCost: 60)
        let first = try recommendation(3, to: 16, fixture: fixture)
        let second = try recommendation(4, to: 17, fixture: fixture)
        let alternate = try recommendation(4, to: 18, fixture: fixture)
        let ordinary = context(fixture, bank: 10)
        let pair = try XCTUnwrap(routes([first, second, alternate], context: ordinary).first { $0.transfers.count == 2 })
        XCTAssertEqual(pair.transfers.map(\.id), [first.id, alternate.id])
        let picksWithSellingPrice = validPicks().map { pick in
            FPLPick(element: pick.element, position: pick.position, multiplier: pick.multiplier,
                    isCaptain: pick.isCaptain, isViceCaptain: pick.isViceCaptain,
                    sellingPrice: pick.element == 3 ? 40 : nil)
        }
        let lowerSale = context(fixture, bank: 10, picks: picksWithSellingPrice)
        XCTAssertNil(lowerSale.validatedPicks(for: [first]))
    }

    func testPositionAndExistingPlayerConflictsAreRejectedBeforeStaging() throws {
        let fixture = try fixture()
        let context = context(fixture, bank: 100)
        XCTAssertNil(context.validatedPicks(for: [try recommendation(1, to: 16, fixture: fixture)]))
        XCTAssertNil(context.validatedPicks(for: [try recommendation(3, to: 4, fixture: fixture)]))
        let first = try recommendation(3, to: 16, fixture: fixture)
        XCTAssertNil(context.validatedPicks(for: [first, first]))
    }

    func testUnknownBudgetSuppressesRoutesAndUnknownFreeTransfersAreExplicit() throws {
        let fixture = try fixture()
        let move = try recommendation(3, to: 16, fixture: fixture)
        XCTAssertEqual(routes([move], context: context(fixture, bank: nil)).map(\.name), ["Roll"])
        let route = try XCTUnwrap(routes([move], context: context(fixture, bank: 10)).first { !$0.transfers.isEmpty })
        XCTAssertEqual(route.hitCost, 4)
        XCTAssertTrue(route.verificationItems.contains { $0.contains("Free transfers are unknown") })
        XCTAssertTrue(route.verificationItems.contains { $0.contains("current player prices") })
    }

    @MainActor
    func testFinalSaveRejectsChangedBudgetAndStillValidatesAfterKeep() throws {
        let model = try model(bank: 20, firstCost: 60, secondCost: 60)
        let initial = try XCTUnwrap(model.transferStagingBaseline)
        var state = FPLTransferStagingState(managerID: 42, season: FPLSeasonIdentifier.currentLabel(), baseline: initial)
        state.stage(replacing(4, with: 17, in: replacing(3, with: 16, in: state.picks)))
        model.applyPublishedSquad(published(bank: 0, week: 2), gameweek: 2)
        XCTAssertFalse(model.saveTransferStaging(state), "An unacknowledged budget change cannot be saved.")
        XCTAssertNil(model.savedSquadDraft)

        state.synchronize(with: try XCTUnwrap(model.transferStagingBaseline))
        XCTAssertTrue(state.hasConflict)
        state.keepStagedPlan()
        XCTAssertFalse(model.saveTransferStaging(state), "Keeping a plan does not bypass the shared budget validator.")
        XCTAssertNil(model.savedSquadDraft)
        XCTAssertTrue(model.draftErrorMessage?.contains("exceeding") == true)

        state.reset()
        state.stage(replacing(3, with: 18, in: state.picks))
        XCTAssertTrue(model.saveTransferStaging(state))
        XCTAssertEqual(model.savedSquadDraft?.budgetLimit, 750)
        XCTAssertEqual(model.savedSquadDraft?.basedOnGameweek, 2)
    }

    @MainActor
    func testAcknowledgedNewBudgetCanSaveAValidRouteAndCannotBoostItArbitrarily() throws {
        let model = try model(bank: 0, firstCost: 60)
        let initial = try XCTUnwrap(model.transferStagingBaseline)
        var state = FPLTransferStagingState(managerID: 42, season: FPLSeasonIdentifier.currentLabel(), baseline: initial)
        state.stage(replacing(3, with: 16, in: state.picks))
        model.applyPublishedSquad(published(bank: 10, week: 2), gameweek: 2)
        XCTAssertFalse(model.saveTransferStaging(state))
        state.synchronize(with: try XCTUnwrap(model.transferStagingBaseline))
        state.keepStagedPlan()
        XCTAssertTrue(model.saveTransferStaging(state))
        XCTAssertEqual(model.savedSquadDraft?.budgetLimit, 760)

        let latest = try XCTUnwrap(model.transferStagingBaseline)
        let boosted = FPLTransferStagingBaseline(picks: latest.picks, publishedPicks: latest.publishedPicks,
                                                 publishedGameweek: latest.publishedGameweek,
                                                 targetGameweek: latest.targetGameweek, budgetLimit: 10_000)
        let invalid = FPLTransferStagingState(managerID: 42, season: FPLSeasonIdentifier.currentLabel(), baseline: boosted)
        XCTAssertFalse(model.saveTransferStaging(invalid))
        XCTAssertEqual(model.savedSquadDraft?.budgetLimit, 760)
    }

    @MainActor
    func testFinalSaveRejectsAnotherManagerOrSeason() throws {
        let model = try model(bank: 10)
        let baseline = try XCTUnwrap(model.transferStagingBaseline)
        let otherManager = FPLTransferStagingState(managerID: 43, season: FPLSeasonIdentifier.currentLabel(), baseline: baseline)
        let otherSeason = FPLTransferStagingState(managerID: 42, season: "2000-01", baseline: baseline)
        XCTAssertFalse(model.saveTransferStaging(otherManager))
        XCTAssertFalse(model.saveTransferStaging(otherSeason))
        XCTAssertNil(model.savedSquadDraft)
    }

    @MainActor
    private func model(bank: Int, firstCost: Int = 50, secondCost: Int = 50) throws -> FPLAdvisorViewModel {
        let model = FPLAdvisorViewModel(draftDefaults: isolatedDefaults())
        model.managerId = 42
        model.bootstrap = try fixture(firstCost: firstCost, secondCost: secondCost)
        model.managerSummary = try JSONDecoder().decode(FPLManagerSummary.self, from: JSONSerialization.data(withJSONObject: [
            "id": 42, "player_first_name": "Test", "player_last_name": "Manager", "name": "Test Squad", "current_event": 1
        ]))
        model.applyPublishedSquad(published(bank: bank, week: 1), gameweek: 1)
        return model
    }

    private func published(bank: Int, week: Int) -> FPLManagerPicks {
        FPLManagerPicks(activeChip: nil, entryHistory: FPLGameweekHistory(
            event: week, points: 0, totalPoints: 0, rank: nil, overallRank: nil,
            bank: bank, value: 750, eventTransfers: 0, eventTransfersCost: 0, pointsOnBench: 0), picks: validPicks())
    }

    private func routes(_ recommendations: [TransferRecommendation], context: FPLTransferPlanContext) -> [FPLDraftRoute] {
        FPLPlannerEngine.routes(recommendations: recommendations, fixtures: [], startGameweek: 2,
                                horizon: 3, freeTransfers: nil, gameweek: nil, context: context)
    }

    private func context(_ fixture: FPLBootstrapResponse, bank: Int?, picks: [FPLPick]? = nil) -> FPLTransferPlanContext {
        let picks = picks ?? validPicks()
        return FPLTransferPlanContext(picks: picks, players: fixture.elements, elementTypes: [], gameSettings: nil,
                                      budgetLimit: FPLTransferPlanContext.budgetLimit(picks: picks, players: fixture.elements, bank: bank))
    }

    private func recommendation(_ outgoing: Int, to incoming: Int, fixture: FPLBootstrapResponse) throws -> TransferRecommendation {
        let scores = FPLAdvisorEngine.scoreAllPlayers(players: fixture.elements, teams: fixture.teams, fixtures: [], events: [])
        let old = try XCTUnwrap(scores.first { $0.id == outgoing })
        let new = try XCTUnwrap(scores.first { $0.id == incoming })
        return TransferRecommendation(playerOut: old, playerIn: new, scoreUplift: 2, costDelta: old.player.nowCost - new.player.nowCost, reason: "Test route")
    }

    private func baseline(picks: [FPLPick]? = nil, week: Int = 1) -> FPLTransferStagingBaseline {
        let picks = picks ?? validPicks()
        return FPLTransferStagingBaseline(picks: picks, publishedPicks: picks, publishedGameweek: week,
                                          targetGameweek: week + 1, budgetLimit: 760)
    }

    private func replacing(_ outgoing: Int, with incoming: Int, in picks: [FPLPick]) -> [FPLPick] {
        picks.map { pick in
            guard pick.element == outgoing else { return pick }
            return FPLPick(element: incoming, position: pick.position, multiplier: pick.multiplier,
                           isCaptain: pick.isCaptain, isViceCaptain: pick.isViceCaptain)
        }
    }

    private func validPicks() -> [FPLPick] {
        [1, 3, 4, 5, 8, 9, 10, 11, 13, 14, 15, 2, 6, 7, 12].enumerated().map { index, id in
            FPLPick(element: id, position: index + 1, multiplier: index > 10 ? 0 : (id == 13 ? 2 : 1),
                    isCaptain: id == 13, isViceCaptain: id == 14)
        }
    }

    private func fixture(firstCost: Int = 50, secondCost: Int = 50, firstTeam: Int = 7, secondTeam: Int = 8) throws -> FPLBootstrapResponse {
        let positions = [1, 1] + Array(repeating: 2, count: 5) + Array(repeating: 3, count: 5) + Array(repeating: 4, count: 3) + [2, 2, 2]
        var players = [[String: Any]]()
        for (offset, position) in positions.enumerated() {
            let id = offset + 1
            let player: [String: Any] = [
                "id": id, "web_name": "Player \(id)", "first_name": "Player", "second_name": "\(id)",
                "team": id == 16 ? firstTeam : (id == 17 ? secondTeam : (id == 18 ? 9 : offset % 6 + 1)),
                "team_code": offset % 6 + 1, "element_type": position, "now_cost": id == 16 ? firstCost : (id == 17 ? secondCost : 50),
                "cost_change_event": 0, "cost_change_event_fall": 0, "selected_by_percent": "10",
                "form": "4", "points_per_game": "4", "total_points": 10, "event_points": 0,
                "minutes": 180, "goals_scored": 0, "assists": 0, "clean_sheets": 0, "goals_conceded": 0,
                "yellow_cards": 0, "red_cards": 0, "saves": 0, "bonus": 0, "bps": 0,
                "influence": "0", "creativity": "0", "threat": "0", "ict_index": "0", "starts": 2,
                "transfers_in_event": 0, "transfers_out_event": 0, "status": "a", "news": "", "can_select": true
            ]
            players.append(player)
        }
        let teams: [[String: Any]] = (1...9).map { ["id": $0, "name": "Team \($0)", "short_name": "T\($0)", "code": $0] }
        return try JSONDecoder().decode(FPLBootstrapResponse.self, from: JSONSerialization.data(withJSONObject: [
            "events": (1...2).map { week -> [String: Any] in
                let deadline = "\(FPLSeasonIdentifier.currentLabel().prefix(4))-08-\(week == 1 ? "21" : "28")T17:30:00Z"
                return ["id": week, "name": "Gameweek \(week)",
                 "deadline_time": deadline,
                 "deadline_time_epoch": Int(ISO8601DateFormatter().date(from: deadline)!.timeIntervalSince1970),
                 "finished": false, "data_checked": false, "is_previous": false,
                 "is_current": week == 1, "is_next": week == 2]
            }, "elements": players, "teams": teams, "element_types": [], "total_players": 18
        ]))
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "FPLTransferPlanSafetyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
