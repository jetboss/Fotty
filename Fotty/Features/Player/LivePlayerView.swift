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

/// WKWebView can win physical-device hit testing even when SwiftUI buttons are
/// visibly composited above it. Keep the control surface deliberately small,
/// but back it with real UIKit buttons so Pause and Sources receive the touch
/// before it reaches the provider page.
struct WebEmbedToolbarView: UIViewRepresentable {
    let isPlaying: Bool
    let showSources: Bool
    let onTogglePlayPause: () -> Void
    let onShowSources: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var buttonFontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTogglePlayPause: onTogglePlayPause,
            onShowSources: onShowSources
        )
    }

    func makeUIView(context: Context) -> ToolbarView {
        let view = ToolbarView()
        view.pauseButton.addTarget(
            context.coordinator,
            action: #selector(Coordinator.togglePlayPause),
            for: .touchUpInside
        )
        view.sourcesButton.addTarget(
            context.coordinator,
            action: #selector(Coordinator.showSources),
            for: .touchUpInside
        )
        return view
    }

    func updateUIView(_ uiView: ToolbarView, context: Context) {
        context.coordinator.onTogglePlayPause = onTogglePlayPause
        context.coordinator.onShowSources = onShowSources
        uiView.update(isPlaying: isPlaying, showSources: showSources, fontSize: buttonFontSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ToolbarView, context: Context) -> CGSize? {
        uiView.fittingSize(maximumWidth: proposal.width)
    }

    final class Coordinator: NSObject {
        var onTogglePlayPause: () -> Void
        var onShowSources: () -> Void

        init(
            onTogglePlayPause: @escaping () -> Void,
            onShowSources: @escaping () -> Void
        ) {
            self.onTogglePlayPause = onTogglePlayPause
            self.onShowSources = onShowSources
        }

        @objc func togglePlayPause() {
            onTogglePlayPause()
        }

        @objc func showSources() {
            onShowSources()
        }
    }

    final class ToolbarView: UIView {
        let pauseButton = UIButton(type: .system)
        let sourcesButton = UIButton(type: .system)
        private let stack = UIStackView()
        private var sourcesMinimumConstraints: [NSLayoutConstraint] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = true

            stack.axis = .horizontal
            stack.alignment = .fill
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)

            configure(pauseButton, accessibilityIdentifier: "web-play-pause")
            configure(sourcesButton, accessibilityIdentifier: "web-broadcast-sources")
            stack.addArrangedSubview(pauseButton)
            stack.addArrangedSubview(sourcesButton)

            sourcesMinimumConstraints = [
                sourcesButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                sourcesButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ]
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                pauseButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                pauseButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ] + sourcesMinimumConstraints)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(isPlaying: Bool, showSources: Bool, fontSize: CGFloat = 13) {
            var pauseConfiguration = buttonConfiguration(fontSize: fontSize)
            pauseConfiguration.title = isPlaying ? "Pause" : "Play"
            pauseConfiguration.image = UIImage(
                systemName: isPlaying ? "pause.fill" : "play.fill"
            )
            pauseButton.configuration = pauseConfiguration
            pauseButton.accessibilityLabel = isPlaying ? "Pause broadcast" : "Play broadcast"

            var sourcesConfiguration = buttonConfiguration(fontSize: fontSize)
            sourcesConfiguration.title = "Sources"
            sourcesConfiguration.image = UIImage(
                systemName: "antenna.radiowaves.left.and.right"
            )
            sourcesButton.configuration = sourcesConfiguration
            sourcesButton.accessibilityLabel = "Choose broadcast source"
            if sourcesButton.isHidden == showSources {
                // UIStackView collapses hidden arranged views to zero. Remove
                // only their minimum bounds, not the visible touch targets.
                if showSources {
                    sourcesButton.isHidden = false
                    NSLayoutConstraint.activate(sourcesMinimumConstraints)
                } else {
                    NSLayoutConstraint.deactivate(sourcesMinimumConstraints)
                    sourcesButton.isHidden = true
                }
            }
            invalidateIntrinsicContentSize()
        }

        /// Measure the real labels/icons instead of forcing both buttons into
        /// 186pt. A narrow window or larger text reflows the small toolbar; it
        /// never shrinks or splits the Sources label to preserve a fixed frame.
        func fittingSize(maximumWidth: CGFloat? = nil) -> CGSize {
            stack.axis = .horizontal
            var size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if let maximumWidth, maximumWidth.isFinite, size.width > maximumWidth,
               !sourcesButton.isHidden {
                stack.axis = .vertical
                size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            }
            return CGSize(width: ceil(size.width), height: ceil(size.height))
        }

        private func configure(_ button: UIButton, accessibilityIdentifier: String) {
            button.accessibilityIdentifier = accessibilityIdentifier
            button.isAccessibilityElement = true
            button.adjustsImageSizeForAccessibilityContentSizeCategory = true
            button.titleLabel?.numberOfLines = 1
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        private func buttonConfiguration(fontSize: CGFloat) -> UIButton.Configuration {
            var configuration = UIButton.Configuration.filled()
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.72)
            configuration.cornerStyle = .capsule
            configuration.imagePlacement = .leading
            configuration.imagePadding = 5
            configuration.preferredSymbolConfigurationForImage = .init(pointSize: fontSize, weight: .bold)
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 8,
                leading: 10,
                bottom: 8,
                trailing: 10
            )
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: fontSize, weight: .bold)
                return outgoing
            }
            return configuration
        }
    }
}

// MARK: - Raw AVPlayer View

/// Local, pull-only hardware-test evidence. This intentionally never reads a
/// stream URI, server address, request header, or AV playback session ID.
enum NativePlaybackMeasurementEncoding {
    static func scalar(_ value: Double?) -> Any {
        guard let value, value.isFinite, value >= 0, value <= 9_007_199_254_740_991 else {
            return NSNull()
        }
        return value
    }

    static func json(_ values: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              data.count <= 4_096,
              let value = String(data: data, encoding: .utf8) else {
            return "{\"measurementAvailable\":false}"
        }
        return value
    }
}

@MainActor
final class NativePlaybackMeasurementBinding {
    private weak var currentPlayer: AVPlayer?
    private var playerIdentity: UUID?
    private weak var currentItem: AVPlayerItem?
    private var currentAttempt: UUID?
    private var itemToken: UUID?
    private weak var physicalItem: AVPlayerItem?
    private var physicalItemIdentity: UUID?

    /// Actual AV object identity. Attempt labels can change while the old item
    /// remains visible during preparation of its replacement.
    func physicalItemToken(for item: AVPlayerItem?) -> UUID? {
        guard let item else { return nil }
        if physicalItem !== item { physicalItem = item; physicalItemIdentity = UUID() }
        return physicalItemIdentity
    }

    func playerToken(for player: AVPlayer?) -> UUID? {
        guard let player else { return nil }
        if currentPlayer !== player { currentPlayer = player; playerIdentity = UUID() }
        return playerIdentity
    }

    func token(for item: AVPlayerItem?, attempt: UUID?) -> UUID? {
        guard let item else {
            reset()
            return nil
        }
        if currentItem !== item || currentAttempt != attempt {
            currentItem = item
            currentAttempt = attempt
            itemToken = UUID()
        }
        return itemToken
    }

    func reset() {
        currentPlayer = nil; playerIdentity = nil
        currentItem = nil
        currentAttempt = nil
        itemToken = nil
        physicalItem = nil; physicalItemIdentity = nil
    }
}

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var pictureInPictureRequestID: UUID? = nil
    var allowsPictureInPicture = true
    var capturesSurfaceTaps = true
    var physicalMeasurementIdentifier = "native-playback-measurement"
    var physicalMeasurementAttemptID: UUID? = nil
    var physicalMeasurementPane: Int? = nil
    var measurementBinding: NativePlaybackMeasurementBinding? = nil
    var suspendsInlinePlayback = false
    var onSurfaceTapped: (() -> Void)? = nil
    var onReadyForDisplayChanged: ((Bool) -> Void)? = nil
    var onTimeControlStatusChanged: ((AVPlayer.TimeControlStatus) -> Void)? = nil
    var onPictureInPictureAvailabilityChanged: ((Bool) -> Void)? = nil
    var onPictureInPictureActiveChanged: ((Bool) -> Void)? = nil
    var onPictureInPictureFailure: ((String) -> Void)? = nil
    
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.measurementBinding = measurementBinding
        view.suspendsInlinePlayback = suspendsInlinePlayback
        view.configurePhysicalMeasurement(
            identifier: physicalMeasurementIdentifier,
            attemptID: physicalMeasurementAttemptID, pane: physicalMeasurementPane
        )
        view.capturesSurfaceTaps = capturesSurfaceTaps
        view.onReadyForDisplayChanged = onReadyForDisplayChanged
        view.onSurfaceTapped = onSurfaceTapped
        view.onTimeControlStatusChanged = onTimeControlStatusChanged
        view.onPictureInPictureAvailabilityChanged = onPictureInPictureAvailabilityChanged
        view.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        view.onPictureInPictureFailure = onPictureInPictureFailure
        view.allowsPictureInPicture = allowsPictureInPicture
        view.player = player
        view.videoGravity = videoGravity
        view.pictureInPictureRequestID = pictureInPictureRequestID
        return view
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.measurementBinding = measurementBinding
        uiView.suspendsInlinePlayback = suspendsInlinePlayback
        uiView.configurePhysicalMeasurement(
            identifier: physicalMeasurementIdentifier,
            attemptID: physicalMeasurementAttemptID, pane: physicalMeasurementPane
        )
        uiView.capturesSurfaceTaps = capturesSurfaceTaps
        uiView.onReadyForDisplayChanged = onReadyForDisplayChanged
        uiView.onSurfaceTapped = onSurfaceTapped
        uiView.onTimeControlStatusChanged = onTimeControlStatusChanged
        uiView.onPictureInPictureAvailabilityChanged = onPictureInPictureAvailabilityChanged
        uiView.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        uiView.onPictureInPictureFailure = onPictureInPictureFailure
        uiView.allowsPictureInPicture = allowsPictureInPicture
        uiView.player = player
        uiView.videoGravity = videoGravity
        uiView.pictureInPictureRequestID = pictureInPictureRequestID
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.dismantlePlaybackBinding()
    }
    
    class PlayerUIView: UIView, AVPictureInPictureControllerDelegate {
        var measurementBinding: NativePlaybackMeasurementBinding?
        var suspendsInlinePlayback = false {
            didSet {
                guard oldValue != suspendsInlinePlayback else { return }
                if suspendsInlinePlayback {
                    // The fullscreen controller borrows the same transport.
                    // Retire only inline render/PiP ownership, never pause it.
                    timeControlStatusObservation?.invalidate(); timeControlStatusObservation = nil
                    pictureInPicturePossibleObservation?.invalidate(); pictureInPicturePossibleObservation = nil
                    pictureInPictureController?.delegate = nil; pictureInPictureController = nil
                    playerLayer.player = nil
                } else { configurePictureInPictureIfNeeded() }
            }
        }
        var allowsPictureInPicture = true {
            didSet {
                guard oldValue != allowsPictureInPicture else { return }
                pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
                DispatchQueue.main.async { [weak self] in self?.notifyPictureInPictureAvailability() }
            }
        }
        var capturesSurfaceTaps = true {
            didSet {
                isUserInteractionEnabled = capturesSurfaceTaps
            }
        }
        var onSurfaceTapped: (() -> Void)?
        // These callbacks are reassigned by SwiftUI during updateUIView. They
        // must not synchronously publish state from their setters: doing so
        // creates updateUIView -> callback -> observable mutation -> updateUIView
        // feedback and eventually trips the foreground scene watchdog.
        var onReadyForDisplayChanged: ((Bool) -> Void)?
        var onTimeControlStatusChanged: ((AVPlayer.TimeControlStatus) -> Void)?
        var onPictureInPictureAvailabilityChanged: ((Bool) -> Void)?
        var onPictureInPictureActiveChanged: ((Bool) -> Void)?
        var onPictureInPictureFailure: ((String) -> Void)?
        var pictureInPictureRequestID: UUID? {
            didSet {
                guard let requestID = pictureInPictureRequestID,
                      requestID != oldValue else { return }
                // AVKit may reject a request synchronously. Deliver the command
                // after updateUIView has finished, just like observation events.
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isDismantled,
                          self.pictureInPictureRequestID == requestID else { return }
                    self.startPictureInPictureIfRequested()
                }
            }
        }

        private var readyForDisplayObservation: NSKeyValueObservation?
        private var timeControlStatusObservation: NSKeyValueObservation?
        private var pictureInPicturePossibleObservation: NSKeyValueObservation?
        private var pictureInPictureController: AVPictureInPictureController?
        private var handledPictureInPictureRequestID: UUID?
        private var isDismantled = false
        private let physicalMeasurementBinding = NativePlaybackMeasurementBinding()
        private var physicalMeasurementAttemptID: UUID?
        private var physicalMeasurementPane: Int?
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        override var accessibilityValue: String? {
            get {
                guard AppRuntime.isPhysicalLiveTesting, !isDismantled else {
                    return super.accessibilityValue
                }
                return physicalMeasurementSnapshot()
            }
            set { super.accessibilityValue = newValue }
        }

        func configurePhysicalMeasurement(identifier: String, attemptID: UUID?, pane: Int?) {
            physicalMeasurementAttemptID = attemptID
            physicalMeasurementPane = pane
            guard AppRuntime.isPhysicalLiveTesting else { return }
            isAccessibilityElement = true
            accessibilityIdentifier = identifier
            accessibilityLabel = "Native playback measurement"
        }

        /// Synchronous reads only, requested by XCTest. No observers, periodic
        /// work, buffers, persistence, uploads, or normal UI are added.
        func physicalMeasurementSnapshot() -> String {
            guard !suspendsInlinePlayback else { return "{\"measurementAvailable\":false}" }
            let physicalMeasurementBinding = measurementBinding ?? self.physicalMeasurementBinding
            // An unbound/temporarily hidden surface is not item retirement.
            // Pulling its AX value must not reset the model's shared identity.
            let player = playerLayer.player
            let item = player?.currentItem
            let itemToken = item.flatMap {
                physicalMeasurementBinding.token(for: $0, attempt: physicalMeasurementAttemptID)
            }
            let events = item?.accessLog()?.events
            let event = events?.last
            let ready = item != nil && playerLayer.isReadyForDisplay
            let screenScale = window?.screen.scale
            let pixelWidth = ready ? screenScale.map { Double(playerLayer.videoRect.width * $0) } : nil
            let pixelHeight = ready ? screenScale.map { Double(playerLayer.videoRect.height * $0) } : nil
            let scalar = NativePlaybackMeasurementEncoding.scalar
            let values: [String: Any] = [
                "measurementAvailable": item != nil && !isDismantled,
                "playerToken": physicalMeasurementBinding.playerToken(for: player)?.uuidString as Any? ?? NSNull(),
                "itemToken": itemToken?.uuidString as Any? ?? NSNull(),
                "physicalItemToken": physicalMeasurementBinding.physicalItemToken(for: item)?.uuidString as Any? ?? NSNull(),
                "attemptToken": physicalMeasurementAttemptID?.uuidString as Any? ?? NSNull(),
                "pane": physicalMeasurementPane.map(Double.init).map(scalar) ?? NSNull(),
                "uptimeSeconds": scalar(ProcessInfo.processInfo.systemUptime),
                "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                "readyForDisplay": ready,
                "currentTimeSeconds": scalar(item?.currentTime().seconds),
                "rate": scalar(item == nil ? nil : player.map { Double($0.rate) }),
                "timeControlStatus": item == nil ? NSNull() : player?.timeControlStatus.rawValue as Any? ?? NSNull(),
                "itemStatus": item?.status.rawValue as Any? ?? NSNull(),
                "presentationWidth": scalar(item.map { Double($0.presentationSize.width) }),
                "presentationHeight": scalar(item.map { Double($0.presentationSize.height) }),
                "renderedPixelWidth": scalar(pixelWidth),
                "renderedPixelHeight": scalar(pixelHeight),
                "accessLogAvailable": event != nil,
                // Access-log counters describe the latest uninterrupted event,
                // not a sum of snapshots. Compare only the same item/attempt
                // and event index; a reset is not negative consumption.
                "accessLogEventCount": scalar(events.map { Double($0.count) }),
                "accessLogEventIndex": scalar(events.flatMap { $0.isEmpty ? nil : Double($0.count - 1) }),
                "bytesTransferred": scalar(event.map { Double($0.numberOfBytesTransferred) }),
                "transferDurationSeconds": scalar(event?.transferDuration),
                "observedBitrate": scalar(event?.observedBitrate),
                "indicatedBitrate": scalar(event?.indicatedBitrate),
                "droppedVideoFrames": scalar(event.map { Double($0.numberOfDroppedVideoFrames) }),
                "stalls": scalar(event.map { Double($0.numberOfStalls) })
            ]
            return NativePlaybackMeasurementEncoding.json(values)
        }
        
        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                guard !suspendsInlinePlayback else { return }
                guard playerLayer.player !== newValue else { return }
                timeControlStatusObservation?.invalidate()
                playerLayer.player = newValue
                timeControlStatusObservation = newValue?.observe(
                    \.timeControlStatus,
                    options: [.initial, .new]
                ) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.notifyTimeControlStatus() }
                }
            }
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
            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(surfaceTapped)))
            readyForDisplayObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.notifyReadyForDisplay() }
            }
            configurePictureInPictureIfNeeded()
        }
        
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func surfaceTapped() {
            onSurfaceTapped?()
        }

        deinit {
            readyForDisplayObservation?.invalidate()
            timeControlStatusObservation?.invalidate()
            pictureInPicturePossibleObservation?.invalidate()
            pictureInPictureController?.delegate = nil
        }

        func dismantlePlaybackBinding() {
            isDismantled = true
            physicalMeasurementBinding.reset()
            pictureInPictureRequestID = nil
            onSurfaceTapped = nil
            onReadyForDisplayChanged = nil
            onTimeControlStatusChanged = nil
            onPictureInPictureAvailabilityChanged = nil
            onPictureInPictureActiveChanged = nil
            onPictureInPictureFailure = nil
            readyForDisplayObservation?.invalidate()
            timeControlStatusObservation?.invalidate()
            pictureInPicturePossibleObservation?.invalidate()
            pictureInPictureController?.delegate = nil
            pictureInPictureController?.stopPictureInPicture()
            pictureInPictureController = nil
            // The model owns the player. Detach this discarded surface without
            // pausing a player that may already belong to its replacement.
            playerLayer.player = nil
        }
        private func notifyReadyForDisplay() {
            guard !isDismantled, !suspendsInlinePlayback else { return }
            onReadyForDisplayChanged?(playerLayer.isReadyForDisplay)
        }
        private func notifyTimeControlStatus() {
            guard !isDismantled, !suspendsInlinePlayback else { return }
            guard let player = playerLayer.player else { return }
            onTimeControlStatusChanged?(player.timeControlStatus)
        }
        
        private func configurePictureInPictureIfNeeded() {
            guard !isDismantled, !suspendsInlinePlayback else { return }
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
            controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
            pictureInPictureController = controller
            pictureInPicturePossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.notifyPictureInPictureAvailability() }
            }
        }

        private func notifyPictureInPictureAvailability() {
            guard !isDismantled, !suspendsInlinePlayback else { return }
            let available = allowsPictureInPicture && AVPictureInPictureController.isPictureInPictureSupported()
                && (pictureInPictureController?.isPictureInPicturePossible ?? false)
            onPictureInPictureAvailabilityChanged?(available)
        }

        private func startPictureInPictureIfRequested() {
            guard !isDismantled, !suspendsInlinePlayback else { return }
            guard allowsPictureInPicture, let requestID = pictureInPictureRequestID,
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

/// Portrait identity can wrap without shrinking the team names or fabricating
/// an opponent for channels and non-match events.
struct PlayerPortraitIdentity: View {
    let event: AnalyticalDataEngine.EventReference
    let status: String

    var hasTeamPair: Bool {
        let home = event.homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = event.awayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !event.isBroadcastChannel && !home.isEmpty && !away.isEmpty
            && (home != "Home" || event.teams?.home?.name != nil)
            && (away != "Away" || event.teams?.away?.name != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasTeamPair {
                teamRow(name: event.homeName, badge: event.homeBadgeURL)
                teamRow(name: event.awayName, badge: event.awayBadgeURL)
            } else {
                Text(event.displayTitle)
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(status)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func teamRow(name: String, badge: URL?) -> some View {
        HStack(alignment: .top, spacing: 7) {
            TeamBadgeWindow(teamName: name, badgeURL: badge, size: 22)
                .accessibilityHidden(true)
            Text(name)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

private struct ViewingLegacyEdgeDismiss: ViewModifier {
    let enabled: Bool
    let onClose: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.fottyLeadingEdgeSwipeDismissesPlayer(onDismiss: onClose) }
        else { content }
    }
}

struct LivePlayerView: View {
    @State var viewModel: LivePlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(LiveScoreService.self) private var scoreService
    
    @State private var didApplyLandscape = false
    @State private var scorePollingOwner = UUID()
    #if FOTTY_PRIVATE_OUTAGE_DRILL
    @State private var privateBlockedSource: UUID?
    @State private var privateBlockedOrigin: String?
    @State private var privateBlockedPublisher: String?
    @State private var privateFailedAttempt: UUID?
    #endif

    let isSurfaceOnly: Bool
    let publishesLiveActivity: Bool
    var usesManagedAudio = false
    var physicalMeasurementIdentifier = "native-playback-measurement"
    private let onClose: (() -> Void)?
    private var onRetryDiscovery: (() -> Void)? = nil
    private var retryDiscoveryMessage: String? = nil
    private var onCancelRetryDiscovery: (() -> Void)? = nil
    
    init(event: AnalyticalDataEngine.EventReference, providedSessions: [StreamSession]) {
        let model = LivePlayerViewModel(event: event, providedSessions: providedSessions)
        model.configureSingleStreamRanking()
        self._viewModel = State(initialValue: model)
        self.isSurfaceOnly = false
        self.publishesLiveActivity = true
        self.onClose = nil
    }

    init(viewModel: LivePlayerViewModel, isSurfaceOnly: Bool, publishesLiveActivity: Bool, usesManagedAudio: Bool,
         physicalMeasurementIdentifier: String = "native-playback-measurement",
         onRetryDiscovery: (() -> Void)? = nil,
         retryDiscoveryMessage: String? = nil,
         onCancelRetryDiscovery: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.isSurfaceOnly = isSurfaceOnly
        self.publishesLiveActivity = publishesLiveActivity
        self.usesManagedAudio = usesManagedAudio
        self.physicalMeasurementIdentifier = physicalMeasurementIdentifier
        self.onRetryDiscovery = onRetryDiscovery
        self.retryDiscoveryMessage = retryDiscoveryMessage
        self.onCancelRetryDiscovery = onCancelRetryDiscovery
        self.onClose = onClose
    }

    #if FOTTY_PRIVATE_OUTAGE_DRILL
    private var privateBackupProvenance: String {
        guard let current = viewModel.activeSource, let original = privateBlockedPublisher,
              let origin = privateBlockedOrigin, let currentOrigin = SourceDeliveryDiversity.origin(for: current) else {
            return "unverified"
        }
        if LivePlaybackSourcePolicy.matchPublisher(for: current) == original { return "same-publisher" }
        return currentOrigin == origin ? "same-origin" : "different-publisher-and-origin"
    }

    private func signalPrivateSourceLoss(_ blocked: UUID) {
        guard AppRuntime.privateOutageFixture == viewModel.event.id, !usesManagedAudio,
              viewModel.activeSource?.id == blocked, let item = viewModel.player?.currentItem,
              privateFailedAttempt != viewModel.loadRequestID else { return }
        privateFailedAttempt = viewModel.loadRequestID
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: NSURLErrorDomain,
                code: NSURLErrorCannotDecodeContentData)])
    }
    #endif

    private func closePlayback() { if let onClose { onClose() } else { dismiss() } }
    
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

    private var sourceSelectorSheet: some View {
        let wrongMatchAction: ((UUID) -> Void)?
        if !AppRuntime.usesPrivateMatchSelection || usesManagedAudio || viewModel.event.isBroadcastChannel {
            wrongMatchAction = nil
        } else {
            let displayedAttempt = viewModel.loadRequestID
            wrongMatchAction = { sourceID in viewModel.reportWrongMatch(for: sourceID, expectedAttempt: displayedAttempt) }
        }
        return LiveStreamSelectorSheet(
            sessions: viewModel.sessions,
            currentSourceIndex: $viewModel.currentSourceIndex,
            failedSessionIDs: viewModel.failedSourceIDs,
            currentPlaybackHasError: viewModel.error != nil,
            currentPlaybackMode: viewModel.isUsingWebEmbed ? .webEmbed : .native,
            isCheckingAdditionalSources: viewModel.isCheckingAdditionalSources,
            usesSinglePlayerPresentation: !usesManagedAudio,
            viewingContext: viewModel.event.isBroadcastChannel ? .channel : .match,
            recommendedIndices: recommendedMatchIndices,
            onWrongMatch: wrongMatchAction,
            onSelect: selectBroadcastSession
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var playerContent: some View {
        Group {
            if isSurfaceOnly {
                mediaSurface(isPortrait: true)
            } else {
                GeometryReader { geometry in
                    let isPortrait = geometry.size.height > geometry.size.width
                    
                    VStack(spacing: 0) {
                        if isPortrait {
                            playerMatchHeader
                        }

                        mediaSurface(isPortrait: isPortrait)
                        .frame(height: isPortrait ? geometry.size.width * 9/16 : geometry.size.height)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("live-player")

                        if isPortrait {
                            highlightsSection
                        }
                    }
                    .background(FottyTheme.background)
                    .ignoresSafeArea(edges: isPortrait ? .bottom : .all)
                }
            }
        }
    }

    var body: some View {
        playerContent
        #if FOTTY_PRIVATE_OUTAGE_DRILL
        .overlay(alignment: .bottomLeading) {
            // Affect only the selected delivery for the duration of this private drill;
            // an ordinary same-source retry cannot silently turn a continuing outage into a pass.
            if !usesManagedAudio, viewModel.viewingPlaybackContext == .single,
               AppRuntime.privateOutageFixture == viewModel.event.id {
                Text("Recovery trace").font(.caption2)
                    .accessibilityIdentifier("private-recovery-trace")
                    .accessibilityValue(viewModel.drillRecoverySteps.joined(separator: "; "))
                if let blocked = privateBlockedSource {
                    Text(viewModel.activeSource?.id == blocked ? "Primary" : "Alternative")
                        .accessibilityIdentifier("private-match-outage-route")
                        .accessibilityValue("choices=\(viewModel.sessions.count) exhausted=\(viewModel.failedSourceIDs.count) switches=\(viewModel.autoFailoverCount) phase=\(viewModel.connectionPhase) failure=\(viewModel.lastFailureKind.rawValue) provenance=\(privateBackupProvenance)")
                } else if !viewModel.isUsingWebEmbed, viewModel.isVideoReadyForDisplay, viewModel.player?.currentItem != nil {
                    Button("Simulate source loss") {
                        guard let source = viewModel.activeSource else { return }
                        privateBlockedOrigin = SourceDeliveryDiversity.origin(for: source)
                        privateBlockedPublisher = LivePlaybackSourcePolicy.matchPublisher(for: source)
                        privateBlockedSource = source.id
                        signalPrivateSourceLoss(source.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("private-match-outage-drill")
                }
            }
        }
        .onChange(of: viewModel.isVideoReadyForDisplay) { _, ready in
            if ready, let blocked = privateBlockedSource { signalPrivateSourceLoss(blocked) }
        }
        #endif
        .persistentSystemOverlays(isSurfaceOnly ? .automatic : .hidden)
        .statusBarHidden(!isSurfaceOnly)
        // Playback is a dark cinema surface, independent of browsing appearance.
        .preferredColorScheme(isSurfaceOnly ? nil : .dark)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $viewModel.showSourceSelector) {
            sourceSelectorSheet
        }
        .onAppear {
            if !isSurfaceOnly { MatchNavigationStore.shared.livePlayerDidAppear(matchID: viewModel.event.id) }
            viewModel.startPlaybackIfNeeded()
            updateLiveActivity()
            viewModel.scheduleAutoHide()
        }
        .task(id: scenePhase == .active) {
            scoreService.updatePollingDemand(
                owner: scorePollingOwner,
                isActive: scenePhase == .active && viewModel.event.normalizedCategory == "football"
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { onCancelRetryDiscovery?() }
            viewModel.handleScenePhaseChange(newPhase)
            updateLiveActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            viewModel.refreshPlaybackControlsAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            viewModel.refreshPlaybackControlsAccessibility()
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
        .onChange(of: publishesLiveActivity) { old, new in
            if old && !new { FottyLiveActivityController.shared.end(event: viewModel.event, scoreText: liveActivityScoreText) }
            if new { updateLiveActivity() }
        }
        .onChange(of: viewModel.error) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.loadRequestID) { _, _ in onCancelRetryDiscovery?() }
        .onChange(of: viewModel.currentSourceIndex) { _, _ in updateLiveActivity() }
        .onChange(of: liveActivityScoreText) { _, _ in updateLiveActivity() }
        .onChange(of: liveActivityMatchStatus) { _, _ in updateLiveActivity() }
        .onChange(of: viewModel.isVideoReadyForDisplay) { _, ready in
            if ready, viewModel.isPlaying, !viewModel.isLoading {
                viewModel.scheduleAutoHide()
                updateLiveActivity()
            }
        }
        .onDisappear {
            scoreService.releasePolling(owner: scorePollingOwner)
            // A full-screen Details route may hide an inline host without
            // retiring its scene-owned session. Only Stop/replacement/removal
            // retires managed transport; legacy covers retain their old owner.
            if !isSurfaceOnly {
                MatchNavigationStore.shared.livePlayerDidDisappear(matchID: viewModel.event.id)
                endLiveActivity()
                viewModel.cleanup()
            }
        }
        .modifier(ViewingLegacyEdgeDismiss(enabled: !isSurfaceOnly, onClose: closePlayback))
        .background { NativeFullscreenPresenter(model: viewModel).frame(width: 0, height: 0) }
    }

    private func mediaSurface(isPortrait: Bool) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.shouldDisplayWebPlayback, let source = viewModel.activeSource {
                let attemptID = viewModel.loadRequestID
                let documentOwner = viewModel
                let managesAudio = viewModel.shouldManageWebAudio(inWatchTwo: usesManagedAudio)
                LiveWebEmbedPlayerView(
                    url: source.url,
                    referer: source.headers["Referer"] ?? source.url.absoluteString,
                    isMuted: managesAudio ? viewModel.webMute : AppRuntime.shouldMutePlaybackForTesting,
                    isSuspended: viewModel.shouldSuspendWebPlayback,
                    providerControlsAudio: !managesAudio,
                    attemptID: attemptID,
                    playbackCommand: viewModel.webPlaybackCommand,
                    nativeTransferSuspensionID: viewModel.nativeTransferSuspensionID,
                    onNativeTransferSuspensionChanged: { id, suspended in
                        viewModel.handleNativeTransferSuspensionChanged(id, suspended: suspended,
                            sourceID: source.id, requestID: attemptID)
                    },
                    webAudioRevocationID: viewModel.webAudioRevocationID,
                    onWebAudioRevocationAcknowledged: { id in
                        viewModel.handleWebAudioRevocationAcknowledged(id, sourceID: source.id, requestID: attemptID)
                    },
                    onSurfaceTapped: {
                        if viewModel.isNativePlaybackTransferInProgress { viewModel.cancelNativePlaybackTransfer() }
                        viewModel.revealWebControlsFromProviderTap()
                    },
                    onDiagnosticStage: { stage, code in
                        viewModel.recordPlaybackStage(stage, errorCode: code,
                                                      sourceID: source.id, requestID: attemptID)
                    },
                    onAudioPreparationMeasured: { milliseconds, result in
                        viewModel.recordWebAudioPreparation(durationMilliseconds: milliseconds, result: result,
                                                           sourceID: source.id, requestID: attemptID)
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
                    onPictureInPictureActiveChanged: { active in
                        viewModel.handleWebPictureInPictureActivityChanged(
                            active, sourceID: source.id, requestID: attemptID
                        )
                    },
                    onNativeCandidateDiscovered: { candidate in
                        viewModel.handleNativePlaybackCandidate(
                            candidate,
                            sourceID: source.id,
                            requestID: attemptID
                        )
                    },
                    onPlaybackRetired: {
                        documentOwner.handleWebPlaybackRetired(sourceID: source.id, requestID: attemptID)
                    },
                    onPlaybackMounted: {
                        documentOwner.handleWebPlaybackMounted(sourceID: source.id, requestID: attemptID)
                    }
                )
                // A selected source/retry owns its WebKit document and
                // callbacks. Rotation, pause and audio changes retain
                // this identity; an old page cannot navigate the new one.
                .id(attemptID)
                .ignoresSafeArea()
            } else if let player = viewModel.player {
                let nativeAttempt = viewModel.loadRequestID
                AVPlayerLayerView(
                    player: player,
                    videoGravity: viewModel.isFillMode ? .resizeAspectFill : .resizeAspect,
                    pictureInPictureRequestID: viewModel.pictureInPictureRequestID,
                    allowsPictureInPicture: viewModel.allowsViewingPiP,
                    capturesSurfaceTaps: !viewModel.showControls
                        && !viewModel.isLoading
                        && viewModel.error == nil,
                    physicalMeasurementIdentifier: physicalMeasurementIdentifier,
                    physicalMeasurementAttemptID: viewModel.loadRequestID,
                    measurementBinding: viewModel.nativeMeasurementBinding,
                    suspendsInlinePlayback: viewModel.nativeFullscreenIsPresented,
                    onSurfaceTapped: {
                        viewModel.toggleControlsFromPlaybackTap()
                    },
                    onReadyForDisplayChanged: { ready in
                        guard !viewModel.nativeFullscreenIsPresented, viewModel.loadRequestID == nativeAttempt else { return }
                        if viewModel.isVideoReadyForDisplay != ready {
                            viewModel.isVideoReadyForDisplay = ready
                        }
                    },
                    onTimeControlStatusChanged: { status in
                        guard !viewModel.nativeFullscreenIsPresented, viewModel.loadRequestID == nativeAttempt else { return }
                        viewModel.handleNativeTimeControlStatusChanged(status)
                    },
                    onPictureInPictureAvailabilityChanged: { available in
                        guard !viewModel.nativeFullscreenIsPresented, viewModel.loadRequestID == nativeAttempt else { return }
                        if viewModel.isPictureInPictureAvailable != available {
                            viewModel.handlePictureInPictureAvailabilityChanged(
                                available,
                                isBackgrounded: scenePhase == .background
                            )
                        }
                    },
                    onPictureInPictureActiveChanged: { active in
                        guard !viewModel.nativeFullscreenIsPresented, viewModel.loadRequestID == nativeAttempt else { return }
                        viewModel.handlePictureInPictureActivityChanged(
                            active,
                            isBackgrounded: scenePhase == .background
                        )
                    },
                    onPictureInPictureFailure: { message in
                        guard !viewModel.nativeFullscreenIsPresented, viewModel.loadRequestID == nativeAttempt else { return }
                        viewModel.handlePictureInPictureFailure(
                            message,
                            isBackgrounded: scenePhase == .background
                        )
                    }
                )
                .ignoresSafeArea()
            }

            if let retryDiscoveryMessage, viewModel.error != nil {
                StreamResolutionPanel(sportCategory: viewModel.event.normalizedCategory,
                    competition: SportMotionContext.competition(for: viewModel.event),
                    statusMessage: retryDiscoveryMessage, subtitle: viewModel.event.displayTitle,
                    isMultiStream: false, multiTitles: [],
                    onCancel: { onCancelRetryDiscovery?() })
            } else if let error = viewModel.error {
                PlaybackErrorOverlay(
                    title: viewModel.errorTitle,
                    message: error,
                    viewModel: viewModel,
                    sourceRecoveryButtonTitle: sourceRecoveryButtonTitle,
                    dismiss: closePlayback,
                    isCompact: isPortrait,
                    onRetry: {
                        if let onRetryDiscovery { onRetryDiscovery() }
                        else { viewModel.retryCurrentSourceExplicitly() }
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
                    webEmbedControlsLayer(
                        isPortrait: isPortrait,
                        showSources: viewModel.sessions.count > 1
                    )
                    .zIndex(100)
                } else if (viewModel.showControls || viewModel.isLoading) {
                    PlaybackControlsOverlay(
                        viewModel: viewModel,
                        showSourceButton: !isPortrait && viewModel.sessions.count > 1,
                        showsTopBar: !isPortrait,
                        dismiss: closePlayback
                    )
                }
            }
        }
    }

    private func updateLiveActivity() {
        guard publishesLiveActivity else { return }
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
        guard publishesLiveActivity else { return }
        FottyLiveActivityController.shared.end(
            event: viewModel.event,
            scoreText: liveActivityScoreText
        )
    }

    private var liveActivityScoreText: String? {
        if WatchingSpoilerProtection.shared.protects(viewModel.event) { return nil }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button { closePlayback() } label: {
                    Image(systemName: "xmark")
                        .font(.fottyScaled(size: 14, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(FottyTheme.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close player")

                if dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                } else {
                    PlayerPortraitIdentity(event: viewModel.event, status: playerStatusText)
                }

                playerMatchHeaderControls
            }

            if dynamicTypeSize.isAccessibilitySize {
                PlayerPortraitIdentity(event: viewModel.event, status: playerStatusText)
            }
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 8)
        .frame(minHeight: 66)
        .background(FottyTheme.surfaceSubtle)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FottyTheme.border).frame(height: 0.5)
        }
    }

    private var playerMatchHeaderControls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let playerScoreText {
                Text(playerScoreText)
                    .font(.fottyScaled(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .monospacedDigit()
                    .fixedSize()
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
    }

    private var playerScoreText: String? {
        if WatchingSpoilerProtection.shared.protects(viewModel.event) { return nil }
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
            let status = MatchStartPolicy.currentStatus(for: viewModel.event, scores: scoreService)
            return MatchdayEventStatePolicy.section(for: viewModel.event, status: status) == .live
                ? "Live broadcast" : "Broadcast"
        case .upcoming:
            guard let kickoff = viewModel.event.kickoffDate else { return "Upcoming broadcast" }
            return "Starts \(kickoff.formatted(date: .abbreviated, time: .shortened))"
        case .available:
            return "Broadcast available"
        }
    }

    private var recommendedMatchIndices: [Int]? {
        guard AppRuntime.usesPrivateMatchSelection, !usesManagedAudio, !viewModel.event.isBroadcastChannel else { return nil }
        var failed = viewModel.failedSourceIDs
        if viewModel.error != nil, let active = viewModel.activeSession { failed.insert(active.id) }
        return BroadcastSourcePickerPolicy.recommendations(sessions: viewModel.sessions,
            currentIndex: viewModel.currentSourceIndex, failedIDs: failed, for: viewModel.event,
            enabledProviders: LivePlaybackSourcePolicy.enabledMatchProviders)
    }

    private var broadcastSourcesSection: some View {
        let indices = recommendedMatchIndices ?? Array(viewModel.sessions.indices)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Broadcast sources")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                Spacer()
                Text("\(indices.count)")
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
                ForEach(indices, id: \.self) { index in
                    let session = viewModel.sessions[index]
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

                if indices.isEmpty {
                    emptyBroadcastState
                }
                if !usesManagedAudio, !viewModel.event.isBroadcastChannel, indices.count < viewModel.sessions.count {
                    Button("Browse sources") { viewModel.showSourceSelector = true }
                        .frame(minHeight: 44)
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
        Button { closePlayback() } label: {
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

    /// Keep web playback chrome above the provider without placing it inside a
    /// hit-testing-disabled ancestor. The layout containers are transparent, so
    /// only the visible buttons intercept touches and the rest of the provider
    /// surface remains directly interactive.
    private func webEmbedControlsLayer(isPortrait: Bool, showSources: Bool) -> some View {
        VStack {
            HStack(alignment: .top) {
                if !isPortrait {
                    webCloseButton
                }

                Spacer(minLength: 8)

                WebEmbedToolbarView(
                    isPlaying: viewModel.isPlaying,
                    showSources: showSources,
                    onTogglePlayPause: {
                        viewModel.togglePlayPause()
                    },
                    onShowSources: {
                        viewModel.showSourceSelector = true
                        viewModel.scheduleAutoHide()
                    }
                )
                .frame(minHeight: 44)
            }
            .padding(isPortrait ? 8 : 12)

            Spacer(minLength: 0)
        }
    }
}
