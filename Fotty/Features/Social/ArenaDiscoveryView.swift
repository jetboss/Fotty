import SwiftUI
import SwiftData

struct MatchdayProjectionKey: Hashable {
    let catalogRevision: Int
    let scoreRevisionMilliseconds: Int64
    let minuteBucket: Int64
    let savedRevision: Int
    let followedTeams: [String]
    let followedLeagues: [String]
    let showKickoffClashes: Bool
    var followedSports: [String] = []
    var registryRevision: String?
    var discoveryRevision: UInt64 = 0
    var listingRevision: UInt64 = 0
    var enabledSources: Set<String> = []
}

/// The same scope control is used by the real screen and bounded native layout
/// checks. No plan state or data is created by changing its presentation.
struct MatchdayScopeControl: View {
    @Binding var selection: MatchdayViewMode
    var usesWideLayout: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                choices.pickerStyle(.menu)
                    .frame(minHeight: 44, alignment: .leading)
            } else {
                choices.pickerStyle(.segmented)
                    .frame(maxWidth: usesWideLayout ? 420 : .infinity, alignment: .leading)
            }
        }
    }

    private var choices: some View {
        Picker("Matchday view", selection: $selection) {
            ForEach(MatchdayViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .accessibilityIdentifier("matchday-view-mode")
    }
}

/// The three existing duration choices keep their full names. A compact phone
/// card is narrower than its screen; select a native menu when the actual
/// proposed control width cannot comfortably hold the segmented labels.
struct MatchdayDurationControl: View {
    @Binding var selection: String
    var usesWideLayout: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var segmentedMinimumWidth: CGFloat = 300
    @State private var hasSegmentedWidth = false

    static func usesMenu(width: CGFloat, minimumWidth: CGFloat = 300,
                         wideLayout: Bool, accessibilitySize: Bool) -> Bool {
        wideLayout || accessibilitySize || !width.isFinite || width < minimumWidth
    }

    var body: some View {
        Group {
            if usesWideLayout || typeSize.isAccessibilitySize || !hasSegmentedWidth {
                choices.pickerStyle(.menu)
            } else {
                choices.pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .onGeometryChange(for: Bool.self) { geometry in
            !Self.usesMenu(width: geometry.size.width, minimumWidth: segmentedMinimumWidth,
                           wideLayout: false, accessibilitySize: false)
        } action: { hasSegmentedWidth = $0 }
    }

    private var choices: some View {
        Picker("Available viewing time", selection: $selection) {
            ForEach(ViewingPlanDuration.allCases) { duration in
                Text(duration.title).tag(duration.rawValue)
            }
        }
        .accessibilityIdentifier("matchday-viewing-duration")
    }
}

/// A fixed-count child per lazy-stack entry, rather than one eager stack per
/// section. Namespaced IDs keep a fixture distinct when its section/columns change.
enum MatchdayDisplayLayout {
    enum ID: Hashable {
        case heading(String)
        case fixtures(section: String, columns: Int, members: [AnyHashable])
    }

    struct Section<Item: Identifiable> {
        let id: String
        let title: String
        let subtitle: String?
        let items: [Item]
    }

    struct Heading {
        let sectionID: String
        let title: String
        let subtitle: String?
        let count: Int?
        let isFirstSection: Bool
    }

    struct Row<Item: Identifiable> {
        let id: ID
        let items: [Item]
        let index: Int
        let count: Int
        let columns: Int
        let showsReason: Bool

        var isFirst: Bool { index == 0 }
        var isLast: Bool { index == count - 1 }
    }

    enum Entry<Item: Identifiable>: Identifiable {
        case heading(Heading)
        case fixtures(Row<Item>)

        var id: ID {
            switch self {
            case .heading(let heading): return .heading(heading.sectionID)
            case .fixtures(let row): return row.id
            }
        }
    }

    static func entries<Item: Identifiable>(
        sections: [Section<Item>], columns: Int, excluding excludedID: Item.ID?,
        reason: (Item) -> String, isChannel: (Item) -> Bool
    ) -> [Entry<Item>] {
        let columns = max(1, columns)
        var entries: [Entry<Item>] = []
        for section in sections {
            let visible = section.items.filter { $0.id != excludedID }
            guard !visible.isEmpty else { continue }
            let sharedReason = Set(visible.map(reason)).count == 1
            entries.append(.heading(Heading(
                sectionID: section.id, title: section.title,
                subtitle: section.subtitle ?? (sharedReason ? visible.first.map(reason) : nil),
                count: visible.allSatisfy(isChannel) ? nil : visible.count,
                isFirstSection: entries.isEmpty
            )))
            let rows = FottyLayoutPolicy.rows(visible, columns: columns)
            for (index, row) in rows.enumerated() {
                entries.append(.fixtures(Row(
                    id: .fixtures(section: section.id, columns: columns, members: row.items.map { AnyHashable($0.id) }),
                    items: row.items, index: index, count: rows.count, columns: columns,
                    showsReason: !sharedReason
                )))
            }
        }
        return entries
    }
}

private struct MatchdayRowPresentation: Identifiable {
    let event: AnalyticalDataEngine.EventReference
    let reason: String
    let reasonIcon: String
    let action: CurrentEventBroadcastPolicy.Action?
    let savedRecord: SavedMatchRecord?
    let isInCurrentSchedule: Bool
    let section: MatchdayEventStatePolicy.Section

    var isLive: Bool { section == .live }
    var isFinished: Bool { section == .recent }

    var id: String { event.id }
}

private struct MatchdayDaySection: Identifiable {
    let date: Date
    let rows: [MatchdayRowPresentation]

    var id: Date { date }
}

private struct MatchdayProjection {
    var isReady = false
    var rows: [MatchdayRowPresentation] = []
    var live: [MatchdayRowPresentation] = []
    var listedNow: [MatchdayRowPresentation] = []
    var nextUp: [MatchdayRowPresentation] = []
    var laterDays: [MatchdayDaySection] = []
    var channels: [MatchdayRowPresentation] = []
    var timeToBeConfirmed: [MatchdayRowPresentation] = []
    var awaitingConfirmation: [MatchdayRowPresentation] = []
    var recent: [MatchdayRowPresentation] = []
    var conflicts: [MatchdayConflict] = []
    var hasFootball = false

    static let empty = MatchdayProjection()
}

/// A personal matchday shortlist. Home discovers the full catalog; this screen
/// contains only matches the user saved or that match their team/league follows.
struct ArenaDiscoveryView: View {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @AppStorage(MatchdayPreferences.showKickoffClashesKey)
    private var showKickoffClashes = MatchdayPreferences.defaultShowKickoffClashes
    @AppStorage(SportsInterestPreferences.storageKey)
    private var followedSportIDsRaw = SportsInterestPreferences.emptyValue
    @Environment(\.fottyWideLayout) private var usesWideLayout
    @Environment(\.dynamicTypeSize) private var typeSize
    let isActive: Bool
    let onBrowseHome: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    @Environment(LiveScoreService.self) private var liveScoreService
    @State private var scorePollingOwner = UUID()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query private var followedLeagues: [FollowedLeagueItem]

    @State private var matchListViewModel: MatchListViewModel
    @State private var myMatchdayStore: MyMatchdayStore
    @State private var selectedCatalogEvent: AnalyticalDataEngine.EventReference?
    @State private var pendingDetailsWatch: AnalyticalDataEngine.EventReference?
    @State private var pendingDetailsSourceCheck: AnalyticalDataEngine.EventReference?
    @State private var showsTeams = false
    @State private var navigation = MatchNavigationStore.shared
    @State private var remindedEventID: String?
    @State private var matchdayProjection = MatchdayProjection.empty
    @State private var matchdayDate = Date()
    @State private var savedMatchError: String?
    @State private var showsClashDetails = false
    @AppStorage(ViewingPlanDuration.storageKey) private var viewingDurationRaw = ViewingPlanDuration.twoHours.rawValue
    @State private var viewingWindowStart = Date()
    @State private var hasStartedViewingWindow = false
    @State private var viewingPlanProjection: ViewingPlanPolicy.Projection?
    @State private var viewMode = MatchdayViewMode.defaultMode

    @State private var showPlayer = false
    @State private var streamEvent: AnalyticalDataEngine.EventReference?
    @State private var streamSessions: [StreamSession] = []
    @State private var isFindingStream = false
    @State private var streamStatusMessage = "Looking for a playable stream..."
    @State private var streamError: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var streamRequestID = UUID()

    @MainActor
    init(isActive: Bool = true, matchListViewModel: MatchListViewModel? = nil,
         myMatchdayStore: MyMatchdayStore? = nil, onBrowseHome: @escaping () -> Void) {
        self.isActive = isActive
        self._matchListViewModel = State(initialValue: matchListViewModel ?? .shared)
        self._myMatchdayStore = State(initialValue: myMatchdayStore ?? .shared)
        self.onBrowseHome = onBrowseHome
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()

                ScrollViewReader { proxy in
                 ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                        matchdayHeader { target in
                            proxy.scrollTo(MatchdayDisplayLayout.ID.heading(target.id), anchor: .top)
                        }
                            .id("matchday-top")

                        matchdayScopePicker

                        if let notice = matchListViewModel.catalogNotice(displaying: matchdayProjection.rows.map(\.event)) {
                            CatalogRefreshNotice(message: notice, checkedAt: matchListViewModel.cplScheduleCheckedAt,
                                                 isRefreshing: matchListViewModel.isRefreshing) {
                                await refreshMatchday()
                            }
                        } else if matchdayProjection.hasFootball && liveScoreService.showsFootballFixtureRefresh() {
                            FootballFixtureRefreshProgress()
                        }

                        if remindedEventID != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    // The same destination serves saved-widget
                                    // links and notification taps. Opening it
                                    // does not imply reminder consent.
                                    Label("Your match", systemImage: "calendar")
                                        .font(FottyTheme.typeAction)
                                        .foregroundStyle(FottyTheme.accentText)
                                    Spacer()
                                    Button { self.remindedEventID = nil } label: {
                                        Text("Dismiss")
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(FottyPressButtonStyle())
                                }
                                if let row = reminderTarget {
                                    personalMatchRow(row)
                                } else {
                                    Text("This match is no longer saved. Browse Home for the latest schedule.")
                                        .font(FottyTheme.typeMeta)
                                        .foregroundStyle(FottyTheme.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("matchday-reminder-target")
                        }

                        if showKickoffClashes, let conflict = matchdayProjection.conflicts.first {
                            conflictBanner(conflict, additionalCount: max(matchdayProjection.conflicts.count - 1, 0))
                        }

                        if viewMode == .timeWindow, matchdayProjection.isReady {
                            viewingWindowContent
                        } else {
                            matchdayContent
                        }

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, FottyTheme.bentoInset)
                    .padding(.top, FottyTheme.spacingMD)
                }
                .refreshable {
                    await refreshMatchday()
                }
                .onChange(of: remindedEventID) { _, id in
                    if id != nil {
                        proxy.scrollTo("matchday-top", anchor: .top)
                    }
                }
                }

            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.fottyStreamLookupBusy, isFindingStream || (!viewing.isTwo && viewing.resolutionMessage != nil))
        .environment(\.fottySceneOwnsSingleWatch, !viewing.isTwo)
        .environment(\.fottyPendingWatchEventID, !viewing.isTwo ? viewing.pendingSingleEvent?.id : nil)
        .preference(key: FixturePreflightActivityPreferenceKey.self, value: isActive && isFindingStream)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let pending = viewing.pendingSingleEvent, let message = viewing.resolutionMessage {
                StreamResolutionPanel(sportCategory: pending.normalizedCategory,
                    competition: SportMotionContext.competition(for: pending), statusMessage: message,
                    subtitle: pending.displayTitle, isMultiStream: false, multiTitles: [],
                    onCancel: { viewing.cancelPendingSingleDiscovery() })
            } else if isFindingStream {
                StreamResolutionPanel(
                    sportCategory: streamEvent?.normalizedCategory ?? HomeSportsDiscovery.allSports,
                    competition: SportMotionContext.competition(for: streamEvent),
                    statusMessage: streamStatusMessage,
                    subtitle: streamEvent.map(eventTitle(_:)),
                    isMultiStream: false,
                    multiTitles: [],
                    onCancel: cancelStreamResolution
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
        .fullScreenCover(isPresented: $showsTeams) { TeamOnboardingView() }
        .sheet(item: $selectedCatalogEvent, onDismiss: completePendingDetailsAction) { event in
            let detailsEvent = CurrentEventBroadcastPolicy.currentEvent(for: event,
                in: matchListViewModel.playbackAdmissionCatalog) ?? event
            let action = CurrentEventBroadcastPolicy.action(for: event, in: matchListViewModel.playbackAdmissionCatalog,
                status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService))
            CatalogEventDetailsView(event: detailsEvent, onWatch: action.map { _ in {
                pendingDetailsWatch = event
                selectedCatalogEvent = nil
            } }, alternateActionTitle: action?.alternateActionTitle,
                onCheckStreams: optionalSourceCheckAction(for: event))
                .environment(liveScoreService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: showPlayer) { _, show in
            guard show else { return }
            if let streamEvent { viewing.open(event: streamEvent, sessions: streamSessions) }
            resetPlayerPresentation()
        }
        .task(id: matchdayProjectionKey) {
            await rebuildMatchdayProjection()
        }
        .task(id: isActive && scenePhase == .active) {
            matchListViewModel.configure(modelContext: modelContext)
            matchdayDate = Date()
            if isActive, viewMode == .timeWindow, !hasStartedViewingWindow { startViewingWindow() }
            guard !AppRuntime.isAutomatedTesting, isActive, scenePhase == .active else {
                liveScoreService.releasePolling(owner: scorePollingOwner)
                return
            }

            liveScoreService.updatePollingDemand(owner: scorePollingOwner, isActive: true)
            await matchListViewModel.refresh()
            matchdayDate = Date()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(90))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await matchListViewModel.refresh()
                matchdayDate = Date()
            }
        }
        .onDisappear {
            viewing.cancelPendingSingleDiscovery()
            pendingDetailsSourceCheck = nil
            viewing.cancelOptionalSourceLookup()
            liveScoreService.releasePolling(owner: scorePollingOwner)
            cancelStreamResolution()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                viewing.cancelPendingSingleDiscovery()
                pendingDetailsSourceCheck = nil
                viewing.cancelOptionalSourceLookup()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewing.cancelPendingSingleDiscovery()
                pendingDetailsSourceCheck = nil
                viewing.cancelOptionalSourceLookup()
            }
        }
        .onChange(of: showKickoffClashes) { _, _ in
            showsClashDetails = false
        }
        .onChange(of: viewingDurationRaw) { _, _ in
            if viewMode == .timeWindow { startViewingWindow() }
        }
        .onChange(of: viewMode) { _, mode in
            // Browsing the full schedule must not silently consume a window.
            // Returning to a chosen window does not slide its start forward.
            if mode == .timeWindow, !hasStartedViewingWindow { startViewingWindow() }
        }
        .onChange(of: navigation.pendingReminderID, initial: true) { _, id in
            guard let id else { return }
            remindedEventID = id
            navigation.pendingReminderID = nil
        }
    }

    private func matchdayHeader(onJump: @escaping (MatchdayDayNavigationPolicy.Target) -> Void) -> some View {
        CatalogAdaptiveHeading {
            Text("My Matchday")
                .font(.title.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

        } actions: {
          HStack(spacing: 12) {
            if viewMode == .fullMatchday, dayNavigationTargets.count > 1 {
                Menu {
                    ForEach(dayNavigationTargets) { target in
                        Button(target.title) { onJump(target) }
                    }
                } label: {
                    Label("Jump to", systemImage: "calendar")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(FottyTheme.typeAction)
                .accessibilityLabel("Jump to a Matchday section")
                .accessibilityIdentifier("matchday-day-jump")
            }
            Button(action: onBrowseHome) {
                Text("Browse")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle())
            .accessibilityLabel("Browse matches on Home")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A scope control, not a screen-wide banner. At accessibility sizes the
    /// native menu retains both complete mode names without squeezing labels.
    private var matchdayScopePicker: some View {
        MatchdayScopeControl(selection: $viewMode, usesWideLayout: usesWideLayout)
    }

    // MARK: - Optional viewing window

    private var viewingDuration: ViewingPlanDuration { .saved(viewingDurationRaw) }

    private var viewingPlan: ViewingPlanPolicy.Projection {
        viewingPlanProjection ?? ViewingPlanPolicy.project([], duration: viewingDuration,
            windowStart: viewingWindowStart, at: matchdayDate)
    }

    private func makeViewingPlan(from rows: [MatchdayRowPresentation]) -> ViewingPlanPolicy.Projection {
        ViewingPlanPolicy.project(rows.map { row in
            let phase: ViewingPlanPolicy.Phase
            switch row.section {
            case .live: phase = .live
            case .listedNow: phase = .listed
            case .upcoming: phase = .upcoming
            case .awaitingConfirmation, .timeToBeConfirmed, .recent, .channel: phase = .excluded
            }
            return .init(id: row.id, start: row.event.kickoffDate, phase: phase,
                         isChannel: row.event.isBroadcastChannel,
                         hasIdentityConflict: row.event.hasCatalogIdentityConflict)
        }, duration: viewingDuration, windowStart: viewingWindowStart, at: matchdayDate)
    }

    private var viewingWindowContent: some View {
        let plan = viewingPlan
        let rows = Dictionary(uniqueKeysWithValues: matchdayProjection.rows.map { ($0.id, $0) })
        let current = plan.currentIDs.compactMap { rows[$0] }.filter { $0.id != reminderTarget?.id }
        let upcoming = plan.upcomingIDs.compactMap { rows[$0] }.filter { $0.id != reminderTarget?.id }
        return VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your viewing window")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Saved matches and your interests, within the time you have.")
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if usesWideLayout {
                HStack(alignment: .top, spacing: FottyTheme.spacingLG) {
                    windowFixtures(current: current, upcoming: upcoming, plan: plan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    viewingWindowControls(plan: plan)
                        .frame(width: 280, alignment: .leading)
                }
            } else {
                viewingWindowControls(plan: plan)
                windowFixtures(current: current, upcoming: upcoming, plan: plan)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matchday-time-window")
    }

    private func viewingWindowControls(plan: ViewingPlanPolicy.Projection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available time")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)

            MatchdayDurationControl(selection: $viewingDurationRaw, usesWideLayout: usesWideLayout)

            Label {
                Text("\(plan.windowStart.formatted(date: .omitted, time: .shortened))–\(plan.windowEnd.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(FottyTheme.textSecondary)
            .accessibilityLabel("Your viewing window, from \(plan.windowStart.formatted(date: .omitted, time: .shortened)) to \(plan.windowEnd.formatted(date: .omitted, time: .shortened))")

            Text(viewingDuration == .evening
                 ? "Until local midnight. This is your viewing window, not the match's finish time."
                 : "Your viewing window, not the match's finish time.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        }
        .padding(FottyTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(FottyTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func windowFixtures(current: [MatchdayRowPresentation], upcoming: [MatchdayRowPresentation],
                                 plan: ViewingPlanPolicy.Projection) -> some View {
        if plan.hasEnded {
            EmptyStateView(icon: "clock", title: "Your viewing window has ended",
                           message: "Choose a new window, or see your Full Matchday.",
                           actionTitle: "Start a new window", action: startViewingWindow)
                .accessibilityIdentifier("matchday-restart-window")
        } else if matchdayProjection.rows.isEmpty {
            matchdayEmptyState
        } else if current.isEmpty && upcoming.isEmpty && plan.count > 0 {
            // A selected reminder is already shown above; do not contradict it
            // with an empty-window message or render the same row twice.
            EmptyView()
        } else if current.isEmpty && upcoming.isEmpty {
            EmptyStateView(icon: "calendar.badge.clock", title: "Nothing in this window",
                           message: "Try a longer window, or see all your saved and followed matches.",
                           actionTitle: "Show Full Matchday", action: { viewMode = .fullMatchday })
        } else {
            VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                if !current.isEmpty {
                    windowGroup(title: "On now", rows: current)
                }
                if !upcoming.isEmpty {
                    windowGroup(title: "Up next", rows: upcoming)
                }
            }
        }
    }

    private func windowGroup(title: String, rows: [MatchdayRowPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FottySectionHeader(title: title, count: rows.count)
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    personalMatchRow(row, showsReason: false)
                        .background(FottyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
                }
            }
        }
    }

    private func startViewingWindow() {
        let now = Date()
        hasStartedViewingWindow = true
        viewingWindowStart = now
        matchdayDate = now
        viewingPlanProjection = makeViewingPlan(from: matchdayProjection.rows)
    }

    @ViewBuilder
    private var matchdayContent: some View {
        if !matchdayProjection.isReady {
            ProgressView()
                .tint(FottyTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("Loading Matchday")
        } else if matchdayProjection.rows.isEmpty {
            matchdayEmptyState
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matchdayDisplayEntries) { entry in
                    matchdayEntry(entry)
                }
            }
        }
    }

    private var matchdayDisplayEntries: [MatchdayDisplayLayout.Entry<MatchdayRowPresentation>] {
        typealias Section = MatchdayDisplayLayout.Section<MatchdayRowPresentation>
        // An ongoing Test may be at lunch or stumps. Keep it visible without
        // calling the entire lifecycle active play or stopping its broadcast.
        let includesCricketInterval = matchdayProjection.live.contains {
            CricketActivityPresentationPolicy.activity(for: $0.event, at: Date())?.suppressesLiveBadge == true
        }
        var sections = [
            Section(id: "live", title: includesCricketInterval ? "In progress" : "Live now", subtitle: nil, items: matchdayProjection.live),
            Section(id: "listed", title: "Broadcast listed", subtitle: nil, items: matchdayProjection.listedNow),
            Section(id: "next", title: "Next up", subtitle: nil, items: matchdayProjection.nextUp)
        ]
        sections += matchdayProjection.laterDays.map {
            Section(id: "day-\($0.date.timeIntervalSinceReferenceDate)",
                    title: $0.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    subtitle: nil, items: $0.rows)
        }
        sections += [
            Section(id: "channels", title: "Saved channels", subtitle: nil, items: matchdayProjection.channels),
            Section(id: "unconfirmed-time", title: "Time to be confirmed", subtitle: nil, items: matchdayProjection.timeToBeConfirmed),
            Section(id: "awaiting", title: "Awaiting confirmation", subtitle: nil, items: matchdayProjection.awaitingConfirmation),
            Section(id: "recent", title: "Recent", subtitle: nil, items: matchdayProjection.recent)
        ]
        return MatchdayDisplayLayout.entries(
            sections: sections, columns: usesWideLayout ? 2 : 1, excluding: reminderTarget?.id,
            reason: { $0.reason }, isChannel: { $0.event.isBroadcastChannel }
        )
    }

    private var dayNavigationTargets: [MatchdayDayNavigationPolicy.Target] {
        MatchdayDayNavigationPolicy.targets(sections: matchdayDisplayEntries.compactMap { entry in
            guard case .heading(let heading) = entry else { return nil }
            return .init(id: heading.sectionID, title: heading.title)
        })
    }

    @ViewBuilder
    private func matchdayEntry(_ entry: MatchdayDisplayLayout.Entry<MatchdayRowPresentation>) -> some View {
        switch entry {
        case .heading(let heading):
            FottySectionHeader(title: heading.title, count: heading.count, subtitle: heading.subtitle)
                .padding(.top, heading.isFirstSection ? 0 : FottyTheme.spacingLG)
                .padding(.bottom, 8)
        case .fixtures(let gridRow):
            let wide = gridRow.columns > 1
            VStack(spacing: 0) {
                if !gridRow.isFirst && !wide { Divider().padding(.horizontal, 12) }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(gridRow.items) { row in
                        personalMatchRow(row, showsReason: gridRow.showsReason)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FottyTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                if wide {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(FottyTheme.border, lineWidth: 1)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    if wide && gridRow.items.count == 1 {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 0, maxHeight: 0).accessibilityHidden(true)
                    }
                }
            }
            .background(wide ? Color.clear : FottyTheme.surface)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: wide || gridRow.isFirst ? 16 : 0,
                bottomLeadingRadius: wide || gridRow.isLast ? 16 : 0,
                bottomTrailingRadius: wide || gridRow.isLast ? 16 : 0,
                topTrailingRadius: wide || gridRow.isFirst ? 16 : 0
            ))
            .padding(.bottom, wide && !gridRow.isLast ? 16 : 0)
        }
    }

    private func personalMatchRow(_ row: MatchdayRowPresentation, showsReason: Bool = true) -> some View {
        let event = row.event
        return VStack(alignment: .leading, spacing: 5) {
            LiveEventCard(
                event: event,
                onWatchTap: row.action == nil ? nil : {
                    if let action = row.action { watchEvent(action.event) }
                },
                alternateActionTitle: row.action?.alternateActionTitle,
                onDetailsTap: { presentModal { selectedCatalogEvent = event } },
                onCheckStreams: row.isInCurrentSchedule && !viewing.isTwo ? { checkSources(for: event) } : nil,
                isSaved: row.savedRecord != nil,
                onSaveTap: { toggleSavedMatch(event) },
                grouped: true
            )
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
            .accessibilityHint(
                row.action != nil
                    ? (row.action?.isChannelFallback == true
                        ? "Opens the preferred cricket channel. Its current programme is not confirmed."
                        : "Checks the available broadcast")
                    : "Opens match information"
            )
            if showsReason {
                Divider().overlay(FottyTheme.border).padding(.horizontal, 12)
                Label(row.reason, systemImage: row.reasonIcon)
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    .padding(.bottom, 10)
            }
            if let saved = row.savedRecord, saved.previousDate != nil || !row.isInCurrentSchedule {
                VStack(alignment: .leading, spacing: 5) {
                    if saved.previousDate != nil {
                        Text("Start time changed · \(event.kickoffDate?.arenaKickoffDetailLine() ?? "Time to be confirmed")")
                            .accessibilityIdentifier("matchday-rescheduled-\(event.id)")
                    }
                    if !row.isInCurrentSchedule {
                        Text("No longer in the current schedule. Pull to refresh.")
                    }
                }
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .accessibilityIdentifier("matchday-row-\(event.id)")
    }

    private var matchdayEmptyState: some View {
        let hasPreferences = !followedTeams.isEmpty || !followedLeagues.isEmpty
            || !followedSportIDs.isEmpty
            || !myMatchdayStore.savedMatches.isEmpty
        return VStack(spacing: 8) {
          EmptyStateView(
            icon: hasPreferences ? "calendar.badge.clock" : "bookmark",
            title: hasPreferences ? "Nothing on your matchday yet" : "Build your matchday",
            message: hasPreferences
                ? "Nothing from your saved matches or interests is scheduled right now."
                : "Save matches or choose sports, competitions and teams to see them here.",
            actionTitle: "Browse Home",
            action: onBrowseHome
          )
          if followedTeams.isEmpty {
              Button { presentModal { showsTeams = true } } label: {
                  Text("Follow a team")
                      .frame(minWidth: 44, minHeight: 44)
                      .contentShape(Rectangle())
              }
              .buttonStyle(FottyPressButtonStyle())
              .accessibilityIdentifier("matchday-follow")
          }
        }
        .tint(FottyTheme.accentText)
        .frame(maxWidth: .infinity)
    }

    private func conflictBanner(_ conflict: MatchdayConflict, additionalCount: Int) -> some View {
        DisclosureGroup(isExpanded: $showsClashDetails) {
            Text(conflictMessage(conflict, additionalCount: additionalCount))
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
          HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.fottyScaled(size: 16, weight: .bold))
                .foregroundStyle(FottyTheme.accentText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Kickoff clash")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.textPrimary)

            }

            Spacer(minLength: 0)
          }
          .frame(minHeight: 44)
        }
        .tint(FottyTheme.accentText)
        .accessibilityIdentifier("matchday-clash-details")
        .padding(FottyTheme.spacingMD)
        .bentoSurface(cornerRadius: FottyTheme.radiusMD)
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        }
    }

    // MARK: - Personal catalog

    private var followedSportIDs: Set<String> {
        SportsInterestPreferences.canonicalIDs(from: followedSportIDsRaw)
    }

    private var matchdayProjectionKey: MatchdayProjectionKey {
        MatchdayProjectionKey(
            catalogRevision: matchListViewModel.contentRevision,
            scoreRevisionMilliseconds: Int64((liveScoreService.lastRefresh?.timeIntervalSince1970 ?? 0) * 1_000),
            minuteBucket: Int64(matchdayDate.timeIntervalSince1970 / 60),
            savedRevision: myMatchdayStore.contentRevision,
            followedTeams: followedTeams.map { "\($0.key)|\($0.teamName)|\($0.sportCategory)" }.sorted(),
            followedLeagues: followedLeagues.map { "\($0.id)|\($0.leagueName)|\($0.sportCategory)" }.sorted(),
            showKickoffClashes: showKickoffClashes,
            followedSports: followedSportIDs.sorted(),
            registryRevision: BroadcastRegistryClient.shared.snapshot?.revision,
            discoveryRevision: FixtureStreamDiscoveryIndex.shared.revision,
            listingRevision: FixtureCatalogAvailabilityIndex.shared.revision,
            enabledSources: FixtureStreamDiscoveryIndex.shared.enabledProviderCodes
        )
    }

    private var reminderTarget: MatchdayRowPresentation? {
        guard let remindedEventID,
              myMatchdayStore.contains(eventID: remindedEventID) else { return nil }
        return matchdayProjection.rows.first {
            $0.id == remindedEventID || myMatchdayStore.records(for: $0.event).contains { $0.id == remindedEventID }
        }
    }

    private func rebuildMatchdayProjection() async {
        let signpostState = FottyPerformanceTrace.catalog.beginInterval("MatchdayProjection")
        defer { FottyPerformanceTrace.catalog.endInterval("MatchdayProjection", signpostState) }

        let requestKey = matchdayProjectionKey
        let now = matchdayDate
        let providerMatches = matchListViewModel.matches
        let officialMatches = liveScoreService.analysisMatches
        let admissionCatalog = CurrentEventBroadcastPolicy.IndexedCatalog(matchListViewModel.playbackAdmissionCatalog, at: now)
        let savedRecords = myMatchdayStore.savedMatches
        // Freeze value selection/date/receipt inputs before the first suspension.
        let selection = SportsPersonalizationPolicy.prepareSelection(
            teams: followedTeams, leagues: followedLeagues, sports: followedSportIDs)
        let teamKeys = selection.teamKeys
        let sportIDs = selection.sportIDs
        let hasLeagueFollows = !followedLeagues.isEmpty
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        let officialChampionsLeague = AnalyticalDataEngine.officialScheduleEvents(
            from: officialMatches,
            competition: .championsLeague
        )
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        let catalog = AnalyticalDataEngine.deduplicateMatches(
            providerMatches + officialChampionsLeague
        )
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        var rowsByID: [String: MatchdayRowPresentation] = [:]
        rowsByID.reserveCapacity(savedRecords.count + 24)
        var representedSavedIDs = Set<String>()

        func makeRow(
            for event: AnalyticalDataEngine.EventReference,
            isInCurrentSchedule: Bool,
            savedRecord: SavedMatchRecord?
        ) -> MatchdayRowPresentation? {
            let canBeFollowed = !event.isBroadcastChannel && !event.hasCatalogIdentityConflict
            let teamFollowed = canBeFollowed && (
                teamKeys.contains(TeamFollowKey.make(name: event.homeName, category: event.normalizedCategory))
                    || teamKeys.contains(TeamFollowKey.make(name: event.awayName, category: event.normalizedCategory))
            )
            let sportFollowed = canBeFollowed && sportIDs.contains(event.normalizedCategory)

            // Official matching is needed once per candidate, not repeatedly by
            // each section, row and sort comparison during SwiftUI rendering.
            let needsOfficialMatch = event.normalizedCategory == "football"
                && (savedRecord != nil || teamFollowed || sportFollowed || hasLeagueFollows)
            let officialMatch = needsOfficialMatch
                ? liveScoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)
                : nil
            let followedLeagueName = canBeFollowed && hasLeagueFollows
                ? SportsPersonalizationPolicy.followedLeagueName(
                    for: event,
                    in: selection,
                    officialMatch: officialMatch
                )
                : nil
            let isFollowed = teamFollowed || followedLeagueName != nil || sportFollowed
            guard savedRecord != nil || isFollowed else { return nil }

            let status = officialMatch.flatMap {
                liveScoreService.currentStatus(for: $0, at: now)
            }
            let section = MatchdayEventStatePolicy.section(for: event, at: now, status: status)
            let reason: String = {
                let followedReason = followedLeagueName.map { "Following \($0)" }
                    ?? (teamFollowed ? "Followed team"
                        : "Following \(AnalyticalDataEngine.categoryDisplayName(for: event.normalizedCategory))")
                if savedRecord != nil, isFollowed { return "Saved · \(followedReason)" }
                if savedRecord != nil { return event.isBroadcastChannel ? "Saved channel" : "Saved match" }
                return followedReason
            }()

            return MatchdayRowPresentation(
                event: event,
                reason: reason,
                reasonIcon: savedRecord == nil ? "star.fill" : "bookmark.fill",
                action: CurrentEventBroadcastPolicy.action(for: event, in: admissionCatalog.candidates(for: event),
                    at: now, status: status),
                savedRecord: savedRecord,
                isInCurrentSchedule: isInCurrentSchedule,
                section: section
            )
        }

        for (index, event) in catalog.enumerated() {
            guard !Task.isCancelled else { return }
            let matchingSaved = myMatchdayStore.records(for: event)
            if let row = makeRow(for: event, isInCurrentSchedule: true,
                                 savedRecord: matchingSaved.min { $0.savedAt < $1.savedAt }) {
                rowsByID[event.id] = row
                representedSavedIDs.formUnion(matchingSaved.map(\.id))
            }
            if (index + 1).isMultiple(of: 16) {
                guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
            }
        }
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        for (index, record) in savedRecords.enumerated() {
            guard !Task.isCancelled else { return }
            if !representedSavedIDs.contains(record.id),
               let row = makeRow(for: record.event, isInCurrentSchedule: false, savedRecord: record) {
                rowsByID[record.id] = row
            }
            if (index + 1).isMultiple(of: 16) {
                guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
            }
        }

        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        let rows = rowsByID.values.sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive { return lhs.isLive }
            return (lhs.event.kickoffDate ?? .distantFuture) < (rhs.event.kickoffDate ?? .distantFuture)
        }
        let live = rows.filter { $0.isLive && !$0.isFinished }
        let recent = rows.filter(\.isFinished).sorted {
            ($0.event.kickoffDate ?? .distantPast) > ($1.event.kickoffDate ?? .distantPast)
        }
        let upcoming = rows.filter { $0.section == .upcoming }
        let nextCutoff = now.addingTimeInterval(6 * 3_600)
        let nextUp = upcoming.filter {
            guard let kickoff = $0.event.kickoffDate else { return false }
            return kickoff <= nextCutoff
        }
        let nextIDs = Set(nextUp.map(\.id))
        let later = upcoming.filter { !nextIDs.contains($0.id) }
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        let calendar = Calendar.current
        let groupedLater = Dictionary(grouping: later.compactMap { row -> (Date, MatchdayRowPresentation)? in
            guard let kickoff = row.event.kickoffDate else { return nil }
            return (calendar.startOfDay(for: kickoff), row)
        }, by: \.0)
        let laterDays = groupedLater.keys.sorted().map { day in
            MatchdayDaySection(date: day, rows: groupedLater[day, default: []].map(\.1))
        }
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }
        let conflicts = requestKey.showKickoffClashes ? makeKickoffConflicts(from: rows, now: now) : []

        let projection = MatchdayProjection(
            isReady: true,
            rows: rows,
            live: live,
            listedNow: rows.filter { $0.section == .listedNow },
            nextUp: nextUp,
            laterDays: laterDays,
            channels: rows.filter { $0.section == .channel },
            timeToBeConfirmed: rows.filter { $0.section == .timeToBeConfirmed },
            awaitingConfirmation: rows.filter { $0.section == .awaitingConfirmation },
            recent: recent,
            conflicts: conflicts,
            hasFootball: rows.contains { $0.event.normalizedCategory == "football" }
        )
        guard await HomeProjectionWorkPolicy.checkpoint(isCurrent: { matchdayProjectionKey == requestKey }) else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            matchdayProjection = projection
            viewingPlanProjection = makeViewingPlan(from: projection.rows)
        }
    }

    // MARK: - Clash detection

    private func makeKickoffConflicts(
        from rows: [MatchdayRowPresentation],
        now: Date
    ) -> [MatchdayConflict] {
        let earliest = now.addingTimeInterval(-15 * 60)
        let candidates = rows
            .filter { !$0.isFinished }
            .map(\.event)
            .filter { ($0.kickoffDate ?? .distantPast) >= earliest }
            .sorted { ($0.kickoffDate ?? .distantFuture) < ($1.kickoffDate ?? .distantFuture) }

        var conflicts: [MatchdayConflict] = []
        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                guard let firstKickoff = candidates[firstIndex].kickoffDate,
                      let secondKickoff = candidates[secondIndex].kickoffDate else { continue }
                let gap = secondKickoff.timeIntervalSince(firstKickoff)
                guard let duration = candidates[firstIndex].estimatedMatchDuration else { continue }
                if gap >= duration { break }
                conflicts.append(
                    MatchdayConflict(
                        first: candidates[firstIndex],
                        second: candidates[secondIndex],
                        minutesApart: max(Int(gap / 60), 0)
                    )
                )
            }
        }
        return conflicts
    }

    private func conflictMessage(_ conflict: MatchdayConflict, additionalCount: Int) -> String {
        let timing: String
        if conflict.minutesApart == 0, let date = conflict.first.kickoffDate {
            timing = "both start \(date.formatted(date: .abbreviated, time: .shortened))"
        } else {
            timing = "start \(conflict.minutesApart) minutes apart"
        }
        let base = "\(eventTitle(conflict.first)) and \(eventTitle(conflict.second)) \(timing)."
        guard additionalCount > 0 else { return base + " You may need to choose which one to watch live." }
        return base + " \(additionalCount) more clash\(additionalCount == 1 ? "" : "es") detected."
    }

    // MARK: - Actions and playback

    private func refreshMatchday() async {
        async let catalogRefresh: Void = matchListViewModel.refresh()
        async let scoreRefresh: Void = liveScoreService.refresh(force: true)
        _ = await (catalogRefresh, scoreRefresh)
        matchdayDate = Date()
    }

    private func toggleSavedMatch(_ event: AnalyticalDataEngine.EventReference) {
        HapticManager.impact(.light)
        withAnimation(FottyTheme.springSnappy) {
            if let message = myMatchdayStore.toggle(event).errorMessage {
                savedMatchError = message
            }
        }
    }

    private func optionalSourceCheckAction(for event: EventReference) -> (() -> Void)? {
        guard isActive, scenePhase == .active, !isFindingStream, !viewing.isTwo else { return nil }
        return {
            guard isActive, scenePhase == .active, !isFindingStream, !viewing.isTwo else { return }
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
        if !viewing.isTwo {
            guard isActive else { return }
            watchEvent(event)
            return
        }
        guard isActive,
              let action = CurrentEventBroadcastPolicy.action(for: event, in: matchListViewModel.playbackAdmissionCatalog,
                status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)) else { return }
        watchEvent(action.event)
    }

    private func checkSources(for event: EventReference) {
        guard isActive, scenePhase == .active, !isFindingStream, !viewing.isTwo else { return }
        viewing.checkOptionalSources(for: event, discover: { request, publish in
            await LiveStreamResolver.shared.resolvePlayback(for: request, onChoices: publish)
        }) { requested, phase in
            let sceneOwned = phase == .completion && viewing.hasMountedOptionalSourceLookup(for: requested)
            guard !Task.isCancelled, !viewing.isTwo,
                  sceneOwned || (isActive && scenePhase == .active && !isFindingStream) else { return nil }
            let codes = Set(await StreamPluginRegistry.shared.enabledProviderCodes())
            let stillSceneOwned = phase == .completion && viewing.hasMountedOptionalSourceLookup(for: requested)
            guard !Task.isCancelled, !viewing.isTwo,
                  stillSceneOwned || (isActive && scenePhase == .active && !isFindingStream) else { return nil }
            let now = Date()
            return OptionalSourceLookupPolicy.event(for: requested,
                in: matchListViewModel.playbackAdmissionCatalog, enabledProviderCodes: codes, at: now,
                status: MatchStartPolicy.currentStatus(for: requested, scores: liveScoreService, now: now), phase: phase)
        }
    }

    private func watchEvent(_ event: AnalyticalDataEngine.EventReference) {
        pendingDetailsSourceCheck = nil
        viewing.cancelOptionalSourceLookup()
        if !viewing.isTwo {
            guard !isFindingStream else { return }
            HapticManager.impact(.light)
            MatchPlaybackFeedback.shared.attempting(event.id)
            streamError = nil
            viewing.watchSingle(event, admission: { requested in
                guard isActive, scenePhase == .active, !isFindingStream else { return nil }
                return CurrentEventBroadcastPolicy.action(for: requested, in: matchListViewModel.playbackAdmissionCatalog,
                    status: MatchStartPolicy.currentStatus(for: requested, scores: liveScoreService))?.event
            })
            return
        }
        guard playbackTimingAllows(event) else { return }
        guard !(isFindingStream && streamEvent?.id == event.id) else { return }
        if viewing.reopenRetainedSingle(event: event, catalog: matchListViewModel.playbackCatalog,
            status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)) {
            if isFindingStream { cancelStreamResolution() }
            streamError = nil
            HapticManager.impact(.light)
            return
        }
        HapticManager.impact(.light)
        MatchPlaybackFeedback.shared.attempting(event.id)
        streamError = nil
        viewing.watchSingle(event)
    }


    private func presentModal(_ action: () -> Void) {
        viewing.cancelPendingSingleDiscovery()
        pendingDetailsSourceCheck = nil
        viewing.cancelOptionalSourceLookup()
        if isFindingStream { cancelStreamResolution() }
        action()
    }

    private func cancelStreamResolution() {
        streamTask?.cancel()
        let pendingEvent = streamEvent
        streamRequestID = UUID()
        isFindingStream = false
        streamStatusMessage = "Looking for a playable stream..."
        if !showPlayer {
            streamEvent = nil
            streamSessions = []
        }
        if let pendingEvent {
            Task {
                await LiveStreamResolver.shared.cancelAttempt(
                    for: StreamPlaybackRequest(event: pendingEvent)
                )
            }
        }
    }

    private func playbackTimingAllows(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        MatchStartPolicy(event: event,
            status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)).timingAllowsPlayback
    }

    private func resetPlayerPresentation() {
        streamEvent = nil
        streamSessions = []
        showPlayer = false
    }

    private func eventTitle(_ event: AnalyticalDataEngine.EventReference) -> String {
        event.displayTitle
    }
}

private struct MatchdayConflict: Identifiable {
    let first: AnalyticalDataEngine.EventReference
    let second: AnalyticalDataEngine.EventReference
    let minutesApart: Int

    var id: String { "\(first.id)|\(second.id)" }
}
