import XCTest
import CoreGraphics
@testable import Fotty

final class ViewingPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFullMatchdayIsTheDefaultAndTheOptionalWindowIsTimeNeutral() {
        XCTAssertEqual(MatchdayViewMode.defaultMode, .fullMatchday)
        XCTAssertEqual(MatchdayViewMode.allCases, [.fullMatchday, .timeWindow])
        XCTAssertEqual(MatchdayViewMode.allCases.map(\.title), ["Full Matchday", "Time window"])
        XCTAssertEqual(ViewingPlanDuration.evening.rawValue, "evening",
                       "A clearer label must not migrate or invalidate existing local/synced duration choices")
        XCTAssertEqual(ViewingPlanDuration.evening.title, "Until midnight")
    }

    private func candidate(_ id: String, phase: ViewingPlanPolicy.Phase = .upcoming,
                           after seconds: TimeInterval? = 600, channel: Bool = false,
                           conflict: Bool = false) -> ViewingPlanPolicy.Candidate {
        .init(id: id, start: seconds.map { now.addingTimeInterval($0) }, phase: phase,
              isChannel: channel, hasIdentityConflict: conflict)
    }

    private func project(_ candidates: [ViewingPlanPolicy.Candidate],
                         duration: ViewingPlanDuration = .twoHours,
                         at date: Date? = nil) -> ViewingPlanPolicy.Projection {
        ViewingPlanPolicy.project(candidates, duration: duration, windowStart: now, at: date ?? now)
    }

    func testWindowUsesAvailableTimeWithoutEstimatingMatchFinish() {
        let candidates = [candidate("ongoing-test", phase: .live, after: -2 * 86_400),
                          candidate("later", after: 100 * 60), candidate("soon", after: 45 * 60)]
        XCTAssertEqual(project(candidates, duration: .ninetyMinutes).currentIDs, ["ongoing-test"])
        XCTAssertEqual(project(candidates, duration: .ninetyMinutes).upcomingIDs, ["soon"])
        XCTAssertEqual(project(candidates).upcomingIDs, ["soon", "later"])
        XCTAssertEqual(project(candidates).windowEnd, now.addingTimeInterval(2 * 3_600))
        XCTAssertEqual(candidates.first?.start, now.addingTimeInterval(-2 * 86_400),
                       "Planning must never manufacture a fixture duration or alter its source facts")
    }

    func testAdmissionKeepsListedSeparateFromLiveAndRejectsUncertainOrChannelRows() {
        let rows = [candidate("listed", phase: .listed, after: -120),
                    candidate("live", phase: .live, after: -60),
                    candidate("channel", phase: .live, after: nil, channel: true),
                    candidate("unknown", after: nil),
                    candidate("finished", phase: .excluded, after: -600),
                    candidate("postponed", phase: .excluded),
                    candidate("conflict", conflict: true),
                    candidate("future-listed", phase: .listed, after: 60)]
        let result = project(rows)
        XCTAssertEqual(result.currentIDs, ["live", "listed"])
        XCTAssertTrue(result.upcomingIDs.isEmpty)
        XCTAssertEqual(rows[0].phase, .listed, "A viewing plan cannot promote a listed start into live evidence")
    }

    func testWindowBoundaryIsExclusiveAndElapsedScheduledRowsAreNotInferredLive() {
        let result = project([candidate("elapsed", after: -1), candidate("exact-now", after: 0),
                              candidate("inside", after: 7_199), candidate("end", after: 7_200),
                              candidate("outside", after: 7_201)])
        XCTAssertEqual(result.upcomingIDs, ["inside"])
        XCTAssertTrue(result.currentIDs.isEmpty)
    }

    func testEndedWindowDoesNotSlideForwardWithoutAnExplicitNewStart() {
        let rows = [candidate("live", phase: .live, after: -60), candidate("later", after: 8_000)]
        let ended = project(rows, at: now.addingTimeInterval(7_200))
        XCTAssertTrue(ended.hasEnded)
        XCTAssertEqual(ended.count, 0)
        XCTAssertEqual(ended.windowStart, now)
        XCTAssertEqual(ended.windowEnd, now.addingTimeInterval(7_200))
        let restarted = ViewingPlanPolicy.project(rows, duration: .twoHours,
            windowStart: now.addingTimeInterval(7_200), at: now.addingTimeInterval(7_200))
        XCTAssertFalse(restarted.hasEnded)
        XCTAssertEqual(restarted.upcomingIDs, ["later"])
    }

    func testDuplicateFactsDeduplicateButConflictingSameIDIsNotGuessed() {
        let same = candidate("same")
        let result = project([same, same, candidate("conflicting", after: 10),
                              candidate("conflicting", after: 20), candidate("", after: 30)])
        XCTAssertEqual(result.upcomingIDs, ["same"])
    }

    func testClockCorrectionDoesNotAdmitAStartBeforeTheSelectedWindow() {
        let rows = [candidate("before-window", after: -60), candidate("inside-window", after: 60)]
        let result = project(rows, at: now.addingTimeInterval(-120))
        XCTAssertEqual(result.upcomingIDs, ["inside-window"])
    }

    func testFixedAvailableTimeMayCrossMidnightWithoutInventingFixtureDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Port_of_Spain"))
        let start = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 12, hour: 23, minute: 30)))
        let tomorrow = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 13, hour: 0, minute: 30)))
        let end = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 13, hour: 1)))
        let result = ViewingPlanPolicy.project([
            .init(id: "inside", start: tomorrow, phase: .upcoming),
            .init(id: "outside", start: end, phase: .upcoming)
        ], duration: .ninetyMinutes, windowStart: start, at: start, calendar: calendar)
        XCTAssertEqual(result.windowEnd, end)
        XCTAssertEqual(result.upcomingIDs, ["inside"])
    }

    func testStableSortingAndTerminalOrRescheduleUpdatesFollowCurrentFacts() {
        let old = candidate("saved", after: 60)
        XCTAssertEqual(project([old, candidate("b", after: 120), candidate("a", after: 120)]).upcomingIDs,
                       ["saved", "a", "b"])
        XCTAssertTrue(project([candidate("saved", phase: .excluded, after: 60)]).upcomingIDs.isEmpty)
        XCTAssertTrue(project([candidate("saved", after: 8_000)]).upcomingIDs.isEmpty)
        XCTAssertEqual(project([candidate("saved", after: 300)]).upcomingIDs, ["saved"])
    }

    func testAllEveningEndsAtLocalMidnightAcrossDSTAndDoesNotAdmitTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 11, day: 1, hour: 0, minute: 30)))
        let nextMidnight = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 11, day: 2)))
        let end = ViewingPlanDuration.evening.endDate(from: start, calendar: calendar)
        XCTAssertEqual(end, nextMidnight)
        XCTAssertEqual(end.timeIntervalSince(start), 24.5 * 3_600,
                       "All evening is a local-calendar boundary, not a fixed 24-hour fixture estimate")
        let rows: [ViewingPlanPolicy.Candidate] = [
            .init(id: "tonight", start: end.addingTimeInterval(-60), phase: .upcoming),
            .init(id: "tomorrow", start: end, phase: .upcoming)
        ]
        let result = ViewingPlanPolicy.project(rows, duration: .evening, windowStart: start, at: start, calendar: calendar)
        XCTAssertEqual(result.upcomingIDs, ["tonight"])
    }

    func testUnknownSavedDurationFallsBackWithoutAffectingFixtures() {
        XCTAssertEqual(ViewingPlanDuration.saved("retired-choice"), .twoHours)
        XCTAssertEqual(ViewingPlanDuration.allCases.map(\.title), ["90 min", "2 hours", "Until midnight"])
    }
}

/// Pure layout-policy evidence, not a rendered iPad or decoded-playback pass.
/// Inputs are the usable video stage after safe areas and controls are removed.
@MainActor
final class ViewingExperienceLayoutTests: XCTestCase {
    private let aspect: CGFloat = 16.0 / 9.0

    func testVideoFirstCompositionIsOnlyForSinglePlayerOnIPad() {
        XCTAssertTrue(ViewingExperienceLayout.usesVideoFirstSinglePlayer(isPad: true, isTwo: false))
        XCTAssertFalse(ViewingExperienceLayout.usesVideoFirstSinglePlayer(isPad: false, isTwo: false),
                       "The tablet presentation must not replace the existing phone branch")
        XCTAssertFalse(ViewingExperienceLayout.usesVideoFirstSinglePlayer(isPad: true, isTwo: true),
                       "Single-player polish must not select a different two-player layout")
        XCTAssertFalse(ViewingExperienceLayout.usesVideoFirstSinglePlayer(isPad: false, isTwo: true))
    }

    func testOrdinaryTabletWidthsUseTheWholeStageWithoutReservingACompanionRail() {
        for width: CGFloat in [819, 820, 1024, 1180] {
            let available = CGSize(width: width, height: 700)
            let video = ViewingExperienceLayout.singleVideoSize(in: available)
            XCTAssertEqual(video.width, width, accuracy: 0.001,
                           "An unrequested companion must not take video width at \(width) points")
            XCTAssertEqual(video.height, width / aspect, accuracy: 0.001)
            assertFits(video, in: available)
        }
    }

    func testCrossingTheOld820PointBreakpointCannotShrinkTheVideo() {
        let before = ViewingExperienceLayout.singleVideoSize(in: CGSize(width: 819, height: 700))
        let after = ViewingExperienceLayout.singleVideoSize(in: CGSize(width: 820, height: 700))
        XCTAssertEqual(after.width - before.width, 1, accuracy: 0.001)
        XCTAssertEqual(after.height - before.height, 1 / aspect, accuracy: 0.001)
        XCTAssertGreaterThan(after.width * after.height, before.width * before.height,
                             "A one-point window expansion must not trigger the old sidebar area loss")
    }

    func testPortraitAndNarrowTabletWindowsKeepAnUncroppedWidthFittedVideo() {
        for available in [CGSize(width: 820, height: 1180), CGSize(width: 768, height: 1024),
                          CGSize(width: 600, height: 900), CGSize(width: 390, height: 700),
                          CGSize(width: 320, height: 600)] {
            let video = ViewingExperienceLayout.singleVideoSize(in: available)
            XCTAssertEqual(video.width, available.width, accuracy: 0.001)
            XCTAssertEqual(video.height, available.width / aspect, accuracy: 0.001)
            assertFits(video, in: available)
        }
    }

    func testShortLandscapeWindowsFitHeightInsteadOfPushingVideoBelowTheViewport() {
        for available in [CGSize(width: 1180, height: 320), CGSize(width: 1024, height: 300),
                          CGSize(width: 820, height: 250), CGSize(width: 600, height: 200)] {
            let video = ViewingExperienceLayout.singleVideoSize(in: available)
            XCTAssertEqual(video.height, available.height, accuracy: 0.001)
            XCTAssertEqual(video.width, available.height * aspect, accuracy: 0.001)
            assertFits(video, in: available)
        }
    }

    func testReservedControlSpaceReducesVideoStageWithoutOverflowOrAspectDistortion() {
        let taller = ViewingExperienceLayout.singleVideoSize(in: CGSize(width: 1180, height: 600))
        let shorter = ViewingExperienceLayout.singleVideoSize(in: CGSize(width: 1180, height: 440))
        XCTAssertEqual(taller.height, 600, accuracy: 0.001)
        XCTAssertEqual(shorter.height, 440, accuracy: 0.001)
        XCTAssertLessThan(shorter.width, taller.width,
                          "Additional readable controls must be accommodated, not drawn over the video")
        assertFits(shorter, in: CGSize(width: 1180, height: 440))
    }

    func testZeroNegativeAndNonFiniteStagesDoNotPublishInvalidSurfaceGeometry() {
        for available in [CGSize.zero, CGSize(width: 0, height: 700), CGSize(width: 820, height: 0),
                          CGSize(width: -1, height: 700), CGSize(width: 820, height: -1),
                          CGSize(width: CGFloat.nan, height: 700), CGSize(width: 820, height: CGFloat.nan),
                          CGSize(width: CGFloat.infinity, height: 700), CGSize(width: 820, height: CGFloat.infinity),
                          CGSize(width: -CGFloat.infinity, height: 700)] {
            XCTAssertEqual(ViewingExperienceLayout.singleVideoSize(in: available), .zero,
                           "Transient invalid window sizes must not poison retained-surface bounds")
        }
    }

    func testLargeFiniteStageStillProducesFiniteAspectFitBounds() {
        let available = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let video = ViewingExperienceLayout.singleVideoSize(in: available)
        XCTAssertTrue(video.width.isFinite)
        XCTAssertTrue(video.height.isFinite)
        XCTAssertGreaterThan(video.width, 0)
        XCTAssertGreaterThan(video.height, 0)
        XCTAssertLessThanOrEqual(video.width, available.width)
        XCTAssertLessThanOrEqual(video.height, available.height)
        XCTAssertEqual(video.width / video.height, aspect, accuracy: 0.000_001)
    }

    func testLegacyCompanionPolicyRemainsAvailableToTheUnchangedPhoneBranch() {
        XCTAssertFalse(ViewingExperienceLayout.usesCompanion(width: 819, accessibility: false))
        XCTAssertTrue(ViewingExperienceLayout.usesCompanion(width: 820, accessibility: false))
        XCTAssertTrue(ViewingExperienceLayout.usesCompanion(width: 1180, accessibility: false))
        XCTAssertFalse(ViewingExperienceLayout.usesCompanion(width: 1180, accessibility: true))
    }

    private func assertFits(_ video: CGSize, in available: CGSize,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(video.width.isFinite && video.height.isFinite, file: file, line: line)
        XCTAssertGreaterThan(video.width, 0, file: file, line: line)
        XCTAssertGreaterThan(video.height, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(video.width, available.width + 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(video.height, available.height + 0.001, file: file, line: line)
        XCTAssertEqual(video.width / video.height, aspect, accuracy: 0.000_001, file: file, line: line)
        XCTAssertTrue(abs(video.width - available.width) < 0.001 || abs(video.height - available.height) < 0.001,
                      "Aspect fit should use the largest available rectangle", file: file, line: line)
    }
}
