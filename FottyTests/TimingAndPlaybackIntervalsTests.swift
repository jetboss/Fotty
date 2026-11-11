import XCTest
import WebKit
@testable import Fotty

@MainActor
final class TimingAndPlaybackIntervalsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testCausalEvidenceBudgetDeduplicatesTransportAndCapsEachAttempt() {
        var budget = FottyPlaybackDiagnosticBudget()
        let identity = FottyPlaybackDiagnosticBudget.Identity(sourceID: UUID(), requestID: UUID())
        XCTAssertTrue(budget.admit(identity: identity, phase: .webTransport, purpose: .webPlayback,
                                   result: .paused, operationID: UUID()))
        XCTAssertFalse(budget.admit(identity: identity, phase: .webTransport, purpose: .webPlayback,
                                    result: .paused, operationID: UUID()))
        XCTAssertTrue(budget.admit(identity: identity, phase: .webTransport, purpose: .webPlayback,
                                   result: .playing, operationID: UUID()))
        let operation = UUID()
        XCTAssertTrue(budget.admit(identity: identity, phase: .candidateObserved, purpose: .nativeHandoff,
                                   result: .began, operationID: operation))
        XCTAssertFalse(budget.admit(identity: identity, phase: .candidateObserved, purpose: .nativeHandoff,
                                    result: .began, operationID: operation))
        for _ in 0..<100 {
            _ = budget.admit(identity: identity, phase: .audioPreparationRequested, purpose: .nativeStart,
                             result: .began, operationID: UUID())
        }
        XCTAssertEqual(budget.emittedCount, FottyPlaybackDiagnosticBudget.maximumRecordsPerAttempt)
        XCTAssertTrue(budget.admit(identity: .init(sourceID: identity.sourceID, requestID: UUID()),
                                   phase: .webTransport, purpose: .webPlayback, result: .paused, operationID: UUID()))
        XCTAssertEqual(budget.emittedCount, 1)
    }

    func testCausalEvidenceUsesStrictTypedPrivacyFields() throws {
        let domain = "FottyCausalPrivacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = FottyQualityStore(defaults: defaults, now: { self.date })
        let job = UUID()
        store.record(category: .playback, name: "playback_causal_evidence", outcome: .info, details: [
            "diagnostic_phase": "audio_activation_requested", "diagnostic_purpose": "platform_activation",
            "diagnostic_result": "began", "handoff_phase": "audio_preparation", "audio_job_id": job.uuidString,
            "diagnostic_operation_id": UUID().uuidString, "audio_enabled": "false", "playback_intent": "true",
            "candidate_count": "12", "url": "https://example.invalid/private", "cookie": "private", "fixture": "Private fixture"
        ])
        store.record(category: .playback, name: "playback_causal_evidence", outcome: .info, details: [
            "diagnostic_phase": "arbitrary", "diagnostic_purpose": "arbitrary", "diagnostic_result": "arbitrary",
            "handoff_phase": "arbitrary", "audio_job_id": "arbitrary", "diagnostic_operation_id": "arbitrary",
            "audio_enabled": "maybe", "playback_intent": "maybe", "candidate_count": "13"
        ])
        let records = store.records()
        XCTAssertEqual(records.count, 2)
        let valid = try XCTUnwrap(records.first { $0.details["audio_job_id"] == job.uuidString })
        XCTAssertEqual(valid.details["candidate_count"], "12")
        XCTAssertNil(valid.details["url"])
        XCTAssertNil(valid.details["cookie"])
        XCTAssertNil(valid.details["fixture"])
        XCTAssertEqual(records.filter { $0.details.isEmpty }.count, 1)
        XCTAssertTrue(records.allSatisfy { $0.outcome == .info })
    }

    func testEmptySearchDoesNotScheduleOrNormalize() async {
        var sleeps = 0, normalizations = 0
        let timing = FottyAsyncTiming(monotonicNow: { 0 }, sleep: { _ in sleeps += 1 })
        let discovery = catalog(count: 32)
        for query in ["", " ", "\n\t"] {
            let result = await HomeSportsSearch.prepareForQuery(in: discovery, query: query,
                leagueName: { _ in normalizations += 1; return "Premier League" }, timing: timing)
            XCTAssertNil(result)
        }
        XCTAssertEqual(sleeps, 0)
        XCTAssertEqual(normalizations, 0)
    }

    func testSearchRetainsOneMillisecondSixteenRowCheckpointsAndExactResults() async throws {
        var delays: [Duration] = []
        let timing = FottyAsyncTiming(monotonicNow: { 0 }, sleep: { delays.append($0) })
        let discovery = catalog(count: 33)
        XCTAssertEqual(discovery.items.count, 33, "Batch coverage requires distinct accepted fixture identities")
        let index = await HomeSportsSearch.prepareForQuery(in: discovery, query: "Chelsea", timing: timing)
        let prepared = try XCTUnwrap(index)
        XCTAssertEqual(delays, Array(repeating: .milliseconds(1), count: 3),
                       "One entry checkpoint, then completed sixteen-row batches; no search debounce")
        XCTAssertEqual(prepared.results(query: "Chelsea").map(\.id),
                       HomeSportsSearch.prepare(in: discovery).results(query: "Chelsea").map(\.id))
    }

    func testOldQueryCannotPublishAfterNonCooperativeWaitAndLatestQueryWorks() async throws {
        let clock = ManualOwnerClock()
        defer { clock.releaseAll() }
        var query = "Chelsea"
        let requested = query
        let task = Task { await HomeSportsSearch.prepareForQuery(in: catalog(count: 4), query: requested,
            isCurrent: { query == requested }, timing: clock.timing) }
        try await waitFor { clock.pendingCount == 1 }
        query = "Brighton"
        clock.advance(by: 0.001)
        let stale = await task.value
        XCTAssertNil(stale)
        let latestCatalog = catalog(count: 4)
        XCTAssertEqual(latestCatalog.items.count, 4, "Latest-query coverage requires four distinct fixture identities")
        let latest = await HomeSportsSearch.prepareForQuery(in: latestCatalog, query: query,
            isCurrent: { query == "Brighton" }, timing: .init(monotonicNow: { 0 }, sleep: { _ in }))
        XCTAssertEqual(try XCTUnwrap(latest).results(query: query).count, 4)
    }

    func testCurrentContextRevocationStopsSearchAtCheckpoint() async throws {
        let clock = ManualOwnerClock()
        defer { clock.releaseAll() }
        var current = true
        let task = Task { await HomeSportsSearch.prepareForQuery(in: catalog(count: 32), query: "Chelsea",
            isCurrent: { current }, timing: clock.timing) }
        try await waitFor { clock.pendingCount == 1 }
        current = false
        clock.advance(by: 0.001)
        let result = await task.value
        XCTAssertNil(result, "Tests the producer's owner fence, not five end-to-end SwiftUI journeys")
    }

    func testCancelledSearchStopsAfterInjectedWaitEvenIfWaitIgnoresCancellation() async throws {
        let clock = ManualOwnerClock()
        defer { clock.releaseAll() }
        var normalized = 0
        let task = Task { await HomeSportsSearch.prepareForQuery(in: catalog(count: 32), query: "Chelsea",
            leagueName: { _ in normalized += 1; return nil }, timing: clock.timing) }
        try await waitFor { clock.pendingCount == 1 }
        task.cancel()
        clock.advance(by: 0.001)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(normalized, 0)
    }

    func testNativeAndWebControlsKeepTheirExistingExactDeadlines() async throws {
        for web in [false, true] {
            let clock = ManualOwnerClock()
            let model = try makeModel(web: web, clock: clock)
            defer { model.cleanup(); clock.releaseAll() }
            model.scheduleAutoHide()
            let task = try XCTUnwrap(model.hideTask)
            try await waitFor { clock.pendingCount == 1 }
            let delay = web ? LivePlaybackPolicy.webControlAutoHideSeconds : 10
            clock.advance(by: delay - 0.001)
            XCTAssertTrue(model.showControls)
            XCTAssertEqual(clock.pendingCount, 1)
            clock.advance(by: 0.001)
            await task.value
            XCTAssertFalse(model.showControls)
        }
    }

    func testAssistiveSinglePlaybackKeepsControlsVisibleWithoutStartingHideTimer() throws {
        for web in [false, true] {
            let clock = ManualOwnerClock()
            let model = try makeModel(web: web, clock: clock, controlsNeedAccessibilityVisibility: { true })
            defer { model.cleanup(); clock.releaseAll() }
            model.showControls = false
            let source = model.activeSource?.id, attempt = model.loadRequestID
            model.scheduleAutoHide()
            XCTAssertTrue(model.showControls)
            XCTAssertNil(model.hideTask)
            XCTAssertEqual(clock.pendingCount, 0)
            XCTAssertEqual(model.activeSource?.id, source)
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertEqual(model.playbackState, .playing(web ? .webEmbed : .native))
        }
    }

    func testHealthySingleNativeWatchdogSamplesAllowControlsToHide() async throws {
        let clock = ManualOwnerClock()
        let model = try makeModel(web: false, clock: clock)
        defer { model.cleanup(); clock.releaseAll() }
        model.scheduleAutoHide()
        let pending = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        for seconds in [2.0, 4.0, 6.0, 8.0] {
            model.observeSingleNativeWatchdogProgress(seconds)
            XCTAssertEqual(model.playbackStagnationTicks, 0)
        }
        clock.advance(by: 10)
        await pending.value
        XCTAssertFalse(model.showControls, "Healthy watchdog samples must not veto auto-hide")
    }

    func testRecoveredProgressRearmsAnExpiredHideWaitWithoutHidingDuringAStall() async throws {
        let clock = ManualOwnerClock()
        let model = try makeModel(web: false, clock: clock)
        defer { model.cleanup(); clock.releaseAll() }
        model.observeSingleNativeWatchdogProgress(10)
        model.scheduleAutoHide()
        let old = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        model.observeSingleNativeWatchdogProgress(10)
        XCTAssertEqual(model.playbackStagnationTicks, 1)
        model.observeSingleNativeWatchdogProgress(10)
        XCTAssertEqual(model.playbackStagnationTicks, 2, "A frozen Playing clock still reaches the recovery threshold")
        clock.advance(by: 10)
        await old.value
        XCTAssertTrue(model.showControls)
        model.observeSingleNativeWatchdogProgress(12)
        let recovered = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        clock.advance(by: 10)
        await recovered.value
        XCTAssertFalse(model.showControls)
    }

    func testClosingSourcePickerRearmsControlsWithoutChangingTheAttempt() async throws {
        let clock = ManualOwnerClock()
        let model = try makeModel(web: false, clock: clock)
        defer { model.cleanup(); clock.releaseAll() }
        let source = model.activeSource?.id, attempt = model.loadRequestID
        model.showSourceSelector = true
        model.scheduleAutoHide()
        let old = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        clock.advance(by: 10)
        await old.value
        XCTAssertTrue(model.showControls)
        model.showSourceSelector = false
        let resumed = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        clock.advance(by: 10)
        await resumed.value
        XCTAssertFalse(model.showControls)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, attempt)
    }

    func testConnectingSingleLeavesLoadingContentCenterFreeAndPreservesTopBarActions() throws {
        let clock = ManualOwnerClock()
        let model = try makeModel(web: false, clock: clock)
        defer { model.cleanup(); clock.releaseAll() }
        let overlay = PlaybackControlsOverlay(viewModel: model, showSourceButton: true, showsTopBar: true, dismiss: {})
        XCTAssertTrue(overlay.showsCenterTransport)
        model.transition(to: .connecting(.native))
        XCTAssertFalse(overlay.showsCenterTransport)
        XCTAssertTrue(overlay.showSourceButton)
        XCTAssertTrue(overlay.showsTopBar)
        model.transition(to: .paused(.native))
        XCTAssertTrue(overlay.showsCenterTransport, "A deliberate Pause still retains its actual Play control")
    }

    func testHomeEmptyRecoveryNamesOnlyTheFilterItActuallyRemoves() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Text(\"Remove interests filter\")"))
        XCTAssertFalse(source.contains("Show everything on Home"))
    }

    func testAssistiveStateAppearingDuringHideWaitCannotRemoveControls() async throws {
        let clock = ManualOwnerClock()
        var accessible = false
        let model = try makeModel(web: true, clock: clock, controlsNeedAccessibilityVisibility: { accessible })
        defer { model.cleanup(); clock.releaseAll() }
        model.scheduleAutoHide()
        let pending = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        accessible = true
        clock.advance(by: LivePlaybackPolicy.webControlAutoHideSeconds)
        await pending.value
        XCTAssertTrue(model.showControls, "The post-wait guard observes the current assistive setting")
        model.showControls = false
        model.refreshPlaybackControlsAccessibility()
        XCTAssertTrue(model.showControls, "The status notification also reveals already hidden controls")
        XCTAssertNil(model.hideTask)
    }

    func testDisablingAssistiveControlRetentionRestoresExistingTimerAndPauseFence() async throws {
        let clock = ManualOwnerClock()
        var accessible = true
        let model = try makeModel(web: false, clock: clock, controlsNeedAccessibilityVisibility: { accessible })
        defer { model.cleanup(); clock.releaseAll() }
        model.scheduleAutoHide()
        XCTAssertNil(model.hideTask)
        accessible = false
        model.refreshPlaybackControlsAccessibility()
        let pending = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        model.transition(to: .paused(.native))
        clock.advance(by: 10)
        await pending.value
        XCTAssertTrue(model.showControls)
        model.cleanup()
        model.refreshPlaybackControlsAccessibility()
        XCTAssertEqual(clock.pendingCount, 0, "Retired views cannot start another controls timer")
    }

    func testReplacementControlsTimerCannotHideBeforeNewDeadline() async throws {
        let clock = ManualOwnerClock()
        let model = try makeModel(web: true, clock: clock)
        defer { model.cleanup(); clock.releaseAll() }
        model.scheduleAutoHide()
        let old = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 1 }
        clock.advance(by: 2)
        model.revealWebControlsFromProviderTap()
        let replacement = try XCTUnwrap(model.hideTask)
        try await waitFor { clock.pendingCount == 2 }
        clock.advance(by: 2)
        await old.value
        XCTAssertTrue(model.showControls, "A canceled old wait cannot hide newly revealed controls")
        clock.advance(by: 2)
        await replacement.value
        XCTAssertFalse(model.showControls)
    }

    func testPausedLoadingPickerStallAndTerminalStatesKeepControlsVisible() async throws {
        for cause in ["pause", "loading", "picker", "stall", "failure", "attempt", "dismissal"] {
            let clock = ManualOwnerClock()
            let model = try makeModel(web: false, clock: clock)
            defer { model.cleanup(); clock.releaseAll() }
            model.scheduleAutoHide()
            let task = try XCTUnwrap(model.hideTask)
            try await waitFor { clock.pendingCount == 1 }
            switch cause {
            case "pause": model.transition(to: .paused(.native))
            case "loading": model.transition(to: .connecting(.native))
            case "picker": model.showSourceSelector = true
            case "stall": model.playbackStagnationTicks = 1
            case "failure": model.error = "Unavailable"; model.transition(to: .failed)
            case "attempt": model.cancelLoading(); model.transition(to: .playing(.native))
            default: model.cleanup()
            }
            clock.advance(by: 10)
            await task.value
            XCTAssertTrue(model.showControls, cause)
            model.cleanup()
            clock.releaseAll()
        }
    }

    func testInitialBufferingDoesNotInventAStallOrRecovery() {
        let tracker = FottyPlaybackIntervals()
        let identity = intervalIdentity()
        tracker.beginAttempt(identity, context: intervalContext(identity), now: 0)
        tracker.beginStall(identity, now: 1)
        XCTAssertNil(tracker.decodedProgress(identity, now: 5))
        XCTAssertEqual(tracker.emittedCount, 0)
        XCTAssertTrue(tracker.hasDecoded)
    }

    func testRepeatedBufferingKeepsFirstObservedStartAndDecodedCompletion() throws {
        let tracker = FottyPlaybackIntervals()
        let identity = intervalIdentity()
        tracker.beginAttempt(identity, context: intervalContext(identity), now: 0)
        tracker.decodedProgress(identity, now: 1)
        tracker.beginStall(identity, now: 2)
        tracker.beginStall(identity, now: 4)
        let record = try XCTUnwrap(tracker.decodedProgress(identity, now: 5))
        XCTAssertEqual(record.durationMilliseconds, 3_000)
        XCTAssertEqual(record.completion, .decodedProgress)
        XCTAssertEqual(record.completion.outcome, .recovered)
        XCTAssertNil(tracker.decodedProgress(identity, now: 6), "Repeated decoded reports cannot duplicate an interval")
    }

    func testAttemptAndSourceReplacementsRejectOldCompletionAndPreserveOldContext() throws {
        let tracker = FottyPlaybackIntervals()
        let old = intervalIdentity(), replacement = intervalIdentity()
        tracker.beginAttempt(old, context: intervalContext(old), now: 0)
        tracker.decodedProgress(old, now: 1)
        tracker.beginStall(old, now: 2)
        let interrupted = try XCTUnwrap(tracker.beginAttempt(replacement, context: intervalContext(replacement), now: 5))
        XCTAssertEqual(interrupted.completion, .interrupted)
        XCTAssertEqual(interrupted.details["attempt_id"], old.attemptID.uuidString)
        XCTAssertFalse(tracker.hasDecoded)
        XCTAssertTrue(tracker.hasDecodedDuringSession, "Losing the next route must still permit recovery of the previously playing match.")
        tracker.beginStall(old, now: 6)
        XCTAssertNil(tracker.decodedProgress(old, now: 7))
        XCTAssertNil(tracker.audioPreparation(old, startedAt: 0, now: 8, result: .completed([])))
        let wrongSource = FottyPlaybackIntervals.Identity(sourceID: old.sourceID, attemptID: replacement.attemptID)
        XCTAssertNil(tracker.decodedProgress(wrongSource, now: 8))
        XCTAssertNil(tracker.decodedProgress(replacement, now: 9))
    }

    func testPausedAndTransportOnlyCompletionsAreNotDecodedRecovery() throws {
        for completion: FottyPlaybackIntervalCompletion in [.interrupted, .transportPlaying, .failed] {
            let tracker = FottyPlaybackIntervals()
            let identity = intervalIdentity()
            tracker.beginAttempt(identity, context: intervalContext(identity), now: 0)
            tracker.decodedProgress(identity, now: 1)
            tracker.beginStall(identity, now: 2)
            let record = try XCTUnwrap(tracker.finishStall(identity, now: 3, completion: completion))
            XCTAssertNotEqual(record.completion.outcome, .recovered)
            XCTAssertNil(tracker.finishStall(identity, now: 4, completion: completion))
        }
    }

    func testElapsedDurationsRejectBadClocksAndRemainBounded() {
        for pair in [(Double.nan, 1), (0, Double.infinity), (-1, 0), (5, 4)] {
            XCTAssertNil(FottyPlaybackIntervals.elapsedMilliseconds(from: pair.0, to: pair.1))
        }
        XCTAssertEqual(FottyPlaybackIntervals.elapsedMilliseconds(from: 10, to: 10), 0)
        XCTAssertEqual(FottyPlaybackIntervals.elapsedMilliseconds(from: 0, to: 100_000), 3_600_000)
    }

    func testPreparationOutcomesAndPerAttemptEmissionCap() throws {
        let tracker = FottyPlaybackIntervals()
        let identity = intervalIdentity()
        tracker.beginAttempt(identity, context: intervalContext(identity), now: 0)
        let complete = try XCTUnwrap(tracker.audioPreparation(identity, startedAt: 1, now: 3, result: .completed([])))
        XCTAssertEqual(complete.durationMilliseconds, 2_000)
        XCTAssertEqual(complete.name, "audio_preparation_duration")
        XCTAssertEqual(complete.completion, .completed)
        let failed = try XCTUnwrap(tracker.audioPreparation(identity, startedAt: 3, now: 4,
            result: .completed([.init(stage: .activation, code: -50)])))
        XCTAssertEqual(failed.completion, .completedWithErrors)
        let cancelled = try XCTUnwrap(tracker.audioPreparation(identity, startedAt: 4, now: 5, result: .cancelled))
        XCTAssertEqual(cancelled.completion.outcome, .info)
        for index in 3..<FottyPlaybackIntervals.maximumRecordsPerAttempt {
            XCTAssertNotNil(tracker.audioPreparation(identity, startedAt: 0, now: Double(index), result: .completed([])))
        }
        XCTAssertNil(tracker.audioPreparation(identity, startedAt: 0, now: 100, result: .completed([])))
        XCTAssertEqual(tracker.emittedCount, FottyPlaybackIntervals.maximumRecordsPerAttempt)
        let next = intervalIdentity()
        tracker.beginAttempt(next, context: intervalContext(next), now: 101)
        XCTAssertNotNil(tracker.audioPreparation(next, startedAt: 101, now: 102, result: .completed([])))
    }

    func testIntervalRecordsKeepExistingRedactionAndDecodedStartDefinitions() throws {
        let domain = "Fotty.IntervalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = FottyQualityStore(defaults: defaults, now: { self.date })
        let tracker = FottyPlaybackIntervals(), identity = intervalIdentity()
        var context = intervalContext(identity)
        context["raw_url"] = "https://example.invalid/private?token=secret"
        context["source"] = "https://example.invalid/private"
        tracker.beginAttempt(identity, context: context, now: 0)
        let record = try XCTUnwrap(tracker.audioPreparation(identity, startedAt: 0, now: 1, result: .completed([])))
        record.record(in: store)
        let retained = try XCTUnwrap(store.records().first)
        XCTAssertNil(retained.details["raw_url"])
        XCTAssertNil(retained.details["source"])
        XCTAssertEqual(retained.details["attempt_id"], identity.attemptID.uuidString)
        XCTAssertEqual(store.summary().provenPlaybackStarts, 0, "Audio preparation is not decoded playback")
        XCTAssertEqual(store.summary().recoveredPlaybackEvents, 0)
    }

    func testRealWebStageConsumerEmitsOneCurrentAttemptIntervalWithoutChangingControls() throws {
        let clock = ManualOwnerClock()
        let model = try makeModel(web: true, clock: clock)
        defer { model.cleanup(); clock.releaseAll() }
        let source = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        clock.advance(by: 2)
        model.recordPlaybackStage(.buffering, sourceID: source.id, requestID: request)
        clock.advance(by: 2)
        model.recordPlaybackStage(.buffering, sourceID: source.id, requestID: request)
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: UUID())
        clock.advance(by: 1)
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        let records = FottyQualityStore.shared.records().filter {
            $0.details["attempt_id"] == request.uuidString && $0.name == "stall_observed_duration"
        }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.durationMilliseconds, 3_000)
        XCTAssertEqual(records.first?.outcome, .recovered)
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.showControls)
    }

    func testWebPreparationCallbackMeasuresCurrentWaitWithoutOpeningNetwork() async throws {
        let clock = ManualOwnerClock(), gate = IntervalAudioGate()
        var measurements: [Int] = []
        let owner = LiveWebEmbedPlayerView.Coordinator(onAudioPreparationMeasured: { milliseconds, _ in
            measurements.append(milliseconds)
        }, configureAudioSession: gate.wait, timing: clock.timing)
        let web = IntervalRecordingWebView()
        defer { owner.invalidateLoading(); gate.finishAll(); clock.releaseAll() }
        owner.webView = web
        let url = try XCTUnwrap(URL(string: "https://example.invalid/interval-embed"))
        owner.beginLoading(url: url, referer: "https://example.invalid/", attemptID: UUID())
        owner.loadAfterAudioConfiguration(URLRequest(url: url), in: web)
        let task = try XCTUnwrap(owner.audioConfigurationTask)
        try await waitFor { gate.callCount == 1 }
        clock.advance(by: 2)
        gate.finish(0)
        await task.value
        XCTAssertEqual(measurements, [2_000])
        XCTAssertEqual(web.loadCount, 1)
    }

    func testWebPreparationReplacementRejectsOldMeasurementsAsWellAsOldNavigation() async throws {
        let clock = ManualOwnerClock(), gate = IntervalAudioGate()
        var measurements: [Int] = []
        let owner = LiveWebEmbedPlayerView.Coordinator(onAudioPreparationMeasured: { milliseconds, _ in
            measurements.append(milliseconds)
        }, configureAudioSession: gate.wait, timing: clock.timing)
        let web = IntervalRecordingWebView()
        defer { owner.invalidateLoading(); gate.finishAll(); clock.releaseAll() }
        owner.webView = web
        let url = try XCTUnwrap(URL(string: "https://example.invalid/interval-embed"))
        owner.beginLoading(url: url, referer: "https://example.invalid/", attemptID: UUID())
        owner.loadAfterAudioConfiguration(URLRequest(url: url), in: web)
        let old = try XCTUnwrap(owner.audioConfigurationTask)
        try await waitFor { gate.callCount == 1 }
        clock.advance(by: 2)
        owner.beginLoading(url: url, referer: "https://example.invalid/", attemptID: UUID())
        owner.loadAfterAudioConfiguration(URLRequest(url: url), in: web)
        let current = try XCTUnwrap(owner.audioConfigurationTask)
        try await waitFor { gate.callCount == 2 }
        gate.finish(0)
        await old.value
        XCTAssertTrue(measurements.isEmpty)
        XCTAssertEqual(web.loadCount, 0)
        clock.advance(by: 3)
        gate.finish(1)
        await current.value
        XCTAssertEqual(measurements, [3_000])
        XCTAssertEqual(web.loadCount, 1)
    }

    private func intervalIdentity() -> FottyPlaybackIntervals.Identity {
        .init(sourceID: UUID(), attemptID: UUID())
    }

    private func intervalContext(_ identity: FottyPlaybackIntervals.Identity) -> [String: String] {
        ["source_id": identity.sourceID.uuidString, "attempt_id": identity.attemptID.uuidString,
         "mode": "native", "route": "single"]
    }

    private func catalog(count: Int) -> HomeSportsDiscovery {
        HomeSportsDiscovery(events: (0..<count).map {
            .init(id: "timing-row-\($0)", title: "Chelsea vs Brighton", category: "football",
                  // IDs alone do not make duplicate fixtures distinct: the
                  // production catalog correctly unions identical teams/start.
                  // Give each test rematch its own exact kickoff identity.
                  date: Int64(date.addingTimeInterval(3_600 + Double($0) * 60).timeIntervalSince1970),
                  poster: nil, popular: false, teams: nil)
        }, now: date)
    }

    private func makeModel(web: Bool, clock: ManualOwnerClock,
                           controlsNeedAccessibilityVisibility: @escaping @MainActor () -> Bool = { false }) throws -> LivePlayerViewModel {
        let event = AnalyticalDataEngine.EventReference(id: "timing-player", title: "Timing test",
            category: "football", date: 0, poster: nil, popular: false, teams: nil)
        let session = StreamSession(matchID: event.id,
            playableURL: try XCTUnwrap(URL(string: "https://example.invalid/timing\(web ? "/embed" : ".m3u8")")),
            streamType: web ? .unknown : .hls, providerName: "CS1",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:],
            diagnosticMetadata: ["source_family": "communitysports"])
        let model = LivePlayerViewModel(event: event, providedSessions: [session],
            prepareAudioSession: { .completed([]) }, validateNativeSource: { _, _ in .valid }, timing: clock.timing,
            controlsNeedAccessibilityVisibility: controlsNeedAccessibilityVisibility)
        XCTAssertNotNil(model.activeSource)
        XCTAssertEqual(model.isUsingWebEmbed, web)
        model.transition(to: .playing(web ? .webEmbed : .native))
        return model
    }

    private func waitFor(file: StaticString = #filePath, line: UInt = #line,
                         _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Owner timing barrier did not arrive", file: file, line: line)
        throw OwnerTimingBarrierFailure.timeout
    }
}

private enum OwnerTimingBarrierFailure: Error { case timeout }

@MainActor
private final class IntervalAudioGate {
    private var calls: [CheckedContinuation<MediaAudioSessionPreparation, Never>?] = []
    var callCount: Int { calls.count }
    func wait() async -> MediaAudioSessionPreparation {
        await withCheckedContinuation { calls.append($0) }
    }
    func finish(_ index: Int) {
        guard calls.indices.contains(index), let continuation = calls[index] else { return }
        calls[index] = nil
        continuation.resume(returning: .completed([]))
    }
    func finishAll() {
        for index in calls.indices { finish(index) }
    }
}

private final class IntervalRecordingWebView: WKWebView {
    private(set) var loadCount = 0
    override func load(_ request: URLRequest) -> WKNavigation? { loadCount += 1; return nil }
}

/// Deliberately non-cooperative waits exercise the production post-wait
/// cancellation/identity fences. Every test drains its own continuations.
@MainActor
private final class ManualOwnerClock {
    private struct Waiter {
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }
    private(set) var now: TimeInterval = 0
    private var waiters: [Waiter] = []
    var pendingCount: Int { waiters.count }
    var timing: FottyAsyncTiming {
        .init(monotonicNow: { self.now }, sleep: { duration in
            let parts = duration.components
            let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
            try await withCheckedThrowingContinuation { continuation in
                self.waiters.append(.init(deadline: self.now + seconds, continuation: continuation))
            }
        })
    }
    func advance(by seconds: TimeInterval) {
        now += seconds
        let ready = waiters.filter { $0.deadline <= now + 0.000_000_1 }
        waiters.removeAll { $0.deadline <= now + 0.000_000_1 }
        for waiter in ready { waiter.continuation.resume() }
    }
    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.continuation.resume() }
    }
}
