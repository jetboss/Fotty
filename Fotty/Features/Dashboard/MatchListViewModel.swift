import SwiftUI
import SwiftData
import Observation

private struct MatchCatalogCacheRecord: Sendable {
    let id: String
    let title: String?
    let homeName: String
    let awayName: String
    let homeBadge: String?
    let awayBadge: String?
    let kickoffDate: Date?
    let category: String?
    let popular: Bool?
}

/// SwiftData's UI context remains responsible for the one-time warm read. Full
/// provider replacements are written by a dedicated model actor so SQLite work
/// cannot take the main thread away from an active scroll gesture.
@ModelActor
private actor MatchCatalogCacheWriter {
    private var latestGeneration = 0

    func replace(with records: [MatchCatalogCacheRecord], generation: Int) throws -> Bool {
        let signpostState = FottyPerformanceTrace.persistence.beginInterval("CatalogCacheReplace")
        defer { FottyPerformanceTrace.persistence.endInterval("CatalogCacheReplace", signpostState) }
        guard generation >= latestGeneration else { return false }
        latestGeneration = generation
        try Task.checkCancellation()
        do {
            try modelContext.delete(model: MatchCacheItem.self)
            for record in records {
                try Task.checkCancellation()
                modelContext.insert(MatchCacheItem(
                    id: record.id,
                    title: record.title,
                    homeName: record.homeName,
                    awayName: record.awayName,
                    homeBadge: record.homeBadge,
                    awayBadge: record.awayBadge,
                    kickoffDate: record.kickoffDate,
                    category: record.category,
                    popular: record.popular
                ))
            }
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

/// BLUEPRINT: @MainActor (Swift 6 Strict Concurrency)
/// Manages the match list with local caching (SwiftData) and silent background refresh.
@MainActor
@Observable
final class MatchListViewModel {
    static let shared = MatchListViewModel()

    var matches: [AnalyticalDataEngine.EventReference] = [] {
        didSet { browseCatalogCache = nil; contentRevision &+= 1 }
    }
    /// A cheap input identity for presentation projections. Views should key
    /// derived catalog work from this value instead of rebuilding from every
    /// unrelated SwiftUI state change.
    private(set) var contentRevision = 0
    var isLoading = false
    private(set) var isRefreshing = false
    var error: String?
    private(set) var lastCatalogCheck: Date?
    private(set) var catalogSource: String?
    private(set) var isPartialCatalog = false
    private(set) var refreshFailed = false
    private(set) var persistenceFailed = false
    private(set) var identityConflicts: [EventReference] = []
    private(set) var cplScheduleCheckedAt: Date?
    private(set) var cplScheduleSourceStatus: CPLSchedule.SourceStatus = .lastKnownGood
    private(set) var cricketFixtureSnapshot: CricketFixtureCatalog.Snapshot? {
        didSet { terminalAdmissionCache = nil; fixtureCatalogRevision &+= 1 }
    }
    private(set) var sportsFixtureSnapshot: SportsFixtureCatalog.Snapshot? {
        didSet { terminalAdmissionCache = nil; fixtureCatalogRevision &+= 1 }
    }
    private(set) var fixtureCatalogRevision: UInt64 = 0
    @ObservationIgnored private var terminalAdmissionCache: [EventReference]?
    @ObservationIgnored private var currentPrimaryCatalogRows: [EventReference] = []
    @ObservationIgnored private var browseCatalogCache: [EventReference]?
    var playbackCatalog: [EventReference] { matches + identityConflicts }

    /// Channels are persistent navigation destinations, not fabricated matches
    /// or primary-feed rows. Keep their browsing inventory out of ingestion and
    /// fixture/source admission, which continue to use the raw catalog.
    var browseCatalog: [EventReference] {
        let current = matches
        if let cached = browseCatalogCache { return cached }
        let projected = CricketChannelCatalog.merging(into: current)
        browseCatalogCache = projected
        return projected
    }

    /// Admission keeps accepted terminal facts after playable listings remove
    /// them. Absence remains unknown; an exact verified finish/cancellation can
    /// veto a stale open sheet or a late discovery result without adding a row
    /// to Home, Search, or the playable catalog. Duplicate/conflicting identities
    /// remain present so the existing identity policy rejects rather than picks.
    var playbackAdmissionCatalog: [EventReference] {
        // Read both observable inputs even on cache hits. Only value projection
        // is memoized; a replacement receipt (including held/partial changes)
        // invalidates it before the next row reads this registry.
        let cricket = cricketFixtureSnapshot, sports = sportsFixtureSnapshot
        let terminal: [EventReference]
        if let cached = terminalAdmissionCache {
            terminal = cached
        } else {
            terminal = CricketFixtureCatalog.terminalEvents(from: cricket)
                + SportsFixtureCatalog.terminalEvents(from: sports)
            terminalAdmissionCache = terminal
        }
        let now = currentDate()
        return playbackCatalog + terminal.filter { VerifiedFixtureTerminalPolicy.state(for: $0, at: now) != nil }
    }

    /// Read-only match information can outlive playable listings. Accepted
    /// terminal facts replace the same nonconflicting active identity here,
    /// never in the playback catalog or its source-admission path.
    var matchContextCatalog: [EventReference] {
        let current = playbackCatalog
        let terminal = CricketFixtureCatalog.terminalEvents(from: cricketFixtureSnapshot)
            + SportsFixtureCatalog.terminalEvents(from: sportsFixtureSnapshot).filter {
                $0.normalizedCategory == "football" && $0.sportsFixture?.competitionID == "champions-league"
            }
        let vetoIDs = Set(Dictionary(grouping: current, by: \.id).compactMap { id, rows in
            rows.count > 1 || rows.contains(where: \.hasCatalogIdentityConflict) ? id : nil
        })
        let replacementIDs = Set(terminal.map(\.id)).subtracting(vetoIDs)
        return current.filter { !replacementIDs.contains($0.id) }
            + terminal.filter { !vetoIDs.contains($0.id) }
    }

    /// A wider read-only planning projection for Search, built on demand by
    /// its nonempty-query preparation owner. Never added to Home or playback.
    func searchSchedule(at now: Date = .init()) -> [EventReference] {
        let excludedIDs = Set(playbackCatalog.filter(\.hasCatalogIdentityConflict).map(\.id))
            .union(SportsFixtureCatalog.terminalEvents(from: sportsFixtureSnapshot).map(\.id))
            .union(CricketFixtureCatalog.terminalEvents(from: cricketFixtureSnapshot).map(\.id))
        return SportsSearchSchedule.events(sports: sportsFixtureSnapshot, cricket: cricketFixtureSnapshot,
            cpl: cplFixtures, cplCheckedAt: cplScheduleCheckedAt,
            cplSourceStatus: cplScheduleSourceStatus, at: now).filter { !excludedIDs.contains($0.id) }
    }

    /// One accepted fixture universe for all source catalogs. Source listings
    /// cannot create fixtures, change status, or lend old URLs to these rows.
    /// Home retains its own compact window; Search can plan up to fourteen days.
    func sourceCatalogRequests(at now: Date = .init()) -> [StreamPlaybackRequest] {
        guard now.timeIntervalSince1970.isFinite else { return [] }
        let latest = now.addingTimeInterval(SportsSearchSchedule.futureHorizon)
        var seen = Set<String>()
        let events = (playbackAdmissionCatalog + searchSchedule(at: now)).filter { event in
            guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
                  VerifiedFixtureTerminalPolicy.state(for: event, at: now) == nil,
                  let kickoff = event.kickoffDate, kickoff <= latest else { return false }
            if let sports = event.sportsFixture {
                guard sports.verified, sports.eventKind == .match,
                      sports.participants.count == 2,
                      SportsSearchSchedule.isFresh(sports.observedAt, at: now) else { return false }
                let scheduled = sports.status == .scheduled && (kickoff >= now
                    || !event.isPastEstimatedMatchWindow(at: now)
                        && (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(sports.observedAt)))
                // A stale LIVE receipt keeps its bounded catalog opportunity so
                // Home evidence does not vanish after one failed fixture refresh.
                return scheduled || sports.status == .live
                    && (sports.isLive(at: now) || sports.isUnconfirmedLive(at: now, kickoff: kickoff))
            }
            if let cricket = event.cricketFixture {
                guard cricket.verified, SportsSearchSchedule.isFresh(cricket.observedAt, at: now) else { return false }
                let scheduled = cricket.status == .scheduled && (kickoff >= now
                    || !event.isPastEstimatedMatchWindow(at: now)
                        && (-300...CricketFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(cricket.observedAt)))
                return scheduled || cricket.status == .live && cricket.isLive(at: now)
            }
            return CPLSchedule.isManagedFixtureID(event.id) && isCPLScheduleFresh(at: now)
                && (kickoff >= now || !event.isPastEstimatedMatchWindow(at: now))
        }.sorted {
            let left = $0.kickoffDate ?? .distantFuture, right = $1.kickoffDate ?? .distantFuture
            // Current fixtures receive the first bounded opportunities.
            let leftCurrent = left <= now, rightCurrent = right <= now
            if leftCurrent != rightCurrent { return leftCurrent }
            return left == right ? $0.id < $1.id : left < right
        }
        return events.compactMap { event in
            guard seen.insert(event.id).inserted else { return nil }
            let request = StreamPlaybackRequest(event: event)
            return ReviewedSportsFixtureMatcher.requestIdentity(for: request) == nil ? nil : request
        }.prefix(256).map { $0 }
    }

    /// Reuse the existing main-catalog receipt instead of making another set of
    /// mirror requests for the shared index. A failed/old receipt is never a
    /// new positive, even while its previous browsing rows remain visible.
    func primarySourceCatalogEvidence(for requests: [StreamPlaybackRequest], at now: Date = .init())
        -> (matches: [FixtureSourceCatalogMatch], failure: StreamFailureCategory?) {
        guard !refreshFailed, let checked = lastCatalogCheck,
              (0..<180).contains(now.timeIntervalSince(checked)) else { return ([], .manifestUnreachable) }
        let sourceCodes = Set(CuratedStreamSourceCatalog.definition(forProviderCode: "streamex")?.catalogSourceCodes ?? [])
        let catalog = currentPrimaryCatalogRows
        return (requests.map { request in
            switch CatalogPlaybackIdentity.selection(for: request, in: catalog) {
            case .conflicting: return .init(matchID: request.matchID, outcome: .conflicting)
            case .missing: return .init(matchID: request.matchID, outcome: .notListed)
            case .matched(let event):
                let source = (event.sources ?? []).first { sourceCodes.contains($0.source.lowercased()) && !$0.id.isEmpty }
                return .init(matchID: request.matchID, outcome: source == nil ? .notListed : .listed,
                             providerEventID: source?.id)
            }
        }, nil)
    }

    func catalogNotice(at now: Date = Date(), displaying visibleEvents: [EventReference]? = nil,
                       availabilityIndex: FixtureCatalogAvailabilityIndex? = nil) -> String? {
        let displaysCPLSchedule = (visibleEvents ?? matches).contains(where: \.isCPLFixture)
        let requests = (visibleEvents ?? matches).prefix(32).map { StreamPlaybackRequest(event: $0) }
        let hasSourceEvidence = (availabilityIndex ?? .shared)
            .hasRecentSuccessfulCatalogEvaluation(for: requests, at: now)
        return catalogNotice(at: now, displaysCPLSchedule: displaysCPLSchedule,
                             hasSourceCatalogEvidence: hasSourceEvidence)
    }

    /// A projection owner may reuse revision-checked fixture identity facts.
    /// Freshness/error evaluation still runs against the current clock/receipt.
    func catalogNotice(at now: Date, displaysCPLSchedule: Bool, hasSourceCatalogEvidence: Bool = false) -> String? {
        // Starting a retry is not evidence that previously stale data is fresh.
        // Keep known uncertainty visible until a successful receipt replaces it.
        if refreshFailed && !hasSourceCatalogEvidence {
            if displaysCPLSchedule, !isCPLScheduleFresh(at: now) {
                return "Couldn't refresh. Broadcasts and CPL times may have changed."
            }
            return "Couldn't refresh. Broadcasts may have changed."
        }
        if displaysCPLSchedule,
           !isCPLScheduleFresh(at: now) {
            return "CPL start times may have changed."
        }
        if let lastCatalogCheck {
            let age = now.timeIntervalSince(lastCatalogCheck)
            if age < 0 { return "Broadcast listings may be out of date." }
        }
        // Routine aging and the initial cache read are handled silently by the
        // foreground refresh. A partial response from redundant mirrors remains
        // internal telemetry: it is not proof that a visible broadcast is
        // missing. Only a failed check or unverified fixture authority should
        // interrupt the user; starting a retry never clears those states.
        return nil
    }

    func isCPLScheduleFresh(at now: Date = Date()) -> Bool {
        CPLSchedule.isFreshlyVerified(
            checkedAt: cplScheduleCheckedAt,
            sourceStatus: cplScheduleSourceStatus,
            at: now
        )
    }
    
    var sportsTabs: [String] {
        let unique = Set(matches.map(\.normalizedCategory))
        let preferredOrder = ["football", "cricket", "basketball", "baseball", "hockey", "fight"]
        var ordered = ["football"]
        ordered.append(contentsOf: preferredOrder.filter { $0 != "football" && unique.contains($0) })
        let remaining = unique.subtracting(Set(ordered)).sorted { lhs, rhs in
            AnalyticalDataEngine.categoryDisplayName(for: lhs) < AnalyticalDataEngine.categoryDisplayName(for: rhs)
        }
        ordered.append(contentsOf: remaining)
        return ordered
    }

    /// Production has no catalog lane since the shared catalog closed; Home
    /// publishes fixture lanes only. Tests may still inject provider rows.
    typealias CatalogFetch = @MainActor () async throws -> LiveCatalogSnapshot
    @ObservationIgnored private var fetchSnapshot: CatalogFetch?
    @ObservationIgnored private var refreshSchedule: @MainActor () async -> CPLSchedule.Snapshot? = { await CPLScheduleUpdater.shared.refresh() }
    @ObservationIgnored private var refreshCricket: @MainActor () async -> CricketFixtureCatalog.Snapshot? = { await CricketFixtureUpdater.shared.refresh() }
    @ObservationIgnored private var refreshSports: @MainActor () async -> SportsFixtureCatalog.Snapshot? = { await SportsFixtureUpdater.shared.refresh() }
    @ObservationIgnored private var currentDate: () -> Date = Date.init
    @ObservationIgnored private var lastRefreshAttempt: Date?
    @ObservationIgnored private var reconcilesPersonalState = true
    @ObservationIgnored private var suppliedMatchdayStore: MyMatchdayStore?
    @ObservationIgnored private var cacheWriter: MatchCatalogCacheWriter?
    @ObservationIgnored private var cacheWriteGeneration = 0
    private var modelContext: ModelContext?
    private var didLoadCache = false
    private var recordedIdentityDiagnostics: Set<String> = []
    private var cplFixtures: [CPLSchedule.Fixture] = CPLSchedule.fixtures

    private init() {
        let cached = CPLScheduleUpdater.shared.cachedSnapshot()
        cplFixtures = CPLSchedule.preservingKnownPlayoffParticipants(
            in: cached?.fixtures ?? CPLSchedule.fixtures,
            from: CPLSchedule.fixtures
        )
        cplScheduleCheckedAt = cached?.checkedAt
        cplScheduleSourceStatus = cached?.sourceStatus ?? .lastKnownGood
        cricketFixtureSnapshot = CricketFixtureUpdater.shared.cachedSnapshot()
        sportsFixtureSnapshot = SportsFixtureUpdater.shared.cachedSnapshot()
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.cacheWriter = MatchCatalogCacheWriter(modelContainer: modelContext.container)
        let cached = CPLScheduleUpdater.shared.cachedSnapshot()
        cplFixtures = CPLSchedule.preservingKnownPlayoffParticipants(
            in: cached?.fixtures ?? CPLSchedule.fixtures,
            from: CPLSchedule.fixtures
        )
        cplScheduleCheckedAt = cached?.checkedAt
        cplScheduleSourceStatus = cached?.sourceStatus ?? .lastKnownGood
        cricketFixtureSnapshot = CricketFixtureUpdater.shared.cachedSnapshot()
        sportsFixtureSnapshot = SportsFixtureUpdater.shared.cachedSnapshot()
        loadFromCache()
    }

    /// Controlled async owner tests never contact providers or mutate shared reminders.
    init(fetchSnapshot: CatalogFetch?,
         refreshSchedule: @escaping @MainActor () async -> CPLSchedule.Snapshot? = { nil },
         refreshCricket: @escaping @MainActor () async -> CricketFixtureCatalog.Snapshot? = { nil },
         refreshSports: @escaping @MainActor () async -> SportsFixtureCatalog.Snapshot? = { nil },
         now: @escaping () -> Date = Date.init,
         fixtures: [CPLSchedule.Fixture] = [],
         matchdayStore: MyMatchdayStore? = nil) {
        self.fetchSnapshot = fetchSnapshot
        self.refreshSchedule = refreshSchedule
        self.refreshCricket = refreshCricket
        self.refreshSports = refreshSports
        self.currentDate = now
        self.cplFixtures = fixtures
        self.reconcilesPersonalState = false
        self.suppliedMatchdayStore = matchdayStore
    }

    /// Home and My Matchday intentionally share one catalog instance. Configure
    /// persistence once the SwiftUI model context is available; subsequent calls
    /// are harmless and do not replace an already-loaded in-memory feed.
    func configure(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        self.cacheWriter = MatchCatalogCacheWriter(modelContainer: modelContext.container)
        loadFromCache()
    }

    /// Loads cached matches from SwiftData for immediate display (IINA Pattern).
    private func loadFromCache() {
        guard !didLoadCache, let modelContext else { return }
        didLoadCache = true
        #if DEBUG
        if AppRuntime.isAutomatedTesting {
            // Test real notice rendering with explicit data states, rather than
            // hiding the notice in every automated view.
            let now = Date()
            lastCatalogCheck = now
            cplScheduleCheckedAt = now
            cplScheduleSourceStatus = .verified
            switch ProcessInfo.processInfo.environment["FOTTY_CATALOG_UI_STATE"] {
            case "stale-cpl": cplScheduleCheckedAt = now.addingTimeInterval(-3 * 3600)
            case "offline": refreshFailed = true
            case "partial": isPartialCatalog = true
            default: break
            }
        }
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_HOME_UI_TESTING"] == "1" {
            let now = HomeSportsDiscovery.automatedClockStart ?? Date()
            func fixture(_ id: String, sport: String, title: String, hours: Double, watchable: Bool = false) -> AnalyticalDataEngine.EventReference {
                .init(id: id, title: title, category: sport, date: Int64(now.addingTimeInterval(hours * 3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil,
                      sources: watchable ? [.init(source: "delta", id: "ui-only-\(id)")] : [])
            }
            // Network-free presentation data; never written to the cache.
            if HomeSportsDiscovery.automatedClockStart != nil {
                matches = [
                    fixture("cpl-2026-ui-today", sport: "cricket", title: "CPL · Guyana Amazon Warriors vs Antigua & Barbuda Falcons", hours: 65.0 / 60),
                    fixture("cpl-2026-ui-next", sport: "cricket", title: "CPL · Trinbago Knight Riders vs Barbados Tridents", hours: 125.0 / 60),
                    fixture("cpl-2026-ui-tomorrow", sport: "cricket", title: "CPL · Guyana Amazon Warriors vs Saint Lucia Kings", hours: 25)
                ]
                cplScheduleCheckedAt = now
                lastCatalogCheck = now
                return
            }
            matches = [
                fixture("ui-football", sport: "football", title: "Arsenal vs Chelsea", hours: -0.5, watchable: true),
                fixture("ui-basketball", sport: "basketball", title: "Lakers vs Warriors", hours: -0.25, watchable: true),
                fixture("cpl-2026-ui-home", sport: "cricket", title: "Trinbago Knight Riders vs Guyana Amazon Warriors", hours: 1),
                fixture("ui-baseball", sport: "baseball", title: "Yankees vs Red Sox", hours: 7),
                fixture("ui-tennis", sport: "tennis", title: "Świątek vs Gauff", hours: 8),
                fixture("ui-rugby", sport: "rugby", title: "Harlequins vs Saracens", hours: 9),
                fixture("ui-hockey", sport: "hockey", title: "Rangers vs Panthers", hours: 10)
            ]
            return
        }
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_CRICKET_UI_TESTING"] == "1" {
            matches = [
                .init(id: "ui-willow", title: "Willow Cricket", category: "cricket", date: -3_600_000, poster: nil, popular: false, teams: nil, sources: []),
                .init(id: "cpl-2026-ui", title: "CPL · Trinbago Knight Riders vs Barbados Tridents", category: "cricket", date: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil, sources: [])
            ]
            return
        }
        #endif
        let descriptor = FetchDescriptor<MatchCacheItem>(sortBy: [SortDescriptor(\.kickoffDate)])
        do {
            let cachedItems = try modelContext.fetch(descriptor)
            let cachedMatches = cachedItems.map { item in
                AnalyticalDataEngine.EventReference(
                    id: item.id,
                    title: item.title,
                    category: item.category,
                    date: item.kickoffDate.map { Int64($0.timeIntervalSince1970) },
                    poster: nil as String?,
                    popular: item.popular,
                    teams: NexusATeams(
                        home: NexusATeam(name: item.homeName, badge: item.homeBadge),
                        away: NexusATeam(name: item.awayName, badge: item.awayBadge)
                    ),
                    sources: nil as [NexusASource]?
                )
            }.filter { $0.passesNearTermLiveListWindow() }
            // Accessibility/UI tests only need a representative first screen.
            // Bounding the fixture tree keeps XCTest's audit analyzer below its
            // hard timeout without changing production data or layout behavior.
            self.matches = AppRuntime.isAutomatedTesting
                ? Array(cachedMatches.prefix(40))
                : SportsFixtureCatalog.merging(
                    into: CricketFixtureCatalog.merging(
                        into: CPLSchedule.merging(into: cachedMatches, fixtures: cplFixtures),
                        snapshot: cricketFixtureSnapshot),
                    snapshot: sportsFixtureSnapshot, currentProviderEvents: [])
            print("[MatchList] Loaded \(matches.count) items from SwiftData cache.")
        } catch {
            print("[MatchList] SwiftData fetch failed: \(error.localizedDescription)")
        }
    }
    
    /// One owner even when old rows remain visible. Refresh callers coalesce;
    /// cancellation cannot publish either a late provider or schedule response.
    /// Foreground entry and periodic polling share one bounded request owner.
    /// Throttle attempts, not receipts: replayed cached receipts and failures
    /// must neither masquerade as fresh checks nor create a request storm.
    func refreshIfNeeded(minimumInterval: TimeInterval = 90) async {
        if let lastRefreshAttempt {
            let age = currentDate().timeIntervalSince(lastRefreshAttempt)
            if age >= 0, age < minimumInterval { return }
        }
        await refresh()
    }

    private enum RefreshLaneResult {
        case catalog(Result<LiveCatalogSnapshot, Error>)
        case cpl(CPLSchedule.Snapshot?)
        case cricket(CricketFixtureCatalog.Snapshot?)
        case sports(SportsFixtureCatalog.Snapshot?)
    }

    /// Concurrent callers (pull-to-refresh, scene activation, the 15-minute
    /// loop) join one refresh instead of returning before it completes. The
    /// first caller owns it: cancelling that caller cancels the refresh.
    @ObservationIgnored private var inFlightRefresh: Task<Void, Never>?

    func refresh() async {
        if let inFlight = inFlightRefresh {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh() }
        inFlightRefresh = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if inFlightRefresh == task { inFlightRefresh = nil }
    }

    private func performRefresh() async {
        guard !isRefreshing else { return }
        lastRefreshAttempt = currentDate()
        isRefreshing = true
        isLoading = matches.isEmpty
        defer { isRefreshing = false; isLoading = false }
        let fetch = fetchSnapshot
        let cpl = refreshSchedule
        let cricket = refreshCricket
        let sports = refreshSports
        await withTaskGroup(of: RefreshLaneResult.self) { group in
            if let fetch {
                group.addTask { @MainActor in
                    do { return .catalog(.success(try await fetch())) }
                    catch { return .catalog(.failure(error)) }
                }
            }
            group.addTask { @MainActor in .cpl(await cpl()) }
            group.addTask { @MainActor in .cricket(await cricket()) }
            group.addTask { @MainActor in .sports(await sports()) }
            // Without a catalog lane, fixture lanes publish as they complete.
            var catalogCompleted = fetch == nil
            var acceptedProvider: LiveCatalogSnapshot?
            var pendingFixtures: [RefreshLaneResult] = []
            for await result in group {
                guard !Task.isCancelled else {
                    lastRefreshAttempt = nil
                    group.cancelAll()
                    return
                }
                switch result {
                case .catalog(let response):
                    catalogCompleted = true
                    switch response {
                    case .success(let snapshot):
                        // Fold only fixture lanes that already completed into
                        // the first usable provider projection. Never wait for
                        // a slower lane or republish once per queued receipt.
                        if lastCatalogCheck.map({ snapshot.checkedAt >= $0 }) ?? true {
                            for fixture in pendingFixtures {
                                guard !Task.isCancelled else { group.cancelAll(); return }
                                _ = acceptFixtureState(fixture)
                            }
                            pendingFixtures.removeAll()
                            acceptedProvider = snapshot
                            currentPrimaryCatalogRows = snapshot.events
                            applyFreshMatches(snapshot)
                            lastCatalogCheck = snapshot.checkedAt
                            catalogSource = snapshot.source
                            isPartialCatalog = snapshot.isPartial
                            refreshFailed = false
                            error = nil
                            isLoading = false
                            await reconcilePersonalState()
                        }
                    case .failure(let failure):
                        guard !(failure is CancellationError),
                              (failure as? URLError)?.code != .cancelled else {
                            lastRefreshAttempt = nil
                            group.cancelAll()
                            return
                        }
                        refreshFailed = true
                    }
                    // A cancelled provider request never authorizes queued
                    // fixture publication, even if its sibling already completed.
                    for fixture in pendingFixtures {
                        guard !Task.isCancelled else { group.cancelAll(); return }
                        await applyCompletedFixtureLane(fixture, provider: acceptedProvider)
                    }
                    pendingFixtures.removeAll()
                default:
                    if catalogCompleted {
                        await applyCompletedFixtureLane(result, provider: acceptedProvider)
                    } else {
                        pendingFixtures.append(result)
                    }
                }
                if refreshFailed {
                    error = matches.isEmpty ? "Live listings could not be checked. Check your connection and try again." : nil
                }
            }
        }
    }

    private func applyCompletedFixtureLane(_ result: RefreshLaneResult, provider: LiveCatalogSnapshot?) async {
        let changed: Bool
        switch result {
        case .cpl(let snapshot):
            guard let snapshot else { return }
            changed = acceptSchedule(snapshot)
            if provider == nil { applyIndependentCPLSchedule() }
        case .cricket(let snapshot):
            guard let snapshot else { return }
            changed = acceptCricket(snapshot)
            if provider == nil {
                matches = CricketFixtureCatalog.merging(into: matches,
                    snapshot: cricketFixtureSnapshot, at: currentDate(), currentProviderEvents: [])
            }
        case .sports(let snapshot):
            guard let snapshot else { return }
            changed = acceptSports(snapshot)
            if provider == nil {
                matches = SportsFixtureCatalog.merging(into: matches,
                    snapshot: sportsFixtureSnapshot, at: currentDate(), currentProviderEvents: [])
            }
        case .catalog:
            return
        }
        // Only this refresh's accepted provider receipt may supply streams.
        // Corrections still pass through the strict fixture identity join. A
        // replayed/rejected fixture receipt supplies no new projection facts.
        if let provider, changed { applyFreshMatches(provider) }
        if !matches.isEmpty { isLoading = false }
        await reconcilePersonalState()
    }

    /// Only the accepted schedule can advance when provider evidence is older
    /// or unavailable. Keep other rows intact without lending their old streams.
    private func applyIndependentCPLSchedule() {
        let sourceFree = matches.map { event in
            EventReference(id: event.id, title: event.title, category: event.category, date: event.date,
                poster: event.poster, popular: event.popular, teams: event.teams, sources: [],
                hasCatalogIdentityConflict: event.hasCatalogIdentityConflict,
                cricketFixture: event.cricketFixture, sportsFixture: event.sportsFixture,
                competitionID: event.competitionID)
        }
        let scheduledCPL = CPLSchedule.merging(into: sourceFree, fixtures: cplFixtures, at: currentDate())
            .filter { CPLSchedule.isManagedFixtureID($0.id) }
        matches = matches.filter { !CPLSchedule.isManagedFixtureID($0.id) && !$0.isCPLFixture } + scheduledCPL
    }

    private func acceptFixtureState(_ result: RefreshLaneResult) -> Bool {
        switch result {
        case .cpl(let snapshot):
            return snapshot.map(acceptSchedule) ?? false
        case .cricket(let snapshot):
            return snapshot.map(acceptCricket) ?? false
        case .sports(let snapshot):
            return snapshot.map(acceptSports) ?? false
        case .catalog:
            return false
        }
    }

    private func acceptSchedule(_ snapshot: CPLSchedule.Snapshot) -> Bool {
        if cplScheduleSourceStatus.isCurrentVerification,
           !snapshot.sourceStatus.isCurrentVerification {
            return false
        }
        if cplScheduleSourceStatus.isCurrentVerification == snapshot.sourceStatus.isCurrentVerification,
           let cplScheduleCheckedAt,
           cplScheduleCheckedAt > snapshot.checkedAt {
            return false
        }
        let acceptedFixtures = CPLSchedule.preservingKnownPlayoffParticipants(
            in: snapshot.fixtures,
            from: cplFixtures
        )
        // An unchanged team/time payload still advances a genuinely newer
        // receipt. Compare every accepted value, never just IDs/revision.
        guard cplFixtures != acceptedFixtures
                || cplScheduleCheckedAt != snapshot.checkedAt
                || cplScheduleSourceStatus != snapshot.sourceStatus else { return false }
        cplFixtures = acceptedFixtures
        cplScheduleCheckedAt = snapshot.checkedAt
        cplScheduleSourceStatus = snapshot.sourceStatus
        return true
    }

    private func acceptCricket(_ snapshot: CricketFixtureCatalog.Snapshot) -> Bool {
        let accepted = CricketFixtureCatalog.accepting(snapshot, over: cricketFixtureSnapshot)
        guard cricketFixtureSnapshot != accepted else { return false }
        cricketFixtureSnapshot = accepted
        return true
    }

    private func acceptSports(_ snapshot: SportsFixtureCatalog.Snapshot) -> Bool {
        let accepted = SportsFixtureCatalog.accepting(snapshot, over: sportsFixtureSnapshot)
        guard sportsFixtureSnapshot != accepted else { return false }
        sportsFixtureSnapshot = accepted
        return true
    }

    private func reconcilePersonalState(events: [EventReference]? = nil) async {
        let store = suppliedMatchdayStore ?? (reconcilesPersonalState ? MyMatchdayStore.shared : nil)
        guard let store else { return }
        // Playable catalogs deliberately omit finished/cancelled events. Preserve
        // their verified source-free facts for saved/reminded state separately;
        // absence from either feed is still not evidence of cancellation.
        let evidence = (events ?? playbackCatalog)
            + SportsFixtureCatalog.terminalEvents(from: sportsFixtureSnapshot)
            + CricketFixtureCatalog.terminalEvents(from: cricketFixtureSnapshot)
        store.reconcile(events: evidence, at: currentDate())
        guard reconcilesPersonalState else { return }
        await MatchReminderStore.shared.reconcile(events: evidence) {
            MatchStartPolicy.currentStatus(for: $0, scores: .shared)
        }
    }

    private func applyFreshMatches(_ snapshot: LiveCatalogSnapshot) {
        let freshIDs = Set(snapshot.events.map(\.id))
        identityConflicts = Array((snapshot.events.filter(\.hasCatalogIdentityConflict)
            + identityConflicts.filter { !freshIDs.contains($0.id) }).prefix(500))
        let retained = snapshot.isPartial ? matches.filter { !freshIDs.contains($0.id) } : []
        let nearTerm = SportsFixtureCatalog.merging(
            into: CricketFixtureCatalog.merging(
                into: CPLSchedule.merging(
                    into: snapshot.events + retained,
                    fixtures: cplFixtures, at: currentDate()),
                snapshot: cricketFixtureSnapshot, at: currentDate(), currentProviderEvents: snapshot.events,
                currentProviderObservedAt: snapshot.checkedAt),
            snapshot: sportsFixtureSnapshot, at: currentDate(), currentProviderEvents: snapshot.events,
            currentProviderObservedAt: snapshot.checkedAt)
            .filter { $0.passesNearTermLiveListWindow(at: currentDate()) }

        recordIdentityDrift(in: nearTerm)

        // A provider refresh can replace hundreds of rows. Global animation of
        // that diff competes with an active scroll and provides no useful spatial
        // meaning; individual user actions retain their focused animations.
        self.matches = nearTerm
        scheduleCacheWrite(nearTerm)
    }

    private func recordIdentityDrift(in events: [AnalyticalDataEngine.EventReference]) {
        if recordedIdentityDiagnostics.count > 500 {
            recordedIdentityDiagnostics.removeAll(keepingCapacity: true)
        }
        for event in events where event.normalizedCategory == "football" {
            let classification = AnalyticalDataEngine.footballLeagueClassification(for: event)
            guard classification.isIdentityConflict,
                  let reasonCode = classification.reasonCode else { continue }
            let diagnosticKey = "\(event.id)|\(reasonCode)"
            guard recordedIdentityDiagnostics.insert(diagnosticKey).inserted else { continue }
            FottyQualityStore.shared.record(
                category: .matchIdentity,
                name: "catalog_classification",
                outcome: .failure,
                details: [
                    "reason_code": reasonCode,
                    "source": "provider_catalog",
                ]
            )
        }
    }


    
    private func scheduleCacheWrite(_ freshMatches: [AnalyticalDataEngine.EventReference]) {
        guard let cacheWriter else { return }
        cacheWriteGeneration &+= 1
        let generation = cacheWriteGeneration
        let records = freshMatches.map {
            MatchCatalogCacheRecord(
                id: $0.id,
                title: $0.title,
                homeName: $0.homeName,
                awayName: $0.awayName,
                homeBadge: $0.teams?.home?.badge,
                awayBadge: $0.teams?.away?.badge,
                kickoffDate: $0.kickoffDate,
                category: $0.category,
                popular: $0.popular
            )
        }
        Task { [weak self] in
            do {
                let wrote = try await cacheWriter.replace(with: records, generation: generation)
                guard wrote, self?.cacheWriteGeneration == generation else { return }
                self?.persistenceFailed = false
            } catch is CancellationError {
                return
            } catch {
                guard self?.cacheWriteGeneration == generation else { return }
                self?.persistenceFailed = true
            }
        }
    }
    
}
