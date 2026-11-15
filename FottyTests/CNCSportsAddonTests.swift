import XCTest
@testable import Fotty

final class CNCSportsAddonTests: XCTestCase {
    private let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00Z")!
    // Synthetic URL-safe opaque values, never decoded into an endpoint or date.
    private let fixtureID = "cnc:" + String(repeating: "A", count: 1218) + "=="
    private let secondID = "cnc:" + String(repeating: "B", count: 1218) + "=="
    private let delivery = "https://edgestream7.pro/hls/offline_fixture.m3u8"

    private actor ProgressiveSessions {
        private var values: [StreamSession] = []
        func append(_ session: StreamSession) { values.append(session) }
        func snapshot() -> [StreamSession] { values }
    }

    @MainActor
    func testDiscoveryDeadlineRetainsAnAcknowledgedCNCChoiceAndItsPartialReceipt() async throws {
        let suite = "CNC.coordinator-deadline." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        let slow = CNCFixtureGate("CNC second stream held beyond discovery deadline")
        let session = try progressiveFixtureSession(cricket: false, second: .controlled(slow))
        let client = CNCSportsAddonClient(session: session, qualityStore: store)
        let fixture = request(), now = kickoff
        let scope = LiveSourceHealthStore.MatchEvidenceScope(request: fixture)
        let published = ProgressiveSessions()
        defer {
            slow.respond(.failure(URLError(.cancelled)))
            session.invalidateAndCancel(); CNCFixtureProtocol.reset()
            defaults.removePersistentDomain(forName: suite)
        }

        let result = await StreamDiscoveryCoordinator.collect(matchScope: scope, lanes: [{ report in
            do {
                let choices = try await client.resolve(for: fixture, now: now, onSession: { choice in
                    guard !Task.isCancelled,
                          choice.eventBinding?.matches(request: fixture, providerCode: "cncsports", at: now) == true
                    else { return false }
                    report(.partialSession(choice))
                    return true
                })
                let diagnostics = StreamAttemptDiagnostics(attemptID: "cnc-progressive-deadline",
                    matchID: fixture.matchID, matchTitle: fixture.displayTitle, finalState: .readyToPlay,
                    createdAt: now, completedAt: now, timeline: [], providerAttempts: [])
                return .success(StreamResolutionSuccess(attemptID: diagnostics.attemptID,
                    sessions: choices, diagnostics: diagnostics))
            } catch {
                let failure = StreamFailure(providerName: "LS", category: .navigationCancelled,
                    technicalMessage: "The owning discovery ended its CNC lane.",
                    userMessage: "Discovery ended.", retryable: true, fallbackAllowed: true)
                let diagnostics = StreamAttemptDiagnostics(attemptID: "cnc-progressive-deadline",
                    matchID: fixture.matchID, matchTitle: fixture.displayTitle, finalState: .failed,
                    createdAt: now, completedAt: now, timeline: [], providerAttempts: [])
                return .failure(failure, diagnostics)
            }
        }],
        // One lane with incremental publication bypasses choice-grace exits.
        // Its second offline response remains held until after the real owner
        // deadline. There is no sub-second expectation or scheduling sleep.
        deadline: .seconds(3), preferDirectInitialChoice: true, clock: { now },
        onSessions: { choices in
            for choice in choices { await published.append(choice) }
        })

        XCTAssertTrue(CNCFixtureProtocol.paths.contains(streamPath(secondID)),
            "The admitted first listing was followed by a genuinely pending sibling")
        XCTAssertTrue(result.reachedDeadline)
        XCTAssertEqual(result.exitReason, .deadline)
        XCTAssertEqual(result.incompleteLanes, 1)
        XCTAssertEqual(result.sessions.map(\.providerName), ["LS1"])
        XCTAssertTrue(result.sessions.first?.eventBinding?.matches(request: fixture,
            providerCode: "cncsports", at: now) == true)
        let beforeLateResponse = await published.snapshot()
        XCTAssertEqual(beforeLateResponse.map(\.id), result.sessions.map(\.id),
            "The collector publishes and retains the same independently admitted choice")

        // collect waits for cancelled child cleanup. A subsequently delivered
        // fixture response cannot append a second choice or change accounting.
        slow.respond(try .json(["streams": [["url": "https://edgestream7.pro/hls/deadline.m3u8"]]]))
        let afterLateResponse = await published.snapshot()
        XCTAssertEqual(afterLateResponse.map(\.id), beforeLateResponse.map(\.id))
        let receipts = store.records().filter { $0.name == "stream_admission" }
        XCTAssertEqual(receipts.count, 1)
        let details = try XCTUnwrap(receipts.first).details
        XCTAssertEqual(details["offered_count"], "1")
        XCTAssertEqual(details["admitted_count"], "1")
        XCTAssertEqual(details["admission_withdrawn_count"], "0")
        XCTAssertEqual(details["admission_completion"], "partial")
        XCTAssertEqual(details["admission_fetch_failures"], "0")
        XCTAssertEqual(details["admission_reconciled"], "yes")
    }


    @MainActor
    func testProgressiveHockeyAndCricketKeepAcknowledgedChoiceAfterSiblingCancellation() async throws {
        for cricket in [false, true] {
            let suite = "CNC.progressive." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let store = FottyQualityStore(defaults: defaults)
            let slow = CNCFixtureGate("second stream request")
            let fixture = cricket ? wbblRequest() : request()
            let now = try XCTUnwrap(fixture.kickoffDate)
            let session = try progressiveFixtureSession(cricket: cricket, second: .controlled(slow))
            let client = CNCSportsAddonClient(session: session, qualityStore: store)
            let observed = ProgressiveSessions()
            let operation = Task {
                try await client.resolve(for: fixture, now: now, onSession: { choice in
                    await observed.append(choice)
                    return true
                })
            }
            defer {
                operation.cancel(); slow.respond(.failure(URLError(.cancelled)))
                session.invalidateAndCancel(); CNCFixtureProtocol.reset()
                defaults.removePersistentDomain(forName: suite)
            }
            // Reaching listing two proves listing one's callback has completed;
            // no sleep or real transport timeout establishes the ordering.
            await fulfillment(of: [slow.started], timeout: 3)
            let before = await observed.snapshot()
            XCTAssertEqual(before.map(\.providerName), ["LS1"])
            XCTAssertTrue(before.first?.eventBinding?.matches(request: fixture,
                providerCode: "cncsports", at: now) == true)
            operation.cancel()
            slow.respond(try .json(["streams": [["url": "https://edgestream7.pro/hls/second.m3u8"]]]))
            do { _ = try await operation.value; XCTFail("Cancellation cannot return an aggregate success") }
            catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
            let after = await observed.snapshot()
            XCTAssertEqual(after.map(\.id), before.map(\.id), "A late sibling cannot publish after cancellation")
            let receipts = store.records().filter { $0.name == "stream_admission" }
            XCTAssertEqual(receipts.count, 1)
            let details = try XCTUnwrap(receipts.first).details
            XCTAssertEqual(details["offered_count"], "1", "An unread sibling has no invented entry count")
            XCTAssertEqual(details["admitted_count"], "1")
            XCTAssertEqual(details["admission_withdrawn_count"], "0")
            XCTAssertEqual(details["admission_completion"], "partial")
            XCTAssertEqual(details["admission_fetch_failures"], "0")
            XCTAssertEqual(details["admission_reconciled"], "yes")
        }
    }

    @MainActor
    func testProgressiveCancellationWithoutAcknowledgementWithdrawsTheObservedChoice() async throws {
        let suite = "CNC.unacknowledged." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        let slow = CNCFixtureGate("unacknowledged sibling")
        let session = try progressiveFixtureSession(cricket: false, second: .controlled(slow))
        let client = CNCSportsAddonClient(session: session, qualityStore: store)
        let observed = ProgressiveSessions(), fixture = request(), now = kickoff
        let operation = Task {
            try await client.resolve(for: fixture, now: now, onSession: { choice in
                await observed.append(choice)
                return false
            })
        }
        defer {
            operation.cancel(); slow.respond(.failure(URLError(.cancelled)))
            session.invalidateAndCancel(); CNCFixtureProtocol.reset()
            defaults.removePersistentDomain(forName: suite)
        }
        await fulfillment(of: [slow.started], timeout: 3)
        let offered = await observed.snapshot()
        XCTAssertEqual(offered.count, 1)
        operation.cancel()
        slow.respond(try .json(["streams": [["url": "https://edgestream7.pro/hls/declined.m3u8"]]]))
        do { _ = try await operation.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        let final = await observed.snapshot()
        XCTAssertEqual(final.map(\.id), offered.map(\.id))
        let details = try XCTUnwrap(store.records().first { $0.name == "stream_admission" }).details
        XCTAssertEqual(details["offered_count"], "1")
        XCTAssertEqual(details["admitted_count"], "0")
        XCTAssertEqual(details["admission_withdrawn_count"], "1")
        XCTAssertEqual(details["admission_completion"], "cancelled")
        XCTAssertEqual(details["admission_fetch_failures"], "0")
        XCTAssertEqual(details["admission_reconciled"], "yes")
    }

    func testProgressiveCancellationBeforeFirstResponseNeverPublishes() async throws {
        let suite = "CNC.unread-cancelled." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        let slow = CNCFixtureGate("first stream request")
        let session = try fixtureSession(streams: .controlled(slow))
        let client = CNCSportsAddonClient(session: session, qualityStore: store)
        let observed = ProgressiveSessions(), fixture = request(), now = kickoff
        let operation = Task {
            try await client.resolve(for: fixture, now: now, onSession: { choice in
                await observed.append(choice)
                return true
            })
        }
        defer {
            operation.cancel(); slow.respond(.failure(URLError(.cancelled)))
            session.invalidateAndCancel(); CNCFixtureProtocol.reset()
            defaults.removePersistentDomain(forName: suite)
        }
        await fulfillment(of: [slow.started], timeout: 3)
        operation.cancel()
        slow.respond(try .json(["streams": [["url": delivery]]]))
        do { _ = try await operation.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        let choices = await observed.snapshot()
        XCTAssertTrue(choices.isEmpty)
        let details = try XCTUnwrap(store.records().first { $0.name == "stream_admission" }).details
        XCTAssertNil(details["offered_count"])
        XCTAssertEqual(details["admission_observation"], "unread")
        XCTAssertEqual(details["admission_completion"], "cancelled")
        XCTAssertEqual(details["admission_fetch_failures"], "0")
    }

    @MainActor
    func testProgressiveAndDefaultLookupsPreserveSessionOrderAndLabels() async throws {
        let session = try progressiveFixtureSession(cricket: false,
            second: .json(["streams": [["url": "https://edgestream7.pro/hls/offline_fixture_second.m3u8"]]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let observed = ProgressiveSessions()
        let progressive = try await client.resolve(for: request(), now: kickoff, onSession: { choice in
            await observed.append(choice)
            return true
        })
        let published = await observed.snapshot()
        XCTAssertEqual(published.map(\.id), progressive.map(\.id), "Final collection cannot renumber or duplicate emitted choices")
        XCTAssertEqual(progressive.map(\.providerName), ["LS1", "LS2"])
        let aggregate = try await client.resolve(for: request(), now: kickoff, forceRefresh: true)
        XCTAssertEqual(aggregate.map(\.playableURL), progressive.map(\.playableURL))
        XCTAssertEqual(aggregate.map(\.providerName), progressive.map(\.providerName))
    }

    @MainActor
    private func progressiveFixtureSession(cricket: Bool, second: CNCFixtureProtocol.Response) throws -> URLSession {
        var manifest = manifestJSON()
        manifest["catalogs"] = [CNCSportsAddonClient.catalogID, CNCSportsAddonClient.cricketCatalogID].map {
            ["id": $0, "type": "tv"]
        }
        let name = cricket ? "🔜 " + wbblName : "🔴 Blackhawks vs Canadiens"
        let metadataName = cricket ? wbblName : "Blackhawks vs Canadiens"
        let descriptionText = cricket ? wbblDescription : description()
        let session = try fixtureSession(manifest: .json(manifest),
            meta: .json(["meta": metadataJSON(name: metadataName, description: descriptionText)]),
            streams: .json(["streams": [cricket ? wbblStreamJSON() : streamJSON()]]))
        let catalog = cricket ? "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json" : catalogPath
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: name), catalogJSON(id: secondID, name: name)]]), for: catalog)
        CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: secondID,
            name: metadataName, description: descriptionText)]), for: metaPath(secondID))
        CNCFixtureProtocol.setResponse(second, for: streamPath(secondID))
        return session
    }

    func testForegroundPartialPublicationRechecksEnablementIdentityAndCancellation() async throws {
        let transport = try fixtureSession()
        defer { transport.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let fixture = request(), now = kickoff
        let choices = try await CNCSportsAddonClient(session: transport).resolve(for: fixture, now: now)
        let choice = try XCTUnwrap(choices.first)
        let reported = expectation(description: "Only the current enabled choice is handed to discovery")
        let accepted = await LiveStreamResolver.publishDirectOptionalSession(choice, request: fixture,
            providerCode: "cncsports", enabledCodes: { ["cncsports"] }, clock: { now }, report: { update in
                if case .partialSession(let offered) = update { XCTAssertEqual(offered.id, choice.id); reported.fulfill() }
                else { XCTFail("Expected one partial choice") }
            })
        XCTAssertTrue(accepted)
        await fulfillment(of: [reported], timeout: 3)
        for (codes, scoped, checkedAt) in [([String](), fixture, now),
            (["cncsports"], request(at: now.addingTimeInterval(24 * 3600)), now),
            (["cncsports"], fixture, now.addingTimeInterval(StreamEventBinding.metadataLifetime + 1))] {
            let accepted = await LiveStreamResolver.publishDirectOptionalSession(choice, request: scoped,
                providerCode: "cncsports", enabledCodes: { codes }, clock: { checkedAt },
                report: { _ in XCTFail("Disabled, changed or expired authority must not publish") })
            XCTAssertFalse(accepted)
        }
        let reading = expectation(description: "Enablement read suspended")
        let operation = Task {
            await LiveStreamResolver.publishDirectOptionalSession(choice, request: fixture,
                providerCode: "cncsports", enabledCodes: {
                    reading.fulfill()
                    do { try await Task.sleep(for: .seconds(30)) } catch { }
                    return ["cncsports"]
                }, clock: { now }, report: { _ in XCTFail("A late enabled result cannot publish after cancellation") })
        }
        await fulfillment(of: [reading], timeout: 3)
        operation.cancel()
        let cancelledAccepted = await operation.value
        XCTAssertFalse(cancelledAccepted)
    }

    func testPartialFetchReceiptSurvivesBothSuccessfulAndThrowingAggregateLookups() async throws {
        let suite = "CNCSports.partial." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let second = secondID
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(), catalogJSON(id: second)]]),
            streams: .failure(URLError(.timedOut)))
        CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: second)]), for: metaPath(second))
        let secondPath = streamPath(second)
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session, qualityStore: store)
        CNCFixtureProtocol.setResponse(try .json(["streams": [["url": delivery]]]), for: secondPath)
        let accepted = try await client.resolve(for: request(), now: kickoff, forceRefresh: true)
        XCTAssertEqual(accepted.count, 1)
        CNCFixtureProtocol.setResponse(try .json(["streams": [["url": delivery, "drm": true]]]), for: secondPath)
        do {
            _ = try await client.resolve(for: request(), now: kickoff, forceRefresh: true)
            XCTFail("A failed sibling keeps the aggregate incomplete")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError,
                .transportFailure(code: URLError.timedOut.rawValue, stage: .streams))
        }
        let receipts = store.records().filter { $0.name == "stream_admission" }
        XCTAssertEqual(receipts.count, 2)
        XCTAssertEqual(Set(receipts.compactMap { $0.details["admission_lookup_id"] }).count, 2)
        for receipt in receipts {
            XCTAssertEqual(receipt.details["offered_count"], "1")
            XCTAssertEqual(receipt.details["admission_fetch_failures"], "1")
            XCTAssertEqual(receipt.details["admission_completion"], "partial")
            XCTAssertEqual(receipt.details["admission_reconciled"], "yes")
            XCTAssertEqual(receipt.details["admission_unprocessed_count"], "0")
        }
        let acceptedReceipt = try XCTUnwrap(receipts.first { $0.details["admitted_count"] == "1" })
        XCTAssertEqual(acceptedReceipt.details["admission_drm_count"], "0")
        let rejectedReceipt = try XCTUnwrap(receipts.first { $0.details["admitted_count"] == "0" })
        XCTAssertEqual(rejectedReceipt.details["admission_drm_count"], "1")
    }

    func testUnreadFailureNeverBecomesAConfirmedZeroOffer() async throws {
        let suite = "CNCSports.unread." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        CNCFixtureProtocol.setResponse(.status(503), for: "/manifest.json")
        do {
            _ = try await CNCSportsAddonClient(session: session, qualityStore: store).resolve(for: request(), now: kickoff)
            XCTFail("Manifest failure")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .manifest))
        }
        let receipts = store.records().filter { $0.name == "stream_admission" }
        XCTAssertEqual(receipts.count, 1)
        let detail = try XCTUnwrap(receipts.first).details
        XCTAssertNil(detail["offered_count"])
        XCTAssertEqual(detail["admission_observation"], "unread")
        XCTAssertEqual(detail["admission_completion"], "failed")
        XCTAssertEqual(detail["admission_fetch_failures"], "1")
    }

    func testCommonAdmissionAccountsForEveryMixedRowWithoutGuessingContentFromTheURL() async throws {
        let suite = "CNCSports.admission." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let php = "https://video.example.org/play.php?token=fixture"
        let bare = "https://video.example.org/live/opaque"
        let rows: [Any] = [NSNull(), "bad-row", ["url": 17],
            ["url": php, "drm": true], ["url": php, "headers": ["Cookie": "private"]],
            ["url": php, "headers": 7], ["url": "http://video.example.org/live"],
            ["url": "https://video.example.org/wrap?url=http%3A%2F%2F127.0.0.1%2Fprivate"],
            ["url": php, "headers": NSNull(), "behaviorHints": NSNull(), "drm": false,
                "clearkey": NSNull(), "licenseUrl": "", "license": [:]],
            ["url": php, "behaviorHints": ["proxyHeaders": ["request": NSNull()]], "drm": [:]],
            ["url": bare, "headers": ["User-Agent": "Player A"], "drmInfo": []],
            ["url": bare, "headers": ["User-Agent": "Player B"], "drmHeaders": NSNull()]]
        let session = try fixtureSession(streams: .json(["streams": rows]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let result = try await CNCSportsAddonClient(session: session, qualityStore: store)
            .resolve(for: request(), now: kickoff, forceRefresh: true)
        XCTAssertEqual(result.map { $0.playableURL.absoluteString }, [php, bare, bare])
        XCTAssertEqual(result.map(\.providerName), ["LS1", "LS2", "LS3"])
        XCTAssertEqual(result.map(\.requiredHeaders), [[:], ["User-Agent": "Player A"], ["User-Agent": "Player B"]])
        XCTAssertTrue(result.allSatisfy { $0.requiresGuardedRelay == true })
        let receipts = store.records().filter { $0.name == "stream_admission" }
        XCTAssertEqual(receipts.count, 1)
        let detail = try XCTUnwrap(receipts.first).details
        XCTAssertEqual(detail["offered_count"], "12")
        XCTAssertEqual(detail["admitted_count"], "3")
        XCTAssertEqual(detail["admission_malformed_count"], "2")
        for reason in ["no_url", "drm", "credential_headers", "malformed_headers", "not_https", "inner_not_https", "duplicate"] {
            XCTAssertEqual(detail["admission_" + reason + "_count"], "1", reason)
        }
        XCTAssertEqual(detail["admission_completion"], "complete")
        XCTAssertEqual(detail["admission_unprocessed_count"], "0")
        XCTAssertEqual(detail["admission_reconciled"], "yes")
        XCTAssertFalse(detail.description.contains("token=fixture"))
        XCTAssertFalse(detail.description.contains("private"))
    }

    func testAggregateSessionLimitAccountsForLaterDuplicatesAndHeaderVariants() throws {
        let rows: [[String: Any]] = (0..<100).map { ["url": "https://video.example.org/opaque/\($0)"] }
        func decode(_ rows: [[String: Any]]) throws -> [CNCSportsStreamEntry] {
            try rows.map { try JSONDecoder().decode(CNCSportsStreamEntry.self, from: data($0)) }
        }
        var ledger = StreamAdmissionLedger()
        ledger.observe(103)
        let first = CNCSportsAddonClient.makeSessions(from: try decode(rows), request: request(),
            addOnVersion: "1.0.0", ledger: &ledger)
        let later: [[String: Any]] = [rows[0],
            ["url": "https://video.example.org/opaque/0", "headers": ["User-Agent": "different"]],
            ["url": "https://video.example.org/opaque/later"]]
        let second = CNCSportsAddonClient.makeSessions(from: try decode(later), request: request(),
            addOnVersion: "1.0.0", after: first, ledger: &ledger)
        ledger.finish(admitted: first.count + second.count, completion: "limited")
        XCTAssertEqual(first.count, 100)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(ledger.dispositions["duplicate"], 1)
        XCTAssertEqual(ledger.dispositions["limit"], 2)
        XCTAssertEqual(ledger.admitted, 100)
        XCTAssertTrue(ledger.isReconciled)
    }

    func testReviewedManifestRequiresExactIdentityStringResourcesAndOneFixedCatalog() throws {
        let manifest = try CNCSportsAddonClient.validateManifest(data: data(manifestJSON()))
        XCTAssertEqual(manifest.id, "com.cncverse.stremiobridge")
        XCTAssertEqual(manifest.version, "1.0.30")
        XCTAssertEqual(CNCSportsAddonClient.catalogID, "cnc_LivXowLiveEvents_tv")
        for mutation: [String: Any] in [
            ["id": "com.lookalike"], ["version": "https://private.example/key"],
            ["resources": ["catalog", "stream"]], ["resources": ["catalog", "meta", "stream", "stream"]],
            ["resources": [["name": "catalog"], ["name": "meta"], ["name": "stream"]]],
            ["types": ["sport"]], ["types": ["tv", "unknown"]],
            ["catalogs": [["id": "another-catalog", "type": "tv"]]],
            ["catalogs": [["id": CNCSportsAddonClient.catalogID, "type": "tv"], ["id": CNCSportsAddonClient.catalogID, "type": "tv"]]],
            ["behaviorHints": ["configurationRequired": true]]
        ] {
            XCTAssertThrowsError(try CNCSportsAddonClient.validateManifest(data: data(manifestJSON().merging(mutation) { _, new in new })))
        }
    }

    func testObservedNHLAliasesOnlyPreselectMetadataAndExplicitUTCFinishesTheJoin() throws {
        let row = catalogEntry()
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [row]), [fixtureID])
        let meta = metadata()
        XCTAssertEqual(CNCSportsAddonClient.explicitKickoff(for: meta), kickoff)
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [row], metadata: [meta]).id, fixtureID)
        let reverse = catalogEntry(name: "🔴 Canadiens vs Blackhawks")
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [reverse],
            metadata: [metadata(name: "Montreal Canadiens vs Chicago Blackhawks")]).id, fixtureID)
        XCTAssertNil(SportsTeamIdentity.known(name: "Blackhawks", category: "hockey"), "No global alias was installed")
        XCTAssertNil(SportsTeamIdentity.known(name: "Canadiens", category: "hockey"))
    }

    func testObservedCapitalsFlyersNamesJoinOnlyTheCorroboratedFullNHLPair() throws {
        let request = capitalsFlyersRequest()
        let row = catalogEntry(name: "🔴 Capitals vs Flyers")
        let meta = metadata(name: "Capitals vs Flyers", description: capitalsFlyersDescription)
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request, from: [row]), [fixtureID])
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request, catalog: [row], metadata: [meta]).id, fixtureID)
        let reversed = catalogEntry(name: "🔴 Flyers vs Capitals")
        let fullNames = metadata(name: "Philadelphia Flyers vs Washington Capitals", description: capitalsFlyersDescription)
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request, catalog: [reversed], metadata: [fullNames]).id, fixtureID)
        XCTAssertNil(SportsTeamIdentity.known(name: "Capitals", category: "hockey"), "Alias remains source-local")
        XCTAssertNil(SportsTeamIdentity.known(name: "Flyers", category: "hockey"))
    }

    func testCapitalsFlyersAliasesCannotAdmitOtherSquadsExtendedNamesOrConflictingSibling() throws {
        let request = capitalsFlyersRequest()
        for name in ["🔴 Capitals Women vs Flyers Women", "🔴 Capitals U19 vs Flyers U19",
                     "🔴 Capitals Reserves vs Flyers Reserves", "🔴 College Capitals vs Flyers",
                     "🔴 Other Capitals vs Flyers", "🔴 Capitals vs Other Flyers"] {
            XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request,
                from: [catalogEntry(name: name)]).isEmpty, name)
        }
        let exact = catalogEntry(name: "🔴 Capitals vs Flyers")
        let conflict = catalogEntry(name: "🔴 Other Capitals vs Flyers")
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request, from: [exact, conflict]).isEmpty,
                      "An id whose own rows disagree is dropped")
    }

    func testNormalClientDiscoversObservedCapitalsFlyersThroughExactMetadataBeforeStreams() async throws {
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(name: "🔴 Capitals vs Flyers")]]),
            meta: .json(["meta": metadataJSON(name: "Capitals vs Flyers", description: capitalsFlyersDescription)]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let request = capitalsFlyersRequest()
        let values = try await CNCSportsAddonClient(session: session).resolve(for: request, now: request.kickoffDate!)
        XCTAssertEqual(values.map(\.providerName), ["LS1"])
        XCTAssertEqual(values.first?.matchID, "sports-fixture:nhl:2026020199")
        let resolved = try XCTUnwrap(values.first)
        let binding = try XCTUnwrap(resolved.eventBinding)
        XCTAssertEqual(binding.providerEventID, fixtureID)
        XCTAssertEqual(binding.streamID, fixtureID)
        XCTAssertTrue(binding.matches(request: request, providerCode: "cncsports", at: try XCTUnwrap(request.kickoffDate)))
        XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(resolved))
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath, metaPath(fixtureID), streamPath(fixtureID)])
    }

    @MainActor
    func testRegisteredTorontoUtahLookupPublishesTheVerifiedCNCBackup() async throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z"))
        let teams = ["Toronto Maple Leafs", "Utah Mammoth"]
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:nhl:2026020236", sport: "hockey",
            competitionID: "nhl", competitionName: "NHL", eventKind: .match, title: teams.joined(separator: " vs "),
            participants: [.init(id: "tor", name: teams[0]), .init(id: "uta", name: teams[1])],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: start, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "hockey",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0], badge: nil), away: .init(name: teams[1], badge: nil)), sportsFixture: metadata, competitionID: "nhl")
        let request = StreamPlaybackRequest(event: event), expiry = start.addingTimeInterval(600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "c", count: 64),
            providerCode: "cncsports", providerEventID: fixtureID, streamID: fixtureID, resourceType: "tv",
            scope: "hockey", kind: .event, sport: "hockey", title: metadata.title, participants: teams, start: start,
            competitionID: "nhl", squad: metadata.squad, observedAt: start, expiresAt: expiry, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "cncsports",
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "hockey",
                start: start, participants: teams, competitionID: "nhl", squad: metadata.squad), expiresAt: expiry)
        let association = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: "cncsports",
            scope: "hockey", status: .available, observedAt: start, expiresAt: expiry))
        let shortTitle = "Maple Leafs vs Mammoth"
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(name: "🔴 " + shortTitle)]]),
            meta: .json(["meta": metadataJSON(name: shortTitle, description:
                "📌 Hockey\n🏆 NHL\n🕐 Nov 04, 2026 00:00 UTC\n\n📡 Available Servers: 1")]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let scoped = request.usingRegistryMatch(association)
        XCTAssertTrue(association.matches(request: scoped, providerCode: "cncsports", providerEventID: fixtureID, streamID: fixtureID, at: start))
        XCTAssertEqual(ReviewedSportsFixtureMatcher.requestIdentity(for: scoped)?.pair,
            BroadcastRegistrySnapshot.participantPair(teams, sport: "hockey"))
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: scoped,
            from: [catalogEntry(name: shortTitle)]), [fixtureID])
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: scoped,
            catalog: [catalogEntry(name: shortTitle)], metadata: [self.metadata(name: shortTitle, description:
                "📌 Hockey\n🏆 NHL\n🕐 Nov 04, 2026 00:00 UTC\n\n📡 Available Servers: 1")], at: start).id, fixtureID)
        let choices = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request, providerCode: "cncsports",
            associations: [association], resolve: { try await client.resolve(for: $0, now: start) }, clock: { start })
        XCTAssertEqual(choices.map(\.providerName), ["LS1"])
        XCTAssertEqual(choices.first?.eventBinding?.usesRegistryAssociation, true)
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request,
            from: [catalogEntry(name: "🔴 Maple Leafs U19 vs Mammoth U19")]).isEmpty)
    }

    func testObservedCapitalsFlyersAliasStillRejectsWrongDateLeagueAndSquadBeforeStreams() async throws {
        for meta in [
            metadataJSON(name: "Capitals vs Flyers", description: capitalsFlyersDescription.replacingOccurrences(of: "Oct 28", with: "Oct 27")),
            metadataJSON(name: "Capitals vs Flyers", description: capitalsFlyersDescription.replacingOccurrences(of: "NHL", with: "College")),
            metadataJSON(name: "Capitals Women vs Flyers Women", description: capitalsFlyersDescription)
        ] {
            let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(name: "🔴 Capitals vs Flyers")]]),
                meta: .json(["meta": meta]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do {
                _ = try await CNCSportsAddonClient(session: session).resolve(for: capitalsFlyersRequest())
                XCTFail("Exact aliases cannot replace independent date, league or squad proof")
            } catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    func testOnlyReviewedNHLSportCompetitionAndFullEnglishUTCDescriptionSupplyDate() {
        let original = description()
        let invalid: [String?] = [nil, "LIVE", "Oct 24, 2026 00:00 UTC", original + "\n",
            original.replacingOccurrences(of: "Hockey", with: "Basketball"),
            original.replacingOccurrences(of: "NHL", with: "NBA"),
            original.replacingOccurrences(of: "UTC", with: "GMT"),
            original.replacingOccurrences(of: "Oct 24, 2026", with: "Oct 24"),
            original.replacingOccurrences(of: "Oct 24, 2026", with: "Feb 31, 2026"),
            original.replacingOccurrences(of: "00:00", with: "24:00"),
            original.replacingOccurrences(of: "\n", with: "\r\n"),
            original.replacingOccurrences(of: "Servers: 1", with: "Servers: unknown"),
            original.replacingOccurrences(of: "\n\n", with: "\n")]
        for value in invalid {
            let meta = metadata(description: value)
            XCTAssertNil(CNCSportsAddonClient.explicitKickoff(for: meta))
            XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [catalogEntry()], metadata: [meta]))
        }
    }

    func testOpaqueIDsRemainLiteralBoundedAndNeverGrantEmbeddedAddressAuthority() {
        XCTAssertTrue(CNCSportsAddonClient.isSafeFixtureID(fixtureID))
        for id in ["", "cnc:", "cnc:a/b", "cnc:a?token=value", "cnc:a#fragment", "cnc:a%2Fb",
                   "cnc:a:b", "cnc:a=b", "cnc:a===", "cnc:a\n", "cnc:" + String(repeating: "A", count: 4093)] {
            XCTAssertFalse(CNCSportsAddonClient.isSafeFixtureID(id))
        }
        XCTAssertTrue(CNCSportsAddonClient.isSafeFixtureID("cnc:" + String(repeating: "A", count: 4092)))
    }

    func testPreselectionRejectsUnreviewedSquadsSportPlaceholderAndMoreThanTwoExactIDs() throws {
        for name in ["🔴 Blackhawks Women vs Canadiens Women", "🔴 Blackhawks U19 vs Canadiens U19", "🔴 Blackhawks Reserves vs Canadiens Reserves",
                     "🔴 Other Blackhawks vs Canadiens", "🔴 TBC vs Canadiens", "🔴 Blackhawks vs Other Team",
                     "🔴 Blackhawks vs Canadiens | Women's Hockey", "🔴 Blackhawks vs Canadiens vs Bruins"] {
            XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [catalogEntry(name: name)]).isEmpty)
        }
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(category: "football"), from: [catalogEntry()]).isEmpty)
        let undated = StreamPlaybackRequest(matchID: "existing", displayTitle: "Chicago Blackhawks vs Montreal Canadiens",
            homeTeam: "Chicago Blackhawks", awayTeam: "Montreal Canadiens", category: "hockey")
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: undated, from: [catalogEntry()]).isEmpty)
        let rows = [catalogEntry(), catalogEntry(id: secondID), catalogEntry(id: "cnc:third")]
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: rows),
                       [fixtureID, secondID, "cnc:third"], "Every listing of the game counts")
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [rows[0], rows[0], rows[1]]).count, 2)
    }

    func testMalformedCatalogMetadataOrEffectiveTargetSiblingCannotDisappearBeforeSelection() throws {
        let exact = catalogEntry()
        let malformed = [catalogEntry(name: "Other Club vs Another Club"), catalogEntry(type: "movie"),
            CNCSportsCatalogEntry(id: fixtureID, name: "🔴 Blackhawks vs Canadiens", hasMalformedIdentity: true),
            CNCSportsCatalogEntry(id: "cnc:other", effectiveID: fixtureID, name: "Other vs Another", hasMalformedIdentity: true)]
        // A malformed or different row on the same id drops that id: nothing from it plays.
        for row in malformed {
            for entries in [[exact, row], [row, exact]] {
                XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: entries).isEmpty)
            }
        }
        var raw = catalogJSON(); raw["name"] = NSNull()
        let decoded = try JSONDecoder().decode(CNCSportsCatalogEntry.self, from: data(raw))
        XCTAssertEqual(decoded.id, fixtureID); XCTAssertTrue(decoded.hasMalformedIdentity)
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [exact, decoded]).isEmpty)
        for hints: Any in [NSNull(), [:], ["defaultVideoId": "cnc:other"],
                           ["defaultVideoId": fixtureID, "proxyHeaders": [:]]] {
            var changed = catalogJSON(); changed["behaviorHints"] = hints
            let row = try JSONDecoder().decode(CNCSportsCatalogEntry.self, from: data(changed))
            XCTAssertTrue(row.hasMalformedIdentity)
            XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [exact, row]).isEmpty)
        }
    }

    func testMetadataMustCorroborateIDTypePairSquadAndExactRequestTime() throws {
        for meta in [metadata(id: secondID), metadata(type: "movie"), metadata(name: "Blackhawks vs Bruins"),
                     metadata(name: "Blackhawks Women vs Canadiens Women"), metadata(name: "Blackhawks U19 vs Canadiens U19"),
                     metadata(description: description(time: "20:00"))] {
            XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [catalogEntry()], metadata: [meta]))
        }
        let boundary = request(at: kickoff.addingTimeInterval(900))
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: boundary, catalog: [catalogEntry()], metadata: [metadata()]).id, fixtureID)
        XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(at: kickoff.addingTimeInterval(901)),
            catalog: [catalogEntry()], metadata: [metadata()]))
        let rows = [catalogEntry(), catalogEntry(id: secondID)]
        // Two ids for the identical game are two listings: the first is used.
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: rows,
            metadata: [metadata(), metadata(id: secondID)]).id, fixtureID)
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: rows,
            metadata: [metadata(), metadata(id: secondID, description: description(time: "21:00"))]).id, fixtureID)
    }

    func testReviewedHLSKeepsExactPublicHeadersGuardedRelayAndOpaqueLabels() throws {
        let values = try sessions([streamJSON()])
        let session = try XCTUnwrap(values.first)
        XCTAssertEqual(session.providerName, "LS1"); XCTAssertEqual(session.streamType, .hls)
        XCTAssertEqual(session.requiredHeaders, CNCSportsAddonClient.reviewedHeaders)
        XCTAssertEqual(session.legacySource.headers, session.requiredHeaders)
        XCTAssertTrue(session.requiresLocalProxy); XCTAssertTrue(session.legacySource.requiresLocalProxy)
        XCTAssertNil(session.nativeOriginProfile); XCTAssertNil(session.nativePlaylistProfile)
        XCTAssertFalse(session.canRefresh)
        XCTAssertEqual(session.diagnosticMetadata["source_family"], "cncsports")
        XCTAssertEqual(session.diagnosticMetadata["source_key"]?.count, 27)
        XCTAssertTrue(session.diagnosticMetadata["source_key"]?.hasPrefix("ls_") == true)
        XCTAssertFalse(session.diagnosticMetadata.description.contains("https://"))
        XCTAssertFalse(session.diagnosticMetadata.description.contains("edgestream"))
    }

    func testDeliveryAdmissionRefusesUnsafeLinksOnly() throws {
        for value in ["http://edgestream7.pro/hls/fixture.m3u8", "https://edgestream7.pro:8443/hls/fixture.m3u8",
            "https://edgestream7.pro./hls/fixture.m3u8", "https://127.0.0.1/hls/fixture.m3u8",
            "https://user@edgestream7.pro/hls/fixture.m3u8", "https://user:secret@edgestream7.pro/hls/fixture.m3u8",
            "https://edgestream7.pro/hls/fixture.m3u8#player"] {
            XCTAssertTrue(try sessions([streamJSON(url: value)]).isEmpty, value)
        }
        for value in ["https://edgestream7.pro/hls/fixture.mp4", "https://cdn.edgestream7.pro/hls/fixture.m3u8", "https://edgestream4.pro/hls/fixture.m3u8",
            "https://edgestream7.pro/hls/fixture.m3u8?token=signed", "https://edgestream7.pro/other/fixture.m3u8"] {
            XCTAssertEqual(try sessions([streamJSON(url: value)]).count, 1, value)
        }
        XCTAssertEqual(try sessions([streamJSON(url: "https://edgestream7.pro:443/hls/fixture.m3u8")]).count, 1)
    }

    func testRequiredHeaderDonationProviderAndMalformedSiblingContractsFailClosed() throws {
        let rejected: [[String: Any]] = [
            streamJSON(name: "Other LivXowProvider"), streamJSON(name: "🎬LivXowProviderLookalike"),
            streamJSON(name: "🎬LivXowProvider\nAuto"), streamJSON(name: "🎬LivXowProvider \u{200D} Auto"),
            streamJSON(name: "🎬LivXowProvider \u{202E} Auto"),
            streamJSON(headers: [:]), streamJSON(headers: ["User-Agent": "unknown"]),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["Cookie": "private"]) { _, new in new }),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["Origin": "https://other.example"]) { _, new in new }),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["Referer": "https://streame.center/other"]) { _, new in new }),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["User-Agent": "Chrome/112"]) { _, new in new }),
            streamJSON().merging(["externalUrl": "https://example.com"]) { _, new in new },
            streamJSON().merging(["infoHash": "unreviewed"]) { _, new in new },
            streamJSON().merging(["drm": ["license": "unreviewed"]]) { _, new in new },
            streamJSON().merging(["behaviorHints": NSNull()]) { _, new in new },
            streamJSON().merging(["behaviorHints": ["proxyHeaders": ["request": NSNull()]]]) { _, new in new },
            streamJSON().merging(["behaviorHints": ["proxyHeaders": ["request": CNCSportsAddonClient.reviewedHeaders,
                "response": ["Access-Control-Allow-Origin": "*"]]]]) { _, new in new }
        ]
        let refused = [7, 13] // Credentials and declared DRM; null optional hints impose no requirement.
        for index in refused { XCTAssertTrue(try sessions([rejected[index]]).isEmpty) }
        let admitted = rejected.indices.filter { !refused.contains($0) }.map { rejected[$0] }
        for row in admitted { XCTAssertEqual(try sessions([row]).count, 1) }
        let donation: [String: Any] = ["name": "support the project", "externalUrl": "https://example.com"]
        XCTAssertEqual(try sessions([donation, streamJSON()]).map(\.providerName), ["LS1"], "A row with no link is skipped")
    }

    func testHeaderVariantsRemainDistinctAndMalformedMapsCannotEraseCredentials() throws {
        let url = "https://example.org/video/live.m3u8"
        let rows: [[String: Any]] = [
            ["url": url, "headers": ["User-Agent": "Player A"]],
            ["url": url, "behaviorHints": ["proxyHeaders": ["request": ["user-agent": "Player A"]]]],
            ["url": url, "headers": ["User-Agent": "Player B"]],
            ["url": url, "headers": ["User-Agent": "Player A"],
             "behaviorHints": ["proxyHeaders": ["request": ["user-agent": "different"]]]],
            ["url": url, "behaviorHints": ["proxyHeaders": ["request": ["Cookie": "private", "Other": 3]]]],
            ["url": url, "headers": ["Authorization": 12]]
        ]
        let result = try sessions(rows)
        XCTAssertEqual(result.map(\.requiredHeaders), [["User-Agent": "Player A"], ["User-Agent": "Player B"]])
        XCTAssertEqual(Set(result.compactMap { $0.diagnosticMetadata["source_key"] }).count, 2)
    }

    func testOfferedCountIncludesRowsBeyondTheAdmissionScan() async throws {
        let suite = "CNCSports.scan." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FottyQualityStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let rows = Array<Any>(repeating: NSNull(), count: 100) + [streamJSON()]
        let session = try fixtureSession(streams: .json(["streams": rows]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        do {
            _ = try await CNCSportsAddonClient(session: session, qualityStore: store).resolve(for: request())
            XCTFail("The 101st row is outside the admission scan")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 101))
        }
        let receipts = store.records().filter { $0.name == "stream_admission" }
        XCTAssertEqual(receipts.count, 1)
        let detail = try XCTUnwrap(receipts.first).details
        XCTAssertEqual(detail["offered_count"], "101")
        XCTAssertEqual(detail["admitted_count"], "0")
        XCTAssertEqual(detail["admission_malformed_count"], "100")
        XCTAssertEqual(detail["admission_limit_count"], "1")
        XCTAssertEqual(detail["admission_completion"], "limited")
        XCTAssertEqual(detail["admission_reconciled"], "yes")
    }

    func testSixDeliveryCapDeduplicationAndHeaderSortedOpaqueKeyAreStable() throws {
        let rows = (0..<8).map { streamJSON(url: "https://edgestream7.pro/hls/fixture_\($0).m3u8") }
        let sessions = try sessions([rows[0]] + rows)
        XCTAssertEqual(sessions.count, 8); XCTAssertEqual(sessions.map(\.providerName), (1...8).map { "LS\($0)" })
        let url = try XCTUnwrap(URL(string: delivery))
        let headers = CNCSportsAddonClient.reviewedHeaders
        let reversed = Dictionary(uniqueKeysWithValues: headers.sorted { $0.key > $1.key })
        XCTAssertEqual(CNCSportsAddonClient.sourceKey(url: url, headers: headers), CNCSportsAddonClient.sourceKey(url: url, headers: reversed))
        XCTAssertNotEqual(CNCSportsAddonClient.sourceKey(url: url, headers: headers), CNCSportsAddonClient.sourceKey(url: url, headers: [:]))
    }

    func testMetadataOriginAndConfigurationRemainBoundedWithoutCookiesOrCredentials() {
        XCTAssertTrue(CNCSportsAddonClient.isSafeMetadataURL(CNCSportsAddonClient.manifestURL))
        for value in ["http://cncverse.dpdns.org/manifest.json", "https://cncverse.dpdns.org:8443/manifest.json",
            "https://cncverse.dpdns.org.evil.example/manifest.json", "https://user@cncverse.dpdns.org/manifest.json",
            "https://cncverse.dpdns.org/manifest.json?key=private", "https://cncverse.dpdns.org/manifest.json#other"] {
            XCTAssertFalse(CNCSportsAddonClient.isSafeMetadataURL(URL(string: value)!))
        }
        let config = CNCSportsAddonClient.makeConfiguration()
        XCTAssertEqual(config.timeoutIntervalForRequest, 7); XCTAssertEqual(config.timeoutIntervalForResource, 12)
        XCTAssertFalse(config.waitsForConnectivity); XCTAssertNil(config.httpCookieStorage); XCTAssertNil(config.urlCredentialStorage)
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "football"))
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "cricket"))
        XCTAssertFalse(CNCSportsAddonClient.supports(category: "basketball"))
        XCTAssertFalse(CNCSportsAddonClient.supports(category: "nba"))
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "hockey"))
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "nhl"))
    }

    func testBatchSharesOneCatalogAndLeavesDateVerificationToWatch() async throws {
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(),
            catalogJSON(id: secondID, name: "🔴 Capitals vs Flyers")]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let requests = [request(), capitalsFlyersRequest(), request(category: "football")]
        let rows = try await client.catalogMatches(for: requests, now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.needsVerification, .needsVerification, .unsupported])
        XCTAssertEqual(rows.prefix(2).map(\.providerEventID), [fixtureID, secondID])
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
        _ = try await client.catalogMatches(for: requests, now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath], "Exact-meta and streams remain Watch-only")
    }

    func testBatchRetainsCatalogSiblingConflictWithoutFetchingMetadata() async throws {
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(), catalogJSON(name: "🔴 Other vs Another")]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let rows = try await CNCSportsAddonClient(session: session).catalogMatches(for: [request()], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.notListed], "An id whose own rows disagree is not offered")
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
    }

    func testCancelledCatalogBatchCannotPublishOrStartMetadata() async throws {
        let gate = CNCFixtureGate("batch catalog")
        let session = try fixtureSession(catalog: .controlled(gate))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session), requests = [request()]
        let operation = Task { try await client.catalogMatches(for: requests, now: self.kickoff) }
        defer { operation.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        operation.cancel(); gate.respond(try .json(["metas": [catalogJSON()]]))
        do { _ = try await operation.value; XCTFail("Cancelled batch cannot publish") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
    }

    @MainActor
    func testBatchKeepsNHLOnlyScopeAndRequestBoundWithoutReads() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let base = request()
        let event = EventReference(id: base.matchID, title: base.displayTitle, category: "hockey",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false, teams: nil, competitionID: "ahl")
        let otherLeague = StreamPlaybackRequest(matchID: base.matchID, displayTitle: base.displayTitle,
            homeTeam: base.homeTeam, awayTeam: base.awayTeam, category: "hockey", kickoffDate: kickoff, preferredEvent: event)
        let client = CNCSportsAddonClient(session: session)
        let rows = try await client.catalogMatches(for: [otherLeague, request(category: "cricket")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.unsupported, .unsupported])
        do { _ = try await client.catalogMatches(for: Array(repeating: base, count: 257), now: kickoff); XCTFail("Bound") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
        XCTAssertTrue(CNCFixtureProtocol.paths.isEmpty)
    }

    func testActualClientRoutesOpaqueIDThroughMetadataBeforeStreamsAndRetainsStageTimeouts() async throws {
        let session = try fixtureSession(); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let result = try await client.resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.map(\.providerName), ["LS1"])
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath, metaPath(fixtureID), streamPath(fixtureID)])
        XCTAssertEqual(CNCFixtureProtocol.timeouts, [7, 7, 7, 11])
        XCTAssertTrue(CNCFixtureProtocol.hosts.allSatisfy { $0 == "cncverse.dpdns.org" })
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == metaPath(fixtureID) }.count, 2, "Metadata is not retained in an unbounded cache")
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 1)
    }

    func testCatalogPreselectionBoundsStopBeforeAnyMetadataRequest() async throws {
        for rows in [[], [catalogJSON(name: "🔴 Other vs Another")]] {
            let session = try fixtureSession(catalog: .json(["metas": rows]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected no source") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
        }
    }

    func testInvalidOrConflictingMetadataCannotReachStreamEndpoint() async throws {
        for value in [metadataJSON(name: "Other vs Another"), metadataJSON(description: "LIVE"),
                      metadataJSON(description: description(time: "20:00")), metadataJSON(id: secondID)] {
            let session = try fixtureSession(meta: .json(["meta": value]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            let observed = ProgressiveSessions()
            do {
                _ = try await CNCSportsAddonClient(session: session).resolve(for: request(), onSession: { choice in
                    await observed.append(choice)
                    return true
                })
                XCTFail("Expected no source")
            }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
            let choices = await observed.snapshot()
            XCTAssertTrue(choices.isEmpty, "Invalid metadata cannot publish a progressive choice")
        }
    }

    func testMetadataFailureKeepsItsActualStageAndCancelsTheLane() async throws {
        let session = try fixtureSession(meta: .status(503)); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected metadata failure") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .metadata)) }
        XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testTwoExactPairMetadataRequestsRunInParallelBeforeDatedSelection() async throws {
        let first = CNCFixtureGate("first metadata"); let second = CNCFixtureGate("second metadata")
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(), catalogJSON(id: secondID)]]),
                                        meta: .controlled(first))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        CNCFixtureProtocol.setResponse(.controlled(second), for: metaPath(secondID))
        let operation = Task { try await CNCSportsAddonClient(session: session).resolve(for: self.request()) }
        defer { operation.cancel() }
        await fulfillment(of: [first.started, second.started], timeout: 3)
        first.respond(try .json(["meta": metadataJSON()]))
        second.respond(try .json(["meta": metadataJSON(id: secondID, description: description(time: "21:00"))]))
        let result = try await operation.value
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }.count, 2)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }, [streamPath(fixtureID)])
    }

    func testEmptyCatalogUsesShortTTLAndValidCatalogUsesTwoMinuteTTL() async throws {
        let session = try fixtureSession(catalog: .json(["metas": []])); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        for offset in [0.0, 14.0] {
            do { _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(offset)); XCTFail("Expected empty") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 1)
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON()]]), for: catalogPath)
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(15))
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(134))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 2)
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(135))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 3)
    }

    func testLateOlderManifestCannotOverwriteNewerPublishedSnapshot() async throws {
        let gate = CNCFixtureGate("older manifest")
        let session = try fixtureSession(manifest: .controlled(gate)); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let older = Task { try await client.resolve(for: self.request(), now: self.kickoff) }; defer { older.cancel() }
        await fulfillment(of: [gate.started], timeout: 3)
        CNCFixtureProtocol.setResponse(try .json(manifestJSON(version: "newer")), for: "/manifest.json")
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        gate.respond(try .json(manifestJSON(version: "older")))
        let original = try await older.value
        XCTAssertEqual(original.first?.diagnosticMetadata["addon_version"], "older")
        let current = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(2))
        XCTAssertEqual(current.first?.diagnosticMetadata["addon_version"], "newer")
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
    }

    func testLateOlderCatalogCannotOverwriteNewerPublishedSnapshot() async throws {
        let gate = CNCFixtureGate("older catalog")
        let session = try fixtureSession(catalog: .controlled(gate)); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let older = Task { try await client.resolve(for: self.request(), now: self.kickoff) }; defer { older.cancel() }
        await fulfillment(of: [gate.started], timeout: 3)
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON()]]), for: catalogPath)
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        gate.respond(try .json(["metas": []]))
        do { _ = try await older.value; XCTFail("Expected original caller's empty catalog") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(2))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 2)
    }

    func testCatalogRowAndTransportBodyLimitsRejectBeforeMetadata() async throws {
        let rows = Array(repeating: catalogJSON(id: "cnc:row"), count: 601)
        for response in [try CNCFixtureProtocol.Response.json(["metas": rows]),
                         .body(Data(repeating: 32, count: 512 * 1024 + 1))] {
            let session = try fixtureSession(catalog: response); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected bounded rejection") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/meta/") })
        }
    }

    @MainActor
    private func wbblRequest(at start: Date? = nil, format: CricketFixtureCatalog.Format = .t20,
                             verified: Bool = true, conflict: Bool = false,
                             status: CricketFixtureCatalog.Status = .scheduled) -> StreamPlaybackRequest {
        let start = start ?? ISO8601DateFormatter().date(from: "2026-11-05T04:40:00Z")!
        let home = "Adelaide Strikers Women", away = "Brisbane Heat Women", competition = "Women's Big Bash League"
        let metadata = CricketFixtureMetadata(fixtureID: "offline-wbbl", competitionID: "wbbl",
            competitionName: competition, format: format, status: status, observedAt: start, verified: verified)
        let event = EventReference(id: CricketFixtureCatalog.fixtureIDPrefix + metadata.fixtureID,
            title: "\(competition) · \(home) vs \(away)", category: "cricket",
            date: Int64(start.timeIntervalSince1970 * 1000), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
            hasCatalogIdentityConflict: conflict, cricketFixture: metadata)
        return StreamPlaybackRequest(event: event)
    }

    private var wbblName: String { "Adelaide Strikers Women vs Brisbane Heat Women" }
    private var wbblDescription: String {
        "📌 Cricket\n🏆 Women's Big Bash League\n🕐 Nov 05, 2026 04:40 UTC\n\n📡 Available Servers: 7"
    }
    private var wbblDelivery: String {
        "https://bl.rutube.ru/livestream/" + String(repeating: "a", count: 32)
            + "/index.m3u8?s=" + String(repeating: "A", count: 22) + "&e=4102444800&scheme=https"
    }
    private func wbblStreamJSON() -> [String: Any] {
        ["name": "🎬PlayZTVProvider 😮‍💨 Auto • CNCVerse Bridge", "title": "SKY CRICKET - AQ", "url": wbblDelivery,
         "behaviorHints": ["bingeGroup": "cncverse-playztv-live-events", "notWebReady": true,
                           "filename": "Offline WBBL", "proxyHeaders": ["request": CNCSportsAddonClient.reviewedCricketHeaders]]]
    }

    @MainActor
    func testWBBLRequiresAcceptedOfficialFormatExactDateTeamsAndCompetition() throws {
        let request = wbblRequest(), row = catalogEntry(name: "🔜 " + wbblName)
        let meta = metadata(name: wbblName, description: wbblDescription)
        XCTAssertTrue(CNCSportsAddonClient.supportsReviewedCricket(request))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(format: .test)))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(format: .odi)))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(verified: false)))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(conflict: true)))
        for status: CricketFixtureCatalog.Status in [.finished, .postponed, .cancelled] {
            XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(status: status)))
        }
        XCTAssertEqual(try CNCSportsAddonClient.selectCricketMetadata(for: request, catalog: [row], metadata: [meta],
            at: request.kickoffDate!).id, fixtureID)
        for text in [wbblDescription.replacingOccurrences(of: "Nov 05", with: "Nov 06"),
                     wbblDescription.replacingOccurrences(of: "04:40", with: "04:41"),
                     wbblDescription.replacingOccurrences(of: "Women's Big Bash League", with: "Big Bash League"),
                     wbblDescription.replacingOccurrences(of: "UTC", with: "IST"),
                     wbblDescription.replacingOccurrences(of: "Nov 05", with: "Feb 30")] {
            XCTAssertThrowsError(try CNCSportsAddonClient.selectCricketMetadata(for: request, catalog: [row],
                metadata: [metadata(name: wbblName, description: text)], at: request.kickoffDate!))
        }
        XCTAssertThrowsError(try CNCSportsAddonClient.selectCricketMetadata(for: request, catalog: [row],
            metadata: [metadata(name: "Adelaide Strikers vs Brisbane Heat", description: wbblDescription)], at: request.kickoffDate!))
        XCTAssertTrue(try CNCSportsAddonClient.cricketCatalogIDs(for: request,
            from: [row, catalogEntry(name: "🔜 Perth Scorchers Women vs Sydney Thunder Women")]).isEmpty,
            "An id whose own rows name different teams is dropped")
    }

    @MainActor
    func testStreamsAreJudgedOnSafetyNotServerPathOrTag() throws {
        let request = wbblRequest()
        func entry(_ json: [String: Any]) throws -> CNCSportsStreamEntry { try JSONDecoder().decode(CNCSportsStreamEntry.self, from: data(json)) }
        func sessions(_ rows: [[String: Any]]) throws -> [StreamSession] {
            CNCSportsAddonClient.makeSessions(from: try rows.map(entry), request: request, addOnVersion: "2.73.31")
        }
        // Any server, path or stream name the provider serves, with or without proxy headers.
        let varied: [[String: Any]] = [wbblStreamJSON(),
            ["name": "Other provider HD", "url": "https://other-cdn.example.net/live/abc.m3u8"],
            ["url": "https://edge.example.org/hls/master.m3u8?sig=1", "behaviorHints": ["notWebReady": true]]]
        XCTAssertEqual(try sessions(varied).count, 3)
        // Safety still refuses: plain HTTP, sign-in in the link, DRM, credential headers.
        var plain = wbblStreamJSON(); plain["url"] = wbblDelivery.replacingOccurrences(of: "https://", with: "http://")
        var signedIn = wbblStreamJSON(); signedIn["url"] = wbblDelivery.replacingOccurrences(of: "bl.rutube.ru", with: "user:pass@bl.rutube.ru")
        var drm = wbblStreamJSON(); drm["clearkey"] = "not-admitted"
        var cookie = wbblStreamJSON()
        cookie["behaviorHints"] = ["proxyHeaders": ["request": ["Cookie": "private"]]]
        XCTAssertTrue(try sessions([plain, signedIn, drm, cookie]).isEmpty)
        // One unusual row never sinks the rest of the list.
        let document = try JSONDecoder().decode(CNCSportsStreamDocumentProbe.self, from: data(["streams": [
            ["weird": true], wbblStreamJSON()]]))
        XCTAssertEqual(document.streams.count, 2)
    }

    @MainActor
    func testWBBLResolutionUsesNormalAdapterAndPreservesGuardedRelayAndRenewalBinding() async throws {
        let request = wbblRequest()
        var manifest = manifestJSON(version: "2.73.31")
        manifest["catalogs"] = [["id": CNCSportsAddonClient.catalogID, "type": "tv"],
                                ["id": CNCSportsAddonClient.cricketCatalogID, "type": "tv"]]
        let session = try fixtureSession(manifest: .json(manifest),
            meta: .json(["meta": metadataJSON(name: wbblName, description: wbblDescription)]),
            streams: .json(["streams": [wbblStreamJSON(), streamJSON()]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let cricketPath = "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json"
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔜 " + wbblName)]]), for: cricketPath)
        let client = CNCSportsAddonClient(session: session)
        let catalog = try await client.catalogMatches(for: [request], now: request.kickoffDate!)
        XCTAssertEqual(catalog.first?.outcome, .needsVerification)
        let sessions = try await client.resolve(for: request, now: request.kickoffDate!)
        XCTAssertEqual(sessions.map(\.providerName), ["LS1", "LS2"], "Every safe stream the listing serves")
        let result = try XCTUnwrap(sessions.first)
        XCTAssertEqual(result.requiredHeaders, CNCSportsAddonClient.reviewedCricketHeaders)
        XCTAssertEqual(result.requiresGuardedRelay, true)
        XCTAssertTrue(result.eventBinding?.matches(request: request, providerCode: "cncsports", at: request.kickoffDate!) == true)
        XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(result))
        XCTAssertFalse(CNCSportsAddonClient.isReviewedNativeSession(result), "Do not inherit NHL-specific timing before measurement")
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", cricketPath, metaPath(fixtureID), streamPath(fixtureID)])
    }

    @MainActor
    func testNormalWatchOnlyAddsCNCCricketForItsReviewedFixtureAndExistingOptIn() throws {
        let definition = try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "cncsports"))
        let good = wbblRequest()
        XCTAssertTrue(definition.supportsOptionalFixture(event: good.preferredEvent!))
        XCTAssertEqual(CuratedStreamSourceCatalog.discoveryPlan(for: good,
            enabledProviderCodes: ["cncsports"], at: good.kickoffDate!).optionalSources.map(\.providerCode), ["cncsports"])
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: good,
            enabledProviderCodes: [], at: good.kickoffDate!).optionalSources.isEmpty)
        for other in [wbblRequest(format: .test), wbblRequest(verified: false), wbblRequest(status: .finished)] {
            XCTAssertFalse(definition.supportsOptionalFixture(event: other.preferredEvent!))
            XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: other,
                enabledProviderCodes: ["cncsports"], at: other.kickoffDate!).optionalSources.isEmpty)
        }
    }

    @MainActor
    func testCricketCatalogFailureCannotEraseExistingNHLEvidenceAndViceVersa() async throws {
        for failingCricket in [true, false] {
            var manifest = manifestJSON()
            manifest["catalogs"] = [["id": CNCSportsAddonClient.catalogID, "type": "tv"],
                                    ["id": CNCSportsAddonClient.cricketCatalogID, "type": "tv"]]
            let session = try fixtureSession(manifest: .json(manifest))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            let cricketPath = "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json"
            CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔜 " + wbblName)]]), for: cricketPath)
            CNCFixtureProtocol.setResponse(.status(503), for: failingCricket ? cricketPath : catalogPath)
            let results = try await CNCSportsAddonClient(session: session).catalogMatches(for: [request(), wbblRequest()])
            XCTAssertEqual(results[failingCricket ? 0 : 1].outcome, .needsVerification)
            if case .failed = results[failingCricket ? 1 : 0].outcome {} else { XCTFail("Failure must remain scoped to its catalog") }
        }
    }

    @MainActor
    func testWBBLConflictingMetadataCannotReachStreamsOrUseNHLCatalog() async throws {
        let request = wbblRequest()
        var manifest = manifestJSON()
        manifest["catalogs"] = [["id": CNCSportsAddonClient.catalogID, "type": "tv"],
                                ["id": CNCSportsAddonClient.cricketCatalogID, "type": "tv"]]
        let session = try fixtureSession(manifest: .json(manifest),
            meta: .json(["meta": metadataJSON(name: wbblName,
                description: wbblDescription.replacingOccurrences(of: "04:40", with: "05:40"))]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let cricketPath = "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json"
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔜 " + wbblName)]]), for: cricketPath)
        do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request, now: request.kickoffDate!); XCTFail("Expected mismatch") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertFalse(CNCFixtureProtocol.paths.contains(catalogPath))
        XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    private let footballStart = ISO8601DateFormatter().date(from: "2026-11-13T19:00:00Z")!
    private let footballTitle = "Grenada vs Saint Kitts and Nevis"

    @MainActor
    private func grenadaRequest(verified: Bool = true, status: SportsFixtureCatalog.Status = .live) -> StreamPlaybackRequest {
        let teams = ["Grenada", "St. Kitts and Nevis"]
        let fixture = SportsFixtureMetadata(fixtureID: "sports-fixture:concacaf-nations-league:401929713",
            sport: "football", competitionID: "concacaf-nations-league", competitionName: "Concacaf Nations League",
            eventKind: .match, title: teams.joined(separator: " vs "),
            participants: [.init(id: "grn", name: teams[0]), .init(id: "skn", name: teams[1])],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: footballStart, verified: verified)
        return StreamPlaybackRequest(event: EventReference(id: fixture.fixtureID, title: fixture.title, category: "football",
            date: Int64(footballStart.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0], badge: nil), away: .init(name: teams[1], badge: nil)),
            sportsFixture: fixture, competitionID: fixture.competitionID))
    }

    private func footballDescription(servers: Int = 1) -> String {
        "📌 Football\n🏆 CONCACAF Nations League\n🕐 Nov 13, 2026 19:00 UTC\n\n📡 Available Servers: \(servers)"
    }

    private func footballSearchPath(_ catalogID: String) -> String {
        "/catalog/tv/\(catalogID)/search=Grenada.json"
    }

    private func footballFixtureSession(livXow: [[String: Any]], playZTV: [[String: Any]]) throws -> URLSession {
        var manifest = manifestJSON(version: "2.106.32")
        manifest["catalogs"] = [CNCSportsAddonClient.catalogID, CNCSportsAddonClient.cricketCatalogID].map {
            ["id": $0, "type": "tv", "extra": [["name": "search", "isRequired": false]]]
        }
        let session = try fixtureSession(manifest: .json(manifest), catalog: .json(["metas": []]))
        for (catalogID, rows) in [(CNCSportsAddonClient.catalogID, livXow), (CNCSportsAddonClient.cricketCatalogID, playZTV)] {
            CNCFixtureProtocol.setResponse(try .json(["metas": []]), for: "/catalog/tv/\(catalogID).json")
            CNCFixtureProtocol.setResponse(try .json(["metas": rows]), for: footballSearchPath(catalogID))
        }
        return session
    }

    @MainActor
    func testEnabledCNCParticipatesInWatchForVerifiedFootballFixtures() throws {
        let request = grenadaRequest()
        let plan = CuratedStreamSourceCatalog.discoveryPlan(for: request, enabledProviderCodes: ["cncsports"], at: footballStart)
        XCTAssertEqual(plan.optionalSources.map(\.providerCode), ["cncsports"])
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: request,
            enabledProviderCodes: [], at: footballStart).optionalSources.isEmpty)
        for invalid in [grenadaRequest(verified: false), grenadaRequest(status: .finished)] {
            XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: invalid,
                enabledProviderCodes: ["cncsports"], at: footballStart).optionalSources.isEmpty)
        }
    }

    @MainActor
    func testOffPageGrenadaListingsDistinguishVerifiedMatchFromIncompatibleDelivery() async throws {
        let noServers = "cnc:zeroPlayZ"
        let session = try footballFixtureSession(livXow: [catalogJSON(name: "🔜 Grenada vs St. Kitts And Nevis")],
            playZTV: [catalogJSON(id: noServers, name: "🔜 " + footballTitle), catalogJSON(id: secondID, name: "🔴 " + footballTitle)])
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        for (id, name, count) in [(fixtureID, "Grenada vs St. Kitts And Nevis", 0),
                                   (noServers, footballTitle, 0), (secondID, footballTitle, 1)] {
            CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: id, name: name,
                description: footballDescription(servers: count))]), for: metaPath(id))
        }
        let unsupported: [[String: Any]] = [
            ["name": "Support the project", "externalUrl": "https://example.com/support"],
            ["name": "🎬PlayZTVProvider Auto", "url": "http://198.51.100.1/test.m3u8",
             "behaviorHints": ["bingeGroup": "cncverse-playztv-live-events", "filename": "Offline match", "notWebReady": true]]
        ]
        CNCFixtureProtocol.setResponse(try .json(["streams": unsupported]), for: streamPath(secondID))
        do {
            _ = try await CNCSportsAddonClient(session: session).resolve(for: grenadaRequest(), now: footballStart)
            XCTFail("A dated listing and an external or HTTP descriptor must not become playable")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 2))
        }
        XCTAssertTrue(CNCFixtureProtocol.paths.contains(footballSearchPath(CNCSportsAddonClient.catalogID)))
        XCTAssertTrue(CNCFixtureProtocol.paths.contains(footballSearchPath(CNCSportsAddonClient.cricketCatalogID)))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }, [streamPath(secondID)])
    }

    @MainActor
    func testMultipleFootballOffersForSameVerifiedFixtureRemainDistinctUntilDeliveryDeduplication() async throws {
        let zero = "cnc:secondHalfZero"
        let otherFixture = "cnc:otherFixture"
        let ids = [fixtureID, zero, secondID]
        for hasCompatibleDelivery in [false, true] {
            var rows = ids.map { id in catalogJSON(id: id, name: (id == zero ? "🔜 " : "🔴 ") + footballTitle) }
            rows.insert(catalogJSON(id: otherFixture, name: "🔴 Grenada vs Cuba"), at: 0)
            let session = try footballFixtureSession(livXow: [], playZTV: rows)
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            for id in ids {
                CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: id, name: footballTitle,
                    description: footballDescription(servers: id == zero ? 0 : 1))]), for: metaPath(id))
                if id == zero { continue }
                let descriptor: [String: Any]
                if hasCompatibleDelivery {
                    descriptor = wbblStreamJSON()
                } else {
                    descriptor = ["name": "🎬PlayZTVProvider Auto", "url": "http://198.51.100.1/test.m3u8",
                                  "behaviorHints": ["bingeGroup": "cncverse-playztv-live-events", "notWebReady": true]]
                }
                let support: [String: Any] = ["name": "Support the project", "externalUrl": "https://example.com/support"]
                CNCFixtureProtocol.setResponse(try .json(["streams": [support, descriptor]]), for: streamPath(id))
            }
            let client = CNCSportsAddonClient(session: session)
            if hasCompatibleDelivery {
                let result = try await client.resolve(for: grenadaRequest(), now: footballStart)
                XCTAssertEqual(result.count, 1, "Two IDs advertising the same delivery cannot become two backups")
                XCTAssertEqual(result.first?.matchID, grenadaRequest().matchID)
            } else {
                do {
                    _ = try await client.resolve(for: grenadaRequest(), now: footballStart)
                    XCTFail("These verified fixture listings had no compatible delivery")
                } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 4)) }
            }
            XCTAssertEqual(Set(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }), Set(ids.map(metaPath)))
            XCTAssertEqual(Set(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }),
                           Set([streamPath(fixtureID), streamPath(secondID)]))
            XCTAssertFalse(CNCFixtureProtocol.paths.contains(metaPath(otherFixture)))
        }
    }

    @MainActor
    func testFootballOfferBudgetIsBoundedAndRetryChecksPreviouslyUnexaminedOffers() async throws {
        let ids = (0..<6).map { "cnc:boundedOffer\($0)" }
        let session = try footballFixtureSession(livXow: [], playZTV: ids.map { catalogJSON(id: $0, name: "🔴 " + footballTitle) })
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        for id in ids {
            CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: id, name: footballTitle,
                description: footballDescription(servers: 0))]), for: metaPath(id))
        }
        let client = CNCSportsAddonClient(session: session)
        var checked = Set<String>()
        for retry in [false, true] {
            let before = CNCFixtureProtocol.paths.count
            do {
                _ = try await client.resolve(for: grenadaRequest(), now: footballStart, forceRefresh: retry)
                XCTFail("A bounded partial scan cannot claim to know all deliveries")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .lookupBudgetExhausted) }
            let current = CNCFixtureProtocol.paths.dropFirst(before)
            let metas = current.filter { $0.hasPrefix("/meta/") }
            XCTAssertEqual(Set(metas).count, 3)
            XCTAssertEqual(metas.count, 3)
            XCTAssertFalse(current.contains { $0.hasPrefix("/stream/") })
            checked.formUnion(metas)
        }
        XCTAssertEqual(checked, Set(ids.map(metaPath)), "Retry must give previously unexamined offers a turn")
    }

    @MainActor
    func testFootballDeliveryBudgetLimitsRequestsWithoutCallingUntestedOffersEmpty() async throws {
        let ids = (0..<3).map { "cnc:activeOffer\($0)" }
        let session = try footballFixtureSession(livXow: [], playZTV: ids.map { catalogJSON(id: $0, name: "🔴 " + footballTitle) })
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        for id in ids {
            CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: id, name: footballTitle,
                description: footballDescription(servers: 1))]), for: metaPath(id))
            CNCFixtureProtocol.setResponse(try .json(["streams": []]), for: streamPath(id))
        }
        do {
            _ = try await CNCSportsAddonClient(session: session).resolve(for: grenadaRequest(), now: footballStart)
            XCTFail("The third advertised offer has not been checked")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .lookupBudgetExhausted) }
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }.count, 3)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }.count, 2)
    }

    @MainActor
    func testRetryEventuallyChecksEveryPositiveFootballOfferAcrossMultipleMetadataWindows() async throws {
        let ids = (0..<9).map { "cnc:positiveOffer\($0)" }
        let session = try footballFixtureSession(livXow: [], playZTV: ids.map { catalogJSON(id: $0, name: "🔴 " + footballTitle) })
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        for id in ids {
            CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(id: id, name: footballTitle,
                description: footballDescription(servers: 1))]), for: metaPath(id))
            CNCFixtureProtocol.setResponse(try .json(["streams": []]), for: streamPath(id))
        }
        let client = CNCSportsAddonClient(session: session)
        var checked = Set<String>()
        // Three metadata windows with three eligible offers per window.
        // Each window must give its previously unexamined third offer a turn on its second visit.
        for pass in 0..<6 {
            let before = CNCFixtureProtocol.paths.count
            do {
                _ = try await client.resolve(for: grenadaRequest(), now: footballStart, forceRefresh: pass > 0)
                XCTFail("Some advertised offers were outside this pass's budget")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .lookupBudgetExhausted) }
            let current = CNCFixtureProtocol.paths.dropFirst(before)
            let metas = current.filter { $0.hasPrefix("/meta/") }
            let streams = current.filter { $0.hasPrefix("/stream/") }
            XCTAssertEqual(metas.count, 3)
            XCTAssertEqual(Set(metas).count, 3)
            XCTAssertEqual(streams.count, 2)
            XCTAssertEqual(Set(streams).count, 2)
            checked.formUnion(streams)
        }
        XCTAssertEqual(checked, Set(ids.map(streamPath)), "No offer may starve across retries")
    }

    @MainActor
    func testFootballCompetitionAliasesAndContradictoryScheduleFields() throws {
        for (published, official) in [("English Premier League (EPL)", "premier-league"),
                                      ("UEFA Champions League", "champions-league"), ("Major League Soccer", "mls"),
                                      ("International Friendly", "international-friendlies"),
                                      ("CONCACAF Nations League", "concacaf-nations-league"),
                                      ("UEFA Nations League", "uefa-nations-league")] {
            XCTAssertEqual(CNCSportsAddonClient.footballCompetitionID(published), official)
        }
        let request = grenadaRequest()
        let original = metadataJSON(name: footballTitle, description: footballDescription())
        let exact = try JSONDecoder().decode(CNCSportsMetadata.self, from: data(original))
        XCTAssertEqual(CNCSportsAddonClient.footballServerCount(for: exact, request: request), 1)
        let otherStart = "2026-11-14T19:00:00Z"
        for field in ["released", "releaseInfo", "date", "startTime", "kickoff", "videos"] {
            var changed = original
            if field == "videos" {
                changed[field] = [["id": fixtureID, "released": otherStart]]
            } else {
                changed[field] = otherStart
            }
            let meta = try JSONDecoder().decode(CNCSportsMetadata.self, from: data(changed))
            XCTAssertNil(CNCSportsAddonClient.footballServerCount(for: meta, request: request), field)
        }
    }

    @MainActor
    func testFootballVerifiesSportDateCompetitionAndBothTeamsBeforeRequestingStreams() async throws {
        for (name, description) in [
            ("Grenada vs Cuba", footballDescription()),
            ("Grenada U20 vs Saint Kitts and Nevis U20", footballDescription()),
            (footballTitle, footballDescription().replacingOccurrences(of: "Football", with: "Hockey")),
            (footballTitle, footballDescription().replacingOccurrences(of: "Nov 13", with: "Nov 12")),
            (footballTitle, footballDescription().replacingOccurrences(of: "19:00 UTC", with: "19:00")),
            (footballTitle, footballDescription().replacingOccurrences(of: "CONCACAF Nations League", with: "International Friendly"))
        ] {
            let session = try footballFixtureSession(livXow: [], playZTV: [catalogJSON(name: "🔴 " + footballTitle)])
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(name: name, description: description)]), for: metaPath(fixtureID))
            do {
                _ = try await CNCSportsAddonClient(session: session).resolve(for: grenadaRequest(), now: footballStart)
                XCTFail("Wrong sport, date, competition or teams reached playback")
            } catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertTrue(CNCFixtureProtocol.paths.contains(metaPath(fixtureID)))
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    @MainActor
    func testUnavailableFootballCatalogCannotHideSiblingDeliveryOrTurnIncompleteLookupIntoNoStreams() async throws {
        let request = grenadaRequest()
        for serverCount in [0, 1] {
            let session = try footballFixtureSession(livXow: [catalogJSON(name: "🔴 " + footballTitle)], playZTV: [])
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(name: footballTitle,
                description: footballDescription(servers: serverCount))]), for: metaPath(fixtureID))
            CNCFixtureProtocol.setResponse(.status(503), for: footballSearchPath(CNCSportsAddonClient.cricketCatalogID))
            let client = CNCSportsAddonClient(session: session)
            if serverCount == 0 {
                do {
                    _ = try await client.resolve(for: request, now: footballStart)
                    XCTFail("An unavailable sibling cannot be counted as a fully checked empty result")
                } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .catalog)) }
                XCTAssertFalse(CNCFixtureProtocol.paths.contains(streamPath(fixtureID)))
            } else {
                let sessions = try await client.resolve(for: request, now: footballStart)
                XCTAssertEqual(sessions.count, 1)
                XCTAssertEqual(sessions.first?.matchID, request.matchID)
            }
        }
    }

    @MainActor
    func testPlayZTVAloneSupportsFootballWithOrWithoutAdvertisedSearchAndCannotSupplyNHL() async throws {
        let playZTV = CNCSportsAddonClient.cricketCatalogID
        let basePath = "/catalog/tv/\(playZTV).json"
        for hasSearch in [true, false] {
            var catalog: [String: Any] = ["id": playZTV, "type": "tv"]
            if hasSearch { catalog["extra"] = [["name": "search", "isRequired": false]] }
            var manifest = manifestJSON(version: "2.106.32")
            manifest["catalogs"] = [catalog]
            let session = try fixtureSession(manifest: .json(manifest),
                meta: .json(["meta": metadataJSON(name: footballTitle, description: footballDescription())]),
                streams: .json(["streams": [wbblStreamJSON()]]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            let expected = hasSearch ? footballSearchPath(playZTV) : basePath
            CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔴 " + footballTitle)]]), for: expected)
            let client = CNCSportsAddonClient(session: session)
            let result = try await client.resolve(for: grenadaRequest(), now: footballStart)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", expected, metaPath(fixtureID), streamPath(fixtureID)])
            do {
                _ = try await client.resolve(for: request(), now: kickoff)
                XCTFail("An advertised PlayZTV football catalog cannot supply the LivXow NHL lane")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidManifest) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains(catalogPath))
        }
    }

    @MainActor
    func testFootballBindsCompatibleLivXowSessionToExactOfficialMatch() async throws {
        let session = try footballFixtureSession(livXow: [catalogJSON(name: "🔴 " + footballTitle)], playZTV: [])
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        CNCFixtureProtocol.setResponse(try .json(["meta": metadataJSON(name: footballTitle, description: footballDescription())]),
                                      for: metaPath(fixtureID))
        let request = grenadaRequest()
        let results = try await CNCSportsAddonClient(session: session).resolve(for: request, now: footballStart)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.matchID, request.matchID)
        let reference = CNCSportsAddonClient.footballReference(fixtureID)
        XCTAssertEqual(result.eventBinding?.providerEventID, reference)
        XCTAssertEqual(result.eventBinding?.streamID, reference)
        XCTAssertTrue(result.eventBinding?.matches(request: request, providerCode: "cncsports", at: footballStart) == true)

        let fixture = try XCTUnwrap(request.preferredEvent?.sportsFixture)
        let expiry = footballStart.addingTimeInterval(300)
        let teams = fixture.participants.map(\.name)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "d", count: 64),
            providerCode: "cncsports", providerEventID: reference, streamID: reference, resourceType: "tv",
            scope: "football", kind: .event, sport: "football", title: fixture.title, participants: teams, start: footballStart,
            competitionID: fixture.competitionID, squad: fixture.squad, observedAt: footballStart, expiresAt: expiry,
            verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: fixture.fixtureID, broadcastID: record.id,
            providerCode: "cncsports", state: .listed, matchMethod: .exact,
            fixtureFingerprint: .init(fixtureID: fixture.fixtureID, sport: "football", start: footballStart,
                participants: teams, competitionID: fixture.competitionID, squad: fixture.squad), expiresAt: expiry)
        let association = BroadcastRegistryMatch(broadcast: record, link: link,
            provider: .init(providerCode: "cncsports", scope: "football", status: .available, observedAt: footballStart, expiresAt: expiry))
        let pinned = request.usingRegistryMatch(association)
        let fresh = try await CNCSportsAddonClient(session: session).resolve(for: pinned, now: footballStart, forceRefresh: true)
        XCTAssertEqual(fresh.first?.eventBinding?.usesRegistryAssociation, true)
        XCTAssertEqual(fresh.first?.eventBinding?.providerEventID, reference)
        XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(try XCTUnwrap(fresh.first)))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == metaPath(fixtureID) }.count, 2)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == streamPath(fixtureID) }.count, 2)
    }

    private var catalogPath: String { "/catalog/tv/" + CNCSportsAddonClient.catalogID + ".json" }
    private func metaPath(_ id: String) -> String { "/meta/tv/" + id + ".json" }
    private func streamPath(_ id: String) -> String { "/stream/tv/" + id + ".json" }
    private func request(category: String = "hockey", at: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: "existing-nhl-fixture", displayTitle: "Chicago Blackhawks vs Montreal Canadiens",
              homeTeam: "Chicago Blackhawks", awayTeam: "Montreal Canadiens", category: category, kickoffDate: at ?? kickoff)
    }
    private func capitalsFlyersRequest() -> StreamPlaybackRequest {
        .init(matchID: "sports-fixture:nhl:2026020199", displayTitle: "Washington Capitals vs Philadelphia Flyers",
              homeTeam: "Washington Capitals", awayTeam: "Philadelphia Flyers", category: "hockey",
              kickoffDate: ISO8601DateFormatter().date(from: "2026-10-28T23:30:00Z")!)
    }
    private var capitalsFlyersDescription: String {
        "📌 Hockey\n🏆 NHL\n🕐 Oct 28, 2026 23:30 UTC\n\n📡 Available Servers: 1"
    }
    private func description(time: String = "00:00") -> String { "📌 Hockey\n🏆 NHL\n🕐 Oct 24, 2026 \(time) UTC\n\n📡 Available Servers: 1" }
    private func catalogEntry(id: String? = nil, type: String = "tv", name: String = "🔴 Blackhawks vs Canadiens") -> CNCSportsCatalogEntry {
        .init(id: id ?? fixtureID, type: type, name: name)
    }
    private func metadata(id: String? = nil, type: String = "tv", name: String = "Blackhawks vs Canadiens",
                          description: String?) -> CNCSportsMetadata {
        .init(id: id ?? fixtureID, type: type, name: name, description: description)
    }
    private func metadata(id: String? = nil, type: String = "tv", name: String = "Blackhawks vs Canadiens") -> CNCSportsMetadata {
        metadata(id: id, type: type, name: name, description: description())
    }
    private func catalogJSON(id: String? = nil, name: String = "🔴 Blackhawks vs Canadiens") -> [String: Any] {
        let id = id ?? fixtureID
        return ["id": id, "type": "tv", "name": name, "behaviorHints": ["defaultVideoId": id]]
    }
    private func metadataJSON(id: String? = nil, name: String = "Blackhawks vs Canadiens", description: String? = nil) -> [String: Any] {
        ["id": id ?? fixtureID, "type": "tv", "name": name, "description": description ?? self.description()]
    }
    private func manifestJSON(version: String = "1.0.30") -> [String: Any] {
        ["id": "com.cncverse.stremiobridge", "version": version, "resources": ["catalog", "meta", "stream", "subtitles"],
         "types": ["movie", "series", "other", "tv"], "catalogs": [["id": CNCSportsAddonClient.catalogID, "type": "tv"]],
         "behaviorHints": ["configurable": false]]
    }
    private func streamJSON(url: String? = nil, name: String = "🎬LivXowProvider 😮‍💨 Auto • CNCVerse Bridge",
                            headers: [String: String] = CNCSportsAddonClient.reviewedHeaders) -> [String: Any] {
        ["url": url ?? delivery, "name": name, "title": "Offline fixture • HLS",
         "behaviorHints": ["proxyHeaders": ["request": headers]]]
    }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func sessions(_ rows: [[String: Any]]) throws -> [StreamSession] {
        let streams = rows.compactMap { try? JSONDecoder().decode(CNCSportsStreamEntry.self, from: data($0)) }
        return CNCSportsAddonClient.makeSessions(from: streams, request: request(), addOnVersion: "1.0.30")
    }
    private func fixtureSession(manifest: CNCFixtureProtocol.Response? = nil, catalog: CNCFixtureProtocol.Response? = nil,
                                meta: CNCFixtureProtocol.Response? = nil, streams: CNCFixtureProtocol.Response? = nil) throws -> URLSession {
        CNCFixtureProtocol.configure([
            "/manifest.json": try manifest ?? .json(manifestJSON()), catalogPath: try catalog ?? .json(["metas": [catalogJSON()]]),
            metaPath(fixtureID): try meta ?? .json(["meta": metadataJSON()]),
            streamPath(fixtureID): try streams ?? .json(["streams": [["name": "donation", "externalUrl": "https://example.com"], streamJSON()]])
        ])
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CNCFixtureProtocol.self]
        configuration.waitsForConnectivity = false; return URLSession(configuration: configuration)
    }
}

/// Every adapter request ends in this offline fixture transport, never a site.
private final class CNCFixtureProtocol: URLProtocol {
    enum Response {
        case body(Data), failure(Error), status(Int), controlled(CNCFixtureGate)
        static func json(_ value: [String: Any]) throws -> Response { .body(try JSONSerialization.data(withJSONObject: value)) }
    }
    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var recordedPaths: [String] = []
    private static var recordedTimeouts: [TimeInterval] = []
    private static var recordedHosts: [String] = []
    static var paths: [String] { lock.lock(); defer { lock.unlock() }; return recordedPaths }
    static var timeouts: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recordedTimeouts }
    static var hosts: [String] { lock.lock(); defer { lock.unlock() }; return recordedHosts }
    static func configure(_ value: [String: Response]) {
        lock.lock(); responses = value; recordedPaths = []; recordedTimeouts = []; recordedHosts = []; lock.unlock()
    }
    static func reset() { configure([:]) }
    static func setResponse(_ value: Response, for path: String) { lock.lock(); responses[path] = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let path = request.url?.path ?? ""
        Self.recordedPaths.append(path); Self.recordedTimeouts.append(request.timeoutInterval)
        Self.recordedHosts.append(request.url?.host ?? "")
        let result = Self.responses[path] ?? .failure(URLError(.fileDoesNotExist)); Self.lock.unlock(); complete(result)
    }
    private func complete(_ result: Response) {
        switch result {
        case .body(let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        case .status(let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocolDidFinishLoading(self)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .controlled(let gate): gate.start { [weak self] result in self?.complete(result) }
        }
    }
    override func stopLoading() {}
}

private final class CNCFixtureGate {
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((CNCFixtureProtocol.Response) -> Void)?
    private var pending: CNCFixtureProtocol.Response?
    init(_ name: String) { started = XCTestExpectation(description: name) }
    func start(_ completion: @escaping (CNCFixtureProtocol.Response) -> Void) {
        lock.lock(); let pending = self.pending; self.pending = nil
        if pending == nil { self.completion = completion }; lock.unlock(); started.fulfill()
        if let pending { completion(pending) }
    }
    func respond(_ result: CNCFixtureProtocol.Response) {
        lock.lock(); let completion = self.completion; self.completion = nil
        if completion == nil { pending = result }; lock.unlock(); completion?(result)
    }
}

/// The registry is a hint, not a gate: when every registered association
/// misses, the same provider's exact direct lookup still gets a chance.
@MainActor
final class RegistryHintDirectFallbackTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-11-07T12:30:00Z")!

    private actor CallCounter {
        private(set) var count = 0
        func hit() { count += 1 }
    }

    private struct ResolveFailure: Error {}

    private func association(_ marker: String = "d") -> (StreamPlaybackRequest, BroadcastRegistryMatch) {
        let teams = ["Leeds United", "Tottenham Hotspur"]
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:560632", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: teams.joined(separator: " vs "),
            participants: [.init(id: "lee", name: teams[0]), .init(id: "tot", name: teams[1])],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: start, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0], badge: nil), away: .init(name: teams[1], badge: nil)), sportsFixture: metadata, competitionID: "premier-league")
        let request = StreamPlaybackRequest(event: event), expiry = start.addingTimeInterval(3600)
        let eventID = "cs-event-" + marker
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: marker, count: 64),
            providerCode: "communitysports", providerEventID: eventID, streamID: eventID, resourceType: "tv",
            scope: "football", kind: .event, sport: "football", title: metadata.title, participants: teams, start: start,
            competitionID: "premier-league", squad: metadata.squad, observedAt: start, expiresAt: expiry,
            verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id,
            providerCode: "communitysports", state: .listed, matchMethod: .exact,
            fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: start, participants: teams,
                competitionID: "premier-league", squad: metadata.squad), expiresAt: expiry)
        let match = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: "communitysports",
            scope: "football", status: .available, observedAt: start, expiresAt: expiry))
        return (request, match)
    }

    nonisolated private static func session(_ path: String) -> StreamSession {
        StreamSession(matchID: "sports-fixture:premier-league:560632",
            playableURL: URL(string: "https://direct.example/" + path + ".m3u8")!, streamType: .hls, providerName: "CS")
    }

    func testRegisteredRetryReachesThirdCurrentListingWithTwoLookupsPerAttempt() async throws {
        let (request, first) = association("a"), second = association("b").1, third = association("c").1
        let instant = start, resolver = LiveStreamResolver(), calls = CallCounter()
        let lookup: @Sendable (StreamPlaybackRequest) async throws -> [StreamSession] = { scoped in
            await calls.hit()
            guard scoped.registryMatch == third else { throw CommunitySportsAddonError.streamEntriesEmpty }
            let binding = try XCTUnwrap(StreamEventBinding(request: scoped, providerCode: "communitysports",
                providerEventID: third.broadcast.providerEventID, streamID: third.broadcast.streamID,
                manifestRevision: "1", verifiedAt: instant, expiresAt: instant.addingTimeInterval(90), at: instant))
            let choice = StreamSession(matchID: scoped.matchID, playableURL: URL(string: "https://third.example/live.m3u8")!,
                streamType: .hls, providerName: "CS1", createdAt: instant, eventBinding: binding)
            XCTAssertNotNil(choice.eventBinding, "The descriptor must be created within its binding's lease")
            return [choice]
        }
        do {
            _ = try await resolver.resolveRegisteredOptionalSessions(for: request, providerCode: "communitysports",
                associations: [first, second, third], resolve: lookup, clock: { instant },
                fallback: { throw CommunitySportsAddonError.streamEntriesEmpty })
            XCTFail("The first two checked rows had no streams")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .lookupBudgetExhausted)
        }
        let initialCalls = await calls.count
        XCTAssertEqual(initialCalls, 2)
        let retry = try await resolver.resolveRegisteredOptionalSessions(for: request, providerCode: "communitysports",
            associations: [second, first, third], resolve: lookup, clock: { instant })
        XCTAssertEqual(retry.map { $0.eventBinding?.providerEventID }, [third.broadcast.providerEventID])
        let retryCalls = await calls.count
        XCTAssertEqual(retryCalls, 4)
    }

    func testRegisteredFailureFallsBackToDirectExactLookup() async throws {
        let (request, match) = association(), calls = CallCounter(), direct = Self.session("direct")
        let clock = start
        let choices = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
            providerCode: "communitysports", associations: [match],
            resolve: { _ in throw ResolveFailure() }, clock: { clock },
            fallback: { await calls.hit(); return [direct] })
        XCTAssertEqual(choices.map(\.playableURL), [direct.playableURL])
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testUnadmittedRegisteredResultsFallBackToDirectLookup() async throws {
        // A stale association whose descriptor no longer binds to the registry
        // entry is filtered out; the direct lane must still run.
        let (request, match) = association(), direct = Self.session("direct")
        let clock = start
        let choices = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
            providerCode: "communitysports", associations: [match],
            resolve: { _ in [Self.session("unbound")] }, clock: { clock },
            fallback: { [direct] })
        XCTAssertEqual(choices.map(\.playableURL), [direct.playableURL])
    }

    func testWithoutFallbackRegisteredMissStillThrows() async {
        let (request, match) = association()
        let clock = start
        do {
            _ = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
                providerCode: "communitysports", associations: [match],
                resolve: { _ in throw ResolveFailure() }, clock: { clock })
            XCTFail("Expected the registered miss to throw without a fallback")
        } catch { XCTAssertTrue(error is ResolveFailure) }
    }

    func testEmptyFallbackPreservesOriginalFailure() async {
        let (request, match) = association()
        let clock = start
        do {
            _ = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
                providerCode: "communitysports", associations: [match],
                resolve: { _ in throw ResolveFailure() }, clock: { clock }, fallback: { [] })
            XCTFail("Expected an empty direct lookup to keep the original failure")
        } catch { XCTAssertTrue(error is ResolveFailure) }
    }

    func testDirectCatalogMissRetainsRegisteredDescriptorWithdrawal() async {
        let (request, match) = association()
        let clock = start
        for descriptorFailure in [CommunitySportsAddonError.streamEntriesEmpty, .streamAdmissionRejected(entryCount: 2)] {
            do {
                _ = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
                    providerCode: "communitysports", associations: [match],
                    resolve: { _ in throw descriptorFailure }, clock: { clock },
                    fallback: { throw CommunitySportsAddonError.matchNotFound })
                XCTFail("An empty or incompatible descriptor cannot produce a stream")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, descriptorFailure) }
        }
    }

    func testFallbackDeliveriesAreDeduplicated() async throws {
        let (request, match) = association(), direct = Self.session("direct")
        let clock = start
        let choices = try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
            providerCode: "communitysports", associations: [match],
            resolve: { _ in throw ResolveFailure() }, clock: { clock },
            fallback: { [direct, Self.session("direct"), Self.session("second")] })
        XCTAssertEqual(choices.count, 2)
    }

    func testCancellationNeverStartsDirectFallback() async {
        let (request, match) = association(), calls = CallCounter()
        let clock = start
        let task = Task {
            try await LiveStreamResolver.shared.resolveRegisteredOptionalSessions(for: request,
                providerCode: "communitysports", associations: [match],
                resolve: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw ResolveFailure()
                }, clock: { clock },
                fallback: { await calls.hit(); return [] })
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }
}


/// Decodes a stream list the way the adapter does, for tests.
private struct CNCSportsStreamDocumentProbe: Decodable { let streams: [CNCSportsStreamEntry] }
