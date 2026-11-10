import SwiftUI

/// One scene owns the media surfaces; destinations submit prepared choices,
/// never keep a second player alive behind a cover. Presentation is not transport.
@Observable @MainActor
final class ViewingSessionCoordinator {
    @MainActor
    struct NativeWatchTwoOperations {
        var prepare: @MainActor (LivePlayerViewModel) async -> PreparedNativeWatchTwoPlayback?
        var isCurrent: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) -> Bool
        var beginRetirement: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) -> Bool
        var waitForRetirement: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) async -> Bool
        var adopt: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) -> Bool
        var start: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) -> Void
        var discard: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) -> Void
        var releaseAudioHold: @MainActor (LivePlayerViewModel, PreparedNativeWatchTwoPlayback) -> Void

        static var live: Self {
            .init(prepare: { await $0.prepareNativeWatchTwoCandidate() },
                isCurrent: { $0.nativeWatchTwoPreparationIsCurrent($1) },
                beginRetirement: { $0.beginNativeWatchTwoRetirement($1) },
                waitForRetirement: { await $0.waitForNativeWatchTwoRetirement($1) },
                adopt: { $0.adoptNativeWatchTwoCandidate($1) },
                start: { $0.startNativeWatchTwoCandidate($1) },
                discard: { $0.discardNativeWatchTwoCandidate($1) },
                releaseAudioHold: { $0.releaseNativeWatchTwoAudioHold($1) })
        }
    }

    struct Pane: Identifiable, Sendable {
        let id: UUID
        let model: LivePlayerViewModel
        var event: EventReference { model.event }
    }

    struct SingleDiscoveryRecovery {
        let event: EventReference
        let category: StreamFailureCategory
        let retryable: Bool
    }

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
    private(set) var swapped = false
    var showsSecondMatchPicker = false
    private(set) var matchPickerReplacementID: UUID?
    var showsContinuity = false
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
    @ObservationIgnored private let nativeWatchTwo: NativeWatchTwoOperations
    @ObservationIgnored private(set) var nativePairTransferTask: Task<Void, Never>?
    @ObservationIgnored private var nativePairTransferGeneration = UUID()
    @ObservationIgnored private var nativePairRequestedAudioID: UUID?
    @ObservationIgnored private var nativePairRetirementStarted = false
    @ObservationIgnored private let makeModel: @MainActor (EventReference, [StreamSession]) -> LivePlayerViewModel
    @ObservationIgnored private let resolvePlayback: @MainActor (StreamPlaybackRequest) async -> StreamResolutionOutcome
    typealias SingleDiscovery = @MainActor (StreamPlaybackRequest, @escaping @Sendable ([StreamSession]) async -> Void) async -> StreamResolutionOutcome
    @ObservationIgnored private let discoverSinglePlayback: SingleDiscovery
    @ObservationIgnored private let rediscoverSinglePlayback: SingleDiscovery
    @ObservationIgnored private let currentSingleEvent: @MainActor (EventReference) -> EventReference?
    @ObservationIgnored private let catalogEvent: @MainActor (StreamPlaybackRequest) async -> EventReference?
    @ObservationIgnored private let cancelPlayback: @MainActor (StreamPlaybackRequest) async -> Void

    private enum ResolutionDestination {
        case single
        case second(retaining: UUID)
        case replacement(target: UUID, survivor: UUID)
    }

    private static let singleAudioTransferFailure = "Audio is still reconnecting. Retry audio without restarting the stream."
    private static let audioTransferFailure = "Audio couldn’t switch safely. Tap Audio on either match to retry."
    private static let nativePairProgress = "Switching players…"
    private static let nativePairPreparationFailure = "Both matches need native playback to switch audio. Your current streams are unchanged."
    private static let nativePairRetirementFailure = "The player switch could not finish safely. Choose a source to retry."

    init(handoffPublisher: SportsHandoffPublisher? = nil,
         lastLiveStore: LastLiveMatchStore? = nil,
         nativeWatchTwo: NativeWatchTwoOperations? = nil,
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
        self.nativeWatchTwo = nativeWatchTwo ?? .live
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
    var isTwo: Bool { panes.count == 2 }
    var displayPanes: [Pane] { swapped ? panes.reversed() : panes }

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
        cancelNativePairTransfer()
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
        pane.model.setViewingPlaybackContext(.single)
        pane.model.setViewingDiagnosticRoute(.single)
        panes = [pane]; primaryID = pane.id; expanded = true; swapped = false
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

    func openMulti(slots: [MultiLiveSlot]) {
        guard slots.count == 2, Set(slots.map(\.id)).count == 2,
              slots.allSatisfy({ !$0.sessions.isEmpty && !$0.event.hasCatalogIdentityConflict
                  && !MatchStartPolicy(event: $0.event).isStopped }) else { return }
        cancelNativePairTransfer()
        cancelResolution()
        let previous = panes
        let next = slots.map { slot in
            previous.first { Self.canReuse($0.event, for: slot.event) }
                ?? Pane(id: UUID(), model: makeModel(slot.event, slot.sessions))
        }
        guard preparePair(next, retaining: previous) else {
            for pane in next where !previous.contains(where: { $0.id == pane.id }) { pane.model.cleanup() }
            return
        }
        if primaryID != next.first?.id { handoffPublisher.stop() }
        // Revoke old media and remote ownership before a replacement is claimed.
        for pane in previous where !next.contains(where: { $0.id == pane.id }) {
            revokeAudio(of: pane)
            pane.model.cleanup()
        }
        for pane in next where !previous.contains(where: { $0.id == pane.id }) {
            pane.model.setRemoteCommandOwnership(false)
            pane.model.setViewingAudioEnabled(false)
            pane.model.setViewingPiPOwnership(false)
        }
        panes = next; primaryID = next[0].id; expanded = true; swapped = false
        for pane in next { pane.model.setViewingDiagnosticRoute(.watchTwo) }
        MatchNavigationStore.shared.livePlayerDidAppear(matchID: next[0].event.id)
        listen(to: next.contains(where: { $0.id == audioID }) ? audioID! : next[0].id)
    }

    /// Admission is decided before any retained pane changes engine or a new
    /// surface mounts. An incompatible choice is not a failing provider.
    private func preparePair(_ proposed: [Pane], retaining previous: [Pane]) -> Bool {
        let retained = proposed.filter { pane in previous.contains(where: { $0.id == pane.id }) }
        let preferred = retained.first(where: { $0.id == audioID })
            ?? retained.first(where: { $0.id == primaryID }) ?? retained.first ?? proposed.first
        guard let preferred, let engine = pairingEngine(for: preferred.model) else {
            reportIncompatiblePlayers()
            return false
        }
        let context = ViewingPlaybackContext.watchTwo(engine: engine)
        for pane in retained {
            guard pairingEngine(for: pane.model) == engine else {
                reportIncompatiblePlayers()
                return false
            }
            if pane.model.activePlaybackEngine != engine {
                // The only supported retained-engine conversion is an adopted
                // native handoff returning to its exact original Web endpoint.
                // A forced Web fallback cannot silently become native again.
                guard engine == .web, pane.model.selectedPlaybackEngine == .web,
                      pane.model.activePlaybackEngine == .native else {
                    reportIncompatiblePlayers()
                    return false
                }
                guard canChangePlaybackEngine(pane) else { return false }
            }
        }
        for pane in proposed where !retained.contains(where: { $0.id == pane.id }) {
            guard pane.model.prepareForViewingPlaybackContext(context) else {
                reportIncompatiblePlayers()
                return false
            }
        }
        // These setters may retire an adopted native handoff back to its exact
        // original Web route. Commit only after every other admission succeeds.
        for pane in retained {
            if pane.model.activePlaybackEngine != engine {
                revokeAudio(of: pane)
            }
            pane.model.setViewingPlaybackContext(context)
        }
        resolutionError = nil
        return true
    }

    private func canChangePlaybackEngine(_ pane: Pane) -> Bool {
        guard !pane.model.isPictureInPictureActive, !pane.model.isWebPictureInPictureActive,
              pane.model.nativeFullscreen == nil else {
            resolutionError = "Return from fullscreen or Picture in Picture before changing this match's player."
            return false
        }
        return true
    }

    private func pairingEngine(for model: LivePlayerViewModel) -> ViewingPlaybackEngine? {
        if model.viewingPlaybackContext == .watchTwo(engine: .native), model.activePlaybackEngine == .native {
            return .native
        }
        return model.selectedPlaybackEngine
    }

    private func reportIncompatiblePlayers() {
        resolutionError = "These broadcasts use different players. Choose another source or watch this match on its own."
    }

    func minimize() { guard isActive else { return }; expanded = false }
    func expand() { guard isActive else { return }; expanded = true }
    func swap() { guard isTwo else { return }; swapped.toggle() }

    static func canReuse(_ retained: EventReference, for requested: EventReference) -> Bool {
        guard retained.id == requested.id,
              retained.competitionID == requested.competitionID,
              SportsHandoffIdentity.qualifiers(for: retained) == SportsHandoffIdentity.qualifiers(for: requested)
        else { return false }
        return CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: requested), in: [retained]) != nil
    }

    /// Duplicate exclusion is broader than media-owner reuse. A verified
    /// canonical fixture may replace a provider ID while identifying the same
    /// dated match; that must not become the "other" match in Watch Two.
    /// This never authorizes reuse of that differently identified player.
    static func representsSameFixture(_ first: EventReference, as second: EventReference) -> Bool {
        if canReuse(first, for: second) { return true }
        guard !first.hasCatalogIdentityConflict, !second.hasCatalogIdentityConflict,
              !first.isBroadcastChannel, !second.isBroadcastChannel,
              first.normalizedCategory == second.normalizedCategory,
              SportsHandoffIdentity.qualifiers(for: first) == SportsHandoffIdentity.qualifiers(for: second),
              let firstStart = first.kickoffDate, let secondStart = second.kickoffDate,
              abs(firstStart.timeIntervalSince(secondStart)) <= CatalogPlaybackIdentity.kickoffTolerance,
              first.competitionID == nil || second.competitionID == nil || first.competitionID == second.competitionID else { return false }
        return CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: first), in: [second]) != nil
            && CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: second), in: [first]) != nil
    }

    /// The Audio button is a deliberate playback-engine transition. Scene and
    /// PiP ownership still use listen(to:) without initiating a pair restart.
    func selectAudio(to id: UUID) {
        guard panes.contains(where: { $0.id == id }) else { return }
        if nativePairTransferTask != nil {
            if nativePairRequestedAudioID == id || nativePairRetirementStarted { return }
            cancelNativePairTransfer()
        }
        guard isTwo, audioID != nil, audioID != id,
              panes.allSatisfy({ $0.model.activePlaybackEngine == .web }) else {
            listen(to: id)
            return
        }
        beginNativePairTransfer(audioID: id)
    }

    private struct NativePairSnapshot: Sendable {
        let pane: Pane
        let sourceID: UUID
        let requestID: UUID
        let intentID: UUID
        let wantsPlayback: Bool
    }

    private func nativePairSnapshotsAreCurrent(_ snapshots: [NativePairSnapshot]) -> Bool {
        panes.count == 2 && snapshots.count == 2 && snapshots.allSatisfy { snapshot in
            panes.contains(where: { $0.id == snapshot.pane.id && $0.model === snapshot.pane.model })
                && !snapshot.pane.model.isPlaybackSessionRetired
                && snapshot.pane.model.activeSource?.id == snapshot.sourceID
                && snapshot.pane.model.loadRequestID == snapshot.requestID
                && snapshot.pane.model.nativeWatchTwoIntentID == snapshot.intentID
                && snapshot.pane.model.userWantsPlayback == snapshot.wantsPlayback
                && !snapshot.pane.model.isPictureInPictureActive
                && !snapshot.pane.model.isWebPictureInPictureActive
                && snapshot.pane.model.nativeFullscreen == nil
        }
    }

    private func beginNativePairTransfer(audioID requestedAudioID: UUID) {
        guard panes.allSatisfy({ canChangePlaybackEngine($0) }) else { return }
        let snapshots = panes.compactMap { pane -> NativePairSnapshot? in
            guard let sourceID = pane.model.activeSource?.id else { return nil }
            return NativePairSnapshot(pane: pane, sourceID: sourceID,
                requestID: pane.model.loadRequestID, intentID: pane.model.nativeWatchTwoIntentID,
                wantsPlayback: pane.model.userWantsPlayback)
        }
        guard snapshots.count == 2 else { return }
        cancelNativePairTransfer()
        let generation = nativePairTransferGeneration
        nativePairRequestedAudioID = requestedAudioID
        resolutionError = nil
        resolutionMessage = Self.nativePairProgress
        nativePairTransferTask = Task { [weak self] in
            guard let self else { return }
            var prepared: [(NativePairSnapshot, PreparedNativeWatchTwoPlayback)] = []
            defer {
                for (snapshot, candidate) in prepared { self.nativeWatchTwo.discard(snapshot.pane.model, candidate) }
                if self.nativePairTransferGeneration == generation {
                    self.nativePairTransferTask = nil
                    self.nativePairRequestedAudioID = nil
                    self.nativePairRetirementStarted = false
                    if self.resolutionMessage == Self.nativePairProgress { self.resolutionMessage = nil }
                }
            }
            for snapshot in snapshots {
                guard let candidate = await self.nativeWatchTwo.prepare(snapshot.pane.model) else {
                    if !Task.isCancelled, self.nativePairTransferGeneration == generation,
                       self.nativePairSnapshotsAreCurrent(snapshots) {
                        self.resolutionError = Self.nativePairPreparationFailure
                    }
                    return
                }
                prepared.append((snapshot, candidate))
                guard !Task.isCancelled, self.nativePairTransferGeneration == generation,
                      self.nativePairSnapshotsAreCurrent(snapshots),
                      prepared.allSatisfy({ self.nativeWatchTwo.isCurrent($0.0.pane.model, $0.1) }) else { return }
            }
            // No old transport/audio ownership changes occur until both paused
            // preflights have passed. Both retire before either candidate adopts.
            self.cancelAudioTransfer()
            self.nativePairRetirementStarted = true
            for (snapshot, candidate) in prepared {
                guard self.nativeWatchTwo.beginRetirement(snapshot.pane.model, candidate) else {
                    self.resolutionError = Self.nativePairRetirementFailure
                    return
                }
            }
            for snapshot in snapshots {
                snapshot.pane.model.setRemoteCommandOwnership(false)
                snapshot.pane.model.setViewingAudioEnabled(false)
                snapshot.pane.model.setViewingPiPOwnership(false)
            }
            for (snapshot, candidate) in prepared {
                let retired = await self.nativeWatchTwo.waitForRetirement(snapshot.pane.model, candidate)
                guard !Task.isCancelled, self.nativePairTransferGeneration == generation,
                      self.nativePairSnapshotsAreCurrent(snapshots),
                      prepared.allSatisfy({ self.nativeWatchTwo.isCurrent($0.0.pane.model, $0.1) }) else { return }
                guard retired else {
                    self.resolutionError = Self.nativePairRetirementFailure
                    return
                }
            }
            for (snapshot, candidate) in prepared {
                guard self.nativeWatchTwo.adopt(snapshot.pane.model, candidate) else {
                    self.resolutionError = Self.nativePairRetirementFailure
                    return
                }
            }
            for (snapshot, candidate) in prepared { self.nativeWatchTwo.start(snapshot.pane.model, candidate) }
            for (snapshot, candidate) in prepared { self.nativeWatchTwo.releaseAudioHold(snapshot.pane.model, candidate) }
            self.listen(to: requestedAudioID)
        }
        observeNativePairSources(generation: generation, snapshots: snapshots)
    }

    private func observeNativePairSources(generation: UUID, snapshots: [NativePairSnapshot]) {
        withObservationTracking {
            for snapshot in snapshots {
                _ = snapshot.pane.model.activeSource?.id
                _ = snapshot.pane.model.loadRequestID
                _ = snapshot.pane.model.nativeWatchTwoIntentID
                _ = snapshot.pane.model.userWantsPlayback
                _ = snapshot.pane.model.isPictureInPictureActive
                _ = snapshot.pane.model.isWebPictureInPictureActive
                _ = snapshot.pane.model.nativeFullscreen
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.nativePairTransferTask != nil,
                      self.nativePairTransferGeneration == generation else { return }
                if self.nativePairSnapshotsAreCurrent(snapshots) {
                    self.observeNativePairSources(generation: generation, snapshots: snapshots)
                } else { self.cancelNativePairTransfer() }
            }
        }
    }

    private func cancelNativePairTransfer() {
        nativePairTransferGeneration = UUID()
        nativePairTransferTask?.cancel()
        nativePairTransferTask = nil
        nativePairRequestedAudioID = nil
        nativePairRetirementStarted = false
        if resolutionMessage == Self.nativePairProgress { resolutionMessage = nil }
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
                    self.resolutionError = self.isTwo ? Self.audioTransferFailure : Self.singleAudioTransferFailure
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
                    self.resolutionError = self.isTwo ? Self.audioTransferFailure : Self.singleAudioTransferFailure
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
        if resolutionError == Self.audioTransferFailure || resolutionError == Self.singleAudioTransferFailure {
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
        cancelNativePairTransfer()
        resolutionError = nil
        cancelResolution()
        dismissMatchPicker()
        if primaryID != id { handoffPublisher.stop() }
        for pane in panes where pane.id != id {
            revokeAudio(of: pane)
            pane.model.cleanup()
        }
        panes = [survivor]; primaryID = id; swapped = false; expanded = true
        survivor.model.setViewingPlaybackContext(.single)
        survivor.model.setViewingDiagnosticRoute(.single)
        MatchNavigationStore.shared.livePlayerDidAppear(matchID: survivor.event.id)
        listen(to: id)
    }

    func stop() {
        retirePlayback(preservingResolution: false)
    }

    private func retirePlayback(preservingResolution: Bool) {
        cancelLastLiveCapture()
        cancelNativePairTransfer()
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
        panes = []; primaryID = nil; audioID = nil; swapped = false
        dismissMatchPicker(); showsContinuity = false
        handoffPublisher.stop()
    }

    func showMatchPicker(replacing paneID: UUID? = nil) {
        if let paneID {
            guard isTwo, let pane = panes.first(where: { $0.id == paneID }), canReplace(pane) else { return }
        } else { guard panes.count == 1 else { return } }
        matchPickerReplacementID = paneID
        showsSecondMatchPicker = true
    }

    func dismissMatchPicker() {
        showsSecondMatchPicker = false
        matchPickerReplacementID = nil
    }

    func chooseSecond(_ event: EventReference) {
        guard !panes.contains(where: { Self.representsSameFixture($0.event, as: event) || $0.event.id == event.id }) else { return }
        let destination: ResolutionDestination
        if let target = matchPickerReplacementID {
            guard isTwo, let pane = panes.first(where: { $0.id == target }), canReplace(pane),
                  let survivor = panes.first(where: { $0.id != target }) else { return }
            destination = .replacement(target: target, survivor: survivor.id)
        } else {
            guard panes.count == 1, let primary else { return }
            destination = .second(retaining: primary.id)
        }
        dismissMatchPicker()
        resolve(event: event, destination: destination)
    }

    /// Commit a prepared replacement into its logical slot, never through
    /// openMulti (which resets display order and reclaims every pane's audio).
    /// Preparation owns no third decoder; only mounting starts the new model.
    @discardableResult
    func replacePreparedPane(_ targetID: UUID, preserving survivorID: UUID,
                             event: EventReference, sessions: [StreamSession]) -> Bool {
        guard isTwo, let index = panes.firstIndex(where: { $0.id == targetID }),
              panes.contains(where: { $0.id == survivorID && $0.id != targetID }),
              !sessions.isEmpty, !event.hasCatalogIdentityConflict,
              !MatchStartPolicy(event: event).isStopped,
              !panes.contains(where: { $0.event.id == event.id || Self.representsSameFixture($0.event, as: event) }),
              canReplace(panes[index]) else { return false }
        cancelNativePairTransfer()
        cancelResolution()
        let previous = panes[index]
        let replacement = Pane(id: UUID(), model: makeModel(event, sessions))
        guard let survivor = panes.first(where: { $0.id == survivorID }),
              preparePair([survivor, replacement], retaining: [survivor]) else {
            replacement.model.cleanup()
            return false
        }
        replacement.model.setViewingDiagnosticRoute(.watchTwo)
        // Establish muted/unclaimed state before the retained surface can mount.
        replacement.model.setRemoteCommandOwnership(false)
        replacement.model.setViewingAudioEnabled(false)
        replacement.model.setViewingPiPOwnership(false)
        let transfersAudio = audioID == previous.id
        let transfersPrimary = primaryID == previous.id
        revokeAudio(of: previous)
        previous.model.cleanup()
        panes[index] = replacement
        if transfersPrimary {
            handoffPublisher.stop()
            MatchNavigationStore.shared.livePlayerDidDisappear(matchID: previous.event.id)
            primaryID = replacement.id
            MatchNavigationStore.shared.livePlayerDidAppear(matchID: event.id)
        }
        if transfersAudio {
            listen(to: replacement.id)
        }
        return true
    }

    private func canReplace(_ pane: Pane) -> Bool {
        guard !pane.model.isPictureInPictureActive, !pane.model.isWebPictureInPictureActive,
              pane.model.nativeFullscreen == nil else {
            resolutionError = "Return from fullscreen or Picture in Picture before changing this match."
            return false
        }
        return true
    }

    func watchIncoming() {
        guard let event = incomingEvent else { return }
        incomingEvent = nil; incomingHandoff = nil
        resolve(event: event, destination: .single)
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
                    return
                }
                requested = admitted
            } else { requested = event }
            let matched = self.currentSingleEvent(requested)
            guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
            guard let matched else {
                self.resolutionError = "This broadcast changed or is no longer available. Refresh the lineup before watching."
                return
            }
            guard !Task.isCancelled, self.resolutionGeneration == generation,
                  Self.canReuse(requested, for: matched),
                  !matched.hasCatalogIdentityConflict,
                  MatchStartPolicy(event: matched).timingAllowsPlayback else {
                if !Task.isCancelled, self.resolutionGeneration == generation {
                    self.resolutionError = "This broadcast is no longer ready to watch. Refresh the lineup before watching."
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
                        : "No supported stream is available for this match right now."
                    MatchPlaybackFeedback.shared.notReady(event.id)
                }
            case .failure(let failure, let diagnostics):
                // An unrelated slow/failed lane cannot interrupt a source that
                // was already admitted. Diagnostics still record the failure.
                guard ![StreamFailureCategory.navigationCancelled, .duplicateRequestCancelled,
                        .userCancelled, .backgroundedDuringResolution].contains(failure.category) else { return }
                if self.singleSourceDiscoveryPaneID == nil {
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
        guard !isTwo, resolutionMessage == nil, optionalSourceLookupGeneration == nil else { return false }
        cancelResolution()
        let generation = UUID()
        resolutionGeneration = generation
        optionalSourceLookupGeneration = generation
        pendingSingleEvent = event
        resolutionMessage = "Opening broadcast…"
        resolutionError = nil
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
                return
            }
            guard !Task.isCancelled, self.resolutionGeneration == generation, !self.isTwo else { return }
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
            switch outcome {
            case .success(let result):
                let acceptance = await self.acceptOptionalSourceChoices(result.sessions, event: admitted,
                    generation: generation, enabledProviders: enabledProviders, currentEvent: currentEvent)
                guard !Task.isCancelled, self.resolutionGeneration == generation else { return }
                if self.optionalSourceLookupPaneID == nil {
                    self.resolutionError = acceptance == .changed
                        ? "This fixture changed. Refresh the lineup before watching."
                        : "No supported stream is available for this match right now."
                }
            case .failure(let failure, let diagnostic):
                if self.optionalSourceLookupPaneID == nil {
                    self.resolutionError = failure.userMessage
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
              optionalSourceLookupGeneration == generation, !isTwo else { return .changed }
        guard let latest = await currentEvent(event, .completion),
              Self.canReuse(event, for: latest), event.kickoffDate == latest.kickoffDate,
              !latest.hasCatalogIdentityConflict, !MatchStartPolicy(event: latest).isStopped else { return .changed }
        guard !Task.isCancelled, resolutionGeneration == generation,
              optionalSourceLookupGeneration == generation, !isTwo else { return .changed }
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

    private func resolve(event: EventReference, destination: ResolutionDestination) {
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
                switch destination {
                case .second(let retainedID):
                    guard self.panes.count == 1, let current = self.panes.first(where: { $0.id == retainedID }) else { return }
                    self.openMulti(slots: [MultiLiveSlot(event: current.event, sessions: current.model.sessions),
                                          MultiLiveSlot(event: currentEvent, sessions: result.sessions)])
                case .replacement(let target, let survivor):
                    self.replacePreparedPane(target, preserving: survivor, event: currentEvent, sessions: result.sessions)
                case .single:
                    self.open(event: currentEvent, sessions: result.sessions)
                }
            case .failure(let failure, _): self.resolutionError = failure.userMessage
            }
        }
    }

    func cancelResolution() {
        cancelNativePairTransfer()
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
    static func usesTwoColumns(width: CGFloat, accessibility: Bool) -> Bool { width >= 700 && !accessibility }

    static func usesVideoFirstSinglePlayer(isPad: Bool, isTwo: Bool) -> Bool { isPad && !isTwo }

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

/// One cancellable, presentation-only snapshot. Search uses Home's existing
/// vocabulary; eligibility still uses the complete catalog/conflict evidence.
@MainActor
enum ViewingMatchPickerPolicy {
    @MainActor
    struct Prepared {
        let events: [EventReference]
        let search: HomeSportsSearch.Index

        var sports: [String] { Set(events.map { $0.normalizedCategory }).sorted() }

        func results(query: String, sport: String = "all-sports") -> [EventReference] {
            let matches: Set<String>?
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { matches = nil }
            else { matches = Set(search.results(query: query).map(\.id)) }
            return events.filter {
                (sport == HomeSportsDiscovery.allSports || $0.normalizedCategory == sport)
                    && (matches?.contains($0.id) ?? true)
            }
        }
    }

    static func prepare(events: [EventReference], catalog: [EventReference],
                        excluding retained: [EventReference], now: Date = Date(),
                        status: (EventReference) -> FootballMatch.MatchStatus? = { _ in nil },
                        leagueName: ((EventReference) -> String?)? = nil,
                        discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
                        isCurrent: () -> Bool = { true },
                        checkpoint: () async -> Bool = { await HomeSportsSearch.checkpoint(isCurrent: { true }) }) async -> Prepared? {
        guard !Task.isCancelled, isCurrent(), await checkpoint(), isCurrent() else { return nil }
        var admitted: [EventReference] = []
        var seen = Set<String>()
        for (index, event) in events.enumerated() {
            guard !Task.isCancelled, isCurrent() else { return nil }
            if !retained.contains(where: { $0.id == event.id || ViewingSessionCoordinator.representsSameFixture($0, as: event) }),
               let action = CurrentEventBroadcastPolicy.action(for: event, in: catalog, at: now, status: status(event),
                   discoveryIndex: discoveryIndex),
               !action.isChannelFallback, seen.insert(action.event.id).inserted {
                admitted.append(action.event)
            }
            if (index + 1).isMultiple(of: 16) {
                guard await checkpoint(), !Task.isCancelled, isCurrent() else { return nil }
            }
        }
        guard await checkpoint(), !Task.isCancelled, isCurrent() else { return nil }
        let discovery = HomeSportsDiscovery(events: admitted, now: now, terminalEvents: catalog, status: status)
        // Include directly selected channels without claiming a named programme.
        let visibleIDs = Set(discovery.items.map(\.id) + discovery.channels.map(\.id))
        let rows = admitted.filter { visibleIDs.contains($0.id) }
        guard await checkpoint(), !Task.isCancelled, isCurrent() else { return nil }
        // The existing cooperative search preparer avoids blocking playback for
        // whole-catalog normalization. Nonempty "catalog" requests preparation;
        // the actual user query is applied only to the resulting immutable index.
        guard let search = await HomeSportsSearch.prepareForQuery(in: discovery, query: "catalog", leagueName: { event in
            if let leagueName { return leagueName(event) }
            guard event.normalizedCategory == "football" else { return nil }
            let league = AnalyticalDataEngine.footballLeagueTab(for: event)
            return league == .all || league == .other ? nil : league.displayName
        }, isCurrent: isCurrent),
              !Task.isCancelled, isCurrent() else { return nil }
        return Prepared(events: rows, search: search)
    }
}
