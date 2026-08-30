import Foundation

@main
struct P2PMacTester {
    static func main() async {
        let cli = CLI(arguments: Array(CommandLine.arguments.dropFirst()))
        do {
            try await cli.run()
        } catch let error as CLIError {
            FileHandle.standardError.writeLine(error.message)
            exit(Int32(error.exitCode))
        } catch {
            FileHandle.standardError.writeLine("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}

private final class CLI {
    private let arguments: [String]
    private let client = P2PClient()

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        let args = Array(arguments.dropFirst())
        switch command {
        case "help", "-h", "--help":
            printHelp()
        case "status":
            try await runStatus()
        case "browse":
            try await runBrowse(args)
        case "search":
            try await runSearch(args)
        case "probe":
            try await runProbe(args)
        case "play":
            var playArgs = args
            if !playArgs.contains("--open") {
                playArgs.append("--open")
            }
            try await runProbe(playArgs)
        default:
            throw CLIError("Unknown command: \(command)\nRun `./tools/p2p-mac-test help` for usage.", exitCode: 2)
        }
    }

    private func runStatus() async throws {
        print("Checking P2P proxy...")
        let status = try await client.proxyStatus()
        print("Proxy: \(status.enabled == false ? "offline" : "online")")
        if let peers = status.activePeers {
            print("Active peers: \(peers)")
        }
        if let state = status.state {
            print("State: \(state)")
        }
        if let detail = status.detail {
            print("Detail: \(detail)")
        }
    }

    private func runBrowse(_ args: [String]) async throws {
        let options = Options(args)
        let limit = options.intValue(for: "--limit") ?? 20
        let shouldProbe = options.has("--probe")
        let shouldJSON = options.has("--json")

        print("Loading P2P channel catalog...")
        let matches = try await client.fetchMatches()
        let sorted = matches
            .sorted { lhs, rhs in
                if lhs.availabilityValue != rhs.availabilityValue {
                    return lhs.availabilityValue > rhs.availabilityValue
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .dedupedByCID()
            .prefix(limit)
            .map { $0 }

        if shouldJSON {
            try printJSON(sorted)
            return
        }

        print("Found \(matches.count) catalog item(s). Showing \(sorted.count).")
        printMatchTable(sorted)

        if shouldProbe {
            try await probeMatches(sorted, watchSeconds: options.doubleValue(for: "--watch") ?? 0, player: options.value(for: "--player"), shouldOpen: options.has("--open"))
        }
    }

    private func runSearch(_ args: [String]) async throws {
        let options = Options(args)
        let queryWords = options.positionals
        guard !queryWords.isEmpty else {
            throw CLIError("Usage: ./tools/p2p-mac-test search \"team or event\" [--limit 10] [--probe]", exitCode: 2)
        }

        let query = queryWords.joined(separator: " ")
        let limit = options.intValue(for: "--limit") ?? 10
        let shouldProbe = options.has("--probe")
        let shouldJSON = options.has("--json")

        print("Searching P2P catalog for: \(query)")
        let matches = try await client.search(query: query)
        let selected = matches
            .dedupedByCID()
            .sorted { lhs, rhs in lhs.availabilityValue > rhs.availabilityValue }
            .prefix(limit)
            .map { $0 }

        if shouldJSON {
            try printJSON(selected)
            return
        }

        print("Found \(matches.count) candidate(s). Showing \(selected.count).")
        printMatchTable(selected)

        if shouldProbe {
            try await probeMatches(selected, watchSeconds: options.doubleValue(for: "--watch") ?? 0, player: options.value(for: "--player"), shouldOpen: options.has("--open"))
        }
    }

    private func runProbe(_ args: [String]) async throws {
        let options = Options(args)
        let streamURL: URL
        let title: String

        if let urlText = options.value(for: "--url"), let url = URL(string: urlText) {
            streamURL = url
            title = options.value(for: "--title") ?? "Manual URL"
        } else if let cid = options.value(for: "--cid") ?? options.positionals.first {
            let candidate = P2PCandidate(cid: cid, title: options.value(for: "--title") ?? cid, availability: 0)
            streamURL = client.streamURL(for: candidate)
            title = candidate.title
        } else {
            throw CLIError("Usage: ./tools/p2p-mac-test probe --cid <acestream-id> [--watch 30] [--open]", exitCode: 2)
        }

        print("Probing: \(title)")
        print("URL: \(redacted(streamURL))")
        let result = try await client.probe(streamURL: streamURL)
        print(result.prettyDescription)

        let watchSeconds = options.doubleValue(for: "--watch") ?? 0
        if watchSeconds > 0, let cid = client.cid(from: streamURL) {
            try await client.watchStatus(cid: cid, seconds: watchSeconds) { snapshot in
                print(snapshot.oneLine)
            }
        }

        if options.has("--open") {
            try open(streamURL, player: options.value(for: "--player"))
        }
    }

    private func probeMatches(_ matches: [ScrapedAceMatch], watchSeconds: Double, player: String?, shouldOpen: Bool) async throws {
        for (index, match) in matches.enumerated() {
            let candidate = P2PCandidate(match: match)
            let streamURL = client.streamURL(for: candidate)
            print("")
            print("[\(index + 1)/\(matches.count)] \(candidate.title)")
            print("CID: \(candidate.cid)")
            let result = try await client.probe(streamURL: streamURL)
            print(result.prettyDescription)

            if watchSeconds > 0 {
                try await client.watchStatus(cid: candidate.cid, seconds: watchSeconds) { snapshot in
                    print(snapshot.oneLine)
                }
            }

            if shouldOpen, result.isPlayable {
                try open(streamURL, player: player)
                break
            }
        }
    }

    private func open(_ url: URL, player: String?) throws {
        var args = [String]()
        if let player, !player.isEmpty, player.lowercased() != "default" {
            args += ["-a", player]
        }
        args.append(url.absoluteString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = args
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Opened stream with \(player ?? "default player").")
        } else {
            throw CLIError("Could not open stream. Try `--player IINA` or `--player VLC`.", exitCode: 1)
        }
    }

    private func printMatchTable(_ matches: [ScrapedAceMatch]) {
        guard !matches.isEmpty else {
            print("No P2P channels found.")
            return
        }

        for (index, match) in matches.enumerated() {
            let availability = match.availability.map { "\(Int($0 * 100))%" } ?? "n/a"
            print(String(format: "%3d. %-6@  %@  %@",
                         index + 1,
                         availability as NSString,
                         String(match.cid.prefix(12)),
                         match.title))
        }
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        print("")
    }

    private func printHelp() {
        print("""
        P2P Mac Tester

        Commands:
          status
              Check the remote P2P proxy health.

          browse [--limit 20] [--probe] [--watch 30] [--open] [--player IINA|VLC|default]
              List catalog channels and optionally probe them.

          search "query" [--limit 10] [--probe] [--watch 30] [--open]
              Search scraper catalog by team, event, or channel name.

          probe --cid <acestream-id> [--title "Label"] [--watch 30] [--open]
              Probe one AceStream/HLS source.

          play --cid <acestream-id> [--player IINA]
              Probe and open one source.

        Examples:
          ./tools/p2p-mac-test status
          ./tools/p2p-mac-test browse --limit 15
          ./tools/p2p-mac-test search "nba" --probe --limit 5
          ./tools/p2p-mac-test probe --cid abc123 --watch 30
          ./tools/p2p-mac-test play --cid abc123 --player IINA
        """)
    }
}

private struct Options {
    let positionals: [String]
    private let values: [String: String]
    private let flags: Set<String>

    init(_ args: [String]) {
        var positionals: [String] = []
        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 0

        while index < args.count {
            let token = args[index]
            if token.hasPrefix("--") {
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    values[token] = args[index + 1]
                    index += 2
                } else {
                    flags.insert(token)
                    index += 1
                }
            } else {
                positionals.append(token)
                index += 1
            }
        }

        self.positionals = positionals
        self.values = values
        self.flags = flags
    }

    func has(_ flag: String) -> Bool {
        flags.contains(flag)
    }

    func value(for key: String) -> String? {
        values[key]
    }

    func intValue(for key: String) -> Int? {
        values[key].flatMap(Int.init)
    }

    func doubleValue(for key: String) -> Double? {
        values[key].flatMap(Double.init)
    }
}

private final class P2PClient {
    private static let serverURL = URL(string: "https://p2p.pixel-invoice.com")!
    private static let scraperURL = URL(string: "https://scraper.pixel-invoice.com")!
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
    private static let p2pReferer = "https://p2p.pixel-invoice.com/"
    private static let hlsAcceptHeader = "application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8"
    private static let minimumSegmentBytes = 512
    private static let readLimitBytes = 4096

    private static let apiPassword = decode([
        0x20, 0x0, 0x0, 0x0, 0x0, 0x1E, 0x1E, 0x53,
        0x1C, 0x26, 0x7, 0xC, 0x0, 0x6, 0x24, 0x57
    ])

    private let discoverySession: URLSession
    private let probeSession: URLSession
    private let statusSession: URLSession

    init() {
        let discoveryConfig = URLSessionConfiguration.default
        discoveryConfig.timeoutIntervalForRequest = 90
        discoveryConfig.timeoutIntervalForResource = 120
        discoveryConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        discoverySession = URLSession(configuration: discoveryConfig)

        let probeConfig = URLSessionConfiguration.ephemeral
        probeConfig.timeoutIntervalForRequest = 50
        probeConfig.timeoutIntervalForResource = 70
        probeConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        probeSession = URLSession(configuration: probeConfig)

        let statusConfig = URLSessionConfiguration.ephemeral
        statusConfig.timeoutIntervalForRequest = 6
        statusConfig.timeoutIntervalForResource = 6
        statusConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        statusSession = URLSession(configuration: statusConfig)
    }

    func proxyStatus() async throws -> ProxyStatusEnvelope {
        var components = URLComponents(url: Self.endpoint(base: Self.serverURL, path: "/proxy/acestream/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_password", value: Self.apiPassword)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(Self.apiPassword)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await statusSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError("Proxy status did not return HTTP.", exitCode: 1)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CLIError("Proxy status HTTP \(http.statusCode): \(body)", exitCode: 1)
        }

        return (try? JSONDecoder.flexible.decode(ProxyStatusEnvelope.self, from: data))
            ?? ProxyStatusEnvelope(enabled: true, activePeers: nil, state: nil, detail: nil)
    }

    func fetchMatches() async throws -> [ScrapedAceMatch] {
        try await fetchMatches(path: "/matches")
    }

    func search(query: String) async throws -> [ScrapedAceMatch] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw CLIError("Could not URL-encode query.", exitCode: 2)
        }
        return try await fetchMatches(path: "/search/\(encoded)")
    }

    func streamURL(for candidate: P2PCandidate) -> URL {
        var components = URLComponents(url: Self.endpoint(base: Self.serverURL, path: "/proxy/acestream/stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: candidate.cid),
            URLQueryItem(name: "api_password", value: Self.apiPassword)
        ]
        return components.url!
    }

    func cid(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" || $0.name == "infohash" })?
            .value
    }

    func probe(streamURL: URL) async throws -> ProbeResult {
        var manifestRequest = URLRequest(url: streamURL)
        manifestRequest.timeoutInterval = 50
        applyPlaybackHeaders(to: &manifestRequest)
        manifestRequest.setValue(Self.hlsAcceptHeader, forHTTPHeaderField: "Accept")

        let started = Date()
        let (manifestData, manifestResponse) = try await probeSession.data(for: manifestRequest)
        let manifestTTFBMs = Int(Date().timeIntervalSince(started) * 1000)
        let manifestHTTP = manifestResponse as? HTTPURLResponse
        let manifestStatus = manifestHTTP?.statusCode ?? -1

        guard (200...299).contains(manifestStatus),
              let manifest = String(data: manifestData, encoding: .utf8),
              manifest.contains("#EXTM3U") else {
            let failure = classifyFailure(statusCode: manifestStatus, data: manifestData)
            return ProbeResult(
                manifestStatusCode: manifestStatus,
                manifestTTFBMs: manifestTTFBMs,
                manifestBytes: manifestData.count,
                segmentStatusCode: nil,
                segmentBytes: 0,
                segmentURL: nil,
                failureClass: failure.failureClass,
                detail: failure.detail,
                activePeers: failure.activePeers
            )
        }

        guard let segmentURL = firstSegmentURL(in: manifest, relativeTo: streamURL) else {
            return ProbeResult(
                manifestStatusCode: manifestStatus,
                manifestTTFBMs: manifestTTFBMs,
                manifestBytes: manifestData.count,
                segmentStatusCode: nil,
                segmentBytes: 0,
                segmentURL: nil,
                failureClass: "manifest empty",
                detail: "Manifest had no segment URL.",
                activePeers: nil
            )
        }

        var segmentRequest = URLRequest(url: segmentURL)
        segmentRequest.timeoutInterval = 50
        applyPlaybackHeaders(to: &segmentRequest)
        segmentRequest.setValue("bytes=0-\(Self.readLimitBytes - 1)", forHTTPHeaderField: "Range")
        segmentRequest.setValue("*/*", forHTTPHeaderField: "Accept")

        let (bytes, segmentResponse) = try await probeSession.bytes(for: segmentRequest)
        let segmentHTTP = segmentResponse as? HTTPURLResponse
        let segmentStatus = segmentHTTP?.statusCode ?? -1
        var segmentData = Data()
        var iterator = bytes.makeAsyncIterator()
        while segmentData.count < Self.readLimitBytes, let byte = try await iterator.next() {
            segmentData.append(byte)
            if segmentData.count >= Self.minimumSegmentBytes {
                break
            }
        }

        if !(200...299).contains(segmentStatus) {
            let failure = classifyFailure(statusCode: segmentStatus, data: segmentData)
            return ProbeResult(
                manifestStatusCode: manifestStatus,
                manifestTTFBMs: manifestTTFBMs,
                manifestBytes: manifestData.count,
                segmentStatusCode: segmentStatus,
                segmentBytes: segmentData.count,
                segmentURL: segmentURL,
                failureClass: failure.failureClass,
                detail: failure.detail,
                activePeers: failure.activePeers
            )
        }

        let playable = segmentData.count >= Self.minimumSegmentBytes
        return ProbeResult(
            manifestStatusCode: manifestStatus,
            manifestTTFBMs: manifestTTFBMs,
            manifestBytes: manifestData.count,
            segmentStatusCode: segmentStatus,
            segmentBytes: segmentData.count,
            segmentURL: segmentURL,
            failureClass: playable ? "ok" : "segment small",
            detail: playable ? nil : "Segment returned \(segmentData.count) bytes.",
            activePeers: nil
        )
    }

    func watchStatus(cid: String, seconds: Double, onSnapshot: (MediaFlowStatus) -> Void) async throws {
        print("Watching status for \(Int(seconds))s...")
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let status = try? await status(cid: cid) {
                onSnapshot(status)
            } else {
                print("status: unavailable")
            }
            try await Task.sleep(for: .seconds(1.5))
        }
    }

    private func status(cid: String) async throws -> MediaFlowStatus {
        var components = URLComponents(url: Self.endpoint(base: Self.serverURL, path: "/proxy/acestream/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: cid),
            URLQueryItem(name: "api_password", value: Self.apiPassword)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 6
        request.setValue("Bearer \(Self.apiPassword)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await statusSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw CLIError("Status request failed.", exitCode: 1)
        }
        return try JSONDecoder.flexible.decode(MediaFlowStatus.self, from: data)
    }

    private func fetchMatches(path: String) async throws -> [ScrapedAceMatch] {
        let url = Self.endpoint(base: Self.scraperURL, path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        request.setValue("Bearer \(Self.apiPassword)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await discoverySession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError("Scraper request did not return HTTP.", exitCode: 1)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CLIError("Scraper HTTP \(http.statusCode): \(body)", exitCode: 1)
        }
        return try JSONDecoder().decode([ScrapedAceMatch].self, from: data)
    }

    private func applyPlaybackHeaders(to request: inout URLRequest) {
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.p2pReferer, forHTTPHeaderField: "Referer")
        request.setValue(Self.apiPassword, forHTTPHeaderField: "api-password")
        request.setValue("Bearer \(Self.apiPassword)", forHTTPHeaderField: "Authorization")
    }

    private static func endpoint(base: URL, path: String) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }

    private func classifyFailure(statusCode: Int, data: Data) -> (failureClass: String, detail: String?, activePeers: Int?) {
        if statusCode == 524 || statusCode == 504 {
            return ("warming", "Searching for peers...", 0)
        }
        if let envelope = try? JSONDecoder().decode(ProxyFailureEnvelope.self, from: data) {
            let fallback = statusCode >= 500 ? "proxy internal error" : "proxy error"
            return (normalizedProxyCode(envelope.code, fallback: fallback), envelope.detail, envelope.activePeers)
        }
        let body = String(data: data.prefix(240), encoding: .utf8)
        return ("http \(statusCode)", body, nil)
    }

    private func normalizedProxyCode(_ code: String?, fallback: String) -> String {
        let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return fallback
        }
        let normalized = raw.lowercased().replacingOccurrences(of: "-", with: "_")
        if normalized.hasPrefix("segment_") {
            return "segment \(normalized.dropFirst("segment_".count))"
        }
        if normalized.hasPrefix("manifest_") {
            return "manifest \(normalized.dropFirst("manifest_".count))"
        }
        return normalized.replacingOccurrences(of: "_", with: " ")
    }

    private func firstSegmentURL(in manifest: String, relativeTo manifestURL: URL) -> URL? {
        for rawLine in manifest.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let url = URL(string: line, relativeTo: manifestURL)?.absoluteURL {
                return url
            }
        }
        return nil
    }

    private static func decode(_ encoded: [UInt8]) -> String {
        let key = Array("FottyAnalyticsV2".utf8)
        let decoded = encoded.enumerated().map { index, byte in byte ^ key[index % key.count] }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }
}

private struct ScrapedAceMatch: Codable {
    let title: String
    let cid: String
    let availability: Double?

    var availabilityValue: Double {
        availability ?? 0
    }
}

private struct P2PCandidate {
    let cid: String
    let title: String
    let availability: Double

    init(cid: String, title: String, availability: Double) {
        self.cid = cid
        self.title = title
        self.availability = availability
    }

    init(match: ScrapedAceMatch) {
        self.cid = match.cid
        self.title = match.title
        self.availability = match.availabilityValue
    }
}

private struct ProbeResult {
    let manifestStatusCode: Int
    let manifestTTFBMs: Int
    let manifestBytes: Int
    let segmentStatusCode: Int?
    let segmentBytes: Int
    let segmentURL: URL?
    let failureClass: String
    let detail: String?
    let activePeers: Int?

    var isPlayable: Bool {
        failureClass == "ok" && segmentBytes >= 512
    }

    var prettyDescription: String {
        var lines = [
            "Manifest: HTTP \(manifestStatusCode), \(manifestBytes) bytes, \(manifestTTFBMs)ms",
            "Result: \(failureClass)"
        ]
        if let segmentStatusCode {
            lines.append("Segment: HTTP \(segmentStatusCode), \(segmentBytes) bytes")
        }
        if let segmentURL {
            lines.append("Segment URL: \(redacted(segmentURL))")
        }
        if let activePeers {
            lines.append("Active peers: \(activePeers)")
        }
        if let detail, !detail.isEmpty {
            lines.append("Detail: \(detail)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct ProxyFailureEnvelope: Decodable {
    let code: String?
    let detail: String?
    let activePeers: Int?

    enum CodingKeys: String, CodingKey {
        case code
        case detail
        case activePeers = "active_peers"
    }
}

private struct ProxyStatusEnvelope: Decodable {
    let enabled: Bool?
    let activePeers: Int?
    let state: String?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case activePeers = "active_peers"
        case state
        case detail
    }
}

private struct MediaFlowStatus: Decodable {
    let state: String
    let peerCount: Int
    let downloadSpeedKbps: Double
    let uploadSpeedKbps: Double
    let bufferSeconds: Double
    let firstSegmentReady: Bool
    let readySegmentCount: Int
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case state
        case status
        case peerCount = "peer_count"
        case altPeerCount = "peerCount"
        case downloadSpeedKbps = "download_speed_kbps"
        case altDownloadSpeedKbps = "downloadSpeedKbps"
        case uploadSpeedKbps = "upload_speed_kbps"
        case altUploadSpeedKbps = "uploadSpeedKbps"
        case bufferSeconds = "buffer_seconds"
        case altBufferSeconds = "bufferSeconds"
        case firstSegmentReady = "first_segment_ready"
        case altFirstSegmentReady = "firstSegmentReady"
        case readySegmentCount = "ready_segment_count"
        case altReadySegmentCount = "readySegmentCount"
        case lastError = "last_error"
        case error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state)
            ?? c.decodeIfPresent(String.self, forKey: .status)
            ?? "unknown"
        peerCount = try c.decodeIfPresent(Int.self, forKey: .peerCount)
            ?? c.decodeIfPresent(Int.self, forKey: .altPeerCount)
            ?? 0
        downloadSpeedKbps = try c.decodeIfPresent(Double.self, forKey: .downloadSpeedKbps)
            ?? c.decodeIfPresent(Double.self, forKey: .altDownloadSpeedKbps)
            ?? 0
        uploadSpeedKbps = try c.decodeIfPresent(Double.self, forKey: .uploadSpeedKbps)
            ?? c.decodeIfPresent(Double.self, forKey: .altUploadSpeedKbps)
            ?? 0
        bufferSeconds = try c.decodeIfPresent(Double.self, forKey: .bufferSeconds)
            ?? c.decodeIfPresent(Double.self, forKey: .altBufferSeconds)
            ?? 0
        firstSegmentReady = try c.decodeIfPresent(Bool.self, forKey: .firstSegmentReady)
            ?? c.decodeIfPresent(Bool.self, forKey: .altFirstSegmentReady)
            ?? false
        readySegmentCount = try c.decodeIfPresent(Int.self, forKey: .readySegmentCount)
            ?? c.decodeIfPresent(Int.self, forKey: .altReadySegmentCount)
            ?? 0
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
            ?? c.decodeIfPresent(String.self, forKey: .error)
    }

    var oneLine: String {
        let errorText = lastError.map { " error=\($0)" } ?? ""
        return String(
            format: "status=%@ peers=%d down=%.0fkbps up=%.0fkbps buffer=%.1fs segments=%d first=%@%@",
            state,
            peerCount,
            downloadSpeedKbps,
            uploadSpeedKbps,
            bufferSeconds,
            readySegmentCount,
            firstSegmentReady ? "yes" : "no",
            errorText
        )
    }
}

private struct CLIError: Error {
    let message: String
    let exitCode: Int

    init(_ message: String, exitCode: Int) {
        self.message = message
        self.exitCode = exitCode
    }
}

private extension JSONDecoder {
    static var flexible: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func redacted(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
        return url.absoluteString
    }

    components.queryItems = queryItems.map { item in
        let sensitiveNames = ["api_password", "password", "token", "authorization", "key"]
        if sensitiveNames.contains(item.name.lowercased()) {
            return URLQueryItem(name: item.name, value: "REDACTED")
        }
        return item
    }
    return components.url?.absoluteString ?? url.absoluteString
}

private extension Array where Element == ScrapedAceMatch {
    func dedupedByCID() -> [ScrapedAceMatch] {
        var seen = Set<String>()
        return filter { match in
            seen.insert(match.cid).inserted
        }
    }
}

private extension FileHandle {
    func writeLine(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            write(data)
        }
    }
}
