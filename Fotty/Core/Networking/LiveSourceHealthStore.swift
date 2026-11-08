import Foundation
import CryptoKit

// MARK: - Live Source Health Store
// Retains successful provider performance to optimize Watch Now selection.
// Content and playback failures belong to the current attempt, not a host.

enum LiveSourceHealthStore {
    enum MatchOutcome: Int { case decoded, sustained, failed, stalled, wrongProgramme }
    enum MatchEvidence: Int {
        case sustained, recentlyPlayed, unknown, recentlyFailed, repeatedlyFailed, wrongProgramme
        var hasPlayed: Bool { self == .sustained || self == .recentlyPlayed }
    }
    private struct MatchDelivery: Hashable {
        let fixture: Data
        let delivery: Data
        init(_ source: StreamSource, fixtureID: String) {
            fixture = digest(["fixture", fixtureID])
            let contract = source.playbackContract ?? .describing(url: source.url, provider: source.provider, headers: source.headers)
            let fields = ["delivery", source.url.absoluteString, contract.endpoint.rawValue, contract.container.rawValue]
                + transportFields(source)
            delivery = digest(fields)
        }
    }
    private static let processKey = SymmetricKey(size: .bits256)
    private static func digest(_ fields: [String]) -> Data {
        // Length framing preserves names/values containing punctuation. The random
        // key prevents correlation across launches and is never serialized.
        var mac = HMAC<SHA256>(key: processKey)
        for field in fields {
            let bytes = Data(field.utf8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { mac.update(data: Data($0)) }
            mac.update(data: bytes)
        }
        return Data(mac.finalize())
    }
    private static func transportFields(_ source: StreamSource) -> [String] {
        [source.cookie == nil ? "no-cookie" : "cookie", source.cookie ?? "",
         source.referer == nil ? "no-referer" : "referer", source.referer ?? ""]
            + source.headers.keys.sorted().flatMap { [$0, source.headers[$0] ?? ""] }
    }
    /// All bound adapters preserve the exact local row ID only after an admitted
    /// same-choice renewal. FS/SV additionally publish an unambiguous channel
    /// path and finite lease-only query contract, even when discovery gets a new
    /// row ID. Other adapters do not gain a query-stripping heuristic.
    private static func programmeKeys(for session: StreamSession, at now: Date) -> [Data] {
        guard let binding = session.eventBinding, binding.fixtureID == session.matchID,
              binding.providerCode == StreamEventBinding.providerCode(forSessionProviderName: session.providerName) else { return [] }
        let contract = session.playbackContract
        let base = ["programme", binding.fixtureID, binding.providerCode, binding.resource, binding.resourceType,
                    binding.providerEventID, binding.streamID, binding.manifestRevision, binding.sport,
                    binding.kickoffDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "undated",
                    contract.endpoint.rawValue, contract.container.rawValue, session.qualityLabel ?? ""]
            + transportFields(session.legacySource)
        var keys = [digest(base + ["renewed-row", session.id.uuidString])]
        let url = session.playableURL
        let stableChannel = (binding.providerCode == "flixstreams" && FlixStreamsAddonClient.isAdmittedDelivery(url))
            || (binding.providerCode == "streamvix" && StreamVixSportsAddonClient.isAdmittedDelivery(url, now: now))
        if stableChannel, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            keys.append(digest(base + ["declared-channel", components.scheme ?? "", components.host ?? "",
                                       String(components.port ?? 443), components.percentEncodedPath]))
        }
        return keys
    }
    private struct MatchObservation {
        let watchID: UUID
        let outcome: MatchOutcome
        let at: Date
        let sharedHealthKey: String
        let providerCode: String?
    }
    // Volatile, capped, exact event and executable delivery. An observation
    // never leaves this process or affects a neighbour sharing its CDN.
    private static var matchObservations: [MatchDelivery: [MatchObservation]] = [:]
    private static var wrongProgrammes: [Data: Date] = [:]
    private static let matchObservationLifetime: TimeInterval = 6 * 60 * 60
    static func recordMatchOutcome(_ outcome: MatchOutcome, for source: StreamSource, fixtureID: String,
                                   watchID: UUID, at now: Date = Date(), session: StreamSession? = nil) {
        guard AppRuntime.privateOutageFixture == nil else { return }
        queue.sync {
            let key = MatchDelivery(source, fixtureID: fixtureID)
            if outcome == .wrongProgramme, let session, session.matchID == fixtureID, session.id == source.id {
                for logical in programmeKeys(for: session, at: now) { wrongProgrammes[logical] = now }
                wrongProgrammes = wrongProgrammes.filter { (0...matchObservationLifetime).contains(now.timeIntervalSince($0.value)) }
                while wrongProgrammes.count > 256, let oldest = wrongProgrammes.min(by: { $0.value < $1.value })?.key {
                    wrongProgrammes.removeValue(forKey: oldest)
                }
            }
            var recent = matchObservations[key, default: []].filter { (0...matchObservationLifetime).contains(now.timeIntervalSince($0.at)) }
            let previous = recent.first { $0.watchID == watchID }
            // A later decoded callback from the same tap does not erase an
            // interruption or the viewer's explicit wrong-programme observation.
            guard (previous?.outcome.rawValue ?? -1) <= outcome.rawValue else { return }
            recent.removeAll { $0.watchID == watchID }
            recent.append(.init(watchID: watchID, outcome: outcome, at: now, sharedHealthKey: singleStreamEvidenceKey(for: source),
                                providerCode: StreamEventBinding.providerCode(forSessionProviderName: source.provider)))
            matchObservations[key] = Array(recent.suffix(8))
            if matchObservations.count > 128,
               let oldest = matchObservations.min(by: { ($0.value.last?.at ?? .distantPast) < ($1.value.last?.at ?? .distantPast) })?.key {
                matchObservations.removeValue(forKey: oldest)
            }
        }
    }
    private static func evidence(_ key: MatchDelivery, at now: Date, programme: [Data] = []) -> MatchEvidence {
        if programme.contains(where: { wrongProgrammes[$0].map { (0...matchObservationLifetime).contains(now.timeIntervalSince($0)) } ?? false }) {
            return .wrongProgramme
        }
        let recent = matchObservations[key, default: []].filter { (0...matchObservationLifetime).contains(now.timeIntervalSince($0.at)) }
        if recent.contains(where: { $0.outcome == .wrongProgramme }) { return .wrongProgramme }
        guard let last = recent.last else { return .unknown }
        let bad = recent.suffix(3).filter { $0.outcome == .failed || $0.outcome == .stalled }.count
        if bad >= 2 { return .repeatedlyFailed }
        if last.outcome == .sustained { return .sustained }
        return last.outcome == .decoded ? .recentlyPlayed : .recentlyFailed
    }
    static func matchEvidence(for source: StreamSource, fixtureID: String, at now: Date = Date()) -> MatchEvidence {
        queue.sync { evidence(MatchDelivery(source, fixtureID: fixtureID), at: now) }
    }
    static func matchEvidence(for session: StreamSession, at now: Date = Date()) -> MatchEvidence {
        queue.sync { evidence(MatchDelivery(session.legacySource, fixtureID: session.matchID),
            at: now, programme: programmeKeys(for: session, at: now)) }
    }
    static func sustainedMatchProviders(for fixtureID: String, at now: Date = Date()) -> Set<String> {
        let fixture = digest(["fixture", fixtureID])
        return queue.sync {
            Set(matchObservations.compactMap { key, samples in
                guard key.fixture == fixture, evidence(key, at: now) == .sustained else { return nil }
                return samples.last?.providerCode
            })
        }
    }
    private static func unreliableSharedHistory(in fixtureID: String, at now: Date) -> Set<String> {
        var keys = Set<String>()
        let fixture = digest(["fixture", fixtureID])
        for (key, samples) in matchObservations where key.fixture == fixture {
            if evidence(key, at: now).rawValue >= MatchEvidence.recentlyFailed.rawValue, let sample = samples.last {
                keys.insert(sample.sharedHealthKey)
            }
        }
        return keys
    }
    static func positiveRecoveryHistory(for source: StreamSource, fixtureID: String, at now: Date = Date()) -> Bool {
        queue.sync {
            let status = evidence(MatchDelivery(source, fixtureID: fixtureID), at: now)
            if status != .unknown { return status.hasPlayed }
            let key = singleStreamEvidenceKey(for: source)
            return !unreliableSharedHistory(in: fixtureID, at: now).contains(key)
                && singleStreamEvidence(snapshot: loadSnapshots()[key], at: now).tier < 2
        }
    }
    private struct RecentStartupSample: Codable {
        let recordedAt: TimeInterval
        let latencyMs: Int
    }

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
        // Optional for backwards-compatible v1 decoding. These are positive
        // decoded-start observations, not attempts or an uptime/success rate.
        var recentStartupSamples: [RecentStartupSample]?
    }

    private static let storageKey = "fotty.live.sourceHealth.v1"
    private static let contextStorageKey = "fotty.live.lastGoodProvider.v1"
    private static let queue = DispatchQueue(label: "com.fotty.liveSourceHealthStore")
    private static var verifyingSourceKeys = Set<String>()
    /// One queue-owned payload, not a process-lifetime freshness flag. Reading
    /// current bytes first also observes direct defaults replacement/removal.
    private struct SnapshotCache {
        let persistedData: Data?
        let snapshots: [String: Snapshot]
    }
    private static var snapshotCache: SnapshotCache?
    private static var snapshotDecodeCount = 0

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
        return queue.sync {
            let snapshots = loadSnapshots()
            guard sources.count > 1 else { return sources }
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

    /// A missing broadcast, HTTP response, startup timeout or stall is not proof
    /// that other fixtures on this family/host are unavailable. Callers exclude
    /// failed source IDs within their current attempt before asking for ranking.
    static func automaticCandidates(
        in sources: [StreamSource],
        contextKey: String? = nil,
        at date: Date = Date()
    ) -> [StreamSource] {
        ranked(sources, contextKey: contextKey)
    }

    static func isTemporarilyUnavailable(_ source: StreamSource, at date: Date = Date()) -> Bool {
        queue.sync {
            _ = loadSnapshots()
            return false
        }
    }

    static func cooldownRemaining(for source: StreamSource, at date: Date = Date()) -> TimeInterval? {
        queue.sync {
            _ = loadSnapshots()
            return nil
        }
    }

    static func isProviderFamilyTemporarilyUnavailable(
        _ rawFamily: String,
        host: String = "embed.st",
        at date: Date = Date()
    ) -> Bool {
        return queue.sync {
            _ = loadSnapshots()
            return false
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

    /// Single-stream ordering uses local language preference, positive continuity
    /// and recent decoded startup evidence. It never filters a candidate or claims
    /// an uptime/success rate; current-attempt exclusion remains the caller's.
    static func rankedSingleStreamSources(
        _ sources: [StreamSource], contextKey: String? = nil, at date: Date = Date()
    ) -> [StreamSource] {
        guard sources.count > 1 else { return sources }
        return queue.sync {
            singleStreamOrder(for: sources, contextKey: contextKey, at: date).map { sources[$0] }
        }
    }

    static func rankedSingleStreamSessions(
        _ sessions: [StreamSession], contextKey: String? = nil, at date: Date = Date(), applyMatchEvidence: Bool = true
    ) -> [StreamSession] {
        guard sessions.count > 1 else { return sessions }
        return queue.sync {
            // A verified alternate delivery of the exact UK Sky station has
            // the station's language too. A CS label alone remains unknown.
            let languages = sessions.map { session -> CommentaryPreference? in
                if let binding = session.eventBinding, binding.providerCode == "communitysports",
                   binding.fixtureID == session.matchID, binding.expiresAt > date,
                   let station = SportsTVStation.station(id: binding.fixtureID), station.provider == "TV11" {
                    return station.language
                }
                return SportsTVStation.station(provider: session.providerName)?.language
            }
            // The reviewed Sky TV route currently advertises HEVC in MPEG-TS,
            // which Apple HLS cannot display. Prefer its verified CS alternate
            // on a cold tie; actual positive startup/continuity can still win.
            let hasSkyAlternate = zip(sessions, languages).contains { session, language in
                language != nil && session.eventBinding?.providerCode == "communitysports"
                    && session.matchID == "sports-channel:sky-sports-football"
            }
            let deliveryRanks = sessions.map { hasSkyAlternate && $0.providerName == "TV11" ? 1 : 0 }
            let matchContext = sessions.allSatisfy { SportsTVStation.station(id: $0.matchID) == nil }
            let matchSelection = applyMatchEvidence && matchContext
            let matchEvidence = matchSelection ? sessions.map { evidence(MatchDelivery($0.legacySource, fixtureID: $0.matchID),
                at: date, programme: programmeKeys(for: $0, at: date)) } : nil
            let sharedEvidenceToIgnore = matchSelection && Set(sessions.map(\.matchID)).count == 1
                ? unreliableSharedHistory(in: sessions[0].matchID, at: date) : []
            return singleStreamOrder(for: sessions.map(\.legacySource), contextKey: contextKey, at: date,
                knownLanguages: languages, coldDeliveryRanks: deliveryRanks,
                evidenceBeforeLanguage: matchContext, matchEvidence: matchEvidence, sharedEvidenceToIgnore: sharedEvidenceToIgnore)
                .map { sessions[$0] }
        }
    }

    /// Positive decoded-start history only. Absence is unknown, never a
    /// provider ban or a claim that another fixture's delivery has failed.
    static func hasFreshSingleStreamSuccess(for source: StreamSource, at date: Date = Date()) -> Bool {
        queue.sync { singleStreamEvidence(snapshot: loadSnapshots()[singleStreamEvidenceKey(for: source)], at: date).tier < 2 }
    }

    private struct SingleStreamEvidence {
        // 0: measured startup; 1: fresh decoded success without latency;
        // 2: no fresh positive observation. Lower is preferred.
        let tier: Int
        let startupBucket: Int
        let confidence: Int
    }

    private static let recentStartupWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let maximumRecentStartupMs = 180_000
    private static let maximumRecentStartupSamples = 12

    /// Called only while the store's queue is owned. Stable indices retain
    /// duplicate IDs and ensure equal candidates do not shuffle on each read.
    private static func singleStreamOrder(
        for sources: [StreamSource], contextKey: String?, at date: Date,
        knownLanguages: [CommentaryPreference?]? = nil, coldDeliveryRanks: [Int]? = nil,
        evidenceBeforeLanguage: Bool = false, matchEvidence: [MatchEvidence]? = nil, sharedEvidenceToIgnore: Set<String> = []
    ) -> [Int] {
        let snapshots = loadSnapshots()
        let lastGood = contextKey.flatMap { loadLastGood()[$0] }
        let evidence = sources.map { source in
            let key = singleStreamEvidenceKey(for: source)
            return singleStreamEvidence(snapshot: sharedEvidenceToIgnore.contains(key) ? nil : snapshots[key], at: date)
        }
        let preference = CommentaryPreference.saved()
        let languageRanks = sources.indices.map {
            preference.preferenceRank(for: knownLanguages?[$0] ?? SportsTVStation.station(provider: sources[$0].provider)?.language)
        }
        let continuity = sources.map { SinglePlaybackContinuityStore.hasRecentHold($0, at: date) }
        return sources.indices.sorted { lhs, rhs in
            if let matchEvidence {
                func reliability(_ index: Int) -> Int {
                    let status = matchEvidence[index]
                    // A current failure always revokes an older successful hold.
                    if status.rawValue >= MatchEvidence.recentlyFailed.rawValue { return status.rawValue }
                    if status == .sustained || continuity[index] { return 0 }
                    return status == .recentlyPlayed ? 1 : 2
                }
                let l = reliability(lhs), r = reliability(rhs)
                if l != r { return l < r }
            }
            if !evidenceBeforeLanguage && languageRanks[lhs] != languageRanks[rhs] { return languageRanks[lhs] < languageRanks[rhs] }
            if matchEvidence == nil && continuity[lhs] != continuity[rhs] { return continuity[lhs] }
            let l = evidence[lhs], r = evidence[rhs]
            if l.tier != r.tier { return l.tier < r.tier }
            // Respect a known language mismatch, but unknown language must not
            // make a fast CS/AS delivery lose to a slower TV label automatically.
            if evidenceBeforeLanguage && languageRanks[lhs] != languageRanks[rhs]
                && max(languageRanks[lhs], languageRanks[rhs]) == 2 { return languageRanks[lhs] < languageRanks[rhs] }
            if l.startupBucket != r.startupBucket { return l.startupBucket < r.startupBucket }
            if evidenceBeforeLanguage && languageRanks[lhs] != languageRanks[rhs] { return languageRanks[lhs] < languageRanks[rhs] }
            // Confidence can break only a roughly 500ms speed tie, and is capped
            // independently of legacy lifetime success counts.
            if l.confidence != r.confidence { return l.confidence > r.confidence }
            let lDirect = isDirectMediaCandidate(sources[lhs])
            let rDirect = isDirectMediaCandidate(sources[rhs])
            if lDirect != rDirect { return lDirect }
            if let coldDeliveryRanks, coldDeliveryRanks[lhs] != coldDeliveryRanks[rhs] {
                return coldDeliveryRanks[lhs] < coldDeliveryRanks[rhs]
            }
            if let lastGood, !evidenceBeforeLanguage || l.tier < 2 {
                let lGood = providerFamily(for: sources[lhs]) == lastGood
                let rGood = providerFamily(for: sources[rhs]) == lastGood
                if lGood != rGood { return lGood }
            }
            return lhs < rhs
        }
    }

    private static func isDirectMediaCandidate(_ source: StreamSource) -> Bool {
        let contract = source.playbackContract ?? .describing(url: source.url, provider: source.provider, headers: source.headers)
        return contract.endpoint == .directMedia
    }

    private static func isFreshPositiveTimestamp(_ timestamp: TimeInterval, at date: Date) -> Bool {
        let now = date.timeIntervalSince1970
        guard now.isFinite, timestamp.isFinite else { return false }
        let age = now - timestamp
        return age >= 0 && age <= recentStartupWindow
    }

    private static func isValidRecentSample(_ sample: RecentStartupSample, at date: Date) -> Bool {
        (1...maximumRecentStartupMs).contains(sample.latencyMs)
            && isFreshPositiveTimestamp(sample.recordedAt, at: date)
    }

    private static func singleStreamEvidence(snapshot: Snapshot?, at date: Date) -> SingleStreamEvidence {
        guard let snapshot else { return .init(tier: 2, startupBucket: 0, confidence: 0) }
        let samples = (snapshot.recentStartupSamples ?? []).suffix(maximumRecentStartupSamples)
            .filter { isValidRecentSample($0, at: date) }.map(\.latencyMs).sorted()
        if !samples.isEmpty {
            let middle = samples.count / 2
            let median = samples.count.isMultiple(of: 2)
                ? (samples[middle - 1] + samples[middle]) / 2 : samples[middle]
            return .init(tier: 0, startupBucket: median / 500, confidence: min(samples.count, 3))
        }
        guard let lastSuccessAt = snapshot.lastSuccessAt, snapshot.successCount > 0,
              isFreshPositiveTimestamp(lastSuccessAt, at: date) else {
            return .init(tier: 2, startupBucket: 0, confidence: 0)
        }
        // A fresh legacy aggregate has no individually dated observations. Warm
        // start with one weak latency observation, never 100-success dominance.
        if snapshot.recentStartupSamples == nil, snapshot.startupSamples > 0, snapshot.totalStartupMs > 0 {
            let average = Double(snapshot.totalStartupMs) / Double(snapshot.startupSamples)
            if average.isFinite, average >= 1, average <= Double(maximumRecentStartupMs) {
                return .init(tier: 0, startupBucket: Int(average) / 500, confidence: 1)
            }
        }
        return .init(tier: 1, startupBucket: 0, confidence: 0)
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
            // Preserve legacy ranking for other playback contexts, while
            // single-stream TV history belongs to a station, not its shared CDN.
            for key in Set([sourceKey(for: source), singleStreamEvidenceKey(for: source)]) {
                var snapshot = snapshots[key] ?? Snapshot()
                snapshot.successCount += 1
                if let startupLatencyMs, startupLatencyMs > 0 {
                    snapshot.totalStartupMs += startupLatencyMs
                    snapshot.startupSamples += 1
                }
                let observedAt = Date()
                snapshot.lastSuccessAt = observedAt.timeIntervalSince1970
                var recent = (snapshot.recentStartupSamples ?? []).filter { isValidRecentSample($0, at: observedAt) }
                if let startupLatencyMs, (1...maximumRecentStartupMs).contains(startupLatencyMs) {
                    recent.append(.init(recordedAt: observedAt.timeIntervalSince1970, latencyMs: startupLatencyMs))
                }
                // An empty new field distinguishes a current no-latency observation
                // from an untouched legacy aggregate. Keep only owned recent facts.
                snapshot.recentStartupSamples = Array(recent.suffix(maximumRecentStartupSamples))
                snapshot.consecutiveFailures = nil
                snapshot.lastFailureAt = nil
                snapshot.lastFailureReason = nil
                snapshots[key] = snapshot
            }
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

    /// Compatibility entry point for attempt-local playback failures. The player
    /// already excludes exhausted source IDs for that attempt. Neither a generic
    /// reason string nor a stall supplies fixture-independent outage evidence,
    /// so these must never create a persisted family/host penalty or circuit.
    static func recordFailure(for source: StreamSource, wasStall: Bool, reason: String? = nil) {
        queue.sync {
            _ = loadSnapshots()
        }
    }

    static func recordFailure(for session: StreamSession, wasStall: Bool, reason: String? = nil) {
        recordFailure(for: session.legacySource, wasStall: wasStall, reason: reason)
    }

    // MARK: - Internals

    private static func sourceKey(for source: StreamSource) -> String {
        let host = source.url.host?.lowercased() ?? "unknown-host"
        return "web|\(providerFamily(for: source))|\(host)"
    }

    private static func singleStreamEvidenceKey(for source: StreamSource) -> String {
        guard let station = SportsTVStation.station(provider: source.provider) else { return sourceKey(for: source) }
        return "single-tv|\(station.provider)|\(source.url.host?.lowercased() ?? "unknown-host")"
    }

    private static func sessionKey(for session: StreamSession) -> String {
        sourceKey(for: session.legacySource)
    }

    /// Coarse provider family so “StreamEx #2” and “StreamEx #1” share last-good memory.
    static func providerFamily(for source: StreamSource) -> String {
        if let family = StreamPluginProviderMatching.opaqueProviderFamily(source.provider) { return family }
        let nexus = source.headers["X-Fotty-Nexus-Source"]?.lowercased()
        if let nexus, !nexus.isEmpty {
            return nexus == "hotel" ? "score808" : nexus
        }
        let provider = source.provider.lowercased()
        let providerRange = NSRange(provider.startIndex..<provider.endIndex, in: provider)
        if let pattern = try? NSRegularExpression(pattern: #"^cs\d+$"#),
           pattern.firstMatch(in: provider, range: providerRange) != nil {
            return StreamPluginProviderMatching.communitySportsProviderCode
        }
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

    private static func computeScore(for snapshot: Snapshot) -> Double {
        let attempts = snapshot.successCount
        let reliability = attempts > 0 ? 1.0 : 0.25

        let averageStartupMs = snapshot.startupSamples > 0
            ? Double(snapshot.totalStartupMs) / Double(snapshot.startupSamples)
            : 2500

        let successBoost = log(Double(snapshot.successCount) + 1) * 9
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

        var score = reliability * 100 + successBoost + recencyBonus - startupPenalty

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

        if let lastGoodProvider, !lastGoodProvider.isEmpty {
            let family = providerFamily(for: source)
            if family == lastGoodProvider || source.provider.lowercased().contains(lastGoodProvider) {
                localScore += 18
            }
        }

        return localScore
    }

    private static func loadSnapshots() -> [String: Snapshot] {
        let persistedData = UserDefaults.standard.data(forKey: storageKey)
        if let cached = snapshotCache, cached.persistedData == persistedData {
            return cached.snapshots
        }
        guard let data = persistedData else {
            snapshotCache = .init(persistedData: nil, snapshots: [:])
            return [:]
        }
        snapshotDecodeCount &+= 1
        guard var snapshots = try? JSONDecoder().decode([String: Snapshot].self, from: data) else {
            // Do not repeatedly decode the same malformed payload or erase it.
            // A later changed payload still gets its own decoding opportunity.
            snapshotCache = .init(persistedData: data, snapshots: [:])
            return [:]
        }
        // v1 stored failures under a family/host key, with no fixture identity or
        // typed transport evidence. Retire only those negative observations;
        // keep measured successes, startup latency and last-good preferences.
        var migrated = false
        for (key, var snapshot) in snapshots {
            guard snapshot.failureCount != 0 || snapshot.stallCount != 0
                || snapshot.consecutiveFailures != nil || snapshot.lastFailureAt != nil
                || snapshot.lastFailureReason != nil else { continue }
            snapshot.failureCount = 0
            snapshot.stallCount = 0
            snapshot.consecutiveFailures = nil
            snapshot.lastFailureAt = nil
            snapshot.lastFailureReason = nil
            snapshots[key] = snapshot
            migrated = true
        }
        snapshotCache = .init(persistedData: data, snapshots: snapshots)
        if migrated { saveSnapshots(snapshots) }
        return snapshots
    }

    private static func saveSnapshots(_ snapshots: [String: Snapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        guard AppRuntime.privateOutageFixture == nil else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        snapshotCache = .init(persistedData: data, snapshots: snapshots)
    }

    private static func loadLastGood() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: contextStorageKey) as? [String: String]) ?? [:]
    }

    private static func saveLastGood(_ map: [String: String]) {
        guard AppRuntime.privateOutageFixture == nil else { return }
        UserDefaults.standard.set(map, forKey: contextStorageKey)
    }

    /// Counts actual JSON decoder invocations, not elapsed-time or UI proof.
    /// Test inspection is serialized with reads and unavailable in normal use.
    static func snapshotDecodeCountForTesting() -> Int? {
        guard AppRuntime.isAutomatedTesting else { return nil }
        return queue.sync { snapshotDecodeCount }
    }

    static func resetForTesting() {
        guard AppRuntime.isAutomatedTesting else { return }
        queue.sync {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: contextStorageKey)
            verifyingSourceKeys.removeAll()
            matchObservations.removeAll()
            wrongProgrammes.removeAll()
            snapshotCache = nil
            snapshotDecodeCount = 0
        }
    }
}
