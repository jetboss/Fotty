import SwiftUI
import AVKit
import os.log

private let nativeFullscreenLifecycleLogger = Logger(subsystem: "com.jelani.Fotty", category: "PlaybackLifecycle")

/// Finite, local-only lifecycle evidence. This distinguishes a system PiP exit
/// from our exact presentation retirement without retaining media or user data.
enum NativeFullscreenLifecycleEvent: String, CaseIterable, Hashable, Sendable {
    case presented
    case pictureInPictureWillStart = "pip_will_start"
    case pictureInPictureDidStart = "pip_did_start"
    case pictureInPictureDidStop = "pip_did_stop"
    case pictureInPictureStartFailed = "pip_start_failed"
    case restoreRetained = "restore_retained"
    case restorePresented = "restore_presented"
    case finishOrphaned = "finish_orphaned"
    case finishReconciled = "finish_reconciled"
    case finishTransportRevoked = "finish_transport_revoked"
    case finishDismantled = "finish_dismantled"
    case finishDismissed = "finish_dismissed"
    case finishPictureInPictureStopped = "finish_pip_stopped"
}

/// Resolve only within the window that originally owned this presentation.
/// A covered marker may be detached by `.fullScreen`; that is not a lost lease.
@MainActor
enum NativeFullscreenPresentationResolver {
    enum Target {
        case retained
        case present(from: UIViewController)
    }

    static func target(in window: UIWindow, markerWindow: UIWindow?,
                       restoring controller: UIViewController? = nil) -> Target? {
        guard markerWindow == nil || markerWindow === window,
              let root = window.rootViewController else { return nil }
        var presenter = root
        var visited: Set<ObjectIdentifier> = []
        while true {
            guard visited.insert(ObjectIdentifier(presenter)).inserted,
                  !presenter.isBeingDismissed, !presenter.isBeingPresented else { return nil }
            if presenter === controller {
                return presenter.presentingViewController == nil ? nil : .retained
            }
            guard let next = presenter.presentedViewController else { break }
            presenter = next
        }
        guard controller?.presentingViewController == nil,
              presenter.viewIfLoaded?.window === window else { return nil }
        return .present(from: presenter)
    }
}

/// KVO can originate off the UI actor. A callback carries only a locked ticket
/// across the queue hop; it must never read presentation flags off that actor.
final class NativeFullscreenTransportObservationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch = UUID()
    private var enabled = true

    func renew(enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        epoch = UUID()
        self.enabled = enabled
    }

    func captureTicket() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        return enabled ? epoch : nil
    }

    func accepts(_ ticket: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && epoch == ticket
    }
}

/// A presentation lease, not a stream session. No URLs, loading or replacement
/// items are created here. Every callback must still own these exact objects.
@MainActor
final class NativeFullscreenSession {
    let id = UUID()
    let player: AVPlayer
    let item: AVPlayerItem
    let attemptID: UUID
    let sourceID: UUID?
    let transportObservationGate = NativeFullscreenTransportObservationGate()
    private(set) var isRetired = false
    private var presentationRetirement: (@MainActor () -> Void)?
    var controlsAreActive = false {
        didSet {
            if oldValue != controlsAreActive { renewTransportObservationAdmission() }
        }
    }
    var isClosing = false {
        didSet {
            if oldValue != isClosing { renewTransportObservationAdmission() }
        }
    }

    private func renewTransportObservationAdmission() {
        transportObservationGate.renew(enabled: !isRetired && (!isClosing || controlsAreActive))
    }

    /// Transport replacement must detach the exact borrowed controller even
    /// while its covered SwiftUI marker receives no presentation updates.
    /// This never pauses, seeks, reloads or starts the underlying player.
    func retire() {
        guard !isRetired else { return }
        isRetired = true
        controlsAreActive = false
        isClosing = true
        transportObservationGate.renew(enabled: false)
        let retirement = presentationRetirement
        presentationRetirement = nil
        retirement?()
    }

    func bindPresentationRetirement(_ retirement: @escaping @MainActor () -> Void) {
        guard !isRetired else { retirement(); return }
        presentationRetirement = retirement
    }

    func unbindPresentationRetirement() {
        presentationRetirement = nil
    }

    /// Native Done can finish its presentation while PiP keeps this lease.
    /// Suppress dismissal-generated rate changes only during that transition,
    /// not deliberate PiP controls for the rest of its retained lifetime.
    func beginClosingPresentation() {
        guard !isRetired else { return }
        isClosing = true
        controlsAreActive = false
    }

    func finishClosingTransition(cancelled: Bool, retainingPictureInPicture: Bool) {
        guard !isRetired else { return }
        if cancelled { isClosing = false }
        controlsAreActive = cancelled || retainingPictureInPicture
    }

    func finishRestoringPresentation() {
        guard !isRetired else { return }
        isClosing = false
        controlsAreActive = true
    }

    func permitsTransportObservation(pictureInPictureActive: Bool) -> Bool {
        !isRetired && (!isClosing || (controlsAreActive && pictureInPictureActive))
    }

    init(player: AVPlayer, item: AVPlayerItem, attemptID: UUID, sourceID: UUID?) {
        self.player = player; self.item = item
        self.attemptID = attemptID; self.sourceID = sourceID
    }
}

/// Always mounted beside the retained inline surface. Present the actual AVKit
/// controller (not a wrapper cover) so Apple owns fullscreen and its controls.
struct NativeFullscreenPresenter: UIViewControllerRepresentable {
    let model: LivePlayerViewModel

    func makeUIViewController(context: Context) -> NativeFullscreenHostController {
        NativeFullscreenHostController(model: model)
    }

    func updateUIViewController(_ controller: NativeFullscreenHostController, context: Context) {
        // Read observed fields here; reconcile after the SwiftUI update finishes.
        _ = model.nativeFullscreen
        let player = model.player, attempt = model.loadRequestID
        DispatchQueue.main.async { [weak controller] in
            guard let controller, controller.model.player === player,
                  controller.model.loadRequestID == attempt else { return }
            // A queued old nil/A snapshot must not close a newer lease B.
            controller.reconcile(controller.model.nativeFullscreen)
        }
    }

    static func dismantleUIViewController(_ controller: NativeFullscreenHostController, coordinator: ()) {
        controller.retirePresentation()
    }
}

@MainActor
final class NativeFullscreenHostController: UIViewController, @preconcurrency AVPlayerViewControllerDelegate {
    let model: LivePlayerViewModel
    private var session: NativeFullscreenSession?
    private var controller: AVPlayerViewController?
    private var readyObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var rateObserver: NSObjectProtocol?
    private var pipActive = false
    private var retired = false
    private weak var presentationWindow: UIWindow?
    private weak var lastAttachedWindow: UIWindow?
    private weak var pendingSession: NativeFullscreenSession?
    private weak var pendingWindow: UIWindow?
    private var pendingDeferrals = 0
    private var presentationRetryTask: Task<Void, Never>?
    private var presentationRetryTicket = UUID()
    private let maximumPresentationDeferrals: Int
    private let waitForPresentationRetry: @MainActor () async throws -> Void
    private let makePlayerController: @MainActor () -> AVPlayerViewController
    private var reportedInitialOutcomes: Set<String> = []
    private enum RestoreOutcome: String {
        case rejectedOwnership = "rejected_ownership"
        case missingWindow = "missing_window"
        case unavailablePresenter = "unavailable_presenter"
        case retained, presented
        case staleCompletion = "stale_completion"
    }
    private var reportedRestoreOutcomes: Set<RestoreOutcome> = []
    private var reportedLifecycleEvents: Set<NativeFullscreenLifecycleEvent> = []

    init(model: LivePlayerViewModel, maximumPresentationDeferrals: Int = 20,
         waitForPresentationRetry: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: .milliseconds(100))
         },
         makePlayerController: @escaping @MainActor () -> AVPlayerViewController = { AVPlayerViewController() }) {
        self.model = model
        self.maximumPresentationDeferrals = max(0, maximumPresentationDeferrals)
        self.waitForPresentationRetry = waitForPresentationRetry
        self.makePlayerController = makePlayerController
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = UIView(); view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = viewIfLoaded?.window { lastAttachedWindow = window }
        if pendingSession != nil { reconcile(model.nativeFullscreen) }
        else if let controller, controller.presentingViewController == nil, !pipActive {
            finishPresentation(reason: .finishOrphaned)
        } else { reconcile(model.nativeFullscreen) }
    }

    func reconcile(_ requested: NativeFullscreenSession?) {
        guard !retired else { return }
        if let pendingSession, requested !== pendingSession || !model.ownsNativeFullscreen(pendingSession) {
            cancelPendingPresentation(outcome: "cancelled")
        }
        if let session, requested !== session || !model.ownsNativeFullscreen(session) {
            finishPresentation(reason: .finishReconciled)
        }
        guard let requested, model.ownsNativeFullscreen(requested) else { return }
        if pendingSession === requested {
            if presentationRetryTask == nil { attemptInitialPresentation(requested) }
            return
        }
        guard session == nil else { return }
        pendingSession = requested
        pendingWindow = viewIfLoaded?.window ?? lastAttachedWindow
        pendingDeferrals = maximumPresentationDeferrals
        reportedInitialOutcomes.removeAll()
        requested.bindPresentationRetirement { [weak self, weak requested] in
            guard let self, let requested else { return }
            if self.session === requested { self.finishPresentation(reason: .finishTransportRevoked) }
            else if self.pendingSession === requested { self.cancelPendingPresentation(outcome: "cancelled") }
        }
        attemptInitialPresentation(requested)
    }

    private func attemptInitialPresentation(_ requested: NativeFullscreenSession) {
        guard pendingSession === requested else { return }
        guard !retired, model.ownsNativeFullscreen(requested), !model.isAppBackgrounded,
              !model.isPictureInPictureActive else {
            cancelPendingPresentation(outcome: "cancelled")
            return
        }
        if session === requested {
            if !completeInitialPresentationIfRetained(requested) { deferInitialPresentation(requested) }
            return
        }
        guard let window = viewIfLoaded?.window else {
            recordInitialOutcome("missing_window")
            deferInitialPresentation(requested)
            return
        }
        if let pendingWindow, pendingWindow !== window {
            cancelPendingPresentation(outcome: "changed_window")
            return
        }
        pendingWindow = window
        lastAttachedWindow = window
        guard case .present(let presenter)? = NativeFullscreenPresentationResolver.target(
            in: window, markerWindow: window) else {
            recordInitialOutcome("unavailable_presenter")
            deferInitialPresentation(requested)
            return
        }
        // This marker's actual scene owns the presentation. Never use a global
        // first window or dismiss someone else's sheet to make room.
        let playerController = makePlayerController()
        playerController.player = requested.player
        playerController.showsPlaybackControls = true
        playerController.updatesNowPlayingInfoCenter = false
        playerController.allowsPictureInPicturePlayback = model.allowsViewingPiP
        playerController.canStartPictureInPictureAutomaticallyFromInline = model.allowsViewingPiP
        playerController.modalPresentationStyle = .fullScreen
        playerController.overrideUserInterfaceStyle = .dark
        playerController.delegate = self
        session = requested; controller = playerController
        requested.bindPresentationRetirement { [weak self, weak requested] in
            guard let self, let requested, self.session === requested else { return }
            self.finishPresentation(reason: .finishTransportRevoked)
        }
        presentationWindow = window
        reportedRestoreOutcomes.removeAll()
        reportedLifecycleEvents.removeAll()
        playerController.loadViewIfNeeded()
        bindObservations(playerController, session: requested)
        if AppRuntime.isPhysicalLiveTesting, let overlay = playerController.contentOverlayView {
            let measurement = NativeFullscreenMeasurementView(controller: playerController,
                session: requested, binding: model.nativeMeasurementBinding)
            measurement.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(measurement)
            NSLayoutConstraint.activate([
                measurement.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                measurement.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                measurement.topAnchor.constraint(equalTo: overlay.topAnchor),
                measurement.bottomAnchor.constraint(equalTo: overlay.bottomAnchor)
            ])
        }
        presenter.present(playerController, animated: true) { [weak self, weak requested] in
            guard let self, let requested, self.pendingSession === requested,
                  self.model.ownsNativeFullscreen(requested), self.controller === playerController else { return }
            if !self.completeInitialPresentationIfRetained(requested) { self.deferInitialPresentation(requested) }
        }
        // UIKit can refuse a presentation without invoking its completion.
        // The same bounded pending lease must recover that path as well.
        if pendingSession === requested { deferInitialPresentation(requested) }
    }

    private func completeInitialPresentationIfRetained(_ requested: NativeFullscreenSession) -> Bool {
        guard !retired, pendingSession === requested, model.ownsNativeFullscreen(requested),
              !model.isAppBackgrounded, !model.isPictureInPictureActive, !requested.isClosing,
              let controller, let window = presentationWindow,
              case .retained? = NativeFullscreenPresentationResolver.target(in: window,
                markerWindow: viewIfLoaded?.window, restoring: controller) else { return false }
        clearPendingPresentation(keepingRetirement: true)
        requested.controlsAreActive = true
        model.commitNativeFullscreenPresentation(requested)
        publishReady()
        recordLifecycle(.presented)
        return true
    }

    private func deferInitialPresentation(_ requested: NativeFullscreenSession) {
        guard pendingSession === requested, presentationRetryTask == nil else { return }
        guard pendingDeferrals > 0 else {
            cancelPendingPresentation(outcome: "exhausted")
            return
        }
        pendingDeferrals -= 1
        let ticket = UUID()
        presentationRetryTicket = ticket
        let wait = waitForPresentationRetry
        presentationRetryTask = Task { @MainActor [weak self, weak requested] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, let self, let requested,
                  self.pendingSession === requested, self.presentationRetryTicket == ticket else { return }
            self.presentationRetryTask = nil
            self.attemptInitialPresentation(requested)
        }
    }

    private func clearPendingPresentation(keepingRetirement: Bool = false) {
        presentationRetryTicket = UUID()
        presentationRetryTask?.cancel(); presentationRetryTask = nil
        if !keepingRetirement { pendingSession?.unbindPresentationRetirement() }
        pendingSession = nil
        pendingWindow = nil
        pendingDeferrals = 0
    }

    private func cancelPendingPresentation(outcome: String) {
        guard let pending = pendingSession else { return }
        recordInitialOutcome(outcome)
        clearPendingPresentation()
        if session === pending { finishPresentation(reason: .finishOrphaned) }
        else { model.endNativeFullscreen(pending) }
    }

    private func recordInitialOutcome(_ outcome: String) {
        guard reportedInitialOutcomes.insert(outcome).inserted else { return }
        nativeFullscreenLifecycleLogger.info("event=native_fullscreen_initial outcome=\(outcome, privacy: .public)")
    }

    private func bindObservations(_ controller: AVPlayerViewController, session: NativeFullscreenSession) {
        readyObservation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.publishReady() }
        }
        let transportGate = session.transportObservationGate
        statusObservation = session.player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak session, transportGate] _, _ in
            guard let ticket = transportGate.captureTicket() else { return }
            DispatchQueue.main.async {
                guard transportGate.accepts(ticket),
                      let self, let session, self.model.ownsNativeFullscreen(session),
                      self.model.nativeFullscreenIsPresented,
                      session.permitsTransportObservation(pictureInPictureActive: self.pipActive) else { return }
                self.model.handleNativeTimeControlStatusChanged(session.player.timeControlStatus)
            }
        }
        rateObserver = NotificationCenter.default.addObserver(forName: AVPlayer.rateDidChangeNotification,
            object: session.player, queue: .main) { [weak self, weak session] notification in
            guard let raw = notification.userInfo?[AVPlayer.rateDidChangeReasonKey] as? String else { return }
            // The .main observer is synchronous for commands on the model's
            // MainActor, before its queued time-control observation can undo Play.
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                self.model.handleFullscreenRateCommand(session.player.rate,
                    reason: .init(rawValue: raw), session: session)
            }
        }
    }

    private func publishReady() {
        guard let session, let controller, model.ownsNativeFullscreen(session),
              model.nativeFullscreenIsPresented, !session.isClosing else { return }
        model.isVideoReadyForDisplay = controller.isReadyForDisplay
        model.handlePictureInPictureAvailabilityChanged(
            model.allowsViewingPiP && controller.isReadyForDisplay && AVPictureInPictureController.isPictureInPictureSupported())
    }

    private func finishPresentation(reason: NativeFullscreenLifecycleEvent) {
        guard let oldSession = session else { return }
        if pendingSession === oldSession { clearPendingPresentation() }
        recordLifecycle(reason)
        oldSession.unbindPresentationRetirement()
        oldSession.retire()
        readyObservation?.invalidate(); readyObservation = nil
        statusObservation?.invalidate(); statusObservation = nil
        if let rateObserver { NotificationCenter.default.removeObserver(rateObserver) }; rateObserver = nil
        let oldController = controller
        oldController?.delegate = nil
        oldController?.player = nil // Detach the presentation; never pause/reload the model's player.
        controller = nil; session = nil; pipActive = false
        presentationWindow = nil
        reportedRestoreOutcomes.removeAll()
        if oldController?.presentingViewController != nil { oldController?.dismiss(animated: false) }
        model.endNativeFullscreen(oldSession)
    }

    func retirePresentation() {
        retired = true
        if session != nil { finishPresentation(reason: .finishDismantled) }
        else { cancelPendingPresentation(outcome: "cancelled") }
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        guard controller === playerViewController, let session else { return }
        session.beginClosingPresentation()
        coordinator.animate(alongsideTransition: nil) { [weak self, weak session] context in
            guard let self, let session, self.session === session else { return }
            session.finishClosingTransition(cancelled: context.isCancelled,
                                            retainingPictureInPicture: self.pipActive)
            if context.isCancelled { return }
            if !self.pipActive { self.finishPresentation(reason: .finishDismissed) }
        }
    }

    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool { false }

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        guard controller === playerViewController, let session, model.ownsNativeFullscreen(session) else { return }
        pipActive = true
        recordLifecycle(.pictureInPictureWillStart)
        model.handlePictureInPictureActivityChanged(true)
    }

    func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        playerViewControllerWillStartPictureInPicture(playerViewController)
        guard controller === playerViewController, let session, model.ownsNativeFullscreen(session) else { return }
        recordLifecycle(.pictureInPictureDidStart)
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        guard controller === playerViewController, let session, model.ownsNativeFullscreen(session) else { return }
        pipActive = false
        recordLifecycle(.pictureInPictureDidStop)
        model.handlePictureInPictureActivityChanged(false,
            isBackgrounded: view.window?.windowScene?.activationState == .background)
        if session.isClosing { finishPresentation(reason: .finishPictureInPictureStopped) }
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              failedToStartPictureInPictureWithError error: Error) {
        guard controller === playerViewController, let session, model.ownsNativeFullscreen(session) else { return }
        pipActive = false
        recordLifecycle(.pictureInPictureStartFailed)
        model.handlePictureInPictureFailure("Picture in Picture could not start.",
            isBackgrounded: view.window?.windowScene?.activationState == .background)
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard !retired, controller === playerViewController, let session, model.ownsNativeFullscreen(session) else {
            if controller === playerViewController { recordRestoreOutcome(.rejectedOwnership) }
            completionHandler(false); return
        }
        guard let window = presentationWindow else {
            recordRestoreOutcome(.missingWindow)
            completionHandler(false); return
        }
        guard let target = NativeFullscreenPresentationResolver.target(in: window,
                markerWindow: viewIfLoaded?.window, restoring: playerViewController) else {
            recordRestoreOutcome(.unavailablePresenter)
            completionHandler(false); return
        }
        switch target {
        case .retained:
            session.finishRestoringPresentation()
            publishReady()
            recordRestoreOutcome(.retained)
            recordLifecycle(.restoreRetained)
            completionHandler(true)
        case .present(let presenter):
            // Native Done can dismiss the UI while its PiP continues. Restore
            // this same controller, never manufacture a new stream/controller.
            presenter.present(playerViewController, animated: false) { [weak self, weak session, weak window] in
                guard let self, let session, let window, !self.retired,
                      self.presentationWindow === window, self.model.ownsNativeFullscreen(session),
                      self.controller === playerViewController,
                      case .retained? = NativeFullscreenPresentationResolver.target(in: window,
                        markerWindow: self.viewIfLoaded?.window, restoring: playerViewController) else {
                    if let self, self.controller === playerViewController { self.recordRestoreOutcome(.staleCompletion) }
                    completionHandler(false); return
                }
                // A failed restore must retain its closing lease so PiP Stop
                // can release fullscreen and rebind the original inline layer.
                session.finishRestoringPresentation()
                self.publishReady()
                self.recordRestoreOutcome(.presented)
                self.recordLifecycle(.restorePresented)
                completionHandler(true)
            }
        }
    }

    private func recordRestoreOutcome(_ outcome: RestoreOutcome) {
        // At most six local records per lease. No titles, URLs or user data.
        guard reportedRestoreOutcomes.insert(outcome).inserted else { return }
        let markerAttached = viewIfLoaded?.window != nil
        let retainedPresented = controller?.presentingViewController != nil
        nativeFullscreenLifecycleLogger.info("event=native_pip_restore outcome=\(outcome.rawValue, privacy: .public) marker_attached=\(markerAttached, privacy: .public) retained_presented=\(retainedPresented, privacy: .public)")
    }

    private func recordLifecycle(_ event: NativeFullscreenLifecycleEvent) {
        // At most one entry for each finite event per presentation lease; the
        // shared local store is bounded too. No periodic or network collection.
        guard let session, reportedLifecycleEvents.insert(event).inserted else { return }
        var details = [
            "attempt_id": session.attemptID.uuidString,
            "mode": "native",
            "native_presentation_id": session.id.uuidString,
            "native_presentation_event": event.rawValue,
            "native_pip_active": String(pipActive),
            "native_app_backgrounded": String(model.isAppBackgrounded)
        ]
        if let sourceID = session.sourceID { details["source_id"] = sourceID.uuidString }
        FottyQualityStore.shared.record(category: .playback, name: "native_presentation",
                                       outcome: .info, details: details)
    }
}

/// Pull-only physical evidence from AVKit's real rendered surface, not from a
/// hidden inline layer. It shares identity tokens with that retained layer.
@MainActor
private final class NativeFullscreenMeasurementView: UIView {
    private weak var controller: AVPlayerViewController?
    private let session: NativeFullscreenSession
    private let binding: NativePlaybackMeasurementBinding
    init(controller: AVPlayerViewController, session: NativeFullscreenSession, binding: NativePlaybackMeasurementBinding) {
        self.controller = controller; self.session = session; self.binding = binding
        super.init(frame: .zero)
        isUserInteractionEnabled = false; isAccessibilityElement = true
        accessibilityIdentifier = "native-fullscreen-measurement"
        accessibilityLabel = "Native fullscreen playback measurement"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var accessibilityValue: String? {
        get {
            guard let controller, controller.player === session.player,
                  session.player.currentItem === session.item else { return "{\"measurementAvailable\":false}" }
            let scalar = NativePlaybackMeasurementEncoding.scalar
            let ready = controller.isReadyForDisplay
            let scale = window?.screen.scale ?? 0
            return NativePlaybackMeasurementEncoding.json([
                "measurementAvailable": true,
                "playerToken": binding.playerToken(for: session.player)?.uuidString as Any? ?? NSNull(),
                "itemToken": binding.token(for: session.item, attempt: session.attemptID)?.uuidString as Any? ?? NSNull(),
                "attemptToken": session.attemptID.uuidString,
                "readyForDisplay": ready,
                "currentTimeSeconds": scalar(session.item.currentTime().seconds),
                "rate": scalar(Double(session.player.rate)),
                "timeControlStatus": session.player.timeControlStatus.rawValue,
                "itemStatus": session.item.status.rawValue,
                "renderedPixelWidth": scalar(ready ? Double(controller.videoBounds.width * scale) : nil),
                "renderedPixelHeight": scalar(ready ? Double(controller.videoBounds.height * scale) : nil),
                "presentationWidth": scalar(Double(session.item.presentationSize.width)),
                "presentationHeight": scalar(Double(session.item.presentationSize.height)),
                "uptimeSeconds": scalar(ProcessInfo.processInfo.systemUptime)
            ])
        }
        set { super.accessibilityValue = newValue }
    }
}
