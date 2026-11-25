import XCTest
@testable import Fotty

final class StorageRuntimeSafetyTests: XCTestCase {
    func testBoundedFileReaderAcceptsExactLimitAndRejectsOversize() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fotty-import-test-\(UUID()).data")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(repeating: 42, count: 128 * 1024)
        try data.write(to: file)
        let exact = try await FottyPrivateBackupFileReader.read(file, maximumBytes: data.count)
        XCTAssertEqual(exact, data)
        do {
            _ = try await FottyPrivateBackupFileReader.read(file, maximumBytes: data.count - 1)
            XCTFail("Oversize encrypted files must be rejected")
        } catch { XCTAssertEqual(error as? FottyPrivateBackupError, .fileTooLarge) }
    }

    func testCancelledImportNeverPublishesItsFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fotty-cancel-test-\(UUID()).data")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([1, 2, 3]).write(to: file)
        let task = Task { try await FottyPrivateBackupFileReader.read(file) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled input was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testQualityReadBenchmarkAtRetentionLimit() throws {
        let name = "Fotty.quality.benchmark.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FottyQualityStore(defaults: defaults)
        for _ in 0..<250 { store.record(category: .playback, name: "sample", outcome: .success) }
        let started = ContinuousClock.now
        for _ in 0..<100 { XCTAssertEqual(store.records().count, 250) }
        print("QUALITY_READ_BENCHMARK_100=\(started.duration(to: .now))")
    }

    /// Jet, 8 Nov: 184 routine score refreshes evicted the previous day's
    /// playback incident from the 250-record buffer.
    func testRoutineRefreshSuccessesCannotEvictPlaybackEvidence() throws {
        let name = "Fotty.quality.routine.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FottyQualityStore(defaults: defaults)
        store.record(category: .playback, name: "terminal_failure", outcome: .failure, details: ["failure_kind": "stalled"])
        store.record(category: .footballData, name: "live_refresh", outcome: .failure, details: ["result": "provider_failure"])
        for _ in 0..<300 {
            store.record(category: .footballData, name: "live_refresh", outcome: .success, details: ["result": "live"])
        }
        let records = store.records()
        XCTAssertEqual(records.filter { $0.name == "terminal_failure" }.count, 1, "Playback evidence survives")
        XCTAssertEqual(records.filter { $0.name == "live_refresh" && $0.outcome == .failure }.count, 1,
                       "Refresh failures keep their normal retention")
        XCTAssertEqual(records.filter { $0.name == "live_refresh" && $0.outcome == .success }.count,
                       FottyQualityStore.maximumRoutineRefreshSuccesses)
        for _ in 0..<260 { store.record(category: .playback, name: "sample", outcome: .info) }
        XCTAssertEqual(store.records().count, 250, "The overall bound is unchanged")
    }

    func testQualitySnapshotReloadsExternalWritesAndClear() throws {
        let name = "Fotty.quality.reload.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let reader = FottyQualityStore(defaults: defaults)
        let writer = FottyQualityStore(defaults: defaults)
        XCTAssertTrue(reader.records().isEmpty)
        writer.record(category: .playback, name: "attempt_started", outcome: .success)
        XCTAssertEqual(reader.records().count, 1)
        writer.record(category: .playback, name: "decoded_progress", outcome: .success)
        XCTAssertEqual(reader.records().count, 2)
        writer.clear()
        XCTAssertTrue(reader.records().isEmpty)
        reader.record(category: .playback, name: "fresh", outcome: .success)
        XCTAssertEqual(writer.records().map(\.name), ["fresh"])
    }

    func testNativePairPreflightTypedDiagnosticsSurvivePersistedQualityRoundTrip() throws {
        let name = "Fotty.quality.native-pair.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FottyQualityStore(defaults: defaults)
        let stages: [NativeWatchTwoPreflightStage] = [.admission, .proxy, .validation, .isolation, .readiness, .registration]
        let outcomes: [NativeWatchTwoPreflightOutcome] = [.notEligible, .unsupported, .noCandidate,
            .staleCandidate, .staleOwner, .cancelled, .proxyFailed, .validationRejected, .isolationFailed,
            .readinessFailed, .readinessTimeout, .registrationRejected, .prepared]
        let expected = outcomes.enumerated().map { index, outcome in
            ["mode": "native_pair_preflight", "preparation_stage": stages[index % stages.count].rawValue,
             "preparation_reason": outcome.rawValue, "native_item_status": "failed",
             "native_error_domain": NativePlaybackErrorDomain.coreMedia.rawValue, "native_error_code": "-12312"]
        }
        for details in expected {
            store.record(category: .playback, name: "native_pair_preflight", outcome: .info, details: details)
        }
        let legacy = ["preparation_stage": PlaybackPreparationDiagnostic.Stage.urlPreparation.rawValue,
                      "preparation_reason": PlaybackPreparationDiagnostic.Reason.proxyStartup.rawValue]
        store.record(category: .playback, name: "legacy_preparation", outcome: .failure, details: legacy)

        let persisted = try XCTUnwrap(defaults.data(forKey: "fotty.quality.records.v1"))
        let decoded = try JSONDecoder().decode([FottyQualityRecord].self, from: persisted)
        let reloaded = FottyQualityStore(defaults: defaults).records()

        XCTAssertEqual(decoded, reloaded, "Evidence must survive storage, not merely the writer's in-memory cache")
        XCTAssertEqual(Array(reloaded.prefix(expected.count)).map(\.details), expected)
        XCTAssertEqual(Set(reloaded.compactMap { $0.details["preparation_stage"] }).intersection(Set(stages.map(\.rawValue))),
            Set(stages.map(\.rawValue)))
        XCTAssertEqual(Set(reloaded.prefix(outcomes.count).compactMap { $0.details["preparation_reason"] }), Set(outcomes.map(\.rawValue)))
        XCTAssertEqual(reloaded.last?.details, legacy, "Existing preparation diagnostics keep their finite vocabulary")
    }

    func testNativePairPreflightDiagnosticsRejectUnknownVocabularyURLsAndCredentialsWhenPersisted() throws {
        let name = "Fotty.quality.native-pair-privacy.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FottyQualityStore(defaults: defaults)
        let rejected = ["https://private.example.invalid/stream?token=secret", "Bearer_secret_123",
                        "custom_native_pair_stage", "prepared_with_credential", "authorization_secret", "api_key_secret"]
        for value in rejected {
            store.record(category: .playback, name: "native_pair_preflight", outcome: .failure, details: [
                "mode": "native_pair_preflight", "preparation_stage": value, "preparation_reason": value,
                "native_error_domain": value, "native_error_code": String(Int64.max),
                "native_item_status": value, "candidate_url": value, "unreviewed_native_pair_key": value
            ])
        }

        let persisted = try XCTUnwrap(defaults.data(forKey: "fotty.quality.records.v1"))
        let decoded = try JSONDecoder().decode([FottyQualityRecord].self, from: persisted)
        XCTAssertEqual(decoded, FottyQualityStore(defaults: defaults).records())
        XCTAssertEqual(decoded.map(\.details), Array(repeating: ["mode": "native_pair_preflight"], count: rejected.count))
        let serialized = try XCTUnwrap(String(data: persisted, encoding: .utf8))
        for value in rejected { XCTAssertFalse(serialized.contains(value), "Arbitrary provider text must never enter the persisted receipt") }
    }

    func testNativePairPreflightPersistsTypedCandidateErrorLogAndRelayEvidenceWithoutPrivateText() throws {
        let name = "Fotty.quality.native-pair-evidence.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date()
        let store = FottyQualityStore(defaults: defaults, now: { now })
        let privateURL = "https://private.example.invalid/playlist?token=credential_secret"
        let itemComment = "Media Entry URL not match previous playlist for MEDIA-SEQUENCE 18: \(privateURL)"
        let logComment = "Media Entry time value does not match previous playlist for MEDIA-SEQUENCE 19: raw_provider_comment \(privateURL)"
        let network = NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "credential_secret \(privateURL)"])
        let media = NSError(domain: "CoreMediaErrorDomain", code: -12_312,
            userInfo: [NSUnderlyingErrorKey: network, "NSDescription": itemComment])
        let item = NSError(domain: "AVFoundationErrorDomain", code: -11_867,
            userInfo: [NSUnderlyingErrorKey: media])
        let candidate = PlayerDiagnosticService().snapshot(error: item, trigger: .itemStatusFailed,
            logDomain: "CoreMediaErrorDomain", logCode: -12_312, logComment: logComment)
        let relay = LocalStreamProxyFailureEvidence(stage: .upstreamResponse, kind: .httpStatus,
            statusCode: 503, errorCode: nil, errorDomain: .http,
            recordedAt: now.addingTimeInterval(-0.5))
        var details = ["mode": "native_pair_preflight",
            "preparation_stage": NativeWatchTwoPreflightStage.readiness.rawValue,
            "preparation_reason": NativeWatchTwoPreflightOutcome.readinessFailed.rawValue,
            "native_item_status": "failed"]
        details.merge(candidate.qualityDetails) { _, observed in observed }
        details.merge(relay.qualityDetails(now: now)) { _, observed in observed }
        store.record(category: .playback, name: "native_pair_preflight", outcome: .failure, details: details)

        let persisted = try XCTUnwrap(defaults.data(forKey: "fotty.quality.records.v1"))
        let decoded = try JSONDecoder().decode([FottyQualityRecord].self, from: persisted)
        XCTAssertEqual(decoded, FottyQualityStore(defaults: defaults, now: { now }).records())
        let receipt = try XCTUnwrap(decoded.first)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(receipt.name, "native_pair_preflight")
        XCTAssertEqual(receipt.details, details, "Candidate and relay evidence must survive the persisted receipt together")
        XCTAssertEqual(receipt.details["native_failure_trigger"], "item_status_failed")
        XCTAssertEqual(receipt.details["native_error_domain"], "avfoundation")
        XCTAssertEqual(receipt.details["native_error_code"], "-11867")
        XCTAssertEqual(receipt.details["native_underlying_domain"], "url")
        XCTAssertEqual(receipt.details["native_underlying_code"], "-1005")
        XCTAssertEqual(receipt.details["native_error_depth"], "3")
        XCTAssertEqual(receipt.details["native_hls_issue"], "segment_uri_changed")
        XCTAssertEqual(receipt.details["native_log_domain"], "coremedia")
        XCTAssertEqual(receipt.details["native_log_code"], "-12312")
        XCTAssertEqual(receipt.details["native_log_hls_issue"], "segment_duration_changed")
        XCTAssertEqual(receipt.details["relay_failure_stage"], "upstream_response")
        XCTAssertEqual(receipt.details["relay_failure_kind"], "http_status")
        XCTAssertEqual(receipt.details["relay_http_status"], "503")
        XCTAssertEqual(receipt.details["relay_error_domain"], "http")
        XCTAssertEqual(receipt.details["relay_failure_age_ms"], "500")
        let serialized = try XCTUnwrap(String(data: persisted, encoding: .utf8))
        for privateValue in [privateURL, "private.example", "credential_secret", "raw_provider_comment", "MEDIA-SEQUENCE"] {
            XCTAssertFalse(serialized.contains(privateValue), "Only finite typed evidence may be persisted")
        }
    }

    func testQualitySnapshotStillExpiresWhileAppRemainsOpen() throws {
        let name = "Fotty.quality.expiry.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = FottyQualityStore(defaults: defaults, now: { clock })
        store.record(category: .playback, name: "old", outcome: .success)
        XCTAssertEqual(store.records().count, 1)
        clock = clock.addingTimeInterval(15 * 24 * 60 * 60)
        XCTAssertTrue(store.records().isEmpty)
        XCTAssertTrue(FottyQualityStore(defaults: defaults, now: { clock }).records().isEmpty)
    }

    func testQualityReadDoesNotRewriteUnchangedRecordsAndRepairsCorruption() throws {
        let name = "Fotty.quality.readonly.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FottyQualityStore(defaults: defaults)
        store.record(category: .playback, name: "sample", outcome: .success)
        let receipt = defaults.data(forKey: "fotty.quality.records.v1")
        XCTAssertEqual(store.records().count, 1)
        XCTAssertEqual(defaults.data(forKey: "fotty.quality.records.v1"), receipt)
        defaults.set(Data([0xff]), forKey: "fotty.quality.records.v1")
        XCTAssertTrue(store.records().isEmpty)
        let repaired = try XCTUnwrap(defaults.data(forKey: "fotty.quality.records.v1"))
        XCTAssertEqual(try JSONDecoder().decode([FottyQualityRecord].self, from: repaired), [])
    }

    func testOffMainQualityWriteAllowsMainObserverToRecordAndReadSnapshot() throws {
        let name = "Fotty.quality.reentrant.\(UUID())"
        let defaults = try XCTUnwrap(DiagnosticNotifyingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let mutationLock = NSLock()
        let store = FottyQualityStore(defaults: defaults, lock: mutationLock)
        let probe = DiagnosticStoreReentryProbe(quality: store, mutationLock: mutationLock)
        defaults.observeWrites(withPrefix: "fotty.quality.")
        let observed = expectation(description: "main observer reentered quality store")
        let finished = expectation(description: "off-main writer completed")
        let token = defaults.changes.addObserver(forName: DiagnosticNotifyingDefaults.changed,
            object: defaults, queue: .main) { _ in
                guard probe.claimFirstObserver() else { return }
                XCTAssertTrue(Thread.isMainThread)
                // A regression must fail instead of hanging the main test
                // runner while directly trying to reenter the locked store.
                let unlocked = probe.mutationLock.try()
                XCTAssertTrue(unlocked, "UserDefaults delivery must not hold the store lock")
                guard unlocked else { observed.fulfill(); return }
                probe.mutationLock.unlock()
                probe.quality?.record(category: .playback, name: "observer", outcome: .info)
                XCTAssertEqual(probe.quality?.records().map(\.name), ["background", "observer"])
                XCTAssertEqual(probe.quality?.ownerStatusSnapshot().retainedRecordCount, 2)
                observed.fulfill()
            }
        defer { defaults.changes.removeObserver(token) }
        DispatchQueue.global().async {
            probe.quality?.record(category: .playback, name: "background", outcome: .info)
            finished.fulfill()
        }
        wait(for: [observed, finished], timeout: 5)
        let reloaded = FottyQualityStore(defaults: defaults)
        XCTAssertEqual(reloaded.records().map(\.name), ["background", "observer"])
        XCTAssertEqual(defaults.writeCount, 2)
    }

    func testReentrantClearAndRecordsPersistLatestBoundedRevision() throws {
        let name = "Fotty.quality.clear-reentrant.\(UUID())"
        let defaults = try XCTUnwrap(DiagnosticNotifyingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let mutationLock = NSLock()
        let clock = DiagnosticTestClock()
        let store = FottyQualityStore(defaults: defaults, now: clock.next, lock: mutationLock)
        let probe = DiagnosticStoreReentryProbe(quality: store, mutationLock: mutationLock)
        defaults.observeWrites(withPrefix: "fotty.quality.")
        let finished = expectation(description: "reentrant latest revision persisted")
        let token = defaults.changes.addObserver(forName: DiagnosticNotifyingDefaults.changed,
            object: defaults, queue: .main) { _ in
                guard probe.claimFirstObserver() else { return }
                let unlocked = probe.mutationLock.try()
                XCTAssertTrue(unlocked)
                guard unlocked else { return }
                probe.mutationLock.unlock()
                probe.quality?.clear()
                XCTAssertEqual(probe.quality?.records(), [])
                for index in 0..<260 {
                    probe.quality?.record(category: .playback, name: "fresh_\(index)", outcome: .info)
                }
                XCTAssertEqual(probe.quality?.records().count, 250)
                XCTAssertFalse(probe.quality?.records().contains { $0.name == "before_clear" } ?? true)
            }
        defer { defaults.changes.removeObserver(token) }
        DispatchQueue.global().async {
            probe.quality?.record(category: .playback, name: "before_clear", outcome: .info)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        let reloaded = FottyQualityStore(defaults: defaults).records()
        XCTAssertEqual(reloaded.count, 250)
        XCTAssertTrue(reloaded.contains { $0.name == "fresh_259" })
        XCTAssertFalse(reloaded.contains { $0.name == "before_clear" })
        XCTAssertEqual(defaults.writeCount, 2, "Reentrant updates should coalesce to the latest bounded receipt")
    }

    func testOffMainQualityClearAllowsMainObserverSnapshotAndFreshRecord() throws {
        let name = "Fotty.quality.clear-notification.\(UUID())"
        let defaults = try XCTUnwrap(DiagnosticNotifyingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let mutationLock = NSLock()
        let store = FottyQualityStore(defaults: defaults, lock: mutationLock)
        store.record(category: .playback, name: "before_clear", outcome: .info)
        let probe = DiagnosticStoreReentryProbe(quality: store, mutationLock: mutationLock)
        defaults.observeWrites(withPrefix: "fotty.quality.")
        let finished = expectation(description: "off-main clear and reentrant record completed")
        let token = defaults.changes.addObserver(forName: DiagnosticNotifyingDefaults.changed,
            object: defaults, queue: .main) { _ in
                guard probe.claimFirstObserver() else { return }
                let unlocked = probe.mutationLock.try()
                XCTAssertTrue(unlocked, "Clear notifications must not hold the store lock")
                guard unlocked else { return }
                probe.mutationLock.unlock()
                XCTAssertEqual(probe.quality?.ownerStatusSnapshot().retainedRecordCount, 0)
                probe.quality?.record(category: .playback, name: "after_clear", outcome: .info)
                XCTAssertEqual(probe.quality?.records().map(\.name), ["after_clear"])
            }
        defer { defaults.changes.removeObserver(token) }
        DispatchQueue.global().async { probe.quality?.clear(); finished.fulfill() }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(FottyQualityStore(defaults: defaults).records().map(\.name), ["after_clear"])
        XCTAssertEqual(defaults.writeCount, 2)
    }

    func testOffMainPerformanceWriteAllowsReentrantSummaryClearAndNewSample() throws {
        let name = "Fotty.performance.reentrant.\(UUID())"
        let defaults = try XCTUnwrap(DiagnosticNotifyingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let mutationLock = NSLock()
        let store = FottyPerformanceStore(defaults: defaults, now: { time }, lock: mutationLock)
        let probe = DiagnosticStoreReentryProbe(performance: store, mutationLock: mutationLock)
        defaults.observeWrites(withPrefix: "fotty.performance.")
        let finished = expectation(description: "performance writer and observer completed")
        let token = defaults.changes.addObserver(forName: DiagnosticNotifyingDefaults.changed,
            object: defaults, queue: .main) { _ in
                guard probe.claimFirstObserver() else { return }
                let unlocked = probe.mutationLock.try()
                XCTAssertTrue(unlocked, "Performance notifications must not hold its store lock")
                guard unlocked else { return }
                probe.mutationLock.unlock()
                XCTAssertEqual(probe.performance?.summary().scroll?.scrollHitchRatio, 0.1)
                probe.performance?.clear()
                XCTAssertEqual(probe.performance?.summary().availability, "not_available")
                probe.performance?.record(windowStart: time, windowEnd: time, reportedBuild: "151",
                    includesMultipleVersions: false, scrollHitchRatio: 0.2)
                XCTAssertEqual(probe.performance?.summary().scroll?.scrollHitchRatio, 0.2)
            }
        defer { defaults.changes.removeObserver(token) }
        DispatchQueue.global().async {
            probe.performance?.record(windowStart: time.addingTimeInterval(-60), windowEnd: time.addingTimeInterval(-1),
                reportedBuild: "151", includesMultipleVersions: false, scrollHitchRatio: 0.1)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(FottyPerformanceStore(defaults: defaults, now: { time }).summary().scroll?.scrollHitchRatio, 0.2)
        XCTAssertLessThanOrEqual(defaults.writeCount, 5)
    }

    func testReentrantPerformancePruningDoesNotRefillNotificationDrain() throws {
        let name = "Fotty.performance.prune-reentrant.\(UUID())"
        let defaults = try XCTUnwrap(DiagnosticNotifyingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.2, forKey: "fotty.performance.scrollHitchRatio")
        defaults.set(Data([0xff]), forKey: "fotty.performance.summary.v1.scroll")
        let mutationLock = NSLock()
        let store = FottyPerformanceStore(defaults: defaults, lock: mutationLock)
        let probe = DiagnosticStoreReentryProbe(performance: store, mutationLock: mutationLock)
        defaults.observeWrites(withPrefix: "fotty.performance.")
        let finished = expectation(description: "one-shot legacy and corrupt receipt pruning completed")
        let token = defaults.changes.addObserver(forName: DiagnosticNotifyingDefaults.changed,
            object: defaults, queue: .main) { _ in
                let unlocked = probe.mutationLock.try()
                XCTAssertTrue(unlocked)
                guard unlocked else { return }
                probe.mutationLock.unlock()
                XCTAssertEqual(probe.performance?.summary().availability, "not_available")
            }
        defer { defaults.changes.removeObserver(token) }
        DispatchQueue.global().async {
            _ = probe.performance?.summary()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(defaults.writeCount, 2, "Pending removals must already appear absent to reentrant reads")
    }

    func testDiagnosticDefaultsHookCountsLogicalRemovalOnlyOnce() throws {
        let name = "Fotty.defaults.notification-hook.\(UUID())"
        let defaults = try XCTUnwrap(DiagnosticNotifyingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "fotty.quality.hook"
        defaults.observeWrites(withPrefix: "fotty.quality.")
        defaults.set(Data([1]), forKey: key)
        defaults.removeObject(forKey: key)
        XCTAssertEqual(defaults.writeCount, 2)
        defaults.set(nil, forKey: key)
        XCTAssertEqual(defaults.writeCount, 3, "A direct nil set is still a separate logical write")
        // Foundation may implement removeObject by dispatching to the set(nil)
        // override. This count identifies that implementation detail without
        // requiring every supported OS to use the same internal dispatch.
        print("DIAGNOSTIC_DEFAULTS_NESTED_REMOVE_SET=\(defaults.nestedRemovalSetCount)")
    }
}

/// Simulates the synchronous queue-main NotificationCenter bridge used by
/// UserDefaults. Posts are capped so even a notification-refill regression is
/// bounded; the explicit mutation-lock probe prevents deadlocking the runner.
private final class DiagnosticNotifyingDefaults: UserDefaults, @unchecked Sendable {
    static let changed = Notification.Name("FottyDiagnosticDefaultsTestChanged")
    let changes = NotificationCenter()
    private let stateLock = NSLock()
    private var prefix: String?
    private var writes = 0
    private var nestedRemovalSets = 0
    private let removalContextKey = "FottyDiagnosticDefaultsRemoval.\(UUID().uuidString)"

    var writeCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return writes }
    var nestedRemovalSetCount: Int { stateLock.lock(); defer { stateLock.unlock() }; return nestedRemovalSets }

    func observeWrites(withPrefix prefix: String) {
        stateLock.lock(); defer { stateLock.unlock() }
        self.prefix = prefix
        writes = 0
        nestedRemovalSets = 0
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        super.set(value, forKey: defaultName)
        if value == nil, Thread.current.threadDictionary[removalContextKey] as? String == defaultName {
            stateLock.lock()
            nestedRemovalSets += 1
            stateLock.unlock()
            return
        }
        postChange(forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        // The context is per-thread and exact-key. Do not hold an adapter lock
        // across Foundation notification delivery or suppress an observer's
        // independent write on the main thread.
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[removalContextKey]
        dictionary[removalContextKey] = defaultName
        super.removeObject(forKey: defaultName)
        if let previous { dictionary[removalContextKey] = previous }
        else { dictionary.removeObject(forKey: removalContextKey) }
        postChange(forKey: defaultName)
    }

    private func postChange(forKey key: String) {
        stateLock.lock()
        let matches = prefix.map { key.hasPrefix($0) } ?? false
        if matches { writes += 1 }
        let shouldPost = matches && writes <= 16
        stateLock.unlock()
        if shouldPost { changes.post(name: Self.changed, object: self) }
    }
}

private final class DiagnosticStoreReentryProbe: @unchecked Sendable {
    let quality: FottyQualityStore?
    let performance: FottyPerformanceStore?
    let mutationLock: NSLock
    private let observerLock = NSLock()
    private var observed = false

    init(quality: FottyQualityStore? = nil, performance: FottyPerformanceStore? = nil, mutationLock: NSLock) {
        self.quality = quality
        self.performance = performance
        self.mutationLock = mutationLock
    }

    func claimFirstObserver() -> Bool {
        observerLock.lock(); defer { observerLock.unlock() }
        guard !observed else { return false }
        observed = true
        return true
    }
}

private final class DiagnosticTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        time.addTimeInterval(0.001)
        return time
    }
}
