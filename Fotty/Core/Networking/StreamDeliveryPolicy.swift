import Foundation

/// Fotty's one stream rule, for every provider. A stream is used when it is
/// safe to open; whether it is the right game is decided by fixture matching,
/// and whether it plays is decided by playback ranking. No host lists, path
/// shapes, stream-name tags, exact header sets or query-name rules.
enum StreamDeliveryPolicy {
    static let maximumURLBytes = 8192
    /// Stops runaway responses only; real games stay far below it.
    static let maximumSessionsPerProvider = 100

    /// nil = safe to play. Reasons are short labels, never a URL.
    nonisolated static func rejection(_ url: URL) -> String? {
        if url.scheme?.lowercased() != "https" { return "not_https" }
        if url.absoluteString.utf8.count > maximumURLBytes { return "too_long" }
        if url.user != nil || url.password != nil { return "credentials_in_link" }
        if !LocalStreamProxyPolicy.allowsDestination(url) { return "unsafe_destination" }
        // A wrapper link (…?url=https://…) is only as safe as the link inside it.
        for inner in innerLinks(url) {
            if inner.scheme?.lowercased() != "https" { return "inner_not_https" }
            if inner.user != nil || inner.password != nil { return "inner_credentials" }
            if !LocalStreamProxyPolicy.allowsDestination(inner) { return "inner_unsafe_destination" }
        }
        return nil
    }

    /// Transport admission is identical for public and configured providers.
    /// The guarded relay verifies actual HLS bytes; URLs cannot prove content.
    nonisolated static func publicRejection(_ url: URL) -> String? {
        rejection(url)
    }

    /// A live HLS playlist, directly or inside a wrapper link.
    nonisolated static func isLivePlaylistLink(_ url: URL) -> Bool {
        ([url] + innerLinks(url)).contains { $0.path.lowercased().hasSuffix(".m3u8") }
    }

    /// Links carried in query values (url=, target=, …), decoded once.
    nonisolated static func innerLinks(_ url: URL) -> [URL] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
            guard !["referer", "referrer", "origin"].contains(item.name.lowercased()),
                  let value = item.value?.trimmingCharacters(in: .whitespaces), value.contains("://"),
                  let inner = URL(string: value), inner.scheme != nil, inner.host != nil else { return nil }
            return inner
        }
    }

    private enum HeaderKey: String, CodingKey { case headers, behaviorHints, proxyHeaders, request, requestHeaders, drm, drmInfo, drmHeaders, clearkey, licenseUrl, license }

    /// Preserve sign-in requirements and conflicting values when reading either
    /// Stremio header location. The caller can reject one malformed stream.
    nonisolated static func decodeRequestHeaders(from decoder: Decoder) throws -> [String: String] {
        let values = try decoder.container(keyedBy: HeaderKey.self)
        var maps: [[String: String]] = []
        if values.contains(.headers), try !values.decodeNil(forKey: .headers) { maps.append(try values.decode([String: String].self, forKey: .headers)) }
        if values.contains(.behaviorHints), try !values.decodeNil(forKey: .behaviorHints) {
            let hints = try values.nestedContainer(keyedBy: HeaderKey.self, forKey: .behaviorHints)
            if hints.contains(.requestHeaders), try !hints.decodeNil(forKey: .requestHeaders) { maps.append(try hints.decode([String: String].self, forKey: .requestHeaders)) }
            if hints.contains(.proxyHeaders), try !hints.decodeNil(forKey: .proxyHeaders) {
                let proxy = try hints.nestedContainer(keyedBy: HeaderKey.self, forKey: .proxyHeaders)
                if proxy.contains(.request), try !proxy.decodeNil(forKey: .request) { maps.append(try proxy.decode([String: String].self, forKey: .request)) }
            }
        }
        var headers: [String: String] = [:]
        for map in maps {
            for (name, value) in map {
                let lower = name.lowercased()
                if let previous = headers[lower], previous != value { throw CommunitySportsAddonError.unsafeResponse }
                headers[lower] = value
            }
        }
        return headers
    }

    /// Optional null/false/empty metadata does not declare DRM. Malformed or
    /// nonempty requirements stay unsupported; no license/access workaround.
    nonisolated static func decodeRequiresDRM(from decoder: Decoder) -> Bool {
        guard let values = try? decoder.container(keyedBy: HeaderKey.self) else { return false }
        for key in [HeaderKey.drm, .drmInfo, .drmHeaders, .clearkey, .licenseUrl, .license] where values.contains(key) {
            if (try? values.decodeNil(forKey: key)) == true { continue }
            if let flag = try? values.decode(Bool.self, forKey: key) { if flag { return true }; continue }
            if let text = try? values.decode(String.self, forKey: key), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if let map = try? values.nestedContainer(keyedBy: AnyKey.self, forKey: key), map.allKeys.isEmpty { continue }
            if let list = try? values.nestedUnkeyedContainer(forKey: key), list.count == 0 { continue }
            return true
        }
        return false
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Provenance is a header value, never a fetch grant. HTTP provenance can
    /// accompany HTTPS media, while private hosts and embedded credentials cannot.
    nonisolated static func allowsProvenance(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.absoluteString.utf8.count <= 512,
              url.port == nil || url.port == 80 || url.port == 443,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        parts.scheme = "https"; parts.port = nil; parts.fragment = nil
        return parts.url.map(LocalStreamProxyPolicy.allowsDestination) == true
    }

    nonisolated static func headerRejection(_ requested: [String: String]) -> String? {
        guard requestHeaders(requested) == nil else { return nil }
        let credentials: Set<String> = ["cookie", "authorization", "proxy-authorization", "x-api-key", "x-auth-token"]
        return requested.keys.contains(where: { credentials.contains($0.lowercased()) }) ? "credential_headers" : "malformed_headers"
    }

    /// Request headers a stream asks for. Referer, Origin and User-Agent are
    /// kept; other harmless names are dropped; a credential header refuses the
    /// stream (nil), because Fotty never forwards sign-in material.
    nonisolated static func requestHeaders(_ requested: [String: String]) -> [String: String]? {
        let canonical = ["referer": "Referer", "origin": "Origin", "user-agent": "User-Agent"]
        let credentials: Set<String> = ["cookie", "authorization", "proxy-authorization", "x-api-key", "x-auth-token"]
        var headers: [String: String] = [:]
        for (name, value) in requested {
            let lower = name.lowercased()
            if credentials.contains(lower) { return nil }
            guard let key = canonical[lower] else { continue }
            guard !value.isEmpty, value.utf8.count <= 512, value.utf8.allSatisfy({ (32...126).contains($0) }),
                  headers[key] == nil || headers[key] == value else { return nil }
            if key != "User-Agent" {
                guard let url = URL(string: value), allowsProvenance(url) else { return nil }
            }
            headers[key] = value
        }
        return headers
    }
}
