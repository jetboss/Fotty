import Foundation

// MARK: - Shared Media Models

enum CatalogBroadcastTiming: String, Sendable {
    case live = "LIVE"
    case upcoming = "UPCOMING"
    case available = "AVAILABLE"

    var actionLabel: String {
        self == .live ? "Watch live" : "Open broadcast"
    }
}

extension AnalyticalDataEngine.EventReference {
    var displayTitle: String {
        if isBroadcastChannel { return title ?? "Cricket channel" }
        let home = homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = awayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !home.isEmpty, !away.isEmpty,
           (home != "Home" || teams?.home?.name != nil),
           (away != "Away" || teams?.away?.name != nil) { return "\(home) vs \(away)" }
        return title ?? "Match"
    }

    /// A channel has no kickoff or final whistle. Do not infer a channel's
    /// programme from its name, or classify every undated fixture as a channel.
    nonisolated var isBroadcastChannel: Bool {
        guard (category ?? "").lowercased() == "cricket" else { return false }
        let name = (title ?? "").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return ["willow", "willowtv", "willowcricket", "willowhd", "willow2", "foxcricket", "foxcrickethd"].contains(name)
    }

    nonisolated var isCPLFixture: Bool {
        guard (category ?? "").lowercased() == "cricket", !isBroadcastChannel else { return false }
        let text = [title, teams?.home?.name, teams?.away?.name].compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("caribbean premier league") || text.range(of: #"\bcpl\b"#, options: .regularExpression) != nil {
            return true
        }
        // Require two distinct franchises: an isolated team name can appear in
        // a news/highlight title or another tournament and is not a fixture.
        return CPLTeam.allCases.filter { $0.matches(in: text) }.count >= 2
    }

    /// Discovery estimates, not official match status. Unknown cricket formats
    /// (especially multi-day Tests) must never inherit football's two-hour end.
    nonisolated var estimatedMatchDuration: TimeInterval? {
        guard !isBroadcastChannel else { return nil }
        switch (category ?? "").lowercased() {
        case "football", "soccer": return 2 * 3600
        case "cricket":
            let name = (title ?? "").lowercased()
            if isCPLFixture || name.range(of: #"\b(t20|t20i|twenty20)\b"#, options: .regularExpression) != nil {
                return 6 * 3600
            }
            return nil
        default: return nil
        }
    }

    nonisolated func isPastEstimatedMatchWindow(at now: Date = .init()) -> Bool {
        guard let kickoff = kickoffDate, let duration = estimatedMatchDuration else { return false }
        return now >= kickoff.addingTimeInterval(duration)
    }

    nonisolated func broadcastTiming(at now: Date = .init()) -> CatalogBroadcastTiming {
        guard !isBroadcastChannel, let kickoff = kickoffDate else { return .available }
        if kickoff > now { return .upcoming }
        if id.hasPrefix("cpl-2026-"), sources?.isEmpty != false { return .available }
        // Preserve the existing four-hour broadcast window for other sports,
        // without declaring them finished when their actual format is unknown.
        let duration = estimatedMatchDuration ?? ((category ?? "").lowercased() == "cricket" ? 0 : 4 * 3600)
        return now.timeIntervalSince(kickoff) < duration ? .live : .available
    }
}

struct StreamSource: Identifiable, Sendable {
    let id: UUID
    let title: String?
    let url: URL
    let quality: String
    let provider: String
    let subtitles: [Subtitle]
    let headers: [String: String]
    let activePeers: Int?
    let cookie: String?
    let referer: String?
    let priority: Int
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        url: URL,
        quality: String,
        provider: String,
        subtitles: [Subtitle] = [],
        headers: [String: String] = [:],
        activePeers: Int? = nil,
        cookie: String? = nil,
        referer: String? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.quality = quality
        self.provider = provider
        self.subtitles = subtitles
        self.headers = headers
        self.activePeers = activePeers
        self.cookie = cookie
        self.referer = referer
        self.priority = priority
    }

    /// Returns a copy with additional HTTP headers merged in (later keys win on collision).
    func mergingHeaders(_ extra: [String: String]) -> StreamSource {
        var merged = headers
        for (k, v) in extra {
            merged[k] = v
        }
        return StreamSource(
            id: id,
            title: title,
            url: url,
            quality: quality,
            provider: provider,
            subtitles: subtitles,
            headers: merged,
            activePeers: activePeers,
            cookie: cookie,
            referer: referer,
            priority: priority
        )
    }

    struct Subtitle: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let language: String
        let label: String
    }
}

enum StreamType: String, Codable, Sendable {
    case hls
    case mp4
    case p2pProxyHLS = "p2p_proxy_hls"
    case p2pProxyMP4 = "p2p_proxy_mp4"
    case unknown
}

enum StreamValidationStatus: String, Codable, Sendable {
    case pending
    case validated
    case failed
}

enum StreamLoadState: String, Codable, Sendable {
    case idle
    case resolving
    case warmingUpP2P = "warming_up_p2p"
    case validating
    case fallingBack = "falling_back"
    case readyToPlay = "ready_to_play"
    case playing
    case refreshing
    case failed
    case cancelled
}

enum StreamFailureCategory: String, Codable, Sendable {
    case noProviderAvailable = "no_provider_available"
    case providerTimeout = "provider_timeout"
    case providerReturnedEmpty = "provider_returned_empty"
    case invalidMatchMapping = "invalid_match_mapping"
    case invalidURL = "invalid_url"
    case unsupportedScheme = "unsupported_scheme"
    case rawP2PIDReturned = "raw_p2p_id_returned"
    case manifestUnreachable = "manifest_unreachable"
    case manifestInvalid = "manifest_invalid"
    case segmentUnreachable = "segment_unreachable"
    case authFailed = "auth_failed"
    case leaseExpired = "lease_expired"
    case p2pWarmupFailed = "p2p_warmup_failed"
    case p2pProxyUnreachable = "p2p_proxy_unreachable"
    case p2pProxyNotReady = "p2p_proxy_not_ready"
    case playerFailed = "player_failed"
    case navigationCancelled = "navigation_cancelled"
    case duplicateRequestCancelled = "duplicate_request_cancelled"
    case userCancelled = "user_cancelled"
    case networkChanged = "network_changed"
    case backgroundedDuringResolution = "backgrounded_during_resolution"
    case unknown
}

struct StreamFailure: Error, Identifiable, Codable, Sendable {
    let id: UUID
    let providerName: String?
    let category: StreamFailureCategory
    let technicalMessage: String
    let userMessage: String
    let retryable: Bool
    let fallbackAllowed: Bool
    let redactedMetadata: [String: String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        providerName: String? = nil,
        category: StreamFailureCategory,
        technicalMessage: String,
        userMessage: String,
        retryable: Bool,
        fallbackAllowed: Bool,
        redactedMetadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.category = category
        self.technicalMessage = technicalMessage
        self.userMessage = userMessage
        self.retryable = retryable
        self.fallbackAllowed = fallbackAllowed
        self.redactedMetadata = redactedMetadata
        self.timestamp = timestamp
    }
}

struct StreamSession: Identifiable, Codable, Sendable {
    let id: UUID
    let matchID: String
    let title: String?
    let playableURL: URL
    let streamType: StreamType
    let providerName: String
    let requiredHeaders: [String: String]
    let qualityLabel: String?
    let expiryTime: Date?
    let leaseID: String?
    let canRefresh: Bool
    let validationStatus: StreamValidationStatus
    let diagnosticMetadata: [String: String]
    let createdAt: Date
    let lastRefreshAt: Date?
    let activePeers: Int?

    init(
        id: UUID = UUID(),
        matchID: String,
        title: String? = nil,
        playableURL: URL,
        streamType: StreamType,
        providerName: String,
        requiredHeaders: [String: String] = [:],
        qualityLabel: String? = nil,
        expiryTime: Date? = nil,
        leaseID: String? = nil,
        canRefresh: Bool = false,
        validationStatus: StreamValidationStatus = .validated,
        diagnosticMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        lastRefreshAt: Date? = nil,
        activePeers: Int? = nil
    ) {
        self.id = id
        self.matchID = matchID
        self.title = title
        self.playableURL = playableURL
        self.streamType = streamType
        self.providerName = providerName
        self.requiredHeaders = requiredHeaders
        self.qualityLabel = qualityLabel
        self.expiryTime = expiryTime
        self.leaseID = leaseID
        self.canRefresh = canRefresh
        self.validationStatus = validationStatus
        self.diagnosticMetadata = diagnosticMetadata
        self.createdAt = createdAt
        self.lastRefreshAt = lastRefreshAt
        self.activePeers = activePeers
    }

    var isP2PProxy: Bool {
        streamType == .p2pProxyHLS || streamType == .p2pProxyMP4
    }

    var requiresLocalProxy: Bool {
        isP2PProxy || !requiredHeaders.isEmpty
    }

    var legacySource: StreamSource {
        StreamSource(
            id: id,
            title: title,
            url: playableURL,
            quality: qualityLabel ?? "auto",
            provider: providerName,
            subtitles: [],
            headers: requiredHeaders,
            activePeers: activePeers,
            cookie: nil,
            referer: diagnosticMetadata["referer"]
        )
    }
}

enum StreamEventName: String, Codable, Sendable {
    case userTappedMatch = "user_tapped_match"
    case streamAttemptCreated = "stream_attempt_created"
    case streamResolutionStarted = "stream_resolution_started"
    case provider1Started = "provider_1_started"
    case provider1Resolved = "provider_1_resolved"
    case provider1ValidationStarted = "provider_1_validation_started"
    case provider1ValidationSucceeded = "provider_1_validation_succeeded"
    case provider1ValidationFailed = "provider_1_validation_failed"
    case provider2Started = "provider_2_started"
    case provider2Resolved = "provider_2_resolved"
    case provider2ValidationStarted = "provider_2_validation_started"
    case provider2ValidationSucceeded = "provider_2_validation_succeeded"
    case provider2ValidationFailed = "provider_2_validation_failed"
    case p2pWarmupStarted = "p2p_warmup_started"
    case p2pWarmupSucceeded = "p2p_warmup_succeeded"
    case p2pWarmupFailed = "p2p_warmup_failed"
    case fallbackStarted = "fallback_started"
    case fallbackSucceeded = "fallback_succeeded"
    case fallbackFailed = "fallback_failed"
    case readyToPlay = "ready_to_play"
    case playerNavigationStarted = "player_navigation_started"
    case avplayerAssetCreated = "avplayer_asset_created"
    case avplayerItemCreated = "avplayer_item_created"
    case playbackStarted = "playback_started"
    case playbackFailed = "playback_failed"
    case streamRefreshStarted = "stream_refresh_started"
    case streamRefreshSucceeded = "stream_refresh_succeeded"
    case streamRefreshFailed = "stream_refresh_failed"
    case streamCleanupStarted = "stream_cleanup_started"
    case streamCleanupCompleted = "stream_cleanup_completed"
    case streamAttemptCancelled = "stream_attempt_cancelled"
}

struct StreamEventRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let name: StreamEventName
    let timestamp: Date
    let matchID: String
    let matchTitle: String
    let providerName: String?
    let attemptID: String
    let taskID: String?
    let sessionID: String?
    let currentState: StreamLoadState
    let failureCategory: StreamFailureCategory?
    let redactedMetadata: [String: String]

    init(
        id: UUID = UUID(),
        name: StreamEventName,
        timestamp: Date = Date(),
        matchID: String,
        matchTitle: String,
        providerName: String? = nil,
        attemptID: String,
        taskID: String? = nil,
        sessionID: String? = nil,
        currentState: StreamLoadState,
        failureCategory: StreamFailureCategory? = nil,
        redactedMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.matchID = matchID
        self.matchTitle = matchTitle
        self.providerName = providerName
        self.attemptID = attemptID
        self.taskID = taskID
        self.sessionID = sessionID
        self.currentState = currentState
        self.failureCategory = failureCategory
        self.redactedMetadata = redactedMetadata
    }
}

struct StreamProviderAttemptLog: Identifiable, Codable, Sendable {
    let id: UUID
    let providerName: String
    let responseTimeMs: Int
    let resolvedStreamType: StreamType
    let urlShape: String
    let requiredHeaders: Bool
    let validationResult: String
    let manifestResult: String?
    let segmentResult: String?
    let playerStartupResult: String?
    let finalFailureCategory: StreamFailureCategory?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        providerName: String,
        responseTimeMs: Int,
        resolvedStreamType: StreamType,
        urlShape: String,
        requiredHeaders: Bool,
        validationResult: String,
        manifestResult: String? = nil,
        segmentResult: String? = nil,
        playerStartupResult: String? = nil,
        finalFailureCategory: StreamFailureCategory? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.responseTimeMs = responseTimeMs
        self.resolvedStreamType = resolvedStreamType
        self.urlShape = urlShape
        self.requiredHeaders = requiredHeaders
        self.validationResult = validationResult
        self.manifestResult = manifestResult
        self.segmentResult = segmentResult
        self.playerStartupResult = playerStartupResult
        self.finalFailureCategory = finalFailureCategory
        self.timestamp = timestamp
    }
}

struct StreamAttemptDiagnostics: Identifiable, Codable, Sendable {
    let attemptID: String
    let matchID: String
    let matchTitle: String
    let finalState: StreamLoadState
    let createdAt: Date
    let completedAt: Date
    let timeline: [StreamEventRecord]
    let providerAttempts: [StreamProviderAttemptLog]

    var id: String { attemptID }
}

struct StreamPlaybackRequest: Identifiable, Sendable {
    let matchID: String
    let displayTitle: String
    let homeTeam: String
    let awayTeam: String
    let category: String
    let kickoffDate: Date?
    let preferredEvent: AnalyticalDataEngine.EventReference?

    var id: String { matchID }

    init(
        matchID: String,
        displayTitle: String,
        homeTeam: String,
        awayTeam: String,
        category: String,
        kickoffDate: Date? = nil,
        preferredEvent: AnalyticalDataEngine.EventReference? = nil
    ) {
        self.matchID = matchID
        self.displayTitle = displayTitle
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.category = category
        self.kickoffDate = kickoffDate
        self.preferredEvent = preferredEvent
    }

    @MainActor
    init(event: AnalyticalDataEngine.EventReference) {
        self.init(
            matchID: event.id,
            displayTitle: event.title ?? "\(event.homeName) vs \(event.awayName)",
            homeTeam: event.homeName,
            awayTeam: event.awayName,
            category: event.normalizedCategory,
            kickoffDate: event.kickoffDate,
            preferredEvent: event
        )
    }
}

enum CatalogRouteIdentity {
    nonisolated static func matches(eventID: String, requestedID: String) -> Bool {
        let eventCandidates = candidates(from: eventID)
        let requestCandidates = candidates(from: requestedID)
        return !eventCandidates.isDisjoint(with: requestCandidates)
    }

    private nonisolated static func candidates(from rawValue: String) -> Set<String> {
        let trimmed = (rawValue.removingPercentEncoding ?? rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return [] }

        var values: Set<String> = [trimmed]
        if let separator = trimmed.firstIndex(of: ":") {
            let suffix = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty {
                values.insert(suffix)
            }
        }
        return values
    }
}

struct StreamResolutionSuccess: Sendable {
    let attemptID: String
    let sessions: [StreamSession]
    let diagnostics: StreamAttemptDiagnostics

    var primarySession: StreamSession? {
        sessions.first
    }
}

enum StreamResolutionOutcome: Sendable {
    case success(StreamResolutionSuccess)
    case failure(StreamFailure, StreamAttemptDiagnostics)
}

struct StreamAttemptProgress: Sendable {
    let attemptID: String
    let state: StreamLoadState
    let userMessage: String
    let technicalMessage: String?
    let providerName: String?
}

#if DEBUG
actor StreamDebugStore {
    static let shared = StreamDebugStore()

    private var latestByMatchID: [String: StreamAttemptDiagnostics] = [:]

    func record(_ diagnostics: StreamAttemptDiagnostics) {
        latestByMatchID[diagnostics.matchID] = diagnostics
    }

    func latest(matchID: String) -> StreamAttemptDiagnostics? {
        latestByMatchID[matchID]
    }
}
#endif

enum ProcessorError: Error {
    case invalidURL
    case httpError
    case invalidData
    case noSourcesFound
    case timeout
    case proxyError
}

extension ProcessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The stream URL is invalid."
        case .httpError:
            return "The stream server returned an error."
        case .invalidData:
            return "The stream data could not be read."
        case .noSourcesFound:
            return "No playable stream sources were found."
        case .timeout:
            return "The stream request timed out."
        case .proxyError:
            return "The local stream proxy failed to start."
        }
    }
}

// MARK: - Event Data Structures

struct NexusATeams: Codable {
    let home: NexusATeam?
    let away: NexusATeam?
}

struct NexusATeam: Codable {
    let name: String?
    let badge: String?
}

struct NexusASource: Codable {
    let source: String    // "delta", "echo", "golf", "admin"
    let id: String        // event-specific ID
}
