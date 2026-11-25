import Foundation

// MARK: - Football Repository
// The single source of truth for football data in Fotty.
// Manages caching, polling intervals, and provider fallback logic.

/// Controls how aggressively Match Hub hits API-Football (quota discipline).
public enum MatchHubRefreshPolicy: Sendable {
  /// Reuse known schedule/live cache; never spend a provider enrichment call.
  case automatic
  /// Deliberate user refresh — provider enrichment is allowed for covered matches.
  case full
  /// Timer / live tick — reuse cached fixture payload only.
  case liveScoreOnly

  var allowsProviderEnrichment: Bool { self == .full }
}

/// Observation receipts travel with their rows. A completed retry is not a new
/// observation of a cached in-play value.
struct FootballLiveSnapshot {
    let matches: [MatchHubData]
    let observedAt: Date?
    let mode: LiveScoreFeedMode
    let refreshSucceeded: Bool
}

struct FootballScheduleSnapshot {
    let matches: [MatchHubData]
    let observedAt: Date
}

public actor FootballRepository {
    
    public static let shared = FootballRepository()
    
    private let primaryProvider: FootballProvider
    private let officialFPLScoreProvider: FootballProvider
    private let footballDataProvider: FootballProvider
    private let scheduleLoader: (@Sendable (ClosedRange<Date>) async throws -> [MatchHubData])?
    private let currentDate: @Sendable () -> Date
    private var cache: [String: CachedData] = [:]
    /// Only an actual successful details fetch can create these observations;
    /// an automatic cache read or enrichment pass cannot renew them.
    private var detailedLiveObservations: [String: Date] = [:]

    // MARK: - Fixture list caching (reduces API-Football traffic from polling + multi-tab refresh)

    private var liveListCache: [MatchHubData]?
    private var liveListCachedAt: Date?
    private var liveListObservedAt: Date?
    private var liveListRefreshSucceeded = false
    private var liveListCooldownUntil: Date?
    private var liveFeedMode: LiveScoreFeedMode = .inactive
    private let liveListTTL: TimeInterval = 55

    private struct PremiumListCache {
        let key: String
        let matches: [MatchHubData]
        let fetchedAt: Date
    }

    private var premiumListCache: PremiumListCache?
    private var premiumFetchCooldownUntil: Date?
    /// Explicit API-Football league sweep; not an empty-schedule fallback.
    private let premiumListTTL: TimeInterval = 7200

    private struct ScheduleListCache {
        let key: String
        let range: ClosedRange<Date>
        let matches: [MatchHubData]
        let fetchedAt: Date
        let observedAt: Date
    }

    private var scheduleListCache: ScheduleListCache?
    private let scheduleListTTL: TimeInterval = 900
    
    public struct CachedData {
        let data: Any
        let timestamp: Date
        let status: MatchHubData.DataQualityStatus
    }
    
    init(
        scheduleLoader: (@Sendable (ClosedRange<Date>) async throws -> [MatchHubData])? = nil,
        primaryProvider: FootballProvider? = nil,
        officialFPLScoreProvider: FootballProvider? = nil,
        footballDataProvider: FootballProvider? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.primaryProvider = primaryProvider ?? APIFootballProvider(apiKey: Config.apiFootballKey)
        self.officialFPLScoreProvider = officialFPLScoreProvider ?? OfficialFPLScoreProvider()
        self.footballDataProvider = footballDataProvider ?? FootballDataProvider()
        self.scheduleLoader = scheduleLoader
        self.currentDate = now
    }
    
    // MARK: - Repository API

    func matchHubSnapshot(fixtureId: String, policy: MatchHubRefreshPolicy) async throws -> MatchHubSnapshot {
        let expected = findHub(fixtureId: fixtureId)
        let fetched = try await getMatchHubData(fixtureId: fixtureId, policy: policy)
        try Task.checkCancellation()
        let match = MatchHubSnapshot.preservingRoute(fetched, expected: expected, routeID: fixtureId)
        if match.identity.resolves(fixtureId) {
            storeHubInCache(match, fixtureId: fixtureId,
                            resolvedFixtureId: match.fixture.apiFootballFixtureId ?? match.fixture.id)
        }
        return MatchHubSnapshot(match: match, insights: insights(from: match))
    }
    
    /// Match Hub payload (score, events, lineups, stats) with quota-aware refresh policy.
    public func getMatchHubData(
        fixtureId: String,
        policy: MatchHubRefreshPolicy = .automatic
    ) async throws -> MatchHubData {
        // Match Hub may still show the broad football-data schedule, but opening
        // a non-covered competition must not spend API-Football quota.
        if let knownHub = findHub(fixtureId: fixtureId) {
            let isCovered = FootballDataPolicy.supportsLiveScores(
                competition: knownHub.fixture.competition
            )
            // Automatic/timer loads consume the schedule or live-list cache.
            // Only an explicit full refresh may ask for deeper provider data.
            if !isCovered || !policy.allowsProviderEnrichment {
                return knownHub
            }
        }

        let resolvedFixtureId = await resolveAPIFootballFixtureIdIfNeeded(fixtureId)
        let existingEntry = cache[resolvedFixtureId]
        let existingHub = existingEntry?.data as? MatchHubData

        if !policy.allowsProviderEnrichment,
           let existingEntry,
           let existingHub,
           !isScoreCacheStale(existingEntry, hub: existingHub) {
            return reconciledHubFacts(existingHub)
        }

        let includeLineupsAndStats = shouldFetchLineupsAndStats(
            policy: policy,
            existing: existingHub
        )

        do {
            let fetched = try await fetchFixtureDetailsFromPrimary(
                fixtureId: resolvedFixtureId,
                includeLineupsAndStats: includeLineupsAndStats
            )
            var merged = mergeHubData(existing: existingHub, fetched: fetched)
            merged = await enrichHubData(merged)
            if let existingHub {
                merged = preserveEnrichedFields(from: existingHub, into: merged)
            }
            if !hasLineups(merged) {
                merged = await backfillLineupsIfNeeded(
                    hub: merged,
                    fixtureId: fixtureId,
                    resolvedFixtureId: resolvedFixtureId
                )
            }
            try Task.checkCancellation()
            registerDetailedLiveObservation(from: fetched)
            merged = reconciledHubFacts(merged)
            storeHubInCache(merged, fixtureId: fixtureId, resolvedFixtureId: resolvedFixtureId)
            return merged
        } catch {
            try propagateCancellation(error)
            print("[FootballRepository] Fetch failed for \(resolvedFixtureId): \(error)")
            if let existingHub {
                detailedLiveObservations.removeValue(forKey: matchKey(for: existingHub))
                return reconciledHubFacts(staleSnapshot(existingHub))
            }
            if let scheduleHub = findHub(fixtureId: fixtureId) ?? findHub(fixtureId: resolvedFixtureId) {
                var enriched = await enrichHubData(scheduleHub)
                if let cachedLineupSource = (cache[resolvedFixtureId]?.data as? MatchHubData)
                    ?? (cache[fixtureId]?.data as? MatchHubData),
                   hasLineups(cachedLineupSource) {
                    enriched = preserveEnrichedFields(from: cachedLineupSource, into: enriched)
                }
                if !hasLineups(enriched) {
                    enriched = await backfillLineupsIfNeeded(
                        hub: enriched,
                        fixtureId: fixtureId,
                        resolvedFixtureId: resolvedFixtureId
                    )
                }
                try Task.checkCancellation()
                storeHubInCache(enriched, fixtureId: fixtureId, resolvedFixtureId: resolvedFixtureId)
                return reconciledHubFacts(staleSnapshot(enriched))
            }
            throw error
        }
    }
    
    /// Get data specifically for the Insights tab (only fields backed by hub feed or honest empties).
    public func getMatchInsights(
        fixtureId: String,
        policy: MatchHubRefreshPolicy = .automatic
    ) async throws -> MatchInsightsData {
        let hubData = try await getMatchHubData(fixtureId: fixtureId, policy: policy)
        return insights(from: hubData)
    }

    /// Derive every insight from the exact snapshot rendered by the parent.
    /// No second fetch or independent timestamp can outrun its score/header.
    func insights(from hubData: MatchHubData) -> MatchInsightsData {
        return MatchInsightsData(
            fixtureId: hubData.fixture.id,
            homeForm: [],
            awayForm: [],
            headToHead: nil,
            keyInsights: deriveInsights(from: hubData),
            momentum: calculateMomentum(from: hubData),
            winProbability: nil,
            lastUpdated: hubData.lastUpdated
        )
    }

    private func staleSnapshot(_ hub: MatchHubData) -> MatchHubData {
        MatchHubData(fixture: hub.fixture, homeTeam: hub.homeTeam, awayTeam: hub.awayTeam,
                     score: hub.score, events: hub.events, homeLineup: hub.homeLineup,
                     awayLineup: hub.awayLineup, statistics: hub.statistics, teamNews: hub.teamNews,
                     lastUpdated: hub.lastUpdated, dataQuality: .stale)
    }
    
    /// Get all fixtures for a specific date
    public func getFixtures(for date: Date = Date()) async throws -> [FottyFixture] {
        return try await primaryProvider.fetchFixtures(date: date)
    }
    
    // MARK: - Cache Strategy
    
    public func getLiveMatches() async throws -> [MatchHubData] {
        try await getLiveSnapshot().matches
    }

    func getLiveSnapshot() async throws -> FootballLiveSnapshot {
        try Task.checkCancellation()
        let now = currentDate()
        if let schedule = scheduleListCache,
           schedule.range.contains(now),
           !FootballDataPolicy.shouldPollLiveScores(
               fixtures: schedule.matches.map(\.fixture),
               at: now
           ) {
            liveListCache = []
            // Keep this nil so the first poll entering the pre-kickoff window
            // cannot be delayed by an empty out-of-window cache entry.
            liveListCachedAt = nil
            liveListObservedAt = nil
            liveListRefreshSucceeded = true
            detailedLiveObservations.removeAll(keepingCapacity: true)
            liveListCooldownUntil = nil
            liveFeedMode = .inactive
            return FootballLiveSnapshot(matches: [], observedAt: nil, mode: .inactive, refreshSucceeded: true)
        }
        if let until = liveListCooldownUntil, now < until, let cached = liveListCache {
            return cachedLiveSnapshot(matches: cached)
        }
        if liveListRefreshSucceeded, let at = liveListCachedAt, let cached = liveListCache,
           (0..<liveListTTL).contains(now.timeIntervalSince(at)) {
            return cachedLiveSnapshot(matches: cached)
        }
        do {
            let official = try await officialFPLScoreProvider.fetchLiveScores()
                .filter { FootballDataPolicy.supportsLiveScores(competition: $0.fixture.competition) }
            try Task.checkCancellation()
            return try commitLiveList(official, mode: .officialFPL)
        } catch {
            try propagateCancellation(error)
            print("[FootballRepository] Official FPL live feed failed: \(error)")
        }

        do {
            let primary = try await primaryProvider.fetchLiveScores()
                .filter { FootballDataPolicy.supportsLiveScores(competition: $0.fixture.competition) }
            try Task.checkCancellation()
            return try commitLiveList(primary, mode: .live)
        } catch {
            try propagateCancellation(error)
            let primaryError = error
            let rateLimited = isProviderRateLimited(primaryError)
            do {
                let fallback = try await footballDataProvider.fetchLiveScores()
                    .filter { FootballDataPolicy.supportsLiveScores(competition: $0.fixture.competition) }
                try Task.checkCancellation()
                let committed = try commitLiveList(
                    fallback,
                    mode: rateLimited ? .quotaFallback : .delayedFallback
                )
                if rateLimited {
                    liveListCooldownUntil = currentDate().addingTimeInterval(120)
                }
                return committed
            } catch {
                try propagateCancellation(error)
            }
            liveFeedMode = .unavailable
            liveListRefreshSucceeded = false
            detailedLiveObservations.removeAll(keepingCapacity: true)
            if let cached = liveListCache {
                liveListCooldownUntil = currentDate().addingTimeInterval(120)
                FottyQualityStore.shared.record(
                    category: .footballData,
                    name: "live_refresh",
                    outcome: .recovered,
                    details: ["feed": "cached", "result": "provider_failure"]
                )
                return cachedLiveSnapshot(matches: cached)
            }
            FottyQualityStore.shared.record(
                category: .footballData,
                name: "live_refresh",
                outcome: .failure,
                details: ["feed": "unavailable", "result": "provider_failure"]
            )
            throw primaryError
        }
    }

    private func cachedLiveSnapshot(matches: [MatchHubData]) -> FootballLiveSnapshot {
        FootballLiveSnapshot(matches: mergeLiveMatchesWithSchedule(matches), observedAt: liveListObservedAt,
            mode: liveFeedMode, refreshSucceeded: liveListRefreshSucceeded)
    }

    private func propagateCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
        try Task.checkCancellation()
    }

    func currentLiveFeedMode() -> LiveScoreFeedMode {
        liveFeedMode
    }

    private func enrichHubData(_ hub: MatchHubData) async -> MatchHubData {
        await TheSportsDBMatchService.shared.enrich(hub)
    }

    private func storeHubInCache(_ hub: MatchHubData, fixtureId: String, resolvedFixtureId: String) {
        var keys = Set([resolvedFixtureId, fixtureId, hub.fixture.id])
        if let apiId = hub.fixture.apiFootballFixtureId { keys.insert(apiId) }
        // Replacing current facts must not erase previously fetched details.
        // Aliases alone are insufficient: only the same match and competition
        // scope may contribute enrichment, never status, scores or receipts.
        let previous = keys.compactMap { cache[$0]?.data as? MatchHubData }
            .filter { sameMatchScope($0, as: hub) }
            .sorted { $0.lastUpdated > $1.lastUpdated }
        let stored = previous.reduce(hub) { preserveEnrichedFields(from: $1, into: $0) }
        for key in keys {
            updateCache(id: key, data: stored)
        }
    }

    /// TheSportsDB + optional API-Football lineups when the live/score cache has no XI yet.
    private func backfillLineupsIfNeeded(
        hub: MatchHubData,
        fixtureId: String,
        resolvedFixtureId: String
    ) async -> MatchHubData {
        if hasLineups(hub) { return hub }

        var merged = await enrichHubData(hub)
        if hasLineups(merged) { return merged }

        guard Int(resolvedFixtureId) != nil else { return merged }

        do {
            let fetched = try await fetchFixtureDetailsFromPrimary(
                fixtureId: resolvedFixtureId,
                includeLineupsAndStats: true
            )
            merged = mergeHubData(existing: merged, fetched: fetched)
            merged = await enrichHubData(merged)
            if hasLineups(merged) { return merged }
        } catch {
            print("[FootballRepository] Lineup backfill API failed for \(resolvedFixtureId): \(error)")
        }

        return merged
    }

    /// Arena / Dashboard schedule — football-data.org (~1 call / 15 min).
    /// Valid empty windows remain empty; source failures still throw.
    public func getScheduleFixtures(dateRange: ClosedRange<Date>) async throws -> [MatchHubData] {
        try await getScheduleSnapshot(dateRange: dateRange).matches
    }

    func getScheduleSnapshot(dateRange: ClosedRange<Date>) async throws -> FootballScheduleSnapshot {
        try Task.checkCancellation()
        let refreshStartedAt = currentDate()
        let cacheKey = premiumCacheKey(for: dateRange)
        if let c = scheduleListCache, c.key == cacheKey,
           (0..<scheduleListTTL).contains(refreshStartedAt.timeIntervalSince(c.fetchedAt)) {
            return FootballScheduleSnapshot(matches: c.matches, observedAt: c.observedAt)
        }

        let schedule = try await fetchScheduleFromFootballData(dateRange: dateRange)
        try Task.checkCancellation()
        let fetchedAt = currentDate()
        let observedAt = try observationDate(for: schedule, successfulEmptyAt: fetchedAt)
        indexMatchKeys(from: schedule)

        let sorted = schedule.sorted { $0.fixture.utcDate < $1.fixture.utcDate }
        scheduleListCache = ScheduleListCache(
            key: cacheKey,
            range: dateRange,
            matches: sorted,
            fetchedAt: fetchedAt,
            observedAt: observedAt
        )
        if let live = liveListCache {
            // A newly accepted terminal schedule fact also repairs older hub
            // lookups. This changes no source receipt or schedule authority.
            liveListCache = mergeLiveMatchesWithSchedule(live)
        }
        for match in sorted {
            let stored = (cache[match.fixture.id]?.data as? MatchHubData)
                .map { preserveEnrichedFields(from: $0, into: match) } ?? match
            updateCache(id: match.fixture.id, data: stored)
        }
        FottyQualityStore.shared.record(
            category: .footballData,
            name: "schedule_refresh",
            outcome: .success,
            durationMilliseconds: max(0, Int(currentDate().timeIntervalSince(refreshStartedAt) * 1_000)),
            details: ["feed": "football_data", "result": sorted.isEmpty ? "empty" : "fixtures"]
        )
        return FootballScheduleSnapshot(matches: sorted, observedAt: observedAt)
    }
    
    /// Explicit API-Football schedule request. It follows the same competition
    /// allowlist as live scores so a football-data outage cannot create a quota burst.
    public func getPremiumFixtures(dateRange: ClosedRange<Date>) async throws -> [MatchHubData] {
        let cacheKey = premiumCacheKey(for: dateRange)
        if let c = premiumListCache, c.key == cacheKey, Date().timeIntervalSince(c.fetchedAt) < premiumListTTL {
            return c.matches
        }
        if let until = premiumFetchCooldownUntil, Date() < until, let c = premiumListCache, c.key == cacheKey {
            return c.matches
        }

        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        let season = month < 7 ? String(year - 1) : String(year)
        
        var byFixtureID: [String: MatchHubData] = [:]

        for competition in FootballDataPolicy.activeLiveScoreCompetitions {
            do {
                let matches = try await primaryProvider.fetchLeagueFixtures(
                    leagueId: competition.apiFootballLeagueId,
                    season: season
                )
                for m in matches where FootballDataPolicy.supportsLiveScores(competition: m.fixture.competition) {
                    byFixtureID[m.fixture.id] = m
                }
            } catch {
                print("[FootballRepository] \(competition.displayName) fallback failed: \(error)")
                if isProviderRateLimited(error) {
                    premiumFetchCooldownUntil = Date().addingTimeInterval(180)
                }
                if let c = premiumListCache, c.key == cacheKey {
                    return c.matches
                }
                throw error
            }
        }
        
        let allMatches = Array(byFixtureID.values)
        
        // The schedule contract is strict: never fill an empty requested window with
        // old fixtures from another date range or season.
        let finalMatches = FootballFixtureWindowPolicy.filter(
            allMatches,
            dateRange: dateRange,
            kickoff: { $0.fixture.utcDate }
        )
        
        // Update cache for these matches
        for match in finalMatches {
            updateCache(id: match.fixture.id, data: match)
        }
        
        let sorted = finalMatches.sorted { $0.fixture.utcDate < $1.fixture.utcDate }
        premiumListCache = PremiumListCache(key: cacheKey, matches: sorted, fetchedAt: Date())
        premiumFetchCooldownUntil = nil
        return sorted
    }

    /// Clears all list caches (use sparingly — triggers a large API burst).
    public func invalidateFixtureListCaches() {
        invalidateLiveListCache()
        invalidatePremiumListCache()
    }

    /// Pull-to-refresh: live scores only; schedule refreshed on its own TTL unless this is called.
    public func invalidateLiveListCache() {
        liveListCache = nil
        liveListCachedAt = nil
        liveListObservedAt = nil
        liveListRefreshSucceeded = false
        liveListCooldownUntil = nil
    }

    public func invalidateScheduleListCache() {
        scheduleListCache = nil
    }

    public func invalidatePremiumListCache() {
        premiumListCache = nil
        premiumFetchCooldownUntil = nil
    }

    private func premiumCacheKey(for range: ClosedRange<Date>) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: range.lowerBound).timeIntervalSince1970
        let end = cal.startOfDay(for: range.upperBound).timeIntervalSince1970
        return "\(Int(start))_\(Int(end))"
    }

    private func isProviderRateLimited(_ error: Error) -> Bool {
        guard let e = error as? FootballProviderError else { return false }
        if case .rateLimited = e { return true }
        return false
    }
    
    private func updateCache(id: String, data: Any) {
        let quality = (data as? MatchHubData)?.dataQuality ?? .verified
        cache[id] = CachedData(data: data, timestamp: Date(), status: quality)
    }
    
    /// Drops cached hub payload so the next `getMatchHubData` / insights pull refetches from the provider.
    public func invalidateHubCache(for fixtureId: String) {
        let keysToRemove = cache.keys.filter { key in
            guard let hub = cache[key]?.data as? MatchHubData else { return key == fixtureId }
            return key == fixtureId
                || hub.identity.resolves(fixtureId)
        }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }
    
    private func isScoreCacheStale(_ cached: CachedData, hub: MatchHubData) -> Bool {
        let age = Date().timeIntervalSince(cached.timestamp)
        let ttl: TimeInterval
        switch hub.fixture.status {
        case .live, .extraTime, .penalties:
            ttl = 90
        case .halfTime:
            ttl = 90
        case .fullTime:
            ttl = 3600
        case .scheduled, .preMatch:
            ttl = 1800
        default:
            ttl = 300
        }
        return age > ttl
    }

    private func shouldFetchLineupsAndStats(policy: MatchHubRefreshPolicy, existing: MatchHubData?) -> Bool {
        switch policy {
        case .liveScoreOnly:
            return false
        case .full:
            guard let existing else { return true }
            if !hasLineups(existing) { return true }
            return existing.statistics.isEmpty
        case .automatic:
            return false
        }
    }

    private func hasLineups(_ hub: MatchHubData?) -> Bool {
        guard let hub else { return false }
        let homeOK = !(hub.homeLineup?.startingXi.isEmpty ?? true)
        let awayOK = !(hub.awayLineup?.startingXi.isEmpty ?? true)
        return homeOK && awayOK
    }

    private func fetchFixtureDetailsFromPrimary(
        fixtureId: String,
        includeLineupsAndStats: Bool
    ) async throws -> MatchHubData {
        if let api = primaryProvider as? APIFootballProvider {
            return try await api.fetchFixtureDetails(
                fixtureId: fixtureId,
                includeLineupsAndStats: includeLineupsAndStats
            )
        }
        return try await primaryProvider.fetchFixtureDetails(fixtureId: fixtureId)
    }

    private func mergeHubData(existing: MatchHubData?, fetched: MatchHubData) -> MatchHubData {
        guard let existing else { return fetched }
        return MatchHubData(
            fixture: fetched.fixture,
            homeTeam: fetched.homeTeam,
            awayTeam: fetched.awayTeam,
            score: fetched.score,
            events: fetched.events.isEmpty ? existing.events : fetched.events,
            homeLineup: preferLineup(existing: existing.homeLineup, fetched: fetched.homeLineup),
            awayLineup: preferLineup(existing: existing.awayLineup, fetched: fetched.awayLineup),
            statistics: existing.statistics.isEmpty ? fetched.statistics : existing.statistics,
            teamNews: existing.teamNews.isEmpty ? fetched.teamNews : existing.teamNews,
            lastUpdated: Date(),
            dataQuality: fetched.dataQuality
        )
    }

    private func preferLineup(existing: FottyLineup?, fetched: FottyLineup?) -> FottyLineup? {
        if let existing, !existing.startingXi.isEmpty { return existing }
        if let fetched, !fetched.startingXi.isEmpty { return fetched }
        return existing ?? fetched
    }

    private func fetchScheduleFromFootballData(dateRange: ClosedRange<Date>) async throws -> [MatchHubData] {
        let raw: [MatchHubData]
        if let scheduleLoader {
            raw = try await scheduleLoader(dateRange)
        } else {
            guard let fd = footballDataProvider as? FootballDataProvider else {
                throw FootballProviderError.malformedData
            }
            raw = try await fd.fetchSchedule(in: dateRange)
        }
        return raw.filter { Config.Arena.discoveryIncludes(competition: $0.fixture.competition) }
    }

    private var apiFootballIdByMatchKey: [String: String] = [:]

    private func indexMatchKeys(from matches: [MatchHubData]) {
        if let live = liveListCache {
            for match in live {
                let apiId = match.fixture.apiFootballFixtureId ?? match.fixture.id
                apiFootballIdByMatchKey[matchKey(for: match)] = apiId
            }
        }
        for match in matches where FootballDataPolicy.supportsLiveScores(competition: match.fixture.competition) {
            let apiId = match.fixture.apiFootballFixtureId ?? match.fixture.id
            if match.dataQuality == .verified || match.fixture.apiFootballFixtureId != nil {
                apiFootballIdByMatchKey[matchKey(for: match)] = apiId
            }
        }
    }

    private func matchKey(for match: MatchHubData) -> String {
        match.identity.matchKey
    }

    private func indexByCanonicalMatchKey(
        _ matches: [MatchHubData],
        source: String
    ) -> [String: MatchHubData] {
        var indexed: [String: MatchHubData] = [:]
        for match in matches {
            let key = matchKey(for: match)
            guard let existing = indexed[key] else {
                indexed[key] = match
                continue
            }

            if existing.fixture.id != match.fixture.id
                || existing.fixture.apiFootballFixtureId != match.fixture.apiFootballFixtureId {
                FottyQualityStore.shared.record(
                    category: .matchIdentity,
                    name: "alias_conflict",
                    outcome: .failure,
                    details: ["source": source, "reason_code": "duplicate_match_key"]
                )
            }

            // Deterministic conflict handling: prefer an explicit provider alias,
            // then the fresher record. Never depend on feed array order alone.
            let existingHasAlias = existing.fixture.apiFootballFixtureId != nil
            let candidateHasAlias = match.fixture.apiFootballFixtureId != nil
            if candidateHasAlias != existingHasAlias {
                indexed[key] = candidateHasAlias ? match : existing
            } else if match.lastUpdated > existing.lastUpdated {
                indexed[key] = match
            }
        }
        return indexed
    }

    private func commitLiveList(_ raw: [MatchHubData], mode: LiveScoreFeedMode) throws -> FootballLiveSnapshot {
        try Task.checkCancellation()
        let fetchedAt = currentDate()
        // Official FPL can return its still-valid in-memory resource. Preserve
        // that original resource date instead of turning each retry into LIVE.
        let observedAt = try observationDate(for: raw, successfulEmptyAt: fetchedAt)
        let merged = mergeLiveMatchesWithSchedule(raw)
        for match in merged {
            storeHubInCache(
                match,
                fixtureId: match.fixture.id,
                resolvedFixtureId: match.fixture.hubFixtureId
            )
        }
        liveListCache = merged
        liveListCachedAt = fetchedAt
        liveListObservedAt = observedAt
        liveListRefreshSucceeded = true
        let activeKeys = Set(merged.filter { $0.fixture.status.isLive }.map { matchKey(for: $0) })
        detailedLiveObservations = detailedLiveObservations.filter { activeKeys.contains($0.key) }
        liveListCooldownUntil = nil
        liveFeedMode = mode
        indexMatchKeys(from: merged)
        FottyQualityStore.shared.record(
            category: .footballData,
            name: "live_refresh",
            outcome: .success,
            details: ["feed": mode.rawValue, "result": merged.isEmpty ? "empty" : "live"]
        )
        return FootballLiveSnapshot(matches: merged, observedAt: observedAt,
            mode: mode, refreshSucceeded: true)
    }

    private func observationDate(for rows: [MatchHubData], successfulEmptyAt now: Date) throws -> Date {
        guard !rows.isEmpty else { return now }
        let receipts = rows.flatMap { [$0.lastUpdated, $0.fixture.lastUpdated] }
        guard receipts.allSatisfy({
            $0.timeIntervalSince1970.isFinite && $0 <= now
        }), let earliest = receipts.min() else {
            throw FootballProviderError.staleData
        }
        return earliest
    }

    /// Live providers use their own fixture/team ids. Keep the football-data
    /// schedule identity so navigation, alerts, and stream matching remain stable.
    private func mergeLiveMatchesWithSchedule(_ live: [MatchHubData]) -> [MatchHubData] {
        guard let currentSchedule = scheduleListCache else { return live }
        let scheduleByKey = indexByCanonicalMatchKey(currentSchedule.matches, source: "schedule_feed")
        return live.map { row in
            guard let schedule = scheduleByKey[matchKey(for: row)] else { return row }
            return mergedScoreRow(schedule: schedule, live: row)
        }

    }

    private func mergedScoreRow(schedule: MatchHubData, live: MatchHubData) -> MatchHubData {
        switch schedule.fixture.status {
        case .fullTime, .cancelled, .abandoned:
            return preserveEnrichedFields(from: live, into: schedule)
        default:
            break
        }
        return applyingFacts(from: live, to: schedule)
    }

    private func applyingFacts(from live: MatchHubData, to schedule: MatchHubData) -> MatchHubData {
        let teams = matchingOfficialArtwork(from: live, preserving: schedule)
        let apiFootballFixtureId: String?
        if let explicit = live.fixture.apiFootballFixtureId {
            apiFootballFixtureId = explicit
        } else if live.dataQuality == .verified {
            apiFootballFixtureId = live.fixture.id
        } else {
            apiFootballFixtureId = schedule.fixture.apiFootballFixtureId
        }

        let fixture = FottyFixture(
            id: schedule.fixture.id,
            utcDate: schedule.fixture.utcDate,
            status: live.fixture.status,
            competition: schedule.fixture.competition,
            venue: schedule.fixture.venue,
            matchday: schedule.fixture.matchday ?? live.fixture.matchday,
            apiFootballFixtureId: apiFootballFixtureId,
            roundLabel: schedule.fixture.roundLabel ?? live.fixture.roundLabel,
            lastUpdated: live.fixture.lastUpdated,
            elapsedMinutes: live.fixture.elapsedMinutes,
            extraMinutes: live.fixture.extraMinutes
        )
        return MatchHubData(
            fixture: fixture,
            homeTeam: teams.home,
            awayTeam: teams.away,
            score: live.score,
            events: live.events.isEmpty ? schedule.events : live.events,
            homeLineup: live.homeLineup ?? schedule.homeLineup,
            awayLineup: live.awayLineup ?? schedule.awayLineup,
            statistics: live.statistics.isEmpty ? schedule.statistics : live.statistics,
            teamNews: live.teamNews.isEmpty ? schedule.teamNews : live.teamNews,
            lastUpdated: live.lastUpdated,
            dataQuality: live.dataQuality
        )
    }

    private func resolveAPIFootballFixtureIdIfNeeded(_ fixtureId: String) async -> String {
        if let hub = findHub(fixtureId: fixtureId) {
            if let api = hub.fixture.apiFootballFixtureId, !api.isEmpty { return api }
            let key = matchKey(for: hub)
            if let apiId = apiFootballIdByMatchKey[key] { return apiId }
            if let resolved = await TheSportsDBMatchService.shared.resolveAPIFootballFixtureId(
                home: hub.homeTeam.name,
                away: hub.awayTeam.name,
                date: hub.fixture.utcDate
            ) {
                apiFootballIdByMatchKey[key] = resolved
                return resolved
            }
        }
        if let key = scheduleListCache?.matches.first(where: { $0.fixture.id == fixtureId }).map({ matchKey(for: $0) }),
           let apiId = apiFootballIdByMatchKey[key] {
            return apiId
        }
        return fixtureId
    }

    private func findHub(fixtureId: String) -> MatchHubData? {
        if let live = liveListCache?.first(where: { $0.identity.resolves(fixtureId) }) { return reconciledHubFacts(live) }
        if let scheduled = scheduleListCache?.matches.first(where: { $0.identity.resolves(fixtureId) }) { return reconciledHubFacts(scheduled) }
        if let cached = cache[fixtureId]?.data as? MatchHubData { return reconciledHubFacts(cached) }
        if let cached = cache.values.compactMap({ $0.data as? MatchHubData }).first(where: {
            $0.identity.resolves(fixtureId)
        }) {
            return reconciledHubFacts(cached)
        }
        return nil
    }

    private func registerDetailedLiveObservation(from data: MatchHubData) {
        let now = currentDate()
        detailedLiveObservations = detailedLiveObservations.filter { (0...600).contains(now.timeIntervalSince($0.value)) }
        guard data.fixture.status.isLive,
              data.dataQuality != .stale, data.dataQuality != .degraded,
              let receipt = try? observationDate(for: [data], successfulEmptyAt: now),
              (0...600).contains(now.timeIntervalSince(receipt)) else { return }
        detailedLiveObservations[matchKey(for: data)] = receipt
    }

    /// Header/Details must obey the same current evidence as the live rail.
    /// Reconcile only score/status facts; retain the full existing enrichment
    /// and route identity so a failed poll never destroys useful match content.
    private func reconciledHubFacts(_ original: MatchHubData) -> MatchHubData {
        let now = currentDate()
        let identity = matchKey(for: original)
        func sameScope(_ data: MatchHubData) -> Bool {
            sameMatchScope(data, as: original)
        }
        let candidates = (scheduleListCache?.matches ?? []) + (liveListCache ?? [])
            + cache.values.compactMap { $0.data as? MatchHubData }
        let enriched = candidates.filter(sameScope).sorted { $0.lastUpdated > $1.lastUpdated }
            .reduce(original) { preserveEnrichedFields(from: $1, into: $0) }
        if let terminal = (candidates + [original]).filter({
            sameScope($0) && ($0.fixture.status.isFinished || $0.fixture.status == .cancelled)
                && $0.dataQuality != .stale && $0.dataQuality != .degraded
                && $0.lastUpdated <= now && $0.fixture.lastUpdated <= now
        }).max(by: { $0.lastUpdated < $1.lastUpdated }) {
            return applyingFacts(from: terminal, to: enriched)
        }
        if liveListRefreshSucceeded, liveFeedMode != .inactive, liveFeedMode != .unavailable,
           let receipt = liveListObservedAt, (0...600).contains(now.timeIntervalSince(receipt)),
           let current = liveListCache?.first(where: {
               sameScope($0) && $0.fixture.status.isLive
                   && $0.dataQuality != .stale && $0.dataQuality != .degraded
                   && (0...600).contains(now.timeIntervalSince($0.lastUpdated))
                   && (0...600).contains(now.timeIntervalSince($0.fixture.lastUpdated))
           }) {
            return applyingFacts(from: current, to: enriched)
        }
        if let receipt = detailedLiveObservations[identity],
           (0...600).contains(now.timeIntervalSince(receipt)), original.fixture.status.isLive {
            return enriched
        }
        guard original.fixture.status.isLive else { return enriched }
        let fixture = FottyFixture(id: original.fixture.id, utcDate: original.fixture.utcDate, status: .unknown,
            competition: original.fixture.competition, venue: original.fixture.venue, matchday: original.fixture.matchday,
            apiFootballFixtureId: original.fixture.apiFootballFixtureId, roundLabel: original.fixture.roundLabel,
            lastUpdated: original.fixture.lastUpdated, elapsedMinutes: nil, extraMinutes: nil)
        return MatchHubData(fixture: fixture, homeTeam: enriched.homeTeam, awayTeam: enriched.awayTeam,
            score: enriched.score, events: enriched.events, homeLineup: enriched.homeLineup,
            awayLineup: enriched.awayLineup, statistics: enriched.statistics, teamNews: enriched.teamNews,
            lastUpdated: original.lastUpdated, dataQuality: .stale)
    }

    private func sameMatchScope(_ data: MatchHubData, as original: MatchHubData) -> Bool {
        guard matchKey(for: data) == matchKey(for: original) else { return false }
        return FootballDataPolicy.supportsLiveScores(competition: original.fixture.competition)
            ? FootballDataPolicy.supportsLiveScores(competition: data.fixture.competition)
            : data.fixture.competition.id == original.fixture.competition.id
    }

    private func preserveEnrichedFields(from existing: MatchHubData, into merged: MatchHubData) -> MatchHubData {
        let teams = matchingOfficialArtwork(from: existing, preserving: merged, keepingTrustedTarget: true)
        return MatchHubData(
            fixture: merged.fixture,
            homeTeam: teams.home,
            awayTeam: teams.away,
            score: merged.score,
            events: merged.events.isEmpty ? existing.events : merged.events,
            homeLineup: merged.homeLineup ?? existing.homeLineup,
            awayLineup: merged.awayLineup ?? existing.awayLineup,
            statistics: merged.statistics.isEmpty ? existing.statistics : merged.statistics,
            teamNews: merged.teamNews.isEmpty ? existing.teamNews : merged.teamNews,
            lastUpdated: merged.lastUpdated,
            dataQuality: merged.dataQuality
        )
    }

    /// Team/fixture IDs remain in the schedule namespace. Only the official
    /// PL publisher's mapped code-based artwork is portable across providers.
    private func matchingOfficialArtwork(from facts: MatchHubData, preserving target: MatchHubData,
                                         keepingTrustedTarget: Bool = false) -> (home: FottyTeam, away: FottyTeam) {
        guard sameMatchScope(facts, as: target), facts.dataQuality == .official,
              FootballDataPolicy.supportsLiveScores(competition: facts.fixture.competition),
              facts.fixture.status.isLive || facts.fixture.status.isFinished else {
            return (target.homeTeam, target.awayTeam)
        }
        func team(_ identity: FottyTeam, artwork: FottyTeam) -> FottyTeam {
            if keepingTrustedTarget, target.dataQuality == .official,
               FootballDataPolicy.isOfficialPremierLeagueCrestURL(identity.crestURL) { return identity }
            guard FootballDataPolicy.isOfficialPremierLeagueCrestURL(artwork.crestURL) else { return identity }
            return FottyTeam(id: identity.id, name: identity.name, shortName: identity.shortName,
                crestURL: artwork.crestURL, color: identity.color)
        }
        return (team(target.homeTeam, artwork: facts.homeTeam), team(target.awayTeam, artwork: facts.awayTeam))
    }
    
    // MARK: - Derived Logic (Non-API)
    
    private func deriveInsights(from data: MatchHubData) -> [String] {
        var insights: [String] = []
        let home = data.homeTeam.displayName
        let away = data.awayTeam.displayName
        let h = data.score.home
        let a = data.score.away
        let totalGoals = h + a
        
        switch data.fixture.status {
        case .live, .extraTime, .penalties:
            insights.append("\(home) \(h)–\(a) \(away) — live.")
        case .halfTime:
            insights.append("Half time: \(home) \(h)–\(a) \(away).")
        case .fullTime:
            insights.append("Full time: \(home) \(h)–\(a) \(away).")
        default:
            if totalGoals > 0 {
                insights.append("Score in feed: \(home) \(h)–\(a) \(away).")
            }
        }
        
        if !data.events.isEmpty {
            insights.append("\(data.events.count) events logged in the match feed.")
        }
        
        if totalGoals >= 4, data.fixture.status.isLive || data.fixture.status.isFinished {
            insights.append("High-scoring affair (\(totalGoals) goals) — momentum can swing quickly.")
        } else if totalGoals == 0, data.fixture.status.isLive {
            insights.append("Still goalless — tight lines or finishing still warming up.")
        } else if abs(h - a) >= 3, totalGoals >= 3 {
            insights.append("One-sided scoreline — trailing side may need to chase the game.")
        }
        
        let cards = data.events.filter { $0.type == .yellowCard || $0.type == .redCard }.count
        if cards > 5 {
            insights.append("Physical match: \(cards) cards — discipline under pressure.")
        } else if cards >= 3 {
            insights.append("\(cards) bookings so far — midfield and duels getting sharper.")
        }
        
        if let shotStat = data.statistics.first(where: { stat in
            let t = stat.type.lowercased()
            return t.contains("shot on") || t.contains("on target") || t == "shots on goal"
        }) {
            insights.append("Shots on target: \(shotStat.homeValue) (\(home)) vs \(shotStat.awayValue) (\(away)).")
        }
        
        return dedupeInsightLines(insights)
    }
    
    private func dedupeInsightLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                out.append(trimmed)
            }
        }
        return Array(out.prefix(6))
    }
    
    /// Simple cumulative swing from on-pitch events (not a proprietary xG model). Empty when nothing to plot.
    private func calculateMomentum(from data: MatchHubData) -> [Double] {
        let sorted = data.events.sorted { lhs, rhs in
            if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
            return lhs.id < rhs.id
        }
        guard !sorted.isEmpty else { return [] }
        
        var series: [Double] = [0]
        var current = 0.0
        let homeId = data.homeTeam.id
        let awayId = data.awayTeam.id
        
        for event in sorted {
            let isHome = event.teamId == homeId
            let isAway = event.teamId == awayId
            
            switch event.type {
            case .goal, .penalty:
                if isHome { current += 0.25 }
                else if isAway { current -= 0.25 }
            case .ownGoal:
                if isHome { current -= 0.22 }
                else if isAway { current += 0.22 }
            case .redCard:
                if isHome { current -= 0.12 }
                else if isAway { current += 0.12 }
            case .yellowCard:
                if isHome { current -= 0.03 }
                else if isAway { current += 0.03 }
            default:
                continue
            }
            current = max(-1, min(1, current))
            series.append(current)
        }
        
        guard series.count >= 2 else { return [] }
        return series
    }
}
