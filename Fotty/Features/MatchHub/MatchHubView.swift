import SwiftUI

struct MatchHubView: View {
    @StateObject private var viewModel: MatchHubViewModel
    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(\.dismiss) private var dismiss
    
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
                FootballLoadingView(size: 60)
            } else if let data = viewModel.hubData {
                VStack(spacing: 0) {
                    MatchHubHeader(
                        data: data,
                        onWatchLive: viewModel.discoveredProviders.isEmpty
                            ? nil
                            : { viewModel.watchLive() }
                    )
                    .padding(.top, showModalDismissButton ? 52 : 6)

                    if let event = viewModel.playerEvent,
                       MatchPlaybackFeedback.shared.notReadyIDs.contains(event.id) {
                        Button("No stream found yet · Retry") { viewModel.watchLive() }
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.accentText)
                            .frame(minHeight: 44)
                    }

                    InsightsHubTab(data: data, providers: viewModel.discoveredProviders)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else if let event = viewModel.catalogEvent {
                CatalogMatchHubView(
                    event: event,
                    providers: viewModel.discoveredProviders,
                    onWatchLive: viewModel.discoveredProviders.isEmpty
                        ? nil
                        : { viewModel.watchLive() }
                )
                .padding(.top, showModalDismissButton ? 52 : 6)
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
            
            if viewModel.isFindingStream {
                StreamResolutionOverlay(
                    statusMessage: viewModel.streamStatusMessage,
                    subtitle: viewModel.playerEvent.map { "\($0.homeName) vs \($0.awayName)" },
                    technicalSummary: viewModel.streamStatusDetail,
                    isMultiStream: false,
                    multiTitles: [],
                    onCancel: {
                        viewModel.cancelStreamLookup()
                    }
                )
                .zIndex(100)
            }

            if showModalDismissButton {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                                .font(FottyTheme.typeAction)
                                .foregroundStyle(FottyTheme.textPrimary)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 40)
                                .background(FottyTheme.surfaceElevated)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule().strokeBorder(FottyTheme.border, lineWidth: 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, FottyTheme.spacingMD)
                .padding(.top, 8)
                .zIndex(110)
            }
        }
        .accessibilityIdentifier("match-center")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $viewModel.showPlayer) {
            if let event = viewModel.playerEvent {
                LivePlayerView(event: event, providedSessions: viewModel.streamSessions)
                    .environment(liveScoreService)
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
    }
}

private struct CatalogMatchHubView: View {
    let event: EventReference
    let providers: [String]
    let onWatchLive: (() -> Void)?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 16) {
                    HStack {
                        Label("BROADCAST LISTING", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .black))
                            .tracking(0.7)
                            .foregroundStyle(FottyTheme.accentText)
                        Spacer()
                        Text(event.broadcastTiming().rawValue)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(FottyTheme.textOnAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(FottyTheme.accent)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 12) {
                        catalogTeam(
                            name: event.homeName,
                            badge: event.teams?.home?.badge
                        )

                        VStack(spacing: 5) {
                            Text("VS")
                                .font(.fottyScaled(size: 18, weight: .black, design: .rounded))
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
                    Label("What is available", systemImage: "info.circle.fill")
                        .font(FottyTheme.typeModuleTitle)
                        .foregroundStyle(FottyTheme.textPrimary)

                    Text("This match comes from the live broadcast catalog. Scores, lineups, and statistics are not supplied for this listing, so Fotty does not invent them.")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !providers.isEmpty {
                        Text("Available through \(providers.joined(separator: " and ")).")
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
        }
    }

    private func catalogTeam(name: String, badge: String?) -> some View {
        VStack(spacing: 7) {
            TeamBadgeView(
                badgeURL: badge.flatMap(URL.init(string:)),
                teamName: name,
                size: 52
            )
            Text(name.isEmpty ? "Team" : name)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
