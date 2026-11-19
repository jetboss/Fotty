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
final class FottyDefaultsWriteBuffer {
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

/// Builds the small, privacy-safe playback context for the player. The quality
/// store applies a second allowlist before anything is retained, but keeping
/// construction here prevents accidentally adding a fixture name or URL.
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

enum FottyPlaybackDiagnosticRoute: String { case single }

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
    let streamAdmissions: [StreamAdmissionSummary.Row]
    let retainedRecordCount: Int
    let olderBuildRecordCount: Int
    let firstCurrentBuildRecordAt: Date?
    let lastCurrentBuildRecordAt: Date?
    let performance: FottyPerformanceSummary

    var hasCurrentBuildEvidence: Bool { currentBuildSummary.recordCount > 0 }
}

/// One provider lookup's bounded accounting. Reasons describe decisions made by
/// the adapter; they never claim that an unplayed response contains live video.
struct StreamAdmissionLedger: Equatable, Sendable {
    static let validCount = 0...1_000_000
    static let reasons: Set<String> = [
        "admitted", "duplicate", "malformed", "no_url", "drm", "not_https", "too_long",
        "credentials_in_link", "unsafe_destination", "replay", "not_live_media",
        "inner_not_https", "inner_credentials", "inner_unsafe_destination", "not_a_playlist",
        "credential_headers", "malformed_headers", "sign_in", "same_addon_domain",
        "validation", "unsupported", "filtered", "fixture_changed", "withdrawn", "limit", "unprocessed",
        "expired", "disabled", "binding"
    ]
    static let completions: Set<String> = ["complete", "partial", "failed", "cancelled", "limited"]
    static func detailKey(_ reason: String) -> String { "admission_" + reason + "_count" }
    static let countDetailKeys = Set(reasons.map(detailKey))

    let id = UUID()
    private(set) var offered = 0
    private(set) var dispositions: [String: Int] = [:]
    private(set) var hasObservedResponse = false
    private(set) var accountingValid = true
    private(set) var completion = "complete"
    private(set) var isFinished = false
    var admitted: Int { dispositions["admitted", default: 0] }
    var accounted: Int { dispositions.values.reduce(0, +) }
    var isReconciled: Bool { hasObservedResponse && accountingValid && accounted == offered }

    mutating func observe(_ count: Int) {
        guard !isFinished, Self.validCount.contains(count), count <= Self.validCount.upperBound - offered else {
            accountingValid = false; return
        }
        hasObservedResponse = true
        offered += count
    }

    mutating func record(_ reason: String, count: Int = 1) {
        guard !isFinished, Self.reasons.contains(reason), Self.validCount.contains(count), count <= offered - accounted else {
            accountingValid = false; return
        }
        if count > 0 { dispositions[reason, default: 0] += count }
    }

    /// Call after the final authority check. Known scan/session tails must be
    /// recorded as `limit` by the caller; unexplained rows remain `unprocessed`.
    mutating func finish(admitted returned: Int, completion: String = "complete") {
        let validCompletion = Self.completions.contains(completion)
        guard validCompletion, Self.validCount.contains(returned), returned <= offered else {
            accountingValid = false
            self.completion = validCompletion ? completion : "failed"
            if !isFinished {
                dispositions["unprocessed", default: 0] += offered - accounted
                isFinished = true
            }
            return
        }
        let finalCount = ["failed", "cancelled"].contains(completion) ? 0 : returned
        if isFinished {
            if finalCount > admitted { accountingValid = false; return }
            dispositions["withdrawn", default: 0] += admitted - finalCount
            dispositions["admitted"] = finalCount
            self.completion = completion
            return
        }
        self.completion = completion
        if admitted > finalCount {
            dispositions["withdrawn", default: 0] += admitted - finalCount
            dispositions["admitted"] = finalCount
        } else if finalCount > admitted {
            let additional = finalCount - admitted
            if additional <= offered - accounted { dispositions["admitted", default: 0] += additional }
            else { accountingValid = false }
        }
        let remaining = offered - accounted
        if remaining > 0 { dispositions["unprocessed", default: 0] += remaining }
        isFinished = true
    }
}

/// Totals from retained receipts. A lookup can see the same stream again.
enum StreamAdmissionSummary {
    static let validCount = StreamAdmissionLedger.validCount
    struct Row: Identifiable, Equatable {
        let id: CuratedStreamSourceCatalog.Provider
        var lookups = 0
        var offered: Int? = 0
        var admitted: Int? = 0
        var firstPictures = 0
        var dispositions: [String: Int] = [:]
        var observedOffered = 0
        var unreadLookups = 0
        var fetchFailures = 0
        var incompleteLookups = 0
        var unreconciledLookups = 0
        var reportedReason: String?
        fileprivate var reasonTime: Date?
    }

    static func rows(records: [FottyQualityRecord]) -> [Row] {
        var rows: [CuratedStreamSourceCatalog.Provider: Row] = [:]
        var lookupIDs = Set<String>()
        for record in records where record.category == .playback {
            let provider: CuratedStreamSourceCatalog.Provider
            switch record.name {
            case "highfly_delivery_admission": provider = .highfly
            case "penguplay_delivery_admission": provider = .penguPlay
            case "stream_admission", WatchOutcomeRecorder.recordName:
                guard let family = record.details["source_family"]?.lowercased(),
                      let definition = CuratedStreamSourceCatalog.all.first(where: {
                          $0.providerCode == family || $0.opaqueLabelPrefix?.lowercased() == family
                      }) else { continue }
                provider = definition.provider
            default: continue
            }
            var row = rows[provider] ?? Row(id: provider)
            if record.name == WatchOutcomeRecorder.recordName {
                guard record.details["terminal_outcome"] == WatchOutcomeTerminal.playing.rawValue else { continue }
                row.firstPictures += 1
            } else {
                if let lookupID = record.details["admission_lookup_id"], !lookupIDs.insert(lookupID).inserted { continue }
                // Legacy account receipts captured candidates before final validation.
                // Their raw entry count is useful, but admitted choices are unknown.
                let offered = count(record.details["offered_count"] ?? record.details["addon_stream_entry_count"])
                let admitted = count(record.details["admitted_count"])
                row.lookups += 1
                row.observedOffered += offered ?? 0
                row.offered = row.offered.flatMap { total in offered.map { total + $0 } }
                if let offered, let admitted, admitted <= offered, let previous = row.admitted {
                    row.admitted = previous + admitted
                } else {
                    row.admitted = nil
                }
                if record.details["admission_schema"] == "1" {
                    row.unreadLookups += record.details["admission_observation"] == "unread" ? 1 : 0
                    row.fetchFailures += count(record.details["admission_fetch_failures"]) ?? 0
                    row.incompleteLookups += record.details["admission_completion"] == "complete" ? 0 : 1
                    let decisions = StreamAdmissionLedger.reasons.reduce(into: [String: Int]()) { result, reason in
                        if let value = count(record.details[StreamAdmissionLedger.detailKey(reason)]) { result[reason] = value }
                    }
                    if let offered, let admitted, record.details["admission_reconciled"] == "yes",
                       decisions.values.reduce(0, +) == offered, decisions["admitted", default: 0] == admitted {
                        for (reason, value) in decisions { row.dispositions[reason, default: 0] += value }
                    } else if let offered {
                        row.unreconciledLookups += 1
                        row.dispositions["unrecorded", default: 0] += offered
                    }
                } else if let offered {
                    // Historical receipts cannot supply a reason histogram.
                    // Account for that gap explicitly instead of extending one
                    // modal reason to every excluded entry.
                    let knownAdmitted = admitted.flatMap { $0 <= offered ? $0 : nil } ?? 0
                    row.dispositions["admitted", default: 0] += knownAdmitted
                    row.dispositions["unrecorded", default: 0] += offered - knownAdmitted
                }
                if let reason = record.details["reason_code"], row.reasonTime.map({ $0 <= record.timestamp }) ?? true {
                    row.reportedReason = reason
                    row.reasonTime = record.timestamp
                }
            }
            rows[provider] = row
        }
        return CuratedStreamSourceCatalog.all.compactMap { rows[$0.provider] }
    }

    static func mostFrequent(_ reasons: [String]) -> String? {
        let counts = reasons.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.sorted().max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    private static func count(_ value: String?) -> Int? {
        guard let value, let parsed = Int(value), validCount.contains(parsed) else { return nil }
        return parsed
    }
}

/// Privacy-safe, on-device evidence for Fotty's release gates.
///
/// Records are bounded and deliberately reject URLs, credentials, free-form
/// errors, fixture names, manager IDs, and prompt text. Recording never causes
/// network traffic and can be cleared or exported by the user.
final class FottyQualityStore {
    static let shared = FottyQualityStore(performanceStore: .shared)

    private static let admissionDetailKeys: Set<String> = Set([
        "admission_schema", "admission_lookup_id", "admission_completion", "admission_observation",
        "admission_reconciled", "admission_fetch_failures", "stream_selection_stage"
    ]).union(StreamAdmissionLedger.countDetailKeys)
    private static let streamSelectionStages: Set<String> = ["final_watch", "registry_binding", "discovery_cache"]
    private static let evidenceCountKeys: Set<String> = ["evidence_read_responses", "evidence_unread_responses",
        "evidence_empty_responses", "evidence_observed_entries", "evidence_unique_contracts",
        "evidence_retained_entries", "evidence_entry_index"]
    private static let evidenceDetailKeys: Set<String> = evidenceCountKeys.union([
        "evidence_schema", "evidence_fixture", "evidence_lookup_id", "evidence_generation",
        "evidence_listing", "evidence_contract", "evidence_has_name", "evidence_has_title",
        "evidence_comparison", "evidence_disposition", "evidence_truncated", "evidence_reconciled", "evidence_web_only"
    ])

    private static let allowedDetailKeys: Set<String> = [
        "discovery_first_candidate_ms", "discovery_first_snapshot_ms", "discovery_initial_wait",
        "mode", "failure_kind", "recovery_kind", "feed", "source",
        "model", "route", "result", "reason_code", "token_count",
        "source_family", "source_key", "attempt_id", "watch_session_id",
        "previous_attempt_id", "attempt_number", "source_id", "variant_key",
        "device_family", "os_version", "source_index", "source_count",
        "selection_version", "selection_stage", "selection_applied", "baseline_slots", "candidate_slots",
        "selection_reason", "candidate_families", "duplicate_choices", "independence_evidence",
        "last_observed_stage", "stage", "platform_error_code",
        "cs_stream_entry_count", "cs_admission_rejected_count",
        "addon_stream_entry_count", "addon_admission_rejected_count", "offered_count", "admitted_count",
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
        "relay_unaliased_segment", "relay_playlist_resource_id", "relay_playlist_samples", "relay_playlist_age_ms", "relay_playlist_metadata_preserved",
        "relay_playlist_upstream_kind", "relay_playlist_upstream_change", "relay_playlist_upstream_endlist",
        "relay_playlist_upstream_segments", "relay_playlist_upstream_sequence", "relay_playlist_upstream_target_ms",
        "relay_playlist_upstream_last_digest", "relay_playlist_upstream_unchanged_ms",
        "relay_playlist_rewritten_kind", "relay_playlist_rewritten_change", "relay_playlist_rewritten_endlist",
        "relay_playlist_rewritten_segments", "relay_playlist_rewritten_sequence", "relay_playlist_rewritten_target_ms",
        "relay_playlist_rewritten_last_digest", "relay_playlist_rewritten_unchanged_ms",
        "preparation_stage", "preparation_reason", "preparation_error_domain", "preparation_error_code",
        "preparation_underlying_domain", "preparation_underlying_code", "preparation_error_depth", "preparation_http_status",
        "diagnostic_phase", "diagnostic_purpose", "diagnostic_result", "handoff_phase", "audio_job_id",
        "diagnostic_operation_id", "audio_enabled", "playback_intent", "candidate_count",
        "competition", "sport", "terminal_outcome", "failover_family", "failover_count",
        // A source's normalized spelling of one team (alias review); never a title/link.
        "unmatched_team", "delivery_host", "kickoff_offset_min", "search_scope", "listing_span_h", "live_catalog", "live_row_count", "live_row_shape", "live_sport_rows", "live_categories", "live_rest_shape", "live_layout", "supplementary_failures", "request_pair", "candidate_pair", "candidate_pair_2", "listing_count", "used_count"
    ]
    private static let retentionInterval: TimeInterval = 14 * 24 * 60 * 60
    private static let maximumRecords = 250
    /// One `watch_outcome` per tap is the per-competition reliability record.
    /// Playback cohorts are large, so the newest outcomes keep a bounded share
    /// of the same 250-record buffer instead of a parallel store.
    static let reservedWatchOutcomes = 100
    static let routineRefreshNames: Set<String> = ["live_refresh", "schedule_refresh"]
    static let maximumRoutineRefreshSuccesses = 40
    /// Samples have their own share of the same buffer, ahead of older ordinary
    /// history but never reserved outcomes or the newest playback/audio cohort.
    static let reservedProviderDeliveryRecords = 64

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

    /// The adapter owns this receipt. Discovery, ranking and cache replay must
    /// not record these same response entries a second time.
    func recordStreamAdmission(sourceFamily: String, ledger: StreamAdmissionLedger,
                               completion: String = "complete", fetchFailures: Int = 0) {
        recordStreamDecisions(sourceFamily: sourceFamily, ledger: ledger, completion: completion,
                              fetchFailures: fetchFailures, name: "stream_admission")
    }

    /// One atomic diagnostic write per lookup. Replayed receipts do not become
    /// extra lookups, and a partial response is never written as an empty one.
    /// This does not publish telemetry or influence source selection.
    func recordProviderLookup(_ receipt: ProviderLookupReceipt) {
        guard AppRuntime.privateOutageFixture == nil, receipt.fixture.isValid,
              receipt.startedAt.timeIntervalSinceReferenceDate.isFinite,
              receipt.finishedAt.timeIntervalSinceReferenceDate.isFinite, receipt.finishedAt >= receipt.startedAt,
              receipt.provider == .highfly || receipt.provider == .penguPlay,
              receipt.deliveries.count <= StreamLookupEvidence.maximumDeliveries,
              StreamAdmissionLedger.completions.contains(receipt.completion),
              [receipt.observedEntries, receipt.readResponses, receipt.unreadResponses,
               receipt.knownEmptyResponses, receipt.uniqueObservedContracts, receipt.admitted]
                .allSatisfy(StreamAdmissionLedger.validCount.contains),
              receipt.knownEmptyResponses <= receipt.readResponses,
              receipt.readResponses - receipt.knownEmptyResponses <= receipt.observedEntries,
              receipt.observedEntries == 0 || receipt.readResponses > receipt.knownEmptyResponses,
              receipt.admitted <= receipt.observedEntries,
              receipt.deliveries.count <= receipt.observedEntries,
              receipt.uniqueObservedContracts == Set(receipt.deliveries.compactMap(\.contract)).count,
              receipt.dispositions.keys.allSatisfy(StreamAdmissionLedger.reasons.contains),
              receipt.dispositions.values.allSatisfy(StreamAdmissionLedger.validCount.contains),
              receipt.deliveries.allSatisfy({ $0.listing.isValid && ($0.contract?.isValid ?? true)
                  && StreamAdmissionLedger.validCount.contains($0.index)
                  && StreamAdmissionLedger.reasons.contains($0.disposition)
                  && ($0.sourceID == nil || ($0.contract != nil && ["admitted", "withdrawn"].contains($0.disposition)))
                  && $0.observedAt.timeIntervalSinceReferenceDate.isFinite
                  && $0.observedAt >= receipt.startedAt && $0.observedAt <= receipt.finishedAt }) else { return }
        let hex: (DeviceHMAC) -> String = { $0.bytes.map { String(format: "%02x", $0) }.joined() }
        let common = ["source_family": receipt.provider.rawValue, "evidence_schema": "1",
                      "evidence_fixture": hex(receipt.fixture), "evidence_lookup_id": receipt.lookupID.uuidString.lowercased(),
                      "evidence_generation": receipt.configurationGeneration.uuidString.lowercased()]
        var summary = common
        summary["admission_completion"] = receipt.completion
        summary["evidence_read_responses"] = String(receipt.readResponses)
        summary["evidence_unread_responses"] = String(receipt.unreadResponses)
        summary["evidence_empty_responses"] = String(receipt.knownEmptyResponses)
        summary["evidence_observed_entries"] = String(receipt.observedEntries)
        summary["evidence_unique_contracts"] = String(receipt.uniqueObservedContracts)
        summary["evidence_retained_entries"] = String(receipt.deliveries.count)
        let truncated = receipt.isTruncated || receipt.deliveries.count < receipt.observedEntries
        let samples = receipt.deliveries.reduce(into: [String: Int]()) { $0[$1.disposition, default: 0] += 1 }
        let reconciled = receipt.isReconciled && receipt.readResponses > 0
            && receipt.dispositions.values.reduce(0, +) == receipt.observedEntries
            && receipt.dispositions["admitted", default: 0] == receipt.admitted
            && StreamAdmissionLedger.reasons.allSatisfy {
                truncated ? samples[$0, default: 0] <= receipt.dispositions[$0, default: 0]
                    : samples[$0, default: 0] == receipt.dispositions[$0, default: 0]
            }
        summary["evidence_truncated"] = String(truncated)
        summary["evidence_reconciled"] = String(reconciled)
        summary["admitted_count"] = String(receipt.admitted)
        for reason in StreamAdmissionLedger.reasons {
            summary[StreamAdmissionLedger.detailKey(reason)] = String(receipt.dispositions[reason, default: 0])
        }
        let timestamp = receipt.finishedAt
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        func make(_ name: String, _ details: [String: String]) -> FottyQualityRecord {
            FottyQualityRecord(id: UUID(), timestamp: timestamp, category: .playback, name: name, outcome: .info,
                durationMilliseconds: nil, details: details, appVersion: version, appBuild: build)
        }
        var cohort = receipt.deliveries.map { delivery -> FottyQualityRecord in
            var details = common
            details["evidence_listing"] = hex(delivery.listing)
            details["evidence_contract"] = delivery.contract.map(hex)
            details["evidence_entry_index"] = String(delivery.index)
            details["evidence_has_name"] = String(delivery.hasName)
            details["evidence_has_title"] = String(delivery.hasTitle)
            details["evidence_comparison"] = delivery.comparison.rawValue
            details["evidence_disposition"] = delivery.disposition
            details["source_id"] = delivery.sourceID?.uuidString.lowercased()
            return make("provider_delivery", details)
        }
        cohort.append(make("provider_lookup", summary))
        lock.lock()
        defer { lock.unlock(); writes.drain() }
        var values = decodedRecordsLocked()
        guard !values.contains(where: { $0.name == "provider_lookup"
            && $0.details["source_family"] == receipt.provider.rawValue
            && $0.details["evidence_lookup_id"] == receipt.lookupID.uuidString.lowercased() }) else { return }
        values.append(contentsOf: cohort)
        persistLocked(Self.pruned(values, now: now()))
    }

    /// A successfully matched Web page is one lookup, never an enumerated
    /// media response. Keep its raw offered/admitted counts unavailable and
    /// correlate only the device-local fixture digest and lookup UUID.
    func recordScore808WebLookup(fixtureID: String, lookupID: UUID) {
        guard AppRuntime.privateOutageFixture == nil,
              case .fixture(let fixture)? = LiveSourceHealthStore.fixtureProgrammeScope(fixtureID: fixtureID) else { return }
        let timestamp = now()
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else { return }
        let details = ["source_family": "score808", "evidence_schema": "1",
            "evidence_fixture": fixture.bytes.map { String(format: "%02x", $0) }.joined(),
            "evidence_lookup_id": lookupID.uuidString.lowercased(), "evidence_web_only": "true",
            "admission_completion": "complete", "admission_observation": "unread", "admission_reconciled": "unknown",
            "evidence_observed_entries": "0", "evidence_unique_contracts": "0", "evidence_retained_entries": "0",
            "evidence_read_responses": "0", "evidence_unread_responses": "0", "evidence_empty_responses": "0",
            "evidence_truncated": "false", "evidence_reconciled": "false"]
        let record = FottyQualityRecord(id: UUID(), timestamp: timestamp, category: .playback,
            name: "provider_lookup", outcome: .info, durationMilliseconds: nil, details: details,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
        lock.lock()
        defer { lock.unlock(); writes.drain() }
        var values = decodedRecordsLocked()
        guard !values.contains(where: { $0.name == "provider_lookup" && $0.details["source_family"] == "score808"
            && $0.details["evidence_lookup_id"] == lookupID.uuidString.lowercased() }) else { return }
        values.append(record)
        persistLocked(Self.pruned(values, now: timestamp))
    }

    /// Totals describe retained receipts only. A contract seen in repeated
    /// lookups counts once; response entries still count on each distinct read.
    func fixtureLookupCounts(fixture: DeviceHMAC, provider: EvidenceProvider,
                             window: DateInterval) -> FixtureLookupCounts {
        let hex = fixture.bytes.map { String(format: "%02x", $0) }.joined()
        let rows = records().filter { $0.category == .playback && $0.details["evidence_fixture"] == hex
            && $0.details["source_family"] == provider.rawValue && window.contains($0.timestamp) }
        var lookups = Set<String>(), contracts = Set<String>()
        var observed = 0, read = 0, unread = 0, empty = 0, webOnly = 0, truncated = false
        for row in rows where row.name == "provider_lookup" {
            guard let lookup = row.details["evidence_lookup_id"], UUID(uuidString: lookup) != nil,
                  lookups.insert(lookup).inserted else { continue }
            if provider == .score808, row.details["evidence_web_only"] == "true" { webOnly += 1 }
            func count(_ key: String) -> Int {
                guard let value = row.details[key], let number = Int(value),
                      StreamAdmissionLedger.validCount.contains(number) else { truncated = true; return 0 }
                return number
            }
            observed += count("evidence_observed_entries"); read += count("evidence_read_responses")
            unread += count("evidence_unread_responses"); empty += count("evidence_empty_responses")
            let samples = rows.filter { $0.name == "provider_delivery" && $0.details["evidence_lookup_id"] == lookup }
            if samples.count != count("evidence_retained_entries") || row.details["evidence_truncated"] != "false" { truncated = true }
            for sample in samples {
                if let contract = sample.details["evidence_contract"], Self.validCorrelationDetail("evidence_contract", value: contract) {
                    contracts.insert(contract)
                }
            }
        }
        return .init(fixture: fixture, provider: provider, window: window, lookups: lookups.count,
            observedEntries: observed, uniqueObservedContracts: contracts.count, readResponses: read,
            unreadResponses: unread, knownEmptyResponses: empty, webOnlyLookups: webOnly, isTruncated: truncated)
    }

    /// Session filtering is a separate unit from provider response entries.
    /// A selection receipt never contributes to offered/admitted lookup totals.
    func recordStreamSelection(sourceFamily: String, stage: String, ledger: StreamAdmissionLedger) {
        guard Self.streamSelectionStages.contains(stage) else { return }
        recordStreamDecisions(sourceFamily: sourceFamily, ledger: ledger, completion: ledger.completion,
                              fetchFailures: 0, name: "stream_selection", stage: stage)
    }

    private func recordStreamDecisions(sourceFamily: String, ledger: StreamAdmissionLedger,
                                       completion: String, fetchFailures: Int, name: String, stage: String? = nil) {
        guard let provider = CuratedStreamSourceCatalog.Provider(rawValue: sourceFamily) else { return }
        var final = ledger
        let terminal = completion == "complete" ? ledger.completion : completion
        final.finish(admitted: final.admitted, completion: terminal)
        var details = ["source_family": provider.rawValue, "admission_schema": "1",
                       "admission_lookup_id": final.id.uuidString.lowercased(),
                       "admission_completion": StreamAdmissionLedger.completions.contains(terminal) ? terminal : "failed",
                       "admission_observation": final.hasObservedResponse ? "known" : "unread",
                       "admission_reconciled": final.hasObservedResponse ? (final.isReconciled ? "yes" : "no") : "unknown",
                       "admission_fetch_failures": String(min(max(fetchFailures, 0), StreamAdmissionLedger.validCount.upperBound))]
        if final.hasObservedResponse {
            details["offered_count"] = String(final.offered)
            details["admitted_count"] = String(final.admitted)
        }
        details["stream_selection_stage"] = stage
        for reason in StreamAdmissionLedger.reasons {
            details[StreamAdmissionLedger.detailKey(reason)] = String(final.dispositions[reason, default: 0])
        }
        record(category: .playback, name: name, outcome: terminal == "complete" ? .info : .failure,
               details: details)
    }

    /// Legacy receipt compatibility. The offered entries and returned choices
    /// belong to the same request; a cancelled lookup supplies neither count.
    func recordStreamAdmission(sourceFamily: String, offered: Int, admitted: Int) {
        guard let provider = CuratedStreamSourceCatalog.Provider(rawValue: sourceFamily),
              StreamAdmissionSummary.validCount.contains(offered),
              (0...offered).contains(admitted) else { return }
        record(category: .playback, name: "stream_admission", outcome: .info, details: [
            "source_family": provider.rawValue,
            "offered_count": String(offered),
            "admitted_count": String(admitted)
        ])
    }

    func recordAccountStreamAdmission(provider: CuratedStreamSourceCatalog.Provider, offered: Int, admitted: Int,
                                      candidateCount: Int, listingCount: Int, rejections: [String],
                                      fallbackReason: String? = nil, rejectedHost: String?, finished: Bool) {
        guard provider == .highfly || provider == .penguPlay,
              StreamAdmissionSummary.validCount.contains(offered), (0...offered).contains(admitted) else { return }
        // Preserve the account diagnostics consumed by existing reports. Owner Status
        // uses only the explicit admission pair and a fixed display label for the reason.
        var details = ["offered_count": String(offered), "admitted_count": String(admitted),
                       "addon_stream_entry_count": String(offered), "used_count": String(admitted),
                       "candidate_count": String(min(candidateCount, 12)), "listing_count": String(listingCount),
                       "addon_admission_rejected_count": String(rejections.count)]
        details["reason_code"] = StreamAdmissionSummary.mostFrequent(rejections) ?? fallbackReason
        details["delivery_host"] = rejectedHost
        record(category: .playback, name: provider.rawValue + "_delivery_admission",
               outcome: finished ? .info : .failure, details: details)
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
            guard Self.allowedDetailKeys.contains(entry.key) || Self.admissionDetailKeys.contains(entry.key)
                    || Self.evidenceDetailKeys.contains(entry.key),
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
            streamAdmissions: StreamAdmissionSummary.rows(records: current),
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
        let positions = records.enumerated().reduce(into: [UUID: Int]()) { $0[$1.element.id] = $1.offset }
        // Routine successful score/schedule refreshes arrive every few minutes.
        // Left uncapped they evicted a whole day of playback evidence (Jet,
        // 8 Nov: 184 of 249 records). Keep only the newest few; failures and
        // every playback receipt keep their existing retention.
        var routineSuccesses = 0
        let retained = records.filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
            .filter { record in
                guard record.outcome == .success, routineRefreshNames.contains(record.name) else { return true }
                routineSuccesses += 1
                return routineSuccesses <= maximumRoutineRefreshSuccesses
            }
        // Start with the ordinary retention policy, then allocate the bounded
        // sample share below. Unused sample capacity remains ordinary history.
        let ordinary = retained.filter { !isProviderDelivery($0) }
        let cohorts = Dictionary(grouping: ordinary) { record in
            if record.category == .playback, let attemptID = record.details["attempt_id"] {
                return "playback:\(attemptID)"
            }
            if record.category == .playback, record.name == "audio_activation_evidence",
               let jobID = record.details["audio_job_id"], UUID(uuidString: jobID) != nil {
                return "audio_job:\(jobID)"
            }
            return "record:\(record.id.uuidString)"
        }.values.sorted {
            let left = $0.map(\.timestamp).max() ?? .distantPast
            let right = $1.map(\.timestamp).max() ?? .distantPast
            if left == right {
                return ($0.map { positions[$0.id, default: 0] }.max() ?? 0)
                    > ($1.map { positions[$0.id, default: 0] }.max() ?? 0)
            }
            return left > right
        }

        let reserved = Set(ordinary.filter { $0.category == .playback && $0.name == WatchOutcomeRecorder.recordName }
            .prefix(reservedWatchOutcomes).map(\.id))
        var selected = ordinary.filter { reserved.contains($0.id) }
        var protectedIDs = reserved
        // The store has no player owner: the newest attempt/job is the bounded
        // proxy for current viewing. Preserve it before newer lookup summaries
        // or samples consume capacity. Only the hard cap/outcome reserve may
        // clip an oversized current cohort, as in ordinary history retention.
        for key in ["attempt_id", "audio_job_id"] {
            if let current = cohorts.first(where: { $0.contains { $0.category == .playback && $0.details[key] != nil } }) {
                let unselected = current.filter { !protectedIDs.contains($0.id) }
                selected.append(contentsOf: unselected.sorted { $0.timestamp < $1.timestamp }
                    .suffix(maximumRecords - selected.count))
                protectedIDs.formUnion(current.map(\.id))
            }
        }
        for cohort in cohorts where !cohort.contains(where: { protectedIDs.contains($0.id) }) {
            if selected.count == reserved.count, cohort.count > maximumRecords - reserved.count {
                selected.append(contentsOf: cohort.sorted { $0.timestamp < $1.timestamp }
                    .suffix(maximumRecords - reserved.count))
                break
            }
            guard selected.count + cohort.count <= maximumRecords else { continue }
            selected.append(contentsOf: cohort)
        }

        let selectedIDs = Set(selected.map(\.id))
        // Each provider's newest lookup is its only sample candidate, so one
        // provider's searches never consume another's eligibility. Reversing
        // the input before a stable timestamp sort breaks equal-time ties by
        // newest append. Choose before capacity selection: never revive an
        // older sample cohort because a newer search is empty, failed, did
        // not fit, or lost its own summary to the hard cap.
        var lookupProviders = Set<String>()
        let latestLookups = records.reversed().filter {
            $0.timestamp >= cutoff && $0.category == .playback && $0.name == "provider_lookup"
                && providerLookupKey($0) != nil
        }.sorted { $0.timestamp > $1.timestamp }.filter {
            lookupProviders.insert($0.details["source_family", default: ""]).inserted
        }.filter { selectedIDs.contains($0.id) }
        let samplesByLookup = Dictionary(grouping: retained.filter(isProviderDelivery)) { providerLookupKey($0) }
        protectedIDs.formUnion(latestLookups.map(\.id))
        var retainedSampleCounts: [String: Int] = [:]
        var sampleCount = 0
        for summary in latestLookups {
            guard let key = providerLookupKey(summary), let samples = samplesByLookup[key],
                  samples.count <= StreamLookupEvidence.maximumDeliveries,
                  sampleCount + samples.count <= reservedProviderDeliveryRecords else { continue }
            // Reserve real capacity, not only leftovers. Plan whole-cohort
            // eviction first; if protected viewing leaves too little space,
            // discard this plan and yield the sample share instead.
            var removed = Set<UUID>()
            let currentIDs = Set(selected.map(\.id))
            for cohort in cohorts.reversed() where selected.count - removed.count + samples.count > maximumRecords {
                let ids = Set(cohort.map(\.id)).intersection(currentIDs)
                guard ids.isDisjoint(with: protectedIDs) else { continue }
                removed.formUnion(ids)
            }
            guard selected.count - removed.count + samples.count <= maximumRecords else { continue }
            selected.removeAll { removed.contains($0.id) }
            selected.append(contentsOf: samples)
            sampleCount += samples.count
            retainedSampleCounts[key] = samples.count
        }
        selected = selected.map { record in
            guard record.category == .playback, record.name == "provider_lookup",
                  let key = providerLookupKey(record), let value = record.details["evidence_retained_entries"],
                  let expected = Int(value), expected > retainedSampleCounts[key, default: 0] else { return record }
            var details = record.details
            details["evidence_truncated"] = "true"
            details["evidence_reconciled"] = "false"
            return .init(id: record.id, timestamp: record.timestamp, category: record.category,
                name: record.name, outcome: record.outcome, durationMilliseconds: record.durationMilliseconds,
                details: details, appVersion: record.appVersion, appBuild: record.appBuild)
        }
        return selected.sorted {
            if $0.timestamp == $1.timestamp { return positions[$0.id, default: 0] < positions[$1.id, default: 0] }
            return $0.timestamp < $1.timestamp
        }
    }

    private static func isProviderDelivery(_ record: FottyQualityRecord) -> Bool {
        record.category == .playback && record.name == "provider_delivery"
    }

    private static func providerLookupKey(_ record: FottyQualityRecord) -> String? {
        guard let provider = record.details["source_family"],
              let lookup = record.details["evidence_lookup_id"], UUID(uuidString: lookup) != nil else { return nil }
        return "\(provider):\(lookup)"
    }

    private static func validCorrelationDetail(_ key: String, value: String) -> Bool {
        if evidenceCountKeys.contains(key) {
            return Int(value).map(StreamAdmissionLedger.validCount.contains) ?? false
        }
        if StreamAdmissionLedger.countDetailKeys.contains(key) {
            return Int(value).map(StreamAdmissionLedger.validCount.contains) ?? false
        }
        if ["native_continuity_elapsed_ms", "native_continuity_media_advance_ms", "native_continuity_stalls"].contains(key) {
            return UInt32(value) != nil
        }
        switch key {
        case "evidence_schema": return value == "1"
        case "evidence_fixture", "evidence_listing", "evidence_contract":
            return value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        case "evidence_lookup_id", "evidence_generation": return UUID(uuidString: value) != nil
        case "evidence_has_name", "evidence_has_title", "evidence_truncated", "evidence_reconciled", "evidence_web_only":
            return value == "true" || value == "false"
        case "evidence_comparison": return MetadataComparison(rawValue: value) != nil
        case "evidence_disposition": return StreamAdmissionLedger.reasons.contains(value)
        case "admission_schema": return value == "1"
        case "admission_lookup_id": return UUID(uuidString: value) != nil
        case "admission_completion": return StreamAdmissionLedger.completions.contains(value)
        case "admission_observation": return ["known", "unread"].contains(value)
        case "admission_reconciled": return ["yes", "no", "unknown"].contains(value)
        case "admission_fetch_failures": return Int(value).map(StreamAdmissionLedger.validCount.contains) ?? false
        case "stream_selection_stage": return streamSelectionStages.contains(value)
        case "relay_unaliased_segment": return value == "true"
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
        case "offered_count", "admitted_count": return Int(value).map(StreamAdmissionSummary.validCount.contains) ?? false
        case "used_count": return Int(value).map { (0...500).contains($0) } ?? false
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
        case "preparation_reason":
            return PlaybackPreparationDiagnostic.Reason(rawValue: value) != nil
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
        case "discovery_initial_wait": return ["unproven_choice", "sustained_provider", "previous_failure"].contains(value)
        case "relay_failure_age_ms", "relay_request_age_ms", "relay_request_elapsed_ms", "native_startup_elapsed_ms", "native_startup_deadline_ms", "discovery_first_candidate_ms", "discovery_first_snapshot_ms":
            return Int(value).map { (0...3_600_000).contains($0) } ?? false
        case "native_item_status":
            return ["unknown", "ready", "failed", "other"].contains(value)
        case "native_time_control":
            return ["paused", "waiting", "playing", "other"].contains(value)
        case "native_wait_reason":
            return ["minimize_stalls", "evaluating_buffer", "no_item", "none", "other"].contains(value)
        case "native_buffer_empty", "native_buffer_full", "native_likely_to_keep_up":
            return ["true", "false"].contains(value)
        case "terminal_outcome": return WatchOutcomeTerminal(rawValue: value) != nil
        case "failover_count": return Int(value).map { (0...12).contains($0) } ?? false
        case "competition", "sport": return WatchOutcomeCompetition.token(value) == value
        case "failover_family": return WatchOutcomeRecorder.family(value) == value
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
