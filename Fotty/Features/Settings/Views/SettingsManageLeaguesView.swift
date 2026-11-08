import SwiftUI
import SwiftData

/// A selection preview, using only the caller's already-loaded lineup. It never
/// fetches sources or changes fixture, competition or follow identities.
@MainActor
enum HomeInterestsEditorPolicy {
    static func initialSport(sports: Set<String>, leagues: [FollowedLeagueItem], teams: [FollowedTeamItem]) -> String {
        let represented = sports
            .union(leagues.compactMap { SportsPersonalizationPolicy.league(for: $0)?.sportCategory })
            .union(teams.map { SportsPersonalizationPolicy.identity(for: $0).sportCategory })
        return SportsInterestPreferences.orderedIDs.first(where: represented.contains) ?? "football"
    }

    static func initialTeamLeague(sport: String, followedLeagues: [FollowedLeagueItem]) -> String? {
        let choices = TeamOnboardingCatalog.options.filter { $0.sport == sport }
        let selectedIDs = Set(followedLeagues.compactMap { SportsPersonalizationPolicy.league(for: $0)?.id })
        return choices.first(where: { selectedIDs.contains($0.competitionID) })?.name ?? choices.first?.name
    }

    static func selectionNames(sports: Set<String>, leagues: [FollowedLeagueItem], teams: [FollowedTeamItem]) -> [String] {
        let sportNames = SportsInterestPreferences.orderedIDs.filter(sports.contains)
            .map(AnalyticalDataEngine.categoryDisplayName(for:))
        let leagueNames = leagues.compactMap { SportsPersonalizationPolicy.league(for: $0)?.name }.sorted()
        let teamNames = teams.map { SportsPersonalizationPolicy.identity(for: $0).displayName }.sorted()
        return sportNames + Array(Set(leagueNames)).sorted() + Array(Set(teamNames)).sorted()
    }

    static func previewItems(events: [AnalyticalDataEngine.EventReference],
                             teams: [FollowedTeamItem], leagues: [FollowedLeagueItem], sports: Set<String>,
                             onlySelected: Bool, now: Date, limit: Int = 2) -> [HomeSportsDiscovery.Item] {
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: teams, leagues: leagues, sports: sports)
        let count = teams.count + leagues.count + selection.sportIDs.count
        let restricted = HomeInterestPreferences.isActive(enabled: onlySelected, selectedInterestCount: count)
        let horizon = HomeUpcomingPresentationPolicy.horizon(personalized: restricted)
        let items = HomeSportsDiscovery(events: events, now: now).items.filter { item in
            let isFollowed = SportsPersonalizationPolicy.isFollowed(event: item.event, selection: selection)
            guard HomeInterestPreferences.shouldInclude(isFollowed: isFollowed, enabled: onlySelected, selectedInterestCount: count) else { return false }
            return item.isOnNow || (item.phase == .upcoming && (item.event.kickoffDate ?? .distantFuture) <= now.addingTimeInterval(horizon))
        }
        let ordered = HomeSportsDiscovery.prioritized(items) { item in
            let followed = SportsPersonalizationPolicy.isFollowed(event: item.event, selection: selection)
            return .init(phase: CricketActivityPresentationPolicy.homePhaseRank(for: item), relevance: followed ? 0 : 1, available: 0)
        }
        return Array(ordered.prefix(max(0, limit)))
    }
}

struct SettingsManageLeaguesView: View {
    var previewEvents: [AnalyticalDataEngine.EventReference] = []
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeInterestPreferences.onlyShowSelectedKey) private var onlyShowSelectedInterests = false
    @AppStorage(SportsInterestPreferences.storageKey) private var followedSportsRaw = SportsInterestPreferences.emptyValue
    @Query(sort: \FollowedTeamItem.teamName, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query(sort: \FollowedLeagueItem.leagueName, order: .forward) private var followedLeagues: [FollowedLeagueItem]
    @State private var saveError: String?
    @State private var browsingSport = "football"
    @State private var initializedBrowsingSport = false
    @State private var teamLeague: TeamOnboardingCatalog.Option?

    private var followedSportIDs: Set<String> { SportsInterestPreferences.canonicalIDs(from: followedSportsRaw) }
    private var hasSavedInterests: Bool { !followedTeams.isEmpty || !followedLeagues.isEmpty || !followedSportIDs.isEmpty }
    private var changesUnavailable: Bool { LocalDataStore.shared.isUsingVolatileFallback }
    private var sportName: String { AnalyticalDataEngine.categoryDisplayName(for: browsingSport) }
    private var browsingLeagues: [SportsPersonalizationPolicy.League] {
        SportsPersonalizationPolicy.leagues.filter { $0.sportCategory == browsingSport }
    }
    private var browsingTeams: [FollowedTeamItem] {
        followedTeams.filter { SportsPersonalizationPolicy.identity(for: $0).sportCategory == browsingSport }
    }
    private var startingTeamLeague: String? {
        HomeInterestsEditorPolicy.initialTeamLeague(sport: browsingSport, followedLeagues: followedLeagues)
    }

    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            List {
                if changesUnavailable {
                    Section { LocalPersistenceWarning().listRowInsets(.init()) }
                        .listRowBackground(Color.clear)
                }
                homePreviewSection
                sportsSection
                if !browsingLeagues.isEmpty { competitionsSection }
                if startingTeamLeague != nil || !browsingTeams.isEmpty { teamsSection }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Home interests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear {
            disableEmptyPreference()
            if !initializedBrowsingSport {
                browsingSport = HomeInterestsEditorPolicy.initialSport(sports: followedSportIDs, leagues: followedLeagues, teams: followedTeams)
                initializedBrowsingSport = true
            }
        }
        .onChange(of: followedTeams.count + followedLeagues.count) { _, _ in disableEmptyPreference() }
        .onChange(of: followedSportsRaw) { _, _ in disableEmptyPreference() }
        .fullScreenCover(item: $teamLeague) { option in
            TeamOnboardingView(initialLeague: option.name)
        }
        .alert("Couldn't save your interests", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var homePreviewSection: some View {
        Section {
            Toggle("Only show my interests", isOn: $onlyShowSelectedInterests)
                .tint(FottyTheme.accentText)
                .accessibilityIdentifier("interest-only-selected")
                .disabled(!hasSavedInterests || changesUnavailable)
                .accessibilityHint(hasSavedInterests ? "Limits Home to your selected sports, teams and competitions" : "Choose a sport, competition or team first")
            VStack(alignment: .leading, spacing: 10) {
                Text(HomeInterestPreferences.isActive(enabled: onlyShowSelectedInterests, selectedInterestCount: followedTeams.count + followedLeagues.count + followedSportIDs.count)
                     ? "Only your interests" : "All sports")
                    .font(.headline)
                    .foregroundStyle(FottyTheme.textPrimary)
                let names = HomeInterestsEditorPolicy.selectionNames(sports: followedSportIDs, leagues: followedLeagues, teams: followedTeams)
                if !names.isEmpty {
                    Text(names.prefix(4).joined(separator: " · ")
                         + (names.count > 4 ? " · \(names.count - 4) more" : ""))
                        .font(.subheadline)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !previewEvents.isEmpty {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let rows = HomeInterestsEditorPolicy.previewItems(events: previewEvents, teams: followedTeams,
                            leagues: followedLeagues, sports: followedSportIDs, onlySelected: onlyShowSelectedInterests, now: context.date)
                        ForEach(rows) { row in
                            HomeInterestPreviewRow(item: row)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("interest-home-preview")
        } header: {
            Text("Home preview")
        }
        .listRowBackground(FottyTheme.surface.opacity(0.5))
        .listRowSeparatorTint(FottyTheme.border)
    }

    private var sportsSection: some View {
        Section {
            Picker("Browse sport", selection: $browsingSport) {
                ForEach(SportsInterestPreferences.orderedIDs, id: \.self) { category in
                    Text(AnalyticalDataEngine.categoryDisplayName(for: category)).tag(category)
                }
            }
            .tint(FottyTheme.accentText)
            .accessibilityIdentifier("interest-browse-sport")
            Button { toggleSport(browsingSport) } label: {
                HStack(spacing: 12) {
                    SportEmblem(category: browsingSport, size: 24).accessibilityHidden(true)
                    Text("All \(sportName.lowercased())")
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: followedSportIDs.contains(browsingSport) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(followedSportIDs.contains(browsingSport) ? FottyTheme.success : FottyTheme.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle())
            .disabled(changesUnavailable)
            .accessibilityValue(followedSportIDs.contains(browsingSport) ? "Following" : "Not followed")
            .accessibilityAddTraits(followedSportIDs.contains(browsingSport) ? .isSelected : [])
            .accessibilityHint("Includes this whole sport; specific competition and team choices stay saved")
            .accessibilityIdentifier("interest-sport-\(browsingSport)")
        } header: { Text("Sports") }
        footer: {
            if !browsingLeagues.isEmpty || startingTeamLeague != nil {
                Text("Follow a whole sport, or choose specific competitions and teams below.")
            }
        }
        .listRowBackground(FottyTheme.surface.opacity(0.5))
        .listRowSeparatorTint(FottyTheme.border)
    }

    private var competitionsSection: some View {
        Section {
            ForEach(browsingLeagues) { league in
                LeagueRow(name: league.name, category: league.sportCategory, country: league.country,
                    isFollowed: isFollowed(league), onToggle: { toggleLeague(league) })
                    .disabled(changesUnavailable)
            }
        } header: { Text("Competitions") }
        .listRowBackground(FottyTheme.surface.opacity(0.5))
        .listRowSeparatorTint(FottyTheme.border)
    }

    private var teamsSection: some View {
        Section {
            ForEach(browsingTeams) { team in
                let identity = SportsPersonalizationPolicy.identity(for: team)
                HStack(spacing: 12) {
                    TeamBadgeWindow(teamName: identity.displayName, badgeURL: identity.badgeURL, size: 28, triggerSearch: false)
                    Text(identity.displayName).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FottyTheme.success).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityValue("Following")
            }
            if let initialLeague = startingTeamLeague {
                Button {
                    teamLeague = TeamOnboardingCatalog.options.first { $0.name == initialLeague }
                } label: {
                    Label("Choose teams", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(changesUnavailable)
                .accessibilityIdentifier("interest-choose-teams")
            }
            NavigationLink { SettingsManageFollowsView() } label: {
                Text("Manage all favorite teams").frame(minHeight: 44)
            }
        } header: { Text("Teams") }
        .listRowBackground(FottyTheme.surface.opacity(0.5))
        .listRowSeparatorTint(FottyTheme.border)
    }

    private func isFollowed(_ league: SportsPersonalizationPolicy.League) -> Bool {
        followedLeagues.contains { SportsPersonalizationPolicy.league(for: $0)?.id == league.id }
    }

    private func disableEmptyPreference() {
        if !hasSavedInterests { onlyShowSelectedInterests = false }
    }

    private func toggleLeague(_ league: SportsPersonalizationPolicy.League) {
        guard !changesUnavailable else { return }
        do {
            let enabled = !isFollowed(league)
            try SportsPersonalizationStore.setLeagueFromView(league, enabled: enabled, in: modelContext)
            if !enabled, followedTeams.isEmpty, followedSportIDs.isEmpty,
               followedLeagues.allSatisfy({ SportsPersonalizationPolicy.league(for: $0)?.id == league.id }) {
                onlyShowSelectedInterests = false
            }
            HapticManager.impact(.light)
        } catch { saveError = "The change wasn't saved. Your previous choices are kept; please try again." }
    }

    private func toggleSport(_ category: String) {
        guard !changesUnavailable else { return }
        do {
            try SportsInterestPreferences.setEnabled(category, enabled: !followedSportIDs.contains(category))
            disableEmptyPreference()
            HapticManager.impact(.light)
        } catch { saveError = "The change wasn't saved. Your previous choices are kept; please try again." }
    }
}

private struct HomeInterestPreviewRow: View {
    let item: HomeSportsDiscovery.Item
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: -4) {
                TeamBadgeWindow(teamName: item.event.homeName, badgeURL: item.event.homeBadgeURL, size: 24, triggerSearch: false)
                if !item.event.awayName.isEmpty {
                    TeamBadgeWindow(teamName: item.event.awayName, badgeURL: item.event.awayBadgeURL, size: 24, triggerSearch: false)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.event.displayTitle).font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.statusLabel).font(.caption).foregroundStyle(FottyTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LeagueRow: View {
    let name: String
    let category: String
    let country: String
    let isFollowed: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(category.replacingOccurrences(of: "-", with: " ").capitalized) • \(country)")
                        .font(.caption)
                        .foregroundColor(FottyTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: isFollowed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isFollowed ? FottyTheme.success : FottyTheme.textTertiary)
                    .font(.title2)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FottyPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isFollowed ? "Following" : "Not followed")
        .accessibilityAddTraits(isFollowed ? .isSelected : [])
        .accessibilityHint(isFollowed
            ? "Removes this competition from Home interests and My Matchday"
            : "Adds recognized fixtures from this competition to Home interests and My Matchday")
    }
}
