import XCTest

@testable import Fotty

@MainActor
final class SettingsUsabilityTests: XCTestCase {
    private let catalogDefinitions = [
        "streamex_manifest": (id: "streamex-extension", provider: "streamex"),
        "score808_manifest": (id: "score808-extension", provider: "score808"),
        "community_sports_manifest": (id: "community-sports-extension", provider: "communitysports"),
        "additional_sports_manifest": (id: "additional-sports-extension", provider: "plaviosports"),
        "cnc_sports_manifest": (id: "cnc-sports-extension", provider: "cncsports"),
        "flix_streams_manifest": (id: "flix-streams-extension", provider: "flixstreams"),
        "streamvix_sports_manifest": (id: "streamvix-sports-extension", provider: "streamvix"),
        "reviewed_tv_manifest": (id: "reviewed-tv-extension", provider: "reviewedtv")
    ]

    private func manifest(named filename: String) throws -> (StreamPluginManifest, URL) {
        let definition = try XCTUnwrap(catalogDefinitions[filename])
        return (.init(id: definition.id, name: definition.provider, providerCode: definition.provider,
                      version: "1", author: "Test", description: "Local test source", allowedDomains: []),
                URL(fileURLWithPath: "/test-bundle/\(filename).json"))
    }

    func testCompletedEmptyAndUnavailableResultsNeverRemainLoading() {
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: 3, unavailableSourceCount: 0), .available)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: 0, unavailableSourceCount: 0), .empty)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: 0, unavailableSourceCount: 3), .unavailable)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: 2, unavailableSourceCount: 1), .unavailable)
    }

    func testBundledCatalogRetainsDisabledChoicesAndOptInDefault() {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: ["streamex-extension": false], loadManifest: manifest)
        XCTAssertEqual(snapshot.plugins.count, 8)
        XCTAssertEqual(snapshot.unavailableSourceCount, 0)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "streamex" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "communitysports" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "plaviosports" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "cncsports" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "flixstreams" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "streamvix" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "reviewedtv" }!.isEnabled)
        XCTAssertTrue(snapshot.plugins.first { $0.providerCode == "score808" }!.isEnabled)
    }

    func testMissingSourceLeavesOtherSettingsUsableAndReportsOnlyBoundedFailureCount() throws {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: ["score808-extension": false]) { filename in
            if filename == "streamex_manifest" { throw URLError(.fileDoesNotExist) }
            return try self.manifest(named: filename)
        }
        XCTAssertEqual(snapshot.unavailableSourceCount, 1)
        XCTAssertEqual(snapshot.plugins.count, 7)
        XCTAssertFalse(try XCTUnwrap(snapshot.plugins.first { $0.providerCode == "score808" }).isEnabled)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: snapshot.plugins.count,
                                                           unavailableSourceCount: snapshot.unavailableSourceCount), .unavailable)
    }

    func testAllMissingSourcesYieldFailureInsteadOfAHealthyEmptyCatalog() {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: [:]) { _ in throw URLError(.fileDoesNotExist) }
        XCTAssertTrue(snapshot.plugins.isEmpty)
        XCTAssertEqual(snapshot.unavailableSourceCount, 8)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: 0,
                                                           unavailableSourceCount: snapshot.unavailableSourceCount), .unavailable)
    }

    func testRetryCanRecoverBundledMetadataWithoutChangingSavedChoices() throws {
        let choices = ["streamex-extension": false, "score808-extension": true,
                       "community-sports-extension": false, "additional-sports-extension": false,
                       "cnc-sports-extension": false, "flix-streams-extension": false,
                       "streamvix-sports-extension": false, "reviewed-tv-extension": false]
        let missing = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
            if filename == "streamex_manifest" { throw URLError(.fileDoesNotExist) }
            return try self.manifest(named: filename)
        }
        let recovered = StreamPluginRegistry.bundledCatalog(savedStates: choices, loadManifest: manifest)
        XCTAssertEqual(missing.unavailableSourceCount, 1)
        XCTAssertEqual(recovered.unavailableSourceCount, 0)
        for plugin in recovered.plugins { XCTAssertEqual(plugin.isEnabled, choices[plugin.id]) }
        XCTAssertFalse(try XCTUnwrap(recovered.plugins.first { $0.id == "streamex-extension" }).isEnabled)
    }

    func testWrongManifestIdentityIsUnavailableNotAnExtraRegisteredSource() {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: [:]) { filename in
            if filename == "streamex_manifest" {
                return (.init(id: "unexpected-extension", name: "Unexpected", providerCode: "streamex",
                              version: "1", author: "Test", description: "", allowedDomains: []),
                        URL(fileURLWithPath: "/test-bundle/unexpected.json"))
            }
            return try self.manifest(named: filename)
        }
        XCTAssertEqual(snapshot.unavailableSourceCount, 1)
        XCTAssertFalse(snapshot.plugins.contains { $0.id == "unexpected-extension" })
        XCTAssertEqual(Set(snapshot.plugins.map(\.id)).count, snapshot.plugins.count)
    }

    func testDisabledSourcesAreStillAvailableToConfigure() {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: [
            "streamex-extension": false, "score808-extension": false, "community-sports-extension": false,
            "additional-sports-extension": false, "cnc-sports-extension": false,
            "flix-streams-extension": false, "streamvix-sports-extension": false, "reviewed-tv-extension": false
        ], loadManifest: manifest)
        XCTAssertTrue(snapshot.plugins.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: snapshot.plugins.count,
                                                           unavailableSourceCount: snapshot.unavailableSourceCount), .available)
    }

    func testFlixOptInChoiceSurvivesBundledRetryWithoutChangingOtherSavedSources() throws {
        XCTAssertFalse(StreamPluginRegistry.isEnabledByDefault(providerCode: "flixstreams"))
        for enabled in [false, true] {
            let choices = ["streamex-extension": false, "score808-extension": true,
                           "community-sports-extension": true, "additional-sports-extension": true,
                           "cnc-sports-extension": false, "flix-streams-extension": enabled,
                           "streamvix-sports-extension": false, "reviewed-tv-extension": false]
            let unavailable = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
                if filename == "flix_streams_manifest" { throw URLError(.fileDoesNotExist) }
                return try self.manifest(named: filename)
            }
            XCTAssertEqual(unavailable.plugins.count, 7)
            XCTAssertEqual(unavailable.unavailableSourceCount, 1)
            let recovered = StreamPluginRegistry.bundledCatalog(savedStates: choices, loadManifest: manifest)
            XCTAssertEqual(recovered.plugins.count, 8)
            XCTAssertEqual(recovered.unavailableSourceCount, 0)
            XCTAssertEqual(try XCTUnwrap(recovered.plugins.first { $0.id == "flix-streams-extension" }).isEnabled, enabled)
            for plugin in recovered.plugins { XCTAssertEqual(plugin.isEnabled, choices[plugin.id]) }
        }
    }

    func testStreamVixOptInChoiceSurvivesBundledRetryWithoutChangingOtherSavedSources() throws {
        XCTAssertFalse(StreamPluginRegistry.isEnabledByDefault(providerCode: "streamvix"))
        for enabled in [false, true] {
            let choices = ["streamex-extension": false, "score808-extension": true,
                           "community-sports-extension": true, "additional-sports-extension": true,
                           "cnc-sports-extension": false, "flix-streams-extension": false,
                           "streamvix-sports-extension": enabled, "reviewed-tv-extension": false]
            let unavailable = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
                if filename == "streamvix_sports_manifest" { throw URLError(.fileDoesNotExist) }
                return try self.manifest(named: filename)
            }
            XCTAssertEqual(unavailable.plugins.count, 7)
            XCTAssertEqual(unavailable.unavailableSourceCount, 1)
            let recovered = StreamPluginRegistry.bundledCatalog(savedStates: choices, loadManifest: manifest)
            XCTAssertEqual(recovered.plugins.count, 8)
            XCTAssertEqual(recovered.unavailableSourceCount, 0)
            XCTAssertEqual(try XCTUnwrap(recovered.plugins.first { $0.id == "streamvix-sports-extension" }).isEnabled, enabled)
            for plugin in recovered.plugins { XCTAssertEqual(plugin.isEnabled, choices[plugin.id]) }
        }
    }

    func testInlineAlertScopeAndScheduledRemindersAreDistinctAndTruthful() {
        XCTAssertTrue(FottyHelpContent.matchAlertSettingsScope.contains("followed Premier League teams"))
        XCTAssertTrue(FottyHelpContent.matchAlertSettingsScope.contains("open and refreshing"))
        XCTAssertTrue(FottyHelpContent.matchAlertSettingsScope.contains("not background push"))
        XCTAssertTrue(FottyHelpContent.scheduledMatchReminders.contains("separate"))
        XCTAssertTrue(FottyHelpContent.scheduledMatchReminders.contains("Fotty closed"))
        XCTAssertTrue(FottyHelpContent.scheduledMatchReminders.contains("notification settings"))
    }

    func testHelpDescribesPersonalizedHomeRatherThanPromisingEveryFixture() {
        XCTAssertTrue(FottyHelpContent.homePersonalization.contains("current selection"))
        XCTAssertTrue(FottyHelpContent.homePersonalization.contains("Only your interests"))
        XCTAssertTrue(FottyHelpContent.homePersonalization.contains("Browse Sports"))
        XCTAssertFalse(FottyHelpContent.homePersonalization.contains("full schedule"))
        XCTAssertTrue(FottyHelpContent.homePersonalization.contains("Saving alone does not enable reminders"))
    }

    func testPassiveValueIsDefaultAndActionEmphasisRequiresAnExplicitRole() {
        let passive = SettingsRow(icon: "info.circle", iconColor: .gray, title: "Fotty", value: "v1", showChevron: false)
        let action = SettingsRow(icon: "bell", iconColor: .gray, title: "Allowed", value: "Manage", valueRole: .action)
        XCTAssertEqual(passive.valueRole, .information)
        XCTAssertEqual(action.valueRole, .action)
    }

    func testTaskGroupedSettingsKeepExistingRoutesAndDoNotMigratePreferences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Settings/SettingsScreen.swift"), encoding: .utf8)
        for title in ["Appearance", "Home & Matchday", "Playback & alerts", "Your data", "Support & About"] {
            XCTAssertTrue(source.contains("SettingsSection(title: \"\(title)\")"), title)
        }
        // Team following is intentionally reached through Home interests.
        let routes = source + (try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Settings/Views/SettingsManageLeaguesView.swift"), encoding: .utf8))
        for route in ["SettingsAppearanceView()", "SettingsManageFollowsView()", "SettingsManageLeaguesView()",
                      "StreamPluginsSettingsView()", "SettingsSportsContinuityView()", "SettingsPrivateBackupView()",
                      "SettingsPrivacyView()", "FottyHelpView()", "FottyFeedbackView()"] {
            XCTAssertTrue(routes.contains(route), route)
        }
        XCTAssertTrue(source.contains("isOn: $showKickoffClashes"))
        XCTAssertTrue(source.contains("title: \"Notifications\", value: notificationPermissionSummary"))
        XCTAssertFalse(source.contains("removePersistentDomain"))
        XCTAssertFalse(source.contains("setPluginEnabled"))
    }

    func testSourceSettingsVocabularyDoesNotClaimPlaybackQualification() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let screen = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Settings/SettingsScreen.swift"), encoding: .utf8)
        let sources = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Settings/Views/StreamPluginsSettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(screen.contains("title: \"Playback sources\""))
        XCTAssertTrue(sources.contains(".navigationTitle(\"Playback sources\")"))
        XCTAssertTrue(sources.contains("Section(header: Text(\"Supported sources\"))"))
        XCTAssertFalse(sources.contains("Section(header: Text(\"Available\"))"))
        XCTAssertFalse(sources.contains("All streams working"))
    }

    func testFeedbackHandoffDoesNotInventDeliveryOrADirectURL() {
        XCTAssertTrue(FottyFeedbackDelivery.testFlightSteps.contains("open TestFlight"))
        XCTAssertTrue(FottyFeedbackDelivery.testFlightSteps.contains("Send Beta Feedback"))
        XCTAssertTrue(FottyFeedbackDelivery.copiedNotice.contains("not sent"))
        XCTAssertFalse(FottyFeedbackDelivery.testFlightSteps.contains("itms-beta"))
        XCTAssertFalse(FottyFeedbackDelivery.testFlightSteps.contains("https://"))
    }
}
