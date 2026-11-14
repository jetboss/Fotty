import XCTest
@testable import Fotty

/// The private per-tap Watch outcome record and its Settings summary.
/// Every store here is an isolated defaults suite; nothing reaches the network.
@MainActor
final class WatchOutcomeRecordTests: XCTestCase {
    func testProviderReceiptsDeduplicateLookupsButCountRepeatedReadsAndUniqueContractsSeparately() throws {
        let first = try evidenceReceipt()
        store.recordProviderLookup(first)
        store.recordProviderLookup(first)
        let second = try evidenceReceipt()
        store.recordProviderLookup(second)
        let window = DateInterval(start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(60))
        let counts = store.fixtureLookupCounts(fixture: first.fixture, provider: .highfly, window: window)
        XCTAssertEqual(counts.lookups, 2)
        XCTAssertEqual(counts.observedEntries, 4)
        XCTAssertEqual(counts.uniqueObservedContracts, 1, "The same executable contract seen twice is not two independent streams")
        XCTAssertEqual(counts.readResponses, 2)
        XCTAssertEqual(counts.unreadResponses, 0)
        XCTAssertEqual(counts.knownEmptyResponses, 0)
        XCTAssertFalse(counts.isTruncated)
        XCTAssertEqual(store.records().filter { $0.name == "provider_delivery" }.count, 4)
        XCTAssertEqual(store.records().filter { $0.name == "provider_lookup" }.count, 2)
    }

    func testProviderUnreadAndKnownEmptyAreDifferentAndFixturesDoNotMix() throws {
        let unread = try evidenceReceipt(mode: "unread")
        let empty = try evidenceReceipt(mode: "empty")
        store.recordProviderLookup(unread); store.recordProviderLookup(empty)
        store.recordProviderLookup(try evidenceReceipt(fixture: "another-private-fixture"))
        let counts = store.fixtureLookupCounts(fixture: unread.fixture, provider: .highfly,
            window: .init(start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(60)))
        XCTAssertEqual(counts.lookups, 2)
        XCTAssertEqual(counts.observedEntries, 0, "Zero observed entries is not a claim that an unread provider offered zero")
        XCTAssertEqual(counts.readResponses, 1)
        XCTAssertEqual(counts.unreadResponses, 1)
        XCTAssertEqual(counts.knownEmptyResponses, 1)
        let other = store.fixtureLookupCounts(fixture: unread.fixture, provider: .penguPlay, window: counts.window)
        XCTAssertEqual(other.lookups, 0)
    }

    func testProviderReceiptExportContainsOpaqueCorrelationOnly() throws {
        let receipt = try evidenceReceipt()
        store.recordProviderLookup(receipt)
        let data = try JSONEncoder().encode(store.records())
        let text = String(decoding: data, as: UTF8.self)
        for raw in ["private-fixture-sentinel", "private-listing-sentinel", "media.example.test",
                    "private-token-sentinel", "private-header-sentinel", "Liverpool", "Arsenal"] {
            XCTAssertFalse(text.contains(raw), raw)
        }
        let delivery = try XCTUnwrap(store.records().first { $0.name == "provider_delivery" })
        XCTAssertEqual(delivery.details["evidence_fixture"]?.count, 64)
        XCTAssertEqual(delivery.details["evidence_contract"]?.count, 64)
        XCTAssertEqual(delivery.details["evidence_comparison"], "agrees")
        XCTAssertEqual(delivery.details["evidence_has_name"], "true")
        XCTAssertEqual(delivery.details["source_id"], try XCTUnwrap(receipt.deliveries[0].sourceID).uuidString.lowercased())
        XCTAssertNil(store.records().first { $0.name == "provider_delivery"
            && $0.details["evidence_disposition"] == "duplicate" }?.details["source_id"])
    }

    func testEvidenceDetailValidationRejectsRawValuesAndInvalidCounters() {
        store.record(category: .playback, name: "provider_lookup", outcome: .info, details: [
            "evidence_contract": "https://private.example/token", "evidence_listing": "private-listing",
            "evidence_lookup_id": "secret", "evidence_generation": "secret", "evidence_comparison": "Liverpool vs Arsenal",
            "evidence_entry_index": "-1", "evidence_read_responses": "1000001", "evidence_has_name": "maybe",
            "evidence_disposition": "some raw provider error", "evidence_schema": "9"])
        XCTAssertEqual(store.records().last?.details, [:])
    }

    func testDelayedReceiptBelongsToItsObservationWindowInsteadOfItsWriteTime() throws {
        let old = Date().addingTimeInterval(-120)
        let receipt = try evidenceReceipt(date: old)
        store.recordProviderLookup(receipt)
        let current = store.fixtureLookupCounts(fixture: receipt.fixture, provider: .highfly,
            window: .init(start: Date().addingTimeInterval(-10), end: Date().addingTimeInterval(10)))
        XCTAssertEqual(current.lookups, 0)
        let original = store.fixtureLookupCounts(fixture: receipt.fixture, provider: .highfly,
            window: .init(start: old.addingTimeInterval(-1), end: old.addingTimeInterval(1)))
        XCTAssertEqual(original.lookups, 1)
        XCTAssertTrue(store.records().allSatisfy { $0.timestamp == receipt.finishedAt })
    }

    func testImpossibleNonemptyResponseCountsCannotCreateReconciledReceipts() throws {
        let empty = try evidenceReceipt(mode: "empty"), normal = try evidenceReceipt()
        for (base, reads, empties) in [(empty, 1, 0), (normal, 3, 0)] {
            let invalid = ProviderLookupReceipt(fixture: base.fixture, provider: base.provider,
                lookupID: UUID(), configurationGeneration: base.configurationGeneration,
                startedAt: base.startedAt, finishedAt: base.finishedAt, observedEntries: base.observedEntries,
                readResponses: reads, unreadResponses: 0, knownEmptyResponses: empties,
                uniqueObservedContracts: base.uniqueObservedContracts, admitted: base.admitted,
                dispositions: base.dispositions, deliveries: base.deliveries, completion: "complete",
                isTruncated: false, isReconciled: true)
            store.recordProviderLookup(invalid)
        }
        XCTAssertTrue(store.records().isEmpty)
    }

    func testCappedProviderSamplesKeepRawCountsAndStateTheUniqueCountIsIncomplete() throws {
        let receipt = try evidenceReceipt(mode: "capped")
        store.recordProviderLookup(receipt)
        let counts = store.fixtureLookupCounts(fixture: receipt.fixture, provider: .highfly,
            window: .init(start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(60)))
        XCTAssertEqual(receipt.observedEntries, 70)
        XCTAssertEqual(receipt.deliveries.count, 64)
        XCTAssertTrue(receipt.isReconciled)
        XCTAssertEqual(receipt.dispositions["limit"], 70)
        XCTAssertEqual(counts.observedEntries, 70)
        XCTAssertEqual(counts.uniqueObservedContracts, 64)
        XCTAssertTrue(counts.isTruncated)
    }

    func testProviderSummariesSurviveSampleLimitAndReplayDoesNotRestoreEvictedSamples() throws {
        let date = Date()
        let receipts = try (0..<6).map { _ in try evidenceReceipt(mode: "capped", date: date) }
        for receipt in receipts { store.recordProviderLookup(receipt) }
        // A later unrelated write must preserve equal-time append ordering too.
        store.record(category: .playback, name: "audio_activation_evidence", outcome: .info)
        let records = store.records()
        XCTAssertLessThanOrEqual(records.count, 250)
        XCTAssertEqual(records.filter { $0.name == "provider_lookup" }.count, 6)
        let samples = records.filter { $0.name == "provider_delivery" }
        XCTAssertEqual(samples.count, 128)
        XCTAssertEqual(Set(samples.compactMap { $0.details["evidence_lookup_id"] }),
            Set(receipts.suffix(2).map { $0.lookupID.uuidString.lowercased() }))
        let retainedIDs = Set(receipts.suffix(2).map { $0.lookupID.uuidString.lowercased() })
        for summary in records where summary.name == "provider_lookup" {
            XCTAssertEqual(summary.details["evidence_reconciled"],
                retainedIDs.contains(summary.details["evidence_lookup_id"] ?? "") ? "true" : "false")
            if !retainedIDs.contains(summary.details["evidence_lookup_id"] ?? "") {
                XCTAssertEqual(summary.details["evidence_truncated"], "true")
            }
        }
        store.recordProviderLookup(receipts[0])
        XCTAssertEqual(store.records(), records, "A retained summary still deduplicates a lookup after its samples expire")
        let counts = store.fixtureLookupCounts(fixture: receipts[0].fixture, provider: .highfly,
            window: .init(start: date.addingTimeInterval(-1), end: date.addingTimeInterval(1)))
        XCTAssertEqual(counts.lookups, 6)
        XCTAssertEqual(counts.observedEntries, 420)
        XCTAssertEqual(counts.readResponses, 6)
        XCTAssertEqual(counts.uniqueObservedContracts, 64)
        XCTAssertTrue(counts.isTruncated, "Evicted samples cannot claim complete contract coverage")
    }

    func testLargeProviderSearchesCannotEvictEarlierPlaybackAudioOrWatchOutcomes() throws {
        let attempt = UUID().uuidString, audioJob = UUID().uuidString
        for index in 0..<100 {
            store.record(category: .playback, name: index == 0 ? "attempt_started" : "decoded_progress", outcome: .success,
                details: ["attempt_id": attempt])
        }
        for _ in 0..<2 {
            store.record(category: .playback, name: "audio_activation_evidence", outcome: .success,
                details: ["audio_job_id": audioJob])
        }
        let recorder = recorder(), watch = UUID()
        recorder.begin(watchID: watch, competition: "premier-league", sport: "football")
        recorder.picture(watchID: watch, family: "HF")
        let before = store.records()
        for _ in 0..<6 { store.recordProviderLookup(try evidenceReceipt(mode: "capped")) }
        let after = store.records()
        XCTAssertTrue(Set(before.map(\.id)).isSubset(of: Set(after.map(\.id))))
        XCTAssertEqual(after.filter { $0.details["attempt_id"] == attempt }, before.filter { $0.details["attempt_id"] == attempt })
        XCTAssertEqual(after.filter { $0.details["audio_job_id"] == audioJob }.count, 2)
        XCTAssertEqual(outcomes().count, 1)
        XCTAssertEqual(after.filter { $0.name == "provider_lookup" }.count, 6)
        XCTAssertEqual(after.filter { $0.name == "provider_delivery" }.count, 128)
        XCTAssertLessThanOrEqual(after.count, 250)
    }

    func testProviderSamplesYieldAllCapacityToNearlyFullViewingHistory() throws {
        let attempt = UUID().uuidString
        for _ in 0..<230 {
            store.record(category: .playback, name: "native_diagnostic", outcome: .info, details: ["attempt_id": attempt])
        }
        let before = store.records()
        for _ in 0..<6 { store.recordProviderLookup(try evidenceReceipt(mode: "capped")) }
        let after = store.records()
        XCTAssertEqual(after.filter { $0.details["attempt_id"] == attempt }, before)
        XCTAssertEqual(after.filter { $0.name == "provider_lookup" }.count, 6)
        XCTAssertTrue(after.filter { $0.name == "provider_delivery" }.isEmpty,
            "Samples reserve no slots and cannot force a playback cohort out")
        XCTAssertTrue(after.filter { $0.name == "provider_lookup" }.allSatisfy {
            $0.details["evidence_truncated"] == "true" && $0.details["evidence_reconciled"] == "false"
        })
        XCTAssertEqual(after.count, 236)
    }

    func testLegacyProviderSamplesArePrunedOnReadWithoutLosingSummariesOrOrphaningEntries() throws {
        var legacy: [FottyQualityRecord] = []
        let date = Date()
        let receipts = try (0..<3).map { _ in try evidenceReceipt(mode: "capped", date: date) }
        for receipt in receipts {
            let isolated = FottyQualityStore(defaults: defaults, storageKey: "legacy-source")
            isolated.clear(); isolated.recordProviderLookup(receipt)
            legacy += isolated.records()
        }
        let orphan = try XCTUnwrap(legacy.first { $0.name == "provider_delivery" })
        var orphanDetails = orphan.details
        orphanDetails["evidence_lookup_id"] = UUID().uuidString.lowercased()
        legacy.append(.init(id: UUID(), timestamp: date, category: .playback, name: "provider_delivery", outcome: .info,
            durationMilliseconds: nil, details: orphanDetails, appVersion: orphan.appVersion, appBuild: orphan.appBuild))
        defaults.set(try JSONEncoder().encode(legacy), forKey: "watch-outcomes")
        let reloaded = FottyQualityStore(defaults: defaults, storageKey: "watch-outcomes")
        let result = reloaded.records()
        XCTAssertEqual(result.filter { $0.name == "provider_lookup" }.count, 3)
        let samples = result.filter { $0.name == "provider_delivery" }
        XCTAssertEqual(samples.count, 128)
        XCTAssertEqual(Set(samples.compactMap { $0.details["evidence_lookup_id"] }),
            Set(receipts.suffix(2).map { $0.lookupID.uuidString.lowercased() }))
        XCTAssertEqual(try JSONDecoder().decode([FottyQualityRecord].self,
            from: XCTUnwrap(defaults.data(forKey: "watch-outcomes"))), result)
    }

    func testNewEmptySearchesDoNotReviveOlderDeliverySamples() throws {
        store.recordProviderLookup(try evidenceReceipt(mode: "capped"))
        store.recordProviderLookup(try evidenceReceipt(mode: "empty"))
        store.recordProviderLookup(try evidenceReceipt(mode: "unread"))
        let records = store.records()
        XCTAssertEqual(records.filter { $0.name == "provider_lookup" }.count, 3)
        XCTAssertTrue(records.filter { $0.name == "provider_delivery" }.isEmpty)
    }

    private func evidenceReceipt(fixture: String = "private-fixture-sentinel", mode: String = "normal",
                                 date: Date = Date()) throws -> ProviderLookupReceipt {
        let generation = UUID()
        let request = StreamPlaybackRequest(matchID: fixture, displayTitle: "Liverpool vs Arsenal",
            homeTeam: "Liverpool", awayTeam: "Arsenal", category: "football", kickoffDate: date)
        var ledger = StreamAdmissionLedger()
        var evidence = StreamLookupEvidence(request: request, provider: .highfly, lookupID: ledger.id,
            configurationGeneration: generation, at: date)
        if mode == "unread" {
            evidence.unreadResponse(); ledger.finish(admitted: 0, completion: "failed")
        } else {
            let count = mode == "empty" ? 0 : (mode == "capped" ? 70 : 2)
            ledger.observe(count); evidence.readResponse(listingID: "private-listing-sentinel", entries: count)
            for index in 0..<count {
                let url = "https://media.example.test/\(mode == "capped" ? String(index) : "game").m3u8?token=private-token-sentinel"
                evidence.observeEntry(listingID: "private-listing-sentinel", index: index, url: url,
                    headers: ["User-Agent": "private-header-sentinel"], name: "Liverpool vs Arsenal", title: nil, at: date)
                let reason = mode == "capped" ? "limit" : (index == 0 ? "admitted" : "duplicate")
                ledger.record(reason); evidence.disposition(listingID: "private-listing-sentinel", index: index, reason: reason)
            }
            if mode == "normal" {
                let session = StreamSession(matchID: fixture,
                    playableURL: try XCTUnwrap(URL(string: "https://media.example.test/game.m3u8?token=private-token-sentinel")),
                    streamType: .hls, providerName: "HF1", requiredHeaders: ["User-Agent": "private-header-sentinel"])
                _ = evidence.attaching(to: session, listingID: "private-listing-sentinel", index: 0, at: date)
            }
            ledger.finish(admitted: mode == "normal" ? 1 : 0)
        }
        return try XCTUnwrap(evidence.snapshot(ledger: ledger, completion: mode == "unread" ? "failed" : "complete", at: date))
    }
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
