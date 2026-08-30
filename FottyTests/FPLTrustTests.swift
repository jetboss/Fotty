import XCTest
@testable import Fotty

final class FPLTrustTests: XCTestCase {
    func testSeasonIdentifierRollsAtTheJulyBoundary() throws {
        let formatter = ISO8601DateFormatter()
        let june = try XCTUnwrap(formatter.date(from: "2027-06-30T23:59:59Z"))
        let july = try XCTUnwrap(formatter.date(from: "2027-07-01T00:00:00Z"))
        XCTAssertEqual(FPLSeasonIdentifier.currentLabel(at: june), "2026-27")
        XCTAssertEqual(FPLSeasonIdentifier.currentLabel(at: july), "2027-28")
    }

    func testDiskSnapshotPolicyRejectsExpiredLiveAndWrongSeasonData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let liveEndpoint = "event/2/live/"
        let fresh = FPLDiskSnapshotEnvelope(
            version: FPLDiskSnapshotEnvelope.currentVersion,
            endpoint: liveEndpoint,
            savedAt: now.addingTimeInterval(-299),
            season: "2026-27",
            catalogFingerprint: "clubs-v1",
            payload: Data()
        )
        XCTAssertTrue(FPLDiskSnapshotPolicy.isUsable(
            fresh,
            endpoint: liveEndpoint,
            expectedSeason: "2026-27",
            expectedCatalogFingerprint: "clubs-v1",
            now: now
        ))

        let expired = FPLDiskSnapshotEnvelope(
            version: FPLDiskSnapshotEnvelope.currentVersion,
            endpoint: liveEndpoint,
            savedAt: now.addingTimeInterval(-301),
            season: "2026-27",
            catalogFingerprint: "clubs-v1",
            payload: Data()
        )
        XCTAssertFalse(FPLDiskSnapshotPolicy.isUsable(
            expired,
            endpoint: liveEndpoint,
            expectedSeason: "2026-27",
            expectedCatalogFingerprint: "clubs-v1",
            now: now
        ))
        XCTAssertFalse(FPLDiskSnapshotPolicy.isUsable(
            fresh,
            endpoint: liveEndpoint,
            expectedSeason: "2027-28",
            expectedCatalogFingerprint: "clubs-v1",
            now: now
        ))
        XCTAssertFalse(FPLDiskSnapshotPolicy.isUsable(
            fresh,
            endpoint: liveEndpoint,
            expectedSeason: "2026-27",
            expectedCatalogFingerprint: "clubs-v2",
            now: now
        ))
    }

    @MainActor
    func testSavedReplacementSurvivesPublishedRefreshAndRelaunch() throws {
        let defaults = isolatedDraftDefaults()
        let model = try draftModel(defaults: defaults)
        let official = model.officialPicks
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        let draft = try XCTUnwrap(model.picks?.picks)
        XCTAssertTrue(draft.contains { $0.element == 16 })
        XCTAssertFalse(draft.contains { $0.element == 3 })

        // Both foreground/full refresh and matchday refresh use this transition.
        model.applyPublishedSquad(official, gameweek: 1)
        XCTAssertEqual(model.picks?.picks, draft)
        XCTAssertEqual(model.officialPicks?.picks, official?.picks)
        XCTAssertTrue(model.isCustomDraft)
        let reopened = try draftModel(defaults: defaults)
        XCTAssertEqual(reopened.picks?.picks, draft)
        XCTAssertTrue(reopened.isCustomDraft)
        XCTAssertEqual(reopened.savedSquadDraft?.basedOnGameweek, 1)
        XCTAssertEqual(reopened.savedSquadDraft?.targetGameweek, 2)
    }

    @MainActor
    func testPublishedViewChoicePersistsWithoutDeletingDraft() throws {
        let defaults = isolatedDraftDefaults()
        let model = try draftModel(defaults: defaults)
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        let saved = model.picks?.picks
        model.showPublishedSquad()
        XCTAssertFalse(model.isCustomDraft)
        XCTAssertEqual(model.picks?.picks, model.officialPicks?.picks)
        let reopened = try draftModel(defaults: defaults)
        XCTAssertFalse(reopened.isCustomDraft)
        reopened.showSavedDraft()
        XCTAssertTrue(reopened.isCustomDraft)
        XCTAssertEqual(reopened.picks?.picks, saved)
    }

    @MainActor
    func testNewDeadlineSnapshotKeepsDraftAndCanBeViewedExplicitly() throws {
        let model = try draftModel(defaults: isolatedDraftDefaults())
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        let draft = try XCTUnwrap(model.picks?.picks)
        let newOfficial = FPLManagerPicks(activeChip: "3xc", entryHistory: nil, picks: draft)
        model.applyPublishedSquad(newOfficial, gameweek: 2)
        XCTAssertTrue(model.isCustomDraft)
        XCTAssertEqual(model.picksGameweek, 2)
        XCTAssertTrue(model.squadSourceExplanation.contains("newer published squad"))
        XCTAssertNil(model.picks?.activeChip)
        model.showPublishedSquad()
        XCTAssertEqual(model.squadSourceTitle, "Published squad · GW2")
        XCTAssertEqual(model.picks?.activeChip, "3xc")
        XCTAssertEqual(model.savedSquadDraft?.picks, draft)
        // Late fallback responses cannot roll back the newly published lineup.
        model.applyPublishedSquad(FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: validPicks()), gameweek: 1)
        XCTAssertEqual(model.picksGameweek, 2)
        XCTAssertEqual(model.picks?.picks, draft)
    }

    @MainActor
    func testDraftDoesNotChangeOfficialAutosubsOrSixtyFourPointTotal() throws {
        let model = try draftModel(defaults: isolatedDraftDefaults())
        model.eventLive = try decodeAutosubLive(noAppearance: [1, 3], points: [2: 7, 6: 7])
        model.fixtures = try decodeCompletedFixtures()
        model.rebuildDecisionState(rebuildOptimizer: false)
        XCTAssertEqual(model.liveSquadSummary?.totalPoints, 64)
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        XCTAssertEqual(model.liveSquadSummary?.totalPoints, 64)
        XCTAssertEqual(model.liveSquadSummary?.officialCurrentPoints, 50)
        XCTAssertNil(model.picks?.entryHistory)
        XCTAssertEqual(model.picks?.automaticSubs.count, 0)
        XCTAssertTrue(model.officialPicks?.picks.contains { $0.element == 3 } == true)
    }

    @MainActor
    func testPreviousGameweekPicksNeverScoreAgainstNewGameweekLiveData() throws {
        let model = try draftModel(defaults: isolatedDraftDefaults())
        model.currentGameweek = try decodeGameweek(deadline: "2026-08-28T17:30:00Z", id: 2)
        model.eventLive = try decodeAutosubLive(noAppearance: [], points: [:])
        model.rebuildDecisionState(rebuildOptimizer: false)
        XCTAssertNil(model.liveSquadSummary)
        XCTAssertEqual(model.squadSourceTitle, "Published squad · GW1")
    }

    @MainActor
    func testCoachCaptainFactUsesPublishedSquadNotDraft() async throws {
        let model = try draftModel(defaults: isolatedDraftDefaults())
        model.setCaptain(elementId: 14)
        XCTAssertEqual(model.picks?.picks.first(where: \.isCaptain)?.element, 14)
        let result = await FPLAICoachService.deterministicResultIfApplicable(
            userQuery: "who is my captain", managerSummary: nil,
            currentGw: model.currentGameweek, picks: model.officialPicks,
            scores: model.playerScores, freeTransfers: nil, live: nil,
            players: model.bootstrap?.elements ?? [], settings: model.bootstrap?.gameSettings,
            freshness: nil, publishedGameweek: model.picksGameweek
        )
        XCTAssertTrue(result?.answer.contains("**P13**") == true)
        XCTAssertTrue(result?.answer.contains("GW1") == true)
        XCTAssertEqual(result?.usage?.totalTokens, 0)
    }

    @MainActor
    func testRejectedReplacementDoesNotChangeStoredDraftOrClaimSuccess() throws {
        let defaults = isolatedDraftDefaults()
        let model = try draftModel(defaults: defaults)
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        let saved = model.picks?.picks
        let duplicate = try XCTUnwrap(model.playerScores.first { $0.player.id == 4 })
        XCTAssertFalse(model.replacePlayer(oldElementId: 16, newScore: duplicate))
        XCTAssertNotNil(model.draftErrorMessage)
        XCTAssertEqual(model.picks?.picks, saved)
        XCTAssertEqual(try draftModel(defaults: defaults).picks?.picks, saved)
        XCTAssertFalse(model.replacePlayer(oldElementId: 999, newScore: replacement))
    }

    @MainActor
    func testDraftStorageRemainsManagerScopedAndSurvivesDisconnect() throws {
        let defaults = isolatedDraftDefaults()
        let model = try draftModel(defaults: defaults)
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        let saved = model.picks?.picks
        model.clearManagerId()
        XCTAssertNil(model.picks)
        XCTAssertNil(model.officialPicks)
        XCTAssertNil(model.savedSquadDraft)
        let other = try draftModel(defaults: defaults, managerID: 9_999_992)
        XCTAssertFalse(other.isCustomDraft)
        XCTAssertNil(other.savedSquadDraft)
        XCTAssertEqual(try draftModel(defaults: defaults).picks?.picks, saved)
    }

    @MainActor
    func testLegacyDraftAndOfflineRefreshRemainReadable() throws {
        let defaults = isolatedDraftDefaults()
        let key = "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.9999991.customDraftPicks"
        defaults.set(try JSONEncoder().encode(validPicks()), forKey: key)
        let model = try draftModel(defaults: defaults)
        XCTAssertTrue(model.isCustomDraft)
        model.applyPublishedSquad(nil, gameweek: nil)
        XCTAssertEqual(model.picks?.picks, validPicks())
        XCTAssertEqual(model.picksGameweek, 1)
        // A draft subsequently edited by build 43 takes precedence over old metadata.
        let replacement = try XCTUnwrap(model.playerScores.first { $0.player.id == 16 })
        XCTAssertTrue(model.replacePlayer(oldElementId: 3, newScore: replacement))
        defaults.set(try JSONEncoder().encode(validPicks()), forKey: key)
        model.applyPublishedSquad(nil, gameweek: nil)
        XCTAssertEqual(model.picks?.picks, validPicks())
    }

    @MainActor
    func testClearedCoachChatCannotBeRepopulatedByPendingReply() async throws {
        let model = try coachModel()
        let pending = PendingCoachAnswer(started: expectation(description: "Coach started"))
        let task = try XCTUnwrap(model.sendCoachQuestion("Review my squad", operation: pending.answer))
        await fulfillment(of: [pending.started], timeout: 2)
        model.clearCoachHistory()
        XCTAssertFalse(model.isCoachThinking)
        pending.succeed(coachResult("Discarded old answer"))
        await task.value
        XCTAssertTrue(task.isCancelled)
        XCTAssertTrue(model.coachMessages.isEmpty)
        model.loadSavedCoachMessages()
        XCTAssertTrue(model.coachMessages.isEmpty, "A cleared chat must remain cleared on reopening")
        XCTAssertNil(model.coachStatusMessage)
    }

    @MainActor
    func testDisablingCoachCancelsPendingFailureWithoutAddingFallback() async throws {
        let defaults = isolatedDraftDefaults()
        defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        let model = try draftModel(defaults: defaults)
        let pending = PendingCoachAnswer(started: expectation(description: "Coach started"))
        let task = try XCTUnwrap(model.sendCoachQuestion("Review my squad", operation: pending.answer))
        await fulfillment(of: [pending.started], timeout: 2)
        defaults.set(false, forKey: "fotty.fpl.smartCoachConsent")
        model.cancelCoachRequest()
        pending.fail(URLError(.timedOut))
        await task.value
        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(model.coachMessages.map(\.sender), [.user])
        XCTAssertFalse(model.isCoachThinking)
        XCTAssertNil(model.coachStatusMessage)
        XCTAssertNil(model.sendCoachQuestion("Do not send", operation: pending.answer))
    }

    @MainActor
    func testRevokedConsentRejectsReplyEvenBeforeViewCancellationRuns() async throws {
        let defaults = isolatedDraftDefaults()
        defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        let model = try draftModel(defaults: defaults)
        let pending = PendingCoachAnswer(started: expectation(description: "Coach started"))
        let task = try XCTUnwrap(model.sendCoachQuestion("Review my squad", operation: pending.answer))
        await fulfillment(of: [pending.started], timeout: 2)
        defaults.set(false, forKey: "fotty.fpl.smartCoachConsent")
        pending.succeed(coachResult("Do not display"))
        await task.value
        XCTAssertEqual(model.coachMessages.map(\.sender), [.user])
        XCTAssertFalse(model.isCoachThinking)
        XCTAssertTrue(model.coachStatusMessage?.contains("off") == true)
    }

    @MainActor
    func testOldManagerReplyCannotEnterOrStopNewManagerRequest() async throws {
        let model = try coachModel()
        let old = PendingCoachAnswer(started: expectation(description: "Old manager started"))
        let first = try XCTUnwrap(model.sendCoachQuestion("Old manager question", operation: old.answer))
        await fulfillment(of: [old.started], timeout: 2)
        model.clearManagerId()
        model.managerId = 9_999_992
        let current = PendingCoachAnswer(started: expectation(description: "New manager started"))
        let second = try XCTUnwrap(model.sendCoachQuestion("New manager question", operation: current.answer))
        await fulfillment(of: [current.started], timeout: 2)
        old.succeed(coachResult("Old manager answer"))
        await first.value
        XCTAssertTrue(model.isCoachThinking, "Old completion cannot stop the new request")
        XCTAssertEqual(model.coachMessages.map(\.text), ["New manager question"])
        current.succeed(coachResult("New manager answer"))
        await second.value
        XCTAssertFalse(model.isCoachThinking)
        XCTAssertEqual(model.coachMessages.map(\.text), ["New manager question", "New manager answer"])
        model.loadSavedCoachMessages()
        XCTAssertEqual(model.coachMessages.map(\.text), ["New manager question", "New manager answer"])
    }

    @MainActor
    func testChangedCoachContextDiscardsReplyWithoutAutomaticRetry() async throws {
        let mutations: [(String, (FPLAdvisorViewModel) throws -> Void)] = [
            ("squad", { $0.setCaptain(elementId: 14) }),
            ("gameweek", { $0.currentGameweek = try self.decodeGameweek(deadline: "2026-08-28T17:30:00Z", id: 2) }),
            ("published week", { $0.applyPublishedSquad($0.officialPicks, gameweek: 2) }),
            ("profile", { $0.coachProfile.planningHorizon = 8 }),
            ("rival", { $0.selectedRivalID = 9_999_993 })
        ]
        for (label, mutate) in mutations {
            let model = try coachModel()
            let pending = PendingCoachAnswer(started: expectation(description: "\(label) request started"))
            let task = try XCTUnwrap(model.sendCoachQuestion("Review my squad", operation: pending.answer))
            await fulfillment(of: [pending.started], timeout: 2)
            try mutate(model)
            pending.succeed(coachResult("Outdated plan"))
            await task.value
            XCTAssertEqual(model.coachMessages.map(\.sender), [.user], label)
            XCTAssertFalse(model.isCoachThinking, label)
            XCTAssertTrue(model.coachStatusMessage?.contains("Please ask again") == true, label)
            XCTAssertEqual(pending.calls, 1, "No duplicate or automatic paid retry")
        }
    }

    @MainActor
    func testCoachAllowsOneRequestAndPreservesFollowUpHistory() async throws {
        let model = try coachModel()
        model.addCoachMessage(AICoachMessage(sender: .coach, text: "Compare P3 with P16"))
        let pending = PendingCoachAnswer(started: expectation(description: "Follow-up started"))
        let task = try XCTUnwrap(model.sendCoachQuestion("Why?", operation: pending.answer))
        XCTAssertNil(model.sendCoachQuestion("Duplicate tap", operation: pending.answer))
        await fulfillment(of: [pending.started], timeout: 2)
        XCTAssertEqual(pending.history.map(\.text), ["Compare P3 with P16", "Why?"])
        pending.succeed(coachResult("The same comparison explained"))
        await task.value
        XCTAssertEqual(model.coachMessages.last?.text, "The same comparison explained")
        XCTAssertEqual(model.coachMessages.last?.gameweek, 1)
        XCTAssertFalse(model.isCoachThinking)
    }

    @MainActor
    func testCoachFailureUsesPublishedFactsInsteadOfDraftCaptain() async throws {
        let model = try coachModel()
        model.setCaptain(elementId: 14)
        let task = try XCTUnwrap(model.sendCoachQuestion("Who is my captain?") { _, _ in
            throw URLError(.notConnectedToInternet)
        })
        await task.value
        let reply = try XCTUnwrap(model.coachMessages.last?.coachCard)
        XCTAssertTrue(reply.answer.contains("**P13**"))
        XCTAssertTrue(reply.answer.contains("GW1"))
        XCTAssertFalse(reply.answer.contains("**P14**"))
        XCTAssertEqual(reply.source, FPLSmartCoachResult.Source.rulesEngine.rawValue)
        XCTAssertEqual(reply.usage?.totalTokens, 0)
        XCTAssertFalse(model.isCoachThinking)
    }

    @MainActor
    func testCoachFallbackCannotConvertUndatedScoringIntoCurrentFacts() async throws {
        let model = try coachModel()
        model.eventLive = try decodeAutosubLive(noAppearance: [1, 3], points: [2: 7, 6: 7])
        model.fixtures = try decodeCompletedFixtures()
        model.rebuildDecisionState(rebuildOptimizer: false)
        XCTAssertEqual(model.liveSquadSummary?.totalPoints, 64)
        let result = await model.localCoachFallback(query: "What is my current total?", history: [])
        XCTAssertTrue(result.answer.contains("cannot verify"))
        XCTAssertEqual(result.officialDataStatus, "stale")
        XCTAssertEqual(result.usage?.totalTokens, 0)
    }

    func testDirectCurrentScoreWordingStaysFactualWithoutSwallowingStrategy() {
        for query in ["What is my current total?", "What are my current points?", "Show my live score", "What's my live gameweek total?", "What’s my current total?"] {
            XCTAssertTrue(FPLAICoachService.isScoringQuery(query), query)
        }
        for query in ["How can I improve my score next week?", "What is my projected total next week?", "Who should I captain?", "Should I roll or take a hit?"] {
            XCTAssertFalse(FPLAICoachService.isScoringQuery(query), query)
        }
    }

    @MainActor
    private func coachModel() throws -> FPLAdvisorViewModel {
        let defaults = isolatedDraftDefaults()
        defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        return try draftModel(defaults: defaults)
    }

    private func coachResult(_ answer: String) -> FPLSmartCoachResult {
        FPLSmartCoachResult(
            answer: answer, confidence: "medium", evidence: ["Synthetic test context"],
            assumptions: [], actions: [], model: "Test model", verifiedAt: Date(),
            officialDataStatus: "Test fixture", source: .deepSeek, usage: .zero
        )
    }

    @MainActor
    private final class PendingCoachAnswer {
        let started: XCTestExpectation
        var history: [AICoachMessage] = []
        var calls = 0
        private var continuation: CheckedContinuation<FPLSmartCoachResult, Error>?

        init(started: XCTestExpectation) { self.started = started }

        func answer(_ query: String, _ history: [AICoachMessage]) async throws -> FPLSmartCoachResult {
            calls += 1
            self.history = history
            return try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        }

        // Deliberately ignores cancellation to exercise late transport callbacks.
        func succeed(_ result: FPLSmartCoachResult) {
            continuation?.resume(returning: result)
            continuation = nil
        }

        func fail(_ error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func isolatedDraftDefaults() -> UserDefaults {
        let name = "FottyFPLDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor
    private func draftModel(defaults: UserDefaults, managerID: Int = 9_999_991) throws -> FPLAdvisorViewModel {
        let model = FPLAdvisorViewModel(draftDefaults: defaults)
        model.managerId = managerID
        let bootstrap = try decodeBootstrap(extraDefender: true)
        model.bootstrap = bootstrap
        model.currentGameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        model.gameweekPhase = .live
        model.playerScores = FPLAdvisorEngine.scoreAllPlayers(players: bootstrap.elements, teams: bootstrap.teams, fixtures: [], events: [])
        model.applyPublishedSquad(FPLManagerPicks(
            activeChip: nil,
            entryHistory: FPLGameweekHistory(event: 1, points: 50, totalPoints: 50, rank: nil, overallRank: nil, bank: 0, value: 1_000, eventTransfers: 0, eventTransfersCost: 0, pointsOnBench: 14),
            picks: validPicks()
        ), gameweek: 1)
        return model
    }

    func testCompactPitchLensLabelsStayShortEnoughForNarrowPhones() {
        for mode in FPLSquadPitchView.PitchDisplayChipMode.allCases {
            XCTAssertFalse(mode.compactTitle.isEmpty)
            XCTAssertLessThanOrEqual(mode.compactTitle.count, 7)
        }
    }

#if DEBUG
    func testNormalAppDebugWorkspaceLaunchOverrideIsBounded() {
        XCTAssertEqual(
            FPLMainView.debugWorkspaceOverride(arguments: ["Fotty", "--fotty-fpl-workspace", "Squad"]),
            .squad
        )
        XCTAssertEqual(
            FPLMainView.debugWorkspaceOverride(arguments: ["Fotty", "--fotty-fpl-workspace=coach"]),
            .coach
        )
        XCTAssertEqual(
            FPLMainView.debugWorkspaceOverride(arguments: ["Fotty", "--fotty-fpl-workspace", "Plan"]),
            .gameweek
        )
        XCTAssertNil(
            FPLMainView.debugWorkspaceOverride(arguments: ["Fotty", "--fotty-fpl-workspace", "unknown"])
        )
    }
#endif

    func testCurrentLeagueStandingsContractDecodesPlayerNameAndPaging() throws {
        let json = #"""
        {
          "league": {
            "id": 218027,
            "name": "Test Mini-League",
            "created": "2026-07-25T01:45:08.370030Z",
            "league_type": "x"
          },
          "standings": {
            "has_next": true,
            "page": 1,
            "results": [
              {
                "entry": 3253567,
                "entry_name": "Intekma",
                "event_total": 95,
                "last_rank": 0,
                "player_name": "Test Manager",
                "rank": 1,
                "rank_sort": 1,
                "total": 95,
                "club_badge_src": null
              }
            ]
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(FPLLeagueStandingsResponse.self, from: json)

        XCTAssertEqual(response.league.leagueType, "x")
        XCTAssertTrue(response.standings.hasNext)
        XCTAssertEqual(response.standings.page, 1)
        XCTAssertEqual(response.standings.results.first?.id, 3_253_567)
        XCTAssertEqual(response.standings.results.first?.managerName, "Test Manager")
    }

    func testLeagueSummaryIdentifiesPrivateMiniLeague() throws {
        let json = #"""
        {
          "id": 218027,
          "name": "Test Mini-League",
          "league_type": "x",
          "entry_rank": 4,
          "entry_last_rank": 6
        }
        """#.data(using: .utf8)!

        let league = try JSONDecoder().decode(FPLLeagueSummary.self, from: json)

        XCTAssertTrue(league.isPrivateMiniLeague)
        XCTAssertEqual(league.entryRank, 4)
    }

    func testGW1TransfersAreOnlyUnlimitedBeforeTheDeadline() throws {
        let gameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-21T17:29:59Z"))
        let after = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-21T17:30:01Z"))

        XCTAssertTrue(FPLTransferRules.hasUnlimitedPreseasonTransfers(gameweek: gameweek, now: before))
        XCTAssertFalse(FPLTransferRules.hasUnlimitedPreseasonTransfers(gameweek: gameweek, now: after))
        XCTAssertEqual(
            FPLTransferRules.estimatedHitCost(
                transferCount: 4,
                assumedFreeTransfers: 1,
                gameweek: gameweek,
                now: before
            ),
            0
        )
        XCTAssertEqual(
            FPLTransferRules.estimatedHitCost(
                transferCount: 4,
                assumedFreeTransfers: 1,
                gameweek: gameweek,
                now: after
            ),
            12
        )
    }

    func testFreeTransferAssumptionIsBoundedAtFive() throws {
        let gameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        let after = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-22T12:00:00Z"))

        XCTAssertEqual(
            FPLTransferRules.estimatedHitCost(
                transferCount: 7,
                assumedFreeTransfers: 99,
                gameweek: gameweek,
                now: after
            ),
            8
        )
    }

    func testPickDecodesSellingAndPurchasePrices() throws {
        let json = #"""
        {
          "element": 101,
          "position": 1,
          "multiplier": 2,
          "is_captain": true,
          "is_vice_captain": false,
          "purchase_price": 75,
          "selling_price": 77
        }
        """#.data(using: .utf8)!

        let pick = try JSONDecoder().decode(FPLPick.self, from: json)

        XCTAssertEqual(pick.purchasePrice, 75)
        XCTAssertEqual(pick.sellingPrice, 77)
    }

    func testCurrentBootstrapRulesAndProjectionFieldsDecode() throws {
        let bootstrap = try decodeBootstrap()

        XCTAssertEqual(bootstrap.gameSettings?.squadSize, 15)
        XCTAssertEqual(bootstrap.gameSettings?.maximumFreeTransfers, 5)
        XCTAssertEqual(bootstrap.chips?.first?.startEvent, 2)
        XCTAssertEqual(bootstrap.elements.first?.officialExpectedPointsNext, 5.4)
        XCTAssertEqual(bootstrap.elements.first?.priceChangeProjections?.first?.likelihood, 3)
    }

    func testOfficialEventLiveContractDecodesPlayedBonusAndDefensiveContribution() throws {
        let json = #"""
        {
          "elements": [{
            "id": 101,
            "stats": {
              "minutes": 90, "goals_scored": 1, "assists": 0,
              "clean_sheets": 1, "goals_conceded": 0,
              "yellow_cards": 0, "red_cards": 0, "saves": 0,
              "bonus": 3, "bps": 41, "defensive_contribution": 11,
              "total_points": 12, "played": true
            },
            "explain": [{"fixture": 1, "stats": [{"identifier": "minutes", "points": 2, "value": 90}]}],
            "modified": false
          }]
        }
        """#.data(using: .utf8)!

        let live = try JSONDecoder().decode(FPLEventLiveResponse.self, from: json)

        XCTAssertEqual(live.elements.first?.stats.totalPoints, 12)
        XCTAssertEqual(live.elements.first?.stats.bonus, 3)
        XCTAssertEqual(live.elements.first?.stats.defensiveContribution, 11)
        XCTAssertEqual(live.elements.first?.stats.played, true)
    }

    func testLiveSummaryProjectsGoalkeeperAndFormationSafeOutfieldAutosubs() throws {
        let bootstrap = try decodeBootstrap()
        let gameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        let picks = FPLManagerPicks(
            activeChip: nil,
            entryHistory: FPLGameweekHistory(
                event: 1,
                points: 50,
                totalPoints: 50,
                rank: nil,
                overallRank: nil,
                bank: 0,
                value: 1_000,
                eventTransfers: 0,
                eventTransfersCost: 0,
                pointsOnBench: 14
            ),
            picks: validPicks()
        )
        let live = try decodeAutosubLive(
            noAppearance: [1, 3],
            points: [2: 7, 6: 7]
        )

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: gameweek,
            picks: picks,
            live: live,
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.officialCurrentPoints, 50)
        XCTAssertEqual(summary.publishedLineupPoints, 50)
        XCTAssertEqual(summary.totalPoints, 64)
        XCTAssertTrue(summary.pointsAreProjected)
        XCTAssertEqual(
            summary.projectedAutomaticSubs.map { [$0.elementIn, $0.elementOut] },
            [[2, 1], [6, 3]]
        )
        XCTAssertEqual(summary.rows.first(where: { $0.player.id == 2 })?.effectiveMultiplier, 1)
        XCTAssertEqual(summary.rows.first(where: { $0.player.id == 6 })?.effectiveMultiplier, 1)
    }

    func testIncompleteScoringSuppressesAllProjectionsAndPreservesOnlyPublishedPoints() async throws {
        let bootstrap = try decodeBootstrap()
        let gameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        let complete = try decodeAutosubLive(noAppearance: [1, 3], points: [2: 7, 6: 7])
        let history = FPLGameweekHistory(event: 1, points: 50, totalPoints: 50, rank: nil,
                                        overallRank: nil, bank: 0, value: 1_000, eventTransfers: 0,
                                        eventTransfersCost: 0, pointsOnBench: 14)
        let variants = [
            FPLEventLiveResponse(elements: complete.elements.filter { $0.id != 1 }),
            FPLEventLiveResponse(elements: complete.elements.filter { $0.id != 13 }),
            FPLEventLiveResponse(elements: complete.elements + [complete.elements[0]]),
            FPLEventLiveResponse(elements: [])
        ]
        for live in variants {
            for official in [history, nil] {
                let summary = FPLDecisionEngine.liveSquadSummary(
                    gameweek: gameweek, picks: FPLManagerPicks(activeChip: nil, entryHistory: official, picks: validPicks()),
                    live: live, players: bootstrap.elements, teams: bootstrap.teams, fixtures: try decodeCompletedFixtures()
                )
                XCTAssertFalse(summary.hasCompleteScoringData)
                XCTAssertEqual(summary.totalPoints, official?.points)
                XCTAssertNil(summary.publishedLineupPoints)
                XCTAssertFalse(summary.pointsAreProjected)
                XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
                XCTAssertNil(summary.projectedCaptainElementID)
                let response = await FPLAICoachService.deterministicResultIfApplicable(
                    userQuery: "What is my correct total after autosubs?", managerSummary: nil, currentGw: gameweek,
                    picks: nil, scores: [], freeTransfers: nil, live: summary, players: bootstrap.elements,
                    settings: nil, freshness: nil
                )
                XCTAssertEqual(response?.source, .rulesEngine)
                XCTAssertEqual(response?.confidence, "low")
                XCTAssertEqual(response?.officialDataStatus, "incomplete")
                XCTAssertEqual(response?.usage, .zero)
                XCTAssertFalse(response?.answer.contains("64 points") == true)
            }
        }
    }

    func testScoringWithDuplicatePicksOrMissingPlayerIsUnknownNotACrash() throws {
        let bootstrap = try decodeBootstrap()
        let live = try decodeAutosubLive(noAppearance: [1, 3], points: [2: 7, 6: 7])
        var duplicatePicks = validPicks()
        duplicatePicks[1] = duplicatePicks[0]
        for (picks, players) in [(duplicatePicks, bootstrap.elements), (validPicks(), Array(bootstrap.elements.dropFirst()))] {
            let summary = FPLDecisionEngine.liveSquadSummary(
                gameweek: try decodeGameweek(deadline: "2026-08-21T17:30:00Z"),
                picks: FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: picks),
                live: live, players: players, teams: bootstrap.teams, fixtures: try decodeCompletedFixtures()
            )
            XCTAssertFalse(summary.hasCompleteScoringData)
            XCTAssertNil(summary.totalPoints)
            XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
        }
    }

    func testScoringQuestionsWithoutLiveDataNeverFallThroughToTheModel() async {
        for query in ["How many gameweek points do I have?", "Should I trust the correct total after autosubs?"] {
            let response = await FPLAICoachService.deterministicResultIfApplicable(
                userQuery: query, managerSummary: nil, currentGw: nil, picks: nil, scores: [],
                freeTransfers: nil, live: nil, players: [], settings: nil, freshness: nil
            )
            XCTAssertEqual(response?.source, .rulesEngine)
            XCTAssertEqual(response?.usage, .zero)
            XCTAssertEqual(response?.officialDataStatus, "unavailable")
            XCTAssertEqual(response?.confidence, "low")
        }
        let advice = await FPLAICoachService.deterministicResultIfApplicable(
            userQuery: "Should I roll my transfer?", managerSummary: nil, currentGw: nil, picks: nil, scores: [],
            freeTransfers: nil, live: nil, players: [], settings: nil, freshness: nil
        )
        XCTAssertNil(advice, "Tactical advice must still be eligible for DeepSeek")
    }

    func testStaleScoringRemainsDeterministicAndFreshScoringKeepsTheCorrectTotal() async throws {
        let bootstrap = try decodeBootstrap()
        let gameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: gameweek, picks: FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: validPicks()),
            live: try decodeAutosubLive(noAppearance: [1, 3], points: [2: 7, 6: 7]),
            players: bootstrap.elements, teams: bootstrap.teams, fixtures: try decodeCompletedFixtures()
        )
        for age in [0.0, 600.0] {
            let response = await FPLAICoachService.deterministicResultIfApplicable(
                userQuery: "How many gameweek points do I have?", managerSummary: nil, currentGw: gameweek,
                picks: nil, scores: [], freeTransfers: nil, live: summary, players: bootstrap.elements,
                settings: nil, freshness: FPLResourceMetadata(source: .network, fetchedAt: Date().addingTimeInterval(-age), endpoint: "test")
            )
            XCTAssertEqual(response?.usage, .zero)
            XCTAssertEqual(response?.source, .rulesEngine)
            if age == 0 { XCTAssertTrue(response?.answer.contains("64 points") == true) }
            else {
                XCTAssertEqual(response?.officialDataStatus, "stale")
                XCTAssertFalse(response?.answer.contains("64 points") == true)
            }
        }
    }

    func testLiveSummarySkipsEarlierBenchMidfielderWhenDefenderIsRequired() throws {
        let bootstrap = try decodeBootstrap()
        let gameweek = try decodeGameweek(deadline: "2026-08-21T17:30:00Z")
        let published = validPicks()
        let reorderedBench = published.filter { $0.position <= 12 } + [
            FPLPick(element: 12, position: 13, multiplier: 0, isCaptain: false, isViceCaptain: false),
            FPLPick(element: 6, position: 14, multiplier: 0, isCaptain: false, isViceCaptain: false),
            FPLPick(element: 7, position: 15, multiplier: 0, isCaptain: false, isViceCaptain: false),
        ]
        let picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: reorderedBench)
        let live = try decodeAutosubLive(
            noAppearance: [3],
            points: [1: 5, 6: 7, 12: 8]
        )

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: gameweek,
            picks: picks,
            live: live,
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.projectedAutomaticSubs.count, 1)
        XCTAssertEqual(summary.projectedAutomaticSubs.first?.elementIn, 6)
        XCTAssertEqual(summary.projectedAutomaticSubs.first?.elementOut, 3)
        XCTAssertNil(summary.rows.first(where: { $0.player.id == 12 }))
    }

    func testLiveSummaryDoesNotOverrideDataCheckedOfficialTotal() throws {
        let bootstrap = try decodeBootstrap()
        let gameweek = try decodeGameweek(
            deadline: "2026-08-21T17:30:00Z",
            finished: true,
            dataChecked: true
        )
        let picks = FPLManagerPicks(
            activeChip: nil,
            entryHistory: FPLGameweekHistory(
                event: 1,
                points: 50,
                totalPoints: 50,
                rank: nil,
                overallRank: nil,
                bank: 0,
                value: 1_000,
                eventTransfers: 0,
                eventTransfersCost: 0,
                pointsOnBench: 14
            ),
            picks: validPicks()
        )

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: gameweek,
            picks: picks,
            live: try decodeAutosubLive(noAppearance: [1, 3], points: [2: 7, 6: 7]),
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.totalPoints, 50)
        XCTAssertFalse(summary.pointsAreProjected)
        XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
        XCTAssertNil(summary.rows.first(where: { $0.player.id == 2 }))
        XCTAssertNil(summary.rows.first(where: { $0.player.id == 6 }))
    }

    func testViceCaptainIsPromotedWhenCaptainIsConfirmedOutEvenWithoutBenchReplacement() throws {
        let bootstrap = try decodeBootstrap()
        let picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: validPicks())

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: try decodeGameweek(deadline: "2026-08-21T17:30:00Z"),
            picks: picks,
            live: try decodeAutosubLive(
                noAppearance: [2, 6, 7, 12, 13],
                points: [14: 5]
            ),
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.projectedCaptainElementID, 14)
        XCTAssertNil(summary.rows.first(where: { $0.pick.isCaptain }))
        XCTAssertEqual(summary.rows.first(where: { $0.player.id == 14 })?.effectiveMultiplier, 2)
        XCTAssertEqual(summary.officialCurrentPoints, 50)
        XCTAssertEqual(summary.totalPoints, 55)
        XCTAssertTrue(summary.pointsAreProjected)
        XCTAssertEqual(summary.projectionLabel, "projected captaincy")
        XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
    }

    func testBenchBoostScoresPublishedBenchWithoutCreatingAutosubs() throws {
        let bootstrap = try decodeBootstrap()
        let boostedPicks = validPicks().map { pick in
            FPLPick(
                element: pick.element,
                position: pick.position,
                multiplier: pick.isCaptain ? 2 : 1,
                isCaptain: pick.isCaptain,
                isViceCaptain: pick.isViceCaptain
            )
        }
        let picks = FPLManagerPicks(activeChip: "bboost", entryHistory: nil, picks: boostedPicks)

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: try decodeGameweek(deadline: "2026-08-21T17:30:00Z"),
            picks: picks,
            live: try decodeAutosubLive(noAppearance: [], points: [2: 4, 6: 6, 7: 7, 12: 8]),
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.rows.count, 15)
        XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
        XCTAssertFalse(summary.pointsAreProjected)
        XCTAssertEqual(summary.totalPoints, summary.publishedLineupPoints)
    }

    func testPublishedOfficialAutosubWinsOverFottyProjection() throws {
        let bootstrap = try decodeBootstrap()
        let officialPicks = validPicks().map { pick in
            FPLPick(
                element: pick.element,
                position: pick.position,
                multiplier: pick.element == 1 ? 0 : (pick.element == 2 ? 1 : pick.multiplier),
                isCaptain: pick.isCaptain,
                isViceCaptain: pick.isViceCaptain
            )
        }
        let officialSub = FPLAutomaticSub(entry: nil, elementIn: 2, elementOut: 1, event: 1)
        let picks = FPLManagerPicks(
            activeChip: nil,
            entryHistory: FPLGameweekHistory(
                event: 1, points: 62, totalPoints: 62, rank: nil, overallRank: nil,
                bank: 0, value: 1_000, eventTransfers: 0, eventTransfersCost: 0, pointsOnBench: 0
            ),
            picks: officialPicks,
            automaticSubs: [officialSub]
        )

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: try decodeGameweek(deadline: "2026-08-21T17:30:00Z"),
            picks: picks,
            live: try decodeAutosubLive(noAppearance: [1], points: [2: 7]),
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.totalPoints, 62)
        XCTAssertEqual(summary.automaticSubs, [officialSub])
        XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
        XCTAssertNil(summary.projectedCaptainElementID)
        XCTAssertFalse(summary.pointsAreProjected)
    }

    func testDoubleGameweekWaitsForEveryTeamFixtureBeforeProjectingAutosub() throws {
        let bootstrap = try decodeBootstrap()
        let picks = FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: validPicks())

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: try decodeGameweek(deadline: "2026-08-21T17:30:00Z"),
            picks: picks,
            live: try decodeAutosubLive(noAppearance: [1], points: [2: 7]),
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeFixtures(incompleteFixtureIDs: [3])
        )

        XCTAssertTrue(summary.projectedAutomaticSubs.isEmpty)
        XCTAssertFalse(summary.pointsAreProjected)
        XCTAssertEqual(summary.rows.first(where: { $0.player.id == 1 })?.effectiveMultiplier, 1)
    }

    func testTransferHitIsSubtractedFromDerivedLiveTotal() throws {
        let bootstrap = try decodeBootstrap()
        let history = FPLGameweekHistory(
            event: 1,
            points: nil,
            totalPoints: nil,
            rank: nil,
            overallRank: nil,
            bank: 0,
            value: 1_000,
            eventTransfers: 2,
            eventTransfersCost: 4,
            pointsOnBench: 0
        )
        let picks = FPLManagerPicks(activeChip: nil, entryHistory: history, picks: validPicks())

        let summary = FPLDecisionEngine.liveSquadSummary(
            gameweek: try decodeGameweek(deadline: "2026-08-21T17:30:00Z"),
            picks: picks,
            live: try decodeAutosubLive(noAppearance: [], points: [:]),
            players: bootstrap.elements,
            teams: bootstrap.teams,
            fixtures: try decodeCompletedFixtures()
        )

        XCTAssertEqual(summary.transferCost, 4)
        XCTAssertEqual(summary.totalPoints, 56)
    }

    func testGameweekPhaseUsesDeadlineKickoffAndConfirmedResult() throws {
        let gameweek = try decodeGameweek(deadline: "2026-08-22T12:00:00Z")
        let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-22T11:00:00Z"))
        let after = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-22T13:00:00Z"))
        let liveFixture = try decodeFixture(kickoff: "2026-08-22T12:30:00Z", finished: false)

        XCTAssertEqual(FPLGameweekPhase.resolve(gameweek: gameweek, fixtures: [liveFixture], now: before), .planning)
        XCTAssertEqual(FPLGameweekPhase.resolve(gameweek: gameweek, fixtures: [], now: after), .locked)
        XCTAssertEqual(FPLGameweekPhase.resolve(gameweek: gameweek, fixtures: [liveFixture], now: after), .live)

        let finished = try decodeGameweek(deadline: "2026-08-22T12:00:00Z", finished: true, dataChecked: true)
        XCTAssertEqual(FPLGameweekPhase.resolve(gameweek: finished, fixtures: [liveFixture], now: after), .review)
    }

    func testDeadlineReminderPlanOnlyContainsFutureTwentyFourAndTwoHourAlerts() throws {
        let gameweek = try decodeGameweek(deadline: "2026-08-25T12:00:00Z")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T12:00:00Z"))

        let reminders = FPLAlertScheduler.reminderPlan(for: gameweek, now: now)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertTrue(reminders.contains { $0.id.hasSuffix("86400") })
        XCTAssertTrue(reminders.contains { $0.id.hasSuffix("7200") })
    }

    func testFreeTransferEstimatePreservesBankThroughWildcardWeek() throws {
        let json = #"""
        {
          "current": [
            {"event": 1, "points": 60, "total_points": 60, "rank": 1, "rank_sort": 1, "overall_rank": 1, "bank": 0, "value": 1000, "event_transfers": 0, "event_transfers_cost": 0, "points_on_bench": 2},
            {"event": 2, "points": 55, "total_points": 115, "rank": 1, "rank_sort": 1, "overall_rank": 1, "bank": 0, "value": 1000, "event_transfers": 0, "event_transfers_cost": 0, "points_on_bench": 3},
            {"event": 3, "points": 70, "total_points": 185, "rank": 1, "rank_sort": 1, "overall_rank": 1, "bank": 0, "value": 1000, "event_transfers": 8, "event_transfers_cost": 0, "points_on_bench": 1}
          ],
          "past": [],
          "chips": [{"name": "wildcard", "time": "2026-09-01T00:00:00Z", "event": 3}]
        }
        """#.data(using: .utf8)!
        let history = try JSONDecoder().decode(FPLManagerHistoryResponse.self, from: json)

        let estimate = FPLFreeTransferEstimator.estimate(history: history, targetGameweek: 4)

        XCTAssertEqual(estimate.count, 2)
        XCTAssertFalse(estimate.isExact)
    }

    func testSquadValidatorAndOptimizerReturnLegalFifteenPlayerDrafts() throws {
        let bootstrap = try decodeBootstrap()
        let picks = validPicks()
        let report = FPLSquadValidator.validate(
            picks: picks,
            players: bootstrap.elements,
            elementTypes: bootstrap.elementTypes,
            gameSettings: bootstrap.gameSettings,
            budgetLimit: 1_000
        )
        XCTAssertTrue(report.isValid, report.issues.map(\.message).joined(separator: " | "))
        XCTAssertEqual(report.formation, "3-4-3")

        let teams = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let scores = bootstrap.elements.compactMap { player -> PlayerScore? in
            guard let team = teams[player.team] else { return nil }
            return PlayerScore(
                player: player,
                team: team,
                compositeScore: Double(player.id),
                formScore: 50,
                fixtureScore: 50,
                xGIScore: 50,
                ictScore: 50,
                valueScore: 50,
                minutesScore: 100,
                ownershipScore: 0,
                xGRegressionState: .expected,
                upcomingFixtures: [],
                priceChangeRisk: .stable,
                availabilityRisk: .available
            )
        }
        let optimized = FPLSquadOptimizer.generate(
            profiles: [.balanced],
            scores: scores,
            fixtures: [],
            elementTypes: bootstrap.elementTypes,
            settings: bootstrap.gameSettings,
            startGameweek: 1,
            horizon: 5,
            budget: 1_000
        )
        XCTAssertEqual(optimized.first?.picks.count, 15)
        XCTAssertEqual(optimized.first?.validation.isValid, true)
    }

    @MainActor
    func testFPLMatchdayContextPersistsAndFindsSquadInvolvementWithoutNetworkWork() throws {
        let suiteName = "FottyTests.FPLMatchdayContext"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let bootstrap = try decodeBootstrap()
        let picks = validPicks()
        let now = Date()

        let store = FPLMatchdayContextStore(
            defaults: defaults,
            storageKey: "context",
            maximumSnapshotAge: 3600
        )
        store.update(
            managerID: 42,
            gameweek: 1,
            phase: .planning,
            picks: picks,
            players: bootstrap.elements,
            teams: bootstrap.teams,
            now: now
        )

        let involvement = try XCTUnwrap(store.involvement(homeTeam: "Team 3 FC", awayTeam: "Team 4"))
        XCTAssertEqual(involvement.starterCount, 6)
        XCTAssertEqual(involvement.benchCount, 0)
        XCTAssertEqual(involvement.captainName, "P13")
        XCTAssertTrue(involvement.compactLabel.contains("Captain P13"))
        XCTAssertNil(store.involvement(homeTeam: "Unrelated FC", awayTeam: "Another Club"))

        let reloaded = FPLMatchdayContextStore(
            defaults: defaults,
            storageKey: "context",
            maximumSnapshotAge: 3600
        )
        XCTAssertEqual(reloaded.snapshot?.managerID, 42)
        XCTAssertNotNil(reloaded.involvement(homeTeam: "Team 3", awayTeam: "Team 4 AFC"))

        reloaded.clear(managerID: 42)
        XCTAssertNil(reloaded.snapshot)

        store.update(
            managerID: 42,
            gameweek: 1,
            phase: .planning,
            picks: picks,
            players: bootstrap.elements,
            teams: bootstrap.teams,
            now: now.addingTimeInterval(-7_200)
        )
        let expired = FPLMatchdayContextStore(
            defaults: defaults,
            storageKey: "context",
            maximumSnapshotAge: 3600
        )
        XCTAssertNil(expired.snapshot)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCommandCenterMetricsAdaptToPlanningPhase() throws {
        let gameweek = try decodeGameweek(deadline: "2026-08-25T12:00:00Z")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-24T09:30:00Z"))
        let state = FPLDecisionEngine.commandCenter(
            phase: .planning,
            gameweek: gameweek,
            picks: FPLManagerPicks(activeChip: nil, entryHistory: nil, picks: validPicks()),
            scores: [],
            validation: nil,
            freeTransfers: FPLFreeTransferEstimate(
                count: 2,
                targetGameweek: 1,
                explanation: "Test estimate",
                isExact: false
            ),
            live: nil,
            history: nil,
            now: now
        )

        XCTAssertEqual(state.phase, .planning)
        XCTAssertEqual(state.metrics.first(where: { $0.label == "DEADLINE" })?.value, "1d 2h")
        XCTAssertEqual(state.metrics.first(where: { $0.label == "EST. FT" })?.value, "2")
        XCTAssertTrue(state.actions.contains { $0.destination == .captain })
    }

    @MainActor
    func testDecisionJournalPersistsUpdatesAndIsolatesManagers() throws {
        let suiteName = "FottyTests.FPLDecisionJournal"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = FPLDecisionJournalEntry(
            id: "captain-gw1",
            managerID: 42,
            gameweek: 1,
            kind: .captain,
            title: "Captain P13",
            rationale: "Best modeled route to points.",
            expectedOutcome: "Outscore the vice-captain.",
            source: "Smart Coach",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            FPLDecisionJournalStore.upsert(initial, managerID: 42, defaults: defaults),
            [initial]
        )
        XCTAssertTrue(FPLDecisionJournalStore.load(managerID: 7, defaults: defaults).isEmpty)

        var reviewed = initial
        reviewed.outcome = .worked
        reviewed.outcomeNote = "The reasoning held even though the margin was small."
        reviewed.updatedAt = Date(timeIntervalSince1970: 200)
        let loaded = FPLDecisionJournalStore.upsert(reviewed, managerID: 42, defaults: defaults)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.outcome, .worked)
        XCTAssertEqual(loaded.first?.outcomeNote, reviewed.outcomeNote)
        XCTAssertTrue(FPLDecisionJournalStore.remove(id: reviewed.id, managerID: 42, defaults: defaults).isEmpty)
    }

    func testLegacyCoachHistoryDecodesWithoutStructuredCard() throws {
        let json = #"""
        {
          "id": "old-message",
          "sender": "coach",
          "text": "Hold the transfer.",
          "date": 100,
          "gameweek": 1,
          "tag": "strategy"
        }
        """#.data(using: .utf8)!

        let message = try JSONDecoder().decode(AICoachMessage.self, from: json)

        XCTAssertEqual(message.text, "Hold the transfer.")
        XCTAssertNil(message.coachCard)
    }

    func testPlannerRollRouteAlwaysExplainsDownsideAndDeadlineChecks() {
        let routes = FPLPlannerEngine.routes(
            recommendations: [],
            fixtures: [],
            startGameweek: 1,
            horizon: 5,
            freeTransfers: nil,
            gameweek: nil
        )

        XCTAssertEqual(routes.map(\.name), ["Roll"])
        XCTAssertFalse(routes[0].downside.isEmpty)
        XCTAssertGreaterThanOrEqual(routes[0].verificationItems.count, 2)
        XCTAssertEqual(routes[0].weeklyProjectedGain.count, 5)
        XCTAssertEqual(routes[0].modelVersion, FPLProjectionEngine.modelVersion)
    }

    @MainActor
    func testPlanningScenariosPersistByManagerAndRemainBounded() throws {
        let suiteName = "FottyTests.FPLPlanningScenarios"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let route = FPLDraftRoute(
            name: "Roll",
            transfers: [],
            hitCost: 0,
            projectedGain: 0,
            weeklyProjectedGain: [2: 0, 3: 0],
            breakEvenGameweek: nil,
            modelVersion: FPLProjectionEngine.modelVersion,
            explanation: "Keep flexibility.",
            downside: "A price may move.",
            verificationItems: ["Verify free transfers."]
        )

        for index in 0..<14 {
            _ = FPLScenarioStore.upsert(
                FPLSavedScenario(
                    id: "scenario-\(index)",
                    managerID: 42,
                    gameweek: 2,
                    name: "Plan \(index)",
                    route: route,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                ),
                defaults: defaults
            )
        }

        let saved = FPLScenarioStore.load(managerID: 42, defaults: defaults)
        XCTAssertEqual(saved.count, 12)
        XCTAssertEqual(saved.first?.name, "Plan 13")
        XCTAssertEqual(saved.first?.weeklyProjectedGain, [2: 0, 3: 0])
        XCTAssertTrue(FPLScenarioStore.load(managerID: 7, defaults: defaults).isEmpty)
    }

    func testProjectionExposesExpectedMinutesConfidenceSourceAndVersion() throws {
        let player = try XCTUnwrap(decodeBootstrap().elements.first)
        let fixture = try decodeFixture(kickoff: "2026-08-22T12:00:00Z", finished: false)

        let projection = FPLProjectionEngine.project(
            player: player,
            fixtures: [fixture],
            startGameweek: 1,
            horizon: 1
        )

        XCTAssertEqual(projection.expectedMinutes[1], 90)
        XCTAssertEqual(projection.confidence, .medium)
        XCTAssertEqual(projection.sourceByGameweek[1], .officialBlend)
        XCTAssertEqual(projection.modelVersion, "fotty-heuristic-2.0.0")
        XCTAssertTrue(projection.assumptions.contains { $0.contains("Expected minutes") })
    }

    func testProjectionKeepsBlankAtZeroAndCountsBothDoubleGameweekFixtures() throws {
        let player = try XCTUnwrap(decodeBootstrap().elements.first)
        let first = try decodeFixture(
            kickoff: "2026-08-29T12:00:00Z",
            finished: false,
            id: 21,
            event: 2
        )
        let second = try decodeFixture(
            kickoff: "2026-09-01T19:00:00Z",
            finished: false,
            id: 22,
            event: 2
        )

        let projection = FPLProjectionEngine.project(
            player: player,
            fixtures: [first, second],
            startGameweek: 1,
            horizon: 2
        )

        XCTAssertEqual(projection.gameweekPoints[1], 0)
        XCTAssertEqual(projection.expectedMinutes[1], 0)
        XCTAssertEqual(projection.expectedMinutes[2], 180)
        XCTAssertGreaterThan(projection.gameweekPoints[2] ?? 0, 0)
        XCTAssertEqual(projection.sourceByGameweek[2], .fottyEstimate)
    }

    func testDirectRulesQuestionUsesNoModelTokens() async throws {
        let settings = try decodeBootstrap().gameSettings

        let result = await FPLAICoachService.deterministicResultIfApplicable(
            userQuery: "What is the squad size and players per club limit?",
            managerSummary: nil,
            currentGw: nil,
            picks: nil,
            scores: [],
            freeTransfers: nil,
            live: nil,
            players: [],
            settings: settings,
            freshness: nil
        )

        XCTAssertEqual(result?.source, .rulesEngine)
        XCTAssertEqual(result?.usage, .zero)
        XCTAssertTrue(result?.answer.contains("15-player squad") == true)
        XCTAssertTrue(result?.answer.contains("3 players") == true)
    }

    func testRivalRaceUsesPublishedStandingAndOfficialLiveSnapshot() throws {
        let standingsJSON = #"""
        {
          "league": {"id": 1, "name": "Race", "created": "2026-08-01T00:00:00Z", "league_type": "x"},
          "standings": {
            "has_next": false, "page": 1,
            "results": [
              {"entry": 42, "entry_name": "Mine", "event_total": 55, "last_rank": 3, "player_name": "Me", "rank": 2, "rank_sort": 2, "total": 110},
              {"entry": 77, "entry_name": "Rival", "event_total": 62, "last_rank": 2, "player_name": "Them", "rank": 1, "rank_sort": 1, "total": 121}
            ]
          }
        }
        """#.data(using: .utf8)!
        let standings = try JSONDecoder().decode(FPLLeagueStandingsResponse.self, from: standingsJSON)
        let liveJSON = #"""
        {"elements": [
          {"id": 13, "stats": {"minutes": 90, "goals_scored": 1, "assists": 0, "clean_sheets": 0, "goals_conceded": 1, "yellow_cards": 0, "red_cards": 0, "saves": 0, "bonus": 3, "bps": 35, "defensive_contribution": 0, "total_points": 9, "played": true}, "explain": [], "modified": false}
        ]}
        """#.data(using: .utf8)!
        let live = try JSONDecoder().decode(FPLEventLiveResponse.self, from: liveJSON)
        let bootstrap = try decodeBootstrap()
        let teams = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let scores = bootstrap.elements.compactMap { player -> PlayerScore? in
            guard let team = teams[player.team] else { return nil }
            return PlayerScore(
                player: player,
                team: team,
                compositeScore: 50,
                formScore: 50,
                fixtureScore: 50,
                xGIScore: 50,
                ictScore: 50,
                valueScore: 50,
                minutesScore: 100,
                ownershipScore: 0,
                xGRegressionState: .expected,
                upcomingFixtures: [],
                priceChangeRisk: .stable,
                availabilityRisk: .available
            )
        }
        let picks = validPicks()

        let result = FPLAdvisorEngine.analyzeRivalGap(
            myEntry: try XCTUnwrap(standings.standings.results.first),
            rivalEntry: try XCTUnwrap(standings.standings.results.last),
            myPicks: picks,
            rivalPicks: picks,
            allScores: scores,
            gameweek: 1,
            phase: .live,
            eventLive: live,
            fixtures: []
        )

        XCTAssertEqual(result.pointDeficit, 11)
        XCTAssertEqual(result.gameweekDeficit, 7)
        XCTAssertEqual(result.myCaptainName, "P13")
        XCTAssertTrue(result.hasOfficialLiveSnapshot)
        XCTAssertEqual(result.sharedPlayers.count, 15)
    }

    private func decodeGameweek(
        deadline: String,
        finished: Bool = false,
        dataChecked: Bool = false,
        id: Int = 1
    ) throws -> FPLGameweek {
        let json = #"""
        {
          "id": \#(id),
          "name": "Gameweek \#(id)",
          "deadline_time": "\#(deadline)",
          "deadline_time_epoch": 1787333400,
          "finished": \#(finished),
          "data_checked": \#(dataChecked),
          "is_previous": false,
          "is_current": true,
          "is_next": false
        }
        """#.data(using: .utf8)!
        return try JSONDecoder().decode(FPLGameweek.self, from: json)
    }

    private func decodeAutosubLive(
        noAppearance: Set<Int>,
        points overrides: [Int: Int]
    ) throws -> FPLEventLiveResponse {
        let starters = Set(validPicks().filter { $0.position <= 11 }.map(\.element))
        let elements: [[String: Any]] = (1...15).map { id in
            let appeared = !noAppearance.contains(id) && (starters.contains(id) || overrides[id] != nil)
            let points = overrides[id] ?? (starters.contains(id) && appeared ? 5 : 0)
            return [
                "id": id,
                "stats": [
                    "minutes": appeared ? 90 : 0,
                    "goals_scored": 0,
                    "assists": 0,
                    "clean_sheets": 0,
                    "goals_conceded": 0,
                    "yellow_cards": 0,
                    "red_cards": 0,
                    "saves": 0,
                    "bonus": 0,
                    "bps": 0,
                    "defensive_contribution": 0,
                    "total_points": points,
                    "played": appeared,
                ],
                "explain": [],
                "modified": false,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["elements": elements])
        return try JSONDecoder().decode(FPLEventLiveResponse.self, from: data)
    }

    private func decodeCompletedFixtures() throws -> [FPLFixture] {
        try decodeFixtures()
    }

    private func decodeFixtures(incompleteFixtureIDs: Set<Int> = []) throws -> [FPLFixture] {
        let rows: [[String: Any]] = [
            ["id": 1, "event": 1, "team_h": 1, "team_a": 2],
            ["id": 2, "event": 1, "team_h": 3, "team_a": 4],
            ["id": 3, "event": 1, "team_h": 5, "team_a": 1],
        ].map { base in
            var fixture = base
            let fixtureID = base["id"] as? Int ?? 0
            let isIncomplete = incompleteFixtureIDs.contains(fixtureID)
            fixture["finished"] = false
            fixture["started"] = true
            fixture["finished_provisional"] = !isIncomplete
            fixture["minutes"] = isIncomplete ? 45 : 90
            fixture["kickoff_time"] = "2026-08-22T12:00:00Z"
            fixture["team_h_score"] = 1
            fixture["team_a_score"] = 0
            fixture["team_h_difficulty"] = 3
            fixture["team_a_difficulty"] = 3
            return fixture
        }
        let data = try JSONSerialization.data(withJSONObject: rows)
        return try JSONDecoder().decode([FPLFixture].self, from: data)
    }

    private func decodeFixture(
        kickoff: String,
        finished: Bool,
        id: Int = 1,
        event: Int = 1
    ) throws -> FPLFixture {
        let json = #"""
        {
          "id": \#(id), "event": \#(event), "finished": \#(finished), "kickoff_time": "\#(kickoff)",
          "team_h": 1, "team_a": 2, "team_h_score": null, "team_a_score": null,
          "team_h_difficulty": 2, "team_a_difficulty": 4
        }
        """#.data(using: .utf8)!
        return try JSONDecoder().decode(FPLFixture.self, from: json)
    }

    private func decodeBootstrap(extraDefender: Bool = false) throws -> FPLBootstrapResponse {
        let positions = [1, 1] + Array(repeating: 2, count: 5) + Array(repeating: 3, count: 5) + Array(repeating: 4, count: 3)
        var players = [[String: Any]]()
        for (offset, position) in positions.enumerated() {
            let id = offset + 1
            var player: [String: Any] = [
                "id": id, "web_name": "P\(id)", "first_name": "Player", "second_name": "\(id)",
                "team": (offset % 5) + 1, "team_code": (offset % 5) + 1, "element_type": position,
                "now_cost": 50, "cost_change_event": 0, "cost_change_event_fall": 0,
                "selected_by_percent": "10.0", "form": "4.0", "points_per_game": "4.0",
                "total_points": 10, "event_points": 0, "minutes": 180, "goals_scored": 0,
                "assists": 0, "clean_sheets": 0, "goals_conceded": 0, "yellow_cards": 0,
                "red_cards": 0, "saves": 0, "bonus": 0, "bps": 0, "influence": "0.0",
                "creativity": "0.0", "threat": "0.0", "ict_index": "0.0", "starts": 2,
                "transfers_in_event": 0, "transfers_out_event": 0, "status": "a", "news": "",
                "can_select": true
            ]
            if id == 1 {
                player["ep_next"] = "5.4"
                player["price_change_projections"] = [["offset": 0, "projected_percent": "78.2", "likelihood": 3]]
            }
            players.append(player)
        }
        if extraDefender {
            var replacement = players[2]
            replacement["id"] = 16
            replacement["web_name"] = "Replacement defender"
            players.append(replacement)
        }
        let teams: [[String: Any]] = (1...5).map {
            ["id": $0, "name": "Team \($0)", "short_name": "T\($0)", "code": $0]
        }
        let types: [[String: Any]] = [
            ["id": 1, "singular_name": "Goalkeeper", "singular_name_short": "GKP", "plural_name": "Goalkeepers", "plural_name_short": "GKP", "squad_select": 2, "squad_min_play": 1, "squad_max_play": 1],
            ["id": 2, "singular_name": "Defender", "singular_name_short": "DEF", "plural_name": "Defenders", "plural_name_short": "DEF", "squad_select": 5, "squad_min_play": 3, "squad_max_play": 5],
            ["id": 3, "singular_name": "Midfielder", "singular_name_short": "MID", "plural_name": "Midfielders", "plural_name_short": "MID", "squad_select": 5, "squad_min_play": 2, "squad_max_play": 5],
            ["id": 4, "singular_name": "Forward", "singular_name_short": "FWD", "plural_name": "Forwards", "plural_name_short": "FWD", "squad_select": 3, "squad_min_play": 1, "squad_max_play": 3]
        ]
        let root: [String: Any] = [
            "events": [], "elements": players, "teams": teams, "element_types": types, "total_players": 15,
            "game_settings": ["squad_squadplay": 11, "squad_squadsize": 15, "squad_team_limit": 3, "squad_total_spend": 1000, "max_extra_free_transfers": 4],
            "chips": [["id": 1, "name": "wildcard", "number": 1, "start_event": 2, "stop_event": 19, "chip_type": "transfer"]]
        ]
        return try JSONDecoder().decode(FPLBootstrapResponse.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func validPicks() -> [FPLPick] {
        let ordered = [1, 3, 4, 5, 8, 9, 10, 11, 13, 14, 15, 2, 6, 7, 12]
        return ordered.enumerated().map { index, id in
            FPLPick(
                element: id,
                position: index + 1,
                multiplier: id == 13 ? 2 : (index < 11 ? 1 : 0),
                isCaptain: id == 13,
                isViceCaptain: id == 14,
                elementType: nil
            )
        }
    }
}
