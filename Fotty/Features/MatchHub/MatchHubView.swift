import SwiftUI

struct MatchHubView: View {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @StateObject private var viewModel: MatchHubViewModel
    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    /// When `true` (sheet / full-screen cover root), show an explicit **Done** control. Pushed hubs use the system back chevron + edge swipe only.
    private let showModalDismissButton: Bool
    
    init(fixtureId: String, showModalDismissButton: Bool = false) {
        self.showModalDismissButton = showModalDismissButton
        _viewModel = StateObject(wrappedValue: MatchHubViewModel(fixtureId: fixtureId))
    }

    #if DEBUG
    init(testEvent: EventReference, showModalDismissButton: Bool = true) {
        self.showModalDismissButton = showModalDismissButton
        _viewModel = StateObject(wrappedValue: MatchHubViewModel(testEvent: testEvent))
    }
    #endif
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            
            if viewModel.isLoading && !viewModel.isFindingStream {
                SportLoadingView(
                    category: viewModel.catalogEvent?.normalizedCategory ?? viewModel.playerEvent?.normalizedCategory ?? "football",
                    size: 60,
                    competition: SportMotionContext.competition(for: viewModel.catalogEvent ?? viewModel.playerEvent)
                )
            } else if let data = viewModel.hubData {
                // One scroll surface keeps an expanded header and every insight
                // reachable; InsightsHubTab lazily supplies content, not another scroll view.
                ScrollView(showsIndicators: false) {
                  VStack(spacing: 12) {
                    MatchHubHeader(
                        data: data,
                        onWatchLive: viewModel.discoveredProviders.isEmpty
                            ? nil
                            : { viewModel.watchLive() }
                    )
                    .padding(.top, 6)

                    if let event = viewModel.playerEvent,
                       MatchPlaybackFeedback.shared.notReadyIDs.contains(event.id) {
                        Button("No stream found yet · Retry") { viewModel.watchLive() }
                            .disabled(viewModel.isFindingStream)
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.accentText)
                            .frame(minHeight: 44)
                    }

                    if let notice = viewModel.refreshNotice {
                        Text(notice).font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.textSecondary).padding(.horizontal)
                    }
                    InsightsHubTab(data: data, providers: viewModel.discoveredProviders,
                                   insights: viewModel.insights, isLoading: viewModel.isRefreshing,
                                   loadError: nil)
                  }
                  .frame(maxWidth: 1000)
                  .frame(maxWidth: .infinity)
                }
                .refreshable { await viewModel.refresh() }
            } else if let event = viewModel.catalogEvent {
                VStack(spacing: 8) {
                if let notice = viewModel.refreshNotice {
                    Text(notice).font(FottyTheme.typeMeta).foregroundStyle(FottyTheme.textSecondary)
                        .padding(.horizontal)
                }
                CatalogMatchHubView(
                    event: event,
                    providers: viewModel.discoveredProviders,
                    onWatchLive: viewModel.discoveredProviders.isEmpty
                        ? nil
                        : { viewModel.watchLive() }
                )
                .refreshable { await viewModel.refresh() }
                }
                .padding(.top, 6)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Match details unavailable",
                    message: errorMessage,
                    actionTitle: "Try Again"
                ) {
                    viewModel.refreshData()
                }
            }
            
        }
        .environment(\.fottyStreamLookupBusy, viewModel.isFindingStream)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isFindingStream {
                StreamResolutionPanel(
                    sportCategory: viewModel.catalogEvent?.normalizedCategory ?? viewModel.playerEvent?.normalizedCategory ?? "football",
                    competition: SportMotionContext.competition(for: viewModel.catalogEvent ?? viewModel.playerEvent),
                    statusMessage: viewModel.streamStatusMessage,
                    subtitle: viewModel.playerEvent.map { "\($0.homeName) vs \($0.awayName)" },
                    isMultiStream: false,
                    multiTitles: [],
                    onCancel: {
                        viewModel.cancelStreamLookup()
                    }
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showModalDismissButton {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .font(FottyTheme.typeAction)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .background(FottyTheme.surfaceElevated)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(FottyTheme.border, lineWidth: 0.5)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(FottyPressButtonStyle(cornerRadius: 22))
                }
                .padding(.horizontal, FottyTheme.spacingMD)
                .padding(.vertical, 8)
                .background(FottyTheme.background)
            }
        }
        .accessibilityIdentifier("match-center")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: viewModel.showPlayer) { _, show in
            guard show else { return }
            if let event = viewModel.playerEvent {
                viewing.open(event: event, sessions: viewModel.streamSessions)
                viewModel.showPlayer = false
                if showModalDismissButton { dismiss() }
            }
        }
        .alert("Playback Error", isPresented: Binding(get: { viewModel.streamError != nil }, set: { _ in viewModel.streamError = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.streamError ?? "Unknown error")
        }
        .onAppear {
            viewModel.resume()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.resume() }
            else { viewModel.pauseDataRefresh() }
        }
    }
}

private struct CatalogMatchHubView: View {
    let event: EventReference
    let providers: [String]
    let onWatchLive: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(LiveScoreService.self) private var scoreService

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 16) {
                    metadataLayout {
                        Label("Broadcast", systemImage: "dot.radiowaves.left.and.right")
                            .font(FottyTheme.typeModuleTitle)
                            .foregroundStyle(FottyTheme.accentText)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Text(MatchdayEventStatePolicy.presentationLabel(for: event,
                            status: MatchStartPolicy.currentStatus(for: event, scores: scoreService)))
                            .font(FottyTheme.typeMeta.weight(.semibold))
                            .foregroundStyle(FottyTheme.textOnAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(FottyTheme.accent)
                            .clipShape(Capsule())
                    }

                    teamsLayout {
                        catalogTeam(
                            name: event.homeName,
                            badge: event.teams?.home?.badge
                        )

                        VStack(spacing: 5) {
                            Text("VS")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            if let kickoff = event.kickoffDate {
                                Text(kickoff.formatted(date: .omitted, time: .shortened))
                                    .font(FottyTheme.typeCaption)
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        .frame(minWidth: 58)

                        catalogTeam(
                            name: event.awayName,
                            badge: event.teams?.away?.badge
                        )
                    }

                    MatchStartControls(event: event, onWatch: onWatchLive)
                }
                .padding(16)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous)
                        .strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Match information", systemImage: "info.circle.fill")
                        .font(FottyTheme.typeModuleTitle)
                        .foregroundStyle(FottyTheme.textPrimary)

                    Text("Scores, lineups and statistics aren't available for this broadcast.")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !providers.isEmpty {
                        Text(providers.count == 1 ? "1 broadcast option" : "\(providers.count) broadcast options")
                            .font(FottyTheme.typeCaption)
                            .foregroundStyle(FottyTheme.accentText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FottyTheme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }

    private var teamsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private func catalogTeam(name: String, badge: String?) -> some View {
        VStack(spacing: 7) {
            TeamBadgeView(
                badgeURL: badge.flatMap(URL.init(string:)),
                teamName: name,
                size: 52
            )
            Text(name.isEmpty ? "Team" : name)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
