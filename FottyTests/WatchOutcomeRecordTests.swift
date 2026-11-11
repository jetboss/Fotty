import XCTest
@testable import Fotty

/// The private per-tap Watch outcome record and its Settings summary.
/// Every store here is an isolated defaults suite; nothing reaches the network.
@MainActor
final class WatchOutcomeRecordTests: XCTestCase {
    private let suiteName = "WatchOutcomeRecordTests"
    private var defaults: UserDefaults!
    private var store: FottyQualityStore!
    private var now: TimeInterval = 1_000

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = FottyQualityStore(defaults: defaults, storageKey: "watch-outcomes")
        now = 1_000
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func recorder() -> WatchOutcomeRecorder {
        WatchOutcomeRecorder(store: store, clock: { [unowned self] in self.now })
    }

    private func outcomes() -> [FottyQualityRecord] {
        store.records().filter { $0.name == WatchOutcomeRecorder.recordName }
    }

    func testEachTapWritesExactlyOneRecordWhateverHappensAfterThePicture() throws {
        let recorder = recorder(), watch = UUID()
        recorder.begin(watchID: watch, competition: "premier-league", sport: "football")
        recorder.begin(watchID: watch, competition: "premier-league", sport: "football") // repeat cannot restart the clock
        now += 2.345
        recorder.picture(watchID: watch, family: "CS")
        recorder.picture(watchID: watch, family: "AS")
        recorder.failover(watchID: watch, toFamily: "HF")
        recorder.finish(watchID: watch, .failed, failureKind: "stalled")
        recorder.finish(watchID: watch, .cancelled)

        let records = outcomes()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.category, .playback)
        XCTAssertEqual(record.outcome, .success)
        XCTAssertEqual(record.durationMilliseconds, 2_345)
        XCTAssertEqual(record.details, ["competition": "premier-league", "sport": "football",
                                        "terminal_outcome": "playing", "failover_count": "0",
                                        "route": "single", "source_family": "CS"])
        XCTAssertFalse(recorder.isPending(watch))
        XCTAssertEqual(recorder.pendingCount, 0)
    }

    func testUnknownWatchAndWatchTwoSessionsWriteNothing() {
        let recorder = recorder()
        recorder.picture(watchID: UUID(), family: "CS")
        recorder.failover(watchID: UUID(), toFamily: "AS")
        recorder.finish(watchID: UUID(), .failed, failureKind: "network")
        XCTAssertTrue(outcomes().isEmpty)
    }

    func testAutomaticFailoverRecordsCountAndTheFamilyItMovedTo() throws {
        let recorder = recorder(), watch = UUID()
        recorder.begin(watchID: watch, competition: "champions-league", sport: "football")
        recorder.failover(watchID: watch, toFamily: "AS")
        recorder.failover(watchID: watch, toFamily: "score808")
        now += 7
        recorder.picture(watchID: watch, family: "score808")

        let details = try XCTUnwrap(outcomes().first?.details)
        XCTAssertEqual(details["failover_count"], "2")
        XCTAssertEqual(details["failover_family"], "score808")
        XCTAssertEqual(details["source_family"], "score808")
        XCTAssertEqual(outcomes().first?.durationMilliseconds, 7_000)
    }

    func testFailedAndNoStreamOutcomesKeepTheirCategoryButNoTime() throws {
        let recorder = recorder()
        let failed = UUID(), empty = UUID(), cancelled = UUID(), timeout = UUID()
        for id in [failed, empty, cancelled, timeout] {
            recorder.begin(watchID: id, competition: "wbbl", sport: "cricket")
        }
        now += 30
        recorder.finish(watchID: failed, .failed, failureKind: LivePlaybackFailureKind.startupTimeout.rawValue, family: "CS")
        recorder.finish(watchID: empty, resolutionFailure: .noProviderAvailable)
        recorder.finish(watchID: cancelled, resolutionFailure: .userCancelled)
        recorder.finish(watchID: timeout, resolutionFailure: .providerTimeout)

        let records = outcomes()
        XCTAssertEqual(records.map { $0.details["terminal_outcome"] }, ["failed", "no_stream_found", "cancelled", "failed"])
        XCTAssertEqual(records.map { $0.details["failure_kind"] },
                       ["startuptimeout", "no_provider_available", "user_cancelled", "provider_timeout"])
        XCTAssertEqual(records.map(\.outcome), [.failure, .failure, .info, .failure])
        XCTAssertTrue(records.allSatisfy { $0.durationMilliseconds == nil })
        XCTAssertEqual(records.first?.details["source_family"], "CS")
    }

    func testRecordCarriesNoURLCredentialOrIdentifierFields() throws {
        let recorder = recorder(), watch = UUID()
        recorder.begin(watchID: watch, competition: "https://private.invalid/live?token=abc", sport: "Football Club FC!")
        recorder.failover(watchID: watch, toFamily: "https://private.invalid/hls.m3u8")
        recorder.picture(watchID: watch, family: "Bearer abc.def")

        let record = try XCTUnwrap(outcomes().first)
        XCTAssertEqual(Set(record.details.keys), ["competition", "sport", "terminal_outcome", "failover_count", "route"])
        XCTAssertEqual(record.details["competition"], "other")
        XCTAssertEqual(record.details["sport"], "other")
        for forbidden in ["watch_session_id", "attempt_id", "source_id", "variant_key", "source_key", "source"] {
            XCTAssertNil(record.details[forbidden], forbidden)
        }
        let export = store.exportJSON()
        XCTAssertFalse(export.contains("://"))
        XCTAssertFalse(export.contains("private.invalid"))
        XCTAssertFalse(export.contains(watch.uuidString))
    }

    func testStoreRejectsForgedOutcomeValues() throws {
        store.record(category: .playback, name: WatchOutcomeRecorder.recordName, outcome: .success, details: [
            "competition": "Premier League", "sport": "football", "terminal_outcome": "streaming",
            "failover_count": "99", "failover_family": "https://private.invalid"
        ])
        XCTAssertEqual(try XCTUnwrap(outcomes().first).details, ["sport": "football"])
    }

    func testAbandonedPendingTapsAreBoundedAndRecordedAsCancelled() {
        let recorder = recorder()
        let ids = (0...WatchOutcomeRecorder.maximumPending).map { _ in UUID() }
        for id in ids { recorder.begin(watchID: id, competition: "premier-league", sport: "football") }
        XCTAssertEqual(recorder.pendingCount, WatchOutcomeRecorder.maximumPending)
        XCTAssertFalse(recorder.isPending(ids[0]))
        XCTAssertEqual(outcomes().map { $0.details["terminal_outcome"] }, ["cancelled"])
    }

    func testOutcomesSurviveLargePlaybackCohortsInTheBoundedBuffer() {
        let recorder = recorder()
        for index in 0..<120 {
            let id = UUID()
            recorder.begin(watchID: id, competition: "premier-league", sport: "football")
            if index.isMultiple(of: 2) { recorder.picture(watchID: id, family: "CS") }
            else { recorder.finish(watchID: id, .failed, failureKind: "network") }
        }
        let attempt = UUID().uuidString
        for _ in 0..<300 {
            store.record(category: .playback, name: "native_diagnostic", outcome: .info, details: ["attempt_id": attempt])
        }
        let records = store.records()
        XCTAssertLessThanOrEqual(records.count, 250)
        XCTAssertEqual(outcomes().count, FottyQualityStore.reservedWatchOutcomes)
        XCTAssertEqual(records.count { $0.details["attempt_id"] == attempt }, 250 - FottyQualityStore.reservedWatchOutcomes)
    }

    func testSummaryCountsTapsPictureShareAndMedianPerCompetition() throws {
        let recorder = recorder()
        func tap(_ competition: String, seconds: Double?, failover: Bool = false) {
            let id = UUID()
            recorder.begin(watchID: id, competition: competition, sport: "football")
            if failover { recorder.failover(watchID: id, toFamily: "AS") }
            now += seconds ?? 5
            if seconds != nil { recorder.picture(watchID: id, family: "CS") }
            else { recorder.finish(watchID: id, .noStreamFound) }
        }
        tap("premier-league", seconds: 4)
        tap("premier-league", seconds: 2, failover: true)
        tap("premier-league", seconds: 9)
        tap("premier-league", seconds: 6)
        tap("premier-league", seconds: nil)
        tap("champions-league", seconds: nil)
        tap("champions-league", seconds: 3)
        tap("wbbl", seconds: nil, failover: true)
        // Unrelated playback evidence never counts as a tap.
        store.record(category: .playback, name: "decoded_progress", outcome: .success, durationMilliseconds: 1)

        let summary = store.watchOutcomeSummary()
        XCTAssertEqual(summary.rows.map(\.competition), ["premier-league", "champions-league", "wbbl"])
        XCTAssertEqual(summary.totalTaps, 8)
        let pl = try XCTUnwrap(summary.rows.first)
        XCTAssertEqual(pl.taps, 5)
        XCTAssertEqual(pl.pictures, 4)
        XCTAssertEqual(pl.pictureShare, 0.8, accuracy: 0.0001)
        XCTAssertEqual(pl.failovers, 1)
        XCTAssertEqual(pl.medianMillisecondsToPicture, 4_000) // lower median of 2, 4, 6, 9
        XCTAssertEqual(summary.rows[1].pictureShare, 0.5, accuracy: 0.0001)
        XCTAssertEqual(summary.rows[1].medianMillisecondsToPicture, 3_000)
        XCTAssertEqual(summary.rows[2].pictures, 0)
        XCTAssertNil(summary.rows[2].medianMillisecondsToPicture)
        XCTAssertEqual(summary.rows[2].failovers, 1)

        XCTAssertEqual(WatchOutcomeSummaryText.value(for: pl), "5 taps · 80% picture · 4.0 s")
        XCTAssertEqual(WatchOutcomeSummaryText.value(for: summary.rows[2]), "1 tap · 0% picture")
        let export = WatchOutcomeSummaryText.export(summary, at: Date(timeIntervalSince1970: 1_794_000_000),
                                                    version: "3.0.0", build: "283")
        XCTAssertTrue(export.hasPrefix("Fotty Watch outcomes · 3.0.0 (283) · "))
        XCTAssertTrue(export.contains("8 Watch taps on this device"))
        XCTAssertTrue(export.contains(": 5 taps · 80% picture · 4.0 s · 1 with a source change"))
        XCTAssertFalse(export.contains("http"), "Export carries totals only")
        XCTAssertEqual(WatchOutcomeSummary.summarize([]).rows, [])
        XCTAssertEqual(WatchOutcomeSummary.median([5]), 5)
        XCTAssertEqual(WatchOutcomeSummary.median([9, 1, 5]), 5)
        XCTAssertNil(WatchOutcomeSummary.median([]))
    }

    func testCompetitionLabelsAreOpaqueBuckets() {
        let channel = EventReference(id: "willow", title: "Willow", category: "cricket", date: nil,
                                     poster: nil, popular: false, teams: nil)
        XCTAssertEqual(WatchOutcomeCompetition.labels(for: channel).competition, WatchOutcomeCompetition.tvChannel)
        XCTAssertEqual(WatchOutcomeCompetition.labels(for: channel).sport, "cricket")
        let unknown = EventReference(id: "x", title: "Somebody vs Someone", category: "basketball", date: nil,
                                     poster: nil, popular: false, teams: nil)
        XCTAssertEqual(WatchOutcomeCompetition.labels(for: unknown).competition, "basketball-other")
        XCTAssertEqual(WatchOutcomeCompetition.token(" WBBL "), "wbbl")
        XCTAssertNil(WatchOutcomeCompetition.token("Premier League"))
        XCTAssertNil(WatchOutcomeCompetition.token("https://x"))
        XCTAssertEqual(WatchOutcomeCompetition.displayName("champions-league"), "Champions League")
        XCTAssertEqual(WatchOutcomeCompetition.displayName("big-bash"), "Big Bash")
        XCTAssertEqual(WatchOutcomeRecorder.family("HF"), "HF")
        XCTAssertNil(WatchOutcomeRecorder.family("cs://host"))
    }
}
