import Foundation

/// Search reads a wider, already-accepted schedule than the three-day Home
/// projection. It owns no fetch, stream discovery, cache admission or playback.
@MainActor
enum SportsSearchSchedule {
    static let futureHorizon: TimeInterval = 14 * 86400
    static let receiptFreshness: TimeInterval = 24 * 3600

    static func isFresh(_ receipt: Date?, at now: Date) -> Bool {
        guard let receipt else { return false }
        return (-300...receiptFreshness).contains(now.timeIntervalSince(receipt))
    }

    static func events(
        sports: SportsFixtureCatalog.Snapshot?,
        cricket: CricketFixtureCatalog.Snapshot?,
        cpl: [CPLSchedule.Fixture] = [],
        cplCheckedAt: Date? = nil,
        cplSourceStatus: CPLSchedule.SourceStatus = .lastKnownGood,
        at now: Date
    ) -> [EventReference] {
        var result = SportsFixtureCatalog.upcomingSearchEvents(from: sports, at: now)
            + CricketFixtureCatalog.upcomingSearchEvents(from: cricket, at: now)
        // Bundled/last-known season data must not acquire new authority merely
        // because Search has a longer presentation window.
        if CPLSchedule.isFreshlyVerified(checkedAt: cplCheckedAt, sourceStatus: cplSourceStatus, at: now) {
            result += CPLSchedule.merging(into: [], fixtures: cpl, at: now)
        }
        let latest = now.addingTimeInterval(futureHorizon)
        return AnalyticalDataEngine.deduplicateMatches(result.sorted { $0.id < $1.id }).filter {
            !$0.hasCatalogIdentityConflict && !$0.isBroadcastChannel
                && ($0.sources ?? []).isEmpty
                && $0.kickoffDate.map { $0 > now && $0 <= latest } == true
        }.sorted {
            let left = $0.kickoffDate ?? .distantFuture, right = $1.kickoffDate ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
    }
}
