import Foundation

/// Codable Swift model for the MediaFlow status endpoint.
struct MediaFlowStatus: Codable, Equatable, Sendable {
    let sessionId: String?
    let sourceId: String?
    let state: String // e.g. "idle", "starting", "warming", "buffering", "ready"
    let message: String?
    let peerCount: Int
    let downloadSpeedKbps: Double
    let uploadSpeedKbps: Double
    let bufferSeconds: Double
    let firstSegmentReady: Bool
    let readySegmentCount: Int
    let estimatedStartupSeconds: Double?
    let manifestTTFBMs: Int?
    let brokerHealth: BrokerHealth?
    let manifestURL: String?
    let firstSegmentURL: String?
    let lastError: String?
    let expiresAt: Date?
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sourceId = "source_id"
        case state
        case message
        case peerCount = "peer_count"
        case downloadSpeedKbps = "download_speed_kbps"
        case uploadSpeedKbps = "upload_speed_kbps"
        case bufferSeconds = "buffer_seconds"
        case firstSegmentReady = "first_segment_ready"
        case readySegmentCount = "ready_segment_count"
        case estimatedStartupSeconds = "estimated_startup_seconds"
        case manifestTTFBMs = "manifest_ttfb_ms"
        case brokerHealth = "broker_health"
        case manifestURL = "manifest_url"
        case firstSegmentURL = "first_segment_url"
        case lastError = "last_error"
        case expiresAt = "expires_at"
        case updatedAt = "updated_at"
    }

    private enum AlternateKeys: String, CodingKey {
        case status
        case message
        case peerCount
        case downloadSpeedKbps
        case uploadSpeedKbps
        case bufferSeconds
        case firstSegmentReady
        case readySegmentCount
        case estimatedStartupSeconds
        case manifestTTFBMs
        case brokerHealth
        case manifestURL
        case firstSegmentURL
        case error
        case expiresAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alternateContainer = try decoder.container(keyedBy: AlternateKeys.self)

        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        state = try container.decodeIfPresent(String.self, forKey: .state)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .status)
            ?? "idle"
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .message)
        peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
            ?? alternateContainer.decodeIfPresent(Int.self, forKey: .peerCount)
            ?? 0
        downloadSpeedKbps = try container.decodeIfPresent(Double.self, forKey: .downloadSpeedKbps)
            ?? alternateContainer.decodeIfPresent(Double.self, forKey: .downloadSpeedKbps)
            ?? 0
        uploadSpeedKbps = try container.decodeIfPresent(Double.self, forKey: .uploadSpeedKbps)
            ?? alternateContainer.decodeIfPresent(Double.self, forKey: .uploadSpeedKbps)
            ?? 0
        bufferSeconds = try container.decodeIfPresent(Double.self, forKey: .bufferSeconds)
            ?? alternateContainer.decodeIfPresent(Double.self, forKey: .bufferSeconds)
            ?? 0
        firstSegmentReady = try container.decodeIfPresent(Bool.self, forKey: .firstSegmentReady)
            ?? alternateContainer.decodeIfPresent(Bool.self, forKey: .firstSegmentReady)
            ?? false
        readySegmentCount = try container.decodeIfPresent(Int.self, forKey: .readySegmentCount)
            ?? alternateContainer.decodeIfPresent(Int.self, forKey: .readySegmentCount)
            ?? 0
        estimatedStartupSeconds = try container.decodeIfPresent(Double.self, forKey: .estimatedStartupSeconds)
            ?? alternateContainer.decodeIfPresent(Double.self, forKey: .estimatedStartupSeconds)
        manifestTTFBMs = try container.decodeIfPresent(Int.self, forKey: .manifestTTFBMs)
            ?? alternateContainer.decodeIfPresent(Int.self, forKey: .manifestTTFBMs)
        brokerHealth = try container.decodeIfPresent(BrokerHealth.self, forKey: .brokerHealth)
            ?? alternateContainer.decodeIfPresent(BrokerHealth.self, forKey: .brokerHealth)
        manifestURL = try container.decodeIfPresent(String.self, forKey: .manifestURL)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .manifestURL)
        firstSegmentURL = try container.decodeIfPresent(String.self, forKey: .firstSegmentURL)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .firstSegmentURL)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .error)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? alternateContainer.decodeIfPresent(Date.self, forKey: .expiresAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? alternateContainer.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(sourceId, forKey: .sourceId)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(peerCount, forKey: .peerCount)
        try container.encode(downloadSpeedKbps, forKey: .downloadSpeedKbps)
        try container.encode(uploadSpeedKbps, forKey: .uploadSpeedKbps)
        try container.encode(bufferSeconds, forKey: .bufferSeconds)
        try container.encode(firstSegmentReady, forKey: .firstSegmentReady)
        try container.encode(readySegmentCount, forKey: .readySegmentCount)
        try container.encodeIfPresent(estimatedStartupSeconds, forKey: .estimatedStartupSeconds)
        try container.encodeIfPresent(manifestTTFBMs, forKey: .manifestTTFBMs)
        try container.encodeIfPresent(brokerHealth, forKey: .brokerHealth)
        try container.encodeIfPresent(manifestURL, forKey: .manifestURL)
        try container.encodeIfPresent(firstSegmentURL, forKey: .firstSegmentURL)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct BrokerHealth: Codable, Equatable, Sendable {
    let score: Int?
    let successCount: Int?
    let failureCount: Int?
    let staleFailureCount: Int?
    let segmentSuccessRate: Double?
    let lastReadyTTFBMs: Int?
    let bestReadyTTFBMs: Int?
    let lastReadyAt: Date?
    let lastFailureCode: String?
    let lastFailureAt: Date?

    enum CodingKeys: String, CodingKey {
        case score
        case successCount = "success_count"
        case failureCount = "failure_count"
        case staleFailureCount = "stale_failure_count"
        case segmentSuccessRate = "segment_success_rate"
        case lastReadyTTFBMs = "last_ready_ttfb_ms"
        case bestReadyTTFBMs = "best_ready_ttfb_ms"
        case lastReadyAt = "last_ready_at"
        case lastFailureCode = "last_failure_code"
        case lastFailureAt = "last_failure_at"
    }
}

struct P2PBrokerSessionEnvelope: Codable, Equatable, Sendable {
    let sessionId: String
    let sourceId: String?
    let state: String
    let message: String?
    let manifestURL: String
    let statusURL: String
    let eventsURL: String?
    let expiresAt: Date?
    let updatedAt: Date?
    let eventCount: Int?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sourceId = "source_id"
        case state
        case message
        case manifestURL = "manifest_url"
        case statusURL = "status_url"
        case eventsURL = "events_url"
        case expiresAt = "expires_at"
        case updatedAt = "updated_at"
        case eventCount = "event_count"
    }
}

/// Comprehensive report for post-warmup analysis.
struct PlaybackWarmupDiagnosticReport: Codable, Sendable {
    let sourceId: String
    let sourceTitle: String
    let manifestURL: URL
    let sessionId: String?
    let warmupStartedAt: Date
    let warmupEndedAt: Date
    let totalWarmupSeconds: TimeInterval
    let peerCountTimeline: [Int]
    let downloadSpeedTimeline: [Double]
    let bufferSecondsTimeline: [Double]
    let firstSegmentReadyAt: Date?
    let readySegmentCountTimeline: [Int]
    let firstSegmentProbeResult: String?
    let authValidationResult: String
    let finalWarmupState: String
    let failureReason: String?
    let recommendedFix: String?
}

/// Configuration for the PlaybackReadinessEvaluator.
struct PlaybackReadinessConfig: Sendable {
    let minimumBufferSeconds: Double
    let minimumReadySegments: Int
    let minimumPeerCount: Int
    let minimumDownloadSpeedKbps: Double
    let warmupTimeoutSeconds: TimeInterval
    let pollingIntervalSeconds: TimeInterval
    
    static let `default` = PlaybackReadinessConfig(
        minimumBufferSeconds: 2.0,
        minimumReadySegments: 1,
        minimumPeerCount: 1,
        minimumDownloadSpeedKbps: 250.0,
        warmupTimeoutSeconds: 90.0,
        pollingIntervalSeconds: 2.0
    )
}
