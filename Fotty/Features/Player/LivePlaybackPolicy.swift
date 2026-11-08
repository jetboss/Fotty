import Foundation
import SwiftUI
import AVFoundation

/// Disconnection, unlike mute, prevents this player from claiming system audio
/// when it starts. The public API is not available to Catalyst/macOS or iOS26.
@MainActor
struct NativePlayerAudioIsolationBackend {
    let isSupported: Bool
    let setDisconnected: @MainActor (AVPlayer, Bool) async -> Bool

    static var system: Self {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 27.0, *) {
            return .init(isSupported: true, setDisconnected: { player, disconnected in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    player.setDisconnectedFromSystemAudio(disconnected) { continuation.resume() }
                }
                return player.disconnectedFromSystemAudio == disconnected
            })
        }
        #endif
        return .init(isSupported: false, setDisconnected: { _, _ in false })
    }
}

/// Platform setters cannot be cancelled. Serialize them for this exact player,
/// let an old setter finish, then reconcile the newest desired state. Cancelling
/// a playback/focus task must never abandon a late reconnect in the platform.
@MainActor
final class NativePlayerAudioIsolation {
    struct Request: Equatable {
        let generation: UUID
        let disconnected: Bool
    }
    @MainActor struct Barrier {
        fileprivate let owner: NativePlayerAudioIsolation
        fileprivate let request: Request
        var identity: ObjectIdentifier { ObjectIdentifier(owner) }
        var revision: UUID { request.generation }
        var isSatisfied: Bool { owner.isSatisfied(request) }
        var isSatisfiedDisconnection: Bool { request.disconnected && isSatisfied }
        func wait() async -> Bool { await owner.wait(for: request) }
        func renewedDisconnection() -> Self { owner.request(disconnected: true) }
    }

    let player: AVPlayer
    let item: AVPlayerItem
    private let backend: NativePlayerAudioIsolationBackend
    private var desired: Request?
    private var verifiedDisconnected: Bool?
    private var worker: Task<Void, Never>?
    private var waiters: [(Request, CheckedContinuation<Bool, Never>)] = []
    var currentBarrier: Barrier? { desired.map { Barrier(owner: self, request: $0) } }

    init(player: AVPlayer, item: AVPlayerItem, backend: NativePlayerAudioIsolationBackend) {
        self.player = player; self.item = item; self.backend = backend
    }

    @discardableResult
    func request(disconnected: Bool) -> Barrier {
        if !disconnected, player.currentItem !== item {
            let rejected = Request(generation: UUID(), disconnected: false)
            request(disconnected: true)
            return Barrier(owner: self, request: rejected)
        }
        if let desired, desired.disconnected == disconnected,
           worker != nil || verifiedDisconnected == disconnected {
            return Barrier(owner: self, request: desired)
        }
        let next = Request(generation: UUID(), disconnected: disconnected)
        desired = next
        let abandoned = waiters; waiters = []
        abandoned.forEach { $0.1.resume(returning: false) }
        if worker == nil { worker = Task { await self.drain() } }
        return Barrier(owner: self, request: next)
    }

    func revokeIfCurrent(_ barrier: Barrier) {
        guard barrier.owner === self, desired == barrier.request else { return }
        request(disconnected: true)
    }

    private func isSatisfied(_ request: Request) -> Bool {
        desired == request && worker == nil && verifiedDisconnected == request.disconnected
            && (request.disconnected || player.currentItem === item)
    }

    private func wait(for request: Request) async -> Bool {
        guard !Task.isCancelled, desired == request else { return false }
        if worker == nil { return isSatisfied(request) }
        return await withCheckedContinuation { waiters.append((request, $0)) }
    }

    private func drain() async {
        while let current = desired {
            let completed = await backend.setDisconnected(player, current.disconnected)
            verifiedDisconnected = completed ? current.disconnected : nil
            // A changed item never inherits an old item's audible connection.
            if player.currentItem !== item, desired?.disconnected == false {
                request(disconnected: true)
            }
            guard desired == current else { continue }
            worker = nil
            let completedWaiters = waiters; waiters = []
            let accepted = completed && (current.disconnected || player.currentItem === item)
            completedWaiters.forEach { $0.1.resume(returning: accepted) }
            return
        }
        worker = nil
    }
}

/// Transport rate and an advancing audio clock do not establish rendered video.
/// The ordinary surface must have a frame ready as well as forward progress.
enum NativePlaybackVideoPolicy {
    static func hasDisplayedProgress(
        isReadyForDisplay: Bool, startSeconds: Double, currentSeconds: Double
    ) -> Bool {
        isReadyForDisplay && startSeconds.isFinite && currentSeconds.isFinite
            && currentSeconds > startSeconds + 0.1
    }
}

/// One immutable monotonic budget covers item readiness and the first displayed
/// video progress. AVPlayer's legitimate buffering waits do not renew it, and
/// readiness alone is not proof that playback has started. These are bounded
/// Fotty policies, not durations prescribed by AVFoundation.
struct NativePlaybackStartupDeadline: Sendable {
    static let timeoutSeconds: TimeInterval = 20

    enum Budget: Equatable, Sendable {
        case standard
        case reviewedLSSingleStream
        case csMatchRenewal

        var seconds: TimeInterval {
            switch self {
            case .standard: return NativePlaybackStartupDeadline.timeoutSeconds
            case .reviewedLSSingleStream: return 30
            case .csMatchRenewal: return 32
            }
        }
    }

    static func budget(for session: StreamSession, context: ViewingPlaybackContext,
                       isNativeHandoff: Bool, renewingMatch: Bool = false) -> Budget {
        if renewingMatch, context == .single, !isNativeHandoff,
           session.eventBinding?.providerCode == "communitysports" { return .csMatchRenewal }
        return context == .single && !isNativeHandoff && CNCSportsAddonClient.isReviewedNativeSession(session)
            ? .reviewedLSSingleStream : .standard
    }

    enum Decision: Equatable, Sendable {
        case waiting
        case started
        case timedOut
        case failed
        case abandoned
        case invalidTiming
    }

    private let startedAt: TimeInterval
    let budget: Budget

    init(startedAt: TimeInterval, budget: Budget = .standard) {
        self.startedAt = startedAt
        self.budget = budget
    }

    func elapsed(at now: TimeInterval) -> TimeInterval? {
        guard startedAt.isFinite, startedAt >= 0, now.isFinite, now >= startedAt else { return nil }
        let elapsed = now - startedAt
        return elapsed.isFinite ? elapsed : nil
    }

    func remaining(at now: TimeInterval) -> TimeInterval? {
        guard let elapsed = elapsed(at: now) else { return nil }
        return max(budget.seconds - elapsed, 0)
    }

    /// Sample current-item video/error evidence before calling this, including
    /// after the final sleep. A verified final sample must not be discarded just
    /// because that sleep crossed the boundary. Revoked owners and manual Pause
    /// are abandonment, never source failure or permission to restart playback.
    func decision(
        at now: TimeInterval,
        hasVerifiedVideoStart: Bool,
        hasFailedItem: Bool,
        isCancelled: Bool = false,
        ownsCurrentAttempt: Bool = true,
        userWantsPlayback: Bool = true
    ) -> Decision {
        guard !isCancelled, ownsCurrentAttempt, userWantsPlayback else { return .abandoned }
        guard !hasFailedItem else { return .failed }
        guard let elapsed = elapsed(at: now) else { return .invalidTiming }
        if hasVerifiedVideoStart { return .started }
        return elapsed >= budget.seconds ? .timedOut : .waiting
    }
}

/// A handoff candidate has no displayed layer yet. Two decoded output frames
/// with advancing presentation times prove video without retiring the web owner.
/// Store only scalar evidence; never retain video buffers or add ongoing polling.
struct NativePlaybackFrameProgress {
    private var previousFrameSeconds: Double?

    mutating func observe(seconds: Double, width: Int, height: Int) -> Bool {
        guard seconds.isFinite, width > 16, height > 16 else { return false }
        defer { previousFrameSeconds = seconds }
        guard let previousFrameSeconds else { return false }
        return seconds > previousFrameSeconds + 0.01
    }
}

/// Control Center and other transient overlays do not move a player into the
/// background. Both player layouts use this boundary without changing PiP policy.
enum MultiLiveScenePolicy {
    static func isForeground(_ phase: ScenePhase) -> Bool {
        switch phase {
        case .active, .inactive: return true
        case .background: return false
        @unknown default: return false
        }
    }

    static func shouldSuspendWebPlayback(_ phase: ScenePhase, isNetworkReachable: Bool) -> Bool {
        !isForeground(phase) || !isNetworkReachable
    }
}

enum LivePlaybackPolicy {
    /// Provider embeds can spend several seconds negotiating a manifest after
    /// the document and player chrome have loaded. The old 10-second cutoff
    /// abandoned sources which then worked after a manual retry.
    static let webStartupFailureSeconds: TimeInterval = 20

    /// A decoded web stream gets a generous recovery window before Fotty
    /// abandons it. Short network interruptions should preserve the source.
    static let webStallFailureSeconds: TimeInterval = 30
    static let webRecoveryGraceSeconds: TimeInterval = 8
    static let webControlAutoHideSeconds: TimeInterval = 4

    static func isExplicitProviderRejection(_ reason: String) -> Bool {
        let normalized = reason.lowercased()
        return normalized.contains("embedding disabled")
            || normalized.contains("broadcast is unavailable")
            || normalized.contains("channel is unavailable")
            || normalized.contains("stream is unavailable")
    }

    /// Child-frame players can emit opaque errors before the real broadcast
    /// has finished negotiating. We deliberately wait out the complete startup
    /// window; if no decoded progress arrives, that elapsed deadline—not the
    /// opaque child-frame wording—is the truthful terminal boundary.
    static func deferredStartupFailureReason(_ providerReason: String) -> String {
        guard !isExplicitProviderRejection(providerReason) else { return providerReason }
        return "Startup timeout: no decoded video within \(Int(webStartupFailureSeconds)) seconds"
    }
}

/// Opt-in evidence for the single-stream recovery path. A logged historical
/// request is not the cause of a current failure; callers must retain ownership
/// of the failed item/attempt before constructing this value.
struct LivePlaybackStructuredFailure: Equatable {
    enum Category: Equatable {
        case network
        case decode
        case unsupported
    }

    let httpStatus: Int?
    let category: Category?

    init(httpStatus: Int? = nil, category: Category? = nil) {
        self.httpStatus = httpStatus.flatMap { (400...599).contains($0) ? $0 : nil }
        self.category = category
    }

    var disallowsAutomaticRetry: Bool {
        if let httpStatus { return (400...499).contains(httpStatus) && httpStatus != 408 }
        return category == .unsupported
    }

    /// Consume only explicit response evidence or the actual NSError chain.
    /// Last native error-log entries and the latest relay request may describe
    /// a recovered retry, so neither can acquire current failure authority here.
    /// A relay receipt requires the caller to correlate it to the terminal
    /// failed request; merely sharing the same player/relay is insufficient.
    static func fromDiagnosticDetails(
        _ details: [String: String], currentRelayFailure: Bool = false
    ) -> Self {
        var statuses = Set<Int>()
        let preparationStage = details["preparation_stage"]
        let hasPreparationCause = preparationStage == "url_preparation" || preparationStage == "contract_validation"
        if hasPreparationCause, details["preparation_reason"] == "http_status",
           let status = responseStatus(details["preparation_http_status"]) {
            statuses.insert(status)
        }
        for prefix in ["native_error", "native_underlying", "preparation_error", "preparation_underlying"] {
            if prefix.hasPrefix("preparation"), !hasPreparationCause { continue }
            if details["\(prefix)_domain"] == "http", let status = responseStatus(details["\(prefix)_code"]) {
                statuses.insert(status)
            }
        }
        if currentRelayFailure, details["relay_failure_stage"] == "upstream_response",
           details["relay_failure_kind"] == "http_status",
           let status = responseStatus(details["relay_http_status"]) {
            statuses.insert(status)
        }
        // Conflicting causal receipts do not justify selecting either response
        // as the current failure, or inferring a codec/network cause instead.
        if statuses.count > 1 { return .init() }
        if let status = statuses.first { return .init(httpStatus: status) }
        if hasPreparationCause, details["preparation_reason"] == "unsupported_content_type" {
            return .init(category: .unsupported)
        }
        for prefix in ["native_error", "native_underlying", "preparation_error", "preparation_underlying"] {
            if prefix.hasPrefix("preparation"), !hasPreparationCause { continue }
            if let category = category(domain: details["\(prefix)_domain"], code: details["\(prefix)_code"]) {
                return .init(category: category)
            }
        }
        return .init()
    }

    private static func responseStatus(_ value: String?) -> Int? {
        guard let value, value.utf8.count == 3, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let status = Int(value), (400...599).contains(status) else { return nil }
        return status
    }

    private static func category(domain: String?, code: String?) -> Category? {
        guard let code, let number = Int(code), String(number) == code else { return nil }
        if domain == "url" {
            switch number {
            case URLError.timedOut.rawValue, URLError.cannotFindHost.rawValue,
                 URLError.cannotConnectToHost.rawValue, URLError.networkConnectionLost.rawValue,
                 URLError.dnsLookupFailed.rawValue, URLError.notConnectedToInternet.rawValue:
                return .network
            case URLError.cannotDecodeContentData.rawValue, URLError.cannotDecodeRawData.rawValue:
                return .decode
            case URLError.unsupportedURL.rawValue:
                return .unsupported
            default: return nil
            }
        }
        if domain == "avfoundation" {
            switch number {
            case AVError.Code.decodeFailed.rawValue: return .decode
            case AVError.Code.decoderNotFound.rawValue, AVError.Code.fileFormatNotRecognized.rawValue:
                return .unsupported
            default: return nil
            }
        }
        return nil
    }
}

enum LivePlaybackFailureKind: String, Equatable {
    case network
    case accessDenied
    case decodeFailure
    case providerUnavailable
    case startupTimeout
    case stalled
    case proxy
    case resumeFailure
    case unsupportedSource
    case sourceFailure
    case unknown

    static func classify(
        reason: String,
        countsAsStall: Bool,
        isNetworkReachable: Bool,
        structuredFailure: LivePlaybackStructuredFailure? = nil
    ) -> LivePlaybackFailureKind {
        let normalized = reason.lowercased()
        if !isNetworkReachable { return .network }
        if let status = structuredFailure?.httpStatus {
            switch status {
            case 401, 403: return .accessDenied
            case 400...499 where status != 408: return .providerUnavailable
            default: return .sourceFailure
            }
        }
        if let category = structuredFailure?.category {
            switch category {
            case .network: return .network
            case .decode: return .decodeFailure
            case .unsupported: return .unsupportedSource
            }
        }
        if normalized.contains("network") || normalized.contains("offline") {
            return .network
        }
        if LivePlaybackPolicy.isExplicitProviderRejection(reason) { return .providerUnavailable }
        if countsAsStall || normalized.contains("stalled") || normalized.contains("frozen") { return .stalled }
        if normalized.contains("never became ready")
            || normalized.contains("failed to start")
            || normalized.contains("timed out")
            || normalized.contains("timeout")
            || (structuredFailure == nil && normalized.contains("404")) {
            return .startupTimeout
        }
        if normalized.contains("proxy") { return .proxy }
        if normalized.contains("resume") || normalized.contains("returning to app") { return .resumeFailure }
        if normalized.contains("unsupported") || normalized.contains("native extraction failed") { return .unsupportedSource }
        if normalized.contains("failed to play")
            || normalized.contains("player item failed")
            || normalized.contains("source failed") {
            return .sourceFailure
        }
        return .unknown
    }

    var title: String {
        switch self {
        case .network: return "Connection Lost"
        case .accessDenied: return "Source Access Denied"
        case .decodeFailure: return "Video Couldn't Be Decoded"
        case .providerUnavailable: return "Broadcast Unavailable"
        case .startupTimeout: return "Stream Didn't Start"
        case .stalled: return "Stream Stalled"
        case .proxy: return "Couldn't Start Stream"
        case .resumeFailure: return "Resume Failed"
        case .unsupportedSource: return "Source Not Supported"
        case .sourceFailure: return "Stream Ended Unexpectedly"
        case .unknown: return "Playback Error"
        }
    }

    var terminalMessage: String {
        switch self {
        case .network:
            return "Connection lost. Fotty will keep this broadcast and resume when the network returns."
        case .accessDenied:
            return "The provider denied access to this broadcast. Choose another broadcast."
        case .decodeFailure:
            return "This video couldn't be decoded. Try another broadcast."
        case .providerUnavailable:
            return "The broadcast provider reported that this source is unavailable. Choose another broadcast or try again later."
        case .startupTimeout:
            return "This broadcast didn't start after retrying. Try it again or choose another broadcast."
        case .stalled:
            return "The video stopped and couldn't recover. Try it again or choose another broadcast."
        case .proxy:
            return "Fotty couldn't start this broadcast. Try again or choose another."
        case .resumeFailure:
            return "This broadcast could not resume after the app returned. Try the same source again."
        case .sourceFailure:
            return "This broadcast ended and couldn't recover. Try again or choose another."
        case .unknown:
            return "Playback couldn't recover. Try again or choose another broadcast."
        case .unsupportedSource:
            return "The provider returned media this player cannot use. Choose another broadcast."
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

struct WebPlaybackCommand: Equatable {
    let id: UUID
    let shouldPlay: Bool
}

enum WebPlaybackTransportState: String {
    case playing
    case paused
}

struct NativeWebPlaybackCandidate: Equatable {
    let url: URL
    let headers: [String: String]
    // Keep scope/expiry metadata until each concrete segment request is made.
    var cookies: [HTTPCookie] = []
}

enum LivePlaybackRecoveryPolicy {
    enum Action: Equatable {
        case waitForNetwork(LivePlaybackFailureKind)
        case returnNativeHandoffToWeb(LivePlaybackFailureKind)
        case tryWebFallback(LivePlaybackFailureKind)
        case retryNativeStartup(LivePlaybackFailureKind)
        case retryWebStall(LivePlaybackFailureKind)
        case retryWebStartup(LivePlaybackFailureKind)
        case exhaustSource(LivePlaybackFailureKind)

        var failureKind: LivePlaybackFailureKind {
            switch self {
            case .waitForNetwork(let kind),
                 .returnNativeHandoffToWeb(let kind),
                 .tryWebFallback(let kind),
                 .retryNativeStartup(let kind),
                 .retryWebStall(let kind),
                 .retryWebStartup(let kind),
                 .exhaustSource(let kind):
                return kind
            }
        }
    }

    struct Input {
        let reason: String
        let countsAsStall: Bool
        let isNetworkReachable: Bool
        let isNativeHandoff: Bool
        let isWebEmbed: Bool
        let isForcedWebEmbed: Bool
        let webStartupRetryCount: Int
        let webStallRetryCount: Int
        var isDirectMedia = false
        var nativeStartupRetryCount = 0
        // Nil retains the existing shared/multi-stream policy. The owned
        // single-stream caller opts in with current causal evidence only.
        var structuredFailure: LivePlaybackStructuredFailure? = nil
    }

    static func action(for input: Input) -> Action {
        let failureKind = LivePlaybackFailureKind.classify(
            reason: input.reason,
            countsAsStall: input.countsAsStall,
            isNetworkReachable: input.isNetworkReachable,
            structuredFailure: input.structuredFailure
        )

        if !input.isNetworkReachable { return .waitForNetwork(failureKind) }
        if input.isNativeHandoff { return .returnNativeHandoffToWeb(failureKind) }
        if input.structuredFailure?.disallowsAutomaticRetry == true { return .exhaustSource(failureKind) }
        if !input.isWebEmbed, !input.countsAsStall, !input.isForcedWebEmbed {
            // An HLS endpoint is not an HTML player. Retry its native transport
            // once; only captured web handoffs can return to an owned web page.
            if input.isDirectMedia {
                if input.nativeStartupRetryCount < 1,
                   !LivePlaybackPolicy.isExplicitProviderRejection(input.reason) {
                    return .retryNativeStartup(failureKind)
                }
                return .exhaustSource(failureKind)
            }
            return .tryWebFallback(failureKind)
        }
        if input.isWebEmbed, !LivePlaybackPolicy.isExplicitProviderRejection(input.reason) {
            if input.countsAsStall, input.webStallRetryCount < 1 {
                return .retryWebStall(failureKind)
            }
            if !input.countsAsStall, input.webStartupRetryCount < 1 {
                return .retryWebStartup(failureKind)
            }
        }
        return .exhaustSource(failureKind)
    }
}

enum LivePlaybackSourcePolicy {
    struct MatchOrderComparison {
        let selected: StreamSource?
        let details: [String: String]

        init(baseline: [StreamSource], candidate: [StreamSource], inventory: [StreamSession],
             current: StreamSource?, fixtureID: String, trial: Bool) {
            let slots = Dictionary(inventory.enumerated().map { ($0.element.id, $0.offset + 1) }, uniquingKeysWith: { first, _ in first })
            func topSlots(_ order: [StreamSource]) -> String {
                let values = order.prefix(3).compactMap { slots[$0.id] }.map(String.init)
                return values.isEmpty ? "none" : values.joined(separator: ".")
            }
            selected = (trial ? candidate : baseline).first
            let reason: String
            if let winner = candidate.first {
                if let old = baseline.first, LiveSourceHealthStore.matchEvidence(for: old, fixtureID: fixtureID).rawValue
                    >= LiveSourceHealthStore.MatchEvidence.recentlyFailed.rawValue, old.id != winner.id { reason = "prior_failure" }
                else if LiveSourceHealthStore.matchEvidence(for: winner, fixtureID: fixtureID).hasPlayed { reason = "played_this_fixture" }
                else if let current, LivePlaybackSourcePolicy.matchPublisher(for: current) != LivePlaybackSourcePolicy.matchPublisher(for: winner) { reason = "different_family" }
                else if let current, let old = SourceDeliveryDiversity.origin(for: current),
                        let new = SourceDeliveryDiversity.origin(for: winner), old != new { reason = "different_origin" }
                else if baseline.first?.id == winner.id { reason = "same_pick" }
                else { reason = "ranked_admitted" }
            } else { reason = "no_eligible_route" }
            let admitted = Set(candidate.map(\.id))
            let executable = inventory.filter { admitted.contains($0.id) }
            let exact = Set(executable.map { StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders) })
            details = ["selection_version": "1", "selection_stage": current == nil ? "initial" : "recovery",
                       "selection_applied": trial ? "trial" : "baseline", "baseline_slots": topSlots(baseline),
                       "candidate_slots": topSlots(candidate), "selection_reason": reason,
                       "candidate_families": String(Set(candidate.map(LivePlaybackSourcePolicy.matchPublisher)).count),
                       "duplicate_choices": String(executable.count - exact.count), "independence_evidence": "unverified"]
        }
    }
    /// A new match delivery must still refer to the currently admitted game.
    /// Losing an optional metadata refresh does not end an already playing item.
    @MainActor static func currentMatchForSwitch(_ event: EventReference, in catalog: [EventReference],
                                                at now: Date = Date()) -> EventReference? {
        guard !event.isBroadcastChannel,
              let latest = CurrentEventBroadcastPolicy.currentEvent(for: event, in: catalog, at: now),
              latest.kickoffDate == event.kickoffDate, ViewingSessionCoordinator.canReuse(event, for: latest),
              !latest.hasCatalogIdentityConflict, !MatchStartPolicy(event: latest, now: now).isStopped else { return nil }
        if latest.sportsFixture != nil || latest.cricketFixture != nil {
            return RegisteredDescriptorRecoveryPolicy.currentRequest(for: .init(event: event), in: catalog, at: now)?.preferredEvent
        }
        return latest
    }

    enum MatchAlternativeAdmission: Equatable { case ready, requiresFreshDescriptor }
    @MainActor static var enabledMatchProviders: Set<String>? {
        let index = FixtureStreamDiscoveryIndex.shared
        return index.hasLoadedProviderEnablement ? index.enabledProviderCodes : nil
    }
    @MainActor static func hasCurrentRegistryAssignment(for session: StreamSession, request: StreamPlaybackRequest) -> Bool {
        guard let binding = session.eventBinding, binding.usesRegistryAssociation else { return true }
        let matches = BroadcastRegistryClient.shared.lookup(for: request, enabledProviderCodes: [binding.providerCode])
        let now = Date()
        return binding.currentRegistryEntry(in: matches, request: request, at: now) != nil
    }

    @MainActor static func admissionForMatchAlternative(
        _ session: StreamSession, request: StreamPlaybackRequest, at now: Date = Date(),
        enabledProviders: Set<String>? = nil
    ) -> MatchAlternativeAdmission? {
        guard session.matchID == request.matchID, session.validationStatus == .validated,
              StreamPluginProviderMatching.isActivePlayerSession(session),
              enabledProviders.map({ $0.contains(where: { StreamPluginProviderMatching.matches(session.legacySource, code: $0) }) }) ?? true,
              LiveSourceHealthStore.matchEvidence(for: session, at: now) != .wrongProgramme else { return nil }
        guard let binding = session.eventBinding else {
            // Persisted or web sessions cannot invent a TV programme assignment.
            guard StreamPluginProviderMatching.opaqueProviderFamily(session.providerName) != ReviewedTVPlaylistClient.providerCode,
                  !session.hasExpiredMediaLease(at: now) else { return nil }
            return .ready
        }
        guard let provider = StreamEventBinding.providerCode(forSessionProviderName: session.providerName),
              binding.matchesIdentity(request: request, providerCode: provider) else { return nil }
        if session.hasExpiredMediaLease(at: now) || !binding.isCurrent(at: now) {
            // The resolver must rejoin the exact provider event/edition before starting any bytes.
            return LiveStreamResolver.supportsDescriptorRenewal(session) ? .requiresFreshDescriptor : nil
        }
        return binding.matches(request: request, providerCode: provider, at: now) ? .ready : nil
    }

    /// Multiple catalog aliases can expose the same dependency; their numbers
    /// are labels, not additional publisher families.
    static func matchPublisher(for source: StreamSource) -> String {
        if let provider = StreamEventBinding.providerCode(forSessionProviderName: source.provider) { return provider }
        if let alias = source.headers["X-Fotty-Nexus-Source"],
           let provider = StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: alias) { return provider }
        return StreamPluginProviderMatching.activeProviderCode(forCatalogSourceCode: LiveSourceHealthStore.providerFamily(for: source))
            ?? LiveSourceHealthStore.providerFamily(for: source)
    }
    static func preferredInitialIndex(
        in sessions: [StreamSession],
        contextKey: String
    ) -> Int {
        let sources = sessions.map(\.legacySource)
        guard let preferredID = LiveSourceHealthStore.automaticCandidates(
            in: sources,
            contextKey: contextKey
        ).first?.id else {
            return 0
        }
        return sessions.firstIndex(where: { $0.id == preferredID }) ?? 0
    }

    static func nextAutomaticSource(
        in sources: [StreamSource],
        after source: StreamSource,
        excluding failedSourceIDs: Set<UUID>,
        contextKey: String
    ) -> StreamSource? {
        let remaining = sources.filter {
            $0.id != source.id && !failedSourceIDs.contains($0.id)
        }
        return LiveSourceHealthStore.automaticCandidates(
            in: remaining,
            contextKey: contextKey
        ).first
    }

    /// A native startup timeout need not repeat that delivery while an already
    /// admitted, current alternative has positive decoded-playback history. This grants
    /// no lookup, new identity, retry budget or provider-wide failure penalty.
    @MainActor static func provenAlternativesBeforeNativeStartupRetry(
        in sessions: [StreamSession], for event: AnalyticalDataEngine.EventReference,
        after sourceID: UUID, failureKind: LivePlaybackFailureKind, hasDecoded: Bool,
        at now: Date = Date(),
        hasPositivePlayback: (StreamSource) -> Bool = { LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: $0) }
    ) -> Set<UUID> {
        guard failureKind == .startupTimeout, !hasDecoded,
              !event.hasCatalogIdentityConflict,
              MatchStartPolicy(event: event, now: now).timingAllowsPlayback else { return [] }
        let request = StreamPlaybackRequest(event: event)
        return Set(sessions.compactMap { session in
            guard session.id != sourceID, session.matchID == event.id,
                  session.validationStatus == .validated,
                  StreamPluginProviderMatching.isActivePlayerSession(session),
                  session.expiryTime.map({ $0 > now }) ?? true,
                  let provider = StreamEventBinding.providerCode(forSessionProviderName: session.providerName),
                  let binding = session.eventBinding,
                  binding.matches(request: request, providerCode: provider, at: now),
                  hasPositivePlayback(session.legacySource) else { return nil }
            return session.id
        })
    }

    /// One failing delivery must not make the viewer wait through every
    /// sibling from the same supplier before an independent lane gets a turn.
    /// This ordering is local to this single Watch attempt, never a persisted
    /// provider penalty, exclusion, or change to the manual source picker.
    static func singleStreamRecoveryOrder(
        ranked sources: [StreamSource], attempted: [StreamSource], after current: StreamSource? = nil,
        family: (StreamSource) -> String = LiveSourceHealthStore.providerFamily(for:),
        hasMeasuredSuccess: (StreamSource) -> Bool = { LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: $0) }
    ) -> [StreamSource] {
        let distinct = Dictionary(attempted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        let counts = Dictionary(grouping: distinct, by: family).mapValues(\.count)
        let currentFamily = current.map(family)
        let proven = sources.map(hasMeasuredSuccess)
        return sources.enumerated().sorted { lhs, rhs in
            let left = family(lhs.element)
            let right = family(rhs.element)
            // Historical success is coarse family/host evidence. Give it a
            // first turn, never let it drain every sibling after a live failure.
            let leftTier = proven[lhs.offset] && counts[left, default: 0] == 0 ? 0 : isWebEmbed(lhs.element) ? 2 : 1
            let rightTier = proven[rhs.offset] && counts[right, default: 0] == 0 ? 0 : isWebEmbed(rhs.element) ? 2 : 1
            if leftTier != rightTier { return leftTier < rightTier }
            if counts[left, default: 0] != counts[right, default: 0] { return counts[left, default: 0] < counts[right, default: 0] }
            if let currentFamily, (left == currentFamily) != (right == currentFamily) { return right == currentFamily }
            if proven[lhs.offset] != proven[rhs.offset] { return proven[lhs.offset] }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func isWebEmbed(_ source: StreamSource) -> Bool {
        if StreamPluginProviderMatching.isP2PLike(source) { return false }
        return (source.playbackContract ?? .describing(url: source.url, provider: source.provider,
                                                       headers: source.headers)).endpoint == .webPage
    }

    static func isWebEmbed(_ session: StreamSession) -> Bool {
        if StreamPluginProviderMatching.isP2PLike(session.legacySource) { return false }
        return session.playbackContract.endpoint == .webPage
    }

    static func isDiscoveryOnly(_ source: StreamSource) -> Bool {
        source.headers["X-Fotty-Discovery-Only"] == "true"
    }
}

/// A live DVR position is repairable only when an explicit current seekable
/// window proves it expired. Missing ranges, gaps and VOD never imply a seek.
enum SingleNativeResumeWindowPolicy {
    static func relation(position: Double, ranges: [(Double, Double)]) -> String {
        guard position.isFinite, position >= 0, !ranges.isEmpty,
              ranges.allSatisfy({ $0.0.isFinite && $0.1.isFinite && $0.0 >= 0 && $0.1 > $0.0 }) else { return "unknown" }
        if ranges.contains(where: { position >= $0.0 - 0.5 && position <= $0.1 + 0.5 }) { return "inside" }
        return position < ranges.map(\.0).min()! - 0.5 ? "expired" : "unknown"
    }
    static func catchUpTarget(position: Double, isLive: Bool, ranges: [(Double, Double)]) -> Double? {
        guard isLive, relation(position: position, ranges: ranges) == "expired",
              let latest = ranges.max(by: { $0.1 < $1.1 }), latest.1 - latest.0 >= 2 else { return nil }
        return latest.1 - min(3, (latest.1 - latest.0) / 2)
    }
}
