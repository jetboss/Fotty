import Foundation
import XCTest
@testable import Fotty

@MainActor
final class SportsPreferenceSyncTests: XCTestCase {
    private let localKey = "fotty.sports-sync.v1"

    func testDeferredStartupPublishesBeforeExternalWorkAndRejectsReentry() {
        let defaults = freshDefaults()
        let cloud = FakeCloud()
        let origin = FakeOrigin()
        let store = SportsPreferenceSyncStore(defaults: defaults, client: cloud,
            originStore: origin, deferStartup: true)
        XCTAssertEqual(origin.saves, 0, "Constructing the shared store must not call Keychain")
        var reentries = 0
        defer { origin.onLoad = nil }
        origin.onLoad = {
            reentries += 1
            XCTAssertFalse(store.prepareForUse())
            store.refresh()
            XCTAssertEqual(store.upsert(.onlySelectedInterests(true)), .rejected)
        }
        XCTAssertTrue(store.prepareForUse())
        XCTAssertGreaterThan(reentries, 0)
        let completed = reentries
        XCTAssertTrue(store.prepareForUse())
        XCTAssertEqual(reentries, completed, "Startup is idempotent after completing")
        XCTAssertEqual(store.upsert(.onlySelectedInterests(true)), .saved)
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(cloud.synchronizations, 0)
        XCTAssertEqual(cloud.writes, 0)
    }

    func testWholeSportIntentsUseAnOldClientInvisibleNamespaceAndPreserveLegacyKeys() throws {
        XCTAssertEqual(SportsSyncValidation.supportedWholeSportIDs, SportsHandoffIdentity.supportedSports)
        XCTAssertEqual(SportsSyncValidation.supportedWholeSportIDs.count, 12)
        for sport in SportsSyncValidation.supportedWholeSportIDs.sorted() {
            let value = record(.followedSport(sport), revision: 1)
            let encoded = try XCTUnwrap(SportsSyncValidation.encode(value))
            let key = SportsSyncValidation.cloudSlotKey(for: value)
            XCTAssertLessThanOrEqual(key.utf8.count, 128, "Every reviewed sport must fit iCloud's key limit")
            XCTAssertTrue(key.hasPrefix(SportsSyncValidation.sportCloudSlotPrefix))
            XCTAssertFalse(key.hasPrefix(SportsSyncValidation.cloudPrefix))
            XCTAssertFalse(key.hasPrefix(SportsSyncValidation.cloudSlotPrefix))
            XCTAssertTrue(SportsSyncValidation.acceptsCloudKey(key, record: value))
            XCTAssertFalse(SportsSyncValidation.acceptsCloudKey(SportsSyncValidation.cloudKey(for: value.intent.id), record: value))
            XCTAssertEqual(SportsSyncValidation.decode(encoded), value)
        }
        let legacy = record(.followedCompetition(id: "cpl", name: "CPL", category: "cricket"), revision: 1)
        XCTAssertTrue(SportsSyncValidation.cloudSlotKey(for: legacy).hasPrefix(SportsSyncValidation.cloudSlotPrefix))
        XCTAssertTrue(SportsSyncValidation.acceptsCloudKey(SportsSyncValidation.cloudKey(for: legacy.intent.id), record: legacy))
        XCTAssertFalse(SportsPreferenceSyncIntent.followedSport("unknown").isValid())
    }

    func testLocalOnlyDartsCannotExpandExistingCloudOrPlannedMatchWireContract() throws {
        XCTAssertTrue(SportsInterestPreferences.supportedIDs.contains("darts"))
        let darts = record(.followedSport("darts"), revision: 1)
        XCTAssertFalse(darts.isValid())
        XCTAssertNil(SportsSyncValidation.encode(darts))
        XCTAssertNil(SportsSyncValidation.decode(try JSONEncoder().encode(darts)))
        let (store, _, cloud) = make()
        XCTAssertEqual(store.upsert(darts.intent), .rejected)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(cloud.writes, 0)
        let plan = SportsPlannedMatchIdentity(id: "darts-fixture", title: "Example A vs Example B", category: "darts",
            homeName: "Example A", awayName: "Example B", kickoff: Date(), competitionID: nil)
        XCTAssertFalse(plan.isValid())
        XCTAssertFalse(SportsPreferenceSyncIntent.plannedMatch(plan).isValid())
    }

    func testWholeSportLocalChangesRemainOffByDefaultAndMergeIndependentSports() throws {
        let (store, _, cloud) = make()
        XCTAssertEqual(store.upsert(.followedSport("cricket")), .saved)
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(cloud.writes, 0)
        let tennis = record(.followedSport("tennis"), revision: 50)
        cloud.values[SportsSyncValidation.cloudSlotKey(for: tennis)] = try XCTUnwrap(SportsSyncValidation.encode(tennis))
        store.setEnabled(true)
        XCTAssertEqual(Set(store.activeIntents.filter { $0.kind == .followedSport }.map(\.key)), ["cricket", "tennis"])
        XCTAssertEqual(store.remove(intentID: tennis.intent.id), .saved)
        let removed = try XCTUnwrap(store.records.first { $0.intent.id == tennis.intent.id })
        XCTAssertTrue(removed.removed)
        XCTAssertTrue(store.activeIntents.contains { $0.kind == .followedSport && $0.key == "cricket" })
        store.refresh()
        XCTAssertTrue(store.records.first { $0.intent.id == tennis.intent.id }?.removed == true)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "Fotty.SportsSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func make(client: FakeCloud? = nil, originStore: FakeOrigin? = nil) -> (SportsPreferenceSyncStore, UserDefaults, FakeCloud) {
        let client = client ?? FakeCloud()
        let defaults = freshDefaults()
        return (SportsPreferenceSyncStore(defaults: defaults, client: client,
            originStore: originStore ?? FakeOrigin()), defaults, client)
    }

    func testOffByDefaultNeverContactsCloudAndFPLDefaultsAreUntouched() {
        let (store, defaults, cloud) = make()
        defaults.set(99999, forKey: "fotty.user.fplManagerId")
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(store.upsert(.onlySelectedInterests(true)), .saved)
        store.refresh()
        XCTAssertEqual(cloud.synchronizations, 0)
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertEqual(defaults.integer(forKey: "fotty.user.fplManagerId"), 99999)
    }

    func testEmptyBootstrapQueuesOwnSlotWithoutNotificationOrDeliveryClaim() throws {
        let (store, _, cloud) = make()
        store.upsert(.onlySelectedInterests(true))
        store.setEnabled(true)
        let local = try XCTUnwrap(store.records.first)
        XCTAssertEqual(cloud.writes, 1, "An empty unchanged store supplies no required notification")
        XCTAssertEqual(cloud.writeKeys, [SportsSyncValidation.cloudSlotKey(for: local)])
        XCTAssertLessThanOrEqual(cloud.writeKeys[0].utf16.count, 128)
        XCTAssertEqual(store.status, .updatesQueued, "Queued is not delivered/synced")
        store.refresh()
        XCTAssertEqual(cloud.writes, 1)
        XCTAssertEqual(store.status, .updatesQueued)
    }

    func testUnchangedReenableAndRelaunchNeedNoNewExternalNotification() throws {
        let writer = FakeOrigin()
        let (store, defaults, cloud) = make(originStore: writer)
        store.upsert(.onlySelectedInterests(true)); store.setEnabled(true)
        let initialOrigin = try XCTUnwrap(writer.value)
        store.setEnabled(false); store.setEnabled(true)
        XCTAssertEqual(store.status, .updatesQueued)
        XCTAssertEqual(cloud.writes, 1)
        let relaunched = SportsPreferenceSyncStore(defaults: defaults, client: cloud, originStore: writer)
        XCTAssertTrue(relaunched.enabled, "The matching secure and local writer binding may retain its existing consent")
        relaunched.refresh()
        XCTAssertEqual(relaunched.status, .updatesQueued)
        XCTAssertEqual(writer.value, initialOrigin)
        XCTAssertEqual(cloud.writes, 1)
    }

    func testFailedLocalKVSAttachmentDoesNotPublishUntilSuccessfulForegroundRetry() {
        let cloud = FakeCloud(); cloud.canSynchronize = false
        let (store, _, _) = make(client: cloud)
        store.upsert(.onlySelectedInterests(true)); store.setEnabled(true)
        XCTAssertEqual(store.status, .unavailable)
        XCTAssertEqual(store.upsert(.onlySelectedInterests(false)), .saved)
        store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange)
        XCTAssertEqual(cloud.writes, 0)
        cloud.canSynchronize = true
        store.refresh()
        XCTAssertEqual(store.status, .updatesQueued)
        XCTAssertEqual(cloud.writes, 1)
        XCTAssertEqual(store.activeIntents.first?.flag, false)
    }

    func testDisableKeepsLocalAndCloudCopiesAndStopsNetwork() {
        let (store, _, cloud) = make()
        store.upsert(.onlySelectedInterests(true))
        store.setEnabled(true)
        let old = cloud.values
        let synchronizations = cloud.synchronizations
        store.setEnabled(false)
        store.upsert(.onlySelectedInterests(false))
        store.refresh()
        store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange)
        XCTAssertEqual(store.activeIntents.first?.flag, false)
        XCTAssertEqual(cloud.values, old)
        XCTAssertEqual(cloud.synchronizations, synchronizations)
    }

    func testAccountChangeSuspendsBeforeWritingPreviousAccountIntent() {
        let (store, defaults, cloud) = make()
        store.upsert(.onlySelectedInterests(true))
        store.setEnabled(true)
        let writes = cloud.writes
        cloud.accountIdentity = Data("another-account".utf8)
        store.upsert(.onlySelectedInterests(false))
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(store.status, .accountChanged)
        XCTAssertEqual(cloud.writes, writes)
        XCTAssertFalse(defaults.bool(forKey: "fotty.sports-sync.v1.enabled"))
        XCTAssertEqual(store.activeIntents.first?.flag, false)
    }

    func testNoAccountNeverQueuesDataForFutureUnknownAccount() {
        let cloud = FakeCloud(); cloud.accountIdentity = nil
        let (store, _, _) = make(client: cloud)
        store.upsert(.onlySelectedInterests(true))
        store.setEnabled(true)
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(store.status, .unavailable)
        XCTAssertEqual(store.failureStage, .accountIdentity)
        XCTAssertEqual(cloud.writes, 0)
    }

    func testPerRecordMergePreservesIndependentConcurrentChanges() throws {
        let (store, _, cloud) = make()
        store.upsert(.onlySelectedInterests(true))
        let remote = record(.viewingWindow("90-minutes"), revision: 1)
        cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        store.setEnabled(true)
        store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        XCTAssertEqual(store.activeIntents.count, 2)
        XCTAssertEqual(store.activeIntents.first { $0.key == "onlySelectedInterests" }?.flag, true)
        XCTAssertEqual(store.activeIntents.first { $0.key == "viewingWindow" }?.name, "90-minutes")
        XCTAssertEqual(cloud.values.count, 2)
    }

    func testTombstoneCannotBeResurrectedByOldOrEqualClockUpdate() throws {
        let intent = SportsPreferenceSyncIntent.followedTeam(key: "football|liverpool", name: "Liverpool", category: "football")
        let (store, _, cloud) = make()
        store.upsert(intent)
        store.remove(intentID: intent.id)
        let removed = try XCTUnwrap(store.records.first)
        let equal = record(intent, revision: removed.revision)
        cloud.values[SportsSyncValidation.cloudKey(for: intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(equal))
        let legacyBytes = cloud.values[SportsSyncValidation.cloudKey(for: intent.id)]
        store.setEnabled(true)
        XCTAssertTrue(store.activeIntents.isEmpty)
        XCTAssertEqual(cloud.values[SportsSyncValidation.cloudKey(for: intent.id)], legacyBytes, "Legacy v1 is read-only")
        XCTAssertEqual(SportsSyncValidation.decode(try XCTUnwrap(cloud.values[SportsSyncValidation.cloudSlotKey(for: removed)]))?.removed, true)
        XCTAssertEqual(store.upsert(intent), .saved, "A later deliberate follow can create a newer revision")
        XCTAssertEqual(store.activeIntents.count, 1)
    }

    func testRevisionsOrderByLogicalClockNotWallClock() {
        let intent = SportsPreferenceSyncIntent.onlySelectedInterests(true)
        let old = record(intent, revision: 1, date: .distantFuture)
        let next = record(intent, revision: 2, date: .distantPast)
        XCTAssertTrue(next.wins(over: old))
        XCTAssertFalse(old.wins(over: next))
    }

    func testUnknownSensitiveAndWrongKeyRemoteDataAreRejectedAtomically() throws {
        let (store, _, cloud) = make()
        store.upsert(.onlySelectedInterests(true))
        let safe = try XCTUnwrap(SportsSyncValidation.encode(record(.viewingWindow("90-minutes"), revision: 2)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: safe) as? [String: Any])
        object["fpl"] = ["managerID": 123]
        cloud.values[SportsSyncValidation.cloudKey(for: "invalid")] = try JSONSerialization.data(withJSONObject: object)
        store.setEnabled(true)
        store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        XCTAssertEqual(store.activeIntents.count, 1)
        XCTAssertEqual(store.status, .invalidRemoteData)
        XCTAssertEqual(cloud.writes, 0)
    }

    func testOnlyReviewedPreferenceKeysAndSportsMayBeSynced() {
        let (store, _, _) = make()
        let invalid = SportsPreferenceSyncIntent(kind: .preference, key: "fplManagerId", category: nil,
            name: nil, flag: nil, number: 123, match: nil)
        XCTAssertEqual(store.upsert(invalid), .rejected)
        XCTAssertEqual(store.upsert(.followedTeam(key: "fpl", name: "Manager", category: "fpl")), .rejected)
        XCTAssertEqual(store.upsert(.viewingWindow("forever")), .rejected)
        XCTAssertEqual(store.upsert(.followedCompetition(id: "cpl", name: "CPL", category: "cricket")), .saved)
    }

    func testQuotaKeepsAcceptedJournalAndDoesNotEraseCloudOrTombstones() {
        let (store, _, cloud) = make()
        for index in 0..<256 {
            XCTAssertEqual(store.upsert(.followedTeam(key: "team-\(index)", name: "Team \(index)", category: "football")), .saved)
        }
        XCTAssertEqual(store.upsert(.followedTeam(key: "extra", name: "Extra", category: "football")), .storageFull)
        XCTAssertEqual(store.records.count, 256)
        store.setEnabled(true)
        let queuedWrites = cloud.writes
        store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreQuotaViolationChange)
        XCTAssertEqual(store.status, .quotaExceeded)
        XCTAssertEqual(cloud.writes, queuedWrites)
        XCTAssertEqual(store.records.count, 256)
    }

    func testPlannedMatchSerializationHasNoDeliveryOrFPLFields() throws {
        let match = SportsPlannedMatchIdentity(id: "cricket-fixture:123", title: "New Zealand vs South Africa",
            category: "cricket", homeName: "New Zealand", awayName: "South Africa",
            kickoff: Date(), competitionID: "icc")
        let data = try XCTUnwrap(SportsSyncValidation.encode(record(.plannedMatch(match), revision: 1)))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in ["sources", "headers", "cookies", "managerID", "fpl", "streamURL"] { XCTAssertFalse(text.contains(forbidden)) }
    }

    func testCanonicalWireEncodingAndOrderEquivalentRemoteDataDoNotCauseWrites() throws {
        let remote = record(.onlySelectedInterests(true), revision: 2)
        let first = try XCTUnwrap(SportsSyncValidation.encode(remote))
        for _ in 0..<10 { XCTAssertEqual(SportsSyncValidation.encode(remote), first) }
        let object = try JSONSerialization.jsonObject(with: first)
        let reordered = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        XCTAssertNotEqual(reordered, first)
        XCTAssertEqual(SportsSyncValidation.decode(reordered), remote)
        let (store, _, cloud) = make()
        cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = reordered
        store.setEnabled(true)
        store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        store.refresh()
        XCTAssertEqual(cloud.writes, 0, "Equivalent JSON must not bounce between devices as a changed record")
    }

    func testLateUnseenLegacyAndForeignSlotCannotBeOverwrittenByBootstrap() throws {
        for usesLegacy in [true, false] {
            let (store, _, cloud) = make()
            let intent = SportsPreferenceSyncIntent.onlySelectedInterests(false)
            store.upsert(intent)
            store.setEnabled(true) // Available cache is empty; no notification.
            let own = try XCTUnwrap(store.records.first)
            let remote = record(.onlySelectedInterests(true), revision: 20)
            let remoteKey = usesLegacy ? SportsSyncValidation.cloudKey(for: remote.intent.id)
                : SportsSyncValidation.cloudSlotKey(for: remote)
            let bytes = try XCTUnwrap(SportsSyncValidation.encode(remote))
            cloud.values[remoteKey] = bytes // Initial download arrives later.
            store.receiveExternalChange(reason: NSUbiquitousKeyValueStoreServerChange)
            XCTAssertEqual(store.records.first, remote)
            XCTAssertEqual(cloud.values[remoteKey], bytes)
            XCTAssertEqual(cloud.values[SportsSyncValidation.cloudSlotKey(for: own)], SportsSyncValidation.encode(own))
            XCTAssertFalse(cloud.writeKeys.contains(remoteKey))
        }
    }

    func testAvailableHigherRevisionIsMergedBeforeExplicitMutationWrites() throws {
        let (store, _, cloud) = make()
        store.upsert(.onlySelectedInterests(false)); store.setEnabled(true)
        let remote = record(.onlySelectedInterests(true), revision: 80)
        let key = SportsSyncValidation.cloudSlotKey(for: remote)
        let bytes = try XCTUnwrap(SportsSyncValidation.encode(remote))
        cloud.values[key] = bytes // No external notification delivered.
        XCTAssertEqual(store.upsert(.onlySelectedInterests(false)), .saved)
        let local = try XCTUnwrap(store.records.first)
        XCTAssertEqual(local.revision, 81)
        XCTAssertEqual(local.intent.flag, false)
        XCTAssertEqual(cloud.values[key], bytes)
        XCTAssertFalse(cloud.writeKeys.contains(key))
    }

    func testPassiveNilReceiptCannotBypassCachedRecordEvenForAlreadyRemovedRow() throws {
        let (store, _, cloud) = make()
        store.setEnabled(true)
        let removed = SportsPreferenceSyncRecord(version: 1, intent: .onlySelectedInterests(true), revision: 100,
            origin: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", removed: true, modifiedAt: Date())
        cloud.values[SportsSyncValidation.cloudSlotKey(for: removed)] = try XCTUnwrap(SportsSyncValidation.encode(removed))
        XCTAssertEqual(store.removeFromAppliedSnapshot(intentID: removed.intent.id, expected: nil), .applicationNeeded)
        XCTAssertEqual(store.upsertFromAppliedSnapshot(.onlySelectedInterests(false), expected: nil), .applicationNeeded)
        XCTAssertEqual(store.records, [removed])
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertEqual(store.upsert(.onlySelectedInterests(false)), .saved, "A deliberate explicit override is a different operation")
        XCTAssertEqual(store.records.first?.revision, 101)
        XCTAssertEqual(store.records.first?.intent.flag, false)
    }

    func testSeparateWriterSlotsMergeConcurrentSameIntentAndRemoval() throws {
        let cloud = FakeCloud()
        let (first, _, _) = make(client: cloud)
        let (second, _, _) = make(client: cloud)
        first.upsert(.onlySelectedInterests(true))
        second.upsert(.onlySelectedInterests(false))
        let firstLocal = try XCTUnwrap(first.records.first)
        let secondLocal = try XCTUnwrap(second.records.first)
        XCTAssertNotEqual(firstLocal.origin, secondLocal.origin)
        // Both bootstrap against an empty cache to model initially unseen peers.
        first.setEnabled(true)
        let firstSlot = try XCTUnwrap(cloud.values[SportsSyncValidation.cloudSlotKey(for: firstLocal)])
        cloud.values = [:]
        second.setEnabled(true)
        cloud.values[SportsSyncValidation.cloudSlotKey(for: firstLocal)] = firstSlot
        first.refresh(); second.refresh()
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(cloud.values.count, 2)
        let id = firstLocal.intent.id
        XCTAssertEqual(first.remove(intentID: id), .saved)
        second.refresh()
        XCTAssertTrue(second.activeIntents.isEmpty)
        XCTAssertTrue(first.records.first?.removed == true)
        XCTAssertEqual(first.records, second.records)
        XCTAssertTrue(cloud.writeKeys.allSatisfy { $0.hasPrefix(SportsSyncValidation.cloudSlotPrefix) })
    }

    func testV2KeyMustMatchBodyOriginAndIntentHash() throws {
        let (store, _, cloud) = make()
        store.upsert(.onlySelectedInterests(false))
        let remote = record(.onlySelectedInterests(true), revision: 2)
        let wrongOrigin = SportsPreferenceSyncRecord(version: 1, intent: remote.intent, revision: remote.revision,
            origin: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", removed: false, modifiedAt: remote.modifiedAt)
        cloud.values[SportsSyncValidation.cloudSlotKey(for: wrongOrigin)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        let accepted = store.records
        store.setEnabled(true)
        XCTAssertEqual(store.records, accepted)
        XCTAssertEqual(store.status, .invalidRemoteData)
        XCTAssertEqual(cloud.writes, 0)
    }

    func testCloudSlotPreflightDoesNotPartiallyWriteOrDeleteExistingSlots() throws {
        let (store, _, cloud) = make()
        store.upsert(.viewingWindow("90-minutes"))
        for index in 1...256 {
            let remote = SportsPreferenceSyncRecord(version: 1, intent: .onlySelectedInterests(true), revision: Int64(index),
                origin: UUID().uuidString, removed: false, modifiedAt: Date())
            cloud.values[SportsSyncValidation.cloudSlotKey(for: remote)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        }
        let before = cloud.values
        store.setEnabled(true)
        XCTAssertEqual(store.status, .quotaExceeded)
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertEqual(cloud.values, before)
        XCTAssertEqual(store.records.count, 2, "The accepted local journal is retained even when cloud slots are full")
    }

    func testCloudBytePreflightRejectsWholeWriteBatch() throws {
        let (store, _, cloud) = make()
        let match = SportsPlannedMatchIdentity(id: String(repeating: "m", count: 200),
            title: String(repeating: "😀", count: 300), category: "football",
            homeName: String(repeating: "😀", count: 160), awayName: String(repeating: "🙂", count: 160),
            kickoff: Date(), competitionID: "premier-league")
        XCTAssertEqual(store.upsert(.plannedMatch(match)), .saved)
        for index in 1...128 {
            let remote = SportsPreferenceSyncRecord(version: 1, intent: .onlySelectedInterests(true), revision: Int64(index),
                origin: UUID().uuidString, removed: false, modifiedAt: Date())
            let data = try XCTUnwrap(SportsSyncValidation.encode(remote))
            cloud.values[SportsSyncValidation.cloudSlotKey(for: remote)] = Data(repeating: 32, count: 4090 - data.count) + data
        }
        let before = cloud.values
        store.setEnabled(true)
        XCTAssertEqual(store.status, .quotaExceeded)
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertEqual(cloud.values, before)
        XCTAssertTrue(store.activeIntents.contains { $0.kind == .plannedMatch })
    }

    func testRestoredDefaultsRehomeOnlyKnownLocalRowsAndRequireFreshOptIn() throws {
        let defaults = freshDefaults()
        let oldOrigin = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let local = SportsPreferenceSyncRecord(version: 1, intent: .onlySelectedInterests(true), revision: 7,
            origin: oldOrigin, removed: true, modifiedAt: Date(timeIntervalSince1970: 1234))
        let foreign = record(.viewingWindow("90-minutes"), revision: 6)
        let data = try JSONEncoder().encode([local, foreign])
        defaults.set(data, forKey: localKey)
        defaults.set(oldOrigin, forKey: localKey + ".origin")
        defaults.set(oldOrigin, forKey: localKey + ".writer-v2")
        defaults.set(true, forKey: localKey + ".enabled")
        defaults.set(Data("test-account".utf8), forKey: localKey + ".account")
        let receipt = Data("accepted-domain-receipt".utf8)
        defaults.set(receipt, forKey: "fotty.sports-sync.bridge.applied.v1")
        let writer = FakeOrigin() // ThisDeviceOnly item did not migrate.
        let cloud = FakeCloud()
        let store = SportsPreferenceSyncStore(defaults: defaults, client: cloud, originStore: writer)
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(store.status, .deviceChanged)
        XCTAssertEqual(cloud.synchronizations, 0)
        XCTAssertEqual(cloud.writes, 0)
        let rehomed = try XCTUnwrap(store.records.first { $0.intent.id == local.intent.id })
        XCTAssertEqual(rehomed.origin, writer.value)
        XCTAssertNotEqual(rehomed.origin, oldOrigin)
        XCTAssertEqual(rehomed.revision, local.revision)
        XCTAssertEqual(rehomed.modifiedAt, local.modifiedAt)
        XCTAssertTrue(rehomed.removed)
        XCTAssertEqual(store.records.first { $0.intent.id == foreign.intent.id }, foreign)
        XCTAssertEqual(defaults.data(forKey: "fotty.sports-sync.bridge.applied.v1"), receipt)
        store.setEnabled(true)
        XCTAssertEqual(cloud.writeKeys, [SportsSyncValidation.cloudSlotKey(for: rehomed)])
        XCTAssertFalse(cloud.writeKeys.contains(SportsSyncValidation.cloudSlotKey(for: foreign)))
    }

    func testFreshReinstallRotatesSurvivingKeychainWriterAndLeavesOldCloudSlotUntouched() throws {
        let previousOrigin = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let writer = FakeOrigin(value: previousOrigin)
        let (store, _, cloud) = make(originStore: writer) // No local binding survived reinstall.
        XCTAssertNotEqual(writer.value, previousOrigin)
        XCTAssertEqual(writer.saves, 1)
        store.upsert(.onlySelectedInterests(false)); store.setEnabled(true)
        let current = try XCTUnwrap(store.records.first)
        let previous = SportsPreferenceSyncRecord(version: 1, intent: .onlySelectedInterests(true), revision: 50,
            origin: previousOrigin, removed: false, modifiedAt: Date())
        let oldKey = SportsSyncValidation.cloudSlotKey(for: previous)
        let oldData = try XCTUnwrap(SportsSyncValidation.encode(previous))
        cloud.values[oldKey] = oldData // A delayed previous-install record appears.
        store.refresh()
        XCTAssertEqual(store.records.first, previous)
        XCTAssertEqual(cloud.values[oldKey], oldData)
        XCTAssertEqual(cloud.values[SportsSyncValidation.cloudSlotKey(for: current)], SportsSyncValidation.encode(current))
        XCTAssertFalse(cloud.writeKeys.contains(oldKey))
    }

    func testKeychainFailureAndFailedMigrationNeverWriteCloudOrEraseAcceptedJournal() throws {
        for failsMigration in [false, true] {
            let defaults = freshDefaults()
            let oldOrigin = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
            let local = SportsPreferenceSyncRecord(version: 1, intent: .onlySelectedInterests(true), revision: 7,
                origin: oldOrigin, removed: true, modifiedAt: Date())
            let data = try JSONEncoder().encode([local])
            defaults.set(data, forKey: localKey)
            defaults.set(oldOrigin, forKey: localKey + ".origin")
            defaults.set(true, forKey: localKey + ".enabled")
            let writer = FakeOrigin(); writer.failLoad = !failsMigration
            let cloud = FakeCloud()
            let store = SportsPreferenceSyncStore(defaults: defaults, client: cloud, originStore: writer,
                journalWriter: { data, key, defaults in
                    if failsMigration { throw CocoaError(.fileWriteUnknown) }
                    defaults.set(data, forKey: key)
                })
            XCTAssertFalse(store.enabled)
            XCTAssertEqual(store.status, .unavailable)
            XCTAssertEqual(store.records, [local])
            XCTAssertEqual(defaults.data(forKey: localKey), data)
            store.setEnabled(true); store.refresh()
            XCTAssertFalse(store.enabled)
            XCTAssertEqual(cloud.writes, 0)
            XCTAssertEqual(cloud.synchronizations, 0)
            XCTAssertEqual(defaults.data(forKey: localKey), data)
        }
    }

    func testUnverifiedSecureWriterSaveCannotEnableOrPublish() {
        let writer = FakeOrigin(); writer.discardSaves = true
        let (store, _, cloud) = make(originStore: writer)
        XCTAssertEqual(store.status, .unavailable)
        XCTAssertEqual(store.upsert(.onlySelectedInterests(true)), .rejected)
        store.setEnabled(true)
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertEqual(cloud.synchronizations, 0)
    }

    private func record(_ intent: SportsPreferenceSyncIntent, revision: Int64, date: Date = .init()) -> SportsPreferenceSyncRecord {
        .init(version: 1, intent: intent, revision: revision, origin: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
              removed: false, modifiedAt: date)
    }

    private final class FakeCloud: SportsPreferenceCloudClient {
        var values: [String: Data] = [:]
        var accountIdentity: Data? = Data("test-account".utf8)
        var writes = 0
        var writeKeys: [String] = []
        var synchronizations = 0
        var canSynchronize = true
        func set(_ data: Data, forKey key: String) { values[key] = data; writes += 1; writeKeys.append(key) }
        func synchronize() -> Bool { synchronizations += 1; return canSynchronize }
    }

    private final class FakeOrigin: SportsSyncWriterOriginStore {
        var onLoad: (() -> Void)?
        var value: String?
        var failLoad = false
        var discardSaves = false
        var saves = 0
        init(value: String? = nil) { self.value = value }
        func load() throws -> String? {
            onLoad?()
            if failLoad { throw CocoaError(.fileReadUnknown) }
            return value
        }
        func save(_ origin: String) throws {
            saves += 1
            if !discardSaves { value = origin }
        }
    }
}
