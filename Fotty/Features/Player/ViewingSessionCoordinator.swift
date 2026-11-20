import SwiftUI

/// One scene owns the media surfaces; destinations submit prepared choices,
/// never keep a second player alive behind a cover. Presentation is not transport.
@Observable @MainActor
final class ViewingSessionCoordinator {
    struct Pane: Identifiable, Sendable {
        let id: UUID
        let model: LivePlayerViewModel
        var event: EventReference { model.event }
    }

    struct SingleDiscoveryRecovery {
        let event: EventReference
        let category: StreamFailureCategory
        let retryable: Bool
        var retryOptionalLookup: (@MainActor () -> Void)? = nil
    }

    private static let cancelledDiscovery: Set<StreamFailureCategory> = [
        .navigationCancelled, .duplicateRequestCancelled, .userCancelled, .backgroundedDuringResolution
    ]

    private(set) var panes: [Pane] = [] {
        didSet {
            // Revoke local single-view capture synchronously. An asynchronous
            // observation must not mistake a rapid pair→single return for a
            // decoded confirmation that occurred in single playback.
            if panes.count != 1 { cancelLastLiveCapture() }
            WatchingSpoilerProtection.shared.setActiveEvent(panes.count == 1 ? panes.first?.event : nil)
        }
    }
    private(set) var expanded = true
    private(set) var primaryID: UUID?
    private(set) var audioID: UUID?
    var showsContinuity = false
    /// Playback source settings, opened from a failed lookup's Sources action.
    var showsSourceSettings = false
    var resolutionMessage: String?
    var resolutionError: String? {
        // Every new assignment owns its own alert, including equal messages.
        // Generic/player errors must never inherit a previous discovery action.
        didSet { singleDiscoveryRecovery = nil }
    }
    private(set) var singleDiscoveryRecovery: SingleDiscoveryRecovery?
    private(set) var pendingSingleEvent: EventReference?
    var incomingHandoff: SportsHandoffIdentity?
    var incomingEvent: EventReference?
    let handoffPublisher: SportsHandoffPublisher
    @ObservationIgnored private let lastLiveStore: LastLiveMatchStore
    @ObservationIgnored private var lastLiveCaptureGeneration = UUID()
    @ObservationIgnored private var lastLiveCaptureTicket: LastLiveMatchStore.PlaybackTicket?
    @ObservationIgnored private var lastLiveCaptureBegan = false
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    @ObservationIgnored private var resolutionGeneration = UUID()
    @ObservationIgnored private var activeRequest: StreamPlaybackRequest?
    @ObservationIgnored private var optionalSourceLookupGeneration: UUID?
    @ObservationIgnored private var optionalSourceLookupPaneID: UUID?
    @ObservationIgnored private var singleSourceDiscoveryGeneration: UUID?
    @ObservationIgnored private var singleSourceDiscoveryPaneID: UUID?
    @ObservationIgnored private var singleSourceDiscoveryEventID: String?
    private struct SinglePlaybackRetryOwner {
        let paneID: UUID
        let attemptID: UUID
        let intentID: UUID
    }
    @ObservationIgnored private var singlePlaybackRetryOwner: SinglePlaybackRetryOwner?
    @ObservationIgnored private(set) var audioTransferTask: Task<Void, Never>?
    @ObservationIgnored private var audioTransferGeneration = UUID()
    @ObservationIgnored private var audioRetirements: [ObjectIdentifier: NativePlayerAudioIsolation.Barrier] = [:]
    private struct WebAudioRetirement {
        let revision = UUID()
        let wait: @MainActor () async -> Bool
    }
    @ObservationIgnored private var webAudioRetirements: [UUID: WebAudioRetirement] = [:]
    @ObservationIgnored private let captureWebAudioRevocation: @MainActor (LivePlayerViewModel) -> (@MainActor () async -> Bool)?
    @ObservationIgnored private let makeModel: @MainActor (EventReference, [StreamSession]) -> LivePlayerViewModel
    @ObservationIgnored private let resolvePlayback: @MainActor (StreamPlaybackRequest) async -> StreamResolutionOutcome
    typealias SingleDiscovery = @MainActor (StreamPlaybackRequest, @escaping @Sendable ([StreamSession]) async -> Void) async -> StreamResolutionOutcome
    @ObservationIgnored private let discoverSinglePlayback: SingleDiscovery
    @ObservationIgnored private let rediscoverSinglePlayback: SingleDiscovery
    @ObservationIgnored private let currentSingleEvent: @MainActor (EventReference) -> EventReference?
    @ObservationIgnored private let catalogEvent: @MainActor (StreamPlaybackRequest) async -> EventReference?
    @ObservationIgnored private let cancelPlayback: @MainActor (StreamPlaybackRequest) async -> Void

    private static let singleAudioTransferFailure = "Audio is still reconnecting. Retry audio without restarting the stream."

    init(handoffPublisher: SportsHandoffPublisher? = nil,
         lastLiveStore: LastLiveMatchStore? = nil,
         captureWebAudioRevocation: @escaping @MainActor (LivePlayerViewModel) -> (@MainActor () async -> Bool)? = {
        $0.captureWebAudioRevocationWaiter()
    },
         makeModel: @escaping @MainActor (EventReference, [StreamSession]) -> LivePlayerViewModel = {
        LivePlayerViewModel(event: $0, providedSessions: $1, ownsRemoteCommands: false)
    }, resolvePlayback: @escaping @MainActor (StreamPlaybackRequest) async -> StreamResolutionOutcome = {
        await LiveStreamResolver.shared.resolvePlayback(for: $0)
    }, discoverSinglePlayback: @escaping SingleDiscovery = { request, publish in
        await LiveStreamResolver.shared.resolvePlayback(for: request, onChoices: publish)
    }, rediscoverSinglePlayback: @escaping SingleDiscovery = { request, publish in
        await LiveStreamResolver.shared.resolvePlayback(for: request, onChoices: publish,
            refreshOptionalSources: true)
    }, currentSingleEvent: @escaping @MainActor (EventReference) -> EventReference? = { event in
        // Read the already-owned admission registry, including accepted
        // terminal facts and conflict tombstones. A
        // source snapshot must not start another network refresh inside the
        // common discovery clock. Absence alone is not a terminal fact.
        guard let current = CurrentEventBroadcastPolicy.currentEvent(for: event,
            in: MatchListViewModel.shared.playbackAdmissionCatalog) else { return nil }
        let status = MatchStartPolicy.currentStatus(for: current, scores: LiveScoreService.shared)
        return MatchStartPolicy(event: current, status: status).timingAllowsPlayback ? current : nil
    }, catalogEvent: @escaping @MainActor (StreamPlaybackRequest) async -> EventReference? = { _ in
        nil // No production catalog since the shared catalog closed; tests may inject one.
    }, cancelPlayback: @escaping @MainActor (StreamPlaybackRequest) async -> Void = {
        LiveStreamResolver.shared.cancelAttempt(for: $0)
    }) {
        self.handoffPublisher = handoffPublisher ?? SportsHandoffPublisher()
        self.lastLiveStore = lastLiveStore ?? .shared
        self.captureWebAudioRevocation = captureWebAudioRevocation
        self.makeModel = makeModel
        self.resolvePlayback = resolvePlayback
        self.discoverSinglePlayback = discoverSinglePlayback
        self.rediscoverSinglePlayback = rediscoverSinglePlayback
        self.currentSingleEvent = currentSingleEvent
        self.catalogEvent = catalogEvent
        self.cancelPlayback = cancelPlayback
    }

    var primary: Pane? { panes.first { $0.id == primaryID } }
    var isActive: Bool { !panes.isEmpty }

    /// A failed browsing lookup the tab shows inline where its "looking"
    /// panel was, instead of a modal alert. Failures behind an expanded
    /// player, and non-discovery errors, keep the shell's alert.
    struct InlineDiscoveryFailure {
        let event: EventReference
        let message: String
        let canRetry: Bool
        let canManageSources: Bool
    }

    var inlineSingleDiscoveryFailure: InlineDiscoveryFailure? {
        guard !(isActive && expanded), pendingSingleEvent == nil, resolutionMessage == nil,
              let message = resolutionError, let recovery = singleDiscoveryRecovery else { return nil }
        return .init(event: recovery.event, message: message, canRetry: recovery.retryable,
                     canManageSources: recovery.category == .noProviderAvailable)
    }

    /// Sources on the inline panel: the same owner as the alert's action.
    func manageInlineDiscoverySources() {
        guard inlineSingleDiscoveryFailure != nil, manageSingleDiscoverySources() else { return }
        showsSourceSettings = true
    }

    func dismissInlineDiscoveryFailure() {
        guard inlineSingleDiscoveryFailure != nil else { return }
        resolutionError = nil
    }

    var canRetrySingleDiscovery: Bool { singleDiscoveryRecovery?.retryable == true }
    var canManageSingleDiscoverySources: Bool { singleDiscoveryRecovery?.category == .noProviderAvailable }

    var canRetrySingleAudio: Bool {
        panes.count == 1 && primary?.id == audioID && resolutionError == Self.singleAudioTransferFailure
    }

    func retrySingleAudio() {
        guard canRetrySingleAudio, let id = primaryID else { return }
        listen(to: id)
    }

    func retrySingleDiscovery() {
        guard let recovery = singleDiscoveryRecovery, recovery.retryable else { return }
        resolutionError = nil
        guard isCurrentSingleRetryOwner() else { cancelResolution(); return }
        if let retryOptionalLookup = recovery.retryOptionalLookup {
            retryOptionalLookup()
            return
        }
        if let pane = primary, panes.count == 1, pane.model.error != nil,
           Self.canReuse(pane.event, for: recovery.event) {
            _ = retrySinglePlaybackDiscovery(for: pane.model)
            return
        }
        // Retry the exact request through the normal current-identity and
        // generation fences. A failure never grants a stored stream replay.
        watchSingle(recovery.event, freshDiscovery: true)
    }

    /// An explicit Retry on an exhausted single player owns a new bounded
    /// discovery. Keep the failed surface until fresh admitted choices arrive;
    /// the same identity, generation and cancellation checks still own mounting.
    @discardableResult
    func retrySinglePlaybackDiscovery(for model: LivePlayerViewModel) -> Bool {
        guard panes.count == 1, let pane = primary, pane.model === model,
              model.viewingPlaybackContext == .single, !model.isPlaybackSessionRetired,
              model.error != nil, !model.isPictureInPictureActive,
              !model.isWebPictureInPictureActive, model.nativeFullscreen == nil else { return false }
        if singlePlaybackRetryOwner?.paneID == pane.id, singleSourceDiscoveryGeneration != nil,
           singleSourceDiscoveryEventID == model.event.id { return true }
        let ticket = SinglePlaybackRetryOwner(paneID: pane.id,
            attemptID: model.loadRequestID, intentID: model.playbackIntentRevision)
        watchSingle(model.event, freshDiscovery: true)
        singlePlaybackRetryOwner = ticket
        return true
    }

    func singlePlaybackRetryMessage(for model: LivePlayerViewModel) -> String? {
        guard panes.count == 1, primary?.model === model, model.error != nil,
              singleSourceDiscoveryGeneration != nil, singlePlaybackRetryOwner?.paneID == primaryID,
              pendingSingleEvent?.id == model.event.id else { return nil }
        return resolutionMessage
    }

    func cancelSinglePlaybackRetry(for model: LivePlayerViewModel) {
        guard primary?.model === model, singlePlaybackRetryOwner?.paneID == primaryID else { return }
        cancelPendingSingleDiscovery()
    }

    private func isCurrentSingleRetryOwner() -> Bool {
        guard let owner = singlePlaybackRetryOwner else { return true }
        // Once the new pane mounts, the existing single discovery owns its
        // append-only alternatives. Before that, manual/lifecycle intent wins.
        if singleSourceDiscoveryPaneID != nil { return true }
        guard panes.count == 1, let pane = primary, pane.id == owner.paneID else { return false }
        let model = pane.model
        return model.viewingPlaybackContext == .single && !model.isPlaybackSessionRetired
            && !model.isAppBackgrounded && model.error != nil
            && model.loadRequestID == owner.attemptID && model.playbackIntentRevision == owner.intentID
    }

    /// The shell opens existing settings only after consuming this alert.
    /// Source enablement and subsequent Watch remain explicit user actions.
    func manageSingleDiscoverySources() -> Bool {
        guard canManageSingleDiscoverySources else { return false }
        resolutionError = nil
        return true
    }

    /// Returning to one retained match is presentation, not another discovery
    /// request. Current catalog identity/terminal facts still veto stale rows.
    @discardableResult
    func reopenRetainedSingle(event: EventReference, catalog: [EventReference],
                              status: FootballMatch.MatchStatus? = nil, now: Date = Date()) -> Bool {
        guard panes.count == 1, let pane = primary,
              !pane.model.isPlaybackSessionRetired, pane.model.viewingPlaybackContext == .single,
              pane.model.error == nil, pane.model.activeSource != nil,
              !event.hasCatalogIdentityConflict,
              let current = CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: event), in: catalog)
                ?? CricketChannelCatalog.canonicalEvent(for: event, in: catalog),
              Self.canReuse(pane.event, for: current), Self.canReuse(current, for: event),
              MatchStartPolicy(event: current, now: now, status: status).timingAllowsPlayback,
              !MatchStartPolicy(event: pane.event, now: now).isStopped else { return false }
        switch pane.model.playbackState {
        case .playing, .paused, .recovering: break
        case .idle, .connecting, .preparingNativeHandoff, .failed: return false
        }
        if let item = pane.model.player?.currentItem, item.status == .failed { return false }
        cancelResolution()
        resolutionError = nil
        expanded = true
        return true
    }

    func open(event: EventReference, sessions: [StreamSession]) {
        openSingle(event: event, sessions: sessions, preservingResolution: false)
    }

    private func openSingle(event: EventReference, sessions: [StreamSession], preservingResolution: Bool, watchID: UUID? = nil) {
        guard !sessions.isEmpty, !event.hasCatalogIdentityConflict,
              !MatchStartPolicy(event: event).isStopped else { return }
        resolutionError = nil
        if !preservingResolution { cancelResolution() }
        if !preservingResolution, let existing = panes.first(where: {
            Self.canReuse($0.event, for: event)
                && (panes.count != 1 || Self.canRetainPreparedSingleOwner($0.model))
        }) {
            keepOnly(existing.id)
            expanded = true
            return
        }
        retirePlayback(preservingResolution: preservingResolution)
        let pane = Pane(id: UUID(), model: makeModel(event, sessions))
        if let watchID { pane.model.bindSingleWatchDiagnostics(watchID) }
        pane.model.configureSingleStreamRanking()
        pane.model.setViewingAudioEnabled(false)
        pane.model.setViewingDiagnosticRoute(.single)
        panes = [pane]; primaryID = pane.id; expanded = true
        MatchNavigationStore.shared.livePlayerDidAppear(matchID: event.id)
        listen(to: pane.id)
        beginLastLiveCapture(for: pane)
    }

    /// Observes only the normal single owner. It never issues media commands,
    /// resolves sources or records a prepared-but-unplayed selection.
    private func beginLastLiveCapture(for pane: Pane) {
        cancelLastLiveCapture()
        let generation = lastLiveCaptureGeneration
        observeLastLiveCapture(for: pane, generation: generation)
    }

    private func cancelLastLiveCapture() {
        lastLiveCaptureGeneration = UUID()
        if let ticket = lastLiveCaptureTicket { lastLiveStore.cancelPlayback(ticket) }
        lastLiveCaptureTicket = nil
        lastLiveCaptureBegan = false
    }

    private func observeLastLiveCapture(for pane: Pane, generation: UUID) {
        guard generation == lastLiveCaptureGeneration else { return }
        guard panes.count == 1, primaryID == pane.id, primary?.model === pane.model,
              pane.model.viewingPlaybackContext == .single,
              !pane.model.isPlaybackSessionRetired else {
            cancelLastLiveCapture()
            return
        }
        if !lastLiveStore.isEnabled {
            if let ticket = lastLiveCaptureTicket { lastLiveStore.cancelPlayback(ticket) }
            lastLiveCaptureTicket = nil
            lastLiveCaptureBegan = false
        } else if !lastLiveCaptureBegan {
            lastLiveCaptureTicket = lastLiveStore.beginPlayback(of: pane.event)
            lastLiveCaptureBegan = true
        }
        if pane.model.hasConfirmedSinglePlayback, let ticket = lastLiveCaptureTicket {
            _ = lastLiveStore.confirmDecodedPlayback(ticket)
            // A cleared or consumed ticket cannot be recreated by an ordinary
            // render, source retry or presentation transition in this session.
            lastLiveCaptureTicket = nil
        }
        let paneID = pane.id
        withObservationTracking {
            _ = self.lastLiveStore.isEnabled
            _ = self.panes.count
            _ = self.primaryID
            _ = pane.model.viewingPlaybackContext
            _ = pane.model.isPlaybackSessionRetired
            _ = pane.model.hasConfirmedSinglePlayback
        } onChange: { [weak self, weak model = pane.model] in
            Task { @MainActor in
                guard let self, let model, self.lastLiveCaptureGeneration == generation,
                      let current = self.panes.first(where: { $0.id == paneID && $0.model === model }) else { return }
                self.observeLastLiveCapture(for: current, generation: generation)
            }
        }
    }

    /// Fresh choices may preserve a healthy single owner, including paused or
    /// in-flight playback, but must not reopen a failed/retired one and discard
    /// the newly resolved delivery. Pair reuse and fixture identity are separate.
    private static func canRetainPreparedSingleOwner(_ model: LivePlayerViewModel) -> Bool {
        !model.isPlaybackSessionRetired && model.error == nil
            && model.playbackState != .failed && model.activeSource != nil
            && model.player?.currentItem?.status != .failed
    }

    func minimize() { guard isActive else { return }; expanded = false }
    func expand() {
        guard isActive else { return }
        // An inline failure belongs to the browsing screen; it must not
        // reappear as an alert over the player being returned to.
        dismissInlineDiscoveryFailure()
        expanded = true
    }

    static func canReuse(_ retained: EventReference, for requested: EventReference) -> Bool {
        guard retained.id == requested.id,
              retained.competitionID == requested.competitionID,
              SportsHandoffIdentity.qualifiers(for: retained) == SportsHandoffIdentity.qualifiers(for: requested)
        else { return false }
        return CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: requested), in: [retained]) != nil
    }

    func listen(to id: UUID) {
        guard panes.contains(where: { $0.id == id }) else { return }
        guard !panes.contains(where: { $0.id != id && ($0.model.isPictureInPictureActive || $0.model.isWebPictureInPictureActive) }) else {
            resolutionError = "Stop Picture in Picture before moving audio to the other match."
            return
        }
        let retainsAudibleOwner = audioID == id && panes.first(where: { $0.id == id })?.model.isViewingAudioEnabled == true
        cancelAudioTransfer()
        // Revoke first. A native platform reconnect is not cancellable, so Web
        // audibility must wait until that exact player has really disconnected.
        for pane in panes {
            pane.model.setRemoteCommandOwnership(false)
            // Retaining the same audible pane is not a new focus claim. Revoke
            // only siblings, before claiming a genuinely different target.
            if pane.id != id {
                revokeAudio(of: pane)
                pane.model.setViewingPiPOwnership(false)
            }
        }
        audioID = id
        guard let selected = panes.first(where: { $0.id == id }) else { return }
        if retainsAudibleOwner { promoteAudio(selected); return }
        var barriers: [NativePlayerAudioIsolation.Barrier] = []
        for previous in Array(audioRetirements.values) {
            let barrier = previous.renewedDisconnection()
            if barrier.isSatisfied { audioRetirements.removeValue(forKey: barrier.identity) }
            else { audioRetirements[barrier.identity] = barrier; barriers.append(barrier) }
        }
        let webBarriers = Array(webAudioRetirements)
        guard !barriers.isEmpty || !webBarriers.isEmpty else { promoteAudio(selected); return }
        selected.model.setViewingAudioEnabled(false)
        selected.model.setViewingPiPOwnership(false)
        let generation = audioTransferGeneration
        audioTransferTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.audioTransferGeneration == generation { self.audioTransferTask = nil } }
            for (identity, barrier) in webBarriers {
                let muted = await barrier.wait()
                guard !Task.isCancelled, self.audioTransferGeneration == generation else { return }
                guard muted else {
                    self.recordSingleAudioTransfer(selected, result: "web_retirement_timeout", outcome: .failure)
                    self.resolutionError = Self.singleAudioTransferFailure
                    return
                }
                if self.webAudioRetirements[identity]?.revision == barrier.revision {
                    self.webAudioRetirements.removeValue(forKey: identity)
                }
            }
            for barrier in barriers {
                let disconnected = await barrier.wait()
                guard !Task.isCancelled, self.audioTransferGeneration == generation else { return }
                guard disconnected else {
                    self.recordSingleAudioTransfer(selected, result: "native_retirement_failed", outcome: .failure)
                    self.resolutionError = Self.singleAudioTransferFailure
                    return
                }
                if self.audioRetirements[barrier.identity]?.revision == barrier.revision {
                    self.audioRetirements.removeValue(forKey: barrier.identity)
                }
            }
            guard !Task.isCancelled, self.audioTransferGeneration == generation, self.audioID == id,
                  self.panes.contains(where: { $0.id == id && $0.model === selected.model }),
                  !selected.model.isPlaybackSessionRetired else { return }
            self.promoteAudio(selected)
        }
    }

    private func recordSingleAudioTransfer(_ pane: Pane, result: String, outcome: FottyQualityOutcome) {
        guard panes.count == 1, pane.model.viewingPlaybackContext == .single else { return }
        FottyQualityStore.shared.record(category: .playback, name: "single_audio_transfer", outcome: outcome,
            details: pane.model.playbackQualityDetails(["result": result,
                "audio_enabled": String(pane.model.isViewingAudioEnabled)]))
    }

    private func promoteAudio(_ pane: Pane) {
        if resolutionError == Self.singleAudioTransferFailure {
            resolutionError = nil
        }
        let wasEnabled = pane.model.isViewingAudioEnabled
        pane.model.setViewingPiPOwnership(true)
        pane.model.setViewingAudioEnabled(true)
        pane.model.setRemoteCommandOwnership(true)
        if !wasEnabled { recordSingleAudioTransfer(pane, result: "enabled", outcome: .success) }
    }

    private func cancelAudioTransfer() {
        audioTransferGeneration = UUID()
        audioTransferTask?.cancel()
        audioTransferTask = nil
    }

    private func rememberAudioRetirement(_ barrier: NativePlayerAudioIsolation.Barrier?) {
        guard let barrier else { return }
        if barrier.isSatisfied { audioRetirements.removeValue(forKey: barrier.identity); return }
        audioRetirements[barrier.identity] = barrier
        Task { [weak self] in
            guard await barrier.wait(), let self,
                  self.audioRetirements[barrier.identity]?.revision == barrier.revision else { return }
            self.audioRetirements.removeValue(forKey: barrier.identity)
        }
    }

    private func revokeAudio(of pane: Pane) {
        if pane.model.viewingPlaybackContext == .single {
            pane.model.onSingleWebAudioRetired = { [weak self] in
                guard let self, self.panes.count == 1, self.audioTransferTask == nil,
                      let current = self.primary, self.audioID == current.id,
                      !current.model.isViewingAudioEnabled, !current.model.isPlaybackSessionRetired else { return }
                // A timeout is not permission to unmute. An actual late teardown
                // ACK can safely retry the same focus claim without a new stream.
                self.listen(to: current.id)
            }
        }
        rememberAudioRetirement(pane.model.revokeViewingAudioForTransfer())
        if let wait = captureWebAudioRevocation(pane.model) {
            webAudioRetirements[pane.model.remoteCommandOwnerID] = WebAudioRetirement(wait: wait)
        }
    }

    /// Provider PiP is an explicit action on that pane. Wait for the system's
    /// old-pane stop callback instead of guessing between two transient claims.
    func reconcilePictureInPictureOwnership() {
        let active = panes.filter { $0.model.isPictureInPictureActive || $0.model.isWebPictureInPictureActive }
        guard active.count == 1, let pane = active.first, pane.id != audioID else { return }
        listen(to: pane.id)
    }

    func keepOnly(_ id: UUID) {
        guard let survivor = panes.first(where: { $0.id == id }) else { return }
        resolutionError = nil
        cancelResolution()
        if primaryID != id { handoffPublisher.stop() }
        for pane in panes where pane.id != id {
            revokeAudio(of: pane)
            pane.model.cleanup()
        }
        panes = [survivor]; primaryID = id; expanded = true
        survivor.model.setViewingDiagnosticRoute(.single)
        MatchNavigationStore.shared.livePlayerDidAppear(matchID: survivor.event.id)
        listen(to: id)
    }

    func stop() {
        if singleDiscoveryRecovery != nil { resolutionError = nil }
        retirePlayback(preservingResolution: false)
    }

    private func retirePlayback(preservingResolution: Bool) {
        cancelLastLiveCapture()
        if !preservingResolution { cancelResolution() }
        cancelAudioTransfer()
        if let primary {
            MatchNavigationStore.shared.livePlayerDidDisappear(matchID: primary.event.id)
            FottyLiveActivityController.shared.end(event: primary.event, scoreText: nil)
        }
        for pane in panes {
            revokeAudio(of: pane)
            pane.model.cleanup()
        }
        panes = []; primaryID = nil; audioID = nil
        showsContinuity = false
        handoffPublisher.stop()
    }

    func watchIncoming() {
        guard let event = incomingEvent else { return }
        incomingEvent = nil; incomingHandoff = nil
        resolve(event: event)
    }

    /// Scene-owned single discovery survives the browsing view being covered.
    /// First admitted choices mount once; subsequent choices only append. All
    /// updates remain fenced by one resolution generation and the exact pane.
    func watchSingle(_ event: EventReference,
                     freshDiscovery: Bool = false,
                     admission: (@MainActor (EventReference) -> EventReference?)? = nil) {
        if !freshDiscovery, singleSourceDiscoveryGeneration != nil,
           singleSourceDiscoveryPaneID == nil, singleSourceDiscoveryEventID == event.id { return }
        cancelResolution()
        let generation = UUID()
        resolutionGeneration = generation
        WatchOutcomeRecorder.shared.begin(watchID: generation, event: event)
        singleSourceDiscoveryGeneration = generation
        singleSourceDiscoveryEventID = event.id
        pendingSingleEvent = event
        resolutionMessage = "Finding a broadcast…"
        resolutionError = nil
        resolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.resolutionGeneration == generation {
                    if let pane = self.panes.first(where: { $0.id == self.singleSourceDiscoveryPaneID }) {
                        pane.model.setSingleSourceDiscoveryActive(false)
                    }
                    self.singleSourceDiscoveryGeneration = nil
                    self.singleSourceDiscoveryPaneID = nil
                    self.singleSourceDiscoveryEventID = nil
                    self.pendingSingleEvent = nil
                    self.resolutionMessage = nil
                    self.activeRequest = nil
                    self.resolveTask = nil
                }
            }
            do { try await StreamResolutionPresentation.waitForFeedbackFrame() } catch { return }
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            FottyQualityStore.shared.record(category: .playback, name: "watch_requested", outcome: .info,
                details: ["watch_session_id": generation.uuidString, "route": "single"])
            guard self.isCurrentSingleRetryOwner() else { self.cancelResolution(); return }
            // Reserve visible feedback before caller-owned catalog selection or
            // retained-player matching. Those main-actor checks can scan the
            // whole catalog; none may run ahead of the acknowledgement frame.
            let requested: EventReference
            if let admission {
                let admitted = admission(event)
                guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
                guard let admitted else {
                    self.resolutionError = "This broadcast changed or is no longer available. Refresh the lineup before watching."
                    WatchOutcomeRecorder.shared.finish(watchID: generation, .failed, failureKind: "fixture_changed")
                    return
                }
                requested = admitted
            } else { requested = event }
            let matched = self.currentSingleEvent(requested)
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            guard let matched else {
                self.resolutionError = "This broadcast changed or is no longer available. Refresh the lineup before watching."
                WatchOutcomeRecorder.shared.finish(watchID: generation, .failed, failureKind: "fixture_changed")
                return
            }
            guard !Task.isCancelled, self.resolutionGeneration == generation,
                  Self.canReuse(requested, for: matched),
                  !matched.hasCatalogIdentityConflict,
                  MatchStartPolicy(event: matched).timingAllowsPlayback else {
                if !Task.isCancelled, self.resolutionGeneration == generation {
                    self.resolutionError = "This broadcast is no longer ready to watch. Refresh the lineup before watching."
                    WatchOutcomeRecorder.shared.finish(watchID: generation, .failed, failureKind: "fixture_not_ready")
                }
                return
            }
            if admission != nil, !freshDiscovery, self.reopenRetainedSingle(event: matched, catalog: [matched]) {
                self.recordRetainedWatch(generation)
                return
            }
            let request = StreamPlaybackRequest(event: matched, watchID: generation)
            self.pendingSingleEvent = matched
            self.activeRequest = request
            guard self.isCurrentSingleRetryOwner() else { self.cancelResolution(); return }
            let lookup = freshDiscovery ? self.rediscoverSinglePlayback : self.discoverSinglePlayback
            let result = await lookup(request) { [weak self] sessions in
                await self?.acceptSingleChoices(sessions, event: matched, generation: generation)
            }
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            guard self.isCurrentSingleRetryOwner() else { self.cancelResolution(); return }
            switch result {
            case .success(let success):
                await self.acceptSingleChoices(success.sessions, event: matched, generation: generation)
                guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
                if self.singleSourceDiscoveryPaneID == nil {
                    self.resolutionError = matched.isBroadcastChannel
                        ? "No supported stream is available for this channel right now."
                        : LiveStreamResolver.noPlayableMatchMessage
                    self.singleDiscoveryRecovery = .init(event: matched, category: .providerReturnedEmpty, retryable: true)
                    MatchPlaybackFeedback.shared.notReady(event.id)
                    WatchOutcomeRecorder.shared.finish(watchID: generation, .noStreamFound, failureKind: "no_admitted_stream")
                }
            case .failure(let failure, let diagnostics):
                // An unrelated slow/failed lane cannot interrupt a source that
                // was already admitted. Diagnostics still record the failure.
                guard !Self.cancelledDiscovery.contains(failure.category) else {
                    if self.singleSourceDiscoveryPaneID == nil {
                        WatchOutcomeRecorder.shared.finish(watchID: generation, resolutionFailure: failure.category)
                    }
                    return
                }
                if self.singleSourceDiscoveryPaneID == nil {
                    WatchOutcomeRecorder.shared.finish(watchID: generation, resolutionFailure: failure.category)
                    self.resolutionError = failure.userMessage
                    self.singleDiscoveryRecovery = .init(event: matched, category: failure.category,
                        retryable: failure.retryable)
                    MatchPlaybackFeedback.shared.notReady(event.id)
                    FottyQualityStore.shared.record(category: .playback, name: "resolution_failure", outcome: .failure,
                        details: ["route": "single", "mode": "resolution", "attempt_id": diagnostics.attemptID,
                                  "watch_session_id": generation.uuidString, "failure_kind": failure.category.rawValue])
                }
            }
        }
    }

    private func acceptSingleChoices(_ sessions: [StreamSession], event: EventReference, generation: UUID) async {
        guard !Task.isCancelled, resolutionGeneration == generation,
              singleSourceDiscoveryGeneration == generation,
              !event.hasCatalogIdentityConflict, MatchStartPolicy(event: event).timingAllowsPlayback else { return }
        guard isCurrentSingleRetryOwner() else { cancelResolution(); return }
        let admitted = sessions.filter { $0.matchID == event.id && StreamPluginProviderMatching.isActivePlayerSession($0) }
        guard !admitted.isEmpty else { return }
        // Current catalog facts still veto a late corrected, terminal or
        // quarantined fixture, without starting a second catalog request or
        // extending the owned discovery clock.
        guard let current = currentSingleEvent(event) else { return }
        guard !Task.isCancelled, resolutionGeneration == generation,
              singleSourceDiscoveryGeneration == generation,
              Self.canReuse(event, for: current), event.kickoffDate == current.kickoffDate,
              !current.hasCatalogIdentityConflict,
              MatchStartPolicy(event: current).timingAllowsPlayback else { return }
        if let id = singleSourceDiscoveryPaneID {
            guard panes.count == 1, let pane = panes.first(where: { $0.id == id }),
                  Self.canReuse(pane.event, for: event) else { return }
            pane.model.appendDiscoveredSingleSessions(admitted, currentEvent: current)
        } else {
            openSingle(event: current, sessions: admitted, preservingResolution: true, watchID: generation)
            guard panes.count == 1, let pane = primary, Self.canReuse(pane.event, for: event) else { return }
            singleSourceDiscoveryPaneID = pane.id
            pane.model.setSingleSourceDiscoveryActive(true)
            resolutionMessage = nil
            pendingSingleEvent = nil
        }
    }

    /// Leaving a browsing destination can cancel an unpresented lookup. Once
    /// playback mounts, its remaining alternatives belong to the scene, not the
    /// tab's appearance callbacks.
    func cancelPendingSingleDiscovery() {
        guard singleSourceDiscoveryGeneration != nil, singleSourceDiscoveryPaneID == nil else { return }
        cancelResolution()
    }

    /// Explicitly check an accepted official fixture without pretending that a
    /// primary broadcast is already listed. The caller supplies the shared
    /// opt-in/freshness policy over its current catalog before and after lookup.
    /// Do not put a primary-catalog preflight ahead of independent source lanes.
    @discardableResult
    func checkOptionalSources(
        for event: EventReference,
        enabledProviders: @escaping @MainActor () -> Set<String> = { FixtureStreamDiscoveryIndex.shared.enabledProviderCodes },
        discover: SingleDiscovery? = nil,
        currentEvent: @escaping @MainActor (EventReference, OptionalSourceLookupPolicy.Phase) async -> EventReference?
    ) -> Bool {
        guard resolutionMessage == nil, optionalSourceLookupGeneration == nil else { return false }
        cancelResolution()
        let generation = UUID()
        resolutionGeneration = generation
        WatchOutcomeRecorder.shared.begin(watchID: generation, event: event)
        optionalSourceLookupGeneration = generation
        pendingSingleEvent = event
        resolutionMessage = "Finding a broadcast…"
        resolutionError = nil
        MatchPlaybackFeedback.shared.attempting(event.id)
        resolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.resolutionGeneration == generation {
                    if let pane = self.panes.first(where: { $0.id == self.optionalSourceLookupPaneID }) {
                        pane.model.setSingleSourceDiscoveryActive(false)
                    }
                    self.resolutionMessage = nil
                    self.pendingSingleEvent = nil
                    self.activeRequest = nil
                    self.resolveTask = nil
                    self.optionalSourceLookupGeneration = nil
                    self.optionalSourceLookupPaneID = nil
                }
            }
            do { try await StreamResolutionPresentation.waitForFeedbackFrame() }
            catch { return }
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            FottyQualityStore.shared.record(category: .playback, name: "watch_requested", outcome: .info,
                details: ["watch_session_id": generation.uuidString, "route": "optional_single"])
            guard let admitted = await currentEvent(event, .offer),
                  Self.canReuse(event, for: admitted), event.kickoffDate == admitted.kickoffDate,
                  !admitted.hasCatalogIdentityConflict, !MatchStartPolicy(event: admitted).isStopped else {
                guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
                self.resolutionError = "This fixture could not be confirmed. Refresh the lineup before watching."
                WatchOutcomeRecorder.shared.finish(watchID: generation, .failed, failureKind: "fixture_changed")
                return
            }
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            if self.reopenRetainedSingle(event: admitted, catalog: [admitted]) {
                self.recordRetainedWatch(generation)
                return
            }
            let request = StreamPlaybackRequest(event: admitted, watchID: generation)
            self.activeRequest = request
            self.pendingSingleEvent = admitted
            let outcome: StreamResolutionOutcome
            if let discover {
                outcome = await discover(request) { [weak self] sessions in
                    _ = await self?.acceptOptionalSourceChoices(sessions, event: admitted,
                        generation: generation, enabledProviders: enabledProviders, currentEvent: currentEvent)
                }
            } else {
                outcome = await self.resolvePlayback(request)
            }
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            // A retry stays on the same official fixture and rechecks the
            // originating screen, current source opt-ins, and eligibility.
            let retryLookup: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                self.checkOptionalSources(for: admitted, enabledProviders: enabledProviders,
                    discover: self.rediscoverSinglePlayback, currentEvent: currentEvent)
            }
            switch outcome {
            case .success(let result):
                let acceptance = await self.acceptOptionalSourceChoices(result.sessions, event: admitted,
                    generation: generation, enabledProviders: enabledProviders, currentEvent: currentEvent)
                guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
                if self.optionalSourceLookupPaneID == nil {
                    self.resolutionError = acceptance == .changed
                        ? "This fixture changed. Refresh the lineup before watching."
                        : LiveStreamResolver.noPlayableMatchMessage
                    if acceptance == .changed {
                        WatchOutcomeRecorder.shared.finish(watchID: generation, .failed, failureKind: "fixture_changed")
                    } else {
                        self.singleDiscoveryRecovery = .init(event: admitted, category: .providerReturnedEmpty,
                            retryable: true, retryOptionalLookup: retryLookup)
                        MatchPlaybackFeedback.shared.notReady(event.id)
                        WatchOutcomeRecorder.shared.finish(watchID: generation, .noStreamFound, failureKind: "no_admitted_stream")
                    }
                }
            case .failure(let failure, let diagnostic):
                if self.optionalSourceLookupPaneID == nil {
                    guard !Self.cancelledDiscovery.contains(failure.category) else {
                        WatchOutcomeRecorder.shared.finish(watchID: generation, resolutionFailure: failure.category)
                        return
                    }
                    self.resolutionError = failure.userMessage
                    self.singleDiscoveryRecovery = .init(event: admitted, category: failure.category,
                        retryable: failure.retryable, retryOptionalLookup: failure.retryable ? retryLookup : nil)
                    MatchPlaybackFeedback.shared.notReady(event.id)
                    WatchOutcomeRecorder.shared.finish(watchID: generation, resolutionFailure: failure.category)
                    FottyQualityStore.shared.record(category: .playback, name: "resolution_failure", outcome: .failure,
                        details: ["watch_session_id": generation.uuidString, "attempt_id": diagnostic.attemptID,
                                  "route": "optional_single", "failure_kind": failure.category.rawValue])
                }
            }
        }
        return true
    }

    /// Reopening existing video links this tap to its current attempt without replacing the owner.
    private func recordRetainedWatch(_ watchID: UUID) {
        guard let model = primary?.model else { return }
        // The tap reopened a picture this scene already owns.
        WatchOutcomeRecorder.shared.finish(watchID: watchID, model.didStartPlayback ? .playing : .cancelled,
            family: WatchOutcomeRecorder.family(for: model.activeSource))
        var details = model.playbackQualityDetails()
        details["watch_session_id"] = watchID.uuidString
        FottyQualityStore.shared.record(category: .playback, name: "watch_reopened_existing_attempt", outcome: .success, details: details)
    }

    private enum OptionalSourceAcceptance: Equatable { case accepted, empty, changed }

    private func acceptOptionalSourceChoices(
        _ sessions: [StreamSession], event: EventReference, generation: UUID,
        enabledProviders: @escaping @MainActor () -> Set<String>,
        currentEvent: @escaping @MainActor (EventReference, OptionalSourceLookupPolicy.Phase) async -> EventReference?
    ) async -> OptionalSourceAcceptance {
        guard !Task.isCancelled, resolutionGeneration == generation,
              optionalSourceLookupGeneration == generation else { return .changed }
        guard let latest = await currentEvent(event, .completion),
              Self.canReuse(event, for: latest), event.kickoffDate == latest.kickoffDate,
              !latest.hasCatalogIdentityConflict, !MatchStartPolicy(event: latest).isStopped else { return .changed }
        guard !Task.isCancelled, resolutionGeneration == generation,
              optionalSourceLookupGeneration == generation else { return .changed }
        // Read the latest local enablement after the async admission check.
        // No suspension may separate this filter from mounting/appending.
        let enabled = Set(enabledProviders().compactMap {
            CuratedStreamSourceCatalog.definition(forProviderCode: $0)?.providerCode
        })
        let admitted = sessions.filter { session in
            session.matchID == event.id && StreamPluginProviderMatching.isActivePlayerSession(session)
                && enabled.contains { StreamPluginProviderMatching.matches(session.legacySource, code: $0) }
        }
        guard !admitted.isEmpty else { return .empty }
        if let id = optionalSourceLookupPaneID {
            guard panes.count == 1, let pane = primary, pane.id == id,
                  Self.canReuse(pane.event, for: latest) else { return .changed }
            pane.model.appendDiscoveredSingleSessions(admitted, currentEvent: latest)
        } else {
            openSingle(event: latest, sessions: admitted, preservingResolution: true, watchID: generation)
            guard panes.count == 1, let pane = primary, Self.canReuse(pane.event, for: latest) else { return .changed }
            optionalSourceLookupPaneID = pane.id
            pane.model.setSingleSourceDiscoveryActive(true)
            resolutionMessage = nil
            pendingSingleEvent = nil
        }
        return .accepted
    }

    /// Navigation may cancel this optional check without touching a retained
    /// player or another resolution route.
    func cancelOptionalSourceLookup() {
        guard optionalSourceLookupGeneration != nil, optionalSourceLookupPaneID == nil else { return }
        cancelResolution()
    }

    /// Only this lookup's mounted single owner may outlive its originating
    /// browsing tab. An unrelated retained player never grants that lifetime.
    func hasMountedOptionalSourceLookup(for event: EventReference) -> Bool {
        guard let generation = optionalSourceLookupGeneration, generation == resolutionGeneration,
              let id = optionalSourceLookupPaneID, panes.count == 1, let pane = primary, pane.id == id,
              !pane.model.isPlaybackSessionRetired, pane.event.kickoffDate == event.kickoffDate,
              Self.canReuse(pane.event, for: event) else { return false }
        return true
    }

    func receiveHandoff(_ activity: NSUserActivity) async {
        do {
            let identity = try SportsHandoffIdentity.decode(activity: activity)
            let catalog = MatchListViewModel.shared
            await catalog.refresh()
            guard let receipt = catalog.scheduleReceipt(category: identity.category, matchID: identity.eventID),
                  let event = SportsHandoffMatchPolicy.confirmationEvent(for: identity,
                    in: catalog.playbackCatalog, scheduleCheckedAt: receipt) else {
                resolutionError = "That match could not be confirmed in the current schedule. Your current viewing is unchanged."
                return
            }
            incomingHandoff = identity; incomingEvent = event
        } catch { resolutionError = "This viewing offer has expired or is not supported." }
    }

    private func resolve(event: EventReference) {
        cancelResolution()
        let generation = UUID(); resolutionGeneration = generation
        let request = StreamPlaybackRequest(event: event)
        activeRequest = request; resolutionMessage = "Finding a broadcast…"; resolutionError = nil
        resolveTask = Task { [weak self] in
            guard let self else { return }
            let matched = await self.catalogEvent(request) ?? event
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            let outcome = await self.resolvePlayback(request)
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            self.resolutionMessage = nil; self.activeRequest = nil
            switch outcome {
            case .success(let result):
                guard !result.sessions.isEmpty else { self.resolutionError = "No broadcast is available yet."; return }
                let currentEvent = await self.catalogEvent(request) ?? matched
                guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
                guard !currentEvent.hasCatalogIdentityConflict, !MatchStartPolicy(event: currentEvent).isStopped else {
                    self.resolutionError = "This fixture is no longer available to watch. Your current viewing is unchanged."
                    return
                }
                self.open(event: currentEvent, sessions: result.sessions)
            case .failure(let failure, _): self.resolutionError = failure.userMessage
            }
        }
    }

    func cancelResolution() {
        // Before a player mounts, this coordinator owns the tap's outcome.
        // A mounted player reports its own picture, failure or cancellation.
        if singleSourceDiscoveryPaneID == nil, optionalSourceLookupPaneID == nil {
            WatchOutcomeRecorder.shared.finish(watchID: resolutionGeneration, .cancelled)
        }
        if let pane = panes.first(where: { $0.id == optionalSourceLookupPaneID }) {
            pane.model.setSingleSourceDiscoveryActive(false, completed: false)
        }
        optionalSourceLookupPaneID = nil
        if let pane = panes.first(where: { $0.id == singleSourceDiscoveryPaneID }) {
            pane.model.setSingleSourceDiscoveryActive(false, completed: false)
        }
        singleSourceDiscoveryGeneration = nil
        singleSourceDiscoveryPaneID = nil
        singleSourceDiscoveryEventID = nil
        singlePlaybackRetryOwner = nil
        pendingSingleEvent = nil
        resolutionGeneration = UUID(); resolveTask?.cancel(); resolveTask = nil
        optionalSourceLookupGeneration = nil
        resolutionMessage = nil
        if let request = activeRequest { Task { await cancelPlayback(request) } }
        activeRequest = nil
    }
}

enum ViewingExperienceLayout {
    static func usesCompanion(width: CGFloat, accessibility: Bool) -> Bool { width >= 820 && !accessibility }

    /// Wide windows show info beside the picture; narrower ones use a sheet.
    static func usesInfoPanel(width: CGFloat, accessibility: Bool) -> Bool { width >= 900 && !accessibility }

    /// The stage has already excluded safe areas and the control dock. Fit both
    /// axes without reserving an unrequested inspector or cropping the programme.
    static func singleVideoSize(in available: CGSize) -> CGSize {
        guard available.width.isFinite, available.height.isFinite,
              available.width > 0, available.height > 0 else { return .zero }
        let aspect: CGFloat = 16.0 / 9.0
        let height = min(available.height, available.width / aspect)
        return CGSize(width: min(available.width, height * aspect), height: height)
    }
}
