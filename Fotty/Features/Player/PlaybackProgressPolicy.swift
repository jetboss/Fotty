import Foundation

/// Progress thresholds and decisions for the player's samplers (player shrink
/// slice 3, 9 Nov 2026). Values are unchanged from the inline literals they
/// replace; naming them makes the timing contract reviewable and testable.
///
/// Samplers that use these:
/// - playback watchdog: a sample every `watchdogInterval`;
/// - recoverable-stall validation: `stallSampleCount` samples, one every
///   `stallSampleInterval`;
/// - native resume validation: one check after `resumeValidationDelay`;
/// - network-loss grace before "Waiting For Network": `networkLossGrace`.
enum PlaybackProgressPolicy {
    static let watchdogInterval: Duration = .seconds(2)
    /// Media-clock movement below this counts as no progress for the watchdog.
    static let stagnationEpsilon: Double = 0.05
    /// Consecutive stagnant watchdog samples before stall validation starts.
    static func frozenTickThreshold(single: Bool) -> Int { single ? 2 : 6 }

    static let stallSampleInterval: Duration = .milliseconds(500)
    static func stallSampleCount(single: Bool) -> Int { single ? 12 : 20 }
    /// Advance beyond this during stall validation proves decoded progress.
    static let decodedProgressThreshold: Double = 0.35

    static let resumeValidationDelay: Duration = .seconds(8)
    /// A resumed item that moved less than this has not resumed.
    static let resumeEpsilon: Double = 0.1

    static let networkLossGrace: Duration = .seconds(2)

    static func hasDecodedProgress(from start: Double, to current: Double) -> Bool {
        current > start + decodedProgressThreshold
    }

    static func resumeDidNotAdvance(from start: Double, to current: Double) -> Bool {
        abs(current - start) < resumeEpsilon
    }
}

/// The watchdog's stagnation count. Mirrors the previous inline branches
/// exactly, including the different counting used for waiting (multi-stream)
/// samples and for the single player's Playing clock.
struct PlaybackStagnationCounter: Equatable {
    var ticks = 0
    var lastSecond: Double?

    /// Single player, transport Playing. Returns true when this sample
    /// advanced after a stagnant streak (the caller may re-arm auto-hide).
    @discardableResult
    mutating func observePlaying(_ seconds: Double) -> Bool {
        let wasStagnant = ticks > 0
        if seconds.isFinite, seconds >= 0,
           lastSecond.map({ abs(seconds - $0) >= PlaybackProgressPolicy.stagnationEpsilon }) ?? true {
            ticks = 0
            lastSecond = seconds
            return wasStagnant
        }
        ticks += 1
        return false
    }

    /// Transport waiting to play at the specified rate.
    mutating func observeWaiting(_ seconds: Double) {
        if let lastSecond, abs(seconds - lastSecond) < PlaybackProgressPolicy.stagnationEpsilon {
            ticks += 1
        } else {
            ticks = 1
            lastSecond = seconds
        }
    }

    /// Any other transport state: healthy, restart the streak at this position.
    mutating func reset(at seconds: Double) {
        ticks = 0
        lastSecond = seconds
    }

    func isFrozen(single: Bool) -> Bool { ticks >= PlaybackProgressPolicy.frozenTickThreshold(single: single) }
}
