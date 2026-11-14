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

    func testOwnerStatusCountsReturnedChoicesAndWatchPicturesIndependently() throws {
        store.recordStreamAdmission(sourceFamily: "communitysports", offered: 120, admitted: 100)
        store.recordStreamAdmission(sourceFamily: "communitysports", offered: 5, admitted: 0)
        store.recordStreamAdmission(sourceFamily: "reviewedtv", offered: 0, admitted: 0)
        for family in ["communitysports", "CS", "score808"] {
            store.record(category: .playback, name: "watch_outcome", outcome: .success,
                         details: ["source_family": family, "terminal_outcome": "playing"])
        }
        store.record(category: .playback, name: "watch_outcome", outcome: .failure,
                     details: ["source_family": "communitysports", "terminal_outcome": "failed"])
        let rows = store.ownerStatusSnapshot().streamAdmissions
        let community = try XCTUnwrap(rows.first { $0.id == .communitySports })
        XCTAssertEqual(community.lookups, 2)
        XCTAssertEqual(community.offered, 125)
        XCTAssertEqual(community.admitted, 100)
        XCTAssertEqual(community.firstPictures, 2)
        XCTAssertEqual(community.admissionText, "125 offered · 100 candidates · 2 lookups")
        XCTAssertEqual(community.dispositions["unrecorded"], 25)
        XCTAssertEqual(rows.first { $0.id == .reviewedTV }?.admissionText, "0 offered · 0 candidates · 1 lookup")
        XCTAssertEqual(rows.first { $0.id == .score808 }?.admissionText, "No stream counts recorded")
        XCTAssertEqual(store.ownerStatusSnapshot(appBuild: "older-build").streamAdmissions, [])
    }

    func testOwnerStatusKeepsUnknownHistoricalCountsAndUnobservedPicturesDistinct() throws {
        // The old logger dropped an offered count over 100. Its used_count could
        // still include candidates discarded during the final fixture check.
        store.record(category: .playback, name: "highfly_delivery_admission", outcome: .info,
                     details: ["used_count": "100", "candidate_count": "12", "reason_code": "replay"])
        store.record(category: .playback, name: "penguplay_delivery_admission", outcome: .info,
                     details: ["addon_stream_entry_count": "5", "candidate_count": "3"])
        let rows = store.ownerStatusSnapshot().streamAdmissions
        let highfly = try XCTUnwrap(rows.first { $0.id == .highfly })
        XCTAssertNil(highfly.offered)
        XCTAssertNil(highfly.admitted)
        XCTAssertEqual(highfly.firstPictures, 0)
        XCTAssertEqual(highfly.reportedReason, "replay")
        let penguPlay = try XCTUnwrap(rows.first { $0.id == .penguPlay })
        XCTAssertEqual(penguPlay.offered, 5)
        XCTAssertNil(penguPlay.admitted)
    }

    func testAdmissionReceiptsContainOnlyBoundedCountsAndKnownFamilies() throws {
        let families = CuratedStreamSourceCatalog.optionalSources.map(\.providerCode)
        for family in families {
            store.recordStreamAdmission(sourceFamily: family, offered: 300, admitted: 12)
        }
        store.recordStreamAdmission(sourceFamily: "highfly", offered: 3, admitted: 4)
        store.recordStreamAdmission(sourceFamily: "penguplay", offered: -1, admitted: 0)
        store.recordStreamAdmission(sourceFamily: "highfly", offered: Int.max, admitted: 0)
        store.recordStreamAdmission(sourceFamily: "https://example.invalid/secret", offered: 5, admitted: 1)
        XCTAssertEqual(store.records().count, families.count)
        for receipt in store.records() {
            XCTAssertEqual(Set(receipt.details.keys), ["source_family", "offered_count", "admitted_count"])
            XCTAssertTrue(families.contains(try XCTUnwrap(receipt.details["source_family"])))
        }
    }

    func testAdmissionLedgerPartitionsEveryObservedEntryWithoutInventingRejections() {
        var ledger = StreamAdmissionLedger()
        ledger.observe(7)
        ledger.record("duplicate")
        ledger.record("malformed")
        ledger.record("same_addon_domain", count: 2)
        ledger.record("limit")
        ledger.finish(admitted: 1)
        XCTAssertEqual(ledger.offered, 7)
        XCTAssertEqual(ledger.admitted, 1)
        XCTAssertEqual(ledger.dispositions["unprocessed"], 1)
        XCTAssertEqual(ledger.dispositions["limit"], 1, "Only an explicitly observed limit is a limit")
        XCTAssertEqual(ledger.accounted, ledger.offered)
        XCTAssertTrue(ledger.isReconciled)
        ledger.finish(admitted: 1)
        XCTAssertTrue(ledger.isReconciled, "Finalization is idempotent")
    }

    func testCancelledOrFailedLookupWithdrawsProvisionalChoicesAndKeepsItsEvidence() throws {
        for completion in ["cancelled", "failed"] {
            var ledger = StreamAdmissionLedger()
            ledger.observe(4)
            ledger.record("duplicate")
            ledger.record("admitted", count: 3)
            ledger.finish(admitted: 3, completion: completion)
            XCTAssertEqual(ledger.admitted, 0)
            XCTAssertEqual(ledger.dispositions["withdrawn"], 3)
            XCTAssertTrue(ledger.isReconciled)
            store.recordStreamAdmission(sourceFamily: "highfly", ledger: ledger, completion: completion)
        }
        let row = try XCTUnwrap(store.ownerStatusSnapshot().streamAdmissions.first)
        XCTAssertEqual(row.lookups, 2)
        XCTAssertEqual(row.offered, 8)
        XCTAssertEqual(row.admitted, 0)
        XCTAssertEqual(row.dispositions["withdrawn"], 6)
        XCTAssertEqual(row.incompleteLookups, 2)
        XCTAssertEqual(row.firstPictures, 0)
    }

    func testAdmissionUnreadAndEmptyResponsesAreDifferentAndFailuresDoNotInventOffers() throws {
        var unread = StreamAdmissionLedger()
        unread.finish(admitted: 0, completion: "failed")
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: unread, completion: "failed", fetchFailures: 2)
        var empty = StreamAdmissionLedger()
        empty.observe(0)
        empty.finish(admitted: 0)
        store.recordStreamAdmission(sourceFamily: "reviewedtv", ledger: empty)
        let records = store.records()
        let failed = try XCTUnwrap(records.first { $0.details["source_family"] == "highfly" })
        XCTAssertNil(failed.details["offered_count"])
        XCTAssertNil(failed.details["admitted_count"])
        XCTAssertEqual(failed.details["admission_observation"], "unread")
        XCTAssertEqual(failed.details["admission_reconciled"], "unknown")
        XCTAssertEqual(failed.details["admission_fetch_failures"], "2")
        let knownEmpty = try XCTUnwrap(records.first { $0.details["source_family"] == "reviewedtv" })
        XCTAssertEqual(knownEmpty.details["offered_count"], "0")
        XCTAssertEqual(knownEmpty.details["admission_observation"], "known")
        XCTAssertEqual(knownEmpty.details["admission_reconciled"], "yes")
        let row = try XCTUnwrap(store.ownerStatusSnapshot().streamAdmissions.first { $0.id == .highfly })
        XCTAssertNil(row.offered)
        XCTAssertEqual(row.unreadLookups, 1)
        XCTAssertEqual(row.fetchFailures, 2)
    }

    func testPartialAdmissionKeepsFailedSiblingAndEveryReasonInTheSameScope() throws {
        var first = StreamAdmissionLedger()
        first.observe(5)
        first.record("duplicate")
        first.record("same_addon_domain")
        first.record("malformed")
        first.finish(admitted: 2, completion: "partial")
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: first, completion: "partial", fetchFailures: 1)
        var second = StreamAdmissionLedger()
        second.observe(3)
        second.record("validation", count: 2)
        second.finish(admitted: 1)
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: second)
        let row = try XCTUnwrap(store.ownerStatusSnapshot().streamAdmissions.first)
        XCTAssertEqual(row.offered, 8)
        XCTAssertEqual(row.admitted, 3)
        XCTAssertEqual(row.dispositions.values.reduce(0, +), 8)
        XCTAssertEqual(row.dispositions["validation"], 2)
        XCTAssertEqual(row.dispositions["same_addon_domain"], 1)
        XCTAssertEqual(row.fetchFailures, 1)
        XCTAssertEqual(row.incompleteLookups, 1)
        XCTAssertEqual(row.firstPictures, 0)
        XCTAssertEqual(StreamAdmissionSummary.label("same_addon_domain"), "Same add-on domain")
        XCTAssertFalse(row.dispositionReasons.contains("admitted"))
    }

    func testDuplicateLookupReceiptDoesNotDoubleCountAndLegacyReasonsAreNotExtrapolated() throws {
        var ledger = StreamAdmissionLedger()
        ledger.observe(3)
        ledger.record("duplicate")
        ledger.finish(admitted: 2)
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: ledger)
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: ledger)
        store.record(category: .playback, name: "highfly_delivery_admission", outcome: .info,
                     details: ["offered_count": "3", "admitted_count": "1", "reason_code": "replay"])
        let row = try XCTUnwrap(store.ownerStatusSnapshot().streamAdmissions.first)
        XCTAssertEqual(row.lookups, 2)
        XCTAssertEqual(row.offered, 6)
        XCTAssertEqual(row.admitted, 3)
        XCTAssertEqual(row.dispositions["duplicate"], 1)
        XCTAssertEqual(row.dispositions["unrecorded"], 2)
        XCTAssertEqual(row.dispositions["replay"], 0, "A legacy modal reason adds no counted replay decisions")
        XCTAssertFalse(row.dispositionReasons.contains("replay"), "Zero histogram entries are not displayed as decisions")
    }

    func testLedgerRejectsOverAccountingUnknownReasonsAndPrivateReceiptFields() throws {
        var ledger = StreamAdmissionLedger()
        ledger.observe(2)
        ledger.record("admitted", count: 2)
        ledger.record("duplicate")
        ledger.record("https://secret.invalid/token")
        ledger.observe(Int.max)
        ledger.finish(admitted: 2)
        XCTAssertFalse(ledger.isReconciled)
        XCTAssertEqual(ledger.accounted, 2)
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: ledger)
        let receipt = try XCTUnwrap(store.records().last)
        XCTAssertEqual(receipt.details["admission_reconciled"], "no")
        XCTAssertEqual(receipt.details["admission_duplicate_count"], "0")
        XCTAssertFalse(receipt.details.description.contains("secret"))
        XCTAssertTrue(StreamAdmissionLedger.reasons.allSatisfy { receipt.details[StreamAdmissionLedger.detailKey($0)] != nil })
        let row = try XCTUnwrap(store.ownerStatusSnapshot().streamAdmissions.first)
        XCTAssertEqual(row.unreconciledLookups, 1)
        XCTAssertEqual(row.dispositions["unrecorded"], 2)
    }

    func testStructuredAdmissionReceiptSupportsEveryRegisteredProviderWithoutPrivateDetails() {
        for provider in CuratedStreamSourceCatalog.Provider.allCases {
            var ledger = StreamAdmissionLedger()
            ledger.observe(101)
            ledger.record("limit")
            ledger.finish(admitted: 100)
            store.recordStreamAdmission(sourceFamily: provider.rawValue, ledger: ledger)
        }
        store.recordStreamAdmission(sourceFamily: "private.invalid", ledger: StreamAdmissionLedger())
        XCTAssertEqual(store.records().count, CuratedStreamSourceCatalog.Provider.allCases.count)
        for receipt in store.records() {
            XCTAssertEqual(receipt.details["admission_reconciled"], "yes")
            XCTAssertEqual(receipt.details["admission_limit_count"], "1")
            XCTAssertNil(receipt.details["delivery_host"])
            XCTAssertNil(receipt.details["reason_code"])
            XCTAssertFalse(receipt.details.values.contains { $0.contains("://") })
        }
    }

    func testSelectionReceiptsPreserveBoundaryLossesWithoutCountingProviderOffersAgain() throws {
        var admission = StreamAdmissionLedger()
        admission.observe(4)
        admission.finish(admitted: 4)
        store.recordStreamAdmission(sourceFamily: "highfly", ledger: admission)
        for stage in ["registry_binding", "final_watch", "discovery_cache"] {
            var selection = StreamAdmissionLedger()
            selection.observe(4)
            selection.record("expired")
            selection.record("disabled")
            selection.record("binding")
            selection.finish(admitted: 1)
            store.recordStreamSelection(sourceFamily: "highfly", stage: stage, ledger: selection)
        }
        store.recordStreamSelection(sourceFamily: "highfly", stage: "private.invalid", ledger: admission)
        let selections = store.records().filter { $0.name == "stream_selection" }
        XCTAssertEqual(selections.count, 3)
        XCTAssertEqual(Set(selections.compactMap { $0.details["stream_selection_stage"] }),
                       ["registry_binding", "final_watch", "discovery_cache"])
        XCTAssertTrue(selections.allSatisfy { $0.details["admission_reconciled"] == "yes" && $0.details["admission_binding_count"] == "1" })
        let row = try XCTUnwrap(store.ownerStatusSnapshot().streamAdmissions.first)
        XCTAssertEqual(row.lookups, 1)
        XCTAssertEqual(row.offered, 4)
        XCTAssertEqual(row.admitted, 4)
        for reason in ["expired", "disabled", "binding"] {
            XCTAssertEqual(row.dispositions[reason], 0, "Selection losses do not enter raw admission totals")
            XCTAssertFalse(row.dispositionReasons.contains(reason))
        }
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
