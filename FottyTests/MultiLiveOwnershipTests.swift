import XCTest
import AVFoundation
@testable import Fotty

@MainActor
final class MultiLiveOwnershipTests: XCTestCase {
    func testNormalAudioFocusHasExactlyOneUnmutedOutput() {
        for activeSlot in ["left", "right"] {
            let outputs = ["left", "right"].map { slot in
                MultiLiveAudioOutputPolicy.isMuted(
                    isAudioActive: slot == activeSlot, shouldMuteForTesting: false
                )
            }
            XCTAssertEqual(outputs.filter { !$0 }.count, 1)
            XCTAssertFalse(outputs[activeSlot == "left" ? 0 : 1])
        }
    }

    func testDiagnosticMuteWinsForNativeAndWebFocusIncludingFocusChanges() {
        for activeSlot: String? in ["left", "right", nil] {
            for slot in ["left", "right"] {
                XCTAssertTrue(MultiLiveAudioOutputPolicy.isMuted(
                    isAudioActive: slot == activeSlot, shouldMuteForTesting: true
                ), "The shared native/Web output decision must remain muted in diagnostics")
            }
        }
    }

    func testNoActiveAudioSlotKeepsBothNormalOutputsMuted() {
        XCTAssertTrue(MultiLiveAudioOutputPolicy.isMuted(
            isAudioActive: false, shouldMuteForTesting: false
        ))
    }

    func testNativeFocusTransferDoesNotReplaceEitherItemOrStartPausedPlayers() {
        let leftItem = AVPlayerItem(asset: AVMutableComposition())
        let rightItem = AVPlayerItem(asset: AVMutableComposition())
        let left = AVPlayer(playerItem: leftItem)
        let right = AVPlayer(playerItem: rightItem)
        defer {
            left.replaceCurrentItem(with: nil)
            right.replaceCurrentItem(with: nil)
        }
        for activeSlot in ["left", "right", "left"] {
            MultiLiveAudioOutputPolicy.apply(
                to: left, isAudioActive: activeSlot == "left", shouldMuteForTesting: false
            )
            MultiLiveAudioOutputPolicy.apply(
                to: right, isAudioActive: activeSlot == "right", shouldMuteForTesting: false
            )
            XCTAssertEqual(left.isMuted, activeSlot != "left")
            XCTAssertEqual(right.isMuted, activeSlot != "right")
            XCTAssertEqual(left.volume, activeSlot == "left" ? 1 : 0)
            XCTAssertEqual(right.volume, activeSlot == "right" ? 1 : 0)
            XCTAssertTrue(left.currentItem === leftItem)
            XCTAssertTrue(right.currentItem === rightItem)
            XCTAssertEqual(left.rate, 0)
            XCTAssertEqual(right.rate, 0)
        }
    }

    func testNativeDiagnosticFocusCannotEmitAudioOrReplaceItsItem() {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let player = AVPlayer(playerItem: item)
        defer { player.replaceCurrentItem(with: nil) }
        for active in [true, false, true] {
            MultiLiveAudioOutputPolicy.apply(
                to: player, isAudioActive: active, shouldMuteForTesting: true
            )
            XCTAssertTrue(player.isMuted)
            XCTAssertEqual(player.volume, 0)
            XCTAssertTrue(player.currentItem === item)
            XCTAssertEqual(player.rate, 0)
        }
    }

    func testNativeFailureBelongsOnlyToExactCurrentItemSourceAndAttempt() {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let otherItem = AVPlayerItem(asset: AVMutableComposition())
        let source = UUID()
        let attempt = UUID()
        XCTAssertTrue(MultiLiveNativeFailurePolicy.ownsFailure(
            sourceID: source, currentSourceID: source, requestID: attempt,
            currentRequestID: attempt, item: item, currentItem: item
        ))
        XCTAssertFalse(MultiLiveNativeFailurePolicy.ownsFailure(
            sourceID: source, currentSourceID: source, requestID: attempt,
            currentRequestID: attempt, item: item, currentItem: otherItem
        ), "A replaced item cannot fail the new native owner")
        XCTAssertFalse(MultiLiveNativeFailurePolicy.ownsFailure(
            sourceID: source, currentSourceID: source, requestID: attempt,
            currentRequestID: UUID(), item: item, currentItem: item
        ), "A same-source retry invalidates the old failure callback")
        XCTAssertFalse(MultiLiveNativeFailurePolicy.ownsFailure(
            sourceID: source, currentSourceID: UUID(), requestID: attempt,
            currentRequestID: attempt, item: item, currentItem: item
        ), "A sibling/replacement source cannot acquire the failure")
        XCTAssertFalse(MultiLiveNativeFailurePolicy.ownsFailure(
            sourceID: source, currentSourceID: nil, requestID: attempt,
            currentRequestID: attempt, item: item, currentItem: nil
        ), "Teardown revokes native item ownership")
    }

    func testNativeReadinessDeadlineWithoutFailedItemRemainsStartupTimeout() {
        let snapshot = PlayerDiagnosticService().snapshot(error: nil, trigger: .readinessTimeout)
        for status: AVPlayerItem.Status in [.unknown, .readyToPlay] {
            let reason = MultiLiveNativeFailurePolicy.readinessFailureReason(
                status: status, snapshot: snapshot
            )
            XCTAssertEqual(reason, "Native readiness timeout.")
            XCTAssertEqual(LivePlaybackFailureKind.classify(
                reason: reason, countsAsStall: false, isNetworkReachable: true
            ), .startupTimeout, "A stream that never started must not be labeled as having ended")
        }
        XCTAssertEqual(MultiLiveNativeFailurePolicy.readinessFailureReason(
            status: .failed, snapshot: snapshot
        ), snapshot.failureReason, "An actually failed item keeps its diagnostic failure reason")
    }
}
