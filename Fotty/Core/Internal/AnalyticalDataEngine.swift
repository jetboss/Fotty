import Foundation
import OSLog

// MARK: - Live Sports Stream Processor
// Resolves football matches to playable streams via embedsports.top

// Module-level typealiases so providers can reference these types without qualification
typealias EventReference = AnalyticalDataEngine.EventReference

@MainActor
struct AnalyticalDataEngine {

    // MARK: - NexusA Live API Models

    @MainActor
    struct EventReference: @preconcurrency Codable, Identifiable {
        let id: String
        let title: String?
        let category: String?
        let date: Int64?
        let poster: String?
        let popular: Bool?
        let teams: NexusATeams?
        let sources: [NexusASource]?
        /// Fotty-owned ingestion metadata. Persist the quarantine in local
        /// caches, but never allow it to advertise or resolve a delivery route.
        let hasCatalogIdentityConflict: Bool
        /// Optional schedule/status receipt; old provider and saved JSON remains
        /// decodable. It never supplies a stream URL or channel programme.
        let cricketFixture: CricketFixtureMetadata?
        let sportsFixture: SportsFixtureMetadata?
        /// Exact competition evidence from an official schedule or fixture feed.
        let competitionID: String?

        enum CodingKeys: String, CodingKey {
            case id, title, category, date, poster, popular, teams, sources
            case hasCatalogIdentityConflict = "_fottyIdentityConflict"
            case cricketFixture = "_fottyCricketFixture"
            case sportsFixture = "_fottySportsFixture"
            case competitionID = "_fottyCompetitionID"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            date = try container.decodeIfPresent(Int64.self, forKey: .date)
            poster = try container.decodeIfPresent(String.self, forKey: .poster)
            popular = try container.decodeIfPresent(Bool.self, forKey: .popular)
            teams = try container.decodeIfPresent(NexusATeams.self, forKey: .teams)
            hasCatalogIdentityConflict = try container.decodeIfPresent(Bool.self, forKey: .hasCatalogIdentityConflict) ?? false
            cricketFixture = try container.decodeIfPresent(CricketFixtureMetadata.self, forKey: .cricketFixture)
            sportsFixture = try container.decodeIfPresent(SportsFixtureMetadata.self, forKey: .sportsFixture)
            competitionID = try container.decodeIfPresent(String.self, forKey: .competitionID) ?? sportsFixture?.competitionID
            let decodedSources = try container.decodeIfPresent([NexusASource].self, forKey: .sources)
            sources = hasCatalogIdentityConflict ? [] : decodedSources

            if let decodedId = try container.decodeIfPresent(String.self, forKey: .id), !decodedId.isEmpty {
                id = decodedId
            } else {
                let baseTitle = title?.replacingOccurrences(of: " ", with: "-").lowercased() ?? "event"
                id = "\(baseTitle)-\(date ?? 0)"
            }
        }

        init(
            id: String,
            title: String?,
            category: String?,
            date: Int64?,
            poster: String?,
            popular: Bool?,
            teams: NexusATeams?,
            sources: [NexusASource]?,
            hasCatalogIdentityConflict: Bool = false,
            cricketFixture: CricketFixtureMetadata? = nil,
            sportsFixture: SportsFixtureMetadata? = nil,
            competitionID: String? = nil
        ) {
            self.id = id
            self.title = title
            self.category = category
            self.date = date
            self.poster = poster
            self.popular = popular
            self.teams = teams
            self.hasCatalogIdentityConflict = hasCatalogIdentityConflict
            self.cricketFixture = cricketFixture
            self.sportsFixture = sportsFixture
            self.competitionID = competitionID ?? sportsFixture?.competitionID
            self.sources = hasCatalogIdentityConflict ? [] : sources
        }

        nonisolated var kickoffDate: Date? {
            guard let date, date > 0 else { return nil }
            if date > 10_000_000_000 {
                return Date(timeIntervalSince1970: Double(date) / 1000)
            }
            return Date(timeIntervalSince1970: Double(date))
        }

        /// Live feed: retain enough trusted future catalog for the personalized
        /// three-day Home window while still dropping months/years-old junk.
        /// Broadcast channels and unknown kickoffs remain available.
        nonisolated func passesNearTermLiveListWindow(at now: Date = .init()) -> Bool {
            guard !hasCatalogIdentityConflict else { return false }
            if isBroadcastChannel { return true }
            guard let kickoff = kickoffDate else { return true }
            if cricketFixture != nil || sportsFixture != nil {
                return kickoff >= now.addingTimeInterval(-14 * 86400)
                    && kickoff <= now.addingTimeInterval(CatalogTimingPolicy.retentionFutureHorizon)
            }
            return kickoff >= now.addingTimeInterval(-CatalogTimingPolicy.retentionPastGrace)
                && kickoff <= now.addingTimeInterval(CatalogTimingPolicy.retentionFutureHorizon)
        }

        var normalizedCategory: String {
            AnalyticalDataEngine.normalizedCategoryKey(category)
        }

        var categoryDisplayName: String {
            AnalyticalDataEngine.categoryDisplayName(for: normalizedCategory)
        }

        var homeName: String {
            if isBroadcastChannel { return title ?? "Cricket channel" }
            if let sportsFixture, sportsFixture.eventKind != .match { return sportsFixture.title }
            if let explicit = teams?.home?.name, !explicit.isEmpty {
                return explicit
            }
            return splitTeamsFromTitle().home
        }

        var awayName: String {
            if isBroadcastChannel { return "" }
            if let sportsFixture, sportsFixture.eventKind != .match { return "" }
            if let explicit = teams?.away?.name, !explicit.isEmpty {
                return explicit
            }
            return splitTeamsFromTitle().away
        }

        var homeBadgeURL: URL? {
            guard !hasCatalogIdentityConflict else { return nil }
            return AnalyticalDataEngine.imageURL(from: teams?.home?.badge)
                ?? TeamBrandService.sportSpecificBadgeURL(for: homeName, category: normalizedCategory)
        }

        var awayBadgeURL: URL? {
            guard !hasCatalogIdentityConflict else { return nil }
            return AnalyticalDataEngine.imageURL(from: teams?.away?.badge)
                ?? TeamBrandService.sportSpecificBadgeURL(for: awayName, category: normalizedCategory)
        }

        var posterURL: URL? {
            hasCatalogIdentityConflict ? nil : AnalyticalDataEngine.imageURL(from: poster)
        }

        private func splitTeamsFromTitle() -> (home: String, away: String) {
            guard let title, !title.isEmpty else {
                return ("Home", "Away")
            }

            let separators = [" vs ", " v ", " @ ", " - "]
            for separator in separators {
                let parts = title.components(separatedBy: separator)
                if parts.count == 2 {
                    let home = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let away = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !home.isEmpty && !away.isEmpty {
                        return (home, away)
                    }
                }
            }

            return (title, "Away")
        }

        init(from match: FootballMatch) {
            // Schedule identities are canonical across catalog fallback,
            // Match Center, notifications, and playback. A presentation-layer
            // prefix here used to create a second identity for the same match.
            self.id = String(match.id)
            self.title = "\(match.homeTeam.displayName) vs \(match.awayTeam.displayName)"
            self.category = "football"

            // Convert ISO8601 string to timestamp
            let dateObj = match.matchDate ?? Date()
            self.date = Int64(dateObj.timeIntervalSince1970)

            self.poster = match.competition.emblem
            self.popular = match.competition.code == "PL" || match.competition.code == "CL"
            self.teams = NexusATeams(
                home: NexusATeam(name: match.homeTeam.displayName, badge: match.homeTeam.crest),
                away: NexusATeam(name: match.awayTeam.displayName, badge: match.awayTeam.crest)
            )
            // An official fixture is schedule truth, not evidence that a
            // provider has published a playable route.
            self.sources = []
            self.hasCatalogIdentityConflict = false
            self.cricketFixture = nil
            self.sportsFixture = nil
            switch AnalyticalDataEngine.officialCompetitionTab(match.competition) {
            case .premierLeague: self.competitionID = "premier-league"
            case .championsLeague: self.competitionID = "champions-league"
            case .laLiga: self.competitionID = "la-liga"
            case .serieA: self.competitionID = "serie-a"
            case .bundesliga: self.competitionID = "bundesliga"
            case .ligue1: self.competitionID = "ligue-1"
            default: self.competitionID = nil
            }
        }
    }



    @MainActor
    static func categoryDisplayName(for rawCategory: String) -> String {
        switch rawCategory {
        case "football", "soccer":
            return "Football"
        case "american-football", "nfl":
            return "American football"
        case "motor-sports", "motorsports":
            return "Motorsport"
        case "afl":
            return "AFL"
        case "basketball":
            return "Basketball"
        case "baseball":
            return "Baseball"
        case "hockey":
            return "Hockey"
        case "fight", "mma", "boxing":
            return "Fight"
        default:
            if rawCategory.isEmpty || rawCategory == "other" {
                return "Other"
            }
            return rawCategory.capitalized
        }
    }

    enum FootballLeagueTab: String, CaseIterable, Identifiable {
        case all
        case premierLeague
        case championsLeague
        case laLiga
        case serieA
        case bundesliga
        case ligue1
        case other

        var id: String { rawValue }

        @MainActor
        var displayName: String {
            switch self {
            case .all:
                return "All Football"
            case .premierLeague:
                return "Premier League"
            case .championsLeague:
                return "Champions League"
            case .laLiga:
                return "La Liga"
            case .serieA:
                return "Serie A"
            case .bundesliga:
                return "Bundesliga"
            case .ligue1:
                return "Ligue 1"
            case .other:
                return "Other Leagues"
            }
        }

        var badgeURL: URL? {
            switch self {
            case .premierLeague: return URL(string: "https://media.api-sports.io/football/leagues/39.png")
            case .championsLeague: return URL(string: "https://media.api-sports.io/football/leagues/2.png")
            case .laLiga: return URL(string: "https://media.api-sports.io/football/leagues/140.png")
            case .serieA: return URL(string: "https://media.api-sports.io/football/leagues/135.png")
            case .bundesliga: return URL(string: "https://media.api-sports.io/football/leagues/78.png")
            case .ligue1: return URL(string: "https://media.api-sports.io/football/leagues/61.png")
            default: return nil
            }
        }
    }

    enum FootballLeagueEvidence: String, Equatable {
        case officialFixture
        case providerMarker
        case rosterInference
        case nonDomesticMarker
        case unresolvedProviderMarker
        case none
    }

    struct FootballLeagueClassification: Equatable {
        let tab: FootballLeagueTab
        let evidence: FootballLeagueEvidence
        let reasonCode: String?

        var isIdentityConflict: Bool { evidence == .unresolvedProviderMarker }
    }

    static func sportIconName(for rawCategory: String) -> String {
        SportIdentity.symbol(for: rawCategory)
    }

    static func footballLeagueTabs(for matches: [EventReference]) -> [FootballLeagueTab] {
        [
            .all,
            .premierLeague,
            .championsLeague,
            .laLiga,
            .serieA,
            .bundesliga,
            .ligue1,
            .other
        ]
    }

    static func footballLeagueTab(
        for match: EventReference,
        officialMatch: FootballMatch? = nil
    ) -> FootballLeagueTab {
        footballLeagueClassification(for: match, officialMatch: officialMatch).tab
    }

    /// Converts the independently verified schedule into source-free catalog
    /// rows. Home/Matchday can therefore show a Champions League fixture even
    /// before a stream provider publishes it, without inventing Watch access.
    static func officialScheduleEvents(
        from matches: [FootballMatch],
        competition: FootballLeagueTab
    ) -> [EventReference] {
        matches.compactMap { match in
            guard officialCompetitionTab(match.competition) == competition,
                  match.matchDate != nil else { return nil }
            return EventReference(from: match)
        }
    }

    /// Official fixture identity wins only after `LiveScoreService` has matched
    /// both teams and a bounded kickoff. Provider metadata and seasonal rosters
    /// remain deterministic fallbacks when that reconciliation is unavailable.
    static func footballLeagueClassification(
        for match: EventReference,
        officialMatch: FootballMatch? = nil
    ) -> FootballLeagueClassification {
        guard !match.hasCatalogIdentityConflict else {
            return FootballLeagueClassification(tab: .other, evidence: .unresolvedProviderMarker,
                reasonCode: "conflicting_catalog_identity")
        }
        if let officialMatch {
            return FootballLeagueClassification(
                tab: officialCompetitionTab(officialMatch.competition),
                evidence: .officialFixture,
                reasonCode: nil
            )
        }

        if let fixture = match.sportsFixture, fixture.sport == "football" {
            let tabs: [String: FootballLeagueTab] = ["premier-league": .premierLeague,
                "champions-league": .championsLeague, "la-liga": .laLiga, "serie-a": .serieA,
                "bundesliga": .bundesliga, "ligue-1": .ligue1]
            if let tab = tabs[fixture.competitionID] {
                return FootballLeagueClassification(tab: tab,
                    evidence: fixture.verified ? .officialFixture : .providerMarker, reasonCode: nil)
            }
        }

        let sourceIdentity = match.sources?
            .map { "\($0.source) \($0.id)" }
            .joined(separator: " ") ?? ""
        let haystack = "\(match.id) \(match.title ?? "") \(sourceIdentity)".lowercased()
        let isCurrentPair: (FootballCompetitionID) -> Bool = { competition in
            FootballCompetitionCatalog.containsBoth(
                home: match.homeName,
                away: match.awayName,
                in: competition
            )
        }

        if containsAny(in: haystack, terms: ["champions league", "uefa champions", "champions-league", "ucl"]) {
            return FootballLeagueClassification(tab: .championsLeague, evidence: .providerMarker, reasonCode: nil)
        }
        let domesticMarkers: [(FootballLeagueTab, FootballCompetitionID, [String])] = [
            (.premierLeague, .premierLeague, ["premier league", "english premier", "premier-league", "epl"]),
            (.laLiga, .laLiga, ["la liga", "laliga", "la-liga"]),
            (.serieA, .serieA, ["serie a", "serie-a"]),
            (.bundesliga, .bundesliga, ["bundesliga"]),
            (.ligue1, .ligue1, ["ligue 1", "ligue-1", "ligue1"]),
        ]
        for (tab, competition, markers) in domesticMarkers where containsAny(in: haystack, terms: markers) {
            if hasNonDomesticCompetitionMarker(haystack) {
                return FootballLeagueClassification(tab: .other, evidence: .nonDomesticMarker, reasonCode: "non_domestic_marker")
            }
            guard isCurrentPair(competition) else {
                return FootballLeagueClassification(
                    tab: .other,
                    evidence: .unresolvedProviderMarker,
                    reasonCode: "provider_marker_membership_conflict"
                )
            }
            return FootballLeagueClassification(tab: tab, evidence: .providerMarker, reasonCode: nil)
        }
        if hasNonDomesticCompetitionMarker(haystack) {
            return FootballLeagueClassification(tab: .other, evidence: .nonDomesticMarker, reasonCode: "non_domestic_marker")
        }

        if isCurrentPair(.premierLeague) {
            return FootballLeagueClassification(tab: .premierLeague, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.laLiga) {
            return FootballLeagueClassification(tab: .laLiga, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.serieA) {
            return FootballLeagueClassification(tab: .serieA, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.bundesliga) {
            return FootballLeagueClassification(tab: .bundesliga, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.ligue1) {
            return FootballLeagueClassification(tab: .ligue1, evidence: .rosterInference, reasonCode: nil)
        }

        return FootballLeagueClassification(tab: .other, evidence: .none, reasonCode: nil)
    }

    private static func officialCompetitionTab(_ competition: MatchCompetition) -> FootballLeagueTab {
        switch competition.id {
        case 39, 2021: return .premierLeague
        case 2, 2001: return .championsLeague
        case 140, 2014: return .laLiga
        case 135, 2019: return .serieA
        case 78, 2002: return .bundesliga
        case 61, 2015: return .ligue1
        default: break
        }

        switch competition.code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PL": return .premierLeague
        case "CL": return .championsLeague
        case "PD": return .laLiga
        case "SA": return .serieA
        case "BL1": return .bundesliga
        case "FL1": return .ligue1
        default: break
        }

        let name = competition.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let country = competition.country?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["champions league", "uefa champions league"].contains(name) { return .championsLeague }
        if ["premier league", "english premier league", "england premier league"].contains(name),
           country.isEmpty || country == "england" { return .premierLeague }
        if ["la liga", "primera division", "primera división"].contains(name), country.isEmpty || country == "spain" { return .laLiga }
        if name == "serie a", country.isEmpty || country == "italy" { return .serieA }
        if name == "bundesliga", country.isEmpty || country == "germany" { return .bundesliga }
        if ["ligue 1", "ligue1"].contains(name), country.isEmpty || country == "france" { return .ligue1 }
        return .other
    }

    // MARK: - Private

    static func deduplicateMatches(_ matches: [EventReference]) -> [EventReference] {
        var accumulator = MatchDeduplicationAccumulator(capacity: matches.count)
        for match in matches { accumulator.acceptID(match) }
        for match in accumulator.matchesByID { accumulator.acceptFixture(match) }
        return accumulator.merged
    }

    /// Home yields between bounded batches while retaining exactly the same
    /// two-pass identity/merge rules as synchronous callers. Intermediate rows
    /// stay local; cancellation or a newer request discards the whole result.
    /// The work count covers both passes and permits deterministic batch tests
    /// without publishing fixture identities or partially prepared snapshots.
    static func deduplicateMatchesCooperatively(
        _ matches: [EventReference],
        isCurrent: () -> Bool,
        checkpoint: (_ processedRows: Int) async -> Bool
    ) async -> [EventReference]? {
        func acceptsRequest() -> Bool { !Task.isCancelled && isCurrent() }
        guard acceptsRequest() else { return nil }
        var accumulator = MatchDeduplicationAccumulator(capacity: matches.count)
        var processedRows = 0
        func suspend() async -> Bool {
            guard acceptsRequest() else { return false }
            guard await checkpoint(processedRows) else { return false }
            return acceptsRequest()
        }
        for (index, match) in matches.enumerated() {
            guard acceptsRequest() else { return nil }
            accumulator.acceptID(match)
            processedRows += 1
            if (index + 1).isMultiple(of: 32), !(await suspend()) { return nil }
        }
        if !matches.count.isMultiple(of: 32), !(await suspend()) { return nil }
        for (index, match) in accumulator.matchesByID.enumerated() {
            guard acceptsRequest() else { return nil }
            accumulator.acceptFixture(match)
            processedRows += 1
            if (index + 1).isMultiple(of: 32), !(await suspend()) { return nil }
        }
        if !accumulator.matchesByID.count.isMultiple(of: 32), !(await suspend()) { return nil }
        guard acceptsRequest() else { return nil }
        return accumulator.merged
    }

    @MainActor
    private struct MatchDeduplicationAccumulator {
        private(set) var matchesByID: [EventReference] = []
        private var indicesByID: [String: Int] = [:]
        private var fixtureIndices: [String: Int] = [:]
        private(set) var merged: [EventReference] = []

        init(capacity: Int) {
            matchesByID.reserveCapacity(capacity)
            indicesByID.reserveCapacity(capacity)
        }

        mutating func acceptID(_ match: EventReference) {
            guard let index = indicesByID[match.id] else {
                indicesByID[match.id] = matchesByID.count
                matchesByID.append(match)
                return
            }
            let existing = matchesByID[index]
            guard !existing.hasCatalogIdentityConflict else { return }
            guard !match.hasCatalogIdentityConflict, existing.kickoffDate == match.kickoffDate,
                  CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: existing), in: [match]) != nil else {
                // One quarantined ID remains in the resolver snapshot, not two
                // Identifiable rows in UI and not a fabricated empty success.
                matchesByID[index] = EventReference(id: existing.id, title: existing.title,
                    category: existing.category, date: existing.date, poster: existing.poster,
                    popular: existing.popular, teams: existing.teams, sources: [],
                    hasCatalogIdentityConflict: true, cricketFixture: existing.cricketFixture,
                    sportsFixture: existing.sportsFixture, competitionID: existing.competitionID)
                return
            }
            var seenSources = Set<String>()
            let sources = ((existing.sources ?? []) + (match.sources ?? [])).filter {
                seenSources.insert("\($0.source)|\($0.id)").inserted
            }
            matchesByID[index] = EventReference(id: existing.id, title: existing.title,
                category: existing.category, date: existing.date, poster: existing.poster,
                popular: existing.popular, teams: existing.teams,
                sources: sources.isEmpty && existing.sources == nil && match.sources == nil ? nil : sources,
                cricketFixture: existing.cricketFixture ?? match.cricketFixture,
                sportsFixture: existing.sportsFixture ?? match.sportsFixture,
                competitionID: existing.competitionID ?? match.competitionID)
        }

        // Different provider families sometimes assign different event IDs to
        // the same fixture. Collapse them only when sport, exact kickoff and
        // both reviewed whole-team identities agree. This preserves genuine
        // doubleheaders and keeps youth/reserve fixtures distinct.
        mutating func acceptFixture(_ event: EventReference) {
            guard !event.hasCatalogIdentityConflict,
                  let fixtureKey = AnalyticalDataEngine.duplicateFixtureKey(for: event) else {
                merged.append(event)
                return
            }
            guard let index = fixtureIndices[fixtureKey] else {
                fixtureIndices[fixtureKey] = merged.count
                merged.append(event)
                return
            }

            let existing = merged[index]
            if let previous = existing.sportsFixture, let current = event.sportsFixture,
               previous.fixtureID != current.fixtureID {
                // Two official IDs at the same instant are an ambiguity, not
                // permission to combine doubleheaders or overwrite a receipt.
                merged.append(event)
                return
            }
            let preferred: EventReference
            let secondary: EventReference
            if (existing.sources?.isEmpty ?? true), !(event.sources?.isEmpty ?? true) {
                preferred = event
                secondary = existing
            } else {
                preferred = existing
                secondary = event
            }
            var seenSources = Set<String>()
            let sources = ((preferred.sources ?? []) + (secondary.sources ?? [])).filter {
                seenSources.insert("\($0.source)|\($0.id)").inserted
            }
            merged[index] = EventReference(
                id: preferred.id,
                title: preferred.title ?? secondary.title,
                category: preferred.category ?? secondary.category,
                date: preferred.date ?? secondary.date,
                poster: preferred.poster ?? secondary.poster,
                popular: preferred.popular ?? secondary.popular,
                teams: preferred.teams ?? secondary.teams,
                sources: sources,
                cricketFixture: preferred.cricketFixture ?? secondary.cricketFixture,
                sportsFixture: preferred.sportsFixture ?? secondary.sportsFixture,
                competitionID: preferred.competitionID ?? secondary.competitionID
            )
        }
    }

    private static func duplicateFixtureKey(for event: EventReference) -> String? {
        guard !event.isBroadcastChannel,
              let kickoff = event.kickoffDate,
              event.homeName != "Home", event.awayName != "Away",
              !event.homeName.isEmpty, !event.awayName.isEmpty else { return nil }
        let category = event.normalizedCategory
        func teamKey(_ name: String) -> String {
            if category == "football", let club = FootballCompetitionCatalog.canonicalClubID(for: name) {
                return "football:\(club)"
            }
            if let known = SportsTeamIdentity.known(name: name, category: category) {
                return "known:\(known.id)"
            }
            return "raw:\(SportsTeamIdentity.normalized(name))"
        }
        let competition = event.competitionID ?? ""
        let squad = category == "football" ? CatalogPlaybackIdentity.footballSquadIdentity(for: event).sorted().joined(separator: ",") : ""
        return "\(category)|\(competition)|\(Int64(kickoff.timeIntervalSince1970))|\(teamKey(event.homeName))|\(teamKey(event.awayName))|\(squad)"
    }

    static func normalizedCategoryKey(_ rawCategory: String?) -> String {
        let raw = rawCategory?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !raw.isEmpty else { return "other" }

        switch raw {
        case "soccer":
            return "football"
        case "mma", "boxing", "ufc", "pfl", "bellator", "one":
            return "fight"
        case "nba", "wnba", "ncaab", "ncaa", "fiba", "euroleague", "acb", "bbl":
            return "basketball"
        case "mlb", "npb", "kbo":
            return "baseball"
        case "nhl", "khl", "ahl":
            return "hockey"
        case "nfl", "american football":
            return "american-football"
        case "atp", "wta":
            return "tennis"
        case "motor-sports", "motorsports", "f1", "formula 1":
            return "motorsport"
        case "pga":
            return "golf"
        default:
            return raw
        }
    }

    private static func containsAny(in text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private static func hasNonDomesticCompetitionMarker(_ text: String) -> Bool {
        containsAny(in: text, terms: [
            "premier league 2", "premier-league-2", "premier league cup", "premier-league-cup",
            "fa cup", "fa-cup", "efl cup", "efl-cup", "league cup", "carabao",
            "community shield", "championship", "league one", "league-one", "league two",
            "league-two", "bundesliga 2", "2. bundesliga", "copa del rey", "coppa italia", "dfb pokal", "coupe de france",
            "europa league", "conference league", "friendly", " u18", " u19", " u21", " u23",
            "women", "ladies", "youth", "academy", "reserves",
        ])
    }

    static func imageURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }

        if raw.hasPrefix("/api/") {
            let s = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0x1A, 0x6, 0x8, 0x13, 0x16, 0x24, 0x1C, 0x36, 0x6, 0xC, 0x11, 0x15, 0x6C, 0x7, 0xF, 0x1A, 0x16, 0x1D, 0xA, 0x6, 0x5D, 0x35, 0x5D, 0x2B]) // "https://streamed.pk"
            let sx = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1B, 0xE, 0x3, 0x47, 0x10, 0x7, 0x24, 0x57, 0x27, 0x2, 0x11, 0xC, 0x57, 0x2F, 0xB, 0x15]) // "https://www.nx.net"
            return URL(string: s + raw) ?? URL(string: sx + raw)
        }

        // Most badge values are opaque provider tokens. They are not paths and
        // must be sent through the provider's badge-image endpoint.
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
        let badgeBase = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x56, 0x68, 0x1F, 0x1F, 0x5B, 0x18, 0x31, 0x7, 0x4E, 0x5, 0x14, 0x15, 0xE, 0x6, 0x0, 0x79, 0x50, 0x27, 0xB, 0x13, 0x11, 0x56])
        return URL(string: badgeBase + "\(encoded).webp")
    }

}
