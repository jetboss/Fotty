import SwiftUI
import SwiftData

/// Search history stays on this installation. It is neither a viewing history
/// nor an iCloud intent, and records deliberate searches rather than typing.
enum SportsSearchHistory {
    static let storageKey = "fotty.search.recentQueries.v1"
    static let emptyValue = "[]"
    static let maximumCount = 8
    static let maximumQueryLength = 120

    static func cleanedQuery(_ value: String) -> String {
        String(value.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maximumQueryLength))
    }

    private static func identity(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }

    static func queries(from raw: String) -> [String] {
        guard raw.utf8.count <= 4_096, let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        var queries: [String] = []
        for value in values {
            let query = cleanedQuery(value)
            guard !query.isEmpty, seen.insert(identity(query)).inserted else { continue }
            queries.append(query)
            if queries.count == maximumCount { break }
        }
        return queries
    }

    static func recording(_ query: String, in raw: String) -> String {
        let query = cleanedQuery(query)
        guard !query.isEmpty else { return raw }
        let previous = queries(from: raw).filter { identity($0) != identity(query) }
        let next = Array(([query] + previous).prefix(maximumCount))
        guard let data = try? JSONEncoder().encode(next), let value = String(data: data, encoding: .utf8) else { return raw }
        return value
    }
}

@MainActor
enum SportsSearchShortcuts {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let query: String
        var team: SportsTeamIdentity? = nil
    }

    static func following(teams: [FollowedTeamItem], leagues: [FollowedLeagueItem], sports: Set<String>) -> [Item] {
        var items: [Item] = []
        var seen = Set<String>()
        for team in teams {
            let identity = SportsPersonalizationPolicy.identity(for: team)
            guard seen.insert("team-\(identity.id)").inserted else { continue }
            items.append(.init(id: "team-\(identity.id)", title: identity.displayName,
                               detail: AnalyticalDataEngine.categoryDisplayName(for: identity.sportCategory),
                               query: identity.displayName, team: identity))
        }
        for stored in leagues {
            guard let league = SportsPersonalizationPolicy.league(for: stored),
                  seen.insert("league-\(league.id)").inserted else { continue }
            items.append(.init(id: "league-\(league.id)", title: league.name,
                               detail: "Competition", query: league.name))
        }
        for sport in SportsInterestPreferences.orderedIDs where sports.contains(sport) {
            let title = AnalyticalDataEngine.categoryDisplayName(for: sport)
            items.append(.init(id: "sport-\(sport)", title: title, detail: "Sport", query: title))
        }
        return items
    }

    /// Search text is never enough to create a new team. Only an exact,
    /// unambiguous alias from the reviewed identity catalog may be followed.
    static func verifiedTeam(for query: String) -> SportsTeamIdentity? {
        SportsTeamIdentity.known(name: SportsSearchHistory.cleanedQuery(query))
    }
}

/// Search uses Home's current catalog plus a wider source-free projection of
/// the same accepted schedules. Queries never create another feed or fetch.
@MainActor
enum HomeSportsSearch {
    private struct LeagueIdentity {
        let markers: [String]
        let searchTerms: String
    }

    /// Nexus normalizes most events to a sport category, so league identity is
    /// sometimes retained only in an event/source identifier. Expose only a
    /// reviewed category-scoped vocabulary here; never dump opaque provider
    /// identifiers into the user-facing search haystack.
    private static let nonFootballLeagues: [String: [LeagueIdentity]] = [
        "basketball": [
            .init(markers: ["nba"], searchTerms: "NBA National Basketball Association"),
            .init(markers: ["wnba"], searchTerms: "WNBA Women's National Basketball Association"),
            .init(markers: ["ncaab", "ncaa"], searchTerms: "NCAA NCAAB college basketball"),
            .init(markers: ["fiba"], searchTerms: "FIBA"),
            .init(markers: ["euroleague"], searchTerms: "EuroLeague"),
            .init(markers: ["nbl"], searchTerms: "NBL National Basketball League")
        ],
        "baseball": [
            .init(markers: ["mlb"], searchTerms: "MLB Major League Baseball"),
            .init(markers: ["npb"], searchTerms: "NPB Nippon Professional Baseball"),
            .init(markers: ["kbo"], searchTerms: "KBO Korea Baseball Organization")
        ],
        "hockey": [
            .init(markers: ["nhl"], searchTerms: "NHL National Hockey League"),
            .init(markers: ["khl"], searchTerms: "KHL Kontinental Hockey League"),
            .init(markers: ["ahl"], searchTerms: "AHL American Hockey League")
        ],
        "american-football": [
            .init(markers: ["nfl"], searchTerms: "NFL National Football League"),
            .init(markers: ["ufl"], searchTerms: "UFL United Football League"),
            .init(markers: ["cfl"], searchTerms: "CFL Canadian Football League"),
            .init(markers: ["ncaaf", "ncaa"], searchTerms: "NCAA NCAAF college football")
        ],
        "nfl": [
            .init(markers: ["nfl"], searchTerms: "NFL National Football League")
        ],
        "cricket": [
            .init(markers: ["ipl"], searchTerms: "IPL Indian Premier League"),
            .init(markers: ["cpl"], searchTerms: "CPL Caribbean Premier League"),
            .init(markers: ["psl"], searchTerms: "PSL Pakistan Super League"),
            .init(markers: ["bbl"], searchTerms: "BBL Big Bash League")
        ],
        "fight": [
            .init(markers: ["ufc"], searchTerms: "UFC Ultimate Fighting Championship"),
            .init(markers: ["pfl"], searchTerms: "PFL Professional Fighters League"),
            .init(markers: ["bellator"], searchTerms: "Bellator")
        ],
        "tennis": [
            .init(markers: ["atp"], searchTerms: "ATP Association of Tennis Professionals"),
            .init(markers: ["wta"], searchTerms: "WTA Women's Tennis Association")
        ],
        "golf": [
            .init(markers: ["pga"], searchTerms: "PGA Professional Golfers Association"),
            .init(markers: ["lpga"], searchTerms: "LPGA Ladies Professional Golf Association")
        ],
        "motorsport": [
            .init(markers: ["f1"], searchTerms: "F1 Formula 1 Formula One"),
            .init(markers: ["motogp"], searchTerms: "MotoGP"),
            .init(markers: ["nascar"], searchTerms: "NASCAR"),
            .init(markers: ["indycar"], searchTerms: "IndyCar")
        ]
    ]

    enum Result: Identifiable {
        case fixture(HomeSportsDiscovery.Item)
        case channel(AnalyticalDataEngine.EventReference)

        var id: String { event.id }
        var event: AnalyticalDataEngine.EventReference {
            switch self {
            case .fixture(let item): item.event
            case .channel(let event): event
            }
        }
    }

    static func results(
        in discovery: HomeSportsDiscovery,
        query: String,
        leagueName: (AnalyticalDataEngine.EventReference) -> String? = { _ in nil }
    ) -> [Result] {
        prepare(in: discovery, leagueName: leagueName).results(query: query)
    }

    struct Index {
        struct Entry {
            let result: Result
            let normalizedLeague: String
            let haystack: String
            let reviewedTeamIDs: Set<String>
        }
        let entries: [Entry]
        let exactFootballLeagues: Set<String>

        func results(query: String) -> [Result] {
            let normalizedQuery = HomeSportsSearch.normalized(query)
            let tokens = normalizedQuery.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { return [] }
            let exactLeague = exactFootballLeagues.contains(normalizedQuery)
            // Keep literal search broad. An exact reviewed alias additionally
            // finds canonical rows, without guessing an identity from tokens.
            let reviewedQueryTeam = exactLeague ? nil : SportsTeamIdentity.known(name: query)
            let reviewedTeamID = reviewedQueryTeam.flatMap { team in
                team.sportCategory == "football"
                    ? HomeSportsSearch.reviewedFootballSearchID(for: query)
                    : team.id
            }
            return entries.compactMap { entry in
                let matches = exactLeague
                    ? entry.normalizedLeague == normalizedQuery
                    : tokens.allSatisfy(entry.haystack.contains)
                        || reviewedTeamID.map { entry.reviewedTeamIDs.contains($0) } == true
                return matches ? entry.result : nil
            }
        }
    }

    /// Normalize catalog fields once per owner revision, never per body read or
    /// per keystroke. This is presentation data only; it owns no network request.
    static func prepare(in discovery: HomeSportsDiscovery,
                        scheduledEvents: [EventReference] = [],
                        status: (EventReference) -> FootballMatch.MatchStatus? = { _ in nil },
                        leagueName: (AnalyticalDataEngine.EventReference) -> String? = { _ in nil }) -> Index {
        let results = searchResults(in: discovery, scheduledEvents: scheduledEvents, status: status)
        return makeIndex(entries: results.map { entry(for: $0, leagueName: leagueName) })
    }

    /// Native presentation and keyboard work can share the actor with Search.
    /// Keep preparation unpublished and suspend between bounded value batches;
    /// an empty prompt does not need any catalog normalization at all.
    static func prepareForQuery(
        in discovery: HomeSportsDiscovery,
        query: String,
        scheduledEvents: [EventReference] = [],
        status: (EventReference) -> FootballMatch.MatchStatus? = { _ in nil },
        leagueName: (AnalyticalDataEngine.EventReference) -> String? = { _ in nil },
        isCurrent: () -> Bool = { true },
        timing: FottyAsyncTiming? = nil
    ) async -> Index? {
        let timing = timing ?? .live
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              await checkpoint(isCurrent: isCurrent, timing: timing) else { return nil }
        let results = searchResults(in: discovery, scheduledEvents: scheduledEvents, status: status)
        var entries: [Index.Entry] = []
        entries.reserveCapacity(results.count)
        for (index, result) in results.enumerated() {
            guard !Task.isCancelled, isCurrent() else { return nil }
            entries.append(entry(for: result, leagueName: leagueName))
            if (index + 1).isMultiple(of: 16) {
                guard await checkpoint(isCurrent: isCurrent, timing: timing) else { return nil }
            }
        }
        guard !Task.isCancelled, isCurrent() else { return nil }
        return makeIndex(entries: entries)
    }

    private static func searchResults(in discovery: HomeSportsDiscovery,
                                      scheduledEvents: [EventReference],
                                      status: (EventReference) -> FootballMatch.MatchStatus?) -> [Result] {
        guard !scheduledEvents.isEmpty else {
            return discovery.items.map(Result.fixture) + discovery.channels.map(Result.channel)
        }
        let currentEvents = discovery.items.map(\.event) + discovery.channels
        let currentIDs = Set(currentEvents.map(\.id))
        let latest = discovery.now.addingTimeInterval(SportsSearchSchedule.futureHorizon)
        let additional = scheduledEvents.filter { event in
            guard !currentIDs.contains(event.id), !event.hasCatalogIdentityConflict,
                  !event.isBroadcastChannel,
                  let start = event.kickoffDate, start > discovery.now, start <= latest else { return false }
            if let fixture = event.sportsFixture { return fixture.verified && fixture.status == .scheduled }
            if let fixture = event.cricketFixture { return fixture.verified && fixture.status == .scheduled }
            return CPLSchedule.isManagedFixtureID(event.id)
        }
        let officialStatuses: [String: FootballMatch.MatchStatus] = Dictionary(uniqueKeysWithValues:
            discovery.items.compactMap { item in item.officialStatus.map { (item.id, $0) } })
        let expanded = HomeSportsDiscovery(events: currentEvents + additional, now: discovery.now,
                                           status: { status($0) ?? officialStatuses[$0.id] })
        return expanded.items.map(Result.fixture) + expanded.channels.map(Result.channel)
    }

    /// A supplemental schedule row must not borrow a result from another day
    /// or squad. Reuse the reviewed dated-pair admission without treating an
    /// official schedule ID as a score-provider ID.
    static func scoreIdentityMatches(_ event: EventReference, score: EventReference) -> Bool {
        guard event.normalizedCategory == "football", score.normalizedCategory == "football",
              !event.hasCatalogIdentityConflict,
              CatalogPlaybackIdentity.footballSquadIdentity(for: event)
                == CatalogPlaybackIdentity.footballSquadIdentity(for: score) else { return false }
        let request = StreamPlaybackRequest(matchID: event.id, displayTitle: event.displayTitle,
            homeTeam: event.homeName, awayTeam: event.awayName, category: "football", kickoffDate: event.kickoffDate)
        return CatalogPlaybackIdentity.matchingEvent(for: request, in: [score]) != nil
    }

    static func checkpoint(isCurrent: () -> Bool, timing: FottyAsyncTiming? = nil) async -> Bool {
        let timing = timing ?? .live
        // Unlike a bare yield, this actually releases the main actor before
        // the next batch. Cancellation interrupts the bounded one-ms pause.
        do { try await timing.wait(for: .milliseconds(1)) }
        catch { return false }
        return !Task.isCancelled && isCurrent()
    }

    private static func makeIndex(entries: [Index.Entry]) -> Index {
        let exactFootballLeagues = Set(
            AnalyticalDataEngine.FootballLeagueTab.allCases
                .filter { $0 != .all && $0 != .other }
                .map { normalized($0.displayName) }
        )
        return Index(entries: entries, exactFootballLeagues: exactFootballLeagues)
    }

    private static func entry(for result: Result,
                              leagueName: (AnalyticalDataEngine.EventReference) -> String?) -> Index.Entry {
        let event = result.event
        let league = leagueName(event) ?? ""
        var fields = [
            event.displayTitle,
            event.title ?? "",
            event.homeName,
            event.awayName,
            event.normalizedCategory,
            event.categoryDisplayName,
            event.sportsFixture?.competitionName ?? "",
            event.sportsFixture?.competitionID ?? "",
            league
        ]
        // A saved team's shortcut uses its reviewed canonical name. Resolve
        // exact provider aliases once while preparing this revision, so e.g.
        // "Man Utd" remains findable as "Manchester United" without fuzzy,
        // cross-sport or reserve-squad inference during each keystroke.
        let participantNames = [event.homeName, event.awayName]
        let reviewedTeams = participantNames.compactMap {
            SportsTeamIdentity.known(name: $0, category: event.normalizedCategory)
        }
        fields.append(contentsOf: reviewedTeams.map(\.displayName))
        fields.append(contentsOf: inferredLeagueTerms(for: event))
        if event.isCPLFixture { fields.append("Caribbean Premier League CPL") }
        if event.isBroadcastChannel { fields.append("channel broadcast") }
        let reviewedTeamIDs: Set<String>
        if event.normalizedCategory == "football" {
            // Official schedules retain legal suffixes such as Forest FC;
            // display formatting alone removes them. Reuse the reviewed club
            // join, without making a women's/youth receipt a senior identity.
            reviewedTeamIDs = CatalogPlaybackIdentity.footballSquadIdentity(for: event).isEmpty
                ? Set(participantNames.compactMap { reviewedFootballSearchID(for: $0) }) : []
        } else {
            reviewedTeamIDs = Set(reviewedTeams.map(\.id))
        }
        return Index.Entry(result: result, normalizedLeague: normalized(league),
                           haystack: normalized(fields.joined(separator: " ")),
                           reviewedTeamIDs: reviewedTeamIDs)
    }

    nonisolated private static func reviewedFootballSearchID(for name: String) -> String? {
        FootballCompetitionCatalog.canonicalClubID(for: name).map { "football-club|\($0)" }
    }

    // Pure value normalization has no UI/service state; the prepared index can
    // filter its immutable fields without inheriting the catalog actor.
    nonisolated private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .joined(separator: " ")
    }

    private static func inferredLeagueTerms(
        for event: AnalyticalDataEngine.EventReference
    ) -> [String] {
        guard let identities = nonFootballLeagues[event.normalizedCategory] else {
            return []
        }
        let evidence = [event.id, event.title ?? "", event.category ?? ""]
        let tokens = Set(
            normalized(evidence.joined(separator: " "))
                .split(separator: " ")
                .map(String.init)
        )
        return identities.compactMap { identity in
            identity.markers.contains(where: tokens.contains) ? identity.searchTerms : nil
        }
    }
}

struct SportsSearchIndexKey: Hashable {
    let catalogRevision: Int
    let clockDate: Date
    let scoreRevision: Date?
    let scheduleRevision: Int

    init(catalogRevision: Int, clockDate: Date, scoreRevision: Date?, scheduleRevision: Int = 0) {
        self.catalogRevision = catalogRevision
        self.clockDate = clockDate
        self.scoreRevision = scoreRevision
        self.scheduleRevision = scheduleRevision
    }
}

/// Typing changes the result request, not the catalog being normalized. The
/// empty/nonempty transition still owns whether preparation is needed at all.
struct SportsSearchPreparationKey: Hashable {
    let index: SportsSearchIndexKey
    let needsIndex: Bool

    init(index: SportsSearchIndexKey, query: String) {
        self.index = index
        needsIndex = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SportsSearchResultsKey: Hashable {
    let index: SportsSearchIndexKey
    let query: String
}

private struct SportsSearchResultsTaskKey: Hashable {
    let results: SportsSearchResultsKey
    let hasPreparedIndex: Bool
}

/// The production suggestion label is also available to hosted layout checks;
/// it contains no search, history, account or follow mutation of its own.
struct SportsSearchShortcutLabel: View {
    let title: String
    var detail: String? = nil
    var symbol: String = "clock"
    var team: SportsTeamIdentity? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let team {
                TeamBadgeWindow(teamName: team.displayName, badgeURL: team.badgeURL,
                                size: 28, glowEnabled: false)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(FottyTheme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(FottyTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SearchView: View {
    let discovery: HomeSportsDiscovery
    let isSaved: (AnalyticalDataEngine.EventReference) -> Bool
    let canWatch: (AnalyticalDataEngine.EventReference) -> Bool
    let alternateActionTitle: (AnalyticalDataEngine.EventReference) -> String?
    let onOpen: (AnalyticalDataEngine.EventReference) -> Void
    let onDetails: (AnalyticalDataEngine.EventReference) -> Void
    let onSave: (AnalyticalDataEngine.EventReference) -> MyMatchdayStore.MutationResult
    var onCheckStreams: ((AnalyticalDataEngine.EventReference) -> Void)? = nil
    var catalogNoticeForEvents: (([AnalyticalDataEngine.EventReference]) -> String?)? = nil
    var catalogCheckedAt: Date? = nil
    var isRefreshing = false
    var onRefresh: (() async -> Void)? = nil
    var catalogRevision = 0
    var scheduledEvents: (() -> [EventReference])? = nil
    var scheduleRevision = 0

    @SceneStorage(BrowsingStateKey.searchQuery) private var restoredQuery = ""
    // The native field owns an immediate editing buffer. Scene restoration is
    // a checkpoint, not a second participant in every keyboard transaction.
    @State private var query = ""
    @State private var didRestoreQuery = false
    @AppStorage(SportsSearchHistory.storageKey) private var recentQueriesRaw = SportsSearchHistory.emptyValue
    @AppStorage(SportsInterestPreferences.storageKey) private var followedSportIDsRaw = SportsInterestPreferences.emptyValue
    @Query(sort: \FollowedTeamItem.teamName, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query(sort: \FollowedLeagueItem.leagueName, order: .forward) private var followedLeagues: [FollowedLeagueItem]
    @State private var saveError: String?
    @State private var saveErrorTitle = "Couldn't update My Matchday"
    @State private var hasColumnWidth = false
    @State private var preparedIndex: HomeSportsSearch.Index?
    @State private var preparedIndexKey: SportsSearchIndexKey?
    @State private var resultsSnapshot: [HomeSportsSearch.Result] = []
    @State private var resultsSnapshotKey: SportsSearchResultsKey?
    @State private var resultPresentations: [String: HomeDiscoveryRow.Presentation] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    private var usesWideLayout: Bool { hasColumnWidth && !dynamicTypeSize.isAccessibilitySize }

    private var results: [HomeSportsSearch.Result] {
        resultsSnapshotKey == resultsKey ? resultsSnapshot : []
    }

    private var indexKey: SportsSearchIndexKey {
        .init(catalogRevision: catalogRevision, clockDate: discovery.now,
              scoreRevision: liveScoreService.lastRefresh, scheduleRevision: scheduleRevision)
    }
    private var resultsKey: SportsSearchResultsKey { .init(index: indexKey, query: query) }
    private var preparationKey: SportsSearchPreparationKey { .init(index: indexKey, query: query) }
    private var resultsTaskKey: SportsSearchResultsTaskKey {
        let hasIndex: Bool
        if preparedIndexKey == indexKey, let _ = preparedIndex { hasIndex = true }
        else { hasIndex = false }
        return .init(results: resultsKey, hasPreparedIndex: hasIndex)
    }

    private var recentQueries: [String] { SportsSearchHistory.queries(from: recentQueriesRaw) }
    private var followingShortcuts: [SportsSearchShortcuts.Item] {
        SportsSearchShortcuts.following(teams: followedTeams, leagues: followedLeagues,
                                       sports: SportsInterestPreferences.canonicalIDs(from: followedSportIDsRaw))
    }

    private var catalogNotice: String? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return catalogNoticeForEvents?(results.map(\.event))
    }

    var body: some View {
        NavigationStack {
            // Keep the searchable host stable as typing replaces prompt,
            // progress and results. A conditional Group is not a container.
            VStack(spacing: 0) {
                Group {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        promptState
                    } else if resultsSnapshotKey != resultsKey {
                        ProgressView("Searching…")
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FottyTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                if let catalogNotice, let onRefresh {
                    CatalogRefreshNotice(message: catalogNotice, checkedAt: catalogCheckedAt,
                                         isRefreshing: isRefreshing,
                                         onRefresh: onRefresh)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Team, league, sport, or channel"
            )
            .searchSuggestions {
                if query.isEmpty {
                    if !recentQueries.isEmpty {
                        Section("Recent searches") {
                            ForEach(recentQueries, id: \.self) { suggestion in
                                Text(suggestion).searchCompletion(suggestion)
                            }
                        }
                    }
                    if !followingShortcuts.isEmpty {
                        Section("Your interests") {
                            ForEach(followingShortcuts) { item in
                                Text(item.title).searchCompletion(item.query)
                            }
                        }
                    }
                }
            }
            .onSubmit(of: .search) { rememberQuery() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("global-sports-search")
        .onAppear {
            guard !didRestoreQuery else { return }
            query = String(restoredQuery.prefix(SportsSearchHistory.maximumQueryLength))
            didRestoreQuery = true
        }
        .onDisappear { checkpointQuery() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { checkpointQuery() }
        }
        .task(id: preparationKey) {
            let key = preparationKey
            guard key.needsIndex else { return }
            if preparedIndexKey == key.index, let _ = preparedIndex { return }
            // The query is only the helper's nonempty admission hint. A later
            // nonempty edit must not revoke query-independent catalog work.
            guard let prepared = await HomeSportsSearch.prepareForQuery(
                in: discovery, query: query, scheduledEvents: scheduledEvents?() ?? [],
                status: searchStatus(for:), leagueName: leagueName(for:),
                isCurrent: { key == preparationKey }
            ), !Task.isCancelled, key == preparationKey else { return }
            publishIndex(prepared, for: key.index)
        }
        .task(id: resultsTaskKey) {
            let key = resultsKey
            guard !key.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                guard !Task.isCancelled, key == resultsKey else { return }
                publishResults([], presentations: [:], for: key)
                return
            }
            // Index publication changes resultsTaskKey and resumes the latest
            // query. Never poll, publish partial normalization, or start a
            // second preparation task from a result request.
            guard preparedIndexKey == key.index, let index = preparedIndex else { return }
            guard await HomeSportsSearch.checkpoint(isCurrent: { key == resultsKey }) else { return }
            let found = index.results(query: key.query)
            var presentations: [String: HomeDiscoveryRow.Presentation] = [:]
            presentations.reserveCapacity(found.count)
            for (offset, result) in found.enumerated() {
                guard !Task.isCancelled, key == resultsKey else { return }
                if case .fixture(let item) = result {
                    presentations[item.id] = .init(item: item, scoreService: liveScoreService)
                }
                if (offset + 1).isMultiple(of: 16) {
                    guard await HomeSportsSearch.checkpoint(isCurrent: { key == resultsKey }) else { return }
                }
            }
            guard !Task.isCancelled, key == resultsKey else { return }
            publishResults(found, presentations: presentations, for: key)
        }
        .onGeometryChange(for: Bool.self) { geometry in
            FottyLayoutPolicy.usesColumns(width: geometry.size.width)
        } action: { hasColumnWidth = $0 }
        .onChange(of: query) { _, value in
            if value.count > 120 { query = String(value.prefix(120)) }
        }
        .alert(saveErrorTitle, isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func publishIndex(_ index: HomeSportsSearch.Index, for key: SportsSearchIndexKey) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            preparedIndex = index
            preparedIndexKey = key
        }
    }

    private func publishResults(_ results: [HomeSportsSearch.Result],
                                presentations: [String: HomeDiscoveryRow.Presentation],
                                for key: SportsSearchResultsKey) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            resultPresentations = presentations
            resultsSnapshot = results
            resultsSnapshotKey = key
        }
    }

    private var promptState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                Text("Find a match or channel")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if !recentQueries.isEmpty || !followingShortcuts.isEmpty {
                    suggestionColumns {
                        VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                            recentSearchesSection
                            followedSearchesSection
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        if !discovery.activities.isEmpty {
                            sportSearchesSection
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                } else {
                    sportSearchesSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(FottyTheme.bentoInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var suggestionColumns: AnyLayout {
        usesWideLayout && !discovery.activities.isEmpty
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: FottyTheme.spacingLG))
    }

    @ViewBuilder private var recentSearchesSection: some View {
        if !recentQueries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        recentSearchesHeading.fixedSize()
                        Spacer(minLength: 0)
                        clearRecentSearchesButton.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        recentSearchesHeading
                        clearRecentSearchesButton
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(recentQueries.enumerated()), id: \.element) { index, recent in
                        if index > 0 { shortcutDivider }
                        shortcutButton(title: recent, detail: nil, symbol: "clock", query: recent)
                    }
                }
                .background(FottyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var recentSearchesHeading: some View {
        Text("Recent searches")
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var clearRecentSearchesButton: some View {
        Button("Clear") { recentQueriesRaw = SportsSearchHistory.emptyValue }
            .font(.subheadline)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .accessibilityLabel("Clear recent searches on this device")
            .accessibilityIdentifier("search-clear-recents")
    }

    @ViewBuilder private var followedSearchesSection: some View {
        let shortcuts = followingShortcuts
        if !shortcuts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your interests").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { shortcutDivider }
                        shortcutButton(title: item.title, detail: item.detail, symbol: "star", query: item.query,
                                       team: item.team)
                    }
                }
                .background(FottyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    @ViewBuilder private var sportSearchesSection: some View {
        if !discovery.activities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sports in the lineup").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                // Reuse the approved sport-art grid's measured reflow rather
                // than fit long sport names into fixed-height text buttons.
                SportTileGridLayout(minimumTileWidth: dynamicTypeSize.isAccessibilitySize ? 220 : 94,
                                    maximumColumns: dynamicTypeSize.isAccessibilitySize ? 1 : 3) {
                    ForEach(discovery.activities) { activity in
                        let title = AnalyticalDataEngine.categoryDisplayName(for: activity.id)
                        Button { chooseSearch(title) } label: {
                            SportsSearchSportTileLabel(category: activity.id, title: title)
                        }
                        .buttonStyle(FottyPressButtonStyle())
                        .accessibilityIdentifier("search-sport-\(activity.id)")
                        .accessibilityHint("Searches current listings")
                    }
                }
            }
        }
    }

    private var shortcutDivider: some View {
        Divider().overlay(FottyTheme.border).padding(.leading, 52)
    }

    private func shortcutButton(title: String, detail: String?, symbol: String, query: String,
                                team: SportsTeamIdentity? = nil) -> some View {
        Button { chooseSearch(query) } label: {
            SportsSearchShortcutLabel(title: title, detail: detail, symbol: symbol, team: team)
        }
        .buttonStyle(FottyPressButtonStyle())
        .accessibilityHint("Searches available fixtures and channels")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No matching fixtures or channels", systemImage: "magnifyingglass")
        } description: {
            Text(catalogNotice == nil
                ? "No listing matches \"\(query)\" in the available schedules. Some broadcasts appear closer to kickoff."
                : "Listings couldn't be fully checked. Try again shortly.")
        } actions: {
            if let identity = SportsSearchShortcuts.verifiedTeam(for: query) {
                let following = SportsPersonalizationPolicy.followedTeamKeys(followedTeams).contains(identity.id)
                Button { followVerifiedTeam(identity) } label: {
                    Label(following ? "Following \(identity.displayName)" : "Follow \(identity.displayName)",
                          systemImage: following ? "checkmark.circle" : "plus.circle")
                        .frame(minHeight: 44)
                }
                .disabled(following)
                .accessibilityHint("Adds future fixtures to My Matchday when they appear in the lineup. Does not enable notifications.")
                .accessibilityIdentifier("search-follow-verified-team")
            }
            if let onRefresh, catalogNotice == nil {
                Button { Task { await onRefresh() } } label: {
                    Text(isRefreshing ? "Checking…" : "Refresh listings")
                        .frame(minHeight: 44)
                }
                    .buttonStyle(.bordered)
                    .tint(FottyTheme.accentText)
                    .disabled(isRefreshing)
            }
        }
    }

    private var resultsList: some View {
        let visibleResults = results
        let rows = FottyLayoutPolicy.rows(visibleResults, columns: usesWideLayout ? 2 : 1)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(resultSummary)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                  HStack(alignment: .top, spacing: 16) {
                   ForEach(row.items) { result in
                    VStack(spacing: 0) {
                        if index > 0 && !usesWideLayout {
                            Divider().overlay(FottyTheme.border).padding(.horizontal, 12)
                        }
                        resultRow(result)
                    }
                    .frame(maxWidth: .infinity)
                    .background(FottyTheme.surface)
                    // Keep each row lazy while rounding only the group ends.
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: usesWideLayout || index == 0 ? 16 : 0,
                        bottomLeadingRadius: usesWideLayout || index == rows.count - 1 ? 16 : 0,
                        bottomTrailingRadius: usesWideLayout || index == rows.count - 1 ? 16 : 0,
                        topTrailingRadius: usesWideLayout || index == 0 ? 16 : 0
                    ))
                   }
                   if usesWideLayout && row.items.count == 1 { Color.clear.frame(maxWidth: .infinity, minHeight: 0, maxHeight: 0).accessibilityHidden(true) }
                  }
                  .padding(.bottom, usesWideLayout ? 16 : 0)
                }
            }
            .padding(.horizontal, FottyTheme.bentoInset)
            .padding(.vertical, FottyTheme.spacingMD)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func resultRow(_ result: HomeSportsSearch.Result) -> some View {
        switch result {
        case .fixture(let item):
            HomeDiscoveryRow(
                item: item,
                presentation: resultPresentations[item.id] ?? .init(item: item, scoreService: liveScoreService),
                isSaved: isSaved(item.event),
                onOpen: { rememberQuery(); onOpen(item.event) },
                onSave: { save(item.event) },
                alternateActionTitle: alternateActionTitle(item.event),
                onDetails: { rememberQuery(); onDetails(item.event) },
                onCheckStreams: onCheckStreams.map { check in { rememberQuery(); check(item.event) } }
            )
            .padding(.horizontal, 12)
            .accessibilityIdentifier("search-result-\(item.id)")
        case .channel(let event):
            LiveEventCard(
                event: event,
                onWatchTap: canWatch(event) ? { rememberQuery(); onOpen(event) } : nil,
                onDetailsTap: { rememberQuery(); onDetails(event) },
                isSaved: isSaved(event),
                onSaveTap: { save(event) },
                grouped: true
            )
            .accessibilityIdentifier("search-result-\(event.id)")
        }
    }

    private var resultSummary: String {
        results.count == 1 ? "1 result" : "\(results.count) results"
    }

    private func save(_ event: AnalyticalDataEngine.EventReference) {
        rememberQuery()
        saveErrorTitle = "Couldn't update My Matchday"
        if let message = onSave(event).errorMessage { saveError = message }
    }

    private func chooseSearch(_ value: String) {
        query = SportsSearchHistory.cleanedQuery(value)
        rememberQuery()
    }

    private func rememberQuery() {
        checkpointQuery()
        recentQueriesRaw = SportsSearchHistory.recording(query, in: recentQueriesRaw)
    }

    private func checkpointQuery() {
        guard didRestoreQuery else { return }
        restoredQuery = query
    }

    private func followVerifiedTeam(_ identity: SportsTeamIdentity) {
        saveErrorTitle = "Couldn't follow this team"
        guard !LocalDataStore.shared.isUsingVolatileFallback else {
            saveError = "Teams cannot be saved while Fotty is using temporary storage. Restart Fotty and try again."
            return
        }
        do {
            try SportsPersonalizationStore.setFollowFromView(identity, enabled: true, in: modelContext)
            rememberQuery()
        } catch {
            saveError = "The team wasn't saved. Your previous choices are kept; please try again."
        }
    }

    private func searchStatus(for event: EventReference) -> FootballMatch.MatchStatus? {
        guard event.normalizedCategory == "football",
              let match = liveScoreService.findMatch(home: event.homeName, away: event.awayName,
                  near: event.kickoffDate, maximumKickoffDelta: CatalogPlaybackIdentity.kickoffTolerance),
              let kickoff = FootballNormalizer.parseISO8601Date(match.utcDate) else { return nil }
        let score = EventReference(id: "search-score-\(match.id)",
            title: "\(match.homeTeam.matchingName) vs \(match.awayTeam.matchingName)", category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: match.homeTeam.matchingName, badge: nil),
                         away: .init(name: match.awayTeam.matchingName, badge: nil)))
        guard HomeSportsSearch.scoreIdentityMatches(event, score: score) else { return nil }
        return liveScoreService.currentStatus(for: match, at: Date())
    }

    private func leagueName(for event: AnalyticalDataEngine.EventReference) -> String? {
        guard event.normalizedCategory == "football" else { return nil }
        let official = liveScoreService.findMatch(
            home: event.homeName,
            away: event.awayName,
            near: event.kickoffDate
        )
        return AnalyticalDataEngine.footballLeagueTab(for: event, officialMatch: official).displayName
    }
}

/// Accept the grid's common height on the visible label itself, so a wrapped
/// sport name cannot leave shorter neighboring button surfaces behind.
struct SportsSearchSportTileLabel: View {
    let category: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            SportEmblem(category: category, size: 30)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(FottyTheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: .infinity)
        .background(FottyTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
