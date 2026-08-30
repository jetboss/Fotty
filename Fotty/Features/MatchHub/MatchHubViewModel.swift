import Foundation
import Combine

@MainActor
class MatchHubViewModel: ObservableObject {
    let fixtureId: String
    
    @Published var hubData: MatchHubData?
    @Published var catalogEvent: EventReference?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var discoveredProviders: [String] = []
    
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
    private let repository: FootballRepository
    private var refreshTimer: Timer?
    
    init(fixtureId: String, repository: FootballRepository = .shared) {
        self.fixtureId = fixtureId
        self.repository = repository
        
        loadMatchData(policy: .automatic)
        if !AppRuntime.isAutomatedTesting {
            startAutoRefresh()
        }
    }

    #if DEBUG
    init(testEvent: EventReference, repository: FootballRepository = .shared) {
        self.fixtureId = testEvent.id
        self.repository = repository
        self.catalogEvent = testEvent
        self.discoveredProviders = ["StreamEx"]
        self.isLoading = false
    }
    #endif
    
    func loadMatchData(policy: MatchHubRefreshPolicy = .automatic) {
        dataTask?.cancel()
        let requestID = UUID()
        dataRequestID = requestID
        if hubData == nil, catalogEvent == nil { isLoading = true }
        errorMessage = nil
        
        dataTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.repository.getMatchHubData(fixtureId: self.fixtureId, policy: policy)
                guard !Task.isCancelled, self.dataRequestID == requestID else { return }
                self.hubData = data
                self.catalogEvent = nil
                self.isLoading = false

                if data.fixture.status.isLive {
                    self.discoverProviders(for: data)
                }
            } catch {
                guard !Task.isCancelled, self.dataRequestID == requestID else { return }

                let routeRequest = Self.catalogRouteRequest(fixtureID: self.fixtureId)
                if let event = await LiveStreamResolver.shared.catalogEvent(for: routeRequest),
                   !(event.sources ?? []).isEmpty {
                    guard !Task.isCancelled, self.dataRequestID == requestID else { return }
                    self.catalogEvent = event
                    self.discoveredProviders = self.providerNames(for: event.sources ?? [])
                    self.errorMessage = nil
                    self.isLoading = false
                    return
                }

                self.errorMessage = "Match details could not be refreshed. Check your connection and try again."
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

    func resume() {
        if hubData == nil, catalogEvent == nil, dataTask == nil {
            loadMatchData(policy: .automatic)
        }
        if refreshTimer == nil, !AppRuntime.isAutomatedTesting {
            startAutoRefresh()
        }
    }

    func stop() {
        dataTask?.cancel()
        dataTask = nil
        streamTask?.cancel()
        streamTask = nil
        if let request = activeStreamRequest {
            Task {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
            }
        }
        activeStreamRequest = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func watchLive() {
        if let data = hubData {
            let fallbackEvent = makeFallbackPlaybackEvent(from: data)
            watchEvent(fallbackEvent, hubData: data)
            return
        }

        if let catalogEvent {
            watchEvent(catalogEvent, hubData: nil)
        }
    }
    
    private func watchEvent(_ event: EventReference, hubData data: MatchHubData?) {
        if let data, !data.fixture.status.isLive,
           data.fixture.status != .scheduled && data.fixture.status != .preMatch { return }
        let knownLive: FootballMatch.MatchStatus? = data?.fixture.status.isLive == true ? .inPlay : nil
        guard MatchStartPolicy(event: event, status: knownLive).timingAllowsPlayback else { return }
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
            let matchedEvent = await LiveStreamResolver.shared.catalogEvent(for: baseRequest) ?? event
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

            let outcome = await LiveStreamResolver.shared.resolvePlayback(for: request) { progress in
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
            case .failure:
                self.activeStreamRequest = nil
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

    private func discoverProviders(for data: MatchHubData) {
        let request = makePlaybackRequest(from: data, preferredEvent: makeFallbackPlaybackEvent(from: data))
        Task {
            // We only need the catalog/pre-resolution phase to see which providers have entries
            let catalogedEvent = await LiveStreamResolver.shared.catalogEvent(for: request)
            if let sources = catalogedEvent?.sources {
                let providers = self.providerNames(for: sources)
                
                await MainActor.run {
                    self.discoveredProviders = providers
                }
            }
        }
    }

    private func providerNames(for sources: [NexusASource]) -> [String] {
        Set(sources.compactMap { source in
            switch StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: source.source) {
            case "streamex": return "StreamEx"
            case "score808": return "Score808"
            default: return nil
            }
        }).sorted()
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
