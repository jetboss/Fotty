import XCTest
@testable import Fotty

final class AdditionalSportsIntegrationTests: XCTestCase {
    func testCuratedCatalogOwnsItsRegistrationAndDispatchIdentities() {
        let definitions = CuratedStreamSourceCatalog.all
        XCTAssertEqual(definitions.map(\.providerCode),
                       ["score808", "communitysports", "plaviosports", "cncsports", "flixstreams", "reviewedtv", "highfly", "penguplay"])
        XCTAssertEqual(Set(definitions.map(\.providerCode)).count, definitions.count)
        XCTAssertEqual(Set(definitions.map(\.manifestID)).count, definitions.count)
        XCTAssertEqual(Set(definitions.map(\.manifestFilename)).count, definitions.count)
        XCTAssertEqual(Set(definitions.map(\.provider)), Set(CuratedStreamSourceCatalog.Provider.allCases))
        XCTAssertEqual(definitions.map(\.dispatch),
                       [.score808, .communitySports, .plavioSports, .cncSports, .flixStreams, .reviewedTV, .highfly, .penguPlay])
        XCTAssertEqual(StreamPluginProviderMatching.activePlayerProviderCodes, definitions.map(\.providerCode))
        XCTAssertEqual(CuratedStreamSourceCatalog.optionalSources.map(\.discoveryName), ["CS", "AS", "LS", "FS", "TV", "HF", "PP"])
    }

    func testEveryCuratedDefinitionRequiresItsOwnBundledManifestAndProviderCode() throws {
        for definition in CuratedStreamSourceCatalog.all {
            let (manifest, _) = try StreamPluginBundle.loadManifest(named: definition.manifestFilename)
            XCTAssertTrue(definition.accepts(manifest: manifest), definition.providerCode)
            for other in CuratedStreamSourceCatalog.all where other.provider != definition.provider {
                XCTAssertFalse(definition.accepts(manifest: catalogManifest(definition, providerCode: other.providerCode)),
                               "A matching manifest ID cannot borrow \(other.providerCode)'s dispatcher or opt-in")
            }
        }
    }

    func testCuratedCatalogRetainsExistingDefaultsAndDoesNotRegisterProviderCodeSubstitution() throws {
        let definitions = CuratedStreamSourceCatalog.all
        for definition in definitions {
            XCTAssertEqual(definition.defaultEnabled, definition.providerCode == "score808")
            XCTAssertEqual(StreamPluginRegistry.isEnabledByDefault(providerCode: definition.providerCode), definition.defaultEnabled)
        }
        let fs = try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "flixstreams"))
        let choices = Dictionary(uniqueKeysWithValues: definitions.map { ($0.manifestID, $0.provider == .flixStreams) })
        let substituted = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
            let definition = try XCTUnwrap(definitions.first { $0.manifestFilename == filename })
            return (self.catalogManifest(definition, providerCode: definition == fs ? "score808" : nil),
                    URL(fileURLWithPath: "/test-bundle/\(filename).json"))
        }
        XCTAssertEqual(substituted.unavailableSourceCount, 1)
        XCTAssertEqual(substituted.plugins.count, definitions.count - 1)
        XCTAssertFalse(substituted.plugins.contains { $0.id == fs.manifestID })
        let restored = StreamPluginRegistry.bundledCatalog(savedStates: choices) { filename in
            let definition = try XCTUnwrap(definitions.first { $0.manifestFilename == filename })
            return (self.catalogManifest(definition), URL(fileURLWithPath: "/test-bundle/\(filename).json"))
        }
        XCTAssertEqual(restored.unavailableSourceCount, 0)
        for plugin in restored.plugins { XCTAssertEqual(plugin.isEnabled, choices[plugin.id]) }
    }

    func testCuratedOpaqueLabelsHaveOneOwnerAndDoNotExpandLegacyLabelAdmission() throws {
        for definition in CuratedStreamSourceCatalog.optionalSources {
            let choices = definition.provider == .reviewedTV
                ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 21, 22, 23, 24, 25, 26, 27] : Array(1...6)
            let lastChoice = try XCTUnwrap(choices.last)
            for choice in choices {
                let label = try XCTUnwrap(definition.sourceLabel(choice: choice))
                XCTAssertEqual(CuratedStreamSourceCatalog.opaqueDefinition(for: label), definition)
                XCTAssertEqual(StreamPluginProviderMatching.opaqueProviderFamily(label), definition.providerCode)
                XCTAssertTrue(definition.matchesOpaqueLabel(" " + label + " "))
                for other in CuratedStreamSourceCatalog.all where other != definition {
                    XCTAssertFalse(other.matchesOpaqueLabel(label))
                }
            }
            XCTAssertNil(definition.sourceLabel(choice: 0))
            XCTAssertNil(definition.sourceLabel(choice: lastChoice + 1))
            if definition.provider == .reviewedTV {
                for missing in [16, 18, 19, 20] {
                    XCTAssertNil(definition.sourceLabel(choice: missing))
                    XCTAssertNil(CuratedStreamSourceCatalog.opaqueDefinition(for: "TV" + String(missing)))
                }
            }
            let invalidSuffixes = ["", "0", String(lastChoice + 1), "01", "1 extra", "١"]
                + (definition.provider == .reviewedTV ? ["16", "20"] : ["10"])
            for suffix in invalidSuffixes {
                XCTAssertNil(CuratedStreamSourceCatalog.opaqueDefinition(for: definition.discoveryName + suffix))
            }
        }
        XCTAssertTrue(try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "communitysports")).matchesLegacyLabel("CS7"),
                      "The old explicit CS-digit alias is separate from the six opaque option labels")
        XCTAssertNil(CuratedStreamSourceCatalog.opaqueDefinition(for: "CS7"))
        XCTAssertFalse(try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "plaviosports")).matchesLegacyLabel("AS7"))
        XCTAssertNil(CuratedStreamSourceCatalog.opaqueDefinition(for: "as1"))
    }

    func testCuratedDefinitionsResolveOnlyReviewedProviderCodes() {
        XCTAssertEqual(CuratedStreamSourceCatalog.definition(forProviderCode: " FLIXSTREAMS ")?.providerCode, "flixstreams")
        XCTAssertNil(CuratedStreamSourceCatalog.definition(forProviderCode: "SV1"))
        XCTAssertNil(CuratedStreamSourceCatalog.definition(forProviderCode: "future"))
    }

    func testCuratedDiscoveryScopesDelegateToExistingReviewedAdaptersWithoutBroadeningLanes() {
        let expected: [(String, [String])] = [
            ("football", ["communitysports", "plaviosports", "flixstreams", "highfly", "penguplay"]),
            ("soccer", ["communitysports", "plaviosports", "flixstreams", "highfly", "penguplay"]),
            ("cricket", ["communitysports", "plaviosports", "cncsports", "flixstreams", "highfly", "penguplay"]),
            ("hockey", ["communitysports", "cncsports", "highfly", "penguplay"]),
            ("american-football", ["communitysports", "highfly", "penguplay"]),
            ("basketball", ["communitysports", "highfly", "penguplay"]),
            ("rugby", ["communitysports"]),
            ("unreviewed", ["communitysports"])
        ]
        for (category, providers) in expected {
            XCTAssertEqual(CuratedStreamSourceCatalog.optionalSources.filter { $0.supportsDiscovery(category: category) }
                .map(\.providerCode), providers, category)
        }
        for definition in CuratedStreamSourceCatalog.all where !definition.isOptional {
            XCTAssertFalse(definition.supportsDiscovery(category: "football"),
                           "Legacy shared/direct lookup retains its separate timing and dispatch policy")
        }
    }

    private func catalogManifest(_ definition: CuratedStreamSourceCatalog.Definition,
                                 providerCode: String? = nil) -> StreamPluginManifest {
        .init(id: definition.manifestID, name: definition.discoveryName, providerCode: providerCode ?? definition.providerCode,
              version: "1", author: "Test", description: "Reviewed source fixture", allowedDomains: [])
    }

    func testFlixLabelsOwnOnlyTheirReviewedFamilyDespiteRemoteProviderAliases() {
        for number in 1...6 {
            let source = StreamSource(title: "Streamed golf india admin community sports plaviosports cncsports",
                url: URL(string: "https://example.invalid/streamed/score808/communitysports/fixture.m3u8")!,
                quality: "HD", provider: "FS\(number)")
            XCTAssertTrue(StreamPluginProviderMatching.matches(source, code: "flixstreams"))
            XCTAssertEqual(StreamPluginProviderMatching.opaqueProviderFamily(source.provider), "flixstreams")
            XCTAssertEqual(LiveSourceHealthStore.providerFamily(for: source), "flixstreams")
            XCTAssertTrue(StreamPluginProviderMatching.isActivePlayerSource(source))
            for other in ["score808", "communitysports", "plaviosports", "cncsports"] {
                XCTAssertFalse(StreamPluginProviderMatching.matches(source, code: other), other)
            }
            let enabledWithoutFlix = StreamPluginProviderMatching.allowedPlayerProviderCodes(enabledCodes:
                ["score808", "communitysports", "plaviosports", "cncsports"])
            XCTAssertFalse(enabledWithoutFlix.contains { StreamPluginProviderMatching.matches(source, code: $0) },
                           "A disabled FS module must not borrow another enabled family")
        }
    }

    func testUnreviewedFlixLabelsAndRemoteNamesCannotImpersonateFSOptions() {
        for label in ["FS0", "FS7", "FS10", "FS1 extra", "Flix", "Broadcast"] {
            let source = StreamSource(title: "FS1 flixstreams",
                url: URL(string: "https://example.invalid/flixstreams/fixture.m3u8")!, quality: "HD", provider: label)
            XCTAssertNil(StreamPluginProviderMatching.opaqueProviderFamily(label), label)
            XCTAssertFalse(StreamPluginProviderMatching.matches(source, code: "flixstreams"), label)
            XCTAssertFalse(StreamPluginProviderMatching.isActivePlayerSource(source), label)
        }
    }

    func testFlixOpaquePlaybackKeyRetainsFamilyAndRedactsPrivateDeliveryContext() throws {
        let url = URL(string: "https://example.invalid/private/fixture.m3u8?token=synthetic-owner-value")!
        let source = StreamSource(url: url, quality: "HD", provider: "FS1")
        let key = FlixStreamsAddonClient.sourceKey(url: url)
        XCTAssertNotNil(key.range(of: #"^fs_[a-f0-9]{24}$"#, options: .regularExpression))
        XCTAssertEqual(key, FlixStreamsAddonClient.sourceKey(url: url))
        let details = FottyPlaybackQualityDetails.make(source: source, mode: "native", route: "single",
            attemptID: UUID(), sourceKey: key)
        XCTAssertEqual(details["source_family"], "flixstreams")
        XCTAssertEqual(details["source_key"], key)
        XCTAssertFalse(details.values.contains { $0.contains("example.invalid") || $0.contains("synthetic-owner-value") })

        let suite = "FS-playback-integration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        store.record(category: .playback, name: "decoded_progress", outcome: .success,
            details: details.merging(["private_url": url.absoluteString], uniquingKeysWith: { _, new in new }))
        XCTAssertEqual(store.records().last?.details["source_family"], "flixstreams")
        XCTAssertEqual(store.records().last?.details["source_key"], key)
        XCTAssertNil(store.records().last?.details["private_url"])
        XCTAssertFalse(store.exportJSON().contains("example.invalid"))
        XCTAssertFalse(store.exportJSON().contains("synthetic-owner-value"))
    }

    func testFlixDiscoveryReceiptCoexistsWithCSAndASWithoutBorrowingTheirOutcome() throws {
        var report = StreamDiscoveryCoordinator.Report()
        report.attempts = [
            .init(providerName: "CS", responseTimeMs: 10, resolvedStreamType: .hls, urlShape: "addon", requiredHeaders: true,
                validationResult: "exact_match_admitted", manifestResult: "exact_fixture_match"),
            .init(providerName: "AS", responseTimeMs: 20, resolvedStreamType: .unknown, urlShape: "addon", requiredHeaders: false,
                validationResult: "failed", manifestResult: "stream_entries_empty", finalFailureCategory: .providerReturnedEmpty),
            .init(providerName: "FS", responseTimeMs: 30, resolvedStreamType: .hls, urlShape: "addon", requiredHeaders: false,
                validationResult: "exact_match_admitted", manifestResult: "exact_fixture_match")
        ]
        let suite = "FS-discovery-integration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        let attempt = UUID().uuidString
        CommunitySportsDiscoveryQuality.record(report, attemptID: attempt, store: store)
        AdditionalSportsDiscoveryQuality.record(report, attemptID: attempt, store: store)
        FlixStreamsDiscoveryQuality.record(report, attemptID: attempt, store: store)

        XCTAssertEqual(store.records().count, 3)
        XCTAssertEqual(Set(store.records().map { $0.details["source_family"] ?? "" }),
                       ["communitysports", "plaviosports", "flixstreams"])
        XCTAssertEqual(store.records().first { $0.details["source_family"] == "communitysports" }?.outcome, .success)
        XCTAssertEqual(store.records().first { $0.details["source_family"] == "plaviosports" }?.outcome, .failure)
        let fs = try XCTUnwrap(store.records().first { $0.details["source_family"] == "flixstreams" })
        XCTAssertEqual(fs.outcome, .success)
        XCTAssertEqual(fs.durationMilliseconds, 30)
        XCTAssertEqual(fs.details["result"], "exact_fixture_match")
        XCTAssertEqual(fs.details["attempt_id"], attempt)
        XCTAssertNil(fs.details["failure_kind"])
    }

    func testFlixFailureUsesOwnProviderAndGenericBoundedAdmissionCounts() {
        let failure = LiveStreamResolver.communitySportsFailure(from: .streamAdmissionRejected(entryCount: 4), providerName: "FS")
        XCTAssertEqual(failure.providerName, "FS")
        XCTAssertEqual(failure.category, .providerReturnedEmpty)
        XCTAssertEqual(failure.redactedMetadata["addon_stream_entry_count"], "4")
        XCTAssertEqual(failure.redactedMetadata["addon_admission_rejected_count"], "4")
        XCTAssertNil(failure.redactedMetadata["cs_stream_entry_count"])
        XCTAssertNil(failure.redactedMetadata["cs_admission_rejected_count"])
    }

    func testLivXowLabelsRetainOwnFamilyAndCannotBorrowExistingProviders() {
        for label in ["LS1", "LS6"] {
            let source = StreamSource(title: "Streamed golf community sports", url: URL(string: "https://edgestream4.pro/hls/fixture.m3u8")!,
                quality: "HD", provider: label)
            XCTAssertTrue(StreamPluginProviderMatching.matches(source, code: "cncsports"))
            for other in ["score808", "communitysports", "plaviosports"] {
                XCTAssertFalse(StreamPluginProviderMatching.matches(source, code: other))
            }
            XCTAssertEqual(LiveSourceHealthStore.providerFamily(for: source), "cncsports")
        }
        for label in ["LS7", "LS1 extra", "Broadcast", "CNCVerse"] {
            let source = StreamSource(title: "LS1 cncsports", url: URL(string: "https://example.com/cncsports")!,
                quality: "HD", provider: label)
            XCTAssertFalse(StreamPluginProviderMatching.matches(source, code: "cncsports"))
        }
    }

    func testLivXowDiscoveryAndMetadataFailureHaveSeparateRedactedAttribution() throws {
        XCTAssertEqual(CommunitySportsRequestStage.metadata.requestTimeout, 7)
        XCTAssertEqual(CommunitySportsRequestStage.metadata.transportDeadline, 9)
        var report = StreamDiscoveryCoordinator.Report()
        report.attempts = [
            .init(providerName: "CS", responseTimeMs: 10, resolvedStreamType: .hls, urlShape: "addon", requiredHeaders: true,
                validationResult: "exact_match_admitted", manifestResult: "exact_fixture_match"),
            .init(providerName: "LS", responseTimeMs: 20, resolvedStreamType: .hls, urlShape: "addon", requiredHeaders: true,
                validationResult: "exact_match_admitted", manifestResult: "exact_fixture_match")
        ]
        let suite = "LS-integration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        let attempt = UUID().uuidString
        CommunitySportsDiscoveryQuality.record(report, attemptID: attempt, store: store)
        CNCSportsDiscoveryQuality.record(report, attemptID: attempt, store: store)
        XCTAssertEqual(Set(store.records().map { $0.details["source_family"] ?? "" }), ["communitysports", "cncsports"])
        let failure = LiveStreamResolver.communitySportsFailure(from: .httpFailure(statusCode: 502, stage: .metadata), providerName: "LS")
        XCTAssertEqual(failure.providerName, "LS")
        XCTAssertEqual(failure.redactedMetadata["manifest_result"], "metadata_http_failure")
        let source = StreamSource(url: URL(string: "https://example.com/private.m3u8")!, quality: "HD", provider: "LS1")
        let details = FottyPlaybackQualityDetails.make(source: source, mode: "native", route: "single", attemptID: UUID(),
            sourceKey: "ls_0123456789abcdef01234567") // gitleaks:allow — synthetic opaque identifier
        XCTAssertEqual(details["source_key"], "ls_0123456789abcdef01234567")
        XCTAssertEqual(details["source_family"], "cncsports")
        XCTAssertFalse(details.values.contains { $0.contains("example.com") })
    }

    func testOpaqueLabelsCannotBorrowAnotherEnabledFamilyFromRemoteText() {
        for label in ["AS1", "AS6"] {
            let source = StreamSource(title: "Streamed golf india admin", url: URL(string: "https://papacito.cfd/streamed/golf/india.m3u8?ft=fixture")!,
                quality: "HD", provider: label)
            XCTAssertTrue(StreamPluginProviderMatching.matches(source, code: "plaviosports"))
            XCTAssertFalse(StreamPluginProviderMatching.matches(source, code: "communitysports"))
            XCTAssertEqual(LiveSourceHealthStore.providerFamily(for: source), "plaviosports")
        }
        let cs = StreamSource(url: URL(string: "https://example.com/streamed")!, quality: "HD", provider: "CS1")
        XCTAssertTrue(StreamPluginProviderMatching.matches(cs, code: "communitysports"))
        XCTAssertFalse(StreamPluginProviderMatching.matches(cs, code: "plaviosports"))
    }

    func testRemoteLabelsAndURLsCannotImpersonateAdditionalFamily() {
        for provider in ["Broadcast", "AS7", "AS1 extra", "Plavio"] {
            let source = StreamSource(title: "AS1 plaviosports", url: URL(string: "https://example.com/plaviosports")!, quality: "auto", provider: provider)
            XCTAssertFalse(StreamPluginProviderMatching.matches(source, code: "plaviosports"))
        }
    }

    func testHeaderlessRelayRequirementSurvivesLegacyCopyAndCodable() throws {
        let session = StreamSession(matchID: "fixture", playableURL: URL(string: "https://papacito.cfd/a/b/live.m3u8?ft=fixture")!,
            streamType: .hls, providerName: "AS1", requiresGuardedRelay: true)
        XCTAssertTrue(session.requiredHeaders.isEmpty)
        XCTAssertTrue(session.requiresLocalProxy)
        XCTAssertTrue(session.legacySource.requiresLocalProxy)
        XCTAssertTrue(session.legacySource.mergingHeaders([:]).requiresLocalProxy)
        XCTAssertNil(session.nativeOriginProfile)
        XCTAssertNil(session.nativePlaylistProfile)
        let decoded = try JSONDecoder().decode(StreamSession.self, from: JSONEncoder().encode(session))
        XCTAssertTrue(decoded.requiresLocalProxy)
        XCTAssertTrue(decoded.legacySource.requiresLocalProxy)
        let ordinary = StreamSession(matchID: "fixture", playableURL: session.playableURL, streamType: .hls, providerName: "Other")
        let oldData = try JSONEncoder().encode(ordinary)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("requiresGuardedRelay"))
        XCTAssertFalse(try JSONDecoder().decode(StreamSession.self, from: oldData).requiresLocalProxy)
    }

    func testAdditionalDiscoveryReceiptDoesNotOverwriteCSAndIsRedacted() throws {
        var report = StreamDiscoveryCoordinator.Report()
        report.attempts = [
            .init(providerName: "CS", responseTimeMs: 10, resolvedStreamType: .hls, urlShape: "addon", requiredHeaders: true,
                validationResult: "exact_match_admitted", manifestResult: "exact_fixture_match"),
            .init(providerName: "AS", responseTimeMs: 25, resolvedStreamType: .unknown, urlShape: "addon", requiredHeaders: false,
                validationResult: "failed", manifestResult: "no_admitted_stream_delivery", finalFailureCategory: .providerReturnedEmpty)
        ]
        let suite = "AS-integration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        let id = UUID().uuidString
        CommunitySportsDiscoveryQuality.record(report, attemptID: id, store: store)
        AdditionalSportsDiscoveryQuality.record(report, attemptID: id, store: store)
        XCTAssertEqual(store.records().count, 2)
        XCTAssertEqual(Set(store.records().map { $0.details["source_family"] ?? "" }), ["communitysports", "plaviosports"])
        XCTAssertEqual(store.records().first { $0.details["source_family"] == "communitysports" }?.outcome, .success)
        XCTAssertEqual(store.records().first { $0.details["source_family"] == "plaviosports" }?.outcome, .failure)
        XCTAssertFalse(store.exportJSON().contains("papacito"))
    }

    func testAdditionalFailureAndOpaqueKeyRetainOwnFamilyWithoutRawURLs() {
        let failure = LiveStreamResolver.communitySportsFailure(from: .streamAdmissionRejected(entryCount: 3), providerName: "AS")
        XCTAssertEqual(failure.providerName, "AS")
        XCTAssertEqual(failure.redactedMetadata["addon_stream_entry_count"], "3")
        XCTAssertNil(failure.redactedMetadata["cs_stream_entry_count"])
        let source = StreamSource(url: URL(string: "https://example.com/private/stream.m3u8?ft=secret")!, quality: "HD", provider: "AS1")
        let details = FottyPlaybackQualityDetails.make(source: source, mode: "native", route: "single", attemptID: UUID(),
            sourceKey: "ps_0123456789abcdef01234567") // gitleaks:allow — synthetic opaque identifier
        XCTAssertEqual(details["source_family"], "plaviosports")
        XCTAssertEqual(details["source_key"], "ps_0123456789abcdef01234567")
        XCTAssertFalse(details.values.contains { $0.contains("secret") || $0.contains("example.com") })
    }
}
