import Foundation

// MARK: - Shared Media Models

enum CatalogTimingPolicy {
    nonisolated static let cplWindow: TimeInterval = 8 * 3600
    nonisolated static let retentionPastGrace: TimeInterval = 36 * 3600
    nonisolated static let retentionFutureHorizon: TimeInterval = 72 * 3600
    nonisolated static let standardHomeUpcomingHorizon: TimeInterval = 6 * 3600
    nonisolated static let standardHomeLaterHorizon: TimeInterval = 48 * 3600
    nonisolated static let personalizedHomeUpcomingHorizon: TimeInterval = 72 * 3600
}

enum CatalogBroadcastTiming: String, Sendable {
    case live = "LIVE"
    case upcoming = "UPCOMING"
    case available = "AVAILABLE"

    var actionLabel: String {
        self == .live ? "Watch live" : "Open broadcast"
    }
}

extension AnalyticalDataEngine.EventReference {
    var cplCompetitionLabel: String {
        if let cricketFixture { return cricketFixture.competitionName }
        guard isCPLFixture else { return categoryDisplayName }
        let prefix = title?
            .components(separatedBy: "·")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix, prefix.hasPrefix("CPL ") { return prefix }
        return "CPL"
    }

    var displayTitle: String {
        if isBroadcastChannel { return title ?? "Cricket channel" }
        if let sportsFixture, sportsFixture.eventKind != .match { return sportsFixture.title }
        let home = homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = awayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !home.isEmpty, !away.isEmpty,
           (home != "Home" || teams?.home?.name != nil),
           (away != "Away" || teams?.away?.name != nil) { return "\(home) vs \(away)" }
        return title ?? "Match"
    }

    /// A channel has no kickoff or final whistle. Do not infer a channel's
    /// programme from its name, or classify every undated fixture as a channel.
    nonisolated var isBroadcastChannel: Bool {
        if SportsTVStation.identifies(self) { return true }
        guard (category ?? "").lowercased() == "cricket" else { return false }
        let name = (title ?? "").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return ["willow", "willowtv", "willowcricket", "willowhd", "willow2", "foxcricket", "foxcrickethd"].contains(name)
    }

    nonisolated var isCPLFixture: Bool {
        guard (category ?? "").lowercased() == "cricket", !isBroadcastChannel else { return false }
        let text = [title, teams?.home?.name, teams?.away?.name].compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("caribbean premier league") || text.range(of: #"\bcpl\b"#, options: .regularExpression) != nil {
            return true
        }
        // Require two distinct franchises: an isolated team name can appear in
        // a news/highlight title or another tournament and is not a fixture.
        return CPLTeam.containsTwoDistinctTeams(in: text)
    }

    /// Discovery estimates, not official match status. Unknown cricket formats
    /// (especially multi-day Tests) must never inherit football's two-hour end.
    nonisolated var estimatedMatchDuration: TimeInterval? {
        guard !isBroadcastChannel else { return nil }
        // A fixture service supplies actual status for every cricket format.
        // Its ODI/Test rows must not expire using an estimated T20 duration.
        if cricketFixture != nil || sportsFixture != nil { return nil }
        switch (category ?? "").lowercased() {
        case "football", "soccer": return 2 * 3600
        case "cricket":
            let name = (title ?? "").lowercased()
            if isCPLFixture { return CatalogTimingPolicy.cplWindow }
            if name.range(of: #"\b(t20|t20i|twenty20)\b"#, options: .regularExpression) != nil {
                return 6 * 3600
            }
            return nil
        default: return nil
        }
    }

    nonisolated func isPastEstimatedMatchWindow(at now: Date = .init()) -> Bool {
        guard let kickoff = kickoffDate, let duration = estimatedMatchDuration else { return false }
        return now >= kickoff.addingTimeInterval(duration)
    }

    nonisolated func broadcastTiming(at now: Date = .init()) -> CatalogBroadcastTiming {
        guard !isBroadcastChannel, let kickoff = kickoffDate else { return .available }
        if let cricketFixture {
            if cricketFixture.isLive(at: now) { return .live }
            if cricketFixture.verified, cricketFixture.status == .scheduled, kickoff > now { return .upcoming }
            return .available
        }
        if let sportsFixture {
            if sportsFixture.isLive(at: now) { return .live }
            if sportsFixture.verified, sportsFixture.status == .scheduled, kickoff > now { return .upcoming }
            return .available
        }
        if kickoff > now { return .upcoming }
        if CPLSchedule.isManagedFixtureID(id) { return .available }
        // Preserve the existing four-hour broadcast window for other sports,
        // without declaring them finished when their actual format is unknown.
        let duration = estimatedMatchDuration ?? ((category ?? "").lowercased() == "cricket" ? 0 : 4 * 3600)
        return now.timeIntervalSince(kickoff) < duration ? .live : .available
    }
}

struct StreamSource: Identifiable, Sendable {
    let id: UUID
    let title: String?
    let url: URL
    let quality: String
    let provider: String
    let subtitles: [Subtitle]
    let headers: [String: String]
    let activePeers: Int?
    let cookie: String?
    let referer: String?
    let priority: Int
    let nativeOriginProfile: LocalStreamProxyOriginProfile?
    let nativePlaylistProfile: LocalStreamProxyPlaylistProfile?
    /// Require the ordinary guarded relay even when no upstream headers exist.
    /// This is a restriction, not an exceptional-origin or playlist grant.
    let requiresGuardedRelay: Bool
    /// Describes routing/evidence only. It grants no transport or playback authority.
    let playbackContract: StreamPlaybackContract?
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        url: URL,
        quality: String,
        provider: String,
        subtitles: [Subtitle] = [],
        headers: [String: String] = [:],
        activePeers: Int? = nil,
        cookie: String? = nil,
        referer: String? = nil,
        priority: Int = 0,
        nativeOriginProfile: LocalStreamProxyOriginProfile? = nil,
        nativePlaylistProfile: LocalStreamProxyPlaylistProfile? = nil,
        requiresGuardedRelay: Bool = false,
        playbackContract: StreamPlaybackContract? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.quality = quality
        self.provider = provider
        self.subtitles = subtitles
        self.headers = headers
        self.activePeers = activePeers
        self.cookie = cookie
        self.referer = referer
        self.priority = priority
        self.nativeOriginProfile = nativeOriginProfile?.validated(for: url, headers: headers)
        self.nativePlaylistProfile = nativePlaylistProfile?.validated(for: url, headers: headers)
        self.requiresGuardedRelay = requiresGuardedRelay
        self.playbackContract = playbackContract
    }

    var requiresLocalProxy: Bool { requiresGuardedRelay || !headers.isEmpty || nativePlaylistProfile != nil }

    /// Returns a copy with additional HTTP headers merged in (later keys win on collision).
    func mergingHeaders(_ extra: [String: String]) -> StreamSource {
        var merged = headers
        for (k, v) in extra {
            merged[k] = v
        }
        return StreamSource(
            id: id,
            title: title,
            url: url,
            quality: quality,
            provider: provider,
            subtitles: subtitles,
            headers: merged,
            activePeers: activePeers,
            cookie: cookie,
            referer: referer,
            priority: priority,
            nativeOriginProfile: nativeOriginProfile,
            nativePlaylistProfile: nativePlaylistProfile,
            requiresGuardedRelay: requiresGuardedRelay,
            playbackContract: merged == headers ? playbackContract : playbackContract?.discardingProbeEvidence()
        )
    }

    struct Subtitle: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let language: String
        let label: String
    }
}

enum StreamType: String, Codable, Sendable {
    case hls
    case mp4
    case unknown
}

enum StreamMediaContainer: String, Sendable {
    case hls, mp4, mpegTransportStream, unknown

    var streamType: StreamType {
        switch self {
        case .hls: return .hls
        case .mp4: return .mp4
        case .mpegTransportStream, .unknown: return .unknown
        }
    }
}

/// A bounded response observation, not a codec, decoded-video or PiP guarantee.
/// Deliberately not Codable: saved sessions must obtain fresh transport evidence.
struct StreamMediaProbeEvidence: Equatable, Sendable {
    enum ResponseType: String, Sendable {
        case hls, mp4, mpegTransportStream, binary, other

        init(contentType: String) {
            switch contentType.split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" {
            case "application/x-mpegurl", "application/vnd.apple.mpegurl": self = .hls
            case "video/mp4": self = .mp4
            case "video/mp2t": self = .mpegTransportStream
            case "application/octet-stream": self = .binary
            default: self = .other
            }
        }

        var declaredContainer: StreamMediaContainer {
            switch self {
            case .hls: return .hls
            case .mp4: return .mp4
            case .mpegTransportStream: return .mpegTransportStream
            case .binary, .other: return .unknown
            }
        }
    }

    let responseType: ResponseType
    let observedContainer: StreamMediaContainer

    init(contentType: String, prefix: Data) {
        responseType = ResponseType(contentType: contentType)
        // This helper retains no response bytes and never scans beyond the
        // validator's prefix budget, even when used independently in a test.
        let bytes = Array(prefix.prefix(1024))
        if Self.hasHLSHeader(bytes) {
            observedContainer = .hls
        } else if Self.hasMP4FileType(bytes) {
            observedContainer = .mp4
        } else {
            observedContainer = .unknown
        }
    }

    var preferredContainer: StreamMediaContainer {
        observedContainer == .unknown ? responseType.declaredContainer : observedContainer
    }

    var preferredStreamType: StreamType { preferredContainer.streamType }

    private static func hasHLSHeader(_ bytes: [UInt8]) -> Bool {
        let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        let header = Array("#EXTM3U".utf8)
        let end = start + header.count
        guard bytes.count >= end, bytes[start..<end].elementsEqual(header) else { return false }
        // HTTP playlists use byte-delimited lines. Swift String treats CRLF as
        // one grapheme, so a String prefix ending at CR can reject valid CRLF.
        return bytes.count == end || bytes[end] == 0x0A || bytes[end] == 0x0D
    }

    private static func hasMP4FileType(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 16, Array(bytes[4..<8]) == Array("ftyp".utf8) else { return false }
        let size = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size >= 16 else { return false }
        // ISO BMFF also carries still images. An arbitrary `ftyp` is not enough
        // to label an AVIF/HEIF response as MP4 media.
        let brands: Set<String> = ["isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9",
                                   "mp41", "mp42", "avc1", "dash", "cmfc", "cmfs", "M4V "]
        if brands.contains(String(decoding: bytes[8..<12], as: UTF8.self)) { return true }
        let end = min(Int(size), bytes.count)
        for offset in stride(from: 16, through: end - 4, by: 4) {
            if brands.contains(String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)) { return true }
        }
        return false
    }
}

/// Route-level compatibility only. A candidate must still pass current source,
/// attempt, expiry, transport, player-readiness and presentation ownership gates.
struct StreamPlaybackContract: Equatable, Sendable {
    enum Endpoint: String, Sendable { case webPage, directMedia, unknown, unsupported }
    enum NativePreparationEligibility: String, Sendable {
        case candidate, needsMediaObservation, unavailable
    }

    let declaredEndpoint: Endpoint
    let declaredContainer: StreamMediaContainer
    let mediaProbeEvidence: StreamMediaProbeEvidence?

    var endpoint: Endpoint {
        guard declaredEndpoint != .unsupported else { return .unsupported }
        if let observed = mediaProbeEvidence?.preferredContainer, observed != .unknown {
            return .directMedia
        }
        return declaredEndpoint
    }

    var container: StreamMediaContainer {
        guard let observed = mediaProbeEvidence?.preferredContainer, observed != .unknown else {
            return declaredContainer
        }
        return observed
    }

    var nativePreparationEligibility: NativePreparationEligibility {
        switch endpoint {
        case .directMedia: return .candidate
        case .webPage, .unknown: return .needsMediaObservation
        case .unsupported: return .unavailable
        }
    }

    func discardingProbeEvidence() -> Self {
        Self(declaredEndpoint: declaredEndpoint, declaredContainer: declaredContainer, mediaProbeEvidence: nil)
    }

    static func describing(url: URL, provider: String, headers: [String: String],
                           streamType: StreamType = .unknown,
                           declaredEndpoint: Endpoint? = nil,
                           mediaProbeEvidence: StreamMediaProbeEvidence? = nil) -> Self {
        let declared: StreamMediaContainer = streamType == .hls ? .hls : streamType == .mp4 ? .mp4 : .unknown
        let endpoint: Endpoint
        if !["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            endpoint = .unsupported
        } else if let declaredEndpoint {
            endpoint = declaredEndpoint
        } else if declared != .unknown {
            endpoint = .directMedia
        } else {
            // Keep the existing delivery-endpoint routing, never a URL hidden
            // inside its query. Declarations remain distinct from a media probe.
            let path = url.path.lowercased()
            if path.contains(".m3u8") || path.contains(".mp4") || path.contains("/acestream") {
                endpoint = .directMedia
            } else if path.contains("/embed/") || (url.host?.lowercased().contains("embed") ?? false)
                        || provider.lowercased().contains("embed") || headers["X-Fotty-Embed"] == "true"
                        || headers["X-Fotty-Web-Embed"] == "true" {
                endpoint = .webPage
            } else {
                endpoint = .unknown
            }
        }
        return Self(declaredEndpoint: endpoint, declaredContainer: declared, mediaProbeEvidence: mediaProbeEvidence)
    }
}

enum StreamValidationStatus: String, Codable, Sendable {
    case pending
    case validated
    case failed
}

enum StreamLoadState: String, Codable, Sendable {
    case idle
    case resolving
    case validating
    case fallingBack = "falling_back"
    case readyToPlay = "ready_to_play"
    case playing
    case refreshing
    case failed
    case cancelled
}

enum StreamFailureCategory: String, Codable, Sendable {
    case noProviderAvailable = "no_provider_available"
    case providerTimeout = "provider_timeout"
    case providerReturnedEmpty = "provider_returned_empty"
    case invalidMatchMapping = "invalid_match_mapping"
    case invalidURL = "invalid_url"
    case unsupportedScheme = "unsupported_scheme"
    case providerSecurityFailure = "provider_security_failure"
    case manifestUnreachable = "manifest_unreachable"
    case manifestInvalid = "manifest_invalid"
    case segmentUnreachable = "segment_unreachable"
    case authFailed = "auth_failed"
    case leaseExpired = "lease_expired"
    case playerFailed = "player_failed"
    case navigationCancelled = "navigation_cancelled"
    case duplicateRequestCancelled = "duplicate_request_cancelled"
    case userCancelled = "user_cancelled"
    case networkChanged = "network_changed"
    case backgroundedDuringResolution = "backgrounded_during_resolution"
    case unknown
}

struct StreamFailure: Error, Identifiable, Codable, Sendable {
    let id: UUID
    let providerName: String?
    let category: StreamFailureCategory
    let technicalMessage: String
    let userMessage: String
    let retryable: Bool
    let fallbackAllowed: Bool
    let redactedMetadata: [String: String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        providerName: String? = nil,
        category: StreamFailureCategory,
        technicalMessage: String,
        userMessage: String,
        retryable: Bool,
        fallbackAllowed: Bool,
        redactedMetadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.category = category
        self.technicalMessage = technicalMessage
        self.userMessage = userMessage
        self.retryable = retryable
        self.fallbackAllowed = fallbackAllowed
        self.redactedMetadata = redactedMetadata
        self.timestamp = timestamp
    }
}

/// Turns transport errors into truthful, user-facing playback failures. A
/// provider trust failure is materially different from an empty catalog: the
/// broadcast exists, but iOS cannot connect to it safely.
enum StreamTransportFailurePolicy {
    static let secureConnectionUnavailableMessage =
        "The broadcast provider’s secure connection is temporarily unavailable. Fotty cannot open it safely. Try again shortly."

    static func isProviderSecurityFailure(_ code: URLError.Code) -> Bool {
        switch code {
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    static func urlErrorCode(from error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return nil }
        return URLError.Code(rawValue: nsError.code)
    }

    static func makeFailure(
        providerName: String,
        code: URLError.Code,
        technicalMessage: String,
        defaultCategory: StreamFailureCategory,
        defaultUserMessage: String,
        fallbackAllowed: Bool,
        redactedMetadata: [String: String] = [:]
    ) -> StreamFailure {
        if isProviderSecurityFailure(code) {
            return StreamFailure(
                providerName: providerName,
                category: .providerSecurityFailure,
                technicalMessage: technicalMessage,
                userMessage: secureConnectionUnavailableMessage,
                retryable: true,
                fallbackAllowed: fallbackAllowed,
                redactedMetadata: redactedMetadata.merging(
                    ["transport_result": "provider_security_failure"]
                ) { current, _ in current }
            )
        }

        let category: StreamFailureCategory
        switch code {
        case .timedOut:
            category = .providerTimeout
        case .networkConnectionLost, .notConnectedToInternet:
            category = .manifestUnreachable
        default:
            category = defaultCategory
        }

        return StreamFailure(
            providerName: providerName,
            category: category,
            technicalMessage: technicalMessage,
            userMessage: defaultUserMessage,
            retryable: code == .timedOut || code == .networkConnectionLost,
            fallbackAllowed: fallbackAllowed,
            redactedMetadata: redactedMetadata
        )
    }

    static func mostActionableFailure(in failures: [StreamFailure]) -> StreamFailure? {
        failures.enumerated().min { lhs, rhs in
            let lhsRank = priority(of: lhs.element.category)
            let rhsRank = priority(of: rhs.element.category)
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }?.element
    }

    private static func priority(of category: StreamFailureCategory) -> Int {
        switch category {
        case .providerSecurityFailure: return 0
        case .authFailed: return 1
        case .providerTimeout: return 2
        case .manifestUnreachable, .segmentUnreachable: return 3
        case .providerReturnedEmpty: return 4
        default: return 5
        }
    }
}

/// Short-lived linkage recorded only after a reviewed adapter has completed
/// its exact fixture/metadata join. This is neither a stream URL nor permission
/// to admit a new route. The adapter must repeat its guards when resolving it.
struct StreamEventBinding: Equatable, Sendable {
    static let metadataLifetime: TimeInterval = 90

    let fixtureID: String
    let providerCode: String
    let providerEventID: String
    let streamID: String
    let resource: String
    let resourceType: String
    let sport: String
    let kickoffDate: Date?
    let manifestRevision: String
    let verifiedAt: Date
    let expiresAt: Date

    private let requestIdentity: ReviewedSportsFixtureMatcher.RequestIdentity?
    private let channelIdentity: CricketBroadcastChannel?
    private let televisionChannelID: String?
    private let competitionID: String?
    private let squad: SportsFixtureCatalog.Squad?
    private let cricketFormat: String?
    private let cricketMatchContext: String?
    private let cricketBroadcastDayIdentity: String?
    private let registryAssociation: BroadcastRegistryMatch?
    private let csHandoff: CSRegisteredHandoff?
    var usesRegistryAssociation: Bool { registryAssociation != nil }
    var usesCSProviderHandoff: Bool { csHandoff != nil }

    init?(
        request: StreamPlaybackRequest,
        providerCode: String,
        providerEventID: String,
        streamID: String,
        resource: String = "stream",
        resourceType: String = "tv",
        manifestRevision: String,
        verifiedAt: Date,
        expiresAt: Date,
        at now: Date = Date(),
        csHandoff: CSRegisteredHandoff? = nil
    ) {
        let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: request)
        let channel = CricketBroadcastChannel.identifying(request: request)
        let television = SportsTVStation.identifying(request)
        let association = request.registryMatch
        if let handoff = csHandoff {
            guard providerCode == "communitysports", handoff.fixtureID == request.matchID, handoff.newID == providerEventID,
                  providerEventID == streamID, let association,
                  association.broadcast.providerEventID == handoff.oldID, association.broadcast.streamID == handoff.oldID,
                  handoff.expiresAt >= expiresAt, handoff.expiresAt > now else { return nil }
        }
        guard request.preferredEvent?.hasCatalogIdentityConflict != true,
              !CricketBroadcastChannel.allCases.contains(where: { $0.canonicalID == request.matchID }) || channel != nil,
              !SportsTVStation.all.filter({ $0.cricketChannel == nil }).contains(where: { $0.id == request.matchID }) || television != nil,
              identity != nil || channel != nil || television != nil,
              let definition = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode),
              channel == nil || definition.provider == .communitySports
                || definition.provider == .reviewedTV && channel == .willow,
              television == nil || (definition.provider == .communitySports
                && CommunitySportsAddonClient.supportsSportsTVChannel(request)
                && CommunitySportsAddonClient.videoIDRejection(providerEventID) == nil
                && CommunitySportsAddonClient.videoIDRejection(streamID) == nil) || (definition.provider == .reviewedTV
                && streamID == ReviewedTVPlaylistClient.channel(forChannelID: television!.id)?.streamID
                && providerEventID == streamID),
              definition.provider != .reviewedTV || channel == .willow || television != nil
                || ReviewedTVPlaylistClient.programmeAssociation(for: request, at: now) != nil,
              association.map({ $0.matches(request: request, providerCode: providerCode,
                  providerEventID: csHandoff?.oldID ?? providerEventID, streamID: csHandoff?.oldID ?? streamID, at: now) }) ?? true,
              Self.isReference(request.matchID, limit: 512),
              Self.isReference(providerEventID, limit: 4096),
              Self.isReference(streamID, limit: 4096),
              resource == "stream", resourceType == "tv",
              Self.isReference(manifestRevision, limit: 96),
              identity.map({ $0.kickoff.timeIntervalSince1970.isFinite }) ?? true,
              [verifiedAt, expiresAt, now].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              expiresAt > verifiedAt,
              verifiedAt.timeIntervalSince(now) <= 30 else { return nil }
        let boundedExpiry = min(expiresAt, verifiedAt.addingTimeInterval(Self.metadataLifetime))
        guard boundedExpiry > now else { return nil }
        fixtureID = request.matchID
        self.providerCode = definition.providerCode
        self.providerEventID = providerEventID
        self.streamID = streamID
        self.resource = resource
        self.resourceType = resourceType
        sport = identity?.sport ?? (television == nil ? "cricket" : "other")
        kickoffDate = identity?.kickoff
        self.manifestRevision = manifestRevision
        self.verifiedAt = verifiedAt
        self.expiresAt = boundedExpiry
        requestIdentity = identity
        channelIdentity = channel
        televisionChannelID = television?.id
        competitionID = request.preferredEvent?.competitionID
        squad = request.preferredEvent?.sportsFixture?.squad
        cricketFormat = request.preferredEvent?.cricketFixture?.format.rawValue
        cricketMatchContext = identity?.sport == "cricket" ? request.displayTitle : nil
        cricketBroadcastDayIdentity = request.preferredEvent?.cricketFixture?.broadcastDayIdentity
        registryAssociation = association
        self.csHandoff = csHandoff
    }

    func isCurrent(at now: Date = Date()) -> Bool {
        now.timeIntervalSince1970.isFinite && expiresAt > now
            && verifiedAt.timeIntervalSince(now) <= 30
    }

    func matches(request: StreamPlaybackRequest, providerCode: String, at now: Date = Date()) -> Bool {
        isCurrent(at: now) && matchesIdentity(request: request, providerCode: providerCode)
            && (registryAssociation.map { $0.matches(request: request, providerCode: providerCode,
                providerEventID: csHandoff?.oldID ?? providerEventID, streamID: csHandoff?.oldID ?? streamID, at: now) } ?? true)
    }

    /// The stream always retains the actual ID. Only the originating verified
    /// CS DLV→TS transition can bridge the short gap until the registry updates.
    func matchesRegistryEntry(_ candidate: BroadcastRegistryMatch, request: StreamPlaybackRequest, at now: Date) -> Bool {
        if candidate.matches(request: request, providerCode: providerCode, providerEventID: providerEventID, streamID: streamID, at: now) { return true }
        guard let handoff = csHandoff, let parent = registryAssociation, candidate.broadcast.id == parent.broadcast.id,
              handoff.fixtureID == request.matchID else { return false }
        // This identifies the owner even during descriptor renewal. Replaying
        // a session still requires matches(request:...), including binding TTL.
        return candidate.matches(request: request, providerCode: providerCode, providerEventID: handoff.oldID, streamID: handoff.oldID, at: now)
    }

    func currentRegistryEntry(in matches: [BroadcastRegistryMatch], request: StreamPlaybackRequest, at now: Date) -> BroadcastRegistryMatch? {
        let exact = matches.filter { $0.broadcast.providerEventID == providerEventID && $0.broadcast.streamID == streamID
            && matchesRegistryEntry($0, request: request, at: now) }
        if !exact.isEmpty { return exact.count == 1 ? exact[0] : nil }
        let parents = matches.filter { matchesRegistryEntry($0, request: request, at: now) }
        return parents.count == 1 ? parents[0] : nil
    }

    /// An expired binding may identify which metadata to re-request, never
    /// authorize replay of its old URL. The adapter must produce a fresh match.
    func matchesIdentity(request: StreamPlaybackRequest, providerCode: String) -> Bool {
        guard request.preferredEvent?.hasCatalogIdentityConflict != true,
              fixtureID == request.matchID,
              CuratedStreamSourceCatalog.definition(forProviderCode: providerCode)?.providerCode == self.providerCode else { return false }
        if let channelIdentity {
            return CricketBroadcastChannel.identifying(request: request) == channelIdentity
        }
        if let televisionChannelID { return SportsTVStation.identifying(request)?.id == televisionChannelID }
        guard let requestIdentity,
              ReviewedSportsFixtureMatcher.requestIdentity(for: request) == requestIdentity else { return false }
        return competitionID == request.preferredEvent?.competitionID
            && squad == request.preferredEvent?.sportsFixture?.squad
            && cricketFormat == request.preferredEvent?.cricketFixture?.format.rawValue
            && cricketMatchContext == (sport == "cricket" ? request.displayTitle : nil)
            && cricketBroadcastDayIdentity == request.preferredEvent?.cricketFixture?.broadcastDayIdentity
    }

    /// Ownership is a finite provider identity or the adapter's owned opaque
    /// label. Remote URL/title substrings cannot reattribute this binding.
    static func providerCode(forSessionProviderName name: String) -> String? {
        StreamPluginProviderMatching.opaqueProviderFamily(name)
            ?? CuratedStreamSourceCatalog.definition(forProviderCode: name)?.providerCode
    }

    private static func isReference(_ value: String, limit: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= limit else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:~="))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

struct StreamSession: Identifiable, Codable, Sendable {
    let id: UUID
    let matchID: String
    let title: String?
    let playableURL: URL
    let streamType: StreamType
    let providerName: String
    let requiredHeaders: [String: String]
    let qualityLabel: String?
    let expiryTime: Date?
    let leaseID: String?
    let canRefresh: Bool
    let validationStatus: StreamValidationStatus
    let diagnosticMetadata: [String: String]
    let createdAt: Date
    let lastRefreshAt: Date?
    let activePeers: Int?

    /// Ephemeral authority is never serialized with a playback session. Decoded
    /// sessions must resolve the reviewed CS contract again to acquire it.
    private(set) var nativeOriginProfile: LocalStreamProxyOriginProfile? = nil
    private(set) var nativePlaylistProfile: LocalStreamProxyPlaylistProfile? = nil
    private(set) var mediaProbeEvidence: StreamMediaProbeEvidence? = nil
    /// Reacquire through the exact adapter after decoding a saved session.
    /// Fixture linkage is transient and never exports provider event IDs.
    private(set) var eventBinding: StreamEventBinding? = nil
    /// A captured media request has a direct endpoint role even if its container
    /// remains unknown. This ephemeral declaration never grants origin authority.
    private(set) var declaredPlaybackEndpoint: StreamPlaybackContract.Endpoint? = nil
    // Optional for decoding sessions saved before this restriction existed.
    // Unlike exceptional transport grants, a relay requirement may persist.
    private(set) var requiresGuardedRelay: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case id, matchID, title, playableURL, streamType, providerName, requiredHeaders
        case qualityLabel, expiryTime, leaseID, canRefresh, validationStatus, diagnosticMetadata
        case createdAt, lastRefreshAt, activePeers
        case requiresGuardedRelay
    }

    init(
        id: UUID = UUID(),
        matchID: String,
        title: String? = nil,
        playableURL: URL,
        streamType: StreamType,
        providerName: String,
        requiredHeaders: [String: String] = [:],
        qualityLabel: String? = nil,
        expiryTime: Date? = nil,
        leaseID: String? = nil,
        canRefresh: Bool = false,
        validationStatus: StreamValidationStatus = .validated,
        diagnosticMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        lastRefreshAt: Date? = nil,
        activePeers: Int? = nil,
        nativeOriginProfile: LocalStreamProxyOriginProfile? = nil,
        nativePlaylistProfile: LocalStreamProxyPlaylistProfile? = nil,
        requiresGuardedRelay: Bool = false,
        mediaProbeEvidence: StreamMediaProbeEvidence? = nil,
        declaredPlaybackEndpoint: StreamPlaybackContract.Endpoint? = nil,
        eventBinding: StreamEventBinding? = nil
    ) {
        self.id = id
        self.matchID = matchID
        self.title = title
        self.playableURL = playableURL
        self.streamType = streamType
        self.providerName = providerName
        self.requiredHeaders = requiredHeaders
        self.qualityLabel = qualityLabel
        self.expiryTime = expiryTime
        self.leaseID = leaseID
        self.canRefresh = canRefresh
        self.validationStatus = validationStatus
        self.diagnosticMetadata = diagnosticMetadata
        self.createdAt = createdAt
        self.lastRefreshAt = lastRefreshAt
        self.activePeers = activePeers
        self.nativeOriginProfile = nativeOriginProfile?.validated(for: playableURL, headers: requiredHeaders)
        self.nativePlaylistProfile = nativePlaylistProfile?.validated(for: playableURL, headers: requiredHeaders)
        self.requiresGuardedRelay = requiresGuardedRelay ? true : nil
        self.mediaProbeEvidence = mediaProbeEvidence
        self.declaredPlaybackEndpoint = declaredPlaybackEndpoint
        self.eventBinding = eventBinding.flatMap { binding in
            binding.fixtureID == matchID && binding.isCurrent(at: createdAt)
                && StreamEventBinding.providerCode(forSessionProviderName: providerName) == binding.providerCode
                ? binding : nil
        }
    }

    var playbackContract: StreamPlaybackContract {
        .describing(url: playableURL, provider: providerName, headers: requiredHeaders,
                    streamType: streamType, declaredEndpoint: declaredPlaybackEndpoint,
                    mediaProbeEvidence: mediaProbeEvidence)
    }

    /// A provider-declared media lease is independent of the shorter metadata
    /// binding. Unknown media expiry cannot be invented from metadata age.
    func hasExpiredMediaLease(at now: Date = Date()) -> Bool {
        guard let expiryTime else { return false }
        return !now.timeIntervalSince1970.isFinite || !expiryTime.timeIntervalSince1970.isFinite || expiryTime <= now
    }

    /// The caller must first recheck the probe's exact source/attempt ownership.
    /// Recording an observation cannot change delivery, expiry or authority.
    func recordingMediaProbe(_ evidence: StreamMediaProbeEvidence?) -> Self {
        var session = self
        session.mediaProbeEvidence = evidence
        return session
    }

    func recordingEventBinding(
        _ binding: StreamEventBinding?, for request: StreamPlaybackRequest, at now: Date = Date()
    ) -> Self {
        var session = self
        session.eventBinding = binding.flatMap { binding in
            binding.fixtureID == matchID
                && StreamEventBinding.providerCode(forSessionProviderName: providerName) == binding.providerCode
                && binding.matches(request: request, providerCode: binding.providerCode, at: now)
                ? binding : nil
        }
        return session
    }

    /// Keep the selected row/attempt identity while adopting a newly admitted
    /// delivery from that exact provider-event binding. No old relay grant is
    /// carried to the replacement URL.
    func renewingDelivery(from fresh: Self, for request: StreamPlaybackRequest, at now: Date = Date()) -> Self? {
        guard let previous = eventBinding, let next = fresh.eventBinding,
              previous.matchesIdentity(request: request, providerCode: previous.providerCode),
              next.matches(request: request, providerCode: previous.providerCode, at: now),
              previous.providerEventID == next.providerEventID, previous.streamID == next.streamID,
              fresh.matchID == matchID,
              !fresh.hasExpiredMediaLease(at: now),
              fresh.playbackContract.endpoint == playbackContract.endpoint,
              StreamEventBinding.providerCode(forSessionProviderName: fresh.providerName) == previous.providerCode
        else { return nil }
        return Self(id: id, matchID: matchID, title: fresh.title ?? title,
            playableURL: fresh.playableURL, streamType: fresh.streamType, providerName: providerName,
            requiredHeaders: fresh.requiredHeaders, qualityLabel: fresh.qualityLabel,
            expiryTime: fresh.expiryTime, leaseID: fresh.leaseID, canRefresh: fresh.canRefresh,
            validationStatus: fresh.validationStatus, diagnosticMetadata: fresh.diagnosticMetadata,
            createdAt: now, lastRefreshAt: now, activePeers: fresh.activePeers,
            nativeOriginProfile: fresh.nativeOriginProfile, nativePlaylistProfile: fresh.nativePlaylistProfile,
            requiresGuardedRelay: fresh.requiresGuardedRelay == true, mediaProbeEvidence: fresh.mediaProbeEvidence,
            declaredPlaybackEndpoint: fresh.declaredPlaybackEndpoint, eventBinding: next)
    }

    var requiresLocalProxy: Bool {
        requiresGuardedRelay == true || !requiredHeaders.isEmpty || nativePlaylistProfile != nil
    }

    var legacySource: StreamSource {
        StreamSource(
            id: id,
            title: title,
            url: playableURL,
            quality: qualityLabel ?? "auto",
            provider: providerName,
            subtitles: [],
            headers: requiredHeaders,
            activePeers: activePeers,
            cookie: nil,
            referer: diagnosticMetadata["referer"],
            nativeOriginProfile: nativeOriginProfile,
            nativePlaylistProfile: nativePlaylistProfile,
            requiresGuardedRelay: requiresGuardedRelay == true,
            playbackContract: playbackContract
        )
    }
}

enum StreamEventName: String, Codable, Sendable {
    case userTappedMatch = "user_tapped_match"
    case streamAttemptCreated = "stream_attempt_created"
    case streamResolutionStarted = "stream_resolution_started"
    case provider1Started = "provider_1_started"
    case provider1Resolved = "provider_1_resolved"
    case provider1ValidationStarted = "provider_1_validation_started"
    case provider1ValidationSucceeded = "provider_1_validation_succeeded"
    case provider1ValidationFailed = "provider_1_validation_failed"
    case fallbackStarted = "fallback_started"
    case fallbackSucceeded = "fallback_succeeded"
    case fallbackFailed = "fallback_failed"
    case readyToPlay = "ready_to_play"
    case playerNavigationStarted = "player_navigation_started"
    case avplayerAssetCreated = "avplayer_asset_created"
    case avplayerItemCreated = "avplayer_item_created"
    case playbackStarted = "playback_started"
    case playbackFailed = "playback_failed"
    case streamRefreshStarted = "stream_refresh_started"
    case streamRefreshSucceeded = "stream_refresh_succeeded"
    case streamRefreshFailed = "stream_refresh_failed"
    case streamCleanupStarted = "stream_cleanup_started"
    case streamCleanupCompleted = "stream_cleanup_completed"
    case streamAttemptCancelled = "stream_attempt_cancelled"
}

struct StreamEventRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let name: StreamEventName
    let timestamp: Date
    let matchID: String
    let matchTitle: String
    let providerName: String?
    let attemptID: String
    let taskID: String?
    let sessionID: String?
    let currentState: StreamLoadState
    let failureCategory: StreamFailureCategory?
    let redactedMetadata: [String: String]

    init(
        id: UUID = UUID(),
        name: StreamEventName,
        timestamp: Date = Date(),
        matchID: String,
        matchTitle: String,
        providerName: String? = nil,
        attemptID: String,
        taskID: String? = nil,
        sessionID: String? = nil,
        currentState: StreamLoadState,
        failureCategory: StreamFailureCategory? = nil,
        redactedMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.matchID = matchID
        self.matchTitle = matchTitle
        self.providerName = providerName
        self.attemptID = attemptID
        self.taskID = taskID
        self.sessionID = sessionID
        self.currentState = currentState
        self.failureCategory = failureCategory
        self.redactedMetadata = redactedMetadata
    }
}

struct StreamProviderAttemptLog: Identifiable, Codable, Sendable {
    let id: UUID
    let providerName: String
    let responseTimeMs: Int
    let resolvedStreamType: StreamType
    let urlShape: String
    let requiredHeaders: Bool
    let validationResult: String
    let manifestResult: String?
    let segmentResult: String?
    let playerStartupResult: String?
    let finalFailureCategory: StreamFailureCategory?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        providerName: String,
        responseTimeMs: Int,
        resolvedStreamType: StreamType,
        urlShape: String,
        requiredHeaders: Bool,
        validationResult: String,
        manifestResult: String? = nil,
        segmentResult: String? = nil,
        playerStartupResult: String? = nil,
        finalFailureCategory: StreamFailureCategory? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.responseTimeMs = responseTimeMs
        self.resolvedStreamType = resolvedStreamType
        self.urlShape = urlShape
        self.requiredHeaders = requiredHeaders
        self.validationResult = validationResult
        self.manifestResult = manifestResult
        self.segmentResult = segmentResult
        self.playerStartupResult = playerStartupResult
        self.finalFailureCategory = finalFailureCategory
        self.timestamp = timestamp
    }
}

struct StreamAttemptDiagnostics: Identifiable, Codable, Sendable {
    let attemptID: String
    let matchID: String
    let matchTitle: String
    let finalState: StreamLoadState
    let createdAt: Date
    let completedAt: Date
    let timeline: [StreamEventRecord]
    let providerAttempts: [StreamProviderAttemptLog]

    var id: String { attemptID }
}

struct StreamPlaybackRequest: Identifiable, Sendable {
    let matchID: String
    let displayTitle: String
    let homeTeam: String
    let awayTeam: String
    let category: String
    let kickoffDate: Date?
    let preferredEvent: AnalyticalDataEngine.EventReference?
    /// An accepted metadata association supplies a lookup identity, never a
    /// media location or permission to bypass the adapter's current response.
    let registryMatch: BroadcastRegistryMatch?
    /// Local diagnostic identity only; never a fixture key or provider parameter.
    let watchID: UUID?

    var id: String { matchID }

    init(
        matchID: String,
        displayTitle: String,
        homeTeam: String,
        awayTeam: String,
        category: String,
        kickoffDate: Date? = nil,
        preferredEvent: AnalyticalDataEngine.EventReference? = nil,
        registryMatch: BroadcastRegistryMatch? = nil,
        watchID: UUID? = nil
    ) {
        self.matchID = matchID
        self.displayTitle = displayTitle
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.category = category
        self.kickoffDate = kickoffDate
        self.preferredEvent = preferredEvent
        self.registryMatch = registryMatch
        self.watchID = watchID
    }

    func usingRegistryMatch(_ match: BroadcastRegistryMatch) -> Self {
        .init(matchID: matchID, displayTitle: displayTitle, homeTeam: homeTeam, awayTeam: awayTeam,
              category: category, kickoffDate: kickoffDate, preferredEvent: preferredEvent, registryMatch: match, watchID: watchID)
    }

    @MainActor
    init(event: AnalyticalDataEngine.EventReference) {
        self.init(event: event, watchID: nil)
    }

    @MainActor
    init(event: AnalyticalDataEngine.EventReference, watchID: UUID?) {
        self.init(
            matchID: event.id,
            displayTitle: event.title ?? "\(event.homeName) vs \(event.awayName)",
            homeTeam: event.homeName,
            awayTeam: event.awayName,
            category: event.normalizedCategory,
            kickoffDate: event.kickoffDate,
            preferredEvent: event, watchID: watchID
        )
    }
}

enum CatalogRouteIdentity {
    nonisolated static func matches(eventID: String, requestedID: String) -> Bool {
        let eventCandidates = candidates(from: eventID)
        let requestCandidates = candidates(from: requestedID)
        return !eventCandidates.isDisjoint(with: requestCandidates)
    }

    nonisolated static func candidates(from rawValue: String) -> Set<String> {
        let trimmed = (rawValue.removingPercentEncoding ?? rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return [] }

        var values: Set<String> = [trimmed]
        if let separator = trimmed.firstIndex(of: ":") {
            let suffix = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty {
                values.insert(suffix)
            }
        }
        return values
    }
}

struct StreamResolutionSuccess: Sendable {
    let attemptID: String
    let sessions: [StreamSession]
    let diagnostics: StreamAttemptDiagnostics

    var primarySession: StreamSession? {
        sessions.first
    }
}

enum StreamResolutionOutcome: Sendable {
    case success(StreamResolutionSuccess)
    case failure(StreamFailure, StreamAttemptDiagnostics)
}

struct StreamAttemptProgress: Sendable {
    let attemptID: String
    let state: StreamLoadState
    let userMessage: String
    let technicalMessage: String?
    let providerName: String?
}

#if DEBUG
actor StreamDebugStore {
    static let shared = StreamDebugStore()

    private var latestByMatchID: [String: StreamAttemptDiagnostics] = [:]

    func record(_ diagnostics: StreamAttemptDiagnostics) {
        latestByMatchID[diagnostics.matchID] = diagnostics
    }

    func latest(matchID: String) -> StreamAttemptDiagnostics? {
        latestByMatchID[matchID]
    }
}
#endif

enum ProcessorError: Error {
    case invalidURL
    case httpError
    case invalidData
    case noSourcesFound
    case timeout
    case proxyError
}

extension ProcessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The stream URL is invalid."
        case .httpError:
            return "The stream server returned an error."
        case .invalidData:
            return "The stream data could not be read."
        case .noSourcesFound:
            return "No playable stream sources were found."
        case .timeout:
            return "The stream request timed out."
        case .proxyError:
            return "The local stream proxy failed to start."
        }
    }
}

// MARK: - Event Data Structures

struct NexusATeams: Codable, Sendable {
    let home: NexusATeam?
    let away: NexusATeam?
}

struct NexusATeam: Codable, Sendable {
    let name: String?
    let badge: String?
}

/// Late discovery is an explicit-Watch policy, not a cross-provider ID mapping.
/// The direct site's published team/time/Watch relationship is validated separately.
enum Score808LateDiscoveryPolicy {
    static let lookupLeadTime: TimeInterval = 30 * 60
    static let lookupTailTime: TimeInterval = 3 * 60 * 60

    static func isLookupWindow(
        kickoffDate: Date?,
        category: String,
        at now: Date = Date()
    ) -> Bool {
        guard category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "football",
              let kickoffDate else {
            return false
        }
        let secondsUntilKickoff = kickoffDate.timeIntervalSince(now)
        return secondsUntilKickoff <= lookupLeadTime
            && secondsUntilKickoff >= -lookupTailTime
    }

}
