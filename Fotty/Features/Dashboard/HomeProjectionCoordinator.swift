import SwiftUI
import Observation

struct HomeCatalogProjectionKey: Hashable {
    let contentRevision: Int
    let scoreRevisionMilliseconds: Int64
    let clockDate: Date
    let selectionIdentity: SportsPersonalizationPolicy.SelectionIdentity

    var factsKey: HomePersonalizationFactsKey {
        .init(contentRevision: contentRevision,
              scoreRevisionMilliseconds: scoreRevisionMilliseconds,
              selectionIdentity: selectionIdentity)
    }
}

struct HomePersonalizationContext {
    let selection: SportsPersonalizationPolicy.PreparedSelection
    let facts: [String: HomePersonalizationFacts]
}

@MainActor
struct HomeProjectionInput {
    let key: HomeCatalogProjectionKey
    let selection: SportsPersonalizationPolicy.PreparedSelection
    let providerEvents: [EventReference]
    let terminalEvents: [EventReference]
    let officialChampionsLeague: [EventReference]
}

/// All base values belong to the same accepted catalog/score/clock request.
@MainActor
struct HomeProjectionBase {
    let key: HomeCatalogProjectionKey
    let revision: Int
    let discovery: HomeSportsDiscovery
    let presentations: [String: HomeDiscoveryRow.Presentation]
    let footballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab]
    let selection: SportsPersonalizationPolicy.PreparedSelection
    let factsCache: HomePersonalizationFactsCache
}

@MainActor
struct HomeProjectionScope {
    let ranking: HomeDiscoveryRankingSnapshot
    let homeActivities: [HomeSportsDiscovery.SportActivity]
    let lineupActivities: [HomeSportsDiscovery.SportActivity]
}

@MainActor
struct HomeProjectionPacket {
    let base: HomeProjectionBase
    let scope: HomeProjectionScope
}

/// Owns preparation, cache reuse and atomic publication, not fetching or Watch
/// commands. The View still owns the structured .task and its cancellation.
@MainActor
@Observable
final class HomeProjectionCoordinator {
    private(set) var packet: HomeProjectionPacket?
    @ObservationIgnored private var requestGeneration = UUID()

    @discardableResult
    func rebuild(
        input: HomeProjectionInput,
        status: (EventReference) -> FootballMatch.MatchStatus?,
        facts: (HomeSportsDiscovery.Item, SportsPersonalizationPolicy.PreparedSelection) -> HomePersonalizationFacts,
        footballLeague: (EventReference) -> AnalyticalDataEngine.FootballLeagueTab,
        presentation: (HomeSportsDiscovery.Item) -> HomeDiscoveryRow.Presentation,
        isCurrent: () -> Bool,
        deriveScope: (HomeProjectionBase) -> HomeProjectionScope,
        checkpoint: () async -> Bool = { await HomeProjectionWorkPolicy.checkpoint { true } }
    ) async -> Bool {
        // A cancelled/stale task can enter late. It must not claim ownership
        // and invalidate the current pending request merely by starting.
        guard !Task.isCancelled, isCurrent() else { return false }
        let generation = UUID()
        requestGeneration = generation
        let signpostState = FottyPerformanceTrace.catalog.beginInterval("CatalogProjection")
        defer { FottyPerformanceTrace.catalog.endInterval("CatalogProjection", signpostState) }
        func acceptsRequest() -> Bool {
            !Task.isCancelled && requestGeneration == generation && isCurrent()
        }
        guard acceptsRequest(), await checkpoint(), acceptsRequest() else { return false }
        let deduplicationInterval = FottyPerformanceTrace.catalog.beginInterval("CatalogDeduplication")
        let catalog: [EventReference]?
        do {
            defer { FottyPerformanceTrace.catalog.endInterval("CatalogDeduplication", deduplicationInterval) }
            catalog = await AnalyticalDataEngine.deduplicateMatchesCooperatively(
                input.providerEvents + input.officialChampionsLeague,
                isCurrent: acceptsRequest, checkpoint: { _ in await checkpoint() })
        }
        guard let catalog else { return false }
        guard await checkpoint(), acceptsRequest() else { return false }
        let discoveryInterval = FottyPerformanceTrace.catalog.beginInterval("CatalogDiscovery")
        let projected = HomeSportsDiscovery(events: catalog, now: input.key.clockDate,
            terminalEvents: input.terminalEvents, status: status)
        FottyPerformanceTrace.catalog.endInterval("CatalogDiscovery", discoveryInterval)
        guard await checkpoint(), acceptsRequest() else { return false }
        var leagues: [String: AnalyticalDataEngine.FootballLeagueTab] = [:]
        var presentations: [String: HomeDiscoveryRow.Presentation] = [:]
        let reusableFacts = packet?.base.factsCache.facts(matching: input.key.factsKey) ?? [:]
        var preparedFacts: [String: HomePersonalizationFacts] = [:]
        preparedFacts.reserveCapacity(projected.items.count)
        leagues.reserveCapacity(projected.items.count)
        presentations.reserveCapacity(projected.items.count)
        for (index, item) in projected.items.enumerated() {
            guard !Task.isCancelled else { return false }
            preparedFacts[item.id] = reusableFacts[item.id] ?? facts(item, input.selection)
            if item.sport == "football" { leagues[item.id] = footballLeague(item.event) }
            presentations[item.id] = presentation(item)
            if (index + 1).isMultiple(of: 16) {
                guard await checkpoint(), acceptsRequest() else { return false }
            }
        }
        let factsCache = HomePersonalizationFactsCache(key: input.key.factsKey, facts: preparedFacts)
        guard await checkpoint(), acceptsRequest() else { return false }
        let base = HomeProjectionBase(key: input.key, revision: (packet?.base.revision ?? 0) &+ 1,
            discovery: projected, presentations: presentations, footballLeagues: leagues,
            selection: input.selection, factsCache: factsCache)
        // The caller reads the latest scope here. Nothing suspends between that
        // derivation and the single visible assignment, even if scope changed
        // while a base stage was preparing.
        let scoped = deriveScope(base)
        guard acceptsRequest() else { return false }
        publish(.init(base: base, scope: scoped))
        return true
    }

    /// A scope-only edit retains the accepted base revision and receipt/cache.
    /// It does not supersede a pending base task, which will derive latest scope.
    func refreshScope(deriveScope: (HomeProjectionBase) -> HomeProjectionScope) {
        guard let base = packet?.base else { return }
        publish(.init(base: base, scope: deriveScope(base)))
    }

    private func publish(_ packet: HomeProjectionPacket) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { self.packet = packet }
    }
}
