import Foundation

/// The new-engine player: a thin coordinator that moves the explicit
/// `PlaybackState` machine while delegating transport work to a
/// `StreamTransport`. Resolution, ranking and `SourceCandidate` → `StreamSession`
/// enrichment happen *before* this engine, so the engine owns no AVPlayer/WebKit/
/// proxy state and no discovery policy. It is `@MainActor`-bound because playback
/// and its transports run on the main actor.
@MainActor
final class PlaybackEngine {
    private let transport: any StreamTransport
    private(set) var state: PlaybackState = .idle
    private var prepared: PreparedPlayback?

    init(transport: any StreamTransport) {
        self.transport = transport
    }

    /// Prepares and starts the selected session. Returns the final state. An
    /// illegal transition leaves the current state unchanged.
    func watch(_ session: StreamSession) async -> PlaybackState {
        guard state.applying(.beginResolve) != nil else { return state }
        state = .resolving

        guard state.applying(.beginPrepare) != nil else { return state }
        state = .preparing

        do {
            let prepared = try await transport.prepare(session)
            guard state.applying(.startPlaying) != nil else { return state }
            self.prepared = prepared
            state = .playing
            await transport.play(prepared)
            return state
        } catch let failure as TransportFailure {
            state = .failed(reason: .init(category: failure.category == .timeout ? .timeout : .decodingFailed,
                                          retryable: failure.retryable))
            return state
        } catch {
            state = .failed(reason: .init(category: .decodingFailed, retryable: true))
            return state
        }
    }

    /// Pauses and returns to idle. No-op from an already-finished state.
    func pause() async {
        guard state.applying(.cancel) != nil else { return }
        await transport.pause()
        prepared = nil
        state = .idle
    }

    /// Stops and releases the delivery. No-op from an already-finished state.
    func stop() async {
        guard state.applying(.cancel) != nil else { return }
        await transport.stop()
        prepared = nil
        state = .idle
    }
}
