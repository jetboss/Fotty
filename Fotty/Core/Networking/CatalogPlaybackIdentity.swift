import Foundation

/// Admission, not ranking: a similarly named fixture is never a substitute
/// for the requested broadcast. Provider-ID and channel routes are explicit
/// contracts; name-based recovery needs a complete, dated fixture identity.
@MainActor
enum CatalogPlaybackIdentity {
    static let kickoffTolerance: TimeInterval = 15 * 60

    enum Selection {
        case matched(AnalyticalDataEngine.EventReference)
        case missing
        case conflicting
    }

    static func matchingEvent(
        for request: StreamPlaybackRequest,
        in events: [AnalyticalDataEngine.EventReference]
    ) -> AnalyticalDataEngine.EventReference? {
        guard case .matched(let event) = selection(for: request, in: events) else { return nil }
        return event
    }

    /// An admitted registry link can select an advertised primary-directory
    /// identity, never create its sources or substitute a sibling by name.
    /// The caller supplies only its freshly admitted primary catalog here.
    static func registeredSelection(
        for request: StreamPlaybackRequest,
        in events: [AnalyticalDataEngine.EventReference],
        catalogObservedAt: Date,
        association: BroadcastRegistryMatch,
        at now: Date = Date()
    ) -> Selection {
        let broadcast = association.broadcast
        guard (0..<180).contains(now.timeIntervalSince(catalogObservedAt)),
              broadcast.providerCode == "streamex", broadcast.kind == .event,
              association.matches(request: request, providerCode: "streamex",
                providerEventID: broadcast.providerEventID, streamID: broadcast.streamID, at: now),
              let sourceStart = broadcast.start else { return .conflicting }
        let exact = events.filter { $0.id == broadcast.providerEventID }
        guard !exact.isEmpty else { return .missing }
        guard exact.count == 1, let source = exact.first,
              !source.hasCatalogIdentityConflict,
              VerifiedFixtureTerminalPolicy.state(for: source, at: now) == nil,
              source.kickoffDate == sourceStart,
              let identity = ReviewedSportsFixtureMatcher.requestIdentity(for: StreamPlaybackRequest(event: source)) else { return .conflicting }
        let comparison: StreamPlaybackRequest
        if association.link?.matchMethod == .testPeriod {
            // The link separately verifies the original Test/day/ordinal/end.
            // Only its literal, freshly repeated source occurrence is compared
            // here; the canonical request and fixture remain unchanged.
            comparison = .init(matchID: request.matchID, displayTitle: request.displayTitle,
                homeTeam: request.homeTeam, awayTeam: request.awayTeam, category: request.category,
                kickoffDate: sourceStart, preferredEvent: request.preferredEvent)
        } else { comparison = request }
        if let fixture = request.preferredEvent?.sportsFixture {
            // The exact cloud link is initial alias admission, not recovery
            // from a prior native merge. Keep the existing competition, full
            // pair, senior squad, reviewed-club and exact-start checks without
            // demanding that this new provider ID was already merged locally.
            guard SportsFixtureCatalog.providerMatches(source, fixture: fixture,
                kickoff: comparison.kickoffDate, allowUnmarkedLeague: true,
                admittingUnmarkedLeague: true) else { return .conflicting }
        } else {
            guard case .matched = selection(for: comparison, in: [source]) else { return .conflicting }
        }
        let cricket = identity.sport == "cricket"
            ? ReviewedSportsFixtureMatcher.cricketBroadcastContext(source.title ?? "") : nil
        guard association.admitsFreshIdentity(sport: identity.sport, pair: identity.pair,
                start: identity.kickoff, providerEventID: source.id, streamID: source.id,
                format: cricket?.format, matchOrdinal: cricket?.ordinal, day: cricket?.day, at: now),
              association.matches(request: request, providerCode: "streamex",
                providerEventID: source.id, streamID: source.id, at: now) else { return .conflicting }
        return .matched(source)
    }

    static func selection(
        for request: StreamPlaybackRequest,
        in events: [AnalyticalDataEngine.EventReference]
    ) -> Selection {
        guard request.preferredEvent?.hasCatalogIdentityConflict != true else { return .conflicting }
        let exact = events.filter {
            CatalogRouteIdentity.matches(eventID: $0.id, requestedID: request.matchID)
                || $0.sportsFixture?.providerEventIDs?.contains(request.matchID) == true
        }
        if !exact.isEmpty {
            // Conflicting duplicate IDs are not made safe by taking the first
            // row. Nor should contradictory ID metadata fall through to names.
            guard exact.count == 1, let event = exact.first,
                  exactIdentityIsConsistent(event, with: request) else { return .conflicting }
            return .matched(event)
        }

        let category = requestCategory(request.category)
        guard !category.isEmpty, let kickoff = request.kickoffDate,
              validPair(home: request.homeTeam, away: request.awayTeam, category: category) else { return .missing }
        let matches = events.filter { event in
            !event.hasCatalogIdentityConflict && !event.isBroadcastChannel
                && event.normalizedCategory == category
                && event.kickoffDate.map { abs($0.timeIntervalSince(kickoff)) <= kickoffTolerance } == true
                && (request.preferredEvent?.sportsFixture.map {
                    SportsFixtureCatalog.providerMatches(event, fixture: $0, kickoff: kickoff, allowUnmarkedLeague: true)
                } ?? samePair(event, request: request, category: category))
        }
        if matches.count > 1 { return .conflicting }
        return matches.first.map { .matched($0) } ?? .missing
    }

    private static func exactIdentityIsConsistent(
        _ event: AnalyticalDataEngine.EventReference, with request: StreamPlaybackRequest
    ) -> Bool {
        guard !event.hasCatalogIdentityConflict else { return false }
        let category = requestCategory(request.category)
        guard category.isEmpty || event.normalizedCategory == category else { return false }
        if let fixture = request.preferredEvent?.sportsFixture {
            // A saved/reminded fixture may follow its same stable ID through a
            // reschedule; cross-ID playback still requires dated evidence.
            if let current = event.sportsFixture {
                guard current.fixtureID == fixture.fixtureID, current.competitionID == fixture.competitionID, current.sport == fixture.sport,
                      current.sport == event.normalizedCategory,
                      current.eventKind == fixture.eventKind,
                      SportsFixtureCatalog.sameParticipantIdentity(current.participants, fixture.participants),
                      current.squad == fixture.squad else { return false }
                return request.kickoffDate == nil || datesAgree(event.kickoffDate, request.kickoffDate)
            } else if !SportsFixtureCatalog.providerMatches(event, fixture: fixture, kickoff: request.kickoffDate,
                                                           allowUnmarkedLeague: true) {
                return false
            } else {
                // A reviewed typed match owns its full-name aliases and squad
                // checks; a second generic raw-name check must not reject it.
                return request.kickoffDate == nil || datesAgree(event.kickoffDate, request.kickoffDate)
            }
        }
        if let preferred = request.preferredEvent, preferred.sportsFixture == nil,
           let fixture = event.sportsFixture, fixture.providerEventIDs?.contains(request.matchID) == true {
            guard SportsFixtureCatalog.providerMatches(preferred, fixture: fixture, kickoff: event.kickoffDate,
                                                       allowUnmarkedLeague: true) else { return false }
            return request.kickoffDate == nil || datesAgree(event.kickoffDate, request.kickoffDate)
        }
        let home = normalizedName(request.homeTeam), away = normalizedName(request.awayTeam)
        if home.isEmpty && away.isEmpty {
            // Notification/deep-link cold launch: the opaque catalog ID is the
            // only identity supplied. Do not fabricate team-name evidence.
            return request.kickoffDate == nil
                || datesAgree(event.kickoffDate, request.kickoffDate)
        }
        if event.isBroadcastChannel {
            return away.isEmpty && home == normalizedName(event.homeName)
        }
        if !validPair(home: request.homeTeam, away: request.awayTeam, category: category) {
            // Race/tournament listings need not have two opposing teams. They
            // remain openable by their exact provider ID and unchanged title,
            // never through the dated two-team fallback below.
            guard !validPair(home: event.homeName, away: event.awayName, category: category),
                  home == normalizedName(event.homeName), away == normalizedName(event.awayName),
                  !normalizedName(request.displayTitle).isEmpty,
                  normalizedName(request.displayTitle) == normalizedName(event.title ?? "") else { return false }
            return request.kickoffDate == nil || datesAgree(event.kickoffDate, request.kickoffDate)
        }
        guard validPair(home: request.homeTeam, away: request.awayTeam, category: category),
              samePair(event, request: request, category: category) else { return false }
        // A provider's own undated row can still be opened by exact ID. If the
        // caller supplies a date, missing/conflicting provider time is unsafe.
        return request.kickoffDate == nil || datesAgree(event.kickoffDate, request.kickoffDate)
    }

    private static func datesAgree(_ candidate: Date?, _ requested: Date?) -> Bool {
        guard let candidate, let requested else { return false }
        return abs(candidate.timeIntervalSince(requested)) <= kickoffTolerance
    }

    private static func samePair(
        _ event: AnalyticalDataEngine.EventReference, request: StreamPlaybackRequest, category: String
    ) -> Bool {
        validPair(home: event.homeName, away: event.awayName, category: category)
            && teamKey(event.homeName, category: category) == teamKey(request.homeTeam, category: category)
            && teamKey(event.awayName, category: category) == teamKey(request.awayTeam, category: category)
            && (category != "football" || squadQualifiers([event.homeName, event.awayName, event.title ?? ""])
                == squadQualifiers([request.homeTeam, request.awayTeam, request.displayTitle]))
    }

    private static func validPair(home: String, away: String, category: String) -> Bool {
        let homeKey = teamKey(home, category: category), awayKey = teamKey(away, category: category)
        let placeholders: Set<String> = ["", "home", "away", "tbd", "tbc", "unknown"]
        return !placeholders.contains(homeKey) && !placeholders.contains(awayKey) && homeKey != awayKey
    }

    private static func teamKey(_ name: String, category: String) -> String {
        if category == "football", let club = FootballCompetitionCatalog.canonicalClubID(for: name) {
            return "club:\(club)"
        }
        let normalized = normalizedName(name)
        guard category == "football" else { return normalized }
        // Whole-name international aliases only; never token overlap. Unknown
        // teams preserve reserve, youth, women's and other identity qualifiers.
        switch normalized {
        case "turkiye", "turkey": return "turkey"
        case "cape verde islands", "cape verde": return "cape verde"
        case "cote d ivoire", "ivory coast": return "ivory coast"
        case "dr congo", "congo dr", "democratic republic of congo": return "congo dr"
        case "bosnia and herzegovina", "bosnia herzegovina": return "bosnia herzegovina"
        case "usa", "united states": return "united states"
        case "korea republic", "south korea": return "south korea"
        default: return normalized
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.map { $0.lowercased() }.joined(separator: " ")
    }

    private static func requestCategory(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : AnalyticalDataEngine.normalizedCategoryKey(value)
    }

    private static func squadQualifiers(_ values: [String]) -> Set<String> {
        // Some feeds leave senior names in `teams` and put the age/sex only in
        // the title. That title evidence must not be lost during admission.
        let text = values.map(normalizedName).joined(separator: " ")
        let pattern = #"\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let token = source.substring(with: match.range).replacingOccurrences(of: " ", with: "")
            if ["women", "womens", "ladies"].contains(token) { return "women" }
            if ["reserve", "reserves"].contains(token) { return "reserves" }
            return token.replacingOccurrences(of: "under", with: "u")
        })
    }

    /// Display formatting can hide legal suffixes, but never squad identity.
    /// Deduplication shares playback's qualifiers instead of merging a youth
    /// or women's listing merely because its `teams` fields name senior clubs.
    static func footballSquadIdentity(teamName: String) -> Set<String> {
        squadQualifiers([teamName])
    }

    static func footballSquadIdentity(for event: AnalyticalDataEngine.EventReference) -> Set<String> {
        var identity = squadQualifiers([event.homeName, event.awayName, event.title ?? ""])
        if let fixture = event.sportsFixture {
            if fixture.squad.gender != .men { identity.insert(fixture.squad.gender.rawValue) }
            if fixture.squad.ageGroup != "senior" { identity.insert(fixture.squad.ageGroup) }
        }
        return identity
    }
}

/// Redaction is for diagnostics, never delivery identity. Query parameters,
/// path case and required request headers may select different broadcasts.
struct StreamDeliveryIdentity: Hashable {
    private struct Header: Hashable { let name: String; let value: String }
    private let url: String
    private let headers: [Header]

    init(url: URL, headers: [String: String]) {
        self.url = url.absoluteString
        self.headers = headers.map { Header(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
    }
}
