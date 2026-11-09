import SwiftUI
import AVKit
import Network
import os.log
import CoreVideo
import UIKit

private let livePlayerLifecycleLogger = Logger(
    subsystem: "com.jelani.Fotty",
    category: "PlaybackLifecycle"
)

enum ViewingPlaybackAudioPolicy {
    static func isMuted(isEnabled: Bool, diagnosticMute: Bool,
                        awaitingWebRetirement: Bool = false, awaitingAudioClaim: Bool = false) -> Bool {
        diagnosticMute || !isEnabled || awaitingWebRetirement || awaitingAudioClaim
    }
}

enum ViewingPlaybackEngine: Equatable { case web, native }
enum NativeWatchTwoPreflightStage: String {
    case admission, proxy, validation, isolation, readiness, registration
}
enum NativeWatchTwoPreflightOutcome: String {
    case notEligible = "not_eligible", unsupported = "unsupported", noCandidate = "no_candidate"
    case staleCandidate = "stale_candidate", staleOwner = "stale_owner", cancelled
    case proxyFailed = "proxy_failed", validationRejected = "validation_rejected"
    case isolationFailed = "isolation_failed", readinessFailed = "readiness_failed"
    case readinessTimeout = "readiness_timeout", registrationRejected = "registration_rejected", prepared
}
enum ViewingPlaybackContext: Equatable {
    case single
    case watchTwo(engine: ViewingPlaybackEngine)
}

/// Composition only: callers capture the exact candidate item and relay before
/// retiring them. No active-player lookup, playback decision or invented cause.
enum NativeHandoffCandidateDiagnostic {
    static func details(itemStatus: AVPlayerItem.Status,
                        native: PlayerDiagnosticService.DiagnosticSnapshot,
                        candidateRelayDetails: [String: String]) -> [String: String] {
        var details = native.qualityDetails.merging(candidateRelayDetails) { _, value in value }
        switch itemStatus {
        case .unknown: details["native_item_status"] = "unknown"
        case .readyToPlay: details["native_item_status"] = "ready"
        case .failed: details["native_item_status"] = "failed"
        @unknown default: details["native_item_status"] = "other"
        }
        return details
    }
}

/// Finite reasons why an initial observation ended without granting a source
/// failure or decoded-video result. These describe ownership, not providers.
enum NativeStartupObservationEndReason: String, CaseIterable {
    case cancelled, retired, paused, backgrounded
    case replacedAttempt = "replaced_attempt", replacedItem = "replaced_item"
    case renewedAudioIntent = "renewed_audio_intent", invalidTiming = "invalid_timing"
    case interrupted

    var diagnosticResult: FottyPlaybackDiagnosticResult {
        switch self {
        case .cancelled, .retired, .invalidTiming, .interrupted: .cancelled
        case .paused: .intentRevoked
        case .backgrounded: .backgrounded
        case .replacedAttempt, .replacedItem, .renewedAudioIntent: .ownershipChanged
        }
    }

    var qualityDetails: [String: String] {
        ["reason_code": rawValue, "diagnostic_result": diagnosticResult.rawValue,
         "diagnostic_purpose": FottyPlaybackDiagnosticPurpose.nativeStart.rawValue]
    }
}

/// A captured old Web owner, not a promise about its replacement document.
/// Teardown can settle this lease even after its model has been retired.
@MainActor
private final class WebViewingAudioRevocation {
    var id = UUID()
    let sourceID: UUID
    let requestID: UUID
    var acknowledged = false
    init(sourceID: UUID, requestID: UUID) { self.sourceID = sourceID; self.requestID = requestID }
    func wait() async -> Bool {
        for _ in 0..<60 {
            guard !Task.isCancelled else { return false }
            if acknowledged { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return acknowledged && !Task.isCancelled
    }
}

/// One fatal observation for the exact native item/attempt. Background delivery
/// records evidence immediately, but grants no transport/retry authority until
/// the same owner returns to foreground with playback still requested.
@MainActor
private final class NativeItemFailureObservation {
    weak var item: AVPlayerItem?
    let sourceID: UUID
    let requestID: UUID
    let reason: String
    let diagnosticDetails: [String: String]
    var mediaSecondAtObservation: Double
    var awaitsForegroundRecovery: Bool

    init(item: AVPlayerItem, sourceID: UUID, requestID: UUID, reason: String,
         diagnosticDetails: [String: String], mediaSecondAtObservation: Double,
         awaitsForegroundRecovery: Bool) {
        self.item = item; self.sourceID = sourceID; self.requestID = requestID
        self.reason = reason; self.diagnosticDetails = diagnosticDetails
        self.mediaSecondAtObservation = mediaSecondAtObservation
        self.awaitsForegroundRecovery = awaitsForegroundRecovery
    }

    func matches(item: AVPlayerItem?, sourceID: UUID?, requestID: UUID) -> Bool {
        self.item != nil && self.item === item && self.sourceID == sourceID && self.requestID == requestID
    }
}

/// Returning from PiP can require observation without a transport resume. Keep
/// the backgrounded transport weakly identified so foregrounding cannot attach
/// recovery work to a replacement item or source.
@MainActor
private struct NativeForegroundObservationLease {
    weak var player: AVPlayer?
    weak var item: AVPlayerItem?
    let sourceID: UUID
    let requestID: UUID
}

/// A provider can replace its decoded document without replacing Fotty's
/// source attempt. Preserve those transport callbacks, but count initial-start
/// evidence only once. Callers fence the active owner before admitting here.
struct SinglePlaybackStartEvidence {
    enum Event: Equatable { case initialStartup, resumedProgress, nativeHandoff }
    enum Receipt: Equatable { case none, initialStartup, resumedProgress, nativeHandoff }
    private var identity: FottyPlaybackIntervals.Identity?
    private var recordedInitialEvidence = false
    private var recordedNativeHandoff = false

    mutating func admit(_ event: Event, identity: FottyPlaybackIntervals.Identity) -> Receipt {
        if self.identity != identity {
            self.identity = identity
            recordedInitialEvidence = false
            recordedNativeHandoff = false
        }
        switch event {
        case .initialStartup, .resumedProgress:
            guard !recordedInitialEvidence else { return .none }
            recordedInitialEvidence = true
            return event == .initialStartup ? .initialStartup : .resumedProgress
        case .nativeHandoff:
            guard !recordedNativeHandoff else { return .none }
            recordedNativeHandoff = true
            // Handoff/resume are not fresh source startup latency samples.
            recordedInitialEvidence = true
            return .nativeHandoff
        }
    }
}

@Observable
@MainActor
final class LivePlayerViewModel {
    let event: AnalyticalDataEngine.EventReference
    private(set) var providedSessions: [StreamSession]
    private(set) var isCheckingAdditionalSources = false
    private struct PendingSingleDiscoveryFailure {
        let sourceID: UUID
        let requestID: UUID
        let failureKind: LivePlaybackFailureKind
        let qualityDetails: [String: String]
        let requiresFreshBinding: Bool
    }
    @ObservationIgnored private var pendingSingleDiscoveryFailure: PendingSingleDiscoveryFailure?
    @ObservationIgnored private var singleDiscoveryContinuationRevoked = false

    var player: AVPlayer? {
        willSet {
            if player !== newValue {
                singlePlaybackQuality.invalidate()
                nativeItemFailureObservation = nil
                retireNativeFullscreenForTransportChange()
            }
        }
        didSet {
            if player !== oldValue {
                retireNativeAudioIsolation()
                cancelNativeHandoffAudioClaim()
                nativeHandoffAudioMuteHeld = false
                if player !== nativePlayerRequiringReplacement { nativePlayerRequiringReplacement = nil }
            }
            applyViewingAudioState()
        }
    }
    let singlePlaybackQuality: SinglePlaybackQualityController
    @ObservationIgnored let nativeMeasurementBinding = NativePlaybackMeasurementBinding()
    private(set) var nativeFullscreen: NativeFullscreenSession?
    /// A requested lease must not detach the inline renderer while its owning
    /// window is still dismissing another sheet. AVKit commits this separately.
    private(set) var nativeFullscreenIsPresented = false
    @ObservationIgnored private var ownedNativeRateCommandDepth = 0
    let remoteCommandOwnerID = UUID()
    private(set) var ownsRemoteCommands = false
    private(set) var isViewingAudioEnabled = true
    private(set) var allowsViewingPiP = true
    private(set) var didStartPlayback = false
    private(set) var isPlaybackSessionRetired = false
    /// Read-only evidence for the local return shortcut. Transport readiness or
    /// a generic Playing state cannot create a viewing record on their own.
    var hasConfirmedSinglePlayback: Bool {
        viewingPlaybackContext == .single && usesSingleStreamRanking
            && isPlaybackSessionActive && !isPlaybackSessionRetired
            && activeSource != nil && error == nil
            && lastObservedPlaybackStage == .decoded
    }
    private var nativeHandoffAwaitingWebRetirement = false
    @ObservationIgnored private var nativeHandoffAudioMuteHeld = false
    @ObservationIgnored private var nativeAudioFocusGeneration = UUID()
    @ObservationIgnored private var nativeHandoffAudioClaimID = UUID()
    @ObservationIgnored private(set) var nativeHandoffAudioClaimTask: Task<Void, Never>?
    @ObservationIgnored private(set) var nativeAudioIsolation: NativePlayerAudioIsolation?
    @ObservationIgnored private var nativeAudioRetirements: [ObjectIdentifier: NativePlayerAudioIsolation.Barrier] = [:]
    @ObservationIgnored private weak var nativePlayerRequiringReplacement: AVPlayer?
    @ObservationIgnored private(set) var diagnosticRoute: FottyPlaybackDiagnosticRoute = .single
    private(set) var viewingPlaybackContext: ViewingPlaybackContext = .single {
        willSet {
            if newValue != viewingPlaybackContext { singlePlaybackQuality.invalidate() }
        }
        didSet {
            if viewingPlaybackContext == .single { refreshSinglePlaybackQuality() }
        }
    }
    private(set) var usesSingleStreamRanking = false
    private(set) var nativeTransferSuspensionID: UUID?
    private(set) var webAudioRevocationID: UUID?
    @ObservationIgnored private var currentWebAudioRevocation: WebViewingAudioRevocation?
    @ObservationIgnored private var webAudioRevocations: [WebViewingAudioRevocation] = []
    // Single-player retirement follows actual mounted documents, not a source
    // selected while discovery/validation is still pending.
    @ObservationIgnored private var mountedWebOwners: [UUID: UUID] = [:]
    @ObservationIgnored var onSingleWebAudioRetired: (() -> Void)?

    func handleWebPlaybackMounted(sourceID: UUID, requestID: UUID) {
        guard !isPlaybackSessionRetired else { return }
        mountedWebOwners[requestID] = sourceID
    }

    private var nativeTransferAcknowledgedID: UUID?
    private var explicitNativeTransferID: UUID?
    @ObservationIgnored private var nativeTransferTaskID: UUID?
    @ObservationIgnored private weak var preparingNativeTransferPlayer: AVPlayer?
    @ObservationIgnored private var preparingNativeTransferPlayerID: UUID?
    private var cachedNativeCandidate: (candidate: NativeWebPlaybackCandidate, sourceID: UUID, requestID: UUID)?
    @ObservationIgnored private var preparedNativeWatchTwo: PreparedNativeWatchTwoPlayback?
    @ObservationIgnored private(set) var nativeWatchTwoPreflightOutcome: NativeWatchTwoPreflightOutcome?
    private(set) var isRetiringWebForNativeWatchTwo = false
    private var nativeWatchTwoAudioHeld = false
    @ObservationIgnored private var nativeWatchTwoDelivery: NativeWebPlaybackCandidate?
    @ObservationIgnored private var retiredWebOwner: (sourceID: UUID, requestID: UUID)?
    private var nativeWatchTwoIntentRevision = UUID()
    var nativeWatchTwoIntentID: UUID { nativeWatchTwoIntentRevision }
    var shouldDisplayWebPlayback: Bool { isUsingWebEmbed && !isRetiringWebForNativeWatchTwo }
    private var lastAdmittedSourceIndex = 0
    @ObservationIgnored private var causalDiagnosticBudget = FottyPlaybackDiagnosticBudget()
    @ObservationIgnored private var handoffDiagnosticPhase: FottyPlaybackDiagnosticHandoffPhase = .none
    @ObservationIgnored private var handoffDiagnosticOperationID: UUID?
    @ObservationIgnored private var diagnosticCandidateCount = 0

    /// Standard WebKit controls remain canonical. The retained host uses this
    /// only for explicitly selected Watch Two audio focus / diagnostic muting.
    var webMute: Bool {
        ViewingPlaybackAudioPolicy.isMuted(isEnabled: isViewingAudioEnabled,
                                           diagnosticMute: AppRuntime.shouldMutePlaybackForTesting)
    }
    var currentSourceIndex = 0 {
        didSet {
            if currentSourceIndex != oldValue {
                singlePlaybackQuality.invalidate()
                singleContinuityTask?.cancel(); singleContinuityTask = nil
                nativeItemFailureObservation = nil
                singleNativePreparation = nil
                deferredSingleNativePreparation = nil
                cancelPendingWebRetry()
            }
        }
    }
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
    var isVideoReadyForDisplay = false {
        didSet { if !isVideoReadyForDisplay { singleContinuityTask?.cancel(); singleContinuityTask = nil } }
    }
    var showControls = true
    var showSourceSelector = false {
        didSet {
            if oldValue && !showSourceSelector, viewingPlaybackContext == .single,
               isPlaybackSessionActive, showControls { scheduleAutoHide() }
        }
    }
    var connectionPhase = "Idle"
    var playbackBannerMessage: String? = nil
    var didApplyLandscape = false
    var webPlaybackCommand: WebPlaybackCommand?
    // Transport state can change during an interruption. Keep explicit user
    // intent separate so recovery cannot turn a deliberate native pause into Play.
    private(set) var userWantsPlayback = true {
        didSet {
            if oldValue != userWantsPlayback { nativeWatchTwoIntentRevision = UUID() }
            if !userWantsPlayback {
                disarmSingleDiscoveryContinuation()
                singleContinuityTask?.cancel(); singleContinuityTask = nil
                invalidateSingleNetworkRecovery()
            }
        }
    }
    private(set) var isWebPlaybackUserPaused = false
    private(set) var isWebPictureInPictureActive = false
    private var backgroundWebSuspensionRequested = false
    private var awaitsNativeAudioRetirement = false
    private(set) var shouldSuspendWebPlayback: Bool {
        get { backgroundWebSuspensionRequested || awaitsNativeAudioRetirement }
        set { backgroundWebSuspensionRequested = newValue }
    }

    private(set) var loadRequestID = UUID() {
        willSet {
            if newValue != loadRequestID {
                pendingSingleDiscoveryFailure = nil
                singlePlaybackQuality.invalidate()
                singleContinuityTask?.cancel(); singleContinuityTask = nil
                nativeItemFailureObservation = nil
                singleNativePreparation = nil
                deferredSingleNativePreparation = nil
                invalidateSingleNetworkRecovery()
                retireNativeFullscreenForTransportChange()
            }
        }
    }
    private(set) var playbackCorrelation = FottyPlaybackCorrelation()
    @ObservationIgnored private var singlePlaybackStartEvidence = SinglePlaybackStartEvidence()
    @ObservationIgnored private var singleContinuityTask: Task<Void, Never>?
    private var lastObservedPlaybackStage = FottyPlaybackStage.preparing
    private(set) var failedSourceIDs: Set<UUID> = []
    private(set) var lastPlaybackStateChangeAt = Date()
    private(set) var isPlaybackWatchdogArmed = false
    private(set) var stallCount = 0
    private(set) var autoFailoverCount = 0
    private(set) var lastFailureKind: LivePlaybackFailureKind = .unknown
    private(set) var lastFailureReason: String?
    var forceWebEmbedSourceIDs: Set<UUID> = []

    var webStartupRetryAttemptsBySource: [UUID: Int] = [:]
    var webStallRetryAttemptsBySource: [UUID: Int] = [:]
    var nativeStartupRetryAttemptsBySource: [UUID: Int] = [:]
    private var exhaustedMatchLookup: Task<Void, Never>?
    private var usedExhaustedMatchLookup = false
    private var descriptorRefreshAttempts: Set<UUID> = []
    private var requiredDescriptorRefreshSourceIDs: Set<UUID> = []
    private var pendingDescriptorRefreshSourceID: UUID?
    private var descriptorNegotiationRequestID: UUID?
    private var pausedDescriptorNegotiationSourceID: UUID?
    /// Before the current attempt installs an item, the player may still hold
    /// the retired attempt's item. A lifecycle resume must never play that item.
    private struct SingleNativePreparation {
        let requestID: UUID
        let sourceID: UUID
        var needsDescriptorRefresh: Bool
    }
    private var singleNativePreparation: SingleNativePreparation?
    private var deferredSingleNativePreparation: SingleNativePreparation?
    private let refreshSourceDescriptor: @MainActor (StreamSession, StreamPlaybackRequest) async -> StreamSession?
    private let currentDescriptorRecoveryRequest: @MainActor (StreamPlaybackRequest) -> StreamPlaybackRequest?
    private let currentMatchProviders: @MainActor () -> Set<String>?
    /// Fresh exact lookup after the in-hand deliveries are exhausted. Injected
    /// so lifecycle tests never reach production resolvers or the network.
    typealias FreshMatchLookup = @MainActor (StreamPlaybackRequest,
        @escaping @Sendable ([StreamSession]) async -> Void) async -> Void
    private let freshMatchLookup: FreshMatchLookup
    /// While a match plays, its backup deliveries age (event bindings last 90 s
    /// and upstream tokens rotate). One bounded lookup per interval keeps the
    /// backup list current so a mid-match failure does not walk stale siblings.
    private let backupRefreshInterval: Duration
    @ObservationIgnored private let backupRefreshScheduler = BackupRefreshScheduler()
    @ObservationIgnored private var prefetchingRenewals: Set<UUID> = []
    /// Read-only receipts for tests and diagnostics.
    private(set) var backupRefreshCount = 0
    @ObservationIgnored private var lastMatchComparison: [String: String]?
    private let nativePlaylistIsNonAdvancing: @MainActor (LocalStreamProxy) -> Bool
    private let nativePlaylistIsAdvancing: @MainActor (LocalStreamProxy) -> Bool

    var isNetworkReachable = true
    var pendingRetryAfterNetworkRestore = false
    private struct SingleNetworkRecoveryOwner {
        let sourceID: UUID
        let requestID: UUID
        let intentID: UUID
    }
    private var singleNetworkRecoveryOwner: SingleNetworkRecoveryOwner?
    private var networkLossTask: Task<Void, Never>?

    var loadTask: Task<Void, Never>?
    var hideTask: Task<Void, Never>?
    private var stallValidationOwner: (attempt: UUID, item: ObjectIdentifier?, token: UUID)?
    var stallValidationTask: Task<Void, Never>?
    var playbackWatchdogTask: Task<Void, Never>?
    var failoverBannerTask: Task<Void, Never>?
    var audioPreparationTask: Task<Void, Never>?
    private var audioIntentID = UUID()
    /// Read-only ownership fence for scene-owned explicit single Retry work.
    var playbackIntentRevision: UUID { nativeWatchTwoIntentRevision }
    var pictureInPicturePreparationTask: Task<Void, Never>?
    private var pictureInPicturePreparationID = UUID()
    var foregroundResumeValidationTask: Task<Void, Never>?
    private var singleResumeOwner: (token: UUID, attempt: UUID)?
    var nativeHandoffTask: Task<Void, Never>?
    private var webBackgroundSuspensionTask: Task<Void, Never>?
    private(set) var webRetryTask: Task<Void, Never>?
    private var webRetryID: UUID?
    private var isPlaybackSessionActive = true
    private(set) var isAppBackgrounded = false
    @ObservationIgnored private var nativeItemFailureObservation: NativeItemFailureObservation?
    @ObservationIgnored private var nativeForegroundObservationLease: NativeForegroundObservationLease?
    private let webRetryDelay: @MainActor () async throws -> Void
    private let webBackgroundSuspensionDelay: @MainActor () async throws -> Void
    private let timing: FottyAsyncTiming
    private let controlsNeedAccessibilityVisibility: @MainActor () -> Bool
    private let playbackIntervals = FottyPlaybackIntervals()
    private var controlsHideGeneration = UUID()
    let networkPathObserver = NetworkPathObserver(label: "com.fotty.livePlayer.networkPath")
    var streamProxy: LocalStreamProxy?
    var nativeHandoffSession: StreamSession?
    var attemptedNativeCandidateURLs: Set<String> = []

    private let diagnosticService = PlayerDiagnosticService()
    private let prepareAudioSession: @MainActor () async -> MediaAudioSessionPreparation
    private let configureAudioSession: @MainActor () async -> MediaAudioSessionPreparation
    private let nativeAudioIsolationBackend: NativePlayerAudioIsolationBackend
    private let validateNativeSource: @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult

    var lastStartupLatencyMs: Int?
    /// Watchdog stagnation (policy in PlaybackProgressPolicy.swift). The two
    /// forwarding properties keep the existing test and controls surface.
    var stagnation = PlaybackStagnationCounter()
    var playbackStagnationTicks: Int {
        get { stagnation.ticks }
        set { stagnation.ticks = newValue }
    }
    var lastObservedPlaybackSecond: Double? {
        get { stagnation.lastSecond }
        set { stagnation.lastSecond = newValue }
    }
    var sourceAttemptStartedAt: Date?
    var shouldResumeAfterForeground = false
    var playerItemNotificationTokens: [NSObjectProtocol] = []
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var initialNativeStartupRequestID: UUID?

    var nativeWatchdogStallThresholdTicks: Int { PlaybackProgressPolicy.frozenTickThreshold(single: false) }

    init(
        event: AnalyticalDataEngine.EventReference,
        providedSessions: [StreamSession],
        ownsRemoteCommands: Bool = true,
        webRetryDelay: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(500))
        },
        webBackgroundSuspensionDelay: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(750))
        },
        prepareAudioSession: @escaping @MainActor () async -> MediaAudioSessionPreparation = {
            await MediaAudioSession.activateForPlaybackIfNeeded()
        },
        configureAudioSession: @escaping @MainActor () async -> MediaAudioSessionPreparation = {
            await MediaAudioSession.configureForPlayback()
        },
        validateNativeSource: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult = { url, headers in
            await StreamContractValidator().validate(url, headers: headers)
        },
        refreshSourceDescriptor: @escaping @MainActor (StreamSession, StreamPlaybackRequest) async -> StreamSession? = {
            await LiveStreamResolver.shared.refreshedDescriptor(for: $0, request: $1)
        },
        currentDescriptorRecoveryRequest: @escaping @MainActor (StreamPlaybackRequest) -> StreamPlaybackRequest? = {
            RegisteredDescriptorRecoveryPolicy.currentRequest(for: $0, in: MatchListViewModel.shared.playbackAdmissionCatalog)
        },
        nativePlaylistIsNonAdvancing: @escaping @MainActor (LocalStreamProxy) -> Bool = {
            $0.hasNonAdvancingLivePlaylist()
        },
        nativePlaylistIsAdvancing: @escaping @MainActor (LocalStreamProxy) -> Bool = {
            $0.hasAdvancingLivePlaylist()
        },
        timing: FottyAsyncTiming? = nil,
        nativeAudioIsolationBackend: NativePlayerAudioIsolationBackend? = nil,
        singlePlaybackQuality: SinglePlaybackQualityController? = nil,
        controlsNeedAccessibilityVisibility: @escaping @MainActor () -> Bool = {
            UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
        },
        currentMatchProviders: @escaping @MainActor () -> Set<String>? = { LivePlaybackSourcePolicy.enabledMatchProviders },
        freshMatchLookup: @escaping FreshMatchLookup = { request, publish in
            // Hosted tests never reach production resolvers; they inject a lookup.
            guard !AppRuntime.isAutomatedTesting else { return }
            _ = await LiveStreamResolver.shared.resolvePlayback(for: request, onChoices: publish,
                refreshOptionalSources: true)
        },
        backupRefreshInterval: Duration = .seconds(600)
    ) {
        self.event = event
        self.webRetryDelay = webRetryDelay
        self.webBackgroundSuspensionDelay = webBackgroundSuspensionDelay
        self.validateNativeSource = validateNativeSource
        self.refreshSourceDescriptor = refreshSourceDescriptor
        self.currentDescriptorRecoveryRequest = currentDescriptorRecoveryRequest
        self.currentMatchProviders = currentMatchProviders
        self.freshMatchLookup = freshMatchLookup
        self.backupRefreshInterval = backupRefreshInterval
        self.nativePlaylistIsNonAdvancing = nativePlaylistIsNonAdvancing
        self.nativePlaylistIsAdvancing = nativePlaylistIsAdvancing
        self.prepareAudioSession = prepareAudioSession
        self.configureAudioSession = configureAudioSession
        self.nativeAudioIsolationBackend = nativeAudioIsolationBackend ?? .system
        self.singlePlaybackQuality = singlePlaybackQuality ?? SinglePlaybackQualityController()
        self.timing = timing ?? .live
        self.controlsNeedAccessibilityVisibility = controlsNeedAccessibilityVisibility
        let context = LiveSourceHealthStore.contextKey(for: event)
        let webOnly = providedSessions.filter(StreamPluginProviderMatching.isActivePlayerSession)
        self.providedSessions = LiveSourceHealthStore.rankedSessions(webOnly, contextKey: context)
        self.currentSourceIndex = LivePlaybackSourcePolicy.preferredInitialIndex(
            in: self.providedSessions,
            contextKey: context
        )

        setRemoteCommandOwnership(ownsRemoteCommands)
    }

    /// Explicitly opted in by a new single-player destination, not the shared
    /// initializer: Watch Two models also start with a `.single` context.
    /// Picking an initial index must never reload or replace a running owner.
    @discardableResult
    func configureSingleStreamRanking() -> Bool {
        guard !didStartPlayback, !isPlaybackSessionRetired,
              viewingPlaybackContext == .single, player == nil,
              sourceAttemptStartedAt == nil, !usesSingleStreamRanking else { return false }
        usesSingleStreamRanking = true
        let context = LiveSourceHealthStore.contextKey(for: event)
        let preferred: StreamSource?
        if event.isBroadcastChannel {
            preferred = LiveSourceHealthStore.rankedSingleStreamSessions(sessions, contextKey: context, applyMatchEvidence: false).first?.legacySource
        } else {
            let eligible = sessions.filter { $0.matchID == event.id && $0.validationStatus == .validated
                && LiveSourceHealthStore.matchEvidence(for: $0) != .wrongProgramme }
            let baseline = LiveSourceHealthStore.rankedSingleStreamSessions(eligible, contextKey: context, applyMatchEvidence: false)
            let trial = LiveSourceHealthStore.rankedSingleStreamSessions(eligible, contextKey: context)
            preferred = selectedMatchSource(baseline: baseline.map(\.legacySource), trial: trial.map(\.legacySource), after: nil)
        }
        if let preferred,
           let index = sessions.firstIndex(where: { $0.id == preferred.id }) {
            currentSourceIndex = index
            lastAdmittedSourceIndex = index
        }
        return true
    }

    /// A scene's Watch survives source attempts and explicit fresh discovery.
    /// Bind only before this model starts; a late caller cannot rewrite receipts.
    func bindSingleWatchDiagnostics(_ id: UUID) {
        guard !didStartPlayback, playbackCorrelation.attemptNumber == 0,
              viewingPlaybackContext == .single, !isPlaybackSessionRetired else { return }
        playbackCorrelation = FottyPlaybackCorrelation(sessionID: id)
    }

    /// Only actual current native HLS item variants expose this choice. A
    /// provider's quality label, Web source or shared pair initializer cannot.
    var canChooseSinglePlaybackQuality: Bool {
        guard let player, let item = player.currentItem, let source = activeSource,
              ownsSinglePlaybackQualityItem(player: player, item: item, sourceID: source.id, requestID: loadRequestID) else { return false }
        return singlePlaybackQuality.matches(player: player, item: item, sourceID: source.id, requestID: loadRequestID)
    }

    func refreshSinglePlaybackQuality() {
        guard let player, let item = player.currentItem, let source = activeSource,
              ownsSinglePlaybackQualityItem(player: player, item: item, sourceID: source.id, requestID: loadRequestID) else {
            singlePlaybackQuality.invalidate()
            return
        }
        let sourceID = source.id, requestID = loadRequestID
        singlePlaybackQuality.inspect(player: player, item: item, sourceID: sourceID, requestID: requestID) { [weak self, weak player, weak item] in
            guard let self, let player, let item else { return false }
            return self.ownsSinglePlaybackQualityItem(player: player, item: item, sourceID: sourceID, requestID: requestID)
        }
    }

    @discardableResult
    func selectSinglePlaybackQuality(_ preference: SinglePlaybackQualityPreference) -> Bool {
        guard canChooseSinglePlaybackQuality else { return false }
        return singlePlaybackQuality.select(preference)
    }

    private func ownsSinglePlaybackQualityItem(player: AVPlayer, item: AVPlayerItem, sourceID: UUID, requestID: UUID) -> Bool {
        usesSingleStreamRanking && viewingPlaybackContext == .single
            && isPlaybackSessionActive && !isPlaybackSessionRetired && !isUsingWebEmbed && error == nil
            && activeSession?.playbackContract.container == .hls
            && self.player === player && player.currentItem === item
            && activeSource?.id == sourceID && loadRequestID == requestID
    }

    /// Healthy/paused owners only append. An exhausted initial auto-start may
    /// consume one lease from its still-active discovery to try a new delivery;
    /// the failed transport itself remains retired.
    func appendDiscoveredSingleSessions(_ incoming: [StreamSession], currentEvent: EventReference? = nil) {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single,
              !isPlaybackSessionRetired else { return }
        var seen = Set(providedSessions.map { StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders) })
        let additions = incoming.filter {
            $0.matchID == event.id && StreamPluginProviderMatching.isActivePlayerSession($0)
                && seen.insert(StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders)).inserted
        }
        guard !additions.isEmpty else { return }
        providedSessions.append(contentsOf: additions)
        guard let pending = pendingSingleDiscoveryFailure,
              isCheckingAdditionalSources, !singleDiscoveryContinuationRevoked,
              isPlaybackSessionActive, !isAppBackgrounded, userWantsPlayback,
              pending.sourceID == activeSource?.id, pending.requestID == loadRequestID,
              !isPictureInPictureActive, !isWebPictureInPictureActive, nativeFullscreen == nil,
              let currentEvent, !currentEvent.hasCatalogIdentityConflict,
              currentEvent.kickoffDate == event.kickoffDate,
              ViewingSessionCoordinator.canReuse(event, for: currentEvent),
              MatchStartPolicy(event: currentEvent).timingAllowsPlayback,
              let source = activeSource else { return }
        let request = StreamPlaybackRequest(event: currentEvent)
        let eligible = Set(additions.filter { session in
            guard !session.hasExpiredMediaLease() else { return false }
            guard let binding = session.eventBinding else { return !pending.requiresFreshBinding }
            guard let provider = StreamEventBinding.providerCode(forSessionProviderName: session.providerName) else { return false }
            return binding.matches(request: request, providerCode: provider)
        }.map(\.id))
        guard let next = nextPlayableSource(after: source, allowing: eligible),
              let index = sources.firstIndex(where: { $0.id == next.id }) else { return }
        pendingSingleDiscoveryFailure = nil
        autoFailoverCount += 1
        FottyQualityStore.shared.record(category: .playback, name: "automatic_failover", outcome: .failure,
            details: pending.qualityDetails)
        currentSourceIndex = index
        showPlaybackBanner("Switching to another source")
        loadCurrentSource()
    }

    private func appendFreshMatchChoices(_ choices: [StreamSession]) {
        guard !Task.isCancelled, exhaustedMatchLookup != nil,
              let current = LivePlaybackSourcePolicy.currentMatchForSwitch(event, in: MatchListViewModel.shared.playbackAdmissionCatalog) else { return }
        appendDiscoveredSingleSessions(choices, currentEvent: current)
    }

    func setSingleSourceDiscoveryActive(_ active: Bool, completed: Bool = true) {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single else { return }
        if active && !isCheckingAdditionalSources { singleDiscoveryContinuationRevoked = false }
        isCheckingAdditionalSources = active && !isPlaybackSessionRetired
        guard !active, let pending = pendingSingleDiscoveryFailure else { return }
        disarmSingleDiscoveryContinuation()
        guard isPlaybackSessionActive, !isPlaybackSessionRetired,
              pending.sourceID == activeSource?.id, pending.requestID == loadRequestID else { return }
        if completed { finishSingleDiscoveryFailure(pending) }
        else { cancelLoading() }
    }

    private func disarmSingleDiscoveryContinuation() {
        if exhaustedMatchLookup != nil {
            exhaustedMatchLookup?.cancel()
            exhaustedMatchLookup = nil
            isCheckingAdditionalSources = false
        }
        pendingSingleDiscoveryFailure = nil
        singleDiscoveryContinuationRevoked = true
    }

    private func finishSingleDiscoveryFailure(_ pending: PendingSingleDiscoveryFailure) {
        FottyQualityStore.shared.record(category: .playback, name: "terminal_failure", outcome: .failure,
            details: pending.qualityDetails)
        errorTitle = pending.failureKind.title
        error = pending.failureKind.terminalMessage
        showControls = true
        transition(to: .failed, phase: "Choose Broadcast Source")
    }

    /// Ownership changes metadata/control routing only, never transport intent,
    /// source ordering, or the active attempt. A retired session cannot reclaim.
    func setRemoteCommandOwnership(_ enabled: Bool) {
        guard !isPlaybackSessionRetired else { return }
        ownsRemoteCommands = enabled
        guard enabled else {
            NowPlayingManager.shared.clearNowPlaying(ownerID: remoteCommandOwnerID)
            return
        }
        NowPlayingManager.shared.configureRemoteCommands(
            ownerID: remoteCommandOwnerID,
            onPlay: { [weak self] in
                self?.requestPlayFromRemoteCommand()
            },
            onPause: { [weak self] in
                self?.requestPauseFromRemoteCommand()
            },
            onToggle: { [weak self] in
                self?.togglePlayPause()
            }
        )
        updateNowPlayingInfo()
    }

    func setViewingAudioEnabled(_ enabled: Bool) {
        guard !isPlaybackSessionRetired else { return }
        guard enabled != isViewingAudioEnabled else { applyViewingAudioState(); return }
        nativeAudioFocusGeneration = UUID()
        isViewingAudioEnabled = enabled
        if enabled {
            webAudioRevocationID = nil
            currentWebAudioRevocation = nil
        }
        if !enabled {
            cancelNativeHandoffAudioClaim()
            if hasAdoptedNativeHandoff { nativeHandoffAudioMuteHeld = true }
        } else if hasAdoptedNativeHandoff, !nativeHandoffAwaitingWebRetirement {
            queueNativeHandoffAudioClaim()
        }
        applyViewingAudioState()
    }

    func shouldManageWebAudio(inWatchTwo: Bool) -> Bool {
        inWatchTwo || !isViewingAudioEnabled
    }

    /// Captured synchronously before a pane is removed or cleaned up. A later
    /// Web promotion must wait for a noncancellable reconnect to be reconciled.
    func revokeViewingAudioForTransfer() -> NativePlayerAudioIsolation.Barrier? {
        setViewingAudioEnabled(false)
        let owners: [(source: UUID, request: UUID)]
        if viewingPlaybackContext == .single {
            owners = mountedWebOwners.map { (source: $0.value, request: $0.key) }
        } else if isUsingWebEmbed, didStartPlayback, !isPlaybackSessionRetired, let source = activeSource,
                  !(retiredWebOwner?.sourceID == source.id && retiredWebOwner?.requestID == loadRequestID) {
            owners = [(source: source.id, request: loadRequestID)]
        } else { owners = [] }
        for owner in owners {
            webAudioRevocations.removeAll { $0.acknowledged }
            let lease: WebViewingAudioRevocation
            if let pending = webAudioRevocations.first(where: { $0.sourceID == owner.source && $0.requestID == owner.request }) {
                lease = pending
                lease.id = UUID()
            } else {
                lease = WebViewingAudioRevocation(sourceID: owner.source, requestID: owner.request)
                webAudioRevocations.append(lease)
            }
            if owner.source == activeSource?.id, owner.request == loadRequestID {
                currentWebAudioRevocation = lease
                webAudioRevocationID = lease.id
            }
        }
        return nativeAudioIsolation?.request(disconnected: true)
    }

    func captureWebAudioRevocationWaiter() -> (@MainActor () async -> Bool)? {
        let leases = webAudioRevocations.filter { !$0.acknowledged }
        guard !leases.isEmpty else { return nil }
        return {
            for lease in leases {
                guard await lease.wait() else { return false }
            }
            return !Task.isCancelled
        }
    }

    func handleWebAudioRevocationAcknowledged(_ id: UUID, sourceID: UUID, requestID: UUID) {
        guard !isPlaybackSessionRetired, isPlaybackSessionActive, !isViewingAudioEnabled,
              isUsingWebEmbed, activeSource?.id == sourceID, loadRequestID == requestID,
              webAudioRevocationID == id, let lease = currentWebAudioRevocation,
              lease.id == id, lease.sourceID == sourceID, lease.requestID == requestID else { return }
        // A fresh mute receipt supersedes prior requests for this exact
        // document, never an older source/attempt still awaiting teardown.
        for pending in webAudioRevocations where pending.sourceID == sourceID && pending.requestID == requestID {
            pending.acknowledged = true
        }
    }

    private func retireNativeAudioIsolation() {
        guard let isolation = nativeAudioIsolation else { return }
        isolation.player.isMuted = true
        let barrier = isolation.request(disconnected: true)
        if player === isolation.player { nativePlayerRequiringReplacement = isolation.player }
        rememberNativeAudioRetirement(barrier)
        nativeAudioIsolation = nil
    }

    private func rememberNativeAudioRetirement(_ barrier: NativePlayerAudioIsolation.Barrier) {
        if barrier.isSatisfied { nativeAudioRetirements.removeValue(forKey: barrier.identity) }
        else {
            nativeAudioRetirements[barrier.identity] = barrier
            Task { [weak self] in
                guard await barrier.wait(), let self,
                      self.nativeAudioRetirements[barrier.identity]?.revision == barrier.revision else { return }
                self.nativeAudioRetirements.removeValue(forKey: barrier.identity)
            }
        }
    }

    func renewNativeAudioRetirementsForExplicitRetry() {
        for old in Array(nativeAudioRetirements.values) {
            rememberNativeAudioRetirement(old.renewedDisconnection())
        }
    }

    /// Diagnostic context only; does not start, pause or reconfigure any media.
    func setViewingDiagnosticRoute(_ route: FottyPlaybackDiagnosticRoute) {
        guard !isPlaybackSessionRetired else { return }
        diagnosticRoute = route
    }

    var selectedPlaybackEngine: ViewingPlaybackEngine? {
        selectedSession.map { LivePlaybackSourcePolicy.isWebEmbed($0) ? .web : .native }
    }

    var activePlaybackEngine: ViewingPlaybackEngine? {
        guard activeSession != nil else { return nil }
        return isUsingWebEmbed ? .web : .native
    }

    private func admits(_ session: StreamSession) -> Bool {
        guard case .watchTwo(let engine) = viewingPlaybackContext else { return true }
        if engine == .native, nativeHandoffSession?.id == session.id,
           !forceWebEmbedSourceIDs.contains(session.id) { return true }
        return (forceWebEmbedSourceIDs.contains(session.id) || LivePlaybackSourcePolicy.isWebEmbed(session)
            ? ViewingPlaybackEngine.web : .native) == engine
    }

    /// Only unmounted models may choose a compatible original endpoint here.
    /// Positive history is not required and no endpoint is invented or hidden.
    func prepareForViewingPlaybackContext(_ context: ViewingPlaybackContext) -> Bool {
        guard !didStartPlayback, !isPlaybackSessionRetired else { return false }
        if case .watchTwo(let engine) = context {
            if selectedPlaybackEngine != engine {
                guard let index = sessions.firstIndex(where: {
                    (LivePlaybackSourcePolicy.isWebEmbed($0) ? ViewingPlaybackEngine.web : .native) == engine
                }) else { return false }
                currentSourceIndex = index
            }
        }
        viewingPlaybackContext = context
        lastAdmittedSourceIndex = currentSourceIndex
        return selectedSession != nil
    }

    func setViewingPlaybackContext(_ context: ViewingPlaybackContext) {
        guard !isPlaybackSessionRetired, viewingPlaybackContext != context else { return }
        viewingPlaybackContext = context
        cancelNativePlaybackTransfer()
        if context == .single, isRetiringWebForNativeWatchTwo, nativeHandoffSession == nil {
            loadCurrentSource(ignoringCircuitBreaker: true)
            return
        }
        // A Web-origin source promoted in single view returns only to its own
        // exact original endpoint before entering a Web/Web pair.
        if case .watchTwo(engine: .web) = context, hasAdoptedNativeHandoff,
           selectedPlaybackEngine == .web {
            let wanted = userWantsPlayback
            withModelOwnedNativeRateCommand { player?.pause() }
            retireNativeAudioIsolation()
            nativeHandoffSession = nil
            loadCurrentSource(ignoringCircuitBreaker: true)
            userWantsPlayback = wanted
            isWebPlaybackUserPaused = !wanted
            if !wanted { webPlaybackCommand = .init(id: UUID(), shouldPlay: false) }
        }
    }

    var canRequestNativePlaybackTransfer: Bool {
        guard viewingPlaybackContext == .single, explicitNativeTransferID == nil, nativeTransferSuspensionID == nil,
              nativeHandoffTask == nil, nativeAudioIsolationBackend.isSupported,
              isPlaybackSessionActive, !isPlaybackSessionRetired,
              isUsingWebEmbed, isVideoReadyForDisplay, isPlaying, userWantsPlayback,
              !isAppBackgrounded, !isWebPictureInPictureActive, let cachedNativeCandidate else { return false }
        return cachedNativeCandidate.sourceID == activeSource?.id && cachedNativeCandidate.requestID == loadRequestID
    }

    var isNativePlaybackTransferInProgress: Bool { explicitNativeTransferID != nil }

    func requestNativePlaybackTransfer() {
        guard canRequestNativePlaybackTransfer, let cachedNativeCandidate else { return }
        // A deliberate retry may validate this candidate again; passive
        // discovery still never retries or starts a decoder.
        attemptedNativeCandidateURLs.remove("\(cachedNativeCandidate.sourceID.uuidString)|\(cachedNativeCandidate.candidate.url.absoluteString)")
        explicitNativeTransferID = UUID()
        beginNativePlaybackTransfer(cachedNativeCandidate.candidate,
            sourceID: cachedNativeCandidate.sourceID, requestID: cachedNativeCandidate.requestID)
        if nativeHandoffTask == nil { explicitNativeTransferID = nil }
    }

    func cancelNativePlaybackTransfer() {
        // Cancellation must revoke the decoder synchronously, before a new
        // Watch Two Web surface can mount—not after a polling await unwinds.
        preparingNativeTransferPlayer?.pause()
        explicitNativeTransferID = nil
        nativeHandoffTask?.cancel()
        if let sourceID = activeSource?.id {
            finishNativeHandoffPreparation(sourceID: sourceID, requestID: loadRequestID)
        }
        // The task retires its paused candidate before releasing WK suspension.
    }

    func handleNativeTransferSuspensionChanged(_ id: UUID, suspended: Bool,
        sourceID: UUID, requestID: UUID) {
        guard isPlaybackSessionActive, !isPlaybackSessionRetired,
              activeSource?.id == sourceID, loadRequestID == requestID,
              nativeTransferSuspensionID == id else { return }
        if suspended { nativeTransferAcknowledgedID = id }
        else {
            nativeTransferAcknowledgedID = nil
            if isUsingWebEmbed { cancelNativePlaybackTransfer() }
        }
    }

    func waitForNativeTransferSuspension(_ id: UUID, sourceID: UUID, requestID: UUID) async -> Bool {
        for _ in 0..<60 {
            guard nativeTransferIsCurrent(id, sourceID: sourceID, requestID: requestID) else { return false }
            if nativeTransferSuspensionAcknowledged(id, sourceID: sourceID, requestID: requestID) { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return false
    }

    func nativeTransferIsCurrent(_ id: UUID, sourceID: UUID, requestID: UUID) -> Bool {
        !Task.isCancelled && isPlaybackSessionActive && !isPlaybackSessionRetired
            && explicitNativeTransferID == id && viewingPlaybackContext == .single && userWantsPlayback
            && !isAppBackgrounded && !isWebPictureInPictureActive && isUsingWebEmbed
            && activeSource?.id == sourceID && loadRequestID == requestID
            && playbackState == .preparingNativeHandoff
    }

    func nativeTransferSuspensionAcknowledged(_ id: UUID, sourceID: UUID, requestID: UUID) -> Bool {
        nativeTransferIsCurrent(id, sourceID: sourceID, requestID: requestID)
            && nativeTransferSuspensionID == id && nativeTransferAcknowledgedID == id
    }

    @discardableResult
    func registerNativeTransferCandidate(_ candidate: AVPlayer, transferID: UUID,
        sourceID: UUID, requestID: UUID) -> Bool {
        guard candidate.currentItem != nil,
              nativeTransferIsCurrent(transferID, sourceID: sourceID, requestID: requestID) else { return false }
        preparingNativeTransferPlayer = candidate
        preparingNativeTransferPlayerID = transferID
        return true
    }

    /// Called only after candidate readiness/isolation; the Web host owns the
    /// actual suspension and must acknowledge this exact lease before Play.
    func beginNativeTransferSuspension(sourceID: UUID, requestID: UUID) -> UUID? {
        guard let id = explicitNativeTransferID,
              nativeTransferIsCurrent(id, sourceID: sourceID, requestID: requestID) else { return nil }
        nativeTransferSuspensionID = id
        return id
    }

    /// Only the explicitly selected pane may preserve native background
    /// playback for PiP. This does not change source, attempt, or user intent.
    /// The scene coordinator prevents moving focus away from an active PiP.
    func setViewingPiPOwnership(_ enabled: Bool) {
        guard !isPlaybackSessionRetired else { return }
        allowsViewingPiP = enabled
        if !enabled {
            cancelPictureInPictureAudioPreparation()
            pictureInPictureRequestID = nil
            lastPictureInPictureRequestAt = nil
        }
        if !enabled, isAppBackgrounded, !isUsingWebEmbed {
            handleAppDidMoveToBackground()
        }
    }

    private func applyViewingAudioState() {
        guard let player else { return }
        let muted = ViewingPlaybackAudioPolicy.isMuted(isEnabled: isViewingAudioEnabled,
            diagnosticMute: AppRuntime.shouldMutePlaybackForTesting,
            awaitingWebRetirement: nativeHandoffAwaitingWebRetirement,
            awaitingAudioClaim: nativeHandoffAudioMuteHeld)
        player.isMuted = muted
        player.volume = muted ? 0 : 1
    }

    /// Presentation/layout changes can mount again without creating another
    /// network monitor, source attempt, player item, or WebKit document.
    func startPlaybackIfNeeded() {
        guard !isPlaybackSessionRetired, !didStartPlayback else { return }
        didStartPlayback = true
        MediaAudioSession.configureForPlaybackIfNeeded()
        startNetworkPathMonitoring()
        if providedSessions.isEmpty {
            showNoSourcesAvailable()
        } else {
            loadCurrentSource(ignoringCircuitBreaker: true)
        }
        scheduleAutoHide()
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
        if state != .playing(.native) { singleContinuityTask?.cancel(); singleContinuityTask = nil }
        if state == .failed || state == .idle {
            invalidateSingleNetworkRecovery()
            if viewingPlaybackContext == .single {
                singleNativePreparation = nil
                deferredSingleNativePreparation = nil
            }
        }
        // A delayed reload belongs only to this recovery state. Decoded
        // progress, explicit pause, native handoff and terminal transitions
        // invalidate it before a late timer can replace working playback.
        if state != .recovering(.webEmbed) { cancelPendingWebRetry() }
        switch state {
        case .paused, .idle:
            playbackIntervals.finishStall(playbackIntervals.identity, now: timing.monotonicNow(), completion: .interrupted)?.record()
        case .failed:
            playbackIntervals.finishStall(playbackIntervals.identity, now: timing.monotonicNow(), completion: .failed)?.record()
        default: break
        }
        playbackState = state
        if let phase { connectionPhase = phase }
        lastPlaybackStateChangeAt = Date()
    }

    func showNoSourcesAvailable() {
        errorTitle = "No Sources Available"
        error = viewingPlaybackContext == .single && event.isBroadcastChannel
            ? "No playable stream is available for this channel right now."
            : "No playable stream is available for this match right now."
        transition(to: .failed, phase: "No Sources")
        showControls = true
    }

    func cancelLoading() {
        disarmSingleDiscoveryContinuation()
        pausedDescriptorNegotiationSourceID = nil
        if usesSingleStreamRanking, viewingPlaybackContext == .single { shouldResumeAfterForeground = false }
        cancelAudioPreparation()
        loadTask?.cancel()
        cancelNativePlaybackTransfer()
        loadRequestID = UUID()
        stopPlaybackWatchdog()
        transition(to: .failed, phase: "Cancelled")
    }

    func togglePlayPause() {
        if pendingSingleDiscoveryFailure != nil {
            disarmSingleDiscoveryContinuation()
            userWantsPlayback = false
            shouldResumeAfterForeground = false
            withModelOwnedNativeRateCommand { player?.pause() }
            transition(to: .paused(isUsingWebEmbed ? .webEmbed : .native), phase: "Paused")
            updateNowPlayingInfo()
            return
        }
        // Failed attempts require the existing explicit Retry/source path.
        // Play must not publish a playing state that preparation will reject.
        guard error == nil, playbackState != .failed else { return }
        if isUsingWebEmbed {
            let shouldPlay = !isPlaying
            userWantsPlayback = shouldPlay
            isWebPlaybackUserPaused = !shouldPlay
            if !shouldPlay { cancelNativePlaybackTransfer() }
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
        if isPlaying || hasPendingNativePlay {
            if usesSingleStreamRanking && viewingPlaybackContext == .single,
               descriptorNegotiationRequestID == loadRequestID {
                // Keep this lookup owned. Play can rejoin it before it completes;
                // its existing intent guard discards a result arriving while paused.
                pausedDescriptorNegotiationSourceID = activeSource?.id
            } else if let preparation = singleNativePreparation, usesSingleStreamRanking,
                      viewingPlaybackContext == .single, preparation.requestID == loadRequestID,
                      preparation.sourceID == activeSource?.id {
                suspendSingleNativePreparation(preparation, phase: "Paused", resumeAfterForeground: false)
            }
            cancelAudioPreparation()
            userWantsPlayback = false
            shouldResumeAfterForeground = false
            pendingRetryAfterNetworkRestore = false
            stallValidationTask?.cancel()
            foregroundResumeValidationTask?.cancel()
            withModelOwnedNativeRateCommand { player?.pause() }
            transition(to: .paused(.native), phase: "Paused")
            stopPlaybackWatchdog()
        } else {
            userWantsPlayback = true
            if resumeDeferredSingleNativePreparationIfNeeded() {
                updateNowPlayingInfo()
                scheduleAutoHide()
                return
            }
            if let sourceID = pausedDescriptorNegotiationSourceID, activeSource?.id == sourceID {
                if descriptorNegotiationRequestID == loadRequestID {
                    // Resume the same in-flight negotiation. Explicit Play
                    // must not queue audio for a player not yet prepared.
                    transition(to: .connecting(.native), phase: "Connecting...")
                } else {
                    // A completed response was discarded while paused. Only
                    // explicit Play reopens this source's negotiation; the
                    // automatic native retry/failover budgets stay unchanged.
                    descriptorRefreshAttempts.remove(sourceID)
                    pendingDescriptorRefreshSourceID = sourceID
                    loadCurrentSource(ignoringCircuitBreaker: true)
                }
                updateNowPlayingInfo()
                scheduleAutoHide()
                return
            }
            if let player { MediaAudioSession.configureNativeBackgroundPlayback(player) }
            let boundedResume = usesSingleStreamRanking && viewingPlaybackContext == .single
            transition(to: boundedResume ? .recovering(.native) : .playing(.native),
                       phase: boundedResume ? "Resuming" : "Playing")
            queueAudioPreparation(for: player) {
                self.withModelOwnedNativeRateCommand { self.player?.play() }
                if let source = self.activeSource {
                    if boundedResume, let player = self.player, let item = player.currentItem {
                        self.beginSingleNativeResume(for: source, player: player, item: item)
                    } else { self.startPlaybackWatchdog(for: source) }
                }
            }
        }
        updateNowPlayingInfo()
        scheduleAutoHide()
    }

    func toggleFillMode() { isFillMode.toggle(); scheduleAutoHide() }

    var canShowNativeFullscreen: Bool {
        !isPlaybackSessionRetired && !isUsingWebEmbed && error == nil && isVideoReadyForDisplay
            && player?.currentItem != nil && player?.currentItem?.status != .failed
            && !isPictureInPictureActive && nativeFullscreen == nil
    }

    /// Presentation borrows the existing transport. Never load, seek or Play
    /// here: entering fullscreen while paused must remain paused.
    func beginNativeFullscreen() {
        guard canShowNativeFullscreen, let player, let item = player.currentItem else { return }
        nativeFullscreenIsPresented = false
        nativeFullscreen = NativeFullscreenSession(player: player, item: item,
            attemptID: loadRequestID, sourceID: activeSource?.id)
    }

    func commitNativeFullscreenPresentation(_ session: NativeFullscreenSession) {
        guard ownsNativeFullscreen(session), !session.isClosing else { return }
        nativeFullscreenIsPresented = true
    }

    func ownsNativeFullscreen(_ session: NativeFullscreenSession) -> Bool {
        isPlaybackSessionActive && !session.isRetired && nativeFullscreen === session && !isUsingWebEmbed
            && loadRequestID == session.attemptID && activeSource?.id == session.sourceID
            && player === session.player && player?.currentItem === session.item
    }

    func endNativeFullscreen(_ session: NativeFullscreenSession) {
        guard nativeFullscreen === session else { return }
        retireNativeFullscreenForTransportChange()
    }

    /// Revoke the lease before its exact controller detaches. Dismissal/KVO
    /// callbacks must not impersonate Pause or change a replacement attempt.
    private func retireNativeFullscreenForTransportChange() {
        guard let session = nativeFullscreen else { return }
        nativeFullscreenIsPresented = false
        nativeFullscreen = nil
        session.retire()
    }

    /// Only an explicit rate command on the current borrowed player changes
    /// intent. Buffering, interruption and background KVO are not user Pause.
    func handleFullscreenRateCommand(_ rate: Float, reason: AVPlayer.RateDidChangeReason,
                                     session: NativeFullscreenSession) {
        guard ownsNativeFullscreen(session), error == nil, rate.isFinite,
              session.controlsAreActive,
              session.permitsTransportObservation(pictureInPictureActive: isPictureInPictureActive),
              ownedNativeRateCommandDepth == 0,
              reason == .setRateCalled, !isAppBackgrounded || isPictureInPictureActive else { return }
        if rate == 0 {
            userWantsPlayback = false
            shouldResumeAfterForeground = false
            pendingRetryAfterNetworkRestore = false
            cancelAudioPreparation()
            stallValidationTask?.cancel(); foregroundResumeValidationTask?.cancel()
            transition(to: .paused(.native), phase: "Paused")
            stopPlaybackWatchdog()
        } else {
            userWantsPlayback = true
            shouldResumeAfterForeground = false
            // The system already issued Play; do not issue it again or seek.
            if nativeHandoffAudioMuteHeld { queueNativeHandoffAudioClaim(explicitAVKitPlay: true) }
            // Pause stopped recovery. Play may remain waiting without another
            // status/error notification, so renew bounded observation now.
            let playing = session.player.timeControlStatus == .playing
            transition(to: playing ? .playing(.native) : .recovering(.native),
                       phase: playing ? "Playing" : "Resuming")
            if !isAppBackgrounded, let source = activeSource {
                if usesSingleStreamRanking && viewingPlaybackContext == .single {
                    beginSingleNativeResume(for: source, player: session.player, item: session.item)
                } else {
                    startPlaybackWatchdog(for: source)
                    scheduleNativeResumeValidation(for: source, player: session.player, item: session.item,
                        requestID: session.attemptID, reason: "Playback resume stalled.")
                }
            }
        }
        updateNowPlayingInfo()
    }

    /// Rate notifications are synchronous on the command's MainActor. Mark our
    /// own calls so recovery/teardown cannot impersonate a system-control tap.
    func withModelOwnedNativeRateCommand(_ command: () -> Void) {
        ownedNativeRateCommandDepth += 1
        defer { ownedNativeRateCommandDepth -= 1 }
        command()
    }

    func requestPlayFromRemoteCommand() {
        guard !isPlaying, !hasPendingNativePlay else { return }
        togglePlayPause()
    }

    func requestPauseFromRemoteCommand() {
        guard isPlaying || hasPendingNativePlay else { return }
        togglePlayPause()
    }

    func togglePictureInPicture() {
        requestPictureInPicture(reason: "Picture in Picture")
    }

    func handlePictureInPictureActivityChanged(_ active: Bool, isBackgrounded: Bool = false) {
        logPictureInPictureState(active ? "pip_active" : "pip_inactive")
        isPictureInPictureActive = active
        if active, allowsViewingPiP, let player {
            MediaAudioSession.configureNativeBackgroundPlayback(player)
            if playbackState == .paused(.native), shouldResumeAfterForeground, userWantsPlayback {
                shouldResumeAfterForeground = false
                transition(to: .playing(.native), phase: "PiP Active")
                updateNowPlayingInfo()
                queueAudioPreparation(for: player) { self.withModelOwnedNativeRateCommand { player.play() } }
            } else {
                queuePictureInPictureAudioPreparation(for: player)
            }
        }
        if !active {
            lastPictureInPictureRequestAt = nil
        }
        connectionPhase = active ? "PiP Active" : "Playing"
        if active, !allowsViewingPiP, isBackgrounded || isAppBackgrounded {
            handleAppDidMoveToBackground()
        } else if !active, isBackgrounded || isAppBackgrounded, allowsViewingPiP {
            pauseNativePlaybackAfterPictureInPictureEnds()
        }
    }

    func handleWebPictureInPictureActivityChanged(_ active: Bool, sourceID: UUID, requestID: UUID) {
        guard activeSource?.id == sourceID, loadRequestID == requestID else { return }
        handleWebPictureInPictureActivityChanged(active)
    }

    func handleWebPictureInPictureActivityChanged(_ active: Bool) {
        guard isPlaybackSessionActive else { return }
        if active {
            guard isUsingWebEmbed else { return }
            livePlayerLifecycleLogger.info(
                "event=web_pip_active background=\(self.isAppBackgrounded, privacy: .public)"
            )
            webBackgroundSuspensionTask?.cancel()
            webBackgroundSuspensionTask = nil
            nativeHandoffTask?.cancel()
            nativeHandoffTask = nil
            if playbackState == .preparingNativeHandoff {
                transition(to: .playing(.webEmbed), phase: "PiP Active")
            }
            isWebPictureInPictureActive = true
            isPictureInPictureActive = true
            shouldSuspendWebPlayback = false
            if shouldResumeAfterForeground, playbackState == .paused(.webEmbed) {
                transition(to: .playing(.webEmbed), phase: "PiP Active")
            } else {
                connectionPhase = "PiP Active"
            }
            shouldResumeAfterForeground = false
            updateNowPlayingInfo()
            return
        }

        guard isWebPictureInPictureActive else { return }
        livePlayerLifecycleLogger.info(
            "event=web_pip_inactive background=\(self.isAppBackgrounded, privacy: .public)"
        )
        isWebPictureInPictureActive = false
        isPictureInPictureActive = false
        if isAppBackgrounded {
            shouldResumeAfterForeground = userWantsPlayback && isPlaying
            scheduleWebBackgroundSuspension()
        } else {
            shouldSuspendWebPlayback = false
            connectionPhase = isPlaying ? "Playing" : "Paused"
        }
        updateNowPlayingInfo()
    }

    func handlePictureInPictureFailure(_ message: String, isBackgrounded: Bool = false) {
        cancelPictureInPictureAudioPreparation()
        logPictureInPictureState("pip_failed")
        isPictureInPictureActive = false
        lastPictureInPictureRequestAt = nil
        connectionPhase = message
        if isBackgrounded || isAppBackgrounded {
            pauseNativePlaybackAfterPictureInPictureEnds()
        }
    }

    func handlePictureInPictureAvailabilityChanged(_ available: Bool, isBackgrounded: Bool = false) {
        isPictureInPictureAvailable = available
        if !available { cancelPictureInPictureAudioPreparation() }
        if !available, !isPictureInPictureActive {
            lastPictureInPictureRequestAt = nil
            if isBackgrounded || isAppBackgrounded {
                handleAppDidMoveToBackground()
            }
        }
    }

    private func requestPictureInPicture(reason: String) {
        guard allowsViewingPiP, isPictureInPictureAvailable, !isUsingWebEmbed else {
            connectionPhase = "PiP Unavailable"
            scheduleAutoHide()
            return
        }
        if let player {
            MediaAudioSession.configureNativeBackgroundPlayback(player)
            queuePictureInPictureAudioPreparation(for: player, reason: reason)
            return
        }
        publishPictureInPictureRequest(reason: reason)
    }

    private func publishPictureInPictureRequest(reason: String) {
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
        let generation = UUID()
        controlsHideGeneration = generation
        if viewingPlaybackContext == .single, controlsNeedAccessibilityVisibility() {
            hideTask = nil
            showControls = true
            return
        }
        let request = loadRequestID
        let source = activeSource?.id
        let delay = isUsingWebEmbed ? LivePlaybackPolicy.webControlAutoHideSeconds : 10
        hideTask = Task {
            do { try await timing.wait(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, controlsHideGeneration == generation,
                  loadRequestID == request, activeSource?.id == source,
                  isPlaybackSessionActive, showControls, isPlaying, error == nil,
                  !isLoading, playbackStagnationTicks == 0 else { return }
            guard !showSourceSelector else { return }
            guard viewingPlaybackContext != .single || !controlsNeedAccessibilityVisibility() else { return }
            withAnimation { showControls = false }
        }
    }

    func refreshPlaybackControlsAccessibility() {
        guard viewingPlaybackContext == .single, isPlaybackSessionActive, !isPlaybackSessionRetired else { return }
        scheduleAutoHide()
    }

    func resetFailoverTracking() {
        disarmSingleDiscoveryContinuation()
        cancelPendingWebRetry()
        cancelNativePlaybackTransfer()
        nativeHandoffTask = nil
        nativeTransferTaskID = nil
        retireNativeAudioIsolation()
        // An admitted native pair may retry its captured current source, but
        // must not silently turn that pane back into a Web sibling.
        if viewingPlaybackContext != .watchTwo(engine: .native) {
            nativeHandoffSession = nil
            nativeWatchTwoDelivery = nil
        }
        attemptedNativeCandidateURLs.removeAll()
        failedSourceIDs.removeAll(); autoFailoverCount = 0
        webStartupRetryAttemptsBySource.removeAll(); webStallRetryAttemptsBySource.removeAll()
        nativeStartupRetryAttemptsBySource.removeAll()
        descriptorRefreshAttempts.removeAll()
        // A user retry resets budgets, not the observed fact that a delivery
        // froze. Only a successful fresh descriptor may clear that requirement.
        pausedDescriptorNegotiationSourceID = nil
        pendingDescriptorRefreshSourceID = nil
        forceWebEmbedSourceIDs.removeAll(); lastFailureReason = nil
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        livePlayerLifecycleLogger.info(
            "scene_phase=\(String(describing: phase), privacy: .public) pip=\(self.isPictureInPictureActive, privacy: .public) native=\(!self.isUsingWebEmbed, privacy: .public)"
        )
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
        isAppBackgrounded = true
        singleContinuityTask?.cancel(); singleContinuityTask = nil
        if pendingSingleDiscoveryFailure != nil { cancelLoading() }
        nativeForegroundObservationLease = nil
        cancelPendingWebRetry()
        foregroundResumeValidationTask?.cancel()

        if isUsingWebEmbed {
            stopPlaybackWatchdog()
            if isWebPictureInPictureActive {
                shouldResumeAfterForeground = false
                shouldSuspendWebPlayback = false
                connectionPhase = "PiP Active"
                return
            }

            shouldResumeAfterForeground = isPlaying
            if isPlaying {
                // WebKit reports PiP at almost the same moment iOS backgrounds
                // the scene. Give that event a small window to arrive before
                // suspending the owning document.
                scheduleWebBackgroundSuspension()
            } else {
                shouldSuspendWebPlayback = true
            }
            return
        }

        if deferSingleNativePreparationForBackgroundIfNeeded() { return }

        if shouldKeepPlaybackAliveForPictureInPicture {
            if viewingPlaybackContext == .single, diagnosticRoute == .single,
               let player, let item = player.currentItem, let source = activeSource {
                nativeForegroundObservationLease = .init(player: player, item: item,
                    sourceID: source.id, requestID: loadRequestID)
            }
            shouldResumeAfterForeground = false
            if let player { MediaAudioSession.configureNativeBackgroundPlayback(player) }
            if let player { queuePictureInPictureAudioPreparation(for: player) }
            connectionPhase = isPictureInPictureActive ? "PiP Active" : "Starting PiP"
            return
        }

        shouldResumeAfterForeground = userWantsPlayback
            && (shouldResumeAfterForeground || isPlaying || isLoading || hasPendingNativePlay)
        cancelAudioPreparation()

        if isPlaying {
            withModelOwnedNativeRateCommand { player?.pause() }
            transition(to: .paused(.native), phase: "Paused (Background)")
        }
        stopPlaybackWatchdog()
    }

    private var shouldKeepPlaybackAliveForPictureInPicture: Bool {
        guard allowsViewingPiP else { return false }
        if isPictureInPictureActive { return true }
        guard isPictureInPictureAvailable,
              !isUsingWebEmbed,
              isPlaying,
              error == nil else {
            return false
        }
        // The scene can reach background before AVKit's PiP delegate callback.
        // Once a native player is PiP-capable, let AVKit own that transition
        // instead of pausing the underlying player during this callback race.
        if isAppBackgrounded { return player?.currentItem != nil }
        guard let lastPictureInPictureRequestAt else { return false }
        return Date().timeIntervalSince(lastPictureInPictureRequestAt) < 10
    }

    private func scheduleWebBackgroundSuspension() {
        webBackgroundSuspensionTask?.cancel()
        let expectedRequestID = loadRequestID
        webBackgroundSuspensionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.webBackgroundSuspensionDelay()
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.isPlaybackSessionActive,
                  self.isAppBackgrounded,
                  !self.isWebPictureInPictureActive,
                  self.isUsingWebEmbed,
                  self.loadRequestID == expectedRequestID else { return }
            self.shouldSuspendWebPlayback = true
            if self.isPlaying {
                self.shouldResumeAfterForeground = true
                self.transition(to: .paused(.webEmbed), phase: "Paused (Background)")
            }
            self.webBackgroundSuspensionTask = nil
            self.updateNowPlayingInfo()
        }
    }

    var keepsPlaybackAliveInBackground: Bool {
        shouldKeepPlaybackAliveForPictureInPicture
    }

    private func pauseNativePlaybackAfterPictureInPictureEnds() {
        cancelAudioPreparation()
        isAppBackgrounded = true
        shouldResumeAfterForeground = userWantsPlayback && isPlaying
        guard isPlaying, !isUsingWebEmbed else {
            stopPlaybackWatchdog()
            return
        }
        withModelOwnedNativeRateCommand { player?.pause() }
        transition(to: .paused(.native), phase: "Paused (Background)")
        stopPlaybackWatchdog()
        updateNowPlayingInfo()
    }

    func handleNativeTimeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard isPlaybackSessionActive, !isUsingWebEmbed, error == nil else { return }
        // A queued AVKit observation may arrive after the background pause.
        // Nonowners cannot turn that observation into PiP Play/user intent.
        if isAppBackgrounded, !allowsViewingPiP {
            if status == .playing { withModelOwnedNativeRateCommand { player?.pause() } }
            return
        }
        livePlayerLifecycleLogger.info(
            "time_control=\(status.rawValue, privacy: .public) pip=\(self.isPictureInPictureActive, privacy: .public) background=\(self.isAppBackgrounded, privacy: .public) proxy=\(self.streamProxy != nil, privacy: .public) connections=\(self.streamProxy?.activeConnectionCount ?? 0, privacy: .public)"
        )
        switch playbackState {
        case .playing(.native), .recovering(.native), .paused(.native):
            break
        case .idle, .connecting, .preparingNativeHandoff, .playing(.webEmbed),
             .recovering(.webEmbed), .paused(.webEmbed), .failed:
            return
        }

        // The explicit resume observer requires advancing video. Transport KVO
        // cannot publish Playing or start a second timer during that budget.
        if viewingPlaybackContext == .single, singleResumeOwner?.attempt == loadRequestID,
           foregroundResumeValidationTask?.isCancelled == false, userWantsPlayback,
           !isAppBackgrounded { return }
        switch status {
        case .playing:
            // AVKit's PiP Play is a new explicit action; other delayed status
            // callbacks must not revoke a pause from Fotty's controls.
            if isPictureInPictureActive { userWantsPlayback = true }
            guard userWantsPlayback else { withModelOwnedNativeRateCommand { player?.pause() }; return }
            if let identity = intervalIdentity {
                playbackIntervals.finishStall(identity, now: timing.monotonicNow(), completion: .transportPlaying)?.record()
            }
            shouldResumeAfterForeground = false
            transition(
                to: .playing(.native),
                phase: isPictureInPictureActive ? "PiP Active" : "Playing"
            )
            if isPictureInPictureActive, nativeHandoffAudioMuteHeld { queueNativeHandoffAudioClaim() }
            if let source = activeSource, !isAppBackgrounded {
                startPlaybackWatchdog(for: source)
            }
        case .paused:
            singleContinuityTask?.cancel(); singleContinuityTask = nil
            // Initial/KVO callbacks can still observe the old paused player
            // while accepted Play is awaiting platform activation. This is not
            // a second user Pause; explicit controls revoke the pending task.
            if hasPendingNativePlay { return }
            // A failed item also becomes paused. That transport observation is
            // not a PiP Pause tap; explicit AVKit rate commands still own user
            // intent, and healthy-item PiP pause observations are unchanged.
            let hasFatalItemFailure = viewingPlaybackContext == .single
                && (player?.currentItem?.status == .failed
                    || nativeItemFailureObservation?.matches(item: player?.currentItem,
                        sourceID: activeSource?.id, requestID: loadRequestID) == true)
            if isPictureInPictureActive, !hasFatalItemFailure { userWantsPlayback = false }
            transition(to: .paused(.native), phase: isAppBackgrounded ? "Paused (Background)" : "Paused")
            shouldResumeAfterForeground = userWantsPlayback && isAppBackgrounded && !isPictureInPictureActive
            stopPlaybackWatchdog()
        case .waitingToPlayAtSpecifiedRate:
            singleContinuityTask?.cancel(); singleContinuityTask = nil
            if userWantsPlayback, let identity = intervalIdentity {
                playbackIntervals.beginStall(identity, now: timing.monotonicNow())
            }
            return
        @unknown default:
            return
        }
        updateNowPlayingInfo()
    }

    private func logPictureInPictureState(_ event: String) {
        livePlayerLifecycleLogger.info(
            "event=\(event, privacy: .public) time_control=\(self.player?.timeControlStatus.rawValue ?? -1, privacy: .public) rate=\(self.player?.rate ?? -1, privacy: .public) background=\(self.isAppBackgrounded, privacy: .public) proxy=\(self.streamProxy != nil, privacy: .public) connections=\(self.streamProxy?.activeConnectionCount ?? 0, privacy: .public)"
        )
    }

    private func handleAppDidBecomeActive() {
        let observationLease = nativeForegroundObservationLease
        nativeForegroundObservationLease = nil
        isAppBackgrounded = false
        webBackgroundSuspensionTask?.cancel()
        webBackgroundSuspensionTask = nil
        shouldSuspendWebPlayback = false
        guard isPlaybackSessionActive else { return }
        if resumeDeferredSingleNativePreparationIfNeeded() { return }
        if recoverObservedBackgroundNativeFailure() { return }
        restoreSingleNativeObservationAfterForeground(observationLease)
        guard shouldResumeAfterForeground, userWantsPlayback else { return }
        shouldResumeAfterForeground = false
        if isUsingWebEmbed {
            queueAudioPreparation(for: nil) {}
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
        transition(to: .recovering(.native), phase: "Resuming")
        queueAudioPreparation(for: player) {
            self.withModelOwnedNativeRateCommand { player.play() }
            self.startPlaybackWatchdog(for: source)
            self.scheduleNativeResumeValidation(for: source, player: player, item: item,
                                                requestID: requestID, reason: "Resume stalled.")
        }
    }

    private func deferSingleNativePreparationForBackgroundIfNeeded() -> Bool {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single,
              isAppBackgrounded, userWantsPlayback, let preparation = singleNativePreparation,
              preparation.requestID == loadRequestID, preparation.sourceID == activeSource?.id,
              !shouldKeepPlaybackAliveForPictureInPicture else { return false }
        suspendSingleNativePreparation(preparation, phase: "Paused (Background)", resumeAfterForeground: true)
        return true
    }

    private func suspendSingleNativePreparation(_ preparation: SingleNativePreparation,
                                                 phase: String, resumeAfterForeground: Bool) {
        // The old relay has already retired. Do not keep its still-ready item
        // around for foreground native-resume, even if this load began while
        // the app was already backgrounded and no new scene event will arrive.
        deferredSingleNativePreparation = preparation
        singleNativePreparation = nil
        loadTask?.cancel()
        loadTask = nil
        if descriptorNegotiationRequestID == preparation.requestID { descriptorNegotiationRequestID = nil }
        cancelAudioPreparation()
        pausedDescriptorNegotiationSourceID = nil
        shouldResumeAfterForeground = resumeAfterForeground
        withModelOwnedNativeRateCommand { player?.pause() }
        player?.replaceCurrentItem(with: nil)
        streamProxy?.stop(); streamProxy = nil
        stopPlaybackWatchdog()
        transition(to: .paused(.native), phase: phase)
    }

    /// Restart only the preparation that backgrounding actually interrupted.
    /// Pause retains it without Play; cancellation/replacement revoke its lease.
    private func resumeDeferredSingleNativePreparationIfNeeded() -> Bool {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single,
              let preparation = deferredSingleNativePreparation else { return false }
        guard isPlaybackSessionActive, !isPlaybackSessionRetired,
              preparation.requestID == loadRequestID, preparation.sourceID == activeSource?.id,
              !isUsingWebEmbed else {
            deferredSingleNativePreparation = nil
            return false
        }
        guard userWantsPlayback, !isAppBackgrounded else { return true }
        deferredSingleNativePreparation = nil
        shouldResumeAfterForeground = false
        if preparation.needsDescriptorRefresh {
            // A cancelled lookup published no response. Reopen that owned
            // negotiation; do not replenish the source's transport retry count.
            descriptorRefreshAttempts.remove(preparation.sourceID)
            pendingDescriptorRefreshSourceID = preparation.sourceID
        }
        loadCurrentSource(ignoringCircuitBreaker: true)
        return true
    }

    private func restoreSingleNativeObservationAfterForeground(_ lease: NativeForegroundObservationLease?) {
        guard let lease, viewingPlaybackContext == .single, diagnosticRoute == .single,
              isPlaybackSessionActive, !isPlaybackSessionRetired, !isAppBackgrounded,
              !isUsingWebEmbed, userWantsPlayback, isPlaying, error == nil,
              !pendingRetryAfterNetworkRestore,
              loadRequestID == lease.requestID, initialNativeStartupRequestID != lease.requestID,
              let source = activeSource, source.id == lease.sourceID,
              let player = lease.player, self.player === player,
              let item = lease.item, player.currentItem === item, item.status != .failed else { return }
        // A background soft stall can consume the old watchdog while its
        // validator correctly refuses background recovery. PiP intentionally
        // clears shouldResumeAfterForeground, so renew observation separately.
        // Current intent admits an explicit PiP Pause→Play, never an old Pause.
        startPlaybackWatchdog(for: source)
    }

    func startNetworkPathMonitoring() {
        guard !isPlaybackSessionRetired else { return }
        networkPathObserver.start { [weak self] reachable in self?.handleNetworkReachabilityChange(reachable) }
    }

    func stopNetworkPathMonitoring() { networkPathObserver.stop() }

    private func invalidateSingleNetworkRecovery() {
        guard viewingPlaybackContext == .single else { return }
        networkLossTask?.cancel(); networkLossTask = nil
        singleNetworkRecoveryOwner = nil
        pendingRetryAfterNetworkRestore = false
    }

    private func ownsSingleNetworkRecovery() -> Bool {
        guard viewingPlaybackContext == .single else { return true }
        guard isPlaybackSessionActive, !isPlaybackSessionRetired, error == nil,
              playbackState != .failed, userWantsPlayback else { return false }
        guard let owner = singleNetworkRecoveryOwner else { return true }
        return owner.sourceID == activeSource?.id && owner.requestID == loadRequestID
            && owner.intentID == playbackIntentRevision
    }

    private func captureSingleNetworkRecovery() {
        guard viewingPlaybackContext == .single, ownsSingleNetworkRecovery(), let source = activeSource else { return }
        singleNetworkRecoveryOwner = .init(sourceID: source.id, requestID: loadRequestID, intentID: playbackIntentRevision)
    }

    /// Internal so the continuity policy can be regression-tested without
    /// constructing a real `NWPathMonitor` or changing the device network.
    func handleNetworkReachabilityChange(_ reachable: Bool) {
        let was = isNetworkReachable; isNetworkReachable = reachable
        guard isPlaybackSessionActive else { return }
        if viewingPlaybackContext == .single, !ownsSingleNetworkRecovery() {
            invalidateSingleNetworkRecovery()
            return
        }
        if !reachable {
            let singleRecovery = viewingPlaybackContext == .single
            if singleRecovery { singleContinuityTask?.cancel(); singleContinuityTask = nil }
            cancelPendingWebRetry()
            guard was else { return }
            captureSingleNetworkRecovery()
            let requestID = loadRequestID
            if singleRecovery { networkLossTask?.cancel() }
            let loss = Task {
                do {
                    if singleRecovery { try await timing.wait(for: PlaybackProgressPolicy.networkLossGrace) }
                    else { try await Task.sleep(for: PlaybackProgressPolicy.networkLossGrace) }
                } catch { return }
                guard !Task.isCancelled, self.isPlaybackSessionActive,
                      self.loadRequestID == requestID, !self.isAppBackgrounded,
                      self.userWantsPlayback,
                      !self.isWebPlaybackUserPaused,
                      !self.isNetworkReachable, !singleRecovery || self.ownsSingleNetworkRecovery() else { return }
                pendingRetryAfterNetworkRestore = true
                transition(to: .recovering(isUsingWebEmbed ? .webEmbed : .native), phase: "Waiting For Network")
                stopPlaybackWatchdog()
            }
            if singleRecovery { networkLossTask = loss }
            return
        }
        guard !was, pendingRetryAfterNetworkRestore, !sources.isEmpty else { return }
        pendingRetryAfterNetworkRestore = false
        resumeCurrentAttemptAfterNetworkRestore()
    }

    private func resumeCurrentAttemptAfterNetworkRestore() {
        guard isPlaybackSessionActive, !isAppBackgrounded,
              userWantsPlayback, !isWebPlaybackUserPaused, ownsSingleNetworkRecovery(),
              let source = activeSource else { return }

        if usesSingleStreamRanking, viewingPlaybackContext == .single,
           let preparation = singleNativePreparation,
           preparation.requestID == loadRequestID, preparation.sourceID == source.id {
            suspendSingleNativePreparation(preparation, phase: "Reconnecting...", resumeAfterForeground: false)
            _ = resumeDeferredSingleNativePreparationIfNeeded()
            return
        }

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
        MediaAudioSession.configureNativeBackgroundPlayback(player)
        transition(to: .recovering(.native), phase: "Reconnecting...")
        queueAudioPreparation(for: player) {
            self.withModelOwnedNativeRateCommand { player.play() }
            self.startPlaybackWatchdog(for: source)
            self.scheduleNativeResumeValidation(for: source, player: player, item: item,
                                                requestID: requestID, reason: "Network recovery stalled.")
        }
    }

    /// Explicit single-player Play gets one recovery budget, not the general
    /// watchdog's startup grace + repeated samples + second stall timeout.
    /// AVKit and inline controls retain the same player/item/attempt.
    func beginSingleNativeResume(for source: StreamSource, player expectedPlayer: AVPlayer,
                                 item: AVPlayerItem) {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single,
              userWantsPlayback, isPlaybackSessionActive, !isAppBackgrounded,
              player === expectedPlayer, expectedPlayer.currentItem === item,
              activeSource?.id == source.id, error == nil else { return }
        foregroundResumeValidationTask?.cancel()
        stallValidationTask?.cancel()
        stopPlaybackWatchdog()
        let token = UUID(), request = loadRequestID, intent = nativeWatchTwoIntentID
        singleResumeOwner = (token, request)
        let observation = SingleNativeResumeObservation(position: expectedPlayer.currentTime().seconds)
        transition(to: .recovering(.native), phase: "Resuming")
        recordSingleResume("started", player: expectedPlayer, item: item, elapsed: 0)
        foregroundResumeValidationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if singleResumeOwner?.token == token { singleResumeOwner = nil } }
            let began = timing.monotonicNow()
            for sample in 0...16 {
                guard !Task.isCancelled, singleResumeOwner?.token == token,
                      viewingPlaybackContext == .single, usesSingleStreamRanking,
                      isPlaybackSessionActive, !isAppBackgrounded, userWantsPlayback,
                      error == nil, loadRequestID == request, activeSource?.id == source.id,
                      nativeWatchTwoIntentID == intent, player === expectedPlayer,
                      expectedPlayer.currentItem === item else { return }
                let elapsed = max(timing.monotonicNow() - began, Double(sample) * 0.5)
                let position = expectedPlayer.currentTime().seconds
                // A seek's clock jump is not playback. Establish a new baseline
                // only after its completion and require subsequent advancement.
                if observation.needsBaseline {
                    observation.baseline = position
                    observation.needsBaseline = false
                } else if !observation.seekPending,
                          NativePlaybackVideoPolicy.hasDisplayedProgress(isReadyForDisplay: isVideoReadyForDisplay,
                              startSeconds: observation.baseline, currentSeconds: position),
                          item.status == .readyToPlay {
                    observeSingleNativeResumeProgress(player: expectedPlayer, item: item, sourceID: source.id,
                        requestID: request, intentID: intent, startSeconds: observation.baseline, currentSeconds: position)
                    recordSingleResume("resumed", player: expectedPlayer, item: item, elapsed: elapsed)
                    singleResumeOwner = nil
                    transition(to: .playing(.native), phase: "Playing")
                    startPlaybackWatchdog(for: source)
                    observeSingleContinuity(source)
                    return
                }
                if !observation.seekRequested,
                   let target = SingleNativeResumeWindowPolicy.catchUpTarget(position: position,
                       isLive: item.duration.isIndefinite,
                       ranges: item.seekableTimeRanges.map { ($0.timeRangeValue.start.seconds, $0.timeRangeValue.end.seconds) }) {
                    observation.seekRequested = true; observation.seekPending = true
                    recordSingleResume("outside_window", player: expectedPlayer, item: item, elapsed: elapsed)
                    expectedPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                        Task { @MainActor in
                            guard let self, self.singleResumeOwner?.token == token,
                                  self.viewingPlaybackContext == .single,
                                  self.loadRequestID == request, self.nativeWatchTwoIntentID == intent,
                                  self.userWantsPlayback, !self.isAppBackgrounded,
                                  self.player === expectedPlayer, expectedPlayer.currentItem === item else { return }
                            observation.seekPending = false
                            observation.needsBaseline = true
                            self.recordSingleResume(finished ? "window_rejoined" : "seek_incomplete",
                                player: expectedPlayer, item: item, elapsed: max(0, self.timing.monotonicNow() - began))
                        }
                    }
                }
                // Preserve AVPlayer's normal buffering policy. Only a resumed
                // live item with actual buffered data gets one bounded nudge.
                if elapsed >= 2, !observation.immediatePlayRequested, !observation.seekPending,
                   item.status == .readyToPlay, item.duration.isIndefinite,
                   expectedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                   expectedPlayer.reasonForWaitingToPlay == .toMinimizeStalls,
                   item.loadedTimeRanges.contains(where: { range in
                       let time = range.timeRangeValue
                       return position.isFinite && time.start.seconds <= position && time.end.seconds >= position + 1
                   }) {
                    observation.immediatePlayRequested = true
                    recordSingleResume("buffered_play", player: expectedPlayer, item: item, elapsed: elapsed)
                    withModelOwnedNativeRateCommand { expectedPlayer.playImmediately(atRate: 1) }
                }
                if elapsed >= 8 {
                    recordSingleResume("timeout", player: expectedPlayer, item: item, elapsed: elapsed)
                    singleResumeOwner = nil
                    handleSourceStartupFailure(source, reason: "Playback resume stalled.", countsAsStall: true,
                        expectedRequestID: request,
                        diagnosticDetails: nativeDiagnosticDetails(diagnosticService.analyze(item, trigger: .stallTimeout)))
                    return
                }
                do { try await timing.wait(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    @MainActor private final class SingleNativeResumeObservation {
        var baseline: Double
        var seekRequested = false, seekPending = false, needsBaseline = false
        var immediatePlayRequested = false
        init(position: Double) { baseline = position }
    }

    private func recordSingleResume(_ action: String, player: AVPlayer, item: AVPlayerItem, elapsed: Double) {
        var details = nativeDiagnosticDetails(diagnosticService.analyze(item, trigger: .stallTimeout))
        details["native_resume_action"] = action
        details["native_resume_elapsed_ms"] = String(Int(min(3_600, max(0, elapsed)) * 1_000))
        let position = player.currentTime().seconds
        let ranges = item.seekableTimeRanges.map { ($0.timeRangeValue.start.seconds, $0.timeRangeValue.end.seconds) }
        details["native_resume_window"] = SingleNativeResumeWindowPolicy.relation(position: position, ranges: ranges)
        FottyQualityStore.shared.record(category: .playback, name: "native_resume", outcome: action == "timeout" ? .failure : .info,
                                       details: playbackQualityDetails(details))
    }

    private func scheduleNativeResumeValidation(for source: StreamSource, player: AVPlayer,
                                                item: AVPlayerItem, requestID: UUID, reason: String) {
        let start = player.currentTime().seconds
        let observationIntent = nativeWatchTwoIntentID
        foregroundResumeValidationTask?.cancel()
        foregroundResumeValidationTask = Task {
            try? await timing.wait(for: PlaybackProgressPolicy.resumeValidationDelay)
            guard !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == source.id,
                  self.player === player,
                  self.player?.currentItem === item,
                  isPlaying, userWantsPlayback else { return }
            let now = self.player?.currentTime().seconds ?? start
            observeSingleNativeResumeProgress(player: player, item: item, sourceID: source.id,
                requestID: requestID, intentID: observationIntent, startSeconds: start, currentSeconds: now)
            if PlaybackProgressPolicy.resumeDidNotAdvance(from: start, to: now),
               self.player?.timeControlStatus != .paused {
                validateRecoverableStall(
                    for: source,
                    reason: reason,
                    expectedItem: item,
                    requestID: requestID
                )
            } else {
                transition(to: .playing(.native), phase: "Playing")
            }
        }
    }

    func loadCurrentSource(ignoringCircuitBreaker: Bool = false) {
        guard !isPlaybackSessionRetired else { return }
        guard let selectedSession, admits(selectedSession) else {
            if sessions.indices.contains(lastAdmittedSourceIndex) { currentSourceIndex = lastAdmittedSourceIndex }
            showPlaybackBanner("Choose a source using the same player, or watch this match on its own.")
            return
        }
        retireNativeFullscreenForTransportChange()
        lastAdmittedSourceIndex = currentSourceIndex
        if let preparedNativeWatchTwo { discardNativeWatchTwoCandidate(preparedNativeWatchTwo) }
        self.preparedNativeWatchTwo = nil
        isRetiringWebForNativeWatchTwo = false
        nativeWatchTwoAudioHeld = false
        webAudioRevocationID = nil
        currentWebAudioRevocation = nil
        didStartPlayback = true
        cancelAudioPreparation()
        cancelPendingWebRetry()
        webBackgroundSuspensionTask?.cancel()
        webBackgroundSuspensionTask = nil
        shouldSuspendWebPlayback = false
        isWebPictureInPictureActive = false
        isPictureInPictureActive = false
        nativeHandoffAwaitingWebRetirement = false
        handoffDiagnosticPhase = .none
        handoffDiagnosticOperationID = nil
        diagnosticCandidateCount = 0
        isPlaybackSessionActive = true
        isPictureInPictureAvailable = false
        pictureInPictureRequestID = nil
        lastPictureInPictureRequestAt = nil
        loadTask?.cancel()
        cancelNativePlaybackTransfer()
        nativeHandoffTask = nil
        nativeTransferSuspensionID = nil
        nativeTransferTaskID = nil
        nativeTransferAcknowledgedID = nil
        cachedNativeCandidate = nil
        stallValidationTask?.cancel()
        foregroundResumeValidationTask?.cancel()
        let rid = UUID(); loadRequestID = rid
        retiredWebOwner = nil
        initialNativeStartupRequestID = nil
        webPlaybackCommand = nil
        isWebPlaybackUserPaused = false
        guard var session = activeSession else {
            showNoSourcesAvailable()
            return
        }
        var source = session.legacySource
        let requiresFreshDescriptor = requiredDescriptorRefreshSourceIDs.contains(source.id)
        if requiresFreshDescriptor {
            // Explicit negotiation is not a second automatic startup budget.
            nativeStartupRetryAttemptsBySource[source.id] = 1
        }
        pausedDescriptorNegotiationSourceID = nil
        let refreshDescriptor = usesSingleStreamRanking && viewingPlaybackContext == .single
            && session.eventBinding != nil && !descriptorRefreshAttempts.contains(source.id)
            && (requiresFreshDescriptor || pendingDescriptorRefreshSourceID == source.id
                || session.eventBinding?.isCurrent() == false || session.hasExpiredMediaLease())
        if refreshDescriptor { descriptorRefreshAttempts.insert(source.id) }
        pendingDescriptorRefreshSourceID = nil
        awaitsNativeAudioRetirement = isWebEmbedSource(source)
            && (nativeAudioIsolation != nil || !nativeAudioRetirements.isEmpty)
        playbackCorrelation.beginAttempt(rid)
        lastObservedPlaybackStage = .preparing
        ensurePlaybackIntervalAttempt()

        let wrongProgramme = usesSingleStreamRanking && viewingPlaybackContext == .single && !event.isBroadcastChannel
            && LiveSourceHealthStore.matchEvidence(for: session) == .wrongProgramme
        if wrongProgramme || (!ignoringCircuitBreaker && LiveSourceHealthStore.isTemporarilyUnavailable(source)) {
            failedSourceIDs.insert(source.id)
            if let next = nextPlayableSource(after: source),
               let index = sources.firstIndex(where: { $0.id == next.id }) {
                currentSourceIndex = index
                showPlaybackBanner(wrongProgramme ? "Trying another broadcast of this match" : "Skipping a recently failing source")
                loadCurrentSource()
            } else {
                errorTitle = wrongProgramme ? "No matching broadcast" : "Sources Temporarily Unavailable"
                error = wrongProgramme ? "This source showed a different programme. Retry to look for another broadcast." : "Automatic switching is paused because every source failed recently. Choose a source to retry it manually."
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
            details: playbackQualityDetails()
        )
        removeItemFailureObservers(); stopPlaybackWatchdog(); streamProxy?.stop(); streamProxy = nil
        descriptorNegotiationRequestID = refreshDescriptor ? rid : nil
        if usesSingleStreamRanking, viewingPlaybackContext == .single, !isWebEmbedSource(source) {
            singleNativePreparation = .init(requestID: rid, sourceID: source.id, needsDescriptorRefresh: refreshDescriptor)
        }
        if deferSingleNativePreparationForBackgroundIfNeeded() { return }
        loadTask = Task {
            guard !Task.isCancelled, loadRequestID == rid else { return }
            // Descriptor negotiation is part of this retry's existing startup
            // budget. A paused/replaced owner cannot publish its completion.
            let negotiationStarted = refreshDescriptor ? timing.monotonicNow() : nil
            if requiresFreshDescriptor && !refreshDescriptor {
                handleSourceStartupFailure(source, reason: "This broadcast could not reconnect.", expectedRequestID: rid,
                    diagnosticDetails: ["preparation_reason": "descriptor_renewal_unavailable"])
                return
            }
            if refreshDescriptor {
                defer {
                    if descriptorNegotiationRequestID == rid { descriptorNegotiationRequestID = nil }
                }
                let originalRequest = StreamPlaybackRequest(event: event)
                let request: StreamPlaybackRequest
                if session.eventBinding?.usesRegistryAssociation == true {
                    guard let current = currentDescriptorRecoveryRequest(originalRequest) else {
                        handleSourceStartupFailure(source, reason: "This match listing changed. Reopen it from the lineup.", expectedRequestID: rid,
                            diagnosticDetails: ["preparation_reason": "descriptor_fixture_changed"])
                        return
                    }
                    request = current
                } else { request = originalRequest }
                let fresh = await refreshSourceDescriptor(session, request)
                guard !Task.isCancelled, loadRequestID == rid, activeSource?.id == source.id,
                      isPlaybackSessionActive, userWantsPlayback, !isAppBackgrounded else { return }
                pausedDescriptorNegotiationSourceID = nil
                if singleNativePreparation?.requestID == rid {
                    singleNativePreparation?.needsDescriptorRefresh = false
                }
                let acceptedRequest: StreamPlaybackRequest
                if session.eventBinding?.usesRegistryAssociation == true {
                    guard let current = currentDescriptorRecoveryRequest(originalRequest) else {
                        handleSourceStartupFailure(source, reason: "This match listing changed. Reopen it from the lineup.", expectedRequestID: rid,
                            diagnosticDetails: ["preparation_reason": "descriptor_fixture_changed"])
                        return
                    }
                    acceptedRequest = current
                } else { acceptedRequest = request }
                if let fresh, fresh.id == session.id,
                   let binding = fresh.eventBinding,
                   binding.matches(request: acceptedRequest, providerCode: binding.providerCode),
                   let index = providedSessions.firstIndex(where: { $0.id == session.id }) {
                    providedSessions[index] = fresh
                    session = fresh
                    source = fresh.legacySource
                    requiredDescriptorRefreshSourceIDs.remove(source.id)
                } else if requiresFreshDescriptor {
                    // A frozen live window needs a freshly resolved delivery.
                    // Retrying the known stalled URL after a failed lookup is
                    // not recovery, even while its declared lease is unexpired.
                    handleSourceStartupFailure(source, reason: "This broadcast could not reconnect.", expectedRequestID: rid,
                        diagnosticDetails: ["preparation_reason": "descriptor_renewal_unavailable"])
                    return
                }
            }
            if usesSingleStreamRanking && viewingPlaybackContext == .single, session.hasExpiredMediaLease() {
                // Metadata TTL alone never revokes a transport. An actual
                // expired lease must not be replayed after renewal failed.
                nativeStartupRetryAttemptsBySource[source.id] = 1
                handleSourceStartupFailure(source, reason: "Stream lease expired.", expectedRequestID: rid,
                    diagnosticDetails: PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: .leaseExpired).qualityDetails)
                return
            }
            if isDiscoveryOnlySource(source) { handleSourceStartupFailure(source, reason: "Resolver only.", expectedRequestID: rid); return }
            if isWebEmbedSource(source) {
                withModelOwnedNativeRateCommand { player?.pause() }
                player = nil
                guard !Task.isCancelled, loadRequestID == rid else { return }
                guard await waitForNativeAudioRetirementBeforeWeb(requestID: rid) else { return }
                transition(to: userWantsPlayback ? .connecting(.webEmbed) : .paused(.webEmbed),
                           phase: userWantsPlayback ? "Starting Web Stream..." : "Paused")
                enterLandscapeIfNeeded()
                return
            }
            do {
                initialNativeStartupRequestID = rid
                defer {
                    if initialNativeStartupRequestID == rid { initialNativeStartupRequestID = nil }
                }
                if nativeAudioIsolation != nil { retireNativeAudioIsolation() }
                if player == nil || player === nativePlayerRequiringReplacement {
                    player = AVPlayer()
                    nativePlayerRequiringReplacement = nil
                } else { player?.replaceCurrentItem(with: nil) }
                guard let player else { return }
                MediaAudioSession.configureNativeBackgroundPlayback(player)
                player.automaticallyWaitsToMinimizeStalling = true
                let url = try await preparePlaybackURL(for: session, requestID: rid)
                guard !Task.isCancelled, loadRequestID == rid else { return }

                // --- AUDIT FIX [CONTRACT VALIDATION] ---
                connectionPhase = "Validating Source..."
                let validation = await validateNativeSource(url, source.headers)
                // Validation may finish after a switch/dismissal even if its
                // transport ignores cancellation. Never replace the new item.
                guard !Task.isCancelled, loadRequestID == rid,
                      isPlaybackSessionActive, activeSource?.id == source.id else { return }
                if case .invalid(let reason, let diagnostic) = validation {
                    let details = (diagnostic ?? .init(stage: .contractValidation, reason: .unavailable)).qualityDetails
                    handleSourceStartupFailure(source, reason: "Stream Contract Failed: \(reason)", expectedRequestID: rid,
                        diagnosticDetails: preparationDiagnosticDetails(details, source: source, requestID: rid))
                    return
                }

                // CRITICAL: Must pass headers to AVURLAsset otherwise many providers (Referer/UA checks) will fail.
                let item = NativePlaybackPreparation.makeItem(url: url, headers: source.headers,
                    session: session, evidence: validation.mediaEvidence)
                configureItemFailureObservers(for: item, source: source, requestID: rid)
                player.replaceCurrentItem(with: item)
                connectionPhase = "Buffering..."
                let startupIntent = audioIntentID
                guard await requestPlaybackStart(player: player) else { return }
                // Audio preparation has completed and the exact owned item has
                // received its first Play. Readiness must not restart this clock.
                let deadline = NativePlaybackStartupDeadline(startedAt: negotiationStarted ?? timing.monotonicNow(),
                    budget: NativePlaybackStartupDeadline.budget(for: session, context: viewingPlaybackContext,
                        isNativeHandoff: nativeHandoffSession != nil, renewingMatch: refreshDescriptor && !event.isBroadcastChannel))
                let observationDetails = viewingPlaybackContext == .single ? playbackQualityDetails() : nil
                let startup = await waitForInitialNativeStartup(player: player, item: item, source: source,
                    requestID: rid, intentID: startupIntent, deadline: deadline)
                if let observationDetails {
                    recordNativeStartupObservationEndIfNeeded(startup, player: player, item: item,
                        sourceID: source.id, requestID: rid, intentID: startupIntent,
                        deadline: deadline, capturedDetails: observationDetails)
                }
                // The caller resumes on a new actor turn. Recheck ownership
                // before any success/failure publication, not only in the waiter.
                guard !Task.isCancelled, isPlaybackSessionActive, userWantsPlayback,
                      loadRequestID == rid, activeSource?.id == source.id,
                      self.player === player, player.currentItem === item, audioIntentID == startupIntent,
                      error == nil, playbackState != .failed,
                      !isAppBackgrounded || shouldKeepPlaybackAliveForPictureInPicture else { return }
                switch startup {
                case .started:
                    handleSuccessfulStartup(source: source, expectedRequestID: rid)
                case .failed:
                    handleNativeItemFailure(item, source: source, requestID: rid, trigger: .itemStatusFailed)
                case .timedOut:
                    if item.status == .failed {
                        handleNativeItemFailure(item, source: source, requestID: rid, trigger: .itemStatusFailed)
                        return
                    }
                    let waiting = nativeStartupTimeoutDetails(player: player, item: item, deadline: deadline)
                    if item.status != .readyToPlay {
                        let snapshot = diagnosticService.analyze(item, trigger: .readinessTimeout)
                        handleSourceStartupFailure(source, reason: "Native readiness timeout.", expectedRequestID: rid,
                            diagnosticDetails: nativeDiagnosticDetails(snapshot).merging(waiting) { _, value in value })
                    } else {
                        let details = PlaybackPreparationDiagnostic(stage: .playbackStart, reason: .playbackStartTimeout,
                                                                    error: item.error).qualityDetails
                            .merging(waiting) { _, value in value }
                        handleSourceStartupFailure(source, reason: "Startup timeout.", expectedRequestID: rid,
                            diagnosticDetails: preparationDiagnosticDetails(details, source: source, requestID: rid))
                    }
                case .abandoned, .invalidTiming, .waiting:
                    // Pause/replacement/background revocation is not a source
                    // failure. An invalid clock grants no retry authority either.
                    return
                }
            } catch {
                let preparedFailure = error as? PlaybackPreparationFailure
                let details = preparedFailure?.qualityDetails ?? PlaybackPreparationDiagnostic(
                    stage: .urlPreparation, reason: error is CancellationError ? .cancelled : .transportError,
                    error: error is CancellationError ? nil : error).qualityDetails
                handleSourceStartupFailure(source, reason: (preparedFailure?.underlyingError ?? error).localizedDescription,
                    expectedRequestID: rid,
                    diagnosticDetails: preparationDiagnosticDetails(details, source: source, requestID: rid))
            }
        }
    }

    // Internal so delayed platform completion can be exercised without opening
    // a provider URL or making AVPlayer decode synthetic network media.
    func requestPlaybackStart(player: AVPlayer) async -> Bool {
        let request = loadRequestID, source = activeSource?.id, intent = audioIntentID
        let audioFocus = nativeAudioFocusGeneration
        let item = player.currentItem
        guard isPlaybackSessionActive, userWantsPlayback else { return false }
        if usesSingleStreamRanking, viewingPlaybackContext == .single, !playbackIntervals.hasDecoded,
           let source, singleNativePreparation == nil {
            singleNativePreparation = .init(requestID: request, sourceID: source, needsDescriptorRefresh: false)
        }
        if hasAdoptedNativeHandoff, let item,
           nativeAudioIsolation?.player !== player || nativeAudioIsolation?.item !== item {
            guard nativeAudioIsolationBackend.isSupported, let source else { return false }
            // A foreign item cannot share an old controller's in-flight setter.
            // The owned source-retry path allocates a fresh player above.
            guard nativeAudioIsolation?.player !== player else { return false }
            retireNativeAudioIsolation()
            let isolation = makeNativeAudioIsolation(player: player, item: item,
                sourceID: source, requestID: request)
            let disconnected = isolation.request(disconnected: true)
            guard await disconnected.wait(), !Task.isCancelled, isPlaybackSessionActive,
                  !isPlaybackSessionRetired, userWantsPlayback, audioIntentID == intent,
                  loadRequestID == request, activeSource?.id == source,
                  self.player === player, player.currentItem === item else {
                isolation.request(disconnected: true)
                return false
            }
            adoptNativeAudioIsolation(isolation)
        }
        MediaAudioSession.configureNativeBackgroundPlayback(player)
        var preparation = MediaAudioSessionPreparation.cancelled
        guard await MediaAudioPlaybackGate.prepare(using: {
            preparation = await self.prepareOwnedNativeAudio(purpose: .nativeStart)
            return preparation
        }, isCurrent: {
            isPlaybackSessionActive && userWantsPlayback && loadRequestID == request && activeSource?.id == source
                && audioIntentID == intent && self.player === player && player.currentItem === item
                && error == nil && playbackState != .failed
                && (!isAppBackgrounded || shouldKeepPlaybackAliveForPictureInPicture)
        }) else { return false }
        guard await releaseNativeHandoffAudioMuteAfterActivation(for: player, result: preparation,
            focusGeneration: audioFocus, isCurrent: {
                self.isPlaybackSessionActive && self.userWantsPlayback && self.loadRequestID == request
                    && self.activeSource?.id == source && self.audioIntentID == intent
                    && self.player === player && player.currentItem === item && self.error == nil
                    && self.playbackState != .failed
                    && (!self.isAppBackgrounded || self.shouldKeepPlaybackAliveForPictureInPicture)
            }) else { return false }
        withModelOwnedNativeRateCommand { player.play() }
        return true
    }

    private func cancelAudioPreparation() {
        audioPreparationTask?.cancel()
        audioPreparationTask = nil
        audioIntentID = UUID()
        cancelPictureInPictureAudioPreparation()
        cancelNativeHandoffAudioClaim()
    }

    private var hasPendingNativePlay: Bool {
        let negotiatingDescriptor = usesSingleStreamRanking && viewingPlaybackContext == .single
            && descriptorNegotiationRequestID == loadRequestID && playbackState == .connecting(.native)
        let deferredPreparation = usesSingleStreamRanking && viewingPlaybackContext == .single
            && deferredSingleNativePreparation?.requestID == loadRequestID
            && deferredSingleNativePreparation?.sourceID == activeSource?.id
        let initialPreparation = usesSingleStreamRanking && viewingPlaybackContext == .single
            && singleNativePreparation?.requestID == loadRequestID
            && singleNativePreparation?.sourceID == activeSource?.id
        return (pendingSingleDiscoveryFailure != nil || audioPreparationTask != nil || negotiatingDescriptor || deferredPreparation || initialPreparation)
            && userWantsPlayback && !isUsingWebEmbed
    }

    private var hasAdoptedNativeHandoff: Bool {
        nativeHandoffSession != nil && nativeHandoffSession?.id == activeSource?.id && !isUsingWebEmbed
    }

    private func cancelNativeHandoffAudioClaim(revokeConnection: Bool = true) {
        nativeHandoffAudioClaimID = UUID()
        nativeHandoffAudioClaimTask?.cancel()
        nativeHandoffAudioClaimTask = nil
        if revokeConnection, let isolation = nativeAudioIsolation {
            nativeHandoffAudioMuteHeld = true
            applyViewingAudioState()
            isolation.request(disconnected: true)
        }
        // Keep an outstanding mute barrier. A later valid activation, not a
        // cancelled callback, is what may make this already-playing item audible.
    }

    /// Adoption has already verified decoded frames. This only holds output
    /// until the exact old Web owner acknowledges retirement; it starts no media.
    func holdNativeHandoffAudioUntilWebRetirement() {
        guard hasAdoptedNativeHandoff else { return }
        cancelNativeHandoffAudioClaim()
        nativeHandoffAwaitingWebRetirement = true
        nativeHandoffAudioMuteHeld = true
        applyViewingAudioState()
    }

    private func queueNativeHandoffAudioClaim(explicitAVKitPlay: Bool = false) {
        guard isPlaybackSessionActive, !isPlaybackSessionRetired, hasAdoptedNativeHandoff,
              !nativeWatchTwoAudioHeld,
              !nativeHandoffAwaitingWebRetirement, isViewingAudioEnabled, userWantsPlayback,
              isPlaying || explicitAVKitPlay, error == nil, playbackState != .failed,
              let expectedPlayer = player, let item = expectedPlayer.currentItem,
              !isAppBackgrounded || shouldKeepPlaybackAliveForPictureInPicture else { return }
        guard nativeHandoffAudioClaimTask == nil else { return }
        cancelNativeHandoffAudioClaim()
        nativeHandoffAudioMuteHeld = true
        applyViewingAudioState()
        let claim = nativeHandoffAudioClaimID, focus = nativeAudioFocusGeneration
        let intent = audioIntentID, request = loadRequestID, source = activeSource?.id
        nativeHandoffAudioClaimTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.nativeHandoffAudioClaimID == claim { self.nativeHandoffAudioClaimTask = nil }
            }
            guard await MediaAudioPlaybackGate.prepare(using: {
                let preparation = await self.measuredAudioPreparation(purpose: .nativeHandoff)
                return Self.audioActivationSucceeded(preparation) ? preparation : .cancelled
            }, isCurrent: {
                self.isPlaybackSessionActive && !self.isPlaybackSessionRetired
                    && self.nativeHandoffAudioClaimID == claim && self.nativeAudioFocusGeneration == focus
                    && self.audioIntentID == intent && self.loadRequestID == request && self.activeSource?.id == source
                    && self.player === expectedPlayer && expectedPlayer.currentItem === item
                    && self.hasAdoptedNativeHandoff && !self.nativeHandoffAwaitingWebRetirement
                    && self.isViewingAudioEnabled && self.userWantsPlayback && self.error == nil
                    && self.playbackState != .failed
                    && (!self.isAppBackgrounded || self.shouldKeepPlaybackAliveForPictureInPicture)
            }) else { return }
            _ = await self.releaseNativeHandoffAudioMuteAfterActivation(for: expectedPlayer,
                result: .completed([]), focusGeneration: focus, isCurrent: {
                    self.nativeHandoffAudioClaimID == claim && self.audioIntentID == intent
                        && self.loadRequestID == request && self.activeSource?.id == source
                        && expectedPlayer.currentItem === item
                })
            // This verified player is already running, or AVKit issued Play.
            // Claiming audio must never issue another Play, seek or item replace.
        }
    }

    private static func audioActivationSucceeded(_ result: MediaAudioSessionPreparation) -> Bool {
        if case .completed(let failures) = result { return failures.isEmpty }
        return false
    }

    private func releaseNativeHandoffAudioMuteAfterActivation(for expectedPlayer: AVPlayer,
        result: MediaAudioSessionPreparation, focusGeneration: UUID,
        isCurrent: @MainActor () -> Bool = { true }) async -> Bool {
        guard !Task.isCancelled, isCurrent() else { return false }
        guard hasAdoptedNativeHandoff else { return true }
        if let isolation = nativeAudioIsolation, !isViewingAudioEnabled || !userWantsPlayback {
            let barrier = isolation.request(disconnected: true)
            return await barrier.wait() && !Task.isCancelled && isCurrent()
        }
        if nativeAudioFocusGeneration != focusGeneration {
            // Preserve a still-current explicit Play, but never let its old
            // focus release mute. It may run only after the newer connection
            // request has settled (or remain silent while disconnected).
            guard let isolation = nativeAudioIsolation else { return true }
            guard isolation.player === expectedPlayer, expectedPlayer.currentItem === isolation.item,
                  let current = isolation.currentBarrier else { return false }
            return await current.wait() && !Task.isCancelled && isCurrent()
                && nativeAudioIsolation === isolation && player === expectedPlayer
                && expectedPlayer.currentItem === isolation.item
        }
        guard isPlaybackSessionActive, !isPlaybackSessionRetired, self.player === expectedPlayer,
              hasAdoptedNativeHandoff, !nativeHandoffAwaitingWebRetirement,
              isViewingAudioEnabled, userWantsPlayback, error == nil, playbackState != .failed,
              nativeAudioFocusGeneration == focusGeneration,
              Self.audioActivationSucceeded(result) else { return false }
        if let isolation = nativeAudioIsolation {
            guard isolation.player === expectedPlayer, expectedPlayer.currentItem === isolation.item else { return false }
            let barrier = isolation.request(disconnected: false)
            guard await barrier.wait(), !Task.isCancelled, isCurrent(),
                  isPlaybackSessionActive, !isPlaybackSessionRetired,
                  nativeAudioIsolation === isolation, player === expectedPlayer,
                  expectedPlayer.currentItem === isolation.item, hasAdoptedNativeHandoff,
                  !nativeHandoffAwaitingWebRetirement, isViewingAudioEnabled, userWantsPlayback,
                  nativeAudioFocusGeneration == focusGeneration, error == nil, playbackState != .failed else {
                isolation.revokeIfCurrent(barrier)
                return false
            }
        }
        cancelNativeHandoffAudioClaim(revokeConnection: false)
        nativeHandoffAudioMuteHeld = false
        applyViewingAudioState()
        return true
    }

    private func prepareOwnedNativeAudio(purpose: FottyPlaybackDiagnosticPurpose) async -> MediaAudioSessionPreparation {
        if let isolation = nativeAudioIsolation, !isViewingAudioEnabled {
            guard await isolation.request(disconnected: true).wait(), !Task.isCancelled else { return .cancelled }
            return await measuredAudioPreparation(purpose: purpose, configurationOnly: true)
        }
        return await measuredAudioPreparation(purpose: purpose)
    }

    private func queueAudioPreparation(for expectedPlayer: AVPlayer?,
                                      completion: @escaping @MainActor () -> Void) {
        cancelAudioPreparation()
        let intent = audioIntentID, request = loadRequestID, source = activeSource?.id
        let audioFocus = nativeAudioFocusGeneration
        let item = expectedPlayer?.currentItem
        audioPreparationTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.audioIntentID == intent { self.audioPreparationTask = nil } }
            var preparation = MediaAudioSessionPreparation.cancelled
            guard await MediaAudioPlaybackGate.prepare(using: {
                preparation = await self.prepareOwnedNativeAudio(purpose: .nativeResume)
                return preparation
            }, isCurrent: {
                self.isPlaybackSessionActive && self.audioIntentID == intent && self.loadRequestID == request
                    && self.activeSource?.id == source && self.player === expectedPlayer
                    && self.player?.currentItem === item && self.userWantsPlayback
                    && self.error == nil && self.playbackState != .failed
                    && (!self.isAppBackgrounded || self.shouldKeepPlaybackAliveForPictureInPicture)
            }) else { return }
            if let expectedPlayer {
                guard await self.releaseNativeHandoffAudioMuteAfterActivation(for: expectedPlayer, result: preparation,
                    focusGeneration: audioFocus, isCurrent: {
                        self.isPlaybackSessionActive && self.audioIntentID == intent && self.loadRequestID == request
                            && self.activeSource?.id == source && self.player === expectedPlayer
                            && expectedPlayer.currentItem === item && self.userWantsPlayback
                            && self.error == nil && self.playbackState != .failed
                            && (!self.isAppBackgrounded || self.shouldKeepPlaybackAliveForPictureInPicture)
                    }) else { return }
            }
            completion()
        }
    }

    private func cancelPictureInPictureAudioPreparation() {
        pictureInPicturePreparationTask?.cancel()
        pictureInPicturePreparationTask = nil
        pictureInPicturePreparationID = UUID()
    }

    /// PiP preparation does not change transport intent. In particular, an
    /// automatic PiP/background callback must not revoke a pending native Play.
    private func queuePictureInPictureAudioPreparation(for expectedPlayer: AVPlayer, reason: String? = nil) {
        if reason == nil, pictureInPicturePreparationTask != nil { return }
        cancelPictureInPictureAudioPreparation()
        let preparationID = pictureInPicturePreparationID
        let intent = audioIntentID, request = loadRequestID, source = activeSource?.id
        let audioFocus = nativeAudioFocusGeneration
        let item = expectedPlayer.currentItem
        pictureInPicturePreparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.pictureInPicturePreparationID == preparationID {
                    self.pictureInPicturePreparationTask = nil
                }
            }
            var preparation = MediaAudioSessionPreparation.cancelled
            guard await MediaAudioPlaybackGate.prepare(using: {
                preparation = await self.prepareOwnedNativeAudio(purpose: .pictureInPicture)
                return preparation
            }, isCurrent: {
                self.isPlaybackSessionActive && self.audioIntentID == intent && self.loadRequestID == request
                    && self.activeSource?.id == source && self.player === expectedPlayer
                    && expectedPlayer.currentItem === item && !self.isUsingWebEmbed
                    && self.error == nil && self.playbackState != .failed
                    && (reason != nil || self.userWantsPlayback)
                    && self.allowsViewingPiP
                    && (self.isPictureInPictureAvailable || self.isPictureInPictureActive)
                    && (!self.isAppBackgrounded || self.shouldKeepPlaybackAliveForPictureInPicture)
            }) else { return }
            guard await self.releaseNativeHandoffAudioMuteAfterActivation(for: expectedPlayer, result: preparation,
                focusGeneration: audioFocus, isCurrent: {
                    self.isPlaybackSessionActive && self.audioIntentID == intent && self.loadRequestID == request
                        && self.activeSource?.id == source && self.player === expectedPlayer
                        && expectedPlayer.currentItem === item && !self.isUsingWebEmbed && self.error == nil
                        && self.playbackState != .failed && (reason != nil || self.userWantsPlayback)
                        && self.allowsViewingPiP && (self.isPictureInPictureAvailable || self.isPictureInPictureActive)
                        && (!self.isAppBackgrounded || self.shouldKeepPlaybackAliveForPictureInPicture)
                }) else { return }
            if let reason { self.publishPictureInPictureRequest(reason: reason) }
        }
    }

    private func preparePlaybackURL(for session: StreamSession, requestID: UUID) async throws -> URL {
        // A same-source native-pair Retry must preserve the captured WK-scoped
        // cookies; the shared HTTP cookie store is not the WebKit cookie store.
        if nativeHandoffSession?.id == session.id, let delivery = nativeWatchTwoDelivery,
           delivery.url == session.playableURL {
            let prepared = try await prepareNativeHandoffURL(for: delivery)
            guard !Task.isCancelled, loadRequestID == requestID, activeSession?.id == session.id else {
                prepared.proxy?.stop()
                throw CancellationError()
            }
            streamProxy = prepared.proxy
            return prepared.url
        }

        let remoteURL = session.playableURL

        // Reviewed CS wrapper rotation also needs stable local segment URIs,
        // including headerless deliveries. Ordinary native sources stay direct.
        guard session.requiresLocalProxy else {
            return remoteURL
        }

        let cookies = HTTPCookieStorage.shared.cookies(for: remoteURL) ?? []
        let prepared = try await NativePlaybackPreparation.prepareDelivery(url: remoteURL,
            headers: session.requiredHeaders, cookies: cookies, requiresRelay: true,
            originProfile: session.nativeOriginProfile, playlistProfile: session.nativePlaylistProfile)
        guard !Task.isCancelled, requestID == loadRequestID, activeSession?.id == session.id else {
            prepared.discard()
            throw CancellationError()
        }
        streamProxy = prepared.proxy
        return prepared.url
    }

    private func handleSuccessfulStartup(
        source: StreamSource,
        reportedLatencyMs: Int? = nil,
        expectedRequestID: UUID? = nil
    ) {
        guard activeSource?.id == source.id else { return }
        guard isPlaybackSessionActive, userWantsPlayback, pendingSingleDiscoveryFailure == nil else { return }
        if let expectedRequestID, expectedRequestID != loadRequestID { return }
        if viewingPlaybackContext == .single {
            singleNativePreparation = nil
            deferredSingleNativePreparation = nil
            invalidateSingleNetworkRecovery()
        }
        if usesSingleStreamRanking, viewingPlaybackContext == .single { disarmSingleDiscoveryContinuation() }
        if let identity = intervalIdentity {
            playbackIntervals.decodedProgress(identity, now: timing.monotonicNow())?.record()
        }
        lastObservedPlaybackStage = .decoded
        let completedNativeHandoff = playbackState == .preparingNativeHandoff
        // A Web owner may report a fresh decoded start while a native candidate
        // is still preparing. Count a handoff only after that candidate owns
        // transport; preserve the existing multistream bookkeeping.
        let recordsNativeHandoff = completedNativeHandoff
            && (viewingPlaybackContext != .single || hasAdoptedNativeHandoff)
        stallValidationTask?.cancel(); failedSourceIDs.remove(source.id); error = nil
        let receipt: SinglePlaybackStartEvidence.Receipt?
        if viewingPlaybackContext == .single {
            receipt = singlePlaybackStartEvidence.admit(recordsNativeHandoff ? .nativeHandoff : .initialStartup,
                identity: .init(sourceID: source.id, attemptID: loadRequestID))
        } else { receipt = nil } // Keep existing multistream bookkeeping unchanged.
        if receipt == nil || receipt == .initialStartup {
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
        }
        if receipt == .initialStartup, viewingPlaybackContext == .single {
            recordMatchOutcome(.decoded, for: source)
            if let station = SportsTVStation.station(id: event.id) { SportsTVLibrary.shared.recordPlayed(station.id) }
            observeSingleContinuity(source)
            startBackupRefreshIfNeeded()
        }
        if receipt == nil || receipt != SinglePlaybackStartEvidence.Receipt.none {
            FottyQualityStore.shared.record(
                category: .playback,
                name: recordsNativeHandoff ? "native_handoff" : "decoded_progress",
                outcome: .success,
                durationMilliseconds: recordsNativeHandoff ? nil : lastStartupLatencyMs,
                details: playbackQualityDetails(viewingPlaybackContext == .single ? singlePlaybackEvidence() : [:])
            )
        }
        transition(to: .playing(isWebEmbedSource(source) ? .webEmbed : .native), phase: "Playing")
        refreshSinglePlaybackQuality()
        // Focus may have moved while native startup was awaiting its muted
        // configuration. Only actual startup, not readiness, can retry that
        // current selected-owner claim; never issue a second Play here.
        if hasAdoptedNativeHandoff, nativeHandoffAudioMuteHeld, isViewingAudioEnabled {
            queueNativeHandoffAudioClaim()
        }
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

    private func waitForInitialNativeStartup(
        player: AVPlayer, item: AVPlayerItem, source: StreamSource,
        requestID: UUID, intentID: UUID, deadline: NativePlaybackStartupDeadline
    ) async -> NativePlaybackStartupDeadline.Decision {
        var baseline: Double?
        var recordedReadiness = false
        while true {
            let ownsAttempt = isPlaybackSessionActive && loadRequestID == requestID
                && activeSource?.id == source.id && self.player === player && player.currentItem === item
                && audioIntentID == intentID && error == nil && playbackState != .failed
                && (!isAppBackgrounded || shouldKeepPlaybackAliveForPictureInPicture)
            let seconds = player.currentTime().seconds
            // AVPlayer can initially report an invalid media time. Adopt the
            // first finite baseline without changing the monotonic deadline.
            if baseline == nil, seconds.isFinite, seconds >= 0 { baseline = seconds }
            let verified = baseline.map {
                NativePlaybackVideoPolicy.hasDisplayedProgress(isReadyForDisplay: isVideoReadyForDisplay,
                    startSeconds: $0, currentSeconds: seconds)
            } ?? false
            let status = item.status
            let decision = deadline.decision(at: timing.monotonicNow(),
                hasVerifiedVideoStart: status == .readyToPlay && verified,
                hasFailedItem: status == .failed, isCancelled: Task.isCancelled,
                ownsCurrentAttempt: ownsAttempt, userWantsPlayback: userWantsPlayback)
            guard decision == .waiting || decision == .started else { return decision }
            if status == .readyToPlay, !recordedReadiness {
                recordedReadiness = true
                recordPlaybackStage(.mediaReady, sourceID: source.id, requestID: requestID)
            }
            if decision == .started { return decision }
            do { try await timing.sleep(.milliseconds(250)) }
            catch { return .abandoned }
        }
    }

    /// Log-only completion for a suspended startup observer. The pre-await
    /// context belongs to the old attempt even after a source/Stop replacement;
    /// never snapshot a newer relay, mutate transport or manufacture a failure.
    private func recordNativeStartupObservationEndIfNeeded(
        _ decision: NativePlaybackStartupDeadline.Decision,
        player expectedPlayer: AVPlayer, item expectedItem: AVPlayerItem,
        sourceID: UUID, requestID: UUID, intentID: UUID,
        deadline: NativePlaybackStartupDeadline, capturedDetails: [String: String]
    ) {
        let reason: NativeStartupObservationEndReason?
        if Task.isCancelled { reason = .cancelled }
        else if isPlaybackSessionRetired || !isPlaybackSessionActive { reason = .retired }
        else if activeSource?.id != sourceID || loadRequestID != requestID { reason = .replacedAttempt }
        else if player !== expectedPlayer || expectedPlayer.currentItem !== expectedItem { reason = .replacedItem }
        else if !userWantsPlayback { reason = .paused }
        else if audioIntentID != intentID { reason = .renewedAudioIntent }
        else if isAppBackgrounded && !shouldKeepPlaybackAliveForPictureInPicture { reason = .backgrounded }
        else if decision == .invalidTiming { reason = .invalidTiming }
        else if decision == .abandoned { reason = .interrupted }
        else { reason = nil }
        guard let reason else { return }
        var details = capturedDetails.merging(reason.qualityDetails) { _, current in current }
        if let elapsed = deadline.elapsed(at: timing.monotonicNow()), elapsed <= 3_600 {
            details["native_startup_elapsed_ms"] = String(Int(elapsed * 1_000))
        }
        FottyQualityStore.shared.record(category: .playback, name: "native_startup_observation_ended",
                                       outcome: .info, details: details)
    }

    /// Passive first-video evidence after an initial observer was abandoned
    /// (for example, an early Pause then Play). Existing resume/watchdog work
    /// supplies samples; this adds no timer, Play, seek, retry or state change.
    /// Controlled callers/tests must not confuse this policy with decoder proof.
    @discardableResult
    func observeSingleNativeResumeProgress(
        player expectedPlayer: AVPlayer, item expectedItem: AVPlayerItem,
        sourceID: UUID, requestID: UUID, intentID: UUID,
        startSeconds: Double, currentSeconds: Double
    ) -> Bool {
        guard viewingPlaybackContext == .single, diagnosticRoute == .single,
              isPlaybackSessionActive, !isPlaybackSessionRetired,
              loadRequestID == requestID, activeSource?.id == sourceID,
              player === expectedPlayer, expectedPlayer.currentItem === expectedItem,
              initialNativeStartupRequestID != requestID,
              userWantsPlayback, nativeWatchTwoIntentID == intentID, !isUsingWebEmbed,
              error == nil, isPlaying,
              !isAppBackgrounded || shouldKeepPlaybackAliveForPictureInPicture,
              expectedItem.status == .readyToPlay,
              startSeconds >= 0, currentSeconds >= 0,
              NativePlaybackVideoPolicy.hasDisplayedProgress(isReadyForDisplay: isVideoReadyForDisplay,
                  startSeconds: startSeconds, currentSeconds: currentSeconds) else { return false }
        // Incident retirement is independent of first-start evidence. A paused
        // or offline foreground visit may already have consumed its recovery
        // request, and this attempt may have decoded long before that failure.
        retireNativeFailureAfterDisplayedProgress(item: expectedItem, sourceID: sourceID,
            requestID: requestID, currentSeconds: currentSeconds)
        ensurePlaybackIntervalAttempt()
        guard let identity = intervalIdentity, !playbackIntervals.hasDecoded else { return false }
        guard singlePlaybackStartEvidence.admit(.resumedProgress, identity: identity) == .resumedProgress else { return false }
        playbackIntervals.decodedProgress(identity, now: timing.monotonicNow())?.record()
        lastObservedPlaybackStage = .decoded
        // This isn't a fresh startup: the user may have paused for minutes.
        // Do not update startup latency, source health or transport state here.
        FottyQualityStore.shared.record(category: .playback, name: "decoded_progress", outcome: .success,
            details: playbackQualityDetails(["diagnostic_purpose": FottyPlaybackDiagnosticPurpose.nativeResume.rawValue]))
        return true
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
        var details = ["native_startup_deadline_ms": String(Int(deadline.budget.seconds * 1_000)),
                       "native_item_status": status, "native_time_control": control, "native_wait_reason": reason,
                       "native_buffer_empty": String(item.isPlaybackBufferEmpty),
                       "native_buffer_full": String(item.isPlaybackBufferFull),
                       "native_likely_to_keep_up": String(item.isPlaybackLikelyToKeepUp)]
        if let elapsed = deadline.elapsed(at: timing.monotonicNow()), elapsed <= 3_600 {
            details["native_startup_elapsed_ms"] = String(Int(elapsed * 1_000))
        }
        return details
    }

    private func waitForVerifiedVideoStart(
        player: AVPlayer, timeoutSeconds: Double, videoOutput: AVPlayerItemVideoOutput? = nil
    ) async -> Bool {
        let expectedItem = player.currentItem
        let startSeconds = player.currentTime().seconds
        var frameProgress = NativePlaybackFrameProgress()
        for _ in 0..<Int(timeoutSeconds * 4) {
            guard !Task.isCancelled, player.currentItem === expectedItem else { return false }
            let itemTime = player.currentTime()
            if let videoOutput {
                if let sample = decodedFrameSample(from: videoOutput, at: itemTime),
                   frameProgress.observe(seconds: sample.seconds, width: sample.width, height: sample.height) {
                    return true
                }
            } else if NativePlaybackVideoPolicy.hasDisplayedProgress(
                isReadyForDisplay: isVideoReadyForDisplay,
                startSeconds: startSeconds, currentSeconds: itemTime.seconds
            ) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func decodedFrameSample(
        from output: AVPlayerItemVideoOutput, at itemTime: CMTime
    ) -> (seconds: Double, width: Int, height: Int)? {
        guard itemTime.isNumeric, output.hasNewPixelBuffer(forItemTime: itemTime) else { return nil }
        if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
            let frame = output.pixelBufferAndDisplayTime(forItemTime: itemTime)
            guard let buffer = frame.pixelBuffer else { return nil }
            let dimensions = buffer.withUnsafeBuffer { (CVPixelBufferGetWidth($0), CVPixelBufferGetHeight($0)) }
            return (frame.itemTimeForDisplay.seconds, dimensions.0, dimensions.1)
        } else {
            var displayTime = CMTime.invalid
            guard let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else { return nil }
            return (displayTime.seconds, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer))
        }
    }

    private func configureItemFailureObservers(
        for item: AVPlayerItem,
        source: StreamSource,
        requestID: UUID
    ) {
        removeItemFailureObservers()
        let center = NotificationCenter.default
        let f = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            let reportedError = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            Task { @MainActor in
                self?.handleNativeItemFailure(item, source: source, requestID: requestID,
                                             trigger: .failedToPlayToEnd, reportedError: reportedError)
            }
        }
        let s = center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadRequestID == requestID, self.activeSource?.id == source.id,
                      self.player?.currentItem === item else { return }
                if item.status == .failed {
                    self.handleNativeItemFailure(item, source: source, requestID: requestID, trigger: .itemStatusFailed)
                    return
                }
                // Initial native buffering has one startup owner/deadline. A
                // recoverable notification cannot start a competing stall timer.
                guard self.initialNativeStartupRequestID != requestID else { return }
                self.validateRecoverableStall(
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
                    guard self.loadRequestID == requestID, self.activeSource?.id == source.id,
                          self.player?.currentItem === item else { return }
                    let snapshot = self.diagnosticService.analyze(item, trigger: .errorLog)
                    if item.status == .failed {
                        self.handleNativeItemFailure(item, source: source, requestID: requestID,
                                                     trigger: .errorLog)
                    } else if self.initialNativeStartupRequestID != requestID,
                              self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate {
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
        // Error-log notifications are not a substitute for item status. A fatal
        // item can otherwise enter .paused and disarm the watchdog without a
        // later log notification, leaving a stopped CS item selected forever.
        playerItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.handleNativeItemFailure(item, source: source, requestID: requestID,
                                             trigger: .itemStatusFailed)
            }
        }
    }

    func removeItemFailureObservers() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        playerItemNotificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        playerItemNotificationTokens = []
    }

    func handleNativeItemFailure(_ item: AVPlayerItem, source: StreamSource, requestID: UUID,
                                 trigger: NativePlaybackDiagnosticTrigger, reportedError: Error? = nil) {
        guard isPlaybackSessionActive, !isUsingWebEmbed,
              pendingSingleDiscoveryFailure == nil,
              loadRequestID == requestID, activeSource?.id == source.id,
              player?.currentItem === item else { return }
        // A late AVFoundation notification cannot resurrect an attempt that
        // already ended in the single-player error screen. Explicit Retry or
        // source selection creates its own new attempt before reaching here.
        if viewingPlaybackContext == .single, playbackState == .failed { return }
        if trigger == .itemStatusFailed || trigger == .errorLog {
            guard item.status == .failed else { return }
        }
        // Notification, status KVO and an error-log callback may all report the
        // same background fatal item. One item/attempt owns one receipt/recovery.
        if let observation = nativeItemFailureObservation,
           observation.matches(item: item, sourceID: source.id, requestID: requestID) {
            // Deduplicate persistence, not freshness. Brief progress between
            // two failures cannot count as recovery after the newer boundary.
            if isAppBackgrounded, observation.awaitsForegroundRecovery {
                observation.mediaSecondAtObservation = player?.currentTime().seconds ?? .nan
            }
            return
        }
        let snapshot = diagnosticService.analyze(item, trigger: trigger, reportedError: reportedError)
        let details = nativeDiagnosticDetails(snapshot)
        if isAppBackgrounded, viewingPlaybackContext == .single {
            nativeItemFailureObservation = NativeItemFailureObservation(item: item, sourceID: source.id,
                requestID: requestID, reason: snapshot.failureReason, diagnosticDetails: details,
                mediaSecondAtObservation: player?.currentTime().seconds ?? .nan,
                awaitsForegroundRecovery: true)
            let failureKind = LivePlaybackFailureKind.classify(reason: snapshot.failureReason,
                countsAsStall: false, isNetworkReachable: isNetworkReachable)
            recordSourceFailure(reason: snapshot.failureReason, failureKind: failureKind,
                diagnosticDetails: details.merging(["reason_code": "native_failure_backgrounded",
                    "playback_intent": String(userWantsPlayback)]) { _, value in value })
            return
        }
        handleSourceStartupFailure(source, reason: snapshot.failureReason,
                                   expectedRequestID: requestID, diagnosticDetails: details)
    }

    /// Consume once before the ordinary foreground-resume guard: a valid PiP
    /// background transition deliberately sets shouldResumeAfterForeground=false.
    /// Replaced owners and explicit Pause never inherit this recovery request.
    private func recoverObservedBackgroundNativeFailure() -> Bool {
        guard let observation = nativeItemFailureObservation, observation.awaitsForegroundRecovery else { return false }
        observation.awaitsForegroundRecovery = false
        guard viewingPlaybackContext == .single, !isUsingWebEmbed,
              observation.matches(item: player?.currentItem, sourceID: activeSource?.id,
                                  requestID: loadRequestID), let source = activeSource else {
            nativeItemFailureObservation = nil
            return false
        }
        guard userWantsPlayback else { return false }
        // A notification can precede a successful same-item recovery. Never
        // replace video that has since genuinely advanced; .playing alone is
        // not sufficient, nor can progress overrule a failed item status.
        if let player, let item = player.currentItem,
           retireNativeFailureAfterDisplayedProgress(item: item, sourceID: source.id,
               requestID: observation.requestID, currentSeconds: player.currentTime().seconds) {
            return false
        }
        shouldResumeAfterForeground = false
        recoverSourceStartupFailure(source, reason: observation.reason, expectedRequestID: observation.requestID,
            diagnosticDetails: observation.diagnosticDetails, recordFailure: false)
        return true
    }

    /// The exact incident ends only after ready video advances beyond its latest
    /// fatal boundary. Transport .playing, a Play command or an old start receipt
    /// cannot retire this deduplication lease or authorize another retry.
    @discardableResult
    private func retireNativeFailureAfterDisplayedProgress(item: AVPlayerItem, sourceID: UUID,
                                                           requestID: UUID, currentSeconds: Double) -> Bool {
        guard viewingPlaybackContext == .single, let observation = nativeItemFailureObservation,
              observation.matches(item: item, sourceID: sourceID, requestID: requestID),
              item.status == .readyToPlay,
              NativePlaybackVideoPolicy.hasDisplayedProgress(isReadyForDisplay: isVideoReadyForDisplay,
                  startSeconds: observation.mediaSecondAtObservation, currentSeconds: currentSeconds) else { return false }
        nativeItemFailureObservation = nil
        return true
    }

    private func nativeDiagnosticDetails(_ snapshot: PlayerDiagnosticService.DiagnosticSnapshot) -> [String: String] {
        snapshot.qualityDetails.merging(streamProxy?.diagnosticDetails() ?? [:]) { _, value in value }
    }

    // Relay evidence belongs only to the currently selected item attempt. A
    // delayed validator/catch must not attribute a new source's relay to an old
    // preparation failure; the failure handler separately fences publication.
    private func preparationDiagnosticDetails(_ details: [String: String], source: StreamSource,
                                              requestID: UUID) -> [String: String] {
        guard isPlaybackSessionActive, loadRequestID == requestID, activeSource?.id == source.id else { return [:] }
        return details.merging(streamProxy?.diagnosticDetails() ?? [:]) { _, value in value }
    }

    func handleSourceStartupFailure(
        _ source: StreamSource,
        reason: String,
        countsAsStall: Bool = false,
        expectedRequestID: UUID? = nil,
        diagnosticDetails: [String: String] = [:]
    ) {
        recoverSourceStartupFailure(source, reason: reason, countsAsStall: countsAsStall,
            expectedRequestID: expectedRequestID, diagnosticDetails: diagnosticDetails, recordFailure: true)
    }

    /// A web provider reports failures as text, never typed diagnostics. A
    /// stall, timeout or generic failure after its one same-source reload may
    /// still look for a fresh delivery. An explicit provider rejection or an
    /// unsupported/denied source is final for this attempt.
    nonisolated static func webFailureCanAwaitFreshDelivery(failureKind: LivePlaybackFailureKind,
                                                           reason: String) -> Bool {
        guard !LivePlaybackPolicy.isExplicitProviderRejection(reason) else { return false }
        switch failureKind {
        case .stalled, .startupTimeout, .sourceFailure, .network, .unknown: return true
        case .accessDenied, .decodeFailure, .providerUnavailable, .proxy, .resumeFailure, .unsupportedSource:
            return false
        }
    }

    private func canAwaitFreshSingleDelivery(failureKind: LivePlaybackFailureKind,
                                             structuredFailure: LivePlaybackStructuredFailure?,
                                             diagnosticDetails: [String: String]) -> Bool {
        let reason = diagnosticDetails["preparation_reason"]
        if ["unsafe_redirect", "descriptor_fixture_changed", "invalid_match_mapping", "unsafe_response"].contains(reason ?? "") {
            return false
        }
        if structuredFailure?.httpStatus != nil { return true }
        // Jet, 8 Nov: CS5 decoded for 55 min, stalled, and every remaining
        // alternative came from the same hour-old discovery and failed within
        // 35 s. The last one was classified `unknown`, which ended the session
        // with no fresh lookup. Once this session has decoded, any non-hard
        // failure earns the single exhausted-delivery lookup; the fresh
        // resolver still owns identity and transport admission.
        if playbackIntervals.hasDecodedDuringSession, !event.isBroadcastChannel,
           structuredFailure?.disallowsAutomaticRetry != true,
           ![.accessDenied, .unsupportedSource, .proxy].contains(failureKind) { return true }
        if reason == PlaybackPreparationDiagnostic.Reason.leaseExpired.rawValue { return true }
        if failureKind == .startupTimeout {
            return diagnosticDetails["native_failure_trigger"] == NativePlaybackDiagnosticTrigger.readinessTimeout.rawValue
                || (diagnosticDetails["preparation_stage"] == PlaybackPreparationDiagnostic.Stage.playbackStart.rawValue
                    && reason == PlaybackPreparationDiagnostic.Reason.playbackStartTimeout.rawValue)
        }
        if structuredFailure?.category == .decode, reason == nil {
            return [NativePlaybackDiagnosticTrigger.itemStatusFailed.rawValue,
                    NativePlaybackDiagnosticTrigger.failedToPlayToEnd.rawValue]
                .contains(diagnosticDetails["native_failure_trigger"] ?? "")
        }
        return structuredFailure?.category == .network && isNetworkReachable
            && (reason == nil || reason == PlaybackPreparationDiagnostic.Reason.transportError.rawValue)
    }

    private func recoverSourceStartupFailure(
        _ source: StreamSource,
        reason: String,
        countsAsStall: Bool = false,
        expectedRequestID: UUID? = nil,
        diagnosticDetails: [String: String] = [:],
        recordFailure: Bool
    ) {
        guard isPlaybackSessionActive, !isAppBackgrounded, userWantsPlayback,
              pendingSingleDiscoveryFailure == nil,
              activeSource?.id == source.id else { return }
        if let expectedRequestID, expectedRequestID != loadRequestID { return }
        // Repeated bridge reports during the same recovery delay must not
        // consume the next retry/failover. An explicit provider rejection still
        // gets its normal terminal handling instead of waiting on a timer.
        if webRetryTask != nil, isNetworkReachable,
           !LivePlaybackPolicy.isExplicitProviderRejection(reason) { return }
        let isForcedWebEmbed = forceWebEmbedSourceIDs.contains(source.id)
        let structuredFailure: LivePlaybackStructuredFailure? = usesSingleStreamRanking && viewingPlaybackContext == .single
            ? .fromDiagnosticDetails(diagnosticDetails) : nil
        var recoveryAction = LivePlaybackRecoveryPolicy.action(
            for: .init(
                reason: reason,
                countsAsStall: countsAsStall,
                isNetworkReachable: isNetworkReachable,
                isNativeHandoff: nativeHandoffSession?.id == source.id && !isForcedWebEmbed,
                isWebEmbed: isWebEmbedSource(source),
                isForcedWebEmbed: isForcedWebEmbed,
                webStartupRetryCount: webStartupRetryAttemptsBySource[source.id, default: 0],
                webStallRetryCount: webStallRetryAttemptsBySource[source.id, default: 0],
                isDirectMedia: activeSession?.playbackContract.endpoint == .directMedia,
                nativeStartupRetryCount: nativeStartupRetryAttemptsBySource[source.id, default: 0],
                structuredFailure: structuredFailure
            )
        )
        let hardPreparationFailure = ["unsafe_redirect", "descriptor_fixture_changed", "invalid_match_mapping", "unsafe_response", "lease_expired"]
            .contains(diagnosticDetails["preparation_reason"] ?? "")
        if viewingPlaybackContext == .single,
           structuredFailure?.disallowsAutomaticRetry == true || hardPreparationFailure,
           case .waitForNetwork = recoveryAction {
            // A current typed denial/unsupported contract is not a device-route
            // interruption. An offline flag must not authorize its replay.
            recoveryAction = .exhaustSource(.classify(reason: reason, countsAsStall: countsAsStall,
                isNetworkReachable: true, structuredFailure: structuredFailure))
        }
        if case .exhaustSource = recoveryAction,
           usesSingleStreamRanking, viewingPlaybackContext == .single,
           !isPlaybackSessionRetired, !isUsingWebEmbed, isPlaying, playbackIntervals.hasDecoded,
           countsAsStall, diagnosticDetails["native_failure_trigger"] == NativePlaybackDiagnosticTrigger.stallTimeout.rawValue,
           isNetworkReachable, !isForcedWebEmbed, !LivePlaybackPolicy.isExplicitProviderRejection(reason),
           structuredFailure?.disallowsAutomaticRetry != true,
           let session = activeSession, session.playbackContract.endpoint == .directMedia,
           let binding = session.eventBinding, ["communitysports", "plaviosports", "reviewedtv"].contains(binding.providerCode),
           !event.hasCatalogIdentityConflict, MatchStartPolicy(event: event).timingAllowsPlayback,
           binding.matchesIdentity(request: StreamPlaybackRequest(event: event), providerCode: binding.providerCode),
           session.canRefresh, nativeStartupRetryAttemptsBySource[source.id, default: 0] < 1,
           !descriptorRefreshAttempts.contains(source.id), player?.currentItem != nil,
           let relay = streamProxy,
           nativePlaylistIsNonAdvancing(relay)
                || (diagnosticDetails["preparation_reason"] == nil && nativePlaylistIsAdvancing(relay)) {
            // Spend the existing ONE native retry on a freshly resolved exact
            // choice when this relay has a current live-window observation.
            // Preparation failures cannot acquire advancing-window recovery;
            // the fresh resolver still owns delivery/identity admission.
            requiredDescriptorRefreshSourceIDs.insert(source.id)
            recoveryAction = .retryNativeStartup(.stalled)
        }
        let failureKind = recoveryAction.failureKind
        traceRecovery("\(source.provider) \(failureKind.rawValue) stall=\(countsAsStall) decoded=\(playbackIntervals.hasDecoded) reachable=\(isNetworkReachable) \(diagnosticDetails["preparation_reason"] ?? "")")
        if recordFailure {
            recordSourceFailure(reason: reason, failureKind: failureKind, diagnosticDetails: diagnosticDetails)
        }

        var preferredReplacement: StreamSource?
        switch recoveryAction {
        case .waitForNetwork:
            // Do not punish or replace a provider because the device briefly
            // lost its route. Preserve the exact attempt and let it resume.
            captureSingleNetworkRecovery()
            pendingRetryAfterNetworkRestore = true
            cancelPendingWebRetry()
            stallValidationTask?.cancel()
            stopPlaybackWatchdog()
            error = nil
            transition(to: .recovering(isUsingWebEmbed ? .webEmbed : .native), phase: "Waiting For Network")
            FottyQualityStore.shared.record(
                category: .playback,
                name: "network_interruption",
                outcome: .info,
                details: playbackQualityDetails()
            )
            return

        case .returnNativeHandoffToWeb:
            guard viewingPlaybackContext != .watchTwo(engine: .native) else {
                cancelAudioPreparation()
                withModelOwnedNativeRateCommand { player?.pause() }
                errorTitle = "Choose Another Source"
                error = "This source couldn’t continue in Watch Two. Retry it, choose another source or watch this match on its own."
                transition(to: .failed, phase: "Choose Broadcast Source")
                showControls = true
                return
            }
            retireNativeAudioIsolation()
            nativeHandoffSession = nil
            forceWebEmbedSourceIDs.insert(source.id)
            transition(to: .recovering(.webEmbed), phase: "Returning to web playback")
            FottyQualityStore.shared.record(
                category: .playback,
                name: "native_handoff_return",
                outcome: .recovered,
                details: playbackQualityDetails(["failure_kind": failureKind.rawValue])
            )
            loadCurrentSource(ignoringCircuitBreaker: true)
            return

        case .tryWebFallback:
            guard viewingPlaybackContext != .watchTwo(engine: .native) else {
                errorTitle = "Choose Another Source"
                error = "This source needs a different player. Choose another source or watch this match on its own."
                transition(to: .failed, phase: "Choose Broadcast Source")
                showControls = true
                return
            }
            forceWebEmbedSourceIDs.insert(source.id)
            loadCurrentSource()
            return

        case .retryNativeStartup:
            if usesSingleStreamRanking, viewingPlaybackContext == .single {
                let eligible = LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(
                    in: sessions, for: event, after: source.id, failureKind: failureKind,
                    hasDecoded: playbackIntervals.hasDecoded, hasPositivePlayback: { [event] in
                        event.isBroadcastChannel || !AppRuntime.usesPrivateMatchSelection ? LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: $0)
                            : LiveSourceHealthStore.positiveRecoveryHistory(for: $0, fixtureID: event.id)
                    })
                // Decode and transport errors can arrive without a stall notification.
                // Once a match played, its replacement need not have prior local history.
                let lostPlayingMatch = playbackIntervals.hasDecodedDuringSession && !event.isBroadcastChannel
                let alternative = nextPlayableSource(after: source, allowing: lostPlayingMatch ? nil : eligible)
                if let next = alternative, let index = sources.firstIndex(where: { $0.id == next.id }) {
                    failedSourceIDs.insert(source.id)
                    recordMatchOutcome(.failed, for: source)
                    LiveSourceHealthStore.recordFailure(for: source, wasStall: false, reason: reason)
                    autoFailoverCount += 1
                    FottyQualityStore.shared.record(category: .playback, name: "automatic_failover", outcome: .failure,
                        details: playbackQualityDetails(["failure_kind": failureKind.rawValue]))
                    currentSourceIndex = index
                    prefetchDescriptorRenewals(after: next)
                    showPlaybackBanner("Switching to another source")
                    loadCurrentSource()
                    return
                }
            }
            if usesSingleStreamRanking && viewingPlaybackContext == .single && activeSession?.eventBinding != nil {
                pendingDescriptorRefreshSourceID = source.id
            }
            nativeStartupRetryAttemptsBySource[source.id] = 1
            loadCurrentSource(ignoringCircuitBreaker: true)
            return

        case .retryWebStall:
            webStallRetryAttemptsBySource[source.id] = 1
            retryCurrentWebSource(source, phase: "Reconnecting to this broadcast")
            return

        case .retryWebStartup:
            // A matched native stream may have arrived while the web page was
            // starting. Try it before spending another timeout on that page.
            if usesSingleStreamRanking, viewingPlaybackContext == .single, !event.isBroadcastChannel {
                let directIDs = Set(sessions.filter { $0.playbackContract.endpoint == .directMedia }.map(\.id))
                if !directIDs.isEmpty { preferredReplacement = nextPlayableSource(after: source, allowing: directIDs) }
            }
            if preferredReplacement == nil {
                webStartupRetryAttemptsBySource[source.id] = 1
                retryCurrentWebSource(source, phase: "Retrying this broadcast")
                return
            }

        case .exhaustSource:
            break
        }

        // A terminal result owns this attempt even while platform audio is
        // still preparing. Its late completion must not restart a failed item.
        cancelAudioPreparation()
        stallValidationTask?.cancel()
        foregroundResumeValidationTask?.cancel()
        stopPlaybackWatchdog()
        withModelOwnedNativeRateCommand { player?.pause() }
        failedSourceIDs.insert(source.id)
        recordMatchOutcome(countsAsStall ? .stalled : .failed, for: source)
        LiveSourceHealthStore.recordFailure(for: source, wasStall: countsAsStall, reason: reason)
        if let next = preferredReplacement ?? nextPlayableSource(after: source), let idx = sources.firstIndex(where: { $0.id == next.id }) {
            autoFailoverCount += 1
            FottyQualityStore.shared.record(
                category: .playback,
                name: "automatic_failover",
                outcome: .failure,
                details: playbackQualityDetails(["failure_kind": failureKind.rawValue])
            )
            currentSourceIndex = idx
            prefetchDescriptorRenewals(after: next)
            showPlaybackBanner("Switching to another source")
            loadCurrentSource()
        }
        else if usesSingleStreamRanking, viewingPlaybackContext == .single,
                (isCheckingAdditionalSources && !singleDiscoveryContinuationRevoked ||
                    !isCheckingAdditionalSources && playbackIntervals.hasDecodedDuringSession && !usedExhaustedMatchLookup && !event.isBroadcastChannel &&
                        LivePlaybackSourcePolicy.currentMatchForSwitch(event, in: MatchListViewModel.shared.playbackAdmissionCatalog) != nil),
                !isPlaybackSessionRetired, userWantsPlayback, !isAppBackgrounded,
                !isPictureInPictureActive, !isWebPictureInPictureActive, nativeFullscreen == nil,
                !event.hasCatalogIdentityConflict, MatchStartPolicy(event: event).timingAllowsPlayback,
                isUsingWebEmbed
                    ? Self.webFailureCanAwaitFreshDelivery(failureKind: failureKind, reason: reason)
                    : canAwaitFreshSingleDelivery(failureKind: failureKind, structuredFailure: structuredFailure,
                        diagnosticDetails: diagnosticDetails) {
            // A typed source-local failure still exhausts this delivery.
            // The original discovery may supply one fresh delivery before its
            // own deadline; no failed URL or terminal callback gains a retry.
            let details = playbackQualityDetails(["failure_kind": failureKind.rawValue])
            loadRequestID = UUID()
            pendingSingleDiscoveryFailure = .init(sourceID: source.id, requestID: loadRequestID,
                failureKind: failureKind, qualityDetails: details,
                // Fresh web embeds are revalidated by the resolver but carry no
                // event binding; requiring one would reject every web backup.
                requiresFreshBinding: !isUsingWebEmbed && structuredFailure?.httpStatus == nil)
            shouldResumeAfterForeground = false
            shouldSuspendWebPlayback = true
            error = nil
            transition(to: .connecting(isUsingWebEmbed ? .webEmbed : .native), phase: "Checking more sources…")
            if !isCheckingAdditionalSources {
                usedExhaustedMatchLookup = true
                setSingleSourceDiscoveryActive(true)
                exhaustedMatchLookup = Task { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    if let current = LivePlaybackSourcePolicy.currentMatchForSwitch(event, in: MatchListViewModel.shared.playbackAdmissionCatalog) {
                        let request = StreamPlaybackRequest(event: current, watchID: playbackCorrelation.sessionID)
                        await freshMatchLookup(request) { [weak self] choices in
                            await self?.appendFreshMatchChoices(choices)
                        }
                    }
                    guard !Task.isCancelled else { return }
                    exhaustedMatchLookup = nil
                    setSingleSourceDiscoveryActive(false)
                }
            }
            showControls = true
        }
        else {
            FottyQualityStore.shared.record(
                category: .playback,
                name: "terminal_failure",
                outcome: .failure,
                details: playbackQualityDetails(["failure_kind": failureKind.rawValue])
            )
            errorTitle = failureKind.title
            error = failureKind.terminalMessage
            showControls = true
            transition(to: .failed, phase: "Choose Broadcast Source")
        }
    }

    private func recordSourceFailure(reason: String, failureKind: LivePlaybackFailureKind,
                                     diagnosticDetails: [String: String]) {
        lastFailureKind = failureKind
        lastFailureReason = reason
        FottyQualityStore.shared.record(
            category: .playback, name: "source_failure", outcome: .failure,
            durationMilliseconds: sourceAttemptStartedAt.map { Int(Date().timeIntervalSince($0) * 1_000) },
            details: playbackQualityDetails(diagnosticDetails.merging(["failure_kind": failureKind.rawValue]) { _, value in value })
        )
    }

    private func retryCurrentWebSource(_ source: StreamSource, phase: String) {
        FottyQualityStore.shared.record(
            category: .playback, name: "retry_scheduled", outcome: .info,
            details: playbackQualityDetails(["recovery_kind": "same_source_web_reload"])
        )
        cancelPendingWebRetry()
        let expectedSourceID = source.id
        let expectedRequestID = loadRequestID
        let retryID = UUID()
        webRetryID = retryID
        transition(to: .recovering(.webEmbed), phase: phase)
        showPlaybackBanner(phase)
        let delay = webRetryDelay
        webRetryTask = Task { @MainActor [weak self] in
            defer {
                if self?.webRetryID == retryID {
                    self?.webRetryTask = nil
                    self?.webRetryID = nil
                }
            }
            do { try await delay() } catch { return }
            guard let self, !Task.isCancelled,
                  self.webRetryID == retryID,
                  self.isPlaybackSessionActive, !self.isAppBackgrounded,
                  self.loadRequestID == expectedRequestID,
                  self.activeSource?.id == expectedSourceID,
                  self.isUsingWebEmbed, !self.isWebPlaybackUserPaused,
                  self.isNetworkReachable,
                  self.playbackState == .recovering(.webEmbed) else { return }
            // Clear ownership before loading so the new attempt does not
            // cancel its own initiating task. The timer is single-use.
            self.webRetryTask = nil
            self.webRetryID = nil
            self.loadCurrentSource(ignoringCircuitBreaker: true)
        }
    }

    private func cancelPendingWebRetry() {
        webRetryID = nil
        webRetryTask?.cancel()
        webRetryTask = nil
    }

    func handleWebEmbedFailure(sourceID: UUID, requestID: UUID, reason: String) {
        guard !isRetiringWebForNativeWatchTwo, let source = activeSource,
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
        guard !isRetiringWebForNativeWatchTwo, isPlaybackSessionActive, !isAppBackgrounded,
              !isWebPlaybackUserPaused, let source = activeSource,
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
        guard !isRetiringWebForNativeWatchTwo, isPlaybackSessionActive, !isAppBackgrounded,
              activeSource?.id == sourceID,
              loadRequestID == requestID,
              isUsingWebEmbed,
              !isWebPlaybackUserPaused else { return }
        lastObservedPlaybackStage = .decoded
        if let identity = intervalIdentity {
            playbackIntervals.decodedProgress(identity, now: timing.monotonicNow())?.record()
        }
        error = nil
        FottyQualityStore.shared.record(
            category: .playback,
            name: "in_place_recovery",
            outcome: .recovered,
            details: playbackQualityDetails(["recovery_kind": "decoded_web_progress"])
        )
        transition(to: .playing(.webEmbed), phase: "Playing")
        scheduleAutoHide()
    }

    func handleWebEmbedTransportState(
        _ state: WebPlaybackTransportState, sourceID: UUID, requestID: UUID
    ) {
        // UIKit dismantling already rejects its own teardown messages. A real
        // Pause delivered before that boundary still revokes the captured intent.
        if isRetiringWebForNativeWatchTwo, case .playing = state { return }
        guard isPlaybackSessionActive, !isAppBackgrounded,
              activeSource?.id == sourceID, loadRequestID == requestID,
              isUsingWebEmbed, isVideoReadyForDisplay,
              connectionPhase != "Paused (Background)", error == nil else { return }
        switch state {
        case .paused:
            recordCausalDiagnostic(phase: .webTransport, purpose: .webPlayback, result: .paused)
            userWantsPlayback = false
            isWebPlaybackUserPaused = true
            cancelNativePlaybackTransfer()
            transition(to: .paused(.webEmbed), phase: "Paused")
            showControls = true
        case .playing:
            recordCausalDiagnostic(phase: .webTransport, purpose: .webPlayback, result: .playing)
            userWantsPlayback = true
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
        transition(to: userWantsPlayback ? .playing(.webEmbed) : .paused(.webEmbed),
                   phase: userWantsPlayback ? "Playing" : "Paused")
    }

    func handleNativePlaybackCandidate(
        _ candidate: NativeWebPlaybackCandidate,
        sourceID: UUID,
        requestID: UUID
    ) {
        guard isPlaybackSessionActive, !isPlaybackSessionRetired, isUsingWebEmbed,
              activeSource?.id == sourceID, loadRequestID == requestID else { return }
        // Discovery is passive. A muted second decoder can still interrupt
        // WebKit, so only an explicit single-view action may start this transfer.
        cachedNativeCandidate = (candidate, sourceID, requestID)
    }

    /// No Play or shared audio operation is permitted during this preflight.
    /// Both original pictures remain mounted until the coordinator commits.
    func prepareNativeWatchTwoCandidate() async -> PreparedNativeWatchTwoPlayback? {
        let began = Date()
        let initialDetails = playbackQualityDetails()
        var outcome = NativeWatchTwoPreflightOutcome.notEligible
        var stage = NativeWatchTwoPreflightStage.admission
        var proxy: LocalStreamProxy?
        var candidatePlayer: AVPlayer?
        var isolation: NativePlayerAudioIsolation?
        var retained = false
        defer {
            nativeWatchTwoPreflightOutcome = outcome
            var details = initialDetails.merging([
                "mode": "native_pair_preflight", "preparation_stage": stage.rawValue,
                "preparation_reason": outcome.rawValue
            ]) { _, new in new }
            if let item = candidatePlayer?.currentItem {
                switch item.status {
                case .unknown: details["native_item_status"] = "unknown"
                case .readyToPlay: details["native_item_status"] = "ready"
                case .failed: details["native_item_status"] = "failed"
                @unknown default: details["native_item_status"] = "other"
                }
                if let error = item.error as NSError? {
                    details["native_error_domain"] = NativePlaybackErrorDomain(error.domain).rawValue
                    details["native_error_code"] = String(error.code)
                }
                if item.status == .failed {
                    details.merge(diagnosticService.analyze(item, trigger: .itemStatusFailed).qualityDetails) { _, new in new }
                }
            }
            // This preflight owns a different relay from the active Web stream.
            // Capture its bounded receipt before cleanup, never the active owner's.
            details.merge(proxy?.diagnosticDetails() ?? [:]) { _, new in new }
            FottyQualityStore.shared.record(category: .playback, name: "native_pair_preflight",
                outcome: retained ? .success : (outcome == .cancelled || outcome == .staleOwner ? .info : .failure),
                durationMilliseconds: Int(Date().timeIntervalSince(began) * 1000), details: details)
            if !retained {
                candidatePlayer?.pause(); proxy?.stop()
                if let barrier = isolation?.request(disconnected: true) { rememberNativeAudioRetirement(barrier) }
            }
        }
        guard nativeAudioIsolationBackend.isSupported else { outcome = .unsupported; return nil }
        guard case .watchTwo(engine: .web) = viewingPlaybackContext,
              preparedNativeWatchTwo == nil,
              isPlaybackSessionActive, !isPlaybackSessionRetired, isUsingWebEmbed,
              isVideoReadyForDisplay, !isAppBackgrounded, !isWebPictureInPictureActive,
              nativeFullscreen == nil, nativeHandoffTask == nil, let selected = selectedSession else { return nil }
        guard let cached = cachedNativeCandidate else { outcome = .noCandidate; return nil }
        guard cached.sourceID == selected.id, cached.requestID == loadRequestID else {
            outcome = .staleCandidate; return nil
        }
        let request = loadRequestID, intent = nativeWatchTwoIntentID
        let wanted = userWantsPlayback
        func current() -> Bool {
            !Task.isCancelled && isPlaybackSessionActive && !isPlaybackSessionRetired
                && viewingPlaybackContext == .watchTwo(engine: .web) && isUsingWebEmbed
                && activeSource?.id == selected.id && loadRequestID == request
                && nativeWatchTwoIntentID == intent && userWantsPlayback == wanted
                && !isAppBackgrounded && !isWebPictureInPictureActive && nativeFullscreen == nil
        }
        func stillCurrent() -> Bool {
            guard current() else {
                outcome = Task.isCancelled ? .cancelled : .staleOwner
                return false
            }
            return true
        }
        // Validate the same scoped delivery AVPlayer will use. A fresh direct
        // probe omits captured WK cookies and can reject an otherwise valid HLS.
        // The existing relay retains cookie scope and all origin/redirect checks.
        stage = .proxy
        guard let preparedURL = try? await prepareNativeHandoffURL(for: cached.candidate) else {
            outcome = Task.isCancelled ? .cancelled : .proxyFailed; return nil
        }
        proxy = preparedURL.proxy
        guard stillCurrent() else { return nil }
        let headers = proxy == nil ? cached.candidate.headers : [:]
        stage = .validation
        let validation = await validateNativeSource(preparedURL.url, headers)
        guard stillCurrent() else { return nil }
        guard validation.isValid else { outcome = .validationRejected; return nil }
        let session = NativePlaybackPreparation.capturedSession(from: selected, candidate: cached.candidate,
                                                               evidence: validation.mediaEvidence)
        let item = NativePlaybackPreparation.makeItem(url: preparedURL.url, headers: headers,
                                                      session: session, evidence: validation.mediaEvidence)
        let candidate = AVPlayer(playerItem: item)
        candidatePlayer = candidate
        candidate.isMuted = true; candidate.automaticallyWaitsToMinimizeStalling = true
        MediaAudioSession.configureNativeBackgroundPlayback(candidate)
        let controller = makeNativeAudioIsolation(player: candidate, item: item,
            sourceID: selected.id, requestID: request)
        isolation = controller
        stage = .isolation
        let disconnected = await controller.request(disconnected: true).wait()
        guard stillCurrent() else { return nil }
        guard disconnected else { outcome = .isolationFailed; return nil }
        stage = .readiness
        let ready = await waitForSourceReadiness(item, timeoutSeconds: 7)
        guard stillCurrent() else { return nil }
        guard ready else {
            outcome = item.status == .failed ? .readinessFailed : .readinessTimeout
            return nil
        }
        let prepared = PreparedNativeWatchTwoPlayback(model: self, session: session,
            player: candidate, item: item, isolation: controller, proxy: proxy, delivery: cached.candidate)
        stage = .registration
        guard registerNativeWatchTwoPreparation(prepared) else { outcome = .registrationRejected; return nil }
        retained = true
        outcome = .prepared
        return prepared
    }

    @discardableResult
    func registerNativeWatchTwoPreparation(_ prepared: PreparedNativeWatchTwoPlayback) -> Bool {
        guard preparedNativeWatchTwo == nil, nativeAudioIsolationBackend.isSupported,
              prepared.modelID == remoteCommandOwnerID, prepared.sourceID == activeSource?.id,
              prepared.requestID == loadRequestID, prepared.intentID == nativeWatchTwoIntentID,
              prepared.wantsPlayback == userWantsPlayback,
              prepared.context == .watchTwo(engine: .web), viewingPlaybackContext == prepared.context,
              isPlaybackSessionActive, !isPlaybackSessionRetired, isUsingWebEmbed,
              !isAppBackgrounded, !isWebPictureInPictureActive, nativeFullscreen == nil,
              prepared.player.currentItem === prepared.item, prepared.player.rate == 0,
              prepared.player.isMuted, prepared.isolation.player === prepared.player,
              prepared.isolation.item === prepared.item,
              prepared.isolation.currentBarrier?.isSatisfiedDisconnection == true,
              !prepared.discarded, !prepared.adopted else { return false }
        preparedNativeWatchTwo = prepared
        return true
    }

    func nativeWatchTwoPreparationIsCurrent(_ prepared: PreparedNativeWatchTwoPlayback) -> Bool {
        guard !Task.isCancelled, isPlaybackSessionActive, !isPlaybackSessionRetired,
              preparedNativeWatchTwo === prepared, !prepared.discarded,
              prepared.modelID == remoteCommandOwnerID, prepared.sourceID == activeSource?.id,
              prepared.requestID == loadRequestID, prepared.intentID == nativeWatchTwoIntentID,
              prepared.wantsPlayback == userWantsPlayback,
              !isAppBackgrounded, !isWebPictureInPictureActive, !isPictureInPictureActive,
              nativeFullscreen == nil, prepared.player.currentItem === prepared.item else { return false }
        return prepared.adopted
            ? (viewingPlaybackContext == .watchTwo(engine: .native) || viewingPlaybackContext == .single)
                && player === prepared.player
            : viewingPlaybackContext == prepared.context && isUsingWebEmbed
    }

    func beginNativeWatchTwoRetirement(_ prepared: PreparedNativeWatchTwoPlayback) -> Bool {
        guard nativeWatchTwoPreparationIsCurrent(prepared), !prepared.retirementBegan else { return false }
        prepared.retirementBegan = true
        cancelPendingWebRetry(); loadTask?.cancel(); stopPlaybackWatchdog()
        stallValidationTask?.cancel(); foregroundResumeValidationTask?.cancel()
        isRetiringWebForNativeWatchTwo = true
        transition(to: .connecting(.native), phase: "Switching players…")
        // Removing the actual representable invokes its public suspension and
        // teardown acknowledgement. No native decoder or audio starts here.
        return true
    }

    func waitForNativeWatchTwoRetirement(_ prepared: PreparedNativeWatchTwoPlayback) async -> Bool {
        for _ in 0..<60 {
            guard nativeWatchTwoPreparationIsCurrent(prepared), prepared.retirementBegan else { return false }
            if prepared.webRetired { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return prepared.webRetired && nativeWatchTwoPreparationIsCurrent(prepared)
    }

    func adoptNativeWatchTwoCandidate(_ prepared: PreparedNativeWatchTwoPlayback) -> Bool {
        guard nativeWatchTwoPreparationIsCurrent(prepared), prepared.retirementBegan,
              prepared.webRetired, !prepared.adopted else { return false }
        nativeWatchTwoAudioHeld = true
        nativeHandoffSession = prepared.session
        nativeWatchTwoDelivery = prepared.delivery
        viewingPlaybackContext = .watchTwo(engine: .native)
        forceWebEmbedSourceIDs.remove(prepared.sourceID)
        nativeHandoffAwaitingWebRetirement = false
        nativeHandoffAudioMuteHeld = true
        player = prepared.player
        nativeHandoffAudioMuteHeld = true
        nativeAudioIsolation = prepared.isolation
        streamProxy?.stop(); streamProxy = prepared.proxy
        prepared.adopted = true
        isVideoReadyForDisplay = false; error = nil
        configureItemFailureObservers(for: prepared.item, source: prepared.session.legacySource,
            requestID: prepared.requestID)
        transition(to: prepared.wantsPlayback ? .connecting(.native) : .paused(.native),
            phase: prepared.wantsPlayback ? "Starting broadcast…" : "Paused")
        applyViewingAudioState()
        return true
    }

    func startNativeWatchTwoCandidate(_ prepared: PreparedNativeWatchTwoPlayback) {
        guard nativeWatchTwoPreparationIsCurrent(prepared), prepared.adopted,
              prepared.webRetired, !prepared.started else { return }
        prepared.started = true
        guard prepared.wantsPlayback else { return } // Never probe a deliberately paused pane.
        let request = loadRequestID, source = prepared.session.legacySource, intent = audioIntentID
        initialNativeStartupRequestID = request
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { if initialNativeStartupRequestID == request { initialNativeStartupRequestID = nil } }
            guard nativeWatchTwoPreparationIsCurrent(prepared),
                  await requestPlaybackStart(player: prepared.player) else { return }
            let deadline = NativePlaybackStartupDeadline(startedAt: timing.monotonicNow())
            let result = await waitForInitialNativeStartup(player: prepared.player, item: prepared.item,
                source: source, requestID: request, intentID: intent, deadline: deadline)
            guard nativeWatchTwoPreparationIsCurrent(prepared), userWantsPlayback else { return }
            switch result {
            case .started: handleSuccessfulStartup(source: source, expectedRequestID: request)
            case .failed: handleNativeItemFailure(prepared.item, source: source, requestID: request, trigger: .itemStatusFailed)
            case .timedOut:
                handleSourceStartupFailure(source, reason: "Native pair startup timeout.", expectedRequestID: request,
                    diagnosticDetails: nativeStartupTimeoutDetails(player: prepared.player, item: prepared.item, deadline: deadline))
            case .abandoned, .invalidTiming, .waiting: break
            }
        }
    }

    func releaseNativeWatchTwoAudioHold(_ prepared: PreparedNativeWatchTwoPlayback) {
        guard nativeWatchTwoPreparationIsCurrent(prepared), prepared.adopted, prepared.started else { return }
        nativeWatchTwoAudioHeld = false
    }

    func discardNativeWatchTwoCandidate(_ prepared: PreparedNativeWatchTwoPlayback) {
        guard !prepared.adopted, !prepared.discarded else { return }
        prepared.discarded = true
        prepared.player.pause(); prepared.proxy?.stop()
        rememberNativeAudioRetirement(prepared.isolation.request(disconnected: true))
        if preparedNativeWatchTwo === prepared {
            preparedNativeWatchTwo = nil
            if prepared.retirementBegan, loadRequestID == prepared.requestID, !isPlaybackSessionRetired {
                errorTitle = "Player Switch Interrupted"
                error = "Choose a source to retry, or watch one match."
                transition(to: .failed, phase: "Choose Broadcast Source")
            }
        }
    }

    private func beginNativePlaybackTransfer(
        _ candidate: NativeWebPlaybackCandidate, sourceID: UUID, requestID: UUID
    ) {
        // Without actual session isolation, a muted native probe can interrupt
        // the proven Web owner. Older OSes keep that owner instead of probing.
        guard let transferID = explicitNativeTransferID, viewingPlaybackContext == .single,
              nativeAudioIsolationBackend.isSupported, activeSource?.id == sourceID,
              loadRequestID == requestID,
              isUsingWebEmbed,
              !isAppBackgrounded,
              !isWebPictureInPictureActive,
              isVideoReadyForDisplay,
              isPlaying,
              nativeHandoffTask == nil else { return }

        let candidateKey = "\(sourceID.uuidString)|\(candidate.url.absoluteString)"
        guard attemptedNativeCandidateURLs.count < 12,
              attemptedNativeCandidateURLs.insert(candidateKey).inserted,
              let selectedSession else { return }

        let diagnosticOperation = UUID()
        diagnosticCandidateCount = min(diagnosticCandidateCount + 1, 12)
        handoffDiagnosticOperationID = diagnosticOperation
        handoffDiagnosticPhase = .preparingURL
        let observedContext = captureCausalDiagnosticContext()
        recordCausalDiagnostic(phase: .candidateObserved, purpose: .nativeHandoff, result: .began,
                               operationID: diagnosticOperation, context: observedContext)
        transition(to: .preparingNativeHandoff, phase: "Playing")
        nativeTransferTaskID = transferID
        nativeHandoffTask = Task { [weak self] in
            guard let self else { return }
            var candidateProxy: LocalStreamProxy?
            var candidateIsolation: NativePlayerAudioIsolation?
            var preparingPlayer: AVPlayer?
            var adoptedCandidate = false
            var capturedCandidateReadinessDiagnostic = false
            var terminalResult = FottyPlaybackDiagnosticResult.cancelled
            var terminalContext = observedContext
            defer {
                if !capturedCandidateReadinessDiagnostic, let context = terminalContext, let candidateProxy {
                    terminalContext = .init(identity: context.identity,
                        details: context.details.merging(candidateProxy.diagnosticDetails()) { _, value in value })
                }
                if !adoptedCandidate {
                    preparingPlayer?.pause()
                    candidateProxy?.stop()
                    let retirement = candidateIsolation?.request(disconnected: true)
                    if let retirement { rememberNativeAudioRetirement(retirement) }
                    // Resume WK's owned interruption only after the candidate
                    // is paused and any in-flight audio change has reconciled.
                    Task { [weak self] in
                        let safe = await retirement?.wait() ?? true
                        guard let self, self.loadRequestID == requestID,
                              self.nativeTransferSuspensionID == transferID else { return }
                        if safe { self.nativeTransferSuspensionID = nil; self.nativeTransferAcknowledgedID = nil }
                        else {
                            self.errorTitle = "Playback Interrupted"
                            self.error = "Playback could not safely change audio. Retry this source."
                            self.transition(to: .failed, phase: "Audio Transition Interrupted")
                        }
                    }
                }
                recordCausalDiagnostic(phase: .candidateFinished, purpose: .nativeHandoff, result: terminalResult,
                                       operationID: diagnosticOperation, context: terminalContext)
                if handoffDiagnosticOperationID == diagnosticOperation, !adoptedCandidate {
                    handoffDiagnosticOperationID = nil
                    handoffDiagnosticPhase = .none
                }
                if self.nativeTransferTaskID == transferID {
                    self.nativeHandoffTask = nil
                    self.nativeTransferTaskID = nil
                }
                if self.preparingNativeTransferPlayerID == transferID {
                    self.preparingNativeTransferPlayer = nil
                    self.preparingNativeTransferPlayerID = nil
                }
                if self.explicitNativeTransferID == transferID {
                    self.explicitNativeTransferID = nil
                    if !adoptedCandidate, self.loadRequestID == requestID {
                        self.showPlaybackBanner("Couldn’t switch players. Your original source is unchanged.")
                    }
                }
            }

            let playbackURL: URL
            terminalContext = advanceHandoffDiagnosticPhase(.preparingURL, sourceID: sourceID,
                requestID: requestID, operationID: diagnosticOperation) ?? terminalContext
            do {
                let prepared = try await prepareNativeHandoffURL(for: candidate)
                playbackURL = prepared.url
                candidateProxy = prepared.proxy
            } catch {
                terminalResult = Task.isCancelled
                    ? handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID) : .preparationFailed
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            // Validate the same scoped delivery that will be given to AVPlayer.
            // A direct probe loses captured WK cookie scope and can falsely
            // reject media which is valid through this already-admitted relay.
            guard !Task.isCancelled, loadRequestID == requestID, activeSource?.id == sourceID,
                  !isAppBackgrounded, !isWebPictureInPictureActive,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                terminalResult = handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID)
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }
            let assetHeaders = candidateProxy == nil ? candidate.headers : [:]
            terminalContext = advanceHandoffDiagnosticPhase(.validation, sourceID: sourceID,
                requestID: requestID, operationID: diagnosticOperation) ?? terminalContext
            let validation = await validateNativeSource(playbackURL, assetHeaders)
            guard validation.isValid, !Task.isCancelled,
                  loadRequestID == requestID, activeSource?.id == sourceID,
                  !isAppBackgrounded, !isWebPictureInPictureActive,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                let abandonment = handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID)
                if !Task.isCancelled, abandonment == .cancelled, case .invalid = validation {
                    terminalResult = .validationRejected
                    if case .invalid(_, let diagnostic) = validation, let diagnostic, let context = terminalContext {
                        terminalContext = .init(identity: context.identity,
                            details: context.details.merging(diagnostic.qualityDetails) { _, value in value })
                    }
                } else { terminalResult = abandonment }
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            let nativeSession = NativePlaybackPreparation.capturedSession(from: selectedSession,
                candidate: candidate, evidence: validation.mediaEvidence)
            let item = NativePlaybackPreparation.makeItem(url: playbackURL, headers: assetHeaders,
                session: nativeSession, evidence: validation.mediaEvidence)
            // This candidate is muted and has no visible layer until ownership
            // transfers. Pull real frames instead of waiting for a nonexistent
            // layer or treating its audio/transport clock as decoded video.
            let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
            item.add(videoOutput)
            defer { item.remove(videoOutput) }
            let candidatePlayer = AVPlayer(playerItem: item)
            preparingPlayer = candidatePlayer
            guard registerNativeTransferCandidate(candidatePlayer, transferID: transferID,
                sourceID: sourceID, requestID: requestID) else {
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }
            MediaAudioSession.configureNativeBackgroundPlayback(candidatePlayer)
            candidatePlayer.automaticallyWaitsToMinimizeStalling = true
            candidatePlayer.isMuted = true

            terminalContext = advanceHandoffDiagnosticPhase(.readiness, sourceID: sourceID,
                requestID: requestID, operationID: diagnosticOperation) ?? terminalContext
            let ready = await waitForSourceReadiness(item, timeoutSeconds: 7)
            guard ready,
                  !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == sourceID,
                  !isAppBackgrounded,
                  !isWebPictureInPictureActive,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                let abandonment = handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID)
                if !ready && !Task.isCancelled && abandonment == .cancelled {
                    let status = item.status
                    terminalResult = status == .failed ? .preparationFailed : .readinessTimeout
                    if let context = terminalContext {
                        let diagnostic = diagnosticService.analyze(item,
                            trigger: status == .failed ? .itemStatusFailed : .readinessTimeout)
                        let details = NativeHandoffCandidateDiagnostic.details(itemStatus: status,
                            native: diagnostic, candidateRelayDetails: candidateProxy?.diagnosticDetails() ?? [:])
                        terminalContext = .init(identity: context.identity,
                            details: context.details.merging(details) { _, value in value })
                        capturedCandidateReadinessDiagnostic = true
                    }
                } else { terminalResult = abandonment }
                candidatePlayer.pause()
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            terminalContext = advanceHandoffDiagnosticPhase(.audioPreparation, sourceID: sourceID,
                requestID: requestID, operationID: diagnosticOperation) ?? terminalContext
            let prepared = await prepareMutedNativeHandoffAudio(sourceID: sourceID, requestID: requestID)
            guard prepared.mayContinue, !Task.isCancelled, userWantsPlayback,
                  loadRequestID == requestID, activeSource?.id == sourceID,
                  !isAppBackgrounded, !isWebPictureInPictureActive,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                terminalResult = handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID)
                candidatePlayer.pause()
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }
            candidateIsolation = await prepareNativeCandidateAudioIsolation(player: candidatePlayer,
                sourceID: sourceID, requestID: requestID)
            guard candidateIsolation != nil, !Task.isCancelled, userWantsPlayback,
                  loadRequestID == requestID, activeSource?.id == sourceID,
                  !isAppBackgrounded, !isWebPictureInPictureActive,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff else {
                terminalResult = handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID)
                candidatePlayer.pause()
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }
            terminalContext = advanceHandoffDiagnosticPhase(.decoding, sourceID: sourceID,
                requestID: requestID, operationID: diagnosticOperation) ?? terminalContext
            guard explicitNativeTransferID == transferID, viewingPlaybackContext == .single else {
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }
            guard beginNativeTransferSuspension(sourceID: sourceID, requestID: requestID) == transferID,
                  await waitForNativeTransferSuspension(transferID, sourceID: sourceID, requestID: requestID),
                  nativeTransferSuspensionAcknowledged(transferID, sourceID: sourceID, requestID: requestID),
                  candidatePlayer.currentItem === item else {
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }
            candidatePlayer.play()
            let started = await waitForVerifiedVideoStart(
                player: candidatePlayer, timeoutSeconds: 4, videoOutput: videoOutput
            )
            guard started,
                  !Task.isCancelled,
                  loadRequestID == requestID,
                  activeSource?.id == sourceID,
                  !isAppBackgrounded,
                  !isWebPictureInPictureActive,
                  isUsingWebEmbed, playbackState == .preparingNativeHandoff,
                  nativeTransferSuspensionAcknowledged(transferID, sourceID: sourceID, requestID: requestID) else {
                let abandonment = handoffDiagnosticAbandonment(sourceID: sourceID, requestID: requestID)
                terminalResult = !started && !Task.isCancelled && abandonment == .cancelled ? .decodedTimeout : abandonment
                candidatePlayer.pause()
                finishNativeHandoffPreparation(sourceID: sourceID, requestID: requestID)
                return
            }

            nativeHandoffSession = nativeSession
            withModelOwnedNativeRateCommand { self.player?.pause() }
            streamProxy?.stop()
            holdNativeHandoffAudioUntilWebRetirement()
            player = candidatePlayer
            if let candidateIsolation { adoptNativeAudioIsolation(candidateIsolation) }
            streamProxy = candidateProxy
            adoptedCandidate = true
            terminalResult = .adopted
            _ = advanceHandoffDiagnosticPhase(.awaitingWebRetirement, sourceID: sourceID,
                requestID: requestID, operationID: diagnosticOperation)
            isVideoReadyForDisplay = false
            configureItemFailureObservers(
                for: item,
                source: nativeSession.legacySource,
                requestID: requestID
            )
            handleSuccessfulStartup(source: nativeSession.legacySource, expectedRequestID: requestID)
            showPlaybackBanner("Native player ready")
            // SwiftUI will retire the web surface after adoption. Keep this
            // proven candidate muted until that exact old owner acknowledges
            // media retirement; a fixed delay cannot establish exclusive audio.
        }
    }

    func handleWebPlaybackRetired(sourceID: UUID, requestID: UUID) {
        if mountedWebOwners[requestID] == sourceID {
            mountedWebOwners.removeValue(forKey: requestID)
        }
        let releasedSingleAudio = viewingPlaybackContext == .single && webAudioRevocations.contains {
            !$0.acknowledged && $0.sourceID == sourceID && $0.requestID == requestID
        }
        if activeSource?.id == sourceID, loadRequestID == requestID {
            retiredWebOwner = (sourceID, requestID)
        }
        if let prepared = preparedNativeWatchTwo, prepared.retirementBegan,
           prepared.sourceID == sourceID, prepared.requestID == requestID {
            prepared.webRetired = true
        }
        // This callback is issued only after the exact old WK public teardown
        // suspension ACK. A removed pane must not leave the next owner waiting
        // on fields that cleanup has already replaced.
        for lease in webAudioRevocations where lease.sourceID == sourceID && lease.requestID == requestID {
            lease.acknowledged = true
        }
        if releasedSingleAudio { onSingleWebAudioRetired?() }
        guard isPlaybackSessionActive,
              loadRequestID == requestID,
              activeSource?.id == sourceID,
              nativeHandoffSession?.id == sourceID,
              !isUsingWebEmbed,
              nativeHandoffAwaitingWebRetirement,
              player != nil else { return }
        nativeHandoffAudioMuteHeld = true
        nativeHandoffAwaitingWebRetirement = false
        nativeTransferSuspensionID = nil
        nativeTransferAcknowledgedID = nil
        recordCausalDiagnostic(phase: .webRetired, purpose: .nativeHandoff, result: .retired,
                               operationID: handoffDiagnosticOperationID ?? UUID())
        handoffDiagnosticPhase = .none
        handoffDiagnosticOperationID = nil
        applyViewingAudioState()
        queueNativeHandoffAudioClaim()
    }

    /// The candidate must separately acknowledge system-audio disconnection
    /// before Play. It needs no shared-session configuration or activation;
    /// even changing category/mode can disturb the proven, active Web owner.
    func prepareMutedNativeHandoffAudio(sourceID: UUID, requestID: UUID) async -> MediaAudioSessionPreparation {
        guard !Task.isCancelled, isPlaybackSessionActive, !isPlaybackSessionRetired, activeSource?.id == sourceID,
              loadRequestID == requestID, isUsingWebEmbed, userWantsPlayback else { return .cancelled }
        return .completed([])
    }

    func prepareNativeCandidateAudioIsolation(player candidate: AVPlayer, sourceID: UUID,
        requestID: UUID) async -> NativePlayerAudioIsolation? {
        let intent = audioIntentID
        guard nativeAudioIsolationBackend.isSupported, let item = candidate.currentItem,
              isPlaybackSessionActive, !isPlaybackSessionRetired, isUsingWebEmbed, userWantsPlayback,
              activeSource?.id == sourceID, loadRequestID == requestID else { return nil }
        let isolation = makeNativeAudioIsolation(player: candidate, item: item, sourceID: sourceID, requestID: requestID)
        let disconnected = isolation.request(disconnected: true)
        guard await disconnected.wait(), !Task.isCancelled, isPlaybackSessionActive, !isPlaybackSessionRetired,
              userWantsPlayback, audioIntentID == intent, activeSource?.id == sourceID, loadRequestID == requestID,
              candidate.currentItem === item, !isAppBackgrounded, !isWebPictureInPictureActive,
              isUsingWebEmbed else {
            isolation.request(disconnected: true)
            return nil
        }
        return isolation
    }

    private func makeNativeAudioIsolation(player: AVPlayer, item: AVPlayerItem, sourceID: UUID,
        requestID: UUID) -> NativePlayerAudioIsolation {
        let raw = nativeAudioIsolationBackend
        let backend = NativePlayerAudioIsolationBackend(isSupported: true, setDisconnected: { [weak self] player, disconnected in
            let context: CausalDiagnosticContext?
            if let self, self.activeSource?.id == sourceID, self.loadRequestID == requestID {
                context = self.captureCausalDiagnosticContext()
            } else { context = nil }
            let operation = UUID()
            let purpose: FottyPlaybackDiagnosticPurpose = disconnected ? .nativeDisconnect : .nativeReconnect
            if let context {
                self?.recordCausalDiagnostic(phase: .audioIsolationRequested, purpose: purpose,
                    result: .began, operationID: operation, context: context)
            }
            let completed = await raw.setDisconnected(player, disconnected)
            if let context {
                self?.recordCausalDiagnostic(phase: .audioIsolationFinished, purpose: purpose,
                    result: completed ? .completed : .completedWithErrors, operationID: operation, context: context)
            }
            return completed
        })
        return NativePlayerAudioIsolation(player: player, item: item, backend: backend)
    }

    private func waitForNativeAudioRetirementBeforeWeb(requestID: UUID) async -> Bool {
        for barrier in Array(nativeAudioRetirements.values) {
            let retired = await barrier.wait()
            guard !Task.isCancelled, isPlaybackSessionActive, !isPlaybackSessionRetired,
                  loadRequestID == requestID else { return false }
            guard retired else {
                errorTitle = "Playback Interrupted"
                error = "Playback could not safely change audio. Retry this source."
                transition(to: .failed, phase: "Audio Transition Interrupted")
                return false
            }
            if nativeAudioRetirements[barrier.identity]?.revision == barrier.revision {
                nativeAudioRetirements.removeValue(forKey: barrier.identity)
            }
        }
        awaitsNativeAudioRetirement = false
        return true
    }

    func adoptNativeAudioIsolation(_ isolation: NativePlayerAudioIsolation) {
        guard hasAdoptedNativeHandoff, player === isolation.player,
              player?.currentItem === isolation.item else { return }
        nativeAudioIsolation = isolation
        applyViewingAudioState()
    }

    private func prepareNativeHandoffURL(
        for candidate: NativeWebPlaybackCandidate
    ) async throws -> (url: URL, proxy: LocalStreamProxy?) {
        let prepared = try await NativePlaybackPreparation.prepareDelivery(for: candidate)
        return (prepared.url, prepared.proxy)
    }

    func retryCurrentSourceExplicitly() {
        disarmSingleDiscoveryContinuation()
        renewNativeAudioRetirementsForExplicitRetry()
        if usesSingleStreamRanking, viewingPlaybackContext == .single,
           let source = activeSource, requiredDescriptorRefreshSourceIDs.contains(source.id) {
            // The gesture owns another metadata negotiation. It does not
            // replenish the automatic transport retry or permit the old URL.
            userWantsPlayback = true
            descriptorRefreshAttempts.remove(source.id)
            pendingDescriptorRefreshSourceID = source.id
        }
        loadCurrentSource(ignoringCircuitBreaker: true)
    }

    func selectSourceManually(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        guard admits(sessions[index]) else {
            showPlaybackBanner("Choose a source using the same player, or watch this match on its own.")
            return
        }
        if usesSingleStreamRanking, viewingPlaybackContext == .single, !event.isBroadcastChannel {
            let selected = sessions[index]
            guard let current = LivePlaybackSourcePolicy.currentMatchForSwitch(event, in: MatchListViewModel.shared.playbackAdmissionCatalog),
                  let admission = LivePlaybackSourcePolicy.admissionForMatchAlternative(selected, request: .init(event: current),
                    enabledProviders: currentMatchProviders()) else {
                showPlaybackBanner("This broadcast is no longer available for this match.")
                return
            }
            guard admission == .requiresFreshDescriptor || LivePlaybackSourcePolicy.hasCurrentRegistryAssignment(for: selected, request: .init(event: current)) else {
                showPlaybackBanner("This broadcast is no longer available for this match.")
                return
            }
            if admission == .requiresFreshDescriptor {
                requiredDescriptorRefreshSourceIDs.insert(selected.id)
            }
        }
        renewNativeAudioRetirementsForExplicitRetry()
        userWantsPlayback = true
        resetFailoverTracking()
        currentSourceIndex = index
        loadCurrentSource(ignoringCircuitBreaker: true)
    }

    func reportWrongMatch(for sourceID: UUID, expectedAttempt: UUID) {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single, !event.isBroadcastChannel,
              isPlaybackSessionActive, !isPlaybackSessionRetired, let current = activeSource,
              current.id == sourceID, loadRequestID == expectedAttempt else { return }
        recordMatchOutcome(.wrongProgramme, for: current)
        FottyQualityStore.shared.record(category: .playback, name: "programme_observation", outcome: .failure,
            details: playbackQualityDetails(singlePlaybackEvidence(programme: .viewerReportedWrong)))
        handleSourceStartupFailure(current, reason: "Provider reports this broadcast is unavailable", expectedRequestID: loadRequestID)
    }

    // MARK: Backup freshness (policy and scheduler in BackupFreshness.swift)

    func startBackupRefreshIfNeeded() {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single,
              !event.isBroadcastChannel, !isPlaybackSessionRetired else { return }
        backupRefreshScheduler.start(every: backupRefreshInterval, timing: timing) { [weak self] in
            guard let self else { return false }
            await self.refreshBackupsOnce()
            return true
        }
    }

    /// One exact lookup for the playing match. Its results replace older
    /// backups from the same provider family; the playing delivery, its index
    /// and every other family stay untouched. Paused, failing, recovering or
    /// background-suspended sessions spend no request.
    func refreshBackupsOnce() async {
        guard isPlaybackSessionActive, !isPlaybackSessionRetired, viewingPlaybackContext == .single,
              usesSingleStreamRanking, userWantsPlayback, isPlaying, error == nil,
              pendingSingleDiscoveryFailure == nil, exhaustedMatchLookup == nil,
              let current = LivePlaybackSourcePolicy.currentMatchForSwitch(event,
                  in: MatchListViewModel.shared.playbackAdmissionCatalog),
              let active = activeSession else { return }
        let attempt = loadRequestID
        let collector = BackupChoiceCollector()
        await freshMatchLookup(StreamPlaybackRequest(event: current, watchID: playbackCorrelation.sessionID)) { choices in
            await collector.add(choices)
        }
        guard !Task.isCancelled, isPlaybackSessionActive, !isPlaybackSessionRetired,
              loadRequestID == attempt, activeSession?.id == active.id else { return }
        backupRefreshCount += 1
        if let rebuilt = BackupFreshnessPolicy.replacingBackups(in: providedSessions, with: collector.choices,
                active: active, matchID: event.id, isPlayable: StreamPluginProviderMatching.isActivePlayerSession) {
            providedSessions = rebuilt
        }
        // A successful fresh lookup renews the single exhausted-delivery budget.
        usedExhaustedMatchLookup = false
    }

    /// Failover renews a chosen backup's descriptor before playing it, one at a
    /// time. Renew the next two concurrently while the first one starts. This
    /// is the same metadata call and identity check as the serial path; no
    /// media, relay or validator request is made here.
    func prefetchDescriptorRenewals(after chosen: StreamSource, limit: Int = 2) {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single, !event.isBroadcastChannel,
              !isPlaybackSessionRetired else { return }
        // At most `limit` renewals are in flight at once across failovers.
        let candidates = BackupFreshnessPolicy.renewalCandidates(in: providedSessions, chosen: chosen.id,
            failed: failedSourceIDs, alreadyRenewed: descriptorRefreshAttempts, inFlight: prefetchingRenewals,
            capacity: limit - prefetchingRenewals.count, supportsRenewal: LiveStreamResolver.supportsDescriptorRenewal)
        for session in candidates {
            prefetchingRenewals.insert(session.id)
            Task { [weak self] in
                guard let self else { return }
                defer { self.prefetchingRenewals.remove(session.id) }
                let original = StreamPlaybackRequest(event: self.event)
                let request = session.eventBinding?.usesRegistryAssociation == true
                    ? self.currentDescriptorRecoveryRequest(original) : original
                guard let request else { return }
                let fresh = await self.refreshSourceDescriptor(session, request)
                guard !self.isPlaybackSessionRetired, self.activeSession?.id != session.id,
                      let index = self.providedSessions.firstIndex(where: { $0.id == session.id }) else { return }
                // Success or failure, this source has spent its one renewal.
                self.descriptorRefreshAttempts.insert(session.id)
                guard let fresh, fresh.id == session.id, let binding = fresh.eventBinding,
                      binding.matches(request: request, providerCode: binding.providerCode) else { return }
                self.providedSessions[index] = fresh
                self.requiredDescriptorRefreshSourceIDs.remove(session.id)
            }
        }
    }

    func startPlaybackWatchdog(for source: StreamSource) {
        stopPlaybackWatchdog(); isPlaybackWatchdogArmed = true
        let requestID = loadRequestID
        let observationPlayer = player, observationItem = player?.currentItem
        let observationIntent = nativeWatchTwoIntentID
        var observationSecond = observationPlayer?.currentTime().seconds
        playbackWatchdogTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: PlaybackProgressPolicy.watchdogInterval)
                guard !Task.isCancelled,
                      loadRequestID == requestID,
                      activeSource?.id == source.id,
                      !isUsingWebEmbed,
                      !isLoading,
                      isPlaying,
                      Date().timeIntervalSince(lastPlaybackStateChangeAt) > (usesSingleStreamRanking && viewingPlaybackContext == .single ? 2.0 : 5.0),
                      let p = player else { continue }
                if let observationPlayer, let observationItem, let previous = observationSecond {
                    let current = observationPlayer.currentTime().seconds
                    observeSingleNativeResumeProgress(player: observationPlayer, item: observationItem,
                        sourceID: source.id, requestID: requestID, intentID: observationIntent,
                        startSeconds: previous, currentSeconds: current)
                    observationSecond = current.isFinite && current >= 0 ? current : nil
                } else if let observationPlayer {
                    let current = observationPlayer.currentTime().seconds
                    observationSecond = current.isFinite && current >= 0 ? current : nil
                }
                let single = usesSingleStreamRanking && viewingPlaybackContext == .single
                if p.timeControlStatus == .waitingToPlayAtSpecifiedRate || (single && p.timeControlStatus == .playing) {
                    let now = p.currentTime().seconds
                    if single && p.timeControlStatus == .playing { observeSingleNativeWatchdogProgress(now) }
                    else { stagnation.observeWaiting(now) }
                    if stagnation.isFrozen(single: single) {
                        validateRecoverableStall(
                            for: source,
                            reason: "Frozen.",
                            expectedItem: p.currentItem,
                            requestID: requestID
                        )
                        return
                    }
                } else { stagnation.reset(at: p.currentTime().seconds) }
            }
        }
    }

    // Advancing single-player video is not one stagnant sample. Besides stall
    // detection, the controls timer depends on zero meaning healthy progress.
    func observeSingleNativeWatchdogProgress(_ seconds: Double) {
        if stagnation.observePlaying(seconds), showControls { scheduleAutoHide() }
    }

    func validateRecoverableStall(
        for source: StreamSource,
        reason: String,
        expectedItem: AVPlayerItem? = nil,
        requestID: UUID? = nil
    ) {
        guard isPlaybackSessionActive, userWantsPlayback else { return }
        let expectedRequestID = requestID ?? loadRequestID
        if viewingPlaybackContext == .single, singleResumeOwner?.attempt == expectedRequestID,
           foregroundResumeValidationTask?.isCancelled == false { return }
        if let identity = intervalIdentity, identity.attemptID == expectedRequestID, identity.sourceID == source.id {
            playbackIntervals.beginStall(identity, now: timing.monotonicNow())
        }
        let itemID = (expectedItem ?? player?.currentItem).map(ObjectIdentifier.init)
        if viewingPlaybackContext == .single, let owner = stallValidationOwner,
           owner.attempt == expectedRequestID, owner.item == itemID, stallValidationTask?.isCancelled == false {
            return // Repeated stall/error notifications cannot restart the same observation window.
        }
        stallValidationTask?.cancel()
        let token = UUID()
        stallValidationOwner = (expectedRequestID, itemID, token)
        let start = player?.currentTime().seconds ?? 0
        stallValidationTask = Task {
            defer { if stallValidationOwner?.token == token { stallValidationOwner = nil } }
            let single = usesSingleStreamRanking && viewingPlaybackContext == .single
            for _ in 0..<PlaybackProgressPolicy.stallSampleCount(single: single) {
                do {
                    if single { try await timing.wait(for: PlaybackProgressPolicy.stallSampleInterval) }
                    else { try await Task.sleep(for: PlaybackProgressPolicy.stallSampleInterval) }
                } catch { return }
                guard !Task.isCancelled,
                      isPlaybackSessionActive, userWantsPlayback, !isAppBackgrounded,
                      loadRequestID == expectedRequestID,
                      activeSource?.id == source.id else { return }
                if let expectedItem, player?.currentItem !== expectedItem { return }
                if let p = player, PlaybackProgressPolicy.hasDecodedProgress(from: start, to: p.currentTime().seconds) {
                    recoverFromSoftStall(for: source, requestID: expectedRequestID, decodedProgress: true)
                    return
                }
            }
            guard !Task.isCancelled, isPlaybackSessionActive, userWantsPlayback, !isAppBackgrounded,
                  loadRequestID == expectedRequestID,
                  activeSource?.id == source.id else { return }
            if let expectedItem, player?.currentItem !== expectedItem { return }
            if let player,
               (!single && player.timeControlStatus == .playing)
                || PlaybackProgressPolicy.hasDecodedProgress(from: start, to: player.currentTime().seconds) {
                recoverFromSoftStall(for: source, requestID: expectedRequestID,
                                     decodedProgress: PlaybackProgressPolicy.hasDecodedProgress(from: start, to: player.currentTime().seconds))
                return
            }
            handleSourceStartupFailure(
                source,
                reason: reason,
                countsAsStall: true,
                expectedRequestID: expectedRequestID,
                diagnosticDetails: player?.currentItem.map {
                    nativeDiagnosticDetails(diagnosticService.analyze($0, trigger: .stallTimeout))
                } ?? [:]
            )
        }
    }

    private func recoverFromSoftStall(for source: StreamSource, requestID: UUID, decodedProgress: Bool) {
        guard isPlaybackSessionActive, userWantsPlayback, !isAppBackgrounded,
              activeSource?.id == source.id, loadRequestID == requestID else { return }
        if let identity = intervalIdentity {
            playbackIntervals.finishStall(identity, now: timing.monotonicNow(),
                completion: decodedProgress ? .decodedProgress : .transportPlaying)?.record()
        }
        error = nil
        transition(to: .playing(.native), phase: "Playing")
        withModelOwnedNativeRateCommand { player?.play() }
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
    func observeSingleContinuity(_ source: StreamSource) {
        singleContinuityTask?.cancel()
        guard viewingPlaybackContext == .single, let player, let item = player.currentItem,
              !isUsingWebEmbed, isVideoReadyForDisplay, !isAppBackgrounded,
              userWantsPlayback, error == nil else { return }
        let attempt = loadRequestID, start = player.currentTime().seconds
        let began = timing.monotonicNow(), initialStalls = stallCount
        let firstClockSample = SinglePlaybackMediaClock.Sample(uptime: began, wall: Date(),
            media: start, programme: item.currentDate())
        singleContinuityTask = Task { @MainActor [weak self, weak player, weak item] in
            guard let initialItem = item else { return }
            let firstAccess = await Self.singleNativeAccessSample(initialItem)
            var lastAccess = firstAccess
            var mediaClock = SinglePlaybackMediaClock(first: firstClockSample)
            var previousTime = start, previousUptime = began
            for _ in 0..<6 {
                do {
                    guard let self else { return }
                    try await self.timing.wait(for: .seconds(15))
                } catch { return }
                guard let self, let player, let item, !Task.isCancelled,
                      self.viewingPlaybackContext == .single, self.isPlaybackSessionActive,
                      self.loadRequestID == attempt, self.activeSource?.id == source.id,
                      self.player === player, player.currentItem === item,
                      self.isVideoReadyForDisplay, !self.isAppBackgrounded, self.userWantsPlayback,
                      self.error == nil,
                      player.timeControlStatus == .playing, abs(player.rate - 1) < 0.05,
                      self.stallCount == initialStalls else { return }
                let currentAccess = await Self.singleNativeAccessSample(item)
                guard SinglePlaybackAccessEvent.uninterrupted(previous: lastAccess?.events,
                                                              current: currentAccess?.events) else { return }
                lastAccess = currentAccess
                guard !Task.isCancelled, self.loadRequestID == attempt,
                      self.player === player, player.currentItem === item,
                      self.activeSource?.id == source.id, self.isPlaybackSessionActive,
                      self.viewingPlaybackContext == .single, self.stallCount == initialStalls,
                      self.isVideoReadyForDisplay, !self.isAppBackgrounded, self.userWantsPlayback,
                      self.error == nil else { return }
                let uptime = self.timing.monotonicNow(), mediaTime = player.currentTime().seconds
                let elapsed = uptime - previousUptime, advance = mediaTime - previousTime
                guard elapsed >= 12, elapsed <= 22, advance.isFinite,
                      advance >= elapsed * 0.9, advance <= elapsed * 1.15 else { return }
                mediaClock.observe(.init(uptime: uptime, wall: Date(), media: mediaTime,
                                         programme: item.currentDate()))
                previousTime = mediaTime; previousUptime = uptime
            }
            guard let self, !Task.isCancelled, self.loadRequestID == attempt,
                  self.activeSource?.id == source.id, self.isVideoReadyForDisplay,
                  !self.isAppBackgrounded, self.userWantsPlayback, self.error == nil else { return }
            let elapsed = previousUptime - began, advance = previousTime - start
            let stalls = self.stallCount - initialStalls
            guard SinglePlaybackContinuityStore.qualifies(elapsed: elapsed, mediaAdvance: advance, stalls: stalls) else { return }
            self.recordMatchOutcome(.sustained, for: source)
            SinglePlaybackContinuityStore.record(source, elapsed: elapsed, mediaAdvance: advance, stalls: stalls)
            var details = self.singlePlaybackEvidence(advertisedAgeMilliseconds: mediaClock.advertisedAgeMilliseconds)
            if let lastAccess {
                details.merge(lastAccess.metrics.qualityDetails) { _, measured in measured }
                details["native_access_event_count"] = String(lastAccess.events.count)
            }
            for (key, size) in [("native_presentation_width", initialItem.presentationSize.width),
                                ("native_presentation_height", initialItem.presentationSize.height)]
                where size.isFinite && (1...16_384).contains(size) {
                details[key] = String(Int(size.rounded()))
            }
            details["native_continuity_elapsed_ms"] = String(Int(elapsed * 1_000))
            details["native_continuity_media_advance_ms"] = String(Int(advance * 1_000))
            details["native_continuity_stalls"] = String(stalls)
            FottyQualityStore.shared.record(category: .playback, name: "native_continuity_90s", outcome: .success,
                durationMilliseconds: Int(elapsed * 1_000), details: self.playbackQualityDetails(details))
        }
    }

    private static func singleNativeAccessSample(_ item: AVPlayerItem) async -> (events: [SinglePlaybackAccessEvent], metrics: NativePlaybackAccessMetrics)? {
        if #available(iOS 27.0, macCatalyst 27.0, *) {
            return await withCheckedContinuation { continuation in
                item.fetchAccessLog { log in
                    guard let events = log?.events, events.count <= 128, let last = events.last else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let counters = events.map { SinglePlaybackAccessEvent(began: $0.playbackStartDate, stalls: $0.numberOfStalls) }
                    continuation.resume(returning: (counters, NativePlaybackAccessMetrics(
                        observedBitrate: last.observedBitrate, indicatedBitrate: last.indicatedBitrate,
                        stallCount: last.numberOfStalls, droppedFrames: last.numberOfDroppedVideoFrames,
                        bytes: last.numberOfBytesTransferred, transferDuration: last.transferDuration)))
                }
            }
        }
        // Older supported systems still use the observed player stall counter
        // and advancing-time checks; never synchronously collect logs on the UI.
        return nil
    }

    #if FOTTY_PRIVATE_OUTAGE_DRILL
    private(set) var drillRecoverySteps: [String] = []
    #endif
    private func traceRecovery(_ step: @autoclosure () -> String) {
        #if FOTTY_PRIVATE_OUTAGE_DRILL
        if AppRuntime.privateOutageFixture == event.id {
            drillRecoverySteps = Array((drillRecoverySteps + [step()]).suffix(12))
        }
        #endif
    }

    func nextPlayableSource(after source: StreamSource, allowing eligibleIDs: Set<UUID>? = nil) -> StreamSource? {
        if usesSingleStreamRanking, viewingPlaybackContext == .single {
            if !event.isBroadcastChannel {
                guard let current = LivePlaybackSourcePolicy.currentMatchForSwitch(event, in: MatchListViewModel.shared.playbackAdmissionCatalog) else {
                    traceRecovery("current fixture unavailable")
                    return nil
                }
                let request = StreamPlaybackRequest(event: current)
                let attempted = sessions.filter { $0.id == source.id || failedSourceIDs.contains($0.id) }
                let exhausted = Set(attempted.map { StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders) })
                var renewals = Set<UUID>()
                let remaining = sessions.filter { session in
                    guard !failedSourceIDs.contains(session.id), eligibleIDs?.contains(session.id) ?? true,
                          !exhausted.contains(StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)),
                          let admission = LivePlaybackSourcePolicy.admissionForMatchAlternative(session, request: request,
                            enabledProviders: currentMatchProviders()) else { return false }
                    if admission == .requiresFreshDescriptor || !LivePlaybackSourcePolicy.hasCurrentRegistryAssignment(for: session, request: request) {
                        guard LiveStreamResolver.supportsDescriptorRenewal(session), !descriptorRefreshAttempts.contains(session.id) else { return false }
                        renewals.insert(session.id)
                    }
                    return true
                }
                let ranked = LiveSourceHealthStore.rankedSingleStreamSessions(remaining, contextKey: LiveSourceHealthStore.contextKey(for: current))
                let differentOrigins = SourceDeliveryDiversity.prioritisingDifferentOrigin(ranked, after: source)
                let order = LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: differentOrigins.map(\.legacySource),
                    attempted: attempted.map(\.legacySource), after: source, family: LivePlaybackSourcePolicy.matchPublisher,
                    hasMeasuredSuccess: { LiveSourceHealthStore.positiveRecoveryHistory(for: $0, fixtureID: current.id) })
                let healthy = order.filter { LiveSourceHealthStore.matchEvidence(for: $0, fixtureID: current.id).rawValue < LiveSourceHealthStore.MatchEvidence.recentlyFailed.rawValue }
                let baselineRank = LiveSourceHealthStore.rankedSingleStreamSessions(remaining, contextKey: LiveSourceHealthStore.contextKey(for: current),
                    applyMatchEvidence: false)
                let baseline = LivePlaybackSourcePolicy.singleStreamRecoveryOrder(
                    ranked: SourceDeliveryDiversity.prioritisingDifferentOrigin(baselineRank, after: source).map(\.legacySource),
                    attempted: attempted.map(\.legacySource), after: source)
                let healthyIDs = Set(healthy.map(\.id))
                let trial = healthy.filter { !renewals.contains($0.id) } + healthy.filter { renewals.contains($0.id) }
                    + order.filter { !healthyIDs.contains($0.id) }
                let chosen = selectedMatchSource(baseline: baseline, trial: trial, after: source)
                traceRecovery("from=\(source.provider) eligible=\(remaining.count)/\(sessions.count) failed=\(failedSourceIDs.count) next=\(chosen?.provider ?? "none")")
                if let chosen, renewals.contains(chosen.id) { requiredDescriptorRefreshSourceIDs.insert(chosen.id) }
                return chosen
            }
            let remaining = sessions.filter {
                admits($0) && $0.id != source.id && !failedSourceIDs.contains($0.id)
                    && (eligibleIDs?.contains($0.id) ?? true)
            }
            let preferred = LiveSourceHealthStore.rankedSingleStreamSessions(remaining,
                contextKey: LiveSourceHealthStore.contextKey(for: event))
            let ranked = SourceDeliveryDiversity.prioritisingDifferentOrigin(preferred, after: source).map(\.legacySource)
            let attempted = sessions.filter { $0.id == source.id || failedSourceIDs.contains($0.id) }.map(\.legacySource)
            return LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: ranked, attempted: attempted, after: source).first
        }
        return LivePlaybackSourcePolicy.nextAutomaticSource(
            in: sessions.filter(admits).map(\.legacySource),
            after: source,
            excluding: failedSourceIDs,
            contextKey: LiveSourceHealthStore.contextKey(for: event)
        )
    }

    private func selectedMatchSource(baseline: [StreamSource], trial: [StreamSource], after current: StreamSource?) -> StreamSource? {
        let comparison = LivePlaybackSourcePolicy.MatchOrderComparison(baseline: baseline, candidate: trial,
            inventory: sessions, current: current, fixtureID: event.id, trial: current == nil || AppRuntime.usesPrivateMatchSelection)
        var details = comparison.details
        details["watch_session_id"] = playbackCorrelation.sessionID.uuidString
        if current != nil { details["attempt_id"] = loadRequestID.uuidString }
        if lastMatchComparison != details {
            lastMatchComparison = details
            FottyQualityStore.shared.record(category: .playback, name: "match_selection_comparison", outcome: .info, details: details)
        }
        return comparison.selected
    }

    private func recordMatchOutcome(_ outcome: LiveSourceHealthStore.MatchOutcome, for source: StreamSource) {
        guard usesSingleStreamRanking, viewingPlaybackContext == .single, !event.isBroadcastChannel else { return }
        LiveSourceHealthStore.recordMatchOutcome(outcome, for: source, fixtureID: event.id,
            watchID: playbackCorrelation.sessionID, session: activeSession)
    }

    private func enterLandscapeIfNeeded() { if !didApplyLandscape { didApplyLandscape = true; PlayerOrientationController.enterLandscape() } }
    func isWebEmbedSource(_ source: StreamSource) -> Bool {
        if forceWebEmbedSourceIDs.contains(source.id) { return true }
        if let session = activeSession, session.id == source.id {
            return LivePlaybackSourcePolicy.isWebEmbed(session)
        }
        return LivePlaybackSourcePolicy.isWebEmbed(source)
    }
    func isDiscoveryOnlySource(_ source: StreamSource) -> Bool {
        LivePlaybackSourcePolicy.isDiscoveryOnly(source)
    }

    // Owner diagnostics stay local and bounded. Never copy URLs, headers or
    // arbitrary provider metadata into the quality record.
    private func singlePlaybackEvidence(programme: SinglePlaybackProgrammeObservation = .unobserved,
                                        advertisedAgeMilliseconds: Int? = nil) -> [String: String] {
        var details = SinglePlaybackMediaClock.qualityDetails(web: isUsingWebEmbed,
            advertisedAgeMilliseconds: advertisedAgeMilliseconds)
        let basis: SinglePlaybackAssignmentBasis
        if event.isBroadcastChannel { basis = .stationTune }
        else if let binding = activeSession?.eventBinding {
            basis = binding.usesCSProviderHandoff ? .publisherHandoff : binding.usesRegistryAssociation ? .registryBinding : .providerBinding
        } else { basis = .unknown }
        details["assignment_basis"] = basis.rawValue
        details["programme_observation"] = programme.rawValue
        // An item, host, binding or two visible options cannot establish an
        // independent upstream. No separate lineage authority is attached here.
        details["upstream_independence_evidence"] = "unverified"
        return details
    }

    func playbackQualityDetails(_ additional: [String: String] = [:]) -> [String: String] {
        FottyPlaybackQualityDetails.make(
            source: activeSource,
            mode: isUsingWebEmbed ? "web_embed" : "native",
            route: diagnosticRoute.rawValue,
            attemptID: loadRequestID,
            sourceKey: activeSession?.diagnosticMetadata["source_key"],
            correlation: playbackCorrelation,
            deviceFamily: FottyPlaybackQualityDetails.deviceFamily,
            additional: additional.merging(["source_index": String(currentSourceIndex + 1),
                                            "source_count": String(sessions.count),
                                            "last_observed_stage": lastObservedPlaybackStage.rawValue]) { _, value in value }
        )
    }

    func recordPlaybackStage(_ stage: FottyPlaybackStage, errorCode: Int? = nil,
                             sourceID: UUID, requestID: UUID) {
        guard isPlaybackSessionActive, loadRequestID == requestID,
              activeSource?.id == sourceID else { return }
        ensurePlaybackIntervalAttempt()
        if let identity = intervalIdentity {
            if stage == .buffering { playbackIntervals.beginStall(identity, now: timing.monotonicNow()) }
            if stage == .decoded { playbackIntervals.decodedProgress(identity, now: timing.monotonicNow())?.record() }
        }
        lastObservedPlaybackStage = stage
        if stage == .decoded, usesSingleStreamRanking, viewingPlaybackContext == .single {
            refreshSinglePlaybackQuality()
            disarmSingleDiscoveryContinuation()
        }
        var details = ["stage": stage.rawValue]
        if let errorCode { details["platform_error_code"] = String(errorCode) }
        FottyQualityStore.shared.record(category: .playback, name: "playback_stage",
                                       outcome: .info, details: playbackQualityDetails(details))
    }

    private var intervalIdentity: FottyPlaybackIntervals.Identity? {
        activeSource.map { .init(sourceID: $0.id, attemptID: loadRequestID) }
    }

    private func ensurePlaybackIntervalAttempt() {
        guard let identity = intervalIdentity else { return }
        playbackIntervals.beginAttempt(identity, context: playbackQualityDetails(), now: timing.monotonicNow())?.record()
    }

    private struct CausalDiagnosticContext {
        let identity: FottyPlaybackDiagnosticBudget.Identity
        let details: [String: String]
    }

    /// Defensive diagnostic identity pin, not a playback/admission decision.
    /// An abandoned continuation keeps its pre-await snapshot and cannot write
    /// a replacement attempt's phase or borrow its current context.
    private func advanceHandoffDiagnosticPhase(_ phase: FottyPlaybackDiagnosticHandoffPhase,
        sourceID: UUID, requestID: UUID, operationID: UUID) -> CausalDiagnosticContext? {
        guard !Task.isCancelled, isPlaybackSessionActive, !isPlaybackSessionRetired,
              loadRequestID == requestID, activeSource?.id == sourceID,
              handoffDiagnosticOperationID == operationID else { return nil }
        handoffDiagnosticPhase = phase
        return captureCausalDiagnosticContext()
    }

    private func captureCausalDiagnosticContext() -> CausalDiagnosticContext? {
        guard isPlaybackSessionActive, !isPlaybackSessionRetired, let source = activeSource else { return nil }
        var details = playbackQualityDetails([
            "audio_enabled": String(isViewingAudioEnabled),
            "playback_intent": String(userWantsPlayback),
            "handoff_phase": handoffDiagnosticPhase.rawValue,
            "candidate_count": String(diagnosticCandidateCount)
        ])
        // Causal evidence needs only the existing random session/source/attempt
        // identifiers, not a URL-derived variant fingerprint.
        details.removeValue(forKey: "variant_key")
        details.removeValue(forKey: "source_key")
        return .init(identity: .init(sourceID: source.id, requestID: loadRequestID), details: details)
    }

    private func recordCausalDiagnostic(phase: FottyPlaybackDiagnosticPhase, purpose: FottyPlaybackDiagnosticPurpose,
                                        result: FottyPlaybackDiagnosticResult, operationID: UUID = UUID(),
                                        context captured: CausalDiagnosticContext? = nil) {
        guard let context = captured ?? captureCausalDiagnosticContext(),
              isPlaybackSessionActive, !isPlaybackSessionRetired,
              loadRequestID == context.identity.requestID, activeSource?.id == context.identity.sourceID,
              causalDiagnosticBudget.admit(identity: context.identity, phase: phase, purpose: purpose,
                                           result: result, operationID: operationID) else { return }
        FottyQualityStore.shared.record(category: .playback, name: "playback_causal_evidence", outcome: .info,
            details: context.details.merging([
                "diagnostic_phase": phase.rawValue, "diagnostic_purpose": purpose.rawValue,
                "diagnostic_result": result.rawValue, "diagnostic_operation_id": operationID.uuidString
            ]) { _, value in value })
    }

    private func handoffDiagnosticAbandonment(sourceID: UUID, requestID: UUID) -> FottyPlaybackDiagnosticResult {
        guard isPlaybackSessionActive, !isPlaybackSessionRetired,
              loadRequestID == requestID, activeSource?.id == sourceID else { return .ownershipChanged }
        if !userWantsPlayback { return .intentRevoked }
        if isAppBackgrounded { return .backgrounded }
        if isWebPictureInPictureActive { return .pictureInPicture }
        return .cancelled
    }

    private func measuredAudioPreparation(purpose: FottyPlaybackDiagnosticPurpose,
                                          configurationOnly: Bool = false) async -> MediaAudioSessionPreparation {
        ensurePlaybackIntervalAttempt()
        let identity = intervalIdentity
        let context = captureCausalDiagnosticContext()
        let operationID = UUID()
        recordCausalDiagnostic(phase: .audioPreparationRequested, purpose: purpose, result: .began,
                               operationID: operationID, context: context)
        let start = timing.monotonicNow()
        let result = configurationOnly ? await configureAudioSession() : await prepareAudioSession()
        let diagnosticResult: FottyPlaybackDiagnosticResult
        switch result {
        case .cancelled: diagnosticResult = .cancelled
        case .completed(let failures): diagnosticResult = failures.isEmpty ? .completed : .completedWithErrors
        }
        recordCausalDiagnostic(phase: .audioPreparationFinished, purpose: purpose, result: diagnosticResult,
                               operationID: operationID, context: context)
        if let identity {
            playbackIntervals.audioPreparation(identity, startedAt: start, now: timing.monotonicNow(), result: result)?.record()
        }
        return result
    }

    func recordWebAudioPreparation(durationMilliseconds: Int, result: MediaAudioSessionPreparation,
                                   sourceID: UUID, requestID: UUID) {
        guard isPlaybackSessionActive, activeSource?.id == sourceID, loadRequestID == requestID else { return }
        ensurePlaybackIntervalAttempt()
        if let identity = intervalIdentity {
            playbackIntervals.audioPreparation(identity, durationMilliseconds: durationMilliseconds, result: result)?.record()
        }
    }

    func updateNowPlayingInfo() {
        guard ownsRemoteCommands, !isPlaybackSessionRetired else { return }
        let title = event.title ?? "Live Match"
        let category = event.category?.uppercased() ?? "LIVE"
        let subtitle = "\(category) • \(activeSource?.provider ?? "Live Stream")"
        NowPlayingManager.shared.updateNowPlaying(ownerID: remoteCommandOwnerID, title: title,
                                                 subtitle: subtitle, isPlaying: isPlaying)
    }

    func cleanup() {
        guard !isPlaybackSessionRetired else { return }
        disarmSingleDiscoveryContinuation()
        isPlaybackSessionRetired = true
        singleContinuityTask?.cancel(); singleContinuityTask = nil
        descriptorNegotiationRequestID = nil
        pausedDescriptorNegotiationSourceID = nil
        nativeForegroundObservationLease = nil
        if let preparedNativeWatchTwo { discardNativeWatchTwoCandidate(preparedNativeWatchTwo) }
        preparedNativeWatchTwo = nil
        nativeWatchTwoDelivery = nil
        nativeWatchTwoAudioHeld = false
        webAudioRevocationID = nil
        cancelNativePlaybackTransfer()
        retireNativeFullscreenForTransportChange()
        cancelAudioPreparation()
        if isPlaybackSessionActive, playbackCorrelation.attemptID != nil {
            FottyQualityStore.shared.record(category: .playback, name: "session_closed",
                                           outcome: .info, details: playbackQualityDetails())
        }
        playbackCorrelation = FottyPlaybackCorrelation()
        isPlaybackSessionActive = false
        userWantsPlayback = false
        explicitNativeTransferID = nil
        nativeTransferSuspensionID = nil
        nativeTransferAcknowledgedID = nil
        cachedNativeCandidate = nil
        loadRequestID = UUID()
        pendingRetryAfterNetworkRestore = false
        shouldResumeAfterForeground = false
        shouldSuspendWebPlayback = false
        awaitsNativeAudioRetirement = false
        isWebPictureInPictureActive = false
        isPictureInPictureActive = false
        nativeHandoffAwaitingWebRetirement = false
        handoffDiagnosticPhase = .none
        handoffDiagnosticOperationID = nil
        cancelPendingWebRetry()
        loadTask?.cancel(); hideTask?.cancel(); stallValidationTask?.cancel(); playbackWatchdogTask?.cancel()
        failoverBannerTask?.cancel(); foregroundResumeValidationTask?.cancel(); nativeHandoffTask?.cancel(); webBackgroundSuspensionTask?.cancel()
        backupRefreshScheduler.stop(); prefetchingRenewals.removeAll()
        stopNetworkPathMonitoring(); removeItemFailureObservers()
        withModelOwnedNativeRateCommand { player?.pause() }
        player = nil; streamProxy?.stop(); streamProxy = nil; nativeHandoffSession = nil
        transition(to: .idle, phase: "Idle")
        NowPlayingManager.shared.clearNowPlaying(ownerID: remoteCommandOwnerID)
        ownsRemoteCommands = false
    }
}
