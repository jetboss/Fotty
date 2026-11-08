import Foundation

/// A confirmed schedule may reach its kickoff before its publisher changes the
/// match status. Preserve its discovery row briefly without inventing LIVE.
@MainActor
enum VerifiedFixtureStartingPolicy {
    static let grace = SportsFixtureCatalog.statusFreshness

    static func contains(_ event: EventReference, at now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite, !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
              event.cricketFixture == nil, let fixture = event.sportsFixture,
              fixture.verified, fixture.status == .scheduled, fixture.eventKind == .match,
              fixture.sport == event.normalizedCategory, event.id == fixture.fixtureID,
              fixture.fixtureID.hasPrefix(SportsFixtureCatalog.fixtureIDPrefix + fixture.competitionID + ":"),
              fixture.participants.count == 2,
              Set([event.homeName, event.awayName].map(SportsTeamIdentity.normalized)).count == 2,
              Set(fixture.participants.map { SportsTeamIdentity.normalized($0.name) })
                == Set([event.homeName, event.awayName].map(SportsTeamIdentity.normalized)),
              let kickoff = event.kickoffDate, (0..<grace).contains(now.timeIntervalSince(kickoff)) else { return false }
        return (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(fixture.identityReceipt))
    }
}

/// The same current-event Watch decision for discovery, saved rows and reminder
/// return. A channel route never certifies the programme currently on air.
@MainActor
enum CurrentEventBroadcastPolicy {
    struct Action {
        enum Evidence: Equatable { case explicitStation, providerListing, programmeAssignment, compatibleDescriptor, freshLookupOpportunity }
        let event: AnalyticalDataEngine.EventReference
        let isChannelFallback: Bool
        let evidence: Evidence
        var registryEvidence: [BroadcastRegistryMatch.DecisionReceipt] = []
        var alternateActionTitle: String? { isChannelFallback ? "Watch" : nil }
    }

    /// A Matchday projection asks about many rows from the same immutable
    /// admission catalog. Keep every exact duplicate, alias and typed terminal
    /// competitor. Saved rows without an exact identity retain the full search.
    struct IndexedCatalog {
        let rows: [EventReference]
        private var route = [String: [Int]](), providerAlias = [String: [Int]]()
        private var sportsTerminal = [String: [Int]](), cricketTerminal = [String: [Int]]()

        @MainActor init(_ rows: [EventReference], at now: Date) {
            self.rows = rows
            for (index, row) in rows.enumerated() {
                for key in CatalogRouteIdentity.candidates(from: row.id) { route[key, default: []].append(index) }
                for key in row.sportsFixture?.providerEventIDs ?? [] { providerAlias[key, default: []].append(index) }
                guard VerifiedFixtureTerminalPolicy.state(for: row, at: now) != nil else { continue }
                if let id = row.sportsFixture?.fixtureID { sportsTerminal[id, default: []].append(index) }
                if let id = row.cricketFixture?.fixtureID { cricketTerminal[id, default: []].append(index) }
            }
        }

        func candidates(for event: EventReference) -> [EventReference] {
            // Channel canonicalization joins all current editions by station identity.
            guard !event.isBroadcastChannel else { return rows }
            var exact = Set(providerAlias[event.id] ?? [])
            for key in CatalogRouteIdentity.candidates(from: event.id) { exact.formUnion(route[key] ?? []) }
            guard !exact.isEmpty else { return rows }
            if let id = event.sportsFixture?.fixtureID { exact.formUnion(sportsTerminal[id] ?? []) }
            if let id = event.cricketFixture?.fixtureID { exact.formUnion(cricketTerminal[id] ?? []) }
            return exact.sorted().map { rows[$0] }
        }
    }

    /// Resolve against the caller's current admission registry, which may
    /// include verified terminal facts omitted from its playable listings.
    /// Missing evidence alone still cannot invent a cancellation.
    static func currentEvent(
        for event: AnalyticalDataEngine.EventReference,
        in catalog: [AnalyticalDataEngine.EventReference],
        at now: Date = .init()
    ) -> AnalyticalDataEngine.EventReference? {
        guard !event.hasCatalogIdentityConflict else { return nil }
        if SportsTVStation.identifies(event), let station = SportsTVStation.station(id: event.id) { return station.event }
        if let channel = CricketChannelCatalog.canonicalEvent(for: event, in: catalog) {
            return channel
        }
        // Saved rows may retain their old provider ID while their accepted
        // metadata owns the canonical fixture ID. That identity must survive
        // after terminal projections no longer contain provider aliases.
        let typedTerminal = catalog.filter {
            VerifiedFixtureTerminalPolicy.state(for: $0, at: now) != nil
                && ((event.sportsFixture != nil && $0.sportsFixture?.fixtureID == event.sportsFixture?.fixtureID)
                    || (event.cricketFixture != nil && $0.cricketFixture?.fixtureID == event.cricketFixture?.fixtureID))
        }
        if !typedTerminal.isEmpty {
            guard typedTerminal.count == 1, let terminal = typedTerminal.first else { return nil }
            let request = StreamPlaybackRequest(matchID: terminal.id,
                displayTitle: event.title ?? event.displayTitle, homeTeam: event.homeName, awayTeam: event.awayName,
                category: event.normalizedCategory, kickoffDate: event.kickoffDate, preferredEvent: event)
            // Use the canonical ID only for verification: a same-ID time/team/
            // competition/squad conflict is a veto, never an absent fact that
            // may fall back to the old live object.
            guard CatalogPlaybackIdentity.matchingEvent(for: request, in: catalog) != nil else { return nil }
            if let old = event.cricketFixture {
                guard let current = terminal.cricketFixture, current.competitionID == old.competitionID,
                      current.format == old.format,
                      current.homeTeamID == old.homeTeamID, current.awayTeamID == old.awayTeamID else { return nil }
            }
            return terminal
        }
        // An untyped terminal tombstone owns its stable fixture identity (or
        // an explicit provider alias), never another similarly named fixture.
        let current = catalog.filter {
            VerifiedFixtureTerminalPolicy.state(for: $0, at: now) == nil
                || CatalogRouteIdentity.matches(eventID: $0.id, requestedID: event.id)
                || $0.sportsFixture?.providerEventIDs?.contains(event.id) == true
        }
        switch CatalogPlaybackIdentity.selection(for: StreamPlaybackRequest(event: event), in: current) {
        case .matched(let match): return match
        case .conflicting: return nil
        case .missing: return event
        }
    }

    static func action(
        for event: AnalyticalDataEngine.EventReference,
        in catalog: [AnalyticalDataEngine.EventReference],
        at now: Date = .init(),
        status: FootballMatch.MatchStatus? = nil,
        useDiscoveryIndex: Bool = true,
        discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
        catalogIndex: FixtureCatalogAvailabilityIndex? = nil,
        registry: BroadcastRegistryClient? = nil
    ) -> Action? {
        guard let current = currentEvent(for: event, in: catalog, at: now) else { return nil }
        return actionForCurrentEvent(current, at: now, status: status, useDiscoveryIndex: useDiscoveryIndex,
                                     discoveryIndex: discoveryIndex, catalogIndex: catalogIndex, registry: registry)
    }

    /// Matchday's current projection already has the unique catalog row.
    /// Apply the same admission without resolving it against the full catalog again.
    static func actionForCurrentEvent(
        _ current: EventReference, at now: Date, status: FootballMatch.MatchStatus? = nil,
        useDiscoveryIndex: Bool = true, discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
        catalogIndex: FixtureCatalogAvailabilityIndex? = nil,
        registry: BroadcastRegistryClient? = nil
    ) -> Action? {
        let timing = MatchStartPolicy(event: current, now: now, status: status, discoveryIndex: discoveryIndex, broadcastRegistry: registry)
        guard !current.hasCatalogIdentityConflict, timing.timingAllowsPlayback,
              status?.isLive == true || !current.isPastEstimatedMatchWindow(at: now) else { return nil }
        if StreamPluginProviderMatching.hasActiveCatalogSource(current) {
            return Action(event: current, isChannelFallback: false, evidence: current.isBroadcastChannel ? .explicitStation : .providerListing)
        }
        guard useDiscoveryIndex else { return nil }
        if SportsTVStation.canResolve(current, discoveryIndex: discoveryIndex) || CricketChannelPlaybackPolicy.canResolve(current, discoveryIndex: discoveryIndex) {
            return Action(event: current, isChannelFallback: false, evidence: .explicitStation)
        }
        let request = StreamPlaybackRequest(event: current)
        let index = discoveryIndex ?? .shared
        let matches = BroadcastRegistryWatchPolicy.matches(for: request, enabledProviderCodes: index.enabledProviderCodes,
            discoveryIndex: index, registry: registry, at: now)
        let evidence = matches.map { $0.decisionReceipt(at: now) }
        if (index.summary(for: request, at: now)?.providers.contains {
            $0.compatibleCandidateCount > 0 && ($0.providerCode != "reviewedtv" || matches.contains { $0.broadcast.providerCode == "reviewedtv" })
        }) == true {
            return Action(event: current, isChannelFallback: false, evidence: .compatibleDescriptor, registryEvidence: evidence)
        }
        if !matches.isEmpty {
            let hasProgramme = matches.contains { $0.programmeAuthority != nil || $0.link?.matchMethod == .programme || $0.link?.matchMethod == .channelAssignment }
            return Action(event: current, isChannelFallback: false, evidence: hasProgramme ? .programmeAssignment : .providerListing,
                          registryEvidence: evidence)
        }
        // An unexpired listing or previous compatible discovery may authorize
        // another exact lookup, even after its media URL is no longer reusable.
        if FixtureSourceLookupPresentation.state(for: current, at: now, status: status,
            discoveryIndex: discoveryIndex, catalogIndex: catalogIndex, registry: registry)?.canWatch == true {
            return Action(event: current, isChannelFallback: false, evidence: .freshLookupOpportunity)
        }
        // The official schedule identifies the fixture. Only its own source
        // or a current programme assignment can qualify a match Watch action.
        return nil
    }
}

/// Explicit channel navigation has no fixture or programme claim. Only the
/// reviewed channel capabilities supply only their explicitly owned channels.
@MainActor
enum CricketChannelPlaybackPolicy {
    static func canResolve(_ event: EventReference, discoveryIndex: FixtureStreamDiscoveryIndex? = nil) -> Bool {
        let request = StreamPlaybackRequest(event: event)
        guard CricketBroadcastChannel.identifying(request: request) != nil else { return false }
        let enabled = (discoveryIndex ?? .shared).enabledProviderCodes
        return enabled.contains(StreamPluginProviderMatching.communitySportsProviderCode)
            || enabled.contains(ReviewedTVPlaylistClient.providerCode) && ReviewedTVPlaylistClient.supports(request)
    }
}

/// A successful source listing grants a normal fresh Watch attempt. A newer
/// completed definitive negative check owns that provider's availability
/// until a genuinely newer source observation arrives. This is presentation
/// policy; explicit resolver retries still use the unmodified registry facts.
@MainActor
enum BroadcastRegistryWatchPolicy {
    static func matches(for request: StreamPlaybackRequest, enabledProviderCodes: Set<String>,
                        discoveryIndex: FixtureStreamDiscoveryIndex? = nil, registry: BroadcastRegistryClient? = nil,
                        at now: Date = Date()) -> [BroadcastRegistryMatch] {
        eligible((registry ?? .shared).lookup(for: request, enabledProviderCodes: enabledProviderCodes, at: now),
            for: request, discoveryIndex: discoveryIndex, at: now)
    }

    static func eligible(_ matches: [BroadcastRegistryMatch], for request: StreamPlaybackRequest,
                         discoveryIndex: FixtureStreamDiscoveryIndex? = nil, at now: Date) -> [BroadcastRegistryMatch] {
        let lookups = (discoveryIndex ?? .shared).summary(for: request, at: now)?.providers ?? []
        return matches.filter { match in
            !lookups.contains { lookup in
                lookup.providerCode == match.broadcast.providerCode
                    && lookup.availabilityWithdrawalAt.map { $0 >= match.availabilityObservedAt } == true
            }
        }
    }
}

/// A manual check is not a listed broadcast or fixture authority. Enabled
/// sources may look up a current accepted fixture without inventing a primary
/// descriptor, but they never supply the fixture's identity or LIVE status.
@MainActor
enum OptionalSourceLookupPolicy {
    enum Phase: Equatable { case offer, completion, preflight }

    static func event(
        for event: EventReference,
        in catalog: [EventReference],
        enabledProviderCodes: Set<String>,
        at now: Date = .init(),
        status: FootballMatch.MatchStatus? = nil,
        phase: Phase = .offer,
        catalogIndex: FixtureCatalogAvailabilityIndex? = nil,
        discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
        registry: BroadcastRegistryClient? = nil
    ) -> EventReference? {
        let enabled = Set(enabledProviderCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let hasReviewedOptionalLookup = CuratedStreamSourceCatalog.hasOptionalFixtureSupport(
            event: event, enabledProviderCodes: enabled)
        guard !event.hasCatalogIdentityConflict,
              case .matched(let current) = CatalogPlaybackIdentity.selection(
                for: StreamPlaybackRequest(event: event), in: catalog),
              current.id == event.id, !current.hasCatalogIdentityConflict,
              !current.isBroadcastChannel,
              // A newly attached primary descriptor hides a new optional
              // offer; it must not discard an already resolved CS result.
              phase != .offer || !StreamPluginProviderMatching.hasActiveCatalogSource(current),
              let kickoff = current.kickoffDate,
              CommunitySportsAddonClient.catalogID(for: current.normalizedCategory) != "nuvio_sports_live",
              hasNamedPair(current) else { return nil }

        // Score808 already resolves a dated football fixture through its own
        // public calendar, independently of the primary provider's catalog.
        // Its existing enabled state/window must also permit this explicit
        // check; requiring an optional add-on would strand verified cup rows
        // whenever the primary provider has no listing. No Watch is invented.
        let hasReviewedScore808Lookup = enabled.contains("score808")
            && Score808LateDiscoveryPolicy.isLookupWindow(kickoffDate: current.kickoffDate,
                category: current.normalizedCategory, at: now)
        guard hasReviewedOptionalLookup || hasReviewedScore808Lookup else { return nil }

        let timing = MatchStartPolicy(event: current, now: now, status: status, discoveryIndex: discoveryIndex, broadcastRegistry: registry)
        guard !timing.isStopped, phase == .preflight || timing.timingAllowsPlayback else { return nil }
        let lead = phase == .preflight ? Score808LateDiscoveryPolicy.lookupLeadTime : MatchStartPolicy.playbackLead
        // A source's exact current listing can permit a manual check while the
        // official status still says scheduled. This never changes LIVE status,
        // starts playback, extends a URL, or relaxes descriptor matching.
        let hasListedCatalog = phase != .preflight && kickoff <= now
            && !(current.isPastEstimatedMatchWindow(at: now))
            && ((catalogIndex ?? .shared).summary(for: StreamPlaybackRequest(event: current), at: now)?.providers
                .contains { enabled.contains($0.providerCode) && $0.outcome == .listed } == true
                || (discoveryIndex ?? .shared).summary(for: StreamPlaybackRequest(event: current), at: now)?.providers
                    .contains { enabled.contains($0.providerCode) && $0.compatibleCandidateCount > 0 } == true)

        if let fixture = current.cricketFixture {
            guard current.sportsFixture == nil, current.normalizedCategory == "cricket",
                  !fixture.fixtureID.isEmpty,
                  current.id == CricketFixtureCatalog.fixtureIDPrefix + fixture.fixtureID,
                  fixture.verified else { return nil }
            switch fixture.status {
            case .live:
                guard fixture.isLive(at: now) else { return nil }
            case .scheduled:
                guard (kickoff >= now && kickoff.timeIntervalSince(now) <= lead || hasListedCatalog),
                      hasCurrentReceipt(fixture.observedAt, at: now,
                        maximumAge: CricketFixtureCatalog.statusFreshness) else { return nil }
            default: return nil
            }
        } else if let fixture = current.sportsFixture {
            guard fixture.verified, fixture.sport == current.normalizedCategory,
                  current.id == fixture.fixtureID,
                  fixture.fixtureID.hasPrefix(SportsFixtureCatalog.fixtureIDPrefix + fixture.competitionID + ":"),
                  fixture.eventKind == .match, fixture.participants.count == 2,
                  Set(fixture.participants.map { SportsTeamIdentity.normalized($0.name) })
                    == Set([current.homeName, current.awayName].map(SportsTeamIdentity.normalized)) else { return nil }
            switch fixture.status {
            case .live:
                guard fixture.isLive(at: now) else { return nil }
            case .scheduled:
                // An unchanged confirmed schedule can have an old publisher
                // status timestamp. Its fresh identity receipt permits lookup,
                // never an inferred LIVE state or a reused delivery descriptor.
                guard (kickoff >= now && kickoff.timeIntervalSince(now) <= lead || hasListedCatalog
                    || phase != .preflight && VerifiedFixtureStartingPolicy.contains(current, at: now)),
                      hasCurrentReceipt(fixture.identityReceipt, at: now,
                        maximumAge: SportsFixtureCatalog.statusFreshness) else { return nil }
            default: return nil
            }
        } else { return nil }
        return current
    }

    private static func hasNamedPair(_ event: EventReference) -> Bool {
        // Accepted fixture projections carry explicit participants. A title
        // fallback must not turn an empty/TBC participant into a named team.
        guard let home = event.teams?.home?.name, let away = event.teams?.away?.name else { return false }
        let pair = [home, away].map(SportsTeamIdentity.normalized)
        let placeholders: Set<String> = ["", "home", "away", "tbd", "tbc", "unknown", "teams to be confirmed"]
        return pair[0] != pair[1] && pair.allSatisfy { !placeholders.contains($0) }
    }

    private static func hasCurrentReceipt(_ observedAt: Date, at now: Date, maximumAge: TimeInterval) -> Bool {
        // Use the fixture services' existing status freshness and tolerated
        // source-clock skew. A manual lookup must not renew either receipt.
        (-300...maximumAge).contains(now.timeIntervalSince(observedAt))
    }
}

/// Shared fixture-first presentation for Home, Search, Matchday and Details.
/// Eligibility remains the existing exact official-fixture/source-opt-in policy;
/// an earlier find is descriptive evidence, never a reusable URL or fake Watch.
@MainActor
enum FixtureSourceLookupPresentation {
    struct State: Equatable {
        let currentCandidateCount: Int
        let previouslyFound: Bool
        let isChecking: Bool
        let catalogListedProviderCount: Int
        let catalogPreviouslyListed: Bool
        let hasCompletedLookup: Bool
        let hasLookupFailure: Bool
        let hasConfirmedAvailability: Bool
        let canOfferFreshLookup: Bool
        init(currentCandidateCount: Int, previouslyFound: Bool, isChecking: Bool,
             catalogListedProviderCount: Int = 0, catalogPreviouslyListed: Bool = false,
             hasCompletedLookup: Bool = false, hasLookupFailure: Bool = false,
             hasConfirmedAvailability: Bool = false, canOfferFreshLookup: Bool = false) {
            self.currentCandidateCount = currentCandidateCount; self.previouslyFound = previouslyFound
            self.isChecking = isChecking; self.catalogListedProviderCount = catalogListedProviderCount
            self.catalogPreviouslyListed = catalogPreviouslyListed
            self.hasCompletedLookup = hasCompletedLookup; self.hasLookupFailure = hasLookupFailure
            self.hasConfirmedAvailability = hasConfirmedAvailability
            self.canOfferFreshLookup = canOfferFreshLookup
        }
        private var hasConfirmedDelivery: Bool { currentCandidateCount > 0 || hasConfirmedAvailability }
        var canWatch: Bool { hasConfirmedDelivery || catalogListedProviderCount > 0 }
        /// A live fixture with an enabled optional source can always trigger a
        /// fresh exact lookup even before any cached evidence exists. This is a
        /// manual check, never a fabricated Watch action.
        var canTriggerLookup: Bool { canWatch || canOfferFreshLookup }
        var statusTitle: String {
            if isChecking { return "Finding a broadcast…" }
            return hasCompletedLookup && !hasLookupFailure ? "Broadcast unavailable" : "Broadcast unconfirmed"
        }
        var title: String {
            if canWatch { return "Watch" }
            return canOfferFreshLookup ? "Check streams" : statusTitle
        }
        var symbol: String {
            if canWatch { return "play.fill" }
            return canOfferFreshLookup || isChecking ? "antenna.radiowaves.left.and.right" : "tv.slash"
        }
        func accessibilityLabel(matchTitle: String) -> String {
            if canWatch { return "Watch \(matchTitle)" }
            if canOfferFreshLookup { return "Check streams \(matchTitle)" }
            return "\(matchTitle), \(statusTitle)"
        }
        var accessibilityHint: String {
            if canWatch { return "Finds an available broadcast and opens the player." }
            if canOfferFreshLookup { return "Checks for a current broadcast." }
            return "Availability updates automatically while Fotty is open."
        }
        var detailsTitle: String {
            if hasConfirmedDelivery { return "Ready to watch" }
            if catalogListedProviderCount > 0 { return "Broadcast listed" }
            if canOfferFreshLookup { return "Check streams" }
            return statusTitle
        }
        func detailsMessage(canWatchHere: Bool) -> String {
            if hasConfirmedDelivery { return "Choose Watch to open the broadcast." }
            if catalogListedProviderCount > 0 { return "Choose Watch to find and open the current broadcast." }
            if canOfferFreshLookup { return "Choose Check streams to look for a current broadcast." }
            if isChecking { return "Finding a matching broadcast in the background." }
            return hasCompletedLookup && !hasLookupFailure
                ? "A compatible broadcast isn't available right now."
                : "Broadcast availability hasn't been confirmed."
        }
    }

    static func state(for event: EventReference, at now: Date = Date(),
                      status: FootballMatch.MatchStatus? = nil,
                      enabledProviderCodes: Set<String>? = nil,
                      discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
                      catalogIndex: FixtureCatalogAvailabilityIndex? = nil,
                      registry: BroadcastRegistryClient? = nil) -> State? {
        let index = discoveryIndex ?? .shared
        let enabled = Set((enabledProviderCodes ?? index.enabledProviderCodes)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard OptionalSourceLookupPolicy.event(for: event, in: [event],
            enabledProviderCodes: enabled, at: now, status: status, catalogIndex: catalogIndex,
            discoveryIndex: index, registry: registry) != nil else { return nil }
        let canonical = Set(enabled.compactMap { CuratedStreamSourceCatalog.definition(forProviderCode: $0)?.providerCode })
        let registeredProviders = Set(BroadcastRegistryWatchPolicy.matches(for: StreamPlaybackRequest(event: event),
            enabledProviderCodes: canonical, discoveryIndex: index, registry: registry, at: now).map { $0.broadcast.providerCode })
        // Reviewed TV event playback always needs a current admissible edition
        // assignment. Old catalog or descriptor history cannot bypass it.
        let eligible = registeredProviders.contains("reviewedtv") ? canonical : canonical.subtracting(["reviewedtv"])
        let providers = index.summary(for: StreamPlaybackRequest(event: event), at: now)?.providers
            .filter { eligible.contains($0.providerCode) } ?? []
        let catalog = (catalogIndex ?? (discoveryIndex == nil ? .shared : nil))?
            .summary(for: StreamPlaybackRequest(event: event), at: now)?.providers
            .filter { eligible.contains($0.providerCode) } ?? []
        let candidateCount = providers.reduce(0) { $0 + $1.compatibleCandidateCount }
        let hasConfirmedAvailability = providers.contains { $0.hasRecentlyConfirmedBroadcast(at: now) }
        let eligibleCatalogListings = catalog.filter { listing in
            guard listing.outcome == .listed, let listedAt = listing.checkedAt else { return false }
            // A newer completed descriptor result owns this provider's actual
            // availability. Its older catalog row must not resurrect an empty
            // or rejected delivery; a healthy sibling remains independent.
            return !providers.contains { lookup in
                lookup.providerCode == listing.providerCode
                    && lookup.availabilityWithdrawalAt.map { $0 >= listedAt } == true
            }
        }
        // Fixture-only upcoming rows keep their explicit countdown. A source
        // capability or catalog hint is not a pre-start Watch action.
        if let kickoff = event.kickoffDate, kickoff > now, candidateCount == 0, !hasConfirmedAvailability { return nil }
        let plan = CuratedStreamSourceCatalog.discoveryPlan(for: StreamPlaybackRequest(event: event),
            enabledProviderCodes: canonical, at: now)
        var relevant = Set(plan.optionalSources.map(\.providerCode))
        if plan.score808SiteEligible { relevant.insert("score808") }
        let completed = !relevant.isEmpty && relevant.allSatisfy { code in
            guard let provider = providers.first(where: { $0.providerCode == code }) else { return false }
            switch provider.outcome {
            case .candidates, .empty, .failed(.providerReturnedEmpty): return true
            default: return false
            }
        }
        let failed = providers.contains { provider in
            guard relevant.contains(provider.providerCode) else { return false }
            if case .failed(let category) = provider.outcome { return category != .providerReturnedEmpty }
            return false
        } || catalog.contains { provider in
            guard relevant.contains(provider.providerCode) else { return false }
            if case .failed = provider.outcome { return true }
            return false
        }
        return State(currentCandidateCount: candidateCount,
                     previouslyFound: providers.contains { $0.lastCandidateFoundAt != nil },
                     isChecking: providers.contains { $0.outcome == .checking } || catalog.contains { $0.outcome == .checking },
                     catalogListedProviderCount: Set(eligibleCatalogListings.map(\.providerCode)).union(registeredProviders).count,
                     catalogPreviouslyListed: catalog.contains( where: \.previouslyListed),
                     hasCompletedLookup: completed, hasLookupFailure: failed,
                     hasConfirmedAvailability: hasConfirmedAvailability,
                     canOfferFreshLookup: event.cricketFixture == nil
                        && candidateCount == 0 && !hasConfirmedAvailability
                        && Set(eligibleCatalogListings.map(\.providerCode)).union(registeredProviders).isEmpty
                        && catalog.isEmpty
                        && event.kickoffDate.map { $0 <= now } == true)
    }
}

/// Accepted terminal fixture facts remain authoritative when a separate score
/// poll has not advanced yet. Unverified/nonterminal data gains no precedence.
@MainActor
enum VerifiedFixtureTerminalPolicy {
    enum State: Equatable {
        case finished, cancelled
        var title: String { self == .finished ? "Finished" : "Cancelled" }
    }

    static func state(for event: EventReference, at now: Date = Date()) -> State? {
        if let fixture = event.sportsFixture, fixture.verified,
           fixture.observedAt <= now.addingTimeInterval(300) {
            if fixture.status == .finished { return .finished }
            if fixture.status == .cancelled { return .cancelled }
        }
        if let fixture = event.cricketFixture, fixture.verified,
           fixture.observedAt <= now.addingTimeInterval(300) {
            if fixture.status == .finished { return .finished }
            if fixture.status == .cancelled { return .cancelled }
        }
        return nil
    }
}

/// Matchday keeps elapsed listed starts separate from verified live evidence.
/// Terminal facts remain useful after playable catalogs intentionally omit them;
/// a missing row alone never supplies those facts.
@MainActor
enum MatchdayEventStatePolicy {
    enum Section: Equatable {
        case live, listedNow, upcoming, awaitingConfirmation, timeToBeConfirmed, recent, channel
    }

    static func section(for event: EventReference, at now: Date = .init(),
                        status: FootballMatch.MatchStatus? = nil) -> Section {
        if event.isBroadcastChannel { return .channel }
        // A current accepted terminal receipt must not be demoted by a score
        // poll that still has an earlier in-play/scheduled value. Restrict this
        // precedence to verified terminal facts; other source ordering stays as-is.
        if VerifiedFixtureTerminalPolicy.state(for: event, at: now) != nil { return .recent }
        if let status {
            if status.isFinished || status == .cancelled { return .recent }
            if status == .postponed || status == .suspended { return .timeToBeConfirmed }
            if status.isLive { return .live }
            if !status.isUpcoming { return .awaitingConfirmation }
        } else if let cricket = event.cricketFixture {
            if cricket.status == .finished || cricket.status == .cancelled { return .recent }
            if cricket.status == .postponed { return .timeToBeConfirmed }
            if cricket.isLive(at: now) { return .live }
            if !cricket.verified || cricket.status != .scheduled || event.kickoffDate.map({ $0 <= now }) == true {
                if cricket.hasCurrentProviderListing(at: now), StreamPluginProviderMatching.hasActiveCatalogSource(event) { return .listedNow }
                return event.kickoffDate == nil ? .timeToBeConfirmed : .awaitingConfirmation
            }
        } else if let fixture = event.sportsFixture {
            if fixture.status == .finished || fixture.status == .cancelled { return .recent }
            if fixture.status == .postponed { return .timeToBeConfirmed }
            if fixture.isLive(at: now) { return .live }
            if !fixture.verified || fixture.status != .scheduled || event.kickoffDate.map({ $0 <= now }) == true {
                if fixture.hasCurrentProviderListing(at: now), StreamPluginProviderMatching.hasActiveCatalogSource(event) { return .listedNow }
                return event.kickoffDate == nil ? .timeToBeConfirmed : .awaitingConfirmation
            }
        }
        if status == nil, event.cricketFixture == nil, event.sportsFixture == nil,
           event.isPastEstimatedMatchWindow(at: now) { return .recent }
        if status == nil, event.cricketFixture == nil, event.sportsFixture == nil,
           StreamPluginProviderMatching.hasActiveCatalogSource(event), event.broadcastTiming(at: now) == .live {
            // An elapsed provider start and a supported source describe a
            // listed broadcast, not independently confirmed in-play status.
            // Keep its Watch admission separate from this presentation state.
            return .listedNow
        }
        guard let start = event.kickoffDate else { return .timeToBeConfirmed }
        // In particular, a CPL kickoff (with or without a channel/source) is
        // not an official in-play status. Keep Watch admission independent.
        return start > now ? .upcoming : .awaitingConfirmation
    }

    /// Visible certainty is shared by Details and player controls. Broadcast
    /// windows admit manual Watch but never manufacture official LIVE status.
    static func presentationLabel(for event: EventReference, at now: Date = .init(),
                                  status: FootballMatch.MatchStatus? = nil) -> String {
        switch section(for: event, at: now, status: status) {
        case .live: return "LIVE"
        case .listedNow: return "Broadcast listed"
        case .upcoming: return "Upcoming"
        case .awaitingConfirmation: return "Start unconfirmed"
        case .timeToBeConfirmed:
            return status == .postponed || event.cricketFixture?.status == .postponed || event.sportsFixture?.status == .postponed
                ? "Postponed" : "Time TBC"
        case .recent:
            if let terminal = VerifiedFixtureTerminalPolicy.state(for: event, at: now) { return terminal.title }
            if let status, status.isFinished || status == .cancelled { return status.displayText }
            return "Past listing"
        case .channel: return "Channel"
        }
    }
}

/// Saved/reminded identity can follow a changed start under its existing exact
/// catalog ID. Playback rematching retains its stricter dated admission rule.
@MainActor
enum SavedMatchContinuityPolicy {
    static func corresponds(_ saved: SavedMatchRecord, to event: AnalyticalDataEngine.EventReference) -> Bool {
        currentEvent(for: saved, in: [event]) != nil
    }

    static func currentEvent(
        for saved: SavedMatchRecord,
        in events: [AnalyticalDataEngine.EventReference]
    ) -> AnalyticalDataEngine.EventReference? {
        let exact = events.filter {
            $0.id == saved.id || $0.sportsFixture?.providerEventIDs?.contains(saved.id) == true
                || (saved.sportsFixture != nil && $0.sportsFixture?.fixtureID == saved.sportsFixture?.fixtureID)
        }
        let old = saved.event
        let exactProviderAlias = exact.count == 1 && exact[0].sportsFixture == nil
            && saved.sportsFixture?.providerEventIDs?.contains(exact[0].id) == true
        if exact.isEmpty || exactProviderAlias {
            // A canonical saved row can temporarily be displayed through its
            // recorded provider alias. This does not renew official facts or
            // infer a reschedule from a provider: require the exact same start,
            // a unique admitted alias and retain the accepted typed receipt.
            let aliases = (exactProviderAlias ? exact : events).filter {
                !$0.hasCatalogIdentityConflict && $0.sportsFixture == nil
                    && saved.sportsFixture?.providerEventIDs?.contains($0.id) == true
                    && old.kickoffDate != nil && $0.kickoffDate == old.kickoffDate
                    && CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: old), in: [$0]) != nil
            }
            guard aliases.count == 1, let candidate = aliases.first else { return nil }
            return EventReference(id: saved.id, title: old.title, category: old.category, date: old.date,
                poster: old.poster, popular: old.popular, teams: old.teams, sources: candidate.sources,
                cricketFixture: old.cricketFixture, sportsFixture: old.sportsFixture, competitionID: old.competitionID)
        }
        guard exact.count == 1, let candidate = exact.first, !candidate.hasCatalogIdentityConflict else { return nil }
        if let fixture = old.cricketFixture {
            guard let current = candidate.cricketFixture,
                  current.fixtureID == fixture.fixtureID,
                  current.competitionID == fixture.competitionID else { return nil }
        }
        let current = candidate.id == saved.id ? candidate : EventReference(
            id: saved.id, title: candidate.title, category: candidate.category, date: candidate.date,
            poster: candidate.poster, popular: candidate.popular, teams: candidate.teams, sources: candidate.sources,
            cricketFixture: candidate.cricketFixture, sportsFixture: candidate.sportsFixture,
            competitionID: candidate.competitionID)
        let identity = StreamPlaybackRequest(
            matchID: saved.id, displayTitle: old.title ?? old.displayTitle,
            homeTeam: old.homeName, awayTeam: old.awayName,
            category: old.normalizedCategory, kickoffDate: nil, preferredEvent: old)
        // Preserve the user's opaque bookmark/reminder ID. Only an explicit
        // unique merge receipt or the same typed official identity may refresh
        // it from a canonical fixture row, including later terminal receipts.
        return CatalogPlaybackIdentity.matchingEvent(for: identity, in: [current])
    }
}
