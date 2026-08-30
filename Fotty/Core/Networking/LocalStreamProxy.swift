import Foundation
import Network
import AVFoundation
import OSLog

final class LocalStreamProxy {
    private static let logger = Logger(subsystem: "com.jelani.Fotty", category: "LocalStreamProxy")

    private struct IncomingRequest {
        let method: String
        let headers: [String: String]
        let originalURL: URL
    }

    private static let requestHeaderTerminator = Data("\r\n\r\n".utf8)
    private static let maxRequestHeaderBytes = 64 * 1024
    private static let uriAttributeRegex = try? NSRegularExpression(
        pattern: #"URI=\"([^\"]+)\""#,
        options: [.caseInsensitive]
    )

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.fotty.proxy")
    private let headers: [String: String]
    private let cookies: [HTTPCookie]
    private let session: URLSession
    private let stateLock = NSLock()
    private var isStopped = true
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    var port: UInt16? {
        listener?.port?.rawValue
    }

    init(headers: [String: String], cookies: [HTTPCookie]) {
        self.headers = headers
        self.cookies = cookies

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 150
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 8
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: .any)
        withStateLock {
            isStopped = false
            activeConnections.removeAll()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener?.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self?.listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        }
        
        // Final verification: Ensure port is actually bound
        guard port != nil else {
            stop()
            throw NSError(domain: "LocalStreamProxy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind port"])
        }
    }

    /// Health check to verify the proxy is responding.
    func ping() async -> Bool {
        guard let port = port, !stoppedSnapshot() else { return false }
        
        let url = URL(string: "http://127.0.0.1:\(port)/ping")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func stop() {
        let connections = withStateLock {
            isStopped = true
            let connections = Array(activeConnections.values)
            activeConnections.removeAll()
            return connections
        }
        
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
    
    deinit {
        listener?.cancel()
        session.invalidateAndCancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        guard registerConnection(connection) else {
            connection.cancel()
            return
        }
        
        let connectionID = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.unregisterConnection(connectionID)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }
    
    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
    
    private func stoppedSnapshot() -> Bool {
        withStateLock { isStopped }
    }
    
    private func registerConnection(_ connection: NWConnection) -> Bool {
        withStateLock {
            guard !isStopped else { return false }
            activeConnections[ObjectIdentifier(connection)] = connection
            return true
        }
    }
    
    private func unregisterConnection(_ connectionID: ObjectIdentifier) {
        withStateLock {
            activeConnections[connectionID] = nil
        }
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                print("[LocalStreamProxy] Receive error: \(error)")
                connection.cancel()
                return
            }

            var requestData = accumulated
            if let content, !content.isEmpty {
                requestData.append(content)
            }

            if requestData.count > Self.maxRequestHeaderBytes {
                self.sendError(431, message: "Request Header Fields Too Large", on: connection)
                return
            }

            if requestData.range(of: Self.requestHeaderTerminator) != nil {
                self.processRequest(requestData, on: connection)
                return
            }

            if isComplete {
                if requestData.isEmpty {
                    connection.cancel()
                } else {
                    self.processRequest(requestData, on: connection)
                }
                return
            }

            self.receiveRequest(on: connection, accumulated: requestData)
        }
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        // Special Case: Local Proxy Health Check
        if let requestLine = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").first {
            let parts = requestLine.split(separator: " ")
            if parts.count >= 2 && parts[1] == "/ping" {
                sendResponse(HTTPURLResponse(url: URL(string: "http://127.0.0.1/ping")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data: "pong".data(using: .utf8)!, on: connection)
                return
            }
        }

        guard let request = parseRequest(data) else {
            sendError(400, on: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            sendError(405, on: connection)
            return
        }

        Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            guard !self.stoppedSnapshot() else {
                self.sendError(503, message: "Proxy stopped", on: connection)
                return
            }
            await self.forwardRequest(request, on: connection)
        }
    }
    
    private func forwardRequest(_ request: IncomingRequest, on connection: NWConnection) async {
        let remoteRequest = makeRemoteRequest(for: request)
        var didStartStreamingResponse = false
        
        let logMsg = "Incoming: \(request.method) \(request.originalURL.lastPathComponent)"
        pulseLog(logMsg)
        
        let isP2P = request.originalURL.host?.contains("p2p.pixel-invoice.com") == true
        let maxRetries = isP2P ? 45 : 0
        var attempt = 0
        
        while attempt <= maxRetries {
            guard !stoppedSnapshot() else {
                connection.cancel()
                return
            }
            
            do {
                let (bytes, response) = try await session.bytes(for: remoteRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    sendError(500, message: "Invalid remote response", on: connection)
                    return
                }
                
                // Hardened P2P middleware returns 503 for transient manifest/segment failures.
                if isP2P && (httpResponse.statusCode == 503 || httpResponse.statusCode == 504 || httpResponse.statusCode == 404) && attempt < maxRetries {
                    attempt += 1
                    pulseLog("P2P Retry \(attempt)/\(maxRetries) for \(request.originalURL.lastPathComponent)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s backoff
                    continue
                }
                
                pulseLog("Remote \(httpResponse.statusCode) from \(request.originalURL.host ?? "unknown")")
                
                guard !stoppedSnapshot() else {
                    connection.cancel()
                    return
                }
                
                if request.method == "HEAD" {
                    do {
                        try await sendStreamResponseHeader(
                            httpResponse,
                            contentLength: extractContentLength(from: httpResponse),
                            on: connection
                        )
                    } catch {
                        sendError(500, message: "HEAD proxy error: \(error.localizedDescription)", on: connection)
                    }
                    connection.cancel()
                    return
                }
                
                if shouldRewriteManifest(from: request.originalURL, response: httpResponse) {
                    let responseData = try await collectAllData(from: bytes)
                    var finalData = responseData
                    var preserveEncoding = false
                    if let content = String(data: responseData, encoding: .utf8),
                       let proxyPort = port {
                        let rewritten = rewriteManifest(content, relativeTo: request.originalURL, proxyPort: proxyPort)
                        if let rewrittenData = rewritten.data(using: .utf8) {
                            finalData = rewrittenData
                        }
                    } else {
                        // If we can't decode UTF-8, it might be gzipped.
                        // Preserve the encoding header so AVPlayer can handle it.
                        preserveEncoding = true
                    }
                    sendResponse(httpResponse, data: finalData, on: connection, preserveEncoding: preserveEncoding)
                    return
                }
                
                try await sendStreamResponseHeader(
                    httpResponse,
                    contentLength: extractContentLength(from: httpResponse),
                    on: connection
                )
                didStartStreamingResponse = true
                try await streamBody(bytes, on: connection)
                connection.cancel()
                return // Success!
            } catch {
                if didStartStreamingResponse {
                    connection.cancel()
                    return
                }
                
                if (error as? CancellationError) != nil {
                    connection.cancel()
                    return
                }
                
                if attempt < maxRetries {
                    attempt += 1
                    pulseLog("Proxy Retry \(attempt)/\(maxRetries) due to error: \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                
                pulseLog("Proxy Error: \(error.localizedDescription)", level: "ERROR")
                sendError(500, message: error.localizedDescription, on: connection)
                return
            }
        }
    }
    
    private func pulseLog(_ msg: String, level: String = "INFO") {
        // Playback diagnostics must never create competing network traffic.
        // The old remote P2P logger is retired; keep diagnostics on-device.
        if level == "ERROR" {
            Self.logger.error("\(msg, privacy: .public)")
        } else {
            Self.logger.debug("\(msg, privacy: .public)")
        }
    }
    
    private func makeRemoteRequest(for request: IncomingRequest) -> URLRequest {
        var remoteRequest = URLRequest(url: request.originalURL)
        remoteRequest.httpMethod = request.method
        
        // Increased timeout for P2P/AceStream warm-up
        let isP2P = request.originalURL.host?.contains("p2p.pixel-invoice.com") == true
        remoteRequest.timeoutInterval = isP2P ? 120 : 30
        
        for (key, value) in headers {
            remoteRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        if let cookieString = cookieHeaders["Cookie"] {
            remoteRequest.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }
        
        if let rangeValue = request.headers["range"], !rangeValue.isEmpty {
            remoteRequest.setValue(rangeValue, forHTTPHeaderField: "Range")
        }
        if let ifModifiedSince = request.headers["if-modified-since"], !ifModifiedSince.isEmpty {
            remoteRequest.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
        if let ifNoneMatch = request.headers["if-none-match"], !ifNoneMatch.isEmpty {
            remoteRequest.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        
        return remoteRequest
    }

    private func parseRequest(_ data: Data) -> IncomingRequest? {
        guard let headerEnd = data.range(of: Self.requestHeaderTerminator)?.lowerBound else {
            return nil
        }

        let headerData = data.subdata(in: 0..<headerEnd)
        let requestString = String(decoding: headerData, as: UTF8.self)
        let lines = requestString.components(separatedBy: "\r\n")

        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return nil
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        guard let localURL = URL(string: "http://localhost\(path)"),
              let components = URLComponents(url: localURL, resolvingAgainstBaseURL: false),
              let originalURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let originalURL = URL(string: originalURLString) else {
            return nil
        }

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parsedHeaders[key] = value
        }

        return IncomingRequest(method: method, headers: parsedHeaders, originalURL: originalURL)
    }

    private func shouldRewriteManifest(from originalURL: URL, response: HTTPURLResponse) -> Bool {
        if originalURL.pathExtension.lowercased() == "m3u8" {
            return true
        }

        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return contentType.contains("mpegurl") || contentType.contains("application/x-mpegurl")
    }

    private func rewriteManifest(_ manifest: String, relativeTo baseURL: URL, proxyPort: UInt16) -> String {
        let usesCRLF = manifest.contains("\r\n")
        let normalized = manifest.replacingOccurrences(of: "\r\n", with: "\n")
        let rewritten = normalized
            .components(separatedBy: "\n")
            .map { rewriteManifestLine($0, relativeTo: baseURL, proxyPort: proxyPort) }
            .joined(separator: "\n")
        return usesCRLF ? rewritten.replacingOccurrences(of: "\n", with: "\r\n") : rewritten
    }

    private func rewriteManifestLine(_ line: String, relativeTo baseURL: URL, proxyPort: UInt16) -> String {
        var rewritten = rewriteTagURIs(in: line, relativeTo: baseURL, proxyPort: proxyPort)
        let trimmed = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return rewritten
        }

        if let proxied = makeProxyURLString(for: trimmed, relativeTo: baseURL, proxyPort: proxyPort) {
            rewritten = proxied
        }

        return rewritten
    }

    private func rewriteTagURIs(in line: String, relativeTo baseURL: URL, proxyPort: UInt16) -> String {
        guard let regex = Self.uriAttributeRegex else { return line }

        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range).reversed()
        var rewritten = line

        for match in matches {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: rewritten) else {
                continue
            }

            let originalValue = String(rewritten[valueRange])
            guard let proxied = makeProxyURLString(for: originalValue, relativeTo: baseURL, proxyPort: proxyPort) else {
                continue
            }

            rewritten.replaceSubrange(valueRange, with: proxied)
        }

        return rewritten
    }

    private func makeProxyURLString(for rawURL: String, relativeTo baseURL: URL, proxyPort: UInt16) -> String? {
        let candidate = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if candidate.contains("127.0.0.1:\(proxyPort)/proxy?url=") {
            return candidate
        }

        guard let absoluteURL = resolveURL(candidate, relativeTo: baseURL),
              let localURL = localProxyURL(for: absoluteURL, proxyPort: proxyPort) else {
            return nil
        }

        return localURL.absoluteString
    }

    private func resolveURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        if value.hasPrefix("//") {
            let scheme = baseURL.scheme ?? "https"
            return URL(string: "\(scheme):\(value)")
        }

        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }

        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private func localProxyURL(for remoteURL: URL, proxyPort: UInt16) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(proxyPort)
        components.path = "/proxy"
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }

    private func extractContentLength(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Content-Length") else {
            return nil
        }
        return Int(value)
    }
    
    private func collectAllData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        data.reserveCapacity(64 * 1024)
        
        for try await byte in bytes {
            data.append(byte)
        }
        
        return data
    }
    
    private func sendStreamResponseHeader(
        _ response: HTTPURLResponse,
        contentLength: Int?,
        on connection: NWConnection
    ) async throws {
        var headerString = "HTTP/1.1 \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))\r\n"
        
        for (key, value) in response.allHeaderFields {
            let keyString = "\(key)"
            let normalizedKey = keyString.lowercased()
            if normalizedKey == "content-length"
                || normalizedKey == "transfer-encoding"
                || normalizedKey == "connection" {
                continue
            }
            
            headerString += "\(keyString): \(value)\r\n"
        }
        
        if let contentLength {
            headerString += "Content-Length: \(contentLength)\r\n"
        }
        headerString += "Connection: close\r\n"
        headerString += "\r\n"
        
        guard let headerData = headerString.data(using: .utf8) else {
            throw NSError(
                domain: "LocalStreamProxy",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode response headers"]
            )
        }
        
        try await sendData(headerData, on: connection)
    }
    
    private func streamBody(_ bytes: URLSession.AsyncBytes, on connection: NWConnection) async throws {
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        
        for try await byte in bytes {
            buffer.append(byte)
            // Send in 64KB chunks for better throughput
            if buffer.count >= 64 * 1024 {
                try await sendData(buffer, on: connection)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        
        if !buffer.isEmpty {
            try await sendData(buffer, on: connection)
        }
    }
    
    private func sendData(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed({ error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }))
        }
    }

    private func sendResponse(
        _ response: HTTPURLResponse,
        data: Data,
        on connection: NWConnection,
        contentLengthOverride: Int? = nil,
        preserveEncoding: Bool = false
    ) {
        var headerString = "HTTP/1.1 \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))\r\n"

        for (key, value) in response.allHeaderFields {
            let keyString = "\(key)"
            let normalized = keyString.lowercased()
            if ["content-length", "transfer-encoding"].contains(normalized) {
                continue
            }
            if normalized == "content-encoding" && !preserveEncoding {
                continue
            }
            headerString += "\(keyString): \(value)\r\n"
        }

        let contentLength = contentLengthOverride ?? data.count
        headerString += "Content-Length: \(contentLength)\r\n"
        headerString += "Connection: close\r\n"
        headerString += "\r\n"

        guard let headerData = headerString.data(using: .utf8) else {
            connection.cancel()
            return
        }

        var totalData = headerData
        totalData.append(data)

        connection.send(content: totalData, completion: .contentProcessed({ error in
            if let error {
                print("[LocalStreamProxy] Send error: \(error)")
            }
            connection.cancel()
        }))
    }

    private func sendError(_ code: Int, message: String = "", on connection: NWConnection) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: code)
        let body = message.isEmpty ? reason : message
        let content = """
        HTTP/1.1 \(code) \(reason)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: content.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

// MARK: - Playback Diagnostics

/// Analyzes AVPlayerItem logs to identify specific failure layers.
final class PlayerDiagnosticService {
    struct DiagnosticSnapshot {
        let statusCode: Int?
        let serverAddress: String?
        let errorComment: String?
        let domain: String?
        let errorCode: Int?
        
        var failureReason: String {
            if let comment = errorComment { return comment }
            if let code = statusCode, code >= 400 { return "HTTP \(code)" }
            return "Unknown"
        }
    }
    
    /// Extracts a diagnostic snapshot from an AVPlayerItem.
    func analyze(_ item: AVPlayerItem) -> DiagnosticSnapshot {
        var statusCode: Int?
        var serverAddress: String?
        var errorComment: String?
        var domain: String?
        var errorCode: Int?
        
        // Check Error Log
        if let errorLog = item.errorLog(), let lastEvent = errorLog.events.last {
            errorComment = lastEvent.errorComment
            domain = lastEvent.errorDomain
            errorCode = lastEvent.errorStatusCode
            statusCode = lastEvent.errorStatusCode // Use errorCode as statusCode for heuristic
        }
        
        // Check Access Log
        if let accessLog = item.accessLog(), let lastEvent = accessLog.events.last {
            serverAddress = lastEvent.serverAddress
        }
        
        return DiagnosticSnapshot(
            statusCode: statusCode,
            serverAddress: serverAddress,
            errorComment: errorComment,
            domain: domain,
            errorCode: errorCode
        )
    }
    
    /// Maps low-level errors to user-friendly messages.
    func userFriendlyError(for snapshot: DiagnosticSnapshot) -> String {
        if let comment = snapshot.errorComment {
            if comment.contains("403") { return "Source Access Denied (403)" }
            if comment.contains("404") { return "Source Not Found (404)" }
            if comment.contains("unsupported") { return "Format Not Supported" }
        }
        
        if let domain = snapshot.domain {
            if domain == "NSURLErrorDomain" { return "Network Connection Failure" }
            if domain == "CoreMediaErrorDomain" { return "Media Decoding Error" }
        }
        
        return "Source Unavailable"
    }
}

// MARK: - Stream Contract Validation

/// Verifies that a resolved URL actually contains valid video stream data.
final class StreamContractValidator {
    enum ValidationResult {
        case valid
        case invalid(String)
    }
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()
    
    /// Validates a URL by checking its headers and first few bytes.
    func validate(_ url: URL, headers: [String: String]) async -> ValidationResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Only fetch the first 1KB to save bandwidth and time
        request.setValue("bytes=0-1024", forHTTPHeaderField: "Range")
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .invalid("Invalid response type")
            }
            
            // Check status code (allow 200 or 206 Partial Content)
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
                return .invalid("HTTP \(httpResponse.statusCode)")
            }
            
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            
            // Validate Content-Type
            let validTypes = ["application/x-mpegurl", "application/vnd.apple.mpegurl", "video/mp4", "video/mp2t", "application/octet-stream"]
            let isTypeValid = validTypes.contains { contentType.contains($0) }
            
            // If it's an HLS stream, check for #EXTM3U
            if contentType.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8" {
                if let content = String(data: data, encoding: .utf8), content.contains("#EXTM3U") {
                    return .valid
                } else {
                    return .invalid("Malformed M3U8 (No #EXTM3U found)")
                }
            }
            
            if isTypeValid {
                return .valid
            }
            
            // If we get HTML instead of video, it's a failure (often a provider redirect or ad gate)
            if contentType.contains("text/html") {
                return .invalid("Received HTML instead of Video")
            }
            
            return .invalid("Unsupported Content-Type: \(contentType)")
            
        } catch {
            return .invalid(error.localizedDescription)
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
