import SwiftUI
import SwiftData

struct MainTabView: View {
    @AppStorage("fotty.selectedTab") private var persistedTabRawValue = ""
    @State private var selectedTab: Tab = MainTabView.initialTab
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var badgeManager = NotificationBadgeManager.shared
    @Environment(LiveScoreService.self) private var liveScoreService
    @State private var matchNavigationStore = MatchNavigationStore.shared
    @StateObject private var fplSession = FPLWorkspaceSession()
    
    enum Tab: String, CaseIterable {
        case home = "Home"
        // Keep the persisted raw value so existing installs retain their selected tab.
        case social = "Arena"
        case fpl = "FPL"
        case settings = "Settings"
        
        var displayName: String {
            switch self {
            case .home: return "Home"
            case .social: return "Matchday"
            case .fpl: return "FPL"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .home: return "house"
            case .social: return "calendar"
            case .fpl: return "chart.line.uptrend.xyaxis"
            case .settings: return "gearshape"
            }
        }
        
        var selectedIcon: String {
            switch self {
            case .home: return "house.fill"
            case .social: return "calendar.circle.fill"
            case .fpl: return "chart.line.uptrend.xyaxis"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    private static var enabledTabs: [Tab] { Tab.allCases }
    private static var initialTab: Tab { .home }
    
    @Query private var followedTeams: [FollowedTeamItem]
    @State private var isTabBarVisible = true

    private var followedAlertSignature: String {
        followedTeams
            .map { "\($0.key):\(($0.alertsEnabled ?? true) ? "1" : "0")" }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home:
                    SportsDashboardView()
                case .social:
                    ArenaDiscoveryView(onBrowseHome: {
                        withAnimation(FottyTheme.springSnappy) {
                            selectedTab = .home
                        }
                    })
                case .fpl:
                    FPLMainView(session: fplSession)
                case .settings:
                    SettingsView(onOpenFPL: {
                        fplSession.workspace = .gameweek
                        selectedTab = .fpl
                    })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isTabBarVisible {
                cinemaDockTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Let the background extend under system chrome without letting that
        // chrome change the content's safe-area proposal on iPhone or iPad.
        .background(FottyTheme.background.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        }
        .onChange(of: matchNavigationStore.pendingReminderID) { _, id in
            if id != nil { selectedTab = .social }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("tabBarVisibilityChanged"))) { notification in
            if let isVisible = notification.userInfo?["isVisible"] as? Bool {
                withAnimation(FottyTheme.springSnappy) {
                    isTabBarVisible = isVisible
                }
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            persistedTabRawValue = newValue.rawValue
            withAnimation(FottyTheme.springSnappy) {
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
            if FottyDeepLinkDestination.parse(url) == .fpl {
                withAnimation(FottyTheme.springSnappy) {
                    selectedTab = .fpl
                }
            } else {
                matchNavigationStore.open(url: url)
            }
        }
        .task {
            migrateFollowedTeamKeysIfNeeded()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !AppRuntime.isAutomatedTesting else { return }
            // Restored SwiftData rows omit source descriptors. Only a fresh
            // catalog response may replace a reminder's saved snapshot.
            await MatchReminderStore.shared.reconcile(events: []) {
                MatchStartPolicy.currentStatus(for: $0, scores: liveScoreService)
            }
        }
    }

    @MainActor
    private func migrateFollowedTeamKeysIfNeeded() {
        var hasChanges = false
        for item in followedTeams {
            if item.key.hasPrefix("team:") {
                let name = item.key.replacingOccurrences(of: "team:", with: "")
                let newKey = TeamFollowKey.make(name: name, category: "football")
                item.key = newKey
                hasChanges = true
            }
        }
        
        if hasChanges {
            try? modelContext.save()
        }
    }
    
    /// Full-bleed, restrained matchday navigation.
    private var cinemaDockTabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FottyTheme.borderStrong)
                .frame(height: 0.5)
            
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(Self.enabledTabs, id: \.self) { tab in
                        let isSelected = selectedTab == tab
                        Button {
                            HapticManager.impact(.light)
                            withAnimation(FottyTheme.springSnappy) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                                    .font(.fottyScaled(size: 18, weight: isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? FottyTheme.accentText : FottyTheme.textTertiary)
                                
                                Text(tab.displayName)
                                    .font(FottyTheme.typeCaption)
                                    .fontWeight(isSelected ? .bold : .medium)
                                    .foregroundStyle(isSelected ? FottyTheme.textPrimary : FottyTheme.textTertiary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                            .frame(width: horizontalSizeClass == .regular ? 96 : nil)
                            .frame(maxWidth: horizontalSizeClass == .regular ? nil : .infinity)
                            .padding(.top, 9)
                            .padding(.bottom, 7)
                            .background(isSelected ? FottyTheme.surface : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.displayName)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("tab-\(tab.rawValue.lowercased())")
                    }
                }
                Spacer(minLength: 0)
            }
            .background(FottyTheme.surfaceElevated)
        }
        .frame(maxWidth: .infinity)
        .background(FottyTheme.surfaceElevated.ignoresSafeArea(edges: .bottom))
    }
}


/// A wrapper that defers view instantiation until it's needed.
struct LazyView<Content: View>: View {
    @ViewBuilder private let build: () -> Content
    
    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}
