import XCTest
import AVFoundation
import AVKit
import UIKit
@testable import Fotty

/// Ownership and intent tests only. Empty local compositions do not establish
/// readiness, decoded video, fullscreen presentation or physical PiP support.
@MainActor
final class NativeFullscreenPlaybackTests: XCTestCase {
    func testInitialFullscreenDefersThroughSheetDismissalWithoutDetachingInlineTransport() async throws {
        let model = makeModel(), retry = FullscreenInitialPresentationRetryGate()
        let mounted = attachPendingFullscreenHost(model, retry: retry)
        defer { mounted.host.retirePresentation(); model.cleanup(); retry.finish() }
        let player = try XCTUnwrap(model.player), item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID
        let inline = AVPlayerLayerView.PlayerUIView()
        inline.player = player
        mounted.presenter.testBeingDismissed = true
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)

        mounted.host.reconcile(session)
        guard await waitForForegroundObservationCondition({ retry.pendingCount == 1 }) else {
            return XCTFail("The initial presentation did not defer its busy same-window presenter")
        }
        inline.suspendsInlinePlayback = model.nativeFullscreenIsPresented
        XCTAssertFalse(model.nativeFullscreenIsPresented)
        XCTAssertTrue(inline.player === player, "A requested lease is not an admitted AVKit renderer")
        XCTAssertNil(mounted.presenter.testPresented)

        mounted.presenter.testBeingDismissed = false
        retry.resumeNext()
        guard await waitForForegroundObservationCondition({ model.nativeFullscreenIsPresented }) else {
            return XCTFail("The same pending lease was not presented after the sheet transition")
        }
        let controller = try XCTUnwrap(mounted.presenter.testPresented as? AVPlayerViewController)
        XCTAssertTrue(controller.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertTrue(model.nativeFullscreen === session)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(mounted.presenter.presentCount, 1)
        XCTAssertEqual(mounted.presenter.dismissCount, 0)
        XCTAssertNil(model.loadTask)
        inline.suspendsInlinePlayback = model.nativeFullscreenIsPresented
        XCTAssertNil(inline.player, "Only retained AVKit presentation commits the inline handoff")
        mounted.host.retirePresentation()
        inline.suspendsInlinePlayback = model.nativeFullscreenIsPresented
        inline.player = player // The ordinary UIView update rebinds the same transport.
        XCTAssertTrue(inline.player === player)
        XCTAssertTrue(player.currentItem === item)
    }

    func testCancelledInitialRetryCannotPresentOrRetireAReplacementLease() async throws {
        let model = makeModel(), retry = FullscreenInitialPresentationRetryGate()
        let mounted = attachPendingFullscreenHost(model, retry: retry)
        defer { mounted.host.retirePresentation(); model.cleanup(); retry.finish() }
        mounted.presenter.testBeingPresented = true
        model.beginNativeFullscreen()
        let old = try XCTUnwrap(model.nativeFullscreen)
        mounted.host.reconcile(old)
        guard await waitForForegroundObservationCondition({ retry.pendingCount == 1 }) else {
            return XCTFail("Expected one pending initial presentation")
        }

        model.endNativeFullscreen(old)
        XCTAssertTrue(old.isRetired)
        mounted.presenter.testBeingPresented = false
        model.beginNativeFullscreen()
        let replacement = try XCTUnwrap(model.nativeFullscreen)
        mounted.host.reconcile(replacement)
        XCTAssertTrue(model.nativeFullscreenIsPresented)
        let controller = try XCTUnwrap(mounted.presenter.testPresented as? AVPlayerViewController)
        retry.resumeNext() // Deliberately release the old callback after cancellation.
        await Task.yield()

        XCTAssertTrue(model.nativeFullscreen === replacement)
        XCTAssertFalse(replacement.isRetired)
        XCTAssertTrue(controller.player === replacement.player)
        XCTAssertEqual(mounted.presenter.presentCount, 1)
        XCTAssertEqual(mounted.presenter.dismissCount, 0)
        XCTAssertNil(model.loadTask)
    }

    func testInitialMissingWindowExhaustionReleasesOnlyThePendingLeaseAndKeepsPausedInlinePlayer() async throws {
        let model = makeModel(), retry = FullscreenInitialPresentationRetryGate()
        model.togglePlayPause()
        let host = NativeFullscreenHostController(model: model, maximumPresentationDeferrals: 1,
            waitForPresentationRetry: retry.wait)
        host.loadViewIfNeeded() // This marker has no window yet.
        defer { host.retirePresentation(); model.cleanup(); retry.finish() }
        let player = try XCTUnwrap(model.player), item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID
        let inline = AVPlayerLayerView.PlayerUIView()
        inline.player = player
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)
        host.reconcile(session)
        guard await waitForForegroundObservationCondition({ retry.pendingCount == 1 }) else {
            return XCTFail("Missing-window admission must wait within its finite budget")
        }

        retry.resumeNext()
        guard await waitForForegroundObservationCondition({ model.nativeFullscreen == nil }) else {
            return XCTFail("Exhaustion left an unpresented lease hiding the inline renderer")
        }
        inline.suspendsInlinePlayback = model.nativeFullscreenIsPresented
        XCTAssertTrue(session.isRetired)
        XCTAssertFalse(model.nativeFullscreenIsPresented)
        XCTAssertTrue(inline.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertTrue(model.canShowNativeFullscreen)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.audioPreparationTask)
    }

    func testInitialRetryCannotMoveItsRequestToAnotherWindow() async throws {
        let model = makeModel(), retry = FullscreenInitialPresentationRetryGate()
        let mounted = attachPendingFullscreenHost(model, retry: retry)
        defer { mounted.host.retirePresentation(); model.cleanup(); retry.finish() }
        mounted.presenter.testBeingDismissed = true
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)
        mounted.host.reconcile(session)
        guard await waitForForegroundObservationCondition({ retry.pendingCount == 1 }) else {
            return XCTFail("Expected one same-window transition deferral")
        }
        let otherWindow = UIWindow(frame: mounted.window.frame)
        let otherPresenter = FullscreenPresentationTestController()
        otherWindow.rootViewController = otherPresenter
        otherWindow.addSubview(otherPresenter.view)
        otherPresenter.view.addSubview(mounted.host.view)
        retry.resumeNext()
        guard await waitForForegroundObservationCondition({ model.nativeFullscreen == nil }) else {
            return XCTFail("A moved marker must release the old window's pending lease")
        }
        XCTAssertTrue(session.isRetired)
        XCTAssertFalse(model.nativeFullscreenIsPresented)
        XCTAssertEqual(mounted.presenter.presentCount + otherPresenter.presentCount, 0)
        XCTAssertEqual(mounted.presenter.dismissCount + otherPresenter.dismissCount, 0)
        XCTAssertTrue(model.player === session.player)
        XCTAssertTrue(model.player?.currentItem === session.item)
        withExtendedLifetime(otherWindow) {}
    }

    func testRefusedInitialPresentationWithoutCompletionRollsBackWithinTheSameBudget() async throws {
        let model = makeModel(), retry = FullscreenInitialPresentationRetryGate()
        let mounted = attachPendingFullscreenHost(model, retry: retry, maximumDeferrals: 1)
        defer { mounted.host.retirePresentation(); model.cleanup(); retry.finish() }
        mounted.presenter.refusesPresentation = true
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)
        mounted.host.reconcile(session)
        guard await waitForForegroundObservationCondition({ retry.pendingCount == 1 }) else {
            return XCTFail("A refused UIKit presentation still needs a bounded completion gate")
        }
        XCTAssertFalse(model.nativeFullscreenIsPresented)
        retry.resumeNext()
        guard await waitForForegroundObservationCondition({ model.nativeFullscreen == nil }) else {
            return XCTFail("A missing UIKit completion must not strand the pending lease")
        }
        XCTAssertTrue(session.isRetired)
        XCTAssertEqual(mounted.presenter.presentCount, 1)
        XCTAssertEqual(mounted.presenter.dismissCount, 0)
        XCTAssertTrue(model.player === session.player)
        XCTAssertTrue(model.player?.currentItem === session.item)
        XCTAssertFalse(model.nativeFullscreenIsPresented)
        XCTAssertNil(model.loadTask)
    }

    func testBackgroundPiPSoftStallExpiryRearmsForegroundObservationAndBoundedExistingRecovery() async throws {
        let validation = FullscreenSourceValidationBarrier()
        let model = makeModel(validateNativeSource: validation.wait)
        defer { model.cleanup(); validation.finish() }
        let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
        let player = FullscreenWaitingTransportSpyPlayer(playerItem: item)
        model.player = player
        model.isPictureInPictureAvailable = true
        model.isPictureInPictureActive = true
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let alternate = try XCTUnwrap(model.sources.first { $0.id != source.id })
        model.startPlaybackWatchdog(for: source)
        let backgroundWatchdog = try XCTUnwrap(model.playbackWatchdogTask)
        model.handleScenePhaseChange(.background)
        XCTAssertFalse(model.shouldResumeAfterForeground, "PiP continuity needs observation, not a second Play")

        // Execute the real two-second samples and six-tick threshold. The
        // production five-second startup grace and stall delays are unchanged.
        var backgroundWatchdogEnded = false
        let backgroundCompletion = Task { await backgroundWatchdog.value; backgroundWatchdogEnded = true }
        defer { backgroundCompletion.cancel() }
        guard await waitForForegroundObservationCondition(timeout: .seconds(21), {
            backgroundWatchdogEnded
        }) else { return XCTFail("The background waiting watchdog did not reach its bounded expiry") }
        let backgroundValidation = try XCTUnwrap(model.stallValidationTask)
        var backgroundValidationEnded = false
        let backgroundValidationCompletion = Task { await backgroundValidation.value; backgroundValidationEnded = true }
        defer { backgroundValidationCompletion.cancel() }
        guard await waitForForegroundObservationCondition({ backgroundValidationEnded }) else {
            return XCTFail("Background validation did not refuse recovery")
        }
        XCTAssertNil(model.loadTask)
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(player.currentItem === item)

        let foregroundObservationStartedAt = ContinuousClock.now
        model.handleScenePhaseChange(.active)
        let foregroundWatchdog = try XCTUnwrap(model.playbackWatchdogTask)
        XCTAssertTrue(backgroundWatchdog.isCancelled, "Foreground must replace the consumed observer")
        XCTAssertFalse(foregroundWatchdog.isCancelled)
        XCTAssertTrue(model.isPlaybackWatchdogArmed)
        XCTAssertEqual(player.playCount, 0, "Observation must not resume or restart transport")
        XCTAssertNil(model.loadTask)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source.id)
        XCTAssertTrue(player.currentItem === item)

        // The background half already executed every real threshold sample.
        // Advance only the foreground stagnation counter to its last sample;
        // execute the real tick and the full ten-second validation unchanged.
        model.playbackStagnationTicks = model.nativeWatchdogStallThresholdTicks - 1
        model.lastObservedPlaybackSecond = 0
        var foregroundWatchdogEnded = false
        let foregroundCompletion = Task { await foregroundWatchdog.value; foregroundWatchdogEnded = true }
        defer { foregroundCompletion.cancel() }
        guard await waitForForegroundObservationCondition(timeout: .seconds(4), {
            foregroundWatchdogEnded
        }) else { return XCTFail("The restored observer did not reach foreground stall validation") }
        XCTAssertEqual(model.activeSource?.id, source.id, "Entering validation is not permission to replace the source")
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertNil(model.loadTask)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertEqual(player.playCount, 0)
        guard await waitForForegroundObservationCondition(timeout: .seconds(13), {
            validation.pendingCount == 1
        }) else { return XCTFail("The real foreground stall budget did not reach its existing recovery policy") }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - foregroundObservationStartedAt, .seconds(12),
            "Recovery still owes the real watchdog sample plus the full ten-second validation budget")
        let loading = try XCTUnwrap(model.loadTask)
        XCTAssertNotEqual(model.loadRequestID, attempt)
        // Existing native policy exhausts a proven frozen stall after this
        // complete validation budget; only startup failures get a native retry.
        // Observation restoration must not introduce a different retry policy.
        XCTAssertEqual(model.activeSource?.id, alternate.id)
        XCTAssertEqual(model.failedSourceIDs, [source.id])
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 1)
        XCTAssertFalse(model.isUsingWebEmbed)
        XCTAssertTrue(model.forceWebEmbedSourceIDs.isEmpty)
        XCTAssertEqual(player.playCount, 0)
        model.cleanup(); validation.finish()
        await loading.value
    }

    func testForegroundPiPObservationPreservesAdvancingTransportAndDoesNotRenewOnDuplicateActive() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
        let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
        model.player = player
        player.setSeconds(1)
        let session = try openControls(model)
        let source = model.activeSource?.id, attempt = model.loadRequestID
        model.isPictureInPictureAvailable = true
        model.isPictureInPictureActive = true
        model.handleScenePhaseChange(.background)
        player.setSeconds(5)
        let previousState = model.playbackState
        model.handleScenePhaseChange(.active)
        let watchdog = try XCTUnwrap(model.playbackWatchdogTask)
        XCTAssertTrue(model.isPlaybackWatchdogArmed)
        XCTAssertFalse(watchdog.isCancelled)
        XCTAssertEqual(model.playbackState, previousState)
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertTrue(model.nativeFullscreen === session)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertNil(model.loadTask)
        model.handleScenePhaseChange(.active)
        XCTAssertFalse(watchdog.isCancelled, "A consumed lease cannot keep replacing the current observer")
        XCTAssertEqual(player.playCount, 0)
    }

    func testForegroundPiPObservationRejectsPausedStaleRetiredAndNonSingleOwners() throws {
        for rejection in ["pause", "source", "attempt", "player", "item", "missing-item", "failed-item",
                          "terminal", "network-wait", "web", "watch-two", "diagnostic", "retired"] {
            let model = makeModel()
            defer { model.cleanup() }
            let item = FullscreenForegroundObservationItem(asset: AVMutableComposition())
            let player = FullscreenWaitingTransportSpyPlayer(playerItem: item)
            model.player = player
            model.isPictureInPictureAvailable = true
            model.isPictureInPictureActive = true
            model.handleScenePhaseChange(.background)
            model.stopPlaybackWatchdog()
            switch rejection {
            case "pause": model.togglePlayPause()
            case "source": model.currentSourceIndex = (model.currentSourceIndex + 1) % model.sessions.count
            case "attempt": model.cancelLoading(); model.transition(to: .playing(.native))
            case "player": model.player = FullscreenWaitingTransportSpyPlayer(
                playerItem: FullscreenDiagnosticReadyItem(asset: AVMutableComposition()))
            case "item": player.replaceCurrentItem(with: FullscreenDiagnosticReadyItem(asset: AVMutableComposition()))
            case "missing-item": player.replaceCurrentItem(with: nil)
            case "failed-item": item.setFailed()
            case "terminal": model.error = "Controlled terminal result"; model.transition(to: .failed)
            case "network-wait": model.pendingRetryAfterNetworkRestore = true
            case "web": model.forceWebEmbedSourceIDs.insert(try XCTUnwrap(model.activeSource?.id))
            case "watch-two": model.setViewingPlaybackContext(.watchTwo(engine: .native))
            case "diagnostic": model.setViewingDiagnosticRoute(.watchTwo)
            default: model.cleanup()
            }
            let source = model.activeSource?.id, attempt = model.loadRequestID
            model.handleScenePhaseChange(.active)
            XCTAssertFalse(model.isPlaybackWatchdogArmed, rejection)
            XCTAssertNil(model.playbackWatchdogTask, rejection)
            XCTAssertNil(model.loadTask, rejection)
            XCTAssertNil(model.audioPreparationTask, rejection)
            XCTAssertEqual(player.playCount, 0, rejection)
            XCTAssertEqual(model.activeSource?.id, source, rejection)
            XCTAssertEqual(model.loadRequestID, attempt, rejection)
        }
    }

    func testExplicitBackgroundPiPPauseThenPlayAllowsCurrentForegroundObservationWithoutAnotherPlay() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let player = FullscreenWaitingTransportSpyPlayer(playerItem: FullscreenDiagnosticReadyItem(asset: AVMutableComposition()))
        model.player = player
        let session = try openControls(model)
        let source = model.activeSource?.id, attempt = model.loadRequestID
        model.isPictureInPictureAvailable = true
        model.isPictureInPictureActive = true
        let backgroundIntent = model.nativeWatchTwoIntentID
        model.handleScenePhaseChange(.background)
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNotEqual(model.nativeWatchTwoIntentID, backgroundIntent)
        XCTAssertFalse(model.isPlaybackWatchdogArmed, "Background Play does not grant background recovery")
        model.handleScenePhaseChange(.active)
        XCTAssertTrue(model.isPlaybackWatchdogArmed)
        XCTAssertFalse(try XCTUnwrap(model.playbackWatchdogTask).isCancelled)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === session.item)
        XCTAssertEqual(player.playCount, 0, "AVKit already issued the explicit Play")
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertNil(model.loadTask)
    }

    func testWatchTwoPiPForegroundDoesNotAcquireSinglePlaybackObservation() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.setViewingPlaybackContext(.watchTwo(engine: .native))
        model.isPictureInPictureAvailable = true
        model.isPictureInPictureActive = true
        model.handleScenePhaseChange(.background)
        model.handleScenePhaseChange(.active)
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        XCTAssertNil(model.playbackWatchdogTask)
        XCTAssertNil(model.foregroundResumeValidationTask)
        XCTAssertNil(model.loadTask)
    }

    func testPausedIncidentRetiresAfterVerifiedResumeEvenWhenTheAttemptAlreadyDecoded() async throws {
        let validation = FullscreenSourceValidationBarrier()
        let model = makeModel(validateNativeSource: validation.wait)
        defer { model.cleanup(); validation.finish() }
        let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
        let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
        model.player = player
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        player.setSeconds(1)
        XCTAssertTrue(model.observeSingleNativeResumeProgress(player: player, item: item,
            sourceID: source.id, requestID: attempt, intentID: model.nativeWatchTwoIntentID,
            startSeconds: 0, currentSeconds: 1))
        let controls = try openControls(model)
        model.isPictureInPictureAvailable = true
        model.handlePictureInPictureActivityChanged(true)
        model.handleScenePhaseChange(.background)
        let failure = NSError(domain: "CoreMediaErrorDomain", code: -12312)
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .failedToPlayToEnd, reportedError: failure)
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: controls)
        model.handleScenePhaseChange(.active)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertNil(model.loadTask, "Consuming a paused incident cannot recover automatically")

        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: controls)
        let intent = model.nativeWatchTwoIntentID
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(player.playCount, 0, "AVKit's explicit Play must not be repeated by the model")
        // An old startup receipt and a .playing transport do not clear the
        // incident. Neither does an unready surface or nonprogressing sample.
        XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
            sourceID: source.id, requestID: attempt, intentID: intent, startSeconds: 1, currentSeconds: 1))
        player.setSeconds(2)
        model.isVideoReadyForDisplay = false
        XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
            sourceID: source.id, requestID: attempt, intentID: intent, startSeconds: 1, currentSeconds: 2))
        model.isVideoReadyForDisplay = true
        XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
            sourceID: source.id, requestID: attempt, intentID: intent, startSeconds: 1, currentSeconds: 2),
            "Incident retirement still occurs before the already-decoded receipt guard")
        XCTAssertEqual(FottyQualityStore.shared.records().filter {
            $0.name == "decoded_progress" && $0.details["attempt_id"] == attempt.uuidString
        }.count, 1, "Recovery must not create a second startup metric")
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player?.currentItem === item)

        model.handleScenePhaseChange(.background)
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .failedToPlayToEnd, reportedError: failure)
        XCTAssertEqual(FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["attempt_id"] == attempt.uuidString
        }.count, 2, "A later real failure must own a new receipt, not the consumed paused incident")
        XCTAssertNil(model.loadTask, "The second incident still cannot retry in background")
        model.handleScenePhaseChange(.active)
        let loading = try XCTUnwrap(model.loadTask)
        await validation.waitUntilEntered()
        XCTAssertEqual(validation.pendingCount, 1)
        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source.id)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
        model.cleanup(); validation.finish()
        await loading.value
    }

    func testProgressBeforeTheLatestBackgroundFailureCannotSuppressItsForegroundRecovery() async throws {
        let validation = FullscreenSourceValidationBarrier()
        let model = makeModel(validateNativeSource: validation.wait)
        defer { model.cleanup(); validation.finish() }
        let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
        let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
        model.player = player
        model.isPictureInPictureAvailable = true
        model.handlePictureInPictureActivityChanged(true)
        model.handleScenePhaseChange(.background)
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let failure = NSError(domain: "CoreMediaErrorDomain", code: -12312)
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .failedToPlayToEnd, reportedError: failure)
        player.setSeconds(1)
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .failedToPlayToEnd, reportedError: failure)
        model.handleScenePhaseChange(.active)
        let loading = try XCTUnwrap(model.loadTask)
        await validation.waitUntilEntered()

        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source.id)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
        XCTAssertEqual(FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["attempt_id"] == attempt.uuidString
        }.count, 1, "Repeated fatal callbacks share one incident receipt")
        model.cleanup(); validation.finish()
        await loading.value
    }

    func testFreshDisplayedProgressAfterBackgroundFailurePreservesTheRecoveredItemAndSource() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
        let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
        model.player = player
        model.isPictureInPictureAvailable = true
        model.handlePictureInPictureActivityChanged(true)
        model.handleScenePhaseChange(.background)
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let failure = NSError(domain: "CoreMediaErrorDomain", code: -12312)
        for second in [1.0, 2.0] {
            model.handleNativeItemFailure(item, source: source, requestID: attempt,
                trigger: .failedToPlayToEnd, reportedError: failure)
            // Controlled advancing media + ready surface, not a .playing-only
            // inference. A real device still supplies the actual video proof.
            player.setSeconds(second)
            model.handleScenePhaseChange(.active)
            XCTAssertTrue(model.player === player)
            XCTAssertTrue(player.currentItem === item)
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertEqual(model.activeSource?.id, source.id)
            XCTAssertTrue(model.userWantsPlayback)
            XCTAssertNil(model.loadTask)
            XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
            XCTAssertEqual(player.playCount, 0)
            model.handleScenePhaseChange(.background)
        }
        XCTAssertEqual(FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["attempt_id"] == attempt.uuidString
        }.count, 2, "Genuine recovery ends the first incident's deduplication lease")
    }

    func testOwnedFullscreenResumeRecordsPreviouslyMissingVideoProgressOnceWithoutAnotherPlay() async throws {
        let delay = FullscreenResumeDelayGate()
        let model = makeModel(timing: .init(monotonicNow: { 0 }, sleep: delay.wait))
        defer { model.cleanup(); delay.finishAll() }
        // Typed readiness and a controlled media clock exercise the real
        // existing resume callback. This is not a decoder/device qualification.
        let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
        let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
        model.player = player
        let session = try openControls(model)
        let attempt = model.loadRequestID
        let oldIntent = model.nativeWatchTwoIntentID
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        let resume = try XCTUnwrap(model.foregroundResumeValidationTask)
        let watchdog = try XCTUnwrap(model.playbackWatchdogTask)
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(2)
        while delay.pendingCount == 0, clock.now < deadline { await Task.yield() }
        guard delay.pendingCount == 1 else { return XCTFail("The existing resume observation did not reach its controlled deadline") }
        XCTAssertNotEqual(model.nativeWatchTwoIntentID, oldIntent)
        XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
            sourceID: try XCTUnwrap(model.activeSource?.id), requestID: attempt, intentID: oldIntent,
            startSeconds: 0, currentSeconds: 1), "A queued pre-Pause sample cannot claim resumed evidence")
        let beforeState = model.playbackState
        let beforeLatency = model.lastStartupLatencyMs
        player.setSeconds(1)
        delay.releaseNext()
        await resume.value

        let receipts = FottyQualityStore.shared.records().filter { $0.name == "decoded_progress" && $0.details["attempt_id"] == attempt.uuidString }
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.details["diagnostic_purpose"], "native_resume")
        XCTAssertNil(receipts.first?.durationMilliseconds, "User Pause time is not fresh startup latency")
        XCTAssertEqual(model.lastStartupLatencyMs, beforeLatency)
        XCTAssertEqual(model.playbackState, beforeState)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(player.playCount, 0, "The diagnostic must never repeat AVKit's Play")
        XCTAssertFalse(watchdog.isCancelled)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
            sourceID: try XCTUnwrap(model.activeSource?.id), requestID: attempt,
            intentID: model.nativeWatchTwoIntentID, startSeconds: 1, currentSeconds: 2))
        XCTAssertEqual(FottyQualityStore.shared.records().filter { $0.name == "decoded_progress" && $0.details["attempt_id"] == attempt.uuidString }.count, 1)
    }

    func testResumeVideoObservationRejectsUnreadyClockOnlyAndNonprogressingSamples() throws {
        for rejection in ["item-unready", "surface-unready", "static", "backwards", "nonfinite", "negative", "paused"] {
            let model = makeModel()
            defer { model.cleanup() }
            let item: AVPlayerItem = rejection == "item-unready"
                ? AVPlayerItem(asset: AVMutableComposition()) : FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
            let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
            model.player = player
            let attempt = model.loadRequestID
            var start = 0.0, current = 1.0
            switch rejection {
            case "surface-unready": model.isVideoReadyForDisplay = false
            case "static": current = 0
            case "backwards": start = 2
            case "nonfinite": current = .nan
            case "negative": start = -1
            case "paused": model.togglePlayPause()
            default: break
            }
            XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
                sourceID: try XCTUnwrap(model.activeSource?.id), requestID: attempt,
                intentID: model.nativeWatchTwoIntentID, startSeconds: start, currentSeconds: current), rejection)
            XCTAssertFalse(FottyQualityStore.shared.records().contains { $0.name == "decoded_progress" && $0.details["attempt_id"] == attempt.uuidString }, rejection)
            XCTAssertEqual(player.playCount, 0, rejection)
            XCTAssertNil(model.loadTask, rejection)
        }
    }

    func testResumeVideoObservationRejectsReplacedOwnersAndDoesNotTouchWatchTwo() throws {
        for rejection in ["source", "attempt", "player", "item", "intent", "watch-two", "retired"] {
            let model = makeModel()
            defer { model.cleanup() }
            let item = FullscreenDiagnosticReadyItem(asset: AVMutableComposition())
            let player = FullscreenDiagnosticProgressPlayer(playerItem: item)
            model.player = player
            let source = try XCTUnwrap(model.activeSource?.id), attempt = model.loadRequestID
            let intent = model.nativeWatchTwoIntentID
            switch rejection {
            case "source": model.currentSourceIndex = (model.currentSourceIndex + 1) % model.sessions.count
            case "attempt": model.cancelLoading(); model.transition(to: .playing(.native), phase: "Controlled current transport")
            case "player": model.player = AVPlayer(playerItem: FullscreenDiagnosticReadyItem(asset: AVMutableComposition()))
            case "item": player.replaceCurrentItem(with: FullscreenDiagnosticReadyItem(asset: AVMutableComposition()))
            case "intent": model.togglePlayPause(); model.handleNativeTimeControlStatusChanged(.playing)
            case "watch-two": model.setViewingDiagnosticRoute(.watchTwo)
            case "retired": model.cleanup()
            default: break
            }
            XCTAssertFalse(model.observeSingleNativeResumeProgress(player: player, item: item,
                sourceID: source, requestID: attempt, intentID: intent, startSeconds: 0, currentSeconds: 1), rejection)
            XCTAssertFalse(FottyQualityStore.shared.records().contains { $0.name == "decoded_progress" && $0.details["attempt_id"] == attempt.uuidString }, rejection)
            XCTAssertEqual(player.playCount, 0, rejection)
        }
    }

    func testInitialStartupObservationExitReasonsStayFiniteAndCannotClaimDecodedOrProviderFailure() {
        for reason in NativeStartupObservationEndReason.allCases {
            let details = reason.qualityDetails
            XCTAssertEqual(details["reason_code"], reason.rawValue)
            XCTAssertEqual(details["diagnostic_purpose"], "native_start")
            XCTAssertNotNil(FottyPlaybackDiagnosticResult(rawValue: details["diagnostic_result"] ?? ""))
            XCTAssertNil(details["native_error_code"])
            XCTAssertNil(details["failure_kind"])
            XCTAssertEqual(Set(details.keys), ["reason_code", "diagnostic_result", "diagnostic_purpose"])
        }
    }

    func testPresentationReceiptsAreBoundedToFiniteEdgesAndExactBorrowedLease() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let mounted = try mountFullscreenHost(model)
        let item = mounted.session.item
        let attempt = model.loadRequestID
        for _ in 0..<3 {
            mounted.host.playerViewControllerWillStartPictureInPicture(mounted.controller)
            mounted.host.playerViewControllerDidStartPictureInPicture(mounted.controller)
        }
        model.handleScenePhaseChange(.background)
        // The covered SwiftUI marker can be detached while AVKit owns PiP.
        mounted.host.view.removeFromSuperview()
        XCTAssertNil(mounted.host.view.window)
        mounted.host.playerViewControllerDidStopPictureInPicture(mounted.controller)

        XCTAssertTrue(model.isAppBackgrounded)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertTrue(model.shouldResumeAfterForeground)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        mounted.host.retirePresentation()
        mounted.host.retirePresentation()

        let receipts = FottyQualityStore.shared.records().filter {
            $0.name == "native_presentation"
                && $0.details["native_presentation_id"] == mounted.session.id.uuidString
        }
        let events = receipts.compactMap { $0.details["native_presentation_event"] }
        XCTAssertEqual(events, ["presented", "pip_will_start", "pip_did_start", "pip_did_stop", "finish_dismantled"])
        XCTAssertTrue(receipts.allSatisfy { $0.details["attempt_id"] == attempt.uuidString
            && $0.details["source_id"] == mounted.session.sourceID?.uuidString })
        let stopped = try XCTUnwrap(receipts.first { $0.details["native_presentation_event"] == "pip_did_stop" })
        XCTAssertEqual(stopped.details["native_pip_active"], "false")
        XCTAssertEqual(stopped.details["native_app_backgrounded"], "true")
        XCTAssertNil(mounted.controller.player)
        XCTAssertTrue(model.player?.currentItem === item)
        withExtendedLifetime(mounted) {}
    }

    func testTransportRetirementReceiptCannotBePublishedByAStaleHostCallback() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let mounted = try mountFullscreenHost(model)
        model.cancelLoading()
        mounted.host.playerViewControllerDidStartPictureInPicture(mounted.controller)
        mounted.host.playerViewControllerDidStopPictureInPicture(mounted.controller)
        mounted.host.retirePresentation()

        let events = FottyQualityStore.shared.records().filter {
            $0.name == "native_presentation"
                && $0.details["native_presentation_id"] == mounted.session.id.uuidString
        }.compactMap { $0.details["native_presentation_event"] }
        XCTAssertEqual(events, ["presented", "finish_transport_revoked"])
        XCTAssertFalse(model.isPictureInPictureActive)
        XCTAssertTrue(mounted.session.isRetired)
        withExtendedLifetime(mounted) {}
    }

    func testAdmittedSamePlayerRetryDetachesFullscreenBeforeResettingItsItem() async throws {
        let validation = FullscreenSourceValidationBarrier()
        let model = makeModel(validateNativeSource: validation.wait)
        defer { model.cleanup(); validation.finish() }
        let mounted = try mountFullscreenHost(model)
        let oldItem = try XCTUnwrap(model.player?.currentItem)
        let attempt = model.loadRequestID
        let ticket = try XCTUnwrap(mounted.session.transportObservationGate.captureTicket())

        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let loading = try XCTUnwrap(model.loadTask)

        // Do not give SwiftUI, KVO or its queued reconciliation a turn. The
        // real borrowed AVKit controller must already be detached right here.
        XCTAssertNil(model.nativeFullscreen)
        XCTAssertTrue(mounted.session.isRetired)
        XCTAssertNil(mounted.controller.player)
        XCTAssertNil(mounted.controller.delegate)
        XCTAssertFalse(mounted.session.transportObservationGate.accepts(ticket))
        XCTAssertTrue(model.player === mounted.session.player)
        XCTAssertTrue(model.player?.currentItem === oldItem,
                      "Retirement precedes the task's same-player item reset")
        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.userWantsPlayback)

        await validation.waitUntilEntered()
        XCTAssertEqual(validation.pendingCount, 1)
        XCTAssertTrue(model.player === mounted.session.player)
        XCTAssertNil(model.player?.currentItem)
        XCTAssertNil(mounted.controller.player,
                     "The old controller cannot follow the reused player's replacement item")
        model.cleanup()
        validation.finish()
        await loading.value
        withExtendedLifetime(mounted) {}
    }

    func testAutomaticNativeFailoverDetachesTheFailedSourcesFullscreenLease() async throws {
        let validation = FullscreenSourceValidationBarrier()
        let model = makeModel(validateNativeSource: validation.wait)
        defer { model.cleanup(); validation.finish() }
        let mounted = try mountFullscreenHost(model)
        let source = try XCTUnwrap(model.activeSource)
        let attempt = model.loadRequestID
        model.nativeStartupRetryAttemptsBySource[source.id] = 1

        model.handleSourceStartupFailure(source, reason: "HTTP 403", expectedRequestID: attempt)
        let loading = try XCTUnwrap(model.loadTask)

        XCTAssertNotEqual(model.activeSource?.id, source.id)
        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.autoFailoverCount, 1)
        XCTAssertNil(model.nativeFullscreen)
        XCTAssertTrue(mounted.session.isRetired)
        XCTAssertNil(mounted.controller.player)
        XCTAssertNil(mounted.controller.delegate)
        XCTAssertTrue(model.userWantsPlayback)
        // Late AVKit callbacks from the retired source cannot Pause its successor.
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: mounted.session)
        model.endNativeFullscreen(mounted.session)
        XCTAssertTrue(model.userWantsPlayback)

        await validation.waitUntilEntered()
        XCTAssertEqual(validation.pendingCount, 1)
        XCTAssertTrue(model.player === mounted.session.player)
        XCTAssertNil(mounted.controller.player)
        model.cleanup()
        validation.finish()
        await loading.value
        withExtendedLifetime(mounted) {}
    }

    func testPlayerReplacementAndCancellationSynchronouslyDetachTheirExactPresentation() throws {
        for operation in ["replace-player", "cancel-attempt"] {
            let model = makeModel()
            defer { model.cleanup() }
            let mounted = try mountFullscreenHost(model)
            let oldItem = mounted.session.item
            let ticket = try XCTUnwrap(mounted.session.transportObservationGate.captureTicket())

            if operation == "replace-player" {
                model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            } else { model.cancelLoading() }

            XCTAssertNil(model.nativeFullscreen, operation)
            XCTAssertTrue(mounted.session.isRetired, operation)
            XCTAssertNil(mounted.controller.player, operation)
            XCTAssertNil(mounted.controller.delegate, operation)
            XCTAssertFalse(mounted.session.transportObservationGate.accepts(ticket), operation)
            XCTAssertTrue(mounted.session.player.currentItem === oldItem,
                          "Presentation retirement itself never replaces or clears an item")
            XCTAssertTrue(model.userWantsPlayback, operation)
            XCTAssertNil(model.loadTask, operation)
            withExtendedLifetime(mounted) {}
        }
    }

    func testRetainedPiPClosingAndRestoreKeepTheSameBoundPlayerAndLease() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let mounted = try mountFullscreenHost(model)
        let item = mounted.session.item
        let attempt = model.loadRequestID
        let source = model.activeSource?.id
        // Controlled PiP lifecycle policy, not a claim that this local
        // composition can decode or open a physical PiP window.
        mounted.session.beginClosingPresentation()
        mounted.session.finishClosingTransition(cancelled: false, retainingPictureInPicture: true)
        XCTAssertFalse(mounted.session.isRetired)
        XCTAssertTrue(mounted.session.permitsTransportObservation(pictureInPictureActive: true))
        XCTAssertTrue(mounted.controller.player === mounted.session.player)

        mounted.session.finishRestoringPresentation()

        XCTAssertFalse(mounted.session.isRetired)
        XCTAssertTrue(model.nativeFullscreen === mounted.session)
        XCTAssertTrue(model.ownsNativeFullscreen(mounted.session))
        XCTAssertTrue(mounted.controller.player === mounted.session.player)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertNil(model.loadTask)
        withExtendedLifetime(mounted) {}
    }

    func testOrdinaryDoneRetiresOnlyAtFinishWithoutMutatingThePausedTransport() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let mounted = try mountFullscreenHost(model)
        let item = mounted.session.item
        let attempt = model.loadRequestID
        let source = model.activeSource?.id

        mounted.session.beginClosingPresentation()
        mounted.session.finishClosingTransition(cancelled: false, retainingPictureInPicture: false)
        XCTAssertFalse(mounted.session.isRetired,
                       "The transition itself is not a transport replacement or a completed presentation exit")
        XCTAssertTrue(mounted.controller.player === mounted.session.player)
        XCTAssertTrue(model.nativeFullscreen === mounted.session)

        model.endNativeFullscreen(mounted.session)

        XCTAssertTrue(mounted.session.isRetired)
        XCTAssertNil(model.nativeFullscreen)
        XCTAssertNil(mounted.controller.player)
        XCTAssertTrue(model.player === mounted.session.player)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.audioPreparationTask)
        withExtendedLifetime(mounted) {}
    }

    func testRetiredPresentationCannotReenableControlsOrDetachANewerLease() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let mounted = try mountFullscreenHost(model)
        model.endNativeFullscreen(mounted.session)
        XCTAssertNil(mounted.controller.player)
        mounted.presenter.testPresented = nil // The recording presenter has no real UIKit transition.
        XCTAssertTrue(model.player === mounted.session.player)
        XCTAssertTrue(model.player?.currentItem === mounted.session.item)
        XCTAssertEqual(model.loadRequestID, mounted.session.attemptID)
        // The actual AVKit controller correctly reports no rendered frame for
        // this empty composition. Restore the test's controlled readiness flag
        // to admit a second lease; do not claim the composition decoded video.
        model.isVideoReadyForDisplay = true
        let replacement = try openControls(model)
        mounted.host.reconcile(replacement)
        let replacementController = try XCTUnwrap(mounted.presenter.testPresented as? AVPlayerViewController)

        mounted.session.finishRestoringPresentation()
        mounted.session.finishClosingTransition(cancelled: true, retainingPictureInPicture: true)
        mounted.session.retire()
        model.endNativeFullscreen(mounted.session)
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: mounted.session)

        XCTAssertTrue(mounted.session.isRetired)
        XCTAssertFalse(mounted.session.controlsAreActive)
        XCTAssertNil(mounted.session.transportObservationGate.captureTicket())
        XCTAssertTrue(model.nativeFullscreen === replacement)
        XCTAssertTrue(model.ownsNativeFullscreen(replacement))
        XCTAssertTrue(replacementController.player === replacement.player)
        XCTAssertFalse(replacement.isRetired)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNil(model.loadTask)
        withExtendedLifetime(mounted) {}
    }

    func testRestoreFindsSameWindowTopmostPresenterWithoutDismissingExistingUI() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let root = FullscreenPresentationTestController()
        let sheet = FullscreenPresentationTestController()
        let top = FullscreenPresentationTestController()
        window.rootViewController = root
        window.addSubview(root.view)
        window.addSubview(sheet.view)
        window.addSubview(top.view)
        root.testPresented = sheet
        sheet.testPresenting = root
        sheet.testPresented = top
        top.testPresenting = sheet
        let retainedPlayerController = FullscreenPresentationTestController()

        guard case .present(let presenter)? = NativeFullscreenPresentationResolver.target(
            in: window, markerWindow: nil, restoring: retainedPlayerController) else {
            return XCTFail("Restore must use the existing same-window presentation chain")
        }
        XCTAssertTrue(presenter === top)
        XCTAssertTrue(root.presentedViewController === sheet)
        XCTAssertTrue(sheet.presentedViewController === top)
        XCTAssertEqual(root.dismissCount + sheet.dismissCount + top.dismissCount, 0)
        XCTAssertNil(retainedPlayerController.presentingViewController)
    }

    func testRestoreAcceptsOwnedPresentedControllerWhenFullscreenDetachedMarker() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let root = FullscreenPresentationTestController()
        let retained = FullscreenPresentationTestController()
        window.rootViewController = root
        root.testPresented = retained
        retained.testPresenting = root

        XCTAssertNil(retained.viewIfLoaded?.window)
        guard case .retained? = NativeFullscreenPresentationResolver.target(
            in: window, markerWindow: nil, restoring: retained) else {
            return XCTFail("The retained same-window presentation does not depend on the covered marker")
        }
        XCTAssertTrue(root.presentedViewController === retained)
        XCTAssertEqual(root.dismissCount + retained.dismissCount, 0)
    }

    func testRestoreRejectsDifferentWindowOrForeignPresentation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let otherWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let root = FullscreenPresentationTestController()
        let foreign = FullscreenPresentationTestController()
        let retained = FullscreenPresentationTestController()
        window.rootViewController = root
        window.addSubview(root.view)
        otherWindow.rootViewController = foreign
        otherWindow.addSubview(foreign.view)

        XCTAssertNil(NativeFullscreenPresentationResolver.target(in: window,
            markerWindow: otherWindow, restoring: retained))
        retained.testPresenting = foreign
        foreign.testPresented = retained
        XCTAssertNil(NativeFullscreenPresentationResolver.target(in: window,
            markerWindow: window, restoring: retained), "Never steal a controller owned by another presentation")
        retained.testPresenting = nil
        root.testPresented = foreign
        XCTAssertNil(NativeFullscreenPresentationResolver.target(in: window,
            markerWindow: nil, restoring: retained), "The top presenter must actually belong to the anchored window")
        XCTAssertEqual(root.dismissCount + foreign.dismissCount + retained.dismissCount, 0)
    }

    func testRestoreRejectsPresentationTransitionsInsteadOfCompletingEarly() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let root = FullscreenPresentationTestController()
        let retained = FullscreenPresentationTestController()
        window.rootViewController = root
        window.addSubview(root.view)
        root.testPresented = retained
        retained.testPresenting = root
        retained.testBeingDismissed = true
        XCTAssertNil(NativeFullscreenPresentationResolver.target(in: window,
            markerWindow: nil, restoring: retained))
        retained.testBeingDismissed = false
        root.testBeingPresented = true
        XCTAssertNil(NativeFullscreenPresentationResolver.target(in: window,
            markerWindow: window, restoring: retained))
        root.testBeingPresented = false
        guard case .retained? = NativeFullscreenPresentationResolver.target(in: window,
            markerWindow: nil, restoring: retained) else {
            return XCTFail("A completed transition restores the same retained presentation")
        }
    }

    func testSuccessfulRetainedRestorationRebindsControlsWithoutChangingPausedTransport() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let player = FullscreenTransportSpyPlayer()
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        model.player = player
        model.togglePlayPause()
        let session = try openControls(model)
        let item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID, source = model.activeSource?.id
        let oldTicket = try XCTUnwrap(session.transportObservationGate.captureTicket())
        session.beginClosingPresentation()
        session.finishClosingTransition(cancelled: false, retainingPictureInPicture: true)

        session.finishRestoringPresentation()

        XCTAssertFalse(session.isClosing)
        XCTAssertTrue(session.controlsAreActive)
        XCTAssertFalse(session.transportObservationGate.accepts(oldTicket))
        XCTAssertNotNil(session.transportObservationGate.captureTicket())
        XCTAssertTrue(model.ownsNativeFullscreen(session))
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(player.playCount, 0)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.audioPreparationTask)
    }

    func testPausedEntryBorrowsExactTransportWithoutLoadingOrAutostart() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let player = try XCTUnwrap(model.player)
        let item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID, source = model.activeSource?.id

        XCTAssertTrue(model.canShowNativeFullscreen)
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)

        XCTAssertTrue(session.player === player)
        XCTAssertTrue(session.item === item)
        XCTAssertEqual(session.attemptID, attempt)
        XCTAssertEqual(session.sourceID, source)
        XCTAssertTrue(model.ownsNativeFullscreen(session))
        XCTAssertFalse(model.canShowNativeFullscreen)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.networkPathMonitor)
        XCTAssertFalse(model.didStartPlayback, "Presentation must not mount or load the session again")
        model.beginNativeFullscreen()
        XCTAssertTrue(model.nativeFullscreen === session, "Repeated entry must not replace the active lease")
    }

    func testRepeatedExitAndReentryPreservePlayerItemAttemptSourceAndPausedIntent() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let player = try XCTUnwrap(model.player)
        let item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID, source = model.activeSource?.id
        var presentationIDs = Set<UUID>()

        for _ in 0..<3 {
            model.beginNativeFullscreen()
            let session = try XCTUnwrap(model.nativeFullscreen)
            XCTAssertTrue(presentationIDs.insert(session.id).inserted)
            model.endNativeFullscreen(session)
            model.endNativeFullscreen(session)

            XCTAssertNil(model.nativeFullscreen)
            XCTAssertTrue(model.canShowNativeFullscreen)
            XCTAssertTrue(model.player === player)
            XCTAssertTrue(player.currentItem === item)
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertEqual(model.activeSource?.id, source)
            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertEqual(model.playbackState, .paused(.native))
            XCTAssertEqual(player.rate, 0)
            XCTAssertNil(model.loadTask)
        }
    }

    func testEntryDoesNotInventFullscreenForMissingUnreadyWebOrPiPTransport() {
        let model = makeModel()
        defer { model.cleanup() }
        let player = model.player

        model.isVideoReadyForDisplay = false
        model.beginNativeFullscreen()
        XCTAssertNil(model.nativeFullscreen)

        model.isVideoReadyForDisplay = true
        model.player = nil
        model.beginNativeFullscreen()
        XCTAssertNil(model.nativeFullscreen)

        model.player = AVPlayer()
        model.beginNativeFullscreen()
        XCTAssertNil(model.nativeFullscreen)

        model.player = player
        model.error = "An existing attempt failed"
        model.beginNativeFullscreen()
        XCTAssertNil(model.nativeFullscreen)

        model.error = nil
        model.isPictureInPictureActive = true
        model.beginNativeFullscreen()
        XCTAssertNil(model.nativeFullscreen)

        model.isPictureInPictureActive = false
        if let source = model.activeSource { model.forceWebEmbedSourceIDs.insert(source.id) }
        XCTAssertTrue(model.isUsingWebEmbed)
        model.beginNativeFullscreen()
        XCTAssertNil(model.nativeFullscreen)
    }

    func testExplicitFullscreenPlayRenewsPauseIntentWithoutIssuingAnotherPlayOrLoad() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let session = try openControls(model)
        let attempt = model.loadRequestID

        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertEqual(session.player.rate, 0, "The observer must not issue its own second Play")
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertNil(model.loadTask)
        model.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertTrue(model.userWantsPlayback, "A subsequent transport observation must not repause system Play")
        XCTAssertEqual(model.playbackState, .playing(.native))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player?.currentItem === session.item)
    }

    func testAcceptedFullscreenResumeArmsRecoveryBeforeAnyPlayingObservationWithoutIssuingAnotherPlay() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let player = FullscreenTransportSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.player = player
        model.togglePlayPause()
        let session = try openControls(model)
        let request = model.loadRequestID, source = model.activeSource?.id
        XCTAssertFalse(model.isPlaybackWatchdogArmed)

        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)

        let watchdog = try XCTUnwrap(model.playbackWatchdogTask)
        XCTAssertTrue(model.isPlaybackWatchdogArmed)
        XCTAssertFalse(watchdog.isCancelled)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNotEqual(model.playbackState, .playing(.native), "Accepted Play is not decoded/playing evidence")
        model.handleNativeTimeControlStatusChanged(.waitingToPlayAtSpecifiedRate)
        XCTAssertTrue(model.isPlaybackWatchdogArmed, "Waiting for data must not disarm accepted resume recovery")
        XCTAssertFalse(watchdog.isCancelled)
        XCTAssertEqual(player.playCount, 0, "AVKit already issued Play; the observer must not repeat it")
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === session.item)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.audioPreparationTask)
    }

    func testAcceptedFullscreenPauseCancelsTheWatchdogArmedByItsPreviousResume() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let session = try openControls(model)
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        let watchdog = try XCTUnwrap(model.playbackWatchdogTask)
        XCTAssertTrue(model.isPlaybackWatchdogArmed)

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)

        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        XCTAssertTrue(watchdog.isCancelled)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertNil(model.loadTask)
    }

    func testAcceptedFullscreenResumeReachesBoundedStallValidationWithoutAnotherPlayingEvent() async throws {
        let delay = FullscreenResumeDelayGate()
        let model = makeModel(timing: .init(monotonicNow: { 0 }, sleep: delay.wait))
        defer { model.cleanup(); delay.finishAll() }
        let player = FullscreenWaitingTransportSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.player = player
        model.togglePlayPause()
        let session = try openControls(model)
        let source = model.activeSource?.id, request = model.loadRequestID
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        let resumeValidation = try XCTUnwrap(model.foregroundResumeValidationTask)
        let watchdog = try XCTUnwrap(model.playbackWatchdogTask)
        for _ in 0..<1_000 {
            if delay.pendingCount == 1 { break }
            await Task.yield()
        }
        XCTAssertEqual(delay.requested, [.seconds(8)], "Resume uses one bounded observation budget")
        guard delay.pendingCount == 1 else {
            XCTFail("The controlled eight-second resume deadline did not arrive")
            return // The defer drains current and future waits; never await an unreleased task.
        }
        XCTAssertNil(model.stallValidationTask)

        delay.releaseNext()
        await resumeValidation.value

        let stallValidation = try XCTUnwrap(model.stallValidationTask)
        XCTAssertFalse(stallValidation.isCancelled)
        XCTAssertTrue(model.isPlaybackWatchdogArmed)
        XCTAssertEqual(model.playbackState, .recovering(.native))
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(player.playCount, 0, "Bounded observation does not repeat AVKit's Play")
        XCTAssertNil(model.loadTask)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertTrue(player.currentItem === session.item)

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        XCTAssertTrue(watchdog.isCancelled)
        XCTAssertTrue(stallValidation.isCancelled)
        XCTAssertTrue(resumeValidation.isCancelled)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(player.playCount, 0)
        await stallValidation.value
    }

    func testRejectedFullscreenResumeCallbacksCannotArmRecoveryOrChangePauseIntent() throws {
        for rejection in ["source", "item", "closed", "inactive-controls", "model-owned", "background"] {
            let model = makeModel()
            defer { model.cleanup() }
            model.togglePlayPause()
            let session = try openControls(model)
            switch rejection {
            case "source": model.currentSourceIndex = (model.currentSourceIndex + 1) % model.sessions.count
            case "item": session.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
            case "closed": model.endNativeFullscreen(session)
            case "inactive-controls": session.controlsAreActive = false
            case "background":
                model.setViewingPiPOwnership(false)
                model.handleScenePhaseChange(.background)
            default: break
            }
            if rejection == "model-owned" {
                model.withModelOwnedNativeRateCommand {
                    model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
                }
            } else { model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session) }
            XCTAssertFalse(model.isPlaybackWatchdogArmed, rejection)
            XCTAssertNil(model.playbackWatchdogTask, rejection)
            XCTAssertFalse(model.userWantsPlayback, rejection)
            XCTAssertNil(model.loadTask, rejection)
            XCTAssertNil(model.audioPreparationTask, rejection)
        }
    }

    func testFullscreenPauseRevokesPendingAudioRecoveryAndForegroundResume() async throws {
        let barrier = FullscreenAudioPreparationBarrier()
        let model = makeModel(prepareAudio: barrier.wait)
        defer { model.cleanup(); barrier.completeAll() }
        model.togglePlayPause()
        let session = try openControls(model)
        model.togglePlayPause()
        let preparation = try XCTUnwrap(model.audioPreparationTask)
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(2)
        while barrier.pendingCount == 0, clock.now < deadline { await Task.yield() }
        XCTAssertEqual(barrier.pendingCount, 1, "Reach the controlled preparation boundary, not a sleep guess")

        let stall = Task<Void, Never> { await Task.yield() }
        let foreground = Task<Void, Never> { await Task.yield() }
        model.stallValidationTask = stall
        model.foregroundResumeValidationTask = foreground
        model.shouldResumeAfterForeground = true
        model.pendingRetryAfterNetworkRestore = true
        let attempt = model.loadRequestID

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)

        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertFalse(model.pendingRetryAfterNetworkRestore)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertTrue(preparation.isCancelled)
        XCTAssertTrue(stall.isCancelled)
        XCTAssertTrue(foreground.isCancelled)
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        barrier.completeAll()
        await preparation.value
        await stall.value
        await foreground.value
        model.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertFalse(model.userWantsPlayback, "A late native observation cannot revoke the accepted Pause")
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(session.player.rate, 0)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player?.currentItem === session.item)
        XCTAssertNil(model.loadTask)
    }

    func testNonUserRateReasonsNeverChangePlayOrPauseIntent() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        let reasons: [AVPlayer.RateDidChangeReason] = [
            .appBackgrounded, .audioSessionInterrupted, .setRateFailed,
            AVPlayer.RateDidChangeReason(rawValue: "unrecognized-system-reason")
        ]

        for reason in reasons {
            model.handleFullscreenRateCommand(0, reason: reason, session: session)
            XCTAssertTrue(model.userWantsPlayback)
            XCTAssertEqual(model.playbackState, .playing(.native))
        }
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        for reason in reasons {
            model.handleFullscreenRateCommand(1, reason: reason, session: session)
            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertEqual(model.playbackState, .paused(.native))
        }
    }

    func testInactiveOrClosingSystemControlsCannotChangeIntent() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)
        session.controlsAreActive = false
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback)

        session.controlsAreActive = true
        session.isClosing = true
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))
    }

    func testFullscreenDismissalTransitionGuardsRateChangesAndCancellationRestoresControls() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        model.isPictureInPictureActive = true
        let beforeCloseTicket = try XCTUnwrap(session.transportObservationGate.captureTicket())

        session.beginClosingPresentation()
        XCTAssertTrue(session.isClosing)
        XCTAssertFalse(session.controlsAreActive)
        XCTAssertFalse(session.permitsTransportObservation(pictureInPictureActive: true))
        XCTAssertNil(session.transportObservationGate.captureTicket())
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback, "Native Done's transition is not a PiP Pause")

        session.finishClosingTransition(cancelled: true, retainingPictureInPicture: true)
        XCTAssertFalse(session.isClosing)
        XCTAssertTrue(session.controlsAreActive)
        XCTAssertFalse(session.transportObservationGate.accepts(beforeCloseTicket),
                       "Cancelled dismissal must not revive a previously queued observation")
        XCTAssertNotNil(session.transportObservationGate.captureTicket())
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertFalse(model.userWantsPlayback, "Cancelled dismissal restores the original control owner")
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        model.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertTrue(model.userWantsPlayback)

        model.isPictureInPictureActive = false
        session.beginClosingPresentation()
        session.finishClosingTransition(cancelled: false, retainingPictureInPicture: false)
        XCTAssertTrue(session.isClosing)
        XCTAssertFalse(session.controlsAreActive)
        XCTAssertNil(session.transportObservationGate.captureTicket())
        XCTAssertFalse(session.permitsTransportObservation(pictureInPictureActive: false))
        XCTAssertFalse(session.permitsTransportObservation(pictureInPictureActive: true),
                       "A late PiP claim cannot reactivate an ordinary completed Close")
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))
    }

    func testQueuedFullscreenPauseCannotCrossDismissalTransitionButFreshPiPPauseIsAdmitted() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        model.isPictureInPictureActive = true
        let gate = session.transportObservationGate
        let beforeTransitionTicket = try XCTUnwrap(gate.captureTicket())
        session.beginClosingPresentation()
        let disabledOriginTicket = gate.captureTicket()
        XCTAssertNil(disabledOriginTicket)
        session.finishClosingTransition(cancelled: false, retainingPictureInPicture: true)
        XCTAssertTrue(session.permitsTransportObservation(pictureInPictureActive: true))

        // Deliver after reopening, exactly like a previously enqueued KVO
        // block. Never obtain a new ticket at delivery for an old callback.
        func deliverPaused(_ ticket: UUID?) {
            guard let ticket, gate.accepts(ticket), model.ownsNativeFullscreen(session),
                  session.permitsTransportObservation(pictureInPictureActive: model.isPictureInPictureActive) else { return }
            model.handleNativeTimeControlStatusChanged(.paused)
        }
        deliverPaused(beforeTransitionTicket)
        deliverPaused(disabledOriginTicket)
        XCTAssertTrue(model.userWantsPlayback, "Old dismissal KVO cannot impersonate a later PiP Pause")
        XCTAssertEqual(model.playbackState, .playing(.native))

        let freshPiPTicket = try XCTUnwrap(gate.captureTicket())
        XCTAssertNotEqual(freshPiPTicket, beforeTransitionTicket)
        deliverPaused(freshPiPTicket)
        XCTAssertFalse(model.userWantsPlayback, "An actual current PiP Pause remains observable")
        XCTAssertEqual(model.playbackState, .paused(.native))
    }

    func testRetainedPiPPauseSurvivesBackgroundStopAndForegroundWithoutNewPlay() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let player = FullscreenTransportSpyPlayer()
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        model.player = player
        let session = try openControls(model)
        let item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID, source = model.activeSource?.id
        // Controlled ownership flags exercise the model policy, not real PiP.
        model.isPictureInPictureActive = true
        model.handleScenePhaseChange(.background)
        session.beginClosingPresentation()
        session.finishClosingTransition(cancelled: false, retainingPictureInPicture: true)

        XCTAssertTrue(session.isClosing, "PiP Stop still owns release of the dismissed fullscreen lease")
        XCTAssertTrue(session.controlsAreActive)
        XCTAssertTrue(session.permitsTransportObservation(pictureInPictureActive: true),
                      "The host must keep observing its retained PiP transport after Native Done")
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        model.handleNativeTimeControlStatusChanged(.paused)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))

        model.handlePictureInPictureActivityChanged(false, isBackgrounded: true)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        // The delegate's successful PiP-stop path releases presentation only.
        model.endNativeFullscreen(session)
        model.handleScenePhaseChange(.active)

        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertFalse(model.isPlaybackSessionRetired)
        XCTAssertNil(model.nativeFullscreen)
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(player.playCount, 0, "Foreground must not undo an explicit retained-PiP Pause")
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertNil(model.pictureInPicturePreparationTask)
        XCTAssertNil(model.loadTask)
    }

    func testRetainedPiPPlayPreservesTransportAndRejectsStaleLeaseWithoutDuplicatePlay() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let player = FullscreenTransportSpyPlayer()
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        model.player = player
        model.togglePlayPause()
        let session = try openControls(model)
        let item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID, source = model.activeSource?.id
        model.isPictureInPictureActive = true
        session.beginClosingPresentation()
        session.finishClosingTransition(cancelled: false, retainingPictureInPicture: true)

        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        model.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))
        XCTAssertTrue(model.nativeFullscreen === session)
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(player.playCount, 0, "AVKit already issued Play; the observer must not duplicate it")
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertNil(model.loadTask)

        model.currentSourceIndex = (model.currentSourceIndex + 1) % model.providedSessions.count
        XCTAssertFalse(model.ownsNativeFullscreen(session))
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback, "Retained PiP does not bypass exact source ownership")
        XCTAssertEqual(player.playCount, 0)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
    }

    func testModelOwnedRateCommandsCannotImpersonateSystemPauseOrPlay() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)

        model.withModelOwnedNativeRateCommand {
            model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
            model.withModelOwnedNativeRateCommand {
                model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
            }
            model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        }
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        XCTAssertFalse(model.userWantsPlayback, "The owned-command depth must return to zero")
        model.withModelOwnedNativeRateCommand {
            model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        }
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(session.player.rate, 0, "Intent observation must not issue transport commands")
    }

    func testSuspendedInlineLayerCannotResetSharedFullscreenIdentityOrReattachPlayer() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        let binding = model.nativeMeasurementBinding
        let playerToken = try XCTUnwrap(binding.playerToken(for: session.player))
        let itemToken = try XCTUnwrap(binding.token(for: session.item, attempt: session.attemptID))
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        defer { view.dismantlePlaybackBinding() }
        view.measurementBinding = binding
        view.configurePhysicalMeasurement(identifier: "fullscreen-test-inline",
                                          attemptID: session.attemptID, pane: nil)
        view.player = session.player
        let initial = try measurement(view)
        XCTAssertEqual(initial["playerToken"] as? String, playerToken.uuidString)
        XCTAssertEqual(initial["itemToken"] as? String, itemToken.uuidString)

        for _ in 0..<3 {
            view.suspendsInlinePlayback = true
            XCTAssertNil(view.player)
            view.player = session.player
            XCTAssertNil(view.player, "A retained update must not compete with fullscreen rendering")
            XCTAssertEqual(try measurement(view)["measurementAvailable"] as? Bool, false)
            XCTAssertEqual(binding.playerToken(for: session.player), playerToken)
            XCTAssertEqual(binding.token(for: session.item, attempt: session.attemptID), itemToken)
            XCTAssertTrue(model.player === session.player)
            XCTAssertTrue(session.player.currentItem === session.item)
            XCTAssertEqual(session.player.rate, 0)

            view.suspendsInlinePlayback = false
            view.player = session.player
            let restored = try measurement(view)
            XCTAssertEqual(restored["playerToken"] as? String, playerToken.uuidString)
            XCTAssertEqual(restored["itemToken"] as? String, itemToken.uuidString)
            XCTAssertEqual(restored["attemptToken"] as? String, session.attemptID.uuidString)
        }
        view.dismantlePlaybackBinding()
        XCTAssertEqual(binding.playerToken(for: session.player), playerToken,
                       "Discarding a surface must not discard the model-owned identity")
        XCTAssertEqual(binding.token(for: session.item, attempt: session.attemptID), itemToken)
    }

    func testTemporarilyUnboundOrdinaryLayerDoesNotResetModelMeasurementIdentity() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let player = try XCTUnwrap(model.player)
        let item = try XCTUnwrap(player.currentItem)
        let attempt = model.loadRequestID
        let binding = model.nativeMeasurementBinding
        let playerToken = try XCTUnwrap(binding.playerToken(for: player))
        let itemToken = try XCTUnwrap(binding.token(for: item, attempt: attempt))
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        defer { view.dismantlePlaybackBinding() }
        view.measurementBinding = binding
        view.configurePhysicalMeasurement(identifier: "temporarily-unbound-inline",
                                          attemptID: attempt, pane: nil)
        XCTAssertFalse(view.suspendsInlinePlayback)

        for _ in 0..<3 {
            view.player = nil
            XCTAssertNil(view.player)
            XCTAssertEqual(try measurement(view)["measurementAvailable"] as? Bool, false)
            XCTAssertEqual(binding.playerToken(for: player), playerToken,
                           "An unbound render layer does not retire the model's player")
            XCTAssertEqual(binding.token(for: item, attempt: attempt), itemToken,
                           "Unavailable render evidence must not reset the unchanged model item")
            XCTAssertTrue(model.player === player)
            XCTAssertTrue(player.currentItem === item)
            XCTAssertEqual(model.loadRequestID, attempt)

            view.player = player
            let restored = try measurement(view)
            XCTAssertEqual(restored["measurementAvailable"] as? Bool, true)
            XCTAssertEqual(restored["playerToken"] as? String, playerToken.uuidString)
            XCTAssertEqual(restored["itemToken"] as? String, itemToken.uuidString)
            XCTAssertEqual(restored["attemptToken"] as? String, attempt.uuidString)
        }
    }

    func testNonfiniteFullscreenRateCannotChangeIntent() throws {
        let model = makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        let session = try openControls(model)
        for rate: Float in [.nan, .infinity, -.infinity] {
            model.handleFullscreenRateCommand(rate, reason: .setRateCalled, session: session)
            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertEqual(model.playbackState, .paused(.native))
        }
    }

    func testBackgroundRateCallbackIsNotUserPauseAndCannotRevokeResumeIntent() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        model.setViewingPiPOwnership(false)
        model.handleScenePhaseChange(.background)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.shouldResumeAfterForeground)

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.shouldResumeAfterForeground)
        XCTAssertEqual(model.playbackState, .paused(.native))
    }

    func testStaleSourceCallbackCannotChangeIntentOfNewSelection() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        model.currentSourceIndex = (model.currentSourceIndex + 1) % model.providedSessions.count
        let currentSource = model.activeSource?.id
        XCTAssertNotEqual(currentSource, session.sourceID)
        XCTAssertFalse(model.ownsNativeFullscreen(session))

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.activeSource?.id, currentSource)
        XCTAssertEqual(model.loadRequestID, session.attemptID)
        XCTAssertNil(model.loadTask)
    }

    func testStaleItemCallbackCannotChangeIntentAfterReplacement() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        let replacement = AVPlayerItem(asset: AVMutableComposition())
        session.player.replaceCurrentItem(with: replacement)
        XCTAssertFalse(model.ownsNativeFullscreen(session))

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.player === session.player)
        XCTAssertTrue(model.player?.currentItem === replacement)
        XCTAssertEqual(model.loadRequestID, session.attemptID)
    }

    func testStalePlayerCallbackCannotChangeIntentAfterReplacement() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        let replacement = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.player = replacement
        XCTAssertFalse(model.ownsNativeFullscreen(session))

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        model.endNativeFullscreen(session)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.player === replacement)
        XCTAssertEqual(replacement.rate, 0)
        XCTAssertEqual(model.loadRequestID, session.attemptID)
    }

    func testStaleAttemptCallbackCannotReviveCancelledAttempt() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let session = try openControls(model)
        model.cancelLoading()
        let attempt = model.loadRequestID
        XCTAssertNotEqual(attempt, session.attemptID)
        XCTAssertFalse(model.ownsNativeFullscreen(session))

        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.audioPreparationTask)
    }

    func testOldPresentationExitAndRateCallbackCannotRetireCurrentPresentation() throws {
        let model = makeModel()
        defer { model.cleanup() }
        let old = try openControls(model)
        model.endNativeFullscreen(old)
        let current = try openControls(model)
        XCTAssertNotEqual(current.id, old.id)

        model.endNativeFullscreen(old)
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: old)

        XCTAssertTrue(model.nativeFullscreen === current)
        XCTAssertTrue(model.ownsNativeFullscreen(current))
        XCTAssertFalse(model.ownsNativeFullscreen(old))
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(current.player === old.player)
        XCTAssertTrue(current.item === old.item)
        XCTAssertEqual(current.attemptID, old.attemptID)
    }

    func testStopMakesLateFullscreenCallbacksAndEntryInert() throws {
        let model = makeModel()
        let session = try openControls(model)
        model.cleanup()
        let retiredAttempt = model.loadRequestID

        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        model.endNativeFullscreen(session)
        model.beginNativeFullscreen()
        model.cleanup()

        XCTAssertTrue(model.isPlaybackSessionRetired)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.ownsNativeFullscreen(session))
        XCTAssertFalse(model.canShowNativeFullscreen)
        XCTAssertNil(model.nativeFullscreen)
        XCTAssertNil(model.player)
        XCTAssertEqual(session.player.rate, 0)
        XCTAssertEqual(model.playbackState, .idle)
        XCTAssertEqual(model.loadRequestID, retiredAttempt)
        XCTAssertNil(model.audioPreparationTask)
        XCTAssertNil(model.loadTask)
    }

    private func waitForForegroundObservationCondition(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + timeout
        while !condition(), clock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        }
        return condition()
    }

    func testSingleStallValidationIsSixSecondsAndRepeatedNoticesCannotRestartIt() async throws {
        let gate = SingleResumeTestClock()
        let model = makeModel(validateNativeSource: { _, _ in .invalid("Controlled failure") }, timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition())
        let player = SingleResumeTestPlayer(playerItem: item); player.control = .playing; model.player = player
        let source = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        model.validateRecoverableStall(for: source, reason: "Frozen.", expectedItem: item, requestID: request)
        let task = try XCTUnwrap(model.stallValidationTask)
        for _ in 0..<12 {
            await gate.waitForSample()
            model.validateRecoverableStall(for: source, reason: "Repeated stalled notification", expectedItem: item, requestID: request)
            gate.advance()
        }
        await task.value
        XCTAssertEqual(gate.now, 6)
        XCTAssertTrue(model.failedSourceIDs.contains(source.id), "Playing status cannot excuse a frozen media clock")
        XCTAssertNotEqual(model.loadRequestID, request)
    }

    func testRankedFullscreenUsesTheSameResumeBudgetWithoutRepeatingPlay() async throws {
        let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition())
        let player = SingleResumeTestPlayer(playerItem: item); model.player = player
        let session = try openControls(model)
        model.handleFullscreenRateCommand(0, reason: .setRateCalled, session: session)
        model.handleFullscreenRateCommand(1, reason: .setRateCalled, session: session)
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        await gate.waitForSample()
        player.seconds = 1; gate.advance(); await task.value
        XCTAssertEqual(player.plays, 0)
        XCTAssertEqual(player.immediatePlays, 0)
        XCTAssertTrue(model.player === player && player.currentItem === item)
        XCTAssertEqual(model.playbackState, .playing(.native))
    }

    func testSingleResumeWindowRequiresExplicitExpiredLiveRange() {
        let policy = SingleNativeResumeWindowPolicy.self
        XCTAssertEqual(policy.catchUpTarget(position: 10, isLive: true, ranges: [(20, 40)]), 37)
        let rejected: [[(Double, Double)]] = [[], [(20, 20)], [(40, 20)], [(.nan, 40)], [(-10, 40)]]
        for ranges in rejected {
            XCTAssertNil(policy.catchUpTarget(position: 10, isLive: true, ranges: ranges))
        }
        XCTAssertNil(policy.catchUpTarget(position: 10, isLive: false, ranges: [(20, 40)]))
        XCTAssertNil(policy.catchUpTarget(position: 25, isLive: true, ranges: [(20, 40)]))
        XCTAssertNil(policy.catchUpTarget(position: 19.8, isLive: true, ranges: [(20, 40)]))
        XCTAssertNil(policy.catchUpTarget(position: 41, isLive: true, ranges: [(20, 40)]))
        XCTAssertNil(policy.catchUpTarget(position: 15, isLive: true, ranges: [(0, 10), (20, 40)]))
    }

    func testSingleInlineResumeWaitsForProgressAndKeepsTheOwner() async throws {
        let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition())
        let player = SingleResumeTestPlayer(playerItem: item); model.player = player
        let attempt = model.loadRequestID
        model.togglePlayPause(); model.togglePlayPause()
        await model.audioPreparationTask?.value
        XCTAssertEqual(model.playbackState, .recovering(.native))
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        await gate.waitForSample()
        XCTAssertFalse(model.isPlaybackWatchdogArmed, "Resume owns the one bounded observation window")
        model.handleNativeTimeControlStatusChanged(.playing)
        XCTAssertEqual(model.playbackState, .recovering(.native), "KVO cannot substitute for advancing video")
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        player.seconds = 1
        gate.advance()
        await task.value
        XCTAssertEqual(model.playbackState, .playing(.native))
        XCTAssertTrue(model.player === player && player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(player.plays, 1)
        XCTAssertTrue(player.seeks.isEmpty)
    }

    func testSingleResumeCannotMistakePlayingStatusForProgressOrStackTenMoreSeconds() async throws {
        let gate = SingleResumeTestClock()
        let model = makeModel(validateNativeSource: { _, _ in .invalid("Controlled failure") }, timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let player = SingleResumeTestPlayer(playerItem: SingleResumeTestItem(asset: AVMutableComposition()))
        player.control = .playing; model.player = player
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
        model.beginSingleNativeResume(for: source, player: player, item: try XCTUnwrap(player.currentItem))
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        for _ in 0..<16 { await gate.waitForSample(); gate.advance() }
        await task.value
        XCTAssertEqual(gate.now, 8)
        XCTAssertTrue(model.failedSourceIDs.contains(source.id))
        XCTAssertNil(model.stallValidationTask, "No second ten-second observation after the resume deadline")
        XCTAssertNotEqual(model.loadRequestID, attempt)
        model.cleanup(); await model.loadTask?.value
    }

    func testSingleResumeExpirySeekJumpIsNotDecodedProgress() async throws {
        let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition()); item.ranges = [(20,40)]
        let player = SingleResumeTestPlayer(playerItem: item); player.seconds = 10; model.player = player
        model.beginSingleNativeResume(for: try XCTUnwrap(model.activeSource), player: player, item: item)
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        await gate.waitForSample()
        XCTAssertEqual(player.seeks, [37])
        player.completeSeek()
        await Task.yield()
        gate.advance(); await gate.waitForSample()
        XCTAssertEqual(model.playbackState, .recovering(.native), "Seek completion is not decoded advancement")
        player.seconds = 38; gate.advance(); await task.value
        XCTAssertEqual(model.playbackState, .playing(.native))
        XCTAssertEqual(player.seeks, [37])
    }

    func testSingleResumePauseRevokesDelayedSeekAndRecovery() async throws {
        let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition()); item.ranges = [(20,40)]
        let player = SingleResumeTestPlayer(playerItem: item); model.player = player
        model.beginSingleNativeResume(for: try XCTUnwrap(model.activeSource), player: player, item: item)
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        await gate.waitForSample(); model.togglePlayPause()
        player.completeSeek(); gate.advance(); await task.value
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(player.plays, 0)
        XCTAssertEqual(player.immediatePlays, 0)
        XCTAssertNil(model.loadTask)
    }

    func testSingleResumeOnlyNudgesBufferedLiveWaitOnce() async throws {
        for hasBuffer in [false, true] {
            let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
            defer { model.cleanup(); gate.finish() }
            model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
            let item = SingleResumeTestItem(asset: AVMutableComposition()); item.buffered = hasBuffer ? [(0,10)] : []
            let player = SingleResumeTestPlayer(playerItem: item); model.player = player
            model.beginSingleNativeResume(for: try XCTUnwrap(model.activeSource), player: player, item: item)
            let task = try XCTUnwrap(model.foregroundResumeValidationTask)
            for _ in 0..<6 { await gate.waitForSample(); gate.advance() }
            await gate.waitForSample()
            XCTAssertEqual(player.immediatePlays, hasBuffer ? 1 : 0)
            XCTAssertEqual(player.plays, 0)
            model.togglePlayPause(); gate.advance(); await task.value
        }
    }

    func testSingleResumeCannotActAfterLeavingSinglePlayerContext() async throws {
        let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition()); item.ranges = [(20,40)]
        let player = SingleResumeTestPlayer(playerItem: item); model.player = player
        model.beginSingleNativeResume(for: try XCTUnwrap(model.activeSource), player: player, item: item)
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        await gate.waitForSample()
        model.setViewingPlaybackContext(.watchTwo(engine: .native))
        let state = model.playbackState
        player.completeSeek(); gate.advance(); await task.value
        XCTAssertEqual(model.playbackState, state)
        XCTAssertEqual(player.plays, 0)
        XCTAssertEqual(player.immediatePlays, 0)
        XCTAssertNil(model.loadTask)
    }

    func testSingleResumeReplacementCannotRecoverTheOldItem() async throws {
        let gate = SingleResumeTestClock(), model = makeModel(timing: gate.timing)
        defer { model.cleanup(); gate.finish() }
        model.player = nil; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = SingleResumeTestItem(asset: AVMutableComposition())
        let player = SingleResumeTestPlayer(playerItem: item); model.player = player
        model.beginSingleNativeResume(for: try XCTUnwrap(model.activeSource), player: player, item: item)
        let task = try XCTUnwrap(model.foregroundResumeValidationTask)
        await gate.waitForSample()
        player.replaceCurrentItem(with: SingleResumeTestItem(asset: AVMutableComposition()))
        player.seconds = 1; gate.advance(); await task.value
        XCTAssertEqual(model.playbackState, .recovering(.native))
        XCTAssertNil(model.loadTask)
        XCTAssertEqual(player.immediatePlays, 0)
    }

    private func openControls(_ model: LivePlayerViewModel) throws -> NativeFullscreenSession {
        model.beginNativeFullscreen()
        let session = try XCTUnwrap(model.nativeFullscreen)
        session.controlsAreActive = true
        session.isClosing = false
        return session
    }

    private func measurement(_ view: AVPlayerLayerView.PlayerUIView) throws -> [String: Any] {
        let data = try XCTUnwrap(view.physicalMeasurementSnapshot().data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Construct and bind the actual host/AVPlayerViewController using an
    /// inert recording presenter. This verifies synchronous player detachment,
    /// not UIKit's physical transition, decoding or PiP availability.
    private func mountFullscreenHost(_ model: LivePlayerViewModel) throws -> FullscreenHostFixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let presenter = FullscreenPresentationTestController()
        window.rootViewController = presenter
        window.addSubview(presenter.view)
        let host = NativeFullscreenHostController(model: model,
            makePlayerController: { FullscreenPresentationTestPlayerController() })
        presenter.addChild(host)
        presenter.view.addSubview(host.view)
        host.didMove(toParent: presenter)
        let session = try openControls(model)
        host.reconcile(session)
        let controller = try XCTUnwrap(presenter.testPresented as? AVPlayerViewController)
        XCTAssertTrue(controller.player === session.player)
        return .init(window: window, presenter: presenter, host: host, session: session, controller: controller)
    }

    private func attachPendingFullscreenHost(_ model: LivePlayerViewModel,
        retry: FullscreenInitialPresentationRetryGate, maximumDeferrals: Int = 20
    ) -> (window: UIWindow, presenter: FullscreenPresentationTestController, host: NativeFullscreenHostController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let presenter = FullscreenPresentationTestController()
        window.rootViewController = presenter
        window.addSubview(presenter.view)
        let host = NativeFullscreenHostController(model: model, maximumPresentationDeferrals: maximumDeferrals,
            waitForPresentationRetry: retry.wait, makePlayerController: { FullscreenPresentationTestPlayerController() })
        presenter.addChild(host)
        presenter.view.addSubview(host.view)
        host.didMove(toParent: presenter)
        return (window, presenter, host)
    }

    private func makeModel(
        prepareAudio: @escaping @MainActor () async -> MediaAudioSessionPreparation = { .completed([]) },
        validateNativeSource: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult = { _, _ in
            XCTFail("A fullscreen ownership test must not load or validate a URL")
            return .invalid("Unexpected source preparation")
        },
        timing: FottyAsyncTiming? = nil
    ) -> LivePlayerViewModel {
        let event = AnalyticalDataEngine.EventReference(id: UUID().uuidString,
            title: "Fullscreen ownership test", category: "football", date: 0,
            poster: nil, popular: false, teams: nil, sources: nil)
        let sessions = (1...2).map { index in
            StreamSession(matchID: event.id,
                playableURL: URL(string: "https://example.invalid/fullscreen-\(index).m3u8")!,
                streamType: .hls, providerName: "StreamEx")
        }
        let model = LivePlayerViewModel(event: event, providedSessions: sessions,
            ownsRemoteCommands: false, prepareAudioSession: prepareAudio,
            validateNativeSource: validateNativeSource, timing: timing)
        model.didApplyLandscape = true
        model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        // A controlled flag exercises the policy; it is not decoded-video proof.
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.native), phase: "Playing")
        return model
    }
}

@MainActor
private struct FullscreenHostFixture {
    let window: UIWindow
    let presenter: FullscreenPresentationTestController
    let host: NativeFullscreenHostController
    let session: NativeFullscreenSession
    let controller: AVPlayerViewController
}

@MainActor
private final class FullscreenPresentationTestController: UIViewController {
    var testPresented: UIViewController?
    weak var testPresenting: UIViewController?
    var testBeingDismissed = false
    var testBeingPresented = false
    var refusesPresentation = false
    private(set) var presentCount = 0
    private(set) var dismissCount = 0

    override var presentedViewController: UIViewController? { testPresented }
    override var presentingViewController: UIViewController? { testPresenting }
    override var isBeingDismissed: Bool { testBeingDismissed }
    override var isBeingPresented: Bool { testBeingPresented }
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool,
                          completion: (() -> Void)? = nil) {
        presentCount += 1
        guard !refusesPresentation else { return }
        testPresented = viewControllerToPresent
        (viewControllerToPresent as? FullscreenPresentationTestPlayerController)?.testPresenting = self
        completion?()
    }
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCount += 1
        completion?()
    }
}

@MainActor
private final class FullscreenPresentationTestPlayerController: AVPlayerViewController {
    weak var testPresenting: UIViewController?
    override var presentingViewController: UIViewController? { testPresenting }
}

@MainActor
private final class FullscreenInitialPresentationRetryGate {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var finished = false
    var pendingCount: Int { pending.count }

    func wait() async throws {
        guard !finished else { return }
        await withCheckedContinuation { pending.append($0) }
    }

    func resumeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume()
    }

    func finish() {
        finished = true
        let callbacks = pending
        pending = []
        for callback in callbacks { callback.resume() }
    }
}

@MainActor
private final class FullscreenSourceValidationBarrier {
    private var pending: [CheckedContinuation<StreamContractValidator.ValidationResult, Never>] = []
    private var finished = false
    var pendingCount: Int { pending.count }

    func wait(_ url: URL, _ headers: [String: String]) async -> StreamContractValidator.ValidationResult {
        guard !finished else { return .invalid("Controlled cancelled preparation") }
        return await withCheckedContinuation { pending.append($0) }
    }

    func waitUntilEntered() async {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(2)
        while pending.isEmpty, clock.now < deadline { await Task.yield() }
    }

    func finish() {
        finished = true
        let completions = pending
        pending = []
        for completion in completions { completion.resume(returning: .invalid("Controlled cancelled preparation")) }
    }
}

private final class FullscreenTransportSpyPlayer: AVPlayer {
    private let countLock = NSLock()
    private var storedPlayCount = 0
    var playCount: Int {
        countLock.lock(); defer { countLock.unlock() }
        return storedPlayCount
    }
    // AVPlayer's override is nonisolated; its counter cannot assume a queue.
    override func play() {
        countLock.lock(); defer { countLock.unlock() }
        storedPlayCount += 1
    }
}

private final class FullscreenDiagnosticReadyItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}

private final class FullscreenForegroundObservationItem: AVPlayerItem {
    private let statusLock = NSLock()
    private var failed = false
    override var status: AVPlayerItem.Status {
        statusLock.lock(); defer { statusLock.unlock() }
        return failed ? .failed : .readyToPlay
    }
    func setFailed() { statusLock.lock(); failed = true; statusLock.unlock() }
}

private final class FullscreenDiagnosticProgressPlayer: AVPlayer {
    private let stateLock = NSLock()
    private var seconds = 0.0
    private var plays = 0
    var playCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return plays }
    func setSeconds(_ value: Double) { stateLock.lock(); seconds = value; stateLock.unlock() }
    override func currentTime() -> CMTime {
        stateLock.lock(); defer { stateLock.unlock() }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
    override var timeControlStatus: AVPlayer.TimeControlStatus { .playing }
    override func play() { stateLock.lock(); plays += 1; stateLock.unlock() }
}

private final class FullscreenWaitingTransportSpyPlayer: AVPlayer {
    private let countLock = NSLock()
    private var plays = 0
    var playCount: Int {
        countLock.lock(); defer { countLock.unlock() }
        return plays
    }
    override var timeControlStatus: AVPlayer.TimeControlStatus { .waitingToPlayAtSpecifiedRate }
    override func currentTime() -> CMTime { .zero }
    override func play() {
        countLock.lock(); defer { countLock.unlock() }
        plays += 1
    }
}

@MainActor
private final class FullscreenResumeDelayGate {
    private(set) var requested: [Duration] = []
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var finished = false
    var pendingCount: Int { pending.count }

    func wait(_ duration: Duration) async throws {
        // The model also uses this timing seam for its ten-second controls
        // timer. Only the resume deadline belongs to this test's manual gate.
        guard duration == .seconds(8) else { return }
        requested.append(duration)
        guard !finished else { return }
        await withCheckedContinuation { pending.append($0) }
    }

    func releaseNext() {
        guard !pending.isEmpty else { XCTFail("Missing controlled resume deadline"); return }
        pending.removeFirst().resume()
    }

    func finishAll() {
        finished = true
        let callbacks = pending
        pending = []
        callbacks.forEach { $0.resume() }
    }
}

@MainActor
private final class FullscreenAudioPreparationBarrier {
    private var pending: [CheckedContinuation<MediaAudioSessionPreparation, Never>] = []
    var pendingCount: Int { pending.count }

    func wait() async -> MediaAudioSessionPreparation {
        await withCheckedContinuation { pending.append($0) }
    }

    func completeAll() {
        let completions = pending
        pending.removeAll()
        for completion in completions { completion.resume(returning: .completed([])) }
    }
}

private final class SingleResumeTestItem: AVPlayerItem {
    var ranges: [(Double,Double)] = []
    var buffered: [(Double,Double)] = []
    override var status: AVPlayerItem.Status { .readyToPlay }
    override var duration: CMTime { .indefinite }
    override var seekableTimeRanges: [NSValue] { values(ranges) }
    override var loadedTimeRanges: [NSValue] { values(buffered) }
    private func values(_ ranges: [(Double,Double)]) -> [NSValue] {
        ranges.map { NSValue(timeRange: CMTimeRange(start: CMTime(seconds: $0.0, preferredTimescale: 600),
            duration: CMTime(seconds: $0.1 - $0.0, preferredTimescale: 600))) }
    }
}
private final class SingleResumeTestPlayer: AVPlayer {
    var seconds = 0.0, plays = 0, immediatePlays = 0
    var control: AVPlayer.TimeControlStatus = .waitingToPlayAtSpecifiedRate
    var seeks: [Double] = []
    var seekCompletion: ((Bool) -> Void)?
    override func currentTime() -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }
    override var timeControlStatus: AVPlayer.TimeControlStatus { control }
    override var reasonForWaitingToPlay: AVPlayer.WaitingReason? { .toMinimizeStalls }
    override func play() { plays += 1 }
    override func pause() {}
    override func playImmediately(atRate rate: Float) { immediatePlays += 1 }
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                       completionHandler: @escaping (Bool) -> Void) {
        seeks.append(time.seconds); seekCompletion = completionHandler
    }
    func completeSeek() { seconds = seeks.last ?? seconds; let fn = seekCompletion; seekCompletion = nil; fn?(true) }
}
@MainActor private final class SingleResumeTestClock {
    var now = 0.0
    private var pending: CheckedContinuation<Void, Never>?
    private var finished = false
    var timing: FottyAsyncTiming { .init(monotonicNow: { self.now }, sleep: { duration in
        guard duration == .milliseconds(500), !self.finished else { return }
        await withCheckedContinuation { self.pending = $0 }
    }) }
    func waitForSample() async {
        let end = ContinuousClock.now + .seconds(2)
        while pending == nil && ContinuousClock.now < end { await Task.yield() }
        XCTAssertNotNil(pending, "Resume did not reach its controlled half-second observation")
    }
    func advance() { now += 0.5; let fn = pending; pending = nil; fn?.resume() }
    func finish() { finished = true; let fn = pending; pending = nil; fn?.resume() }
}
