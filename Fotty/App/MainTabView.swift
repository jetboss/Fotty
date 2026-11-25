import SwiftUI
import SwiftData

/// A browsing destination may hold an older local lookup/selection owner before
/// a scene player mounts. The scene's one preflight owner yields to it as well.
struct FixturePreflightActivityPreferenceKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct MainTabView: View {
    @AppStorage("fotty.selectedTab") private var persistedTabRawValue = ""
    @State private var selectedTab: Tab = MainTabView.initialTab
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LiveScoreService.self) private var liveScoreService
    @State private var matchNavigationStore = MatchNavigationStore.shared
    @StateObject private var fplSession = FPLWorkspaceSession()
    @State private var followMigrationError: String?
    @State private var viewingSession = ViewingSessionCoordinator()
    @State private var sourcePreflightSchedule = FixtureStreamPreflightSchedule()
    @State private var sourcePreflightIsLocallyBlocked = false

    private var canPreflightSourceMetadata: Bool {
        scenePhase == .active && selectedTab != .fpl && viewingSession.panes.isEmpty
            && viewingSession.resolutionMessage == nil && viewingSession.pendingSingleEvent == nil
            && !sourcePreflightIsLocallyBlocked
    }

    private var sourcePreflightTaskKey: String {
        // Ordinary sports-tab changes, Search presentation and catalog revisions
        // do not replace the owner or reset its retained90-second reservation.
        "\(canPreflightSourceMetadata)-\(FixtureCatalogAvailabilityIndex.shared.enablementRevision)"
    }

    private var sourceCatalogTaskKey: String {
        "\(scenePhase == .active)-\(FixtureCatalogAvailabilityIndex.shared.enablementRevision)"
    }

    private var sourceCatalogFixtureKey: String {
        let catalog = MatchListViewModel.shared
        return "\(catalog.contentRevision)-\(catalog.fixtureCatalogRevision)"
    }
    
    enum Tab: String, CaseIterable {
        case home = "Home"
        case tv = "TV"
        // Keep the persisted raw value so existing installs retain their selected tab.
        case social = "Arena"
        case fpl = "FPL"
        
        var displayName: String {
            switch self {
            case .home: return "Home"
            case .tv: return "TV"
            case .social: return "Matchday"
            case .fpl: return "FPL"
            }
        }
        
        var icon: String {
            switch self {
            case .home: return "house"
            case .tv: return "tv"
            case .social: return "calendar"
            case .fpl: return "chart.line.uptrend.xyaxis"
            }
        }
        
    }
    
    private static var initialTab: Tab { .home }
    
    @Query private var followedTeams: [FollowedTeamItem]
    @Query private var followedLeagues: [FollowedLeagueItem]
    @State private var isTabBarVisible = true
    @State private var showsSettings = false

    private var followedAlertSignature: String {
        followedTeams
            .map { "\($0.key):\(($0.alertsEnabled ?? true) ? "1" : "0")" }
            .sorted()
            .joined(separator: "|")
    }

    private var sportsInterestSignature: String {
        followedTeams.map { $0.key }.sorted().joined(separator: "|") + ";" +
            followedLeagues.map { $0.id }.sorted().joined(separator: "|")
    }

    private var followMigrationErrorIsPresented: Binding<Bool> {
        Binding(
            get: { followMigrationError != nil },
            set: { if !$0 { followMigrationError = nil } }
        )
    }

    var body: some View {
        ViewingSessionShell(viewing: viewingSession) { tabContent }
        // Let the background extend under system chrome without letting that
        // chrome change the content's safe-area proposal on iPhone or iPad.
        .background(FottyTheme.background.ignoresSafeArea())
        // FPL has inline editors and the Coach composer. Let the system shrink
        // their available space above a docked software keyboard; do not replace
        // the selected view tree or add keyboard-height observers/padding.
        .ignoresSafeArea(selectedTab == .fpl ? [] : .keyboard, edges: .bottom)
        .fottyAdaptiveWindow()
        .fullScreenCover(isPresented: Binding(
            get: { matchNavigationStore.pendingMatchID != nil },
            set: { if !$0 { matchNavigationStore.pendingMatchID = nil } }
        )) {
            if let matchID = matchNavigationStore.pendingMatchID {
                NavigationStack {
                    MatchHubView(fixtureId: matchID, showModalDismissButton: true)
                        .environment(liveScoreService)
                }
            }
        }
        .onAppear {
            MatchAlertPreferences.synchronize(from: followedTeams)
            // Drop unknown/retired persisted tab ids back to Home.
            if let persisted = Tab(rawValue: persistedTabRawValue) {
                selectedTab = persisted
            } else if !persistedTabRawValue.isEmpty {
                selectedTab = .home
                persistedTabRawValue = Tab.home.rawValue
            }
            if matchNavigationStore.pendingReminderID != nil { selectedTab = .social }
            if matchNavigationStore.pendingFPL { openPendingFPLDestination() }
        }
        .onChange(of: matchNavigationStore.pendingReminderID) { _, id in
            if id != nil { selectedTab = .social }
        }
        .onChange(of: matchNavigationStore.pendingFPL) { _, pending in
            if pending { openPendingFPLDestination() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("tabBarVisibilityChanged"))) { notification in
            if let isVisible = notification.userInfo?["isVisible"] as? Bool {
                withAnimation(reduceMotion ? nil : FottyTheme.springSnappy) {
                    isTabBarVisible = isVisible
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FottyPrivateBackupService.restoredNotification)) { _ in
            migrateFollowedTeamKeysIfNeeded()
            fplSession.resetNavigation()
            let managerID = UserDefaults.standard.integer(forKey: "fotty.user.fplManagerId")
            if managerID > 0 {
                fplSession.viewModel.requestManagerConfirmation(managerID: managerID)
            } else {
                fplSession.viewModel.clearManagerId()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            persistedTabRawValue = newValue.rawValue
            withAnimation(reduceMotion ? nil : FottyTheme.springSnappy) {
                isTabBarVisible = true
            }
        }
        .onChange(of: persistedTabRawValue) { _, newValue in
            guard let target = Tab(rawValue: newValue) else { return }
            guard selectedTab != target else { return }
            selectedTab = target
        }
        .onChange(of: followedAlertSignature) { _, _ in
            MatchAlertPreferences.synchronize(from: followedTeams)
        }
        .onOpenURL { url in
            if url.scheme == "fotty", url.host == "sports-plan" {
                viewingSession.minimize()
                selectedTab = .social
            } else if url.scheme == "fotty", url.host == "matchday" {
                viewingSession.minimize()
                selectedTab = .social
                matchNavigationStore.pendingReminderID = url.pathComponents.dropFirst().first
            } else if FottyDeepLinkDestination.parse(url) == .fpl {
                selectedTab = .fpl
            } else {
                matchNavigationStore.open(url: url)
            }
        }
        .onContinueUserActivity(SportsHandoffIdentity.activityType) { activity in
            Task { await viewingSession.receiveHandoff(activity) }
        }
        .task(id: viewingSession.handoffPublisher.offeredIdentity?.expiresAt) {
            guard let expiry = viewingSession.handoffPublisher.offeredIdentity?.expiresAt else { return }
            do { try await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow))) }
            catch { return }
            viewingSession.handoffPublisher.expireIfNeeded()
        }
        .task {
            await StreamPluginRegistry.shared.refreshDiscoveryAvailability()
            guard !Task.isCancelled else { return }
            migrateFollowedTeamKeysIfNeeded()
            if !AppRuntime.isAutomatedTesting, !LocalDataStore.shared.isUsingVolatileFallback {
                SportsContinuityBridge.shared.configure(modelContext: modelContext)
            }
        }
        .onChange(of: sportsInterestSignature) { _, _ in
            if !AppRuntime.isAutomatedTesting, !LocalDataStore.shared.isUsingVolatileFallback {
                SportsContinuityBridge.shared.publishLocalSnapshot()
            }
        }
        .alert("Saved follows", isPresented: followMigrationErrorIsPresented) {
            Button("OK", role: .cancel) { followMigrationError = nil }
        } message: {
            Text(followMigrationErrorMessage)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, !AppRuntime.isAutomatedTesting else { return }
            SportsReminderBackgroundRefresh.shared.scheduleIfNeeded()
        }
        .onPreferenceChange(FixturePreflightActivityPreferenceKey.self) { isBlocked in
            sourcePreflightIsLocallyBlocked = isBlocked
        }
        .onChange(of: MatchReminderStore.shared.records) { _, _ in
            guard !AppRuntime.isAutomatedTesting else { return }
            SportsReminderBackgroundRefresh.shared.scheduleIfNeeded()
        }
        .onChange(of: sourceCatalogFixtureKey) { _, _ in
            guard !AppRuntime.isAutomatedTesting else { return }
            // Revoke corrected/terminal identities immediately without cancelling
            // unaffected catalog reads or spending their refresh budget again.
            FixtureCatalogAvailabilityIndex.shared.replaceFixtures(
                MatchListViewModel.shared.sourceCatalogRequests(at: Date()), at: Date())
        }
        .task(id: sourceCatalogTaskKey) {
            guard scenePhase == .active, !AppRuntime.isAutomatedTesting else { return }
            await StreamPluginRegistry.shared.refreshDiscoveryAvailability()
            let catalog = MatchListViewModel.shared
            catalog.configure(modelContext: modelContext)
            while !Task.isCancelled {
                let now = Date()
                await BroadcastRegistryClient.shared.refresh(at: now)
                guard !Task.isCancelled else { return }
                let requests = catalog.sourceCatalogRequests(at: now)
                await FixtureSourceCatalogCollector.refresh(requests: requests,
                    lanes: FixtureSourceCatalogCollector.lanes(
                        registrySnapshot: BroadcastRegistryClient.shared.cachedSnapshot(at: now), requests: requests),
                    at: now)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .task(id: sourcePreflightTaskKey) {
            guard !AppRuntime.isAutomatedTesting, canPreflightSourceMetadata else { return }
            while !Task.isCancelled {
                let codes = Set(await StreamPluginRegistry.shared.enabledProviderCodes())
                guard !Task.isCancelled, canPreflightSourceMetadata else { return }
                let now = Date()
                let catalog = MatchListViewModel.shared
                let admission = catalog.playbackAdmissionCatalog
                let eligible = catalog.sourceCatalogRequests(at: now).compactMap { request in
                    request.preferredEvent.flatMap { event in
                        OptionalSourceLookupPolicy.event(for: event, in: admission,
                            enabledProviderCodes: codes, at: now, phase: .preflight)
                    }
                }
                if let nextID = sourcePreflightSchedule.takeNextID(from: eligible.map(\.id), at: now),
                   let event = eligible.first(where: { $0.id == nextID }) {
                    await LiveStreamResolver.shared.preflightSources(for: StreamPlaybackRequest(event: event))
                }
                do { try await Task.sleep(for: .seconds(sourcePreflightSchedule.delay(at: Date()))) }
                catch { return }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !AppRuntime.isAutomatedTesting else { return }
            viewingSession.handoffPublisher.expireIfNeeded()
            if !LocalDataStore.shared.isUsingVolatileFallback { SportsContinuityBridge.shared.refresh() }
            let catalog = MatchListViewModel.shared
            catalog.configure(modelContext: modelContext)
            await catalog.refreshIfNeeded()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15 * 60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await catalog.refreshIfNeeded()
            }
        }
    }

    private var followMigrationErrorMessage: String {
        followMigrationError ?? ""
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            SportsDashboardView(isActive: selectedTab == .home)
                .tabItem {
                    Label(Tab.home.displayName, systemImage: Tab.home.icon)
                        .accessibilityIdentifier("tab-home")
                }
                .tag(Tab.home)

            SportsTVView(isActive: selectedTab == .tv) {
                SportsTVWatchPolicy.watch($0, using: viewingSession,
                    currentCatalog: { MatchListViewModel.shared.playbackAdmissionCatalog })
            }
                .tabItem {
                    Label(Tab.tv.displayName, systemImage: Tab.tv.icon)
                        .accessibilityIdentifier("tab-tv")
                }
                .tag(Tab.tv)

            ArenaDiscoveryView(isActive: selectedTab == .social) {
                selectedTab = .home
            }
            .tabItem {
                Label(Tab.social.displayName, systemImage: Tab.social.icon)
                    .accessibilityIdentifier("tab-arena")
            }
            .tag(Tab.social)

            FPLMainView(session: fplSession)
                .tabItem {
                    Label(Tab.fpl.displayName, systemImage: Tab.fpl.icon)
                        .accessibilityIdentifier("tab-fpl")
                }
                .tag(Tab.fpl)

        }
        // Settings is not a place to watch sport: Home's gear opens it here.
        .environment(\.fottyOpenSettings, { showsSettings = true })
        .sheet(isPresented: $showsSettings) {
            SettingsView(onOpenFPL: {
                showsSettings = false
                fplSession.workspace = .gameweek
                selectedTab = .fpl
            }, onClose: { showsSettings = false })
            .presentationDetents([.large])
        }
        // These are real destinations, so let the system own their Liquid Glass
        // navigation surface. A separate custom dock plus an empty TabView was
        // what produced the duplicate blank capsule on iOS 27.
        .toolbarVisibility(isTabBarVisible ? .visible : .hidden, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: viewingSession.isActive && !viewingSession.expanded) {
            ViewingMiniPlayer()
        }
        .tint(FottyTheme.accentText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func migrateFollowedTeamKeysIfNeeded() {
        do { try SportsPersonalizationStore.migrateTeamIdentities(in: modelContext) }
        catch { followMigrationError = "Your saved follows are still available, but their updated identities could not be saved. Try again in Manage follows." }
    }

    private func openPendingFPLDestination() {
        matchNavigationStore.pendingFPL = false
        fplSession.workspace = .gameweek
        selectedTab = .fpl
    }
    
}


private struct FottyOpenSettingsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens Settings as a sheet. Home's gear button uses it.
    var fottyOpenSettings: (() -> Void)? {
        get { self[FottyOpenSettingsKey.self] }
        set { self[FottyOpenSettingsKey.self] = newValue }
    }
}
