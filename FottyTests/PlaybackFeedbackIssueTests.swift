import XCTest
@testable import Fotty

final class PlaybackFeedbackIssueTests: XCTestCase {
    func testKnownPlaybackProblemSeedsBothFieldsForAnEmptyDraft() {
        for issue in [PlaybackFeedbackIssue.cannotStart, .buffering, .noSound, .wrongMatch, .controls] {
            let draft = issue.seed(expected: "  ", actual: "")
            XCTAssertFalse(draft.expected.isEmpty)
            XCTAssertEqual(draft.actual, issue.suggestedActual)
        }
    }

    func testChoosingAProblemNeverOverwritesAnUnfinishedOrContextualDraft() {
        for draft in [("My notes", ""), ("", "Provider rejected playback"), ("Watch this match", "Wrong sound")] {
            let result = PlaybackFeedbackIssue.noSound.seed(expected: draft.0, actual: draft.1)
            XCTAssertEqual(result.expected, draft.0)
            XCTAssertEqual(result.actual, draft.1)
        }
    }

    func testUnspecifiedOrOtherDoesNotInventFailureDetails() {
        for issue in [PlaybackFeedbackIssue.unspecified, .other] {
            let draft = issue.seed(expected: "", actual: "")
            XCTAssertEqual(draft, .init(expected: "", actual: ""))
        }
    }

    func testClassificationAppearsOnlyInPlaybackReports() {
        var report = FottyFeedbackReport(area: "Playback", expected: "Watch match", actual: "No sound",
            version: "test", device: "test", system: "test", date: Date(timeIntervalSince1970: 0), playbackIssue: .noSound)
        XCTAssertTrue(report.text.contains("Playback problem: No sound"))
        XCTAssertTrue(report.text.contains("No sound"))
        XCTAssertFalse(report.text.contains("Optional on-device diagnostics"))
        for area in FottyFeedbackArea.allCases where area != .playback {
            report = FottyFeedbackReport(area: area.rawValue, expected: "Watch match", actual: "No sound",
                version: "test", device: "test", system: "test", date: Date(timeIntervalSince1970: 0), playbackIssue: .noSound)
            XCTAssertFalse(report.text.contains("Playback problem:"))
        }
    }

    func testUnknownStoredClassificationCannotEnterAReport() {
        let issue = PlaybackFeedbackIssue(rawValue: "unreviewed https://example.invalid/private")
        XCTAssertNil(issue)
        let report = FottyFeedbackReport(area: "Playback", expected: "Watch", actual: "Unavailable",
            version: "test", device: "test", system: "test", date: .distantPast, playbackIssue: issue)
        XCTAssertFalse(report.text.contains("example.invalid"))
        XCTAssertFalse(report.text.contains("Playback problem:"))
    }
}
