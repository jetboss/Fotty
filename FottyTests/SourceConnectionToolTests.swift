import XCTest
@testable import Fotty

/// Explicit, fixture-pinned live tool. Ordinary test runs make no network calls.
/// All catalog matching, descriptor admission, relay and decoding use Fotty code.
@MainActor
final class SourceConnectionToolTests: XCTestCase {
    /// A one-window acceptance of the production fixture, registry, resolver
    /// join and CS adapter. No defaults shared with the app, media or player.
    func testOptInNHLRegisteredCSMetadata() async throws {
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("Hosted Catalyst metadata gate.")
        #else
        let environment = ProcessInfo.processInfo.environment
        guard (environment["FOTTY_NHL_CS_PREFLIGHT"] ?? environment["TEST_RUNNER_FOTTY_NHL_CS_PREFLIGHT"]) == "1" else {
            throw XCTSkip("Requires the explicit NHL window.")
        }
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-03T00:00:00Z"))
        guard (0...4 * 3600.0).contains(Date().timeIntervalSince(start)) else { throw XCTSkip("The pinned NHL window is closed.") }
        let suite = "FottyNHLMetadataPreflight." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = FottyBoundedHTTPClient(configuration: .ephemeral)
        let sports = SportsFixtureUpdater(defaults: defaults) { request in
            let response = try await transport.fetch(request, maximumBytes: SportsFixtureCatalog.maximumPayloadBytes,
                deadline: 12, acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
            return (response.data, response.http)
        }
        let registry = BroadcastRegistryClient(defaults: defaults)
        guard let fixtures = await sports.refresh(force: true), fixtures.sourceStatus.verifiesCurrentRows,
              let receipt = fixtures.receiptDate,
              (-300...SportsFixtureCatalog.statusFreshness).contains(Date().timeIntervalSince(receipt)),
              await registry.refresh(force: true) != nil else {
            XCTFail("Fresh deployed fixture or broadcast registry unavailable."); return
        }
        let catalog = SportsFixtureCatalog.merging(into: [], snapshot: fixtures, at: Date())
        let cs = CommunitySportsAddonClient()
        let pins: [(id: String, names: Set<String>)] = [
            ("sports-fixture:nhl:2026020232", ["Vegas Golden Knights", "Boston Bruins"]),
            ("sports-fixture:nhl:2026020233", ["Detroit Red Wings", "Florida Panthers"])
        ]
        for pin in pins {
            guard let event = catalog.first(where: { $0.id == pin.id }), event.kickoffDate == start,
                  let fixture = event.sportsFixture, fixture.isLive(at: Date()), fixture.sport == "hockey",
                  fixture.competitionID == "nhl", fixture.squad == .init(gender: .men, ageGroup: "senior"),
                  Set(fixture.participants.map(\.name)) == pin.names else {
                XCTFail("\(pin.id) lacks current verified exact live fixture authority."); continue
            }
            let request = StreamPlaybackRequest(event: event)
            let matches = registry.lookup(for: request, enabledProviderCodes: ["communitysports"])
            guard !matches.isEmpty else { XCTFail("\(pin.id) has no current registered CS association."); continue }
            do {
                let sessions = try await LiveStreamResolver.resolveRegisteredOptionalSessions(
                    for: request, providerCode: "communitysports", associations: matches,
                    resolve: { scoped in try await cs.resolve(for: scoped, now: Date(), forceRefresh: true) })
                let native = sessions.filter { $0.playbackContract.endpoint == .directMedia && $0.playbackContract.container == .hls }
                let rekeyed = native.filter { session in
                    matches.contains { association in
                        guard let binding = session.eventBinding else { return false }
                        return binding.providerEventID != association.broadcast.providerEventID
                            && binding.matchesRegistryEntry(association, request: request, at: Date())
                    }
                }
                print("FOTTY_NHL_CS_PREFLIGHT fixture=\(pin.id) listed=\(matches.count) admitted=\(sessions.count) hls=\(native.count) rekeyed_hls=\(rekeyed.count) decoded=not_tested")
                XCTAssertFalse(native.isEmpty, "\(pin.id) did not yield a registered native HLS choice.")
            } catch {
                let stage: String
                switch error as? CommunitySportsAddonError {
                case .some(.httpFailure(let status, let stageID)): stage = "\(stageID.rawValue)_http_\(status)"
                case .some(.transportFailure(_, let stageID)): stage = "\(stageID.rawValue)_transport"
                case .some(.invalidJSON(let stageID)): stage = "\(stageID.rawValue)_json"
                case .some(.conflictingMatch): stage = "identity_conflict"
                case .some(.streamEntriesEmpty): stage = "empty_descriptor"
                case .some(.streamAdmissionRejected(let count)): stage = "admission_rejected_\(count)"
                default: stage = "other_resolution_failure"
                }
                XCTFail("\(pin.id) registered resolution failed at \(stage).")
            }
        }
        #endif
    }

    struct Delivery: Codable {
        let label: String
        let endpoint: String
        var result = "not_tested"
        var frames: Int? = nil
        var progressSeconds: Double? = nil
        var startupSeconds: Double? = nil
        var phase: String? = nil
        var recheck: [String: Int]? = nil
        var httpStatus: Int? = nil
        var nativeErrorCode: Int? = nil
        var failureDetails: [String: String]? = nil
    }
    struct Row: Codable {
        let provider: String
        var catalog = "not_checked"
        var registeredMatches = 0
        var resolution = "not_checked"
        var failureStage: String? = nil
        var failureCategory: String? = nil
        var elapsedMilliseconds = 0
        var contractChecks: [String: Bool]? = nil
        var deliveries: [Delivery] = []
    }
    struct Report: Codable {
        let schemaVersion = 1
        let toolRevision = "2026-10-31.connection-2"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let fixtureID: String
        let title: String
        let kickoffUTC: String
        let mode: String
        let liveStatusAuthority: String
        var observedAtUTC: String
        var fixtureStatus: String
        var rows: [Row] = []
        var completion = "running"
        var sequence = 0
        var gateFailureCode: Int? = nil
    }
    private var report: Report?
    private let stamp = ISO8601DateFormatter()

    /// Channel-transport qualification does not fabricate an official fixture
    /// or establish the separate normal match-to-station Watch gate.
    func testReviewedTVExpandedChannelsThroughGuardedDecoder() throws {
        #if FOTTY_SOURCE_CONNECTION_TOOL && FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
        let env = ProcessInfo.processInfo.environment
        guard env["FOTTY_TV_CHANNEL_CANARY"] == "1" else {
            throw XCTSkip("Explicit reviewed-TV channel gate required; no playback check ran.")
        }
        let labels = (env["FOTTY_TV_CHANNEL_LABELS"] ?? "TV2,TV3,TV4,TV5,TV6,TV7,TV8")
            .split(separator: ",").map(String.init)
        guard !labels.isEmpty, labels.count <= 7, Set(labels).count == labels.count,
              labels.allSatisfy({ $0 != "TV1" && ReviewedTVPlaylistClient.channel(forProviderName: $0) != nil }) else {
            XCTFail("The bounded gate accepts only the finite reviewed TV2–TV8 stations"); return
        }
        let finished = expectation(description: "Reviewed TV channel transport collection")
        let operation = Task { @MainActor in
            defer { finished.fulfill() }
            var rows: [Delivery] = []
            func emitChannels(_ completion: String) {
                struct Receipt: Codable {
                    let schemaVersion = 1
                    let scope = "reviewed_channel_transport_only"
                    let observedAtUTC: String
                    let completion: String
                    let normalMatchWatchQualified = false
                    let deliveries: [Delivery]
                }
                let value = Receipt(observedAtUTC: self.stamp.string(from: Date()), completion: completion, deliveries: rows)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                guard let data = try? encoder.encode(value) else { return }
                let text = String(decoding: data, as: UTF8.self)
                print("FOTTY_TV_CHANNEL_REPORT " + text)
                let attachment = XCTAttachment(string: text)
                attachment.name = "Reviewed TV channel transport report"; attachment.lifetime = .keepAlways; self.add(attachment)
            }
            for label in labels {
                guard !Task.isCancelled else { emitChannels("interrupted"); return }
                guard await StreamPluginRegistry.shared.enabledProviderCodes().contains("reviewedtv") else {
                    emitChannels("source_not_enabled"); return
                }
                rows.append(Delivery(label: label, endpoint: "directMedia"))
                let index = rows.count - 1
                do {
                    let url = try await ReviewedTVPlaylistClient.shared.channelDelivery(forProviderName: label)
                    let session = StreamSession(matchID: "reviewed-channel-qualification:" + label, playableURL: url,
                        streamType: .hls, providerName: label, canRefresh: false,
                        diagnosticMetadata: ["source_family": "reviewedtv", "qualification_scope": "channel_transport_only"],
                        requiresGuardedRelay: true)
                    rows[index].result = "decoding"; emitChannels("running")
                    try await ReviewedAddonPhysicalCanary.run(on: self, source: .connection, verifiedSession: session) { evidence in
                        rows[index].phase = Self.safeCode(evidence["canary_phase"] ?? "unknown")
                        rows[index].frames = Int(evidence["decoded_frame_count"] ?? "")
                        rows[index].progressSeconds = Double(evidence["hold_progress_seconds"] ?? "")
                        rows[index].startupSeconds = Double(evidence["decoded_startup_seconds"] ?? "")
                        rows[index].httpStatus = Int(evidence["relay_http_status"] ?? "")
                        rows[index].nativeErrorCode = Int(evidence["native_error_code"] ?? "")
                        rows[index].failureDetails = Self.failureDetails(evidence)
                    }
                    rows[index].result = "decoded_90_seconds_channel_programme_review_required"
                } catch is XCTSkip {
                    rows[index].result = "physical_gate_unavailable"; emitChannels("physical_gate_unavailable"); return
                } catch {
                    rows[index].result = "channel_check_failed"
                }
                emitChannels("running")
            }
            emitChannels("channel_collection_complete_not_match_watch_qualification")
        }
        defer { operation.cancel() }
        waitForExpectations(timeout: 1_500)
        #else
        throw XCTSkip("The channel transport gate is absent from ordinary builds; no playback pass.")
        #endif
    }

    func testAllEnabledSourcesForVerifiedFootballFixture() throws {
        #if FOTTY_SOURCE_CONNECTION_TOOL
        guard ProcessInfo.processInfo.environment["FOTTY_SOURCE_CONNECTION_TOOL"] == "1" else {
            throw XCTSkip("Explicit connection-tool mode is required; no live check ran.")
        }
        #else
        throw XCTSkip("Connection tool is absent from this ordinary build; no live check ran.")
        #endif
        // Keep XCTest's async error-observation thunk out of this long-running
        // physical collector. The owned task reports redacted errors explicitly.
        let finished = expectation(description: "Bounded physical connection collection")
        let operation = Task { @MainActor in
            defer { finished.fulfill() }
            do { try await collectConnections() }
            catch is XCTSkip { /* Explicit mode absence is never a playback pass. */ }
            catch {
                self.report?.completion = "fixture_or_tool_gate_failed"
                if let failure = error as NSError?, failure.domain == "FottyConnectionFixture" {
                    self.report?.gateFailureCode = failure.code
                }
                self.emit()
                XCTFail("Connection collection could not complete; inspect the redacted receipt.")
            }
        }
        defer { operation.cancel() }
        waitForExpectations(timeout: 3_600)
    }

    private func collectConnections() async throws {
        #if FOTTY_SOURCE_CONNECTION_TOOL
        let env = ProcessInfo.processInfo.environment
        guard env["FOTTY_SOURCE_CONNECTION_TOOL"] == "1",
              let fixtureID = env["FOTTY_CONNECTION_FIXTURE"],
              Self.scoreboardCompetition(fixtureID) != nil else {
            throw XCTSkip("Requires the explicit fixture-pinned connection tool; no connection/playback pass.")
        }
        let playback = env["FOTTY_CONNECTION_PLAYBACK"] == "1"
        let initial = try await fixture(fixtureID, requireLive: playback)
        let request = StreamPlaybackRequest(event: initial)
        report = Report(fixtureID: fixtureID, title: initial.displayTitle,
            kickoffUTC: stamp.string(from: request.kickoffDate!), mode: playback ? "physical" : "metadata",
            liveStatusAuthority: playback ? "independent_espn_exact_fixture_in_progress" : "not_checked",
            observedAtUTC: stamp.string(from: Date()), fixtureStatus: initial.sportsFixture!.status.rawValue)
        defer { emit() }
        let enabled = Set(await StreamPluginRegistry.shared.enabledProviderCodes())
        let inventory = CuratedStreamSourceCatalog.all.filter { enabled.contains($0.providerCode) }
        XCTAssertFalse(inventory.isEmpty, "The tool must read actual enabled modules, not enable its own sources")
        await BroadcastRegistryClient.shared.refresh(force: true)
        var candidates: [(CuratedStreamSourceCatalog.Definition, [StreamSession])] = []
        for definition in inventory {
            guard await StreamPluginRegistry.shared.enabledProviderCodes().contains(definition.providerCode) else { continue }
            let event = try await fixture(fixtureID, requireLive: playback)
            let current = StreamPlaybackRequest(event: event)
            let started = ProcessInfo.processInfo.systemUptime
            var row = Row(provider: definition.providerCode)
            row.registeredMatches = BroadcastRegistryClient.shared.lookup(for: current,
                enabledProviderCodes: [definition.providerCode], at: Date()).count
            let unsupported = definition.dispatch == .reviewedTV
                ? !ReviewedTVPlaylistClient.channels.contains { $0.sports.contains(current.category) }
                : definition.isOptional && !definition.supportsDiscovery(category: current.category)
            if unsupported {
                row.catalog = "unsupported_sport"; row.resolution = "unsupported_sport"
                report!.rows.append(row); emit(); continue
            }
            do {
                let matches = try await catalog(definition, request: current)
                row.catalog = matches.first.map { String(describing: $0.outcome) } ?? "no_evidence"
            } catch {
                row.catalog = "catalog_failed"
            }
            let outcome = await LiveStreamResolver().inspectSourceConnection(definition, request: current)
            switch outcome {
            case .success(let success):
                let sessions = success.sessions.filter {
                    StreamPluginProviderMatching.matches($0.legacySource, code: definition.providerCode)
                }
                row.resolution = sessions.isEmpty ? "no_admitted_delivery" : "descriptors_admitted"
                row.deliveries = sessions.map {
                    Delivery(label: $0.providerName, endpoint: $0.playbackContract.endpoint.rawValue)
                }
                candidates.append((definition, sessions))
            case .failure(let failure, _):
                row.resolution = "resolution_failed"; row.failureCategory = failure.category.rawValue
                row.failureStage = ["addon_stage", "stage", "source_stage", "manifest_result"]
                    .compactMap { failure.redactedMetadata[$0] }.first.flatMap(Self.safeCode)
            }
            row.elapsedMilliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            report!.rows.append(row); emit()
        }
        guard playback else { report!.completion = "metadata_collection_complete_no_playback_claim"; return }
        #if os(iOS) && !targetEnvironment(macCatalyst) && FOTTY_REVIEWED_ADDON_CANARY
        // Breadth first: one real delivery from each source before its siblings.
        // Every delivery gets a fresh same-choice descriptor immediately before use.
        let maximum = candidates.map { $0.1.count }.max() ?? 0
        let selected = Set((env["FOTTY_CONNECTION_LABELS"] ?? "").split(separator: ",").map(String.init))
        for variant in 0..<maximum {
            for (definition, sessions) in candidates where variant < sessions.count {
                let original = sessions[variant]
                guard selected.isEmpty || selected.contains(original.providerName) else { continue }
                let index = report!.rows.firstIndex { $0.provider == definition.providerCode }!
                // XCTest's hosted WebKit entry aborts in the SDK error observer.
                // Keep this an explicit manual production-player gate, never a
                // provider failure or an automated decoded-playback pass.
                guard original.playbackContract.endpoint == .directMedia else {
                    report!.rows[index].deliveries[variant].result = "manual_web_gate_required"
                    emit(); continue
                }
                guard await StreamPluginRegistry.shared.enabledProviderCodes().contains(definition.providerCode) else {
                    report!.rows[index].deliveries[variant].result = "disabled_during_run"; emit(); continue
                }
                let event = try await fixture(fixtureID, requireLive: true)
                let current = StreamPlaybackRequest(event: event)
                let renewed = await LiveStreamResolver().inspectSourceConnection(definition, request: current)
                let currentChoices: [StreamSession]
                if case .success(let success) = renewed {
                    var checks: [String: Int] = ["resolved": success.sessions.count]
                    checks["sameLabel"] = success.sessions.filter { $0.providerName == original.providerName }.count
                    checks["sameQuality"] = success.sessions.filter { $0.qualityLabel == original.qualityLabel }.count
                    checks["sameEvent"] = success.sessions.filter { $0.eventBinding?.providerEventID == original.eventBinding?.providerEventID }.count
                    checks["sameStream"] = success.sessions.filter { $0.eventBinding?.streamID == original.eventBinding?.streamID }.count
                    checks["currentBinding"] = success.sessions.filter { $0.eventBinding?.matches(request: current, providerCode: definition.providerCode, at: Date()) == true }.count
                    report!.rows[index].deliveries[variant].recheck = checks
                    currentChoices = success.sessions.filter {
                          $0.providerName == original.providerName
                            && $0.qualityLabel == original.qualityLabel
                            && $0.playbackContract.endpoint == original.playbackContract.endpoint
                            && $0.eventBinding?.providerEventID == original.eventBinding?.providerEventID
                            && $0.eventBinding?.streamID == original.eventBinding?.streamID
                            && ($0.eventBinding?.matches(request: current, providerCode: definition.providerCode, at: Date()) == true
                                || $0.eventBinding == nil && $0.matchID == current.matchID
                                    && $0.validationStatus == .validated
                                    && StreamPluginProviderMatching.matches($0.legacySource, code: definition.providerCode))
                    }
                } else {
                    report!.rows[index].deliveries[variant].recheck = ["resolutionFailed": 1]
                    currentChoices = []
                }
                // This is a new qualification, not renewal of a playing item.
                // A signed delivery may rotate; current production admission
                // and one unambiguous upstream choice own the fresh test.
                guard currentChoices.count == 1, let fresh = currentChoices.first else {
                    report!.rows[index].deliveries[variant].result = "unavailable_on_fresh_recheck"; emit(); continue
                }
                report!.rows[index].deliveries[variant].result = "decoding"; emit()
                do {
                    let capture: @MainActor ([String: String]) -> Void = { evidence in
                            self.report!.rows[index].deliveries[variant].phase = Self.safeCode(evidence["canary_phase"] ?? "unknown")
                            self.report!.rows[index].deliveries[variant].frames = Int(evidence["decoded_frame_count"] ?? "")
                            self.report!.rows[index].deliveries[variant].progressSeconds = Double(evidence["hold_progress_seconds"] ?? "")
                            self.report!.rows[index].deliveries[variant].startupSeconds = Double(evidence["decoded_startup_seconds"] ?? "")
                            self.report!.rows[index].deliveries[variant].httpStatus = Int(evidence["relay_http_status"] ?? "")
                            self.report!.rows[index].deliveries[variant].nativeErrorCode = Int(evidence["native_error_code"] ?? "")
                            self.report!.rows[index].deliveries[variant].failureDetails = Self.failureDetails(evidence)
                    }
                    try await ReviewedAddonPhysicalCanary.run(on: self, source: .connection,
                        verifiedSession: fresh, evidence: capture)
                    _ = try await fixture(fixtureID, requireLive: true)
                    report!.rows[index].deliveries[variant].result = "decoded_90_seconds_programme_review_required"
                } catch is XCTSkip {
                    report!.rows[index].deliveries[variant].result = "physical_gate_unavailable"
                    report!.completion = "physical_gate_unavailable"; emit(); return
                } catch let error as NSError where error.domain == "FottyConnectionFixture" {
                    report!.rows[index].deliveries[variant].result = "fixture_recheck_unavailable"
                    report!.completion = "fixture_recheck_unavailable"; emit(); return
                } catch {
                    report!.rows[index].deliveries[variant].result = "physical_check_failed"
                }
                emit()
            }
        }
        report!.completion = "physical_collection_complete_review_each_delivery"
        #else
        throw XCTSkip("Physical connection decoding requires Jet iPad; metadata is not playback proof.")
        #endif
        #else
        throw XCTSkip("Connection tool is not compiled in this ordinary test build; no connection pass.")
        #endif
    }

    #if FOTTY_SOURCE_CONNECTION_TOOL
    private static func scoreboardCompetition(_ id: String) -> (fixture: String, scoreboard: String)? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "sports-fixture",
              parts[2].range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil else { return nil }
        switch parts[1] {
        case "premier-league": return ("premier-league", "eng.1")
        case "champions-league": return ("champions-league", "uefa.champions")
        default: return nil
        }
    }

    private func fixture(_ id: String, requireLive: Bool) async throws -> EventReference {
        let now = Date()
        guard let competition = Self.scoreboardCompetition(id),
              let snapshot = await SportsFixtureUpdater.shared.refresh(now: now, force: true),
              snapshot.sourceStatus.verifiesCurrentRows, let receipt = snapshot.receiptDate,
              (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(receipt)),
              let row = snapshot.fixtures.first(where: { $0.id == id }), row.sport == "football",
              row.competitionId == competition.fixture, row.squad == .init(gender: .men, ageGroup: "senior"),
              [.scheduled, .live].contains(row.status),
              let event = SportsFixtureCatalog.merging(into: [], snapshot: snapshot, at: now).first(where: { $0.id == id }),
              let identityReceipt = event.sportsFixture?.identityReceipt,
              (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(identityReceipt)),
              let start = event.kickoffDate, start >= now.addingTimeInterval(-3 * 3600),
              start <= now.addingTimeInterval(30 * 60) else {
            throw NSError(domain: "FottyConnectionFixture", code: 1)
        }
        if requireLive {
            // Independent current status corroborates the accepted schedule.
            // Do not promote a held app status or relax any source adapter:
            // failed production admission remains a failed matrix row.
            let day = stamp.string(from: start).prefix(10).replacingOccurrences(of: "-", with: "")
            let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/" + competition.scoreboard + "/scoreboard?dates=" + day)!
            let transport = FottyBoundedHTTPClient(configuration: .ephemeral)
            let result = try await transport.fetch(URLRequest(url: url), maximumBytes: 1_024 * 1_024,
                deadline: 8, acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
            struct Scoreboard: Decodable {
                struct Event: Decodable {
                    struct Status: Decodable { struct Kind: Decodable { let state: String }; let type: Kind }
                    struct Competition: Decodable {
                        struct Competitor: Decodable { struct Team: Decodable { let displayName: String }; let team: Team }
                        let competitors: [Competitor]
                    }
                    let date: String; let status: Status; let competitions: [Competition]
                }
                let events: [Event]
            }
            let scores = try JSONDecoder().decode(Scoreboard.self, from: result.data)
            guard let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: .init(event: event)) else {
                throw NSError(domain: "FottyConnectionFixture", code: 2)
            }
            let matches = scores.events.filter {
                let date = ISO8601DateFormatter().date(from: $0.date.replacingOccurrences(of: "Z", with: ":00Z"))
                    ?? ISO8601DateFormatter().date(from: $0.date)
                let names = $0.competitions.first?.competitors.map(\.team.displayName) ?? []
                return date == start && $0.status.type.state == "in"
                    && ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: names,
                        title: names.joined(separator: " vs "))?.pair == identity.pair
            }
            guard matches.count == 1 else { throw NSError(domain: "FottyConnectionFixture", code: 2) }
        }
        return event
    }

    private func catalog(_ source: CuratedStreamSourceCatalog.Definition,
                         request: StreamPlaybackRequest) async throws -> [FixtureSourceCatalogMatch] {
        switch source.dispatch {
        case .sharedCatalog:
            let row = try await LiveStreamResolver().resolveCatalogEvent(for: request)
            return [.init(matchID: request.matchID, outcome: row?.sources?.isEmpty == false ? .listed : .notListed)]
        case .score808: return try await Score808CatalogClient.shared.catalogMatches(for: [request])
        case .communitySports: return try await CommunitySportsAddonClient.shared.catalogMatches(for: [request])
        case .plavioSports: return try await PlavioSportsAddonClient.shared.catalogMatches(for: [request])
        case .cncSports: return try await CNCSportsAddonClient.shared.catalogMatches(for: [request])
        case .flixStreams: return try await FlixStreamsAddonClient.shared.catalogMatches(for: [request])
        case .reviewedTV:
            return [.init(matchID: request.matchID,
                outcome: ReviewedTVPlaylistClient.programmeLookupRequests(for: request).isEmpty ? .notListed : .listed)]
        }
    }
    #endif

    private static func safeCode(_ text: String) -> String? {
        text.count <= 100 && text.range(of: #"^[A-Za-z0-9_.:-]+$"#, options: .regularExpression) != nil ? text : nil
    }

    /// Keep enough causal detail for the complete batch review. URLs, error
    /// text, relay/request/resource identifiers and arbitrary fields stay out.
    static func failureDetails(_ evidence: [String: String]) -> [String: String] {
        let keys: Set<String> = ["relay_failure_stage", "relay_failure_kind", "relay_failure_resource_category",
            "relay_error_code", "relay_error_domain", "relay_http_status", "native_error_domain",
            "native_underlying_domain", "native_underlying_code", "native_failure_trigger", "native_hls_issue",
            "relay_request_outcome", "relay_same_resource_later_completed"]
        return evidence.reduce(into: [:]) { result, row in
            if keys.contains(row.key), let value = safeCode(row.value) { result[row.key] = value }
        }
    }

    func testFailureDetailsKeepCausalStageWithoutPrivateTransportData() {
        let result = Self.failureDetails(["relay_failure_stage": "upstream_response", "relay_failure_kind": "http_status",
            "relay_http_status": "502", "native_underlying_code": "-1008", "relay_failure_resource_category": "manifest",
            "relay_failure_request_id": "private-id", "relay_id": "another-id", "url": "https://private.invalid/media",
            "relay_error_domain": "https://private.invalid/error", "native_hls_issue": String(repeating: "x", count: 101)])
        XCTAssertEqual(result, ["relay_failure_stage": "upstream_response", "relay_failure_kind": "http_status",
            "relay_http_status": "502", "native_underlying_code": "-1008", "relay_failure_resource_category": "manifest"])
    }
    private func emit() {
        guard var report else { return }
        report.observedAtUTC = stamp.string(from: Date())
        report.sequence += 1
        self.report = report
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        let text = String(decoding: data, as: UTF8.self)
        print("FOTTY_CONNECTION_REPORT " + text)
        let attachment = XCTAttachment(string: text)
        attachment.name = "Fotty source connection report"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
