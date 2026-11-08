import Foundation

/// The minimal, transport-neutral request shared by the resolver and adapters.
/// It carries only the reviewed match identity; it never carries provider URLs,
/// registry state, or UI authority.
struct MatchRequest: Sendable, Equatable {
    let matchID: String
    let homeTeam: String
    let awayTeam: String
    let category: String
    let kickoffDate: Date?
}

/// The reviewed exact-match receipt that proves a candidate belongs to the
/// requested match. The full fail-closed matcher (exact team/squad/date/
/// competition) is ported into the engine around this type in a later step.
struct MatchReceipt: Sendable, Equatable {
    let fixtureID: String
    let participants: [String]
    let start: Date
}

/// A single playable stream candidate, resolved directly from a source adapter.
/// It carries only transport facts plus the exact-match receipt; there is no
/// registry identity and no gate here — admission and ranking happen once, in
/// the resolver.
struct SourceCandidate: Sendable, Equatable {
    let url: URL
    let requiredHeaders: [String: String]
    let qualityLabel: String?
    let providerCode: String
    let matchReceipt: MatchReceipt
}

/// A single third-party source family. This is the only thing that talks to a
/// provider. The resolver asks every enabled adapter in parallel; nothing else
/// is allowed to fetch stream metadata.
protocol SourceAdapter: Sendable {
    var code: String { get }

    /// Whether this adapter can attempt this exact match (sport/competition
    /// gating only — never a freshness or registry decision).
    func supports(_ request: MatchRequest) -> Bool

    /// Resolves the match directly against the provider, returning admitted
    /// candidates in ranked order, or throwing a typed, retryable failure.
    func resolve(_ request: MatchRequest, at now: Date) async throws -> [SourceCandidate]
}
