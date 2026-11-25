import AVFoundation
import SwiftUI
import XCTest
@testable import Fotty

/// No real audio session, provider URL, device or playback decoder is opened.
/// Barriers observe accepted requests rather than sleeping to manufacture races.
@MainActor
final class MediaAudioSessionOwnerTests: XCTestCase {
    func testActivationEvidenceDescribesOneActualCoalescedJobNotEachWaiter() async {
        let backend = ControlledAudioBackend(), evidence = ActivationDiagnosticRecorder()
        let owner = MediaAudioSessionOwner(backend: backend, diagnostic: { evidence.append($0) })
        let first = Task { await owner.prepare(activate: true) }
        await waitUntil("causal configuration started") { await backend.count(.configure) == 1 }
        let second = Task { await owner.prepare(activate: true) }
        await waitUntil("causal requests coalesced") { await owner.pendingRequestCount == 2 }
        XCTAssertTrue(evidence.values.isEmpty, "Waiting/configuration is not actual activation")
        await backend.release(.configure)
        await waitUntil("causal activation started") { await backend.count(.activate) == 1 }
        XCTAssertEqual(evidence.values.map(\.phase), [.audioActivationRequested])
        await backend.release(.activate, errorCode: -100)
        _ = await first.value; _ = await second.value
        let records = evidence.values
        XCTAssertEqual(records.map(\.phase), [.audioActivationRequested, .audioActivationFinished])
        XCTAssertEqual(records.map(\.result), [.began, .completedWithErrors])
        XCTAssertEqual(records.first?.jobID, records.last?.jobID)
    }

    func testActivationEvidenceCapDoesNotStopActualPlaybackPreparation() async {
        let backend = ImmediateAudioBackend(), evidence = ActivationDiagnosticRecorder()
        let owner = MediaAudioSessionOwner(backend: backend, diagnostic: { evidence.append($0) })
        _ = await owner.prepare()
        XCTAssertTrue(evidence.values.isEmpty)
        for _ in 0..<(MediaAudioSessionOwner.maximumDiagnosedActivations + 2) {
            let preparation = await owner.prepare(activate: true)
            XCTAssertEqual(preparation, .completed([]))
        }
        let actualActivations = await backend.activations
        XCTAssertEqual(actualActivations, MediaAudioSessionOwner.maximumDiagnosedActivations + 2)
        XCTAssertEqual(evidence.values.count, MediaAudioSessionOwner.maximumDiagnosedActivations * 2)
    }

    func testPreparationEvidenceKeepsPreAwaitRouteAndAudioContext() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.setViewingDiagnosticRoute(.watchTwo)
        model.setViewingAudioEnabled(false)
        let request = model.loadRequestID
        let task = Task { await model.requestPlaybackStart(player: player) }
        await waitUntil("causal preparation started") { delay.pendingCount == 1 }
        model.setViewingDiagnosticRoute(.single)
        model.setViewingAudioEnabled(true)
        delay.completeAll()
        let started = await task.value
        XCTAssertTrue(started)
        let records = FottyQualityStore.shared.records().filter {
            $0.name == "playback_causal_evidence" && $0.details["attempt_id"] == request.uuidString
        }
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.details["route"] == "watch_two" && $0.details["audio_enabled"] == "false" })
        XCTAssertEqual(records.first?.details["diagnostic_operation_id"], records.last?.details["diagnostic_operation_id"])
        XCTAssertTrue(records.allSatisfy { $0.details["diagnostic_purpose"] == "native_start" && $0.details["variant_key"] == nil })
    }

    func testRetiredPreparationCompletionCannotCreateCurrentOwnerEvidence() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        let request = model.loadRequestID
        let task = Task { await model.requestPlaybackStart(player: player) }
        await waitUntil("retired causal preparation started") { delay.pendingCount == 1 }
        model.cleanup()
        delay.completeAll()
        let started = await task.value
        XCTAssertFalse(started)
        XCTAssertEqual(player.playCount, 0)
        let records = FottyQualityStore.shared.records().filter {
            $0.name == "playback_causal_evidence" && $0.details["attempt_id"] == request.uuidString
        }
        XCTAssertEqual(records.map { $0.details["diagnostic_phase"] }, ["audio_preparation_requested"])
    }

    func testConfigurationIsLazyAndDoesNotActivate() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let initialCalls = await backend.calls
        XCTAssertTrue(initialCalls.isEmpty)
        let request = Task { await owner.prepare() }
        await waitUntil("configuration started") { await backend.count(.configure) == 1 }
        await backend.release(.configure)
        let result = await request.value
        let calls = await backend.calls
        XCTAssertEqual(result, .completed([]))
        XCTAssertEqual(calls, [.configure])
    }

    func testConcurrentActivationDemandCoalescesAndConfigurationFinishesFirst() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let first = Task { await owner.prepare(activate: true) }
        await waitUntil("first configuration started") { await backend.count(.configure) == 1 }
        let second = Task { await owner.prepare(activate: true) }
        await waitUntil("both requests accepted") { await owner.pendingRequestCount == 2 }
        let before = await backend.calls
        XCTAssertEqual(before, [.configure], "Activation must not overtake configuration")
        await backend.release(.configure)
        await waitUntil("shared activation started") { await backend.count(.activate) == 1 }
        await backend.release(.activate)
        let firstResult = await first.value, secondResult = await second.value
        let calls = await backend.calls
        XCTAssertEqual(firstResult, .completed([]))
        XCTAssertEqual(secondResult, .completed([]))
        XCTAssertEqual(calls, [.configure, .activate])
    }

    func testCancelOneWaiterDoesNotCancelSharedActivation() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let first = Task { await owner.prepare(activate: true) }
        await waitUntil("configuration started") { await backend.count(.configure) == 1 }
        let second = Task { await owner.prepare(activate: true) }
        await waitUntil("both requests accepted") { await owner.pendingRequestCount == 2 }
        await backend.release(.configure)
        await waitUntil("activation started") { await backend.count(.activate) == 1 }
        first.cancel()
        let cancelled = await first.value
        XCTAssertEqual(cancelled, .cancelled, "A canceled waiter must not wait for the SDK callback")
        let remaining = await owner.pendingRequestCount
        XCTAssertEqual(remaining, 1)
        await backend.release(.activate)
        let completed = await second.value
        XCTAssertEqual(completed, .completed([]))
    }

    func testCancelOnlyActivationDemandLeavesConfigurationOnlyWaiter() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let activation = Task { await owner.prepare(activate: true) }
        await waitUntil("configuration started") { await backend.count(.configure) == 1 }
        let configuration = Task { await owner.prepare() }
        await waitUntil("both requests accepted") { await owner.pendingRequestCount == 2 }
        activation.cancel()
        let cancelled = await activation.value
        XCTAssertEqual(cancelled, .cancelled)
        await backend.release(.configure)
        let completed = await configuration.value
        let calls = await backend.calls
        XCTAssertEqual(completed, .completed([]))
        XCTAssertEqual(calls, [.configure], "Canceled playback must not leave sticky activation demand")
    }

    func testCanceledJobCannotOverlapNextConfiguration() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let old = Task { await owner.prepare(activate: true) }
        await waitUntil("old configuration started") { await backend.count(.configure) == 1 }
        old.cancel()
        let cancelled = await old.value
        XCTAssertEqual(cancelled, .cancelled)
        let next = Task { await owner.resetAndConfigure() }
        await waitUntil("new request accepted") { await owner.pendingRequestCount == 1 }
        let before = await backend.calls
        XCTAssertEqual(before, [.configure], "Even a canceled physical operation must finish before the next begins")
        await backend.release(.configure)
        await waitUntil("next configuration started") { await backend.count(.configure) == 2 }
        await backend.release(.configure)
        let completed = await next.value
        let calls = await backend.calls
        XCTAssertEqual(completed, .completed([]))
        XCTAssertEqual(calls, [.configure, .configure])
    }

    func testMediaResetRepreparesSurvivingPlaybackBeforeAuthorizingIt() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let play = Task { await owner.prepare(activate: true) }
        await waitUntil("configuration started") { await backend.count(.configure) == 1 }
        await backend.release(.configure)
        await waitUntil("old activation started") { await backend.count(.activate) == 1 }
        let reset = Task { await owner.resetAndConfigure() }
        await waitUntil("reset accepted") { await owner.pendingRequestCount == 2 }
        await backend.release(.activate, errorCode: -100)
        await waitUntil("reset configuration started") { await backend.count(.configure) == 2 }
        let duringReset = await owner.pendingRequestCount
        XCTAssertEqual(duringReset, 2, "An old-epoch completion must not authorize playback")
        await backend.release(.configure)
        await waitUntil("new activation started") { await backend.count(.activate) == 2 }
        await backend.release(.activate)
        let playResult = await play.value, resetResult = await reset.value
        let calls = await backend.calls
        XCTAssertEqual(playResult, .completed([]))
        XCTAssertEqual(resetResult, .completed([]))
        XCTAssertEqual(calls, [.configure, .activate, .configure, .activate])
    }

    func testTypedConfigurationAndActivationFailurePermitLaterRetry() async {
        let backend = ControlledAudioBackend()
        let owner = MediaAudioSessionOwner(backend: backend)
        let first = Task { await owner.prepare(activate: true) }
        await waitUntil("configuration started") { await backend.count(.configure) == 1 }
        await backend.release(.configure, errorCode: -50)
        await waitUntil("activation still attempted") { await backend.count(.activate) == 1 }
        await backend.release(.activate, errorCode: -100)
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .completed([
            .init(stage: .configuration, code: -50), .init(stage: .activation, code: -100)
        ]))
        XCTAssertTrue(firstResult.mayContinue, "An audio error is not a provider failure or permission to change sources")
        let retry = Task { await owner.prepare(activate: true) }
        await waitUntil("retry configuration started") { await backend.count(.configure) == 2 }
        await backend.release(.configure)
        await waitUntil("retry activation started") { await backend.count(.activate) == 2 }
        await backend.release(.activate)
        let retryResult = await retry.value
        XCTAssertEqual(retryResult, .completed([]))
    }

    func testMultiPanePermissionIsRecheckedAfterDelayedActivation() async {
        for revokedBy in ["pause", "background", "network", "dismissal"] {
            let delay = ControlledAudioPreparation()
            let player = AudioSpyPlayer()
            let identity = MediaAudioPlaybackIdentity(requestID: UUID(), sourceID: UUID(), intentID: UUID(),
                                                      player: player, item: nil)
            var permission = true
            let task = Task {
                await MediaAudioPlaybackGate.prepareNative(using: delay.wait, expected: identity,
                    currentIdentity: { identity }, playbackMayStart: { permission })
            }
            await waitUntil("\(revokedBy) preparation started") { delay.pendingCount == 1 }
            permission = false
            delay.completeAll()
            let mayPlay = await task.value
            XCTAssertFalse(mayPlay, revokedBy)
            XCTAssertEqual(player.playCount, 0)
        }
    }

    func testMultiPaneAttemptIdentityCannotBeReusedForAnotherPlayerSourceOrIntent() async {
        let oldPlayer = AudioSpyPlayer(), newPlayer = AudioSpyPlayer()
        let oldItem = AVPlayerItem(asset: AVMutableComposition())
        let newItem = AVPlayerItem(asset: AVMutableComposition())
        let request = UUID(), source = UUID(), intent = UUID()
        let expected = MediaAudioPlaybackIdentity(requestID: request, sourceID: source, intentID: intent,
                                                  player: oldPlayer, item: oldItem)
        let replacements = [
            MediaAudioPlaybackIdentity(requestID: UUID(), sourceID: source, intentID: intent, player: oldPlayer, item: oldItem),
            MediaAudioPlaybackIdentity(requestID: request, sourceID: UUID(), intentID: intent, player: oldPlayer, item: oldItem),
            MediaAudioPlaybackIdentity(requestID: request, sourceID: source, intentID: UUID(), player: oldPlayer, item: oldItem),
            MediaAudioPlaybackIdentity(requestID: request, sourceID: source, intentID: intent, player: newPlayer, item: oldItem),
            MediaAudioPlaybackIdentity(requestID: request, sourceID: source, intentID: intent, player: oldPlayer, item: newItem)
        ]
        for replacement in replacements {
            let delay = ControlledAudioPreparation()
            var current = expected
            let task = Task {
                await MediaAudioPlaybackGate.prepareNative(using: delay.wait, expected: expected,
                    currentIdentity: { current }, playbackMayStart: { true })
            }
            await waitUntil("replacement preparation started") { delay.pendingCount == 1 }
            current = replacement
            delay.completeAll()
            let mayPlay = await task.value
            XCTAssertFalse(mayPlay)
        }
    }

    func testNativePlayWaitsForPreparationAndKeepsExistingAudioErrorFallback() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.togglePlayPause()
        let task = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("Play preparation started") { delay.pendingCount == 1 }
        XCTAssertEqual(player.playCount, 0)
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
        delay.completeAll(.completed([.init(stage: .activation, code: -100)]))
        await task.value
        XCTAssertEqual(player.playCount, 1)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)
    }

    func testNativeSecondTapCancelsPendingPlayEvenAfterOldPausedObservation() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.togglePlayPause()
        let task = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("Play preparation started") { delay.pendingCount == 1 }
        model.handleNativeTimeControlStatusChanged(.paused)
        model.togglePlayPause()
        delay.completeAll()
        await task.value
        XCTAssertEqual(player.playCount, 0)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
    }

    func testTerminalNativeFailureRevokesPendingPlayAndFirstStartWithoutLosingRetryIntent() async throws {
        for isFirstStart in [false, true] {
            let delay = ControlledAudioPreparation()
            let (model, player) = try makeNativeModel(preparation: delay.wait)
            defer { model.cleanup(); delay.completeAll() }
            let source = try XCTUnwrap(model.activeSource)
            let task: Task<Void, Never>
            if isFirstStart {
                model.transition(to: .connecting(.native), phase: "Connecting")
                task = Task {
                    let started = await model.requestPlaybackStart(player: player)
                    XCTAssertFalse(started, "A failed first-start attempt cannot regain permission")
                }
            } else {
                model.togglePlayPause()
                task = try XCTUnwrap(model.audioPreparationTask)
            }
            await waitUntil("terminal test preparation started") { delay.pendingCount == 1 }
            model.handleSourceStartupFailure(source, reason: "This broadcast is unavailable",
                                             expectedRequestID: model.loadRequestID)
            XCTAssertEqual(model.playbackState, .failed)
            XCTAssertNotNil(model.error)
            XCTAssertTrue(model.failedSourceIDs.contains(source.id))
            XCTAssertNil(model.audioPreparationTask)
            XCTAssertTrue(model.userWantsPlayback, "Terminal cancellation must preserve existing manual Retry intent")
            delay.completeAll()
            await task.value
            XCTAssertEqual(player.playCount, 0)
            XCTAssertEqual(model.playbackState, .failed)
            XCTAssertFalse(model.isPlaybackWatchdogArmed)
            XCTAssertEqual(model.autoFailoverCount, 0)
        }
    }

    func testRemotePlayDoesNotTogglePendingPlayIntoPauseAndRemotePauseRevokesIt() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.requestPlayFromRemoteCommand()
        let task = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("remote Play preparation started") { delay.pendingCount == 1 }
        model.handleNativeTimeControlStatusChanged(.paused)
        model.requestPlayFromRemoteCommand()
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertFalse(task.isCancelled)
        model.requestPauseFromRemoteCommand()
        delay.completeAll()
        await task.value
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(player.playCount, 0)
    }

    func testFreshRemoteAndInlinePlayKeepTerminalFailureUntilExplicitRetry() throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        let source = try XCTUnwrap(model.activeSource)
        model.handleSourceStartupFailure(source, reason: "This broadcast is unavailable",
                                         expectedRequestID: model.loadRequestID)
        let terminalError = try XCTUnwrap(model.error)
        let terminalPhase = model.connectionPhase
        XCTAssertEqual(model.playbackState, .failed)
        for command in ["remote", "inline"] {
            if command == "remote" { model.requestPlayFromRemoteCommand() }
            else { model.togglePlayPause() }
            XCTAssertEqual(model.playbackState, .failed)
            XCTAssertEqual(model.error, terminalError)
            XCTAssertEqual(model.connectionPhase, terminalPhase)
            XCTAssertNil(model.audioPreparationTask)
            XCTAssertEqual(delay.pendingCount, 0)
            XCTAssertEqual(player.playCount, 0)
            XCTAssertFalse(model.isPlaybackWatchdogArmed)
            XCTAssertTrue(model.userWantsPlayback, "Only explicit Retry changes this retained attempt intent")
        }
    }

    func testPendingNativePlaySurvivesPiPActivationAndAllowedBackground() async throws {
        for callback in ["PiP active", "background capable"] {
            let delay = ControlledAudioPreparation()
            let (model, player) = try makeNativeModel(preparation: delay.wait, withItem: true)
            defer { model.cleanup(); delay.completeAll() }
            model.handlePictureInPictureAvailabilityChanged(true)
            model.togglePlayPause()
            let playTask = try XCTUnwrap(model.audioPreparationTask)
            await waitUntil("Play preparation started") { delay.pendingCount == 1 }
            if callback == "PiP active" { model.handlePictureInPictureActivityChanged(true) }
            else { model.handleScenePhaseChange(.background) }
            model.handleNativeTimeControlStatusChanged(.paused)
            let pipTask = try XCTUnwrap(model.pictureInPicturePreparationTask)
            await waitUntil("independent PiP preparation started") { delay.pendingCount == 2 }
            XCTAssertFalse(playTask.isCancelled, callback)
            delay.completeAll()
            await playTask.value
            await pipTask.value
            XCTAssertEqual(player.playCount, 1, callback)
            XCTAssertTrue(model.userWantsPlayback)
        }
    }

    func testExplicitPiPRequestDoesNotReplacePendingNativePlay() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.handlePictureInPictureAvailabilityChanged(true)
        model.togglePlayPause()
        let playTask = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("Play preparation started") { delay.pendingCount == 1 }
        model.togglePictureInPicture()
        let pipTask = try XCTUnwrap(model.pictureInPicturePreparationTask)
        await waitUntil("PiP preparation started") { delay.pendingCount == 2 }
        XCTAssertNil(model.pictureInPictureRequestID)
        delay.completeAll()
        await playTask.value
        await pipTask.value
        XCTAssertEqual(player.playCount, 1)
        XCTAssertNotNil(model.pictureInPictureRequestID)
    }

    func testPauseRevokesPendingPlayAndPiPRequest() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.handlePictureInPictureAvailabilityChanged(true)
        model.togglePlayPause()
        let playTask = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("Play preparation started") { delay.pendingCount == 1 }
        model.togglePictureInPicture()
        let pipTask = try XCTUnwrap(model.pictureInPicturePreparationTask)
        await waitUntil("PiP preparation started") { delay.pendingCount == 2 }
        model.togglePlayPause()
        delay.completeAll()
        await playTask.value
        await pipTask.value
        XCTAssertEqual(player.playCount, 0)
        XCTAssertNil(model.pictureInPictureRequestID)
    }

    func testUnavailablePiPCannotPublishAfterLateActivation() async throws {
        let delay = ControlledAudioPreparation()
        let (model, _) = try makeNativeModel(preparation: delay.wait)
        defer { model.cleanup(); delay.completeAll() }
        model.handlePictureInPictureAvailabilityChanged(true)
        model.togglePictureInPicture()
        let task = try XCTUnwrap(model.pictureInPicturePreparationTask)
        await waitUntil("PiP preparation started") { delay.pendingCount == 1 }
        model.handlePictureInPictureAvailabilityChanged(false)
        delay.completeAll()
        await task.value
        XCTAssertNil(model.pictureInPictureRequestID)
    }

    func testReplacedPlayerAndDismissalCannotPlayAfterLateActivation() async throws {
        for replacement in ["player", "dismissal"] {
            let delay = ControlledAudioPreparation()
            let (model, oldPlayer) = try makeNativeModel(preparation: delay.wait)
            defer { model.cleanup(); delay.completeAll() }
            model.togglePlayPause()
            let task = try XCTUnwrap(model.audioPreparationTask)
            await waitUntil("Play preparation started") { delay.pendingCount == 1 }
            let newPlayer = AudioSpyPlayer()
            if replacement == "player" { model.player = newPlayer }
            else { model.cleanup() }
            delay.completeAll()
            await task.value
            XCTAssertEqual(oldPlayer.playCount, 0)
            XCTAssertEqual(newPlayer.playCount, 0)
            XCTAssertFalse(model.isPlaybackWatchdogArmed)
        }
    }

    func testPendingPlayResumesAfterOrdinaryBackgroundDespiteOldPausedObservation() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait, withItem: true)
        defer { model.cleanup(); delay.completeAll() }
        model.togglePlayPause()
        let old = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("Play preparation started") { delay.pendingCount == 1 }
        model.handleNativeTimeControlStatusChanged(.paused)
        model.handleScenePhaseChange(.background)
        XCTAssertTrue(model.shouldResumeAfterForeground)
        delay.completeAll()
        await old.value
        XCTAssertEqual(player.playCount, 0)
        model.handleScenePhaseChange(.active)
        let resumed = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("resume preparation started") { delay.pendingCount == 1 }
        XCTAssertNil(model.foregroundResumeValidationTask, "Audio wait must not spend the provider's resume timeout")
        delay.completeAll()
        await resumed.value
        XCTAssertEqual(player.playCount, 1)
        XCTAssertNotNil(model.foregroundResumeValidationTask)
    }

    func testConnectingNativeStartResumesAfterBackgroundDuringAudioPreparation() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait, withItem: true)
        defer { model.cleanup(); delay.completeAll() }
        model.transition(to: .connecting(.native), phase: "Buffering")
        let startup = Task { await model.requestPlaybackStart(player: player) }
        await waitUntil("startup preparation started") { delay.pendingCount == 1 }
        model.handleScenePhaseChange(.background)
        XCTAssertTrue(model.shouldResumeAfterForeground)
        delay.completeAll()
        let didStartInBackground = await startup.value
        XCTAssertFalse(didStartInBackground)
        XCTAssertEqual(player.playCount, 0)
        model.handleScenePhaseChange(.active)
        let resumed = try XCTUnwrap(model.audioPreparationTask)
        await waitUntil("foreground preparation started") { delay.pendingCount == 1 }
        delay.completeAll()
        await resumed.value
        XCTAssertEqual(player.playCount, 1)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
    }

    func testMultiSuspendedNativeFirstStartClearsLoadingOnlyAfterPreparedForegroundResume() async {
        let delay = ControlledAudioPreparation()
        let player = AudioSpyPlayer()
        let request = UUID(), source = UUID()
        var intent = UUID(), foreground = true, userWantsPlayback = true
        var isLoading = true, isPlaying = true, audioFocused = false
        var appliedAudioFocus: Bool?
        let currentIdentity = {
            MediaAudioPlaybackIdentity(requestID: request, sourceID: source, intentID: intent,
                                       player: player, item: nil)
        }
        let initialIdentity = currentIdentity()
        let startup = Task {
            await MediaAudioPlaybackGate.prepareNative(using: delay.wait, expected: initialIdentity,
                currentIdentity: currentIdentity, playbackMayStart: { foreground && userWantsPlayback })
        }
        await waitUntil("Multi initial preparation started") { delay.pendingCount == 1 }
        foreground = false
        intent = UUID() // The actual panel's background boundary revokes this start.
        isPlaying = false
        delay.completeAll()
        let startedInBackground = await startup.value
        XCTAssertFalse(startedInBackground)
        XCTAssertTrue(isLoading)
        XCTAssertEqual(player.playCount, 0)

        foreground = true
        let resumedIdentity = currentIdentity()
        let resumed = Task {
            await MultiLiveNativeAudioResume.resume(using: delay.wait, expected: resumedIdentity,
                currentIdentity: currentIdentity, playbackMayStart: { foreground && userWantsPlayback },
                player: player,
                isLoading: Binding(get: { isLoading }, set: { isLoading = $0 }),
                isPlaying: Binding(get: { isPlaying }, set: { isPlaying = $0 }),
                updateAudio: { appliedAudioFocus = audioFocused })
        }
        await waitUntil("Multi foreground preparation started") { delay.pendingCount == 1 }
        XCTAssertTrue(isLoading)
        XCTAssertFalse(isPlaying)
        audioFocused = true
        delay.completeAll()
        let didResume = await resumed.value
        XCTAssertTrue(didResume)
        XCTAssertEqual(player.playCount, 1)
        XCTAssertFalse(isLoading, "A canceled first-start task must not leave a permanent spinner")
        XCTAssertTrue(isPlaying)
        XCTAssertEqual(appliedAudioFocus, true, "Resume must apply current audio focus, not the captured pane")

        // A new explicit pause during a later wait cannot publish playing or
        // clear a new loading surface after its permission has been revoked.
        isLoading = true
        isPlaying = false
        let paused = Task {
            await MultiLiveNativeAudioResume.resume(using: delay.wait, expected: resumedIdentity,
                currentIdentity: currentIdentity, playbackMayStart: { foreground && userWantsPlayback },
                player: player,
                isLoading: Binding(get: { isLoading }, set: { isLoading = $0 }),
                isPlaying: Binding(get: { isPlaying }, set: { isPlaying = $0 }), updateAudio: {})
        }
        await waitUntil("Multi pending resume started") { delay.pendingCount == 1 }
        userWantsPlayback = false
        delay.completeAll()
        let resumedAfterPause = await paused.value
        XCTAssertFalse(resumedAfterPause)
        XCTAssertEqual(player.playCount, 1)
        XCTAssertTrue(isLoading)
        XCTAssertFalse(isPlaying)
    }

    func testMultiTerminalErrorDeniesLateAudioResumeWithoutPublishingPlaying() async {
        let delay = ControlledAudioPreparation()
        let player = AudioSpyPlayer()
        let identity = MediaAudioPlaybackIdentity(requestID: UUID(), sourceID: UUID(), intentID: UUID(),
                                                  player: player, item: nil)
        var terminalError: String?
        var isLoading = true, isPlaying = false, appliedAudio = false
        let task = Task {
            await MultiLiveNativeAudioResume.resume(using: delay.wait, expected: identity,
                currentIdentity: { identity }, playbackMayStart: { terminalError == nil }, player: player,
                isLoading: Binding(get: { isLoading }, set: { isLoading = $0 }),
                isPlaying: Binding(get: { isPlaying }, set: { isPlaying = $0 }),
                updateAudio: { appliedAudio = true })
        }
        await waitUntil("Multi terminal test preparation started") { delay.pendingCount == 1 }
        // The pane's terminal handler has published the error and ended loading;
        // exact item/source identity alone cannot authorize the late completion.
        terminalError = "This broadcast is unavailable"
        isLoading = false
        delay.completeAll()
        let resumed = await task.value
        XCTAssertFalse(resumed)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertFalse(appliedAudio)
        XCTAssertFalse(isLoading)
        XCTAssertFalse(isPlaying)
    }

    func testColdSingleRemotePauseRevokesFirstActivationAndDuplicatePlayDoesNotForkIt() async throws {
        let delay = ControlledAudioPreparation()
        let (model, player) = try makeNativeModel(preparation: delay.wait, withItem: true, singleRanking: true)
        defer { model.cleanup(); delay.completeAll() }
        model.transition(to: .connecting(.native), phase: "Buffering")
        let attempt = model.loadRequestID
        let first = Task { await model.requestPlaybackStart(player: player) }
        await waitUntil("cold activation suspended") { delay.pendingCount == 1 }
        model.requestPlayFromRemoteCommand()
        XCTAssertNil(model.audioPreparationTask, "A second Play cannot fork the first-start owner into ordinary resume")
        XCTAssertEqual(delay.pendingCount, 1)
        model.requestPauseFromRemoteCommand()
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        delay.completeAll()
        let started = await first.value
        XCTAssertFalse(started)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertFalse(model.isPlaybackWatchdogArmed)
    }

    func testColdSingleForegroundReentersFirstDisplayPreparationInsteadOfResumingOldItem() async throws {
        for pauseWhileDeferred in [false, true] {
            let delay = ControlledAudioPreparation()
            var validations = 0
            let (model, player) = try makeNativeModel(preparation: delay.wait, withItem: true, singleRanking: true,
                validation: { _, _ in
                    validations += 1
                    return .invalid("Controlled fresh preparation", diagnostics:
                        .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 403))
                })
            defer { model.cleanup(); delay.completeAll() }
            model.transition(to: .connecting(.native), phase: "Buffering")
            let original = model.loadRequestID
            let first = Task { await model.requestPlaybackStart(player: player) }
            await waitUntil("cold background activation suspended") { delay.pendingCount == 1 }
            model.handleScenePhaseChange(.background)
            XCTAssertNil(player.currentItem, "An unverified old item must not take the ordinary decoded-resume path")
            if pauseWhileDeferred { model.requestPauseFromRemoteCommand() }
            delay.completeAll()
            let started = await first.value
            XCTAssertFalse(started)
            model.handleScenePhaseChange(.active)
            if pauseWhileDeferred {
                XCTAssertEqual(validations, 0)
                XCTAssertFalse(model.userWantsPlayback)
                XCTAssertEqual(model.loadRequestID, original)
                model.requestPlayFromRemoteCommand()
            }
            await model.loadTask?.value
            XCTAssertEqual(validations, 1, "Resume must return to normal first-display preparation/validation")
            XCTAssertNotEqual(model.loadRequestID, original)
            XCTAssertEqual(player.playCount, 0, "The previously unverified item cannot be played by a resume callback")
            XCTAssertEqual(model.playbackState, .failed, "The injected rejection ends before any media request")
            XCTAssertNil(model.audioPreparationTask)
        }
    }

    private func makeNativeModel(preparation: @escaping @MainActor () async -> MediaAudioSessionPreparation,
                                 withItem: Bool = false, singleRanking: Bool = false,
                                 validation: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult = { _, _ in .valid }) throws -> (LivePlayerViewModel, AudioSpyPlayer) {
        let event = AnalyticalDataEngine.EventReference(id: "audio-owner-test", title: "Audio test",
            category: "football", date: 0, poster: nil, popular: false, teams: nil)
        let session = StreamSession(matchID: event.id,
            playableURL: try XCTUnwrap(URL(string: "https://example.invalid/audio-test.m3u8")),
            streamType: .hls, providerName: "CS1", requiredHeaders: [:],
            diagnosticMetadata: ["source_family": "communitysports", "source_key": "cs_000000000000000000000000"])
        let model = LivePlayerViewModel(event: event, providedSessions: [session],
            prepareAudioSession: preparation, validateNativeSource: validation)
        if singleRanking { XCTAssertTrue(model.configureSingleStreamRanking()) }
        XCTAssertNotNil(model.activeSource)
        XCTAssertFalse(model.isUsingWebEmbed)
        let player = AudioSpyPlayer()
        if withItem { player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition())) }
        model.player = player
        model.didApplyLandscape = true
        model.transition(to: .paused(.native), phase: "Paused")
        return (model, player)
    }

    private func waitUntil(_ label: String, file: StaticString = #filePath, line: UInt = #line,
                           _ predicate: () async -> Bool) async {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(2)
        while clock.now < deadline {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Request barrier timed out: \(label)", file: file, line: line)
    }
}

private final class ActivationDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MediaAudioSessionOwner.ActivationDiagnostic] = []
    func append(_ value: MediaAudioSessionOwner.ActivationDiagnostic) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }
    var values: [MediaAudioSessionOwner.ActivationDiagnostic] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private actor ImmediateAudioBackend: MediaAudioSessionBackend {
    private(set) var activations = 0
    func configure() async throws {}
    func activate() async throws { activations += 1 }
}

private actor ControlledAudioBackend: MediaAudioSessionBackend {
    enum Operation: Equatable, Sendable { case configure, activate }
    private(set) var calls: [Operation] = []
    private var pending: [(Operation, CheckedContinuation<Void, Error>)] = []

    func configure() async throws { try await suspend(.configure) }
    func activate() async throws { try await suspend(.activate) }
    func count(_ operation: Operation) -> Int { calls.filter { $0 == operation }.count }

    private func suspend(_ operation: Operation) async throws {
        calls.append(operation)
        try await withCheckedThrowingContinuation { pending.append((operation, $0)) }
    }

    func release(_ operation: Operation, errorCode: Int? = nil) {
        guard let index = pending.firstIndex(where: { $0.0 == operation }) else {
            XCTFail("No suspended \(operation) operation")
            return
        }
        let continuation = pending.remove(at: index).1
        if let errorCode { continuation.resume(throwing: NSError(domain: "SyntheticAudioTest", code: errorCode)) }
        else { continuation.resume() }
    }
}

@MainActor
private final class ControlledAudioPreparation {
    private var pending: [CheckedContinuation<MediaAudioSessionPreparation, Never>] = []
    var pendingCount: Int { pending.count }
    func wait() async -> MediaAudioSessionPreparation {
        await withCheckedContinuation { pending.append($0) }
    }
    func completeAll(_ result: MediaAudioSessionPreparation = .completed([])) {
        let waiters = pending
        pending.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
    }
}

private final class AudioSpyPlayer: AVPlayer {
    private(set) var playCount = 0
    override func play() { playCount += 1 }
}
