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

public actor FootballRepository {
    
    public static let shared = FootballRepository()
    
    private let primaryProvider: FootballProvider
    private let officialFPLScoreProvider: FootballProvider
    private let footballDataProvider: FootballProvider
    private var cache: [String: CachedData] = [:]

    // MARK: - Fixture list caching (reduces API-Football traffic from polling + multi-tab refresh)

    private var liveListCache: [MatchHubData]?
    private var liveListCachedAt: Date?
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
    /// API-Football league sweep — only when football-data schedule is empty (emergency fallback).
    private let premiumListTTL: TimeInterval = 7200
    private var premiumFallbackBlockedUntil: Date?

    private struct ScheduleListCache {
        let key: String
        let range: ClosedRange<Date>
        let matches: [MatchHubData]
        let fetchedAt: Date
    }

    private var scheduleListCache: ScheduleListCache?
    private let scheduleListTTL: TimeInterval = 900
    
    public struct CachedData {
        let data: Any
        let timestamp: Date
        let status: MatchHubData.DataQualityStatus
    }
    
    private init() {
        self.primaryProvider = APIFootballProvider(apiKey: Config.apiFootballKey)
        self.officialFPLScoreProvider = OfficialFPLScoreProvider()
        self.footballDataProvider = FootballDataProvider()
    }
    
    // MARK: - Repository API
    
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
            return existingHub
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
            storeHubInCache(merged, fixtureId: fixtureId, resolvedFixtureId: resolvedFixtureId)
            return merged
        } catch {
            print("[FootballRepository] Fetch failed for \(resolvedFixtureId): \(error)")
            if let existingHub {
                return existingHub
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
                storeHubInCache(enriched, fixtureId: fixtureId, resolvedFixtureId: resolvedFixtureId)
                return enriched
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
        
        return MatchInsightsData(
            fixtureId: fixtureId,
            homeForm: [],
            awayForm: [],
            headToHead: nil,
            keyInsights: deriveInsights(from: hubData),
            momentum: calculateMomentum(from: hubData),
            winProbability: nil,
            lastUpdated: Date()
        )
    }
    
    /// Get all fixtures for a specific date
    public func getFixtures(for date: Date = Date()) async throws -> [FottyFixture] {
        return try await primaryProvider.fetchFixtures(date: date)
    }
    
    // MARK: - Cache Strategy
    
    public func getLiveMatches() async throws -> [MatchHubData] {
        let now = Date()
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
            liveListCooldownUntil = nil
            liveFeedMode = .inactive
            return []
        }
        if let until = liveListCooldownUntil, Date() < until, let cached = liveListCache {
            return cached
        }
        if let at = liveListCachedAt, let cached = liveListCache, Date().timeIntervalSince(at) < liveListTTL {
            return cached
        }
        do {
            let official = try await officialFPLScoreProvider.fetchLiveScores()
                .filter { FootballDataPolicy.supportsLiveScores(competition: $0.fixture.competition) }
            return commitLiveList(official, mode: .officialFPL)
        } catch {
            print("[FootballRepository] Official FPL live feed failed: \(error)")
        }

        do {
            let primary = try await primaryProvider.fetchLiveScores()
                .filter { FootballDataPolicy.supportsLiveScores(competition: $0.fixture.competition) }
            return commitLiveList(primary, mode: .live)
        } catch {
            let primaryError = error
            let rateLimited = isProviderRateLimited(primaryError)
            if let fallback = try? await footballDataProvider.fetchLiveScores() {
                let committed = commitLiveList(
                    fallback,
                    mode: rateLimited ? .quotaFallback : .delayedFallback
                )
                if rateLimited {
                    liveListCooldownUntil = Date().addingTimeInterval(120)
                }
                return committed
            }
            if let cached = liveListCache {
                FottyQualityStore.shared.record(
                    category: .footballData,
                    name: "live_refresh",
                    outcome: .recovered,
                    details: ["feed": "cached", "result": "provider_failure"]
                )
                return cached
            }
            liveFeedMode = .unavailable
            FottyQualityStore.shared.record(
                category: .footballData,
                name: "live_refresh",
                outcome: .failure,
                details: ["feed": "unavailable", "result": "provider_failure"]
            )
            throw primaryError
        }
    }

    func currentLiveFeedMode() -> LiveScoreFeedMode {
        liveFeedMode
    }

    private func enrichHubData(_ hub: MatchHubData) async -> MatchHubData {
        await TheSportsDBMatchService.shared.enrich(hub)
    }

    private func storeHubInCache(_ hub: MatchHubData, fixtureId: String, resolvedFixtureId: String) {
        updateCache(id: resolvedFixtureId, data: hub)
        if resolvedFixtureId != fixtureId {
            updateCache(id: fixtureId, data: hub)
        }
        updateCache(id: hub.fixture.id, data: hub)
        if let apiId = hub.fixture.apiFootballFixtureId, apiId != hub.fixture.id {
            updateCache(id: apiId, data: hub)
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

    /// Arena / Dashboard schedule — football-data.org first (~1 call / 15 min), zero API-Football unless empty fallback.
    public func getScheduleFixtures(dateRange: ClosedRange<Date>) async throws -> [MatchHubData] {
        let refreshStartedAt = Date()
        let cacheKey = premiumCacheKey(for: dateRange)
        if let c = scheduleListCache, c.key == cacheKey, Date().timeIntervalSince(c.fetchedAt) < scheduleListTTL {
            return c.matches
        }

        var schedule = try await fetchScheduleFromFootballData(dateRange: dateRange)
        schedule = mergeLiveScores(into: schedule)
        indexMatchKeys(from: schedule)

        if schedule.isEmpty {
            schedule = try await fetchPremiumFallbackIfAllowed(dateRange: dateRange, cacheKey: cacheKey)
        }

        let sorted = schedule.sorted { $0.fixture.utcDate < $1.fixture.utcDate }
        scheduleListCache = ScheduleListCache(
            key: cacheKey,
            range: dateRange,
            matches: sorted,
            fetchedAt: Date()
        )
        for match in sorted {
            updateCache(id: match.fixture.id, data: match)
        }
        FottyQualityStore.shared.record(
            category: .footballData,
            name: "schedule_refresh",
            outcome: .success,
            durationMilliseconds: Int(Date().timeIntervalSince(refreshStartedAt) * 1_000),
            details: ["feed": "football_data", "result": sorted.isEmpty ? "empty" : "fixtures"]
        )
        return sorted
    }
    
    /// Emergency API-Football schedule fallback. It follows the same competition
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
        guard let fd = footballDataProvider as? FootballDataProvider else { return [] }
        let raw = try await fd.fetchSchedule(in: dateRange)
        return raw.filter { Config.Arena.discoveryIncludes(competition: $0.fixture.competition) }
    }

    private func fetchPremiumFallbackIfAllowed(
        dateRange: ClosedRange<Date>,
        cacheKey: String
    ) async throws -> [MatchHubData] {
        if let until = premiumFallbackBlockedUntil, Date() < until {
            if let c = premiumListCache, c.key == cacheKey { return c.matches }
            return []
        }
        do {
            let matches = try await getPremiumFixtures(dateRange: dateRange)
            premiumFallbackBlockedUntil = Date().addingTimeInterval(7200)
            return matches
        } catch {
            if isProviderRateLimited(error) {
                premiumFallbackBlockedUntil = Date().addingTimeInterval(1800)
            }
            throw error
        }
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

    private func commitLiveList(_ raw: [MatchHubData], mode: LiveScoreFeedMode) -> [MatchHubData] {
        let merged = mergeLiveMatchesWithSchedule(raw)
        for match in merged {
            storeHubInCache(
                match,
                fixtureId: match.fixture.id,
                resolvedFixtureId: match.fixture.hubFixtureId
            )
        }
        liveListCache = merged
        liveListCachedAt = Date()
        liveListCooldownUntil = nil
        liveFeedMode = mode
        indexMatchKeys(from: merged)
        FottyQualityStore.shared.record(
            category: .footballData,
            name: "live_refresh",
            outcome: .success,
            details: ["feed": mode.rawValue, "result": merged.isEmpty ? "empty" : "live"]
        )
        return merged
    }

    private func mergeLiveScores(into schedule: [MatchHubData]) -> [MatchHubData] {
        guard let live = liveListCache, !live.isEmpty else { return schedule }
        let liveByKey = indexByCanonicalMatchKey(live, source: "live_feed")
        return schedule.map { row in
            guard let liveMatch = liveByKey[matchKey(for: row)] else { return row }
            return mergedScoreRow(schedule: row, live: liveMatch)
        }
    }

    /// Live providers use their own fixture/team ids. Keep the football-data
    /// schedule identity so navigation, alerts, and stream matching remain stable.
    private func mergeLiveMatchesWithSchedule(_ live: [MatchHubData]) -> [MatchHubData] {
        guard let currentSchedule = scheduleListCache else { return live }
        let scheduleByKey = indexByCanonicalMatchKey(currentSchedule.matches, source: "schedule_feed")
        let mergedLive = live.map { row in
            guard let schedule = scheduleByKey[matchKey(for: row)] else { return row }
            return mergedScoreRow(schedule: schedule, live: row)
        }

        guard !mergedLive.isEmpty else { return mergedLive }
        let liveByKey = indexByCanonicalMatchKey(mergedLive, source: "merged_live_feed")
        let updatedSchedule = currentSchedule.matches.map { row in
            liveByKey[matchKey(for: row)] ?? row
        }
        scheduleListCache = ScheduleListCache(
            key: currentSchedule.key,
            range: currentSchedule.range,
            matches: updatedSchedule,
            fetchedAt: currentSchedule.fetchedAt
        )
        return mergedLive
    }

    private func mergedScoreRow(schedule: MatchHubData, live: MatchHubData) -> MatchHubData {
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
            homeTeam: schedule.homeTeam,
            awayTeam: schedule.awayTeam,
            score: live.score,
            events: live.events.isEmpty ? schedule.events : live.events,
            homeLineup: live.homeLineup ?? schedule.homeLineup,
            awayLineup: live.awayLineup ?? schedule.awayLineup,
            statistics: live.statistics.isEmpty ? schedule.statistics : live.statistics,
            teamNews: schedule.teamNews,
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
        if let live = liveListCache?.first(where: { $0.identity.resolves(fixtureId) }) { return live }
        if let scheduled = scheduleListCache?.matches.first(where: { $0.identity.resolves(fixtureId) }) { return scheduled }
        if let cached = cache[fixtureId]?.data as? MatchHubData { return cached }
        if let cached = cache.values.compactMap({ $0.data as? MatchHubData }).first(where: {
            $0.identity.resolves(fixtureId)
        }) {
            return cached
        }
        return nil
    }

    private func preserveEnrichedFields(from existing: MatchHubData, into merged: MatchHubData) -> MatchHubData {
        MatchHubData(
            fixture: merged.fixture,
            homeTeam: merged.homeTeam,
            awayTeam: merged.awayTeam,
            score: merged.score,
            events: merged.events.isEmpty ? existing.events : merged.events,
            homeLineup: merged.homeLineup ?? existing.homeLineup,
            awayLineup: merged.awayLineup ?? existing.awayLineup,
            statistics: merged.statistics.isEmpty ? existing.statistics : merged.statistics,
            teamNews: merged.teamNews.isEmpty ? existing.teamNews : existing.teamNews,
            lastUpdated: merged.lastUpdated,
            dataQuality: merged.dataQuality
        )
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
