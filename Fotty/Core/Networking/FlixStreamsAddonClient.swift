import Foundation
import CryptoKit

struct FlixStreamsCatalogEntry: Decodable, Sendable, Equatable {
    let id: String
    let type: String?
    let name: String
    let description: String?
    let genres: [String]?
    let hasMalformedIdentity: Bool
    let videoReleasedDate: Date?

    init(id: String, type: String? = "tv", name: String, description: String?,
         genres: [String]?, hasMalformedIdentity: Bool = false, videoReleasedDate: Date? = nil) {
        self.id = id; self.type = type; self.name = name
        self.description = description; self.genres = genres
        self.hasMalformedIdentity = hasMalformedIdentity
        self.videoReleasedDate = videoReleasedDate
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, description, genres, released, releaseInfo, cast, behaviorHints, videos
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private struct PlaybackHints: Decodable {
        let defaultVideoId: String
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            guard Set(values.allKeys.map(\.stringValue)) == Set(["defaultVideoId"]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreviewed playback hints"))
            }
            defaultVideoId = try values.decode(String.self, forKey: Key(stringValue: "defaultVideoId")!)
        }
    }

    private struct Video: Decodable {
        let id: String
        let released: Date
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            func key(_ value: String) -> Key { Key(stringValue: value)! }
            guard Set(values.allKeys.map(\.stringValue)) == Set(["id", "released", "title", "season", "episode"]),
                  try values.decode(String.self, forKey: key("title")) == "Live Stream" else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreviewed video contract"))
            }
            id = try values.decode(String.self, forKey: key("id"))
            // Positions are inert Stremio metadata, never source routing.
            _ = try values.decode(Int.self, forKey: key("season"))
            _ = try values.decode(Int.self, forKey: key("episode"))
            let raw = try values.decode(String.self, forKey: key("released"))
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:00\.000Z$"#,
                            options: .regularExpression) != nil,
                  let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreviewed video date"))
            }
            released = date
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Identifiable malformed siblings remain conflict evidence. Reviewed
        // Stremio hints/videos corroborate, never replace, the event's target.
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        type = try? values.decode(String.self, forKey: .type)
        name = (try? values.decode(String.self, forKey: .name)) ?? ""
        description = try? values.decode(String.self, forKey: .description)
        genres = try? values.decode([String].self, forKey: .genres)
        var malformed = id.isEmpty || type == nil || name.isEmpty || description == nil
            || genres == nil || [CodingKeys.released, .releaseInfo, .cast].contains(where: values.contains)
        if values.contains(.behaviorHints) {
            let hints = try? values.decode(PlaybackHints.self, forKey: .behaviorHints)
            malformed = malformed || hints?.defaultVideoId != id
        }
        var videoDate: Date?
        if values.contains(.videos) {
            if let videos = try? values.decode([Video].self, forKey: .videos), videos.count == 1, videos[0].id == id {
                videoDate = videos[0].released
            } else { malformed = true }
        }
        videoReleasedDate = videoDate
        hasMalformedIdentity = malformed
    }
}

enum FlixStreamsMatchSelection: Equatable {
    case matched(FlixStreamsCatalogEntry)
    case missing
    case conflicting
}

struct FlixStreamsStreamEntry: Decodable, Sendable {
    let url: String?
    /// nil preserves an invalid advertised header contract for row-level rejection.
    let requestedHeaders: [String: String]?
    let requiresDRM: Bool

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        func key(_ name: String) -> Key { Key(stringValue: name)! }
        url = try? values.decodeIfPresent(String.self, forKey: key("url"))
        requestedHeaders = try? StreamDeliveryPolicy.decodeRequestHeaders(from: decoder)
        requiresDRM = StreamDeliveryPolicy.decodeRequiresDRM(from: decoder)
    }
}

/// Optional, fixed-origin Stremio adapter. Only explicitly dated two-team rows
/// add deliveries to an existing Fotty fixture; channels never create matches.
actor FlixStreamsAddonClient {
    static let shared = FlixStreamsAddonClient()
    static let providerCode = "flixstreams"
    static let manifestURL = URL(string: "https://free.flixnest.app/manifest.json")!
    static let catalogID = "essential-live-events"
    // Literal labels observed in the reviewed feed, joined to existing official
    // competitions. Similar reserve/women/second-tier labels do not inherit it.
    nonisolated static let footballCompetitions: [String: String] = [
        "England - Premier League": "premier-league", "UEFA Champions League": "champions-league",
        "Europe - UEFA Champions League": "champions-league", "Italy - Serie A": "serie-a",
        "France - Ligue 1": "ligue-1", "Germany - Bundesliga": "bundesliga", "Bundesliga": "bundesliga", "Spain - La Liga": "la-liga"
    ]

    struct Manifest: Decodable, Sendable {
        struct Catalog: Decodable, Sendable {
            struct Extra: Decodable, Sendable {
                let name: String
                let isRequired: Bool?
                let options: [String]?
            }
            let id: String
            let type: String
            let extra: [Extra]?
        }
        struct Hints: Decodable, Sendable { let configurationRequired: Bool? }
        let id: String
        let version: String
        let resources: [String]
        let types: [String]?
        let catalogs: [Catalog]
        let behaviorHints: Hints?
    }

    private struct CatalogDocument: Decodable {
        let metas: [FlixStreamsCatalogEntry]
        private enum CodingKeys: String, CodingKey { case metas }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            var rows = try values.nestedUnkeyedContainer(forKey: .metas)
            var entries: [FlixStreamsCatalogEntry] = []
            while !rows.isAtEnd {
                guard entries.count < 40 else { throw CommunitySportsAddonError.invalidResponse }
                let row = try rows.superDecoder()
                if let entry = try? FlixStreamsCatalogEntry(from: row) { entries.append(entry) }
                else { entries.append(.init(id: "", name: "", description: nil, genres: nil,
                                            hasMalformedIdentity: true)) }
            }
            metas = entries
        }
    }

    private struct StreamDocument: Decodable, Sendable {
        let streams: [FlixStreamsStreamEntry]
        let entryCount: Int
        let malformedCount: Int
        let unexaminedCount: Int
        private enum CodingKeys: String, CodingKey { case streams }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard values.contains(.streams), try !values.decodeNil(forKey: .streams) else {
                streams = []; entryCount = 0; malformedCount = 0; unexaminedCount = 0; return
            }
            var rows = try values.nestedUnkeyedContainer(forKey: .streams)
            let offered = rows.count
            var entries: [FlixStreamsStreamEntry] = []
            var scanned = 0
            while !rows.isAtEnd, scanned < StreamDeliveryPolicy.maximumSessionsPerProvider {
                let row = try rows.superDecoder(); scanned += 1
                if let entry = try? FlixStreamsStreamEntry(from: row) { entries.append(entry) }
            }
            streams = entries; entryCount = offered ?? scanned
            malformedCount = scanned - entries.count
            unexaminedCount = entryCount - scanned
        }

        func observe(in ledger: inout StreamAdmissionLedger) {
            ledger.observe(entryCount)
            ledger.record("malformed", count: malformedCount)
            ledger.record("limit", count: unexaminedCount)
        }
    }

    private struct Snapshot<Value> { let value: Value; let fetchedAt: Date }
    private let qualityStore: FottyQualityStore
    private let transport: FottyBoundedHTTPClient
    private let manifestTTL: TimeInterval
    private let catalogTTL: TimeInterval
    private let negativeCatalogTTL: TimeInterval
    private var manifestSnapshot: Snapshot<Manifest>?
    private var manifestGeneration: UUID?
    private var catalogSnapshots: [String: Snapshot<[FlixStreamsCatalogEntry]>] = [:]
    private var catalogGenerations: [String: UUID] = [:]

    init(session: URLSession? = nil, manifestTTL: TimeInterval = 30 * 60,
         catalogTTL: TimeInterval = 120, negativeCatalogTTL: TimeInterval = 15, qualityStore: FottyQualityStore = .shared) {
        self.qualityStore = qualityStore
        transport = FottyBoundedHTTPClient(configuration: session?.configuration ?? Self.makeConfiguration())
        self.manifestTTL = manifestTTL; self.catalogTTL = catalogTTL
        self.negativeCatalogTTL = negativeCatalogTTL
    }

    /// One complete reviewed catalog read per requested genre, then pure
    /// fixture mapping. Browsing never retrieves a descriptor or media URL.
    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        try Task.checkCancellation()
        guard requests.count <= 256 else { throw CommunitySportsAddonError.invalidResponse }
        let eligible = requests.filter { Self.supports(request: $0)
            && $0.preferredEvent?.hasCatalogIdentityConflict != true
            && ReviewedSportsFixtureMatcher.requestIdentity(for: $0) != nil }
        var entries: [String: [FlixStreamsCatalogEntry]] = [:]
        var candidates: [String: [ReviewedSportsFixtureMatcher.Candidate]] = [:]
        var failures: [String: StreamFailureCategory] = [:]
        if !eligible.isEmpty {
            _ = try await loadManifest(now: now)
            let genres = Set(eligible.map { ReviewedSportsFixtureMatcher.sportKey($0.category) == "cricket" ? "cricket" : "soccer" })
            for genre in genres.sorted() {
                do {
                    let catalog = try await loadCatalog(genre: genre, now: now)
                    entries[genre] = catalog
                    candidates[genre] = Self.catalogCandidates(catalog)
                } catch {
                    try Task.checkCancellation()
                    if CommunitySportsAddonClient.isFatalCatalogBatchError(error) { throw error }
                    // A failed page makes this entire genre unverified, but
                    // cannot erase another complete genre's catalog evidence.
                    failures[genre] = CommunitySportsAddonClient.catalogBatchFailureCategory(error)
                }
            }
        }
        try Task.checkCancellation()
        return try requests.map { request in
            try Task.checkCancellation()
            if request.preferredEvent?.hasCatalogIdentityConflict == true {
                return .init(matchID: request.matchID, outcome: .conflicting)
            }
            let genre = ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket" ? "cricket" : "soccer"
            guard Self.supports(request: request),
                  ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else {
                return .init(matchID: request.matchID, outcome: .unsupported)
            }
            if let category = failures[genre] { return .init(matchID: request.matchID, outcome: .failed(category)) }
            guard let catalog = entries[genre], let parsed = candidates[genre] else {
                return .init(matchID: request.matchID, outcome: .unsupported)
            }
            let selection = Self.listingSelection(for: request, entries: catalog, candidates: parsed)
            if let first = selection.indices.first {
                return .init(matchID: request.matchID, outcome: .listed, providerEventID: catalog[first].id)
            }
            return .init(matchID: request.matchID, outcome: selection.conflict ? .conflicting : .notListed)
        }
    }

    func resolve(for request: StreamPlaybackRequest, now: Date = Date(),
                 forceRefresh: Bool = false) async throws -> [StreamSession] {
        var ledger = StreamAdmissionLedger(), fetchFailures = 0
        var returned = 0, limited = false, completion = "failed"
        defer {
            ledger.finish(admitted: returned, completion: completion)
            qualityStore.recordStreamAdmission(sourceFamily: Self.providerCode, ledger: ledger,
                completion: completion, fetchFailures: fetchFailures)
        }
        do {
            let sessions = try await resolveAdmission(for: request, now: now, forceRefresh: forceRefresh,
                ledger: &ledger, fetchFailures: &fetchFailures, limited: &limited)
            returned = sessions.count
            completion = fetchFailures > 0 ? "partial" : (limited || ledger.dispositions["limit", default: 0] > 0 ? "limited" : "complete")
            return sessions
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                completion = "cancelled"
            } else {
                if fetchFailures == 0, Self.isAdmissionFetchFailure(error) { fetchFailures = 1 }
                switch error as? CommunitySportsAddonError {
                case .lookupBudgetExhausted?: completion = fetchFailures > 0 ? "partial" : "limited"
                case .streamEntriesEmpty?, .streamAdmissionRejected?:
                    completion = fetchFailures > 0 ? "partial" : (limited || ledger.dispositions["limit", default: 0] > 0 ? "limited" : "complete")
                default: completion = ledger.hasObservedResponse && fetchFailures > 0 ? "partial" : "failed"
                }
            }
            throw error
        }
    }

    private nonisolated static func isAdmissionFetchFailure(_ error: Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
        switch error as? CommunitySportsAddonError {
        case .httpFailure?, .transportFailure?, .invalidJSON?, .invalidResponse?, .unsafeResponse?, .unsafeMetadata?: return true
        default: return error is URLError
        }
    }

    private func resolveAdmission(for request: StreamPlaybackRequest, now: Date,
        forceRefresh: Bool, ledger: inout StreamAdmissionLedger, fetchFailures: inout Int,
        limited: inout Bool) async throws -> [StreamSession] {
        let started = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        guard Self.supports(request: request),
              request.preferredEvent?.hasCatalogIdentityConflict != true,
              ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else {
            throw CommunitySportsAddonError.matchNotFound
        }
        let isRegistered = request.registryMatch != nil
        // Registered identity and explicit Retry both require current metadata.
        // Re-read every page so malformed/conflicting siblings keep their veto.
        let refreshMetadata = isRegistered || forceRefresh
        let manifest = try await loadManifest(now: now, forceRefresh: refreshMetadata)
        let genre = ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket" ? "cricket" : "soccer"
        let entries = try await loadCatalog(genre: genre, now: now, forceRefresh: refreshMetadata)
        let listings = Self.selectAllMatches(for: request, from: entries)
        guard !listings.isEmpty else {
            if case .conflicting = Self.selectMatch(for: request, from: entries) { throw CommunitySportsAddonError.conflictingMatch }
            throw CommunitySportsAddonError.matchNotFound
        }
        var all: [StreamSession] = []
        limited = listings.count > Self.maximumListings
        var firstFailure: Error?
        for listing in listings.prefix(Self.maximumListings) {
            let document: StreamDocument
            do {
                document = try await fetchJSON(StreamDocument.self,
                    from: Self.route(["stream", "tv", listing.id + ".json"]), stage: .streams)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if Self.isAdmissionFetchFailure(error) { fetchFailures += 1 }
                firstFailure = firstFailure ?? error; continue
            }
            document.observe(in: &ledger)
            // A registered request binds each stream to the exact listing it came from.
            let binding = isRegistered ? StreamEventBinding(request: request, providerCode: Self.providerCode,
                providerEventID: listing.id, streamID: listing.id, manifestRevision: manifest.version,
                verifiedAt: now, expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime), at: now) : nil
            if isRegistered, binding == nil { ledger.record("fixture_changed", count: document.streams.count); continue }
            all += Self.makeSessions(from: document.streams, request: request, addOnVersion: manifest.version,
                                     eventBinding: binding, at: now, after: all, ledger: &ledger)
        }
        try Task.checkCancellation()
        if all.isEmpty, let firstFailure { throw firstFailure }
        let completed = now.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - started))
        if isRegistered, !all.allSatisfy({ $0.eventBinding?.matches(request: request,
            providerCode: Self.providerCode, at: completed) == true }) {
            throw CommunitySportsAddonError.conflictingMatch
        }
        guard ledger.offered > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        guard !all.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: ledger.offered) }
        return all
    }

    private func loadManifest(now: Date, forceRefresh: Bool = false) async throws -> Manifest {
        if !forceRefresh, let snapshot = manifestSnapshot, Self.isFresh(snapshot.fetchedAt, at: now, ttl: manifestTTL) {
            return snapshot.value
        }
        let generation = UUID(); manifestGeneration = generation
        let data = try await fetchData(from: Self.manifestURL, stage: .manifest)
        let manifest = try Self.validateManifest(data: data)
        try Task.checkCancellation()
        if manifestGeneration == generation { manifestSnapshot = .init(value: manifest, fetchedAt: now) }
        return manifest
    }

    private func loadCatalog(genre: String, now: Date, forceRefresh: Bool = false) async throws -> [FlixStreamsCatalogEntry] {
        if !forceRefresh, let snapshot = catalogSnapshots[genre], Self.isFresh(snapshot.fetchedAt, at: now,
            ttl: snapshot.value.isEmpty ? negativeCatalogTTL : catalogTTL) { return snapshot.value }
        let generation = UUID(); catalogGenerations[genre] = generation
        var entries: [FlixStreamsCatalogEntry] = []
        // Search is advertised but currently ignored. Complete all three
        // reviewed 40-row pages before matching, including later veto evidence.
        for skip in [0, 40, 80] {
            try Task.checkCancellation()
            let extra = "genre=\(genre)" + (skip == 0 ? "" : "&skip=\(skip)")
            let document: CatalogDocument = try await fetchJSON(CatalogDocument.self,
                from: Self.route(["catalog", "tv", Self.catalogID, extra + ".json"]), stage: .catalog)
            entries.append(contentsOf: document.metas)
        }
        try Task.checkCancellation()
        if catalogGenerations[genre] == generation { catalogSnapshots[genre] = .init(value: entries, fetchedAt: now) }
        return entries
    }

    private func fetchJSON<Value: Decodable>(_ type: Value.Type, from url: URL,
                                            stage: CommunitySportsRequestStage) async throws -> Value {
        let data = try await fetchData(from: url, stage: stage)
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as CommunitySportsAddonError { throw error }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: stage) }
    }

    private func fetchData(from url: URL, stage: CommunitySportsRequestStage) async throws -> Data {
        guard Self.isSafeMetadataURL(url) else { throw CommunitySportsAddonError.unsafeResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = stage.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fotty/2.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        let byteLimit = stage == .manifest ? 128 * 1024 : stage == .streams ? 256 * 1024 : 512 * 1024
        do {
            let result = try await transport.fetch(request, maximumBytes: byteLimit,
                deadline: stage.transportDeadline, redirectPolicy: { from, to in
                    // A new path/configuration is a new contract, not a redirect
                    // exemption. No off-origin or endpoint-changing redirect.
                    Self.isSafeMetadataURL(from) && Self.isSafeMetadataURL(to) && from.path == to.path
                })
            try Task.checkCancellation()
            guard Self.isSafeMetadataURL(result.http.url ?? url), (result.http.url ?? url).path == url.path else {
                throw CommunitySportsAddonError.unsafeResponse
            }
            return result.data
        } catch let failure as FottyBoundedHTTPClient.Failure {
            try Task.checkCancellation()
            if failure == .unsafeRedirect { throw CommunitySportsAddonError.unsafeResponse }
            if case .httpStatus(let code) = failure {
                throw CommunitySportsAddonError.httpFailure(statusCode: code, stage: stage)
            }
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
        let events = manifest.catalogs.filter { $0.id == catalogID && $0.type == "tv" }
        let extras = events.first?.extra ?? []
        guard manifest.id == "org.flixstreams.free", safeVersion(manifest.version) != "unknown",
              Set(manifest.resources) == Set(["catalog", "meta", "stream"]), manifest.resources.count == 3,
              manifest.behaviorHints?.configurationRequired != true,
              manifest.types == nil || manifest.types?.contains("tv") == true,
              manifest.catalogs.count <= 16, events.count == 1,
              extras.count <= 8, Set(extras.map(\.name)).count == extras.count,
              extras.allSatisfy({ $0.isRequired != true }),
              extras.contains(where: { $0.name == "skip" }),
              extras.contains(where: { $0.name == "genre" && $0.options?.contains("soccer") == true
                  && $0.options?.contains("cricket") == true }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        return manifest
    }

    nonisolated static let maximumCatalogEntries = 400
    nonisolated static let maximumListings = 6

    /// Every exact listing of the requested game (registered requests keep one).
    nonisolated static func selectAllMatches(for request: StreamPlaybackRequest,
                                            from entries: [FlixStreamsCatalogEntry]) -> [FlixStreamsCatalogEntry] {
        let entries = Array(entries.prefix(maximumCatalogEntries))
        let selection = listingSelection(for: request, entries: entries, candidates: catalogCandidates(entries))
        return selection.indices.map { entries[$0] }
    }

    nonisolated static func selectMatch(for request: StreamPlaybackRequest,
                                       from entries: [FlixStreamsCatalogEntry]) -> FlixStreamsMatchSelection {
        let entries = Array(entries.prefix(maximumCatalogEntries))
        let selection = listingSelection(for: request, entries: entries, candidates: catalogCandidates(entries))
        if let first = selection.indices.first { return .matched(entries[first]) }
        return selection.conflict ? .conflicting : .missing
    }

    nonisolated private static func listingSelection(for request: StreamPlaybackRequest,
        entries: [FlixStreamsCatalogEntry], candidates: [ReviewedSportsFixtureMatcher.Candidate]) -> (indices: [Int], conflict: Bool) {
        guard supports(request: request), request.preferredEvent?.hasCatalogIdentityConflict != true,
              let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return ([], false) }
        let matches: [Int]
        if request.registryMatch != nil {
            switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates) {
            case .matched(let index): matches = [index]
            case .missing: return ([], false)
            case .conflicting: return ([], true)
            }
        } else {
            matches = ReviewedSportsFixtureMatcher.selectAll(for: identity, from: candidates)
            if matches.isEmpty {
                return ([], ReviewedSportsFixtureMatcher.select(for: identity, from: candidates) == .conflicting)
            }
        }
        let eligible = matches.filter { matchesRequestedCompetition(request, selected: entries[$0], entries: entries) }
        return (eligible, eligible.isEmpty)
    }

    nonisolated private static func catalogCandidates(_ entries: [FlixStreamsCatalogEntry]) -> [ReviewedSportsFixtureMatcher.Candidate] {
        entries.map { entry in
            .init(metadataID: entry.id, effectiveID: entry.id, identity: fixtureIdentity(for: entry))
        }
    }

    nonisolated static func explicitKickoff(for entry: FlixStreamsCatalogEntry) -> Date? {
        guard !entry.hasMalformedIdentity, let description = entry.description, description.utf8.count <= 4096,
              !entry.name.isEmpty, entry.name.utf8.count <= 1024,
              stripReviewedFlags(entry.name) != nil else { return nil }
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 4, lines[0].hasPrefix("Category: "), lines[0].count > 10,
              lines[1].range(of: #"^Date: [0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01]) \(UTC\)$"#,
                             options: .regularExpression) != nil,
              lines[2].range(of: #"^Time: (?:[01][0-9]|2[0-3]):[0-5][0-9]$"#,
                             options: .regularExpression) != nil,
              lines[3].hasPrefix("Channels: "), lines[3].count > 10,
              lines.allSatisfy({ !containsControls($0) }) else { return nil }
        let dateText = String(lines[1].dropFirst(6).dropLast(6))
        let timeText = String(lines[2].dropFirst(6))
        let raw = dateText + " " + timeText
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw,
              entry.videoReleasedDate == nil || entry.videoReleasedDate == date else { return nil }
        return date
    }

    nonisolated private static func fixtureIdentity(
        for entry: FlixStreamsCatalogEntry
    ) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard !entry.hasMalformedIdentity, isSafeFixtureID(entry.id), entry.type == "tv",
              let date = explicitKickoff(for: entry), let title = stripReviewedFlags(entry.name),
              let description = entry.description else { return nil }
        let category = String(description.components(separatedBy: "\n")[0].dropFirst(10))
        let sport: String
        let prefix: String
        switch category {
        case "All Soccer Events ⚽": sport = "football"; prefix = "⚽ "
        case "Cricket 🏏": sport = "cricket"; prefix = "🏏 "
        default: return nil
        }
        guard entry.genres == ["Live TV", "Sports", category], title.hasPrefix(prefix) else { return nil }
        let parts = String(title.dropFirst(prefix.count)).components(separatedBy: " : ")
        guard parts.count == 2, !parts[0].isEmpty,
              title.range(of: #"(?i)\b(?:xtra\s*time|extra\s*time|watch\s*along|watchalong|preview|highlights?|replays?|simulcast|multicast)\b"#,
                          options: .regularExpression) == nil else { return nil }
        if sport == "football" {
            guard footballCompetitions[parts[0]] != nil else { return nil }
        }
        let teams = parts[1].components(separatedBy: " vs ").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard teams.count == 2, teams.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
              squadQualifiers(parts[0]).isSubset(of: squadQualifiers(teams[0])),
              squadQualifiers(parts[0]).isSubset(of: squadQualifiers(teams[1])) else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: sport, cast: teams,
            title: teams.joined(separator: " vs "), kickoff: date, effectiveID: entry.id, resourceType: "tv",
            programmeMetadata: sport == "cricket" ? title : nil)
    }

    /// Decoration is token-scoped. Exact country flags and the three reviewed
    /// tagged UK flags are removed; an unexpected format/control character is
    /// rejected, never blanket stripped into an apparently valid team name.
    nonisolated private static func stripReviewedFlags(_ raw: String) -> String? {
        let flags: Set<String> = [
            "🇿🇦", "🇮🇹", "🇨🇦", "🇺🇸", "🇬🇧", "🇪🇸", "🇫🇷", "🇩🇪", "🇵🇹", "🇳🇱", "🇧🇪", "🇹🇷", "🇨🇿", "🇸🇰", "🇦🇹", "🇨🇭",
            "🇭🇷", "🇷🇸", "🇩🇰", "🇳🇴", "🇸🇪", "🇫🇮", "🇵🇱", "🇬🇷", "🇷🇴", "🇭🇺", "🇺🇦", "🇨🇾", "🇦🇿", "🇮🇱", "🇮🇪", "🇮🇸",
            "🇯🇲", "🇹🇹", "🇧🇧", "🇬🇾", "🇱🇨", "🇦🇬", "🇰🇳", "🇻🇨", "🇬🇩", "🇩🇲", "🇳🇿", "🇮🇳", "🇵🇰", "🇧🇩", "🇱🇰", "🇦🇫",
            "🇿🇼", "🇳🇦", "🇳🇵", "🇦🇪", "🇭🇰", "🇴🇲", "🇵🇬", "🇦🇺", "🇰🇪", "🇺🇬", "🇸🇦", "🇶🇦", "🇲🇽", "🇧🇷", "🇦🇷", "🇨🇱",
            "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
            "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
            "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
        ]
        let tokens = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let stripped = tokens.filter { !flags.contains($0) }.joined(separator: " ")
        guard !containsControls(stripped), !stripped.unicodeScalars.contains(where: {
            (0x1F1E6...0x1F1FF).contains($0.value)
        }) else { return nil }
        return stripped
    }

    nonisolated private static func containsControls(_ raw: String) -> Bool {
        raw.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        }
    }

    nonisolated private static func squadQualifiers(_ raw: String) -> Set<String> {
        let value = SportsTeamIdentity.normalized(raw)
        let pattern = #"\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = value as NSString
        return Set(expression.matches(in: value, range: NSRange(location: 0, length: text.length)).map {
            let word = text.substring(with: $0.range).replacingOccurrences(of: " ", with: "")
            if ["women", "womens", "ladies", "w"].contains(word) { return "women" }
            if ["reserve", "reserves"].contains(word) { return "reserves" }
            return word.replacingOccurrences(of: "under", with: "u")
        })
    }

    nonisolated static func makeSessions(from streams: [FlixStreamsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String, eventBinding: StreamEventBinding? = nil,
                                        at now: Date = Date(), after earlier: [StreamSession] = []) -> [StreamSession] {
        var ledger = StreamAdmissionLedger()
        ledger.observe(streams.count)
        return makeSessions(from: streams, request: request, addOnVersion: addOnVersion, eventBinding: eventBinding, at: now, after: earlier, ledger: &ledger)
    }

    nonisolated static func makeSessions(from streams: [FlixStreamsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String, eventBinding: StreamEventBinding? = nil,
                                        at now: Date = Date(), after earlier: [StreamSession] = [], ledger: inout StreamAdmissionLedger) -> [StreamSession] {
        guard let definition = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode) else { ledger.record("validation", count: streams.count); return [] }
        if let eventBinding, !eventBinding.matches(request: request, providerCode: providerCode, at: now) {
            ledger.record("fixture_changed", count: streams.count); return []
        }
        var seen = Set(earlier.compactMap { $0.diagnosticMetadata["source_key"] })
        var sessions: [StreamSession] = []
        ledger.record("limit", count: max(0, streams.count - StreamDeliveryPolicy.maximumSessionsPerProvider))
        for entry in streams.prefix(StreamDeliveryPolicy.maximumSessionsPerProvider) {
            guard !entry.requiresDRM else { ledger.record("drm"); continue }
            guard let value = entry.url, !value.isEmpty else { ledger.record("no_url"); continue }
            guard let url = URL(string: value) else { ledger.record("malformed"); continue }
            if let reason = StreamDeliveryPolicy.publicRejection(url) { ledger.record(reason); continue }
            guard let requested = entry.requestedHeaders else { ledger.record("malformed_headers"); continue }
            guard let headers = StreamDeliveryPolicy.requestHeaders(requested) else {
                ledger.record(StreamDeliveryPolicy.headerRejection(requested) ?? "malformed_headers")
                continue
            }
            let key = sourceKey(url: url, headers: headers)
            guard seen.insert(key).inserted else { ledger.record("duplicate"); continue }
            guard let label = definition.sourceLabel(choice: earlier.count + sessions.count + 1) else {
                ledger.record("limit"); continue
            }
            ledger.record("admitted")
            sessions.append(.init(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: label, requiredHeaders: headers, qualityLabel: "Live video",
                canRefresh: false, validationStatus: .validated,
                diagnosticMetadata: ["source_family": providerCode, "manifest_result": "exact_fixture_match",
                    "delivery": "provider_direct_hls", "addon_version": safeVersion(addOnVersion),
                    "source_key": key, "source_key_scope": "delivery"], createdAt: now,
                requiresGuardedRelay: true, eventBinding: eventBinding))
        }
        return sessions
    }

    /// Safe to open (see StreamDeliveryPolicy); link shape is not judged.
    nonisolated static func isAdmittedDelivery(_ url: URL) -> Bool { StreamDeliveryPolicy.publicRejection(url) == nil }

    nonisolated static func sourceKey(url: URL, headers: [String: String] = [:]) -> String {
        let contract = headers.isEmpty ? "{}" : headers.keys.sorted().map { "\($0):\(headers[$0]!)" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data((url.absoluteString + "\nheaders:" + contract).utf8))
        return "fs_" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func supports(event: EventReference) -> Bool {
        let category = event.category ?? ""
        guard supports(category: category) else { return false }
        guard ReviewedSportsFixtureMatcher.sportKey(category) == "football",
              let competition = event.sportsFixture?.competitionID ?? event.competitionID else { return true }
        return Set(footballCompetitions.values).contains(competition)
    }

    nonisolated private static func supports(request: StreamPlaybackRequest) -> Bool {
        supports(category: request.category) && (request.preferredEvent.map { supports(event: $0) } ?? true)
    }

    nonisolated private static func matchesRequestedCompetition(_ request: StreamPlaybackRequest,
        selected: FlixStreamsCatalogEntry, entries: [FlixStreamsCatalogEntry]) -> Bool {
        guard ReviewedSportsFixtureMatcher.sportKey(request.category) == "football",
              let event = request.preferredEvent,
              let expected = event.sportsFixture?.competitionID ?? event.competitionID else { return true }
        // A same-ID sibling with a different explicit competition remains veto
        // evidence even when date and team normalization happen to agree.
        return entries.filter { $0.id == selected.id }.allSatisfy { entry in
            guard let title = stripReviewedFlags(entry.name), title.hasPrefix("⚽ ") else { return false }
            let parts = String(title.dropFirst(2)).components(separatedBy: " : ")
            return parts.count == 2 && footballCompetitions[parts[0]] == expected
        }
    }

    nonisolated static func supports(category: String) -> Bool {
        ["football", "cricket"].contains(ReviewedSportsFixtureMatcher.sportKey(category))
    }

    nonisolated private static func isSafeFixtureID(_ id: String) -> Bool {
        id.range(of: #"^dlstreams:event:[a-f0-9]{12}$"#, options: .regularExpression) != nil
    }

    nonisolated static func isSafeMetadataURL(_ url: URL) -> Bool {
        guard isSafeOrigin(url), url.query == nil, url.absoluteString.utf8.count <= 1024,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let path = parts.percentEncodedPath
        if path == "/manifest.json" { return true }
        if path.range(of: #"^/catalog/tv/essential-live-events/genre=(?:soccer|cricket)(?:&skip=(?:40|80))?\.json$"#,
                      options: .regularExpression) != nil { return true }
        let decoded = url.path
        return decoded.range(of: #"^/stream/tv/dlstreams:event:[a-f0-9]{12}\.json$"#,
                             options: .regularExpression) != nil
            && (path == decoded || path == decoded.replacingOccurrences(of: ":", with: "%3A"))
    }

    nonisolated private static func isSafeOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "free.flixnest.app"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil && url.fragment == nil
    }

    nonisolated private static func route(_ components: [String]) -> URL {
        components.reduce(manifestURL.deletingLastPathComponent()) { $0.appendingPathComponent($1) }
    }

    nonisolated private static func safeVersion(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,23}$"#, options: .regularExpression) != nil ? value : "unknown"
    }

    nonisolated static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7; configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    nonisolated private static func isFresh(_ date: Date, at now: Date, ttl: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < ttl
    }
}
