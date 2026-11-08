import XCTest
@testable import Fotty

final class StreamVixTimingPolicyTests: XCTestCase {
    func testObservedChelseaClockRetainsOriginalGMTFactAndRecognizesOnlyReviewedDerivedTime() throws {
        let original = try XCTUnwrap(StreamVixTimingPolicy.originalKickoff(
            dayHeader: "Saturday 24th October 2026 - Schedule Time UK GMT", clock: "16:30"))
        XCTAssertEqual(original, utc("2026-10-24T16:30:00Z"))
        XCTAssertEqual(StreamVixTimingPolicy.legacyRomeInterpretation(of: original), utc("2026-10-24T14:30:00Z"))
        XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: utc("2026-10-24T14:30:00Z"), original: original))
        XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: original, original: original),
                      "An upstream correction must not need the legacy conversion")
    }

    func testRomeOffsetChangesAcrossOctoberDSTBoundaryRatherThanApplyingFixedTwoHours() throws {
        let before = try XCTUnwrap(StreamVixTimingPolicy.originalKickoff(
            dayHeader: "Saturday 24th Oct 2026 - Schedule Time UK GMT", clock: "16:30"))
        let after = try XCTUnwrap(StreamVixTimingPolicy.originalKickoff(
            dayHeader: "Sunday 25th October 2026 - Schedule Time UK GMT", clock: "16:30"))
        XCTAssertEqual(StreamVixTimingPolicy.legacyRomeInterpretation(of: before), utc("2026-10-24T14:30:00Z"))
        XCTAssertEqual(StreamVixTimingPolicy.legacyRomeInterpretation(of: after), utc("2026-10-25T15:30:00Z"))
        XCTAssertFalse(StreamVixTimingPolicy.corroborates(derived: utc("2026-10-25T14:30:00Z"), original: after))
        XCTAssertFalse(StreamVixTimingPolicy.corroborates(derived: utc("2026-10-24T15:30:00Z"), original: before))
    }

    func testAutumnRepeatedRomeWallClockCannotJustifyEitherPossibleLegacyConversion() throws {
        let original = try XCTUnwrap(StreamVixTimingPolicy.originalKickoff(
            dayHeader: "Sunday 25th October 2026 - Schedule Time UK GMT", clock: "02:30"))
        XCTAssertEqual(original, utc("2026-10-25T02:30:00Z"))
        XCTAssertNil(StreamVixTimingPolicy.legacyRomeInterpretation(of: original))
        for candidate in ["2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z"] {
            XCTAssertFalse(StreamVixTimingPolicy.corroborates(derived: utc(candidate), original: original), candidate)
        }
        XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: original, original: original))
    }

    func testSpringNonexistentRomeWallClockCannotJustifyNormalizationOrCorrection() throws {
        let original = try XCTUnwrap(StreamVixTimingPolicy.originalKickoff(
            dayHeader: "Sunday 29th March 2026 - Schedule Time UK GMT", clock: "02:30"))
        XCTAssertEqual(original, utc("2026-03-29T02:30:00Z"))
        XCTAssertNil(StreamVixTimingPolicy.legacyRomeInterpretation(of: original))
        for candidate in ["2026-03-29T00:30:00Z", "2026-03-29T01:30:00Z", "2026-03-29T03:30:00Z"] {
            XCTAssertFalse(StreamVixTimingPolicy.corroborates(derived: utc(candidate), original: original), candidate)
        }
        XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: original, original: original))
    }

    func testUniqueWallClocksImmediatelyOutsideDSTGapAndOverlapRemainCorroboratable() {
        let cases = [
            ("2026-03-29T01:59:00Z", "2026-03-29T00:59:00Z"),
            ("2026-03-29T03:00:00Z", "2026-03-29T01:00:00Z"),
            ("2026-10-25T01:59:00Z", "2026-10-24T23:59:00Z"),
            ("2026-10-25T03:00:00Z", "2026-10-25T02:00:00Z")
        ]
        for (original, derived) in cases {
            XCTAssertEqual(StreamVixTimingPolicy.legacyRomeInterpretation(of: utc(original)), utc(derived), original)
            XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: utc(derived), original: utc(original)), original)
        }
    }

    func testOriginalCalendarDateAndYearSurviveLegacyConversionAcrossMidnight() throws {
        let cases = [
            ("Thursday 1st January 2026 - Schedule Time UK GMT", "00:30", "2026-01-01T00:30:00Z", "2025-12-31T23:30:00Z"),
            ("Saturday 24th October 2026 - Schedule Time UK GMT", "00:30", "2026-10-24T00:30:00Z", "2026-10-23T22:30:00Z"),
            ("Friday 1st January 2027 - Schedule Time UK GMT", "00:00", "2027-01-01T00:00:00Z", "2026-12-31T23:00:00Z")
        ]
        for (header, clock, originalText, derivedText) in cases {
            let original = try XCTUnwrap(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: clock))
            XCTAssertEqual(original, utc(originalText), header)
            XCTAssertEqual(StreamVixTimingPolicy.legacyRomeInterpretation(of: original), utc(derivedText), header)
            XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: utc(derivedText), original: original), header)
        }
    }

    func testExactDateCanOmitOrdinalAndUseReviewedEnglishMonthSpellings() {
        for header in ["Saturday 24th October 2026 - Schedule Time UK GMT",
                       "Saturday 24 October 2026 - Schedule Time UK GMT",
                       "Saturday 24th Oct 2026 - Schedule Time UK GMT"] {
            XCTAssertEqual(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: "16:30"),
                           utc("2026-10-24T16:30:00Z"), header)
        }
        for month in ["September", "Sep", "Sept"] {
            XCTAssertEqual(StreamVixTimingPolicy.originalKickoff(
                dayHeader: "Tuesday 1st \(month) 2026 - Schedule Time UK GMT", clock: "00:00"),
                utc("2026-09-01T00:00:00Z"), month)
        }
    }

    func testOrdinalSuffixesAreCheckedIncludingElevenTwelveAndThirteen() {
        let cases = [
            ("Tuesday 11th August 2026 - Schedule Time UK GMT", "2026-08-11T12:00:00Z"),
            ("Wednesday 12th August 2026 - Schedule Time UK GMT", "2026-08-12T12:00:00Z"),
            ("Thursday 13th August 2026 - Schedule Time UK GMT", "2026-08-13T12:00:00Z"),
            ("Friday 21st August 2026 - Schedule Time UK GMT", "2026-08-21T12:00:00Z"),
            ("Saturday 22nd August 2026 - Schedule Time UK GMT", "2026-08-22T12:00:00Z"),
            ("Sunday 23rd August 2026 - Schedule Time UK GMT", "2026-08-23T12:00:00Z")
        ]
        for (header, expected) in cases {
            XCTAssertEqual(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: "12:00"), utc(expected), header)
        }
        for header in ["Saturday 24rd October 2026 - Schedule Time UK GMT",
                       "Sunday 25st October 2026 - Schedule Time UK GMT",
                       "Tuesday 11st August 2026 - Schedule Time UK GMT",
                       "Wednesday 12nd August 2026 - Schedule Time UK GMT",
                       "Thursday 13rd August 2026 - Schedule Time UK GMT"] {
            XCTAssertNil(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: "12:00"), header)
        }
    }

    func testMissingAmbiguousOrChangedHeaderFactsNeverBorrowCurrentDateOrAnotherTimezone() {
        for header in ["", "LIVE", "Saturday - Schedule Time UK GMT", "24th October 2026 - Schedule Time UK GMT",
                       "Saturday 24th October - Schedule Time UK GMT", "Saturday 24th October 26 - Schedule Time UK GMT",
                       "Saturday 24th October 2026", "Saturday 24th October 2026 - Schedule Time UK",
                       "Saturday 24th October 2026 - Schedule Time Europe/London",
                       "Saturday 24th October 2026 - Schedule Time Europe/Rome",
                       "Saturday 24th October 2026 - Schedule Time UK BST",
                       "Saturday 24th October 2026 - Schedule Time UTC",
                       "Friday 24th October 2026 - Schedule Time UK GMT",
                       "Saturday 24th Unknown 2026 - Schedule Time UK GMT",
                       "Saturday 24th October 2026 - Schedule Time UK GMT extra",
                       "prefix Saturday 24th October 2026 - Schedule Time UK GMT",
                       String(repeating: "x", count: 129)] {
            XCTAssertNil(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: "16:30"), header)
        }
    }

    func testHeaderMustConsumeEntireInputIncludingTerminalLineSeparators() {
        let valid = "Saturday 24th October 2026 - Schedule Time UK GMT"
        for separator in ["\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"] {
            XCTAssertNil(StreamVixTimingPolicy.originalKickoff(dayHeader: valid + separator, clock: "16:30"),
                         "A terminal line separator must not bypass the exact marker contract")
            XCTAssertNil(StreamVixTimingPolicy.originalKickoff(dayHeader: separator + valid, clock: "16:30"))
        }
    }

    func testInvalidCalendarAndClockValuesCannotNormalizeIntoAnotherFixture() {
        for header in ["Saturday 31st February 2026 - Schedule Time UK GMT",
                       "Sunday 29th February 2026 - Schedule Time UK GMT",
                       "Monday 31st November 2026 - Schedule Time UK GMT",
                       "Saturday 0th October 2026 - Schedule Time UK GMT",
                       "Saturday 32nd October 2026 - Schedule Time UK GMT",
                       "Saturday 24th October 1999 - Schedule Time UK GMT",
                       "Saturday 24th October 2100 - Schedule Time UK GMT"] {
            XCTAssertNil(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: "16:30"), header)
        }
        let header = "Saturday 24th October 2026 - Schedule Time UK GMT"
        for clock in ["", "LIVE", "16", "6:30", "16:3", "24:00", "23:60", "-1:30", "16:30:00",
                      "16:30Z", "16:30 UTC", "16:30+00:00", " 16:30", "16:30 ", "16:30\n", "16:30\r\n"] {
            XCTAssertNil(StreamVixTimingPolicy.originalKickoff(dayHeader: header, clock: clock), clock)
        }
        XCTAssertEqual(StreamVixTimingPolicy.originalKickoff(
            dayHeader: "Thursday 29th February 2024 - Schedule Time UK GMT", clock: "23:59"),
            utc("2024-02-29T23:59:00Z"))
    }

    func testCorroborationIsNotAnArbitraryHourMinuteDateOrNearestKickoffFence() {
        let original = utc("2026-10-24T16:30:00Z")
        for offset: TimeInterval in [-86_400, -10_800, -7_201, -7_199, -5_400, -3_600, -900, -1, 1, 900, 3_600, 7_200, 86_400] {
            XCTAssertFalse(StreamVixTimingPolicy.corroborates(derived: original.addingTimeInterval(offset), original: original),
                           "Unreviewed offset \(offset)")
        }
        XCTAssertTrue(StreamVixTimingPolicy.corroborates(derived: original.addingTimeInterval(-7_200), original: original))
    }

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
