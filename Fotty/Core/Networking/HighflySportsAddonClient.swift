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
    private struct Meta: Decodable { let meta: Row; init(meta: Row) { self.meta = meta } }
    /// Stremio manifest, read tolerantly (bare-string or object resources).
    private typealias Manifest = PenguPlaySportsAddonClient.Manifest
    /// One stream row. Only the link and any requested request headers matter;
    /// every other field is ignored rather than treated as a reason to refuse.
    struct Delivery: Decodable, Sendable {
        let url: String?
        let requestedHeaders: [String: String]
        /// DRM-protected rows cannot play in Fotty's player; skipping them is a
        /// capability rule, not a judgement about the row's shape.
        let requiresDRM: Bool
        private struct Key: CodingKey {
            let stringValue: String; var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil }
            static func named(_ name: String) -> Key { Key(stringValue: name)! }
        }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: Key.self)
            url = try? c?.decode(String.self, forKey: .named("url"))
            let hints = try? c?.nestedContainer(keyedBy: Key.self, forKey: .named("behaviorHints"))
            let proxy = try? hints?.nestedContainer(keyedBy: Key.self, forKey: .named("proxyHeaders"))
            let proxied = (try? proxy?.decode([String: String].self, forKey: .named("request"))) ?? [:]
            let direct = (try? c?.decode([String: String].self, forKey: .named("headers"))) ?? [:]
            requestedHeaders = proxied.merging(direct) { first, _ in first }
            requiresDRM = c?.contains(.named("drm")) == true
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
    /// Pages of the plain sport listing read when search misses (100 rows each).
    nonisolated static let browsePageLimit = 3

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
        // One lookup receipt per eligible request: the stage reached, never titles or URLs.
        var stage = "manifest"
        var finished = false
        var missReason: String?, rowCount: Int?, unmatchedTeam: String?, kickoffOffset: Int?
        var searchScope = "search"
        var requestPair: String?, candidatePairs: [String] = []
        var listingCount: Int?
        var listingSpan: String?, liveCatalog: String?
        var supplementaryFailures = 0
        var liveRows: Int?, liveShape: String?, liveSameSport: Int?, liveCategories: String?, liveRestShape: String?
        var liveLayout: String?
        defer {
            var details = ["source_family": Self.providerCode, "stage": stage, "result": finished ? "admitted" : "stopped_at_" + stage]
            if let missReason { details["reason_code"] = missReason }
            if stage != "manifest", stage != "search" { details["search_scope"] = searchScope }
            if let listingSpan { details["listing_span_h"] = listingSpan }
            if supplementaryFailures > 0 { details["supplementary_failures"] = "\(supplementaryFailures)" }
            if let liveCatalog { details["live_catalog"] = liveCatalog }
            if let liveRows { details["live_row_count"] = "\(liveRows)" }
            if let liveShape { details["live_row_shape"] = liveShape }
            if let liveSameSport { details["live_sport_rows"] = "\(liveSameSport)" }
            if let liveCategories { details["live_categories"] = liveCategories }
            if let liveRestShape { details["live_rest_shape"] = liveRestShape }
            if let liveLayout { details["live_layout"] = liveLayout }
            if let rowCount { details["candidate_count"] = "\(rowCount)" }
            if let unmatchedTeam { details["unmatched_team"] = unmatchedTeam }
            if let requestPair { details["request_pair"] = requestPair }
            if let listingCount { details["listing_count"] = "\(listingCount)" }
            for (index, pair) in candidatePairs.prefix(2).enumerated() { details[index == 0 ? "candidate_pair" : "candidate_pair_2"] = pair }
            if let kickoffOffset {
                details["kickoff_offset_min"] = String(max(-10_000, min(10_000, kickoffOffset)))
                details["sport"] = original.sport
            }
            FottyQualityStore.shared.record(category: .playback, name: "highfly_lookup", outcome: finished ? .success : .info,
                details: details)
        }
        // The first request after launch can race the network; retry once.
        let manifest: Manifest
        do { manifest = try await read(manifestURL) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try await Task.sleep(for: .milliseconds(1500))
            manifest = try await read(manifestURL)
        }
        let catalogID = Self.catalogID(forSport: original.sport)
        // The validated link already pins Highfly's host; its manifest id and
        // version wording may change without making the source unsafe.
        guard !manifest.version.isEmpty, manifest.version.utf8.count <= 64,
              manifest.catalogs.contains(where: { $0.id == catalogID && $0.type == "sport" }),
              ["catalog", "meta", "stream"].allSatisfy({ name in manifest.resources.contains { $0.name == name && $0.types.contains("sport") } }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        // Diagnostic: whether the account advertises a separate live catalog (never its name or URL).
        liveCatalog = manifest.catalogs.contains { $0.id.lowercased().contains("live") } ? "present" : "absent"
        stage = "search"
        let root = manifestURL.deletingLastPathComponent()
        var rows: [Row] = []
        // Both advertised participant searches handle common short-name
        // differences. Exact pairs/date/squad still decide admission below.
        for term in PenguPlaySportsAddonClient.searchTerms(request.homeTeam, request.awayTeam) {
            let escaped = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
            var skip = 0
            for _ in 0..<3 {
                let extra = "search=" + escaped + (skip == 0 ? "" : "&skip=\(skip)") + ".json"
                guard let url = URL(string: root.absoluteString + "catalog/sport/" + catalogID + "/" + extra) else { throw CommunitySportsAddonError.unsafeResponse }
                let page: Catalog
                do { page = try await read(url) }
                catch is CancellationError { throw CancellationError() }
                catch { supplementaryFailures += 1; break } // Keep earlier pages; try the other team.
                guard page.metas.count <= 100, rows.count + page.metas.count <= 600 else { supplementaryFailures += 1; break }
                rows += page.metas; skip += page.metas.count
                if page.metas.isEmpty { break }
            }
        }
        stage = "fixture_match"
        rowCount = Set(rows.map(\.id)).count
        // Highfly's search returned these teams' other dated games but not
        // today's (Jet build 303), so a miss also reads the plain sport
        // listing. The same exact pair/kickoff/squad rules decide admission.
        if Self.selectAll(request: request, rows: rows, now: now).isEmpty {
            // Jet build 305: the dated listing starts 1-8 h ahead, so a game
            // leaves it at kickoff. The account's live catalog carries games
            // in progress; its rows face the same exact identity rules.
            stage = "live"
            var live: [Row] = []
            for catalog in manifest.catalogs.filter({ $0.type == "sport" && $0.id.lowercased().contains("live") }).prefix(2) {
                guard catalog.id.range(of: #"^[A-Za-z0-9_.-]{1,64}$"#, options: .regularExpression) != nil else { continue }
                // Paging is per catalog. A supplementary read that fails or is
                // unsafe drops only that catalog, never a match found elsewhere.
                var catalogRows: [Row] = []
                do {
                    for _ in 0..<Self.browsePageLimit {
                        let extra = catalog.id + (catalogRows.isEmpty ? "" : "/skip=\(catalogRows.count)") + ".json"
                        guard let url = URL(string: root.absoluteString + "catalog/sport/" + extra) else { throw CommunitySportsAddonError.unsafeResponse }
                        let page: Catalog = try await read(url)
                        guard page.metas.count <= 100, live.count + catalogRows.count + page.metas.count <= 600 else { break }
                        catalogRows += page.metas
                        if page.metas.count < 100 { break }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { supplementaryFailures += 1; catalogRows = [] }
                live += catalogRows
            }
            liveRows = live.count
            liveShape = live.lazy.compactMap { Self.identityRejection($0) }.first ?? (live.isEmpty ? nil : "parsed")
            let liveStart = Self.liveKickoff(for: original, now: now)
            liveSameSport = live.filter { Self.identity($0, liveKickoff: liveStart, fallbackSport: original.sport)?.sport == original.sport }.count
            liveCategories = Self.categorySummary(live)
            liveLayout = Self.layoutSummary(live.filter { Self.supports(category: $0.category) })
            // Would rows parse if the category were a sport we know? (shape beyond category)
            liveRestShape = live.lazy.map { Row(id: $0.id, type: $0.type, name: $0.name, description: $0.description,
                releaseInfo: $0.releaseInfo, category: original.sport) }.compactMap { Self.identityRejection($0) }.first
                ?? (live.isEmpty ? nil : "parsed")
            let seen = Set(rows.map(\.id))
            rows += live.filter { !seen.contains($0.id) }
            // A live match is enough; the upcoming listing cannot hold a game
            // in progress, so it is read only while there is still no match.
            let stillMissing = Self.selectAll(request: request, rows: rows, now: now).isEmpty
            var browsed: [Row] = []
            if stillMissing {
                stage = "browse"
                searchScope = "search_and_browse"
                do {
                    for _ in 0..<Self.browsePageLimit {
                        let extra = browsed.isEmpty ? catalogID + ".json" : catalogID + "/skip=\(browsed.count).json"
                        guard let url = URL(string: root.absoluteString + "catalog/sport/" + extra) else { throw CommunitySportsAddonError.unsafeResponse }
                        let page: Catalog = try await read(url)
                        guard page.metas.count <= 100 else { throw CommunitySportsAddonError.unsafeResponse }
                        browsed += page.metas
                        if page.metas.count < 100 { break }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { supplementaryFailures += 1; browsed = [] }
            } else { searchScope = "search_and_live" }
            // Diagnostic: the hour span the listing covers relative to now
            // (e.g. "20_170" means it starts 20 h ahead, so live games are absent).
            let hours = browsed.compactMap { Self.identity($0) }.map { Int(($0.kickoff.timeIntervalSince(now) / 3600).rounded()) }
            if let low = hours.min(), let high = hours.max() {
                listingSpan = "\(max(-999, low))_\(min(9999, high))"
            } else if stillMissing { listingSpan = browsed.isEmpty ? "empty" : "unreadable" }
            let known = Set(rows.map(\.id))
            rows += browsed.filter { !known.contains($0.id) }
            stage = "fixture_match"
            rowCount = Set(rows.map(\.id)).count
        }
        // Highfly lists one game several times (one listing per upstream
        // feed, plus a live row). Every exact listing contributes streams.
        let matchedRows = Self.selectAll(request: request, rows: rows, now: now)
        if matchedRows.isEmpty {
            missReason = Self.missReason(request: request, rows: rows, now: now)
            if let requestID = ReviewedSportsFixtureMatcher.requestIdentity(for: request) {
                let parsed = rows.map { Self.identity($0, liveKickoff: Self.liveKickoff(for: requestID, now: now),
                                                        fallbackSport: requestID.sport) }
                // Team keys for alias work: Fotty's pair and Highfly's pairs in the same slot.
                if missReason == "teams_differ" || missReason == "one_team_matches" {
                    requestPair = ReviewedSportsFixtureMatcher.pairLabel(requestID.pair)
                    candidatePairs = ReviewedSportsFixtureMatcher.sameSlotPairs(for: requestID, parsed: parsed)
                }
                if missReason == "one_team_matches" {
                    unmatchedTeam = ReviewedSportsFixtureMatcher.unmatchedTeamName(for: requestID, parsed: parsed)
                } else if missReason == "kickoff_differs" || missReason == "format_or_match_number_differs" {
                    kickoffOffset = ReviewedSportsFixtureMatcher.kickoffOffsetMinutes(for: requestID, parsed: parsed)
                }
            }
            throw CommunitySportsAddonError.matchNotFound
        }
        stage = "streams"
        listingCount = matchedRows.count
        var listings: [(row: Row, deliveries: [Delivery])] = []
        var offeredTotal = 0
        for listing in matchedRows.prefix(Self.maximumListings) {
            // A manifest that declares which ids it streams is honoured per listing.
            guard manifest.resources.filter({ $0.name == "stream" }).contains(where: { resource in
                resource.idPrefixes.map { prefixes in prefixes.contains { listing.id.hasPrefix($0) } } ?? true }) else {
                supplementaryFailures += 1; continue
            }
            let metaRow: Row
            do { metaRow = (try await read(root.appendingPathComponent("meta/sport/" + listing.id + ".json")) as Meta).meta }
            catch is CancellationError { throw CancellationError() }
            catch { supplementaryFailures += 1; metaRow = listing } // The catalog row already matched this game.
            // A live marker may tick between reads; the fixed fields must agree.
            guard Self.metaDifference(metaRow, listing) == nil else { supplementaryFailures += 1; continue }
            do {
                let streams: Streams = try await read(root.appendingPathComponent("stream/sport/" + listing.id + ".json"))
                offeredTotal += streams.streams.count
                listings.append((metaRow, Array(streams.streams.prefix(100))))
            } catch is CancellationError { throw CancellationError() }
            catch { supplementaryFailures += 1 }
        }
        guard !listings.isEmpty else { missReason = "streams_read"; throw CommunitySportsAddonError.invalidResponse }
        let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(startedClock)))
        // Revalidation below uses wall clock elapsed from resolve, supplied in
        // one local scope; no cached account or fixture authority is renewed.
        missReason = "revalidate_account"
        guard await enabled(), try await configuration() == manifestURL,
              let latest = await current(request), Self.sameFixture(latest, request) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        // Each listing's own details must still identify the game now.
        listings = listings.filter { !Self.selectAll(request: latest, rows: [$0.row], now: completedAt).isEmpty }
        guard !listings.isEmpty else {
            missReason = "revalidate_meta"
            throw CommunitySportsAddonError.conflictingMatch
        }
        missReason = nil
        var sessions: [StreamSession] = [], seen: Set<URL> = []
        var rejections: [String] = [], rejectedHost: String?
        defer {
            // Shape-only receipt: counts, the commonest reason and a rejected host name. Never a path or token.
            var details = ["addon_stream_entry_count": "\(offeredTotal)", "used_count": "\(sessions.count)",
                           "candidate_count": "\(min(sessions.count, 12))",
                           "addon_admission_rejected_count": "\(rejections.count)"]
            if let common = Dictionary(grouping: rejections, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
                details["reason_code"] = common
            }
            if let rejectedHost { details["delivery_host"] = rejectedHost }
            details["listing_count"] = "\(listings.count)"
            FottyQualityStore.shared.record(category: .playback, name: "highfly_delivery_admission",
                outcome: sessions.isEmpty ? .failure : .info, details: details)
        }
        for (listing, row) in listings.flatMap({ listing in listing.deliveries.map { (listing.row, $0) } }) {
            guard let value = row.url, let url = URL(string: value) else { rejections.append("no_url"); continue }
            if row.requiresDRM { rejections.append("drm"); continue }
            if let reason = AccountSourceDeliveryPolicy.rejection(url) {
                rejections.append(reason)
                rejectedHost = rejectedHost ?? url.host?.lowercased()
                continue
            }
            if Self.isAddonDomain(url.host, manifestHost: manifestURL.host) {
                rejections.append("addon_message"); rejectedHost = rejectedHost ?? url.host?.lowercased(); continue
            }
            guard let headers = AccountSourceDeliveryPolicy.requestHeaders(row.requestedHeaders) else {
                rejections.append("credential_headers"); continue
            }
            guard seen.insert(url).inserted else { continue }
            do { try await validate(url) }
            catch is CancellationError { throw CancellationError() }
            catch { rejections.append("validation"); continue } // One rejected route must not erase valid siblings.
            guard let binding = StreamEventBinding(request: latest, providerCode: Self.providerCode,
                providerEventID: listing.id, streamID: listing.id, resourceType: "sport", manifestRevision: manifest.version,
                verifiedAt: completedAt, expiresAt: completedAt.addingTimeInterval(90), at: completedAt) else { throw CommunitySportsAddonError.conflictingMatch }
            sessions.append(StreamSession(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: "HF\(sessions.count + 1)", requiredHeaders: headers, qualityLabel: nil,
                expiryTime: binding.expiresAt, canRefresh: true,
                diagnosticMetadata: ["source_family": Self.providerCode, "delivery": "account_direct_hls",
                    "source_key": Self.stableChoiceKey(url), "source_key_scope": "upstream",
                    // Server name only (e.g. testleaf.papacito.cfd); never a path or token.
                    "delivery_host": url.host?.lowercased() ?? "unknown"],
                createdAt: completedAt, requiresGuardedRelay: true, eventBinding: binding))
            if sessions.count == Self.maximumSessions { break }
        }
        stage = "admission"
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: offeredTotal) }
        stage = "final_check"
        try Task.checkCancellation()
        guard await enabled(), try await configuration() == manifestURL,
              let final = await current(request), Self.sameFixture(final, latest),
              !Self.selectAll(request: final, rows: listings.map(\.row),
                              now: now.addingTimeInterval(max(0, Date().timeIntervalSince(startedClock)))).isEmpty else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        finished = true
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
    /// Highfly serves games from its delivery network; links on its own domain
    /// (highfly.to, any server) are tip, upgrade or sign-in messages.
    nonisolated static func isAddonDomain(_ host: String?, manifestHost: String?) -> Bool {
        func domain(_ value: String?) -> String? {
            guard let labels = value?.lowercased().split(separator: "."), labels.count >= 2 else { return nil }
            return labels.suffix(2).joined(separator: ".")
        }
        guard let delivery = domain(host), let addon = domain(manifestHost) else { return false }
        return delivery == addon
    }

    /// An account delivery is admitted when it is safe; see AccountSourceDeliveryPolicy.
    nonisolated static func deliveryRejection(_ url: URL) -> String? { AccountSourceDeliveryPolicy.rejection(url) }
    nonisolated static func admitsDelivery(_ url: URL) -> Bool { deliveryRejection(url) == nil }

    /// Upper bounds that only stop runaway responses; real games stay far below them.
    nonisolated static let maximumListings = 12
    nonisolated static let maximumSessions = 100

    /// Every listing of the requested game (see ReviewedSportsFixtureMatcher.selectAll).
    nonisolated static func selectAll(request: StreamPlaybackRequest, rows: [Row], now: Date) -> [Row] {
        guard let requestID = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              request.preferredEvent?.hasCatalogIdentityConflict != true else { return [] }
        let candidates = screenedCandidates(request: request, requestID: requestID, rows: rows, now: now)
        return ReviewedSportsFixtureMatcher.selectAll(for: requestID, from: candidates).map { rows[$0] }
    }

    nonisolated static func select(request: StreamPlaybackRequest, rows: [Row], now: Date) throws -> Row {
        guard let requestID = ReviewedSportsFixtureMatcher.requestIdentity(for: request), request.preferredEvent?.hasCatalogIdentityConflict != true else { throw CommunitySportsAddonError.matchNotFound }
        let candidates = screenedCandidates(request: request, requestID: requestID, rows: rows, now: now)
        switch ReviewedSportsFixtureMatcher.select(for: requestID, from: candidates) {
        case .matched(let index): return rows[index]
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
    }

    /// Diagnostic label for a lookup that found no row (never a title).
    nonisolated static func missReason(request: StreamPlaybackRequest, rows: [Row], now: Date) -> String {
        guard let requestID = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return "no_request_identity" }
        let live = liveKickoff(for: requestID, now: now)
        let parsed = rows.map { Self.identity($0, liveKickoff: live, fallbackSport: requestID.sport) }
        let final = screenedCandidates(request: request, requestID: requestID, rows: rows, now: now)
        let screened = zip(parsed, final).compactMap { raw, kept in kept.identity == nil ? raw : nil }
        return ReviewedSportsFixtureMatcher.missReason(for: requestID, parsed: parsed, screened: screened)
    }

    nonisolated private static func screenedCandidates(request: StreamPlaybackRequest,
            requestID: ReviewedSportsFixtureMatcher.RequestIdentity, rows: [Row], now: Date) -> [ReviewedSportsFixtureMatcher.Candidate] {
        let live = liveKickoff(for: requestID, now: now)
        return rows.map { row -> ReviewedSportsFixtureMatcher.Candidate in
            var identity = Self.identity(row, liveKickoff: live, fallbackSport: requestID.sport)
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
    }
    /// Diagnostic: distinct row categories, commonest first, as lowercase
    /// letters/digits/hyphens joined by "." (≤64 chars). Categories, never titles.
    nonisolated static func categorySummary(_ rows: [Row]) -> String {
        let cleaned = rows.map { row -> String in
            let lowered = row.category.lowercased().replacingOccurrences(of: " ", with: "-")
            let kept = String(lowered.unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) && $0.isASCII
                || CharacterSet.decimalDigits.contains($0) && $0.isASCII || $0 == "-" }.prefix(20).map(Character.init))
            return kept.isEmpty ? "blank" : kept
        }
        let ranked = Dictionary(grouping: cleaned, by: { $0 }).sorted { $0.value.count > $1.value.count || $0.value.count == $1.value.count && $0.key < $1.key }
        var summary = ""
        for (name, _) in ranked {
            let next = summary.isEmpty ? name : summary + "." + name
            guard next.count <= 64 else { break }
            summary = next
        }
        return summary.isEmpty ? "none" : summary
    }

    /// Diagnostic: the commonest description layout among rows, as line
    /// classes (name/vs/release/date/live/empty/text) plus the releaseInfo
    /// class, e.g. "name.text.date-ri_date". Classes only, never text.
    nonisolated static func layoutSummary(_ rows: [Row]) -> String {
        func isDate(_ value: String) -> Bool {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = value.first == "0" ? "dd MMM yyyy '·' HH:mm 'UTC'" : "d MMM yyyy '·' HH:mm 'UTC'"
            return f.date(from: value) != nil
        }
        func kind(_ line: String, row: Row) -> String {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "empty" }
            if trimmed == row.name { return "name" }
            if !row.releaseInfo.isEmpty && trimmed == row.releaseInfo { return "release" }
            if isDate(trimmed) { return "date" }
            if trimmed.lowercased().contains("live") { return "live" }
            if trimmed.range(of: #" (vs?\.?|v|@|-) "#, options: [.regularExpression, .caseInsensitive]) != nil { return "vs" }
            return trimmed.rangeOfCharacter(from: .decimalDigits) != nil ? "digits" : "text"
        }
        let layouts = rows.map { row -> String in
            let lines = row.description.components(separatedBy: "\n").prefix(5).map { kind($0, row: row) }.joined(separator: ".")
            let info = row.releaseInfo.isEmpty ? "empty" : isDate(row.releaseInfo) ? "date"
                : row.releaseInfo.lowercased().contains("live") ? "live" : row.releaseInfo.rangeOfCharacter(from: .decimalDigits) != nil ? "digits" : "text"
            return String((lines + "-ri_" + info).prefix(64))
        }
        return Dictionary(grouping: layouts, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? "none"
    }

    /// nil when a meta row may stand for the selected catalog row: fixed
    /// fields equal; description/releaseInfo are re-matched by identity.
    nonisolated static func metaDifference(_ meta: Row, _ selected: Row) -> String? {
        if meta.id != selected.id { return "id" }
        if meta.type != selected.type { return "type" }
        if meta.name != selected.name { return "name" }
        if meta.category != selected.category { return "category" }
        return nil
    }

    /// Diagnostic: the first identity rule a row fails (nil = parsed). Never a title.
    /// Diagnostic: why a row could not be read as a game (nil = it can). Never a title.
    nonisolated static func identityRejection(_ row: Row, fallbackSport: String? = nil) -> String? {
        guard identity(row, fallbackSport: fallbackSport) == nil else { return nil }
        if row.type != "sport" { return "type" }
        if rowSport(row, fallbackSport: fallbackSport) == nil { return "category" }
        if !admitsRowID(row.id) { return "id" }
        if title(of: row) == nil { return "no_title" }
        if kickoff(of: row) == nil { return isLiveMarked(row) ? "live_without_window" : "no_date" }
        return "teams"
    }

    /// Any plain id the add-on serves, except its replays. Ids become path
    /// components, so only characters that cannot escape a path are allowed.
    nonisolated static func admitsRowID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_~.:-]{0,399}$"#, options: .regularExpression) != nil
            && !id.lowercased().hasPrefix("recap")
    }

    /// The row's sport, or the requested sport when the row leaves it blank
    /// (Highfly's live catalog often does). Teams and kickoff still decide.
    nonisolated static func rowSport(_ row: Row, fallbackSport: String?) -> String? {
        let category = row.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if supports(category: category) { return category }
        if category.isEmpty, let fallbackSport, supports(category: fallbackSport) { return fallbackSport }
        return nil
    }

    /// First description line, else the name.
    nonisolated static func title(of row: Row) -> String? {
        let first = row.description.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = first.isEmpty ? row.name.trimmingCharacters(in: .whitespaces) : first
        return title.isEmpty ? nil : title
    }

    /// A dated kickoff from releaseInfo or any description line, in Highfly's
    /// "12 Nov 2026 · 19:45 UTC" form or ISO 8601.
    nonisolated static func kickoff(of row: Row) -> Date? {
        let lines = [row.releaseInfo] + row.description.components(separatedBy: "\n").dropFirst()
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.utf8.count <= 64 else { continue }
            // A time without its zone is ambiguous, so only complete forms count.
            for format in ["d MMM yyyy '·' HH:mm 'UTC'", "dd MMM yyyy '·' HH:mm 'UTC'"] {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = format; f.isLenient = false
                if let date = f.date(from: line), f.string(from: date) == line { return date }
            }
            if let date = ISO8601DateFormatter().date(from: line) { return date }
        }
        return nil
    }

    nonisolated static func isLiveMarked(_ row: Row) -> Bool {
        ([row.releaseInfo] + row.description.components(separatedBy: "\n").dropFirst())
            .contains { $0.utf8.count <= 64 && $0.lowercased().contains("live") }
    }

    /// How long after the official kickoff a game can still be in progress.
    /// Cricket is excluded: its format/ordinal/day rules own live identity.
    nonisolated static let liveWindow: [String: TimeInterval] = [
        "football": 150 * 60, "hockey": 210 * 60, "basketball": 210 * 60,
        "baseball": 300 * 60, "american-football": 270 * 60,
    ]

    /// Highfly's live catalog rows carry no date ("<title>" + a live marker),
    /// so the official kickoff stands in only while the official game is in
    /// its live window. Pair, sport and squad still have to match exactly.
    nonisolated static func liveKickoff(for requestID: ReviewedSportsFixtureMatcher.RequestIdentity, now: Date) -> Date? {
        guard let window = liveWindow[requestID.sport],
              now >= requestID.kickoff.addingTimeInterval(-10 * 60),
              now <= requestID.kickoff.addingTimeInterval(window) else { return nil }
        return requestID.kickoff
    }

    /// Reads a row as a game. Unknown or extra fields are ignored; only a
    /// sport, a title naming two teams and a kickoff are required.
    nonisolated static func identity(_ row: Row, liveKickoff: Date? = nil,
                                     fallbackSport: String? = nil) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard row.type == "sport", row.name.utf8.count <= 1024, row.description.utf8.count <= 4096,
              admitsRowID(row.id), let sport = rowSport(row, fallbackSport: fallbackSport),
              let title = title(of: row) else { return nil }
        if let date = kickoff(of: row) {
            return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: sport, cast: [], title: title, kickoff: date,
                effectiveID: row.id, resourceType: "sport", programmeMetadata: row.name)
        }
        // Live rows carry no date. The official kickoff stands in only while
        // the official game is inside its live window (never cricket).
        guard let liveKickoff, ReviewedSportsFixtureMatcher.sportKey(sport) != "cricket", isLiveMarked(row) else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: sport, cast: [], title: title, kickoff: liveKickoff,
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


/// The owner's own paid add-ons (Highfly, PenguPlay) are trusted for what they
/// serve. Fotty checks only that a stream is safe to open; whether it is the
/// right game is decided by fixture matching, and whether it plays is decided by
/// playback ranking. No host lists, path shapes or query-name rules.
enum AccountSourceDeliveryPolicy {
    static let maximumURLBytes = 8192

    /// nil = safe to play. Reasons are short labels, never a URL.
    nonisolated static func rejection(_ url: URL) -> String? {
        if url.scheme?.lowercased() != "https" { return "not_https" }
        if url.absoluteString.utf8.count > maximumURLBytes { return "too_long" }
        if url.user != nil || url.password != nil { return "credentials_in_link" }
        if !LocalStreamProxyPolicy.allowsDestination(url) { return "unsafe_destination" }
        if isReplayHost(url.host) { return "replay" }
        if nonLiveExtensions.contains(url.pathExtension.lowercased()) { return "not_live_media" }
        return nil
    }

    /// Files and pages, not live streams: Fotty's live relay cannot play them.
    /// Links without an extension or with any other one are tried.
    static let nonLiveExtensions: Set<String> = ["mp4", "m4v", "mkv", "avi", "mov", "webm", "mp3", "aac",
                                                 "html", "htm", "php", "jpg", "jpeg", "png", "gif"]

    /// Replay/VOD servers (e.g. recaps.highfly.to) never join a live source list.
    nonisolated static func isReplayHost(_ host: String?) -> Bool {
        guard let first = host?.lowercased().split(separator: ".").first else { return false }
        return ["recap", "recaps", "replay", "replays", "vod"].contains(String(first))
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
            guard let key = canonical[lower], headers[key] == nil, !value.isEmpty, value.utf8.count <= 512,
                  value.utf8.allSatisfy({ (32...126).contains($0) }) else { continue }
            if key != "User-Agent" {
                guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil, url.user == nil, url.password == nil else { continue }
            }
            headers[key] = value
        }
        return headers
    }
}
