import Foundation

/// Attempt-local collection. Page-ready choices are not decoded-playback proof.
/// A slow lane must not erase a choice or failure already reported by another.
enum StreamDiscoveryCoordinator {
    static let defaultDeadline: Duration = .seconds(18)
    // Foreground CS may need its 24s descriptor slice; TV may need a 20s
    // registry refresh plus an 8s playlist. Ready siblings publish in parallel.
    static let singleExtendedMetadataDeadline: Duration = .seconds(32)

    static func discoveryDeadline(singleStreamDiscovery: Bool,
                                  optionalProviderCodes: Set<String>) -> Duration {
        singleStreamDiscovery && !optionalProviderCodes.isDisjoint(with: ["communitysports", "reviewedtv"])
            ? singleExtendedMetadataDeadline : defaultDeadline
    }

    enum Update: Sendable {
        case session(StreamSession)
        case partialSession(StreamSession)
        case failure(StreamFailure)
        case event(StreamEventRecord)
        case attempt(StreamProviderAttemptLog)
        case fairOpportunity
    }
    typealias Reporter = @Sendable (Update) -> Void
    typealias Lane = @Sendable (@escaping Reporter) async -> StreamResolutionOutcome

    struct Report {
        enum ExitReason: String { case completed, deadline, choiceGrace, cancelled }
        var sessions: [StreamSession] = []
        var failures: [StreamFailure] = []
        var timeline: [StreamEventRecord] = []
        var attempts: [StreamProviderAttemptLog] = []
        var reachedDeadline = false
        var exitReason: ExitReason = .completed
        var incompleteLanes = 0
    }

    private enum Event: Sendable {
        case update(Int, Update)
        case completed(Int, StreamResolutionOutcome)
        case deadline
        case graceEnded
        case initialChoiceGraceEnded
    }

    /// A current match failure outranks coarse host history. Conversely, an
    /// exact sustained match need not wait for a host-wide startup sample.
    static func hasCurrentDirectEvidence(_ session: StreamSession, at now: Date) -> Bool {
        guard session.playbackContract.endpoint == .directMedia,
              !session.hasExpiredMediaLease(at: now) else { return false }
        switch LiveSourceHealthStore.matchEvidence(for: session, at: now) {
        case .sustained, .recentlyPlayed: return true
        case .unknown: return LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: session.legacySource)
        case .recentlyFailed, .repeatedlyFailed, .wrongProgramme: return false
        }
    }

    static func collect(
        lanes: [Lane],
        deadline: Duration = defaultDeadline,
        choiceGrace: Duration = .milliseconds(1500),
        preferDirectInitialChoice: Bool = false,
        initialChoiceGrace: Duration = .seconds(6),
        sustainedProviderLanes: Set<Int> = [],
        clock: @escaping @Sendable () -> Date = { Date() },
        onSessions: (@Sendable ([StreamSession]) async -> Void)? = nil
    ) async -> Report {
        guard !Task.isCancelled else {
            var report = Report(); report.exitReason = .cancelled
            return report
        }
        guard !lanes.isEmpty else { return Report() }
        let (events, continuation) = AsyncStream<Event>.makeStream()
        return await withTaskGroup(of: Void.self) { group in
            defer {
                continuation.finish()
                group.cancelAll()
            }
            for (index, lane) in lanes.enumerated() {
                group.addTask {
                    let result = await lane { continuation.yield(.update(index, $0)) }
                    continuation.yield(.completed(index, result))
                }
            }
            group.addTask {
                do { try await Task.sleep(for: deadline) } catch { return }
                continuation.yield(.deadline)
            }

            var report = Report()
            var pendingSustainedLanes = sustainedProviderLanes
            var completed = 0
            var startedGrace = false
            var startedInitialChoiceGrace = false
            var initialChoiceGraceEnded = false
            var hasPublishedChoices = false
            var responded = Set<Int>()
            var seen = Set<StreamDeliveryIdentity>()
            var eventIDs = Set<UUID>()
            var attemptIDs = Set<UUID>()
            func addEvents(_ events: [StreamEventRecord]) {
                report.timeline += events.filter { eventIDs.insert($0.id).inserted }
            }
            func addAttempts(_ attempts: [StreamProviderAttemptLog]) {
                report.attempts += attempts.filter { attemptIDs.insert($0.id).inserted }
            }
            func add(_ session: StreamSession) {
                if seen.insert(StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)).inserted {
                    report.sessions.append(session)
                }
            }
            for await event in events {
                guard !Task.isCancelled else { report.exitReason = .cancelled; break }
                let previousCount = report.sessions.count
                var shouldFinish = false
                switch event {
                case .update(let index, .session(let session)):
                    responded.insert(index)
                    add(session)
                case .update(_, .partialSession(let session)): add(session)
                case .update(let index, .fairOpportunity): responded.insert(index)
                case .update(_, .failure(let failure)): report.failures.append(failure)
                case .update(_, .event(let event)): addEvents([event])
                case .update(_, .attempt(let attempt)): addAttempts([attempt])
                case .completed(let index, let outcome):
                    responded.insert(index)
                    completed += 1
                    pendingSustainedLanes.remove(index)
                    switch outcome {
                    case .success(let success):
                        success.sessions.forEach(add)
                        addEvents(success.diagnostics.timeline)
                        addAttempts(success.diagnostics.providerAttempts)
                    case .failure(let failure, let diagnostics):
                        report.failures.append(failure)
                        addEvents(diagnostics.timeline)
                        addAttempts(diagnostics.providerAttempts)
                    }
                    shouldFinish = completed == lanes.count
                case .deadline:
                    report.reachedDeadline = true
                    report.exitReason = .deadline
                    shouldFinish = true
                case .graceEnded: report.exitReason = .choiceGrace; shouldFinish = true
                case .initialChoiceGraceEnded: initialChoiceGraceEnded = true
                }
                // Serialized, append-only snapshots within the same bounded
                // owner. The consumer may start a choice without canceling the
                // slower independent lanes. Completion/error is still separate.
                // Collect the first unproven single-player choices briefly so
                // a fast listing cannot preempt a proven direct delivery. The
                // timer starts with a candidate, never with diagnostics alone.
                // Once mounted, alternatives remain append-only.
                let availableSessions = report.sessions.filter {
                    !$0.hasExpiredMediaLease(at: clock()) && (!preferDirectInitialChoice
                        || LiveSourceHealthStore.matchEvidence(for: $0, at: clock()) != .wrongProgramme)
                }
                let hasProvenDirectChoice = availableSessions.contains {
                    Self.hasCurrentDirectEvidence($0, at: clock())
                }
                // A late backup cannot win the initial ranking once a known
                // failing route has already mounted. Keep only that first pick
                // pending, within the same attempt deadline.
                let onlyPreviouslyFailed = preferDirectInitialChoice && onSessions != nil && !hasPublishedChoices && !availableSessions.isEmpty && availableSessions.allSatisfy {
                    LiveSourceHealthStore.matchEvidence(for: $0, at: clock()).rawValue >= LiveSourceHealthStore.MatchEvidence.recentlyFailed.rawValue
                }
                // Returning to the same match: let the provider that already
                // sustained it answer before mounting an unrelated early page.
                // A definitive empty completes that lane and releases the wait.
                let waitingForSustained = !pendingSustainedLanes.isEmpty && !availableSessions.contains {
                    LiveSourceHealthStore.matchEvidence(for: $0, at: clock()) == .sustained
                }
                let holdsFirstChoice = preferDirectInitialChoice && onSessions != nil && !hasPublishedChoices
                    && !availableSessions.isEmpty && (waitingForSustained || onlyPreviouslyFailed || (!hasProvenDirectChoice && !initialChoiceGraceEnded)) && !shouldFinish && completed < lanes.count && lanes.count > 1
                if holdsFirstChoice && !startedInitialChoiceGrace {
                    startedInitialChoiceGrace = true
                    group.addTask {
                        do { try await Task.sleep(for: initialChoiceGrace) } catch { return }
                        continuation.yield(.initialChoiceGraceEnded)
                    }
                }
                if !holdsFirstChoice, !availableSessions.isEmpty, !Task.isCancelled,
                   !hasPublishedChoices || availableSessions.count != previousCount {
                    await onSessions?(availableSessions)
                    hasPublishedChoices = true
                }
                if shouldFinish { break }
                // A quick shared HTML page cannot cancel a still-looking direct
                // provider. Every lane gets its first result or the common deadline.
                if !(preferDirectInitialChoice && onSessions != nil), !report.sessions.isEmpty, responded.count == lanes.count, !startedGrace {
                    startedGrace = true
                    group.addTask {
                        do { try await Task.sleep(for: choiceGrace) } catch { return }
                        continuation.yield(.graceEnded)
                    }
                }
            }
            if Task.isCancelled { report.exitReason = .cancelled }
            report.sessions.removeAll { $0.hasExpiredMediaLease(at: clock()) }
            report.incompleteLanes = lanes.count - completed
            return report
        }
    }
}

/// A catalog refresh may replace its SwiftUI task before the next90-second
/// iteration. Keep rotation and the reserved due time in view-owned state so
/// that a fresh catalog cannot repeatedly restart discovery at its first row.
struct FixtureStreamPreflightSchedule: Sendable {
    static let interval: TimeInterval = 90
    private(set) var nextDueAt: Date?
    private var rotation: [String] = []

    mutating func takeNextID(from eligibleIDs: [String], at now: Date) -> String? {
        guard now.timeIntervalSince1970.isFinite else { return nil }
        var seen = Set<String>()
        let current = eligibleIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        let available = Set(current)
        rotation.removeAll { !available.contains($0) }
        let retained = Set(rotation)
        rotation.append(contentsOf: current.filter { !retained.contains($0) })
        guard nextDueAt.map({ now >= $0 }) ?? true, !rotation.isEmpty else { return nil }
        let selected = rotation.removeFirst()
        rotation.append(selected)
        // Reserve before the caller awaits work. Cancellation or replacement
        // keeps this reservation rather than creating an immediate retry loop.
        nextDueAt = now.addingTimeInterval(Self.interval)
        return selected
    }

    func delay(at now: Date) -> TimeInterval {
        guard now.timeIntervalSince1970.isFinite, let nextDueAt, nextDueAt > now else { return Self.interval }
        return min(Self.interval, max(0.25, nextDueAt.timeIntervalSince(now)))
    }
}

/// Provider opportunities rotate independently for each accepted fixture. A
/// global cursor can alias with the fixture rotation and permanently skip a
/// provider for a particular match (for example two fixtures/four providers).
struct FixtureProviderPreflightSchedule: Sendable {
    private struct Entry: Sendable { var providers: [String]; var order: UInt64 }
    private var entries: [String: Entry] = [:]
    private var order: UInt64 = 0
    private let capacity: Int

    init(capacity: Int = 256) { self.capacity = max(1, min(capacity, 256)) }
    var retainedFixtureCount: Int { entries.count }

    mutating func takeProviders(for fixtureKey: String, available: [String], limit: Int = 2) -> [String] {
        guard !fixtureKey.isEmpty, limit > 0 else { return [] }
        var seen = Set<String>()
        let available = available.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !available.isEmpty else { entries.removeValue(forKey: fixtureKey); return [] }
        if entries[fixtureKey] == nil, entries.count >= capacity,
           let oldest = entries.min(by: { $0.value.order < $1.value.order })?.key { entries.removeValue(forKey: oldest) }
        var pending = entries[fixtureKey]?.providers.filter { available.contains($0) } ?? []
        pending += available.filter { !pending.contains($0) }
        let selected = Array(pending.prefix(min(limit, available.count)))
        pending.removeFirst(selected.count); pending += selected
        order &+= 1; entries[fixtureKey] = .init(providers: pending, order: order)
        return selected
    }
}

import Observation

/// Process-local discovery observations. A candidate is not decoded playback,
/// and neither an empty result nor a failure prevents an explicit user retry.
/// This index owns no tasks, network requests, persistent files or telemetry.
@MainActor
@Observable
final class FixtureStreamDiscoveryIndex {
    static let shared = FixtureStreamDiscoveryIndex()
    static let positiveLifetime: TimeInterval = 60
    static let preflightCooldown: TimeInterval = 90
    // This is a nonplayable observation, not permission to reuse a delivery.
    // Keep it across the shorter descriptor cache and bounded preflight rotation.
    static let priorFoundLifetime: TimeInterval = 15 * 60
    /// A recent successful descriptor lookup may keep the Watch action stable
    /// while its short-lived URL is refreshed. It never extends URL/binding life.
    nonisolated static let confirmedAvailabilityLifetime: TimeInterval = 5 * 60

    private(set) var enabledProviderCodes: Set<String> = []
    private(set) var hasLoadedProviderEnablement = false
    @ObservationIgnored private var enablementRevision: UInt64?

    enum Outcome: Equatable, Sendable {
        case checking, candidates, empty, failed(StreamFailureCategory), stale
    }

    struct ProviderSummary: Equatable, Sendable {
        let providerCode: String
        let outcome: Outcome
        let checkedAt: Date?
        let compatibleCandidateCount: Int
        let failureCategory: StreamFailureCategory?
        let lastCandidateFoundAt: Date?
        var lastConfirmedAvailableAt: Date? = nil
        /// Distinguish a completed empty/failed lookup from a successful
        /// descriptor whose URL cache has since expired.
        var lastLookupHadCandidates: Bool? = nil
        /// A completed, definitive negative observation. A timeout or failed
        /// fetch cannot withdraw an older, still-current source listing.
        var availabilityWithdrawalAt: Date? = nil

        func hasRecentlyConfirmedBroadcast(at now: Date) -> Bool {
            guard now.timeIntervalSince1970.isFinite, availabilityWithdrawalAt == nil,
                  let found = lastConfirmedAvailableAt,
                  (0..<FixtureStreamDiscoveryIndex.confirmedAvailabilityLifetime)
                    .contains(now.timeIntervalSince(found)) else { return false }
            switch outcome {
            case .candidates, .checking, .stale, .failed: return true
            case .empty: return false
            }
        }
    }

    struct Summary: Equatable, Sendable {
        let providers: [ProviderSummary]
        var compatibleCandidateCount: Int { providers.reduce(0) { $0 + $1.compatibleCandidateCount } }
        var isChecking: Bool { providers.contains { $0.outcome == .checking } }
    }

    struct Ticket: Sendable {
        let providerCode: String
        fileprivate let key: Key
        fileprivate let generation: UUID
    }

    fileprivate struct RequestKey: Hashable, Sendable {
        let fixtureID: String
        let sport: String
        let participants: [String]
        let kickoff: Date?
        let competition: String?
        let gender: String?
        let ageGroup: String?
        let cricketFormat: String?
        let cricketMatchContext: String?
        let cricketBroadcastDayIdentity: String?
        let fallbackTitle: String?
    }

    fileprivate struct Key: Hashable, Sendable {
        let request: RequestKey
        let provider: String
    }

    private struct Record {
        let request: StreamPlaybackRequest
        let startedAt: Date
        var generation: UUID?
        var completedAt: Date?
        var sessions: [StreamSession] = []
        var failure: StreamFailureCategory?
        var lastCandidateFoundAt: Date?
        var lastConfirmedAvailableAt: Date? = nil
        var availabilityWithdrawalAt: Date? = nil
        var order: UInt64
    }

    private(set) var revision: UInt64 = 0
    private var records: [Key: Record] = [:] {
        didSet { revision &+= 1 }
    }
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private var order: UInt64 = 0
    @ObservationIgnored private var highestObservedAt: Date?
    @ObservationIgnored private var lastStartedByProvider: [String: Date] = [:]
    @ObservationIgnored private var preflightStarts: [Date] = []

    init(capacity: Int = 24) { self.capacity = max(1, min(capacity, 24)) }

    var retainedRecordCount: Int { records.count }

    /// Registry snapshots are local metadata. A delayed startup read must not
    /// restore a source that a newer explicit toggle already disabled.
    func updateEnabledProviders(_ codes: Set<String>, revision: UInt64,
                                invalidating providerCode: String? = nil) {
        guard enablementRevision.map({ revision >= $0 }) ?? true else { return }
        let admitted = Set(codes.compactMap { CuratedStreamSourceCatalog.definition(forProviderCode: $0)?.providerCode })
        let revoked = enabledProviderCodes.subtracting(admitted)
        for code in revoked { invalidate(providerCode: code) }
        if let providerCode { invalidate(providerCode: providerCode) }
        enabledProviderCodes = admitted
        enablementRevision = revision
        hasLoadedProviderEnablement = true
    }

    func begin(
        for request: StreamPlaybackRequest, providerCode: String,
        preflight: Bool, at now: Date = Date()
    ) -> Ticket? {
        guard now.timeIntervalSince1970.isFinite,
              let key = key(for: request, providerCode: providerCode) else { return nil }
        let clockRegressed = highestObservedAt.map { now < $0 } ?? false
        noteTime(now)
        if preflight {
            guard !clockRegressed, ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil,
                  !records.contains(where: { $0.key.provider == key.provider && $0.value.generation != nil }),
                  records[key].map({ !isFresh($0, at: now) }) ?? true,
                  lastStartedByProvider[key.provider].map({ now.timeIntervalSince($0) >= Self.preflightCooldown }) ?? true else {
                return nil
            }
            preflightStarts.removeAll { now.timeIntervalSince($0) >= 86_400 }
            guard preflightStarts.count < 96,
                  preflightStarts.filter({ now.timeIntervalSince($0) < 3_600 }).count < 24 else { return nil }
        }
        if records[key] == nil, records.count >= capacity {
            let completed = records.filter { $0.value.generation == nil }
            let victim = (completed.isEmpty ? (preflight ? [:] : records) : completed)
                .min { $0.value.order < $1.value.order }?.key
            guard let victim else { return nil }
            records.removeValue(forKey: victim)
        }
        let generation = UUID()
        let priorFound = records[key]?.lastCandidateFoundAt
        let priorAvailability = records[key]?.lastConfirmedAvailableAt
        let priorWithdrawal = records[key]?.availabilityWithdrawalAt
        order &+= 1
        records[key] = Record(request: request, startedAt: now, generation: generation,
                              lastCandidateFoundAt: priorFound,
                              lastConfirmedAvailableAt: priorAvailability,
                              availabilityWithdrawalAt: priorWithdrawal, order: order)
        lastStartedByProvider[key.provider] = now
        if preflight { preflightStarts.append(now) }
        return Ticket(providerCode: key.provider, key: key, generation: generation)
    }

    func complete(
        _ ticket: Ticket, sessions: [StreamSession], failure: StreamFailure? = nil,
        at now: Date = Date()
    ) {
        guard now.timeIntervalSince1970.isFinite,
              var record = records[ticket.key], record.generation == ticket.generation,
              now >= record.startedAt else { return }
        noteTime(now)
        var seen = Set<StreamDeliveryIdentity>()
        record.sessions = sessions.filter { session in
            guard isAdmitted(session, for: record.request, providerCode: ticket.providerCode, at: now) else { return false }
            return seen.insert(StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)).inserted
        }.prefix(6).map { $0 }
        record.completedAt = now
        record.generation = nil
        if !record.sessions.isEmpty { record.lastCandidateFoundAt = now }
        if !record.sessions.isEmpty {
            record.lastConfirmedAvailableAt = now
            record.availabilityWithdrawalAt = nil
        } else if Self.withdrawsPriorAvailability(failure) {
            record.lastConfirmedAvailableAt = nil
            record.availabilityWithdrawalAt = now
        }
        // Unconfirmed rechecks keep only the original availability receipt,
        // never an old session or a renewed availability lifetime. They also
        // cannot erase a prior definitive negative while another check runs.
        // The reviewed descriptor explicitly returned no entries. This is
        // pending availability, not a provider outage. A rejected nonempty
        // delivery contract may share the category but keeps its own failure.
        let knownEmptyDescriptor = failure?.category == .providerReturnedEmpty
            && failure?.redactedMetadata["manifest_result"] == "stream_entries_empty"
        record.failure = knownEmptyDescriptor ? nil : failure?.category
        order &+= 1
        record.order = order
        records[ticket.key] = record
    }

    func abandon(_ ticket: Ticket) {
        guard var record = records[ticket.key], record.generation == ticket.generation else { return }
        if record.lastCandidateFoundAt != nil || record.availabilityWithdrawalAt != nil {
            // Cancelling a recheck can retain the fact of an earlier find,
            // never its expired sessions or a falsely completed new check.
            // A cancelled retry cannot erase a definitive earlier withdrawal.
            record.generation = nil
            record.completedAt = nil
            record.sessions = []
            record.failure = nil
            records[ticket.key] = record
        } else { records.removeValue(forKey: ticket.key) }
    }

    func cachedSessions(
        for request: StreamPlaybackRequest, providerCode: String, at now: Date = Date()
    ) -> [StreamSession]? {
        guard now.timeIntervalSince1970.isFinite,
              highestObservedAt.map({ now >= $0 }) ?? true,
              let key = key(for: request, providerCode: providerCode),
              let record = records[key], record.generation == nil, isFresh(record, at: now) else { return nil }
        noteTime(now)
        let sessions = record.sessions.filter {
            isAdmitted($0, for: request, providerCode: key.provider, at: now)
                && $0.eventBinding?.matches(request: request, providerCode: key.provider, at: now) == true
        }
        return sessions.isEmpty ? nil : sessions
    }

    func summary(for request: StreamPlaybackRequest, at now: Date = Date()) -> Summary? {
        guard now.timeIntervalSince1970.isFinite, let requested = requestKey(for: request) else { return nil }
        let clockRegressed = highestObservedAt.map { now < $0 } ?? false
        noteTime(now)
        let providers = CuratedStreamSourceCatalog.all.compactMap { definition -> ProviderSummary? in
            let key = Key(request: requested, provider: definition.providerCode)
            guard let record = records[key] else { return nil }
            let fresh = !clockRegressed && isFresh(record, at: now)
            let count = fresh ? record.sessions.filter {
                isAdmitted($0, for: request, providerCode: definition.providerCode, at: now)
            }.count : 0
            let outcome: Outcome
            if record.generation != nil, !clockRegressed, now >= record.startedAt { outcome = .checking }
            else if !fresh || !record.sessions.isEmpty && count == 0 { outcome = .stale }
            else if count > 0 { outcome = .candidates }
            else if let failure = record.failure { outcome = .failed(failure) }
            else { outcome = .empty }
            let priorFound = record.lastCandidateFoundAt.flatMap { found in
                !clockRegressed && (0..<Self.priorFoundLifetime).contains(now.timeIntervalSince(found)) ? found : nil
            }
            return ProviderSummary(providerCode: definition.providerCode, outcome: outcome,
                checkedAt: record.completedAt, compatibleCandidateCount: count, failureCategory: record.failure,
                lastCandidateFoundAt: priorFound,
                lastConfirmedAvailableAt: clockRegressed ? nil : record.lastConfirmedAvailableAt,
                lastLookupHadCandidates: clockRegressed ? nil : record.completedAt.map { _ in !record.sessions.isEmpty },
                availabilityWithdrawalAt: clockRegressed ? nil : record.availabilityWithdrawalAt)
        }
        return providers.isEmpty ? nil : Summary(providers: providers)
    }

    func invalidate(providerCode: String) {
        guard let provider = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode)?.providerCode else { return }
        records = records.filter { $0.key.provider != provider }
        // Cooldowns and spent budgets survive invalidation. Disabling and
        // enabling a source must not reset proactive request limits.
    }

    private func key(for request: StreamPlaybackRequest, providerCode: String) -> Key? {
        guard let provider = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode)?.providerCode,
              let request = requestKey(for: request) else { return nil }
        return Key(request: request, provider: provider)
    }

    private func requestKey(for request: StreamPlaybackRequest) -> RequestKey? {
        guard !request.matchID.isEmpty, request.matchID.utf8.count <= 512,
              request.preferredEvent?.hasCatalogIdentityConflict != true,
              request.kickoffDate.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { return nil }
        let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: request)
        return RequestKey(fixtureID: request.matchID,
            sport: identity?.sport ?? ReviewedSportsFixtureMatcher.sportKey(request.category),
            participants: identity?.pair ?? [request.homeTeam, request.awayTeam],
            kickoff: request.kickoffDate, competition: request.preferredEvent?.competitionID,
            gender: request.preferredEvent?.sportsFixture?.squad.gender.rawValue,
            ageGroup: request.preferredEvent?.sportsFixture?.squad.ageGroup,
            cricketFormat: request.preferredEvent?.cricketFixture?.format.rawValue,
            cricketMatchContext: identity?.sport == "cricket" ? request.displayTitle : nil,
            cricketBroadcastDayIdentity: request.preferredEvent?.cricketFixture?.broadcastDayIdentity,
            fallbackTitle: identity == nil ? request.displayTitle : nil)
    }

    private func isFresh(_ record: Record, at now: Date) -> Bool {
        guard let completedAt = record.completedAt else { return false }
        return (0..<Self.positiveLifetime).contains(now.timeIntervalSince(completedAt))
    }

    private static func withdrawsPriorAvailability(_ failure: StreamFailure?) -> Bool {
        guard let failure else { return true } // A completed, known-empty lookup.
        switch failure.category {
        case .providerSecurityFailure:
            // TLS failure prevented a trustworthy response; it is not an
            // advertised unsafe delivery. All transport guards remain intact.
            return failure.redactedMetadata["transport_result"] != "provider_security_failure"
        case .providerReturnedEmpty, .invalidMatchMapping, .invalidURL, .unsupportedScheme,
             .authFailed, .leaseExpired:
            return true
        default:
            // An explicit rejection of this literal event/descriptor differs
            // from a failed manifest/catalog fetch or a transient HTTP error.
            return ["metadata_http_failure", "streams_http_failure"].contains(failure.redactedMetadata["manifest_result"] ?? "")
                && ["401", "403", "404", "410", "451"].contains(failure.redactedMetadata["platform_error_code"] ?? "")
        }
    }

    private func isAdmitted(
        _ session: StreamSession, for request: StreamPlaybackRequest, providerCode: String, at now: Date
    ) -> Bool {
        guard session.matchID == request.matchID, session.validationStatus == .validated,
              StreamPluginProviderMatching.isActivePlayerSession(session),
              StreamEventBinding.providerCode(forSessionProviderName: session.providerName) == providerCode,
              !session.hasExpiredMediaLease(at: now) else { return false }
        return session.eventBinding.map { $0.matches(request: request, providerCode: providerCode, at: now) } ?? true
    }

    private func noteTime(_ now: Date) {
        if highestObservedAt.map({ now > $0 }) ?? true { highestObservedAt = now }
    }
}

/// Metadata from a reviewed source's bounded catalog evaluation. A listing is
/// neither a stream descriptor nor permission to advertise Watch.
struct FixtureSourceCatalogMatch: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case listed, needsVerification, notListed, conflicting, unsupported
        case failed(StreamFailureCategory)
    }
    let matchID: String
    let outcome: Outcome
    let providerEventID: String?
    // Imported cloud evidence keeps its original observation and finite expiry.
    // Re-reading the same cached snapshot cannot create a fresh source receipt.
    let evidenceObservedAt: Date?
    let evidenceValidUntil: Date?

    init(matchID: String, outcome: Outcome, providerEventID: String? = nil,
         evidenceObservedAt: Date? = nil, evidenceValidUntil: Date? = nil) {
        self.matchID = matchID; self.outcome = outcome; self.providerEventID = providerEventID
        self.evidenceObservedAt = evidenceObservedAt; self.evidenceValidUntil = evidenceValidUntil
    }
}

/// Scene-shared, process-local catalog evidence. This owns no tasks, transport,
/// sessions, media URLs, settings, persistence, or playback actions.
@MainActor
@Observable
final class FixtureCatalogAvailabilityIndex {
    static let shared = FixtureCatalogAvailabilityIndex()
    static let maximumFixtures = 256
    static let metadataLifetime: TimeInterval = 120
    static let priorListedLifetime: TimeInterval = 15 * 60
    static let minimumRefreshInterval: TimeInterval = 300

    enum Outcome: Sendable, Equatable {
        case checking, listed, needsVerification, notListed, conflicting, unsupported
        case failed(StreamFailureCategory), stale
    }

    struct ProviderSummary: Sendable, Equatable {
        let providerCode: String
        let outcome: Outcome
        let checkedAt: Date?
        let providerEventID: String?
        let previouslyListed: Bool
    }

    struct Summary: Sendable, Equatable {
        let providers: [ProviderSummary]
        var listedProviderCount: Int { providers.filter { $0.outcome == .listed }.count }
        var isChecking: Bool { providers.contains { $0.outcome == .checking } }
        var previouslyListed: Bool { providers.contains( where: \.previouslyListed) }
        var needsVerification: Bool {
            providers.contains {
                switch $0.outcome {
                case .needsVerification, .conflicting, .failed, .stale: true
                default: false
                }
            }
        }
    }

    struct Ticket: Sendable {
        let providerCode: String
        fileprivate let generation: UUID
        fileprivate let settingsRevision: UInt64
        fileprivate let fixtures: [String: FixtureKey]
        fileprivate let startedAt: Date
        fileprivate var cloudImport: CloudImportStamp? = nil
    }

    fileprivate struct CloudImportStamp: Sendable, Equatable {
        let settingsRevision: UInt64
        let fixtures: [String: FixtureKey]
        let matches: [FixtureSourceCatalogMatch]
    }

    fileprivate struct FixtureKey: Hashable, Sendable {
        let id: String
        let sport: String
        let pair: [String]
        let kickoff: Date
        let competition: String?
        let gender: String?
        let ageGroup: String?
        let cricketFormat: String?
        let cricketContext: String?
        let cricketBroadcastDayIdentity: String?
        let status: String
    }

    private struct FixtureAuthority {
        let key: FixtureKey
        let expiresAt: Date?
        let freshAfterStartUntil: Date?
        let estimatedEndAt: Date?
    }

    private struct RecordKey: Hashable { let fixture: FixtureKey; let provider: String }
    private struct Record {
        let outcome: Outcome
        let checkedAt: Date
        let providerEventID: String?
        let lastListedAt: Date?
        let evidenceValidUntil: Date?
    }

    private(set) var enabledProviderCodes: Set<String> = []
    private(set) var hasLoadedProviderEnablement = false
    private(set) var enablementRevision: UInt64 = 0
    private(set) var revision: UInt64 = 0
    private var records: [RecordKey: Record] = [:]
    private var pending: [String: Ticket] = [:]
    @ObservationIgnored private var fixtures: [String: FixtureAuthority] = [:]
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private var highestObservedAt: Date?
    @ObservationIgnored private var lastStarted: [String: Date] = [:]
    @ObservationIgnored private var starts: [String: [Date]] = [:]
    @ObservationIgnored private var lastCloudImports: [String: CloudImportStamp] = [:]

    init(capacity: Int = 256) { self.capacity = max(1, min(capacity, Self.maximumFixtures)) }
    var retainedRecordCount: Int { records.count }
    var fixtureCount: Int { fixtures.count }

    func updateEnabledProviders(_ codes: Set<String>, revision incoming: UInt64,
                                invalidating providerCode: String? = nil) {
        guard !hasLoadedProviderEnablement || incoming >= enablementRevision else { return }
        let admitted = Set(codes.compactMap { CuratedStreamSourceCatalog.definition(forProviderCode: $0)?.providerCode })
        guard !hasLoadedProviderEnablement || incoming != enablementRevision || admitted != enabledProviderCodes
                || providerCode != nil else { return }
        let revoked = enabledProviderCodes.subtracting(admitted)
        records = records.filter { !revoked.contains($0.key.provider) && $0.key.provider != providerCode }
        // Even disable/re-enable to the same code set cannot revive a delayed
        // batch. Spent cadence/budgets deliberately survive these revocations.
        pending.removeAll()
        enabledProviderCodes = admitted; enablementRevision = incoming
        hasLoadedProviderEnablement = true
        revision &+= 1
    }

    func replaceFixtures(_ requests: [StreamPlaybackRequest], at now: Date = .init()) {
        guard acceptsTime(now) else { return }
        var admitted: [String: FixtureAuthority] = [:], duplicateIDs = Set<String>()
        // The host supplies a priority-ordered bounded official registry. Scan
        // duplicates before capping, rather than hiding a contradictory tail.
        if requests.count <= 4_000 {
            var seen = Set<String>()
            for request in requests {
                if !seen.insert(request.matchID).inserted { duplicateIDs.insert(request.matchID) }
            }
            for request in requests where !duplicateIDs.contains(request.matchID) && admitted.count < capacity {
                if let authority = Self.authority(for: request, at: now) { admitted[request.matchID] = authority }
            }
        }
        let keys = Set(admitted.values.map(\.key))
        records = records.filter { keys.contains($0.key.fixture) }
        fixtures = admitted
        revision &+= 1
    }

    func begin(providerCode raw: String, at now: Date = .init()) -> Ticket? {
        guard acceptsTime(now), let provider = CuratedStreamSourceCatalog.definition(forProviderCode: raw)?.providerCode,
              enabledProviderCodes.contains(provider), pending[provider] == nil,
              lastStarted[provider].map({ now.timeIntervalSince($0) >= Self.minimumRefreshInterval }) ?? true else { return nil }
        let current = fixtures.filter { isCurrent($0.value.key, at: now) }.mapValues(\.key)
        guard !current.isEmpty else { return nil }
        let recent = (starts[provider] ?? []).filter { now.timeIntervalSince($0) < 86_400 }
        starts[provider] = recent
        guard recent.count < 96, recent.filter({ now.timeIntervalSince($0) < 3_600 }).count < 24 else { return nil }
        let ticket = Ticket(providerCode: provider, generation: UUID(), settingsRevision: enablementRevision,
                            fixtures: current, startedAt: now)
        pending[provider] = ticket
        lastStarted[provider] = now; starts[provider, default: []].append(now)
        revision &+= 1
        return ticket
    }

    /// Importing an already accepted cloud receipt performs no provider HTTP.
    /// It therefore does not spend or inherit the local request reservation.
    /// Exact source facts, fixture keys and settings deduplicate cached imports.
    func beginCloudImport(providerCode raw: String, matches: [FixtureSourceCatalogMatch],
                          requests: [StreamPlaybackRequest], at now: Date = .init()) -> Ticket? {
        guard acceptsTime(now), requests.count <= Self.maximumFixtures,
              matches.count <= Self.maximumFixtures, Set(matches.map(\.matchID)).count == matches.count,
              let provider = CuratedStreamSourceCatalog.definition(forProviderCode: raw)?.providerCode,
              enabledProviderCodes.contains(provider), pending[provider] == nil else { return nil }
        let requested = Dictionary(requests.compactMap { request in
            Self.authority(for: request, at: now).map { (request.matchID, $0.key) }
        }, uniquingKeysWith: { first, _ in first })
        let current = fixtures.filter {
            requested[$0.key] == $0.value.key && isCurrent($0.value.key, at: now)
        }.mapValues(\.key)
        let receipt = matches.filter { current[$0.matchID] != nil }.sorted { $0.matchID < $1.matchID }
        guard !current.isEmpty, !receipt.isEmpty, receipt.allSatisfy({
            $0.evidenceObservedAt?.timeIntervalSince1970.isFinite == true
                && $0.evidenceValidUntil?.timeIntervalSince1970.isFinite == true
        }) else { return nil }
        guard receipt.contains(where: { row in
            guard let fixture = current[row.matchID],
                  let previous = records[RecordKey(fixture: fixture, provider: provider)] else { return true }
            return row.evidenceObservedAt! >= previous.checkedAt
        }) else { return nil }
        let stamp = CloudImportStamp(settingsRevision: enablementRevision, fixtures: current, matches: receipt)
        guard lastCloudImports[provider] != stamp else { return nil }
        var ticket = Ticket(providerCode: provider, generation: UUID(), settingsRevision: enablementRevision,
                            fixtures: current, startedAt: now)
        ticket.cloudImport = stamp
        pending[provider] = ticket
        revision &+= 1
        return ticket
    }

    func complete(_ ticket: Ticket, matches: [FixtureSourceCatalogMatch], at now: Date = .init()) {
        guard accepts(ticket, at: now), matches.count <= Self.maximumFixtures * 2 else { return }
        let grouped = Dictionary(grouping: matches.filter { ticket.fixtures[$0.matchID] != nil }, by: \.matchID)
        let IDs = Dictionary(grouping: matches.filter { $0.outcome == .listed && Self.safeProviderID($0.providerEventID) != nil },
                             by: { $0.providerEventID! })
        for (id, key) in ticket.fixtures where isCurrent(key, at: now) {
            let rows = grouped[id] ?? []
            let row = rows.first
            let conflictingRows = row.map { first in rows.contains { $0 != first } } ?? false
            let reusedID = row?.providerEventID.flatMap { IDs[$0] }.map { Set($0.map(\.matchID)).count > 1 } ?? false
            let outcome: Outcome
            if conflictingRows || reusedID { outcome = .conflicting }
            else if let row {
                if row.providerEventID != nil && Self.safeProviderID(row.providerEventID) == nil { outcome = .needsVerification }
                else {
                    switch row.outcome {
                    case .listed: outcome = .listed
                    case .needsVerification: outcome = .needsVerification
                    case .notListed: outcome = .notListed
                    case .conflicting: outcome = .conflicting
                    case .unsupported: outcome = .unsupported
                    case .failed(let category): outcome = .failed(category)
                    }
                }
            } else { outcome = .needsVerification }
            store(outcome, for: key, provider: ticket.providerCode,
                  providerEventID: outcome == .listed ? Self.safeProviderID(row?.providerEventID) : nil, at: now,
                  evidenceObservedAt: row?.evidenceObservedAt, evidenceValidUntil: row?.evidenceValidUntil)
        }
        if let stamp = ticket.cloudImport { lastCloudImports[ticket.providerCode] = stamp }
        pending.removeValue(forKey: ticket.providerCode)
        revision &+= 1
    }

    func fail(_ ticket: Ticket, category: StreamFailureCategory, at now: Date = .init()) {
        guard accepts(ticket, at: now) else { return }
        for key in ticket.fixtures.values where isCurrent(key, at: now) {
            store(.failed(category), for: key, provider: ticket.providerCode, providerEventID: nil, at: now)
        }
        pending.removeValue(forKey: ticket.providerCode)
        revision &+= 1
    }

    func abandon(_ ticket: Ticket) {
        guard pending[ticket.providerCode]?.generation == ticket.generation else { return }
        pending.removeValue(forKey: ticket.providerCode)
        revision &+= 1
    }

    func summary(for request: StreamPlaybackRequest, at now: Date = .init()) -> Summary? {
        guard acceptsTime(now), let key = Self.authority(for: request, at: now)?.key, isCurrent(key, at: now) else { return nil }
        let providers = CuratedStreamSourceCatalog.all.compactMap { definition -> ProviderSummary? in
            let code = definition.providerCode
            guard enabledProviderCodes.contains(code) else { return nil }
            let record = records[.init(fixture: key, provider: code)]
            let checking = pending[code].map { $0.fixtures[request.matchID] == key } ?? false
            guard record != nil || checking else { return nil }
            let fresh = record.map {
                (0..<Self.metadataLifetime).contains(now.timeIntervalSince($0.checkedAt))
                    && ($0.evidenceValidUntil.map { $0 > now } ?? true)
            } ?? false
            let previouslyListed = record?.lastListedAt.map {
                (0..<Self.priorListedLifetime).contains(now.timeIntervalSince($0))
            } ?? false
            return ProviderSummary(providerCode: code, outcome: checking ? .checking : fresh ? record!.outcome : .stale,
                checkedAt: record?.checkedAt, providerEventID: fresh && !checking ? record?.providerEventID : nil,
                previouslyListed: previouslyListed)
        }
        return providers.isEmpty ? nil : .init(providers: providers)
    }

    /// A provider response can keep the shared catalog current even when the
    /// primary directory fails. This is transport/catalog evidence only, never
    /// a playable-session TTL or permission to reuse a delivery URL.
    func hasRecentSuccessfulCatalogEvaluation(for requests: [StreamPlaybackRequest], at now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite,
              highestObservedAt.map({ now >= $0 }) ?? true else { return false }
        for request in requests.prefix(32) {
            guard let key = Self.authority(for: request, at: now)?.key, isCurrent(key, at: now) else { continue }
            for provider in enabledProviderCodes {
                guard let record = records[.init(fixture: key, provider: provider)],
                      (0..<(Self.minimumRefreshInterval + 60)).contains(now.timeIntervalSince(record.checkedAt)),
                      record.evidenceValidUntil.map({ $0 > now }) ?? true else { continue }
                if record.outcome == .listed || record.outcome == .notListed { return true }
            }
        }
        return false
    }

    private func acceptsTime(_ now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite, highestObservedAt.map({ now >= $0 }) ?? true else { return false }
        highestObservedAt = now
        return true
    }

    private func accepts(_ ticket: Ticket, at now: Date) -> Bool {
        acceptsTime(now) && now >= ticket.startedAt && enabledProviderCodes.contains(ticket.providerCode)
            && ticket.settingsRevision == enablementRevision
            && pending[ticket.providerCode]?.generation == ticket.generation
    }

    private func isCurrent(_ key: FixtureKey, at now: Date) -> Bool {
        guard let current = fixtures[key.id], current.key == key else { return false }
        if current.estimatedEndAt.map({ now >= $0 }) == true { return false }
        let expiry = key.status == "scheduled" && key.kickoff < now ? current.freshAfterStartUntil : current.expiresAt
        return expiry.map { $0 > now } ?? true
    }

    private func store(_ outcome: Outcome, for fixture: FixtureKey, provider: String,
                       providerEventID: String?, at now: Date,
                       evidenceObservedAt: Date? = nil, evidenceValidUntil: Date? = nil) {
        let key = RecordKey(fixture: fixture, provider: provider)
        let imported = evidenceObservedAt != nil || evidenceValidUntil != nil
        let validImport = evidenceObservedAt.map { $0.timeIntervalSince1970.isFinite } == true
            && evidenceValidUntil.map { $0.timeIntervalSince1970.isFinite && $0 > now } == true
        let checkedAt = imported ? evidenceObservedAt ?? now : now
        if imported, let previous = records[key], checkedAt < previous.checkedAt { return }
        var expiry = imported ? evidenceValidUntil ?? .distantPast : nil
        if imported, let previous = records[key], previous.checkedAt == checkedAt,
           let previousExpiry = previous.evidenceValidUntil, let proposed = expiry, proposed > previousExpiry {
            expiry = previousExpiry
        }
        let acceptedOutcome: Outcome = imported && !validImport ? .stale : outcome
        records[key] = Record(outcome: acceptedOutcome, checkedAt: checkedAt, providerEventID: providerEventID,
            lastListedAt: acceptedOutcome == .listed ? checkedAt : records[key]?.lastListedAt,
            evidenceValidUntil: expiry)
    }

    private static func safeProviderID(_ value: String?) -> String? {
        safeOpaqueID(value, maximumCharacters: 240)
    }

    private static func safeOpaqueID(_ value: String?, maximumCharacters: Int) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:~-"))
        guard let value, !value.isEmpty, value.count <= maximumCharacters, value.utf8.count <= 4096,
              value.unicodeScalars.first.map(CharacterSet.alphanumerics.contains) == true,
              value.unicodeScalars.allSatisfy(allowed.contains),
              value.range(of: #"^(?:https?|file|data|javascript):"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return value
    }

    private static func authority(for request: StreamPlaybackRequest, at now: Date) -> FixtureAuthority? {
        guard let event = request.preferredEvent, !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
              event.id == request.matchID, safeOpaqueID(request.matchID, maximumCharacters: 256) != nil,
              let kickoff = request.kickoffDate, kickoff.timeIntervalSince1970.isFinite, event.kickoffDate == kickoff,
              kickoff <= now.addingTimeInterval(SportsSearchSchedule.futureHorizon),
              let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return nil }
        let status: String, expiresAt: Date?, freshAfterStartUntil: Date?
        if let fixture = event.sportsFixture {
            guard event.cricketFixture == nil, fixture.verified, fixture.fixtureID == event.id,
                  fixture.sport == identity.sport, [.scheduled, .live].contains(fixture.status) else { return nil }
            let future = fixture.status == .scheduled && kickoff >= now
            let freshness = future ? SportsSearchSchedule.receiptFreshness : SportsFixtureCatalog.statusFreshness
            guard !event.isPastEstimatedMatchWindow(at: now),
                  (-300...freshness).contains(now.timeIntervalSince(fixture.identityReceipt)) else { return nil }
            status = fixture.status.rawValue; expiresAt = fixture.identityReceipt.addingTimeInterval(freshness)
            freshAfterStartUntil = fixture.identityReceipt.addingTimeInterval(SportsFixtureCatalog.statusFreshness)
        } else if let fixture = event.cricketFixture {
            guard fixture.verified, event.id == CricketFixtureCatalog.fixtureIDPrefix + fixture.fixtureID,
                  identity.sport == "cricket", fixture.format != .unknown, [.scheduled, .live].contains(fixture.status) else { return nil }
            let future = fixture.status == .scheduled && kickoff >= now
            let freshness = future ? SportsSearchSchedule.receiptFreshness : CricketFixtureCatalog.statusFreshness
            guard !event.isPastEstimatedMatchWindow(at: now),
                  (-300...freshness).contains(now.timeIntervalSince(fixture.observedAt)) else { return nil }
            status = fixture.status.rawValue; expiresAt = fixture.observedAt.addingTimeInterval(freshness)
            freshAfterStartUntil = fixture.observedAt.addingTimeInterval(CricketFixtureCatalog.statusFreshness)
        } else {
            // CPL's separate, freshly verified schedule is filtered by the
            // registry host; an arbitrary title containing CPL cannot enter.
            guard identity.sport == "cricket", CPLSchedule.isManagedFixtureID(event.id),
                  !event.isPastEstimatedMatchWindow(at: now) else { return nil }
            status = "cpl-schedule"; expiresAt = nil; freshAfterStartUntil = nil
        }
        return .init(key: .init(id: event.id, sport: identity.sport, pair: identity.pair, kickoff: kickoff,
            competition: event.sportsFixture?.competitionID ?? event.cricketFixture?.competitionID ?? event.competitionID,
            gender: event.sportsFixture?.squad.gender.rawValue, ageGroup: event.sportsFixture?.squad.ageGroup,
            cricketFormat: event.cricketFixture?.format.rawValue,
            cricketContext: identity.sport == "cricket" ? request.displayTitle : nil,
            cricketBroadcastDayIdentity: event.cricketFixture?.broadcastDayIdentity, status: status), expiresAt: expiresAt,
            freshAfterStartUntil: freshAfterStartUntil, estimatedEndAt: event.estimatedMatchDuration.map { kickoff.addingTimeInterval($0) })
    }
}
