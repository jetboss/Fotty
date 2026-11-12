import Foundation

/// PenguPlay Live TV through the owner's own configured add-on link. The link
/// stays in the device Keychain; neither the cloud registry nor another source
/// receives it. Catalog rows are public; streams require the owner's sign-in.
actor PenguPlaySportsAddonClient {
    static let shared = PenguPlaySportsAddonClient()
    static let providerCode = "penguplay"
    static let manifestIdentity = "com.penguplay"
    typealias Configuration = @Sendable () async throws -> URL?
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias Enabled = @Sendable () async -> Bool
    typealias Current = @Sendable (StreamPlaybackRequest) async -> StreamPlaybackRequest?
    private let configuration: Configuration
    private let fetch: Fetch
    private let enabled: Enabled
    private let current: Current
    private let validate: @Sendable (URL) async throws -> Void

    struct Row: Decodable, Equatable, Sendable {
        let id, type, name, released: String
        let genres: [String]
        enum CodingKeys: String, CodingKey { case id, type, name, released, genres }
        init(id: String, type: String = "tv", name: String, released: String, genres: [String] = []) {
            self.id = id; self.type = type; self.name = name; self.released = released; self.genres = genres
        }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            id = (try? c?.decode(String.self, forKey: .id)) ?? ""
            type = (try? c?.decode(String.self, forKey: .type)) ?? ""
            name = (try? c?.decode(String.self, forKey: .name)) ?? ""
            released = (try? c?.decode(String.self, forKey: .released)) ?? ""
            genres = (try? c?.decode([String].self, forKey: .genres)) ?? []
        }
    }
    private struct Catalog: Decodable { let metas: [Row] }
    struct Manifest: Decodable {
        struct Resource: Decodable {
            let name: String; let types: [String]; let idPrefixes: [String]?
            init(from decoder: Decoder) throws {
                // Stremio allows a bare resource name or an object.
                if let name = try? decoder.singleValueContainer().decode(String.self) {
                    self.name = name; types = []; idPrefixes = nil; return
                }
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                types = (try? c.decode([String].self, forKey: .types)) ?? []
                idPrefixes = try? c.decode([String].self, forKey: .idPrefixes)
            }
            enum CodingKeys: String, CodingKey { case name, types, idPrefixes }
        }
        struct Catalog: Decodable { let id: String; let type: String }
        let id: String; let version: String; let resources: [Resource]; let catalogs: [Catalog]
    }
    struct Delivery: Decodable, Sendable {
        struct Hints: Decodable, Sendable {
            struct Proxy: Decodable, Sendable { let request: [String: String]?; let response: [String: String]? }
            let proxyHeaders: Proxy?
        }
        let url: String?
        let title: String?
        let behaviorHints: Hints?
    }
    private struct Streams: Decodable { let streams: [Delivery] }

    init(configuration: Configuration? = nil, fetch: Fetch? = nil, enabled: Enabled? = nil,
         current: Current? = nil, validate: (@Sendable (URL) async throws -> Void)? = nil) {
        self.configuration = configuration ?? { try await MainActor.run { try AccountSourceSetupStore().savedLink(for: .penguPlay) } }
        self.enabled = enabled ?? { await StreamPluginRegistry.shared.enabledProviderCodes().contains(Self.providerCode) }
        self.current = current ?? { request in await MainActor.run {
            RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: MatchListViewModel.shared.playbackAdmissionCatalog)
        } }
        self.validate = validate ?? { try await LocalStreamProxyDestinationValidator.validate($0) }
        if let fetch { self.fetch = fetch } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
            config.waitsForConnectivity = false
            let transport = FottyBoundedHTTPClient(configuration: config)
            self.fetch = { request in
                let result = try await transport.fetch(request, maximumBytes: 512 * 1024, deadline: 8,
                                                       acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
                return (result.data, result.http)
            }
        }
    }

    /// Sports Fotty's own schedules cover, so a fixture can be matched exactly.
    nonisolated static let supportedSports: Set<String> = ["football", "cricket", "basketball", "baseball", "hockey", "american-football"]

    nonisolated static func supports(category: String) -> Bool {
        supportedSports.contains(ReviewedSportsFixtureMatcher.sportKey(category))
    }

    /// PenguPlay's Live TV catalogs: `pp-live-football`, `pp-live-american_football`…
    nonisolated static func catalogID(forSport sport: String) -> String {
        "pp-live-" + ReviewedSportsFixtureMatcher.sportKey(sport).replacingOccurrences(of: "-", with: "_")
    }

    nonisolated static func encodedComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }

    /// Live TV must be switched on in the owner's configuration.
    nonisolated static func hasLiveTV(_ manifest: Manifest) -> Bool {
        manifest.id == manifestIdentity
            && manifest.resources.contains { $0.name == "stream" && $0.types.contains("tv") && $0.idPrefixes?.contains("pp-live:") == true }
            && manifest.resources.contains { $0.name == "catalog" }
            && manifest.catalogs.contains { catalog in
                catalog.type == "tv" && supportedSports.contains { catalogID(forSport: $0) == catalog.id }
            }
    }

    /// PenguPlay's placeholder when the configured link lacks a valid sign-in.
    nonisolated static func isSignInPlaceholder(_ delivery: Delivery) -> Bool {
        (delivery.title ?? "").localizedCaseInsensitiveContains("sign in")
    }

    /// Checks the owner's link before saving: Live TV is on and the sign-in is
    /// accepted (one live item's stream list is not the sign-in placeholder).
    /// Fetches no media and never logs a credential-bearing URL.
    nonisolated static func validateConfiguration(_ url: URL) async throws {
        do {
            guard try AccountSourceSetup.penguPlay.validatedLink(url.absoluteString) == url, url.query == nil else {
                throw AccountSourceSetupError.accessUnavailable
            }
            try await LocalStreamProxyDestinationValidator.validate(url)
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
            let client = FottyBoundedHTTPClient(configuration: config)
            func get<T: Decodable>(_ target: URL, _ type: T.Type) async throws -> T {
                var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let response = try await client.fetch(request, maximumBytes: 512 * 1024, deadline: 8,
                    acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
                guard response.http.mimeType == "application/json" else { throw AccountSourceSetupError.accessUnavailable }
                return try JSONDecoder().decode(T.self, from: response.data)
            }
            let manifest = try await get(url, Manifest.self)
            guard hasLiveTV(manifest) else { throw AccountSourceSetupError.accessUnavailable }
            let root = url.deletingLastPathComponent().absoluteString
            guard let nowURL = URL(string: root + "catalog/tv/pp-live-now.json") else { throw AccountSourceSetupError.accessUnavailable }
            let listing = try await get(nowURL, Catalog.self)
            if let first = listing.metas.first(where: { $0.id.hasPrefix("pp-live:") }),
               let streamURL = URL(string: root + "stream/tv/" + encodedComponent(first.id) + ".json") {
                let streams = try await get(streamURL, Streams.self)
                guard !streams.streams.contains(where: isSignInPlaceholder) else { throw AccountSourceSetupError.accessUnavailable }
            }
            try Task.checkCancellation()
        } catch is CancellationError { throw CancellationError() }
        catch { throw AccountSourceSetupError.accessUnavailable }
    }

    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        let configured = try await configuration() != nil
        return requests.map { .init(matchID: $0.matchID,
            outcome: configured && Self.supports(category: $0.category) ? .needsVerification : .unsupported) }
    }

    func resolve(for request: StreamPlaybackRequest, now: Date = Date()) async throws -> [StreamSession] {
        let startedClock = Date()
        guard Self.supports(category: request.category), request.registryMatch == nil,
              let original = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              await enabled(), let manifestURL = try await configuration(), manifestURL.query == nil,
              (try? AccountSourceSetup.penguPlay.validatedLink(manifestURL.absoluteString)) == manifestURL,
              let initial = await current(request), Self.sameFixture(initial, request) else {
            throw CommunitySportsAddonError.matchNotFound
        }
        let manifest: Manifest = try await read(manifestURL)
        let catalogID = Self.catalogID(forSport: original.sport)
        guard Self.hasLiveTV(manifest), manifest.catalogs.contains(where: { $0.id == catalogID && $0.type == "tv" }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        let root = manifestURL.deletingLastPathComponent().absoluteString
        var rows: [Row] = []
        for term in Set([request.homeTeam, request.awayTeam]).sorted() where !term.isEmpty {
            guard let url = URL(string: root + "catalog/tv/" + catalogID + "/search=" + Self.encodedComponent(term) + ".json") else {
                throw CommunitySportsAddonError.unsafeResponse
            }
            let page: Catalog = try await read(url)
            guard page.metas.count <= 200, rows.count + page.metas.count <= 400 else { throw CommunitySportsAddonError.unsafeResponse }
            rows += page.metas
        }
        let selected = try Self.select(request: request, rows: rows, now: now)
        guard let streamURL = URL(string: root + "stream/tv/" + Self.encodedComponent(selected.id) + ".json") else {
            throw CommunitySportsAddonError.unsafeResponse
        }
        let streams: Streams = try await read(streamURL)
        guard streams.streams.count <= 40 else { throw CommunitySportsAddonError.unsafeResponse }
        guard !streams.streams.contains(where: Self.isSignInPlaceholder) else {
            throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: streams.streams.count)
        }
        let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(startedClock)))
        guard await enabled(), try await configuration() == manifestURL,
              let latest = await current(request), Self.sameFixture(latest, request),
              (try? Self.select(request: latest, rows: [selected], now: completedAt)) != nil else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        var sessions: [StreamSession] = [], seen: Set<URL> = []
        var rejected = 0
        for row in streams.streams {
            guard let value = row.url, let url = URL(string: value), Self.admitsDelivery(url),
                  let headers = Self.requestHeaders(row), seen.insert(url).inserted else { rejected += 1; continue }
            do { try await validate(url) }
            catch is CancellationError { throw CancellationError() }
            catch { rejected += 1; continue } // One rejected route must not erase valid siblings.
            guard let binding = StreamEventBinding(request: latest, providerCode: Self.providerCode,
                providerEventID: selected.id, streamID: selected.id, resourceType: "tv", manifestRevision: manifest.version,
                verifiedAt: completedAt, expiresAt: completedAt.addingTimeInterval(90), at: completedAt) else {
                throw CommunitySportsAddonError.conflictingMatch
            }
            sessions.append(StreamSession(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: "PP\(sessions.count + 1)", requiredHeaders: headers, qualityLabel: nil,
                expiryTime: binding.expiresAt, canRefresh: true,
                diagnosticMetadata: ["source_family": Self.providerCode, "delivery": "penguplay_hls",
                    "source_key": HighflySportsAddonClient.stableChoiceKey(url), "source_key_scope": "upstream"],
                createdAt: completedAt, requiresGuardedRelay: true, eventBinding: binding))
            if sessions.count == 6 { break }
        }
        // Shape-only receipt so admission rules can be reviewed: counts, never URLs.
        FottyQualityStore.shared.record(category: .playback, name: "penguplay_delivery_admission", outcome: sessions.isEmpty ? .failure : .info,
            details: ["entries": "\(streams.streams.count)", "admitted": "\(sessions.count)", "rejected": "\(rejected)"])
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: streams.streams.count) }
        try Task.checkCancellation()
        guard await enabled(), try await configuration() == manifestURL,
              let final = await current(request), Self.sameFixture(final, latest) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        return sessions
    }

    /// Secure HLS only, through the existing guarded relay's destination rules.
    nonisolated static func admitsDelivery(_ url: URL) -> Bool {
        url.scheme == "https" && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.fragment == nil && url.absoluteString.utf8.count <= 8192 && LocalStreamProxyPolicy.allowsDestination(url)
            && url.path.lowercased().hasSuffix(".m3u8")
    }

    /// At most Origin, Referer and User-Agent; provenance must be https.
    nonisolated static func requestHeaders(_ delivery: Delivery) -> [String: String]? {
        guard delivery.behaviorHints?.proxyHeaders?.response?.isEmpty ?? true else { return nil }
        let request = delivery.behaviorHints?.proxyHeaders?.request ?? [:]
        guard request.count <= 3 else { return nil }
        let canonical = ["referer": "Referer", "origin": "Origin", "user-agent": "User-Agent"]
        var headers: [String: String] = [:]
        for (name, value) in request {
            guard let key = canonical[name.lowercased()], headers[key] == nil, !value.isEmpty, value.utf8.count <= 512,
                  value.utf8.allSatisfy({ (32...126).contains($0) }) else { return nil }
            if key != "User-Agent" {
                guard let url = URL(string: value), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil, url.fragment == nil else { return nil }
            }
            headers[key] = value
        }
        return headers
    }

    /// "🔴 LIVE: A - B" / "📺 A x B" → "A vs B" when exactly one separator splits two names.
    nonisolated static func pairTitle(_ name: String) -> String? {
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["🔴 LIVE:", "🔴", "📺"] where title.hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        for separator in [" vs. ", " vs ", " v ", " x ", " - "] {
            let parts = title.components(separatedBy: separator)
            if parts.count == 2, parts.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return parts[0].trimmingCharacters(in: .whitespaces) + " vs " + parts[1].trimmingCharacters(in: .whitespaces)
            }
            if parts.count > 2 { return nil }
        }
        return nil
    }

    nonisolated static func identity(_ row: Row, sport: String) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard row.type == "tv", row.id.range(of: #"^pp-live:[A-Za-z0-9]{1,32}~[A-Za-z0-9_=~.-]{1,200}$"#, options: .regularExpression) != nil,
              row.name.utf8.count <= 512, let title = pairTitle(row.name) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let kickoff = formatter.date(from: row.released) else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: sport, cast: [], title: title, kickoff: kickoff,
            effectiveID: row.id, resourceType: "tv", programmeMetadata: row.name)
    }

    nonisolated static func select(request: StreamPlaybackRequest, rows: [Row], now: Date) throws -> Row {
        guard let requestID = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              request.preferredEvent?.hasCatalogIdentityConflict != true else { throw CommunitySportsAddonError.matchNotFound }
        var unique: [Row] = [], ids = Set<String>()
        for row in rows where ids.insert(row.id).inserted { unique.append(row) }
        let candidates = unique.map { row in
            ReviewedSportsFixtureMatcher.Candidate(metadataID: row.id, effectiveID: row.id, identity: identity(row, sport: requestID.sport))
        }
        switch ReviewedSportsFixtureMatcher.select(for: requestID, from: candidates) {
        case .matched(let index): return unique[index]
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
    }

    nonisolated private static func sameFixture(_ lhs: StreamPlaybackRequest, _ rhs: StreamPlaybackRequest) -> Bool {
        lhs.matchID == rhs.matchID && lhs.preferredEvent?.hasCatalogIdentityConflict != true
            && ReviewedSportsFixtureMatcher.requestIdentity(for: lhs) == ReviewedSportsFixtureMatcher.requestIdentity(for: rhs)
            && lhs.preferredEvent?.competitionID == rhs.preferredEvent?.competitionID
            && lhs.preferredEvent?.sportsFixture?.squad == rhs.preferredEvent?.sportsFixture?.squad
            && lhs.preferredEvent?.cricketFixture?.broadcastDayIdentity == rhs.preferredEvent?.cricketFixture?.broadcastDayIdentity
    }

    private func read<T: Decodable>(_ url: URL) async throws -> T {
        try Task.checkCancellation()
        guard await enabled(), let configured = try await configuration(),
              url.absoluteString.hasPrefix(configured.deletingLastPathComponent().absoluteString) else {
            throw CommunitySportsAddonError.matchNotFound
        }
        try await validate(url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fotty/3.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard data.count <= 512 * 1024, response.statusCode == 200, response.mimeType == "application/json" else {
                throw CommunitySportsAddonError.invalidResponse
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch { throw CommunitySportsAddonError.invalidResponse } // Never propagate a credential-bearing URL.
    }
}
