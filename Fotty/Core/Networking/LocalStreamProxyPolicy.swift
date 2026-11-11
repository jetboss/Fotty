import Foundation
import Darwin
import CryptoKit

/// Runtime-only authority for one reviewed CS delivery. It is deliberately not
/// Codable: persisted/add-on metadata cannot restore an exceptional port grant.
struct LocalStreamProxyOriginProfile: Sendable, Equatable {
    private static let reviewedManifestURL = URL(string: "https://nuviosports.xyz/manifest.json")!
    // Owner-approved origin observed in the exact CS1 contract on 11 October
    // 2026. A future advertised host is not automatically approved.
    private static let reviewedOriginSHA256 = "6f9cf8e38a18ecd21731b9ed9f6328fc9c97fadb5f7e6c911d88eaa49b2e19ce"
    private let host: String
    private let deliveryBinding: String

    private init(host: String, deliveryBinding: String) {
        self.host = host
        self.deliveryBinding = deliveryBinding
    }

    static func communitySports(deliveryURL: URL, manifestURL: URL,
                                sourceHint: String?, headers: [String: String]) -> Self? {
        guard sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "daddylive",
              LocalStreamProxyPolicy.sameOrigin(manifestURL, reviewedManifestURL),
              manifestURL.path == reviewedManifestURL.path, manifestURL.query == nil,
              manifestURL.fragment == nil, manifestURL.user == nil, manifestURL.password == nil,
              let host = reviewedHost(for: deliveryURL, headers: headers) else { return nil }
        return Self(host: host, deliveryBinding: binding(deliveryURL, headers: headers))
    }

    func validated(for deliveryURL: URL, headers: [String: String]) -> Self? {
        guard Self.reviewedHost(for: deliveryURL, headers: headers) == host,
              Self.binding(deliveryURL, headers: headers) == deliveryBinding else { return nil }
        return self
    }

    func allowsExceptionalDestination(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == host,
              url.port == 8443, Self.originDigest(host) == Self.reviewedOriginSHA256 else { return false }
        // Reuse all default public-host, credential, fragment and scheme rules;
        // replacing the port here is validation only, never a network rewrite.
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.port = 443
        guard let ordinary = parts?.url else { return false }
        return LocalStreamProxyPolicy.allowsDestination(ordinary)
    }

    private static func reviewedHost(for deliveryURL: URL, headers: [String: String]) -> String? {
        guard LocalStreamProxyPolicy.sameOrigin(deliveryURL, reviewedManifestURL),
              LocalStreamProxyPolicy.isCommunitySportsManifestRoute(deliveryURL, manifestURL: reviewedManifestURL),
              deliveryURL.user == nil, deliveryURL.password == nil,
              deliveryURL.fragment == nil, deliveryURL.absoluteString.utf8.count <= 8_192,
              (deliveryURL.query?.utf8.count ?? 0) <= 12 * 1_024,
              Set(headers.keys) == Set(["Referer", "Origin", "User-Agent"]),
              headers.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512
                  && $0.utf8.allSatisfy({ (32...126).contains($0) }) }) else { return nil }
        let query = URLComponents(url: deliveryURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let target = query.filter { $0.name.lowercased() == "url" }
        guard target.count == 1, let rawTarget = target[0].value,
              let upstream = URL(string: rawTarget), upstream.scheme?.lowercased() == "https",
              upstream.port == 8443, upstream.user == nil, upstream.password == nil,
              upstream.fragment == nil, upstream.pathExtension.lowercased() == "m3u8",
              upstream.absoluteString.utf8.count <= 8_192,
              let host = upstream.host?.lowercased(), originDigest(host) == reviewedOriginSHA256 else { return nil }
        var ordinary = URLComponents(url: upstream, resolvingAgainstBaseURL: false)
        ordinary?.port = 443
        guard let ordinaryURL = ordinary?.url, LocalStreamProxyPolicy.allowsDestination(ordinaryURL) else { return nil }
        var provenance: [String: URL] = [:]
        for header in ["Referer", "Origin"] {
            let matching = query.filter { $0.name.lowercased() == header.lowercased() }
            guard matching.count == 1, let value = headers[header], matching[0].value == value,
                  let url = URL(string: value), LocalStreamProxyPolicy.allowsDestination(url),
                  url.query == nil, url.fragment == nil,
                  header != "Origin" || url.path.isEmpty || url.path == "/" else { return nil }
            provenance[header] = url
        }
        guard let referer = provenance["Referer"], let origin = provenance["Origin"],
              LocalStreamProxyPolicy.sameOrigin(referer, origin) else { return nil }
        return host
    }

    private static func originDigest(_ host: String) -> String {
        digest(Data("https|\(host)|8443".utf8))
    }

    private static func binding(_ url: URL, headers: [String: String]) -> String {
        var data = Data()
        func append(_ value: String) {
            data.append(contentsOf: "\(value.utf8.count):".utf8)
            data.append(contentsOf: value.utf8)
        }
        append(url.absoluteString)
        for key in headers.keys.sorted() { append(key); append(headers[key]!) }
        return digest(data)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Runtime-only compatibility for the reviewed CS manifest rewriter. This is
/// not destination authority and deliberately is not Codable. The maintainer
/// randomly rotates equivalent segment wrappers across this exact Worker pool
/// on playlist reloads; Apple's HLS client requires an unchanged overlapping
/// segment URI. Preserve the first already admitted wrapper without changing
/// its tokens or resource bytes when the complete nested delivery is unchanged.
struct LocalStreamProxyPlaylistProfile: Sendable, Equatable {
    private static let reviewedManifestURL = URL(string: "https://nuviosports.xyz/manifest.json")!
    // Reviewed at live-sport-plugin 700fad8343a057797eb37b30709b7be5f6dae599,
    // HlsRewriteService.js. This list does not admit new network destinations.
    private static let segmentWorkerHosts: Set<String> = [
        "nuvio-proxy.odedararaj456.workers.dev",
        "nuvio-proxy2.rajodedara360.workers.dev",
        "nuvio-proxy3.raj-odedara.workers.dev",
        "spring-brook-5c1e.rajodedara456.workers.dev",
        "falling-unit-ffa6.rajcfproxy1.workers.dev",
        "falling-violet-3301.hansabenhodedara.workers.dev",
        "nameless-dawn-2ab8.abhi-munot01.workers.dev"
    ]
    private let deliveryBinding: String
    private let renewsSegmentToken: Bool

    private init(deliveryBinding: String, renewsSegmentToken: Bool = false) {
        self.deliveryBinding = deliveryBinding
        self.renewsSegmentToken = renewsSegmentToken
    }

    static func communitySports(deliveryURL: URL, manifestURL: URL,
                                sourceHint: String?, headers: [String: String]) -> Self? {
        let hint = sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hint == "streamedpk" || hint == "timstreams" || hint == "daddylive",
              LocalStreamProxyPolicy.sameOrigin(manifestURL, reviewedManifestURL),
              manifestURL.path == reviewedManifestURL.path, manifestURL.query == nil,
              manifestURL.fragment == nil, manifestURL.user == nil, manifestURL.password == nil,
              isReviewedDelivery(deliveryURL, headers: headers) else { return nil }
        return Self(deliveryBinding: binding(deliveryURL, headers: headers), renewsSegmentToken: hint == "daddylive")
    }

    func validated(for deliveryURL: URL, headers: [String: String]) -> Self? {
        guard Self.isReviewedDelivery(deliveryURL, headers: headers),
              Self.binding(deliveryURL, headers: headers) == deliveryBinding else { return nil }
        return self
    }

    /// The observed DaddyLive CDN rotates only the authorization token for
    /// identical overlapping MPEG-TS segments. Keep a stable local identity,
    /// but send the latest advertised URL, including its entire token, upstream.
    /// This grants no destination, redirect, header or expired-descriptor access.
    var updatesAdvertisedSegmentURL: Bool { renewsSegmentToken }

    func stableSegmentKey(for url: URL) -> String? {
        if renewsSegmentToken {
            guard LocalStreamProxyPolicy.allowsDestination(url), url.host?.lowercased() == "cdn.hdm1.net",
                  url.pathExtension == "ts", url.absoluteString.utf8.count <= 8_192,
                  var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = parts.queryItems, items.count == 1, items[0].name == "token",
                  let token = items[0].value, !token.isEmpty else { return nil }
            parts.query = nil
            guard let identity = parts.string else { return nil }
            return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        // For the older Worker wrapper profile the entire encoded query,
        // including inner signatures and provenance, remains the identity.
        guard LocalStreamProxyPolicy.allowsDestination(url), url.path == "/",
              url.absoluteString.utf8.count <= 8_192,
              let host = url.host?.lowercased(), Self.segmentWorkerHosts.contains(host),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = parts.percentEncodedQuery else { return nil }
        let items = parts.queryItems ?? []
        guard items.count == 3, Set(items.map(\.name)) == Set(["url", "referer", "origin"]),
              items.allSatisfy({ !($0.value?.isEmpty ?? true) }),
              let target = items.first(where: { $0.name == "url" })?.value,
              let inner = URL(string: target), LocalStreamProxyPolicy.allowsDestination(inner),
              inner.absoluteString.utf8.count <= 8_192,
              let innerHost = inner.host?.lowercased() else { return nil }
        let isStreamedHost = innerHost == "strmd.st" || innerHost.hasSuffix(".strmd.st")
        // The reviewed rewriter also rotates .image wrappers for this exact
        // TikTok CDN host (observed in a fresh streamedpk delivery). Treat only
        // that host as equivalent; this is not a wildcard CDN/network grant.
        let isImageHost = isStreamedHost || innerHost == "streamed.pk" || innerHost.hasSuffix(".streamed.pk")
            || innerHost == "p16-common-sign.tiktokcdn.com"
        let suffix = inner.pathExtension.lowercased()
        guard suffix == "ts" && isStreamedHost || suffix == "image" && isImageHost else { return nil }
        for name in ["referer", "origin"] {
            guard let value = items.first(where: { $0.name == name })?.value,
                  let provenance = URL(string: value), LocalStreamProxyPolicy.allowsDestination(provenance),
                  name != "origin" || (provenance.path.isEmpty || provenance.path == "/") && provenance.query == nil else { return nil }
        }
        return SHA256.hash(data: Data(query.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isReviewedDelivery(_ url: URL, headers: [String: String]) -> Bool {
        guard LocalStreamProxyPolicy.allowsDestination(url),
              LocalStreamProxyPolicy.isCommunitySportsManifestRoute(url, manifestURL: reviewedManifestURL),
              url.absoluteString.utf8.count <= 8_192,
              Set(headers.keys).isSubset(of: Set(["Referer", "Origin", "User-Agent"])),
              headers.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512
                  && $0.utf8.allSatisfy({ (32...126).contains($0) }) }) else { return false }
        let targets = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { $0.name == "url" }
        guard targets.count == 1, let raw = targets[0].value, let target = URL(string: raw),
              LocalStreamProxyPolicy.allowsDestination(target), target.pathExtension.lowercased() == "m3u8",
              target.absoluteString.utf8.count <= 8_192 else { return false }
        return true
    }

    private static func binding(_ url: URL, headers: [String: String]) -> String {
        var data = Data()
        func append(_ value: String) {
            data.append(contentsOf: "\(value.utf8.count):".utf8)
            data.append(contentsOf: value.utf8)
        }
        append(url.absoluteString)
        for key in headers.keys.sorted() { append(key); append(headers[key]!) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Admission and credential rules for one selected media item. Only the app can
/// register the first URL; subsequent URLs must come from an admitted manifest
/// or an explicitly checked redirect. Local clients never supply destinations.
struct LocalStreamProxyPolicy {
    struct Limits {
        var requestHeaderBytes = 16 * 1024
        var manifestBytes = 1 * 1024 * 1024
        var resourceBytes = 128 * 1024 * 1024
        var registeredURLs = 4_096
        var urlBytes = 8_192
        var connections = 12
        var redirects = 5
        var headerSeconds: TimeInterval = 5
        var requestSeconds: TimeInterval = 30
        var resourceSeconds: TimeInterval = 150
    }

    enum Failure: Error { case destination, manifest, capacity, revoked }

    private struct Entry { var url: URL; var lastUse: UInt64; var stableSegmentKey: String? = nil }
    let selectedMediaURL: URL
    let capability: String
    let limits: Limits
    private let originProfile: LocalStreamProxyOriginProfile?
    private let playlistProfile: LocalStreamProxyPlaylistProfile?
    private(set) var isRevoked = false
    private var entries: [String: Entry] = [:]
    private var identifiers: [URL: String] = [:]
    private var stableSegmentAliases: [String: String] = [:]
    private var sequence: UInt64 = 0
    private var selectedIdentifier: String?
    private var protectedURLs: Set<URL> = []

    init(selectedMediaURL: URL, limits: Limits = Limits(),
         originProfile: LocalStreamProxyOriginProfile? = nil, requestHeaders: [String: String] = [:],
         playlistProfile: LocalStreamProxyPlaylistProfile? = nil) {
        self.selectedMediaURL = selectedMediaURL
        self.limits = limits
        self.originProfile = originProfile?.validated(for: selectedMediaURL, headers: requestHeaders)
        self.playlistProfile = playlistProfile?.validated(for: selectedMediaURL, headers: requestHeaders)
        capability = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if admitsDestination(selectedMediaURL), selectedMediaURL.absoluteString.utf8.count <= limits.urlBytes {
            selectedIdentifier = try? register(selectedMediaURL)
        }
    }

    var isValid: Bool { selectedIdentifier != nil && !isRevoked }
    var registeredURLCount: Int { entries.count }
    var stableSegmentAliasCount: Int { stableSegmentAliases.count }
    var pingPath: String { "/\(capability)/ping" }

    func playbackURL(port: UInt16) -> URL? {
        guard !isRevoked, let selectedIdentifier else { return nil }
        return localURL(identifier: selectedIdentifier, port: port)
    }

    mutating func revoke() {
        isRevoked = true
        entries.removeAll()
        identifiers.removeAll()
        stableSegmentAliases.removeAll()
    }

    mutating func destination(for path: String) -> URL? {
        guard !isRevoked, path.hasPrefix("/\(capability)/media/") else { return nil }
        let identifier = String(path.dropFirst("/\(capability)/media/".count))
        guard var entry = entries[identifier] else { return nil }
        sequence &+= 1
        entry.lastUse = sequence
        entries[identifier] = entry
        return entry.url
    }

    func contains(_ url: URL) -> Bool { !isRevoked && identifiers[url] != nil }

    /// Called only after the redirect destination passes transport validation.
    mutating func admitRedirect(from source: URL, to destination: URL) throws {
        guard contains(source) else { throw Failure.destination }
        _ = try register(destination)
    }

    mutating func rewriteManifest(_ manifest: String, relativeTo baseURL: URL, port: UInt16) throws -> String {
        guard contains(baseURL), manifest.utf8.count <= limits.manifestBytes,
              manifest.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
        else { throw Failure.manifest }
        // Commit admission only after every reference has passed policy. An
        // invalid reference must never escape unchanged to AVPlayer.
        var updated = self
        updated.protectedURLs = [baseURL]
        let usesCRLF = manifest.contains("\r\n")
        let lines = manifest.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var followsMediaDuration = false
        let rewritten = try lines.map { line -> String in
            var result = line
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                let mediaSegment = followsMediaDuration
                followsMediaDuration = false
                return try updated.registerReference(trimmed, relativeTo: baseURL, port: port, mediaSegment: mediaSegment)
            }
            if trimmed.hasPrefix("#EXTINF:") { followsMediaDuration = true }
            // Parse comma-separated attributes outside quoted values. A regex
            // matching URI= inside another attribute's text can corrupt metadata.
            guard trimmed.hasPrefix("#EXT-X-"), let colon = line.firstIndex(of: ":") else { return result }
            var start = line.index(after: colon)
            var quoted = false
            var attributes: [Range<String.Index>] = []
            for index in line[start...].indices {
                if line[index] == "\"" { quoted.toggle() }
                if line[index] == ",", !quoted {
                    attributes.append(start..<index)
                    start = line.index(after: index)
                }
            }
            guard !quoted else { throw Failure.manifest }
            attributes.append(start..<line.endIndex)
            for attribute in attributes.reversed() {
                guard let equal = line[attribute].firstIndex(of: "=") else { continue }
                let name = line[attribute.lowerBound..<equal].trimmingCharacters(in: .whitespaces).uppercased()
                guard name == "URI" || name.hasSuffix("-URI") else { continue }
                let valueStart = line.index(after: equal)
                guard valueStart < attribute.upperBound, line[valueStart] == "\"",
                      line[line.index(before: attribute.upperBound)] == "\"" else { throw Failure.manifest }
                let range = line.index(after: valueStart)..<line.index(before: attribute.upperBound)
                guard !line[range].contains("\"") else { throw Failure.manifest }
                let value = try updated.registerReference(String(result[range]), relativeTo: baseURL, port: port)
                result.replaceSubrange(range, with: value)
            }
            return result
        }.joined(separator: "\n")
        // The local URL is longer than a short relative URI; bound that expansion too.
        guard rewritten.utf8.count <= limits.manifestBytes * 2 else { throw Failure.capacity }
        updated.protectedURLs.removeAll()
        self = updated
        return usesCRLF ? rewritten.replacingOccurrences(of: "\n", with: "\r\n") : rewritten
    }

    private mutating func registerReference(_ reference: String, relativeTo base: URL, port: UInt16, mediaSegment: Bool = false) throws -> String {
        guard !reference.isEmpty, !reference.contains("{$"),
              let url = URL(string: reference, relativeTo: base)?.absoluteURL else { throw Failure.manifest }
        // Admission remains unchanged even if an existing alias is found. An
        // alias grants no permission to an unsafe or oversized new reference.
        guard admitsDestination(url), url.absoluteString.utf8.count <= limits.urlBytes else { throw Failure.destination }
        let renewsToken = playlistProfile?.updatesAdvertisedSegmentURL == true
        let rawKey = !renewsToken || mediaSegment ? playlistProfile?.stableSegmentKey(for: url) : nil
        // Each playlist owns its aliases; another rendition cannot rebind them.
        let stableKey = rawKey.map { renewsToken ? base.absoluteString + "|" + $0 : $0 }
        if let stableKey, let identifier = stableSegmentAliases[stableKey], var entry = entries[identifier] {
            sequence &+= 1
            entry.lastUse = sequence
            if renewsToken, entry.url != url {
                if identifiers[entry.url] == identifier { identifiers[entry.url] = nil }
                entry.url = url
                identifiers[url] = identifier
            }
            entries[identifier] = entry
            protectedURLs.insert(entry.url)
            return localURL(identifier: identifier, port: port).absoluteString
        }
        let identifier = try register(url, forceNew: renewsToken && stableKey != nil)
        if let stableKey {
            stableSegmentAliases[stableKey] = identifier
            entries[identifier]?.stableSegmentKey = stableKey
        }
        protectedURLs.insert(url)
        return localURL(identifier: identifier, port: port).absoluteString
    }

    private mutating func register(_ url: URL, forceNew: Bool = false) throws -> String {
        guard !isRevoked else { throw Failure.revoked }
        guard admitsDestination(url), url.absoluteString.utf8.count <= limits.urlBytes else { throw Failure.destination }
        sequence &+= 1
        if !forceNew, let identifier = identifiers[url] {
            entries[identifier]?.lastUse = sequence
            return identifier
        }
        guard limits.registeredURLs > 1 else { throw Failure.capacity }
        if entries.count >= limits.registeredURLs {
            guard let oldest = entries.filter({ $0.key != selectedIdentifier && !protectedURLs.contains($0.value.url) })
                .min(by: { $0.value.lastUse < $1.value.lastUse }) else {
                throw Failure.capacity
            }
            if let alias = oldest.value.stableSegmentKey, stableSegmentAliases[alias] == oldest.key {
                stableSegmentAliases[alias] = nil
            }
            if identifiers[oldest.value.url] == oldest.key { identifiers[oldest.value.url] = nil }
            entries[oldest.key] = nil
        }
        let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        entries[identifier] = Entry(url: url, lastUse: sequence)
        identifiers[url] = identifier
        return identifier
    }

    private func localURL(identifier: String, port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(capability)/media/\(identifier)")!
    }

    static func allowsDestination(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443,
              let rawHost = url.host?.lowercased(), !rawHost.contains("%") else { return false }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let isPublic = publicIPAddress(host) { return isPublic }
        // Reject legacy numeric IPv4 spellings and local/search-domain names.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.allSatisfy({ UInt64($0) != nil || $0.hasPrefix("0x") && UInt64($0.dropFirst(2), radix: 16) != nil }) {
            return false
        }
        guard labels.count >= 2, host.utf8.count <= 253,
              let suffix = labels.last, suffix.contains(where: { $0.isASCII && $0.isLetter }),
              !["localhost", "local", "internal", "intranet", "lan", "home", "test", "invalid", "onion"].contains(String(suffix))
        else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// The reviewed add-on now publishes its same manifest handler with an HLS
    /// suffix (upstream db40402). Recognize only those two literal routes; never
    /// normalize a signed query or let an alias skip wrapped-target validation.
    static func isCommunitySportsManifestRoute(_ url: URL, manifestURL: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", sameOrigin(url, manifestURL),
              url.user == nil, url.password == nil, url.fragment == nil,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              let original = URLComponents(url: manifestURL.deletingLastPathComponent()
                .appendingPathComponent("api").appendingPathComponent("manifest"),
                resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
        return path == original || path == original + ".m3u8"
    }

    func admitsDestination(_ url: URL) -> Bool {
        Self.allowsDestination(url) || originProfile?.allowsExceptionalDestination(url) == true
    }

    /// nil means a DNS name; false includes non-global/special-use addresses.
    static func publicIPAddress(_ host: String) -> Bool? {
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            let bytes = withUnsafeBytes(of: v4.s_addr) { Array($0) }
            let a = Int(bytes[0]), b = Int(bytes[1]), c = Int(bytes[2])
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a == 169 && b == 254 || a == 172 && (16...31).contains(b) { return false }
            if a == 192 && (b == 168 || b == 0 && (c == 0 || c == 2) || b == 88 && c == 99) { return false }
            if a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) { return false }
            if a == 203 && b == 0 && c == 113 { return false }
            return true
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            let b = withUnsafeBytes(of: v6) { Array($0) }
            guard b[0] & 0xe0 == 0x20 else { return false } // global unicast only
            if b[0] == 0x20 && b[1] == 0x01 && (b[2] < 2 || b[2] == 0x0d && b[3] == 0xb8) { return false }
            if b[0] == 0x20 && b[1] == 0x02 { return false } // 6to4 embeds an IPv4 destination
            if b[0] == 0x3f && b[1] == 0xff && b[2] & 0xf0 == 0 { return false }
            return true
        }
        return nil
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? 443) == (rhs.port ?? 443)
    }

    static func cookie(_ cookie: HTTPCookie, matches url: URL, now: Date = Date()) -> Bool {
        guard let host = url.host?.lowercased(),
              !cookie.isSecure || url.scheme?.lowercased() == "https",
              cookie.expiresDate.map({ $0 > now }) ?? true else { return false }
        let rawDomain = cookie.domain.lowercased()
        let domain = rawDomain.hasPrefix(".") ? String(rawDomain.dropFirst()) : rawDomain
        guard domain.contains("."), !domain.hasSuffix("."),
              host == domain || rawDomain.hasPrefix(".") && host.hasSuffix(".\(domain)") else { return false }
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        let requestPath = encodedPath.isEmpty ? "/" : encodedPath
        guard cookiePath.hasPrefix("/"), requestPath == cookiePath
                || requestPath.hasPrefix(cookiePath) && (cookiePath.hasSuffix("/") || requestPath.dropFirst(cookiePath.count).first == "/")
        else { return false }
        return !cookie.name.contains(where: { $0.isNewline || $0 == ";" })
            && !cookie.value.contains(where: { $0.isNewline || $0 == ";" })
    }

    static func remoteRequest(url: URL, selectedMediaURL: URL, method: String,
                              capturedHeaders: [String: String], cookies: [HTTPCookie],
                              clientHeaders: [String: String], timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        let sameOrigin = sameOrigin(url, selectedMediaURL)
        // Playlist rewriting changes byte offsets and representation identity.
        // A player's 0-1 probe must fetch the complete known playlist, not an
        // upstream slice or 304 validated against a different representation.
        let requestsWholeManifest = url.pathExtension.lowercased() == "m3u8"
        let representationHeaders: Set<String> = ["range", "if-range", "if-modified-since", "if-none-match", "if-match", "if-unmodified-since"]
        let shareable: Set<String> = ["referer", "origin", "user-agent", "accept", "accept-language"]
        let forbidden: Set<String> = ["host", "cookie", "cookie2", "proxy-authorization", "connection", "content-length", "transfer-encoding", "upgrade", "te", "trailer", "accept-encoding"]
        for (key, value) in capturedHeaders {
            let name = key.lowercased()
            guard !forbidden.contains(name), !name.hasPrefix("x-fotty-"),
                  !requestsWholeManifest || !representationHeaders.contains(name),
                  !name.hasPrefix("proxy-"), !name.hasPrefix("sec-"),
                  sameOrigin || shareable.contains(name),
                  key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !value.contains(where: { $0.asciiValue.map({ $0 < 32 || $0 == 127 }) ?? false }) else { continue }
            if name == "referer" || name == "origin" {
                guard let provenance = URL(string: value), allowsDestination(provenance) else { continue }
                var parts = URLComponents(url: provenance, resolvingAgainstBaseURL: false)
                parts?.fragment = nil
                if name == "origin" { parts?.path = ""; parts?.query = nil }
                if !sameOrigin { parts?.query = nil }
                request.setValue(parts?.url?.absoluteString, forHTTPHeaderField: key)
            } else {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        // Only cookies that belonged to the selected media item enter this
        // session. Re-check their real scope and expiry on every request/hop.
        let scoped = cookies.filter { cookie($0, matches: selectedMediaURL) && cookie($0, matches: url) }
            .sorted { $0.path.count > $1.path.count }
        if !scoped.isEmpty {
            request.setValue(scoped.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        for name in ["range", "if-modified-since", "if-none-match", "if-range"] where !requestsWholeManifest {
            if let value = clientHeaders[name], !value.contains(where: { $0.isNewline }) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
}

/// URLSession resolves again at connection time; this fail-closed DNS preflight
/// rejects private/mixed answers but is not an address-pinned egress transport.
enum LocalStreamProxyDestinationValidator {
    typealias Resolver = @Sendable (String) async throws -> [String]

    static func validate(_ url: URL, originProfile: LocalStreamProxyOriginProfile? = nil,
                         resolver: Resolver = { try await resolve($0) }) async throws {
        try Task.checkCancellation()
        guard LocalStreamProxyPolicy.allowsDestination(url)
                || originProfile?.allowsExceptionalDestination(url) == true,
              let rawHost = url.host else { throw URLError(.unsupportedURL) }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if LocalStreamProxyPolicy.publicIPAddress(host) == true { return }
        let addresses = try await resolver(host)
        try Task.checkCancellation()
        guard !addresses.isEmpty, addresses.allSatisfy({ LocalStreamProxyPolicy.publicIPAddress($0) == true }) else {
            throw URLError(.cannotFindHost)
        }
    }

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.fotty.proxy.dns"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    private static let lock = NSLock()
    private static var pending = 0

    static func resolve(_ host: String) async throws -> [String] {
        let result = LocalStreamProxyCompletion<[String]>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                result.install(continuation)
                lock.lock()
                let admitted = pending < 24
                if admitted { pending += 1 }
                lock.unlock()
                guard admitted else { result.finish(.failure(URLError(.resourceUnavailable))); return }
                queue.addOperation {
                    defer { lock.lock(); pending -= 1; lock.unlock() }
                    guard !result.isFinished else { return }
                    var hints = addrinfo()
                    hints.ai_family = AF_UNSPEC
                    hints.ai_socktype = SOCK_STREAM
                    var list: UnsafeMutablePointer<addrinfo>?
                    guard getaddrinfo(host, "443", &hints, &list) == 0, let first = list else {
                        result.finish(.failure(URLError(.cannotFindHost))); return
                    }
                    defer { freeaddrinfo(first) }
                    var addresses: [String] = []
                    var cursor: UnsafeMutablePointer<addrinfo>? = first
                    while let entry = cursor, addresses.count < 64 {
                        var address = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &address,
                                       socklen_t(address.count), nil, 0, NI_NUMERICHOST) == 0 {
                            addresses.append(String(cString: address))
                        }
                        cursor = entry.pointee.ai_next
                    }
                    guard cursor == nil else { result.finish(.failure(URLError(.cannotFindHost))); return }
                    result.finish(.success(addresses))
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                    result.finish(.failure(URLError(.timedOut)))
                }
            }
        } onCancel: { result.finish(.failure(CancellationError())) }
    }
}

/// A continuation may race stop, task cancellation, a deadline and a callback.
final class LocalStreamProxyCompletion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
