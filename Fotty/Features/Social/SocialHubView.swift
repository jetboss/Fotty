import SwiftUI
import SwiftData

struct SocialHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]
    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query(sort: \SocialAccount.createdAt, order: .forward) private var socialAccounts: [SocialAccount]
    @Query(sort: \SocialFollowRelationship.createdAt, order: .forward) private var socialFollows: [SocialFollowRelationship]
    @Query(sort: \SocialNotificationItem.createdAt, order: .reverse) private var socialNotifications: [SocialNotificationItem]
    @Query(sort: \SocialActivityItem.createdAt, order: .reverse) private var socialActivities: [SocialActivityItem]
    @Query(sort: \SocialSafetyActionItem.createdAt, order: .reverse) private var socialSafetyActions: [SocialSafetyActionItem]
    @Query(sort: \SocialPendingActionItem.createdAt, order: .forward) private var pendingSocialActions: [SocialPendingActionItem]
    
    @StateObject private var badgeManager = NotificationBadgeManager.shared

    @State private var teamAlerts: [SocialTeamAlert] = []
    @State private var isLoadingAlerts = false
    @State private var alertsError: String?
    @State private var teamNewsHeadlines: [TeamNewsHeadline] = []
    @State private var isLoadingTeamNews = false
    @State private var teamNewsError: String?
    @State private var teamFollowSuggestions: [SocialTeamSuggestion] = []
    @State private var isLoadingTeamFollowSuggestions = false
    @State private var teamFollowSuggestionsError: String?
    @State private var teamFollowSearchText = ""
    @State private var selectedTeamBrowseLeague: String?
    @ObservedObject private var brandService = TeamBrandService.shared
    @State private var leagueBadgeURLsByLookup: [String: URL] = [:]
    @State private var leagueTeamCatalog: [String: [SocialLeagueCatalogTeam]] = [:]
    @State private var sportsDBLeagueCatalogByLeagueName: [String: SocialLeagueBadgeCatalog] = [:]
    @State private var isLoadingFootballBrandAssets = false
    @State private var lastFootballBrandAssetsAttemptAt: Date?
    @State private var lastFootballBrandAssetsRefreshAt: Date?
    @State private var activeSocialTab: SocialHubTab = .following

    @State private var searchText = ""
    @State private var searchScope: SocialDiscoveryScope = .all
    @State private var searchSort: SocialDiscoverySort = .relevance
    @State private var composerText = ""
    @State private var composerCategory = "general"
    @State private var replyDraftByActivityID: [String: String] = [:]
    @State private var expandedThreadIDs: Set<String> = []

    @State private var isShowingNotificationCenter = false
    @State private var localPersistenceError: String?
    @AppStorage("fotty.social.eulaAccepted") private var eulaAccepted = false
    @State private var isShowingEULA = false

    private let composerCategories = ["general", "matchday", "prediction", "reaction"]
    private let footballCompetitionCodesByLeagueName: [String: String] = [
        "Premier League": "PL",
        "Champions League": "CL",
        "La Liga": "PD",
        "Serie A": "SA",
        "Bundesliga": "BL1",
        "Ligue 1": "FL1"
    ]
    private let sportsDBLeagueNamesByLeagueName: [String: String] = [
        "Premier League": "English Premier League",
        "Championship": "English Championship",
        "La Liga": "Spanish La Liga",
        "La Liga 2": "Spanish La Liga 2",
        "Serie A": "Italian Serie A",
        "Serie B": "Italian Serie B",
        "Bundesliga": "German Bundesliga",
        "2. Bundesliga": "German 2 Bundesliga",
        "Ligue 1": "French Ligue 1",
        "Ligue 2": "French Ligue 2",
        "Primeira Liga": "Portuguese Primeira Liga",
        "Eredivisie": "Dutch Eredivisie",
        "Scottish Premiership": "Scottish Premier League",
        "Champions League": "Champions League",
        "UEFA Europa League": "Europa League",
        "Europa League": "Europa League",
        "Conference League": "Conference League",
        "MLS": "MLS",
        "Saudi Pro League": "Saudi Pro League",
        "Argentine Liga Profesional": "Argentine Primera Division",
        "Brasileirão": "Brazilian Serie A"
    ]

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    FottyTheme.background.ignoresSafeArea()

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                            socialTabRail
                            socialTabContent

                            Spacer(minLength: 80)
                        }
                        .padding(.top, FottyTheme.spacingSM)
                    }
                    .refreshable {
                        await refreshAllSocialData(reason: "pull-to-refresh")
                    }
                }
                .navigationTitle("Social")
                .navigationBarTitleDisplayMode(.large)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingNotificationCenter = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                if unreadNotificationsCount > 0 {
                                    Circle()
                                        .fill(FottyTheme.liveAccent)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            ensureLocalProfileExists()
            purgeRetiredSyntheticSocialData()
            purgeRetiredPendingActions()
            await refreshAllSocialData(reason: "social-tab-appear")
        }
        .onChange(of: followedTeamAlertSnapshot) { _, _ in
            Task {
                await refreshTeamFollowSuggestions()
                await refreshTeamAlerts()
                await refreshTeamNews()
            }
        }
        .onChange(of: selectedTeamBrowseLeague) { _, _ in
            Task {
                await refreshTeamFollowSuggestions(refreshBrandAssets: false)
            }
        }
        .onChange(of: socialFollows.count) { _, _ in
            Task { await refreshTeamAlerts() }
        }
        .onChange(of: socialNotifications.filter({ !$0.isRead }).count) { _, newCount in
            badgeManager.updateCount(newCount)
        }
        .sheet(isPresented: $isShowingEULA) {
            UserAgreementView {
                eulaAccepted = true
                isShowingEULA = false
            }
            .interactiveDismissDisabled(!eulaAccepted)
            .fottyStandardSheetChrome()
        }
        .onAppear {
            if !eulaAccepted {
                isShowingEULA = true
            }
        }
    }
    
    private var activeProfile: UserProfile? {
        profiles.first(where: { $0.id == "local-profile" }) ?? profiles.first
    }

    private var profileID: String {
        activeProfile?.id ?? "local-profile"
    }
    
    private var resolvedProfileDisplayName: String {
        let current = sanitizeDisplayName(activeProfile?.displayName ?? "")
        if !current.isEmpty, current.lowercased() != "guest" {
            return current
        }
        
        return current.isEmpty ? "Guest" : current
    }
    
    private var resolvedProfileUsername: String? {
        let current = sanitizeUsername(activeProfile?.username ?? "")
        if !current.isEmpty, current != "guestfan" {
            return current
        }
        
        return current.isEmpty ? nil : current
    }

    private var blockedAccountIDs: Set<String> {
        Set(
            socialSafetyActions
                .filter { $0.action == SocialSafetyAction.block.rawValue }
                .map(\.targetAccountID)
        )
    }

    private var mutedAccountIDs: Set<String> {
        Set(
            socialSafetyActions
                .filter { $0.action == SocialSafetyAction.mute.rawValue }
                .map(\.targetAccountID)
        )
    }

    private var followingRelationships: [SocialFollowRelationship] {
        socialFollows.filter { $0.followerProfileID == profileID }
    }

    private var followingAccountIDs: Set<String> {
        Set(followingRelationships.map(\.followedAccountID))
    }

    private var followedAccounts: [SocialAccount] {
        socialAccounts.filter {
            followingAccountIDs.contains($0.id) && !blockedAccountIDs.contains($0.id)
        }
    }

    private var persistedDiscoveryEntries: [SocialDiscoveryEntry] {
        socialAccounts.map { account in
            SocialDiscoveryEntry(
                id: account.id,
                username: account.username,
                displayName: account.displayName,
                bio: account.bio,
                avatarSymbol: account.avatarSymbol,
                favoriteCategory: account.favoriteCategory,
                isVerified: account.isVerified
            )
        }
    }
    
    private var discoverySourceEntries: [SocialDiscoveryEntry] {
        persistedDiscoveryEntries
    }
    
    private var discoverableEntries: [SocialDiscoveryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = discoverySourceEntries.filter { account in
            guard !blockedAccountIDs.contains(account.id) else { return false }
            
            switch searchScope {
            case .all:
                break
            case .football:
                guard account.favoriteCategory?.lowercased() == "football" else { return false }
            case .verified:
                guard account.isVerified else { return false }
            }
            
            guard !query.isEmpty else { return true }
            return account.displayName.lowercased().contains(query)
                || account.username.lowercased().contains(query)
                || (account.favoriteCategory?.lowercased().contains(query) ?? false)
        }
        
        switch searchSort {
        case .alphabetical:
            return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .verifiedFirst:
            return filtered.sorted { lhs, rhs in
                if lhs.isVerified != rhs.isVerified {
                    return lhs.isVerified && !rhs.isVerified
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        case .relevance:
            guard !query.isEmpty else {
                return filtered.sorted { lhs, rhs in
                    if lhs.isVerified != rhs.isVerified {
                        return lhs.isVerified && !rhs.isVerified
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
            
            func score(for entry: SocialDiscoveryEntry) -> Int {
                let display = entry.displayName.lowercased()
                let username = entry.username.lowercased()
                let category = entry.favoriteCategory?.lowercased() ?? ""
                if display == query || username == query { return 100 }
                if display.hasPrefix(query) || username.hasPrefix(query) { return 80 }
                if display.contains(query) || username.contains(query) { return 60 }
                if category.contains(query) { return 40 }
                return 0
            }
            
            return filtered.sorted { lhs, rhs in
                let lhsScore = score(for: lhs)
                let rhsScore = score(for: rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.isVerified != rhs.isVerified {
                    return lhs.isVerified && !rhs.isVerified
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }
    
    private var hasDiscoveryQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var areAllAccountsBlocked: Bool {
        searchScope == .all
            && !discoverySourceEntries.isEmpty
            && discoverableEntries.isEmpty
            && !hasDiscoveryQuery
    }
    
    private var blockedEntries: [SocialDiscoveryEntry] {
        discoverySourceEntries.filter { blockedAccountIDs.contains($0.id) }
    }
    
    private var mutedEntries: [SocialDiscoveryEntry] {
        discoverySourceEntries.filter {
            mutedAccountIDs.contains($0.id) && !blockedAccountIDs.contains($0.id)
        }
    }

    private var followerAccountIDs: Set<String> {
        Set(
            socialNotifications
                .filter { $0.type == "follower" }
                .compactMap(\.actorAccountID)
        )
    }

    private var followerAccounts: [SocialAccount] {
        socialAccounts.filter {
            followerAccountIDs.contains($0.id) && !blockedAccountIDs.contains($0.id)
        }
    }

    private var unreadNotificationsCount: Int {
        socialNotifications.filter { !$0.isRead }.count
    }

    private var visibleNotifications: [SocialNotificationItem] {
        Array(socialNotifications.prefix(6))
    }

    private var visibleFeed: [SocialActivityItem] {
        socialActivities.filter { !mutedAccountIDs.contains($0.actorProfileID) }
    }
    
    private var rootFeedItems: [SocialActivityItem] {
        visibleFeed.filter { item in
            !isReplyActivity(item) && !isReactionActivity(item)
        }
    }

    private var followedTeamAlertSnapshot: [String] {
        followedTeams
            .map { "\($0.key):\(($0.alertsEnabled ?? true) ? "1" : "0")" }
            .sorted()
    }
    
    private var followedTeamEntries: [FollowedTeamItem] {
        followedTeams.filter { !isLeagueFollowCategory($0.sportCategory) }
    }
    
    private var followedLeagueEntries: [FollowedTeamItem] {
        followedTeams.filter { isLeagueFollowCategory($0.sportCategory) }
    }
    
    private var followedTeamKeys: Set<String> {
        Set(followedTeamEntries.map(\.key))
    }
    
    private var followedLeagueNames: [String] {
        let names = followedLeagueEntries
            .map(\.teamName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }
    
    private var discoverLeagueSuggestions: [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        
        func register(_ rawValue: String?) {
            guard let rawValue else { return }
            let cleaned = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !cleaned.isEmpty else { return }
            let normalized = cleaned.lowercased()
            guard seen.insert(normalized).inserted else { return }
            ordered.append(cleaned)
        }
        
        teamFollowSuggestions.forEach { register($0.leagueName) }
        followedLeagueNames.forEach { register($0) }
        TeamNewsService.inferLeagueTopics(for: followedFootballTeamNames).forEach { register($0) }
        
        [
            "Champions League",
            "Premier League",
            "La Liga",
            "Serie A",
            "Bundesliga",
            "Ligue 1"
        ].forEach { register($0) }
        
        return ordered
    }
    
    private var followedFootballTeamNames: [String] {
        let names = followedTeamEntries
            .filter { team in
                let category = team.sportCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return category == "football" || category == "soccer"
            }
            .map(\.teamName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }
    
    private var followedFootballLeagueTopics: [String] {
        let cleaned = followedLeagueNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned
    }
    
    private var trimmedTeamFollowSearchText: String {
        teamFollowSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var hasTeamFollowSearchQuery: Bool {
        !trimmedTeamFollowSearchText.isEmpty
    }
    
    private var hasTeamBrowseContext: Bool {
        hasTeamFollowSearchQuery || selectedTeamBrowseLeague != nil
    }
    
    private func normalizedLeagueName(for suggestion: SocialTeamSuggestion) -> String {
        let cleaned = suggestion.leagueName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) ?? ""
        return cleaned.isEmpty ? "Other Leagues" : cleaned
    }
    
    private func normalizedBrandLookupKey(_ rawValue: String) -> String {
        rawValue
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func canonicalClubDisplayName(name: String?, shortName: String?, tla: String?) -> String {
        let preferred = (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty {
            let cleaned = preferred
                .replacingOccurrences(
                    of: "\\s+(fc|afc|cf|ac|sc)$",
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        
        let fallbackShort = (shortName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackShort.isEmpty {
            return fallbackShort
        }
        
        let fallbackTLA = (tla ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTLA.isEmpty ? "Unknown" : fallbackTLA
    }
    
    private func teamBrandLookupKeys(for teamName: String) -> Set<String> {
        let normalized = normalizedBrandLookupKey(teamName)
        guard !normalized.isEmpty else { return [] }
        
        var keys: Set<String> = [normalized]
        let stripped = normalized
            .replacingOccurrences(of: "\\b(fc|cf|afc|ac|sc)\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stripped.isEmpty {
            keys.insert(stripped)
        }
        return keys
    }
    
    private func leagueBrandLookupKeys(for leagueName: String) -> Set<String> {
        let normalized = normalizedBrandLookupKey(leagueName)
        guard !normalized.isEmpty else { return [] }
        
        var keys: Set<String> = [normalized]
        if normalized.hasPrefix("uefa ") {
            keys.insert(
                String(normalized.dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            keys.insert("uefa \(normalized)")
        }
        if normalized == "champions league" {
            keys.insert("uefa champions league")
        }
        if normalized == "europa league" {
            keys.insert("uefa europa league")
        }
        return keys
    }
    
    private func teamBadgeURL(for teamName: String) -> URL? {
        brandService.badgeURL(for: teamName)
    }
    
    private func badgeURLFromLookup(_ lookup: [String: URL], candidateNames: [String]) -> URL? {
        for name in candidateNames {
            for key in teamBrandLookupKeys(for: name) {
                if let url = lookup[key] {
                    return url
                }
            }
        }
        return nil
    }
    
    private func teamBadgeLookup(for team: SportsDBTeam) -> [String: URL] {
        guard let badgeRaw = team.strBadge,
              let badgeURL = URL(string: badgeRaw),
              !badgeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        
        var result: [String: URL] = [:]
        let candidateNames: [String] = {
            var names: [String] = []
            if let value = team.strTeam, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names.append(value)
            }
            if let value = team.strTeamShort, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names.append(value)
            }
            if let alternate = team.strTeamAlternate {
                names.append(contentsOf: alternate.components(separatedBy: ","))
            }
            return names
        }()
        
        for name in candidateNames {
            for key in teamBrandLookupKeys(for: name) where result[key] == nil {
                result[key] = badgeURL
            }
        }
        
        return result
    }
    
    private func fetchSportsDBLeagueBadgeCatalog(for leagueName: String) async -> SocialLeagueBadgeCatalog {
        if let cached = sportsDBLeagueCatalogByLeagueName[leagueName] {
            return cached
        }
        
        guard let sportsDBLeagueName = sportsDBLeagueNamesByLeagueName[leagueName] else {
            return .empty
        }
        
        guard var components = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/3/search_all_teams.php") else {
            return .empty
        }
        components.queryItems = [
            URLQueryItem(name: "l", value: sportsDBLeagueName)
        ]
        guard let url = components.url else { return .empty }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .empty
            }
            let decoded = try JSONDecoder().decode(SportsDBLeagueTeamsResponse.self, from: data)
            guard let teams = decoded.teams, !teams.isEmpty else {
                return .empty
            }
            
            var lookup: [String: URL] = [:]
            var catalogByName: [String: SocialLeagueCatalogTeam] = [:]
            
            for team in teams {
                let badgeLookup = teamBadgeLookup(for: team)
                for (key, value) in badgeLookup where lookup[key] == nil {
                    lookup[key] = value
                }
                
                let displayName = canonicalClubDisplayName(
                    name: team.strTeam,
                    shortName: team.strTeamShort,
                    tla: nil
                )
                let displayKey = normalizedBrandLookupKey(displayName)
                guard !displayKey.isEmpty else { continue }
                
                let badgeURL = badgeURLFromLookup(
                    badgeLookup,
                    candidateNames: [displayName, team.strTeam ?? "", team.strTeamShort ?? ""]
                )
                if let existing = catalogByName[displayKey] {
                    if existing.badgeURL == nil, badgeURL != nil {
                        catalogByName[displayKey] = SocialLeagueCatalogTeam(displayName: displayName, badgeURL: badgeURL)
                    }
                } else {
                    catalogByName[displayKey] = SocialLeagueCatalogTeam(displayName: displayName, badgeURL: badgeURL)
                }
            }

            if leagueName == "Premier League" {
                let remoteByMembershipKey = Dictionary(
                    catalogByName.values.compactMap { team -> (String, SocialLeagueCatalogTeam)? in
                        guard let officialName = PremierLeagueClubCatalog.officialName(for: team.displayName) else {
                            return nil
                        }
                        return (FootballDataPolicy.normalizedTeamMatchKey(officialName), team)
                    },
                    uniquingKeysWith: { existing, candidate in
                        existing.badgeURL != nil ? existing : candidate
                    }
                )
                catalogByName = Dictionary(
                    uniqueKeysWithValues: PremierLeagueClubCatalog.officialClubNames.map { officialName in
                        let membershipKey = FootballDataPolicy.normalizedTeamMatchKey(officialName)
                        let badgeURL = remoteByMembershipKey[membershipKey]?.badgeURL
                            ?? badgeURLFromLookup(lookup, candidateNames: [officialName])
                        return (
                            normalizedBrandLookupKey(officialName),
                            SocialLeagueCatalogTeam(displayName: officialName, badgeURL: badgeURL)
                        )
                    }
                )
            }
            
            let catalog = SocialLeagueBadgeCatalog(
                lookup: lookup,
                teams: catalogByName.values.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            )
            await MainActor.run {
                sportsDBLeagueCatalogByLeagueName[leagueName] = catalog
            }
            return catalog
        } catch {
            return .empty
        }
    }
    
    private func leagueBadgeURL(for leagueName: String) -> URL? {
        for key in leagueBrandLookupKeys(for: leagueName) {
            if let url = leagueBadgeURLsByLookup[key] {
                return url
            }
        }
        return nil
    }
    
    private var filteredTeamFollowSuggestions: [SocialTeamSuggestion] {
        let query = trimmedTeamFollowSearchText.lowercased()
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let selectedLeague = selectedTeamBrowseLeague?.lowercased()
        
        // In league-browse mode, anchor to canonical league catalog rows.
        if let selectedTeamBrowseLeague,
           let catalogTeams = leagueTeamCatalog[selectedTeamBrowseLeague],
           !catalogTeams.isEmpty {
            let leagueKey = normalizedBrandLookupKey(selectedTeamBrowseLeague)
            let catalogRows: [SocialTeamSuggestion] = catalogTeams.map { team in
                let followKey = teamFollowKey(name: team.displayName, category: "football")
                return SocialTeamSuggestion(
                    id: "\(followKey)::\(leagueKey)",
                    followKey: followKey,
                    teamName: team.displayName,
                    sportCategory: "football",
                    kickoff: nil,
                    leagueName: selectedTeamBrowseLeague,
                    badgeURL: team.badgeURL ?? teamBadgeURL(for: team.displayName)
                )
            }
            
            let queryFiltered: [SocialTeamSuggestion]
            if query.isEmpty || terms.isEmpty {
                queryFiltered = catalogRows
            } else {
                queryFiltered = catalogRows.filter { suggestion in
                    let haystack = [
                        suggestion.teamName.lowercased(),
                        suggestion.sportCategory.lowercased(),
                        selectedTeamBrowseLeague.lowercased()
                    ].joined(separator: " ")
                    return terms.allSatisfy { term in haystack.contains(term) }
                }
            }
            
            return queryFiltered.sorted {
                $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
            }
        }
        
        var filtered = teamFollowSuggestions.filter { suggestion in
            if let selectedLeague {
                let leagueName = normalizedLeagueName(for: suggestion).lowercased()
                guard leagueName == selectedLeague else { return false }
            }
            
            guard !query.isEmpty else { return true }
            guard !terms.isEmpty else { return true }
            
            let haystack = [
                suggestion.teamName.lowercased(),
                suggestion.sportCategory.lowercased(),
                normalizedLeagueName(for: suggestion).lowercased()
            ]
            .joined(separator: " ")
            
            return terms.allSatisfy { term in
                haystack.contains(term)
            }
        }
        
        // Collapse alias duplicates (e.g. "Man City" + "Manchester City"), preferring rows with real badges.
        var dedupedByNormalizedKey: [String: SocialTeamSuggestion] = [:]
        for suggestion in filtered {
            let resolvedBadgeURL = suggestion.badgeURL ?? teamBadgeURL(for: suggestion.teamName)
            let dedupeKey: String
            if let resolvedBadgeURL {
                dedupeKey = "\(normalizedLeagueName(for: suggestion).lowercased())|badge:\(resolvedBadgeURL.absoluteString)"
            } else {
                dedupeKey = "\(normalizedLeagueName(for: suggestion).lowercased())|name:\(normalizedBrandLookupKey(suggestion.teamName))"
            }
            if let existing = dedupedByNormalizedKey[dedupeKey] {
                let existingResolvedBadgeURL = existing.badgeURL ?? teamBadgeURL(for: existing.teamName)
                if existingResolvedBadgeURL == nil, resolvedBadgeURL != nil {
                    dedupedByNormalizedKey[dedupeKey] = suggestion
                } else if (existingResolvedBadgeURL != nil) == (resolvedBadgeURL != nil),
                          canonicalClubDisplayName(name: suggestion.teamName, shortName: nil, tla: nil).count
                            > canonicalClubDisplayName(name: existing.teamName, shortName: nil, tla: nil).count {
                    dedupedByNormalizedKey[dedupeKey] = suggestion
                }
            } else {
                dedupedByNormalizedKey[dedupeKey] = suggestion
            }
        }
        filtered = Array(dedupedByNormalizedKey.values)
        
        if query.isEmpty {
            filtered.sort { lhs, rhs in
                let lhsLeague = normalizedLeagueName(for: lhs)
                let rhsLeague = normalizedLeagueName(for: rhs)
                if lhsLeague != rhsLeague {
                    return lhsLeague.localizedCaseInsensitiveCompare(rhsLeague) == .orderedAscending
                }
                return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending
            }
            return filtered
        }
        
        return filtered.sorted {
            $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
        }
    }

    
    private var socialTabRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Social Section", selection: $activeSocialTab) {
                ForEach(SocialHubTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, FottyTheme.spacingMD)
    }
    
    @ViewBuilder
    private var socialTabContent: some View {
        switch activeSocialTab {
        case .following:
            SocialFollowingView(
                composerText: $composerText,
                composerCategory: $composerCategory,
                composerCategories: composerCategories,
                rootFeedItems: rootFeedItems,
                expandedThreadIDs: expandedThreadIDs,
                replyDraftByActivityID: $replyDraftByActivityID,
                onPostActivity: { postActivity() },
                onQuickReaction: { emoji, id in addReaction(emoji: emoji, for: id) },
                onToggleThread: { id in toggleThreadExpanded(id) },
                onPostReply: { id in postReply(for: id) },
                onReport: { item in
                    applySafetyActionForFeedItem(.report, item: item, reason: "Content report")
                },
                onBlock: { item in
                    applySafetyActionForFeedItem(.block, item: item, reason: "Blocked from feed")
                }
            )
        case .explore:
            SocialExploreView(
                searchText: $searchText,
                searchScope: $searchScope,
                searchSort: $searchSort,
                discoverableEntries: discoverableEntries,
                blockedAccountIDs: blockedAccountIDs,
                hasDiscoveryQuery: hasDiscoveryQuery,
                areAllAccountsBlocked: areAllAccountsBlocked,
                isFollowing: { id in isFollowing(accountID: id) },
                onToggleFollow: { entry in toggleFollowForDiscoveryEntry(entry) },
                onMute: { entry in applySafetyActionForDiscoveryEntry(.mute, account: entry, reason: "Muted from discovery") },
                onBlock: { entry in applySafetyActionForDiscoveryEntry(.block, account: entry, reason: "Blocked from social") },
                onReport: { entry in applySafetyActionForDiscoveryEntry(.report, account: entry, reason: "User report from discovery") },
                onClearBlocked: { clearAllBlockedAccounts() }
            )
        case .teams:
            discoverTeamsAndLeaguesSection
            teamAlertPreferencesSection
            teamAlertsSection
            teamNewsSection
        case .notifications:
            SocialNotificationsView(
                notifications: visibleNotifications,
                unreadCount: unreadNotificationsCount,
                localPersistenceError: localPersistenceError,
                onMarkAsRead: { n in markNotificationAsRead(n) },
                onMarkAllRead: { markAllNotificationsAsRead() }
            )
            moderationSection
        case .messages:
            messagesSection
        }
    }

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Private Rooms",
                subtitle: "Direct side-conversations with other fans"
            )
            
            SocialInboxView()
        }
    }


    
    private var discoverTeamsAndLeaguesSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Teams & Leagues",
                subtitle: "Follow clubs and competitions in one place"
            )
            
            VStack(alignment: .leading, spacing: FottyTheme.spacingSM) {
                LeagueTeamPicker()
                    .padding(.top, 4)
            }
        }
    }
    
    // Legacy browse code removed
    private var legacyBrowseItemsSectionPlaceholder: some View { EmptyView() }


    private var moderationSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Safety & Moderation",
                subtitle: "Manage muted and blocked accounts"
            )
            
            VStack(spacing: FottyTheme.spacingSM) {
                if blockedEntries.isEmpty && mutedEntries.isEmpty {
                    socialEmptyStateCard(text: "No muted or blocked accounts.")
                } else {
                    if !blockedEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Blocked Accounts")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(FottyTheme.textSecondary)
                                Spacer()
                                Button("Clear All") {
                                    clearAllBlockedAccounts()
                                }
                                .pillButtonStyle(accent: true)
                            }
                            
                            ForEach(blockedEntries) { entry in
                                HStack(spacing: 10) {
                                    Image(systemName: entry.avatarSymbol)
                                        .foregroundStyle(FottyTheme.accentText)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(FottyTheme.textPrimary)
                                        Text("@\(entry.username)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(FottyTheme.textSecondary)
                                    }
                                    Spacer()
                                    Button("Unblock") {
                                        removeSafetyAction(.block, accountID: entry.id)
                                    }
                                    .pillButtonStyle(accent: true)
                                }
                            }
                        }
                        .padding(FottyTheme.spacingMD)
                        .cardStyle()
                    }
                    
                    if !mutedEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Muted Accounts")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(FottyTheme.textSecondary)
                                Spacer()
                                Button("Clear All") {
                                    clearAllMutedAccounts()
                                }
                                .pillButtonStyle(accent: true)
                            }
                            
                            ForEach(mutedEntries) { entry in
                                HStack(spacing: 10) {
                                    Image(systemName: entry.avatarSymbol)
                                        .foregroundStyle(FottyTheme.textTertiary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(FottyTheme.textPrimary)
                                        Text("@\(entry.username)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(FottyTheme.textSecondary)
                                    }
                                    Spacer()
                                    Button("Unmute") {
                                        removeSafetyAction(.mute, accountID: entry.id)
                                    }
                                    .pillButtonStyle(accent: false)
                                }
                            }
                        }
                        .padding(FottyTheme.spacingMD)
                        .cardStyle()
                    }
                }
            }
            .padding(.horizontal, FottyTheme.spacingMD)
        }
    }

    private var activityComposerSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Activity Feed",
                subtitle: "Post updates and reactions for your network"
            )

            VStack(alignment: .leading, spacing: 10) {
                TextField("Share a quick update...", text: $composerText, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)

                HStack {
                    Picker("Category", selection: $composerCategory) {
                        ForEach(composerCategories, id: \.self) { category in
                            Text(category.capitalized).tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button("Post") {
                        postActivity()
                    }
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pillButtonStyle(accent: true)
                }
            }
            .padding(FottyTheme.spacingMD)
            .cardStyle()
            .padding(.horizontal, FottyTheme.spacingMD)
        }
    }

    private var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            if rootFeedItems.isEmpty {
                socialEmptyStateCard(text: "No feed activity yet. Follow accounts and post updates to get started.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                VStack(spacing: FottyTheme.spacingSM) {
                    ForEach(Array(rootFeedItems.prefix(20))) { item in
                        SocialActivityRow(
                            item: item,
                            replies: repliesForActivity(item.id),
                            reactionSummary: reactionSummaryForActivity(item.id),
                            isExpanded: expandedThreadIDs.contains(item.id),
                            replyDraft: Binding(
                                get: { replyDraftByActivityID[item.id] ?? "" },
                                set: { replyDraftByActivityID[item.id] = $0 }
                            ),
                            onReaction: { emoji in addReaction(emoji: emoji, for: item.id) },
                            onToggleThread: {
                                toggleThreadExpanded(item.id)
                            },
                            onPostReply: {
                                postReply(for: item.id)
                            },
                            onReport: {
                                applySafetyActionForFeedItem(.report, item: item, reason: "Content report")
                            },
                            onBlock: {
                                applySafetyActionForFeedItem(.block, item: item, reason: "Blocked from feed")
                            }
                        )
                    }
                }
                .padding(.horizontal, FottyTheme.spacingMD)
            }
        }
    }

    @ViewBuilder
    private func socialBadgeImage(url: URL?, fallbackSystemName: String, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(FottyTheme.surfaceElevated)
            
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    default:
                        Image(systemName: fallbackSystemName)
                            .font(.system(size: max(10, size * 0.42), weight: .semibold))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
            } else {
                Image(systemName: fallbackSystemName)
                    .font(.system(size: max(10, size * 0.42), weight: .semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var teamAlertPreferencesSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Alert Bells",
                subtitle: "Choose which followed teams trigger alerts"
            )

            VStack(alignment: .leading, spacing: FottyTheme.spacingSM) {
                if followedTeamEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        socialEmptyStateCard(text: "Follow teams in Discover to unlock per-team alerts.")
                        Button("Go To Discover Teams") {
                            withAnimation(FottyTheme.springSnappy) {
                                activeSocialTab = .teams
                            }
                        }
                    }
                    .padding(.horizontal, FottyTheme.spacingMD)
                } else {
                    VStack(spacing: FottyTheme.spacingSM) {
                        ForEach(followedTeamEntries) { team in
                            SwipeableTeamRow(
                                team: team,
                                onToggleAlerts: { toggleTeamAlerts(team) },
                                onDelete: {
                                    let key = team.key
                                    if let existing = followedTeamEntries.first(where: { $0.key == key }) {
                                        modelContext.delete(existing)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, FottyTheme.spacingMD)
                }
                
                if !followedLeagueNames.isEmpty {
                    Text("League follows influence team news: \(followedLeagueNames.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .padding(.horizontal, FottyTheme.spacingMD)
                }
            }
        }
    }

    @ViewBuilder
    private var teamAlertsSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Team Alerts",
                subtitle: "Upcoming matches shaped by your follows"
            )

            if isLoadingAlerts {
                HStack(spacing: 10) {
                    ProgressView().tint(FottyTheme.accentText)
                    Text("Refreshing team alerts...")
                        .font(.system(size: 13))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .padding(FottyTheme.spacingMD)
                .cardStyle()
                .padding(.horizontal, FottyTheme.spacingMD)
            } else if let alertsError {
                socialEmptyStateCard(text: "Could not load alerts: \(alertsError)")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else if teamAlerts.isEmpty {
                socialEmptyStateCard(text: "No upcoming matches for alert-enabled teams right now.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                VStack(spacing: FottyTheme.spacingSM) {
                    ForEach(teamAlerts) { alert in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(alert.category.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(FottyTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(FottyTheme.surfaceElevated))

                                if alert.isPopular {
                                    Text("Popular")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(FottyTheme.textOnAccent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(FottyTheme.accent))
                                }

                                Spacer()

                                Text(alertTimeLabel(for: alert.kickoff))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }

                            Text(alert.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FottyTheme.textPrimary)

                            HStack(spacing: 6) {
                                ForEach(alert.matchedTeams, id: \.self) { team in
                                    HStack(spacing: 4) {
                                        if let url = TeamBrandService.shared.badgeURL(for: team, triggerSearch: true) {
                                            AsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFit()
                                                } else {
                                                    Image(systemName: "sportscourt").font(.system(size: 8))
                                                }
                                            }
                                            .frame(width: 14, height: 14)
                                        }
                                        
                                        Text(team)
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(FottyTheme.success)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(FottyTheme.success.opacity(0.12)))
                                }
                            }

                            if !alert.supportingHandles.isEmpty {
                                Text("Signals from \(alert.supportingHandles.joined(separator: ", "))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        .padding(FottyTheme.spacingMD)
                        .cardStyle()
                    }
                }
                .padding(.horizontal, FottyTheme.spacingMD)
            }
        }
    }
    
    @ViewBuilder
    private var teamNewsSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Team News",
                subtitle: followedFootballLeagueTopics.isEmpty
                    ? "Latest headlines for followed football teams"
                    : "Latest headlines for followed teams and leagues"
            )
            
            if followedFootballTeamNames.isEmpty && followedLeagueNames.isEmpty {
                socialEmptyStateCard(text: "Follow teams and leagues in Discover to unlock personalized team news.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else if isLoadingTeamNews {
                HStack(spacing: 10) {
                    ProgressView().tint(FottyTheme.accentText)
                    Text("Refreshing team headlines...")
                        .font(.system(size: 13))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .padding(FottyTheme.spacingMD)
                .cardStyle()
                .padding(.horizontal, FottyTheme.spacingMD)
            } else if let teamNewsError {
                socialEmptyStateCard(text: "Could not load team news: \(teamNewsError)")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else if teamNewsHeadlines.isEmpty {
                socialEmptyStateCard(text: "No team headlines available right now.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                VStack(spacing: FottyTheme.spacingSM) {
                    ForEach(teamNewsHeadlines) { headline in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(headline.teamName.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(FottyTheme.accentText)
                                if headline.topicType == .league {
                                    Text("LEAGUE")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(FottyTheme.accentText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(FottyTheme.liveAccent.opacity(0.15), in: Capsule())
                                }
                                Spacer()
                                if let date = headline.publishedAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundStyle(FottyTheme.textTertiary)
                                }
                            }
                            
                            if let url = headline.url {
                                Link(destination: url) {
                                    Text(headline.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(FottyTheme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(headline.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(FottyTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            if let source = headline.source, !source.isEmpty {
                                Text(source)
                                    .font(.system(size: 11))
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        .padding(FottyTheme.spacingMD)
                        .cardStyle()
                    }
                }
                .padding(.horizontal, FottyTheme.spacingMD)
            }
        }
    }

    private func socialEmptyStateCard(text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(FottyTheme.textSecondary)
            .padding(FottyTheme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    private func toggleFollow(for account: SocialAccount) {
        if let existing = followingRelationships.first(where: { $0.followedAccountID == account.id }) {
            modelContext.delete(existing)
            insertSocialNotification(
                type: "follow",
                title: "Unfollowed @\(account.username)",
                body: "You will no longer get activity signals from this account.",
                actorAccountID: account.id
            )
            persistSocialMutation(actionType: "unfollow", payload: account.id)
        } else {
            modelContext.insert(
                SocialFollowRelationship(
                    followerProfileID: profileID,
                    followedAccountID: account.id
                )
            )
            modelContext.insert(
                SocialActivityItem(
                    actorProfileID: profileID,
                    actorDisplayName: resolvedProfileDisplayName,
                    actorUsername: resolvedProfileUsername ?? "fan",
                    category: "network",
                    content: "Followed @\(account.username)"
                )
            )
            insertSocialNotification(
                type: "follow",
                title: "Now Following @\(account.username)",
                body: "Their activity can shape your social feed and alerts.",
                actorAccountID: account.id
            )
            persistSocialMutation(actionType: "follow", payload: account.id)
        }
    }
    
    private func toggleFollowForDiscoveryEntry(_ account: SocialDiscoveryEntry) {
        guard let persistedAccount = materializeDiscoveryEntry(account) else { return }
        toggleFollow(for: persistedAccount)
    }
    
    private func applySafetyActionForDiscoveryEntry(
        _ action: SocialSafetyAction,
        account: SocialDiscoveryEntry,
        reason: String
    ) {
        guard let persistedAccount = materializeDiscoveryEntry(account) else { return }
        applySafetyAction(action, target: persistedAccount, reason: reason)
    }

    private func applySafetyActionForFeedItem(
        _ action: SocialSafetyAction,
        item: SocialActivityItem,
        reason: String
    ) {
        let entry = SocialDiscoveryEntry(
            id: item.actorProfileID,
            username: item.actorUsername,
            displayName: item.actorDisplayName,
            bio: "",
            avatarSymbol: "person.crop.circle.fill",
            favoriteCategory: nil,
            isVerified: false
        )
        guard let persistedAccount = materializeDiscoveryEntry(entry) else { return }
        applySafetyAction(action, target: persistedAccount, reason: reason)
    }

    private func isFollowing(_ account: SocialAccount) -> Bool {
        followingRelationships.contains { $0.followedAccountID == account.id }
    }
    
    private func isFollowing(accountID: String) -> Bool {
        followingRelationships.contains { $0.followedAccountID == accountID }
    }
    
    private func materializeDiscoveryEntry(_ entry: SocialDiscoveryEntry) -> SocialAccount? {
        if let existing = socialAccounts.first(where: { $0.id == entry.id }) {
            return existing
        }
        
        let account = SocialAccount(
            id: entry.id,
            username: entry.username,
            displayName: entry.displayName,
            bio: entry.bio,
            avatarSymbol: entry.avatarSymbol,
            favoriteCategory: entry.favoriteCategory,
            isVerified: entry.isVerified
        )
        modelContext.insert(account)
        
        do {
            try modelContext.save()
            return account
        } catch {
            localPersistenceError = "Could not create social account locally: \(error.localizedDescription)"
            return nil
        }
    }

    private func postActivity() {
        let content = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let actorDisplayName = resolvedProfileDisplayName
        let actorUsername = resolvedProfileUsername ?? "fan"

        modelContext.insert(
            SocialActivityItem(
                actorProfileID: profileID,
                actorDisplayName: actorDisplayName,
                actorUsername: actorUsername,
                category: composerCategory,
                content: content
            )
        )

        insertSocialNotification(
            type: "activity",
            title: "Post Published",
            body: "Your update is now visible in the feed."
        )

        composerText = ""
        persistSocialMutation(actionType: "post_activity", payload: content)
    }
    
    @ViewBuilder
    private func quickReactionButton(_ emoji: String, parentID: String) -> some View {
        Button(emoji) {
            addReaction(emoji: emoji, for: parentID)
        }
    }
    
    private func toggleThreadExpanded(_ activityID: String) {
        if expandedThreadIDs.contains(activityID) {
            expandedThreadIDs.remove(activityID)
        } else {
            expandedThreadIDs.insert(activityID)
        }
    }
    
    private func postReply(for parentID: String) {
        let draft = (replyDraftByActivityID[parentID] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        
        modelContext.insert(
            SocialActivityItem(
                actorProfileID: profileID,
                actorDisplayName: resolvedProfileDisplayName,
                actorUsername: resolvedProfileUsername ?? "fan",
                category: "reply",
                content: makeReplyPayload(parentID: parentID, text: draft)
            )
        )
        
        replyDraftByActivityID[parentID] = ""
        expandedThreadIDs.insert(parentID)
        persistSocialMutation(actionType: "reply_activity", payload: parentID)
    }
    
    private func addReaction(emoji: String, for parentID: String) {
        modelContext.insert(
            SocialActivityItem(
                actorProfileID: profileID,
                actorDisplayName: resolvedProfileDisplayName,
                actorUsername: resolvedProfileUsername ?? "fan",
                category: "reaction",
                content: makeReactionPayload(parentID: parentID, emoji: emoji)
            )
        )
        persistSocialMutation(actionType: "reaction_activity", payload: "\(parentID)|\(emoji)")
    }
    
    private func repliesForActivity(_ parentID: String) -> [SocialActivityItem] {
        visibleFeed.filter { activity in
            guard let parsed = parseReplyPayload(activity.content), activity.category == "reply" else { return false }
            return parsed.parentID == parentID
        }
        .sorted { $0.createdAt < $1.createdAt }
    }
    
    private func displayTextForReply(_ activity: SocialActivityItem) -> String {
        parseReplyPayload(activity.content)?.text ?? activity.content
    }
    
    private func reactionSummaryForActivity(_ parentID: String) -> [SocialReactionSummaryItem] {
        let reactions = visibleFeed.compactMap { activity -> String? in
            guard activity.category == "reaction",
                  let parsed = parseReactionPayload(activity.content),
                  parsed.parentID == parentID else { return nil }
            return parsed.emoji
        }
        
        var counts: [String: Int] = [:]
        reactions.forEach { emoji in
            counts[emoji, default: 0] += 1
        }
        
        return counts.keys.sorted().map { emoji in
            SocialReactionSummaryItem(emoji: emoji, count: counts[emoji] ?? 0)
        }
    }
    
    private func isReplyActivity(_ activity: SocialActivityItem) -> Bool {
        activity.category == "reply" && parseReplyPayload(activity.content) != nil
    }
    
    private func isReactionActivity(_ activity: SocialActivityItem) -> Bool {
        activity.category == "reaction" && parseReactionPayload(activity.content) != nil
    }
    
    private func makeReplyPayload(parentID: String, text: String) -> String {
        "reply:\(parentID)|\(text)"
    }
    
    private func parseReplyPayload(_ rawValue: String) -> (parentID: String, text: String)? {
        guard rawValue.hasPrefix("reply:") else { return nil }
        let payload = String(rawValue.dropFirst("reply:".count))
        guard let separatorIndex = payload.firstIndex(of: "|") else { return nil }
        let parentID = String(payload[..<separatorIndex])
        let text = String(payload[payload.index(after: separatorIndex)...])
        guard !parentID.isEmpty else { return nil }
        return (parentID, text)
    }
    
    private func makeReactionPayload(parentID: String, emoji: String) -> String {
        "react:\(parentID)|\(emoji)"
    }
    
    private func parseReactionPayload(_ rawValue: String) -> (parentID: String, emoji: String)? {
        guard rawValue.hasPrefix("react:") else { return nil }
        let payload = String(rawValue.dropFirst("react:".count))
        guard let separatorIndex = payload.firstIndex(of: "|") else { return nil }
        let parentID = String(payload[..<separatorIndex])
        let emoji = String(payload[payload.index(after: separatorIndex)...])
        guard !parentID.isEmpty, !emoji.isEmpty else { return nil }
        return (parentID, emoji)
    }

    private func applySafetyAction(_ action: SocialSafetyAction, target account: SocialAccount, reason: String) {
        let existing = socialSafetyActions.first {
            $0.action == action.rawValue && $0.targetAccountID == account.id
        }
        if existing != nil {
            return
        }

        modelContext.insert(
            SocialSafetyActionItem(
                action: action.rawValue,
                targetAccountID: account.id,
                reason: reason
            )
        )

        if action == .block {
            for relationship in followingRelationships where relationship.followedAccountID == account.id {
                modelContext.delete(relationship)
            }
        }

        insertSocialNotification(
            type: "safety",
            title: "\(action.rawValue.capitalized)ed @\(account.username)",
            body: reason,
            actorAccountID: account.id
        )

        persistSocialMutation(actionType: "safety_\(action.rawValue)", payload: account.id)
    }

    private func markNotificationAsRead(_ notification: SocialNotificationItem) {
        guard !notification.isRead else { return }
        notification.isRead = true
        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not update notifications: \(error.localizedDescription)"
        }
    }

    private func markAllNotificationsAsRead() {
        for notification in socialNotifications where !notification.isRead {
            notification.isRead = true
        }
        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not update notifications: \(error.localizedDescription)"
        }
    }

    private func insertSocialNotification(
        type: String,
        title: String,
        body: String,
        actorAccountID: String? = nil
    ) {
        modelContext.insert(
            SocialNotificationItem(
                type: type,
                title: title,
                body: body,
                actorAccountID: actorAccountID,
                isRead: false
            )
        )
    }

    private func persistSocialMutation(actionType: String, payload: String) {
        _ = (actionType, payload)

        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not save this change: \(error.localizedDescription)"
        }
    }

    private func purgeRetiredPendingActions() {
        guard !pendingSocialActions.isEmpty else { return }
        for item in pendingSocialActions {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not remove retired sync actions: \(error.localizedDescription)"
        }
    }

    private func ensureLocalProfileExists() {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let existingProfiles = (try? modelContext.fetch(descriptor)) ?? profiles
        guard !existingProfiles.isEmpty else {
            let profile = UserProfile()
            modelContext.insert(profile)
            do {
                try modelContext.save()
            } catch {
                print("[SocialHub] Failed to create local profile: \(error.localizedDescription)")
                localPersistenceError = "Could not create local profile: \(error.localizedDescription)"
            }
            return
        }
        
        if let localProfile = existingProfiles.first(where: { $0.id == "local-profile" }) {
            if let preferred = preferredCanonicalProfile(from: existingProfiles),
               preferred !== localProfile,
               profileQualityScore(preferred) > profileQualityScore(localProfile) {
                copyProfileIdentity(from: preferred, to: localProfile)
            }
            
            for duplicate in existingProfiles where duplicate !== localProfile {
                modelContext.delete(duplicate)
            }
        } else if let source = preferredCanonicalProfile(from: existingProfiles) {
            let migrated = UserProfile(
                id: "local-profile",
                displayName: source.displayName,
                username: source.username,
                bio: source.bio,
                avatarSymbol: source.avatarSymbol,
                avatarImageData: source.avatarImageData,
                avatarImageUpdatedAt: source.avatarImageUpdatedAt,
                isSignedIn: source.isSignedIn,
                isPrivateAccount: source.isPrivateAccount,
                allowFollowerRequests: source.allowFollowerRequests,
                shareTeamActivity: source.shareTeamActivity,
                lastUpdatedAt: source.lastUpdatedAt,
                createdAt: source.createdAt
            )
            modelContext.insert(migrated)
            
            for duplicate in existingProfiles {
                modelContext.delete(duplicate)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("[SocialHub] Failed to normalize local profile: \(error.localizedDescription)")
            localPersistenceError = "Could not normalize local profile: \(error.localizedDescription)"
        }
    }

    private func purgeRetiredSyntheticSocialData() {
        let isSynthetic: (String) -> Bool = { $0.hasPrefix("seed-") }

        for account in socialAccounts where isSynthetic(account.id) {
            modelContext.delete(account)
        }
        for relationship in socialFollows where isSynthetic(relationship.followedAccountID) {
            modelContext.delete(relationship)
        }
        for notification in socialNotifications where notification.actorAccountID.map(isSynthetic) == true {
            modelContext.delete(notification)
        }
        for activity in socialActivities where isSynthetic(activity.actorProfileID) {
            modelContext.delete(activity)
        }
        for action in socialSafetyActions where isSynthetic(action.targetAccountID) {
            modelContext.delete(action)
        }

        if let conversations = try? modelContext.fetch(FetchDescriptor<SocialConversation>()) {
            for conversation in conversations where conversation.participantIDs.contains(where: isSynthetic) {
                modelContext.delete(conversation)
            }
        }
        if let messages = try? modelContext.fetch(FetchDescriptor<DirectMessage>()) {
            for message in messages where isSynthetic(message.senderID) || isSynthetic(message.recipientID) {
                modelContext.delete(message)
            }
        }

        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not remove retired sample social data: \(error.localizedDescription)"
        }
    }
    
    private func preferredCanonicalProfile(from profiles: [UserProfile]) -> UserProfile? {
        profiles.max { lhs, rhs in
            let lhsScore = profileQualityScore(lhs)
            let rhsScore = profileQualityScore(rhs)
            if lhsScore == rhsScore {
                let lhsUpdated = lhs.lastUpdatedAt ?? lhs.createdAt
                let rhsUpdated = rhs.lastUpdatedAt ?? rhs.createdAt
                return lhsUpdated < rhsUpdated
            }
            return lhsScore < rhsScore
        }
    }
    
    private func profileQualityScore(_ profile: UserProfile) -> Int {
        let display = sanitizeDisplayName(profile.displayName).lowercased()
        let username = sanitizeUsername(profile.username ?? "").lowercased()
        let bio = sanitizeBio(profile.bio ?? "").lowercased()
        
        var score = 0
        if !display.isEmpty, display != "guest" { score += 4 }
        if !username.isEmpty, username != "guestfan" { score += 3 }
        if !bio.isEmpty, bio != "football and movie nights." { score += 1 }
        if profile.isSignedIn { score += 2 }
        if profile.avatarImageData != nil { score += 1 }
        return score
    }
    
    private func copyProfileIdentity(from source: UserProfile, to target: UserProfile) {
        target.displayName = source.displayName
        target.username = source.username
        target.bio = source.bio
        target.avatarSymbol = source.avatarSymbol
        target.avatarImageData = source.avatarImageData
        target.avatarImageUpdatedAt = source.avatarImageUpdatedAt
        target.isSignedIn = source.isSignedIn
        target.isPrivateAccount = source.isPrivateAccount
        target.allowFollowerRequests = source.allowFollowerRequests
        target.shareTeamActivity = source.shareTeamActivity
        target.lastUpdatedAt = source.lastUpdatedAt ?? Date()
    }

    private func displayNameFromEmail(_ email: String) -> String {
        let localPart = email.components(separatedBy: "@").first ?? "fan"
        let sanitized = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let display = sanitizeDisplayName(sanitized)
        return display.isEmpty ? "Fan" : display
    }

    private func usernameFromEmail(_ email: String) -> String {
        let localPart = email.components(separatedBy: "@").first ?? "fan"
        let cleaned = localPart
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9._-]",
                with: "",
                options: .regularExpression
            )
        let username = sanitizeUsername(cleaned)
        return username.isEmpty ? "fan" : username
    }

    private func toggleTeamAlerts(_ team: FollowedTeamItem) {
        let currentlyEnabled = team.alertsEnabled ?? true
        team.alertsEnabled = !currentlyEnabled

        persistSocialMutation(actionType: "team_alert_toggle", payload: team.key)
    }
    
    private func isLeagueFollowCategory(_ rawCategory: String) -> Bool {
        rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "football_league"
    }
    
    private func teamFollowKey(name: String, category: String) -> String {
        TeamFollowKey.make(name: name, category: category)
    }
    
    private func toggleTeamFollow(name: String, category: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        let key = teamFollowKey(name: trimmedName, category: category)
        if let existing = followedTeamEntries.first(where: { $0.key == key }) {
            modelContext.delete(existing)
            persistSocialMutation(actionType: "team_unfollow", payload: key)
        } else {
            let badgeURL = teamBadgeURL(for: trimmedName)?.absoluteString
            modelContext.insert(
                FollowedTeamItem(
                    key: key,
                    teamName: trimmedName,
                    sportCategory: category,
                    badgeURLString: badgeURL,
                    alertsEnabled: true
                )
            )
            persistSocialMutation(actionType: "team_follow", payload: key)
        }
    }
    
    private func leagueFollowKey(name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "league:\(cleaned)"
    }
    
    private func isLeagueFollowed(name: String) -> Bool {
        let key = leagueFollowKey(name: name)
        return followedLeagueEntries.contains { $0.key == key }
    }
    
    private func toggleLeagueFollow(name: String) {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !cleaned.isEmpty else { return }
        
        let key = leagueFollowKey(name: cleaned)
        if let existing = followedLeagueEntries.first(where: { $0.key == key }) {
            modelContext.delete(existing)
            persistSocialMutation(actionType: "league_unfollow", payload: key)
        } else {
            modelContext.insert(
                FollowedTeamItem(
                    key: key,
                    teamName: cleaned,
                    sportCategory: "football_league",
                    alertsEnabled: false
                )
            )
            persistSocialMutation(actionType: "league_follow", payload: key)
        }
    }
    
    private func curatedFootballTeamsByLeague() -> [String: [String]] {
        guard FootballCompetitionCatalog.isFresh() else { return [:] }
        return FootballCompetitionCatalog.socialFallback()
    }
    
    
    private func refreshTeamFollowSuggestions(refreshBrandAssets: Bool = true) async {
        // Brand assets are now managed by TeamBrandService.shared
        
        isLoadingTeamFollowSuggestions = true
        teamFollowSuggestionsError = nil
        
        func suggestionIdentifier(followKey: String, leagueName: String?) -> String {
            let leagueComponent = normalizedBrandLookupKey(leagueName ?? "other-leagues")
            return "\(followKey)::\(leagueComponent.isEmpty ? "other-leagues" : leagueComponent)"
        }
        
        do {
            let events = try await AnalyticalDataEngine.allLiveEvents()
                .filter { $0.passesNearTermLiveListWindow() }
            var suggestionsByKey: [String: SocialTeamSuggestion] = [:]
            
            func registerTeam(
                _ teamName: String,
                category: String,
                kickoff: Date?,
                leagueName: String?,
                badgeURL: URL?
            ) {
                let cleaned = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                guard cleaned.lowercased() != "home", cleaned.lowercased() != "away" else { return }
                
                let followKey = teamFollowKey(name: cleaned, category: category)
                let normalizedLeague = leagueName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidateLeague = (normalizedLeague?.isEmpty ?? true) ? nil : normalizedLeague
                let key = suggestionIdentifier(followKey: followKey, leagueName: candidateLeague)
                
                if let existing = suggestionsByKey[key] {
                    let existingKickoff = existing.kickoff ?? .distantFuture
                    let candidateKickoff = kickoff ?? .distantFuture
                    if candidateKickoff < existingKickoff {
                        suggestionsByKey[key] = SocialTeamSuggestion(
                            id: key,
                            followKey: followKey,
                            teamName: cleaned,
                            sportCategory: category,
                            kickoff: kickoff,
                            leagueName: candidateLeague ?? existing.leagueName,
                            badgeURL: badgeURL ?? existing.badgeURL
                        )
                    } else if existing.leagueName == nil, let candidateLeague {
                        suggestionsByKey[key] = SocialTeamSuggestion(
                            id: key,
                            followKey: existing.followKey,
                            teamName: existing.teamName,
                            sportCategory: existing.sportCategory,
                            kickoff: existing.kickoff,
                            leagueName: candidateLeague,
                            badgeURL: existing.badgeURL ?? badgeURL
                        )
                    } else if existing.badgeURL == nil, let badgeURL {
                        suggestionsByKey[key] = SocialTeamSuggestion(
                            id: key,
                            followKey: existing.followKey,
                            teamName: existing.teamName,
                            sportCategory: existing.sportCategory,
                            kickoff: existing.kickoff,
                            leagueName: existing.leagueName,
                            badgeURL: badgeURL
                        )
                    }
                } else {
                    suggestionsByKey[key] = SocialTeamSuggestion(
                        id: key,
                        followKey: followKey,
                        teamName: cleaned,
                        sportCategory: category,
                        kickoff: kickoff,
                        leagueName: candidateLeague,
                        badgeURL: badgeURL
                    )
                }
            }
            
            for event in events {
                guard event.normalizedCategory == "football" || event.normalizedCategory == "soccer" else { continue }
                let inferredLeague = AnalyticalDataEngine.footballLeagueTab(for: event)
                let leagueName = inferredLeague == .other ? nil : inferredLeague.displayName
                registerTeam(
                    event.homeName,
                    category: event.normalizedCategory,
                    kickoff: event.kickoffDate,
                    leagueName: leagueName,
                    badgeURL: event.homeBadgeURL ?? teamBadgeURL(for: event.homeName)
                )
                registerTeam(
                    event.awayName,
                    category: event.normalizedCategory,
                    kickoff: event.kickoffDate,
                    leagueName: leagueName,
                    badgeURL: event.awayBadgeURL ?? teamBadgeURL(for: event.awayName)
                )
            }
            
            let curatedByLeague = curatedFootballTeamsByLeague()
            let mergedLeagueNames = Set(curatedByLeague.keys).union(leagueTeamCatalog.keys)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            
            for leagueName in mergedLeagueNames {
                if let catalogTeams = leagueTeamCatalog[leagueName], !catalogTeams.isEmpty {
                    for team in catalogTeams {
                        registerTeam(
                            team.displayName,
                            category: "football",
                            kickoff: nil,
                            leagueName: leagueName,
                            badgeURL: team.badgeURL ?? teamBadgeURL(for: team.displayName)
                        )
                    }
                    continue
                }
                
                for team in curatedByLeague[leagueName] ?? [] {
                    registerTeam(
                        team,
                        category: "football",
                        kickoff: nil,
                        leagueName: leagueName,
                        badgeURL: teamBadgeURL(for: team)
                    )
                }
            }
            
            let sorted = suggestionsByKey.values.sorted { lhs, rhs in
                let lhsFollowed = followedTeamKeys.contains(lhs.followKey)
                let rhsFollowed = followedTeamKeys.contains(rhs.followKey)
                if lhsFollowed != rhsFollowed {
                    return !lhsFollowed && rhsFollowed
                }
                
                let lhsKickoff = lhs.kickoff ?? .distantFuture
                let rhsKickoff = rhs.kickoff ?? .distantFuture
                if lhsKickoff != rhsKickoff {
                    return lhsKickoff < rhsKickoff
                }
                let lhsLeague = normalizedLeagueName(for: lhs)
                let rhsLeague = normalizedLeagueName(for: rhs)
                if lhsLeague != rhsLeague {
                    return lhsLeague.localizedCaseInsensitiveCompare(rhsLeague) == .orderedAscending
                }
                return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending
            }
            
            // Keep the complete suggestion set searchable; the UI layer already limits rendered rows.
            teamFollowSuggestions = sorted
            teamFollowSuggestionsError = nil
            isLoadingTeamFollowSuggestions = false
        } catch {
            guard FootballCompetitionCatalog.isFresh() else {
                teamFollowSuggestions = []
                teamFollowSuggestionsError = "Team suggestions need a season refresh before they can be shown offline."
                isLoadingTeamFollowSuggestions = false
                return
            }
            var fallback: [SocialTeamSuggestion] = []
            for (leagueName, teams) in curatedFootballTeamsByLeague() {
                for team in teams {
                    let followKey = teamFollowKey(name: team, category: "football")
                    fallback.append(
                        SocialTeamSuggestion(
                            id: suggestionIdentifier(followKey: followKey, leagueName: leagueName),
                            followKey: followKey,
                            teamName: team,
                            sportCategory: "football",
                            kickoff: nil,
                            leagueName: leagueName,
                            badgeURL: teamBadgeURL(for: team)
                        )
                    )
                }
            }
            teamFollowSuggestions = fallback.sorted {
                if ($0.leagueName ?? "") != ($1.leagueName ?? "") {
                    return ($0.leagueName ?? "").localizedCaseInsensitiveCompare($1.leagueName ?? "") == .orderedAscending
                }
                return $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
            }
            teamFollowSuggestionsError = nil
            isLoadingTeamFollowSuggestions = false
        }
    }

    private func refreshAllSocialData(reason: String) async {
        await brandService.bootstrapIfNeeded()
        await refreshTeamFollowSuggestions()
        await refreshTeamAlerts()
        await refreshTeamNews()
        await backfillBadgeURLsForFollowedTeams()
        _ = reason
    }
    
    private func backfillBadgeURLsForFollowedTeams() async {
        for team in followedTeams {
            if team.badgeURLString == nil || team.badgeURLString?.isEmpty == true {
                if let badgeURL = teamBadgeURL(for: team.teamName) {
                    team.badgeURLString = badgeURL.absoluteString
                }
            }
        }
        try? modelContext.save()
    }

    private func refreshTeamAlerts() async {
        guard activeProfile?.shareTeamActivity ?? true else {
            teamAlerts = []
            alertsError = nil
            return
        }

        let enabledTeams = followedTeamEntries.filter { team in
            let category = team.sportCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return (category == "football" || category == "soccer") && (team.alertsEnabled ?? true)
        }
        guard !enabledTeams.isEmpty else {
            teamAlerts = []
            alertsError = nil
            return
        }

        isLoadingAlerts = true
        alertsError = nil

        do {
            let enabledTeamMap = Dictionary(uniqueKeysWithValues: enabledTeams.map { ($0.key, $0) })
            let events = try await AnalyticalDataEngine.allLiveEvents()
                .filter { $0.passesNearTermLiveListWindow() }
            let now = Date()

            let sortedEvents = events.sorted {
                let lhs = $0.kickoffDate ?? .distantFuture
                let rhs = $1.kickoffDate ?? .distantFuture
                return lhs < rhs
            }

            let alerts: [SocialTeamAlert] = sortedEvents.compactMap { event in
                // Keep a wider live window so currently-playing matches are not hidden by feed clock drift.
                if let kickoff = event.kickoffDate, kickoff < now.addingTimeInterval(-4 * 60 * 60) {
                    return nil
                }

                let homeKey = TeamFollowKey.make(name: event.homeName, category: event.normalizedCategory)
                let awayKey = TeamFollowKey.make(name: event.awayName, category: event.normalizedCategory)

                var matchedTeams: [String] = []
                if enabledTeamMap[homeKey] != nil {
                    matchedTeams.append(event.homeName)
                }
                if enabledTeamMap[awayKey] != nil && event.awayName != event.homeName {
                    matchedTeams.append(event.awayName)
                }

                guard !matchedTeams.isEmpty else {
                    return nil
                }

                let handles = supportingHandles(for: event)

                return SocialTeamAlert(
                    id: "\(event.id)-\(matchedTeams.joined(separator: "|"))",
                    title: matchupTitle(for: event),
                    category: event.categoryDisplayName,
                    kickoff: event.kickoffDate,
                    matchedTeams: matchedTeams,
                    supportingHandles: handles,
                    isPopular: event.popular ?? false
                )
            }

            teamAlerts = Array(alerts.prefix(24))
            isLoadingAlerts = false
        } catch {
            alertsError = error.localizedDescription
            teamAlerts = []
            isLoadingAlerts = false
        }
    }
    
    private func refreshTeamNews() async {
        guard activeProfile?.shareTeamActivity ?? true else {
            teamNewsHeadlines = []
            teamNewsError = nil
            return
        }
        
        let teams = followedFootballTeamNames
        let leagues = followedFootballLeagueTopics
        guard !teams.isEmpty || !leagues.isEmpty else {
            teamNewsHeadlines = []
            teamNewsError = nil
            return
        }
        
        isLoadingTeamNews = true
        teamNewsError = nil
        
        do {
            let headlines = try await TeamNewsService.shared.headlines(
                for: teams,
                leagueTopics: leagues,
                perTeamLimit: 3,
                perLeagueLimit: 2,
                totalLimit: 12
            )
            teamNewsHeadlines = headlines
            isLoadingTeamNews = false
        } catch {
            teamNewsHeadlines = []
            teamNewsError = error.localizedDescription
            isLoadingTeamNews = false
        }
    }

    private func supportingHandles(for event: AnalyticalDataEngine.EventReference) -> [String] {
        guard !followedAccounts.isEmpty else { return [] }

        let eventCategory = event.categoryDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let categoryMatched = followedAccounts.filter { account in
            guard let favoriteCategory = account.favoriteCategory else { return false }
            return favoriteCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == eventCategory
        }

        if !categoryMatched.isEmpty {
            return Array(categoryMatched.prefix(2)).map { "@\($0.username)" }
        }

        return Array(followedAccounts.prefix(1)).map { "@\($0.username)" }
    }

    private func matchupTitle(for event: AnalyticalDataEngine.EventReference) -> String {
        let home = event.homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = event.awayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !home.isEmpty, !away.isEmpty {
            return "\(home) vs \(away)"
        }

        return event.title ?? "Live Event"
    }

    private func alertTimeLabel(for kickoff: Date?) -> String {
        guard let kickoff else { return "Live now" }

        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d • h:mm a"
        let base = formatter.string(from: kickoff)
        if let snippet = kickoff.liveKickoffRelativeSnippet() {
            return "\(base) • \(snippet)"
        }
        return base
    }
    
    private func clearAllBlockedAccounts() {
        let blockedActions = socialSafetyActions.filter { $0.action == SocialSafetyAction.block.rawValue }
        guard !blockedActions.isEmpty else { return }
        
        for action in blockedActions {
            modelContext.delete(action)
        }
        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not clear blocked accounts: \(error.localizedDescription)"
            return
        }
        
        insertSocialNotification(
            type: "safety",
            title: "Blocked Accounts Cleared",
            body: "Previously blocked accounts are visible again."
        )
        persistSocialMutation(actionType: "safety_unblock_all", payload: "all")
    }
    
    private func clearAllMutedAccounts() {
        let mutedActions = socialSafetyActions.filter { $0.action == SocialSafetyAction.mute.rawValue }
        guard !mutedActions.isEmpty else { return }
        
        for action in mutedActions {
            modelContext.delete(action)
        }
        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not clear muted accounts: \(error.localizedDescription)"
            return
        }
        
        insertSocialNotification(
            type: "safety",
            title: "Muted Accounts Cleared",
            body: "Previously muted accounts are visible in feed again."
        )
        persistSocialMutation(actionType: "safety_unmute_all", payload: "all")
    }
    
    private func removeSafetyAction(_ action: SocialSafetyAction, accountID: String) {
        let matches = socialSafetyActions.filter {
            $0.action == action.rawValue && $0.targetAccountID == accountID
        }
        guard !matches.isEmpty else { return }
        
        for entry in matches {
            modelContext.delete(entry)
        }
        
        do {
            try modelContext.save()
        } catch {
            localPersistenceError = "Could not update moderation action: \(error.localizedDescription)"
            return
        }
        
        let accountUsername = discoverySourceEntries.first(where: { $0.id == accountID })?.username ?? "account"
        let pastTense = action == .mute ? "Unmuted" : "Unblocked"
        insertSocialNotification(
            type: "safety",
            title: "\(pastTense) @\(accountUsername)",
            body: "Your moderation setting was updated."
        )
        persistSocialMutation(actionType: "safety_un\(action.rawValue)", payload: accountID)
    }

    private func sanitizeDisplayName(_ rawValue: String) -> String {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return String(trimmed.prefix(32))
    }

    private func sanitizeUsername(_ rawValue: String) -> String {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let withoutPrefix = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let allowedCharacters = withoutPrefix.filter { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == ".")
        }

        return String(allowedCharacters.prefix(24))
    }

    private func sanitizeBio(_ rawValue: String) -> String {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return String(trimmed.prefix(140))
    }
}

private struct SocialTeamAlert: Identifiable {
    let id: String
    let title: String
    let category: String
    let kickoff: Date?
    let matchedTeams: [String]
    let supportingHandles: [String]
    let isPopular: Bool
}

private struct SocialLeagueBadgeCatalog {
    let lookup: [String: URL]
    let teams: [SocialLeagueCatalogTeam]
    
    static let empty = SocialLeagueBadgeCatalog(lookup: [:], teams: [])
}

private struct SocialLeagueCatalogTeam {
    let displayName: String
    let badgeURL: URL?
}

private struct SportsDBLeagueTeamsResponse: Decodable {
    let teams: [SportsDBTeam]?
}

private struct SportsDBTeam: Decodable {
    let strTeam: String?
    let strTeamShort: String?
    let strTeamAlternate: String?
    let strBadge: String?
}






private struct SwipeableTeamRow: View {
    let team: FollowedTeamItem
    let onToggleAlerts: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TeamBadgeView(
                badgeURL: {
                    if let urlString = team.badgeURLString, let url = URL(string: urlString) {
                        return url
                    }
                    return TeamBrandService.shared.badgeURL(for: team.teamName)
                }(),
                teamName: team.teamName,
                size: 32
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(team.teamName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                
                Text(AnalyticalDataEngine.categoryDisplayName(for: team.sportCategory))
                    .font(.system(size: 11))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            
            Spacer()
            
            Button {
                HapticManager.impact(.light)
                onToggleAlerts()
            } label: {
                Label(
                    (team.alertsEnabled ?? true) ? "Alerts On" : "Muted",
                    systemImage: (team.alertsEnabled ?? true) ? "bell.fill" : "bell.slash.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle((team.alertsEnabled ?? true) ? FottyTheme.success : FottyTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(FottyTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
        }
        .padding(FottyTheme.spacingMD)
        .cardStyle()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.notification(.warning)
                onDelete()
            } label: {
                Label("Unfollow", systemImage: "person.badge.minus")
            }
        }
        .contextMenu {
            Button {
                HapticManager.impact(.light)
                onToggleAlerts()
            } label: {
                Label(
                    (team.alertsEnabled ?? true) ? "Mute Alerts" : "Enable Alerts",
                    systemImage: (team.alertsEnabled ?? true) ? "bell.slash" : "bell"
                )
            }
            
            Divider()
            
            Button(role: .destructive) {
                HapticManager.notification(.warning)
                onDelete()
            } label: {
                Label("Unfollow", systemImage: "person.badge.minus")
            }
        }
    }
}
