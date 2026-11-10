import Foundation
import Observation
import CryptoKit

/// Finite reviewed stations, not inferred fixtures or arbitrary playlist imports.
struct SportsTVStation: Identifiable, Equatable, Sendable {
    let id: String
    let provider: String
    let title: String
    let language: CommentaryPreference

    static var all: [Self] {
        ReviewedTVPlaylistClient.channels.map {
            .init(id: $0.channelID, provider: $0.providerName, title: $0.displayName,
                  language: $0.commentaryLanguage)
        } + [.init(id: CricketBroadcastChannel.foxCricket.canonicalID, provider: "CS-Fox",
                   title: CricketBroadcastChannel.foxCricket.title, language: .english),
             .init(id: "sports-channel:sky-sports-main-event", provider: "CS-SkyMain", title: "Sky Sports Main Event", language: .english)]
    }
    var cricketChannel: CricketBroadcastChannel? {
        CricketBroadcastChannel.allCases.first { $0.canonicalID == id && $0.title == title }
    }
    var isCricket: Bool { cricketChannel != nil || ReviewedTVPlaylistClient.channel(forChannelID: id)?.sports == ["cricket"] }
    static var configuredOriginCount: Int { Set(ReviewedTVPlaylistClient.channels.flatMap { $0.allowedDeliveryHosts }).count }
    static func station(provider: String) -> Self? { all.first { $0.provider == provider } }
    static func station(id: String) -> Self? { all.first { $0.id == id } }

    static func identifying(_ request: StreamPlaybackRequest) -> Self? {
        guard let station = station(id: request.matchID), station.cricketChannel == nil,
              request.category == "other", request.kickoffDate == nil, request.registryMatch == nil,
              request.displayTitle == station.title, request.homeTeam == station.title,
              request.awayTeam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let event = request.preferredEvent {
            guard identifies(event), event.id == station.id else { return nil }
        }
        return station
    }
    static func identifies(_ event: EventReference) -> Bool {
        guard let station = station(id: event.id), station.cricketChannel == nil else { return false }
        return event.category == "other" && event.title == station.title && event.date == nil
            && event.teams == nil && event.competitionID == nil && event.cricketFixture == nil
            && event.sportsFixture == nil && !event.hasCatalogIdentityConflict
    }
    @MainActor static func canResolve(_ event: EventReference, discoveryIndex: FixtureStreamDiscoveryIndex? = nil) -> Bool {
        guard identifies(event) else { return false }
        let enabled = (discoveryIndex ?? .shared).enabledProviderCodes
        return (enabled.contains("reviewedtv") && ReviewedTVPlaylistClient.channel(forChannelID: event.id) != nil)
            || (enabled.contains("communitysports") && CommunitySportsAddonClient.supportsSportsTVChannel(.init(event: event)))
    }
    @MainActor var event: EventReference {
        if let cricketChannel { return CricketChannelCatalog.event(for: cricketChannel, in: []) }
        return .init(id: id, title: title, category: "other", date: nil, poster: nil,
                     popular: false, teams: nil)
    }
}

enum CommentaryPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case any, english, spanish
    static let storageKey = "sports.playback.commentary.v1"
    var id: String { rawValue }
    var title: String { switch self { case .any: "Any language"; case .english: "English"; case .spanish: "Spanish" } }
    static func saved(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .english
    }
    func preferenceRank(for known: Self?) -> Int {
        guard self != .any else { return 0 }
        if known == self { return 0 }
        return known == nil || known == .any ? 1 : 2
    }
}

extension SportsTVStation {
    /// The TV tab and Home's "On air now" share this Watch decision.
    @MainActor static func canWatchNow(_ station: SportsTVStation,
                                       discoveryIndex: FixtureStreamDiscoveryIndex? = nil) -> Bool {
        let index = discoveryIndex ?? .shared
        if let channel = station.cricketChannel {
            return (channel == .willow && index.enabledProviderCodes.contains(ReviewedTVPlaylistClient.providerCode))
                || MatchStartPolicy(event: station.event, discoveryIndex: index).canAttemptPlayback
        }
        return SportsTVStation.canResolve(station.event, discoveryIndex: index)
    }
}

/// Home's "On air now": channels that can open right now, in the TV tab's own
/// order (favourites, recently watched, then cricket and other channels).
/// A programme line appears only when the guide currently confirms it.
enum HomeOnAirPolicy {
    struct Entry: Identifiable, Equatable {
        let station: SportsTVStation
        let programme: String?
        var id: String { station.id }
    }

    @MainActor static func entries(library: SportsTVLibrary, commentary: CommentaryPreference,
                                   snapshot: BroadcastRegistrySnapshot?, sport: String?, at now: Date, limit: Int,
                                   canWatch: (SportsTVStation) -> Bool) -> [Entry] {
        guard limit > 0 else { return [] }
        let ordered = library.sections(commentary: commentary).flatMap(\.stations)
        var seen = Set<String>(), result: [Entry] = []
        for station in ordered where seen.insert(station.id).inserted {
            guard sport.map({ $0 == "cricket" ? station.isCricket : false }) ?? true, canWatch(station) else { continue }
            let current = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first { $0.isOnNow(at: now) }
            result.append(.init(station: station, programme: current?.title))
            if result.count == limit { break }
        }
        return result
    }
}

enum SportsTVGuidePolicy {
    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let start: Date
        let end: Date?
        let sport: String
        func isOnNow(at now: Date) -> Bool { end.map { start <= now && now < $0 } ?? false }
        func progress(at now: Date) -> Double? {
            guard isOnNow(at: now), let end, end > start else { return nil }
            return now.timeIntervalSince(start) / end.timeIntervalSince(start)
        }
    }
    static func entries(for station: SportsTVStation, snapshot: BroadcastRegistrySnapshot?, at now: Date) -> [Entry] {
        guard let snapshot, now.timeIntervalSince1970.isFinite,
              (-300...BroadcastRegistrySnapshot.retention).contains(now.timeIntervalSince(snapshot.generatedAt)) else { return [] }
        let scheduled = (snapshot.tvGuide ?? []).filter { $0.channelID == station.id && $0.expiresAt > now
            && $0.start >= now && $0.start <= now.addingTimeInterval(7 * 86400) }
            .map { Entry(id: $0.id, title: $0.title, start: $0.start, end: nil, sport: $0.sport) }
        // Upcoming start-only schedules retain their own observed expiry during a
        // refresh outage. Current programme claims still need a fresh registry.
        guard now.timeIntervalSince(snapshot.generatedAt) <= BroadcastRegistrySnapshot.networkFreshness else {
            return scheduled.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        }
        let linked: [Entry] = snapshot.broadcasts.filter {
            $0.providerCode == "reviewedtv" && $0.channelID == station.id && $0.verification == .dated
                && $0.issues.isEmpty && $0.observedAt <= now.addingTimeInterval(30) && $0.expiresAt > now
                && $0.start != nil && ($0.end.map { $0 > now } ?? ($0.start! >= now))
        }.compactMap {
            guard let start = $0.start, start <= now.addingTimeInterval(7 * 86400) else { return nil }
            // A fresh guide can still describe a match that has finished or
            // belongs to a different station edition. The published interval
            // alone must not turn that claim into "On now". Use the registry's
            // independently corroborated fixture association, retaining each
            // original expiry. Start-only future schedules are unaffected.
            if $0.kind == .programme, start <= now {
                guard hasCurrentProgrammeAuthority($0, snapshot: snapshot, at: now) else { return nil }
            }
            return Entry(id: $0.id, title: $0.title, start: start, end: $0.end, sport: $0.sport)
        }
        // The detailed guide takes precedence over a duplicated football listing.
        let remaining = linked.filter { row in !scheduled.contains { $0.start == row.start && $0.title.contains(row.title) } }
        return (scheduled + remaining).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    private static func hasCurrentProgrammeAuthority(_ programme: BroadcastRegistrySnapshot.Broadcast,
                                                     snapshot: BroadcastRegistrySnapshot, at now: Date) -> Bool {
        guard (-300...BroadcastRegistrySnapshot.programmeLifetime).contains(now.timeIntervalSince(programme.observedAt)),
              let provider = snapshot.providers.first(where: {
                  $0.providerCode == programme.providerCode && $0.scope == programme.scope
              }), let observed = provider.observedAt,
              (-300...BroadcastRegistrySnapshot.sourceLifetime).contains(now.timeIntervalSince(observed)),
              let providerExpiry = provider.expiresAt, providerExpiry > now else { return false }
        let retained = provider.status == .failed && provider.lastSuccessAt == observed
        guard [.available, .partial].contains(provider.status) || retained else { return false }
        let current = snapshot.links.filter {
            $0.broadcastID == programme.id && $0.providerCode == programme.providerCode && $0.expiresAt > now
        }
        guard !current.contains(where: { $0.state == .conflicting }),
              Set(current.filter { $0.state == .listed && $0.matchMethod == .programme && $0.reason == nil }
                .map(\.fixtureID)).count == 1 else { return false }
        return true
    }
}

/// Local station IDs only; no stream locations, tokens, account sync or telemetry.
@Observable @MainActor
final class SportsTVLibrary {
    static let shared = SportsTVLibrary()
    static let favouritesKey = "sports.tv.favourites.v1"
    static let recentKey = "sports.tv.recent.v1"
    private let defaults: UserDefaults
    private(set) var favourites: [String]
    private(set) var recent: [String]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func accepted(_ key: String, limit: Int) -> [String] {
            var seen = Set<String>()
            return (defaults.stringArray(forKey: key) ?? []).filter { SportsTVStation.station(id: $0) != nil && seen.insert($0).inserted }.prefix(limit).map { $0 }
        }
        favourites = accepted(Self.favouritesKey, limit: SportsTVStation.all.count); recent = accepted(Self.recentKey, limit: 6)
    }
    func toggleFavourite(_ id: String) {
        guard SportsTVStation.station(id: id) != nil else { return }
        if favourites.contains(id) { favourites.removeAll { $0 == id } } else { favourites.append(id) }
        defaults.set(favourites, forKey: Self.favouritesKey)
    }
    func recordPlayed(_ id: String) {
        guard SportsTVStation.station(id: id) != nil else { return }
        recent = [id] + recent.filter { $0 != id }; recent = Array(recent.prefix(6))
        defaults.set(recent, forKey: Self.recentKey)
    }
    func clearRecent() {
        recent = []
        defaults.removeObject(forKey: Self.recentKey)
    }
    struct Section: Identifiable {
        let id: String
        let stations: [SportsTVStation]
    }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All channels", favourites = "Favourites", english = "English"
        var id: String { rawValue }
    }

    func sections(commentary: CommentaryPreference, filter: Filter, query: String,
                  snapshot: BroadcastRegistrySnapshot?, at now: Date) -> [Section] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return sections(commentary: commentary).compactMap { section in
            let stations = section.stations.filter { station in
                guard filter != .favourites || favourites.contains(station.id),
                      filter != .english || station.language == .english else { return false }
                let programmes = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).map(\.title)
                let searchable = ([station.title, station.language.title] + programmes).joined(separator: " ")
                return words.allSatisfy { searchable.localizedStandardContains($0) }
            }
            return stations.isEmpty ? nil : Section(id: section.id, stations: stations)
        }
    }

    func sections(commentary: CommentaryPreference) -> [Section] {
        let all = orderedStations
        let pinned = all.filter { favourites.contains($0.id) }
        let watched = recent.compactMap(SportsTVStation.station(id:)).filter { !favourites.contains($0.id) }
        let rest = all.filter { !favourites.contains($0.id) && !recent.contains($0.id) }
        let cricketOrder = [CricketBroadcastChannel.willow.canonicalID, CricketBroadcastChannel.foxCricket.canonicalID,
                            "sports-channel:sky-sports-cricket"]
        let cricket = rest.filter(\.isCricket).sorted {
            (cricketOrder.firstIndex(of: $0.id) ?? Int.max) < (cricketOrder.firstIndex(of: $1.id) ?? Int.max)
        }
        let other = rest.filter { !$0.isCricket }
        let language: [Section] = commentary == .any ? [.init(id: "Channels", stations: other)]
            : [.init(id: commentary.title + " channels", stations: other.filter { $0.language == commentary }),
               .init(id: "More channels", stations: other.filter { $0.language != commentary })]
        return ([.init(id: "Favourites", stations: pinned), .init(id: "Recently watched", stations: watched),
                 .init(id: "Cricket channels", stations: cricket)] + language).filter { !$0.stations.isEmpty }
    }
    var orderedStations: [SportsTVStation] {
        let order = favourites + recent.filter { !favourites.contains($0) }
        return SportsTVStation.all.sorted {
            let a = order.firstIndex(of: $0.id) ?? Int.max, b = order.firstIndex(of: $1.id) ?? Int.max
            return a == b ? $0.provider.localizedStandardCompare($1.provider) == .orderedAscending : a < b
        }
    }
}

/// Different hosts are distinct observed origins, never proof of independent suppliers.
enum SourceDeliveryDiversity {
    static func origin(for source: StreamSource) -> String? {
        let contract = source.playbackContract ?? .describing(url: source.url, provider: source.provider, headers: source.headers)
        guard contract.endpoint == .directMedia, LocalStreamProxyPolicy.allowsDestination(source.url), source.url.scheme?.lowercased() == "https",
              let host = source.url.host?.lowercased(), !host.isEmpty,
              !["localhost", "127.0.0.1", "::1"].contains(host) else { return nil }
        return host + ":" + String(source.url.port ?? 443)
    }
    static func distinctOriginCount(_ sessions: [StreamSession]) -> Int {
        Set(sessions.compactMap { origin(for: $0.legacySource) }).count
    }
    static func prioritisingDifferentOrigin(_ sessions: [StreamSession], after source: StreamSource?) -> [StreamSession] {
        guard let source, let origin = origin(for: source) else { return sessions }
        return sessions.enumerated().sorted {
            func rank(_ session: StreamSession) -> Int {
                guard let candidate = Self.origin(for: session.legacySource) else { return 1 }
                return candidate == origin ? 1 : 0
            }
            let a = rank($0.element), b = rank($1.element)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    static func localDeliveryKey(for source: StreamSource) -> String {
        let value = [source.provider.lowercased(), source.url.host?.lowercased() ?? "", source.url.path].joined(separator: "|")
        return "continuity|" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Positive continuity observations on this device only. Not an uptime ratio,
/// a provider ban, or qualification of the programme being shown.
enum SinglePlaybackContinuityStore {
    struct Sample: Codable { let observedAt: Date }
    static let storageKey = "sports.playback.continuity.v1"
    private static let queue = DispatchQueue(label: "com.fotty.singlePlaybackContinuity")
    static func qualifies(elapsed: Double, mediaAdvance: Double, stalls: Int) -> Bool {
        elapsed.isFinite && mediaAdvance.isFinite && elapsed >= 90 && elapsed <= 120
            && mediaAdvance >= max(85, elapsed * 0.94) && mediaAdvance <= elapsed * 1.15 && stalls == 0
    }
    static func record(_ source: StreamSource, elapsed: Double, mediaAdvance: Double, stalls: Int,
                       at now: Date = Date(), defaults: UserDefaults = .standard) {
        guard qualifies(elapsed: elapsed, mediaAdvance: mediaAdvance, stalls: stalls), now.timeIntervalSince1970.isFinite else { return }
        queue.sync {
            var samples = accepted(defaults, at: now)
            samples[SourceDeliveryDiversity.localDeliveryKey(for: source)] = .init(observedAt: now)
            let retained = samples.sorted { $0.value.observedAt > $1.value.observedAt }.prefix(64)
            if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }
    static func hasRecentHold(_ source: StreamSource, at now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        queue.sync { accepted(defaults, at: now)[SourceDeliveryDiversity.localDeliveryKey(for: source)] != nil }
    }
    private static func accepted(_ defaults: UserDefaults, at now: Date) -> [String: Sample] {
        guard let data = defaults.data(forKey: storageKey), data.count <= 32768,
              let decoded = try? JSONDecoder().decode([String: Sample].self, from: data), decoded.count <= 64 else { return [:] }
        return decoded.filter { $0.key.range(of: "^continuity\\|[a-f0-9]{64}$", options: .regularExpression) != nil
            && (0...86400).contains(now.timeIntervalSince($0.value.observedAt)) }
    }
}

/// Optional local privacy during one retained single-player session. No score
/// authority or global notification preference is rewritten.
@Observable @MainActor
final class WatchingSpoilerProtection {
    static let shared = WatchingSpoilerProtection()
    static let preferenceKey = "sports.playback.spoilerSafe.v1"
    private(set) var activeEvent: EventReference?
    var enabled = UserDefaults.standard.bool(forKey: WatchingSpoilerProtection.preferenceKey) {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.preferenceKey) }
    }
    func setActiveEvent(_ event: EventReference?) { activeEvent = event }
    func protects(_ event: EventReference, defaults: UserDefaults? = nil) -> Bool {
        (defaults?.bool(forKey: Self.preferenceKey) ?? enabled) && activeEvent?.id == event.id
    }
    func suppressesGoal(home: String, away: String, kickoff: Date?, defaults: UserDefaults? = nil) -> Bool {
        guard (defaults?.bool(forKey: Self.preferenceKey) ?? enabled), let event = activeEvent,
              event.normalizedCategory == "football", let start = event.kickoffDate, let kickoff,
              abs(kickoff.timeIntervalSince(start)) <= 15 * 60 else { return false }
        return FootballCompetitionCatalog.canonicalTeamKey(home) == FootballCompetitionCatalog.canonicalTeamKey(event.homeName)
            && FootballCompetitionCatalog.canonicalTeamKey(away) == FootballCompetitionCatalog.canonicalTeamKey(event.awayName)
    }
}

struct SportsTVGuideItem: Codable, Equatable, Sendable {
    let id: String
    let channelID: String
    let market: String
    let sport: String
    let title: String
    let start: Date
    let observedAt: Date
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, channelID, market, sport, title, start, observedAt, expiresAt
    }
    private struct WireKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private struct Slot: Hashable {
        let channelID: String
        let start: Date
    }

    /// Reserve every readable identity before discarding an invalid row. A
    /// broken sibling must neither hide unrelated guide entries nor authorize
    /// an arbitrary winner for the same station slot.
    static func decodeRows(from decoder: Decoder, generatedAt: Date) throws -> [Self]? {
        var container = try decoder.unkeyedContainer()
        guard (container.count ?? 0) <= 300 else { return nil }
        var rows: [Self] = []
        let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var seenIDs = Set<String>(), conflictingIDs = Set<String>()
        var seenSlots = Set<Slot>(), conflictingSlots = Set<Slot>()
        while !container.isAtEnd {
            guard container.currentIndex < 300 else { return nil }
            let element = try container.superDecoder()
            guard let values = try? element.container(keyedBy: CodingKeys.self) else { continue }
            if let id = try? values.decode(String.self, forKey: .id), !seenIDs.insert(id).inserted {
                conflictingIDs.insert(id)
            }
            if let channelID = try? values.decode(String.self, forKey: .channelID),
               let text = try? values.decode(String.self, forKey: .start),
               text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil,
               let start = CricketFixtureCatalog.date(text) {
                let slot = Slot(channelID: channelID, start: start)
                if !seenSlots.insert(slot).inserted { conflictingSlots.insert(slot) }
            }
            guard let raw = try? element.container(keyedBy: WireKey.self),
                  Set(raw.allKeys.map(\.stringValue)) == wireKeys,
                  let row = try? Self(from: element), row.isValid(generatedAt: generatedAt),
                  try values.decode(String.self, forKey: .start) == utcFormatter.string(from: row.start),
                  try values.decode(String.self, forKey: .observedAt) == utcFormatter.string(from: row.observedAt),
                  try values.decode(String.self, forKey: .expiresAt) == utcFormatter.string(from: row.expiresAt)
            else { continue }
            rows.append(row)
        }
        if container.currentIndex > 0 && rows.isEmpty { return nil }
        return rows.filter { !conflictingIDs.contains($0.id) && !conflictingSlots.contains(Slot(channelID: $0.channelID, start: $0.start)) }
    }

    func isValid(generatedAt: Date) -> Bool {
        let sports: Set<String> = ["football", "baseball", "basketball", "american-football", "rugby", "tennis", "hockey"]
        return id.range(of: "^tv-guide:[a-f0-9]{64}$", options: .regularExpression) != nil
            && SportsTVStation.station(id: channelID)?.provider != "TV1"
            && ReviewedTVPlaylistClient.channel(forChannelID: channelID)?.markets.contains("UY") == true && market == "UY"
            && sports.contains(sport) && !title.isEmpty && title.utf8.count <= 800
            && title.utf16.count <= 400 && !title.contains("://") && !title.contains("<") && !title.contains(">")
            && title == title.trimmingCharacters(in: .whitespacesAndNewlines)
            && title.rangeOfCharacter(from: .controlCharacters) == nil
            && title.range(of: "[\u{061c}\u{200e}\u{200f}\u{202a}-\u{202e}\u{2066}-\u{2069}]", options: .regularExpression) == nil
            && observedAt <= generatedAt.addingTimeInterval(300) && expiresAt > observedAt
            && expiresAt.timeIntervalSince(observedAt) <= 4 * 3600
            && (-8 * 86400...9 * 86400).contains(start.timeIntervalSince(observedAt))
    }
}

/// Accepted priority fixtures and fresh enabled-source listings. This does not
/// call a listing playable, or two source families independent suppliers.
@MainActor
struct PriorityBroadcastCoverage {
    let fixtureCount: Int
    let withListings: Int
    let withMultipleFamilies: Int
    let missingTitles: [String]
    static func evaluate(events: [EventReference], snapshot: BroadcastRegistrySnapshot?, enabled: Set<String>, at now: Date) -> Self {
        var seen = Set<String>()
        let fixtures = events.filter { event in
            guard !event.isBroadcastChannel, !event.hasCatalogIdentityConflict,
                  event.sportsFixture?.verified == true || event.cricketFixture?.verified == true,
                  let start = event.kickoffDate, (-6 * 3600...24 * 3600).contains(start.timeIntervalSince(now)),
                  !MatchStartPolicy(event: event, now: now).isStopped, seen.insert(event.id).inserted else { return false }
            return event.normalizedCategory == "cricket" || ["premier-league", "champions-league"].contains(event.competitionID ?? "")
        }
        var listed = 0, multiple = 0, missing: [String] = []
        for event in fixtures {
            let matches = snapshot?.lookup(for: StreamPlaybackRequest(event: event), enabledProviderCodes: enabled, at: now) ?? []
            let families = Set(matches.map { $0.broadcast.providerCode })
            if !families.isEmpty { listed += 1 } else { missing.append(event.displayTitle) }
            if families.count > 1 { multiple += 1 }
        }
        return .init(fixtureCount: fixtures.count, withListings: listed, withMultipleFamilies: multiple, missingTitles: Array(missing.prefix(5)))
    }
}
