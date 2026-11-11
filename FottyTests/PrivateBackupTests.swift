import CryptoKit
import SwiftData
import XCTest
@testable import Fotty

final class PrivateBackupTests: XCTestCase {
    @MainActor
    func testWholeSportChoicesRoundTripInBackupWithoutChangingOtherFollowChoices() throws {
        let fixture = try makeFixture()
        fixture.context.insert(FollowedTeamItem(key: "football|liverpool", teamName: "Liverpool", sportCategory: "football"))
        fixture.context.insert(FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket"))
        try fixture.context.save()
        try SportsInterestPreferences.setEnabled("cricket", enabled: true, in: fixture.defaults)
        try SportsInterestPreferences.setEnabled("tennis", enabled: true, in: fixture.defaults)
        let payload = try FottyPrivateBackupService.capture(modelContext: fixture.context, defaults: fixture.defaults, matchday: fixture.matchday)
        XCTAssertEqual(payload.preferences.followedSportIDs, ["cricket", "tennis"])
        let decoded = try JSONDecoder().decode(FottyPrivateBackupPayload.self, from: JSONEncoder().encode(payload))
        try SportsInterestPreferences.setEnabled("golf", enabled: true, in: fixture.defaults)
        _ = try FottyPrivateBackupService.restore(decoded, modelContext: fixture.context, defaults: fixture.defaults,
            matchday: fixture.matchday, reminderStore: nil)
        XCTAssertEqual(try SportsInterestPreferences.validatedIDs(in: fixture.defaults), ["cricket", "tennis"])
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<FollowedTeamItem>()).map(\.teamName), ["Liverpool"])
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<FollowedLeagueItem>()).map(\.id), ["cpl"])
    }

    func testOlderBackupWithoutWholeSportFieldDecodesAndRejectsUnreviewedIDs() throws {
        let encoded = try JSONEncoder().encode(samplePayload())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var preferences = try XCTUnwrap(root["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "followedSportIDs")
        root["preferences"] = preferences
        let legacy = try JSONDecoder().decode(FottyPrivateBackupPayload.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertNil(legacy.preferences.followedSportIDs)
        XCTAssertEqual(legacy.fpl, samplePayload().fpl)
        preferences["followedSportIDs"] = ["unreviewed"]
        root["preferences"] = preferences
        let invalid = try JSONDecoder().decode(FottyPrivateBackupPayload.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertThrowsError(try FottyPrivateBackupService.validate(invalid))
    }

    func testReplacedBackupReviewCannotPublishOrClearTheNewReviewsBusyState() {
        var review = FottyPrivateBackupReviewState()
        let fileA = samplePayload()
        let fileB = samplePayload(now: fileA.createdAt.addingTimeInterval(3600))
        let attemptA = review.begin()
        review.invalidate() // Choosing/importing B or editing the password.
        let attemptB = review.begin()

        XCTAssertFalse(review.complete(attemptA, payload: fileA))
        XCTAssertTrue(review.isWorking, "A must not stop B's progress indicator")
        XCTAssertNil(review.payload)
        XCTAssertNil(review.errorMessage)
        XCTAssertFalse(review.fail(attemptA, message: "A's stale password error"))
        XCTAssertTrue(review.isWorking)
        XCTAssertNil(review.errorMessage)

        XCTAssertTrue(review.complete(attemptB, payload: fileB))
        XCTAssertEqual(review.payload, fileB)
        XCTAssertFalse(review.isWorking)
        XCTAssertFalse(review.complete(attemptA, payload: fileA))
        XCTAssertFalse(review.fail(attemptA, message: "A failed after B succeeded"))
        XCTAssertEqual(review.payload, fileB, "B must remain the only restorable preview")
        XCTAssertNil(review.errorMessage)
    }

    func testNewBackupReviewFailureCannotBeReplacedByAnOlderSuccess() {
        var review = FottyPrivateBackupReviewState()
        let attemptA = review.begin()
        let attemptB = review.begin()

        XCTAssertTrue(review.fail(attemptB, message: "B's password was incorrect"))
        XCTAssertFalse(review.complete(attemptA, payload: samplePayload()))
        XCTAssertNil(review.payload)
        XCTAssertEqual(review.errorMessage, "B's password was incorrect")
        XCTAssertFalse(review.isWorking)
        review.clearError()
        XCTAssertNil(review.errorMessage)
    }

    func testBackupInputChangeOrDismissalRevokesCompletedAndPendingReview() {
        var review = FottyPrivateBackupReviewState()
        let completedAttempt = review.begin()
        XCTAssertTrue(review.complete(completedAttempt, payload: samplePayload()))
        review.invalidate() // A reviewed preview no longer matches current input.
        XCTAssertNil(review.payload)
        XCTAssertNil(review.errorMessage)
        XCTAssertFalse(review.isWorking)

        let pendingAttempt = review.begin()
        review.invalidate() // Dismiss before crypto finishes.
        XCTAssertFalse(review.complete(pendingAttempt, payload: samplePayload()))
        XCTAssertFalse(review.fail(pendingAttempt, message: "Finished after dismissal"))
        XCTAssertNil(review.payload)
        XCTAssertNil(review.errorMessage)
        XCTAssertFalse(review.isWorking)
    }

    func testEncryptedBackupRoundTripsAndRejectsWrongPassword() throws {
        let payload = samplePayload()
        let salt = Data((0..<16).map(UInt8.init))
        let nonce = try AES.GCM.Nonce(data: Data((16..<28).map(UInt8.init)))
        let encrypted = try FottyPrivateBackupCrypto.seal(
            payload,
            password: "correct horse battery",
            iterations: 4,
            salt: salt,
            nonce: nonce
        )

        XCTAssertFalse(String(data: encrypted, encoding: .utf8)?.contains("Arsenal") ?? true)
        XCTAssertEqual(
            try FottyPrivateBackupCrypto.open(
                encrypted,
                password: "correct horse battery",
                minimumIterations: 1
            ),
            payload
        )
        XCTAssertThrowsError(
            try FottyPrivateBackupCrypto.open(
                encrypted,
                password: "incorrect password here",
                minimumIterations: 1
            )
        ) { error in
            XCTAssertEqual(error as? FottyPrivateBackupError, .invalidPasswordOrDamagedFile)
        }
    }

    func testAcceptedStrengthBackupSurvivesAnActualFileRoundTrip() throws {
        let payload = samplePayload()
        let password = "correct horse battery"
        let encrypted = try FottyPrivateBackupCrypto.seal(
            payload,
            password: password,
            iterations: 50_000
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).fottybackup")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try encrypted.write(to: fileURL, options: .atomic)
        let reopened = try Data(contentsOf: fileURL)

        XCTAssertEqual(reopened, encrypted)
        XCTAssertEqual(try FottyPrivateBackupCrypto.open(reopened, password: password), payload)
    }

    @MainActor
    func testCaptureExcludesProviderRoutesConsentCoachHistoryAndDiagnostics() throws {
        let fixture = try makeFixture()
        fixture.context.insert(FollowedTeamItem(
            key: "football:arsenal",
            teamName: "Arsenal",
            sportCategory: "football",
            badgeURLString: "https://private.test/badge.png"
        ))
        try fixture.context.save()
        fixture.defaults.set(42, forKey: "fotty.user.fplManagerId")
        fixture.defaults.set(true, forKey: MatchdayPreferences.showKickoffClashesKey)
        fixture.defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        fixture.defaults.set(Data("SECRET_COACH_HISTORY".utf8),
            forKey: "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.42.coachMessages")
        fixture.defaults.set(Data("SECRET_DIAGNOSTIC".utf8), forKey: "fotty.quality.records.v1")

        let event = AnalyticalDataEngine.EventReference(
            id: "safe-event-id",
            title: "Arsenal vs Chelsea",
            category: "football",
            date: Int64(Date().addingTimeInterval(3_600).timeIntervalSince1970),
            poster: "https://private.test/poster.jpg",
            popular: true,
            teams: NexusATeams(
                home: NexusATeam(name: "Arsenal", badge: "https://private.test/arsenal.png"),
                away: NexusATeam(name: "Chelsea", badge: "https://private.test/chelsea.png")
            ))
        fixture.matchday.save(event)

        let payload = try FottyPrivateBackupService.capture(
            modelContext: fixture.context,
            defaults: fixture.defaults,
            matchday: fixture.matchday,
            bundle: .main
        )
        let encoded = try JSONEncoder().encode(payload)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(payload.followedTeams.first?.teamName, "Arsenal")
        XCTAssertEqual(payload.savedMatches.first?.id, "safe-event-id")
        XCTAssertEqual(payload.preferences.showKickoffClashes, true)
        for excluded in ["SECRET_PROVIDER", "SECRET_ROUTE", "SECRET_COACH_HISTORY", "SECRET_DIAGNOSTIC", "private.test"] {
            XCTAssertFalse(text.contains(excluded), "Backup leaked \(excluded)")
        }
    }

    @MainActor
    func testSavedChannelWithoutOpposingTeamBacksUpAndRestores() throws {
        let fixture = try makeFixture()
        let channel = AnalyticalDataEngine.EventReference(
            id: "channel-willow",
            title: "Willow Cricket",
            category: "cricket",
            date: nil,
            poster: nil,
            popular: false,
            teams: nil)
        fixture.matchday.save(channel)
        let savedAway = try XCTUnwrap(fixture.matchday.savedMatches.first?.awayName)
        XCTAssertTrue(savedAway.isEmpty, "Fixture should save a channel with no opposing team")

        let payload = try FottyPrivateBackupService.capture(
            modelContext: fixture.context,
            defaults: fixture.defaults,
            matchday: fixture.matchday,
            bundle: .main
        )
        XCTAssertEqual(payload.savedMatches.map(\.id), ["channel-willow"])

        let restoreFixture = try makeFixture()
        try FottyPrivateBackupService.restore(
            payload,
            modelContext: restoreFixture.context,
            defaults: restoreFixture.defaults,
            matchday: restoreFixture.matchday,
            reminderStore: nil,
            now: payload.createdAt
        )
        XCTAssertEqual(restoreFixture.matchday.savedMatches.map(\.id), ["channel-willow"])
    }

    @MainActor
    func testRestoreReplacesValidatedLocalStateAndRevokesAIConsent() throws {
        let fixture = try makeFixture()
        fixture.context.insert(FollowedTeamItem(
            key: "football:old",
            teamName: "Old Team",
            sportCategory: "football"
        ))
        try fixture.context.save()
        fixture.defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        fixture.defaults.set(true, forKey: "fotty.insights.aiConsentAccepted")
        let stagingKey = "fotty.fpl.2026-27.manager.42.transferStaging"
        fixture.defaults.set(Data("unfinished".utf8), forKey: stagingKey)
        fixture.defaults.set("preserve", forKey: "unrelated.transferStaging")

        let payload = samplePayload()
        let summary = try FottyPrivateBackupService.restore(
            payload,
            modelContext: fixture.context,
            defaults: fixture.defaults,
            matchday: fixture.matchday,
            reminderStore: nil,
            now: payload.createdAt
        )

        let teams = try fixture.context.fetch(FetchDescriptor<FollowedTeamItem>())
        XCTAssertEqual(teams.map(\.teamName), ["Arsenal"])
        XCTAssertNil(teams.first?.badgeURLString)
        XCTAssertEqual(fixture.matchday.savedMatches.map(\.id), ["match-1"])
        XCTAssertEqual(fixture.defaults.string(forKey: FottyAppearance.storageKey), "light")
        XCTAssertTrue(fixture.defaults.bool(forKey: HomeInterestPreferences.onlyShowSelectedKey))
        XCTAssertTrue(MatchdayPreferences.showsKickoffClashes(in: fixture.defaults))
        XCTAssertEqual(fixture.defaults.integer(forKey: "fotty.user.fplManagerId"), 42)
        XCTAssertFalse(fixture.defaults.bool(forKey: "fotty.fpl.smartCoachConsent"))
        XCTAssertFalse(fixture.defaults.bool(forKey: "fotty.insights.aiConsentAccepted"))
        XCTAssertNil(fixture.defaults.data(forKey: stagingKey))
        XCTAssertEqual(fixture.defaults.string(forKey: "unrelated.transferStaging"), "preserve")
        XCTAssertEqual(summary.savedMatches, 1)
    }

    func testOlderVersionOneBackupWithoutHomePreferenceStillDecodes() throws {
        let encoded = try JSONEncoder().encode(samplePayload())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var preferences = try XCTUnwrap(root["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "onlyShowSelectedHomeInterests")
        root["preferences"] = preferences

        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(FottyPrivateBackupPayload.self, from: legacyData)

        XCTAssertNil(decoded.preferences.onlyShowSelectedHomeInterests)
    }

    @MainActor
    func testOlderBackupWithoutClashPreferenceRestoresWithClashesOff() throws {
        let fixture = try makeFixture()
        fixture.defaults.set(true, forKey: MatchdayPreferences.showKickoffClashesKey)
        let encoded = try JSONEncoder().encode(samplePayload())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var preferences = try XCTUnwrap(root["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "showKickoffClashes")
        root["preferences"] = preferences
        let decoded = try JSONDecoder().decode(
            FottyPrivateBackupPayload.self,
            from: JSONSerialization.data(withJSONObject: root)
        )
        XCTAssertNil(decoded.preferences.showKickoffClashes)
        _ = try FottyPrivateBackupService.restore(
            decoded, modelContext: fixture.context, defaults: fixture.defaults,
            matchday: fixture.matchday, reminderStore: nil, now: decoded.createdAt
        )
        XCTAssertFalse(MatchdayPreferences.showsKickoffClashes(in: fixture.defaults))
        XCTAssertEqual(fixture.matchday.savedMatches.map(\.id), ["match-1"])
        XCTAssertTrue(fixture.defaults.bool(forKey: "settings.notif.kickoff"))
    }

    @MainActor
    func testInvalidBackupDoesNotMutateExistingState() throws {
        let fixture = try makeFixture()
        fixture.context.insert(FollowedTeamItem(
            key: "football:old",
            teamName: "Old Team",
            sportCategory: "football"
        ))
        try fixture.context.save()
        let valid = samplePayload()
        let duplicate = FottyPrivateBackupPayload(
            version: valid.version,
            createdAt: valid.createdAt,
            appVersion: valid.appVersion,
            appBuild: valid.appBuild,
            preferences: valid.preferences,
            followedTeams: [valid.followedTeams[0], valid.followedTeams[0]],
            followedLeagues: valid.followedLeagues,
            savedMatches: valid.savedMatches,
            fpl: valid.fpl
        )

        XCTAssertThrowsError(try FottyPrivateBackupService.restore(
            duplicate,
            modelContext: fixture.context,
            defaults: fixture.defaults,
            matchday: fixture.matchday,
            reminderStore: nil
        ))
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<FollowedTeamItem>()).map(\.teamName),
            ["Old Team"]
        )
    }

    @MainActor
    func testMatchdayWriteFailureStopsRestoreBeforeReplacingFollows() throws {
        let fixture = try makeFixture()
        fixture.context.insert(FollowedTeamItem(
            key: "football:old",
            teamName: "Old Team",
            sportCategory: "football"
        ))
        try fixture.context.save()
        let failingMatchday = MyMatchdayStore(
            defaults: fixture.defaults,
            storageKey: "test.matchday.failure",
            persistenceWriter: { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        )

        XCTAssertThrowsError(try FottyPrivateBackupService.restore(
            samplePayload(),
            modelContext: fixture.context,
            defaults: fixture.defaults,
            matchday: failingMatchday,
            reminderStore: nil
        ))
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<FollowedTeamItem>()).map(\.teamName),
            ["Old Team"]
        )
        XCTAssertTrue(failingMatchday.savedMatches.isEmpty)
    }

    private func samplePayload(now: Date = Date(timeIntervalSince1970: 1_788_115_200)) -> FottyPrivateBackupPayload {
        FottyPrivateBackupPayload(
            version: FottyPrivateBackupPayload.currentVersion,
            createdAt: now,
            appVersion: "2.0.0",
            appBuild: "47",
            preferences: .init(
                appearance: "light",
                preferredSport: "football",
                favoriteTeams: ["Arsenal"],
                kickoffUpdates: true,
                goalUpdates: true,
                fullTimeUpdates: true,
                spoilerProtection: false,
                onlyShowSelectedHomeInterests: true,
                showKickoffClashes: true
            ),
            followedTeams: [
                .init(
                    key: "football:arsenal",
                    teamName: "Arsenal",
                    sportCategory: "football",
                    alertsEnabled: true,
                    createdAt: now
                )
            ],
            followedLeagues: [],
            savedMatches: [
                .init(
                    id: "match-1",
                    title: "Arsenal vs Chelsea",
                    category: "football",
                    date: Int64(now.addingTimeInterval(3_600).timeIntervalSince1970),
                    popular: true,
                    homeName: "Arsenal",
                    awayName: "Chelsea",
                    savedAt: now
                )
            ],
            fpl: .init(
                managerID: 42,
                season: FPLSeasonIdentifier.currentLabel(at: now),
                localDraft: nil,
                showsPublishedSquad: false,
                scenarios: [],
                decisionJournal: [],
                reviews: [],
                coachProfile: .default
            )
        )
    }

    @MainActor
    private func makeFixture() throws -> (
        defaults: UserDefaults,
        container: ModelContainer,
        context: ModelContext,
        matchday: MyMatchdayStore
    ) {
        let suite = "PrivateBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let configuration = ModelConfiguration(schema: LocalDataStore.appSchema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalDataStore.appSchema, configurations: configuration)
        let matchday = MyMatchdayStore(defaults: defaults, storageKey: "test.matchday")
        return (defaults, container, container.mainContext, matchday)
    }
}
