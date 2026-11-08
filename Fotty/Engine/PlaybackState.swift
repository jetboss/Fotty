import Foundation

/// The new-engine playback state machine.
///
/// This replaces the legacy ad-hoc coordination (dozens of stored properties
/// and several concurrent `Task` fields in `LivePlayerViewModel`) with one
/// explicit, typed transition graph. A state can only move along the arrows in
/// `PlaybackTransition`; anything else is rejected, so a stale callback can no
/// longer mutate a retired attempt.
enum PlaybackState: Equatable, Sendable {
    case idle
    case resolving
    case preparing
    case playing
    case stalled
    case recovering
    case failed(reason: PlaybackFailure)

    struct PlaybackFailure: Equatable, Sendable {
        let category: Category
        let retryable: Bool

        enum Category: Equatable, Sendable {
            case sourceUnavailable
            case manifestUnreachable
            case decodingFailed
            case timeout
            case cancelled
        }
    }
}

/// The legal transitions between states. Anything not listed is invalid, which
/// is the entire point: no implicit or unguarded movement between states.
enum PlaybackTransition: Equatable, Sendable {
    case beginResolve   // idle -> resolving
    case beginPrepare   // resolving -> preparing
    case startPlaying   // preparing -> playing
    case stall          // playing -> stalled
    case beginRecover   // stalled -> recovering
    case recovered      // recovering -> playing
    case fail(PlaybackState.PlaybackFailure) // any -> failed
    case reset          // failed -> idle
    case cancel         // any -> idle
}

extension PlaybackState {
    /// Applies a transition, returning the new state, or `nil` when the
    /// transition is not legal from the current state.
    func applying(_ transition: PlaybackTransition) -> PlaybackState? {
        switch (self, transition) {
        case (.idle, .beginResolve):
            return .resolving
        case (.resolving, .beginPrepare):
            return .preparing
        case (.preparing, .startPlaying):
            return .playing
        case (.playing, .stall):
            return .stalled
        case (.stalled, .beginRecover):
            return .recovering
        case (.recovering, .recovered):
            return .playing
        case (.recovering, .stall):
            return .stalled
        case (_, .fail(let reason)):
            return .failed(reason: reason)
        case (.failed, .reset):
            return .idle
        case (_, .cancel):
            return .idle
        default:
            return nil
        }
    }
}
