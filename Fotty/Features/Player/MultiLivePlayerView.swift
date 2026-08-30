import SwiftUI
import AVKit
import Network
import os.log

struct MultiLiveSlot: Identifiable {
    let id: String
    let event: AnalyticalDataEngine.EventReference
    let sessions: [StreamSession]
    
    init(event: AnalyticalDataEngine.EventReference, sessions: [StreamSession]) {
        self.id = event.id
        self.event = event
        self.sessions = sessions
    }

    var sources: [StreamSource] {
        sessions.map(\.legacySource)
    }
}

struct MultiLivePlayerView: View {
    let slots: [MultiLiveSlot]
    
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveScoreService.self) private var liveScoreService
    @State private var activeAudioSlotID: String?
    @State private var isFillMode = true
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var audioSessionKeepAliveTask: Task<Void, Never>?
    
    @State private var orderedSlots: [MultiLiveSlot] = []
    @State private var isAutoAudioFocusEnabled = true
    @State private var autoFocusGlowSlotID: String? = nil
    @State private var lastKnownScores: [String: (home: Int, away: Int)] = [:]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                
                if orderedSlots.count == 2 {
                    Group {
                        if isLandscape {
                            HStack(spacing: 1) {
                                ForEach(orderedSlots) { slot in
                                    panel(for: slot)
                                }
                            }
                        } else {
                            VStack(spacing: 1) {
                                ForEach(orderedSlots) { slot in
                                    panel(for: slot)
                                }
                            }
                        }
                    }
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                        Text("Preparing MultiView...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .allowsHitTesting(!showControls)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = true
                    }
                    scheduleAutoHide()
                }
            
            if showControls {
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Close MultiView")
                        
                        Spacer()
                        
                        Button {
                            isFillMode.toggle()
                            scheduleAutoHide()
                        } label: {
                            Image(systemName: isFillMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(isFillMode ? "Fit Video" : "Fill Screen")
                        
                        Button {
                            swapSlots()
                            scheduleAutoHide()
                        } label: {
                            Image(systemName: "rectangle.2.swap")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Swap screen positions")
                        
                        Button {
                            isAutoAudioFocusEnabled.toggle()
                            scheduleAutoHide()
                        } label: {
                            Image(systemName: isAutoAudioFocusEnabled ? "waveform.circle.fill" : "waveform.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isAutoAudioFocusEnabled ? FottyTheme.accentText : .white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(isAutoAudioFocusEnabled ? "Disable Auto Audio" : "Enable Auto Audio")
                        .accessibilityHint("Let Fotty choose which stream you hear")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .fottyLeadingEdgeSwipeDismissesPlayer(onDismiss: { dismiss() })
        .onChange(of: liveScoreService.scores) { _, _ in
            checkForGoalAutoFocus()
        }
        .onAppear {
            orderedSlots = Array(slots.prefix(2))
            updateLastKnownScores()
            MediaAudioSession.configureForPlaybackIfNeeded()
            startAudioSessionKeepAlive()
            activeAudioSlotID = orderedSlots.first?.id
            PlayerOrientationController.enterLandscape()
            scheduleAutoHide()
        }
        .onDisappear {
            hideTask?.cancel()
            audioSessionKeepAliveTask?.cancel()
            PlayerOrientationController.exitToPortrait()
            ActiveWebViewManager.clear()
        }
    }
    
    private func panel(for slot: MultiLiveSlot) -> some View {
        let isGlowActive = autoFocusGlowSlotID == slot.id
        let teamColor = TeamColorResolver.resolve(teamName: slot.event.homeName) ?? FottyTheme.accent
        
        return MultiLivePanelView(
            slot: slot,
            isAudioActive: activeAudioSlotID == slot.id,
            isFillMode: isFillMode,
            showControls: showControls,
            onRequestAudio: {
                activeAudioSlotID = slot.id
                scheduleAutoHide()
            },
            onInteraction: {
                if !showControls {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = true
                    }
                }
                scheduleAutoHide()
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(teamColor, lineWidth: isGlowActive ? 6 : 0)
                .shadow(color: teamColor.opacity(0.8), radius: isGlowActive ? 15 : 0)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isGlowActive)
    }
    
    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }
    
    private func startAudioSessionKeepAlive() {
        audioSessionKeepAliveTask?.cancel()
        audioSessionKeepAliveTask = Task {
            while !Task.isCancelled {
                MediaAudioSession.configureForPlaybackIfNeeded()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    
    private func swapSlots() {
        guard orderedSlots.count == 2 else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            orderedSlots.swapAt(0, 1)
        }
    }
    
    private func updateLastKnownScores() {
        for slot in orderedSlots {
            if let score = liveScoreService.scoreForMatch(home: slot.event.homeName, away: slot.event.awayName) {
                lastKnownScores[slot.id] = (score.homeGoals, score.awayGoals)
            } else {
                lastKnownScores[slot.id] = (0, 0)
            }
        }
    }
    
    private func checkForGoalAutoFocus() {
        guard isAutoAudioFocusEnabled else { return }
        
        for slot in orderedSlots {
            guard let score = liveScoreService.scoreForMatch(home: slot.event.homeName, away: slot.event.awayName) else { continue }
            let last = lastKnownScores[slot.id] ?? (0, 0)
            let newHome = score.homeGoals
            let newAway = score.awayGoals
            
            if newHome > last.home || newAway > last.away {
                if activeAudioSlotID != slot.id {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        activeAudioSlotID = slot.id
                        autoFocusGlowSlotID = slot.id
                    }
                    
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        if autoFocusGlowSlotID == slot.id {
                            withAnimation(.easeOut(duration: 0.5)) {
                                autoFocusGlowSlotID = nil
                            }
                        }
                    }
                }
            }
            lastKnownScores[slot.id] = (newHome, newAway)
        }
    }
}

private struct MultiLivePanelView: View {
    let slot: MultiLiveSlot
    let isAudioActive: Bool
    let isFillMode: Bool
    let showControls: Bool
    let onRequestAudio: () -> Void
    let onInteraction: () -> Void
    
    @AppStorage("fotty.livePlayer.showAdvancedControls") private var showAdvancedControls = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var currentSourceIndex = 0
    @State private var isLoading = true
    @State private var isPlaying = true
    @State private var errorTitle = "Playback Error"
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var stallValidationTask: Task<Void, Never>?
    @State private var foregroundResumeValidationTask: Task<Void, Never>?
    @State private var loadRequestID = UUID()
    @State private var streamProxy: LocalStreamProxy?
    @State private var networkPathMonitor: NWPathMonitor?
    @State private var isNetworkReachable = true
    @State private var pendingRetryAfterNetworkRestore = false
    @State private var playerItemNotificationTokens: [NSObjectProtocol] = []
    @State private var playbackWatchdogTask: Task<Void, Never>?
    @State private var failedSourceIDs: Set<UUID> = []
    @State private var sourceAttemptStartedAt: Date?
    @State private var isVideoReadyForDisplay = false
    @State private var lastObservedPlaybackSecond: Double?
    @State private var playbackStagnationTicks = 0
    @State private var shouldResumeAfterForeground = false
    @State private var p2pStallBrokerReloadAttemptsBySource: [UUID: Int] = [:]
    @State private var webRetryAttemptsBySource: [UUID: Int] = [:]
    @State private var isP2PSoftRecoveryInFlight = false
    
    private let diagnosticService = PlayerDiagnosticService()
    private let validator = StreamContractValidator()
    
    private var event: AnalyticalDataEngine.EventReference {
        slot.event
    }
    @State private var lastFailureKind: LivePlaybackFailureKind = .unknown
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let source = activeSource, isWebEmbedSource(source) {
                let attemptID = loadRequestID
                LiveWebEmbedPlayerView(
                    url: source.url,
                    referer: source.headers["Referer"] ?? source.url.absoluteString,
                    isMuted: !isAudioActive,
                    isSuspended: scenePhase == .background,
                    attemptID: attemptID,
                    onPlaybackStarted: { startupLatencyMs in
                        guard loadRequestID == attemptID else { return }
                        handleWebPlaybackStarted(source: source, startupLatencyMs: startupLatencyMs)
                    },
                    onPlaybackStalled: { reason in
                        guard loadRequestID == attemptID else { return }
                        let normalized = reason.lowercased()
                        handleSourceFailure(
                            source,
                            reason: reason,
                            countsAsStall: normalized.contains("stalled") || normalized.contains("frozen"),
                            expectedRequestID: attemptID
                        )
                    },
                    onPlaybackRecovered: {
                        guard loadRequestID == attemptID,
                              activeSource?.id == source.id else { return }
                        isLoading = false
                        isPlaying = true
                        error = nil
                    }
                )
                .ignoresSafeArea()
            } else if let player {
                AVPlayerLayerView(
                    player: player,
                    videoGravity: isFillMode ? .resizeAspectFill : .resizeAspect,
                    onReadyForDisplayChanged: { ready in
                        if isVideoReadyForDisplay != ready {
                            isVideoReadyForDisplay = ready
                        }
                    }
                )
                .ignoresSafeArea()
            }
            
            if showControls {
                LinearGradient(
                    colors: [.black.opacity(0.5), .clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text(shortCode(for: slot.event.homeName))
                            Text("vs")
                                .foregroundStyle(.white.opacity(0.75))
                            Text(shortCode(for: slot.event.awayName))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        
                        Spacer()
                        
                        if !slot.sources.isEmpty {
                            Menu {
                                ForEach(Array(slot.sources.enumerated()), id: \.offset) { index, source in
                                    Button {
                                        currentSourceIndex = index
                                        failedSourceIDs.removeAll()
                                        loadCurrentSource(ignoringCircuitBreaker: true)
                                        onInteraction()
                                    } label: {
                                        HStack {
                                            Text(source.provider)
                                            if index == currentSourceIndex {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.purple.opacity(0.75))
                                    .clipShape(Circle())
                            }
                        }
                        
                        Button {
                            onRequestAudio()
                            onInteraction()
                        } label: {
                            Image(systemName: isAudioActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(isAudioActive ? FottyTheme.accent.opacity(0.85) : .black.opacity(0.45))
                                )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button {
                            togglePlayPause()
                            onInteraction()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.event.categoryDisplayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            
                            if showAdvancedControls {
                                Text(activeProviderLabel)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .transition(.opacity)
            }
            
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.1)
            }
            
            if let error {
                VStack(spacing: 8) {
                    Text(errorTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    
                    // Source picker — always show so users can switch from any failure state
                    if !slot.sources.isEmpty {
                        Menu {
                            ForEach(Array(slot.sources.enumerated()), id: \.offset) { index, source in
                                Button {
                                    currentSourceIndex = index
                                    failedSourceIDs.removeAll()
                                    loadCurrentSource(ignoringCircuitBreaker: true)
                                } label: {
                                    HStack {
                                        Text(source.provider)
                                        if index == currentSourceIndex {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 11))
                                Text(slot.sources.count > 1 ? "Change Source" : "Retry")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.purple.opacity(0.85)))
                        }
                    }

                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.65))
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if showControls {
                onRequestAudio()
            }
            onInteraction()
        }
        .onAppear {
            MediaAudioSession.configureForPlaybackIfNeeded()
            startNetworkPathMonitoring()
            if !slot.sources.isEmpty {
                currentSourceIndex = preferredInitialSourceIndex()
            }
            failedSourceIDs.removeAll()
            loadCurrentSource()
        }
        .onChange(of: isAudioActive) { _, _ in
            updateAudioState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: isVideoReadyForDisplay) { _, ready in
            if ready, isPlaying, !isLoading {
                logP2PTimestamp("first_frame_displayed_at", source: activeSource)
            }
        }
        .onDisappear {
            loadTask?.cancel()
            stallValidationTask?.cancel()
            loadRequestID = UUID()
            foregroundResumeValidationTask?.cancel()
            shouldResumeAfterForeground = false
            stopNetworkPathMonitoring()
            stopPlaybackWatchdog()
            removeItemFailureObservers()
            player?.pause()
            player = nil
            streamProxy?.stop()
            streamProxy = nil
        }
    }
    
    private var activeSource: StreamSource? {
        guard slot.sources.indices.contains(currentSourceIndex) else { return nil }
        return slot.sources[currentSourceIndex]
    }
    
    private var activeProviderLabel: String {
        if slot.sources.indices.contains(currentSourceIndex) {
            return slot.sources[currentSourceIndex].provider
        }
        return "Source"
    }
    
    private func shortCode(for team: String) -> String {
        let cleaned = team
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if cleaned.isEmpty {
            return "TEAM"
        }
        
        if cleaned.count == 1 {
            return String(cleaned[0].prefix(4)).uppercased()
        }
        
        let initials = cleaned.prefix(3).compactMap { $0.first }
        return String(initials).uppercased()
    }
    
    private func startNetworkPathMonitoring() {
        stopNetworkPathMonitoring()
        let monitor = NWPathMonitor()
        networkPathMonitor = monitor
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                handleNetworkReachabilityChange(path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.fotty.multiLivePanel.networkPath.\(slot.id)"))
    }
    
    private func stopNetworkPathMonitoring() {
        networkPathMonitor?.cancel()
        networkPathMonitor = nil
    }
    
    private func handleNetworkReachabilityChange(_ reachable: Bool) {
        let wasReachable = isNetworkReachable
        isNetworkReachable = reachable
        
        if !reachable {
            guard wasReachable else { return }
            pendingRetryAfterNetworkRestore = true
            stopPlaybackWatchdog()
            return
        }
        
        guard !wasReachable, pendingRetryAfterNetworkRestore else { return }
        pendingRetryAfterNetworkRestore = false
        resumeCurrentAttemptAfterNetworkRestore()
    }

    private func resumeCurrentAttemptAfterNetworkRestore() {
        guard let source = activeSource else { return }

        error = nil
        isPlaying = true
        if isWebEmbedSource(source) {
            isLoading = !isVideoReadyForDisplay
            updateAudioState()
            return
        }

        guard let player, let item = player.currentItem else {
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        }
        guard item.status != .failed else {
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        }

        let startSeconds = player.currentTime().seconds
        let requestID = loadRequestID
        MediaAudioSession.configureForPlaybackIfNeeded()
        player.play()
        isLoading = false
        updateAudioState()
        startPlaybackWatchdog(for: source)

        foregroundResumeValidationTask?.cancel()
        foregroundResumeValidationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  activeSource?.id == source.id,
                  loadRequestID == requestID,
                  self.player?.currentItem === item,
                  isPlaying else { return }
            let currentSeconds = self.player?.currentTime().seconds ?? startSeconds
            if abs(currentSeconds - startSeconds) < 0.1,
               self.player?.timeControlStatus != .paused {
                validateRecoverablePanelStall(
                    for: source,
                    reason: "Network recovery stalled.",
                    expectedItem: item,
                    requestID: requestID
                )
            }
        }
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            handleAppDidBecomeActive()
        case .inactive, .background:
            handleAppDidMoveToBackground()
        @unknown default:
            break
        }
    }
    
    private func handleAppDidMoveToBackground() {
        foregroundResumeValidationTask?.cancel()
        shouldResumeAfterForeground = isPlaying
        if let source = activeSource, isWebEmbedSource(source) {
            isPlaying = false
            stopPlaybackWatchdog()
            return
        }
        
        if isPlaying {
            player?.pause()
            isPlaying = false
        }
        
        stopPlaybackWatchdog()
    }
    
    private func handleAppDidBecomeActive() {
        MediaAudioSession.configureForPlaybackIfNeeded()
        updateAudioState()
        
        guard shouldResumeAfterForeground else { return }
        shouldResumeAfterForeground = false
        
        guard let source = activeSource else {
            loadCurrentSource()
            return
        }
        if isWebEmbedSource(source) {
            isPlaying = true
            isLoading = !isVideoReadyForDisplay
            updateAudioState()
            return
        }
        
        guard let player, let item = player.currentItem else {
            loadCurrentSource()
            return
        }
        
        let startSeconds = player.currentTime().seconds
        let requestID = loadRequestID
        player.play()
        isPlaying = true
        startPlaybackWatchdog(for: source)
        
        // We do NOT add new observers here to avoid duplicates. 
        // Observers are configured in loadCurrentSource() via configureItemFailureObservers().
        
        if item.status == .failed {
            handleSourceFailure(source, reason: "Playback failed after returning to app.")
            return
        }
        
        foregroundResumeValidationTask?.cancel()
        foregroundResumeValidationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard activeSource?.id == source.id,
                  loadRequestID == requestID,
                  self.player?.currentItem === item else { return }
            guard !isLoading, isPlaying else { return }
            
            let currentSeconds = self.player?.currentTime().seconds ?? startSeconds
            let noProgress = startSeconds.isFinite
                && currentSeconds.isFinite
                && abs(currentSeconds - startSeconds) < 0.1
            
            if noProgress, self.player?.timeControlStatus != .paused {
                validateRecoverablePanelStall(
                    for: source,
                    reason: "Resume stalled after returning to app.",
                    expectedItem: item,
                    requestID: requestID
                )
            }
        }
    }
    
    private func togglePlayPause() {
        guard let player else { return }
        
        if isPlaying {
            player.pause()
            stopPlaybackWatchdog()
        } else {
            MediaAudioSession.configureForPlaybackIfNeeded()
            player.play()
            if let source = activeSource {
                startPlaybackWatchdog(for: source)
            }
        }
        
        isPlaying.toggle()
    }
    
    private func loadCurrentSource(ignoringCircuitBreaker: Bool = false) {
        loadTask?.cancel()
        stallValidationTask?.cancel()
        foregroundResumeValidationTask?.cancel()
        let requestID = UUID()
        loadRequestID = requestID
        guard let source = activeSource else {
            isLoading = false
            errorTitle = "No Sources Available"
            error = "No stream sources were returned for this event."
            return
        }

        if !ignoringCircuitBreaker, LiveSourceHealthStore.isTemporarilyUnavailable(source) {
            failedSourceIDs.insert(source.id)
            if let next = nextPlayableSource(after: source),
               let index = slot.sources.firstIndex(where: { $0.id == next.id }) {
                currentSourceIndex = index
                loadCurrentSource()
            } else {
                isLoading = false
                isPlaying = false
                errorTitle = "Sources Temporarily Unavailable"
                error = "Automatic switching is paused because every source failed recently. Choose a source to retry it manually."
            }
            return
        }
        logP2PTimestamp("tap_time", source: source)
        
        isLoading = true
        isPlaying = true
        isVideoReadyForDisplay = false
        error = nil
        sourceAttemptStartedAt = Date()
        removeItemFailureObservers()
        stopPlaybackWatchdog()
        
        loadTask = Task {
            if isWebEmbedSource(source) {
                streamProxy?.stop()
                streamProxy = nil
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                player = nil
                guard !Task.isCancelled, loadRequestID == requestID else { return }
                isPlaying = true
                updateAudioState()
                return
            }
            
            do {
                if player == nil {
                    player = AVPlayer()
                }
                guard let player else { return }
                let p2p = isP2PSource(source)
                player.automaticallyWaitsToMinimizeStalling = !p2p

                let playbackURL = try await preparePlaybackURL(for: source, requestID: requestID)
                guard !Task.isCancelled, loadRequestID == requestID else { return }

                // --- AUDIT FIX [CONTRACT VALIDATION] ---
                let validation = await validator.validate(playbackURL, headers: source.headers)
                if case .invalid(let reason) = validation {
                    handleSourceFailure(
                        source,
                        reason: "Stream Contract Failed: \(reason)",
                        expectedRequestID: requestID
                    )
                    return
                }

                let asset: AVURLAsset
                if !source.headers.isEmpty, playbackURL.host != "127.0.0.1" {
                    asset = AVURLAsset(url: playbackURL, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
                } else {
                    asset = AVURLAsset(url: playbackURL)
                }

                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = p2p ? 3.0 : 2.0
                if p2p {
                    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                }
                configureItemFailureObservers(for: item, source: source, requestID: requestID)
                player.replaceCurrentItem(with: item)
                updateAudioState()
                logP2PTimestamp("avplayer_item_created_at", source: source)

                let readyTimeout = p2p ? 28.0 : 6.0
                if p2p {
                    MediaAudioSession.configureForPlaybackIfNeeded()
                    player.playImmediately(atRate: 1.0)
                    isPlaying = true
                }
                let ready = await waitForSourceReadiness(item, timeoutSeconds: readyTimeout)
                guard !Task.isCancelled, loadRequestID == requestID else { return }
                guard ready else {
                    let snapshot = diagnosticService.analyze(item)
                    handleSourceFailure(
                        source,
                        reason: "Not ready. \(snapshot.failureReason)",
                        expectedRequestID: requestID
                    )
                    return
                }
                logP2PTimestamp("avplayer_item_ready_at", source: source)

                MediaAudioSession.configureForPlaybackIfNeeded()
                if p2p {
                    player.playImmediately(atRate: 1.0)
                } else {
                    player.play()
                }
                isPlaying = true

                let started = await waitForPlaybackStart(from: player.currentTime().seconds, timeoutSeconds: readyTimeout)
                guard !Task.isCancelled, loadRequestID == requestID else { return }
                guard started else {
                    handleSourceFailure(
                        source,
                        reason: "Playback failed to start before timeout.",
                        expectedRequestID: requestID
                    )
                    return
                }

                stallValidationTask?.cancel()
                error = nil
                isLoading = false
                p2pStallBrokerReloadAttemptsBySource[source.id] = 0
                isP2PSoftRecoveryInFlight = false
                LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: startupLatencyMs())
                startPlaybackWatchdog(for: source)
            } catch {
                guard !Task.isCancelled, loadRequestID == requestID else { return }
                handleSourceFailure(
                    source,
                    reason: error.localizedDescription,
                    expectedRequestID: requestID
                )
            }
        }
    }

    private func preparePlaybackURL(for source: StreamSource, requestID _: UUID) async throws -> URL {
        streamProxy?.stop()
        streamProxy = nil

        let remoteURL: URL
        if isP2PSource(source) {
            let prepared = try await AceSessionEngine.shared.prepareSession(for: source)
            remoteURL = prepared.playbackURL
        } else {
            remoteURL = source.url
        }

        let isP2P = isP2PSource(source)
        
        // Always bypass LocalStreamProxy for P2P sources.
        guard !isP2P && !source.headers.isEmpty else {
            return remoteURL
        }

        let cookies = HTTPCookieStorage.shared.cookies(for: remoteURL) ?? []
        let proxy = LocalStreamProxy(headers: source.headers, cookies: cookies)
        try await proxy.start()
        
        // Wait for proxy health check
        var proxyReady = false
        for _ in 0..<5 {
            if await proxy.ping() { proxyReady = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        guard proxyReady, let port = proxy.port,
              let localURL = localProxyURL(for: remoteURL, proxyPort: port) else {
            proxy.stop()
            throw ProcessorError.proxyError
        }
        
        streamProxy = proxy
        return localURL
    }

    private func localProxyURL(for remoteURL: URL, proxyPort: UInt16) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(proxyPort)
        components.path = "/proxy"
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }

    private func startupLatencyMs() -> Int? {
        guard let sourceAttemptStartedAt else { return nil }
        return Int(Date().timeIntervalSince(sourceAttemptStartedAt) * 1000)
    }

    private func preferredInitialSourceIndex() -> Int {
        guard let bestID = LiveSourceHealthStore.automaticCandidates(in: slot.sources).first?.id else { return 0 }
        return slot.sources.firstIndex(where: { $0.id == bestID }) ?? 0
    }

    private func handleWebPlaybackStarted(source: StreamSource, startupLatencyMs: Int) {
        guard activeSource?.id == source.id, isWebEmbedSource(source) else { return }
        isVideoReadyForDisplay = true
        isLoading = false
        isPlaying = true
        error = nil
        LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: startupLatencyMs)
    }

    private func waitForSourceReadiness(_ item: AVPlayerItem, timeoutSeconds: Double) async -> Bool {
        let steps = Int((timeoutSeconds / 0.25).rounded(.up))
        for _ in 0..<max(steps, 1) {
            if Task.isCancelled { return false }
            switch item.status {
            case .readyToPlay:
                return true
            case .failed:
                return false
            case .unknown:
                break
            @unknown default:
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return item.status == .readyToPlay
    }

    private func waitForPlaybackStart(from startSeconds: Double, timeoutSeconds: Double) async -> Bool {
        let steps = Int((timeoutSeconds / 0.25).rounded(.up))
        for _ in 0..<max(steps, 1) {
            if Task.isCancelled { return false }
            if let player {
                let now = player.currentTime().seconds
                if now.isFinite, now > startSeconds + 0.35, isVideoReadyForDisplay {
                    return true
                }
                
                if player.timeControlStatus == .playing,
                   isVideoReadyForDisplay,
                   let size = player.currentItem?.presentationSize,
                   size.width > 16,
                   size.height > 16 {
                    return true
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func startPlaybackWatchdog(for source: StreamSource) {
        stopPlaybackWatchdog()
        let requestID = loadRequestID
        playbackWatchdogTask = Task { @MainActor in
            lastObservedPlaybackSecond = nil
            playbackStagnationTicks = 0
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard activeSource?.id == source.id,
                      loadRequestID == requestID else { return }
                guard isPlaying, !isLoading, isVideoReadyForDisplay else { continue }
                
                let currentSecond = player?.currentTime().seconds ?? 0
                if let last = lastObservedPlaybackSecond, abs(currentSecond - last) < 0.1 {
                    playbackStagnationTicks += 1
                } else {
                    playbackStagnationTicks = 0
                }
                lastObservedPlaybackSecond = currentSecond
                
                let maxStagnation = isP2PSource(source) ? 10 : 6
                if playbackStagnationTicks >= maxStagnation {
                    validateRecoverablePanelStall(
                        for: source,
                        reason: "Playback stalled (watchdog).",
                        expectedItem: player?.currentItem,
                        requestID: requestID
                    )
                    break
                }
            }
        }
    }

    private func validateRecoverablePanelStall(
        for source: StreamSource,
        reason: String,
        expectedItem: AVPlayerItem?,
        requestID: UUID
    ) {
        stallValidationTask?.cancel()
        let startSeconds = player?.currentTime().seconds ?? 0
        stallValidationTask = Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled,
                      loadRequestID == requestID,
                      activeSource?.id == source.id else { return }
                if let expectedItem, player?.currentItem !== expectedItem { return }
                if let player, player.currentTime().seconds > startSeconds + 0.35 {
                    isLoading = false
                    isPlaying = true
                    error = nil
                    startPlaybackWatchdog(for: source)
                    return
                }
            }

            guard loadRequestID == requestID,
                  activeSource?.id == source.id else { return }
            if let expectedItem, player?.currentItem !== expectedItem { return }
            if let player,
               player.timeControlStatus == .playing
                || player.currentTime().seconds > startSeconds + 0.35 {
                isLoading = false
                isPlaying = true
                error = nil
                startPlaybackWatchdog(for: source)
                return
            }
            handleSourceFailure(
                source,
                reason: reason,
                countsAsStall: true,
                expectedRequestID: requestID
            )
        }
    }
    
    private func stopPlaybackWatchdog() {
        playbackWatchdogTask?.cancel()
        playbackWatchdogTask = nil
        playbackStagnationTicks = 0
        lastObservedPlaybackSecond = nil
    }

    private func handleSourceFailure(
        _ failedSource: StreamSource,
        reason: String,
        countsAsStall: Bool = false,
        expectedRequestID: UUID? = nil
    ) {
        guard slot.sources.indices.contains(currentSourceIndex) else { return }
        guard slot.sources[currentSourceIndex].id == failedSource.id else { return }
        if let expectedRequestID, expectedRequestID != loadRequestID { return }

        let failureKind = LivePlaybackFailureKind.classify(
            reason: reason,
            countsAsStall: countsAsStall,
            isNetworkReachable: isNetworkReachable
        )
        lastFailureKind = failureKind
        if !isNetworkReachable {
            pendingRetryAfterNetworkRestore = true
            foregroundResumeValidationTask?.cancel()
            stopPlaybackWatchdog()
            error = nil
            isLoading = true
            isPlaying = true
            return
        }

        let isExplicitProviderRejection = LivePlaybackPolicy
            .isExplicitProviderRejection(reason)
        if isWebEmbedSource(failedSource),
           !isExplicitProviderRejection,
           webRetryAttemptsBySource[failedSource.id, default: 0] < 1 {
            webRetryAttemptsBySource[failedSource.id] = 1
            isLoading = true
            error = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard activeSource?.id == failedSource.id else { return }
                loadCurrentSource(ignoringCircuitBreaker: true)
            }
            return
        }
        
        if isP2PSource(failedSource), countsAsStall, !isP2PSoftRecoveryInFlight {
            let reloads = p2pStallBrokerReloadAttemptsBySource[failedSource.id, default: 0]
            if reloads < 2 {
                p2pStallBrokerReloadAttemptsBySource[failedSource.id] = reloads + 1
                isP2PSoftRecoveryInFlight = true
                foregroundResumeValidationTask?.cancel()
                stopPlaybackWatchdog()
                failedSourceIDs.remove(failedSource.id)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isP2PSoftRecoveryInFlight = false
                    guard activeSource?.id == failedSource.id else { return }
                    loadCurrentSource()
                }
                return
            }
        }
        
        invalidateP2PSessionIfNeeded(for: failedSource, failureKind: failureKind)
        logP2PTimestamp("failure_code", source: failedSource, failureCode: failureKind.rawValue)
        foregroundResumeValidationTask?.cancel()
        stopPlaybackWatchdog()
        failedSourceIDs.insert(failedSource.id)
        LiveSourceHealthStore.recordFailure(for: failedSource, wasStall: countsAsStall, reason: reason)
        
        if let next = nextPlayableSource(after: failedSource),
           let nextIndex = slot.sources.firstIndex(where: { $0.id == next.id }) {
            currentSourceIndex = nextIndex
            loadCurrentSource()
            return
        }

        isLoading = false
        isPlaying = false
        errorTitle = failureKind.title
        error = failureKind.terminalMessage
    }

    private func nextPlayableSource(after source: StreamSource) -> StreamSource? {
        let remaining = slot.sources.filter {
            $0.id != source.id && !failedSourceIDs.contains($0.id)
        }
        return LiveSourceHealthStore.automaticCandidates(in: remaining).first
    }

    private func invalidateP2PSessionIfNeeded(for source: StreamSource, failureKind: LivePlaybackFailureKind) {
        guard isP2PSource(source), failureKind.invalidatesP2PSession else { return }
        Task {
            await AceSessionEngine.shared.invalidateSession(for: source)
        }
    }

    private func logP2PTimestamp(
        _ label: String,
        source: StreamSource?,
        failureCode: String? = nil,
        metadata: [String: String] = [:]
    ) {
        guard let source, isP2PSource(source) else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let cid = source.headers["X-Fotty-P2P-Cid"]
            ?? URLComponents(url: source.url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "infohash" || $0.name == "id" })?
                .value
            ?? "unknown"
        var fields = metadata
        fields["provider"] = source.provider
        fields["cid"] = cid
        fields["failure_code"] = failureCode ?? "none"
        let fieldText = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        NSLog("[Fotty][P2P_TIMELINE] %@=%@ %@", label, timestamp, fieldText)
    }

    private func isP2PSource(_ source: StreamSource) -> Bool {
        let host = source.url.host?.lowercased() ?? ""
        let absolute = source.url.absoluteString.lowercased()
        return host.contains("p2p.pixel-invoice.com")
            || absolute.contains("/proxy/acestream")
            || absolute.contains("/ace/getstream")
            || absolute.hasPrefix("acestream://")
    }

    private func isWebEmbedSource(_ source: StreamSource) -> Bool {
        let absolute = source.url.absoluteString.lowercased()
        let host = source.url.host?.lowercased() ?? ""
        let provider = source.provider.lowercased()

        if absolute.contains(".m3u8") || absolute.contains(".mp4") || absolute.contains("/acestream") {
            return false
        }
        if provider.contains(StringObfuscator.decode([0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x50, 0x6E, 0x1A, 0x16, 0x1D])) {
            return true
        }
        if host.contains(StringObfuscator.decode([0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x50, 0x6E, 0x1A, 0x16, 0x1D, 0xA, 0x6, 0x5D, 0x35, 0x5D, 0x2B])) || absolute.contains("/embed/") {
            return true
        }
        return false
    }
    
    private func updateAudioState() {
        player?.isMuted = !isAudioActive
        player?.volume = isAudioActive ? 1 : 0
    }
    
    private func configureItemFailureObservers(
        for item: AVPlayerItem,
        source: StreamSource,
        requestID: UUID
    ) {
        removeItemFailureObservers()
        let center = NotificationCenter.default
        let token1 = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            handleSourceFailure(
                source,
                reason: "Playback reached end of stream.",
                expectedRequestID: requestID
            )
        }
        let token2 = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            let errorMsg = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "Unknown failure"
            handleSourceFailure(
                source,
                reason: "Failed to play to end: \(errorMsg)",
                expectedRequestID: requestID
            )
        }
        let token3 = center.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let snapshot = diagnosticService.analyze(item)
                guard loadRequestID == requestID,
                      activeSource?.id == source.id else { return }
                if item.status == .failed {
                    handleSourceFailure(
                        source,
                        reason: "AVPlayer Error: \(snapshot.failureReason)",
                        expectedRequestID: requestID
                    )
                }
            }
        }
        playerItemNotificationTokens = [token1, token2, token3]
    }
    
    private func removeItemFailureObservers() {
        for token in playerItemNotificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        playerItemNotificationTokens.removeAll()
    }
}
