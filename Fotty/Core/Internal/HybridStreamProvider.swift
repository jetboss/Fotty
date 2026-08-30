import Foundation
import Observation
import os.log

private let hybridLogger = Logger(subsystem: "com.jelani.Fotty", category: "HybridPlayer")

#if FOTTY_LEGACY_P2P
/// Retained only as an opt-in migration reference. Production builds do not
/// define `FOTTY_LEGACY_P2P` and cannot instantiate this retired resolver.
actor HybridStreamProvider {
    static let shared = HybridStreamProvider()

    enum PlaybackPriority {
        case web    // Priority 1: Direct Web (Echo, Delta, Golf)
        case p2p    // Priority 2: P2P Backup (AceStream/Admin)
    }

    private enum ResolutionBatch {
        case web([StreamSource])
        case p2p([StreamSource])
    }

    private let webTimeout: TimeInterval = 12.0

    /// Resolves the prioritized list of streams (Fast Web + P2P Backup Concurrently).
    func resolvePrioritizedSources(for match: AnalyticalDataEngine.EventReference) async throws -> [StreamSource] {
        hybridLogger.info("Resolving prioritized sources for: \(match.title ?? "Unknown", privacy: .public)")

        // Settings modules are an allowlist over the single Nexus catalog lookup.
        // Older builds resolved each module independently, repeating the same network
        // and WebKit extraction work before querying the catalog again here.
        let pluginWebSources: [StreamSource] = []

        return try await withTaskGroup(of: ResolutionBatch.self) { group in
            // Task 1: Web Scraper (Fast Path)
            group.addTask {
                do {
                    let sources = try await self.withTimeout(seconds: self.webTimeout) {
                        try await self.attemptWebPriority(for: match, pluginSources: pluginWebSources)
                    }
                    return .web(sources)
                } catch {
                    hybridLogger.error("Web priority failed: \(error.localizedDescription, privacy: .public)")
                    let fallbackSources = await AnalyticalDataEngine.fallbackEmbedSources(for: match)
                    return .web(fallbackSources)
                }
            }

            var p2pFallbackSources: [StreamSource] = []
            var webSourcesResult: [StreamSource] = []
            var didFinishWebPath = false

            while let batch = await group.next() {
                switch batch {
                case .web(let webSources):
                    didFinishWebPath = true
                    webSourcesResult = webSources
                    if webSources.isEmpty {
                        if !p2pFallbackSources.isEmpty {
                            group.cancelAll()
                            return LiveSourceHealthStore.ranked(
                                self.deduplicated(p2pFallbackSources),
                                contextKey: LiveSourceHealthStore.contextKey(for: match)
                            )
                        }
                    } else if !p2pFallbackSources.isEmpty {
                        group.cancelAll()
                        return LiveSourceHealthStore.ranked(
                            self.combineWebAndP2PWithPairing(web: webSources, p2p: p2pFallbackSources),
                            contextKey: LiveSourceHealthStore.contextKey(for: match)
                        )
                    }
                    // Web has sources but P2P not finished yet — wait for the P2P batch (do not cancel).
                case .p2p(let p2pSources):
                    p2pFallbackSources = p2pSources
                    if didFinishWebPath {
                        if !webSourcesResult.isEmpty {
                            group.cancelAll()
                            return LiveSourceHealthStore.ranked(
                                self.combineWebAndP2PWithPairing(web: webSourcesResult, p2p: p2pFallbackSources),
                                contextKey: LiveSourceHealthStore.contextKey(for: match)
                            )
                        }
                        if !p2pSources.isEmpty {
                            group.cancelAll()
                            return LiveSourceHealthStore.ranked(
                                self.deduplicated(p2pSources),
                                contextKey: LiveSourceHealthStore.contextKey(for: match)
                            )
                        }
                    }
                }
            }

            if !webSourcesResult.isEmpty {
                let final = self.combineWebAndP2PWithPairing(web: webSourcesResult, p2p: p2pFallbackSources)
                let ranked = LiveSourceHealthStore.ranked(
                    final,
                    contextKey: LiveSourceHealthStore.contextKey(for: match)
                )
                hybridLogger.info("Resolution complete (\(ranked.count) sources). Primary: \(ranked.first?.provider ?? "None", privacy: .public)")
                return ranked
            }
            if !p2pFallbackSources.isEmpty {
                let final = LiveSourceHealthStore.ranked(
                    self.deduplicated(p2pFallbackSources),
                    contextKey: LiveSourceHealthStore.contextKey(for: match)
                )
                hybridLogger.info("Resolution complete (P2P only: \(final.count) sources). Primary: \(final.first?.provider ?? "None", privacy: .public)")
                return final
            }

            hybridLogger.info("Resolution complete. No sources found.")
            return []
        }
        .throwingIfEmpty()
    }

    /// Priority One: Direct Web sources (StreamEx / Score808 modules, then catalog)
    private func attemptWebPriority(
        for match: AnalyticalDataEngine.EventReference,
        pluginSources: [StreamSource] = []
    ) async throws -> [StreamSource] {
        let existingSources = match.sources
        let homeName = await match.homeName
        let awayName = await match.awayName
        let enabledCodes = await StreamPluginRegistry.shared.enabledProviderCodes()
        let allowedCodes = StreamPluginProviderMatching.allowedPlayerProviderCodes(enabledCodes: enabledCodes)

        // Always resolve the Nexus catalog. Relying only on per-plugin fetches can drop
        // entire families (Score808/hotel) when StreamEx wins and Score808 times out.
        let catalog: [StreamSource]
        if existingSources == nil || existingSources?.isEmpty == true {
            hybridLogger.debug("Stub match detected (\(homeName, privacy: .public)), performing deep resolution...")
            catalog = try await AnalyticalDataEngine.findStreams_NexusAImplementation(
                homeTeam: homeName,
                awayTeam: awayName
            )
        } else {
            catalog = try await AnalyticalDataEngine.findStreamsDirect(for: match)
        }

        let webCatalog = catalog.filter { !isP2PSource($0) && !StreamPluginProviderMatching.isP2PLike($0) }
        let fromPlugins = pluginSources.filter { !isP2PSource($0) && !StreamPluginProviderMatching.isP2PLike($0) }

        let fromCatalog = webCatalog.filter { source in
            allowedCodes.contains { code in
                StreamPluginProviderMatching.matches(source, code: code)
            }
        }
        let fromPluginsAllowed = fromPlugins.filter { source in
            allowedCodes.contains { code in
                StreamPluginProviderMatching.matches(source, code: code)
            }
        }

        let sources = deduplicated(fromPluginsAllowed + fromCatalog)
        guard !sources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }

        return sources
    }

    /// Priority Two: P2P Backup (AceStream) — skipped when homelab/module returns nothing
    private func attemptP2PPriority(
        for match: AnalyticalDataEngine.EventReference,
        pluginSources: [StreamSource] = []
    ) async throws -> [StreamSource] {
        var p2pSources = pluginSources.filter { isP2PSource($0) }

        if p2pSources.isEmpty {
            p2pSources = try await fetchPreferredP2PSources(
                homeTeam: match.homeName,
                awayTeam: match.awayName,
                category: match.normalizedCategory
            )
        }

        guard !p2pSources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }

        return p2pSources
    }

    private func isP2PSource(_ source: StreamSource) -> Bool {
        let absolute = source.url.absoluteString.lowercased()
        let provider = source.provider.lowercased()
        let quality = source.quality.lowercased()
        return absolute.contains(":6878")
            || absolute.contains("/proxy/acestream/")
            || provider.contains("p2p")
            || quality.contains("p2p")
    }

    private func deduplicated(_ sources: [StreamSource]) -> [StreamSource] {
        var seenCanonicalURLs = Set<String>()
        return sources.filter { source in
            // For P2P sources, the query parameters (infohash) define the uniqueness.
            // For Web sources, we strip tokens/sessions to prevent duplicates of the same provider.
            let isP2P = isP2PSource(source)
            let canonical: String

            if isP2P {
                // Keep the full URL string for P2P to ensure different CIDs aren't collapsed
                canonical = source.url.absoluteString
            } else {
                // Strip query params for web sources to prevent token-based duplicates
                canonical = "\(source.url.scheme ?? "")://\(source.url.host ?? "")\(source.url.path)"
            }

            return seenCanonicalURLs.insert(canonical).inserted
        }
    }

    /// Prefer Streamex-class web feeds first, then interleave each web row with P2P backups
    /// tagged as paired to the closest anchor (region hint when possible).
    private func combineWebAndP2PWithPairing(web: [StreamSource], p2p: [StreamSource]) -> [StreamSource] {
        let w = deduplicated(web)
        let p = deduplicated(p2p)

        let result: [StreamSource]
        if w.isEmpty || p.isEmpty {
            result = deduplicated(w + p)
        } else {
            result = deduplicated(interleaveWebWithPairedP2P(web: w, p2p: p))
        }

        hybridLogger.debug("Final source list resolved (\(result.count) total):")
        for (index, source) in result.enumerated() {
            hybridLogger.debug("  \(index + 1). \(source.provider, privacy: .public) [\(source.quality, privacy: .public)]")
        }

        return result
    }

    private func interleaveWebWithPairedP2P(web: [StreamSource], p2p: [StreamSource]) -> [StreamSource] {
        let webOrdered = sortHighPriorityFirst(web)
        let p2pSorted = p2p.sorted { p2pFixtureMatchScore($0) > p2pFixtureMatchScore($1) }
        var buckets = Array(repeating: [StreamSource](), count: webOrdered.count)
        for source in p2pSorted {
            let idx = bestWebAnchorIndex(for: source, web: webOrdered)
            buckets[idx].append(tagP2PWithWebAnchor(source, anchor: webOrdered[idx]))
        }
        var out: [StreamSource] = []
        for i in webOrdered.indices {
            out.append(webOrdered[i])
            out.append(contentsOf: buckets[i])
        }
        return out
    }

    private func p2pFixtureMatchScore(_ source: StreamSource) -> Int {
        guard let raw = source.headers["X-Fotty-P2P-Match-Score"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let v = Int(raw) else { return 0 }
        return v
    }

    private func isLikelyHighPriorityFeed(_ source: StreamSource) -> Bool {
        let url = source.url.absoluteString.lowercased()
        if url.contains("streamex") || url.contains("vipleague") || url.contains("methstreams") {
            return true
        }
        let cat = source.headers["X-Fotty-Nexus-Catalog"]?.lowercased() ?? ""
        let provider = source.provider.lowercased()
        return cat.contains("streamex") || cat.contains("nexus") ||
               provider.contains("vipleague") || provider.contains("methstreams") ||
               provider.contains("streamex")
    }

    private func sortHighPriorityFirst(_ web: [StreamSource]) -> [StreamSource] {
        web.sorted { lhs, rhs in
            let l = isLikelyHighPriorityFeed(lhs)
            let r = isLikelyHighPriorityFeed(rhs)
            if l != r { return l && !r }
            return lhs.provider < rhs.provider
        }
    }

    private func p2pLabelForPairing(_ source: StreamSource) -> String {
        let t = source.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        return source.provider
    }

    private func bracketRegionTag(from label: String) -> String? {
        guard let open = label.lastIndex(of: "["),
              let close = label.lastIndex(of: "]"),
              open < close else { return nil }
        let inner = label[label.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if (2 ... 4).contains(inner.count), inner.allSatisfy({ $0.isLetter }) {
            return inner
        }
        return nil
    }

    private func webRegionHint(for source: StreamSource) -> String? {
        if let t = source.title, let r = bracketRegionTag(from: t) { return r }
        if let r = bracketRegionTag(from: source.provider) { return r }
        let host = source.url.host?.lowercased() ?? ""
        if host.hasSuffix(".co.uk") || host.contains(".uk.") { return "UK" }
        if host.hasSuffix(".com.au") { return "AU" }
        if host.hasSuffix(".ie") { return "IE" }
        return nil
    }

    private func bestWebAnchorIndex(for p2p: StreamSource, web: [StreamSource]) -> Int {
        guard let firstIndex = web.indices.first else { return 0 }
        let label = p2pLabelForPairing(p2p)
        if let pr = bracketRegionTag(from: label) {
            if let idx = web.enumerated().first(where: { webRegionHint(for: $0.element) == pr })?.offset {
                return idx
            }
        }
        if let idx = web.firstIndex(where: { isLikelyHighPriorityFeed($0) }) {
            return idx
        }
        return firstIndex
    }

    private func tagP2PWithWebAnchor(_ p2p: StreamSource, anchor: StreamSource) -> StreamSource {
        p2p.mergingHeaders([
            "X-Fotty-Paired-Web-Provider": anchor.provider,
            "X-Fotty-Paired-Web-Host": anchor.url.host ?? "",
            "X-Fotty-Paired-Nexus-Source": anchor.headers["X-Fotty-Nexus-Source"] ?? "",
            "X-Fotty-Paired-Nexus-Stream": anchor.headers["X-Fotty-Nexus-Stream"] ?? ""
        ])
    }

    /// The 'Pre-Warm' Pattern: Silently monitor P2P health while Web is playing.
    /// Reference VLC for iOS: Checks for peer count in the background.
    func prewarmP2P(for match: AnalyticalDataEngine.EventReference) {
        Task.detached(priority: .background) {
            hybridLogger.debug("❄️ Pre-warming P2P swarm for \(match.title ?? "event", privacy: .public)...")
            // Silently check if the match has P2P sources to warm up the swarm.
            _ = try? await self.fetchPreferredP2PSources(
                homeTeam: match.homeName,
                awayTeam: match.awayName,
                category: match.normalizedCategory
            )
            hybridLogger.debug("✅ P2P swarm pre-warmed.")
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ProcessorError.timeout
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    private func fetchPreferredP2PSources(
        homeTeam: String,
        awayTeam: String,
        category: String?
    ) async throws -> [StreamSource] {
        do {
            let exactSources = try await P2PDataService.shared.findStreams(
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                category: category,
                allowSportChannelFallback: false
            )
            if !exactSources.isEmpty {
                return exactSources
            }
        } catch {
            if !shouldAllowSportChannelFallback(for: category) {
                throw error
            }
        }

        guard shouldAllowSportChannelFallback(for: category) else {
            throw ProcessorError.noSourcesFound
        }

        return try await P2PDataService.shared.findStreams(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            category: category,
            allowSportChannelFallback: true
        )
    }
}
#else
/// Production source resolver. Fotty 2.0 supports only enabled StreamEx and
/// Score808 web-module families; retired P2P/Ace paths are not consulted.
actor HybridStreamProvider {
    static let shared = HybridStreamProvider()

    private let webTimeout: TimeInterval = 12

    func resolvePrioritizedSources(for match: AnalyticalDataEngine.EventReference) async throws -> [StreamSource] {
        let resolved: [StreamSource]
        do {
            resolved = try await withTimeout(seconds: webTimeout) {
                try await self.resolveEnabledWebSources(for: match)
            }
        } catch {
            resolved = await filterEnabledWebSources(
                AnalyticalDataEngine.fallbackEmbedSources(for: match)
            )
        }

        let ranked = LiveSourceHealthStore.ranked(
            deduplicated(resolved),
            contextKey: LiveSourceHealthStore.contextKey(for: match)
        )
        return try ranked.throwingIfEmpty()
    }

    private func resolveEnabledWebSources(
        for match: AnalyticalDataEngine.EventReference
    ) async throws -> [StreamSource] {
        let catalog: [StreamSource]
        if match.sources?.isEmpty != false {
            catalog = try await AnalyticalDataEngine.findStreams_NexusAImplementation(
                homeTeam: match.homeName,
                awayTeam: match.awayName
            )
        } else {
            catalog = try await AnalyticalDataEngine.findStreamsDirect(for: match)
        }

        return await filterEnabledWebSources(catalog)
    }

    private func filterEnabledWebSources(_ catalog: [StreamSource]) async -> [StreamSource] {
        let enabledCodes = await StreamPluginRegistry.shared.enabledProviderCodes()
        let allowedCodes = StreamPluginProviderMatching.allowedPlayerProviderCodes(enabledCodes: enabledCodes)
        return catalog.filter { source in
            !StreamPluginProviderMatching.isP2PLike(source)
                && allowedCodes.contains { StreamPluginProviderMatching.matches(source, code: $0) }
        }
    }

    private func deduplicated(_ sources: [StreamSource]) -> [StreamSource] {
        var seen = Set<String>()
        return sources.filter { source in
            let canonical = "\(source.url.scheme ?? "")://\(source.url.host ?? "")\(source.url.path)"
            return seen.insert(canonical).inserted
        }
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ProcessorError.timeout
            }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

private extension Array where Element == StreamSource {
    func throwingIfEmpty() throws -> [StreamSource] {
        guard !isEmpty else {
            throw ProcessorError.noSourcesFound
        }
        return self
    }
}

private func shouldAllowSportChannelFallback(for category: String?) -> Bool {
    let normalized = (category ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    switch normalized {
    case "":
        return false
    case "football", "soccer":
        // Football exact-match CIDs are ideal, but Streamex often has no playable
        // direct stream for big fixtures while the P2P catalog only exposes the
        // carrying channel (Sky/TNT/BT/Champions League/etc.). Let the existing
        // football channel fallback run, then require broker validation before
        // any source reaches AVPlayer.
        return true
    default:
        return true
    }
}

@MainActor
private enum StreamWebExtractor {
    static func extract(
        from embedURL: String,
        referer: String,
        providerName: String,
        timeout: TimeInterval = 8
    ) async throws -> [StreamSource] {
        let renderer = WebViewRenderer()
        return try await renderer.extractSources(
            from: embedURL,
            referer: referer,
            providerName: providerName,
            timeout: timeout
        )
    }
}

actor LiveStreamResolver {
    static let shared = LiveStreamResolver()

    private enum ProviderSlot: String {
        case coreMedia = "CoreMedia"
        case p2p = "P2P"
    }

    private let validationSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private let resolverRetryLimit = 2
    /// How many P2P sessions to validate per match resolve (antenna list). Sport-channel used to stop after 1.
    private let maxP2PSessionsPerResolutionAttempt = 14
    private let maxWebEmbedFallbackSessionsPerResolution = 6
    private let maxNativeWebExtractionAttemptsWhenEmbedFallbackExists = 1
    private let p2pReuseWindowSeconds: TimeInterval = 45
    private let p2pPrewarmCooldownSeconds: TimeInterval = 120
    private var recentP2PPrewarms: [String: Date] = [:]

    private struct ProviderResolutionOutput: Sendable {
        let providerName: String
        let result: Result<[StreamSession], StreamFailure>
        let timeline: [StreamEventRecord]
        let providerAttempts: [StreamProviderAttemptLog]
        let resolvedAt: Date
    }

    func resolvePlayback(
        for request: StreamPlaybackRequest,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)? = nil
    ) async -> StreamResolutionOutcome {
        let attemptID = UUID().uuidString
        guard !Task.isCancelled else {
            return cancelledOutcome(
                attemptID: attemptID,
                request: request,
                timeline: [],
                providerAttempts: [],
                category: .navigationCancelled,
                technicalMessage: "Stream attempt cancelled before resolution began."
            )
        }

        // Hard cap so Watch Now cannot sit on "Looking for a playable stream..." forever.
        let startedAt = Date()
        let outcome = await withTaskGroup(of: StreamResolutionOutcome?.self) { group in
            group.addTask { [self] in
                await performResolution(
                    attemptID: attemptID,
                    request: request,
                    onProgress: onProgress
                )
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                } catch {
                    return nil
                }
                return nil
            }
            var result: StreamResolutionOutcome?
            for await value in group {
                if let value {
                    result = value
                    group.cancelAll()
                    break
                }
                group.cancelAll()
                if Task.isCancelled {
                    result = cancelledOutcome(
                        attemptID: attemptID,
                        request: request,
                        timeline: [],
                        providerAttempts: [],
                        category: .navigationCancelled,
                        technicalMessage: "Stream attempt cancelled while resolving."
                    )
                    break
                }
                let failure = StreamFailure(
                    providerName: ProviderSlot.coreMedia.rawValue,
                    category: .providerTimeout,
                    technicalMessage: "Stream resolution exceeded 20s budget.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: true
                )
                result = .failure(
                    failure,
                    StreamAttemptDiagnostics(
                        attemptID: attemptID,
                        matchID: request.matchID,
                        matchTitle: request.displayTitle,
                        finalState: .failed,
                        createdAt: startedAt,
                        completedAt: Date(),
                        timeline: [],
                        providerAttempts: []
                    )
                )
                break
            }
            return result ?? .failure(
                StreamFailure(
                    providerName: ProviderSlot.coreMedia.rawValue,
                    category: .providerTimeout,
                    technicalMessage: "Stream resolution timed out.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: true
                ),
                StreamAttemptDiagnostics(
                    attemptID: attemptID,
                    matchID: request.matchID,
                    matchTitle: request.displayTitle,
                    finalState: .failed,
                    createdAt: startedAt,
                    completedAt: Date(),
                    timeline: [],
                    providerAttempts: []
                )
            )
        }
        return outcome
    }

    /// Resolution is owned by the caller's structured task. Cancelling that task only
    /// cancels that caller, so another screen resolving the same fixture is unaffected.
    func cancelAttempt(for request: StreamPlaybackRequest) {
        _ = request
    }

    func prewarmLikelyP2P(for requests: [StreamPlaybackRequest], limit: Int = 3) async {
        let prioritized = requests
            .sorted { lhs, rhs in
                let lhsPreferred = lhs.preferredEvent?.popular ?? false
                let rhsPreferred = rhs.preferredEvent?.popular ?? false
                if lhsPreferred != rhsPreferred {
                    return lhsPreferred && !rhsPreferred
                }
                let lhsDistance = abs(lhs.kickoffDate?.timeIntervalSinceNow ?? 86_400)
                let rhsDistance = abs(rhs.kickoffDate?.timeIntervalSinceNow ?? 86_400)
                return lhsDistance < rhsDistance
            }
            .prefix(limit)

        for request in prioritized {
            await prewarmP2PIfNeeded(for: request)
        }
    }

    func validateManualP2PSource(
        _ source: StreamSource,
        matchID: String,
        matchTitle: String,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)? = nil
    ) async -> StreamResolutionOutcome {
        let request = StreamPlaybackRequest(
            matchID: matchID,
            displayTitle: matchTitle,
            homeTeam: matchTitle,
            awayTeam: "",
            category: "football",
            preferredEvent: nil
        )

        let attemptID = UUID().uuidString
        var timeline: [StreamEventRecord] = []
        var providerAttempts: [StreamProviderAttemptLog] = []
        var currentState: StreamLoadState = .warmingUpP2P

        await emitProgress(
            attemptID: attemptID,
            state: .warmingUpP2P,
            userMessage: "The stream is still preparing...",
            technicalMessage: "Validating manual P2P source.",
            providerName: ProviderSlot.p2p.rawValue,
            onProgress: onProgress
        )
        appendEvent(
            to: &timeline,
            name: .streamAttemptCreated,
            request: request,
            attemptID: attemptID,
            currentState: .warmingUpP2P
        )

        let validated = await validateP2PSource(
            source,
            request: request,
            attemptID: attemptID,
            timeline: &timeline,
            providerAttempts: &providerAttempts,
            onProgress: onProgress
        )

        switch validated {
        case .success(let session):
            currentState = .readyToPlay
            appendEvent(
                to: &timeline,
                name: .readyToPlay,
                request: request,
                attemptID: attemptID,
                providerName: ProviderSlot.p2p.rawValue,
                currentState: .readyToPlay
            )
            let diagnostics = makeDiagnostics(
                attemptID: attemptID,
                request: request,
                finalState: currentState,
                timeline: timeline,
                providerAttempts: providerAttempts
            )
            await recordDiagnostics(diagnostics)
            return .success(
                StreamResolutionSuccess(
                    attemptID: attemptID,
                    sessions: [session],
                    diagnostics: diagnostics
                )
            )
        case .failure(let failure):
            currentState = .failed
            appendEvent(
                to: &timeline,
                name: .p2pWarmupFailed,
                request: request,
                attemptID: attemptID,
                providerName: ProviderSlot.p2p.rawValue,
                currentState: .failed,
                failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata
            )
            let diagnostics = makeDiagnostics(
                attemptID: attemptID,
                request: request,
                finalState: currentState,
                timeline: timeline,
                providerAttempts: providerAttempts
            )
            await recordDiagnostics(diagnostics)
            return .failure(failure, diagnostics)
        }
    }

    func catalogEvent(for request: StreamPlaybackRequest) async -> AnalyticalDataEngine.EventReference? {
        try? await resolveCatalogEvent(for: request)
    }

    private func fetchPreferredP2PSources(
        homeTeam: String,
        awayTeam: String,
        category: String?
    ) async throws -> [StreamSource] {
        do {
            let exactSources = try await P2PDataService.shared.findStreams(
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                category: category,
                allowSportChannelFallback: false
            )
            if !exactSources.isEmpty {
                return exactSources
            }
        } catch {
            if !shouldAllowSportChannelFallback(for: category) {
                throw error
            }
        }

        guard shouldAllowSportChannelFallback(for: category) else {
            throw ProcessorError.noSourcesFound
        }

        return try await P2PDataService.shared.findStreams(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            category: category,
            allowSportChannelFallback: true
        )
    }

    private func prewarmP2PIfNeeded(for request: StreamPlaybackRequest) async {
        let key = activeKey(for: request)
        let now = Date()
        if let lastPrewarm = recentP2PPrewarms[key],
           now.timeIntervalSince(lastPrewarm) < p2pPrewarmCooldownSeconds {
            return
        }

        do {
            let sources = try await fetchPreferredP2PSources(
                homeTeam: request.homeTeam,
                awayTeam: request.awayTeam,
                category: request.category
            )
            guard !sources.isEmpty else { return }

            let bestIndex = LiveSourceHealthStore.bestSourceIndex(in: sources) ?? 0
            let source = sources[min(bestIndex, sources.count - 1)]
            await AceSessionEngine.shared.prewarmSession(for: source)
            recentP2PPrewarms[key] = Date()
        } catch {
            // Best effort only: prewarm should never affect foreground playback flow.
        }
    }

    private func performResolution(
        attemptID: String,
        request: StreamPlaybackRequest,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> StreamResolutionOutcome {
        let startedAt = Date()
        var timeline: [StreamEventRecord] = []
        var providerAttempts: [StreamProviderAttemptLog] = []
        var currentState: StreamLoadState = .idle
        var validatedSessions: [StreamSession] = []

        appendEvent(
            to: &timeline,
            name: .userTappedMatch,
            request: request,
            attemptID: attemptID,
            currentState: .idle
        )
        appendEvent(
            to: &timeline,
            name: .streamAttemptCreated,
            request: request,
            attemptID: attemptID,
            currentState: .idle
        )

        await emitProgress(
            attemptID: attemptID,
            state: .resolving,
            userMessage: "Looking for a playable stream...",
            technicalMessage: "Starting controlled stream resolution.",
            providerName: nil,
            onProgress: onProgress
        )
        currentState = .resolving
        appendEvent(
            to: &timeline,
            name: .streamResolutionStarted,
            request: request,
            attemptID: attemptID,
            currentState: currentState
        )

        if Task.isCancelled {
            return cancelledOutcome(
                attemptID: attemptID,
                request: request,
                timeline: timeline,
                providerAttempts: providerAttempts,
                category: .navigationCancelled,
                technicalMessage: "Stream attempt cancelled before provider resolution began."
            )
        }

        // Web-only resolution — P2P / AceStream retired from Watch Now.
        let outcome = await withTaskGroup(of: ProviderResolutionOutput?.self) { group in
            group.addTask {
                await self.runProvider1Track(request: request, attemptID: attemptID, onProgress: onProgress)
            }

            var webOutput: ProviderResolutionOutput?
            for await output in group {
                guard let output = output else { continue }
                webOutput = output
                if case .success(let sessions) = output.result, !sessions.isEmpty {
                    group.cancelAll()
                    return output
                }
            }

            if let web = webOutput, case .success(let sessions) = web.result, !sessions.isEmpty {
                return web
            }
            if let output = webOutput {
                return output
            }

            return ProviderResolutionOutput(
                providerName: "HybridStreamProvider",
                result: .failure(
                    StreamFailure(
                        providerName: ProviderSlot.coreMedia.rawValue,
                        category: .providerReturnedEmpty,
                        technicalMessage: "Web resolution returned no StreamEx/Score808 result.",
                        userMessage: "No stream sources were found.",
                        retryable: true,
                        fallbackAllowed: false
                    )
                ),
                timeline: [],
                providerAttempts: [],
                resolvedAt: Date()
            )
        }

        let finalOutput = outcome

        // Merge the winning track's data into our main resolution record
        timeline.append(contentsOf: finalOutput.timeline)
        providerAttempts.append(contentsOf: finalOutput.providerAttempts)

        switch finalOutput.result {
        case .success(let sessions):
            validatedSessions.append(contentsOf: sessions)
        case .failure(let failure):
            // If the winner was a failure, and we haven't tried the other one yet (due to early failure),
            // the group loop above already handled the fallback logic.
            if validatedSessions.isEmpty {
                let diagnostics = makeDiagnostics(
                    attemptID: attemptID,
                    request: request,
                    finalState: .failed,
                    timeline: timeline,
                    providerAttempts: providerAttempts,
                    startedAt: startedAt
                )
                await recordDiagnostics(diagnostics)
                return .failure(failure, diagnostics)
            }
        }

        let deduplicated = deduplicatedSessions(validatedSessions)
        guard !deduplicated.isEmpty else {
            let failure = StreamFailure(
                providerName: nil,
                category: .noProviderAvailable,
                technicalMessage: "All providers completed without yielding a validated StreamSession.",
                userMessage: "No playable stream is available for this match right now.",
                retryable: true,
                fallbackAllowed: false
            )
            let diagnostics = makeDiagnostics(
                attemptID: attemptID,
                request: request,
                finalState: .failed,
                timeline: timeline,
                providerAttempts: providerAttempts,
                startedAt: startedAt
            )
            await recordDiagnostics(diagnostics)
            return .failure(failure, diagnostics)
        }

        currentState = .readyToPlay
        appendEvent(
            to: &timeline,
            name: .readyToPlay,
            request: request,
            attemptID: attemptID,
            providerName: deduplicated.first?.providerName,
            currentState: currentState,
            redactedMetadata: ["session_count": "\(deduplicated.count)"]
        )
        let diagnostics = makeDiagnostics(
            attemptID: attemptID,
            request: request,
            finalState: currentState,
            timeline: timeline,
            providerAttempts: providerAttempts,
            startedAt: startedAt
        )
        await recordDiagnostics(diagnostics)
        return .success(
            StreamResolutionSuccess(
                attemptID: attemptID,
                sessions: deduplicated,
                diagnostics: diagnostics
            )
        )
    }

    private func runProvider1Track(
        request: StreamPlaybackRequest,
        attemptID: String,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> ProviderResolutionOutput {
        var timeline: [StreamEventRecord] = []
        var providerAttempts: [StreamProviderAttemptLog] = []
        let result = await attemptProvider1(
            request: request,
            attemptID: attemptID,
            timeline: &timeline,
            providerAttempts: &providerAttempts,
            onProgress: onProgress
        )
        return ProviderResolutionOutput(
            providerName: ProviderSlot.coreMedia.rawValue,
            result: result,
            timeline: timeline,
            providerAttempts: providerAttempts,
            resolvedAt: Date()
        )
    }

    private func runProvider2Track(
        request: StreamPlaybackRequest,
        attemptID: String,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> ProviderResolutionOutput {
        var timeline: [StreamEventRecord] = []
        var providerAttempts: [StreamProviderAttemptLog] = []
        let result = await attemptProvider2(
            request: request,
            attemptID: attemptID,
            timeline: &timeline,
            providerAttempts: &providerAttempts,
            onProgress: onProgress
        )
        return ProviderResolutionOutput(
            providerName: ProviderSlot.p2p.rawValue,
            result: result,
            timeline: timeline,
            providerAttempts: providerAttempts,
            resolvedAt: Date()
        )
    }

    private func attemptProvider1(
        request: StreamPlaybackRequest,
        attemptID: String,
        timeline: inout [StreamEventRecord],
        providerAttempts: inout [StreamProviderAttemptLog],
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> Result<[StreamSession], StreamFailure> {
        await emitProgress(
            attemptID: attemptID,
            state: .resolving,
            userMessage: "Looking for a playable stream...",
            technicalMessage: "Trying \(ProviderSlot.coreMedia.rawValue).",
            providerName: ProviderSlot.coreMedia.rawValue,
            onProgress: onProgress
        )
        appendEvent(
            to: &timeline,
            name: .provider1Started,
            request: request,
            attemptID: attemptID,
            providerName: ProviderSlot.coreMedia.rawValue,
            currentState: .resolving
        )

        var lastFailure: StreamFailure?
        for attempt in 1...resolverRetryLimit {
            let startedAt = Date()
            let resolved = await resolveCoreMediaSessionsOnce(
                request: request,
                attemptID: attemptID,
                timeline: &timeline,
                providerAttempts: &providerAttempts,
                onProgress: onProgress
            )

            switch resolved {
            case .success(let sessions):
                return .success(sessions)
            case .failure(let failure):
                lastFailure = failure
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                providerAttempts.append(
                    StreamProviderAttemptLog(
                        providerName: ProviderSlot.coreMedia.rawValue,
                        responseTimeMs: elapsedMs,
                        resolvedStreamType: .unknown,
                        urlShape: failure.redactedMetadata["url_shape"] ?? "none",
                        requiredHeaders: false,
                        validationResult: "failed",
                        manifestResult: failure.redactedMetadata["manifest_result"],
                        segmentResult: failure.redactedMetadata["segment_result"],
                        finalFailureCategory: failure.category
                    )
                )
                guard failure.retryable, attempt < resolverRetryLimit else {
                    return .failure(failure)
                }
            }
        }

        return .failure(
            lastFailure
                ?? StreamFailure(
                    providerName: ProviderSlot.coreMedia.rawValue,
                    category: .providerReturnedEmpty,
                    technicalMessage: "\(ProviderSlot.coreMedia.rawValue) returned no playable sources.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: true
                )
        )
    }

    private func attemptProvider2(
        request: StreamPlaybackRequest,
        attemptID: String,
        timeline: inout [StreamEventRecord],
        providerAttempts: inout [StreamProviderAttemptLog],
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> Result<[StreamSession], StreamFailure> {
        await emitProgress(
            attemptID: attemptID,
            state: .warmingUpP2P,
            userMessage: "The stream is still preparing...",
            technicalMessage: "Trying \(ProviderSlot.p2p.rawValue).",
            providerName: ProviderSlot.p2p.rawValue,
            onProgress: onProgress
        )
        appendEvent(
            to: &timeline,
            name: .provider2Started,
            request: request,
            attemptID: attemptID,
            providerName: ProviderSlot.p2p.rawValue,
            currentState: .warmingUpP2P
        )

        var lastFailure: StreamFailure?
        for attempt in 1...resolverRetryLimit {
            let startedAt = Date()
            let resolved = await resolveP2PSessionsOnce(
                request: request,
                attemptID: attemptID,
                timeline: &timeline,
                providerAttempts: &providerAttempts,
                onProgress: onProgress
            )

            switch resolved {
            case .success(let sessions):
                return .success(sessions)
            case .failure(let failure):
                lastFailure = failure
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                providerAttempts.append(
                    StreamProviderAttemptLog(
                        providerName: ProviderSlot.p2p.rawValue,
                        responseTimeMs: elapsedMs,
                        resolvedStreamType: .p2pProxyHLS,
                        urlShape: failure.redactedMetadata["url_shape"] ?? "none",
                        requiredHeaders: true,
                        validationResult: "failed",
                        manifestResult: failure.redactedMetadata["manifest_result"],
                        segmentResult: failure.redactedMetadata["segment_result"],
                        finalFailureCategory: failure.category
                    )
                )
                guard failure.retryable, attempt < resolverRetryLimit else {
                    return .failure(failure)
                }
            }
        }

        return .failure(
            lastFailure
                ?? StreamFailure(
                    providerName: ProviderSlot.p2p.rawValue,
                    category: .providerReturnedEmpty,
                    technicalMessage: "\(ProviderSlot.p2p.rawValue) returned no playable sources.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: false
                )
        )
    }

    private func resolveCoreMediaSessionsOnce(
        request: StreamPlaybackRequest,
        attemptID: String,
        timeline: inout [StreamEventRecord],
        providerAttempts: inout [StreamProviderAttemptLog],
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> Result<[StreamSession], StreamFailure> {
        guard !Task.isCancelled else {
            return .failure(cancelledFailure(.navigationCancelled, "Cancelled before core media resolution."))
        }

        let catalogEvent: AnalyticalDataEngine.EventReference
        do {
            guard let resolved = try await resolveCatalogEvent(for: request) else {
                let failure = StreamFailure(
                    providerName: ProviderSlot.coreMedia.rawValue,
                    category: .invalidMatchMapping,
                    technicalMessage: "Could not map \(request.displayTitle) to a provider event with source metadata.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: false,
                    fallbackAllowed: true,
                    redactedMetadata: [
                        "match_id": request.matchID,
                        "title": request.displayTitle
                    ]
                )
                appendEvent(
                    to: &timeline,
                    name: .provider1ValidationFailed,
                    request: request,
                    attemptID: attemptID,
                    providerName: ProviderSlot.coreMedia.rawValue,
                    currentState: .failed,
                    failureCategory: failure.category,
                    redactedMetadata: failure.redactedMetadata
                )
                return .failure(failure)
            }
            catalogEvent = resolved
        } catch {
            let failure = failureFromError(
                providerName: ProviderSlot.coreMedia.rawValue,
                fallbackAllowed: true,
                defaultUserMessage: "No playable stream is available for this match right now.",
                error: error,
                defaultCategory: .unknown
            )
            appendEvent(
                to: &timeline,
                name: .provider1ValidationFailed,
                request: request,
                attemptID: attemptID,
                providerName: ProviderSlot.coreMedia.rawValue,
                currentState: .failed,
                failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata
            )
            return .failure(failure)
        }

        guard let rawDescriptors = catalogEvent.sources, !rawDescriptors.isEmpty else {
            let failure = StreamFailure(
                providerName: ProviderSlot.coreMedia.rawValue,
                category: .providerReturnedEmpty,
                technicalMessage: "Mapped provider event did not include any stream sources.",
                userMessage: "No playable stream is available for this match right now.",
                retryable: false,
                fallbackAllowed: true
            )
            appendEvent(
                to: &timeline,
                name: .provider1Resolved,
                request: request,
                attemptID: attemptID,
                providerName: ProviderSlot.coreMedia.rawValue,
                currentState: .resolving,
                redactedMetadata: ["source_count": "0"]
            )
            return .failure(failure)
        }

        // Supported catalog web embeds only. Catalog families remain available
        // for an explicit Watch tap even when their recent health is poor; the
        // player still validates decoded progress and handles bounded failover.
        let enabledCodes = await StreamPluginRegistry.shared.enabledProviderCodes()
        let allowedCodes = StreamPluginProviderMatching.allowedPlayerProviderCodes(enabledCodes: enabledCodes)
        let sourceDescriptors = rawDescriptors
            .filter { descriptor in
                let source = descriptor.source.lowercased()
                return (allowedCodes.contains("streamex") && ["admin", "delta", "echo", "golf", "india"].contains(source))
                    || (allowedCodes.contains("score808") && source == "hotel")
            }
            .sorted { lhs, rhs in
                let order = ["admin", "delta", "echo", "golf", "india", "hotel"]
                let li = order.firstIndex(of: lhs.source.lowercased()) ?? order.count
                let ri = order.firstIndex(of: rhs.source.lowercased()) ?? order.count
                return li < ri
            }

        appendEvent(
            to: &timeline,
            name: .provider1Resolved,
            request: request,
            attemptID: attemptID,
            providerName: ProviderSlot.coreMedia.rawValue,
            currentState: .resolving,
            redactedMetadata: ["source_count": "\(sourceDescriptors.count)"]
        )

        var actualCandidateGroups: [[AnalyticalDataEngine.StreamCandidate]] = []

        for descriptor in sourceDescriptors {
            if Task.isCancelled {
                return .failure(cancelledFailure(.navigationCancelled, "Cancelled during core media candidate scan."))
            }

            let webCandidates = await AnalyticalDataEngine.streamCandidates(
                for: descriptor,
                synthesizeWhenEmpty: false
            )
                .filter { !isP2PCandidate($0) }
            if !webCandidates.isEmpty {
                actualCandidateGroups.append(webCandidates)
            }
        }

        var curatedCandidates = AnalyticalDataEngine.curatedPlaybackCandidates(
            from: actualCandidateGroups,
            limit: 12
        )

        // A canonical URL remains a last-resort path only when the catalog has
        // no variants at all. Never mix invented rows into an event which has
        // real catalog choices, and never fabricate both #1 and #2.
        if curatedCandidates.isEmpty {
            curatedCandidates = sourceDescriptors.compactMap { descriptor in
                guard AnalyticalDataEngine.supportsCanonicalEmbedFallback(
                    sourceCode: descriptor.source
                ) else { return nil }
                guard let embedURL = AnalyticalDataEngine.canonicalEmbedURL(
                    for: descriptor,
                    streamNo: 1
                ) else { return nil }
                return AnalyticalDataEngine.StreamCandidate(
                    sourceCode: descriptor.source,
                    streamNo: 1,
                    language: nil,
                    isHD: true,
                    heatTier: "last_resort",
                    embedURL: embedURL,
                    catalogProvider: "embed.st"
                )
            }
        }

        let webEmbedSessions = await validateWebEmbedFallbackSessions(
            from: curatedCandidates,
            request: request,
            attemptID: attemptID,
            timeline: &timeline,
            providerAttempts: &providerAttempts
        )

        let sessions = LiveSourceHealthStore.rankedSessions(
            deduplicatedSessions(webEmbedSessions).filter { session in
                allowedCodes.contains { code in
                    StreamPluginProviderMatching.matches(session.legacySource, code: code)
                }
            }
        )

        guard !sessions.isEmpty else {
            return .failure(
                StreamFailure(
                    providerName: ProviderSlot.coreMedia.rawValue,
                    category: .providerReturnedEmpty,
                    technicalMessage: "No StreamEx/Score808 web embed sessions for this match.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: false
                )
            )
        }

        appendEvent(
            to: &timeline,
            name: .provider1ValidationSucceeded,
            request: request,
            attemptID: attemptID,
            providerName: ProviderSlot.coreMedia.rawValue,
            currentState: .readyToPlay,
            redactedMetadata: [
                "session_count": "\(sessions.count)",
                "mode": "web_embed_fast"
            ]
        )
        return .success(sessions)
    }

    private func resolveP2PSessionsOnce(
        request: StreamPlaybackRequest,
        attemptID: String,
        timeline: inout [StreamEventRecord],
        providerAttempts: inout [StreamProviderAttemptLog],
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> Result<[StreamSession], StreamFailure> {
        guard !Task.isCancelled else {
            return .failure(cancelledFailure(.navigationCancelled, "Cancelled before P2P resolution."))
        }

        let allowCategoryFallback = shouldAllowSportChannelFallback(for: request.category)

        func loadP2PSources(allowSportChannelFallback: Bool) async -> Result<[StreamSource], StreamFailure> {
            do {
                let sources = try await P2PDataService.shared.findStreams(
                    homeTeam: request.homeTeam,
                    awayTeam: request.awayTeam,
                    category: request.category,
                    allowSportChannelFallback: allowSportChannelFallback
                )
                guard !sources.isEmpty else {
                    return .failure(
                        StreamFailure(
                            providerName: ProviderSlot.p2p.rawValue,
                            category: .providerReturnedEmpty,
                            technicalMessage: allowSportChannelFallback
                                ? "P2P sport-channel fallback returned zero preflighted sources."
                                : "P2P exact-match search returned zero preflighted sources.",
                            userMessage: "No playable stream is available for this match right now.",
                            retryable: true,
                            fallbackAllowed: allowCategoryFallback && !allowSportChannelFallback
                        )
                    )
                }
                return .success(sources)
            } catch {
                return .failure(
                    failureFromError(
                        providerName: ProviderSlot.p2p.rawValue,
                        fallbackAllowed: allowCategoryFallback && !allowSportChannelFallback,
                        defaultUserMessage: "No playable stream is available for this match right now.",
                        error: error,
                        defaultCategory: .providerReturnedEmpty
                    )
                )
            }
        }

        var candidateGroups: [(strategy: String, sources: [StreamSource])] = []
        var initialFailure: StreamFailure?

        switch await loadP2PSources(allowSportChannelFallback: false) {
        case .success(let exactSources):
            candidateGroups.append(("exact-match", exactSources))
        case .failure(let failure):
            initialFailure = failure
        }

        if allowCategoryFallback {
            switch await loadP2PSources(allowSportChannelFallback: true) {
            case .success(let fallbackSources):
                let existingIDs = Set(candidateGroups.flatMap(\.sources).map(\.id))
                let uniqueFallbackSources = fallbackSources.filter { !existingIDs.contains($0.id) }
                if !uniqueFallbackSources.isEmpty {
                    candidateGroups.append(("sport-channel", uniqueFallbackSources))
                }
            case .failure(let failure):
                initialFailure = initialFailure ?? failure
            }
        }

        guard !candidateGroups.isEmpty else {
            if let initialFailure {
                appendEvent(
                    to: &timeline,
                    name: .provider2ValidationFailed,
                    request: request,
                    attemptID: attemptID,
                    providerName: ProviderSlot.p2p.rawValue,
                    currentState: .failed,
                    failureCategory: initialFailure.category,
                    redactedMetadata: initialFailure.redactedMetadata
                )
                return .failure(initialFailure)
            }

            return .failure(
                StreamFailure(
                    providerName: ProviderSlot.p2p.rawValue,
                    category: .providerReturnedEmpty,
                    technicalMessage: "P2P provider returned zero preflighted sources.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: false
                )
            )
        }

        var sessions: [StreamSession] = []
        var lastFailure: StreamFailure?

        for (groupIndex, group) in candidateGroups.enumerated() {
            if groupIndex > 0 {
                appendEvent(
                    to: &timeline,
                    name: .fallbackStarted,
                    request: request,
                    attemptID: attemptID,
                    providerName: ProviderSlot.p2p.rawValue,
                    currentState: .fallingBack,
                    redactedMetadata: ["strategy": group.strategy]
                )
                await emitProgress(
                    attemptID: attemptID,
                    state: .fallingBack,
                    userMessage: "Trying another source...",
                    technicalMessage: "P2P is trying \(group.strategy) channels.",
                    providerName: ProviderSlot.p2p.rawValue,
                    onProgress: onProgress
                )
            }

            appendEvent(
                to: &timeline,
                name: .provider2Resolved,
                request: request,
                attemptID: attemptID,
                providerName: ProviderSlot.p2p.rawValue,
                currentState: .warmingUpP2P,
                redactedMetadata: [
                    "source_count": "\(group.sources.count)",
                    "strategy": group.strategy
                ]
            )

            for source in group.sources {
                if Task.isCancelled {
                    return .failure(cancelledFailure(.navigationCancelled, "Cancelled during P2P validation."))
                }

                let validation = await validateP2PSource(
                    source,
                    request: request,
                    attemptID: attemptID,
                    timeline: &timeline,
                    providerAttempts: &providerAttempts,
                    onProgress: onProgress
                )

                switch validation {
                case .success(let session):
                    sessions.append(session)
                    if groupIndex > 0 {
                        appendEvent(
                            to: &timeline,
                            name: .fallbackSucceeded,
                            request: request,
                            attemptID: attemptID,
                            providerName: ProviderSlot.p2p.rawValue,
                            currentState: .readyToPlay,
                            redactedMetadata: ["strategy": group.strategy]
                        )
                    }
                    if sessions.count >= maxP2PSessionsPerResolutionAttempt {
                        return .success(sessions)
                    }
                case .failure(let failure):
                    lastFailure = failure
                }
            }
        }

        // If at least one source validated, succeed even when we never hit the early return
        // (e.g. exact-match had only one passing warmup — previously this fell through to failure).
        if !sessions.isEmpty {
            return .success(sessions)
        }

        return .failure(
            lastFailure
                ?? initialFailure
                ?? StreamFailure(
                    providerName: ProviderSlot.p2p.rawValue,
                    category: .p2pWarmupFailed,
                    technicalMessage: "P2P provider returned sources, but none survived warmup validation.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: false
                )
        )
    }

    private func validateWebEmbedFallbackSessions(
        from candidates: [AnalyticalDataEngine.StreamCandidate],
        request: StreamPlaybackRequest,
        attemptID: String,
        timeline: inout [StreamEventRecord],
        providerAttempts: inout [StreamProviderAttemptLog]
    ) async -> [StreamSession] {
        var sessions: [StreamSession] = []

        for candidate in candidates {
            guard sessions.count < maxWebEmbedFallbackSessionsPerResolution else { break }
            guard !Task.isCancelled else { break }

            let startedAt = Date()
            appendEvent(
                to: &timeline,
                name: .provider1ValidationStarted,
                request: request,
                attemptID: attemptID,
                providerName: ProviderSlot.coreMedia.rawValue,
                currentState: .validating,
                redactedMetadata: [
                    "mode": "web_embed",
                    "url_shape": redactURLShape(candidate.embedURL),
                    "stream_no": "\(candidate.streamNo)"
                ]
            )

            let validation = await validateWebEmbedCandidate(
                candidate,
                request: request,
                providerName: ProviderSlot.coreMedia.rawValue
            )
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            switch validation {
            case .success(let session):
                sessions.append(session)
                providerAttempts.append(
                    StreamProviderAttemptLog(
                        providerName: ProviderSlot.coreMedia.rawValue,
                        responseTimeMs: elapsedMs,
                        resolvedStreamType: session.streamType,
                        urlShape: redactURL(session.playableURL),
                        requiredHeaders: !session.requiredHeaders.isEmpty,
                        validationResult: "validated_web_embed",
                        manifestResult: session.diagnosticMetadata["manifest_result"],
                        segmentResult: session.diagnosticMetadata["segment_result"]
                    )
                )
                appendEvent(
                    to: &timeline,
                    name: .provider1ValidationSucceeded,
                    request: request,
                    attemptID: attemptID,
                    providerName: ProviderSlot.coreMedia.rawValue,
                    currentState: .validating,
                    redactedMetadata: [
                        "mode": "web_embed",
                        "url_shape": redactURL(session.playableURL)
                    ]
                )
            case .failure(let failure):
                providerAttempts.append(
                    StreamProviderAttemptLog(
                        providerName: ProviderSlot.coreMedia.rawValue,
                        responseTimeMs: elapsedMs,
                        resolvedStreamType: .unknown,
                        urlShape: failure.redactedMetadata["url_shape"] ?? redactURLShape(candidate.embedURL),
                        requiredHeaders: true,
                        validationResult: "failed_web_embed",
                        manifestResult: failure.redactedMetadata["manifest_result"],
                        segmentResult: failure.redactedMetadata["segment_result"],
                        finalFailureCategory: failure.category
                    )
                )
                appendEvent(
                    to: &timeline,
                    name: .provider1ValidationFailed,
                    request: request,
                    attemptID: attemptID,
                    providerName: ProviderSlot.coreMedia.rawValue,
                    currentState: .validating,
                    failureCategory: failure.category,
                    redactedMetadata: failure.redactedMetadata.merging(["mode": "web_embed"]) { current, _ in current }
                )
            }
        }

        return sessions
    }

    private func validateWebEmbedCandidate(
        _ candidate: AnalyticalDataEngine.StreamCandidate,
        request: StreamPlaybackRequest,
        providerName: String
    ) async -> Result<StreamSession, StreamFailure> {
        guard let url = URL(string: candidate.embedURL) else {
            return .failure(
                StreamFailure(
                    providerName: providerName,
                    category: .invalidURL,
                    technicalMessage: "Web embed candidate was not a valid URL.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: false,
                    fallbackAllowed: true,
                    redactedMetadata: ["url_shape": "invalid"]
                )
            )
        }

        if let unsupported = unsupportedFailureIfNeeded(for: url, providerName: providerName) {
            return .failure(unsupported)
        }

        let headers = webEmbedHeaders(for: candidate, embedURL: url)
        // embed.st intermittently returns ~1KB empty JW shells; retry before rejecting Score808/StreamEx.
        let maxAttempts = candidate.sourceCode.lowercased() == "hotel" ? 3 : 2
        var lastFailure: StreamFailure?

        for attempt in 1...maxAttempts {
            if Task.isCancelled {
                return .failure(cancelledFailure(.navigationCancelled, "Web embed validation cancelled."))
            }
            if attempt > 1 {
                try? await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.timeoutInterval = 8
            applyHeaders(headers, to: &urlRequest)
            // Alternate referer on retries — hotel stubs often clear with StreamEx referer.
            if attempt > 1, candidate.sourceCode.lowercased() == "hotel" {
                urlRequest.setValue("https://www.streamex.net/", forHTTPHeaderField: "Referer")
                urlRequest.setValue("https://www.streamex.net", forHTTPHeaderField: "Origin")
            }
            urlRequest.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            do {
                let (bytes, response) = try await validationSession.bytes(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastFailure = StreamFailure(
                        providerName: providerName,
                        category: .invalidURL,
                        technicalMessage: "Web embed validation response was not HTTP.",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: false,
                        fallbackAllowed: true,
                        redactedMetadata: ["url_shape": redactURL(url)]
                    )
                    continue
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    lastFailure = StreamFailure(
                        providerName: providerName,
                        category: httpResponse.statusCode == 401 || httpResponse.statusCode == 403 ? .authFailed : .manifestUnreachable,
                        technicalMessage: "Web embed validation returned HTTP \(httpResponse.statusCode).",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: httpResponse.statusCode >= 500,
                        fallbackAllowed: true,
                        redactedMetadata: [
                            "url_shape": redactURL(url),
                            "status_code": "\(httpResponse.statusCode)"
                        ]
                    )
                    continue
                }

                let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                // Real embed.st players ship ~600KB of inline config; ad-only stubs are ~1–2KB
                // and produce hls:networkError_manifestLoadError inside the web player.
                let prefix = try await readPrefix(from: bytes, limit: 8192, minimumBytes: 256)
                let bodyPreview = String(data: prefix, encoding: .utf8) ?? ""
                let bodyLower = bodyPreview.lowercased()
                let looksLikeEmbedPage = contentType.contains("text/html")
                    || bodyLower.contains("<html")
                    || bodyLower.contains("<iframe")
                    || bodyLower.contains("<script")
                    || bodyLower.contains("<!doctype")
                    || bodyLower.contains("video")
                    || bodyLower.contains("player")
                    || bodyLower.contains("jwplayer")
                let looksLikeStub = prefix.count < 32
                let explicitlyUnavailable = bodyLower.contains("embedding disabled")
                    || bodyLower.contains("channel is unavailable")
                    || bodyLower.contains("stream is unavailable")

                guard prefix.count >= 32,
                      looksLikeEmbedPage,
                      !looksLikeStub,
                      !explicitlyUnavailable else {
                    lastFailure = StreamFailure(
                        providerName: providerName,
                        category: .providerReturnedEmpty,
                        technicalMessage: explicitlyUnavailable
                            ? "Web embed explicitly reported that this channel is unavailable."
                            : (looksLikeStub
                                ? "Web embed validation returned an empty player stub (attempt \(attempt))."
                                : "Web embed validation did not return a playable embed page."),
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: true,
                        fallbackAllowed: true,
                        redactedMetadata: [
                            "url_shape": redactURL(url),
                            "manifest_result": explicitlyUnavailable
                                ? "web_embed_disabled"
                                : (looksLikeStub ? "web_embed_stub" : "web_embed_invalid")
                        ]
                    )
                    continue
                }

                var sessionHeaders = headers
                if attempt > 1, candidate.sourceCode.lowercased() == "hotel" {
                    sessionHeaders["Referer"] = "https://www.streamex.net/"
                    sessionHeaders["Origin"] = "https://www.streamex.net"
                }

                return .success(
                    StreamSession(
                        matchID: request.matchID,
                        title: webEmbedProviderName(for: candidate),
                        playableURL: url,
                        streamType: .unknown,
                        providerName: webEmbedProviderName(for: candidate),
                        requiredHeaders: sessionHeaders,
                        qualityLabel: webEmbedQualityLabel(for: candidate),
                        validationStatus: .validated,
                        diagnosticMetadata: [
                            "url_shape": redactURL(url),
                            "manifest_result": "web_embed_validated_html",
                            "segment_result": "handled_by_web_player",
                            "nexus_source": candidate.sourceCode
                        ]
                    )
                )
            } catch {
                lastFailure = failureFromError(
                    providerName: providerName,
                    fallbackAllowed: true,
                    defaultUserMessage: "No playable stream is available for this match right now.",
                    error: error,
                    defaultCategory: .manifestUnreachable
                )
            }
        }

        return .failure(
            lastFailure
                ?? StreamFailure(
                    providerName: providerName,
                    category: .manifestUnreachable,
                    technicalMessage: "Web embed validation exhausted \(maxAttempts) attempts.",
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: true,
                    redactedMetadata: ["url_shape": redactURL(url)]
                )
        )
    }

    private func webEmbedProviderName(for candidate: AnalyticalDataEngine.StreamCandidate) -> String {
        let sourceName = webEmbedSourceDisplayName(candidate.sourceCode)
        return "\(sourceName) #\(candidate.streamNo)"
    }

    private func webEmbedQualityLabel(for candidate: AnalyticalDataEngine.StreamCandidate) -> String {
        if let language = candidate.language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty {
            return candidate.isHD ? "\(language) · HD" : language
        }
        let sourceName = webEmbedSourceDisplayName(candidate.sourceCode)
        return candidate.isHD ? "\(sourceName) HD" : "\(sourceName) Web"
    }

    private func webEmbedSourceDisplayName(_ rawSource: String) -> String {
        switch rawSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "delta": return "StreamEx"
        case "echo": return "VipLeague"
        case "golf": return "MethStreams"
        case "hotel": return "Score808"
        case "india": return "StrikeOut"
        case "admin": return "StreamEx PPV"
        default:
            guard !rawSource.isEmpty else { return "Web Source" }
            return rawSource.uppercased()
        }
    }

    private func webEmbedHeaders(
        for candidate: AnalyticalDataEngine.StreamCandidate,
        embedURL: URL
    ) -> [String: String] {
        let referer = webEmbedReferer(for: embedURL, sourceCode: candidate.sourceCode)
            ?? embedURL.absoluteString
        var headers: [String: String] = [
            "Referer": referer,
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "X-Fotty-Nexus-Source": candidate.sourceCode,
            "X-Fotty-Nexus-Stream": "\(candidate.streamNo)",
            "X-Fotty-Nexus-Catalog": candidate.catalogProvider,
            "X-Fotty-Web-Embed": "true"
        ]
        if let origin = webEmbedOrigin(forReferer: referer) {
            headers["Origin"] = origin
        }
        return headers
    }

    private func webEmbedReferer(for embedURL: URL?, sourceCode: String? = nil) -> String? {
        if let sourceCode,
           let referer = AnalyticalDataEngine.embedReferer(forSourceCode: sourceCode) {
            return referer
        }
        guard let embedURL else { return nil }
        let host = embedURL.host?.lowercased() ?? ""
        // Current Nexus embeds are on embed.st; keep embedsports.top for older rows.
        if host.contains("embed.st") || host.contains("embedsports.top") {
            return "https://www.streamex.net/"
        }
        guard let scheme = embedURL.scheme, let urlHost = embedURL.host else {
            return nil
        }
        return "\(scheme)://\(urlHost)/"
    }

    private func webEmbedOrigin(forReferer referer: String) -> String? {
        guard let url = URL(string: referer),
              let scheme = url.scheme,
              let host = url.host else {
            return nil
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func validateDirectSource(
        _ source: StreamSource,
        request: StreamPlaybackRequest,
        providerName: String
    ) async -> Result<StreamSession, StreamFailure> {
        let validationStart = Date()

        if let unsupported = unsupportedFailureIfNeeded(for: source.url, providerName: providerName) {
            return .failure(unsupported)
        }

        var urlRequest = URLRequest(url: source.url)
        urlRequest.timeoutInterval = 5
        applyHeaders(source.headers, to: &urlRequest)
        urlRequest.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await validationSession.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(
                    StreamFailure(
                        providerName: providerName,
                        category: .invalidURL,
                        technicalMessage: "Validation response was not HTTP.",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: false,
                        fallbackAllowed: true,
                        redactedMetadata: ["url_shape": redactURL(source.url)]
                    )
                )
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(
                    StreamFailure(
                        providerName: providerName,
                        category: httpResponse.statusCode == 401 || httpResponse.statusCode == 403 ? .authFailed : .manifestUnreachable,
                        technicalMessage: "Validation returned HTTP \(httpResponse.statusCode).",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: httpResponse.statusCode >= 500,
                        fallbackAllowed: true,
                        redactedMetadata: [
                            "url_shape": redactURL(source.url),
                            "status_code": "\(httpResponse.statusCode)"
                        ]
                    )
                )
            }

            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let initialData = try await readPrefix(from: bytes, limit: 4096, minimumBytes: 512)
            let elapsedMs = Int(Date().timeIntervalSince(validationStart) * 1000)

            if isHLS(url: source.url, contentType: contentType, data: initialData) {
                guard let manifest = String(data: initialData, encoding: .utf8), manifest.contains("#EXTM3U") else {
                    return .failure(
                        StreamFailure(
                            providerName: providerName,
                            category: .manifestInvalid,
                            technicalMessage: "Manifest payload did not contain #EXTM3U.",
                            userMessage: "No playable stream is available for this match right now.",
                            retryable: false,
                            fallbackAllowed: true,
                            redactedMetadata: [
                                "url_shape": redactURL(source.url),
                                "manifest_result": "missing_extm3u"
                            ]
                        )
                    )
                }

                guard let firstSegment = firstSegmentURL(in: manifest, relativeTo: source.url) else {
                    return .failure(
                        StreamFailure(
                            providerName: providerName,
                            category: .manifestInvalid,
                            technicalMessage: "Manifest contained no playable segment entries.",
                            userMessage: "No playable stream is available for this match right now.",
                            retryable: false,
                            fallbackAllowed: true,
                            redactedMetadata: [
                                "url_shape": redactURL(source.url),
                                "manifest_result": "empty_segments"
                            ]
                        )
                    )
                }

                let segmentValidation = await validateSegment(
                    segmentURL: firstSegment,
                    headers: source.headers,
                    providerName: providerName
                )

                switch segmentValidation {
                case .success(let segmentBytes):
                    return .success(
                        StreamSession(
                            matchID: request.matchID,
                            title: source.title ?? request.displayTitle,
                            playableURL: source.url,
                            streamType: .hls,
                            providerName: source.provider,
                            requiredHeaders: source.headers,
                            qualityLabel: source.quality,
                            validationStatus: .validated,
                            diagnosticMetadata: [
                                "url_shape": redactURL(source.url),
                                "manifest_result": "ok",
                                "segment_result": "ok",
                                "segment_bytes": "\(segmentBytes)",
                                "validation_ms": "\(elapsedMs)"
                            ],
                            activePeers: source.activePeers
                        )
                    )
                case .failure(let failure):
                    return .failure(failure)
                }
            }

            if initialData.count < 256 {
                return .failure(
                    StreamFailure(
                        providerName: providerName,
                        category: .segmentUnreachable,
                        technicalMessage: "Validation returned only \(initialData.count) bytes.",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: true,
                        fallbackAllowed: true,
                        redactedMetadata: [
                            "url_shape": redactURL(source.url),
                            "segment_result": "short_body"
                        ]
                    )
                )
            }

            let streamType: StreamType = isMP4(url: source.url, contentType: contentType) ? .mp4 : .unknown
            return .success(
                StreamSession(
                    matchID: request.matchID,
                    title: source.title ?? request.displayTitle,
                    playableURL: source.url,
                    streamType: streamType,
                    providerName: source.provider,
                    requiredHeaders: source.headers,
                    qualityLabel: source.quality,
                    validationStatus: .validated,
                    diagnosticMetadata: [
                        "url_shape": redactURL(source.url),
                        "manifest_result": "not_applicable",
                        "segment_result": "ok",
                        "validation_ms": "\(elapsedMs)"
                    ],
                    activePeers: source.activePeers
                )
            )
        } catch is CancellationError {
            return .failure(cancelledFailure(.navigationCancelled, "Direct source validation cancelled."))
        } catch let error as URLError {
            return .failure(
                StreamFailure(
                    providerName: providerName,
                    category: error.code == .timedOut ? .providerTimeout : .manifestUnreachable,
                    technicalMessage: error.localizedDescription,
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: error.code == .timedOut || error.code == .networkConnectionLost,
                    fallbackAllowed: true,
                    redactedMetadata: ["url_shape": redactURL(source.url)]
                )
            )
        } catch {
            return .failure(
                failureFromError(
                    providerName: providerName,
                    fallbackAllowed: true,
                    defaultUserMessage: "No playable stream is available for this match right now.",
                    error: error,
                    defaultCategory: .unknown
                )
            )
        }
    }

    private func validateP2PSource(
        _ source: StreamSource,
        request: StreamPlaybackRequest,
        attemptID: String,
        timeline: inout [StreamEventRecord],
        providerAttempts: inout [StreamProviderAttemptLog],
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async -> Result<StreamSession, StreamFailure> {
        let providerName = ProviderSlot.p2p.rawValue
        let start = Date()

        if let unsupported = unsupportedFailureIfNeeded(for: source.url, providerName: providerName) {
            return .failure(unsupported)
        }

        appendEvent(
            to: &timeline,
            name: .provider2ValidationStarted,
            request: request,
            attemptID: attemptID,
            providerName: providerName,
            currentState: .warmingUpP2P,
            redactedMetadata: ["url_shape": redactURL(source.url)]
        )
        appendEvent(
            to: &timeline,
            name: .p2pWarmupStarted,
            request: request,
            attemptID: attemptID,
            providerName: providerName,
            currentState: .warmingUpP2P,
            redactedMetadata: ["url_shape": redactURL(source.url)]
        )

        await emitProgress(
            attemptID: attemptID,
            state: .warmingUpP2P,
            userMessage: "Connecting to P2P proxy...",
            technicalMessage: "Preparing broker session (manifest + segment validation).",
            providerName: providerName,
            onProgress: onProgress
        )

        do {
            let prepared = try await AceSessionEngine.shared.prepareSession(for: source, forceRestart: false) { snapshot in
                await self.emitAceWarmupProgress(
                    attemptID: attemptID,
                    snapshot: snapshot,
                    providerName: providerName,
                    onProgress: onProgress
                )
            }
            let urlShape = redactURL(prepared.playbackURL)
            let session = StreamSession(
                matchID: request.matchID,
                title: source.title ?? request.displayTitle,
                playableURL: prepared.playbackURL,
                streamType: .p2pProxyHLS,
                providerName: source.provider,
                requiredHeaders: source.headers,
                qualityLabel: source.quality,
                expiryTime: prepared.expiresAt ?? prepared.preparedAt.addingTimeInterval(p2pReuseWindowSeconds),
                leaseID: prepared.sessionID,
                canRefresh: true,
                validationStatus: .validated,
                diagnosticMetadata: [
                    "cid": prepared.cid,
                    "url_shape": urlShape,
                    "manifest_result": "ok",
                    "segment_result": "ok",
                    "session_state": prepared.lastStatus?.state ?? "ready"
                ],
                createdAt: prepared.preparedAt,
                lastRefreshAt: prepared.preparedAt,
                activePeers: source.activePeers ?? prepared.lastStatus?.peerCount
            )
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            providerAttempts.append(
                StreamProviderAttemptLog(
                    providerName: providerName,
                    responseTimeMs: elapsedMs,
                    resolvedStreamType: session.streamType,
                    urlShape: urlShape,
                    requiredHeaders: !session.requiredHeaders.isEmpty,
                    validationResult: "validated",
                    manifestResult: "ok",
                    segmentResult: "ok"
                )
            )
            appendEvent(
                to: &timeline,
                name: .p2pWarmupSucceeded,
                request: request,
                attemptID: attemptID,
                providerName: providerName,
                sessionID: prepared.sessionID,
                currentState: .readyToPlay,
                redactedMetadata: [
                    "cid": prepared.cid,
                    "url_shape": urlShape,
                    "peer_count": "\(prepared.lastStatus?.peerCount ?? 0)"
                ]
            )
            appendEvent(
                to: &timeline,
                name: .provider2ValidationSucceeded,
                request: request,
                attemptID: attemptID,
                providerName: providerName,
                sessionID: prepared.sessionID,
                currentState: .readyToPlay,
                redactedMetadata: ["cid": prepared.cid, "url_shape": urlShape]
            )
            return .success(session)
        } catch let error as AceSessionEngine.PreparationError {
            let category: StreamFailureCategory
            switch error {
            case .timedOut:
                category = .p2pWarmupFailed
            case .brokerSessionNotFound:
                category = .p2pWarmupFailed
            case .cancelled:
                category = .navigationCancelled
            case .invalidSource:
                category = .rawP2PIDReturned
            case .failed(let reason):
                category = mapP2PReasonToCategory(reason)
            }

            let failure = StreamFailure(
                providerName: providerName,
                category: category,
                technicalMessage: error.errorDescription ?? "P2P warmup failed.",
                userMessage: category == .p2pProxyNotReady || category == .p2pWarmupFailed
                    ? "The stream is still preparing..."
                    : "No playable stream is available for this match right now.",
                retryable: category == .p2pProxyNotReady || category == .p2pWarmupFailed || category == .p2pProxyUnreachable,
                fallbackAllowed: false,
                redactedMetadata: ["url_shape": redactURL(source.url)]
            )
            appendEvent(
                to: &timeline,
                name: .p2pWarmupFailed,
                request: request,
                attemptID: attemptID,
                providerName: providerName,
                currentState: .failed,
                failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata
            )
            appendEvent(
                to: &timeline,
                name: .provider2ValidationFailed,
                request: request,
                attemptID: attemptID,
                providerName: providerName,
                currentState: .failed,
                failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata
            )
            return .failure(failure)
        } catch {
            let failure = failureFromError(
                providerName: providerName,
                fallbackAllowed: false,
                defaultUserMessage: "No playable stream is available for this match right now.",
                error: error,
                defaultCategory: .p2pWarmupFailed
            )
            appendEvent(
                to: &timeline,
                name: .provider2ValidationFailed,
                request: request,
                attemptID: attemptID,
                providerName: providerName,
                currentState: .failed,
                failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata
            )
            return .failure(failure)
        }
    }

    private func resolveCatalogEvent(for request: StreamPlaybackRequest) async throws -> AnalyticalDataEngine.EventReference? {
        if let preferred = request.preferredEvent,
           let sources = preferred.sources,
           !sources.isEmpty {
            return preferred
        }

        let allEvents = try await AnalyticalDataEngine.fetchLiveEvents_NexusAImplementation()
        guard !allEvents.isEmpty else { return nil }

        let targetCategory = request.category.lowercased()
        let homePhrase = canonicalTeamPhrase(request.homeTeam)
        let awayPhrase = canonicalTeamPhrase(request.awayTeam)
        let kickoff = request.kickoffDate

        struct EventSnapshot {
            let event: AnalyticalDataEngine.EventReference
            let normalizedCategory: String
            let homeName: String
            let awayName: String
            let kickoffDate: Date?
            let hasSources: Bool
            let isPopular: Bool
        }

        let snapshots = await MainActor.run {
            allEvents.map { event in
                EventSnapshot(
                    event: event,
                    normalizedCategory: event.normalizedCategory.lowercased(),
                    homeName: event.homeName,
                    awayName: event.awayName,
                    kickoffDate: event.kickoffDate,
                    hasSources: !(event.sources ?? []).isEmpty,
                    isPopular: event.popular == true
                )
            }
        }

        // Notification and Live Activity routes can cold-launch with only the
        // provider catalog id. Resolve that exact identity before attempting
        // fuzzy team-name matching, which has no useful input in this path.
        if let exact = snapshots.first(where: {
            CatalogRouteIdentity.matches(eventID: $0.event.id, requestedID: request.matchID)
        }) {
            return exact.event
        }

        return snapshots
            .filter { snapshot in
                targetCategory.isEmpty || snapshot.normalizedCategory == targetCategory
            }
            .map { snapshot -> (event: AnalyticalDataEngine.EventReference, score: Int, kickoffDate: Date?, homeOverlap: Int, awayOverlap: Int) in
                let eventHome = canonicalTeamPhrase(snapshot.homeName)
                let eventAway = canonicalTeamPhrase(snapshot.awayName)
                let homeOverlap = tokenOverlapScore(lhs: homePhrase, rhs: eventHome)
                let awayOverlap = tokenOverlapScore(lhs: awayPhrase, rhs: eventAway)
                var score = 0

                if eventHome == homePhrase { score += 60 }
                if eventAway == awayPhrase { score += 60 }
                if aliasesEquivalent(eventHome, homePhrase) { score += 50 }
                if aliasesEquivalent(eventAway, awayPhrase) { score += 50 }
                score += homeOverlap * 12
                score += awayOverlap * 12

                if let kickoff, let eventKickoff = snapshot.kickoffDate {
                    let delta = abs(eventKickoff.timeIntervalSince(kickoff))
                    if delta <= 15 * 60 {
                        score += 35
                    } else if delta <= 60 * 60 {
                        score += 15
                    }
                }

                if snapshot.hasSources {
                    score += 10
                }
                if snapshot.isPopular {
                    score += 2
                }

                return (snapshot.event, score, snapshot.kickoffDate, homeOverlap, awayOverlap)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                let lhsDate = lhs.kickoffDate ?? .distantFuture
                let rhsDate = rhs.kickoffDate ?? .distantFuture
                return lhsDate < rhsDate
            }
            .first { candidate in
                candidate.score >= 40
                    || (candidate.homeOverlap > 0 && candidate.awayOverlap > 0 && candidate.score >= 24)
            }?
            .event
    }

    private func validateSegment(
        segmentURL: URL,
        headers: [String: String],
        providerName: String
    ) async -> Result<Int, StreamFailure> {
        var request = URLRequest(url: segmentURL)
        request.timeoutInterval = 8
        applyHeaders(headers, to: &request)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await validationSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(
                    StreamFailure(
                        providerName: providerName,
                        category: .segmentUnreachable,
                        technicalMessage: "Segment probe response was not HTTP.",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: true,
                        fallbackAllowed: true,
                        redactedMetadata: ["url_shape": redactURL(segmentURL)]
                    )
                )
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(
                    StreamFailure(
                        providerName: providerName,
                        category: .segmentUnreachable,
                        technicalMessage: "Segment probe returned HTTP \(httpResponse.statusCode).",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: httpResponse.statusCode >= 500,
                        fallbackAllowed: true,
                        redactedMetadata: [
                            "url_shape": redactURL(segmentURL),
                            "segment_result": "http_\(httpResponse.statusCode)"
                        ]
                    )
                )
            }

            let prefix = try await readPrefix(from: bytes, limit: 2048, minimumBytes: 512)
            guard prefix.count >= 512 else {
                return .failure(
                    StreamFailure(
                        providerName: providerName,
                        category: .segmentUnreachable,
                        technicalMessage: "Segment probe returned only \(prefix.count) bytes.",
                        userMessage: "No playable stream is available for this match right now.",
                        retryable: true,
                        fallbackAllowed: true,
                        redactedMetadata: [
                            "url_shape": redactURL(segmentURL),
                            "segment_result": "short_body"
                        ]
                    )
                )
            }

            return .success(prefix.count)
        } catch let error as URLError {
            return .failure(
                StreamFailure(
                    providerName: providerName,
                    category: error.code == .timedOut ? .segmentUnreachable : .manifestUnreachable,
                    technicalMessage: error.localizedDescription,
                    userMessage: "No playable stream is available for this match right now.",
                    retryable: true,
                    fallbackAllowed: true,
                    redactedMetadata: ["url_shape": redactURL(segmentURL)]
                )
            )
        } catch {
            return .failure(
                failureFromError(
                    providerName: providerName,
                    fallbackAllowed: true,
                    defaultUserMessage: "No playable stream is available for this match right now.",
                    error: error,
                    defaultCategory: .segmentUnreachable
                )
            )
        }
    }

    private func emitProgress(
        attemptID: String,
        state: StreamLoadState,
        userMessage: String,
        technicalMessage: String?,
        providerName: String?,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async {
        guard let onProgress else { return }
        await onProgress(
            StreamAttemptProgress(
                attemptID: attemptID,
                state: state,
                userMessage: userMessage,
                technicalMessage: technicalMessage,
                providerName: providerName
            )
        )
    }

    private func emitAceWarmupProgress(
        attemptID: String,
        snapshot: AceSessionEngine.SessionSnapshot,
        providerName: String?,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)?
    ) async {
        let mapped = mapAceSnapshotToStreamProgress(snapshot)
        await emitProgress(
            attemptID: attemptID,
            state: mapped.state,
            userMessage: mapped.userMessage,
            technicalMessage: mapped.technicalMessage,
            providerName: providerName,
            onProgress: onProgress
        )
    }

    private func mapAceSnapshotToStreamProgress(_ snapshot: AceSessionEngine.SessionSnapshot)
        -> (state: StreamLoadState, userMessage: String, technicalMessage: String?) {
        switch snapshot.state {
        case .idle:
            return (.warmingUpP2P, "Connecting to P2P...", nil)
        case .starting:
            return (.warmingUpP2P, "Starting P2P session...", snapshot.message)
        case .resolving:
            return (.warmingUpP2P, "Looking for peers...", snapshot.message)
        case .warming(let peers, let speed, _):
            if peers > 0 {
                return (.warmingUpP2P, "Warming P2P (\(peers) peers, \(Int(speed)) kbps)", snapshot.message)
            }
            return (.warmingUpP2P, "Warming P2P...", snapshot.message)
        case .validatingManifest:
            return (.validating, "Verifying stream...", snapshot.message)
        case .ready:
            return (.readyToPlay, "Stream ready.", snapshot.message)
        case .failed(let reason):
            return (.warmingUpP2P, reason, snapshot.message)
        case .timedOut:
            return (.failed, "P2P warmup timed out.", snapshot.message)
        }
    }

    private func appendEvent(
        to timeline: inout [StreamEventRecord],
        name: StreamEventName,
        request: StreamPlaybackRequest,
        attemptID: String,
        providerName: String? = nil,
        taskID: String? = nil,
        sessionID: String? = nil,
        currentState: StreamLoadState,
        failureCategory: StreamFailureCategory? = nil,
        redactedMetadata: [String: String] = [:]
    ) {
        timeline.append(
            StreamEventRecord(
                name: name,
                matchID: request.matchID,
                matchTitle: request.displayTitle,
                providerName: providerName,
                attemptID: attemptID,
                taskID: taskID,
                sessionID: sessionID,
                currentState: currentState,
                failureCategory: failureCategory,
                redactedMetadata: redactedMetadata
            )
        )
    }

    private func makeDiagnostics(
        attemptID: String,
        request: StreamPlaybackRequest,
        finalState: StreamLoadState,
        timeline: [StreamEventRecord],
        providerAttempts: [StreamProviderAttemptLog],
        startedAt: Date = Date()
    ) -> StreamAttemptDiagnostics {
        StreamAttemptDiagnostics(
            attemptID: attemptID,
            matchID: request.matchID,
            matchTitle: request.displayTitle,
            finalState: finalState,
            createdAt: startedAt,
            completedAt: Date(),
            timeline: timeline,
            providerAttempts: providerAttempts
        )
    }

    private func recordDiagnostics(_ diagnostics: StreamAttemptDiagnostics) async {
        #if DEBUG
        await StreamDebugStore.shared.record(diagnostics)
        #endif
    }

    private func activeKey(for request: StreamPlaybackRequest) -> String {
        let dateKey = request.kickoffDate.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        return "\(request.homeTeam.lowercased())|\(request.awayTeam.lowercased())|\(dateKey)"
    }

    private func deduplicatedSessions(_ sessions: [StreamSession]) -> [StreamSession] {
        var seen = Set<String>()
        return sessions.filter { session in
            let key = "\(session.providerName.lowercased())|\(redactURL(session.playableURL))"
            return seen.insert(key).inserted
        }
    }

    private func unsupportedFailureIfNeeded(for url: URL, providerName: String) -> StreamFailure? {
        guard let scheme = url.scheme?.lowercased() else {
            return StreamFailure(
                providerName: providerName,
                category: .invalidURL,
                technicalMessage: "Missing URL scheme.",
                userMessage: "No playable stream is available for this match right now.",
                retryable: false,
                fallbackAllowed: true
            )
        }

        if scheme == "acestream" || scheme == "magnet" {
            return StreamFailure(
                providerName: providerName,
                category: .rawP2PIDReturned,
                technicalMessage: "Provider returned a raw P2P identifier instead of a proxy URL.",
                userMessage: "No playable stream is available for this match right now.",
                retryable: false,
                fallbackAllowed: true,
                redactedMetadata: ["url_shape": redactURL(url)]
            )
        }

        guard scheme == "http" || scheme == "https" else {
            return StreamFailure(
                providerName: providerName,
                category: .unsupportedScheme,
                technicalMessage: "Unsupported scheme \(scheme).",
                userMessage: "No playable stream is available for this match right now.",
                retryable: false,
                fallbackAllowed: true,
                redactedMetadata: ["url_shape": redactURL(url)]
            )
        }

        return nil
    }

    private func cancelledFailure(_ category: StreamFailureCategory, _ message: String) -> StreamFailure {
        StreamFailure(
            providerName: nil,
            category: category,
            technicalMessage: message,
            userMessage: "Stream loading was cancelled.",
            retryable: false,
            fallbackAllowed: false
        )
    }

    private func cancelledOutcome(
        attemptID: String,
        request: StreamPlaybackRequest,
        timeline: [StreamEventRecord],
        providerAttempts: [StreamProviderAttemptLog],
        category: StreamFailureCategory,
        technicalMessage: String
    ) -> StreamResolutionOutcome {
        var mutableTimeline = timeline
        appendEvent(
            to: &mutableTimeline,
            name: .streamAttemptCancelled,
            request: request,
            attemptID: attemptID,
            currentState: .cancelled,
            failureCategory: category
        )
        let failure = StreamFailure(
            providerName: nil,
            category: category,
            technicalMessage: technicalMessage,
            userMessage: "Stream loading was cancelled.",
            retryable: false,
            fallbackAllowed: false
        )
        let diagnostics = makeDiagnostics(
            attemptID: attemptID,
            request: request,
            finalState: .cancelled,
            timeline: mutableTimeline,
            providerAttempts: providerAttempts
        )
        return .failure(failure, diagnostics)
    }

    private func isP2PCandidate(_ candidate: AnalyticalDataEngine.StreamCandidate) -> Bool {
        let url = candidate.embedURL.lowercased()
        return url.contains("acestream://")
            || url.contains("/proxy/acestream/")
    }

    private func isHLS(url: URL, contentType: String, data: Data) -> Bool {
        if url.pathExtension.lowercased() == "m3u8" {
            return true
        }
        if contentType.contains("mpegurl") || contentType.contains("application/x-mpegurl") {
            return true
        }
        if let body = String(data: data, encoding: .utf8), body.contains("#EXTM3U") {
            return true
        }
        return false
    }

    private func isMP4(url: URL, contentType: String) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mp4" || contentType.contains("video/mp4")
    }

    private func readPrefix(
        from bytes: URLSession.AsyncBytes,
        limit: Int,
        minimumBytes: Int
    ) async throws -> Data {
        var data = Data()
        var iterator = bytes.makeAsyncIterator()
        while data.count < limit,
              let byte = try await iterator.next() {
            data.append(byte)
            if data.count >= minimumBytes {
                break
            }
        }
        return data
    }

    private func firstSegmentURL(in manifest: String, relativeTo baseURL: URL) -> URL? {
        for rawLine in manifest.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                return resolved
            }
        }
        return nil
    }

    private func applyHeaders(_ headers: [String: String], to request: inout URLRequest) {
        for (key, value) in headers where !key.lowercased().hasPrefix("x-fotty-") {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let requestURL = request.url,
           let cookies = HTTPCookieStorage.shared.cookies(for: requestURL) {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
    }

    private func mapP2PReasonToCategory(_ reason: String) -> StreamFailureCategory {
        let normalized = reason.lowercased()
        if normalized.contains("timed out") {
            return .p2pWarmupFailed
        }
        if normalized.contains("proxy") || normalized.contains("offline") || normalized.contains("unreachable") {
            return .p2pProxyUnreachable
        }
        if normalized.contains("not ready") || normalized.contains("warming") {
            return .p2pProxyNotReady
        }
        if normalized.contains("manifest") {
            return .manifestInvalid
        }
        return .p2pWarmupFailed
    }

    private func failureFromError(
        providerName: String,
        fallbackAllowed: Bool,
        defaultUserMessage: String,
        error: Error,
        defaultCategory: StreamFailureCategory
    ) -> StreamFailure {
        if let failure = error as? StreamFailure {
            return failure
        }

        if let urlError = error as? URLError {
            let category: StreamFailureCategory
            switch urlError.code {
            case .timedOut:
                category = .providerTimeout
            case .networkConnectionLost, .notConnectedToInternet:
                category = .manifestUnreachable
            default:
                category = defaultCategory
            }

            return StreamFailure(
                providerName: providerName,
                category: category,
                technicalMessage: urlError.localizedDescription,
                userMessage: defaultUserMessage,
                retryable: urlError.code == .timedOut || urlError.code == .networkConnectionLost,
                fallbackAllowed: fallbackAllowed
            )
        }

        return StreamFailure(
            providerName: providerName,
            category: defaultCategory,
            technicalMessage: error.localizedDescription,
            userMessage: defaultUserMessage,
            retryable: false,
            fallbackAllowed: fallbackAllowed
        )
    }

    private func normalizedPhrase(_ value: String) -> String {
        let ignoredTokens: Set<String> = [
            "fc", "cf", "afc", "ac", "sc", "sk", "fk", "nk", "tj", "club", "team"
        ]

        return value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .filter { !ignoredTokens.contains(String($0)) }
            .joined(separator: " ")
    }

    private func canonicalTeamPhrase(_ value: String) -> String {
        let phrase = normalizedPhrase(value)
        switch phrase {
        case "turkiye", "turkey": return "turkey"
        case "cape verde islands", "cape verde": return "cape verde"
        case "curaçao", "curacao": return "curacao"
        case "cote d ivoire", "ivory coast": return "ivory coast"
        case "dr congo", "congo dr", "democratic republic of congo": return "congo dr"
        case "bosnia and herzegovina", "bosnia herzegovina": return "bosnia herzegovina"
        case "usa", "united states": return "united states"
        case "korea republic", "south korea": return "south korea"
        default: return phrase
        }
    }

    private func aliasesEquivalent(_ left: String, _ right: String) -> Bool {
        canonicalTeamPhrase(left) == canonicalTeamPhrase(right)
    }

    private func tokenOverlapScore(lhs: String, rhs: String) -> Int {
        // Use > 1 (i.e. length >= 2) so 3-char tokens like "PSG", "Man", "BVB" are included.
        let left = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let right = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        return left.intersection(right).count
    }

    private func redactURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? "\(url.scheme ?? "unknown")://\(url.host ?? "unknown")\(url.path)"
    }

    private func redactURLShape(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "invalid" }
        return redactURL(url)
    }
}
#endif
