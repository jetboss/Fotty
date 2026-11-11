import XCTest
@testable import Fotty

@MainActor
final class FPLPlanningBoundariesTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z")!

    private func events(start: Date? = nil) throws -> [FPLGameweek] {
        try (1...38).map { id in
            let deadline = (start ?? now).addingTimeInterval(Double(id) * 7 * 86_400)
            return try decode(FPLGameweek.self, [
                "id": id, "name": "Gameweek \(id)", "deadline_time": ISO8601DateFormatter().string(from: deadline),
                "deadline_time_epoch": Int(deadline.timeIntervalSince1970), "finished": false,
                "is_previous": false, "is_current": id == 3, "is_next": id == 4
            ])
        }
    }

    private func chip(_ name: String = "wildcard", start: Int = 2, stop: Int = 19) throws -> FPLChipDefinition {
        try decode(FPLChipDefinition.self, ["id": start, "name": name, "number": 1,
            "start_event": start, "stop_event": stop, "chip_type": "transfer"])
    }

    func testChipStatusUsesSelectedTargetAndSeparateOfficialAllocations() throws {
        let weeks = try events()
        let first = try chip()
        let second = try chip(start: 20, stop: 38)
        let used = [FPLChipUsage(name: "wildcard", time: nil, event: 8)]
        XCTAssertEqual(status(first, target: 8, weeks: weeks, usages: used), .used)
        XCTAssertEqual(status(second, target: 19, weeks: weeks, usages: used), .upcoming)
        XCTAssertEqual(status(second, target: 20, weeks: weeks, usages: used), .eligible)
        XCTAssertEqual(status(first, target: 20, weeks: weeks), .expired)
        XCTAssertEqual(status(first, target: 1, weeks: weeks), .upcoming)
    }

    func testChipDeadlineBoundaryNeverClaimsAvailableAfterLock() throws {
        let weeks = try events()
        let definition = try chip()
        let deadline = try XCTUnwrap(weeks.first { $0.id == 19 }?.deadlineDate)
        XCTAssertEqual(status(definition, target: 19, weeks: weeks, at: deadline.addingTimeInterval(-1)), .eligible)
        XCTAssertEqual(status(definition, target: 19, weeks: weeks, at: deadline), .deadlinePassed)
        XCTAssertEqual(status(definition, target: 19, weeks: weeks, at: deadline.addingTimeInterval(1)), .deadlinePassed)
    }

    func testOpeningManagerGameweekAndConsecutiveFreeHitAreNotEligible() throws {
        let weeks = try events()
        let freeHit = try chip("free_hit", start: 20, stop: 38)
        XCTAssertEqual(status(try chip(), target: 6, weeks: weeks, started: 6), .blocked)
        XCTAssertEqual(status(freeHit, target: 20, weeks: weeks,
            usages: [.init(name: "freehit", time: nil, event: 19)]), .blocked)
        XCTAssertEqual(status(freeHit, target: 21, weeks: weeks,
            usages: [.init(name: "freehit", time: nil, event: 19)]), .eligible)
        XCTAssertEqual(status(try chip("bboost", start: 1), target: 6, weeks: weeks, started: 6), .eligible)
    }

    func testAnotherChipInTargetWeekBlocksButPrivateFactsRemainUnknown() throws {
        let weeks = try events()
        let bench = try chip("bboost", start: 1)
        XCTAssertEqual(status(bench, target: 5, weeks: weeks,
            usages: [.init(name: "3xc", time: nil, event: 5)]), .blocked)
        XCTAssertEqual(status(bench, target: 5, weeks: weeks, usages: nil), .unknown)
        XCTAssertEqual(status(try chip(), target: 5, weeks: weeks, started: nil), .unknown)
        let eligible = FPLChipAvailabilityPolicy.availability(chip: bench, targetGameweek: 5,
            events: weeks, usages: [], managerStartedEvent: 1, now: now)
        XCTAssertTrue(eligible.explanation.contains("pending chip choices"))
        XCTAssertNotEqual(eligible.status.rawValue, "AVAILABLE")
    }

    func testUnknownChipStaleSeasonAndMissingCalendarNeverLookEligible() throws {
        XCTAssertEqual(status(try chip("newchip"), target: 5, weeks: try events()), .unknown)
        XCTAssertEqual(status(try chip(), target: 5, weeks: []), .unknown)
        let old = try events(start: ISO8601DateFormatter().date(from: "2025-09-01T12:00:00Z")!)
        XCTAssertEqual(status(try chip(), target: 5, weeks: old), .unknown)
        XCTAssertEqual(status(try chip(), target: 39, weeks: try events()), .unknown)
    }

    func testPlanningCalendarStopsAtSeasonEndWithoutInventingWeeks() throws {
        let weeks = try events()
        XCTAssertEqual(FPLPlanningBounds.gameweeks(start: 37, horizon: 8, events: weeks), [37, 38])
        XCTAssertTrue(FPLPlanningBounds.gameweeks(start: 39, horizon: 8, events: weeks).isEmpty)
        XCTAssertTrue(FPLPlanningBounds.gameweeks(start: 4, horizon: 5, events: []).isEmpty)
        XCTAssertEqual(FPLPlanningBounds.gameweeks(start: 4, horizon: 5, events: weeks.filter { $0.id != 5 }), [4])
        XCTAssertTrue(FPLPlanningBounds.gameweeks(start: 0, horizon: 5, events: weeks).isEmpty)
        XCTAssertNil(FPLPlanningBounds.targetGameweek(explicit: 39, planningGameweek: 4, events: weeks))
        XCTAssertEqual(FPLPlanningBounds.targetGameweek(explicit: nil, planningGameweek: 4, events: weeks), 4)
        XCTAssertEqual(FPLPlanningBounds.targetGameweek(explicit: 7, planningGameweek: 4, events: weeks), 7)
    }

    func testPlannerRollAndOptimizerRespectEndOfSeasonBounds() throws {
        let weeks = try events()
        let routes = FPLPlannerEngine.routes(recommendations: [], fixtures: [], startGameweek: 37,
            horizon: 8, freeTransfers: nil, gameweek: nil, events: weeks)
        XCTAssertEqual(routes.first?.weeklyProjectedGain.keys.sorted(), [37, 38])
        XCTAssertTrue(FPLPlannerEngine.routes(recommendations: [], fixtures: [], startGameweek: 39,
            horizon: 5, freeTransfers: nil, gameweek: nil, events: weeks).isEmpty)
        XCTAssertTrue(FPLSquadOptimizer.generate(scores: [], fixtures: [], elementTypes: [], settings: nil,
            startGameweek: 39, horizon: 5, budget: 1000, events: weeks).isEmpty)
    }

    func testWildcardBudgetUsesPublishedValuesWithoutAnInitialBudgetFloor() throws {
        let picks = (1...15).map { FPLPick(element: $0, position: $0, multiplier: 1,
            isCaptain: $0 == 1, isViceCaptain: $0 == 2, sellingPrice: 50) }
        func resolve(bank: Int) -> FPLWildcardBudget {
            FPLWildcardBudget.resolve(publishedPicks: .init(activeChip: nil,
                entryHistory: history(bank: bank), picks: picks), publishedGameweek: 3, managerSummary: nil,
                players: [], savedDraftBudgetLimit: 1300, draftBudgetLimit: 1400, settings: nil)
        }
        XCTAssertEqual(resolve(bank: 20).amount, 770)
        XCTAssertEqual(resolve(bank: 0).amount, 750)
        XCTAssertFalse(resolve(bank: 20).explanation.contains("initial-squad"))
    }

    func testUnknownOrMismatchedBankUsesLabeledLocalBudgetNotOtherWeek() throws {
        let summary = try decode(FPLManagerSummary.self, ["id": 42, "name": "Squad",
            "player_first_name": "Test", "player_last_name": "Manager", "current_event": 2, "last_deadline_bank": 500])
        let picks = FPLManagerPicks(activeChip: nil, entryHistory: nil,
            picks: [.init(element: 1, position: 1, multiplier: 1, isCaptain: true, isViceCaptain: false, sellingPrice: 50)])
        let budget = FPLWildcardBudget.resolve(publishedPicks: picks, publishedGameweek: 3,
            managerSummary: summary, players: [], savedDraftBudgetLimit: 900, draftBudgetLimit: 1100, settings: nil)
        XCTAssertEqual(budget.amount, 900)
        XCTAssertTrue(budget.explanation.contains("not verified"))
        let initial = FPLWildcardBudget.resolve(publishedPicks: nil, publishedGameweek: nil,
            managerSummary: nil, players: [], savedDraftBudgetLimit: nil, draftBudgetLimit: nil, settings: nil)
        XCTAssertEqual(initial.amount, 1000)
        XCTAssertTrue(initial.explanation.contains("not a verified manager balance"))
    }

    func testSameCountOptimizerPublicationReplacesUnconstrainedLocalOutput() {
        let old = squads(firstID: 1, points: 40)
        let fresh = squads(firstID: 2, points: 55)
        XCTAssertEqual(old.count, fresh.count)
        XCTAssertNotEqual(FPLWildcardResultIdentity.signature(old), FPLWildcardResultIdentity.signature(fresh))
        var working = FPLWildcardWorkingResult()
        working.acceptGenerated(old)
        working.sourceChanged(hasConstraints: false)
        XCTAssertEqual(working.displayedSquads(published: fresh).first?.picks.first?.element, 2)
        XCTAssertEqual(working.displayedSquads(published: fresh).first?.projectedPoints, 55)
        XCTAssertFalse(working.needsRefresh)
    }

    func testConstrainedResultRemainsVisibleButStaleUntilRegenerated() {
        let old = squads(firstID: 1, points: 40)
        let fresh = squads(firstID: 2, points: 55)
        var working = FPLWildcardWorkingResult()
        working.acceptGenerated(old)
        working.sourceChanged(hasConstraints: true)
        XCTAssertEqual(working.displayedSquads(published: fresh).first?.picks.first?.element, 1)
        XCTAssertTrue(working.needsRefresh)
        working.acceptGenerated(fresh)
        XCTAssertFalse(working.needsRefresh)
        XCTAssertEqual(working.displayedSquads(published: old).first?.picks.first?.element, 2)
    }

    func testJournalIntendedWeekPersistsAndIsolatesManagerAndSeason() throws {
        let suite = "FPLPlanningBoundariesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let intended = entry(gameweek: 7)
        XCTAssertEqual(FPLDecisionJournalStore.upsert(intended, managerID: 42, season: "2026-27", defaults: defaults).first?.gameweek, 7)
        XCTAssertEqual(FPLDecisionJournalStore.load(managerID: 42, season: "2026-27", defaults: defaults).first?.gameweek, 7)
        XCTAssertTrue(FPLDecisionJournalStore.load(managerID: 43, season: "2026-27", defaults: defaults).isEmpty)
        XCTAssertTrue(FPLDecisionJournalStore.load(managerID: 42, season: "2027-28", defaults: defaults).isEmpty)
        XCTAssertEqual(FPLDecisionJournalStore.upsert(entry(gameweek: 39), managerID: 42, season: "2026-27", defaults: defaults), [intended])
    }

    func testJournalEncodingFailurePreservesExistingDataAndDoesNotClaimSave() throws {
        let suite = "FPLPlanningBoundariesTests.Failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = entry(gameweek: 4)
        FPLDecisionJournalStore.upsert(existing, managerID: 42, season: "2026-27", defaults: defaults)
        var invalid = entry(gameweek: 5)
        invalid.updatedAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertEqual(FPLDecisionJournalStore.upsert(invalid, managerID: 42, season: "2026-27", defaults: defaults), [existing])
        XCTAssertEqual(FPLDecisionJournalStore.load(managerID: 42, season: "2026-27", defaults: defaults), [existing])
    }

    private func status(_ chip: FPLChipDefinition, target: Int, weeks: [FPLGameweek],
                        usages: [FPLChipUsage]? = [], started: Int? = 1, at date: Date? = nil) -> FPLChipAvailabilityPolicy.Status {
        FPLChipAvailabilityPolicy.availability(chip: chip, targetGameweek: target, events: weeks,
            usages: usages, managerStartedEvent: started, now: date ?? now).status
    }

    private func history(bank: Int) -> FPLGameweekHistory {
        .init(event: 3, points: 0, totalPoints: 0, rank: nil, overallRank: nil, bank: bank,
              value: 750, eventTransfers: 0, eventTransfersCost: 0, pointsOnBench: 0)
    }

    private func squads(firstID: Int, points: Double) -> [FPLOptimizedSquad] {
        FPLOptimizedSquad.Profile.allCases.map { profile in
            .init(profile: profile, picks: [.init(element: firstID, position: 1, multiplier: 2,
                isCaptain: true, isViceCaptain: false)], projectedPoints: points, cost: 900,
                validation: .init(issues: [], totalCost: 900, budgetLimit: 1000, formation: "3-4-3"), explanation: "Test model")
        }
    }

    private func entry(gameweek: Int) -> FPLDecisionJournalEntry {
        .init(managerID: 42, gameweek: gameweek, kind: .transfer, title: "Future plan", rationale: "Fixture swing",
              expectedOutcome: "Modeled gain", source: "Test", createdAt: now, updatedAt: now)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
}
