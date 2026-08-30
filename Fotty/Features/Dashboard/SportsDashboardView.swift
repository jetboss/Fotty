import SwiftUI
import SwiftData

struct SportsDashboardView: View {
    init() {
        #if DEBUG
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_CRICKET_UI_TESTING"] == "1" {
            _selectedSportTab = State(initialValue: "cricket")
        }
        #endif
    }

    @State private var matchListViewModel: MatchListViewModel?
    @State private var myMatchdayStore = MyMatchdayStore.shared
    @State private var selectedSportTab = HomeSportsDiscovery.allSports
    @State private var showsFullLineup = false
    @State private var showsAllSports = false
    @State private var discoveryDate = Date()
    @State private var selectedFootballLeague: AnalyticalDataEngine.FootballLeagueTab = .all
    @State private var selectedCricketFilter: CricketCatalogFilter = .all
    @State private var showPlayer = false
    @State private var showMultiPlayer = false
    @State private var streamSessions: [StreamSession] = []
    @State private var multiViewSlots: [MultiLiveSlot] = []
    @State private var activeMultiRequests: [StreamPlaybackRequest] = []
    @State private var streamEvent: AnalyticalDataEngine.EventReference? = nil
    @State private var isFindingStream = false
    @State private var isFindingMultiStreams = false
    @State private var streamError: String? = nil
    @State private var streamStatusMessage = "Looking for a playable stream..."
    @State private var multiStreamStatusMessage = "Preparing MultiView..."
    @State private var p2pPreflightSummary: String? = nil
    @State private var streamTask: Task<Void, Never>?
    @State private var multiStreamTask: Task<Void, Never>?
    @State private var streamRequestID = UUID()
    @State private var multiStreamRequestID = UUID()
    @State private var isMultiSelectMode = false
    @State private var selectedMultiEventIDs: Set<String> = []
    @State private var showFollowedOnly = false
    @State private var selectedCatalogEvent: AnalyticalDataEngine.EventReference? = nil
    @Environment(LiveScoreService.self) private var liveScoreService
    @State private var selectedHighlightsMatch: FootballMatch? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var socialCloudStore: SocialCloudStore

    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]

    private static let footballCategoryID = "football"

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
        }
        .alert("Stream Not Available", isPresented: .init(
            get: { streamError != nil },
            set: { if !$0 { streamError = nil } }
        )) {
            Button("OK") { streamError = nil }
        } message: {
            Text(streamError ?? "")
        }
        .dashboardPresentationLayers(
            selectedHighlightsMatch: $selectedHighlightsMatch,
            showPlayer: $showPlayer,
            showMultiPlayer: $showMultiPlayer,
            streamEvent: streamEvent,
            streamSessions: streamSessions,
            multiViewSlots: multiViewSlots,
            liveScoreService: liveScoreService,
            socialCloudStore: socialCloudStore
        )
        .sheet(item: $selectedCatalogEvent) { event in
            CatalogEventDetailsView(event: event)
                .environment(liveScoreService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAllSports) {
            NavigationStack {
                ScrollView {
                    SportActivityGrid(discovery: discovery, selectedSport: $selectedSportTab, expanded: true)
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
            streamTask?.cancel()
            multiStreamTask?.cancel()
            streamRequestID = UUID()
            multiStreamRequestID = UUID()
            isFindingStream = false
            isFindingMultiStreams = false
            isMultiSelectMode = false
            selectedMultiEventIDs = []
            streamSessions = []
            streamStatusMessage = "Looking for a playable stream..."
            multiStreamStatusMessage = "Preparing MultiView..."
            p2pPreflightSummary = nil
            cancelActiveMultiStreamRequests()
        }
        .task {
            if matchListViewModel == nil {
                matchListViewModel = MatchListViewModel.shared
            }
            matchListViewModel?.configure(modelContext: modelContext)
            if let viewModel = matchListViewModel {
                ensureValidSportSelection(from: viewModel.sportsTabs)
            }

            guard !AppRuntime.isAutomatedTesting else { return }
            await matchListViewModel?.refresh()
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
                await matchListViewModel?.refresh()
            }
        }
        .task {
            guard !AppRuntime.isAutomatedTesting else { return }
            await TeamBrandService.shared.bootstrapIfNeeded()
        }
        .task {
            // A lightweight local clock keeps "next" honest even if a network
            // refresh fails. It never starts an additional provider request.
            while !Task.isCancelled {
                discoveryDate = Date()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .task(id: selectedSportTab) {
            // All-sports includes football; reuse the same bounded score owner.
            guard !AppRuntime.isAutomatedTesting else { return }
            guard showsFootballScores else {
                liveScoreService.stopPolling()
                return
            }
            liveScoreService.startPolling()
        }
        .onDisappear {
            liveScoreService.stopPolling()
        }
        .onChange(of: selectedSportTab) { _, newValue in
            showFollowedOnly = false
            if newValue != Self.footballCategoryID {
                selectedFootballLeague = .all
            }
        }
        .onChange(of: matchListViewModel?.matches.count) { _, _ in
            if let tabs = matchListViewModel?.sportsTabs {
                ensureValidSportSelection(from: tabs)
            }
        }
        .onChange(of: followedTeams.count) { _, count in
            if count == 0 {
                showFollowedOnly = false
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
            guard !AppRuntime.isAutomatedTesting else { return }
            if newValue == .active {
                discoveryDate = Date()
                if showsFootballScores {
                    // startPolling performs an immediate refresh. Starting another
                    // detached refresh here doubled cold-launch API requests.
                    liveScoreService.startPolling()
                }
            } else if newValue == .background {
                liveScoreService.stopPolling()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            if let viewModel = matchListViewModel {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    matchesContent(viewModel)
                }
            } else {
                loadingView
            }

            if isFindingAnyStream {
                StreamResolutionOverlay(
                    statusMessage: isFindingMultiStreams ? multiStreamStatusMessage : streamStatusMessage,
                    subtitle: streamEvent.map { eventTitle($0) },
                    technicalSummary: p2pPreflightSummary,
                    isMultiStream: isFindingMultiStreams,
                    multiTitles: selectedMultiEvents.prefix(2).map { eventTitle($0) },
                    onCancel: cancelCurrentResolution
                )
            }
        }
        .background(FottyTheme.background.ignoresSafeArea())
    }

    private func matchesContent(_ viewModel: MatchListViewModel) -> some View {
        let schedule = discovery
        let items = scopedItems(in: schedule)
        let featured = schedule.featured(from: items, diverse: selectedSportTab == HomeSportsDiscovery.allSports)
        let later = schedule.later(from: items, excluding: featured)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                cinemaHomeMasthead
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsFootballScores && liveScoreService.shouldShowScoreFeedNotice {
                    FootballQuotaBanner()
                }

                discoveryFilters(schedule)

                if showFollowedOnly {
                    Button("Followed teams only · Clear") { showFollowedOnly = false }
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Clear followed-teams filter")
                }

                if isMultiSelectMode {
                    homeMatchList(events: items.map(\.event), usesMultiColumnGrid: false)
                } else {
                    HStack(alignment: .center) {
                        Text("Now & next")
                            .font(FottyTheme.typeSectionTitle)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .accessibilityIdentifier("home-discovery-heading")
                        Spacer(minLength: 8)
                        Button { showsFullLineup = true } label: {
                            Label("See all", systemImage: "chevron.right")
                                .font(FottyTheme.typeAction)
                                .foregroundStyle(FottyTheme.accentText)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the full lineup on Home")
                        .accessibilityIdentifier("home-see-all")
                    }

                    if !featured.isEmpty {
                        discoveryRows(featured, elevated: true)
                    } else if !items.isEmpty {
                        Text("Nothing starting in the next six hours. The full lineup has later and unconfirmed listings.")
                            .font(FottyTheme.typeBody)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if selectedSportTab == HomeSportsDiscovery.allSports, !schedule.channels.isEmpty {
                        Text("No timed events are listed right now. Choose Cricket to explore the available channels.")
                            .font(FottyTheme.typeBody)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !later.items.isEmpty {
                        Text(later.title)
                            .font(FottyTheme.typeSectionTitle)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .accessibilityIdentifier("home-discovery-heading")
                        discoveryRows(later.items, elevated: false)
                    }
                }

                if selectedSportTab == "cricket" { cricketDiscovery }

                if items.isEmpty && channelEvents.isEmpty {
                    emptyState
                }

                if !isMultiSelectMode { MatchdaySetupCard() }

                Text("Times are local. “On now” uses the listed start time unless a live score confirms play. Streams depend on the source.")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .accessibilityIdentifier("home-discovery-note")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FottyTheme.bentoInset)
            .padding(.top, FottyTheme.spacingMD)
        }
        .refreshable {
            guard !AppRuntime.isAutomatedTesting else { return }
            await viewModel.refresh()
            discoveryDate = Date()
        }
    }

    private var discovery: HomeSportsDiscovery {
        HomeSportsDiscovery(events: matchListViewModel?.matches ?? [], now: discoveryDate) { event in
            guard event.normalizedCategory == "football",
                  let match = liveScoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) else { return nil }
            // A schedule-only "timed" row is not proof of a delayed start.
            if match.status.isUpcoming, (event.kickoffDate ?? .distantFuture) <= discoveryDate { return nil }
            return HomeSportsDiscovery.recentStatus(
                match.status, refreshedAt: liveScoreService.lastRefresh,
                liveFeedAvailable: liveScoreService.feedMode != .unavailable && liveScoreService.feedMode != .inactive,
                now: discoveryDate
            )
        }
    }

    private var showsFootballScores: Bool {
        selectedSportTab == Self.footballCategoryID || selectedSportTab == HomeSportsDiscovery.allSports
    }

    private func footballLeagueTab(
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

    private func scopedItems(in schedule: HomeSportsDiscovery) -> [HomeSportsDiscovery.Item] {
        schedule.scopedItems(sport: selectedSportTab).filter { item in
            if showsFootballLeagueTabs, selectedFootballLeague != .all,
               footballLeagueTab(for: item.event) != selectedFootballLeague { return false }
            if selectedSportTab == "cricket", !selectedCricketFilter.includes(item.event) { return false }
            return !showFollowedOnly || isEventFollowed(item.event)
        }
    }

    private func discoveryFilters(_ schedule: HomeSportsDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SportActivityGrid(discovery: schedule, selectedSport: $selectedSportTab) { showsAllSports = true }
            if showsFootballLeagueTabs || selectedSportTab == "cricket" {
                CompactHomeFilterBar(
                    categories: [], selectedCategory: $selectedSportTab,
                    leagues: matchListViewModel.map(footballLeagueTabs(for:)) ?? [],
                    selectedLeague: $selectedFootballLeague,
                    showsSportMenu: false, showsLeagueMenu: showsFootballLeagueTabs,
                    selectedCricketFilter: $selectedCricketFilter
                )
            }
        }
    }

    private func discoveryRows(_ items: [HomeSportsDiscovery.Item], elevated: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id { Divider().overlay(FottyTheme.border) }
                HomeDiscoveryRow(
                    item: item,
                    isSaved: myMatchdayStore.contains(eventID: item.id),
                    onOpen: { openEvent(item.event) },
                    onSave: { toggleSavedMatch(item.event) }
                )
            }
        }
        .padding(.horizontal, 12)
        .background(elevated ? FottyTheme.surface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG))
        .overlay {
            if elevated {
                RoundedRectangle(cornerRadius: FottyTheme.radiusLG).strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
            }
        }
    }

    private var fullLineup: some View {
        let schedule = discovery
        let items = scopedItems(in: schedule)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                discoveryFilters(schedule)
                if !followedTeams.isEmpty {
                    Toggle("Followed teams only", isOn: $showFollowedOnly)
                        .font(FottyTheme.typeBody)
                        .tint(FottyTheme.accentText)
                }
                if items.isEmpty && channelEvents.isEmpty { emptyState }
                ForEach(FixtureDateGrouper.sections(from: items.map(\.event))) { section in
                    Text(section.title)
                        .font(FottyTheme.typeSectionTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    let ids = Set(section.events.map(\.id))
                    discoveryRows(items.filter { ids.contains($0.id) }, elevated: true)
                }
                if selectedSportTab == "cricket" || selectedSportTab == HomeSportsDiscovery.allSports { cricketDiscovery }
            }
            .padding(FottyTheme.spacingMD)
            .frame(maxWidth: 920)
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

    private var cinemaHomeMasthead: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FOTTY")
                    .font(FottyTheme.typeScreenTitle)
                    .tracking(-1.0)
                    .foregroundStyle(FottyTheme.textPrimary)

                Text(mastheadSubtitle)
                    .font(.fottyScaled(size: 14, weight: .bold))
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            Spacer()

            if canOfferMultiView {
                Button(action: beginMultiSelectMode) {
                    Label("Watch 2", systemImage: "square.split.2x1")
                        .font(.fottyScaled(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(FottyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch two matches")
                .accessibilityHint("Select two matches to watch together")
            }
        }
    }

    private static let upNextDateFormatterLock = NSLock()
    private static let upNextDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var mastheadSubtitle: String {
        return "Your day in sport."
    }

    private var multiSelectChrome: some View {
        HStack {
            Button("Cancel", action: cancelMultiSelectMode)
                .foregroundStyle(FottyTheme.textPrimary)
            Spacer()
            Text("Select 2 matches (\(selectedMultiEventIDs.count)/2)")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
            Spacer()
            Button("Watch 2-Up", action: watchSelectedInMultiView)
                .fontWeight(.bold)
                .foregroundStyle(selectedMultiEventIDs.count == 2 ? FottyTheme.accentText : FottyTheme.textTertiary)
                .disabled(selectedMultiEventIDs.count != 2)
        }
        .padding(.horizontal, FottyTheme.bentoInset)
        .padding(.vertical, 10)
        .background(FottyTheme.surfaceElevated)
    }

    private func homeMatchList(
        events: [AnalyticalDataEngine.EventReference],
        usesMultiColumnGrid: Bool = UIDevice.current.userInterfaceIdiom == .pad
    ) -> some View {
        DashboardMatchList(
            title: isMultiSelectMode ? "Select matches" : "Match schedule",
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
            onInfoTap: { match in selectedHighlightsMatch = match },
            onAppearEvent: { _ in },
            canWatchEvent: isPlaybackCandidate(_:),
            isSavedEvent: { myMatchdayStore.contains(eventID: $0.id) },
            onToggleSaved: toggleSavedMatch,
            usesMultiColumnGrid: usesMultiColumnGrid
        )
    }

    private func liveCard(
        for event: AnalyticalDataEngine.EventReference
    ) -> some View {
        LiveEventCard(
            event: event,
            onInfoTap: { match in selectedHighlightsMatch = match },
            onWatchTap: isPlaybackCandidate(event) ? { watchEvent(event) } : nil,
            onDetailsTap: { openEvent(event) },
            isSaved: myMatchdayStore.contains(eventID: event.id),
            onSaveTap: { toggleSavedMatch(event) }
        )
    }

    private func toggleSavedMatch(_ event: AnalyticalDataEngine.EventReference) {
        HapticManager.impact(.light)
        withAnimation(FottyTheme.springSnappy) {
            myMatchdayStore.toggle(event)
        }
    }

    private var showsFootballLeagueTabs: Bool {
        selectedSportTab == Self.footballCategoryID
    }

    private var channelEvents: [AnalyticalDataEngine.EventReference] {
        guard !showFollowedOnly else { return [] }
        return discovery.channels.filter { selectedSportTab == HomeSportsDiscovery.allSports || $0.normalizedCategory == selectedSportTab }
    }

    @ViewBuilder
    private var cricketDiscovery: some View {
        if selectedCricketFilter != .channels,
           filteredEvents.contains(where: { $0.id.hasPrefix("cpl-2026-") }) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Caribbean Premier League")
                    .font(FottyTheme.typeSectionTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(CPLSchedule.sourceLabel)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                Text(CPLSchedule.sourceNote)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("cpl-schedule-notice")
        }
        if !channelEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                FottySectionHeader(title: "Cricket channels")
                Text("Current programmes are not confirmed. A channel listing does not guarantee a CPL broadcast.")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(channelEvents) { event in
                    LiveEventCard(
                        event: event,
                        onWatchTap: isPlaybackCandidate(event) ? { watchEvent(event) } : nil,
                        onDetailsTap: { selectedCatalogEvent = event },
                        isSaved: myMatchdayStore.contains(eventID: event.id),
                        onSaveTap: { toggleSavedMatch(event) }
                    )
                    .accessibilityIdentifier("cricket-channel-\(event.id)")
                }
            }
        }
    }

    private var filteredEvents: [AnalyticalDataEngine.EventReference] {
        let allMatches = matchListViewModel?.matches ?? []
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

        guard showFollowedOnly else {
            return leagueScoped
        }

        return leagueScoped.filter(isEventFollowed(_:))
    }

    private var canOfferMultiView: Bool {
        return filteredEvents.lazy.filter(isMultiViewCandidate(_:)).prefix(2).count == 2
    }

    private func isMultiViewCandidate(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        guard !HomeMatchPriority.isFinished(event, scoreService: liveScoreService) else { return false }
        return HomeMatchPriority.isMultiViewTimingEligible(event, scoreService: liveScoreService)
            && isPlaybackCandidate(event)
            && event.sources?.contains { source in
                StreamPluginProviderMatching.isActiveCatalogSource(source)
                    && LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: source.source)
            } == true
    }

    /// A Watch action is shown whenever the catalog advertises a supported
    /// source. Recent provider failures may influence automatic ordering, but
    /// must never hide a manual Watch attempt from a catalog-listed match.
    private func isPlaybackCandidate(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        event.sources?.contains { source in
            StreamPluginProviderMatching.isActiveCatalogSource(source)
        } == true
    }

    private var carouselEvents: [AnalyticalDataEngine.EventReference] {
        HomeMatchPriority.carouselCandidates(
            from: filteredEvents.filter(isPlaybackCandidate(_:)),
            scoreService: liveScoreService,
            isFollowed: isEventFollowed(_:)
        )
    }

    /// All sports — independent of the selected category filter.
    private func onNowGlance(
        from allMatches: [AnalyticalDataEngine.EventReference]
    ) -> (
        live: [AnalyticalDataEngine.EventReference],
        soon: [AnalyticalDataEngine.EventReference],
        surprise: AnalyticalDataEngine.EventReference?
    ) {
        let live = HomeMatchPriority.prioritized(
            allMatches.filter {
                isPlaybackCandidate($0)
                    && HomeMatchPriority.isLive($0, scoreService: liveScoreService)
            },
            scoreService: liveScoreService,
            isFollowed: isEventFollowed(_:)
        )
        let soon = HomeMatchPriority.prioritized(
            allMatches.filter {
                isPlaybackCandidate($0)
                    && !HomeMatchPriority.isLive($0, scoreService: liveScoreService)
                    && !HomeMatchPriority.isFinished($0, scoreService: liveScoreService)
                    && HomeMatchPriority.isStartingSoon($0)
            },
            scoreService: liveScoreService,
            isFollowed: isEventFollowed(_:)
        )
        // Surprise prefers live; falls back to soon. Followed teams already rank first.
        let surprisePool = live.isEmpty ? soon : live
        let surprise: AnalyticalDataEngine.EventReference?
        if surprisePool.count <= 1 {
            surprise = surprisePool.first
        } else {
            // Stable-ish pick that still rotates: day bucket + count.
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            surprise = surprisePool[(day + surprisePool.count) % surprisePool.count]
        }
        return (live, soon, surprise)
    }

    private func liveEvents(excluding heroIDs: Set<String>) -> [AnalyticalDataEngine.EventReference] {
        HomeMatchPriority.prioritized(
            filteredEvents.filter {
                !heroIDs.contains($0.id)
                    && HomeMatchPriority.isLive($0, scoreService: liveScoreService)
            },
            scoreService: liveScoreService,
            isFollowed: isEventFollowed(_:)
        )
    }

    private func soonEvents(excluding heroIDs: Set<String>) -> [AnalyticalDataEngine.EventReference] {
        HomeMatchPriority.prioritized(
            filteredEvents.filter {
                !heroIDs.contains($0.id)
                    && !HomeMatchPriority.isLive($0, scoreService: liveScoreService)
                    && !HomeMatchPriority.isFinished($0, scoreService: liveScoreService)
                    && HomeMatchPriority.isStartingSoon($0)
            },
            scoreService: liveScoreService,
            isFollowed: isEventFollowed(_:)
        )
    }

    private func listEvents(
        excluding heroIDs: Set<String>,
        excludeSoon: Bool
    ) -> [AnalyticalDataEngine.EventReference] {
        let remaining = filteredEvents.filter { event in
            guard !heroIDs.contains(event.id) else { return false }
            if HomeMatchPriority.isLive(event, scoreService: liveScoreService) { return false }
            if excludeSoon, HomeMatchPriority.isStartingSoon(event) { return false }
            return true
        }
        return HomeMatchPriority.prioritized(
            remaining,
            scoreService: liveScoreService,
            isFollowed: isEventFollowed(_:)
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
        guard selectedSportTab != HomeSportsDiscovery.allSports else { return }
        guard !tabs.isEmpty else { return }
        if !tabs.contains(selectedSportTab) {
            selectedSportTab = HomeSportsDiscovery.allSports
        }
    }

    private var isFindingAnyStream: Bool {
        isFindingStream || isFindingMultiStreams
    }

    private var selectedMultiEvents: [AnalyticalDataEngine.EventReference] {
        let allMatches = matchListViewModel?.matches ?? []
        return allMatches.filter { selectedMultiEventIDs.contains($0.id) }
    }

    private var followedTeamKeys: Set<String> {
        Set(followedTeams.map(\.key))
    }

    private func teamKey(name: String, category: String) -> String {
        TeamFollowKey.make(name: name, category: category)
    }

    private func isTeamFollowed(name: String, category: String) -> Bool {
        followedTeamKeys.contains(teamKey(name: name, category: category))
    }

    private func isEventFollowed(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        isTeamFollowed(name: event.homeName, category: event.normalizedCategory)
        || isTeamFollowed(name: event.awayName, category: event.normalizedCategory)
    }

    private func beginMultiSelectMode() {
        isMultiSelectMode = true
        selectedMultiEventIDs = []
    }

    private func cancelMultiSelectMode() {
        isMultiSelectMode = false
        selectedMultiEventIDs = []
    }

    private func toggleMultiSelection(for event: AnalyticalDataEngine.EventReference) {
        guard isMultiViewCandidate(event) else {
            streamError = "No healthy stream candidate is currently available for this match."
            return
        }

        if selectedMultiEventIDs.contains(event.id) {
            selectedMultiEventIDs.remove(event.id)
            return
        }

        if selectedMultiEventIDs.count >= 2 {
            streamError = "You can only select up to 2 matches for MultiView."
            return
        }

        selectedMultiEventIDs.insert(event.id)
    }

    private func watchSelectedInMultiView() {
        let events = selectedMultiEvents
        guard events.count == 2, events.allSatisfy({ playbackTimingAllows($0) }) else { return }

        multiStreamTask?.cancel()
        cancelActiveMultiStreamRequests()

        let requestID = UUID()
        multiStreamRequestID = requestID
        isFindingMultiStreams = true
        streamError = nil
        multiStreamStatusMessage = "Preparing MultiView..."
        let requests = events.map(StreamPlaybackRequest.init(event:))
        activeMultiRequests = requests

        multiStreamTask = Task {
            async let firstOutcome = LiveStreamResolver.shared.resolvePlayback(for: requests[0]) { progress in
                await MainActor.run {
                    guard multiStreamRequestID == requestID else { return }
                    multiStreamStatusMessage = "\(progress.userMessage)\n\(requests[0].displayTitle)"
                }
            }
            async let secondOutcome = LiveStreamResolver.shared.resolvePlayback(for: requests[1]) { progress in
                await MainActor.run {
                    guard multiStreamRequestID == requestID else { return }
                    multiStreamStatusMessage = "\(progress.userMessage)\n\(requests[1].displayTitle)"
                }
            }

            let outcomes = await (firstOutcome, secondOutcome)

            guard !Task.isCancelled, multiStreamRequestID == requestID else {
                cancelRequests(requests)
                return
            }

            await MainActor.run {
                isFindingMultiStreams = false
                activeMultiRequests = []
            }

            switch outcomes {
            case (.success(let firstSuccess), .success(let secondSuccess)):
                guard !firstSuccess.sessions.isEmpty, !secondSuccess.sessions.isEmpty else {
                    await MainActor.run {
                        streamError = "Could not prepare both streams for MultiView."
                    }
                    return
                }

                await MainActor.run {
                    multiViewSlots = [
                        MultiLiveSlot(event: events[0], sessions: firstSuccess.sessions),
                        MultiLiveSlot(event: events[1], sessions: secondSuccess.sessions)
                    ]
                    selectedMultiEventIDs = []
                    isMultiSelectMode = false
                    multiStreamStatusMessage = "Preparing MultiView..."
                    showMultiPlayer = true
                }
            case (.failure(let failure, _), _):
                await MainActor.run {
                    multiStreamStatusMessage = "Preparing MultiView..."
                    streamError = failure.userMessage
                }
            case (_, .failure(let failure, _)):
                await MainActor.run {
                    multiStreamStatusMessage = "Preparing MultiView..."
                    streamError = failure.userMessage
                }
            }
        }
    }

    @ViewBuilder
    private func multiSelectBadge(for event: AnalyticalDataEngine.EventReference) -> some View {
        let isSelected = selectedMultiEventIDs.contains(event.id)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.fottyScaled(size: 20, weight: .semibold))
            .foregroundStyle(isSelected ? FottyTheme.accent : .white.opacity(0.8))
            .padding(4)
            .background(Circle().fill(.black.opacity(0.45)))
    }



    private func watchEvent(_ event: AnalyticalDataEngine.EventReference) {
        guard playbackTimingAllows(event) else { return }
        MatchPlaybackFeedback.shared.attempting(event.id)
        // Prevent launching the player if we are trying to show highlights or chat
        guard selectedHighlightsMatch == nil else { return }

        if let inFlightEvent = streamEvent {
            let inFlightRequest = StreamPlaybackRequest(event: inFlightEvent)
            Task {
                await LiveStreamResolver.shared.cancelAttempt(for: inFlightRequest)
            }
        }

        streamTask?.cancel()
        let requestID = UUID()
        streamRequestID = requestID

        isFindingStream = true
        streamEvent = event
        streamError = nil
        streamSessions = []
        streamStatusMessage = "Looking for a playable stream..."
        p2pPreflightSummary = nil

        streamTask = Task {
            let matchedEvent = await LiveStreamResolver.shared.catalogEvent(for: StreamPlaybackRequest(event: event)) ?? event
            guard !Task.isCancelled, streamRequestID == requestID else { return }
            guard playbackTimingAllows(matchedEvent) else {
                isFindingStream = false
                MatchPlaybackFeedback.shared.notReady(event.id)
                return
            }
            let request = StreamPlaybackRequest(event: matchedEvent)

            await MainActor.run {
                guard streamRequestID == requestID else { return }
                streamEvent = matchedEvent
            }

            let outcome = await LiveStreamResolver.shared.resolvePlayback(for: request) { progress in
                await MainActor.run {
                    guard streamRequestID == requestID else { return }
                    streamStatusMessage = progress.userMessage
                    p2pPreflightSummary = progress.technicalMessage
                }
            }

            guard !Task.isCancelled, streamRequestID == requestID else {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
                return
            }

            await MainActor.run {
                switch outcome {
                case .success(let success):
                    isFindingStream = false
                    // StreamEx + Score808 only — never surface P2P / VipLeague rows in the player.
                    let webSessions = success.sessions.filter(StreamPluginProviderMatching.isActivePlayerSession)
                    p2pPreflightSummary = nil
                    if webSessions.isEmpty {
                        MatchPlaybackFeedback.shared.notReady(event.id)
                    } else {
                        streamSessions = webSessions
                        showPlayer = true
                    }
                case .failure:
                    isFindingStream = false
                    MatchPlaybackFeedback.shared.notReady(event.id)
                }
            }
        }
    }

    /// Future rows stay inline. A supported source can be tried only inside
    /// the pre-start window; useful match information is a separate action.
    private func openEvent(_ event: AnalyticalDataEngine.EventReference) {
        guard playbackTimingAllows(event) else { return }
        guard event.kickoffDate.map({ $0 <= Date() }) ?? true || isPlaybackCandidate(event) else { return }
        if isPlaybackCandidate(event) {
            watchEvent(event)
            return
        }

        if event.normalizedCategory == "football",
           let match = liveScoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) {
            selectedHighlightsMatch = match
            return
        }

        selectedCatalogEvent = event
    }

    private func playbackTimingAllows(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        MatchStartPolicy(event: event,
            status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)).timingAllowsPlayback
    }

    private func eventTitle(_ event: AnalyticalDataEngine.EventReference) -> String {
        event.displayTitle
    }

    private func cancelCurrentResolution() {
        streamTask?.cancel()
        multiStreamTask?.cancel()
        let pendingEvent = streamEvent
        streamRequestID = UUID()
        multiStreamRequestID = UUID()
        isFindingStream = false
        isFindingMultiStreams = false
        streamEvent = nil
        streamSessions = []
        streamStatusMessage = "Looking for a playable stream..."
        multiStreamStatusMessage = "Preparing MultiView..."
        p2pPreflightSummary = nil
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

    private var emptyStateMessage: String {
        if let error = matchListViewModel?.error, !error.isEmpty {
            return "Connection failed. Check your network and try again.\n\n\(error)"
        }
        if selectedSportTab == "cricket" {
            return selectedCricketFilter == .cpl
                ? "No CPL fixtures are listed for this period. Cricket channels may still be available under Channels."
                : "No cricket broadcasts are listed right now. Pull to refresh the provider catalogue."
        }
        if showFollowedOnly {
            return "No upcoming events match your followed teams. Turn off the filter to see the full lineup."
        }
        return "No events are listed for this selection. Try another sport or refresh the catalogue."
    }

    private var emptyState: some View {
        VStack(spacing: FottyTheme.spacingMD) {
            Image(systemName: "sportscourt")
                .font(.fottyScaled(size: 40))
                .foregroundStyle(FottyTheme.textTertiary)

            Text("No events right now")
                .font(.fottyScaled(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)

            Text(emptyStateMessage)
                .font(.fottyScaled(size: 15, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("dashboard-empty-state-message")

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
            FootballLoadingView(size: 50)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: FottyTheme.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.fottyScaled(size: 40))
                .foregroundStyle(FottyTheme.accentText)

            Text("Couldn't load matches")
                .font(.fottyScaled(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)

            Text(message)
                .font(.fottyScaled(size: 13))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await matchListViewModel?.refresh() }
            } label: {
                Text("Retry")
                    .font(.fottyScaled(size: 15, weight: .semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(FottyTheme.accentGradient)
                    .clipShape(Capsule())
            }
        }
        .padding(FottyTheme.spacingXL)
    }
}

struct CatalogEventDetailsView: View {
    let event: AnalyticalDataEngine.EventReference

    @Environment(\.dismiss) private var dismiss
    @Environment(LiveScoreService.self) private var scoreService

    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()

                ScrollView {
                  VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                    HStack {
                        Text(event.categoryDisplayName.uppercased())
                            .font(FottyTheme.typeCaption)
                            .foregroundStyle(FottyTheme.textTertiary)

                        Spacer()

                        Text(statusLabel)
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(isLive ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .background(isLive ? FottyTheme.accent : FottyTheme.surfaceElevated)
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        if event.isBroadcastChannel {
                            Label(event.title ?? "Cricket channel", systemImage: "tv")
                                .font(FottyTheme.typeSectionTitle)
                        } else if event.awayName == "Away", event.teams?.away?.name == nil {
                            Text(event.displayTitle)
                                .font(FottyTheme.typeSectionTitle)
                                .foregroundStyle(FottyTheme.textPrimary)
                        } else {
                            teamRow(name: event.homeName, crest: event.homeBadgeURL)
                            teamRow(name: event.awayName, crest: event.awayBadgeURL)
                        }
                    }

                    if event.id.hasPrefix("cpl-2026-") {
                        Text(CPLSchedule.sourceLabel + "\n" + CPLSchedule.sourceNote)
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Broadcast not listed", systemImage: "tv.slash")
                            .font(FottyTheme.typeSectionTitle)
                            .foregroundStyle(FottyTheme.textPrimary)

                        Text(availabilityMessage)
                            .font(FottyTheme.typeBody)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(FottyTheme.spacingMD)
                    .bentoSurface(cornerRadius: FottyTheme.radiusMD)

                    Spacer(minLength: 0)
                }
                .padding(FottyTheme.spacingLG)
                }
            }
            .navigationTitle(event.isBroadcastChannel ? "Channel details" : "Match details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(FottyTheme.accentText)
                }
            }
        }
    }

    private var isLive: Bool {
        HomeMatchPriority.isLive(event, scoreService: scoreService)
    }

    private var statusLabel: String {
        if event.isBroadcastChannel { return "CHANNEL" }
        if isLive { return "IN PLAY" }
        guard let kickoff = event.kickoffDate else { return "SCHEDULED" }
        return kickoff.arenaKickoffDetailLine()
    }

    private var availabilityMessage: String {
        if event.isBroadcastChannel {
            return "This channel is in the catalogue, but no supported source is currently listed. Its programme is not confirmed."
        }
        let timing = isLive ? "This match is currently in play" : "This match is listed in the schedule"
        return "\(timing), but Fotty does not currently have a supported broadcast for it."
    }

    private func teamRow(name: String, crest: URL?) -> some View {
        HStack(spacing: 12) {
            FlagSquircleBadge(name: name, badgeURL: crest, size: 40, glowEnabled: false)
            Text(name)
                .font(FottyTheme.typeSectionTitle)
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(2)
        }
    }
}

struct MomentumPulse: View {
    @State private var pulse = 0.0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<6) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(FottyTheme.momentumGradient)
                    .frame(width: 2, height: height(for: index))
                    .opacity(opacity(for: index))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = 1.0
            }
        }
    }

    private func height(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let variation = CGFloat.random(in: 4...12)
        return base + (variation * pulse)
    }

    private func opacity(for index: Int) -> Double {
        let base = 0.3
        let variation = 0.7 * pulse
        return base + variation
    }
}
