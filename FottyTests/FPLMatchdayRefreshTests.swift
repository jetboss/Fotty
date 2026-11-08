import XCTest
@testable import Fotty

@MainActor
final class FPLMatchdayRefreshTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_788_000_000)

    func testVisibleSnapshotMovesThroughFullTimeAutosubsAndCheckedFinalResult() async throws {
        let initial = try sample()
        let provider = ControlledFPLProvider(snapshot: initial, fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        XCTAssertEqual(model.gameweekPhase, .live)
        XCTAssertGreaterThan(try XCTUnwrap(model.liveSquadSummary).playersRemaining, 0)
        XCTAssertTrue(try XCTUnwrap(model.liveSquadSummary).projectedAutomaticSubs.isEmpty)

        let fullTime = try sample(fixturesFinished: true)
        await provider.replace(fullTime, fetchedAt: instant.addingTimeInterval(1))
        await model.refreshMatchdayData()
        let provisional = try XCTUnwrap(model.liveSquadSummary)
        XCTAssertEqual(provisional.playersRemaining, 0)
        XCTAssertEqual(provisional.projectedAutomaticSubs.count, 1)
        XCTAssertEqual(provisional.projectedAutomaticSubs.first?.elementIn, 2)
        XCTAssertFalse(provisional.isFinal)
        XCTAssertEqual(model.fixtures.first?.finished, true)

        let checked = try sample(fixturesFinished: true, checked: true)
        await provider.replace(checked, fetchedAt: instant.addingTimeInterval(2))
        await model.refreshMatchdayData()
        XCTAssertEqual(model.currentGameweek?.id, 1, "A visible final result must not jump to next week's empty plan")
        XCTAssertEqual(model.gameweekPhase, .review)
        XCTAssertTrue(try XCTUnwrap(model.liveSquadSummary).isFinal)
        XCTAssertEqual(model.liveSquadSummary?.totalPoints, 64)
        XCTAssertEqual(model.liveSquadSummary?.playersRemaining, 0)
        XCTAssertEqual(model.resourceMetadata["bootstrap"]?.fetchedAt, instant.addingTimeInterval(2))
    }

    func testPlanningPollCrossesDeadlineAndOfficialGameweekWithoutNavigation() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(planning: true), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        XCTAssertEqual(model.gameweekPhase, .planning)
        XCTAssertNil(model.eventLive)

        await provider.replace(try sample(gameweek: 2), fetchedAt: instant.addingTimeInterval(1))
        await model.refreshMatchdayData()
        XCTAssertEqual(model.gameweekPhase, .live)
        XCTAssertEqual(model.currentGameweek?.id, 2)
        XCTAssertEqual(model.picksGameweek, 2)
        XCTAssertEqual(model.officialPicks?.entryHistory?.event, 2)
        XCTAssertEqual(model.liveSquadSummary?.gameweek, 2)
        XCTAssertTrue(model.fixtures.allSatisfy { $0.event == 2 })
        XCTAssertEqual(model.resourceMetadata["eventLive"]?.endpoint, "event/2/live/")
    }

    func testStaggeredDoubleGameweekWaitsForSecondFixtureBeforeAutosubAndRetainsLabeledProjectionOnFailure() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()

        // Team 1's first fixture has finished, but its second fixture (ID 5)
        // is tomorrow. A current zero-minute goalkeeper is not a non-appearance.
        let betweenFixtures = try sample(fixturesFinished: true, unfinishedFixtureIDs: [5])
        await provider.replace(betweenFixtures, fetchedAt: instant)
        await model.refreshMatchdayData()
        XCTAssertEqual(model.fixtures.first { $0.id == 1 }?.finished, true)
        XCTAssertEqual(model.fixtures.first { $0.id == 5 }?.finished, false)
        XCTAssertGreaterThan(try XCTUnwrap(model.fixtures.first { $0.id == 5 }?.kickoffDate), instant)
        XCTAssertGreaterThan(try XCTUnwrap(model.liveSquadSummary).playersRemaining, 0)
        XCTAssertTrue(try XCTUnwrap(model.liveSquadSummary).projectedAutomaticSubs.isEmpty)

        await provider.replace(try sample(fixturesFinished: true), fetchedAt: instant)
        await model.refreshMatchdayData()
        let completed = try XCTUnwrap(model.liveSquadSummary)
        XCTAssertEqual(completed.playersRemaining, 0)
        XCTAssertEqual(completed.projectedAutomaticSubs.first?.elementIn, 2)
        XCTAssertTrue(completed.pointsAreProjected)
        XCTAssertFalse(model.scoringSnapshotNeedsRefresh)

        await provider.setDiskFixtureFallback(true)
        await model.refreshMatchdayData()
        let retained = try XCTUnwrap(model.liveSquadSummary)
        XCTAssertEqual(retained.totalPoints, completed.totalPoints)
        XCTAssertEqual(retained.projectedAutomaticSubs, completed.projectedAutomaticSubs)
        XCTAssertTrue(retained.pointsAreProjected)
        XCTAssertEqual(FPLLiveTrackerView(viewModel: model).scoreTitle(retained), "LAST COMPLETE UPDATE")
        XCTAssertEqual(model.scoringSnapshotAgeDescription, "just now")

        await provider.setDiskFixtureFallback(false)
        await model.refreshMatchdayData()
        XCTAssertFalse(model.scoringSnapshotNeedsRefresh)
        XCTAssertEqual(FPLLiveTrackerView(viewModel: model).scoreTitle(try XCTUnwrap(model.liveSquadSummary)), "PROVISIONAL FPL TOTAL")
    }

    func testRefreshKeepsLocalDraftSeparateFromNewPublishedLineup() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        let draft = model.picks?.picks

        await provider.replace(try sample(gameweek: 2), fetchedAt: instant.addingTimeInterval(1))
        await model.refreshMatchdayData()
        XCTAssertTrue(model.isCustomDraft)
        XCTAssertEqual(model.picks?.picks, draft)
        XCTAssertEqual(model.officialPicks?.entryHistory?.event, 2)
        XCTAssertFalse(try XCTUnwrap(model.officialPicks).picks.contains { $0.element == 16 })
        XCTAssertFalse(try XCTUnwrap(model.liveSquadSummary).rows.contains { $0.player.id == 16 })
    }

    func testDiskFixtureFallbackDoesNotPublishFreshPointsOrTimestampOverOldContext() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        let oldMetadata = model.resourceMetadata
        let oldPoints = model.liveSquadSummary?.totalPoints
        await provider.replace(try sample(fixturesFinished: true), fetchedAt: instant)
        await provider.setDiskFixtureFallback(true)
        await model.refreshMatchdayData()

        XCTAssertEqual(model.fixtures.first?.finished, false)
        XCTAssertEqual(model.liveSquadSummary?.totalPoints, oldPoints)
        XCTAssertEqual(model.resourceMetadata, oldMetadata)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.scoringSnapshotNeedsRefresh)
        XCTAssertEqual(FPLLiveTrackerView(viewModel: model).scoreTitle(try XCTUnwrap(model.liveSquadSummary)), "LAST COMPLETE UPDATE")
        XCTAssertEqual(model.scoringSnapshotAgeDescription, "just now")
    }

    func testInitialDiskContextNeverAuthorizesNewLiveProjection() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(fixturesFinished: true), fetchedAt: instant)
        await provider.setDiskFixtureFallback(true)
        let model = model(provider)
        await model.loadData()
        XCTAssertNotNil(model.officialPicks)
        XCTAssertEqual(model.resourceMetadata["fixtures"]?.source, .diskSnapshot)
        XCTAssertNil(model.eventLive)
        XCTAssertNil(model.liveSquadSummary)
    }

    func testOverlappingFullLoadWinsOverDelayedOldMatchdayRefresh() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        await provider.holdNextBootstrap()
        let oldRefresh = Task { await model.refreshMatchdayData() }
        await provider.waitUntilHeld()
        await provider.replace(try sample(gameweek: 2), fetchedAt: instant.addingTimeInterval(2))
        await model.loadData()
        XCTAssertEqual(model.currentGameweek?.id, 2)
        await provider.releaseBootstrap()
        await oldRefresh.value
        XCTAssertEqual(model.currentGameweek?.id, 2)
        XCTAssertEqual(model.picksGameweek, 2)
        XCTAssertTrue(model.fixtures.allSatisfy { $0.event == 2 })
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isRefreshing)
    }

    func testManagerClearInvalidatesRefreshEvenWhenTransportIgnoresCancellation() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        await provider.holdNextBootstrap()
        let refresh = Task { await model.refreshMatchdayData() }
        await provider.waitUntilHeld()
        model.clearManagerId()
        await provider.releaseBootstrap()
        await refresh.value
        XCTAssertNil(model.managerId)
        XCTAssertNil(model.bootstrap)
        XCTAssertNil(model.eventLive)
        XCTAssertTrue(model.fixtures.isEmpty)
        XCTAssertTrue(model.resourceMetadata.isEmpty)
        XCTAssertFalse(model.isRefreshing)
    }

    func testCancelledRefreshCannotPublishAndConcurrentTickIsSingleFlight() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        await provider.replace(try sample(fixturesFinished: true), fetchedAt: instant.addingTimeInterval(2))
        await provider.holdNextBootstrap()
        let refresh = Task { await model.refreshMatchdayData() }
        await provider.waitUntilHeld()
        let callsBefore = await provider.bootstrapCalls
        await model.refreshMatchdayData()
        let callsAfter = await provider.bootstrapCalls
        XCTAssertEqual(callsBefore, callsAfter)
        refresh.cancel()
        await provider.releaseBootstrap()
        await refresh.value
        XCTAssertEqual(model.fixtures.first?.finished, false)
        XCTAssertEqual(model.resourceMetadata["bootstrap"]?.fetchedAt, instant)
        XCTAssertFalse(model.isRefreshing)
    }

    func testFreshnessUsesOldestOfAllFourScoringInputsAndBoundsBootstrapAge() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        model.resourceMetadata["fixtures"] = FPLResourceMetadata(source: .memoryCache, fetchedAt: instant.addingTimeInterval(-50), endpoint: "fixtures/")
        XCTAssertEqual(model.scoringFreshness?.endpoint, "fixtures/")
        let metadata = model.resourceMetadata
        XCTAssertTrue(FPLMatchdayRefreshPolicy.hasCurrentScoringResources(metadata, now: instant))
        XCTAssertFalse(FPLMatchdayRefreshPolicy.hasCurrentScoringResources(metadata, now: instant.addingTimeInterval(41)))
        model.resourceMetadata["fixtures"] = FPLResourceMetadata(source: .memoryCache, fetchedAt: instant.addingTimeInterval(-121), endpoint: "fixtures/")
        XCTAssertTrue(model.scoringSnapshotNeedsRefresh)
        XCTAssertEqual(model.scoringSnapshotAgeDescription, "2m ago")
        XCTAssertEqual(FPLMatchdayRefreshPolicy.bootstrapMaximumAge(gameweek: model.currentGameweek, now: instant), 60)
        let future = try sample(planning: true).bootstrap.events[0]
        XCTAssertEqual(FPLMatchdayRefreshPolicy.bootstrapMaximumAge(gameweek: future, now: instant), 300)
    }

    func testPlayerHistoryTTLRefreshPreservesSelectionAndOldEvidenceOnFailure() async throws {
        let fixture = try sample()
        let provider = ControlledFPLProvider(snapshot: fixture, fetchedAt: instant)
        let clock = FPLEvidenceTestClock(instant)
        let model = model(provider, clock: clock)
        await model.loadData()
        model.comparisonPlayer1ID = 1
        model.comparisonPlayer2ID = 2
        _ = await model.fetchElementSummary(playerID: 1)
        _ = await model.fetchElementSummary(playerID: 1)
        let firstCalls = await provider.elementCalls
        XCTAssertEqual(firstCalls, 1)
        clock.advance(301)
        await provider.replace(fixture, fetchedAt: clock.now)
        _ = await model.fetchElementSummary(playerID: 1)
        let secondCalls = await provider.elementCalls
        XCTAssertEqual(secondCalls, 2)
        let acceptedAt = model.resourceMetadata["element-1"]?.fetchedAt
        await provider.setElementFailure(true)
        _ = await model.fetchElementSummary(playerID: 1, forceRefresh: true)
        XCTAssertNotNil(model.elementSummaries[1])
        XCTAssertEqual(model.resourceMetadata["element-1"]?.fetchedAt, acceptedAt)
        XCTAssertTrue(model.playerHistoryStatus(playerID: 1).contains("failed"))
        XCTAssertEqual(model.comparisonPlayer1ID, 1)
        XCTAssertEqual(model.comparisonPlayer2ID, 2)
        XCTAssertTrue(model.loadingElementSummaries.isEmpty)
        let ages = await provider.elementMaximumAges
        XCTAssertEqual(ages.last, 0)
    }

    func testPlayerHistoryCoalescesAndManagerResetRejectsLateCompletion() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        await provider.holdNextElement()
        let first = Task { await model.fetchElementSummary(playerID: 1) }
        await provider.waitUntilElementHeld()
        let second = Task { await model.fetchElementSummary(playerID: 1) }
        await Task.yield()
        model.clearManagerId()
        await provider.releaseElement()
        _ = await (first.value, second.value)
        let count = await provider.elementCalls
        XCTAssertEqual(count, 1)
        XCTAssertTrue(model.elementSummaries.isEmpty)
        XCTAssertTrue(model.elementSummaryErrors.isEmpty)
        XCTAssertTrue(model.loadingElementSummaries.isEmpty)
    }

    func testFirstPendingHistoryCannotCoalesceAcrossChangedPlayerIdentity() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        await provider.holdNextElement()
        let old = Task { await model.fetchElementSummary(playerID: 1) }
        await provider.waitUntilElementHeld()
        XCTAssertNil(model.elementSummaries[1], "The first request has not published a cache entry yet")

        let updatedAt = instant.addingTimeInterval(1)
        await provider.replace(try sample(firstPlayerName: "Replacement identity"), fetchedAt: updatedAt)
        await model.refreshMatchdayData()
        XCTAssertEqual(model.bootstrap?.elements.first?.firstName, "Replacement identity")
        let freshStarted = expectation(description: "New-identity history waiter started")
        let fresh = Task {
            freshStarted.fulfill()
            return await model.fetchElementSummary(playerID: 1)
        }
        // The MainActor waiter enters fetchElementSummary before yielding. It
        // either starts a new request or joins the obsolete one before release.
        await fulfillment(of: [freshStarted], timeout: 2)
        await provider.releaseElement()
        let (oldResult, freshResult) = await (old.value, fresh.value)

        XCTAssertNil(oldResult)
        XCTAssertNotNil(freshResult)
        let calls = await provider.elementCalls
        XCTAssertEqual(calls, 2, "A reused numeric ID with a changed identity requires a new history request")
        XCTAssertEqual(model.resourceMetadata["element-1"]?.fetchedAt, updatedAt)
        XCTAssertTrue(model.loadingElementSummaries.isEmpty)
    }

    func testHistoryRevisionRejectsOlderOrDiskEvidenceAsCurrent() async throws {
        let fixture = try sample()
        let provider = ControlledFPLProvider(snapshot: fixture, fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        _ = await model.fetchElementSummary(playerID: 1)
        let oldRevision = model.evidenceRevision
        await model.refreshMatchdayData()
        XCTAssertNotEqual(model.evidenceRevision, oldRevision)
        XCTAssertNotNil(model.resourceMetadata["element-1"])
        await provider.replace(fixture, fetchedAt: instant.addingTimeInterval(-1))
        _ = await model.fetchElementSummary(playerID: 1, forceRefresh: true)
        XCTAssertEqual(model.resourceMetadata["element-1"]?.fetchedAt, instant)
        XCTAssertTrue(model.playerHistoryStatus(playerID: 1).contains("rejected"))
        await provider.replace(fixture, fetchedAt: instant)
        await provider.setElementDisk(true)
        _ = await model.fetchElementSummary(playerID: 2)
        XCTAssertNotNil(model.elementSummaries[2])
        XCTAssertFalse(FPLPlayerEvidencePolicy.isCurrent(model.resourceMetadata["element-2"], at: instant))
        XCTAssertTrue(model.playerHistoryStatus(playerID: 2).contains("saved history"))
    }

    func testHistoryRolloverRejectsCachedAndForcedReadsWithoutProviderCalls() async throws {
        let clock = FPLEvidenceTestClock(instant)
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        let model = model(provider, clock: clock, defaults: defaults)
        await model.loadData()
        model.addCoachMessage(AICoachMessage(sender: .user, text: "Existing season question", date: instant))
        let originalMessageIDs = model.coachMessages.map(\.id)
        let originalMessageText = model.coachMessages.map(\.text)
        let initial = await model.fetchElementSummary(playerID: 1)
        XCTAssertNotNil(initial)
        let originalMetadata = model.resourceMetadata["element-1"]
        let originalCalls = await provider.elementCalls
        XCTAssertEqual(originalCalls, 1)

        let rollover = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-07-01T00:00:00Z"))
        clock.advance(rollover.timeIntervalSince(clock.now))
        // Fresh-looking provenance must not bypass the loaded calendar's
        // identity boundary, even before the next workspace refresh runs.
        model.resourceMetadata["element-1"] = FPLResourceMetadata(source: .memoryCache,
            fetchedAt: clock.now, endpoint: "element-summary/1/")
        let cached = await model.fetchElementSummary(playerID: 1)
        let forced = await model.fetchElementSummary(playerID: 1, forceRefresh: true)
        XCTAssertNil(cached)
        XCTAssertNil(forced)
        let calls = await provider.elementCalls
        XCTAssertEqual(calls, originalCalls)
        XCTAssertTrue(model.loadingElementSummaries.isEmpty)
        XCTAssertNotNil(originalMetadata)

        var cloudCalls = 0
        let coachTask = model.sendCoachQuestion("Who should I buy?", operation: { _, _ in
            cloudCalls += 1
            XCTFail("A stale-season workspace must not initiate a paid Coach operation")
            throw URLError(.badServerResponse)
        })
        XCTAssertNil(coachTask)
        await coachTask?.value
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertTrue(model.coachStatusMessage?.contains("Refresh and confirm your current-season team") == true)
        XCTAssertEqual(model.coachMessages.map(\.id), originalMessageIDs)
        XCTAssertEqual(model.coachMessages.map(\.text), originalMessageText)
        XCTAssertFalse(model.isCoachThinking)

        await model.loadLeagueStandings(leagueId: 1)
        XCTAssertTrue(model.leagueErrorMessage?.contains("current-season") == true)
        XCTAssertNil(model.leagueStandings)
        XCTAssertFalse(model.isLeagueLoading)
    }

    func testLocalFactualCoachDoesNotRequireConsentOrCallCloudOperation() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        var cloudCalls = 0
        let task = try XCTUnwrap(model.sendCoachQuestion("What are my total points?", operation: { _, _ in
            cloudCalls += 1
            throw URLError(.badServerResponse)
        }))
        await task.value
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertEqual(model.coachMessages.last?.coachCard?.source, FPLSmartCoachResult.Source.rulesEngine.rawValue)
        let strategy = try XCTUnwrap(model.sendCoachQuestion("Who should I buy?", operation: { _, _ in
            cloudCalls += 1
            throw URLError(.badServerResponse)
        }))
        await strategy.value
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertTrue(model.coachMessages.last?.text.contains("Cloud Coach is off") == true)
    }

    func testLegacyManagerRequiresSeasonConfirmationWithoutLoadingOrDeletingPlans() async throws {
        let suite = "FottySeasonTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "fotty.user.fplManagerId")
        defaults.set("keep", forKey: "fotty.fpl.2025-26.manager.42.customDraftPicks")
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let date = instant
        let model = FPLAdvisorViewModel(draftDefaults: defaults, dataProvider: provider, now: { date })
        XCTAssertTrue(model.requiresManagerConfirmation)
        await model.loadData()
        let count = await provider.bootstrapCalls
        XCTAssertEqual(count, 0)
        XCTAssertNil(model.bootstrap)
        XCTAssertEqual(model.managerId, 42)
        XCTAssertEqual(defaults.string(forKey: "fotty.fpl.2025-26.manager.42.customDraftPicks"), "keep")
        let store = FPLManagerSeasonStore(defaults: defaults)
        store.confirm(managerID: 42, at: instant)
        XCTAssertFalse(store.needsConfirmation(managerID: 42, at: instant))
        XCTAssertTrue(store.needsConfirmation(managerID: 43, at: instant))
        XCTAssertTrue(store.needsConfirmation(managerID: 42, at: instant.addingTimeInterval(366 * 86_400)))
        model.requestManagerConfirmation(managerID: 42)
        XCTAssertTrue(store.needsConfirmation(managerID: 42, at: instant))
        XCTAssertTrue(model.requiresManagerConfirmation)
        XCTAssertEqual(defaults.string(forKey: "fotty.fpl.2025-26.manager.42.customDraftPicks"), "keep")
    }

    func testLoadedWorkspaceRolloverRejectsDraftSaveWithoutChangingStoredPlan() async throws {
        let defaults = isolatedDefaults()
        let clock = FPLEvidenceTestClock(instant)
        let managerID = 9_999_981
        defaults.set(managerID, forKey: "fotty.user.fplManagerId")
        FPLManagerSeasonStore(defaults: defaults).confirm(managerID: managerID, at: clock.now)
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider, clock: clock, defaults: defaults)
        await model.loadData()
        let picks = try XCTUnwrap(model.picks?.picks)
        XCTAssertTrue(model.updateUserSquad(picks: picks))
        let workspace = FPLWorkspacePersistence(defaults: defaults)
        let saved = try XCTUnwrap(workspace.loadDraft(managerID: managerID))

        let rollover = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-07-01T00:00:00Z"))
        clock.advance(rollover.timeIntervalSince(clock.now))
        XCTAssertFalse(model.updateUserSquad(picks: picks))
        XCTAssertTrue(model.requiresManagerConfirmation)
        XCTAssertEqual(workspace.loadDraft(managerID: managerID), saved)
        XCTAssertNil(defaults.data(forKey: "fotty.fpl.2027-28.manager.\(managerID).customDraftPicks"))
    }

    func testLoadedJournalRolloverCannotUpdateDeleteOrReassignOldEntries() async throws {
        let clock = FPLEvidenceTestClock(instant)
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        // An already-loaded workspace must reject the mutation even before a
        // refresh has had a chance to change requiresManagerConfirmation.
        let model = model(provider, clock: clock)
        await model.loadData()
        let managerID = try XCTUnwrap(model.managerId)
        let seasons = ["2026-27", "2027-28"]
        let keys = seasons.map { "fotty.fpl.\($0).manager.\(managerID).decisionJournal" }
        let prior = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, prior) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let entry = FPLDecisionJournalEntry(managerID: managerID, gameweek: 2, kind: .strategy,
            title: "Original season plan", rationale: "Reviewed before rollover", expectedOutcome: "Review later",
            source: "Test", createdAt: instant, updatedAt: instant)
        let original = FPLDecisionJournalStore.upsert(entry, managerID: managerID, season: seasons[0])
        model.decisionJournalEntries = original
        let oldBytes = UserDefaults.standard.data(forKey: keys[0])
        let nextBytes = UserDefaults.standard.data(forKey: keys[1])
        let rollover = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-07-01T00:00:00Z"))
        clock.advance(rollover.timeIntervalSince(clock.now))

        model.updateDecisionOutcome(id: entry.id, outcome: .worked, note: "Must not move seasons")
        XCTAssertFalse(model.recordDecision(kind: .strategy, title: "Wrong season", rationale: "",
            expectedOutcome: "", source: "Test", targetGameweek: 2))
        model.removeDecision(id: entry.id)
        XCTAssertEqual(UserDefaults.standard.data(forKey: keys[0]), oldBytes)
        XCTAssertEqual(UserDefaults.standard.data(forKey: keys[1]), nextBytes)
        XCTAssertEqual(model.decisionJournalEntries, original)
    }

    func testLoadStartedBeforeRolloverCannotPublishAfterRollover() async throws {
        let defaults = isolatedDefaults()
        let clock = FPLEvidenceTestClock(instant)
        defaults.set(9_999_981, forKey: "fotty.user.fplManagerId")
        FPLManagerSeasonStore(defaults: defaults).confirm(managerID: 9_999_981, at: clock.now)
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let model = model(provider, clock: clock, defaults: defaults)
        await provider.holdNextBootstrap()
        let load = Task { await model.loadData() }
        await provider.waitUntilHeld()
        let rollover = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-07-01T00:00:00Z"))
        clock.advance(rollover.timeIntervalSince(clock.now))
        await provider.releaseBootstrap()
        await load.value

        XCTAssertTrue(model.requiresManagerConfirmation)
        XCTAssertNil(model.bootstrap)
        XCTAssertNil(model.officialPicks)
        XCTAssertNil(model.eventLive)
        XCTAssertTrue(model.resourceMetadata.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isRefreshing)
    }

    func testUnscopedLegacyWorkspaceIsPreservedWithoutCurrentSeasonAdoption() throws {
        let defaults = isolatedDefaults()
        let picks = try sample().picks.picks
        let legacyDraft = try JSONEncoder().encode(picks)
        let legacyChat = Data("legacy chat without an owner or season".utf8)
        defaults.set(42, forKey: "fotty.user.fplManagerId")
        defaults.set(legacyDraft, forKey: "fotty.fpl.customDraftPicks")
        defaults.set(legacyChat, forKey: "fotty.fpl.coachMessages")
        let provider = ControlledFPLProvider(snapshot: try sample(), fetchedAt: instant)
        let date = instant
        let model = FPLAdvisorViewModel(draftDefaults: defaults, dataProvider: provider, now: { date })
        XCTAssertTrue(model.requiresManagerConfirmation)
        let persistence = FPLWorkspacePersistence(defaults: defaults)
        persistence.migrateLegacyWorkspace(managerID: 42)
        persistence.migrateLegacyWorkspace(managerID: 43)

        XCTAssertEqual(defaults.data(forKey: "fotty.fpl.customDraftPicks"), legacyDraft)
        XCTAssertEqual(defaults.data(forKey: "fotty.fpl.coachMessages"), legacyChat)
        for managerID in [42, 43] {
            XCTAssertNil(persistence.loadDraft(managerID: managerID))
            XCTAssertTrue(persistence.loadCoachMessages(managerID: managerID).isEmpty)
            let prefix = "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.\(managerID)"
            XCTAssertNil(defaults.data(forKey: prefix + ".customDraftPicks"))
            XCTAssertNil(defaults.data(forKey: prefix + ".coachMessages"))
        }
    }

    func testLegacyQuarantineDoesNotReplaceCurrentSeasonScopedDraft() throws {
        let defaults = isolatedDefaults()
        let persistence = FPLWorkspacePersistence(defaults: defaults)
        let scoped = FPLLocalSquadDraft(picks: try sample().picks.picks, basedOnGameweek: 1,
                                       targetGameweek: 2, budgetLimit: 1_000)
        try persistence.saveDraft(scoped, managerID: 42)
        let legacy = Data("unowned older draft".utf8)
        defaults.set(legacy, forKey: "fotty.fpl.customDraftPicks")
        persistence.migrateLegacyWorkspace(managerID: 42)
        XCTAssertEqual(persistence.loadDraft(managerID: 42), scoped)
        XCTAssertEqual(defaults.data(forKey: "fotty.fpl.customDraftPicks"), legacy)
    }

    func testJournalUsesRoutePlanningGameweekAndRejectsBeyondSeason() async throws {
        let provider = ControlledFPLProvider(snapshot: try sample(gameweek: 3), fetchedAt: instant)
        let model = model(provider)
        await model.loadData()
        let id = try XCTUnwrap(model.managerId)
        let season = FPLSeasonIdentifier.label(from: try XCTUnwrap(model.bootstrap).events)
        let key = "fotty.fpl.\(season).manager.\(id).decisionJournal"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let route = FPLDraftRoute(name: "Next deadline", transfers: [], hitCost: 0, projectedGain: 2,
            weeklyProjectedGain: [4: 2], breakEvenGameweek: nil, modelVersion: "test", explanation: "Test",
            downside: "Estimate", verificationItems: [])
        model.recordRouteDecision(route)
        XCTAssertEqual(model.decisionJournalEntries.first?.gameweek, 4)
        XCTAssertFalse(model.recordDecision(kind: .strategy, title: "Invalid", rationale: "", expectedOutcome: "",
            source: "Test", targetGameweek: 39))
        XCTAssertFalse(model.decisionJournalEntries.contains { $0.gameweek == 39 })
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "FottyFPLMatchdayRefreshTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func model(_ provider: ControlledFPLProvider, clock: FPLEvidenceTestClock? = nil,
                       defaults: UserDefaults? = nil) -> FPLAdvisorViewModel {
        let date = instant
        let model = FPLAdvisorViewModel(draftDefaults: defaults ?? isolatedDefaults(), dataProvider: provider,
                                       now: { clock?.now ?? date })
        model.managerId = 9_999_981
        return model
    }

    private func sample(
        gameweek: Int = 1, planning: Bool = false, fixturesFinished: Bool = false, checked: Bool = false,
        unfinishedFixtureIDs: Set<Int> = [], firstPlayerName: String = "Player"
    ) throws -> FPLRefreshFixture {
        func decode<T: Decodable>(_ object: Any) throws -> T {
            try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let formatter = ISO8601DateFormatter()
        let positions = [1, 1] + Array(repeating: 2, count: 5) + Array(repeating: 3, count: 5) + Array(repeating: 4, count: 3) + [2]
        let players: [[String: Any]] = positions.enumerated().map { offset, position in
            ["id": offset + 1, "web_name": "P\(offset + 1)", "first_name": offset == 0 ? firstPlayerName : "Player", "second_name": "\(offset + 1)",
             "team": offset == 15 ? 3 : offset % 5 + 1, "team_code": offset == 15 ? 3 : offset % 5 + 1, "element_type": position,
             "now_cost": 50, "cost_change_event": 0, "cost_change_event_fall": 0, "selected_by_percent": "10",
             "form": "4", "points_per_game": "4", "total_points": 10, "event_points": 0, "minutes": 180,
             "goals_scored": 0, "assists": 0, "clean_sheets": 0, "goals_conceded": 0, "yellow_cards": 0,
             "red_cards": 0, "saves": 0, "bonus": 0, "bps": 0, "influence": "0", "creativity": "0",
             "threat": "0", "ict_index": "0", "starts": 2, "transfers_in_event": 0, "transfers_out_event": 0,
             "status": "a", "news": "", "can_select": true]
        }
        func event(_ id: Int, next: Bool = false) -> [String: Any] {
            let deadline = instant.addingTimeInterval(next ? 604_800 : (planning ? 3_600 : -7_200))
            return ["id": id, "name": "Gameweek \(id)", "deadline_time": formatter.string(from: deadline),
                    "deadline_time_epoch": Int(deadline.timeIntervalSince1970), "finished": !next && checked,
                    "data_checked": !next && checked, "is_previous": false, "is_current": !next, "is_next": next]
        }
        let bootstrap: FPLBootstrapResponse = try decode([
            "events": [event(gameweek), event(gameweek + 1, next: true)], "elements": players,
            "teams": (1...5).map { ["id": $0, "code": $0, "name": "Team \($0)", "short_name": "T\($0)"] as [String: Any] },
            "element_types": [
                ["id": 1, "singular_name": "Goalkeeper", "singular_name_short": "GKP", "plural_name": "Goalkeepers", "plural_name_short": "GKP", "squad_select": 2, "squad_min_play": 1, "squad_max_play": 1],
                ["id": 2, "singular_name": "Defender", "singular_name_short": "DEF", "plural_name": "Defenders", "plural_name_short": "DEF", "squad_select": 5, "squad_min_play": 3, "squad_max_play": 5],
                ["id": 3, "singular_name": "Midfielder", "singular_name_short": "MID", "plural_name": "Midfielders", "plural_name_short": "MID", "squad_select": 5, "squad_min_play": 2, "squad_max_play": 5],
                ["id": 4, "singular_name": "Forward", "singular_name_short": "FWD", "plural_name": "Forwards", "plural_name_short": "FWD", "squad_select": 3, "squad_min_play": 1, "squad_max_play": 3]
            ], "total_players": 16
        ])
        let fixtures: [FPLFixture] = try decode((1...5).map { team -> [String: Any] in
            let pending = unfinishedFixtureIDs.contains(team)
            return ["id": team, "event": gameweek, "team_h": team, "team_a": team % 5 + 1,
             "finished": fixturesFinished && !pending, "finished_provisional": fixturesFinished && !pending, "started": !planning && !pending,
             "kickoff_time": formatter.string(from: instant.addingTimeInterval(pending ? 86_400 : (planning ? 7_200 : -3_600))),
             "team_h_difficulty": 3, "team_a_difficulty": 3]
        })
        let ordered = [1, 3, 4, 5, 8, 9, 10, 11, 13, 14, 15, 2, 6, 7, 12]
        let picks = FPLManagerPicks(activeChip: nil, entryHistory: FPLGameweekHistory(
            event: gameweek, points: checked ? 64 : 50, totalPoints: 64, rank: nil, overallRank: nil,
            bank: 250, value: 1_000, eventTransfers: 0, eventTransfersCost: 0, pointsOnBench: 8
        ), picks: ordered.enumerated().map { offset, id in
            FPLPick(element: id, position: offset + 1, multiplier: id == 13 ? 2 : (offset < 11 ? 1 : 0),
                    isCaptain: id == 13, isViceCaptain: id == 14, elementType: nil)
        })
        let live: FPLEventLiveResponse = try decode(["elements": (1...15).map { id -> [String: Any] in
            ["id": id, "stats": ["minutes": id == 1 ? 0 : 90, "goals_scored": 0, "assists": 0,
                "clean_sheets": 0, "goals_conceded": 0, "yellow_cards": 0, "red_cards": 0, "saves": 0,
                "bonus": 0, "bps": 0, "total_points": id == 2 ? 8 : (id == 1 ? 0 : 5), "played": id != 1],
             "explain": [], "modified": false]
        }])
        let summary: FPLManagerSummary = try decode(["id": 9_999_981, "name": "Test manager", "player_first_name": "Test", "player_last_name": "Manager", "last_deadline_bank": 250])
        let history: FPLManagerHistoryResponse = try decode(["current": [], "past": [], "chips": []])
        return FPLRefreshFixture(bootstrap: bootstrap, fixtures: fixtures, picks: picks, live: live, summary: summary, history: history)
    }
}

private struct FPLRefreshFixture: Sendable {
    let bootstrap: FPLBootstrapResponse
    let fixtures: [FPLFixture]
    let picks: FPLManagerPicks
    let live: FPLEventLiveResponse
    let summary: FPLManagerSummary
    let history: FPLManagerHistoryResponse
}

/// Deliberately does not obey Task cancellation, proving the view-model's own
/// publication guard against late network/cache completions.
private actor ControlledFPLProvider: FPLAdvisorDataProviding {
    private var snapshot: FPLRefreshFixture
    private var fetchedAt: Date
    private var diskFixtures = false
    private var holdBootstrap = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var bootstrapCalls = 0
    private(set) var elementCalls = 0
    private(set) var elementMaximumAges: [TimeInterval] = []
    private var elementFailure = false
    private var elementDisk = false
    private var holdElement = false
    private var heldElement: CheckedContinuation<Void, Never>?
    private var waitingElement: CheckedContinuation<Void, Never>?

    init(snapshot: FPLRefreshFixture, fetchedAt: Date) { self.snapshot = snapshot; self.fetchedAt = fetchedAt }
    func replace(_ snapshot: FPLRefreshFixture, fetchedAt: Date) { self.snapshot = snapshot; self.fetchedAt = fetchedAt }
    func setDiskFixtureFallback(_ enabled: Bool) { diskFixtures = enabled }
    func holdNextBootstrap() { holdBootstrap = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func releaseBootstrap() { held?.resume(); held = nil }
    func clearCache() {}
    func setElementFailure(_ enabled: Bool) { elementFailure = enabled }
    func setElementDisk(_ enabled: Bool) { elementDisk = enabled }
    func holdNextElement() { holdElement = true }
    func waitUntilElementHeld() async {
        if heldElement != nil { return }
        await withCheckedContinuation { waitingElement = $0 }
    }
    func releaseElement() { heldElement?.resume(); heldElement = nil }
    func fetchElementSummaryResource(playerId: Int, maximumAge: TimeInterval) async throws -> FPLResource<FPLElementSummaryResponse> {
        elementCalls += 1
        elementMaximumAges.append(maximumAge)
        if elementFailure { throw URLError(.notConnectedToInternet) }
        let value = try JSONDecoder().decode(FPLElementSummaryResponse.self,
            from: Data(#"{"fixtures":[],"history":[],"history_past":[]}"#.utf8))
        let result = resource(value, endpoint: "element-summary/\(playerId)/", disk: elementDisk)
        if holdElement {
            holdElement = false
            await withCheckedContinuation { heldElement = $0; waitingElement?.resume(); waitingElement = nil }
        }
        return result
    }
    private func resource<T: Sendable>(_ value: T, endpoint: String, disk: Bool = false) -> FPLResource<T> {
        FPLResource(value: value, metadata: FPLResourceMetadata(source: disk ? .diskSnapshot : .network, fetchedAt: fetchedAt, endpoint: endpoint))
    }
    func fetchBootstrapResource(maximumAge: TimeInterval) async throws -> FPLResource<FPLBootstrapResponse> {
        bootstrapCalls += 1
        let result = resource(snapshot.bootstrap, endpoint: "bootstrap-static/")
        if holdBootstrap {
            holdBootstrap = false
            await withCheckedContinuation { held = $0; waiting?.resume(); waiting = nil }
        }
        return result
    }
    func fetchFixturesResource() -> FPLResource<[FPLFixture]> { resource(snapshot.fixtures, endpoint: "fixtures/", disk: diskFixtures) }
    func fetchManagerSummaryResource(id: Int) -> FPLResource<FPLManagerSummary> { resource(snapshot.summary, endpoint: "entry/\(id)/") }
    func fetchManagerHistoryResource(id: Int) -> FPLResource<FPLManagerHistoryResponse> { resource(snapshot.history, endpoint: "entry/\(id)/history/") }
    func fetchPicksResource(managerId: Int, gameweek: Int) -> FPLResource<FPLManagerPicks> { resource(snapshot.picks, endpoint: "entry/\(managerId)/event/\(gameweek)/picks/") }
    func fetchEventLiveResource(gameweek: Int) -> FPLResource<FPLEventLiveResponse> { resource(snapshot.live, endpoint: "event/\(gameweek)/live/") }
}

private final class FPLEvidenceTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(interval) }
}
