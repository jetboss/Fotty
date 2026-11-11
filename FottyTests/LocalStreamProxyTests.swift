import XCTest
import Network
import AVFoundation
@testable import Fotty

final class LocalStreamProxyTests: XCTestCase {
    func testPlaylistProgressSeparatesFrozenWindowFromSequenceAdvanceAndURIOnlyChange() throws {
        let resource = UUID()
        var progress = LocalHLSPlaylistProgress()
        let first = playlistFacts(sequence: 7, lastURI: "segment8.ts?token=private-token")
        progress.observe(upstream: first, rewritten: first, resourceID: resource, startedAt: 100, at: 100)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isNonAdvancingLive(at: 100))
        progress.observe(upstream: first, rewritten: first, resourceID: resource, startedAt: 110, at: 110)
        let frozen = try XCTUnwrap(progress.latestSnapshot)
        XCTAssertTrue(frozen.isNonAdvancingLive(at: 111))
        XCTAssertFalse(frozen.isNonAdvancingLive(at: 126), "An old receipt cannot trigger a current recovery")
        XCTAssertEqual(frozen.qualityDetails(at: 115)["relay_playlist_upstream_unchanged_ms"], "10000",
            "Reading diagnostics later cannot invent additional unchanged responses")

        let advanced = playlistFacts(sequence: 8, lastURI: "segment9.ts?token=private-token")
        progress.observe(upstream: advanced, rewritten: advanced, resourceID: resource, startedAt: 111, at: 111)
        XCTAssertEqual(progress.latestSnapshot?.upstream.change, .advanced)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isNonAdvancingLive(at: 111))
        let rotated = playlistFacts(sequence: 8, lastURI: "segment9.ts?token=replaced-private-token")
        progress.observe(upstream: rotated, rewritten: rotated, resourceID: resource, startedAt: 112, at: 112)
        XCTAssertEqual(progress.latestSnapshot?.upstream.change, .windowChanged,
            "A fresh signature is not a newly published media sequence or decoded frame")
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isNonAdvancingLive(at: 112))
        let details = try XCTUnwrap(progress.latestSnapshot).qualityDetails(at: 112).description
        for privateValue in ["segment9", "token=", "private-token", "https://"] { XCTAssertFalse(details.contains(privateValue)) }
    }

    func testAdvancingLivePlaylistRecoveryRequiresRecentSequenceProgress() throws {
        let resource = UUID()
        var progress = LocalHLSPlaylistProgress()
        let first = playlistFacts(sequence: 7, lastURI: "segment8.ts")
        progress.observe(upstream: first, rewritten: first, resourceID: resource, startedAt: 100, at: 100)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isAdvancingLive(at: 100), "One response cannot prove sequence progress")
        let advanced = playlistFacts(sequence: 8, lastURI: "segment9.ts")
        progress.observe(upstream: advanced, rewritten: advanced, resourceID: resource, startedAt: 110, at: 110)
        let snapshot = try XCTUnwrap(progress.latestSnapshot)
        XCTAssertTrue(snapshot.isAdvancingLive(at: 110))
        XCTAssertTrue(snapshot.isAdvancingLive(at: 125))
        for clock in [109, 125.001, Double.nan, Double.infinity] {
            XCTAssertFalse(snapshot.isAdvancingLive(at: clock), "Only current relay evidence can authorize recovery")
        }
        let rotated = playlistFacts(sequence: 8, lastURI: "segment9.ts?token=replaced-private-token")
        progress.observe(upstream: rotated, rewritten: rotated, resourceID: resource, startedAt: 111, at: 111)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isAdvancingLive(at: 111), "Token rotation is not media progress")
        progress.observe(upstream: first, rewritten: first, resourceID: resource, startedAt: 112, at: 112)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isAdvancingLive(at: 112), "A regressed sequence cannot authorize recovery")
        progress.observe(upstream: first, rewritten: first, resourceID: resource, startedAt: 113, at: 113)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isAdvancingLive(at: 113), "Unchanged windows retain their separate frozen-window policy")
    }

    func testAdvancingLivePlaylistRecoveryRejectsEndedIncompleteOrChangedRewriteEvidence() throws {
        let first = playlistFacts(sequence: 7, lastURI: "segment8.ts")
        let advanced = playlistFacts(sequence: 8, lastURI: "segment9.ts")
        let missingTarget = LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:8\n#EXTINF:6,\nsegment9.ts")
        let partial = LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:8\n#EXTINF:6,\nsegment9.ts\n#EXT-X-PART:DURATION=1,URI=\"part.ts\"")
        for (upstream, rewritten) in [
            (playlistFacts(sequence: 8, lastURI: "segment9.ts", endList: true), playlistFacts(sequence: 8, lastURI: "segment9.ts", endList: true)),
            (missingTarget, missingTarget), (partial, partial),
            (advanced, first), (first, advanced)
        ] {
            var progress = LocalHLSPlaylistProgress(); let resource = UUID()
            progress.observe(upstream: first, rewritten: first, resourceID: resource, startedAt: 100, at: 100)
            progress.observe(upstream: upstream, rewritten: rewritten, resourceID: resource, startedAt: 110, at: 110)
            XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isAdvancingLive(at: 111))
        }
    }

    func testPlaylistProgressNeverRenewsMasterVODMalformedOrUnverifiedWindows() throws {
        let live = playlistFacts(sequence: 7, lastURI: "segment8.ts")
        let fixtures = [
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1500000\nvariant.m3u8"),
            playlistFacts(sequence: 7, lastURI: "segment8.ts", endList: true),
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts"),
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-MEDIA-SEQUENCE:8\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts"),
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-TARGETDURATION:0\n#EXTINF:6,\nsegment.ts"),
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,"),
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts\n#EXT-X-PART:DURATION=1,URI=\"part.ts?nonce=private\""),
            LocalHLSPlaylistProgress.Facts.observed(in: "#EXTM3U\n#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts"),
            LocalHLSPlaylistProgress.Facts.observed(in: "<html>private-body</html>")
        ]
        for facts in fixtures {
            var progress = LocalHLSPlaylistProgress(); let resource = UUID()
            progress.observe(upstream: facts, rewritten: facts, resourceID: resource, startedAt: 100, at: 100)
            progress.observe(upstream: facts, rewritten: facts, resourceID: resource, startedAt: 110, at: 110)
            XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isNonAdvancingLive(at: 111))
        }
        var changedRewrite = LocalHLSPlaylistProgress(); let resource = UUID()
        let wrong = playlistFacts(sequence: 70, lastURI: "segment8.ts")
        changedRewrite.observe(upstream: live, rewritten: wrong, resourceID: resource, startedAt: 100, at: 100)
        changedRewrite.observe(upstream: live, rewritten: wrong, resourceID: resource, startedAt: 110, at: 110)
        XCTAssertFalse(try XCTUnwrap(changedRewrite.latestSnapshot).metadataPreserved)
        XCTAssertFalse(try XCTUnwrap(changedRewrite.latestSnapshot).isNonAdvancingLive(at: 111))
    }

    func testPlaylistProgressIsBoundedAndOlderConcurrentResponsesCannotReplaceNewerEvidence() throws {
        var progress = LocalHLSPlaylistProgress(); let resource = UUID()
        let old = playlistFacts(sequence: 7, lastURI: "old.ts"), fresh = playlistFacts(sequence: 8, lastURI: "new.ts")
        progress.observe(upstream: fresh, rewritten: fresh, resourceID: resource, startedAt: 101, at: 102)
        progress.observe(upstream: old, rewritten: old, resourceID: resource, startedAt: 100, at: 103)
        XCTAssertEqual(progress.latestSnapshot?.upstream.facts.mediaSequence, 8)
        for invalid in [Double.nan, Double.infinity, -1] {
            progress.observe(upstream: old, rewritten: old, resourceID: resource, startedAt: invalid, at: 104)
        }
        XCTAssertEqual(progress.latestSnapshot?.sampleCount, 1)
        for index in 0..<40 {
            progress.observe(upstream: old, rewritten: old, resourceID: UUID(),
                startedAt: Double(200 + index), at: Double(200 + index))
        }
        XCTAssertEqual(progress.retainedCount, LocalHLSPlaylistProgress.maximumResources)
        XCTAssertFalse(try XCTUnwrap(progress.latestSnapshot).isNonAdvancingLive(at: 239),
            "Unrelated resources cannot accumulate the same window's unchanged duration")
    }

    func testActualRelayObservesPlaylistProgressWithoutAdditionalRequestsOrPrivateExports() async throws {
        ProxyFixtureProtocol.configure { fixture in
            let sequence = ProxyFixtureProtocol.requests.count
            let body = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:\(sequence)\n#EXTINF:6,\nsegment\(sequence).ts?token=private-token"
            fixture.respond(type: "application/vnd.apple.mpegurl", body: Data(body.utf8))
        }
        let proxy = makeProxy(); defer { proxy.stop() }
        try await proxy.start()
        let local = try XCTUnwrap(proxy.playbackURL())
        for _ in 0..<2 { _ = try await URLSession.shared.data(from: local) }
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 2, "Observation issues no new media or metadata requests")
        let details = proxy.diagnosticDetails()
        XCTAssertEqual(details["relay_playlist_samples"], "2")
        XCTAssertEqual(details["relay_playlist_upstream_sequence"], "2")
        XCTAssertEqual(details["relay_playlist_rewritten_sequence"], "2")
        XCTAssertEqual(details["relay_playlist_upstream_change"], "advanced")
        XCTAssertEqual(details["relay_playlist_metadata_preserved"], "true")
        XCTAssertNotEqual(details["relay_playlist_upstream_last_digest"], details["relay_playlist_rewritten_last_digest"])
        XCTAssertFalse(proxy.hasNonAdvancingLivePlaylist())
        XCTAssertTrue(proxy.hasAdvancingLivePlaylist(), "The selected relay exposes its actual recent sequence progress")
        let suite = "relay-playlist-privacy-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        store.record(category: .playback, name: "synthetic_progress", outcome: .info, details: details)
        let persisted = try XCTUnwrap(store.records().first).details
        XCTAssertEqual(persisted["relay_playlist_upstream_change"], "advanced")
        for privateValue in ["media.example", "private-token", "segment2.ts", local.pathComponents[1], "http://", "https://"] {
            XCTAssertFalse(persisted.description.contains(privateValue))
        }
        proxy.stop()
        XCTAssertFalse(proxy.hasNonAdvancingLivePlaylist(), "A retired relay cannot authorize recovery")
        XCTAssertFalse(proxy.hasAdvancingLivePlaylist(), "A retired relay cannot authorize advancing-window recovery")
    }

    private func playlistFacts(sequence: Int, lastURI: String, endList: Bool = false) -> LocalHLSPlaylistProgress.Facts {
        .observed(in: "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:\(sequence)\n#EXTINF:6,\nfirst.ts\n#EXTINF:6,\n\(lastURI)" + (endList ? "\n#EXT-X-ENDLIST" : ""))
    }

    func testAccessMetricsKeepOnlyFiniteMeasuredScalars() {
        let metrics = NativePlaybackAccessMetrics(observedBitrate: 2_100_000, indicatedBitrate: 1_500_000,
            stallCount: 2, droppedFrames: 3, bytes: 4_000_000, transferDuration: 2.5)
        XCTAssertEqual(metrics.qualityDetails, ["native_access_observed_bitrate": "2100000", "native_access_indicated_bitrate": "1500000",
            "native_access_stalls": "2", "native_access_dropped_frames": "3", "native_access_bytes": "4000000", "native_access_transfer_ms": "2500"])
        let invalid = NativePlaybackAccessMetrics(observedBitrate: .nan, indicatedBitrate: .infinity,
            stallCount: -1, droppedFrames: -1, bytes: -1, transferDuration: .nan)
        XCTAssertTrue(invalid.qualityDetails.isEmpty)
        let huge = NativePlaybackAccessMetrics(observedBitrate: .greatestFiniteMagnitude, indicatedBitrate: -1,
            stallCount: .max, droppedFrames: .max, bytes: .max, transferDuration: .greatestFiniteMagnitude)
        XCTAssertEqual(huge.qualityDetails["native_access_stalls"], "1000000")
        XCTAssertEqual(huge.qualityDetails["native_access_transfer_ms"], "3600000")
        XCTAssertNil(huge.qualityDetails["native_access_observed_bitrate"])
    }

    private let media = URL(string: "https://media.example.com/live/master.m3u8")!

    override func tearDown() {
        ProxyFixtureProtocol.reset()
        super.tearDown()
    }

    func testCapabilityRoutesCannotBeForgedOrRetargeted() throws {
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media)
        let local = try XCTUnwrap(policy.playbackURL(port: 8765))
        XCTAssertEqual(local.host, "127.0.0.1")
        XCTAssertNil(local.query)
        XCTAssertFalse(local.absoluteString.contains(media.host!))
        XCTAssertEqual(policy.destination(for: local.path), media)
        XCTAssertNil(policy.destination(for: local.path + "?url=https://other.example.com/secret"))
        XCTAssertNil(policy.destination(for: "/proxy?url=" + media.absoluteString))
        XCTAssertNil(policy.destination(for: "/forged/media/" + local.lastPathComponent))
        XCTAssertNil(policy.destination(for: "/\(policy.capability)/media/forged"))
        let other = LocalStreamProxyPolicy(selectedMediaURL: media)
        XCTAssertNotEqual(policy.capability, other.capability)
        XCTAssertNil(policy.destination(for: try XCTUnwrap(other.playbackURL(port: 8765)).path))
        policy.revoke()
        XCTAssertNil(policy.destination(for: local.path))
        XCTAssertNil(policy.playbackURL(port: 8765))
        XCTAssertEqual(policy.registeredURLCount, 0)
    }

    func testURLAdmissionRejectsPrivateAndUnsupportedDestinations() {
        for value in ["http://media.example.com/a", "file:///tmp/a", "data:text/plain,secret",
                      "https://user:pass@media.example.com/a", "https://media.example.com:8443/a",
                      "https://media.example.com/a#fragment", "https://localhost/a", "https://printer.local/a",
                      "https://127.0.0.1/a", "https://10.1.2.3/a", "https://169.254.169.254/a",
                      "https://172.16.0.1/a", "https://192.168.1.1/a", "https://100.64.0.1/a",
                      "https://127.1/a", "https://2130706433/a", "https://0x7f.0x0.0x0.0x1/a",
                      "https://[::1]/a", "https://[::ffff:127.0.0.1]/a", "https://[fd00::1]/a",
                      "https://[fe80::1]/a", "https://[2002:7f00:1::]/a", "https://[2001:db8::1]/a"] {
            XCTAssertFalse(LocalStreamProxyPolicy.allowsDestination(URL(string: value)!), value)
        }
        for value in [media.absoluteString, "https://cdn.example.net/path/segment.ts?token=a%2Fb",
                      "https://8.8.8.8/a", "https://[2606:4700:4700::1111]/a"] {
            XCTAssertTrue(LocalStreamProxyPolicy.allowsDestination(URL(string: value)!), value)
        }
    }

    func testCSManifestAliasRecognitionDoesNotRewriteOrBroadenSignedRoutes() throws {
        let manifest = URL(string: "https://nuviosports.xyz/manifest.json")!
        let query = "?url=https%3A%2F%2Fvideo.example%2Flive.m3u8%3Ftoken%3Dfixture%252Bvalue&rck=fixture%2Bkey"
        for path in ["/api/manifest", "/api/manifest.m3u8"] {
            let selected = try XCTUnwrap(URL(string: "https://nuviosports.xyz" + path + query))
            XCTAssertTrue(LocalStreamProxyPolicy.isCommunitySportsManifestRoute(selected, manifestURL: manifest))
            var policy = LocalStreamProxyPolicy(selectedMediaURL: selected)
            let local = try XCTUnwrap(policy.playbackURL(port: 8765))
            XCTAssertEqual(policy.destination(for: local.path)?.absoluteString, selected.absoluteString)
        }
        for path in ["/api/manifest.mpd", "/api/manifest.m3u8/", "/API/manifest.m3u8", "/api/%6danifest.m3u8",
                     "/api/other/../manifest.m3u8", "/api//manifest.m3u8"] {
            XCTAssertFalse(LocalStreamProxyPolicy.isCommunitySportsManifestRoute(
                URL(string: "https://nuviosports.xyz" + path + query)!, manifestURL: manifest), path)
        }
        XCTAssertFalse(LocalStreamProxyPolicy.isCommunitySportsManifestRoute(
            URL(string: "https://other.example/api/manifest.m3u8" + query)!, manifestURL: manifest))
    }

    func testDNSPreflightRejectsPrivateMixedEmptyAndUnparseableAnswers() async throws {
        for addresses in [[], ["127.0.0.1"], ["8.8.8.8", "192.168.1.1"], ["not-an-address"], ["::ffff:127.0.0.1"]] {
            do {
                try await LocalStreamProxyDestinationValidator.validate(media, resolver: { _ in addresses })
                XCTFail("Must reject DNS answers: \(addresses)")
            } catch { }
        }
        try await LocalStreamProxyDestinationValidator.validate(media, resolver: { _ in ["8.8.8.8", "2606:4700:4700::1111"] })
    }

    func testDNSPreflightHonorsCancellation() async {
        let began = expectation(description: "Resolver began")
        let work = Task {
            try await LocalStreamProxyDestinationValidator.validate(media, resolver: { _ in
                began.fulfill()
                try await Task.sleep(for: .seconds(60))
                return ["8.8.8.8"]
            })
        }
        await fulfillment(of: [began], timeout: 2)
        work.cancel()
        do { try await work.value; XCTFail("Cancelled validation must not authorize a destination") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testReviewedCSOriginProfileIsExactAndDefaultPolicyStillRejects8443() throws {
        let (delivery, headers, profile) = try reviewedCSProfile()
        let approved = URL(string: "https://643t8a.7odxv0l067ka.net:8443/live/segment.ts?token=fixture")!
        XCTAssertFalse(LocalStreamProxyPolicy.allowsDestination(approved))
        let ordinary = LocalStreamProxyPolicy(selectedMediaURL: delivery)
        XCTAssertFalse(ordinary.admitsDestination(approved))
        let scoped = LocalStreamProxyPolicy(selectedMediaURL: delivery, originProfile: profile, requestHeaders: headers)
        XCTAssertTrue(scoped.admitsDestination(approved))
        XCTAssertTrue(scoped.admitsDestination(URL(string: "https://cdn.example.net/segment.ts")!))
        for value in ["http://643t8a.7odxv0l067ka.net:8443/a", "https://643t8a.7odxv0l067ka.net:9443/a",
                      "https://other.example.net:8443/a", "https://643t8a.7odxv0l067ka.net.evil.net:8443/a",
                      "https://127.0.0.1:8443/a", "https://user:secret@643t8a.7odxv0l067ka.net:8443/a",
                      "https://643t8a.7odxv0l067ka.net:8443/a#fragment"] {
            XCTAssertFalse(scoped.admitsDestination(URL(string: value)!), value)
        }
    }

    func testCSOriginProfileCannotBeReboundToDifferentDeliveryOrHeaders() throws {
        let (delivery, headers, profile) = try reviewedCSProfile()
        var changed = try XCTUnwrap(URLComponents(url: delivery, resolvingAgainstBaseURL: false))
        changed.queryItems?.append(URLQueryItem(name: "fixture", value: "another-session"))
        let replacement = try XCTUnwrap(changed.url)
        XCTAssertNil(profile.validated(for: replacement, headers: headers))
        var altered = headers
        altered["User-Agent"] = "different-player"
        XCTAssertNil(profile.validated(for: delivery, headers: altered))
        let target = URL(string: "https://643t8a.7odxv0l067ka.net:8443/a.ts")!
        XCTAssertFalse(LocalStreamProxyPolicy(selectedMediaURL: replacement, originProfile: profile,
                                              requestHeaders: headers).admitsDestination(target))
        XCTAssertFalse(LocalStreamProxyPolicy(selectedMediaURL: delivery, originProfile: profile,
                                              requestHeaders: altered).admitsDestination(target))
    }

    func testCSPlaylistProfileIsRuntimeBoundToTheReviewedDeliveryAndHeaders() throws {
        let (delivery, headers, profile) = try reviewedCSPlaylistProfile()
        let manifest = URL(string: "https://nuviosports.xyz/manifest.json")!
        XCTAssertNotNil(profile.validated(for: delivery, headers: headers))
        XCTAssertNotNil(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery, manifestURL: manifest,
                                                                        sourceHint: "timstreams", headers: headers))
        for hint in ["unknown", "", "streamedpk-other"] {
            XCTAssertNil(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery, manifestURL: manifest,
                                                                         sourceHint: hint, headers: headers))
        }
        for badManifest in ["https://other.example/manifest.json", "https://nuviosports.xyz/other.json",
                            "https://nuviosports.xyz/manifest.json?other=1", "https://nuviosports.xyz/manifest.json#fragment"] {
            XCTAssertNil(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery, manifestURL: URL(string: badManifest)!,
                                                                         sourceHint: "streamedpk", headers: headers))
        }
        var changed = try XCTUnwrap(URLComponents(url: delivery, resolvingAgainstBaseURL: false))
        changed.queryItems?.append(URLQueryItem(name: "session", value: "replacement"))
        XCTAssertNil(profile.validated(for: try XCTUnwrap(changed.url), headers: headers))
        var altered = headers
        altered["User-Agent"] = "replacement player"
        XCTAssertNil(profile.validated(for: delivery, headers: altered))
        altered["Authorization"] = "private"
        XCTAssertNil(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery, manifestURL: manifest,
                                                                     sourceHint: "streamedpk", headers: altered))
    }

    func testCSPlaylistReloadPinsTheFirstEquivalentWorkerWithoutRebindingOrNewAuthority() throws {
        let (delivery, headers, profile) = try reviewedCSPlaylistProfile()
        var scoped = LocalStreamProxyPolicy(selectedMediaURL: delivery, requestHeaders: headers, playlistProfile: profile)
        let pool = ["nuvio-proxy.odedararaj456.workers.dev", "nuvio-proxy2.rajodedara360.workers.dev",
                    "nuvio-proxy3.raj-odedara.workers.dev", "spring-brook-5c1e.rajodedara456.workers.dev",
                    "falling-unit-ffa6.rajcfproxy1.workers.dev", "falling-violet-3301.hansabenhodedara.workers.dev",
                    "nameless-dawn-2ab8.abhi-munot01.workers.dev"]
        let first = try reviewedCSWorker(host: pool[0], target: "https://lb1.strmd.st/live/segment8.image?e=123&st=unchanged")
        let original = try rewrittenCSReference(first, policy: &scoped, delivery: delivery)
        for host in pool.dropFirst() {
            let rotated = try reviewedCSWorker(host: host, target: "https://lb1.strmd.st/live/segment8.image?e=123&st=unchanged")
            XCTAssertEqual(try rewrittenCSReference(rotated, policy: &scoped, delivery: delivery), original)
            XCTAssertEqual(scoped.destination(for: original.path), first)
            XCTAssertFalse(scoped.contains(rotated), "Equivalent wrappers are not newly admitted or fetched")
        }
        XCTAssertEqual(scoped.registeredURLCount, 2)
        XCTAssertEqual(scoped.stableSegmentAliasCount, 1)
        XCTAssertEqual(scoped.destination(for: original.path), first, "An in-flight first destination remains immutable and admitted")

        var ordinary = LocalStreamProxyPolicy(selectedMediaURL: delivery)
        let unprofiledFirst = try rewrittenCSReference(first, policy: &ordinary, delivery: delivery)
        let rotated = try reviewedCSWorker(host: pool[1], target: "https://lb1.strmd.st/live/segment8.image?e=123&st=unchanged")
        XCTAssertNotEqual(try rewrittenCSReference(rotated, policy: &ordinary, delivery: delivery), unprofiledFirst)
        XCTAssertEqual(ordinary.stableSegmentAliasCount, 0)
    }

    func testCSPlaylistAliasesDoNotFlattenChangedInnerSignaturesProvenanceOrUnreviewedShapes() throws {
        let (delivery, headers, profile) = try reviewedCSPlaylistProfile()
        let first = try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment8.ts?e=123&st=unchanged")
        let firstKey = try XCTUnwrap(profile.stableSegmentKey(for: first))
        for changed in [
            try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment8.ts?e=124&st=unchanged"),
            try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment8.ts?e=123&st=changed"),
            try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment9.ts?e=123&st=unchanged"),
            try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment8.ts?e=123&st=unchanged", referer: "https://www.score808live.tv/other")
        ] {
            XCTAssertNotEqual(profile.stableSegmentKey(for: changed), firstKey)
        }
        var duplicate = try XCTUnwrap(URLComponents(url: first, resolvingAgainstBaseURL: false))
        duplicate.queryItems?.append(URLQueryItem(name: "url", value: "https://lb1.strmd.st/forged.ts"))
        var extra = try XCTUnwrap(URLComponents(url: first, resolvingAgainstBaseURL: false))
        extra.queryItems?.append(URLQueryItem(name: "action", value: "other"))
        for unsupported in [
            try reviewedCSWorker(host: "unreviewed.workers.dev", target: "https://lb1.strmd.st/live/segment8.ts?e=123&st=unchanged"),
            try reviewedCSWorker(path: "/other", target: "https://lb1.strmd.st/live/segment8.ts?e=123&st=unchanged"),
            try reviewedCSWorker(target: "https://lb1.strmd.st/live/list.m3u8"),
            try reviewedCSWorker(target: "https://cdn.example.net/live/segment.image"),
            try reviewedCSWorker(target: "https://p17-common-sign.tiktokcdn.com/live/segment.image"),
            try reviewedCSWorker(target: "https://p16-common-sign.tiktokcdn.com.evil.example/live/segment.image"),
            try reviewedCSWorker(target: "https://p16-common-sign.tiktokcdn.com/live/segment.ts"),
            try reviewedCSWorker(target: "https://streamed.pk/live/segment.ts"),
            try reviewedCSWorker(target: "https://127.0.0.1/live/segment.image"),
            try reviewedCSWorker(target: "https://user:private@lb1.strmd.st/live/segment.image"),
            try reviewedCSWorker(target: "https://lb1.strmd.st:8443/live/segment.image"),
            try reviewedCSWorker(target: "http://lb1.strmd.st/live/segment.image"),
            try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment.image#fragment"),
            try XCTUnwrap(duplicate.url), try XCTUnwrap(extra.url)
        ] {
            XCTAssertNil(profile.stableSegmentKey(for: unsupported))
        }
        var scoped = LocalStreamProxyPolicy(selectedMediaURL: delivery, requestHeaders: headers, playlistProfile: profile)
        let old = try rewrittenCSReference(first, policy: &scoped, delivery: delivery)
        let changedToken = try reviewedCSWorker(host: "nuvio-proxy2.rajodedara360.workers.dev",
                                                target: "https://lb1.strmd.st/live/segment8.ts?e=123&st=changed")
        XCTAssertNotEqual(try rewrittenCSReference(changedToken, policy: &scoped, delivery: delivery), old)
        var altered = headers
        altered["User-Agent"] = "changed"
        var unbound = LocalStreamProxyPolicy(selectedMediaURL: delivery, requestHeaders: altered, playlistProfile: profile)
        _ = try rewrittenCSReference(first, policy: &unbound, delivery: delivery)
        XCTAssertEqual(unbound.stableSegmentAliasCount, 0, "A profile cannot migrate to changed captured headers")
    }

    func testReviewedTikTokImageWrapperRotationPreservesAllSignedQueryIdentity() throws {
        let (delivery, headers, profile) = try reviewedCSPlaylistProfile()
        let target = "https://p16-common-sign.tiktokcdn.com/fixture/segment8.image?dr=1&refresh_token=fixture&t=123&ps=fixture&shp=a&shcp=b&idc=us"
        let first = try reviewedCSWorker(target: target)
        let rotated = try reviewedCSWorker(host: "falling-violet-3301.hansabenhodedara.workers.dev", target: target)
        XCTAssertNotNil(profile.stableSegmentKey(for: first))
        XCTAssertEqual(profile.stableSegmentKey(for: first), profile.stableSegmentKey(for: rotated))
        var scoped = LocalStreamProxyPolicy(selectedMediaURL: delivery, requestHeaders: headers, playlistProfile: profile)
        let original = try rewrittenCSReference(first, policy: &scoped, delivery: delivery)
        XCTAssertEqual(try rewrittenCSReference(rotated, policy: &scoped, delivery: delivery), original)
        XCTAssertEqual(scoped.destination(for: original.path), first)
        XCTAssertFalse(scoped.contains(rotated))
        for changed in [target.replacingOccurrences(of: "refresh_token=fixture", with: "refresh_token=renewed"),
                        target.replacingOccurrences(of: "shp=a", with: "shp=changed"),
                        target.replacingOccurrences(of: "segment8.image", with: "segment9.image")] {
            let changedWrapper = try reviewedCSWorker(host: "falling-violet-3301.hansabenhodedara.workers.dev", target: changed)
            XCTAssertNotEqual(profile.stableSegmentKey(for: changedWrapper), profile.stableSegmentKey(for: first))
            XCTAssertNotEqual(try rewrittenCSReference(changedWrapper, policy: &scoped, delivery: delivery), original)
        }
    }

    func testCSPlaylistAliasStorageEvictionRevokeAndAtomicFailureStayBounded() throws {
        let (delivery, headers, profile) = try reviewedCSPlaylistProfile()
        var limits = LocalStreamProxyPolicy.Limits()
        limits.registeredURLs = 3
        var scoped = LocalStreamProxyPolicy(selectedMediaURL: delivery, limits: limits,
                                           requestHeaders: headers, playlistProfile: profile)
        let first = try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment1.image?token=unchanged")
        let firstLocal = try rewrittenCSReference(first, policy: &scoped, delivery: delivery)
        for index in 2..<20 {
            let next = try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment\(index).image?token=unchanged")
            _ = try rewrittenCSReference(next, policy: &scoped, delivery: delivery)
            XCTAssertLessThanOrEqual(scoped.registeredURLCount, 3)
            XCTAssertLessThanOrEqual(scoped.stableSegmentAliasCount, 2)
        }
        XCTAssertNil(scoped.destination(for: firstLocal.path))
        let reintroduced = try rewrittenCSReference(first, policy: &scoped, delivery: delivery)
        XCTAssertNotEqual(reintroduced, firstLocal, "Evicted aliases cannot restore an expired capability route")
        let count = scoped.registeredURLCount
        let aliasCount = scoped.stableSegmentAliasCount
        let next = try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment20.image?token=unchanged")
        XCTAssertThrowsError(try scoped.rewriteManifest("#EXTM3U\n\(next.absoluteString)\nhttps://127.0.0.1/private",
                                                       relativeTo: delivery, port: 8765))
        XCTAssertEqual(scoped.registeredURLCount, count)
        XCTAssertEqual(scoped.stableSegmentAliasCount, aliasCount)
        XCTAssertFalse(scoped.contains(next))
        XCTAssertEqual(scoped.destination(for: reintroduced.path), first)
        scoped.revoke()
        XCTAssertEqual(scoped.registeredURLCount, 0)
        XCTAssertEqual(scoped.stableSegmentAliasCount, 0)
        XCTAssertNil(scoped.destination(for: reintroduced.path))
    }

    func testActualCSRelayPreservesRotatingSegmentURIAndFetchesItsFirstHeaderedDelivery() async throws {
        let (delivery, headers, profile) = try reviewedCSPlaylistProfile()
        let first = try reviewedCSWorker(target: "https://lb1.strmd.st/live/segment8.image?e=123&st=unchanged")
        let rotated = try reviewedCSWorker(host: "nuvio-proxy2.rajodedara360.workers.dev",
                                          target: "https://lb1.strmd.st/live/segment8.image?e=123&st=unchanged")
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.url?.host == "nuviosports.xyz" {
                let reloads = ProxyFixtureProtocol.requests.filter { $0.url?.host == "nuviosports.xyz" }.count
                let reference = reloads == 1 ? first : rotated
                fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\n#EXTINF:6,\n\(reference.absoluteString)".utf8))
            } else {
                fixture.respond(type: "video/mp2t", body: Data("fixture-segment".utf8))
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProxyFixtureProtocol.self]
        let proxy = LocalStreamProxy(headers: headers, cookies: [], selectedMediaURL: delivery,
                                     playlistProfile: profile, configuration: config, resolver: { _ in ["8.8.8.8"] })
        defer { proxy.stop() }
        try await proxy.start()
        let localManifest = try XCTUnwrap(proxy.playbackURL())
        let (manifestA, responseA) = try await URLSession.shared.data(from: localManifest)
        let (manifestB, responseB) = try await URLSession.shared.data(from: localManifest)
        XCTAssertEqual((responseA as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((responseB as? HTTPURLResponse)?.statusCode, 200)
        let lineA = try XCTUnwrap(String(decoding: manifestA, as: UTF8.self).components(separatedBy: "\n").last)
        let lineB = try XCTUnwrap(String(decoding: manifestB, as: UTF8.self).components(separatedBy: "\n").last)
        XCTAssertEqual(lineA, lineB)
        let segment = try XCTUnwrap(URL(string: lineA))
        let (bytes, response) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes, Data("fixture-segment".utf8))
        let request = try XCTUnwrap(ProxyFixtureProtocol.requests.last)
        XCTAssertEqual(request.url, first)
        XCTAssertFalse(ProxyFixtureProtocol.requests.contains { $0.url == rotated })
        for (name, value) in headers { XCTAssertEqual(request.value(forHTTPHeaderField: name), value) }
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(proxy.lastFailureEvidence)
    }

    func testProfiledManifestAdmissionRemainsAtomicAndScopedThroughRedirects() throws {
        let (delivery, headers, profile) = try reviewedCSProfile()
        let target = URL(string: "https://643t8a.7odxv0l067ka.net:8443/live/segment.ts")!
        var scoped = LocalStreamProxyPolicy(selectedMediaURL: delivery, originProfile: profile, requestHeaders: headers)
        let rewritten = try scoped.rewriteManifest("#EXTM3U\n\(target.absoluteString)", relativeTo: delivery, port: 8765)
        let local = try XCTUnwrap(URL(string: rewritten.components(separatedBy: "\n")[1]))
        XCTAssertEqual(scoped.destination(for: local.path), target)
        var ordinary = LocalStreamProxyPolicy(selectedMediaURL: delivery)
        XCTAssertThrowsError(try ordinary.rewriteManifest("#EXTM3U\n\(target.absoluteString)", relativeTo: delivery, port: 8765))
        XCTAssertEqual(ordinary.registeredURLCount, 1)
        let count = scoped.registeredURLCount
        XCTAssertThrowsError(try scoped.rewriteManifest("#EXTM3U\n\(target.absoluteString)\nhttps://other.example.net:8443/a.ts",
                                                       relativeTo: delivery, port: 8765))
        XCTAssertEqual(scoped.registeredURLCount, count)
        try scoped.admitRedirect(from: target, to: URL(string: "https://cdn.example.net/moved.ts")!)
        XCTAssertThrowsError(try scoped.admitRedirect(from: target, to: URL(string: "https://other.example.net:8443/a.ts")!))
        scoped.revoke()
        XCTAssertNil(scoped.destination(for: local.path))
        XCTAssertThrowsError(try scoped.admitRedirect(from: target, to: target))
    }

    func testScoped8443DNSValidationStillRejectsPrivateMixedEmptyAnswers() async throws {
        let (_, _, profile) = try reviewedCSProfile()
        let target = URL(string: "https://643t8a.7odxv0l067ka.net:8443/segment.ts")!
        for addresses in [[], ["127.0.0.1"], ["8.8.8.8", "192.168.1.1"], ["not-an-address"], ["::ffff:127.0.0.1"]] {
            do {
                try await LocalStreamProxyDestinationValidator.validate(target, originProfile: profile, resolver: { _ in addresses })
                XCTFail("Exceptional ports do not bypass public DNS validation")
            } catch { }
        }
        try await LocalStreamProxyDestinationValidator.validate(target, originProfile: profile,
                                                                  resolver: { _ in ["8.8.8.8", "2606:4700:4700::1111"] })
        do {
            try await LocalStreamProxyDestinationValidator.validate(target, resolver: { _ in ["8.8.8.8"] })
            XCTFail("Unprofiled DNS validation must still reject8443")
        } catch { XCTAssertEqual((error as? URLError)?.code, .unsupportedURL) }
    }

    func testActualProfiledRelayRewritesAndFetches8443WithPublicHeadersOnly() async throws {
        let (delivery, headers, profile) = try reviewedCSProfile()
        let target = URL(string: "https://643t8a.7odxv0l067ka.net:8443/live/segment.ts")!
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.url?.host == "nuviosports.xyz" {
                fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\n\(target.absoluteString)".utf8))
            } else { fixture.respond(type: "video/mp2t", body: Data("fixture-segment".utf8)) }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProxyFixtureProtocol.self]
        let cookie = try makeCookie(name: "selected", domain: "nuviosports.xyz")
        let proxy = LocalStreamProxy(headers: headers, cookies: [cookie], selectedMediaURL: delivery,
                                     originProfile: profile, configuration: config, resolver: { _ in ["8.8.8.8"] })
        defer { proxy.stop() }
        try await proxy.start()
        let (manifest, firstResponse) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        XCTAssertEqual((firstResponse as? HTTPURLResponse)?.statusCode, 200)
        let segment = try XCTUnwrap(URL(string: String(decoding: manifest, as: UTF8.self).components(separatedBy: "\n")[1]))
        let (data, response) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, Data("fixture-segment".utf8))
        let request = try XCTUnwrap(ProxyFixtureProtocol.requests.last)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 2)
        XCTAssertEqual(request.url, target)
        for (name, value) in headers { XCTAssertEqual(request.value(forHTTPHeaderField: name), value) }
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(proxy.lastFailureEvidence)
    }

    func testProfiledRelayRevalidatesExceptionalDNSBeforeFetchingSegment() async throws {
        let (delivery, headers, profile) = try reviewedCSProfile()
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "application/vnd.apple.mpegurl",
                            body: Data("#EXTM3U\nhttps://643t8a.7odxv0l067ka.net:8443/segment.ts".utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProxyFixtureProtocol.self]
        let proxy = LocalStreamProxy(headers: headers, cookies: [], selectedMediaURL: delivery,
                                     originProfile: profile, configuration: config, resolver: { host in
            host == "nuviosports.xyz" ? ["8.8.8.8"] : ["8.8.8.8", "192.168.1.1"]
        })
        defer { proxy.stop() }
        try await proxy.start()
        let (manifest, _) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        let segment = try XCTUnwrap(URL(string: String(decoding: manifest, as: UTF8.self).components(separatedBy: "\n")[1]))
        let (_, response) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 502)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1)
        XCTAssertEqual(proxy.lastFailureEvidence?.stage, .destinationValidation)
    }

    func testProfiledRedirectDelegateKeepsExactOriginDNSHeadersAndHopBudget() async throws {
        let (delivery, headers, profile) = try reviewedCSProfile()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProxyFixtureProtocol.self]
        let proxy = LocalStreamProxy(headers: headers, cookies: [], selectedMediaURL: delivery,
                                     originProfile: profile, configuration: config, resolver: { _ in ["8.8.8.8"] })
        defer { proxy.stop() }
        let incoming = LocalStreamProxy.ParsedRequest(method: "GET", path: "/unused", headers: ["range": "bytes=0-99"])
        let delegate = LocalStreamProxy.RedirectDelegate(proxy: proxy, request: incoming, limit: 2)
        let target = URL(string: "https://643t8a.7odxv0l067ka.net:8443/list.m3u8")!
        let accepted = await redirect(delegate, from: delivery, to: target)
        XCTAssertEqual(accepted?.url, target)
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "Range"), "Redirected playlists require a complete representation")
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "Authorization"))
        for (name, value) in headers { XCTAssertEqual(accepted?.value(forHTTPHeaderField: name), value) }
        let rejected = await redirect(delegate, from: target, to: URL(string: "https://other.example.net:8443/a")!)
        XCTAssertNil(rejected)
        let overBudget = await redirect(delegate, from: target, to: URL(string: "https://cdn.example.net/a")!)
        XCTAssertNil(overBudget)
        let mixedDNSProxy = LocalStreamProxy(headers: headers, cookies: [], selectedMediaURL: delivery,
                                             originProfile: profile, configuration: config,
                                             resolver: { _ in ["8.8.8.8", "127.0.0.1"] })
        defer { mixedDNSProxy.stop() }
        let mixedDelegate = LocalStreamProxy.RedirectDelegate(proxy: mixedDNSProxy, request: incoming, limit: 2)
        let mixedRejected = await redirect(mixedDelegate, from: delivery, to: target)
        XCTAssertNil(mixedRejected)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 0)
    }

    func testCSRotatingTokenKeepsSegmentIdentityAndUsesTheFreshCompleteURL() throws {
        let (delivery, headers, _) = try reviewedCSPlaylistProfile()
        let profile = try XCTUnwrap(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery,
            manifestURL: URL(string: "https://nuviosports.xyz/manifest.json")!, sourceHint: "daddylive", headers: headers))
        var policy = LocalStreamProxyPolicy(selectedMediaURL: delivery, requestHeaders: headers, playlistProfile: profile)
        let first = URL(string: "https://cdn.hdm1.net/live/channel/segment101.ts?token=first-token")!
        let fresh = URL(string: "https://cdn.hdm1.net/live/channel/segment101.ts?token=fresh-token")!
        func manifest(_ url: URL) -> String { "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:101\n#EXTINF:6,\n" + url.absoluteString + "\n" }
        func segment(_ text: String) throws -> URL { try XCTUnwrap(text.split(separator: "\n").first { !$0.hasPrefix("#") }.flatMap { URL(string: String($0)) }) }
        let local = try segment(policy.rewriteManifest(manifest(first), relativeTo: delivery, port: 9000))
        XCTAssertEqual(policy.destination(for: local.path), first)
        XCTAssertEqual(try segment(policy.rewriteManifest(manifest(fresh), relativeTo: delivery, port: 9000)), local)
        XCTAssertEqual(policy.destination(for: local.path), fresh, "Forward the full fresh token, never strip or synthesize authorization")
        XCTAssertFalse(policy.contains(first)); XCTAssertTrue(policy.contains(fresh))
        XCTAssertEqual(policy.registeredURLCount, 2)
        XCTAssertThrowsError(try policy.rewriteManifest(manifest(URL(string: "http://cdn.hdm1.net/live/channel/segment101.ts?token=new")!), relativeTo: delivery, port: 9000))
        XCTAssertEqual(policy.destination(for: local.path), fresh, "Rejected manifest cannot mutate an accepted alias")
        policy.revoke(); XCTAssertNil(policy.destination(for: local.path))
    }

    func testCSRotatingTokenCannotAliasOtherHostsPathsTokensKeysOrPlaylists() throws {
        let (delivery, headers, oldProfile) = try reviewedCSPlaylistProfile()
        let profile = try XCTUnwrap(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery,
            manifestURL: URL(string: "https://nuviosports.xyz/manifest.json")!, sourceHint: "daddylive", headers: headers))
        let first = URL(string: "https://cdn.hdm1.net/live/a.ts?token=one")!
        let key = try XCTUnwrap(profile.stableSegmentKey(for: first))
        XCTAssertNil(oldProfile.stableSegmentKey(for: first))
        for raw in ["https://other.example/a.ts?token=one", "http://cdn.hdm1.net/a.ts?token=one",
                    "https://cdn.hdm1.net/a.m3u8?token=one", "https://cdn.hdm1.net/a.ts?token=",
                    "https://cdn.hdm1.net/a.ts?token=one&token=two", "https://cdn.hdm1.net/a.ts?token=one&key=two"] {
            XCTAssertNil(profile.stableSegmentKey(for: URL(string: raw)!))
        }
        XCTAssertNotEqual(profile.stableSegmentKey(for: URL(string: "https://cdn.hdm1.net/live/b.ts?token=one")!), key)
        var policy = LocalStreamProxyPolicy(selectedMediaURL: delivery, requestHeaders: headers, playlistProfile: profile)
        let original = try policy.rewriteManifest("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"" + first.absoluteString + "\"\n", relativeTo: delivery, port: 9000)
        let rotated = try policy.rewriteManifest("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://cdn.hdm1.net/live/a.ts?token=two\"\n", relativeTo: delivery, port: 9000)
        XCTAssertNotEqual(original, rotated, "Key URIs are never segment aliases")
        XCTAssertEqual(policy.stableSegmentAliasCount, 0)
        let child = URL(string: "https://nuviosports.xyz/child.m3u8")!
        _ = try policy.rewriteManifest("#EXTM3U\n" + child.absoluteString, relativeTo: delivery, port: 9000)
        let media = "#EXTM3U\n#EXTINF:6,\n" + first.absoluteString
        XCTAssertNotEqual(try policy.rewriteManifest(media, relativeTo: delivery, port: 9000),
                          try policy.rewriteManifest(media, relativeTo: child, port: 9000), "Separate playlist ownership")
    }

    private func reviewedCSPlaylistProfile() throws -> (URL, [String: String], LocalStreamProxyPlaylistProfile) {
        let manifest = URL(string: "https://nuviosports.xyz/manifest.json")!
        var parts = URLComponents(string: "https://nuviosports.xyz/api/manifest")!
        parts.queryItems = [URLQueryItem(name: "url", value: "https://lb1.strmd.st/live/variant.m3u8?e=123&st=fixture"),
                            URLQueryItem(name: "referer", value: "https://www.score808live.tv/"),
                            URLQueryItem(name: "origin", value: "https://embed.st")]
        let delivery = try XCTUnwrap(parts.url)
        let headers = ["Referer": "https://www.score808live.tv/", "Origin": "https://embed.st", "User-Agent": "Fixture Player"]
        let profile = try XCTUnwrap(LocalStreamProxyPlaylistProfile.communitySports(deliveryURL: delivery,
            manifestURL: manifest, sourceHint: "streamedpk", headers: headers))
        return (delivery, headers, profile)
    }

    private func reviewedCSWorker(host: String = "nuvio-proxy.odedararaj456.workers.dev", path: String = "/",
                                  target: String, referer: String = "https://www.score808live.tv/") throws -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = path
        parts.queryItems = [URLQueryItem(name: "url", value: target), URLQueryItem(name: "referer", value: referer),
                            URLQueryItem(name: "origin", value: "https://embed.st")]
        return try XCTUnwrap(parts.url)
    }

    private func rewrittenCSReference(_ reference: URL, policy: inout LocalStreamProxyPolicy, delivery: URL) throws -> URL {
        let result = try policy.rewriteManifest("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:8\n#EXTINF:6,\n\(reference.absoluteString)",
                                                relativeTo: delivery, port: 8765)
        let line = try XCTUnwrap(result.components(separatedBy: "\n").last)
        return try XCTUnwrap(URL(string: line))
    }

    private func reviewedCSProfile() throws -> (URL, [String: String], LocalStreamProxyOriginProfile) {
        let headers = ["Referer": "https://embed.example/player", "Origin": "https://embed.example",
                       "User-Agent": "Fixture Player"]
        var components = try XCTUnwrap(URLComponents(string: "https://nuviosports.xyz/api/manifest"))
        components.queryItems = [URLQueryItem(name: "url", value: "https://643t8a.7odxv0l067ka.net:8443/live/master.m3u8"),
                                 URLQueryItem(name: "referer", value: headers["Referer"]),
                                 URLQueryItem(name: "origin", value: headers["Origin"])]
        let delivery = try XCTUnwrap(components.url)
        let profile = try XCTUnwrap(LocalStreamProxyOriginProfile.communitySports(
            deliveryURL: delivery, manifestURL: URL(string: "https://nuviosports.xyz/manifest.json")!,
            sourceHint: "daddylive", headers: headers))
        return (delivery, headers, profile)
    }

    func testManifestAdmitsRelativeCDNKeyMapAndRenditionReferences() throws {
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media)
        let manifest = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",URI="//audio.example.net/audio.m3u8"
        #EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin?token=one"
        #EXT-X-MAP:URI="../init.mp4"
        #EXT-X-PART:DURATION=0.333,URI="parts/one.m4s"
        #EXT-X-CONTENT-STEERING:SERVER-URI="https://steering.example.net/path.json"
        #EXTINF:6,
        segment.ts?token=a%2Fb
        https://cdn.example.net/video.m3u8
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let result = try policy.rewriteManifest(manifest, relativeTo: media, port: 8765)
        XCTAssertTrue(result.contains("\r\n"))
        let expression = try NSRegularExpression(pattern: #"http://127\.0\.0\.1:8765/[^"\s]+"#)
        let destinations = try expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).map { match -> URL in
            let range = try XCTUnwrap(Range(match.range, in: result))
            let local = try XCTUnwrap(URL(string: String(result[range])))
            return try XCTUnwrap(policy.destination(for: local.path))
        }
        XCTAssertEqual(Set(destinations.map(\.absoluteString)), Set([
            "https://audio.example.net/audio.m3u8", "https://media.example.com/live/keys/key.bin?token=one",
            "https://media.example.com/init.mp4", "https://media.example.com/live/parts/one.m4s",
            "https://steering.example.net/path.json", "https://media.example.com/live/segment.ts?token=a%2Fb",
            "https://cdn.example.net/video.m3u8"
        ]))
    }

    func testUnsafeManifestAndUnknownParentFailWithoutPartialRegistration() throws {
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media)
        for manifest in ["#EXTM3U\ngood.ts\nhttp://cdn.example.net/insecure.ts",
                         "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"http://127.0.0.1/private\"",
                         "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI='https://cdn.example.net/key'",
                         "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"\"",
                         "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://cdn.example.net/key",
                         "#EXTM3U\n{$unresolved}/segment.ts", "<html>provider error</html>"] {
            XCTAssertThrowsError(try policy.rewriteManifest(manifest, relativeTo: media, port: 8765))
            XCTAssertEqual(policy.registeredURLCount, 1)
        }
        XCTAssertThrowsError(try policy.rewriteManifest("#EXTM3U\nsegment.ts", relativeTo: URL(string: "https://forged.example.net/list.m3u8")!, port: 8765))
    }

    func testManifestMetadataDoesNotCreateDestinationAuthority() throws {
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media)
        let manifest = "#EXTM3U\n#EXT-X-SESSION-DATA:DATA-ID=\"text\",VALUE=\"URI=https://unrelated.example.net/metadata\"\nsegment.ts"
        let result = try policy.rewriteManifest(manifest, relativeTo: media, port: 8765)
        XCTAssertTrue(result.contains("VALUE=\"URI=https://unrelated.example.net/metadata\""))
        XCTAssertFalse(policy.contains(URL(string: "https://unrelated.example.net/metadata")!))
        XCTAssertEqual(policy.registeredURLCount, 2)
    }

    func testRegistrationAndManifestBudgetsRemainBoundedAcrossLiveReloads() throws {
        var limits = LocalStreamProxyPolicy.Limits()
        limits.registeredURLs = 3
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media, limits: limits)
        let rootPath = try XCTUnwrap(policy.playbackURL(port: 8765)).path
        for index in 0..<20 {
            let result = try policy.rewriteManifest("#EXTM3U\n\(index).ts", relativeTo: media, port: 8765)
            let segment = try XCTUnwrap(URL(string: result.components(separatedBy: "\n")[1]))
            XCTAssertNotNil(policy.destination(for: segment.path))
            XCTAssertLessThanOrEqual(policy.registeredURLCount, 3)
            XCTAssertEqual(policy.destination(for: rootPath), media)
        }
        XCTAssertThrowsError(try policy.rewriteManifest("#EXTM3U\na.ts\nb.ts\nc.ts", relativeTo: media, port: 8765))
        XCTAssertLessThanOrEqual(policy.registeredURLCount, 3)
        limits.manifestBytes = 32
        var tiny = LocalStreamProxyPolicy(selectedMediaURL: media, limits: limits)
        XCTAssertThrowsError(try tiny.rewriteManifest("#EXTM3U\n" + String(repeating: "x", count: 33), relativeTo: media, port: 8765))
        XCTAssertThrowsError(try tiny.rewriteManifest("#EXTM3U\na.ts", relativeTo: media, port: 8765), "Rewritten output also has a budget")
    }

    func testLiveManifestOverlapRetainsTheSameAdmittedSegmentURIAndTimingFacts() throws {
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media)
        let first = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:7
        #EXT-X-DISCONTINUITY-SEQUENCE:2
        #EXTINF:6,
        segment7.ts?token=unchanged
        #EXT-X-DISCONTINUITY
        #EXTINF:6,
        segment8.ts?token=unchanged
        """
        let second = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:8
        #EXT-X-DISCONTINUITY-SEQUENCE:2
        #EXT-X-DISCONTINUITY
        #EXTINF:6,
        segment8.ts?token=unchanged
        #EXTINF:6,
        segment9.ts?token=unchanged
        """
        let firstLines = try policy.rewriteManifest(first, relativeTo: media, port: 8765).components(separatedBy: "\n")
        let secondLines = try policy.rewriteManifest(second, relativeTo: media, port: 8765).components(separatedBy: "\n")
        let firstURIs = firstLines.filter { !$0.hasPrefix("#") && !$0.isEmpty }
        let secondURIs = secondLines.filter { !$0.hasPrefix("#") && !$0.isEmpty }
        XCTAssertEqual(firstURIs[1], secondURIs[0], "The relay must not manufacture a URI change for unchanged overlapping media")
        XCTAssertEqual(firstLines.filter { $0.hasPrefix("#") }, first.components(separatedBy: "\n").filter { $0.hasPrefix("#") })
        XCTAssertEqual(secondLines.filter { $0.hasPrefix("#") }, second.components(separatedBy: "\n").filter { $0.hasPrefix("#") })

        let changedCredential = second.replacingOccurrences(of: "segment8.ts?token=unchanged", with: "segment8.ts?token=changed")
        let changedURIs = try policy.rewriteManifest(changedCredential, relativeTo: media, port: 8765)
            .components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        XCTAssertNotEqual(secondURIs[0], changedURIs[0], "Unknown signed delivery changes must not be flattened into an old resource identity")
    }

    func testRedirectRequiresAnAdmittedParentAndUsesFinalManifestBase() throws {
        var policy = LocalStreamProxyPolicy(selectedMediaURL: media)
        let final = URL(string: "https://cdn.example.net/moved/live.m3u8")!
        XCTAssertThrowsError(try policy.admitRedirect(from: URL(string: "https://unknown.example.net/a")!, to: final))
        XCTAssertThrowsError(try policy.admitRedirect(from: media, to: URL(string: "https://127.0.0.1/private")!))
        try policy.admitRedirect(from: media, to: final)
        let result = try policy.rewriteManifest("#EXTM3U\nsegment.ts", relativeTo: final, port: 8765)
        let local = try XCTUnwrap(URL(string: result.components(separatedBy: "\n")[1]))
        XCTAssertEqual(policy.destination(for: local.path)?.absoluteString, "https://cdn.example.net/moved/segment.ts")
    }

    func testCookieDomainPathSecureExpiryAndEncodedPathScope() throws {
        let domainCookie = try makeCookie(name: "session", domain: ".example.com", path: "/live")
        XCTAssertTrue(LocalStreamProxyPolicy.cookie(domainCookie, matches: media))
        XCTAssertTrue(LocalStreamProxyPolicy.cookie(domainCookie, matches: URL(string: "https://cdn.example.com/live/part.ts")!))
        for value in ["https://media.example.com/lively/part.ts", "https://media.example.com/live%2Fpart.ts",
                      "https://media.example.com/other/part.ts", "https://example.com.evil.net/live/a",
                      "https://unrelated.net/live/a", "http://media.example.com/live/a"] {
            XCTAssertFalse(LocalStreamProxyPolicy.cookie(domainCookie, matches: URL(string: value)!), value)
        }
        let hostCookie = try makeCookie(name: "host", domain: "media.example.com")
        XCTAssertTrue(LocalStreamProxyPolicy.cookie(hostCookie, matches: media))
        XCTAssertFalse(LocalStreamProxyPolicy.cookie(hostCookie, matches: URL(string: "https://sub.media.example.com/live/a")!))
        let expired = try makeCookie(name: "expired", domain: ".example.com", expires: Date(timeIntervalSince1970: 1))
        XCTAssertFalse(LocalStreamProxyPolicy.cookie(expired, matches: media))
    }

    func testCredentialsAreScopedWhileCDNProvenanceAndRangeSurvive() throws {
        let headers = ["Authorization": "Bearer selected-secret", "X-API-Key": "custom-secret",
                       "Cookie": "raw=must-not-be-used", "Referer": "https://player.example.org/watch/match?private=token",
                       "Origin": "https://player.example.org", "User-Agent": "Fixture Player",
                       "Host": "forged.example.net", "Proxy-Authorization": "proxy-secret",
                       "X-Fotty-Web-Embed": "true", "X-Unsafe": "line\r\ninjection"]
        let cookies = [try makeCookie(name: "selected", domain: "media.example.com", path: "/live"),
                       try makeCookie(name: "unrelated", domain: "cdn.example.net")]
        func request(_ url: URL) -> URLRequest {
            LocalStreamProxyPolicy.remoteRequest(url: url, selectedMediaURL: media, method: "GET",
                capturedHeaders: headers, cookies: cookies, clientHeaders: ["range": "bytes=0-99", "authorization": "forged"], timeout: 30)
        }
        let selected = request(media)
        XCTAssertEqual(selected.value(forHTTPHeaderField: "Authorization"), "Bearer selected-secret")
        XCTAssertEqual(selected.value(forHTTPHeaderField: "X-API-Key"), "custom-secret")
        XCTAssertEqual(selected.value(forHTTPHeaderField: "Cookie"), "selected=value")
        XCTAssertNil(selected.value(forHTTPHeaderField: "Host"))
        XCTAssertNil(selected.value(forHTTPHeaderField: "Proxy-Authorization"))
        XCTAssertNil(selected.value(forHTTPHeaderField: "X-Fotty-Web-Embed"))
        XCTAssertNil(selected.value(forHTTPHeaderField: "X-Unsafe"))
        XCTAssertNil(selected.value(forHTTPHeaderField: "Range"))
        let cdn = request(URL(string: "https://cdn.example.net/live/part.ts")!)
        XCTAssertNil(cdn.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(cdn.value(forHTTPHeaderField: "X-API-Key"))
        XCTAssertNil(cdn.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(cdn.value(forHTTPHeaderField: "Referer"), "https://player.example.org/watch/match")
        XCTAssertEqual(cdn.value(forHTTPHeaderField: "Origin"), "https://player.example.org")
        XCTAssertEqual(cdn.value(forHTTPHeaderField: "User-Agent"), "Fixture Player")
        XCTAssertEqual(cdn.value(forHTTPHeaderField: "Range"), "bytes=0-99")
        XCTAssertEqual(cdn.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
        XCTAssertFalse(cdn.httpShouldHandleCookies)
    }

    func testParserRejectsAlternateHostsBodiesDuplicateHeadersAndRetargeting() {
        let valid = "GET /cap/media/id HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nRange: bytes=0-99\r\n\r\n"
        XCTAssertEqual(LocalStreamProxy.parseRequest(Data(valid.utf8), port: 8765)?.headers["range"], "bytes=0-99")
        for value in [valid.replacingOccurrences(of: "127.0.0.1:8765", with: "attacker.example.net"),
                      valid.replacingOccurrences(of: "Range:", with: "Host:"),
                      valid.replacingOccurrences(of: "/cap/media/id", with: "/proxy?url=https://media.example.com/a"),
                      valid.replacingOccurrences(of: "/cap/media/id", with: "http://127.0.0.1:8765/cap/media/id"),
                      valid.replacingOccurrences(of: "/cap/media/id", with: "/%63ap/media/id"),
                      valid.replacingOccurrences(of: "Range: bytes=0-99", with: "Transfer-Encoding: chunked"),
                      valid + "body", "GET /cap/media/id HTTP/1.1\r\n\r\n"] {
            XCTAssertNil(LocalStreamProxy.parseRequest(Data(value.utf8), port: 8765), value)
        }
    }

    func testActualListenerRejectsForgedRoutesBeforeUpstreamWork() async throws {
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let healthy = await proxy.ping()
        XCTAssertTrue(healthy)
        let port = try XCTUnwrap(proxy.port)
        for path in ["/ping", "/forged/media/resource", "/proxy?url=https://unrelated.example.net/private"] {
            let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            XCTAssertTrue([400, 404].contains((response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 0)
    }

    func testActualRelayRewritesManifestAndFetchesOnlyItsRegisteredCDNResource() async throws {
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.url?.host == "media.example.com" {
                fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\nhttps://cdn.example.net/segment.ts".utf8))
            } else {
                fixture.respond(type: "video/mp2t", body: Data([1, 2, 3, 4]))
            }
        }
        let proxy = makeProxy(headers: ["Authorization": "secret", "User-Agent": "Fixture"])
        defer { proxy.stop() }
        try await proxy.start()
        let (manifest, response) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let segment = try XCTUnwrap(URL(string: String(decoding: manifest, as: UTF8.self).components(separatedBy: "\n")[1]))
        let (data, _) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual(data, Data([1, 2, 3, 4]))
        let requests = ProxyFixtureProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "secret")
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "User-Agent"), "Fixture")
    }

    // The playback lab composes the real native validator, local listener and
    // relay rather than checking each policy in isolation. HTTPS terminates in
    // ProxyFixtureProtocol; only the capability's loopback socket is opened.
    // These tests prove transport/ownership contracts, never decoded playback.
    func testPlaybackLabHeldManifestCompletesRealValidationWithoutInventingStartupFailure() async throws {
        let began = expectation(description: "Manifest waits for controlled upstream release")
        let gate = ProxyFixtureGate()
        ProxyFixtureProtocol.configure { fixture in
            gate.hold(fixture)
            began.fulfill()
        }
        let proxy = makeProxy(headers: ["Authorization": "synthetic-owner-only"])
        defer { proxy.stop() }
        try await proxy.start()
        let localURL = try XCTUnwrap(proxy.playbackURL())
        let validation = Task { await StreamContractValidator(deadline: 3).validate(localURL, headers: [:]) }
        defer { validation.cancel() }
        await fulfillment(of: [began], timeout: 2)

        XCTAssertEqual(gate.pendingCount, 1)
        XCTAssertEqual(proxy.activeConnectionCount, 1)
        XCTAssertNil(proxy.lastFailureEvidence, "An unfinished request is not a provider failure")
        let pending = proxy.requestEvidenceSnapshot()
        XCTAssertEqual(pending.requests.count, 1)
        XCTAssertEqual(pending.requests.first?.outcome, .inFlight)
        XCTAssertEqual(pending.requests.first?.categoryBasis, .pathHint)
        XCTAssertEqual(pending.requests.first?.method, .get)
        XCTAssertNil(ProxyFixtureProtocol.requests.first?.value(forHTTPHeaderField: "Range"), "Validation probes still fetch a complete known playlist")
        gate.release(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts\n".utf8))

        let result = await validation.value
        XCTAssertTrue(result.isValid, "The same held request should validate when its manifest arrives")
        XCTAssertEqual(proxy.playbackURL(), localURL)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1, "Slow preparation must not create another request or capability")
        XCTAssertNil(proxy.lastFailureEvidence)
        XCTAssertEqual(proxy.requestEvidenceSnapshot().requests.first?.outcome, .completed)
    }

    func testPlaybackLabActualRelayHTTPFailuresRemainTypedAtNativeValidationBoundary() async throws {
        for status in [401, 403, 404, 503] {
            ProxyFixtureProtocol.configure { fixture in
                fixture.respond(type: "text/plain", body: Data("synthetic private upstream body".utf8), status: status)
            }
            let proxy = makeProxy()
            defer { proxy.stop() }
            try await proxy.start()
            let result = await StreamContractValidator(deadline: 2)
                .validate(try XCTUnwrap(proxy.playbackURL()), headers: [:])
            guard case .invalid(let reason, let receipt) = result else {
                return XCTFail("An upstream HTTP \(status) must not become a playable manifest")
            }
            XCTAssertEqual(reason, "HTTP \(status)")
            XCTAssertEqual(receipt?.qualityDetails["preparation_http_status"], String(status))
            XCTAssertEqual(proxy.lastFailureEvidence?.statusCode, status)
            XCTAssertEqual(proxy.lastFailureEvidence?.stage, .upstreamResponse)
            let snapshot = proxy.requestEvidenceSnapshot()
            let observed = try XCTUnwrap(snapshot.requests.first)
            XCTAssertEqual(observed.outcome, .failed)
            XCTAssertEqual(observed.httpStatus, status)
            XCTAssertEqual(proxy.lastFailureEvidence?.relayID, snapshot.relayID)
            XCTAssertEqual(proxy.lastFailureEvidence?.requestID, observed.requestID)
            XCTAssertEqual(proxy.lastFailureEvidence?.resourceID, observed.resourceID)
            XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1)
            XCTAssertFalse(receipt?.qualityDetails.description.contains("example.com") ?? true)
            XCTAssertFalse(receipt?.qualityDetails.description.contains("private") ?? true)
            proxy.stop()
        }
    }

    func testPlaybackLabValidManifestDoesNotProveSegmentPlaybackAndSameCapabilityCanRecover() async throws {
        let deliveries = ProxyFixtureDeliverySequence()
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.url?.host == "media.example.com" {
                fixture.respond(type: "application/vnd.apple.mpegurl",
                    body: Data("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nhttps://cdn.example.net/segment.ts?synthetic=retained\n".utf8))
            } else if deliveries.next() == 1 {
                fixture.respond(type: "text/plain", body: Data("expired synthetic delivery".utf8), status: 403)
            } else {
                fixture.respond(type: "video/mp2t", body: Data([0x47, 1, 2, 3]))
            }
        }
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let localURL = try XCTUnwrap(proxy.playbackURL())
        let validation = await StreamContractValidator(deadline: 2).validate(localURL, headers: [:])
        XCTAssertTrue(validation.isValid, "The controlled manifest must pass prefix validation")
        let (manifest, _) = try await URLSession.shared.data(from: localURL)
        let segment = try XCTUnwrap(String(decoding: manifest, as: UTF8.self)
            .components(separatedBy: "\n").first { $0.hasPrefix("http://127.0.0.1:") }.flatMap(URL.init(string:)))
        let (_, expired) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual((expired as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertEqual(proxy.lastFailureEvidence?.statusCode, 403)

        let (recovered, response) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(recovered, Data([0x47, 1, 2, 3]))
        XCTAssertEqual(proxy.playbackURL(), localURL)
        let segmentRequests = ProxyFixtureProtocol.requests.filter { $0.url?.host == "cdn.example.net" }
        XCTAssertEqual(segmentRequests.count, 2)
        XCTAssertEqual(segmentRequests.first?.url, segmentRequests.last?.url,
            "A transient failure must not silently change the signed resource or relay owner")
        let snapshot = proxy.requestEvidenceSnapshot()
        let failed = try XCTUnwrap(snapshot.requests.first { $0.outcome == .failed })
        let retried = try XCTUnwrap(snapshot.requests.last { $0.resourceID == failed.resourceID && $0.outcome == .completed })
        XCTAssertNotEqual(failed.requestID, retried.requestID)
        XCTAssertEqual(failed.resourceID, retried.resourceID)
        XCTAssertEqual(snapshot.qualityDetails()["relay_same_resource_later_completed"], "true")
        XCTAssertEqual(proxy.lastFailureEvidence?.requestID, failed.requestID,
            "Later success does not erase historical failure or claim that it caused a decoder event")
    }

    func testPlaybackLabRangedSegmentPreservesResponseAndDoesNotInheritManifestCredentials() async throws {
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.url?.host == "media.example.com" {
                fixture.respond(type: "application/vnd.apple.mpegurl",
                    body: Data("#EXTM3U\n#EXTINF:6,\nhttps://cdn.example.net/segment.ts\n".utf8))
            } else {
                fixture.respond(type: "video/mp2t", body: Data([2, 3, 4, 5]), status: 206,
                    headers: ["Content-Range": "bytes 2-5/8", "Accept-Ranges": "bytes"])
            }
        }
        let proxy = makeProxy(headers: ["Authorization": "synthetic-owner-only", "User-Agent": "Fixture"])
        defer { proxy.stop() }
        try await proxy.start()
        let (manifest, _) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        let segment = try XCTUnwrap(String(decoding: manifest, as: UTF8.self)
            .components(separatedBy: "\n").first { $0.hasPrefix("http://127.0.0.1:") }.flatMap(URL.init(string:)))
        var request = URLRequest(url: segment)
        request.setValue("bytes=2-5", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 2-5/8")
        XCTAssertEqual(data, Data([2, 3, 4, 5]))
        XCTAssertEqual(ProxyFixtureProtocol.requests.last?.value(forHTTPHeaderField: "Range"), "bytes=2-5")
        XCTAssertNil(ProxyFixtureProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(ProxyFixtureProtocol.requests.last?.value(forHTTPHeaderField: "User-Agent"), "Fixture")
    }

    func testKnownManifestDropsCapturedAndClientRepresentationConditionsButMediaRangesSurvive() {
        let conditions = ["RaNgE": "bytes=9-19", "If-Range": "upstream-tag", "If-None-Match": "upstream-tag",
                          "If-Modified-Since": "Wed, 21 Oct 2026 07:28:00 GMT", "If-Match": "other-tag",
                          "If-Unmodified-Since": "Wed, 21 Oct 2026 07:28:00 GMT"]
        let client = ["range": "bytes=0-1", "if-range": "client-tag", "if-none-match": "client-tag",
                      "if-modified-since": "Wed, 21 Oct 2026 07:28:00 GMT"]
        for url in [media, URL(string: "https://media.example.com/live/MASTER.M3U8?token=fixture")!] {
            let request = LocalStreamProxyPolicy.remoteRequest(url: url, selectedMediaURL: media, method: "GET",
                capturedHeaders: conditions, cookies: [], clientHeaders: client, timeout: 30)
            for key in conditions.keys { XCTAssertNil(request.value(forHTTPHeaderField: key), key) }
        }
        let segment = URL(string: "https://media.example.com/live/segment.ts")!
        let request = LocalStreamProxyPolicy.remoteRequest(url: segment, selectedMediaURL: media, method: "GET",
            capturedHeaders: conditions, cookies: [], clientHeaders: client, timeout: 30)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "client-tag")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "other-tag")
    }

    func testPlaybackLabManifestByteProbeFetchesOneWholeRewrittenRepresentation() async throws {
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.value(forHTTPHeaderField: "Range") != nil {
                fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#E".utf8), status: 206,
                    headers: ["Content-Range": "bytes 0-1/100"])
            } else {
                fixture.respond(type: "application/vnd.apple.mpegurl",
                    body: Data("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts\n".utf8),
                    headers: ["ETag": "upstream-tag", "Last-Modified": "Wed, 21 Oct 2026 07:28:00 GMT", "Accept-Ranges": "bytes"])
            }
        }
        let proxy = makeProxy(headers: ["Range": "bytes=5-9", "If-Range": "captured-tag", "If-None-Match": "captured-tag"])
        defer { proxy.stop() }; try await proxy.start()
        var request = URLRequest(url: try XCTUnwrap(proxy.playbackURL()))
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue("client-tag", forHTTPHeaderField: "If-Range")
        request.setValue("client-tag", forHTTPHeaderField: "If-None-Match")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("#EXTM3U"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("http://127.0.0.1:"))
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), String(data.count))
        for field in ["Content-Range", "ETag", "Last-Modified", "Accept-Ranges"] {
            XCTAssertNil(http.value(forHTTPHeaderField: field))
        }
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1, "No retry or hidden MIME refetch")
        XCTAssertNil(ProxyFixtureProtocol.requests.first?.value(forHTTPHeaderField: "Range"))
        XCTAssertNil(ProxyFixtureProtocol.requests.first?.value(forHTTPHeaderField: "If-Range"))
        XCTAssertNil(ProxyFixtureProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(proxy.lastFailureEvidence)
    }

    func testPartialConditionalAndMIMEOnlyPartialPlaylistsFailClosedWithoutNormalizationOrRetry() async throws {
        let cases: [(URL, Int, [String: String])] = [
            (media, 206, ["Content-Range": "bytes 0-1/100"]),
            (media, 206, [:]), (media, 200, ["Content-Range": "bytes 0-99/100"]), (media, 304, [:]),
            (URL(string: "https://media.example.com/live/unknown")!, 206, ["Content-Range": "bytes 0-1/100"])
        ]
        for (url, status, fields) in cases {
            ProxyFixtureProtocol.configure { fixture in
                fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\nsegment.ts\n".utf8),
                                status: status, headers: fields)
            }
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ProxyFixtureProtocol.self]
            let proxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: url,
                configuration: configuration, resolver: { _ in ["8.8.8.8"] })
            defer { proxy.stop() }; try await proxy.start()
            let (_, response) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 502)
            XCTAssertEqual(proxy.lastFailureEvidence?.stage, .manifest)
            XCTAssertEqual(proxy.lastFailureEvidence?.kind, .invalidManifest)
            XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1)
        }
    }

    func testKnownManifestHEADDoesNotExposeUpstreamRepresentationLengthOrValidators() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "application/vnd.apple.mpegurl", body: Data(),
                headers: ["Content-Length": "721", "ETag": "upstream-tag", "Last-Modified": "Wed, 21 Oct 2026 07:28:00 GMT", "Accept-Ranges": "bytes"])
        }
        let proxy = makeProxy(); defer { proxy.stop() }; try await proxy.start()
        var request = URLRequest(url: try XCTUnwrap(proxy.playbackURL())); request.httpMethod = "HEAD"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200); XCTAssertTrue(data.isEmpty)
        for field in ["Content-Length", "Content-Range", "ETag", "Last-Modified", "Accept-Ranges"] {
            XCTAssertNil(http.value(forHTTPHeaderField: field))
        }
        XCTAssertNil(ProxyFixtureProtocol.requests.first?.value(forHTTPHeaderField: "Range"))
    }

    func testPlaybackLabCancelledValidationAndStoppedRelayCannotReviveHeldRequest() async throws {
        let began = expectation(description: "Controlled native validation began")
        let stopped = expectation(description: "Owned upstream cancelled")
        let gate = ProxyFixtureGate()
        ProxyFixtureProtocol.configure(onStop: { stopped.fulfill() }) { fixture in
            gate.hold(fixture)
            began.fulfill()
        }
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let localURL = try XCTUnwrap(proxy.playbackURL())
        let validation = Task { await StreamContractValidator(deadline: 3).validate(localURL, headers: [:]) }
        await fulfillment(of: [began], timeout: 2)
        validation.cancel()
        let result = await validation.value
        guard case .invalid(_, let receipt) = result else { return XCTFail("Cancellation cannot publish a valid stream") }
        XCTAssertEqual(receipt?.qualityDetails["preparation_reason"], "cancelled")
        proxy.stop()
        await fulfillment(of: [stopped], timeout: 2)
        gate.release(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\nsegment.ts\n".utf8))
        XCTAssertNil(proxy.playbackURL())
        XCTAssertEqual(proxy.activeConnectionCount, 0)
        XCTAssertNil(proxy.lastFailureEvidence, "Owner cancellation must not be labelled as provider rejection")
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1)
        XCTAssertEqual(proxy.requestEvidenceSnapshot().requests.first?.outcome, .cancelled)
    }

    func testRelayRequestEvidenceIsBoundedOpaqueAndDoesNotWriteTheQualityStorePerRequest() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "text/plain", body: Data("synthetic private body".utf8), status: 503)
        }
        let proxy = makeProxy(headers: ["Authorization": "synthetic-private-header"])
        defer { proxy.stop() }
        try await proxy.start()
        let localURL = try XCTUnwrap(proxy.playbackURL())
        for _ in 0..<40 {
            let (_, response) = try await URLSession.shared.data(from: localURL)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
        }
        let snapshot = proxy.requestEvidenceSnapshot()
        XCTAssertEqual(snapshot.requests.count, 32)
        XCTAssertEqual(snapshot.evictedCount, 8)
        XCTAssertEqual(Set(snapshot.requests.map(\.requestID)).count, 32)
        XCTAssertEqual(Set(snapshot.requests.map(\.resourceID)).count, 1)
        XCTAssertTrue(snapshot.requests.allSatisfy { $0.relayID == snapshot.relayID && $0.outcome == .failed })
        XCTAssertEqual(snapshot.qualityDetails()["relay_retained_failed_count"], "32")
        XCTAssertTrue(FottyQualityStore.shared.records().filter { $0.details["relay_id"] == snapshot.relayID.uuidString }.isEmpty,
            "Only the owned item/preflight snapshot is persisted; requests do not flood the global quality ring")
        let exported = snapshot.qualityDetails().description
        for forbidden in ["example.com", "synthetic-private-header", "synthetic private body", localURL.pathComponents[1], "http://", "https://"] {
            XCTAssertFalse(exported.contains(forbidden))
        }
    }

    func testConcurrentRelayFailureAndOtherResourceCompletionStaySeparateObservations() async throws {
        let began = expectation(description: "Both admitted resources began")
        began.expectedFulfillmentCount = 2
        let success = ProxyFixtureGate(), failure = ProxyFixtureGate()
        ProxyFixtureProtocol.configure { fixture in
            if fixture.request.url?.host == "media.example.com" {
                fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\nhttps://cdn.example.net/first.ts\nhttps://cdn.example.net/second.ts\n".utf8))
            } else {
                if fixture.request.url?.lastPathComponent == "first.ts" { success.hold(fixture) }
                else { failure.hold(fixture) }
                began.fulfill()
            }
        }
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let (manifest, _) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        let urls = String(decoding: manifest, as: UTF8.self).components(separatedBy: "\n")
            .filter { $0.hasPrefix("http://127.0.0.1:") }.compactMap(URL.init(string:))
        guard urls.count == 2 else { return XCTFail("Both admitted controlled resource routes are required") }
        let first = Task { try await URLSession.shared.data(from: urls[0]) }
        let second = Task { try await URLSession.shared.data(from: urls[1]) }
        defer { first.cancel(); second.cancel() }
        await fulfillment(of: [began], timeout: 2)
        XCTAssertEqual(proxy.requestEvidenceSnapshot().requests.filter { $0.outcome == .inFlight }.count, 2)
        failure.release(type: "text/plain", body: Data(), status: 503)
        let (_, failedResponse) = try await second.value
        XCTAssertEqual((failedResponse as? HTTPURLResponse)?.statusCode, 503)
        let heldDetails = proxy.diagnosticDetails()
        XCTAssertEqual(heldDetails["relay_retained_failed_count"], "1")
        XCTAssertEqual(heldDetails["relay_retained_in_flight_count"], "1")
        XCTAssertEqual(heldDetails["relay_request_id"], heldDetails["relay_failure_request_id"],
            "The atomically captured latest failure and request window share their actual request")
        success.release(type: "video/mp2t", body: Data([0x47, 0, 1]))
        _ = try await first.value

        let snapshot = proxy.requestEvidenceSnapshot()
        let failed = try XCTUnwrap(snapshot.requests.first { $0.outcome == .failed })
        let completed = try XCTUnwrap(snapshot.requests.last { $0.outcome == .completed && $0.resourceCategory == .media })
        XCTAssertNotEqual(failed.requestID, completed.requestID)
        XCTAssertNotEqual(failed.resourceID, completed.resourceID)
        XCTAssertEqual(proxy.lastFailureEvidence?.requestID, failed.requestID)
        XCTAssertEqual(snapshot.qualityDetails()["relay_same_resource_later_completed"], "false")
        XCTAssertEqual(snapshot.qualityDetails()["relay_request_outcome"], "completed")
        let details = proxy.diagnosticDetails()
        XCTAssertEqual(details["relay_request_id"], completed.requestID.uuidString)
        XCTAssertEqual(details["relay_failure_request_id"], failed.requestID.uuidString)
        XCTAssertNotEqual(details["relay_request_id"], details["relay_failure_request_id"])
    }

    func testRelayResourceIdentityIsPerRelayAndNeverTheCapability() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\n".utf8))
        }
        let first = makeProxy(), second = makeProxy()
        defer { first.stop(); second.stop() }
        try await first.start(); try await second.start()
        let firstURL = try XCTUnwrap(first.playbackURL()), secondURL = try XCTUnwrap(second.playbackURL())
        _ = try await URLSession.shared.data(from: firstURL)
        _ = try await URLSession.shared.data(from: secondURL)
        let a = first.requestEvidenceSnapshot(), b = second.requestEvidenceSnapshot()
        XCTAssertNotEqual(a.relayID, b.relayID)
        XCTAssertNotEqual(a.requests.first?.resourceID, b.requests.first?.resourceID)
        XCTAssertNotEqual(a.requests.first?.requestID, b.requests.first?.requestID)
        XCTAssertFalse(a.qualityDetails().description.contains(firstURL.pathComponents[1]))
        XCTAssertNil(LocalStreamProxyRequestReceipt.resourceIdentifier(for: "/not-a-route"))
        XCTAssertNil(LocalStreamProxyRequestReceipt.resourceIdentifier(for: "/" + String(repeating: "z", count: 32)))
    }

    func testRelaySnapshotInvalidMonotonicSamplesStayUnknownAndSummaryRemainsBounded() {
        let relay = UUID(), resource = UUID()
        let receipts = (0..<40).map { _ in LocalStreamProxyRequestReceipt(relayID: relay, requestID: UUID(),
            resourceID: resource, method: .get, resourceCategory: .unknown, categoryBasis: .unknown, startedAt: 100) }
        let snapshot = LocalStreamProxyRequestSnapshot(relayID: relay, requests: receipts, evictedCount: Int.max, observedAt: .nan)
        let details = snapshot.qualityDetails()
        XCTAssertEqual(details["relay_retained_request_count"], "32")
        XCTAssertEqual(details["relay_evicted_request_count"], "1000000")
        XCTAssertNil(details["relay_request_age_ms"])
        XCTAssertEqual(details["relay_request_elapsed_ms"], "0")
        XCTAssertFalse(details.description.contains("nan"))
        XCTAssertNil(LocalStreamProxyRequestSnapshot(relayID: relay, requests: receipts,
            evictedCount: 0, observedAt: 99).qualityDetails()["relay_request_age_ms"])
    }

    func testActualRelayRejectsOversizeManifestWithUnknownLength() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "application/vnd.apple.mpegurl", body: Data(("#EXTM3U\n" + String(repeating: "x", count: 100)).utf8))
        }
        var limits = LocalStreamProxyPolicy.Limits()
        limits.manifestBytes = 32
        let proxy = makeProxy(limits: limits)
        defer { proxy.stop() }
        try await proxy.start()
        let (_, response) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 502)
        XCTAssertEqual(proxy.lastFailureEvidence?.stage, .manifest)
        XCTAssertEqual(proxy.lastFailureEvidence?.kind, .responseTooLarge)
    }

    func testRelayRecordsRealHTTPFailureSeparatelyFromNativePlatformErrors() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "text/plain", body: Data("private upstream body".utf8), status: 503)
        }
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let (_, response) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
        let evidence = try XCTUnwrap(proxy.lastFailureEvidence)
        XCTAssertEqual(evidence.stage, .upstreamResponse)
        XCTAssertEqual(evidence.kind, .httpStatus)
        XCTAssertEqual(evidence.qualityDetails()["relay_http_status"], "503")
        XCTAssertFalse(evidence.qualityDetails().description.contains("private"))
        XCTAssertFalse(evidence.qualityDetails().description.contains("example.com"))
    }

    func testRelayRecordsRejectedManifestWithoutChangingFailClosedAdmission() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "application/vnd.apple.mpegurl", body: Data("#EXTM3U\nhttp://127.0.0.1/private".utf8))
        }
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let (_, response) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 502)
        XCTAssertEqual(proxy.lastFailureEvidence?.stage, .manifest)
        XCTAssertEqual(proxy.lastFailureEvidence?.kind, .destinationDenied)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1)
    }

    func testQueuedDeadlineWithoutConnectionOwnershipCannotOverwriteFailureEvidence() async throws {
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "text/plain", body: Data(), status: 503)
        }
        let proxy = makeProxy()
        defer { proxy.stop() }
        try await proxy.start()
        let (_, response) = try await URLSession.shared.data(from: XCTUnwrap(proxy.playbackURL()))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
        let drained = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in proxy.activeConnectionCount == 0 }, object: nil)
        await fulfillment(of: [drained], timeout: 2)
        let acceptedEvidence = try XCTUnwrap(proxy.lastFailureEvidence)

        // Reproduce a deadline callback after its connection was removed. The
        // socket is never started: an absent owner must be a deterministic no-op.
        let staleConnection = NWConnection(host: .ipv4(.loopback), port: .http, using: .tcp)
        proxy.expireResourceConnection(ObjectIdentifier(staleConnection))
        XCTAssertEqual(proxy.lastFailureEvidence, acceptedEvidence)
        XCTAssertEqual(proxy.activeConnectionCount, 0)

        proxy.stop()
        proxy.expireResourceConnection(ObjectIdentifier(staleConnection))
        XCTAssertEqual(proxy.lastFailureEvidence, acceptedEvidence)
    }

    func testNativeDiagnosticPreservesNotificationErrorChainButNoPrivateText() throws {
        let network = NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "secret https://provider.example/private", "owner": "private owner"])
        let media = NSError(domain: "CoreMediaErrorDomain", code: -12_966, userInfo: [NSUnderlyingErrorKey: network])
        let item = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.noLongerPlayable.rawValue,
                           userInfo: [NSUnderlyingErrorKey: media])
        let snapshot = PlayerDiagnosticService().snapshot(error: item, trigger: .failedToPlayToEnd)
        XCTAssertEqual(snapshot.qualityDetails["native_failure_trigger"], "failed_to_play_to_end")
        XCTAssertEqual(snapshot.qualityDetails["native_error_domain"], "avfoundation")
        XCTAssertEqual(snapshot.qualityDetails["native_underlying_domain"], "url")
        XCTAssertEqual(snapshot.qualityDetails["native_underlying_code"], "-1005")
        XCTAssertEqual(snapshot.qualityDetails["native_error_depth"], "3")
        XCTAssertNil(snapshot.statusCode)
        XCTAssertFalse(snapshot.qualityDetails.description.contains("secret"))
        XCTAssertFalse(snapshot.failureReason.contains("provider.example"))
    }

    func testNativeDiagnosticCannotMislabelCoreMediaNumericCodeAsHTTPStatus() {
        let service = PlayerDiagnosticService()
        for domain in ["CoreMediaErrorDomain", NSOSStatusErrorDomain, "private-owner-domain"] {
            let snapshot = service.snapshot(error: nil, trigger: .errorLog, logDomain: domain, logCode: 404)
            XCTAssertNil(snapshot.statusCode)
            XCTAssertFalse(snapshot.failureReason.contains("HTTP"))
            XCTAssertFalse(snapshot.qualityDetails.description.contains("private-owner"))
        }
        XCTAssertEqual(service.snapshot(error: nil, trigger: .errorLog,
                                        logDomain: "HTTP", logCode: 404).statusCode, 404)
    }

    func testNativeHLSConsistencyReceiptRequiresAnObservedTypedMessage() {
        let service = PlayerDiagnosticService()
        let cases: [(String, NativeHLSPlaylistIssue)] = [
            ("Media Entry URL not match previous playlist for MEDIA-SEQUENCE 8: https://private.example/old?token=one vs https://private.example/new?token=two", .segmentURIChanged),
            ("Media Entry time value does not match previous playlist for MEDIA-SEQUENCE 8: 6.000000 vs 8.000000", .segmentDurationChanged),
            ("Media Entry discontinuity value does not match previous playlist for MEDIA-SEQUENCE 8: 0 vs 1", .segmentDiscontinuityChanged)
        ]
        for (comment, issue) in cases {
            let error = NSError(domain: "CoreMediaErrorDomain", code: -12_312,
                                userInfo: ["NSDescription": comment])
            let snapshot = service.snapshot(error: error, trigger: .failedToPlayToEnd)
            XCTAssertEqual(snapshot.qualityDetails["native_hls_issue"], issue.rawValue)
            XCTAssertNil(snapshot.qualityDetails["native_log_hls_issue"])
            XCTAssertEqual(snapshot.failureReason, "Player item failed: coremedia -12312")
            for privateValue in ["private.example", "token=", "MEDIA-SEQUENCE", "6.000000"] {
                XCTAssertFalse(snapshot.qualityDetails.description.contains(privateValue))
                XCTAssertFalse(snapshot.failureReason.contains(privateValue))
            }
        }
        let numericOnly = service.snapshot(error: NSError(domain: "CoreMediaErrorDomain", code: -12_312),
                                           trigger: .failedToPlayToEnd,
                                           logDomain: "CoreMediaErrorDomain", logCode: -12_312)
        XCTAssertNil(numericOnly.qualityDetails["native_hls_issue"])
        XCTAssertNil(numericOnly.qualityDetails["native_log_hls_issue"], "The code alone does not establish a playlist conflict")
    }

    func testNativeHLSCommentEvidenceDoesNotOverrideTheActualFatalError() {
        let service = PlayerDiagnosticService()
        let fatal = NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "secret account https://private.example/fatal"])
        let comment = "Media Entry URL not match previous playlist for MEDIA-SEQUENCE 9: https://private.example/a?token=one vs https://private.example/b?token=two"
        let snapshot = service.snapshot(error: fatal, trigger: .failedToPlayToEnd,
                                        logDomain: "CoreMediaErrorDomain", logCode: -12_312, logComment: comment)
        XCTAssertEqual(snapshot.failureReason, "Player item failed: url -1005")
        XCTAssertNil(snapshot.qualityDetails["native_hls_issue"])
        XCTAssertEqual(snapshot.qualityDetails["native_log_hls_issue"], "segment_uri_changed")
        XCTAssertFalse(snapshot.qualityDetails.description.contains("private.example"))
        XCTAssertFalse(snapshot.qualityDetails.description.contains("token"))
        XCTAssertFalse(snapshot.qualityDetails.description.contains("secret"))

        let underlying = NSError(domain: "CoreMediaErrorDomain", code: -12_312,
                                 userInfo: [NSLocalizedFailureReasonErrorKey: comment])
        let outer = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.noLongerPlayable.rawValue,
                            userInfo: [NSUnderlyingErrorKey: underlying])
        let chain = service.snapshot(error: outer, trigger: .itemStatusFailed,
            logDomain: "CoreMediaErrorDomain", logCode: -12_312,
            logComment: "Media Entry time value does not match previous playlist for MEDIA-SEQUENCE 3: 6 vs 8")
        XCTAssertEqual(chain.qualityDetails["native_hls_issue"], "segment_uri_changed")
        XCTAssertEqual(chain.qualityDetails["native_log_hls_issue"], "segment_duration_changed")
        XCTAssertEqual(chain.qualityDetails["native_error_domain"], "avfoundation")
        XCTAssertEqual(chain.qualityDetails["native_underlying_domain"], "coremedia")
    }

    func testNativeHLSMessageAdmissionIsPrefixBoundedAndFailClosed() {
        let known = "Media Entry URL not match previous playlist for MEDIA-SEQUENCE 5: "
        for unrecognized in ["provider says \(known)", "\(String(repeating: " ", count: 513))\(known)",
                             "Media Entry URL not match previous playlist for MEDIA-SEQUENCES 5: ",
                             "Media Entry URL not match previous playlist", "translated message", ""] {
            XCTAssertNil(NativeHLSPlaylistIssue.observed(in: unrecognized, domain: .coreMedia))
        }
        for domain in [NativePlaybackErrorDomain.url, .avFoundation, .osStatus, .http, .other] {
            XCTAssertNil(NativeHLSPlaylistIssue.observed(in: known, domain: domain))
        }
        let largePrivateTail = known + String(repeating: "https://private.example/?secret=owner ", count: 1_000)
        let snapshot = PlayerDiagnosticService().snapshot(error: nil, trigger: .errorLog,
            logDomain: "CoreMediaErrorDomain", logCode: -12_312, logComment: largePrivateTail)
        XCTAssertEqual(snapshot.qualityDetails["native_log_hls_issue"], "segment_uri_changed")
        XCTAssertNil(snapshot.qualityDetails["native_hls_issue"])
        XCTAssertFalse(snapshot.qualityDetails.description.contains("owner"))
        XCTAssertFalse(snapshot.qualityDetails.description.contains("https://"))
        XCTAssertNil(NativeHLSPlaylistIssue.observed(in: nil, domain: .coreMedia))
    }

    func testReportedFatalErrorOutranksEarlierRecoverableHTTPLogWithoutErasingLogEvidence() {
        let service = PlayerDiagnosticService()
        let fatal = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.mediaServicesWereReset.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "private https://provider.example/owner"])
        let snapshot = service.snapshot(error: fatal, trigger: .failedToPlayToEnd,
                                        logDomain: "HTTP", logCode: 404)
        XCTAssertEqual(snapshot.failureReason, "Player item failed: avfoundation \(fatal.code)")
        XCTAssertEqual(snapshot.qualityDetails["native_error_domain"], "avfoundation")
        XCTAssertEqual(snapshot.qualityDetails["native_error_code"], String(fatal.code))
        XCTAssertEqual(snapshot.qualityDetails["native_log_domain"], "http")
        XCTAssertEqual(snapshot.qualityDetails["native_log_code"], "404")
        XCTAssertEqual(snapshot.statusCode, 404, "A historical log code stays evidence, not the fatal reason")
        XCTAssertEqual(LivePlaybackFailureKind.classify(
            reason: snapshot.failureReason, countsAsStall: false, isNetworkReachable: true
        ), .sourceFailure, "A stale404 must not classify a genuinely failed item as a startup timeout")
        XCTAssertFalse(snapshot.failureReason.contains("private"))
        XCTAssertFalse(snapshot.qualityDetails.description.contains("provider.example"))
        let unrepresentable = service.snapshot(error: NSError(domain: "private-domain", code: Int.max),
                                              trigger: .itemStatusFailed, logDomain: "HTTP", logCode: 503)
        XCTAssertEqual(unrepresentable.failureReason, "Player item failed: underlying cause unavailable")
        XCTAssertEqual(unrepresentable.qualityDetails["native_log_code"], "503")
        XCTAssertEqual(service.snapshot(error: nil, trigger: .errorLog, logDomain: "HTTP", logCode: 404).failureReason,
                       "Player item failed: HTTP 404")
    }

    func testNativeDiagnosticMissingCauseRemainsUnknownAndChainIsBounded() {
        let service = PlayerDiagnosticService()
        let missing = service.snapshot(error: nil, trigger: .failedToPlayToEnd)
        XCTAssertEqual(missing.qualityDetails, ["native_failure_trigger": "failed_to_play_to_end"])
        XCTAssertTrue(missing.failureReason.contains("cause unavailable"))
        var error = NSError(domain: "private-domain", code: Int.max)
        for _ in 0..<10 {
            error = NSError(domain: "private-domain", code: Int.max, userInfo: [NSUnderlyingErrorKey: error])
        }
        let bounded = service.snapshot(error: error, trigger: .itemStatusFailed)
        XCTAssertEqual(bounded.qualityDetails, ["native_failure_trigger": "item_status_failed"])
        let legitimate = NSError(domain: NSOSStatusErrorDomain, code: -50)
        error = legitimate
        for index in 0..<10 { error = NSError(domain: "CoreMediaErrorDomain", code: index, userInfo: [NSUnderlyingErrorKey: error]) }
        let chain = service.snapshot(error: error, trigger: .itemStatusFailed)
        XCTAssertEqual(chain.qualityDetails["native_error_depth"], "4")
        XCTAssertEqual(chain.qualityDetails["native_underlying_code"], "6")
    }

    func testPreparationReceiptKeepsBoundedErrorChainWithoutInventingHTTPOrItemFailure() {
        let underlying = NSError(domain: NSOSStatusErrorDomain, code: -9807,
                                 userInfo: [NSLocalizedDescriptionKey: "private certificate owner"])
        let error = NSError(domain: NSURLErrorDomain, code: URLError.secureConnectionFailed.rawValue,
            userInfo: [NSUnderlyingErrorKey: underlying,
                       NSLocalizedDescriptionKey: "https://owner.invalid/private?secret=one"])
        let details = PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .transportError,
                                                     error: error).qualityDetails
        XCTAssertEqual(details["preparation_error_domain"], "url")
        XCTAssertEqual(details["preparation_error_code"], String(URLError.secureConnectionFailed.rawValue))
        XCTAssertEqual(details["preparation_underlying_domain"], "osstatus")
        XCTAssertEqual(details["preparation_underlying_code"], "-9807")
        XCTAssertEqual(details["preparation_error_depth"], "2")
        XCTAssertNil(details["native_failure_trigger"])
        XCTAssertNil(details["preparation_http_status"])
        XCTAssertFalse(details.description.contains("private"))
        XCTAssertFalse(details.description.contains("owner.invalid"))
        let numeric404 = PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: .proxyStartup,
            error: NSError(domain: NSURLErrorDomain, code: 404)).qualityDetails
        XCTAssertNil(numeric404["preparation_http_status"], "A numerical NSError is not an HTTP response")
    }

    func testPreparationReceiptMissingCauseAndErrorChainLimitsRemainExplicit() {
        let missing = PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .unavailable).qualityDetails
        XCTAssertEqual(missing, ["preparation_stage": "contract_validation", "preparation_reason": "unavailable"])
        var error = NSError(domain: "private-owner", code: Int.max)
        for _ in 0..<10 { error = NSError(domain: "private-owner", code: Int.max, userInfo: [NSUnderlyingErrorKey: error]) }
        XCTAssertEqual(PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: .proxyStartup,
            error: error, httpStatus: 999).qualityDetails,
            ["preparation_stage": "url_preparation", "preparation_reason": "proxy_startup"])
        error = NSError(domain: NSOSStatusErrorDomain, code: -50)
        for index in 0..<10 { error = NSError(domain: "private-owner", code: index, userInfo: [NSUnderlyingErrorKey: error]) }
        let bounded = PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: .proxyStartup, error: error).qualityDetails
        XCTAssertEqual(bounded["preparation_error_depth"], "4")
        XCTAssertEqual(bounded["preparation_error_domain"], "other")
        XCTAssertEqual(bounded["preparation_underlying_code"], "6")
        XCTAssertFalse(bounded.description.contains("private-owner"))
    }

    func testProxyPreparationFailurePreservesOriginalPolicyErrorButNoSyntheticCause() {
        let observed = LocalStreamProxyFailureEvidence(stage: .upstreamResponse, kind: .httpStatus,
            statusCode: 503, errorCode: nil, recordedAt: Date())
        let health = PlaybackPreparationFailure(ProcessorError.proxyError, reason: .proxyHealthCheck,
                                               relayEvidence: observed)
        XCTAssertEqual(health.underlyingError.localizedDescription, ProcessorError.proxyError.localizedDescription)
        XCTAssertEqual(health.qualityDetails["preparation_stage"], "url_preparation")
        XCTAssertEqual(health.qualityDetails["preparation_reason"], "proxy_health_check")
        XCTAssertNil(health.qualityDetails["preparation_error_code"], "Local health failure does not invent a provider NSError")
        XCTAssertEqual(health.qualityDetails["relay_http_status"], "503")
        XCTAssertNil(health.qualityDetails["preparation_http_status"], "Last observed relay evidence is not the preparation cause")
        let cancelled = PlaybackPreparationFailure(CancellationError(), reason: .cancelled)
        XCTAssertEqual(cancelled.qualityDetails, ["preparation_stage": "url_preparation", "preparation_reason": "cancelled"])
        XCTAssertTrue(cancelled.underlyingError is CancellationError)
    }

    func testRealRedirectDelegateRebuildsCredentialsAndEnforcesHopBudget() async throws {
        let proxy = makeProxy(headers: ["Authorization": "selected-secret", "X-Token": "private", "User-Agent": "Fixture"])
        defer { proxy.stop() }
        let incoming = LocalStreamProxy.ParsedRequest(method: "GET", path: "/unused", headers: ["range": "bytes=0-99"])
        let delegate = LocalStreamProxy.RedirectDelegate(proxy: proxy, request: incoming, limit: 1)
        let cdn = URL(string: "https://cdn.example.net/list.m3u8")!
        let accepted = await redirect(delegate, from: media, to: cdn)
        XCTAssertEqual(accepted?.url, cdn)
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "X-Token"))
        XCTAssertNil(accepted?.value(forHTTPHeaderField: "Range"))
        XCTAssertEqual(accepted?.value(forHTTPHeaderField: "User-Agent"), "Fixture")
        let mediaDelegate = LocalStreamProxy.RedirectDelegate(proxy: proxy, request: incoming, limit: 1)
        let segment = URL(string: "https://cdn.example.net/segment.ts")!
        let rangedSegment = await redirect(mediaDelegate, from: media, to: segment)
        XCTAssertEqual(rangedSegment?.value(forHTTPHeaderField: "Range"), "bytes=0-99")
        let overBudget = await redirect(delegate, from: cdn, to: URL(string: "https://next.example.net/list.m3u8")!)
        XCTAssertNil(overBudget)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 0)
    }

    func testRealRedirectDelegateRevalidatesDNSAndCancellationBeforeFollowing() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProxyFixtureProtocol.self]
        let proxy = LocalStreamProxy(headers: ["Authorization": "secret"], cookies: [], selectedMediaURL: media,
                                    configuration: config, resolver: { _ in ["127.0.0.1"] })
        defer { proxy.stop() }
        let incoming = LocalStreamProxy.ParsedRequest(method: "GET", path: "/unused", headers: [:])
        let delegate = LocalStreamProxy.RedirectDelegate(proxy: proxy, request: incoming, limit: 5)
        let rejected = await redirect(delegate, from: media, to: URL(string: "https://private-answer.example.net/key")!)
        XCTAssertNil(rejected)
        delegate.cancel()
        let cancelled = await redirect(delegate, from: media, to: URL(string: "https://8.8.8.8/key")!)
        XCTAssertNil(cancelled)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 0)
    }

    func testActualListenerCapsConcurrentConnections() async throws {
        var limits = LocalStreamProxyPolicy.Limits()
        limits.connections = 1
        let proxy = makeProxy(limits: limits)
        defer { proxy.stop() }
        try await proxy.start()
        let port = NWEndpoint.Port(rawValue: try XCTUnwrap(proxy.port))!
        let first = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        defer { first.cancel() }
        let ready = expectation(description: "First connection ready")
        first.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        first.start(queue: DispatchQueue(label: "proxy.test.first"))
        await fulfillment(of: [ready], timeout: 2)
        for _ in 0..<100 where proxy.activeConnectionCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(proxy.activeConnectionCount, 1)
        let second = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        defer { second.cancel() }
        let closed = expectation(description: "Excess connection closed")
        second.start(queue: DispatchQueue(label: "proxy.test.second"))
        second.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, complete, error in
            XCTAssertTrue(complete || error != nil)
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(proxy.activeConnectionCount, 1)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 0)
    }

    func testStopCancelsOwnedTransportAndRevokesSession() async throws {
        let started = expectation(description: "Owned upstream began")
        let cancelled = expectation(description: "Owned upstream cancelled")
        ProxyFixtureProtocol.configure(onStop: { cancelled.fulfill() }) { _ in started.fulfill() }
        let proxy = makeProxy()
        try await proxy.start()
        let url = try XCTUnwrap(proxy.playbackURL())
        let loading = Task { try await URLSession.shared.data(from: url) }
        await fulfillment(of: [started], timeout: 3)
        proxy.stop()
        await fulfillment(of: [cancelled], timeout: 3)
        loading.cancel()
        _ = try? await loading.value
        XCTAssertEqual(proxy.activeConnectionCount, 0)
        XCTAssertNil(proxy.playbackURL())
        let healthy = await proxy.ping()
        XCTAssertFalse(healthy)
        do { try await proxy.start(); XCTFail("Stopped sessions must not restart") } catch { }
    }

    func testHeaderDeadlineClosesAnIncompleteLocalRequest() async throws {
        var limits = LocalStreamProxyPolicy.Limits()
        limits.headerSeconds = 0.1
        let proxy = makeProxy(limits: limits)
        defer { proxy.stop() }
        try await proxy.start()
        let connection = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: try XCTUnwrap(proxy.port))!, using: .tcp)
        defer { connection.cancel() }
        let closed = expectation(description: "Incomplete request closed")
        connection.start(queue: DispatchQueue(label: "proxy.test.partial"))
        connection.send(content: Data("GET / HTTP/1.1\r\n".utf8), completion: .contentProcessed { _ in })
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, complete, error in
            XCTAssertTrue(complete || error != nil)
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 3)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 0)
    }

    func testResourceDeadlineCancelsAHangingUpstream() async throws {
        let started = expectation(description: "Upstream began")
        let cancelled = expectation(description: "Deadline cancelled upstream")
        let finished = expectation(description: "Deadline closed the single local connection without client cancellation")
        ProxyFixtureProtocol.configure(onStop: { cancelled.fulfill() }) { _ in started.fulfill() }
        var limits = LocalStreamProxyPolicy.Limits()
        limits.resourceSeconds = 0.2
        let proxy = makeProxy(limits: limits)
        defer { proxy.stop() }
        try await proxy.start()
        let url = try XCTUnwrap(proxy.playbackURL())
        let port = try XCTUnwrap(proxy.port)
        // URLSession can transparently retry an idempotent GET when the relay
        // closes before response headers. Use one socket and one request so a
        // retry cannot create a second connection during teardown assertions.
        let connection = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { connection.cancel() }
        connection.start(queue: DispatchQueue(label: "proxy.test.resource-deadline"))
        receiveUntilClosed(connection, closed: finished)
        let request = "GET \(url.path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
            XCTAssertNil(error)
        })
        await fulfillment(of: [started, cancelled, finished], timeout: 3)
        // URLProtocol.stopLoading observes upstream cancellation, not relay
        // teardown. URLSession's timeout may arrive before forwardRequest's
        // catch/send callback closes the downstream NWConnection. Wait for the
        // owned state to drain without stop() or client cancellation hiding a
        // leak, then assert the same zero-connection invariant.
        let drained = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in proxy.activeConnectionCount == 0 }, object: nil)
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(proxy.activeConnectionCount, 0)
        XCTAssertEqual(ProxyFixtureProtocol.requests.count, 1)
        let receipt = try XCTUnwrap(proxy.requestEvidenceSnapshot().requests.first)
        XCTAssertEqual(receipt.outcome, .failed)
        XCTAssertEqual(proxy.lastFailureEvidence?.requestID, receipt.requestID)
        XCTAssertEqual(proxy.lastFailureEvidence?.kind, .timeout)
    }

    private func receiveUntilClosed(_ connection: NWConnection, closed: XCTestExpectation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [self] _, _, complete, error in
            if complete || error != nil {
                closed.fulfill()
            } else {
                // A bounded 502 response may precede the EOF when Foundation's
                // upstream deadline wins; receiving bytes alone is not teardown.
                receiveUntilClosed(connection, closed: closed)
            }
        }
    }

    private func makeCookie(name: String, domain: String, path: String = "/", expires: Date = Date().addingTimeInterval(3600)) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: "value", .domain: domain,
                                             .path: path, .secure: "TRUE", .expires: expires]))
    }

    private func redirect(_ delegate: LocalStreamProxy.RedirectDelegate, from source: URL, to destination: URL) async -> URLRequest? {
        // Exercise the production redirect delegate without resuming a task or
        // relying on URLProtocol's platform-specific redirect implementation.
        let task = URLSession.shared.dataTask(with: source)
        defer { task.cancel() }
        let response = HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: ["Location": destination.absoluteString])!
        var inherited = URLRequest(url: destination)
        inherited.setValue("inherited-cookie", forHTTPHeaderField: "Cookie")
        inherited.setValue("inherited-authorization", forHTTPHeaderField: "Authorization")
        return await withCheckedContinuation { continuation in
            delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: inherited) {
                continuation.resume(returning: $0)
            }
        }
    }

    private func makeProxy(headers: [String: String] = [:], limits: LocalStreamProxyPolicy.Limits = .init()) -> LocalStreamProxy {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProxyFixtureProtocol.self]
        return LocalStreamProxy(headers: headers, cookies: [], selectedMediaURL: media, limits: limits,
                                configuration: config, resolver: { _ in ["8.8.8.8"] })
    }
}

/// Opt-in capacity measurement, not a decoded-video or provider-health verdict.
/// Synthetic HTTPS terminates in the test protocol; only the relay uses sockets.
final class ReviewedRelayThroughputPhysicalTests: XCTestCase {
    override func tearDown() {
        ProxyFixtureProtocol.reset()
        super.tearDown()
    }

    func testSyntheticOneMiBDirectBytesAndGuardedRelayThroughputOnPhysicalDevice() async throws {
        #if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst) && !targetEnvironment(simulator)
        let startedAt = ProcessInfo.processInfo.systemUptime
        let overallDeadline = startedAt + 55
        let payload = Data(repeating: 0x47, count: 1_048_576)
        // The production destination policy deliberately rejects `.invalid`.
        // All HTTPS and DNS below are intercepted, so use a policy-admissible
        // synthetic host without granting it real network access.
        let upstream = URL(string: "https://relay-throughput.example.com/segment.ts")!
        ProxyFixtureProtocol.configure { fixture in
            fixture.respond(type: "video/mp2t", body: payload,
                            headers: ["Content-Length": String(payload.count)])
        }
        func configuration(interceptHTTPS: Bool) -> URLSessionConfiguration {
            let config = URLSessionConfiguration.ephemeral
            if interceptHTTPS { config.protocolClasses = [ProxyFixtureProtocol.self] }
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.httpShouldSetCookies = false; config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 15
            return config
        }
        let direct = URLSession(configuration: configuration(interceptHTTPS: true))
        let downstream = URLSession(configuration: configuration(interceptHTTPS: false))
        var limits = LocalStreamProxyPolicy.Limits()
        limits.resourceBytes = payload.count; limits.requestSeconds = 15; limits.resourceSeconds = 15
        let proxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: upstream,
            limits: limits, configuration: configuration(interceptHTTPS: true), resolver: { _ in ["8.8.8.8"] })
        var phase = "setup"
        var outcome = "incomplete"
        var measurements: [String: TimeInterval] = [:]
        defer {
            proxy.stop(); direct.invalidateAndCancel(); downstream.invalidateAndCancel()
            var evidence = ["diagnostic_scope": "synthetic_relay_capacity_not_decode",
                            "outcome": outcome, "phase": phase, "body_bytes": String(payload.count)]
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            if elapsed.isFinite, elapsed >= 0, elapsed < 3_600 {
                evidence["overall_elapsed_ms"] = String(Int(elapsed * 1_000))
            }
            for (name, seconds) in measurements where seconds.isFinite && seconds > 0 && seconds < 3_600 {
                evidence[name + "_elapsed_ms"] = String(format: "%.3f", seconds * 1_000)
                let throughput = 1 / seconds // Exactly one MiB in every path.
                if throughput.isFinite { evidence[name + "_mib_per_second"] = String(format: "%.3f", throughput) }
            }
            let attachment = XCTAttachment(string: evidence.keys.sorted().map { "\($0)=\(evidence[$0]!)" }.joined(separator: "\n"))
            attachment.name = "Physical synthetic relay throughput evidence"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        try await withTaskCancellationHandler {
            try await proxy.start()
            try Task.checkCancellation()
            let local = try XCTUnwrap(proxy.playbackURL())

            phase = "direct_data"
            measurements[phase] = try await Self.measure(before: overallDeadline) {
                let (data, response) = try await direct.data(from: upstream)
                try Self.validate(data: data, response: response, expected: payload)
            }
            phase = "direct_async_bytes"
            measurements[phase] = try await Self.measure(before: overallDeadline) {
                let (bytes, response) = try await direct.bytes(from: upstream)
                defer { bytes.task.cancel() }
                var buffer = Data(); buffer.reserveCapacity(65_536)
                var collected = Data(); collected.reserveCapacity(payload.count)
                var count = 0
                for try await byte in bytes {
                    guard count < payload.count else { throw URLError(.dataLengthExceedsMaximum) }
                    count += 1; buffer.append(byte)
                    if buffer.count == 65_536 {
                        try Task.checkCancellation()
                        collected.append(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                if !buffer.isEmpty { collected.append(buffer) }
                try Self.validate(data: collected, response: response, expected: payload)
            }
            phase = "capability_relay"
            measurements[phase] = try await Self.measure(before: overallDeadline) {
                let (data, response) = try await downstream.data(from: local)
                try Self.validate(data: data, response: response, expected: payload)
            }
            XCTAssertEqual(ProxyFixtureProtocol.requests.count, 3,
                           "Each measured path uses exactly one intercepted synthetic delivery")
            XCTAssertNil(proxy.lastFailureEvidence)
            XCTAssertEqual(proxy.requestEvidenceSnapshot().requests.last?.outcome, .completed)
            outcome = "functionally_measured"
            phase = "completed"
        } onCancel: {
            proxy.stop(); direct.invalidateAndCancel(); downstream.invalidateAndCancel()
        }
        #else
        throw XCTSkip("Requires explicit FOTTY_REVIEWED_ADDON_CANARY on a physical iOS device; no capacity measurement.")
        #endif
    }

    private static func validate(data: Data, response: URLResponse, expected: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Length") == String(expected.count), data == expected else {
            throw URLError(.badServerResponse)
        }
    }

    private static func measure(before overallDeadline: TimeInterval,
                                operation: @escaping @Sendable () async throws -> Void) async throws -> TimeInterval {
        let seconds = min(15, overallDeadline - ProcessInfo.processInfo.systemUptime)
        guard seconds.isFinite, seconds > 0 else { throw URLError(.timedOut) }
        return try await withThrowingTaskGroup(of: TimeInterval.self) { group in
            group.addTask {
                let began = ProcessInfo.processInfo.systemUptime
                try await operation()
                try Task.checkCancellation()
                return ProcessInfo.processInfo.systemUptime - began
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let measured = try await group.next() else { throw CancellationError() }
            return measured
        }
    }
}

/// All HTTPS media traffic in these tests terminates here. Only the listener's
/// 127.0.0.1 requests use a socket; no provider or public DNS traffic is issued.
private final class ProxyFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((ProxyFixtureProtocol) -> Void)?
    private static var stopHandler: (() -> Void)?
    private static var recorded: [URLRequest] = []
    private let stateLock = NSLock()
    private var stopped = false
    private var ownedStopHandler: (() -> Void)?

    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    static func configure(onStop: (() -> Void)? = nil, handler: @escaping (ProxyFixtureProtocol) -> Void) {
        lock.lock()
        self.handler = handler
        stopHandler = onStop
        recorded = []
        lock.unlock()
    }

    static func reset() {
        lock.lock(); handler = nil; stopHandler = nil; recorded = []; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "https" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let handler = Self.handler
        let stopHandler = Self.stopHandler
        Self.lock.unlock()
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); return }
        ownedStopHandler = stopHandler
        stateLock.unlock()
        if let handler { handler(self) }
        else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)) }
    }

    override func stopLoading() {
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); return }
        stopped = true
        let handler = ownedStopHandler
        ownedStopHandler = nil
        stateLock.unlock()
        handler?()
    }

    func respond(type: String, body: Data, status: Int = 200, headers: [String: String] = [:]) {
        guard isActive, let client else { return }
        let fields = headers.merging(["Content-Type": type]) { _, value in value }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!
        // Foundation callbacks can synchronously stop this protocol. Keep them
        // outside our lock and do not publish another event after that stop.
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard isActive else { return }
        client.urlProtocol(self, didLoad: body)
        guard isActive else { return }
        client.urlProtocolDidFinishLoading(self)
    }

    private var isActive: Bool { stateLock.lock(); defer { stateLock.unlock() }; return !stopped }
}

/// Test-owned release gate: no wall-clock sleeps and no live provider is needed
/// to arrange an unfinished request or a completion after its owner is retired.
private final class ProxyFixtureGate {
    private let lock = NSLock()
    private var pending: [ProxyFixtureProtocol] = []

    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return pending.count }

    func hold(_ fixture: ProxyFixtureProtocol) {
        lock.lock(); pending.append(fixture); lock.unlock()
    }

    func release(type: String, body: Data, status: Int = 200) {
        lock.lock(); let fixtures = pending; pending.removeAll(); lock.unlock()
        fixtures.forEach { $0.respond(type: type, body: body, status: status) }
    }
}

private final class ProxyFixtureDeliverySequence {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }; count += 1; return count
    }
}
