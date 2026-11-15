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
    let hasAlternateScheduleFields: Bool

    init(id: String, type: String? = "tv", name: String, description: String?,
         hasMalformedIdentity: Bool = false) {
        self.id = id; self.type = type; self.name = name; self.description = description
        self.hasMalformedIdentity = hasMalformedIdentity
        self.hasAlternateScheduleFields = false
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CNCSportsCodingKey.self)
        id = (try? values.decode(String.self, forKey: .init("id"))) ?? ""
        type = try? values.decode(String.self, forKey: .init("type"))
        name = (try? values.decode(String.self, forKey: .init("name"))) ?? ""
        description = try? values.decode(String.self, forKey: .init("description"))
        hasAlternateScheduleFields = ["released", "releaseInfo", "date", "startTime", "kickoff", "videos"]
            .contains { values.contains(.init($0)) }
        hasMalformedIdentity = id.isEmpty || type == nil || name.isEmpty || description == nil
            || values.contains(.init("behaviorHints"))
    }
}

struct CNCSportsStreamEntry: Decodable, Sendable {
    let name: String?
    let url: String?
    /// nil preserves an invalid advertised header contract for row-level rejection.
    let requiredHeaders: [String: String]?
    let requiresDRM: Bool

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CNCSportsCodingKey.self)
        func key(_ name: String) -> CNCSportsCodingKey { .init(name) }
        name = try? values.decodeIfPresent(String.self, forKey: key("name"))
        url = try? values.decodeIfPresent(String.self, forKey: key("url"))
        requiredHeaders = try? StreamDeliveryPolicy.decodeRequestHeaders(from: decoder)
        requiresDRM = StreamDeliveryPolicy.decodeRequiresDRM(from: decoder)
    }
}

/// Reviewed football, LivXow NHL and PlayZTV WBBL lanes. Catalog names bound
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
        struct Catalog: Decodable, Sendable {
            struct Extra: Decodable, Sendable { let name: String; let isRequired: Bool? }
            let id: String
            let type: String
            var extra: [Extra]? = nil
            var supportsSearch: Bool {
                extra?.contains { $0.name == "search" && $0.isRequired != true } == true
            }
        }
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
    private struct StreamDocument: Decodable, Sendable {
        let streams: [CNCSportsStreamEntry]
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
            var entries: [CNCSportsStreamEntry] = []
            var scanned = 0
            while !rows.isAtEnd, scanned < StreamDeliveryPolicy.maximumSessionsPerProvider {
                let row = try rows.superDecoder(); scanned += 1
                if let entry = try? CNCSportsStreamEntry(from: row) { entries.append(entry) }
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
    private var catalogSnapshot: Snapshot<[CNCSportsCatalogEntry]>?
    private var manifestGeneration: UUID?
    private var catalogGeneration: UUID?
    private var cricketCatalogSnapshot: Snapshot<[CNCSportsCatalogEntry]>?
    private var cricketCatalogGeneration: UUID?
    private var footballCursors: [String: Int] = [:]
    private var footballCursorOrder: [String] = []

    init(session: URLSession? = nil, manifestTTL: TimeInterval = 30 * 60,
         catalogTTL: TimeInterval = 2 * 60, negativeCatalogTTL: TimeInterval = 15, qualityStore: FottyQualityStore = .shared) {
        self.qualityStore = qualityStore
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
        let needsLivXow = requests.contains(where: supported)
        let needsCricket = requests.contains(where: Self.supportsReviewedCricket)
        guard needsLivXow || needsCricket else {
            return requests.map { .init(matchID: $0.matchID,
                outcome: $0.preferredEvent?.hasCatalogIdentityConflict == true ? .conflicting :
                    Self.supportsReviewedFootball($0) ? .needsVerification : .unsupported) }
        }
        let manifest = try await loadManifest(now: now)
        var entries: [CNCSportsCatalogEntry] = []
        var cricketEntries: [CNCSportsCatalogEntry] = []
        var failures: [String: StreamFailureCategory] = [:]
        if needsLivXow {
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
            if Self.supportsReviewedFootball(request) {
                // First pages do not exhaust football. Only a selected fixture
                // spends the two team searches, regardless of schedule size.
                return .init(matchID: request.matchID, outcome: .needsVerification)
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

    /// Foreground discovery may acknowledge independently admitted hockey or
    /// cricket choices before later stream reads finish. Football keeps its
    /// aggregate conflict checks; ordinary and renewal callers stay aggregate.
    func resolve(for request: StreamPlaybackRequest, now: Date = Date(),
                 forceRefresh: Bool = false,
                 onSession: (@Sendable (StreamSession) async -> Bool)? = nil) async throws -> [StreamSession] {
        var ledger = StreamAdmissionLedger(), fetchFailures = 0
        var returned = 0, acknowledged = 0, limited = false, completion = "failed"
        defer {
            ledger.finish(admitted: returned, completion: completion)
            qualityStore.recordStreamAdmission(sourceFamily: Self.providerCode, ledger: ledger,
                completion: completion, fetchFailures: fetchFailures)
        }
        do {
            let sessions = try await resolveAdmission(for: request, now: now, forceRefresh: forceRefresh,
                ledger: &ledger, fetchFailures: &fetchFailures, limited: &limited,
                onSession: onSession, acknowledged: &acknowledged)
            returned = sessions.count
            completion = fetchFailures > 0 ? "partial" : (limited || ledger.dispositions["limit", default: 0] > 0 ? "limited" : "complete")
            return sessions
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                // Cancellation still ends the lookup. Choices already handed
                // to its owner remain observed admissions, not withdrawals;
                // unread siblings contribute no invented offer count.
                returned = acknowledged
                completion = acknowledged > 0 ? "partial" : "cancelled"
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
        limited: inout Bool, onSession: (@Sendable (StreamSession) async -> Bool)?,
        acknowledged: inout Int) async throws -> [StreamSession] {
        try Task.checkCancellation()
        if ReviewedSportsFixtureMatcher.sportKey(request.category) == "football" {
            return try await resolveFootball(for: request, now: now, forceRefresh: forceRefresh,
                ledger: &ledger, fetchFailures: &fetchFailures, limited: &limited)
        }
        if ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket" {
            return try await resolveCricket(for: request, now: now, forceRefresh: forceRefresh,
                ledger: &ledger, fetchFailures: &fetchFailures, limited: &limited,
                onSession: onSession, acknowledged: &acknowledged)
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
        limited = ids.count > Self.maximumListings
        let metadata = try await fetchMetadata(Array(ids.prefix(Self.maximumListings)), fetchFailures: &fetchFailures)
        try Task.checkCancellation()
        let selected = try Self.selectAllMetadata(for: request, catalog: entries, metadata: metadata,
            at: now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started))
        return try await sessions(for: selected, request: request, manifest: manifest, now: now, started: started,
            ledger: &ledger, fetchFailures: &fetchFailures, onSession: onSession, acknowledged: &acknowledged)
    }

    /// Details for each listing; one that fails or names another id is left out.
    /// When none load, the first real failure is reported (never a generic miss).
    private func fetchMetadata(_ ids: [String], fetchFailures: inout Int) async throws -> [CNCSportsMetadata] {
        let results = await withTaskGroup(of: Result<CNCSportsMetadata, Error>.self,
                                          returning: [Result<CNCSportsMetadata, Error>].self) { group in
            for id in ids {
                group.addTask {
                    do {
                        let document = try await self.fetchJSON(MetadataDocument.self,
                            from: Self.route(["meta", "tv", id + ".json"]), stage: .metadata)
                        guard document.meta.id == id else { return .failure(CommunitySportsAddonError.conflictingMatch) }
                        return .success(document.meta)
                    } catch { return .failure(error) }
                }
            }
            var all: [Result<CNCSportsMetadata, Error>] = []
            for await result in group { all.append(result) }
            return all
        }
        fetchFailures += results.filter { result in
            if case .failure(let error) = result { return Self.isAdmissionFetchFailure(error) }
            return false
        }.count
        let rows = results.compactMap { try? $0.get() }
        if rows.isEmpty, case .failure(let error)? = results.first(where: { if case .failure = $0 { return true }; return false }) {
            throw error
        }
        return ids.compactMap { id in rows.first { $0.id == id } }
    }

    /// Streams from every matched listing, merged and numbered once.
    private func sessions(for listings: [CNCSportsMetadata], request: StreamPlaybackRequest, manifest: Manifest,
                          now: Date, started: TimeInterval, ledger: inout StreamAdmissionLedger,
                          fetchFailures: inout Int, onSession: (@Sendable (StreamSession) async -> Bool)?,
                          acknowledged: inout Int) async throws -> [StreamSession] {
        var all: [StreamSession] = []
        var firstFailure: Error?
        for listing in listings {
            try Task.checkCancellation()
            let document: StreamDocument
            do { document = try await fetchJSON(StreamDocument.self,
                from: Self.route(["stream", "tv", listing.id + ".json"]), stage: .streams) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if Self.isAdmissionFetchFailure(error) { fetchFailures += 1 }
                firstFailure = firstFailure ?? error; continue
            }
            try Task.checkCancellation()
            document.observe(in: &ledger)
            let completed = now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started)
            guard let binding = StreamEventBinding(request: request, providerCode: Self.providerCode,
                providerEventID: listing.id, streamID: listing.id, manifestRevision: manifest.version,
                verifiedAt: now, expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime),
                at: completed) else { ledger.record("fixture_changed", count: document.streams.count); continue }
            let made = Self.makeSessions(from: document.streams, request: request, addOnVersion: manifest.version, after: all, ledger: &ledger)
            let admitted = made.map { $0.recordingEventBinding(binding, for: request, at: completed) }
            all += admitted
            if let onSession {
                // All listing metadata has already passed selection. Keep its
                // established order/labels, and recheck each receipt after any
                // earlier callback suspension before handing it to the owner.
                for session in admitted {
                    try Task.checkCancellation()
                    let emittedAt = now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started)
                    guard !session.hasExpiredMediaLease(at: emittedAt),
                          session.eventBinding?.matches(request: request, providerCode: Self.providerCode,
                                                        at: emittedAt) == true else { continue }
                    if await onSession(session) { acknowledged += 1 }
                    try Task.checkCancellation()
                }
            }
        }
        try Task.checkCancellation()
        if all.isEmpty, let firstFailure { throw firstFailure }
        let completed = now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started)
        guard all.allSatisfy({ $0.eventBinding?.matches(request: request, providerCode: Self.providerCode, at: completed) == true })
        else { throw CommunitySportsAddonError.conflictingMatch }
        guard ledger.hasObservedResponse else { throw CommunitySportsAddonError.invalidResponse }
        guard ledger.offered > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        guard !all.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: ledger.offered) }
        return all
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
        // Every consistent listing counts; an id whose own rows disagree is dropped alone.
        return Array(ids.filter { id in
            entries.filter { $0.id == id || $0.effectiveID == id }.allSatisfy({ !$0.hasMalformedIdentity && $0.type == "tv"
                && $0.id == id && $0.effectiveID == id && participantIdentity(title: cleanCatalogName($0.name)) == wanted })
        })
    }

    nonisolated static let maximumListings = 6

    nonisolated static func selectMetadata(for request: StreamPlaybackRequest, catalog: [CNCSportsCatalogEntry],
                                         metadata: [CNCSportsMetadata], at now: Date = Date()) throws -> CNCSportsMetadata {
        guard let first = try selectAllMetadata(for: request, catalog: catalog, metadata: metadata, at: now).first else {
            throw CommunitySportsAddonError.matchNotFound
        }
        return first
    }

    /// Every listing whose own details identify the requested game.
    nonisolated static func selectAllMetadata(for request: StreamPlaybackRequest, catalog: [CNCSportsCatalogEntry],
                                            metadata: [CNCSportsMetadata], at now: Date = Date()) throws -> [CNCSportsMetadata] {
        let ids = Set(try preselectedCatalogIDs(for: request, from: catalog))
        let usable = metadata.filter { ids.contains($0.id) }
        guard !usable.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        let byID = Dictionary(usable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var candidates: [ReviewedSportsFixtureMatcher.Candidate] = []
        for row in catalog {
            var identity: ReviewedSportsFixtureMatcher.FixtureIdentity?
            if let meta = byID[row.id], !meta.hasMalformedIdentity, meta.type == "tv",
               participantIdentity(title: meta.name) == participantIdentity(title: cleanCatalogName(row.name)) {
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
        return try matchedMetadata(for: request, catalog: catalog, candidates: candidates, byID: byID, at: now)
    }

    /// Registry-bound requests keep their single registered listing; others take every exact listing.
    nonisolated static func matchedMetadata(for request: StreamPlaybackRequest, catalog: [CNCSportsCatalogEntry],
        candidates: [ReviewedSportsFixtureMatcher.Candidate], byID: [String: CNCSportsMetadata], at now: Date) throws -> [CNCSportsMetadata] {
        if request.registryMatch != nil {
            switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates, at: now) {
            case .matched(let index): return byID[catalog[index].id].map { [$0] } ?? []
            case .missing: throw CommunitySportsAddonError.matchNotFound
            case .conflicting: throw CommunitySportsAddonError.conflictingMatch
            }
        }
        guard let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { throw CommunitySportsAddonError.matchNotFound }
        var seen = Set<String>()
        let all = ReviewedSportsFixtureMatcher.selectAll(for: identity, from: candidates)
            .compactMap { byID[catalog[$0].id] }.filter { seen.insert($0.id).inserted }
        guard !all.isEmpty else {
            if case .conflicting = ReviewedSportsFixtureMatcher.select(for: request, from: candidates, at: now) {
                throw CommunitySportsAddonError.conflictingMatch
            }
            throw CommunitySportsAddonError.matchNotFound
        }
        return all
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

    private func loadManifest(now: Date, forceRefresh: Bool = false, football: Bool = false) async throws -> Manifest {
        if !forceRefresh, let snapshot = manifestSnapshot, Self.isFresh(snapshot.fetchedAt, at: now, ttl: manifestTTL) {
            try Self.requireCatalogs(in: snapshot.value, football: football)
            return snapshot.value
        }
        let generation = UUID(); manifestGeneration = generation
        let data = try await fetchData(from: Self.manifestURL, stage: .manifest)
        let manifest = try Self.validateManifest(data: data, football: football); try Task.checkCancellation()
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

    nonisolated static func validateManifest(data: Data, football: Bool = false) throws -> Manifest {
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: .manifest) }
        let resources = Set(manifest.resources); let types = Set(manifest.types)
        guard manifest.id == "com.cncverse.stremiobridge", safeVersion(manifest.version) != "unknown",
              manifest.behaviorHints?.configurationRequired != true,
              resources.isSuperset(of: ["catalog", "meta", "stream"]),
              resources.isSubset(of: ["catalog", "meta", "stream", "subtitles"]), resources.count == manifest.resources.count,
              types.contains("tv"), types.isSubset(of: ["movie", "series", "other", "tv"]), types.count == manifest.types.count,
              manifest.catalogs.count <= 64 else {
            throw CommunitySportsAddonError.invalidManifest
        }
        try requireCatalogs(in: manifest, football: football)
        return manifest
    }

    private nonisolated static func requireCatalogs(in manifest: Manifest, football: Bool) throws {
        let ids = football ? [catalogID, cricketCatalogID] : [catalogID]
        guard ids.contains(where: { id in manifest.catalogs.filter { $0.id == id && $0.type == "tv" }.count == 1 }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
    }

    nonisolated static func makeSessions(from streams: [CNCSportsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String, after earlier: [StreamSession] = []) -> [StreamSession] {
        var ledger = StreamAdmissionLedger()
        ledger.observe(streams.count)
        return makeSessions(from: streams, request: request, addOnVersion: addOnVersion, after: earlier, ledger: &ledger)
    }

    nonisolated static func makeSessions(from streams: [CNCSportsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String, after earlier: [StreamSession] = [], ledger: inout StreamAdmissionLedger) -> [StreamSession] {
        guard let definition = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode) else { ledger.record("validation", count: streams.count); return [] }
        var seen = Set(earlier.compactMap { $0.diagnosticMetadata["source_key"] })
        var sessions: [StreamSession] = []
        ledger.record("limit", count: max(0, streams.count - StreamDeliveryPolicy.maximumSessionsPerProvider))
        for entry in streams.prefix(StreamDeliveryPolicy.maximumSessionsPerProvider) {
            guard !entry.requiresDRM else { ledger.record("drm"); continue }
            guard let value = entry.url, !value.isEmpty else { ledger.record("no_url"); continue }
            guard let url = URL(string: value) else { ledger.record("malformed"); continue }
            if let reason = StreamDeliveryPolicy.publicRejection(url) { ledger.record(reason); continue }
            guard let requested = entry.requiredHeaders else { ledger.record("malformed_headers"); continue }
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
            sessions.append(StreamSession(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: label, requiredHeaders: headers, qualityLabel: "Live video", canRefresh: false,
                validationStatus: .validated, diagnosticMetadata: ["source_family": providerCode,
                    "manifest_result": "exact_fixture_match", "delivery": "provider_direct_hls",
                    "addon_version": safeVersion(addOnVersion), "source_key": key, "source_key_scope": "delivery"],
                requiresGuardedRelay: true))
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

    nonisolated static func isReviewedNativeSession(_ session: StreamSession) -> Bool {
        session.diagnosticMetadata["source_family"] == providerCode
            && session.diagnosticMetadata["manifest_result"] == "exact_fixture_match"
            && ["reviewed_direct_hls", "provider_direct_hls"].contains(session.diagnosticMetadata["delivery"] ?? "")
            && (session.eventBinding.map { ReviewedSportsFixtureMatcher.sportKey($0.sport) == "hockey" } ?? true)
            && CuratedStreamSourceCatalog.definition(forProviderCode: providerCode)?.sourceLabel(choice: Int(session.providerName.dropFirst(2)) ?? 0) == session.providerName
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
        ["hockey", "cricket", "football"].contains(ReviewedSportsFixtureMatcher.sportKey(category))
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
              // The competition line is what separates the women's and men's squads
              // in this catalog, so cricket stays limited to the reviewed league.
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
        return Array(ids.filter { id in
            entries.filter({ $0.id == id || $0.effectiveID == id }).allSatisfy({
                !$0.hasMalformedIdentity && $0.type == "tv" && $0.id == id && $0.effectiveID == id && pair($0) == wanted.pair })
        })
    }

    nonisolated static func explicitCricketKickoff(for meta: CNCSportsMetadata) -> Date? {
        guard !meta.hasMalformedIdentity, meta.type == "tv", let description = meta.description,
              description.utf8.count <= 2048 else { return nil }
        // The league line identifies the squad (women's vs men's); the clock line the kickoff.
        let lines = description.components(separatedBy: "\n")
        guard lines.contains("🏆 Women's Big Bash League") else { return nil }
        let clocks = lines.filter { $0.hasPrefix("🕐 ") }
        guard clocks.count == 1, let clock = clocks.first else { return nil }
        return parseExplicitUTCClock(String(clock.dropFirst("🕐 ".count)))
    }

    nonisolated static func selectCricketMetadata(for request: StreamPlaybackRequest,
        catalog: [CNCSportsCatalogEntry], metadata: [CNCSportsMetadata], at now: Date) throws -> CNCSportsMetadata {
        guard let first = try selectAllCricketMetadata(for: request, catalog: catalog, metadata: metadata, at: now).first else {
            throw CommunitySportsAddonError.matchNotFound
        }
        return first
    }

    nonisolated static func selectAllCricketMetadata(for request: StreamPlaybackRequest,
        catalog: [CNCSportsCatalogEntry], metadata: [CNCSportsMetadata], at now: Date) throws -> [CNCSportsMetadata] {
        let ids = Set(try cricketCatalogIDs(for: request, from: catalog))
        let usable = metadata.filter { ids.contains($0.id) }
        guard !usable.isEmpty, let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else {
            throw CommunitySportsAddonError.matchNotFound
        }
        let byID = Dictionary(usable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        return try matchedMetadata(for: request, catalog: catalog, candidates: candidates, byID: byID, at: now)
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
                                forceRefresh: Bool, ledger: inout StreamAdmissionLedger,
                                fetchFailures: inout Int, limited: inout Bool,
                                onSession: (@Sendable (StreamSession) async -> Bool)?,
                                acknowledged: inout Int) async throws -> [StreamSession] {
        guard Self.supportsReviewedCricket(request) else { throw CommunitySportsAddonError.matchNotFound }
        let started = ProcessInfo.processInfo.systemUptime
        let manifest = try await loadManifest(now: now, forceRefresh: forceRefresh)
        try Self.requireCricketCatalog(manifest)
        let catalog = try await loadCricketCatalog(now: now, forceRefresh: forceRefresh)
        let ids = try Self.cricketCatalogIDs(for: request, from: catalog)
        guard !ids.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        limited = ids.count > Self.maximumListings
        let metadata = try await fetchMetadata(Array(ids.prefix(Self.maximumListings)), fetchFailures: &fetchFailures)
        let selected = try Self.selectAllCricketMetadata(for: request, catalog: catalog, metadata: metadata,
            at: now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started))
        return try await sessions(for: selected, request: request, manifest: manifest, now: now, started: started,
            ledger: &ledger, fetchFailures: &fetchFailures, onSession: onSession, acknowledged: &acknowledged)
    }
}

// Both CNC catalogs mix sports. Football uses their advertised team search, then
// fresh same-ID metadata. A title alone is never an event or delivery binding.
extension CNCSportsAddonClient {
    nonisolated static func supportsReviewedFootball(_ request: StreamPlaybackRequest) -> Bool {
        guard let event = request.preferredEvent, let fixture = event.sportsFixture,
              !event.hasCatalogIdentityConflict, event.cricketFixture == nil,
              ReviewedSportsFixtureMatcher.sportKey(request.category) == "football",
              fixture.verified, fixture.sport == "football", fixture.eventKind == .match,
              !fixture.status.stopsPlayback, fixture.fixtureID == request.matchID,
              fixture.fixtureID == event.id, fixture.fixtureID.hasPrefix(SportsFixtureCatalog.fixtureIDPrefix + fixture.competitionID + ":"),
              !fixture.competitionID.isEmpty, !fixture.competitionName.isEmpty,
              event.kickoffDate == request.kickoffDate, fixture.participants.count == 2,
              fixture.squad.ageGroup == "senior", [.men, .women].contains(fixture.squad.gender),
              let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              BroadcastRegistrySnapshot.participantPair(fixture.participants.map(\.name), sport: "football") == wanted.pair else { return false }
        // Team identity uses "football|club-id" for known clubs, followed
        // by a separate "|women"/"|u20" suffix when the team is qualified.
        return wanted.pair.allSatisfy { key in
            let baseFields = key.hasPrefix("football|") ? 2 : 1
            let qualifiers = key.components(separatedBy: "|").dropFirst(baseFields)
            return fixture.squad.gender == .women ? Array(qualifiers) == ["women"] : qualifiers.isEmpty
        }
    }

    nonisolated static func footballReference(_ id: String) -> String {
        "cnc-observation:" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct FootballListingSelection {
        var ids: [String] = []
        var conflictingReferences = Set<String>()
    }

    private nonisolated static func footballListings(for request: StreamPlaybackRequest,
                                                      from entries: [CNCSportsCatalogEntry]) -> FootballListingSelection {
        var selected = FootballListingSelection()
        guard supportsReviewedFootball(request), entries.count <= 600,
              let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return selected }
        func pair(_ row: CNCSportsCatalogEntry) -> [String]? {
            guard let name = cleanCatalogName(row.name) else { return nil }
            return ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: name)?.pair
        }
        let pinned = request.registryMatch?.broadcast
        if let pinned, pinned.providerCode != providerCode || pinned.providerEventID != pinned.streamID { return selected }
        let byID = Dictionary(grouping: entries, by: \.id)
        let byTarget = Dictionary(grouping: entries, by: \.effectiveID)
        var seen = Set<String>(), otherIDs: [String] = []
        for row in entries where pair(row) == wanted.pair && isSafeFixtureID(row.id) {
            guard seen.insert(row.id).inserted else { continue }
            let reference = footballReference(row.id)
            guard pinned.map({ $0.providerEventID == reference }) ?? true else { continue }
            let siblings = (byID[row.id] ?? []) + (byTarget[row.id] ?? [])
            guard siblings.allSatisfy({ !$0.hasMalformedIdentity && $0.type == "tv" && $0.id == row.id
                && $0.effectiveID == row.id && pair($0) == wanted.pair }) else {
                selected.conflictingReferences.insert(reference)
                continue
            }
            // A live marker only orders bounded metadata checks. It supplies no match evidence.
            if siblings.contains(where: { $0.name.hasPrefix("🔴 ") }) { selected.ids.append(row.id) }
            else { otherIDs.append(row.id) }
        }
        selected.ids += otherIDs
        return selected
    }

    private func footballWindow<T>(_ candidates: [T], limit: Int, cursorKey: String) -> [T] {
        guard candidates.count > limit else { return candidates }
        let start = (footballCursors[cursorKey] ?? 0) % candidates.count
        if footballCursors[cursorKey] == nil {
            if footballCursorOrder.count >= 48 { footballCursors.removeValue(forKey: footballCursorOrder.removeFirst()) }
            footballCursorOrder.append(cursorKey)
        }
        footballCursors[cursorKey] = (start + limit) % candidates.count
        return (0..<limit).map { candidates[(start + $0) % candidates.count] }
    }

    /// cncLeague in the Worker matches the official competition ID, even when
    /// the publisher's full tournament name differs from our display label.
    nonisolated static func footballCompetitionID(_ label: String) -> String {
        let key = SportsTeamIdentity.normalized(label)
        switch key {
        case "uefa champions league": return "champions-league"
        case "english premier league", "english premier league epl": return "premier-league"
        case "major league soccer": return "mls"
        case "fifa friendlies", "international friendly": return "international-friendlies"
        default: return key.replacingOccurrences(of: " ", with: "-")
        }
    }

    nonisolated static func footballServerCount(for meta: CNCSportsMetadata, request: StreamPlaybackRequest) -> Int? {
        guard supportsReviewedFootball(request), let fixture = request.preferredEvent?.sportsFixture,
              !meta.hasMalformedIdentity, !meta.hasAlternateScheduleFields, meta.type == "tv", let description = meta.description,
              description.utf8.count <= 2048, let title = cleanCatalogName(meta.name),
              ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: title)?.pair ==
                ReviewedSportsFixtureMatcher.requestIdentity(for: request)?.pair else { return nil }
        let lines = description.components(separatedBy: "\n")
        let prefix = "📡 Available Servers: "
        guard lines.count == 5, lines[0] == "📌 Football", lines[1].hasPrefix("🏆 "),
              lines[1].utf8.count <= 160, footballCompetitionID(String(lines[1].dropFirst("🏆 ".count))) == fixture.competitionID,
              lines[2].hasPrefix("🕐 "), let start = parseExplicitUTCClock(String(lines[2].dropFirst("🕐 ".count))),
              start == request.kickoffDate, lines[3].isEmpty, lines[4].hasPrefix(prefix) else { return nil }
        let count = String(lines[4].dropFirst(prefix.count))
        guard let value = Int(count), (0...100).contains(value), String(value) == count else { return nil }
        return value
    }

    private struct FootballDelivery: Sendable {
        let reference: String
        let catalog: String
        let document: StreamDocument?
    }

    private struct FootballConflict: Error { let reference: String }

    private func footballDeliveries(catalog: Manifest.Catalog, term: String?, request: StreamPlaybackRequest,
                                    now: Date) async throws -> [Result<FootballDelivery, Error>] {
        let path: [String]
        if catalog.supportsSearch, let term {
            path = ["catalog", "tv", catalog.id, "search=" + term + ".json"]
        } else {
            path = ["catalog", "tv", catalog.id + ".json"]
        }
        let rows: CatalogDocument = try await fetchJSON(CatalogDocument.self, from: Self.route(path), stage: .catalog)
        let listing = Self.footballListings(for: request, from: rows.metas)
        var results: [Result<FootballDelivery, Error>] = listing.conflictingReferences.map { .failure(FootballConflict(reference: $0)) }
        guard !listing.ids.isEmpty else { return results.isEmpty ? [.failure(CommunitySportsAddonError.matchNotFound)] : results }
        let key = request.matchID + "|" + catalog.id
        let ids = footballWindow(listing.ids, limit: 3, cursorKey: key + "|meta")
        if ids.count < listing.ids.count { results.append(.failure(CommunitySportsAddonError.lookupBudgetExhausted)) }
        var available = Set<String>()
        await withTaskGroup(of: (String, Result<Int, Error>).self) { group in
            for id in ids {
                group.addTask {
                    do {
                        let doc = try await self.fetchJSON(MetadataDocument.self,
                            from: Self.route(["meta", "tv", id + ".json"]), stage: .metadata)
                        let reference = Self.footballReference(id)
                        guard doc.meta.id == id else { throw FootballConflict(reference: reference) }
                        guard let count = Self.footballServerCount(for: doc.meta, request: request) else {
                            throw CommunitySportsAddonError.matchNotFound
                        }
                        if let association = request.registryMatch {
                            guard let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
                                  association.matches(request: request, providerCode: Self.providerCode,
                                    providerEventID: reference, streamID: reference, at: now),
                                  association.admitsFreshIdentity(sport: "football", pair: wanted.pair,
                                    start: wanted.kickoff, providerEventID: reference, streamID: reference, at: now)
                            else { throw FootballConflict(reference: reference) }
                        }
                        return (id, .success(count))
                    } catch { return (id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let count) where count > 0: available.insert(id)
                case .success: results.append(.success(.init(reference: Self.footballReference(id), catalog: catalog.id, document: nil)))
                case .failure(let error): results.append(.failure(error))
                }
            }
        }
        if Task.isCancelled { return results + [.failure(CancellationError())] }
        // Advance each metadata window's stream cursor independently. Otherwise
        // cycles with matching periods can permanently skip the same delivery.
        let positiveIDs = ids.filter(available.contains)
        let windowKey = positiveIDs.count > 2 ? Self.footballReference(positiveIDs.joined(separator: "|")) : ""
        let streamIDs = footballWindow(positiveIDs, limit: 2, cursorKey: key + "|streams|" + windowKey)
        if streamIDs.count < available.count { results.append(.failure(CommunitySportsAddonError.lookupBudgetExhausted)) }
        await withTaskGroup(of: Result<FootballDelivery, Error>.self) { group in
            for id in streamIDs {
                group.addTask {
                    do {
                        let doc = try await self.fetchJSON(StreamDocument.self,
                            from: Self.route(["stream", "tv", id + ".json"]), stage: .streams)
                        return .success(.init(reference: Self.footballReference(id), catalog: catalog.id, document: doc))
                    } catch { return .failure(error) }
                }
            }
            for await result in group { results.append(result) }
        }
        // Return already-read responses even when cancellation arrived during
        // sibling fetches; the lookup owner records them before rethrowing.
        return results
    }

    private func resolveFootball(for request: StreamPlaybackRequest, now: Date,
                                 forceRefresh: Bool, ledger: inout StreamAdmissionLedger,
                                 fetchFailures: inout Int, limited: inout Bool) async throws -> [StreamSession] {
        guard Self.supportsReviewedFootball(request) else { throw CommunitySportsAddonError.matchNotFound }
        let name = request.homeTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\?#%&="))
        let term = !name.isEmpty && name.utf8.count <= 120 && name.rangeOfCharacter(from: reserved) == nil ? name : nil
        let started = ProcessInfo.processInfo.systemUptime
        let manifest = try await loadManifest(now: now, forceRefresh: forceRefresh, football: true)
        let catalogs = [Self.catalogID, Self.cricketCatalogID].compactMap { id -> Manifest.Catalog? in
            let matches = manifest.catalogs.filter { $0.type == "tv" && $0.id == id }
            return matches.count == 1 ? matches.first : nil
        }
        guard !catalogs.isEmpty else { throw CommunitySportsAddonError.invalidManifest }
        let results = await withTaskGroup(of: [Result<FootballDelivery, Error>].self) { group in
            for catalog in catalogs {
                group.addTask {
                    do { return try await self.footballDeliveries(catalog: catalog, term: term, request: request, now: now) }
                    catch { return [.failure(error)] }
                }
            }
            var values: [Result<FootballDelivery, Error>] = []
            for await result in group { values.append(contentsOf: result) }
            return values
        }
        let errors: [Error] = results.compactMap { result in
            if case .failure(let error) = result { return error }
            return nil
        }
        fetchFailures += errors.filter(Self.isAdmissionFetchFailure).count
        limited = errors.contains { ($0 as? CommunitySportsAddonError) == .lookupBudgetExhausted }
        let allDeliveries = results.compactMap { try? $0.get() }
        for delivery in allDeliveries { delivery.document?.observe(in: &ledger) }
        try Task.checkCancellation()
        if let fatal = errors.first(where: CommunitySportsAddonClient.isFatalCatalogBatchError) { throw fatal }
        let conflicts = Set(errors.compactMap { ($0 as? FootballConflict)?.reference })
        for delivery in allDeliveries where conflicts.contains(delivery.reference) {
            ledger.record("fixture_changed", count: delivery.document?.streams.count ?? 0)
        }
        let deliveries = allDeliveries.filter { !conflicts.contains($0.reference) }
            .sorted { ($0.catalog, $0.reference) < ($1.catalog, $1.reference) }
        let completed = now.addingTimeInterval(ProcessInfo.processInfo.systemUptime - started)
        var sessions: [StreamSession] = []
        for delivery in deliveries {
            guard let document = delivery.document else { continue }
            guard let binding = StreamEventBinding(request: request, providerCode: Self.providerCode,
                providerEventID: delivery.reference, streamID: delivery.reference, manifestRevision: manifest.version,
                verifiedAt: now, expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime),
                at: completed) else {
                ledger.record("fixture_changed", count: document.streams.count)
                throw CommunitySportsAddonError.conflictingMatch
            }
            let accepted = Self.makeSessions(from: document.streams, request: request, addOnVersion: manifest.version,
                after: sessions, ledger: &ledger)
            sessions += accepted.map { $0.recordingEventBinding(binding, for: request, at: completed) }
        }
        if sessions.isEmpty {
            // Incomplete sibling requests cannot establish a definitive absence.
            if let incomplete = errors.first(where: { !($0 is FootballConflict) && ($0 as? CommunitySportsAddonError) != .matchNotFound }) { throw incomplete }
            if !conflicts.isEmpty { throw CommunitySportsAddonError.conflictingMatch }
            guard !deliveries.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        }
        guard sessions.isEmpty else { return sessions }
        throw ledger.offered > 0 ? CommunitySportsAddonError.streamAdmissionRejected(entryCount: ledger.offered) : .streamEntriesEmpty
    }
}
