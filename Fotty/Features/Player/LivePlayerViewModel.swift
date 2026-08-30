import SwiftUI
import AVKit
import os.log
import Network
import Combine

enum LivePlaybackFailureKind: String {
    case network, providerUnavailable, startupTimeout, stalled, proxy, resumeFailure, unsupportedSource, sourceFailure, unknown

    static func classify(reason: String, countsAsStall: Bool, isNetworkReachable: Bool) -> LivePlaybackFailureKind {
        let normalized = reason.lowercased()
        if !isNetworkReachable || normalized.contains("network") || normalized.contains("offline") { return .network }
        if LivePlaybackPolicy.isExplicitProviderRejection(reason) { return .providerUnavailable }
        if countsAsStall || normalized.contains("stalled") || normalized.contains("frozen") { return .stalled }
        if normalized.contains("never became ready") || normalized.contains("failed to start") || normalized.contains("timed out") || normalized.contains("timeout") || normalized.contains("404") { return .startupTimeout }
        if normalized.contains("proxy") { return .proxy }
        if normalized.contains("resume") || normalized.contains("returning to app") { return .resumeFailure }
        if normalized.contains("unsupported") || normalized.contains("native extraction failed") { return .unsupportedSource }
        if normalized.contains("failed to play") || normalized.contains("player item failed") || normalized.contains("source failed") { return .sourceFailure }
        return .unknown
    }

    var title: String {
        switch self {
        case .network: return "Connection Lost"
        case .providerUnavailable: return "Broadcast Unavailable"
        case .startupTimeout: return "Slow Stream Startup"
        case .stalled: return "Stream Stalled"
        case .proxy: return "Stream Handshake Failed"
        case .resumeFailure: return "Resume Failed"
        case .unsupportedSource: return "Source Not Supported"
        case .sourceFailure: return "Stream Ended Unexpectedly"
        case .unknown: return "Playback Error"
        }
    }

    var terminalMessage: String {
        switch self {
        case .network:
            return "This device lost its network route. Fotty kept the same attempt and will recover it when the connection returns."
        case .providerUnavailable:
            return "The broadcast provider reported that this source is unavailable. Choose another broadcast or try again later."
        case .startupTimeout:
            return "The provider did not deliver advancing video inside the startup window. Fotty retried this broadcast before exhausting the available sources."
        case .stalled:
            return "The video stopped advancing and did not recover during Fotty's recovery window. Try this broadcast again or choose another source."
        case .proxy:
            return "Fotty could not complete the local playback handshake required by this source. Try again or choose another broadcast."
        case .resumeFailure:
            return "This broadcast could not resume after the app returned. Try the same source again."
        case .sourceFailure:
            return "The provider stream ended unexpectedly and Fotty exhausted recovery. Try again or choose another broadcast."
        case .unknown:
            return "Fotty exhausted in-place recovery and the available broadcasts without proving stable video."
        case .unsupportedSource:
            return "The provider returned media this player cannot use. Choose another broadcast."
        }
    }

    var invalidatesP2PSession: Bool {
        switch self {
        case .proxy, .sourceFailure, .startupTimeout: return true
        default: return false
        }
    }
}

enum LivePlaybackMode: String, Equatable {
    case webEmbed
    case native
}

enum LivePlaybackState: Equatable {
    case idle
    case connecting(LivePlaybackMode)
    case playing(LivePlaybackMode)
    case preparingNativeHandoff
    case recovering(LivePlaybackMode)
    case paused(LivePlaybackMode)
    case failed

    var isLoading: Bool {
        if case .connecting = self { return true }
        return false
    }

    var isPlaying: Bool {
        switch self {
        case .playing, .preparingNativeHandoff, .recovering:
            return true
        case .idle, .connecting, .paused, .failed:
            return false
        }
    }
}

@Observable
@MainActor
final class LivePlayerViewModel {
    let event: AnalyticalDataEngine.EventReference
    let providedSessions: [StreamSession]

    var player: AVPlayer?
    var currentSourceIndex = 0
    private(set) var playbackState: LivePlaybackState = .idle
    var isLoading: Bool { playbackState.isLoading }
    var isPlaying: Bool { playbackState.isPlaying }
    var isFillMode = false
    var isPictureInPictureAvailable = false
    var isPictureInPictureActive = false
    var pictureInPictureRequestID: UUID?
    var lastPictureInPictureRequestAt: Date?
    var errorTitle = "Playback Error"
    var error: String?
    var isVideoReadyForDisplay = false
    var showControls = true
    var showStreamDebugSheet = false
    var showSourceSelector = false
    var connectionPhase = "Idle"
    var playbackBannerMessage: String? = nil
    var didApplyLandscape = false
    var webPlaybackCommand: WebPlaybackCommand?
    private(set) var isWebPlaybackUserPaused = false

    private(set) var loadRequestID = UUID()
    private(set) var failedSourceIDs: Set<UUID> = []
    private(set) var lastPlaybackStateChangeAt = Date()
    private(set) var isPlaybackWatchdogArmed = false
    private(set) var stallCount = 0
    private(set) var autoFailoverCount = 0
    private(set) var lastFailureKind: LivePlaybackFailureKind = .unknown
    private(set) var lastFailureReason: String?
    var forceWebEmbedSourceIDs: Set<UUID> = []

    var warmupService = PlaybackWarmupService()
    var p2pSoftRecoveryAttemptsBySource: [UUID: Int] = [:]
    var p2pStallBrokerReloadAttemptsBySource: [UUID: Int] = [:]
    var webStartupRetryAttemptsBySource: [UUID: Int] = [:]
    var webStallRetryAttemptsBySource: [UUID: Int] = [:]
    var isP2PSoftRecoveryInFlight = false

    var isNetworkReachable = true
    var pendingRetryAfterNetworkRestore = false

    var loadTask: Task<Void, Never>?
    var hideTask: Task<Void, Never>?
    var stallValidationTask: Task<Void, Never>?
    var playbackWatchdogTask: Task<Void, Never>?
    var failoverBannerTask: Task<Void, Never>?
    var audioSessionKeepAliveTask: Task<Void, Never>?
    var foregroundResumeValidationTask: Task<Void, Never>?
    var nativeHandoffTask: Task<Void, Never>?
    var networkPathMonitor: NWPathMonitor?
    var streamProxy: LocalStreamProxy?
    var nativeHandoffSession: StreamSession?
    var attemptedNativeCandidateURLs: Set<String> = []

    private let diagnosticService = PlayerDiagnosticService()
    private let validator = StreamContractValidator()

    var attemptDiagnostics: StreamAttemptDiagnostics?
    var lastStartupLatencyMs: Int?
    var playbackStagnationTicks = 0
    var lastObservedPlaybackSecond: Double?
    var sourceAttemptStartedAt: Date?
    var shouldResumeAfterForeground = false
    var playerItemNotificationTokens: [NSObjectProtocol] = []

    let nonP2PStartupTimeoutSeconds = 7.0
    let p2pStartupTimeoutSeconds: TimeInterval = 25.0
    let nonP2PWatchdogStallThresholdTicks = 6
    let p2PWatchdogStallThresholdTicks = 12

    private let logger = Logger(subsystem: "com.jelani.Fotty", category: "LivePlayerViewModel")

    init(event: AnalyticalDataEngine.EventReference, providedSessions: [StreamSession]) {
        self.event = event
        let context = LiveSourceHealthStore.contextKey(for: event)
        let webOnly = providedSessions.filter(StreamPluginProviderMatching.isActivePlayerSession)
        self.providedSessions = LiveSourceHealthStore.rankedSessions(webOnly, contextKey: context)
        if let preferredID = LiveSourceHealthStore.automaticCandidates(
            in: self.providedSessions.map(\.legacySource),
            contextKey: context
        ).first?.id {
            self.currentSourceIndex = self.providedSessions.firstIndex(where: { $0.id == preferredID }) ?? 0
        } else {
            self.currentSourceIndex = 0
        }

        NowPlayingManager.shared.configureRemoteCommands(
            onPlay: { [weak self] in
                if self?.isPlaying == false { self?.togglePlayPause() }
            },
            onPause: { [weak self] in
                if self?.isPlaying == true { self?.togglePlayPause() }
            },
            onToggle: { [weak self] in
                self?.togglePlayPause()
            }
        )
        updateNowPlayingInfo()
    }

    var sessions: [StreamSession] { providedSessions }
    var sources: [StreamSource] { sessions.map(\.legacySource) }
    private var selectedSession: StreamSession? {
        guard sessions.indices.contains(currentSourceIndex) else { return nil }
        return sessions[currentSourceIndex]
    }
    var activeSession: StreamSession? {
        guard let selectedSession else { return nil }
        if let nativeHandoffSession,
           nativeHandoffSession.id == selectedSession.id,
           !forceWebEmbedSourceIDs.contains(selectedSession.id) {
            return nativeHandoffSession
        }
        return selectedSession
    }
    var activeSource: StreamSource? { activeSession?.legacySource }
    var isUsingWebEmbed: Bool {
        guard let source = activeSource else { return false }
        return forceWebEmbedSourceIDs.contains(source.id) || isWebEmbedSource(source)
    }

    func transition(to state: LivePlaybackState, phase: String? = nil) {
        playbackState = state
        if let phase { connectionPhase = phase }
        lastPlaybackStateChangeAt = Date()
    }

    func showNoSourcesAvailable() {
        errorTitle = "No Sources Available"
        error = "No playable stream is available for this match right now."
        transition(to: .failed, phase: "No Sources")
        showControls = true
    }

    func cancelLoading() {
        loadTask?.cancel()
        nativeHandoffTask?.cancel()
        stopPlaybackWatchdog()
        transition(to: .failed, phase: "Cancelled")
    }

    func togglePlayPause() {
        if isUsingWebEmbed {
            let shouldPlay = !isPlaying
            isWebPlaybackUserPaused = !shouldPlay
            if !shouldPlay { nativeHandoffTask?.cancel() }
            webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: shouldPlay)
            transition(
                to: shouldPlay ? .playing(.webEmbed) : .paused(.webEmbed),
                phase: shouldPlay ? "Playing" : "Paused"
            )
            updateNowPlayingInfo()
            showControls = true
            scheduleAutoHide()
            return
        }
        if isPlaying {
            player?.pause()
            transition(to: .paused(.native), phase: "Paused")
            stopPlaybackWatchdog()
        } else {
            MediaAudioSession.configureForPlaybackIfNeeded()
            player?.play()
            transition(to: .playing(.native), phase: "Playing")
            if let source = activeSource { startPlaybackWatchdog(for: source) }
        }
        updateNowPlayingInfo()
        scheduleAutoHide()
    }

    func toggleFillMode() { isFillMode.toggle(); scheduleAutoHide() }

    func togglePictureInPicture() {
        requestPictureInPicture(reason: "Picture in Picture")
    }

    func handlePictureInPictureActivityChanged(_ active: Bool, isBackgrounded: Bool = false) {
        isPictureInPictureActive = active
        if !active {
            lastPictureInPictureRequestAt = nil
        }
        connectionPhase = active ? "PiP Active" : "Playing"
        if !active, isBackgrounded {
            handleAppDidMoveToBackground()
        }
    }

    func handlePictureInPictureFailure(_ message: String, isBackgrounded: Bool = false) {
        isPictureInPictureActive = false
        lastPictureInPictureRequestAt = nil
        connectionPhase = message
        if isBackgrounded {
            handleAppDidMoveToBackground()
        }
    }

    func handlePictureInPictureAvailabilityChanged(_ available: Bool, isBackgrounded: Bool = false) {
        isPictureInPictureAvailable = available
        if !available, !isPictureInPictureActive {
            lastPictureInPictureRequestAt = nil
            if isBackgrounded {
                handleAppDidMoveToBackground()
            }
        }
    }

    private func requestPictureInPicture(reason: String) {
        guard isPictureInPictureAvailable, !isUsingWebEmbed else {
            connectionPhase = "PiP Unavailable"
            scheduleAutoHide()
            return
        }
        lastPictureInPictureRequestAt = Date()
        pictureInPictureRequestID = UUID()
        connectionPhase = reason
        scheduleAutoHide()
    }

    func toggleControlsFromPlaybackTap() {
        if showControls { hideTask?.cancel(); withAnimation { showControls = false } }
        else { withAnimation { showControls = true }; scheduleAutoHide() }
    }

    func revealWebControlsFromProviderTap() {
        // A provider tap may itself toggle playback. Never cover it with a
        // second transport action or hide the only known working Play button.
        showControls = true
        scheduleAutoHide()
    }

    func scheduleAutoHide() {
        hideTask?.cancel()
        let delay = isUsingWebEmbed ? LivePlaybackPolicy.webControlAutoHideSeconds : 10
        hideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, showControls, isPlaying, error == nil, !isLoading, playbackStagnationTicks == 0 else { return }
            guard !showSourceSelector, !showStreamDebugSheet else { return }
            withAnimation { showControls = false }
        }
    }

    func resetFailoverTracking() {
        nativeHandoffTask?.cancel()
        nativeHandoffTask = nil
        nativeHandoffSession = nil
        attemptedNativeCandidateURLs.removeAll()
        failedSourceIDs.removeAll(); autoFailoverCount = 0
        p2pSoftRecoveryAttemptsBySource.removeAll(); p2pStallBrokerReloadAttemptsBySource.removeAll()
        webStartupRetryAttemptsBySource.removeAll(); webStallRetryAttemptsBySource.removeAll()
        forceWebEmbedSourceIDs.removeAll(); lastFailureReason = nil
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            handleAppDidBecomeActive()
        case .inactive:
            // Inactive also covers transient system overlays. Do not force PiP
            // or pause here; AVKit's automatic-from-inline policy and the
            // explicit PiP control own that transition. Background is the
            // authoritative point for suspending non-PiP playback.
            break
        case .background:
            handleAppDidMoveToBackground()
        @unknown default:
            handleAppDidMoveToBackground()
        }
    }

    private func handleAppDidMoveToBackground() {
        foregroundResumeValidationTask?.cancel(); audioSessionKeepAliveTask?.cancel()
        shouldResumeAfterForeground = isPlaying

        if shouldKeepPlaybackAliveForPictureInPicture {
            connectionPhase = isPictureInPictureActive ? "PiP Active" : "Starting PiP"
            return
        }

        if isPlaying, isUsingWebEmbed {
            transition(to: .paused(.webEmbed), phase: "Paused (Background)")
            stopPlaybackWatchdog()
            return
        }

        if isPlaying, !isUsingWebEmbed {
            player?.pause()
            transition(to: .paused(.native), phase: "Paused (Background)")
        }
        stopPlaybackWatchdog()
    }

    private var shouldKeepPlaybackAliveForPictureInPicture: Bool {
        if isPictureInPictureActive { return true }
        guard isPictureInPictureAvailable,
              !isUsingWebEmbed,
              isPlaying,
              error == nil,
              let lastPictureInPictureRequestAt else {
            return false
        }
        return Date().timeIntervalSince(lastPictureInPictureRequestAt) < 10
    }

    var keepsPlaybackAliveInBackground: Bool {
        shouldKeepPlaybackAliveForPictureInPicture
    }

    private func handleAppDidBecomeActive() {
        MediaAudioSession.configureForPlaybackIfNeeded(); startAudioSessionKeepAlive()
        guard shouldResumeAfterForeground else { return }
        shouldResumeAfterForeground = false
        if isUsingWebEmbed {
            transition(to: .playing(.webEmbed), phase: "Playing")
            scheduleAutoHide()
            return
        }
        guard let source = activeSource, let player, let item = player.currentItem else { loadCurrentSource(); return }
        let requestID = loadRequestID
        if item.status == .failed {
            handleSourceStartupFailure(source, reason: "Resume failed.", expectedRequestID: requestID)
            return
        }
        let start = player.currentTime().seconds
        player.play()
        transition(to: .recovering(.native), phase: "Resuming")
        startPlaybackWatchdog(for: source)
        foregroundResumeValidationTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == source.id,
                  self.player?.currentItem === item,
                  !isLoading,
                  isPlaying else { return }
            let now = self.player?.currentTime().seconds ?? start
            if abs(now - start) < 0.1, self.player?.timeControlStatus != .paused {
                validateRecoverableStall(
                    for: source,
                    reason: "Resume stalled.",
                    expectedItem: item,
                    requestID: requestID
                )
            } else { transition(to: .playing(.native), phase: "Playing") }
        }
    }

    func startAudioSessionKeepAlive() {
        // Redundant with MediaAudioSession observers. Removing to prevent audio session activation glitches.
    }

    func startNetworkPathMonitoring() {
        let monitor = NWPathMonitor()
        networkPathMonitor = monitor
        monitor.pathUpdateHandler = { path in Task { @MainActor in self.handleNetworkReachabilityChange(path.status == .satisfied) } }
        monitor.start(queue: DispatchQueue(label: "network.monitor"))
    }

    func stopNetworkPathMonitoring() { networkPathMonitor?.cancel(); networkPathMonitor = nil }

    /// Internal so the continuity policy can be regression-tested without
    /// constructing a real `NWPathMonitor` or changing the device network.
    func handleNetworkReachabilityChange(_ reachable: Bool) {
        let was = isNetworkReachable; isNetworkReachable = reachable
        if !reachable {
            guard was else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard !self.isNetworkReachable else { return } // Recovered within grace period
                pendingRetryAfterNetworkRestore = true
                transition(to: .recovering(isUsingWebEmbed ? .webEmbed : .native), phase: "Waiting For Network")
                stopPlaybackWatchdog()
            }
            return
        }
        guard !was, pendingRetryAfterNetworkRestore, !sources.isEmpty else { return }
        pendingRetryAfterNetworkRestore = false
        resumeCurrentAttemptAfterNetworkRestore()
    }

    private func resumeCurrentAttemptAfterNetworkRestore() {
        guard let source = activeSource else { return }

        error = nil
        if isUsingWebEmbed {
            transition(
                to: isVideoReadyForDisplay ? .playing(.webEmbed) : .connecting(.webEmbed),
                phase: isVideoReadyForDisplay ? "Playing" : "Reconnecting..."
            )
            scheduleAutoHide()
            return
        }

        guard let player, let item = player.currentItem else {
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        }
        guard item.status != .failed else {
            // The item itself is no longer recoverable. Retry the same selected
            // source first; a source change still requires a proven new failure.
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        }

        let requestID = loadRequestID
        let start = player.currentTime().seconds
        MediaAudioSession.configureForPlaybackIfNeeded()
        player.play()
        transition(to: .recovering(.native), phase: "Reconnecting...")
        startPlaybackWatchdog(for: source)

        foregroundResumeValidationTask?.cancel()
        foregroundResumeValidationTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == source.id,
                  self.player?.currentItem === item,
                  isPlaying else { return }
            let now = self.player?.currentTime().seconds ?? start
            if abs(now - start) < 0.1,
               self.player?.timeControlStatus != .paused {
                validateRecoverableStall(
                    for: source,
                    reason: "Network recovery stalled.",
                    expectedItem: item,
                    requestID: requestID
                )
            } else {
                transition(to: .playing(.native), phase: "Playing")
            }
        }
    }

    func loadCurrentSource(ignoringCircuitBreaker: Bool = false) {
        loadTask?.cancel()
        nativeHandoffTask?.cancel()
        nativeHandoffTask = nil
        stallValidationTask?.cancel()
        foregroundResumeValidationTask?.cancel()
        let rid = UUID(); loadRequestID = rid
        webPlaybackCommand = nil
        isWebPlaybackUserPaused = false
        guard let session = activeSession else {
            showNoSourcesAvailable()
            return
        }
        let source = session.legacySource

        if !ignoringCircuitBreaker, LiveSourceHealthStore.isTemporarilyUnavailable(source) {
            failedSourceIDs.insert(source.id)
            if let next = nextPlayableSource(after: source),
               let index = sources.firstIndex(where: { $0.id == next.id }) {
                currentSourceIndex = index
                showPlaybackBanner("Skipping a recently failing source")
                loadCurrentSource()
            } else {
                errorTitle = "Sources Temporarily Unavailable"
                error = "Automatic switching is paused because every source failed recently. Choose a source to retry it manually."
                transition(to: .failed, phase: "Choose Broadcast Source")
                showControls = true
            }
            return
        }

        transition(to: .connecting(isWebEmbedSource(source) ? .webEmbed : .native), phase: "Connecting...")
        isVideoReadyForDisplay = false; error = nil; sourceAttemptStartedAt = Date()
        FottyQualityStore.shared.record(
            category: .playback,
            name: "attempt_started",
            outcome: .info,
            details: ["mode": isWebEmbedSource(source) ? "web_embed" : "native"]
        )
        removeItemFailureObservers(); stopPlaybackWatchdog(); streamProxy?.stop(); streamProxy = nil
        loadTask = Task {
            if isDiscoveryOnlySource(source) { handleSourceStartupFailure(source, reason: "Resolver only.", expectedRequestID: rid); return }
            if isWebEmbedSource(source) {
                player?.pause()
                player = nil
                guard !Task.isCancelled, loadRequestID == rid else { return }
                transition(to: .connecting(.webEmbed), phase: "Starting Web Stream...")
                enterLandscapeIfNeeded()
                return
            }
            do {
                if player == nil { player = AVPlayer() } else { player?.replaceCurrentItem(with: nil) }
                guard let player else { return }
                let p2p = isP2PSource(source)
                player.automaticallyWaitsToMinimizeStalling = !p2p
                let url = try await preparePlaybackURL(for: session, requestID: rid)
                guard !Task.isCancelled, loadRequestID == rid else { return }

                // --- AUDIT FIX [CONTRACT VALIDATION] ---
                connectionPhase = "Validating Source..."
                let validation = await validator.validate(url, headers: source.headers)
                if case .invalid(let reason) = validation {
                    handleSourceStartupFailure(source, reason: "Stream Contract Failed: \(reason)", expectedRequestID: rid)
                    return
                }

                // CRITICAL: Must pass headers to AVURLAsset otherwise many providers (Referer/UA checks) will fail.
                let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = p2p ? 3.0 : 12.0
                item.canUseNetworkResourcesForLiveStreamingWhilePaused = p2p
                configureItemFailureObservers(for: item, source: source, requestID: rid)
                player.replaceCurrentItem(with: item)
                connectionPhase = p2p ? "Buffering P2P..." : "Buffering..."
                requestPlaybackStart(player: player, isP2P: p2p)
                let ready = await waitForSourceReadiness(item, timeoutSeconds: p2p ? p2pStartupTimeoutSeconds : nonP2PStartupTimeoutSeconds)
                guard !Task.isCancelled, loadRequestID == rid, ready else {
                    let snapshot = diagnosticService.analyze(item)
                    handleSourceStartupFailure(source, reason: "Not ready. \(snapshot.failureReason)", expectedRequestID: rid)
                    return
                }
                requestPlaybackStart(player: player, isP2P: p2p)
                let started = await waitForPlaybackStart(player: player, timeoutSeconds: 3.0)
                guard !Task.isCancelled, loadRequestID == rid, started else {
                    handleSourceStartupFailure(source, reason: "Startup timeout.", expectedRequestID: rid)
                    return
                }
                handleSuccessfulStartup(source: source, expectedRequestID: rid)
            } catch { handleSourceStartupFailure(source, reason: error.localizedDescription, expectedRequestID: rid) }
        }
    }

    private func requestPlaybackStart(player: AVPlayer, isP2P: Bool) {
        MediaAudioSession.configureForPlaybackIfNeeded()
        if isP2P {
            player.playImmediately(atRate: 1.0)
        } else {
            player.play()
        }
    }

    private func preparePlaybackURL(for session: StreamSession, requestID: UUID) async throws -> URL {
        let source = session.legacySource

        if session.isP2PProxy || isP2PSource(source) {
            let prepared = try await AceSessionEngine.shared.prepareSession(for: source, forceRestart: false)
            return prepared.playbackURL
        }

        let remoteURL = session.playableURL

        // Use LocalStreamProxy for non-P2P sources with headers to ensure segment-level header injection.
        guard !source.headers.isEmpty else {
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

        self.streamProxy = proxy
        return localURL
    }

    private func localProxyURL(for remoteURL: URL, proxyPort: UInt16) -> URL? {
        var components = URLComponents()
        components.scheme = "http"; components.host = "127.0.0.1"; components.port = Int(proxyPort); components.path = "/proxy"
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }

    private func handleSuccessfulStartup(
        source: StreamSource,
        reportedLatencyMs: Int? = nil,
        expectedRequestID: UUID? = nil
    ) {
        guard activeSource?.id == source.id else { return }
        if let expectedRequestID, expectedRequestID != loadRequestID { return }
        let completedNativeHandoff = playbackState == .preparingNativeHandoff
        stallValidationTask?.cancel(); failedSourceIDs.remove(source.id); isP2PSoftRecoveryInFlight = false; error = nil
        if let reportedLatencyMs {
            lastStartupLatencyMs = reportedLatencyMs
        } else if let s = sourceAttemptStartedAt {
            lastStartupLatencyMs = Int(Date().timeIntervalSince(s) * 1000)
        }
        LiveSourceHealthStore.recordSuccess(
            for: source,
            startupLatencyMs: lastStartupLatencyMs,
            contextKey: LiveSourceHealthStore.contextKey(for: event)
        )
        FottyQualityStore.shared.record(
            category: .playback,
            name: completedNativeHandoff ? "native_handoff" : "decoded_progress",
            outcome: .success,
            durationMilliseconds: completedNativeHandoff ? nil : lastStartupLatencyMs,
            details: ["mode": isWebEmbedSource(source) ? "web_embed" : "native"]
        )
        transition(to: .playing(isWebEmbedSource(source) ? .webEmbed : .native), phase: "Playing")
        enterLandscapeIfNeeded()
        if !isWebEmbedSource(source) {
            startPlaybackWatchdog(for: source)
        }
        scheduleAutoHide()
        lastPlaybackStateChangeAt = Date()
        updateNowPlayingInfo()
    }

    private func waitForSourceReadiness(_ item: AVPlayerItem, timeoutSeconds: Double) async -> Bool {
        for _ in 0..<Int(timeoutSeconds * 4) {
            if Task.isCancelled { return false }
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return item.status == .readyToPlay
    }

    private func waitForPlaybackStart(player: AVPlayer, timeoutSeconds: Double) async -> Bool {
        for _ in 0..<Int(timeoutSeconds * 4) {
            if Task.isCancelled { return false }
            if player.rate > 0 || player.timeControlStatus == .playing {
                return true
            }
            if player.currentTime().seconds > 0.1 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func configureItemFailureObservers(
        for item: AVPlayerItem,
        source: StreamSource,
        requestID: UUID
    ) {
        removeItemFailureObservers()
        let center = NotificationCenter.default
        let f = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleSourceStartupFailure(source, reason: "End reached.", expectedRequestID: requestID)
            }
        }
        let s = center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.validateRecoverableStall(
                    for: source,
                    reason: "Stalled.",
                    expectedItem: item,
                    requestID: requestID
                )
            }
        }
        let e = center.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if let self = self {
                    let snapshot = self.diagnosticService.analyze(item)
                    if item.status == .failed {
                        self.handleSourceStartupFailure(
                            source,
                            reason: "AVPlayer Error: \(snapshot.failureReason)",
                            expectedRequestID: requestID
                        )
                    } else if self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                        self.validateRecoverableStall(
                            for: source,
                            reason: "AVPlayer interruption: \(snapshot.failureReason)",
                            expectedItem: item,
                            requestID: requestID
                        )
                    }
                }
            }
        }
        playerItemNotificationTokens = [f, s, e]
    }

    func removeItemFailureObservers() { playerItemNotificationTokens.forEach { NotificationCenter.default.removeObserver($0) }; playerItemNotificationTokens = [] }

    func handleSourceStartupFailure(
        _ source: StreamSource,
        reason: String,
        countsAsStall: Bool = false,
        expectedRequestID: UUID? = nil
    ) {
        guard activeSource?.id == source.id else { return }
        if let expectedRequestID, expectedRequestID != loadRequestID { return }
        let failureKind = LivePlaybackFailureKind.classify(reason: reason, countsAsStall: countsAsStall, isNetworkReachable: isNetworkReachable)
        lastFailureKind = failureKind
        lastFailureReason = reason
        if !isNetworkReachable {
            // Do not punish or replace a provider because the device briefly
            // lost its route. Preserve the exact attempt and let it resume.
            pendingRetryAfterNetworkRestore = true
            stallValidationTask?.cancel()
            stopPlaybackWatchdog()
            error = nil
            transition(to: .recovering(isUsingWebEmbed ? .webEmbed : .native), phase: "Waiting For Network")
            FottyQualityStore.shared.record(
                category: .playback,
                name: "network_interruption",
                outcome: .info,
                details: ["mode": isUsingWebEmbed ? "web_embed" : "native"]
            )
            return
        }
        if nativeHandoffSession?.id == source.id,
           !forceWebEmbedSourceIDs.contains(source.id) {
            nativeHandoffSession = nil
            forceWebEmbedSourceIDs.insert(source.id)
            transition(to: .recovering(.webEmbed), phase: "Returning to web playback")
            FottyQualityStore.shared.record(
                category: .playback,
                name: "native_handoff_return",
                outcome: .recovered,
                details: ["failure_kind": failureKind.rawValue]
            )
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        }
        if !isP2PSource(source),
           !isWebEmbedSource(source),
           !countsAsStall,
           !forceWebEmbedSourceIDs.contains(source.id) {
            forceWebEmbedSourceIDs.insert(source.id)
            loadCurrentSource()
            return
        }

        // Slow provider embeds often succeed when the same document is loaded
        // once more. Keep the selected broadcast in place for one controlled
        // retry instead of forcing repeated taps or immediately switching away.
        let isExplicitProviderRejection = LivePlaybackPolicy
            .isExplicitProviderRejection(reason)
        if isWebEmbedSource(source), !isExplicitProviderRejection {
            if countsAsStall,
               webStallRetryAttemptsBySource[source.id, default: 0] < 1 {
                webStallRetryAttemptsBySource[source.id] = 1
                retryCurrentWebSource(source, phase: "Reconnecting to this broadcast")
                return
            }
            if !countsAsStall,
               webStartupRetryAttemptsBySource[source.id, default: 0] < 1 {
                webStartupRetryAttemptsBySource[source.id] = 1
                retryCurrentWebSource(source, phase: "Retrying this broadcast")
                return
            }
        }

        // Soft recovery for P2P: reuse the existing broker session once before failing over.
        if isP2PSource(source), countsAsStall, p2pSoftRecoveryAttemptsBySource[source.id, default: 0] < 1 {
            p2pSoftRecoveryAttemptsBySource[source.id] = 1
            let recoveryRequestID = loadRequestID
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard activeSource?.id == source.id,
                      loadRequestID == recoveryRequestID else { return }
                loadCurrentSource()
            }
            return
        }
        invalidateP2PSessionIfNeeded(for: source, failureKind: failureKind)
        failedSourceIDs.insert(source.id)
        LiveSourceHealthStore.recordFailure(for: source, wasStall: countsAsStall, reason: reason)
        if let next = nextPlayableSource(after: source), let idx = sources.firstIndex(where: { $0.id == next.id }) {
            autoFailoverCount += 1
            FottyQualityStore.shared.record(
                category: .playback,
                name: "automatic_failover",
                outcome: .failure,
                details: ["failure_kind": failureKind.rawValue]
            )
            currentSourceIndex = idx
            showPlaybackBanner("Switching to another source")
            loadCurrentSource()
        }
        else {
            FottyQualityStore.shared.record(
                category: .playback,
                name: "terminal_failure",
                outcome: .failure,
                details: ["failure_kind": failureKind.rawValue]
            )
            errorTitle = failureKind.title
            error = failureKind.terminalMessage
            showControls = true
            transition(to: .failed, phase: "Choose Broadcast Source")
        }
    }

    private func retryCurrentWebSource(_ source: StreamSource, phase: String) {
        let expectedSourceID = source.id
        transition(to: .recovering(.webEmbed), phase: phase)
        showPlaybackBanner(phase)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard activeSource?.id == expectedSourceID else { return }
            loadCurrentSource(ignoringCircuitBreaker: true)
        }
    }

    func handleWebEmbedFailure(sourceID: UUID, requestID: UUID, reason: String) {
        guard let source = activeSource,
              source.id == sourceID,
              loadRequestID == requestID,
              isUsingWebEmbed,
              !isWebPlaybackUserPaused else { return }
        let normalized = reason.lowercased()
        let countsAsStall = normalized.contains("stalled") || normalized.contains("frozen")
        handleSourceStartupFailure(
            source,
            reason: reason,
            countsAsStall: countsAsStall,
            expectedRequestID: requestID
        )
    }

    func handleWebEmbedPlaybackStarted(sourceID: UUID, requestID: UUID, startupLatencyMs: Int) {
        guard let source = activeSource,
              source.id == sourceID,
              loadRequestID == requestID,
              isUsingWebEmbed else { return }
        isVideoReadyForDisplay = true
        handleSuccessfulStartup(
            source: source,
            reportedLatencyMs: startupLatencyMs,
            expectedRequestID: requestID
        )
    }

    func handleWebEmbedPlaybackRecovered(sourceID: UUID, requestID: UUID) {
        guard activeSource?.id == sourceID,
              loadRequestID == requestID,
              isUsingWebEmbed,
              !isWebPlaybackUserPaused else { return }
        error = nil
        FottyQualityStore.shared.record(
            category: .playback,
            name: "in_place_recovery",
            outcome: .recovered,
            details: ["recovery_kind": "decoded_web_progress"]
        )
        transition(to: .playing(.webEmbed), phase: "Playing")
        scheduleAutoHide()
    }

    func handleWebEmbedTransportState(
        _ state: WebPlaybackTransportState, sourceID: UUID, requestID: UUID
    ) {
        guard activeSource?.id == sourceID, loadRequestID == requestID,
              isUsingWebEmbed, isVideoReadyForDisplay,
              connectionPhase != "Paused (Background)", error == nil else { return }
        switch state {
        case .paused:
            isWebPlaybackUserPaused = true
            nativeHandoffTask?.cancel()
            transition(to: .paused(.webEmbed), phase: "Paused")
            showControls = true
        case .playing:
            isWebPlaybackUserPaused = false
            if playbackState != .preparingNativeHandoff {
                transition(to: .playing(.webEmbed), phase: "Playing")
            }
        }
        updateNowPlayingInfo()
        scheduleAutoHide()
    }

    func finishNativeHandoffPreparation(sourceID: UUID, requestID: UUID) {
        guard activeSource?.id == sourceID, loadRequestID == requestID,
              isUsingWebEmbed, playbackState == .preparingNativeHandoff else { return }
        transition(to: .playing(.webEmbed), phase: "Playing")
    }

    func handleNativePlaybackCandidate(
        _ candidate: NativeWebPlaybackCandidate,
        sourceID: UUID,
        requestID: UUID
    ) {
        guard activeSource?.id == sourceID,
              loadRequestID == requestID,
              isUsingWebEmbed,
              isVideoReadyForDisplay,
              isPlaying,
              nativeHandoffTask == nil else { return }

        let candidateKey = "\(sourceID.uuidString)|\(candidate.url.absoluteString)"
        guard attemptedNativeCandidateURLs.count < 12,
              attemptedNativeCandidateURLs.insert(candidateKey).inserted,
              let selectedSession else { return }

        let nativeSession = StreamSession(
            id: selectedSession.id,
            matchID: selectedSession.matchID,
            title: selectedSession.title,
            playableURL: candidate.url,
            streamType: candidate.url.pathExtension.lowercased() == "mp4" ? .mp4 : .hls,
            providerName: selectedSession.providerName,
            requiredHeaders: candidate.headers,
            qualityLabel: selectedSession.qualityLabel,
            canRefresh: true,
            validationStatus: .validated,
            diagnosticMetadata: [
                "delivery": "native_web_handoff",
                "manifest_result": "captured_after_decoded_web_playback",
                "referer": candidate.headers["Referer"] ?? ""
            ],
            activePeers: selectedSession.activePeers
        )

        transition(to: .preparingNativeHandoff, phase: "Playing")
        nativeHandoffTask = Task { [weak self] in
            guard let self else { return }
            var candidateProxy: LocalStreamProxy?
            var adoptedCandidate = false
            defer {
                if !adoptedCandidate { candidateProxy?.stop() }
                if self.loadRequestID == requestID { self.nativeHandoffTask = nil }
            }

            let validation = await validator.validate(candidate.url, headers: candidate.headers)
            guard case .valid = validation,
                  !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == sourceID,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            let playbackURL: URL
            do {
                let prepared = try await prepareNativeHandoffURL(for: candidate)
                playbackURL = prepared.url
                candidateProxy = prepared.proxy
            } catch {
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            let assetHeaders = candidateProxy == nil ? candidate.headers : [:]
            let asset = AVURLAsset(
                url: playbackURL,
                options: ["AVURLAssetHTTPHeaderFieldsKey": assetHeaders]
            )
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 12
            let candidatePlayer = AVPlayer(playerItem: item)
            candidatePlayer.automaticallyWaitsToMinimizeStalling = true
            candidatePlayer.isMuted = true

            let ready = await waitForSourceReadiness(item, timeoutSeconds: 7)
            guard ready,
                  !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == sourceID,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                candidatePlayer.pause()
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            candidatePlayer.play()
            let started = await waitForPlaybackStart(player: candidatePlayer, timeoutSeconds: 4)
            guard started,
                  !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == sourceID,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                candidatePlayer.pause()
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            nativeHandoffSession = nativeSession
            player?.pause()
            streamProxy?.stop()
            player = candidatePlayer
            streamProxy = candidateProxy
            adoptedCandidate = true
            isVideoReadyForDisplay = false
            configureItemFailureObservers(
                for: item,
                source: nativeSession.legacySource,
                requestID: requestID
            )
            handleSuccessfulStartup(source: nativeSession.legacySource, expectedRequestID: requestID)
            showPlaybackBanner("Native player ready")

            Task { @MainActor [weak self, weak candidatePlayer] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self,
                      self.loadRequestID == requestID,
                      self.activeSource?.id == sourceID else { return }
                let muted = AppRuntime.shouldMutePlaybackForTesting
                candidatePlayer?.isMuted = muted
                candidatePlayer?.volume = muted ? 0 : 1
            }
        }
    }

    private func prepareNativeHandoffURL(
        for candidate: NativeWebPlaybackCandidate
    ) async throws -> (url: URL, proxy: LocalStreamProxy?) {
        guard !candidate.headers.isEmpty else { return (candidate.url, nil) }

        let proxy = LocalStreamProxy(headers: candidate.headers, cookies: [])
        try await proxy.start()
        var ready = false
        for _ in 0..<5 {
            if await proxy.ping() {
                ready = true
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard ready,
              let port = proxy.port,
              let localURL = localProxyURL(for: candidate.url, proxyPort: port) else {
            proxy.stop()
            throw ProcessorError.proxyError
        }
        return (localURL, proxy)
    }

    func selectSourceManually(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        resetFailoverTracking()
        currentSourceIndex = index
        loadCurrentSource(ignoringCircuitBreaker: true)
    }

    private func invalidateP2PSessionIfNeeded(for source: StreamSource, failureKind: LivePlaybackFailureKind) {
        guard isP2PSource(source), failureKind.invalidatesP2PSession else { return }
        Task {
            await AceSessionEngine.shared.invalidateSession(for: source)
        }
    }

    func startPlaybackWatchdog(for source: StreamSource) {
        stopPlaybackWatchdog(); isPlaybackWatchdogArmed = true
        let requestID = loadRequestID
        playbackWatchdogTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      loadRequestID == requestID,
                      activeSource?.id == source.id,
                      !isUsingWebEmbed,
                      !isLoading,
                      isPlaying,
                      Date().timeIntervalSince(lastPlaybackStateChangeAt) > 5.0,
                      let p = player else { continue }
                if p.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    let now = p.currentTime().seconds
                    if let last = lastObservedPlaybackSecond, abs(now - last) < 0.05 { playbackStagnationTicks += 1 }
                    else { playbackStagnationTicks = 1; lastObservedPlaybackSecond = now }
                    if playbackStagnationTicks >= (isP2PSource(source) ? p2PWatchdogStallThresholdTicks : nonP2PWatchdogStallThresholdTicks) {
                        validateRecoverableStall(
                            for: source,
                            reason: "Frozen.",
                            expectedItem: p.currentItem,
                            requestID: requestID
                        )
                        return
                    }
                } else { playbackStagnationTicks = 0; lastObservedPlaybackSecond = p.currentTime().seconds }
            }
        }
    }

    private func validateRecoverableStall(
        for source: StreamSource,
        reason: String,
        expectedItem: AVPlayerItem? = nil,
        requestID: UUID? = nil
    ) {
        let expectedRequestID = requestID ?? loadRequestID
        stallValidationTask?.cancel()
        let start = player?.currentTime().seconds ?? 0
        stallValidationTask = Task {
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled,
                      loadRequestID == expectedRequestID,
                      activeSource?.id == source.id else { return }
                if let expectedItem, player?.currentItem !== expectedItem { return }
                if let p = player, p.currentTime().seconds > start + 0.35 {
                    recoverFromSoftStall(for: source, requestID: expectedRequestID)
                    return
                }
            }
            guard loadRequestID == expectedRequestID,
                  activeSource?.id == source.id else { return }
            if let expectedItem, player?.currentItem !== expectedItem { return }
            if let player,
               player.timeControlStatus == .playing
                || player.currentTime().seconds > start + 0.35 {
                recoverFromSoftStall(for: source, requestID: expectedRequestID)
                return
            }
            handleSourceStartupFailure(
                source,
                reason: reason,
                countsAsStall: true,
                expectedRequestID: expectedRequestID
            )
        }
    }

    private func recoverFromSoftStall(for source: StreamSource, requestID: UUID) {
        guard activeSource?.id == source.id, loadRequestID == requestID else { return }
        error = nil
        transition(to: .playing(.native), phase: "Playing")
        if isP2PSource(source) { player?.playImmediately(atRate: 1.0) } else { player?.play() }
        startPlaybackWatchdog(for: source)
    }
    func stopPlaybackWatchdog() { playbackWatchdogTask?.cancel(); isPlaybackWatchdogArmed = false; playbackStagnationTicks = 0 }
    func showPlaybackBanner(_ message: String) {
        FottyLogger.shared.log(.streamStart, message: "playback_notice: \(message)", params: ["event_id": event.id])
        failoverBannerTask?.cancel()
        withAnimation { playbackBannerMessage = message }
        failoverBannerTask = Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { playbackBannerMessage = nil }
        }
    }
    private func preferredInitialSourceIndex() -> Int {
        let candidates = LiveSourceHealthStore.automaticCandidates(
            in: sources,
            contextKey: LiveSourceHealthStore.contextKey(for: event)
        )
        guard let bestID = candidates.first?.id else { return 0 }
        return sources.firstIndex(where: { $0.id == bestID }) ?? 0
    }

    private func nextPlayableSource(after source: StreamSource) -> StreamSource? {
        let remaining = sources.filter { $0.id != source.id && !failedSourceIDs.contains($0.id) }
        return LiveSourceHealthStore.automaticCandidates(
            in: remaining,
            contextKey: LiveSourceHealthStore.contextKey(for: event)
        ).first
    }

    private func enterLandscapeIfNeeded() { if !didApplyLandscape { didApplyLandscape = true; PlayerOrientationController.enterLandscape() } }
    func logP2PTimestamp(_ label: String, source: StreamSource?, failureCode: String? = nil, metadata: [String: String] = [:]) {
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
    func isP2PSource(_ source: StreamSource) -> Bool {
        let abs = source.url.absoluteString.lowercased()
        let host = source.url.host?.lowercased() ?? ""
        return host.contains("p2p.pixel-invoice.com") || abs.contains("/proxy/acestream") || abs.contains("/ace/getstream") || abs.hasPrefix("acestream://") || source.headers["X-Fotty-P2P"] == "true"
    }
    func isWebEmbedSource(_ source: StreamSource) -> Bool {
        if isP2PSource(source) { return false }
        let abs = source.url.absoluteString.lowercased()
        let host = source.url.host?.lowercased() ?? ""
        let prov = source.provider.lowercased()
        if abs.contains(".m3u8") || abs.contains(".mp4") || abs.contains("/acestream") { return false }
        return abs.contains("/embed/")
            || host.contains("embed")
            || prov.contains("embed")
            || source.headers["X-Fotty-Embed"] == "true"
            || source.headers["X-Fotty-Web-Embed"] == "true"
    }
    func isDiscoveryOnlySource(_ source: StreamSource) -> Bool { source.headers["X-Fotty-Discovery-Only"] == "true" }

    func updateNowPlayingInfo() {
        let title = event.title ?? "Live Match"
        let category = event.category?.uppercased() ?? "LIVE"
        let subtitle = "\(category) • \(activeSource?.provider ?? "Live Stream")"
        NowPlayingManager.shared.updateNowPlaying(title: title, subtitle: subtitle, isPlaying: isPlaying)
    }

    func cleanup() {
        loadTask?.cancel(); hideTask?.cancel(); stallValidationTask?.cancel(); playbackWatchdogTask?.cancel()
        failoverBannerTask?.cancel(); audioSessionKeepAliveTask?.cancel(); foregroundResumeValidationTask?.cancel(); nativeHandoffTask?.cancel()
        stopNetworkPathMonitoring(); removeItemFailureObservers()
        player?.pause(); player = nil; streamProxy?.stop(); streamProxy = nil; nativeHandoffSession = nil
        transition(to: .idle, phase: "Idle")
        NowPlayingManager.shared.clearNowPlaying()
    }
}
