import Foundation
import CryptoKit

struct PlavioSportsCatalogEntry: Decodable, Sendable, Equatable {
    let id: String
    let type: String?
    let name: String
    let description: String?
    let genres: [String]?
    let hasMalformedIdentity: Bool
    let hasCompetingDateAuthority: Bool

    init(id: String, type: String? = "tv", name: String, description: String?,
         genres: [String]? = ["Sports"], hasMalformedIdentity: Bool = false,
         hasCompetingDateAuthority: Bool = false) {
        self.id = id; self.type = type; self.name = name
        self.description = description; self.genres = genres
        self.hasMalformedIdentity = hasMalformedIdentity
        self.hasCompetingDateAuthority = hasCompetingDateAuthority
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, description, genres, behaviorHints
        case released, releaseInfo, date, startTime, kickoff, videos
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Keep an identifiable malformed sibling as veto evidence. Dropping it
        // would let a second row reuse its ID for a different fixture.
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        type = try? values.decode(String.self, forKey: .type)
        name = (try? values.decode(String.self, forKey: .name)) ?? ""
        description = try? values.decode(String.self, forKey: .description)
        genres = try? values.decode([String].self, forKey: .genres)
        hasMalformedIdentity = id.isEmpty || type == nil || name.isEmpty || description == nil
            || genres == nil || values.contains(.behaviorHints)
        hasCompetingDateAuthority = [CodingKeys.released, .releaseInfo, .date, .startTime, .kickoff, .videos]
            .contains(where: values.contains)
    }
}

enum PlavioSportsMatchSelection: Equatable {
    case matched(PlavioSportsCatalogEntry)
    case missing
    case conflicting
}

/// Explicit publisher metadata used only to corroborate a literal public event
/// ID advertised by this add-on. It is not a new fixture or live-status feed.
struct PlavioPublisherFixture: Decodable, Sendable {
    struct Teams: Decodable, Sendable {
        struct Team: Decodable, Sendable { let name: String }
        let home: Team
        let away: Team
    }
    let id: String
    let title: String?
    let category: String?
    let date: Int64?
    let teams: Teams?
    let hasMalformedIdentity: Bool

    init(id: String = "") {
        self.id = id; title = nil; category = nil; date = nil; teams = nil
        hasMalformedIdentity = true
    }

    private enum CodingKeys: String, CodingKey { case id, title, category, date, teams }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Retain an identifiable malformed sibling rather than dropping its
        // conflicting ID while another row happens to decode successfully.
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        title = try? values.decode(String.self, forKey: .title)
        category = try? values.decode(String.self, forKey: .category)
        date = try? values.decode(Int64.self, forKey: .date)
        teams = try? values.decode(Teams.self, forKey: .teams)
        hasMalformedIdentity = id.isEmpty || title == nil || category == nil || date == nil || teams == nil
    }
}

struct PlavioSportsStreamEntry: Decodable, Sendable {
    let url: String?
    /// nil preserves an invalid advertised header contract for row-level rejection.
    let requiredHeaders: [String: String]?
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
        requiredHeaders = try? StreamDeliveryPolicy.decodeRequestHeaders(from: decoder)
        requiresDRM = StreamDeliveryPolicy.decodeRequiresDRM(from: decoder)
    }
}

/// A separately reviewed Stremio source, not a new fixture authority. Only its
/// explicitly dated reviewed rows or same-advertised-ID metadata may add options
/// to an existing match. LIVE text never supplies a kickoff.
actor PlavioSportsAddonClient {
    static let shared = PlavioSportsAddonClient()
    static let providerCode = "plaviosports"
    // Maintainer-announced 2 November split: PlavioLive owns sports. The old
    // PlavioHD host now serves a movie/series manifest with no sports catalogs.
    static let manifestURL = URL(string: "https://addon.plavio.site/manifest.json")!
    static let catalogID = "plaviohd-live-sports"
    // Version 1.9.82 advertises a dedicated football catalog. The older Live
    // catalog now contains generic channels; it remains an older-manifest
    // compatibility path, never authority to infer their current programme.
    static let footballCatalogID = "plaviohd-football"
    static let cricketCatalogID = "plaviohd-cricket"
    static let publisherURL = URL(string: "https://streamed.pk/api/matches/all")!
    // The public source schedule named by the reviewed Daddy producer. This
    // metadata-only origin does not authorize any playback destination.
    static let dlhdOriginalScheduleURL = URL(string: "https://thedaddy.pk/")!
    private static let streamPrefix = "plaviohdtv-"
    private static let livePublisherPrefix = "plaviohdtv-sfly-streamed:"

    private enum CatalogProfile: Hashable, Sendable {
        case football, cricket

        nonisolated func catalogID(in manifest: Manifest) -> String? {
            let reviewed = self == .football
                ? [PlavioSportsAddonClient.footballCatalogID, PlavioSportsAddonClient.catalogID]
                : [PlavioSportsAddonClient.cricketCatalogID]
            // Reject ambiguous or wrong-type declarations, including an
            // unselected reviewed sibling, rather than guessing which one owns
            // the transport route. Remote IDs cannot append new catalog paths.
            for id in reviewed {
                let rows = manifest.catalogs.filter { $0.id == id }
                guard rows.count <= 1, rows.allSatisfy({ $0.type == "tv" }) else { return nil }
            }
            return reviewed.first { id in manifest.catalogs.contains { $0.id == id && $0.type == "tv" } }
        }

        nonisolated static func profile(for category: String) -> Self? {
            switch SportsTeamIdentity.normalized(category) {
            case "football", "soccer": return .football
            case "cricket": return .cricket
            default: return nil
            }
        }
    }

    struct Manifest: Decodable, Sendable {
        struct Resource: Decodable, Sendable {
            let name: String
            let types: [String]?
            let idPrefixes: [String]?

            init(from decoder: Decoder) throws {
                if let value = try? decoder.singleValueContainer().decode(String.self) {
                    name = value; types = nil; idPrefixes = nil
                } else {
                    let values = try decoder.container(keyedBy: CodingKeys.self)
                    name = try values.decode(String.self, forKey: .name)
                    types = try values.decode([String].self, forKey: .types)
                    idPrefixes = try values.decode([String].self, forKey: .idPrefixes)
                }
            }
            private enum CodingKeys: String, CodingKey { case name, types, idPrefixes }
        }
        func advertises(_ name: String, id: String) -> Bool {
            resources.contains { $0.name == name && $0.types?.contains("tv") == true
                && $0.idPrefixes?.contains(where: { id.hasPrefix($0) }) == true }
        }
        struct Catalog: Decodable, Sendable { let id: String; let type: String }
        struct Hints: Decodable, Sendable { let configurationRequired: Bool? }
        let id: String
        let version: String
        let types: [String]
        let resources: [Resource]
        let catalogs: [Catalog]
        let behaviorHints: Hints?
    }

    private struct CatalogDocument: Decodable {
        let metas: [PlavioSportsCatalogEntry]

        private enum CodingKeys: String, CodingKey { case metas }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            var rows = try values.nestedUnkeyedContainer(forKey: .metas)
            var entries: [PlavioSportsCatalogEntry] = []
            while !rows.isAtEnd {
                guard entries.count < 600 else { throw CommunitySportsAddonError.invalidResponse }
                let row = try rows.superDecoder()
                if let entry = try? PlavioSportsCatalogEntry(from: row) { entries.append(entry) }
                else { entries.append(.init(id: "", name: "", description: nil, hasMalformedIdentity: true)) }
            }
            metas = entries
        }
    }

    private struct StreamDocument: Decodable, Sendable {
        let streams: [PlavioSportsStreamEntry]
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
            var entries: [PlavioSportsStreamEntry] = []
            var scanned = 0
            while !rows.isAtEnd, scanned < StreamDeliveryPolicy.maximumSessionsPerProvider {
                let row = try rows.superDecoder(); scanned += 1
                if let entry = try? PlavioSportsStreamEntry(from: row) { entries.append(entry) }
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

    private struct MetaDocument: Decodable {
        let meta: MetaEntry
    }

    /// The observed advertised meta envelope omits catalog genres. Keep those
    /// separately verified catalog facts, but reject new/conflicting authority
    /// fields rather than silently ignoring dates or alternate video identities.
    private struct MetaEntry: Decodable, Sendable {
        let id: String
        let type: String
        let name: String
        let description: String
        let genres: [String]?
        let hasUnsupportedAuthority: Bool

        private enum CodingKeys: String, CodingKey {
            case id, type, name, description, genres
            case released, releaseInfo, date, startTime, kickoff, videos, behaviorHints
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            type = try values.decode(String.self, forKey: .type)
            name = try values.decode(String.self, forKey: .name)
            description = try values.decode(String.self, forKey: .description)
            genres = values.contains(.genres) ? try values.decode([String].self, forKey: .genres) : nil
            let competingAuthority: [CodingKeys] = [.released, .releaseInfo, .date, .startTime, .kickoff, .videos, .behaviorHints]
            hasUnsupportedAuthority = competingAuthority
                .contains(where: values.contains)
        }
    }

    private struct Snapshot<Value> { let value: Value; let fetchedAt: Date }
    private let qualityStore: FottyQualityStore
    private let transport: FottyBoundedHTTPClient
    private let manifestTTL: TimeInterval
    private let catalogTTL: TimeInterval
    private let negativeCatalogTTL: TimeInterval
    private var manifestSnapshot: Snapshot<Manifest>?
    private var catalogSnapshots: [String: Snapshot<[PlavioSportsCatalogEntry]>] = [:]
    private var manifestGeneration: UUID?
    private var catalogGenerations: [String: UUID] = [:]
    private var dlhdOriginalSnapshot: Snapshot<[DLHDOriginalFixture]>?
    private var dlhdOriginalGeneration: UUID?
    private let originalScheduleResolver: LocalStreamProxyDestinationValidator.Resolver
    private let officialSnapshot: @Sendable (Date) async -> SportsFixtureCatalog.Snapshot?

    init(session: URLSession? = nil, manifestTTL: TimeInterval = 30 * 60,
         catalogTTL: TimeInterval = 2 * 60, negativeCatalogTTL: TimeInterval = 15,
         originalScheduleResolver: @escaping LocalStreamProxyDestinationValidator.Resolver = {
             try await LocalStreamProxyDestinationValidator.resolve($0)
         }, officialSnapshot: @escaping @Sendable (Date) async -> SportsFixtureCatalog.Snapshot? = { now in
             await MainActor.run { SportsFixtureUpdater.shared.cachedSnapshot(now: now) }
         }, qualityStore: FottyQualityStore = .shared) {
        self.qualityStore = qualityStore
        transport = FottyBoundedHTTPClient(configuration: session?.configuration ?? Self.makeConfiguration())
        self.manifestTTL = manifestTTL; self.catalogTTL = catalogTTL
        self.negativeCatalogTTL = negativeCatalogTTL
        self.officialSnapshot = officialSnapshot
        self.originalScheduleResolver = originalScheduleResolver
    }

    /// Batch catalog evidence only. Same-ID metadata and stream descriptors
    /// remain the selected fixture's Watch work, never a browse-time fan-out.
    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        try Task.checkCancellation()
        guard requests.count <= 256 else { throw CommunitySportsAddonError.invalidResponse }
        func profile(for request: StreamPlaybackRequest) -> CatalogProfile? {
            guard request.preferredEvent?.hasCatalogIdentityConflict != true,
                  ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil,
                  let profile = CatalogProfile.profile(for: request.category),
                  profile != .cricket || Self.cricketRequest(for: request) != nil || Self.supportsCNCOfficialCricket(request) else { return nil }
            return profile
        }
        let profiles = Set(requests.compactMap { profile(for: $0) })
        guard !profiles.isEmpty else {
            return requests.map { .init(matchID: $0.matchID, outcome: .unsupported) }
        }
        let manifest = try await loadManifest(now: now)
        var catalogs: [CatalogProfile: [PlavioSportsCatalogEntry]] = [:]
        var catalogFailures: [CatalogProfile: StreamFailureCategory] = [:]
        for scope in [CatalogProfile.football, .cricket] where profiles.contains(scope) {
            guard let id = scope.catalogID(in: manifest) else { continue }
            do {
                catalogs[scope] = try await loadCatalog(id: id, now: now)
                try Task.checkCancellation()
            } catch {
                try Task.checkCancellation()
                guard !CommunitySportsAddonClient.isFatalCatalogBatchError(error) else { throw error }
                catalogFailures[scope] = CommunitySportsAddonClient.catalogBatchFailureCategory(error)
            }
        }
        let liveOfficial = (catalogs[.football] ?? []).contains { Self.isSafeRoxieID($0.id) }
            ? await officialSnapshot(now) : nil
        let footballCandidates = Self.footballCatalogCandidates(catalogs[.football] ?? [])
        let cricketIdentities = (catalogs[.cricket] ?? []).map(Self.cricketIdentity(for:))
        func select(_ request: StreamPlaybackRequest, scope: CatalogProfile,
                    entries: [PlavioSportsCatalogEntry]) -> PlavioSportsMatchSelection {
            if scope == .cricket {
                return Self.selectCricketMatch(for: request, from: entries, preparedIdentities: cricketIdentities)
            }
            switch ReviewedSportsFixtureMatcher.select(for: request, from: footballCandidates) {
            case .matched(let index): return .matched(entries[index])
            case .missing: return .missing
            case .conflicting: return .conflicting
            }
        }
        var needsOriginal = false
        for request in requests where profile(for: request) == .football {
            guard let entries = catalogs[.football] else { continue }
            if case .matched = select(request, scope: .football, entries: entries) { continue }
            if (try? Self.dlhdMetadataCandidate(for: request, from: entries)) != nil { needsOriginal = true; break }
        }
        var originals: [DLHDOriginalFixture] = []
        var originalFailure: StreamFailureCategory?
        if needsOriginal {
            do { originals = try await loadDLHDOriginalSchedule(now: now) }
            catch {
                try Task.checkCancellation()
                guard !CommunitySportsAddonClient.isFatalCatalogBatchError(error) else { throw error }
                originalFailure = CommunitySportsAddonClient.catalogBatchFailureCategory(error)
            }
        }
        try Task.checkCancellation()
        return requests.map { request in
            guard let scope = profile(for: request) else {
                return .init(matchID: request.matchID, outcome: .unsupported)
            }
            if let failure = catalogFailures[scope] { return .init(matchID: request.matchID, outcome: .failed(failure)) }
            guard let entries = catalogs[scope] else { return .init(matchID: request.matchID, outcome: .unsupported) }
            var conflict = false
            switch select(request, scope: scope, entries: entries) {
            case .matched(let row): return .init(matchID: request.matchID, outcome: .listed, providerEventID: row.id)
            case .conflicting: conflict = true
            case .missing: break
            }
            if scope == .football {
                switch Self.selectRoxieMatch(for: request, from: entries, official: liveOfficial, at: now) {
                case .matched(let row): return .init(matchID: request.matchID, outcome: .listed, providerEventID: row.id)
                case .conflicting: conflict = true
                case .missing: break
                }
                if let row = try? Self.advertisedMetadataCandidate(for: request, from: entries) {
                    return .init(matchID: request.matchID, outcome: .needsVerification, providerEventID: row.id)
                }
                do {
                    if try Self.dlhdMetadataCandidate(for: request, from: entries) != nil {
                        if let originalFailure { return .init(matchID: request.matchID, outcome: .failed(originalFailure)) }
                        switch Self.selectDLHDMatch(for: request, from: entries, originals: originals) {
                        case .matched(let row): return .init(matchID: request.matchID, outcome: .needsVerification, providerEventID: row.id)
                        case .conflicting: conflict = true
                        case .missing: break
                        }
                    }
                } catch { conflict = true }
            }
            return .init(matchID: request.matchID, outcome: conflict ? .conflicting : .notListed)
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
        try Task.checkCancellation()
        guard let profile = CatalogProfile.profile(for: request.category),
              request.preferredEvent?.hasCatalogIdentityConflict != true, request.kickoffDate != nil else { throw CommunitySportsAddonError.matchNotFound }
        // A plain cricket team pair has no format or match/day distinction.
        // Reject that ambiguity before making any requests, rather than using
        // an add-on suffix to invent the native fixture's missing authority.
        if profile == .cricket, Self.cricketRequest(for: request) == nil, !Self.supportsCNCOfficialCricket(request) {
            throw CommunitySportsAddonError.matchNotFound
        }
        let hadCachedManifest = manifestSnapshot.map { Self.isFresh($0.fetchedAt, at: now, ttl: manifestTTL) } ?? false
        var refreshed = forceRefresh
        var manifest = try await loadManifest(now: now, forceRefresh: forceRefresh)
        if profile.catalogID(in: manifest) == nil,
           !refreshed, hadCachedManifest,
           CommunitySportsAddonClient.allowsTargetedRefresh(for: request, at: now) {
            refreshed = true
            manifest = try await loadManifest(now: now, forceRefresh: true)
        }
        guard let selectedCatalogID = profile.catalogID(in: manifest) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        let started = ProcessInfo.processInfo.systemUptime
        let entries = try await loadCatalog(id: selectedCatalogID, now: now, forceRefresh: refreshed)
        let official = entries.contains(where: { Self.isSafeRoxieID($0.id) }) ? await officialSnapshot(now) : nil
        let plan = Self.listings(for: request, entries: entries, official: official, at: now)
        try Task.checkCancellation()
        guard !plan.rows.isEmpty else {
            throw plan.conflict ? CommunitySportsAddonError.conflictingMatch : .matchNotFound
        }

        limited = plan.rows.count > Self.maximumListings
        let listings = plan.rows.prefix(Self.maximumListings)
        if !refreshed, hadCachedManifest, CommunitySportsAddonClient.allowsTargetedRefresh(for: request, at: now),
           listings.contains(where: { $0.join == .live && !manifest.advertises("meta", id: $0.row.id) }) {
            manifest = try await loadManifest(now: now, forceRefresh: true)
            refreshed = true
            guard profile.catalogID(in: manifest) == selectedCatalogID else { throw CommunitySportsAddonError.invalidManifest }
        }
        var sessions: [StreamSession] = []
        var firstFailure: Error?
        var readDescriptor = false
        var mayRefreshEmpty = !refreshed && CommunitySportsAddonClient.allowsTargetedRefresh(for: request, at: now)
        var mayRefreshOriginal = dlhdOriginalSnapshot.map { Self.isFresh($0.fetchedAt, at: now, ttl: 5 * 60) } == true
            && CommunitySportsAddonClient.allowsTargetedRefresh(for: request, at: now)
        for listing in listings {
            try Task.checkCancellation()
            let id = listing.row.id
            do {
                guard manifest.advertises("stream", id: id) else { throw CommunitySportsAddonError.invalidManifest }
                if listing.join != .dated {
                    guard manifest.advertises("meta", id: id) else { throw CommunitySportsAddonError.invalidManifest }
                    let metadata = try await fetchJSON(MetaDocument.self, from: Self.route(["meta", "tv", id + ".json"]),
                        stage: .metadata, forceRefresh: refreshed || listing.join == .cnc)
                    try Task.checkCancellation()
                    let meta = metadata.meta
                    switch listing.join {
                    case .cnc:
                        let checked = PlavioSportsCatalogEntry(id: meta.id, type: meta.type, name: meta.name,
                            description: meta.description, genres: meta.genres, hasMalformedIdentity: meta.hasUnsupportedAuthority)
                        guard meta.id == id, Self.cncCricketIdentity(checked) == Self.cncCricketIdentity(listing.row)
                        else { throw CommunitySportsAddonError.conflictingMatch }
                    case .roxie:
                        let row = PlavioSportsCatalogEntry(id: meta.id, type: meta.type, name: meta.name,
                            description: meta.description, genres: meta.genres ?? listing.row.genres,
                            hasMalformedIdentity: meta.hasUnsupportedAuthority)
                        let checkedAt = now.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - started))
                        guard meta.id == id, Self.roxieIdentity(row) == Self.roxieIdentity(listing.row),
                              case .matched = Self.selectRoxieMatch(for: request, from: [listing.row],
                                  official: await officialSnapshot(checkedAt), at: checkedAt) else {
                            throw CommunitySportsAddonError.conflictingMatch
                        }
                    case .dlhd:
                        try Self.validateDLHDMetadata(meta, catalog: listing.row)
                        let originals = try await loadDLHDOriginalSchedule(now: now)
                        var selection = Self.selectDLHDMatch(for: request, from: [listing.row], originals: originals)
                        if case .missing = selection, mayRefreshOriginal {
                            mayRefreshOriginal = false
                            let fresh = try await loadDLHDOriginalSchedule(now: now, forceRefresh: true)
                            selection = Self.selectDLHDMatch(for: request, from: [listing.row], originals: fresh)
                        }
                        switch selection {
                        case .matched: break
                        case .missing: throw CommunitySportsAddonError.matchNotFound
                        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
                        }
                    case .live:
                        _ = try Self.corroboratedMetadata(meta, for: listing.row, request: request)
                    case .dated: break
                    }
                }
                try Task.checkCancellation()
                let streamURL = Self.route(["stream", "tv", id + ".json"])
                var document = try await fetchJSON(StreamDocument.self, from: streamURL, stage: .streams, forceRefresh: refreshed)
                document.observe(in: &ledger)
                readDescriptor = true
                if document.entryCount == 0, mayRefreshEmpty {
                    mayRefreshEmpty = false
                    document = try await fetchJSON(StreamDocument.self, from: streamURL, stage: .streams, forceRefresh: true)
                    document.observe(in: &ledger)
                }
                try Task.checkCancellation()
                guard let binding = StreamEventBinding(request: request, providerCode: Self.providerCode,
                    providerEventID: id, streamID: id, manifestRevision: manifest.version, verifiedAt: now,
                    expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime), at: now) else {
                    ledger.record("fixture_changed", count: document.streams.count)
                    throw CommunitySportsAddonError.conflictingMatch
                }
                sessions += Self.makeSessions(from: document.streams, request: request, addOnVersion: manifest.version,
                    matchMethod: listing.join == .roxie ? "official_fixture_pair_civil_date" : "explicit_dated_fixture",
                    after: sessions, ledger: &ledger).map { $0.recordingEventBinding(binding, for: request, at: now) }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                if Self.isAdmissionFetchFailure(error) { fetchFailures += 1 }
                firstFailure = firstFailure ?? error
            }
        }
        try Task.checkCancellation()
        guard readDescriptor else { throw firstFailure ?? CommunitySportsAddonError.matchNotFound }
        let completedAt = now.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - started))
        guard sessions.allSatisfy({ $0.eventBinding?.matches(request: request, providerCode: Self.providerCode,
            at: completedAt) == true }) else { throw CommunitySportsAddonError.conflictingMatch }
        if sessions.isEmpty, let firstFailure { throw firstFailure }
        if !sessions.isEmpty { return sessions }
        if ledger.offered == 0 { throw CommunitySportsAddonError.streamEntriesEmpty }
        throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: ledger.offered)
    }

    private enum ListingJoin { case dated, cnc, roxie, dlhd, live }
    private struct Listing {
        let row: PlavioSportsCatalogEntry
        let join: ListingJoin
    }
    nonisolated static let maximumListings = 6

    /// A literal stream ID owns all its catalog siblings. Keep those together
    /// through the family's identity checks before fetching its descriptor.
    nonisolated private static func listings(for request: StreamPlaybackRequest, entries: [PlavioSportsCatalogEntry],
        official: SportsFixtureCatalog.Snapshot?, at now: Date) -> (rows: [Listing], conflict: Bool) {
        let groups = Dictionary(grouping: entries, by: \.id)
        var seen = Set<String>(), result: [Listing] = []
        var conflict = false
        for entry in entries where seen.insert(entry.id).inserted {
            guard let siblings = groups[entry.id] else { continue }
            if let registry = request.registryMatch,
               !registry.matches(request: request, providerCode: providerCode,
                    providerEventID: entry.id, streamID: entry.id, at: now) { continue }
            // Roxie and DaddyLive never supply an explicit dated catalog identity.
            // A pinned registry entry for either still needs its own metadata join.
            let specialFootball = isSafeRoxieID(entry.id) || isSafeDLHDID(entry.id)
            switch specialFootball ? .missing : selectMatch(for: request, from: siblings) {
            case .matched(let row):
                result.append(Listing(row: row, join: isSafeCNCCricketID(row.id) ? .cnc : .dated))
                continue
            case .conflicting: conflict = true; continue
            case .missing: break
            }
            guard CatalogProfile.profile(for: request.category) == .football else { continue }
            if isSafeRoxieID(entry.id) {
                switch selectRoxieMatch(for: request, from: siblings, official: official, at: now) {
                case .matched(let row): result.append(Listing(row: row, join: .roxie))
                case .conflicting: conflict = true
                case .missing: break
                }
            } else if isSafeDLHDID(entry.id) {
                do {
                    if let row = try dlhdMetadataCandidate(for: request, from: siblings) {
                        result.append(Listing(row: row, join: .dlhd))
                    }
                } catch { conflict = true }
            } else if let row = try? advertisedMetadataCandidate(for: request, from: siblings) {
                result.append(Listing(row: row, join: .live))
            }
        }
        if request.registryMatch == nil, let cricket = cricketRequest(for: request), cricket.ordinal == nil {
            let ordinals = Set(result.compactMap { cricketIdentity(for: $0.row)?.qualifier.ordinal })
            if ordinals.count > 1 { return ([], true) }
        }
        return (result, conflict)
    }

    private func loadDLHDOriginalSchedule(now: Date, forceRefresh: Bool = false) async throws -> [DLHDOriginalFixture] {
        if !forceRefresh, let snapshot = dlhdOriginalSnapshot,
           Self.isFresh(snapshot.fetchedAt, at: now, ttl: 5 * 60) { return snapshot.value }
        let generation = UUID(); dlhdOriginalGeneration = generation
        let url = Self.dlhdOriginalScheduleURL
        guard Self.isSafeDLHDOriginalURL(url) else { throw CommunitySportsAddonError.unsafeResponse }
        try await LocalStreamProxyDestinationValidator.validate(url, resolver: originalScheduleResolver)
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = CommunitySportsRequestStage.catalog.requestTimeout
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Fotty/2.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let result = try await transport.fetch(request, maximumBytes: 1024 * 1024,
                deadline: CommunitySportsRequestStage.catalog.transportDeadline,
                // A homepage relocation is a contract change, not authority to
                // admit an arbitrary replacement host or playback endpoint.
                redirectPolicy: { _, _ in false })
            try Task.checkCancellation()
            guard let finalURL = result.http.url, Self.isSafeDLHDOriginalURL(finalURL) else {
                throw CommunitySportsAddonError.unsafeResponse
            }
            let originals = try Self.dlhdOriginalFixtures(data: result.data)
            try Task.checkCancellation()
            if dlhdOriginalGeneration == generation {
                dlhdOriginalSnapshot = .init(value: originals, fetchedAt: now)
            }
            return originals
        } catch let failure as FottyBoundedHTTPClient.Failure {
            try Task.checkCancellation()
            if failure == .unsafeRedirect { throw CommunitySportsAddonError.unsafeResponse }
            if case .httpStatus(let code) = failure {
                throw CommunitySportsAddonError.httpFailure(statusCode: code, stage: .catalog)
            }
            throw CommunitySportsAddonError.invalidResponse
        } catch let error as URLError {
            try Task.checkCancellation()
            if error.code == .cancelled { throw error }
            throw CommunitySportsAddonError.transportFailure(code: error.errorCode, stage: .catalog)
        }
    }

    private func loadManifest(now: Date, forceRefresh: Bool = false) async throws -> Manifest {
        if !forceRefresh, let snapshot = manifestSnapshot, Self.isFresh(snapshot.fetchedAt, at: now, ttl: manifestTTL) {
            return snapshot.value
        }
        let generation = UUID(); manifestGeneration = generation
        let data = try await fetchData(from: Self.manifestURL, stage: .manifest, forceRefresh: forceRefresh)
        let manifest = try Self.validateManifest(data: data)
        try Task.checkCancellation()
        if manifestGeneration == generation { manifestSnapshot = .init(value: manifest, fetchedAt: now) }
        return manifest
    }

    private func loadCatalog(id catalogID: String, now: Date,
                             forceRefresh: Bool = false) async throws -> [PlavioSportsCatalogEntry] {
        if !forceRefresh, let snapshot = catalogSnapshots[catalogID],
           Self.isFresh(snapshot.fetchedAt, at: now, ttl: snapshot.value.isEmpty ? negativeCatalogTTL : catalogTTL) {
            return snapshot.value
        }
        let generation = UUID(); catalogGenerations[catalogID] = generation
        let document: CatalogDocument = try await fetchJSON(CatalogDocument.self,
            from: Self.route(["catalog", "tv", catalogID + ".json"]), stage: .catalog,
            forceRefresh: forceRefresh)
        try Task.checkCancellation()
        if catalogGenerations[catalogID] == generation {
            catalogSnapshots[catalogID] = .init(value: document.metas, fetchedAt: now)
        }
        return document.metas
    }

    private func fetchJSON<Value: Decodable>(_ type: Value.Type, from url: URL,
                                            stage: CommunitySportsRequestStage,
                                            forceRefresh: Bool = false) async throws -> Value {
        let data = try await fetchData(from: url, stage: stage, forceRefresh: forceRefresh)
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as CommunitySportsAddonError { throw error }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: stage) }
    }

    private func fetchData(from url: URL, stage: CommunitySportsRequestStage,
                           forceRefresh: Bool = false) async throws -> Data {
        guard Self.isSafeMetadataURL(url) else { throw CommunitySportsAddonError.unsafeResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = stage.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("Fotty/2.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        do {
            let result = try await transport.fetch(request, maximumBytes: 512 * 1024,
                deadline: stage.transportDeadline, redirectPolicy: { from, to in
                    Self.isSafeMetadataURL(from) && Self.isSafeMetadataURL(to)
                })
            try Task.checkCancellation()
            guard Self.isSafeMetadataURL(result.http.url ?? url) else { throw CommunitySportsAddonError.unsafeResponse }
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
        let resourceNames: Set<String> = ["catalog", "meta", "stream", "subtitles"]
        let types: Set<String> = ["movie", "series", "tv"]
        guard manifest.id == "community.plaviohd.private", manifest.types.contains("tv"),
              !manifest.types.isEmpty, Set(manifest.types).isSubset(of: types),
              manifest.version.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,23}$"#, options: .regularExpression) != nil,
              manifest.behaviorHints?.configurationRequired != true,
              !manifest.resources.isEmpty, manifest.resources.count <= 16,
              Set(manifest.resources.map(\.name)).count == manifest.resources.count,
              manifest.resources.allSatisfy({ resource in
                  guard resourceNames.contains(resource.name) else { return false }
                  if let declaredTypes = resource.types, let prefixes = resource.idPrefixes {
                      return !declaredTypes.isEmpty && Set(declaredTypes).isSubset(of: types)
                          && Set(declaredTypes).count == declaredTypes.count && !prefixes.isEmpty
                          && Set(prefixes).count == prefixes.count && prefixes.allSatisfy {
                              $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$"#, options: .regularExpression) != nil
                          }
                  }
                  return resource.types == nil && resource.idPrefixes == nil
              }),
              manifest.resources.contains(where: { $0.name == "catalog" && ($0.types?.contains("tv") ?? true) }),
              manifest.resources.contains(where: {
                  $0.name == "stream" && $0.types?.contains("tv") == true
                      && $0.idPrefixes?.contains(Self.streamPrefix) == true
              }), manifest.catalogs.count <= 64,
              CatalogProfile.football.catalogID(in: manifest) != nil else {
            throw CommunitySportsAddonError.invalidManifest
        }
        return manifest
    }

    struct DLHDOriginalFixture: Sendable, Equatable {
        let competition: String
        let participants: ReviewedSportsFixtureMatcher.ParticipantIdentity?
        let clock: String?
        let kickoff: Date?
    }

    private struct DLHDCatalogIdentity: Equatable {
        let competition: String
        let participants: ReviewedSportsFixtureMatcher.ParticipantIdentity
        let clock: String
    }

    private struct DLHDHTMLNode {
        let tag: String
        let classes: Set<String>
        let start: Int
        let end: Int
        let parent: Int?
        let hidden: Bool
        var contentEnd: Int?
        var closeEnd: Int?
        var wellFormed = true
    }

    nonisolated static func isSafeDLHDOriginalURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "thedaddy.pk"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.path == "/" && url.query == nil && url.fragment == nil
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/"
    }

    nonisolated private static func isSafeDLHDID(_ id: String) -> Bool {
        id.range(of: #"^plaviohdtv-dlhd-ev-[a-z0-9]{1,32}$"#, options: .regularExpression) != nil
    }

    /// The AS prefix and original producer both name DaddyLive. AS omitted
    /// the calendar date from this newer envelope; only the original explicit
    /// GMT day section can supply it. Neither request date nor fetch date does.
    nonisolated static func dlhdOriginalFixtures(data: Data) throws -> [DLHDOriginalFixture] {
        guard data.count <= 1024 * 1024, let raw = String(data: data, encoding: .utf8),
              let ignored = try? NSRegularExpression(pattern: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>|<!--.*?(?:-->|\z)"#),
              let tags = try? NSRegularExpression(pattern: #"<(\/?)([A-Za-z][A-Za-z0-9]*)\b([^<>]{0,4096})>"#),
              let classes = try? NSRegularExpression(pattern: #"(?:^|\s)class\s*=\s*(["'])([^"']*)\1"#) else {
            throw CommunitySportsAddonError.invalidResponse
        }
        let visible = ignored.stringByReplacingMatches(in: raw,
            range: NSRange(raw.startIndex..<raw.endIndex, in: raw), withTemplate: "") as NSString
        let matches = tags.matches(in: visible as String, range: NSRange(location: 0, length: visible.length))
        guard matches.count <= 24_000 else { throw CommunitySportsAddonError.invalidResponse }
        let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        var nodes: [DLHDHTMLNode] = [], stack: [Int] = [], skipUntil = 0
        for match in matches {
            guard match.range.location >= skipUntil else { continue }
            let tag = visible.substring(with: match.range(at: 2)).lowercased()
            if visible.substring(with: match.range(at: 1)) == "/" {
                guard let position = stack.lastIndex(where: { nodes[$0].tag == tag }) else { continue }
                let index = stack[position]
                if position != stack.count - 1 { for ancestor in stack { nodes[ancestor].wellFormed = false } }
                nodes[index].contentEnd = match.range.location; nodes[index].closeEnd = NSMaxRange(match.range)
                stack.removeSubrange(position...)
                continue
            }
            let attributes = visible.substring(with: match.range(at: 3)) as NSString
            let attr = classes.firstMatch(in: attributes as String, range: NSRange(location: 0, length: attributes.length))
            let tokens = attr.map { Set(attributes.substring(with: $0.range(at: 2)).split(whereSeparator: \.isWhitespace).map(String.init)) } ?? []
            let inheritedHidden = stack.last.map { nodes[$0].hidden } ?? false
            let structuralHidden = ["template", "noscript", "textarea", "script", "style"].contains(tag)
                || (attributes as String).range(of: #"(?i)(?:^|\s)(?:hidden|inert)(?=\s|=|/|$)|(?:^|\s)aria-hidden\s*=\s*(?:["']true["']|true(?:\s|$))|(?:^|\s)style\s*=\s*["'][^"']*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))"#, options: .regularExpression) != nil
            let index = nodes.count
            nodes.append(.init(tag: tag, classes: tokens, start: match.range.location, end: NSMaxRange(match.range),
                               parent: stack.last, hidden: inheritedHidden || structuralHidden))
            if tokens.contains("schedule__day"), stack.contains(where: { nodes[$0].classes.contains("schedule__day") }) {
                nodes[index].wellFormed = false
                for ancestor in stack { nodes[ancestor].wellFormed = false }
            }
            if ["noscript", "textarea", "script", "style"].contains(tag) {
                // These are raw-text/inactive containers, never schedule DOM.
                // Skip their body instead of parsing apparent child markup.
                if let closing = try? NSRegularExpression(pattern: "(?i)</" + tag + #"\s*>"#),
                   let close = closing.firstMatch(in: visible as String,
                    range: NSRange(location: nodes[index].end, length: visible.length - nodes[index].end)) {
                    nodes[index].contentEnd = close.range.location; nodes[index].closeEnd = NSMaxRange(close.range)
                    skipUntil = NSMaxRange(close.range)
                } else { nodes[index].wellFormed = false; skipUntil = visible.length }
            } else if voidTags.contains(tag) || (attributes as String).trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") {
                nodes[index].contentEnd = nodes[index].end; nodes[index].closeEnd = nodes[index].end
            } else {
                guard stack.count < 96 else { throw CommunitySportsAddonError.invalidResponse }
                stack.append(index)
            }
        }
        let days = nodes.indices.filter { nodes[$0].classes.contains("schedule__day") && !nodes[$0].hidden }
        guard !days.isEmpty, days.count <= 16 else { throw CommunitySportsAddonError.invalidResponse }
        func ancestor(_ index: Int, with name: String) -> Int? {
            var parent = nodes[index].parent
            while let current = parent {
                if nodes[current].classes.contains(name) { return current }
                parent = nodes[current].parent
            }
            return nil
        }
        func text(_ index: Int) -> String? {
            let node = nodes[index]
            guard !node.hidden, node.wellFormed, let end = node.contentEnd, end >= node.end else { return nil }
            var content = visible.substring(with: NSRange(location: node.end, length: end - node.end)) as NSString
            let hidden = nodes.filter { $0.hidden && $0.start >= node.end && ($0.closeEnd ?? Int.max) <= end
                && ($0.parent.map { !nodes[$0].hidden } ?? true) }
            for child in hidden.reversed() {
                guard let close = child.closeEnd else { continue }
                content = content.replacingCharacters(in: NSRange(location: child.start - node.end, length: close - child.start), with: "") as NSString
            }
            return dlhdVisibleText(content as String)
        }
        func field(_ name: String, owner: Int, scope: String) -> String? {
            let fields = nodes.indices.filter { !nodes[$0].hidden && nodes[$0].classes.contains(name) && ancestor($0, with: scope) == owner }
            guard fields.count == 1 else { return nil }
            return text(fields[0])
        }
        func qualified(_ index: Int) -> Bool { nodes[index].wellFormed && nodes[index].contentEnd != nil && !nodes[index].hidden }
        var result: [DLHDOriginalFixture] = []
        for event in nodes.indices where !nodes[event].hidden && nodes[event].classes.contains("schedule__event") {
            guard let day = ancestor(event, with: "schedule__day"), let category = ancestor(event, with: "schedule__category"),
                  ancestor(category, with: "schedule__day") == day else { continue }
            guard result.count < 2_000 else { throw CommunitySportsAddonError.invalidResponse }
            let title = field("schedule__eventTitle", owner: event, scope: "schedule__event")
            let clock = field("schedule__time", owner: event, scope: "schedule__event")
            let parts = title.flatMap(dlhdTitleIdentity)
            let header = field("schedule__dayTitle", owner: day, scope: "schedule__day")
            let sourceCategory = field("card__meta", owner: category, scope: "schedule__category")
            let isSoccer = sourceCategory.map { SportsTeamIdentity.normalized($0) == "all soccer events" } == true
            let validScope = qualified(day) && qualified(category) && qualified(event) && isSoccer
            result.append(.init(competition: parts?.competition ?? "", participants: parts?.participants,
                clock: clock, kickoff: validScope ? header.flatMap { dlhdGMTDate(header: $0, clock: clock) } : nil))
        }
        return result
    }

    nonisolated private static func dlhdVisibleText(_ raw: String) -> String? {
        guard raw.utf8.count <= 4096 else { return nil }
        var value = raw.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in [("&amp;", "&"), ("&nbsp;", " "), ("&#039;", "'"), ("&#39;", "'"), ("&quot;", "\"")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        guard value.range(of: #"&(?:#[0-9A-Za-z]+|[A-Za-z][A-Za-z0-9]+);"#, options: .regularExpression) == nil,
              !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                && !(0xE0020...0xE007F).contains($0.value)
        }) else { return nil }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    nonisolated private static func dlhdTitleIdentity(_ title: String) -> (competition: String, participants: ReviewedSportsFixtureMatcher.ParticipantIdentity)? {
        guard title.utf8.count <= 512, let colon = title.firstIndex(of: ":"),
              title[title.index(after: colon)...].firstIndex(of: ":") == nil,
              !title.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && !(0xE0020...0xE007F).contains($0.value)
              }) else { return nil }
        let competition = SportsTeamIdentity.normalized(String(title[..<colon]))
        let pairTitle = SportsTeamIdentity.normalized(String(title[title.index(after: colon)...]))
        guard !competition.isEmpty,
              let pair = ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: pairTitle) else { return nil }
        return (competition, pair)
    }

    nonisolated private static func dlhdGMTDate(header: String, clock: String?) -> Date? {
        guard let clock, clock.range(of: #"^(?:0[6-9]|1[0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil,
              let regex = try? NSRegularExpression(pattern: #"^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) ([1-9]|[12][0-9]|3[01])(?:st|nd|rd|th|h) (Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?) (20[0-9]{2}) - Schedule Time UK GMTT?$"#),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..<header.endIndex, in: header)) else { return nil }
        let source = header as NSString
        let month = String(source.substring(with: match.range(at: 3)).prefix(3))
        guard let monthIndex = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].firstIndex(of: month),
              let day = Int(source.substring(with: match.range(at: 2))),
              let year = Int(source.substring(with: match.range(at: 4))),
              let hour = Int(clock.prefix(2)), let minute = Int(clock.suffix(2)),
              let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let components = DateComponents(year: year, month: monthIndex + 1, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year, calendar.component(.month, from: date) == monthIndex + 1,
              calendar.component(.day, from: date) == day, calendar.component(.hour, from: date) == hour,
              calendar.component(.minute, from: date) == minute,
              let weekday = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                .firstIndex(of: source.substring(with: match.range(at: 1))),
              calendar.component(.weekday, from: date) == weekday + 1 else { return nil }
        return date
    }

    nonisolated private static func dlhdCatalogIdentity(_ row: PlavioSportsCatalogEntry) -> DLHDCatalogIdentity? {
        guard !row.hasMalformedIdentity, !row.hasCompetingDateAuthority, isSafeDLHDID(row.id), row.type == "tv",
              row.genres == ["Football"], let description = row.description, description.utf8.count <= 128,
              row.name.rangeOfCharacter(from: .newlines) == nil,
              let identity = dlhdTitleIdentity(row.name),
              let regex = try? NSRegularExpression(pattern: #"^Starts ((?:[01][0-9]|2[0-3]):[0-5][0-9]) \(UK time\) · [1-9][0-9]{0,2} channels$"#),
              let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..<description.endIndex, in: description)) else { return nil }
        return .init(competition: identity.competition, participants: identity.participants,
                     clock: (description as NSString).substring(with: match.range(at: 1)))
    }

    nonisolated private static func dlhdMetadataCandidate(for request: StreamPlaybackRequest,
        from entries: [PlavioSportsCatalogEntry]) throws -> PlavioSportsCatalogEntry? {
        guard entries.count <= 600, let asked = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              asked.sport == "football" else { return nil }
        var sawConflict = false
        let siblings = Dictionary(grouping: entries, by: \.id)
        for entry in entries {
            if let registry = request.registryMatch,
               (registry.broadcast.providerCode != providerCode || registry.broadcast.providerEventID != entry.id
                || registry.broadcast.streamID != entry.id) { continue }
            guard let identity = dlhdCatalogIdentity(entry), identity.participants.pair == asked.pair else { continue }
            guard siblings[entry.id]?.allSatisfy({ dlhdCatalogIdentity($0) == identity && $0.name == entry.name }) == true
            else { sawConflict = true; continue }
            if let competition = request.preferredEvent?.competitionID, !competition.isEmpty {
                let competitions = ["england premier league": "premier-league", "uefa champions league": "champions-league",
                                    "england league cup": "carabao-cup", "france ligue 1": "ligue-1",
                                    "germany bundesliga": "bundesliga", "italy serie a": "serie-a", "spain la liga": "la-liga"]
                guard competitions[identity.competition] == competition else { sawConflict = true; continue }
            }
            return entry
        }
        if sawConflict { throw CommunitySportsAddonError.conflictingMatch }
        return nil
    }

    nonisolated private static func validateDLHDMetadata(_ meta: MetaEntry, catalog: PlavioSportsCatalogEntry) throws {
        // Channel counts are display decoration: the same advertised metadata
        // route omits that suffix. Compare its literal clock/timezone grammar,
        // while retaining the catalog's full identity and dated original join.
        func clock(_ text: String) -> String? {
            guard text.utf8.count <= 128,
                  let regex = try? NSRegularExpression(pattern: #"^Starts ((?:[01][0-9]|2[0-3]):[0-5][0-9]) \(UK time\)(?: · [1-9][0-9]{0,2} channels)?$"#),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
            return (text as NSString).substring(with: match.range(at: 1))
        }
        guard !meta.hasUnsupportedAuthority, meta.id == catalog.id, meta.type == "tv", meta.name == catalog.name,
              let expected = dlhdCatalogIdentity(catalog), clock(meta.description) == expected.clock,
              meta.genres == nil || meta.genres == catalog.genres else {
            throw CommunitySportsAddonError.conflictingMatch
        }
    }

    nonisolated static func selectDLHDMatch(for request: StreamPlaybackRequest,
        from entries: [PlavioSportsCatalogEntry], originals: [DLHDOriginalFixture]) -> PlavioSportsMatchSelection {
        guard entries.count <= 600, originals.count <= 2_000 else { return .missing }
        let siblings = Dictionary(grouping: entries, by: \.id)
        var seen = Set<String>(), conflict = false
        for entry in entries where seen.insert(entry.id).inserted {
            do {
                guard let candidate = try dlhdMetadataCandidate(for: request, from: siblings[entry.id] ?? []),
                      let identity = dlhdCatalogIdentity(candidate) else { continue }
                switch selectDLHDOriginal(for: request, candidate: candidate, identity: identity, originals: originals) {
                case .matched: return .matched(candidate)
                case .conflicting: conflict = true
                case .missing: break
                }
            } catch { conflict = true }
        }
        return conflict ? .conflicting : .missing
    }

    nonisolated private static func selectDLHDOriginal(for request: StreamPlaybackRequest, candidate: PlavioSportsCatalogEntry,
        identity: DLHDCatalogIdentity, originals: [DLHDOriginalFixture]) -> PlavioSportsMatchSelection {
        let linked = originals.filter { $0.competition == identity.competition && $0.participants == identity.participants }
        // Another date, clock, malformed context or duplicate original row
        // is ambiguity, even if one sibling happens to fit the request.
        guard linked.count <= 1 else { return .conflicting }
        guard let original = linked.first, original.clock == identity.clock, let date = original.kickoff,
              let london = TimeZone(identifier: "Europe/London") else { return .missing }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = london
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let ukClock = String(format: "%02d:%02d", parts.hour ?? -1, parts.minute ?? -1)
        guard ukClock == identity.clock else { return .conflicting }
        let fixture = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football", cast: [],
            title: candidate.name.components(separatedBy: ":").last.map(SportsTeamIdentity.normalized) ?? "",
            kickoff: date, effectiveID: candidate.id, resourceType: "tv")
        switch ReviewedSportsFixtureMatcher.select(for: request,
            from: [.init(metadataID: candidate.id, effectiveID: candidate.id, identity: fixture)]) {
        case .matched: return .matched(candidate)
        case .conflicting: return .conflicting
        case .missing: return .missing
        }
    }

    nonisolated static func selectMatch(for request: StreamPlaybackRequest,
                                       from entries: [PlavioSportsCatalogEntry]) -> PlavioSportsMatchSelection {
        if CatalogProfile.profile(for: request.category) == .cricket {
            return selectCricketMatch(for: request, from: entries)
        }
        if let association = request.registryMatch,
           association.broadcast.providerCode == Self.providerCode,
           entries.contains(where: { $0.id == association.broadcast.providerEventID
               && (isSafeDLHDID($0.id) || livePublisherID(for: $0) != nil) }) {
            // These families still require the existing original schedule or
            // same-ID metadata join before any stream descriptor is requested.
            return .missing
        }
        // The common matcher owns exact clubs, squad distinctions and the
        // request's canonical official participant projection.
        let candidates = footballCatalogCandidates(entries)
        switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates) {
        case .missing: return .missing
        case .conflicting: return .conflicting
        case .matched(let index): return .matched(entries[index])
        }
    }

    /// Roxie publishes a civil-date label and an undocumented wall clock. Do
    /// not convert that clock or use it as kickoff. The fresh accepted official
    /// fixture owns schedule/status; this source corroborates its unique identity.
    /// Listing a scheduled match never bypasses the existing Watch timing policy.
    struct RoxieIdentity: Equatable {
        let pair: ReviewedSportsFixtureMatcher.ParticipantIdentity
        let date: String
        let wallClock: String
    }

    nonisolated static func isSafeRoxieID(_ id: String) -> Bool {
        id.range(of: #"^plaviohdtv-roxie-ev-[a-z0-9][a-z0-9-]{0,159}$"#, options: .regularExpression) != nil
    }

    nonisolated static func roxieIdentity(_ row: PlavioSportsCatalogEntry) -> RoxieIdentity? {
        guard isSafeRoxieID(row.id), !row.hasMalformedIdentity, !row.hasCompetingDateAuthority,
              row.type == "tv", row.genres == ["Football"], row.name.utf8.count <= 512,
              let description = row.description, description.utf8.count <= 1024,
              (row.name + " " + description).range(of: #"(?i)\b(replay|highlights?|classic|finished|cancelled|postponed)\b"#, options: .regularExpression) == nil,
              let pair = ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: row.name),
              let re = try? NSRegularExpression(pattern: #"^Starts ([A-Za-z]+) ([0-9]{1,2}), ([0-9]{4}) ([0-9]{1,2}):([0-9]{2}) (AM|PM) \(site time\)(?: · [1-9][0-9]{0,2} channels?)?$"#, options: [.caseInsensitive]),
              let m = re.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) else { return nil }
        let text = description as NSString
        func part(_ n: Int) -> String { text.substring(with: m.range(at: n)) }
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        guard let monthIndex = months.firstIndex(of: part(1).lowercased()), let day = Int(part(2)), let year = Int(part(3)),
              let hour = Int(part(4)), (1...12).contains(hour), let minute = Int(part(5)), (0...59).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: year, month: monthIndex + 1, day: day)
        guard let date = calendar.date(from: parts) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == monthIndex + 1, roundTrip.day == day else { return nil }
        return .init(pair: pair, date: String(format: "%04d-%02d-%02d", year, monthIndex + 1, day),
                     wallClock: String(format: "%02d:%02d", hour, minute) + part(6).uppercased())
    }

    nonisolated static func selectRoxieMatch(for request: StreamPlaybackRequest, from entries: [PlavioSportsCatalogEntry],
        official: SportsFixtureCatalog.Snapshot?, at now: Date) -> PlavioSportsMatchSelection {
        guard let wanted = ReviewedSportsFixtureMatcher.requestIdentity(for: request), wanted.sport == "football",
              let event = request.preferredEvent, !event.hasCatalogIdentityConflict,
              let anchor = event.sportsFixture, anchor.sport == "football", anchor.eventKind == .match,
              anchor.squad == .init(gender: .men, ageGroup: "senior"), anchor.verified,
              [.scheduled, .live].contains(anchor.status),
              (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(anchor.identityReceipt)),
              let official, official.sourceStatus.verifiesCurrentRows, let receipt = official.receiptDate,
              (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(receipt)) else { return .missing }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func day(_ date: Date) -> String {
            let p = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
        }
        let wantedDay = day(wanted.kickoff)
        guard entries.contains(where: { row in
            guard let identity = roxieIdentity(row) else { return false }
            return identity.pair.pair == wanted.pair && identity.date == wantedDay
        }) else { return .missing }
        let peers = official.fixtures.filter { row in
            guard row.sport == "football", row.eventKind == .match, row.squad == anchor.squad,
                  row.source.verification != .held,
                  let coverage = official.coverage.first(where: { $0.competitionKey == row.competitionKey }),
                  coverage.status == .covered || row.source.verification == .verified,
                  let observed = SportsFixtureCatalog.date(row.source.observedAt),
                  (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(observed)),
                  let kickoff = row.kickoff, day(kickoff) == wantedDay,
                  let pair = ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: row.participants.map(\.name), title: row.title)
            else { return false }
            return pair.pair == wanted.pair
        }
        guard peers.count == 1, let peer = peers.first, peer.id == anchor.fixtureID,
              [.scheduled, .live].contains(peer.status), peer.kickoff == wanted.kickoff,
              peer.competitionId == anchor.competitionID, peer.participants == anchor.participants else { return .conflicting }
        if peer.status == .live {
            let observed = SportsFixtureCatalog.date(peer.source.observedAt) ?? .distantPast
            let statusReceipt = min(observed, peer.source.updatedAt.flatMap(SportsFixtureCatalog.date) ?? observed)
            guard (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(statusReceipt)) else { return .conflicting }
        }
        var candidates: [PlavioSportsCatalogEntry] = []
        var conflictingID = false
        for row in entries {
            guard let identity = roxieIdentity(row), identity.pair.pair == wanted.pair, identity.date == wantedDay else { continue }
            if let registry = request.registryMatch,
               (registry.broadcast.providerCode != Self.providerCode || registry.broadcast.providerEventID != row.id || registry.broadcast.streamID != row.id) { continue }
            guard entries.filter({ $0.id == row.id }).allSatisfy({ roxieIdentity($0) == identity }) else { conflictingID = true; continue }
            if !candidates.contains(where: { $0.id == row.id }) { candidates.append(row) }
        }
        return candidates.first.map(PlavioSportsMatchSelection.matched) ?? (conflictingID ? .conflicting : .missing)
    }

    nonisolated private static func footballCatalogCandidates(_ entries: [PlavioSportsCatalogEntry]) -> [ReviewedSportsFixtureMatcher.Candidate] {
        entries.map { entry -> ReviewedSportsFixtureMatcher.Candidate in
            let identity: ReviewedSportsFixtureMatcher.FixtureIdentity?
            if !entry.hasMalformedIdentity, !entry.hasCompetingDateAuthority, isSafeFixtureID(entry.id), entry.type == "tv",
               entry.genres == ["Sports"], let date = explicitKickoff(for: entry) {
                identity = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football", cast: [],
                    title: entry.name, kickoff: date, effectiveID: entry.id, resourceType: "tv")
            } else { identity = nil }
            return .init(metadataID: entry.id, effectiveID: entry.id, identity: identity)
        }
    }

    nonisolated static func explicitKickoff(for entry: PlavioSportsCatalogEntry) -> Date? {
        if entry.genres == ["Cricket"] { return cricketIdentity(for: entry)?.fixture.kickoff }
        guard let description = entry.description, description.utf8.count <= 1024,
              !entry.name.isEmpty, entry.name.utf8.count <= 512,
              entry.name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 2, lines[0] == entry.name,
              lines[1].range(of: #"^(?:[1-9]|[12][0-9]|3[01]) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} · [0-2][0-9]:[0-5][0-9] UTC$"#,
                             options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy '·' HH:mm 'UTC'"
        formatter.isLenient = false
        guard let date = formatter.date(from: lines[1]), formatter.string(from: date) == lines[1] else { return nil }
        return date
    }

    private enum CricketFormat: Equatable, Sendable { case t20, test }
    private struct CricketQualifier: Equatable, Sendable {
        let ordinal: Int
        let format: CricketFormat
        let day: Int?
    }
    private struct CricketIdentity: Equatable, Sendable {
        let fixture: ReviewedSportsFixtureMatcher.FixtureIdentity
        let qualifier: CricketQualifier
    }
    private struct CricketRequest: Sendable {
        let fixture: ReviewedSportsFixtureMatcher.RequestIdentity
        let format: CricketFormat
        let ordinal: Int?
    }

    /// Source-local cricket authority: the suffix is retained independently of
    /// the common participant identity, so two same-ID rows cannot silently
    /// turn a first Test/T20I into a second match or a later Test day.
    nonisolated private static func cricketIdentity(for entry: PlavioSportsCatalogEntry) -> CricketIdentity? {
        guard !entry.hasMalformedIdentity, !entry.hasCompetingDateAuthority, isSafeFixtureID(entry.id, profile: .cricket),
              entry.type == "tv", entry.genres == ["Cricket"],
              !entry.name.isEmpty, entry.name.utf8.count <= 512,
              entry.name.rangeOfCharacter(from: .controlCharacters) == nil,
              let description = entry.description, description.utf8.count <= 1024 else { return nil }
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 2, !lines[0].isEmpty,
              lines[0].rangeOfCharacter(from: .controlCharacters) == nil,
              entry.name.hasPrefix(lines[0] + " - "),
              let qualifier = cricketQualifier(String(entry.name.dropFirst((lines[0] + " - ").count))),
              // The reviewed Test catalog always names a day explicitly.
              qualifier.format != .test || qualifier.day != nil,
              let kickoff = cricketUTCDate(lines[1]),
              let fixture = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "cricket", cast: [],
                title: lines[0], kickoff: kickoff, effectiveID: entry.id, resourceType: "tv",
                programmeMetadata: entry.name) else { return nil }
        return .init(fixture: fixture, qualifier: qualifier)
    }

    nonisolated private static func cricketUTCDate(_ value: String) -> Date? {
        guard value.range(of: #"^(?:0?[1-9]|[12][0-9]|3[01]) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} · [0-2][0-9]:[0-5][0-9] UTC$"#,
                          options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for dayFormat in ["d", "dd"] {
            formatter.dateFormat = dayFormat + " MMM yyyy '·' HH:mm 'UTC'"
            if let date = formatter.date(from: value), formatter.string(from: date) == value { return date }
        }
        return nil
    }

    /// Only suffixes actually advertised by this cricket catalog are accepted.
    /// IDs stay opaque; neither an abbreviated ID nor its digits supply dates,
    /// format, match number or Test-day authority.
    nonisolated private static func cricketQualifier(_ value: String) -> CricketQualifier? {
        guard value.utf8.count <= 64,
              let regex = try? NSRegularExpression(pattern: #"^([1-9][0-9]?)(st|nd|rd|th) (T20I|Test)(?: Day ([1-5]))?$"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        let source = value as NSString
        guard let ordinal = Int(source.substring(with: match.range(at: 1))) else { return nil }
        let suffix: String
        if (11...13).contains(ordinal % 100) { suffix = "th" }
        else {
            switch ordinal % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        guard source.substring(with: match.range(at: 2)) == suffix else { return nil }
        let format: CricketFormat = source.substring(with: match.range(at: 3)) == "Test" ? .test : .t20
        let day = match.range(at: 4).location == NSNotFound ? nil : Int(source.substring(with: match.range(at: 4)))
        guard format == .test || day == nil else { return nil }
        return .init(ordinal: ordinal, format: format, day: day)
    }

    /// An official cricket projection can establish format + initial UTC. Its
    /// optional explicit ordinal must agree too. A generic team pair cannot
    /// borrow a format from this add-on, and the native model has no verified
    /// Test-day-start identity: Day 2–5 therefore stay unmatchable here.
    nonisolated private static func cricketRequest(for request: StreamPlaybackRequest) -> CricketRequest? {
        guard CatalogProfile.profile(for: request.category) == .cricket,
              let kickoff = request.kickoffDate,
              request.preferredEvent?.hasCatalogIdentityConflict != true else { return nil }
        let pairTitle = "\(request.homeTeam) vs \(request.awayTeam)"
        guard let participants = ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket",
            cast: [request.homeTeam, request.awayTeam], title: pairTitle) else { return nil }

        if let event = request.preferredEvent, let fixture = event.cricketFixture {
            guard !event.hasCatalogIdentityConflict, event.sportsFixture == nil,
                  event.id == request.matchID, event.id == CricketFixtureCatalog.fixtureIDPrefix + fixture.fixtureID,
                  event.kickoffDate == kickoff, fixture.verified, !fixture.fixtureID.isEmpty,
                  !fixture.competitionID.isEmpty, !fixture.competitionName.isEmpty, fixture.competitionName.utf8.count <= 512,
                  fixture.competitionName.rangeOfCharacter(from: .controlCharacters) == nil,
                  let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
                  requested.sport == "cricket", requested.pair == participants.pair,
                  event.title == request.displayTitle,
                  event.title == "\(fixture.competitionName) · \(pairTitle)" else { return nil }
            let format: CricketFormat
            switch fixture.format {
            case .t20: format = .t20
            case .test: format = .test
            default: return nil
            }
            // A known ordinal in native competition copy remains authority.
            // Without one, exact initial UTC and a unique catalog identity are
            // required below; no ordinal is inferred from opaque fixture IDs.
            guard let qualifiers = cricketQualifiers(in: fixture.competitionName),
                  qualifiers.count <= 1, qualifiers.allSatisfy({
                $0.format == format && ($0.day == nil || $0.day == 1)
            }) else { return nil }
            let publishedOrdinal = fixture.matchOrdinal ?? fixture.context?.matchOrdinal
            let titleOrdinal = qualifiers.first?.ordinal
            if let publishedOrdinal, let titleOrdinal, publishedOrdinal != titleOrdinal { return nil }
            if format == .test, let day = fixture.context?.day, day != 1 { return nil }
            return .init(fixture: requested, format: format, ordinal: publishedOrdinal ?? titleOrdinal)
        }

        let parts = request.displayTitle.components(separatedBy: " - ")
        guard parts.count == 2, let qualifier = cricketQualifier(parts[1]),
              qualifier.day == nil || qualifier.day == 1,
              let identity = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "cricket",
                cast: [request.homeTeam, request.awayTeam], title: parts[0], kickoff: kickoff,
                effectiveID: request.matchID, resourceType: "tv"),
              identity.pair == participants.pair else { return nil }
        if let event = request.preferredEvent {
            guard event.id == request.matchID, event.kickoffDate == kickoff,
                  event.title == request.displayTitle,
                  ReviewedSportsFixtureMatcher.sportKey(event.category ?? "") == "cricket",
                  let home = event.teams?.home?.name, let away = event.teams?.away?.name,
                  ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket", cast: [home, away],
                    title: "\(home) vs \(away)") == participants else { return nil }
        }
        return .init(fixture: .init(sport: "cricket", pair: identity.pair, kickoff: kickoff),
                     format: qualifier.format, ordinal: qualifier.ordinal)
    }

    nonisolated private static func cricketQualifiers(in value: String) -> [CricketQualifier]? {
        guard let regex = try? NSRegularExpression(pattern: #"\b[0-9]+(?:st|nd|rd|th) (?:T20I|T20|ODI|Test)(?: Day [0-9]+)?\b"#,
                                                 options: [.caseInsensitive]) else { return nil }
        let source = value as NSString
        var qualifiers: [CricketQualifier] = []
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let qualifier = cricketQualifier(source.substring(with: match.range)) else { return nil }
            qualifiers.append(qualifier)
        }
        return qualifiers
    }

    /// PlavioLive's CNC rows publish an explicit UTC date but no format/ordinal.
    /// Only an accepted limited-overs official fixture may supply that context.
    /// Test-day matching remains on the older explicit format/day contract.
    nonisolated static func supportsCNCOfficialCricket(_ request: StreamPlaybackRequest) -> Bool {
        guard request.preferredEvent?.hasCatalogIdentityConflict != true,
              let event = request.preferredEvent, let fixture = event.cricketFixture,
              fixture.verified, [.t20, .odi].contains(fixture.format),
              event.id == request.matchID, event.kickoffDate == request.kickoffDate,
              event.id == CricketFixtureCatalog.fixtureIDPrefix + fixture.fixtureID,
              ReviewedSportsFixtureMatcher.requestIdentity(for: request)?.sport == "cricket" else { return false }
        return true
    }

    nonisolated static func isSafeCNCCricketID(_ id: String) -> Bool {
        id.range(of: #"^plaviohdtv-cnc-(?:sportzx|playztv|livxow)-[0-9]{1,12}$"#, options: .regularExpression) != nil
    }

    nonisolated static func cncCricketIdentity(_ entry: PlavioSportsCatalogEntry) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard isSafeCNCCricketID(entry.id), !entry.hasMalformedIdentity, !entry.hasCompetingDateAuthority,
              entry.type == "tv", entry.genres == ["Cricket"], let text = entry.description,
              text.range(of: #"^Starts [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian); formatter.isLenient = false
        formatter.dateFormat = "'Starts' yyyy-MM-dd HH:mm 'UTC'"
        guard let start = formatter.date(from: text), formatter.string(from: start) == text else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "cricket", cast: [], title: entry.name,
            kickoff: start, effectiveID: entry.id, resourceType: "tv", programmeMetadata: entry.name)
    }

    nonisolated private static func selectCricketMatch(
        for request: StreamPlaybackRequest, from entries: [PlavioSportsCatalogEntry],
        preparedIdentities: [CricketIdentity?]? = nil
    ) -> PlavioSportsMatchSelection {
        guard entries.count <= 600 else { return .missing }
        if supportsCNCOfficialCricket(request), entries.contains(where: { isSafeCNCCricketID($0.id) }) {
            let candidates = entries.map { entry in
                ReviewedSportsFixtureMatcher.Candidate(metadataID: entry.id, effectiveID: entry.id,
                    identity: cncCricketIdentity(entry).flatMap { identity in
                        guard let official = request.preferredEvent?.cricketFixture,
                              identity.cricketFormat.map({ $0 == official.format.rawValue }) ?? true,
                              identity.matchOrdinal.map({ ordinal in official.matchOrdinal.map { $0 == ordinal } ?? true }) ?? true
                        else { return nil }
                        return identity
                    })
            }
            switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates) {
            case .matched(let index): return .matched(entries[index])
            case .conflicting: return .conflicting
            case .missing: break
            }
        }
        guard let requested = cricketRequest(for: request) else { return .missing }
        let identities = preparedIdentities ?? entries.map(cricketIdentity(for:))
        let candidates = entries.indices.map { index -> ReviewedSportsFixtureMatcher.Candidate in
            let entry = entries[index]
            let admitted = identities[index].flatMap { identity -> ReviewedSportsFixtureMatcher.FixtureIdentity? in
                guard identity.qualifier.format == requested.format,
                      requested.ordinal == nil || requested.ordinal == identity.qualifier.ordinal,
                      identity.qualifier.day == nil || identity.qualifier.day == 1,
                      identity.fixture.kickoff == requested.fixture.kickoff else { return nil }
                return identity.fixture
            }
            return .init(metadataID: entry.id, effectiveID: entry.id, identity: admitted)
        }
        if request.registryMatch == nil, requested.ordinal == nil {
            let groups = Dictionary(grouping: entries.indices, by: { entries[$0].id })
            let ordinals = Set(groups.values.compactMap { indices -> Int? in
                guard let first = indices.first, let fixture = candidates[first].identity,
                      fixture.pair == requested.fixture.pair, indices.allSatisfy({ identities[$0] == identities[first] })
                else { return nil }
                return identities[first]?.qualifier.ordinal
            })
            if ordinals.count > 1 { return .conflicting }
        }
        let selection = request.registryMatch == nil
            ? ReviewedSportsFixtureMatcher.select(for: requested.fixture, from: candidates)
            : ReviewedSportsFixtureMatcher.select(for: request, from: candidates)
        switch selection {
        case .missing: return .missing
        case .conflicting: return .conflicting
        case .matched(let index):
            // Shared identities intentionally omit source-specific ordinals.
            // Keep that extra evidence locally, including malformed siblings.
            guard entries.indices.filter({ entries[$0].id == entries[index].id }).allSatisfy({
                identities[$0] == identities[index]
            }) else { return .conflicting }
            return .matched(entries[index])
        }
    }

    /// A fetch hint only: a unique literal catalog ID may request its advertised
    /// meta resource. Full-pair and malformed same-ID siblings remain vetoes.
    nonisolated private static func advertisedMetadataCandidate(
        for request: StreamPlaybackRequest, from entries: [PlavioSportsCatalogEntry]
    ) throws -> PlavioSportsCatalogEntry? {
        let ids = try corroboratableLiveIDs(for: request, from: entries)
        guard let id = ids.first else { return nil }
        return entries.first { livePublisherID(for: $0) == id }
    }

    nonisolated private static func corroboratedMetadata(
        _ meta: MetaEntry, for catalog: PlavioSportsCatalogEntry, request: StreamPlaybackRequest
    ) throws -> PlavioSportsCatalogEntry {
        guard !meta.hasUnsupportedAuthority, meta.id == catalog.id, meta.type == "tv",
              meta.genres == nil || meta.genres == catalog.genres,
              let catalogPair = liveParticipantIdentity(for: catalog),
              let metaPair = ReviewedSportsFixtureMatcher.participantIdentity(
                sport: "football", cast: [], title: meta.name), metaPair == catalogPair,
              let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              metaPair.sport == requested.sport, metaPair.pair == requested.pair else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let dated = PlavioSportsCatalogEntry(id: meta.id, type: meta.type, name: meta.name,
            description: meta.description, genres: catalog.genres)
        guard let publishedKickoff = explicitKickoff(for: dated),
              publishedKickoff == request.kickoffDate else { throw CommunitySportsAddonError.conflictingMatch }
        if request.registryMatch != nil {
            let identity = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football", cast: [],
                title: dated.name, kickoff: publishedKickoff, effectiveID: dated.id, resourceType: "tv")
            guard case .matched = ReviewedSportsFixtureMatcher.select(for: request,
                from: [.init(metadataID: dated.id, effectiveID: dated.id, identity: identity)]) else {
                throw CommunitySportsAddonError.conflictingMatch
            }
        }
        return dated
    }

    /// A fetch hint only: the LIVE label supplies no kickoff and authorizes no
    /// stream lookup. Retained historical publisher-matching tests also use it.
    nonisolated static func corroboratableLiveIDs(
        for request: StreamPlaybackRequest, from entries: [PlavioSportsCatalogEntry]
    ) throws -> [String] {
        guard CatalogProfile.profile(for: request.category) == .football,
              let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return [] }
        var ids: [String] = []
        for entry in entries {
            if let association = request.registryMatch,
               (association.broadcast.providerCode != Self.providerCode
                || association.broadcast.providerEventID != entry.id
                || association.broadcast.streamID != entry.id) { continue }
            guard let id = livePublisherID(for: entry),
                  let identity = liveParticipantIdentity(for: entry),
                  identity.sport == requested.sport, identity.pair == requested.pair else { continue }
            guard entries.filter({ $0.id == entry.id }).allSatisfy({
                liveParticipantIdentity(for: $0) == identity
            }) else { continue }
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    nonisolated static func selectLiveMatch(
        for request: StreamPlaybackRequest, from entries: [PlavioSportsCatalogEntry],
        publisher: [PlavioPublisherFixture]
    ) -> PlavioSportsMatchSelection {
        guard CatalogProfile.profile(for: request.category) == .football,
              let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return .missing }
        guard entries.count <= 600, publisher.count <= 600 else { return .conflicting }
        var candidates: [ReviewedSportsFixtureMatcher.Candidate] = []
        for entry in entries {
            var identity: ReviewedSportsFixtureMatcher.FixtureIdentity?
            if !entry.hasMalformedIdentity, !entry.hasCompetingDateAuthority, isSafeFixtureID(entry.id), entry.type == "tv",
               entry.genres == ["Sports"], let date = explicitKickoff(for: entry) {
                identity = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football", cast: [],
                    title: entry.name, kickoff: date, effectiveID: entry.id, resourceType: "tv")
            } else if let publicID = livePublisherID(for: entry),
                      let participants = liveParticipantIdentity(for: entry),
                      participants.sport == requested.sport, participants.pair == requested.pair {
                let linked = publisher.filter { $0.id == publicID }.map { row in
                    ReviewedSportsFixtureMatcher.Candidate(metadataID: row.id, effectiveID: entry.id,
                        identity: publisherIdentity(for: row, effectiveID: entry.id))
                }
                switch ReviewedSportsFixtureMatcher.select(for: requested, from: linked) {
                case .conflicting: return .conflicting
                case .missing: break
                case .matched(let index):
                    if let corroborated = linked[index].identity,
                       corroborated.sport == participants.sport, corroborated.pair == participants.pair {
                        identity = corroborated
                    }
                }
            }
            // Every original row remains present, including malformed siblings.
            candidates.append(.init(metadataID: entry.id, effectiveID: entry.id, identity: identity))
        }
        let selection = request.registryMatch == nil
            ? ReviewedSportsFixtureMatcher.select(for: requested, from: candidates)
            : ReviewedSportsFixtureMatcher.select(for: request, from: candidates)
        switch selection {
        case .missing: return .missing
        case .conflicting: return .conflicting
        case .matched(let index): return .matched(entries[index])
        }
    }

    nonisolated private static func liveParticipantIdentity(
        for entry: PlavioSportsCatalogEntry
    ) -> ReviewedSportsFixtureMatcher.ParticipantIdentity? {
        guard livePublisherID(for: entry) != nil else { return nil }
        return ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: entry.name)
    }

    nonisolated private static func livePublisherID(for entry: PlavioSportsCatalogEntry) -> String? {
        guard !entry.hasMalformedIdentity, !entry.hasCompetingDateAuthority, entry.type == "tv", entry.genres == ["Sports"],
              isSafeAdvertisedLiveID(entry.id),
              !entry.name.isEmpty, entry.name.utf8.count <= 512,
              entry.name.rangeOfCharacter(from: .controlCharacters) == nil,
              let description = entry.description, description.utf8.count <= 1024 else { return nil }
        let id = String(entry.id.dropFirst(livePublisherPrefix.count))
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 2 || lines.count == 4,
              lines[0] == entry.name, lines[1] == "LIVE NOW" else { return nil }
        if lines.count == 4 {
            guard lines[2] == "Popular match", lines[3].range(
                of: #"^Sources: [A-Z][a-z]{0,23}(?:, [A-Z][a-z]{0,23}){0,15}$"#,
                options: .regularExpression) != nil else { return nil }
        }
        return id
    }

    nonisolated private static func isSafeAdvertisedLiveID(_ id: String) -> Bool {
        id.hasPrefix(livePublisherPrefix) && id.utf8.count <= 240
            && isSafePublicID(String(id.dropFirst(livePublisherPrefix.count)))
    }

    nonisolated private static func publisherIdentity(
        for fixture: PlavioPublisherFixture, effectiveID: String
    ) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard !fixture.hasMalformedIdentity, isSafePublicID(fixture.id), fixture.category == "football",
              let title = fixture.title, !title.isEmpty, title.utf8.count <= 512,
              title.rangeOfCharacter(from: .controlCharacters) == nil,
              let teams = fixture.teams, !teams.home.name.isEmpty, !teams.away.name.isEmpty,
              teams.home.name.utf8.count <= 512, teams.away.name.utf8.count <= 512,
              teams.home.name.rangeOfCharacter(from: .controlCharacters) == nil,
              teams.away.name.rangeOfCharacter(from: .controlCharacters) == nil,
              let milliseconds = fixture.date,
              milliseconds >= 946_684_800_000, milliseconds < 4_133_980_800_000 else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football",
            cast: [teams.home.name, teams.away.name], title: title,
            kickoff: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
            effectiveID: effectiveID, resourceType: "tv")
    }

    nonisolated private static func isSafePublicID(_ id: String) -> Bool {
        id.utf8.count <= 216 && id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                                       options: .regularExpression) != nil
    }

    nonisolated static func makeSessions(from streams: [PlavioSportsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String, matchMethod: String = "explicit_dated_fixture",
                                        after earlier: [StreamSession] = []) -> [StreamSession] {
        var ledger = StreamAdmissionLedger()
        ledger.observe(streams.count)
        return makeSessions(from: streams, request: request, addOnVersion: addOnVersion, matchMethod: matchMethod, after: earlier, ledger: &ledger)
    }

    nonisolated static func makeSessions(from streams: [PlavioSportsStreamEntry], request: StreamPlaybackRequest,
                                        addOnVersion: String, matchMethod: String = "explicit_dated_fixture",
                                        after earlier: [StreamSession] = [], ledger: inout StreamAdmissionLedger) -> [StreamSession] {
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
                providerName: label, requiredHeaders: headers, qualityLabel: "Live video",
                canRefresh: false, validationStatus: .validated,
                diagnosticMetadata: ["source_family": providerCode, "manifest_result": "exact_fixture_match",
                    "delivery": "reviewed_direct_hls", "addon_version": safeVersion(addOnVersion), "match_method": matchMethod,
                    "source_key": key, "source_key_scope": "delivery"], requiresGuardedRelay: true))
        }
        return sessions
    }

    /// Safe to open (see StreamDeliveryPolicy); server and link shape are not judged.
    nonisolated static func isAdmittedDelivery(_ url: URL) -> Bool {
        StreamDeliveryPolicy.publicRejection(url) == nil
    }

    nonisolated static func sourceKey(url: URL, headers: [String: String] = [:]) -> String {
        // The full signed delivery is identity; never log it or flatten its
        // query. Required headers are part of the delivery identity.
        let headerIdentity = headers.isEmpty ? "{}" : headers.keys.sorted().map { "\($0):\(headers[$0]!)" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data((url.absoluteString + "\nheaders:" + headerIdentity).utf8))
        return "ps_" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
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

    nonisolated static func supports(category: String) -> Bool {
        CatalogProfile.profile(for: category) != nil
    }

    nonisolated private static func isSafeFixtureID(_ id: String) -> Bool {
        isSafeFixtureID(id, profile: .football)
    }

    nonisolated private static func isSafeFixtureID(_ id: String, profile: CatalogProfile) -> Bool {
        if profile == .cricket, isSafeCNCCricketID(id) { return true }
        let sport = profile == .football ? "football" : "cricket"
        return id.utf8.count <= 240 && id.range(of: "^plaviohdtv-sfly-streamed:\(sport)-[a-z0-9][a-z0-9-]*$",
                                              options: .regularExpression) != nil
    }

    nonisolated static func isSafeMetadataURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "addon.plavio.site"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil
    }

    nonisolated static func isSafePublisherURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "streamed.pk"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.path == "/api/matches/all" && url.query == nil && url.fragment == nil
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/api/matches/all"
    }

    nonisolated private static func route(_ components: [String]) -> URL {
        components.reduce(manifestURL.deletingLastPathComponent()) { $0.appendingPathComponent($1) }
    }

    nonisolated private static func isFresh(_ date: Date, at now: Date, ttl: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < ttl
    }
}
