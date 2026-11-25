import Foundation

/// A followed team is identified by its sport and exact reviewed/provider name,
/// never by a shared badge image, substring or the text entered into search.
struct SportsTeamIdentity: Equatable, Sendable, Identifiable {
    let displayName: String
    let sportCategory: String
    let badgeURL: URL?
    var id: String { "\(sportCategory)|\(Self.slug(displayName))" }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func slug(_ value: String) -> String { normalized(value).replacingOccurrences(of: " ", with: "-") }

    static func sport(_ value: String) -> String? {
        switch normalized(value) {
        case "football", "soccer": return "football"
        case "basketball", "nba", "wnba": return "basketball"
        case "baseball", "mlb": return "baseball"
        case "hockey", "ice hockey", "nhl": return "hockey"
        case "american football", "nfl", "cfl": return "american-football"
        case "cricket": return "cricket"
        case "rugby", "rugby league", "rugby union": return "rugby"
        default: return nil
        }
    }

    /// Only exact aliases from existing reviewed catalogs are collapsed.
    static func known(name: String, category: String? = nil) -> SportsTeamIdentity? {
        let expectedSport = category.flatMap(sport)
        guard category == nil || expectedSport != nil else { return nil }
        let query = normalized(name)
        guard !query.isEmpty else { return nil }
        let matches = (knownByName[query] ?? []).filter { expectedSport == nil || expectedSport == $0.sportCategory }
        let unique = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.count == 1 ? unique.values.first : nil
    }

    private static let knownByName: [String: [SportsTeamIdentity]] = {
        var entries: [String: [SportsTeamIdentity]] = [:]
        let clubs = FootballCompetitionCatalog.snapshots.values.flatMap(\.clubs)
            + FootballCompetitionCatalog.additionalClubIdentities
        for club in clubs {
            let identity = SportsTeamIdentity(displayName: club.name, sportCategory: "football", badgeURL: nil)
            for name in [club.name] + club.aliases { entries[normalized(name), default: []].append(identity) }
        }
        for team in CPLTeam.allCases {
            let badge = cplNames(team).lazy.compactMap { TeamBrandService.majorLeagueBadgeURLs[$0.lowercased()] }.first
            let identity = SportsTeamIdentity(displayName: team.rawValue, sportCategory: "cricket", badgeURL: badge)
            for name in cplNames(team) { entries[normalized(name), default: []].append(identity) }
        }
        for entry in majorTeams {
            for name in entry.aliases { entries[normalized(name), default: []].append(entry.identity) }
        }
        return entries
    }()

    static func cplNames(_ team: CPLTeam) -> [String] {
        switch team {
        case .antigua: return [team.rawValue, "Antigua and Barbuda Falcons", "Antigua Falcons"]
        case .barbados: return [team.rawValue, "Barbados Royals"]
        case .saintLucia: return [team.rawValue, "St Lucia Kings"]
        case .stKitts: return [team.rawValue, "St Kitts and Nevis Patriots", "Saint Kitts and Nevis Patriots", "St Kitts Nevis Patriots"]
        default: return [team.rawValue]
        }
    }

    struct MajorTeam: Sendable {
        let identity: SportsTeamIdentity
        let league: String
        let aliases: [String]
    }

    /// These are the already-reviewed NBA/WNBA/MLB/NHL bundled entries, not the
    /// mutable global badge cache. Shared football/reserve logos never enter here.
    static let majorTeams: [MajorTeam] = {
        let leagues = ["nba": "basketball", "wnba": "basketball", "mlb": "baseball", "nhl": "hockey"]
        var groups: [String: [(String, URL, String, String)]] = [:]
        for (name, url) in TeamBrandService.majorLeagueBadgeURLs {
            let parts = url.pathComponents
            guard url.host == "a.espncdn.com", let index = parts.firstIndex(of: "teamlogos"),
                  parts.indices.contains(index + 1), let category = leagues[parts[index + 1]] else { continue }
            let league = parts[index + 1]
            groups["\(category)|\(league)|\(url.lastPathComponent)", default: []].append((name, url, category, league))
        }
        return groups.values.compactMap { entries in
            guard let preferred = entries.sorted(by: {
                $0.0.count == $1.0.count ? $0.0 < $1.0 : $0.0.count > $1.0.count
            }).first else { return nil }
            var aliases = entries.map { $0.0 }
            if preferred.0 == "los angeles lakers" { aliases.append("LA Lakers") }
            if preferred.0 == "los angeles dodgers" { aliases.append("LA Dodgers") }
            return MajorTeam(identity: .init(displayName: preferred.0.capitalized,
                                            sportCategory: preferred.2, badgeURL: preferred.1),
                             league: preferred.3, aliases: aliases)
        }.sorted { $0.identity.displayName < $1.identity.displayName }
    }()

    private static let majorLeagueByTeamID: [String: String] = Dictionary(
        majorTeams.map { ($0.identity.id, $0.league) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Returns a league only when both exact, reviewed team identities belong
    /// to the same bundled major-league catalog. Unknown college/minor teams
    /// must not inherit importance from the sport name alone.
    static func sharedMajorLeague(home: String, away: String, category: String) -> String? {
        guard let homeID = known(name: home, category: category)?.id,
              let awayID = known(name: away, category: category)?.id,
              let homeLeague = majorLeagueByTeamID[homeID],
              homeLeague == majorLeagueByTeamID[awayID] else { return nil }
        return homeLeague
    }
}
