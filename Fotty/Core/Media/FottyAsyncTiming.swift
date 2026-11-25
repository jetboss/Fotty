import Foundation

/// A small owner-local timing seam, not another scheduler or playback owner.
/// Production keeps its existing delays; tests can advance time without waiting
/// for real timers. Monotonic time is for elapsed intervals, never fixture dates.
@MainActor
struct FottyAsyncTiming {
    let monotonicNow: () -> TimeInterval
    let sleep: (Duration) async throws -> Void

    static var live: Self {
        Self(monotonicNow: { ProcessInfo.processInfo.systemUptime },
             sleep: { try await Task.sleep(for: $0) })
    }

    func wait(for duration: Duration) async throws {
        try Task.checkCancellation()
        try await sleep(duration)
        // An injected/platform wait may ignore cancellation. It still cannot
        // grant a superseded owner permission to publish after returning.
        try Task.checkCancellation()
    }
}
