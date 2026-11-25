import XCTest
import AVFoundation
@testable import Fotty

/// Player shrink slice 6: handoff candidate ledger and shared receipt labels.
final class NativeHandoffTests: XCTestCase {
    func testLedgerTriesEachCandidateOnceUpToTwelve() throws {
        var ledger = NativeHandoffCandidateLedger()
        let source = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/a.m3u8"))
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertTrue(ledger.admit(sourceID: source, url: url))
        XCTAssertFalse(ledger.admit(sourceID: source, url: url), "Passive discovery never retries a candidate")
        XCTAssertTrue(ledger.admit(sourceID: UUID(), url: url), "The key is source and URL together")
        for index in 0..<10 {
            XCTAssertTrue(ledger.admit(sourceID: source, url: try XCTUnwrap(URL(string: "https://example.com/\(index).m3u8"))))
        }
        XCTAssertEqual(ledger.attempted.count, NativeHandoffCandidateLedger.maximumAttempts)
        XCTAssertFalse(ledger.admit(sourceID: source, url: try XCTUnwrap(URL(string: "https://example.com/new.m3u8"))),
                       "No more than 12 candidates in all")
        ledger.allowRetry(sourceID: source, url: url)
        XCTAssertTrue(ledger.admit(sourceID: source, url: url), "An explicit request may validate one again")
        ledger.reset()
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertEqual(NativeHandoffCandidateLedger.key(sourceID: source, url: url), "\(source.uuidString)|\(url.absoluteString)")
    }

    func testItemStatusLabels() {
        XCTAssertEqual(NativeHandoffCandidateDiagnostic.itemStatusLabel(.unknown), "unknown")
        XCTAssertEqual(NativeHandoffCandidateDiagnostic.itemStatusLabel(.readyToPlay), "ready")
        XCTAssertEqual(NativeHandoffCandidateDiagnostic.itemStatusLabel(.failed), "failed")
    }

    func testPreflightReceiptOutcome() {
        XCTAssertEqual(NativeWatchTwoPreflightOutcome.prepared.qualityOutcome(retained: true), .success)
        XCTAssertEqual(NativeWatchTwoPreflightOutcome.cancelled.qualityOutcome(retained: false), .info)
        XCTAssertEqual(NativeWatchTwoPreflightOutcome.staleOwner.qualityOutcome(retained: false), .info)
        for outcome: NativeWatchTwoPreflightOutcome in [.notEligible, .unsupported, .noCandidate, .staleCandidate,
            .proxyFailed, .validationRejected, .isolationFailed, .readinessFailed, .readinessTimeout,
            .registrationRejected, .prepared] {
            XCTAssertEqual(outcome.qualityOutcome(retained: false), .failure, outcome.rawValue)
        }
    }
}
