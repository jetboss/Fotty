import SwiftUI

struct ViewingSurfaceBoundsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ViewingViewportBoundsKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue(); if !next.isEmpty { value = next }
    }
}

private struct ViewingViewportMarker: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ViewingViewportBoundsKey.self, value: proxy.frame(in: .global))
        }
    }
}

/// An empty layout slot, not a second AVPlayerLayer/WKWebView. Its coordinates
/// move the one root-owned media surface without changing that surface's identity.
struct ViewingSurfaceSlot: View {
    let id: UUID
    var body: some View {
        Color.black
            .overlay {
                GeometryReader { proxy in
                    Color.clear.preference(key: ViewingSurfaceBoundsKey.self,
                                           value: [id: proxy.frame(in: .global)])
                }
            }
            .accessibilityHidden(true)
    }
}

struct ViewingMiniPlayer: View {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View {
        if let pane = viewing.primary {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(viewing.panes) { item in
                        ViewingSurfaceSlot(id: item.id).frame(width: viewing.isTwo ? 46 : 78, height: 44)
                    }
                }.clipShape(.rect(cornerRadius: 8))
                Button { viewing.expand() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pane.event.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(placement == .inline ? 1 : 2)
                        if placement != .inline { Text(viewing.isTwo ? "Two matches · Tap to return" : ViewingPlaybackCopy.status(pane.model)).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewing.isTwo ? "Return to Watch Two" : "Return to \(pane.event.displayTitle)")
                .accessibilityIdentifier("viewing-mini-expand")
                // Web controls belong to the provider; restore them rather than
                // expose an unverified generic app transport command here.
                if !viewing.isTwo && !pane.model.isUsingWebEmbed {
                    Button { pane.model.togglePlayPause() } label: {
                        Image(systemName: pane.model.userWantsPlayback ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(pane.model.userWantsPlayback ? "Pause broadcast" : "Resume broadcast")
                    .accessibilityIdentifier("viewing-mini-transport")
                }
                if placement != .inline {
                    Button { viewing.stop() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Stop watching").accessibilityIdentifier("viewing-mini-stop")
                }
            }
            .padding(.horizontal, 8)
            .buttonStyle(.plain)
        }
    }
}

enum ViewingPlaybackCopy {
    @MainActor static func status(_ model: LivePlayerViewModel) -> String {
        if model.isNativePlaybackTransferInProgress { return "Switching player…" }
        return status(state: model.playbackState, hasError: model.error != nil,
               userWantsPlayback: model.userWantsPlayback,
               isNetworkReachable: model.isNetworkReachable)
    }

    /// `isPlaying` includes recovery to preserve transport ownership. UI copy
    /// must describe that typed state instead of claiming a stalled picture plays.
    static func status(state: LivePlaybackState, hasError: Bool,
                       userWantsPlayback: Bool, isNetworkReachable: Bool) -> String {
        if hasError || state == .failed { return "Source unavailable" }
        if !userWantsPlayback { return "Paused" }
        switch state {
        case .idle: return "Ready"
        case .connecting:
            return isNetworkReachable ? "Connecting…" : "Waiting for connection…"
        case .recovering:
            return isNetworkReachable ? "Reconnecting…" : "Waiting for connection…"
        case .paused: return "Paused"
        // The original web owner keeps playing during a native handoff.
        case .playing, .preparingNativeHandoff: return "Playing"
        case .failed: return "Source unavailable"
        }
    }
}

/// Presentation-only identity for the single watch screen. Accessibility sizes
/// move the score below the names rather than compressing the names or badges.
/// Watch Two retains its existing separate identity/layout contract.
struct SinglePlayerMatchIdentity: View {
    let event: EventReference
    let status: String
    let scoreText: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        identityLayout {
            HStack(alignment: .top, spacing: 12) {
                if !event.isBroadcastChannel && !event.awayName.isEmpty {
                    HStack(spacing: 3) {
                        TeamBadgeWindow(teamName: event.homeName, badgeURL: event.homeBadgeURL, size: 32, triggerSearch: true)
                        TeamBadgeWindow(teamName: event.awayName, badgeURL: event.awayBadgeURL, size: 32, triggerSearch: true)
                    }
                    .accessibilityHidden(true)
                } else {
                    SportEmblem(category: event.normalizedCategory, size: 32).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.displayTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let scoreText {
                Text(scoreText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel("Score \(scoreText)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewing-single-match-identity")
    }

    private var identityLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
}

/// Single-player navigation only. At narrow widths/large text the media actions
/// get their own row instead of squeezing a long title between four hit areas.
/// Every callback still belongs to the existing scene/model owner.
struct SinglePlayerNavigationHeader: View {
    let subtitle: String
    let showsNativeFullscreen: Bool
    let enablesNativeFullscreen: Bool
    let isFocused: Bool
    let onMinimize: () -> Void
    let onNativeFullscreen: () -> Void
    let onExitFocus: () -> Void
    let onClose: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                minimizeButton
                title.fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 8)
                mediaActions
                closeButton
            }
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    minimizeButton
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    closeButton
                }
                if showsNativeFullscreen || isFocused {
                    HStack(spacing: 12) { mediaActions }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.body.weight(.semibold))
        .buttonStyle(FottyPressButtonStyle(cornerRadius: 22))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(FottyTheme.surfaceSubtle)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Now watching").font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private var minimizeButton: some View {
        Button(action: onMinimize) { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
            .accessibilityLabel("Minimize player and browse")
            .accessibilityIdentifier("viewing-minimize")
    }
    private var closeButton: some View {
        Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
            .accessibilityLabel("Close player")
            .accessibilityIdentifier("close-live-player")
    }
    @ViewBuilder private var mediaActions: some View {
        if showsNativeFullscreen {
            Button(action: onNativeFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
            }
            .disabled(!enablesNativeFullscreen)
            .accessibilityLabel("Open native fullscreen player")
            .accessibilityIdentifier("viewing-native-fullscreen")
        }
        if isFocused {
            Button(action: onExitFocus) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Show match companion")
            .accessibilityIdentifier("viewing-exit-focus")
        }
    }
}

/// Station guide metadata stays separate from the playing picture and fixture
/// identity. Only an exact reviewed station can reuse the TV tab's fresh guide.
@MainActor
struct SinglePlayerStationGuideProjection {
    let station: SportsTVStation
    let current: SportsTVGuidePolicy.Entry?
    let next: SportsTVGuidePolicy.Entry?

    init?(event: EventReference, snapshot: BroadcastRegistrySnapshot?, at now: Date) {
        let request = StreamPlaybackRequest(event: event)
        let reviewedStation = SportsTVStation.identifying(request)
            ?? CricketBroadcastChannel.identifying(request: request)
                .flatMap { SportsTVStation.station(id: $0.canonicalID) }
        guard let station = reviewedStation else { return nil }
        self.station = station
        let entries = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now)
        current = entries.first { $0.isOnNow(at: now) }
        next = entries.first { $0.start > now }
    }
}

struct ViewingExperienceView: View {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(LiveScoreService.self) private var scores
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var companionTab = CompanionTab.live
    @State private var focusVideo = false
    @State private var showsTabletDetails = false
    @State private var singleFeedbackContext: SinglePlaybackFeedbackContext?
    @State private var broadcastRegistry = BroadcastRegistryClient.shared
    enum CompanionTab: String, CaseIterable { case live = "Live", details = "Match" }

    var body: some View {
        GeometryReader { proxy in
            let wide = ViewingExperienceLayout.usesCompanion(width: proxy.size.width, accessibility: typeSize.isAccessibilitySize)
            let videoFirst = ViewingExperienceLayout.usesVideoFirstSinglePlayer(
                isPad: UIDevice.current.userInterfaceIdiom == .pad, isTwo: viewing.isTwo)
            if videoFirst, let pane = viewing.primary {
                tabletSinglePlayer(pane, size: proxy.size)
            } else {
            VStack(spacing: 0) {
                if viewing.isTwo { toolbar }
                else if let pane = viewing.primary { singleToolbar(pane) }
                if viewing.isTwo {
                    twoMatches(size: proxy.size)
                } else if let pane = viewing.primary {
                    if focusVideo {
                        // Fit both axes of a short landscape window. Focus is
                        // not a width-driven video hidden below a scroll edge.
                        ViewingSurfaceSlot(id: pane.id)
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(16)
                        singleFocusActions(pane)
                    } else { ScrollView {
                        if wide && !focusVideo {
                            HStack(alignment: .top, spacing: 24) {
                                singleColumn(pane).frame(maxWidth: .infinity)
                                companion(pane).frame(width: min(340, proxy.size.width * 0.28))
                            }
                            .padding(20)
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                singleColumn(pane)
                                if !focusVideo { companion(pane) }
                            }.padding(16)
                        }
                    }
                    .background(ViewingViewportMarker())
                    }
                }
            }
            .background(FottyTheme.background)
            .preferredColorScheme(viewing.isTwo ? nil : .dark)
            }
        }
        // Give the container its own AX node so its identifier cannot replace
        // the toolbar's Minimize/Close identities on the physical iPad.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewing-experience")
        .sheet(isPresented: Binding(get: { viewing.showsSecondMatchPicker }, set: { if !$0 { viewing.dismissMatchPicker() } })) {
            ViewingSecondMatchPicker()
        }
        .sheet(isPresented: Binding(get: { viewing.showsContinuity }, set: { viewing.showsContinuity = $0 })) {
            ViewingContinuitySheet()
        }
        .sheet(isPresented: $showsTabletDetails) {
            if let pane = viewing.primary {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            SinglePlayerMatchIdentity(event: pane.event, status: ViewingPlaybackCopy.status(pane.model),
                                scoreText: score(for: pane.event).map { "\($0.homeGoals)–\($0.awayGoals)" })
                            companion(pane, showsHeading: false)
                        }.padding(20)
                    }
                    .navigationTitle(pane.event.isBroadcastChannel ? "Channel details" : "Match details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsTabletDetails = false }
                                .accessibilityIdentifier("viewing-details-done")
                        }
                    }
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $singleFeedbackContext) { context in
            FottyFeedbackSheet(area: .playback, initialExpected: context.expected, initialActual: context.actual)
        }
        .onChange(of: viewing.primary?.id) { _, _ in
            showsTabletDetails = false
            singleFeedbackContext = nil
        }
        .onChange(of: viewing.isTwo) { _, isTwo in
            if isTwo { singleFeedbackContext = nil }
        }
    }

    /// Only layout slots move. ViewingSessionShell keeps the real media surface,
    /// player/item and attempt mounted, including while either sheet is open.
    private func tabletSinglePlayer(_ pane: ViewingSessionCoordinator.Pane, size: CGSize) -> some View {
        let compactControls = typeSize.isAccessibilitySize || size.width < 600 || size.height < 500
        return VStack(spacing: 0) {
            tabletToolbar(pane, compact: compactControls)
            GeometryReader { stage in
                let video = ViewingExperienceLayout.singleVideoSize(in: stage.size)
                ViewingSurfaceSlot(id: pane.id)
                    .frame(width: video.width, height: video.height)
                    .position(x: stage.size.width / 2, y: stage.size.height / 2)
            }
            // Publish this on every resize/orientation, not a departed scroll
            // branch's viewport. Retained media must never clip to stale bounds.
            .background(ViewingViewportMarker())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabletControlDock(pane, compact: compactControls)
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewing-video-first")
    }

    private func tabletToolbar(_ pane: ViewingSessionCoordinator.Pane, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Button { viewing.minimize() } label: {
                Image(systemName: "chevron.down").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Minimize player and browse")
            .accessibilityIdentifier("viewing-minimize")
            badgePair(pane.event)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pane.event.displayTitle)
                .accessibilityHidden(!typeSize.isAccessibilitySize)
            VStack(alignment: .leading, spacing: 3) {
                if !typeSize.isAccessibilitySize {
                    Text(pane.event.displayTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                Text(ViewingPlaybackCopy.status(pane.model))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !pane.model.isUsingWebEmbed {
                Button { pane.model.beginNativeFullscreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .disabled(!pane.model.canShowNativeFullscreen)
                .accessibilityLabel("Open native fullscreen player")
                .accessibilityIdentifier("viewing-native-fullscreen")
            }
            Button { viewing.stop() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close player")
            .accessibilityIdentifier("close-live-player")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(FottyTheme.surfaceSubtle)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tabletControlDock(_ pane: ViewingSessionCoordinator.Pane, compact: Bool) -> some View {
        // These controls deliberately sit OUTSIDE the retained media bounds.
        // A transparent overlay above WebKit would steal provider control taps;
        // chrome below the retained surface would instead be untappable.
        Group {
            if compact {
                // Standard action symbols keep a short/narrow/AX window usable;
                // full button names remain available to VoiceOver and on hover.
                // Full team names remain readable in the scrollable Details sheet.
                HStack(spacing: 12) { tabletActions(pane, compact: true) }
                    .labelStyle(.iconOnly)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { tabletActions(pane, compact: false) }
                    HStack(spacing: 12) { tabletActions(pane, compact: true) }.labelStyle(.iconOnly)
                }
            }
        }
        .font(.body.weight(.medium))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(FottyTheme.surfaceSubtle)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewing-control-dock")
    }

    @ViewBuilder private func tabletActions(_ pane: ViewingSessionCoordinator.Pane, compact: Bool) -> some View {
        Button { pane.model.showSourceSelector = true } label: {
            Label("Sources", systemImage: "antenna.radiowaves.left.and.right").frame(minHeight: 44)
        }
        .tint(FottyTheme.accent)
        .accessibilityValue(pane.model.activeSession?.providerName ?? "No source selected")
        .accessibilityIdentifier("viewing-sources")
        .help("Sources")
        Button { showsTabletDetails = true } label: {
            Label("Details", systemImage: "info.circle").frame(minHeight: 44)
        }
        .accessibilityIdentifier("viewing-details")
        .help(pane.event.isBroadcastChannel ? "Channel details" : "Match details")
        if !compact {
            Button { viewing.showMatchPicker() } label: {
                Label("Add match", systemImage: "rectangle.split.2x1").frame(minHeight: 44)
            }
            .accessibilityLabel("Add a second match")
            .accessibilityIdentifier("viewing-watch-two")
        }
        singleOptions(pane, showsFocusOption: false, includesAddMatch: compact)
    }

    /// The phone header carries navigation; full match identity belongs beside
    /// its badges below the video. Repeating long team names above and below
    /// the picture made the controls compete with the content at phone widths.
    private func singleToolbar(_ pane: ViewingSessionCoordinator.Pane) -> some View {
        SinglePlayerNavigationHeader(
            subtitle: focusVideo ? ViewingPlaybackCopy.status(pane.model) : pane.event.categoryDisplayName,
            showsNativeFullscreen: !pane.model.isUsingWebEmbed,
            enablesNativeFullscreen: pane.model.canShowNativeFullscreen, isFocused: focusVideo,
            onMinimize: { viewing.minimize() },
            onNativeFullscreen: { pane.model.beginNativeFullscreen() },
            onExitFocus: { focusVideo = false }, onClose: { viewing.stop() })
    }

    private func singleFocusActions(_ pane: ViewingSessionCoordinator.Pane) -> some View {
        HStack(spacing: 12) {
            Button { pane.model.showSourceSelector = true } label: {
                Label("Sources", systemImage: "antenna.radiowaves.left.and.right").frame(minHeight: 44)
            }
            .tint(FottyTheme.accent)
            .accessibilityIdentifier("viewing-sources")
            Button { showsTabletDetails = true } label: {
                Label(pane.event.isBroadcastChannel ? "Channel details" : "Match details", systemImage: "info.circle").frame(minHeight: 44)
            }
            .accessibilityLabel("\(pane.event.isBroadcastChannel ? "Channel details" : "Match details") for \(pane.event.displayTitle)")
            .accessibilityIdentifier("viewing-details")
        }
        .if(typeSize.isAccessibilitySize) { $0.labelStyle(.iconOnly) }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered).buttonBorderShape(.capsule)
        .tint(.white)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(FottyTheme.surfaceSubtle)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { viewing.minimize() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .accessibilityLabel("Minimize player and browse").accessibilityIdentifier("viewing-minimize")
            VStack(alignment: .leading, spacing: 3) {
                Text(viewing.isTwo ? "Watch Two" : (viewing.primary?.event.displayTitle ?? "Watch"))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if viewing.isTwo { Text("Two matches · One audio focus").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            // Fullscreen stays a direct media action, not a buried layout menu.
            // Keep it outside the retained video layer's hit-testing region.
            if !viewing.isTwo, let pane = viewing.primary, !pane.model.isUsingWebEmbed {
                Button { pane.model.beginNativeFullscreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .disabled(!pane.model.canShowNativeFullscreen)
                .accessibilityLabel("Open native fullscreen player")
                .accessibilityIdentifier("viewing-native-fullscreen")
            }
            if focusVideo && !viewing.isTwo {
                Button { focusVideo = false } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Show match companion")
                    .accessibilityIdentifier("viewing-exit-focus")
            }
            Button { viewing.stop() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Close player").accessibilityIdentifier("close-live-player")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(FottyTheme.surfaceSubtle)
    }

    private func singleColumn(_ pane: ViewingSessionCoordinator.Pane) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewingSurfaceSlot(id: pane.id).aspectRatio(16/9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 16))
            SinglePlayerMatchIdentity(event: pane.event, status: ViewingPlaybackCopy.status(pane.model),
                scoreText: score(for: pane.event).map { "\($0.homeGoals)–\($0.awayGoals)" })
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { singleActions(pane) }
                VStack(alignment: .leading, spacing: 8) { singleActions(pane) }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.white)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private func singleActions(_ pane: ViewingSessionCoordinator.Pane) -> some View {
        Button { pane.model.showSourceSelector = true } label: {
            Label("Sources", systemImage: "antenna.radiowaves.left.and.right")
                .frame(minHeight: 44)
        }
            .buttonStyle(.borderedProminent)
            .tint(FottyTheme.accent)
            .foregroundStyle(FottyTheme.textOnAccent)
            .accessibilityIdentifier("viewing-sources")
        Button { viewing.showMatchPicker() } label: {
            Label("Add match", systemImage: "rectangle.split.2x1").frame(minHeight: 44)
        }
            .accessibilityLabel("Add a second match")
            .accessibilityIdentifier("viewing-watch-two")
        singleOptions(pane)
    }

    private func singleOptions(_ pane: ViewingSessionCoordinator.Pane, showsFocusOption: Bool = true,
                               includesAddMatch: Bool = false) -> some View {
        Menu {
            if pane.model.canChooseSinglePlaybackQuality {
                SinglePlaybackQualityMenu(selection: Binding(
                    get: { pane.model.singlePlaybackQuality.preference },
                    set: { _ = pane.model.selectSinglePlaybackQuality($0) }
                ))
            }
            if includesAddMatch {
                Button { viewing.showMatchPicker() } label: { Label("Add match", systemImage: "rectangle.split.2x1") }
                    .accessibilityLabel("Add a second match")
                    .accessibilityIdentifier("viewing-watch-two")
            }
            if pane.model.isNativePlaybackTransferInProgress {
                Button { pane.model.cancelNativePlaybackTransfer() } label: {
                    Label("Cancel Player Switch", systemImage: "xmark")
                }
                .accessibilityIdentifier("viewing-cancel-native-transfer")
                Button { pane.model.requestPauseFromRemoteCommand() } label: {
                    Label("Pause Broadcast", systemImage: "pause.fill")
                }
                .accessibilityIdentifier("viewing-pause-native-transfer")
            } else if pane.model.canRequestNativePlaybackTransfer {
                Button { pane.model.requestNativePlaybackTransfer() } label: {
                    Label("Use Native Player", systemImage: "play.rectangle")
                }
                .accessibilityIdentifier("viewing-use-native-player")
            }
            if showsFocusOption {
                Button { focusVideo.toggle() } label: {
                    Label(focusVideo ? (pane.event.isBroadcastChannel ? "Show Channel Details" : "Show Match Companion") : "Focus on Video", systemImage: "viewfinder")
                }
                .accessibilityIdentifier("viewing-focus-video")
            }
            if pane.model.isPictureInPictureAvailable && !pane.model.isUsingWebEmbed {
                Button { pane.model.togglePictureInPicture() } label: {
                    Label(pane.model.isPictureInPictureActive ? "Stop Picture in Picture" : "Start Picture in Picture",
                          systemImage: pane.model.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityIdentifier("viewing-pip")
            }
            Divider()
            Button { singleFeedbackContext = SinglePlaybackFeedbackContext.make(model: pane.model) } label: {
                Label("Report a problem", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
            .accessibilityIdentifier("single-playback-report")
            Button { viewing.showsContinuity = true } label: { Label("Continue on Another Device…", systemImage: "ipad.and.iphone") }
                .accessibilityIdentifier("viewing-continuity")
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Viewing options")
            .accessibilityIdentifier("viewing-options")
    }

    private func identity(_ pane: ViewingSessionCoordinator.Pane) -> some View {
        HStack(alignment: .top, spacing: 12) {
            badgePair(pane.event)
            VStack(alignment: .leading, spacing: 4) {
                Text(pane.event.displayTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(ViewingPlaybackCopy.status(pane.model)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let score = score(for: pane.event) {
                Text("\(score.homeGoals)–\(score.awayGoals)").font(.title2.weight(.semibold)).monospacedDigit()
            }
        }
    }

    @ViewBuilder private func badgePair(_ event: EventReference) -> some View {
        if !event.isBroadcastChannel && !event.awayName.isEmpty {
            HStack(spacing: 2) {
                TeamBadgeWindow(teamName: event.homeName, badgeURL: event.homeBadgeURL, size: 30, triggerSearch: true)
                TeamBadgeWindow(teamName: event.awayName, badgeURL: event.awayBadgeURL, size: 30, triggerSearch: true)
            }
        } else if SportsTVStation.identifies(event) {
            Image(systemName: "tv").font(.title3).foregroundStyle(FottyTheme.textSecondary)
                .frame(width: 32, height: 32)
        } else { SportEmblem(category: event.normalizedCategory, size: 32) }
    }

    private func companion(_ pane: ViewingSessionCoordinator.Pane, showsHeading: Bool = true) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
        if !viewing.isTwo, let guide = SinglePlayerStationGuideProjection(event: pane.event,
            snapshot: broadcastRegistry.snapshot, at: tick.date) {
            stationGuide(guide)
        } else {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeading { Text("Match companion").font(FottyTheme.typeSectionTitle) }
            Picker("Match companion", selection: $companionTab) {
                ForEach(CompanionTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if companionTab == .live, !viewing.isTwo, WatchingSpoilerProtection.shared.protects(pane.event) {
                Label("Spoiler-safe watching", systemImage: "eye.slash").foregroundStyle(.secondary)
            } else if companionTab == .live, let current = CurrentSportsMatchContextPolicy.event(for: pane.event,
                in: MatchListViewModel.shared.matchContextCatalog, at: tick.date) {
                CricketMatchContextView(event: current, at: tick.date)
                UCLReportedScoreView(event: current, at: tick.date)
            } else if companionTab == .live, let score = score(for: pane.event) {
                HStack {
                    Text(score.minute ?? score.status.displayText).font(.headline)
                    Spacer()
                    Text("\(score.homeGoals)–\(score.awayGoals)").font(.title2.weight(.semibold)).monospacedDigit()
                }
                if let qualifier = scores.scoreStatusQualifier { Text(qualifier).font(.caption).foregroundStyle(.secondary) }
                if let match = scores.findMatch(home: pane.event.homeName, away: pane.event.awayName, near: pane.event.kickoffDate),
                   let events = match.events, !events.isEmpty {
                    LiveMatchTimelineView(events: events, homeTeamId: match.homeTeam.id, awayTeamId: match.awayTeam.id)
                        .frame(minHeight: 200, maxHeight: 320)
                }
            } else {
                Label(pane.event.categoryDisplayName, systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
                if let kickoff = pane.event.kickoffDate {
                    Text(kickoff, format: .dateTime.weekday().month().day().hour().minute()).font(.subheadline)
                }
                Text(companionState(pane.event)).font(.subheadline).foregroundStyle(.secondary)
                if pane.event.isBroadcastChannel {
                    Text("Channel viewing does not identify the programme on air.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            if let future = nextPlannedEvent {
                Text("Next in My Matchday").font(.headline)
                HStack(alignment: .top, spacing: 10) {
                    badgePair(future).accessibilityHidden(true)
                    Text(future.displayTitle).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let start = future.kickoffDate { Text(start, style: .time).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(16).background(FottyTheme.surface, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewing-companion")
        }
        }
    }

    @ViewBuilder private func stationGuide(_ guide: SinglePlayerStationGuideProjection) -> some View {
        if guide.current != nil || guide.next != nil {
            VStack(alignment: .leading, spacing: 16) {
                Text("Programme guide").font(FottyTheme.typeSectionTitle)
                    .accessibilityAddTraits(.isHeader)
                if let current = guide.current {
                    stationProgramme(current, label: "Now", showsEnd: true)
                }
                if guide.current != nil && guide.next != nil { Divider() }
                if let next = guide.next {
                    stationProgramme(next, label: "Next", showsEnd: false)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(FottyTheme.surface, in: .rect(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("viewing-station-guide")
        }
    }

    private func stationProgramme(_ programme: SportsTVGuidePolicy.Entry, label: String,
                                  showsEnd: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(programme.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if showsEnd, let end = programme.end {
                Text("\(programme.start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(programme.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var nextPlannedEvent: EventReference? {
        let now = Date()
        let catalog = MatchListViewModel.shared.playbackCatalog
        return MyMatchdayStore.shared.savedMatches.compactMap { saved -> EventReference? in
            guard let event = SavedMatchContinuityPolicy.currentEvent(for: saved, in: catalog),
                  !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
                  event.kickoffDate.map({ $0 > now }) == true else { return nil }
            let status = event.normalizedCategory == "football"
                ? scores.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate).flatMap { scores.currentStatus(for: $0) } : nil
            guard MatchdayEventStatePolicy.section(for: event, at: now, status: status) == .upcoming else { return nil }
            return event
        }.min { ($0.kickoffDate ?? .distantFuture) < ($1.kickoffDate ?? .distantFuture) }
    }

    private func score(for event: EventReference) -> LiveScoreService.LiveScore? {
        guard event.normalizedCategory == "football",
              viewing.isTwo || !WatchingSpoilerProtection.shared.protects(event) else { return nil }
        return scores.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)
    }

    private func companionState(_ event: EventReference) -> String {
        let status = event.normalizedCategory == "football"
            ? scores.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate).flatMap { scores.currentStatus(for: $0) } : nil
        switch MatchdayEventStatePolicy.section(for: event, status: status) {
        case .live: return "Live fixture"
        case .upcoming: return "Scheduled"
        case .recent: return MatchdayEventStatePolicy.presentationLabel(for: event, status: status)
        case .channel: return "TV channel"
        case .listedNow: return "Broadcast listed · Match status not confirmed"
        case .awaitingConfirmation: return "Waiting for a current match update"
        case .timeToBeConfirmed: return "Start time not confirmed"
        }
    }

    private func twoMatches(size: CGSize) -> some View {
        ScrollView {
            let columns = ViewingExperienceLayout.usesTwoColumns(width: size.width, accessibility: typeSize.isAccessibilitySize)
            let layout = columns ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 20))
            VStack(alignment: .leading, spacing: 16) {
                layout {
                    ForEach(viewing.displayPanes) { pane in
                        VStack(alignment: .leading, spacing: 10) {
                            identity(pane)
                            ViewingSurfaceSlot(id: pane.id).aspectRatio(16/9, contentMode: .fit).clipShape(.rect(cornerRadius: 14))
                            ViewThatFits(in: .horizontal) {
                                HStack { panelActions(pane) }
                                VStack(alignment: .leading, spacing: 8) {
                                    panelActions(pane, sourceOnly: true)
                                    HStack { panelActions(pane, controlsOnly: true) }
                                }
                                VStack(alignment: .leading) { panelActions(pane) }
                            }
                            .buttonStyle(FottySecondaryButtonStyle())
                        }.frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    Button { viewing.swap() } label: { Label("Swap", systemImage: "arrow.left.arrow.right") }
                        .accessibilityIdentifier("viewing-swap")
                    Spacer()
                    Button("Return to one match") { if let id = viewing.primaryID { viewing.keepOnly(id) } }
                        .accessibilityIdentifier("viewing-return-one")
                }.buttonStyle(FottySecondaryButtonStyle())
                if let audio = viewing.panes.first(where: { $0.id == viewing.audioID }) {
                    Label("Audio: \(audio.event.displayTitle)", systemImage: "speaker.wave.2").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
        .background(ViewingViewportMarker())
    }

    @ViewBuilder private func panelActions(_ pane: ViewingSessionCoordinator.Pane, sourceOnly: Bool = false, controlsOnly: Bool = false) -> some View {
        if !controlsOnly {
        Button { pane.model.showSourceSelector = true } label: { Label("Sources", systemImage: "antenna.radiowaves.left.and.right") }
            .accessibilityLabel("Sources for \(pane.event.displayTitle)").accessibilityIdentifier("viewing-pane-source-\(pane.event.id)")
            .accessibilityValue(pane.model.activeSession?.providerName ?? "No source selected")
        }
        if !sourceOnly {
        Button { viewing.selectAudio(to: pane.id) } label: { Label("Audio", systemImage: viewing.audioID == pane.id ? "speaker.wave.2.fill" : "speaker.slash") }
            .accessibilityLabel("Listen to \(pane.event.displayTitle)").accessibilityValue(viewing.audioID == pane.id ? "Selected" : "Muted")
            .accessibilityIdentifier("viewing-pane-audio-\(pane.event.id)")
        Menu {
            Button { viewing.showMatchPicker(replacing: pane.id) } label: {
                Label("Change Match…", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("viewing-pane-change-\(pane.event.id)")
            Button { viewing.keepOnly(pane.id) } label: { Label("Keep This Match", systemImage: "rectangle") }
                .accessibilityLabel("Return to \(pane.event.displayTitle) only")
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Options for \(pane.event.displayTitle)")
            .accessibilityIdentifier("viewing-pane-options-\(pane.event.id)")
        }
    }
}

struct ViewingSecondMatchPicker: View {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveScoreService.self) private var scores
    @Environment(\.scenePhase) private var scenePhase
    @State private var prepared: ViewingMatchPickerPolicy.Prepared?
    @State private var query = ""
    @State private var sport = HomeSportsDiscovery.allSports
    @State private var preparationID = UUID()
    @State private var projectionDate = Date()
    private var catalog: MatchListViewModel { .shared }
    private var candidates: [EventReference] { prepared?.results(query: query, sport: sport) ?? [] }
    private var inputKey: String {
        "\(catalog.contentRevision)|\(scores.lastRefresh?.timeIntervalSince1970 ?? 0)|\(Int(projectionDate.timeIntervalSince1970 / 60))|\(viewing.panes.map { $0.id.uuidString }.joined(separator: ","))"
    }
    var body: some View {
        NavigationStack {
            List {
                if let prepared, prepared.sports.count > 1 {
                    Picker("Sport", selection: $sport) {
                        Text("All sports").tag(HomeSportsDiscovery.allSports)
                        ForEach(prepared.sports, id: \.self) { category in
                            Text(AnalyticalDataEngine.categoryDisplayName(for: category)).tag(category)
                        }
                    }
                    .accessibilityIdentifier("viewing-match-picker-sport")
                }
                ForEach(candidates) { event in
                Button { viewing.chooseSecond(event) } label: {
                    HStack(spacing: 12) {
                        if event.isBroadcastChannel || event.awayName.isEmpty {
                            SportEmblem(category: event.normalizedCategory, size: 30)
                        } else {
                            HStack(spacing: 2) {
                                TeamBadgeWindow(teamName: event.homeName, badgeURL: event.homeBadgeURL, size: 26, triggerSearch: true)
                                TeamBadgeWindow(teamName: event.awayName, badgeURL: event.awayBadgeURL, size: 26, triggerSearch: true)
                            }
                        }
                        VStack(alignment: .leading) {
                            Text(event.displayTitle).foregroundStyle(FottyTheme.textPrimary)
                            Text(event.categoryDisplayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: viewing.matchPickerReplacementID == nil ? "plus.circle" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(FottyTheme.accentText)
                    }.frame(minHeight: 44)
                }
                .accessibilityIdentifier("viewing-second-match-\(event.id)")
                }
            }
            .searchable(text: $query, prompt: "Teams, competition or sport")
            .overlay {
                if prepared == nil { ProgressView("Finding matches…") }
                else if candidates.isEmpty {
                    ContentUnavailableView(query.isEmpty && sport == HomeSportsDiscovery.allSports ? "No other broadcast yet" : "No matching broadcast",
                        systemImage: "play.tv", description: Text("Your current viewing stays unchanged."))
                }
            }
            .navigationTitle(viewing.matchPickerReplacementID == nil ? "Add a second match" : "Change match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: inputKey) {
                let generation = UUID(); preparationID = generation
                let key = inputKey
                guard let next = await ViewingMatchPickerPolicy.prepare(events: catalog.matches,
                    catalog: catalog.playbackCatalog, excluding: viewing.panes.map(\.event), now: projectionDate,
                    status: { event in
                        guard event.normalizedCategory == "football" else { return nil }
                        return scores.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)
                            .flatMap { scores.currentStatus(for: $0) }
                    }, leagueName: { event in
                        guard event.normalizedCategory == "football" else { return nil }
                        let match = scores.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)
                        let league = AnalyticalDataEngine.footballLeagueTab(for: event, officialMatch: match)
                        return league == .all || league == .other ? nil : league.displayName
                    }, isCurrent: { preparationID == generation && inputKey == key }),
                    !Task.isCancelled, preparationID == generation, inputKey == key else { return }
                prepared = next
                if sport != HomeSportsDiscovery.allSports, !next.sports.contains(sport) { sport = HomeSportsDiscovery.allSports }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                projectionDate = Date()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                    projectionDate = Date()
                }
            }
        }
    }
}

struct ViewingContinuitySheet: View {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let event = viewing.primary?.event {
                    Section { Text(event.displayTitle).font(.headline) }
                    Section {
                        Button(viewing.handoffPublisher.isOffering ? "Offer again" : "Continue on another device") {
                            do { try viewing.handoffPublisher.offer(event: event); error = nil }
                            catch { self.error = "This match cannot be offered right now." }
                        }
                        if viewing.handoffPublisher.isOffering { Button("Stop offering", role: .destructive) { viewing.handoffPublisher.stop() } }
                    } footer: {
                        Text("Use Handoff on another device signed into your Apple Account. Only this match’s identity is offered; that device confirms it and finds a fresh broadcast. Your current viewing stays unchanged.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Continue watching").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
