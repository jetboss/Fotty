import Foundation

/// The pure, dependency-free core of the fail-closed match-identity discipline.
///
/// This is the first engine-owned slice of the matcher that already exists in
/// `ReviewedSportsFixtureMatcher` + `SportsTeamIdentity`. It contains only the
/// string-normalization, team-name, title-parsing and cricket-context logic
/// that has no dependency on the app's club/team catalogs. The catalog-coupled
/// parts (canonical club IDs, alias resolution, full request/fixture selection)
/// are layered on top in a later step, so those pieces stay unchanged until
/// this core is proven identical.
enum MatchIdentity {
    /// The shared string normalization: case/diacritic/width folding, `&`
    /// expansion and alphanumeric tokenization. Never substring- or fuzzy-match.
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Maps free-text sport labels to the canonical sport key. Unknown labels
    /// return an empty string so they can never match by accident.
    static func sportKey(_ raw: String) -> String {
        switch normalized(raw) {
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

    private static let squadPattern = #"\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b"#

    /// Removes recognized squad/age tokens to recover the base legal team name.
    /// Unknown base names retain their complete normalized spelling.
    static func baseTeamName(_ raw: String) -> String {
        normalized(raw)
            .replacingOccurrences(of: squadPattern, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Extracts the recognized squad/age qualifiers (women/reserves/uNN) as a
    /// normalized set. Women/Womens/Ladies/W collapse to a single token.
    static func squadQualifiers(_ raw: String) -> Set<String> {
        let text = normalized(raw)
        guard let regex = try? NSRegularExpression(pattern: squadPattern) else { return [] }
        let source = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let token = source.substring(with: match.range).replacingOccurrences(of: " ", with: "")
            if ["women", "womens", "ladies", "w"].contains(token) { return "women" }
            if ["reserve", "reserves"].contains(token) { return "reserves" }
            return token.replacingOccurrences(of: "under", with: "u")
        })
    }

    enum TitleTeams: Equatable, Sendable {
        case absent
        case ambiguous
        case pair(String, String)
    }

    /// Parses exactly one `A vs B` separator from a title, rejecting ambiguity
    /// (multiple separators, competition suffixes, or a second embedded pair).
    /// `absent` means "no separator", `ambiguous` means "cannot trust the title".
    static func titleTeams(_ raw: String) -> TitleTeams {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = title.firstIndex(of: ":") {
            let prefix = normalized(String(title[..<colon]))
            if prefix == "live" || prefix == "upcoming" {
                title = String(title[title.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let separator = #"(?i)\s+(?:vs\.?|v\.?|versus|@)\s+"#
        guard let separatorRegex = try? NSRegularExpression(pattern: separator) else { return .ambiguous }
        let separators = separatorRegex.numberOfMatches(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title))
        guard separators > 0 else { return .absent }
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

    struct CricketContext: Equatable, Sendable {
        let format: String
        let ordinal: Int?
        let day: Int?
    }

    /// Literal programme qualifiers (Test/T20/ODI/T10 + ordinal + Test day),
    /// retained separately from the official Test's original start. Never
    /// supplies a date or timezone.
    static func cricketContext(_ text: String) -> CricketContext? {
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
            return CricketContext(format: format, ordinal: ordinal, day: day)
        }
        return nil
    }

    /// A team key is the base legal name plus normalized squad qualifiers.
    /// This engine core is catalog-free: canonical club-ID resolution and the
    /// reviewed alias table are layered on by the app in a later step, so those
    /// already-reviewed names keep working unchanged until this core is proven.
    static func teamKey(_ raw: String, sport: String) -> String {
        let base = baseTeamName(raw)
        guard !base.isEmpty else { return "" }
        let qualifiers = squadQualifiers(raw).sorted().joined(separator: ",")
        return qualifiers.isEmpty ? base : "\(base)|\(qualifiers)"
    }

    /// Forms the canonical unordered team pair, rejecting placeholders and
    /// same-team strings. Returns nil when the pair cannot be trusted.
    static func pairKey(home: String, away: String, sport: String) -> [String]? {
        let homeKey = teamKey(home, sport: sport)
        let awayKey = teamKey(away, sport: sport)
        let placeholders: Set<String> = ["", "home", "away", "tbd", "tbc", "unknown"]
        guard !placeholders.contains(homeKey), !placeholders.contains(awayKey), homeKey != awayKey else { return nil }
        return [homeKey, awayKey].sorted()
    }

    struct FixtureIdentity: Equatable, Sendable {
        let sport: String
        let pair: [String]
        let kickoff: Date
        let effectiveID: String
    }

    struct CandidateIdentity: Equatable, Sendable {
        let metadataID: String
        let effectiveID: String
        let identity: FixtureIdentity?
    }

    enum Selection: Equatable, Sendable {
        case matched(Int)
        case missing
        case conflicting
    }

    /// The fail-closed exact selection: a candidate matches only when sport,
    /// canonical pair and kickoff (within a 15-minute window) all agree. Any
    /// malformed or contradictory sibling sharing a metadata/effective ID is a
    /// veto, and more than one distinct match is a conflict.
    static func select(sport: String, pair: [String], kickoff: Date,
                       from candidates: [CandidateIdentity]) -> Selection {
        let grouped = Dictionary(grouping: candidates, by: \.metadataID)
        let groupedTargets = Dictionary(grouping: candidates, by: \.effectiveID)
        let matches = candidates.indices.filter { index in
            guard let identity = candidates[index].identity else { return false }
            return identity.sport == sport && identity.pair == pair
                && abs(identity.kickoff.timeIntervalSince(kickoff)) <= 15 * 60
        }
        for index in matches {
            let candidate = candidates[index]
            guard grouped[candidate.metadataID]?.allSatisfy({ $0.identity == candidate.identity }) == true,
                  let target = candidate.identity?.effectiveID,
                  groupedTargets[target]?.allSatisfy({ $0.identity == candidate.identity }) == true else {
                return .conflicting
            }
        }
        let unique = Dictionary(matches.map { (candidates[$0].metadataID, $0) },
                                uniquingKeysWith: { first, _ in first })
        if unique.count > 1 { return .conflicting }
        return unique.values.first.map(Selection.matched) ?? .missing
    }
}
