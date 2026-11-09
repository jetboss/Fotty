import XCTest
@testable import Fotty

/// Player shrink slice 3: the progress thresholds are a named, pinned contract.
/// Changing one of these values is a deliberate retune, not a refactor.
final class PlaybackProgressPolicyTests: XCTestCase {
    func testTimingContractMatchesThePreviousInlineValues() {
        XCTAssertEqual(PlaybackProgressPolicy.watchdogInterval, .seconds(2))
        XCTAssertEqual(PlaybackProgressPolicy.stagnationEpsilon, 0.05)
        XCTAssertEqual(PlaybackProgressPolicy.frozenTickThreshold(single: true), 2)
        XCTAssertEqual(PlaybackProgressPolicy.frozenTickThreshold(single: false), 6)
        XCTAssertEqual(PlaybackProgressPolicy.stallSampleInterval, .milliseconds(500))
        XCTAssertEqual(PlaybackProgressPolicy.stallSampleCount(single: true), 12)
        XCTAssertEqual(PlaybackProgressPolicy.stallSampleCount(single: false), 20)
        XCTAssertEqual(PlaybackProgressPolicy.decodedProgressThreshold, 0.35)
        XCTAssertEqual(PlaybackProgressPolicy.resumeValidationDelay, .seconds(8))
        XCTAssertEqual(PlaybackProgressPolicy.resumeEpsilon, 0.1)
        XCTAssertEqual(PlaybackProgressPolicy.networkLossGrace, .seconds(2))
    }

    func testDecodedProgressAndResumeBoundaries() {
        XCTAssertFalse(PlaybackProgressPolicy.hasDecodedProgress(from: 10, to: 10.35))
        XCTAssertTrue(PlaybackProgressPolicy.hasDecodedProgress(from: 10, to: 10.36))
        XCTAssertFalse(PlaybackProgressPolicy.hasDecodedProgress(from: 10, to: .nan))
        XCTAssertTrue(PlaybackProgressPolicy.resumeDidNotAdvance(from: 10, to: 10.09))
        // 10.1 - 10 is 0.0999… in binary floating point, so it still counts as not
        // advanced, exactly as the previous inline `abs(now - start) < 0.1` did.
        XCTAssertTrue(PlaybackProgressPolicy.resumeDidNotAdvance(from: 10, to: 10.1))
        XCTAssertFalse(PlaybackProgressPolicy.resumeDidNotAdvance(from: 10, to: 10.11))
        XCTAssertTrue(PlaybackProgressPolicy.resumeDidNotAdvance(from: 10, to: 9.95), "Moving backwards slightly is not a resume")
    }

    func testPlayingClockCountingMatchesTheSinglePlayerWatchdog() {
        var counter = PlaybackStagnationCounter()
        XCTAssertFalse(counter.observePlaying(10), "First sample establishes the position")
        XCTAssertEqual(counter, .init(ticks: 0, lastSecond: 10))
        counter.observePlaying(10.04)
        XCTAssertEqual(counter.ticks, 1, "Under the epsilon is stagnant")
        XCTAssertFalse(counter.isFrozen(single: true))
        counter.observePlaying(10.02)
        XCTAssertTrue(counter.isFrozen(single: true))
        XCTAssertTrue(counter.observePlaying(10.05), "Advancing after a stagnant streak reports recovery")
        XCTAssertEqual(counter, .init(ticks: 0, lastSecond: 10.05))
        for invalid in [Double.nan, -1, .infinity] {
            var copy = counter
            copy.observePlaying(invalid)
            XCTAssertEqual(copy.ticks, 1, "An invalid clock counts as stagnant: \(invalid)")
            XCTAssertEqual(copy.lastSecond, 10.05)
        }
    }

    func testWaitingCountingMatchesTheMultiStreamWatchdog() {
        var counter = PlaybackStagnationCounter()
        counter.observeWaiting(5)
        XCTAssertEqual(counter, .init(ticks: 1, lastSecond: 5), "The first waiting sample starts a streak at one")
        for expected in 2...6 { counter.observeWaiting(5.01); XCTAssertEqual(counter.ticks, expected) }
        XCTAssertTrue(counter.isFrozen(single: false))
        counter.observeWaiting(6)
        XCTAssertEqual(counter, .init(ticks: 1, lastSecond: 6), "Movement restarts the streak at one")
        counter.reset(at: 7)
        XCTAssertEqual(counter, .init(ticks: 0, lastSecond: 7))
    }
}
