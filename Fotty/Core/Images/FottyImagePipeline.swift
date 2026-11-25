import SwiftUI
import UIKit
import ImageIO

// MARK: - Image Caching

final class FottyImageCache: @unchecked Sendable {
    static let shared = FottyImageCache()
    private let memoryCache = NSCache<NSURL, UIImage>()

    init() {
        memoryCache.countLimit = 600
        memoryCache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// One bounded pipeline owns badge networking for the whole app. Concurrent
/// rows asking for the same crest share one task, and URLCache provides a small
/// stale-on-disk warm path without allowing catalog scrolling to create an
/// unbounded request storm.
actor FottyImagePipeline {
    static let shared = FottyImagePipeline()
    static let maximumResponseBytes = 2 * 1_024 * 1_024

    typealias Download = @Sendable (URLRequest) async throws -> Data

    private let cache: FottyImageCache
    private let download: Download
    private let failureRetryDelay: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private var retryAfter: [URL: TimeInterval] = [:]
    static let maximumFailureEntries = 256
    private struct InFlightLoad {
        let task: Task<UIImage?, Never>
        var waiters: Set<UUID>
    }
    private var inFlight: [URL: InFlightLoad] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 12 * 1_024 * 1_024,
            diskCapacity: 48 * 1_024 * 1_024,
            diskPath: "fotty-badges"
        )
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        cache = .shared
        failureRetryDelay = 2
        now = { ProcessInfo.processInfo.systemUptime }
        download = { request in
            try await FottyBoundedImageDownload.data(
                for: request, session: session, maximumBytes: Self.maximumResponseBytes
            )
        }
    }

    /// Isolated ownership is useful for deterministic request-sharing tests.
    /// Production retains the single shared cache, bounded URLSession transport
    /// and the same off-main decode scheduler; consumers cannot replace those.
    init(cache: FottyImageCache, failureRetryDelay: TimeInterval = 2,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         download: @escaping Download) {
        self.cache = cache
        self.download = download
        self.failureRetryDelay = failureRetryDelay.isFinite ? min(30, max(0, failureRetryDelay)) : 2
        self.now = now
    }

    var activeLoadCount: Int { inFlight.count }
    var failureEntryCount: Int { retryAfter.count }
    func activeWaiterCount(for url: URL) -> Int { inFlight[url]?.waiters.count ?? 0 }

    func image(for url: URL) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = cache.image(for: url) { return cached }
        // A recreated row must not immediately retry the same failed preferred
        // badge before showing its accepted fallback. Memory-only, exact URL,
        // short monotonic cooldown; a changed URL or newly cached authoritative
        // image remains eligible immediately. This is not a stream health rule.
        if let retry = retryAfter[url], retry > now() { return nil }
        retryAfter[url] = nil
        let waiterID = UUID()
        let task: Task<UIImage?, Never>
        if var existing = inFlight[url] {
            existing.waiters.insert(waiterID)
            inFlight[url] = existing
            task = existing.task
        } else {
            task = Task(priority: .utility) { [download] in
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 8
                    let data = try await download(request)
                    guard !Task.isCancelled else { return nil }
                    return await FottyImageDecodeScheduler.shared.perform {
                        return FottyImageDecoder.decode(data)
                    }
                } catch {
                    return nil
                }
            }
            inFlight[url] = InFlightLoad(task: task, waiters: [waiterID])
        }

        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, for: url) }
        }
        finishWaiter(waiterID, for: url)
        guard !Task.isCancelled else { return nil }
        if let image {
            retryAfter[url] = nil
            cache.insert(image, for: url)
        } else if !task.isCancelled, failureRetryDelay > 0 {
            let tick = now()
            retryAfter = retryAfter.filter { $0.value > tick }
            if retryAfter[url] == nil, retryAfter.count >= Self.maximumFailureEntries,
               let oldest = retryAfter.min(by: { $0.value < $1.value })?.key {
                retryAfter[oldest] = nil
            }
            retryAfter[url] = tick + failureRetryDelay
        }
        return image
    }

    private func cancelWaiter(_ waiterID: UUID, for url: URL) {
        guard var load = inFlight[url], load.waiters.remove(waiterID) != nil else { return }
        if load.waiters.isEmpty {
            load.task.cancel()
            inFlight[url] = nil
        } else {
            inFlight[url] = load
        }
    }

    private func finishWaiter(_ waiterID: UUID, for url: URL) {
        guard var load = inFlight[url], load.waiters.remove(waiterID) != nil else { return }
        inFlight[url] = load.waiters.isEmpty ? nil : load
    }
}

/// Download limits are per host; decoding needs its own app-wide budget.
/// Queued work can be removed when its last visible waiter leaves. A decode
/// already inside ImageIO retains its permit until it really finishes.
actor FottyImageDecodeScheduler {
    static let shared = FottyImageDecodeScheduler(maximumConcurrentDecodes: 2)
    private let limit: Int
    private var active: Set<UUID> = []
    private var queued: [(UUID, CheckedContinuation<Void, any Error>)] = []

    init(maximumConcurrentDecodes: Int) { limit = max(1, maximumConcurrentDecodes) }
    var activeCount: Int { active.count }
    var queuedCount: Int { queued.count }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value?
    ) async -> Value? {
        let id = UUID()
        return await withTaskCancellationHandler {
            do { try await acquire(id) } catch { return nil }
            defer { release(id) }
            guard !Task.isCancelled else { return nil }
            let decode = Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return nil as Value? }
                return operation()
            }
            let result = await withTaskCancellationHandler {
                await decode.value
            } onCancel: {
                decode.cancel()
            }
            return Task.isCancelled ? nil : result
        } onCancel: {
            Task { await self.cancelQueued(id) }
        }
    }

    private func acquire(_ id: UUID) async throws {
        try Task.checkCancellation()
        if active.count < limit { active.insert(id); return }
        try await withCheckedThrowingContinuation { continuation in
            queued.append((id, continuation))
        }
    }

    private func cancelQueued(_ id: UUID) {
        guard let index = queued.firstIndex(where: { $0.0 == id }) else { return }
        let (_, continuation) = queued.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }

    private func release(_ id: UUID) {
        guard active.remove(id) != nil else { return }
        if !queued.isEmpty {
            let (next, continuation) = queued.removeFirst()
            active.insert(next)
            continuation.resume()
        }
    }
}

/// Inspect headers before collecting bytes, and stop unknown/chunked responses
/// at the same limit. AsyncBytes avoids buffering the entire response first;
/// its transport is explicitly cancelled on rejection, caller cancellation and
/// completion. Request sharing and the pipeline's small URLCache stay intact.
enum FottyBoundedImageDownload {
    enum Failure: Error, Equatable {
        case invalidResponse, responseTooLarge
    }

    nonisolated static func data(
        for request: URLRequest, session: URLSession, maximumBytes: Int
    ) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        return try await withTaskCancellationHandler {
            defer { bytes.task.cancel() }
            return try await collect(bytes, response: response, maximumBytes: maximumBytes)
        } onCancel: {
            bytes.task.cancel()
        }
    }

    nonisolated static func collect<Bytes: AsyncSequence>(
        _ bytes: Bytes, response: URLResponse, maximumBytes: Int
    ) async throws -> Data where Bytes.Element == UInt8 {
        try Task.checkCancellation()
        guard maximumBytes > 0, let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { throw Failure.invalidResponse }
        let length = http.expectedContentLength
        guard length == NSURLSessionTransferSizeUnknown || length <= Int64(maximumBytes) else {
            throw Failure.responseTooLarge
        }
        var data = Data()
        data.reserveCapacity(length >= 0 ? Int(length) : min(maximumBytes, 64 * 1_024))
        for try await byte in bytes {
            // Check before appending: even a lying Content-Length cannot grow
            // the collected body beyond the configured byte boundary.
            guard data.count < maximumBytes else { throw Failure.responseTooLarge }
            if data.count % 1_024 == 0 { try Task.checkCancellation() }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}

/// Badge artwork is displayed at no more than 64 points. Decode a bounded
/// thumbnail off the main actor instead of inflating an arbitrary provider
/// image while the user is scrolling.
enum FottyImageDecoder {
    static let maximumPixelDimension = 256

    nonisolated static func decode(_ data: Data, maximumPixelDimension: Int = maximumPixelDimension) -> UIImage? {
        guard maximumPixelDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
}
