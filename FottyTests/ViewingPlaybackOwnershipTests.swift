import XCTest
import AVFoundation
import MediaPlayer
@testable import Fotty

@MainActor
final class ViewingPlaybackOwnershipTests: XCTestCase {
    func testRetiredPaneCannotClearOrOverwriteReplacementNowPlaying() {
        let old = makeModel(title: "Old session")
        let replacement = makeModel(title: "Current session")
        defer { old.cleanup(); replacement.cleanup() }

        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: replacement.remoteCommandOwnerID))
        old.updateNowPlayingInfo()
        old.setRemoteCommandOwnership(false)
        old.cleanup()

        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: replacement.remoteCommandOwnerID))
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,
                       "Current session")
        old.setRemoteCommandOwnership(true)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: replacement.remoteCommandOwnerID),
                      "A retired pane cannot reclaim the active remote commands")
    }

    func testSecondaryConstructionAndCleanupDoNotStealPrimaryRemoteCommands() {
        let primary = makeModel(title: "Primary")
        let secondary = makeModel(title: "Secondary", ownsRemoteCommands: false)
        defer { primary.cleanup(); secondary.cleanup() }

        secondary.updateNowPlayingInfo()
        secondary.cleanup()
        XCTAssertFalse(secondary.ownsRemoteCommands)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: primary.remoteCommandOwnerID))
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,
                       "Primary")
    }

    func testExplicitRemoteFocusTransferPreservesBothAttemptsAndItems() {
        let left = makeModel(title: "Left")
        let right = makeModel(title: "Right", ownsRemoteCommands: false)
        let leftItem = AVPlayerItem(asset: AVMutableComposition())
        let rightItem = AVPlayerItem(asset: AVMutableComposition())
        left.player = AVPlayer(playerItem: leftItem)
        right.player = AVPlayer(playerItem: rightItem)
        let leftAttempt = left.loadRequestID, rightAttempt = right.loadRequestID
        defer { left.cleanup(); right.cleanup() }

        for audible in [right, left, right] {
            let silent = audible === left ? right : left
            silent.setRemoteCommandOwnership(false)
            audible.setRemoteCommandOwnership(true)
            XCTAssertTrue(NowPlayingManager.shared.isOwned(by: audible.remoteCommandOwnerID))
            XCTAssertEqual(left.loadRequestID, leftAttempt)
            XCTAssertEqual(right.loadRequestID, rightAttempt)
            XCTAssertTrue(left.player?.currentItem === leftItem)
            XCTAssertTrue(right.player?.currentItem === rightItem)
            XCTAssertEqual(left.player?.rate, 0)
            XCTAssertEqual(right.player?.rate, 0)
        }
    }

    func testAudioPolicyHasOneExplicitOutputAndNeverUnmutesPendingRetirement() {
        for audible in [0, 1] {
            let outputs = [0, 1].map {
                ViewingPlaybackAudioPolicy.isMuted(isEnabled: $0 == audible, diagnosticMute: false)
            }
            XCTAssertEqual(outputs.filter { !$0 }.count, 1)
        }
        XCTAssertTrue(ViewingPlaybackAudioPolicy.isMuted(isEnabled: true, diagnosticMute: true))
        XCTAssertTrue(ViewingPlaybackAudioPolicy.isMuted(isEnabled: true, diagnosticMute: false,
                                                        awaitingWebRetirement: true))
    }

    func testAudioFocusNeverReplacesItemOrResumesPausedTransport() {
        let model = makeModel(ownsRemoteCommands: false)
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .paused(.native), phase: "Paused")
        let attempt = model.loadRequestID
        defer { model.cleanup() }

        for enabled in [false, true, false] {
            model.setViewingAudioEnabled(enabled)
            XCTAssertEqual(model.isViewingAudioEnabled, enabled)
            XCTAssertEqual(model.webMute, AppRuntime.shouldMutePlaybackForTesting || !enabled)
            XCTAssertEqual(model.player?.isMuted, model.webMute)
            XCTAssertEqual(model.player?.volume, model.webMute ? 0 : 1)
            XCTAssertEqual(model.player?.rate, 0)
            XCTAssertEqual(model.playbackState, .paused(.native))
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertTrue(model.player?.currentItem === item)
        }
    }

    func testSilentPanePreferenceAppliesToNewNativePlayer() {
        let model = makeModel(ownsRemoteCommands: false)
        defer { model.cleanup() }
        model.setViewingAudioEnabled(false)
        let replacement = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.player = replacement
        XCTAssertTrue(replacement.isMuted)
        XCTAssertEqual(replacement.volume, 0)
        XCTAssertEqual(replacement.rate, 0)
    }

    func testNonPiPOwnerBackgroundSuspendsNativeItemWithoutRevokingPlayIntent() {
        let model = makeModel(ownsRemoteCommands: false, native: true)
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .playing(.native), phase: "Playing")
        model.isPictureInPictureAvailable = true
        model.setViewingPiPOwnership(false)
        let attempt = model.loadRequestID
        defer { model.cleanup() }

        model.handleScenePhaseChange(.background)
        XCTAssertFalse(model.keepsPlaybackAliveInBackground)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.shouldResumeAfterForeground)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(model.player?.rate, 0)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)

        model.handlePictureInPictureActivityChanged(true, isBackgrounded: true)
        model.handleNativeTimeControlStatusChanged(.playing)
        model.handleNativeTimeControlStatusChanged(.paused)
        model.handlePictureInPictureActivityChanged(false, isBackgrounded: true)
        XCTAssertTrue(model.userWantsPlayback, "Late nonowner PiP callbacks are not a deliberate user pause")
        XCTAssertTrue(model.shouldResumeAfterForeground)
        XCTAssertEqual(model.playbackState, .paused(.native))

        model.handleScenePhaseChange(.active)
        XCTAssertEqual(model.playbackState, .recovering(.native))
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
    }

    func testNonPiPOwnerCannotPublishRequestAndPreservesDeliberatePause() {
        let model = makeModel(ownsRemoteCommands: false, native: true)
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .playing(.native), phase: "Playing")
        model.togglePlayPause()
        model.isPictureInPictureAvailable = true
        model.setViewingPiPOwnership(false)
        let attempt = model.loadRequestID
        defer { model.cleanup() }

        model.togglePictureInPicture()
        XCTAssertNil(model.pictureInPictureRequestID)
        model.handleScenePhaseChange(.background)
        model.handleScenePhaseChange(.active)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.audioPreparationTask)
    }

    func testDefaultPiPOwnerRetainsLegacyBackgroundAllowanceWithoutReplacingItem() {
        let model = makeModel(ownsRemoteCommands: false, native: true)
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .playing(.native), phase: "Playing")
        model.isPictureInPictureAvailable = true
        let attempt = model.loadRequestID
        defer { model.cleanup() }

        model.handleScenePhaseChange(.background)
        XCTAssertTrue(model.allowsViewingPiP)
        XCTAssertTrue(model.keepsPlaybackAliveInBackground)
        XCTAssertEqual(model.playbackState, .playing(.native))
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
    }

    func testRevokedPendingPiPRequestCannotPublishAfterFocusReturns() async throws {
        let delay = ViewingPiPPreparationBarrier()
        let event = AnalyticalDataEngine.EventReference(id: UUID().uuidString, title: "Retained native pane",
            category: "football", date: 0, poster: nil, popular: false, teams: nil)
        let model = LivePlayerViewModel(event: event, providedSessions: [], ownsRemoteCommands: false,
                                       prepareAudioSession: delay.wait)
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .playing(.native), phase: "Playing")
        model.isPictureInPictureAvailable = true
        let attempt = model.loadRequestID
        defer { model.cleanup(); delay.completeAll() }

        model.togglePictureInPicture()
        let oldPreparation = try XCTUnwrap(model.pictureInPicturePreparationTask)
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(2)
        while delay.pendingCount == 0, clock.now < deadline { await Task.yield() }
        XCTAssertEqual(delay.pendingCount, 1, "PiP must reach the controlled platform preparation boundary")

        model.setViewingPiPOwnership(false)
        XCTAssertTrue(oldPreparation.isCancelled)
        model.setViewingPiPOwnership(true)
        delay.completeAll()
        await oldPreparation.value

        XCTAssertNil(model.pictureInPictureRequestID,
                     "Regaining focus cannot revive the request cancelled under its earlier ownership")
        XCTAssertNil(model.pictureInPicturePreparationTask)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))
    }

    func testRepeatedPresentationMountKeepsExactWebAttemptAndMonitor() async throws {
        let model = makeModel(ownsRemoteCommands: false, web: true)
        defer { model.cleanup() }
        model.startPlaybackIfNeeded()
        await model.loadTask?.value
        let attempt = model.loadRequestID
        let source = model.activeSource?.id
        XCTAssertTrue(model.networkPathObserver.isRunning)
        let monitorStarts = model.networkPathObserver.startCount
        model.transition(to: .paused(.webEmbed), phase: "Paused")

        model.startPlaybackIfNeeded()
        XCTAssertTrue(model.didStartPlayback)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.networkPathObserver.startCount, monitorStarts, "A repeated start reuses the running monitor")
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
    }

    func testCleanupRetiresOnceAndFutureMountCannotRestart() async {
        let model = makeModel(ownsRemoteCommands: false, web: true)
        model.startPlaybackIfNeeded()
        await model.loadTask?.value
        let activeAttempt = model.loadRequestID.uuidString
        model.cleanup()
        let retiredAttempt = model.loadRequestID
        let retiredCorrelation = model.playbackCorrelation.sessionID
        model.cleanup()
        model.startPlaybackIfNeeded()
        model.loadCurrentSource(ignoringCircuitBreaker: true)

        XCTAssertTrue(model.isPlaybackSessionRetired)
        XCTAssertEqual(model.loadRequestID, retiredAttempt)
        XCTAssertEqual(model.playbackCorrelation.sessionID, retiredCorrelation)
        XCTAssertEqual(model.playbackState, .idle)
        XCTAssertFalse(model.networkPathObserver.isRunning)
        XCTAssertNil(model.player)
        XCTAssertEqual(FottyQualityStore.shared.records().filter {
            $0.name == "session_closed" && $0.details["attempt_id"] == activeAttempt
        }.count, 1)
    }

    private func makeModel(title: String = "Viewing session", ownsRemoteCommands: Bool = true,
                           web: Bool = false, native: Bool = false) -> LivePlayerViewModel {
        let event = AnalyticalDataEngine.EventReference(id: UUID().uuidString, title: title,
            category: "football", date: 0, poster: nil, popular: false, teams: nil)
        let sessions: [StreamSession] = (web || native) ? [StreamSession(matchID: event.id,
            playableURL: URL(string: web ? "https://example.invalid/embed/game" : "https://example.invalid/game.m3u8")!,
            streamType: web ? .unknown : .hls, providerName: "Score808",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:])] : []
        return LivePlayerViewModel(event: event, providedSessions: sessions,
                                   ownsRemoteCommands: ownsRemoteCommands)
    }
}

@MainActor
private final class ViewingPiPPreparationBarrier {
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
