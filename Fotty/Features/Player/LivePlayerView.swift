import SwiftUI
import AVKit
import os.log
import UIKit
import Network
import UniformTypeIdentifiers

private let playerLogger = Logger(subsystem: "com.jelani.Fotty", category: "LivePlayer")

// MARK: - Orientation Control

enum PlayerOrientationController {
    static func enterLandscape() {
        request(mask: .landscape, orientation: .landscapeRight)
    }
    
    static func exitToPortrait() {
        request(mask: .portrait, orientation: .portrait)
    }
    
    private static func request(mask: UIInterfaceOrientationMask, orientation: UIInterfaceOrientation) {
        #if targetEnvironment(macCatalyst)
        // Catalyst windows do not have an iOS device orientation. Asking the
        // scene for an iOS geometry update can interrupt an otherwise healthy
        // playback session when entering or leaving the player on Mac.
        return
        #else
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        
        Task { @MainActor in
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            
            if let scene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            _ = orientation
        }
        #endif
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}

// MARK: - Raw AVPlayer View

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var pictureInPictureRequestID: UUID? = nil
    var onReadyForDisplayChanged: ((Bool) -> Void)? = nil
    var onPictureInPictureAvailabilityChanged: ((Bool) -> Void)? = nil
    var onPictureInPictureActiveChanged: ((Bool) -> Void)? = nil
    var onPictureInPictureFailure: ((String) -> Void)? = nil
    
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.onReadyForDisplayChanged = onReadyForDisplayChanged
        view.onPictureInPictureAvailabilityChanged = onPictureInPictureAvailabilityChanged
        view.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        view.onPictureInPictureFailure = onPictureInPictureFailure
        view.player = player
        view.videoGravity = videoGravity
        view.pictureInPictureRequestID = pictureInPictureRequestID
        return view
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.onReadyForDisplayChanged = onReadyForDisplayChanged
        uiView.onPictureInPictureAvailabilityChanged = onPictureInPictureAvailabilityChanged
        uiView.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        uiView.onPictureInPictureFailure = onPictureInPictureFailure
        uiView.player = player
        uiView.videoGravity = videoGravity
        uiView.pictureInPictureRequestID = pictureInPictureRequestID
    }
    
    class PlayerUIView: UIView, AVPictureInPictureControllerDelegate {
        var onReadyForDisplayChanged: ((Bool) -> Void)? {
            didSet { notifyReadyForDisplay() }
        }
        var onPictureInPictureAvailabilityChanged: ((Bool) -> Void)? {
            didSet { notifyPictureInPictureAvailability() }
        }
        var onPictureInPictureActiveChanged: ((Bool) -> Void)?
        var onPictureInPictureFailure: ((String) -> Void)?
        var pictureInPictureRequestID: UUID? {
            didSet { startPictureInPictureIfRequested() }
        }

        private var readyForDisplayObservation: NSKeyValueObservation?
        private var pictureInPicturePossibleObservation: NSKeyValueObservation?
        private var pictureInPictureController: AVPictureInPictureController?
        private var handledPictureInPictureRequestID: UUID?
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }
        
        var videoGravity: AVLayerVideoGravity {
            get { playerLayer.videoGravity }
            set { playerLayer.videoGravity = newValue }
        }
        
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            videoGravity = .resizeAspect
            backgroundColor = .black
            readyForDisplayObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.notifyReadyForDisplay() }
            }
            configurePictureInPictureIfNeeded()
        }
        
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit {
            readyForDisplayObservation?.invalidate()
            pictureInPicturePossibleObservation?.invalidate()
            pictureInPictureController?.delegate = nil
        }
        private func notifyReadyForDisplay() { onReadyForDisplayChanged?(playerLayer.isReadyForDisplay) }
        
        private func configurePictureInPictureIfNeeded() {
            guard pictureInPictureController == nil else { return }
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                notifyPictureInPictureAvailability()
                return
            }

            guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
                notifyPictureInPictureAvailability()
                return
            }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController = controller
            pictureInPicturePossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.notifyPictureInPictureAvailability() }
            }
        }

        private func notifyPictureInPictureAvailability() {
            let available = AVPictureInPictureController.isPictureInPictureSupported()
                && (pictureInPictureController?.isPictureInPicturePossible ?? false)
            onPictureInPictureAvailabilityChanged?(available)
        }

        private func startPictureInPictureIfRequested() {
            guard let requestID = pictureInPictureRequestID,
                  handledPictureInPictureRequestID != requestID else {
                return
            }
            handledPictureInPictureRequestID = requestID
            configurePictureInPictureIfNeeded()

            guard let controller = pictureInPictureController,
                  controller.isPictureInPicturePossible else {
                onPictureInPictureFailure?("Picture in Picture is not ready for this stream yet.")
                notifyPictureInPictureAvailability()
                return
            }

            if controller.isPictureInPictureActive {
                controller.stopPictureInPicture()
            } else {
                controller.startPictureInPicture()
            }
        }

        func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            onPictureInPictureActiveChanged?(true)
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            onPictureInPictureActiveChanged?(true)
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            onPictureInPictureActiveChanged?(false)
            notifyPictureInPictureAvailability()
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            // The player presentation remains mounted while PiP is active, so
            // returning to Fotty needs no replacement player or navigation.
            completionHandler(true)
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            onPictureInPictureActiveChanged?(false)
            onPictureInPictureFailure?(error.localizedDescription)
            notifyPictureInPictureAvailability()
        }
    }
}

// MARK: - Live Sports Player

struct LivePlayerView: View {
    @State var viewModel: LivePlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LiveScoreService.self) private var scoreService
    
    @State private var didApplyLandscape = false
    
    init(event: AnalyticalDataEngine.EventReference, providedSessions: [StreamSession]) {
        self._viewModel = State(initialValue: LivePlayerViewModel(event: event, providedSessions: providedSessions))
    }
    
    private var sourceRecoveryButtonTitle: String {
        "Choose another source"
    }
    
    private var matchingMatch: FootballMatch? {
        scoreService.findMatch(
            home: viewModel.event.homeName,
            away: viewModel.event.awayName,
            near: viewModel.event.kickoffDate
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            
            VStack(spacing: 0) {
                if isPortrait {
                    playerMatchHeader
                }

                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if viewModel.isUsingWebEmbed, let source = viewModel.activeSource {
                        let attemptID = viewModel.loadRequestID
                        LiveWebEmbedPlayerView(
                            url: source.url,
                            referer: source.headers["Referer"] ?? source.url.absoluteString,
                            isMuted: AppRuntime.shouldMutePlaybackForTesting,
                            isSuspended: scenePhase == .background,
                            providerControlsAudio: true,
                            attemptID: attemptID,
                            playbackCommand: viewModel.webPlaybackCommand,
                            onSurfaceTapped: {
                                viewModel.revealWebControlsFromProviderTap()
                            },
                            onTransportStateChanged: { state in
                                viewModel.handleWebEmbedTransportState(
                                    state, sourceID: source.id, requestID: attemptID
                                )
                            },
                            onPlaybackStarted: { startupLatencyMs in
                                viewModel.handleWebEmbedPlaybackStarted(
                                    sourceID: source.id,
                                    requestID: attemptID,
                                    startupLatencyMs: startupLatencyMs
                                )
                            },
                            onPlaybackStalled: { reason in
                                viewModel.handleWebEmbedFailure(
                                    sourceID: source.id,
                                    requestID: attemptID,
                                    reason: reason
                                )
                            },
                            onPlaybackRecovered: {
                                viewModel.handleWebEmbedPlaybackRecovered(
                                    sourceID: source.id,
                                    requestID: attemptID
                                )
                            },
                            onNativeCandidateDiscovered: { candidate in
                                viewModel.handleNativePlaybackCandidate(
                                    candidate,
                                    sourceID: source.id,
                                    requestID: attemptID
                                )
                            }
                        )
                        .ignoresSafeArea()
                    } else if let player = viewModel.player {
                        AVPlayerLayerView(
                            player: player,
                            videoGravity: viewModel.isFillMode ? .resizeAspectFill : .resizeAspect,
                            pictureInPictureRequestID: viewModel.pictureInPictureRequestID,
                            onReadyForDisplayChanged: { ready in
                                if viewModel.isVideoReadyForDisplay != ready {
                                    viewModel.isVideoReadyForDisplay = ready
                                }
                            },
                            onPictureInPictureAvailabilityChanged: { available in
                                if viewModel.isPictureInPictureAvailable != available {
                                    viewModel.handlePictureInPictureAvailabilityChanged(
                                        available,
                                        isBackgrounded: scenePhase == .background
                                    )
                                    if available {
                                        viewModel.showPlaybackBanner("Picture in Picture ready")
                                    }
                                }
                            },
                            onPictureInPictureActiveChanged: { active in
                                viewModel.handlePictureInPictureActivityChanged(
                                    active,
                                    isBackgrounded: scenePhase == .background
                                )
                            },
                            onPictureInPictureFailure: { message in
                                viewModel.handlePictureInPictureFailure(
                                    message,
                                    isBackgrounded: scenePhase == .background
                                )
                            }
                        )
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleControlsFromPlaybackTap()
                        }
                    }
                    
                    if let error = viewModel.error {
                        PlaybackErrorOverlay(
                            title: viewModel.errorTitle,
                            message: error,
                            viewModel: viewModel,
                            sourceRecoveryButtonTitle: sourceRecoveryButtonTitle,
                            dismiss: dismiss,
                            isCompact: isPortrait,
                            onRetry: {
                                viewModel.loadCurrentSource(ignoringCircuitBreaker: true)
                            },
                            onShowBroadcastSources: {
                                // Keep the recovery state behind the sheet. If the
                                // user closes it without choosing a source, they
                                // should not be dropped onto a silent black player.
                                revealBroadcastSources(clearError: false)
                            }
                        )
                    } else if viewModel.isLoading {
                        LoadingStateOverlay(viewModel: viewModel)
                    }

                    if let message = viewModel.playbackBannerMessage, viewModel.error == nil {
                        VStack {
                            Spacer()
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 38)
                                .background(.black.opacity(0.72))
                                .clipShape(Capsule())
                                .padding(.bottom, isPortrait ? 12 : 26)
                        }
                        .allowsHitTesting(false)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if viewModel.error == nil {
                        if viewModel.isUsingWebEmbed,
                           !viewModel.isLoading,
                           viewModel.showControls {
                            Color.clear
                                .allowsHitTesting(false)
                                .overlay(alignment: .topLeading) {
                                    if !isPortrait { webCloseButton.padding(12) }
                                }
                                .overlay(alignment: .topTrailing) {
                                    webEmbedToolbar(showSources: viewModel.sessions.count > 1)
                                        .padding(8)
                                }
                        } else if (viewModel.showControls || viewModel.isLoading) {
                            PlaybackControlsOverlay(
                                viewModel: viewModel,
                                showSourceButton: !isPortrait && viewModel.sessions.count > 1,
                                showsTopBar: !isPortrait,
                                dismiss: dismiss
                            )
                        }
                    }
                }
                .frame(height: isPortrait ? geometry.size.width * 9/16 : geometry.size.height)
                .accessibilityIdentifier("live-player")
                
                if isPortrait {
                    highlightsSection
                }
            }
            .background(FottyTheme.background)
            .ignoresSafeArea(edges: isPortrait ? .bottom : .all)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        // Playback is a dark cinema surface, independent of browsing appearance.
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showStreamDebugSheet) {
            LiveStreamDebugSheet(
                event: viewModel.event,
                attemptDiagnostics: viewModel.attemptDiagnostics,
                sourceCount: viewModel.sources.count,
                currentSourceIndex: viewModel.currentSourceIndex,
                activeSource: viewModel.activeSource,
                p2pProbeInfo: viewModel.activeSource?.headers["X-Fotty-P2P-Probe"],
                isUsingWebEmbed: viewModel.isUsingWebEmbed,
                proxyPort: nil,
                activeSourceHealthScore: viewModel.activeSource.map { LiveSourceHealthStore.score(for: $0) },
                connectionPhase: viewModel.connectionPhase,
                lastStartupLatencyMs: viewModel.lastStartupLatencyMs,
                stallCount: viewModel.stallCount,
                playbackStagnationTicks: viewModel.playbackStagnationTicks,
                isPlaybackWatchdogArmed: viewModel.isPlaybackWatchdogArmed,
                isNetworkReachable: viewModel.isNetworkReachable,
                pendingRetryAfterNetworkRestore: viewModel.pendingRetryAfterNetworkRestore,
                autoFailoverCount: viewModel.autoFailoverCount,
                lastFailureKind: viewModel.lastFailureKind.rawValue,
                lastFailureReason: viewModel.lastFailureReason
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showSourceSelector) {
            LiveStreamSelectorSheet(
                sessions: viewModel.sessions,
                currentSourceIndex: $viewModel.currentSourceIndex,
                failedSessionIDs: viewModel.failedSourceIDs,
                currentPlaybackHasError: viewModel.error != nil,
                onSelect: selectBroadcastSession
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            MatchNavigationStore.shared.livePlayerDidAppear(matchID: viewModel.event.id)
            MediaAudioSession.configureForPlaybackIfNeeded()
            viewModel.startAudioSessionKeepAlive()
            viewModel.startNetworkPathMonitoring()
            scoreService.startPolling()
            
            if viewModel.providedSessions.isEmpty {
                viewModel.showNoSourcesAvailable()
            } else {
                // Reaching the player follows an explicit Watch action. Retry the
                // selected catalog source even if automatic health ordering has
                // temporarily opened its circuit; manual intent must win here.
                viewModel.loadCurrentSource(ignoringCircuitBreaker: true)
            }
            updateLiveActivity()
            viewModel.scheduleAutoHide()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
            updateLiveActivity()
        }
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing {
                viewModel.scheduleAutoHide()
            } else {
                viewModel.hideTask?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showControls = true
                }
            }
            updateLiveActivity()
        }
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading, viewModel.isPlaying {
                viewModel.scheduleAutoHide()
            }
            updateLiveActivity()
        }
        .onChange(of: viewModel.connectionPhase) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.isPictureInPictureActive) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.isPictureInPictureAvailable) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.error) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.currentSourceIndex) { _, _ in updateLiveActivity() }
        .onChange(of: liveActivityScoreText) { _, _ in updateLiveActivity() }
        .onChange(of: liveActivityMatchStatus) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.isVideoReadyForDisplay) { _, ready in
            if ready, viewModel.isPlaying, !viewModel.isLoading {
                viewModel.logP2PTimestamp("first_frame_displayed_at", source: viewModel.activeSource)
                viewModel.scheduleAutoHide()
                updateLiveActivity()
            }
        }
        .onDisappear {
            MatchNavigationStore.shared.livePlayerDidDisappear(matchID: viewModel.event.id)
            endLiveActivity()
            viewModel.cleanup()
        }
        .fottyLeadingEdgeSwipeDismissesPlayer(onDismiss: { dismiss() })
    }

    private func updateLiveActivity() {
        let shouldPresent = FottyLiveActivityPolicy.shouldPresent(
            isWebEmbed: viewModel.isUsingWebEmbed,
            isPlaying: viewModel.isPlaying,
            isLoading: viewModel.isLoading,
            hasError: viewModel.error != nil,
            supportsPictureInPicture: viewModel.isPictureInPictureAvailable,
            hasActivePictureInPicture: viewModel.isPictureInPictureActive,
            hasUsefulMatchState: liveActivityScoreText != nil
        )
        guard shouldPresent else {
            endLiveActivity()
            return
        }

        FottyLiveActivityController.shared.startOrUpdate(
            event: viewModel.event,
            source: viewModel.activeSource,
            matchStatus: liveActivityMatchStatus,
            scoreText: liveActivityScoreText
        )
    }

    private func endLiveActivity() {
        FottyLiveActivityController.shared.end(
            event: viewModel.event,
            scoreText: liveActivityScoreText
        )
    }

    private var liveActivityScoreText: String? {
        if let score = scoreService.scoreForMatch(
            home: viewModel.event.homeName,
            away: viewModel.event.awayName,
            near: viewModel.event.kickoffDate
        ) {
            return "\(score.homeGoals)-\(score.awayGoals)"
        }
        guard let match = matchingMatch,
              FootballDataPolicy.supportsLiveScores(competition: match.competition) else { return nil }
        let home = match.score.fullTime?.home ?? match.score.halfTime?.home
        let away = match.score.fullTime?.away ?? match.score.halfTime?.away
        guard let home, let away else { return nil }
        return "\(home)-\(away)"
    }

    private var liveActivityMatchStatus: String {
        if let score = scoreService.scoreForMatch(
            home: viewModel.event.homeName,
            away: viewModel.event.awayName,
            near: viewModel.event.kickoffDate
        ) {
            let status = score.minute ?? score.status.displayText
            return scoreService.scoreStatusQualifier.map { "\(status) · \($0)" } ?? status
        }
        guard FootballDataPolicy.hasConfirmedLiveScoreCoverage(
            competition: matchingMatch?.competition
        ) else { return "LIVE" }
        return scoreService.isRefreshing ? "Updating score" : "Score unavailable"
    }
    
    private var highlightsSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                broadcastSourcesSection

            if let match = matchingMatch, !(match.events ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MATCH TIMELINE")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .padding(.horizontal, FottyTheme.spacingMD)

                        LiveMatchTimelineView(
                            events: match.events ?? [],
                            homeTeamId: match.homeTeam.id,
                            awayTeamId: match.awayTeam.id
                        )
                        .frame(minHeight: 220, maxHeight: 360)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(FottyTheme.background)
    }

    private var playerMatchHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.fottyScaled(size: 14, weight: .bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(FottyTheme.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.event.displayTitle)
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(playerStatusText)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let playerScoreText {
                Text(playerScoreText)
                    .font(.fottyScaled(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .monospacedDigit()
            }

            if viewModel.isPictureInPictureAvailable && !viewModel.isUsingWebEmbed {
                Button {
                    viewModel.togglePictureInPicture()
                } label: {
                    Image(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                        .font(.fottyScaled(size: 16, weight: .semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(FottyTheme.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.isPictureInPictureActive ? "Stop Picture in Picture" : "Start Picture in Picture")
            }
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .frame(minHeight: 66)
        .background(FottyTheme.surfaceSubtle)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FottyTheme.border).frame(height: 0.5)
        }
    }

    private var playerScoreText: String? {
        guard let score = scoreService.scoreForMatch(
            home: viewModel.event.homeName,
            away: viewModel.event.awayName,
            near: viewModel.event.kickoffDate
        ) else { return nil }
        return "\(score.homeGoals)–\(score.awayGoals)"
    }

    private var playerStatusText: String {
        if let score = scoreService.scoreForMatch(
            home: viewModel.event.homeName,
            away: viewModel.event.awayName,
            near: viewModel.event.kickoffDate
        ) {
            return score.minute ?? score.status.displayText
        }
        if viewModel.isLoading { return "Connecting to broadcast" }
        switch viewModel.event.broadcastTiming() {
        case .live:
            return "Live broadcast"
        case .upcoming:
            guard let kickoff = viewModel.event.kickoffDate else { return "Upcoming broadcast" }
            return "Starts \(kickoff.formatted(date: .abbreviated, time: .shortened))"
        case .available:
            return "Broadcast available"
        }
    }

    private var broadcastSourcesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Broadcast sources")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)

                    Text("Tap a source to switch playback")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Spacer()
                Text("\(viewModel.sessions.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, FottyTheme.spacingMD)
            .padding(.top, 20)

            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(
                        session: session,
                        displayNumber: index + 1,
                        isActive: viewModel.currentSourceIndex == index,
                        isFailed: viewModel.failedSourceIDs.contains(session.id)
                            || (viewModel.error != nil && viewModel.currentSourceIndex == index),
                        isCoolingDown: LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource)
                    ) {
                        selectBroadcastSession(at: index)
                    }
                }

                if viewModel.sessions.isEmpty {
                    emptyBroadcastState
                }
            }
            .padding(.horizontal, FottyTheme.spacingMD)
        }
    }

    private var emptyBroadcastState: some View {
        loadingBroadcastState("No broadcast source is available for this match right now.")
    }

    private func loadingBroadcastState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FottyTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(FottyTheme.surfaceElevated.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG))
    }

    private func revealBroadcastSources(clearError: Bool) {
        viewModel.showSourceSelector = true
        viewModel.showControls = true
        viewModel.connectionPhase = "Choose Broadcast Source"
        if clearError {
            viewModel.error = nil
        }
    }

    private func selectBroadcastSession(at index: Int) {
        viewModel.selectSourceManually(at: index)
        HapticManager.selection()
    }

    private var webCloseButton: some View {
        Button { dismiss() } label: {
            Label("Close", systemImage: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.black.opacity(0.72))
                .clipShape(Capsule())
        }
        .accessibilityIdentifier("close-live-player")
    }

    private func webEmbedToolbar(showSources: Bool) -> some View {
        HStack(spacing: 8) {
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Label(
                        viewModel.isPlaying ? "Pause" : "Play",
                        systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill"
                    )
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.72))
                        .clipShape(Capsule())
                }
                .accessibilityLabel(viewModel.isPlaying ? "Pause broadcast" : "Play broadcast")
                .accessibilityIdentifier("web-play-pause")

                if showSources && viewModel.sessions.count > 1 {
                    Button {
                        viewModel.showSourceSelector = true
                        viewModel.scheduleAutoHide()
                    } label: {
                        Label("Sources", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.72))
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("Choose broadcast source")
                }
        }
        // Only the actual buttons hit-test; no full-video toolbar/spacer.
        .fixedSize(horizontal: true, vertical: false)
    }
}
