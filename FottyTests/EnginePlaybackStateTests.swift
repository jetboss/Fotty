import XCTest
@testable import Fotty

final class EnginePlaybackStateTests: XCTestCase {
    func testHappyPathTransitions() {
        var state = PlaybackState.idle
        state = state.applying(.beginResolve)!
        XCTAssertEqual(state, .resolving)
        state = state.applying(.beginPrepare)!
        XCTAssertEqual(state, .preparing)
        state = state.applying(.startPlaying)!
        XCTAssertEqual(state, .playing)
        state = state.applying(.stall)!
        XCTAssertEqual(state, .stalled)
        state = state.applying(.beginRecover)!
        XCTAssertEqual(state, .recovering)
        state = state.applying(.recovered)!
        XCTAssertEqual(state, .playing)
    }

    func testStaleTransitionIsRejected() {
        XCTAssertNil(PlaybackState.playing.applying(.beginResolve))
        XCTAssertNil(PlaybackState.idle.applying(.startPlaying))
        XCTAssertNil(PlaybackState.idle.applying(.beginPrepare))
        XCTAssertNil(PlaybackState.resolving.applying(.stall))
        let failed = PlaybackState.failed(reason: .init(category: .decodingFailed, retryable: true))
        XCTAssertNil(failed.applying(.beginPrepare))
    }

    func testFailureIsReachableFromAnyActiveState() {
        let reason = PlaybackState.PlaybackFailure(category: .timeout, retryable: true)
        for state in [PlaybackState.idle, .resolving, .preparing, .playing, .stalled, .recovering] {
            XCTAssertEqual(state.applying(.fail(reason)), .failed(reason: reason))
        }
    }

    func testFailureAndResetRoundTrip() {
        let reason = PlaybackState.PlaybackFailure(category: .manifestUnreachable, retryable: true)
        let failed = PlaybackState.playing.applying(.fail(reason))!
        XCTAssertEqual(failed, .failed(reason: reason))
        XCTAssertEqual(failed.applying(.reset), .idle)
        XCTAssertEqual(failed.applying(.cancel), .idle)
    }

    func testCancelFromAnyStateReturnsToIdle() {
        for state in [PlaybackState.idle, .resolving, .preparing, .playing, .stalled, .recovering] {
            XCTAssertEqual(state.applying(.cancel), .idle)
        }
    }

    func testRecoveryCanStallAgainWithoutLosingPlayingTarget() {
        var state = PlaybackState.playing.applying(.stall)!
        state = state.applying(.beginRecover)!
        XCTAssertEqual(state, .recovering)
        state = state.applying(.stall)!
        XCTAssertEqual(state, .stalled)
        state = state.applying(.beginRecover)!
        state = state.applying(.recovered)!
        XCTAssertEqual(state, .playing)
    }
}
