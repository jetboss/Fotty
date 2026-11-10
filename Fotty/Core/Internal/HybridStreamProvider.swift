import Foundation

/// A mounted player's immutable receipt may age while its exact fixture keeps
/// receiving verified updates. Only a fresh equivalent admission can authorize
/// descriptor recovery; corrections, terminal facts and Test-day changes veto.
@MainActor
enum RegisteredDescriptorRecoveryPolicy {
    static func currentRequest(for original: StreamPlaybackRequest, in catalog: [EventReference],
                               at now: Date = Date()) -> StreamPlaybackRequest? {
        guard let old = original.preferredEvent, old.id == original.matchID,
              !old.hasCatalogIdentityConflict,
              let current = CurrentEventBroadcastPolicy.currentEvent(for: old, in: catalog, at: now),
              current.id == old.id, !current.hasCatalogIdentityConflict,
              current.kickoffDate == old.kickoffDate,
              current.normalizedCategory == old.normalizedCategory,
              (current.competitionID ?? current.cricketFixture?.competitionID)
                == (old.competitionID ?? old.cricketFixture?.competitionID),
              CatalogPlaybackIdentity.matchingEvent(for: original, in: [current]) != nil,
              CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: current), in: [old]) != nil,
              MatchStartPolicy(event: current, now: now).timingAllowsPlayback else { return nil }
        if let oldSports = old.sportsFixture {
            // An unchanged schedule retains its publisher's old status-change
            // time. Watch already admits its freshly checked identity; recovery
            // must use the same receipt without upgrading that status to LIVE.
            guard let fresh = current.sportsFixture, current.cricketFixture == nil, fresh.verified,
                  fresh.fixtureID == oldSports.fixtureID, fresh.squad == oldSports.squad,
                  Set(fresh.participants.map(\.id)) == Set(oldSports.participants.map(\.id)),
                  [.scheduled, .live].contains(fresh.status),
                  (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(
                    fresh.status == .scheduled ? fresh.identityReceipt : fresh.observedAt)) else { return nil }
        } else if let oldCricket = old.cricketFixture {
            guard let fresh = current.cricketFixture, current.sportsFixture == nil, fresh.verified,
                  fresh.fixtureID == oldCricket.fixtureID, fresh.format == oldCricket.format,
                  fresh.homeTeamID == oldCricket.homeTeamID, fresh.awayTeamID == oldCricket.awayTeamID,
                  fresh.broadcastDayIdentity == oldCricket.broadcastDayIdentity,
                  [.scheduled, .live].contains(fresh.status),
                  (-300...CricketFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(fresh.observedAt)) else { return nil }
        } else if CricketBroadcastChannel.identifying(request: StreamPlaybackRequest(event: current)) == nil
                    && SportsTVStation.identifying(StreamPlaybackRequest(event: current)) == nil { return nil }
        return StreamPlaybackRequest(event: current, watchID: original.watchID)
    }
}

/// Emits at most one CS discovery receipt per owned resolution. Admission and
/// cancellation remain the resolver's job; recording never starts network work.
enum CommunitySportsDiscoveryQuality {
    struct Receipt: Equatable {
        let outcome: FottyQualityOutcome
        let durationMilliseconds: Int?
        let details: [String: String]
    }

    static func receipt(_ report: StreamDiscoveryCoordinator.Report, attemptID: String,
                        providerName: String = "CS", sourceFamily: String = "communitysports") -> Receipt? {
        guard UUID(uuidString: attemptID) != nil else { return nil }
        let attempt = report.attempts.last { $0.providerName == providerName }
        let events = report.timeline.filter { $0.providerName == providerName }
        guard attempt != nil || !events.isEmpty else { return nil }
        var details = ["mode": "source_discovery", "source_family": sourceFamily,
                       "attempt_id": attemptID, "stage": "preparing"]
        let outcome: FottyQualityOutcome
        if let attempt,
           ![StreamFailureCategory.navigationCancelled, .duplicateRequestCancelled, .userCancelled]
            .contains(where: { $0 == attempt.finalFailureCategory }) {
            // A terminal CS result is not cancelled retroactively when the user
            // cancels a still-pending sibling after CS has already completed.
            outcome = attempt.finalFailureCategory == nil ? .success : .failure
            details["result"] = attempt.manifestResult ?? "discovery_completed"
            if let category = attempt.finalFailureCategory {
                details["failure_kind"] = category.rawValue
                let metadata = events.last(where: { $0.failureCategory != nil })?.redactedMetadata ?? [:]
                if let code = metadata["platform_error_code"] {
                    details["platform_error_code"] = code
                }
                let countKeys = providerName == "CS"
                    ? ["cs_stream_entry_count", "cs_admission_rejected_count"]
                    : ["addon_stream_entry_count", "addon_admission_rejected_count"]
                for key in countKeys {
                    if let value = metadata[key], let count = Int(value), (0...100).contains(count) {
                        details[key] = String(count)
                    }
                }
            }
        } else if report.exitReason == .cancelled {
            outcome = .info
            details["result"] = "discovery_cancelled"
        } else if attempt != nil {
            outcome = .info
            details["result"] = "discovery_cancelled"
        } else if report.reachedDeadline {
            outcome = .failure
            details["result"] = "discovery_deadline"
            details["failure_kind"] = StreamFailureCategory.providerTimeout.rawValue
        } else {
            outcome = .info
            details["result"] = "discovery_incomplete"
        }
        let duration = attempt.flatMap { (0...3_600_000).contains($0.responseTimeMs) ? $0.responseTimeMs : nil }
        return Receipt(outcome: outcome, durationMilliseconds: duration, details: details)
    }

    static func record(_ report: StreamDiscoveryCoordinator.Report, attemptID: String,
                       store: FottyQualityStore = .shared) {
        guard let receipt = receipt(report, attemptID: attemptID) else { return }
        store.record(category: .playback, name: "source_discovery_result", outcome: receipt.outcome,
                     durationMilliseconds: receipt.durationMilliseconds, details: receipt.details)
    }
}

/// A separate receipt keeps AS failures visible without overwriting CS evidence.
enum AdditionalSportsDiscoveryQuality {
    static func record(_ report: StreamDiscoveryCoordinator.Report, attemptID: String,
                       store: FottyQualityStore = .shared) {
        guard let receipt = CommunitySportsDiscoveryQuality.receipt(report, attemptID: attemptID,
            providerName: "AS", sourceFamily: StreamPluginProviderMatching.plavioSportsProviderCode) else { return }
        store.record(category: .playback, name: "source_discovery_result", outcome: receipt.outcome,
                     durationMilliseconds: receipt.durationMilliseconds, details: receipt.details)
    }
}

/// LivXow discovery stays distinguishable from both optional sibling add-ons.
enum CNCSportsDiscoveryQuality {
    static func record(_ report: StreamDiscoveryCoordinator.Report, attemptID: String,
                       store: FottyQualityStore = .shared) {
        guard let receipt = CommunitySportsDiscoveryQuality.receipt(report, attemptID: attemptID,
            providerName: "LS", sourceFamily: StreamPluginProviderMatching.cncSportsProviderCode) else { return }
        store.record(category: .playback, name: "source_discovery_result", outcome: receipt.outcome,
                     durationMilliseconds: receipt.durationMilliseconds, details: receipt.details)
    }
}

/// A discovery receipt is not a decoded-playback or fixture-status claim.
enum FlixStreamsDiscoveryQuality {
    static func record(_ report: StreamDiscoveryCoordinator.Report, attemptID: String,
                       store: FottyQualityStore = .shared) {
        guard let receipt = CommunitySportsDiscoveryQuality.receipt(report, attemptID: attemptID,
            providerName: "FS", sourceFamily: StreamPluginProviderMatching.flixStreamsProviderCode) else { return }
        store.record(category: .playback, name: "source_discovery_result", outcome: receipt.outcome,
                     durationMilliseconds: receipt.durationMilliseconds, details: receipt.details)
    }
}

actor LiveStreamResolver {
    static let shared = LiveStreamResolver()

    private let validationSession: URLSession
    private var preflightProviderSchedule = FixtureProviderPreflightSchedule()

    init(validationConfiguration: URLSessionConfiguration? = nil) {
        let configuration = validationConfiguration ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        validationSession = URLSession(configuration: configuration)
    }

    // Mirrors and candidate retries already get bounded opportunities. Do not
    // restart the entire shared catalog scan inside the common discovery clock.

    func resolvePlayback(
        for request: StreamPlaybackRequest,
        singleStreamDiscovery: Bool = false,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)? = nil
    ) async -> StreamResolutionOutcome {
        await resolvePlayback(for: request, onChoices: nil,
            singleStreamDiscovery: singleStreamDiscovery, onProgress: onProgress)
    }

    /// Incremental choices are opt-in for the scene-owned single-player path.
    /// Existing aggregate callers retain their original API and completion.
    func resolvePlayback(
        for request: StreamPlaybackRequest,
        onChoices: (@Sendable ([StreamSession]) async -> Void)?,
        singleStreamDiscovery: Bool = true,
        refreshOptionalSources: Bool = false,
        onProgress: (@Sendable (StreamAttemptProgress) async -> Void)? = nil
    ) async -> StreamResolutionOutcome {
        let attemptID = UUID().uuidString
        let startedAt = Date()
        if singleStreamDiscovery, let watchID = request.watchID {
            FottyQualityStore.shared.record(category: .playback, name: "watch_discovery_started", outcome: .info,
                details: ["watch_session_id": watchID.uuidString, "attempt_id": attemptID, "route": "single"])
        }
        if request.preferredEvent?.hasCatalogIdentityConflict == true {
            let failure = StreamFailure(providerName: nil, category: .invalidMatchMapping,
                technicalMessage: "Provider catalog supplied conflicting identities for this event ID.",
                userMessage: "This broadcast listing has conflicting match details. Please refresh the schedule.",
                retryable: false, fallbackAllowed: false,
                redactedMetadata: ["identity_result": "quarantined_catalog_id"])
            var timeline: [StreamEventRecord] = []
            appendEvent(to: &timeline, name: .provider1ValidationFailed, request: request,
                attemptID: attemptID, providerName: nil, currentState: .failed,
                failureCategory: .invalidMatchMapping, redactedMetadata: failure.redactedMetadata)
            let diagnostics = makeDiagnostics(attemptID: attemptID, request: request, finalState: .failed,
                timeline: timeline, providerAttempts: [], startedAt: startedAt)
            await recordDiagnostics(diagnostics)
            return .failure(failure, diagnostics)
        }
        let enabled = await StreamPluginRegistry.shared.enabledProviderCodes()
        let foregroundTVLookup = singleStreamDiscovery && onChoices != nil
        let plan = await CuratedStreamSourceCatalog.discoveryPlan(for: request,
            enabledProviderCodes: Set(enabled), allowDeferredTVLookup: foregroundTVLookup)
        var lanes: [StreamDiscoveryCoordinator.Lane] = []
        if plan.score808SiteEligible {
            lanes.append { report in
                await self.resolveScore808Site(for: request, attemptID: attemptID, report: report,
                    useRegistry: singleStreamDiscovery)
            }
        }
        let sustainedProviders = foregroundTVLookup && request.preferredEvent?.isBroadcastChannel == false
            ? LiveSourceHealthStore.sustainedMatchProviders(for: request.matchID) : []
        var sustainedLanes = Set<Int>()
        for source in plan.optionalSources {
            if sustainedProviders.contains(source.providerCode) { sustainedLanes.insert(lanes.count) }
            lanes.append { report in
                await self.resolveOptionalSports(for: request, attemptID: attemptID,
                    source: source, report: report, useDiscoveryIndex: singleStreamDiscovery,
                    refreshTVRegistry: foregroundTVLookup,
                    refreshOptionalSources: singleStreamDiscovery && refreshOptionalSources)
            }
        }
        if singleStreamDiscovery {
            // Cold-start discriminators: how many providers were enabled and how
            // many discovery lanes were actually built. When the next failure is
            // reviewed, an absent "watch_discovery_started" record means the Watch
            // gate suppressed the attempt; a present record with zero candidate
            // lanes means no enabled source supported the fixture.
            FottyQualityStore.shared.record(category: .playback, name: "watch_discovery_plan",
                outcome: .info, details: ["source_count": "\(enabled.count)", "candidate_count": "\(lanes.count)"])
        }
        guard !lanes.isEmpty else {
            let failure = StreamFailure(category: .noProviderAvailable,
                technicalMessage: "No enabled reviewed provider supports this lookup.",
                userMessage: singleStreamDiscovery && request.preferredEvent?.isBroadcastChannel == true
                    ? "No enabled source supports this channel. Review your source settings."
                    : "No enabled source can check this match. Review your source settings.",
                retryable: false, fallbackAllowed: false,
                redactedMetadata: ["discovery_result": "no_eligible_provider"])
            let diagnostics = makeDiagnostics(attemptID: attemptID, request: request, finalState: .failed,
                timeline: [], providerAttempts: [], startedAt: startedAt)
            await recordDiagnostics(diagnostics)
            return .failure(failure, diagnostics)
        }
        let publishChoices: (@Sendable ([StreamSession]) async -> Void)?
        if let publish = onChoices {
            publishChoices = { @Sendable sessions in
                guard !Task.isCancelled else { return }
                let enabledNow = await StreamPluginRegistry.shared.enabledProviderCodes()
                let allowed = StreamPluginProviderMatching.allowedPlayerProviderCodes(enabledCodes: enabledNow)
                let admitted = sessions.filter { session in
                    !session.hasExpiredMediaLease()
                        && (!singleStreamDiscovery || LiveSourceHealthStore.matchEvidence(for: session) != .wrongProgramme)
                        && allowed.contains { StreamPluginProviderMatching.matches(session.legacySource, code: $0) }
                }
                guard !Task.isCancelled, !admitted.isEmpty else { return }
                await publish(LiveSourceHealthStore.rankedSessions(admitted))
            }
        } else { publishChoices = nil }
        let discoveryDeadline = StreamDiscoveryCoordinator.discoveryDeadline(
            singleStreamDiscovery: singleStreamDiscovery,
            optionalProviderCodes: Set(plan.optionalSources.map(\.providerCode)))
        let collected = await StreamDiscoveryCoordinator.collect(lanes: lanes, deadline: discoveryDeadline,
            preferDirectInitialChoice: singleStreamDiscovery && onChoices != nil, sustainedProviderLanes: sustainedLanes,
            onSessions: publishChoices)
        // A working sibling must not erase the optional lane's result. This
        // bounded local receipt is discovery evidence, not playback or health
        // scoring, and has no fixture, URL, header or response-body fields.
        CommunitySportsDiscoveryQuality.record(collected, attemptID: attemptID)
        AdditionalSportsDiscoveryQuality.record(collected, attemptID: attemptID)
        CNCSportsDiscoveryQuality.record(collected, attemptID: attemptID)
        FlixStreamsDiscoveryQuality.record(collected, attemptID: attemptID)
        if Task.isCancelled {
            return cancelledOutcome(attemptID: attemptID, request: request,
                                    timeline: collected.timeline, providerAttempts: collected.attempts,
                                    category: .navigationCancelled,
                                    technicalMessage: "Cancelled during provider discovery.")
        }
        let enabledAtCompletion = await StreamPluginRegistry.shared.enabledProviderCodes()
        let sessions = LiveSourceHealthStore.rankedSessions(deduplicatedSessions(collected.sessions.filter { session in
            !session.hasExpiredMediaLease()
                && (!singleStreamDiscovery || LiveSourceHealthStore.matchEvidence(for: session) != .wrongProgramme)
                && StreamPluginProviderMatching.allowedPlayerProviderCodes(enabledCodes: enabledAtCompletion)
                .contains { StreamPluginProviderMatching.matches(session.legacySource, code: $0) }
        }))
        let exitEvent = StreamEventRecord(name: .streamResolutionStarted, matchID: request.matchID,
            matchTitle: request.displayTitle, attemptID: attemptID,
            currentState: sessions.isEmpty ? .failed : .readyToPlay,
            redactedMetadata: ["discovery_exit": collected.exitReason.rawValue,
                               "incomplete_lanes": "\(collected.incompleteLanes)"])
        let diagnostics = makeDiagnostics(
            attemptID: attemptID, request: request,
            finalState: sessions.isEmpty ? .failed : .readyToPlay,
            timeline: (collected.timeline + [exitEvent]).sorted { $0.timestamp < $1.timestamp },
            providerAttempts: collected.attempts, startedAt: startedAt
        )
        await recordDiagnostics(diagnostics)
        if !sessions.isEmpty {
            return .success(StreamResolutionSuccess(attemptID: attemptID, sessions: sessions,
                                                    diagnostics: diagnostics))
        }
        var failures = collected.failures
        if collected.reachedDeadline {
            failures.append(StreamFailure(providerName: nil, category: .providerTimeout,
                technicalMessage: "Provider discovery reached its bounded deadline.",
                userMessage: "Checking the broadcast providers took too long. Please try again.",
                retryable: true, fallbackAllowed: true))
        }
        let failure = StreamTransportFailurePolicy.mostActionableFailure(in: failures)
            ?? StreamFailure(providerName: nil, category: .providerReturnedEmpty,
                technicalMessage: "No enabled provider returned a matched player page.",
                userMessage: singleStreamDiscovery && request.preferredEvent?.isBroadcastChannel == true
                    ? "No playable stream is available for this channel right now."
                    : "No playable stream is available for this match right now.",
                retryable: true, fallbackAllowed: false)
        return .failure(failure, diagnostics)
    }

    /// Foreground metadata only: one current fixture, at most two reviewed
    /// optional providers, an eight-second owner and a separate preflight budget.
    /// No player, media probe, source setting or shared publisher is involved.
    func preflightSources(for request: StreamPlaybackRequest) async {
        guard !Task.isCancelled else { return }
        let enabled = Set(await StreamPluginRegistry.shared.enabledProviderCodes())
        let plan = await CuratedStreamSourceCatalog.discoveryPlan(for: request, enabledProviderCodes: enabled)
        var sources = plan.optionalSources
        if plan.score808SiteEligible,
           let score808 = CuratedStreamSourceCatalog.definition(forProviderCode: "score808") {
            sources.append(score808)
        }
        guard !sources.isEmpty else { return }
        var lanes: [StreamDiscoveryCoordinator.Lane] = []
        var tickets: [FixtureStreamDiscoveryIndex.Ticket] = []
        let selectedCodes = preflightProviderSchedule.takeProviders(for: request.matchID,
            available: sources.map(\.providerCode))
        for code in selectedCodes {
            guard let source = sources.first(where: { $0.providerCode == code }) else { continue }
            guard let ticket = await FixtureStreamDiscoveryIndex.shared.begin(
                for: request, providerCode: source.providerCode, preflight: true) else { continue }
            tickets.append(ticket)
            lanes.append { report in
                if source.providerCode == "score808" {
                    let result = await self.resolveScore808Site(for: request,
                        attemptID: UUID().uuidString, report: report, useRegistry: true)
                    if Task.isCancelled {
                        await FixtureStreamDiscoveryIndex.shared.abandon(ticket)
                    } else {
                        switch result {
                        case .success(let success):
                            await FixtureStreamDiscoveryIndex.shared.complete(ticket, sessions: success.sessions)
                        case .failure(let failure, _):
                            await FixtureStreamDiscoveryIndex.shared.complete(ticket, sessions: [], failure: failure)
                        }
                    }
                    return result
                }
                return await self.resolveOptionalSports(for: request, attemptID: UUID().uuidString,
                    source: source, report: report, useDiscoveryIndex: true, preflightTicket: ticket)
            }
        }
        guard !lanes.isEmpty else { return }
        _ = await StreamDiscoveryCoordinator.collect(lanes: lanes, deadline: .seconds(8))
        // Completed generations ignore abandonment; a parent cancelled before
        // a lane started must still release its metadata-only lease.
        for ticket in tickets { await FixtureStreamDiscoveryIndex.shared.abandon(ticket) }
    }

    /// Stable upstream identity can survive wrapper rotation. A delivery hash
    /// includes expiring query credentials and must not veto their refresh;
    /// keep that fallback tied to the same admitted origin/path and choice.
    nonisolated static func isSameDescriptorChoice(_ candidate: StreamSession, as previous: StreamSession) -> Bool {
        guard candidate.qualityLabel == previous.qualityLabel,
              candidate.playbackContract.endpoint == previous.playbackContract.endpoint else { return false }
        if previous.diagnosticMetadata["source_key_scope"] == "upstream",
           let key = previous.diagnosticMetadata["source_key"] {
            return candidate.diagnosticMetadata["source_key_scope"] == "upstream"
                && candidate.diagnosticMetadata["source_key"] == key
        }
        return candidate.providerName == previous.providerName
            && candidate.playableURL.scheme == previous.playableURL.scheme
            && candidate.playableURL.host == previous.playableURL.host
            && candidate.playableURL.port == previous.playableURL.port
            && candidate.playableURL.path == previous.playableURL.path
    }

    /// Re-resolve metadata for the selected provider event only. An old binding
    /// authorizes a lookup, never replay of an expired URL or a new route grant.
    /// A unique current choice must preserve provider-event/stream identity.
    nonisolated static func supportsDescriptorRenewal(_ session: StreamSession) -> Bool {
        guard let provider = session.eventBinding?.providerCode else { return false }
        return provider == ReviewedTVPlaylistClient.providerCode || session.playbackContract.endpoint == .directMedia
            && ["communitysports", "plaviosports", "cncsports", "flixstreams"].contains(provider)
    }

    func refreshedDescriptor(for session: StreamSession, request: StreamPlaybackRequest) async -> StreamSession? {
        guard Self.supportsDescriptorRenewal(session) else { return nil }
        if let binding = session.eventBinding, binding.usesRegistryAssociation {
            let entries = await BroadcastRegistryClient.shared.lookup(for: request, enabledProviderCodes: [binding.providerCode])
            if binding.currentRegistryEntry(in: entries, request: request, at: Date()) == nil {
                _ = await BroadcastRegistryClient.shared.refreshForPlayback()
                guard !Task.isCancelled else { return nil }
            }
        }
        if session.eventBinding?.providerCode == ReviewedTVPlaylistClient.providerCode {
            return await withTaskGroup(of: StreamSession?.self) { group in
                group.addTask {
                    await ReviewedTVPlaylistClient.shared.refreshedDescriptor(for: session, request: request)
                }
                group.addTask {
                    do { try await Task.sleep(for: .seconds(6)) } catch { return nil }
                    return nil
                }
                defer { group.cancelAll() }
                return await group.next() ?? nil
            }
        }
        guard !Task.isCancelled, let binding = session.eventBinding,
              binding.matchesIdentity(request: request, providerCode: binding.providerCode),
              await StreamPluginRegistry.shared.enabledProviderCodes().contains(binding.providerCode) else { return nil }
        let recoveryRequest: StreamPlaybackRequest
        if binding.usesRegistryAssociation {
            guard let current = await RegisteredDescriptorRecoveryPolicy.currentRequest(for: request,
                in: MatchListViewModel.shared.playbackAdmissionCatalog) else { return nil }
            recoveryRequest = current
        } else { recoveryRequest = request }
        guard binding.matchesIdentity(request: recoveryRequest, providerCode: binding.providerCode) else { return nil }
        let metadataRequest: StreamPlaybackRequest
        if binding.usesRegistryAssociation {
            let current = await BroadcastRegistryClient.shared.lookup(for: recoveryRequest,
                enabledProviderCodes: [binding.providerCode], at: Date())
            guard let association = binding.currentRegistryEntry(in: current, request: recoveryRequest, at: Date()) else { return nil }
            metadataRequest = recoveryRequest.usingRegistryMatch(association)
        } else { metadataRequest = recoveryRequest }
        return await withTaskGroup(of: StreamSession?.self) { group in
            group.addTask {
                do {
                    let candidates: [StreamSession]
                    if binding.providerCode == "communitysports" {
                        candidates = try await CommunitySportsAddonClient.shared.resolve(for: metadataRequest, forceRefresh: true)
                    } else if binding.providerCode == "cncsports" {
                        candidates = try await CNCSportsAddonClient.shared.resolve(for: metadataRequest, forceRefresh: true)
                    } else if binding.providerCode == "flixstreams" {
                        candidates = try await FlixStreamsAddonClient.shared.resolve(for: metadataRequest)
                    } else {
                        candidates = try await PlavioSportsAddonClient.shared.resolve(for: metadataRequest, forceRefresh: true)
                    }
                    try Task.checkCancellation()
                    let matching = candidates.filter { candidate in
                        guard let current = candidate.eventBinding,
                              current.matches(request: recoveryRequest, providerCode: binding.providerCode),
                              current.providerEventID == binding.providerEventID,
                              current.streamID == binding.streamID,
                              candidate.playbackContract.endpoint == session.playbackContract.endpoint,
                              candidate.qualityLabel == session.qualityLabel else { return false }
                        return Self.isSameDescriptorChoice(candidate, as: session)
                    }
                    guard matching.count == 1, let fresh = matching.first,
                          await StreamPluginRegistry.shared.enabledProviderCodes().contains(binding.providerCode)
                    else { return nil }
                    let acceptedRequest: StreamPlaybackRequest
                    if binding.usesRegistryAssociation {
                        guard let current = await RegisteredDescriptorRecoveryPolicy.currentRequest(for: request,
                            in: MatchListViewModel.shared.playbackAdmissionCatalog) else { return nil }
                        acceptedRequest = current
                    } else { acceptedRequest = recoveryRequest }
                    return session.renewingDelivery(from: fresh, for: acceptedRequest)
                } catch { return nil }
            }
            group.addTask {
                do { try await Task.sleep(for: .seconds(binding.providerCode == "communitysports" && request.preferredEvent?.isBroadcastChannel == false ? CommunitySportsAddonClient.streamTransportDeadline : 6)) } catch { return nil }
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }

    nonisolated private static func usesCurrentCricketRegistry(_ request: StreamPlaybackRequest,
        providerCode: String) -> Bool {
        guard providerCode == "communitysports", let event = request.preferredEvent,
              let cricket = event.cricketFixture, cricket.verified, cricket.status == .live,
              cricket.format == .odi || cricket.format == .t20,
              event.id == CricketFixtureCatalog.fixtureIDPrefix + cricket.fixtureID,
              request.matchID == event.id, !event.hasCatalogIdentityConflict else { return false }
        return true
    }

    nonisolated static func needsCurrentCricketRegistry(_ request: StreamPlaybackRequest,
        providerCode: String, at now: Date) -> Bool {
        usesCurrentCricketRegistry(request, providerCode: providerCode)
            && request.preferredEvent?.cricketFixture.map { (-300..<600).contains(now.timeIntervalSince($0.observedAt)) } == true
    }

    /// Current-listing CS rows depend on the registry's official fixture join.
    /// Join its existing refresh inside this provider lane, never before other
    /// providers can resolve. The preflight's eight-second owner still cancels
    /// this wait and releases its ticket without publishing a false empty result.
    @MainActor
    static func optionalRegistryMatches(for request: StreamPlaybackRequest, providerCode: String,
        registry: BroadcastRegistryClient? = nil, at now: Date = Date()) async -> [BroadcastRegistryMatch] {
        let registry = registry ?? .shared
        let found = registry.lookup(for: request, enabledProviderCodes: [providerCode], at: now)
        guard found.isEmpty, needsCurrentCricketRegistry(request, providerCode: providerCode, at: now) else { return found }
        let started = ContinuousClock.now
        _ = await registry.refreshForPlayback(at: now)
        guard !Task.isCancelled else { return [] }
        let elapsed = started.duration(to: .now).components
        let completedAt = now.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        return registry.lookup(for: request, enabledProviderCodes: [providerCode], at: completedAt)
    }

    nonisolated static func isUnassociatedCurrentCricketMiss(_ error: Error, request: StreamPlaybackRequest,
        providerCode: String, registered: [BroadcastRegistryMatch], at now: Date) -> Bool {
        registered.isEmpty && (error as? CommunitySportsAddonError) == .matchNotFound
            // An old cached official receipt also means authority is pending,
            // never proof of source absence. This does not authorize playback:
            // the registry/adapter still require independently fresh evidence.
            && usesCurrentCricketRegistry(request, providerCode: providerCode)
    }

    private func resolveOptionalSports(
        for request: StreamPlaybackRequest,
        attemptID: String,
        source: CuratedStreamSourceCatalog.Definition,
        report: @escaping StreamDiscoveryCoordinator.Reporter,
        useDiscoveryIndex: Bool = false,
        preflightTicket: FixtureStreamDiscoveryIndex.Ticket? = nil,
        refreshTVRegistry: Bool = false,
        refreshOptionalSources: Bool = false
    ) async -> StreamResolutionOutcome {
        let providerCode = source.providerCode
        let providerName = source.discoveryName
        let startedAt = Date()
        let startedEvent = StreamEventRecord(
            name: .provider1Started,
            matchID: request.matchID,
            matchTitle: request.displayTitle,
            providerName: providerName,
            attemptID: attemptID,
            currentState: .resolving,
            redactedMetadata: ["mode": "exact_addon_lookup"]
        )
        report(.event(startedEvent))

        let needsFreshTVAssociation = refreshTVRegistry && source.dispatch == .reviewedTV
            && request.registryMatch == nil && ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil
        if needsFreshTVAssociation {
            let hasFreshProgramme = await MainActor.run {
                ReviewedTVPlaylistClient.programmeLookupRequest(for: request) != nil
            }
            if !hasFreshProgramme {
                // Registry work belongs to this parallel lane. AS/CS can publish
                // and start while one existing registry refresh is joined.
                _ = await BroadcastRegistryClient.shared.refreshForPlayback()
            }
            if Task.isCancelled {
                return cancelledOutcome(attemptID: attemptID, request: request,
                    timeline: [], providerAttempts: [], category: .navigationCancelled,
                    technicalMessage: "Cancelled while joining broadcast registry refresh.")
            }
        }

        let registered = useDiscoveryIndex ? await Self.optionalRegistryMatches(for: request,
            providerCode: providerCode) : []
        // Explicit single-player Retry asks every enabled lane for current
        // metadata. It must not replay a still-leased descriptor that just
        // failed. Registry identity facts and provider limits remain intact.
        let cachedCandidates = useDiscoveryIndex && preflightTicket == nil && !refreshOptionalSources
            ? await FixtureStreamDiscoveryIndex.shared.cachedSessions(for: request, providerCode: providerCode)
            : nil
        let cached = cachedCandidates.flatMap { candidates -> [StreamSession]? in
            let allowed = registered.isEmpty ? candidates : candidates.filter { session in
                guard let binding = session.eventBinding else { return false }
                return registered.contains { binding.matchesRegistryEntry($0, request: request, at: Date()) }
            }
            return allowed.isEmpty ? nil : allowed
        }
        let ticket: FixtureStreamDiscoveryIndex.Ticket?
        if useDiscoveryIndex && cached == nil {
            if let preflightTicket { ticket = preflightTicket }
            else { ticket = await FixtureStreamDiscoveryIndex.shared.begin(
                for: request, providerCode: providerCode, preflight: false) }
        } else { ticket = nil }
        do {
            guard !needsFreshTVAssociation || !registered.isEmpty else {
                throw CommunitySportsAddonError.matchNotFound
            }
            let sessions: [StreamSession]
            if let cached {
                sessions = cached
            } else {
                if source.dispatch == .reviewedTV, request.registryMatch == nil, !registered.isEmpty {
                    // One closed playlist read resolves every independently
                    // assigned station. The generic two-adapter lookup cap
                    // must not hide TV3–TV8 or reread the playlist per station.
                    let resolved = try await resolveOptionalAdapter(source, request: request, forceRefresh: true,
                        forceFreshMetadata: refreshOptionalSources)
                    let admitted = resolved.filter { session in
                        guard let binding = session.eventBinding else { return false }
                        return registered.contains { association in
                            association.matches(request: request, providerCode: providerCode,
                                providerEventID: binding.providerEventID, streamID: binding.streamID, at: Date())
                                && binding.matches(request: request, providerCode: providerCode)
                        }
                    }
                    guard !admitted.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
                    sessions = deduplicatedSessions(admitted)
                    for session in sessions { report(.partialSession(session)) }
                } else if registered.isEmpty {
                    FottyQualityStore.shared.record(category: .playback, name: "direct_fallback_lookup",
                        outcome: .info, details: ["source": providerCode, "mode": "registry_empty_direct_fallback"])
                    sessions = try await resolveOptionalAdapter(source, request: request, forceRefresh: useDiscoveryIndex,
                        forceFreshMetadata: refreshOptionalSources)
                } else {
                    // The registry is a hint, not a gate. When every registered
                    // association misses (stale cloud row, joined TV channel that
                    // is down, expired lease), run the same exact adapter lookup
                    // the empty-registry branch uses. The adapter still owns
                    // team/date/competition identity and transport admission.
                    // Reviewed TV is excluded: a generic channel never identifies
                    // a fixture without a registry or programme association.
                    var directFallback: (@Sendable () async throws -> [StreamSession])?
                    if source.dispatch != .reviewedTV {
                        let refreshMetadata = refreshOptionalSources
                        directFallback = { @Sendable [source, request, providerCode] () async throws -> [StreamSession] in
                            FottyQualityStore.shared.record(category: .playback, name: "direct_fallback_lookup",
                                outcome: .info, details: ["source": providerCode, "mode": "registry_miss_direct_fallback"])
                            return try await self.resolveOptionalAdapter(source, request: request, forceRefresh: true,
                                forceFreshMetadata: refreshMetadata)
                        }
                    }
                    sessions = try await Self.resolveRegisteredOptionalSessions(for: request,
                        providerCode: providerCode, associations: registered, resolve: { scoped in
                            try await self.resolveOptionalAdapter(source, request: scoped, forceRefresh: true,
                                forceFreshMetadata: refreshOptionalSources)
                        }, onSession: { report(.partialSession($0)) }, fallback: directFallback)
                }
            }
            try Task.checkCancellation()
            guard await StreamPluginRegistry.shared.enabledProviderCodes().contains(providerCode) else {
                throw CancellationError()
            }
            if let ticket {
                await FixtureStreamDiscoveryIndex.shared.complete(ticket, sessions: sessions, failure: nil)
            }
            sessions.forEach { report(.session($0)) }
            let attempt = StreamProviderAttemptLog(
                providerName: providerName,
                responseTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                resolvedStreamType: sessions.first?.streamType ?? .unknown,
                urlShape: "reviewed_addon",
                requiredHeaders: sessions.first?.requiredHeaders.isEmpty == false,
                validationResult: "exact_match_admitted",
                manifestResult: "exact_fixture_match"
            )
            report(.attempt(attempt))
            let succeededEvent = StreamEventRecord(
                name: .provider1ValidationSucceeded,
                matchID: request.matchID,
                matchTitle: request.displayTitle,
                providerName: providerName,
                attemptID: attemptID,
                currentState: .readyToPlay,
                redactedMetadata: ["session_count": "\(sessions.count)", "mode": "exact_addon_lookup"]
            )
            report(.event(succeededEvent))
            let diagnostics = makeDiagnostics(
                attemptID: attemptID,
                request: request,
                finalState: .readyToPlay,
                timeline: [startedEvent, succeededEvent],
                providerAttempts: [attempt],
                startedAt: startedAt
            )
            return .success(
                StreamResolutionSuccess(attemptID: attemptID, sessions: sessions, diagnostics: diagnostics)
            )
        } catch {
            let failure = communitySportsFailure(from: error, providerName: providerName)
            if let ticket {
                if Task.isCancelled || error is CancellationError
                    || Self.isUnassociatedCurrentCricketMiss(error, request: request,
                        providerCode: providerCode, registered: registered, at: startedAt) {
                    // A generated-clock CS catalog cannot date this fixture by
                    // itself. Its miss must not veto an exact registry link
                    // that finishes loading after this lane's bounded lookup.
                    await FixtureStreamDiscoveryIndex.shared.abandon(ticket)
                } else {
                    await FixtureStreamDiscoveryIndex.shared.complete(ticket, sessions: [], failure: failure)
                }
            }
            report(.failure(failure))
            let attempt = StreamProviderAttemptLog(
                providerName: providerName,
                responseTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                resolvedStreamType: .unknown,
                urlShape: "reviewed_addon",
                requiredHeaders: false,
                validationResult: "failed",
                manifestResult: failure.redactedMetadata["manifest_result"],
                finalFailureCategory: failure.category
            )
            report(.attempt(attempt))
            let failedEvent = StreamEventRecord(
                name: .provider1ValidationFailed,
                matchID: request.matchID,
                matchTitle: request.displayTitle,
                providerName: providerName,
                attemptID: attemptID,
                currentState: .failed,
                failureCategory: failure.category,
                redactedMetadata: failure.redactedMetadata
            )
            report(.event(failedEvent))
            let diagnostics = makeDiagnostics(
                attemptID: attemptID,
                request: request,
                finalState: .failed,
                timeline: [startedEvent, failedEvent],
                providerAttempts: [attempt],
                startedAt: startedAt
            )
            return .failure(failure, diagnostics)
        }
    }

    /// The production registered lane keeps only fresh deliveries from each
    /// exact association. The adapter still owns all source-specific matching
    /// and transport admission; this seam cannot invent an executable ID.
    nonisolated static func resolveRegisteredOptionalSessions(
        for request: StreamPlaybackRequest, providerCode: String, associations: [BroadcastRegistryMatch],
        resolve: @escaping @Sendable (StreamPlaybackRequest) async throws -> [StreamSession],
        onSession: @escaping @Sendable (StreamSession) -> Void = { _ in },
        clock: @escaping @Sendable () -> Date = { Date() },
        fallback: (@Sendable () async throws -> [StreamSession])? = nil
    ) async throws -> [StreamSession] {
        var choices: [StreamSession] = [], lastError: Error?
        // Retain independent literal broadcasts without a second broad search.
        // The calling coordinator's deadline and cancellation own all children.
        for association in associations.prefix(2) {
            try Task.checkCancellation()
            do {
                let resolved = try await resolve(request.usingRegistryMatch(association))
                try Task.checkCancellation()
                let now = clock()
                let admitted = resolved.filter { session in
                    guard let binding = session.eventBinding, !session.hasExpiredMediaLease(at: now) else { return false }
                    return binding.matchesRegistryEntry(association, request: request, at: now)
                        && binding.matches(request: request, providerCode: providerCode, at: now)
                }
                for session in admitted { choices.append(session); onSession(session) }
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        if choices.isEmpty {
            // Registered associations are evidence, not the only route. A miss
            // here must not hide an exact direct listing from the same provider.
            guard let fallback else { throw lastError ?? CommunitySportsAddonError.matchNotFound }
            try Task.checkCancellation()
            let direct = try await fallback()
            try Task.checkCancellation()
            guard !direct.isEmpty else { throw lastError ?? CommunitySportsAddonError.matchNotFound }
            choices = direct
        }
        var seen = Set<StreamDeliveryIdentity>()
        return choices.filter { seen.insert(StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders)).inserted }
    }

    #if FOTTY_SOURCE_CONNECTION_TOOL
    /// Test-bundle entry only. Invokes production adapters independently without
    /// changing Watch, settings, registry publication or source ordering.
    func inspectSourceConnection(_ source: CuratedStreamSourceCatalog.Definition,
        request: StreamPlaybackRequest) async -> StreamResolutionOutcome {
        let id = UUID().uuidString
        switch source.dispatch {
        case .score808:
            return await resolveScore808Site(for: request, attemptID: id, report: { _ in }, useRegistry: false)
        default:
            return await resolveOptionalSports(for: request, attemptID: id, source: source,
                report: { _ in }, useDiscoveryIndex: false)
        }
    }
    #endif

    private func resolveOptionalAdapter(_ source: CuratedStreamSourceCatalog.Definition,
        request: StreamPlaybackRequest, forceRefresh: Bool,
        forceFreshMetadata: Bool = false) async throws -> [StreamSession] {
        switch source.dispatch {
        case .reviewedTV: return try await ReviewedTVPlaylistClient.shared.resolve(for: request)
        case .cncSports: return try await CNCSportsAddonClient.shared.resolve(for: request, forceRefresh: forceFreshMetadata)
        case .flixStreams: return try await FlixStreamsAddonClient.shared.resolve(for: request, forceRefresh: forceFreshMetadata)
        case .plavioSports: return try await PlavioSportsAddonClient.shared.resolve(for: request, forceRefresh: forceRefresh)
        case .communitySports: return try await CommunitySportsAddonClient.shared.resolve(for: request, forceRefresh: forceRefresh)
        case .score808: throw CommunitySportsAddonError.matchNotFound
        }
    }

    private func communitySportsFailure(from error: Error, providerName: String = "CS") -> StreamFailure {
        guard let addOnError = error as? CommunitySportsAddonError else {
            return failureFromError(
                providerName: providerName,
                fallbackAllowed: true,
                defaultUserMessage: "Broadcast information could not be checked just now.",
                error: error,
                defaultCategory: .manifestUnreachable,
                redactedMetadata: ["discovery": "exact_addon_lookup"]
            )
        }

        return Self.communitySportsFailure(from: addOnError, providerName: providerName)
    }

    nonisolated static func communitySportsFailure(from addOnError: CommunitySportsAddonError,
                                                  providerName: String = "CS") -> StreamFailure {
        let entryCountKey = providerName == "CS" ? "cs_stream_entry_count" : "addon_stream_entry_count"
        let rejectedCountKey = providerName == "CS" ? "cs_admission_rejected_count" : "addon_admission_rejected_count"
        switch addOnError {
        case .httpFailure(let statusCode, let stage):
            return StreamFailure(
                providerName: providerName,
                category: [408, 504].contains(statusCode) ? .providerTimeout : .manifestUnreachable,
                technicalMessage: "The optional add-on returned an unsuccessful HTTP status.",
                userMessage: "Broadcast information could not be checked just now.",
                retryable: true,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "\(stage.rawValue)_http_failure",
                                   "platform_error_code": String(statusCode)]
            )
        case .transportFailure(let code, let stage):
            return StreamTransportFailurePolicy.makeFailure(
                providerName: providerName,
                code: URLError.Code(rawValue: code),
                technicalMessage: "The optional add-on request failed in transport.",
                defaultCategory: .manifestUnreachable,
                defaultUserMessage: "Broadcast information could not be checked just now.",
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "\(stage.rawValue)_transport_failure",
                                   "platform_error_code": String(code)]
            )
        case .invalidJSON(let stage):
            return StreamFailure(
                providerName: providerName,
                category: .manifestInvalid,
                technicalMessage: "The optional add-on returned malformed JSON.",
                userMessage: "Broadcast information could not be checked just now.",
                retryable: true,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "\(stage.rawValue)_invalid_json"]
            )
        case .matchNotFound:
            return StreamFailure(
                providerName: providerName,
                category: .providerReturnedEmpty,
                technicalMessage: "The optional add-on had no exact playable match at this kickoff.",
                userMessage: "A matching broadcast could not be confirmed for this match.",
                retryable: true,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "no_exact_fixture_match"]
            )
        case .streamEntriesEmpty:
            return StreamFailure(
                providerName: providerName,
                category: .providerReturnedEmpty,
                technicalMessage: "The exact fixture matched, but its stream list contained no entries.",
                userMessage: "The additional sources found this match but have not listed any streams yet.",
                retryable: true,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "stream_entries_empty",
                                   entryCountKey: "0", rejectedCountKey: "0"]
            )
        case .streamAdmissionRejected(let entryCount):
            let count = String(min(max(entryCount, 0), 100))
            return StreamFailure(
                providerName: providerName,
                category: .providerReturnedEmpty,
                technicalMessage: "The exact fixture matched, but none of its bounded entries met the supported delivery contract.",
                userMessage: "The additional sources found this match, but their streams are not compatible right now. Try another source.",
                retryable: true,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "no_admitted_stream_delivery",
                                   entryCountKey: count, rejectedCountKey: count]
            )
        case .conflictingMatch:
            return StreamFailure(
                providerName: providerName,
                category: .invalidMatchMapping,
                technicalMessage: "The optional add-on returned conflicting exact fixture candidates.",
                userMessage: "The broadcast details could not be matched to this fixture.",
                retryable: false,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "conflicting_fixture_match"]
            )
        case .unsafeResponse:
            return StreamFailure(
                providerName: providerName,
                category: .providerSecurityFailure,
                technicalMessage: "The optional add-on returned a cross-origin or unapproved delivery URL.",
                userMessage: "The additional broadcast source could not be opened safely.",
                retryable: false,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "unsafe_response_rejected"]
            )
        case .unsafeMetadata(let stage, let reason, let invalidScalar):
            // Only one invalid character's public Unicode code point may refine
            // this fixed diagnostic. Never retain the identifier or its hash.
            let scalarSuffix: String
            if reason == .streamIDCharacters, let invalidScalar, let scalar = UnicodeScalar(invalidScalar),
               !CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~")).contains(scalar) {
                scalarSuffix = String(format: "_u%04X", invalidScalar)
            } else { scalarSuffix = reason == .streamIDCharacters ? "_unresolved" : "" }
            return StreamFailure(
                providerName: providerName,
                category: .providerSecurityFailure,
                technicalMessage: "The optional add-on metadata request was rejected by its existing safety contract.",
                userMessage: "The additional broadcast source could not be opened safely.",
                retryable: false,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "\(stage.rawValue)_unsafe_\(reason.rawValue)\(scalarSuffix)"]
            )
        case .configurationUnavailable, .invalidManifest, .invalidResponse:
            return StreamFailure(
                providerName: providerName,
                category: .manifestInvalid,
                technicalMessage: "The optional add-on contract was unavailable or invalid.",
                userMessage: "Broadcast information could not be checked just now.",
                retryable: true,
                fallbackAllowed: true,
                redactedMetadata: ["manifest_result": "invalid_addon_contract"]
            )
        }
    }

    private func resolveScore808Site(
        for request: StreamPlaybackRequest, attemptID: String,
        report: @escaping StreamDiscoveryCoordinator.Reporter,
        useRegistry: Bool = false
    ) async -> StreamResolutionOutcome {
        let startedAt = Date()
        let result: Result<[StreamSession], StreamFailure>
        do {
            let registered = useRegistry ? await BroadcastRegistryClient.shared.lookup(for: request,
                enabledProviderCodes: ["score808"], at: Date()) : []
            var choices: [StreamSession] = [], lastError: Error?
            if registered.isEmpty {
                if let session = try await Score808SiteResolver().resolve(for: request) { choices = [session] }
            } else {
                for association in registered.prefix(2) {
                    do {
                        if let session = try await Score808SiteResolver().resolve(for: request.usingRegistryMatch(association)),
                           let binding = session.eventBinding,
                           association.matches(request: request, providerCode: "score808",
                            providerEventID: binding.providerEventID, streamID: binding.streamID, at: Date()),
                           binding.matches(request: request, providerCode: "score808") {
                            choices.append(session); report(.partialSession(session))
                        }
                    } catch { try Task.checkCancellation(); lastError = error }
                }
                if choices.isEmpty {
                    // Registry is a hint, not a gate: a stale or unbound Score808
                    // association falls back to the same exact site lookup used
                    // when the registry is empty. Identity checks are unchanged.
                    try Task.checkCancellation()
                    FottyQualityStore.shared.record(category: .playback, name: "direct_fallback_lookup",
                        outcome: .info, details: ["source": "score808", "mode": "registry_miss_direct_fallback"])
                    do {
                        if let session = try await Score808SiteResolver().resolve(for: request) { choices = [session] }
                    } catch { try Task.checkCancellation(); lastError = lastError ?? error }
                }
            }
            try Task.checkCancellation()
            if !choices.isEmpty { result = .success(deduplicatedSessions(choices)) }
            else if let lastError { throw lastError }
            else {
                result = .failure(StreamFailure(providerName: "Score808", category: .providerReturnedEmpty,
                    technicalMessage: "No fresh unambiguous site event and configured player matched.",
                    userMessage: "Fotty checked the available broadcast sources, but none has a playable stream for this match yet. Try again shortly.",
                    retryable: true, fallbackAllowed: true))
            }
        } catch {
            result = .failure(failureFromError(providerName: "Score808", fallbackAllowed: true,
                defaultUserMessage: "The available broadcast sources could not provide a playable stream just now. Please try again.",
                error: error, defaultCategory: .manifestUnreachable,
                redactedMetadata: ["discovery": "direct_site"]))
        }
        var attempts: [StreamProviderAttemptLog] = []
        let failure: StreamFailure?
        let sessions: [StreamSession]
        switch result {
        case .success(let found):
            found.forEach { report(.session($0)) }
            sessions = found
            failure = nil
        case .failure(let error):
            report(.failure(error))
            sessions = []
            failure = error
        }
        attempts.append(StreamProviderAttemptLog(providerName: "Score808",
            responseTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            resolvedStreamType: .unknown, urlShape: "score808_site",
            requiredHeaders: true, validationResult: failure == nil ? "matched_player_page" : "failed",
            manifestResult: "direct_site_calendar", segmentResult: "awaiting_decoded_web_playback",
            finalFailureCategory: failure?.category))
        let diagnostics = makeDiagnostics(attemptID: attemptID, request: request,
            finalState: failure == nil ? .readyToPlay : .failed,
            timeline: [], providerAttempts: attempts, startedAt: startedAt)
        if let failure { return .failure(failure, diagnostics) }
        return .success(StreamResolutionSuccess(attemptID: attemptID, sessions: sessions, diagnostics: diagnostics))
    }

    /// Resolution is owned by the caller's structured task. Cancelling that task only
    /// cancels that caller, so another screen resolving the same fixture is unaffected.
    func cancelAttempt(for request: StreamPlaybackRequest) {
        _ = request
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

    private func deduplicatedSessions(_ sessions: [StreamSession]) -> [StreamSession] {
        var seen = Set<StreamDeliveryIdentity>()
        return sessions.filter { session in
            seen.insert(StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)).inserted
        }
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

    private func failureFromError(
        providerName: String,
        fallbackAllowed: Bool,
        defaultUserMessage: String,
        error: Error,
        defaultCategory: StreamFailureCategory,
        redactedMetadata: [String: String] = [:]
    ) -> StreamFailure {
        if let failure = error as? StreamFailure {
            return failure
        }

        if let urlErrorCode = StreamTransportFailurePolicy.urlErrorCode(from: error) {
            return StreamTransportFailurePolicy.makeFailure(
                providerName: providerName,
                code: urlErrorCode,
                technicalMessage: error.localizedDescription,
                defaultCategory: defaultCategory,
                defaultUserMessage: defaultUserMessage,
                fallbackAllowed: fallbackAllowed,
                redactedMetadata: redactedMetadata
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

}
