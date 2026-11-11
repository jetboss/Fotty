import XCTest

@testable import Fotty

final class InlineCricketMotionTests: XCTestCase {
    func testCricketStaysWithinTheApprovedGentleMotionEnvelope() {
        var maximumLift = 0.0
        for frame in 0...720 {
            let pose = SportMotionPose(style: .cricket, elapsed: Double(frame) / 30, animated: true)
            XCTAssertLessThanOrEqual(abs(pose.x), 6.001, "The ball should stay close to its loading label")
            XCTAssertTrue((0...16.001).contains(pose.lift))
            XCTAssertLessThanOrEqual(abs(pose.rotation), 12.001, "Seams should rock rather than spin")
            XCTAssertTrue((0...0.04001).contains(pose.squash))
            maximumLift = max(maximumLift, Double(pose.lift))
        }
        XCTAssertGreaterThan(maximumLift, 15, "The bounded animation must still have a visible bounce")
    }

    func testCricketPoseJoinsWithoutASeamJumpAtTheLoopBoundary() {
        let step = 0.0001
        let before = SportMotionPose(style: .cricket, elapsed: SportMotionPose.duration - step, animated: true)
        let start = SportMotionPose(style: .cricket, elapsed: 0, animated: true)
        let after = SportMotionPose(style: .cricket, elapsed: step, animated: true)

        XCTAssertEqual(before.x, after.x, accuracy: 0.01)
        XCTAssertEqual(before.lift, after.lift, accuracy: 0.001)
        XCTAssertEqual(before.squash, after.squash, accuracy: 0.001)
        XCTAssertEqual(before.rotation, after.rotation, accuracy: 0.01)
        XCTAssertLessThan(abs(Double(before.lift - start.lift)) / step, 0.1,
                          "Landing should ease into contact rather than snap vertically")
        XCTAssertLessThan(abs(Double(after.lift - start.lift)) / step, 0.1)
    }

    func testCricketRemainsStillForEveryMotionSuppressionReason() {
        for reason in [(true, false, true), (false, true, true), (false, false, false)] {
            let animated = FottyMotionPolicy.allowsContinuousMotion(
                reduceMotion: reason.0, lowPowerMode: reason.1, sceneIsActive: reason.2
            )
            XCTAssertFalse(animated)
            for time in [0.0, 0.6, 1.8, 120] {
                let pose = SportMotionPose(style: .cricket, elapsed: time, animated: animated)
                XCTAssertEqual(pose.x, 0)
                XCTAssertEqual(pose.lift, 0)
                XCTAssertEqual(pose.rotation, 0)
                XCTAssertEqual(pose.squash, 0)
                XCTAssertEqual(pose.phase, 0)
            }
        }
    }
}

@MainActor
final class InlineSportMotionTests: XCTestCase {
    func testSpecificSportsAndAliasPrecedenceKeepTheirOwnEquipment() {
        let aliases: [(SportMotionStyle, [String])] = [
            (.tableTennis, ["table-tennis", "table tennis", "table_tennis", "ping pong", "ping-pong", "ping_pong"]),
            (.tennis, ["tennis", "Tennis", "ATP", "WTA"]),
            (.golf, ["golf", "PGA"]),
            (.darts, ["darts", "dart"]),
            (.volleyball, ["volleyball"]),
            (.handball, ["handball"]),
            (.lacrosse, ["lacrosse"]),
            (.cycling, ["cycling"]),
            (.americanFootball, ["american-football", "american_football", "NFL"]),
            (.motorsport, ["formula1", "formula-1", "formula_1", "Formula 1", "F1", "motor-sports"]),
            (.combat, ["ufc", "pfl", "bellator", "one"]),
            (.multiSport, ["all-sports", "all_sports", "all", ""])
        ]
        for (expected, values) in aliases {
            for value in values {
                let profile = SportMotionProfile.profile(for: value)
                XCTAssertEqual(profile.style, expected, value)
                XCTAssertFalse(profile.symbol.isEmpty, value)
                XCTAssertFalse(profile.displayName.isEmpty, value)
            }
        }
        for value in ["college", "college-sports", "other", "unlisted-sport"] {
            XCTAssertEqual(SportMotionProfile.profile(for: value).style, .generic,
                           "Unknown categories must not borrow another sport's equipment: \(value)")
        }
        for value in ["ping-pong", "ping_pong", "table_tennis"] {
            XCTAssertEqual(SportIdentity.artwork(for: value), "🏓")
            XCTAssertEqual(SportIdentity.symbol(for: value), "figure.table.tennis")
        }
        for value in ["formula1", "formula-1", "formula_1"] {
            XCTAssertEqual(SportIdentity.artwork(for: value), "🏎️")
            XCTAssertEqual(SportIdentity.symbol(for: value), "flag.checkered")
        }
    }

    func testAllSportPosesStayWithinTheInlineMotionEnvelopeAcrossRepeatedLoops() {
        XCTAssertEqual(SportMotionPose.duration, 2.4, accuracy: 0.00001)
        for style in SportMotionStyle.allCases {
            for sample in 0...720 {
                let pose = SportMotionPose(style: style, elapsed: Double(sample) / 60, animated: true)
                let context = "\(style.rawValue), sample \(sample)"
                XCTAssertLessThanOrEqual(abs(pose.x), 18.001, context)
                XCTAssertTrue((0...20.001).contains(pose.lift), context)
                XCTAssertTrue((0...0.05001).contains(pose.squash), context)
                XCTAssertTrue(pose.rotation.isFinite, context)
                XCTAssertTrue((0..<1).contains(pose.phase), context)
            }
        }
    }

    func testEverySportLoopJoinsIncludingWholeTurnRotations() {
        func angleDistance(_ first: Double, _ second: Double) -> Double {
            let delta = abs(first - second).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta)
        }
        for style in SportMotionStyle.allCases {
            let epsilon = 0.0001
            let before = SportMotionPose(style: style, elapsed: SportMotionPose.duration - epsilon, animated: true)
            let after = SportMotionPose(style: style, elapsed: epsilon, animated: true)
            XCTAssertEqual(before.x, after.x, accuracy: 0.02, style.rawValue)
            XCTAssertEqual(before.lift, after.lift, accuracy: 0.02, style.rawValue)
            XCTAssertEqual(before.squash, after.squash, accuracy: 0.001, style.rawValue)
            XCTAssertLessThan(angleDistance(before.rotation, after.rotation), 0.1, style.rawValue)
            for time in [0.0, 0.3, 0.6, 1.2, 1.8] {
                let first = SportMotionPose(style: style, elapsed: time, animated: true)
                let next = SportMotionPose(style: style, elapsed: time + SportMotionPose.duration, animated: true)
                XCTAssertEqual(first.x, next.x, accuracy: 0.00001, style.rawValue)
                XCTAssertEqual(first.lift, next.lift, accuracy: 0.00001, style.rawValue)
                XCTAssertEqual(first.squash, next.squash, accuracy: 0.00001, style.rawValue)
                XCTAssertLessThan(angleDistance(first.rotation, next.rotation), 0.0001, style.rawValue)
            }
        }
    }

    func testAllSportsStayStillForEveryAccessibilityPowerAndLifecycleSuppression() {
        for reduceMotion in [false, true] {
            for lowPower in [false, true] {
                for active in [false, true] {
                    let animated = FottyMotionPolicy.allowsContinuousMotion(
                        reduceMotion: reduceMotion, lowPowerMode: lowPower, sceneIsActive: active)
                    guard !animated else { continue }
                    for style in SportMotionStyle.allCases {
                        for time in [0.0, 0.6, 1.8, 120.0] {
                            let pose = SportMotionPose(style: style, elapsed: time, animated: animated)
                            XCTAssertEqual(pose.x, 0, style.rawValue)
                            XCTAssertEqual(pose.lift, 0, style.rawValue)
                            XCTAssertEqual(pose.rotation, 0, style.rawValue)
                            XCTAssertEqual(pose.squash, 0, style.rawValue)
                            XCTAssertEqual(pose.phase, 0, style.rawValue)
                        }
                    }
                }
            }
        }
    }

    func testNonFiniteAndNegativeTimeCannotProduceInvalidDrawingCoordinates() {
        for style in SportMotionStyle.allCases {
            for time in [Double.nan, .infinity, -.infinity, -120] {
                let pose = SportMotionPose(style: style, elapsed: time, animated: true)
                XCTAssertTrue(pose.x.isFinite, style.rawValue)
                XCTAssertTrue(pose.lift.isFinite, style.rawValue)
                XCTAssertTrue(pose.rotation.isFinite, style.rawValue)
                XCTAssertTrue(pose.squash.isFinite, style.rawValue)
                XCTAssertEqual(pose.phase, 0, style.rawValue)
            }
        }
    }
}
