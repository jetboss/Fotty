import SwiftUI

/// Keep the manager and navigation context, not an off-screen view with active tasks.
@MainActor
final class FPLWorkspaceSession: ObservableObject {
    let viewModel: FPLAdvisorViewModel
    @Published var workspace: FPLMainView.FPLWorkspace
    @Published var selectedTool: FPLMainView.FPLTool?
    var scrollOffsets: [String: CGFloat] = [:]

    init(viewModel: FPLAdvisorViewModel? = nil) {
        self.viewModel = viewModel ?? FPLAdvisorViewModel()
#if DEBUG
        workspace = FPLMainView.debugWorkspaceOverride(arguments: ProcessInfo.processInfo.arguments) ?? .gameweek
#else
        workspace = .gameweek
#endif
    }

    func resetNavigation() {
        workspace = .gameweek
        selectedTool = nil
        scrollOffsets.removeAll()
    }
}

struct FPLSquadSourceNotice: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @State private var confirmsSuggestedDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.squadSourceTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(FottyTheme.textPrimary)
                .accessibilityIdentifier("fpl-squad-source")
            Text(viewModel.squadSourceExplanation)
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.savedSquadDraft != nil || !viewModel.optimizedSquads.isEmpty {
                Menu("Squad options") {
                    if viewModel.isCustomDraft, let gameweek = viewModel.picksGameweek {
                        Button("View published GW\(gameweek) squad") { viewModel.showPublishedSquad() }
                    } else if viewModel.savedSquadDraft != nil {
                        Button("View saved local draft") { viewModel.showSavedDraft() }
                    }
                    if !viewModel.optimizedSquads.isEmpty {
                        Button("Use suggested draft…") { confirmsSuggestedDraft = true }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FottyTheme.accentText)
                .frame(minHeight: 44)
                .accessibilityIdentifier("fpl-squad-source-options")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Replace the local draft with Fotty's suggestion?", isPresented: $confirmsSuggestedDraft) {
            Button("Replace local draft", role: .destructive) { viewModel.resetToAITemplate() }
        } message: {
            Text("The published official squad will not change.")
        }
    }
}

public struct FPLMainView: View {
    private struct RefreshIdentity: Hashable {
        let isActive: Bool
        let managerSelectionID: UUID
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.fottyWideLayout) private var usesWideLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: FPLWorkspaceSession
    @ObservedObject private var viewModel: FPLAdvisorViewModel
    @State private var showsFeedback = false

    private var workspace: FPLWorkspace {
        get { session.workspace }
        nonmutating set { session.workspace = newValue }
    }
    private var selectedTool: FPLTool? {
        get { session.selectedTool }
        nonmutating set { session.selectedTool = newValue }
    }

    enum FPLWorkspace: String, CaseIterable, Identifiable {
        case gameweek = "Gameweek"
        case squad = "Squad"
        case coach = "Coach"
        case tools = "Tools"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .gameweek: return "checklist"
            case .squad: return "person.3.fill"
            case .coach: return "brain.head.profile"
            case .tools: return "square.grid.2x2"
            }
        }

        func displayName(for phase: FPLGameweekPhase) -> String {
            guard self == .gameweek else { return rawValue }
            switch phase {
            case .planning: return "Plan"
            case .locked, .live: return "Live"
            case .review: return "Review"
            case .unavailable: return rawValue
            }
        }
    }

    enum FPLTool: String, CaseIterable, Identifiable {
        case transfers = "Transfer lab"
        case captain = "Captain"
        case live = "Live points"
        case priceRadar = "Price radar"
        case wildcard = "Wildcard solver"
        case compare = "Compare players"
        case planner = "Plan ahead"
        case fixtures = "Fixture difficulty"
        case leagues = "Mini-leagues"
        case rivals = "Rival race"
        case journal = "Decision journal"

        var id: String { rawValue }

        static let groups: [(title: String, tools: [Self])] = [
            ("Plan your next move", [.transfers, .captain, .compare, .planner, .fixtures, .wildcard]),
            ("Follow the gameweek", [.live, .leagues, .rivals, .priceRadar]),
            ("Learn for next time", [.journal])
        ]

        var icon: String {
            switch self {
            case .transfers: return "arrow.left.arrow.right"
            case .captain: return "c.circle.fill"
            case .live: return "bolt.fill"
            case .priceRadar: return "chart.line.uptrend.xyaxis"
            case .wildcard: return "wand.and.stars"
            case .compare: return "person.2.fill"
            case .planner: return "calendar.badge.clock"
            case .fixtures: return "calendar"
            case .leagues: return "list.number"
            case .rivals: return "scope"
            case .journal: return "book.closed.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .transfers: return "Compare routes, costs, and downside"
            case .captain: return "Rank armband options"
            case .live: return "Track the active gameweek"
            case .priceRadar: return "Monitor likely price movement"
            case .wildcard: return "Build a legal full squad"
            case .compare: return "Compare player evidence"
            case .planner: return "Look ahead across fixtures"
            case .fixtures: return "Review upcoming difficulty"
            case .leagues: return "Check your standings"
            case .rivals: return "Track a published head-to-head"
            case .journal: return "Learn from calls after each gameweek"
            }
        }

        /// Short trust labels keep official facts, local plans and projections
        /// distinct without hiding useful advanced tools.
        var evidenceLabel: String {
            switch self {
            case .live, .leagues: return "Official data"
            case .fixtures: return "Official fixtures"
            case .rivals: return "Published data"
            case .transfers, .journal: return "On-device plan"
            case .captain, .compare, .planner: return "Projection"
            case .priceRadar: return "Estimate"
            case .wildcard: return "Advanced solver"
            }
        }

        var evidenceSymbol: String {
            switch self {
            case .live, .leagues, .fixtures, .rivals: return "checkmark.seal.fill"
            case .transfers, .journal: return "iphone"
            case .captain, .compare, .planner, .priceRadar: return "chart.xyaxis.line"
            case .wildcard: return "wand.and.stars"
            }
        }
    }
    
    public init() {
        self.init(session: FPLWorkspaceSession())
    }

    init(session: FPLWorkspaceSession) {
        _session = StateObject(wrappedValue: session)
        _viewModel = ObservedObject(wrappedValue: session.viewModel)
    }

#if DEBUG
    static func debugWorkspaceOverride(arguments: [String]) -> FPLWorkspace? {
        let key = "--fotty-fpl-workspace"
        let rawValue: String?

        if let inline = arguments.first(where: { $0.hasPrefix("\(key)=") }) {
            rawValue = String(inline.dropFirst(key.count + 1))
        } else if let keyIndex = arguments.firstIndex(of: key), arguments.indices.contains(keyIndex + 1) {
            rawValue = arguments[keyIndex + 1]
        } else {
            rawValue = nil
        }

        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plan", "gameweek": return .gameweek
        case "squad": return .squad
        case "coach": return .coach
        case "tools": return .tools
        default: return nil
        }
    }
#endif

    private var isCompactWidth: Bool { horizontalSizeClass == .compact }
    private var workspaceColumns: AnyLayout {
        usesWideLayout
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(spacing: isCompactWidth ? 10 : 14))
    }
    private var managerHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }
    private var contentInset: CGFloat { isCompactWidth ? 12 : 16 }
    private var scrollLocation: String {
        workspace == .tools ? "Tools/\(selectedTool?.rawValue ?? "overview")" : workspace.rawValue
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()
                
                if viewModel.managerId == nil || viewModel.requiresManagerConfirmation {
                    FPLManagerInputView(viewModel: viewModel)
                } else if viewModel.isLoading && viewModel.bootstrap == nil {
                    // Loading State
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(FottyTheme.accentText)
                        
                        Text("Loading your FPL team…")
                            .font(.fottyScaled(size: 15, weight: .semibold))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        Text("Checking your squad, points and upcoming fixtures")
                            .font(.fottyScaled(size: 12, weight: .medium))
                            .foregroundStyle(FottyTheme.textSecondary)
                        Button("Change manager ID") { viewModel.clearManagerId() }
                            .frame(minHeight: 44)
                    }
                } else if let error = viewModel.errorMessage, viewModel.bootstrap == nil {
                    // Error State
                    ScrollView {
                      VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.fottyScaled(size: 42))
                            .foregroundStyle(FottyTheme.error)
                        
                        Text("Something went wrong")
                            .font(.fottyScaled(size: 17, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        Text(error)
                            .font(.fottyScaled(size: 13, weight: .regular))
                            .foregroundStyle(FottyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button {
                            Task { await viewModel.loadData() }
                        } label: {
                            Text("Try Again")
                                .font(.fottyScaled(size: 14, weight: .bold))
                                .foregroundStyle(FottyTheme.textOnAccent)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(FottyTheme.accentGradient)
                                .clipShape(Capsule())
                        }
                        Button("Change manager ID") { viewModel.clearManagerId() }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("fpl-change-manager")
                        Button("Report this problem") { showsFeedback = true }
                            .frame(minHeight: 44)
                      }
                      .padding(20)
                      .frame(maxWidth: 560)
                      .frame(maxWidth: .infinity)
                    }
                } else if workspace == .coach {
                  workspaceColumns {
                    if usesWideLayout {
                        ScrollView { headerBanner }
                            .frame(width: 300)
                    }
                    VStack(spacing: isCompactWidth ? 8 : 10) {
                        if !isCompactWidth && !usesWideLayout {
                            compactFPLHeader
                                .padding(.horizontal, contentInset)
                                .padding(.top, 8)
                        }
                        workspaceBar
                        FPLAICoachView(viewModel: viewModel)
                            .padding(.horizontal, contentInset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                  }
                  .padding(.horizontal, usesWideLayout ? 16 : 0)
                } else {
                    FPLWorkspaceScrollView(session: session, location: scrollLocation, managerSelectionID: viewModel.managerSelectionID) {
                        workspaceColumns {
                            headerBanner
                                .frame(width: usesWideLayout ? 300 : nil)
                          VStack(spacing: isCompactWidth ? 10 : 14) {
                            workspaceBar

                            if viewModel.isRefreshing || (viewModel.isLoading && viewModel.bootstrap != nil) {
                                Label("Refreshing FPL data…", systemImage: "arrow.clockwise")
                                    .font(FottyTheme.typeMeta)
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }

                            if let error = viewModel.errorMessage {
                                Label("Showing your last loaded data. \(error) Pull down to retry.", systemImage: "arrow.clockwise")
                                    .font(FottyTheme.typeMeta)
                                    .foregroundStyle(FottyTheme.textSecondary)
                                    .padding(.horizontal, contentInset)
                            }

                            if let draftError = viewModel.draftErrorMessage {
                                Label(draftError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FottyTheme.error)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(FottyTheme.error.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal, contentInset)
                            }
                            
                            workspaceContent
                                .padding(.horizontal, contentInset)
                          }
                          .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, usesWideLayout ? 16 : 0)
                        .padding(.top, isCompactWidth ? 4 : 8)
                        .padding(.bottom, 16)
                    }
                    .id(scrollLocation)
                    .refreshable {
                        if !viewModel.usesAutomatedTestFixture {
                            await viewModel.loadData(isRefresh: true)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: RefreshIdentity(isActive: scenePhase == .active, managerSelectionID: viewModel.managerSelectionID)) {
                guard scenePhase == .active else {
                    viewModel.cancelRivalRefresh(clearSelection: false)
                    return
                }
                if !viewModel.usesAutomatedTestFixture,
                   viewModel.managerId != nil {
                    // Recompute phase using the service's TTL-bounded cache.
                    // Only an explicit pull-to-refresh clears that cache.
                    await viewModel.loadData()
                    // One visible-workspace poller, including planning. It must
                    // survive moving between Gameweek/Squad/Coach, but stop when
                    // this tab disappears or the scene leaves the foreground.
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(FPLMatchdayRefreshPolicy.interval)) }
                        catch { break }
                        guard !Task.isCancelled else { break }
                        await viewModel.refreshMatchdayData()
                    }
                }
            }
        }
        .sheet(isPresented: $showsFeedback) { FottyFeedbackSheet(area: .fpl) }
        .onDisappear { viewModel.cancelRivalRefresh(clearSelection: false) }
        .onChange(of: viewModel.managerSelectionID) { _, _ in session.resetNavigation() }
        .tint(FottyTheme.accentText)
    }

    private var compactFPLHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your FPL")
                    .font(FottyTheme.typeScreenTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
            }
            Spacer()
        }
    }

    private var workspaceBar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 6) {
            ForEach(FPLWorkspace.allCases) { item in
                let isSelected = workspace == item
                Button {
                    HapticManager.selection()
                    withAnimation(reduceMotion ? nil : FottyTheme.springSnappy) {
                        workspace = item
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(item.displayName(for: viewModel.gameweekPhase))
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(isSelected ? FottyTheme.accentText : FottyTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: isCompactWidth ? 44 : 52)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isSelected ? FottyTheme.accentText : FottyTheme.border)
                            .frame(height: isSelected ? 2 : 1)
                    }
                }
                .buttonStyle(FottyPressButtonStyle())
                .accessibilityLabel(item.displayName(for: viewModel.gameweekPhase))
                .accessibilityIdentifier("fpl-workspace-\(item.rawValue.lowercased())")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, contentInset)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspace {
        case .gameweek:
            FPLCommandCenterView(viewModel: viewModel, onNavigate: navigateFromGameweek)
        case .squad:
            FPLSquadSourceNotice(viewModel: viewModel)
            if let picks = viewModel.picks {
                FPLSquadPitchView(
                    picks: picks.picks,
                    scores: viewModel.playerScores,
                    teams: viewModel.bootstrap?.teams ?? [],
                    fixtures: viewModel.fixtures,
                    projectionStartGameweek: viewModel.gameweekPhase == .planning
                        ? (viewModel.currentGameweek?.id ?? viewModel.nextGameweek?.id ?? 1)
                        : (viewModel.nextGameweek?.id ?? ((viewModel.currentGameweek?.id ?? 0) + 1)),
                    isCustomDraft: viewModel.isCustomDraft,
                    showsDraftBanner: false,
                    onUpdateSquad: { viewModel.updateUserSquad(picks: $0) },
                    draftError: { viewModel.draftErrorMessage },
                    onResetTemplate: { viewModel.resetToAITemplate() }
                )
            } else {
                EmptyStateView(
                    icon: "person.3",
                    title: "Squad unavailable",
                    message: "Refresh your manager data to load the current squad."
                )
            }
        case .coach:
            EmptyView()
        case .tools:
            toolboxContent
        }
    }

    @ViewBuilder
    private var toolboxContent: some View {
        if let selectedTool {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(reduceMotion ? nil : FottyTheme.springSnappy) { self.selectedTool = nil }
                } label: {
                    Label("All tools", systemImage: "chevron.left")
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(FottyPressButtonStyle())
                .accessibilityIdentifier("fpl-all-tools")
                Text(selectedTool.rawValue)
                    .font(FottyTheme.typeSectionTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Label(selectedTool.evidenceLabel, systemImage: selectedTool.evidenceSymbol)
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
                Text("Plans stay in Fotty. Confirm changes in official FPL.")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                toolDestination(selectedTool)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Decision tools")
                        .font(FottyTheme.typeSectionTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("Official data and Fotty estimates are labelled. Plans stay in Fotty.")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("fpl-tools-trust-guide")
                ForEach(FPLTool.groups, id: \.title) { group in
                  FottySectionHeader(title: group.title)
                  LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: dynamicTypeSize.isAccessibilitySize || isCompactWidth ? 1 : 2), spacing: 6) {
                    ForEach(group.tools) { tool in
                        Button {
                            withAnimation(reduceMotion ? nil : FottyTheme.springSnappy) { selectedTool = tool }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: tool.icon)
                                    .font(.fottyScaled(size: 18, weight: .bold))
                                    .foregroundStyle(FottyTheme.accentText)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                              VStack(alignment: .leading, spacing: 4) {
                                Text(tool.rawValue)
                                    .font(FottyTheme.typeModuleTitle)
                                    .foregroundStyle(FottyTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Label(tool.evidenceLabel, systemImage: tool.evidenceSymbol)
                                    .font(FottyTheme.typeCaption.weight(.semibold))
                                    .foregroundStyle(FottyTheme.textTertiary)
                              }
                              Spacer(minLength: 4)
                              Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(FottyTheme.textSecondary)
                                .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(isCompactWidth ? 12 : 14)
                            .background(FottyTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                                    .strokeBorder(FottyTheme.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusMD))
                        .accessibilityIdentifier("fpl-tool-\(tool.id)")
                        .accessibilityHint(tool.subtitle)
                    }
                  }
                }
            }
        }
    }

    @ViewBuilder
    private func toolDestination(_ tool: FPLTool) -> some View {
        switch tool {
        case .transfers: FPLTransferHubView(viewModel: viewModel)
        case .captain: FPLCaptainPickerView(recommendations: viewModel.captainRecs)
        case .live: FPLLiveTrackerView(viewModel: viewModel, onOpenPlan: { workspace = .gameweek })
        case .priceRadar: FPLPriceAlertsView(alerts: viewModel.priceAlerts)
        case .wildcard: FPLWildcardGeneratorView(viewModel: viewModel)
        case .compare: FPLPlayerComparisonView(viewModel: viewModel)
        case .planner: FPLMultiGWPlannerView(viewModel: viewModel)
        case .fixtures:
            FPLFixtureTrackerView(grid: viewModel.fixtureGrid, gameweeks: viewModel.fixtureGameweeks)
        case .leagues: FPLLeagueStandingsView(viewModel: viewModel)
        case .rivals: FPLRivalMatrixView(viewModel: viewModel, onOpenLeagues: { selectedTool = .leagues })
        case .journal: FPLDecisionJournalView(viewModel: viewModel)
        }
    }

    private func navigateFromGameweek(_ destination: FPLCommandCenterAction.Destination) {
        withAnimation(reduceMotion ? nil : FottyTheme.springSnappy) {
            switch destination {
            case .squad:
                workspace = .squad
            case .coach:
                workspace = .coach
            case .transfers:
                workspace = .tools; selectedTool = .transfers
            case .captain:
                workspace = .tools; selectedTool = .captain
            case .live:
                workspace = .tools; selectedTool = .live
            case .leagues:
                workspace = .tools; selectedTool = .leagues
            case .planner:
                workspace = .tools; selectedTool = .planner
            }
        }
    }
    
    // MARK: - Header Gameweek & Rank Banner
    
    private var headerBanner: some View {
        VStack(spacing: isCompactWidth ? 8 : 12) {
            // Manager Team & Quick Action Row
            managerHeaderLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.managerSummary?.name ?? "Your FPL team")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    
                    if let gw = viewModel.currentGameweek ?? viewModel.nextGameweek {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Gameweek \(gw.id)")
                                .font(FottyTheme.typeMeta)
                                .foregroundStyle(FottyTheme.accentText)
                            
                            Text("Deadline \(gw.deadlineTimeFormatted)")
                                .font(FottyTheme.typeMeta)
                                .foregroundStyle(FottyTheme.textSecondary)
                        }
                    }
                }
                
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                
                Button {
                    HapticManager.impact(.light)
                    viewModel.clearManagerId()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                        Text("Switch")
                    }
                    .font(FottyTheme.typeCaption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(FottyTheme.surfaceElevated)
                    .foregroundStyle(FottyTheme.accentText)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(FottyTheme.accent.opacity(0.3), lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusLG))
                .accessibilityLabel("Switch FPL manager")
            }
            
            Divider()
                .background(FottyTheme.border)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: dynamicTypeSize.isAccessibilitySize || usesWideLayout ? 1 : 3), spacing: 12) {
                statItem(
                    label: "Overall rank",
                    value: viewModel.managerSummary?.summaryOverallRank.map { "#\($0)" } ?? "-"
                )
                
                statItem(
                    label: "Total points",
                    value: viewModel.managerSummary?.summaryOverallPoints.map(String.init) ?? "-"
                )
                
                statItem(
                    label: Self.pointsLabel(live: viewModel.liveSquadSummary, officialGameweek: viewModel.managerSummary?.currentEvent),
                    value: viewModel.liveSquadSummary.flatMap { $0.totalPoints.map(String.init) }
                        ?? viewModel.managerSummary?.summaryEventPoints.map(String.init)
                        ?? "-"
                )
            }
        }
        .padding(isCompactWidth ? 12 : 16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, contentInset)
    }
    
    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(FottyTheme.typeCaption)
                .multilineTextAlignment(.center)
                .foregroundStyle(FottyTheme.textTertiary)
            
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(FottyTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    static func pointsLabel(live: FPLLiveSquadSummary?, officialGameweek: Int?) -> String {
        if let live {
            let status = !live.hasCompleteScoringData ? "incomplete data" : (live.pointsAreProjected ? "projected" : (live.isFinal ? "final" : "live"))
            return "GW \(live.gameweek) points · \(status)"
        }
        guard let officialGameweek else { return "Official points" }
        return "GW \(officialGameweek) points · official"
    }
}

private struct FPLWorkspaceScrollView<Content: View>: View {
    let session: FPLWorkspaceSession
    let location: String
    let managerSelectionID: UUID
    @ViewBuilder var content: () -> Content
    @State private var position = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0

    var body: some View {
        ScrollView { content() }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, value in
                offset = value
            }
            .onAppear { position.scrollTo(y: session.scrollOffsets[location] ?? 0) }
            .onDisappear {
                guard session.viewModel.managerSelectionID == managerSelectionID else { return }
                session.scrollOffsets[location] = offset
            }
    }
}

// Format FPL ISO Date String
private extension FPLGameweek {
    var deadlineTimeFormatted: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: deadlineTime)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: deadlineTime)
        }
        guard let d = date else { return deadlineTime }
        let out = DateFormatter()
        out.dateFormat = "EEE d MMM, HH:mm"
        return out.string(from: d)
    }
}
