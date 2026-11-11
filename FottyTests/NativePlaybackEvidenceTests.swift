import XCTest
import SwiftUI
import AVFoundation
import WebKit
@testable import Fotty

@MainActor
final class NativePlaybackEvidenceTests: XCTestCase {
    func testPhysicalMeasurementScalarEncodingRejectsUnknownAndUnboundedValues() throws {
        let data = try XCTUnwrap(NativePlaybackMeasurementEncoding.json([
            "nan": NativePlaybackMeasurementEncoding.scalar(.nan),
            "infinity": NativePlaybackMeasurementEncoding.scalar(.infinity),
            "negative": NativePlaybackMeasurementEncoding.scalar(-1),
            "overflow": NativePlaybackMeasurementEncoding.scalar(Double.greatestFiniteMagnitude),
            "absent": NativePlaybackMeasurementEncoding.scalar(nil),
            "zero": NativePlaybackMeasurementEncoding.scalar(0),
            "known": NativePlaybackMeasurementEncoding.scalar(1.25)
        ]).data(using: .utf8))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["nan", "infinity", "negative", "overflow", "absent"] {
            XCTAssertTrue(values[key] is NSNull, "Unknown \(key) must not be reported as zero")
        }
        XCTAssertEqual(values["zero"] as? Double, 0)
        XCTAssertEqual(values["known"] as? Double, 1.25)
    }

    func testPhysicalMeasurementAbsentItemAndAccessLogRemainExplicitlyUnknown() throws {
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        defer { view.dismantlePlaybackBinding() }
        let data = try XCTUnwrap(view.physicalMeasurementSnapshot().data(using: .utf8))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(values["measurementAvailable"] as? Bool, false)
        XCTAssertEqual(values["accessLogAvailable"] as? Bool, false)
        for key in ["itemToken", "currentTimeSeconds", "bytesTransferred", "stalls", "observedBitrate"] {
            XCTAssertTrue(values[key] is NSNull)
        }
        XCTAssertFalse(values.keys.contains("uri"))
        XCTAssertFalse(values.keys.contains("serverAddress"))
        XCTAssertFalse(values.keys.contains("playbackSessionID"))
    }

    func testPhysicalMeasurementTokenCannotMixReplacedItemsOrAttempts() {
        let binding = NativePlaybackMeasurementBinding()
        let item = AVPlayerItem(asset: AVMutableComposition())
        let otherItem = AVPlayerItem(asset: AVMutableComposition())
        let attempt = UUID()
        let physical = binding.physicalItemToken(for: item)
        _ = binding.token(for: item, attempt: UUID())
        XCTAssertEqual(binding.physicalItemToken(for: item), physical)
        XCTAssertNotEqual(binding.physicalItemToken(for: otherItem), physical)
        let first = binding.token(for: item, attempt: attempt)
        XCTAssertNotNil(first)
        XCTAssertEqual(binding.token(for: item, attempt: attempt), first)
        let replacement = binding.token(for: otherItem, attempt: attempt)
        XCTAssertNotEqual(replacement, first)
        let newAttempt = binding.token(for: otherItem, attempt: UUID())
        XCTAssertNotEqual(newAttempt, replacement)
        XCTAssertNil(binding.token(for: nil, attempt: attempt))
        XCTAssertNotEqual(binding.token(for: item, attempt: attempt), first)
    }

    func testNativeStartupDoesNotMistakeTransportProgressForVideo() {
        XCTAssertFalse(NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: false, startSeconds: 0, currentSeconds: 20
        ))
        XCTAssertFalse(NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: true, startSeconds: 20, currentSeconds: 20
        ))
        XCTAssertFalse(NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: true, startSeconds: 20, currentSeconds: 19
        ))
        XCTAssertFalse(NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: true, startSeconds: .nan, currentSeconds: 20
        ))
        XCTAssertTrue(NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: true, startSeconds: 20, currentSeconds: 20.25
        ))
    }

    func testNativeStartupPreservesBufferingBeyondTheFormerThreeSecondCutoff() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        XCTAssertEqual(deadline.decision(at: 103, hasVerifiedVideoStart: false, hasFailedItem: false), .waiting)
        XCTAssertEqual(deadline.decision(at: 107, hasVerifiedVideoStart: false, hasFailedItem: false), .waiting)
        XCTAssertEqual(deadline.decision(at: 108, hasVerifiedVideoStart: true, hasFailedItem: false), .started)
    }

    func testNativeStartupRepeatedWaitingCannotRenewTheSharedDeadline() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        for elapsed: TimeInterval in [0, 3, 6, 7, 12, 19.75] {
            XCTAssertEqual(deadline.decision(at: 100 + elapsed, hasVerifiedVideoStart: false,
                                             hasFailedItem: false), .waiting)
        }
        XCTAssertEqual(NativePlaybackStartupDeadline.timeoutSeconds, 20)
        XCTAssertEqual(deadline.elapsed(at: 119.75), 19.75)
        XCTAssertEqual(deadline.remaining(at: 119.75), 0.25)
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: false, hasFailedItem: false), .timedOut)
        XCTAssertEqual(deadline.decision(at: 125, hasVerifiedVideoStart: false, hasFailedItem: false), .timedOut)
        XCTAssertEqual(deadline.remaining(at: 125), 0)
    }

    func testNativeStartupFinalSampleAcceptsDisplayedProgressAtTheDeadline() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        XCTAssertEqual(deadline.decision(at: 119.75, hasVerifiedVideoStart: false, hasFailedItem: false), .waiting)
        // The last quarter-second sleep can contain the first real frame. The
        // caller must sample it, not return a stale timeout result after sleep.
        let verified = NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: true, startSeconds: 0, currentSeconds: 0.25
        )
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: verified, hasFailedItem: false), .started)
        XCTAssertEqual(deadline.decision(at: 120.1, hasVerifiedVideoStart: verified, hasFailedItem: false), .started)
    }

    func testNativeStartupDeadlineDoesNotTreatReadinessOrClockProgressAsDecodedVideo() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 0)
        let audioClockOnly = NativePlaybackVideoPolicy.hasDisplayedProgress(
            isReadyForDisplay: false, startSeconds: 0, currentSeconds: 20
        )
        XCTAssertEqual(deadline.decision(at: 20, hasVerifiedVideoStart: audioClockOnly, hasFailedItem: false), .timedOut)
    }

    func testNativeStartupRejectsNonfiniteNegativeAndRegressingClocks() {
        for start: TimeInterval in [.nan, .infinity, -.infinity, -1] {
            let deadline = NativePlaybackStartupDeadline(startedAt: start)
            XCTAssertNil(deadline.elapsed(at: 20))
            XCTAssertNil(deadline.remaining(at: 20))
            XCTAssertEqual(deadline.decision(at: 20, hasVerifiedVideoStart: false, hasFailedItem: false), .invalidTiming)
        }
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        for now: TimeInterval in [.nan, .infinity, -.infinity, -1, 99.99] {
            XCTAssertNil(deadline.elapsed(at: now))
            XCTAssertNil(deadline.remaining(at: now))
            XCTAssertEqual(deadline.decision(at: now, hasVerifiedVideoStart: true, hasFailedItem: false), .invalidTiming)
        }
        let finiteLarge = NativePlaybackStartupDeadline(startedAt: 0)
        XCTAssertEqual(finiteLarge.decision(at: .greatestFiniteMagnitude,
            hasVerifiedVideoStart: false, hasFailedItem: false), .timedOut)
        XCTAssertEqual(finiteLarge.remaining(at: .greatestFiniteMagnitude), 0)
    }

    func testNativeStartupFatalItemFailureDoesNotWaitForTheDeadline() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        XCTAssertEqual(deadline.decision(at: 101, hasVerifiedVideoStart: false, hasFailedItem: true), .failed)
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: true, hasFailedItem: true), .failed)
    }

    func testNativeStartupCancellationDoesNotPublishFailureOrLateSuccess() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: true, hasFailedItem: true,
                                         isCancelled: true), .abandoned)
    }

    func testNativeStartupReplacedOwnerCannotTimeoutOrClaimItsSuccess() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        for hasProgress in [false, true] {
            XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: hasProgress, hasFailedItem: false,
                                             ownsCurrentAttempt: false), .abandoned)
        }
    }

    func testNativeStartupManualPauseIsAbandonmentNotAReasonToRetry() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100)
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: false, hasFailedItem: false,
                                         userWantsPlayback: false), .abandoned)
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: true, hasFailedItem: true,
                                         userWantsPlayback: false), .abandoned)
    }

    func testReviewedLSStartupProfileRequiresTheExactSingleStreamDeliveryContract() {
        let session = reviewedLSSession()
        XCTAssertTrue(CNCSportsAddonClient.isReviewedNativeSession(session))
        XCTAssertEqual(NativePlaybackStartupDeadline.budget(for: session, context: .single,
            isNativeHandoff: false), .reviewedLSSingleStream)
        for context: ViewingPlaybackContext in [.watchTwo(engine: .native), .watchTwo(engine: .web)] {
            XCTAssertEqual(NativePlaybackStartupDeadline.budget(for: session, context: context,
                isNativeHandoff: false), .standard)
        }
        XCTAssertEqual(NativePlaybackStartupDeadline.budget(for: session, context: .single,
            isNativeHandoff: true), .standard)
        XCTAssertEqual(NativePlaybackStartupDeadline(startedAt: 0).budget.seconds, 20,
                       "Unprofiled native, handoff and pair constructors retain the existing budget")
    }

    func testReviewedLSStartupProfileRejectsSpoofedOrAlteredContracts() {
        var wrongHeaders = CNCSportsAddonClient.reviewedHeaders
        wrongHeaders["Origin"] = "https://example.invalid"
        let hostile: [StreamSession] = [
            reviewedLSSession(family: "communitysports"),
            reviewedLSSession(provider: "CS1"),
            reviewedLSSession(provider: "LS7"),
            reviewedLSSession(provider: "LS1\n"),
            reviewedLSSession(type: .mp4),
            reviewedLSSession(type: .unknown),
            reviewedLSSession(url: "https://example.invalid/hls/test.m3u8"),
            reviewedLSSession(url: "http://edgestream7.pro/hls/test.m3u8"),
            reviewedLSSession(url: "https://edgestream7.pro:8443/hls/test.m3u8"),
            reviewedLSSession(url: "https://edgestream7.pro/hls/test.m3u8?token=not-reviewed"),
            reviewedLSSession(url: "https://edgestream4.pro/hls/test.m3u8"),
            reviewedLSSession(headers: wrongHeaders),
            reviewedLSSession(headers: [:]),
            reviewedLSSession(guardedRelay: false),
            reviewedLSSession(canRefresh: true),
            reviewedLSSession(manifestResult: "catalog_name_only"),
            reviewedLSSession(delivery: "native_web_handoff"),
            reviewedLSSession(sourceKey: "ls_unverified")
        ]
        for session in hostile {
            XCTAssertFalse(CNCSportsAddonClient.isReviewedNativeSession(session))
            XCTAssertEqual(NativePlaybackStartupDeadline.budget(for: session, context: .single,
                isNativeHandoff: false), .standard)
        }
    }

    func testReviewedLSStartupWaitsAt20AndAcceptsDisplayedProgressAt25() {
        let budget = NativePlaybackStartupDeadline.budget(for: reviewedLSSession(), context: .single,
                                                        isNativeHandoff: false)
        let deadline = NativePlaybackStartupDeadline(startedAt: 100, budget: budget)
        XCTAssertEqual(deadline.budget.seconds, 30)
        XCTAssertEqual(deadline.decision(at: 120, hasVerifiedVideoStart: false, hasFailedItem: false), .waiting)
        XCTAssertEqual(deadline.remaining(at: 120), 10)
        XCTAssertEqual(deadline.decision(at: 125, hasVerifiedVideoStart: true, hasFailedItem: false), .started)
        XCTAssertEqual(NativePlaybackStartupDeadline(startedAt: 100).decision(at: 120,
            hasVerifiedVideoStart: false, hasFailedItem: false), .timedOut)
    }

    func testReviewedLSStartupBudgetCannotRenewIts30SecondHardDeadline() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100, budget: .reviewedLSSingleStream)
        for elapsed: TimeInterval in [0, 3, 12, 19.75, 20, 25, 29.75] {
            XCTAssertEqual(deadline.decision(at: 100 + elapsed, hasVerifiedVideoStart: false,
                                             hasFailedItem: false), .waiting)
        }
        XCTAssertEqual(deadline.remaining(at: 129.75), 0.25)
        for now: TimeInterval in [130, 135] {
            XCTAssertEqual(deadline.decision(at: now, hasVerifiedVideoStart: false,
                                             hasFailedItem: false), .timedOut)
            XCTAssertEqual(deadline.remaining(at: now), 0)
        }
        XCTAssertEqual(deadline.decision(at: 130, hasVerifiedVideoStart: true,
                                         hasFailedItem: false), .started,
                       "A real final-frame sample still wins over an expired sleep")
    }

    func testReviewedLSStartupBudgetPreservesPauseCancellationOwnershipFatalAndClockGuards() {
        let deadline = NativePlaybackStartupDeadline(startedAt: 100, budget: .reviewedLSSingleStream)
        XCTAssertEqual(deadline.decision(at: 125, hasVerifiedVideoStart: true, hasFailedItem: true,
                                         isCancelled: true), .abandoned)
        XCTAssertEqual(deadline.decision(at: 135, hasVerifiedVideoStart: true, hasFailedItem: true,
                                         ownsCurrentAttempt: false), .abandoned)
        XCTAssertEqual(deadline.decision(at: 135, hasVerifiedVideoStart: true, hasFailedItem: true,
                                         userWantsPlayback: false), .abandoned)
        XCTAssertEqual(deadline.decision(at: 101, hasVerifiedVideoStart: false, hasFailedItem: true), .failed)
        XCTAssertEqual(deadline.decision(at: 130, hasVerifiedVideoStart: true, hasFailedItem: true), .failed)
        for now: TimeInterval in [.nan, .infinity, -.infinity, 99] {
            XCTAssertEqual(deadline.decision(at: now, hasVerifiedVideoStart: true,
                                             hasFailedItem: false), .invalidTiming)
            XCTAssertNil(deadline.remaining(at: now))
        }
    }

    private func reviewedLSSession(
        url: String = "https://edgestream7.pro/hls/reviewed_test.m3u8", type: StreamType = .hls,
        provider: String = "LS1", headers: [String: String]? = nil, family: String = "cncsports",
        guardedRelay: Bool = true, canRefresh: Bool = false, manifestResult: String = "exact_fixture_match",
        delivery: String = "reviewed_direct_hls", sourceKey: String? = nil
    ) -> StreamSession {
        let endpoint = URL(string: url)!
        let headers = headers ?? CNCSportsAddonClient.reviewedHeaders
        return StreamSession(matchID: "reviewed-ls-startup", playableURL: endpoint, streamType: type,
            providerName: provider, requiredHeaders: headers, canRefresh: canRefresh,
            diagnosticMetadata: ["source_family": family, "manifest_result": manifestResult,
                "delivery": delivery, "source_key": sourceKey ?? CNCSportsAddonClient.sourceKey(url: endpoint, headers: headers)],
            requiresGuardedRelay: guardedRelay)
    }

    func testUndisplayedHandoffRequiresTwoRealAdvancingFrames() {
        var proof = NativePlaybackFrameProgress()
        XCTAssertFalse(proof.observe(seconds: .nan, width: 1920, height: 1080))
        XCTAssertFalse(proof.observe(seconds: 1, width: 0, height: 0))
        XCTAssertFalse(proof.observe(seconds: 1, width: 16, height: 16))
        XCTAssertFalse(proof.observe(seconds: 1, width: 1920, height: 1080))
        XCTAssertFalse(proof.observe(seconds: 1, width: 1920, height: 1080))
        XCTAssertTrue(proof.observe(seconds: 1.04, width: 1920, height: 1080))
    }

    func testRegressingCandidateTimelineMustEstablishForwardProgressAgain() {
        var proof = NativePlaybackFrameProgress()
        XCTAssertFalse(proof.observe(seconds: 20, width: 1280, height: 720))
        XCTAssertFalse(proof.observe(seconds: 1, width: 1280, height: 720))
        XCTAssertFalse(proof.observe(seconds: 1, width: 1280, height: 720))
        XCTAssertTrue(proof.observe(seconds: 1.04, width: 1280, height: 720))
    }

    func testWatchTwoTransientInactiveOverlayPreservesBothPlaybackOwners() {
        for phase: ScenePhase in [.active, .inactive] {
            XCTAssertTrue(MultiLiveScenePolicy.isForeground(phase))
            XCTAssertFalse(MultiLiveScenePolicy.shouldSuspendWebPlayback(
                phase, isNetworkReachable: true
            ))
        }
        XCTAssertFalse(MultiLiveScenePolicy.isForeground(.background))
        XCTAssertTrue(MultiLiveScenePolicy.shouldSuspendWebPlayback(
            .background, isNetworkReachable: true
        ))
        XCTAssertTrue(MultiLiveScenePolicy.shouldSuspendWebPlayback(
            .inactive, isNetworkReachable: false
        ))
    }

    func testWatchTwoTypedNativeSourceGetsOneSameSourceRetryBeforeExhaustion() {
        for type: StreamType in [.hls, .mp4] {
            let session = makeSession(type: type)
            let slot = MultiLiveSlot(event: makeEvent(), sessions: [session])
            XCTAssertEqual(recovery(slot: slot, session: session, retryCount: 0),
                           .retryNativeStartup(.startupTimeout))
            XCTAssertEqual(recovery(slot: slot, session: session, retryCount: 1),
                           .exhaustSource(.startupTimeout))
        }
    }

    func testWatchTwoExplicitRejectionAndNativeStallDoNotReceiveStartupRetry() {
        let session = makeSession(type: .hls)
        let slot = MultiLiveSlot(event: makeEvent(), sessions: [session])
        XCTAssertEqual(recovery(slot: slot, session: session, retryCount: 0,
                                reason: "Broadcast is unavailable"),
                       .exhaustSource(.providerUnavailable))
        XCTAssertEqual(recovery(slot: slot, session: session, retryCount: 0,
                                reason: "Frozen.", countsAsStall: true),
                       .exhaustSource(.stalled))
        XCTAssertEqual(slot.recoveryAction(
            for: session.legacySource, reason: "Network offline", countsAsStall: false,
            isNetworkReachable: false, webStartupRetryCount: 0,
            webStallRetryCount: 0, nativeStartupRetryCount: 0
        ), .waitForNetwork(.network))
    }

    func testWatchTwoWebWrapperStillUsesIndependentBoundedWebBudget() {
        let session = makeSession(type: .unknown, web: true)
        let slot = MultiLiveSlot(event: makeEvent(), sessions: [session])
        XCTAssertEqual(recovery(slot: slot, session: session, retryCount: 1),
                       .retryWebStartup(.startupTimeout))
        XCTAssertEqual(slot.recoveryAction(
            for: session.legacySource, reason: "Failed to start", countsAsStall: false,
            isNetworkReachable: true, webStartupRetryCount: 1,
            webStallRetryCount: 0, nativeStartupRetryCount: 0
        ), .exhaustSource(.startupTimeout))
    }

    private func recovery(
        slot: MultiLiveSlot, session: StreamSession, retryCount: Int,
        reason: String = "Failed to start", countsAsStall: Bool = false
    ) -> LivePlaybackRecoveryPolicy.Action {
        slot.recoveryAction(
            for: session.legacySource, reason: reason, countsAsStall: countsAsStall,
            isNetworkReachable: true, webStartupRetryCount: 0,
            webStallRetryCount: 0, nativeStartupRetryCount: retryCount
        )
    }

    private func makeSession(type: StreamType, web: Bool = false) -> StreamSession {
        StreamSession(
            matchID: "native-evidence",
            // Endpoint type comes from the contract, not a nested query URL.
            playableURL: URL(string: "https://example.invalid/play?next=other.m3u8")!,
            streamType: type, providerName: "CS1",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:]
        )
    }

    private func makeEvent() -> AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(
            id: "native-evidence", title: "Playback test", category: "football",
            date: 0, poster: nil, popular: false, teams: nil)
    }
}

@MainActor
final class NativePlaybackRetirementTests: XCTestCase {
    func testHandoffAudioPolicyIsAppliedOnlyByCurrentRetiredWebAttempt() async throws {
        let (model, session, candidate) = makeAdoptedCandidate()
        defer { model.cleanup() }
        let attempt = model.loadRequestID
        let unchangedMute = !AppRuntime.shouldMutePlaybackForTesting
        candidate.isMuted = unchangedMute
        candidate.volume = 0.5

        model.handleWebPlaybackRetired(sourceID: UUID(), requestID: attempt)
        model.handleWebPlaybackRetired(sourceID: session.id, requestID: UUID())
        XCTAssertEqual(candidate.isMuted, unchangedMute)
        XCTAssertEqual(candidate.volume, 0.5)

        model.handleWebPlaybackRetired(sourceID: session.id, requestID: attempt)
        XCTAssertTrue(candidate.isMuted, "Retirement must hold mute until activation completes")
        XCTAssertEqual(candidate.volume, 0)
        let claim = try XCTUnwrap(model.nativeHandoffAudioClaimTask)
        await claim.value
        XCTAssertEqual(candidate.isMuted, AppRuntime.shouldMutePlaybackForTesting)
        XCTAssertEqual(candidate.volume, AppRuntime.shouldMutePlaybackForTesting ? 0 : 1)
    }

    func testRetiredCallbackCannotActivateCandidateAfterCancellationOrWebReturn() {
        let (model, session, candidate) = makeAdoptedCandidate()
        defer { model.cleanup() }
        let attempt = model.loadRequestID
        candidate.volume = 0.5

        model.forceWebEmbedSourceIDs.insert(session.id)
        model.handleWebPlaybackRetired(sourceID: session.id, requestID: attempt)
        XCTAssertEqual(candidate.volume, 0.5)

        model.forceWebEmbedSourceIDs.removeAll()
        model.cancelLoading()
        model.handleWebPlaybackRetired(sourceID: session.id, requestID: attempt)
        XCTAssertEqual(candidate.volume, 0.5)

        model.cleanup()
        model.handleWebPlaybackRetired(sourceID: session.id, requestID: model.loadRequestID)
        XCTAssertEqual(candidate.volume, 0.5)
    }

    func testWebRetirementWaitsForMediaSuspensionAcknowledgementAndIsOneShot() {
        let webView = RetirementAcknowledgingWebView(frame: .zero)
        var acknowledgements = 0
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackRetired: {
            acknowledgements += 1
        })
        coordinator.webView = webView

        LiveWebEmbedPlayerView.dismantleUIView(webView, coordinator: coordinator)
        XCTAssertTrue(webView.didPauseAllMedia)
        XCTAssertTrue(webView.didSuspendAllMedia)
        XCTAssertEqual(acknowledgements, 0)
        XCTAssertNil(coordinator.onPlaybackRetired)
        XCTAssertNil(coordinator.webView)

        webView.acknowledgeSuspension()
        XCTAssertEqual(acknowledgements, 1)
        webView.acknowledgeSuspension()
        XCTAssertEqual(acknowledgements, 1)
    }

    private func makeAdoptedCandidate() -> (LivePlayerViewModel, StreamSession, AVPlayer) {
        let event = AnalyticalDataEngine.EventReference(
            id: "native-retirement", title: "Playback test", category: "football",
            date: 0, poster: nil, popular: false, teams: nil)
        let web = StreamSession(
            matchID: event.id, playableURL: URL(string: "https://example.invalid/embed/game")!,
            streamType: .unknown, providerName: "Score808",
            requiredHeaders: ["X-Fotty-Web-Embed": "true"]
        )
        let model = LivePlayerViewModel(event: event, providedSessions: [web],
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) })
        model.nativeHandoffSession = StreamSession(
            id: web.id, matchID: event.id, playableURL: URL(string: "https://example.invalid/video.m3u8")!,
            streamType: .hls, providerName: "Score808"
        )
        let candidate = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.holdNativeHandoffAudioUntilWebRetirement()
        model.player = candidate
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.native), phase: "Playing")
        return (model, web, candidate)
    }
}

@MainActor
private final class RetirementAcknowledgingWebView: WKWebView {
    private(set) var didPauseAllMedia = false
    private(set) var didSuspendAllMedia = false
    private var suspensionCompletion: (@MainActor () -> Void)?

    override func pauseAllMediaPlayback(completionHandler: (@MainActor () -> Void)?) {
        didPauseAllMedia = true
        completionHandler?()
    }

    override func setAllMediaPlaybackSuspended(
        _ suspended: Bool, completionHandler: (@MainActor () -> Void)?
    ) {
        didSuspendAllMedia = suspended
        suspensionCompletion = completionHandler
    }

    override func closeAllMediaPresentations(completionHandler: (@MainActor () -> Void)?) {
        completionHandler?()
    }

    override func stopLoading() {}

    func acknowledgeSuspension() {
        let completion = suspensionCompletion
        suspensionCompletion = nil
        completion?()
    }
}

/// These barriers exercise only an injected setter. No platform audio-session
/// API, media decoding, provider request or device connection is opened.
@MainActor
final class NativePlayerAudioIsolationTests: XCTestCase {
    func testDisconnectMustBeAcknowledgedBeforeBarrierCanAuthorizePlayback() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        let barrier = owner.request(disconnected: true)
        var result: Bool?
        let waiter = Task { result = await barrier.wait() }

        await waitUntil("disconnect setter entered") { backend.calls.count == 1 }
        XCTAssertEqual(backend.calls, [true])
        XCTAssertNil(result)
        XCTAssertFalse(barrier.isSatisfied)

        backend.completeNext()
        await waiter.value
        XCTAssertEqual(result, true)
        XCTAssertTrue(barrier.isSatisfied)
        XCTAssertEqual(backend.verifiedDisconnected, true)
    }

    func testRevocationSerializesAfterLateReconnectAndEndsDisconnected() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        let reconnect = owner.request(disconnected: false)
        let oldWaiter = Task { await reconnect.wait() }
        await waitUntil("reconnect setter entered") { backend.calls.count == 1 }

        let revoke = owner.request(disconnected: true)
        XCTAssertEqual(backend.calls, [false], "A second setter cannot overtake the pending reconnect")
        XCTAssertFalse(reconnect.isSatisfied)
        XCTAssertFalse(revoke.isSatisfied)

        backend.completeNext()
        await waitUntil("late reconnect reconciled to disconnection") { backend.calls.count == 2 }
        XCTAssertEqual(backend.calls, [false, true])
        XCTAssertEqual(backend.maximumInFlight, 1)
        XCTAssertEqual(backend.verifiedDisconnected, false)
        let oldAccepted = await oldWaiter.value
        XCTAssertFalse(oldAccepted)

        backend.completeNext()
        let revokeAccepted = await revoke.wait()
        XCTAssertTrue(revokeAccepted)
        XCTAssertEqual(backend.verifiedDisconnected, true)
        XCTAssertTrue(revoke.isSatisfied)
        XCTAssertFalse(reconnect.isSatisfied)
    }

    func testOldReconnectGenerationCannotAuthorizeAReissuedReconnect() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        let old = owner.request(disconnected: false)
        let oldWaiter = Task { await old.wait() }
        await waitUntil("old reconnect setter entered") { backend.calls.count == 1 }
        let revoked = owner.request(disconnected: true)
        let current = owner.request(disconnected: false)
        XCTAssertNotEqual(old.revision, current.revision)

        backend.completeNext()
        await waitUntil("new generation setter entered") { backend.calls.count == 2 }
        XCTAssertEqual(backend.calls, [false, false])
        let oldAccepted = await oldWaiter.value
        XCTAssertFalse(oldAccepted)
        XCTAssertFalse(old.isSatisfied)
        XCTAssertFalse(revoked.isSatisfied)
        XCTAssertFalse(current.isSatisfied)

        backend.completeNext()
        let currentAccepted = await current.wait()
        XCTAssertTrue(currentAccepted)
        XCTAssertTrue(current.isSatisfied)
        XCTAssertFalse(old.isSatisfied, "Matching Boolean state cannot revive a superseded ownership generation")
    }

    func testCleanupDisconnectionContinuesWhenItsAwaitingTaskIsCancelled() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        let connected = owner.request(disconnected: false)
        await waitUntil("initial reconnect setter entered") { backend.calls.count == 1 }
        backend.completeNext()
        let connectedAccepted = await connected.wait()
        XCTAssertTrue(connectedAccepted)

        let cleanup = owner.request(disconnected: true)
        let waiter = Task { await cleanup.wait() }
        await waitUntil("cleanup setter entered") { backend.calls.count == 2 }
        waiter.cancel()
        backend.completeNext()
        _ = await waiter.value

        let cleanupAccepted = await cleanup.wait()
        XCTAssertTrue(cleanupAccepted)
        XCTAssertTrue(cleanup.isSatisfied)
        XCTAssertEqual(backend.calls, [false, true])
        XCTAssertEqual(backend.verifiedDisconnected, true,
                       "Cancelling a caller cannot abandon an already-issued platform cleanup")
    }

    func testItemReplacementDuringReconnectRejectsItsWaiterAndReconcilesDisconnected() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        let reconnect = owner.request(disconnected: false)
        let waiter = Task { await reconnect.wait() }
        await waitUntil("reconnect pending before item replacement") { backend.calls.count == 1 }
        let replacement = AVPlayerItem(asset: AVMutableComposition())
        owner.player.replaceCurrentItem(with: replacement)

        backend.completeNext()
        await waitUntil("replacement forced disconnection") { backend.calls.count == 2 }
        let oldAccepted = await waiter.value
        XCTAssertFalse(oldAccepted)
        XCTAssertFalse(reconnect.isSatisfied)
        XCTAssertEqual(backend.calls, [false, true])
        XCTAssertTrue(owner.player.currentItem === replacement)

        backend.completeNext()
        let disconnected = owner.currentBarrier
        let disconnectedAccepted = await disconnected?.wait()
        XCTAssertEqual(disconnectedAccepted, true)
        XCTAssertEqual(backend.verifiedDisconnected, true)
        XCTAssertFalse(reconnect.isSatisfied)
    }

    func testItemReplacementAfterSettledReconnectRejectsAnotherAudibleRequest() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        let settled = owner.request(disconnected: false)
        await waitUntil("initial reconnect before replacement") { backend.calls.count == 1 }
        backend.completeNext()
        let settledAccepted = await settled.wait()
        XCTAssertTrue(settledAccepted)

        let replacement = AVPlayerItem(asset: AVMutableComposition())
        owner.player.replaceCurrentItem(with: replacement)
        XCTAssertFalse(settled.isSatisfied)
        let rejected = owner.request(disconnected: false)
        let rejectedAccepted = await rejected.wait()
        XCTAssertFalse(rejectedAccepted)
        await waitUntil("settled old item reconciled to disconnection") { backend.calls.count == 2 }
        XCTAssertEqual(backend.calls, [false, true], "A replacement item cannot inherit the old audible connection")

        backend.completeNext()
        let disconnectedAccepted = await owner.currentBarrier?.wait()
        XCTAssertEqual(disconnectedAccepted, true)
        XCTAssertEqual(backend.verifiedDisconnected, true)
        XCTAssertTrue(owner.player.currentItem === replacement)
        XCTAssertFalse(settled.isSatisfied)
        XCTAssertFalse(rejected.isSatisfied)
    }

    func testRepeatedSettledDesiredStateReusesBarrierWithoutAnotherSetter() async {
        let (owner, backend) = makeOwner()
        defer { backend.finishAll() }
        for disconnected in [true, false] {
            let request = owner.request(disconnected: disconnected)
            let expectedCount = disconnected ? 1 : 2
            await waitUntil("desired-state setter entered") { backend.calls.count == expectedCount }
            backend.completeNext()
            let accepted = await request.wait()
            XCTAssertTrue(accepted)

            let repeated = owner.request(disconnected: disconnected)
            XCTAssertEqual(repeated.revision, request.revision)
            XCTAssertEqual(repeated.identity, request.identity)
            XCTAssertTrue(repeated.isSatisfied)
            let repeatedAccepted = await repeated.wait()
            XCTAssertTrue(repeatedAccepted)
            XCTAssertEqual(backend.calls.count, expectedCount)
        }
        XCTAssertEqual(backend.calls, [true, false])
    }

    private func makeOwner() -> (NativePlayerAudioIsolation, ControlledNativeAudioIsolationBackend) {
        let backend = ControlledNativeAudioIsolationBackend()
        let item = AVPlayerItem(asset: AVMutableComposition())
        let player = AVPlayer(playerItem: item)
        let owner = NativePlayerAudioIsolation(player: player, item: item,
            backend: .init(isSupported: true, setDisconnected: { player, disconnected in
                await backend.setDisconnected(player, disconnected)
            }))
        return (owner, backend)
    }

    private func waitUntil(_ label: String, file: StaticString = #filePath, line: UInt = #line,
                           _ predicate: () -> Bool) async {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(2)
        while clock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Audio-isolation barrier timed out: \(label)", file: file, line: line)
    }
}

@MainActor
private final class ControlledNativeAudioIsolationBackend {
    private struct Pending {
        let disconnected: Bool
        let continuation: CheckedContinuation<Bool, Never>
    }
    private(set) var calls: [Bool] = []
    private(set) var verifiedDisconnected: Bool?
    private(set) var maximumInFlight = 0
    private var pending: [Pending] = []
    private var completesImmediately = false

    func setDisconnected(_ player: AVPlayer, _ disconnected: Bool) async -> Bool {
        calls.append(disconnected)
        if completesImmediately {
            verifiedDisconnected = disconnected
            return true
        }
        return await withCheckedContinuation { continuation in
            pending.append(.init(disconnected: disconnected, continuation: continuation))
            maximumInFlight = max(maximumInFlight, pending.count)
        }
    }

    func completeNext() {
        guard !pending.isEmpty else { XCTFail("No injected audio-isolation setter is awaiting acknowledgement"); return }
        let request = pending.removeFirst()
        verifiedDisconnected = request.disconnected
        request.continuation.resume(returning: true)
    }

    func finishAll() {
        completesImmediately = true
        let requests = pending
        pending = []
        for request in requests {
            verifiedDisconnected = request.disconnected
            request.continuation.resume(returning: true)
        }
    }
}

@MainActor
final class NativeTransferWebSuspensionTests: XCTestCase {
    func testTransferUsesOneBalancedPublicSuspensionWithAcknowledgedGrantAndImmediateRevocation() throws {
        var acknowledgements: [(UUID, Bool)] = []
        let (owner, view, _) = try makeOwner { acknowledgements.append(($0, $1)) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let transfer = UUID()
        owner.requestNativeTransferSuspension(transfer)
        owner.requestNativeTransferSuspension(transfer)
        XCTAssertEqual(view.suspensions, [true])
        XCTAssertTrue(acknowledgements.isEmpty)
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.0), [transfer])
        XCTAssertEqual(acknowledgements.map(\.1), [true])

        owner.requestNativeTransferSuspension(nil)
        owner.requestNativeTransferSuspension(nil)
        XCTAssertEqual(view.suspensions, [true, false])
        XCTAssertEqual(acknowledgements.map(\.1), [true, false], "Authorization is revoked before platform release")
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.0), [transfer, transfer])
        XCTAssertEqual(acknowledgements.map(\.1), [true, false])
        XCTAssertEqual(view.pauseCount, 0, "A reversible transfer must not erase WebKit's prior playing state")
        XCTAssertTrue(view.scripts.allSatisfy { !$0.contains(".pause(") && !$0.contains(".play(") && !$0.contains(".muted") })
    }

    func testCancelledPendingAcquireCannotDeliverTrueAndReleasesBeforeNewAcquire() throws {
        var acknowledgements: [(UUID, Bool)] = []
        let (owner, view, _) = try makeOwner { acknowledgements.append(($0, $1)) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let old = UUID(), replacement = UUID()
        owner.requestNativeTransferSuspension(old)
        owner.requestNativeTransferSuspension(nil)
        owner.requestNativeTransferSuspension(replacement)
        XCTAssertEqual(view.suspensions, [true])
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.1), [false])
        XCTAssertEqual(view.suspensions, [true, false])
        view.acknowledgeNextSuspension()
        XCTAssertEqual(view.suspensions, [true, false, true])
        XCTAssertEqual(acknowledgements.map(\.0), [old])
        XCTAssertEqual(acknowledgements.map(\.1), [false])
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.0), [old, replacement])
        XCTAssertEqual(acknowledgements.map(\.1), [false, true])
    }

    func testExplicitPauseWhileAcquiringIsAcknowledgedBeforeReleaseAndCannotGrantNativePlay() throws {
        var acknowledgements: [(UUID, Bool)] = []
        let (owner, view, _) = try makeOwner { acknowledgements.append(($0, $1)) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let transfer = UUID()
        owner.requestNativeTransferSuspension(transfer)
        owner.playbackCommandWillApply(.init(id: UUID(), shouldPlay: false))
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.1), [false])
        XCTAssertEqual(view.pauseCount, 1)
        XCTAssertEqual(view.suspensions, [true], "Pause ACK must precede the matching false setter")
        view.acknowledgeNextPause()
        XCTAssertEqual(view.suspensions, [true, false])
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.0), [transfer])
        XCTAssertEqual(acknowledgements.map(\.1), [false])
    }

    func testSourceReplacementRevokesPendingAuthorizationAndRejectsLateTrue() throws {
        var acknowledgements: [(UUID, Bool)] = []
        let (owner, view, url) = try makeOwner { acknowledgements.append(($0, $1)) }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.requestNativeTransferSuspension(UUID())
        owner.beginLoading(url: url, referer: "", attemptID: UUID())
        view.acknowledgeNextSuspension()
        XCTAssertEqual(view.suspensions, [true, false])
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements.map(\.1), [false], "Old authorization must be revoked even when its document is gone")
    }

    func testTransferContainsOnlyOwnedObservationsAndLeavesOrdinaryUnknownPauseVisible() throws {
        var states: [WebPlaybackTransportState] = []
        var recoveries = 0
        let (owner, view, _) = try makeOwner { _, _ in }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.onTransportStateChanged = { states.append($0) }
        owner.onPlaybackRecovered = { recoveries += 1 }
        let attempt = try XCTUnwrap(owner.loadedAttemptID)
        func observation(_ type: String, reason: String = "") -> [String: Any] {
            ["type": type, "reason": reason, "attemptID": attempt.uuidString, "documentID": "transfer-owner"]
        }
        owner.requestNativeTransferSuspension(UUID())
        view.acknowledgeNextSuspension()
        owner.handlePlaybackMessage(observation("transport_state", reason: "paused"))
        owner.handlePlaybackMessage(observation("playback_recovered"))
        XCTAssertTrue(states.isEmpty)
        XCTAssertEqual(recoveries, 0)
        owner.requestNativeTransferSuspension(nil)
        owner.handlePlaybackMessage(observation("transport_state", reason: "playing"))
        XCTAssertTrue(states.isEmpty, "Release is still owned until its ACK")
        view.acknowledgeNextSuspension()
        owner.handlePlaybackMessage(observation("transport_state", reason: "paused"))
        XCTAssertEqual(states, [.paused])
    }

    func testTeardownNeverDeliversPendingTransferAuthorization() throws {
        var acknowledgements: [(UUID, Bool)] = []
        let (owner, view, _) = try makeOwner { acknowledgements.append(($0, $1)) }
        defer { view.finishAll() }
        owner.requestNativeTransferSuspension(UUID())
        LiveWebEmbedPlayerView.dismantleUIView(view, coordinator: owner)
        view.finishAll()
        XCTAssertEqual(acknowledgements.map(\.1), [false])
        XCTAssertNil(owner.webView)
    }

    func testInputShieldRestoresOnlyTheOriginalInteractionValueAfterRelease() throws {
        for initiallyEnabled in [true, false] {
            let (owner, view, _) = try makeOwner { _, _ in }
            defer { owner.invalidateLoading(); view.finishAll() }
            view.isUserInteractionEnabled = initiallyEnabled
            owner.requestNativeTransferSuspension(UUID())
            XCTAssertFalse(view.isUserInteractionEnabled)
            view.acknowledgeNextSuspension()
            owner.requestNativeTransferSuspension(nil)
            XCTAssertFalse(view.isUserInteractionEnabled, "The release operation still owns input until ACK")
            view.acknowledgeNextSuspension()
            XCTAssertEqual(view.isUserInteractionEnabled, initiallyEnabled)
        }
    }

    func testStaleAndTeardownRestoreShieldWithoutEnablingOriginallyDisabledView() throws {
        for initiallyEnabled in [true, false] {
            let (owner, view, _) = try makeOwner { _, _ in }
            defer { view.finishAll() }
            view.isUserInteractionEnabled = initiallyEnabled
            owner.requestNativeTransferSuspension(UUID())
            XCTAssertFalse(view.isUserInteractionEnabled)
            LiveWebEmbedPlayerView.dismantleUIView(view, coordinator: owner)
            XCTAssertEqual(view.isUserInteractionEnabled, initiallyEnabled)
            view.finishAll()
            XCTAssertEqual(view.isUserInteractionEnabled, initiallyEnabled)
        }
    }

    func testQueuedProviderPauseBeforeAcquireAckRevokesAndPreservesBalancedPauseRelease() throws {
        var states: [WebPlaybackTransportState] = []
        var acknowledgements: [Bool] = []
        let (owner, view, _) = try makeOwner { _, enabled in acknowledgements.append(enabled) }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.onTransportStateChanged = { states.append($0) }
        let transfer = UUID(), attempt = try XCTUnwrap(owner.loadedAttemptID)
        owner.requestNativeTransferSuspension(transfer)
        owner.handlePlaybackMessage(["type": "transport_state", "reason": "paused",
            "attemptID": attempt.uuidString, "documentID": "transfer-owner"])
        XCTAssertEqual(states, [.paused])
        XCTAssertEqual(acknowledgements, [false])
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements, [false], "A queued provider Pause can never grant native Play")
        XCTAssertEqual(view.suspensions, [true])
        XCTAssertEqual(view.pauseCount, 1)
        view.acknowledgeNextPause()
        XCTAssertEqual(view.suspensions, [true, false])
        view.acknowledgeNextSuspension()
        XCTAssertTrue(view.isUserInteractionEnabled)
        XCTAssertEqual(acknowledgements, [false])
    }

    func testDocumentReleaseRevokesAnAcknowledgedGrantImmediatelyOnlyOnce() throws {
        var acknowledgements: [Bool] = []
        let (owner, view, _) = try makeOwner { _, enabled in acknowledgements.append(enabled) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let attempt = try XCTUnwrap(owner.loadedAttemptID)
        owner.requestNativeTransferSuspension(UUID())
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements, [true])
        owner.handlePlaybackMessage(["type": "playback_released", "attemptID": attempt.uuidString,
                                     "documentID": "transfer-owner"])
        XCTAssertEqual(acknowledgements, [true, false])
        XCTAssertTrue(view.isUserInteractionEnabled)
        view.acknowledgeNextSuspension()
        XCTAssertEqual(acknowledgements, [true, false])
    }

    func testRetiredLeaseCannotHideReplacementDocumentsUnknownPauseDuringRelease() throws {
        var states: [WebPlaybackTransportState] = []
        let (owner, view, url) = try makeOwner { _, _ in }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.onTransportStateChanged = { states.append($0) }
        owner.requestNativeTransferSuspension(UUID())
        view.acknowledgeNextSuspension()
        let replacementAttempt = UUID()
        owner.beginLoading(url: url, referer: "", attemptID: replacementAttempt)
        XCTAssertEqual(view.suspensions, [true, false])
        XCTAssertTrue(owner.acceptCommittedDocument(url))
        owner.handlePlaybackMessage(["type": "playback_started", "documentID": "replacement-owner",
                                     "attemptID": replacementAttempt.uuidString])
        owner.handlePlaybackMessage(["type": "transport_state", "reason": "paused",
                                     "documentID": "replacement-owner", "attemptID": replacementAttempt.uuidString])
        XCTAssertEqual(states, [.paused], "Old release bookkeeping cannot contain a replacement owner's Pause")
        view.acknowledgeNextSuspension()
        XCTAssertEqual(states, [.paused])
    }

    private func makeOwner(_ acknowledgement: @escaping (UUID, Bool) -> Void) throws
        -> (LiveWebEmbedPlayerView.Coordinator, NativeTransferAcknowledgingWebView, URL) {
        let url = try XCTUnwrap(URL(string: "https://player.example.test/embed"))
        let view = NativeTransferAcknowledgingWebView(frame: .zero)
        view.documentURL = url
        let owner = LiveWebEmbedPlayerView.Coordinator(onNativeTransferSuspensionChanged: acknowledgement,
            configureAudioSession: { .completed([]) })
        owner.webView = view
        let attempt = UUID()
        owner.beginLoading(url: url, referer: "", attemptID: attempt)
        XCTAssertTrue(owner.acceptCommittedDocument(url))
        owner.handlePlaybackMessage(["type": "playback_started", "documentID": "transfer-owner", "attemptID": attempt.uuidString])
        return (owner, view, url)
    }
}

@MainActor
private final class NativeTransferAcknowledgingWebView: WKWebView {
    var documentURL: URL?
    override var url: URL? { documentURL }
    private(set) var suspensions: [Bool] = []
    private(set) var scripts: [String] = []
    private(set) var pauseCount = 0
    private var suspensionCompletions: [@MainActor () -> Void] = []
    private var pauseCompletions: [@MainActor () -> Void] = []
    private var completesImmediately = false

    override func evaluateJavaScript(_ javaScriptString: String,
        completionHandler: (@MainActor (Any?, (any Error)?) -> Void)? = nil) {
        scripts.append(javaScriptString)
        completionHandler?(nil, nil)
    }

    override func setAllMediaPlaybackSuspended(_ suspended: Bool,
        completionHandler: (@MainActor () -> Void)?) {
        suspensions.append(suspended)
        guard let completionHandler else { return }
        if completesImmediately { completionHandler() }
        else { suspensionCompletions.append(completionHandler) }
    }

    override func pauseAllMediaPlayback(completionHandler: (@MainActor () -> Void)?) {
        pauseCount += 1
        guard let completionHandler else { return }
        if completesImmediately { completionHandler() }
        else { pauseCompletions.append(completionHandler) }
    }

    override func closeAllMediaPresentations(completionHandler: (@MainActor () -> Void)?) { completionHandler?() }
    override func stopLoading() {}

    func acknowledgeNextSuspension() {
        guard !suspensionCompletions.isEmpty else { XCTFail("Missing public suspension acknowledgement"); return }
        suspensionCompletions.removeFirst()()
    }

    func acknowledgeNextPause() {
        guard !pauseCompletions.isEmpty else { XCTFail("Missing explicit-Pause acknowledgement"); return }
        pauseCompletions.removeFirst()()
    }

    func finishAll() {
        completesImmediately = true
        let pauses = pauseCompletions, suspensions = suspensionCompletions
        pauseCompletions = []; suspensionCompletions = []
        pauses.forEach { $0() }; suspensions.forEach { $0() }
    }
}

@MainActor
final class WebAudioRevocationBridgeTests: XCTestCase {
    func testConnectingOwnerRetainsDesiredRevocationUntilItsExactDecodedStart() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, _, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.hasReportedPlayback = false
        owner.playbackDocumentID = nil
        let request = UUID(), scriptsBefore = view.scripts.count
        owner.requestWebAudioRevocation(request)
        owner.requestWebAudioRevocation(request)
        XCTAssertEqual(view.scripts.count, scriptsBefore)
        owner.handlePlaybackMessage(["type":"playback_started", "documentID":"audio-owner", "attemptID":attempt.uuidString])
        XCTAssertEqual(view.scripts.count, scriptsBefore + 1, "Decoded ownership must dispatch the still-current desired request")
        owner.requestWebAudioRevocation(request)
        XCTAssertEqual(view.scripts.count, scriptsBefore + 1)
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertEqual(acknowledgements, [request])
    }

    func testConnectingRevocationKeepsOriginalDeadlineAndCannotBindToReplacementAttempt() throws {
        var now: TimeInterval = 100
        var acknowledgements: [UUID] = []
        let timing = FottyAsyncTiming(monotonicNow: { now }, sleep: { _ in })
        let (owner, view, url, attempt) = try makeAudioOwner(timing: timing) { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.hasReportedPlayback = false
        owner.playbackDocumentID = nil
        let request = UUID(), scriptsBefore = view.scripts.count
        owner.requestWebAudioRevocation(request)
        now += 2.01
        owner.handlePlaybackMessage(["type":"playback_started", "documentID":"audio-owner", "attemptID":attempt.uuidString])
        owner.requestWebAudioRevocation(request)
        XCTAssertEqual(view.scripts.count, scriptsBefore, "A decoded start cannot extend the original mute budget")
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertTrue(acknowledgements.isEmpty)
        let replacementAttempt = UUID()
        owner.beginLoading(url: url, referer: "", attemptID: replacementAttempt)
        XCTAssertTrue(owner.acceptCommittedDocument(url))
        owner.handlePlaybackMessage(["type":"playback_started", "documentID":"audio-owner", "attemptID":replacementAttempt.uuidString])
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertEqual(view.scripts.count, scriptsBefore)
        XCTAssertTrue(acknowledgements.isEmpty)
    }

    func testMainScriptCompletionCannotAcknowledgeTheDecodedOwnerAndExactReceiptIsOneShot() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, _, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let request = UUID()
        owner.requestWebAudioRevocation(request)
        owner.requestWebAudioRevocation(request)
        XCTAssertEqual(view.scripts.filter { $0.contains("__fottyRevokeAudio") }.count, 1)
        XCTAssertTrue(acknowledgements.isEmpty, "Main evaluateJavaScript completion does not acknowledge a child")
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertEqual(acknowledgements, [request])
        XCTAssertEqual(view.pauseCount, 0)
        XCTAssertTrue(view.suspensions.isEmpty)
        XCTAssertTrue(view.scripts.allSatisfy { !$0.contains(".play(") && !$0.contains(".pause(") })
    }

    func testReleasedDocumentCannotRebindTheSameDesiredIDToItsReplacementOwner() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, _, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let request = UUID()
        owner.requestWebAudioRevocation(request)
        let scriptsBefore = view.scripts.count
        owner.handlePlaybackMessage(["type":"playback_released", "documentID":"audio-owner", "attemptID":attempt.uuidString])
        owner.handlePlaybackMessage(["type":"playback_started", "documentID":"replacement-owner", "attemptID":attempt.uuidString])
        owner.requestWebAudioRevocation(request)
        owner.handlePlaybackMessage(receipt(request, attempt: attempt, document: "replacement-owner"))
        XCTAssertEqual(view.scripts.count, scriptsBefore)
        XCTAssertTrue(acknowledgements.isEmpty)
    }

    func testWrongRequestAttemptOrOwnerCannotAcknowledgeMute() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, _, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let request = UUID()
        owner.requestWebAudioRevocation(request)
        owner.handlePlaybackMessage(receipt(UUID(), attempt: attempt))
        owner.handlePlaybackMessage(receipt(request, attempt: UUID()))
        owner.handlePlaybackMessage(receipt(request, attempt: attempt, document: "other-owner"))
        XCTAssertTrue(acknowledgements.isEmpty)
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertEqual(acknowledgements, [request])
    }

    func testRevokedOrReplacedRequestCannotAcknowledgeANewerTransfer() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, _, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let old = UUID(), current = UUID()
        owner.requestWebAudioRevocation(old)
        owner.requestWebAudioRevocation(nil)
        owner.handlePlaybackMessage(receipt(old, attempt: attempt))
        owner.requestWebAudioRevocation(current)
        owner.handlePlaybackMessage(receipt(old, attempt: attempt))
        XCTAssertTrue(acknowledgements.isEmpty)
        owner.handlePlaybackMessage(receipt(current, attempt: attempt))
        XCTAssertEqual(acknowledgements, [current])
    }

    func testDocumentReplacementAndTeardownInvalidatePendingAudioReceipt() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, url, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { view.finishAll() }
        let request = UUID()
        owner.requestWebAudioRevocation(request)
        owner.beginLoading(url: url, referer: "", attemptID: attempt)
        XCTAssertTrue(owner.acceptCommittedDocument(url))
        owner.handlePlaybackMessage(["type":"playback_started", "documentID":"audio-owner", "attemptID":attempt.uuidString])
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertTrue(acknowledgements.isEmpty, "A reused attempt/document string still has a different loading generation")
        let next = UUID()
        owner.requestWebAudioRevocation(next)
        LiveWebEmbedPlayerView.dismantleUIView(view, coordinator: owner)
        owner.handlePlaybackMessage(receipt(next, attempt: attempt))
        XCTAssertTrue(acknowledgements.isEmpty)
    }

    func testExpiredAudioReceiptAndMissingDecodedOwnerFailClosed() throws {
        var now: TimeInterval = 100
        var acknowledgements: [UUID] = []
        let timing = FottyAsyncTiming(monotonicNow: { now }, sleep: { _ in })
        let (owner, view, _, attempt) = try makeAudioOwner(timing: timing) { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        let request = UUID()
        owner.requestWebAudioRevocation(request)
        now += 2.01
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertTrue(acknowledgements.isEmpty)
        owner.hasReportedPlayback = false
        let scriptsBefore = view.scripts.count
        let missingOwner = UUID()
        owner.requestWebAudioRevocation(missingOwner)
        owner.handlePlaybackMessage(receipt(missingOwner, attempt: attempt))
        XCTAssertEqual(view.scripts.count, scriptsBefore)
        XCTAssertTrue(acknowledgements.isEmpty)
    }

    func testOrdinaryProviderAudioCannotBeReclaimedByARevocationProperty() throws {
        var acknowledgements: [UUID] = []
        let (owner, view, _, attempt) = try makeAudioOwner { acknowledgements.append($0) }
        defer { owner.invalidateLoading(); view.finishAll() }
        owner.providerControlsAudio = true
        let request = UUID(), scriptsBefore = view.scripts.count
        owner.requestWebAudioRevocation(request)
        owner.handlePlaybackMessage(receipt(request, attempt: attempt))
        XCTAssertEqual(view.scripts.count, scriptsBefore)
        XCTAssertTrue(acknowledgements.isEmpty)
    }

    private func receipt(_ request: UUID, attempt: UUID, document: String = "audio-owner") -> [String: Any] {
        ["type":"audio_revocation_ack", "requestID":request.uuidString,
         "attemptID":attempt.uuidString, "documentID":document]
    }

    private func makeAudioOwner(timing: FottyAsyncTiming? = nil,
        acknowledgement: @escaping (UUID) -> Void) throws
        -> (LiveWebEmbedPlayerView.Coordinator, NativeTransferAcknowledgingWebView, URL, UUID) {
        let url = try XCTUnwrap(URL(string: "https://player.example.test/embed"))
        let view = NativeTransferAcknowledgingWebView(frame: .zero)
        view.documentURL = url
        let owner = LiveWebEmbedPlayerView.Coordinator(onWebAudioRevocationAcknowledged: acknowledgement,
            configureAudioSession: { .completed([]) }, timing: timing)
        owner.webView = view
        let attempt = UUID()
        owner.beginLoading(url: url, referer: "", attemptID: attempt)
        XCTAssertTrue(owner.acceptCommittedDocument(url))
        owner.handlePlaybackMessage(["type":"playback_started", "documentID":"audio-owner", "attemptID":attempt.uuidString])
        return (owner, view, url, attempt)
    }
}
