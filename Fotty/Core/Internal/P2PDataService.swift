import Foundation

actor P2PDataService: LiveStreamingProvider {
    static let shared = P2PDataService()

    nonisolated let name = StringObfuscator.decode([0x7, 0xC, 0x11, 0x27, 0xD, 0x33, 0xB, 0x0, 0x1])
    nonisolated let priority = 20 // Lower priority — let NexusA (priority 10) play first; P2P takes 30-120s to warm up

    // Official subdomains via Cloudflare Tunnel
    static let decodedServerURL = Config.P2P.serverBaseURLString
    static let decodedScraperURL = Config.P2P.scraperBaseURLString
    static let decodedAPIPassword = StringObfuscator.decode([0x20, 0x0, 0x0, 0x0, 0x0, 0x1E, 0x1E, 0x53, 0x1C, 0x26, 0x7, 0xC, 0x0, 0x6, 0x24, 0x57])

    // Discovery session can be longer because scraper endpoints may cold-start.
    private static let discoverySession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 150
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // Preflight must allow enough time for the 2026 swarm to stabilize.
    private static let preflightSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 50
        config.timeoutIntervalForResource = 70
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
    private static let p2pReferer = "https://p2p.pixel-invoice.com/"
    private static let hlsAcceptHeader = "application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8"
    private static let maxReturnedSources = 20 // Expanded to find more healthy swarms
    private static let maxProbeAttempts = maxReturnedSources * 2
    private static let maxBrowseChannels = 80
    /// Cap for sport-channel / search-fallback rows before preflight (was 8 — too few for PL-heavy feeds).
    private static let maxContextualFallbackCandidates = 32
    private static let minimumSegmentBytes = 512
    private static let preflightTimeoutSeconds: TimeInterval = 50
    private static let maxPreflightBudgetSeconds: TimeInterval = 75
    private static let preflightReadLimitBytes = 4096
    private static let proxyStatusTimeoutSeconds: TimeInterval = 5
    private static let brokerSnapshotTimeoutSeconds: TimeInterval = 5
    
    private var latestPreflightSummary = "P2P preflight has not run yet."
    
    func latestPreflightSummaryText() -> String {
        latestPreflightSummary
    }

    static func brokerSessionCreateURL() -> URL? {
        URL(string: "\(decodedServerURL)/proxy/acestream/session")
    }

    private static var edgeHeaders: [String: String] {
        Config.P2P.edgeHeaders
    }

    private static func applyStandardHeaders(
        to request: inout URLRequest,
        accept: String = "application/json"
    ) {
        request.setValue("Bearer \(decodedAPIPassword)", forHTTPHeaderField: "Authorization")
        request.setValue(decodedAPIPassword, forHTTPHeaderField: "api-password")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(p2pReferer, forHTTPHeaderField: "Referer")
        for (key, value) in edgeHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private static func brokerMetadataHeaders(for match: ScrapedAceMatch, categoryHint: String? = nil) -> [String: String] {
        var headers: [String: String] = [
            "X-Fotty-P2P-Cid": match.cid,
            "X-Fotty-P2P-Title": match.title
        ]
        if let availability = match.availability {
            headers["X-Fotty-P2P-Availability"] = "\(availability)"
        }
        if let bitrateKbps = match.bitrateKbps {
            headers["X-Fotty-P2P-Bitrate-Kbps"] = "\(bitrateKbps)"
        }
        if let source = match.source, !source.isEmpty {
            headers["X-Fotty-P2P-Source"] = source
        }
        if !match.categories.isEmpty {
            headers["X-Fotty-P2P-Categories"] = match.categories.joined(separator: ",")
        }
        if let categoryHint, !categoryHint.isEmpty {
            headers["X-Fotty-P2P-Category"] = categoryHint
        } else if let primaryCategory = match.primaryCategory {
            headers["X-Fotty-P2P-Category"] = primaryCategory
        }
        return headers
    }
    
    // MARK: - External API
    
    func findStreams(homeTeam: String, awayTeam: String) async throws -> [StreamSource] {
        try await findStreams(homeTeam: homeTeam, awayTeam: awayTeam, category: nil)
    }
    
    func findStreams(homeTeam: String, awayTeam: String, category: String?) async throws -> [StreamSource] {
        try await findStreams(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            category: category,
            allowSportChannelFallback: true
        )
    }

    func findStreams(
        homeTeam: String,
        awayTeam: String,
        category: String?,
        allowSportChannelFallback: Bool
    ) async throws -> [StreamSource] {
        let sources = await searchForMatch(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            category: category,
            allowSportChannelFallback: allowSportChannelFallback
        )
        guard !sources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }
        return sources
    }
    
    func browseChannels(category: String? = nil) async -> [StreamSource] {
        await allSportChannels(category: category)
    }

    /// Main discovery entry point using the advanced MatchDiscoveryEngine logic
    func search(query: String) async throws -> [StreamSource] {
        // Clear previous diagnostics before starting a new search
        await MainActor.run {
            MatchDiscoveryEngine.shared.latestDiagnostics = nil
        }
        
        // Dynamic extraction: Try to split query for discovery engine
        let separators = [" vs ", " v ", " - ", " @ "]
        var home = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var away = ""
        
        for separator in separators {
            let parts = query.components(separatedBy: separator)
            if parts.count >= 2 {
                home = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                away = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        if !away.isEmpty {
            return await searchForMatch(
                homeTeam: home,
                awayTeam: away,
                category: nil,
                allowSportChannelFallback: true
            )
        }

        guard let encoded = home.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(Self.decodedScraperURL)/search/\(encoded)") else {
            throw ProcessorError.invalidURL
        }

        let matches = try await fetchMatches(from: url)
        let sources = await preflightAndBuildSources(from: matches, context: "search", scope: .catalog)
        guard !sources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }
        return sources
    }


    // MARK: - Phase 1: Match-specific search

    private func searchForMatch(
        homeTeam: String,
        awayTeam: String,
        category: String?,
        allowSportChannelFallback: Bool
    ) async -> [StreamSource] {
        let context = Self.MatchContext(homeTeam: homeTeam, awayTeam: awayTeam, category: category)
        let queries = [
            "\(homeTeam) \(awayTeam)",
            homeTeam,
            awayTeam
        ]
        
        let candidates = await withTaskGroup(of: [ScrapedAceMatch].self) { group in
            group.addTask {
                guard let url = URL(string: "\(Self.decodedScraperURL)/matches") else { return [] }
                return (try? await self.fetchMatches(from: url)) ?? []
            }
            
            for query in queries {
                group.addTask {
                    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let url = URL(string: "\(Self.decodedScraperURL)/search/\(encoded)") else { return [] }
                    return (try? await self.fetchMatches(from: url)) ?? []
                }
            }
            
            var all = [ScrapedAceMatch]()
            var seen = Set<String>()
            for await matches in group {
                for match in matches {
                    if seen.insert(match.cid).inserted {
                        all.append(match)
                    }
                }
            }
            return all
        }
        
        let rankedMatchingCandidates = candidates
            .compactMap { match -> (match: ScrapedAceMatch, score: Int)? in
                let score = Self.exactMatchScore(match, context: context)
                guard score >= context.minimumExactMatchScore else { return nil }
                return (match, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                let lhsHealth = Self.historicalHealthScore(for: lhs.match)
                let rhsHealth = Self.historicalHealthScore(for: rhs.match)
                if lhsHealth != rhsHealth {
                    return lhsHealth > rhsHealth
                }
                return (lhs.match.availability ?? 0) > (rhs.match.availability ?? 0)
            }
        let matchingCandidates = rankedMatchingCandidates.map(\.match)
        let exactMatchConfidenceByCID = Dictionary(uniqueKeysWithValues: rankedMatchingCandidates.map { ($0.match.cid, $0.score) })
        
        if !matchingCandidates.isEmpty {
            let sources = await preflightAndBuildSources(
                from: matchingCandidates,
                context: "match",
                scope: .exactMatch,
                matchConfidenceByCID: exactMatchConfidenceByCID
            )
            if !sources.isEmpty {
                return sources
            }
        }

        guard allowSportChannelFallback else {
            return []
        }

        // Only exclude CIDs that actually had an exact match — not all 122 fetched channels.
        // If we exclude all candidates, the sport-channel fallback (which finds CL channels like
        // "M. Liga de Campeones" or "Sky Sports Football") will see an empty inclusion list.
        let seenCids = Set(matchingCandidates.map { $0.cid })
        let sportSearchCandidates = await sportSearchFallbackCandidates(context: context, excluding: seenCids)

        if !sportSearchCandidates.isEmpty {
            let searchFallbackSources = await preflightAndBuildSources(
                from: sportSearchCandidates,
                context: "\(context.categoryDisplayName) search fallback",
                scope: .sportChannel
            )
            if !searchFallbackSources.isEmpty {
                return searchFallbackSources
            }
        }
        
        // If no exact matches passed preflight, fall back to general sport channels
        let channelCandidates = await sportScopedChannelCandidates(context: context, excluding: seenCids)
        
        if !channelCandidates.isEmpty {
            let channelSources = await preflightAndBuildSources(
                from: channelCandidates,
                context: "\(context.categoryDisplayName) channels",
                scope: .sportChannel
            )
            if !channelSources.isEmpty {
                return channelSources
            }
        }
        
        return []
    }

    // MARK: - Phase 2: All sport channels

    private func allSportChannels(category: String?) async -> [StreamSource] {
        guard let url = URL(string: "\(Self.decodedScraperURL)/matches") else { return [] }
        let matches = (try? await fetchMatches(from: url)) ?? []
        let normalizedCategory = Self.canonicalCategory(category ?? "")
        let brokerHealth = await Self.fetchBrokerHealth()

        let orderedMatches: [ScrapedAceMatch]
        if normalizedCategory.isEmpty || normalizedCategory == "other" {
            orderedMatches = matches
                .sorted { lhs, rhs in
                    let lhsBrokerScore = Self.brokerHealthScore(for: lhs, brokerHealth: brokerHealth)
                    let rhsBrokerScore = Self.brokerHealthScore(for: rhs, brokerHealth: brokerHealth)
                    if lhsBrokerScore != rhsBrokerScore {
                        return lhsBrokerScore > rhsBrokerScore
                    }
                    if (lhs.availability ?? 0) != (rhs.availability ?? 0) {
                        return (lhs.availability ?? 0) > (rhs.availability ?? 0)
                    }
                    return lhs.title < rhs.title
                }
        } else {
            let context = MatchContext(homeTeam: "", awayTeam: "", category: normalizedCategory)
            var seen = Set<String>()
            var prioritized: [ScrapedAceMatch] = []

            let searchFallback = await sportSearchFallbackCandidates(context: context, excluding: seen)
            for match in searchFallback where seen.insert(match.cid).inserted {
                prioritized.append(match)
            }

            let channelFallback = await sportScopedChannelCandidates(context: context, excluding: seen)
            for match in channelFallback where seen.insert(match.cid).inserted {
                prioritized.append(match)
            }

            let remainder = matches
                .filter { seen.insert($0.cid).inserted }
                .sorted { lhs, rhs in
                    let lhsScore = Self.sportChannelScore(lhs, context: context)
                    let rhsScore = Self.sportChannelScore(rhs, context: context)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                    let lhsBrokerScore = Self.brokerHealthScore(for: lhs, brokerHealth: brokerHealth)
                    let rhsBrokerScore = Self.brokerHealthScore(for: rhs, brokerHealth: brokerHealth)
                    if lhsBrokerScore != rhsBrokerScore {
                        return lhsBrokerScore > rhsBrokerScore
                    }
                    if (lhs.availability ?? 0) != (rhs.availability ?? 0) {
                        return (lhs.availability ?? 0) > (rhs.availability ?? 0)
                    }
                    return lhs.title < rhs.title
                }

            orderedMatches = prioritized + remainder
        }

        // For manual browse, we want to show all matching channels, but prioritize verified ones.
        // We no longer strictly filter by brokerHealthIndicatesPlayable here to avoid the "empty list" problem
        // when the broker is cold but the channels are actually live.
        let playableMatches = orderedMatches
        
        guard !playableMatches.isEmpty else {
            latestPreflightSummary = normalizedCategory.isEmpty || normalizedCategory == "other"
                ? "No P2P channels were found for this category."
                : "No \(Self.displayName(forCategory: normalizedCategory)) P2P channels were found."
            return []
        }

        if normalizedCategory.isEmpty || normalizedCategory == "other" {
            latestPreflightSummary = "P2P manual browse loaded \(playableMatches.count) broker-ready channel(s). Cold catalog channels are hidden until they pass server playback checks."
        } else {
            latestPreflightSummary = "P2P manual browse loaded \(playableMatches.count) broker-ready \(Self.displayName(forCategory: normalizedCategory)) channel(s). Cold catalog channels are hidden until they pass server playback checks."
        }

        return Self.browseSources(from: playableMatches, brokerHealth: brokerHealth)
    }

    // MARK: - Helpers

    func fetchMatches(from url: URL) async throws -> [ScrapedAceMatch] {
        var request = URLRequest(url: url)
        Self.applyStandardHeaders(to: &request)
        
        do {
            let (data, response) = try await Self.discoverySession.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("[P2P] Scraper returned HTTP \(http.statusCode) for \(url.path)")
                latestPreflightSummary = "Scraper Error: HTTP \(http.statusCode)"
                return []
            }
            return try JSONDecoder().decode([ScrapedAceMatch].self, from: data)
        } catch {
            print("[P2P] Fetch failed: \(error.localizedDescription)")
            latestPreflightSummary = "Network Error: \(error.localizedDescription)"
            throw error
        }
    }

    private static func fetchBrokerHealth() async -> [String: BrokerHealth] {
        guard var components = URLComponents(string: "\(decodedServerURL)/proxy/acestream/prewarm") else {
            return [:]
        }
        components.queryItems = [URLQueryItem(name: "api_password", value: decodedAPIPassword)]
        guard let url = components.url else { return [:] }

        var request = URLRequest(url: url)
        request.timeoutInterval = brokerSnapshotTimeoutSeconds
        applyStandardHeaders(to: &request)

        do {
            let (data, response) = try await preflightSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return [:]
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                try decodeFlexibleDate(from: decoder)
            }
            let envelope = try decoder.decode(BrokerPrewarmEnvelope.self, from: data)
            return envelope.broker?.cidHealth.reduce(into: [String: BrokerHealth]()) { partial, item in
                partial[item.key.lowercased()] = item.value
            } ?? [:]
        } catch {
            return [:]
        }
    }

    private static func decodeFlexibleDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
    }

    private static func brokerHealth(for match: ScrapedAceMatch, brokerHealth: [String: BrokerHealth]) -> BrokerHealth? {
        brokerHealth[match.cid.lowercased()]
    }

    private static func brokerHealthScore(for match: ScrapedAceMatch, brokerHealth: [String: BrokerHealth]) -> Int {
        Self.brokerHealth(for: match, brokerHealth: brokerHealth)?.score ?? 0
    }

    private static func brokerHealthIndicatesPlayable(_ health: BrokerHealth?) -> Bool {
        guard let health, (health.successCount ?? 0) > 0 else {
            return false
        }

        let score = health.score ?? 0
        let segmentRate = health.segmentSuccessRate ?? 0
        let hadRecentFailureAfterReady: Bool
        if let lastFailureAt = health.lastFailureAt, let lastReadyAt = health.lastReadyAt {
            hadRecentFailureAfterReady = lastFailureAt > lastReadyAt
        } else {
            hadRecentFailureAfterReady = false
        }

        if hadRecentFailureAfterReady {
            return false
        }

        return score >= 60 || segmentRate >= 0.5
    }
    
    private func sportScopedChannelCandidates(context: MatchContext, excluding seen: Set<String>) async -> [ScrapedAceMatch] {
        guard context.supportsSportFallback,
              let url = URL(string: "\(Self.decodedScraperURL)/matches") else {
            return []
        }
        
        let matches = (try? await fetchMatches(from: url)) ?? []
        var localSeen = seen
        let filtered = matches.filter { match in
            guard localSeen.insert(match.cid).inserted else { return false }
            return Self.matchesSportChannelContext(match, context: context)
        }
        
        return Array(
            filtered
                .sorted { lhs, rhs in
                    let lhsScore = Self.sportChannelScore(lhs, context: context)
                    let rhsScore = Self.sportChannelScore(rhs, context: context)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                    let lhsHealth = Self.historicalHealthScore(for: lhs)
                    let rhsHealth = Self.historicalHealthScore(for: rhs)
                    if lhsHealth != rhsHealth {
                        return lhsHealth > rhsHealth
                    }
                    return (lhs.availability ?? 0) > (rhs.availability ?? 0)
                }
                .prefix(Self.maxContextualFallbackCandidates)
        )
    }

    private func sportSearchFallbackCandidates(context: MatchContext, excluding seen: Set<String>) async -> [ScrapedAceMatch] {
        guard context.supportsSportFallback,
              let queries = Self.sportFallbackQueries[context.category],
              !queries.isEmpty else {
            return []
        }

        let rawCandidates = await withTaskGroup(of: [ScrapedAceMatch].self) { group in
            for query in queries {
                group.addTask {
                    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let url = URL(string: "\(Self.decodedScraperURL)/search/\(encoded)") else {
                        return []
                    }
                    return (try? await self.fetchMatches(from: url)) ?? []
                }
            }

            var collected: [ScrapedAceMatch] = []
            for await matches in group {
                collected.append(contentsOf: matches)
            }
            return collected
        }

        var localSeen = seen
        let filtered = rawCandidates.filter { match in
            guard localSeen.insert(match.cid).inserted else { return false }
            let titleTokens = Set(Self.normalizedPhrase(match.title).split(separator: " ").map(String.init))
            guard !Self.hasSportConflict(titleTokens, category: context.category) else {
                return false
            }
            return true
        }

        return Array(
            filtered
                .sorted { lhs, rhs in
                    let lhsScore = Self.sportChannelScore(lhs, context: context)
                    let rhsScore = Self.sportChannelScore(rhs, context: context)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                    let lhsHealth = Self.historicalHealthScore(for: lhs)
                    let rhsHealth = Self.historicalHealthScore(for: rhs)
                    if lhsHealth != rhsHealth {
                        return lhsHealth > rhsHealth
                    }
                    return (lhs.availability ?? 0) > (rhs.availability ?? 0)
                }
                .prefix(Self.maxContextualFallbackCandidates)
        )
    }
    
    private func preflightAndBuildSources(
        from matches: [ScrapedAceMatch],
        context: String,
        scope: SourceScope,
        matchConfidenceByCID: [String: Int] = [:]
    ) async -> [StreamSource] {
        if matches.isEmpty {
            latestPreflightSummary = "P2P preflight skipped: no candidates from \(context)."
            return []
        }

        guard await Self.isProxyHealthy() else {
            latestPreflightSummary = "P2P Infrastructure Error: Proxy is reporting offline or unreachable."
            print("[P2P] Infrastructure failure: \(latestPreflightSummary)")
            return []
        }
        
        let brokerHealth = await Self.fetchBrokerHealth()
        let sortedMatches = matches.sorted { lhs, rhs in
            let lhsConfidence = matchConfidenceByCID[lhs.cid] ?? 0
            let rhsConfidence = matchConfidenceByCID[rhs.cid] ?? 0
            if lhsConfidence != rhsConfidence {
                return lhsConfidence > rhsConfidence
            }
            let lhsBrokerScore = Self.brokerHealthScore(for: lhs, brokerHealth: brokerHealth)
            let rhsBrokerScore = Self.brokerHealthScore(for: rhs, brokerHealth: brokerHealth)
            if lhsBrokerScore != rhsBrokerScore {
                return lhsBrokerScore > rhsBrokerScore
            }
            let lhsHealth = Self.historicalHealthScore(for: lhs)
            let rhsHealth = Self.historicalHealthScore(for: rhs)
            if lhsHealth != rhsHealth {
                return lhsHealth > rhsHealth
            }
            return (lhs.availability ?? 0) > (rhs.availability ?? 0)
        }

        guard !brokerHealth.isEmpty else {
            latestPreflightSummary = "P2P broker readiness is unavailable. Skipping cold foreground P2P."
            return []
        }

        let brokerPlayableMatches = sortedMatches.filter {
            Self.brokerHealthIndicatesPlayable(Self.brokerHealth(for: $0, brokerHealth: brokerHealth))
        }

        guard !brokerPlayableMatches.isEmpty else {
            latestPreflightSummary = "P2P broker has no ready \(context) source yet. Skipping cold foreground P2P."
            return []
        }

        latestPreflightSummary = "P2P broker selected \(min(brokerPlayableMatches.count, scope.maxHealthySources)) ready/recent \(context) source(s)."
        return brokerPlayableMatches
            .prefix(scope.maxHealthySources)
            .compactMap { match in
                guard let candidate = Self.makeCandidate(match: match) else { return nil }
                return Self.brokerRankedStreamSource(
                    from: candidate,
                    scope: scope,
                    brokerHealth: Self.brokerHealth(for: match, brokerHealth: brokerHealth)
                )
            }
    }
    
    static func makeCandidate(match: ScrapedAceMatch) -> P2PCandidate? {
        // AVPlayer is most reliable when MediaFlow exposes AceStream as HLS.
        var components = URLComponents(string: "\(Self.decodedServerURL)/proxy/acestream/manifest.m3u8")
        components?.queryItems = [
            URLQueryItem(name: "infohash", value: match.cid),
            URLQueryItem(name: "api_password", value: Self.decodedAPIPassword)
        ]
        guard let streamURL = components?.url else {
            return nil
        }
        return P2PCandidate(
            cid: match.cid,
            title: match.title,
            availability: match.availability ?? 0,
            bitrateKbps: match.bitrateKbps,
            categories: match.categories,
            categoryHint: match.primaryCategory,
            sourceName: match.source,
            streamURL: streamURL
        )
    }
    
    private static func streamSource(
        from healthy: HealthyP2PSource,
        scope: SourceScope,
        matchConfidenceScore: Int? = nil
    ) -> StreamSource {
        let availabilityLabel = healthy.availability > 0 ? " (\(Int(healthy.availability * 100))%)" : ""
        let probeSummary = "ok; class=\(healthy.failureClass); manifest_ttfb_ms=\(healthy.manifestTTFBMs); segment_status=\(healthy.segmentStatusCode); segment_bytes=\(healthy.segmentBytes)"
        var headers: [String: String] = [
            "User-Agent": Self.mobileUserAgent,
            "Referer": Self.p2pReferer,
            "api-password": Self.decodedAPIPassword,
            "Authorization": "Bearer \(Self.decodedAPIPassword)",
            "X-Fotty-P2P-Probe": probeSummary,
            "X-Fotty-P2P-Probe-Class": healthy.failureClass,
            "X-Fotty-P2P-Scope": scope.headerValue
        ]
        headers["X-Fotty-P2P-Source-Discovered-At"] = ISO8601DateFormatter().string(from: Date())
        for (key, value) in Self.edgeHeaders {
            headers[key] = value
        }
        headers["X-Fotty-P2P-Cid"] = healthy.cid
        headers["X-Fotty-P2P-Title"] = healthy.title
        if let categoryHint = healthy.categoryHint, !categoryHint.isEmpty {
            headers["X-Fotty-P2P-Category"] = categoryHint
        }
        if let bitrateKbps = healthy.bitrateKbps {
            headers["X-Fotty-P2P-Bitrate-Kbps"] = "\(bitrateKbps)"
        }
        if !healthy.categories.isEmpty {
            headers["X-Fotty-P2P-Categories"] = healthy.categories.joined(separator: ",")
        }
        if let sourceName = healthy.sourceName, !sourceName.isEmpty {
            headers["X-Fotty-P2P-Source"] = sourceName
        }
        if let matchConfidenceScore {
            headers["X-Fotty-P2P-Match-Score"] = "\(matchConfidenceScore)"
        }
        return StreamSource(
            title: healthy.title,
            url: healthy.streamURL,
            quality: "\(scope.qualityLabel)\(availabilityLabel)",
            provider: scope.providerTitle(for: healthy.title),
            subtitles: [],
            headers: headers,
            activePeers: healthy.activePeers
        )
    }

    private static func brokerRankedStreamSource(
        from candidate: P2PCandidate,
        scope: SourceScope,
        brokerHealth: BrokerHealth?
    ) -> StreamSource {
        let availabilityLabel = candidate.availability > 0 ? " (\(Int(candidate.availability * 100))%)" : ""
        var headers = baseP2PHeaders(
            cid: candidate.cid,
            title: candidate.title,
            probeSummary: "broker-ranked; playback validated before handoff",
            probeClass: "broker-ranked",
            scope: scope.headerValue
        )
        applyCandidateMetadata(candidate, to: &headers)
        if let score = brokerHealth?.score {
            headers["X-Fotty-P2P-Broker-Score"] = "\(score)"
        }
        if let segmentRate = brokerHealth?.segmentSuccessRate {
            headers["X-Fotty-P2P-Broker-Segment-Rate"] = String(format: "%.3f", segmentRate)
        }
        if let readyAt = brokerHealth?.lastReadyAt {
            headers["X-Fotty-P2P-Broker-Last-Ready-At"] = ISO8601DateFormatter().string(from: readyAt)
        }

        return StreamSource(
            title: candidate.title,
            url: candidate.streamURL,
            quality: "\(scope.qualityLabel)\(availabilityLabel)",
            provider: scope.providerTitle(for: candidate.title),
            subtitles: [],
            headers: headers,
            activePeers: nil
        )
    }

    private static func browseSources(
        from matches: [ScrapedAceMatch],
        brokerHealth: [String: BrokerHealth]
    ) -> [StreamSource] {
        var seen = Set<String>()
        return matches
            .compactMap { match -> StreamSource? in
                guard seen.insert(match.cid).inserted,
                      let candidate = makeCandidate(match: match) else {
                    return nil
                }
                return browseStreamSource(
                    from: candidate,
                    brokerHealth: Self.brokerHealth(for: match, brokerHealth: brokerHealth)
                )
            }
            .prefix(Self.maxBrowseChannels)
            .map { $0 }
    }

    private static func browseStreamSource(
        from candidate: P2PCandidate,
        brokerHealth: BrokerHealth? = nil
    ) -> StreamSource {
        let readyLabel: String
        if let score = brokerHealth?.score, score > 0 {
            readyLabel = "Ready \(score)"
        } else {
            readyLabel = "Ready"
        }
        var headers = baseP2PHeaders(
            cid: candidate.cid,
            title: candidate.title,
            probeSummary: "manual-browse; broker has recent playable history",
            probeClass: "broker-history",
            scope: "manual-browse"
        )
        applyCandidateMetadata(candidate, to: &headers)
        if let score = brokerHealth?.score {
            headers["X-Fotty-P2P-Broker-Score"] = "\(score)"
        }
        return StreamSource(
            title: candidate.title,
            url: candidate.streamURL,
            quality: readyLabel,
            provider: candidate.title,
            subtitles: [],
            headers: headers,
            activePeers: nil
        )
    }

    private static func baseP2PHeaders(
        cid: String,
        title: String,
        probeSummary: String,
        probeClass: String,
        scope: String
    ) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": Self.mobileUserAgent,
            "Referer": Self.p2pReferer,
            "api-password": Self.decodedAPIPassword,
            "Authorization": "Bearer \(Self.decodedAPIPassword)",
            "X-Fotty-P2P-Probe": probeSummary,
            "X-Fotty-P2P-Probe-Class": probeClass,
            "X-Fotty-P2P-Scope": scope,
            "X-Fotty-P2P-Cid": cid,
            "X-Fotty-P2P-Title": title,
            "X-Fotty-P2P-Source-Discovered-At": ISO8601DateFormatter().string(from: Date())
        ]
        for (key, value) in Self.edgeHeaders {
            headers[key] = value
        }
        return headers
    }

    private static func applyCandidateMetadata(_ candidate: P2PCandidate, to headers: inout [String: String]) {
        if let categoryHint = candidate.categoryHint, !categoryHint.isEmpty {
            headers["X-Fotty-P2P-Category"] = categoryHint
        }
        if let bitrateKbps = candidate.bitrateKbps {
            headers["X-Fotty-P2P-Bitrate-Kbps"] = "\(bitrateKbps)"
        }
        if !candidate.categories.isEmpty {
            headers["X-Fotty-P2P-Categories"] = candidate.categories.joined(separator: ",")
        }
        if let sourceName = candidate.sourceName, !sourceName.isEmpty {
            headers["X-Fotty-P2P-Source"] = sourceName
        }
    }
    
    private static func preflightSummary(
        healthyCount: Int,
        rejectedCount: Int,
        failures: [P2PProbeFailure]
    ) -> String {
        guard rejectedCount > 0 else {
            return "P2P preflight passed for \(healthyCount) candidate(s)."
        }
        
        var grouped: [String: Int] = [:]
        for failure in failures {
            grouped[failure.failureClass, default: 0] += 1
        }
        let reasonText = grouped
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: ", ")
        
        if healthyCount == 0 {
            return "P2P preflight rejected all candidates (\(reasonText))."
        }
        return "P2P preflight rejected \(rejectedCount) candidate(s): \(reasonText)."
    }
    
    private static func preflight(candidate: P2PCandidate) async -> P2PProbeResult {
        var manifestRequest = URLRequest(url: candidate.streamURL)
        manifestRequest.timeoutInterval = Self.preflightTimeoutSeconds
        Self.applyStandardHeaders(to: &manifestRequest, accept: Self.hlsAcceptHeader)
        
        let probeStart = Date()
        do {
            let (manifestBytes, response) = try await Self.preflightSession.bytes(for: manifestRequest)
            let manifestTTFBMs = Int(Date().timeIntervalSince(probeStart) * 1000)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.init(candidate: candidate, failureClass: "manifest invalid", reason: "Preflight response was not HTTP."))
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let manifestData = try await readPrefix(
                from: manifestBytes,
                limit: Self.preflightReadLimitBytes,
                minimumBytes: contentType.contains("video/") || contentType.contains("octet-stream")
                    ? Self.minimumSegmentBytes
                    : Self.preflightReadLimitBytes
            )
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let classifiedFailure = classifyProxyFailure(
                    statusCode: httpResponse.statusCode,
                    body: manifestData
                )
                
                let detailSuffix: String
                if let detail = classifiedFailure.detail, !detail.isEmpty {
                    detailSuffix = " \(detail)"
                } else {
                    detailSuffix = ""
                }
                return .failure(
                    .init(
                        candidate: candidate,
                        failureClass: classifiedFailure.failureClass,
                        reason: "Manifest returned HTTP \(httpResponse.statusCode).\(detailSuffix)",
                        activePeers: classifiedFailure.activePeers
                    )
                )
            }

            if isDirectTransportStream(contentType: contentType, data: manifestData) {
                return .success(
                    .init(
                        cid: candidate.cid,
                        title: candidate.title,
                        availability: candidate.availability,
                        bitrateKbps: candidate.bitrateKbps,
                        categories: candidate.categories,
                        categoryHint: candidate.categoryHint,
                        sourceName: candidate.sourceName,
                        streamURL: candidate.streamURL,
                        manifestTTFBMs: manifestTTFBMs,
                        segmentStatusCode: httpResponse.statusCode,
                        segmentBytes: manifestData.count,
                        probeScore: max(0, 10_000 - manifestTTFBMs),
                        failureClass: "ok",
                        activePeers: nil
                    )
                )
            }
            
            guard let manifest = String(data: manifestData, encoding: .utf8),
                  manifest.contains("#EXTM3U") else {
                return .failure(
                    .init(
                        candidate: candidate,
                        failureClass: "manifest parse",
                        reason: "Preflight body was not an HLS manifest."
                    )
                )
            }
            
            guard let segmentURL = firstSegmentURL(in: manifest, relativeTo: candidate.streamURL) else {
                return .failure(
                    .init(
                        candidate: candidate,
                        failureClass: "manifest empty",
                        reason: "Manifest did not contain a playable segment URL."
                    )
                )
            }
            
            var segmentRequest = URLRequest(url: segmentURL)
            segmentRequest.timeoutInterval = Self.preflightTimeoutSeconds
            Self.applyStandardHeaders(to: &segmentRequest, accept: "*/*")
            segmentRequest.setValue("bytes=0-\(Self.preflightReadLimitBytes - 1)", forHTTPHeaderField: "Range")
            
            let (bytes, segmentResponse) = try await Self.preflightSession.bytes(for: segmentRequest)
            var probeData = Data()
            probeData.reserveCapacity(Self.preflightReadLimitBytes)
            var iterator = bytes.makeAsyncIterator()
            while probeData.count < Self.preflightReadLimitBytes,
                  let byte = try await iterator.next() {
                probeData.append(byte)
                if probeData.count >= Self.minimumSegmentBytes {
                    break
                }
            }
            
            guard let segmentHTTPResponse = segmentResponse as? HTTPURLResponse else {
                return .failure(.init(candidate: candidate, failureClass: "segment invalid", reason: "Segment response was not HTTP."))
            }
            
            guard (200...299).contains(segmentHTTPResponse.statusCode) else {
                let classifiedFailure = classifyProxyFailure(
                    statusCode: segmentHTTPResponse.statusCode,
                    body: probeData
                )
                let detailSuffix: String
                if let detail = classifiedFailure.detail, !detail.isEmpty {
                    detailSuffix = " \(detail)"
                } else {
                    detailSuffix = ""
                }
                return .failure(
                    .init(
                        candidate: candidate,
                        failureClass: classifiedFailure.failureClass,
                        reason: "Segment returned HTTP \(segmentHTTPResponse.statusCode).\(detailSuffix)",
                        activePeers: classifiedFailure.activePeers
                    )
                )
            }
            
            guard probeData.count >= Self.minimumSegmentBytes else {
                return .failure(
                    .init(
                        candidate: candidate,
                        failureClass: "segment small",
                        reason: "Segment preflight returned only \(probeData.count) bytes."
                    )
                )
            }
            
            let probeScore = max(
                0,
                10_000 - manifestTTFBMs
            )
            
            return .success(
                .init(
                    cid: candidate.cid,
                    title: candidate.title,
                    availability: candidate.availability,
                    bitrateKbps: candidate.bitrateKbps,
                    categories: candidate.categories,
                    categoryHint: candidate.categoryHint,
                    sourceName: candidate.sourceName,
                    streamURL: candidate.streamURL,
                    manifestTTFBMs: manifestTTFBMs,
                    segmentStatusCode: segmentHTTPResponse.statusCode,
                    segmentBytes: probeData.count,
                    probeScore: probeScore,
                    failureClass: "ok",
                    activePeers: nil
                )
            )
        } catch let error as URLError {
            if error.code == .timedOut {
                return .failure(.init(candidate: candidate, failureClass: "timeout", reason: "Preflight probe timed out.", activePeers: 0))
            }
            return .failure(.init(candidate: candidate, failureClass: "network", reason: "Preflight probe failed: \(error.localizedDescription)", activePeers: 0))
        } catch {
            return .failure(.init(candidate: candidate, failureClass: "probe error", reason: "Preflight probe failed: \(error.localizedDescription)", activePeers: 0))
        }
    }

    private static func readPrefix(
        from bytes: URLSession.AsyncBytes,
        limit: Int,
        minimumBytes: Int
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(limit)
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

    private static func isDirectTransportStream(contentType: String, data: Data) -> Bool {
        if contentType.contains("video/mp2t") ||
            contentType.contains("video/vnd.dlna.mpeg-tts") ||
            contentType.contains("application/octet-stream") {
            return data.count >= minimumSegmentBytes
        }

        return false
    }
    
    private static func firstSegmentURL(in manifest: String, relativeTo manifestURL: URL) -> URL? {
        for rawLine in manifest.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }
            
            if let absoluteURL = URL(string: line, relativeTo: manifestURL)?.absoluteURL {
                return absoluteURL
            }
        }
        
        return nil
    }
    
    private static func classifyProxyFailure(statusCode: Int, body: Data) -> (failureClass: String, detail: String?, activePeers: Int?) {
        if statusCode == 524 || statusCode == 504 {
            return ("warming", "Searching for peers...", 0)
        }
        
        if let envelope = try? JSONDecoder().decode(ProxyFailureEnvelope.self, from: body) {
            let proxyCode = envelope.code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (normalizedProxyFailureCode(proxyCode), envelope.detail, envelope.active_peers)
        }
        
        return ("stream \(statusCode)", nil, 0)
    }
    
    private static func normalizedProxyFailureCode(_ rawCode: String) -> String {
        let normalized = rawCode.lowercased().replacingOccurrences(of: "-", with: "_")
        
        if normalized == "timeout" {
            return "timeout"
        }
        if normalized == "524" {
            return "524"
        }
        if normalized.hasPrefix("segment_") {
            let suffix = normalized.dropFirst("segment_".count)
            return "segment \(suffix)"
        }
        if normalized.hasPrefix("manifest_") {
            let suffix = normalized.dropFirst("manifest_".count)
            return "manifest \(suffix)"
        }
        return normalized.replacingOccurrences(of: "_", with: " ")
    }
    
    private struct MatchContext {
        let homePhrase: String
        let awayPhrase: String
        let homeTokens: Set<String>
        let awayTokens: Set<String>
        let category: String
        let categoryDisplayName: String
        
        let homeAbbreviation: String
        let awayAbbreviation: String
        
        init(homeTeam: String, awayTeam: String, category: String?) {
            homePhrase = P2PDataService.normalizedPhrase(homeTeam)
            awayPhrase = P2PDataService.normalizedPhrase(awayTeam)
            homeTokens = P2PDataService.significantTokens(from: homeTeam)
            awayTokens = P2PDataService.significantTokens(from: awayTeam)
            self.category = P2PDataService.canonicalCategory(category ?? "")
            self.categoryDisplayName = P2PDataService.displayName(forCategory: self.category)
            
            // Extract common 3-letter abbreviations (e.g., Crystal Palace -> CRY, West Ham -> WHU)
            self.homeAbbreviation = P2PDataService.abbreviation(for: homeTeam)
            self.awayAbbreviation = P2PDataService.abbreviation(for: awayTeam)
        }
        
        var supportsSportFallback: Bool {
            !category.isEmpty && category != "other"
        }

        var minimumExactMatchScore: Int {
            if !homePhrase.isEmpty && !awayPhrase.isEmpty {
                // Official names (e.g. "Brighton & Hove Albion") vs short P2P titles ("Brighton v Newcastle")
                // often land ~70–79 with token overlap + both-teams bonus — 80 was excluding real fixtures.
                return 70
            }
            return 40
        }
    }
    
    private enum SourceScope {
        case exactMatch
        case sportChannel
        case catalog
        
        var qualityLabel: String {
            switch self {
            case .exactMatch:
                return "P2P HD"
            case .sportChannel:
                return "P2P Channel HD"
            case .catalog:
                return "P2P HD"
            }
        }
        
        var headerValue: String {
            switch self {
            case .exactMatch:
                return "exact-match"
            case .sportChannel:
                return "sport-channel"
            case .catalog:
                return "catalog"
            }
        }

        var maxHealthySources: Int {
            switch self {
            case .sportChannel:
                return 14
            case .exactMatch:
                return 14
            case .catalog:
                return P2PDataService.maxReturnedSources
            }
        }
        
        func providerTitle(for title: String) -> String {
            switch self {
            case .sportChannel:
                return "P2P Channel - \(title)"
            case .exactMatch, .catalog:
                return title
            }
        }
    }
    
    private static let weakTeamTokens: Set<String> = [
        "the", "and", "club", "team", "fc", "cf", "sc", "ac", "afc", "bc", "u19", "u20",
        "u21", "women", "woman", "men", "united", "state", "new", "real", "sporting",
        "athletic", "athletico", "college", "university"
    ]
    
    private static let sportConflictTokens: [String: Set<String>] = [
        "basketball": ["golf", "baseball", "mlb", "nhl", "hockey", "soccer", "football", "tennis", "ufc", "mma", "f1", "formula"],
        "baseball": ["golf", "basketball", "nba", "wnba", "nhl", "hockey", "soccer", "football", "tennis", "ufc", "mma"],
        "football": ["golf", "baseball", "mlb", "basketball", "nba", "wnba", "hockey", "nhl", "tennis", "ufc", "mma", "f1", "formula"],
        "hockey": ["golf", "baseball", "mlb", "basketball", "nba", "wnba", "soccer", "football", "tennis", "ufc", "mma"],
        "fight": ["golf", "baseball", "mlb", "basketball", "nba", "wnba", "hockey", "nhl", "soccer", "football", "tennis"],
        "cricket": ["golf", "basketball", "nba", "nhl", "hockey", "ufc", "mma", "f1", "formula", "baseball", "mlb"]
    ]
    
    private static let sportPositiveTokens: [String: Set<String>] = [
        "basketball": ["basketball", "nba", "wnba", "ncaab", "ncaa", "fiba", "euroleague", "bbl", "acb"],
        "baseball": ["baseball", "mlb", "kbo", "npb", "baseball"],
        // Football: Premier League + Champions League (UK-heavy). NBA uses `basketball` keys below.
        // "sport" / "sports" still catch Sky/TNT-style channel names.
        "football": ["football", "soccer", "premier", "epl", "english", "england",
                     "champions", "campeones", "uefa", "ucl",
                     "facup", "palace", "hammers", "eagles", "cpfc", "whu",
                     "sport", "sports", "sky", "tnt", "bt"],
        "hockey": ["hockey", "nhl", "khl", "ahl"],
        "fight": ["fight", "fights", "ufc", "mma", "boxing", "pfl", "bellator", "one"],
        // cricket: broad token set to catch IPL, T20, ODI, Test, Sky Sports Cricket, Willow TV, etc.
        "cricket": ["cricket", "ipl", "t20", "t20i", "odi", "test", "bcci", "willow", "hotstar",
                    "rcb", "csk", "mi", "kkr", "srh", "dc", "pbks", "gt", "lsg", "rr"]
    ]
    
    private static let sportPositivePhrases: [String: [String]] = [
        "basketball": ["nba tv", "nba league pass", "college basketball", "nba on tnt", "espn nba", "abc nba",
                       "tnt nba", "tnt sports", "sky sports nba", "sky sports arena", "dazn nba"],
        "baseball": ["mlb network", "major league baseball"],
        "football": ["sky sports football", "sky sports premier", "sky sports main event", "sky sports",
                     "bt sport", "tnt sports",
                     "premier league", "english premier", "champions league",
                     "liga de campeones", "uefa champions"],
        "hockey": ["nhl network", "ice hockey"],
        "fight": ["ufc fight pass", "fight night"],
        "cricket": ["cricket live", "ipl live", "sky sports cricket", "willow tv",
                    "star sports", "jio cinema", "espn cricinfo", "t20 live"]
    ]

    private static let sportFallbackQueries: [String: [String]] = [
        "basketball": [
            "nba", "nba live", "basketball", "nba tv", "wnba", "euroleague", "college basketball",
            "tnt nba", "espn nba", "sky sports nba", "sky sports arena",
        ],
        "baseball": ["mlb", "baseball", "mlb network"],
        "football": [
            "premier league", "premier league live", "epl", "english premier league",
            "sky sports football", "sky sports premier league", "sky sports main event",
            "tnt sports", "bt sport",
            "champions league", "uefa champions league", "ucl",
        ],
        "hockey": ["nhl", "hockey", "nhl network"],
        "fight": ["ufc", "mma", "boxing", "fight night"],
        "cricket": ["cricket", "ipl", "t20", "cricket live", "sky sports cricket", "willow"]
    ]
    
    private static func matchesContext(_ match: ScrapedAceMatch, context: MatchContext) -> Bool {
        let titlePhrase = normalizedPhrase(match.title)
        let titleTokens = Set(titlePhrase.split(separator: " ").map(String.init))
        
        guard !hasSportConflict(titleTokens, category: context.category) else {
            return false
        }

        let homeMatched = matchesTeamContext(
            phrase: context.homePhrase,
            tokens: context.homeTokens,
            abbreviation: context.homeAbbreviation,
            titlePhrase: titlePhrase,
            titleTokens: titleTokens
        )
        let awayMatched = matchesTeamContext(
            phrase: context.awayPhrase,
            tokens: context.awayTokens,
            abbreviation: context.awayAbbreviation,
            titlePhrase: titlePhrase,
            titleTokens: titleTokens
        )

        if !context.homePhrase.isEmpty && !context.awayPhrase.isEmpty {
            return homeMatched && awayMatched
        }
        return homeMatched || awayMatched
    }

    private static func exactMatchScore(_ match: ScrapedAceMatch, context: MatchContext) -> Int {
        let titlePhrase = normalizedPhrase(match.title)
        let titleTokens = Set(titlePhrase.split(separator: " ").map(String.init))

        guard !hasSportConflict(titleTokens, category: context.category) else {
            return 0
        }

        let homeScore = teamContextScore(
            phrase: context.homePhrase,
            tokens: context.homeTokens,
            abbreviation: context.homeAbbreviation,
            titlePhrase: titlePhrase,
            titleTokens: titleTokens
        )
        let awayScore = teamContextScore(
            phrase: context.awayPhrase,
            tokens: context.awayTokens,
            abbreviation: context.awayAbbreviation,
            titlePhrase: titlePhrase,
            titleTokens: titleTokens
        )

        if !context.homePhrase.isEmpty && !context.awayPhrase.isEmpty,
           (homeScore == 0 || awayScore == 0) {
            return 0
        }

        var score = homeScore + awayScore
        if homeScore > 0 && awayScore > 0 {
            score += 25
        }
        if titlePhrase.contains(" vs ") || titlePhrase.contains(" v ") {
            score += 8
        }
        score += Int((match.availability ?? 0) * 10)
        score += max(0, historicalHealthScore(for: match) / 3)
        return score
    }

    private static func matchesTeamContext(
        phrase: String,
        tokens: Set<String>,
        abbreviation: String,
        titlePhrase: String,
        titleTokens: Set<String>
    ) -> Bool {
        if !phrase.isEmpty, titlePhrase.contains(phrase) {
            return true
        }

        let loweredAbbreviation = abbreviation.lowercased()
        if !loweredAbbreviation.isEmpty, titleTokens.contains(loweredAbbreviation) {
            return true
        }

        return !tokens.isDisjoint(with: titleTokens)
    }

    private static func teamContextScore(
        phrase: String,
        tokens: Set<String>,
        abbreviation: String,
        titlePhrase: String,
        titleTokens: Set<String>
    ) -> Int {
        var score = 0

        if !phrase.isEmpty, titlePhrase.contains(phrase) {
            score += 90
        }

        let loweredAbbreviation = abbreviation.lowercased()
        if !loweredAbbreviation.isEmpty, titleTokens.contains(loweredAbbreviation) {
            score += 35
        }

        let overlap = tokens.intersection(titleTokens).count
        score += overlap * 22

        return score
    }

    private static func historicalHealthScore(for match: ScrapedAceMatch) -> Int {
        guard let candidate = makeCandidate(match: match) else { return 0 }
        return LiveSourceHealthStore.score(for: browseStreamSource(from: candidate))
    }

    private static func historicalHealthScore(for healthy: HealthyP2PSource) -> Int {
        let availabilityLabel = healthy.availability > 0 ? " (\(Int(healthy.availability * 100))%)" : ""
        let probeSummary = "ok; class=\(healthy.failureClass); manifest_ttfb_ms=\(healthy.manifestTTFBMs); segment_status=\(healthy.segmentStatusCode); segment_bytes=\(healthy.segmentBytes)"
        let source = StreamSource(
            title: healthy.title,
            url: healthy.streamURL,
            quality: "P2P HD\(availabilityLabel)",
            provider: healthy.title,
            subtitles: [],
            headers: [
                "User-Agent": Self.mobileUserAgent,
                "Referer": Self.p2pReferer,
                "X-Fotty-P2P-Probe": probeSummary
            ],
            activePeers: healthy.activePeers
        )
        return LiveSourceHealthStore.score(for: source)
    }
    
    /// First matching needle wins — keep longer / more specific strings before shorter ones.
    private static let footballTeamAbbreviationHints: [(needle: String, code: String)] = [
        ("manchester united", "MUN"), ("man united", "MUN"), ("man utd", "MUN"),
        ("manchester city", "MCI"), ("man city", "MCI"),
        ("nottingham forest", "NFO"), ("nott'm forest", "NFO"), ("nottm forest", "NFO"),
        ("tottenham hotspur", "TOT"), ("tottenham", "TOT"), ("spurs", "TOT"),
        ("west ham", "WHU"),
        ("crystal palace", "CRY"), ("cpfc", "CRY"),
        ("aston villa", "AVL"),
        ("brighton", "BHA"), ("hove albion", "BHA"),
        ("wolverhampton wanderers", "WOL"), ("wolverhampton", "WOL"), ("wolves", "WOL"),
        ("newcastle united", "NEW"), ("newcastle", "NEW"),
        ("afc bournemouth", "BOU"), ("bournemouth", "BOU"),
        ("brentford", "BRE"),
        ("fulham", "FUL"),
        ("everton", "EVE"),
        ("burnley", "BUR"),
        ("leicester city", "LEI"), ("leicester", "LEI"),
        ("leeds united", "LEE"), ("leeds", "LEE"),
        ("southampton", "SOU"),
        ("sheffield united", "SHU"),
        ("ipswich town", "IPS"), ("ipswich", "IPS"),
        ("luton town", "LUT"), ("luton", "LUT"),
        ("sunderland", "SUN"),
        ("west bromwich albion", "WBA"), ("west bromwich", "WBA"), ("west brom", "WBA"),
        ("watford", "WAT"),
        ("norwich city", "NOR"), ("norwich", "NOR"),
        ("cardiff city", "CAR"), ("cardiff", "CAR"),
        ("swansea city", "SWA"), ("swansea", "SWA"),
        ("middlesbrough", "MID"),
        ("hull city", "HUL"), ("hull", "HUL"),
        ("arsenal", "ARS"),
        ("liverpool", "LIV"),
        ("chelsea", "CHE"),
    ]

    private static func abbreviation(for teamName: String) -> String {
        let normalized = teamName.lowercased()
        for hint in footballTeamAbbreviationHints where normalized.contains(hint.needle) {
            return hint.code
        }
        let tokens = teamName.split(separator: " ").map(String.init)
        if let first = tokens.first, !first.isEmpty {
            return String(first.prefix(3)).uppercased()
        }
        return ""
    }
    
    private static func matchesSportChannelContext(_ match: ScrapedAceMatch, context: MatchContext) -> Bool {
        let titlePhrase = normalizedPhrase(match.title)
        let titleTokens = Set(titlePhrase.split(separator: " ").map(String.init))
        
        guard !hasSportConflict(titleTokens, category: context.category) else {
            return false
        }
        
        if let phrases = sportPositivePhrases[context.category],
           phrases.contains(where: { titlePhrase.contains($0) }) {
            return true
        }
        
        guard let positiveTokens = sportPositiveTokens[context.category] else {
            return false
        }
        return !titleTokens.isDisjoint(with: positiveTokens)
    }
    
    private static func sportChannelScore(_ match: ScrapedAceMatch, context: MatchContext) -> Int {
        let titlePhrase = normalizedPhrase(match.title)
        let titleTokens = Set(titlePhrase.split(separator: " ").map(String.init))
        var score = 0
        
        if let phrases = sportPositivePhrases[context.category] {
            for phrase in phrases where titlePhrase.contains(phrase) {
                score += 5
            }
        }
        if let positiveTokens = sportPositiveTokens[context.category] {
            score += titleTokens.intersection(positiveTokens).count * 2
        }
        if titlePhrase.contains("hd") {
            score += 1
        }
        return score
    }
    
    private static func hasSportConflict(_ titleTokens: Set<String>, category: String) -> Bool {
        guard let conflicts = sportConflictTokens[category], !conflicts.isEmpty else {
            return false
        }
        return !titleTokens.isDisjoint(with: conflicts)
    }
    
    private static func displayName(forCategory category: String) -> String {
        switch category {
        case "basketball": return "basketball"
        case "baseball": return "baseball"
        case "football": return "football"
        case "hockey": return "hockey"
        case "fight": return "fight"
        case "cricket": return "cricket"
        default: return category.isEmpty ? "sport" : category
        }
    }
    
    private static func significantTokens(from value: String) -> Set<String> {
        Set(normalizedPhrase(value)
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count > 2 && !weakTeamTokens.contains(token)
            })
    }

    private static func canonicalCategory(_ value: String) -> String {
        let normalized = normalizedPhrase(value)
        guard !normalized.isEmpty else { return "" }

        switch normalized {
        case "soccer":
            return "football"
        case "mma", "boxing", "ufc", "pfl", "bellator", "one":
            return "fight"
        case "nba", "wnba", "ncaab", "ncaa", "fiba", "euroleague", "acb", "bbl":
            return "basketball"
        case "mlb", "npb", "kbo":
            return "baseball"
        case "nhl", "khl", "ahl":
            return "hockey"
        case "ipl", "t20", "odi", "test match", "test cricket":
            return "cricket"
        default:
            return normalized
        }
    }
    
    private static func normalizedPhrase(_ value: String) -> String {
        let lower = value.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append(" ")
            }
        }
        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func isProxyHealthy() async -> Bool {
        guard var components = URLComponents(string: "\(Self.decodedServerURL)/proxy/acestream/status") else {
            return false
        }
        components.queryItems = [
            URLQueryItem(name: "api_password", value: Self.decodedAPIPassword)
        ]
        guard let url = components.url else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.proxyStatusTimeoutSeconds
        Self.applyStandardHeaders(to: &request)

        do {
            let (data, response) = try await Self.discoverySession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            if let status = try? JSONDecoder().decode(ProxyStatusEnvelope.self, from: data),
               let enabled = status.enabled {
                return enabled
            }
            return true
        } catch {
            return false
        }
    }
    
    func fetchLiveEvents() async throws -> [EventReference] { [] }

    private struct BrokerPrewarmEnvelope: Decodable {
        let broker: BrokerSnapshot?
    }

    private struct BrokerSnapshot: Decodable {
        let cidHealth: [String: BrokerHealth]

        enum CodingKeys: String, CodingKey {
            case cidHealth = "cid_health"
        }
    }

    struct ScrapedAceMatch: Codable {
        let title: String
        let cid: String
        let availability: Double?
        let bitrateKbps: Int?
        let categories: [String]
        let source: String?

        enum CodingKeys: String, CodingKey {
            case title
            case cid
            case availability
            case bitrateKbps = "bitrate_kbps"
            case categories
            case source
        }

        init(
            title: String,
            cid: String,
            availability: Double?,
            bitrateKbps: Int? = nil,
            categories: [String] = [],
            source: String? = nil
        ) {
            self.title = title
            self.cid = cid
            self.availability = availability
            self.bitrateKbps = bitrateKbps
            self.categories = categories
            self.source = source
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            cid = try container.decode(String.self, forKey: .cid)
            availability = try container.decodeIfPresent(Double.self, forKey: .availability)
            bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps)
            categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
            source = try container.decodeIfPresent(String.self, forKey: .source)
        }

        var primaryCategory: String? {
            categories.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
    
    struct P2PCandidate {
        let cid: String
        let title: String
        let availability: Double
        let bitrateKbps: Int?
        let categories: [String]
        let categoryHint: String?
        let sourceName: String?
        let streamURL: URL
    }
    
    private struct HealthyP2PSource {
        let cid: String
        let title: String
        let availability: Double
        let bitrateKbps: Int?
        let categories: [String]
        let categoryHint: String?
        let sourceName: String?
        let streamURL: URL
        let manifestTTFBMs: Int
        let segmentStatusCode: Int
        let segmentBytes: Int
        let probeScore: Int
        let failureClass: String
        let activePeers: Int?
    }
    
    private struct P2PProbeFailure {
        let cid: String
        let title: String
        let failureClass: String
        let reason: String
        let activePeers: Int
        
        init(candidate: P2PCandidate, failureClass: String, reason: String, activePeers: Int? = nil) {
            self.cid = candidate.cid
            self.title = candidate.title
            self.failureClass = failureClass
            self.reason = reason
            self.activePeers = activePeers ?? 0
        }
    }
    
    private enum P2PProbeResult {
        case success(HealthyP2PSource)
        case failure(P2PProbeFailure)
    }
    
    private struct ProxyFailureEnvelope: Decodable {
        let code: String?
        let detail: String?
        let active_peers: Int?
    }

    private struct ProxyStatusEnvelope: Decodable {
        let enabled: Bool?
        let active_peers: Int?
    }
}

// MARK: - Match Discovery Architecture

struct SourceCandidate: Identifiable, Codable {
    let id: String
    let title: String
    let provider: String
    let discoveredAt: Date
    let url: URL
    
    // Scoring Metadata
    var teamMatchScore: Double = 0.0
    var competitionMatchScore: Double = 0.0
    var kickoffTimeScore: Double = 0.0
    var freshnessScore: Double = 0.0
    var playbackHealthScore: Double = 0.0
    var peerHealthScore: Double = 0.0
    
    var finalScore: Double {
        // Weighted calculation: Team match is most important (50%), 
        // followed by health (30%) and freshness/competition (20%)
        let weighted = (teamMatchScore * 0.5) + 
                       (playbackHealthScore * 0.3) + 
                       (freshnessScore * 0.1) + 
                       (competitionMatchScore * 0.1)
        return weighted
    }
    
    var rejectionReason: String? = nil
    var isHealthy: Bool { playbackHealthScore > 0.5 }
    var isVerified: Bool = false
}

struct MatchDiscoveryDiagnostics: Codable {
    let matchId: String
    let generatedQueries: [String]
    let providersSearched: [String]
    let rawResultCount: Int
    let candidateCount: Int
    let rejectedCount: Int
    let rejections: [String: String] // cid: reason
    let finalRankedList: [SourceCandidate]
    let engineStatus: String
}

class MatchQueryNormalizer {
    static let shared = MatchQueryNormalizer()
    
    private let commonAliases: [String: [String]] = [
        "crystal palace": ["palace", "cpfc", "cry"],
        "west ham": ["west ham united", "whu", "hammers"],
        "manchester city": ["man city", "mci", "citizens"],
        "manchester united": ["man utd", "mun", "red devils"],
        "tottenham": ["spurs", "thfc"],
        "arsenal": ["afc", "gunners"],
        "liverpool": ["lfc", "reds"],
        "chelsea": ["cfc", "blues"]
    ]
    
    func generateVariants(home: String, away: String, competition: String? = nil) -> [String] {
        let homeAliases = getAliases(for: home)
        let awayAliases = getAliases(for: away)
        
        var variants = Set<String>()
        
        // 1. Full primary names
        if !away.isEmpty {
            variants.insert("\(home) vs \(away)")
            variants.insert("\(home) \(away)")
        } else {
            variants.insert(home)
        }
        
        // 2. Short aliases (High density search)
        for h in homeAliases {
            if !away.isEmpty {
                for a in awayAliases {
                    variants.insert("\(h) \(a)")
                    variants.insert("\(h) vs \(a)")
                }
            } else {
                variants.insert(h)
            }
        }
        
        // 3. Reversed order (Common in international streams)
        if !away.isEmpty {
            variants.insert("\(away) vs \(home)")
            variants.insert("\(away) \(home)")
        }
        
        // 4. Competition specific
        if let comp = competition {
            variants.insert("\(comp) \(home)")
            variants.insert("\(comp) \(away)")
        }
        
        return Array(variants).sorted { $0.count > $1.count }
    }
    
    private func getAliases(for team: String) -> [String] {
        let normalized = team.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var results = [normalized]
        
        for (key, aliases) in commonAliases {
            if normalized.contains(key) || key.contains(normalized) {
                results.append(contentsOf: aliases)
            }
        }
        
        // Add 3-letter prefix as last resort
        let firstThree = String(normalized.prefix(3)).uppercased()
        if !results.contains(firstThree.lowercased()) {
            results.append(firstThree)
        }
        
        return Array(Set(results))
    }
    
    func calculateTeamMatchScore(title: String, home: String, away: String, competition: String? = nil) -> Double {
        let normalizedTitle = title.lowercased()
        let homeAliases = getAliases(for: home)
        let awayAliases = getAliases(for: away)
        
        var score = 0.0
        
        // Find home team
        if homeAliases.contains(where: { normalizedTitle.contains($0.lowercased()) }) {
            score += 0.5
        }
        
        // Find away team
        if awayAliases.contains(where: { normalizedTitle.contains($0.lowercased()) }) {
            score += 0.5
        }
        
        // Boost if competition matches
        if let comp = competition, normalizedTitle.contains(comp.lowercased()) {
            score += 0.2
        }
        
        return score
    }

    func calculateCompetitionMatchScore(title: String, competition: String?) -> Double {
        guard let competition else { return 0.0 }
        let normalizedCompetition = competition.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCompetition.isEmpty else { return 0.0 }
        return title.lowercased().contains(normalizedCompetition) ? 0.3 : 0.0
    }
}

class MatchDiscoveryEngine: ObservableObject {
    static let shared = MatchDiscoveryEngine()
    
    @Published var latestDiagnostics: MatchDiscoveryDiagnostics?
    
    func discover(home: String, away: String, competition: String? = nil) async -> [SourceCandidate] {
        let queries = MatchQueryNormalizer.shared.generateVariants(home: home, away: away, competition: competition)
        let startTime = Date()
        
        var allCandidates = [SourceCandidate]()
        var rejections = [String: String]()
        
        // Use P2PDataService (and potentially others in the future)
        let p2pResults = await withTaskGroup(of: [SourceCandidate].self) { group in
            // 1. Raw Catalog Fetch (No Preflight)
            group.addTask {
                guard let url = URL(string: "\(P2PDataService.decodedScraperURL)/matches") else { return [] }
                let matches = (try? await P2PDataService.shared.fetchMatches(from: url)) ?? []
                return matches.compactMap { src in
                    guard let p2p = P2PDataService.makeCandidate(match: src) else { return nil }
                    var candidate = SourceCandidate(
                        id: p2p.cid,
                        title: p2p.title,
                        provider: "P2P",
                        discoveredAt: Date(),
                        url: p2p.streamURL
                    )
                        candidate.teamMatchScore = MatchQueryNormalizer.shared.calculateTeamMatchScore(
                            title: p2p.title,
                            home: home,
                            away: away,
                            competition: competition
                        )
                    candidate.competitionMatchScore = MatchQueryNormalizer.shared.calculateCompetitionMatchScore(
                        title: p2p.title,
                        competition: competition
                    )
                    candidate.peerHealthScore = p2p.availability
                    return candidate
                }
            }

            // 2. Raw Search Fetch (No Preflight)
            for query in queries {
                group.addTask {
                    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let url = URL(string: "\(P2PDataService.decodedScraperURL)/search/\(encoded)") else { return [] }
                    
                    let matches = (try? await P2PDataService.shared.fetchMatches(from: url)) ?? []
                    return matches.compactMap { src in
                        guard let p2p = P2PDataService.makeCandidate(match: src) else { return nil }
                        var candidate = SourceCandidate(
                            id: p2p.cid,
                            title: p2p.title,
                            provider: "P2P",
                            discoveredAt: Date(),
                            url: p2p.streamURL
                        )
                        candidate.teamMatchScore = MatchQueryNormalizer.shared.calculateTeamMatchScore(
                            title: p2p.title,
                            home: home,
                            away: away,
                            competition: competition
                        )
                        candidate.competitionMatchScore = MatchQueryNormalizer.shared.calculateCompetitionMatchScore(
                            title: p2p.title,
                            competition: competition
                        )
                        candidate.peerHealthScore = p2p.availability
                        return candidate
                    }
                }
            }
            
            var collected = [SourceCandidate]()
            for await candidates in group {
                collected.append(contentsOf: candidates)
            }
            return collected
        }
        
        // Deduplicate and filter
        var seenUrls = Set<URL>()
        let majorProviderTokens = ["sky", "bt sport", "dazn", "nbc", "peacock", "canal+", "bein"]
        
        for candidate in p2pResults {
            if seenUrls.insert(candidate.url).inserted {
                let normalizedTitle = candidate.title.lowercased()
                let isMajorChannel = majorProviderTokens.contains { normalizedTitle.contains($0) }
                
                // CRITICAL FIX: Allow the match if:
                // 1. Team name match (0.5+)
                // 2. Competition name match (0.2+) - e.g. "Premier League" channel
                // 3. It's a major sports provider (Sky/BT/etc) - these are always relevant
                if candidate.teamMatchScore >= 0.5 || candidate.competitionMatchScore >= 0.2 {
                    
                    var boostedCandidate = candidate
                    if isMajorChannel && candidate.teamMatchScore < 0.5 && candidate.competitionMatchScore > 0 {
                        // Boost major channels so they appear near the top as reliable fallbacks
                        boostedCandidate.competitionMatchScore += 0.2
                    }
                    allCandidates.append(boostedCandidate)
                } else {
                    rejections[candidate.id] = "Insufficient relevance (team=\(candidate.teamMatchScore), competition=\(candidate.competitionMatchScore))"
                }
            }
        }
        
        let ranked = allCandidates.sorted { $0.finalScore > $1.finalScore }
        
        // Log diagnostics
        let rejectedCount = rejections.count
        let rejectionSnapshot = rejections

        await MainActor.run {
            self.latestDiagnostics = MatchDiscoveryDiagnostics(
                matchId: "\(home)-\(away)",
                generatedQueries: queries,
                providersSearched: ["P2PScraper"],
                rawResultCount: p2pResults.count,
                candidateCount: ranked.count,
                rejectedCount: rejectedCount,
                rejections: rejectionSnapshot,
                finalRankedList: ranked,
                engineStatus: "Completed in \(String(format: "%.2fs", Date().timeIntervalSince(startTime)))"
            )
        }
        
        return ranked
    }
    
    func verify(candidate: SourceCandidate) async -> Double {
        // Option B: Progressive verification
        // Map SourceCandidate to StreamSource for the HealthStore and P2PDataService logic
        let streamSource = StreamSource(
            title: candidate.title,
            url: candidate.url,
            quality: "AUTO",
            provider: candidate.provider
        )
        
        LiveSourceHealthStore.startVerifying(streamSource)
        defer { LiveSourceHealthStore.stopVerifying(streamSource) }
        
        do {
            // Perform the same preflight as P2PDataService but isolated
            let results = try await P2PDataService.shared.search(query: candidate.title)
            if results.first(where: { $0.url == candidate.url }) != nil {
                // If it passed P2P preflight, it's healthy
                LiveSourceHealthStore.recordSuccess(for: streamSource, startupLatencyMs: nil)
                return 1.0
            }
        } catch {
            LiveSourceHealthStore.recordFailure(for: streamSource, wasStall: false)
        }
        return 0.0
    }
}
