import Foundation

/// Account-scoped, lazy discovery. Credentials stay in the device Keychain;
/// neither the cloud registry nor another provider receives this configuration.
actor HighflySportsAddonClient {
    static let shared = HighflySportsAddonClient()
    static let providerCode = "highfly"
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
        let id, type, name, description, releaseInfo, category: String
        enum CodingKeys: String, CodingKey { case id, type, name, description, releaseInfo, category }
        init(id: String, type: String = "sport", name: String, description: String, releaseInfo: String, category: String) {
            self.id = id; self.type = type; self.name = name; self.description = description
            self.releaseInfo = releaseInfo; self.category = category
        }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            id = (try? c?.decode(String.self, forKey: .id)) ?? ""
            type = (try? c?.decode(String.self, forKey: .type)) ?? ""
            name = (try? c?.decode(String.self, forKey: .name)) ?? ""
            description = (try? c?.decode(String.self, forKey: .description)) ?? ""
            releaseInfo = (try? c?.decode(String.self, forKey: .releaseInfo)) ?? ""
            category = (try? c?.decode(String.self, forKey: .category)) ?? ""
        }
    }
    private struct Catalog: Decodable { let metas: [Row] }
    private struct Meta: Decodable { let meta: Row }
    private struct Manifest: Decodable {
        struct Resource: Decodable { let name: String; let types: [String]; let idPrefixes: [String]? }
        struct Catalog: Decodable { let id: String; let type: String }
        let id: String; let version: String; let resources: [Resource]; let catalogs: [Catalog]
    }
    struct Delivery: Decodable, Sendable {
        let url: String?
        let supported: Bool
        private struct Key: CodingKey {
            let stringValue: String; var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil }
        }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: Key.self)
            url = try? c?.decode(String.self, forKey: Key(stringValue: "url")!)
            let keys = Set(c?.allKeys.map(\.stringValue) ?? [])
            let hints = try? c?.decode([String: Bool].self, forKey: Key(stringValue: "behaviorHints")!)
            supported = keys.isSubset(of: ["name", "title", "url", "behaviorHints"])
                && (keys.contains("behaviorHints") ? hints?.keys.allSatisfy { $0 == "notWebReady" } == true : true)
        }
    }
    private struct Streams: Decodable { let streams: [Delivery] }

    init(configuration: Configuration? = nil, fetch: Fetch? = nil, enabled: Enabled? = nil,
         current: Current? = nil, validate: (@Sendable (URL) async throws -> Void)? = nil) {
        self.configuration = configuration ?? { try await MainActor.run { try AccountSourceSetupStore().savedLink(for: .highfly) } }
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

    /// Highfly publishes a dated "Home vs Away" catalog for every sport. These
    /// are the sports Fotty's own schedules also cover, so a fixture can be
    /// matched exactly. Rugby, fight, golf, motorsport and tennis have no Fotty
    /// fixture to match against.
    nonisolated static let supportedSports: Set<String> = ["football", "cricket", "basketball", "baseball", "hockey", "american-football"]

    nonisolated static func supports(category: String) -> Bool {
        supportedSports.contains(ReviewedSportsFixtureMatcher.sportKey(category))
    }

    /// Highfly names catalogs with underscores: `sports_american_football`.
    nonisolated static func catalogID(forSport sport: String) -> String {
        "sports_" + ReviewedSportsFixtureMatcher.sportKey(sport).replacingOccurrences(of: "-", with: "_")
    }

    /// Check the owner's configured account before saving or enabling it. This
    /// checks one bounded catalog page, fetches no media, and never logs a credential-bearing URL.
    nonisolated static func validateConfiguration(_ url: URL) async throws {
        do {
            guard try AccountSourceSetup.highfly.validatedLink(url.absoluteString) == url,
                  url.query == nil else { throw AccountSourceSetupError.accessUnavailable }
            try await LocalStreamProxyDestinationValidator.validate(url)
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
            let client = FottyBoundedHTTPClient(configuration: config)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await client.fetch(request, maximumBytes: 512 * 1024, deadline: 8,
                acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
            let manifest = try JSONDecoder().decode(Manifest.self, from: response.data)
            guard response.http.url == url, response.http.mimeType == "application/json",
                  manifest.id == manifestIdentity(for: url),
                  ["catalog", "meta", "stream"].allSatisfy({ name in manifest.resources.contains { $0.name == name && $0.types.contains("sport") } }),
                  let catalog = manifest.catalogs.first(where: { catalog in
                      catalog.type == "sport" && supportedSports.contains { catalogID(forSport: $0) == catalog.id } }) else {
                throw AccountSourceSetupError.accessUnavailable
            }
            let catalogURL = url.deletingLastPathComponent().appendingPathComponent("catalog/sport/" + catalog.id + ".json")
            request.url = catalogURL
            let listing = try await client.fetch(request, maximumBytes: 512 * 1024, deadline: 8,
                acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
            guard listing.http.url == catalogURL, listing.http.mimeType == "application/json" else { throw AccountSourceSetupError.accessUnavailable }
            _ = try JSONDecoder().decode(Catalog.self, from: listing.data)
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
              await enabled(), let manifestURL = try await configuration(),
              manifestURL.query == nil,
              (try? AccountSourceSetup.highfly.validatedLink(manifestURL.absoluteString)) == manifestURL,
              let initial = await current(request), Self.sameFixture(initial, request) else {
            throw CommunitySportsAddonError.matchNotFound
        }
        let manifest: Manifest = try await read(manifestURL)
        let catalogID = Self.catalogID(forSport: original.sport)
        guard manifest.id == Self.manifestIdentity(for: manifestURL), manifest.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              manifest.catalogs.contains(where: { $0.id == catalogID && $0.type == "sport" }),
              ["catalog", "meta", "stream"].allSatisfy({ name in manifest.resources.contains { $0.name == name && $0.types.contains("sport") } }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        let root = manifestURL.deletingLastPathComponent()
        var rows: [Row] = []
        // Both advertised participant searches handle common short-name
        // differences. Exact pairs/date/squad still decide admission below.
        for term in Set([request.homeTeam, request.awayTeam]).sorted() where !term.isEmpty {
            let escaped = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
            var skip = 0
            for _ in 0..<3 {
                let extra = "search=" + escaped + (skip == 0 ? "" : "&skip=\(skip)") + ".json"
                guard let url = URL(string: root.absoluteString + "catalog/sport/" + catalogID + "/" + extra) else { throw CommunitySportsAddonError.unsafeResponse }
                let page: Catalog = try await read(url)
                guard page.metas.count <= 100, rows.count + page.metas.count <= 300 else { throw CommunitySportsAddonError.unsafeResponse }
                rows += page.metas; skip += page.metas.count
                if page.metas.isEmpty { break }
            }
        }
        let selected = try Self.select(request: request, rows: rows, now: now)
        guard manifest.resources.filter({ $0.name == "stream" }).contains(where: { $0.idPrefixes?.contains(where: { selected.id.hasPrefix($0) }) == true }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        let metadata: Meta = try await read(root.appendingPathComponent("meta/sport/" + selected.id + ".json"))
        guard metadata.meta == selected else { throw CommunitySportsAddonError.conflictingMatch }
        let streams: Streams = try await read(root.appendingPathComponent("stream/sport/" + selected.id + ".json"))
        guard streams.streams.count <= 40 else { throw CommunitySportsAddonError.unsafeResponse }
        let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(startedClock)))
        // Revalidation below uses wall clock elapsed from resolve, supplied in
        // one local scope; no cached account or fixture authority is renewed.
        guard await enabled(), try await configuration() == manifestURL,
              let latest = await current(request), Self.sameFixture(latest, request),
              (try? Self.select(request: latest, rows: [metadata.meta], now: completedAt)) != nil else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        var sessions: [StreamSession] = [], seen: Set<URL> = []
        for row in streams.streams {
            guard row.supported, let value = row.url, let url = URL(string: value), Self.admitsDelivery(url), seen.insert(url).inserted else { continue }
            do { try await validate(url) }
            catch is CancellationError { throw CancellationError() }
            catch { continue } // One rejected route must not erase valid siblings.
            guard let binding = StreamEventBinding(request: latest, providerCode: Self.providerCode,
                providerEventID: selected.id, streamID: selected.id, resourceType: "sport", manifestRevision: manifest.version,
                verifiedAt: completedAt, expiresAt: completedAt.addingTimeInterval(90), at: completedAt) else { throw CommunitySportsAddonError.conflictingMatch }
            sessions.append(StreamSession(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: "HF\(sessions.count + 1)", requiredHeaders: [:], qualityLabel: nil,
                expiryTime: binding.expiresAt, canRefresh: true,
                diagnosticMetadata: ["source_family": Self.providerCode, "delivery": "reviewed_direct_hls",
                    "source_key": Self.stableChoiceKey(url), "source_key_scope": "upstream"],
                createdAt: completedAt, requiresGuardedRelay: true, eventBinding: binding))
            if sessions.count == 6 { break }
        }
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: streams.streams.count) }
        try Task.checkCancellation()
        guard await enabled(), try await configuration() == manifestURL,
              let final = await current(request), Self.sameFixture(final, latest),
              (try? Self.select(request: final, rows: [metadata.meta], now: now.addingTimeInterval(max(0, Date().timeIntervalSince(startedClock))))) != nil else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        return sessions
    }

    nonisolated static func stableChoiceKey(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.query = nil
        return PlavioSportsAddonClient.sourceKey(url: parts.url!)
    }
    nonisolated static func manifestIdentity(for url: URL) -> String {
        url.host?.hasPrefix("sports.") == true ? "community.sports.fly" : "community.sports.streamed.premium"
    }
    nonisolated static func admitsDelivery(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "papacito.cfd", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil, url.fragment == nil, url.absoluteString.utf8.count <= 8192,
              LocalStreamProxyPolicy.allowsDestination(url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.percentEncodedPath == url.path,
              url.path.range(of: #"^/m3u/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9_-]{1,64}\.m3u8$"#, options: .regularExpression) != nil,
              let items = parts.queryItems, items.count == 1, ["ft", "token"].contains(items[0].name),
              let value = items[0].value, (1...4096).contains(value.utf8.count),
              value.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil else { return false }
        return true
    }
    nonisolated static func select(request: StreamPlaybackRequest, rows: [Row], now: Date) throws -> Row {
        guard let requestID = ReviewedSportsFixtureMatcher.requestIdentity(for: request), request.preferredEvent?.hasCatalogIdentityConflict != true else { throw CommunitySportsAddonError.matchNotFound }
        let candidates = rows.map { row -> ReviewedSportsFixtureMatcher.Candidate in
            var identity = Self.identity(row)
            if requestID.sport == "cricket", let candidate = identity {
                guard let official = request.preferredEvent?.cricketFixture, official.verified, !official.status.stopsPlayback,
                      candidate.cricketFormat == official.format.rawValue,
                      candidate.matchOrdinal == (official.matchOrdinal ?? official.context?.matchOrdinal) else {
                    return .init(metadataID: row.id, effectiveID: row.id, identity: nil)
                }
                if official.format == .test {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    guard let day = official.context?.day, day == candidate.day,
                          candidate.matchOrdinal != nil,
                          calendar.isDate(candidate.kickoff, inSameDayAs: now),
                          let expectedDay = calendar.date(byAdding: .day, value: day - 1, to: requestID.kickoff),
                          calendar.isDate(expectedDay, inSameDayAs: candidate.kickoff) else {
                        return .init(metadataID: row.id, effectiveID: row.id, identity: nil)
                    }
                    // An official Test start identifies day one, not every
                    // later session's clock. Exact ordinal/current day/UTC date
                    // own this join; neither timestamp is rewritten upstream.
                    identity = .init(sport: candidate.sport, pair: candidate.pair, kickoff: requestID.kickoff,
                        effectiveID: candidate.effectiveID, resourceType: candidate.resourceType,
                        cricketFormat: candidate.cricketFormat, matchOrdinal: candidate.matchOrdinal, day: candidate.day)
                }
            }
            return .init(metadataID: row.id, effectiveID: row.id, identity: identity)
        }
        switch ReviewedSportsFixtureMatcher.select(for: requestID, from: candidates) {
        case .matched(let index): return rows[index]
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
    }
    nonisolated static func identity(_ row: Row) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard row.type == "sport", supports(category: row.category), row.name.utf8.count <= 1024,
              row.description.utf8.count <= 4096,
              row.id.range(of: #"^(streamed|sf|leaf|recap):[A-Za-z0-9_~.-]{1,400}$"#, options: .regularExpression) != nil,
              !row.id.hasPrefix("recap:") else { return nil }
        let parts = row.description.components(separatedBy: "\n")
        guard parts.count == 2, parts[1] == row.releaseInfo,
              row.name == parts[0] || row.category == "cricket" && row.name.hasPrefix(parts[0] + " - ") else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = row.releaseInfo.first == "0" ? "dd MMM yyyy '·' HH:mm 'UTC'" : "d MMM yyyy '·' HH:mm 'UTC'"
        f.isLenient = false
        guard let date = f.date(from: row.releaseInfo), f.string(from: date) == row.releaseInfo else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: row.category, cast: [], title: parts[0], kickoff: date,
            effectiveID: row.id, resourceType: "sport", programmeMetadata: row.name)
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
            guard data.count <= 512 * 1024, response.statusCode == 200, response.url == url,
                  response.mimeType == "application/json" else { throw CommunitySportsAddonError.invalidResponse }
            return try JSONDecoder().decode(T.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch { throw CommunitySportsAddonError.invalidResponse } // Never propagate a credential-bearing URL.
    }
}
