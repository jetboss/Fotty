import Foundation
import SwiftData
import XCTest
@testable import Fotty

@MainActor
final class SportsContinuityBridgeTests: XCTestCase {
    func testWidgetFailureIsVisibleAndRetryRecoversWithoutCloudOptIn() throws {
        let gate = try makeGate()
        let saved = fixture(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(gate.matchday.save(saved), .saved)
        gate.widgetWritesAllowed = false
        gate.bridge.retryPendingChanges()
        XCTAssertTrue(gate.bridge.presentation.widgetWriteFailed)
        XCTAssertEqual(gate.matchday.savedMatches.map(\.id), [saved.id])
        XCTAssertEqual(gate.cloud.synchronizations, 0)
        XCTAssertTrue(gate.cloud.writtenRecords.isEmpty)
        gate.widgetWritesAllowed = true
        gate.bridge.retryPendingChanges()
        XCTAssertFalse(gate.bridge.presentation.widgetWriteFailed)
        XCTAssertEqual(gate.snapshots.last?.matches.map(\.id), [saved.id])
        XCTAssertEqual(gate.cloud.synchronizations, 0)
    }

    func testPendingApplyErrorRemainsUntilVerifiedSaveThenRetryRecovers() throws {
        enum Failure: Error { case expected }
        var canSave = false
        let gate = try makeGate(save: { context in
            guard canSave else { throw Failure.expected }
            try context.save()
        })
        let remote = record(.followedCompetition(id: "cpl", name: "CPL", category: "cricket"))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true)
        gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertNotNil(gate.bridge.presentation.localError)
        gate.bridge.retryPendingChanges()
        XCTAssertNotNil(gate.bridge.presentation.localError)
        XCTAssertTrue(try gate.context.fetch(FetchDescriptor<FollowedLeagueItem>()).isEmpty)
        canSave = true
        gate.bridge.retryPendingChanges()
        XCTAssertNil(gate.bridge.presentation.localError)
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedLeagueItem>()).map(\.id), ["cpl"])
    }

    func testSyncOffJournalQuotaDoesNotBlockValidLocalWidgetOrPruneTombstones() throws {
        let gate = try makeGate()
        for index in 0..<SportsSyncValidation.maximumRecords {
            let intent = SportsPreferenceSyncIntent.followedTeam(key: "quota-team-\(index)", name: "Team \(index)", category: "football")
            XCTAssertEqual(gate.sync.upsert(intent), .saved)
            XCTAssertEqual(gate.sync.remove(intentID: intent.id), .saved)
        }
        let priorRecords = gate.sync.records
        let priorJournal = try XCTUnwrap(gate.defaults.data(forKey: "fotty.sports-sync.v1"))
        let event = fixture(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(gate.matchday.save(event), .saved)
        gate.bridge.publishLocalSnapshot()

        XCTAssertFalse(gate.sync.enabled)
        XCTAssertEqual(gate.sync.records.count, SportsSyncValidation.maximumRecords)
        XCTAssertTrue(gate.sync.records.allSatisfy(\.removed))
        XCTAssertEqual(gate.sync.records, priorRecords)
        XCTAssertEqual(gate.defaults.data(forKey: "fotty.sports-sync.v1"), priorJournal)
        XCTAssertNotNil(gate.bridge.lastError, "The sync quota remains visible to its owner")
        XCTAssertEqual(gate.cloud.synchronizations, 0)
        XCTAssertTrue(gate.cloud.writtenRecords.isEmpty)
        let snapshot = try XCTUnwrap(gate.snapshots.last)
        XCTAssertEqual(snapshot.matches.map(\.id), [event.id])
        XCTAssertNotNil(snapshot.validatedData())
        XCTAssertEqual(gate.matchday.savedMatches.map(\.id), [event.id])
    }

    func testWidgetOmitsUnsupportedAndInvalidRowsBeforeBoundingWithoutDeletingSavedMatches() throws {
        let now = Date()
        let football = fixture(at: now.addingTimeInterval(3600))
        let darts = (0..<8).map { index in
            EventReference(id: "widget-darts-\(index)", title: "Example A vs Example B", category: "darts",
                date: Int64(now.addingTimeInterval(-86_400 + Double(index)).timeIntervalSince1970),
                poster: nil, popular: nil,
                teams: .init(home: .init(name: "Example A", badge: nil), away: .init(name: "Example B", badge: nil)), sources: [])
        }
        let invalid = EventReference(id: String(repeating: "x", count: 201), title: "Example C vs Example D", category: "football",
            date: Int64(now.addingTimeInterval(1800).timeIntervalSince1970), poster: nil, popular: nil,
            teams: .init(home: .init(name: "Example C", badge: nil), away: .init(name: "Example D", badge: nil)), sources: [])
        let saved = darts + [invalid, football]
        let gate = try makeGate(initialSavedMatches: saved)
        let snapshot = try XCTUnwrap(gate.snapshots.last)
        XCTAssertEqual(snapshot.matches.map(\.id), [football.id])
        let encoded = try XCTUnwrap(snapshot.validatedData())
        XCTAssertEqual(SportsWidgetSnapshot.decode(encoded), snapshot)
        XCTAssertEqual(Set(gate.matchday.savedMatches.map(\.id)), Set(saved.map(\.id)))
        XCTAssertEqual(gate.matchday.savedMatches.count, saved.count)
    }

    func testAllUnsupportedSavedRowsPublishValidEmptyWidgetWithoutRemovingBookmarks() throws {
        let darts = EventReference(id: "widget-darts-only", title: "Example A vs Example B", category: "darts",
            date: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: nil,
            teams: .init(home: .init(name: "Example A", badge: nil), away: .init(name: "Example B", badge: nil)), sources: [])
        let gate = try makeGate(initialSavedMatches: [darts])
        let snapshot = try XCTUnwrap(gate.snapshots.last)
        XCTAssertTrue(snapshot.matches.isEmpty)
        XCTAssertNotNil(snapshot.validatedData())
        XCTAssertEqual(gate.matchday.savedMatches.map(\.id), [darts.id])
    }

    func testVolatileFallbackPreservesPriorAppliedFollowsAndJournalWithSyncOnOrOff() throws {
        for enabled in [false, true] {
            var storageAvailable = true
            let gate = try makeGate(storageAvailable: { storageAvailable })
            gate.context.insert(FollowedTeamItem(key: "football|liverpool", teamName: "Liverpool", sportCategory: "football"))
            gate.context.insert(FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket"))
            try gate.context.save()
            gate.bridge.publishLocalSnapshot()
            if enabled { gate.sync.setEnabled(true); gate.bridge.refresh() }
            XCTAssertEqual(gate.sync.activeIntents.filter { $0.kind == .followedTeam || $0.kind == .followedCompetition }.count, 2)

            // Simulate a new launch that retains durable defaults/receipts but
            // could not open its SwiftData store. This empty context must never
            // be interpreted as an explicit removal of the saved follows.
            storageAvailable = false
            let emptySchema = Schema([FollowedTeamItem.self, FollowedLeagueItem.self])
            let emptyContainer = try ModelContainer(for: emptySchema,
                configurations: ModelConfiguration(schema: emptySchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            let restoredSync = SportsPreferenceSyncStore(defaults: gate.defaults, client: gate.cloud, originStore: gate.originStore)
            let priorRecords = restoredSync.records
            let priorJournal = try XCTUnwrap(gate.defaults.data(forKey: "fotty.sports-sync.v1"))
            let priorApplied = try XCTUnwrap(gate.defaults.data(forKey: "fotty.sports-sync.bridge.applied.v1"))
            let priorTracked = try XCTUnwrap(gate.defaults.stringArray(forKey: "fotty.sports-sync.bridge.local-intents.v1"))
            let priorCloud = gate.cloud.values
            let priorWrites = gate.cloud.writtenRecords
            let priorSynchronizations = gate.cloud.synchronizations
            var saves = 0
            var widgetWrites = 0
            let fallback = SportsContinuityBridge(defaults: gate.defaults, sync: restoredSync,
                matchday: gate.matchday, catalog: MatchListViewModel(refreshSchedule: { nil }),
                saveContext: { _ in saves += 1 }, publishWidget: { _ in widgetWrites += 1; return true },
                storageAvailable: { false })
            fallback.configure(modelContext: emptyContainer.mainContext)
            fallback.refresh()
            fallback.publishLocalSnapshot()

            XCTAssertEqual(restoredSync.enabled, enabled)
            XCTAssertEqual(restoredSync.records, priorRecords)
            XCTAssertEqual(gate.defaults.data(forKey: "fotty.sports-sync.v1"), priorJournal)
            XCTAssertEqual(gate.defaults.data(forKey: "fotty.sports-sync.bridge.applied.v1"), priorApplied)
            XCTAssertEqual(gate.defaults.stringArray(forKey: "fotty.sports-sync.bridge.local-intents.v1"), priorTracked)
            XCTAssertEqual(gate.cloud.values, priorCloud)
            XCTAssertEqual(gate.cloud.writtenRecords, priorWrites)
            XCTAssertEqual(gate.cloud.synchronizations, priorSynchronizations)
            XCTAssertEqual(saves, 0)
            XCTAssertEqual(widgetWrites, 0, "An empty fallback must not replace a healthy sports widget snapshot")
            XCTAssertTrue(try emptyContainer.mainContext.fetch(FetchDescriptor<FollowedTeamItem>()).isEmpty)
            XCTAssertTrue(try emptyContainer.mainContext.fetch(FetchDescriptor<FollowedLeagueItem>()).isEmpty)
            XCTAssertNotNil(fallback.lastError)
        }
    }

    func testLosingStorageAfterConfigurationCannotApplyQueuedRemoteIntent() async throws {
        var storageAvailable = true
        let gate = try makeGate(storageAvailable: { storageAvailable })
        gate.sync.setEnabled(true)
        let incoming = record(.followedCompetition(id: "cpl", name: "Caribbean Premier League", category: "cricket"))
        gate.cloud.values[SportsSyncValidation.cloudSlotKey(for: incoming)] = try XCTUnwrap(SportsSyncValidation.encode(incoming))
        gate.sync.refresh() // Accepted transport receipt, not yet applied to the domain.
        storageAvailable = false
        let priorRecords = gate.sync.records
        let priorApplied = gate.defaults.data(forKey: "fotty.sports-sync.bridge.applied.v1")
        let priorSnapshots = gate.snapshots
        let priorWrites = gate.cloud.writtenRecords
        let priorSynchronizations = gate.cloud.synchronizations
        gate.bridge.refresh()
        gate.bridge.publishLocalSnapshot()
        // Observation work scheduled before availability changed must recheck
        // the same guard after yielding, not publish a delayed destructive echo.
        for _ in 0..<8 { await Task.yield() }
        XCTAssertTrue(try gate.context.fetch(FetchDescriptor<FollowedLeagueItem>()).isEmpty)
        XCTAssertEqual(gate.sync.records, priorRecords)
        XCTAssertEqual(gate.defaults.data(forKey: "fotty.sports-sync.bridge.applied.v1"), priorApplied)
        XCTAssertEqual(gate.snapshots, priorSnapshots)
        XCTAssertEqual(gate.cloud.writtenRecords, priorWrites)
        XCTAssertEqual(gate.cloud.synchronizations, priorSynchronizations)
        XCTAssertNotNil(gate.bridge.lastError)
    }

    func testBlockedConfigurationCanConfigureWhenDurableStorageReturns() throws {
        var storageAvailable = false
        let gate = try makeGate(storageAvailable: { storageAvailable })
        XCTAssertTrue(gate.snapshots.isEmpty)
        XCTAssertTrue(gate.sync.records.isEmpty)
        gate.context.insert(FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket"))
        try gate.context.save()
        storageAvailable = true
        gate.bridge.configure(modelContext: gate.context)
        XCTAssertTrue(gate.sync.activeIntents.contains { $0.kind == .followedCompetition && $0.key == "cpl" })
        XCTAssertFalse(gate.snapshots.isEmpty)
        XCTAssertNil(gate.bridge.lastError)
    }

    func testAllWholeSportRemoteFollowsRestoreWithoutChangingTeamsAlertsOrFPL() throws {
        let gate = try makeGate()
        try SportsInterestPreferences.setEnabled("darts", enabled: true, in: gate.defaults)
        gate.defaults.set(321, forKey: "fotty.user.fplManagerId")
        gate.context.insert(FollowedTeamItem(key: "football|liverpool", teamName: "Liverpool", sportCategory: "football", alertsEnabled: true))
        try gate.context.save()
        for (index, sport) in SportsSyncValidation.supportedWholeSportIDs.sorted().enumerated() {
            let incoming = record(.followedSport(sport), revision: Int64(100 + index))
            gate.cloud.values[SportsSyncValidation.cloudSlotKey(for: incoming)] = try XCTUnwrap(SportsSyncValidation.encode(incoming))
        }
        gate.sync.setEnabled(true)
        gate.bridge.refresh()
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: gate.defaults), SportsInterestPreferences.supportedIDs)
        XCTAssertFalse(gate.sync.records.contains { $0.intent.category == "darts" })
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).first?.alertsEnabled, true)
        XCTAssertEqual(gate.defaults.integer(forKey: "fotty.user.fplManagerId"), 321)
        XCTAssertTrue(gate.snapshots.last?.matches.isEmpty == true, "Following a sport must not fabricate saved widget matches")
    }

    func testWholeSportRemovalIsIndependentAndDoesNotEraseExistingCompetition() throws {
        let gate = try makeGate()
        gate.context.insert(FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket"))
        try gate.context.save()
        try SportsInterestPreferences.setEnabled("cricket", enabled: true, in: gate.defaults)
        try SportsInterestPreferences.setEnabled("tennis", enabled: true, in: gate.defaults)
        try SportsInterestPreferences.setEnabled("darts", enabled: true, in: gate.defaults)
        gate.bridge.publishLocalSnapshot()
        let removed = record(.followedSport("cricket"), removed: true)
        gate.cloud.values[SportsSyncValidation.cloudSlotKey(for: removed)] = try XCTUnwrap(SportsSyncValidation.encode(removed))
        gate.sync.setEnabled(true); gate.bridge.refresh()
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: gate.defaults), ["tennis", "darts"])
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedLeagueItem>()).map(\.id), ["cpl"])
        XCTAssertTrue(gate.sync.records.first { $0.intent.id == removed.intent.id }?.removed == true)
    }

    func testLocalDartsDoesNotBlockReviewedSportPublicationWithSyncOffOrOn() throws {
        let gate = try makeGate()
        try SportsInterestPreferences.setEnabled("darts", enabled: true, in: gate.defaults)
        try SportsInterestPreferences.setEnabled("cricket", enabled: true, in: gate.defaults)
        gate.bridge.publishLocalSnapshot()
        XCTAssertFalse(gate.sync.enabled)
        XCTAssertNil(gate.bridge.lastError)
        XCTAssertEqual(gate.sync.activeIntents.filter { $0.kind == .followedSport }.map(\.key), ["cricket"])
        XCTAssertTrue(gate.cloud.writtenRecords.isEmpty)
        gate.sync.setEnabled(true)
        gate.bridge.refresh()
        XCTAssertNil(gate.bridge.lastError)
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: gate.defaults), ["cricket", "darts"])
        XCTAssertFalse(gate.sync.records.contains { $0.intent.category == "darts" })
        XCTAssertFalse(gate.cloud.writtenRecords.contains { $0.intent.category == "darts" })
        XCTAssertTrue(gate.cloud.writtenRecords.contains { $0.intent.kind == .followedSport && $0.intent.key == "cricket" })
    }

    func testFailedWholeSportApplicationWaitsWithoutDestructiveCloudEchoAndRetries() throws {
        var failWrites = true
        let gate = try makeGate(sportWriter: { sport, enabled, defaults in
            if failWrites { throw CocoaError(.fileWriteUnknown) }
            try SportsInterestPreferences.setEnabled(sport, enabled: enabled, in: defaults)
        })
        let incoming = record(.followedSport("cricket"))
        let key = SportsSyncValidation.cloudSlotKey(for: incoming)
        gate.cloud.values[key] = try XCTUnwrap(SportsSyncValidation.encode(incoming))
        gate.sync.setEnabled(true); gate.bridge.refresh(); gate.bridge.publishLocalSnapshot()
        XCTAssertTrue(SportsInterestPreferences.selectedIDs(in: gate.defaults).isEmpty)
        XCTAssertEqual(gate.sync.records.first { $0.intent.id == incoming.intent.id }, incoming)
        XCTAssertEqual(SportsSyncValidation.decode(try XCTUnwrap(gate.cloud.values[key])), incoming)
        XCTAssertNotNil(gate.bridge.lastError)
        failWrites = false
        gate.bridge.refresh()
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: gate.defaults), ["cricket"])
        XCTAssertFalse(gate.sync.records.first { $0.intent.id == incoming.intent.id }?.removed == true)
    }

    func testMalformedLocalWholeSportStorageCannotPublishRemovalOfAcceptedSport() throws {
        let gate = try makeGate()
        try SportsInterestPreferences.setEnabled("cricket", enabled: true, in: gate.defaults)
        gate.bridge.publishLocalSnapshot()
        let accepted = try XCTUnwrap(gate.sync.records.first { $0.intent.kind == .followedSport })
        gate.defaults.set("malformed", forKey: SportsInterestPreferences.storageKey)
        gate.bridge.publishLocalSnapshot()
        XCTAssertEqual(gate.sync.records.first { $0.intent.id == accepted.intent.id }, accepted)
        XCTAssertEqual(gate.defaults.string(forKey: SportsInterestPreferences.storageKey), "malformed")
        XCTAssertFalse(gate.sync.enabled)
        XCTAssertNotNil(gate.bridge.lastError)
    }

    func testRemoteTeamRestorationDoesNotEnableDeviceAlertsOrTouchFPL() throws {
        let gate = try makeGate()
        gate.defaults.set(123456, forKey: "fotty.user.fplManagerId")
        let identity = SportsTeamIdentity(displayName: "Liverpool", sportCategory: "football", badgeURL: nil)
        let remote = record(.followedTeam(key: identity.id, name: identity.displayName, category: identity.sportCategory))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true)
        gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        let restored = try XCTUnwrap(gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).first)
        XCTAssertEqual(restored.teamName, "Liverpool")
        XCTAssertEqual(restored.alertsEnabled, false)
        XCTAssertEqual(gate.defaults.integer(forKey: "fotty.user.fplManagerId"), 123456)
    }

    func testExistingFollowAlertChoiceSurvivesIncomingFollowAndCompetitionRestore() throws {
        let gate = try makeGate()
        let team = FollowedTeamItem(key: "football|liverpool", teamName: "Liverpool", sportCategory: "football", alertsEnabled: true)
        gate.context.insert(team); try gate.context.save()
        gate.bridge.publishLocalSnapshot()
        let remote = record(.followedTeam(key: "football|liverpool", name: "Liverpool", category: "football"))
        let league = record(.followedCompetition(id: "cpl", name: "CPL", category: "cricket"), revision: 101)
        for record in [remote, league] {
            gate.cloud.values[SportsSyncValidation.cloudKey(for: record.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(record))
        }
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).count, 1)
        XCTAssertEqual(team.alertsEnabled, true)
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedLeagueItem>()).first?.id, "cpl")
    }

    func testMissingForeignPlanRemainsAnIntentNotAnInventedFixtureOrStream() throws {
        let gate = try makeGate()
        let match = SportsPlannedMatchIdentity(id: "missing", title: "Liverpool vs Chelsea", category: "football",
            homeName: "Liverpool", awayName: "Chelsea", kickoff: Date(), competitionID: "premier-league")
        let remote = record(.plannedMatch(match))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertTrue(gate.matchday.savedMatches.isEmpty)
        XCTAssertEqual(gate.sync.activeIntents.first { $0.kind == .plannedMatch }?.match?.id, "missing")
        XCTAssertTrue(gate.snapshots.last?.matches.isEmpty == true)
    }

    func testNoDefaultFalseIntentOverwritesIncomingHomePreference() throws {
        let gate = try makeGate()
        XCTAssertNil(gate.defaults.object(forKey: HomeInterestPreferences.onlyShowSelectedKey))
        XCTAssertFalse(gate.sync.records.contains { $0.intent.key == "onlySelectedInterests" })
        let remote = record(.onlySelectedInterests(true))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertTrue(gate.defaults.bool(forKey: HomeInterestPreferences.onlyShowSelectedKey))
    }

    func testFailedRemoteModelSaveKeepsPreviousSetupAndDoesNotPublishDestructiveEcho() throws {
        enum Failure: Error { case expected }
        let gate = try makeGate(save: { _ in throw Failure.expected })
        let remote = record(.followedCompetition(id: "cpl", name: "CPL", category: "cricket"))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertTrue(try gate.context.fetch(FetchDescriptor<FollowedLeagueItem>()).isEmpty)
        XCTAssertFalse(gate.sync.records.first?.removed == true)
        XCTAssertNotNil(gate.bridge.lastError)
    }

    func testUnrelatedPendingEditsAreNotRolledBackWhenPreflightSaveFails() throws {
        enum Failure: Error { case expected }
        let gate = try makeGate(save: { _ in throw Failure.expected })
        gate.context.insert(FollowedTeamItem(key: "football|chelsea", teamName: "Chelsea", sportCategory: "football"))
        let remote = record(.followedCompetition(id: "cpl", name: "CPL", category: "cricket"))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertTrue(gate.context.hasChanges)
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).first?.teamName, "Chelsea")
    }

    /// Since the shared catalog closed (27 Oct 2026), a synced plan is confirmed
    /// against the current schedule that covers its sport.
    func testPendingPlanSurvivesRelaunchAndImportsOnlyAfterCurrentSchedule() async throws {
        let now = ScheduleTestFixtures.wholeSecond()
        let schedule = ScheduleTestFixtures.sports(kickoff: now.addingTimeInterval(3600), checkedAt: now)
        let source = MatchListViewModel(refreshSports: { schedule }, now: { now })
        await source.refresh()
        let event = try XCTUnwrap(source.playbackCatalog.first { $0.sportsFixture != nil })
        let gate = try makeGate()
        let remote = record(.plannedMatch(SportsPlannedMatchIdentity(event: event)))
        gate.cloud.values[SportsSyncValidation.cloudKey(for: remote.intent.id)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertTrue(gate.matchday.savedMatches.isEmpty)

        let restoredSync = SportsPreferenceSyncStore(defaults: gate.defaults, client: gate.cloud, originStore: gate.originStore)
        let restoredPlans = MyMatchdayStore(defaults: gate.defaults)
        let catalog = MatchListViewModel(refreshSports: { schedule }, now: { now },
                                         matchdayStore: restoredPlans)
        let relaunched = SportsContinuityBridge(defaults: gate.defaults, sync: restoredSync, matchday: restoredPlans,
            catalog: catalog, clock: { now }, publishWidget: { _ in true }, storageAvailable: { true })
        relaunched.configure(modelContext: gate.context)
        restoredSync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        relaunched.refresh()
        XCTAssertTrue(restoredPlans.savedMatches.isEmpty, "No schedule receipt must mean pending, not applied")
        await catalog.refresh()
        relaunched.refresh()
        XCTAssertEqual(restoredPlans.savedMatches.first?.id, event.id)
        XCTAssertTrue(restoredPlans.savedMatches.first?.sources.isEmpty == true, "Only the current source-free fixture was saved")
        XCTAssertFalse(restoredSync.records.first { $0.intent.id == remote.intent.id }?.removed == true)
    }

    func testScheduleReceiptUsesTheCoveringScheduleAndRequiresCurrentVerification() async {
        let now = ScheduleTestFixtures.wholeSecond()
        func model(sports: SportsFixtureCatalog.Snapshot? = nil, cricket: CricketFixtureCatalog.Snapshot? = nil) async -> MatchListViewModel {
            let model = MatchListViewModel(refreshCricket: { cricket }, refreshSports: { sports }, now: { now })
            await model.refresh()
            return model
        }
        let current = await model(sports: ScheduleTestFixtures.sports(kickoff: now.addingTimeInterval(3600), checkedAt: now))
        XCTAssertNotNil(current.scheduleReceipt(category: "basketball", matchID: "any", at: now))
        XCTAssertNil(current.scheduleReceipt(category: "cricket", matchID: "any", at: now),
                     "Cricket is confirmed only by the cricket schedule")
        XCTAssertNotNil(current.scheduleReceipt(category: "basketball", matchID: "any",
            at: now.addingTimeInterval(ScheduleReceiptPolicy.freshness)))
        XCTAssertNil(current.scheduleReceipt(category: "basketball", matchID: "any",
            at: now.addingTimeInterval(ScheduleReceiptPolicy.freshness + 1)), "A stale schedule cannot confirm")

        let unverified = await model(sports: ScheduleTestFixtures.sports(kickoff: now.addingTimeInterval(3600), checkedAt: now,
                                                                 status: .lastKnownGood))
        XCTAssertNil(unverified.scheduleReceipt(category: "basketball", matchID: "any", at: now))

        let cricket = await model(cricket: ScheduleTestFixtures.cricket(checkedAt: now))
        XCTAssertNotNil(cricket.scheduleReceipt(category: "cricket", matchID: "any", at: now))
        XCTAssertNil(cricket.scheduleReceipt(category: "football", matchID: "any", at: now))
        XCTAssertNil(MatchListViewModel(now: { now })
            .scheduleReceipt(category: "football", matchID: "any", at: now), "No schedule, no receipt")
    }

    func testFailedRemoteFollowSaveRetriesAcrossRelaunchWithoutTombstoneEcho() throws {
        enum Failure: Error { case expected }
        let gate = try makeGate(save: { _ in throw Failure.expected })
        let remote = record(.followedTeam(key: "football|liverpool", name: "Liverpool", category: "football"))
        let key = SportsSyncValidation.cloudKey(for: remote.intent.id)
        gate.cloud.values[key] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        XCTAssertTrue(try gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).isEmpty)
        XCTAssertEqual(SportsSyncValidation.decode(try XCTUnwrap(gate.cloud.values[key])), remote)

        let restoredSync = SportsPreferenceSyncStore(defaults: gate.defaults, client: gate.cloud, originStore: gate.originStore)
        let relaunched = SportsContinuityBridge(defaults: gate.defaults, sync: restoredSync,
            matchday: gate.matchday, catalog: MatchListViewModel(refreshSchedule: { nil }),
            publishWidget: { _ in true }, storageAvailable: { true })
        relaunched.configure(modelContext: gate.context)
        XCTAssertTrue(try gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).isEmpty)
        XCTAssertEqual(restoredSync.records.first { $0.intent.id == remote.intent.id }, remote,
                       "Waiting for cloud reconciliation cannot overwrite the accepted remote intent")
        restoredSync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        relaunched.refresh()
        XCTAssertEqual(try gate.context.fetch(FetchDescriptor<FollowedTeamItem>()).first?.teamName, "Liverpool")
        XCTAssertFalse(restoredSync.records.first { $0.intent.id == remote.intent.id }?.removed == true)
    }

    func testFailedRemotePlanRemovalCannotBeRevivedByPublishingOldLocalState() throws {
        enum Failure: Error { case expected }
        var failWrites = false
        let gate = try makeGate(planWriter: { data, key, defaults in
            if failWrites { throw Failure.expected }
            defaults.set(data, forKey: key)
        })
        let event = fixture(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(gate.matchday.save(event), .saved)
        gate.bridge.publishLocalSnapshot()
        let intent = SportsPreferenceSyncIntent.plannedMatch(SportsPlannedMatchIdentity(event: event))
        let removed = record(intent, removed: true)
        let key = SportsSyncValidation.cloudKey(for: intent.id)
        gate.cloud.values[key] = try XCTUnwrap(SportsSyncValidation.encode(removed))
        failWrites = true
        gate.sync.setEnabled(true); gate.sync.receiveExternalChange(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        gate.bridge.refresh()
        gate.bridge.publishLocalSnapshot()
        XCTAssertEqual(gate.matchday.savedMatches.first?.id, event.id, "Failed persistence must keep accepted local data")
        XCTAssertEqual(gate.sync.records.first { $0.intent.id == intent.id }, removed)
        XCTAssertEqual(SportsSyncValidation.decode(try XCTUnwrap(gate.cloud.values[key])), removed)
        XCTAssertNotNil(gate.bridge.lastError)
        failWrites = false
        gate.bridge.refresh()
        XCTAssertTrue(gate.matchday.savedMatches.isEmpty)
        XCTAssertTrue(gate.sync.records.first { $0.intent.id == intent.id }?.removed == true)
    }

    func testDelayedRemotePreferenceCannotBecomePassiveLocalEcho() throws {
        for arrivesInsideMutation in [false, true] {
            let gate = try makeGate()
            gate.defaults.set(false, forKey: HomeInterestPreferences.onlyShowSelectedKey)
            gate.bridge.publishLocalSnapshot()
            gate.sync.setEnabled(true)
            let remote = record(.onlySelectedInterests(true), revision: 100)
            let key = SportsSyncValidation.cloudSlotKey(for: remote)
            let data = try XCTUnwrap(SportsSyncValidation.encode(remote))
            if arrivesInsideMutation {
                gate.cloud.beforeNextRead = { $0.acceptReceived(data, forKey: key) }
            } else { gate.cloud.values[key] = data }
            let synchronizations = gate.cloud.synchronizations
            gate.bridge.publishLocalSnapshot() // No external-change notification.
            XCTAssertEqual(gate.sync.records.first { $0.intent.id == remote.intent.id }, remote)
            XCTAssertTrue(gate.defaults.bool(forKey: HomeInterestPreferences.onlyShowSelectedKey))
            XCTAssertEqual(gate.cloud.values[key], data)
            XCTAssertFalse(gate.cloud.writtenRecords.contains {
                $0.intent.id == remote.intent.id && $0.revision > 100 && $0.intent.flag == false
            }, "A stale domain snapshot must not create false revision101")
            XCTAssertEqual(gate.cloud.synchronizations, synchronizations, "CAS reads must not force another synchronize")
        }
    }

    func testDelayedRemoteTombstoneCannotBeRevivedByPassiveSnapshot() throws {
        let gate = try makeGate()
        gate.defaults.set(false, forKey: HomeInterestPreferences.onlyShowSelectedKey)
        gate.bridge.publishLocalSnapshot(); gate.sync.setEnabled(true)
        let removed = record(.onlySelectedInterests(false), revision: 100, removed: true)
        let key = SportsSyncValidation.cloudSlotKey(for: removed)
        let data = try XCTUnwrap(SportsSyncValidation.encode(removed))
        gate.cloud.beforeNextRead = { $0.acceptReceived(data, forKey: key) }
        gate.bridge.publishLocalSnapshot()
        XCTAssertEqual(gate.sync.records.first { $0.intent.id == removed.intent.id }, removed)
        XCTAssertNil(gate.defaults.object(forKey: HomeInterestPreferences.onlyShowSelectedKey))
        XCTAssertEqual(gate.cloud.values[key], data)
        XCTAssertFalse(gate.cloud.writtenRecords.contains { $0.intent.id == removed.intent.id && $0.revision > 100 })
    }

    func testDelayedRemoteAdditionCannotBeRemovedByStaleAbsentDomainSnapshot() throws {
        let gate = try makeGate()
        gate.defaults.set(false, forKey: HomeInterestPreferences.onlyShowSelectedKey)
        gate.bridge.publishLocalSnapshot(); gate.sync.setEnabled(true)
        gate.defaults.removeObject(forKey: HomeInterestPreferences.onlyShowSelectedKey)
        let remote = record(.onlySelectedInterests(true), revision: 100)
        let key = SportsSyncValidation.cloudSlotKey(for: remote)
        let data = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.cloud.beforeNextRead = { $0.acceptReceived(data, forKey: key) }
        gate.bridge.publishLocalSnapshot()
        XCTAssertEqual(gate.sync.records.first { $0.intent.id == remote.intent.id }, remote)
        XCTAssertTrue(gate.defaults.bool(forKey: HomeInterestPreferences.onlyShowSelectedKey))
        XCTAssertEqual(gate.cloud.values[key], data)
        XCTAssertFalse(gate.cloud.writtenRecords.contains { $0.intent.id == remote.intent.id && $0.revision > 100 && $0.removed })
    }

    func testActualSavedMatchToggleStillPublishesWhileSyncIsEnabled() throws {
        let gate = try makeGate()
        gate.sync.setEnabled(true)
        let event = fixture(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(gate.matchday.toggle(event), .saved)
        gate.bridge.publishLocalSnapshot()
        let first = try XCTUnwrap(gate.sync.records.first { $0.intent.kind == .plannedMatch })
        XCTAssertFalse(first.removed)
        XCTAssertEqual(gate.matchday.toggle(event), .removed)
        gate.bridge.publishLocalSnapshot()
        let removed = try XCTUnwrap(gate.sync.records.first { $0.intent.id == first.intent.id })
        XCTAssertTrue(removed.removed)
        XCTAssertGreaterThan(removed.revision, first.revision)
        XCTAssertEqual(gate.cloud.values[SportsSyncValidation.cloudSlotKey(for: removed)], SportsSyncValidation.encode(removed))
    }

    func testOffModeJournalsLocalChangeWithoutApplyingOrContactingRemote() throws {
        let gate = try makeGate()
        gate.defaults.set(false, forKey: HomeInterestPreferences.onlyShowSelectedKey)
        gate.bridge.publishLocalSnapshot(); gate.sync.setEnabled(true)
        let remote = record(.onlySelectedInterests(true), revision: 100)
        gate.cloud.values[SportsSyncValidation.cloudSlotKey(for: remote)] = try XCTUnwrap(SportsSyncValidation.encode(remote))
        gate.sync.refresh() // Journal receipt exists, but domain has not applied it.
        gate.sync.setEnabled(false)
        let before = gate.cloud.values
        let synchronizations = gate.cloud.synchronizations
        gate.bridge.publishLocalSnapshot()
        XCTAssertFalse(gate.defaults.bool(forKey: HomeInterestPreferences.onlyShowSelectedKey))
        XCTAssertEqual(gate.sync.activeIntents.first { $0.key == "onlySelectedInterests" }?.flag, false)
        XCTAssertEqual(gate.cloud.values, before)
        XCTAssertEqual(gate.cloud.synchronizations, synchronizations)
    }

    private func fixture(at date: Date) -> EventReference {
        EventReference(id: "fixture-liverpool-chelsea", title: "Liverpool vs Chelsea", category: "football",
            date: Int64(date.timeIntervalSince1970), poster: nil, popular: nil,
            teams: .init(home: .init(name: "Liverpool", badge: nil), away: .init(name: "Chelsea", badge: nil)),
            sources: [], competitionID: "premier-league")
    }

    private func record(_ intent: SportsPreferenceSyncIntent, revision: Int64 = 100, removed: Bool = false) -> SportsPreferenceSyncRecord {
        .init(version: 1, intent: intent, revision: revision, origin: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
              removed: removed, modifiedAt: Date())
    }

    private func makeGate(save: @escaping (ModelContext) throws -> Void = { try $0.save() },
                          planWriter: MyMatchdayStore.PersistenceWriter? = nil,
                          sportWriter: @escaping @MainActor (String, Bool, UserDefaults) throws -> Void = { sport, enabled, defaults in
                              try SportsInterestPreferences.setEnabled(sport, enabled: enabled, in: defaults)
                          },
                          storageAvailable: @escaping @MainActor () -> Bool = { true },
                          initialSavedMatches: [EventReference] = []) throws -> Gate {
        let suite = "Fotty.SportsBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let schema = Schema([FollowedTeamItem.self, FollowedLeagueItem.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let gate = Gate(defaults: defaults, container: container)
        gate.context.autosaveEnabled = false
        gate.sync = SportsPreferenceSyncStore(defaults: defaults, client: gate.cloud, originStore: gate.originStore)
        if let planWriter { gate.matchday = MyMatchdayStore(defaults: defaults, persistenceWriter: planWriter) }
        else { gate.matchday = MyMatchdayStore(defaults: defaults) }
        for event in initialSavedMatches { XCTAssertEqual(gate.matchday.save(event), .saved) }
        gate.bridge = SportsContinuityBridge(defaults: defaults, sync: gate.sync, matchday: gate.matchday,
            catalog: MatchListViewModel(refreshSchedule: { nil }),
            saveContext: save, publishWidget: { [weak gate] snapshot in
                guard gate?.widgetWritesAllowed == true else { return false }
                guard snapshot.validatedData() != nil else { return false }
                gate?.snapshots.append(snapshot)
                return true
            },
            writeSportInterest: sportWriter, storageAvailable: storageAvailable)
        gate.bridge.configure(modelContext: gate.context)
        return gate
    }

    @MainActor
    private final class Gate {
        let defaults: UserDefaults
        let container: ModelContainer
        let context: ModelContext
        let cloud: FakeCloud
        let originStore = FakeOrigin()
        var sync: SportsPreferenceSyncStore!
        var matchday: MyMatchdayStore!
        var bridge: SportsContinuityBridge!
        var snapshots: [SportsWidgetSnapshot] = []
        var widgetWritesAllowed = true
        init(defaults: UserDefaults, container: ModelContainer, cloud: FakeCloud? = nil) {
            self.defaults = defaults; self.container = container; self.context = container.mainContext
            self.cloud = cloud ?? FakeCloud()
        }
    }

    private final class FakeCloud: SportsPreferenceCloudClient {
        private var storage: [String: Data] = [:]
        var beforeNextRead: (@MainActor (FakeCloud) -> Void)?
        var values: [String: Data] {
            get {
                let hook = beforeNextRead; beforeNextRead = nil
                hook?(self)
                return storage
            }
            set { storage = newValue }
        }
        var accountIdentity: Data? = Data("test-account".utf8)
        var writtenRecords: [SportsPreferenceSyncRecord] = []
        var synchronizations = 0
        func acceptReceived(_ data: Data, forKey key: String) { storage[key] = data }
        func set(_ data: Data, forKey key: String) {
            storage[key] = data
            if let record = SportsSyncValidation.decode(data) { writtenRecords.append(record) }
        }
        func synchronize() -> Bool { synchronizations += 1; return true }
    }

    private final class FakeOrigin: SportsSyncWriterOriginStore {
        private var value: String?
        func load() throws -> String? { value }
        func save(_ origin: String) throws { value = origin }
    }
}
