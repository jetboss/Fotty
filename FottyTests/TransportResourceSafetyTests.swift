import XCTest
@testable import Fotty

/// No provider endpoint or media download is used. The real URLSession delegate
/// sees bounded, unfinished and redirected responses through a local protocol.
@MainActor
final class TransportResourceSafetyTests: XCTestCase {
    private let url = URL(string: "https://transport.invalid/probe")!

    override func tearDown() {
        ResourceSafetyProtocol.reset()
        super.tearDown()
    }

    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResourceSafetyProtocol.self]
        config.waitsForConnectivity = false
        return config
    }

    func testPrefixCompletesAndCancelsServerIgnoringRangeWithoutWaitingForEOF() async throws {
        let stopped = expectation(description: "Unfinished resource cancelled after prefix")
        ResourceSafetyProtocol.configure(.unfinished(Data(repeating: 9, count: 4096)), onStop: { stopped.fulfill() })
        let client = FottyBoundedHTTPClient(configuration: configuration())
        let result = try await client.fetch(URLRequest(url: url), maximumBytes: 1024, mode: .prefix, deadline: 1)
        XCTAssertEqual(result.data.count, 1024)
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testCompleteBodyRejectsKnownOversizeAndUnknownLengthOverflow() async {
        for length in ["10", nil] {
            ResourceSafetyProtocol.configure(.body(Data(repeating: 1, count: 10), length: length))
            let client = FottyBoundedHTTPClient(configuration: configuration())
            do {
                _ = try await client.fetch(URLRequest(url: url), maximumBytes: 3, deadline: 1)
                XCTFail("A size header is not the only body limit")
            } catch {
                XCTAssertEqual(error as? FottyBoundedHTTPClient.Failure, .responseTooLarge)
            }
        }
    }

    func testExactBodyLimitSucceeds() async throws {
        ResourceSafetyProtocol.configure(.body(Data([1, 2, 3]), length: "3"))
        let result = try await FottyBoundedHTTPClient(configuration: configuration())
            .fetch(URLRequest(url: url), maximumBytes: 3, deadline: 1)
        XCTAssertEqual(result.data, Data([1, 2, 3]))
    }

    func testHardDeadlineEndsDribblingBodyDespiteContinuedNetworkActivity() async {
        let stopped = expectation(description: "Dribbling response cancelled")
        ResourceSafetyProtocol.configure(.dribble, onStop: { stopped.fulfill() })
        let started = ContinuousClock.now
        do {
            _ = try await FottyBoundedHTTPClient(configuration: configuration())
                .fetch(URLRequest(url: url), maximumBytes: 4096, deadline: 0.15)
            XCTFail("Periodic bytes must not renew the absolute deadline")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testParentCancellationEndsRequestWaitingForHeaders() async {
        let began = expectation(description: "Request began")
        let stopped = expectation(description: "Pending request cancelled")
        ResourceSafetyProtocol.configure(.wait, onStart: { began.fulfill() }, onStop: { stopped.fulfill() })
        let client = FottyBoundedHTTPClient(configuration: configuration())
        let work = Task { try await client.fetch(URLRequest(url: url), maximumBytes: 1024, deadline: 10) }
        await fulfillment(of: [began], timeout: 1)
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled request cannot publish a response") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testCSRedirectPolicyRejectsUnreviewedOriginsAndCredentials() {
        let manifest = URL(string: "https://addon.invalid/manifest.json")!
        let source = URL(string: "https://addon.invalid/catalog/tv/live.json")!
        for target in ["https://other.invalid/catalog.json", "http://addon.invalid/catalog.json",
                       "https://addon.invalid:8443/catalog.json", "https://user:secret@addon.invalid/catalog.json"] {
            XCTAssertFalse(CommunitySportsAddonClient.allowsRedirect(from: source,
                to: URL(string: target)!, anchoredTo: manifest))
        }
        XCTAssertTrue(CommunitySportsAddonClient.allowsRedirect(from: source,
            to: URL(string: "https://addon.invalid:443/redirected.json")!, anchoredTo: manifest))
        XCTAssertFalse(CommunitySportsAddonClient.allowsRedirect(from: URL(string: "https://other.invalid/start")!,
            to: manifest, anchoredTo: manifest))
    }

    func testCSRedirectIsRejectedBeforeDestinationRequestAndDoesNotStartLiveFallback() async {
        let manifest = URL(string: "https://addon.invalid/manifest.json")!
        ResourceSafetyProtocol.configure(.redirect(URL(string: "https://unreviewed.invalid/redirected.json")!))
        let session = URLSession(configuration: configuration())
        defer { session.invalidateAndCancel() }
        let client = CommunitySportsAddonClient(manifestURL: manifest, session: session)
        let request = StreamPlaybackRequest(matchID: "fixture", displayTitle: "Chelsea vs Brighton",
            homeTeam: "Chelsea", awayTeam: "Brighton", category: "football", kickoffDate: Date())
        do { _ = try await client.resolve(for: request); XCTFail("Off-origin redirect must fail closed") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .unsafeMetadata(stage: .manifest, reason: .redirect)) }
        XCTAssertEqual(ResourceSafetyProtocol.requestedURLs, [manifest])
    }

    func testCSOversizeManifestStopsBeforeDecoding() async {
        ResourceSafetyProtocol.configure(.unfinished(Data(repeating: 32, count: 129 * 1024)))
        let session = URLSession(configuration: configuration())
        defer { session.invalidateAndCancel() }
        let client = CommunitySportsAddonClient(manifestURL: URL(string: "https://addon.invalid/manifest.json")!, session: session)
        let request = StreamPlaybackRequest(matchID: "fixture", displayTitle: "Chelsea vs Brighton",
            homeTeam: "Chelsea", awayTeam: "Brighton", category: "football", kickoffDate: Date())
        do { _ = try await client.resolve(for: request); XCTFail("Oversized unfinished JSON must not wait for EOF") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
        XCTAssertEqual(ResourceSafetyProtocol.requestedURLs.count, 1)
    }

    func testNativeValidationPreservesHeadersButBoundsCapturedFullRange() async {
        ResourceSafetyProtocol.configure(.unfinished(Data("#EXTM3U\n".utf8) + Data(repeating: 32, count: 2048)))
        let validator = StreamContractValidator(configuration: configuration(), deadline: 1)
        let result = await validator.validate(URL(string: "https://transport.invalid/live.m3u8")!,
            headers: ["Referer": "https://page.invalid/player", "X-Required": "fixture", "Range": "bytes=0-"])
        guard result.isValid else { return XCTFail("Ignored Range still permits prefix validation") }
        let sent = ResourceSafetyProtocol.lastRequest
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Range"), "bytes=0-1023")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Referer"), "https://page.invalid/player")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "X-Required"), "fixture")
    }

    func testNativeValidationRejectsEmptyRecognizedMediaType() async {
        ResourceSafetyProtocol.configure(.body(Data(), length: "0"))
        let result = await StreamContractValidator(configuration: configuration(), deadline: 1)
            .validate(URL(string: "https://transport.invalid/live.m3u8")!, headers: [:])
        guard case .invalid(let reason, let diagnostic) = result else { return XCTFail("Empty media is not a valid stream") }
        XCTAssertEqual(reason, "Empty media response")
        XCTAssertEqual(diagnostic?.qualityDetails, ["preparation_stage": "contract_validation", "preparation_reason": "empty_media"])
    }

    func testNativeHTTPValidationReceiptPreservesStatusAndExistingReason() async {
        ResourceSafetyProtocol.configure(.status(503))
        let result = await StreamContractValidator(configuration: configuration(), deadline: 1)
            .validate(URL(string: "https://transport.invalid/live.m3u8")!, headers: [:])
        guard case .invalid(let reason, let diagnostic) = result else { return XCTFail("HTTP503 must remain invalid") }
        XCTAssertEqual(reason, "HTTP 503")
        XCTAssertEqual(diagnostic?.qualityDetails, ["preparation_stage": "contract_validation",
            "preparation_reason": "http_status", "preparation_http_status": "503"])
    }

    func testNativeValidationTransportErrorRetainsOnlyBoundedIdentifiers() async throws {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.cannotFindHost.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "private https://owner.invalid/live?secret=one",
                NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -50)])
        ResourceSafetyProtocol.configure(.failure(error))
        let result = await StreamContractValidator(configuration: configuration(), deadline: 1)
            .validate(URL(string: "https://transport.invalid/live.m3u8")!, headers: [:])
        guard case .invalid(_, let diagnostic) = result else { return XCTFail("Transport failure must remain invalid") }
        let details = try XCTUnwrap(diagnostic?.qualityDetails)
        XCTAssertEqual(details["preparation_stage"], "contract_validation")
        XCTAssertEqual(details["preparation_reason"], "transport_error")
        XCTAssertEqual(details["preparation_error_domain"], "url")
        XCTAssertEqual(details["preparation_error_code"], String(URLError.cannotFindHost.rawValue))
        XCTAssertEqual(details["preparation_underlying_domain"], "osstatus")
        XCTAssertEqual(details["preparation_underlying_code"], "-50")
        XCTAssertNil(details["native_failure_trigger"], "No AVPlayerItem exists at this boundary")
        XCTAssertNil(details["preparation_http_status"])
        XCTAssertFalse(details.description.contains("owner.invalid"))
        XCTAssertFalse(details.description.contains("private"))
    }

    func testNativeValidationDeadlineReportsTransportTimeoutWithoutRenewingBudget() async throws {
        ResourceSafetyProtocol.configure(.wait)
        let began = ContinuousClock.now
        let result = await StreamContractValidator(configuration: configuration(), deadline: 0.05)
            .validate(URL(string: "https://transport.invalid/live.m3u8")!, headers: [:])
        guard case .invalid(_, let diagnostic) = result else { return XCTFail("Deadline must remain invalid") }
        XCTAssertLessThan(began.duration(to: .now), .seconds(1))
        let details = try XCTUnwrap(diagnostic?.qualityDetails)
        XCTAssertEqual(details["preparation_error_domain"], "url")
        XCTAssertEqual(details["preparation_error_code"], String(URLError.timedOut.rawValue))
        XCTAssertEqual(details["preparation_reason"], "transport_error")
        XCTAssertNil(details["preparation_http_status"])
    }

    func testNativeValidationContentFailuresKeepReasonsButNeverPersistMIMEText() async {
        let cases: [(Data, String, String, String)] = [
            (Data("not-a-playlist".utf8), "application/vnd.apple.mpegurl", "Malformed M3U8 (No #EXTM3U found)", "malformed_manifest"),
            (Data("<html>private</html>".utf8), "text/html", "Received HTML instead of Video", "html_response"),
            (Data("private".utf8), "text/x-private-owner", "Unsupported Content-Type: text/x-private-owner", "unsupported_content_type")
        ]
        for (body, mime, expectedReason, receiptReason) in cases {
            ResourceSafetyProtocol.configure(.typedBody(body, contentType: mime))
            let result = await StreamContractValidator(configuration: configuration(), deadline: 1)
                .validate(URL(string: "https://transport.invalid/probe")!, headers: [:])
            guard case .invalid(let reason, let diagnostic) = result else { return XCTFail("Content must remain invalid") }
            XCTAssertEqual(reason, expectedReason)
            XCTAssertEqual(diagnostic?.qualityDetails, ["preparation_stage": "contract_validation",
                                                        "preparation_reason": receiptReason])
        }
    }

    func testCancelledNativeValidationRetainsCancellationWithoutSyntheticError() async {
        let began = expectation(description: "Validation began")
        ResourceSafetyProtocol.configure(.wait, onStart: { began.fulfill() })
        let work = Task {
            await StreamContractValidator(configuration: configuration(), deadline: 1)
                .validate(URL(string: "https://transport.invalid/live.m3u8")!, headers: [:])
        }
        await fulfillment(of: [began], timeout: 1)
        work.cancel()
        let result = await work.value
        guard case .invalid(let reason, let diagnostic) = result else { return XCTFail("Cancellation must remain invalid") }
        XCTAssertEqual(reason, "Validation cancelled")
        XCTAssertEqual(diagnostic?.qualityDetails, ["preparation_stage": "contract_validation", "preparation_reason": "cancelled"])
    }

    func testNativePrefixCutInsideUTF8DoesNotRejectValidM3U8Header() async {
        var bytes = Data("#EXTM3U\n".utf8)
        bytes.append(Data(repeating: 32, count: 1015))
        bytes.append(contentsOf: [0xC3, 0xA9, 32])
        ResourceSafetyProtocol.configure(.unfinished(bytes))
        let result = await StreamContractValidator(configuration: configuration(), deadline: 1)
            .validate(URL(string: "https://transport.invalid/live.m3u8")!, headers: [:])
        guard result.isValid else { return XCTFail("Only the ASCII HLS header needs prefix validation") }
    }

}

private final class ResourceSafetyProtocol: URLProtocol, @unchecked Sendable {
    enum Mode {
        case body(Data, length: String?), typedBody(Data, contentType: String), unfinished(Data), dribble, wait
        case redirect(URL), status(Int), failure(NSError)
    }
    private static let lock = NSLock()
    private static var mode: Mode = .wait
    private static var requests: [URLRequest] = []
    private static var onStart: (() -> Void)?
    private static var onStop: (() -> Void)?
    private let stateLock = NSLock()
    private var stopped = false
    private var didNotifyStop = false
    private var stopCallback: (() -> Void)?
    static var requestedURLs: [URL] { lock.lock(); defer { lock.unlock() }; return requests.compactMap(\.url) }
    static var lastRequest: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }
    static func configure(_ mode: Mode, onStart: (() -> Void)? = nil, onStop: (() -> Void)? = nil) {
        lock.lock(); self.mode = mode; requests = []; self.onStart = onStart; self.onStop = onStop; lock.unlock()
    }
    static func reset() { configure(.wait) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let mode = Self.mode, start = Self.onStart, stop = Self.onStop
        Self.lock.unlock()
        stateLock.lock(); stopCallback = stop; stateLock.unlock()
        start?()
        var headers = ["Content-Type": "application/vnd.apple.mpegurl"]
        if case .body(_, let length) = mode { headers["Content-Length"] = length }
        if case .typedBody(_, let type) = mode { headers["Content-Type"] = type }
        switch mode {
        case .wait: return
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .redirect(let target):
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        case .status(let code):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("[]".utf8))
            client?.urlProtocolDidFinishLoading(self)
        default:
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            switch mode {
            case .body(let data, _): client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
            case .typedBody(let data, _): client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
            case .unfinished(let data): client?.urlProtocol(self, didLoad: data)
            case .dribble: dribble()
            default: break
            }
        }
    }
    private func dribble() {
        stateLock.lock(); let active = !stopped; stateLock.unlock()
        guard active else { return }
        client?.urlProtocol(self, didLoad: Data([1]))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.025) { [weak self] in self?.dribble() }
    }
    override func stopLoading() {
        stateLock.lock()
        stopped = true
        let notify = !didNotifyStop
        didNotifyStop = true
        let callback = stopCallback
        stateLock.unlock()
        if notify { callback?() }
    }
}
