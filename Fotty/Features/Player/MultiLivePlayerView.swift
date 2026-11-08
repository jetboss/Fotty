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

    func isWebEmbed(_ source: StreamSource) -> Bool {
        if let session = sessions.first(where: { $0.id == source.id }) {
            return LivePlaybackSourcePolicy.isWebEmbed(session)
        }
        return LivePlaybackSourcePolicy.isWebEmbed(source)
    }

    func recoveryAction(
        for source: StreamSource, reason: String, countsAsStall: Bool,
        isNetworkReachable: Bool, webStartupRetryCount: Int,
        webStallRetryCount: Int, nativeStartupRetryCount: Int
    ) -> LivePlaybackRecoveryPolicy.Action {
        let session = sessions.first { $0.id == source.id }
        let isWeb = isWebEmbed(source)
        return LivePlaybackRecoveryPolicy.action(for: .init(
            reason: reason, countsAsStall: countsAsStall,
            isNetworkReachable: isNetworkReachable,
            isNativeHandoff: false, isWebEmbed: isWeb,
            isForcedWebEmbed: isWeb,
            webStartupRetryCount: webStartupRetryCount,
            webStallRetryCount: webStallRetryCount,
            isDirectMedia: session?.playbackContract.endpoint == .directMedia,
            nativeStartupRetryCount: nativeStartupRetryCount
        ))
    }
}

/// Layout belongs to each panel's allocated width, not the fitted video's width.
/// Source identity and independent audio controls must never collapse into a
/// single over-compressed row in the secondary Focus panel.
enum MultiLivePanelChromeLayout: Equatable {
    case inline
    case stacked
    case accessibility

    static func layout(width: CGFloat, isAccessibilitySize: Bool) -> Self {
        if isAccessibilitySize { return .accessibility }
        return width >= 600 ? .inline : .stacked
    }

    var rowCount: Int {
        switch self {
        case .inline: return 1
        case .stacked: return 2
        case .accessibility: return 3
        }
    }

    func reservedHeight(controlHeight: CGFloat) -> CGFloat {
        CGFloat(rowCount) * max(44, controlHeight) + CGFloat(rowCount - 1) * 6 + 12 + 1
    }
}

/// Only offer enlargement when the window can actually render unequal panes.
enum MultiLiveLayoutPolicy {
    static func canFocus(in size: CGSize) -> Bool {
        size.width >= 900 && size.width > size.height
    }

    static func surfaceSize(in size: CGSize, chromeHeight: CGFloat, isRecovering: Bool) -> CGSize {
        let availableHeight = max(0, size.height - chromeHeight)
        // Recovery is text and actions, not 16:9 media. Let its scroll surface
        // use the remaining pane instead of clipping it to the video rectangle.
        if isRecovering { return CGSize(width: size.width, height: availableHeight) }
        let height = min(availableHeight, size.width * 9 / 16)
        return CGSize(width: min(size.width, height * 16 / 9), height: height)
    }
}

enum MultiLiveRecoveryAction: Equatable {
    case none, retry, chooseSource

    static func action(sourceCount: Int) -> Self {
        if sourceCount <= 0 { return .none }
        return sourceCount == 1 ? .retry : .chooseSource
    }
}

/// Resuming a suspended first start uses the pane's existing bindings. There is
/// no second playback store: rejected preparation cannot publish playing state,
/// and accepted resume clears the spinner abandoned by the suspended load task.
@MainActor
enum MultiLiveNativeAudioResume {
    static func resume(using preparation: @MainActor () async -> MediaAudioSessionPreparation,
                       expected: MediaAudioPlaybackIdentity,
                       currentIdentity: () -> MediaAudioPlaybackIdentity,
                       playbackMayStart: () -> Bool,
                       player: AVPlayer,
                       isLoading: Binding<Bool>, isPlaying: Binding<Bool>,
                       updateAudio: () -> Void) async -> Bool {
        guard expected.playerID == ObjectIdentifier(player),
              await MediaAudioPlaybackGate.prepareNative(using: preparation, expected: expected,
                  currentIdentity: currentIdentity, playbackMayStart: playbackMayStart) else { return false }
        updateAudio()
        player.play()
        isLoading.wrappedValue = false
        isPlaying.wrappedValue = true
        return true
    }
}

/// Owns only a bounded delayed retry, not playback state. The panel supplies its
/// current context so a cancelled timer cannot reload a recovered/new attempt.
@MainActor
final class MultiLiveWebRetryOwner {
    struct Context {
        let sourceID: UUID?
        let attemptID: UUID
        let isActive: Bool
        let playbackMayStart: Bool
        let isRecovering: Bool
    }

    private(set) var task: Task<Void, Never>?
    private var token: UUID?
    var isPending: Bool { task != nil }

    @discardableResult
    func schedule(
        sourceID: UUID,
        attemptID: UUID,
        delay: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(500))
        },
        currentContext: @escaping @MainActor () -> Context,
        onRetry: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        cancel()
        let expectedToken = UUID()
        token = expectedToken
        let scheduled = Task { @MainActor [weak self] in
            defer {
                if self?.token == expectedToken {
                    self?.task = nil
                    self?.token = nil
                }
            }
            do { try await delay() } catch { return }
            guard let self, !Task.isCancelled, self.token == expectedToken else { return }
            let context = currentContext()
            guard context.sourceID == sourceID, context.attemptID == attemptID,
                  context.isActive, context.playbackMayStart, context.isRecovering else { return }
            // Release ownership before loading, which cancels the old timer.
            self.task = nil
            self.token = nil
            onRetry()
        }
        task = scheduled
        return scheduled
    }

    func cancel() {
        token = nil
        task?.cancel()
        task = nil
    }
}

enum MultiLiveGoalAudioPolicy {
    static func shouldFocus(
        slotID: String, currentAudioSlotID: String?, viableSlotIDs: Set<String>,
        scoreIncreased: Bool
    ) -> Bool {
        scoreIncreased && slotID != currentAudioSlotID && viableSlotIDs.contains(slotID)
    }
}

enum MultiLiveAudioControlPolicy {
    static func canRequestAudio(slotID: String, viableSlotIDs: Set<String>) -> Bool {
        viableSlotIDs.contains(slotID)
    }
}

/// Audio focus is a per-slot user preference, not permission to emit sound in
/// an explicitly muted diagnostic run. Native and WebKit use the same result.
enum MultiLiveAudioOutputPolicy {
    static func isMuted(isAudioActive: Bool, shouldMuteForTesting: Bool) -> Bool {
        shouldMuteForTesting || !isAudioActive
    }

    @MainActor
    static func apply(to player: AVPlayer?, isAudioActive: Bool, shouldMuteForTesting: Bool) {
        let muted = isMuted(isAudioActive: isAudioActive, shouldMuteForTesting: shouldMuteForTesting)
        player?.isMuted = muted
        player?.volume = muted ? 0 : 1
    }
}

/// A notification/KVO callback belongs to the native item it observed, not just
/// a reused source label. Replacement and teardown revoke that ownership.
enum MultiLiveNativeFailurePolicy {
    static func readinessFailureReason(status: AVPlayerItem.Status,
                                       snapshot: PlayerDiagnosticService.DiagnosticSnapshot) -> String {
        status == .failed ? snapshot.failureReason : "Native readiness timeout."
    }

    static func ownsFailure(sourceID: UUID, currentSourceID: UUID?, requestID: UUID,
                            currentRequestID: UUID, item: AVPlayerItem,
                            currentItem: AVPlayerItem?) -> Bool {
        sourceID == currentSourceID && requestID == currentRequestID && item === currentItem
    }
}

private enum MultiViewLayoutMode: String {
    case focus
    case equal

    mutating func toggle() {
        self = self == .focus ? .equal : .focus
    }
}

struct MultiLivePlayerView: View {
    let slots: [MultiLiveSlot]
    var onPlaybackUnavailable: (String) -> Void = { _ in }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeAudioSlotID: String?
    @State private var isFillMode = false
    @State private var layoutMode: MultiViewLayoutMode = .focus
    @State private var focusedSlotID: String?
    @State private var audioSessionKeepAliveTask: Task<Void, Never>?
    @State private var scorePollingOwner = UUID()
    
    @State private var orderedSlots: [MultiLiveSlot] = []
    @State private var isAutoAudioFocusEnabled = true
    @State private var autoFocusGlowSlotID: String? = nil
    @State private var lastKnownScores: [String: (home: Int, away: Int)] = [:]
    @State private var viableSlotIDs: Set<String> = []
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                let canFocus = MultiLiveLayoutPolicy.canFocus(in: geo.size)
                let usesFocusLayout = canFocus && layoutMode == .focus

                VStack(spacing: 0) {
                    multiViewToolbar(canFocus: canFocus)

                    Rectangle()
                        .fill(FottyTheme.borderStrong)
                        .frame(height: 1)

                    if orderedSlots.count == 2 {
                        let adaptiveLayout: AnyLayout = isLandscape
                            ? AnyLayout(HStackLayout(spacing: 8))
                            : AnyLayout(VStackLayout(spacing: 8))

                        adaptiveLayout {
                            ForEach(orderedSlots) { slot in
                                panel(for: slot, canFocus: canFocus, usesFocusLayout: usesFocusLayout)
                                    .frame(
                                        width: isLandscape
                                            ? panelWidth(
                                                for: slot,
                                                totalWidth: geo.size.width,
                                                usesFocusLayout: usesFocusLayout
                                            )
                                            : nil
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            SportLoadingView(category: HomeSportsDiscovery.allSports, size: 36,
                                             label: "Preparing two-match view…")
                                .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .fottyLeadingEdgeSwipeDismissesPlayer(onDismiss: { dismiss() })
        .onChange(of: liveScoreService.scores) { _, _ in
            checkForGoalAutoFocus()
        }
        .task(id: scenePhase == .active) {
            liveScoreService.updatePollingDemand(
                owner: scorePollingOwner,
                isActive: scenePhase == .active && slots.contains {
                    $0.event.normalizedCategory == "football"
                }
            )
        }
        .onAppear {
            orderedSlots = Array(slots.prefix(2))
            viableSlotIDs = Set(orderedSlots.map(\.id))
            focusedSlotID = orderedSlots.first?.id
            updateLastKnownScores()
            MediaAudioSession.configureForPlaybackIfNeeded()
            startAudioSessionKeepAlive()
            activeAudioSlotID = orderedSlots.first?.id
            PlayerOrientationController.enterLandscape()
        }
        .onDisappear {
            liveScoreService.releasePolling(owner: scorePollingOwner)
            audioSessionKeepAliveTask?.cancel()
            PlayerOrientationController.exitToPortrait()
            ActiveWebViewManager.clear()
        }
    }

    private func panel(for slot: MultiLiveSlot, canFocus: Bool, usesFocusLayout: Bool) -> some View {
        let isGlowActive = autoFocusGlowSlotID == slot.id
        let teamColor = TeamColorResolver.resolve(teamName: slot.event.homeName) ?? FottyTheme.accent
        
        return MultiLivePanelView(
            slot: slot,
            panelNumber: (orderedSlots.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1,
            isAudioActive: Binding(get: { activeAudioSlotID == slot.id }, set: { _ in }),
            isAudioAvailable: MultiLiveAudioControlPolicy.canRequestAudio(
                slotID: slot.id, viableSlotIDs: viableSlotIDs
            ),
            isFocused: usesFocusLayout && focusedSlotID == slot.id,
            canFocus: canFocus,
            isFillMode: isFillMode,
            onRequestFocus: {
                let update = {
                    focusedSlotID = slot.id
                    layoutMode = .focus
                }
                if reduceMotion {
                    update()
                } else {
                    withAnimation(.snappy(duration: 0.28)) { update() }
                }
            },
            onRequestAudio: {
                if MultiLiveAudioControlPolicy.canRequestAudio(slotID: slot.id, viableSlotIDs: viableSlotIDs) {
                    activeAudioSlotID = slot.id
                }
            },
            onPlaybackAvailable: {
                viableSlotIDs.insert(slot.id)
            },
            onPlaybackUnavailable: {
                viableSlotIDs.remove(slot.id)
                if activeAudioSlotID == slot.id {
                    activeAudioSlotID = orderedSlots.first(where: {
                        $0.id != slot.id && viableSlotIDs.contains($0.id)
                    })?.id
                }
                onPlaybackUnavailable(slot.id)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(teamColor, lineWidth: isGlowActive ? 6 : 0)
                .shadow(color: teamColor.opacity(0.8), radius: isGlowActive ? 15 : 0)
        )
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: isGlowActive)
    }

    private func multiViewToolbar(canFocus: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.fottyScaled(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(FottyTheme.surfaceElevated))
            }
            .accessibilityLabel("Close two-match view")
            .accessibilityIdentifier("multiview-close")

            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch two")
                        .font(.headline)
                    Text("Choose Source and Audio separately for each match")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FottyTheme.textSecondary)
                }

                Text("Watch two")
                    .font(.headline)
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            if orderedSlots.count == 2 && canFocus {
                Button {
                    let update = { layoutMode.toggle() }
                    if reduceMotion {
                        update()
                    } else {
                        withAnimation(.snappy(duration: 0.28)) { update() }
                    }
                } label: {
                    toolbarLabel(
                        title: layoutMode == .focus ? "Focus" : "Equal",
                        systemImage: layoutMode == .focus ? "rectangle.lefthalf.inset.filled" : "rectangle.split.2x1"
                    )
                }
                .accessibilityLabel("Two-match layout")
                .accessibilityValue(layoutMode == .focus ? "Focus" : "Equal")
                .accessibilityHint("Switches between one large match and two equal matches")
                .accessibilityIdentifier("multiview-layout")
            }

            if supportsFillMode {
                Button {
                    isFillMode.toggle()
                } label: {
                    toolbarLabel(
                        title: isFillMode ? "Fill" : "Fit",
                        systemImage: isFillMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
                    )
                }
                .accessibilityLabel("Video sizing: \(isFillMode ? "Fill" : "Fit")")
                .accessibilityValue(isFillMode ? "Fill" : "Fit")
                .accessibilityHint("Switches how video fits each panel")
                .accessibilityIdentifier("multiview-fill-mode")
            }

            if orderedSlots.count == 2 {
                Button {
                    swapSlots()
                } label: {
                    toolbarLabel(title: "Swap", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityLabel("Swap match positions")
                .accessibilityIdentifier("multiview-swap")
            }

            if supportsAutomaticGoalAudio {
                Button {
                    isAutoAudioFocusEnabled.toggle()
                } label: {
                    toolbarLabel(
                        title: "Goal audio",
                        systemImage: isAutoAudioFocusEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        isActive: isAutoAudioFocusEnabled
                    )
                }
                .accessibilityLabel("Automatic goal audio")
                .accessibilityValue(isAutoAudioFocusEnabled ? "On" : "Off")
                .accessibilityHint("Moves audio to a football match when its score changes")
            }
        }
        .foregroundStyle(FottyTheme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(FottyTheme.surface)
    }

    @ViewBuilder
    private func toolbarLabel(title: String, systemImage: String, isActive: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(minHeight: 44)

            Image(systemName: systemImage)
                .font(.fottyScaled(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(isActive ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? FottyTheme.accent : FottyTheme.surfaceElevated)
        )
    }

    private var supportsFillMode: Bool {
        orderedSlots.contains { !$0.sources.isEmpty }
    }

    private var supportsAutomaticGoalAudio: Bool {
        orderedSlots.count == 2 && orderedSlots.allSatisfy { $0.event.normalizedCategory == "football" }
    }
    
    private func startAudioSessionKeepAlive() {
        audioSessionKeepAliveTask?.cancel()
        audioSessionKeepAliveTask = Task {
            while !Task.isCancelled {
                _ = await MediaAudioSession.configureForPlayback()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func panelWidth(
        for slot: MultiLiveSlot,
        totalWidth: CGFloat,
        usesFocusLayout: Bool
    ) -> CGFloat {
        let availableWidth = max(0, totalWidth - 8)
        guard usesFocusLayout else { return availableWidth / 2 }

        let secondaryWidth = min(380, max(320, availableWidth * 0.30))
        return slot.id == focusedSlotID
            ? availableWidth - secondaryWidth
            : secondaryWidth
    }
    
    private func swapSlots() {
        guard orderedSlots.count == 2 else { return }
        let update = { orderedSlots.swapAt(0, 1) }
        if reduceMotion { update() }
        else { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { update() } }
    }
    
    private func updateLastKnownScores() {
        for slot in orderedSlots {
            if let score = liveScoreService.scoreForMatch(home: slot.event.homeName, away: slot.event.awayName) {
                lastKnownScores[slot.id] = (score.homeGoals, score.awayGoals)
            }
        }
    }
    
    private func checkForGoalAutoFocus() {
        guard isAutoAudioFocusEnabled else { return }
        
        for slot in orderedSlots {
            guard let score = liveScoreService.scoreForMatch(home: slot.event.homeName, away: slot.event.awayName) else { continue }
            let newHome = score.homeGoals
            let newAway = score.awayGoals
            guard let last = lastKnownScores[slot.id] else {
                lastKnownScores[slot.id] = (newHome, newAway)
                continue
            }
            
            if MultiLiveGoalAudioPolicy.shouldFocus(
                slotID: slot.id, currentAudioSlotID: activeAudioSlotID,
                viableSlotIDs: viableSlotIDs,
                scoreIncreased: newHome > last.home || newAway > last.away
            ) {
                let focusUpdate = {
                    activeAudioSlotID = slot.id
                    autoFocusGlowSlotID = slot.id
                }
                if reduceMotion { focusUpdate() }
                else { withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { focusUpdate() } }

                Task {
                    try? await Task.sleep(for: .seconds(5))
                    if autoFocusGlowSlotID == slot.id {
                        if reduceMotion { autoFocusGlowSlotID = nil }
                        else { withAnimation(.easeOut(duration: 0.5)) { autoFocusGlowSlotID = nil } }
                    }
                }
            }
            lastKnownScores[slot.id] = (newHome, newAway)
        }
    }
}

private struct MultiLivePanelView: View {
    let slot: MultiLiveSlot
    let panelNumber: Int
    @Binding var isAudioActive: Bool
    let isAudioAvailable: Bool
    let isFocused: Bool
    let canFocus: Bool
    let isFillMode: Bool
    let onRequestFocus: () -> Void
    let onRequestAudio: () -> Void
    let onPlaybackAvailable: () -> Void
    let onPlaybackUnavailable: () -> Void
    
    @AppStorage("fotty.livePlayer.showAdvancedControls") private var showAdvancedControls = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var scaledControlHeight: CGFloat = 44
    @State private var player: AVPlayer?
    @State private var currentSourceIndex = 0
    @State private var isLoading = true
    @State private var isPlaying = true
    @State private var errorTitle = "Playback Error"
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var stallValidationTask: Task<Void, Never>?
    @State private var foregroundResumeValidationTask: Task<Void, Never>?
    @State private var audioPreparationTask: Task<Void, Never>?
    @State private var audioIntentID = UUID()
    @State private var loadRequestID = UUID()
    @State private var playbackCorrelation = FottyPlaybackCorrelation()
    @State private var lastObservedPlaybackStage = FottyPlaybackStage.preparing
    @State private var playbackIntervals = FottyPlaybackIntervals()
    @State private var streamProxy: LocalStreamProxy?
    @State private var networkPathMonitor: NWPathMonitor?
    @State private var isNetworkReachable = true
    @State private var pendingRetryAfterNetworkRestore = false
    @State private var playerItemNotificationTokens: [NSObjectProtocol] = []
    @State private var playerItemStatusObservation: NSKeyValueObservation?
    @State private var playbackWatchdogTask: Task<Void, Never>?
    @State private var failedSourceIDs: Set<UUID> = []
    @State private var sourceAttemptStartedAt: Date?
    @State private var isVideoReadyForDisplay = false
    @State private var lastObservedPlaybackSecond: Double?
    @State private var playbackStagnationTicks = 0
    @State private var shouldResumeAfterForeground = false
    @State private var userWantsPlayback = true
    @State private var isPlaybackSessionActive = false
    @State private var webRetryOwner = MultiLiveWebRetryOwner()
    @State private var webPlaybackCommand: WebPlaybackCommand?
    @State private var webStartupRetryAttemptsBySource: [UUID: Int] = [:]
    @State private var webStallRetryAttemptsBySource: [UUID: Int] = [:]
    @State private var nativeStartupRetryAttemptsBySource: [UUID: Int] = [:]
    
    private let diagnosticService = PlayerDiagnosticService()
    private let validator = StreamContractValidator()
    
    private var event: AnalyticalDataEngine.EventReference {
        slot.event
    }
    @State private var lastFailureKind: LivePlaybackFailureKind = .unknown
    
    var body: some View {
        GeometryReader { geometry in
            let chromeLayout = MultiLivePanelChromeLayout.layout(
                width: geometry.size.width,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
            let surfaceSize = MultiLiveLayoutPolicy.surfaceSize(
                in: geometry.size,
                chromeHeight: chromeLayout.reservedHeight(controlHeight: minimumControlHeight),
                isRecovering: error != nil
            )

            VStack(spacing: 0) {
                panelHeader(layout: chromeLayout)

                Rectangle()
                    .fill(FottyTheme.borderStrong)
                    .frame(height: 1)

                playerSurface
                    .frame(width: surfaceSize.width, height: surfaceSize.height)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("multiview-video-surface-\(panelNumber)")
            }
            .frame(width: geometry.size.width)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isFocused ? FottyTheme.accent : FottyTheme.borderStrong, lineWidth: isFocused ? 2 : 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(Color.black)
        .onAppear {
            isPlaybackSessionActive = true
            userWantsPlayback = true
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
        .onDisappear {
            cancelAudioPreparation()
            finishObservedStall(.interrupted)
            if isPlaybackSessionActive, let source = activeSource {
                FottyQualityStore.shared.record(category: .playback, name: "session_closed",
                                               outcome: .info,
                                               details: playbackQualityDetails(source: source))
            }
            playbackCorrelation = FottyPlaybackCorrelation()
            isPlaybackSessionActive = false
            webRetryOwner.cancel()
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

    @ViewBuilder
    private var playerSurface: some View {
        ZStack {
            Color.black

            if let source = activeSource, isWebEmbedSource(source) {
                let attemptID = loadRequestID
                LiveWebEmbedPlayerView(
                    url: source.url,
                    referer: source.headers["Referer"] ?? source.url.absoluteString,
                    isMuted: MultiLiveAudioOutputPolicy.isMuted(
                        isAudioActive: isAudioActive,
                        shouldMuteForTesting: AppRuntime.shouldMutePlaybackForTesting
                    ),
                    isSuspended: MultiLiveScenePolicy.shouldSuspendWebPlayback(
                        scenePhase, isNetworkReachable: isNetworkReachable
                    ),
                    isFillMode: isFillMode,
                    attemptID: attemptID,
                    playbackCommand: webPlaybackCommand,
                    onDiagnosticStage: { stage, code in
                        guard isPlaybackSessionActive, loadRequestID == attemptID,
                              activeSource?.id == source.id else { return }
                        lastObservedPlaybackStage = stage
                        ensurePlaybackIntervalAttempt()
                        if let identity = intervalIdentity {
                            if stage == .buffering { playbackIntervals.beginStall(identity, now: ProcessInfo.processInfo.systemUptime) }
                            if stage == .decoded { playbackIntervals.decodedProgress(identity, now: ProcessInfo.processInfo.systemUptime)?.record() }
                        }
                        var details = ["stage": stage.rawValue]
                        if let code { details["platform_error_code"] = String(code) }
                        FottyQualityStore.shared.record(category: .playback, name: "playback_stage",
                                                       outcome: .info,
                                                       details: playbackQualityDetails(source: source, additional: details))
                    },
                    onAudioPreparationMeasured: { milliseconds, result in
                        guard isPlaybackSessionActive, loadRequestID == attemptID,
                              activeSource?.id == source.id else { return }
                        ensurePlaybackIntervalAttempt()
                        if let identity = intervalIdentity {
                            playbackIntervals.audioPreparation(identity, durationMilliseconds: milliseconds, result: result)?.record()
                        }
                    },
                    onTransportStateChanged: { state in
                        guard isPlaybackSessionActive, loadRequestID == attemptID,
                              activeSource?.id == source.id,
                              MultiLiveScenePolicy.isForeground(scenePhase), isNetworkReachable else { return }
                        if state == .paused { webRetryOwner.cancel(); finishObservedStall(.interrupted) }
                        userWantsPlayback = state == .playing
                        isPlaying = state == .playing
                    },
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
                        guard playbackMayStart else { return }
                        webRetryOwner.cancel()
                        isLoading = false
                        isPlaying = true
                        lastObservedPlaybackStage = .decoded
                        markObservedDecodedProgress()
                        error = nil
                        onPlaybackAvailable()
                        FottyQualityStore.shared.record(
                            category: .playback,
                            name: "in_place_recovery",
                            outcome: .recovered,
                            details: playbackQualityDetails(
                                source: source,
                                additional: ["recovery_kind": "decoded_web_progress"]
                            )
                        )
                    }
                )
                // Keep each panel stable through layout/audio changes, but
                // retire its WebKit document on a new source/retry attempt.
                .id(attemptID)
            } else if let player {
                AVPlayerLayerView(
                    player: player,
                    videoGravity: isFillMode ? .resizeAspectFill : .resizeAspect,
                    physicalMeasurementIdentifier: "native-measurement-pane-\(panelNumber)",
                    physicalMeasurementAttemptID: loadRequestID,
                    physicalMeasurementPane: panelNumber,
                    onReadyForDisplayChanged: { ready in
                        if isVideoReadyForDisplay != ready {
                            isVideoReadyForDisplay = ready
                        }
                    }
                )
            }

            if isLoading {
                SportLoadingView(category: slot.event.normalizedCategory, size: 22, label: "",
                                 competition: SportMotionContext.competition(for: slot.event))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading \(slot.event.displayTitle)")
            }

            if let error {
                playbackErrorSurface(error)
            }
        }
        .clipped()
    }

    private var minimumControlHeight: CGFloat { max(44, scaledControlHeight) }

    private func panelHeader(layout: MultiLivePanelChromeLayout) -> some View {
        Group {
            switch layout {
            case .inline:
                HStack(spacing: 8) {
                    panelIdentity
                    Spacer(minLength: 0)
                    transportButton
                    sourceMenu
                    audioButton
                }
            case .stacked:
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        panelIdentity
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        transportButton
                        sourceMenu
                        Spacer(minLength: 0)
                        audioButton
                    }
                }
            case .accessibility:
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        panelIdentity
                        Spacer(minLength: 0)
                    }
                    HStack {
                        sourceMenu
                        Spacer(minLength: 0)
                    }
                    HStack {
                        transportButton
                        Spacer(minLength: 0)
                        audioButton
                    }
                }
            }
        }
        .foregroundStyle(FottyTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: layout.reservedHeight(controlHeight: minimumControlHeight) - 1)
        .background(FottyTheme.surfaceSubtle)
    }

    private var panelIdentity: some View {
        Group {
            if canFocus {
                Button(action: onRequestFocus) {
                    panelNumberBadge
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFocused ? "Panel \(panelNumber), large view" : "Make panel \(panelNumber) large")
                .accessibilityValue(isFocused ? "Focused" : "Not focused")
                .accessibilityIdentifier("multiview-panel-\(panelNumber)")
            } else {
                panelNumberBadge
                    .accessibilityLabel("Panel \(panelNumber)")
                    .accessibilityIdentifier("multiview-panel-\(panelNumber)")
            }

            ViewThatFits(in: .horizontal) {
                matchIdentity(usesShortNames: false)
                matchIdentity(usesShortNames: true)
                Text("Match \(panelNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Panel \(panelNumber), \(slot.event.homeName) versus \(slot.event.awayName)")
        }
    }

    private var panelNumberBadge: some View {
        Text("\(panelNumber)")
            .font(.fottyScaled(size: 13, weight: .bold))
            .foregroundStyle(isFocused ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
            .frame(width: minimumControlHeight, height: minimumControlHeight)
            .background(Circle().fill(isFocused ? FottyTheme.accent : FottyTheme.surfaceElevated))
    }

    private var transportButton: some View {
        Button {
            togglePlayPause()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.fottyScaled(size: 14, weight: .bold))
                .frame(minWidth: 44, minHeight: minimumControlHeight)
                .background(controlBackground(isActive: false))
        }
        .accessibilityLabel(isPlaying ? "Pause panel \(panelNumber)" : "Play panel \(panelNumber)")
    }

    @ViewBuilder
    private var sourceMenu: some View {
        if !slot.sources.isEmpty {
            Menu {
                ForEach(Array(slot.sources.enumerated()), id: \.offset) { index, source in
                    Button {
                        userWantsPlayback = true
                        currentSourceIndex = index
                        failedSourceIDs.removeAll()
                        resetRetryBudget(for: source)
                        loadCurrentSource(ignoringCircuitBreaker: true)
                    } label: {
                        HStack {
                            Text(sourceMenuTitle(index: index, source: source))
                            if index == currentSourceIndex {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Source \(currentSourceIndex + 1)")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.fottyScaled(size: 9, weight: .bold))
                }
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(FottyTheme.textOnAccent)
                .padding(.horizontal, 10)
                .frame(minHeight: minimumControlHeight)
                .background(controlBackground(isActive: true))
            }
            .accessibilityLabel("Choose source for panel \(panelNumber)")
            .accessibilityValue("Source \(currentSourceIndex + 1)")
            .accessibilityHint("Changes only the stream in panel \(panelNumber)")
            .accessibilityIdentifier("multiview-source-\(panelNumber)")
        }
    }

    private var audioButton: some View {
        Button {
            onRequestAudio()
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(audioControlTitle, systemImage: isAudioActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(minHeight: minimumControlHeight)

                Image(systemName: isAudioActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.fottyScaled(size: 14, weight: .semibold))
                    .frame(minWidth: 44, minHeight: minimumControlHeight)
            }
            .foregroundStyle(isAudioActive ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
            .background(controlBackground(isActive: isAudioActive))
        }
        .disabled(!isAudioAvailable)
        .accessibilityLabel(isAudioAvailable
            ? (isAudioActive ? "Audio playing from panel \(panelNumber)" : "Listen to panel \(panelNumber)")
            : (isLoading ? "Audio pending for panel \(panelNumber)" : "Audio unavailable for panel \(panelNumber)"))
        .accessibilityHint(isAudioAvailable
            ? (isAudioActive ? "This panel currently owns audio" : "Switches audio to this panel")
            : "Available when this panel has a working source")
        .accessibilityIdentifier("multiview-audio-\(panelNumber)")
    }

    private var audioControlTitle: String {
        guard isAudioAvailable else { return isLoading ? "Loading" : "Unavailable" }
        return isAudioActive ? "Audio" : "Muted"
    }

    private func controlBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(isActive ? FottyTheme.accent : FottyTheme.surfaceElevated)
    }

    private func playbackErrorSurface(_ message: String) -> some View {
        ZStack {
            // A failed provider page is untrusted content. Replace the entire
            // panel instead of leaving ads or fake prompts visible behind it.
            Color.black
                .allowsHitTesting(true)

            ScrollView {
                VStack(spacing: 8) {
                    Text(errorTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)

                    if MultiLiveRecoveryAction.action(sourceCount: slot.sources.count) == .retry,
                       let source = slot.sources.first {
                        Button {
                            userWantsPlayback = true
                            currentSourceIndex = 0
                            failedSourceIDs.removeAll()
                            resetRetryBudget(for: source)
                            loadCurrentSource(ignoringCircuitBreaker: true)
                        } label: {
                            recoveryActionLabel("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry panel \(panelNumber)")
                        .accessibilityIdentifier("multiview-retry-\(panelNumber)")
                    } else if MultiLiveRecoveryAction.action(sourceCount: slot.sources.count) == .chooseSource {
                        Menu {
                            ForEach(Array(slot.sources.enumerated()), id: \.offset) { index, source in
                                Button {
                                    userWantsPlayback = true
                                    currentSourceIndex = index
                                    failedSourceIDs.removeAll()
                                    resetRetryBudget(for: source)
                                    loadCurrentSource(ignoringCircuitBreaker: true)
                                } label: {
                                    HStack {
                                        Text(sourceMenuTitle(index: index, source: source))
                                        if index == currentSourceIndex {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                    }
                                }
                            }
                        } label: {
                            recoveryActionLabel("Change Source", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .accessibilityLabel("Change source for panel \(panelNumber)")
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FottyTheme.surface)
                )
                .padding(12)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .accessibilityIdentifier("multiview-recovery-\(panelNumber)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recoveryActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(FottyTheme.textOnAccent)
            .padding(.horizontal, 10)
            .frame(minHeight: minimumControlHeight)
            .background(Capsule().fill(FottyTheme.accent))
    }
    
    private var activeSource: StreamSource? {
        guard slot.sources.indices.contains(currentSourceIndex) else { return nil }
        return slot.sources[currentSourceIndex]
    }
    
    private func sourceMenuTitle(index: Int, source: StreamSource) -> String {
        let publicLabel = "Source \(index + 1)"
        guard showAdvancedControls else { return publicLabel }
        return "\(publicLabel) · \(source.provider)"
    }

    private func matchIdentity(usesShortNames: Bool) -> some View {
        HStack(spacing: 5) {
            TeamBadgeWindow(
                teamName: slot.event.homeName,
                badgeURL: slot.event.homeBadgeURL,
                size: 20
            )
            Text(usesShortNames ? shortCode(for: slot.event.homeName) : slot.event.homeName)
                .lineLimit(1)
            Text("v")
                .foregroundStyle(.white.opacity(0.75))
            Text(usesShortNames ? shortCode(for: slot.event.awayName) : slot.event.awayName)
                .lineLimit(1)
            TeamBadgeWindow(
                teamName: slot.event.awayName,
                badgeURL: slot.event.awayBadgeURL,
                size: 20
            )
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func shortCode(for team: String) -> String {
        let words = team.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first else { return "TEAM" }
        if words.count == 1 { return String(first.prefix(4)).uppercased() }
        return String(words.prefix(3).compactMap(\.first)).uppercased()
    }

    private var playbackMayStart: Bool {
        isPlaybackSessionActive && userWantsPlayback
            && MultiLiveScenePolicy.isForeground(scenePhase) && isNetworkReachable
    }

    private func resetRetryBudget(for source: StreamSource) {
        webStartupRetryAttemptsBySource[source.id] = 0
        webStallRetryAttemptsBySource[source.id] = 0
        nativeStartupRetryAttemptsBySource[source.id] = 0
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
            webRetryOwner.cancel()
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
        guard playbackMayStart else {
            isLoading = false
            isPlaying = false
            return
        }

        error = nil
        if isWebEmbedSource(source) {
            isPlaying = true
            isLoading = !isVideoReadyForDisplay
            webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: true)
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

        let requestID = loadRequestID
        isLoading = false
        queueAudioPreparation(for: player) {
            startPlaybackWatchdog(for: source)
            scheduleNativeResumeValidation(for: source, player: player, item: item,
                                           requestID: requestID, delaySeconds: 8,
                                           reason: "Network recovery stalled.")
        }
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            handleAppDidBecomeActive()
        case .inactive:
            // Transient overlays do not suspend either pane or replace its
            // attempt. Background remains the deliberate suspension boundary.
            break
        case .background:
            handleAppDidMoveToBackground()
        @unknown default:
            break
        }
    }
    
    private func handleAppDidMoveToBackground() {
        finishObservedStall(.interrupted)
        cancelAudioPreparation()
        webRetryOwner.cancel()
        foregroundResumeValidationTask?.cancel()
        shouldResumeAfterForeground = userWantsPlayback && isPlaying
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
        
        let needsResume = shouldResumeAfterForeground || (userWantsPlayback && !isPlaying)
        guard needsResume, userWantsPlayback, isNetworkReachable else { return }
        shouldResumeAfterForeground = false
        
        guard let source = activeSource else {
            loadCurrentSource()
            return
        }
        if isWebEmbedSource(source) {
            isPlaying = true
            isLoading = !isVideoReadyForDisplay
            webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: true)
            updateAudioState()
            return
        }
        
        guard let player, let item = player.currentItem else {
            loadCurrentSource()
            return
        }
        
        let requestID = loadRequestID
        if item.status == .failed {
            handleSourceFailure(source, reason: "Playback failed after returning to app.")
            return
        }
        queueAudioPreparation(for: player) {
            startPlaybackWatchdog(for: source)
            scheduleNativeResumeValidation(for: source, player: player, item: item,
                                           requestID: requestID, delaySeconds: 3,
                                           reason: "Resume stalled after returning to app.")
        }
        
        // We do NOT add new observers here to avoid duplicates.
        // Observers are configured in loadCurrentSource() via configureItemFailureObservers().
    }

    private func scheduleNativeResumeValidation(for source: StreamSource, player: AVPlayer,
                                                item: AVPlayerItem, requestID: UUID,
                                                delaySeconds: Double, reason: String) {
        let startSeconds = player.currentTime().seconds
        foregroundResumeValidationTask?.cancel()
        foregroundResumeValidationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            guard activeSource?.id == source.id,
                  loadRequestID == requestID,
                  self.player === player,
                  self.player?.currentItem === item else { return }
            guard !isLoading, isPlaying else { return }
            
            let currentSeconds = self.player?.currentTime().seconds ?? startSeconds
            let noProgress = startSeconds.isFinite
                && currentSeconds.isFinite
                && abs(currentSeconds - startSeconds) < 0.1
            
            if noProgress, self.player?.timeControlStatus != .paused {
                validateRecoverablePanelStall(
                    for: source,
                    reason: reason,
                    expectedItem: item,
                    requestID: requestID
                )
            }
        }
    }
    
    private func togglePlayPause() {
        if isPlaying || (audioPreparationTask != nil && userWantsPlayback) {
            finishObservedStall(.interrupted)
            cancelAudioPreparation()
            userWantsPlayback = false
            webRetryOwner.cancel()
            stallValidationTask?.cancel()
            foregroundResumeValidationTask?.cancel()
            if let source = activeSource, isWebEmbedSource(source) {
                webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: false)
            } else {
                player?.pause()
            }
            stopPlaybackWatchdog()
            isPlaying = false
            isLoading = false
        } else {
            userWantsPlayback = true
            guard MultiLiveScenePolicy.isForeground(scenePhase), isNetworkReachable else { return }
            if let source = activeSource, isWebEmbedSource(source) {
                MediaAudioSession.configureForPlaybackIfNeeded()
                webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: true)
                isPlaying = true
            } else {
                queueAudioPreparation(for: player) {
                    if let source = activeSource { startPlaybackWatchdog(for: source) }
                }
            }
        }
    }
    
    private var audioPlaybackIdentity: MediaAudioPlaybackIdentity {
        .init(requestID: loadRequestID, sourceID: activeSource?.id, intentID: audioIntentID,
              player: player, item: player?.currentItem)
    }

    private func cancelAudioPreparation() {
        audioPreparationTask?.cancel()
        audioPreparationTask = nil
        audioIntentID = UUID()
    }

    private func queueAudioPreparation(for expectedPlayer: AVPlayer?,
                                       completion: @escaping @MainActor () -> Void) {
        guard let expectedPlayer, self.player === expectedPlayer else { return }
        cancelAudioPreparation()
        let identity = audioPlaybackIdentity
        audioPreparationTask = Task { @MainActor in
            defer { if audioIntentID == identity.intentID { audioPreparationTask = nil } }
            guard await MultiLiveNativeAudioResume.resume(using: {
                await measuredAudioPreparation()
            }, expected: identity, currentIdentity: { audioPlaybackIdentity },
               playbackMayStart: { playbackMayStart && error == nil }, player: expectedPlayer,
               isLoading: $isLoading, isPlaying: $isPlaying, updateAudio: { updateAudioState() }) else { return }
            completion()
        }
    }

    private func loadCurrentSource(ignoringCircuitBreaker: Bool = false) {
        cancelAudioPreparation()
        webRetryOwner.cancel()
        loadTask?.cancel()
        stallValidationTask?.cancel()
        foregroundResumeValidationTask?.cancel()
        let requestID = UUID()
        loadRequestID = requestID
        playbackCorrelation.beginAttempt(requestID)
        lastObservedPlaybackStage = .preparing
        guard let source = activeSource else {
            isLoading = false
            errorTitle = "No Sources Available"
            error = "No stream sources were returned for this event."
            onPlaybackUnavailable()
            return
        }
        ensurePlaybackIntervalAttempt()

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
                onPlaybackUnavailable()
            }
            return
        }
        isLoading = playbackMayStart
        isPlaying = playbackMayStart
        isVideoReadyForDisplay = false
        error = nil
        sourceAttemptStartedAt = Date()
        FottyQualityStore.shared.record(
            category: .playback,
            name: "attempt_started",
            outcome: .info,
            details: playbackQualityDetails(source: source)
        )
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
                isPlaying = playbackMayStart
                if playbackMayStart {
                    webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: true)
                } else {
                    shouldResumeAfterForeground = userWantsPlayback
                }
                updateAudioState()
                return
            }
            
            do {
                if player == nil {
                    player = AVPlayer()
                }
                guard let player else { return }
                player.automaticallyWaitsToMinimizeStalling = true

                let playbackURL = try await preparePlaybackURL(for: source, requestID: requestID)
                guard !Task.isCancelled, loadRequestID == requestID else { return }

                // --- AUDIT FIX [CONTRACT VALIDATION] ---
                let validation = await validator.validate(playbackURL, headers: source.headers)
                guard !Task.isCancelled, loadRequestID == requestID,
                      activeSource?.id == source.id else { return }
                if case .invalid(let reason, let diagnostic) = validation {
                    let details = (diagnostic ?? .init(stage: .contractValidation, reason: .unavailable)).qualityDetails
                    handleSourceFailure(
                        source,
                        reason: "Stream Contract Failed: \(reason)",
                        expectedRequestID: requestID,
                        diagnosticDetails: preparationDiagnosticDetails(details, source: source, requestID: requestID)
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
                item.preferredForwardBufferDuration = 2.0
                configureItemFailureObservers(for: item, source: source, requestID: requestID)
                player.replaceCurrentItem(with: item)
                updateAudioState()
                guard playbackMayStart else {
                    shouldResumeAfterForeground = userWantsPlayback
                    isLoading = false
                    isPlaying = false
                    return
                }
                let identity = audioPlaybackIdentity
                guard await MediaAudioPlaybackGate.prepareNative(using: {
                    await measuredAudioPreparation()
                }, expected: identity, currentIdentity: { audioPlaybackIdentity },
                   playbackMayStart: { playbackMayStart && error == nil }) else { return }
                player.play()
                let deadline = NativePlaybackStartupDeadline(startedAt: ProcessInfo.processInfo.systemUptime)
                isPlaying = true
                updateAudioState()
                let startup = await waitForInitialNativeStartup(player: player, item: item, source: source,
                    identity: identity, deadline: deadline)
                guard !Task.isCancelled, playbackMayStart, error == nil,
                      loadRequestID == requestID, activeSource?.id == source.id,
                      audioPlaybackIdentity == identity, self.player === player,
                      player.currentItem === item else { return }
                switch startup {
                case .started:
                    break
                case .failed:
                    handleNativeItemFailure(item, source: source, requestID: requestID, trigger: .itemStatusFailed)
                    return
                case .timedOut:
                    if item.status == .failed {
                        handleNativeItemFailure(item, source: source, requestID: requestID, trigger: .itemStatusFailed)
                        return
                    }
                    let waiting = nativeStartupTimeoutDetails(player: player, item: item, deadline: deadline)
                    if item.status != .readyToPlay {
                        let snapshot = diagnosticService.analyze(item, trigger: .readinessTimeout)
                        handleSourceFailure(source, reason: "Native readiness timeout.", expectedRequestID: requestID,
                            diagnosticDetails: nativeDiagnosticDetails(snapshot).merging(waiting) { _, value in value })
                    } else {
                        let details = PlaybackPreparationDiagnostic(stage: .playbackStart, reason: .playbackStartTimeout,
                                                                    error: item.error).qualityDetails
                            .merging(waiting) { _, value in value }
                        handleSourceFailure(source, reason: "Playback failed to start before timeout.",
                            expectedRequestID: requestID,
                            diagnosticDetails: preparationDiagnosticDetails(details, source: source, requestID: requestID))
                    }
                    return
                case .abandoned, .invalidTiming, .waiting:
                    // The old waiter cannot pause a replacement, override a
                    // manual Pause or turn lifecycle revocation into a failure.
                    return
                }

                stallValidationTask?.cancel()
                error = nil
                isLoading = false
                lastObservedPlaybackStage = .decoded
                markObservedDecodedProgress()
                let startupLatency = startupLatencyMs()
                LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: startupLatency)
                FottyQualityStore.shared.record(
                    category: .playback,
                    name: "decoded_progress",
                    outcome: .success,
                    durationMilliseconds: startupLatency,
                    details: playbackQualityDetails(source: source)
                )
                onPlaybackAvailable()
                startPlaybackWatchdog(for: source)
            } catch {
                guard !Task.isCancelled, loadRequestID == requestID else { return }
                let preparedFailure = error as? PlaybackPreparationFailure
                let details = preparedFailure?.qualityDetails ?? PlaybackPreparationDiagnostic(
                    stage: .urlPreparation, reason: error is CancellationError ? .cancelled : .transportError,
                    error: error is CancellationError ? nil : error).qualityDetails
                handleSourceFailure(
                    source,
                    reason: (preparedFailure?.underlyingError ?? error).localizedDescription,
                    expectedRequestID: requestID,
                    diagnosticDetails: preparationDiagnosticDetails(details, source: source, requestID: requestID)
                )
            }
        }
    }

    private func preparePlaybackURL(for source: StreamSource, requestID: UUID) async throws -> URL {
        streamProxy?.stop()
        streamProxy = nil

        let remoteURL = source.url
        guard source.requiresLocalProxy else {
            return remoteURL
        }

        let cookies = HTTPCookieStorage.shared.cookies(for: remoteURL) ?? []
        let proxy = LocalStreamProxy(headers: source.headers, cookies: cookies, selectedMediaURL: remoteURL,
                                     originProfile: source.nativeOriginProfile,
                                     playlistProfile: source.nativePlaylistProfile)
        do {
            try await proxy.start()
        } catch {
            throw PlaybackPreparationFailure(error, reason: error is CancellationError ? .cancelled : .proxyStartup,
                                             relayEvidence: proxy.lastFailureEvidence)
        }
        
        // Wait for proxy health check
        var proxyReady = false
        for _ in 0..<5 {
            if await proxy.ping() { proxyReady = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        guard !Task.isCancelled, requestID == loadRequestID else {
            proxy.stop()
            throw CancellationError()
        }
        guard proxyReady, let localURL = proxy.playbackURL() else {
            proxy.stop()
            throw PlaybackPreparationFailure(ProcessorError.proxyError, reason: .proxyHealthCheck,
                                             relayEvidence: proxy.lastFailureEvidence)
        }
        
        streamProxy = proxy
        return localURL
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
        guard playbackMayStart else {
            webPlaybackCommand = WebPlaybackCommand(id: UUID(), shouldPlay: false)
            isPlaying = false
            isLoading = false
            return
        }
        webRetryOwner.cancel()
        lastObservedPlaybackStage = .decoded
        markObservedDecodedProgress()
        isVideoReadyForDisplay = true
        isLoading = false
        isPlaying = true
        error = nil
        LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: startupLatencyMs)
        FottyQualityStore.shared.record(
            category: .playback,
            name: "decoded_progress",
            outcome: .success,
            durationMilliseconds: startupLatencyMs,
            details: playbackQualityDetails(source: source)
        )
        onPlaybackAvailable()
    }

    private func waitForInitialNativeStartup(
        player: AVPlayer, item: AVPlayerItem, source: StreamSource,
        identity: MediaAudioPlaybackIdentity, deadline: NativePlaybackStartupDeadline
    ) async -> NativePlaybackStartupDeadline.Decision {
        var baseline: Double?
        var recordedReadiness = false
        while true {
            let ownsAttempt = playbackMayStart && error == nil && audioPlaybackIdentity == identity
                && self.player === player && player.currentItem === item && activeSource?.id == source.id
            let seconds = player.currentTime().seconds
            if baseline == nil, seconds.isFinite, seconds >= 0 { baseline = seconds }
            let advancing = baseline.map { seconds.isFinite && seconds > $0 + 0.35 } ?? false
            let size = item.presentationSize
            // Retain the pane's existing displayed-video startup evidence;
            // audio focus and transport bytes alone do not qualify a surface.
            let verified = isVideoReadyForDisplay && (advancing ||
                (player.timeControlStatus == .playing && size.width > 16 && size.height > 16))
            let status = item.status
            let decision = deadline.decision(at: ProcessInfo.processInfo.systemUptime,
                hasVerifiedVideoStart: status == .readyToPlay && verified, hasFailedItem: status == .failed,
                isCancelled: Task.isCancelled, ownsCurrentAttempt: ownsAttempt,
                userWantsPlayback: userWantsPlayback)
            guard decision == .waiting || decision == .started else { return decision }
            if status == .readyToPlay, !recordedReadiness {
                recordedReadiness = true
                lastObservedPlaybackStage = .mediaReady
            }
            if decision == .started { return decision }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return .abandoned }
        }
    }

    private func nativeStartupTimeoutDetails(
        player: AVPlayer, item: AVPlayerItem, deadline: NativePlaybackStartupDeadline
    ) -> [String: String] {
        let status: String
        switch item.status {
        case .unknown: status = "unknown"
        case .readyToPlay: status = "ready"
        case .failed: status = "failed"
        @unknown default: status = "other"
        }
        let control: String
        switch player.timeControlStatus {
        case .paused: control = "paused"
        case .waitingToPlayAtSpecifiedRate: control = "waiting"
        case .playing: control = "playing"
        @unknown default: control = "other"
        }
        let reason: String
        switch player.reasonForWaitingToPlay {
        case .toMinimizeStalls?: reason = "minimize_stalls"
        case .evaluatingBufferingRate?: reason = "evaluating_buffer"
        case .noItemToPlay?: reason = "no_item"
        case nil: reason = "none"
        default: reason = "other"
        }
        var details = ["native_startup_deadline_ms": String(Int(NativePlaybackStartupDeadline.timeoutSeconds * 1_000)),
                       "native_item_status": status, "native_time_control": control, "native_wait_reason": reason,
                       "native_buffer_empty": String(item.isPlaybackBufferEmpty),
                       "native_buffer_full": String(item.isPlaybackBufferFull),
                       "native_likely_to_keep_up": String(item.isPlaybackLikelyToKeepUp)]
        if let elapsed = deadline.elapsed(at: ProcessInfo.processInfo.systemUptime), elapsed <= 3_600 {
            details["native_startup_elapsed_ms"] = String(Int(elapsed * 1_000))
        }
        return details
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
                
                if playbackStagnationTicks >= 6 {
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
        if let identity = intervalIdentity, identity.attemptID == requestID, identity.sourceID == source.id {
            playbackIntervals.beginStall(identity, now: ProcessInfo.processInfo.systemUptime)
        }
        stallValidationTask?.cancel()
        let startSeconds = player?.currentTime().seconds ?? 0
        stallValidationTask = Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled,
                      loadRequestID == requestID,
                      activeSource?.id == source.id else { return }
                if let expectedItem, player?.currentItem !== expectedItem { return }
                if playbackMayStart,
                   let player,
                   player.currentTime().seconds > startSeconds + 0.35 {
                    isLoading = false
                    isPlaying = true
                    error = nil
                    recordNativeRecovery(for: source, decodedProgress: true)
                    onPlaybackAvailable()
                    startPlaybackWatchdog(for: source)
                    return
                }
            }

            guard loadRequestID == requestID,
                  activeSource?.id == source.id else { return }
            if let expectedItem, player?.currentItem !== expectedItem { return }
            if playbackMayStart,
               let player,
               player.timeControlStatus == .playing
                || player.currentTime().seconds > startSeconds + 0.35 {
                isLoading = false
                isPlaying = true
                error = nil
                recordNativeRecovery(for: source, decodedProgress: player.currentTime().seconds > startSeconds + 0.35)
                onPlaybackAvailable()
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

    private func recordNativeRecovery(for source: StreamSource, decodedProgress: Bool) {
        finishObservedStall(decodedProgress ? .decodedProgress : .transportPlaying)
        // A playing transport can still have frozen video. Only advancing
        // decoded media is evidence for the recovered counter.
        guard decodedProgress else { return }
        FottyQualityStore.shared.record(
            category: .playback,
            name: "in_place_recovery",
            outcome: .recovered,
            details: playbackQualityDetails(
                source: source,
                additional: ["recovery_kind": "native_decoded_progress"]
            )
        )
    }

    private func handleSourceFailure(
        _ failedSource: StreamSource,
        reason: String,
        countsAsStall: Bool = false,
        expectedRequestID: UUID? = nil,
        diagnosticDetails: [String: String] = [:]
    ) {
        guard isPlaybackSessionActive, userWantsPlayback,
              MultiLiveScenePolicy.isForeground(scenePhase) else { return }
        guard slot.sources.indices.contains(currentSourceIndex) else { return }
        guard slot.sources[currentSourceIndex].id == failedSource.id else { return }
        if let expectedRequestID, expectedRequestID != loadRequestID { return }
        // Duplicate bridge errors must not consume both retry budgets while
        // this attempt already owns a timer. Explicit rejection stays terminal.
        if webRetryOwner.isPending, isNetworkReachable,
           !LivePlaybackPolicy.isExplicitProviderRejection(reason) { return }

        let failureKind = LivePlaybackFailureKind.classify(
            reason: reason,
            countsAsStall: countsAsStall,
            isNetworkReachable: isNetworkReachable
        )
        lastFailureKind = failureKind
        FottyQualityStore.shared.record(
            category: .playback, name: "source_failure", outcome: .failure,
            durationMilliseconds: sourceAttemptStartedAt.map { Int(Date().timeIntervalSince($0) * 1_000) },
            details: playbackQualityDetails(source: failedSource,
                additional: diagnosticDetails.merging(["failure_kind": failureKind.rawValue]) { _, new in new })
        )
        if !isNetworkReachable {
            webRetryOwner.cancel()
            pendingRetryAfterNetworkRestore = userWantsPlayback
            foregroundResumeValidationTask?.cancel()
            stopPlaybackWatchdog()
            error = nil
            isLoading = userWantsPlayback
            isPlaying = false
            FottyQualityStore.shared.record(
                category: .playback,
                name: "network_interruption",
                outcome: .info,
                details: playbackQualityDetails(source: failedSource)
            )
            return
        }

        let recovery = slot.recoveryAction(
            for: failedSource, reason: reason, countsAsStall: countsAsStall,
            isNetworkReachable: isNetworkReachable,
            webStartupRetryCount: webStartupRetryAttemptsBySource[failedSource.id, default: 0],
            webStallRetryCount: webStallRetryAttemptsBySource[failedSource.id, default: 0],
            nativeStartupRetryCount: nativeStartupRetryAttemptsBySource[failedSource.id, default: 0]
        )
        switch recovery {
        case .retryNativeStartup:
            nativeStartupRetryAttemptsBySource[failedSource.id, default: 0] += 1
            FottyQualityStore.shared.record(
                category: .playback, name: "retry_scheduled", outcome: .info,
                details: playbackQualityDetails(source: failedSource,
                    additional: ["recovery_kind": "same_source_native_reload"])
            )
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        case .retryWebStartup:
            webStartupRetryAttemptsBySource[failedSource.id, default: 0] += 1
            scheduleWebRetry(for: failedSource)
            return
        case .retryWebStall:
            webStallRetryAttemptsBySource[failedSource.id, default: 0] += 1
            scheduleWebRetry(for: failedSource)
            return
        default:
            break
        }
        
        // Revoke the accepted start before publishing exhaustion. The audio
        // operation may finish later, but no longer owns this failed attempt.
        cancelAudioPreparation()
        finishObservedStall(.failed)
        player?.pause()
        stallValidationTask?.cancel()
        foregroundResumeValidationTask?.cancel()
        webRetryOwner.cancel()
        stopPlaybackWatchdog()
        failedSourceIDs.insert(failedSource.id)
        LiveSourceHealthStore.recordFailure(for: failedSource, wasStall: countsAsStall, reason: reason)
        
        if let next = nextPlayableSource(after: failedSource),
           let nextIndex = slot.sources.firstIndex(where: { $0.id == next.id }) {
            FottyQualityStore.shared.record(
                category: .playback,
                name: "automatic_failover",
                outcome: .failure,
                details: playbackQualityDetails(
                    source: failedSource,
                    additional: diagnosticDetails.merging(["failure_kind": failureKind.rawValue]) { _, new in new }
                )
            )
            currentSourceIndex = nextIndex
            loadCurrentSource()
            return
        }

        FottyQualityStore.shared.record(
            category: .playback,
            name: "terminal_failure",
            outcome: .failure,
            details: playbackQualityDetails(
                source: failedSource,
                additional: diagnosticDetails.merging(["failure_kind": failureKind.rawValue]) { _, new in new }
            )
        )
        isLoading = false
        isPlaying = false
        errorTitle = failureKind.title
        error = failureKind.terminalMessage
        onPlaybackUnavailable()
    }

    private func scheduleWebRetry(for source: StreamSource) {
        guard playbackMayStart else { return }
        FottyQualityStore.shared.record(
            category: .playback, name: "retry_scheduled", outcome: .info,
            details: playbackQualityDetails(source: source,
                                           additional: ["recovery_kind": "same_source_web_reload"])
        )
        isLoading = true
        isPlaying = false
        error = nil
        webRetryOwner.schedule(sourceID: source.id, attemptID: loadRequestID,
            currentContext: {
                .init(sourceID: activeSource?.id, attemptID: loadRequestID,
                      isActive: isPlaybackSessionActive, playbackMayStart: playbackMayStart,
                      isRecovering: isLoading && !isPlaying && error == nil)
            }, onRetry: {
                loadCurrentSource(ignoringCircuitBreaker: true)
            })
    }

    private func nextPlayableSource(after source: StreamSource) -> StreamSource? {
        let remaining = slot.sources.filter {
            $0.id != source.id && !failedSourceIDs.contains($0.id)
        }
        return LiveSourceHealthStore.automaticCandidates(in: remaining).first
    }

    private func isWebEmbedSource(_ source: StreamSource) -> Bool {
        slot.isWebEmbed(source)
    }

    private func playbackQualityDetails(
        source: StreamSource,
        additional: [String: String] = [:]
    ) -> [String: String] {
        let sourceKey = slot.sessions.first(where: { $0.id == source.id })?
            .diagnosticMetadata["source_key"]
        return FottyPlaybackQualityDetails.make(
            source: source,
            mode: isWebEmbedSource(source) ? "web_embed" : "native",
            route: "multiview",
            attemptID: loadRequestID,
            sourceKey: sourceKey,
            correlation: playbackCorrelation,
            deviceFamily: FottyPlaybackQualityDetails.deviceFamily,
            additional: additional.merging(["source_index": String(currentSourceIndex + 1),
                                            "source_count": String(slot.sources.count),
                                            "last_observed_stage": lastObservedPlaybackStage.rawValue]) { _, value in value }
        )
    }

    private var intervalIdentity: FottyPlaybackIntervals.Identity? {
        activeSource.map { .init(sourceID: $0.id, attemptID: loadRequestID) }
    }

    private func ensurePlaybackIntervalAttempt() {
        guard let source = activeSource, let identity = intervalIdentity else { return }
        playbackIntervals.beginAttempt(identity, context: playbackQualityDetails(source: source),
                                       now: ProcessInfo.processInfo.systemUptime)?.record()
    }

    private func markObservedDecodedProgress() {
        ensurePlaybackIntervalAttempt()
        if let identity = intervalIdentity {
            playbackIntervals.decodedProgress(identity, now: ProcessInfo.processInfo.systemUptime)?.record()
        }
    }

    private func finishObservedStall(_ completion: FottyPlaybackIntervalCompletion) {
        playbackIntervals.finishStall(playbackIntervals.identity, now: ProcessInfo.processInfo.systemUptime,
                                      completion: completion)?.record()
    }

    private func measuredAudioPreparation() async -> MediaAudioSessionPreparation {
        ensurePlaybackIntervalAttempt()
        let identity = intervalIdentity
        let startedAt = ProcessInfo.processInfo.systemUptime
        let result = await MediaAudioSession.activateForPlaybackIfNeeded()
        if let identity {
            playbackIntervals.audioPreparation(identity, startedAt: startedAt, now: ProcessInfo.processInfo.systemUptime,
                                               result: result)?.record()
        }
        return result
    }
    
    private func updateAudioState() {
        MultiLiveAudioOutputPolicy.apply(
            to: player, isAudioActive: isAudioActive,
            shouldMuteForTesting: AppRuntime.shouldMutePlaybackForTesting
        )
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
            let reportedError = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            handleNativeItemFailure(item, source: source, requestID: requestID,
                                    trigger: .failedToPlayToEnd, reportedError: reportedError)
        }
        let token3 = center.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if item.status == .failed {
                    handleNativeItemFailure(item, source: source, requestID: requestID,
                                            trigger: .errorLog)
                }
            }
        }
        playerItemNotificationTokens = [token1, token2, token3]
        // A fatal item need not emit an error-log/end notification. Its layer
        // can become not-ready, so the progress watchdog is not that boundary.
        playerItemStatusObservation = item.observe(\.status, options: [.new]) { observedItem, _ in
            guard observedItem.status == .failed else { return }
            Task { @MainActor in
                handleNativeItemFailure(observedItem, source: source, requestID: requestID,
                                        trigger: .itemStatusFailed)
            }
        }
    }

    private func handleNativeItemFailure(_ item: AVPlayerItem, source: StreamSource,
                                         requestID: UUID, trigger: NativePlaybackDiagnosticTrigger,
                                         reportedError: Error? = nil) {
        guard MultiLiveNativeFailurePolicy.ownsFailure(
            sourceID: source.id, currentSourceID: activeSource?.id,
            requestID: requestID, currentRequestID: loadRequestID,
            item: item, currentItem: player?.currentItem
        ) else { return }
        if trigger == .itemStatusFailed || trigger == .errorLog {
            guard item.status == .failed else { return }
        }
        let snapshot = diagnosticService.analyze(item, trigger: trigger, reportedError: reportedError)
        handleSourceFailure(source, reason: snapshot.failureReason, expectedRequestID: requestID,
                            diagnosticDetails: nativeDiagnosticDetails(snapshot))
    }

    private func nativeDiagnosticDetails(_ snapshot: PlayerDiagnosticService.DiagnosticSnapshot) -> [String: String] {
        snapshot.qualityDetails.merging(streamProxy?.lastFailureEvidence?.qualityDetails() ?? [:]) { _, new in new }
    }

    private func preparationDiagnosticDetails(_ details: [String: String], source: StreamSource,
                                              requestID: UUID) -> [String: String] {
        guard isPlaybackSessionActive, loadRequestID == requestID, activeSource?.id == source.id else { return [:] }
        return details.merging(streamProxy?.lastFailureEvidence?.qualityDetails() ?? [:]) { _, value in value }
    }
    
    private func removeItemFailureObservers() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        for token in playerItemNotificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        playerItemNotificationTokens.removeAll()
    }
}
