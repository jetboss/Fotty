import XCTest

@testable import Fotty

@MainActor
final class SettingsUsabilityTests: XCTestCase {

    func testSettingsOffersOnlyAccountSourcesThatCanPlay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent(
            "Fotty/Features/Settings/Views/StreamPluginsSettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("AccountSourceSetup.allCases.filter { $0.playbackProviderCode != nil }"),
                      "Review-only account sources must not appear in Settings")
        XCTAssertEqual(AccountSourceSetup.allCases.filter { $0.playbackProviderCode != nil }, [.highfly])
    }

    private let catalogDefinitions = [
        "score808_manifest": (id: "score808-extension", provider: "score808"),
        "community_sports_manifest": (id: "community-sports-extension", provider: "communitysports"),
        "additional_sports_manifest": (id: "additional-sports-extension", provider: "plaviosports"),
        "cnc_sports_manifest": (id: "cnc-sports-extension", provider: "cncsports"),
        "flix_streams_manifest": (id: "flix-streams-extension", provider: "flixstreams"),
        "reviewed_tv_manifest": (id: "reviewed-tv-extension", provider: "reviewedtv"),
        "highfly_manifest": (id: "highfly-extension", provider: "highfly")
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
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: ["score808-extension": false], loadManifest: manifest)
        XCTAssertEqual(snapshot.plugins.count, CuratedStreamSourceCatalog.all.count)
        XCTAssertEqual(snapshot.unavailableSourceCount, 0)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "score808" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "communitysports" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "plaviosports" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "cncsports" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "flixstreams" }!.isEnabled)
        XCTAssertFalse(snapshot.plugins.first { $0.providerCode == "reviewedtv" }!.isEnabled)
    }

    func testMissingSourceLeavesOtherSettingsUsableAndReportsOnlyBoundedFailureCount() throws {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: ["score808-extension": false]) { filename in
            if filename == "community_sports_manifest" { throw URLError(.fileDoesNotExist) }
            return try self.manifest(named: filename)
        }
        XCTAssertEqual(snapshot.unavailableSourceCount, 1)
        XCTAssertEqual(snapshot.plugins.count, CuratedStreamSourceCatalog.all.count - 1)
        XCTAssertFalse(try XCTUnwrap(snapshot.plugins.first { $0.providerCode == "score808" }).isEnabled)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: snapshot.plugins.count,
                                                           unavailableSourceCount: snapshot.unavailableSourceCount), .unavailable)
    }

    func testAllMissingSourcesYieldFailureInsteadOfAHealthyEmptyCatalog() {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: [:]) { _ in throw URLError(.fileDoesNotExist) }
        XCTAssertTrue(snapshot.plugins.isEmpty)
        XCTAssertEqual(snapshot.unavailableSourceCount, CuratedStreamSourceCatalog.all.count)
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: 0,
                                                           unavailableSourceCount: snapshot.unavailableSourceCount), .unavailable)
    }

    func testRetryCanRecoverBundledMetadataWithoutChangingSavedChoices() throws {
        let choices = ["score808-extension": false,
                       "community-sports-extension": false, "additional-sports-extension": false,
                       "cnc-sports-extension": false, "flix-streams-extension": false,
                       "reviewed-tv-extension": false, "highfly-extension": false]
        let missing = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
            if filename == "score808_manifest" { throw URLError(.fileDoesNotExist) }
            return try self.manifest(named: filename)
        }
        let recovered = StreamPluginRegistry.bundledCatalog(savedStates: choices, loadManifest: manifest)
        XCTAssertEqual(missing.unavailableSourceCount, 1)
        XCTAssertEqual(recovered.unavailableSourceCount, 0)
        for plugin in recovered.plugins { XCTAssertEqual(plugin.isEnabled, choices[plugin.id]) }
        XCTAssertFalse(try XCTUnwrap(recovered.plugins.first { $0.id == "score808-extension" }).isEnabled)
    }

    func testWrongManifestIdentityIsUnavailableNotAnExtraRegisteredSource() {
        let snapshot = StreamPluginRegistry.bundledCatalog(savedStates: [:]) { filename in
            if filename == "score808_manifest" {
                return (.init(id: "unexpected-extension", name: "Unexpected", providerCode: "score808",
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
            "score808-extension": false, "community-sports-extension": false,
            "additional-sports-extension": false, "cnc-sports-extension": false,
            "flix-streams-extension": false, "reviewed-tv-extension": false, "highfly-extension": false
        ], loadManifest: manifest)
        XCTAssertTrue(snapshot.plugins.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(PlaybackSourceSettingsState.resolved(availableSourceCount: snapshot.plugins.count,
                                                           unavailableSourceCount: snapshot.unavailableSourceCount), .available)
    }

    func testFlixOptInChoiceSurvivesBundledRetryWithoutChangingOtherSavedSources() throws {
        XCTAssertFalse(StreamPluginRegistry.isEnabledByDefault(providerCode: "flixstreams"))
        for enabled in [false, true] {
            let choices = ["score808-extension": true,
                           "community-sports-extension": true, "additional-sports-extension": true,
                           "cnc-sports-extension": false, "flix-streams-extension": enabled,
                           "reviewed-tv-extension": false, "highfly-extension": false]
            let unavailable = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
                if filename == "flix_streams_manifest" { throw URLError(.fileDoesNotExist) }
                return try self.manifest(named: filename)
            }
            XCTAssertEqual(unavailable.plugins.count, CuratedStreamSourceCatalog.all.count - 1)
            XCTAssertEqual(unavailable.unavailableSourceCount, 1)
            let recovered = StreamPluginRegistry.bundledCatalog(savedStates: choices, loadManifest: manifest)
            XCTAssertEqual(recovered.plugins.count, CuratedStreamSourceCatalog.all.count)
            XCTAssertEqual(recovered.unavailableSourceCount, 0)
            XCTAssertEqual(try XCTUnwrap(recovered.plugins.first { $0.id == "flix-streams-extension" }).isEnabled, enabled)
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

@MainActor
final class AccountSourceSetupTests: XCTestCase {
    func testAddVerifiesThenSavesAndEnablesWithoutSecondToggle() async throws {
        var value: Data?, order: [String] = []
        let store = AccountSourceSetupStore(read: { _ in value }, write: { _, next in order.append("save"); value = next })
        let connector = AccountSourceConnector(store: store, verify: { provider, _ in
            XCTAssertEqual(provider, .highfly); order.append("verify")
        }, setEnabled: { code, enabled in
            XCTAssertEqual(code, "highfly"); XCTAssertTrue(enabled); XCTAssertNotNil(value); order.append("enable")
        })
        let enabled = try await connector.add("https://premium.highfly.to/synthetic/manifest.json", for: .highfly)
        XCTAssertTrue(enabled)
        XCTAssertEqual(order, ["verify", "save", "enable"])
    }

    func testFailedAccessDoesNotReplaceAccountOrChangeEnablement() async throws {
        let original = Data("https://premium.highfly.to/original-synthetic/manifest.json".utf8)
        var value: Data? = original, changes = 0
        let store = AccountSourceSetupStore(read: { _ in value }, write: { _, next in value = next })
        let connector = AccountSourceConnector(store: store, verify: { _, _ in throw AccountSourceSetupError.accessUnavailable },
            setEnabled: { _, _ in changes += 1 })
        do { _ = try await connector.add("https://premium.highfly.to/replacement-synthetic/manifest.json", for: .highfly); XCTFail() }
        catch { XCTAssertFalse(error.localizedDescription.contains("replacement-synthetic")) }
        XCTAssertEqual(value, original); XCTAssertEqual(changes, 0)
    }

    func testFailedSecureSaveDoesNotEnableSource() async {
        var changes = 0
        let store = AccountSourceSetupStore(read: { _ in nil }, write: { _, _ in throw AccountSourceSetupError.storageUnavailable })
        let connector = AccountSourceConnector(store: store, verify: { _, _ in }, setEnabled: { _, _ in changes += 1 })
        do { _ = try await connector.add("https://premium.highfly.to/synthetic/manifest.json", for: .highfly); XCTFail() }
        catch { }
        XCTAssertEqual(changes, 0)
    }

    func testCancelledValidationDoesNotSaveOrEnable() async {
        var writes = 0, changes = 0
        let store = AccountSourceSetupStore(read: { _ in nil }, write: { _, _ in writes += 1 })
        let connector = AccountSourceConnector(store: store, verify: { _, _ in throw CancellationError() }, setEnabled: { _, _ in changes += 1 })
        do { _ = try await connector.add("https://premium.highfly.to/synthetic/manifest.json", for: .highfly); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes, 0); XCTAssertEqual(changes, 0)
    }

    func testUnimplementedSourceIsSavedForReviewWithoutFalseActivation() async throws {
        var writes = 0, changes = 0
        let store = AccountSourceSetupStore(read: { _ in nil }, write: { _, _ in writes += 1 })
        let connector = AccountSourceConnector(store: store, verify: { _, _ in XCTFail("Review-only configuration is not an adapter") }, setEnabled: { _, _ in changes += 1 })
        let enabled = try await connector.add("https://pengu.uk/synthetic/manifest.json", for: .penguPlay)
        XCTAssertFalse(enabled); XCTAssertEqual(writes, 1); XCTAssertEqual(changes, 0)
    }

    func testRemovingAddedSourceDisablesOnlyThatSourceAfterSecureRemoval() async throws {
        var removed = false, changes: [String] = []
        let store = AccountSourceSetupStore(read: { _ in nil }, write: { _, next in XCTAssertNil(next); removed = true })
        let connector = AccountSourceConnector(store: store, verify: { _, _ in }, setEnabled: { code, enabled in
            XCTAssertTrue(removed); XCTAssertFalse(enabled); changes.append(code)
        })
        try await connector.remove(.highfly)
        XCTAssertEqual(changes, ["highfly"])
    }

    func testConfiguredLinksStayWithTheirNamedProvider() throws {
        let samples: [(AccountSourceSetup, String)] = [
            (.penguPlay, "https://pengu.uk/test-config/manifest.json"),
            (.highfly, "stremio://sports.highfly.to/test-config/manifest.json"),
            (.streamNexus, "https://sports.streamnexus.cc.cd/test-config/manifest.json")
        ]
        for (provider, value) in samples {
            let accepted = try provider.validatedLink(value)
            XCTAssertEqual(accepted.scheme, "https")
            for other in AccountSourceSetup.allCases where other != provider {
                XCTAssertThrowsError(try other.validatedLink(value))
            }
        }
        let query = "https://pengu.uk/manifest.json?configuration=test-only"
        XCTAssertEqual(try AccountSourceSetup.penguPlay.validatedLink(query).absoluteString, query)
        XCTAssertEqual(try AccountSourceSetup.highfly.validatedLink("https://premium-eu1.highfly.to/test-account/test-profile/manifest.json").host,
                       "premium-eu1.highfly.to")
    }

    func testUnsafeOrUnreviewedConfigurationAddressesAreNotStored() throws {
        var writes = 0
        let store = AccountSourceSetupStore(read: { _ in nil }, write: { _, _ in writes += 1 })
        for value in ["", "not a link", "http://pengu.uk/a/manifest.json", "https://pengu.uk:8443/a/manifest.json",
                      "https://pengu.uk.evil.example/a/manifest.json", "https://sub.pengu.uk/a/manifest.json",
                      "https://user:password@pengu.uk/a/manifest.json", "https://127.0.0.1/a/manifest.json",
                      "https://pengu.uk/configure", "https://pengu.uk/a/manifest.json#fragment",
                      "https://pengu.uk/a/%2e%2e/manifest.json", "https://pengu.uk/a%5Cb/manifest.json",
                      "https://pengu.uk/a\n/manifest.json", "https://pengu.uk/" + String(repeating: "a", count: 8192) + "/manifest.json"] {
            XCTAssertThrowsError(try store.save(value, for: .penguPlay))
        }
        XCTAssertEqual(writes, 0)
    }

    func testPrivateStorageDoesNotInventAdaptersOrChangeOtherSavedLinks() throws {
        var values: [AccountSourceSetup: Data] = [:]
        let before = CuratedStreamSourceCatalog.all.map(\.providerCode)
        let store = AccountSourceSetupStore(read: { values[$0] }, write: { values[$0] = $1 })
        for provider in AccountSourceSetup.allCases {
            XCTAssertFalse(try store.hasSavedLink(for: provider))
            let host = provider.manifestHosts.sorted().first!
            try store.save("https://\(host)/test-config/manifest.json", for: provider)
            XCTAssertTrue(try store.hasSavedLink(for: provider))
            if provider != .highfly { XCTAssertNil(CuratedStreamSourceCatalog.definition(forProviderCode: provider.rawValue)) }
        }
        XCTAssertEqual(CuratedStreamSourceCatalog.all.map(\.providerCode), before)
        try store.remove(.highfly)
        XCTAssertFalse(try store.hasSavedLink(for: .highfly))
        XCTAssertTrue(try store.hasSavedLink(for: .penguPlay))
        XCTAssertTrue(try store.hasSavedLink(for: .streamNexus))
    }

    func testRejectedReplacementPreservesExistingPrivateLinkAndErrorsDoNotEchoIt() throws {
        let old = Data("https://pengu.uk/test-original/manifest.json".utf8)
        var value: Data? = old
        var unavailable = false
        let store = AccountSourceSetupStore(read: { _ in
            if unavailable { throw AccountSourceSetupError.storageUnavailable }; return value
        }, write: { _, next in
            if unavailable { throw AccountSourceSetupError.storageUnavailable }; value = next
        })
        XCTAssertThrowsError(try store.save("https://elsewhere.example/private-test/manifest.json", for: .penguPlay)) { error in
            XCTAssertFalse(error.localizedDescription.contains("private-test"))
        }
        XCTAssertEqual(value, old)
        unavailable = true
        XCTAssertThrowsError(try store.save("https://pengu.uk/test-replacement/manifest.json", for: .penguPlay))
        XCTAssertThrowsError(try store.hasSavedLink(for: .penguPlay))
        XCTAssertEqual(value, old)
    }
}
