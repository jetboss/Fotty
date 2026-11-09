import Foundation

/// Identity of the playback attempt an async continuation was started for
/// (player shrink slice 4, 9 Nov 2026).
///
/// Before this type, the player fenced late async work three different ways
/// (audit §2.3-A): a bare `loadRequestID`, `(sourceID, requestID, intentID)`
/// owner tuples, and per-path inline checks that each compared a different
/// subset. A `PlaybackAttempt` records the load request plus exactly the
/// parts its continuation depends on (its `scope`), and `isCurrent(in:)`
/// compares those parts and nothing else.
///
/// The scopes are deliberately not unified. The active source can change
/// without a new load request (web-to-native handoff, source selection), so a
/// request-only fence is looser than a request-and-source fence. Each
/// conversion keeps the scope its inline check had; tightening one is a
/// behaviour change for a later, separately reviewed slice.
///
/// Native item identity stays with the caller: continuations hold the item
/// strongly and compare it with `===`, which a value type must not retain.
struct PlaybackAttempt: Equatable, Sendable {
    struct Scope: OptionSet, Equatable, Sendable {
        let rawValue: UInt8
        /// The active source must still be the captured one (nil included).
        static let source = Scope(rawValue: 1 << 0)
        /// The scene's playback intent revision must be unchanged.
        static let playbackIntent = Scope(rawValue: 1 << 1)
        /// The audio intent must be unchanged.
        static let audioIntent = Scope(rawValue: 1 << 2)
    }

    /// The player's current identity values, read once per check.
    struct Current: Equatable, Sendable {
        let requestID: UUID
        let sourceID: UUID?
        let playbackIntent: UUID
        let audioIntent: UUID
    }

    let scope: Scope
    let requestID: UUID
    let sourceID: UUID?
    let playbackIntent: UUID?
    let audioIntent: UUID?

    /// Captures the current attempt with the given scope.
    init(capturing current: Current, scope: Scope) {
        self.scope = scope
        requestID = current.requestID
        sourceID = scope.contains(.source) ? current.sourceID : nil
        playbackIntent = scope.contains(.playbackIntent) ? current.playbackIntent : nil
        audioIntent = scope.contains(.audioIntent) ? current.audioIntent : nil
    }

    /// An attempt for a request and source supplied by the caller, for work
    /// that is handed a request ID and source rather than reading the current ones.
    init(requestID: UUID, sourceID: UUID?) {
        scope = .source
        self.requestID = requestID
        self.sourceID = sourceID
        playbackIntent = nil
        audioIntent = nil
    }

    /// An attempt fenced on the load request only.
    init(requestID: UUID) {
        scope = []
        self.requestID = requestID
        sourceID = nil
        playbackIntent = nil
        audioIntent = nil
    }

    func isCurrent(in current: Current) -> Bool {
        guard current.requestID == requestID else { return false }
        if scope.contains(.source), current.sourceID != sourceID { return false }
        if scope.contains(.playbackIntent), current.playbackIntent != playbackIntent { return false }
        if scope.contains(.audioIntent), current.audioIntent != audioIntent { return false }
        return true
    }
}
