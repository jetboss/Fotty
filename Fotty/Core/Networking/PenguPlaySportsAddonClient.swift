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
    /// Fox Cricket / Willow channels a reviewed TV guide programme currently ties to this fixture.
    typealias ProgrammeChannels = @Sendable (StreamPlaybackRequest) async -> Set<CricketBroadcastChannel>
    private let configuration: Configuration
    private let fetch: Fetch
    private let enabled: Enabled
    private let current: Current
    private let validate: @Sendable (URL) async throws -> Void
    private let programmeChannels: ProgrammeChannels

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
         current: Current? = nil, validate: (@Sendable (URL) async throws -> Void)? = nil,
         programmeChannels: ProgrammeChannels? = nil) {
        self.programmeChannels = programmeChannels ?? { request in await MainActor.run {
            Set(ReviewedTVPlaylistClient.programmeLookupRequests(for: request).compactMap { scoped in
                scoped.registryMatch?.broadcast.channelID.flatMap { id in CricketBroadcastChannel.allCases.first { $0.canonicalID == id } }
            })
        } }
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
                let result = try await transport.fetch(request, maximumBytes: 512 * 1024, deadline: request.timeoutInterval,
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

    /// PenguPlay's search misses "Sydney Thunder Women" but finds "Sydney Thunder";
    /// the squad word is still enforced by the fixture matcher afterwards.
    nonisolated static func searchTerms(_ home: String, _ away: String) -> [String] {
        var terms = Set<String>()
        for name in [home, away] {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            terms.insert(trimmed)
            let base = trimmed.replacingOccurrences(of: #"(?i)\s+(women'?s?|w)$"#, with: "", options: .regularExpression)
            if !base.isEmpty { terms.insert(base) }
        }
        return terms.sorted()
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
        // A fixture matches by exact teams and kickoff. A Fox Cricket / Willow
        // channel row is used only for that channel's own tile, or for a fixture
        // a reviewed TV guide programme currently places on that channel.
        let channelTile = CricketBroadcastChannel.identifying(request: request)
        let original = ReviewedSportsFixtureMatcher.requestIdentity(for: request)
        guard Self.supports(category: request.category), request.registryMatch == nil,
              original != nil || channelTile != nil,
              await enabled(), let manifestURL = try await configuration(), manifestURL.query == nil,
              (try? AccountSourceSetup.penguPlay.validatedLink(manifestURL.absoluteString)) == manifestURL else {
            throw CommunitySportsAddonError.matchNotFound
        }
        if original != nil {
            guard let initial = await current(request), Self.sameFixture(initial, request) else { throw CommunitySportsAddonError.matchNotFound }
        }
        let sport = original?.sport ?? "cricket"
        // One lookup receipt per eligible request: the stage reached, never titles or URLs.
        var stage = "manifest"
        var finished = false
        lastReadFailure = nil
        var missReason: String?, rowCount: Int?
        defer {
            var details = ["source_family": Self.providerCode, "stage": stage, "result": finished ? "admitted" : "stopped_at_" + stage]
            if !finished, let failure = lastReadFailure ?? missReason { details["reason_code"] = failure }
            if let rowCount { details["candidate_count"] = "\(rowCount)" }
            FottyQualityStore.shared.record(category: .playback, name: "penguplay_lookup", outcome: finished ? .success : .info,
                details: details)
        }
        let manifest: Manifest = try await readManifest(manifestURL)
        let catalogID = Self.catalogID(forSport: sport)
        guard Self.hasLiveTV(manifest), manifest.catalogs.contains(where: { $0.id == catalogID && $0.type == "tv" }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        stage = "search"
        let root = manifestURL.deletingLastPathComponent().absoluteString
        var rows: [Row] = []
        for term in channelTile == nil ? Self.searchTerms(request.homeTeam, request.awayTeam) : [] {
            guard let url = URL(string: root + "catalog/tv/" + catalogID + "/search=" + Self.encodedComponent(term) + ".json") else {
                throw CommunitySportsAddonError.unsafeResponse
            }
            do {
                let page: Catalog = try await read(url)
                rows += page.metas.prefix(max(0, 400 - rows.count))
            } catch is CancellationError { throw CancellationError() }
            catch { lastReadFailure = nil; continue } // Keep the other team's rows.
        }
        stage = "fixture_match"
        var viaChannel: CricketBroadcastChannel? = channelTile
        let selected: Row
        if channelTile == nil { rowCount = Set(rows.map(\.id)).count }
        if channelTile == nil, let exact = try? Self.select(request: request, rows: rows, now: now) {
            selected = exact
        } else {
            if channelTile == nil, let requestID = original {
                missReason = ReviewedSportsFixtureMatcher.missReason(for: requestID,
                    parsed: rows.map { Self.identity($0, sport: requestID.sport) })
            }
            if viaChannel == nil {
                // Exact listing missed: only a current reviewed programme names the channel.
                stage = "programme_channel"
                let channels = sport == "cricket" ? await programmeChannels(request) : []
                guard channels.count == 1 else { throw CommunitySportsAddonError.matchNotFound }
                viaChannel = channels.first
            }
            stage = "channel_row"
            guard let channel = viaChannel, let url = URL(string: root + "catalog/tv/" + catalogID + ".json") else {
                throw CommunitySportsAddonError.matchNotFound
            }
            let page: Catalog = try await read(url)
            selected = try Self.selectChannel(channel, rows: Array(page.metas.prefix(200)))
        }
        stage = "streams"
        guard let streamURL = URL(string: root + "stream/tv/" + Self.encodedComponent(selected.id) + ".json") else {
            throw CommunitySportsAddonError.unsafeResponse
        }
        lastReadFailure = nil
        let streams: Streams = try await read(streamURL, timeout: Self.streamReadTimeout)
        stage = "stream_count"
        let offered = Array(streams.streams.prefix(40))
        stage = "sign_in"
        guard !streams.streams.contains(where: Self.isSignInPlaceholder) else {
            throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: streams.streams.count)
        }
        stage = "recheck"
        let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(startedClock)))
        guard await enabled(), try await configuration() == manifestURL,
              let latest = original == nil ? request : await current(request), Self.sameFixture(latest, request),
              await stillSelected(selected, channel: viaChannel, request: latest, at: completedAt) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        stage = "delivery"
        var sessions: [StreamSession] = [], seen: Set<URL> = []
        var rejections: [String] = [], rejectedHost: String?
        for row in offered {
            guard let value = row.url, let url = URL(string: value) else { rejections.append("no_url"); continue }
            if let reason = AccountSourceDeliveryPolicy.rejection(url) {
                rejections.append(reason); rejectedHost = rejectedHost ?? url.host?.lowercased(); continue
            }
            guard let headers = Self.requestHeaders(row) else { rejections.append("credential_headers"); continue }
            guard seen.insert(url).inserted else { continue }
            do { try await validate(url) }
            catch is CancellationError { throw CancellationError() }
            catch { rejections.append("validation"); rejectedHost = rejectedHost ?? url.host?.lowercased(); continue }
            guard let binding = StreamEventBinding(request: latest, providerCode: Self.providerCode,
                providerEventID: selected.id, streamID: selected.id, resourceType: "tv", manifestRevision: manifest.version,
                verifiedAt: completedAt, expiresAt: completedAt.addingTimeInterval(90), at: completedAt) else {
                throw CommunitySportsAddonError.conflictingMatch
            }
            sessions.append(StreamSession(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: "PP\(sessions.count + 1)", requiredHeaders: headers, qualityLabel: nil,
                expiryTime: binding.expiresAt, canRefresh: true,
                diagnosticMetadata: ["source_family": Self.providerCode, "delivery": "penguplay_hls",
                    "source_key": HighflySportsAddonClient.stableChoiceKey(url), "source_key_scope": "upstream",
                    "delivery_host": url.host?.lowercased() ?? "unknown"],
                createdAt: completedAt,
                nativePlaylistProfile: LocalStreamProxyPlaylistProfile.penguPlay(deliveryURL: url,
                    providerEventID: selected.id, headers: headers),
                requiresGuardedRelay: true, eventBinding: binding))
            if sessions.count == 6 { break }
        }
        // Shape-only receipt so admission rules can be reviewed: counts, never URLs.
        var admission = ["addon_stream_entry_count": "\(streams.streams.count)", "candidate_count": "\(sessions.count)",
                         "addon_admission_rejected_count": "\(rejections.count)"]
        if let common = Dictionary(grouping: rejections, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            admission["reason_code"] = common
        }
        if let rejectedHost { admission["delivery_host"] = rejectedHost }
        FottyQualityStore.shared.record(category: .playback, name: "penguplay_delivery_admission", outcome: sessions.isEmpty ? .failure : .info,
            details: admission)
        stage = "admission"
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: streams.streams.count) }
        try Task.checkCancellation()
        stage = "final_check"
        guard await enabled(), try await configuration() == manifestURL,
              let final = original == nil ? request : await current(request), Self.sameFixture(final, latest),
              await stillSelected(selected, channel: viaChannel, request: final, at: completedAt) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        finished = true
        return sessions
    }

    /// Safe to open (see AccountSourceDeliveryPolicy); link shape is not judged.
    nonisolated static func admitsDelivery(_ url: URL) -> Bool { AccountSourceDeliveryPolicy.rejection(url) == nil }

    /// Referer, Origin and User-Agent are forwarded; other names are dropped;
    /// a credential header refuses the stream. Response-header hints are ignored.
    nonisolated static func requestHeaders(_ delivery: Delivery) -> [String: String]? {
        AccountSourceDeliveryPolicy.requestHeaders(delivery.behaviorHints?.proxyHeaders?.request ?? [:])
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

    /// The one live row that is exactly this channel ("🔴 LIVE: Fox Cricket").
    /// A competition-named row ("🔴 LIVE: WBBL") never identifies a game.
    nonisolated static func selectChannel(_ channel: CricketBroadcastChannel, rows: [Row]) throws -> Row {
        var ids = Set<String>()
        let matches = rows.filter { row in
            guard row.type == "tv", row.name.utf8.count <= 512, ids.insert(row.id).inserted,
                  row.id.range(of: #"^pp-live:[A-Za-z0-9]{1,32}~[A-Za-z0-9_=~.-]{1,200}$"#, options: .regularExpression) != nil else { return false }
            var title = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.hasPrefix("🔴 LIVE:") else { return false }
            title = String(title.dropFirst("🔴 LIVE:".count))
            return CricketBroadcastChannel.identifying(title: title) == channel
        }
        guard !matches.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        guard matches.count == 1 else { throw CommunitySportsAddonError.conflictingMatch }
        return matches[0]
    }

    private func stillSelected(_ row: Row, channel: CricketBroadcastChannel?, request: StreamPlaybackRequest, at now: Date) async -> Bool {
        guard let channel else { return (try? Self.select(request: request, rows: [row], now: now)) != nil }
        if CricketBroadcastChannel.identifying(request: request) == channel { return true }
        return await programmeChannels(request) == [channel]
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

    /// The first request after launch can race the network and source setup;
    /// one short retry keeps that from becoming a missed lookup.
    private func readManifest(_ url: URL) async throws -> Manifest {
        do { return try await read(url) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try await Task.sleep(for: .milliseconds(1500))
            lastReadFailure = nil
            return try await read(url)
        }
    }

    /// Why the last read failed, as a shape only: status, type, size or decode.
    private var lastReadFailure: String?

    /// PenguPlay gathers a channel's links when asked, which can take well over
    /// 8 s; only that one stream request gets the longer allowance.
    static let streamReadTimeout: TimeInterval = 25

    private func read<T: Decodable>(_ url: URL, timeout: TimeInterval = 8) async throws -> T {
        try Task.checkCancellation()
        guard await enabled() else { lastReadFailure = "not_enabled"; throw CommunitySportsAddonError.matchNotFound }
        guard let configured = try await configuration(),
              url.absoluteString.hasPrefix(configured.deletingLastPathComponent().absoluteString) else {
            lastReadFailure = "no_link"; throw CommunitySportsAddonError.matchNotFound
        }
        do { try await validate(url) }
        catch is CancellationError { throw CancellationError() }
        catch { lastReadFailure = "destination_check"; throw error }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: min(max(timeout, 1), 30))
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fotty/3.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        do {
            let fetched: (Data, HTTPURLResponse)
            do { fetched = try await fetch(request) } catch is CancellationError { throw CancellationError() }
            catch {
                switch error as? FottyBoundedHTTPClient.Failure {
                case .httpStatus(let code)?: lastReadFailure = "http_\(min(max(code, 0), 999))"
                case .responseTooLarge?: lastReadFailure = "too_large"
                case .unsafeRedirect?: lastReadFailure = "redirect"
                default: lastReadFailure = (error as? URLError)?.code == .timedOut ? "timeout" : "transport"
                }
                throw error
            }
            let (data, response) = fetched
            try Task.checkCancellation()
            guard response.statusCode == 200 else { lastReadFailure = "http_\(min(max(response.statusCode, 0), 999))"; throw CommunitySportsAddonError.invalidResponse }
            guard response.mimeType == "application/json" else { lastReadFailure = "content_type"; throw CommunitySportsAddonError.invalidResponse }
            guard data.count <= 512 * 1024 else { lastReadFailure = "too_large"; throw CommunitySportsAddonError.invalidResponse }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { lastReadFailure = "decode"; throw error }
        } catch is CancellationError { throw CancellationError() }
        catch { throw CommunitySportsAddonError.invalidResponse } // Never propagate a credential-bearing URL.
    }
}
