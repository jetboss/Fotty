import Foundation
import SwiftData

/// Additive local interests: no model migration or inference from a temporary
/// Home filter. Existing team and competition choices remain independent.
enum SportsInterestPreferences {
    static let storageKey = "fotty.sports.followedSportIDs.v1"
    static let emptyValue = "[]"
    static let orderedIDs = ["football", "cricket", "basketball", "baseball", "tennis", "hockey",
                             "fight", "american-football", "motorsport", "golf", "rugby", "volleyball", "darts"]
    // Local interests can cover sports beyond a versioned continuity contract.
    static let supportedIDs = Set(orderedIDs)
    enum StorageError: Error { case invalidSelection, invalidStoredValue, writeNotVerified }
    typealias Writer = (String, String, UserDefaults) throws -> Void

    static func canonicalIDs(from raw: String) -> Set<String> { decodedIDs(from: raw) ?? [] }

    static func decodedIDs(from raw: String) -> Set<String>? {
        guard raw.utf8.count <= 2_048, let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data),
              values.count <= supportedIDs.count, Set(values).count == values.count,
              Set(values).isSubset(of: supportedIDs) else { return nil }
        return Set(values)
    }

    static func selectedIDs(in defaults: UserDefaults) -> Set<String> {
        (try? validatedIDs(in: defaults)) ?? []
    }

    static func validatedIDs(in defaults: UserDefaults) throws -> Set<String> {
        guard let stored = defaults.object(forKey: storageKey) else { return [] }
        guard let raw = stored as? String, let ids = decodedIDs(from: raw) else { throw StorageError.invalidStoredValue }
        return ids
    }

    static func encodedValue(for ids: Set<String>) -> String? {
        guard ids.isSubset(of: supportedIDs), let data = try? JSONEncoder().encode(ids.sorted()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setEnabled(_ sport: String, enabled: Bool, in defaults: UserDefaults = .standard,
                           writer: Writer = { value, key, defaults in defaults.set(value, forKey: key) }) throws {
        guard supportedIDs.contains(sport) else { throw StorageError.invalidSelection }
        var ids = try validatedIDs(in: defaults)
        if enabled { ids.insert(sport) } else { ids.remove(sport) }
        guard let next = encodedValue(for: ids) else { throw StorageError.invalidSelection }
        if defaults.string(forKey: storageKey) == next { return }
        try writer(next, storageKey, defaults)
        guard defaults.string(forKey: storageKey) == next else { throw StorageError.writeNotVerified }
    }
}

@MainActor
enum SportsPersonalizationPolicy {
    /// Cheap, value-based invalidation: edits/replacements matter even when the
    /// number of saved interests stays unchanged. No normalization runs here.
    struct SelectionIdentity: Hashable {
        struct Team: Hashable {
            let name: String
            let category: String
        }
        struct Competition: Hashable {
            let id: String
            let name: String
            let category: String
        }
        let teams: [Team]
        let competitions: [Competition]
        var sports: [String] = []
    }

    /// Reviewed aliases and legacy compatibility are resolved once for a
    /// selection, not again for every catalog row and every view-body update.
    struct PreparedSelection: Hashable {
        let identity: SelectionIdentity
        let teamKeys: Set<String>
        let leagueIDs: Set<String>
        let sportIDs: Set<String>
    }

    static func selectionIdentity(
        teams: [FollowedTeamItem], leagues: [FollowedLeagueItem], sports: Set<String> = []
    ) -> SelectionIdentity {
        SelectionIdentity(
            teams: teams.map { SelectionIdentity.Team(name: $0.teamName, category: $0.sportCategory) }
                .sorted { $0.category == $1.category ? $0.name < $1.name : $0.category < $1.category },
            competitions: leagues.map { SelectionIdentity.Competition(id: $0.id, name: $0.leagueName, category: $0.sportCategory) }
                .sorted {
                    if $0.category != $1.category { return $0.category < $1.category }
                    return $0.id == $1.id ? $0.name < $1.name : $0.id < $1.id
                },
            sports: sports.intersection(SportsInterestPreferences.supportedIDs).sorted()
        )
    }

    static func prepareSelection(
        teams: [FollowedTeamItem], leagues: [FollowedLeagueItem], sports: Set<String> = []
    ) -> PreparedSelection {
        PreparedSelection(
            identity: selectionIdentity(teams: teams, leagues: leagues, sports: sports),
            teamKeys: followedTeamKeys(teams),
            leagueIDs: Set(leagues.compactMap { league(for: $0)?.id }),
            sportIDs: sports.intersection(SportsInterestPreferences.supportedIDs)
        )
    }

    struct League: Identifiable, Equatable {
        let id: String
        let name: String
        let sportCategory: String
        let country: String
        let markers: [String]
    }

    static let leagues: [League] = [
        .init(id: "premier-league", name: "Premier League", sportCategory: "football", country: "England", markers: []),
        .init(id: "la-liga", name: "La Liga", sportCategory: "football", country: "Spain", markers: []),
        .init(id: "serie-a", name: "Serie A", sportCategory: "football", country: "Italy", markers: []),
        .init(id: "bundesliga", name: "Bundesliga", sportCategory: "football", country: "Germany", markers: []),
        .init(id: "ligue-1", name: "Ligue 1", sportCategory: "football", country: "France", markers: []),
        .init(id: "champions-league", name: "Champions League", sportCategory: "football", country: "Europe", markers: []),
        .init(id: "carabao-cup", name: "Carabao Cup", sportCategory: "football", country: "England", markers: []),
        .init(id: "mls", name: "MLS", sportCategory: "football", country: "USA / Canada", markers: ["mls"]),
        .init(id: "cpl", name: "Caribbean Premier League", sportCategory: "cricket", country: "Caribbean", markers: []),
        .init(id: "nba", name: "NBA", sportCategory: "basketball", country: "USA / Canada", markers: ["nba"]),
        .init(id: "wnba", name: "WNBA", sportCategory: "basketball", country: "USA / Canada", markers: ["wnba"]),
        .init(id: "mlb", name: "MLB", sportCategory: "baseball", country: "USA / Canada", markers: ["mlb"]),
        .init(id: "nhl", name: "NHL", sportCategory: "hockey", country: "USA / Canada", markers: ["nhl"]),
        .init(id: "nfl", name: "NFL", sportCategory: "american-football", country: "USA", markers: ["nfl"])
    ]

    static func league(for stored: FollowedLeagueItem) -> League? {
        leagues.first {
            $0.sportCategory == SportsTeamIdentity.sport(stored.sportCategory)
                && ($0.id == stored.id || SportsTeamIdentity.normalized($0.name) == SportsTeamIdentity.normalized(stored.leagueName)
                    || ($0.id == "cpl" && SportsTeamIdentity.normalized(stored.leagueName) == "cpl"))
        }
    }

    /// Compatibility reads make legacy aliases usable before migration, including
    /// exact reviewed multisport results the former picker saved as football.
    static func identity(for item: FollowedTeamItem) -> SportsTeamIdentity {
        let category = SportsTeamIdentity.sport(item.sportCategory) ?? item.sportCategory
        let known = SportsTeamIdentity.known(name: item.teamName, category: category)
            ?? (category == "football" ? SportsTeamIdentity.known(name: item.teamName) : nil)
        return SportsTeamIdentity(displayName: known?.displayName ?? item.teamName,
                                  sportCategory: known?.sportCategory ?? category,
                                  badgeURL: item.badgeURLString.flatMap(URL.init(string:)) ?? known?.badgeURL)
    }

    static func followedTeamKeys(_ items: [FollowedTeamItem]) -> Set<String> {
        Set(items.map { item in
            let identity = identity(for: item)
            return TeamFollowKey.make(name: identity.displayName, category: identity.sportCategory)
        })
    }

    static func isFollowed(event: AnalyticalDataEngine.EventReference,
                           teamKeys: Set<String>, leagueItems: [FollowedLeagueItem],
                           officialMatch: FootballMatch? = nil) -> Bool {
        guard !event.isBroadcastChannel, !event.hasCatalogIdentityConflict else { return false }
        return teamKeys.contains(TeamFollowKey.make(name: event.homeName, category: event.normalizedCategory))
            || teamKeys.contains(TeamFollowKey.make(name: event.awayName, category: event.normalizedCategory))
            || followedLeagueName(for: event, in: leagueItems, officialMatch: officialMatch) != nil
    }

    static func isFollowed(event: AnalyticalDataEngine.EventReference,
                           selection: PreparedSelection,
                           officialMatch: FootballMatch? = nil) -> Bool {
        guard !event.isBroadcastChannel, !event.hasCatalogIdentityConflict else { return false }
        return selection.sportIDs.contains(event.normalizedCategory)
            || selection.teamKeys.contains(TeamFollowKey.make(name: event.homeName, category: event.normalizedCategory))
            || selection.teamKeys.contains(TeamFollowKey.make(name: event.awayName, category: event.normalizedCategory))
            || followedLeagueName(for: event, in: selection, officialMatch: officialMatch) != nil
    }

    static func followedLeagueName(for event: AnalyticalDataEngine.EventReference,
                                    in selection: PreparedSelection,
                                    officialMatch: FootballMatch? = nil) -> String? {
        guard !selection.leagueIDs.isEmpty,
              let identified = league(for: event, officialMatch: officialMatch),
              selection.leagueIDs.contains(identified.id) else { return nil }
        return identified.name
    }

    static func followedLeagueName(for event: AnalyticalDataEngine.EventReference,
                                    in items: [FollowedLeagueItem],
                                    officialMatch: FootballMatch? = nil) -> String? {
        guard let identified = league(for: event, officialMatch: officialMatch),
              items.contains(where: { league(for: $0)?.id == identified.id }) else { return nil }
        return identified.name
    }

    static func league(for event: AnalyticalDataEngine.EventReference,
                       officialMatch: FootballMatch? = nil) -> League? {
        guard !event.isBroadcastChannel, !event.hasCatalogIdentityConflict else { return nil }
        if officialMatch == nil, let fixture = event.sportsFixture {
            return leagues.first { $0.id == fixture.competitionID && $0.sportCategory == fixture.sport }
        }
        if event.normalizedCategory == "cricket", event.isCPLFixture {
            let isVerifiedScheduleRow = CPLSchedule.isManagedFixtureID(event.id)
            let hasTwoKnownTeams: Bool = {
                guard let home = SportsTeamIdentity.known(name: event.homeName, category: "cricket"),
                      let away = SportsTeamIdentity.known(name: event.awayName, category: "cricket") else { return false }
                return home.id != away.id
            }()
            // Verified schedule rows include knockout placeholders whose teams
            // are not known until qualification is settled. They still belong
            // to a saved CPL interest. Untrusted provider/editorial rows must
            // continue to prove two reviewed CPL teams.
            if isVerifiedScheduleRow || hasTwoKnownTeams {
                return leagues.first { $0.id == "cpl" }
            }
        }
        if event.normalizedCategory == "football" {
            let classification = AnalyticalDataEngine.footballLeagueClassification(for: event, officialMatch: officialMatch)
            let tab = classification.tab
            // Bare club names can be shared by different squads and can meet
            // outside their domestic league. Roster inference remains useful
            // for catalog browsing, but is not competition-follow evidence.
            if classification.evidence != .rosterInference, tab != .all && tab != .other {
                return leagues.first { $0.name == tab.displayName && $0.sportCategory == "football" }
            }
            // An official non-MLS competition must never be replaced by a marker.
            if let officialMatch,
               !(officialMatch.competition.name ?? "").localizedCaseInsensitiveContains("major league soccer"),
               officialMatch.competition.code?.uppercased() != "MLS" { return nil }
        }
        let evidence = [event.id, event.title ?? "", event.category ?? ""]
        let tokens = Set(SportsTeamIdentity.normalized(evidence.joined(separator: " ")).split(separator: " ").map(String.init))
        let matches = leagues.filter {
            $0.sportCategory == event.normalizedCategory && !$0.markers.isEmpty
                && $0.markers.contains(where: tokens.contains)
        }
        return matches.count == 1 ? matches.first : nil
    }
}

/// Background/non-view mutations use an isolated context so a failure cannot
/// discard an unrelated editor's pending work. The explicit view mutation below
/// instead uses SwiftUI's observed context so its `@Query` refreshes immediately.
@MainActor
enum SportsPersonalizationStore {
    /// SwiftUI's `@Query` reads the environment's ModelContext. Mutations made
    /// in another context are durable but aren't guaranteed to refresh that
    /// query immediately. Interest-editor actions therefore use this same
    /// view context so Home reflects the new competition as soon as the user
    /// navigates back.
    static func setLeagueFromView(
        _ league: SportsPersonalizationPolicy.League,
        enabled: Bool,
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        // Commit any already-valid UI edit first so rollback below is scoped to
        // this toggle rather than silently discarding another pending change.
        if context.hasChanges { try save(context) }
        let matches = try context.fetch(FetchDescriptor<FollowedLeagueItem>()).filter {
            SportsPersonalizationPolicy.league(for: $0)?.id == league.id
        }
        if !enabled {
            matches.forEach { context.delete($0) }
        } else if matches.isEmpty {
            context.insert(FollowedLeagueItem(id: league.id, leagueName: league.name,
                                              sportCategory: league.sportCategory, country: league.country))
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Search's explicit Follow action uses the observed view context so Home
    /// and Matchday update immediately, with rollback scoped to this one edit.
    static func setFollowFromView(_ identity: SportsTeamIdentity, enabled: Bool, in context: ModelContext,
                                  save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        if context.hasChanges { try save(context) }
        let known = SportsTeamIdentity.known(name: identity.displayName, category: identity.sportCategory)
        let identity = SportsTeamIdentity(displayName: known?.displayName ?? identity.displayName,
                                         sportCategory: known?.sportCategory ?? SportsTeamIdentity.sport(identity.sportCategory) ?? identity.sportCategory.lowercased(),
                                         badgeURL: identity.badgeURL ?? known?.badgeURL)
        let matches = try context.fetch(FetchDescriptor<FollowedTeamItem>()).filter {
            SportsPersonalizationPolicy.identity(for: $0).id == identity.id
        }
        if !enabled { matches.forEach { context.delete($0) } }
        else if matches.isEmpty {
            context.insert(FollowedTeamItem(key: TeamFollowKey.make(name: identity.displayName, category: identity.sportCategory),
                                          teamName: identity.displayName, sportCategory: identity.sportCategory,
                                          badgeURLString: identity.badgeURL?.absoluteString))
        }
        do { try save(context) }
        catch { context.rollback(); throw error }
    }

    static func setFollow(_ identity: SportsTeamIdentity, enabled: Bool, in context: ModelContext,
                          save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let known = SportsTeamIdentity.known(name: identity.displayName, category: identity.sportCategory)
        let identity = SportsTeamIdentity(displayName: known?.displayName ?? identity.displayName,
                                         sportCategory: known?.sportCategory ?? SportsTeamIdentity.sport(identity.sportCategory) ?? identity.sportCategory.lowercased(),
                                         badgeURL: identity.badgeURL ?? known?.badgeURL)
        let writer = writer(for: context)
        let matches = try writer.fetch(FetchDescriptor<FollowedTeamItem>()).filter {
            SportsPersonalizationPolicy.identity(for: $0).id == identity.id
        }
        if !enabled {
            matches.forEach { writer.delete($0) }
        } else if matches.isEmpty {
            writer.insert(FollowedTeamItem(key: TeamFollowKey.make(name: identity.displayName, category: identity.sportCategory),
                                          teamName: identity.displayName, sportCategory: identity.sportCategory,
                                          badgeURLString: identity.badgeURL?.absoluteString))
        }
        try save(writer)
    }

    static func setAlerts(_ enabled: Bool, teamKeys: Set<String>, in context: ModelContext,
                          save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let writer = writer(for: context)
        for item in try writer.fetch(FetchDescriptor<FollowedTeamItem>()) where teamKeys.contains(SportsPersonalizationPolicy.identity(for: item).id) {
            item.alertsEnabled = enabled
        }
        try save(writer)
    }

    static func removeTeams(keys: Set<String>, in context: ModelContext,
                            save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let writer = writer(for: context)
        for item in try writer.fetch(FetchDescriptor<FollowedTeamItem>()) where keys.contains(SportsPersonalizationPolicy.identity(for: item).id) {
            writer.delete(item)
        }
        try save(writer)
    }

    static func setLeague(_ league: SportsPersonalizationPolicy.League, enabled: Bool, in context: ModelContext,
                          save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let writer = writer(for: context)
        let matches = try writer.fetch(FetchDescriptor<FollowedLeagueItem>()).filter { SportsPersonalizationPolicy.league(for: $0)?.id == league.id }
        if !enabled { matches.forEach { writer.delete($0) } }
        else if matches.isEmpty {
            writer.insert(FollowedLeagueItem(id: league.id, leagueName: league.name,
                                            sportCategory: league.sportCategory, country: league.country))
        }
        try save(writer)
    }

    static func migrateTeamIdentities(in context: ModelContext,
                                      save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let writer = writer(for: context)
        let items = try writer.fetch(FetchDescriptor<FollowedTeamItem>())
        let groups = Dictionary(grouping: items) { SportsPersonalizationPolicy.identity(for: $0).id }
        for group in groups.values {
            guard let keeper = group.sorted(by: { $0.createdAt < $1.createdAt }).first else { continue }
            let identity = SportsPersonalizationPolicy.identity(for: keeper)
            let muted = group.contains { $0.alertsEnabled == false }
            let badge = group.compactMap(\.badgeURLString).first ?? identity.badgeURL?.absoluteString
            for duplicate in group where duplicate !== keeper { writer.delete(duplicate) }
            keeper.key = TeamFollowKey.make(name: identity.displayName, category: identity.sportCategory)
            keeper.teamName = identity.displayName
            keeper.sportCategory = identity.sportCategory
            keeper.badgeURLString = badge
            keeper.alertsEnabled = !muted
        }
        if writer.hasChanges { try save(writer) }
    }

    private static func writer(for context: ModelContext) -> ModelContext {
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        return writer
    }
}
