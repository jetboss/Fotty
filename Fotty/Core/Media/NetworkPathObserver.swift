import Foundation
import Network

/// One owner for a system network-path monitor. Changes are delivered on the
/// main actor to a handler the owner supplies; the observer never retains its
/// owner, so a player that is dropped without `stop()` is still released.
///
/// Extracted from `LivePlayerViewModel` and `MultiLivePlayerView` (player
/// shrink slice 1, 9 Nov 2026). The previous view-model closure captured the
/// whole player strongly (AUDIT.md §2.1-D).
@MainActor
final class NetworkPathObserver {
    typealias Handler = @MainActor (_ reachable: Bool) -> Void

    // Main-actor use only, plus cancellation in deinit.
    private nonisolated(unsafe) var monitor: NWPathMonitor?
    private let label: String

    init(label: String) { self.label = label }

    var isRunning: Bool { monitor != nil }
    /// How many system monitors this observer has started (diagnostics/tests).
    private(set) var startCount = 0

    /// Starts observing if not already running. The handler should capture its
    /// owner weakly; the observer itself holds only the handler.
    func start(_ handler: @escaping Handler) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        startCount += 1
        monitor.pathUpdateHandler = { path in
            let reachable = path.status == .satisfied
            Task { @MainActor in handler(reachable) }
        }
        monitor.start(queue: DispatchQueue(label: label))
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    deinit { monitor?.cancel() }
}
