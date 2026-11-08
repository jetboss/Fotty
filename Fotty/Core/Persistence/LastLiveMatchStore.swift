import Foundation
import Observation

/// One optional local return identity, not a player, transport cache or history.
/// This key is intentionally absent from Fotty's sync and explicit backup payloads.
struct LastLiveMatchRecord: Codable, Equatable, Sendable {
    static let lifetime: TimeInterval = 36 * 60 * 60
    static let maximumPayloadBytes = 8 * 1_024

    enum Kind: String, Codable, Sendable { case match, event }
    struct SportsIdentity: Codable, Equatable, Sendable {
        let eventKind: SportsFixtureCatalog.EventKind
        let participants: [SportsFixtureCatalog.Participant]
        let squad: SportsFixtureCatalog.Squad
    }

    let version: Int
    let eventID: String
    let title: String
    let category: String
    let homeName: String
    let awayName: String
    let kickoff: Date
    let competitionID: String?
    let canonicalFixtureID: String?
    let kind: Kind
    let squadQualifiers: [String]
    let sportsIdentity: SportsIdentity?
    let cricketFormat: CricketFixtureCatalog.Format?
    let cricketLabel: String?
    let confirmedAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, eventID, title, category, homeName, awayName, kickoff,
             competitionID, canonicalFixtureID, kind, squadQualifiers,
             sportsIdentity, cricketFormat, cricketLabel, confirmedAt
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        guard all.allKeys.allSatisfy({ Set(CodingKeys.allCases.map(\.rawValue)).contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown local identity field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        eventID = try values.decode(String.self, forKey: .eventID)
        title = try values.decode(String.self, forKey: .title)
        category = try values.decode(String.self, forKey: .category)
        homeName = try values.decode(String.self, forKey: .homeName)
        awayName = try values.decode(String.self, forKey: .awayName)
        kickoff = try values.decode(Date.self, forKey: .kickoff)
        competitionID = try values.decodeIfPresent(String.self, forKey: .competitionID)
        canonicalFixtureID = try values.decodeIfPresent(String.self, forKey: .canonicalFixtureID)
        kind = try values.decode(Kind.self, forKey: .kind)
        squadQualifiers = try values.decode([String].self, forKey: .squadQualifiers)
        sportsIdentity = try values.decodeIfPresent(SportsIdentity.self, forKey: .sportsIdentity)
        cricketFormat = try values.decodeIfPresent(CricketFixtureCatalog.Format.self, forKey: .cricketFormat)
        cricketLabel = try values.decodeIfPresent(String.self, forKey: .cricketLabel)
        confirmedAt = try values.decode(Date.self, forKey: .confirmedAt)
    }

    @MainActor
    private init(event: EventReference, kickoff: Date, now: Date) {
        version = 1
        eventID = event.id
        title = event.displayTitle
        category = event.normalizedCategory
        homeName = event.homeName
        awayName = event.awayName
        self.kickoff = kickoff
        competitionID = event.competitionID ?? event.cricketFixture?.competitionID
        canonicalFixtureID = event.sportsFixture?.fixtureID ?? event.cricketFixture?.fixtureID
        kind = event.sportsFixture.map { $0.eventKind != .match } == true || event.awayName.isEmpty ? .event : .match
        squadQualifiers = SportsHandoffIdentity.qualifiers(for: event)
        sportsIdentity = event.sportsFixture.map { .init(eventKind: $0.eventKind, participants: $0.participants, squad: $0.squad) }
        cricketFormat = event.cricketFixture?.format
        cricketLabel = category == "cricket" ? event.title : nil
        confirmedAt = now
    }

    @MainActor
    static func make(event: EventReference, now: Date) -> Self? {
        guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
              let kickoff = event.kickoffDate,
              event.sportsFixture.map({ $0.sport == event.normalizedCategory }) ?? true,
              !MatchStartPolicy(event: event, now: now).isStopped else { return nil }
        let value = Self(event: event, kickoff: kickoff, now: now)
        return value.isValid(at: now) ? value : nil
    }

    @MainActor
    func isValid(at now: Date) -> Bool {
        guard version == 1, now.timeIntervalSince1970.isFinite, confirmedAt.timeIntervalSince1970.isFinite,
              (-30..<Self.lifetime).contains(now.timeIntervalSince(confirmedAt)),
              kickoff.timeIntervalSince1970.isFinite,
              kickoff >= confirmedAt.addingTimeInterval(-14 * 86_400),
              kickoff <= confirmedAt.addingTimeInterval(MatchStartPolicy.playbackLead),
              SportsInterestPreferences.supportedIDs.contains(category),
              Self.safeText(eventID, maximum: 200), Self.safeText(title, maximum: 300),
              Self.safeText(homeName, maximum: 160), Self.safeText(awayName, maximum: 160, empty: kind == .event),
              competitionID.map({ Self.safeText($0, maximum: 120) }) ?? true,
              canonicalFixtureID.map({ Self.safeText($0, maximum: 200) }) ?? true,
              cricketLabel.map({ category == "cricket" && Self.safeText($0, maximum: 300) }) ?? true,
              squadQualifiers.count <= 12, Set(squadQualifiers).count == squadQualifiers.count,
              squadQualifiers.allSatisfy({ Self.safeText($0, maximum: 40) }),
              kind != .match || (Self.named(homeName) && Self.named(awayName)
                  && homeName.caseInsensitiveCompare(awayName) != .orderedSame),
              !(sportsIdentity != nil && cricketFormat != nil) else { return false }
        if let sportsIdentity {
            guard canonicalFixtureID != nil, competitionID != nil,
                  !sportsIdentity.participants.isEmpty, sportsIdentity.participants.count <= 32,
                  Set(sportsIdentity.participants.map(\.id)).count == sportsIdentity.participants.count,
                  sportsIdentity.participants.allSatisfy({ Self.safeText($0.id, maximum: 200)
                      && Self.safeText($0.name, maximum: 160)
                      && ($0.role.map { Self.safeText($0, maximum: 40) } ?? true) }),
                  Self.safeText(sportsIdentity.squad.ageGroup, maximum: 40),
                  (sportsIdentity.eventKind == .match) == (kind == .match) else { return false }
        }
        if cricketFormat != nil {
            guard category == "cricket", canonicalFixtureID != nil, competitionID != nil else { return false }
        }
        return true
    }

    @MainActor
    func matches(_ event: EventReference) -> Bool {
        guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
              event.normalizedCategory == category,
              (event.competitionID ?? event.cricketFixture?.competitionID) == competitionID,
              (event.sportsFixture?.fixtureID ?? event.cricketFixture?.fixtureID) == canonicalFixtureID,
              SportsHandoffIdentity.qualifiers(for: event) == squadQualifiers,
              event.cricketFixture?.format == cricketFormat,
              category != "cricket" || event.title == cricketLabel else { return false }
        if let sportsIdentity {
            guard let current = event.sportsFixture,
                  current.sport == category,
                  current.eventKind == sportsIdentity.eventKind, current.squad == sportsIdentity.squad,
                  SportsFixtureCatalog.sameParticipantIdentity(current.participants, sportsIdentity.participants) else { return false }
        } else if event.sportsFixture != nil { return false }
        // Event/series/session descriptions and cricket ordinals/day labels are
        // part of identity. They must not disappear in a team-pair fallback.
        if kind == .event || category == "cricket" {
            guard event.displayTitle == title else { return false }
        }
        return true
    }

    @MainActor var request: StreamPlaybackRequest {
        StreamPlaybackRequest(matchID: eventID, displayTitle: title, homeTeam: homeName,
            awayTeam: awayName, category: category, kickoffDate: kickoff)
    }

    @MainActor
    static func decode(_ data: Data, at now: Date) -> Self? {
        guard !data.isEmpty, data.count <= maximumPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let sports = object["sportsIdentity"] as? [String: Any] {
            guard Set(sports.keys).isSubset(of: ["eventKind", "participants", "squad"]),
                  let participants = sports["participants"] as? [[String: Any]],
                  participants.allSatisfy({ Set($0.keys).isSubset(of: ["id", "name", "role"]) }),
                  let squad = sports["squad"] as? [String: Any],
                  Set(squad.keys).isSubset(of: ["gender", "ageGroup"]) else { return nil }
        }
        guard let record = try? JSONDecoder().decode(Self.self, from: data), record.isValid(at: now) else { return nil }
        return record
    }

    private static func safeText(_ value: String, maximum: Int, empty: Bool = false) -> Bool {
        value.count <= maximum && value.utf8.count <= maximum * 4
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !value.contains("://") && (empty || !value.isEmpty)
    }

    private static func named(_ value: String) -> Bool {
        !["", "home", "away", "tbd", "tbc", "unknown", "teams to be confirmed"].contains(value.lowercased())
    }
}

@Observable @MainActor
final class LastLiveMatchStore {
    static let shared = LastLiveMatchStore()
    static let enablementKey = "fotty.privacy.rememberLastLiveMatch.v1"
    static let storageKey = "fotty.lastLiveMatch.v1"

    struct PlaybackTicket: Equatable, Sendable { fileprivate let id = UUID() }
    private struct Pending { let ticket: PlaybackTicket; let event: EventReference }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var pending: Pending?
    private(set) var record: LastLiveMatchRecord?
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enablementKey)
            if !isEnabled { clear() }
        }
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        clock = now
        isEnabled = defaults.bool(forKey: Self.enablementKey)
        if isEnabled, let data = defaults.data(forKey: Self.storageKey),
           let value = LastLiveMatchRecord.decode(data, at: now()) {
            record = value
        } else {
            record = nil
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    /// Begin from the accepted single owner, not a Watch tap. No durable data is
    /// written until that owner's real decoded-video callback confirms it.
    func beginPlayback(of event: EventReference, now: Date? = nil) -> PlaybackTicket? {
        pending = nil
        guard isEnabled, LastLiveMatchRecord.make(event: event, now: now ?? clock()) != nil else { return nil }
        let ticket = PlaybackTicket()
        pending = Pending(ticket: ticket, event: event)
        return ticket
    }

    @discardableResult
    func confirmDecodedPlayback(_ ticket: PlaybackTicket, now: Date? = nil) -> Bool {
        guard isEnabled, let pending, pending.ticket == ticket else { return false }
        self.pending = nil // consume once; redraw/repeated callbacks cannot re-add
        guard let value = LastLiveMatchRecord.make(event: pending.event, now: now ?? clock()),
              let data = try? JSONEncoder().encode(value), data.count <= LastLiveMatchRecord.maximumPayloadBytes else { return false }
        defaults.set(data, forKey: Self.storageKey)
        record = value
        return true
    }

    func cancelPlayback(_ ticket: PlaybackTicket) {
        if pending?.ticket == ticket { pending = nil }
    }

    func clear() {
        pending = nil
        record = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Explicit lifecycle maintenance, safe to call from an active scene task
    /// or clock update. Eligibility reads during SwiftUI rendering stay pure.
    @discardableResult
    func pruneExpiredRecord(at now: Date? = nil) -> Bool {
        guard let record, !record.isValid(at: now ?? clock()) else { return false }
        // The expired identity can belong to an older viewing session while
        // a new owner is still buffering. Only an explicit Forget/opt-out
        // revokes that pending owner's decoded-confirmation ticket.
        self.record = nil
        defaults.removeObject(forKey: Self.storageKey)
        return true
    }

    /// A retained identity is not LIVE authority. Missing/deleted or conflicting
    /// catalog rows never fall back to the stored record, and playback is never
    /// started here. The caller uses the returned fresh event's normal Watch path.
    func eligibleEvent(in catalog: [EventReference], at now: Date? = nil,
                       status: (EventReference) -> FootballMatch.MatchStatus? = { _ in nil }) -> EventReference? {
        let now = now ?? clock()
        guard isEnabled, let record else { return nil }
        guard record.isValid(at: now) else { return nil }
        guard let current = CatalogPlaybackIdentity.matchingEvent(for: record.request, in: catalog),
              record.matches(current), let kickoff = current.kickoffDate,
              kickoff <= now.addingTimeInterval(300),
              current.sportsFixture?.status.stopsPlayback != true,
              current.cricketFixture?.status.stopsPlayback != true else { return nil }
        let scoreStatus = current.normalizedCategory == "football" ? status(current) : nil
        guard !MatchStartPolicy(event: current, now: now, status: scoreStatus).isStopped else { return nil }
        if let scoreStatus { return scoreStatus.isLive ? current : nil }
        return current.sportsFixture?.isLive(at: now) == true || current.cricketFixture?.isLive(at: now) == true ? current : nil
    }
}
