import Foundation
import CryptoKit

enum CommunitySportsRequestStage: String, Equatable, Sendable {
    case manifest
    case catalog
    case metadata
    case streams

    // Stream resolution can return useful metadata just past the old seven-
    // second timeout. Only that stage gets a larger slice; the owning discovery
    // still has one bounded deadline and never retries this request.
    var requestTimeout: TimeInterval { self == .streams ? 11 : 7 }
    var transportDeadline: TimeInterval { self == .streams ? 12 : 9 }
}

/// Fixed diagnostic vocabulary only: never retain a rejected URL, team query,
/// stream ID, redirect location or credential in the local discovery receipt.
enum CommunitySportsUnsafeMetadataReason: String, Equatable, Sendable {
    case requestOrigin = "request_origin"
    case redirect
    case responseOrigin = "response_origin"
    case streamID = "stream_id"
    case streamIDEmpty = "stream_id_empty"
    case streamIDPrefix = "stream_id_prefix"
    case streamIDLength = "stream_id_length"
    case streamIDCharacters = "stream_id_characters"
    case searchRoute = "search_route"
}

enum CommunitySportsAddonError: Error, Equatable {
    case configurationUnavailable
    case invalidManifest
    case invalidResponse
    case httpFailure(statusCode: Int, stage: CommunitySportsRequestStage)
    case transportFailure(code: Int, stage: CommunitySportsRequestStage)
    case invalidJSON(stage: CommunitySportsRequestStage)
    case unsafeResponse
    case unsafeMetadata(stage: CommunitySportsRequestStage, reason: CommunitySportsUnsafeMetadataReason,
                        invalidScalar: UInt32? = nil)
    case matchNotFound
    case conflictingMatch
    case streamEntriesEmpty
    case streamAdmissionRejected(entryCount: Int)

    var isSecurityRejection: Bool {
        switch self {
        case .unsafeResponse, .unsafeMetadata: return true
        default: return false
        }
    }
}

/// Issued only after the original CS metadata, a unique fresh sport-catalog
/// entry and that entry's own metadata all identify the same live NHL match.
struct CSRegisteredHandoff: Equatable, Sendable {
    let fixtureID: String, oldID: String, newID: String
    let expiresAt: Date
    fileprivate init(fixtureID: String, oldID: String, newID: String, expiresAt: Date) {
        self.fixtureID = fixtureID; self.oldID = oldID; self.newID = newID; self.expiresAt = expiresAt
    }
}

struct CommunitySportsCatalogEntry: Decodable, Sendable, Equatable {
    struct BehaviorHints: Decodable, Sendable, Equatable {
        let defaultVideoId: String?
    }

    let id: String
    let type: String?
    let name: String
    let releaseInfo: String?
    let released: String?
    let genres: [String]?
    let cast: [String]?
    let behaviorHints: BehaviorHints?
    let description: String?
    let hasUnreviewedChannelAuthority: Bool
    let hasAdditionalEventTimeAuthority: Bool

    init(id: String, type: String?, name: String, releaseInfo: String?, released: String?, genres: [String]?,
         cast: [String]?, behaviorHints: BehaviorHints?, description: String? = nil,
         hasUnreviewedChannelAuthority: Bool = false, hasAdditionalEventTimeAuthority: Bool = false) {
        self.id = id; self.type = type; self.name = name; self.releaseInfo = releaseInfo; self.released = released
        self.genres = genres; self.cast = cast; self.behaviorHints = behaviorHints
        self.description = description; self.hasUnreviewedChannelAuthority = hasUnreviewedChannelAuthority
        self.hasAdditionalEventTimeAuthority = hasAdditionalEventTimeAuthority
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, releaseInfo, released, genres, cast, behaviorHints, description
        case date, startTime, kickoff, videos
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        name = try values.decode(String.self, forKey: .name)
        releaseInfo = try values.decodeIfPresent(String.self, forKey: .releaseInfo)
        released = try values.decodeIfPresent(String.self, forKey: .released)
        genres = try values.decodeIfPresent([String].self, forKey: .genres)
        cast = try values.decodeIfPresent([String].self, forKey: .cast)
        behaviorHints = try values.decodeIfPresent(BehaviorHints.self, forKey: .behaviorHints)
        description = try? values.decode(String.self, forKey: .description)
        // Fixture parsing continues to ignore unreviewed description copy.
        // Only the new standalone channel contract uses these extra guards.
        hasUnreviewedChannelAuthority = [CodingKeys.released, .date, .startTime, .kickoff, .videos].contains(where: values.contains)
            || values.contains(.description) && description == nil
        hasAdditionalEventTimeAuthority = [CodingKeys.date, .startTime, .kickoff, .videos].contains(where: values.contains)
    }
}

enum CommunitySportsMatchSelection: Equatable {
    case matched(CommunitySportsCatalogEntry)
    case missing
    case conflicting
}

struct CommunitySportsStreamEntry: Decodable, Sendable, Equatable {
    struct BehaviorHints: Decodable, Sendable, Equatable {
        struct ProxyHeaders: Decodable, Sendable, Equatable {
            let request: [String: String]?
            let response: [String: String]?

            private enum CodingKeys: String, CodingKey { case request, response }

            init(request: [String: String]? = nil, response: [String: String]? = nil) {
                self.request = request
                self.response = response
            }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                // An advertised null/non-string header contract is not absence.
                request = values.contains(.request) ? try values.decode([String: String].self, forKey: .request) : nil
                response = values.contains(.response) ? try values.decode([String: String].self, forKey: .response) : nil
            }
        }

        let proxyHeaders: ProxyHeaders?
    }

    let name: String?
    let title: String?
    let url: String?
    let externalURL: String?
    let resolution: String?
    let quality: String?
    let sourceHint: String?
    let behaviorHints: BehaviorHints?

    init(name: String?, title: String?, url: String?, externalURL: String?,
         resolution: String?, quality: String?, sourceHint: String?,
         behaviorHints: BehaviorHints? = nil) {
        self.name = name
        self.title = title
        self.url = url
        self.externalURL = externalURL
        self.resolution = resolution
        self.quality = quality
        self.sourceHint = sourceHint
        self.behaviorHints = behaviorHints
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, url, resolution, quality, behaviorHints
        case externalURL = "externalUrl"
        case sourceHint = "_source"
    }
}

/// Narrow Stremio-protocol adapter for Fotty's optional CS lane. The remote
/// catalog is lookup evidence only: an exact Fotty sport, team-pair and kickoff
/// match is required before any stream route can be requested.
actor CommunitySportsAddonClient {
    static let shared = CommunitySportsAddonClient()
    // A verified live CS response took sixteen seconds. Keep this larger
    // budget source-local; sibling adapters retain their existing deadlines.
    nonisolated static let streamRequestTimeout: TimeInterval = 23
    nonisolated static let streamTransportDeadline: TimeInterval = 24

    private struct ManifestDocument: Decodable, Sendable {
        struct CatalogDescriptor: Decodable, Sendable {
            struct Extra: Decodable, Sendable {
                let name: String
            }

            let id: String
            let type: String
            let extra: [Extra]?

            var supportsSearch: Bool { extra?.contains { $0.name == "search" } == true }
        }

        let id: String
        let version: String
        let resources: [String]
        let catalogs: [CatalogDescriptor]
    }

    private struct CatalogDocument: Decodable, Sendable {
        let metas: [CommunitySportsCatalogEntry]
    }
    private struct ChannelMetadataDocument: Decodable, Sendable { let meta: CommunitySportsCatalogEntry }

    private struct StreamDocument: Decodable, Sendable {
        let streams: [CommunitySportsStreamEntry]
        let entryCount: Int

        private enum CodingKeys: String, CodingKey { case streams }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard values.contains(.streams) else {
                streams = []; entryCount = 0; return
            }
            if try values.decodeNil(forKey: .streams) {
                streams = []; entryCount = 0; return
            }
            var rows = try values.nestedUnkeyedContainer(forKey: .streams)
            var admittedRows: [CommunitySportsStreamEntry] = []
            var scanned = 0
            while !rows.isAtEnd, scanned < 100 {
                let row = try rows.superDecoder()
                scanned += 1
                // Reject a malformed entry in full, including its advertised
                // header requirements, without erasing independent siblings.
                if let entry = try? CommunitySportsStreamEntry(from: row) {
                    admittedRows.append(entry)
                }
            }
            streams = admittedRows
            entryCount = scanned
        }
    }

    private struct ManifestSnapshot {
        let document: ManifestDocument
        let fetchedAt: Date
    }

    private struct CatalogSnapshot {
        let entries: [CommunitySportsCatalogEntry]
        let fetchedAt: Date
    }

    private let manifestURL: URL?
    private let transport: FottyBoundedHTTPClient
    private let manifestTTL: TimeInterval
    private let catalogTTL: TimeInterval
    private let negativeCatalogTTL: TimeInterval
    private let programmeEnablement: @Sendable () async -> Bool
    private let programmeCurrentRequest: @Sendable (StreamPlaybackRequest, Date) async -> StreamPlaybackRequest?
    private let programmeAssociations: @Sendable (StreamPlaybackRequest, Date) async -> [BroadcastRegistryMatch]
    private var manifestSnapshot: ManifestSnapshot?
    private var manifestRequestGeneration: UUID?
    private var catalogSnapshots: [String: CatalogSnapshot] = [:]
    private var catalogRequestGenerations: [String: UUID] = [:]

    init(
        manifestURL: URL? = Config.communitySportsManifestURL,
        session: URLSession? = nil,
        manifestTTL: TimeInterval = 30 * 60,
        catalogTTL: TimeInterval = 2 * 60,
        negativeCatalogTTL: TimeInterval = 15,
        programmeEnablement: @escaping @Sendable () async -> Bool = {
            await StreamPluginRegistry.shared.enabledProviderCodes().contains("communitysports")
        },
        programmeCurrentRequest: @escaping @Sendable (StreamPlaybackRequest, Date) async -> StreamPlaybackRequest? = { request, at in
            await MainActor.run { RegisteredDescriptorRecoveryPolicy.currentRequest(for: request,
                in: MatchListViewModel.shared.playbackAdmissionCatalog, at: at) }
        },
        programmeAssociations: @escaping @Sendable (StreamPlaybackRequest, Date) async -> [BroadcastRegistryMatch] = { request, at in
            await BroadcastRegistryClient.shared.lookup(for: request, enabledProviderCodes: ["communitysports"], at: at)
        }
    ) {
        self.manifestURL = manifestURL
        self.transport = FottyBoundedHTTPClient(configuration: session?.configuration ?? Self.makeConfiguration())
        self.manifestTTL = manifestTTL
        self.catalogTTL = catalogTTL
        self.negativeCatalogTTL = negativeCatalogTTL
        self.programmeEnablement = programmeEnablement
        self.programmeCurrentRequest = programmeCurrentRequest
        self.programmeAssociations = programmeAssociations
    }

    /// One bounded advertised snapshot for browsing. Catalog evidence never
    /// fetches descriptors, searches once per fixture or proves playback.
    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        try Task.checkCancellation()
        guard requests.count <= 256 else { throw CommunitySportsAddonError.invalidResponse }
        let eligible = requests.filter {
            $0.preferredEvent?.hasCatalogIdentityConflict != true
                && ReviewedSportsFixtureMatcher.requestIdentity(for: $0) != nil
        }
        guard !eligible.isEmpty else {
            return requests.map { .init(matchID: $0.matchID, outcome: .unsupported) }
        }
        guard let manifestURL, Self.isSafeManifestURL(manifestURL) else {
            throw CommunitySportsAddonError.configurationUnavailable
        }
        let manifest = try await loadManifest(from: manifestURL, now: now)
        var catalogIDs = Set(eligible.map { Self.catalogID(for: $0.category) })
        catalogIDs.insert("nuvio_sports_live")
        var entries: [CommunitySportsCatalogEntry] = []
        var failures: [String: StreamFailureCategory] = [:]
        // Sorting makes the finite request inventory deterministic. The sport
        // and Live cohorts stay together so neither hides a same-ID veto.
        for id in catalogIDs.sorted() where manifest.catalogs.contains(where: { $0.id == id && $0.type == "tv" }) {
            try Task.checkCancellation()
            do {
                entries.append(contentsOf: try await loadAdvertisedCatalog(id: id, manifest: manifest,
                    manifestURL: manifestURL, now: now))
            } catch {
                try Task.checkCancellation()
                guard !Self.isFatalCatalogBatchError(error) else { throw error }
                failures[id] = Self.catalogBatchFailureCategory(error)
            }
        }
        try Task.checkCancellation()
        let candidates = Self.catalogCandidates(entries)
        return requests.map { request in
            guard request.preferredEvent?.hasCatalogIdentityConflict != true,
                  ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else {
                return .init(matchID: request.matchID, outcome: .unsupported)
            }
            switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates) {
            case .matched(let index):
                let row = entries[index]
                guard Self.videoIDRejection(row.id) == nil,
                      Self.videoIDRejection(row.behaviorHints?.defaultVideoId ?? row.id) == nil else {
                    return .init(matchID: request.matchID, outcome: .conflicting)
                }
                return .init(matchID: request.matchID, outcome: .listed, providerEventID: row.id)
            case .missing:
                let relevant = [Self.catalogID(for: request.category), "nuvio_sports_live"].compactMap { failures[$0] }
                if !relevant.isEmpty {
                    return .init(matchID: request.matchID,
                        outcome: .failed(relevant.contains(.manifestInvalid) ? .manifestInvalid : .manifestUnreachable))
                }
                return .init(matchID: request.matchID, outcome: .notListed)
            case .conflicting: return .init(matchID: request.matchID, outcome: .conflicting)
            }
        }
    }

    nonisolated static func isFatalCatalogBatchError(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
            || (error as? CommunitySportsAddonError)?.isSecurityRejection == true
            || (error as? CommunitySportsAddonError) == .conflictingMatch
    }

    nonisolated static func catalogBatchFailureCategory(_ error: Error) -> StreamFailureCategory {
        guard let failure = error as? CommunitySportsAddonError else { return .manifestUnreachable }
        switch failure {
        case .invalidManifest, .invalidJSON, .invalidResponse, .configurationUnavailable: return .manifestInvalid
        default: return .manifestUnreachable
        }
    }

    func resolve(for request: StreamPlaybackRequest, now: Date = Date(),
                 forceRefresh: Bool = false) async throws -> [StreamSession] {
        try Task.checkCancellation()
        if let association = request.registryMatch {
            return try await resolveRegistered(association, request: request, now: now, forceRefresh: forceRefresh)
        }
        if let channel = CricketBroadcastChannel.identifying(request: request) {
            return try await resolveChannel(.cricket(channel), request: request, now: now, forceRefresh: forceRefresh)
        }
        if let channel = Self.tvNetwork(for: request) {
            return try await resolveChannel(channel, request: request, now: now, forceRefresh: forceRefresh)
        }
        guard let manifestURL, Self.isSafeManifestURL(manifestURL) else {
            throw CommunitySportsAddonError.configurationUnavailable
        }

        let hadCachedManifest = manifestSnapshot.map {
            now.timeIntervalSince($0.fetchedAt) >= 0 && now.timeIntervalSince($0.fetchedAt) < manifestTTL
        } ?? false
        var refreshed = forceRefresh
        var manifest = try await loadManifest(from: manifestURL, now: now, forceRefresh: forceRefresh)
        let preferredCatalogID = Self.catalogID(for: request.category)
        // A cached contract can predate a newly published sport catalog. One
        // targeted revalidation is allowed within the owning attempt; it does
        // not infer LIVE or retry transport/security/identity failures.
        if !refreshed, hadCachedManifest, Self.allowsTargetedRefresh(for: request, at: now),
           !manifest.catalogs.contains(where: { $0.type == "tv" && $0.id == preferredCatalogID }) {
            refreshed = true
            manifest = try await loadManifest(from: manifestURL, now: now, forceRefresh: true)
        }
        let preferredCatalogIsAdvertised = manifest.catalogs.contains {
            $0.type == "tv" && $0.id == preferredCatalogID
        }
        var preferredCatalogFailure: Error?
        var matchSelection: CommunitySportsMatchSelection
        // Keep all completed lookup evidence. A later targeted result may not
        // overwrite a contradictory metadata ID or stream target from an
        // ordinary catalog, including a malformed/nonmatching sibling.
        var lookupEntries: [CommunitySportsCatalogEntry] = []
        do {
            let entries = try await loadAdvertisedCatalog(
                id: preferredCatalogID,
                manifest: manifest,
                manifestURL: manifestURL,
                now: now,
                forceRefresh: refreshed
            )
            lookupEntries.append(contentsOf: entries)
            matchSelection = Self.selectMatch(for: request, from: lookupEntries)
        } catch {
            // A missing or temporarily broken sport catalog does not invalidate
            // the independently advertised Live catalog. Cancellation and unsafe
            // responses still end this lane rather than starting more work.
            try Task.checkCancellation()
            guard preferredCatalogID != "nuvio_sports_live",
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled,
                  (error as? CommunitySportsAddonError)?.isSecurityRejection != true,
                  (error as? CommunitySportsAddonError) != .conflictingMatch else { throw error }
            // An unadvertised optional sport catalog is expected absence. A
            // failed advertised catalog is evidence that an empty Live lookup
            // must not later misreport as an ordinary missing fixture.
            if preferredCatalogIsAdvertised { preferredCatalogFailure = error }
            matchSelection = .missing
        }

        // Some add-on deployments populate the Live catalog before the sport
        // catalog. The second lookup is still admitted by the same exact policy.
        if case .missing = matchSelection, preferredCatalogID != "nuvio_sports_live" {
            try Task.checkCancellation()
            let entries = try await loadAdvertisedCatalog(
                id: "nuvio_sports_live",
                manifest: manifest,
                manifestURL: manifestURL,
                now: now,
                forceRefresh: refreshed
            )
            lookupEntries.append(contentsOf: entries)
            matchSelection = Self.selectMatch(for: request, from: lookupEntries)
        }

        // Ordinary catalogs can be truncated by the publisher (currently 100
        // rows). Only an explicitly advertised search route may fill that gap;
        // team names are retrieval hints, never fixture or stream authority.
        // At most two requests use the first reviewed searchable catalog, and
        // the existing parent discovery deadline/cancellation still owns them.
        if case .missing = matchSelection,
           ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil,
           let catalog = [preferredCatalogID, "nuvio_sports_live"].compactMap({ id in
               manifest.catalogs.first { $0.type == "tv" && $0.id == id && $0.supportsSearch }
           }).first {
            for query in Self.searchQueries(for: request) {
                try Task.checkCancellation()
                guard let url = Self.searchCatalogURL(relativeTo: manifestURL, catalogID: catalog.id, query: query) else {
                    throw CommunitySportsAddonError.unsafeMetadata(stage: .catalog, reason: .searchRoute)
                }
                let document: CatalogDocument = try await fetchJSON(CatalogDocument.self,
                    from: url, anchoredTo: manifestURL, byteLimit: 700 * 1024, stage: .catalog,
                    forceRefresh: refreshed)
                guard document.metas.count <= 600 else { throw CommunitySportsAddonError.invalidResponse }
                lookupEntries.append(contentsOf: document.metas)
                matchSelection = Self.selectMatch(for: request, from: lookupEntries)
                if case .missing = matchSelection { continue }
                break
            }
        }

        let matched: CommunitySportsCatalogEntry
        switch matchSelection {
        case .matched(let entry): matched = entry
        case .missing:
            if let preferredCatalogFailure { throw preferredCatalogFailure }
            throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }

        let streamID = matched.behaviorHints?.defaultVideoId ?? matched.id
        if let rejection = Self.videoIDRejection(streamID) {
            throw CommunitySportsAddonError.unsafeMetadata(stage: .streams, reason: rejection,
                invalidScalar: rejection == .streamIDCharacters ? Self.videoIDInvalidScalar(streamID) : nil)
        }
        let streamURL = Self.routeURL(
            relativeTo: manifestURL,
            components: ["stream", "tv", "\(streamID).json"]
        )
        var document: StreamDocument = try await fetchJSON(
            StreamDocument.self,
            from: streamURL,
            anchoredTo: manifestURL,
            byteLimit: 256 * 1024,
            stage: .streams,
            forceRefresh: refreshed
        )
        if document.entryCount == 0, !refreshed, Self.allowsTargetedRefresh(for: request, at: now) {
            try Task.checkCancellation()
            refreshed = true
            // The same exact catalog match owns this one descriptor re-fetch.
            // Empty stays pending if it is still empty; admission failures and
            // HTTP/auth/security failures never enter a blind retry loop.
            document = try await fetchJSON(StreamDocument.self, from: streamURL, anchoredTo: manifestURL,
                byteLimit: 256 * 1024, stage: .streams, forceRefresh: true)
        }
        guard document.entryCount > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        let sessions = Self.makeSessions(
            from: document.streams,
            request: request,
            manifestURL: manifestURL,
            addOnVersion: manifest.version
        )
        guard !sessions.isEmpty else {
            throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: document.entryCount)
        }
        try Task.checkCancellation()
        let binding = StreamEventBinding(request: request,
            providerCode: StreamPluginProviderMatching.communitySportsProviderCode,
            providerEventID: matched.id, streamID: streamID,
            manifestRevision: manifest.version, verifiedAt: now,
            expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime), at: now)
        return sessions.map { $0.recordingEventBinding(binding, for: request, at: now) }
    }

    /// The accepted broadcast supplies its literal metadata/stream IDs. A fresh
    /// same-ID response must still corroborate those facts before any media
    /// descriptor is requested. No canonical kickoff replaces a source date.
    private func resolveRegistered(_ association: BroadcastRegistryMatch, request: StreamPlaybackRequest,
                                   now: Date, forceRefresh: Bool) async throws -> [StreamSession] {
        let record = association.broadcast
        let startedAt = ProcessInfo.processInfo.systemUptime
        let currentCricketListing = record.startBasis == "current-listing"
        var currentListingExpiry: Date?
        guard association.matches(request: request, providerCode: "communitysports",
            providerEventID: record.providerEventID, streamID: record.streamID, at: now),
              Self.videoIDRejection(record.providerEventID) == nil,
              Self.videoIDRejection(record.streamID) == nil,
              let manifestURL, Self.isSafeManifestURL(manifestURL) else { throw CommunitySportsAddonError.conflictingMatch }
        if association.programmeAuthority != nil {
            return try await resolveProgrammeChannel(association, request: request, now: now, manifestURL: manifestURL)
        }
        let manifest = try await loadManifest(from: manifestURL, now: now, forceRefresh: forceRefresh)
        guard manifest.resources.contains("meta"), manifest.resources.contains("stream") else {
            throw CommunitySportsAddonError.invalidManifest
        }
        let meta: ChannelMetadataDocument = try await fetchJSON(ChannelMetadataDocument.self,
            from: Self.routeURL(relativeTo: manifestURL, components: ["meta", "tv", record.providerEventID + ".json"]),
            anchoredTo: manifestURL, byteLimit: 700 * 1024, stage: .metadata, forceRefresh: true)
        let handoff: CSRegisteredHandoff?
        if meta.meta.id != record.providerEventID || (meta.meta.behaviorHints?.defaultVideoId ?? meta.meta.id) != record.streamID {
            handoff = try await verifyNHLHandoff(from: association, redirected: meta.meta, request: request,
                manifest: manifest, manifestURL: manifestURL, now: now)
        } else { handoff = nil }
        if handoff == nil && (record.kind == .channel || record.kind == .programme) {
            guard let channel = Self.channelIdentity(meta.meta), channel.channel.canonicalID == record.channelID else {
                throw CommunitySportsAddonError.conflictingMatch
            }
        } else if handoff == nil && currentCricketListing {
            // This reviewed dynamic FanCode branch synthesizes `released` from
            // fetch time. The registry's unique current official fixture owns
            // event time/format; a freshly fetched exact-ID listing must still
            // corroborate its participant pair before requesting a descriptor.
            guard association.link?.matchMethod == .currentEvent,
                  let identity = Self.currentCricketListingIdentity(for: meta.meta, at: now),
                  let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
                  identity.sport == requested.sport, identity.pair == requested.pair,
                  identity.pair == BroadcastRegistrySnapshot.participantPair(record.participants, sport: record.sport) else {
                throw CommunitySportsAddonError.conflictingMatch
            }
            currentListingExpiry = meta.meta.released.flatMap(BroadcastRegistrySnapshot.date)?
                .addingTimeInterval(BroadcastRegistrySnapshot.sourceLifetime)
        } else if handoff == nil {
            let candidates = Self.catalogCandidates([meta.meta])
            guard case .matched = ReviewedSportsFixtureMatcher.selectRegistered(for: request,
                association: association, from: candidates, at: now) else { throw CommunitySportsAddonError.conflictingMatch }
        }
        try Task.checkCancellation()
        let advertisedStream = handoff?.newID ?? record.streamID
        func completionTime() -> Date {
            handoff == nil && !currentCricketListing ? now
                : now.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - startedAt))
        }
        func currentListingStillValid(at time: Date) -> Bool {
            !currentCricketListing || currentListingExpiry.map { $0 > time } == true
                && association.matches(request: request, providerCode: "communitysports",
                    providerEventID: record.providerEventID, streamID: record.streamID, at: time)
        }
        guard handoff.map({ $0.expiresAt > completionTime() }) ?? true,
              currentListingStillValid(at: completionTime()) else { throw CommunitySportsAddonError.conflictingMatch }
        let document: StreamDocument = try await fetchJSON(StreamDocument.self,
            from: Self.routeURL(relativeTo: manifestURL, components: ["stream", "tv", advertisedStream + ".json"]),
            anchoredTo: manifestURL, byteLimit: 256 * 1024, stage: .streams, forceRefresh: true)
        guard document.entryCount > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        let completedAt = completionTime()
        guard currentListingStillValid(at: completedAt) else { throw CommunitySportsAddonError.conflictingMatch }
        let currentEvidenceExpiry = currentCricketListing
            ? min(currentListingExpiry ?? now, association.link?.expiresAt ?? now,
                  record.expiresAt, association.provider.expiresAt ?? now,
                  request.preferredEvent?.cricketFixture?.observedAt.addingTimeInterval(600) ?? now) : .distantFuture
        guard let binding = StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: handoff?.newID ?? record.providerEventID, streamID: advertisedStream, manifestRevision: manifest.version,
            verifiedAt: now, expiresAt: min(now.addingTimeInterval(StreamEventBinding.metadataLifetime),
                handoff?.expiresAt ?? .distantFuture, currentEvidenceExpiry), at: completedAt, csHandoff: handoff) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let sessions = Self.makeSessions(from: document.streams, request: request, manifestURL: manifestURL,
            addOnVersion: manifest.version).map { $0.recordingEventBinding(binding, for: request, at: completedAt) }
        try Task.checkCancellation()
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: document.entryCount) }
        return sessions
    }

    private func verifyNHLHandoff(from association: BroadcastRegistryMatch, redirected: CommunitySportsCatalogEntry,
                                  request: StreamPlaybackRequest, manifest: ManifestDocument, manifestURL: URL, now: Date) async throws -> CSRegisteredHandoff {
        let old = association.broadcast
        guard old.providerCode == "communitysports", old.kind == .event, old.scope == "hockey", old.sport == "hockey",
              association.link?.state == .listed, association.link?.matchMethod == .exact,
              old.providerEventID == old.streamID, old.providerEventID.range(of: #"^nuvio_sport_dlv_[0-9]+_[a-z0-9-]+$"#, options: .regularExpression) != nil,
              let fixture = request.preferredEvent?.sportsFixture, fixture.fixtureID == request.matchID,
              fixture.sport == "hockey", fixture.competitionID == "nhl", fixture.eventKind == .match,
              fixture.squad.gender == .men, fixture.squad.ageGroup == "senior", fixture.isLive(at: now),
              let official = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              let source = Self.fixtureIdentity(for: redirected),
              source.sport == official.sport, source.pair == official.pair, source.kickoff == official.kickoff,
              old.start == official.kickoff, redirected.cast?.count == 2, !redirected.hasAdditionalEventTimeAuthority,
              redirected.type == "tv", redirected.genres == ["HOCKEY"], redirected.releaseInfo == "LIVE",
              redirected.id.range(of: #"^nuvio_sport_ts_[a-z0-9-]+-[0-9]+$"#, options: .regularExpression) != nil,
              Self.videoIDRejection(redirected.id) == nil, source.effectiveID == redirected.id,
              redirected.behaviorHints?.defaultVideoId == redirected.id else { throw CommunitySportsAddonError.conflictingMatch }

        let rows = try await loadAdvertisedCatalog(id: Self.catalogID(for: "hockey"), manifest: manifest,
            manifestURL: manifestURL, now: now, forceRefresh: true)
        let candidates = Self.catalogCandidates(rows)
        guard case .matched(let index) = ReviewedSportsFixtureMatcher.select(for: official, from: candidates),
              candidates[index].metadataID == redirected.id, candidates[index].identity == source,
              rows[index].type == "tv", rows[index].cast?.count == 2, !rows[index].hasAdditionalEventTimeAuthority,
              rows[index].behaviorHints?.defaultVideoId == redirected.id, rows[index].releaseInfo == "LIVE",
              rows[index].genres == ["HOCKEY"] else { throw CommunitySportsAddonError.conflictingMatch }
        let current: ChannelMetadataDocument = try await fetchJSON(ChannelMetadataDocument.self,
            from: Self.routeURL(relativeTo: manifestURL, components: ["meta", "tv", redirected.id + ".json"]),
            anchoredTo: manifestURL, byteLimit: 700 * 1024, stage: .metadata, forceRefresh: true)
        guard current.meta.id == redirected.id, current.meta.behaviorHints?.defaultVideoId == redirected.id,
              current.meta.type == "tv", current.meta.cast?.count == 2, !current.meta.hasAdditionalEventTimeAuthority,
              current.meta.genres == ["HOCKEY"], current.meta.releaseInfo == "LIVE",
              Self.fixtureIdentity(for: current.meta) == source else { throw CommunitySportsAddonError.conflictingMatch }
        return CSRegisteredHandoff(fixtureID: request.matchID, oldID: old.providerEventID, newID: redirected.id,
            expiresAt: min(now.addingTimeInterval(StreamEventBinding.metadataLifetime), association.acceptanceExpiresAt))
    }

    /// Join only the original accepted guide and current CS channel facts.
    /// This does not reclassify a conflicting Day-labelled event as a channel.
    private func currentProgrammeRequest(for request: StreamPlaybackRequest, association: BroadcastRegistryMatch,
                                         at now: Date) async -> StreamPlaybackRequest? {
        guard await programmeEnablement(), !Task.isCancelled,
              let original = association.programmeAuthority,
              let current = await programmeCurrentRequest(request, now) else { return nil }
        let matches = await programmeAssociations(current, now).filter { candidate in
            candidate.programmeAuthority?.broadcast.providerEventID == original.broadcast.providerEventID
                && candidate.broadcast.providerCode == "communitysports"
                && candidate.broadcast.providerEventID == association.broadcast.providerEventID
                && candidate.broadcast.streamID == association.broadcast.streamID
                && candidate.matches(request: current, providerCode: "communitysports",
                    providerEventID: candidate.broadcast.providerEventID, streamID: candidate.broadcast.streamID, at: now)
        }
        guard matches.count == 1, let currentAssociation = matches.first,
              await programmeEnablement(), !Task.isCancelled else { return nil }
        return current.usingRegistryMatch(currentAssociation)
    }

    /// A programme proof permits one fresh lookup of the literal CS NETWORKS
    /// identity. Catalog/meta agreement and delivery guards remain the same as
    /// channel browsing, while the returned binding owns the official fixture.
    private func resolveProgrammeChannel(_ association: BroadcastRegistryMatch, request: StreamPlaybackRequest,
                                        now: Date, manifestURL: URL) async throws -> [StreamSession] {
        let started = Date(), record = association.broadcast
        guard var accepted = await currentProgrammeRequest(for: request, association: association, at: now) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let manifest = try await loadManifest(from: manifestURL, now: now, forceRefresh: true)
        guard manifest.resources.contains("meta"), manifest.resources.contains("stream") else {
            throw CommunitySportsAddonError.invalidManifest
        }
        guard let channel = CricketBroadcastChannel.allCases.first(where: { $0.canonicalID == record.channelID }) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let catalog = try await loadChannelCatalog(.cricket(channel), manifest: manifest, manifestURL: manifestURL,
            now: now, forceRefresh: true)
        let channels = try Self.channelEntries(.cricket(channel), from: catalog)
        guard let selected = channels.first(where: { $0.id == record.providerEventID
            && ($0.behaviorHints?.defaultVideoId ?? $0.id) == record.streamID }),
              let selectedIdentity = Self.channelIdentity(selected), Self.isReviewedProgrammeChannel(selectedIdentity, channel: channel) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let meta: ChannelMetadataDocument = try await fetchJSON(ChannelMetadataDocument.self,
            from: Self.routeURL(relativeTo: manifestURL, components: ["meta", "tv", record.providerEventID + ".json"]),
            anchoredTo: manifestURL, byteLimit: 700 * 1024, stage: .metadata, forceRefresh: true)
        guard meta.meta.id == selected.id, Self.channelIdentity(meta.meta) == Self.channelIdentity(selected) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        try Task.checkCancellation()
        let beforeDescriptor = now.addingTimeInterval(max(0, Date().timeIntervalSince(started)))
        guard let current = await currentProgrammeRequest(for: accepted, association: association, at: beforeDescriptor) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        accepted = current
        let document: StreamDocument = try await fetchJSON(StreamDocument.self,
            from: Self.routeURL(relativeTo: manifestURL, components: ["stream", "tv", record.streamID + ".json"]),
            anchoredTo: manifestURL, byteLimit: 256 * 1024, stage: .streams, forceRefresh: true)
        try Task.checkCancellation()
        guard document.entryCount > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(started)))
        guard let current = await currentProgrammeRequest(for: accepted, association: association, at: completedAt),
              let proof = current.registryMatch,
              let binding = StreamEventBinding(request: current, providerCode: "communitysports",
                providerEventID: record.providerEventID, streamID: record.streamID, manifestRevision: manifest.version,
                verifiedAt: completedAt, expiresAt: min(completedAt.addingTimeInterval(StreamEventBinding.metadataLifetime),
                    proof.acceptanceExpiresAt), at: completedAt) else { throw CommunitySportsAddonError.conflictingMatch }
        let sessions = Self.makeSessions(from: document.streams, request: current, manifestURL: manifestURL,
            addOnVersion: manifest.version, eventBinding: binding, at: completedAt)
        guard !sessions.isEmpty, sessions.allSatisfy({ $0.eventBinding != nil }) else {
            throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: document.entryCount)
        }
        return sessions
    }

    nonisolated static func supportsSportsTVChannel(_ request: StreamPlaybackRequest) -> Bool {
        tvNetwork(for: request) != nil
    }

    nonisolated private static func tvNetwork(for request: StreamPlaybackRequest) -> NetworkChannel? {
        guard let station = SportsTVStation.identifying(request),
              let profile = TVNetwork.allCases.first(where: { $0.channelID == station.id }) else { return nil }
        return .television(profile)
    }

    private enum TVNetwork: String, CaseIterable, Sendable {
        case skyCricket = "Sky Sports Cricket"
        case skyFootball = "Sky Sports Football"
        case fs1 = "Fox Sports 1"
        case skyMain = "Sky Sports Main Event"
        var channelID: String {
            switch self {
            case .skyCricket: "sports-channel:sky-sports-cricket"
            case .skyFootball: "sports-channel:sky-sports-football"
            case .fs1: "sports-channel:fox-sports-1-us"
            case .skyMain: "sports-channel:sky-sports-main-event"
            }
        }
        var country: String { self == .fs1 ? "United States" : "United Kingdom" }
    }

    private enum NetworkChannel: Equatable {
        case cricket(CricketBroadcastChannel)
        case television(TVNetwork)
        var canonicalID: String {
            switch self {
            case .cricket(let channel): channel.canonicalID
            case .television(let profile): profile.channelID
            }
        }
        var title: String {
            switch self {
            case .cricket(let channel): channel.title
            case .television(let profile): profile.rawValue
            }
        }
        var cacheKey: String { canonicalID }
        static func identifying(title: String) -> Self? {
            if let channel = CricketBroadcastChannel.identifying(title: title) { return .cricket(channel) }
            let value = title.hasPrefix("📺 ") ? String(title.dropFirst(2)) : title
            return TVNetwork.allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }.map(Self.television)
        }
    }

    private struct ChannelIdentity: Equatable {
        let channel: NetworkChannel
        let name: String
        let description: String
        let target: String
    }

    /// The reviewed guides identify US Willow and AU Fox. A different or absent
    /// regional label remains browsable, but gains no fixture programme claim.
    nonisolated private static func isReviewedProgrammeChannel(_ identity: ChannelIdentity, channel: CricketBroadcastChannel) -> Bool {
        guard identity.channel == .cricket(channel),
              let country = identity.description.components(separatedBy: "\n").first,
              country.hasPrefix("🏆 League: ") else { return false }
        let value = country.dropFirst("🏆 League: ".count).trimmingCharacters(in: .whitespaces).lowercased()
        switch channel {
        case .willow: return ["united states", "united states of america", "usa"].contains(value)
        case .foxCricket: return value == "australia"
        }
    }

    nonisolated private static func channelIdentity(_ entry: CommunitySportsCatalogEntry) -> ChannelIdentity? {
        guard !entry.hasUnreviewedChannelAuthority, entry.type == "tv", entry.genres == ["NETWORKS"],
              videoIDRejection(entry.id) == nil, let target = entry.behaviorHints?.defaultVideoId,
              videoIDRejection(target) == nil, entry.released == nil, entry.cast?.isEmpty ?? true,
              entry.name.utf8.count <= 128, entry.name.rangeOfCharacter(from: .controlCharacters) == nil,
              let channel = NetworkChannel.identifying(title: entry.name),
              let description = entry.description, description.utf8.count <= 512 else { return nil }
        let lines = description.components(separatedBy: "\n")
        guard lines.count == 3, lines[0].hasPrefix("🏆 League: "), lines[0].count > "🏆 League: ".count,
              !lines[0].contains("://"), lines[0].rangeOfCharacter(from: .controlCharacters) == nil,
              lines[1] == "📅 Category: NETWORKS", lines[2] == "⏰ Status: 24/7 Live Network" else { return nil }
        if case .television(let profile) = channel, lines[0] != "🏆 League: " + profile.country { return nil }
        return .init(channel: channel, name: entry.name, description: description, target: target)
    }

    nonisolated private static func channelEntries(_ channel: NetworkChannel,
                                                  from entries: [CommunitySportsCatalogEntry]) throws -> [CommunitySportsCatalogEntry] {
        guard entries.count <= 600 else { throw CommunitySportsAddonError.invalidResponse }
        var seen = Set<String>(), selected: [CommunitySportsCatalogEntry] = []
        for entry in entries {
            guard let identity = channelIdentity(entry), identity.channel == channel else { continue }
            let siblings = entries.filter { $0.id == entry.id || ($0.behaviorHints?.defaultVideoId ?? $0.id) == identity.target }
            guard siblings.allSatisfy({ channelIdentity($0) == identity }) else { throw CommunitySportsAddonError.conflictingMatch }
            if seen.insert(entry.id).inserted { selected.append(entry) }
        }
        guard selected.count <= 2 else { throw CommunitySportsAddonError.conflictingMatch }
        return selected
    }

    private func loadChannelCatalog(_ channel: NetworkChannel, manifest: ManifestDocument,
                                    manifestURL: URL, now: Date, forceRefresh: Bool) async throws -> [CommunitySportsCatalogEntry] {
        let catalogID = "nuvio_sports_networks", cacheKey = "channel:" + channel.cacheKey
        let advertised = manifest.catalogs.filter { $0.id == catalogID }
        guard advertised.count == 1, advertised[0].type == "tv", advertised[0].supportsSearch else {
            throw CommunitySportsAddonError.invalidManifest
        }
        if !forceRefresh, let cached = catalogSnapshots[cacheKey],
           (0..<(cached.entries.isEmpty ? negativeCatalogTTL : catalogTTL)).contains(now.timeIntervalSince(cached.fetchedAt)) {
            return cached.entries
        }
        let generation = UUID(); catalogRequestGenerations[cacheKey] = generation
        guard let url = Self.searchCatalogURL(relativeTo: manifestURL, catalogID: catalogID, query: channel.title) else {
            throw CommunitySportsAddonError.unsafeMetadata(stage: .catalog, reason: .searchRoute)
        }
        let document: CatalogDocument = try await fetchJSON(CatalogDocument.self, from: url, anchoredTo: manifestURL,
            byteLimit: 700 * 1024, stage: .catalog, forceRefresh: forceRefresh)
        guard document.metas.count <= 600 else { throw CommunitySportsAddonError.invalidResponse }
        try Task.checkCancellation()
        if catalogRequestGenerations[cacheKey] == generation {
            catalogSnapshots[cacheKey] = .init(entries: document.metas, fetchedAt: now)
        }
        return document.metas
    }

    private func resolveChannel(_ channel: NetworkChannel, request: StreamPlaybackRequest,
                                now: Date, forceRefresh: Bool) async throws -> [StreamSession] {
        guard let manifestURL, Self.isSafeManifestURL(manifestURL) else { throw CommunitySportsAddonError.configurationUnavailable }
        let manifest = try await loadManifest(from: manifestURL, now: now, forceRefresh: forceRefresh)
        guard manifest.resources.contains("meta"), manifest.resources.contains("stream") else { throw CommunitySportsAddonError.invalidManifest }
        let catalog = try await loadChannelCatalog(channel, manifest: manifest, manifestURL: manifestURL, now: now, forceRefresh: forceRefresh)
        let choices = try Self.channelEntries(channel, from: catalog)
        guard !choices.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        // Corroborate every selected identity before any descriptor lookup.
        for choice in choices {
            let meta: ChannelMetadataDocument = try await fetchJSON(ChannelMetadataDocument.self,
                from: Self.routeURL(relativeTo: manifestURL, components: ["meta", "tv", choice.id + ".json"]),
                anchoredTo: manifestURL, byteLimit: 700 * 1024, stage: .metadata, forceRefresh: forceRefresh)
            guard meta.meta.id == choice.id, Self.channelIdentity(meta.meta) == Self.channelIdentity(choice) else {
                throw CommunitySportsAddonError.conflictingMatch
            }
        }
        var documents: [(entry: CommunitySportsCatalogEntry, streams: [CommunitySportsStreamEntry])] = []
        var totalEntries = 0, lastFailure: Error?
        for choice in choices {
            try Task.checkCancellation()
            do {
                let target = choice.behaviorHints?.defaultVideoId ?? choice.id
                let document: StreamDocument = try await fetchJSON(StreamDocument.self,
                    from: Self.routeURL(relativeTo: manifestURL, components: ["stream", "tv", target + ".json"]),
                    anchoredTo: manifestURL, byteLimit: 256 * 1024, stage: .streams, forceRefresh: forceRefresh)
                totalEntries += document.entryCount
                documents.append((choice, document.streams))
            } catch {
                try Task.checkCancellation()
                if Self.isFatalCatalogBatchError(error) { throw error }
                lastFailure = error
            }
        }
        if totalEntries == 0 {
            if let lastFailure { throw lastFailure }
            throw CommunitySportsAddonError.streamEntriesEmpty
        }
        let sessions = Self.makeSessions(from: documents.flatMap(\.streams), request: request,
            manifestURL: manifestURL, addOnVersion: manifest.version, entryLimit: 200)
        let provenance = documents.map { document in
            (document.entry, Set(Self.makeSessions(from: document.streams, request: request,
                manifestURL: manifestURL, addOnVersion: manifest.version).map {
                    StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders)
                }))
        }
        let bound = sessions.compactMap { session -> StreamSession? in
            let identity = StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)
            guard let entry = provenance.first(where: { $0.1.contains(identity) })?.0,
                  let binding = StreamEventBinding(request: request, providerCode: StreamPluginProviderMatching.communitySportsProviderCode,
                    providerEventID: entry.id, streamID: entry.behaviorHints?.defaultVideoId ?? entry.id,
                    manifestRevision: manifest.version, verifiedAt: now,
                    expiresAt: now.addingTimeInterval(StreamEventBinding.metadataLifetime), at: now) else { return nil }
            return session.recordingEventBinding(binding, for: request, at: now)
        }
        try Task.checkCancellation()
        guard !bound.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: totalEntries) }
        return bound
    }

    /// Eligibility for one lookup revalidation, never an assertion of LIVE or
    /// availability. Football uses the existing late-discovery bounds. Cricket
    /// requires its fresh official status instead of guessing a Test duration.
    nonisolated static func allowsTargetedRefresh(for request: StreamPlaybackRequest, at now: Date) -> Bool {
        guard ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else { return false }
        if ReviewedSportsFixtureMatcher.sportKey(request.category) == "football" {
            return Score808LateDiscoveryPolicy.isLookupWindow(kickoffDate: request.kickoffDate,
                category: "football", at: now)
        }
        guard ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket",
              let event = request.preferredEvent, event.id == request.matchID,
              !event.hasCatalogIdentityConflict, event.kickoffDate == request.kickoffDate,
              let fixture = event.cricketFixture, fixture.verified else { return false }
        if fixture.isLive(at: now) { return true }
        guard fixture.status == .scheduled, let kickoff = request.kickoffDate else { return false }
        return (0...Score808LateDiscoveryPolicy.lookupLeadTime).contains(kickoff.timeIntervalSince(now))
            && (-300...CricketFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(fixture.observedAt))
    }

    private func loadAdvertisedCatalog(
        id catalogID: String,
        manifest: ManifestDocument,
        manifestURL: URL,
        now: Date,
        forceRefresh: Bool = false
    ) async throws -> [CommunitySportsCatalogEntry] {
        guard manifest.catalogs.contains(where: { $0.type == "tv" && $0.id == catalogID }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        return try await loadCatalog(
            id: catalogID,
            manifestURL: manifestURL,
            now: now,
            forceRefresh: forceRefresh
        )
    }

    nonisolated private static func searchQueries(for request: StreamPlaybackRequest) -> [String] {
        var seen = Set<String>()
        return [request.homeTeam, request.awayTeam].compactMap { name in
            guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            let entered = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // Official fixture projections can include legal FC/AFC/CF tokens
            // that the publisher's literal search does not index. Normalize
            // only those reviewed football spellings; already working literal
            // aliases such as Brighton must not expand into longer names.
            // Never strip arbitrary suffixes or squad qualifiers from teams.
            let legalTokens: Set<String> = ["fc", "afc", "cf"]
            let hasLegalToken = SportsTeamIdentity.normalized(entered).split(separator: " ")
                .contains { legalTokens.contains(String($0)) }
            let reviewed: String?
            if hasLegalToken, ReviewedSportsFixtureMatcher.sportKey(request.category) == "football",
               let clubID = FootballCompetitionCatalog.canonicalClubID(for: entered) {
                reviewed = (FootballCompetitionCatalog.snapshots.values.flatMap(\.clubs)
                    + FootballCompetitionCatalog.additionalClubIdentities)
                    .filter { FootballCompetitionCatalog.canonicalClubID(for: $0.name) == clubID }
                    .map(\.name).min { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
            } else { reviewed = nil }
            let query = reviewed ?? entered
            guard !query.isEmpty, query.utf8.count <= 128,
                  seen.insert(query.lowercased()).inserted else { return nil }
            return query
        }
    }

    nonisolated static func searchCatalogURL(relativeTo manifestURL: URL, catalogID: String, query: String) -> URL? {
        // Encode the entire public team name as one path value, including '/',
        // '?', '&', '%' and '=', instead of letting it change the fixed route.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard !query.isEmpty, query.utf8.count <= 128,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: unreserved),
              var parts = URLComponents(url: routeURL(relativeTo: manifestURL,
                  components: ["catalog", "tv", catalogID]), resolvingAgainstBaseURL: false) else { return nil }
        parts.percentEncodedPath += "/search=\(encoded).json"
        return parts.url
    }

    private func loadManifest(from url: URL, now: Date, forceRefresh: Bool = false) async throws -> ManifestDocument {
        if !forceRefresh, let snapshot = manifestSnapshot,
           now.timeIntervalSince(snapshot.fetchedAt) >= 0,
           now.timeIntervalSince(snapshot.fetchedAt) < manifestTTL {
            return snapshot.document
        }
        let generation = UUID()
        manifestRequestGeneration = generation
        let document: ManifestDocument = try await fetchJSON(
            ManifestDocument.self,
            from: url,
            anchoredTo: url,
            byteLimit: 128 * 1024,
            stage: .manifest,
            forceRefresh: forceRefresh
        )
        guard document.id == "community.nuvio.live-sports",
              !document.version.isEmpty,
              document.resources.contains("catalog"),
              document.resources.contains("stream"),
              document.catalogs.contains(where: { $0.type == "tv" && $0.id == "nuvio_sports_live" }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        // As with catalog fetches, a late older manifest may satisfy its caller
        // but cannot replace a newer request's cached contract.
        try Task.checkCancellation()
        if manifestRequestGeneration == generation {
            manifestSnapshot = ManifestSnapshot(document: document, fetchedAt: now)
        }
        return document
    }

    private func loadCatalog(
        id: String,
        manifestURL: URL,
        now: Date,
        forceRefresh: Bool = false
    ) async throws -> [CommunitySportsCatalogEntry] {
        if !forceRefresh, let snapshot = catalogSnapshots[id],
           now.timeIntervalSince(snapshot.fetchedAt) >= 0,
           now.timeIntervalSince(snapshot.fetchedAt) < (snapshot.entries.isEmpty ? negativeCatalogTTL : catalogTTL) {
            return snapshot.entries
        }
        // Actor reentrancy permits overlapping fetches. A late older response
        // can satisfy its caller, but cannot replace a newer request's cache.
        let generation = UUID()
        catalogRequestGenerations[id] = generation
        let url = Self.routeURL(
            relativeTo: manifestURL,
            components: ["catalog", "tv", "\(id).json"]
        )
        let document: CatalogDocument = try await fetchJSON(
            CatalogDocument.self,
            from: url,
            anchoredTo: manifestURL,
            byteLimit: 700 * 1024,
            stage: .catalog,
            forceRefresh: forceRefresh
        )
        guard document.metas.count <= 600 else { throw CommunitySportsAddonError.invalidResponse }
        try Task.checkCancellation()
        let snapshot = CatalogSnapshot(entries: document.metas, fetchedAt: now)
        if catalogRequestGenerations[id] == generation { catalogSnapshots[id] = snapshot }
        return snapshot.entries
    }

    private func fetchJSON<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        anchoredTo manifestURL: URL,
        byteLimit: Int,
        stage: CommunitySportsRequestStage,
        forceRefresh: Bool = false
    ) async throws -> Value {
        guard Self.hasSameHTTPSOrigin(url, manifestURL) else {
            throw CommunitySportsAddonError.unsafeMetadata(stage: stage, reason: .requestOrigin)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = stage == .streams ? Self.streamRequestTimeout : stage.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        let result: FottyBoundedHTTPClient.Response
        do {
            result = try await transport.fetch(request, maximumBytes: byteLimit,
                deadline: stage == .streams ? Self.streamTransportDeadline : stage.transportDeadline,
                redirectPolicy: { source, destination in
                    Self.allowsRedirect(from: source, to: destination, anchoredTo: manifestURL)
                })
        } catch let failure as FottyBoundedHTTPClient.Failure {
            try Task.checkCancellation()
            if failure == .unsafeRedirect {
                throw CommunitySportsAddonError.unsafeMetadata(stage: stage, reason: .redirect)
            }
            if case .httpStatus(let statusCode) = failure {
                throw CommunitySportsAddonError.httpFailure(statusCode: statusCode, stage: stage)
            }
            throw CommunitySportsAddonError.invalidResponse
        } catch let error as URLError {
            try Task.checkCancellation()
            // Cancellation must end the lane; it is not an outage and must not
            // start the optional Live-catalog fallback.
            if error.code == .cancelled { throw error }
            throw CommunitySportsAddonError.transportFailure(code: error.errorCode, stage: stage)
        }
        let data = result.data
        let http = result.http
        try Task.checkCancellation()
        guard Self.hasSameHTTPSOrigin(http.url ?? url, manifestURL) else {
            throw CommunitySportsAddonError.unsafeMetadata(stage: stage, reason: .responseOrigin)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CommunitySportsAddonError.httpFailure(statusCode: http.statusCode, stage: stage)
        }
        if http.expectedContentLength > Int64(byteLimit) || data.count > byteLimit {
            throw CommunitySportsAddonError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CommunitySportsAddonError.invalidJSON(stage: stage)
        }
    }

    nonisolated static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = Self.streamTransportDeadline
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    nonisolated static func selectMatch(
        for request: StreamPlaybackRequest,
        from entries: [CommunitySportsCatalogEntry]
    ) -> CommunitySportsMatchSelection {
        let candidates = catalogCandidates(entries)
        switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates) {
        case .matched(let index): return .matched(entries[index])
        case .missing: return .missing
        case .conflicting: return .conflicting
        }
    }

    nonisolated private static func catalogCandidates(_ entries: [CommunitySportsCatalogEntry]) -> [ReviewedSportsFixtureMatcher.Candidate] {
        entries.map {
            .init(metadataID: $0.id, effectiveID: $0.behaviorHints?.defaultVideoId ?? $0.id,
                  identity: fixtureIdentity(for: $0))
        }
    }

    nonisolated static func makeSessions(
        from streams: [CommunitySportsStreamEntry],
        request: StreamPlaybackRequest,
        manifestURL: URL,
        addOnVersion: String,
        entryLimit: Int = 100,
        eventBinding: StreamEventBinding? = nil,
        at now: Date = Date()
    ) -> [StreamSession] {
        guard let definition = CuratedStreamSourceCatalog.definition(
            forProviderCode: StreamPluginProviderMatching.communitySportsProviderCode) else { return [] }
        if let eventBinding, !eventBinding.matches(request: request,
            providerCode: StreamPluginProviderMatching.communitySportsProviderCode, at: now) { return [] }
        var seen = Set<StreamDeliveryIdentity>()
        var admitted: [(entry: CommunitySportsStreamEntry, url: URL, isWeb: Bool,
                        directHLS: Bool, headers: [String: String])] = []

        // The standalone channel path can combine two independently verified
        // 100-row descriptors. Ordinary fixture resolution keeps its old cap.
        for entry in streams.prefix(min(max(entryLimit, 0), 200)) {
            let candidates = [entry.url, entry.externalURL].compactMap { $0 }.compactMap(URL.init(string:))
            guard let accepted = candidates.compactMap({ candidate -> (URL, Bool)? in
                guard let isWeb = admittedDelivery(candidate, manifestURL: manifestURL,
                                                   sourceHint: entry.sourceHint) else { return nil }
                return (candidate, isWeb)
            }).first else { continue }
            let directHLS = isReviewedDirectHLS(accepted.0, manifestURL: manifestURL, sourceHint: entry.sourceHint)
            guard let requestHeaders = admittedRequestHeaders(for: entry, deliveryURL: accepted.0,
                                                              reviewedDirectHLS: directHLS) else { continue }
            guard accepted.1 || admitsWrappedTarget(accepted.0, manifestURL: manifestURL,
                sourceHint: entry.sourceHint, headers: requestHeaders) else { continue }
            // The reviewed header contract is native HLS only. Do not silently
            // drop advertised requirements on a Web route that cannot apply them.
            guard !accepted.1 || requestHeaders.isEmpty else { continue }
            let headers = accepted.1 ? ["X-Fotty-Web-Embed": "true"] : requestHeaders
            guard seen.insert(StreamDeliveryIdentity(url: accepted.0, headers: headers)).inserted else { continue }
            admitted.append((entry, accepted.0, accepted.1, directHLS, headers))
        }

        // One upstream can advertise many equivalent quality/channel variants.
        // Reserve a first valid choice for each opaque source group before
        // filling the six slots, so early variants cannot hide other providers.
        // Admission/delivery deduplication above and response order stay intact.
        var selectedIndices = Set<Int>()
        var representedSources = Set<String>()
        for index in admitted.indices {
            let item = admitted[index]
            let identity = sourceIdentity(for: item.entry, deliveryURL: item.url)
            if representedSources.insert(identity.key).inserted {
                selectedIndices.insert(index)
                if selectedIndices.count == 6 { break }
            }
        }
        for index in admitted.indices where selectedIndices.count < 6 {
            selectedIndices.insert(index)
        }
        let selected = admitted.enumerated().filter { selectedIndices.contains($0.offset) }.map(\.element)

        return selected.enumerated().compactMap { index, item -> StreamSession? in
            guard let label = definition.sourceLabel(choice: index + 1) else { return nil }
            let identity = sourceIdentity(for: item.entry, deliveryURL: item.url)
            return StreamSession(
                matchID: request.matchID,
                playableURL: item.url,
                streamType: item.isWeb ? .unknown : .hls,
                providerName: label,
                requiredHeaders: item.headers,
                qualityLabel: qualityLabel(for: item.entry),
                expiryTime: eventBinding?.expiresAt,
                canRefresh: eventBinding != nil && !item.isWeb,
                validationStatus: .validated,
                diagnosticMetadata: [
                    "source_family": StreamPluginProviderMatching.communitySportsProviderCode,
                    "manifest_result": request.registryMatch?.programmeAuthority != nil ? "verified_programme_channel_match"
                        : CricketBroadcastChannel.identifying(request: request) != nil || Self.supportsSportsTVChannel(request)
                            ? "exact_channel_match" : "exact_fixture_match",
                    "delivery": item.isWeb ? "same_origin_web"
                        : item.directHLS ? "reviewed_direct_hls" : "same_origin_hls_proxy",
                    "addon_version": String(addOnVersion.prefix(24)),
                    "source_hint": sanitizedSourceHint(item.entry.sourceHint),
                    "source_key": identity.key,
                    "source_key_scope": identity.scope
                ],
                createdAt: now,
                nativeOriginProfile: item.isWeb ? nil : LocalStreamProxyOriginProfile.communitySports(
                    deliveryURL: item.url, manifestURL: manifestURL,
                    sourceHint: item.entry.sourceHint, headers: item.headers),
                nativePlaylistProfile: item.isWeb ? nil : LocalStreamProxyPlaylistProfile.communitySports(
                    deliveryURL: item.url, manifestURL: manifestURL,
                    sourceHint: item.entry.sourceHint, headers: item.headers),
                // The new headerless HLS alias still needs per-reference
                // destination/redirect checks in the native guarded relay.
                requiresGuardedRelay: !item.isWeb && item.url.path.hasSuffix(".m3u8"),
                eventBinding: eventBinding
            )
        }
    }

    /// Only the reviewed, public request provenance enters the existing guarded
    /// local proxy. No credentials or response mutation; the approved direct
    /// route has its own fixed public provenance rather than proxy-query hints.
    nonisolated private static func admittedRequestHeaders(
        for entry: CommunitySportsStreamEntry, deliveryURL: URL,
        reviewedDirectHLS: Bool = false
    ) -> [String: String]? {
        guard let proxy = entry.behaviorHints?.proxyHeaders else { return reviewedDirectHLS ? nil : [:] }
        guard proxy.response?.isEmpty ?? true else { return nil }
        let request = proxy.request ?? [:]
        guard request.count <= 3 else { return nil }
        let canonical = ["referer": "Referer", "origin": "Origin", "user-agent": "User-Agent"]
        var headers: [String: String] = [:]
        for (name, value) in request {
            guard let key = canonical[name.lowercased()], headers[key] == nil,
                  !value.isEmpty, value.utf8.count <= 512,
                  value.utf8.allSatisfy({ (32...126).contains($0) }) else { return nil }
            headers[key] = value
        }
        if reviewedDirectHLS {
            if deliveryURL.host?.lowercased() == "cdnlivetv.tv" {
                guard Set(headers.keys) == Set(["Origin", "Referer", "User-Agent"]),
                      headers["Origin"] == "https://cdnlivetv.tv",
                      headers["Referer"] == "https://cdnlivetv.tv/",
                      headers["User-Agent"]?.hasPrefix("Mozilla/5.0 ") == true else { return nil }
                return headers
            }
            guard Set(headers.keys) == Set(["Referer", "User-Agent"]),
                  headers["Referer"] == "https://fancode.com/",
                  let userAgent = headers["User-Agent"],
                  userAgent.hasPrefix("ReactNativeVideo/"),
                  userAgent.count > "ReactNativeVideo/".count else { return nil }
            return headers
        }
        let query = URLComponents(url: deliveryURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var provenance: [String: URL] = [:]
        for (header, parameter) in [("Referer", "referer"), ("Origin", "origin")] {
            guard let value = headers[header] else { continue }
            let matching = query.filter { $0.name.lowercased() == parameter }
            guard matching.count == 1, matching[0].value == value,
                  let url = URL(string: value), LocalStreamProxyPolicy.allowsDestination(url),
                  url.query == nil, url.fragment == nil else { return nil }
            if header == "Origin", !url.path.isEmpty && url.path != "/" { return nil }
            provenance[header] = url
        }
        if let origin = provenance["Origin"], let referer = provenance["Referer"],
           !hasSameHTTPSOrigin(origin, referer) { return nil }
        return headers
    }

    nonisolated static func catalogID(for category: String) -> String {
        let sport = ReviewedSportsFixtureMatcher.sportKey(category)
        let suffix: String
        switch sport {
        case "american-football": suffix = "american_football"
        case "fight": suffix = "mma"
        case "": return "nuvio_sports_live"
        default: suffix = sport
        }
        return "nuvio_sports_\(suffix)"
    }

    nonisolated private static func fixtureIdentity(
        for entry: CommunitySportsCatalogEntry
    ) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard entry.id.hasPrefix("nuvio_sport_"),
              entry.type == nil || entry.type == "tv",
              let kickoff = entry.released.flatMap(releasedDate) else { return nil }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: entry.genres?.first ?? "",
            cast: entry.cast ?? [], title: entry.name, kickoff: kickoff,
            effectiveID: entry.behaviorHints?.defaultVideoId ?? entry.id, resourceType: entry.type ?? "tv",
            programmeMetadata: entry.description ?? entry.name)
    }

    /// The reviewed dynamic-M3U FanCode event branch has no provider kickoff:
    /// upstream materializes `Date.now()` and exposes it as `released`. This
    /// helper verifies the current listing contract only; it never creates a
    /// fixture, grants a date/format or authorizes a stream without the registry.
    nonisolated static func currentCricketListingIdentity(
        for entry: CommunitySportsCatalogEntry, at now: Date
    ) -> ReviewedSportsFixtureMatcher.ParticipantIdentity? {
        let safeParticipantText: (String, Int) -> Bool = { text, limit in
            !text.isEmpty && text.count <= limit && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
                && !text.contains("://")
                && text.range(of: #"[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]"#,
                              options: .regularExpression) == nil
        }
        guard entry.id.range(of: #"^nuvio_sport_sktech_sktech_ev_fancode_[1-9][0-9]{0,15}$"#,
                             options: .regularExpression) != nil,
              entry.type == "tv", entry.genres == ["CRICKET"], entry.releaseInfo == "LIVE",
              entry.behaviorHints?.defaultVideoId == entry.id, !entry.hasAdditionalEventTimeAuthority,
              entry.name.hasPrefix("🔴 LIVE: "),
              entry.description == "🏆 League: Cricket\n📅 Category: CRICKET\n⏰ Status: 🔴 LIVE NOW",
              let released = entry.released.flatMap(BroadcastRegistrySnapshot.date),
              // CS publishes this generated listing with max-age=14400. It is
              // not the age of the official LIVE receipt (still <=10 minutes).
              // Use the registry's existing source lifetime, not that separate
              // status clock; fresh same-ID metadata and association are required
              // by resolveRegistered before any descriptor can be used.
              (-300...BroadcastRegistrySnapshot.sourceLifetime).contains(now.timeIntervalSince(released)),
              let cast = entry.cast, cast.count == 2, cast.allSatisfy({ safeParticipantText($0, 256) }),
              safeParticipantText(entry.name, 512),
              let identity = ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket", cast: cast, title: entry.name),
              identity.pair == BroadcastRegistrySnapshot.participantPair(cast, sport: "cricket") else { return nil }
        return identity
    }

    nonisolated private static func releasedDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    nonisolated private static func qualityLabel(for entry: CommunitySportsStreamEntry) -> String {
        if let resolution = entry.resolution?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolution.isEmpty {
            let parts = resolution.lowercased().split(separator: "x")
            if parts.count == 2, let height = Int(parts[1]), (144...4320).contains(height) {
                return "\(height)p"
            }
            if resolution.count <= 24 { return resolution }
        }
        if let quality = entry.quality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quality.isEmpty, quality.count <= 24 {
            return quality
        }
        return "Live video"
    }

    nonisolated private static func sanitizedSourceHint(_ value: String?) -> String {
        guard let value else { return "unknown" }
        let safe = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return safe.isEmpty ? "unknown" : String(safe.prefix(32))
    }

    /// Opaque attribution survives response reordering without publishing an
    /// upstream name or signed URL. Unknown origins remain delivery-specific.
    nonisolated private static func sourceIdentity(
        for entry: CommunitySportsStreamEntry,
        deliveryURL: URL
    ) -> (key: String, scope: String) {
        let hint = entry.sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        // Accept a short provider name as upstream attribution, never a URL,
        // signed argument or opaque numeric token masquerading as a hint.
        let reliableHint = !["unknown", "none", "null", "auto"].contains(hint)
            && hint.range(of: #"^[a-z][a-z_-]{1,31}$"#, options: .regularExpression) != nil
        let scope = reliableHint ? "upstream" : "delivery"
        let material = reliableHint ? "source|\(hint)" : "delivery|\(deliveryURL.absoluteString)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return ("cs_" + digest.prefix(12).map { String(format: "%02x", $0) }.joined(), scope)
    }

    /// Reviewed direct CS HLS contracts. The CDNLive descriptor was verified
    /// against fresh same-ID main-Willow metadata on4November2026. It retains
    /// the original public token and headers, without exceptional transport
    /// authority. The ordinary guarded relay checks every referenced resource.
    nonisolated private static func isReviewedDirectHLS(
        _ url: URL, manifestURL: URL, sourceHint: String?
    ) -> Bool {
        guard let reviewedManifest = URL(string: "https://nuviosports.xyz/manifest.json"),
              hasSameHTTPSOrigin(manifestURL, reviewedManifest),
              manifestURL.path == reviewedManifest.path,
              manifestURL.user == nil, manifestURL.password == nil,
              manifestURL.query == nil, manifestURL.fragment == nil,
              LocalStreamProxyPolicy.allowsDestination(url),
              url.fragment == nil,
              let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              encodedPath == url.path else { return false }
        let hint = sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hint == "cdnlive", url.host?.lowercased() == "cdnlivetv.tv" {
            guard encodedPath.range(of: #"^/secure/api/v1/[a-f0-9]{24}/playlist\.m3u8$"#,
                                    options: .regularExpression) != nil,
                  let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  fields.count == 1, fields[0].name == "token", let token = fields[0].value,
                  (32...1024).contains(token.utf8.count),
                  token.range(of: #"^[A-Za-z0-9_+/=-]+$"#, options: .regularExpression) != nil else { return false }
            return true
        }
        guard hint == "sktech", url.host?.lowercased() == "dai-fancode.pages.dev", url.query == nil else { return false }
        return encodedPath.range(of: #"^/mumbai/[A-Za-z0-9][A-Za-z0-9_-]{0,239}/index\.m3u8$"#,
                                 options: .regularExpression) != nil
    }

    nonisolated private static func admittedDelivery(_ url: URL, manifestURL: URL,
                                                    sourceHint: String?) -> Bool? {
        let absolute = url.absoluteString.lowercased()
        guard !absolute.contains("magnet:"), !absolute.contains("acestream"),
              !absolute.contains(":6878"), !absolute.contains("/proxy/acestream/") else { return nil }
        if isReviewedDirectHLS(url, manifestURL: manifestURL, sourceHint: sourceHint) { return false }
        guard hasSameHTTPSOrigin(url, manifestURL), url.user == nil, url.password == nil,
              (url.query?.utf8.count ?? 0) <= 12 * 1024 else { return nil }
        let path = url.path.lowercased()
        let watchPath = routeURL(relativeTo: manifestURL, components: ["watch"]).path.lowercased()
        if LocalStreamProxyPolicy.isCommunitySportsManifestRoute(url, manifestURL: manifestURL) { return false }
        if path == watchPath || path.hasPrefix("\(watchPath)/") { return true }
        return nil
    }

    /// An HTTPS wrapper must not launder an explicitly unsafe nested delivery,
    /// including when the row omits headers. Preserve the already reviewed
    /// runtime8443 exception; it still needs its exact origin/header binding.
    nonisolated private static func admitsWrappedTarget(
        _ deliveryURL: URL, manifestURL: URL, sourceHint: String?, headers: [String: String]
    ) -> Bool {
        guard LocalStreamProxyPolicy.isCommunitySportsManifestRoute(deliveryURL, manifestURL: manifestURL)
        else { return true }
        let targets = URLComponents(url: deliveryURL, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name.lowercased() == "url" } ?? []
        guard !targets.isEmpty else { return true }
        guard targets.count == 1, let value = targets[0].value, let target = URL(string: value),
              target.absoluteString.utf8.count <= 8_192 else { return false }
        if LocalStreamProxyPolicy.allowsDestination(target) { return true }
        return LocalStreamProxyOriginProfile.communitySports(deliveryURL: deliveryURL,
            manifestURL: manifestURL, sourceHint: sourceHint, headers: headers)?
            .allowsExceptionalDestination(target) == true
    }

    nonisolated private static func isSafeManifestURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil
            && url.user == nil && url.password == nil
            && url.lastPathComponent.lowercased() == "manifest.json"
    }

    /// Keep admission and diagnostics on one explicit scalar walk. The bound
    /// `allSatisfy(allowed.contains)` predicate disagreed with the explicit walk
    /// in the optimized iPad build; do not reject an otherwise valid reference
    /// or broaden its permitted characters to work around that disagreement.
    /// No identifier or derived fingerprint leaves this pure validator.
    nonisolated static func videoIDRejection(_ value: String) -> CommunitySportsUnsafeMetadataReason? {
        if value.isEmpty { return .streamIDEmpty }
        guard value.hasPrefix("nuvio_sport_") else { return .streamIDPrefix }
        guard value.count <= 240 else { return .streamIDLength }
        return videoIDInvalidScalar(value) == nil ? nil : .streamIDCharacters
    }

    nonisolated static func videoIDInvalidScalar(_ value: String) -> UInt32? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        for scalar in value.unicodeScalars {
            if !allowed.contains(scalar) { return scalar.value }
        }
        return nil
    }

    nonisolated private static func routeURL(relativeTo manifestURL: URL, components: [String]) -> URL {
        components.reduce(manifestURL.deletingLastPathComponent()) { url, component in
            url.appendingPathComponent(component)
        }
    }

    nonisolated private static func hasSameHTTPSOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard lhs.scheme?.lowercased() == "https", rhs.scheme?.lowercased() == "https",
              lhs.host?.lowercased() == rhs.host?.lowercased() else { return false }
        return (lhs.port ?? 443) == (rhs.port ?? 443)
    }

    /// Used before URLSession follows, not merely after downloading the target.
    nonisolated static func allowsRedirect(from source: URL, to destination: URL, anchoredTo manifest: URL) -> Bool {
        source.user == nil && source.password == nil && destination.user == nil && destination.password == nil
            && hasSameHTTPSOrigin(source, manifest) && hasSameHTTPSOrigin(destination, manifest)
    }
}
