import Foundation
import os
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// UserDefaults may synchronously deliver a did-change observer on another
/// operation queue. Never hold a diagnostics store's lock during that delivery.
/// One caller drains outside all store locks; reentrant writes only update the
/// latest pending value and return. The overlay also keeps a reentrant read
/// from replacing newer cached state with an older, still-in-flight receipt.
private final class FottyDefaultsWriteBuffer {
    private enum Value {
        case set(Any)
        case remove
    }
    private struct Pending {
        let revision: UInt64
        let value: Value
    }
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var desired: [String: Pending] = [:]
    private var pendingKeys: [String] = []
    private var isDraining = false

    init(defaults: UserDefaults) { self.defaults = defaults }

    func object(forKey key: String) -> Any? {
        lock.lock()
        let pending = desired[key]
        lock.unlock()
        if let pending {
            switch pending.value {
            case .set(let value): return value
            case .remove: return nil
            }
        }
        return defaults.object(forKey: key)
    }

    func set(_ value: Any, forKey key: String) { enqueue(.set(value), forKey: key) }
    func removeObject(forKey key: String) { enqueue(.remove, forKey: key) }

    private func enqueue(_ value: Value, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        revision &+= 1
        desired[key] = Pending(revision: revision, value: value)
        if !pendingKeys.contains(key) { pendingKeys.append(key) }
    }

    /// Called only after the owning diagnostics lock has been released.
    func drain() {
        lock.lock()
        guard !isDraining else { lock.unlock(); return }
        isDraining = true
        while !pendingKeys.isEmpty {
            let key = pendingKeys.removeFirst()
            guard let pending = desired[key] else { continue }
            lock.unlock()
            switch pending.value {
            case .set(let value): defaults.set(value, forKey: key)
            case .remove: defaults.removeObject(forKey: key)
            }
            lock.lock()
            if desired[key]?.revision == pending.revision { desired.removeValue(forKey: key) }
        }
        isDraining = false
        lock.unlock()
    }
}

/// Only scalar summaries of Apple's reports, never raw payloads or call stacks.
/// Measurement windows/build attribution prevent yesterday's data being labelled
/// as the currently installed release. Missing data is not a zero-hang result.
struct FottyPerformanceSample: Codable, Equatable {
    let windowStart: Date
    let windowEnd: Date
    let receivedAt: Date
    let reportedBuild: String?
    let includesMultipleVersions: Bool
    let scrollHitchRatio: Double?
    let hangCount: Int?
    let longestHangSeconds: Double?
}

struct FottyPerformanceSummary: Codable, Equatable {
    let availability: String
    let scroll: FottyPerformanceSample?
    let hangs: FottyPerformanceSample?
}

final class FottyPerformanceStore {
    static let shared = FottyPerformanceStore()
    private let defaults: UserDefaults
    private let now: () -> Date
    private let lock: NSLock
    private let writes: FottyDefaultsWriteBuffer
    private static let prefix = "fotty.performance.summary.v1."
    private static let retention: TimeInterval = 14 * 24 * 60 * 60
    private static let legacyKeys = ["metricDate", "scrollHitchRatio", "hangDate", "hangCount", "longestHangSeconds"]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         lock: NSLock = NSLock()) {
        self.defaults = defaults
        self.now = now
        self.lock = lock
        self.writes = FottyDefaultsWriteBuffer(defaults: defaults)
    }

    func record(windowStart: Date, windowEnd: Date, reportedBuild: String?,
                includesMultipleVersions: Bool, scrollHitchRatio: Double? = nil,
                hangCount: Int? = nil, longestHangSeconds: Double? = nil) {
        let sample = FottyPerformanceSample(
            windowStart: windowStart, windowEnd: windowEnd, receivedAt: now(),
            reportedBuild: Self.safeBuild(reportedBuild), includesMultipleVersions: includesMultipleVersions,
            scrollHitchRatio: scrollHitchRatio, hangCount: hangCount, longestHangSeconds: longestHangSeconds
        )
        lock.lock()
        defer { lock.unlock(); writes.drain() }
        guard valid(sample, at: sample.receivedAt) else { return }
        let kind = scrollHitchRatio == nil ? "hangs" : "scroll"
        if let previous = read(kind, at: sample.receivedAt), previous.windowEnd > windowEnd { return }
        guard let data = try? JSONEncoder().encode(sample) else { return }
        writes.set(data, forKey: Self.prefix + kind)
    }

    func summary() -> FottyPerformanceSummary {
        lock.lock()
        defer { lock.unlock(); writes.drain() }
        // Old unscoped scalars cannot be attributed safely to a release/window.
        removeLegacy()
        let time = now()
        let scroll = read("scroll", at: time)
        let hangs = read("hangs", at: time)
        return .init(availability: scroll == nil && hangs == nil ? "not_available" : "available",
                     scroll: scroll, hangs: hangs)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock(); writes.drain() }
        writes.removeObject(forKey: Self.prefix + "scroll")
        writes.removeObject(forKey: Self.prefix + "hangs")
        writes.set(now(), forKey: Self.prefix + "clearedAt")
        removeLegacy()
    }

    private func removeLegacy() {
        for key in Self.legacyKeys {
            let legacyKey = "fotty.performance." + key
            if writes.object(forKey: legacyKey) != nil { writes.removeObject(forKey: legacyKey) }
        }
    }

    private func read(_ kind: String, at time: Date) -> FottyPerformanceSample? {
        let key = Self.prefix + kind
        guard let data = writes.object(forKey: key) as? Data else { return nil }
        guard data.count <= 2_048,
              let sample = try? JSONDecoder().decode(FottyPerformanceSample.self, from: data),
              valid(sample, at: time),
              (kind == "scroll") == (sample.scrollHitchRatio != nil) else {
            writes.removeObject(forKey: key)
            return nil
        }
        return sample
    }

    private func valid(_ sample: FottyPerformanceSample, at time: Date) -> Bool {
        let dates = [sample.windowStart, sample.windowEnd, sample.receivedAt, time]
        guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              sample.windowStart <= sample.windowEnd, sample.windowEnd <= sample.receivedAt,
              sample.receivedAt <= time, time.timeIntervalSince(sample.windowStart) <= Self.retention,
              sample.windowEnd.timeIntervalSince(sample.windowStart) <= 48 * 60 * 60,
              sample.reportedBuild == Self.safeBuild(sample.reportedBuild) else { return false }
        if let cutoff = writes.object(forKey: Self.prefix + "clearedAt") as? Date,
           sample.windowStart < cutoff { return false }
        if let ratio = sample.scrollHitchRatio {
            // Preserve Apple's dimensionless value; do not present it as a percentage.
            return ratio.isFinite && (0...1_000).contains(ratio)
                && sample.hangCount == nil && sample.longestHangSeconds == nil
        }
        guard let count = sample.hangCount, let duration = sample.longestHangSeconds else { return false }
        return (1...100_000).contains(count) && duration.isFinite && (0...86_400).contains(duration)
    }

    private static func safeBuild(_ value: String?) -> String? {
        guard let value, value.range(of: #"^[0-9]{1,10}(\.[0-9]{1,10}){0,3}$"#,
                                    options: .regularExpression) != nil else { return nil }
        return value
    }
}

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

/// Builds the small, privacy-safe playback context shared by the normal player
/// and Watch Two. The quality store applies a second allowlist before anything
/// is retained, but keeping construction here prevents the two playback paths
/// from drifting or accidentally adding a fixture name or URL.
/// A watch/panel owns this value. Reloads get new attempts, not new sessions.
/// This is diagnostic bookkeeping only; it never drives recovery or admission.
struct FottyPlaybackCorrelation {
    let sessionID: UUID

    init(sessionID: UUID = UUID()) { self.sessionID = sessionID }
    private(set) var attemptNumber = 0
    private(set) var attemptID: UUID?
    private(set) var previousAttemptID: UUID?

    mutating func beginAttempt(_ id: UUID) {
        guard id != attemptID else { return }
        previousAttemptID = attemptID
        attemptID = id
        attemptNumber += 1
    }

    var details: [String: String] {
        var result = ["watch_session_id": sessionID.uuidString,
                      "attempt_number": String(attemptNumber)]
        if let previousAttemptID { result["previous_attempt_id"] = previousAttemptID.uuidString }
        return result
    }
}

enum FottyPlaybackStage: String, CaseIterable {
    case preparing, documentLoaded = "document_loaded", mediaObserved = "media_observed"
    case mediaReady = "media_ready", decoded, buffering
    case documentFailure = "document_failure", mediaFailure = "media_failure"
    case processTerminated = "process_terminated"
}

/// Local causal evidence only. These values never grant playback permission or
/// classify an observed provider pause as a user/system action.
enum FottyPlaybackDiagnosticPhase: String, Equatable, Sendable {
    case candidateObserved = "candidate_observed", candidateFinished = "candidate_finished"
    case audioPreparationRequested = "audio_preparation_requested", audioPreparationFinished = "audio_preparation_finished"
    case audioActivationRequested = "audio_activation_requested", audioActivationFinished = "audio_activation_finished"
    case audioIsolationRequested = "audio_isolation_requested", audioIsolationFinished = "audio_isolation_finished"
    case webTransport = "web_transport", webRetired = "web_retired"
}

enum FottyPlaybackDiagnosticPurpose: String, Equatable, Sendable {
    case nativeStart = "native_start", nativeResume = "native_resume", nativeHandoff = "native_handoff"
    case pictureInPicture = "picture_in_picture", webPlayback = "web_playback", platformActivation = "platform_activation"
    case nativeDisconnect = "native_disconnect", nativeReconnect = "native_reconnect"
}

enum FottyPlaybackDiagnosticResult: String, Equatable, Sendable {
    case began, completed, cancelled, playing, paused, adopted, retired
    case completedWithErrors = "completed_with_errors", validationRejected = "validation_rejected"
    case preparationFailed = "preparation_failed", readinessTimeout = "readiness_timeout", decodedTimeout = "decoded_timeout"
    case ownershipChanged = "ownership_changed", backgrounded, pictureInPicture = "picture_in_picture", intentRevoked = "intent_revoked"
}

enum FottyPlaybackDiagnosticHandoffPhase: String, Equatable, Sendable {
    case none, validation, preparingURL = "preparing_url", readiness, audioPreparation = "audio_preparation"
    case decoding, awaitingWebRetirement = "awaiting_web_retirement"
}

enum FottyPlaybackDiagnosticRoute: String { case single, watchTwo = "watch_two" }

/// A bounded, attempt-bound admission gate for passive diagnostic records.
/// Repeated transport states are not new edges. Callers must reject stale
/// callbacks before admitting them, so an old identity cannot reset the budget.
struct FottyPlaybackDiagnosticBudget {
    struct Identity: Equatable { let sourceID: UUID; let requestID: UUID }
    static let maximumRecordsPerAttempt = 32
    private(set) var identity: Identity?
    private(set) var emittedCount = 0
    private var lastTransport: FottyPlaybackDiagnosticResult?
    private var keys: Set<String> = []

    mutating func admit(identity: Identity, phase: FottyPlaybackDiagnosticPhase,
                        purpose: FottyPlaybackDiagnosticPurpose, result: FottyPlaybackDiagnosticResult,
                        operationID: UUID) -> Bool {
        if self.identity != identity {
            self.identity = identity; emittedCount = 0; lastTransport = nil; keys.removeAll(keepingCapacity: true)
        }
        guard emittedCount < Self.maximumRecordsPerAttempt else { return false }
        if phase == .webTransport, lastTransport == result { return false }
        let key = "\(operationID.uuidString)|\(phase.rawValue)|\(purpose.rawValue)|\(result.rawValue)"
        guard keys.insert(key).inserted else { return false }
        if phase == .webTransport { lastTransport = result }
        emittedCount += 1
        return true
    }
}

enum FottyPlaybackQualityDetails {
    @MainActor static var deviceFamily: String {
        #if targetEnvironment(macCatalyst)
        return "catalyst"
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        return "other"
        #endif
    }

    /// Endpoint-specific, not a broadcaster/match identity. Signed URL rotation
    /// changes this key; identical URLs with different headers can share it.
    /// Source UUIDs still distinguish those choices within the local session.
    /// No URL, query value, cookie or header is retained in the record.
    static func variantKey(for source: StreamSource) -> String? {
        guard ["https", "http"].contains(source.url.scheme?.lowercased() ?? ""),
              source.url.user == nil, source.url.password == nil,
              source.url.absoluteString.utf8.count <= 16_384 else { return nil }
        let digest = SHA256.hash(data: Data(source.url.absoluteString.utf8))
        return "variant_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func make(
        source: StreamSource?,
        mode: String,
        route: String,
        attemptID: UUID,
        sourceKey: String? = nil,
        correlation: FottyPlaybackCorrelation? = nil,
        deviceFamily: String = "unknown",
        additional: [String: String] = [:]
    ) -> [String: String] {
        guard let source else { return additional }
        var details = additional.merging([
            "mode": mode,
            "route": route,
            "source_family": LiveSourceHealthStore.providerFamily(for: source),
            "source": source.provider,
            "attempt_id": attemptID.uuidString,
            "source_id": source.id.uuidString,
            "device_family": deviceFamily
        ]) { _, value in value }
        // VersionString is localized/free-form; retain only the numeric version.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        details["os_version"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if let key = variantKey(for: source) { details["variant_key"] = key }
        if let correlation, correlation.attemptID == attemptID {
            details.merge(correlation.details) { _, authoritative in authoritative }
        }
        if let sourceKey,
           sourceKey.range(of: #"^(?:cs|ps|ls|fs|sv)_[a-f0-9]{24}$"#, options: .regularExpression) != nil {
            details["source_key"] = sourceKey
        }
        return details
    }
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
    let sustainedNativeAttempts: Int
    let recoveredPlaybackEvents: Int
    let automaticFailovers: Int
    let terminalPlaybackFailures: Int
    let resolutionFailures: Int
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
        sustainedNativeAttempts: 0,
        recoveredPlaybackEvents: 0,
        automaticFailovers: 0,
        terminalPlaybackFailures: 0,
        resolutionFailures: 0,
        nativeHandoffs: 0,
        medianStartupMilliseconds: nil,
        footballDataRefreshFailures: 0,
        matchIdentityConflicts: 0,
        fplRefreshFailures: 0,
        coachModelRequests: 0
    )
}

/// Build-scoped, privacy-safe evidence for the hidden owner status view.
/// Retained records may span app updates, so current and older builds must never
/// be combined into one apparently healthy release summary.
struct FottyOwnerStatusSnapshot: Equatable {
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let currentBuildSummary: FottyQualitySummary
    let retainedRecordCount: Int
    let olderBuildRecordCount: Int
    let firstCurrentBuildRecordAt: Date?
    let lastCurrentBuildRecordAt: Date?
    let performance: FottyPerformanceSummary

    var hasCurrentBuildEvidence: Bool { currentBuildSummary.recordCount > 0 }
}

/// Privacy-safe, on-device evidence for Fotty's release gates.
///
/// Records are bounded and deliberately reject URLs, credentials, free-form
/// errors, fixture names, manager IDs, and prompt text. Recording never causes
/// network traffic and can be cleared or exported by the user.
final class FottyQualityStore {
    static let shared = FottyQualityStore(performanceStore: .shared)

    private static let allowedDetailKeys: Set<String> = [
        "mode", "failure_kind", "recovery_kind", "feed", "source",
        "model", "route", "result", "reason_code", "token_count",
        "source_family", "source_key", "attempt_id", "watch_session_id",
        "previous_attempt_id", "attempt_number", "source_id", "variant_key",
        "device_family", "os_version", "source_index", "source_count",
        "selection_version", "selection_stage", "selection_applied", "baseline_slots", "candidate_slots",
        "selection_reason", "candidate_families", "duplicate_choices", "independence_evidence",
        "last_observed_stage", "stage", "platform_error_code",
        "cs_stream_entry_count", "cs_admission_rejected_count",
        "addon_stream_entry_count", "addon_admission_rejected_count",
        "native_presentation_id", "native_presentation_event", "native_pip_active", "native_app_backgrounded",
        "native_failure_trigger", "native_error_domain", "native_error_code",
        "native_underlying_domain", "native_underlying_code", "native_error_depth",
        "native_resume_action", "native_resume_elapsed_ms", "native_resume_window",
        "native_startup_elapsed_ms", "native_startup_deadline_ms", "native_item_status", "native_time_control",
        "native_wait_reason", "native_buffer_empty", "native_buffer_full", "native_likely_to_keep_up",
        "native_log_domain", "native_log_code", "native_hls_issue", "native_log_hls_issue", "relay_failure_stage",
        "native_continuity_elapsed_ms", "native_continuity_media_advance_ms", "native_continuity_stalls",
        "live_event_delay_evidence", "media_clock_evidence", "advertised_media_age_ms",
        "assignment_basis", "programme_observation", "upstream_independence_evidence",
        "native_presentation_width", "native_presentation_height", "native_access_event_count",
        "native_access_observed_bitrate", "native_access_indicated_bitrate", "native_access_stalls",
        "native_access_dropped_frames", "native_access_bytes", "native_access_transfer_ms",
        "relay_failure_kind", "relay_http_status", "relay_error_code", "relay_error_domain", "relay_failure_age_ms",
        "relay_id", "relay_request_id", "relay_resource_id", "relay_request_method", "relay_resource_category",
        "relay_resource_basis", "relay_request_phase", "relay_request_outcome", "relay_request_http_status",
        "relay_request_age_ms", "relay_request_elapsed_ms", "relay_retained_request_count", "relay_evicted_request_count",
        "relay_retained_in_flight_count", "relay_retained_completed_count", "relay_retained_failed_count", "relay_retained_cancelled_count",
        "relay_observed_failure_request_id", "relay_observed_failure_resource_id", "relay_same_resource_later_completed",
        "relay_failure_request_id", "relay_failure_resource_id", "relay_failure_resource_category",
        "relay_playlist_resource_id", "relay_playlist_samples", "relay_playlist_age_ms", "relay_playlist_metadata_preserved",
        "relay_playlist_upstream_kind", "relay_playlist_upstream_change", "relay_playlist_upstream_endlist",
        "relay_playlist_upstream_segments", "relay_playlist_upstream_sequence", "relay_playlist_upstream_target_ms",
        "relay_playlist_upstream_last_digest", "relay_playlist_upstream_unchanged_ms",
        "relay_playlist_rewritten_kind", "relay_playlist_rewritten_change", "relay_playlist_rewritten_endlist",
        "relay_playlist_rewritten_segments", "relay_playlist_rewritten_sequence", "relay_playlist_rewritten_target_ms",
        "relay_playlist_rewritten_last_digest", "relay_playlist_rewritten_unchanged_ms",
        "preparation_stage", "preparation_reason", "preparation_error_domain", "preparation_error_code",
        "preparation_underlying_domain", "preparation_underlying_code", "preparation_error_depth", "preparation_http_status",
        "diagnostic_phase", "diagnostic_purpose", "diagnostic_result", "handoff_phase", "audio_job_id",
        "diagnostic_operation_id", "audio_enabled", "playback_intent", "candidate_count"
    ]
    private static let retentionInterval: TimeInterval = 14 * 24 * 60 * 60
    private static let maximumRecords = 250

    private let defaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let performanceStore: FottyPerformanceStore
    private let lock: NSLock
    private let writes: FottyDefaultsWriteBuffer
    // The persisted receipt is checked on every read so another store instance,
    // restore or clear cannot leave this owner serving an old in-memory snapshot.
    private var hasLoadedRecords = false
    private var cachedRecordsReceipt: Data?
    private var cachedRecords: [FottyQualityRecord] = []
    private var corruptRecordsReceipt = false
    private var cachedRecordsValidUntil: Date?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "fotty.quality.records.v1",
        now: @escaping () -> Date = Date.init,
        performanceStore: FottyPerformanceStore? = nil,
        lock: NSLock = NSLock()
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.now = now
        self.performanceStore = performanceStore ?? FottyPerformanceStore(defaults: defaults, now: now)
        self.lock = lock
        self.writes = FottyDefaultsWriteBuffer(defaults: defaults)
    }

    func record(
        category: FottyQualityCategory,
        name: String,
        outcome: FottyQualityOutcome,
        durationMilliseconds: Int? = nil,
        details: [String: String] = [:]
    ) {
        // Synthetic outage outcomes belong in the bounded XCTest receipt, not the owner's real history.
        guard AppRuntime.privateOutageFixture == nil else { return }
        let safeName = Self.safeToken(name, maximumLength: 48) ?? "unknown"
        let safeDetails = details.reduce(into: [String: String]()) { result, entry in
            guard Self.allowedDetailKeys.contains(entry.key),
                  Self.validCorrelationDetail(entry.key, value: entry.value),
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
        defer { lock.unlock(); writes.drain() }
        var values = decodedRecordsLocked()
        values.append(record)
        persistLocked(Self.pruned(values, now: record.timestamp))
    }

    func records() -> [FottyQualityRecord] {
        lock.lock()
        defer { lock.unlock(); writes.drain() }
        let decoded = decodedRecordsLocked()
        let time = now()
        if !corruptRecordsReceipt, let validUntil = cachedRecordsValidUntil, time <= validUntil {
            return decoded
        }
        let values = Self.pruned(decoded, now: time)
        if values != decoded || corruptRecordsReceipt {
            persistLocked(values)
        } else {
            cachedRecordsValidUntil = Self.nextExpiry(of: values)
        }
        return values
    }

    func summary() -> FottyQualitySummary {
        Self.summarize(records())
    }

    func ownerStatusSnapshot(
        appVersion: String? = nil,
        appBuild: String? = nil
    ) -> FottyOwnerStatusSnapshot {
        let version = appVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
        let build = appBuild
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "unknown"
        let retained = records()
        let current = retained.filter { $0.appVersion == version && $0.appBuild == build }
        return FottyOwnerStatusSnapshot(
            generatedAt: now(),
            appVersion: version,
            appBuild: build,
            currentBuildSummary: Self.summarize(current),
            retainedRecordCount: retained.count,
            olderBuildRecordCount: retained.count - current.count,
            firstCurrentBuildRecordAt: current.map(\.timestamp).min(),
            lastCurrentBuildRecordAt: current.map(\.timestamp).max(),
            performance: performanceStore.summary()
        )
    }

    static func summarize(_ records: [FottyQualityRecord]) -> FottyQualitySummary {
        let playbackRecords = records.filter { $0.category == .playback }
        let attempts = Dictionary(grouping: playbackRecords) { record in
            record.details["attempt_id"] ?? "record:\(record.id.uuidString)"
        }
        let startupSamples = attempts.values
            .compactMap { attempt in
                attempt
                    .filter { $0.name == "decoded_progress" }
                    .min(by: { $0.timestamp < $1.timestamp })?
                    .durationMilliseconds
            }
            .sorted()
        let median: Int?
        if startupSamples.isEmpty {
            median = nil
        } else {
            median = startupSamples[(startupSamples.count - 1) / 2]
        }
        return FottyQualitySummary(
            recordCount: records.count,
            playbackAttempts: attempts.values.count { $0.contains { $0.name == "attempt_started" } },
            provenPlaybackStarts: attempts.values.count { $0.contains { $0.name == "decoded_progress" } },
            sustainedNativeAttempts: attempts.values.count { $0.contains { $0.name == "native_continuity_90s" && $0.outcome == .success } },
            recoveredPlaybackEvents: attempts.values.count { $0.contains { $0.outcome == .recovered } },
            automaticFailovers: playbackRecords.count { $0.name == "automatic_failover" },
            terminalPlaybackFailures: attempts.values.count { $0.contains { $0.name == "terminal_failure" } },
            resolutionFailures: attempts.values.count { $0.contains { $0.name == "resolution_failure" } },
            nativeHandoffs: attempts.values.count {
                $0.contains { $0.name == "native_handoff" && $0.outcome == .success }
            },
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
            privacyNotice: "On-device quality events and dated scalar performance summaries only. No fixture names, manager identifiers, URLs, credentials, prompt text or raw diagnostic traces. Missing performance data is not a zero-failure result; Apple reports may cover older or multiple builds.",
            summary: Self.summarize(retainedRecords),
            performance: performanceStore.summary(),
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
        writes.removeObject(forKey: storageKey)
        hasLoadedRecords = true
        cachedRecordsReceipt = nil
        cachedRecords = []
        corruptRecordsReceipt = false
        cachedRecordsValidUntil = .distantFuture
        lock.unlock()
        writes.drain()
        performanceStore.clear()
    }

    private struct ExportPayload: Codable {
        let generatedAt: Date
        let privacyNotice: String
        let summary: FottyQualitySummary
        let performance: FottyPerformanceSummary
        let records: [FottyQualityRecord]
    }

    private func decodedRecordsLocked() -> [FottyQualityRecord] {
        let data = writes.object(forKey: storageKey) as? Data
        if hasLoadedRecords, data == cachedRecordsReceipt { return cachedRecords }
        hasLoadedRecords = true
        cachedRecordsReceipt = data
        corruptRecordsReceipt = false
        cachedRecordsValidUntil = nil
        if let data {
            if let records = try? JSONDecoder().decode([FottyQualityRecord].self, from: data) {
                cachedRecords = records
            } else {
                cachedRecords = []
                corruptRecordsReceipt = true
            }
        } else {
            cachedRecords = []
        }
        return cachedRecords
    }

    private func persistLocked(_ records: [FottyQualityRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        writes.set(data, forKey: storageKey)
        hasLoadedRecords = true
        cachedRecordsReceipt = data
        cachedRecords = records
        corruptRecordsReceipt = false
        cachedRecordsValidUntil = Self.nextExpiry(of: records)
    }

    private static func nextExpiry(of records: [FottyQualityRecord]) -> Date {
        records.map(\.timestamp).min()?.addingTimeInterval(retentionInterval) ?? .distantFuture
    }

    private static func pruned(_ records: [FottyQualityRecord], now: Date) -> [FottyQualityRecord] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let retained = records.filter { $0.timestamp >= cutoff }
        let cohorts = Dictionary(grouping: retained) { record in
            if record.category == .playback, let attemptID = record.details["attempt_id"] {
                return "playback:\(attemptID)"
            }
            if record.category == .playback, record.name == "audio_activation_evidence",
               let jobID = record.details["audio_job_id"], UUID(uuidString: jobID) != nil {
                return "audio_job:\(jobID)"
            }
            return "record:\(record.id.uuidString)"
        }.values.sorted {
            ($0.map(\.timestamp).max() ?? .distantPast) > ($1.map(\.timestamp).max() ?? .distantPast)
        }

        var selected: [FottyQualityRecord] = []
        for cohort in cohorts {
            if selected.isEmpty, cohort.count > maximumRecords {
                selected.append(contentsOf: cohort.sorted { $0.timestamp < $1.timestamp }.suffix(maximumRecords))
                break
            }
            guard selected.count + cohort.count <= maximumRecords else { continue }
            selected.append(contentsOf: cohort)
        }
        return selected.sorted { $0.timestamp < $1.timestamp }
    }

    private static func validCorrelationDetail(_ key: String, value: String) -> Bool {
        if ["native_continuity_elapsed_ms", "native_continuity_media_advance_ms", "native_continuity_stalls"].contains(key) {
            return UInt32(value) != nil
        }
        switch key {
        case "native_resume_action": return ["started", "resumed", "outside_window", "window_rejoined", "seek_incomplete", "buffered_play", "timeout"].contains(value)
        case "native_resume_elapsed_ms": return UInt32(value).map { $0 <= 3_600_000 } ?? false
        case "native_resume_window": return ["inside", "expired", "unknown"].contains(value)
        case "selection_version": return value == "1"
        case "selection_stage": return ["initial", "recovery"].contains(value)
        case "selection_applied": return ["baseline", "trial"].contains(value)
        case "baseline_slots", "candidate_slots":
            let slots = value.components(separatedBy: ".")
            return value == "none" || (1...3).contains(slots.count) && slots.allSatisfy { UInt16($0).map { $0 > 0 } == true }
        case "selection_reason": return ["prior_failure", "played_this_fixture", "different_family", "different_origin",
                                          "same_pick", "ranked_admitted", "no_eligible_route"].contains(value)
        case "candidate_families", "duplicate_choices": return UInt16(value) != nil
        case "independence_evidence": return value == "unverified"
        case "live_event_delay_evidence": return value == "unmeasured"
        case "assignment_basis": return SinglePlaybackAssignmentBasis(rawValue: value) != nil
        case "programme_observation": return SinglePlaybackProgrammeObservation(rawValue: value) != nil
        case "upstream_independence_evidence": return value == "unverified"
        case "media_clock_evidence": return ["unavailable_web", "unknown", "advertised_item_date"].contains(value)
        case "advertised_media_age_ms": return Int(value).map { (0...86_400_000).contains($0) } ?? false
        case "native_presentation_width", "native_presentation_height": return Int(value).map { (1...16_384).contains($0) } ?? false
        case "native_access_event_count": return Int(value).map { (1...100_000).contains($0) } ?? false
        case "diagnostic_phase": return FottyPlaybackDiagnosticPhase(rawValue: value) != nil
        case "diagnostic_purpose": return FottyPlaybackDiagnosticPurpose(rawValue: value) != nil
        case "diagnostic_result": return FottyPlaybackDiagnosticResult(rawValue: value) != nil
        case "handoff_phase": return FottyPlaybackDiagnosticHandoffPhase(rawValue: value) != nil
        case "audio_job_id", "diagnostic_operation_id", "relay_id", "relay_request_id", "relay_resource_id",
             "relay_observed_failure_request_id", "relay_observed_failure_resource_id", "relay_failure_request_id", "relay_failure_resource_id",
             "native_presentation_id":
            return UUID(uuidString: value) != nil
        case "native_presentation_event": return NativeFullscreenLifecycleEvent(rawValue: value) != nil
        case "relay_request_method": return LocalStreamProxyRequestReceipt.Method(rawValue: value) != nil
        case "relay_resource_category", "relay_failure_resource_category":
            return LocalStreamProxyRequestReceipt.ResourceCategory(rawValue: value) != nil
        case "relay_resource_basis": return LocalStreamProxyRequestReceipt.CategoryBasis(rawValue: value) != nil
        case "relay_request_outcome": return LocalStreamProxyRequestReceipt.Outcome(rawValue: value) != nil
        case "relay_request_phase": return LocalStreamProxyFailureEvidence.Stage(rawValue: value) != nil
        case "relay_same_resource_later_completed": return ["true", "false"].contains(value)
        case "relay_retained_request_count", "relay_retained_in_flight_count", "relay_retained_completed_count", "relay_retained_failed_count", "relay_retained_cancelled_count":
            return Int(value).map { (0...LocalStreamProxyRequestSnapshot.maximumRetainedRequests).contains($0) } ?? false
        case "relay_evicted_request_count": return Int(value).map { (0...1_000_000).contains($0) } ?? false
        case "audio_enabled", "playback_intent", "native_pip_active", "native_app_backgrounded":
            return ["true", "false"].contains(value)
        case "candidate_count": return Int(value).map { (0...12).contains($0) } ?? false
        case "cs_stream_entry_count", "cs_admission_rejected_count", "addon_stream_entry_count", "addon_admission_rejected_count":
            return Int(value).map { (0...100).contains($0) } ?? false
        case "stage", "last_observed_stage":
            return FottyPlaybackStage(rawValue: value) != nil
        case "platform_error_code":
            return Int(value).map { (-100_000...100_000).contains($0) } ?? false
        case "native_failure_trigger":
            return NativePlaybackDiagnosticTrigger(rawValue: value) != nil
        case "native_hls_issue", "native_log_hls_issue":
            return NativeHLSPlaylistIssue(rawValue: value) != nil
        case "preparation_stage":
            return PlaybackPreparationDiagnostic.Stage(rawValue: value) != nil
                || NativeWatchTwoPreflightStage(rawValue: value) != nil
        case "preparation_reason":
            return PlaybackPreparationDiagnostic.Reason(rawValue: value) != nil
                || NativeWatchTwoPreflightOutcome(rawValue: value) != nil
        case "native_error_domain", "native_underlying_domain", "native_log_domain", "relay_error_domain",
             "preparation_error_domain", "preparation_underlying_domain":
            return NativePlaybackErrorDomain(rawValue: value) != nil
        case "native_error_code", "native_underlying_code", "native_log_code", "relay_error_code",
             "preparation_error_code", "preparation_underlying_code":
            return Int(value).map(NativePlaybackErrorDomain.isBoundedCode) ?? false
        case "native_error_depth", "preparation_error_depth":
            return Int(value).map { (1...4).contains($0) } ?? false
        case "relay_failure_stage":
            return LocalStreamProxyFailureEvidence.Stage(rawValue: value) != nil
        case "relay_failure_kind":
            return LocalStreamProxyFailureEvidence.Kind(rawValue: value) != nil
        case "relay_http_status", "preparation_http_status", "relay_request_http_status":
            return Int(value).map { (100...599).contains($0) } ?? false
        case "relay_failure_age_ms", "relay_request_age_ms", "relay_request_elapsed_ms", "native_startup_elapsed_ms", "native_startup_deadline_ms":
            return Int(value).map { (0...3_600_000).contains($0) } ?? false
        case "native_item_status":
            return ["unknown", "ready", "failed", "other"].contains(value)
        case "native_time_control":
            return ["paused", "waiting", "playing", "other"].contains(value)
        case "native_wait_reason":
            return ["minimize_stalls", "evaluating_buffer", "no_item", "none", "other"].contains(value)
        case "native_buffer_empty", "native_buffer_full", "native_likely_to_keep_up":
            return ["true", "false"].contains(value)
        case "watch_session_id", "previous_attempt_id", "source_id":
            return UUID(uuidString: value) != nil
        case "variant_key":
            return value.range(of: #"^variant_[a-f0-9]{32}$"#, options: .regularExpression) != nil
        case "attempt_number", "source_index", "source_count":
            return Int(value).map { (0...1_000_000).contains($0) } ?? false
        case "device_family":
            return ["iphone", "ipad", "catalyst", "other", "unknown"].contains(value)
        case "os_version":
            return value.range(of: #"^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"#,
                               options: .regularExpression) != nil
        default: return true
        }
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
