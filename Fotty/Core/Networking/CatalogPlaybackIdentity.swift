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

    static func selection(
        for request: StreamPlaybackRequest,
        in events: [AnalyticalDataEngine.EventReference]
    ) -> Selection {
        guard request.preferredEvent?.hasCatalogIdentityConflict != true else { return .conflicting }
        let exact = events.filter {
            CatalogRouteIdentity.matches(eventID: $0.id, requestedID: request.matchID)
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
        return NationalTeamAliases.canonical(normalized, sport: category)
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

/// Reviewed whole-name spellings of the same national side, shared by catalog
/// admission and every reviewed source adapter (Highfly, CS, CNC, Plavio).
/// Input must already be normalized (lowercase, diacritics folded, words
/// separated by single spaces). Never token overlap or prefix matching; squad
/// qualifiers (women, U21…) are handled by callers and stay part of identity.
enum NationalTeamAliases {
    nonisolated static func canonical(_ normalized: String, sport: String) -> String {
        if let name = shared[normalized] { return name }
        if sport == "football", let name = football[normalized] { return name }
        return normalized
    }

    private static let shared: [String: String] = groups([
        "united states": ["usa", "united states", "united states of america"],
        "united arab emirates": ["uae", "united arab emirates"],
        "south korea": ["korea republic", "south korea", "republic of korea"],
        "north korea": ["korea dpr", "dpr korea", "north korea"],
        "hong kong": ["hong kong", "hong kong china"],
        "papua new guinea": ["papua new guinea", "png"],
    ])

    /// Football-only: in cricket "Ireland" is a different (all-island) side.
    private static let football: [String: String] = groups([
        "turkey": ["turkiye", "turkey"],
        "czech republic": ["czechia", "czech republic"],
        "iran": ["iran", "ir iran", "islamic republic of iran"],
        "ivory coast": ["cote d ivoire", "ivory coast"],
        "cape verde": ["cape verde islands", "cape verde", "cabo verde"],
        "congo dr": ["dr congo", "congo dr", "democratic republic of congo",
                     "democratic republic of the congo"],
        "bosnia herzegovina": ["bosnia and herzegovina", "bosnia herzegovina", "bosnia"],
        "republic of ireland": ["republic of ireland", "ireland"],
        "north macedonia": ["north macedonia", "macedonia", "fyr macedonia"],
        "netherlands": ["netherlands", "holland"],
        "china": ["china", "china pr"],
        "chinese taipei": ["chinese taipei", "taiwan"],
        "eswatini": ["eswatini", "swaziland"],
        "kyrgyzstan": ["kyrgyzstan", "kyrgyz republic"],
        "gambia": ["gambia", "the gambia"],
        "trinidad and tobago": ["trinidad and tobago", "trinidad tobago"],
        "saint kitts and nevis": ["saint kitts and nevis", "st kitts and nevis", "st kitts nevis"],
        "saint lucia": ["saint lucia", "st lucia"],
        "saint vincent and the grenadines": ["saint vincent and the grenadines",
                                             "st vincent and the grenadines", "st vincent grenadines"],
        "sao tome and principe": ["sao tome and principe", "sao tome e principe"],
        "antigua and barbuda": ["antigua and barbuda", "antigua barbuda"],
        "brunei": ["brunei", "brunei darussalam"],
        "laos": ["laos", "lao pdr", "lao"],
        "syria": ["syria", "syrian arab republic"],
        "russia": ["russia", "russian federation"],
        "moldova": ["moldova", "republic of moldova"],
        "palestine": ["palestine", "state of palestine"],
        "timor leste": ["timor leste", "east timor"],
        "vietnam": ["vietnam", "viet nam"],
            ])

    private static func groups(_ table: [String: [String]]) -> [String: String] {
        var result: [String: String] = [:]
        for (name, spellings) in table {
            for spelling in spellings {
                precondition(result[spelling] == nil, "duplicate national-team spelling \(spelling)")
                result[spelling] = name
            }
        }
        return result
    }
}
