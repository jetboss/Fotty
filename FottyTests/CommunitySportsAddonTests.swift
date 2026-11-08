import XCTest
@testable import Fotty

private actor CSProgrammeTestState {
    private(set) var available = true
    func set(_ value: Bool) { available = value }
}

final class CommunitySportsAddonTests: XCTestCase {
    private let kickoff = ISO8601DateFormatter().date(from: "2026-09-13T20:05:00Z")!

    private let cdnLiveURL = "https://cdnlivetv.tv/secure/api/v1/0123456789abcdef01234567/playlist.m3u8?token=" + String(repeating: "a", count: 64)
    private let cdnLiveHeaders = ["Origin": "https://cdnlivetv.tv", "Referer": "https://cdnlivetv.tv/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"]

    func testReviewedCDNLiveCSDeliveryPreservesTokenHeadersAndGuardedRelay() throws {
        let entry = directFancodeEntry(url: cdnLiveURL, sourceHint: "cdnlive", headers: cdnLiveHeaders)
        let session = try XCTUnwrap(directFancodeSessions([entry]).first)
        XCTAssertEqual(session.playableURL.absoluteString, cdnLiveURL)
        XCTAssertEqual(session.requiredHeaders, cdnLiveHeaders)
        XCTAssertEqual(session.streamType, .hls)
        XCTAssertEqual(session.requiresGuardedRelay, true)
        XCTAssertNil(session.nativeOriginProfile)
        XCTAssertNil(session.nativePlaylistProfile)
        XCTAssertEqual(session.diagnosticMetadata["source_hint"], "cdnlive")
        XCTAssertFalse(session.diagnosticMetadata.values.contains { $0.contains("token=") || $0.contains("cdnlivetv.tv") })
    }

    func testReviewedCDNLiveContractRejectsUnreviewedOriginsPathsAndTokens() {
        let invalid = [cdnLiveURL.replacingOccurrences(of: "https:", with: "http:"),
            cdnLiveURL.replacingOccurrences(of: "cdnlivetv.tv/", with: "cdnlivetv.tv:8443/"),
            cdnLiveURL.replacingOccurrences(of: "cdnlivetv.tv", with: "cdn.cdnlivetv.tv"),
            cdnLiveURL.replacingOccurrences(of: "cdnlivetv.tv", with: "user@cdnlivetv.tv"),
            cdnLiveURL.replacingOccurrences(of: "/secure/", with: "/%73ecure/"),
            cdnLiveURL.replacingOccurrences(of: "0123456789abcdef01234567", with: "other"),
            cdnLiveURL.replacingOccurrences(of: ".m3u8", with: ".html"),
            cdnLiveURL.components(separatedBy: "?")[0],
            cdnLiveURL + "&token=duplicate", cdnLiveURL + "&url=https://example.com/a.m3u8", cdnLiveURL + "#fragment"]
        for url in invalid {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: url, sourceHint: "cdnlive", headers: cdnLiveHeaders)]).isEmpty)
        }
        for hint in ["daddylive", "sktech", "unknown"] {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: cdnLiveURL, sourceHint: hint, headers: cdnLiveHeaders)]).isEmpty)
        }
    }

    func testReviewedCDNLiveRequiresExactPublicHeaderContract() {
        var wrongOrigin = cdnLiveHeaders; wrongOrigin["Origin"] = "https://other.example"
        var wrongReferer = cdnLiveHeaders; wrongReferer["Referer"] = "https://cdnlivetv.tv/other"
        var credentials = cdnLiveHeaders; credentials["Authorization"] = "fixture-secret"
        var missing = cdnLiveHeaders; missing.removeValue(forKey: "Origin")
        for headers in [nil, [:], wrongOrigin, wrongReferer, credentials, missing] {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: cdnLiveURL, sourceHint: "cdnlive", headers: headers)]).isEmpty)
        }
        XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: cdnLiveURL, sourceHint: "cdnlive",
            headers: cdnLiveHeaders, responseHeaders: ["Access-Control-Allow-Origin": "*"])]).isEmpty)
    }

    func testOnlyStreamListGetsALargerBoundedTransportSlice() {
        for stage in [CommunitySportsRequestStage.manifest, .catalog, .metadata] {
            XCTAssertEqual(stage.requestTimeout, 7)
            XCTAssertEqual(stage.transportDeadline, 9)
        }
        XCTAssertEqual(CommunitySportsRequestStage.streams.requestTimeout, 11)
        XCTAssertEqual(CommunitySportsRequestStage.streams.transportDeadline, 12)
        let configuration = CommunitySportsAddonClient.makeConfiguration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 7)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 24)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
    }

    func testActualCSRequestsKeepMetadataTimeoutsAndUseSourceLocalStreamBudget() async throws {
        let session = try makeFixtureSession()
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let result = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", "/catalog/tv/nuvio_sports_football.json",
            "/catalog/tv/nuvio_sports_live.json", "/stream/tv/nuvio_sport_fixture.json"])
        XCTAssertEqual(CommunitySportsFixtureProtocol.timeouts, [7, 7, 7, 23])
    }

    func testDelayedValidStreamListSurvivesOldDeadlineWithoutRetry() async throws {
        let gate = CommunitySportsFixtureGate("CS slow stream route started")
        let session = try makeFixtureSession(streamResponse: .controlled(gate))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let operation = Task { try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football")) }
        defer { operation.cancel() }
        await fulfillment(of: [gate.started], timeout: 3)
        // Cross the old twelve-second transport deadline using a controlled
        // response, with no external traffic or widened metadata budget.
        try await Task.sleep(nanoseconds: 13_250_000_000)
        gate.respond(try .json(["streams": [["url": "https://addon.example/api/manifest?channel=fixture", "_source": "upstream-a"]]]))
        let result = try await operation.value
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }.count, 1)
    }

    func testReviewedDirectFancodeHLSRetainsPublicHeadersAndNativeDeliveryIdentity() throws {
        for authority in ["dai-fancode.pages.dev", "dai-fancode.pages.dev:443"] {
            let url = "https://\(authority)/mumbai/fixture_english-hls_123/index.m3u8"
            let entry = directFancodeEntry(url: url)
            let session = try XCTUnwrap(directFancodeSessions([entry]).first)
            XCTAssertEqual(session.playableURL.absoluteString, url)
            XCTAssertEqual(session.streamType, .hls)
            XCTAssertEqual(session.providerName, "CS1")
            XCTAssertEqual(session.requiredHeaders, ["Referer": "https://fancode.com/", "User-Agent": "ReactNativeVideo/9.11.1 (Fixture Player)"])
            XCTAssertEqual(session.legacySource.headers, session.requiredHeaders)
            XCTAssertEqual(session.legacySource.url, session.playableURL)
            XCTAssertTrue(session.requiresLocalProxy)
            XCTAssertTrue(session.legacySource.requiresLocalProxy)
            XCTAssertNil(session.nativeOriginProfile, "HTTPS443 needs no exceptional-port authority")
            XCTAssertNil(session.nativePlaylistProfile, "A direct playlist is not the reviewed rotating wrapper contract")
            XCTAssertEqual(session.diagnosticMetadata["delivery"], "reviewed_direct_hls")
            XCTAssertEqual(session.diagnosticMetadata["source_hint"], "sktech")
            XCTAssertEqual(session.diagnosticMetadata["source_key_scope"], "upstream")
            XCTAssertFalse(session.diagnosticMetadata.values.contains { $0.contains("dai-fancode") || $0.contains("Fixture Player") })
        }
    }

    func testReviewedDirectFancodeHeadersKeepCanonicalCaseAndOnlyGuardedPublicRequestFields() throws {
        let entry = directFancodeEntry(headers: ["referer": "https://fancode.com/", "user-agent": "ReactNativeVideo/9.11.1 (Fixture Player)"])
        let session = try XCTUnwrap(directFancodeSessions([entry]).first)
        XCTAssertEqual(session.requiredHeaders, ["Referer": "https://fancode.com/", "User-Agent": "ReactNativeVideo/9.11.1 (Fixture Player)"])
        let segment = session.playableURL.deletingLastPathComponent().appendingPathComponent("segment.ts")
        let request = LocalStreamProxyPolicy.remoteRequest(url: segment, selectedMediaURL: session.playableURL,
            method: "GET", capturedHeaders: session.requiredHeaders, cookies: [],
            clientHeaders: ["range": "bytes=0-99", "authorization": "untrusted", "cookie": "untrusted=value",
                            "x-fotty-web-embed": "true"], timeout: 30)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "ReactNativeVideo/9.11.1 (Fixture Player)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://fancode.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-99")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Fotty-Web-Embed"))
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testReviewedDirectFancodeMasterRegistersCDNVariantWithoutLosingHeadersOrSignedQuery() throws {
        let session = try XCTUnwrap(directFancodeSessions([directFancodeEntry()]).first)
        let variant = try XCTUnwrap(URL(string:
            "https://in-mc-plive.fancode.com/mumbai/fixture/english/index.m3u8?token=fixture%2Bsignature%2Fvalue&expires=1800000000"))
        var policy = LocalStreamProxyPolicy(selectedMediaURL: session.playableURL,
            originProfile: session.nativeOriginProfile, requestHeaders: session.requiredHeaders,
            playlistProfile: session.nativePlaylistProfile)
        XCTAssertTrue(policy.isValid)
        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1200000\n\(variant.absoluteString)\n"
        let rewritten = try policy.rewriteManifest(master, relativeTo: session.playableURL, port: 12345)
        let mediaLines = rewritten.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(mediaLines.count, 1)
        let local = try XCTUnwrap(mediaLines.first.flatMap { URL(string: String($0)) })
        XCTAssertEqual(local.host, "127.0.0.1")
        let admitted = try XCTUnwrap(policy.destination(for: local.path))
        XCTAssertEqual(admitted.absoluteString, variant.absoluteString,
            "Manifest rewriting must not normalize/drop the CDN's signed query")
        let request = LocalStreamProxyPolicy.remoteRequest(url: admitted, selectedMediaURL: session.playableURL,
            method: "GET", capturedHeaders: session.requiredHeaders, cookies: [], clientHeaders: [:], timeout: 30)
        XCTAssertEqual(request.url?.absoluteString, variant.absoluteString)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "ReactNativeVideo/9.11.1 (Fixture Player)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://fancode.com/")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testReviewedDirectFancodeAdmissionRejectsOtherOriginsPortsCredentialsAndRoutes() {
        let path = "/mumbai/fixture_english-hls_123/index.m3u8"
        let rejected = [
            "http://dai-fancode.pages.dev\(path)",
            "https://dai-fancode.pages.dev:80\(path)",
            "https://dai-fancode.pages.dev:8443\(path)",
            "https://dai-fancode.pages.dev.evil.example\(path)",
            "https://cdn.dai-fancode.pages.dev\(path)",
            "https://dai-fancode.pages.dev.\(path)",
            "https://other.pages.dev\(path)",
            "https://unreviewed.example\(path)",
            "https://user@dai-fancode.pages.dev\(path)",
            "https://user:secret@dai-fancode.pages.dev\(path)",
            "https://dai-fancode.pages.dev/mumbai/fixture/index.mp4",
            "https://dai-fancode.pages.dev/mumbai/fixture/master.m3u8",
            "https://dai-fancode.pages.dev/other/fixture/index.m3u8",
            "https://dai-fancode.pages.dev/mumbai/fixture/extra/index.m3u8",
            "https://dai-fancode.pages.dev/mumbai//index.m3u8",
            "https://dai-fancode.pages.dev/mumbai/fixture%2Fother/index.m3u8",
            "https://dai-fancode.pages.dev/mumbai/fixture%5Cother/index.m3u8",
            "https://dai-fancode.pages.dev\(path)?quality=hd",
            "https://dai-fancode.pages.dev\(path)#player",
            "https://www.buymeacoffee.com/fixture-support"
        ]
        for url in rejected {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: url)]).isEmpty, url)
        }
    }

    func testReviewedDirectFancodeRequiresReviewedManifestAndSourceAttribution() {
        let entry = directFancodeEntry()
        for manifest in ["https://addon.example/manifest.json", "https://nuviosports.xyz/other/manifest.json",
                         "http://nuviosports.xyz/manifest.json", "https://nuviosports.xyz:8443/manifest.json",
                         "https://user:secret@nuviosports.xyz/manifest.json",
                         "https://nuviosports.xyz/manifest.json?config=other",
                         "https://nuviosports.xyz/manifest.json#other"] {
            XCTAssertTrue(directFancodeSessions([entry], manifest: manifest).isEmpty, manifest)
        }
        for hint in ["unknown", "other-source", "daddylive", "https://sktech.example"] {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(sourceHint: hint)]).isEmpty, hint)
        }
    }

    func testReviewedDirectFancodeRequiresExactPublicHeaderContractWithoutCredentials() {
        let good = ["Referer": "https://fancode.com/", "User-Agent": "ReactNativeVideo/9.11.1 (Fixture Player)"]
        var rejected: [[String: String]?] = [nil, [:], ["User-Agent": "ReactNativeVideo/9.11.1 (Fixture Player)"], ["Referer": "https://fancode.com/"]]
        for referer in ["https://www.fancode.com/", "https://fancode.com", "http://fancode.com/",
                        "https://fancode.com:444/", "https://fancode.com.evil.example/", "https://127.0.0.1/",
                        "https://user:secret@fancode.com/", "https://fancode.com/player", "https://fancode.com/?private=token"] {
            rejected.append(["Referer": referer, "User-Agent": "ReactNativeVideo/9.11.1 (Fixture Player)"])
        }
        for name in ["Origin", "Cookie", "Authorization", "Proxy-Authorization", "Host", "X-API-Key"] {
            rejected.append(good.merging([name: name == "Origin" ? "https://fancode.com" : "untrusted"],
                                         uniquingKeysWith: { _, new in new }))
        }
        for agent in ["", "Fixture Player", "ReactNativeVideo/", "OtherReactNativeVideo/9.11.1",
                      "ReactNativeVideo/9.11.1\r\nCookie: secret", "ReactNativeVideo/9.11.1🟢",
                      "ReactNativeVideo/" + String(repeating: "a", count: 513)] {
            rejected.append(["Referer": "https://fancode.com/", "User-Agent": agent])
        }
        rejected.append(good.merging(["user-agent": "duplicate"], uniquingKeysWith: { _, new in new }))
        for headers in rejected {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(headers: headers)]).isEmpty)
        }
        XCTAssertTrue(directFancodeSessions([directFancodeEntry(responseHeaders: ["Access-Control-Allow-Origin": "*"])]).isEmpty)
    }

    func testReviewedDirectFancodeDoesNotAdmitDonationOrWrappedHTTP2122AndKeepsOpaqueLabels() throws {
        let direct = directFancodeEntry()
        let donation = directFancodeEntry(url: "https://www.buymeacoffee.com/fixture-support")
        let unsafeWrapper = try fairCapEntry(sourceHint: "sktech", upstream: "http://93.184.216.34:2122/live/index.m3u8")
        let sibling = try fairCapEntry(sourceHint: "streamedpk", upstream: "https://video.example/live.m3u8")
        let sessions = directFancodeSessions([donation, unsafeWrapper, direct, sibling, direct])
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(sessions.map { $0.playableURL.absoluteString }, [direct, sibling].compactMap(\.url))
        let reordered = directFancodeSessions([sibling, donation, direct, unsafeWrapper])
        XCTAssertEqual(reordered.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(sessions.first?.diagnosticMetadata["source_key"], reordered.last?.diagnosticMetadata["source_key"])
        XCTAssertEqual(sessions.last?.diagnosticMetadata["source_key"], reordered.first?.diagnosticMetadata["source_key"])
        XCTAssertNotEqual(sessions.first?.diagnosticMetadata["source_key"], sessions.last?.diagnosticMetadata["source_key"])
    }

    private func directFancodeEntry(
        url: String = "https://dai-fancode.pages.dev/mumbai/fixture_english-hls_123/index.m3u8",
        sourceHint: String = "sktech",
        headers: [String: String]? = ["Referer": "https://fancode.com/", "User-Agent": "ReactNativeVideo/9.11.1 (Fixture Player)"],
        responseHeaders: [String: String]? = nil
    ) -> CommunitySportsStreamEntry {
        CommunitySportsStreamEntry(name: nil, title: nil, url: url, externalURL: nil,
            resolution: "1920x1080", quality: nil, sourceHint: sourceHint,
            behaviorHints: headers == nil && responseHeaders == nil ? nil
                : .init(proxyHeaders: .init(request: headers, response: responseHeaders)))
    }

    func testWrappedUnsafeTargetsCannotBypassChecksWithAPIRouteOrQueryCase() throws {
        for path in ["/api/manifest", "/API/Manifest", "/api/%6danifest", "/api/manifest.m3u8"] {
            for key in ["url", "URL"] {
                var parts = try XCTUnwrap(URLComponents(string: "https://nuviosports.xyz" + path))
                parts.queryItems = [URLQueryItem(name: key, value: "http://93.184.216.34:2122/live/index.m3u8")]
                let entry = directFancodeEntry(url: try XCTUnwrap(parts.url).absoluteString,
                    sourceHint: "ak47live", headers: nil)
                XCTAssertTrue(directFancodeSessions([entry]).isEmpty, "\(path), \(key)")
            }
        }
    }

    func testPublishedManifestHLSAliasPreservesSignedQueryAndReviewedPlaylistProfile() throws {
        let raw = "https://nuviosports.xyz/api/manifest.m3u8?url=https%3A%2F%2Flb1.strmd.st%2Flive%2Fmaster.m3u8%3Fst%3Dfixture%252Bsignature%252Fvalue&rck=fixture%2Bkey"
        let entry = directFancodeEntry(url: raw, sourceHint: "streamedpk", headers: nil)
        let session = try XCTUnwrap(directFancodeSessions([entry]).first)
        XCTAssertEqual(session.playableURL.absoluteString, raw)
        XCTAssertEqual(session.streamType, .hls)
        XCTAssertTrue(session.requiredHeaders.isEmpty)
        XCTAssertTrue(session.requiresLocalProxy)
        XCTAssertEqual(session.requiresGuardedRelay, true)
        XCTAssertNotNil(session.nativePlaylistProfile)
        XCTAssertNotNil(session.legacySource.nativePlaylistProfile)
        XCTAssertNil(session.nativeOriginProfile)
        XCTAssertEqual(session.diagnosticMetadata["delivery"], "same_origin_hls_proxy")
        XCTAssertFalse(session.diagnosticMetadata.values.contains { $0.contains("signature") || $0.contains("rck=") })
        let headerlessDaddy = try XCTUnwrap(directFancodeSessions([
            directFancodeEntry(url: raw, sourceHint: "daddylive", headers: nil)
        ]).first)
        XCTAssertNil(headerlessDaddy.nativeOriginProfile)
        XCTAssertNotNil(headerlessDaddy.nativePlaylistProfile)
        XCTAssertTrue(headerlessDaddy.requiresLocalProxy,
            "A headerless alias must not bypass the relay when no exceptional/stability profile applies")
    }

    func testPublishedManifestHLSAliasCannotLaunderUnsafeHeaderlessTargets() throws {
        let targets = ["http://93.184.216.34:8008/live/index.m3u8", "http://93.184.216.34:2122/live/index.m3u8",
                       "http://video.example/live.m3u8", "https://video.example:8443/live.m3u8",
                       "https://user:secret@video.example/live.m3u8", "https://127.0.0.1/live.m3u8",
                       "https://video.example/live.m3u8#fragment"]
        for target in targets {
            var url = try XCTUnwrap(URLComponents(string: "https://nuviosports.xyz/api/manifest.m3u8"))
            url.queryItems = [URLQueryItem(name: "url", value: target)]
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: try XCTUnwrap(url.url).absoluteString,
                sourceHint: "daddylive", headers: nil)]).isEmpty, target)
        }
        var duplicate = try XCTUnwrap(URLComponents(string: "https://nuviosports.xyz/api/manifest.m3u8"))
        duplicate.queryItems = [URLQueryItem(name: "url", value: "https://video.example/live.m3u8"),
                                URLQueryItem(name: "URL", value: "https://video.example/other.m3u8")]
        XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: try XCTUnwrap(duplicate.url).absoluteString,
            sourceHint: "streamedpk", headers: nil)]).isEmpty)
        let safe = "https://nuviosports.xyz/api/manifest.m3u8?url=https%3A%2F%2Fvideo.example%2Flive.m3u8"
        for header in ["Cookie", "Authorization", "X-API-Key"] {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: safe, sourceHint: "daddylive",
                headers: [header: "untrusted"])]).isEmpty)
        }
    }

    func testPublishedManifestHLSAliasRejectsLookalikesAndUnreviewedOrigins() {
        let suffix = "?url=https%3A%2F%2Fvideo.example%2Flive.m3u8"
        let rejected = ["https://nuviosports.xyz/API/manifest.m3u8", "https://nuviosports.xyz/api/Manifest.m3u8",
                        "https://nuviosports.xyz/api/%6danifest.m3u8", "https://nuviosports.xyz/api/manifest%2Em3u8",
                        "https://nuviosports.xyz/api/other/../manifest.m3u8", "https://nuviosports.xyz/api/manifest.m3u8/",
                        "https://nuviosports.xyz/api/manifest.m3u8.evil", "https://nuviosports.xyz/api/manifest.mpd",
                        "https://nuviosports.xyz/api//manifest.m3u8", "https://nuviosports.xyz.evil.example/api/manifest.m3u8",
                        "https://other.example/api/manifest.m3u8", "https://nuviosports.xyz:8443/api/manifest.m3u8",
                        "https://user:secret@nuviosports.xyz/api/manifest.m3u8", "http://nuviosports.xyz/api/manifest.m3u8"]
        for raw in rejected {
            XCTAssertTrue(directFancodeSessions([directFancodeEntry(url: raw + suffix,
                sourceHint: "streamedpk", headers: nil)]).isEmpty, raw)
        }
        XCTAssertTrue(directFancodeSessions([directFancodeEntry(url:
            "https://nuviosports.xyz/api/manifest.m3u8" + suffix + "#fragment", sourceHint: "streamedpk", headers: nil)]).isEmpty)
    }

    func testPublishedManifestHLSAliasKeepsExceptionalOriginAndHeaderBindingNarrow() throws {
        let entry = try reviewed8443Entry(delivery: "https://nuviosports.xyz/api/manifest.m3u8")
        let session = try XCTUnwrap(reviewed8443Sessions([entry]).first)
        let profile = try XCTUnwrap(session.nativeOriginProfile)
        XCTAssertTrue(session.requiresLocalProxy)
        XCTAssertTrue(LocalStreamProxyPolicy(selectedMediaURL: session.playableURL, originProfile: profile,
            requestHeaders: session.requiredHeaders).admitsDestination(URL(string: "https://643t8a.7odxv0l067ka.net:8443/segment.ts")!))
        XCTAssertNil(profile.validated(for: URL(string: session.playableURL.absoluteString
            .replacingOccurrences(of: "/api/manifest.m3u8?", with: "/api/manifest?"))!, headers: session.requiredHeaders))
        for target in ["https://other.example:8443/live.m3u8", "http://643t8a.7odxv0l067ka.net:8443/live.m3u8"] {
            XCTAssertTrue(reviewed8443Sessions([try reviewed8443Entry(upstream: target,
                delivery: "https://nuviosports.xyz/api/manifest.m3u8")]).isEmpty)
        }
        XCTAssertTrue(reviewed8443Sessions([directFancodeEntry(url: entry.url!, sourceHint: "daddylive", headers: nil)]).isEmpty)
    }

    private func directFancodeSessions(
        _ entries: [CommunitySportsStreamEntry], manifest: String = "https://nuviosports.xyz/manifest.json"
    ) -> [StreamSession] {
        CommunitySportsAddonClient.makeSessions(from: entries,
            request: makeRequest(home: "Afghanistan", away: "Zimbabwe", category: "cricket"),
            manifestURL: URL(string: manifest)!, addOnVersion: "3.1.3")
    }

    func testSixChoiceCapRetainsLateIndependentUpstreamsAndTheirRuntimeProfiles() throws {
        let dominant = try (0..<10).map { index in
            try reviewed8443Entry(upstream: "https://643t8a.7odxv0l067ka.net:8443/live/variant-\(index).m3u8")
        }
        let streamed = try (0..<2).map { index in
            try fairCapEntry(sourceHint: "streamedpk", upstream: "https://lb1.strmd.st/live/streamed-\(index).m3u8?st=fixture")
        }
        let tim = try (0..<2).map { index in
            try fairCapEntry(sourceHint: "timstreams", upstream: "https://lb1.strmd.st/live/tim-\(index).m3u8?st=fixture")
        }
        let sessions = reviewed8443Sessions(dominant + streamed + tim)

        XCTAssertEqual(sessions.count, 6)
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2", "CS3", "CS4", "CS5", "CS6"])
        XCTAssertEqual(sessions.map { $0.playableURL.absoluteString },
                       (Array(dominant.prefix(4)) + [streamed[0], tim[0]]).compactMap(\.url))
        XCTAssertEqual(sessions.map { $0.diagnosticMetadata["source_hint"] },
                       ["daddylive", "daddylive", "daddylive", "daddylive", "streamedpk", "timstreams"])
        XCTAssertTrue(sessions.prefix(4).allSatisfy { $0.nativeOriginProfile != nil })
        XCTAssertTrue(sessions.suffix(2).allSatisfy { $0.nativePlaylistProfile != nil && $0.requiresLocalProxy })
        XCTAssertEqual(Set(sessions.compactMap { $0.diagnosticMetadata["source_key"] }).count, 3)
    }

    func testAtMostSixAdmittedDeliveriesKeepOriginalOrderAndLabels() throws {
        let entries = try ["daddylive", "daddylive", "streamedpk", "daddylive", "timstreams", "other-source"]
            .enumerated().map { index, hint in
                try fairCapEntry(sourceHint: hint, upstream: "https://lb1.strmd.st/live/variant-\(index).m3u8?st=fixture")
            }
        let sessions = reviewed8443Sessions(entries)
        XCTAssertEqual(sessions.map { $0.playableURL.absoluteString }, entries.compactMap(\.url))
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2", "CS3", "CS4", "CS5", "CS6"])
    }

    func testFairCapDeduplicatesOnlyIdenticalDeliveryAndPreservesSignedAndHeaderVariants() throws {
        let first = try fairCapEntry(sourceHint: "streamedpk", upstream: "https://lb1.strmd.st/live/master.m3u8?st=one",
                                     headers: ["User-Agent": "Fixture One"])
        let headers = try fairCapEntry(sourceHint: "streamedpk", upstream: "https://lb1.strmd.st/live/master.m3u8?st=one",
                                       headers: ["User-Agent": "Fixture Two"])
        let signed = try fairCapEntry(sourceHint: "streamedpk", upstream: "https://lb1.strmd.st/live/master.m3u8?st=two",
                                      headers: ["User-Agent": "Fixture One"])
        let other = try fairCapEntry(sourceHint: "timstreams", upstream: "https://lb1.strmd.st/live/other.m3u8?st=one")
        let sessions = reviewed8443Sessions([first, first, headers, signed, signed, other])
        XCTAssertEqual(sessions.count, 4)
        XCTAssertEqual(sessions.map { $0.playableURL.absoluteString }, [first, headers, signed, other].compactMap(\.url))
        XCTAssertEqual(sessions.map(\.requiredHeaders), [["User-Agent": "Fixture One"], ["User-Agent": "Fixture Two"],
                                                        ["User-Agent": "Fixture One"], [:]])
        XCTAssertEqual(Set(sessions.prefix(3).compactMap { $0.diagnosticMetadata["source_key"] }).count, 1)
        XCTAssertTrue(sessions.allSatisfy { $0.nativePlaylistProfile != nil })
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2", "CS3", "CS4"])
    }

    func testFairCapRunsAfterAdmissionAndDoesNotReadBeyondHundredInputEntries() throws {
        let invalid = CommunitySportsStreamEntry(name: nil, title: nil,
            url: "https://other.example/api/manifest", externalURL: nil,
            resolution: nil, quality: nil, sourceHint: "streamedpk")
        let dominant = try (0..<7).map { index in
            try fairCapEntry(sourceHint: "daddylive", upstream: "https://lb1.strmd.st/live/variant-\(index).m3u8")
        }
        let alternative = try fairCapEntry(sourceHint: "streamedpk", upstream: "https://lb1.strmd.st/live/alternative.m3u8")
        let admitted = reviewed8443Sessions([invalid] + dominant + [alternative])
        XCTAssertEqual(admitted.count, 6)
        XCTAssertEqual(admitted.last?.playableURL.absoluteString, alternative.url)
        XCTAssertNotNil(admitted.last?.nativePlaylistProfile)

        let bounded = reviewed8443Sessions(Array(repeating: dominant[0], count: 100) + [alternative])
        XCTAssertEqual(bounded.count, 1)
        XCTAssertEqual(bounded.first?.playableURL.absoluteString, dominant[0].url)

        let distinct = try (0..<8).map { index in
            try fairCapEntry(sourceHint: "unknown", upstream: "https://lb1.strmd.st/live/distinct-\(index).m3u8")
        }
        XCTAssertEqual(reviewed8443Sessions(distinct).map { $0.playableURL.absoluteString },
                       distinct.prefix(6).compactMap(\.url))
    }

    private func fairCapEntry(sourceHint: String, upstream: String,
                              headers: [String: String] = [:]) throws -> CommunitySportsStreamEntry {
        var parts = try XCTUnwrap(URLComponents(string: "https://nuviosports.xyz/api/manifest"))
        parts.queryItems = [URLQueryItem(name: "url", value: upstream)]
        return CommunitySportsStreamEntry(name: nil, title: nil, url: try XCTUnwrap(parts.url).absoluteString,
            externalURL: nil, resolution: nil, quality: nil, sourceHint: sourceHint,
            behaviorHints: headers.isEmpty ? nil : .init(proxyHeaders: .init(request: headers)))
    }

    func testHeaderlessReviewedPlaylistProfileSurvivesAdapterAndNativeSourceOnlyAtRuntime() throws {
        var delivery = try XCTUnwrap(URLComponents(string: "https://nuviosports.xyz/api/manifest"))
        delivery.queryItems = [URLQueryItem(name: "url", value: "https://lb1.strmd.st/live/master.m3u8?st=fixture")]
        let document: [String: String] = ["url": try XCTUnwrap(delivery.url).absoluteString, "_source": "streamedpk"]
        let entry = try JSONDecoder().decode(CommunitySportsStreamEntry.self,
                                             from: JSONSerialization.data(withJSONObject: document))
        let sessions = CommunitySportsAddonClient.makeSessions(from: [entry],
            request: makeRequest(home: "Chelsea", away: "Brighton", category: "football"),
            manifestURL: URL(string: "https://nuviosports.xyz/manifest.json")!, addOnVersion: "fixture")
        let session = try XCTUnwrap(sessions.first)
        XCTAssertTrue(session.requiredHeaders.isEmpty)
        XCTAssertNotNil(session.nativePlaylistProfile)
        XCTAssertTrue(session.requiresLocalProxy)
        let source = session.legacySource.mergingHeaders([:])
        XCTAssertNotNil(source.nativePlaylistProfile)
        XCTAssertTrue(source.requiresLocalProxy)
        XCTAssertNil(source.mergingHeaders(["User-Agent": "changed"]).nativePlaylistProfile)
        let decoded = try JSONDecoder().decode(StreamSession.self, from: JSONEncoder().encode(session))
        XCTAssertNil(decoded.nativePlaylistProfile, "A saved session must resolve the reviewed contract again")
        XCTAssertFalse(decoded.requiresLocalProxy)
    }

    func testDecodedPublicProxyHeadersSurviveNativeSessionAndLegacySource() throws {
        let headers = ["Referer": "https://embed.example/player", "Origin": "https://embed.example",
                       "User-Agent": "Mozilla/5.0 (public player)"]
        let entry = try decodedHeaderEntry(headers: headers)
        let session = try XCTUnwrap(headerSessions([entry]).first)
        XCTAssertEqual(session.requiredHeaders, headers)
        XCTAssertEqual(session.legacySource.headers, headers)
        XCTAssertTrue(session.requiresLocalProxy)
        XCTAssertEqual(session.streamType, .hls)
        XCTAssertEqual(session.providerName, "CS1")
        XCTAssertFalse(session.diagnosticMetadata.values.contains(headers["Referer"]!))
    }

    func testVerifiedDaddyLiveProfilePropagatesWithoutRenumberingSourcesOrChangingAttribution() throws {
        let entry = try reviewed8443Entry()
        let plain = CommunitySportsStreamEntry(name: nil, title: nil,
            url: "https://nuviosports.xyz/api/manifest?fixture=other", externalURL: nil,
            resolution: nil, quality: nil, sourceHint: "source-b")
        let sessions = reviewed8443Sessions([entry, plain])
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2"])
        let session = try XCTUnwrap(sessions.first)
        XCTAssertNotNil(session.nativeOriginProfile)
        XCTAssertNotNil(session.legacySource.nativeOriginProfile)
        XCTAssertNotNil(session.legacySource.mergingHeaders([:]).nativeOriginProfile)
        XCTAssertNil(session.legacySource.mergingHeaders(["User-Agent": "changed-player"]).nativeOriginProfile)
        XCTAssertNil(sessions.last?.nativeOriginProfile)
        XCTAssertEqual(session.diagnosticMetadata["source_hint"], "daddylive")
        XCTAssertEqual(session.diagnosticMetadata["source_key_scope"], "upstream")
        XCTAssertTrue(session.requiresLocalProxy)
        XCTAssertFalse(session.diagnosticMetadata.values.contains { $0.contains("643t8a") || $0.contains("8443") })
    }

    func testCSProfileRequiresReviewedAttributionRouteUniqueQueryAndPinnedOrigin() throws {
        let good = try reviewed8443Entry()
        XCTAssertNotNil(reviewed8443Sessions([good]).first?.nativeOriginProfile)
        for source in ["other-provider", "unknown", "https://daddylive.invalid"] {
            XCTAssertNil(reviewed8443Sessions([try reviewed8443Entry(sourceHint: source)]).first?.nativeOriginProfile)
        }
        for target in ["https://other.example.net:8443/live.m3u8", "https://643t8a.7odxv0l067ka.net:9443/live.m3u8",
                       "http://643t8a.7odxv0l067ka.net:8443/live.m3u8", "https://127.0.0.1:8443/live.m3u8",
                       "https://user:secret@643t8a.7odxv0l067ka.net:8443/live.m3u8",
                       "https://643t8a.7odxv0l067ka.net:8443/live.m3u8#fragment"] {
            XCTAssertNil(reviewed8443Sessions([try reviewed8443Entry(upstream: target)]).first?.nativeOriginProfile, target)
        }
        let duplicate = try reviewed8443Entry(extraQuery: [URLQueryItem(name: "URL", value: "https://643t8a.7odxv0l067ka.net:8443/other.m3u8")])
        XCTAssertNil(reviewed8443Sessions([duplicate]).first?.nativeOriginProfile)
        let wrongRoute = try reviewed8443Entry(delivery: "https://nuviosports.xyz/watch")
        XCTAssertTrue(reviewed8443Sessions([wrongRoute]).isEmpty)
        let wrongManifest = URL(string: "https://nuviosports.xyz/not-reviewed/manifest.json")!
        XCTAssertNil(LocalStreamProxyOriginProfile.communitySports(deliveryURL: URL(string: good.url!)!,
            manifestURL: wrongManifest, sourceHint: good.sourceHint,
            headers: good.behaviorHints?.proxyHeaders?.request ?? [:]))
        XCTAssertNil(LocalStreamProxyOriginProfile.communitySports(deliveryURL: URL(string: good.url!)!,
            manifestURL: URL(string: "https://addon.example/manifest.json")!, sourceHint: good.sourceHint,
            headers: good.behaviorHints?.proxyHeaders?.request ?? [:]))
    }

    func testExceptionalAuthorityCannotBeSerializedRestoredOrForgedBySessionJSON() throws {
        let session = try XCTUnwrap(reviewed8443Sessions([try reviewed8443Entry()]).first)
        let data = try JSONEncoder().encode(session)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(document["nativeOriginProfile"])
        let decoded = try JSONDecoder().decode(StreamSession.self, from: data)
        XCTAssertNil(decoded.nativeOriginProfile)
        XCTAssertNil(decoded.legacySource.nativeOriginProfile)
        XCTAssertEqual(decoded.requiredHeaders, session.requiredHeaders)
        XCTAssertEqual(decoded.diagnosticMetadata, session.diagnosticMetadata)
        document["nativeOriginProfile"] = ["host": "643t8a.7odxv0l067ka.net", "port": 8443,
                                            "deliveryBinding": String(repeating: "a", count: 64)]
        let forged = try JSONDecoder().decode(StreamSession.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertNil(forged.nativeOriginProfile)
        let target = URL(string: "https://643t8a.7odxv0l067ka.net:8443/segment.ts")!
        XCTAssertFalse(LocalStreamProxyPolicy(selectedMediaURL: forged.playableURL,
                                              originProfile: forged.nativeOriginProfile,
                                              requestHeaders: forged.requiredHeaders).admitsDestination(target))
    }

    func testProfileRuntimeBindingRejectsReplacedURLAndChangedHeaderIdentity() throws {
        let session = try XCTUnwrap(reviewed8443Sessions([try reviewed8443Entry()]).first)
        var delivery = try XCTUnwrap(URLComponents(url: session.playableURL, resolvingAgainstBaseURL: false))
        delivery.queryItems?.append(URLQueryItem(name: "session", value: "replacement"))
        let replaced = StreamSource(url: try XCTUnwrap(delivery.url), quality: "auto", provider: "CS1",
                                    headers: session.requiredHeaders, nativeOriginProfile: session.nativeOriginProfile)
        XCTAssertNil(replaced.nativeOriginProfile)
        var headers = session.requiredHeaders
        headers["Authorization"] = "untrusted"
        let altered = StreamSession(matchID: "another-fixture", playableURL: session.playableURL,
                                    streamType: .hls, providerName: "CS1", requiredHeaders: headers,
                                    nativeOriginProfile: session.nativeOriginProfile)
        XCTAssertNil(altered.nativeOriginProfile)
        let arbitrary = StreamSession(matchID: "fixture", playableURL: session.playableURL, streamType: .hls,
                                      providerName: "CS1", requiredHeaders: session.requiredHeaders,
                                      diagnosticMetadata: session.diagnosticMetadata)
        XCTAssertNil(arbitrary.nativeOriginProfile, "Source labels/diagnostic strings cannot mint authority")
    }

    private func reviewed8443Entry(upstream: String = "https://643t8a.7odxv0l067ka.net:8443/live/master.m3u8",
                                   sourceHint: String = "daddylive", delivery: String = "https://nuviosports.xyz/api/manifest",
                                   extraQuery: [URLQueryItem] = []) throws -> CommunitySportsStreamEntry {
        let headers = ["Referer": "https://embed.example/player", "Origin": "https://embed.example", "User-Agent": "Fixture Player"]
        var parts = try XCTUnwrap(URLComponents(string: delivery))
        parts.queryItems = [URLQueryItem(name: "url", value: upstream),
                            URLQueryItem(name: "referer", value: headers["Referer"]),
                            URLQueryItem(name: "origin", value: headers["Origin"])] + extraQuery
        return CommunitySportsStreamEntry(name: nil, title: nil, url: try XCTUnwrap(parts.url).absoluteString,
            externalURL: nil, resolution: "HD", quality: nil, sourceHint: sourceHint,
            behaviorHints: .init(proxyHeaders: .init(request: headers)))
    }

    private func reviewed8443Sessions(_ entries: [CommunitySportsStreamEntry]) -> [StreamSession] {
        CommunitySportsAddonClient.makeSessions(from: entries,
            request: makeRequest(home: "Chelsea", away: "Brighton", category: "football"),
            manifestURL: URL(string: "https://nuviosports.xyz/manifest.json")!, addOnVersion: "3.1.3")
    }

    func testHeaderContractRetainsNoHintRoutesAndDeliveryDeduplication() throws {
        let plain = try decodedHeaderEntry(headers: nil)
        let first = try decodedHeaderEntry(headers: ["User-Agent": "public-a"])
        let second = try decodedHeaderEntry(headers: ["User-Agent": "public-b"])
        let sessions = headerSessions([plain, first, first, second])
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2", "CS3"])
        XCTAssertEqual(sessions[0].requiredHeaders, [:])
        XCTAssertFalse(sessions[0].requiresLocalProxy)
        XCTAssertEqual(sessions[1].requiredHeaders, ["User-Agent": "public-a"])
        XCTAssertEqual(sessions[2].requiredHeaders, ["User-Agent": "public-b"])
    }

    func testOnlyPublicThreeHeaderRequestContractIsAdmitted() throws {
        for name in ["Cookie", "Authorization", "Proxy-Authorization", "Host", "X-API-Key", "X-Fotty-Web-Embed"] {
            XCTAssertTrue(headerSessions([try decodedHeaderEntry(headers: [name: "untrusted"]) ]).isEmpty, name)
        }
        let duplicated = try decodedHeaderEntry(headers: ["User-Agent": "one", "user-agent": "two"])
        XCTAssertTrue(headerSessions([duplicated]).isEmpty)
        let response = try decodedHeaderEntry(headers: [:], responseHeaders: ["Access-Control-Allow-Origin": "*"])
        XCTAssertTrue(headerSessions([response]).isEmpty)
    }

    func testHeaderValuesRejectControlUnicodeAndOversizedInput() throws {
        for value in ["", "public\r\nCookie: secret", "public\0agent", "public\u{7f}", "public🟢", String(repeating: "a", count: 513)] {
            XCTAssertTrue(headerSessions([try decodedHeaderEntry(headers: ["User-Agent": value])]).isEmpty)
        }
        let accepted = try decodedHeaderEntry(headers: ["user-agent": String(repeating: "a", count: 512)])
        XCTAssertEqual(headerSessions([accepted]).first?.requiredHeaders["User-Agent"]?.count, 512)
    }

    func testProvenanceRequiresSafeHTTPSAndExactUnambiguousQueryAgreement() throws {
        let unsafe = ["http://embed.example/player", "https://127.0.0.1/player", "https://localhost/player",
                      "https://169.254.169.254/player", "https://[::ffff:127.0.0.1]/player",
                      "https://embed.example:444/player", "https://user:pass@embed.example/player",
                      "https://embed.example/player?token=private", "https://embed.example/player#fragment"]
        for value in unsafe {
            XCTAssertTrue(headerSessions([try decodedHeaderEntry(headers: ["Referer": value], referer: value)]).isEmpty, value)
        }
        let mismatch = try decodedHeaderEntry(headers: ["Referer": "https://other.example/player"])
        XCTAssertTrue(headerSessions([mismatch]).isEmpty)
        let duplicate = try decodedHeaderEntry(headers: ["Referer": "https://embed.example/player"],
                                                extraQuery: [URLQueryItem(name: "REFERER", value: "https://embed.example/player")])
        XCTAssertTrue(headerSessions([duplicate]).isEmpty)
        let missing = try decodedHeaderEntry(headers: ["Origin": "https://embed.example"], origin: nil)
        XCTAssertTrue(headerSessions([missing]).isEmpty)
    }

    func testOriginMustBeRootAndAgreeWithRefererOrigin() throws {
        let path = try decodedHeaderEntry(headers: ["Origin": "https://embed.example/player"],
                                           origin: "https://embed.example/player")
        XCTAssertTrue(headerSessions([path]).isEmpty)
        let conflicting = try decodedHeaderEntry(headers: ["Referer": "https://embed.example/player", "Origin": "https://other.example"],
                                                  origin: "https://other.example")
        XCTAssertTrue(headerSessions([conflicting]).isEmpty)
    }

    func testMalformedAdvertisedHeaderContractsCannotBecomeAbsentHeaders() throws {
        let malformedValues: [Any] = [NSNull(), "not-an-object", ["User-Agent": 7]]
        for malformed in malformedValues {
            let document: [String: Any] = ["url": "https://addon.example/api/manifest",
                                          "behaviorHints": ["proxyHeaders": ["request": malformed]]]
            let data = try JSONSerialization.data(withJSONObject: document)
            XCTAssertThrowsError(try JSONDecoder().decode(CommunitySportsStreamEntry.self, from: data))
        }
    }

    func testHeadersNeverBroadenDeliveryOriginPathOrWebAdmission() throws {
        let headers = ["User-Agent": "public-player"]
        for url in ["https://other.example/api/manifest", "https://addon.example/api/other", "https://addon.example/watch"] {
            let entry = try decodedHeaderEntry(headers: headers, delivery: url)
            XCTAssertTrue(headerSessions([entry]).isEmpty, url)
        }
    }

    private func decodedHeaderEntry(headers: [String: String]?,
                                    responseHeaders: [String: String]? = nil,
                                    referer: String? = "https://embed.example/player",
                                    origin: String? = "https://embed.example",
                                    extraQuery: [URLQueryItem] = [],
                                    delivery: String = "https://addon.example/api/manifest") throws -> CommunitySportsStreamEntry {
        var url = try XCTUnwrap(URLComponents(string: delivery))
        url.queryItems = [URLQueryItem(name: "url", value: "https://video.example/live.m3u8")]
        if let referer { url.queryItems?.append(URLQueryItem(name: "referer", value: referer)) }
        if let origin { url.queryItems?.append(URLQueryItem(name: "origin", value: origin)) }
        url.queryItems?.append(contentsOf: extraQuery)
        var document: [String: Any] = ["url": try XCTUnwrap(url.url).absoluteString, "_source": "known-upstream"]
        if headers != nil || responseHeaders != nil {
            var proxy: [String: Any] = [:]
            if let headers { proxy["request"] = headers }
            if let responseHeaders { proxy["response"] = responseHeaders }
            document["behaviorHints"] = ["proxyHeaders": proxy]
        }
        return try JSONDecoder().decode(CommunitySportsStreamEntry.self,
                                         from: JSONSerialization.data(withJSONObject: document))
    }

    private func headerSessions(_ entries: [CommunitySportsStreamEntry]) -> [StreamSession] {
        CommunitySportsAddonClient.makeSessions(from: entries,
            request: makeRequest(home: "Chelsea", away: "Brighton", category: "football"),
            manifestURL: URL(string: "https://addon.example/manifest.json")!, addOnVersion: "3.1.3")
    }

    func testExactSportPairAndKickoffMatchIsAdmittedRegardlessOfProviderOrder() {
        let request = makeRequest(home: "Athletics", away: "Seattle Mariners", category: "baseball")
        let entry = makeEntry(
            id: "nuvio_sport_game-1",
            name: "🔴 LIVE: Seattle Mariners vs Athletics",
            released: "2026-09-13T20:05:00.000Z",
            genre: "BASEBALL",
            cast: ["Athletics", "Seattle Mariners"]
        )

        XCTAssertEqual(
            CommunitySportsAddonClient.selectMatch(for: request, from: [entry]),
            .matched(entry)
        )
    }

    func testWrongSportPartialIdentityAndWrongKickoffAreRejected() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let wrongSport = makeEntry(
            id: "nuvio_sport_game-1",
            name: "Chelsea vs Brighton",
            released: "2026-09-13T20:05:00.000Z",
            genre: "CRICKET",
            cast: ["Chelsea", "Brighton"]
        )
        let partialPair = makeEntry(
            id: "nuvio_sport_game-2",
            name: "Chelsea vs Fulham",
            released: "2026-09-13T20:05:00.000Z",
            genre: "FOOTBALL",
            cast: ["Chelsea", "Fulham"]
        )
        let wrongTime = makeEntry(
            id: "nuvio_sport_game-3",
            name: "Chelsea vs Brighton",
            released: "2026-09-13T20:25:01.000Z",
            genre: "FOOTBALL",
            cast: ["Chelsea", "Brighton"]
        )

        XCTAssertEqual(
            CommunitySportsAddonClient.selectMatch(
                for: request,
                from: [wrongSport, partialPair, wrongTime]
            ),
            .missing
        )
    }

    func testEvertonAndHullReviewedLegalNamesMatchPlainCatalogNamesInEitherDirection() {
        for (requestTeams, catalogTeams) in [
            (["Hull City AFC", "Everton FC"], ["Hull City", "Everton"]),
            (["Everton", "Hull City"], ["Hull City AFC", "Everton FC"]),
            (["Hull", "Everton"], ["Everton FC", "Hull City AFC"])
        ] {
            let request = makeRequest(home: requestTeams[0], away: requestTeams[1], category: "football")
            let entry = makeEntry(id: "nuvio_sport_everton-hull", name: catalogTeams.joined(separator: " vs "),
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: catalogTeams)
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .matched(entry))
        }
    }

    func testFootballLegalNameMatchingDoesNotCollapseWomenYouthOrReserveSquads() {
        let senior = makeEntry(id: "nuvio_sport_senior", name: "Hull City vs Everton",
                               released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Hull City", "Everton"])
        let request = makeRequest(home: "Hull City AFC", away: "Everton FC", category: "football")
        for suffix in ["Women", "W", "Ladies", "U19", "Under 21", "U17", "Reserves", "Academy"] {
            let teams = ["Hull City AFC \(suffix)", "Everton FC \(suffix)"]
            let squad = makeEntry(id: "nuvio_sport_squad", name: teams.joined(separator: " vs "),
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: teams)
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [squad]), .missing, suffix)
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
                for: makeRequest(home: teams[0], away: teams[1], category: "football"), from: [senior]), .missing, suffix)
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
                for: makeRequest(home: teams[0], away: teams[1], category: "football"), from: [squad]), .matched(squad), suffix)
        }
    }

    func testTitleOnlySquadEvidenceCannotBecomeASeniorFixtureThroughUnqualifiedCast() {
        let senior = makeRequest(home: "RB Leipzig", away: "Bayern Munich", category: "football")
        for suffix in ["W", "Women", "Ladies", "U19", "Under 21", "Reserves", "Academy"] {
            let entry = makeEntry(id: "nuvio_sport_title-squad", name: "RB Leipzig \(suffix) vs Bayern Munich \(suffix)",
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                  cast: ["Bayern", "Leipzig"])
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: senior, from: [entry]), .missing, suffix)
            let correct = makeRequest(home: "Leipzig \(suffix)", away: "Bayern \(suffix)", category: "football")
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: correct, from: [entry]), .matched(entry), suffix)
        }
    }

    func testIndependentCastSquadEvidenceAndWomensSpellingSurviveTitleOrderAndReviewedAliases() {
        let request = makeRequest(home: "RB Leipzig Women", away: "Bayern Munich Women", category: "football")
        let castQualified = makeEntry(id: "nuvio_sport_cast-squad", name: "Bayern Munich vs RB Leipzig",
                                      released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                      cast: ["Leipzig W", "Bayern W"])
        let bothQualified = makeEntry(id: "nuvio_sport_both-squad", name: "Bayern W vs Leipzig W",
                                      released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                      cast: ["RB Leipzig Women", "Bayern Munich Women"])
        for entry in [castQualified, bothQualified] {
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .matched(entry))
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
                for: makeRequest(home: "RB Leipzig", away: "Bayern Munich", category: "football"), from: [entry]), .missing)
        }
    }

    func testParsedTitleCastParticipantOrExplicitSquadContradictionsAreRejected() {
        let castRequest = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let wrongParticipants = makeEntry(id: "nuvio_sport_contradictory-title", name: "Arsenal vs Tottenham",
                                          released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                          cast: ["Chelsea", "Brighton"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: castRequest, from: [wrongParticipants]), .missing)
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
            for: makeRequest(home: "Arsenal", away: "Tottenham", category: "football"), from: [wrongParticipants]), .missing)
        for titleSuffix in ["U19", "Reserves", "Academy"] {
            let wrongSquad = makeEntry(id: "nuvio_sport_contradictory-squad",
                                       name: "Brighton \(titleSuffix) vs Chelsea \(titleSuffix)",
                                       released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                       cast: ["Chelsea Women", "Brighton Women"])
            for suffix in ["Women", titleSuffix] {
                XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
                    for: makeRequest(home: "Chelsea \(suffix)", away: "Brighton \(suffix)", category: "football"),
                    from: [wrongSquad]), .missing)
            }
        }
    }

    func testRequestTitleSquadEvidenceIsNotLostWhenItsTeamFieldsAreUnqualified() {
        let request = StreamPlaybackRequest(matchID: "title-qualified-request", displayTitle: "Chelsea W vs Brighton W",
            homeTeam: "Chelsea", awayTeam: "Brighton", category: "football", kickoffDate: kickoff)
        let women = makeEntry(id: "nuvio_sport_women", name: "Chelsea Women vs Brighton Women",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Chelsea", "Brighton"])
        let senior = makeEntry(id: "nuvio_sport_senior", name: "Chelsea vs Brighton",
                               released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Chelsea", "Brighton"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [women]), .matched(women))
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [senior]), .missing)
    }

    @MainActor
    func testObservedOfficialAfghanistanZimbabweProjectionMatchesCSWithoutParsingCompetitionCopyAsATeam() throws {
        // Observed native/CS metadata on23Oct2026, not an archived provider
        // response or a claim that its streams continue to play.
        let event = try observedAfghanistanZimbabweProjection()
        let entry = observedAfghanistanZimbabweCSEntry()
        let request = StreamPlaybackRequest(event: event)
        XCTAssertEqual(event.id, "cricket-fixture:icc:274659")
        XCTAssertEqual(request.displayTitle,
            "ODI Tri-Series in United Arab Emirates, 2026 · Afghanistan vs Zimbabwe")
        XCTAssertEqual(event.displayTitle, "Afghanistan vs Zimbabwe")
        XCTAssertEqual(request.kickoffDate, CricketFixtureCatalog.date("2026-10-23T11:30:00.000Z"))
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .matched(entry))
    }

    @MainActor
    func testOfficialProjectionRequestTitleBypassRequiresExactRequestAndVerifiedCanonicalIdentity() throws {
        let original = try observedAfghanistanZimbabweProjection()
        let receipt = try XCTUnwrap(original.cricketFixture)
        let entry = observedAfghanistanZimbabweCSEntry()
        for change in ["id", "sport", "home", "away", "time", "unverified", "noncanonical", "conflict", "missing-teams"] {
            let metadata = CricketFixtureMetadata(fixtureID: receipt.fixtureID, competitionID: receipt.competitionID,
                competitionName: receipt.competitionName, format: receipt.format, status: receipt.status,
                observedAt: receipt.observedAt, verified: change != "unverified")
            let event = EventReference(id: change == "noncanonical" ? "provider-unverified-id" : original.id,
                title: original.title, category: original.category, date: original.date, poster: nil, popular: false,
                teams: change == "missing-teams" ? nil : original.teams, sources: [],
                hasCatalogIdentityConflict: change == "conflict", cricketFixture: metadata)
            let request = StreamPlaybackRequest(matchID: change == "id" ? "other-request-id" : event.id,
                displayTitle: try XCTUnwrap(original.title), homeTeam: change == "home" ? "India" : "Afghanistan",
                awayTeam: change == "away" ? "Ireland" : "Zimbabwe", category: change == "sport" ? "football" : "cricket",
                kickoffDate: original.kickoffDate?.addingTimeInterval(change == "time" ? 1 : 0), preferredEvent: event)
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .missing, change)
        }
    }

    @MainActor
    func testTrustedPreferredFixtureCannotEraseAnAdversarialRequestTitleOrCompetitionSquadConflict() throws {
        let event = try observedAfghanistanZimbabweProjection()
        let entry = observedAfghanistanZimbabweCSEntry()
        for title in ["Afghanistan W vs Zimbabwe W", "Afghanistan U19 vs Zimbabwe U19",
                      "Afghanistan vs Zimbabwe | Women's competition"] {
            let request = StreamPlaybackRequest(matchID: event.id, displayTitle: title,
                homeTeam: "Afghanistan", awayTeam: "Zimbabwe", category: "cricket",
                kickoffDate: event.kickoffDate, preferredEvent: event)
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .missing, title)
        }
        let original = try XCTUnwrap(event.cricketFixture)
        let metadata = CricketFixtureMetadata(fixtureID: original.fixtureID, competitionID: original.competitionID,
            competitionName: "Women's international cricket", format: original.format, status: original.status,
            observedAt: original.observedAt, verified: true)
        let conflicting = EventReference(id: event.id,
            title: "Women's international cricket · Afghanistan vs Zimbabwe", category: "cricket", date: event.date,
            poster: nil, popular: false, teams: event.teams, sources: [], cricketFixture: metadata)
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
            for: StreamPlaybackRequest(event: conflicting), from: [entry]), .missing)
    }

    func testAmbiguousPairTitleDoesNotTurnCompetitionSuffixIntoSquadEvidenceOrIgnoreIt() {
        for title in ["Chelsea vs Brighton - Women's Super League", "Chelsea vs Brighton | Women",
                      "Chelsea vs Brighton (U19)", "Chelsea vs Brighton vs Arsenal"] {
            let entry = makeEntry(id: "nuvio_sport_ambiguous-title", name: title,
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Chelsea", "Brighton"])
            for suffix in ["", " Women", " U19"] {
                XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
                    for: makeRequest(home: "Chelsea\(suffix)", away: "Brighton\(suffix)", category: "football"),
                    from: [entry]), .missing, title)
            }
        }
        let generic = makeEntry(id: "nuvio_sport_cast-authority", name: "Featured football broadcast",
                                released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Chelsea", "Brighton"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(
            for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"), from: [generic]), .matched(generic))
    }

    func testFootballLegalNamesStillRequireBothTeamsSportAndKickoffWindow() {
        let request = makeRequest(home: "Hull City AFC", away: "Everton FC", category: "football")
        let partial = makeEntry(id: "nuvio_sport_other", name: "Hull City vs Chelsea",
                                released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Hull City", "Chelsea"])
        let wrongSport = makeEntry(id: "nuvio_sport_sport", name: "Hull City vs Everton",
                                   released: "2026-09-13T20:05:00Z", genre: "CRICKET", cast: ["Hull City", "Everton"])
        let outsideWindow = makeEntry(id: "nuvio_sport_late", name: "Hull City vs Everton",
                                      released: "2026-09-13T20:20:01Z", genre: "FOOTBALL", cast: ["Hull City", "Everton"])
        let boundary = makeEntry(id: "nuvio_sport_boundary", name: "Hull City vs Everton",
                                 released: "2026-09-13T20:20:00Z", genre: "FOOTBALL", cast: ["Hull City", "Everton"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [partial, wrongSport, outsideWindow]), .missing)
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [boundary]), .matched(boundary))
    }

    func testUnknownFootballNamesDoNotGainUnreviewedLegalAliases() {
        let request = makeRequest(home: "Unreviewed Town FC", away: "Unreviewed Rovers AFC", category: "football")
        let entry = makeEntry(id: "nuvio_sport_unknown", name: "Unreviewed Town vs Unreviewed Rovers",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Unreviewed Town", "Unreviewed Rovers"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .missing)
    }

    func testFootballLegalTokenNormalizationDoesNotApplyToOtherSports() {
        let request = makeRequest(home: "Hull City AFC", away: "Everton FC", category: "cricket")
        let entry = makeEntry(id: "nuvio_sport_cricket", name: "Hull City vs Everton",
                              released: "2026-09-13T20:05:00Z", genre: "CRICKET", cast: ["Hull City", "Everton"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .missing)
    }

    func testEquivalentLegalNamesDoNotEraseConflictingFixtureIDsOrSquads() {
        let request = makeRequest(home: "Hull City AFC", away: "Everton FC", category: "football")
        let plain = makeEntry(id: "nuvio_sport_shared", name: "Hull City vs Everton",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Hull City", "Everton"])
        let equivalent = makeEntry(id: "nuvio_sport_shared", name: "Everton FC vs Hull City AFC",
                                   released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Everton FC", "Hull City AFC"])
        let anotherID = makeEntry(id: "nuvio_sport_other-id", name: "Everton FC vs Hull City AFC",
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Everton FC", "Hull City AFC"])
        let squad = makeEntry(id: "nuvio_sport_shared", name: "Hull City Women vs Everton Women",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL", cast: ["Hull City Women", "Everton Women"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [plain, equivalent]), .matched(plain))
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [plain, anotherID]), .conflicting)
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [plain, squad]), .conflicting)
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [squad, plain]), .conflicting)
    }

    func testYouthFixtureCannotSubstituteForSeniorFixture() {
        let request = makeRequest(home: "Borussia Dortmund", away: "Villarreal", category: "football")
        let youth = makeEntry(
            id: "nuvio_sport_youth",
            name: "Borussia Dortmund U19 vs Villarreal U19",
            released: "2026-09-13T20:05:00.000Z",
            genre: "FOOTBALL",
            cast: ["Borussia Dortmund U19", "Villarreal U19"]
        )

        XCTAssertEqual(
            CommunitySportsAddonClient.selectMatch(for: request, from: [youth]),
            .missing
        )
    }

    func testMultipleExactProviderIDsAreRejectedAsConflicting() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let first = makeEntry(
            id: "nuvio_sport_game-1",
            name: "Chelsea vs Brighton",
            released: "2026-09-13T20:05:00.000Z",
            genre: "FOOTBALL",
            cast: ["Chelsea", "Brighton"]
        )
        let second = makeEntry(
            id: "nuvio_sport_game-2",
            name: "Brighton vs Chelsea",
            released: "2026-09-13T20:05:00.000Z",
            genre: "FOOTBALL",
            cast: ["Brighton", "Chelsea"]
        )

        XCTAssertEqual(
            CommunitySportsAddonClient.selectMatch(for: request, from: [first, second]),
            .conflicting
        )
    }

    func testReusedIDWithContradictoryFixtureCannotHideBehindRequestFiltering() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let exact = makeEntry(id: "nuvio_sport_shared", name: "Chelsea vs Brighton",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                              cast: ["Chelsea", "Brighton"])
        let other = makeEntry(id: "nuvio_sport_shared", name: "Arsenal vs Tottenham",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                              cast: ["Arsenal", "Tottenham"])
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [exact, other]), .conflicting)
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [other, exact]), .conflicting)
    }

    func testReusedIDWithDifferentStreamTargetIsConflictingButEquivalentDuplicatesAreAdmitted() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let first = makeEntry(id: "nuvio_sport_shared", name: "Chelsea vs Brighton",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                              cast: ["Chelsea", "Brighton"])
        let equivalent = makeEntry(id: "nuvio_sport_shared", name: "Brighton vs Chelsea",
                                   released: "2026-09-13T20:05:00.000Z", genre: "soccer",
                                   cast: ["Brighton", "Chelsea"])
        let redirected = makeEntry(id: "nuvio_sport_shared", name: "Chelsea vs Brighton",
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                  cast: ["Chelsea", "Brighton"], videoID: "nuvio_sport_other")
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [first, equivalent]), .matched(first))
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [first, redirected]), .conflicting)
    }

    func testDifferentMetadataIDsCannotClaimAConflictingSharedStreamTargetInEitherOrder() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let target = "nuvio_sport_shared-target"
        let exact = makeEntry(id: "nuvio_sport_exact", name: "Chelsea vs Brighton",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                              cast: ["Chelsea", "Brighton"], videoID: target)
        let conflicting = [
            makeEntry(id: "nuvio_sport_other", name: "Arsenal vs Tottenham", released: "2026-09-13T20:05:00Z",
                      genre: "FOOTBALL", cast: ["Arsenal", "Tottenham"], videoID: target),
            makeEntry(id: "nuvio_sport_other", name: "Chelsea vs Brighton", released: "2026-09-13T20:05:00Z",
                      genre: "CRICKET", cast: ["Chelsea", "Brighton"], videoID: target),
            makeEntry(id: "nuvio_sport_other", name: "Chelsea vs Brighton", released: "2026-09-14T20:05:00Z",
                      genre: "FOOTBALL", cast: ["Chelsea", "Brighton"], videoID: target),
            makeEntry(id: "nuvio_sport_other", name: "Chelsea W vs Brighton W", released: "2026-09-13T20:05:00Z",
                      genre: "FOOTBALL", cast: ["Chelsea", "Brighton"], videoID: target),
            CommunitySportsCatalogEntry(id: "nuvio_sport_other", type: "movie", name: "Chelsea vs Brighton",
                releaseInfo: nil, released: "2026-09-13T20:05:00Z", genres: ["FOOTBALL"], cast: ["Chelsea", "Brighton"],
                behaviorHints: .init(defaultVideoId: target))
        ]
        for other in conflicting {
            for entries in [[exact, other], [other, exact]] {
                XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: entries), .conflicting)
            }
        }
    }

    func testMalformedSharedTargetOrMetadataSiblingRemainsConflictEvidenceInEitherOrder() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let target = "nuvio_sport_shared-target"
        let exact = makeEntry(id: "nuvio_sport_exact", name: "Chelsea vs Brighton",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                              cast: ["Chelsea", "Brighton"], videoID: target)
        for id in [exact.id, "nuvio_sport_other"] {
            let malformed = [
                makeEntry(id: id, name: "Chelsea vs Brighton", released: "not-a-date", genre: "FOOTBALL",
                          cast: ["Chelsea", "Brighton"], videoID: target),
                makeEntry(id: id, name: "Chelsea vs Brighton", released: "2026-09-13T20:05:00Z", genre: "Unknown sport",
                          cast: ["Chelsea", "Brighton"], videoID: target),
                makeEntry(id: id, name: "Chelsea vs Brighton", released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                          cast: ["Arsenal", "Tottenham"], videoID: target),
                makeEntry(id: id, name: "Chelsea U19 vs Brighton U19", released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                          cast: ["Chelsea Women", "Brighton Women"], videoID: target),
                makeEntry(id: id, name: "Chelsea vs Brighton | Women's Super League", released: "2026-09-13T20:05:00Z",
                          genre: "FOOTBALL", cast: ["Chelsea", "Brighton"], videoID: target)
            ]
            for other in malformed {
                for entries in [[exact, other], [other, exact]] {
                    XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: entries), .conflicting)
                }
            }
        }
        let unrelatedMalformed = makeEntry(id: "nuvio_sport_unrelated", name: "Malformed unrelated listing",
            released: "not-a-date", genre: "FOOTBALL", cast: [], videoID: "nuvio_sport_unrelated-target")
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [unrelatedMalformed, exact]), .matched(exact))
    }

    func testSharedTargetDoesNotRelaxMultipleExactMetadataIDPolicyAndEquivalentSameIDRemainsSafe() {
        let request = makeRequest(home: "Hull City AFC Women", away: "Everton FC Women", category: "football")
        let target = "nuvio_sport_shared-target"
        let first = makeEntry(id: "nuvio_sport_exact", name: "Hull City W vs Everton W",
                              released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                              cast: ["Everton", "Hull City"], videoID: target)
        let sameID = makeEntry(id: first.id, name: "Everton FC Women vs Hull City AFC Women",
                               released: "2026-09-13T20:05:00.000Z", genre: "soccer",
                               cast: ["Hull City AFC Women", "Everton FC Women"], videoID: target)
        for entries in [[first, sameID], [sameID, first]] {
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: entries), .matched(entries[0]))
        }
        let anotherID = makeEntry(id: "nuvio_sport_another-id", name: sameID.name,
                                  released: "2026-09-13T20:05:00Z", genre: "FOOTBALL",
                                  cast: ["Hull City AFC Women", "Everton FC Women"], videoID: target)
        for entries in [[first, anotherID], [anotherID, first]] {
            XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: entries), .conflicting)
        }
    }

    func testConflictingEffectiveTargetStopsBeforeStreamLookupOrLiveFallback() async throws {
        let exact = catalogEntry(teams: ["Chelsea", "Brighton"])
        var other = catalogEntry(teams: ["Arsenal", "Tottenham"])
        other["id"] = "nuvio_sport_other-metadata-id"
        // The unchanged defaultVideoId still claims the exact row's route.
        let response = try CommunitySportsFixtureProtocol.Response.json(["metas": [exact, other]])
        let session = try makeFixtureSession(sportResponse: response)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Conflicting route claims must not request any stream")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch)
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths,
                       ["/manifest.json", "/catalog/tv/nuvio_sports_football.json"])
    }

    func testMissingSportCatalogFallsBackToExactLiveFixture() async throws {
        let session = try makeFixtureSession(includeSportCatalog: false)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)

        let result = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))

        XCTAssertEqual(result.map(\.providerName), ["CS1"])
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", "/catalog/tv/nuvio_sports_live.json", "/stream/tv/nuvio_sport_fixture.json"])
    }

    func testFailedSportCatalogFallsBackToExactLiveFixture() async throws {
        let session = try makeFixtureSession(sportResponse: .failure(URLError(.timedOut)))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)

        let result = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(CommunitySportsFixtureProtocol.paths.contains("/catalog/tv/nuvio_sports_live.json"))
    }

    func testFailedAdvertisedSportCatalogRetainsItsFailureWhenLiveHasNoExactFixture() async throws {
        let cases: [(CommunitySportsFixtureProtocol.Response, CommunitySportsAddonError)] = [
            (.status(503), .httpFailure(statusCode: 503, stage: .catalog)),
            (.failure(URLError(.timedOut)), .transportFailure(code: URLError.Code.timedOut.rawValue, stage: .catalog)),
            (.body(Data("not JSON".utf8)), .invalidJSON(stage: .catalog))
        ]
        for (response, expected) in cases {
            let session = try makeFixtureSession(sportResponse: response, liveResponse: .json(["metas": []]))
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
                XCTFail("An independently empty Live catalog must not erase an advertised catalog failure")
            } catch {
                XCTAssertEqual(error as? CommunitySportsAddonError, expected)
            }
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths,
                           ["/manifest.json", "/catalog/tv/nuvio_sports_football.json", "/catalog/tv/nuvio_sports_live.json"])
        }
    }

    func testUnadvertisedSportCatalogWithEmptyLiveRemainsAnOrdinaryMissingFixture() async throws {
        let session = try makeFixtureSession(includeSportCatalog: false, liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("There is no exact fixture in the advertised catalog")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound)
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths,
                       ["/manifest.json", "/catalog/tv/nuvio_sports_live.json"])
    }

    func testFallbackStillRejectsWrongLiveFixture() async throws {
        let session = try makeFixtureSession(includeSportCatalog: false, liveTeams: ["Chelsea", "Fulham"])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)

        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("A fallback catalog must not loosen exact fixture identity")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound)
        }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testCancelledSportCatalogDoesNotStartLiveFallback() async throws {
        let session = try makeFixtureSession(sportResponse: .failure(URLError(.cancelled)))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)

        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Cancellation must end the lookup")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains("/catalog/tv/nuvio_sports_live.json"))
    }

    func testConflictingSportCatalogDoesNotUseLiveToEraseConflict() async throws {
        let conflicting = try CommunitySportsFixtureProtocol.Response.json([
            "metas": [catalogEntry(teams: ["Chelsea", "Brighton"]), catalogEntry(teams: ["Arsenal", "Tottenham"])]
        ])
        let session = try makeFixtureSession(sportResponse: conflicting)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)

        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("The Live catalog cannot erase contradictory source IDs")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch)
        }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains("/catalog/tv/nuvio_sports_live.json"))
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testSaturatedCatalogUsesAdvertisedSearchForObservedPremierLeagueFixture() async throws {
        // Regression shape: the publisher's first 100 rows omit Arsenal–Everton
        // on 24 October, while its advertised search returns the dated fixture.
        let ordinary = (0..<100).map { index -> [String: Any] in
            var row = catalogEntry(teams: ["Other Home \(index)", "Other Away \(index)"])
            row["id"] = "nuvio_sport_other_\(index)"
            row["behaviorHints"] = ["defaultVideoId": "nuvio_sport_other_\(index)"]
            return row
        }
        var exact = catalogEntry(teams: ["Arsenal", "Everton"])
        exact["released"] = "2026-10-24T14:00:00.000Z"
        let session = try makeFixtureSession(sportResponse: .json(["metas": ordinary]),
            manifestResponse: .json(fixtureManifest(version: "3.1.3", searchCatalogs: ["nuvio_sports_football"])),
            liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_football/search=Arsenal.json": .json(["metas": [exact]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let request = StreamPlaybackRequest(matchID: "pl-arsenal-everton", displayTitle: "Arsenal vs Everton",
            homeTeam: "Arsenal", awayTeam: "Everton", category: "football",
            kickoffDate: ISO8601DateFormatter().date(from: "2026-10-24T14:00:00Z")!)
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let sources = try await client.resolve(for: request)
        XCTAssertEqual(sources.map(\.providerName), ["CS1"])
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", "/catalog/tv/nuvio_sports_football.json",
            "/catalog/tv/nuvio_sports_live.json", "/catalog/tv/nuvio_sports_football/search=Arsenal.json",
            "/stream/tv/nuvio_sport_fixture.json"])
        XCTAssertEqual(CommunitySportsFixtureProtocol.timeouts, [7, 7, 7, 7, 23])
    }

    func testSearchFallbackIsNotLimitedToPremierLeagueClubPairs() async throws {
        // The same exact dated football path must also support Champions League
        // club pairs, without a competition-specific allowlist or alias bypass.
        let exact = catalogEntry(teams: ["Real Madrid", "Borussia Dortmund"])
        let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
            searchCatalogs: ["nuvio_sports_football"])), liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_football/search=Real Madrid.json": .json(["metas": [exact]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let sources = try await client.resolve(for: makeRequest(home: "Real Madrid", away: "Borussia Dortmund", category: "football"))
        XCTAssertEqual(sources.count, 1)
        XCTAssertTrue(CommunitySportsFixtureProtocol.paths.contains("/catalog/tv/nuvio_sports_football/search=Real Madrid.json"))
    }

    func testOfficialPremierLeagueLegalNamesUseReviewedShortSearchHintWithoutChangingMatchIdentity() async throws {
        let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
            searchCatalogs: ["nuvio_sports_football"])), liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_football/search=Arsenal.json": .json(["metas": [catalogEntry(teams: ["Arsenal", "Everton"])]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let sources = try await client.resolve(for: makeRequest(home: "Arsenal FC", away: "Everton FC", category: "football"))
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("search=") },
            ["/catalog/tv/nuvio_sports_football/search=Arsenal.json"])
    }

    func testSearchHintDoesNotStripUnknownLegalNamesOrFootballSquads() async throws {
        for teams in [["Unreviewed Town FC", "Unreviewed Rovers AFC"], ["Arsenal FC Women", "Everton FC Women"],
                      ["Arsenal U19", "Everton U19"], ["Arsenal Reserves", "Everton Reserves"]] {
            let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
            let expectedPaths = teams.map { "/catalog/tv/nuvio_sports_football/search=\($0).json" }
            let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
                searchCatalogs: ["nuvio_sports_football"])), liveResponse: empty,
                searchResponses: Dictionary(uniqueKeysWithValues: expectedPaths.map { ($0, empty) }))
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                _ = try await client.resolve(for: makeRequest(home: teams[0], away: teams[1], category: "football"))
                XCTFail("No exact fixture was returned")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("search=") }, expectedPaths)
        }
    }

    func testUnadvertisedSearchIsNeverGuessed() async throws {
        let session = try makeFixtureSession(liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("No advertised search may be synthesized")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.contains("search=") })
    }

    func testOrdinaryCatalogHitOrConflictDoesNotStartAdvertisedSearch() async throws {
        let exact = catalogEntry(teams: ["Chelsea", "Brighton"])
        for conflicting in [false, true] {
            let rows = conflicting ? [exact, catalogEntry(teams: ["Arsenal", "Tottenham"])] : [exact]
            let session = try makeFixtureSession(sportResponse: .json(["metas": rows]),
                manifestResponse: .json(fixtureManifest(version: "3.1.3", searchCatalogs: ["nuvio_sports_football"])))
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                let sources = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
                XCTAssertFalse(conflicting)
                XCTAssertEqual(sources.count, 1)
            } catch {
                XCTAssertTrue(conflicting)
                XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch)
            }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.contains("search=") })
        }
    }

    func testSearchRemainsBoundedToTwoParticipantQueriesAndCanUseAdvertisedLiveCatalog() async throws {
        let session = try makeFixtureSession(includeSportCatalog: false,
            manifestResponse: .json(fixtureManifest(version: "3.1.3", includeSportCatalog: false,
                searchCatalogs: ["nuvio_sports_live"])), liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_live/search=Chelsea.json": .json(["metas": []]),
                              "/catalog/tv/nuvio_sports_live/search=Brighton.json": .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let sources = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("search=") },
            ["/catalog/tv/nuvio_sports_live/search=Chelsea.json", "/catalog/tv/nuvio_sports_live/search=Brighton.json"])
    }

    func testTargetedSearchCannotAdmitWrongDateSportOrSquad() async throws {
        let exact = catalogEntry(teams: ["Chelsea", "Brighton"])
        var wrongDate = exact; wrongDate["released"] = "2026-09-14T20:05:00Z"
        var wrongSport = exact; wrongSport["genres"] = ["CRICKET"]
        var wrongSquad = catalogEntry(teams: ["Chelsea Women", "Brighton Women"])
        wrongSquad["id"] = "nuvio_sport_women"
        wrongSquad["behaviorHints"] = ["defaultVideoId": "nuvio_sport_women"]
        for row in [wrongDate, wrongSport, wrongSquad] {
            let response = try CommunitySportsFixtureProtocol.Response.json(["metas": [row]])
            let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
                searchCatalogs: ["nuvio_sports_football"])), liveResponse: .json(["metas": []]),
                searchResponses: ["/catalog/tv/nuvio_sports_football/search=Chelsea.json": response,
                                  "/catalog/tv/nuvio_sports_football/search=Brighton.json": response])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
                XCTFail("Search is a hint only; the dated full fixture identity still owns admission")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("search=") }.count, 2)
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    func testSearchPreservesOrdinaryCatalogConflictingIDAndTargetEvidence() async throws {
        let exact = catalogEntry(teams: ["Chelsea", "Brighton"])
        for conflict in ["metadata-id", "effective-target", "malformed"] {
            var other = catalogEntry(teams: ["Arsenal", "Tottenham"])
            if conflict == "metadata-id" { other["behaviorHints"] = ["defaultVideoId": "nuvio_sport_other"] }
            if conflict == "effective-target" { other["id"] = "nuvio_sport_other" }
            if conflict == "malformed" { other.removeValue(forKey: "released") }
            let session = try makeFixtureSession(sportResponse: .json(["metas": [other]]),
                manifestResponse: .json(fixtureManifest(version: "3.1.3", searchCatalogs: ["nuvio_sports_football"])),
                liveResponse: .json(["metas": []]),
                searchResponses: ["/catalog/tv/nuvio_sports_football/search=Chelsea.json": .json(["metas": [exact]])])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
                XCTFail("Targeted evidence cannot erase a completed ordinary conflict: \(conflict)")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch, conflict) }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    func testSecondSearchCannotEraseFirstSearchConflictingEvidence() async throws {
        let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
            searchCatalogs: ["nuvio_sports_football"])), liveResponse: .json(["metas": []]), searchResponses: [
                "/catalog/tv/nuvio_sports_football/search=Chelsea.json": .json(["metas": [catalogEntry(teams: ["Chelsea", "Fulham"])]]),
                "/catalog/tv/nuvio_sports_football/search=Brighton.json": .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Both completed search responses remain conflict evidence")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testSearchQueryIsOneEncodedPathValueUnderFixedCatalogRoute() throws {
        let query = "Paris / Saint-Germain?x=1&other=%2F + München"
        let url = try XCTUnwrap(CommunitySportsAddonClient.searchCatalogURL(
            relativeTo: URL(string: "https://addon.example/config/manifest.json")!,
            catalogID: "nuvio_sports_football", query: query))
        XCTAssertEqual(url.host, "addon.example")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.percentEncodedPath,
            "/config/catalog/tv/nuvio_sports_football/search=Paris%20%2F%20Saint-Germain%3Fx%3D1%26other%3D%252F%20%2B%20M%C3%BCnchen.json")
    }

    func testObservedPremierLeagueVideoIDAndExistingCharacterContractKeepTheSameAdmission() {
        let observed = "nuvio_sport_spk_arsenal-vs-everton-2494072"
        XCTAssertEqual(observed.utf8.count, 42)
        for value in [observed, "nuvio_sport_fixture_1-2.3~4", "nuvio_sport_",
                      "nuvio_sport_" + String(repeating: "a", count: 228)] {
            XCTAssertNil(CommunitySportsAddonClient.videoIDRejection(value))
        }
        XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection(""), .streamIDEmpty)
        XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection("other_fixture"), .streamIDPrefix)
        XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection("nuvio_sport_" + String(repeating: "a", count: 229)), .streamIDLength)
        for value in ["nuvio_sport_fixture:0", "nuvio_sport_fixture/part", "nuvio_sport_fixture=value",
                      "nuvio_sport_fixture%20", "nuvio_sport_fixture ", "nuvio_sport_fixture\u{200B}"] {
            XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection(value), .streamIDCharacters)
        }
        // Prefix and length remain earlier checks than forbidden characters.
        XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection("other/" + String(repeating: "a", count: 240)), .streamIDPrefix)
        XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection("nuvio_sport_/" + String(repeating: "a", count: 240)), .streamIDLength)
        XCTAssertNil(CommunitySportsAddonClient.videoIDInvalidScalar(observed))
        XCTAssertEqual(CommunitySportsAddonClient.videoIDInvalidScalar("nuvio_sport_fixture:0/other"), 0x003A)
        XCTAssertEqual(CommunitySportsAddonClient.videoIDInvalidScalar("nuvio_sport_fixture\u{200B}"), 0x200B)
    }

    func testEveryASCIIIdentifierCharacterMatchesIndependentExplicitAllowlist() {
        for value in UInt32(0)...UInt32(127) {
            let scalar = UnicodeScalar(value)!
            let identifier = "nuvio_sport_fixture" + String(scalar)
            // Independent byte ranges, not the implementation's CharacterSet
            // or method-reference predicate that failed on optimized iPad.
            let permitted = (48...57).contains(value) || (65...90).contains(value)
                || (97...122).contains(value) || [45, 46, 95, 126].contains(value)
            if permitted {
                XCTAssertNil(CommunitySportsAddonClient.videoIDRejection(identifier), "ASCII \(value)")
                XCTAssertNil(CommunitySportsAddonClient.videoIDInvalidScalar(identifier), "ASCII \(value)")
            } else {
                XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection(identifier), .streamIDCharacters, "ASCII \(value)")
                XCTAssertEqual(CommunitySportsAddonClient.videoIDInvalidScalar(identifier), value, "ASCII \(value)")
            }
        }
    }

    func testIdentifierValidationRetainsItsExistingUnicodeAlphanumericPolicy() {
        for suffix in ["é", "Ω", "中", "١"] {
            let identifier = "nuvio_sport_fixture" + suffix
            XCTAssertNil(CommunitySportsAddonClient.videoIDRejection(identifier), suffix)
            XCTAssertNil(CommunitySportsAddonClient.videoIDInvalidScalar(identifier), suffix)
        }
        for suffix in ["\u{200B}", "⚽", "\u{2028}"] {
            let identifier = "nuvio_sport_fixture" + suffix
            XCTAssertEqual(CommunitySportsAddonClient.videoIDRejection(identifier), .streamIDCharacters, suffix)
        }
    }

    func testObservedArsenalEvertonIdentifierResolvesFromOfficialLegalNamesThroughCatalogAndSearch() async throws {
        let observedID = "nuvio_sport_spk_arsenal-vs-everton-2494072"
        XCTAssertEqual(observedID.utf8.count, 42)
        var exact = catalogEntry(teams: ["Arsenal", "Everton"])
        exact["id"] = observedID
        exact["released"] = "2026-10-24T14:00:00.000Z"
        exact["behaviorHints"] = ["defaultVideoId": observedID]
        for searchOnly in [false, true] {
            let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
            let match = try CommunitySportsFixtureProtocol.Response.json(["metas": [exact]])
            let session = try makeFixtureSession(sportResponse: searchOnly ? empty : match,
                manifestResponse: .json(fixtureManifest(version: "3.1.3", searchCatalogs: ["nuvio_sports_football"])),
                liveResponse: empty,
                searchResponses: ["/catalog/tv/nuvio_sports_football/search=Arsenal.json": match])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let streamPath = "/stream/tv/\(observedID).json"
            CommunitySportsFixtureProtocol.setResponse(try .json(["streams": [
                ["url": "https://addon.example/api/manifest?channel=fixture", "_source": "upstream-a"]
            ]]), for: streamPath)
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            let request = StreamPlaybackRequest(matchID: "pl-arsenal-everton", displayTitle: "Arsenal FC vs Everton FC",
                homeTeam: "Arsenal FC", awayTeam: "Everton FC", category: "football",
                kickoffDate: ISO8601DateFormatter().date(from: "2026-10-24T14:00:00Z")!)
            let sources = try await client.resolve(for: request)
            XCTAssertEqual(sources.map(\.providerName), ["CS1"])
            XCTAssertEqual(sources.first?.playableURL.absoluteString, "https://addon.example/api/manifest?channel=fixture")
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths.last, streamPath)
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("search=") },
                searchOnly ? ["/catalog/tv/nuvio_sports_football/search=Arsenal.json"] : [])
        }
    }

    func testCancellingTargetedSearchStopsBeforeSecondQueryOrStreams() async throws {
        let search = CommunitySportsFixtureGate("targeted search started")
        let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
            searchCatalogs: ["nuvio_sports_football"])), liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_football/search=Chelsea.json": .controlled(search)])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let task = Task { try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football")) }
        await fulfillment(of: [search.started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("The owning discovery's cancellation must end search") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        search.respond(try .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]))
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("search=") }.count, 1)
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testTargetedResultsDoNotPoisonTheOrdinaryCatalogCacheOrPersistPastTheEventWindow() async throws {
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let session = try makeFixtureSession(manifestResponse: .json(fixtureManifest(version: "3.1.3",
            searchCatalogs: ["nuvio_sports_football"])), liveResponse: empty,
            searchResponses: ["/catalog/tv/nuvio_sports_football/search=Chelsea.json": .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
                              "/catalog/tv/nuvio_sports_football/search=Brighton.json": empty])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let sources = try await client.resolve(for: request)
        XCTAssertEqual(sources.count, 1)
        CommunitySportsFixtureProtocol.setResponse(empty, for: "/catalog/tv/nuvio_sports_football/search=Chelsea.json")
        do { _ = try await client.resolve(for: request); XCTFail("Search must be refreshed, not stored as an ordinary catalog") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football/search=Chelsea.json" }.count, 2)
    }

    func testOpaqueSourceIdentitySurvivesResponseReorderingWithoutChangingCSLabels() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let manifest = URL(string: "https://addon.example/manifest.json")!
        let first = CommunitySportsStreamEntry(name: nil, title: nil,
            url: "https://addon.example/api/manifest?token=private-a", externalURL: nil,
            resolution: nil, quality: nil, sourceHint: "Upstream-A")
        let second = CommunitySportsStreamEntry(name: nil, title: nil,
            url: "https://addon.example/api/manifest?token=private-b", externalURL: nil,
            resolution: nil, quality: nil, sourceHint: "Upstream-B")
        let initial = CommunitySportsAddonClient.makeSessions(from: [first, second], request: request,
                                                               manifestURL: manifest, addOnVersion: "3.0.0")
        let reordered = CommunitySportsAddonClient.makeSessions(from: [second, first], request: request,
                                                                 manifestURL: manifest, addOnVersion: "3.0.0")

        XCTAssertEqual(initial.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(reordered.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(initial[0].diagnosticMetadata["source_key"], reordered[1].diagnosticMetadata["source_key"])
        XCTAssertNotEqual(initial[0].diagnosticMetadata["source_key"], initial[1].diagnosticMetadata["source_key"])
        XCTAssertEqual(initial[0].diagnosticMetadata["source_key_scope"], "upstream")
        let identity = initial[0].diagnosticMetadata["source_key"] ?? ""
        XCTAssertEqual(identity.count, 27)
        XCTAssertTrue(identity.hasPrefix("cs_"))
        XCTAssertFalse(identity.contains("private"))
        XCTAssertFalse(identity.contains("upstream"))
    }

    func testUnknownOrURLSourceHintUsesOpaqueDeliverySpecificAttribution() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let manifest = URL(string: "https://addon.example/manifest.json")!
        let first = CommunitySportsStreamEntry(name: nil, title: nil,
            url: "https://addon.example/api/manifest?token=private-a", externalURL: nil,
            resolution: nil, quality: nil, sourceHint: "unknown")
        let second = CommunitySportsStreamEntry(name: nil, title: nil,
            url: "https://addon.example/api/manifest?token=private-b", externalURL: nil,
            resolution: nil, quality: nil, sourceHint: "https://private.example/?token=secret")
        let sessions = CommunitySportsAddonClient.makeSessions(from: [first, second], request: request,
                                                                manifestURL: manifest, addOnVersion: "3.0.0")

        XCTAssertEqual(sessions.map { $0.diagnosticMetadata["source_key_scope"] }, ["delivery", "delivery"])
        XCTAssertNotEqual(sessions[0].diagnosticMetadata["source_key"], sessions[1].diagnosticMetadata["source_key"])
        XCTAssertTrue(sessions.allSatisfy {
            ($0.diagnosticMetadata["source_key"] ?? "").range(of: #"^cs_[a-f0-9]{24}$"#, options: .regularExpression) != nil
        })
    }

    func testStreamAdmissionKeepsOnlyReviewedSameOriginRoutesAndLabelsCS() {
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let manifest = URL(string: "https://addon.example/manifest.json")!
        let hls = CommunitySportsStreamEntry(
            name: "Direct", title: nil,
            url: "https://addon.example/api/manifest?url=https%3A%2F%2Fvideo.example%2Fmaster.m3u8",
            externalURL: nil, resolution: "1920x1080", quality: nil, sourceHint: "source-a"
        )
        let duplicate = CommunitySportsStreamEntry(
            name: "Duplicate", title: nil, url: hls.url, externalURL: nil,
            resolution: "1920x1080", quality: nil, sourceHint: "source-b"
        )
        let web = CommunitySportsStreamEntry(
            name: "Web", title: nil, url: nil,
            externalURL: "https://addon.example/watch?url=https%3A%2F%2Fembed.example%2Fone",
            resolution: nil, quality: "HD", sourceHint: "source-c"
        )
        let crossOrigin = CommunitySportsStreamEntry(
            name: "External", title: nil, url: "https://video.example/master.m3u8",
            externalURL: nil, resolution: nil, quality: nil, sourceHint: nil
        )
        let p2p = CommunitySportsStreamEntry(
            name: "P2P", title: nil,
            url: "https://addon.example/api/manifest?url=acestream%3A%2F%2Fdeadbeef",
            externalURL: nil, resolution: nil, quality: nil, sourceHint: nil
        )
        let unreviewedPath = CommunitySportsStreamEntry(
            name: "Other", title: nil, url: "https://addon.example/api/other",
            externalURL: nil, resolution: nil, quality: nil, sourceHint: nil
        )
        let misleadingWatchPath = CommunitySportsStreamEntry(
            name: "Nested", title: nil, url: nil,
            externalURL: "https://addon.example/unreviewed/watch/player",
            resolution: nil, quality: nil, sourceHint: nil
        )

        let sessions = CommunitySportsAddonClient.makeSessions(
            from: [hls, duplicate, web, crossOrigin, p2p, unreviewedPath, misleadingWatchPath],
            request: request,
            manifestURL: manifest,
            addOnVersion: "3.0.0"
        )

        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(sessions.map(\.streamType), [.hls, .unknown])
        XCTAssertEqual(sessions.first?.qualityLabel, "1080p")
        XCTAssertEqual(sessions.last?.requiredHeaders["X-Fotty-Web-Embed"], "true")
        XCTAssertEqual(sessions.first?.diagnosticMetadata["source_family"], "communitysports")
        XCTAssertTrue(sessions.allSatisfy(StreamPluginProviderMatching.isActivePlayerSession))
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(sessions[0].legacySource))
        XCTAssertTrue(LivePlaybackSourcePolicy.isWebEmbed(sessions[1].legacySource))
    }

    func testCommunitySportsPluginIsOptInAndCatalogNamesAreMapped() {
        XCTAssertFalse(StreamPluginRegistry.isEnabledByDefault(providerCode: "communitysports"))
        XCTAssertTrue(StreamPluginRegistry.isEnabledByDefault(providerCode: "score808"))
        XCTAssertEqual(CommunitySportsAddonClient.catalogID(for: "American Football"),
                       "nuvio_sports_american_football")
        XCTAssertEqual(CommunitySportsAddonClient.catalogID(for: "boxing"), "nuvio_sports_mma")
    }

    func testReviewedReplacementManifestAndBundledDomainAgree() throws {
        XCTAssertEqual(Config.communitySportsManifestURL?.absoluteString,
                       "https://nuviosports.xyz/manifest.json")
        let (manifest, _) = try StreamPluginBundle.loadManifest(named: "community_sports_manifest")
        XCTAssertEqual(manifest.allowedDomains, ["nuviosports.xyz"])
        XCTAssertEqual(manifest.providerCode, "communitysports")
        XCTAssertFalse(StreamPluginRegistry.isEnabledByDefault(providerCode: manifest.providerCode))
    }

    func testHTTPManifestOutageRetainsStatusAndStopsBeforeCatalogLookup() async throws {
        let session = try makeFixtureSession(manifestResponse: .status(530))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("An HTTP outage is not an empty catalog or schema error")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 530, stage: .manifest))
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json"])
    }

    func testManifestTimeoutRetainsTransportCodeAndStage() async throws {
        let session = try makeFixtureSession(manifestResponse: .failure(URLError(.timedOut)))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("A transport timeout must remain distinguishable from invalid JSON")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError,
                           .transportFailure(code: URLError.Code.timedOut.rawValue, stage: .manifest))
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json"])
    }

    func testMalformedManifestJSONHasTypedDecodeFailure() async throws {
        let session = try makeFixtureSession(manifestResponse: .body(Data("not JSON".utf8)))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Successful HTTP with unreadable JSON is a decode failure")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .invalidJSON(stage: .manifest))
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json"])
    }

    func testWellFormedWrongManifestIdentityRemainsContractFailure() async throws {
        let wrong = try CommunitySportsFixtureProtocol.Response.json([
            "id": "unreviewed.addon", "version": "3.1.3", "resources": ["catalog", "stream"],
            "catalogs": [["id": "nuvio_sports_live", "type": "tv"]]
        ])
        let session = try makeFixtureSession(manifestResponse: wrong)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Valid JSON cannot substitute an unreviewed add-on identity")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .invalidManifest)
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json"])
    }

    func testStreamHTTPFailureRetainsStreamStageAfterExactMatch() async throws {
        let session = try makeFixtureSession(streamResponse: .status(503))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Stream-list HTTP failure must not become no matching fixture")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .streams))
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.last, "/stream/tv/nuvio_sport_fixture.json")
    }

    func testResolutionBindsMetadataAndEffectiveStreamIDsOnlyAfterExactJoin() async throws {
        var catalog = catalogEntry(teams: ["Chelsea", "Brighton"])
        catalog["id"] = "nuvio_sport_catalog_reference"
        let session = try makeFixtureSession(sportResponse: .json(["metas": [catalog]]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let resolved = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
            session: session).resolve(for: request, now: kickoff, forceRefresh: true)
        let binding = try XCTUnwrap(resolved.first?.eventBinding)
        XCTAssertEqual(binding.providerEventID, "nuvio_sport_catalog_reference")
        XCTAssertEqual(binding.streamID, "nuvio_sport_fixture")
        XCTAssertTrue(binding.matches(request: request,
            providerCode: StreamPluginProviderMatching.communitySportsProviderCode, at: kickoff))
        XCTAssertEqual(binding.expiresAt, kickoff.addingTimeInterval(StreamEventBinding.metadataLifetime))
        XCTAssertNil(resolved.first?.expiryTime, "Metadata lifetime is not an invented signed-URL expiry")
        XCTAssertNil(directFancodeSessions([directFancodeEntry()]).first?.eventBinding,
            "Pure delivery conversion has no fixture-join witness")
    }

    func testNextDayNHLPublicationStaysUnmatchedUntilPublisherCorrectsSameIDAndExplicitRefreshes() async throws {
        // Observed28October: CS published this pairing24hours after the NHL
        // fixture. These synthetic responses prove rejection and later source
        // correction; they do not repair or reinterpret the real publisher.
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-28T23:30:00Z"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-29T00:40:00Z"))
        let request = StreamPlaybackRequest(matchID: "sports-fixture:nhl:synthetic-current",
            displayTitle: "Washington Capitals vs Philadelphia Flyers", homeTeam: "Washington Capitals",
            awayTeam: "Philadelphia Flyers", category: "hockey", kickoffDate: start)
        let hockeyPath = "/catalog/tv/nuvio_sports_hockey.json"
        let streamPath = "/stream/tv/nuvio_sport_fixture.json"
        var manifest = fixtureManifest(version: "3.1.3", includeSportCatalog: false)
        manifest["catalogs"] = [["id": "nuvio_sports_live", "type": "tv"],
                                ["id": "nuvio_sports_hockey", "type": "tv"]]
        var nextDay = catalogEntry(teams: ["Philadelphia Flyers", "Washington Capitals"])
        nextDay["name"] = "⏱️ philadelphia flyers vs washington capitals"
        nextDay["genres"] = ["HOCKEY"]
        nextDay["released"] = "2026-10-29T23:30:00.000Z"
        nextDay["releaseInfo"] = "11:30 PM"
        nextDay["description"] = "League: NHL\nStatus: Kickoff at11:30PM (upcoming)"
        let session = try makeFixtureSession(manifestResponse: .json(manifest),
            liveResponse: .json(["metas": []]),
            searchResponses: [hockeyPath: .json(["metas": [nextDay]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
            session: session)

        do {
            _ = try await client.resolve(for: request, now: now, forceRefresh: true)
            XCTFail("A currently live requested fixture must not borrow tomorrow's same-pair listing")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths,
            ["/manifest.json", hockeyPath, "/catalog/tv/nuvio_sports_live.json"])
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })

        var corrected = nextDay
        corrected["name"] = "🔴 LIVE: Philadelphia Flyers vs Washington Capitals"
        corrected["released"] = "2026-10-28T23:30:00.000Z"
        corrected["releaseInfo"] = "LIVE"
        corrected["description"] = "League: NHL\nStatus: LIVE"
        XCTAssertEqual(corrected["id"] as? String, nextDay["id"] as? String)
        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [corrected]]), for: hockeyPath)
        let beforeCachedLookup = CommunitySportsFixtureProtocol.paths.count
        do {
            _ = try await client.resolve(for: request, now: now.addingTimeInterval(1))
            XCTFail("A cached populated catalog must retain its original dated evidence until revalidated")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.count, beforeCachedLookup)

        let beforeExplicitRefresh = CommunitySportsFixtureProtocol.requests.count
        let resolved = try await client.resolve(for: request, now: now.addingTimeInterval(2), forceRefresh: true)
        XCTAssertEqual(resolved.map(\.providerName), ["CS1"])
        let refreshed = Array(CommunitySportsFixtureProtocol.requests.dropFirst(beforeExplicitRefresh))
        XCTAssertEqual(refreshed.map { $0.url?.path ?? "" }, ["/manifest.json", hockeyPath, streamPath])
        XCTAssertTrue(refreshed.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache" })
        let binding = try XCTUnwrap(resolved.first?.eventBinding)
        XCTAssertEqual(binding.kickoffDate, start)
        XCTAssertEqual(binding.providerEventID, "nuvio_sport_fixture")
        XCTAssertEqual(binding.streamID, "nuvio_sport_fixture")
        XCTAssertTrue(binding.matches(request: request, providerCode: "communitysports", at: now.addingTimeInterval(2)))

        var wrongSquad = corrected
        wrongSquad["name"] = "Philadelphia Flyers Women vs Washington Capitals Women"
        wrongSquad["cast"] = ["Philadelphia Flyers Women", "Washington Capitals Women"]
        var outsideTolerance = corrected
        outsideTolerance["released"] = "2026-10-28T23:45:01.000Z"
        let rejected: [([[String: Any]], CommunitySportsAddonError)] = [
            ([wrongSquad], .matchNotFound),
            ([outsideTolerance], .matchNotFound),
            ([corrected, nextDay], .conflictingMatch)
        ]
        for (entries, expected) in rejected {
            CommunitySportsFixtureProtocol.setResponse(try .json(["metas": entries]), for: hockeyPath)
            do {
                _ = try await client.resolve(for: request, now: now.addingTimeInterval(3), forceRefresh: true)
                XCTFail("Date correction must retain squad, kickoff-tolerance and duplicate-ID guards")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, expected) }
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == streamPath }.count, 1,
            "Only the corrected exact fixture may request a descriptor")
    }

    func testExplicitRefreshBypassesNegativeCatalogAndManifestSnapshots() async throws {
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let session = try makeFixtureSession(includeSportCatalog: false, liveResponse: empty)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let now = kickoff.addingTimeInterval(-3600) // Outside automatic late-discovery eligibility.
        do { _ = try await client.resolve(for: request, now: now); XCTFail("Not published yet") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        CommunitySportsFixtureProtocol.setResponse(try .json(fixtureManifest(version: "newer")), for: "/manifest.json")
        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            for: "/catalog/tv/nuvio_sports_football.json")
        let firstCount = CommunitySportsFixtureProtocol.requests.count
        let result = try await client.resolve(for: request, now: now.addingTimeInterval(1), forceRefresh: true)
        XCTAssertEqual(result.first?.diagnosticMetadata["addon_version"], "newer")
        let refreshed = Array(CommunitySportsFixtureProtocol.requests.dropFirst(firstCount))
        XCTAssertEqual(refreshed.map { $0.url?.path ?? "" }, ["/manifest.json", "/catalog/tv/nuvio_sports_football.json",
            "/stream/tv/nuvio_sport_fixture.json"])
        XCTAssertTrue(refreshed.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache" })
    }

    func testCachedMissingSportCapabilityRevalidatesOnceInTheEligibleWindow() async throws {
        let session = try makeFixtureSession(includeSportCatalog: false,
            liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        do { _ = try await client.resolve(for: request, now: kickoff); XCTFail("No exact catalog row") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        CommunitySportsFixtureProtocol.setResponse(try .json(fixtureManifest(version: "published")), for: "/manifest.json")
        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            for: "/catalog/tv/nuvio_sports_football.json")
        let result = try await client.resolve(for: request, now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(result.first?.diagnosticMetadata["addon_version"], "published")
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/stream/tv/nuvio_sport_fixture.json" }.count, 1)
    }

    func testExactEmptyDescriptorGetsOnlyOneFreshReadAndCanObserveLatePublication() async throws {
        let session = try makeFixtureSession()
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let path = "/stream/tv/nuvio_sport_fixture.json"
        CommunitySportsFixtureProtocol.setResponses([
            try .json(["streams": []]),
            try .json(["streams": [["url": "https://addon.example/api/manifest?channel=published", "_source": "upstream-a"]]])
        ], for: path)
        let result = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
            session: session).resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"), now: kickoff)
        XCTAssertEqual(result.count, 1)
        let descriptors = CommunitySportsFixtureProtocol.requests.filter { $0.url?.path == path }
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertNil(descriptors.first?.value(forHTTPHeaderField: "Cache-Control"))
        XCTAssertEqual(descriptors.last?.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testStillEmptyDescriptorStopsAfterOneFreshReadAndKeepsPendingMeaning() async throws {
        let session = try makeFixtureSession(streamResponse: .json(["streams": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"), now: kickoff)
            XCTFail("Still pending")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamEntriesEmpty) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/stream/tv/nuvio_sport_fixture.json" }.count, 2)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
    }

    func testForcedSportCatalogErrorStillAllowsIndependentExactLiveChoice() async throws {
        let session = try makeFixtureSession(sportResponse: .status(503))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let result = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
            session: session).resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"),
                now: kickoff, forceRefresh: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/stream/tv/nuvio_sport_fixture.json" }.count, 1)
    }

    func testOlderForcedCatalogCannotOverwriteANewerForcedAcceptedSnapshot() async throws {
        let populated = try CommunitySportsFixtureProtocol.Response.json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])
        let session = try makeFixtureSession(sportResponse: populated, liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        _ = try await client.resolve(for: request, now: kickoff)
        let gate = CommunitySportsFixtureGate("older forced catalog")
        CommunitySportsFixtureProtocol.setResponse(.controlled(gate), for: "/catalog/tv/nuvio_sports_football.json")
        let old = Task { try await client.resolve(for: request, now: kickoff.addingTimeInterval(1), forceRefresh: true) }
        defer { old.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        CommunitySportsFixtureProtocol.setResponse(populated, for: "/catalog/tv/nuvio_sports_football.json")
        _ = try await client.resolve(for: request, now: kickoff.addingTimeInterval(2), forceRefresh: true)
        gate.respond(try .json(["metas": []]))
        do { _ = try await old.value; XCTFail("Original request has no exact row") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        CommunitySportsFixtureProtocol.setResponse(.status(503), for: "/catalog/tv/nuvio_sports_football.json")
        let retained = try await client.resolve(for: request, now: kickoff.addingTimeInterval(3))
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 3)
    }

    func testCancelledForcedManifestCannotPublishContractOrContinueToCatalog() async throws {
        let session = try makeFixtureSession()
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        _ = try await client.resolve(for: request, now: kickoff)
        let gate = CommunitySportsFixtureGate("forced manifest cancelled")
        CommunitySportsFixtureProtocol.setResponse(.controlled(gate), for: "/manifest.json")
        let task = Task { try await client.resolve(for: request, now: kickoff.addingTimeInterval(1), forceRefresh: true) }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        let catalogCount = CommunitySportsFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count
        task.cancel()
        gate.respond(try .json(fixtureManifest(version: "cancelled")))
        do { _ = try await task.value; XCTFail("Cancelled refresh") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count, catalogCount)
        let retained = try await client.resolve(for: request, now: kickoff.addingTimeInterval(2))
        XCTAssertEqual(retained.first?.diagnosticMetadata["addon_version"], "3.0.0")
    }

    func testNewlyPublishedFixtureIsVisibleAfterDefaultFifteenSecondEmptyTTL() async throws {
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let session = try makeFixtureSession(liveResponse: empty)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        do { _ = try await client.resolve(for: request, now: start); XCTFail("The initial catalogs are empty") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }

        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            for: "/catalog/tv/nuvio_sports_football.json")
        do { _ = try await client.resolve(for: request, now: start.addingTimeInterval(14)); XCTFail("The bounded negative cache is still fresh") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.contains("/catalog/") }.count, 2)

        let result = try await client.resolve(for: request, now: start.addingTimeInterval(15))
        XCTAssertEqual(result.map(\.providerName), ["CS1"])
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 2)
    }

    func testInjectedEmptyTTLDoesNotShortenPopulatedCatalogTTL() async throws {
        let populated = try CommunitySportsFixtureProtocol.Response.json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let session = try makeFixtureSession(sportResponse: populated, liveResponse: empty)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            negativeCatalogTTL: 3)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await client.resolve(for: request, now: start)
        CommunitySportsFixtureProtocol.setResponse(empty, for: "/catalog/tv/nuvio_sports_football.json")
        let retained = try await client.resolve(for: request, now: start.addingTimeInterval(119))
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 1)
        do { _ = try await client.resolve(for: request, now: start.addingTimeInterval(120)); XCTFail("The populated cache expired at its original TTL") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }

        CommunitySportsFixtureProtocol.setResponse(populated, for: "/catalog/tv/nuvio_sports_football.json")
        do { _ = try await client.resolve(for: request, now: start.addingTimeInterval(122)); XCTFail("The injected empty cache has not expired yet") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        let refreshed = try await client.resolve(for: request, now: start.addingTimeInterval(123))
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 3)
    }

    func testClockRollbackDoesNotTreatFutureManifestAndCatalogAsFresh() async throws {
        let populated = try CommunitySportsFixtureProtocol.Response.json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let session = try makeFixtureSession(sportResponse: populated, liveResponse: empty)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await client.resolve(for: request, now: start)
        CommunitySportsFixtureProtocol.setResponse(empty, for: "/catalog/tv/nuvio_sports_football.json")
        do { _ = try await client.resolve(for: request, now: start.addingTimeInterval(-1)); XCTFail("Future-dated cached data cannot be fresh") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 2)
    }

    func testOlderEmptyCatalogCompletionCannotOverwriteNewerPopulatedSnapshot() async throws {
        let older = CommunitySportsFixtureGate("older football catalog")
        let newer = CommunitySportsFixtureGate("newer football catalog")
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let populated = try CommunitySportsFixtureProtocol.Response.json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])
        let session = try makeFixtureSession(sportResponse: .controlled(older), liveResponse: empty)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let oldLookup = Task { try await client.resolve(for: request, now: start) }
        defer { oldLookup.cancel(); older.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [older.started], timeout: 2)
        CommunitySportsFixtureProtocol.setResponse(.controlled(newer), for: "/catalog/tv/nuvio_sports_football.json")
        let newLookup = Task { try await client.resolve(for: request, now: start.addingTimeInterval(1)) }
        defer { newLookup.cancel(); newer.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [newer.started], timeout: 2)
        newer.respond(populated)
        let newResult = try await newLookup.value
        XCTAssertEqual(newResult.count, 1)
        older.respond(empty)
        do { _ = try await oldLookup.value; XCTFail("The original caller still receives its own empty result") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }

        CommunitySportsFixtureProtocol.setResponse(.failure(URLError(.networkConnectionLost)), for: "/catalog/tv/nuvio_sports_football.json")
        let retained = try await client.resolve(for: request, now: start.addingTimeInterval(2))
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 2,
                       "The newer populated cache must remain; no third catalog fetch is needed")
    }

    func testOlderManifestCompletionCannotOverwriteNewerCachedContract() async throws {
        let older = CommunitySportsFixtureGate("older manifest")
        let newer = CommunitySportsFixtureGate("newer manifest")
        let populated = try CommunitySportsFixtureProtocol.Response.json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])
        let session = try makeFixtureSession(sportResponse: populated, manifestResponse: .controlled(older))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let oldLookup = Task { try await client.resolve(for: request, now: start) }
        defer { oldLookup.cancel(); older.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [older.started], timeout: 2)
        CommunitySportsFixtureProtocol.setResponse(.controlled(newer), for: "/manifest.json")
        let newLookup = Task { try await client.resolve(for: request, now: start.addingTimeInterval(1)) }
        defer { newLookup.cancel(); newer.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [newer.started], timeout: 2)

        newer.respond(try .json(fixtureManifest(version: "newer")))
        let newResult = try await newLookup.value
        XCTAssertEqual(newResult.first?.diagnosticMetadata["addon_version"], "newer")
        older.respond(try .json(fixtureManifest(version: "older")))
        let oldResult = try await oldLookup.value
        XCTAssertEqual(oldResult.first?.diagnosticMetadata["addon_version"], "older",
                       "The original caller retains its own independently verified result")

        CommunitySportsFixtureProtocol.setResponse(.status(503), for: "/manifest.json")
        let retained = try await client.resolve(for: request, now: start.addingTimeInterval(2))
        XCTAssertEqual(retained.first?.diagnosticMetadata["addon_version"], "newer")
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
    }

    func testFailedNewerManifestDoesNotLetAnOlderCompletionBecomeTheCachedContract() async throws {
        let older = CommunitySportsFixtureGate("older manifest before failed newer request")
        let populated = try CommunitySportsFixtureProtocol.Response.json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]])
        let session = try makeFixtureSession(sportResponse: populated, manifestResponse: .controlled(older))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let oldLookup = Task { try await client.resolve(for: request, now: start) }
        defer { oldLookup.cancel(); older.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [older.started], timeout: 2)

        CommunitySportsFixtureProtocol.setResponse(.status(503), for: "/manifest.json")
        do {
            _ = try await client.resolve(for: request, now: start.addingTimeInterval(1))
            XCTFail("The newer manifest request failed")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .manifest))
        }
        older.respond(try .json(fixtureManifest(version: "older")))
        _ = try await oldLookup.value

        CommunitySportsFixtureProtocol.setResponse(try .json(fixtureManifest(version: "fresh")), for: "/manifest.json")
        let refreshed = try await client.resolve(for: request, now: start.addingTimeInterval(2))
        XCTAssertEqual(refreshed.first?.diagnosticMetadata["addon_version"], "fresh")
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 3)
    }

    func testExactFixtureWithEmptyStreamListDoesNotBecomeMissingFixture() async throws {
        for document: [String: Any] in [["streams": []], ["streams": NSNull()], [:]] {
            let session = try makeFixtureSession(streamResponse: .json(document))
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
                XCTFail("An exact fixture with no stream entries must retain that distinct result")
            } catch {
                XCTAssertEqual(error as? CommunitySportsAddonError, .streamEntriesEmpty)
                let failure = LiveStreamResolver.communitySportsFailure(from: try XCTUnwrap(error as? CommunitySportsAddonError))
                XCTAssertEqual(failure.category, .providerReturnedEmpty)
                XCTAssertEqual(failure.redactedMetadata["manifest_result"], "stream_entries_empty")
                XCTAssertEqual(failure.redactedMetadata["cs_stream_entry_count"], "0")
                XCTAssertEqual(failure.redactedMetadata["cs_admission_rejected_count"], "0")
            }
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths.last, "/stream/tv/nuvio_sport_fixture.json")
        }
    }

    func testMalformedStreamSiblingsAreRejectedWholeWithoutErasingValidChoices() async throws {
        let malformedRows: [Any] = [
            NSNull(), "not-an-entry", 7, ["url": 7],
            ["url": "https://addon.example/api/manifest?channel=bad-null",
             "behaviorHints": ["proxyHeaders": ["request": NSNull()]]],
            ["url": "https://addon.example/api/manifest?channel=bad-string",
             "behaviorHints": ["proxyHeaders": ["request": "not-an-object"]]],
            ["url": "https://addon.example/api/manifest?channel=bad-value",
             "behaviorHints": ["proxyHeaders": ["request": ["User-Agent": 7]]]],
            ["url": "https://addon.example/api/manifest?channel=bad-response",
             "behaviorHints": ["proxyHeaders": ["response": NSNull()]]]
        ]
        let first: [String: Any] = ["url": "https://addon.example/api/manifest?channel=first", "_source": "upstream-a"]
        let last: [String: Any] = ["url": "https://addon.example/api/manifest?channel=last", "_source": "upstream-b"]
        let session = try makeFixtureSession(streamResponse: .json(["streams": [first] + malformedRows + [last]]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let result = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
        XCTAssertEqual(result.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(result.map { $0.diagnosticMetadata["source_hint"] }, ["upstream-a", "upstream-b"])
        XCTAssertEqual(result.map { $0.playableURL.query }, ["channel=first", "channel=last"])
        XCTAssertTrue(result.allSatisfy { $0.requiredHeaders.isEmpty },
                      "A malformed required-header row must be rejected, never converted to a headerless session")
    }

    func testAllMalformedStreamRowsRemainAnAdmissionFailureRatherThanAnEmptyList() async throws {
        let session = try makeFixtureSession(streamResponse: .json(["streams": [NSNull(), "invalid", ["url": 7]]]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("There were entries, but none met the supported contract")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 3))
        }
    }

    func testMalformedStreamRowsCannotMoveTheHundredEntryBoundary() async throws {
        let valid: [String: Any] = ["url": "https://addon.example/api/manifest?channel=after-boundary"]
        let rows = Array<Any>(repeating: NSNull(), count: 100) + [valid]
        let session = try makeFixtureSession(streamResponse: .json(["streams": rows]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Skipping malformed rows must not scan unbounded later candidates")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 100))
        }
    }

    func testMalformedStreamDocumentAndWrongContainerShapeRemainFatalDecodeFailures() async throws {
        let responses: [CommunitySportsFixtureProtocol.Response] = [
            .body(Data("not JSON".utf8)),
            .body(Data("[]".utf8)),
            try .json(["streams": "not-an-array"]),
            try .json(["streams": ["url": "https://addon.example/api/manifest"]])
        ]
        for response in responses {
            let session = try makeFixtureSession(streamResponse: response)
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            do {
                _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
                XCTFail("Per-entry isolation must not accept malformed document containers")
            } catch {
                XCTAssertEqual(error as? CommunitySportsAddonError, .invalidJSON(stage: .streams))
            }
        }
    }

    func testExactFixtureWithOnlyUnsupportedDeliveriesRetainsBoundedAdmissionResult() async throws {
        let entries = [
            ["url": "https://unreviewed.example/api/manifest?private=one"],
            ["url": "https://addon.example/unreviewed-route?private=two"]
        ]
        let session = try makeFixtureSession(streamResponse: .json(["streams": entries]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Unsupported deliveries must not be admitted or mislabeled as a missing fixture")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 2))
            let failure = LiveStreamResolver.communitySportsFailure(from: try XCTUnwrap(error as? CommunitySportsAddonError))
            XCTAssertEqual(failure.category, .providerReturnedEmpty)
            XCTAssertEqual(failure.redactedMetadata["manifest_result"], "no_admitted_stream_delivery")
            XCTAssertEqual(failure.redactedMetadata["cs_stream_entry_count"], "2")
            XCTAssertEqual(failure.redactedMetadata["cs_admission_rejected_count"], "2")
            XCTAssertFalse(failure.redactedMetadata.description.contains("private"))
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.last, "/stream/tv/nuvio_sport_fixture.json")
    }

    func testAdmissionCountsDescribeOnlyTheHundredEntriesActuallyScanned() async throws {
        let entries = Array(repeating: ["url": "https://unreviewed.example/api/manifest"], count: 150)
        let session = try makeFixtureSession(streamResponse: .json(["streams": entries]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("The adapter must not read or count beyond its existing admission limit")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 100))
        }
        for count in [Int.min, -1, 0, 2, 100, 101, Int.max] {
            let metadata = LiveStreamResolver.communitySportsFailure(from: .streamAdmissionRejected(entryCount: count)).redactedMetadata
            XCTAssertEqual(metadata["cs_stream_entry_count"], String(min(max(count, 0), 100)))
            XCTAssertEqual(metadata["cs_admission_rejected_count"], metadata["cs_stream_entry_count"])
        }
    }

    func testMissingFixtureDoesNotClaimAnEmptyOrRejectedStreamList() async throws {
        let session = try makeFixtureSession(liveTeams: ["Chelsea", "Fulham"])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("The wrong fixture must remain absent without fetching its stream list")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound)
            let failure = LiveStreamResolver.communitySportsFailure(from: try XCTUnwrap(error as? CommunitySportsAddonError))
            XCTAssertEqual(failure.redactedMetadata["manifest_result"], "no_exact_fixture_match")
            XCTAssertNil(failure.redactedMetadata["cs_stream_entry_count"])
            XCTAssertNil(failure.redactedMetadata["cs_admission_rejected_count"])
        }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testUnsupportedEntryDoesNotChangeAdmittedSiblingLabelOrSourceIdentity() async throws {
        let session = try makeFixtureSession(streamResponse: .json(["streams": [
            ["url": "https://unreviewed.example/api/manifest", "_source": "unreviewed"],
            ["url": "https://addon.example/api/manifest?channel=fixture", "_source": "upstream-a"]
        ]]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let result = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
        XCTAssertEqual(result.map(\.providerName), ["CS1"])
        XCTAssertEqual(result.first?.diagnosticMetadata["source_hint"], "upstream-a")
        XCTAssertEqual(result.first?.playableURL.host, "addon.example")
    }

    func testDistinctAdmissionOutcomesAndOnlyBoundedCountsPersistInCSDiscoveryReceipt() throws {
        let suite = "CS-admission-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FottyQualityStore(defaults: defaults)
        let outcomes: [(CommunitySportsAddonError, String, String?)] = [
            (.matchNotFound, "no_exact_fixture_match", nil),
            (.streamEntriesEmpty, "stream_entries_empty", "0"),
            (.streamAdmissionRejected(entryCount: 2), "no_admitted_stream_delivery", "2")
        ]
        for (error, expectedResult, count) in outcomes {
            let id = UUID().uuidString
            let failure = LiveStreamResolver.communitySportsFailure(from: error)
            var metadata = failure.redactedMetadata
            metadata["private_url"] = "https://private.invalid/account?secret=owner"
            metadata["private_fixture"] = "Private Home versus Private Away"
            var report = StreamDiscoveryCoordinator.Report()
            report.attempts = [.init(providerName: "CS", responseTimeMs: 20, resolvedStreamType: .unknown,
                urlShape: "same_origin_addon", requiredHeaders: false, validationResult: "failed",
                manifestResult: failure.redactedMetadata["manifest_result"], finalFailureCategory: failure.category)]
            report.timeline = [.init(name: .provider1ValidationFailed, matchID: "private-fixture",
                matchTitle: "Private Home versus Private Away", providerName: "CS", attemptID: id,
                currentState: .failed, failureCategory: failure.category, redactedMetadata: metadata)]
            CommunitySportsDiscoveryQuality.record(report, attemptID: id, store: store)
            let record = try XCTUnwrap(store.records().last)
            XCTAssertEqual(record.name, "source_discovery_result")
            XCTAssertEqual(record.details["result"], expectedResult)
            XCTAssertEqual(record.details["cs_stream_entry_count"], count)
            XCTAssertEqual(record.details["cs_admission_rejected_count"], count)
            XCTAssertNil(record.details["private_url"])
            XCTAssertNil(record.details["private_fixture"])
        }
        XCTAssertFalse(store.exportJSON().contains("private.invalid"))
        XCTAssertFalse(store.exportJSON().contains("Private Home"))
        let restarted = FottyQualityStore(defaults: defaults)
        XCTAssertEqual(restarted.records().last?.details["cs_stream_entry_count"], "2")

        for invalid in ["-1", "101", "NaN", "Infinity", String(Int.max), "private-owner", "https://private.invalid"] {
            store.record(category: .playback, name: "source_discovery_result", outcome: .failure,
                details: ["cs_stream_entry_count": invalid, "cs_admission_rejected_count": invalid,
                          "private_url": "https://private.invalid"])
            XCTAssertEqual(try XCTUnwrap(store.records().last?.details), [:])
        }
    }

    func testLiveCatalogFallbackRetainsItsFinalHTTPFailure() async throws {
        let session = try makeFixtureSession(sportResponse: .status(503), liveResponse: .status(530))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("The final independently checked catalog outage must remain visible")
        } catch {
            XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 530, stage: .catalog))
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths,
                       ["/manifest.json", "/catalog/tv/nuvio_sports_football.json", "/catalog/tv/nuvio_sports_live.json"])
    }

    func testCancelledManifestDoesNotBecomeTransportOutage() async throws {
        let session = try makeFixtureSession(manifestResponse: .failure(URLError(.cancelled)))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        do {
            _ = try await client.resolve(for: makeRequest(home: "Chelsea", away: "Brighton", category: "football"))
            XCTFail("Cancellation must end lookup without recording a source outage")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json"])
    }

    func testReplacementOriginAdmitsOnlyItsExactReviewedDeliveryRoutes() {
        let manifest = URL(string: "https://nuviosports.xyz/manifest.json")!
        let request = makeRequest(home: "Chelsea", away: "Brighton", category: "football")
        let urls = [
            "https://nuviosports.xyz/api/manifest?fixture=one",
            "https://nuviosports.xyz/watch?fixture=one",
            "https://nuvio.moaqeel6679.my.id/api/manifest?fixture=one",
            "https://nuviosports.xyz.evil.invalid/api/manifest?fixture=one",
            "https://media.nuviosports.xyz/api/manifest?fixture=one",
            "https://nuviosports.xyz:8443/api/manifest?fixture=one",
            "https://user:secret@nuviosports.xyz/api/manifest?fixture=one",
            "http://nuviosports.xyz/api/manifest?fixture=one",
            "https://nuviosports.xyz/api/other?fixture=one",
            "https://nuviosports.xyz/api/manifest?url=acestream%3A%2F%2Ffixture"
        ]
        let entries = urls.map {
            CommunitySportsStreamEntry(name: nil, title: nil, url: $0, externalURL: nil,
                                       resolution: nil, quality: nil, sourceHint: nil)
        }
        let sessions = CommunitySportsAddonClient.makeSessions(from: entries, request: request,
                                                               manifestURL: manifest, addOnVersion: "3.1.3")
        XCTAssertEqual(sessions.map(\.providerName), ["CS1", "CS2"])
        XCTAssertEqual(sessions.map(\.streamType), [.hls, .unknown])
        XCTAssertEqual(sessions.map { $0.playableURL.host }, ["nuviosports.xyz", "nuviosports.xyz"])
        XCTAssertTrue(sessions.allSatisfy(StreamPluginProviderMatching.isActivePlayerSession))
    }

    func testBatchCatalogMapsSeveralFixturesFromOneSnapshotWithoutDescriptorsOrSearch() async throws {
        let second = batchCatalogRow(id: "nuvio_sport_second", teams: ["Arsenal", "Liverpool"])
        let session = try makeFixtureSession(sportResponse: .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"]), second]]),
            manifestResponse: .json(fixtureManifest(version: "batch", searchCatalogs: ["nuvio_sports_football"])),
            liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let requests = [batchRequest(id: "first", teams: ["Chelsea", "Brighton"]),
                        batchRequest(id: "second", teams: ["Arsenal", "Liverpool"]),
                        batchRequest(id: "absent", teams: ["Everton", "Fulham"])]
        let rows = try await client.catalogMatches(for: requests, now: kickoff)
        XCTAssertEqual(rows.map(\.matchID), ["first", "second", "absent"])
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed, .notListed])
        XCTAssertEqual(rows.first?.providerEventID, "nuvio_sport_fixture")
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths,
            ["/manifest.json", "/catalog/tv/nuvio_sports_football.json", "/catalog/tv/nuvio_sports_live.json"])
        _ = try await client.catalogMatches(for: requests, now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.count, 3)
    }

    func testBatchCatalogRetainsMalformedAndConflictingEvidenceAcrossSportAndLive() async throws {
        let valid = catalogEntry(teams: ["Chelsea", "Brighton"])
        var contradictory = valid; contradictory["name"] = "Other Club vs Another Club"; contradictory["cast"] = ["Other Club", "Another Club"]
        for sibling in [contradictory, valid.merging(["released": "not-a-date"], uniquingKeysWith: { _, new in new })] {
            let session = try makeFixtureSession(sportResponse: .json(["metas": [valid]]), liveResponse: .json(["metas": [sibling]]))
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            let rows = try await client.catalogMatches(for: [batchRequest(id: "first", teams: ["Chelsea", "Brighton"])], now: kickoff)
            XCTAssertEqual(rows.first?.outcome, .conflicting)
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains(where: { $0.contains("/stream/") || $0.contains("/search=") }))
        }
    }

    func testBatchCatalogKeepsDateSquadAndUnsupportedRequestsDistinct() async throws {
        let session = try makeFixtureSession(sportResponse: .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let requests = [batchRequest(id: "date", teams: ["Chelsea", "Brighton"], date: kickoff.addingTimeInterval(901)),
                        batchRequest(id: "squad", teams: ["Chelsea Women", "Brighton Women"]),
                        batchRequest(id: "unsupported", teams: ["Chelsea", "Brighton"], category: "unsupported-sport")]
        let rows = try await client.catalogMatches(for: requests, now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.notListed, .notListed, .unsupported])
        XCTAssertTrue(rows.allSatisfy { $0.providerEventID == nil })
    }

    func testBatchCatalogLoadsEachNeededAdvertisedSportOnlyOnce() async throws {
        var manifest = fixtureManifest(version: "batch")
        manifest["catalogs"] = [["id": "nuvio_sports_live", "type": "tv"], ["id": "nuvio_sports_football", "type": "tv"],
                                ["id": "nuvio_sports_cricket", "type": "tv"]]
        let session = try makeFixtureSession(sportResponse: .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            manifestResponse: .json(manifest), liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_cricket.json": try .json(["metas": [
                batchCatalogRow(id: "nuvio_sport_cricket", teams: ["India", "New Zealand"], genre: "CRICKET")]])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let rows = try await client.catalogMatches(for: [batchRequest(id: "football", teams: ["Chelsea", "Brighton"]),
            batchRequest(id: "cricket", teams: ["India", "New Zealand"], category: "cricket")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed])
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.count, 4)
        XCTAssertEqual(Set(CommunitySportsFixtureProtocol.paths).count, 4)
    }

    func testBatchCatalogTransportFailureNeverMasqueradesAsNotListed() async throws {
        let session = try makeFixtureSession(sportResponse: .status(503), liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let rows = try await client.catalogMatches(for: [batchRequest(id: "first", teams: ["Chelsea", "Brighton"])], now: kickoff)
        XCTAssertEqual(rows.first?.outcome, .failed(.manifestUnreachable))
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains(where: { $0.contains("/stream/") }))
    }

    func testBatchFailedSportCatalogRetainsHealthyExactLiveListingAndMarksOnlyUnmatchedFailed() async throws {
        let session = try makeFixtureSession(sportResponse: .status(503))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let rows = try await client.catalogMatches(for: [batchRequest(id: "healthy", teams: ["Chelsea", "Brighton"]),
            batchRequest(id: "unknown", teams: ["Arsenal", "Liverpool"])], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .failed(.manifestUnreachable)])
        XCTAssertEqual(rows.first?.providerEventID, "nuvio_sport_fixture")
        XCTAssertNil(rows.last?.providerEventID)
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains(where: { $0.contains("/stream/") || $0.contains("/meta/") }))
    }

    func testBatchSportFailureCannotTaintDifferentHealthySportAndInvalidContractStaysTyped() async throws {
        var manifest = fixtureManifest(version: "batch")
        manifest["catalogs"] = [["id": "nuvio_sports_live", "type": "tv"], ["id": "nuvio_sports_football", "type": "tv"],
                                ["id": "nuvio_sports_cricket", "type": "tv"]]
        let session = try makeFixtureSession(sportResponse: .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            manifestResponse: .json(manifest), liveResponse: .json(["metas": []]),
            searchResponses: ["/catalog/tv/nuvio_sports_cricket.json": .body(Data("invalid JSON".utf8))])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let rows = try await client.catalogMatches(for: [batchRequest(id: "football", teams: ["Chelsea", "Brighton"]),
            batchRequest(id: "cricket", teams: ["India", "New Zealand"], category: "cricket")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .failed(.manifestInvalid)])
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains(where: { $0.contains("/stream/") || $0.contains("/meta/") }))
    }

    func testBatchSecurityCancellationAndConflictErrorsRemainFatal() {
        for error: Error in [CancellationError(), URLError(.cancelled), CommunitySportsAddonError.unsafeResponse,
            CommunitySportsAddonError.unsafeMetadata(stage: .catalog, reason: .responseOrigin),
            CommunitySportsAddonError.conflictingMatch] {
            XCTAssertTrue(CommunitySportsAddonClient.isFatalCatalogBatchError(error))
        }
        XCTAssertFalse(CommunitySportsAddonClient.isFatalCatalogBatchError(
            CommunitySportsAddonError.httpFailure(statusCode: 503, stage: .catalog)))
    }

    @MainActor
    func testCancelledBatchCatalogCannotPublishPartialResultsOrCacheCancelledCohort() async throws {
        let gate = CommunitySportsFixtureGate("batch cancelled")
        let session = try makeFixtureSession(sportResponse: .controlled(gate), liveResponse: .json(["metas": []]))
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let requests = [batchRequest(id: "first", teams: ["Chelsea", "Brighton"])]
        let task = Task { try await client.catalogMatches(for: requests, now: kickoff) }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        task.cancel(); gate.respond(try .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]))
        do { _ = try await task.value; XCTFail("Cancelled batch") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains("/catalog/tv/nuvio_sports_live.json"))
        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [catalogEntry(teams: ["Chelsea", "Brighton"])]]),
            for: "/catalog/tv/nuvio_sports_football.json")
        let rows = try await client.catalogMatches(for: requests, now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(rows.first?.outcome, .listed)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/catalog/tv/nuvio_sports_football.json" }.count, 2)
    }

    @MainActor
    func testVerifiedUSGuideAddsFreshCSNetworkDeliveryToCanonicalFixtureWithoutTVOptIn() async throws {
        let (snapshot, canonical) = try programmeChannelFixture(guideLifetime: 30)
        let association = try XCTUnwrap(snapshot.lookup(for: canonical,
            enabledProviderCodes: ["communitysports"], at: kickoff).first)
        let row = channelRow(.willow, id: association.broadcast.providerEventID)
        let session = try makeChannelSession(.willow, rows: [row])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
            programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
        let choices = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff)
        let choice = try XCTUnwrap(choices.first), binding = try XCTUnwrap(choice.eventBinding)
        XCTAssertEqual(choice.matchID, canonical.matchID)
        XCTAssertEqual(choice.providerName, "CS1")
        XCTAssertTrue(choice.canRefresh)
        XCTAssertTrue(binding.usesRegistryAssociation)
        XCTAssertEqual(binding.providerEventID, association.broadcast.providerEventID)
        XCTAssertEqual(binding.streamID, association.broadcast.streamID)
        XCTAssertTrue(binding.matches(request: canonical, providerCode: "communitysports", at: kickoff.addingTimeInterval(1)))
        XCTAssertEqual(choice.expiryTime, kickoff.addingTimeInterval(30), "Neither the channel nor the 90s descriptor may extend the guide receipt")
        XCTAssertFalse(binding.matches(request: canonical, providerCode: "communitysports", at: kickoff.addingTimeInterval(30)))
        XCTAssertEqual(choice.diagnosticMetadata["manifest_result"], "verified_programme_channel_match")
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", channelSearchPath(.willow),
            "/meta/tv/\(association.broadcast.providerEventID).json", "/stream/tv/\(association.broadcast.streamID).json"])
    }

    @MainActor
    func testUSProgrammeCannotAuthorizeDifferentOrUnknownRegionalCSNetworks() async throws {
        let (snapshot, canonical) = try programmeChannelFixture()
        let association = try XCTUnwrap(snapshot.lookup(for: canonical, enabledProviderCodes: ["communitysports"], at: kickoff).first)
        for country in ["United Kingdom", "Unknown", "USA / Canada"] {
            let row = channelRow(.willow, id: association.broadcast.providerEventID, country: country)
            let session = try makeChannelSession(.willow, rows: [row])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
                programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
                programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
            do { _ = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff); XCTFail("Unverified region must stay out of fixture sources") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", channelSearchPath(.willow)])
            let browsing = try await client.resolve(for: channelRequest(.willow), now: kickoff)
            XCTAssertEqual(browsing.count, 1, "The regional restriction applies only to fixture programme association")
        }
    }

    @MainActor
    func testDerivedProgrammeChecksCSOptInBeforeFetchingAndRevokesWithdrawnGuideBeforeDescriptor() async throws {
        let (snapshot, canonical) = try programmeChannelFixture()
        let association = try XCTUnwrap(snapshot.lookup(for: canonical, enabledProviderCodes: ["communitysports"], at: kickoff).first)
        let row = channelRow(.willow, id: association.broadcast.providerEventID)
        let session = try makeChannelSession(.willow, rows: [row])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let disabled = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            programmeEnablement: { false }, programmeCurrentRequest: { _, _ in canonical },
            programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
        do { _ = try await disabled.resolve(for: canonical.usingRegistryMatch(association), now: kickoff); XCTFail("CS off") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertTrue(CommunitySportsFixtureProtocol.paths.isEmpty)
        let state = CSProgrammeTestState(), gate = CommunitySportsFixtureGate("derived channel metadata pending")
        CommunitySportsFixtureProtocol.setResponse(.controlled(gate), for: "/meta/tv/\(association.broadcast.providerEventID).json")
        let enabled = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
            programmeAssociations: { request, at in
                guard await state.available else { return [] }
                return snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at)
            })
        let clock = kickoff
        let work = Task { try await enabled.resolve(for: canonical.usingRegistryMatch(association), now: clock) }
        defer { work.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        await state.set(false)
        gate.respond(try .json(["meta": row]))
        do { _ = try await work.value; XCTFail("Withdrawn programme cannot publish a fixture source") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains("/stream/tv/\(association.broadcast.streamID).json"))
    }

    @MainActor
    func testDerivedProgrammeCannotUseAnExpiredGuideOrChangedFreshChannelMetadata() async throws {
        let (snapshot, canonical) = try programmeChannelFixture(guideLifetime: 30)
        let association = try XCTUnwrap(snapshot.lookup(for: canonical, enabledProviderCodes: ["communitysports"], at: kickoff).first)
        let row = channelRow(.willow, id: association.broadcast.providerEventID)
        let session = try makeChannelSession(.willow, rows: [row])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
            programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
        do { _ = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff.addingTimeInterval(30)); XCTFail("Expired guide") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertTrue(CommunitySportsFixtureProtocol.paths.isEmpty)
        var changed = row; changed["name"] = "📺 Willow 2 Cricket"
        CommunitySportsFixtureProtocol.setResponse(try .json(["meta": changed]), for: "/meta/tv/\(association.broadcast.providerEventID).json")
        do { _ = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff); XCTFail("Changed station") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains("/stream/tv/\(association.broadcast.streamID).json"))
    }

    @MainActor
    func testFoxProgrammeResolvesFreshAUChannelThroughExistingMatchAndKeepsGuideLease() async throws {
        let (snapshot, canonical) = try programmeChannelFixture(guideLifetime: 30, fox: true)
        let matches = snapshot.lookup(for: canonical, enabledProviderCodes: ["communitysports", "reviewedtv"], at: kickoff)
        XCTAssertEqual(matches.count, 1, "A guide-only record must not become a fake TV delivery")
        let association = try XCTUnwrap(matches.first)
        XCTAssertEqual(association.decisionReceipt(at: kickoff).provenance, .foxProgramme)
        XCTAssertEqual(association.decisionReceipt(at: kickoff).guideMarket, "AU")
        let row = channelRow(.foxCricket, id: association.broadcast.providerEventID, country: "Australia")
        let session = try makeChannelSession(.foxCricket, rows: [row])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
            programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
        let choices = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff)
        let choice = try XCTUnwrap(choices.first), binding = try XCTUnwrap(choice.eventBinding)
        XCTAssertEqual(choice.matchID, canonical.matchID); XCTAssertEqual(choice.providerName, "CS1")
        XCTAssertEqual(choice.expiryTime, kickoff.addingTimeInterval(30))
        XCTAssertTrue(binding.matches(request: canonical, providerCode: "communitysports", at: kickoff.addingTimeInterval(1)))
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", channelSearchPath(.foxCricket),
            "/meta/tv/\(association.broadcast.providerEventID).json", "/stream/tv/\(association.broadcast.streamID).json"])
    }

    @MainActor
    func testFoxGuideRejectsUnknownMarketAndChangedFreshMetaBeforeRequestingMedia() async throws {
        let (snapshot, canonical) = try programmeChannelFixture(fox: true)
        let association = try XCTUnwrap(snapshot.lookup(for: canonical, enabledProviderCodes: ["communitysports"], at: kickoff).first)
        for country in ["Sports", "United Kingdom", "Australia / New Zealand"] {
            let row = channelRow(.foxCricket, id: association.broadcast.providerEventID, country: country)
            let session = try makeChannelSession(.foxCricket, rows: [row])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
                programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
                programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
            do { _ = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff); XCTFail("Unverified station edition") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
        let row = channelRow(.foxCricket, id: association.broadcast.providerEventID, country: "Australia")
        let session = try makeChannelSession(.foxCricket, rows: [row])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        CommunitySportsFixtureProtocol.setResponse(try .json(["meta": channelRow(.foxCricket,
            id: association.broadcast.providerEventID, country: "Sports")]), for: "/meta/tv/\(association.broadcast.providerEventID).json")
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session,
            programmeEnablement: { true }, programmeCurrentRequest: { _, _ in canonical },
            programmeAssociations: { request, at in snapshot.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at) })
        do { _ = try await client.resolve(for: canonical.usingRegistryMatch(association), now: kickoff); XCTFail("Changed metadata") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    @MainActor
    func testFoxProgrammeKeepsProviderOptInPolicyAndOriginalExpiryGates() throws {
        let (snapshot, canonical) = try programmeChannelFixture(fox: true)
        XCTAssertTrue(snapshot.lookup(for: canonical, enabledProviderCodes: ["reviewedtv"], at: kickoff).isEmpty)
        XCTAssertTrue(snapshot.lookup(for: canonical, enabledProviderCodes: [], at: kickoff).isEmpty)
        XCTAssertTrue(snapshot.lookup(for: canonical, enabledProviderCodes: ["communitysports"], at: kickoff.addingTimeInterval(601)).isEmpty)
        let policies: [BroadcastRegistrySnapshot.ProgrammeAccess?] = [.unknown,
            .init(entitlement: .denied, use: .eventPlayback, territory: .worldwide, reviewID: "test-only-policy", expiresAt: kickoff.addingTimeInterval(600))]
        for access in policies {
            var links = snapshot.links; links[0].access = access
            let held = BroadcastRegistrySnapshot(schemaVersion: snapshot.schemaVersion, revision: snapshot.revision,
                generatedAt: snapshot.generatedAt, providers: snapshot.providers, broadcasts: snapshot.broadcasts, links: links)
            XCTAssertTrue(held.lookup(for: canonical, enabledProviderCodes: ["communitysports"], at: kickoff).isEmpty)
        }
    }

    @MainActor
    private func programmeChannelFixture(guideLifetime: TimeInterval = 600, fox: Bool = false) throws -> (BroadcastRegistrySnapshot, StreamPlaybackRequest) {
        let home = fox ? "Adelaide Strikers Women" : "India", away = fox ? "Brisbane Heat Women" : "Australia"
        let competition = fox ? "wbbl" : "icc", fixtureID = fox ? "ca:40630" : "icc:programme-fixture"
        let station: CricketBroadcastChannel = fox ? .foxCricket : .willow
        let channelID = fox ? "nuvio_sport_fox_au" : "nuvio_sport_willow_main"
        let metadata = CricketFixtureMetadata(fixtureID: fixtureID, competitionID: competition, competitionName: "ICC",
            format: .t20, status: .live, observedAt: kickoff, verified: true, matchOrdinal: 3)
        let event = EventReference(id: "cricket-fixture:" + fixtureID, title: home + " vs " + away, category: "cricket",
            date: Int64(kickoff.addingTimeInterval(-1_800).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), sources: [], cricketFixture: metadata)
        let programme = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "reviewedtv",
            providerEventID: (fox ? "reviewed-tv:fox-programme:" : "reviewed-tv:programme:") + String(repeating: "c", count: 64),
            streamID: fox ? ReviewedTVPlaylistClient.foxGuideStreamID : ReviewedTVPlaylistClient.providerEventID,
            resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket", title: "India vs Australia T20",
            participants: [home, away], start: event.kickoffDate!, end: kickoff.addingTimeInterval(3_600), competitionID: competition, squad: fox ? .init(gender: .women, ageGroup: "senior") : nil,
            format: .t20, matchOrdinal: fox ? nil : 3, channelID: station.canonicalID, observedAt: kickoff,
            expiresAt: kickoff.addingTimeInterval(guideLifetime), verification: .dated, issues: [])
        let channel = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "b", count: 64), providerCode: "communitysports",
            providerEventID: channelID, streamID: channelID, resourceType: "tv", scope: "networks",
            kind: .channel, sport: "cricket", title: "Willow Cricket", participants: [], channelID: station.canonicalID,
            stationMarket: fox ? "AU" : "US", observedAt: kickoff.addingTimeInterval(-3_600), expiresAt: kickoff.addingTimeInterval(3_600), verification: .undated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: programme.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .programme, fixtureFingerprint: .init(fixtureID: event.id, sport: "cricket", start: event.kickoffDate!,
                participants: [home, away], competitionID: competition, squad: nil,
                format: .t20, matchOrdinal: 3), expiresAt: programme.expiresAt)
        let providers = [BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket", status: .available,
            observedAt: kickoff, expiresAt: programme.expiresAt), .init(providerCode: "communitysports", scope: "networks", status: .available,
            observedAt: channel.observedAt, expiresAt: channel.expiresAt)]
        let raw = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "cs-programme", generatedAt: kickoff,
            providers: providers, broadcasts: [programme, channel], links: [link])
        return (try BroadcastRegistrySnapshot.validated(from: raw.encoded(), at: kickoff), StreamPlaybackRequest(event: event))
    }

    @MainActor
    func testSkyFootballUsesExactUKNetworkMetadataAndKeepsCSAttribution() async throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV11"))
        let request = StreamPlaybackRequest(event: station.event)
        var row = channelRow(.willow, id: "nuvio_sport_sky_football", country: "United Kingdom")
        row["name"] = "📺 Sky Sports Football"
        let transport = try makeChannelSession(.willow, rows: [row], searchTitle: station.title)
        defer { transport.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: transport)
        let sources = try await client.resolve(for: request, now: kickoff)
        let source = try XCTUnwrap(sources.first), binding = try XCTUnwrap(source.eventBinding)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(source.providerName, "CS1")
        XCTAssertEqual(source.diagnosticMetadata["manifest_result"], "exact_channel_match")
        XCTAssertEqual(binding.providerEventID, "nuvio_sport_sky_football")
        XCTAssertTrue(binding.matches(request: request, providerCode: "communitysports", at: kickoff))
        XCTAssertNil(binding.kickoffDate)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json",
            "/catalog/tv/nuvio_sports_networks/search=Sky Sports Football.json",
            "/meta/tv/nuvio_sport_sky_football.json", "/stream/tv/nuvio_sport_sky_football.json"])
        // Fresh resolution retains the same station and binding identity.
        let fresh = try await client.resolve(for: request, now: kickoff.addingTimeInterval(5), forceRefresh: true)
        XCTAssertNotNil(source.renewingDelivery(from: try XCTUnwrap(fresh.first), for: request, at: kickoff.addingTimeInterval(5)))
    }

    @MainActor
    func testFS1AndSkyStationsRequireTheirOwnNetworkEdition() async throws {
        for (provider, country) in [("TV24", "United States"), ("TV10", "United Kingdom"), ("CS-SkyMain", "United Kingdom")] {
            let station = try XCTUnwrap(SportsTVStation.station(provider: provider))
            let request = StreamPlaybackRequest(event: station.event)
            for offeredCountry in [country, "Canada"] {
                var row = channelRow(.willow, id: "nuvio_sport_station", country: offeredCountry)
                row["name"] = provider == "TV24" ? "📺 FOX Sports 1" : "📺 " + station.title
                let transport = try makeChannelSession(.willow, rows: [row], searchTitle: station.title)
                defer { transport.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
                let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: transport)
                if country == offeredCountry {
                    let sessions = try await client.resolve(for: request, now: kickoff)
                    let source = try XCTUnwrap(sessions.first)
                    XCTAssertEqual(source.providerName, "CS1")
                    XCTAssertTrue(source.eventBinding?.matches(request: request, providerCode: "communitysports", at: kickoff) == true)
                } else {
                    do { _ = try await client.resolve(for: request, now: kickoff); XCTFail("Wrong station edition") }
                    catch { XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") }) }
                }
            }
        }
    }

    @MainActor
    func testFS1DoesNotAcceptMexicoEditionWithUSCountryMetadata() async throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV24"))
        var row = channelRow(.willow, id: "nuvio_sport_station", country: "United States")
        row["name"] = "📺 FOX Sports 1 Mx"
        let transport = try makeChannelSession(.willow, rows: [row], searchTitle: station.title)
        defer { transport.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: transport)
        do {
            _ = try await client.resolve(for: StreamPlaybackRequest(event: station.event), now: kickoff)
            XCTFail("A regional FS1 variant is not the US station")
        } catch {
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    @MainActor
    func testSkyFootballCannotBorrowAnotherStationCountryOrChangedMetadata() async throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV11"))
        let request = StreamPlaybackRequest(event: station.event)
        var exact = channelRow(.willow, id: "nuvio_sport_sky_football", country: "United Kingdom")
        exact["name"] = "📺 Sky Sports Football"
        for mutation in ["country", "station", "metadata", "duplicate"] {
            var row = exact
            if mutation == "country" { row["description"] = "🏆 League: United States\n📅 Category: NETWORKS\n⏰ Status: 24/7 Live Network" }
            if mutation == "station" { row["name"] = "📺 Sky Sports Premier League" }
            var rows = [row]
            if mutation == "duplicate" { var conflict = exact; conflict["name"] = "📺 Willow Cricket"; rows.append(conflict) }
            let transport = try makeChannelSession(.willow, rows: rows, searchTitle: station.title)
            if mutation == "metadata" { var changed = exact; changed["name"] = "📺 Sky Sports Main Event"
                CommunitySportsFixtureProtocol.setResponse(try .json(["meta": changed]), for: "/meta/tv/nuvio_sport_sky_football.json") }
            do {
                _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
                    session: transport).resolve(for: request, now: kickoff)
                XCTFail("Must reject \(mutation)")
            } catch { XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") }, mutation) }
            transport.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset()
        }
        let other = try XCTUnwrap(SportsTVStation.station(provider: "TV12"))
        XCTAssertFalse(CommunitySportsAddonClient.supportsSportsTVChannel(StreamPlaybackRequest(event: other.event)))
    }

    func testCanonicalCricketChannelsUseAdvertisedNetworkIdentityWithoutInventingFixture() async throws {
        for channel in CricketBroadcastChannel.allCases {
            let row = channelRow(channel, id: "nuvio_sport_channel")
            let session = try makeChannelSession(channel, rows: [row])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let request = channelRequest(channel)
            let sources = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
                session: session).resolve(for: request, now: kickoff)
            XCTAssertEqual(sources.count, 1)
            let binding = try XCTUnwrap(sources.first?.eventBinding)
            XCTAssertNil(binding.kickoffDate)
            XCTAssertEqual(binding.providerEventID, "nuvio_sport_channel")
            XCTAssertTrue(binding.matches(request: request, providerCode: StreamPluginProviderMatching.communitySportsProviderCode, at: kickoff))
            XCTAssertEqual(sources.first?.diagnosticMetadata["manifest_result"], "exact_channel_match")
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", channelSearchPath(channel),
                "/meta/tv/nuvio_sport_channel.json", "/stream/tv/nuvio_sport_channel.json"])
        }
    }

    func testTwoDistinctMainWillowNetworkDeliveriesRemainAvailableButWillowTwoDoesNotSubstitute() async throws {
        let us = channelRow(.willow, id: "nuvio_sport_willow_us")
        let uk = channelRow(.willow, id: "nuvio_sport_willow_uk", country: "United Kingdom")
        var alternate = channelRow(.willow, id: "nuvio_sport_willow_two")
        alternate["name"] = "📺 Willow 2 Cricket"
        let session = try makeChannelSession(.willow, rows: [us, us, uk, alternate])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let sources = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
            session: session).resolve(for: channelRequest(.willow), now: kickoff)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(Set(sources.compactMap { $0.eventBinding?.providerEventID }),
            ["nuvio_sport_willow_us", "nuvio_sport_willow_uk"])
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }.count, 2)
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.contains("willow_two") })
    }

    func testChannelCatalogSharedIdentityConflictVetoesBeforeAnyMetadataOrDescriptor() async throws {
        let exact = channelRow(.willow, id: "nuvio_sport_shared")
        var wrongChannel = exact; wrongChannel["name"] = "📺 Willow 2 Cricket"
        var wrongGenre = exact; wrongGenre["genres"] = ["CRICKET"]
        var dated = exact; dated["released"] = "2026-10-30T08:00:00.000Z"
        var wrongDescription = exact; wrongDescription["description"] = "🏆 League: United States\n📅 Category: NETWORKS\n⏰ Status: LIVE match"
        var otherIDSameTarget = wrongChannel; otherIDSameTarget["id"] = "nuvio_sport_other"
        for conflict in [wrongChannel, wrongGenre, dated, wrongDescription, otherIDSameTarget] {
            let session = try makeChannelSession(.willow, rows: [exact, conflict])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            do {
                _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
                    session: session).resolve(for: channelRequest(.willow), now: kickoff)
                XCTFail("A contradictory advertised identity must not be hidden")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/meta/") || $0.hasPrefix("/stream/") })
        }
    }

    func testChannelMetadataMustCorroborateEveryCatalogIdentityBeforeDescriptors() async throws {
        let us = channelRow(.willow, id: "nuvio_sport_us")
        let uk = channelRow(.willow, id: "nuvio_sport_uk", country: "United Kingdom")
        let session = try makeChannelSession(.willow, rows: [us, uk])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        var wrong = uk; wrong["behaviorHints"] = ["defaultVideoId": "nuvio_sport_unadvertised"]
        CommunitySportsFixtureProtocol.setResponse(try .json(["meta": wrong]), for: "/meta/tv/nuvio_sport_uk.json")
        do {
            _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
                session: session).resolve(for: channelRequest(.willow), now: kickoff)
            XCTFail("Metadata cannot replace the advertised target")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testChannelSearchRequiresAdvertisedNetworkCatalogAndSearchCapability() async throws {
        for catalogs in [[], [["id": "nuvio_sports_networks", "type": "tv"]],
            [["id": "nuvio_sports_networks", "type": "movie", "extra": [["name": "search"]]]]] as [[[String: Any]]] {
            let session = try makeChannelSession(.foxCricket, rows: [channelRow(.foxCricket)])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            CommunitySportsFixtureProtocol.setResponse(try .json(["id": "community.nuvio.live-sports", "version": "3.1.3",
                "resources": ["catalog", "meta", "stream"], "catalogs": [["id": "nuvio_sports_live", "type": "tv"]] + catalogs]), for: "/manifest.json")
            do {
                _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
                    session: session).resolve(for: channelRequest(.foxCricket), now: kickoff)
                XCTFail("Never guess a channel route")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidManifest) }
            XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json"])
        }
    }

    func testChannelLookupCachesCatalogButRevalidatesMetadataAndForcedRefreshReplacesIt() async throws {
        let original = channelRow(.foxCricket, id: "nuvio_sport_original")
        let replacement = channelRow(.foxCricket, id: "nuvio_sport_replacement")
        let session = try makeChannelSession(.foxCricket, rows: [original])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        _ = try await client.resolve(for: channelRequest(.foxCricket), now: kickoff)
        _ = try await client.resolve(for: channelRequest(.foxCricket), now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == channelSearchPath(.foxCricket) }.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/meta/tv/nuvio_sport_original.json" }.count, 2)
        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [replacement]]), for: channelSearchPath(.foxCricket))
        CommunitySportsFixtureProtocol.setResponse(try .json(["meta": replacement]), for: "/meta/tv/nuvio_sport_replacement.json")
        CommunitySportsFixtureProtocol.setResponse(try .json(["streams": [["url": "https://addon.example/api/manifest?channel=replacement"]]]),
            for: "/stream/tv/nuvio_sport_replacement.json")
        let refreshed = try await client.resolve(for: channelRequest(.foxCricket), now: kickoff.addingTimeInterval(2), forceRefresh: true)
        XCTAssertEqual(refreshed.first?.eventBinding?.providerEventID, "nuvio_sport_replacement")
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == channelSearchPath(.foxCricket) }.count, 2)
    }

    func testChannelDescriptorFailureDoesNotDiscardIndependentMainChannelDelivery() async throws {
        let us = channelRow(.willow, id: "nuvio_sport_us")
        let uk = channelRow(.willow, id: "nuvio_sport_uk", country: "United Kingdom")
        let session = try makeChannelSession(.willow, rows: [us, uk])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        CommunitySportsFixtureProtocol.setResponse(.status(503), for: "/stream/tv/nuvio_sport_us.json")
        let result = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
            session: session).resolve(for: channelRequest(.willow), now: kickoff)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.eventBinding?.providerEventID, "nuvio_sport_uk")
    }

    func testChannelDescriptorsRetainExistingDeliveryAndHeaderRestrictions() async throws {
        let session = try makeChannelSession(.foxCricket, rows: [channelRow(.foxCricket)])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        CommunitySportsFixtureProtocol.setResponse(try .json(["streams": [
            ["url": "http://addon.example/api/manifest?channel=insecure"],
            ["url": "https://127.0.0.1/stream.m3u8"],
            ["url": "https://unreviewed.example/stream.m3u8"],
            ["url": "https://addon.example/api/manifest?channel=headers", "behaviorHints": ["proxyHeaders": ["response": ["Access-Control-Allow-Origin": "*"]]]]
        ]]), for: "/stream/tv/nuvio_sport_channel.json")
        do {
            _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!,
                session: session).resolve(for: channelRequest(.foxCricket), now: kickoff)
            XCTFail("Channel identity grants no delivery-security exception")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 4)) }
    }

    @MainActor
    func testCancelledChannelCatalogCannotPublishCacheOrStartMetadataAndDescriptors() async throws {
        let gate = CommunitySportsFixtureGate("channel catalog cancellation")
        let row = channelRow(.willow)
        let session = try makeChannelSession(.willow, rows: [row])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        CommunitySportsFixtureProtocol.setResponse(.controlled(gate), for: channelSearchPath(.willow))
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let task = Task { try await client.resolve(for: channelRequest(.willow), now: kickoff) }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        task.cancel(); gate.respond(try .json(["metas": [row]]))
        do { _ = try await task.value; XCTFail("Cancelled channel resolution") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/meta/") || $0.hasPrefix("/stream/") })
        CommunitySportsFixtureProtocol.setResponse(try .json(["metas": [row]]), for: channelSearchPath(.willow))
        _ = try await client.resolve(for: channelRequest(.willow), now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == channelSearchPath(.willow) }.count, 2)
    }

    @MainActor
    func testRegisteredEventUsesExactMetadataAndDescriptorWithoutSearchingAnotherCatalog() async throws {
        let request = try registryFixtureRequest()
        let row = catalogEntry(teams: ["Chelsea", "Brighton"])
        let session = try makeFixtureSession(manifestResponse: .json([
            "id": "community.nuvio.live-sports", "version": "3.1.3",
            "resources": ["catalog", "meta", "stream"], "catalogs": [["id": "nuvio_sports_live", "type": "tv"]]
        ]), searchResponses: ["/meta/tv/nuvio_sport_fixture.json": try .json(["meta": row])])
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
        let sessions = try await client.resolve(for: request, now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", "/meta/tv/nuvio_sport_fixture.json", "/stream/tv/nuvio_sport_fixture.json"])
        let binding = try XCTUnwrap(sessions.first?.eventBinding)
        XCTAssertTrue(binding.usesRegistryAssociation)
        XCTAssertTrue(binding.matches(request: request, providerCode: "communitysports", at: kickoff))
        XCTAssertEqual(binding.fixtureID, request.matchID)
    }

    @MainActor
    func testLiveNHLPublisherHandoffSurvivesRegisteredCoordinatorAndRenewsActualID() async throws {
        let h = try nhlHandoff()
        defer { h.session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: h.session)
        let clock = kickoff
        let choices = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: h.request,
            providerCode: "communitysports", associations: [h.parent], resolve: { scoped in
                try await client.resolve(for: scoped, now: clock, forceRefresh: true)
            }, clock: { clock })
        let first = try XCTUnwrap(choices.first)
        let binding = try XCTUnwrap(first.eventBinding)
        XCTAssertEqual(binding.providerEventID, h.newID)
        XCTAssertEqual(binding.streamID, h.newID)
        XCTAssertTrue(binding.usesCSProviderHandoff)
        XCTAssertTrue(binding.matchesRegistryEntry(h.parent, request: h.request, at: clock))
        XCTAssertEqual(binding.currentRegistryEntry(in: [h.parent], request: h.request, at: clock), h.parent)
        XCTAssertNil(binding.currentRegistryEntry(in: [h.parent, h.parent], request: h.request, at: clock))
        XCTAssertFalse(binding.matches(request: h.request, providerCode: "communitysports", at: clock.addingTimeInterval(90)))
        let nextClock = clock.addingTimeInterval(1)
        let renewOwner = try XCTUnwrap(binding.currentRegistryEntry(in: [h.parent], request: h.request, at: nextClock))
        let refreshed = try await client.resolve(for: h.request.usingRegistryMatch(renewOwner), now: nextClock, forceRefresh: true)
        let renewed = try XCTUnwrap(refreshed.first)
        XCTAssertNotNil(first.renewingDelivery(from: renewed, for: h.request, at: nextClock))
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths.filter { $0 == "/stream/tv/" + h.newID + ".json" }.count, 2)
        XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains("/stream/tv/" + h.oldID + ".json"))
    }

    @MainActor
    func testUncorroboratedNHLHandoffCannotReachDescriptor() async throws {
        for scenario in ["ambiguous", "wrong-date", "wrong-programme", "wrong-squad", "terminal", "expired", "wrong-target", "extra-time", "cricket"] {
            let h = try nhlHandoff(scenario)
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: h.session)
            do {
                _ = try await client.resolve(for: h.request.usingRegistryMatch(h.parent), now: kickoff, forceRefresh: true)
                XCTFail("Unexpected admission for \(scenario)")
            } catch let error as CommunitySportsAddonError { XCTAssertEqual(error, .conflictingMatch, scenario) }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains(where: { $0.hasPrefix("/stream/") }), scenario)
            h.session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset()
        }
    }

    @MainActor
    private func nhlHandoff(_ scenario: String = "accepted") throws ->
        (request: StreamPlaybackRequest, parent: BroadcastRegistryMatch, session: URLSession, oldID: String, newID: String) {
        let teams = ["Home Hockey Club", "Visiting Hockey Club"]
        let old = "nuvio_sport_dlv_20_visiting-hockey-club-vs-home-hockey-club"
        let next = "nuvio_sport_ts_visiting-hockey-club-v-home-hockey-club-12345"
        let sport = scenario == "cricket" ? "cricket" : "hockey"
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:nhl:live", sport: sport,
            competitionID: "nhl", competitionName: "NHL", eventKind: .match, title: teams.joined(separator: " vs "),
            participants: teams.map { .init(id: $0, name: $0) }, squad: .init(gender: scenario == "wrong-squad" ? .women : .men,
            ageGroup: "senior"), status: scenario == "terminal" ? .finished : .live, observedAt: kickoff, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: sport,
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0], badge: nil), away: .init(name: teams[1], badge: nil)), sources: [], sportsFixture: metadata)
        let request = StreamPlaybackRequest(event: event)
        let end = kickoff.addingTimeInterval(scenario == "expired" ? 0 : 600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "1", count: 64), providerCode: "communitysports",
            providerEventID: old, streamID: old, resourceType: "tv", scope: sport, kind: .event, sport: sport,
            title: metadata.title, participants: teams, start: kickoff, observedAt: kickoff.addingTimeInterval(-60),
            expiresAt: kickoff.addingTimeInterval(1200), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: record.providerCode,
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: sport, start: kickoff,
                participants: teams, competitionID: metadata.competitionID, squad: metadata.squad), expiresAt: end)
        let parent = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: "communitysports", scope: sport,
            status: .partial, observedAt: kickoff, expiresAt: record.expiresAt))
        var row = batchCatalogRow(id: next, teams: teams, genre: "HOCKEY")
        row["releaseInfo"] = "LIVE"
        var meta = row
        if scenario == "wrong-date" { meta["released"] = "2026-09-12T20:05:00Z" }
        if scenario == "wrong-programme" { meta["name"] = "New York vs Chicago" }
        if scenario == "wrong-target" { meta["behaviorHints"] = ["defaultVideoId": next + "2"] }
        if scenario == "extra-time" { meta["kickoff"] = "2026-09-12T20:05:00Z" }
        var others: [[String: Any]] = [row]
        if scenario == "ambiguous" {
            var duplicate = row
            duplicate["id"] = next + "2"; duplicate["behaviorHints"] = ["defaultVideoId": next + "2"]
            others.append(duplicate)
        }
        let session = try makeFixtureSession(manifestResponse: .json(["id":"community.nuvio.live-sports","version":"3.1.3",
            "resources":["catalog","meta","stream"],"catalogs":[["id":"nuvio_sports_live","type":"tv"],["id":"nuvio_sports_hockey","type":"tv"]]]),
            searchResponses: ["/meta/tv/" + old + ".json": try .json(["meta": row]), "/meta/tv/" + next + ".json": try .json(["meta": meta]),
                "/catalog/tv/nuvio_sports_hockey.json": try .json(["metas": others]),
                "/stream/tv/" + next + ".json": try .json(["streams":[["url":"https://addon.example/api/manifest?channel=fixture", "_source":"upstream-a"]]])])
        return (request, parent, session, old, next)
    }

    @MainActor
    func testRegisteredEventRejectsChangedIDParticipantsOrTimeBeforeDescriptorFetch() async throws {
        let request = try registryFixtureRequest()
        var wrongID = catalogEntry(teams: ["Chelsea", "Brighton"]); wrongID["id"] = "nuvio_sport_other"
        var wrongTime = catalogEntry(teams: ["Chelsea", "Brighton"]); wrongTime["released"] = "2026-09-13T20:06:00Z"
        for row in [wrongID, wrongTime, catalogEntry(teams: ["Chelsea", "Fulham"])] {
            let session = try makeFixtureSession(manifestResponse: .json([
                "id": "community.nuvio.live-sports", "version": "3.1.3", "resources": ["catalog", "meta", "stream"],
                "catalogs": [["id": "nuvio_sports_live", "type": "tv"]]
            ]), searchResponses: ["/meta/tv/nuvio_sport_fixture.json": try .json(["meta": row])])
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            do {
                _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
                    .resolve(for: request, now: kickoff)
                XCTFail("Registry metadata must not authorize a changed same-ID programme")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") || $0.hasPrefix("/catalog/") })
        }
    }

    func testDynamicCricketListingDoesNotTurnItsSyntheticReleasedClockIntoKickoff() throws {
        let now = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T12:00:19.025Z"))
        let entry = try decodeCurrentCricketRow(currentCricketRow())
        let identity = try XCTUnwrap(CommunitySportsAddonClient.currentCricketListingIdentity(for: entry, at: now))
        XCTAssertEqual(identity.sport, "cricket")
        XCTAssertEqual(identity.pair, BroadcastRegistrySnapshot.participantPair(["Ireland", "Namibia"], sport: "cricket"))
        let request = StreamPlaybackRequest(matchID: "unregistered", displayTitle: "Namibia vs Ireland",
            homeTeam: "Namibia", awayTeam: "Ireland", category: "cricket",
            kickoffDate: try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T07:30:00Z")))
        XCTAssertEqual(CommunitySportsAddonClient.selectMatch(for: request, from: [entry]), .missing,
                       "The current listing alone has no authority to replace the official fixture's kickoff")
    }

    func testDynamicCricketListingContractRejectsOtherSourcesReplaysSquadConflictsAndExtraClocks() throws {
        let now = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T12:00:19.025Z"))
        let invalid: [[String: Any]] = [
            ["id": "nuvio_sport_other_4250335"], ["id": "nuvio_sport_sktech_sktech_ev_fancode_4250335x"],
            ["type": "movie"], ["genres": ["FOOTBALL"]], ["genres": ["CRICKET", "NETWORKS"]],
            ["releaseInfo": "UPCOMING"], ["name": "🔴 LIVE: Ireland vs Namibia Highlights"],
            ["name": "🔴 LIVE: Ireland Women vs Namibia Women", "cast": ["Ireland", "Namibia"]],
            ["name": "🔴 LIVE: Ireland vs Australia"], ["cast": ["Ireland", "Australia"]],
            ["cast": ["Ireland\u{202e}", "Namibia"]], ["cast": ["Ireland\n", "Namibia"]],
            ["name": "Ireland vs Namibia"], ["released": "2026-11-01T08:00:19.024Z"],
            ["released": "2026-11-01T12:05:19.026Z"], ["released": "not-a-date"],
            ["description": "🏆 League: 5th ODI\n📅 Category: CRICKET\n⏰ Status: 🔴 LIVE NOW"],
            ["description": "🏆 League: Cricket\n📅 Category: CRICKET\n⏰ Status: Replay"],
            ["behaviorHints": ["defaultVideoId": "nuvio_sport_other"]],
            ["date": NSNull()], ["startTime": "2026-11-01T07:30:00Z"], ["kickoff": NSNull()], ["videos": []]
        ]
        for mutation in invalid {
            let row = currentCricketRow().merging(mutation, uniquingKeysWith: { _, replacement in replacement })
            XCTAssertNil(CommunitySportsAddonClient.currentCricketListingIdentity(for: try decodeCurrentCricketRow(row), at: now),
                         "Changed current-listing contract must not authorize an event: \(mutation.keys.sorted())")
        }
        for value in ["2026-11-01T08:00:19.025Z", "2026-11-01T12:05:19.025Z"] {
            var row = currentCricketRow(); row["released"] = value
            XCTAssertNotNil(CommunitySportsAddonClient.currentCricketListingIdentity(for: try decodeCurrentCricketRow(row), at: now))
        }
    }

    @MainActor
    func testRegisteredCurrentCricketAcceptsChangedSyntheticClockAfterFreshExactMetadata() async throws {
        let (request, now) = try currentCricketRegistryRequest()
        let row = currentCricketRow(), id = try XCTUnwrap(row["id"] as? String)
        let session = try makeCurrentCricketSession(row: row)
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        let result = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            .resolve(for: request, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(CommunitySportsFixtureProtocol.paths, ["/manifest.json", "/meta/tv/\(id).json", "/stream/tv/\(id).json"])
        XCTAssertTrue(try XCTUnwrap(result.first?.eventBinding).matches(request: request, providerCode: "communitysports", at: now))
    }

    @MainActor
    func testRegisteredCurrentCricketUsesRegistryListingLifetimeWithoutRenewingEvidence() async throws {
        let (request, now) = try currentCricketRegistryRequest()
        // Real failure: the same-ID endpoint is fetched now, but its generated
        // released clock is older than 10 minutes inside the published 4h cache.
        for age: TimeInterval in [601, 25 * 60, 2 * 3600, 4 * 3600 - 30] {
            var row = currentCricketRow()
            row["released"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(-age))
            let session = try makeCurrentCricketSession(row: row)
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let result = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
                .resolve(for: request, now: now)
            XCTAssertEqual(result.count, 1)
            let binding = try XCTUnwrap(result.first?.eventBinding)
            XCTAssertTrue(binding.matches(request: request, providerCode: "communitysports", at: now))
            let released = try XCTUnwrap((row["released"] as? String).flatMap(BroadcastRegistrySnapshot.date))
            XCTAssertLessThanOrEqual(binding.expiresAt, released.addingTimeInterval(BroadcastRegistrySnapshot.sourceLifetime))
            XCTAssertLessThanOrEqual(binding.expiresAt, now.addingTimeInterval(StreamEventBinding.metadataLifetime))
            let reads = CommunitySportsFixtureProtocol.requests.filter { $0.url?.path.hasPrefix("/meta/") == true }
            XCTAssertEqual(reads.count, 1)
            XCTAssertEqual(reads.first?.cachePolicy, .reloadIgnoringLocalCacheData)
        }
    }

    @MainActor
    func testRegisteredCurrentCricketCannotUseExpiredListingOrRenewOfficialReceipt() async throws {
        for observedAge: TimeInterval in [0, 580] {
            let (request, now) = try currentCricketRegistryRequest(observedAge: observedAge)
            var row = currentCricketRow()
            row["released"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(observedAge == 0 ? -14401 : -1800))
            let session = try makeCurrentCricketSession(row: row)
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
            if observedAge == 0 {
                do { _ = try await client.resolve(for: request, now: now); XCTFail("Expired listing must not resolve") }
                catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
                XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
            } else {
                let result = try await client.resolve(for: request, now: now)
                XCTAssertLessThanOrEqual(try XCTUnwrap(result.first?.eventBinding).expiresAt, now.addingTimeInterval(20))
            }
        }
    }

    @MainActor
    func testRegisteredCurrentCricketRejectsChangedFreshIdentityBeforeAnyStreamFetch() async throws {
        let (request, now) = try currentCricketRegistryRequest()
        for mutation: [String: Any] in [["cast": ["Ireland", "Australia"]], ["released": "2026-10-31T12:00:19.025Z"],
                                       ["releaseInfo": "REPLAY"], ["date": "2026-11-01"],
                                       ["behaviorHints": ["defaultVideoId": "nuvio_sport_other"]]] {
            let row = currentCricketRow().merging(mutation, uniquingKeysWith: { _, replacement in replacement })
            let session = try makeCurrentCricketSession(row: row)
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            do {
                _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
                    .resolve(for: request, now: now)
                XCTFail("Changed current listing must not request any stream")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(CommunitySportsFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") || $0.hasPrefix("/catalog/") })
        }
    }

    @MainActor
    func testRegisteredCurrentCricketRejectsStaleOrTerminalOfficialFixtureBeforeNetwork() async throws {
        for status in [CricketFixtureCatalog.Status.finished, .scheduled] {
            let (request, now) = try currentCricketRegistryRequest(status: status)
            let session = try makeCurrentCricketSession(row: currentCricketRow())
            defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
            do {
                _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
                    .resolve(for: request, now: now)
                XCTFail("Only the official currently-live fixture may own a current listing")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertTrue(CommunitySportsFixtureProtocol.paths.isEmpty)
        }
        let (request, now) = try currentCricketRegistryRequest(observedAge: 601)
        let session = try makeCurrentCricketSession(row: currentCricketRow())
        defer { session.invalidateAndCancel(); CommunitySportsFixtureProtocol.reset() }
        do {
            _ = try await CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, session: session)
                .resolve(for: request, now: now)
            XCTFail("Stale official live receipt must not authorize a current listing")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertTrue(CommunitySportsFixtureProtocol.paths.isEmpty)
    }

    private func currentCricketRow() -> [String: Any] {
        let id = "nuvio_sport_sktech_sktech_ev_fancode_4250335"
        return ["id": id, "type": "tv", "name": "🔴 LIVE: Ireland vs Namibia", "genres": ["CRICKET"],
                "cast": ["Ireland", "Namibia"], "released": "2026-11-01T12:00:19.025Z", "releaseInfo": "LIVE",
                "behaviorHints": ["defaultVideoId": id],
                "description": "🏆 League: Cricket\n📅 Category: CRICKET\n⏰ Status: 🔴 LIVE NOW"]
    }

    private func decodeCurrentCricketRow(_ row: [String: Any]) throws -> CommunitySportsCatalogEntry {
        try JSONDecoder().decode(CommunitySportsCatalogEntry.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private func makeCurrentCricketSession(row: [String: Any]) throws -> URLSession {
        let id = try XCTUnwrap(currentCricketRow()["id"] as? String)
        return try makeFixtureSession(manifestResponse: .json([
            "id": "community.nuvio.live-sports", "version": "3.1.3", "resources": ["catalog", "meta", "stream"],
            "catalogs": [["id": "nuvio_sports_live", "type": "tv"], ["id": "nuvio_sports_cricket", "type": "tv"]]
        ]), searchResponses: ["/meta/tv/\(id).json": try .json(["meta": row]),
            "/stream/tv/\(id).json": try .json(["streams": [["url": "https://addon.example/api/manifest?channel=fixture", "_source": "sktech"]]])])
    }

    @MainActor
    private func currentCricketRegistryRequest(status: CricketFixtureCatalog.Status = .live,
                                               observedAge: TimeInterval = 0) throws -> (StreamPlaybackRequest, Date) {
        let now = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T12:00:19.025Z"))
        let start = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T07:30:00Z"))
        let metadata = CricketFixtureMetadata(fixtureID: "icc:275415", competitionID: "icc", competitionName: "Ireland in Namibia, 5 ODI Series",
            format: .odi, status: status, observedAt: now.addingTimeInterval(-observedAge), verified: true, matchOrdinal: 5)
        let event = EventReference(id: "cricket-fixture:icc:275415", title: "Namibia vs Ireland", category: "cricket",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Namibia", badge: nil), away: .init(name: "Ireland", badge: nil)), sources: [], cricketFixture: metadata)
        let id = try XCTUnwrap(currentCricketRow()["id"] as? String)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "communitysports",
            providerEventID: id, streamID: id, resourceType: "tv", scope: "cricket", kind: .event, sport: "cricket",
            title: "🔴 LIVE: Ireland vs Namibia", participants: ["Ireland", "Namibia"],
            start: try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T10:08:39.913Z")), startBasis: "current-listing",
            observedAt: now, expiresAt: now.addingTimeInterval(600), verification: .undated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: record.providerCode,
            state: .listed, matchMethod: .currentEvent,
            fixtureFingerprint: .init(fixtureID: event.id, sport: "cricket", start: start, participants: ["Namibia", "Ireland"],
                competitionID: "icc", format: .odi, matchOrdinal: 5), expiresAt: record.expiresAt)
        let association = BroadcastRegistryMatch(broadcast: record, link: link,
            provider: .init(providerCode: record.providerCode, scope: "cricket", status: .available,
                observedAt: now, expiresAt: record.expiresAt))
        return (StreamPlaybackRequest(event: event).usingRegistryMatch(association), now)
    }

    @MainActor
    private func registryFixtureRequest() throws -> StreamPlaybackRequest {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:chelsea-brighton", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "Chelsea vs Brighton",
            participants: [.init(id: "chelsea", name: "Chelsea"), .init(id: "brighton", name: "Brighton")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: kickoff, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Chelsea", badge: nil), away: .init(name: "Brighton", badge: nil)), sources: [], sportsFixture: metadata)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "communitysports",
            providerEventID: "nuvio_sport_fixture", streamID: "nuvio_sport_fixture", resourceType: "tv", scope: "football", kind: .event,
            sport: "football", title: metadata.title, participants: ["Chelsea", "Brighton"], start: kickoff,
            observedAt: kickoff, expiresAt: kickoff.addingTimeInterval(600), verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: record.providerCode,
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: kickoff,
                participants: record.participants, competitionID: "premier-league", squad: metadata.squad), expiresAt: record.expiresAt)
        let match = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: record.providerCode,
            scope: record.scope, status: .available, observedAt: kickoff, expiresAt: record.expiresAt))
        let request = StreamPlaybackRequest(event: event)
        XCTAssertTrue(match.matches(request: request, providerCode: record.providerCode, providerEventID: record.providerEventID,
            streamID: record.streamID, at: kickoff))
        return request.usingRegistryMatch(match)
    }

    private func channelRequest(_ channel: CricketBroadcastChannel) -> StreamPlaybackRequest {
        .init(matchID: channel.canonicalID, displayTitle: channel.title, homeTeam: channel.title,
              awayTeam: "", category: "cricket", kickoffDate: nil)
    }

    private func channelSearchPath(_ channel: CricketBroadcastChannel) -> String {
        "/catalog/tv/nuvio_sports_networks/search=\(channel.title).json"
    }

    private func channelRow(_ channel: CricketBroadcastChannel, id: String = "nuvio_sport_channel",
                            country: String = "United States") -> [String: Any] {
        ["id": id, "type": "tv", "name": channel == .willow ? "📺 Willow Cricket" : "📺 FOX Cricket",
         "genres": ["NETWORKS"], "releaseInfo": "LIVE", "behaviorHints": ["defaultVideoId": id],
         "description": "🏆 League: \(country)\n📅 Category: NETWORKS\n⏰ Status: 24/7 Live Network"]
    }

    private func makeChannelSession(_ channel: CricketBroadcastChannel, rows: [[String: Any]], searchTitle: String? = nil) throws -> URLSession {
        var responses: [String: CommunitySportsFixtureProtocol.Response] = [
            "/manifest.json": try .json(["id": "community.nuvio.live-sports", "version": "3.1.3",
                "resources": ["catalog", "meta", "stream"], "catalogs": [["id": "nuvio_sports_live", "type": "tv"], ["id": "nuvio_sports_networks", "type": "tv",
                    "extra": [["name": "search", "isRequired": false]]]]]),
            searchTitle.map { "/catalog/tv/nuvio_sports_networks/search=\($0).json" } ?? channelSearchPath(channel): try .json(["metas": rows])
        ]
        for row in rows {
            let id = try XCTUnwrap(row["id"] as? String)
            responses["/meta/tv/\(id).json"] = try .json(["meta": row])
            responses["/stream/tv/\(id).json"] = try .json(["streams": [["url": "https://addon.example/api/manifest?channel=\(id)", "_source": id]]])
        }
        CommunitySportsFixtureProtocol.configure(responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommunitySportsFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func batchRequest(id: String, teams: [String], category: String = "football", date: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: id, displayTitle: teams.joined(separator: " vs "), homeTeam: teams[0], awayTeam: teams[1],
              category: category, kickoffDate: date ?? kickoff)
    }

    private func batchCatalogRow(id: String, teams: [String], genre: String = "FOOTBALL") -> [String: Any] {
        ["id": id, "type": "tv", "name": teams.joined(separator: " vs "), "released": "2026-09-13T20:05:00Z",
         "genres": [genre], "cast": teams, "behaviorHints": ["defaultVideoId": id]]
    }

    private func makeRequest(home: String, away: String, category: String) -> StreamPlaybackRequest {
        StreamPlaybackRequest(
            matchID: "fotty-fixture",
            displayTitle: "\(home) vs \(away)",
            homeTeam: home,
            awayTeam: away,
            category: category,
            kickoffDate: kickoff
        )
    }

    @MainActor
    private func observedAfghanistanZimbabweProjection() throws -> EventReference {
        let observed = "2026-10-23T17:24:51.796Z"
        let now = try XCTUnwrap(CricketFixtureCatalog.date(observed))
        let fixture = CricketFixtureCatalog.Fixture(id: "icc:274659", start: "2026-10-23T11:30:00.000Z",
            format: .odi, status: .live, competitionId: "icc",
            competitionName: "ODI Tri-Series in United Arab Emirates, 2026",
            home: .init(id: "afghanistan", name: "Afghanistan"), away: .init(id: "zimbabwe", name: "Zimbabwe"),
            source: .init(name: "ICC", url: "https://www.icc-cricket.com/fixtures-results",
                          observedAt: observed, verification: .verified))
        let snapshot = CricketFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: observed,
            revision: "observed-afghanistan-zimbabwe-integration", sourceStatus: .verified, fixtures: [fixture],
            coverage: [.init(competitionId: "icc", competitionName: "ICC international cricket", status: .covered,
                checkedAt: observed, fixtureCount: 1, expectedFixtureCount: 1, nextStart: nil)])
        let accepted = try CricketFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(snapshot), now: now)
        return try XCTUnwrap(CricketFixtureCatalog.merging(into: [], snapshot: accepted, at: now).first)
    }

    private func observedAfghanistanZimbabweCSEntry() -> CommunitySportsCatalogEntry {
        makeEntry(id: "nuvio_sport_sktech_sktech_match_21_cHJvL1QwUkpJRlJ5", name: "🔴 LIVE: Zimbabwe vs Afghanistan",
            released: "2026-10-23T11:30:00.000Z", genre: "CRICKET", cast: ["Afghanistan", "Zimbabwe"])
    }

    private func makeEntry(
        id: String,
        name: String,
        released: String,
        genre: String,
        cast: [String],
        videoID: String? = nil
    ) -> CommunitySportsCatalogEntry {
        CommunitySportsCatalogEntry(
            id: id,
            type: "tv",
            name: name,
            releaseInfo: "LIVE",
            released: released,
            genres: [genre],
            cast: cast,
            behaviorHints: .init(defaultVideoId: videoID ?? id)
        )
    }

    private func catalogEntry(teams: [String]) -> [String: Any] {
        ["id": "nuvio_sport_fixture", "type": "tv", "name": teams.joined(separator: " vs "),
         "released": "2026-09-13T20:05:00Z", "genres": ["FOOTBALL"], "cast": teams,
         "behaviorHints": ["defaultVideoId": "nuvio_sport_fixture"]]
    }

    private func fixtureManifest(version: String, includeSportCatalog: Bool = true,
                                 searchCatalogs: Set<String> = []) -> [String: Any] {
        var catalogs: [[String: Any]] = [["id": "nuvio_sports_live", "type": "tv"]]
        if includeSportCatalog { catalogs.append(["id": "nuvio_sports_football", "type": "tv"]) }
        for index in catalogs.indices where searchCatalogs.contains(catalogs[index]["id"] as? String ?? "") {
            catalogs[index]["extra"] = [["name": "search", "isRequired": false]]
        }
        return ["id": "community.nuvio.live-sports", "version": version,
                "resources": ["catalog", "stream"], "catalogs": catalogs]
    }

    private func makeFixtureSession(
        includeSportCatalog: Bool = true,
        sportResponse: CommunitySportsFixtureProtocol.Response? = nil,
        liveTeams: [String] = ["Chelsea", "Brighton"],
        manifestResponse: CommunitySportsFixtureProtocol.Response? = nil,
        liveResponse: CommunitySportsFixtureProtocol.Response? = nil,
        streamResponse: CommunitySportsFixtureProtocol.Response? = nil,
        searchResponses: [String: CommunitySportsFixtureProtocol.Response] = [:]
    ) throws -> URLSession {
        let manifest = fixtureManifest(version: "3.0.0", includeSportCatalog: includeSportCatalog)
        let empty = try CommunitySportsFixtureProtocol.Response.json(["metas": []])
        let responses: [String: CommunitySportsFixtureProtocol.Response] = [
            "/manifest.json": try manifestResponse ?? .json(manifest),
            "/catalog/tv/nuvio_sports_football.json": sportResponse ?? empty,
            "/catalog/tv/nuvio_sports_live.json": try liveResponse ?? .json(["metas": [catalogEntry(teams: liveTeams)]]),
            "/stream/tv/nuvio_sport_fixture.json": try streamResponse ?? .json(["streams": [
                ["url": "https://addon.example/api/manifest?channel=fixture", "_source": "upstream-a"]
            ]])
        ]
        CommunitySportsFixtureProtocol.configure(responses.merging(searchResponses, uniquingKeysWith: { _, search in search }))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommunitySportsFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

/// Every request from the adapter's injected session terminates in this fixture.
/// No public endpoint, media request, or DNS lookup is used by these tests.
private final class CommunitySportsFixtureProtocol: URLProtocol {
    enum Response {
        case body(Data)
        case failure(Error)
        case status(Int)
        case controlled(CommunitySportsFixtureGate)

        static func json(_ value: [String: Any]) throws -> Response {
            .body(try JSONSerialization.data(withJSONObject: value))
        }
    }

    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var recordedPaths: [String] = []
    private static var recordedTimeouts: [TimeInterval] = []
    private static var recordedRequests: [URLRequest] = []
    private static var responseQueues: [String: [Response]] = [:]
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recordedRequests }
    static var paths: [String] { lock.lock(); defer { lock.unlock() }; return recordedPaths }
    static var timeouts: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recordedTimeouts }

    static func configure(_ responses: [String: Response]) {
        lock.lock(); self.responses = responses; responseQueues = [:]; recordedRequests = []; recordedPaths = []; recordedTimeouts = []; lock.unlock()
    }
    static func reset() { configure([:]) }
    static func setResponse(_ response: Response, for path: String) {
        lock.lock(); responses[path] = response; responseQueues.removeValue(forKey: path); lock.unlock()
    }

    static func setResponses(_ values: [Response], for path: String) {
        lock.lock(); responseQueues[path] = values; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.recordedPaths.append(path)
        Self.recordedTimeouts.append(request.timeoutInterval)
        Self.recordedRequests.append(request)
        let result: Response
        if var queue = Self.responseQueues[path], !queue.isEmpty {
            result = queue.removeFirst(); Self.responseQueues[path] = queue
        } else { result = Self.responses[path] ?? .failure(URLError(.fileDoesNotExist)) }
        Self.lock.unlock()
        complete(result)
    }

    private func complete(_ result: Response) {
        switch result {
        case .body(let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .status(let statusCode):
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .controlled(let gate):
            gate.start { [weak self] response in self?.complete(response) }
        }
    }

    override func stopLoading() {}
}

/// Controlled completion order, not timing-dependent sleeps or public traffic.
private final class CommunitySportsFixtureGate {
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((CommunitySportsFixtureProtocol.Response) -> Void)?
    private var pending: CommunitySportsFixtureProtocol.Response?

    init(_ description: String) { started = XCTestExpectation(description: description) }

    func start(_ completion: @escaping (CommunitySportsFixtureProtocol.Response) -> Void) {
        lock.lock()
        let response = pending
        pending = nil
        if response == nil { self.completion = completion }
        lock.unlock()
        started.fulfill()
        if let response { completion(response) }
    }

    func respond(_ response: CommunitySportsFixtureProtocol.Response) {
        lock.lock()
        let callback = completion
        completion = nil
        if callback == nil { pending = response }
        lock.unlock()
        callback?(response)
    }
}
