import Foundation
import Network
import AVFoundation
import CryptoKit

/// A single-use, loopback-only relay owned by one selected playback item.
final class LocalStreamProxy: @unchecked Sendable {
    struct ParsedRequest {
        let method: String
        let path: String
        let headers: [String: String]
    }

    private struct ConnectionState {
        let ownerID: UUID
        let connection: NWConnection
        let deadline: DispatchSourceTimer
        var task: Task<Void, Never>?
        var requestEvidence: LocalStreamProxyRequestReceipt?
    }

    private static let requestHeaderTerminator = Data("\r\n\r\n".utf8)
    private let queue = DispatchQueue(label: "com.fotty.proxy")
    private let headers: [String: String]
    private let cookies: [HTTPCookie]
    private let selectedMediaURL: URL
    private let session: URLSession
    private let resolver: LocalStreamProxyDestinationValidator.Resolver
    private let limits: LocalStreamProxyPolicy.Limits
    private let originProfile: LocalStreamProxyOriginProfile?
    private let stateLock = NSLock()
    private var policy: LocalStreamProxyPolicy
    private var listener: NWListener?
    private var didStart = false
    private var isStopped = false
    private var startup: LocalStreamProxyCompletion<Void>?
    private var activeConnections: [ObjectIdentifier: ConnectionState] = [:]
    private var failureEvidence: LocalStreamProxyFailureEvidence?
    private let relayID = UUID()
    private var requestReceipts: [LocalStreamProxyRequestReceipt] = []
    private var evictedRequestReceiptCount = 0
    private var playlistProgress = LocalHLSPlaylistProgress()

    var port: UInt16? { withStateLock { isStopped ? nil : listener?.port?.rawValue } }
    var activeConnectionCount: Int { withStateLock { activeConnections.count } }
    /// This is the last observed failure of this item's relay, not proof that it
    /// caused AVPlayer to stop. Its age and separate namespace preserve that
    /// distinction when concurrent playlist/segment requests are in flight.
    var lastFailureEvidence: LocalStreamProxyFailureEvidence? { withStateLock { failureEvidence } }

    /// A bounded observation of this exact relay, not an explanation of a
    /// decoder failure. Copy under the relay lock; persist only outside it.
    func requestEvidenceSnapshot(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> LocalStreamProxyRequestSnapshot {
        withStateLock { .init(relayID: relayID, requests: requestReceipts,
                             evictedCount: evictedRequestReceiptCount, observedAt: now) }
    }

    /// Capture the historical failure and request window atomically, then build
    /// finite export fields without holding a lock or touching persistence.
    func diagnosticDetails(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [String: String] {
        let captured = withStateLock { (LocalStreamProxyRequestSnapshot(relayID: relayID,
            requests: requestReceipts, evictedCount: evictedRequestReceiptCount, observedAt: now), failureEvidence,
            playlistProgress.latestSnapshot) }
        return captured.0.qualityDetails()
            .merging(captured.1?.qualityDetails() ?? [:]) { _, value in value }
            .merging(captured.2?.qualityDetails(at: now) ?? [:]) { _, value in value }
    }

    /// A current, repeated upstream-window observation, never a decoded-video
    /// claim or permission to reuse a URL. The item owner must fence any retry.
    func hasNonAdvancingLivePlaylist(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        withStateLock { !isStopped && playlistProgress.latestSnapshot?.isNonAdvancingLive(at: now) == true }
    }

    /// Recent sequence progress can support one owned stalled-transport renewal;
    /// it neither proves decoded progress nor grants a new delivery authority.
    func hasAdvancingLivePlaylist(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        withStateLock { !isStopped && playlistProgress.latestSnapshot?.isAdvancingLive(at: now) == true }
    }

    init(headers: [String: String], cookies: [HTTPCookie], selectedMediaURL: URL,
         limits: LocalStreamProxyPolicy.Limits = .init(),
         originProfile: LocalStreamProxyOriginProfile? = nil,
         playlistProfile: LocalStreamProxyPlaylistProfile? = nil,
         configuration: URLSessionConfiguration? = nil,
         resolver: @escaping LocalStreamProxyDestinationValidator.Resolver = { try await LocalStreamProxyDestinationValidator.resolve($0) }) {
        self.headers = headers
        self.cookies = cookies
        self.selectedMediaURL = selectedMediaURL
        self.limits = limits
        self.originProfile = originProfile?.validated(for: selectedMediaURL, headers: headers)
        self.resolver = resolver
        policy = LocalStreamProxyPolicy(selectedMediaURL: selectedMediaURL, limits: limits,
                                        originProfile: self.originProfile, requestHeaders: headers,
                                        playlistProfile: playlistProfile)
        let config = configuration ?? .ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = limits.requestSeconds
        config.timeoutIntervalForResource = limits.resourceSeconds
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = min(6, limits.connections)
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func playbackURL() -> URL? {
        withStateLock {
            guard !isStopped, let port = listener?.port?.rawValue else { return nil }
            return policy.playbackURL(port: port)
        }
    }

    func start() async throws {
        try Task.checkCancellation()
        let completion = LocalStreamProxyCompletion<Void>()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.requiredInterfaceType = .loopback
        let newListener = try NWListener(using: parameters)
        let admitted = withStateLock {
            guard !didStart, !isStopped, policy.isValid else { return false }
            didStart = true
            listener = newListener
            startup = completion
            return true
        }
        guard admitted else { newListener.cancel(); throw URLError(.unsupportedURL) }

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: completion.finish(.success(()))
            case .failed(let error):
                completion.finish(.failure(error))
                self?.stop()
            case .cancelled: completion.finish(.failure(CancellationError()))
            default: break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.handleConnection(connection)
        }
        newListener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard !completion.isFinished else { return }
            completion.finish(.failure(URLError(.timedOut)))
            self?.stop()
        }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { completion.install($0) }
                try Task.checkCancellation()
                guard port != nil else { throw URLError(.cannotConnectToHost) }
            } onCancel: { [weak self] in self?.stop() }
        } catch {
            stop()
            throw error
        }
    }

    func ping() async -> Bool {
        guard let url = withStateLock({ () -> URL? in
            guard !isStopped, let port = listener?.port?.rawValue else { return nil }
            return URL(string: "http://127.0.0.1:\(port)\(policy.pingPath)")
        }) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.httpShouldHandleCookies = false
        do {
            let (data, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200 && data == Data("pong".utf8)
        } catch { return false }
    }

    func stop() {
        let owned = withStateLock { () -> (NWListener?, [ConnectionState], LocalStreamProxyCompletion<Void>?) in
            isStopped = true
            policy.revoke()
            for identifier in Array(activeConnections.keys) {
                _ = updateRequestEvidenceLocked(identifier, outcome: .cancelled)
            }
            let owned = (listener, Array(activeConnections.values), startup)
            listener = nil
            startup = nil
            activeConnections.removeAll()
            return owned
        }
        owned.2?.finish(.failure(CancellationError()))
        owned.0?.cancel()
        for state in owned.1 {
            state.deadline.cancel()
            state.task?.cancel()
            state.connection.cancel()
        }
        session.invalidateAndCancel()
    }

    deinit {
        listener?.cancel()
        for state in activeConnections.values {
            state.deadline.cancel()
            state.task?.cancel()
            state.connection.cancel()
        }
        session.invalidateAndCancel()
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func handleConnection(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        let ownerID = UUID()
        let deadline = DispatchSource.makeTimerSource(queue: queue)
        deadline.schedule(deadline: .now() + limits.headerSeconds)
        deadline.setEventHandler { [weak self] in self?.closeConnection(identifier, expectedOwnerID: ownerID) }
        let admitted = withStateLock {
            guard !isStopped, activeConnections.count < limits.connections else { return false }
            activeConnections[identifier] = ConnectionState(ownerID: ownerID, connection: connection, deadline: deadline)
            return true
        }
        // A suspended dispatch source must be resumed before destruction.
        deadline.resume()
        guard admitted else { deadline.cancel(); connection.cancel(); return }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.closeConnection(identifier, expectedOwnerID: ownerID)
            default: break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func closeConnection(_ identifier: ObjectIdentifier, expectedOwnerID: UUID? = nil) {
        guard let state = withStateLock({ () -> ConnectionState? in
            guard let state = activeConnections[identifier], expectedOwnerID == nil || state.ownerID == expectedOwnerID else { return nil }
            _ = updateRequestEvidenceLocked(identifier, outcome: .cancelled)
            return activeConnections.removeValue(forKey: identifier)
        }) else { return }
        state.deadline.cancel()
        state.task?.cancel()
        state.connection.cancel()
    }

    /// Cancellation cannot recall a timer handler already queued for execution.
    /// Only a deadline that still owns its connection may record a failure.
    func expireResourceConnection(_ identifier: ObjectIdentifier, expectedOwnerID: UUID? = nil) {
        let state = withStateLock { () -> ConnectionState? in
            guard !isStopped, let state = activeConnections[identifier],
                  expectedOwnerID == nil || state.ownerID == expectedOwnerID else { return nil }
            let receipt = updateRequestEvidenceLocked(identifier, phase: .resourceDeadline, outcome: .failed)
            // A queued deadline cannot replace an already completed request.
            guard state.requestEvidence == nil || receipt != nil else { return nil }
            failureEvidence = LocalStreamProxyFailureEvidence(stage: .resourceDeadline, kind: .timeout,
                statusCode: nil, errorCode: nil, recordedAt: Date(), relayID: relayID,
                requestID: receipt?.requestID, resourceID: receipt?.resourceID,
                resourceCategory: receipt?.resourceCategory)
            return activeConnections.removeValue(forKey: identifier)
        }
        guard let state else { return }
        state.deadline.cancel()
        state.task?.cancel()
        state.connection.cancel()
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] content, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            guard error == nil else { self.closeConnection(ObjectIdentifier(connection)); return }
            var data = accumulated
            if let content { data.append(content) }
            guard data.count <= self.limits.requestHeaderBytes else {
                self.sendError(431, on: connection); return
            }
            if data.range(of: Self.requestHeaderTerminator) != nil {
                self.processRequest(data, on: connection)
            } else if isComplete {
                self.closeConnection(ObjectIdentifier(connection))
            } else {
                self.receiveRequest(on: connection, accumulated: data)
            }
        }
    }

    static func parseRequest(_ data: Data, port: UInt16) -> ParsedRequest? {
        guard let end = data.range(of: requestHeaderTerminator),
              end.upperBound == data.endIndex,
              let text = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
              parts[1].hasPrefix("/"), !parts[1].hasPrefix("//"),
              !parts[1].contains("?"), !parts[1].contains("#"), !parts[1].contains("%") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = String(line[..<separator]).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil,
                  name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !value.contains(where: { $0.asciiValue.map({ $0 < 32 || $0 == 127 }) ?? false }) else { return nil }
            headers[name] = value
        }
        guard headers["host"] == "127.0.0.1:\(port)", headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == "0" else { return nil }
        return ParsedRequest(method: String(parts[0]), path: String(parts[1]), headers: headers)
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        guard let port, let request = Self.parseRequest(data, port: port) else {
            sendError(400, on: connection); return
        }
        guard request.method == "GET" || request.method == "HEAD" else {
            sendError(405, on: connection); return
        }
        if withStateLock({ !isStopped && request.path == policy.pingPath }) {
            sendResponse(status: 200, headers: ["Content-Type": "text/plain"],
                         data: request.method == "HEAD" ? Data() : Data("pong".utf8), on: connection)
            return
        }
        guard let remoteURL = withStateLock({ policy.destination(for: request.path) }) else {
            sendError(404, on: connection); return
        }
        let identifier = ObjectIdentifier(connection)
        withStateLock {
            guard var state = activeConnections[identifier], !isStopped else { return }
            let hint = LocalStreamProxyRequestReceipt.resourceHint(for: remoteURL)
            let receipt = LocalStreamProxyRequestReceipt(relayID: relayID, requestID: UUID(),
                resourceID: LocalStreamProxyRequestReceipt.resourceIdentifier(for: request.path) ?? UUID(),
                method: request.method == "HEAD" ? .head : .get,
                resourceCategory: hint.0, categoryBasis: hint.1,
                startedAt: ProcessInfo.processInfo.systemUptime)
            state.requestEvidence = receipt
            activeConnections[identifier] = state
            requestReceipts.append(receipt)
            if requestReceipts.count > LocalStreamProxyRequestSnapshot.maximumRetainedRequests {
                requestReceipts.removeFirst(requestReceipts.count - LocalStreamProxyRequestSnapshot.maximumRetainedRequests)
                evictedRequestReceiptCount = min(1_000_000, evictedRequestReceiptCount + 1)
            }
            let ownerID = state.ownerID
            activeConnections[identifier]?.deadline.setEventHandler { [weak self] in
                self?.expireResourceConnection(identifier, expectedOwnerID: ownerID)
            }
            activeConnections[identifier]?.deadline.schedule(deadline: .now() + limits.resourceSeconds)
        }
        let task = Task { [weak self] in
            guard let self else { connection.cancel(); return }
            await self.forwardRequest(request, remoteURL: remoteURL, on: connection)
        }
        let owned = withStateLock {
            guard !isStopped, activeConnections[identifier] != nil else { return false }
            activeConnections[identifier]?.task = task
            return true
        }
        if !owned { task.cancel(); connection.cancel() }
    }

    private func makeRemoteRequest(url: URL, request: ParsedRequest) -> URLRequest {
        LocalStreamProxyPolicy.remoteRequest(
            url: url, selectedMediaURL: selectedMediaURL, method: request.method,
            capturedHeaders: headers, cookies: cookies, clientHeaders: request.headers,
            timeout: limits.requestSeconds)
    }

    private func forwardRequest(_ request: ParsedRequest, remoteURL: URL, on connection: NWConnection) async {
        let delegate = RedirectDelegate(proxy: self, request: request, limit: limits.redirects)
        await withTaskCancellationHandler {
            var startedResponse = false
            var stage = LocalStreamProxyFailureEvidence.Stage.destinationValidation
            do {
                try await validateDestination(remoteURL)
                stage = .upstreamResponse
                updateRequestEvidence(on: connection, phase: stage)
                let (bytes, response) = try await session.bytes(for: makeRemoteRequest(url: remoteURL, request: request), delegate: delegate)
                defer { bytes.task.cancel(); delegate.cancel() }
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, let finalURL = http.url,
                      withStateLock({ !isStopped && policy.contains(finalURL) }),
                      !(300...399).contains(http.statusCode) || http.statusCode == 304
                else { throw URLError(.badServerResponse) }
                let hint = LocalStreamProxyRequestReceipt.resourceHint(for: finalURL,
                    contentType: http.value(forHTTPHeaderField: "Content-Type"))
                updateRequestEvidence(on: connection, statusCode: http.statusCode, category: hint)
                guard (200...299).contains(http.statusCode) || http.statusCode == 304 else {
                    recordFailure(on: connection, stage: stage, kind: .httpStatus, statusCode: http.statusCode)
                    sendError(http.statusCode, on: connection); return
                }
                let isManifest = finalURL.pathExtension.lowercased() == "m3u8"
                    || (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("mpegurl")
                if isManifest {
                    stage = .manifest
                    updateRequestEvidence(on: connection, phase: stage)
                    // Never relabel a partial/conditional upstream response as
                    // a complete rewritten playlist. Unknown MIME-only routes
                    // remain fail-closed; there is no retry or MIME refetch.
                    guard http.statusCode == 200, http.value(forHTTPHeaderField: "Content-Range") == nil else {
                        throw LocalStreamProxyPolicy.Failure.manifest
                    }
                }
                let byteLimit = isManifest ? limits.manifestBytes : limits.resourceBytes
                guard http.expectedContentLength <= Int64(byteLimit) else { throw URLError(.dataLengthExceedsMaximum) }
                if request.method == "HEAD" || http.statusCode == 304 {
                    if isManifest {
                        // The upstream length/validators describe unrewritten
                        // bytes. HEAD may omit them rather than invent a length.
                        try await sendData(responseHeader(status: 200,
                            headers: ["Content-Type": "application/vnd.apple.mpegurl"]), on: connection)
                    } else {
                        try await sendHeader(http, length: responseLength(http), on: connection)
                    }
                    updateRequestEvidence(on: connection, outcome: .completed)
                    closeConnection(ObjectIdentifier(connection))
                    return
                }
                if isManifest {
                    stage = .manifest
                    updateRequestEvidence(on: connection, phase: stage)
                    let data = try await collectData(bytes, limit: limits.manifestBytes)
                    guard let manifest = String(data: data, encoding: .utf8), let port else { throw URLError(.cannotDecodeContentData) }
                    let rewritten = try withStateLock { try policy.rewriteManifest(manifest, relativeTo: finalURL, port: port) }
                    // Observe only bytes already fetched for this guarded GET.
                    // No playlist bodies, destinations or extra requests leave
                    // this path; cancelled/replaced connections cannot publish.
                    let upstreamFacts = LocalHLSPlaylistProgress.Facts.observed(in: manifest)
                    let rewrittenFacts = LocalHLSPlaylistProgress.Facts.observed(in: rewritten)
                    withStateLock {
                        guard !isStopped, !Task.isCancelled,
                              let receipt = activeConnections[ObjectIdentifier(connection)]?.requestEvidence,
                              receipt.outcome == .inFlight else { return }
                        playlistProgress.observe(upstream: upstreamFacts, rewritten: rewrittenFacts,
                            resourceID: receipt.resourceID, startedAt: receipt.startedAt,
                            at: ProcessInfo.processInfo.systemUptime)
                    }
                    sendResponse(status: 200, headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                                 data: Data(rewritten.utf8), on: connection)
                } else {
                    stage = .resource
                    updateRequestEvidence(on: connection, phase: stage)
                    try await sendHeader(http, length: responseLength(http), on: connection)
                    startedResponse = true
                    try await streamBody(bytes, limit: limits.resourceBytes, on: connection)
                    updateRequestEvidence(on: connection, outcome: .completed)
                    closeConnection(ObjectIdentifier(connection))
                }
            } catch {
                delegate.cancel()
                if !Task.isCancelled, !withStateLock({ isStopped }) {
                    recordFailure(on: connection, stage: stage, kind: .classify(error), error: error as NSError)
                }
                if startedResponse || Task.isCancelled || withStateLock({ isStopped }) {
                    closeConnection(ObjectIdentifier(connection))
                } else {
                    // Provider URLs, credentials and low-level network messages
                    // never become local response bodies or public log records.
                    sendError(502, on: connection)
                }
            }
        } onCancel: {
            delegate.cancel()
            connection.cancel()
        }
    }

    private func recordFailure(on connection: NWConnection, stage: LocalStreamProxyFailureEvidence.Stage,
                               kind: LocalStreamProxyFailureEvidence.Kind,
                               statusCode: Int? = nil, error: NSError? = nil) {
        withStateLock {
            let identifier = ObjectIdentifier(connection)
            guard !isStopped, let state = activeConnections[identifier] else { return }
            let receipt = updateRequestEvidenceLocked(identifier, phase: stage, statusCode: statusCode, outcome: .failed)
            guard state.requestEvidence == nil || receipt != nil else { return }
            failureEvidence = LocalStreamProxyFailureEvidence(stage: stage, kind: kind,
                statusCode: statusCode, errorCode: error?.code,
                errorDomain: error.map { NativePlaybackErrorDomain($0.domain) }, recordedAt: Date(),
                relayID: relayID, requestID: receipt?.requestID, resourceID: receipt?.resourceID,
                resourceCategory: receipt?.resourceCategory)
        }
    }

    private func updateRequestEvidence(on connection: NWConnection,
        phase: LocalStreamProxyFailureEvidence.Stage? = nil, statusCode: Int? = nil,
        category: (LocalStreamProxyRequestReceipt.ResourceCategory, LocalStreamProxyRequestReceipt.CategoryBasis)? = nil,
        outcome: LocalStreamProxyRequestReceipt.Outcome? = nil) {
        withStateLock { _ = updateRequestEvidenceLocked(ObjectIdentifier(connection), phase: phase,
            statusCode: statusCode, category: category, outcome: outcome) }
    }

    /// Must run under stateLock. Terminal receipts are immutable; neither a late
    /// cancellation nor a queued timeout can turn a completed transfer into a
    /// different outcome or resurrect an evicted receipt.
    @discardableResult
    private func updateRequestEvidenceLocked(_ identifier: ObjectIdentifier,
        phase: LocalStreamProxyFailureEvidence.Stage? = nil, statusCode: Int? = nil,
        category: (LocalStreamProxyRequestReceipt.ResourceCategory, LocalStreamProxyRequestReceipt.CategoryBasis)? = nil,
        outcome: LocalStreamProxyRequestReceipt.Outcome? = nil) -> LocalStreamProxyRequestReceipt? {
        guard var state = activeConnections[identifier], var receipt = state.requestEvidence,
              receipt.outcome == .inFlight else { return nil }
        receipt.observedAt = ProcessInfo.processInfo.systemUptime
        if let phase { receipt.phase = phase }
        if let statusCode, (100...599).contains(statusCode) { receipt.httpStatus = statusCode }
        if let category { receipt.resourceCategory = category.0; receipt.categoryBasis = category.1 }
        if let outcome { receipt.outcome = outcome }
        state.requestEvidence = receipt
        activeConnections[identifier] = state
        if let index = requestReceipts.firstIndex(where: { $0.requestID == receipt.requestID }) {
            requestReceipts[index] = receipt
        }
        return receipt
    }

    private func validateDestination(_ url: URL) async throws {
        guard withStateLock({ !isStopped && policy.contains(url) }) else { throw CancellationError() }
        try await LocalStreamProxyDestinationValidator.validate(url, originProfile: originProfile, resolver: resolver)
        try Task.checkCancellation()
        guard withStateLock({ !isStopped }) else { throw CancellationError() }
    }

    private func redirect(from source: URL, to destination: URL, request: ParsedRequest) async throws -> URLRequest {
        guard withStateLock({ !isStopped && policy.contains(source) }) else { throw CancellationError() }
        try await LocalStreamProxyDestinationValidator.validate(destination, originProfile: originProfile, resolver: resolver)
        try Task.checkCancellation()
        try withStateLock {
            guard !isStopped else { throw CancellationError() }
            try policy.admitRedirect(from: source, to: destination)
        }
        // Rebuild from scoped captured state, never Foundation's inherited
        // redirect headers (which can carry Cookie/Authorization/custom secrets).
        return makeRemoteRequest(url: destination, request: request)
    }

    private func responseLength(_ response: HTTPURLResponse) -> Int? {
        guard response.value(forHTTPHeaderField: "Content-Encoding") == nil,
              let raw = response.value(forHTTPHeaderField: "Content-Length"),
              let length = Int(raw), length >= 0 else { return nil }
        return length
    }

    private func collectData(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 65_536))
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    private func streamBody(_ bytes: URLSession.AsyncBytes, limit: Int, on connection: NWConnection) async throws {
        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var count = 0
        for try await byte in bytes {
            guard count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            count += 1
            buffer.append(byte)
            if buffer.count == 65_536 {
                try Task.checkCancellation()
                try await sendData(buffer, on: connection)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { try await sendData(buffer, on: connection) }
    }

    private func sendHeader(_ response: HTTPURLResponse, length: Int?, on connection: NWConnection) async throws {
        let allowed = ["Content-Type", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified"]
        var headers: [String: String] = [:]
        for key in allowed {
            if let value = response.value(forHTTPHeaderField: key), !value.contains(where: { $0.isNewline }) {
                headers[key] = value
            }
        }
        if let length { headers["Content-Length"] = String(length) }
        try await sendData(responseHeader(status: response.statusCode, headers: headers), on: connection)
    }

    private func responseHeader(status: Int, headers: [String: String]) -> Data {
        var text = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        for (key, value) in headers { text += "\(key): \(value)\r\n" }
        text += "Connection: close\r\nCache-Control: no-store\r\n\r\n"
        return Data(text.utf8)
    }

    private func sendData(_ data: Data, on connection: NWConnection) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func sendResponse(status: Int, headers: [String: String] = [:], data: Data, on connection: NWConnection) {
        var headers = headers
        headers["Content-Length"] = String(data.count)
        var response = responseHeader(status: status, headers: headers)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            if let self {
                if let error, let phase = self.withStateLock({ self.activeConnections[ObjectIdentifier(connection)]?.requestEvidence?.phase }) {
                    self.recordFailure(on: connection, stage: phase, kind: .classify(error), error: error as NSError)
                } else if error == nil {
                    self.updateRequestEvidence(on: connection, outcome: .completed)
                }
                self.closeConnection(ObjectIdentifier(connection))
            }
            connection.cancel()
        })
    }

    private func sendError(_ code: Int, on connection: NWConnection) {
        sendResponse(status: code, headers: ["Content-Type": "text/plain"],
                     data: Data(HTTPURLResponse.localizedString(forStatusCode: code).utf8), on: connection)
    }

    final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private weak var proxy: LocalStreamProxy?
        private let request: ParsedRequest
        private let limit: Int
        private let lock = NSLock()
        private var count = 0
        private var isCancelled = false
        private var validation: Task<Void, Never>?

        init(proxy: LocalStreamProxy, request: ParsedRequest, limit: Int) {
            self.proxy = proxy
            self.request = request
            self.limit = limit
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let task = validation
            validation = nil
            lock.unlock()
            task?.cancel()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            lock.lock()
            count += 1
            let allowed = !isCancelled && count <= limit
            lock.unlock()
            guard allowed, let proxy, let source = response.url, let destination = request.url else {
                completionHandler(nil); return
            }
            let validation = Task {
                do {
                    let next = try await proxy.redirect(from: source, to: destination, request: self.request)
                    try Task.checkCancellation()
                    guard task.state != .canceling && task.state != .completed else {
                        completionHandler(nil); return
                    }
                    completionHandler(next)
                } catch { completionHandler(nil) }
            }
            lock.lock()
            self.validation = validation
            let cancelled = isCancelled
            lock.unlock()
            if cancelled { validation.cancel() }
        }
    }
}

// MARK: - Playback Diagnostics

/// Metadata observed at this relay's HTTP boundary, never decoded video proof.
/// Resource UUIDs are the existing random route identifiers without the relay
/// capability. Requests have separate UUIDs, even for repeated byte ranges.
/// Finite observations of existing relay responses. These describe publisher
/// playlist windows, never decoded frames or a new authority to fetch media.
struct LocalHLSPlaylistProgress: Sendable {
    static let maximumResources = 16

    struct Facts: Equatable, Sendable {
        enum Kind: String, Sendable { case master, media, unknown }
        let kind: Kind
        let mediaSequence: Int64?
        let targetDuration: Int?
        let endList: Bool
        let segmentCount: Int
        let lastSegmentDigest: String?

        static func observed(in manifest: String) -> Self {
            let unknown = Self(kind: .unknown, mediaSequence: nil, targetDuration: nil,
                endList: false, segmentCount: 0, lastSegmentDigest: nil)
            // Rewritten loopback references can be longer than original URIs.
            guard manifest.utf8.count <= 2 * 1_024 * 1_024 else { return unknown }
            var sequence: Int64?, duration: Int?, sawSequence = false, sawDuration = false
            var master = false, media = false, endList = false, malformed = false, partialContract = false
            var pendingDuration: String?, pendingRange: String?, count = 0, lastDigest: String?
            var firstLine = true
            for raw in manifest.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                if firstLine {
                    guard line == "#EXTM3U" else { return unknown }
                    firstLine = false
                    continue
                }
                if line.hasPrefix("#EXT-X-STREAM-INF:") || line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                    master = true
                } else if line.hasPrefix("#EXT-X-PART:") || line.hasPrefix("#EXT-X-PART-INF:")
                    || line.hasPrefix("#EXT-X-SERVER-CONTROL:") && line.contains("CAN-BLOCK-RELOAD=YES") {
                    // Complete segments alone cannot describe LL-HLS progress.
                    // Keep its scalar facts, but do not call advancing parts a
                    // frozen ordinary playlist or trigger descriptor renewal.
                    partialContract = true; media = true
                } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                    if sawSequence { malformed = true }
                    sawSequence = true; media = true
                    sequence = Int64(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
                    if sequence == nil || sequence! < 0 { malformed = true }
                } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                    if sawDuration { malformed = true }
                    sawDuration = true; media = true
                    duration = Int(line.dropFirst("#EXT-X-TARGETDURATION:".count))
                    if duration.map({ (1...3_600).contains($0) }) != true { malformed = true }
                } else if line == "#EXT-X-ENDLIST" {
                    endList = true; media = true
                } else if line.hasPrefix("#EXTINF:") {
                    if pendingDuration != nil { malformed = true }
                    media = true
                    pendingDuration = String(line.prefix(128))
                } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                    pendingRange = String(line.prefix(128))
                } else if !line.hasPrefix("#"), let segmentDuration = pendingDuration {
                    count += 1
                    // Keep only a one-way digest, not a URL, signed query or
                    // body. URI/token-only changes are NOT sequence progress.
                    let identity = segmentDuration + "\n" + (pendingRange ?? "") + "\n" + line
                    lastDigest = SHA256.hash(data: Data(identity.utf8)).prefix(16)
                        .map { String(format: "%02x", $0) }.joined()
                    pendingDuration = nil; pendingRange = nil
                }
            }
            guard !firstLine, !malformed, pendingDuration == nil, !(master && media), count <= 100_000 else { return unknown }
            return Self(kind: master ? .master : (media && !partialContract ? .media : .unknown), mediaSequence: sequence,
                targetDuration: duration, endList: endList, segmentCount: count, lastSegmentDigest: lastDigest)
        }

        fileprivate var lastSequence: Int64? {
            guard let mediaSequence, segmentCount > 0,
                  mediaSequence <= Int64.max - Int64(segmentCount - 1) else { return nil }
            return mediaSequence + Int64(segmentCount - 1)
        }
    }

    struct Window: Equatable, Sendable {
        enum Change: String, Sendable { case initial, advanced, unchanged, regressed, windowChanged = "window_changed", unknown }
        let facts: Facts
        let change: Change
        let unchangedSince: TimeInterval?

        fileprivate static func observing(_ facts: Facts, previous: Self?, previousObservedAt: TimeInterval) -> Self {
            guard let previous, facts.kind == .media, previous.facts.kind == .media else {
                return .init(facts: facts, change: previous == nil ? .initial : .unknown, unchangedSince: nil)
            }
            if facts == previous.facts {
                return .init(facts: facts, change: .unchanged,
                    unchangedSince: previous.unchangedSince ?? previousObservedAt)
            }
            let change: Change
            if let old = previous.facts.lastSequence, let new = facts.lastSequence, new != old {
                change = new > old ? .advanced : .regressed
            } else { change = .windowChanged }
            return .init(facts: facts, change: change, unchangedSince: nil)
        }
    }

    struct Snapshot: Equatable, Sendable {
        let resourceID: UUID
        let upstream: Window
        let rewritten: Window
        let sampleCount: Int
        let startedAt: TimeInterval
        let observedAt: TimeInterval

        var metadataPreserved: Bool {
            let a = upstream.facts, b = rewritten.facts
            return a.kind == b.kind && a.mediaSequence == b.mediaSequence && a.targetDuration == b.targetDuration
                && a.endList == b.endList && a.segmentCount == b.segmentCount
        }

        func isNonAdvancingLive(at now: TimeInterval) -> Bool {
            let facts = upstream.facts
            guard now.isFinite, now >= observedAt, now - observedAt <= 15, sampleCount >= 2,
                  facts.kind == .media, facts.mediaSequence != nil, facts.segmentCount > 0,
                  !facts.endList, metadataPreserved,
                  upstream.change == .unchanged, rewritten.change == .unchanged,
                  let target = facts.targetDuration, let unchangedSince = upstream.unchangedSince,
                  observedAt - unchangedSince > Double(target) * 1.5 else { return false }
            return true
        }

        func isAdvancingLive(at now: TimeInterval) -> Bool {
            let facts = upstream.facts
            return now.isFinite && now >= observedAt && now - observedAt <= 15 && sampleCount >= 2
                && facts.kind == .media && facts.mediaSequence != nil && facts.segmentCount > 0
                && facts.targetDuration != nil && !facts.endList && metadataPreserved
                && upstream.change == .advanced && rewritten.change == .advanced
        }

        func qualityDetails(at now: TimeInterval) -> [String: String] {
            var details = ["relay_playlist_resource_id": resourceID.uuidString,
                "relay_playlist_samples": String(sampleCount),
                "relay_playlist_metadata_preserved": String(metadataPreserved)]
            if let age = Self.milliseconds(observedAt, now) { details["relay_playlist_age_ms"] = String(age) }
            for (prefix, window) in [("upstream", upstream), ("rewritten", rewritten)] {
                let key = "relay_playlist_\(prefix)_"
                let facts = window.facts
                details[key + "kind"] = facts.kind.rawValue
                details[key + "change"] = window.change.rawValue
                details[key + "endlist"] = String(facts.endList)
                details[key + "segments"] = String(facts.segmentCount)
                if let sequence = facts.mediaSequence { details[key + "sequence"] = String(sequence) }
                if let duration = facts.targetDuration { details[key + "target_ms"] = String(duration * 1_000) }
                if let digest = facts.lastSegmentDigest { details[key + "last_digest"] = digest }
                // Do not extend an unchanged claim beyond the final response.
                if let start = window.unchangedSince, let duration = Self.milliseconds(start, observedAt) {
                    details[key + "unchanged_ms"] = String(duration)
                }
            }
            return details
        }

        private static func milliseconds(_ start: TimeInterval, _ end: TimeInterval) -> Int? {
            guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
            return Int(min(3_600_000, (end - start) * 1_000))
        }
    }

    private var snapshots: [UUID: Snapshot] = [:]
    var retainedCount: Int { snapshots.count }
    var latestSnapshot: Snapshot? {
        // A late master request must not obscure the media window observation.
        let media = snapshots.values.filter { $0.upstream.facts.kind == .media }
        return (media.isEmpty ? Array(snapshots.values) : media).max { $0.observedAt < $1.observedAt }
    }

    mutating func observe(upstream: Facts, rewritten: Facts, resourceID: UUID,
                         startedAt: TimeInterval, at now: TimeInterval) {
        guard startedAt.isFinite, now.isFinite, startedAt >= 0, now >= startedAt else { return }
        let previous = snapshots[resourceID]
        // Concurrent older GET completions cannot roll back a newer sample.
        guard previous.map({ startedAt >= $0.startedAt && now >= $0.observedAt }) ?? true else { return }
        if previous == nil, snapshots.count >= Self.maximumResources,
           let oldest = snapshots.values.min(by: { $0.observedAt < $1.observedAt }) {
            snapshots[oldest.resourceID] = nil
        }
        snapshots[resourceID] = Snapshot(resourceID: resourceID,
            upstream: .observing(upstream, previous: previous?.upstream, previousObservedAt: previous?.observedAt ?? now),
            rewritten: .observing(rewritten, previous: previous?.rewritten, previousObservedAt: previous?.observedAt ?? now),
            sampleCount: min(1_000_000, (previous?.sampleCount ?? 0) + 1), startedAt: startedAt, observedAt: now)
    }
}

struct LocalStreamProxyRequestReceipt: Equatable, Sendable {
    enum Method: String, Sendable { case get = "GET", head = "HEAD" }
    enum ResourceCategory: String, Sendable { case manifest, media, unknown }
    enum CategoryBasis: String, Sendable { case response, pathHint = "path_hint", unknown }
    enum Outcome: String, Sendable { case inFlight = "in_flight", completed, failed, cancelled }

    let relayID: UUID
    let requestID: UUID
    let resourceID: UUID
    let method: Method
    var resourceCategory: ResourceCategory
    var categoryBasis: CategoryBasis
    let startedAt: TimeInterval
    var observedAt: TimeInterval
    var phase: LocalStreamProxyFailureEvidence.Stage = .destinationValidation
    var httpStatus: Int?
    var outcome: Outcome = .inFlight

    init(relayID: UUID, requestID: UUID, resourceID: UUID, method: Method,
         resourceCategory: ResourceCategory, categoryBasis: CategoryBasis, startedAt: TimeInterval) {
        self.relayID = relayID; self.requestID = requestID; self.resourceID = resourceID
        self.method = method; self.resourceCategory = resourceCategory; self.categoryBasis = categoryBasis
        self.startedAt = startedAt; self.observedAt = startedAt
    }

    static func resourceIdentifier(for path: String) -> UUID? {
        guard let tail = path.split(separator: "/").last, tail.count == 32,
              tail.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let bytes = Array(tail)
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(bytes[$0]) }
        return UUID(uuidString: groups.joined(separator: "-"))
    }

    /// A path/MIME hint is explicitly not a container, codec or playback claim.
    /// Nested query URLs and response bodies never enter diagnostic metadata.
    static func resourceHint(for url: URL, contentType: String? = nil) -> (ResourceCategory, CategoryBasis) {
        let mime = contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["application/x-mpegurl", "application/vnd.apple.mpegurl"].contains(mime) { return (.manifest, .response) }
        if mime.hasPrefix("video/") || mime.hasPrefix("audio/") { return (.media, .response) }
        if url.pathExtension.lowercased() == "m3u8" { return (.manifest, .pathHint) }
        if ["mp4", "m4s", "ts", "aac"].contains(url.pathExtension.lowercased()) { return (.media, .pathHint) }
        return (.unknown, .unknown)
    }
}

struct LocalStreamProxyRequestSnapshot: Equatable, Sendable {
    static let maximumRetainedRequests = 32
    let relayID: UUID
    let requests: [LocalStreamProxyRequestReceipt]
    let evictedCount: Int
    let observedAt: TimeInterval

    func qualityDetails() -> [String: String] {
        let retained = Array(requests.suffix(Self.maximumRetainedRequests))
        var details = ["relay_id": relayID.uuidString,
            "relay_retained_request_count": String(retained.count),
            "relay_evicted_request_count": String(max(0, min(1_000_000, evictedCount)))]
        for outcome in [LocalStreamProxyRequestReceipt.Outcome.inFlight, .completed, .failed, .cancelled] {
            details["relay_retained_\(outcome.rawValue)_count"] = String(retained.filter { $0.outcome == outcome }.count)
        }
        if let latest = retained.max(by: { $0.observedAt < $1.observedAt }) {
            details.merge(["relay_request_id": latest.requestID.uuidString, "relay_resource_id": latest.resourceID.uuidString,
                "relay_request_method": latest.method.rawValue, "relay_resource_category": latest.resourceCategory.rawValue,
                "relay_resource_basis": latest.categoryBasis.rawValue, "relay_request_phase": latest.phase.rawValue,
                "relay_request_outcome": latest.outcome.rawValue]) { _, value in value }
            if let status = latest.httpStatus, (100...599).contains(status) { details["relay_request_http_status"] = String(status) }
            if let age = Self.milliseconds(from: latest.observedAt, to: observedAt) { details["relay_request_age_ms"] = String(age) }
            if let duration = Self.milliseconds(from: latest.startedAt, to: latest.observedAt) { details["relay_request_elapsed_ms"] = String(duration) }
        }
        if let failed = retained.filter({ $0.outcome == .failed }).max(by: { $0.observedAt < $1.observedAt }) {
            details["relay_observed_failure_request_id"] = failed.requestID.uuidString
            details["relay_observed_failure_resource_id"] = failed.resourceID.uuidString
            details["relay_same_resource_later_completed"] = String(retained.contains {
                $0.resourceID == failed.resourceID && $0.outcome == .completed && $0.observedAt > failed.observedAt
            })
        }
        return details
    }

    private static func milliseconds(from start: TimeInterval, to end: TimeInterval) -> Int? {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        return Int(min(3_600_000, (end - start) * 1_000))
    }
}

struct LocalStreamProxyFailureEvidence: Equatable {
    enum Stage: String, Sendable { case destinationValidation = "destination_validation", upstreamResponse = "upstream_response", manifest, resource, resourceDeadline = "resource_deadline" }
    enum Kind: String {
        case httpStatus = "http_status", timeout, destinationDenied = "destination_denied"
        case invalidManifest = "invalid_manifest", capacity, responseTooLarge = "response_too_large"
        case invalidResponse = "invalid_response", network, other

        static func classify(_ error: Error) -> Kind {
            if let failure = error as? LocalStreamProxyPolicy.Failure {
                switch failure {
                case .destination: return .destinationDenied
                case .manifest: return .invalidManifest
                case .capacity: return .capacity
                case .revoked: return .other
                }
            }
            let value = error as NSError
            guard value.domain == NSURLErrorDomain else { return .other }
            switch value.code {
            case URLError.timedOut.rawValue: return .timeout
            case URLError.unsupportedURL.rawValue: return .destinationDenied
            case URLError.dataLengthExceedsMaximum.rawValue: return .responseTooLarge
            case URLError.badServerResponse.rawValue, URLError.cannotDecodeContentData.rawValue: return .invalidResponse
            default: return .network
            }
        }
    }

    let stage: Stage
    let kind: Kind
    let statusCode: Int?
    let errorCode: Int?
    var errorDomain: NativePlaybackErrorDomain? = nil
    let recordedAt: Date
    var relayID: UUID? = nil
    var requestID: UUID? = nil
    var resourceID: UUID? = nil
    var resourceCategory: LocalStreamProxyRequestReceipt.ResourceCategory? = nil

    func qualityDetails(now: Date = Date()) -> [String: String] {
        let elapsed = now.timeIntervalSince(recordedAt) * 1_000
        let age = elapsed.isFinite ? Int(max(0, min(3_600_000, elapsed))) : 0
        var details = ["relay_failure_stage": stage.rawValue, "relay_failure_kind": kind.rawValue,
                       "relay_failure_age_ms": String(age)]
        if let statusCode, (100...599).contains(statusCode) { details["relay_http_status"] = String(statusCode) }
        if let errorCode, NativePlaybackErrorDomain.isBoundedCode(errorCode) { details["relay_error_code"] = String(errorCode) }
        if let errorDomain { details["relay_error_domain"] = errorDomain.rawValue }
        if let relayID { details["relay_id"] = relayID.uuidString }
        if let requestID { details["relay_failure_request_id"] = requestID.uuidString }
        if let resourceID { details["relay_failure_resource_id"] = resourceID.uuidString }
        if let resourceCategory { details["relay_failure_resource_category"] = resourceCategory.rawValue }
        return details
    }
}

enum NativePlaybackDiagnosticTrigger: String {
    case failedToPlayToEnd = "failed_to_play_to_end"
    case itemStatusFailed = "item_status_failed"
    case errorLog = "error_log"
    case readinessTimeout = "readiness_timeout"
    case stallTimeout = "stall_timeout"
}

enum NativePlaybackErrorDomain: String {
    case url = "url", avFoundation = "avfoundation", coreMedia = "coremedia", osStatus = "osstatus", http, other

    init(_ domain: String) {
        switch domain {
        case NSURLErrorDomain: self = .url
        case AVFoundationErrorDomain: self = .avFoundation
        case "CoreMediaErrorDomain": self = .coreMedia
        case NSOSStatusErrorDomain: self = .osStatus
        case "HTTP", "HTTPStatusCode": self = .http
        default: self = .other
        }
    }

    static func isBoundedCode(_ code: Int) -> Bool { (-2_147_483_648...2_147_483_647).contains(code) }
}

/// An observed Apple HLS consistency complaint, not a decoding of a numeric
/// CoreMedia code. Only these exact typed-message prefixes become finite local
/// evidence; the sequence number, URLs and other private message text never do.
enum NativeHLSPlaylistIssue: String, CaseIterable {
    case segmentURIChanged = "segment_uri_changed"
    case segmentDurationChanged = "segment_duration_changed"
    case segmentDiscontinuityChanged = "segment_discontinuity_changed"

    static func observed(in description: String?, domain: NativePlaybackErrorDomain) -> Self? {
        guard domain == .coreMedia, let description else { return nil }
        // Inspect only a bounded prefix. Do not retain the raw comment or use
        // substring matching, which could mistake arbitrary provider text for
        // Apple's complaint. Unknown/localized wording remains unclassified.
        let prefix = String(description.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let known: [(String, Self)] = [
            ("media entry url not match previous playlist for media-sequence ", .segmentURIChanged),
            ("media entry time value does not match previous playlist for media-sequence ", .segmentDurationChanged),
            ("media entry discontinuity value does not match previous playlist for media-sequence ", .segmentDiscontinuityChanged)
        ]
        return known.first(where: { prefix.hasPrefix($0.0) })?.1
    }
}

/// Extracts bounded typed errors, never records provider descriptions, userInfo,
/// URIs or server addresses. Apple error logs may describe recoverable internal retries;
/// they are diagnostic evidence, not themselves a terminal playback boundary.
final class PlayerDiagnosticService {
    struct DiagnosticSnapshot {
        let statusCode: Int?
        let domain: NativePlaybackErrorDomain?
        let errorCode: Int?
        let qualityDetails: [String: String]
        let primaryErrorReason: String?

        var failureReason: String {
            // The last error-log event can describe an earlier recoverable
            // playlist/segment retry. It cannot override the actual item or
            // failed-to-end notification error at this fatal boundary.
            if let primaryErrorReason { return primaryErrorReason }
            if let code = statusCode { return "Player item failed: HTTP \(code)" }
            if let domain, let code = errorCode { return "Player item failed: \(domain.rawValue) \(code)" }
            return "Player item failed: underlying cause unavailable"
        }
    }

    func analyze(_ item: AVPlayerItem, trigger: NativePlaybackDiagnosticTrigger = .errorLog,
                 reportedError: Error? = nil) -> DiagnosticSnapshot {
        let event = item.errorLog()?.events.last
        let native = snapshot(error: reportedError ?? item.error, trigger: trigger,
                        logDomain: event?.errorDomain, logCode: event?.errorStatusCode,
                        logComment: event?.errorComment)
        guard let access = item.accessLog()?.events.last else { return native }
        // Read existing on-device AVPlayer observations at this diagnostic
        // boundary only. No URL/server address, recurring observer or upload.
        let measured = NativePlaybackAccessMetrics(observedBitrate: access.observedBitrate,
            indicatedBitrate: access.indicatedBitrate, stallCount: access.numberOfStalls,
            droppedFrames: access.numberOfDroppedVideoFrames, bytes: access.numberOfBytesTransferred,
            transferDuration: access.transferDuration).qualityDetails
        return .init(statusCode: native.statusCode, domain: native.domain, errorCode: native.errorCode,
            qualityDetails: native.qualityDetails.merging(measured) { _, value in value },
            primaryErrorReason: native.primaryErrorReason)
    }

    /// Pure entry point permits error-chain/privacy regression without loading a
    /// provider URL or constructing a failed AVPlayerItem through live traffic.
    func snapshot(error: Error?, trigger: NativePlaybackDiagnosticTrigger,
                  logDomain: String? = nil, logCode: Int? = nil,
                  logComment: String? = nil) -> DiagnosticSnapshot {
        var details = ["native_failure_trigger": trigger.rawValue]
        var chain: [(NativePlaybackErrorDomain, Int)] = []
        var current = error.map { $0 as NSError }
        var seen: Set<ObjectIdentifier> = []
        var depth = 0
        while let value = current, depth < 4, seen.insert(ObjectIdentifier(value)).inserted {
            depth += 1
            let domain = NativePlaybackErrorDomain(value.domain)
            if NativePlaybackErrorDomain.isBoundedCode(value.code) { chain.append((domain, value.code)) }
            if details["native_hls_issue"] == nil {
                // NSError's actual notification/item chain is kept distinct
                // from a possibly older recoverable error-log comment.
                let descriptions = ["NSDescription", NSLocalizedFailureReasonErrorKey, NSLocalizedDescriptionKey]
                if let issue = descriptions.lazy.compactMap({ key in
                    NativeHLSPlaylistIssue.observed(in: value.userInfo[key] as? String, domain: domain)
                }).first {
                    details["native_hls_issue"] = issue.rawValue
                }
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        // Keep only first and deepest available error; depth is capped even if
        // an upstream error supplies a cyclic or unexpectedly long chain.
        if let first = chain.first {
            details["native_error_domain"] = first.0.rawValue
            details["native_error_code"] = String(first.1)
            details["native_error_depth"] = String(depth)
            if chain.count > 1, let underlying = chain.last {
                details["native_underlying_domain"] = underlying.0.rawValue
                details["native_underlying_code"] = String(underlying.1)
            }
        }
        let typedLogDomain = logDomain.map { NativePlaybackErrorDomain($0) }
        let boundedLogCode = logCode.flatMap { NativePlaybackErrorDomain.isBoundedCode($0) ? $0 : nil }
        if let typedLogDomain { details["native_log_domain"] = typedLogDomain.rawValue }
        if let boundedLogCode { details["native_log_code"] = String(boundedLogCode) }
        if let typedLogDomain,
           let issue = NativeHLSPlaylistIssue.observed(in: logComment, domain: typedLogDomain) {
            details["native_log_hls_issue"] = issue.rawValue
        }
        // A CoreMedia/OSStatus value of 404 is not an HTTP404. Do not infer
        // response semantics from an untyped numerical error identifier.
        let status = typedLogDomain == .http ? boundedLogCode.flatMap { (400...599).contains($0) ? $0 : nil } : nil
        let primaryReason = error.map { _ in
            chain.first.map { "Player item failed: \($0.0.rawValue) \($0.1)" }
                ?? "Player item failed: underlying cause unavailable"
        }
        return DiagnosticSnapshot(statusCode: status, domain: chain.first?.0 ?? typedLogDomain,
                                  errorCode: chain.first?.1 ?? boundedLogCode, qualityDetails: details,
                                  primaryErrorReason: primaryReason)
    }
}

struct NativePlaybackAccessMetrics {
    let observedBitrate: Double
    let indicatedBitrate: Double
    let stallCount: Int
    let droppedFrames: Int
    let bytes: Int64
    let transferDuration: TimeInterval

    var qualityDetails: [String: String] {
        var details: [String: String] = [:]
        for (key, value) in [("native_access_observed_bitrate", observedBitrate), ("native_access_indicated_bitrate", indicatedBitrate)] {
            if value.isFinite, value > 0, value <= 10_000_000_000 { details[key] = String(Int64(value)) }
        }
        if stallCount >= 0 { details["native_access_stalls"] = String(min(1_000_000, stallCount)) }
        if droppedFrames >= 0 { details["native_access_dropped_frames"] = String(min(1_000_000_000, droppedFrames)) }
        if bytes >= 0 { details["native_access_bytes"] = String(min(1_000_000_000_000, bytes)) }
        if transferDuration.isFinite, transferDuration >= 0 {
            details["native_access_transfer_ms"] = String(Int(min(3_600_000, transferDuration * 1_000)))
        }
        return details
    }
}

// MARK: - Stream Contract Validation

/// Pre-item failures are not AVPlayer item failures. Keep their stage and finite
/// contract reason separate, and admit only bounded error identifiers. Never
/// persist an error description, response MIME value, URL or NSError userInfo.
struct PlaybackPreparationDiagnostic {
    enum Stage: String {
        case urlPreparation = "url_preparation"
        case contractValidation = "contract_validation"
        case playbackStart = "playback_start"
    }

    enum Reason: String {
        case unavailable
        case proxyStartup = "proxy_startup"
        case proxyHealthCheck = "proxy_health_check"
        case httpStatus = "http_status"
        case invalidResponse = "invalid_response"
        case responseTooLarge = "response_too_large"
        case unsafeRedirect = "unsafe_redirect"
        case cancelled
        case transportError = "transport_error"
        case leaseExpired = "lease_expired"
        case emptyMedia = "empty_media"
        case malformedManifest = "malformed_manifest"
        case htmlResponse = "html_response"
        case unsupportedContentType = "unsupported_content_type"
        case playbackStartTimeout = "playback_start_timeout"
    }

    let qualityDetails: [String: String]

    init(stage: Stage, reason: Reason, error: Error? = nil, httpStatus: Int? = nil) {
        var details = ["preparation_stage": stage.rawValue, "preparation_reason": reason.rawValue]
        var current = error.map { $0 as NSError }
        var seen: Set<ObjectIdentifier> = []
        var chain: [(NativePlaybackErrorDomain, Int)] = []
        var depth = 0
        while let value = current, depth < 4, seen.insert(ObjectIdentifier(value)).inserted {
            depth += 1
            if NativePlaybackErrorDomain.isBoundedCode(value.code) {
                chain.append((NativePlaybackErrorDomain(value.domain), value.code))
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if let first = chain.first {
            details["preparation_error_domain"] = first.0.rawValue
            details["preparation_error_code"] = String(first.1)
            details["preparation_error_depth"] = String(depth)
            if chain.count > 1, let underlying = chain.last {
                details["preparation_underlying_domain"] = underlying.0.rawValue
                details["preparation_underlying_code"] = String(underlying.1)
            }
        }
        // An arbitrary numerical NSError code is not evidence of HTTP status.
        if let httpStatus, (100...599).contains(httpStatus) {
            details["preparation_http_status"] = String(httpStatus)
        }
        qualityDetails = details
    }
}

/// Carries the original recovery error without changing its private policy
/// classification. Only the already bounded receipt enters the quality ring.
struct PlaybackPreparationFailure: Error {
    let underlyingError: Error
    let qualityDetails: [String: String]

    init(_ error: Error, reason: PlaybackPreparationDiagnostic.Reason,
         relayEvidence: LocalStreamProxyFailureEvidence? = nil) {
        underlyingError = error
        qualityDetails = PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: reason,
            // A local health-check failure has a known finite reason, not a
            // synthetic Foundation error purporting to explain the transport.
            error: reason == .proxyHealthCheck || reason == .cancelled ? nil : error).qualityDetails
            .merging(relayEvidence?.qualityDetails() ?? [:]) { _, value in value }
    }
}

/// Checks a bounded response media contract. This is not codec, decoded-video,
/// uninterrupted-playback or picture-in-picture qualification.
final class StreamContractValidator {
    enum ValidationResult {
        /// Kept for injected/legacy validation seams. No probe evidence is implied.
        case valid
        case validWithEvidence(StreamMediaProbeEvidence)
        case invalid(String, diagnostics: PlaybackPreparationDiagnostic? = nil)

        var isValid: Bool {
            switch self {
            case .valid, .validWithEvidence: return true
            case .invalid: return false
            }
        }

        var mediaEvidence: StreamMediaProbeEvidence? {
            guard case .validWithEvidence(let evidence) = self else { return nil }
            return evidence
        }
    }
    
    private let transport: FottyBoundedHTTPClient
    private let deadline: TimeInterval

    init(configuration: URLSessionConfiguration? = nil, deadline: TimeInterval = 5) {
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        transport = FottyBoundedHTTPClient(configuration: config)
        self.deadline = deadline
    }
    
    /// Validates a URL by checking its headers and first few bytes.
    func validate(_ url: URL, headers: [String: String]) async -> ValidationResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // A captured full-resource Range must not replace the validation probe.
        // Prefix mode also stops reading when a server ignores this header.
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        
        do {
            let response = try await transport.fetch(request, maximumBytes: 1024, mode: .prefix,
                deadline: deadline, acceptedStatusCodes: [200, 206])
            try Task.checkCancellation()
            let data = response.data
            let httpResponse = response.http
            guard !data.isEmpty else {
                return .invalid("Empty media response", diagnostics:
                    .init(stage: .contractValidation, reason: .emptyMedia))
            }
            
            // Check status code (allow 200 or 206 Partial Content)
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
                return .invalid("HTTP \(httpResponse.statusCode)", diagnostics:
                    .init(stage: .contractValidation, reason: .httpStatus, httpStatus: httpResponse.statusCode))
            }
            
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let evidence = StreamMediaProbeEvidence(contentType: contentType, prefix: data)
            
            // Validate Content-Type
            let validTypes = ["application/x-mpegurl", "application/vnd.apple.mpegurl", "video/mp4", "video/mp2t", "application/octet-stream"]
            let isTypeValid = validTypes.contains { contentType.contains($0) }
            
            // If it's an HLS stream, check for #EXTM3U
            if contentType.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8" {
                if evidence.observedContainer == .hls {
                    return .validWithEvidence(evidence)
                } else {
                    return .invalid("Malformed M3U8 (No #EXTM3U found)", diagnostics:
                        .init(stage: .contractValidation, reason: .malformedManifest))
                }
            }
            
            if isTypeValid {
                return .validWithEvidence(evidence)
            }

            // An opaque endpoint may omit a media MIME type. An actual bounded
            // HLS/MP4 signature is stronger than guessing from that URL's suffix.
            if evidence.observedContainer == .hls || evidence.observedContainer == .mp4 {
                return .validWithEvidence(evidence)
            }
            
            // If we get HTML instead of video, it's a failure (often a provider redirect or ad gate)
            if contentType.contains("text/html") {
                return .invalid("Received HTML instead of Video", diagnostics:
                    .init(stage: .contractValidation, reason: .htmlResponse))
            }
            
            return .invalid("Unsupported Content-Type: \(contentType)", diagnostics:
                .init(stage: .contractValidation, reason: .unsupportedContentType))
            
        } catch let failure as FottyBoundedHTTPClient.Failure {
            if case .httpStatus(let status) = failure {
                return .invalid("HTTP \(status)", diagnostics:
                    .init(stage: .contractValidation, reason: .httpStatus, httpStatus: status))
            }
            let reason: PlaybackPreparationDiagnostic.Reason
            switch failure {
            case .invalidResponse: reason = .invalidResponse
            case .responseTooLarge: reason = .responseTooLarge
            case .unsafeRedirect: reason = .unsafeRedirect
            case .httpStatus: reason = .httpStatus
            }
            return .invalid("Invalid stream response", diagnostics:
                .init(stage: .contractValidation, reason: reason))
        } catch is CancellationError {
            return .invalid("Validation cancelled", diagnostics:
                .init(stage: .contractValidation, reason: .cancelled))
        } catch {
            return .invalid(error.localizedDescription, diagnostics:
                .init(stage: .contractValidation, reason: .transportError, error: error))
        }
    }
}

// MARK: - Playback Failure Classification

enum PlaybackFailureReason: String, CaseIterable {
    case invalidURL = "invalidURL"
    case emptyURL = "emptyURL"
    case unsupportedFormat = "unsupportedFormat"
    case htmlInsteadOfMedia = "htmlInsteadOfMedia"
    case jsonInsteadOfMedia = "jsonInsteadOfMedia"
    case unauthorized401 = "unauthorized401"
    case forbidden403 = "forbidden403"
    case notFound404 = "notFound404"
    case serverError = "serverError"
    case timeout = "timeout"
    case missingHeaders = "missingHeaders"
    case expiredToken = "expiredToken"
    case noVideoTrack = "noVideoTrack"
    case avPlayerItemFailed = "avPlayerItemFailed"
    case stalledBeforeFirstFrame = "stalledBeforeFirstFrame"
    case playbackStartedButNoFrame = "playbackStartedButNoFrame"
    case playerViewNotRendering = "playerViewNotRendering"
    case unknown = "unknown"
}

struct PlaybackCandidateResult {
    let index: Int
    let providerName: String
    let urlType: String
    let httpStatus: Int?
    let contentType: String?
    let itemStatus: String
    let hasVideoTrack: Bool
    let hasAudioTrack: Bool
    let firstFrameRendered: Bool
    let playbackAdvanced: Bool
    let failureReason: PlaybackFailureReason?
    
    func logSummary() {
        print("""
        ----------------------------------------
        Candidate \(index + 1): \(providerName)
        URL Type: \(urlType)
        HTTP: \(httpStatus ?? 0)
        Content-Type: \(contentType ?? "unknown")
        AVPlayerItem Status: \(itemStatus)
        Video Track: \(hasVideoTrack ? "YES" : "NO")
        Audio Track: \(hasAudioTrack ? "YES" : "NO")
        First Frame: \(firstFrameRendered ? "YES" : "NO")
        Failure Reason: \(failureReason?.rawValue ?? "NONE")
        ----------------------------------------
        """)
    }
}

// MARK: - Playback Probe

final class PlaybackProbe {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
    
    func probe(url: URL, headers: [String: String]) async -> (status: Int?, contentType: String?, type: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (nil, nil, "unknown") }
            
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            var type = "unknown"
            
            if contentType.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8" {
                type = "HLS .m3u8"
            } else if contentType.contains("video/mp4") || url.pathExtension.lowercased() == "mp4" {
                type = "MP4"
            } else if contentType.contains("text/html") {
                type = "embed webpage"
            } else if contentType.contains("application/dash+xml") {
                type = "DASH .mpd"
            }
            
            return (http.statusCode, contentType, type)
        } catch {
            return (nil, nil, "error: \(error.localizedDescription)")
        }
    }
}
