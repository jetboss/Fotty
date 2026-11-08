import Foundation
import CryptoKit

private struct CNCSportsCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct CNCSportsCatalogEntry: Decodable, Sendable {
    let id: String
    let effectiveID: String
    let type: String?
    let name: String
    let hasMalformedIdentity: Bool

    init(id: String, effectiveID: String? = nil, type: String? = "tv", name: String,
         hasMalformedIdentity: Bool = false) {
        self.id = id; self.effectiveID = effectiveID ?? id; self.type = type
        self.name = name; self.hasMalformedIdentity = hasMalformedIdentity
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CNCSportsCodingKey.self)
        id = (try? values.decode(String.self, forKey: .init("id"))) ?? ""
        type = try? values.decode(String.self, forKey: .init("type"))
        name = (try? values.decode(String.self, forKey: .init("name"))) ?? ""
        let hints = try? values.nestedContainer(keyedBy: CNCSportsCodingKey.self, forKey: .init("behaviorHints"))
        let target = try? hints?.decode(String.self, forKey: .init("defaultVideoId"))
        effectiveID = target ?? id
        hasMalformedIdentity = id.isEmpty || type == nil || name.isEmpty || target != id
            || hints.map { Set($0.allKeys.map(\.stringValue)) != ["defaultVideoId"] } != false
    }
}

struct CNCSportsMetadata: Decodable, Sendable {
    let id: String
    let type: String?
    let name: String
    let description: String?
    let hasMalformedIdentity: Bool

    init(id: String, type: String? = "tv", name: String, description: String?,
         hasMalformedIdentity: Bool = false) {
        self.id = id; self.type = type; self.name = name; self.description = description
        self.hasMalformedIdentity = hasMalformedIdentity
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CNCSportsCodingKey.self)
        id = (try? values.decode(String.self, forKey: .init("id"))) ?? ""
        type = try? values.decode(String.self, forKey: .init("type"))
        name = (try? values.decode(String.self, forKey: .init("name"))) ?? ""
        description = try? values.decode(String.self, forKey: .init("description"))
        hasMalformedIdentity = id.isEmpty || type == nil || name.isEmpty || description == nil
            || values.contains(.init("behaviorHints"))
    }
}

struct CNCSportsStreamEntry: Decodable, Sendable {
    let name: String?
    let url: String?
    let requiredHeaders: [String: String]?
    let isSupportedContract: Bool
    let isReviewedCricketContract: Bool

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CNCSportsCodingKey.self)
        func key(_ value: String) -> CNCSportsCodingKey { .init(value) }
        name = try values.decodeIfPresent(String.self, forKey: key("name"))
        url = try values.decodeIfPresent(String.self, forKey: key("url"))
        if values.contains(key("title")) { _ = try values.decode(String.self, forKey: key("title")) }
        var supported = Set(values.allKeys.map(\.stringValue)).isSubset(of: ["name", "title", "url", "behaviorHints"])
        let hints = try values.nestedContainer(keyedBy: CNCSportsCodingKey.self, forKey: key("behaviorHints"))
        supported = supported && Set(hints.allKeys.map(\.stringValue)) == ["proxyHeaders"]
        let proxy = try hints.nestedContainer(keyedBy: CNCSportsCodingKey.self, forKey: key("proxyHeaders"))
        supported = supported && Set(proxy.allKeys.map(\.stringValue)).isSubset(of: ["request", "response"])
        if proxy.contains(key("response")) {
            supported = try proxy.decode([String: String].self, forKey: key("response")).isEmpty && supported
        }
        let headers = try proxy.decode([String: String].self, forKey: key("request"))
        requiredHeaders = headers
        isSupportedContract = supported && headers == CNCSportsAddonClient.reviewedHeaders
        // The newer PlayZTV envelope is a separate reviewed contract. It does
        // not relax LivXow's existing NHL headers or accept response rewrites.
        let cricketHints = Set(hints.allKeys.map(\.stringValue))
        let cricketFields = Set(values.allKeys.map(\.stringValue))
        let group = try? hints.decode(String.self, forKey: key("bingeGroup"))
        let notWebReady = try? hints.decode(Bool.self, forKey: key("notWebReady"))
        let filename = try? hints.decode(String.self, forKey: key("filename"))
        let responseIsEmpty = !proxy.contains(key("response"))
            || (try? proxy.decode([String: String].self, forKey: key("response")))?.isEmpty == true
        isReviewedCricketContract = cricketFields.isSubset(of: ["name", "title", "url", "behaviorHints"])
            && cricketHints.isSubset(of: ["bingeGroup", "notWebReady", "proxyHeaders", "filename"])
            && group == "cncverse-playztv-live-events" && notWebReady == true
            && (!hints.contains(key("filename")) || (filename.map { $0.utf8.count <= 512 && $0.rangeOfCharacter(from: .controlCharacters) == nil } ?? false))
            && Set(proxy.allKeys.map(\.stringValue)).isSubset(of: ["request", "response"])
            && responseIsEmpty && CNCSportsAddonClient.isAdmittedCricketHeaders(headers)
    }
}

/// Reviewed LivXow NHL and PlayZTV WBBL lanes. Catalog names bound at most two
/// metadata requests per fixture; an explicit dated, corroborated identity is required
/// before requesting any stream. Neither catalog status emoji nor LIVE is fact.
actor CNCSportsAddonClient {
    static let shared = CNCSportsAddonClient()
    static let providerCode = "cncsports"
    static let manifestURL = URL(string: "https://cncverse.dpdns.org/manifest.json")!
    static let catalogID = "cnc_LivXowLiveEvents_tv"
    static let cricketCatalogID = "cnc_PlayZTVLiveEvents_tv"
    static let reviewedCricketHeaders = ["User-Agent": "Mozilla/5.0 (Linux; Android 10; Pixel 3 XL) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"]
    static let reviewedHeaders = [
        "Origin": "https://streame.center",
        "Referer": "https://streame.center/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36"
    ]

    struct Manifest: Decodable, Sendable {
        struct Catalog: Decodable, Sendable { let id: String; let type: String }
        struct Hints: Decodable, Sendable { let configurationRequired: Bool? }
        let id: String
        let version: String
        let resources: [String]
        let types: [String]
        let catalogs: [Catalog]
        let behaviorHints: Hints?
    }

    private struct CatalogDocument: Decodable {
        let metas: [CNCSportsCatalogEntry]
        private enum CodingKeys: String, CodingKey { case metas }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            var rows = try values.nestedUnkeyedContainer(forKey: .metas)
            var entries: [CNCSportsCatalogEntry] = []
            while !rows.isAtEnd {
                guard entries.count < 600 else { throw CommunitySportsAddonError.invalidResponse }
                let row = try rows.superDecoder()
                entries.append((try? CNCSportsCatalogEntry(from: row))
                    ?? .init(id: "", name: "", hasMalformedIdentity: true))
            }
            metas = entries
        }
    }
    private struct MetadataDocument: Decodable { let meta: CNCSportsMetadata }
    private struct StreamDocument: Decodable {
        let streams: [CNCSportsStreamEntry]
        let entryCount: Int
        private enum CodingKeys: String, CodingKey { case streams }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard values.contains(.streams), try !values.decodeNil(forKey: .streams) else {
                streams = []; entryCount = 0; return
            }
            var rows = try values.nestedUnkeyedContainer(forKey: .streams)
            var entries: [CNCSportsStreamEntry] = []; var count = 0
            while !rows.isAtEnd, count < 100 {
                let row = try rows.superDecoder(); count += 1
                if let entry = try? CNCSportsStreamEntry(from: row) { entries.append(entry) }
            }
            streams = entries; entryCount = count
        }
    }
    private struct Snapshot<Value> { let value: Value; let fetchedAt: Date }
    private let transport: FottyBoundedHTTPClient
    private let manifestTTL: TimeInterval
    private let catalogTTL: TimeInterval
    private let negativeCatalogTTL: TimeInterval
    private var manifestSnapshot: Snapshot<Manifest>?
    private var catalogSnapshot: Snapshot<[CNCSportsCatalogEntry]>?
    private var manifestGeneration: UUID?
    private var catalogGeneration: UUID?
    private var cricketCatalogSnapshot: Snapshot<[CNCSportsCatalogEntry]>?
    private var cricketCatalogGeneration: UUID?

    init(session: URLSession? = nil, manifestTTL: TimeInterval = 30 * 60,
         catalogTTL: TimeInterval = 2 * 60, negativeCatalogTTL: TimeInterval = 15) {
        transport = FottyBoundedHTTPClient(configuration: session?.configuration ?? Self.makeConfiguration())
        self.manifestTTL = manifestTTL; self.catalogTTL = catalogTTL; self.negativeCatalogTTL = negativeCatalogTTL
    }

    /// CNC's catalog has no reviewed date field. An exact NHL pair is a hint
    /// for Watch-time metadata verification, never a dated playable listing.
    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        try Task.checkCancellation()
        guard requests.count <= 256 else { throw CommunitySportsAddonError.invalidResponse }
        let supported: (StreamPlaybackRequest) -> Bool = { request in
            ReviewedSportsFixtureMatcher.sportKey(request.category) == "hockey"
                && request.preferredEvent?.hasCatalogIdentityConflict != true
                && (request.preferredEvent?.competitionID.map { $0.isEmpty || $0 == "nhl" } ?? true)
                && ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil
        }
        let needsHockey = requests.contains(where: supported)
        let needsCricket = requests.contains(where: Self.supportsReviewedCricket)
        guard needsHockey || needsCricket else {
            return requests.map { .init(matchID: $0.matchID,
                outcome: $0.preferredEvent?.hasCatalogIdentityConflict == true ? .conflicting : .unsupported) }
        }
        let manifest = try await loadManifest(now: now)
        var entries: [CNCSportsCatalogEntry] = []
        var cricketEntries: [CNCSportsCatalogEntry] = []
        var failures: [String: StreamFailureCategory] = [:]
        if needsHockey {
            do { entries = try await loadCatalog(now: now) }
            catch {
                try Task.checkCancellation()
                if CommunitySportsAddonClient.isFatalCatalogBatchError(error) { throw error }
                failures["hockey"] = CommunitySportsAddonClient.catalogBatchFailureCategory(error)
            }
        }
        if needsCricket {
            do {
                try Self.requireCricketCatalog(manifest)
                cricketEntries = try await loadCricketCatalog(now: now)
            } catch {
                try Task.checkCancellation()
                if CommunitySportsAddonClient.isFatalCatalogBatchError(error) { throw error }
                failures["cricket"] = CommunitySportsAddonClient.catalogBatchFailureCategory(error)
            }
        }
        try Task.checkCancellation()
        return try requests.map { request in
            try Task.checkCancellation()
            if request.preferredEvent?.hasCatalogIdentityConflict == true {
                return .init(matchID: request.matchID, outcome: .conflicting)
            }
            if Self.supportsReviewedCricket(request) {
                if let failure = failures["cricket"] { return .init(matchID: request.matchID, outcome: .failed(failure)) }
                do {
                    let ids = try Self.cricketCatalogIDs(for: request, from: cricketEntries)
                    return .init(matchID: request.matchID, outcome: ids.isEmpty ? .notListed : .needsVerification,
                        providerEventID: ids.count == 1 ? ids[0] : nil)
                } catch { return .init(matchID: request.matchID, outcome: .conflicting) }
            }
            guard supported(request) else { return .init(matchID: request.matchID, outcome: .unsupported) }
            if let failure = failures["hockey"] { return .init(matchID: request.matchID, outcome: .failed(failure)) }
            do {
                let ids = try Self.preselectedCatalogIDs(for: request, from: entries)
                return .init(matchID: request.matchID, outcome: ids.isEmpty ? .notListed : .needsVerification,
                             providerEventID: ids.count == 1 ? ids[0] : nil)
            } catch { return .init(matchID: request.matchID, outcome: .conflicting) }
        }
    }

    func resolve(for request: StreamPlaybackRequest, now: Date = Date(),
                 forceRefresh: Bool = false) async throws -> [StreamSession] {
        try Task.checkCancellation()
        if ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket" {
            return try await resolveCricket(for: request, now: now, forceRefresh: forceRefresh)
        }
        guard Self.supports(category: request.category),
              ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else {
            throw CommunitySportsAddonError.matchNotFound
        }
        let started = ProcessInfo.processInfo.systemUptime
        let manifest = try await loadManifest(now: now, forceRefresh: forceRefresh)
        let entries = try await loadCatalog(now: now, forceRefresh: forceRefresh)
        let ids = try Self.preselectedCatalogIDs(for: request, from: entries)
        guard !ids.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        let metadata = try await withThrowingTaskGroup(of: CNCSportsMetadata.self,
                                                       returning: [CNCSportsMetadata].self) { group in
            for id in ids {
                group.addTask {
                    let document: MetadataDocument = try await self.fetchJSON(MetadataDocument.self,
                        from: Self.route(["meta", "tv", id + ".json"]), stage: .metadata)
                    guard document.meta.id == id else { throw CommunitySportsAddonError.conflictingMatch }
                    return document.meta
                }
            }
            var rows: [CNCSportsMetadata] = []
            for try await row in group { rows.append(row) }
            return rows
        }
        try Task.checkCancellation()
        let selected = try Self.selectMetadata(for: request, catalog: entries, metadata: metadata,
            at: now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started))
        let document: StreamDocument = try await fetchJSON(StreamDocument.self,
            from: Self.route(["stream", "tv", selected.id + ".json"]), stage: .streams)
        guard document.entryCount > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        let sessions = Self.makeSessions(from: document.streams, request: request, addOnVersion: manifest.version)
        guard !sessions.isEmpty else {
            throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: document.entryCount)
        }
        try Task.checkCancellation()
        let completed = now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started)
        guard let binding = StreamEventBinding(request: request, providerCode: Self.providerCode,
            providerEventID: selected.id, streamID: selected.id, manifestRevision: manifest.version,
            verifiedAt: now, expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime),
            at: completed) else { throw CommunitySportsAddonError.conflictingMatch }
        return sessions.map { $0.recordingEventBinding(binding, for: request, at: completed) }
    }

    nonisolated static func preselectedCatalogIDs(for request: StreamPlaybackRequest,
                                                from entries: [CNCSportsCatalogEntry]) throws -> [String] {
        guard ReviewedSportsFixtureMatcher.sportKey(request.category) == "hockey", let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return [] }
        let wanted = ReviewedSportsFixtureMatcher.ParticipantIdentity(sport: requested.sport, pair: requested.pair)
        if let association = request.registryMatch,
           (association.broadcast.providerCode != Self.providerCode
            || association.broadcast.providerEventID != association.broadcast.streamID
            || !isSafeFixtureID(association.broadcast.providerEventID)) { return [] }
        let exact = entries.filter { row in
            (request.registryMatch.map { $0.broadcast.providerEventID == row.id } ?? true)
                && participantIdentity(title: cleanCatalogName(row.name)) == wanted
        }
        var ids: [String] = []
        for row in exact where !row.hasMalformedIdentity && row.type == "tv"
            && row.effectiveID == row.id && isSafeFixtureID(row.id) {
            if !ids.contains(row.id) { ids.append(row.id) }
        }
        guard ids.count <= 2 else { throw CommunitySportsAddonError.conflictingMatch }
        for id in ids {
            let siblings = entries.filter { $0.id == id || $0.effectiveID == id }
            guard siblings.allSatisfy({ !$0.hasMalformedIdentity && $0.type == "tv" && $0.id == id
                && $0.effectiveID == id && participantIdentity(title: cleanCatalogName($0.name)) == wanted }) else {
                throw CommunitySportsAddonError.conflictingMatch
            }
        }
        return ids
    }

    nonisolated static func selectMetadata(for request: StreamPlaybackRequest, catalog: [CNCSportsCatalogEntry],
                                         metadata: [CNCSportsMetadata], at now: Date = Date()) throws -> CNCSportsMetadata {
        let ids = try preselectedCatalogIDs(for: request, from: catalog)
        guard !ids.isEmpty, metadata.count == ids.count, Set(metadata.map(\.id)) == Set(ids) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let byID = Dictionary(metadata.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var candidates: [ReviewedSportsFixtureMatcher.Candidate] = []
        for row in catalog {
            var identity: ReviewedSportsFixtureMatcher.FixtureIdentity?
            if let meta = byID[row.id], !meta.hasMalformedIdentity, meta.type == "tv" {
                guard participantIdentity(title: meta.name) == participantIdentity(title: cleanCatalogName(row.name)) else {
                    throw CommunitySportsAddonError.conflictingMatch
                }
                if let kickoff = explicitKickoff(for: meta), let pair = participantIdentity(title: meta.name) {
                    let context = pair.sport == "cricket"
                        ? ReviewedSportsFixtureMatcher.cricketBroadcastContext(meta.name + "\n" + (meta.description ?? "")) : nil
                    identity = .init(sport: pair.sport, pair: pair.pair, kickoff: kickoff,
                                     effectiveID: row.effectiveID, resourceType: "tv", cricketFormat: context?.format,
                                     matchOrdinal: context?.ordinal, day: context?.day)
                }
            }
            candidates.append(.init(metadataID: row.id, effectiveID: row.effectiveID, identity: identity))
        }
        switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates, at: now) {
        case .matched(let index):
            guard let meta = byID[catalog[index].id] else { throw CommunitySportsAddonError.matchNotFound }
            return meta
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
    }

    nonisolated static func explicitKickoff(for entry: CNCSportsMetadata) -> Date? {
        guard !entry.hasMalformedIdentity, let description = entry.description, description.utf8.count <= 2048 else { return nil }
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 5, lines[0] == "📌 Hockey", lines[1] == "🏆 NHL", lines[3].isEmpty,
              lines[4].range(of: #"^📡 Available Servers: (?:[1-9][0-9]?|100)$"#, options: .regularExpression) != nil,
              lines[2].hasPrefix("🕐 ") else { return nil }
        return parseExplicitUTCClock(String(lines[2].dropFirst("🕐 ".count)))
    }

    nonisolated private static func parseExplicitUTCClock(_ raw: String) -> Date? {
        guard raw.range(of: #"^(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (?:0?[1-9]|[12][0-9]|3[01]), [0-9]{4} (?:[01][0-9]|2[0-3]):[0-5][0-9] UTC$"#,
                        options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = raw.dropFirst(4).first == "0" ? "MMM dd, yyyy HH:mm 'UTC'" : "MMM d, yyyy HH:mm 'UTC'"; formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    nonisolated private static func participantIdentity(title: String?) -> ReviewedSportsFixtureMatcher.ParticipantIdentity? {
        guard let title, !title.isEmpty, title.utf8.count <= 512,
              title.rangeOfCharacter(from: .controlCharacters) == nil,
              let parsed = ReviewedSportsFixtureMatcher.participantIdentity(sport: "hockey", cast: [], title: title) else { return nil }
        let pair = parsed.pair.map { key -> String in
            guard let name = nhlNames[key] else { return key }
            return SportsTeamIdentity.known(name: name, category: "hockey")?.id ?? SportsTeamIdentity.normalized(name)
        }.sorted()
        return .init(sport: parsed.sport, pair: pair)
    }

    // Exact NHL publisher nicknames. Only unqualified keys can match; meta still
    // has to agree on both participants, the league and the full UTC start.
    private static let nhlNames = [
        "blackhawks": "Chicago Blackhawks", "canadiens": "Montréal Canadiens", "capitals": "Washington Capitals",
        "flyers": "Philadelphia Flyers", "maple leafs": "Toronto Maple Leafs", "mammoth": "Utah Mammoth",
        "jets": "Winnipeg Jets", "oilers": "Edmonton Oilers", "devils": "New Jersey Devils",
        "red wings": "Detroit Red Wings", "lightning": "Tampa Bay Lightning", "blues": "St. Louis Blues",
        "rangers": "New York Rangers", "wild": "Minnesota Wild", "golden knights": "Vegas Golden Knights",
        "penguins": "Pittsburgh Penguins", "stars": "Dallas Stars", "avalanche": "Colorado Avalanche",
        "blue jackets": "Columbus Blue Jackets", "hurricanes": "Carolina Hurricanes", "predators": "Nashville Predators",
        "ducks": "Anaheim Ducks", "canucks": "Vancouver Canucks"
    ]

    nonisolated private static func cleanCatalogName(_ name: String) -> String? {
        guard name.utf8.count <= 512, name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        for prefix in ["🔴 ", "🔜 ", "✅ "] where name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        return name
    }

    private func loadManifest(now: Date, forceRefresh: Bool = false) async throws -> Manifest {
        if !forceRefresh, let snapshot = manifestSnapshot, Self.isFresh(snapshot.fetchedAt, at: now, ttl: manifestTTL) { return snapshot.value }
        let generation = UUID(); manifestGeneration = generation
        let data = try await fetchData(from: Self.manifestURL, stage: .manifest)
        let manifest = try Self.validateManifest(data: data); try Task.checkCancellation()
        if manifestGeneration == generation { manifestSnapshot = .init(value: manifest, fetchedAt: now) }
        return manifest
    }

    private func loadCatalog(now: Date, forceRefresh: Bool = false) async throws -> [CNCSportsCatalogEntry] {
        if !forceRefresh, let snapshot = catalogSnapshot, Self.isFresh(snapshot.fetchedAt, at: now,
            ttl: snapshot.value.isEmpty ? negativeCatalogTTL : catalogTTL) { return snapshot.value }
        let generation = UUID(); catalogGeneration = generation
        let document: CatalogDocument = try await fetchJSON(CatalogDocument.self,
            from: Self.route(["catalog", "tv", Self.catalogID + ".json"]), stage: .catalog)
        try Task.checkCancellation()
        if catalogGeneration == generation { catalogSnapshot = .init(value: document.metas, fetchedAt: now) }
        return document.metas
    }

    private func fetchJSON<Value: Decodable>(_ type: Value.Type, from url: URL,
                                            stage: CommunitySportsRequestStage) async throws -> Value {
        let data = try await fetchData(from: url, stage: stage)
        do { return try JSONDecoder().decode(type, from: data) }
        catch let failure as CommunitySportsAddonError { throw failure }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: stage) }
    }

    private func fetchData(from url: URL, stage: CommunitySportsRequestStage) async throws -> Data {
        guard Self.isSafeMetadataURL(url) else { throw CommunitySportsAddonError.unsafeResponse }
        var request = URLRequest(url: url); request.timeoutInterval = stage.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fotty/2.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        do {
            let response = try await transport.fetch(request, maximumBytes: 512 * 1024, deadline: stage.transportDeadline,
                redirectPolicy: { Self.isSafeMetadataURL($0) && Self.isSafeMetadataURL($1) })
            try Task.checkCancellation()
            guard Self.isSafeMetadataURL(response.http.url ?? url) else { throw CommunitySportsAddonError.unsafeResponse }
            return response.data
        } catch let failure as FottyBoundedHTTPClient.Failure {
            try Task.checkCancellation()
            if failure == .unsafeRedirect { throw CommunitySportsAddonError.unsafeResponse }
            if case .httpStatus(let status) = failure { throw CommunitySportsAddonError.httpFailure(statusCode: status, stage: stage) }
            throw CommunitySportsAddonError.invalidResponse
        } catch let error as URLError {
            try Task.checkCancellation()
            if error.code == .cancelled { throw error }
            throw CommunitySportsAddonError.transportFailure(code: error.errorCode, stage: stage)
        }
    }

    nonisolated static func validateManifest(data: Data) throws -> Manifest {
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: .manifest) }
        let resources = Set(manifest.resources); let types = Set(manifest.types)
        guard manifest.id == "com.cncverse.stremiobridge", safeVersion(manifest.version) != "unknown",
              manifest.behaviorHints?.configurationRequired != true,
              resources.isSuperset(of: ["catalog", "meta", "stream"]),
              resources.isSubset(of: ["catalog", "meta", "stream", "subtitles"]), resources.count == manifest.resources.count,
              types.contains("tv"), types.isSubset(of: ["movie", "series", "other", "tv"]), types.count == manifest.types.count,
              manifest.catalogs.count <= 64,
              manifest.catalogs.filter({ $0.id == Self.catalogID && $0.type == "tv" }).count == 1 else {
            throw CommunitySportsAddonError.invalidManifest
        }
        return manifest
    }

    nonisolated static func makeSessions(from streams: [CNCSportsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String) -> [StreamSession] {
        guard let definition = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode) else { return [] }
        let cricket = supportsReviewedCricket(request)
        var seen = Set<String>(); var sessions: [StreamSession] = []
        for entry in streams.prefix(100) {
            guard (cricket ? entry.isReviewedCricketContract : entry.isSupportedContract),
                  let name = entry.name, name.utf8.count <= 256,
                  // Foundation includes U+200D in controlCharacters, but the
                  // reviewed name contains that joiner in this exact emoji.
                  // Permit the observed sequence, not arbitrary format controls.
                  name.replacingOccurrences(of: "😮‍💨", with: "")
                    .rangeOfCharacter(from: .controlCharacters) == nil,
                  name.range(of: cricket ? #"^🎬PlayZTVProvider(?:\s|$)"# : #"^🎬LivXowProvider(?:\s|$)"#, options: .regularExpression) != nil,
                  let value = entry.url, let url = URL(string: value),
                  (cricket ? isAdmittedCricketDelivery(url) : isAdmittedDelivery(url)),
                  let headers = entry.requiredHeaders, (cricket ? isAdmittedCricketHeaders(headers) : headers == reviewedHeaders) else { continue }
            let key = sourceKey(url: url, headers: headers); guard seen.insert(key).inserted else { continue }
            guard let label = definition.sourceLabel(choice: sessions.count + 1) else { break }
            sessions.append(StreamSession(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: label, requiredHeaders: headers, qualityLabel: "Live video", canRefresh: false,
                validationStatus: .validated, diagnosticMetadata: ["source_family": providerCode,
                    "manifest_result": "exact_fixture_match", "delivery": "reviewed_direct_hls",
                    "addon_version": safeVersion(addOnVersion), "source_key": key, "source_key_scope": "delivery"],
                requiresGuardedRelay: true))
            if sessions.count == 6 { break }
        }
        return sessions
    }

    nonisolated static func isAdmittedDelivery(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "edgestream7.pro",
              url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.count <= 4096, !url.absoluteString.contains("%"), LocalStreamProxyPolicy.allowsDestination(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == url.path else { return false }
        return url.path.range(of: #"^/hls/[A-Za-z0-9_-]+\.m3u8$"#, options: .regularExpression) != nil
    }

    /// A timing allowance is not source authority. Recheck the complete reviewed
    /// contract rather than trusting an LS display name or provider metadata alone.
    nonisolated static func isReviewedNativeSession(_ session: StreamSession) -> Bool {
        session.diagnosticMetadata["source_family"] == providerCode
            && session.diagnosticMetadata["manifest_result"] == "exact_fixture_match"
            && session.diagnosticMetadata["delivery"] == "reviewed_direct_hls"
            && ["LS1", "LS2", "LS3", "LS4", "LS5", "LS6"].contains(session.providerName)
            && session.streamType == .hls && session.playbackContract.endpoint == .directMedia
            && isAdmittedDelivery(session.playableURL) && session.requiredHeaders == reviewedHeaders
            && session.requiresGuardedRelay == true && session.nativeOriginProfile == nil
            && session.nativePlaylistProfile == nil && !session.canRefresh
            && session.diagnosticMetadata["source_key"] == sourceKey(url: session.playableURL, headers: reviewedHeaders)
    }

    nonisolated static func sourceKey(url: URL, headers: [String: String]) -> String {
        let contract = headers.keys.sorted().map { "\($0):\(headers[$0]!)" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data((url.absoluteString + "\nheaders:\n" + contract).utf8))
        return "ls_" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func supports(category: String) -> Bool {
        ["hockey", "ice hockey", "nhl", "cricket"].contains(SportsTeamIdentity.normalized(category))
    }
    nonisolated static func isSafeFixtureID(_ value: String) -> Bool {
        value.utf8.count <= 4096 && value.range(of: #"^cnc:[A-Za-z0-9_-]+={0,2}$"#, options: .regularExpression) != nil
    }
    nonisolated static func isSafeMetadataURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "cncverse.dpdns.org"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil
    }
    nonisolated static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7; configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false; configuration.urlCredentialStorage = nil
        return configuration
    }
    nonisolated private static func route(_ components: [String]) -> URL {
        components.reduce(manifestURL.deletingLastPathComponent()) { $0.appendingPathComponent($1) }
    }
    nonisolated private static func safeVersion(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,23}$"#, options: .regularExpression) != nil ? value : "unknown"
    }
    nonisolated private static func isFresh(_ date: Date, at now: Date, ttl: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date); return age >= 0 && age < ttl
    }
}

// PlayZTV's WBBL lane is deliberately separate from the accepted LivXow NHL
// contract. An advertised channel alone cannot identify the match being played.
extension CNCSportsAddonClient {
    nonisolated static func supportsReviewedCricket(_ request: StreamPlaybackRequest) -> Bool {
        guard ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket",
              let event = request.preferredEvent, !event.hasCatalogIdentityConflict,
              let fixture = event.cricketFixture, fixture.verified, fixture.format == .t20, !fixture.status.stopsPlayback,
              event.id == request.matchID, event.kickoffDate == request.kickoffDate,
              event.id == CricketFixtureCatalog.fixtureIDPrefix + fixture.fixtureID,
              ["wbbl", "women's big bash league", "women’s big bash league"].contains(fixture.competitionName.lowercased()),
              ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else { return false }
        return true
    }

    private static func requireCricketCatalog(_ manifest: Manifest) throws {
        guard manifest.catalogs.filter({ $0.id == cricketCatalogID && $0.type == "tv" }).count == 1 else {
            throw CommunitySportsAddonError.invalidManifest
        }
    }

    nonisolated static func cricketCatalogIDs(for request: StreamPlaybackRequest,
                                              from entries: [CNCSportsCatalogEntry]) throws -> [String] {
        guard supportsReviewedCricket(request), entries.count <= 600,
              let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return [] }
        if let association = request.registryMatch,
           association.broadcast.providerCode != providerCode
            || association.broadcast.providerEventID != association.broadcast.streamID { return [] }
        func pair(_ row: CNCSportsCatalogEntry) -> [String]? {
            guard let title = cleanCatalogName(row.name) else { return nil }
            return ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket", cast: [], title: title)?.pair
        }
        var ids: [String] = []
        for row in entries where pair(row) == wanted.pair {
            guard request.registryMatch.map({ $0.broadcast.providerEventID == row.id }) ?? true else { continue }
            guard !row.hasMalformedIdentity, row.type == "tv", row.effectiveID == row.id,
                  isSafeFixtureID(row.id) else { continue }
            if !ids.contains(row.id) { ids.append(row.id) }
        }
        guard ids.count <= 2 else { throw CommunitySportsAddonError.conflictingMatch }
        for id in ids {
            guard entries.filter({ $0.id == id || $0.effectiveID == id }).allSatisfy({
                !$0.hasMalformedIdentity && $0.type == "tv" && $0.id == id && $0.effectiveID == id && pair($0) == wanted.pair
            }) else { throw CommunitySportsAddonError.conflictingMatch }
        }
        return ids
    }

    nonisolated static func explicitCricketKickoff(for meta: CNCSportsMetadata) -> Date? {
        guard !meta.hasMalformedIdentity, meta.type == "tv", let description = meta.description,
              description.utf8.count <= 2048 else { return nil }
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 5, lines[0] == "📌 Cricket", lines[1] == "🏆 Women's Big Bash League",
              lines[3].isEmpty, lines[4].range(of: #"^📡 Available Servers: (?:[1-9][0-9]?|100)$"#, options: .regularExpression) != nil,
              lines[2].hasPrefix("🕐 ") else { return nil }
        return parseExplicitUTCClock(String(lines[2].dropFirst("🕐 ".count)))
    }

    nonisolated static func selectCricketMetadata(for request: StreamPlaybackRequest,
        catalog: [CNCSportsCatalogEntry], metadata: [CNCSportsMetadata], at now: Date) throws -> CNCSportsMetadata {
        let ids = try cricketCatalogIDs(for: request, from: catalog)
        guard !ids.isEmpty, metadata.count == ids.count, Set(metadata.map(\.id)) == Set(ids),
              let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let byID = Dictionary(metadata.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = catalog.map { row -> ReviewedSportsFixtureMatcher.Candidate in
            var identity: ReviewedSportsFixtureMatcher.FixtureIdentity?
            if let meta = byID[row.id], let start = explicitCricketKickoff(for: meta), start == wanted.kickoff,
               let catalogTitle = cleanCatalogName(row.name),
               let fromCatalog = ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket", cast: [], title: catalogTitle),
               let fromMeta = ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket", cast: [], title: meta.name),
               fromCatalog == fromMeta, fromMeta.pair == wanted.pair {
                identity = .init(sport: "cricket", pair: fromMeta.pair, kickoff: start,
                    effectiveID: row.effectiveID, resourceType: "tv", cricketFormat: "T20")
            }
            return .init(metadataID: row.id, effectiveID: row.effectiveID, identity: identity)
        }
        switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates, at: now) {
        case .matched(let index):
            guard let meta = byID[catalog[index].id] else { throw CommunitySportsAddonError.matchNotFound }
            return meta
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
    }

    nonisolated static func isAdmittedCricketHeaders(_ headers: [String: String]) -> Bool {
        // User-Agent is the only advertised header. Keep it bounded and free
        // of control characters without pinning a harmless browser version.
        guard Set(headers.keys) == ["User-Agent"], let value = headers["User-Agent"],
              value.hasPrefix("Mozilla/5.0 "), value.utf8.count <= 512,
              value.utf8.allSatisfy({ (32...126).contains($0) }) else { return false }
        return true
    }

    nonisolated static func isAdmittedCricketDelivery(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "bl.rutube.ru", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.absoluteString.utf8.count <= 2048, LocalStreamProxyPolicy.allowsDestination(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == url.path,
              url.path.range(of: #"^/livestream/[a-f0-9]{32}/index\.m3u8$"#, options: .regularExpression) != nil,
              let query = components.queryItems, query.count == 3,
              Set(query.map(\.name)) == ["s", "e", "scheme"],
              query.first(where: { $0.name == "scheme" })?.value == "https",
              let signature = query.first(where: { $0.name == "s" })?.value,
              signature.range(of: #"^[A-Za-z0-9_-]{22}$"#, options: .regularExpression) != nil,
              let expiry = query.first(where: { $0.name == "e" })?.value,
              expiry.range(of: #"^[0-9]{10}$"#, options: .regularExpression) != nil,
              let deadline = TimeInterval(expiry), deadline > Date().timeIntervalSince1970 else { return false }
        return true
    }

    private func loadCricketCatalog(now: Date, forceRefresh: Bool = false) async throws -> [CNCSportsCatalogEntry] {
        if !forceRefresh, let snapshot = cricketCatalogSnapshot,
           Self.isFresh(snapshot.fetchedAt, at: now, ttl: snapshot.value.isEmpty ? negativeCatalogTTL : catalogTTL) {
            return snapshot.value
        }
        let generation = UUID(); cricketCatalogGeneration = generation
        let document = try await fetchJSON(CatalogDocument.self,
            from: Self.route(["catalog", "tv", Self.cricketCatalogID + ".json"]), stage: .catalog)
        try Task.checkCancellation()
        if cricketCatalogGeneration == generation { cricketCatalogSnapshot = .init(value: document.metas, fetchedAt: now) }
        return document.metas
    }

    private func resolveCricket(for request: StreamPlaybackRequest, now: Date,
                                forceRefresh: Bool) async throws -> [StreamSession] {
        guard Self.supportsReviewedCricket(request) else { throw CommunitySportsAddonError.matchNotFound }
        let started = ProcessInfo.processInfo.systemUptime
        let manifest = try await loadManifest(now: now, forceRefresh: forceRefresh)
        try Self.requireCricketCatalog(manifest)
        let catalog = try await loadCricketCatalog(now: now, forceRefresh: forceRefresh)
        let ids = try Self.cricketCatalogIDs(for: request, from: catalog)
        guard !ids.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        var metadata: [CNCSportsMetadata] = []
        for id in ids {
            let document = try await fetchJSON(MetadataDocument.self,
                from: Self.route(["meta", "tv", id + ".json"]), stage: .metadata)
            guard document.meta.id == id else { throw CommunitySportsAddonError.conflictingMatch }
            metadata.append(document.meta)
        }
        let selected = try Self.selectCricketMetadata(for: request, catalog: catalog, metadata: metadata,
            at: now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started))
        let streams = try await fetchJSON(StreamDocument.self,
            from: Self.route(["stream", "tv", selected.id + ".json"]), stage: .streams)
        guard streams.entryCount > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        let sessions = Self.makeSessions(from: streams.streams, request: request, addOnVersion: manifest.version)
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: streams.entryCount) }
        try Task.checkCancellation()
        let completed = now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started)
        guard let binding = StreamEventBinding(request: request, providerCode: Self.providerCode,
            providerEventID: selected.id, streamID: selected.id, manifestRevision: manifest.version,
            verifiedAt: now, expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime), at: completed) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        return sessions.map { $0.recordingEventBinding(binding, for: request, at: completed) }
    }
}
