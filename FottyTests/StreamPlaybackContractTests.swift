import XCTest
@testable import Fotty

final class StreamPlaybackContractTests: XCTestCase {
    func testRecommendedSubsetShowsFullCountAndAllUsesOriginalIndices() {
        let options = (1...6).map { number in
            StreamSession(matchID: "fixture", playableURL: URL(string: "https://proxy.example/stream/\(number)")!,
                streamType: .hls, providerName: "CS\(number)")
        }
        let short = BroadcastSourcePickerPolicy.matchProjection(options, recommended: [3], filter: .automatic)
        XCTAssertEqual(short.indices, [3])
        XCTAssertEqual(short.summary, "1 recommended · 6 available")
        XCTAssertEqual(short.showAllTitle, "Show all 6 sources")
        let all = BroadcastSourcePickerPolicy.matchProjection(options, recommended: [3], filter: .all)
        XCTAssertEqual(all.indices, Array(options.indices))
        XCTAssertNil(all.showAllTitle)
        XCTAssertNil(all.summary)
        XCTAssertEqual(BroadcastSourcePickerPolicy.matchProjection(options, recommended: [3], filter: .group("CS")).indices, all.indices)
        let whole = BroadcastSourcePickerPolicy.matchProjection(options, recommended: Array(options.indices), filter: .automatic)
        XCTAssertNil(whole.showAllTitle)
        XCTAssertNil(whole.summary)
    }
    func testSelectionShadowComparesAliasesToDifferentFamiliesWithoutLeakingLinksOrClaimingIndependence() {
        let fixture = UUID().uuidString
        func option(_ name: String, _ path: String) -> StreamSession {
            StreamSession(matchID: fixture, playableURL: URL(string: "https://private.example/\(path)?token=secret")!,
                streamType: .hls, providerName: name, requiredHeaders: ["Authorization": "private"])
        }
        let failed = option("AS1", "first"), alias = option("AS2", "second"),
            duplicate = option("FS1", "second"), different = option("CS1", "third")
        let inventory = [failed, alias, duplicate, different]
        let old = [alias, duplicate, different].map(\.legacySource), proposed = [different, alias, duplicate].map(\.legacySource)
        func compare(_ enabled: Bool) -> LivePlaybackSourcePolicy.MatchOrderComparison {
            .init(baseline: old, candidate: proposed, inventory: inventory, current: failed.legacySource, fixtureID: fixture, trial: enabled)
        }
        let shadow = compare(false), trial = compare(true)
        XCTAssertEqual(shadow.selected?.id, alias.id)
        XCTAssertEqual(trial.selected?.id, different.id)
        XCTAssertEqual(shadow.details["baseline_slots"], "2.3.4")
        XCTAssertEqual(shadow.details["candidate_slots"], "4.2.3")
        XCTAssertEqual(shadow.details["duplicate_choices"], "1")
        XCTAssertEqual(shadow.details["selection_reason"], "different_family")
        XCTAssertEqual(shadow.details["independence_evidence"], "unverified")
        XCTAssertEqual(shadow.details["selection_applied"], "baseline")
        XCTAssertEqual(trial.details["selection_version"], "1")
        XCTAssertFalse(shadow.details.values.contains { $0.contains(fixture) || $0.contains("private") || $0.contains("secret") })
    }
    @MainActor func testMatchPickerCapsDistinctOriginsWithoutLosingManualOrRecoveryCandidates() throws {
        let now = Date()
        let event = EventReference(id: "picker-fixture", title: "One vs Two", category: "football",
            date: Int64(now.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "One", badge: nil), away: .init(name: "Two", badge: nil)), sources: [])
        func session(_ name: String, _ url: String, match: String? = nil, expiry: Date? = nil) -> StreamSession {
            StreamSession(matchID: match ?? event.id, playableURL: URL(string: url)!, streamType: .hls,
                providerName: name, expiryTime: expiry)
        }
        let options = [
            session("AS1", "https://as.test/a.m3u8"), session("AS2", "https://as.test/b.m3u8"),
            session("FS1", "https://as.test/a.m3u8"), session("CS1", "https://cs.test/c.m3u8"),
            session("StreamEx", "https://third.test/d.m3u8"), session("CS2", "https://fourth.test/e.m3u8"),
            session("FS2", "https://different.test/f.m3u8", match: "another-fixture"),
            session("FS3", "https://expired.test/g.m3u8", expiry: now),
            session("FS4", "https://unknown.test/h.m3u8"), session("FS5", "https://failed.test/i.m3u8")
        ]
        let proven = Set(options[0...7].map(\.id))
        let rows = BroadcastSourcePickerPolicy.recommendations(sessions: options, currentIndex: 0,
            failedIDs: [options[9].id], for: event, at: now, hasRecentStart: { proven.contains($0.id) })
        XCTAssertEqual(rows.first, 0)
        XCTAssertEqual(Set(rows), [0, 3, 4])
        XCTAssertEqual(options.count, 10)
        let onlySiblings = Array(options[0...2])
        XCTAssertEqual(BroadcastSourcePickerPolicy.recommendations(sessions: onlySiblings, currentIndex: 0,
            failedIDs: [], for: event, at: now, hasRecentStart: { _ in true }), [0])
        XCTAssertEqual(BroadcastSourcePickerPolicy.recommendations(sessions: options, currentIndex: 0,
            failedIDs: [options[0].id], for: event, at: now, hasRecentStart: { _ in false }), [])
    }

    @MainActor func testAutomaticAlternativeRequiresSameFixtureAndDoesNotRenewAnUnboundExpiredURL() throws {
        let now = Date()
        let event = EventReference(id: "switch-fixture", title: "One vs Two", category: "football",
            date: Int64(now.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "One", badge: nil), away: .init(name: "Two", badge: nil)), sources: [])
        let request = StreamPlaybackRequest(event: event)
        func option(_ name: String, match: String, expiry: Date? = nil) -> StreamSession {
            .init(matchID: match, playableURL: URL(string: "https://unit.test/choice.m3u8")!,
                streamType: .hls, providerName: name, expiryTime: expiry)
        }
        XCTAssertEqual(LivePlaybackSourcePolicy.admissionForMatchAlternative(option("Score808", match: event.id), request: request, at: now), .ready)
        XCTAssertNil(LivePlaybackSourcePolicy.admissionForMatchAlternative(option("Score808", match: "other"), request: request, at: now))
        XCTAssertNil(LivePlaybackSourcePolicy.admissionForMatchAlternative(option("Score808", match: event.id, expiry: now), request: request, at: now))
        XCTAssertNil(LivePlaybackSourcePolicy.admissionForMatchAlternative(option("TV4", match: event.id), request: request, at: now))
        XCTAssertEqual(LivePlaybackSourcePolicy.matchPublisher(for: option("StreamEx", match: event.id).legacySource),
            LivePlaybackSourcePolicy.matchPublisher(for: option("delta", match: event.id).legacySource))
    }
    func testSourcePickerGroupsUseOnlyReviewedLabelsAndPreserveOrder() throws {
        func choice(_ provider: String) -> StreamSession {
            .init(matchID: "picker", playableURL: URL(string: "https://example.invalid/player.m3u8")!,
                  streamType: .hls, providerName: provider)
        }
        XCTAssertEqual(BroadcastSourcePickerPolicy.groups(in: [choice("StreamEx"), choice("AS1"), choice("CS2"),
            choice("AS2"), choice("Score808"), choice("SV1")]), ["Broadcasts", "AS", "CS", "SV"])
        for raw in ["https://private.invalid/token", "A source named AS1", "FS7", "AS01", "as1"] {
            XCTAssertEqual(BroadcastSourcePickerPolicy.group(for: choice(raw)), "Broadcasts")
        }
        XCTAssertEqual(BroadcastSourcePickerPolicy.groups(in: []), [])
        XCTAssertEqual(BroadcastSourcePickerPolicy.groups(in: [choice("AS1"), choice("AS2")]), ["AS"])
    }
    func testDeclaredNativeSessionKeepsTypedRouteThroughLegacySourceWithoutInventingProbeEvidence() throws {
        let session = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://embed.example/opaque?url=https%3A%2F%2Fexample.invalid%2Fembed%2Fpage")),
            streamType: .hls, providerName: "CS1", validationStatus: .validated)
        XCTAssertEqual(session.playbackContract.endpoint, .directMedia)
        XCTAssertEqual(session.playbackContract.declaredContainer, .hls)
        XCTAssertEqual(session.playbackContract.nativePreparationEligibility, .candidate)
        XCTAssertNil(session.mediaProbeEvidence)
        XCTAssertNil(session.playbackContract.mediaProbeEvidence)
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(session))
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(session.legacySource))
    }

    func testValidatedWebPageNeedsMediaObservationAndIgnoresNestedMediaURL() throws {
        let session = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://addon.example/watch?url=https%3A%2F%2Fvideo.example%2Fmaster.m3u8")),
            streamType: .unknown, providerName: "CS2", requiredHeaders: ["X-Fotty-Web-Embed": "true"],
            validationStatus: .validated)
        XCTAssertEqual(session.playbackContract.endpoint, .webPage)
        XCTAssertEqual(session.playbackContract.container, .unknown)
        XCTAssertEqual(session.playbackContract.nativePreparationEligibility, .needsMediaObservation)
        XCTAssertNil(session.mediaProbeEvidence, "Validated listing/HTML is not a media response observation")
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(session))
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(session.legacySource))
    }

    func testUnknownAndUnsupportedEndpointsDoNotGainNativeCompatibilityFromValidatedStatus() throws {
        let unknown = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://media.example/opaque")), streamType: .unknown, providerName: "Fixture",
            validationStatus: .validated)
        XCTAssertEqual(unknown.playbackContract.endpoint, .unknown)
        XCTAssertEqual(unknown.playbackContract.nativePreparationEligibility, .needsMediaObservation)
        let unsupported = StreamPlaybackContract.describing(url: try XCTUnwrap(URL(string:
            "magnet:?xt=urn:btih:fixture")), provider: "Fixture", headers: [:], streamType: .hls)
        XCTAssertEqual(unsupported.endpoint, .unsupported)
        XCTAssertEqual(unsupported.nativePreparationEligibility, .unavailable)
    }

    func testProbeKeepsMIMEDeclarationSeparateFromObservedFormat() {
        let evidence = StreamMediaProbeEvidence(contentType: "Video/MP4; charset=binary",
                                                prefix: Data("#EXTM3U\n#EXT-X-VERSION:3\n".utf8))
        XCTAssertEqual(evidence.responseType, .mp4)
        XCTAssertEqual(evidence.observedContainer, .hls)
        XCTAssertEqual(evidence.preferredContainer, .hls)
        XCTAssertEqual(evidence.preferredStreamType, .hls)
        let declarationOnly = StreamMediaProbeEvidence(contentType: "video/mp4", prefix: Data("not-decoded".utf8))
        XCTAssertEqual(declarationOnly.observedContainer, .unknown)
        XCTAssertEqual(declarationOnly.preferredContainer, .mp4)
        let generic = StreamMediaProbeEvidence(contentType: "application/octet-stream", prefix: Data([0, 1, 2]))
        XCTAssertEqual(generic.responseType, .binary)
        XCTAssertEqual(generic.preferredContainer, .unknown)
        XCTAssertEqual(generic.preferredStreamType, .unknown)
        let transport = StreamMediaProbeEvidence(contentType: "video/mp2t", prefix: Data([0x47]))
        XCTAssertEqual(transport.preferredContainer, .mpegTransportStream)
        XCTAssertEqual(transport.preferredStreamType, .unknown, "Transport-stream MIME is not an HLS manifest")
    }

    func testHLSObservationRequiresBoundedHeaderNotAMarkerInsideHTMLOrBeyondBudget() {
        for header in ["#EXTM3U", "#EXTM3U\n", "#EXTM3U\r", "#EXTM3U\r\n",
                       "\u{feff}#EXTM3U\n", "\u{feff}#EXTM3U\r\n"] {
            XCTAssertEqual(StreamMediaProbeEvidence(contentType: "text/plain", prefix: Data(header.utf8))
                .observedContainer, .hls, "Header bytes: \(Array(header.utf8))")
        }
        for text in ["<html>#EXTM3U</html>", "#EXTM3U-not-a-header", "#EXTM3U\u{0301}\n",
                     String(repeating: " ", count: 1024) + "#EXTM3U\n"] {
            XCTAssertEqual(StreamMediaProbeEvidence(contentType: "text/plain", prefix: Data(text.utf8))
                .observedContainer, .unknown)
        }
    }

    func testMP4FileTypeObservationRejectsTruncatedInvalidAndStillImageBoxes() {
        XCTAssertEqual(StreamMediaProbeEvidence(contentType: "application/octet-stream", prefix: Self.mp4Prefix)
            .observedContainer, .mp4)
        let compatibleBrand = Data([0, 0, 0, 20]) + Data("ftypzzzz".utf8) + Data([0, 0, 0, 0]) + Data("mp42".utf8)
        XCTAssertEqual(StreamMediaProbeEvidence(contentType: "application/octet-stream", prefix: compatibleBrand)
            .observedContainer, .mp4)
        for prefix in [Data("ftypmp42".utf8), Data([0, 0, 0, 4]) + Self.mp4Prefix.dropFirst(4),
                       Data([0, 0, 0, 16]) + Data("ftypavif".utf8) + Data([0, 0, 0, 0])] {
            XCTAssertEqual(StreamMediaProbeEvidence(contentType: "application/octet-stream", prefix: prefix)
                .observedContainer, .unknown)
        }
    }

    func testSessionSerializationDropsProbeEvidenceAndIgnoresForgedPersistedObservation() throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let session = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://media.example/opaque")), streamType: .mp4, providerName: "CS1",
            requiredHeaders: ["Referer": "https://page.example/player"], expiryTime: expiry,
            leaseID: "fixture-lease", canRefresh: true,
            mediaProbeEvidence: .init(contentType: "application/octet-stream", prefix: Self.mp4Prefix))
        let bytes = try JSONEncoder().encode(session)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(document["mediaProbeEvidence"])
        XCTAssertNil(document["playbackContract"])
        document["mediaProbeEvidence"] = ["observedContainer": "hls", "responseType": "hls"]
        let decoded = try JSONDecoder().decode(StreamSession.self,
            from: JSONSerialization.data(withJSONObject: document))
        XCTAssertNil(decoded.mediaProbeEvidence)
        XCTAssertEqual(decoded.playbackContract.container, .mp4)
        XCTAssertEqual(decoded.requiredHeaders, session.requiredHeaders)
        XCTAssertEqual(decoded.expiryTime, expiry)
        XCTAssertEqual(decoded.leaseID, session.leaseID)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertNil(decoded.nativeOriginProfile)
        XCTAssertNil(decoded.nativePlaylistProfile)
    }

    func testLegacyHeaderMutationInvalidatesProbeButPreservesRouteAndRequiredHeaders() throws {
        let session = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://embed.example/opaque")), streamType: .mp4, providerName: "CS1",
            requiredHeaders: ["User-Agent": "Fixture One"],
            mediaProbeEvidence: .init(contentType: "video/mp4", prefix: Self.mp4Prefix))
        let original = session.legacySource
        XCTAssertNotNil(original.playbackContract?.mediaProbeEvidence)
        XCTAssertNotNil(original.mergingHeaders([:]).playbackContract?.mediaProbeEvidence)
        let changed = original.mergingHeaders(["User-Agent": "Fixture Two", "Referer": "https://page.example/"])
        XCTAssertNil(changed.playbackContract?.mediaProbeEvidence)
        XCTAssertEqual(changed.playbackContract?.declaredContainer, .mp4)
        XCTAssertEqual(changed.playbackContract?.endpoint, .directMedia)
        XCTAssertEqual(changed.headers["User-Agent"], "Fixture Two")
        XCTAssertEqual(changed.headers["Referer"], "https://page.example/")
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(changed))
    }

    func testRecordingProbeCannotReplaceSessionIdentityDeliveryOrExpiry() throws {
        let original = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://media.example/opaque")), streamType: .hls, providerName: "CS1",
            requiredHeaders: ["User-Agent": "Fixture"], expiryTime: Date(timeIntervalSince1970: 2_000_000_000),
            leaseID: "fixture-lease", diagnosticMetadata: ["source_key": "fixture"])
        let observed = original.recordingMediaProbe(.init(contentType: "video/mp4", prefix: Self.mp4Prefix))
        XCTAssertNil(original.mediaProbeEvidence)
        XCTAssertEqual(observed.playbackContract.declaredContainer, .hls)
        XCTAssertEqual(observed.playbackContract.container, .mp4)
        XCTAssertEqual(observed.id, original.id)
        XCTAssertEqual(observed.playableURL, original.playableURL)
        XCTAssertEqual(observed.requiredHeaders, original.requiredHeaders)
        XCTAssertEqual(observed.expiryTime, original.expiryTime)
        XCTAssertEqual(observed.leaseID, original.leaseID)
        XCTAssertEqual(observed.diagnosticMetadata, original.diagnosticMetadata)
        XCTAssertNil(observed.recordingMediaProbe(nil).mediaProbeEvidence)
    }

    func testObservedOpaqueNativeCandidateCannotFallBackIntoWebRouting() throws {
        let opaque = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://embed.example/opaque")), streamType: .unknown, providerName: "Embed Fixture",
            requiredHeaders: ["Referer": "https://page.example/player"])
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(opaque))
        let observed = opaque.recordingMediaProbe(.init(contentType: "application/octet-stream",
            prefix: Data("#EXTM3U\n".utf8)))
        XCTAssertEqual(observed.streamType, .unknown, "The declaration must not be rewritten as an observation")
        XCTAssertEqual(observed.playbackContract.declaredContainer, .unknown)
        XCTAssertEqual(observed.playbackContract.declaredEndpoint, .webPage)
        XCTAssertEqual(observed.playbackContract.endpoint, .directMedia)
        XCTAssertEqual(observed.playbackContract.container, .hls)
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(observed))
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(observed.legacySource))
        let changed = observed.legacySource.mergingHeaders(["Referer": "https://changed.example/player"])
        XCTAssertNil(changed.playbackContract?.mediaProbeEvidence)
        XCTAssertEqual(changed.playbackContract?.endpoint, .webPage,
                       "Changing delivery must not retain a probe-derived route")
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(changed))
        XCTAssertNil(observed.nativeOriginProfile)
        XCTAssertNil(observed.nativePlaylistProfile)
    }

    func testCapturedEndpointRoleDoesNotInventFormatAndCannotOverrideUnsupportedScheme() throws {
        let evidence = StreamMediaProbeEvidence(contentType: "application/octet-stream", prefix: Data([0, 1, 2]))
        let captured = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://embed.example/opaque")), streamType: .unknown, providerName: "Embed Fixture",
            mediaProbeEvidence: evidence, declaredPlaybackEndpoint: .directMedia)
        XCTAssertEqual(captured.playbackContract.endpoint, .directMedia)
        XCTAssertEqual(captured.playbackContract.container, .unknown)
        XCTAssertEqual(captured.playbackContract.nativePreparationEligibility, .candidate)
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(captured))
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(captured.legacySource))
        let changed = captured.legacySource.mergingHeaders(["User-Agent": "Fixture"])
        XCTAssertEqual(changed.playbackContract?.endpoint, .directMedia, "A captured role is not a format probe")
        XCTAssertEqual(changed.playbackContract?.container, .unknown)
        XCTAssertNil(changed.playbackContract?.mediaProbeEvidence)
        XCTAssertEqual(captured.recordingMediaProbe(nil).declaredPlaybackEndpoint, .directMedia)
        let bytes = try JSONEncoder().encode(captured)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(document["declaredPlaybackEndpoint"])
        document["declaredPlaybackEndpoint"] = "directMedia"
        let decoded = try JSONDecoder().decode(StreamSession.self,
            from: JSONSerialization.data(withJSONObject: document))
        XCTAssertNil(decoded.declaredPlaybackEndpoint)
        XCTAssertNil(decoded.mediaProbeEvidence)
        XCTAssertEqual(decoded.playbackContract.endpoint, .webPage)
        XCTAssertNil(captured.nativeOriginProfile)
        XCTAssertNil(captured.nativePlaylistProfile)
        let unsupported = StreamPlaybackContract.describing(url: try XCTUnwrap(URL(string:
            "magnet:?xt=urn:btih:fixture")), provider: "Fixture", headers: [:],
            declaredEndpoint: .directMedia, mediaProbeEvidence: evidence)
        XCTAssertEqual(unsupported.endpoint, .unsupported)
        XCTAssertEqual(unsupported.nativePreparationEligibility, .unavailable)
    }

    @MainActor
    func testCapturedUnknownFormatReceivesNativeRetryWithoutInventingAWebFallback() throws {
        let session = StreamSession(matchID: "contract", playableURL: try XCTUnwrap(URL(string:
            "https://embed.example/opaque")), streamType: .unknown, providerName: "Fixture",
            declaredPlaybackEndpoint: .directMedia)
        let event = AnalyticalDataEngine.EventReference(id: "contract", title: "Fixture", category: "football",
            date: 0, poster: nil, popular: false, teams: nil, sources: nil)
        let slot = MultiLiveSlot(event: event, sessions: [session])
        XCTAssertEqual(slot.recoveryAction(for: session.legacySource, reason: "Failed to start",
            countsAsStall: false, isNetworkReachable: true, webStartupRetryCount: 0,
            webStallRetryCount: 0, nativeStartupRetryCount: 0), .retryNativeStartup(.startupTimeout))
        XCTAssertEqual(slot.recoveryAction(for: session.legacySource, reason: "Failed to start",
            countsAsStall: false, isNetworkReachable: true, webStartupRetryCount: 0,
            webStallRetryCount: 0, nativeStartupRetryCount: 1), .exhaustSource(.startupTimeout))
    }

    func testValidationResultKeepsInjectedSuccessSeparateFromObservedSuccess() {
        let legacy = StreamContractValidator.ValidationResult.valid
        XCTAssertTrue(legacy.isValid)
        XCTAssertNil(legacy.mediaEvidence)
        let evidence = StreamMediaProbeEvidence(contentType: "video/mp4", prefix: Self.mp4Prefix)
        let observed = StreamContractValidator.ValidationResult.validWithEvidence(evidence)
        XCTAssertTrue(observed.isValid)
        XCTAssertEqual(observed.mediaEvidence, evidence)
        let failure = StreamContractValidator.ValidationResult.invalid("Fixture failure")
        XCTAssertFalse(failure.isValid)
        XCTAssertNil(failure.mediaEvidence)
    }

    func testOpaqueNativeValidationReturnsBoundedActualFormatWithoutASecondRequest() async throws {
        for (body, mime, expected) in [(Data("#EXTM3U\n#EXT-X-VERSION:3\n".utf8), "text/plain", StreamType.hls),
                                       (Self.mp4Prefix, "application/octet-stream", StreamType.mp4)] {
            StreamContractProtocol.configure(body: body, mime: mime)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StreamContractProtocol.self]
            let result = await StreamContractValidator(configuration: configuration, deadline: 1)
                .validate(try XCTUnwrap(URL(string: "https://contract.invalid/opaque")),
                          headers: ["Referer": "https://page.example/player"])
            XCTAssertTrue(result.isValid)
            XCTAssertEqual(result.mediaEvidence?.preferredStreamType, expected)
            XCTAssertEqual(StreamContractProtocol.requests.count, 1)
            XCTAssertEqual(StreamContractProtocol.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=0-1023")
            XCTAssertEqual(StreamContractProtocol.requests.first?.value(forHTTPHeaderField: "Referer"),
                           "https://page.example/player")
        }
    }

    func testHTMLMarkerCannotValidateAsAnHLSManifest() async throws {
        StreamContractProtocol.configure(body: Data("<html><script>const example = '#EXTM3U';</script></html>".utf8),
                                         mime: "application/vnd.apple.mpegurl")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamContractProtocol.self]
        let result = await StreamContractValidator(configuration: configuration, deadline: 1)
            .validate(try XCTUnwrap(URL(string: "https://contract.invalid/live.m3u8")), headers: [:])
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.mediaEvidence)
        guard case .invalid(_, let diagnostic) = result else { return XCTFail("HTML is not an HLS header") }
        XCTAssertEqual(diagnostic?.qualityDetails["preparation_reason"], "malformed_manifest")
        XCTAssertEqual(StreamContractProtocol.requests.count, 1)
    }

    private static let mp4Prefix = Data([0, 0, 0, 20]) + Data("ftypisom".utf8) + Data([0, 0, 0, 0]) + Data("mp42".utf8)
}

private final class StreamContractProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var body = Data()
    private static var mime = "application/octet-stream"
    private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests
    }

    static func configure(body: Data, mime: String) {
        lock.lock(); defer { lock.unlock() }
        self.body = body; self.mime = mime; recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let body = Self.body, mime = Self.mime
        Self.lock.unlock()
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
