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
/// Whether a schedule receipt is current enough to confirm a match for
/// continuity and handoff: verified rows, checked within the schedules' status
/// freshness, allowing for device clock skew. The schedules replaced the closed
/// shared catalog, whose 60 s receipt these features used until 27 Oct 2026.
enum ScheduleReceiptPolicy {
    static let freshness = SportsFixtureCatalog.statusFreshness
    static let clockSkew: TimeInterval = 300

    static func isCurrent(_ receipt: Date, at now: Date) -> Bool {
        (-clockSkew...freshness).contains(now.timeIntervalSince(receipt))
    }
}

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
    private(set) var persistenceFailed = false
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
    @ObservationIgnored private var browseCatalogCache: [EventReference]?
    var playbackCatalog: [EventReference] { matches }

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

    /// Home's one data notice: CPL times shown from a CPL schedule that is no
    /// longer freshly verified. The schedules have no other refresh failure
    /// that changes what is shown.
    func catalogNotice(at now: Date = Date(), displaying visibleEvents: [EventReference]? = nil) -> String? {
        catalogNotice(at: now, displaysCPLSchedule: (visibleEvents ?? matches).contains(where: \.isCPLFixture))
    }

    func catalogNotice(at now: Date, displaysCPLSchedule: Bool) -> String? {
        displaysCPLSchedule && !isCPLScheduleFresh(at: now) ? "CPL start times may have changed." : nil
    }

    /// When the schedule that covers a match was last verified, if that receipt
    /// is current: CPL's own schedule, the cricket schedule for cricket, and
    /// the sports schedule for everything else. Nil means the match cannot be
    /// confirmed now.
    func scheduleReceipt(category: String, matchID: String, at now: Date = Date()) -> Date? {
        let verified: Bool, receipt: Date?
        if CPLSchedule.isManagedFixtureID(matchID) {
            verified = isCPLScheduleFresh(at: now); receipt = cplScheduleCheckedAt
        } else if ReviewedSportsFixtureMatcher.sportKey(category) == "cricket" {
            verified = cricketFixtureSnapshot?.sourceStatus.verifiesCurrentRows == true
            receipt = cricketFixtureSnapshot?.receiptDate
        } else {
            verified = sportsFixtureSnapshot?.sourceStatus.verifiesCurrentRows == true
            receipt = sportsFixtureSnapshot?.receiptDate
        }
        guard verified, let receipt, ScheduleReceiptPolicy.isCurrent(receipt, at: now) else { return nil }
        return receipt
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
    init(refreshSchedule: @escaping @MainActor () async -> CPLSchedule.Snapshot? = { nil },
         refreshCricket: @escaping @MainActor () async -> CricketFixtureCatalog.Snapshot? = { nil },
         refreshSports: @escaping @MainActor () async -> SportsFixtureCatalog.Snapshot? = { nil },
         now: @escaping () -> Date = Date.init,
         fixtures: [CPLSchedule.Fixture] = [],
         matchdayStore: MyMatchdayStore? = nil) {
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
            cplScheduleCheckedAt = now
            cplScheduleSourceStatus = .verified
            if ProcessInfo.processInfo.environment["FOTTY_CATALOG_UI_STATE"] == "stale-cpl" {
                cplScheduleCheckedAt = now.addingTimeInterval(-3 * 3600)
            }
        }
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_HOME_UI_TESTING"] == "1" {
            let now = HomeSportsDiscovery.automatedClockStart ?? Date()
            func fixture(_ id: String, sport: String, title: String, hours: Double) -> AnalyticalDataEngine.EventReference {
                .init(id: id, title: title, category: sport, date: Int64(now.addingTimeInterval(hours * 3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil)
            }
            // Network-free presentation data; never written to the cache.
            if HomeSportsDiscovery.automatedClockStart != nil {
                matches = [
                    fixture("cpl-2026-ui-today", sport: "cricket", title: "CPL · Guyana Amazon Warriors vs Antigua & Barbuda Falcons", hours: 65.0 / 60),
                    fixture("cpl-2026-ui-next", sport: "cricket", title: "CPL · Trinbago Knight Riders vs Barbados Tridents", hours: 125.0 / 60),
                    fixture("cpl-2026-ui-tomorrow", sport: "cricket", title: "CPL · Guyana Amazon Warriors vs Saint Lucia Kings", hours: 25)
                ]
                cplScheduleCheckedAt = now
                return
            }
            matches = [
                fixture("ui-football", sport: "football", title: "Arsenal vs Chelsea", hours: -0.5),
                fixture("ui-basketball", sport: "basketball", title: "Lakers vs Warriors", hours: -0.25),
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
                .init(id: "ui-willow", title: "Willow Cricket", category: "cricket", date: -3_600_000, poster: nil, popular: false, teams: nil),
                .init(id: "cpl-2026-ui", title: "CPL · Trinbago Knight Riders vs Barbados Tridents", category: "cricket", date: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil)
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
                    )
                )
            }.filter { $0.passesNearTermLiveListWindow() }
            // Accessibility/UI tests only need a representative first screen.
            // Bounding the fixture tree keeps XCTest's audit analyzer below its
            // hard timeout without changing production data or layout behavior.
            // Rows come from the cached schedules; cached rows from the closed
            // shared catalog are not restored.
            self.matches = AppRuntime.isAutomatedTesting
                ? Array(cachedMatches.prefix(40))
                : scheduleRows(at: Date())
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

    private enum ScheduleLane {
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

    /// Home's rows come from the CPL, cricket and sports schedules. Each lane
    /// publishes as it lands; the first completion always rebuilds, so rows
    /// restored from the on-disk cache are replaced by current schedules.
    private func performRefresh() async {
        guard !isRefreshing else { return }
        lastRefreshAttempt = currentDate()
        isRefreshing = true
        isLoading = matches.isEmpty
        defer { isRefreshing = false; isLoading = false }
        let cpl = refreshSchedule
        let cricket = refreshCricket
        let sports = refreshSports
        await withTaskGroup(of: ScheduleLane.self) { group in
            group.addTask { @MainActor in .cpl(await cpl()) }
            group.addTask { @MainActor in .cricket(await cricket()) }
            group.addTask { @MainActor in .sports(await sports()) }
            var rebuilt = false
            for await lane in group {
                guard !Task.isCancelled else {
                    lastRefreshAttempt = nil
                    group.cancelAll()
                    return
                }
                guard accept(lane) || !rebuilt else { continue }
                rebuilt = true
                applySchedules()
                if !matches.isEmpty { isLoading = false }
                await reconcilePersonalState()
            }
        }
    }

    private func accept(_ lane: ScheduleLane) -> Bool {
        switch lane {
        case .cpl(let snapshot): return snapshot.map(acceptSchedule) ?? false
        case .cricket(let snapshot): return snapshot.map(acceptCricket) ?? false
        case .sports(let snapshot): return snapshot.map(acceptSports) ?? false
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

    /// Rebuild Home's near-term rows from the accepted schedules.
    private func applySchedules() {
        let nearTerm = scheduleRows(at: currentDate())

        recordIdentityDrift(in: nearTerm)

        // A refresh can replace hundreds of rows. Global animation of that diff
        // competes with an active scroll and provides no useful spatial
        // meaning; individual user actions retain their focused animations.
        self.matches = nearTerm
        scheduleCacheWrite(nearTerm)
    }

    /// Home's near-term rows from the accepted CPL, cricket and sports schedules.
    private func scheduleRows(at now: Date) -> [EventReference] {
        SportsFixtureCatalog.merging(
            into: CricketFixtureCatalog.merging(
                into: CPLSchedule.merging(into: [], fixtures: cplFixtures, at: now),
                snapshot: cricketFixtureSnapshot, at: now),
            snapshot: sportsFixtureSnapshot, at: now)
            .filter { $0.passesNearTermLiveListWindow(at: now) }
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
                    "source": "fixture_schedule",
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
