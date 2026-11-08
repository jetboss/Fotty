import Foundation
import Observation

/// A short-lived viewing intent, never a playback session or a private backup.
/// The receiving device still confirms this identity and discovers its own source.
struct SportsHandoffIdentity: Codable, Equatable, Sendable {
    static let activityType = "com.jelani.Fotty.sports-viewing"
    static let payloadKey = "sportsViewingIdentity"
    static let maximumPayloadBytes = 8 * 1_024
    static let lifetime: TimeInterval = 10 * 60
    static let supportedSports: Set<String> = [
        "football", "cricket", "basketball", "baseball", "tennis", "hockey",
        "fight", "american-football", "motorsport", "golf", "rugby", "volleyball"
    ]

    enum Kind: String, Codable, Sendable { case match, channel, event }
    enum ValidationError: Error, Equatable { case malformed, size, version, expired, identity }

    let version: Int
    let eventID: String
    let title: String
    let category: String
    let homeName: String
    let awayName: String
    let kickoff: Date?
    let competitionID: String?
    let canonicalFixtureID: String?
    let kind: Kind
    let squadQualifiers: [String]
    let issuedAt: Date
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, eventID, title, category, homeName, awayName, kickoff,
             competitionID, canonicalFixtureID, kind, squadQualifiers, issuedAt, expiresAt
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(version: Int = 1, eventID: String, title: String, category: String,
         homeName: String, awayName: String, kickoff: Date?, competitionID: String?,
         canonicalFixtureID: String?, kind: Kind, squadQualifiers: [String],
         issuedAt: Date, expiresAt: Date) {
        self.version = version; self.eventID = eventID; self.title = title; self.category = category
        self.homeName = homeName; self.awayName = awayName; self.kickoff = kickoff
        self.competitionID = competitionID; self.canonicalFixtureID = canonicalFixtureID
        self.kind = kind; self.squadQualifiers = squadQualifiers
        self.issuedAt = issuedAt; self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard all.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ValidationError.malformed
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        eventID = try values.decode(String.self, forKey: .eventID)
        title = try values.decode(String.self, forKey: .title)
        category = try values.decode(String.self, forKey: .category)
        homeName = try values.decode(String.self, forKey: .homeName)
        awayName = try values.decode(String.self, forKey: .awayName)
        kickoff = try values.decodeIfPresent(Date.self, forKey: .kickoff)
        competitionID = try values.decodeIfPresent(String.self, forKey: .competitionID)
        canonicalFixtureID = try values.decodeIfPresent(String.self, forKey: .canonicalFixtureID)
        kind = try values.decode(Kind.self, forKey: .kind)
        squadQualifiers = try values.decode([String].self, forKey: .squadQualifiers)
        issuedAt = try values.decode(Date.self, forKey: .issuedAt)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
    }

    @MainActor
    static func make(event: EventReference, now: Date = .init()) throws -> Self {
        guard !event.hasCatalogIdentityConflict,
              !MatchStartPolicy(event: event, now: now).isStopped else { throw ValidationError.identity }
        let kind: Kind = event.isBroadcastChannel ? .channel
            : (event.awayName.isEmpty || event.sportsFixture.map { $0.eventKind != .match } == true ? .event : .match)
        let value = Self(eventID: event.id, title: event.displayTitle, category: event.normalizedCategory,
            homeName: event.homeName, awayName: event.awayName, kickoff: event.kickoffDate,
            competitionID: event.competitionID ?? event.cricketFixture?.competitionID,
            canonicalFixtureID: event.sportsFixture?.fixtureID ?? event.cricketFixture?.fixtureID,
            kind: kind, squadQualifiers: qualifiers(for: event), issuedAt: now,
            expiresAt: now.addingTimeInterval(lifetime))
        try value.validate(now: now)
        return value
    }

    func validate(now: Date = .init()) throws {
        guard version == 1 else { throw ValidationError.version }
        guard now.timeIntervalSince1970.isFinite, issuedAt.timeIntervalSince1970.isFinite,
              expiresAt.timeIntervalSince1970.isFinite, issuedAt <= now.addingTimeInterval(30),
              expiresAt > now, expiresAt > issuedAt,
              expiresAt.timeIntervalSince(issuedAt) <= Self.lifetime else { throw ValidationError.expired }
        guard Self.safeText(eventID, maximum: 200), Self.safeText(title, maximum: 300),
              Self.supportedSports.contains(category), Self.safeText(homeName, maximum: 160),
              Self.safeText(awayName, maximum: 160, permitsEmpty: kind != .match),
              competitionID.map({ Self.safeText($0, maximum: 120) }) ?? true,
              canonicalFixtureID.map({ Self.safeText($0, maximum: 200) }) ?? true,
              squadQualifiers.count <= 12, Set(squadQualifiers).count == squadQualifiers.count,
              squadQualifiers.allSatisfy({ Self.safeText($0, maximum: 40) }),
              kickoff.map({ $0.timeIntervalSince1970.isFinite
                  && $0 >= now.addingTimeInterval(-14 * 86400)
                  && $0 <= now.addingTimeInterval(90 * 86400) }) ?? (kind != .match),
              kind != .match || homeName.caseInsensitiveCompare(awayName) != .orderedSame,
              kind != .channel || (awayName.isEmpty && canonicalFixtureID == nil)
        else { throw ValidationError.identity }
    }

    func encodedPayload(now: Date = .init()) throws -> Data {
        try validate(now: now)
        let encoded = try JSONEncoder().encode(self)
        guard encoded.count <= Self.maximumPayloadBytes else { throw ValidationError.size }
        return encoded
    }

    static func decode(payload: Data, now: Date = .init()) throws -> Self {
        guard !payload.isEmpty, payload.count <= maximumPayloadBytes else { throw ValidationError.size }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: payload) }
        catch let error as ValidationError { throw error }
        catch { throw ValidationError.malformed }
        try value.validate(now: now)
        return value
    }

    static func decode(activity: NSUserActivity, now: Date = .init()) throws -> Self {
        guard activity.activityType == activityType,
              let info = activity.userInfo, info.count == 1,
              let payload = info[payloadKey] as? Data else { throw ValidationError.malformed }
        return try decode(payload: payload, now: now)
    }

    fileprivate static func safeText(_ text: String, maximum: Int, permitsEmpty: Bool = false) -> Bool {
        guard text.utf8.count <= maximum * 4, text.count <= maximum,
              text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !text.contains("://") else { return false }
        return permitsEmpty || !text.isEmpty
    }

    @MainActor
    static func qualifiers(for event: EventReference) -> [String] {
        let value = [event.title ?? "", event.homeName, event.awayName].joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let pattern = #"\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2})\b"#
        let source = value as NSString
        let regex = try? NSRegularExpression(pattern: pattern)
        let words: [String] = regex?.matches(in: value, range: NSRange(location: 0, length: source.length)).map { match -> String in
            let word = source.substring(with: match.range).replacingOccurrences(of: " ", with: "")
            if ["women", "womens", "ladies"].contains(word) { return "women" }
            if ["reserve", "reserves"].contains(word) { return "reserves" }
            return word.replacingOccurrences(of: "under", with: "u")
        } ?? []
        var tokens = Set(words)
        if let squad = event.sportsFixture?.squad {
            if squad.gender != .men { tokens.insert(squad.gender.rawValue) }
            if squad.ageGroup != "senior" { tokens.insert(squad.ageGroup) }
        }
        return tokens.sorted()
    }
}

@MainActor
enum SportsHandoffMatchPolicy {
    static let catalogFreshness: TimeInterval = 60

    /// The caller supplies the receipt from a successful current catalog fetch,
    /// not the time a cache was read. This returns context for confirmation; it
    /// neither creates a source nor starts playback.
    static func confirmationEvent(for identity: SportsHandoffIdentity, in catalog: [EventReference],
                                  catalogObservedAt: Date, now: Date = .init()) -> EventReference? {
        guard (try? identity.validate(now: now)) != nil,
              (-5...catalogFreshness).contains(now.timeIntervalSince(catalogObservedAt)) else { return nil }
        let request = StreamPlaybackRequest(matchID: identity.eventID, displayTitle: identity.title,
            homeTeam: identity.homeName, awayTeam: identity.awayName, category: identity.category,
            kickoffDate: identity.kickoff, preferredEvent: nil)
        guard let event = CatalogPlaybackIdentity.matchingEvent(for: request, in: catalog),
              !event.hasCatalogIdentityConflict, !MatchStartPolicy(event: event, now: now).isStopped,
              SportsHandoffIdentity.qualifiers(for: event) == identity.squadQualifiers,
              identity.competitionID.map({ $0 == (event.competitionID ?? event.cricketFixture?.competitionID) }) ?? true,
              identity.canonicalFixtureID.map({ $0 == (event.sportsFixture?.fixtureID ?? event.cricketFixture?.fixtureID) }) ?? true,
              (identity.kind == .channel) == event.isBroadcastChannel,
              identity.kind != .channel || event.id == identity.eventID,
              identity.kind != .event || (event.id == identity.eventID && event.displayTitle == identity.title)
        else { return nil }
        return event
    }
}

@MainActor
protocol SportsHandoffActivityPublishing {
    func publish(identity: SportsHandoffIdentity, payload: Data)
    func invalidate()
}

@MainActor
private final class SystemSportsHandoffActivityPublisher: SportsHandoffActivityPublishing {
    private var activity: NSUserActivity?

    func publish(identity: SportsHandoffIdentity, payload: Data) {
        invalidate()
        let next = NSUserActivity(activityType: SportsHandoffIdentity.activityType)
        next.title = identity.title
        next.userInfo = [SportsHandoffIdentity.payloadKey: payload]
        next.requiredUserInfoKeys = [SportsHandoffIdentity.payloadKey]
        next.isEligibleForHandoff = true
        next.isEligibleForSearch = false
        next.isEligibleForPublicIndexing = false
        next.isEligibleForPrediction = false
        next.expirationDate = identity.expiresAt
        next.targetContentIdentifier = identity.eventID
        activity = next
        next.becomeCurrent()
    }

    func invalidate() {
        activity?.isEligibleForHandoff = false
        activity?.resignCurrent()
        activity?.invalidate()
        activity = nil
    }
}

/// Dormant on creation. Only the explicit Continue-on-another-device action
/// calls offer. The system supplies Handoff; no device list or delivery ACK is claimed.
@MainActor @Observable
final class SportsHandoffPublisher {
    private(set) var offeredIdentity: SportsHandoffIdentity?
    var isOffering: Bool { offeredIdentity != nil }
    private let client: any SportsHandoffActivityPublishing

    init(client: (any SportsHandoffActivityPublishing)? = nil) {
        self.client = client ?? SystemSportsHandoffActivityPublisher()
    }

    @discardableResult
    func offer(event: EventReference, now: Date = .init()) throws -> SportsHandoffIdentity {
        stop()
        let identity = try SportsHandoffIdentity.make(event: event, now: now)
        let payload = try identity.encodedPayload(now: now)
        client.publish(identity: identity, payload: payload)
        offeredIdentity = identity
        return identity
    }

    func stop() {
        client.invalidate()
        offeredIdentity = nil
    }

    func expireIfNeeded(now: Date = .init()) {
        guard let identity = offeredIdentity, (try? identity.validate(now: now)) == nil else { return }
        stop()
    }
}
