import XCTest
@testable import Fotty

final class PenguPlaySportsAddonTests: XCTestCase {
    private typealias Client = PenguPlaySportsAddonClient
    private let kickoff = ISO8601DateFormatter().date(from: "2026-11-12T00:00:00Z")!
    private let manifestURL = URL(string: "https://pengu.uk/%7B%22source_live-sports%22%3A%22checked%22%7D/manifest.json")!

    private func request(home: String = "Buffalo Sabres", away: String = "Tampa Bay Lightning", sport: String = "hockey") -> StreamPlaybackRequest {
        StreamPlaybackRequest(matchID: "sports-fixture:nhl:1", displayTitle: "\(home) vs \(away)",
                              homeTeam: home, awayTeam: away, category: sport, kickoffDate: kickoff)
    }
    private func row(_ name: String, id: String = "pp-live:daddylive~dHY2fDI5NWVh", released: String = "2026-11-12T00:00:00.000Z") -> Client.Row {
        .init(id: id, name: name, released: released, genres: ["🏒 Hockey"])
    }

    func testCatalogNamesBecomeExactPairs() {
        XCTAssertEqual(Client.pairTitle("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning"), "Buffalo Sabres vs Tampa Bay Lightning")
        XCTAssertEqual(Client.pairTitle("📺 New York Rangers vs. Calgary Flames"), "New York Rangers vs Calgary Flames")
        XCTAssertEqual(Client.pairTitle("🔴 LIVE: Inter Bogotá x América de Cali"), "Inter Bogotá vs América de Cali")
        XCTAssertNil(Client.pairTitle("🔴 LIVE: Fox Cricket"), "A channel is never a fixture")
        XCTAssertNil(Client.pairTitle("A - B - C"), "Ambiguous names fail closed")
    }

    func testSelectionNeedsBothTeamsSportAndExactKickoff() throws {
        let live = row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning")
        XCTAssertEqual(try Client.select(request: request(), rows: [live], now: kickoff).id, live.id)
        for wrong in [row("🔴 LIVE: Buffalo Sabres - Boston Bruins", id: "pp-live:x~1"),
                      row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning", id: "pp-live:x~2", released: "2026-11-13T00:00:00.000Z"),
                      row("🔴 LIVE: Fox Cricket", id: "pp-live:x~3"),
                      row("🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning", id: "https://evil.example/x")] {
            XCTAssertThrowsError(try Client.select(request: request(), rows: [wrong], now: kickoff), wrong.name)
        }
        // Two different listings of the same game cannot be told apart.
        XCTAssertThrowsError(try Client.select(request: request(), rows: [live, row(live.name, id: "pp-live:ppv~other")], now: kickoff))
    }

    func testLiveTVManifestAndSignInPlaceholder() throws {
        let manifest = try JSONDecoder().decode(Client.Manifest.self, from: Data("""
        {"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["movie","series","tv"],"idPrefixes":["tt","pp-live:"]},
         {"name":"meta","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],
         "catalogs":[{"type":"tv","id":"pp-live-now"},{"type":"tv","id":"pp-live-hockey"}]}
        """.utf8))
        XCTAssertTrue(Client.hasLiveTV(manifest))
        let off = try JSONDecoder().decode(Client.Manifest.self, from: Data("""
        {"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["movie","series","tv"],"idPrefixes":["tt","pp-live:"]}],"catalogs":[]}
        """.utf8))
        XCTAssertFalse(Client.hasLiveTV(off), "Live TV switched off in the owner's configuration")
        let placeholder = try JSONDecoder().decode(Client.Delivery.self, from: Data("""
        {"name":"PenguPlay","title":"You must sign in","url":"https://pengu.uk/web/index.html"}
        """.utf8))
        XCTAssertTrue(Client.isSignInPlaceholder(placeholder))
    }

    func testDeliveryAndHeaderAdmission() throws {
        XCTAssertTrue(Client.admitsDelivery(URL(string: "https://cdn.example.com/live/index.m3u8?token=x")!))
        for bad in ["http://cdn.example.com/a.m3u8", "https://user:pw@cdn.example.com/a.m3u8",
                    "https://cdn.example.com/a.mp4", "https://127.0.0.1/a.m3u8"] {
            XCTAssertFalse(Client.admitsDelivery(URL(string: bad)!), bad)
        }
        func delivery(_ headers: String) throws -> Client.Delivery {
            try JSONDecoder().decode(Client.Delivery.self, from: Data(#"{"url":"https://cdn.example.com/a.m3u8","behaviorHints":{"proxyHeaders":{"request":\#(headers)}}}"#.utf8))
        }
        XCTAssertEqual(Client.requestHeaders(try delivery(#"{"referer":"https://site.example/","User-Agent":"UA"}"#)),
                       ["Referer": "https://site.example/", "User-Agent": "UA"])
        XCTAssertNil(Client.requestHeaders(try delivery(#"{"Cookie":"secret"}"#)))
        XCTAssertNil(Client.requestHeaders(try delivery(#"{"Referer":"http://site.example/"}"#)))
    }

    func testResolveUsesOnlyTheOwnersLinkAndReturnsGuardedHLS() async throws {
        let root = manifestURL.deletingLastPathComponent().absoluteString
        let manifest = #"{"id":"com.penguplay","version":"1.4.0","resources":[{"name":"stream","types":["tv"],"idPrefixes":["pp-live:"]},{"name":"catalog","types":["tv"]}],"catalogs":[{"type":"tv","id":"pp-live-hockey"}]}"#
        let catalog = #"{"metas":[{"id":"pp-live:daddylive~dHY2fDI5NWVh","type":"tv","name":"🔴 LIVE: Buffalo Sabres - Tampa Bay Lightning","released":"2026-11-12T00:00:00.000Z","genres":["🏒 Hockey"]}]}"#
        let streams = #"{"streams":[{"name":"PenguPlay","url":"https://cdn.example.com/live/index.m3u8","behaviorHints":{"proxyHeaders":{"request":{"Referer":"https://site.example/"}}}},{"name":"PenguPlay","url":"https://cdn.example.com/file.mp4"}]}"#
        let request = self.request()
        let fetched = PenguPlayLockedValue<[String]>([])
        let client = Client(configuration: { self.manifestURL }, fetch: { urlRequest in
            let url = urlRequest.url!.absoluteString
            fetched.mutate { $0.append(url) }
            let body = url == self.manifestURL.absoluteString ? manifest
                : url.hasPrefix(root + "catalog/tv/pp-live-hockey/search=") ? catalog
                : url == root + "stream/tv/" + Client.encodedComponent("pp-live:daddylive~dHY2fDI5NWVh") + ".json" ? streams : "{}"
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        }, enabled: { true }, current: { $0 }, validate: { _ in })
        let sessions = try await client.resolve(for: request, now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["PP1"], "The mp4 delivery is not admitted")
        XCTAssertEqual(sessions.first?.requiredHeaders, ["Referer": "https://site.example/"])
        XCTAssertEqual(sessions.first?.requiresGuardedRelay, true)
        XCTAssertTrue(fetched.value.allSatisfy { $0.hasPrefix(root) }, "Every request stays on the owner's configured link")
    }
}

/// Minimal thread-safe box for test closures.
final class PenguPlayLockedValue<T>: @unchecked Sendable {
    private var stored: T; private let lock = NSLock()
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}
