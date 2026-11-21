import Foundation
import Combine

@MainActor
class MatchHubViewModel: ObservableObject {
    let fixtureId: String
    
    @Published private(set) var snapshot: MatchHubSnapshot?
    var hubData: MatchHubData? { snapshot?.match }
    var insights: MatchInsightsData? { snapshot?.insights }
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var refreshNotice: String?
    @Published var catalogEvent: EventReference?
    @Published var isLoading = true
    @Published var errorMessage: String?


    private var dataTask: Task<Void, Never>?
    private var dataRequestID = UUID()
    private let repository: any MatchHubDataLoading
    /// No production catalog since the shared catalog closed; tests may inject one.
    private var lookupCatalog: @MainActor (StreamPlaybackRequest) async -> EventReference? = { _ in nil }
    private var currentDate: () -> Date = Date.init
    private var isFixtureOnly = false
    /// A retained catalog snapshot is readable after failure, not authority to
    /// retry a delivery route whose current identity could not be checked.
    private var refreshTimer: Timer?
    
    init(fixtureId: String, repository: any MatchHubDataLoading = FootballRepository.shared,
         lookupCatalog: (@MainActor (StreamPlaybackRequest) async -> EventReference?)? = nil,
         now: @escaping () -> Date = Date.init, startsAutomatically: Bool = true) {
        self.fixtureId = fixtureId
        self.repository = repository
        self.currentDate = now
        if let lookupCatalog { self.lookupCatalog = lookupCatalog }
        if startsAutomatically { loadMatchData(policy: .automatic) }
        if startsAutomatically, !AppRuntime.isAutomatedTesting {
            startAutoRefresh()
        }
    }

    #if DEBUG
    init(testEvent: EventReference, repository: any MatchHubDataLoading = FootballRepository.shared) {
        self.fixtureId = testEvent.id
        self.repository = repository
        self.catalogEvent = testEvent
        self.isLoading = false
        self.isFixtureOnly = true
    }
    #endif
    
    func loadMatchData(policy: MatchHubRefreshPolicy = .automatic) {
        dataTask?.cancel()
        let requestID = UUID()
        dataRequestID = requestID
        if hubData == nil, catalogEvent == nil { isLoading = true }
        isRefreshing = true
        
        dataTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.dataRequestID == requestID {
                    self.isRefreshing = false
                    self.isLoading = false
                    self.dataTask = nil
                }
            }
            do {
                let snapshot = try await self.repository.matchHubSnapshot(fixtureId: self.fixtureId, policy: policy)
                guard !Task.isCancelled, self.dataRequestID == requestID else { return }
                let data = snapshot.match
                guard data.identity.resolves(self.fixtureId), snapshot.insights.fixtureId == data.fixture.id,
                      snapshot.insights.lastUpdated == data.lastUpdated else { throw URLError(.cannotParseResponse) }
                let previousDate = self.hubData?.lastUpdated
                if let previousDate, data.lastUpdated < previousDate {
                    self.refreshNotice = "The update was older than the match already shown. Keeping the last complete update."
                    return
                }
                self.snapshot = snapshot
                self.catalogEvent = nil
                self.isLoading = false
                self.errorMessage = nil
                self.lastCheckedAt = self.currentDate()
                let age = self.currentDate().timeIntervalSince(data.lastUpdated)
                self.refreshNotice = data.dataQuality == .stale || age < 0 || age > (data.fixture.status.isLive ? 120 : 900)
                    ? "Showing the last available match update. New data could not be confirmed."
                    : (policy.allowsProviderEnrichment && previousDate == data.lastUpdated
                       ? "No newer match update was available. The last complete update is still shown." : nil)

            } catch {
                guard !Task.isCancelled, self.dataRequestID == requestID else { return }

                // A failed full refresh cannot replace a complete score/lineup
                // snapshot with an unrelated partial catalog fallback.
                if self.hubData != nil {
                    self.errorMessage = "Match details could not be refreshed. The last complete update is still shown."
                    self.refreshNotice = self.errorMessage
                    return
                }

                let oldCatalog = self.catalogEvent
                let routeRequest = oldCatalog.map {
                    StreamPlaybackRequest(matchID: $0.id, displayTitle: $0.displayTitle, homeTeam: $0.homeName,
                        awayTeam: $0.awayName, category: $0.normalizedCategory, kickoffDate: nil, preferredEvent: nil)
                } ?? Self.catalogRouteRequest(fixtureID: self.fixtureId)
                let candidate = await self.lookupCatalog(routeRequest)
                guard !Task.isCancelled, self.dataRequestID == requestID else { return }
                if let event = candidate, !event.hasCatalogIdentityConflict,
                   CatalogPlaybackIdentity.matchingEvent(for: routeRequest, in: [event]) != nil {
                    self.catalogEvent = event
                    self.errorMessage = nil
                    self.refreshNotice = nil
                    self.lastCheckedAt = self.currentDate()
                    self.isLoading = false
                    return
                }

                self.errorMessage = "Match details could not be refreshed. Check your connection and try again."
                self.refreshNotice = oldCatalog == nil ? nil : "This listing could not be verified. Saved details remain."
                self.isLoading = false
            }
        }
    }
    
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadMatchData(policy: .automatic)
            }
        }
    }
    
    func refreshData() {
        loadMatchData(policy: .full)
    }

    func refresh() async {
        loadMatchData(policy: .full)
        await dataTask?.value
    }

    func resume() {
        if !isFixtureOnly, dataTask == nil,
           lastCheckedAt.map({ currentDate().timeIntervalSince($0) >= 60 }) ?? true {
            loadMatchData(policy: .automatic)
        }
        if refreshTimer == nil, !AppRuntime.isAutomatedTesting {
            startAutoRefresh()
        }
    }

    func stop() {
        pauseDataRefresh()
    }

    func pauseDataRefresh() {
        dataTask?.cancel()
        dataRequestID = UUID()
        dataTask = nil
        isRefreshing = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// The match page has no Watch of its own. While the match can still be
    /// watched it offers Search for the home team; the shared Watch path then
    /// identifies and plays whatever match the viewer picks there.
    var findInFottyQuery: String? {
        guard let data = hubData,
              data.fixture.status.isLive || data.fixture.status == .scheduled || data.fixture.status == .preMatch
        else { return nil }
        let name = data.homeTeam.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func catalogRouteRequest(fixtureID: String) -> StreamPlaybackRequest {
        StreamPlaybackRequest(
            matchID: fixtureID,
            displayTitle: "Live match",
            homeTeam: "",
            awayTeam: "",
            category: "",
            kickoffDate: nil,
            preferredEvent: nil
        )
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
}
