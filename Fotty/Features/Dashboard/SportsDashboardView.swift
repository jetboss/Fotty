import SwiftUI
import SwiftData
import UIKit

private struct CatalogClockKey: Hashable {
    let isActive: Bool
    let contentRevision: Int
}

private struct IndexedMultiResolution: Sendable {
    let index: Int
    let outcome: StreamResolutionOutcome
}

struct SportsDashboardView: View {
    let isActive: Bool
    @Environment(\.fottyWideLayout) private var usesWideLayout
    @State private var matchListViewModel: MatchListViewModel?
    @State private var myMatchdayStore: MyMatchdayStore
    @State private var lastLiveStore = LastLiveMatchStore.shared
    @SceneStorage(BrowsingStateKey.homeSport) private var selectedSportTab = HomeSportsDiscovery.allSports
    @SceneStorage(BrowsingStateKey.homeFootballLeague) private var selectedFootballLeagueRaw = AnalyticalDataEngine.FootballLeagueTab.all.rawValue
    @SceneStorage(BrowsingStateKey.homeCricketFilter) private var selectedCricketFilterRaw = CricketCatalogFilter.all.rawValue
    @SceneStorage(BrowsingStateKey.homeFollowingOnly) private var showFollowedOnly = false
    @AppStorage(HomeInterestPreferences.onlyShowSelectedKey) private var onlyShowSelectedInterests = false
    @AppStorage(SportsInterestPreferences.storageKey) private var followedSportsRaw = "[]"
    @State private var projectionCoordinator = HomeProjectionCoordinator()
    @State private var showsMoreLive = false
    @State private var tvLibrary = SportsTVLibrary.shared
    @State private var tvRegistry = BroadcastRegistryClient.shared
    @AppStorage(CommentaryPreference.storageKey) private var tvCommentary = CommentaryPreference.english.rawValue
    @State private var showsFullLineup = false
    @State private var showsAllSports = false
    @State private var allSportsAppliesHomeInterests = true
    @State private var showsSearch = false
    @State private var showsInterestEditor = false
    @State private var showsClubPicker = false
    @State private var homeResultsRequest = 0
    @State private var pendingSearchSelection: PendingSearchSelection?
    @State private var discoveryDate = HomeSportsDiscovery.automatedClockDate ?? Date()
    @State private var showPlayer = false
    @State private var showMultiPlayer = false
    @State private var streamSessions: [StreamSession] = []
    @State private var multiViewSlots: [MultiLiveSlot] = []
    @State private var activeMultiRequests: [StreamPlaybackRequest] = []
    @State private var streamEvent: AnalyticalDataEngine.EventReference? = nil
    @State private var isFindingStream = false
    @State private var isFindingMultiStreams = false
    @State private var multiResolutionTitles: [String] = []
    @State private var streamError: String? = nil
    @State private var streamStatusMessage = "Looking for a playable stream..."
    @State private var multiStreamStatusMessage = "Preparing two-match view..."
    @State private var streamTask: Task<Void, Never>?
    @State private var multiStreamTask: Task<Void, Never>?
    @State private var streamRequestID = UUID()
    @State private var multiStreamRequestID = UUID()
    @State private var isMultiSelectMode = false
    @State private var selectedMultiEventIDs: [String] = []
    @State private var savedMatchError: String?
    @State private var selectedCatalogEvent: AnalyticalDataEngine.EventReference? = nil
    @State private var pendingDetailsWatch: AnalyticalDataEngine.EventReference?
    @State private var pendingDetailsSourceCheck: AnalyticalDataEngine.EventReference?
    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(\.fottyOpenSettings) private var openSettings
    @State private var scorePollingOwner = UUID()
    @State private var selectedHighlightsMatch: FootballMatch? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query private var followedLeagues: [FollowedLeagueItem]

    private static let footballCategoryID = "football"

    @MainActor
    init(isActive: Bool = true, matchListViewModel: MatchListViewModel? = nil,
         myMatchdayStore: MyMatchdayStore? = nil) {
        self.isActive = isActive
        self._matchListViewModel = State(initialValue: matchListViewModel)
        self._myMatchdayStore = State(initialValue: myMatchdayStore ?? .shared)
    }

    private var selectedFootballLeague: AnalyticalDataEngine.FootballLeagueTab {
        get { .init(rawValue: selectedFootballLeagueRaw) ?? .all }
        nonmutating set { selectedFootballLeagueRaw = newValue.rawValue }
    }

    private var selectedCricketFilter: CricketCatalogFilter {
        get { .init(rawValue: selectedCricketFilterRaw) ?? .all }
        nonmutating set { selectedCricketFilterRaw = newValue.rawValue }
    }

    private var footballLeagueBinding: Binding<AnalyticalDataEngine.FootballLeagueTab> {
        .init(get: { selectedFootballLeague }, set: { selectedFootballLeague = $0 })
    }

    private var cricketFilterBinding: Binding<CricketCatalogFilter> {
        .init(get: { selectedCricketFilter }, set: { selectedCricketFilter = $0 })
    }

    // Explicit browsing actions return to their results. Restored state and
    // background catalog updates never move the user's scroll position.
    private var homeSportBinding: Binding<String> {
        .init(get: { selectedSportTab }, set: {
            guard selectedSportTab != $0 else { return }
            selectedSportTab = $0
            requestHomeResults()
        })
    }

    private var homeLeagueBinding: Binding<AnalyticalDataEngine.FootballLeagueTab> {
        .init(get: { selectedFootballLeague }, set: {
            guard selectedFootballLeague != $0 else { return }
            selectedFootballLeague = $0
            requestHomeResults()
        })
    }

    private var homeCricketBinding: Binding<CricketCatalogFilter> {
        .init(get: { selectedCricketFilter }, set: {
            guard selectedCricketFilter != $0 else { return }
            selectedCricketFilter = $0
            requestHomeResults()
        })
    }

    private func requestHomeResults() {
        showsMoreLive = false
        homeResultsRequest += 1
    }

    private struct PendingSearchSelection {
        enum Destination { case open, details, checkStreams }
        let event: AnalyticalDataEngine.EventReference
        let destination: Destination
    }

    var body: some View {
        NavigationStack {
            mainContent
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isMultiSelectMode {
                        multiSelectChrome
                    }
                }
                .navigationDestination(isPresented: $showsFullLineup) {
                    fullLineup
                }
                .fullScreenCover(isPresented: $showsClubPicker) { TeamOnboardingView() }
                .navigationDestination(isPresented: $showsInterestEditor) {
                    SettingsManageLeaguesView(previewEvents: matchListViewModel?.playbackCatalog ?? [])
                }
        }
        .environment(\.fottyStreamLookupBusy, isFindingAnyStream || (!viewing.isTwo && viewing.resolutionMessage != nil))
        .environment(\.fottySceneOwnsSingleWatch, !isMultiSelectMode && !viewing.isTwo)
        .environment(\.fottyPendingWatchEventID, !isMultiSelectMode && !viewing.isTwo ? viewing.pendingSingleEvent?.id : nil)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let pending = viewing.pendingSingleEvent, let message = viewing.resolutionMessage {
                StreamResolutionPanel(sportCategory: pending.normalizedCategory,
                    competition: SportMotionContext.competition(for: pending), statusMessage: message,
                    subtitle: pending.displayTitle, isMultiStream: false, multiTitles: [],
                    onCancel: { viewing.cancelPendingSingleDiscovery() })
            } else if isFindingAnyStream {
                StreamResolutionPanel(
                    sportCategory: isFindingMultiStreams ? HomeSportsDiscovery.allSports : (streamEvent?.normalizedCategory ?? selectedSportTab),
                    competition: isFindingMultiStreams ? nil : SportMotionContext.competition(for: streamEvent),
                    statusMessage: isFindingMultiStreams ? multiStreamStatusMessage : streamStatusMessage,
                    subtitle: streamEvent.map { eventTitle($0) },
                    isMultiStream: isFindingMultiStreams,
                    multiTitles: multiResolutionTitles,
                    onCancel: cancelCurrentResolution
                )
            }
        }
        .alert("Stream Not Available", isPresented: .init(
            get: { streamError != nil },
            set: { if !$0 { streamError = nil } }
        )) {
            Button("OK") { streamError = nil }
        } message: {
            Text(streamError ?? "")
        }
        .alert("Couldn't update My Matchday", isPresented: .init(
            get: { savedMatchError != nil },
            set: { if !$0 { savedMatchError = nil } }
        )) {
            Button("OK") { savedMatchError = nil }
        } message: {
            Text(savedMatchError ?? "")
        }
        .dashboardPresentationLayers(
            selectedHighlightsMatch: $selectedHighlightsMatch,
            showPlayer: $showPlayer,
            showMultiPlayer: $showMultiPlayer,
            streamEvent: streamEvent,
            streamSessions: streamSessions,
            multiViewSlots: multiViewSlots,
            liveScoreService: liveScoreService,
            onMultiPlaybackUnavailable: { eventID in
                MatchPlaybackFeedback.shared.notReady(eventID)
            }
        )
        .sheet(item: $selectedCatalogEvent, onDismiss: completePendingDetailsAction) { event in
            let detailsEvent = isMultiSelectMode || viewing.isTwo ? event
                : CurrentEventBroadcastPolicy.currentEvent(for: event,
                    in: matchListViewModel?.playbackAdmissionCatalog ?? []) ?? event
            CatalogEventDetailsView(event: detailsEvent, onWatch: canOpenBroadcast(event) ? {
                pendingDetailsWatch = event
                selectedCatalogEvent = nil
            } : nil, alternateActionTitle: cplChannelActionTitle(event),
                onCheckStreams: optionalSourceCheckAction(for: event))
                .environment(liveScoreService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsSearch, onDismiss: completePendingSearchSelection) {
            SearchView(
                discovery: discovery,
                isSaved: { myMatchdayStore.contains(event: $0) },
                canWatch: canOpenBroadcast(_:),
                alternateActionTitle: cplChannelActionTitle(_:),
                onOpen: { queueSearchSelection($0, destination: .open) },
                onDetails: { queueSearchSelection($0, destination: .details) },
                onSave: mutateSavedMatch(_:),
                onCheckStreams: { queueSearchSelection($0, destination: .checkStreams) },
                catalogNoticeForEvents: { events in
                    matchListViewModel?.catalogNotice(at: HomeSportsDiscovery.automatedClockDate ?? Date(), displaying: events)
                },
                catalogCheckedAt: matchListViewModel?.cplScheduleCheckedAt,
                isRefreshing: matchListViewModel?.isRefreshing ?? false,
                onRefresh: { await matchListViewModel?.refresh(); discoveryDate = Date() },
                catalogRevision: discoveryProjectionRevision,
                scheduledEvents: { matchListViewModel?.searchSchedule(at: Date()) ?? [] },
                scheduleRevision: matchListViewModel?.contentRevision ?? 0
            )
            .environment(liveScoreService)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAllSports) {
            NavigationStack {
                ScrollView {
                    SportActivityGrid(
                        discovery: discovery,
                        selectedSport: allSportsAppliesHomeInterests ? homeSportBinding : $selectedSportTab,
                        activities: allSportsAppliesHomeInterests ? homeSportActivities : fullLineupSportActivities,
                        expanded: true
                    )
                        .padding(FottyTheme.spacingMD)
                }
                .background(FottyTheme.background)
                .navigationTitle("Sports on the schedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsAllSports = false }
                    }
                }
            }
            .onChange(of: selectedSportTab) { _, _ in showsAllSports = false }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            viewing.cancelPendingSingleDiscovery()
            pendingDetailsSourceCheck = nil
            viewing.cancelOptionalSourceLookup()
            streamTask?.cancel()
            multiStreamTask?.cancel()
            streamRequestID = UUID()
            multiStreamRequestID = UUID()
            isFindingStream = false
            isFindingMultiStreams = false
            multiResolutionTitles = []
            isMultiSelectMode = false
            selectedMultiEventIDs = []
            streamSessions = []
            streamStatusMessage = "Looking for a playable stream..."
            multiStreamStatusMessage = "Preparing two-match view..."
            cancelActiveMultiStreamRequests()
        }
        .task(id: catalogProjectionKey) {
            await rebuildCatalogProjection()
        }
        .task(id: homeSportActivityProjectionKey) {
            rebuildSportActivityProjection()
        }
        .preference(key: FixturePreflightActivityPreferenceKey.self,
                    value: isActive && (isFindingAnyStream || isMultiSelectMode))
        .task(id: isActive && scenePhase == .active) {
            if matchListViewModel == nil {
                matchListViewModel = MatchListViewModel.shared
            }
            matchListViewModel?.configure(modelContext: modelContext)
            if let viewModel = matchListViewModel {
                ensureValidSportSelection(from: viewModel.sportsTabs)
            }

            guard !AppRuntime.isAutomatedTesting, isActive, scenePhase == .active else { return }
            await matchListViewModel?.refreshIfNeeded()
            if let viewModel = matchListViewModel {
                ensureValidSportSelection(from: viewModel.sportsTabs)
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(90))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await matchListViewModel?.refreshIfNeeded()
            }
        }
        .onAppear {
            #if DEBUG
            if AppRuntime.isAutomatedTesting, !Self.hasPreparedAutomatedBrowsingState {
                // SceneStorage intentionally survives navigation. Give each UI-test
                // process a deterministic starting point without resetting again
                // when SwiftUI recreates Home to verify in-scene restoration.
                Self.hasPreparedAutomatedBrowsingState = true
                selectedSportTab = ProcessInfo.processInfo.environment["FOTTY_CRICKET_UI_TESTING"] == "1"
                    ? "cricket"
                    : HomeSportsDiscovery.allSports
                selectedFootballLeague = .all
                selectedCricketFilter = .all
                showFollowedOnly = false
            }
            #endif
        }
        .task(id: isActive && scenePhase == .active) {
            guard !AppRuntime.isAutomatedTesting, isActive, scenePhase == .active else { return }
            await TeamBrandService.shared.bootstrapIfNeeded()
        }
        .task(id: CatalogClockKey(isActive: isActive && scenePhase == .active, contentRevision: matchListViewModel?.contentRevision ?? -1)) {
            // A lightweight local clock keeps "next" honest even if a network
            // refresh fails. It never starts an additional provider request.
            guard HomeSportsDiscovery.automatedClockStart == nil, isActive, scenePhase == .active else { return }
            while !Task.isCancelled {
                discoveryDate = Date()
                lastLiveStore.pruneExpiredRecord(at: discoveryDate)
                let events = (matchListViewModel?.matches ?? []) + discovery.items.map(\.event)
                let delay = HomeSportsDiscovery.nextClockDelay(events: events, now: discoveryDate)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
        .task(id: "\(isActive)-\(selectedSportTab)-\(scenePhase == .active)") {
            // All-sports includes football; reuse the same bounded score owner.
            guard !AppRuntime.isAutomatedTesting else { return }
            liveScoreService.updatePollingDemand(
                owner: scorePollingOwner,
                isActive: isActive && scenePhase == .active && showsFootballScores
            )
        }
        .onDisappear {
            liveScoreService.releasePolling(owner: scorePollingOwner)
        }
        .onChange(of: selectedSportTab) { _, newValue in
            showFollowedOnly = false
            if newValue != Self.footballCategoryID {
                selectedFootballLeague = .all
            }
        }
        .onChange(of: matchListViewModel?.sportsTabs) { _, tabs in
            if let tabs {
                ensureValidSportSelection(from: tabs)
            }
        }
        .onChange(of: selectedInterestCount) { _, count in
            if count == 0 {
                showFollowedOnly = false
                onlyShowSelectedInterests = false
            }
        }
        .onChange(of: liveScoreService.lastRefresh) { _, _ in
            discoveryDate = Date()
        }
        .onChange(of: matchListViewModel?.matches.count) { _, _ in
            guard selectedSportTab == Self.footballCategoryID else { return }
            if let tabs = matchListViewModel?.matches,
               !AnalyticalDataEngine.footballLeagueTabs(for: tabs).contains(selectedFootballLeague) {
                selectedFootballLeague = .all
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                viewing.cancelPendingSingleDiscovery()
                pendingDetailsSourceCheck = nil
                viewing.cancelOptionalSourceLookup()
            }
            guard !AppRuntime.isAutomatedTesting else { return }
            if newValue == .active {
                discoveryDate = Date()
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                viewing.cancelPendingSingleDiscovery()
                pendingDetailsSourceCheck = nil
                viewing.cancelOptionalSourceLookup()
            }
        }
    }

    #if DEBUG
    @MainActor private static var hasPreparedAutomatedBrowsingState = false
    #endif

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            if let viewModel = matchListViewModel {
                if viewModel.isLoading {
                    loadingView
                } else {
                    matchesContent(viewModel)
                }
            } else {
                loadingView
            }

        }
        .background(FottyTheme.background.ignoresSafeArea())
    }

    private func matchesContent(_ viewModel: MatchListViewModel) -> some View {
        let schedule = discovery
        let personalization = discoveryPersonalizationContext
        let usesPersonalizedWindow = isHomeInterestRestrictionActive && !showFollowedOnly
        let items = discoveryRankingSnapshot?.items(matching: discoveryRankingKey, home: true) ?? prioritizedDiscoveryItems(
            scopedItems(in: schedule, applyingHomeInterests: true, personalization: personalization),
            equalizeSelectedInterests: usesPersonalizedWindow,
            personalization: personalization, preservingLegacyOrder: isMultiSelectMode
        )
        let personalizedUpcomingLimit = UIDevice.current.userInterfaceIdiom == .pad ? 4 : 3
        let sections = schedule.homeSections(
            from: items,
            diverseUpcoming: !usesPersonalizedWindow && selectedSportTab == HomeSportsDiscovery.allSports,
            featuredLiveLimit: personalizedUpcomingLimit,
            upcomingHorizon: HomeUpcomingPresentationPolicy.horizon(personalized: usesPersonalizedWindow),
            upcomingLimit: usesPersonalizedWindow ? personalizedUpcomingLimit : 3,
            followedTeamKeys: personalization.selection.teamKeys,
            canWatch: { canOpenBroadcast($0.event) }
        )
        let later = usesPersonalizedWindow
            ? (title: "", items: [HomeSportsDiscovery.Item]())
            : schedule.later(from: items, excluding: sections.upcoming + [sections.nextClub].compactMap { $0 })
        let displaysCPLSchedule = items.contains {
            personalization.facts[$0.id]?.isCPL ?? $0.event.isCPLFixture
        }
        let catalogNoticeDate = HomeSportsDiscovery.automatedClockDate ?? Date()
        // Read layout/state dependencies before entering the escaping lazy
        // content closure. The sequence itself must update on a width change.
        let onAir: [HomeOnAirPolicy.Entry] = isMultiSelectMode || showFollowedOnly
            || ![HomeSportsDiscovery.allSports, "cricket"].contains(selectedSportTab) ? []
            : HomeOnAirPolicy.entries(library: tvLibrary, commentary: CommentaryPreference(rawValue: tvCommentary) ?? .english,
                snapshot: tvRegistry.snapshot, sport: selectedSportTab == HomeSportsDiscovery.allSports ? nil : "cricket",
                at: discoveryDate, limit: usesWideLayout ? 3 : 2, canWatch: { SportsTVStation.canWatchNow($0) })
        let entries = homeEntries(sections: sections, onAir: onAir, later: later, items: items,
                                  personalized: usesPersonalizedWindow, hasChannels: !schedule.channels.isEmpty, needsClub: personalization.selection.teamKeys.isEmpty,
                                  selectionIsEmpty: items.isEmpty && channelEvents(applyingHomeInterests: true).isEmpty,
                                  columns: usesWideLayout ? 2 : 1)

        return ScrollViewReader { proxy in
         ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                cinemaHomeMasthead
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("home-results")

                CatalogAdaptiveHeading {
                    Text("Tailored to you")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home-context-heading")
                } actions: {
                    Menu {
                    Button("Browse sports", systemImage: "sportscourt") {
                        allSportsAppliesHomeInterests = true
                        presentModal { showsAllSports = true }
                    }
                    if selectedSportTab != HomeSportsDiscovery.allSports {
                        Button("Clear sport filter", systemImage: "line.3.horizontal.decrease") {
                            selectedSportTab = HomeSportsDiscovery.allSports
                            selectedFootballLeague = .all
                            selectedCricketFilter = .all
                            requestHomeResults()
                        }
                    }
                    Toggle("Only my interests", isOn: $onlyShowSelectedInterests)
                        .disabled(selectedInterestCount == 0)
                    Button("Follow a club", systemImage: "star") { presentModal { showsClubPicker = true } }
                    Button("Edit interests", systemImage: "slider.horizontal.3") {
                        presentModal { showsInterestEditor = true }
                    }
                    .accessibilityIdentifier("dashboard-home-interests-edit")
                } label: {
                        HStack(spacing: 8) {
                            Text(homeScopeLabel ?? "All sports")
                            Image(systemName: "chevron.down").imageScale(.small)
                        }
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44, alignment: .leading)
                }
                    .buttonStyle(FottyPressButtonStyle())
                    .accessibilityLabel("Showing \(homeScopeLabel ?? "All sports")")
                    .accessibilityHint("Change the sport filter, show only your interests, or edit your interests")
                    .accessibilityIdentifier("home-selected-scope")
                }

                #if DEBUG
                if HomeSportsDiscovery.automatedClockStart != nil {
                    Button("Advance test clock past kickoff") {
                        HomeSportsDiscovery.advanceAutomatedClock()
                        discoveryDate = HomeSportsDiscovery.automatedClockDate ?? Date()
                    }
                    .accessibilityIdentifier("home-test-advance-clock")
                }
                #endif

                if let notice = viewModel.catalogNotice(at: catalogNoticeDate, displaysCPLSchedule: displaysCPLSchedule) {
                    CatalogRefreshNotice(message: notice, checkedAt: viewModel.cplScheduleCheckedAt,
                                         isRefreshing: viewModel.isRefreshing) {
                        await viewModel.refresh()
                    }
                } else if showsFootballScores && liveScoreService.showsFootballFixtureRefresh(at: discoveryDate) {
                    FootballFixtureRefreshProgress()
                }
                if viewModel.persistenceFailed {
                    Text("Couldn't save these listings for offline use.")
                        .font(FottyTheme.typeMeta).foregroundStyle(FottyTheme.error)
                }

                if showsFootballScores && liveScoreService.shouldShowScoreFeedNotice {
                    FootballQuotaBanner()
                }

                if showFollowedOnly {
                    Button("Clear team filter") { showFollowedOnly = false }
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Clear followed-teams filter")
                }

                if isMultiSelectMode {
                    homeMatchList(
                        events: filteredEvents.filter(isMultiViewCandidate(_:)),
                        usesMultiColumnGrid: false
                    )
                } else {
                    ForEach(entries) { entry in
                        homeEntry(entry)
                    }
                }

                if !viewing.isActive, let event = lastLiveEvent(at: discoveryDate) {
                    LastLiveMatchCard(event: event,
                        actionTitle: "Watch",
                        onOpen: { openLastLiveMatch(event) },
                        onDismiss: { lastLiveStore.clear() })
                }

                if selectedSportTab == "cricket" {
                    cricketDiscovery(applyingHomeInterests: true)
                }

                if isMultiSelectMode && items.isEmpty && channelEvents(applyingHomeInterests: true).isEmpty {
                    emptyState(applyingHomeInterests: true)
                }

                if !isMultiSelectMode { MatchdaySetupCard() }

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FottyTheme.bentoInset)
            .padding(.top, 4)
        }
        .refreshable {
            guard !AppRuntime.isAutomatedTesting else { return }
            await viewModel.refresh()
            discoveryDate = Date()
        }
         .onChange(of: homeResultsRequest) { _, _ in
             if reduceMotion {
                 proxy.scrollTo("home-results", anchor: .top)
             } else {
                 withAnimation(.easeInOut(duration: 0.22)) {
                     proxy.scrollTo("home-results", anchor: .top)
                 }
             }
         }
        }
    }

    private var homeScopeLabel: String? {
        var labels: [String] = []
        if selectedSportTab != HomeSportsDiscovery.allSports {
            labels.append(AnalyticalDataEngine.categoryDisplayName(for: selectedSportTab))
        }
        if showsFootballLeagueTabs, selectedFootballLeague != .all {
            labels.append(selectedFootballLeague.displayName)
        }
        if selectedSportTab == "cricket", selectedCricketFilter != .all {
            labels.append(selectedCricketFilter.displayName)
        }
        if isHomeInterestRestrictionActive { labels.append("Your interests") }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    private var catalogProjectionKey: HomeCatalogProjectionKey {
        HomeCatalogProjectionKey(
            contentRevision: matchListViewModel?.contentRevision ?? -1,
            scoreRevisionMilliseconds: Int64((liveScoreService.lastRefresh?.timeIntervalSince1970 ?? 0) * 1_000),
            clockDate: discoveryDate,
            selectionIdentity: personalizationSelectionIdentity
        )
    }

    private var homeSportActivityProjectionKey: HomeSportActivityProjectionKey {
        HomeSportActivityProjectionKey(
            selectedSport: selectedSportTab,
            selectedFootballLeague: selectedFootballLeagueRaw,
            selectedCricketFilter: selectedCricketFilterRaw,
            showFollowedOnly: showFollowedOnly,
            onlyShowSelectedInterests: onlyShowSelectedInterests,
            selectionIdentity: personalizationSelectionIdentity
        )
    }

    private var discovery: HomeSportsDiscovery {
        discoveryProjection ?? HomeSportsDiscovery(events: [], now: discoveryDate)
    }

    private var discoveryProjection: HomeSportsDiscovery? { projectionCoordinator.packet?.base.discovery }
    private var discoveryProjectionRevision: Int { projectionCoordinator.packet?.base.revision ?? 0 }
    private var rowPresentations: [String: HomeDiscoveryRow.Presentation] { projectionCoordinator.packet?.base.presentations ?? [:] }
    private var projectedFootballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab] { projectionCoordinator.packet?.base.footballLeagues ?? [:] }
    private var projectedPersonalizationSelection: SportsPersonalizationPolicy.PreparedSelection? { projectionCoordinator.packet?.base.selection }
    private var personalizationFactsCache: HomePersonalizationFactsCache? { projectionCoordinator.packet?.base.factsCache }
    private var discoveryRankingSnapshot: HomeDiscoveryRankingSnapshot? {
        // The cached Home presentation order includes cricket intervals. The
        // existing multi-select fallback keeps its legacy candidate ordering.
        isMultiSelectMode ? nil : projectionCoordinator.packet?.scope.ranking
    }
    private var homeSportActivities: [HomeSportsDiscovery.SportActivity]? { projectionCoordinator.packet?.scope.homeActivities }
    private var fullLineupSportActivities: [HomeSportsDiscovery.SportActivity]? { projectionCoordinator.packet?.scope.lineupActivities }

    private var personalizationFactsKey: HomePersonalizationFactsKey {
        HomePersonalizationFactsKey(
            contentRevision: matchListViewModel?.contentRevision ?? -1,
            scoreRevisionMilliseconds: Int64((liveScoreService.lastRefresh?.timeIntervalSince1970 ?? 0) * 1_000),
            selectionIdentity: personalizationSelectionIdentity
        )
    }

    private func rebuildCatalogProjection() async {
        let requestKey = catalogProjectionKey
        let input = HomeProjectionInput(
            key: requestKey,
            selection: preparedPersonalizationSelection,
            providerEvents: matchListViewModel?.browseCatalog ?? CricketChannelCatalog.merging(into: []),
            terminalEvents: SportsFixtureCatalog.terminalEvents(from: matchListViewModel?.sportsFixtureSnapshot)
                + CricketFixtureCatalog.terminalEvents(from: matchListViewModel?.cricketFixtureSnapshot),
            officialChampionsLeague: AnalyticalDataEngine.officialScheduleEvents(
                from: liveScoreService.analysisMatches, competition: .championsLeague)
        )
        await projectionCoordinator.rebuild(input: input, status: { event in
            guard event.normalizedCategory == "football",
                  let match = liveScoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) else { return nil }
            // A schedule-only "timed" row is not proof of a delayed start.
            if match.status.isUpcoming, (event.kickoffDate ?? .distantFuture) <= requestKey.clockDate { return nil }
            return liveScoreService.currentStatus(for: match, at: requestKey.clockDate)
        }, facts: { item, selection in
            HomePersonalizationFacts(
                isFollowed: follows(item.event, selection: selection),
                isMajorLeague: SportsTeamIdentity.sharedMajorLeague(
                    home: item.event.homeName, away: item.event.awayName, category: item.sport
                ) != nil,
                isCPL: item.event.isCPLFixture
            )
        }, footballLeague: resolveFootballLeagueTab(for:), presentation: {
            HomeDiscoveryRow.Presentation(item: $0, scoreService: liveScoreService)
        }, isCurrent: { catalogProjectionKey == requestKey }, deriveScope: { base in
            projectionScope(for: base, personalization: .init(selection: base.selection, facts: base.factsCache.facts))
        })
    }

    private func rebuildSportActivityProjection() {
        projectionCoordinator.refreshScope { base in
            projectionScope(for: base, personalization: discoveryPersonalizationContext)
        }
    }

    private func projectionScope(for base: HomeProjectionBase,
        personalization: HomePersonalizationContext) -> HomeProjectionScope {
        .init(ranking: rebuildDiscoveryRanking(in: base.discovery, revision: base.revision,
                personalization: personalization, footballLeagues: base.footballLeagues),
            homeActivities: sportActivities(in: base.discovery, applyingHomeInterests: true,
                personalization: personalization, footballLeagues: base.footballLeagues),
            lineupActivities: sportActivities(in: base.discovery, applyingHomeInterests: false,
                personalization: personalization, footballLeagues: base.footballLeagues))
    }

    private var discoveryRankingKey: HomeDiscoveryRankingKey {
        .init(projectionRevision: discoveryProjectionRevision, scope: homeSportActivityProjectionKey)
    }

    private func rebuildDiscoveryRanking(in schedule: HomeSportsDiscovery, revision: Int,
        personalization: HomePersonalizationContext,
        footballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab]) -> HomeDiscoveryRankingSnapshot {
        let equalizeInterests = isHomeInterestRestrictionActive && !showFollowedOnly
        let home = prioritizedDiscoveryItems(
            scopedItems(in: schedule, applyingHomeInterests: true, personalization: personalization,
                        footballLeagues: footballLeagues),
            equalizeSelectedInterests: equalizeInterests, personalization: personalization,
            footballLeagues: footballLeagues)
        let lineup = prioritizedDiscoveryItems(
            scopedItems(in: schedule, applyingHomeInterests: false, personalization: personalization,
                        footballLeagues: footballLeagues),
            personalization: personalization, footballLeagues: footballLeagues)
        return .init(key: .init(projectionRevision: revision, scope: homeSportActivityProjectionKey),
                     home: home, lineup: lineup)
    }

    private var showsFootballScores: Bool {
        selectedSportTab == Self.footballCategoryID || selectedSportTab == HomeSportsDiscovery.allSports
    }

    private func footballLeagueTab(
        for event: AnalyticalDataEngine.EventReference
    ) -> AnalyticalDataEngine.FootballLeagueTab {
        projectedFootballLeagues[event.id] ?? resolveFootballLeagueTab(for: event)
    }

    private func resolveFootballLeagueTab(
        for event: AnalyticalDataEngine.EventReference
    ) -> AnalyticalDataEngine.FootballLeagueTab {
        let officialMatch = liveScoreService.findMatch(
            home: event.homeName,
            away: event.awayName,
            near: event.kickoffDate,
            maximumKickoffDelta: 6 * 3_600
        )
        return AnalyticalDataEngine.footballLeagueTab(for: event, officialMatch: officialMatch)
    }

    private func scopedItems(
        in schedule: HomeSportsDiscovery,
        applyingHomeInterests: Bool,
        personalization: HomePersonalizationContext,
        footballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab]? = nil
    ) -> [HomeSportsDiscovery.Item] {
        schedule.scopedItems(sport: selectedSportTab).filter { item in
            if showsFootballLeagueTabs, selectedFootballLeague != .all,
               (footballLeagues?[item.id] ?? footballLeagueTab(for: item.event)) != selectedFootballLeague { return false }
            if selectedSportTab == "cricket", !selectedCricketFilter.includes(item.event) { return false }
            if showFollowedOnly { return isEventFollowed(item.event, personalization: personalization) }
            guard applyingHomeInterests, isHomeInterestRestrictionActive else { return true }
            return isEventFollowed(item.event, personalization: personalization)
        }
    }

    /// Filter the cached discovery projection only when its scope changes. This
    /// stays outside SwiftUI body evaluation so ordinary redraws do not repeat
    /// broad catalog filtering or sorting merely to label the sport tiles.
    private func sportActivities(
        in schedule: HomeSportsDiscovery,
        applyingHomeInterests: Bool,
        personalization: HomePersonalizationContext,
        footballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab]
    ) -> [HomeSportsDiscovery.SportActivity] {
        let scope = HomeSportActivityScope(
            selectedSport: selectedSportTab,
            selectedFootballLeague: selectedFootballLeague,
            selectedCricketFilter: selectedCricketFilter,
            showFollowedOnly: showFollowedOnly,
            restrictToHomeInterests: applyingHomeInterests && isHomeInterestRestrictionActive
        )
        let items = schedule.items.filter { item in
            scope.includes(
                item,
                footballLeague: item.sport == Self.footballCategoryID ? footballLeagues[item.id] : nil,
                isFollowed: isEventFollowed(item.event, personalization: personalization)
            )
        }
        let channels = schedule.channels.filter { scope.includes(channel: $0) }
        return schedule.activities(scopedItems: items, scopedChannels: channels)
    }

    /// Urgency first, then an audience relevance tier. A followed major match
    /// leads; Premier League and Champions League remain ahead of an unrelated
    /// lower-interest listing. Explicitly followed events and CPL remain strong
    /// preferences without allowing the full live catalog to dominate Home.
    /// This is presentation ranking only; it never changes provider identity or
    /// claims that a catalog listing has decoded successfully.
    private func prioritizedDiscoveryItems(
        _ items: [HomeSportsDiscovery.Item],
        equalizeSelectedInterests: Bool = false,
        personalization: HomePersonalizationContext,
        footballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab]? = nil,
        preservingLegacyOrder: Bool = false
    ) -> [HomeSportsDiscovery.Item] {
        HomeSportsDiscovery.prioritized(items) {
            discoveryRank(for: $0, equalizeSelectedInterests: equalizeSelectedInterests,
                          personalization: personalization, footballLeagues: footballLeagues,
                          preservingLegacyOrder: preservingLegacyOrder)
        }
    }

    private func discoveryRank(
        for item: HomeSportsDiscovery.Item,
        equalizeSelectedInterests: Bool,
        personalization: HomePersonalizationContext,
        footballLeagues: [String: AnalyticalDataEngine.FootballLeagueTab]? = nil,
        preservingLegacyOrder: Bool = false
    ) -> HomeSportsDiscovery.PresentationPriority {
        let phase = CricketActivityPresentationPolicy.homePhaseRank(for: item, preservingLegacyOrder: preservingLegacyOrder)
        let followed = isEventFollowed(item.event, personalization: personalization)
        let relevance = equalizeSelectedInterests && followed
            ? 0
            : HomeSportsDiscovery.relevanceRank(
                sport: item.sport,
                footballLeague: item.sport == Self.footballCategoryID
                    ? (footballLeagues?[item.id] ?? footballLeagueTab(for: item.event)) : nil,
                isFollowed: followed,
                isCPL: personalization.facts[item.id]?.isCPL ?? item.event.isCPLFixture,
                isMajorLeague: personalization.facts[item.id]?.isMajorLeague ?? (SportsTeamIdentity.sharedMajorLeague(
                    home: item.event.homeName,
                    away: item.event.awayName,
                    category: item.sport
                ) != nil)
            )
        // Attached supported descriptors are a cheap presentation signal. The
        // full catalog broadcast selection remains tap-owned and bounded.
        return .init(
            phase: phase,
            relevance: relevance,
            available: HomeUpcomingPresentationPolicy.availabilityRank(
                equalizeSelectedInterests: equalizeSelectedInterests,
                isFollowed: followed,
                isUpcoming: item.phase == .upcoming
            )
        )
    }

    @ViewBuilder
    private func moreLiveButton(_ items: [HomeSportsDiscovery.Item]) -> some View {
        Button {
            showsMoreLive.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(FottyTheme.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("More events")
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(items.count == 1 ? "1 other event" : "\(items.count) other events")
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: showsMoreLive ? "chevron.up" : "chevron.down")
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusSM)
                    .strokeBorder(FottyTheme.borderStrong, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
        }
        .buttonStyle(FottyPressButtonStyle())
        .accessibilityLabel("More events, \(items.count) other events")
        .accessibilityValue(showsMoreLive ? "Expanded" : "Collapsed")
        .accessibilityHint(showsMoreLive ? "Hides additional events" : "Shows additional events and listed broadcasts")
        .accessibilityIdentifier("home-more-live")

    }

    private func discoveryFilters(
        _ schedule: HomeSportsDiscovery,
        includesHomePersonalization: Bool
    ) -> some View {
        let scopedActivities = includesHomePersonalization ? homeSportActivities : fullLineupSportActivities
        return VStack(alignment: .leading, spacing: 4) {
            SportActivityGrid(
                discovery: schedule,
                selectedSport: includesHomePersonalization ? homeSportBinding : $selectedSportTab,
                activities: scopedActivities,
                onMore: {
                    allSportsAppliesHomeInterests = includesHomePersonalization
                    presentModal { showsAllSports = true }
                },
                showsMoreLink: !includesHomePersonalization
            )
            if showsFootballLeagueTabs || selectedSportTab == "cricket" {
                CompactHomeFilterBar(
                    categories: [], selectedCategory: includesHomePersonalization ? homeSportBinding : $selectedSportTab,
                    leagues: matchListViewModel.map(footballLeagueTabs(for:)) ?? [],
                    selectedLeague: includesHomePersonalization ? homeLeagueBinding : footballLeagueBinding,
                    showsSportMenu: false, showsLeagueMenu: showsFootballLeagueTabs,
                    selectedCricketFilter: includesHomePersonalization ? homeCricketBinding : cricketFilterBinding
                )
            }
            if includesHomePersonalization {
                homeInterestControl
            }
        }
    }

    private func browseSportsSection(_ schedule: HomeSportsDiscovery, compact: Bool = false) -> some View {
        let baseActivities = homeSportActivities ?? schedule.activities
        let scopedActivities = baseActivities.allSatisfy(\.hasNearbyActivity) ? baseActivities
            : HomeSportsDiscovery.SportActivity.addingLaterFixtures(baseActivities,
                from: matchListViewModel?.searchSchedule(at: schedule.now) ?? [], at: schedule.now)
        let allSportsVisible = SportActivityGrid.showsAllSports(
            expanded: false,
            regularWidth: horizontalSizeClass == .regular,
            isPad: UIDevice.current.userInterfaceIdiom == .pad
        )
        let visibleCount = HomeSportsDiscovery.visibleActivities(
            scopedActivities,
            selectedSport: selectedSportTab
        ).count
        return VStack(alignment: .leading, spacing: 6) {
            CatalogAdaptiveHeading {
                Text("Browse sports")
                    .font(FottyTheme.typeSectionTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            } actions: {
                if !allSportsVisible, scopedActivities.count > visibleCount {
                    Button("More") {
                        allSportsAppliesHomeInterests = true
                        presentModal { showsAllSports = true }
                    }
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                        .buttonStyle(FottyPressButtonStyle())
                        .accessibilityHint("Shows every sport with listed activity")
                        .accessibilityIdentifier("home-more-sports")
                }
            }

            SportActivityGrid(
                discovery: schedule,
                selectedSport: homeSportBinding,
                activities: scopedActivities,
                onMore: {
                    allSportsAppliesHomeInterests = true
                    presentModal { showsAllSports = true }
                },
                showsMoreLink: false,
                compactPresentation: compact
            )

            if showsFootballLeagueTabs || selectedSportTab == "cricket" {
                CompactHomeFilterBar(
                    categories: [], selectedCategory: homeSportBinding,
                    leagues: matchListViewModel.map(footballLeagueTabs(for:)) ?? [],
                    selectedLeague: homeLeagueBinding,
                    showsSportMenu: false, showsLeagueMenu: showsFootballLeagueTabs,
                    selectedCricketFilter: homeCricketBinding
                )
            }

        }
    }

    @ScaledMetric(relativeTo: .subheadline) private var homeControlTextSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title2) private var homeWordmarkSize: CGFloat = 28

    private var homeInterestControl: some View {
        NavigationLink {
            SettingsManageLeaguesView(previewEvents: matchListViewModel?.playbackCatalog ?? [])
        } label: {
            HStack(spacing: 10) {
                Text(selectedInterestCount == 0 ? "Personalize Home"
                    : (isHomeInterestRestrictionActive ? "Only your interests" : "Home interests"))
                    .font(.system(size: homeControlTextSize))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("Edit")
                    .font(.system(size: homeControlTextSize, weight: .medium))
                    .foregroundStyle(FottyTheme.accentText)
                    .accessibilityIdentifier("dashboard-home-interests-edit")
                Image(systemName: "chevron.right")
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
        }
        .buttonStyle(FottyPressButtonStyle())
        .accessibilityLabel("Home interests")
        .accessibilityValue(homeInterestControlSubtitle)
        .accessibilityHint("Choose sports, competitions and teams, or change whether Home shows only those interests")
        .accessibilityIdentifier("home-personalization")
    }

    private var homeInterestControlSubtitle: String {
        guard selectedInterestCount > 0 else { return "Choose sports, competitions and teams" }
        let selection = selectedInterestCount == 1 ? "1 selection" : "\(selectedInterestCount) selections"
        return isHomeInterestRestrictionActive
            ? "\(selection) · showing only yours"
            : "\(selection) · showing all sports"
    }

    private enum HomeEntry: Identifiable {
        enum Heading: Hashable { case live, upcoming, later, awaitingStatus, todaySoFar }
        enum ID: Hashable {
            case heading(Heading), overview, onAir, spotlight(String), club(String), followClub, moreLive, browseSports, empty, selectionEmpty, fixture(HomeSportsDiscovery.DisplayRow.ID)
        }
        case heading(Heading, String)
        case overview(HomeSportsDiscovery.HomeSections, emptyMessage: String, onAir: [HomeOnAirPolicy.Entry])
        case onAir([HomeOnAirPolicy.Entry])
        case spotlight(HomeSportsDiscovery.Item)
        case club(HomeSportsDiscovery.Item)
        case followClub
        case moreLive([HomeSportsDiscovery.Item])
        case browseSports
        case empty(String, offersAllSports: Bool)
        case selectionEmpty
        case fixture(HomeSportsDiscovery.DisplayRow, elevated: Bool)
        var id: ID {
            switch self {
            case .heading(let kind, _): return .heading(kind)
            case .overview: return .overview
            case .onAir: return .onAir
            case .spotlight(let item): return .spotlight(item.id)
            case .club(let item): return .club(item.id)
            case .followClub: return .followClub
            case .moreLive: return .moreLive
            case .browseSports: return .browseSports
            case .empty: return .empty
            case .selectionEmpty: return .selectionEmpty
            case .fixture(let row, _): return .fixture(row.id)
            }
        }
    }

    /// One identified, fixed-count child per lazy-stack entry. Independent
    /// conditional ForEach groups change their child counts when the first live
    /// section appears. Flatten headers and rows together before SwiftUI
    /// reconciles them; do not reset the scroll container to force a refresh.
    private func homeEntries(sections: HomeSportsDiscovery.HomeSections, onAir: [HomeOnAirPolicy.Entry],
                             later: (title: String, items: [HomeSportsDiscovery.Item]),
                             items: [HomeSportsDiscovery.Item], personalized: Bool,
                             hasChannels: Bool, needsClub: Bool, selectionIsEmpty: Bool, columns: Int) -> [HomeEntry] {
        var entries: [HomeEntry] = []
        func appendRows(_ items: [HomeSportsDiscovery.Item], section: String, elevated: Bool) {
            entries += HomeSportsDiscovery.displayRows(items, columns: columns, section: section)
                .map { .fixture($0, elevated: elevated) }
        }
        func appendPausedToday() {
            guard !sections.pausedToday.isEmpty else { return }
            entries.append(.heading(.todaySoFar, "Today so far"))
            appendRows(sections.pausedToday, section: "today-so-far", elevated: false)
        }
        func appendAwaitingStatus() {
            guard !sections.awaitingStatus.isEmpty else { return }
            entries.append(.heading(.awaitingStatus, "Awaiting match update"))
            appendRows(sections.awaitingStatus, section: "awaiting-status", elevated: false)
        }
        // Only the bounded featured/upcoming projection enters the overview.
        // Expanded current events and later fixtures stay independently lazy.
        if columns > 1, !sections.featuredLive.isEmpty || !sections.pausedToday.isEmpty || !onAir.isEmpty {
            let activeSport = selectedSportTab == HomeSportsDiscovery.allSports
                ? nil : AnalyticalDataEngine.categoryDisplayName(for: selectedSportTab)
            entries.append(.overview(sections, emptyMessage: HomeUpcomingPresentationPolicy.emptyMessage(
                sport: activeSport, personalized: personalized, hasCurrentEvents: true), onAir: onAir))
            if needsClub { entries.append(.followClub) }
            if !sections.moreLive.isEmpty {
                entries.append(.moreLive(sections.moreLive))
                if showsMoreLive { appendRows(sections.moreLive, section: "more-live", elevated: false) }
            }
            appendAwaitingStatus()
            if !later.items.isEmpty {
                entries.append(.heading(.later, later.title))
                appendRows(later.items, section: "later", elevated: false)
            }
            return entries
        }
        if let spotlight = sections.spotlight {
            entries.append(.spotlight(spotlight))
            if let club = sections.clubBelowSpotlight { entries.append(.club(club)) }
            if !onAir.isEmpty { entries.append(.onAir(onAir)) }
            if needsClub { entries.append(.followClub) }
            if !sections.remainingFeatured.isEmpty { entries.append(.heading(.live, CricketActivityPresentationPolicy.sectionTitle(for: Array(sections.remainingFeatured)))) }
            appendRows(Array(sections.remainingFeatured), section: "live", elevated: false)
        } else if !onAir.isEmpty {
            // Nothing watchable is live: channels that open now lead Home.
            entries.append(.onAir(onAir))
        }
        if sections.spotlight == nil, !sections.remainingFeatured.isEmpty {
            // Live without a Watch action: listed, never the Live now card.
            entries.append(.heading(.live, "On now"))
            appendRows(sections.remainingFeatured, section: "live", elevated: false)
        }
        if sections.spotlight == nil, let club = sections.nextClub { entries.append(.club(club)) }
        appendPausedToday()
        if !sections.moreLive.isEmpty {
            entries.append(.moreLive(sections.moreLive))
            if showsMoreLive { appendRows(sections.moreLive, section: "more-live", elevated: false) }
        }
        appendAwaitingStatus()
        if sections.spotlight == nil && needsClub { entries.append(.followClub) }
        if selectionIsEmpty {
            // Explain this exact empty selection before offering other sports;
            // an empty Up Next/See all heading has no matches to lead into.
            entries.append(.selectionEmpty)
        } else if !sections.upcoming.isEmpty || sections.nextClub == nil {
            entries.append(.heading(.upcoming, "Up Next"))
            if !sections.upcoming.isEmpty {
                appendRows(sections.upcoming, section: "upcoming", elevated: true)
            } else if !items.isEmpty {
                let activeSport = selectedSportTab == HomeSportsDiscovery.allSports
                    ? nil
                    : AnalyticalDataEngine.categoryDisplayName(for: selectedSportTab)
                let message = HomeUpcomingPresentationPolicy.emptyMessage(
                    sport: activeSport, personalized: personalized,
                    hasCurrentEvents: !sections.featuredLive.isEmpty)
                entries.append(.empty(message, offersAllSports: activeSport != nil))
            } else if !isHomeInterestRestrictionActive, selectedSportTab == HomeSportsDiscovery.allSports, hasChannels {
                entries.append(.empty(
                    "No matches are scheduled right now. Cricket channels are still available.",
                    offersAllSports: false
                ))
            }
        }
        entries.append(.browseSports)
        if !later.items.isEmpty {
            entries.append(.heading(.later, later.title))
            appendRows(later.items, section: "later", elevated: false)
        }
        return entries
    }

    @ViewBuilder
    private func homeEntry(_ entry: HomeEntry) -> some View {
        switch entry {
        case .heading(let kind, let title):
            homeSectionHeading(kind, title: title)
        case .overview(let sections, let emptyMessage, let onAir):
            wideHomeOverview(sections, emptyMessage: emptyMessage, onAir: onAir)
        case .onAir(let onAir):
            onAirSection(onAir, columns: 2)
        case .club(let item): clubNextRow(item)
        case .followClub:
            Button { presentModal { showsClubPicker = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.circle").font(.title2).foregroundStyle(FottyTheme.accentText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your club. Front and centre.").font(.headline).foregroundStyle(FottyTheme.textPrimary)
                        Text("Follow a club to put its matches here.").font(.subheadline).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(FottyTheme.surface, in: .rect(cornerRadius: FottyTheme.radiusLG))
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusLG))
            .accessibilityLabel("Follow a club")
            .accessibilityIdentifier("home-follow-club")
        case .spotlight(let item):
            liveSpotlight(item)
        case .moreLive(let items): moreLiveButton(items)
        case .browseSports:
            browseSportsSection(discovery)
        case .selectionEmpty:
            emptyState(applyingHomeInterests: true)
        case .empty(let title, let offersAllSports):
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if offersAllSports {
                    Button("Show all sports") {
                        selectedSportTab = HomeSportsDiscovery.allSports
                        selectedFootballLeagueRaw = AnalyticalDataEngine.FootballLeagueTab.all.rawValue
                        selectedCricketFilterRaw = CricketCatalogFilter.all.rawValue
                        requestHomeResults()
                    }
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(minHeight: 44)
                    .buttonStyle(FottyPressButtonStyle())
                    .accessibilityHint("Removes the active sport filter from Home")
                    .accessibilityIdentifier("home-show-all-sports")
                }
            }
        case .fixture(let row, let elevated): discoveryRow(row, elevated: elevated)
        }
    }

    private func homeSectionHeading(_ kind: HomeEntry.Heading, title: String) -> some View {
        CatalogAdaptiveHeading {
            Text(title)
                .font(FottyTheme.typeSectionTitle)
                .foregroundStyle(FottyTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(kind == .live ? "home-live-heading" : "home-discovery-heading")
        } actions: {
            if kind == .upcoming {
                Button { showsFullLineup = true } label: {
                    Text("See all")
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle())
                .accessibilityHint("Opens the full lineup on Home")
                .accessibilityIdentifier("home-see-all")
            }
        }
    }

    private func liveSpotlight(_ item: HomeSportsDiscovery.Item) -> some View {
        HomeLiveSpotlight(
            item: item,
            presentation: rowPresentations[item.id] ?? HomeDiscoveryRow.Presentation(item: item),
            now: HomeSportsDiscovery.automatedClockStart == nil ? nil : discoveryDate,
            isSaved: myMatchdayStore.contains(event: item.event),
            onOpen: { openEvent(item.event) },
            onSave: { toggleSavedMatch(item.event) },
            alternateActionTitle: cplChannelActionTitle(item.event),
            onDetails: { presentModal { selectedCatalogEvent = item.event } },
            onCheckStreams: rowSourceCheckAction(for: item.event)
        )
    }

    private func clubNextRow(_ item: HomeSportsDiscovery.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Your club · Up next").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    clubKickoff(item)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your club · Up next").font(.subheadline.weight(.semibold))
                    clubKickoff(item)
                }
            }
            overviewMatchGroup([item])
        }
        .accessibilityIdentifier("home-next-club")
    }

    @ViewBuilder
    private func clubKickoff(_ item: HomeSportsDiscovery.Item) -> some View {
        if let date = item.event.kickoffDate {
            Text(date.arenaKickoffDetailLine()).font(.subheadline)
                .foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: true)
        }
    }

    private func onAirSection(_ entries: [HomeOnAirPolicy.Entry], columns: Int) -> some View {
        HomeOnAirSection(entries: entries, columns: columns,
            pendingEventID: !isMultiSelectMode && !viewing.isTwo ? viewing.pendingSingleEvent?.id : nil) { event in
            SportsTVWatchPolicy.watch(event, using: viewing,
                currentCatalog: { MatchListViewModel.shared.playbackAdmissionCatalog })
        }
    }

    private func wideHomeOverview(_ sections: HomeSportsDiscovery.HomeSections, emptyMessage: String,
                                  onAir: [HomeOnAirPolicy.Entry]) -> some View {
        HomeOverviewLayout {
            VStack(alignment: .leading, spacing: 16) {
                if let item = sections.spotlight { liveSpotlight(item) }
                if let club = sections.clubBelowSpotlight { clubNextRow(club) }
                if !onAir.isEmpty { onAirSection(onAir, columns: 3) }
                if !sections.remainingFeatured.isEmpty {
                    homeSectionHeading(.live, title: sections.spotlight == nil ? "On now"
                        : CricketActivityPresentationPolicy.sectionTitle(for: sections.remainingFeatured))
                    overviewMatchGroup(sections.remainingFeatured)
                }
                if !sections.pausedToday.isEmpty {
                    homeSectionHeading(.todaySoFar, title: "Today so far")
                    overviewMatchGroup(sections.pausedToday)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                if !sections.upcoming.isEmpty || sections.nextClub == nil {
                VStack(alignment: .leading, spacing: 8) {
                    homeSectionHeading(.upcoming, title: "Up next")
                    if sections.upcoming.isEmpty {
                        Text(emptyMessage)
                            .font(FottyTheme.typeBody)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if selectedSportTab != HomeSportsDiscovery.allSports {
                            Button("Show all sports") {
                                selectedSportTab = HomeSportsDiscovery.allSports
                                selectedFootballLeagueRaw = AnalyticalDataEngine.FootballLeagueTab.all.rawValue
                                selectedCricketFilterRaw = CricketCatalogFilter.all.rawValue
                                requestHomeResults()
                            }
                            .font(FottyTheme.typeAction)
                            .foregroundStyle(FottyTheme.accentText)
                            .frame(minHeight: 44)
                            .buttonStyle(FottyPressButtonStyle())
                            .accessibilityIdentifier("home-show-all-sports")
                        }
                    } else {
                        overviewMatchGroup(sections.upcoming)
                    }
                }
                }
                browseSportsSection(discovery, compact: true)
            }
        }
        .accessibilityIdentifier("home-wide-overview")
    }

    /// This group receives only Home's small featured/upcoming limits. The
    /// unbounded catalog deliberately continues through identified lazy rows.
    private func overviewMatchGroup(_ items: [HomeSportsDiscovery.Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Divider().overlay(FottyTheme.borderStrong)
                        .accessibilityHidden(true)
                }
                homeScheduleRow(item)
            }
        }
        .padding(.horizontal, 12)
        .background(FottyTheme.surface, in: RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
    }

    private func homeScheduleRow(_ item: HomeSportsDiscovery.Item) -> some View {
        HomeScheduleRow(
            item: item,
            presentation: rowPresentations[item.id] ?? HomeDiscoveryRow.Presentation(item: item),
            now: HomeSportsDiscovery.automatedClockStart == nil ? nil : discoveryDate,
            isSaved: myMatchdayStore.contains(event: item.event),
            onOpen: { openEvent(item.event) },
            onSave: { toggleSavedMatch(item.event) },
            alternateActionTitle: cplChannelActionTitle(item.event),
            onDetails: { presentModal { selectedCatalogEvent = item.event } },
            onCheckStreams: rowSourceCheckAction(for: item.event)
        )
    }

    private func discoveryRow(_ row: HomeSportsDiscovery.DisplayRow, elevated: Bool) -> some View {
        let index = row.index
        let wide = row.id.columns > 1
        return HStack(alignment: .top, spacing: 16) {
            ForEach(row.items) { item in
            VStack(spacing: 0) {
                if index > 0 && !wide {
                    Divider().overlay(FottyTheme.borderStrong)
                        .accessibilityHidden(true)
                }
                homeScheduleRow(item)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(FottyTheme.surface)
            .clipShape(HomeMatchGroupShape(isFirst: wide || index == 0,
                                           isLast: wide || index == row.total - 1))
            .overlay {
                if wide {
                    RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous)
                        .strokeBorder(FottyTheme.border, lineWidth: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            }
            if wide && row.items.count == 1 { Color.clear.frame(maxWidth: .infinity, minHeight: 0, maxHeight: 0).accessibilityHidden(true) }
          }
            // Join only sibling compact rows into their section surface. Their
            // divider remains visible; separate sections retain the full rhythm.
            .padding(.top, wide || index == 0 ? 0 : -FottyTheme.spacingMD)
    }

    private var fullLineup: some View {
        let schedule = discovery
        let personalization = discoveryPersonalizationContext
        let items = discoveryRankingSnapshot?.items(matching: discoveryRankingKey, home: false) ?? prioritizedDiscoveryItems(
            scopedItems(in: schedule, applyingHomeInterests: false, personalization: personalization),
            personalization: personalization, preservingLegacyOrder: isMultiSelectMode
        )
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                discoveryFilters(schedule, includesHomePersonalization: false)
                if selectedInterestCount > 0 {
                    Toggle("Following only", isOn: $showFollowedOnly)
                        .font(FottyTheme.typeBody)
                        .tint(FottyTheme.accentText)
                }
                if items.isEmpty && channelEvents(applyingHomeInterests: false).isEmpty {
                    emptyState(applyingHomeInterests: false)
                }
                ForEach(fullLineupEntries(from: items)) { entry in
                    switch entry {
                    case .heading(_, let title):
                        Text(title)
                            .font(FottyTheme.typeSectionTitle)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    case .fixtures(_, let rowItems, let startsSection):
                      HStack(alignment: .top, spacing: 16) {
                       ForEach(rowItems) { item in
                        VStack(spacing: 0) {
                            if !startsSection && !usesWideLayout {
                                Divider().overlay(FottyTheme.border)
                            }
                            HomeDiscoveryRow(
                                item: item,
                                presentation: rowPresentations[item.id],
                                isSaved: myMatchdayStore.contains(event: item.event),
                                onOpen: { openEvent(item.event) },
                                onSave: { toggleSavedMatch(item.event) },
                                alternateActionTitle: cplChannelActionTitle(item.event),
                                onDetails: { presentModal { selectedCatalogEvent = item.event } },
                                onCheckStreams: rowSourceCheckAction(for: item.event)
                            )
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(FottyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
                        .overlay {
                            RoundedRectangle(cornerRadius: FottyTheme.radiusSM)
                                .strokeBorder(FottyTheme.borderStrong, lineWidth: 0.5)
                        }
                       }
                       if usesWideLayout && rowItems.count == 1 { Color.clear.frame(maxWidth: .infinity, minHeight: 0, maxHeight: 0).accessibilityHidden(true) }
                      }
                      .padding(.top, usesWideLayout || startsSection ? 0 : -FottyTheme.spacingMD)
                    }
                }
                if selectedSportTab == "cricket" || selectedSportTab == HomeSportsDiscovery.allSports {
                    cricketDiscovery(applyingHomeInterests: false)
                }
            }
            .padding(FottyTheme.spacingMD)
            .frame(maxWidth: .infinity)
        }
        .background(FottyTheme.background)
        .navigationTitle("Full lineup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("home-full-lineup")
        .refreshable {
            guard !AppRuntime.isAutomatedTesting else { return }
            await matchListViewModel?.refresh()
            discoveryDate = Date()
        }
    }

    private enum FullLineupEntry: Identifiable {
        case heading(id: String, title: String)
        case fixtures(id: String, items: [HomeSportsDiscovery.Item], startsSection: Bool)

        var id: String {
            switch self {
            case .heading(let id, _), .fixtures(let id, _, _): return id
            }
        }
    }

    /// One stable entry per lazy-stack child. Headers and fixtures are flattened
    /// before rendering so SwiftUI never has to discover a dynamic child count
    /// inside a date-section row while the user is scrolling.
    private func fullLineupEntries(from items: [HomeSportsDiscovery.Item]) -> [FullLineupEntry] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return FixtureDateGrouper.sections(from: items.map(\.event)).flatMap { section -> [FullLineupEntry] in
            let fixtures = section.events.compactMap { byID[$0.id] }
            guard !fixtures.isEmpty else { return [] }
            return [.heading(id: "heading-\(section.id)", title: section.title)]
                + FottyLayoutPolicy.rows(fixtures, columns: usesWideLayout ? 2 : 1).enumerated().map { index, row in
                    .fixtures(id: "fixture-\(section.id)-\(row.id)", items: row.items, startsSection: index == 0)
                }
        }
    }

    private var cinemaHomeMasthead: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            Text(FottyBrand.shortName)
                .font(.system(size: homeWordmarkSize, weight: .bold))
                .tracking(-1.0)
                .foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            cinemaHomeActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cinemaHomeActions: some View {
        HStack(spacing: 8) {
            Button {
                presentModal { showsSearch = true }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.fottyScaled(size: 15, weight: .bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(FottyTheme.borderStrong, lineWidth: 0.5) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
            .accessibilityLabel("Search sports")
            .accessibilityHint("Searches every sport, team, league, match, and channel in the Home lineup")
            .accessibilityIdentifier("home-search")

            if let openSettings {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.fottyScaled(size: 15, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(FottyTheme.borderStrong, lineWidth: 0.5) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home-settings")
            }

            if canOfferMultiView {
                Button(action: beginMultiSelectMode) {
                    Label("Watch two", systemImage: "rectangle.split.2x1")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 32)
                }
                // Let the native control own its adaptive fill, contrast and
                // pressed state instead of a faint custom material outline.
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(FottyTheme.textPrimary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Watch two matches")
                .accessibilityHint("Select two matches to watch together")
                .accessibilityIdentifier("home-watch-two")
                .disabled(isFindingAnyStream)
            }
        }
    }

    private static let upNextDateFormatterLock = NSLock()
    private static let upNextDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var multiSelectChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        multiSelectTitleBlock
                        Spacer(minLength: 4)
                        multiSelectCancelButton
                    }
                    multiSelectStartButton
                }
            } else {
                HStack(spacing: 10) {
                    multiSelectCancelButton
                    multiSelectTitleBlock
                    Spacer(minLength: 4)
                    multiSelectStartButton
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index < selectedMultiEventIDs.count ? FottyTheme.accent : FottyTheme.borderStrong)
                        .frame(maxWidth: .infinity)
                        .frame(height: 3)
                }
            }
        }
        .buttonStyle(FottyPressButtonStyle())
        .padding(.horizontal, FottyTheme.bentoInset)
        .padding(.vertical, 8)
        .background(FottyTheme.surfaceElevated.shadow(color: .black.opacity(0.18), radius: 10, y: 4))
    }

    private var multiSelectCancelButton: some View {
        Button(action: cancelMultiSelectMode) {
            Label("Cancel", systemImage: "xmark")
                .font(FottyTheme.typeAction)
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("multiview-cancel-selection")
    }

    private var multiSelectTitleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Choose two matches")
                .font(.fottyScaled(size: 15, weight: .bold))
                .foregroundStyle(FottyTheme.textPrimary)
            multiSelectCount
        }
    }

    private var multiSelectStartButton: some View {
        Button(action: watchSelectedInMultiView) {
            Label("Start", systemImage: "play.fill")
                .font(FottyTheme.typeAction)
                .foregroundStyle(selectedMultiEventIDs.count == 2 ? FottyTheme.textOnAccent : FottyTheme.textTertiary)
                .padding(.horizontal, 14)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                .background(
                    Capsule().fill(selectedMultiEventIDs.count == 2 ? FottyTheme.accent : FottyTheme.surfaceSubtle)
                )
                .contentShape(Capsule())
        }
        .disabled(selectedMultiEventIDs.count != 2 || isFindingAnyStream)
        .accessibilityLabel("Start two-match view")
        .accessibilityHint("Opens both selected broadcasts together")
        .accessibilityIdentifier("multiview-start")
    }

    private var multiSelectCount: some View {
        Text("\(selectedMultiEventIDs.count) of 2 selected")
            .font(FottyTheme.typeMeta)
            .foregroundStyle(FottyTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func homeMatchList(
        events: [AnalyticalDataEngine.EventReference],
        usesMultiColumnGrid: Bool = UIDevice.current.userInterfaceIdiom == .pad
    ) -> some View {
        DashboardMatchList(
            title: isMultiSelectMode ? "Ready to watch" : "Match schedule",
            events: events,
            showFollowedOnly: $showFollowedOnly,
            hasFollowedTeams: !followedTeams.isEmpty,
            isMultiSelectMode: isMultiSelectMode,
            selectedMultiEventIDs: $selectedMultiEventIDs,
            onEventTap: { event in
                guard !isMultiSelectMode else {
                    toggleMultiSelection(for: event)
                    return
                }
                openEvent(event)
            },
            onInfoTap: { match in presentModal { selectedHighlightsMatch = match } },
            onAppearEvent: { _ in },
            canWatchEvent: canOpenBroadcast(_:),
            alternateActionTitle: cplChannelActionTitle(_:),
            isSavedEvent: { myMatchdayStore.contains(event: $0) },
            onToggleSaved: toggleSavedMatch,
            usesMultiColumnGrid: usesMultiColumnGrid
        )
    }

    private func liveCard(
        for event: AnalyticalDataEngine.EventReference
    ) -> some View {
        LiveEventCard(
            event: event,
            onInfoTap: { match in presentModal { selectedHighlightsMatch = match } },
            onWatchTap: canOpenBroadcast(event) ? { openEvent(event) } : nil,
            alternateActionTitle: cplChannelActionTitle(event),
            onDetailsTap: { presentModal { selectedCatalogEvent = event } },
            onCheckStreams: rowSourceCheckAction(for: event),
            isSaved: myMatchdayStore.contains(event: event),
            onSaveTap: { toggleSavedMatch(event) }
        )
    }

    private func toggleSavedMatch(_ event: AnalyticalDataEngine.EventReference) {
        if let message = mutateSavedMatch(event).errorMessage {
            savedMatchError = message
        }
    }

    private func mutateSavedMatch(_ event: AnalyticalDataEngine.EventReference) -> MyMatchdayStore.MutationResult {
        HapticManager.impact(.light)
        return withAnimation(FottyTheme.springSnappy) { myMatchdayStore.toggle(event) }
    }

    private func queueSearchSelection(
        _ event: AnalyticalDataEngine.EventReference,
        destination: PendingSearchSelection.Destination
    ) {
        pendingSearchSelection = PendingSearchSelection(event: event, destination: destination)
        showsSearch = false
    }

    private func completePendingSearchSelection() {
        guard let selection = pendingSearchSelection else { return }
        pendingSearchSelection = nil
        switch selection.destination {
        case .open:
            openEvent(selection.event)
        case .details:
            presentModal { selectedCatalogEvent = selection.event }
        case .checkStreams:
            checkSources(for: selection.event)
        }
    }

    private func rowSourceCheckAction(for event: EventReference) -> (() -> Void)? {
        guard !isMultiSelectMode, !viewing.isTwo else { return nil }
        // "Today so far" rows (stumps, breaks) carry no action or lookup status.
        if CricketActivityPresentationPolicy.activity(for: event, at: discoveryDate)?.suppressesLiveBadge == true { return nil }
        return { checkSources(for: event) }
    }

    private func optionalSourceCheckAction(for event: EventReference) -> (() -> Void)? {
        guard isActive, scenePhase == .active, !isFindingAnyStream, !viewing.isTwo else { return nil }
        return {
            guard isActive, scenePhase == .active, !isFindingAnyStream, !viewing.isTwo else { return }
            pendingDetailsWatch = nil
            pendingDetailsSourceCheck = event
            selectedCatalogEvent = nil
        }
    }

    private func completePendingDetailsAction() {
        if let event = pendingDetailsSourceCheck {
            pendingDetailsSourceCheck = nil
            pendingDetailsWatch = nil
            checkSources(for: event)
            return
        }
        guard let event = pendingDetailsWatch else { return }
        pendingDetailsWatch = nil
        guard isActive else { return }
        // Dismiss the details sheet first. Ordinary Watch rechecks the current
        // listing before starting an attempt, rather than trusting a stale row.
        openEvent(event)
    }

    private func checkSources(for event: EventReference) {
        guard isActive, scenePhase == .active, !isFindingAnyStream,
              !isMultiSelectMode, !viewing.isTwo else { return }
        viewing.checkOptionalSources(for: event, discover: { request, publish in
            await LiveStreamResolver.shared.resolvePlayback(for: request, onChoices: publish)
        }) { requested, phase in
            let sceneOwned = phase == .completion && viewing.hasMountedOptionalSourceLookup(for: requested)
            guard !Task.isCancelled, !viewing.isTwo,
                  sceneOwned || (isActive && scenePhase == .active && !isFindingAnyStream && !isMultiSelectMode) else { return nil }
            let codes = Set(await StreamPluginRegistry.shared.enabledProviderCodes())
            let stillSceneOwned = phase == .completion && viewing.hasMountedOptionalSourceLookup(for: requested)
            guard !Task.isCancelled, !viewing.isTwo,
                  stillSceneOwned || (isActive && scenePhase == .active && !isFindingAnyStream && !isMultiSelectMode) else { return nil }
            let now = Date()
            return OptionalSourceLookupPolicy.event(for: requested,
                in: matchListViewModel?.playbackAdmissionCatalog ?? [], enabledProviderCodes: codes, at: now,
                status: MatchStartPolicy.currentStatus(for: requested, scores: liveScoreService, now: now), phase: phase)
        }
    }

    private var showsFootballLeagueTabs: Bool {
        selectedSportTab == Self.footballCategoryID
    }

    private func channelEvents(applyingHomeInterests: Bool) -> [AnalyticalDataEngine.EventReference] {
        guard !showFollowedOnly,
              !(applyingHomeInterests && isHomeInterestRestrictionActive) else { return [] }
        let inventory = matchListViewModel?.browseCatalog ?? CricketChannelCatalog.merging(into: [])
        return inventory.filter { $0.isBroadcastChannel
            && (selectedSportTab == HomeSportsDiscovery.allSports || $0.normalizedCategory == selectedSportTab) }
    }

    @ViewBuilder
    private func cricketDiscovery(applyingHomeInterests: Bool) -> some View {
        let channels = channelEvents(applyingHomeInterests: applyingHomeInterests)
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                FottySectionHeader(title: "Cricket channels")
                ForEach(channels) { event in
                    LiveEventCard(
                        event: event,
                        onWatchTap: canOpenBroadcast(event) ? { watchEvent(event) } : nil,
                        onDetailsTap: { presentModal { selectedCatalogEvent = event } },
                        isSaved: myMatchdayStore.contains(event: event),
                        onSaveTap: { toggleSavedMatch(event) }
                    )
                    .accessibilityIdentifier("cricket-channel-\(event.id)")
                }
            }
        }
    }

    private var filteredEvents: [AnalyticalDataEngine.EventReference] {
        filteredEvents(applyingHomeInterests: true)
    }

    private func filteredEvents(applyingHomeInterests: Bool) -> [AnalyticalDataEngine.EventReference] {
        // The projection also contains verified source-free Champions League
        // fixtures that may not have reached a stream provider yet.
        let allMatches = discovery.items.map(\.event) + discovery.channels
        let sportScoped = allMatches.filter { selectedSportTab == HomeSportsDiscovery.allSports || $0.normalizedCategory == selectedSportTab }

        let leagueScoped: [AnalyticalDataEngine.EventReference]
        if showsFootballLeagueTabs, selectedFootballLeague != .all {
            leagueScoped = sportScoped.filter {
                footballLeagueTab(for: $0) == selectedFootballLeague
            }
        } else if selectedSportTab == "cricket" {
            leagueScoped = sportScoped.filter { selectedCricketFilter.includes($0) }
        } else {
            leagueScoped = sportScoped
        }

        guard showFollowedOnly || (applyingHomeInterests && isHomeInterestRestrictionActive) else { return leagueScoped }
        let personalization = personalizationContext
        return leagueScoped.filter {
            isEventFollowed($0, personalization: personalization)
        }
    }

    private var selectedInterestCount: Int {
        followedTeams.count + followedLeagues.count + followedSportIDs.count
    }

    private var followedSportIDs: Set<String> {
        SportsInterestPreferences.canonicalIDs(from: followedSportsRaw)
    }

    private var isHomeInterestRestrictionActive: Bool {
        HomeInterestPreferences.isActive(
            enabled: onlyShowSelectedInterests,
            selectedInterestCount: selectedInterestCount
        )
    }

    private var canOfferMultiView: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && TwoMatchSelectionPolicy.hasTwoCandidates(in: filteredEvents, where: isMultiViewCandidate(_:))
    }

    /// A match can join "Watch two" when its normal Watch action is available
    /// (stations, the registry, or a fresh lookup through enabled sources) and
    /// its timing suits two-match viewing. Until 9 Nov this required a shared
    /// catalog source, which no match has had since that catalog closed.
    private func isMultiViewCandidate(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        guard !HomeMatchPriority.isFinished(event, scoreService: liveScoreService),
              HomeMatchPriority.isMultiViewTimingEligible(event, scoreService: liveScoreService) else { return false }
        return broadcastAction(for: event) != nil
    }

    private func cplChannelActionTitle(_ event: AnalyticalDataEngine.EventReference) -> String? {
        // Ordinary rows never need the catalog-wide channel fallback search. Keeping that resolver in every
        // lazy-row body made the first scroll pay O(rows × catalog) work.
        guard event.isCPLFixture else { return nil }
        return broadcastAction(for: event)?.alternateActionTitle
    }

    private func canOpenBroadcast(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        if isMultiSelectMode { return isMultiViewCandidate(event) }
        return broadcastAction(for: event) != nil
    }

    /// The normal Watch action. Two-match selection and replacement use the
    /// same rule; they no longer depend on shared-catalog sources.
    private func broadcastAction(for event: EventReference) -> CurrentEventBroadcastPolicy.Action? {
        CurrentEventBroadcastPolicy.action(for: event, in: matchListViewModel?.playbackAdmissionCatalog ?? [], at: discoveryDate,
                                          status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService, now: discoveryDate))
    }

    private func liveEvents(excluding heroIDs: Set<String>) -> [AnalyticalDataEngine.EventReference] {
        let personalization = personalizationContext
        return HomeMatchPriority.prioritized(
            filteredEvents.filter {
                !heroIDs.contains($0.id)
                    && HomeMatchPriority.isLive($0, scoreService: liveScoreService)
            },
            scoreService: liveScoreService,
            isFollowed: { isEventFollowed($0, personalization: personalization) }
        )
    }

    private func soonEvents(excluding heroIDs: Set<String>) -> [AnalyticalDataEngine.EventReference] {
        let personalization = personalizationContext
        return HomeMatchPriority.prioritized(
            filteredEvents.filter {
                !heroIDs.contains($0.id)
                    && !HomeMatchPriority.isLive($0, scoreService: liveScoreService)
                    && !HomeMatchPriority.isFinished($0, scoreService: liveScoreService)
                    && HomeMatchPriority.isStartingSoon($0)
            },
            scoreService: liveScoreService,
            isFollowed: { isEventFollowed($0, personalization: personalization) }
        )
    }

    private func listEvents(
        excluding heroIDs: Set<String>,
        excludeSoon: Bool
    ) -> [AnalyticalDataEngine.EventReference] {
        let personalization = personalizationContext
        let remaining = filteredEvents.filter { event in
            guard !heroIDs.contains(event.id) else { return false }
            if HomeMatchPriority.isLive(event, scoreService: liveScoreService) { return false }
            if excludeSoon, HomeMatchPriority.isStartingSoon(event) { return false }
            return true
        }
        return HomeMatchPriority.prioritized(
            remaining,
            scoreService: liveScoreService,
            isFollowed: { isEventFollowed($0, personalization: personalization) }
        )
    }

    private var sectionTitle: String {
        if showFollowedOnly { return "Following" }
        let liveCount = filteredEvents.filter {
            HomeMatchPriority.isLive($0, scoreService: liveScoreService)
        }.count
        if liveCount > 0 { return "Live & upcoming" }
        if showsFootballLeagueTabs, selectedFootballLeague != .all {
            return selectedFootballLeague.displayName
        }
        return "Upcoming"
    }

    private func footballLeagueTabs(for viewModel: MatchListViewModel) -> [AnalyticalDataEngine.FootballLeagueTab] {
        AnalyticalDataEngine.footballLeagueTabs(for: viewModel.matches)
    }

    private func ensureValidSportSelection(from tabs: [String]) {
        let validSelection = HomeSportSelectionPolicy.validatedSelection(selectedSportTab, availableSports: tabs)
        if selectedSportTab != validSelection {
            selectedSportTab = validSelection
        }
    }

    private var isFindingAnyStream: Bool {
        isFindingStream || isFindingMultiStreams
    }

    private var selectedMultiEvents: [AnalyticalDataEngine.EventReference] {
        let allMatches = matchListViewModel?.matches ?? []
        return selectedMultiEventIDs.compactMap { selectedID in
            allMatches.first { $0.id == selectedID }
        }
    }

    private var followedTeamKeys: Set<String> {
        preparedPersonalizationSelection.teamKeys
    }

    private var personalizationSelectionIdentity: SportsPersonalizationPolicy.SelectionIdentity {
        SportsPersonalizationPolicy.selectionIdentity(teams: followedTeams, leagues: followedLeagues, sports: followedSportIDs)
    }

    private var preparedPersonalizationSelection: SportsPersonalizationPolicy.PreparedSelection {
        if let selection = projectedPersonalizationSelection,
           selection.identity == personalizationSelectionIdentity {
            return selection
        }
        return SportsPersonalizationPolicy.prepareSelection(teams: followedTeams, leagues: followedLeagues, sports: followedSportIDs)
    }

    private var personalizationContext: HomePersonalizationContext {
        HomePersonalizationContext(
            selection: preparedPersonalizationSelection,
            // Team/competition identity is not clock-dependent. Keep these
            // facts through countdown/status ticks, but never through catalog,
            // official-score or saved-selection edits. Missing IDs fall back.
            facts: personalizationFactsCache?.facts(matching: personalizationFactsKey) ?? [:]
        )
    }

    private var discoveryPersonalizationContext: HomePersonalizationContext {
        HomePersonalizationContext(
            selection: preparedPersonalizationSelection,
            facts: personalizationFactsCache?.factsForPublishedProjection(
                selection: personalizationSelectionIdentity) ?? [:]
        )
    }

    private func teamKey(name: String, category: String) -> String {
        TeamFollowKey.make(name: name, category: category)
    }

    private func isTeamFollowed(name: String, category: String) -> Bool {
        followedTeamKeys.contains(teamKey(name: name, category: category))
    }

    private func isEventFollowed(
        _ event: AnalyticalDataEngine.EventReference,
        personalization: HomePersonalizationContext
    ) -> Bool {
        if let facts = personalization.facts[event.id] { return facts.isFollowed }
        return follows(event, selection: personalization.selection)
    }

    private func follows(
        _ event: AnalyticalDataEngine.EventReference,
        selection: SportsPersonalizationPolicy.PreparedSelection
    ) -> Bool {
        SportsPersonalizationPolicy.isFollowed(event: event, selection: selection,
            officialMatch: event.normalizedCategory == "football"
                ? liveScoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil)
    }

    private func beginMultiSelectMode() {
        guard !isFindingAnyStream else { return }
        isMultiSelectMode = true
        selectedMultiEventIDs = []
    }

    private func cancelMultiSelectMode() {
        if isFindingMultiStreams { cancelCurrentResolution() }
        isMultiSelectMode = false
        selectedMultiEventIDs = []
    }

    private func toggleMultiSelection(for event: AnalyticalDataEngine.EventReference) {
        guard !isFindingAnyStream else { return }
        guard isMultiViewCandidate(event) else {
            streamError = "This match is not ready for two-match viewing yet."
            return
        }

        let updated = TwoMatchSelectionPolicy.toggled(selectedMultiEventIDs, eventID: event.id)
        if updated == selectedMultiEventIDs, !selectedMultiEventIDs.contains(event.id) {
            streamError = "Two matches are already selected. Remove one before choosing another."
            return
        }
        selectedMultiEventIDs = updated
        HapticManager.impact(.light)
    }

    private func watchSelectedInMultiView() {
        guard !isFindingAnyStream else { return }
        let events = selectedMultiEvents
        guard events.count == 2, events.allSatisfy({ playbackTimingAllows($0) }) else { return }

        #if DEBUG
        if ProcessInfo.processInfo.environment["FOTTY_MULTIVIEW_UI_TESTING"] == "1" {
            let sessions = events.map { event in
                (1...2).compactMap { index -> StreamSession? in
                    guard let url = URL(string: "https://www.score808live.tv/embed/fotty-ui-\(event.id)/\(index)") else {
                        return nil
                    }
                    return StreamSession(
                        matchID: event.id,
                        title: "Source \(index)",
                        playableURL: url,
                        streamType: .unknown,
                        providerName: "Score808",
                        qualityLabel: "UI fixture"
                    )
                }
            }
            multiViewSlots = zip(events, sessions).map { MultiLiveSlot(event: $0.0, sessions: $0.1) }
            selectedMultiEventIDs = []
            isMultiSelectMode = false
            showMultiPlayer = true
            return
        }
        #endif

        multiStreamTask?.cancel()
        cancelActiveMultiStreamRequests()

        let requestID = UUID()
        multiStreamRequestID = requestID
        isFindingMultiStreams = true
        multiResolutionTitles = events.map(eventTitle(_:))
        streamError = nil
        multiStreamStatusMessage = "Finding two playable broadcasts..."
        let requests = events.map(StreamPlaybackRequest.init(event:))
        activeMultiRequests = requests

        multiStreamTask = Task {
            defer {
                if multiStreamRequestID == requestID {
                    isFindingMultiStreams = false
                    activeMultiRequests = []
                }
            }
            do {
                try await StreamResolutionPresentation.waitForFeedbackFrame()
            } catch {
                return
            }
            guard !Task.isCancelled, multiStreamRequestID == requestID else { return }
            let indexedOutcomes = await resolveMultiViewRequests(requests, requestID: requestID)

            guard !Task.isCancelled, multiStreamRequestID == requestID else {
                cancelRequests(requests)
                return
            }

            if let failed = indexedOutcomes.first(where: {
                if case .failure = $0.outcome { return true }
                return false
            }), case .failure(let failure, let diagnostics) = failed.outcome {
                recordMultiResolutionFailure(failure, diagnostics: diagnostics)
                await MainActor.run {
                    guard !Task.isCancelled, multiStreamRequestID == requestID else { return }
                    multiStreamStatusMessage = "Preparing two-match view..."
                    streamError = "\(requests[failed.index].displayTitle) could not be prepared. \(failure.userMessage)"
                }
                return
            }

            let successes = indexedOutcomes.compactMap { result -> (Int, StreamResolutionSuccess)? in
                guard case .success(let success) = result.outcome else { return nil }
                return (result.index, success)
            }.sorted { $0.0 < $1.0 }

            guard successes.count == 2 else {
                await MainActor.run {
                    guard !Task.isCancelled, multiStreamRequestID == requestID else { return }
                    streamError = "One of these matches stopped preparing. Please try again."
                }
                return
            }

            let firstSuccess = successes[0].1
            let secondSuccess = successes[1].1
            switch (firstSuccess.sessions.isEmpty, secondSuccess.sessions.isEmpty) {
            case (false, false):
                guard !firstSuccess.sessions.isEmpty, !secondSuccess.sessions.isEmpty else {
                    await MainActor.run {
                        guard !Task.isCancelled, multiStreamRequestID == requestID else { return }
                        streamError = "One of these matches did not return a playable broadcast. Choose another pair or try again."
                    }
                    return
                }

                await MainActor.run {
                    guard !Task.isCancelled, multiStreamRequestID == requestID else { return }
                    multiViewSlots = [
                        MultiLiveSlot(event: events[0], sessions: firstSuccess.sessions),
                        MultiLiveSlot(event: events[1], sessions: secondSuccess.sessions)
                    ]
                    selectedMultiEventIDs = []
                    isMultiSelectMode = false
                    multiStreamStatusMessage = "Preparing two-match view..."
                    showMultiPlayer = true
                }
            default:
                await MainActor.run {
                    guard !Task.isCancelled, multiStreamRequestID == requestID else { return }
                    multiStreamStatusMessage = "Preparing two-match view..."
                    streamError = "One of these matches did not return a playable broadcast. Choose another pair or try again."
                }
            }
        }
    }

    private func resolveMultiViewRequests(
        _ requests: [StreamPlaybackRequest],
        requestID: UUID
    ) async -> [IndexedMultiResolution] {
        await withTaskGroup(of: IndexedMultiResolution.self, returning: [IndexedMultiResolution].self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    let outcome = await LiveStreamResolver.shared.resolvePlayback(for: request) { _ in
                        await MainActor.run {
                            guard multiStreamRequestID == requestID else { return }
                            multiStreamStatusMessage = "Preparing both matches..."
                        }
                    }
                    return IndexedMultiResolution(index: index, outcome: outcome)
                }
            }

            var results: [IndexedMultiResolution] = []
            for await result in group {
                results.append(result)
                if case .failure = result.outcome {
                    group.cancelAll()
                    for (index, request) in requests.enumerated() where index != result.index {
                        await LiveStreamResolver.shared.cancelAttempt(for: request)
                    }
                    break
                }
            }
            return results
        }
    }

    private func recordMultiResolutionFailure(
        _ failure: StreamFailure,
        diagnostics: StreamAttemptDiagnostics
    ) {
        FottyQualityStore.shared.record(
            category: .playback,
            name: "resolution_failure",
            outcome: .failure,
            details: [
                "route": "multiview",
                "mode": "resolution",
                "attempt_id": diagnostics.attemptID,
                "failure_kind": failure.category.rawValue
            ]
        )
    }



    private func lastLiveEvent(at now: Date) -> EventReference? {
        lastLiveStore.eligibleEvent(in: matchListViewModel?.playbackCatalog ?? [], at: now) { event in
            guard event.normalizedCategory == "football",
                  let match = liveScoreService.findMatch(home: event.homeName, away: event.awayName,
                    near: event.kickoffDate, maximumKickoffDelta: 15 * 60) else { return nil }
            return liveScoreService.currentStatus(for: match, at: now)
        }
    }

    private func openLastLiveMatch(_ event: EventReference) {
        guard !viewing.isTwo, !isFindingAnyStream, selectedHighlightsMatch == nil else { return }
        HapticManager.impact(.light)
        MatchPlaybackFeedback.shared.attempting(event.id)
        streamError = nil
        viewing.watchSingle(event, admission: { requested in
            let now = Date()
            discoveryDate = now
            // A displayed card can expire. Recheck after acknowledging the tap,
            // then use ordinary current admission, never a stored delivery URL.
            guard isActive, scenePhase == .active, let current = lastLiveEvent(at: now), current.id == requested.id else { return nil }
            return CurrentEventBroadcastPolicy.action(for: current,
                in: matchListViewModel?.playbackAdmissionCatalog ?? [], at: now,
                status: MatchStartPolicy.currentStatus(for: current, scores: liveScoreService, now: now))?.event
        })
    }

    private func watchEvent(_ event: AnalyticalDataEngine.EventReference) {
        guard !isFindingAnyStream else { return }
        pendingDetailsSourceCheck = nil
        viewing.cancelOptionalSourceLookup()
        if !isMultiSelectMode, !viewing.isTwo {
            guard selectedHighlightsMatch == nil else { return }
            HapticManager.impact(.light)
            MatchPlaybackFeedback.shared.attempting(event.id)
            streamError = nil
            viewing.watchSingle(event, admission: { requested in
                guard isActive, scenePhase == .active, !isFindingAnyStream, selectedHighlightsMatch == nil else { return nil }
                return CurrentEventBroadcastPolicy.action(for: requested,
                    in: matchListViewModel?.playbackAdmissionCatalog ?? [],
                    status: MatchStartPolicy.currentStatus(for: requested, scores: liveScoreService))?.event
            })
            return
        }
        guard playbackTimingAllows(event) else { return }
        guard !(isFindingStream && streamEvent?.id == event.id) else { return }
        // Prevent launching the player if we are trying to show highlights or chat.
        guard selectedHighlightsMatch == nil else { return }
        if viewing.reopenRetainedSingle(event: event, catalog: matchListViewModel?.playbackCatalog ?? [],
            status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)) {
            HapticManager.impact(.light)
            streamError = nil
            return
        }
        HapticManager.impact(.light)
        MatchPlaybackFeedback.shared.attempting(event.id)
        streamError = nil
        viewing.watchSingle(event)
    }


    /// Future rows stay inline. A supported source can be tried only inside
    /// the pre-start window; useful match information is a separate action.
    private func openEvent(_ event: AnalyticalDataEngine.EventReference) {
        if !isMultiSelectMode, !viewing.isTwo {
            watchEvent(event)
            return
        }
        // Recheck at the tap, rather than using the last display clock's action.
        if let action = CurrentEventBroadcastPolicy.action(for: event, in: matchListViewModel?.playbackAdmissionCatalog ?? [],
                status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)) {
            watchEvent(action.event)
            return
        }
        // Upcoming rows retain their inline countdown; no empty player or extra
        // detail sheet appears merely because a previously visible action expired.
    }

    private func playbackTimingAllows(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        MatchStartPolicy(event: event,
            status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)).timingAllowsPlayback
    }

    private func eventTitle(_ event: AnalyticalDataEngine.EventReference) -> String {
        event.displayTitle
    }

    /// A new modal destination owns the user's attention. Cancel before it
    /// opens so a late lookup cannot request a competing player presentation.
    private func presentModal(_ action: () -> Void) {
        viewing.cancelPendingSingleDiscovery()
        pendingDetailsSourceCheck = nil
        viewing.cancelOptionalSourceLookup()
        if isFindingAnyStream { cancelCurrentResolution() }
        action()
    }

    private func cancelCurrentResolution() {
        streamTask?.cancel()
        multiStreamTask?.cancel()
        let pendingEvent = streamEvent
        streamRequestID = UUID()
        multiStreamRequestID = UUID()
        isFindingStream = false
        isFindingMultiStreams = false
        multiResolutionTitles = []
        streamEvent = nil
        streamSessions = []
        streamStatusMessage = "Looking for a playable stream..."
        multiStreamStatusMessage = "Preparing two-match view..."
        if let event = pendingEvent {
            let request = StreamPlaybackRequest(event: event)
            Task {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
            }
        }
        cancelActiveMultiStreamRequests()
    }

    private func cancelActiveMultiStreamRequests() {
        cancelRequests(activeMultiRequests)
        activeMultiRequests = []
    }

    private func cancelRequests(_ requests: [StreamPlaybackRequest]) {
        guard !requests.isEmpty else { return }
        Task {
            for request in requests {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
            }
        }
    }

    private func emptyStateMessage(applyingHomeInterests: Bool) -> String {
        if applyingHomeInterests && isHomeInterestRestrictionActive && !showFollowedOnly {
            return "Nothing from your interests is scheduled in the next three days. Try Full lineup or Search."
        }
        if selectedSportTab == "cricket" {
            return selectedCricketFilter == .cpl
                ? "No CPL fixtures are listed for this period. Cricket channels may still be available under Channels."
                : "No cricket broadcasts are listed right now. Pull to refresh."
        }
        if showFollowedOnly {
            return "No upcoming events match your followed teams. Turn off the filter to see the full lineup."
        }
        return "Nothing is listed for this selection. Try another sport or refresh."
    }

    private func emptyState(applyingHomeInterests: Bool) -> some View {
        VStack(spacing: FottyTheme.spacingMD) {
            Image(systemName: "sportscourt")
                .font(.fottyScaled(size: 40))
                .foregroundStyle(FottyTheme.textTertiary)

            Text(applyingHomeInterests && isHomeInterestRestrictionActive
                 ? "Nothing from your interests"
                 : "No events right now")
                .font(.fottyScaled(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)

            Text(emptyStateMessage(applyingHomeInterests: applyingHomeInterests))
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dashboard-empty-state-message")

            if applyingHomeInterests && isHomeInterestRestrictionActive && !showFollowedOnly {
                NavigationLink {
                    SettingsManageLeaguesView(previewEvents: matchListViewModel?.playbackCatalog ?? [])
                } label: {
                    Label("Edit interests", systemImage: "slider.horizontal.3")
                        .font(.fottyScaled(size: 15, weight: .semibold))
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(FottyTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusXL))

                Button {
                    onlyShowSelectedInterests = false
                } label: {
                    Text("Remove interests filter")
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle())
            } else {
                Button {
                    Task { await matchListViewModel?.refresh() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                            .accessibilityIdentifier("dashboard-empty-refresh-label")
                    }
                    .font(.fottyScaled(size: 15, weight: .semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusXL))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(FottyTheme.spacingXL)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous)
                .strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
        }
    }

    private var loadingView: some View {
        VStack(spacing: FottyTheme.spacingMD) {
            SportLoadingView(category: selectedSportTab, size: 50,
                             competition: selectedFootballLeague == .championsLeague ? .championsLeague : nil)
        }
    }

}
