import Foundation

/// Reads only the publisher's public calendar and selected same-site player page.
/// No ID guessing, rolling-stream cache, HTML execution, or TLS exceptions.
final class Score808SiteResolver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let listingPage = URL(string: "https://www.score808live.tv/score808-live-football-scores-real-time-match-updates-results/")!
    private static let calendarHost = "core.service.elfsight.com"
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        super.init()
    }

    deinit { session.invalidateAndCancel() }

    func resolve(for request: StreamPlaybackRequest, now: Date = Date()) async throws -> StreamSession? {
        if let association = request.registryMatch {
            guard association.matches(request: request, providerCode: "score808",
                providerEventID: association.broadcast.providerEventID, streamID: association.broadcast.streamID, at: now),
                  association.broadcast.providerEventID == association.broadcast.streamID else { return nil }
        }
        guard let kickoff = request.kickoffDate ?? request.preferredEvent?.kickoffDate,
              Score808LateDiscoveryPolicy.isLookupWindow(kickoffDate: kickoff, category: request.category, at: now)
        else { return nil }

        let listing = try await read(Self.listingPage)
        let listingHTML = String(decoding: listing, as: UTF8.self)
        // A changed/multiple-widget layout needs a reviewed parser, not a scan
        // across unrelated calendars or unlimited network requests.
        let ids = Score808SiteCatalog.widgetIDs(in: listingHTML)
        guard ids.count == 1, let widgetID = ids.first else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = Self.calendarHost
        parts.path = "/p/boot/"
        parts.queryItems = [URLQueryItem(name: "w", value: widgetID),
                            URLQueryItem(name: "page", value: Self.listingPage.absoluteString)]
        guard let configURL = parts.url else { return nil }
        let config = try await read(configURL)
        guard let watchURL = Score808SiteCatalog.matchingWatchPage(
            in: config, widgetID: widgetID, homeTeam: request.homeTeam,
            awayTeam: request.awayTeam, kickoff: kickoff, now: now,
            registeredEventID: request.registryMatch?.broadcast.providerEventID
        ) else { return nil }

        let html: String
        if watchURL == Self.listingPage { html = listingHTML }
        else { html = String(decoding: try await read(watchURL), as: UTF8.self) }
        guard Score808SiteCatalog.playerEvidence(in: html) else { return nil }
        try Task.checkCancellation()
        let session = StreamSession(
            matchID: request.matchID, title: "Score808", playableURL: watchURL,
            streamType: .unknown, providerName: "Score808",
            requiredHeaders: ["Referer": Self.listingPage.absoluteString,
                              "X-Fotty-Web-Embed": "true",
                              "X-Fotty-Nexus-Source": "score808_site"],
            qualityLabel: "Web", validationStatus: .validated,
            diagnosticMetadata: ["manifest_result": "matched_site_player_page",
                                 "segment_result": "awaiting_decoded_web_playback",
                                 "referer": Self.listingPage.absoluteString]
        )
        guard let association = request.registryMatch else { return session }
        guard let binding = StreamEventBinding(request: request, providerCode: "score808",
            providerEventID: association.broadcast.providerEventID, streamID: association.broadcast.streamID,
            manifestRevision: "score808-calendar-v1", verifiedAt: now,
            expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime), at: now) else { return nil }
        return session.recordingEventBinding(binding, for: request, at: now)
    }

    private func read(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard Self.allows(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: self)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url, Self.allows(finalURL),
              (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let limit = 1_048_576
        guard response.expectedContentLength <= Int64(limit) else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            if data.count >= limit { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    static func allows(_ url: URL) -> Bool {
        if Score808SiteCatalog.safeWatchPageURL(url.absoluteString) != nil { return true }
        // Foundation's URL.path may normalize away a directory's trailing slash.
        return url.scheme == "https" && url.host == calendarHost && ["/p/boot", "/p/boot/"].contains(url.path)
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Validate before following a redirect, not after sending to an arbitrary host.
        let allowed = request.url.map(Self.allows) == true
            && request.url?.host == response.url?.host
        completionHandler(allowed ? request : nil)
    }
}

/// Metadata-only batch lane. A calendar listing is not player/stream evidence;
/// Watch still runs Score808SiteResolver's independent fresh player checks.
actor Score808CatalogClient {
    static let shared = Score808CatalogClient()
    typealias Reader = @Sendable (URL) async throws -> Data
    private struct Snapshot {
        let widgetID: String?
        let configuration: Data?
        let unavailable: FixtureSourceCatalogMatch.Outcome?
        let fetchedAt: Date
    }
    private let reader: Reader?
    private let transport: FottyBoundedHTTPClient
    private let cacheTTL: TimeInterval
    private var snapshot: Snapshot?
    private var generation: UUID?

    init(reader: Reader? = nil, cacheTTL: TimeInterval = 120) {
        self.reader = reader
        self.cacheTTL = min(300, max(1, cacheTTL))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false
        transport = FottyBoundedHTTPClient(configuration: configuration)
    }

    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        try Task.checkCancellation()
        guard requests.count <= 256 else { throw CommunitySportsAddonError.invalidResponse }
        let supported: (StreamPlaybackRequest) -> Bool = { request in
            guard request.preferredEvent?.hasCatalogIdentityConflict != true,
                  ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else { return false }
            return Score808LateDiscoveryPolicy.isLookupWindow(kickoffDate: request.kickoffDate,
                category: request.category, at: now)
        }
        let current = requests.contains(where: supported) ? try await loadSnapshot(now: now) : nil
        try Task.checkCancellation()
        return try requests.map { request in
            try Task.checkCancellation()
            if request.preferredEvent?.hasCatalogIdentityConflict == true {
                return .init(matchID: request.matchID, outcome: .conflicting)
            }
            guard supported(request), let current else { return .init(matchID: request.matchID, outcome: .unsupported) }
            if let outcome = current.unavailable { return .init(matchID: request.matchID, outcome: outcome) }
            guard let widget = current.widgetID, let configuration = current.configuration, let kickoff = request.kickoffDate else {
                return .init(matchID: request.matchID, outcome: .needsVerification)
            }
            let listed = Score808SiteCatalog.matchingWatchPage(in: configuration, widgetID: widget,
                homeTeam: request.homeTeam, awayTeam: request.awayTeam, kickoff: kickoff, now: now) != nil
            // The existing optional matcher does not distinguish a missing
            // entry from an ambiguous/invalid one. Never invent absence here.
            return .init(matchID: request.matchID, outcome: listed ? .listed : .needsVerification)
        }
    }

    private func loadSnapshot(now: Date) async throws -> Snapshot {
        if let snapshot, (0..<(snapshot.unavailable == nil ? cacheTTL : 15)).contains(now.timeIntervalSince(snapshot.fetchedAt)) {
            return snapshot
        }
        let token = UUID(); generation = token
        let listing = try await read(Score808SiteResolver.listingPage)
        let widgets = Score808SiteCatalog.widgetIDs(in: String(decoding: listing, as: UTF8.self))
        let candidate: Snapshot
        if widgets.count != 1 || widgets.first == nil {
            candidate = .init(widgetID: nil, configuration: nil,
                unavailable: widgets.count > 1 ? .conflicting : .needsVerification, fetchedAt: now)
        } else {
            let widget = widgets[0]
            var parts = URLComponents()
            parts.scheme = "https"; parts.host = "core.service.elfsight.com"; parts.path = "/p/boot/"
            parts.queryItems = [URLQueryItem(name: "w", value: widget),
                URLQueryItem(name: "page", value: Score808SiteResolver.listingPage.absoluteString)]
            guard let url = parts.url else { throw CommunitySportsAddonError.invalidResponse }
            candidate = .init(widgetID: widget, configuration: try await read(url), unavailable: nil, fetchedAt: now)
        }
        try Task.checkCancellation()
        if generation == token { snapshot = candidate }
        return candidate
    }

    private func read(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard Self.allowsMetadata(url) else { throw URLError(.unsupportedURL) }
        let data: Data
        if let reader { data = try await reader(url) }
        else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")
            let response = try await transport.fetch(request, maximumBytes: Score808SiteCatalog.maximumDocumentBytes,
                deadline: 6, redirectPolicy: { from, to in
                    Self.allowsMetadata(from) && Self.allowsMetadata(to)
                        && from.host == to.host && from.path == to.path && from.query == to.query
                })
            guard let final = response.http.url, Self.allowsMetadata(final), final == url else {
                throw URLError(.badServerResponse)
            }
            data = response.data
        }
        try Task.checkCancellation()
        guard data.count <= Score808SiteCatalog.maximumDocumentBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    nonisolated private static func allowsMetadata(_ url: URL) -> Bool {
        if url == Score808SiteResolver.listingPage { return true }
        guard Score808SiteResolver.allows(url), url.host == "core.service.elfsight.com", url.fragment == nil,
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, query.count == 2,
              query.filter({ $0.name == "page" && $0.value == Score808SiteResolver.listingPage.absoluteString }).count == 1,
              let widget = query.first(where: { $0.name == "w" })?.value else { return false }
        return widget.range(of: #"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"#,
            options: .regularExpression) != nil
    }
}
