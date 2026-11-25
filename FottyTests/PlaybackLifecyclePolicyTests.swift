import XCTest
@testable import Fotty

/// Player shrink slice 5: background and foreground decisions, pinned to the
/// inline rules they replace.
final class PlaybackLifecyclePolicyTests: XCTestCase {
    private func pip(allows: Bool = true, active: Bool = false, available: Bool = true, web: Bool = false,
                     playing: Bool = true, error: Bool = false, backgrounded: Bool = false,
                     item: Bool = true, age: TimeInterval? = nil) -> PlaybackLifecyclePolicy.PictureInPictureInputs {
        .init(allowsViewingPiP: allows, isPictureInPictureActive: active, isPictureInPictureAvailable: available,
              isUsingWebEmbed: web, isPlaying: playing, hasError: error, isAppBackgrounded: backgrounded,
              hasCurrentItem: item, secondsSincePictureInPictureRequest: age)
    }

    func testPictureInPictureKeepAliveRules() {
        let keeps = PlaybackLifecyclePolicy.keepsPlaybackAliveForPictureInPicture
        XCTAssertFalse(keeps(pip(allows: false, active: true)), "PiP not allowed in this viewing context")
        XCTAssertTrue(keeps(pip(active: true, available: false, web: true, playing: false, error: true)),
                      "Active PiP always keeps playback alive")
        XCTAssertFalse(keeps(pip(available: false, backgrounded: true)))
        XCTAssertFalse(keeps(pip(web: true, backgrounded: true)))
        XCTAssertFalse(keeps(pip(playing: false, backgrounded: true)))
        XCTAssertFalse(keeps(pip(error: true, backgrounded: true)))
        XCTAssertTrue(keeps(pip(backgrounded: true)), "Background before AVKit's PiP callback")
        XCTAssertFalse(keeps(pip(backgrounded: true, item: false)))
        XCTAssertFalse(keeps(pip()), "Foreground without a PiP request")
        XCTAssertTrue(keeps(pip(age: 9.9)))
        XCTAssertFalse(keeps(pip(age: 10)), "The request window is strictly under 10 s")
        XCTAssertEqual(PlaybackLifecyclePolicy.pictureInPictureRequestWindow, 10)
    }

    func testWebBackgroundAction() {
        let action = PlaybackLifecyclePolicy.webBackgroundAction
        XCTAssertEqual(action(true, true), .keepPictureInPicture)
        XCTAssertEqual(action(true, false), .keepPictureInPicture)
        XCTAssertEqual(action(false, true), .suspendAfterGrace)
        XCTAssertEqual(action(false, false), .suspendNow)
    }

    func testNativeResumeAfterForeground() {
        let resumes = PlaybackLifecyclePolicy.resumesNativeAfterForeground
        XCTAssertFalse(resumes(false, true, true, true, true), "Pause always wins")
        XCTAssertFalse(resumes(true, false, false, false, false))
        XCTAssertTrue(resumes(true, true, false, false, false))
        XCTAssertTrue(resumes(true, false, true, false, false))
        XCTAssertTrue(resumes(true, false, false, true, false))
        XCTAssertTrue(resumes(true, false, false, false, true))
    }
}
