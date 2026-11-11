import Foundation

/// Catalog-only collection for accepted official fixtures. Every enabled source
/// gets its own bounded opportunity; no source supplies another source's result.
/// Playback descriptors remain owned by the existing selected-match resolver.
@MainActor
enum FixtureSourceCatalogCollector {
    struct Lane: Sendable {
        enum Origin: Equatable, Sendable { case local, cloud }
        let providerCode: String
        let origin: Origin
        let cloudEvidence: [FixtureSourceCatalogMatch]?
        let load: @Sendable ([StreamPlaybackRequest], Date) async throws -> [FixtureSourceCatalogMatch]

        init(providerCode: String, origin: Origin = .local, cloudEvidence: [FixtureSourceCatalogMatch]? = nil,
             load: @escaping @Sendable ([StreamPlaybackRequest], Date) async throws -> [FixtureSourceCatalogMatch]) {
            self.providerCode = providerCode; self.origin = origin; self.cloudEvidence = cloudEvidence; self.load = load
        }
    }

    private enum Completion: Sendable {
        case matches(FixtureCatalogAvailabilityIndex.Ticket, [FixtureSourceCatalogMatch])
        case failed(FixtureCatalogAvailabilityIndex.Ticket, StreamFailureCategory)
        case abandoned(FixtureCatalogAvailabilityIndex.Ticket)
        case deadline
    }

    static func lanes(registrySnapshot: BroadcastRegistrySnapshot? = nil,
                      requests: [StreamPlaybackRequest] = [], at now: Date = Date()) -> [Lane] {
        // Cloud-owned current cohorts are collected once for the group. The
        // original on-device collectors remain a bounded fallback during a
        // cloud outage/activation, not a second fleet-wide collection loop.
        let requestedSports = Set(requests.map { ReviewedSportsFixtureMatcher.sportKey($0.category) })
        let cohorts = Dictionary(grouping: registrySnapshot?.providers ?? [], by: \.providerCode)
        let freshEnvelope = registrySnapshot.map {
            $0.generatedAt.timeIntervalSince1970.isFinite
                && (-300..<BroadcastRegistrySnapshot.networkFreshness).contains(now.timeIntervalSince($0.generatedAt))
        } ?? false
        let cloudOwned = Set(cohorts.compactMap { code, rows -> String? in
            // A healthy football cohort cannot stand in for failed cricket.
            // Without the actual request scope, no whole-provider suppression
            // is justified. NETWORKS and generic Live never imply event scope.
            guard freshEnvelope, !requestedSports.isEmpty, !requestedSports.contains(""),
                  rows.allSatisfy({ provider in
                    guard provider.complete == true, [.available, .empty].contains(provider.status),
                          let expiry = provider.expiresAt, expiry.timeIntervalSince1970.isFinite, expiry > now,
                          let observed = provider.observedAt, observed.timeIntervalSince1970.isFinite else { return false }
                    return (-300..<(FixtureCatalogAvailabilityIndex.minimumRefreshInterval + 60))
                        .contains(now.timeIntervalSince(observed))
                  }), requestedSports.isSubset(of: Set(rows.map(\.scope))) else { return nil }
            return code
        })
        return CuratedStreamSourceCatalog.all.filter {
            $0.provider != .reviewedTV || cloudOwned.contains($0.providerCode)
        }.map { definition in
            if cloudOwned.contains(definition.providerCode), let snapshot = registrySnapshot {
                // This lane spends the same ticket/cadence as a local lookup but
                // performs no HTTP. Its original receipts bound every import.
                let prepared = BroadcastRegistrySnapshot.LookupIndex(snapshot: snapshot)
                let provider = definition.providerCode
                let coverage = Dictionary((cohorts[provider] ?? []).map { ($0.scope, $0) },
                    uniquingKeysWith: { first, _ in first })
                let links = Dictionary(grouping: snapshot.links.filter { $0.providerCode == provider }, by: \.fixtureID)
                let channelOnlyScopes = Set(Dictionary(grouping: snapshot.broadcasts.filter {
                    $0.providerCode == provider
                }, by: \.scope).compactMap { scope, rows in
                    rows.allSatisfy { $0.kind == .channel } ? scope : nil
                })
                let evidence = cloudMatches(requests: requests, provider: provider, snapshot: snapshot,
                    prepared: prepared, coverage: coverage, links: links, channelOnlyScopes: channelOnlyScopes, at: now)
                return Lane(providerCode: provider, origin: .cloud, cloudEvidence: evidence) { requests, at in
                    try Task.checkCancellation()
                    return await cloudMatches(requests: requests, provider: provider, snapshot: snapshot,
                                        prepared: prepared, coverage: coverage, links: links,
                                        channelOnlyScopes: channelOnlyScopes, at: at)
                }
            }
            return Lane(providerCode: definition.providerCode) { requests, now in
                switch definition.dispatch {
                case .score808: return try await Score808CatalogClient.shared.catalogMatches(for: requests, now: now)
                case .communitySports: return try await CommunitySportsAddonClient.shared.catalogMatches(for: requests, now: now)
                case .plavioSports: return try await PlavioSportsAddonClient.shared.catalogMatches(for: requests, now: now)
                case .cncSports: return try await CNCSportsAddonClient.shared.catalogMatches(for: requests, now: now)
                case .flixStreams: return try await FlixStreamsAddonClient.shared.catalogMatches(for: requests, now: now)
                case .highfly: return try await HighflySportsAddonClient.shared.catalogMatches(for: requests, now: now)
                case .reviewedTV: return requests.map { .init(matchID: $0.matchID, outcome: .unsupported) }
                }
            }
        }
    }

    private static func cloudMatches(requests: [StreamPlaybackRequest], provider: String,
                                     snapshot: BroadcastRegistrySnapshot,
                                     prepared: BroadcastRegistrySnapshot.LookupIndex,
                                     coverage: [String: BroadcastRegistrySnapshot.Provider],
                                     links: [String: [BroadcastRegistrySnapshot.Link]], channelOnlyScopes: Set<String>,
                                     at now: Date) -> [FixtureSourceCatalogMatch] {
        guard requests.count <= FixtureCatalogAvailabilityIndex.maximumFixtures else { return [] }
        let envelopeExpiry = snapshot.generatedAt.addingTimeInterval(BroadcastRegistrySnapshot.networkFreshness)
        return requests.map { request in
            let sport = ReviewedSportsFixtureMatcher.sportKey(request.category)
            guard let cohort = coverage[sport], cohort.complete == true,
                  [.available, .empty].contains(cohort.status),
                  let observed = cohort.observedAt, let expiry = cohort.expiresAt,
                  observed.timeIntervalSince1970.isFinite, expiry.timeIntervalSince1970.isFinite,
                  expiry > now, envelopeExpiry > now,
                  (-300...BroadcastRegistrySnapshot.sourceLifetime).contains(now.timeIntervalSince(observed)),
                  ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil,
                  request.preferredEvent?.hasCatalogIdentityConflict != true,
                  request.preferredEvent?.isBroadcastChannel != true else {
                return .init(matchID: request.matchID, outcome: .needsVerification,
                             evidenceObservedAt: snapshot.generatedAt, evidenceValidUntil: envelopeExpiry)
            }
            let qualified = prepared.lookup(for: request, enabledProviderCodes: [provider], at: now)
                .filter { $0.broadcast.providerCode == provider }
            if let match = qualified.first {
                let sourceObserved = [observed, match.broadcast.observedAt,
                    match.programmeAuthority?.broadcast.observedAt,
                    match.programmeAuthority?.provider.observedAt].compactMap { $0 }.min() ?? observed
                return .init(matchID: request.matchID, outcome: .listed,
                             providerEventID: match.broadcast.providerEventID,
                             evidenceObservedAt: sourceObserved,
                             evidenceValidUntil: min(min(envelopeExpiry, expiry), match.acceptanceExpiresAt))
            }
            let related = links[request.matchID] ?? []
            // An explicit conflict, rejected fingerprint or expired association
            // is uncertainty, never a complete-catalog claim of absence.
            let outcome: FixtureSourceCatalogMatch.Outcome = related.contains { $0.state == .conflicting }
                ? .conflicting : related.isEmpty && !channelOnlyScopes.contains(sport) ? .notListed : .needsVerification
            return .init(matchID: request.matchID, outcome: outcome,
                         evidenceObservedAt: observed, evidenceValidUntil: min(envelopeExpiry, expiry))
        }
    }

    static func refresh(requests: [StreamPlaybackRequest], lanes: [Lane],
                        index suppliedIndex: FixtureCatalogAvailabilityIndex? = nil,
                        at now: Date = Date(), deadline: Duration = .seconds(45),
                        clock: @escaping @Sendable () -> Date = { Date() }) async {
        guard !Task.isCancelled else { return }
        let index = suppliedIndex ?? .shared
        index.replaceFixtures(requests, at: now)
        var seen = Set<String>()
        let work = lanes.filter { seen.insert($0.providerCode).inserted }
        guard !work.isEmpty else { return }
        await withTaskGroup(of: Completion.self) { group in
            var startedTickets: [FixtureCatalogAvailabilityIndex.Ticket] = []
            defer {
                group.cancelAll()
                // Revocation/replacement makes old tickets harmless; cancellation
                // must also clear queued sources that never began transport.
                for ticket in startedTickets { index.abandon(ticket) }
            }
            group.addTask {
                do { try await Task.sleep(for: deadline) } catch { return .deadline }
                return .deadline
            }
            var next = 0, active = 0
            @MainActor func enqueue() {
                var selected: (Lane, FixtureCatalogAvailabilityIndex.Ticket, Date)?
                while next < work.count, !Task.isCancelled {
                    let lane = work[next]; next += 1
                    let startedAt = clock()
                    let ticket: FixtureCatalogAvailabilityIndex.Ticket?
                    if let evidence = lane.cloudEvidence {
                        ticket = index.beginCloudImport(providerCode: lane.providerCode, matches: evidence,
                                                        requests: requests, at: startedAt)
                    } else {
                        ticket = index.begin(providerCode: lane.providerCode, at: startedAt)
                    }
                    if let ticket {
                        selected = (lane, ticket, startedAt); break
                    }
                }
                guard let (lane, ticket, startedAt) = selected else { return }
                startedTickets.append(ticket); active += 1
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let matches = try await lane.load(requests, startedAt)
                        try Task.checkCancellation()
                        return .matches(ticket, matches)
                    } catch {
                        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                            return .abandoned(ticket)
                        }
                        return .failed(ticket, failureCategory(error))
                    }
                }
            }
            enqueue(); enqueue()
            while active > 0, let result = await group.next(), !Task.isCancelled {
                switch result {
                case .deadline: return
                case .matches(let ticket, let matches): index.complete(ticket, matches: matches, at: clock())
                case .failed(let ticket, let category): index.fail(ticket, category: category, at: clock())
                case .abandoned(let ticket): index.abandon(ticket)
                }
                active -= 1
                enqueue()
            }
        }
    }

    nonisolated static func failureCategory(_ error: Error) -> StreamFailureCategory {
        if let failure = error as? StreamFailure { return failure.category }
        if let error = error as? URLError {
            if StreamTransportFailurePolicy.isProviderSecurityFailure(error.code) { return .providerSecurityFailure }
            return error.code == .timedOut ? .providerTimeout : .manifestUnreachable
        }
        if let error = error as? CommunitySportsAddonError, error.isSecurityRejection { return .providerSecurityFailure }
        return .manifestInvalid
    }
}
