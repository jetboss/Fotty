import CryptoKit
import XCTest
@testable import Fotty

final class StreamEvidenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let attempt = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let otherAttempt = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let lookup = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private let watch = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    // Explicit deterministic test key; production fingerprints come from the
    // existing device-local key owner, never from this fixture stand-in.
    private func digest(_ value: String) -> DeviceHMAC {
        let key = SymmetricKey(data: Data(repeating: 0x5a, count: 32))
        return DeviceHMAC(bytes: Data(HMAC<SHA256>.authenticationCode(
            for: Data(("fotty.evidence-test.v1\0" + value).utf8), using: key)))
    }

    private func provenance(scope: ProgrammeScope? = nil, provider: EvidenceProvider = .highfly,
                            contract: DeviceHMAC? = nil, listing: DeviceHMAC? = nil,
                            lookupID: UUID? = nil, configuration: UUID? = nil, watchID: UUID? = nil,
                            observedAt: Date? = nil, schemaVersion: Int = 1) -> DeliveryProvenance {
        DeliveryProvenance(schemaVersion: schemaVersion, scope: scope ?? .fixture(digest("fixture")),
            provider: provider, listing: listing ?? digest("listing"), contract: contract ?? digest("contract"),
            lookupID: lookupID ?? lookup, configurationGeneration: configuration ?? generation,
            watchID: watchID ?? watch, observedAt: observedAt ?? now)
    }

    private func viewer(_ verdict: ViewerVerdict = .confirmed, provenance: DeliveryProvenance? = nil,
                        attemptID: UUID? = nil, observedAt: Date? = nil,
                        expiry: CorrectnessExpiry? = nil) -> ProgrammeEvidence {
        ProgrammeEvidence(provenance: provenance ?? self.provenance(), attemptID: attemptID ?? attempt,
            verdict: verdict, observedAt: observedAt ?? now, expiry: expiry ?? .boundary(now.addingTimeInterval(600)))
    }

    private func metadata(_ comparison: MetadataComparison = .agrees, provenance: DeliveryProvenance? = nil,
                          comparedAt: Date? = nil, expiresAt: Date? = nil) -> DeliveryMetadataReceipt {
        DeliveryMetadataReceipt(provenance: provenance ?? self.provenance(), hasName: true, hasTitle: false,
            comparison: comparison, comparedAt: comparedAt ?? now, expiresAt: expiresAt ?? now.addingTimeInterval(300))
    }

    private func correctness(_ ledger: ProgrammeEvidenceLedger, provenance: DeliveryProvenance? = nil,
                             attemptID: UUID? = nil, expiry: CorrectnessExpiry? = nil,
                             at date: Date? = nil) -> ProgrammeCorrectness {
        ledger.correctness(for: provenance ?? self.provenance(), attemptID: attemptID ?? attempt,
            expiry: expiry ?? .boundary(now.addingTimeInterval(600)), at: date ?? now)
    }

    func testFrozenProvenanceAndEvidenceRoundTripWithoutRawIdentity() throws {
        let privateMarker = "private-account-and-delivery-marker"
        let context = provenance(scope: .channelProgramme(channel: digest("channel"), programme: digest(privateMarker)),
                                 contract: digest(privateMarker))
        let evidence = viewer(provenance: context)
        let bytes = try JSONEncoder().encode(evidence)
        XCTAssertEqual(try JSONDecoder().decode(ProgrammeEvidence.self, from: bytes), evidence)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(privateMarker))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("://"))
        let receipt = metadata(provenance: context)
        XCTAssertEqual(try JSONDecoder().decode(DeliveryMetadataReceipt.self,
            from: JSONEncoder().encode(receipt)), receipt)
        for provider in EvidenceProvider.allCases {
            let candidate = provenance(provider: provider)
            XCTAssertEqual(try JSONDecoder().decode(DeliveryProvenance.self,
                from: JSONEncoder().encode(candidate)), candidate)
        }
    }

    func testDecoderRejectsMalformedDigestsAndUnregisteredProvider() throws {
        for size in [0, 1, 31, 33, 256] {
            let encoded = try JSONEncoder().encode(DeviceHMAC(bytes: Data(repeating: 0, count: size)))
            XCTAssertThrowsError(try JSONDecoder().decode(DeviceHMAC.self, from: encoded))
        }
        let encoded = try JSONEncoder().encode(provenance())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["provider"] = "unregistered"
        XCTAssertThrowsError(try JSONDecoder().decode(DeliveryProvenance.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }

    func testMetadataAgreementIsSeparateFromExplicitCorrectnessAndContradictionWins() {
        var ledger = ProgrammeEvidenceLedger()
        XCTAssertEqual(correctness(ledger), .unknown)
        for impossible in [MetadataComparison.agrees, .contradicts] {
            XCTAssertFalse(ledger.record(DeliveryMetadataReceipt(provenance: provenance(), hasName: false,
                hasTitle: false, comparison: impossible, comparedAt: now, expiresAt: now.addingTimeInterval(300)), at: now))
        }
        XCTAssertTrue(ledger.record(metadata(.noParseableTeams), at: now))
        XCTAssertEqual(correctness(ledger), .unknown)
        XCTAssertTrue(ledger.record(metadata(), at: now))
        XCTAssertEqual(correctness(ledger), .metadataAgrees)
        XCTAssertTrue(ledger.record(metadata(.contradicts), at: now))
        XCTAssertEqual(correctness(ledger), .unknown)
        XCTAssertFalse(ledger.viewerEvidence.contains { $0.verdict == .rejected })
        XCTAssertTrue(ledger.record(viewer(), at: now))
        XCTAssertEqual(correctness(ledger), .viewerConfirmed)
    }

    func testExplicitRejectionBeatsMetadataAndTiedConfirmationButNewViewerActionCanCorrectIt() {
        for reverse in [false, true] {
            var ledger = ProgrammeEvidenceLedger()
            let records = [viewer(.confirmed), viewer(.rejected)]
            for record in reverse ? Array(records.reversed()) : records { ledger.record(record, at: now) }
            ledger.record(metadata(), at: now)
            XCTAssertEqual(correctness(ledger), .viewerRejected)
            let later = now.addingTimeInterval(1)
            ledger.record(viewer(.confirmed, observedAt: later), at: later)
            XCTAssertEqual(correctness(ledger, at: later), .viewerConfirmed)
        }
    }

    func testContextChangesImmediatelyInvalidateRetainedEvidence() {
        var ledger = ProgrammeEvidenceLedger()
        ledger.record(viewer(.rejected), at: now)
        ledger.record(metadata(), at: now)
        let alternatives = [
            provenance(scope: .fixture(digest("other-fixture"))),
            provenance(scope: .channelProgramme(channel: digest("fixture"), programme: digest("programme"))),
            provenance(provider: .penguPlay), provenance(contract: digest("renewed-contract")),
            provenance(configuration: otherAttempt)
        ]
        for alternative in alternatives { XCTAssertEqual(correctness(ledger, provenance: alternative), .unknown) }
        let sameDelivery = provenance(listing: digest("another-listing"), lookupID: otherAttempt, watchID: otherAttempt)
        XCTAssertEqual(correctness(ledger, provenance: sameDelivery), .viewerRejected,
                       "A repeated lookup of the same scoped contract is not a new programme")
    }

    func testSameChannelDifferentProgrammeAndSameProgrammeDifferentChannelAreIsolated() {
        let channel = digest("channel"), programme = digest("programme")
        let context = provenance(scope: .channelProgramme(channel: channel, programme: programme))
        var ledger = ProgrammeEvidenceLedger()
        ledger.record(viewer(provenance: context), at: now)
        for scope in [ProgrammeScope.channelProgramme(channel: digest("other"), programme: programme),
                      .channelProgramme(channel: channel, programme: digest("next"))] {
            XCTAssertEqual(correctness(ledger, provenance: provenance(scope: scope)), .unknown)
        }
    }

    func testStoredAndCurrentBoundariesAreExclusiveAndEarlierAuthorityCapsEvidence() {
        var ledger = ProgrammeEvidenceLedger()
        let end = now.addingTimeInterval(10)
        ledger.record(viewer(expiry: .boundary(end)), at: now)
        XCTAssertEqual(correctness(ledger, at: end.addingTimeInterval(-0.001)), .viewerConfirmed)
        XCTAssertEqual(correctness(ledger, at: end), .unknown)
        XCTAssertEqual(correctness(ledger, expiry: .boundary(now)), .unknown)
        XCTAssertEqual(correctness(ledger, expiry: .boundary(now.addingTimeInterval(-1))), .unknown)
        ledger.prune(at: end)
        XCTAssertEqual(ledger.count, 1, "Expired authority remains only as a bounded replay marker")
        XCTAssertEqual(correctness(ledger, at: end), .unknown)
    }

    func testAttemptOnlyNeedsExactAttemptAndCleanupDoesNotEraseBoundedEvidence() {
        var ledger = ProgrammeEvidenceLedger()
        ledger.record(viewer(expiry: .attemptOnly), at: now)
        XCTAssertEqual(correctness(ledger), .viewerConfirmed)
        XCTAssertEqual(correctness(ledger, attemptID: otherAttempt), .unknown)
        XCTAssertEqual(ledger.correctness(for: provenance(), attemptID: nil, expiry: .attemptOnly, at: now), .unknown)
        ledger.endAttempt(otherAttempt)
        XCTAssertEqual(ledger.count, 1)
        ledger.endAttempt(attempt)
        XCTAssertEqual(correctness(ledger), .unknown)
        ledger.record(viewer(), at: now)
        ledger.endAttempt(attempt)
        XCTAssertEqual(correctness(ledger, attemptID: otherAttempt), .viewerConfirmed)
        XCTAssertEqual(correctness(ledger, attemptID: otherAttempt, expiry: .attemptOnly), .unknown,
                       "Losing current programme authority restricts even a stored boundary to its original attempt")
    }

    func testAttemptOnlyMetadataRequiresExactLookupAndWatch() {
        var ledger = ProgrammeEvidenceLedger()
        ledger.record(metadata(), at: now)
        XCTAssertEqual(correctness(ledger, expiry: .attemptOnly), .metadataAgrees)
        for renewed in [provenance(lookupID: otherAttempt), provenance(watchID: otherAttempt)] {
            XCTAssertEqual(correctness(ledger, provenance: renewed, expiry: .attemptOnly), .unknown)
        }
    }

    func testRelaunchNeverRestoresAttemptEvidenceEvenWhenGivenSameAttemptUUID() throws {
        var ledger = ProgrammeEvidenceLedger()
        ledger.record(viewer(.rejected, expiry: .attemptOnly), at: now)
        XCTAssertTrue(ledger.persisted(at: now).viewerEvidence.isEmpty)
        // Also defend restoration from a manually injected or older snapshot.
        let injected = ProgrammeEvidenceLedger.Snapshot(metadataReceipts: [], viewerEvidence: ledger.viewerEvidence)
        let decoded = try JSONDecoder().decode(ProgrammeEvidenceLedger.Snapshot.self,
            from: JSONEncoder().encode(injected))
        let restored = ProgrammeEvidenceLedger(snapshot: decoded, at: now)
        XCTAssertEqual(correctness(restored), .unknown)
        ledger.endAttempt(attempt)
        ledger.record(viewer(), at: now)
        let roundTrip = try JSONDecoder().decode(ProgrammeEvidenceLedger.Snapshot.self,
            from: JSONEncoder().encode(ledger.persisted(at: now)))
        XCTAssertEqual(correctness(ProgrammeEvidenceLedger(snapshot: roundTrip, at: now)), .viewerConfirmed)
        XCTAssertEqual(correctness(ProgrammeEvidenceLedger(snapshot: roundTrip, at: now.addingTimeInterval(600)),
                                   at: now.addingTimeInterval(600)), .unknown)
    }

    func testInvalidFutureAndNonfiniteObservationsCannotCreateCorrectness() {
        let invalid = [now.addingTimeInterval(1), Date(timeIntervalSince1970: .infinity),
                       Date(timeIntervalSince1970: -.infinity), Date(timeIntervalSince1970: .nan)]
        for date in invalid {
            var ledger = ProgrammeEvidenceLedger()
            XCTAssertFalse(ledger.record(viewer(observedAt: date), at: now))
            XCTAssertFalse(ledger.record(viewer(provenance: provenance(observedAt: date)), at: now))
            XCTAssertFalse(ledger.record(metadata(comparedAt: date), at: now))
            XCTAssertFalse(ledger.record(metadata(provenance: provenance(observedAt: date)), at: now))
            XCTAssertEqual(ledger.count, 0)
        }
        for date in invalid.dropFirst() {
            var ledger = ProgrammeEvidenceLedger()
            XCTAssertFalse(ledger.record(viewer(expiry: .boundary(date)), at: now))
            XCTAssertFalse(ledger.record(metadata(expiresAt: date), at: now))
            ledger.record(viewer(), at: now)
            XCTAssertEqual(correctness(ledger, expiry: .boundary(date)), .unknown)
            XCTAssertEqual(correctness(ledger, at: date), .unknown)
            XCTAssertFalse(ledger.record(viewer(), at: date))
        }
        var ledger = ProgrammeEvidenceLedger()
        XCTAssertFalse(ledger.record(viewer(observedAt: now.addingTimeInterval(-1)), at: now))
        XCTAssertFalse(ledger.record(metadata(comparedAt: now.addingTimeInterval(-1)), at: now))
        XCTAssertFalse(ledger.record(metadata(expiresAt: now), at: now))
        XCTAssertFalse(ledger.record(viewer(expiry: .boundary(now)), at: now))
    }

    func testMalformedContextIsRejectedInMemoryAndUnknownSnapshotVersionIsNotRestored() throws {
        for context in [provenance(schemaVersion: 2), provenance(contract: DeviceHMAC(bytes: Data())),
                        provenance(listing: DeviceHMAC(bytes: Data())),
                        provenance(scope: .fixture(DeviceHMAC(bytes: Data()))),
                        provenance(scope: .channelProgramme(channel: digest("channel"), programme: DeviceHMAC(bytes: Data())))] {
            var ledger = ProgrammeEvidenceLedger()
            XCTAssertFalse(ledger.record(viewer(provenance: context), at: now))
            XCTAssertFalse(ledger.record(metadata(provenance: context), at: now))
            XCTAssertEqual(correctness(ledger, provenance: context), .unknown)
        }
        let snapshot = ProgrammeEvidenceLedger.Snapshot(schemaVersion: 2, metadataReceipts: [], viewerEvidence: [viewer()])
        XCTAssertEqual(ProgrammeEvidenceLedger(snapshot: snapshot, at: now).count, 0)
        XCTAssertThrowsError(try JSONDecoder().decode(ProgrammeEvidenceLedger.Snapshot.self,
            from: JSONEncoder().encode(snapshot)))
    }

    func testMetadataTTLAndMaximumRetentionAreExclusive() {
        var ledger = ProgrammeEvidenceLedger()
        ledger.record(metadata(expiresAt: now.addingTimeInterval(1)), at: now)
        XCTAssertEqual(correctness(ledger), .metadataAgrees)
        XCTAssertEqual(correctness(ledger, at: now.addingTimeInterval(1)), .unknown)
        let end = now.addingTimeInterval(ProgrammeEvidenceLedger.maximumRetention)
        ledger.record(viewer(expiry: .boundary(end.addingTimeInterval(1))), at: now)
        XCTAssertEqual(correctness(ledger, expiry: .boundary(end.addingTimeInterval(1)), at: end.addingTimeInterval(-1)), .viewerConfirmed)
        XCTAssertEqual(correctness(ledger, expiry: .boundary(end.addingTimeInterval(1)), at: end), .unknown)
        ledger.prune(at: end)
        XCTAssertEqual(ledger.count, 0)
    }

    func testDuplicateObservationCannotExtendAuthoritativeBoundary() {
        var ledger = ProgrammeEvidenceLedger()
        let end = now.addingTimeInterval(10)
        ledger.record(viewer(expiry: .boundary(end)), at: now)
        ledger.record(viewer(expiry: .boundary(end.addingTimeInterval(100))), at: now)
        XCTAssertEqual(ledger.viewerEvidence.count, 1)
        XCTAssertEqual(correctness(ledger, at: end), .unknown)
        ledger.record(metadata(expiresAt: end), at: now)
        ledger.record(metadata(expiresAt: end.addingTimeInterval(100)), at: now)
        XCTAssertEqual(ledger.metadataReceipts.count, 1)
        XCTAssertEqual(correctness(ledger, at: end), .unknown)
        XCTAssertFalse(ledger.record(viewer(expiry: .boundary(end.addingTimeInterval(100))), at: end),
                       "Re-emitting the same observation cannot revive an expired boundary")
        XCTAssertFalse(ledger.record(viewer(expiry: .boundary(end.addingTimeInterval(100))), at: end),
                       "A rejected first replay must not remove the original expiry")
        var metadataOnly = ProgrammeEvidenceLedger()
        metadataOnly.record(metadata(expiresAt: end), at: now)
        XCTAssertFalse(metadataOnly.record(metadata(expiresAt: end.addingTimeInterval(100)), at: end))
        XCTAssertFalse(metadataOnly.record(metadata(expiresAt: end.addingTimeInterval(100)), at: end))
    }

    func testExpiredReplayMarkersSurvivePruneAndRelaunchWithoutBecomingAuthority() throws {
        var ledger = ProgrammeEvidenceLedger()
        let end = now.addingTimeInterval(10), replayAt = end.addingTimeInterval(1)
        ledger.record(viewer(.rejected, expiry: .boundary(end)), at: now)
        ledger.record(metadata(expiresAt: end), at: now)
        XCTAssertEqual(correctness(ledger, at: end), .unknown)
        ledger.prune(at: replayAt)
        XCTAssertEqual(ledger.count, 2)
        let snapshot = ledger.persisted(at: replayAt)
        XCTAssertEqual(snapshot.viewerEvidence.count, 1)
        XCTAssertEqual(snapshot.metadataReceipts.count, 1)
        let decoded = try JSONDecoder().decode(ProgrammeEvidenceLedger.Snapshot.self,
            from: JSONEncoder().encode(snapshot))
        var restored = ProgrammeEvidenceLedger(snapshot: decoded, at: replayAt)
        for _ in 0..<2 {
            XCTAssertFalse(restored.record(viewer(.rejected, expiry: .boundary(now.addingTimeInterval(600))), at: replayAt))
            XCTAssertFalse(restored.record(viewer(.rejected, expiry: .attemptOnly), at: replayAt),
                           "Re-emitting an ended boundary as attempt-only cannot revive the same observation")
            XCTAssertFalse(restored.record(metadata(expiresAt: now.addingTimeInterval(600)), at: replayAt))
            XCTAssertEqual(correctness(restored, at: replayAt), .unknown)
        }
        var attemptOnly = ProgrammeEvidenceLedger()
        attemptOnly.record(viewer(expiry: .attemptOnly), at: now)
        XCTAssertFalse(attemptOnly.record(viewer(), at: now),
                       "The same attempt-only observation cannot later acquire persistence")
        XCTAssertTrue(attemptOnly.persisted(at: now).viewerEvidence.isEmpty)
        let retentionEnd = now.addingTimeInterval(ProgrammeEvidenceLedger.maximumRetention)
        restored.prune(at: retentionEnd)
        XCTAssertEqual(restored.count, 0)
        XCTAssertFalse(restored.record(viewer(expiry: .boundary(retentionEnd.addingTimeInterval(600))), at: retentionEnd))
        XCTAssertFalse(restored.record(metadata(expiresAt: retentionEnd.addingTimeInterval(600)), at: retentionEnd))
    }

    func testCombinedLedgerBoundKeepsNewestObservationsAndDuplicateReceiptsDoNotConsumeSpace() throws {
        var ledger = ProgrammeEvidenceLedger()
        for index in 0..<300 {
            let observed = now.addingTimeInterval(TimeInterval(index - 300))
            let context = provenance(contract: digest("contract-\(index)"), observedAt: observed)
            if index.isMultiple(of: 2) {
                let receipt = metadata(provenance: context, comparedAt: observed)
                ledger.record(receipt, at: now)
                ledger.record(receipt, at: now)
            } else {
                ledger.record(viewer(provenance: context, observedAt: observed), at: now)
            }
        }
        XCTAssertEqual(ledger.count, ProgrammeEvidenceLedger.maximumRecords)
        XCTAssertFalse(ledger.metadataReceipts.contains { $0.provenance.contract == digest("contract-0") })
        XCTAssertTrue(ledger.viewerEvidence.contains { $0.provenance.contract == digest("contract-299") })
        let snapshot = ledger.persisted(at: now)
        XCTAssertEqual(try JSONDecoder().decode(ProgrammeEvidenceLedger.Snapshot.self,
            from: JSONEncoder().encode(snapshot)), snapshot)
        let overLimit = ProgrammeEvidenceLedger.Snapshot(metadataReceipts: Array(repeating: metadata(), count: 256),
            viewerEvidence: [viewer()])
        XCTAssertThrowsError(try JSONDecoder().decode(ProgrammeEvidenceLedger.Snapshot.self,
            from: JSONEncoder().encode(overLimit)))
        let expiredAt = now.addingTimeInterval(600)
        ledger.prune(at: expiredAt)
        XCTAssertEqual(ledger.count, ProgrammeEvidenceLedger.maximumRecords)
        let fresh = provenance(contract: digest("fresh-contract"), observedAt: expiredAt)
        XCTAssertTrue(ledger.record(metadata(provenance: fresh, comparedAt: expiredAt,
            expiresAt: expiredAt.addingTimeInterval(300)), at: expiredAt))
        XCTAssertEqual(ledger.count, ProgrammeEvidenceLedger.maximumRecords,
                       "Expired replay markers share the same cap as active observations")
    }

    func testFrozenCountsKeepUnreadWebAndTruncationSeparateWithoutInventingTotals() {
        let value = FixtureLookupCounts(fixture: digest("fixture"), provider: .score808,
            window: DateInterval(start: now, duration: 60), lookups: 2,
            observedEntries: 0, uniqueObservedContracts: 0, readResponses: 1, unreadResponses: 1,
            knownEmptyResponses: 0, webOnlyLookups: 1, isTruncated: true)
        XCTAssertEqual(value.knownEmptyResponses, 0)
        XCTAssertEqual(value.unreadResponses, 1)
        XCTAssertEqual(value.webOnlyLookups, 1)
        XCTAssertTrue(value.isTruncated)
    }
}
