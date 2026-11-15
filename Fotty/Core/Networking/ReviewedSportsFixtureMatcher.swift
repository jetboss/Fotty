import Foundation

/// Pure fixture identity shared only by reviewed source adapters. Each adapter
/// still owns its schema, explicit date evidence and stream-route admission.
/// Matching catalog metadata never establishes that a fixture is live.
enum ReviewedSportsFixtureMatcher {
    struct ParticipantIdentity: Equatable, Sendable {
        let sport: String
        let pair: [String]
    }

    struct RequestIdentity: Equatable, Sendable {
        let sport: String
        let pair: [String]
        let kickoff: Date
    }

    struct FixtureIdentity: Equatable, Sendable {
        let sport: String
        let pair: [String]
        let kickoff: Date
        let effectiveID: String
        let resourceType: String
        var cricketFormat: String? = nil
        var matchOrdinal: Int? = nil
        var day: Int? = nil
    }

    /// Preserve malformed rows with a nil identity: a sibling reusing their
    /// metadata ID or effective stream target must not hide that contradiction.
    struct Candidate: Equatable, Sendable {
        let metadataID: String
        let effectiveID: String
        let identity: FixtureIdentity?
    }

    enum Selection: Equatable, Sendable {
        /// Index in the unchanged candidate array, not a source-specific ID.
        case matched(Int)
        case missing
        case conflicting
    }

    /// A bounded metadata-fetch hint only. This has no kickoff and must never
    /// authorize a stream request or establish a live fixture by itself.
    nonisolated static func participantIdentity(
        sport rawSport: String, cast: [String], title: String
    ) -> ParticipantIdentity? {
        let sport = sportKey(rawSport)
        guard !sport.isEmpty, let participants = teams(cast: cast, title: title, sport: sport),
              let pair = pairKey(home: participants.0, away: participants.1, sport: sport) else { return nil }
        return ParticipantIdentity(sport: sport, pair: pair)
    }

    nonisolated static func requestIdentity(for request: StreamPlaybackRequest) -> RequestIdentity? {
        let sport = sportKey(request.category)
        guard !sport.isEmpty, let kickoff = request.kickoffDate,
              let requestedTeams = teams(cast: [request.homeTeam, request.awayTeam],
                                         title: matchingRequestTitle(request, sport: sport), sport: sport),
              let pair = pairKey(home: requestedTeams.0, away: requestedTeams.1, sport: sport) else { return nil }
        return RequestIdentity(sport: sport, pair: pair, kickoff: kickoff)
    }

    /// `kickoff` must come from the adapter's reviewed, explicit dated field;
    /// callers must not substitute a LIVE label, current time or channel guide.
    nonisolated static func fixtureIdentity(
        sport rawSport: String, cast: [String], title: String, kickoff: Date?,
        effectiveID: String, resourceType: String, programmeMetadata: String? = nil
    ) -> FixtureIdentity? {
        let sport = sportKey(rawSport)
        guard !sport.isEmpty, let kickoff,
              let participants = teams(cast: cast, title: title, sport: sport),
              let pair = pairKey(home: participants.0, away: participants.1, sport: sport) else { return nil }
        let cricket = sport == "cricket" ? cricketBroadcastContext(programmeMetadata ?? title) : nil
        return FixtureIdentity(sport: sport, pair: pair, kickoff: kickoff,
                               effectiveID: effectiveID, resourceType: resourceType,
                               cricketFormat: cricket?.format, matchOrdinal: cricket?.ordinal, day: cricket?.day)
    }

    nonisolated static func select(
        for request: StreamPlaybackRequest, from candidates: [Candidate], at now: Date = Date()
    ) -> Selection {
        if let association = request.registryMatch {
            return selectRegistered(for: request, association: association, from: candidates, at: now)
        }
        guard let identity = requestIdentity(for: request) else { return .missing }
        return select(for: identity, from: candidates)
    }

    nonisolated static func selectRegistered(for request: StreamPlaybackRequest,
        association: BroadcastRegistryMatch, from candidates: [Candidate], at now: Date = Date()) -> Selection {
        let record = association.broadcast
        guard association.matches(request: request, providerCode: record.providerCode,
            providerEventID: record.providerEventID, streamID: record.streamID, at: now) else { return .conflicting }
        let sameID = candidates.indices.filter { candidates[$0].metadataID == record.providerEventID }
        guard !sameID.isEmpty else { return .missing }
        guard let first = sameID.first, let identity = candidates[first].identity,
              identity.effectiveID == record.streamID,
              association.admitsFreshIdentity(sport: identity.sport, pair: identity.pair, start: identity.kickoff,
                providerEventID: record.providerEventID, streamID: record.streamID,
                format: identity.cricketFormat, matchOrdinal: identity.matchOrdinal, day: identity.day, at: now),
              candidates.filter({ $0.metadataID == record.providerEventID || $0.effectiveID == record.streamID })
                .allSatisfy({ $0.identity == identity }) else { return .conflicting }
        return .matched(first)
    }

    /// Literal programme qualifiers are retained separately from the official
    /// Test's original start. They never supply a date or a timezone.
    nonisolated static func cricketBroadcastContext(_ text: String) -> (format: String, ordinal: Int?, day: Int?)? {
        let lower = text.lowercased()
        let formats: [(String, String)] = [("Test", "test"), ("T20", "t20i?"), ("ODI", "odi"), ("T10", "t10")]
        for (format, expression) in formats {
            guard lower.range(of: "\\b(?:" + expression + ")\\b", options: .regularExpression) != nil else { continue }
            var ordinal: Int?
            if let range = lower.range(of: "\\b([1-9][0-9]?)(?:st|nd|rd|th)\\s+(?:" + expression + ")\\b", options: .regularExpression),
               let value = Int(lower[range].prefix(while: { $0.isNumber })) {
                let suffix = (11...13).contains(value % 100) ? "th" : ([1: "st", 2: "nd", 3: "rd"][value % 10] ?? "th")
                guard lower[range].hasPrefix("\(value)\(suffix)") else { return nil }
                ordinal = value
            }
            let day = format == "Test" ? lower.range(of: #"\bday\s*[-:]?\s*[1-6]\b"#, options: .regularExpression)
                .flatMap { Int(lower[$0].filter(\.isNumber)) } : nil
            return (format, ordinal, day)
        }
        return nil
    }

    /// Diagnostic only: why no row matched, as a fixed label (never a title).
    /// `screened` are identities the adapter rejected on extra evidence
    /// (e.g. cricket format or match number) after they had parsed.
    nonisolated static func missReason(for request: RequestIdentity, parsed: [FixtureIdentity?],
                                       screened: [FixtureIdentity] = []) -> String {
        guard !parsed.isEmpty else { return "no_rows" }
        let near: (FixtureIdentity) -> Bool = { $0.pair == request.pair && abs($0.kickoff.timeIntervalSince(request.kickoff)) <= 15 * 60 }
        if screened.contains(where: { $0.sport == request.sport && near($0) }) { return "format_or_match_number_differs" }
        let readable = (parsed.compactMap { $0 } + screened).filter { $0.sport == request.sport }
        guard !readable.isEmpty else { return "unreadable_rows" }
        if readable.contains(where: near) { return "conflicting_rows" }
        if readable.contains(where: { $0.pair == request.pair }) { return "kickoff_differs" }
        let qualifiers = #"\|(?:women|reserves|youth|academy|ladies|w|u\d{1,2})(?:,(?:women|reserves|youth|academy|ladies|w|u\d{1,2}))*$"#
        let base: ([String]) -> [String] = { pair in
            pair.map { $0.replacingOccurrences(of: qualifiers, with: "", options: .regularExpression) }.sorted()
        }
        if readable.contains(where: { base($0.pair) == base(request.pair) }) { return "squad_differs" }
        if readable.contains(where: { !Set(base($0.pair)).isDisjoint(with: base(request.pair)) }) { return "one_team_matches" }
        return "teams_differ"
    }

    /// Diagnostic only: when exactly one team matched, the source's own key for
    /// the other team (a normalized team name, never a title or link), so a
    /// naming alias can be reviewed.
    /// Diagnostic only: minutes from the official kickoff to the source's time
    /// for the same team pair (closest row), e.g. "-30" when listed 30 min early.
    nonisolated static func kickoffOffsetMinutes(for request: RequestIdentity, parsed: [FixtureIdentity?]) -> Int? {
        parsed.compactMap { $0 }
            .filter { $0.sport == request.sport && $0.pair == request.pair }
            .map { Int(($0.kickoff.timeIntervalSince(request.kickoff) / 60).rounded()) }
            .min { abs($0) < abs($1) }
    }

    /// Diagnostic for alias work: pairs listed in the same sport within 15
    /// minutes of the request's kickoff, as "home v away" team keys (no titles).
    nonisolated static func sameSlotPairs(for request: RequestIdentity, parsed: [FixtureIdentity?], limit: Int = 2) -> [String] {
        var seen = Set<String>()
        return parsed.compactMap { $0 }
            .filter { $0.sport == request.sport && abs($0.kickoff.timeIntervalSince(request.kickoff)) <= 15 * 60 && $0.pair != request.pair }
            .map { pairLabel($0.pair) }
            .filter { seen.insert($0).inserted }
            .prefix(limit).map { $0 }
    }

    /// Every listing of the requested game, for aggregating sources that list
    /// one game several times (once per upstream feed, plus a live row). Each
    /// listing must match exactly; an id whose own rows disagree is skipped,
    /// without vetoing the other listings.
    nonisolated static func selectAll(for request: RequestIdentity, from candidates: [Candidate]) -> [Int] {
        matchingIndices(for: request, from: candidates).accepted
    }

    nonisolated static func pairLabel(_ pair: [String]) -> String {
        String(pair.map { $0.replacingOccurrences(of: "|", with: " ") }.joined(separator: " v ").prefix(64))
    }

    nonisolated static func unmatchedTeamName(for request: RequestIdentity, parsed: [FixtureIdentity?]) -> String? {
        for identity in parsed.compactMap({ $0 }) where identity.sport == request.sport {
            let shared = Set(identity.pair).intersection(request.pair)
            guard shared.count == 1, let other = identity.pair.first(where: { !shared.contains($0) }) else { continue }
            return other.replacingOccurrences(of: "|", with: " ")
        }
        return nil
    }

    nonisolated static func select(
        for request: RequestIdentity, from candidates: [Candidate]
    ) -> Selection {
        let matches = matchingIndices(for: request, from: candidates)
        if let first = matches.accepted.first { return .matched(first) }
        return matches.hadMatch ? .conflicting : .missing
    }

    /// Both entry points use the same ownership proof, including unreadable siblings.
    private nonisolated static func matchingIndices(for request: RequestIdentity, from candidates: [Candidate])
        -> (accepted: [Int], hadMatch: Bool) {
        let byListing = Dictionary(grouping: candidates, by: \.metadataID)
        let byTarget = Dictionary(grouping: candidates, by: \.effectiveID)
        var accepted: [Int] = [], seen = Set<String>()
        var hadMatch = false
        for (index, candidate) in candidates.enumerated() {
            guard let identity = candidate.identity, identity.sport == request.sport,
                  identity.pair == request.pair, abs(identity.kickoff.timeIntervalSince(request.kickoff)) <= 15 * 60 else { continue }
            hadMatch = true
            guard candidate.effectiveID == identity.effectiveID,
                  byListing[candidate.metadataID]?.allSatisfy({ $0.identity == identity }) == true,
                  byTarget[candidate.effectiveID]?.allSatisfy({ $0.identity == identity }) == true,
                  seen.insert(candidate.metadataID).inserted else { continue }
            accepted.append(index)
        }
        return (accepted, hadMatch)
    }

    nonisolated static func sportKey(_ raw: String) -> String {
        switch SportsTeamIdentity.normalized(raw) {
        case "football", "soccer": return "football"
        case "cricket": return "cricket"
        case "basketball", "nba", "wnba": return "basketball"
        case "baseball", "mlb": return "baseball"
        case "hockey", "ice hockey", "nhl": return "hockey"
        case "american football", "nfl", "cfl": return "american-football"
        case "rugby", "rugby league", "rugby union": return "rugby"
        case "fight", "fighting", "mma", "boxing", "ufc": return "fight"
        case "motorsport", "motor sport", "motor racing", "f1", "formula 1": return "motorsport"
        case "golf": return "golf"
        case "tennis": return "tennis"
        case "darts": return "darts"
        case "college", "college sports": return "college"
        case "other", "other sports": return "other"
        default: return ""
        }
    }

    /// Native official projections put competition copy in `title`, whereas
    /// their explicit participants own the canonical display pair. Only that
    /// exact verified projection may avoid parsing its own competition prefix.
    /// Remote catalog titles and uncorroborated request titles stay unchanged.
    nonisolated private static func matchingRequestTitle(_ request: StreamPlaybackRequest, sport: String) -> String {
        guard let event = request.preferredEvent, !event.hasCatalogIdentityConflict,
              event.id == request.matchID, sportKey(event.category ?? "") == sport,
              let kickoff = request.kickoffDate, event.kickoffDate == kickoff,
              let home = event.teams?.home?.name, let away = event.teams?.away?.name,
              pairKey(home: home, away: away, sport: sport) != nil,
              teamKey(home, sport: sport) == teamKey(request.homeTeam, sport: sport),
              teamKey(away, sport: sport) == teamKey(request.awayTeam, sport: sport),
              let title = event.title, title == request.displayTitle else { return request.displayTitle }
        let pairTitle = "\(home) vs \(away)"
        let participantSquads = squadQualifiers(home).union(squadQualifiers(away))
        if let fixture = event.cricketFixture {
            guard event.sportsFixture == nil, sport == "cricket", fixture.verified,
                  !fixture.fixtureID.isEmpty, !fixture.competitionID.isEmpty,
                  event.id == CricketFixtureCatalog.fixtureIDPrefix + fixture.fixtureID,
                  title == "\(fixture.competitionName) · \(pairTitle)",
                  squadQualifiers(fixture.competitionName).isSubset(of: participantSquads) else {
                return request.displayTitle
            }
            return pairTitle
        }
        if let fixture = event.sportsFixture {
            guard fixture.verified, fixture.sport == sport, fixture.eventKind == .match,
                  !fixture.competitionID.isEmpty, fixture.fixtureID == event.id,
                  fixture.fixtureID.hasPrefix(SportsFixtureCatalog.fixtureIDPrefix + fixture.competitionID + ":"),
                  fixture.title == title, fixture.participants.count == 2,
                  Set(fixture.participants.map { teamKey($0.name, sport: sport) })
                    == Set([home, away].map { teamKey($0, sport: sport) }),
                  squadQualifiers(fixture.competitionName).isSubset(of: participantSquads),
                  fixture.squad.ageGroup == "senior",
                  fixture.squad.gender == .men && participantSquads.isEmpty
                    || fixture.squad.gender == .women && participantSquads == ["women"] else {
                return request.displayTitle
            }
            return pairTitle
        }
        return request.displayTitle
    }

    nonisolated private static func pairKey(home: String, away: String, sport: String) -> [String]? {
        let homeKey = teamKey(home, sport: sport)
        let awayKey = teamKey(away, sport: sport)
        let placeholders: Set<String> = ["", "home", "away", "tbd", "tbc", "unknown"]
        guard !placeholders.contains(homeKey), !placeholders.contains(awayKey), homeKey != awayKey else {
            return nil
        }
        return [homeKey, awayKey].sorted()
    }

    nonisolated private static func teamKey(_ raw: String, sport: String) -> String {
        // Club identity and explicit squad evidence are independent. Only the
        // existing recognized squad tokens are removed from the base spelling;
        // they always return in the key, including W/Women equivalence. Unknown
        // base names retain their complete normalized legal-name spelling.
        let normalized = baseTeamName(raw)
        guard !normalized.isEmpty else { return "" }
        let canonical: String
        if sport == "football" {
            // Use the same unique, reviewed club identity as the main catalog,
            // then the reviewed whole-name national-team spellings
            // (Türkiye/Turkey). Never token overlap or one-team matching.
            canonical = FootballCompetitionCatalog.canonicalClubID(for: normalized)
                .map { "football|\($0)" } ?? NationalTeamAliases.canonical(normalized, sport: sport)
        } else {
            canonical = SportsTeamIdentity.known(name: normalized, category: sport)?.id
                ?? NationalTeamAliases.canonical(normalized, sport: sport)
        }
        let qualifiers = squadQualifiers(raw).sorted().joined(separator: ",")
        return qualifiers.isEmpty ? canonical : "\(canonical)|\(qualifiers)"
    }

    private static let squadPattern = #"\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b"#

    nonisolated private static func baseTeamName(_ raw: String) -> String {
        SportsTeamIdentity.normalized(raw)
            .replacingOccurrences(of: squadPattern, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    nonisolated private static func squadQualifiers(_ raw: String) -> Set<String> {
        let text = SportsTeamIdentity.normalized(raw)
        guard let regex = try? NSRegularExpression(pattern: squadPattern) else { return [] }
        let source = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let token = source.substring(with: match.range).replacingOccurrences(of: " ", with: "")
            if ["women", "womens", "ladies", "w"].contains(token) { return "women" }
            if ["reserve", "reserves"].contains(token) { return "reserves" }
            return token.replacingOccurrences(of: "under", with: "u")
        })
    }

    private enum TitleTeams {
        case absent
        case ambiguous
        case pair(String, String)
    }

    nonisolated static func teams(
        cast rawCast: [String], title: String, sport: String
    ) -> (String, String)? {
        let cast = rawCast.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch titleTeams(title) {
        case .ambiguous: return nil
        case .absent:
            return cast.count == 2 ? (cast[0], cast[1]) : nil
        case .pair(let first, let second):
            guard pairKey(home: first, away: second, sport: sport) != nil else { return nil }
            guard cast.count == 2 else { return (first, second) }
            guard pairKey(home: cast[0], away: cast[1], sport: sport) != nil else { return nil }

            // Compare both parsed participant pairs without losing independent
            // squad evidence. Title/cast order may differ, legal aliases still
            // need the existing reviewed base identity, and disagreement fails
            // closed instead of trusting whichever field was read first.
            let titleNames = [first, second]
            let titleBases = titleNames.map { teamKey(baseTeamName($0), sport: sport) }
            let castBases = cast.map { teamKey(baseTeamName($0), sport: sport) }
            guard Set(titleBases).count == 2, Set(titleBases) == Set(castBases) else { return nil }
            var merged: [String] = []
            for (index, name) in cast.enumerated() {
                guard let titleIndex = titleBases.firstIndex(of: castBases[index]) else { return nil }
                let titleName = titleNames[titleIndex]
                let castSquad = squadQualifiers(name), titleSquad = squadQualifiers(titleName)
                guard castSquad.isEmpty || titleSquad.isEmpty || castSquad == titleSquad else { return nil }
                merged.append(castSquad.isEmpty && !titleSquad.isEmpty ? titleName : name)
            }
            return (merged[0], merged[1])
        }
    }

    nonisolated private static func titleTeams(_ raw: String) -> TitleTeams {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = title.firstIndex(of: ":") {
            let prefix = SportsTeamIdentity.normalized(String(title[..<colon]))
            if prefix == "live" || prefix == "upcoming" {
                title = String(title[title.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let separator = #"(?i)\s+(?:vs\.?|v\.?|versus|@)\s+"#
        guard let separatorRegex = try? NSRegularExpression(pattern: separator) else { return .ambiguous }
        let separators = separatorRegex.numberOfMatches(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title))
        guard separators > 0 else { return .absent }
        // A competition suffix or a second pair is not an independently parsed
        // participant. Never infer a squad from blanket matching over that text.
        guard separators == 1,
              title.rangeOfCharacter(from: CharacterSet(charactersIn: "|•·()[]:\n\r\t<>")) == nil,
              ![" - ", " – ", " — "].contains(where: { title.contains($0) }) else { return .ambiguous }
        let pattern = #"(?i)^(.+?)\s+(?:vs\.?|v\.?|versus|@)\s+(.+?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: title,
                range: NSRange(title.startIndex..<title.endIndex, in: title)
              ), match.numberOfRanges == 3,
              let homeRange = Range(match.range(at: 1), in: title),
              let awayRange = Range(match.range(at: 2), in: title) else { return .ambiguous }
        return .pair(
            String(title[homeRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(title[awayRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
