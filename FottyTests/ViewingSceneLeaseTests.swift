import XCTest
import UIKit
@testable import Fotty

/// Isolated notifications exercise scene ownership without selecting,
/// disconnecting, backgrounding or manipulating any real device/window.
@MainActor
final class ViewingSceneLeaseTests: XCTestCase {
    func testMatchingSceneDisconnectStopsExactlyOnce() {
        let center = NotificationCenter()
        var stops = 0
        let lease = makeLease(center: center) { stops += 1 }
        XCTAssertTrue(lease.bind(sessionID: "owner-scene"))
        defer { lease.stop() }

        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        lease.stop()
        XCTAssertTrue(lease.isStopped)
        XCTAssertEqual(stops, 1)
    }

    func testDifferentSceneAndUnknownNotificationObjectsCannotStopOwner() {
        let center = NotificationCenter()
        var stops = 0
        let lease = makeLease(center: center) { stops += 1 }
        lease.bind(sessionID: "owner-scene")
        defer { lease.stop() }

        center.post(name: UIScene.didDisconnectNotification, object: "another-scene")
        center.post(name: UIScene.didDisconnectNotification, object: nil)
        center.post(name: UIScene.didDisconnectNotification, object: NSObject())
        XCTAssertEqual(stops, 0)
        XCTAssertFalse(lease.isStopped)
        XCTAssertEqual(lease.sessionID, "owner-scene")
    }

    func testBackgroundInactiveAndMarkerRemovalAreNotSceneDisposal() {
        let center = NotificationCenter()
        var stops = 0
        let lease = makeLease(center: center) { stops += 1 }
        lease.bind(sessionID: "owner-scene")
        defer { lease.stop() }

        center.post(name: UIScene.didEnterBackgroundNotification, object: "owner-scene")
        center.post(name: UIScene.willDeactivateNotification, object: "owner-scene")
        let marker = ViewingSceneLeaseMarker.SceneMarkerView(lease: lease)
        let container = UIView()
        container.addSubview(marker)
        marker.removeFromSuperview()
        marker.didMoveToWindow()
        XCTAssertFalse(marker.isUserInteractionEnabled)
        XCTAssertTrue(marker.accessibilityElementsHidden)
        XCTAssertEqual(stops, 0)
        XCTAssertFalse(lease.isStopped)

        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        XCTAssertEqual(stops, 1, "A cover/removal does not unregister genuine scene teardown")
    }

    func testLeaseCannotRebindToAnotherScenesIdentity() {
        let center = NotificationCenter()
        var stops = 0
        let lease = makeLease(center: center) { stops += 1 }
        defer { lease.stop() }
        XCTAssertFalse(lease.bind(sessionID: ""))
        XCTAssertNil(lease.sessionID)
        XCTAssertTrue(lease.bind(sessionID: "owner-scene"))
        XCTAssertTrue(lease.bind(sessionID: "owner-scene"))
        XCTAssertFalse(lease.bind(sessionID: "another-scene"))
        center.post(name: UIScene.didDisconnectNotification, object: "another-scene")
        XCTAssertEqual(stops, 0)
        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(lease.bind(sessionID: "owner-scene"))
    }

    func testObserverRetainsBoundLeaseThroughMarkerLifetimeButStopRemainsOneShot() {
        let center = NotificationCenter()
        var stops = 0
        weak var retainedLease: ViewingSceneLease?
        do {
            let lease = makeLease(center: center) { stops += 1 }
            lease.bind(sessionID: "owner-scene")
            retainedLease = lease
        }
        XCTAssertNotNil(retainedLease, "Scene teardown must still reach the owner after the marker is removed")
        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        XCTAssertEqual(stops, 1)
        XCTAssertTrue(retainedLease?.isStopped ?? true)
    }

    func testExplicitTerminalLeaseStopIsIdempotentAndUnregistersNotification() {
        let center = NotificationCenter()
        var stops = 0
        let lease = makeLease(center: center) { stops += 1 }
        lease.bind(sessionID: "owner-scene")
        lease.stop()
        lease.stop()
        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        XCTAssertEqual(stops, 1)
    }

    func testUnboundLeaseDoesNotObserveOrRetainAStopCallback() {
        let center = NotificationCenter()
        var stops = 0
        weak var releasedLease: ViewingSceneLease?
        do {
            let lease = makeLease(center: center) { stops += 1 }
            releasedLease = lease
            center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
            XCTAssertEqual(stops, 0)
        }
        XCTAssertNil(releasedLease)
        XCTAssertEqual(stops, 0)
    }

    func testProductionNotificationAdapterRejectsNonSceneObjects() {
        let center = NotificationCenter()
        var stops = 0
        let lease = ViewingSceneLease(notificationCenter: center) { stops += 1 }
        lease.bind(sessionID: "owner-scene")
        defer { lease.stop() }
        center.post(name: UIScene.didDisconnectNotification, object: "owner-scene")
        XCTAssertEqual(stops, 0, "Production must use the affected UIScene, not arbitrary notification data")
    }

    private func makeLease(center: NotificationCenter, onStop: @escaping @MainActor () -> Void) -> ViewingSceneLease {
        ViewingSceneLease(notificationCenter: center, sceneIdentity: { $0.object as? String }, onStop: onStop)
    }
}
