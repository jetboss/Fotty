import Foundation
import Observation

/// Metadata associations from Fotty's existing edge. No delivery URL, credential,
/// fixture status or provider enablement is supplied by this registry.
struct BroadcastRegistrySnapshot: Codable, Equatable, Sendable {
    static let maximumBytes = 4 * 1_024 * 1_024
    static let maximumRecords = 4_000
    static let networkFreshness: TimeInterval = 15 * 60
    // Stable listing evidence grants only a fresh resolution attempt. It never
    // extends the existing descriptor/media lease, which is rechecked natively.
    static let sourceLifetime: TimeInterval = 4 * 60 * 60
    static let programmeLifetime: TimeInterval = 10 * 60
    static let retention: TimeInterval = 24 * 60 * 60
    static let providerCodes: Set<String> = ["score808", "communitysports", "plaviosports", "cncsports", "flixstreams", "reviewedtv"]
    static let scopes: Set<String> = ["football", "cricket", "basketball", "baseball", "hockey", "american-football", "rugby", "fight", "motorsport", "golf", "tennis", "darts", "college", "other", "live", "networks"]
    static let reasons: Set<String> = ["source-unavailable", "budget-exhausted", "invalid-collection", "incomplete-catalog", "catalog-conflict", "stale-source", "identity-conflict", "time-conflict", "squad-conflict", "competition-conflict", "format-conflict", "ordinal-conflict", "day-conflict", "missing-date", "missing-participants", "missing-programme", "unverified-fixture", "terminal-fixture", "missing-test-authority", "unsupported-scope", "capacity-exceeded"]

    enum ValidationError: Error, Equatable { case invalidSnapshot, invalidRecord, duplicateIdentity, danglingLink, staleSnapshot }
    enum CoverageStatus: String, Codable, Sendable { case available, empty, partial, failed, unsupported }
    enum Kind: String, Codable, Sendable { case event, channel, programme }
    enum Verification: String, Codable, Sendable { case dated, undated, conflicting }
    enum LinkState: String, Codable, Sendable { case listed, needsVerification, conflicting }
    enum MatchMethod: String, Codable, Sendable {
        case exact, programme
        case testPeriod = "test-period"
        case currentEvent = "current-event"
        case channelAssignment = "channel-assignment"
    }

    struct Provider: Codable, Equatable, Sendable {
        let providerCode: String
        let scope: String
        let status: CoverageStatus
        var complete: Bool? = nil
        var observedAt: Date? = nil
        var lastSuccessAt: Date? = nil
        var expiresAt: Date? = nil
        var nextAttemptAt: Date? = nil
        var failure: String? = nil
    }

    struct Broadcast: Codable, Equatable, Sendable {
        let id: String
        let providerCode: String
        let providerEventID: String
        let streamID: String
        let resourceType: String
        let scope: String
        let kind: Kind
        let sport: String
        let title: String
        let participants: [String]
        var start: Date? = nil
        var startBasis: String? = nil
        var end: Date? = nil
        var competitionID: String? = nil
        var squad: SportsFixtureCatalog.Squad? = nil
        var format: CricketFixtureCatalog.Format? = nil
        var matchOrdinal: Int? = nil
        var day: Int? = nil
        var channelID: String? = nil
        var stationMarket: String? = nil
        let observedAt: Date
        let expiresAt: Date
        let verification: Verification
        let issues: [String]
    }

    struct Fingerprint: Codable, Equatable, Sendable {
        let fixtureID: String
        let sport: String
        let start: Date
        let participants: [String]
        var competitionID: String? = nil
        var squad: SportsFixtureCatalog.Squad? = nil
        var format: CricketFixtureCatalog.Format? = nil
        var matchOrdinal: Int? = nil
        var day: Int? = nil
        var end: Date? = nil
    }

    struct ProgrammeAccess: Codable, Equatable, Sendable {
        enum Entitlement: String, Codable, Sendable { case cleared, denied, blackout, unknown }
        enum Use: String, Codable, Sendable { case eventPlayback = "event-playback", stationOnly = "station-only", unknown }
        enum Territory: String, Codable, Sendable { case worldwide, restricted, unknown }
        let entitlement: Entitlement
        let use: Use
        let territory: Territory
        var reviewID: String? = nil
        var expiresAt: Date? = nil
        static let unknown = Self(entitlement: .unknown, use: .unknown, territory: .unknown)

        nonisolated func permitsEvent(at now: Date) -> Bool {
            guard entitlement == .cleared, use == .eventPlayback, territory == .worldwide,
                  let reviewID, !reviewID.isEmpty, reviewID.utf8.count <= 128,
                  reviewID.range(of: #"^[A-Za-z0-9_.:\-]+$"#, options: .regularExpression) != nil,
                  let expiresAt else { return false }
            return expiresAt > now
        }
    }

    struct Link: Codable, Equatable, Sendable {
        let fixtureID: String
        let broadcastID: String
        let providerCode: String
        let state: LinkState
        let matchMethod: MatchMethod
        let fixtureFingerprint: Fingerprint
        let expiresAt: Date
        var reason: String? = nil
        var startRelation: String? = nil
        var access: ProgrammeAccess? = nil
    }

    let schemaVersion: Int
    let revision: String
    let generatedAt: Date
    let providers: [Provider]
    let broadcasts: [Broadcast]
    let links: [Link]
    var tvGuide: [SportsTVGuideItem]? = nil

    static func validated(from data: Data, at now: Date, cached: Bool = false) throws -> Self {
        guard data.count <= maximumBytes, now.timeIntervalSince1970.isFinite else { throw ValidationError.invalidSnapshot }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.date(value) else { throw ValidationError.invalidRecord }
            return date
        }
        let decoded = try decoder.decode(Self.self, from: data)
        // A source the app has retired (StreamEx, StreamVix) may still be
        // published by the Worker. Drop its rows instead of rejecting the
        // whole registry; every remaining row keeps the checks below.
        let value = Self(schemaVersion: decoded.schemaVersion, revision: decoded.revision,
            generatedAt: decoded.generatedAt,
            providers: decoded.providers.filter { providerCodes.contains($0.providerCode) },
            broadcasts: decoded.broadcasts.filter { providerCodes.contains($0.providerCode) },
            links: decoded.links.filter { providerCodes.contains($0.providerCode) },
            tvGuide: decoded.tvGuide)
        guard value.schemaVersion == 1, safeText(value.revision, limit: 128),
              value.providers.count <= providerCodes.count * scopes.count,
              value.broadcasts.count <= maximumRecords, value.links.count <= maximumRecords else { throw ValidationError.invalidSnapshot }
        guard (-300...(cached ? retention : networkFreshness)).contains(now.timeIntervalSince(value.generatedAt)) else {
            throw ValidationError.staleSnapshot
        }
        var coverageKeys = Set<String>()
        for provider in value.providers {
            guard providerCodes.contains(provider.providerCode), scopes.contains(provider.scope),
                  provider.failure.map(reasons.contains) ?? true,
                  provider.observedAt.map({ $0 <= value.generatedAt.addingTimeInterval(300) }) ?? true,
                  provider.lastSuccessAt.map({ $0 <= value.generatedAt.addingTimeInterval(300) }) ?? true,
                  provider.nextAttemptAt.map({ $0 <= value.generatedAt.addingTimeInterval(retention) }) ?? true else { throw ValidationError.invalidRecord }
            if [.available, .empty, .partial].contains(provider.status) {
                guard let observed = provider.observedAt, let expiry = provider.expiresAt,
                      validLifetime(observed, expiry) else { throw ValidationError.invalidRecord }
            } else if let expiry = provider.expiresAt {
                guard let observed = provider.observedAt, validLifetime(observed, expiry) else { throw ValidationError.invalidRecord }
            }
            guard coverageKeys.insert(provider.providerCode + ":" + provider.scope).inserted else { throw ValidationError.duplicateIdentity }
        }
        var IDs = Set<String>(), providerIDs = Set<String>()
        for broadcast in value.broadcasts {
            guard broadcast.id.range(of: #"^br:[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                  providerCodes.contains(broadcast.providerCode), scopes.contains(broadcast.scope),
                  coverageKeys.contains(broadcast.providerCode + ":" + broadcast.scope),
                  safeReference(broadcast.providerEventID), safeReference(broadcast.streamID), broadcast.resourceType == "tv",
                  scopes.subtracting(["live", "networks"]).union(["unknown"]).contains(broadcast.sport),
                  safeText(broadcast.title, limit: 512), validParticipants(broadcast.participants, exactlyTwo: false,
                    requireDistinct: broadcast.verification != .conflicting),
                  validLifetime(broadcast.observedAt, broadcast.expiresAt,
                    maximum: broadcast.kind == .programme || broadcast.providerCode == "reviewedtv"
                        ? programmeLifetime : sourceLifetime),
                  broadcast.observedAt <= value.generatedAt.addingTimeInterval(300),
                  broadcast.issues.count <= 21, broadcast.issues.allSatisfy(reasons.contains),
                  Set(broadcast.issues).count == broadcast.issues.count,
                  broadcast.competitionID.map({ safeText($0, limit: 128) }) ?? true,
                  validSquad(broadcast.squad), validCricket(format: broadcast.format, ordinal: broadcast.matchOrdinal, day: broadcast.day),
                  validChannelAndMarket(broadcast),
                  broadcast.startBasis == nil || isCurrentCricketListing(broadcast) else { throw ValidationError.invalidRecord }
            if broadcast.verification != .conflicting, let start = broadcast.start, let end = broadcast.end {
                guard end > start, end.timeIntervalSince(start) <= 7 * 86_400 else { throw ValidationError.invalidRecord }
            }
            if broadcast.verification == .dated, broadcast.start == nil { throw ValidationError.invalidRecord }
            if broadcast.kind == .programme, broadcast.verification != .conflicting {
                guard broadcast.start != nil, let end = broadcast.end,
                      broadcast.channelID != nil, broadcast.expiresAt <= end else { throw ValidationError.invalidRecord }
            }
            if broadcast.kind == .channel, broadcast.verification != .conflicting {
                guard broadcast.start == nil, broadcast.end == nil, broadcast.participants.isEmpty,
                      broadcast.format == nil, broadcast.matchOrdinal == nil, broadcast.day == nil else { throw ValidationError.invalidRecord }
            }
            guard IDs.insert(broadcast.id).inserted,
                  providerIDs.insert([broadcast.providerCode, broadcast.providerEventID, broadcast.streamID].joined(separator: "\n")).inserted else { throw ValidationError.duplicateIdentity }
        }
        let records = Dictionary(uniqueKeysWithValues: value.broadcasts.map { ($0.id, $0) })
        var linkIDs = Set<String>()
        var acceptedLinks: [Link] = []
        var incompleteScopes = Set<String>()
        for link in value.links {
            let fingerprint = link.fixtureFingerprint
            guard let broadcast = records[link.broadcastID], broadcast.kind != .channel,
                  broadcast.providerCode == link.providerCode,
                  safeText(link.fixtureID, limit: 512), link.fixtureID == fingerprint.fixtureID,
                  safeText(fingerprint.sport, limit: 32), scopes.contains(fingerprint.sport),
                  validParticipants(fingerprint.participants, exactlyTwo: true),
                  fingerprint.competitionID.map({ safeText($0, limit: 128) }) ?? true,
                  validSquad(fingerprint.squad), validCricket(format: fingerprint.format, ordinal: fingerprint.matchOrdinal, day: fingerprint.day),
                  fingerprint.end.map({ $0 > fingerprint.start && $0.timeIntervalSince(fingerprint.start) <= 7 * 86_400 }) ?? true,
                  link.expiresAt <= broadcast.expiresAt else { throw ValidationError.danglingLink }
            guard linkIDs.insert([link.fixtureID, link.broadcastID, link.providerCode].joined(separator: "\n")).inserted else { throw ValidationError.duplicateIdentity }
            if link.matchMethod == .currentEvent {
                guard isCurrentCricketListing(broadcast), fingerprint.sport == "cricket",
                      link.state != .listed || broadcast.verification == .undated
                        && (fingerprint.format == .odi || fingerprint.format == .t20),
                      link.expiresAt <= broadcast.observedAt.addingTimeInterval(sourceLifetime) else { throw ValidationError.danglingLink }
            }
            if link.matchMethod == .channelAssignment {
                guard broadcast.providerCode == "reviewedtv", broadcast.kind == .event,
                      ReviewedTVPlaylistClient.supportsScheduledSport(broadcast),
                      broadcast.stationMarket == "UY", broadcast.end == nil else { throw ValidationError.danglingLink }
            }
            let relationIsValid: Bool
            switch link.startRelation {
            case nil:
                // Earlier Workers omitted this field only on negative assignments.
                relationIsValid = link.matchMethod != .channelAssignment || link.state != .listed
            case "early-coverage":
                relationIsValid = link.matchMethod == .exact
            case "channel-coverage":
                relationIsValid = link.matchMethod == .channelAssignment
            default:
                relationIsValid = false
            }
            let reasonIsValid = link.state == .listed ? link.reason == nil : link.reason.map(reasons.contains) == true
            guard relationIsValid && reasonIsValid else {
                // A malformed annotation on a known negative cannot grant or
                // revoke a different match. Preserve verified parent/identity
                // checks above and never describe its scope as complete.
                guard link.state != .listed else { throw ValidationError.danglingLink }
                incompleteScopes.insert(broadcast.providerCode + ":" + broadcast.scope)
                continue
            }
            acceptedLinks.append(link)
        }
        guard !incompleteScopes.isEmpty else { return value }
        let providers = value.providers.map { provider -> Provider in
            guard incompleteScopes.contains(provider.providerCode + ":" + provider.scope),
                  [.available, .empty, .partial].contains(provider.status) else { return provider }
            return Provider(providerCode: provider.providerCode, scope: provider.scope, status: .partial, complete: false,
                observedAt: provider.observedAt, lastSuccessAt: provider.lastSuccessAt, expiresAt: provider.expiresAt,
                nextAttemptAt: provider.nextAttemptAt, failure: provider.failure)
        }
        return Self(schemaVersion: value.schemaVersion, revision: value.revision, generatedAt: value.generatedAt,
            providers: providers, broadcasts: value.broadcasts, links: acceptedLinks, tvGuide: value.tvGuide)
    }

    static func isCurrentCricketListing(_ broadcast: Broadcast) -> Bool {
        guard broadcast.startBasis == "current-listing", broadcast.providerCode == "communitysports",
              broadcast.providerEventID.range(of: #"^nuvio_sport_sktech_sktech_ev_fancode_[0-9]+$"#, options: .regularExpression) != nil,
              broadcast.streamID == broadcast.providerEventID, broadcast.resourceType == "tv", broadcast.kind == .event,
              broadcast.sport == "cricket", ["cricket", "live"].contains(broadcast.scope),
              broadcast.title.hasPrefix("🔴 LIVE: "), broadcast.format == nil, broadcast.matchOrdinal == nil,
              broadcast.day == nil, broadcast.end == nil, broadcast.channelID == nil, broadcast.competitionID == nil,
              broadcast.squad == nil, broadcast.stationMarket == nil, let clock = broadcast.start,
              (-300...sourceLifetime).contains(broadcast.observedAt.timeIntervalSince(clock)),
              let title = ReviewedSportsFixtureMatcher.participantIdentity(sport: "cricket", cast: [], title: broadcast.title),
              let pair = participantPair(broadcast.participants, sport: "cricket") else { return false }
        return title.pair == pair
    }

    /// A country's schedule belongs only to its reviewed linear feed. Other
    /// source families retain the existing exact US-Willow station contract.
    private static func validChannelAndMarket(_ broadcast: Broadcast) -> Bool {
        if broadcast.providerCode == ReviewedTVPlaylistClient.providerCode, ["football", "baseball", "hockey"].contains(broadcast.sport) {
            guard broadcast.kind == .event, broadcast.scope == broadcast.sport,
                  ReviewedTVPlaylistClient.supportsScheduledSport(broadcast),
                  let id = broadcast.channelID,
                  let channel = ReviewedTVPlaylistClient.channel(forChannelID: id),
                  channel.sports.contains(broadcast.sport), channel.streamID == broadcast.streamID,
                  channel.markets.contains("UY"), broadcast.stationMarket == "UY",
                  ReviewedTVPlaylistClient.isAssignmentID(broadcast.providerEventID),
                  broadcast.format == nil, broadcast.matchOrdinal == nil, broadcast.day == nil,
                  broadcast.end == nil else { return false }
            return true
        }
        guard broadcast.channelID.map({ CricketBroadcastChannel.allCases.map(\.canonicalID).contains($0) }) ?? true else { return false }
        return broadcast.stationMarket == nil || isReviewedCricketChannelMarket(broadcast)
    }

    static func isReviewedCricketChannelMarket(_ broadcast: Broadcast) -> Bool {
        broadcast.providerCode == "communitysports" && broadcast.kind == .channel && broadcast.sport == "cricket"
            && ["cricket", "live", "networks"].contains(broadcast.scope)
            && (broadcast.stationMarket == "US" && broadcast.channelID == CricketBroadcastChannel.willow.canonicalID
                || broadcast.stationMarket == "AU" && broadcast.channelID == CricketBroadcastChannel.foxCricket.canonicalID)
    }

    /// Each match retains the same source identity used by browsing and the
    /// resolver. A generic channel never lends a programme to a fixture.
    func lookup(for request: StreamPlaybackRequest, enabledProviderCodes: Set<String>, at now: Date) -> [BroadcastRegistryMatch] {
        LookupIndex(snapshot: self).lookup(for: request, enabledProviderCodes: enabledProviderCodes, at: now)
    }

    /// Prepared once by the background parsing owner. Visible rows inspect only
    /// their fixture's links, never rebuild the entire registry's dictionaries.
    struct LookupIndex: Sendable {
        let generatedAt: Date
        private let coverage: [String: Provider]
        private let records: [String: Broadcast]
        private let linksByFixture: [String: [Link]]
        private let linksByBroadcast: [String: [Link]]
        private let channels: [String: [Broadcast]]

        init(snapshot: BroadcastRegistrySnapshot) {
            generatedAt = snapshot.generatedAt
            coverage = Dictionary(snapshot.providers.map { ($0.providerCode + ":" + $0.scope, $0) }, uniquingKeysWith: { first, _ in first })
            records = Dictionary(snapshot.broadcasts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            linksByFixture = Dictionary(grouping: snapshot.links, by: \.fixtureID)
            linksByBroadcast = Dictionary(grouping: snapshot.links, by: \.broadcastID)
            channels = Dictionary(grouping: snapshot.broadcasts.filter { $0.kind == .channel && $0.channelID != nil }, by: { $0.channelID! })
        }

        func lookup(for request: StreamPlaybackRequest, enabledProviderCodes: Set<String>, at now: Date) -> [BroadcastRegistryMatch] {
            guard now.timeIntervalSince1970.isFinite,
                  (-300...BroadcastRegistrySnapshot.retention).contains(now.timeIntervalSince(generatedAt)),
                  request.preferredEvent?.hasCatalogIdentityConflict != true else { return [] }
            let enabled = Set(enabledProviderCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            if let channel = CricketBroadcastChannel.identifying(request: request) {
                return (channels[channel.canonicalID] ?? []).compactMap { broadcast in
                    guard enabled.contains(broadcast.providerCode),
                          let provider = coverage[broadcast.providerCode + ":" + broadcast.scope] else { return nil }
                    let match = BroadcastRegistryMatch(broadcast: broadcast, link: nil, provider: provider)
                    return match.matches(request: request, providerCode: broadcast.providerCode,
                        providerEventID: broadcast.providerEventID, streamID: broadcast.streamID, at: now) ? match : nil
                }
            }
            let fixtureLinks = linksByFixture[request.matchID] ?? []
            let direct: [BroadcastRegistryMatch] = fixtureLinks.compactMap { link in
                // Competing current official fixtures cannot both own the same
                // advertised delivery. Unrelated healthy broadcasts remain usable.
                guard Set((linksByBroadcast[link.broadcastID] ?? []).filter {
                    $0.state == .listed && $0.expiresAt > now
                }.map(\.fixtureID)).count <= 1 else { return nil }
                guard link.state == .listed, enabled.contains(link.providerCode),
                      let broadcast = records[link.broadcastID], let provider = coverage[link.providerCode + ":" + broadcast.scope] else { return nil }
                // Fox supplies programme authority, not a reviewed-TV media
                // profile. Only the verified enabled channel join below plays it.
                if ReviewedTVPlaylistClient.isFoxProgramme(broadcast) { return nil }
                let match = BroadcastRegistryMatch(broadcast: broadcast, link: link, provider: provider)
                return match.matches(request: request, providerCode: link.providerCode,
                    providerEventID: broadcast.providerEventID, streamID: broadcast.streamID, at: now) ? match : nil
            }
            // Programme metadata is independent of the playback-provider opt-in.
            // A verified guide may qualify another enabled delivery of its exact
            // linear channel, without fabricating a public source observation.
            var joined: [BroadcastRegistryMatch] = []
            if enabled.contains("communitysports") {
                for guideLink in fixtureLinks where guideLink.providerCode == ReviewedTVPlaylistClient.providerCode {
                    guard Set((linksByBroadcast[guideLink.broadcastID] ?? []).filter {
                        $0.state == .listed && $0.expiresAt > now
                    }.map(\.fixtureID)).count <= 1,
                          let programme = records[guideLink.broadcastID],
                          let guideProvider = coverage[programme.providerCode + ":" + programme.scope] else { continue }
                    let guide = BroadcastRegistryMatch(broadcast: programme, link: guideLink, provider: guideProvider)
                    guard ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(guide), at: now) != nil,
                          let channelID = programme.channelID else { continue }
                    let authority = BroadcastRegistryMatch.ProgrammeAuthority(broadcast: programme, link: guideLink, provider: guideProvider)
                    for channel in channels[channelID] ?? [] where channel.providerCode == "communitysports" {
                        guard let provider = coverage[channel.providerCode + ":" + channel.scope] else { continue }
                        let match = BroadcastRegistryMatch(broadcast: channel, link: nil, provider: provider, programmeAuthority: authority)
                        if match.matches(request: request, providerCode: "communitysports", providerEventID: channel.providerEventID,
                            streamID: channel.streamID, at: now) { joined.append(match) }
                    }
                }
            }
            var seen = Set<String>()
            return (direct + joined).filter {
                seen.insert([$0.broadcast.providerCode, $0.broadcast.providerEventID, $0.broadcast.streamID,
                    $0.programmeAuthority?.broadcast.providerEventID ?? ""].joined(separator: "\n")).inserted
            }
        }
    }

    func accepting(_ candidate: Self) -> Self {
        (try? reconciling(candidate)) ?? self
    }

    private enum AcceptanceError: Error { case rejectedEnvelope }

    /// Keep rollback protection local to the observation that regressed. A
    /// retained diagnostic row must not veto fresh assignments for other games.
    /// Rejected observations never supply replacement links or renewed leases.
    fileprivate func reconciling(_ candidate: Self) throws -> Self {
        guard candidate.generatedAt >= generatedAt,
              candidate.generatedAt != generatedAt || candidate == self else { throw AcceptanceError.rejectedEnvelope }
        let old = Dictionary(uniqueKeysWithValues: broadcasts.map { ($0.id, $0) })
        let rejected = Set(candidate.broadcasts.compactMap { next -> String? in
            guard let previous = old[next.id], next.observedAt < previous.observedAt
                || next.observedAt == previous.observedAt && next.expiresAt > previous.expiresAt else { return nil }
            return next.id
        })
        guard !rejected.isEmpty else { return candidate }

        let healthyRows = candidate.broadcasts.filter { !rejected.contains($0.id) }
        let healthyLinks = candidate.links.filter { !rejected.contains($0.broadcastID) }
        let coverage = Set(candidate.providers.map { $0.providerCode + ":" + $0.scope })
        var identities = Set(healthyRows.map { [$0.providerCode, $0.providerEventID, $0.streamID].joined(separator: "\n") })
        let oldLinks = Dictionary(grouping: links, by: \.broadcastID)
        let restricted = Set(candidate.links.compactMap { link -> String? in
            guard let access = link.access, !access.permitsEvent(at: candidate.generatedAt) else { return nil }
            return link.broadcastID + "\n" + link.fixtureID
        })
        var retainedRows: [Broadcast] = [], retainedLinks: [Link] = []
        // Candidate order keeps reconciliation deterministic. The old exact row
        // can survive only within the new envelope's coverage and global bounds.
        for next in candidate.broadcasts where rejected.contains(next.id) {
            guard let previous = old[next.id], coverage.contains(previous.providerCode + ":" + previous.scope),
                  identities.insert([previous.providerCode, previous.providerEventID, previous.streamID].joined(separator: "\n")).inserted else { continue }
            retainedRows.append(previous)
            let prior = (oldLinks[previous.id] ?? []).filter { !restricted.contains($0.broadcastID + "\n" + $0.fixtureID) }
            // Preserve the complete prior association set or none: dropping one
            // competing link could incorrectly make an ambiguous source usable.
            if healthyLinks.count + retainedLinks.count + prior.count <= Self.maximumRecords {
                retainedLinks.append(contentsOf: prior)
            }
        }
        func rebuilt(rows: [Broadcast], links: [Link]) throws -> Self {
            let value = Self(schemaVersion: candidate.schemaVersion, revision: candidate.revision,
                generatedAt: candidate.generatedAt, providers: candidate.providers,
                broadcasts: rows, links: links, tvGuide: candidate.tvGuide)
            return try Self.validated(from: value.encoded(), at: candidate.generatedAt)
        }
        // Revalidate the combined wire contract, including size, references and
        // identity bounds. If retaining old facts cannot fit, quarantine only the
        // regressing observations; the independently valid siblings still advance.
        if let retained = try? rebuilt(rows: healthyRows + retainedRows, links: healthyLinks + retainedLinks) { return retained }
        return try rebuilt(rows: healthyRows, links: healthyLinks)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(self)
    }

    static func date(_ text: String) -> Date? {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$"#, options: .regularExpression) != nil else { return nil }
        return CricketFixtureCatalog.date(text)
    }
    static func participantPair(_ names: [String], sport: String) -> [String]? {
        guard names.count == 2 else { return nil }
        return ReviewedSportsFixtureMatcher.participantIdentity(sport: sport, cast: names,
            title: "\(names[0]) vs \(names[1])")?.pair
    }
    private static func validLifetime(_ observed: Date, _ expiry: Date, maximum: TimeInterval = sourceLifetime) -> Bool {
        // Retained diagnostic observations may already have expired when
        // collected (for example a programme whose published end just passed).
        // They are valid evidence, never a current lookup result.
        expiry.timeIntervalSince(observed) <= maximum
    }
    private static func safeText(_ text: String, limit: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= limit * 4 && text.count <= limit
            && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && !text.contains("://") && !text.contains("<") && !text.contains(">")
            && !text.unicodeScalars.contains { scalar in
                // Match the edge text contract. ZWJ/emoji tags are display
                // formatting, while Cc and directional overrides are rejected.
                scalar.properties.generalCategory == .control
                    || scalar.value == 0x061C || scalar.value == 0x200E || scalar.value == 0x200F
                    || (0x202A...0x202E).contains(scalar.value)
                    || (0x2066...0x2069).contains(scalar.value)
            }
    }
    private static func safeReference(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 4_096
            && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:~=")).contains($0) }
    }
    private static func validParticipants(_ participants: [String], exactlyTwo: Bool, requireDistinct: Bool = true) -> Bool {
        (exactlyTwo ? participants.count == 2 : participants.count <= 8)
            && participants.allSatisfy { safeText($0, limit: 256) }
            && (!requireDistinct || Set(participants.map(SportsTeamIdentity.normalized)).count == participants.count)
    }
    private static func validSquad(_ squad: SportsFixtureCatalog.Squad?) -> Bool {
        squad.map { safeText($0.ageGroup, limit: 32) } ?? true
    }
    private static func validCricket(format: CricketFixtureCatalog.Format?, ordinal: Int?, day: Int?) -> Bool {
        format != .unknown && (ordinal.map { format != nil && (1...99).contains($0) } ?? true)
            && (day.map { format == .test && (1...6).contains($0) } ?? true)
    }
}

extension BroadcastRegistrySnapshot.Link {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(BroadcastRegistrySnapshot.LinkState.self, forKey: .state)
        func annotation(_ key: CodingKeys) throws -> String? {
            do { return try values.decodeIfPresent(String.self, forKey: key) }
            catch {
                guard state != .listed else { throw error }
                // This invalid marker is quarantined once parent identity,
                // fingerprint and duplicate checks finish in validated().
                return ""
            }
        }
        let access: BroadcastRegistrySnapshot.ProgrammeAccess?
        if values.contains(.access) {
            // A malformed or explicit-null policy cannot fall back to the
            // historic profile. Unknown access cannot grant automatic use.
            access = (try? values.decode(BroadcastRegistrySnapshot.ProgrammeAccess.self, forKey: .access)) ?? .unknown
        } else { access = nil }
        self.init(fixtureID: try values.decode(String.self, forKey: .fixtureID),
            broadcastID: try values.decode(String.self, forKey: .broadcastID),
            providerCode: try values.decode(String.self, forKey: .providerCode), state: state,
            matchMethod: try values.decode(BroadcastRegistrySnapshot.MatchMethod.self, forKey: .matchMethod),
            fixtureFingerprint: try values.decode(BroadcastRegistrySnapshot.Fingerprint.self, forKey: .fixtureFingerprint),
            expiresAt: try values.decode(Date.self, forKey: .expiresAt),
            reason: try annotation(.reason), startRelation: try annotation(.startRelation), access: access)
    }
}

struct BroadcastRegistryMatch: Equatable, Sendable {
    /// Private, derived provenance only. The wire snapshot and both original
    /// observations remain unchanged and keep their independent receipts.
    struct ProgrammeAuthority: Equatable, Sendable {
        let broadcast: BroadcastRegistrySnapshot.Broadcast
        let link: BroadcastRegistrySnapshot.Link
        let provider: BroadcastRegistrySnapshot.Provider
    }
    let broadcast: BroadcastRegistrySnapshot.Broadcast
    let link: BroadcastRegistrySnapshot.Link?
    let provider: BroadcastRegistrySnapshot.Provider
    var programmeAuthority: ProgrammeAuthority? = nil

    /// Orders a new opportunity against an earlier negative lookup. This does
    /// not renew either observation, extend a lease or override a later failure.
    var availabilityObservedAt: Date {
        max(broadcast.observedAt, programmeAuthority?.broadcast.observedAt ?? broadcast.observedAt)
    }

    var acceptanceExpiresAt: Date {
        var facts = [broadcast.expiresAt]
        if let expiry = provider.expiresAt { facts.append(expiry) }
        if let expiry = link?.expiresAt { facts.append(expiry) }
        if let expiry = link?.access?.expiresAt { facts.append(expiry) }
        if let authority = programmeAuthority {
            facts += [authority.broadcast.expiresAt, authority.link.expiresAt]
            if let expiry = authority.link.access?.expiresAt { facts.append(expiry) }
            if let expiry = authority.provider.expiresAt { facts.append(expiry) }
            if let end = authority.broadcast.end { facts.append(end) }
        }
        return facts.min() ?? broadcast.expiresAt
    }

    /// Source metadata, a television edition and the device locale do not
    /// establish territorial entitlement. A global response can admit explicit
    /// clearance only when no per-user territory or account check is required.
    nonisolated func permitsAutomaticProgramme(at now: Date) -> Bool {
        let guide = programmeAuthority?.broadcast ?? broadcast
        let guideLink = programmeAuthority?.link ?? link
        if let access = guideLink?.access { return access.permitsEvent(at: now) }
        guard guide.providerCode == "reviewedtv" else { return true }
        // Reviewed programme identity is not an entitlement claim. Explicit
        // access restrictions above still override the matching contract.
        if guide.kind == .programme {
            return ReviewedTVPlaylistClient.isFoxProgramme(guide)
                || guide.sport == "cricket" && guide.channelID == CricketBroadcastChannel.willow.canonicalID
        }
        guard guide.stationMarket == "UY", guide.channelID?.range(
            of: #"^sports-channel:espn(?:[2-7])?-latinamerica-south$"#, options: .regularExpression) != nil else { return false }
        switch guide.sport {
        case "football":
            return ["premier-league", "champions-league", "la-liga", "serie-a", "bundesliga", "ligue-1"].contains(guide.competitionID ?? "")
        case "baseball": return guide.competitionID == "mlb"
        case "hockey": return guide.competitionID == "nhl"
        default: return false
        }
    }

    struct DecisionReceipt: Equatable, Sendable {
        enum Provenance: String, Sendable { case providerEvent, willowProgramme, foxProgramme, espnEdition, stationTune }
        enum Confidence: String, Sendable { case confirmedAssignment, explicitStation, unverified }
        let provider: String
        let provenance: Provenance
        let confidence: Confidence
        let fixtureID: String?
        let edition: String?
        let guideMarket: String?
        let observedAt: Date
        let evidenceExpiresAt: Date
        let access: BroadcastRegistrySnapshot.ProgrammeAccess
        let hasExplicitAccessPolicy: Bool
        // Descriptor/media expiry belongs to the resolver. A listing has no media lease.
        var mediaExpiresAt: Date? { nil }
    }

    func decisionReceipt(at now: Date) -> DecisionReceipt {
        let guide = programmeAuthority?.broadcast ?? broadcast
        let association = programmeAuthority?.link ?? link
        let station = broadcast.kind == .channel && association == nil
        let provenance: DecisionReceipt.Provenance = station ? .stationTune
            : ReviewedTVPlaylistClient.isFoxProgramme(guide) && association?.matchMethod == .programme ? .foxProgramme
            : guide.providerCode == "reviewedtv" && association?.matchMethod == .programme ? .willowProgramme
            : guide.providerCode == "reviewedtv" && association?.matchMethod == .channelAssignment ? .espnEdition : .providerEvent
        let confirmed = association?.state == .listed && acceptanceExpiresAt > now && hasCurrentSource(at: now) && permitsAutomaticProgramme(at: now)
        return DecisionReceipt(provider: broadcast.providerCode, provenance: provenance,
            confidence: station ? .explicitStation : confirmed ? .confirmedAssignment : .unverified,
            fixtureID: association?.fixtureID, edition: guide.channelID,
            guideMarket: provenance == .willowProgramme ? "US" : provenance == .foxProgramme ? "AU" : guide.stationMarket,
            observedAt: availabilityObservedAt, evidenceExpiresAt: acceptanceExpiresAt,
            access: association?.access ?? .unknown, hasExplicitAccessPolicy: association?.access != nil)
    }

    private func hasCurrentSource(at now: Date) -> Bool {
        // Retain the accepted listing through a failed refresh, without
        // renewing its receipt or granting authority to reuse an old URL.
        let retained = provider.status == .failed && provider.lastSuccessAt != nil
            && provider.lastSuccessAt == provider.observedAt
        guard now.timeIntervalSince1970.isFinite, provider.providerCode == broadcast.providerCode,
              provider.scope == broadcast.scope, [.available, .partial].contains(provider.status) || retained,
              let observed = provider.observedAt, let expiry = provider.expiresAt,
              (-300...BroadcastRegistrySnapshot.sourceLifetime).contains(now.timeIntervalSince(observed)), expiry > now,
              (-300...BroadcastRegistrySnapshot.sourceLifetime).contains(now.timeIntervalSince(broadcast.observedAt)),
              broadcast.expiresAt > now, broadcast.verification != .conflicting else { return false }
        return Set(broadcast.issues).isDisjoint(with: ["invalid-collection", "catalog-conflict", "stale-source",
            "identity-conflict", "time-conflict", "squad-conflict", "competition-conflict", "format-conflict",
            "ordinal-conflict", "day-conflict", "missing-date", "missing-participants", "missing-programme",
            "unverified-fixture", "terminal-fixture", "missing-test-authority"])
    }

    /// A current adapter response must still advertise these exact source facts.
    /// The registry cannot substitute a canonical kickoff for a changed source
    /// clock, or turn whole-Test identity into a daily occurrence.
    func admitsFreshIdentity(sport: String, participants: [String], start: Date,
                             providerEventID: String, streamID: String, format: String? = nil,
                             matchOrdinal: Int? = nil, day: Int? = nil, at now: Date) -> Bool {
        guard let pair = BroadcastRegistrySnapshot.participantPair(participants, sport: sport) else { return false }
        return admitsFreshIdentity(sport: sport, pair: pair, start: start, providerEventID: providerEventID,
            streamID: streamID, format: format, matchOrdinal: matchOrdinal, day: day, at: now)
    }

    func admitsFreshIdentity(sport: String, pair: [String], start: Date,
                             providerEventID: String, streamID: String, format: String? = nil,
                             matchOrdinal: Int? = nil, day: Int? = nil, at now: Date) -> Bool {
        guard hasCurrentSource(at: now), broadcast.kind != .channel,
              let link, link.state == .listed, link.expiresAt > now, link.providerCode == broadcast.providerCode,
              broadcast.verification == .dated, broadcast.startBasis == nil,
              broadcast.providerEventID == providerEventID, broadcast.streamID == streamID,
              broadcast.sport == ReviewedSportsFixtureMatcher.sportKey(sport), broadcast.start == start,
              pair.count == 2, pair == BroadcastRegistrySnapshot.participantPair(broadcast.participants, sport: broadcast.sport),
              format == broadcast.format?.rawValue, matchOrdinal == broadcast.matchOrdinal, day == broadcast.day else { return false }
        switch link.matchMethod {
        case .currentEvent: return false // CS rechecks its synthetic-clock contract in the native adapter.
        case .exact: return day == nil
        case .testPeriod:
            return format == CricketFixtureCatalog.Format.test.rawValue && day != nil && matchOrdinal != nil
                && link.fixtureFingerprint.day == day && link.fixtureFingerprint.matchOrdinal == matchOrdinal
        case .programme: return broadcast.kind == .programme && broadcast.channelID != nil
        case .channelAssignment:
            return broadcast.providerCode == "reviewedtv" && broadcast.kind == .event
                && ReviewedTVPlaylistClient.supportsScheduledSport(broadcast) && broadcast.stationMarket == "UY"
                && link.startRelation == "channel-coverage"
                && ReviewedTVPlaylistClient.hasProgrammeShape(self, at: now)
        }
    }

    /// Reapply this exact association before resolving a new descriptor. This
    /// validates identity only, never authorizes a URL or asserts decoded play.
    func matches(request: StreamPlaybackRequest, providerCode: String, providerEventID: String,
                 streamID: String, at now: Date) -> Bool {
        guard hasCurrentSource(at: now), broadcast.providerCode == providerCode,
              broadcast.providerEventID == providerEventID, broadcast.streamID == streamID,
              request.preferredEvent?.hasCatalogIdentityConflict != true else { return false }
        if let authority = programmeAuthority {
            guard link == nil, CricketBroadcastChannel.identifying(request: request) == nil,
                  broadcast.providerCode == "communitysports", ["cricket", "live", "networks"].contains(broadcast.scope),
                  BroadcastRegistrySnapshot.isReviewedCricketChannelMarket(broadcast),
                  broadcast.participants.isEmpty, broadcast.start == nil, broadcast.end == nil,
                  broadcast.format == nil, broadcast.matchOrdinal == nil, broadcast.day == nil,
                  authority.broadcast.channelID == broadcast.channelID, acceptanceExpiresAt > now else { return false }
            let guide = Self(broadcast: authority.broadcast, link: authority.link, provider: authority.provider)
            return ReviewedTVPlaylistClient.programmeAssociation(for: request.usingRegistryMatch(guide), at: now) != nil
        }
        if let channel = CricketBroadcastChannel.identifying(request: request) {
            if broadcast.providerCode == ReviewedTVPlaylistClient.providerCode {
                guard channel == .willow, broadcast.providerEventID == ReviewedTVPlaylistClient.providerEventID,
                      broadcast.streamID == ReviewedTVPlaylistClient.providerEventID else { return false }
            }
            return link == nil && broadcast.kind == .channel && broadcast.channelID == channel.canonicalID
                && broadcast.participants.isEmpty && broadcast.start == nil && broadcast.end == nil
        }
        if broadcast.providerCode == ReviewedTVPlaylistClient.providerCode,
           !ReviewedTVPlaylistClient.hasProgrammeShape(self, at: now) { return false }
        guard let link, link.state == .listed, link.expiresAt > now,
              link.fixtureID == request.matchID, link.fixtureFingerprint.fixtureID == request.matchID,
              link.fixtureFingerprint.participants.count == 2,
              let requested = ReviewedSportsFixtureMatcher.requestIdentity(for: request),
              let event = request.preferredEvent, event.id == request.matchID,
              request.kickoffDate == event.kickoffDate, let start = request.kickoffDate,
              let pair = BroadcastRegistrySnapshot.participantPair(link.fixtureFingerprint.participants, sport: requested.sport),
              pair == requested.pair, link.fixtureFingerprint.sport == requested.sport,
              link.fixtureFingerprint.start == start,
              link.fixtureFingerprint.competitionID == (event.competitionID ?? event.cricketFixture?.competitionID),
              broadcast.sport == requested.sport, broadcast.kind != .channel,
              broadcast.verification == .dated && broadcast.startBasis == nil
                || link.matchMethod == .currentEvent && broadcast.verification == .undated
                    && BroadcastRegistrySnapshot.isCurrentCricketListing(broadcast),
              broadcast.participants.count == 2,
              BroadcastRegistrySnapshot.participantPair(broadcast.participants, sport: requested.sport) == pair,
              broadcast.competitionID == nil || link.fixtureFingerprint.competitionID == nil
                || broadcast.competitionID == link.fixtureFingerprint.competitionID,
              broadcast.squad == nil || link.fixtureFingerprint.squad == nil
                || broadcast.squad == link.fixtureFingerprint.squad,
              broadcast.format == link.fixtureFingerprint.format || link.matchMethod == .currentEvent else { return false }
        if let sports = event.sportsFixture {
            guard event.cricketFixture == nil, sports.verified, sports.fixtureID == request.matchID,
                  sports.eventKind == .match, [.scheduled, .live].contains(sports.status),
                  (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(sports.identityReceipt)),
                  sports.squad == link.fixtureFingerprint.squad,
                  link.fixtureFingerprint.format == nil, link.fixtureFingerprint.day == nil,
                  link.fixtureFingerprint.matchOrdinal == nil, link.fixtureFingerprint.end == nil else { return false }
        } else if let cricket = event.cricketFixture {
            guard cricket.verified, CricketFixtureCatalog.fixtureIDPrefix + cricket.fixtureID == request.matchID,
                  [.scheduled, .live].contains(cricket.status),
                  (-300...CricketFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(cricket.observedAt)),
                  cricket.format == link.fixtureFingerprint.format, link.fixtureFingerprint.squad == nil else { return false }
            if cricket.format == .test {
                if link.matchMethod == .exact, broadcast.kind == .event, broadcast.day == nil {
                    // A whole-Test listing uses its explicit original kickoff.
                    // Optional daily score context cannot be a prerequisite for
                    // that exact identity or turn it into a daily programme.
                    let ordinals = [broadcast.matchOrdinal, link.fixtureFingerprint.matchOrdinal,
                                    cricket.context?.matchOrdinal].compactMap { $0 }
                    guard Set(ordinals).count <= 1 else { return false }
                } else {
                    guard let context = cricket.context,
                          (-300...CricketMatchContextPolicy.freshness).contains(now.timeIntervalSince(cricket.observedAt)),
                          let day = context.day, let ordinal = context.matchOrdinal,
                          let end = context.matchEndsAt.flatMap(BroadcastRegistrySnapshot.date),
                          day == link.fixtureFingerprint.day, ordinal == link.fixtureFingerprint.matchOrdinal,
                          end == link.fixtureFingerprint.end else { return false }
                }
             } else {
                guard link.fixtureFingerprint.day == nil, link.fixtureFingerprint.end == nil else { return false }
                if let ordinal = link.fixtureFingerprint.matchOrdinal, cricket.matchOrdinal != ordinal { return false }
                if let ordinal = broadcast.matchOrdinal, let official = cricket.matchOrdinal, ordinal != official { return false }
            }
        } else { return false }
        switch link.matchMethod {
        case .currentEvent:
            guard BroadcastRegistrySnapshot.isCurrentCricketListing(broadcast), broadcast.issues.isEmpty,
                  let cricket = event.cricketFixture, cricket.status == .live,
                  cricket.format == .odi || cricket.format == .t20,
                  (-300...600).contains(now.timeIntervalSince(cricket.observedAt)),
                  now >= start, now.timeIntervalSince(start) <= (cricket.format == .odi ? 12 : 6) * 3600,
                  cricket.observedAt.addingTimeInterval(600) > now else { return false }
            // The cloud and device may observe this same official fixture on
            // different refreshes. Each receipt must be current independently;
            // comparing a newer link's expiry against an older device receipt
            // wrongly removes Watch while both are fresh. The adapter bounds
            // its session to the earlier of those independent expiries.
            return true
        case .exact:
            guard broadcast.format != .test || broadcast.kind == .event else { return false }
            guard broadcast.day == nil, let sourceStart = broadcast.start else { return false }
            if link.startRelation == "early-coverage" {
                let lead = start.timeIntervalSince(sourceStart)
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = TimeZone(secondsFromGMT: 0)!
                guard broadcast.sport == "cricket", broadcast.kind == .event,
                      broadcast.format == .odi || broadcast.format == .t20,
                      lead > 15 * 60, lead <= 60 * 60,
                      utc.isDate(sourceStart, inSameDayAs: start),
                      broadcast.matchOrdinal == nil || broadcast.matchOrdinal == link.fixtureFingerprint.matchOrdinal else { return false }
            } else if abs(sourceStart.timeIntervalSince(start)) > 15 * 60 { return false }
            return broadcast.matchOrdinal == nil || link.fixtureFingerprint.matchOrdinal == nil
                || broadcast.matchOrdinal == link.fixtureFingerprint.matchOrdinal
        case .testPeriod:
            guard broadcast.format == .test, let day = broadcast.day, let ordinal = broadcast.matchOrdinal,
                  day == link.fixtureFingerprint.day, ordinal == link.fixtureFingerprint.matchOrdinal,
                  let end = link.fixtureFingerprint.end, let sourceStart = broadcast.start,
                  sourceStart >= start, sourceStart < end, now >= sourceStart, now < end else { return false }
            return true
        case .programme:
            guard broadcast.kind == .programme, broadcast.channelID != nil,
                  let programmeStart = broadcast.start, let programmeEnd = broadcast.end,
                  programmeStart <= now, now < programmeEnd, broadcast.expiresAt <= programmeEnd,
                  (-300...BroadcastRegistrySnapshot.programmeLifetime).contains(now.timeIntervalSince(broadcast.observedAt)) else { return false }
            if broadcast.format == .test {
                guard let end = link.fixtureFingerprint.end,
                      let day = broadcast.day, day == link.fixtureFingerprint.day,
                      let ordinal = broadcast.matchOrdinal, ordinal == link.fixtureFingerprint.matchOrdinal,
                      programmeStart >= start, programmeStart < end, programmeEnd <= end else { return false }
                return true
            }
            // Fox's Abu Dhabi T10 listing has no ordinal; the unique current
            // ESPN T10 fixture of the same pair and competition owns it.
            let foxT10 = ReviewedTVPlaylistClient.isFoxProgramme(broadcast) && broadcast.competitionID == "abu-dhabi-t10"
                && broadcast.format == .t10 && link.fixtureFingerprint.competitionID == "abu-dhabi-t10"
                && event.id.range(of: #"^cricket-fixture:espn-cricket:\d+$"#, options: .regularExpression) != nil
            guard let cricket = event.cricketFixture,
                  cricket.format == .odi || cricket.format == .t20 || foxT10 && cricket.format == .t10,
                  (-300...600).contains(now.timeIntervalSince(cricket.observedAt)) else { return false }
            let reviewedDomestic = foxT10 || (ReviewedTVPlaylistClient.isFoxProgramme(broadcast) || broadcast.providerCode == "reviewedtv"
                && broadcast.channelID == CricketBroadcastChannel.willow.canonicalID
                && broadcast.streamID == "reviewed-tv:willow-main"
                && ReviewedTVPlaylistClient.isProgrammeID(broadcast.providerEventID))
                && broadcast.competitionID == "wbbl" && link.fixtureFingerprint.competitionID == "wbbl"
                && event.id.range(of: #"^cricket-fixture:ca:\d+$"#, options: .regularExpression) != nil
                && cricket.format == .t20 && broadcast.squad?.gender == .women && broadcast.squad?.ageGroup == "senior"
                && broadcast.participants.allSatisfy { $0.hasSuffix(" Women") } && broadcast.matchOrdinal == nil
            if !reviewedDomestic {
                guard let ordinal = cricket.matchOrdinal, broadcast.matchOrdinal == ordinal,
                      link.fixtureFingerprint.matchOrdinal == ordinal else { return false }
            }
            let delta = programmeStart.timeIntervalSince(start)
            let limit: TimeInterval = (cricket.format == .odi ? 12 : cricket.format == .t10 ? 3 : 6) * 3600
            if cricket.status == .live {
                return now >= start && now.timeIntervalSince(start) <= limit && (-3600...limit).contains(delta)
            }
            return cricket.status == .scheduled && (-3600...0).contains(delta)
                && (0...3600).contains(start.timeIntervalSince(now))
        case .channelAssignment:
            guard broadcast.providerCode == ReviewedTVPlaylistClient.providerCode,
                  broadcast.kind == .event, ReviewedTVPlaylistClient.supportsScheduledSport(broadcast),
                  link.startRelation == "channel-coverage", broadcast.stationMarket == "UY",
                  let coverageStart = broadcast.start, broadcast.end == nil,
                  broadcast.competitionID == link.fixtureFingerprint.competitionID,
                  broadcast.squad == link.fixtureFingerprint.squad,
                  (-300...BroadcastRegistrySnapshot.programmeLifetime).contains(now.timeIntervalSince(broadcast.observedAt)) else { return false }
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let lead = start.timeIntervalSince(coverageStart)
            return (0...60 * 60).contains(lead) && utc.isDate(coverageStart, inSameDayAs: start)
        }
    }
}

/// One foreground-owned metadata refresh. Source choices remain local opt-ins;
/// a failed/cancelled read never renews cached association/source receipts.
@MainActor
@Observable
final class BroadcastRegistryClient {
    static let shared = BroadcastRegistryClient()
    static let refreshInterval: TimeInterval = 300
    private static let cacheKey = "Fotty.BroadcastRegistry.accepted.v1"
    private(set) var snapshot: BroadcastRegistrySnapshot?
    private(set) var isRefreshing = false
    enum RefreshFailure: String, Equatable, Sendable { case network, response, validation, rejectedSnapshot, joinTimeout }
    private(set) var lastRefreshFailure: RefreshFailure?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var preparedIndex: BroadcastRegistrySnapshot.LookupIndex?
    @ObservationIgnored private var pendingCacheData: Data?
    @ObservationIgnored private var didLoadCache = false
    @ObservationIgnored private var refreshGeneration: UUID?
    @ObservationIgnored private var lastPlaybackRefreshAttempt: Date?
    @ObservationIgnored private var refreshWaiters: [UUID: RefreshWaiter] = [:]

    private struct RefreshWaiter {
        let continuation: CheckedContinuation<Bool, Never>
        let timeout: Task<Void, Never>
    }
    private enum PreparationFailure: Error { case rejectedSnapshot }

    private struct Prepared: Sendable {
        let snapshot: BroadcastRegistrySnapshot
        let index: BroadcastRegistrySnapshot.LookupIndex
        let encoded: Data?
    }

    init(defaults: UserDefaults = .standard,
         fetch: ((URLRequest) async throws -> (Data, URLResponse))? = nil) {
        self.defaults = defaults
        pendingCacheData = defaults.data(forKey: Self.cacheKey)
        if let fetch { self.fetch = fetch }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCache = nil
            configuration.httpShouldSetCookies = false; configuration.waitsForConnectivity = false
            let transport = FottyBoundedHTTPClient(configuration: configuration)
            self.fetch = { request in
                let result = try await transport.fetch(request, maximumBytes: BroadcastRegistrySnapshot.maximumBytes,
                    deadline: min(20, request.timeoutInterval), acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
                return (result.data, result.http)
            }
        }
    }

    func cachedSnapshot(at now: Date = .init()) -> BroadcastRegistrySnapshot? {
        if let snapshot, (-300...BroadcastRegistrySnapshot.retention).contains(now.timeIntervalSince(snapshot.generatedAt)) { return snapshot }
        return nil
    }

    func lookup(for request: StreamPlaybackRequest, enabledProviderCodes: Set<String>, at now: Date = .init()) -> [BroadcastRegistryMatch] {
        // Keep the observation dependency even though the immutable index is an
        // ignored implementation detail. Reads do not decode or start requests.
        guard cachedSnapshot(at: now) != nil else { return [] }
        return preparedIndex?.lookup(for: request, enabledProviderCodes: enabledProviderCodes, at: now) ?? []
    }

    /// Prime persisted metadata once, using the same cancellable utility owner
    /// as a network refresh. The synchronous getter above only reads published
    /// values, including on repeated lazy-row renders.
    func loadCached(at now: Date = .init()) async -> BroadcastRegistrySnapshot? {
        guard !isRefreshing, !Task.isCancelled, now.timeIntervalSince1970.isFinite else { return cachedSnapshot(at: now) }
        let generation = UUID(); refreshGeneration = generation; isRefreshing = true
        defer { finishRefresh(generation: generation) }
        await primeCache(at: now, generation: generation)
        return cachedSnapshot(at: now)
    }

    func refresh(at now: Date = .init(), force: Bool = false) async -> BroadcastRegistrySnapshot? {
        // The observed 1.6 MiB snapshot can take nearly 12s. One shared 20s owner
        // avoids making a foreground join inherit a shorter background timeout.
        await performRefresh(at: now, force: force, timeout: 20)
    }

    /// A foreground TV lane can recover an expired/missing assignment without
    /// serializing other providers behind registry I/O. Join an existing owner;
    /// otherwise permit one bounded refresh, with a finite retry reservation.
    func refreshForPlayback(at now: Date = .init(), maximumWait: Duration = .seconds(20)) async -> BroadcastRegistrySnapshot? {
        guard now.timeIntervalSince1970.isFinite, !Task.isCancelled else { return nil }
        let started = ContinuousClock.now
        if isRefreshing {
            let joined = await waitForRefresh(maximumWait: min(.seconds(20), max(.zero, maximumWait)))
            guard !Task.isCancelled else { return nil }
            if !joined {
                recordRefreshFailure(.joinTimeout)
                return cachedSnapshot(at: Self.currentTime(from: now, started: started))
            }
            // loadCached also owns isRefreshing. Joining its decode alone must
            // not masquerade as the one network check this lane still needs.
            if lastAttempt != nil {
                return cachedSnapshot(at: Self.currentTime(from: now, started: started))
            }
        }
        if let lastPlaybackRefreshAttempt,
           (0..<30).contains(now.timeIntervalSince(lastPlaybackRefreshAttempt)) {
            return cachedSnapshot(at: now)
        }
        lastPlaybackRefreshAttempt = now
        defer { if Task.isCancelled { lastPlaybackRefreshAttempt = nil } }
        return await performRefresh(at: now, force: true, timeout: 20)
    }

    private func performRefresh(at now: Date, force: Bool, timeout: TimeInterval) async -> BroadcastRegistrySnapshot? {
        guard now.timeIntervalSince1970.isFinite, !isRefreshing, !Task.isCancelled else { return cachedSnapshot(at: now) }
        let started = ContinuousClock.now
        let generation = UUID(); refreshGeneration = generation; isRefreshing = true
        defer { finishRefresh(generation: generation) }
        await primeCache(at: now, generation: generation)
        let cached = cachedSnapshot(at: now)
        guard !Task.isCancelled, refreshGeneration == generation,
              force || lastAttempt.map({ now.timeIntervalSince($0) >= Self.refreshInterval }) ?? true,
              let url = Config.footballProxyBaseURL?.appendingPathComponent("api/live/broadcasts"),
              Self.safeEndpoint(url) else { return cached }
        lastAttempt = now
        var failureStage = RefreshFailure.network
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            // Existing servers still deliver Willow; assignment-aware servers
            // opt into the extended projection without another network read.
            request.setValue("reviewedtv-programme-v1", forHTTPHeaderField: "X-Fotty-Broadcast-Capabilities")
            request.setValue("reviewedtv-programme-v2", forHTTPHeaderField: "X-Fotty-Broadcast-Assignments")
            request.setValue("current-listing-v1", forHTTPHeaderField: "X-Fotty-Cricket-Matching")
            request.setValue("fox-cricket-v1", forHTTPHeaderField: "X-Fotty-Fox-Programmes")
            request.setValue("reviewedtv-guide-v1", forHTTPHeaderField: "X-Fotty-TV-Guide")
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            failureStage = .response
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url == url, Self.safeEndpoint(url),
                  http.mimeType == "application/json", data.count <= BroadcastRegistrySnapshot.maximumBytes else { throw URLError(.badServerResponse) }
            failureStage = .validation
            let prepared = try await Self.prepare(data, at: Self.currentTime(from: now, started: started),
                cached: false, previous: cached, persist: true)
            try Task.checkCancellation()
            let completedAt = Self.currentTime(from: now, started: started)
            guard refreshGeneration == generation,
                  (-300...BroadcastRegistrySnapshot.retention).contains(completedAt.timeIntervalSince(prepared.snapshot.generatedAt)) else {
                return cachedSnapshot(at: completedAt)
            }
            snapshot = prepared.snapshot
            preparedIndex = prepared.index
            lastRefreshFailure = nil
            if let encoded = prepared.encoded { defaults.set(encoded, forKey: Self.cacheKey) }
            return prepared.snapshot
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                lastAttempt = nil
            } else {
                recordRefreshFailure(error is PreparationFailure ? .rejectedSnapshot : failureStage)
            }
            return cached
        }
    }

    private func waitForRefresh(maximumWait: Duration) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard isRefreshing, !Task.isCancelled else { continuation.resume(returning: !isRefreshing); return }
                let timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: maximumWait) } catch { return }
                    self?.finishWaiter(id, completed: false)
                }
                refreshWaiters[id] = RefreshWaiter(continuation: continuation, timeout: timeout)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishWaiter(id, completed: false) }
        }
    }

    private func finishWaiter(_ id: UUID, completed: Bool) {
        guard let waiter = refreshWaiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        waiter.continuation.resume(returning: completed)
    }

    private func finishRefresh(generation: UUID) {
        guard refreshGeneration == generation else { return }
        refreshGeneration = nil; isRefreshing = false
        for id in Array(refreshWaiters.keys) { finishWaiter(id, completed: true) }
    }

    private func recordRefreshFailure(_ failure: RefreshFailure) {
        lastRefreshFailure = failure
        let stage: String
        switch failure {
        case .network: stage = "network"
        case .response: stage = "response"
        case .validation, .rejectedSnapshot: stage = "validation"
        case .joinTimeout: stage = "join"
        }
        FottyQualityStore.shared.record(category: .playback, name: "broadcast_registry_refresh", outcome: .failure,
            details: ["mode": "source_discovery", "stage": stage,
                      "failure_kind": failure.rawValue])
    }

    private func primeCache(at now: Date, generation: UUID) async {
        guard !didLoadCache else { return }
        guard let data = pendingCacheData else { didLoadCache = true; return }
        let prepared = try? await Self.prepare(data, at: now, cached: true, previous: nil, persist: false)
        guard !Task.isCancelled, refreshGeneration == generation else { return }
        didLoadCache = true; pendingCacheData = nil
        if let prepared { snapshot = prepared.snapshot; preparedIndex = prepared.index }
    }

    private nonisolated static func prepare(_ data: Data, at now: Date, cached: Bool,
                                           previous: BroadcastRegistrySnapshot?, persist: Bool) async throws -> Prepared {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let candidate = try BroadcastRegistrySnapshot.validated(from: data, at: now, cached: cached)
            let accepted: BroadcastRegistrySnapshot
            do { accepted = try previous?.reconciling(candidate) ?? candidate }
            catch { throw PreparationFailure.rejectedSnapshot }
            try Task.checkCancellation()
            let index = BroadcastRegistrySnapshot.LookupIndex(snapshot: accepted)
            let encoded = persist ? try accepted.encoded() : nil
            try Task.checkCancellation()
            return Prepared(snapshot: accepted, index: index, encoded: encoded)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static func currentTime(from startDate: Date, started: ContinuousClock.Instant) -> Date {
        let elapsed = started.duration(to: ContinuousClock.now).components
        return startDate.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }

    private static func safeEndpoint(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443) && url.query == nil && url.fragment == nil
            && url.path.hasSuffix("/api/live/broadcasts")
    }
}

// Guide decoding is isolated from accepted match/source associations. A malformed
// sidecar cannot make valid Watch routes disappear on an otherwise valid snapshot.
extension BroadcastRegistrySnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(String.self, forKey: .revision)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        providers = try values.decode([Provider].self, forKey: .providers)
        broadcasts = try values.decode([Broadcast].self, forKey: .broadcasts)
        links = try values.decode([Link].self, forKey: .links)
        tvGuide = try? SportsTVGuideItem.decodeRows(from: values.superDecoder(forKey: .tvGuide), generatedAt: generatedAt)
    }
}
