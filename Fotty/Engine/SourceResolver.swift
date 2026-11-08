import Foundation

/// A resolved, ranked stream candidate. `score` is lower-is-better.
struct RankedCandidate: Sendable, Equatable {
    let candidate: SourceCandidate
    let score: Int
}

/// Resolves a match directly against enabled source adapters — no registry gate.
///
/// This is the engine's single "give me sources for this match" entry point. A
/// cache may warm it, but the adapters are always the source of truth; nothing
/// here can suppress a direct lookup because a registry is stale or empty.
actor SourceResolver {
    private let adapters: [any SourceAdapter]

    /// Per-fetch timeouts are owned by each adapter. The resolver only gathers
    /// whatever completes; a later refinement adds a coordinator-level deadline.
    init(adapters: [any SourceAdapter]) {
        self.adapters = adapters
    }

    /// Asks every adapter that supports the match, in parallel. Failures are
    /// isolated so a healthy sibling's results survive. Returns candidates
    /// deduplicated by delivery identity and ranked deterministically.
    func resolve(_ request: MatchRequest, at now: Date = Date()) async -> [RankedCandidate] {
        let relevant = adapters.filter { $0.supports(request) }
        guard !relevant.isEmpty else { return [] }

        let results = await withTaskGroup(of: (String, [SourceCandidate]).self,
                                          returning: [String: [SourceCandidate]].self) { group in
            for adapter in relevant {
                group.addTask {
                    (adapter.code, (try? await adapter.resolve(request, at: now)) ?? [])
                }
            }
            var collected: [String: [SourceCandidate]] = [:]
            for await (code, candidates) in group { collected[code] = candidates }
            return collected
        }

        // Reassemble in adapter declaration order so ranking is deterministic
        // regardless of which adapter's task completed first.
        let ordered = relevant.flatMap { results[$0.code] ?? [] }
        return Self.rank(Self.deduplicated(ordered))
    }

    /// Deduplicates by full delivery identity (URL + required headers), so the
    /// same stream advertised through two adapters collapses to one choice.
    nonisolated static func deduplicated(_ candidates: [SourceCandidate]) -> [SourceCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let headers = candidate.requiredHeaders
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            return seen.insert(candidate.url.absoluteString + "|" + headers).inserted
        }
    }

    /// Deterministic ranking: preserve adapter order, no reordering without
    /// observed reliability evidence. A later step injects reliability/proximity
    /// scoring here.
    nonisolated static func rank(_ candidates: [SourceCandidate]) -> [RankedCandidate] {
        candidates.enumerated().map { RankedCandidate(candidate: $0.element, score: $0.offset) }
    }
}
