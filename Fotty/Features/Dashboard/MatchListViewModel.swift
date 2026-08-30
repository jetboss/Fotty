import SwiftUI
import SwiftData
import Observation

/// BLUEPRINT: @MainActor (Swift 6 Strict Concurrency)
/// Manages the match list with local caching (SwiftData) and silent background refresh.
@MainActor
@Observable
final class MatchListViewModel {
    static let shared = MatchListViewModel()

    var matches: [AnalyticalDataEngine.EventReference] = []
    var isLoading = false
    var error: String?
    
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

    private let actor = MatchListActor()
    private var modelContext: ModelContext?
    private var didLoadCache = false
    private var recordedIdentityDiagnostics: Set<String> = []

    private init() {}

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadFromCache()
    }

    /// Home and My Matchday intentionally share one catalog instance. Configure
    /// persistence once the SwiftUI model context is available; subsequent calls
    /// are harmless and do not replace an already-loaded in-memory feed.
    func configure(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        loadFromCache()
    }

    /// Loads cached matches from SwiftData for immediate display (IINA Pattern).
    private func loadFromCache() {
        guard !didLoadCache, let modelContext else { return }
        didLoadCache = true
        #if DEBUG
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_HOME_UI_TESTING"] == "1" {
            let now = Date()
            func fixture(_ id: String, sport: String, title: String, hours: Double, watchable: Bool = false) -> AnalyticalDataEngine.EventReference {
                .init(id: id, title: title, category: sport, date: Int64(now.addingTimeInterval(hours * 3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil,
                      sources: watchable ? [.init(source: "delta", id: "ui-only-\(id)")] : [])
            }
            // Network-free presentation data; never written to the cache.
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
                : CPLSchedule.merging(into: cachedMatches)
            print("[MatchList] Loaded \(matches.count) items from SwiftData cache.")
        } catch {
            print("[MatchList] SwiftData fetch failed: \(error.localizedDescription)")
        }
    }
    
    /// Optimized refresh using URLCache and background decoding (IINA Pattern).
    func refresh() async {
        guard !isLoading else { return }
        isLoading = matches.isEmpty
        error = nil // Clear previous errors
        
        do {
            let freshMatches = try await fetchFreshMatches()
            applyFreshMatches(freshMatches)
            await MatchReminderStore.shared.reconcile(events: matches) {
                MatchStartPolicy.currentStatus(for: $0, scores: .shared)
            }
            
            self.isLoading = false
            self.error = nil
            print("[MatchList] Refresh complete with \(freshMatches.count) matches.")
            
        } catch {
            // Ignore cancellation errors — they occur naturally during navigation
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                print("[MatchList] Refresh cancelled via navigation.")
                self.isLoading = false
                return
            }
            
            if matches.isEmpty {
                self.error = "Could not load matches: \(error.localizedDescription)"
            } else {
                // Keep stale cache visible if a background refresh fails.
                self.error = nil
            }
            self.isLoading = false
        }
    }

    private func fetchFreshMatches() async throws -> [AnalyticalDataEngine.EventReference] {
        return try await AnalyticalDataEngine.allLiveEvents()
    }
    
    private func applyFreshMatches(_ decodedMatches: [AnalyticalDataEngine.EventReference]) {
        let nearTerm = CPLSchedule.merging(into: decodedMatches.filter { $0.passesNearTermLiveListWindow() })
        guard !nearTerm.isEmpty else { return }

        recordIdentityDrift(in: nearTerm)

        // Sync with SwiftData cache (near-term only; empty clears stale cache)
        try? updateCache(with: nearTerm)

        withAnimation(.easeInOut) {
            self.matches = nearTerm
        }
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


    
    private func updateCache(with freshMatches: [AnalyticalDataEngine.EventReference]) throws {
        guard let modelContext else { return }
        try modelContext.delete(model: MatchCacheItem.self)
        for match in freshMatches {
            let item = MatchCacheItem(
                id: match.id,
                title: match.title,
                homeName: match.homeName,
                awayName: match.awayName,
                homeBadge: match.teams?.home?.badge,
                awayBadge: match.teams?.away?.badge,
                kickoffDate: match.kickoffDate,
                category: match.category,
                popular: match.popular
            )
            modelContext.insert(item)
        }
        try modelContext.save()
    }
    
}
