import XCTest
@testable import Fotty

final class EngineSourceResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_361_600)

    private func request() -> MatchRequest {
        MatchRequest(matchID: "sports-fixture:premier-league:1",
                     homeTeam: "Chelsea", awayTeam: "Arsenal",
                     category: "football", kickoffDate: now)
    }

    private func candidate(_ url: String, provider: String, headers: [String: String] = [:]) -> SourceCandidate {
        SourceCandidate(
            url: URL(string: url)!,
            requiredHeaders: headers,
            qualityLabel: nil,
            providerCode: provider,
            matchReceipt: MatchReceipt(fixtureID: "sports-fixture:premier-league:1",
                                       participants: ["Chelsea", "Arsenal"], start: now)
        )
    }

    private struct MockAdapter: SourceAdapter {
        let code: String
        let supported: Bool
        let throwsError: Bool
        let candidates: [SourceCandidate]

        func supports(_ request: MatchRequest) -> Bool { supported }
        func resolve(_ request: MatchRequest, at now: Date) async throws -> [SourceCandidate] {
            if throwsError { throw URLError(.notConnectedToInternet) }
            return candidates
        }
    }

    func testResolvesAcrossEnabledAdapters() async {
        let a = MockAdapter(code: "a", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/a.m3u8", provider: "a")])
        let b = MockAdapter(code: "b", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/b.m3u8", provider: "b")])
        let resolver = SourceResolver(adapters: [a, b])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertEqual(result.map(\.candidate.url.absoluteString).sorted(),
                       ["https://example.com/a.m3u8", "https://example.com/b.m3u8"])
    }

    func testSkipsUnsupportedAdapters() async {
        let a = MockAdapter(code: "a", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/a.m3u8", provider: "a")])
        let b = MockAdapter(code: "b", supported: false, throwsError: false,
                            candidates: [candidate("https://example.com/b.m3u8", provider: "b")])
        let resolver = SourceResolver(adapters: [a, b])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertEqual(result.map(\.candidate.url.absoluteString), ["https://example.com/a.m3u8"])
    }

    func testIsolatesFailingAdapter() async {
        let a = MockAdapter(code: "a", supported: true, throwsError: true, candidates: [])
        let b = MockAdapter(code: "b", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/b.m3u8", provider: "b")])
        let resolver = SourceResolver(adapters: [a, b])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertEqual(result.map(\.candidate.url.absoluteString), ["https://example.com/b.m3u8"])
    }

    func testDeduplicatesIdenticalDelivery() async {
        let a = MockAdapter(code: "a", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/same.m3u8", provider: "a",
                                                  headers: ["Referer": "https://x/"])])
        let b = MockAdapter(code: "b", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/same.m3u8", provider: "b",
                                                  headers: ["Referer": "https://x/"])])
        let resolver = SourceResolver(adapters: [a, b])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertEqual(result.count, 1, "The same URL+headers through two adapters collapses to one choice")
    }

    func testDistinctHeadersAreNotDeduplicated() async {
        let a = MockAdapter(code: "a", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/same.m3u8", provider: "a",
                                                  headers: ["Referer": "https://a/"])])
        let b = MockAdapter(code: "b", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/same.m3u8", provider: "b",
                                                  headers: ["Referer": "https://b/"])])
        let resolver = SourceResolver(adapters: [a, b])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertEqual(result.count, 2, "Different required headers are distinct deliveries")
    }

    func testReturnsEmptyWhenNoAdapterSupports() async {
        let a = MockAdapter(code: "a", supported: false, throwsError: false,
                            candidates: [candidate("https://example.com/a.m3u8", provider: "a")])
        let resolver = SourceResolver(adapters: [a])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertTrue(result.isEmpty)
    }

    func testRankingIsStableAndOrdered() async {
        let a = MockAdapter(code: "a", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/a.m3u8", provider: "a")])
        let b = MockAdapter(code: "b", supported: true, throwsError: false,
                            candidates: [candidate("https://example.com/b.m3u8", provider: "b")])
        let resolver = SourceResolver(adapters: [a, b])
        let result = await resolver.resolve(request(), at: now)
        XCTAssertEqual(result.map(\.score), [0, 1])
        XCTAssertEqual(result.map(\.candidate.providerCode), ["a", "b"])
    }
}
