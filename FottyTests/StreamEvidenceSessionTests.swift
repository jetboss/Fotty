import XCTest
@testable import Fotty

@MainActor
final class StreamEvidenceSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_548_400)
    private let configuration = UUID()

    func testProvenanceIsEphemeralAndSavedJSONCannotInjectIt() throws {
        let original = try session().recordingDeliveryTransport(cookies: [], at: now)
        let provenance = try receipt(for: original)
        let recorded = original.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now)
        XCTAssertNil(original.deliveryProvenance)
        XCTAssertEqual(recorded.deliveryProvenance, provenance)
        XCTAssertEqual(recorded.id, original.id)

        let data = try JSONEncoder().encode(recorded)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["deliveryProvenance"])
        XCTAssertNil(json["deliveryTransportContext"])
        XCTAssertNil(try JSONDecoder().decode(StreamSession.self, from: data).deliveryProvenance)
        XCTAssertNil(try JSONDecoder().decode(StreamSession.self, from: data).deliveryTransportContext)
        json["deliveryProvenance"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(provenance))
        json["deliveryTransportContext"] = ["contract": "injected"]
        let injected = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(StreamSession.self, from: injected).deliveryProvenance,
            "A saved association cannot restore lookup authority")
        XCTAssertNil(try JSONDecoder().decode(StreamSession.self, from: injected).deliveryTransportContext)
    }

    func testRecordingRequiresCurrentProviderScopeConfigurationAndFullContract() throws {
        let original = try session()
        let provenance = try receipt(for: original)
        let otherScope = try XCTUnwrap(LiveSourceHealthStore.fixtureProgrammeScope(fixtureID: "other-fixture"))
        XCTAssertNil(original.recordingDeliveryProvenance(provenance, scope: otherScope,
            configurationGeneration: configuration, at: now).deliveryProvenance)
        XCTAssertNil(original.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: UUID(), at: now).deliveryProvenance)

        let differentDeliveries = [
            try session(matchID: "other-fixture"),
            try session(provider: "AS1"),
            try session(url: "https://media.example/live.m3u8?token=replaced"),
            try session(headers: ["User-Agent": "Changed"]),
            try session(streamType: .mp4),
            try session(endpoint: .webPage)
        ]
        for changed in differentDeliveries {
            XCTAssertNil(changed.recordingDeliveryProvenance(provenance, scope: provenance.scope,
                configurationGeneration: configuration, at: now).deliveryProvenance)
        }
        let recorded = original.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now)
        XCTAssertNil(recorded.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: UUID(), at: now).deliveryProvenance,
            "Failed attachment must clear the previous configuration's association")
        XCTAssertNil(recorded.recordingDeliveryProvenance(nil, scope: provenance.scope,
            configurationGeneration: configuration, at: now).deliveryProvenance)
    }

    func testRecordingRejectsFutureNonFiniteAndExpiredObservationTimes() throws {
        let source = try session()
        let provenance = try receipt(for: source)
        XCTAssertNil(source.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now.addingTimeInterval(-1)).deliveryProvenance)
        XCTAssertNil(source.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: Date(timeIntervalSince1970: .infinity)).deliveryProvenance)
        XCTAssertNil(source.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration,
            at: now.addingTimeInterval(ProgrammeEvidenceLedger.maximumRetention)).deliveryProvenance)
        XCTAssertNotNil(source.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration,
            at: now.addingTimeInterval(ProgrammeEvidenceLedger.maximumRetention - 1)).deliveryProvenance)
    }

    func testChannelProvenanceRequiresTheCallersCurrentProgrammeScope() throws {
        let source = try session(matchID: "channel-1", provider: "TV1")
        let current = try XCTUnwrap(LiveSourceHealthStore.channelProgrammeScope(
            channelID: "channel-1", programmeID: "programme-1"))
        let next = try XCTUnwrap(LiveSourceHealthStore.channelProgrammeScope(
            channelID: "channel-1", programmeID: "programme-2"))
        let provenance = try XCTUnwrap(LiveSourceHealthStore.deliveryProvenance(for: source, scope: current,
            listingID: "channel-listing", lookupID: UUID(), configurationGeneration: configuration, at: now))
        XCTAssertEqual(source.recordingDeliveryProvenance(provenance, scope: current,
            configurationGeneration: configuration, at: now).deliveryProvenance, provenance)
        XCTAssertNil(source.recordingDeliveryProvenance(provenance, scope: next,
            configurationGeneration: configuration, at: now).deliveryProvenance,
            "An unchanged rolling channel URL cannot extend evidence into the next programme")
    }

    func testObservationMayPrecedeSessionConstructionWithoutInventingExpiry() throws {
        let source = try session(at: now.addingTimeInterval(5))
        let provenance = try receipt(for: source, at: now)
        XCTAssertEqual(source.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now.addingTimeInterval(5)).deliveryProvenance, provenance)
        XCTAssertNil(source.expiryTime, "Provenance does not invent a fixture or media boundary")
    }

    func testProbeInvalidatesOnlyChangedEffectiveEndpointOrContainer() throws {
        let source = try session().recordingDeliveryTransport(cookies: [], at: now)
        let provenance = try receipt(for: source)
        let recorded = source.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now)
        let unchanged = recorded.recordingMediaProbe(.init(contentType: "application/vnd.apple.mpegurl",
            prefix: Data("#EXTM3U\n".utf8)))
        XCTAssertEqual(unchanged.deliveryProvenance, provenance)
        XCTAssertEqual(unchanged.deliveryTransportContext, recorded.deliveryTransportContext)
        XCTAssertEqual(unchanged.recordingMediaProbe(nil).deliveryProvenance, provenance)
        let changed = recorded.recordingMediaProbe(.init(contentType: "video/mp4", prefix: Data()))
        XCTAssertNil(changed.deliveryProvenance)
        XCTAssertNil(changed.deliveryTransportContext)

        let opaque = try session(url: "https://media.example/opaque", streamType: .unknown, endpoint: .webPage)
        let opaqueReceipt = try receipt(for: opaque)
        let opaqueRecorded = opaque.recordingDeliveryProvenance(opaqueReceipt, scope: opaqueReceipt.scope,
            configurationGeneration: configuration, at: now)
        let probed = opaqueRecorded.recordingMediaProbe(.init(contentType: "application/vnd.apple.mpegurl",
            prefix: Data("#EXTM3U\n".utf8)))
        XCTAssertNil(probed.deliveryProvenance, "An observed direct-media contract replaces the page contract")
        let mediaReceipt = try receipt(for: probed)
        let mediaRecorded = probed.recordingDeliveryProvenance(mediaReceipt, scope: mediaReceipt.scope,
            configurationGeneration: configuration, at: now)
        XCTAssertNil(mediaRecorded.recordingMediaProbe(nil).deliveryProvenance,
            "Removing probe evidence can also change the effective contract")
    }

    func testRenewalDoesNotCarryPreviousProvenanceEvenForUnchangedContract() throws {
        let old = try boundSession(at: now).recordingDeliveryTransport(cookies: [], at: now)
        let oldReceipt = try receipt(for: old)
        let recorded = old.recordingDeliveryProvenance(oldReceipt, scope: oldReceipt.scope,
            configurationGeneration: configuration, at: now)
        let later = now.addingTimeInterval(10)
        for url in [old.playableURL.absoluteString, "https://media.example/live.m3u8?token=renewed"] {
            let fresh = try boundSession(url: url, at: later)
            let renewed = try XCTUnwrap(recorded.renewingDelivery(from: fresh, for: request(), at: later))
            XCTAssertEqual(renewed.id, old.id)
            XCTAssertEqual(renewed.playableURL, fresh.playableURL)
            XCTAssertNil(renewed.deliveryProvenance,
                "The retained selected-row ID cannot transfer provenance from the previous lookup")
            XCTAssertNil(renewed.deliveryTransportContext, "The old preparation is not the renewed transport")
        }
    }

    func testRenewalCarriesOnlyFreshLookupProvenanceForItsExactContract() throws {
        let old = try boundSession(at: now)
        let oldReceipt = try receipt(for: old)
        let recorded = old.recordingDeliveryProvenance(oldReceipt, scope: oldReceipt.scope,
            configurationGeneration: configuration, at: now)
        let later = now.addingTimeInterval(10), newConfiguration = UUID()
        for url in [old.playableURL.absoluteString, "https://media.example/live.m3u8?token=renewed"] {
            let fresh = try boundSession(url: url, provider: "CS2", at: later)
                .recordingDeliveryTransport(cookies: [], at: later)
            let provenance = try receipt(for: fresh, configuration: newConfiguration, at: later)
            let freshRecorded = fresh.recordingDeliveryProvenance(provenance, scope: provenance.scope,
                configurationGeneration: newConfiguration, at: later)
            let renewed = try XCTUnwrap(recorded.renewingDelivery(from: freshRecorded, for: request(), at: later))
            XCTAssertEqual(renewed.id, old.id)
            XCTAssertEqual(renewed.providerName, old.providerName)
            XCTAssertEqual(renewed.deliveryProvenance, provenance)
            XCTAssertEqual(renewed.deliveryTransportContext, fresh.deliveryTransportContext)
            XCTAssertNotEqual(renewed.deliveryProvenance?.lookupID, oldReceipt.lookupID)
            XCTAssertEqual(renewed.deliveryProvenance?.configurationGeneration, newConfiguration)
        }
    }

    func testSameLookupCannotMasqueradeAsFreshRenewalObservation() throws {
        let old = try boundSession(at: now)
        let oldReceipt = try receipt(for: old)
        let recorded = old.recordingDeliveryProvenance(oldReceipt, scope: oldReceipt.scope,
            configurationGeneration: configuration, at: now)
        let later = now.addingTimeInterval(10)
        let fresh = try boundSession(at: later)
        let reused = try receipt(for: fresh, lookupID: oldReceipt.lookupID, at: later)
        let freshRecorded = fresh.recordingDeliveryProvenance(reused, scope: reused.scope,
            configurationGeneration: configuration, at: later)
        XCTAssertNotNil(freshRecorded.deliveryProvenance)
        let renewed = try XCTUnwrap(recorded.renewingDelivery(from: freshRecorded, for: request(), at: later))
        XCTAssertNil(renewed.deliveryProvenance)
        XCTAssertEqual(renewed.id, old.id, "Delivery renewal succeeds independently of provenance")
    }

    func testCapturedCookiesChangeTheFullContractAndNeverEnterSavedSession() throws {
        let original = try session()
        let firstCookie = try cookie(value: "private-cookie-one")
        let first = original.recordingDeliveryTransport(cookies: [firstCookie], at: now)
        let provenance = try receipt(for: first)
        let recorded = first.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now)
        XCTAssertNotNil(recorded.deliveryTransportContext)
        XCTAssertNotEqual(LiveSourceHealthStore.deliveryContractFingerprint(for: original), provenance.contract)
        let unchanged = recorded.recordingDeliveryTransport(cookies: [firstCookie], at: now.addingTimeInterval(1))
        XCTAssertEqual(unchanged.deliveryProvenance, provenance,
            "Recapturing the same actual request does not change its contract")

        let changed = recorded.recordingDeliveryTransport(cookies: [try cookie(value: "private-cookie-two")], at: now)
        XCTAssertNil(changed.deliveryProvenance)
        XCTAssertNotEqual(changed.deliveryTransportContext?.contract, recorded.deliveryTransportContext?.contract)
        XCTAssertNil(changed.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now).deliveryProvenance)
        let differentURL = try session(url: "https://media.example/live.m3u8?token=different")
            .recordingDeliveryTransport(cookies: [firstCookie], at: now)
        XCTAssertNotEqual(differentURL.deliveryTransportContext?.contract, recorded.deliveryTransportContext?.contract)

        let encoded = try JSONEncoder().encode(recorded)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("private-cookie-one"))
        XCTAssertFalse(text.contains("deliveryTransportContext"))
        let decoded = try JSONDecoder().decode(StreamSession.self, from: encoded)
        XCTAssertNil(decoded.deliveryTransportContext)
        XCTAssertNil(decoded.deliveryProvenance)
    }

    func testExplicitEmptyTransportKeepsMetadataAndInvalidCaptureClearsIt() throws {
        let original = try session()
        let provenance = try receipt(for: original)
        let recorded = original.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: now)
        XCTAssertNil(recorded.deliveryTransportContext, "Discovery can record metadata before preparation")
        let empty = recorded.recordingDeliveryTransport(cookies: [], at: now)
        XCTAssertEqual(empty.deliveryProvenance, provenance)
        XCTAssertTrue(LiveSourceHealthStore.deliveryTransportIsCurrent(for: empty, at: now))
        let outside = empty.recordingDeliveryTransport(cookies: [try cookie(value: "unrelated", domain: "other.example")], at: now)
        XCTAssertEqual(outside.deliveryTransportContext?.contract, empty.deliveryTransportContext?.contract)
        XCTAssertEqual(outside.deliveryProvenance, provenance)
        let invalid = empty.recordingDeliveryTransport(cookies: [], at: Date(timeIntervalSince1970: .infinity))
        XCTAssertNil(invalid.deliveryTransportContext)
        XCTAssertNil(invalid.deliveryProvenance)
    }

    func testRenewalRejectsExpiredCapturedCookieContextWithoutRejectingDelivery() throws {
        let old = try boundSession(at: now)
        let capturedAt = now.addingTimeInterval(1), later = now.addingTimeInterval(10)
        let fresh = try boundSession(at: capturedAt).recordingDeliveryTransport(
            cookies: [try cookie(value: "short-cookie", expiresAt: now.addingTimeInterval(5))], at: capturedAt)
        let provenance = try receipt(for: fresh, at: capturedAt)
        let recorded = fresh.recordingDeliveryProvenance(provenance, scope: provenance.scope,
            configurationGeneration: configuration, at: capturedAt)
        XCTAssertNotNil(recorded.deliveryProvenance)
        XCTAssertNotNil(recorded.deliveryTransportContext)
        let renewed = try XCTUnwrap(old.renewingDelivery(from: recorded, for: request(), at: later))
        XCTAssertNil(renewed.deliveryTransportContext)
        XCTAssertNil(renewed.deliveryProvenance)
        XCTAssertEqual(renewed.playableURL, fresh.playableURL)
    }

    private func cookie(value: String, domain: String = "media.example", expiresAt: Date? = nil) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [.domain: domain, .path: "/", .name: "session", .value: value,
            .secure: "TRUE", .expires: expiresAt ?? now.addingTimeInterval(120)]))
    }

    private func session(matchID: String = "evidence-fixture", provider: String = "CS1",
                         url: String = "https://media.example/live.m3u8?token=original",
                         headers: [String: String] = ["User-Agent": "Fixture"], streamType: StreamType = .hls,
                         endpoint: StreamPlaybackContract.Endpoint? = nil, at date: Date? = nil) throws -> StreamSession {
        StreamSession(matchID: matchID, playableURL: try XCTUnwrap(URL(string: url)), streamType: streamType,
            providerName: provider, requiredHeaders: headers, createdAt: date ?? now,
            declaredPlaybackEndpoint: endpoint)
    }

    private func request() -> StreamPlaybackRequest {
        StreamPlaybackRequest(matchID: "evidence-fixture", displayTitle: "Ipswich Town vs Liverpool",
            homeTeam: "Ipswich Town", awayTeam: "Liverpool", category: "football", kickoffDate: now)
    }

    private func boundSession(url: String = "https://media.example/live.m3u8?token=original",
                              provider: String = "CS1", at date: Date) throws -> StreamSession {
        let binding = try XCTUnwrap(StreamEventBinding(request: request(), providerCode: "communitysports",
            providerEventID: "event-1", streamID: "stream-1", manifestRevision: "revision-1",
            verifiedAt: date, expiresAt: date.addingTimeInterval(90), at: date))
        return try session(provider: provider, url: url, at: date)
            .recordingEventBinding(binding, for: request(), at: date)
    }

    private func receipt(for session: StreamSession, configuration: UUID? = nil, lookupID: UUID = UUID(),
                         at date: Date? = nil) throws -> DeliveryProvenance {
        let scope = try XCTUnwrap(LiveSourceHealthStore.fixtureProgrammeScope(fixtureID: session.matchID))
        return try XCTUnwrap(LiveSourceHealthStore.deliveryProvenance(for: session, scope: scope,
            listingID: "provider-listing", lookupID: lookupID, configurationGeneration: configuration ?? self.configuration,
            at: date ?? now))
    }
}
