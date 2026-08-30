import Foundation
import os

enum FottyQualityCategory: String, Codable, CaseIterable {
    case playback
    case footballData = "football_data"
    case fpl
    case coach
    case matchIdentity = "match_identity"
}

enum FottyQualityOutcome: String, Codable {
    case info
    case success
    case recovered
    case failure
}

struct FottyQualityRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let category: FottyQualityCategory
    let name: String
    let outcome: FottyQualityOutcome
    let durationMilliseconds: Int?
    let details: [String: String]
    let appVersion: String
    let appBuild: String
}

struct FottyQualitySummary: Codable, Equatable {
    let recordCount: Int
    let playbackAttempts: Int
    let provenPlaybackStarts: Int
    let recoveredPlaybackEvents: Int
    let automaticFailovers: Int
    let terminalPlaybackFailures: Int
    let nativeHandoffs: Int
    let medianStartupMilliseconds: Int?
    let footballDataRefreshFailures: Int
    let matchIdentityConflicts: Int
    let fplRefreshFailures: Int
    let coachModelRequests: Int

    static let empty = FottyQualitySummary(
        recordCount: 0,
        playbackAttempts: 0,
        provenPlaybackStarts: 0,
        recoveredPlaybackEvents: 0,
        automaticFailovers: 0,
        terminalPlaybackFailures: 0,
        nativeHandoffs: 0,
        medianStartupMilliseconds: nil,
        footballDataRefreshFailures: 0,
        matchIdentityConflicts: 0,
        fplRefreshFailures: 0,
        coachModelRequests: 0
    )
}

/// Privacy-safe, on-device evidence for Fotty's release gates.
///
/// Records are bounded and deliberately reject URLs, credentials, free-form
/// errors, fixture names, manager IDs, and prompt text. Recording never causes
/// network traffic and can be cleared or exported by the user.
final class FottyQualityStore {
    static let shared = FottyQualityStore()

    private static let allowedDetailKeys: Set<String> = [
        "mode", "failure_kind", "recovery_kind", "feed", "source",
        "model", "route", "result", "reason_code", "token_count"
    ]
    private static let retentionInterval: TimeInterval = 14 * 24 * 60 * 60
    private static let maximumRecords = 250

    private let defaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "fotty.quality.records.v1",
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.now = now
    }

    func record(
        category: FottyQualityCategory,
        name: String,
        outcome: FottyQualityOutcome,
        durationMilliseconds: Int? = nil,
        details: [String: String] = [:]
    ) {
        let safeName = Self.safeToken(name, maximumLength: 48) ?? "unknown"
        let safeDetails = details.reduce(into: [String: String]()) { result, entry in
            guard Self.allowedDetailKeys.contains(entry.key),
                  let value = Self.safeToken(entry.value, maximumLength: 64) else { return }
            result[entry.key] = value
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let record = FottyQualityRecord(
            id: UUID(),
            timestamp: now(),
            category: category,
            name: safeName,
            outcome: outcome,
            durationMilliseconds: durationMilliseconds.map { max(0, min($0, 3_600_000)) },
            details: safeDetails,
            appVersion: version,
            appBuild: build
        )

        lock.lock()
        defer { lock.unlock() }
        var values = decodedRecordsLocked()
        values.append(record)
        persistLocked(Self.pruned(values, now: record.timestamp))
    }

    func records() -> [FottyQualityRecord] {
        lock.lock()
        defer { lock.unlock() }
        let values = Self.pruned(decodedRecordsLocked(), now: now())
        persistLocked(values)
        return values
    }

    func summary() -> FottyQualitySummary {
        Self.summarize(records())
    }

    static func summarize(_ records: [FottyQualityRecord]) -> FottyQualitySummary {
        let startupSamples = records
            .filter { $0.category == .playback && $0.name == "decoded_progress" }
            .compactMap(\.durationMilliseconds)
            .sorted()
        let median: Int?
        if startupSamples.isEmpty {
            median = nil
        } else {
            median = startupSamples[(startupSamples.count - 1) / 2]
        }
        return FottyQualitySummary(
            recordCount: records.count,
            playbackAttempts: records.count { $0.category == .playback && $0.name == "attempt_started" },
            provenPlaybackStarts: records.count { $0.category == .playback && $0.name == "decoded_progress" },
            recoveredPlaybackEvents: records.count { $0.category == .playback && $0.outcome == .recovered },
            automaticFailovers: records.count { $0.category == .playback && $0.name == "automatic_failover" },
            terminalPlaybackFailures: records.count { $0.category == .playback && $0.name == "terminal_failure" },
            nativeHandoffs: records.count { $0.category == .playback && $0.name == "native_handoff" && $0.outcome == .success },
            medianStartupMilliseconds: median,
            footballDataRefreshFailures: records.count { $0.category == .footballData && $0.outcome == .failure },
            matchIdentityConflicts: records.count { $0.category == .matchIdentity && $0.outcome == .failure },
            fplRefreshFailures: records.count { $0.category == .fpl && $0.name == "refresh" && $0.outcome == .failure },
            coachModelRequests: records.count { $0.category == .coach && $0.name == "model_request" }
        )
    }

    func exportJSON() -> String {
        let retainedRecords = records()
        let payload = ExportPayload(
            generatedAt: now(),
            privacyNotice: "On-device quality events only. No fixture names, manager identifiers, URLs, credentials, or prompt text are recorded.",
            summary: Self.summarize(retainedRecords),
            records: retainedRecords
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Unable to encode diagnostics\"}"
        }
        return text
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }

    private struct ExportPayload: Codable {
        let generatedAt: Date
        let privacyNotice: String
        let summary: FottyQualitySummary
        let records: [FottyQualityRecord]
    }

    private func decodedRecordsLocked() -> [FottyQualityRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([FottyQualityRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func persistLocked(_ records: [FottyQualityRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func pruned(_ records: [FottyQualityRecord], now: Date) -> [FottyQualityRecord] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return Array(records.filter { $0.timestamp >= cutoff }.suffix(maximumRecords))
    }

    private static func safeToken(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("://"),
              !trimmed.lowercased().contains("authorization"),
              !trimmed.lowercased().contains("token"),
              !trimmed.lowercased().contains("api_key"),
              trimmed.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics
                      .union(CharacterSet(charactersIn: "-_ ."))
                      .contains($0)
              }) else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}

/// Extension point for future remote analytics backends
protocol FottyAnalyticsProvider {
    func logEvent(name: String, parameters: [String: Any]?)
    func logError(_ error: Error, message: String?)
}

/// Lightweight singleton for unified logging and event tracking
class FottyLogger {
    static let shared = FottyLogger()
    
    private let logger = Logger(subsystem: "com.jelani.Fotty", category: "App")
    private var providers: [FottyAnalyticsProvider] = []
    
    // In-memory queue for session logs to be exported
    private(set) var sessionLogs: [String] = []
    private let maxLogs = 500
    
    private init() {
        log(.appLaunch, message: "Fotty initialized")
    }
    
    enum LogEvent: String {
        case appLaunch = "app_launch"
        case streamStart = "stream_start"
        case streamEnd = "stream_end"
        case authLogin = "auth_login"
        case authLogout = "auth_logout"
        case error = "error_caught"
        case navigate = "navigate"
        case featureUsage = "feature_usage"
    }
    
    func addProvider(_ provider: FottyAnalyticsProvider) {
        providers.append(provider)
    }
    
    func log(_ event: LogEvent, message: String? = nil, params: [String: Any]? = nil) {
        let timestamp = Date().formatted(.iso8601)
        let logEntry = "[\(timestamp)] [\(event.rawValue)] \(message ?? "")"
        
        // Console logging
        logger.info("\(logEntry, privacy: .public)")
        
        // In-memory capture for Export
        sessionLogs.append(logEntry)
        if sessionLogs.count > maxLogs {
            sessionLogs.removeFirst()
        }
        
        // Forward to analytics hooks
        for provider in providers {
            provider.logEvent(name: event.rawValue, parameters: params)
        }
    }
    
    func error(_ error: Error, message: String? = nil) {
        let timestamp = Date().formatted(.iso8601)
        let logEntry = "[\(timestamp)] [ERROR] \(message ?? ""): \(error.localizedDescription)"
        
        logger.error("\(logEntry, privacy: .public)")
        
        sessionLogs.append(logEntry)
        
        for provider in providers {
            provider.logError(error, message: message)
        }
    }
    
    func exportLogs() -> String {
        return sessionLogs.joined(separator: "\n")
    }

    /// Category-scoped log for M4 migration off `print`.
    func info(category: String, _ message: String) {
        let entry = "[\(category)] \(message)"
        logger.info("\(entry, privacy: .public)")
        sessionLogs.append("[\(Date().formatted(.iso8601))] \(entry)")
        if sessionLogs.count > maxLogs { sessionLogs.removeFirst() }
    }
}
