import XCTest
@testable import Fotty

/// All requests terminate in the injected protocol, including production-host
/// URLs. These units exercise metadata admission without requesting media.
@MainActor
final class ExplicitRetryAdapterFreshnessTests: XCTestCase {
    func testExplicitRetryBypassesMissingMetadataCachesAcrossAllThreeAdapters() async throws {
        for adapter in Adapter.allCases {
            let fixture = Fixture(adapter), session = try fixture.session(missing: true)
            defer { session.invalidateAndCancel(); RetryFreshnessProtocol.reset() }
            let resolve = adapter.resolver(session)
            await expectMissing { try await resolve(fixture.request, fixture.now, false) }
            let initialReads = RetryFreshnessProtocol.requests.count
            try RetryFreshnessProtocol.replace(fixture.responses())
            await expectMissing { try await resolve(fixture.request, fixture.now.addingTimeInterval(1), false) }
            XCTAssertEqual(RetryFreshnessProtocol.requests.count, initialReads, adapter.rawValue)
            let choices = try await resolve(fixture.request, fixture.now.addingTimeInterval(2), true)
            XCTAssertEqual(choices.map(\.playableURL.absoluteString), [fixture.delivery], adapter.rawValue)
            XCTAssertEqual(choices.first?.matchID, fixture.request.matchID)
            XCTAssertEqual(choices.first?.requiredHeaders, adapter == .cnc ? CNCSportsAddonClient.reviewedHeaders : [:])
            for key in fixture.cachedMetadataKeys {
                XCTAssertEqual(RetryFreshnessProtocol.requests.filter { RetryFreshnessProtocol.key($0.url!) == key }.count,
                    2, "Explicit Retry must reread \(adapter.rawValue) \(key)")
            }
            XCTAssertEqual(RetryFreshnessProtocol.requests.filter { $0.url?.path.hasPrefix("/stream/") == true }.count, 1)
        }
    }

    func testExplicitRetryCannotReuseCachedIdentityAfterPublishedFixtureChanges() async throws {
        for adapter in Adapter.allCases {
            let fixture = Fixture(adapter), session = try fixture.session()
            defer { session.invalidateAndCancel(); RetryFreshnessProtocol.reset() }
            let resolve = adapter.resolver(session)
            let initial = try await resolve(fixture.request, fixture.now, false)
            XCTAssertEqual(initial.count, 1)
            try RetryFreshnessProtocol.replace(fixture.responses(changedIdentity: true))
            let ordinary = try await resolve(fixture.request, fixture.now.addingTimeInterval(1), false)
            XCTAssertEqual(ordinary.count, 1,
                "Ordinary resolution retains its existing catalog TTL")
            let streamReads = RetryFreshnessProtocol.requests.filter { $0.url?.path.hasPrefix("/stream/") == true }.count
            do {
                _ = try await resolve(fixture.request, fixture.now.addingTimeInterval(2), true)
                XCTFail("Fresh conflicting/nonmatching identity cannot inherit the cached delivery: \(adapter.rawValue)")
            } catch {
                let rejection = error as? CommunitySportsAddonError
                XCTAssertTrue(rejection == .matchNotFound || rejection == .conflictingMatch, "Unexpected rejection: \(error)")
            }
            XCTAssertEqual(RetryFreshnessProtocol.requests.filter { $0.url?.path.hasPrefix("/stream/") == true }.count,
                streamReads, adapter.rawValue)
            for key in fixture.cachedMetadataKeys {
                XCTAssertEqual(RetryFreshnessProtocol.requests.filter { RetryFreshnessProtocol.key($0.url!) == key }.count, 2)
            }
        }
    }

    func testCancelledExplicitRefreshCannotContinueToCatalogOrDescriptor() async throws {
        for adapter in Adapter.allCases {
            let fixture = Fixture(adapter), session = try fixture.session(missing: true)
            defer { session.invalidateAndCancel(); RetryFreshnessProtocol.reset() }
            let resolve = adapter.resolver(session)
            await expectMissing { try await resolve(fixture.request, fixture.now, false) }
            try RetryFreshnessProtocol.replace(fixture.responses())
            let before = RetryFreshnessProtocol.requests.count
            let started = RetryFreshnessProtocol.hold(fixture.manifestKey)
            let operation = Task { try await resolve(fixture.request, fixture.now.addingTimeInterval(1), true) }
            defer { operation.cancel(); RetryFreshnessProtocol.release() }
            await fulfillment(of: [started], timeout: 2)
            operation.cancel(); RetryFreshnessProtocol.release()
            do { _ = try await operation.value; XCTFail("Cancelled refresh cannot publish") }
            catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
            XCTAssertEqual(RetryFreshnessProtocol.requests.count, before + 1, adapter.rawValue)
            XCTAssertFalse(RetryFreshnessProtocol.requests.contains { $0.url?.path.hasPrefix("/stream/") == true })
        }
    }

    private func expectMissing(_ operation: () async throws -> [StreamSession]) async {
        do { _ = try await operation(); XCTFail("The cached catalog contains no matching fixture") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
    }

    private enum Adapter: String, CaseIterable {
        case flix, cnc, streamVix
        func resolver(_ session: URLSession) -> (StreamPlaybackRequest, Date, Bool) async throws -> [StreamSession] {
            switch self {
            case .flix:
                let client = FlixStreamsAddonClient(session: session)
                return { try await client.resolve(for: $0, now: $1, forceRefresh: $2) }
            case .cnc:
                let client = CNCSportsAddonClient(session: session)
                return { try await client.resolve(for: $0, now: $1, forceRefresh: $2) }
            case .streamVix:
                let client = StreamVixSportsAddonClient(session: session)
                return { try await client.resolve(for: $0, now: $1, forceRefresh: $2) }
            }
        }
    }

    /// Minimal copies of each existing adapter's reviewed offline fixture
    /// schema; the transport is shared, while the real decoders remain distinct.
    private struct Fixture {
        let adapter: Adapter
        init(_ adapter: Adapter) { self.adapter = adapter }
        let now = ISO8601DateFormatter().date(from: "2026-10-24T15:00:00Z")!
        var host: String {
            switch adapter { case .flix: "free.flixnest.app"; case .cnc: "cncverse.dpdns.org"; case .streamVix: "streamvix.hayd.uk" }
        }
        var fixtureID: String {
            switch adapter {
            case .flix: "dlstreams:event:aaaaaaaaaaaa"
            case .cnc: "cnc:" + String(repeating: "A", count: 1218) + "=="
            case .streamVix: "tv:16-30-chelsea-vs-tottenham-hotspur-premier-league-24-10-20261024"
            }
        }
        var delivery: String {
            switch adapter {
            case .flix: "https://free.flixnest.app/dlstreams/stream/dlstreams%3Achannel%3A870.m3u8?t=fresh-fixture-signature"
            case .cnc: "https://edgestream7.pro/hls/offline_fixture.m3u8"
            case .streamVix: "https://p7.streamhostingcdn.top/stream/870/index.m3u8?token=fresh-fixture-signature&exp=1792864800"
            }
        }
        var request: StreamPlaybackRequest {
            let pair: (String, String, String, String)
            switch adapter {
            case .flix: pair = ("Arsenal", "Everton", "football", "14:00")
            case .cnc: pair = ("Chicago Blackhawks", "Montreal Canadiens", "hockey", "00:00")
            case .streamVix: pair = ("Chelsea", "Tottenham Hotspur", "football", "16:30")
            }
            return .init(matchID: "retry-freshness-fixture", displayTitle: "\(pair.0) vs \(pair.1)", homeTeam: pair.0,
                awayTeam: pair.1, category: pair.2, kickoffDate: ISO8601DateFormatter().date(from: "2026-10-24T\(pair.3):00Z")!)
        }
        var manifestKey: String { host + "|/manifest.json" }
        var catalogPaths: [String] {
            switch adapter {
            case .flix: [0, 40, 80].map { "/catalog/tv/essential-live-events/genre=soccer" + ($0 == 0 ? "" : "&skip=\($0)") + ".json" }
            case .cnc: ["/catalog/tv/cnc_LivXowLiveEvents_tv.json"]
            case .streamVix: ["/catalog/tv/streamvix_eventi/genre=Premier League.json"]
            }
        }
        var originalKey: String { "raw.githubusercontent.com|/qwertyuiop8899/logo/main/daddyliveSchedule.json" }
        var cachedMetadataKeys: [String] {
            [manifestKey] + (adapter == .streamVix ? [originalKey] : []) + catalogPaths.map { host + "|" + $0 }
        }
        func session(missing: Bool = false) throws -> URLSession {
            RetryFreshnessProtocol.reset()
            try RetryFreshnessProtocol.replace(responses(missing: missing))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RetryFreshnessProtocol.self]
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }
        func responses(missing: Bool = false, changedIdentity: Bool = false) -> [String: [String: Any]] {
            var result: [String: [String: Any]] = [:]
            let manifest: [String: Any], row: [String: Any], stream: [String: Any]
            switch adapter {
            case .flix:
                manifest = ["id": "org.flixstreams.free", "version": "1.0.0", "types": ["tv"], "resources": ["stream", "catalog", "meta"],
                    "catalogs": [["id": "essential-live-events", "type": "tv", "extra": [
                        ["name": "genre", "isRequired": false, "options": ["soccer", "cricket"]],
                        ["name": "search", "isRequired": false], ["name": "skip", "isRequired": false]]]],
                    "behaviorHints": ["configurationRequired": false]]
                row = ["id": fixtureID, "type": "tv", "name": "⚽ England - Premier League : " + (changedIdentity ? "Other vs Another" : "Arsenal vs Everton"),
                    "description": "Category: All Soccer Events ⚽\nDate: 2026-10-24 (UTC)\nTime: 14:00\nChannels: Example Sports",
                    "genres": ["Live TV", "Sports", "All Soccer Events ⚽"], "behaviorHints": ["defaultVideoId": fixtureID],
                    "videos": [["id": fixtureID, "title": "Live Stream", "released": "2026-10-24T14:00:00.000Z", "season": 1, "episode": 1]]]
                stream = ["url": delivery]
            case .cnc:
                manifest = ["id": "com.cncverse.stremiobridge", "version": "1.0.30", "resources": ["catalog", "meta", "stream", "subtitles"],
                    "types": ["movie", "series", "other", "tv"], "catalogs": [["id": "cnc_LivXowLiveEvents_tv", "type": "tv"]],
                    "behaviorHints": ["configurable": false]]
                row = ["id": fixtureID, "type": "tv", "name": changedIdentity ? "Other vs Another" : "🔴 Blackhawks vs Canadiens",
                    "behaviorHints": ["defaultVideoId": fixtureID]]
                result[host + "|/meta/tv/" + fixtureID + ".json"] = ["meta": ["id": fixtureID, "type": "tv", "name": "Blackhawks vs Canadiens",
                    "description": "📌 Hockey\n🏆 NHL\n🕐 Oct 24, 2026 00:00 UTC\n\n📡 Available Servers: 1"]]
                stream = ["url": delivery, "name": "🎬LivXowProvider 😮‍💨 Auto • CNCVerse Bridge", "title": "Offline fixture • HLS",
                    "behaviorHints": ["proxyHeaders": ["request": CNCSportsAddonClient.reviewedHeaders]]]
            case .streamVix:
                manifest = ["id": "org.prisonmike.streamvix", "version": "1.0.0", "types": ["tv"], "resources": ["catalog", "meta", "stream"],
                    "catalogs": [["id": "streamvix_eventi", "type": "tv", "extra": [["name": "genre", "isRequired": true,
                        "options": ["Premier League", "Coppe"]]]]], "behaviorHints": ["configurationRequired": false]]
                let pair = changedIdentity ? "Other vs Another" : "Chelsea vs Tottenham Hotspur"
                row = ["id": fixtureID, "type": "tv", "name": "\(pair) ⏰ 16:30 - 24/10",
                    "description": "🔴 Inizio: 16:30 - \(pair) - Premier League - 24/10", "eventStart": "2026-10-24T14:30:00Z",
                    "category": "premierleague", "_dynamic": true, "_originalName": "⏰ 16:30 : \(pair) - Premier League 24/10"]
                var meta = row; meta.removeValue(forKey: "_originalName")
                meta["name"] = "Chelsea vs Tottenham Hotspur ⏰ 16:30 - 24/10"
                meta["description"] = "🔴 Inizio: 16:30 - Chelsea vs Tottenham Hotspur - Premier League - 24/10"
                result[host + "|/meta/tv/" + fixtureID + ".json"] = ["meta": meta]
                result[originalKey] = ["Saturday 24th October 2026 - Schedule Time UK GMT": ["All Soccer Events ⚽": [
                    ["event": "⚽ England - Premier League : Chelsea vs Tottenham Hotspur", "time": "16:30", "channels": []]]]]
                stream = ["name": "StreamViX", "title": "HD", "url": delivery]
            }
            result[manifestKey] = manifest
            for (index, path) in catalogPaths.enumerated() { result[host + "|" + path] = ["metas": missing || index > 0 ? [] : [row]] }
            result[host + "|/stream/tv/" + fixtureID + ".json"] = ["streams": [stream]]
            return result
        }
    }
}

private final class RetryFreshnessProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var bodies: [String: Data] = [:]
    private static var recorded: [URLRequest] = []
    private static var heldKey: String?
    private static var started: XCTestExpectation?
    private static var heldCompletion: (() -> Void)?
    private let stateLock = NSLock()
    private var stopped = false
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    static func key(_ url: URL) -> String { (url.host ?? "") + "|" + url.path }
    static func replace(_ documents: [String: [String: Any]]) throws {
        let encoded = try documents.mapValues { try JSONSerialization.data(withJSONObject: $0) }
        lock.lock(); bodies = encoded; lock.unlock()
    }
    static func reset() {
        release()
        lock.lock(); bodies = [:]; recorded = []; heldKey = nil; started = nil; lock.unlock()
    }
    static func hold(_ key: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Explicit refresh reached uncached manifest")
        lock.lock(); heldKey = key; started = expectation; lock.unlock()
        return expectation
    }
    static func release() {
        lock.lock(); let completion = heldCompletion; heldCompletion = nil; heldKey = nil; lock.unlock()
        completion?()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = Self.key(request.url!)
        Self.lock.lock()
        Self.recorded.append(request)
        let data = Self.bodies[key]
        let held = Self.heldKey == key
        let started = held ? Self.started : nil
        if held { Self.heldCompletion = { [weak self] in self?.complete(data) } }
        Self.lock.unlock()
        if held { started?.fulfill() } else { complete(data) }
    }
    private func complete(_ data: Data?) {
        stateLock.lock(); let active = !stopped; stateLock.unlock()
        guard active else { return }
        guard let data else { client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}
