import XCTest
import UIKit

@testable import Fotty

/// These are request-lifecycle tests, not source-string or live-network checks.
/// Each pipeline owns an isolated memory cache and a held local byte transport;
/// the production decoder still runs through its off-main, two-permit scheduler.
@MainActor
final class ImagePipelineOwnershipTests: XCTestCase {
    private let url = URL(string: "https://badges.invalid/shared-crest.png")!

    private func artwork(width: Int = 16, color: UIColor = .systemBlue) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: CGFloat(width), height: 12)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func pipeline(_ transport: HeldBadgeTransport, cache: FottyImageCache = FottyImageCache()) -> FottyImagePipeline {
        FottyImagePipeline(cache: cache, download: { request in
            try await transport.data(for: request)
        })
    }

    /// A bounded watchdog for establishing a real actor-state barrier. We never
    /// sleep for an estimated download/decode duration or depend on queue order.
    private func waitUntil(_ description: String, condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            guard clock.now < deadline else { throw BarrierTimeout(description: description) }
            await Task.yield()
        }
    }

    private func assertOwnership(_ pipeline: FottyImagePipeline, loads: Int, waiters: Int,
                                 for url: URL? = nil, file: StaticString = #filePath, line: UInt = #line) async {
        let activeLoads = await pipeline.activeLoadCount
        let activeWaiters = await pipeline.activeWaiterCount(for: url ?? self.url)
        XCTAssertEqual(activeLoads, loads, file: file, line: line)
        XCTAssertEqual(activeWaiters, waiters, file: file, line: line)
    }

    func testTwoConsumersShareOneDownloadAndDecodedImage() async throws {
        let transport = HeldBadgeTransport()
        let cache = FottyImageCache()
        let pipeline = pipeline(transport, cache: cache)
        let first = Task { await pipeline.image(for: url) }
        let second = Task { await pipeline.image(for: url) }
        defer {
            first.cancel(); second.cancel()
            Task { await transport.cancelAllPending() }
        }
        try await waitUntil("Both visible consumers joined one load") {
            let started = await transport.startedRequestCount
            let waiters = await pipeline.activeWaiterCount(for: self.url)
            return started == 1 && waiters == 2
        }
        await assertOwnership(pipeline, loads: 1, waiters: 2)
        let request = await transport.request(at: 0)
        XCTAssertEqual(request?.url, url)
        XCTAssertEqual(request?.timeoutInterval, 8)
        let completed = await transport.complete(0, with: .success(try artwork()))
        XCTAssertTrue(completed)
        let firstResult = await first.value
        let secondResult = await second.value
        let firstImage = try XCTUnwrap(firstResult)
        let secondImage = try XCTUnwrap(secondResult)
        XCTAssertTrue(firstImage === secondImage, "Shared consumers must receive the same single decoded result")
        XCTAssertTrue(cache.image(for: url) === firstImage)
        await assertOwnership(pipeline, loads: 0, waiters: 0)
        let starts = await transport.startedRequestCount
        XCTAssertEqual(starts, 1)
    }

    func testCancellingOneConsumerKeepsTheOtherTransportAndDelivery() async throws {
        let transport = HeldBadgeTransport()
        let cache = FottyImageCache()
        let pipeline = pipeline(transport, cache: cache)
        let disappearing = Task { await pipeline.image(for: url) }
        let visible = Task { await pipeline.image(for: url) }
        defer {
            disappearing.cancel(); visible.cancel()
            Task { await transport.cancelAllPending() }
        }
        try await waitUntil("Both consumers are attached before cancellation") {
            await pipeline.activeWaiterCount(for: self.url) == 2
        }
        disappearing.cancel()
        try await waitUntil("Only the still-visible consumer owns the load") {
            await pipeline.activeWaiterCount(for: self.url) == 1
        }
        let cancelled = await transport.cancelledRequestIDs
        XCTAssertTrue(cancelled.isEmpty, "One disappearing row must not cancel another row's download")
        await assertOwnership(pipeline, loads: 1, waiters: 1)
        try await waitUntil("Transport has reached its controlled byte barrier") {
            await transport.startedRequestCount == 1
        }
        let completed = await transport.complete(0, with: .success(try artwork()))
        XCTAssertTrue(completed)
        let cancelledResult = await disappearing.value
        let visibleResult = await visible.value
        XCTAssertNil(cancelledResult, "The cancelled consumer must not publish artwork")
        let image = try XCTUnwrap(visibleResult)
        XCTAssertTrue(cache.image(for: url) === image)
        await assertOwnership(pipeline, loads: 0, waiters: 0)
    }

    func testLastConsumerCancellationStopsSharedTransportWithoutCaching() async throws {
        let transport = HeldBadgeTransport()
        let cache = FottyImageCache()
        let pipeline = pipeline(transport, cache: cache)
        let first = Task { await pipeline.image(for: url) }
        let second = Task { await pipeline.image(for: url) }
        defer {
            first.cancel(); second.cancel()
            Task { await transport.cancelAllPending() }
        }
        try await waitUntil("Two consumers own the started transport") {
            let starts = await transport.startedRequestCount
            let waiters = await pipeline.activeWaiterCount(for: self.url)
            return starts == 1 && waiters == 2
        }
        first.cancel()
        try await waitUntil("First cancellation is processed") {
            await pipeline.activeWaiterCount(for: self.url) == 1
        }
        let cancellationsBeforeLast = await transport.cancelledRequestIDs
        XCTAssertTrue(cancellationsBeforeLast.isEmpty)
        second.cancel()
        try await waitUntil("Last cancellation reached the actual injected transport") {
            await transport.cancelledRequestIDs == [0]
        }
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertNil(cache.image(for: url))
        await assertOwnership(pipeline, loads: 0, waiters: 0)
        let pending = await transport.pendingRequestCount
        XCTAssertEqual(pending, 0, "Cancellation resumes the held transport; it does not leak a continuation")
    }

    func testImmediateCompletionAndWarmCacheHitsReleaseAllOwnership() async throws {
        let data = try artwork()
        let recorder = ImmediateBadgeTransport(data: data)
        let cache = FottyImageCache()
        let pipeline = FottyImagePipeline(cache: cache, download: { request in
            await recorder.data(for: request)
        })
        let result = await pipeline.image(for: url)
        let first = try XCTUnwrap(result)
        await assertOwnership(pipeline, loads: 0, waiters: 0)
        for _ in 0..<20 {
            let warm = await pipeline.image(for: url)
            XCTAssertTrue(warm === first)
            await assertOwnership(pipeline, loads: 0, waiters: 0)
        }
        let starts = await recorder.startedRequestCount
        XCTAssertEqual(starts, 1, "Neither immediate task completion nor warm cache delivery may retain or restart a load")
    }

    func testLateCancelledCompletionCannotTouchFreshSameURLLoad() async throws {
        // A provider can finish despite cancellation. Keep that old operation
        // alive so the stale-result boundary is tested rather than assumed.
        let transport = HeldBadgeTransport(ignoresCancellation: true)
        let cache = FottyImageCache()
        let pipeline = pipeline(transport, cache: cache)
        let old = Task { await pipeline.image(for: url) }
        defer {
            old.cancel()
            Task { await transport.cancelAllPending() }
        }
        try await waitUntil("Old request is held before cancellation") {
            await transport.startedRequestCount == 1
        }
        old.cancel()
        try await waitUntil("Old waiter ownership is gone, transport has observed cancellation") {
            let waiters = await pipeline.activeWaiterCount(for: self.url)
            let cancelled = await transport.cancelledRequestIDs
            return waiters == 0 && cancelled == [0]
        }
        let fresh = Task { await pipeline.image(for: url) }
        defer { fresh.cancel() }
        try await waitUntil("Fresh same-URL request owns its independent transport") {
            let starts = await transport.startedRequestCount
            let waiters = await pipeline.activeWaiterCount(for: self.url)
            return starts == 2 && waiters == 1
        }
        let completedOld = await transport.complete(0, with: .success(try artwork(width: 7, color: .systemRed)))
        XCTAssertTrue(completedOld)
        let obsoleteResult = await old.value
        XCTAssertNil(obsoleteResult)
        XCTAssertNil(cache.image(for: url), "Late cancelled bytes must not warm the cache with obsolete artwork")
        await assertOwnership(pipeline, loads: 1, waiters: 1)
        let stillVisible = Task { await pipeline.image(for: url) }
        defer { stillVisible.cancel() }
        try await waitUntil("Another consumer joins the fresh load, not a stale cache entry") {
            await pipeline.activeWaiterCount(for: self.url) == 2
        }
        let startsBeforeFreshCompletion = await transport.startedRequestCount
        XCTAssertEqual(startsBeforeFreshCompletion, 2, "Old cleanup must not remove the fresh load and create a third download")
        let cancellationsBeforeFreshCompletion = await transport.cancelledRequestIDs
        XCTAssertEqual(cancellationsBeforeFreshCompletion, [0], "Old cancellation must not target the replacement transport")
        let completedFresh = await transport.complete(1, with: .success(try artwork(width: 23, color: .systemGreen)))
        XCTAssertTrue(completedFresh)
        let freshResult = await fresh.value
        let otherResult = await stillVisible.value
        let image = try XCTUnwrap(freshResult)
        XCTAssertTrue(otherResult === image)
        XCTAssertEqual(image.cgImage?.width, 23, "Only the current transport's artwork is accepted")
        XCTAssertTrue(cache.image(for: url) === image)
        await assertOwnership(pipeline, loads: 0, waiters: 0)
    }

    func testDifferentURLsKeepIndependentTransportAndCancellation() async throws {
        let transport = HeldBadgeTransport()
        let pipeline = pipeline(transport)
        let otherURL = URL(string: "https://badges.invalid/other-crest.png")!
        let first = Task { await pipeline.image(for: url) }
        let second = Task { await pipeline.image(for: otherURL) }
        defer {
            first.cancel(); second.cancel()
            Task { await transport.cancelAllPending() }
        }
        try await waitUntil("Separate identities have separate held downloads") {
            await transport.startedRequestCount == 2
        }
        await assertOwnership(pipeline, loads: 2, waiters: 1)
        await assertOwnership(pipeline, loads: 2, waiters: 1, for: otherURL)
        let firstRequestID = await transport.requestID(for: url)
        let secondRequestID = await transport.requestID(for: otherURL)
        let firstID = try XCTUnwrap(firstRequestID)
        let secondID = try XCTUnwrap(secondRequestID)
        first.cancel()
        try await waitUntil("Only the first URL transport is cancelled") {
            await transport.cancelledRequestIDs == [firstID]
        }
        let cancelledResult = await first.value
        XCTAssertNil(cancelledResult)
        await assertOwnership(pipeline, loads: 1, waiters: 1, for: otherURL)
        let completed = await transport.complete(secondID, with: .success(try artwork(width: 29)))
        XCTAssertTrue(completed)
        let remainingResult = await second.value
        XCTAssertEqual(remainingResult?.cgImage?.width, 29)
        await assertOwnership(pipeline, loads: 0, waiters: 0, for: otherURL)
    }

    func testSharedFailureReleasesOwnershipAndAllowsSameURLRetry() async throws {
        let transport = HeldBadgeTransport()
        let cache = FottyImageCache()
        let clock = BadgeRetryClock()
        let pipeline = FottyImagePipeline(cache: cache, now: { clock.value }, download: { request in
            try await transport.data(for: request)
        })
        let first = Task { await pipeline.image(for: url) }
        let second = Task { await pipeline.image(for: url) }
        defer {
            first.cancel(); second.cancel()
            Task { await transport.cancelAllPending() }
        }
        try await waitUntil("Two consumers share the failure attempt") {
            let starts = await transport.startedRequestCount
            let waiters = await pipeline.activeWaiterCount(for: self.url)
            return starts == 1 && waiters == 2
        }
        let failed = await transport.complete(0, with: .failure(URLError(.networkConnectionLost)))
        XCTAssertTrue(failed)
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertNil(cache.image(for: url))
        await assertOwnership(pipeline, loads: 0, waiters: 0)
        let cooled = await pipeline.image(for: url)
        XCTAssertNil(cooled)
        let startsDuringCooldown = await transport.startedRequestCount
        XCTAssertEqual(startsDuringCooldown, 1)
        clock.advance(by: 2)
        let retry = Task { await pipeline.image(for: url) }
        defer { retry.cancel() }
        try await waitUntil("A failed shared task cannot poison the retry") {
            await transport.startedRequestCount == 2
        }
        let completed = await transport.complete(1, with: .success(try artwork()))
        XCTAssertTrue(completed)
        let retryResult = await retry.value
        XCTAssertNotNil(retryResult)
        await assertOwnership(pipeline, loads: 0, waiters: 0)
    }

    func testBadgeCooldownCannotHideNewCachedPreferredArtworkOrAnotherURL() async throws {
        let recorder = FailedPreferredBadgeTransport(preferred: url)
        let cache = FottyImageCache()
        let clock = BadgeRetryClock()
        let pipeline = FottyImagePipeline(cache: cache, now: { clock.value }, download: { request in
            try await recorder.data(for: request)
        })
        let failed = await pipeline.image(for: url)
        XCTAssertNil(failed)
        let image = try XCTUnwrap(UIImage(data: artwork()))
        cache.insert(image, for: url)
        let warmed = await pipeline.image(for: url)
        XCTAssertTrue(warmed === image, "New authoritative cached art takes precedence over a prior transport failure")
        _ = await pipeline.image(for: URL(string: "https://badges.invalid/new-identity.png")!)
        let otherRequests = await recorder.otherRequestCount
        XCTAssertEqual(otherRequests, 1, "Cooldown is exact-URL, never a host or team ban")
    }

    func testBadgeFailureCooldownRegistryIsBoundedAndExpiredEntriesAreRemoved() async throws {
        let recorder = FailedPreferredBadgeTransport(preferred: url)
        let clock = BadgeRetryClock()
        let pipeline = FottyImagePipeline(cache: FottyImageCache(), now: { clock.value }, download: { request in
            try await recorder.data(for: request)
        })
        for index in 0..<(FottyImagePipeline.maximumFailureEntries + 8) {
            _ = await pipeline.image(for: URL(string: "https://badges.invalid/missing-\(index).png")!)
        }
        let boundedCount = await pipeline.failureEntryCount
        XCTAssertEqual(boundedCount, FottyImagePipeline.maximumFailureEntries)
        clock.advance(by: 2)
        _ = await pipeline.image(for: url)
        let freshCount = await pipeline.failureEntryCount
        XCTAssertEqual(freshCount, 1)
    }

    func testAlreadyCancelledCallerCannotStartDownloadOrReturnWarmArtwork() async throws {
        let transport = HeldBadgeTransport()
        let cache = FottyImageCache()
        let pipeline = pipeline(transport, cache: cache)
        defer { Task { await transport.cancelAllPending() } }
        let cachedURL = URL(string: "https://badges.invalid/cached-crest.png")!
        let image = try XCTUnwrap(UIImage(data: artwork()))
        cache.insert(image, for: cachedURL)
        for candidate in [url, cachedURL] {
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await pipeline.image(for: candidate)
            }
            let result = await cancelled.value
            XCTAssertNil(result, "Cancellation must be checked before both cache lookup and waiter registration")
            await assertOwnership(pipeline, loads: 0, waiters: 0, for: candidate)
        }
        let starts = await transport.startedRequestCount
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(cache.image(for: cachedURL) === image, "Cancellation must not erase accepted cache entries")
    }

    /// Characterize repeated consumer creation with an immediately failing
    /// preferred URL and a warm accepted fallback. This counts real pipeline
    /// transport starts, not network latency or rendered-image timing. Frozen
    /// monotonic time verifies coalescing across recreated consumers reliably.
    func testFailedPreferredWarmFallbackRequestAmplificationMicrobenchmark() async throws {
        let preferred = URL(string: "https://badges.invalid/missing-preferred.png")!
        let fallback = URL(string: "https://badges.invalid/accepted-fallback.png")!
        let transport = FailedPreferredBadgeTransport(preferred: preferred)
        let cache = FottyImageCache()
        let clock = BadgeRetryClock()
        let fallbackImage = try XCTUnwrap(UIImage(data: artwork()))
        cache.insert(fallbackImage, for: fallback)
        let pipeline = FottyImagePipeline(cache: cache, now: { clock.value }, download: { request in
            try await transport.data(for: request)
        })
        let recreations = 32
        var selections: [FottyImageSelectionPolicy.Selection<UIImage>?] = []
        selections.reserveCapacity(recreations)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<recreations {
            let selected = await FottyImageSelectionPolicy.load(urls: [preferred, fallback],
                cache: { cache.image(for: $0) }, fetch: { await pipeline.image(for: $0) })
            selections.append(selected)
        }
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        var accepted = 0
        for selected in selections {
            XCTAssertEqual(selected?.selectedURL, fallback)
            XCTAssertTrue(selected?.value === fallbackImage)
            if selected?.selectedURL == fallback { accepted += 1 }
        }
        let preferredRequests = await transport.preferredRequestCount
        let otherRequests = await transport.otherRequestCount
        XCTAssertEqual(accepted, recreations)
        XCTAssertEqual(preferredRequests, 1, "Recreated consumers retain one exact-URL failure within the bounded retry delay")
        XCTAssertEqual(otherRequests, 0, "A warm fallback must not be downloaded or decoded again")
        await assertOwnership(pipeline, loads: 0, waiters: 0, for: preferred)
        print(String(format: "[BadgeFallbackMicrobenchmark] recreations=%d accepted_fallbacks=%d preferred_requests=%d fallback_requests=%d immediate_failure_total_ms=%.3f",
                     recreations, accepted, preferredRequests, otherRequests, milliseconds))
    }
}

private struct BarrierTimeout: Error, CustomStringConvertible {
    let description: String
}

private final class BadgeRetryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var tick: TimeInterval = 100
    var value: TimeInterval { lock.lock(); defer { lock.unlock() }; return tick }
    func advance(by interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; tick += interval }
}

/// All completions are explicit and addressable by request ID. Ignoring
/// cancellation deliberately simulates a delayed provider completion; the
/// default mode resumes cancelled work immediately and records propagation.
private actor HeldBadgeTransport {
    private let ignoresCancellation: Bool
    private var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var isClosed = false
    private(set) var cancelledRequestIDs: Set<Int> = []
    var startedRequestCount: Int { requests.count }
    var pendingRequestCount: Int { pending.count }

    init(ignoresCancellation: Bool = false) { self.ignoresCancellation = ignoresCancellation }

    func data(for request: URLRequest) async throws -> Data {
        guard !isClosed else { throw CancellationError() }
        let id = requests.count
        requests.append(request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[id] = $0 }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func request(at id: Int) -> URLRequest? { requests.indices.contains(id) ? requests[id] : nil }
    func requestID(for url: URL) -> Int? { requests.firstIndex(where: { $0.url == url }) }

    @discardableResult
    func complete(_ id: Int, with result: Result<Data, any Error>) -> Bool {
        guard let continuation = pending.removeValue(forKey: id) else { return false }
        continuation.resume(with: result)
        return true
    }

    private func cancel(_ id: Int) {
        cancelledRequestIDs.insert(id)
        guard !ignoresCancellation else { return }
        complete(id, with: .failure(CancellationError()))
    }

    func cancelAllPending() {
        isClosed = true
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}

private actor ImmediateBadgeTransport {
    private let result: Data
    private(set) var startedRequestCount = 0
    init(data: Data) { result = data }
    func data(for request: URLRequest) -> Data {
        startedRequestCount += 1
        return result
    }
}

private actor FailedPreferredBadgeTransport {
    private let preferred: URL
    private(set) var preferredRequestCount = 0
    private(set) var otherRequestCount = 0
    init(preferred: URL) { self.preferred = preferred }
    func data(for request: URLRequest) throws -> Data {
        if request.url == preferred { preferredRequestCount += 1 }
        else { otherRequestCount += 1 }
        throw URLError(.badServerResponse)
    }
}
