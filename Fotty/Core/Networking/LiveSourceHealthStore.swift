import Foundation

// MARK: - Live Source Health Store
// Tracks reliability and performance of stream sources to optimize Watch Now selection.

enum LiveSourceHealthStore {
    private struct Snapshot: Codable {
        var successCount: Int = 0
        var failureCount: Int = 0
        var stallCount: Int = 0
        var totalStartupMs: Int = 0
        var startupSamples: Int = 0
        var lastSuccessAt: TimeInterval?
        var consecutiveFailures: Int?
        var lastFailureAt: TimeInterval?
        var lastFailureReason: String?
    }

    private static let storageKey = "fotty.live.sourceHealth.v1"
    private static let contextStorageKey = "fotty.live.lastGoodProvider.v1"
    private static let queue = DispatchQueue(label: "com.fotty.liveSourceHealthStore")
    private static var verifyingSourceKeys = Set<String>()
    static let circuitBreakerFailureThreshold = 2
    static let circuitBreakerDuration: TimeInterval = 15 * 60

    static func isVerifying(_ source: StreamSource) -> Bool {
        queue.sync { verifyingSourceKeys.contains(sourceKey(for: source)) }
    }

    static func startVerifying(_ source: StreamSource) {
        queue.sync { _ = verifyingSourceKeys.insert(sourceKey(for: source)) }
    }

    static func stopVerifying(_ source: StreamSource) {
        queue.sync { _ = verifyingSourceKeys.remove(sourceKey(for: source)) }
    }

    /// Sport (+ coarse league hint) bucket used to remember “last good provider”.
    /// Kept nonisolated so HybridStreamProvider (actor) can call it safely.
    static func contextKey(for event: AnalyticalDataEngine.EventReference) -> String {
        let raw = event.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let sport: String
        switch raw {
        case "": sport = "other"
        case "soccer": sport = "football"
        default: sport = raw
        }

        let haystack = "\(event.id) \(event.title ?? "")".lowercased()
        let league: String
        if haystack.contains("champions league") || haystack.contains("ucl") {
            league = "championsLeague"
        } else if haystack.contains("premier league") {
            league = "premierLeague"
        } else if haystack.contains("la liga") {
            league = "laLiga"
        } else if haystack.contains("serie a") {
            league = "serieA"
        } else if haystack.contains("bundesliga") {
            league = "bundesliga"
        } else if haystack.contains("ligue 1") {
            league = "ligue1"
        } else {
            league = "all"
        }
        return "\(sport)|\(league)"
    }

    /// Best-first ordering for failover and initial Watch Now pick.
    static func ranked(_ sources: [StreamSource], contextKey: String? = nil) -> [StreamSource] {
        guard sources.count > 1 else { return sources }
        return queue.sync {
            let snapshots = loadSnapshots()
            let lastGood = contextKey.flatMap { loadLastGood()[$0] }
            return sources.sorted { lhs, rhs in
                let l = liveScore(
                    for: lhs,
                    snapshot: snapshots[sourceKey(for: lhs)] ?? Snapshot(),
                    lastGoodProvider: lastGood
                )
                let r = liveScore(
                    for: rhs,
                    snapshot: snapshots[sourceKey(for: rhs)] ?? Snapshot(),
                    lastGoodProvider: lastGood
                )
                if abs(l - r) > 0.01 { return l > r }
                // Prefer StreamEx before Score808 when scores tie (alpha put Score808 first).
                let lf = preferredFamilyRank(providerFamily(for: lhs))
                let rf = preferredFamilyRank(providerFamily(for: rhs))
                if lf != rf { return lf < rf }
                return lhs.provider < rhs.provider
            }
        }
    }

    /// Lower = preferred default when measured health scores tie.
    private static func preferredFamilyRank(_ family: String) -> Int {
        switch family {
        case "score808": return 0
        case "delta": return 1
        case "admin": return 2
        case "golf": return 3
        case "echo": return 4
        case "india": return 5
        default: return 50
        }
    }

    /// Automatic attempts skip a provider family briefly after repeated failures.
    /// Manual source selection remains available and can override this circuit.
    static func automaticCandidates(
        in sources: [StreamSource],
        contextKey: String? = nil,
        at date: Date = Date()
    ) -> [StreamSource] {
        let available = queue.sync {
            let snapshots = loadSnapshots()
            return sources.filter { source in
                !isCircuitOpen(
                    snapshots[sourceKey(for: source)] ?? Snapshot(),
                    at: date.timeIntervalSince1970
                )
            }
        }
        return ranked(available, contextKey: contextKey)
    }

    static func isTemporarilyUnavailable(_ source: StreamSource, at date: Date = Date()) -> Bool {
        queue.sync {
            let snapshot = loadSnapshots()[sourceKey(for: source)] ?? Snapshot()
            return isCircuitOpen(snapshot, at: date.timeIntervalSince1970)
        }
    }

    static func cooldownRemaining(for source: StreamSource, at date: Date = Date()) -> TimeInterval? {
        queue.sync {
            let snapshot = loadSnapshots()[sourceKey(for: source)] ?? Snapshot()
            guard isCircuitOpen(snapshot, at: date.timeIntervalSince1970),
                  let lastFailureAt = snapshot.lastFailureAt else { return nil }
            return max(0, circuitBreakerDuration - (date.timeIntervalSince1970 - lastFailureAt))
        }
    }

    static func isProviderFamilyTemporarilyUnavailable(
        _ rawFamily: String,
        host: String = "embed.st",
        at date: Date = Date()
    ) -> Bool {
        let family = rawFamily.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedFamily = family == "hotel" ? "score808" : family
        let key = "web|\(normalizedFamily)|\(host.lowercased())"
        return queue.sync {
            let snapshot = loadSnapshots()[key] ?? Snapshot()
            return isCircuitOpen(snapshot, at: date.timeIntervalSince1970)
        }
    }

    static func hasRecentSuccess(
        forProviderFamily rawFamily: String,
        host: String = "embed.st",
        within interval: TimeInterval = 24 * 60 * 60,
        at date: Date = Date()
    ) -> Bool {
        let family = rawFamily.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedFamily = family == "hotel" ? "score808" : family
        let key = "web|\(normalizedFamily)|\(host.lowercased())"
        return queue.sync {
            guard let lastSuccessAt = loadSnapshots()[key]?.lastSuccessAt else { return false }
            return date.timeIntervalSince1970 - lastSuccessAt <= interval
        }
    }

    static func rankedSessions(_ sessions: [StreamSession], contextKey: String? = nil) -> [StreamSession] {
        guard sessions.count > 1 else { return sessions }
        let sources = sessions.map(\.legacySource)
        let order = ranked(sources, contextKey: contextKey).map(\.id)
        return sessions.sorted { lhs, rhs in
            let li = order.firstIndex(of: lhs.id) ?? Int.max
            let ri = order.firstIndex(of: rhs.id) ?? Int.max
            return li < ri
        }
    }

    /// Finds the best source index based on historical health data.
    static func bestSourceIndex(in sources: [StreamSource], contextKey: String? = nil) -> Int? {
        guard !sources.isEmpty else { return nil }
        let ordered = ranked(sources, contextKey: contextKey)
        guard let bestID = ordered.first?.id else { return 0 }
        return sources.firstIndex(where: { $0.id == bestID }) ?? 0
    }

    static func bestSessionIndex(in sessions: [StreamSession], contextKey: String? = nil) -> Int? {
        guard !sessions.isEmpty else { return nil }
        let ordered = rankedSessions(sessions, contextKey: contextKey)
        guard let bestID = ordered.first?.id else { return 0 }
        return sessions.firstIndex(where: { $0.id == bestID }) ?? 0
    }

    /// Returns a rounded health score (0-100+) for a given source.
    static func score(for source: StreamSource, contextKey: String? = nil) -> Int {
        queue.sync {
            let snapshots = loadSnapshots()
            let snapshot = snapshots[sourceKey(for: source)] ?? Snapshot()
            let lastGood = contextKey.flatMap { loadLastGood()[$0] }
            let baseScore = liveScore(for: source, snapshot: snapshot, lastGoodProvider: lastGood)

            let peerBoost = Double(min((source.activePeers ?? 0) / 10, 50))

            var penalty = 0.0
            if let peers = source.activePeers, peers < 5 {
                penalty = 30.0
            }

            return Int((baseScore + peerBoost - penalty).rounded())
        }
    }

    static func score(for session: StreamSession, contextKey: String? = nil) -> Int {
        score(for: session.legacySource, contextKey: contextKey)
    }

    /// Records a successful connection to a stream source.
    static func recordSuccess(
        for source: StreamSource,
        startupLatencyMs: Int?,
        contextKey: String? = nil
    ) {
        queue.sync {
            var snapshots = loadSnapshots()
            let key = sourceKey(for: source)
            var snapshot = snapshots[key] ?? Snapshot()
            snapshot.successCount += 1
            if let startupLatencyMs, startupLatencyMs > 0 {
                snapshot.totalStartupMs += startupLatencyMs
                snapshot.startupSamples += 1
            }
            snapshot.lastSuccessAt = Date().timeIntervalSince1970
            snapshot.consecutiveFailures = 0
            snapshot.lastFailureAt = nil
            snapshot.lastFailureReason = nil
            snapshots[key] = snapshot
            saveSnapshots(snapshots)

            if let contextKey, !contextKey.isEmpty {
                var lastGood = loadLastGood()
                lastGood[contextKey] = providerFamily(for: source)
                saveLastGood(lastGood)
            }
        }
    }

    static func recordSuccess(
        for session: StreamSession,
        startupLatencyMs: Int?,
        contextKey: String? = nil
    ) {
        recordSuccess(for: session.legacySource, startupLatencyMs: startupLatencyMs, contextKey: contextKey)
    }

    /// Records a playback failure or stall for a stream source.
    static func recordFailure(for source: StreamSource, wasStall: Bool, reason: String? = nil) {
        queue.sync {
            var snapshots = loadSnapshots()
            let key = sourceKey(for: source)
            var snapshot = snapshots[key] ?? Snapshot()
            let now = Date().timeIntervalSince1970
            if let previousFailure = snapshot.lastFailureAt,
               now - previousFailure > circuitBreakerDuration {
                snapshot.consecutiveFailures = 0
            }
            snapshot.failureCount += 1
            if wasStall {
                snapshot.stallCount += 1
            }
            snapshot.consecutiveFailures = (snapshot.consecutiveFailures ?? 0) + 1
            snapshot.lastFailureAt = now
            snapshot.lastFailureReason = reason.map { String($0.prefix(240)) }
            snapshots[key] = snapshot
            saveSnapshots(snapshots)
        }
    }

    static func recordFailure(for session: StreamSession, wasStall: Bool, reason: String? = nil) {
        recordFailure(for: session.legacySource, wasStall: wasStall, reason: reason)
    }

    // MARK: - Internals

    private static func sourceKey(for source: StreamSource) -> String {
        if let p2pKey = p2pSourceKey(for: source.url, providerHint: source.provider) {
            return p2pKey
        }
        let host = source.url.host?.lowercased() ?? "unknown-host"
        return "web|\(providerFamily(for: source))|\(host)"
    }

    private static func sessionKey(for session: StreamSession) -> String {
        sourceKey(for: session.legacySource)
    }

    /// Coarse provider family so “StreamEx #2” and “StreamEx #1” share last-good memory.
    static func providerFamily(for source: StreamSource) -> String {
        let nexus = source.headers["X-Fotty-Nexus-Source"]?.lowercased()
        if let nexus, !nexus.isEmpty {
            return nexus == "hotel" ? "score808" : nexus
        }
        let provider = source.provider.lowercased()
        if provider.contains("streamex") || provider.contains("delta") { return "delta" }
        if provider.contains("vipleague") || provider.contains("echo") { return "echo" }
        if provider.contains("methstreams") || provider.contains("golf") { return "golf" }
        // Nexus `hotel` is the Score808 family (UI label Score808).
        if provider.contains("score808") || provider.contains("808")
            || provider.contains("cricfree") || provider.contains("hotel") {
            return "score808"
        }
        if provider.contains("strikeout") || provider.contains("india") { return "india" }
        return provider.components(separatedBy: " ").first ?? provider
    }

    private static func isCircuitOpen(_ snapshot: Snapshot, at now: TimeInterval) -> Bool {
        guard (snapshot.consecutiveFailures ?? 0) >= circuitBreakerFailureThreshold,
              let lastFailureAt = snapshot.lastFailureAt else { return false }
        return now - lastFailureAt < circuitBreakerDuration
    }

    private static func p2pSourceKey(for url: URL, providerHint: String) -> String? {
        let host = url.host?.lowercased() ?? ""
        let isKnownP2P = host.contains("p2p.pixel-invoice.com")
            || providerHint.lowercased().contains("p2p")
            || url.absoluteString.lowercased().contains("/proxy/acestream/")

        guard isKnownP2P else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let cid = components?.queryItems?.first(where: { item in
            item.name == "infohash" || item.name == "id"
        })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            return "p2p|\(cid.lowercased())"
        }

        return "p2p|\(host)|\(url.path.lowercased())"
    }

    private static func computeScore(for snapshot: Snapshot) -> Double {
        let attempts = snapshot.successCount + snapshot.failureCount
        let reliability = attempts > 0
            ? Double(snapshot.successCount) / Double(attempts)
            : 0.25

        let averageStartupMs = snapshot.startupSamples > 0
            ? Double(snapshot.totalStartupMs) / Double(snapshot.startupSamples)
            : 2500

        let successBoost = log(Double(snapshot.successCount) + 1) * 9
        let failurePenalty = Double(snapshot.failureCount) * 2
        let stallPenalty = Double(snapshot.stallCount) * 6
        let startupPenalty = averageStartupMs / 300

        var recencyBonus = 0.0
        if let lastSuccessAt = snapshot.lastSuccessAt {
            let age = Date().timeIntervalSince1970 - lastSuccessAt
            if age < 6 * 3600 {
                recencyBonus = 8
            } else if age < 24 * 3600 {
                recencyBonus = 4
            } else if age < 3 * 24 * 3600 {
                recencyBonus = 2
            }
        }

        var score = reliability * 100 + successBoost + recencyBonus - failurePenalty - stallPenalty - startupPenalty

        if snapshot.successCount == 0 {
            score -= 22
        }

        let confidence = min(1.0, Double(attempts) / 4.0)
        score = score * confidence + 10.0 * (1.0 - confidence)

        return score
    }

    private static func liveScore(
        for source: StreamSource,
        snapshot: Snapshot,
        lastGoodProvider: String?
    ) -> Double {
        var localScore = computeScore(for: snapshot)

        if isCircuitOpen(snapshot, at: Date().timeIntervalSince1970) {
            localScore -= 1_000
        }

        if let lastGoodProvider, !lastGoodProvider.isEmpty {
            let family = providerFamily(for: source)
            if family == lastGoodProvider || source.provider.lowercased().contains(lastGoodProvider) {
                localScore += 18
            }
        }

        if let brokerScoreText = source.headers["X-Fotty-P2P-Broker-Score"],
           let brokerScore = Double(brokerScoreText) {
            return max(localScore, brokerScore)
        }

        return localScore
    }

    private static func loadSnapshots() -> [String: Snapshot] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Snapshot].self, from: data)) ?? [:]
    }

    private static func saveSnapshots(_ snapshots: [String: Snapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadLastGood() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: contextStorageKey) as? [String: String]) ?? [:]
    }

    private static func saveLastGood(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: contextStorageKey)
    }

    static func resetForTesting() {
        guard AppRuntime.isAutomatedTesting else { return }
        queue.sync {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: contextStorageKey)
            verifyingSourceKeys.removeAll()
        }
    }
}
