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
    
    @Published var isFindingStream = false
    @Published var streamSessions: [StreamSession] = []
    @Published var streamError: String?
    @Published var streamStatusMessage = "Looking for a playable stream..."
    @Published var streamStatusDetail: String?
    @Published var showPlayer = false
    @Published var playerEvent: EventReference?
    
    private var streamTask: Task<Void, Never>?
    private var activeStreamRequest: StreamPlaybackRequest?
    private var streamRequestID = UUID()
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
                if self.isFindingStream { self.cancelStreamLookup() }
                self.refreshNotice = oldCatalog == nil ? nil : "This listing could not be verified. Saved details remain, but Watch is paused until a successful refresh."
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
        streamTask?.cancel()
        streamTask = nil
        if let request = activeStreamRequest {
            Task {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
            }
        }
        activeStreamRequest = nil
    }

    /// Scene inactivity must not tear down an already presented player or PiP.
    func pauseDataRefresh() {
        dataTask?.cancel()
        dataRequestID = UUID()
        dataTask = nil
        isRefreshing = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func watchLive() {
        if let data = hubData {
            let fallbackEvent = makeFallbackPlaybackEvent(from: data)
            watchEvent(fallbackEvent, hubData: data)
        }
    }

    /// Watch is offered exactly when tapping it would start a lookup: the
    /// fixture is live or about to start and its timing allows playback. Until
    /// 9 Nov this needed shared-catalog providers, which no match had after
    /// that catalog closed on 27 Oct.
    var canWatchLive: Bool {
        guard let data = hubData,
              data.fixture.status.isLive || data.fixture.status == .scheduled || data.fixture.status == .preMatch else { return false }
        let knownLive: FootballMatch.MatchStatus? = data.fixture.status.isLive ? .inPlay : nil
        return MatchStartPolicy(event: makeFallbackPlaybackEvent(from: data), status: knownLive).timingAllowsPlayback
    }
    
    private func watchEvent(_ event: EventReference, hubData data: MatchHubData?) {
        if let data, !data.fixture.status.isLive,
           data.fixture.status != .scheduled && data.fixture.status != .preMatch { return }
        let knownLive: FootballMatch.MatchStatus? = data?.fixture.status.isLive == true ? .inPlay : nil
        guard MatchStartPolicy(event: event, status: knownLive).timingAllowsPlayback else { return }
        guard !(isFindingStream && playerEvent?.id == event.id) else { return }
        HapticManager.impact(.light)
        MatchPlaybackFeedback.shared.attempting(event.id)
        if let inFlightRequest = activeStreamRequest {
            Task {
                await LiveStreamResolver.shared.cancelAttempt(for: inFlightRequest)
            }
        }

        streamTask?.cancel()
        let requestID = UUID()
        streamRequestID = requestID
        let baseRequest = data.map { makePlaybackRequest(from: $0, preferredEvent: event) }
            ?? StreamPlaybackRequest(event: event)
        activeStreamRequest = baseRequest
        
        isFindingStream = true
        playerEvent = event
        streamError = nil
        streamSessions = []
        streamStatusMessage = "Looking for a playable stream..."
        streamStatusDetail = nil

        streamTask = Task {
            do {
                try await StreamResolutionPresentation.waitForFeedbackFrame()
            } catch {
                return
            }
            guard !Task.isCancelled, self.streamRequestID == requestID else { return }
            // Complete dated fixture requests already have independent adapter
            // identity. Do not await a failed master catalog before those lanes.
            let matchedEvent: EventReference
            if ReviewedSportsFixtureMatcher.requestIdentity(for: baseRequest) != nil {
                matchedEvent = event
            } else {
                matchedEvent = await lookupCatalog(baseRequest) ?? event
            }
            guard !Task.isCancelled, streamRequestID == requestID else { return }
            guard MatchStartPolicy(event: matchedEvent, status: knownLive).timingAllowsPlayback else {
                isFindingStream = false
                activeStreamRequest = nil
                return
            }
            let request = data.map { makePlaybackRequest(from: $0, preferredEvent: matchedEvent) }
                ?? StreamPlaybackRequest(event: matchedEvent)

            await MainActor.run {
                guard self.streamRequestID == requestID else { return }
                self.playerEvent = matchedEvent
                self.activeStreamRequest = request
            }

            let outcome = await LiveStreamResolver.shared.resolvePlayback(for: request, singleStreamDiscovery: true) { progress in
                await MainActor.run {
                    guard self.streamRequestID == requestID else { return }
                    self.streamStatusMessage = progress.userMessage
                    self.streamStatusDetail = progress.technicalMessage
                }
            }

            guard !Task.isCancelled, self.streamRequestID == requestID else {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
                return
            }

            switch outcome {
            case .success(let success):
                let webSessions = success.sessions.filter(StreamPluginProviderMatching.isActivePlayerSession)
                self.streamSessions = webSessions
                self.isFindingStream = false
                self.streamStatusDetail = nil
                if webSessions.isEmpty {
                    self.showPlayer = false
                    self.activeStreamRequest = nil
                    MatchPlaybackFeedback.shared.notReady(event.id)
                } else {
                    self.showPlayer = true
                }
            case .failure(let failure, _):
                self.activeStreamRequest = nil
                self.streamError = failure.userMessage
                MatchPlaybackFeedback.shared.notReady(event.id)
                self.isFindingStream = false
            }
        }
    }

    func cancelStreamLookup() {
        streamTask?.cancel()
        if let request = activeStreamRequest {
            Task {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
            }
        }
        activeStreamRequest = nil
        isFindingStream = false
        streamStatusDetail = nil
    }

    private func makeFallbackPlaybackEvent(from data: MatchHubData) -> EventReference {
        EventReference(
            id: data.fixture.id,
            title: "\(data.homeTeam.displayName) vs \(data.awayTeam.displayName)",
            category: "football",
            date: Int64(data.fixture.utcDate.timeIntervalSince1970),
            poster: data.fixture.competition.emblemURL?.absoluteString,
            popular: Config.Arena.discoveryLeagueIds.contains(data.fixture.competition.id),
            teams: NexusATeams(
                home: NexusATeam(name: data.homeTeam.displayName, badge: data.homeTeam.crestURL?.absoluteString),
                away: NexusATeam(name: data.awayTeam.displayName, badge: data.awayTeam.crestURL?.absoluteString)
            ),
            sources: []
        )
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
    
    private func makePlaybackRequest(from data: MatchHubData, preferredEvent: EventReference) -> StreamPlaybackRequest {
        StreamPlaybackRequest(
            matchID: data.identity.routeID,
            displayTitle: preferredEvent.title ?? "\(data.homeTeam.displayName) vs \(data.awayTeam.displayName)",
            homeTeam: data.homeTeam.displayName,
            awayTeam: data.awayTeam.displayName,
            category: preferredEvent.normalizedCategory,
            kickoffDate: data.fixture.utcDate,
            preferredEvent: preferredEvent
        )
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
}
