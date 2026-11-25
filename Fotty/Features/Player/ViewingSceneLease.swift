import SwiftUI
import UIKit

/// Scene lifetime is different from a view's visibility. Details covers,
/// backgrounding and temporary marker removal must not retire live transport.
/// A bound lease stays observed until its own scene disconnects, even if UIKit
/// removes the marker before delivering that final scene notification.
@MainActor
final class ViewingSceneLease {
    private(set) var sessionID: String?
    private(set) var isStopped = false
    private let notificationCenter: NotificationCenter
    private let sceneIdentity: @MainActor (Notification) -> String?
    private var onStop: (@MainActor () -> Void)?
    private var disconnectObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default,
         sceneIdentity: @escaping @MainActor (Notification) -> String? = {
             ($0.object as? UIScene)?.session.persistentIdentifier
         },
         onStop: @escaping @MainActor () -> Void) {
        self.notificationCenter = notificationCenter
        self.sceneIdentity = sceneIdentity
        self.onStop = onStop
    }

    /// Bind only to the actual marker's window scene, never to the app's first
    /// connected/active scene. A lease cannot silently move to another window.
    @discardableResult
    func bind(sessionID: String) -> Bool {
        guard !isStopped, !sessionID.isEmpty else { return false }
        if let current = self.sessionID { return current == sessionID }
        self.sessionID = sessionID
        // Deliberate bounded retention: the scene's observer owns the lease
        // through marker removal. stop() unregisters it and releases onStop.
        // There is no observer/retention before a real scene is bound.
        disconnectObserver = notificationCenter.addObserver(
            forName: UIScene.didDisconnectNotification, object: nil, queue: .main
        ) { [self] notification in
            // NotificationCenter's .main operation queue owns this delivery.
            MainActor.assumeIsolated {
                guard let disconnectedID = sceneIdentity(notification),
                      disconnectedID == self.sessionID else { return }
                stop()
            }
        }
        return true
    }

    /// Terminal lease disposal is idempotent. Ordinary Stop watching belongs
    /// to the viewing coordinator; it must not disable this scene's lease for
    /// the next match opened in the same window.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        if let disconnectObserver {
            notificationCenter.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }
        let callback = onStop
        onStop = nil
        callback?()
    }
}

/// Attach once to the root viewing shell's background. This transparent,
/// noninteractive UIKit marker discovers the owning window scene; detaching
/// it for a cover is not a signal to stop the scene-owned viewing coordinator.
@MainActor
struct ViewingSceneLeaseMarker: UIViewRepresentable {
    let onSceneDisconnect: @MainActor () -> Void

    func makeCoordinator() -> ViewingSceneLease {
        ViewingSceneLease(onStop: onSceneDisconnect)
    }

    func makeUIView(context: Context) -> SceneMarkerView {
        SceneMarkerView(lease: context.coordinator)
    }

    func updateUIView(_ uiView: SceneMarkerView, context: Context) {
        uiView.bindOwningSceneIfAvailable()
    }

    // No dismantleUIView stop: UIKit can remove a view before disconnecting its
    // scene, or hide it while presenting Details. The bound observer owns cleanup.
    final class SceneMarkerView: UIView {
        private let lease: ViewingSceneLease

        init(lease: ViewingSceneLease) {
            self.lease = lease
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            bindOwningSceneIfAvailable()
        }

        func bindOwningSceneIfAvailable() {
            guard let scene = window?.windowScene else { return }
            lease.bind(sessionID: scene.session.persistentIdentifier)
        }
    }
}
