import SwiftUI
import SwiftData

struct SettingsManageFollowsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(HomeInterestPreferences.onlyShowSelectedKey) private var onlyShowSelectedInterests = false
    @AppStorage(SportsInterestPreferences.storageKey) private var followedSportsRaw = SportsInterestPreferences.emptyValue
    @Query(sort: \FollowedTeamItem.teamName, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query private var followedLeagues: [FollowedLeagueItem]
    @State private var isShowingAddTeams = false
    @State private var saveError: String?
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            
            VStack {
                if LocalDataStore.shared.isUsingVolatileFallback {
                    LocalPersistenceWarning()
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                if followedTeams.isEmpty {
                    ContentUnavailableView(
                        "No teams followed yet",
                        systemImage: "star.slash",
                        description: Text("Follow a team to add its fixtures to My Matchday.")
                    )
                } else {
                    List {
                        ForEach(followedTeams) { team in
                            let identity = SportsPersonalizationPolicy.identity(for: team)
                            teamRowLayout {
                              HStack(spacing: FottyTheme.spacingMD) {
                                SettingsTeamBadgeView(teamName: identity.displayName, size: 40, badgeURL: identity.badgeURL)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(identity.displayName)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(FottyTheme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(identity.sportCategory.replacingOccurrences(of: "-", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundColor(FottyTheme.textSecondary)
                                }
                                
                              }
                              .frame(maxWidth: .infinity, alignment: .leading)
                              HStack(spacing: 8) {
                                if identity.sportCategory == "football", PremierLeagueClubCatalog.contains(identity.displayName) {
                                  Button {
                                    performChange {
                                        try SportsPersonalizationStore.setAlerts(!(team.alertsEnabled ?? true), teamKeys: [identity.id], in: modelContext)
                                    }
                                } label: {
                                    Image(systemName: (team.alertsEnabled ?? true) ? "bell.fill" : "bell.slash.fill")
                                        .foregroundColor((team.alertsEnabled ?? true) ? FottyTheme.accentText : FottyTheme.textTertiary)
                                        .font(.body.weight(.semibold))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(FottyPressButtonStyle())
                                .accessibilityLabel((team.alertsEnabled ?? true) ? "Mute in-app updates for \(identity.displayName)" : "Enable in-app updates for \(identity.displayName)")
                                .accessibilityHint("Updates arrive while Home or Matchday is open and refreshing")
                                }

                                Button {
                                    deleteTeam(team)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(FottyTheme.error)
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(FottyPressButtonStyle())
                                .accessibilityLabel("Unfollow \(identity.displayName)")
                                .accessibilityHint("Removes this team's automatic fixtures; individually saved matches stay saved")
                              }
                              .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(FottyTheme.surface.opacity(0.5))
                            .listRowSeparatorTint(FottyTheme.border)
                        }
                        .onDelete(perform: deleteTeams)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
                
                Spacer()
                
                Button {
                    isShowingAddTeams = true
                } label: {
                    Label("Follow more teams", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(FottyTheme.textOnAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(FottyTheme.accent)
                .buttonBorderShape(.roundedRectangle(radius: FottyTheme.radiusMD))
                .frame(maxWidth: 480)
                .padding()
            }
        }
        .navigationTitle("Favorite Teams")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: followedTeams.count + followedLeagues.count) { _, count in
            if count == 0, SportsInterestPreferences.canonicalIDs(from: followedSportsRaw).isEmpty { onlyShowSelectedInterests = false }
        }
        .fullScreenCover(isPresented: $isShowingAddTeams) {
            TeamOnboardingView()
        }
        .alert("Couldn't save your teams", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var teamRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: FottyTheme.spacingMD))
    }
    
    private func deleteTeam(_ team: FollowedTeamItem) {
        let key = SportsPersonalizationPolicy.identity(for: team).id
        if performChange({ try SportsPersonalizationStore.removeTeams(keys: [key], in: modelContext) }) {
            disableHomeRestrictionIfRemovingLastTeams([key])
        }
    }
    
    private func deleteTeams(at offsets: IndexSet) {
        let keys = Set(offsets.compactMap { index in
            followedTeams.indices.contains(index) ? SportsPersonalizationPolicy.identity(for: followedTeams[index]).id : nil
        })
        if performChange({ try SportsPersonalizationStore.removeTeams(keys: keys, in: modelContext) }) {
            disableHomeRestrictionIfRemovingLastTeams(keys)
        }
    }

    private func disableHomeRestrictionIfRemovingLastTeams(_ keys: Set<String>) {
        let remainingTeams = followedTeams.filter {
            !keys.contains(SportsPersonalizationPolicy.identity(for: $0).id)
        }
        if remainingTeams.isEmpty && followedLeagues.isEmpty && SportsInterestPreferences.canonicalIDs(from: followedSportsRaw).isEmpty {
            onlyShowSelectedInterests = false
        }
    }

    @discardableResult
    private func performChange(_ operation: () throws -> Void) -> Bool {
        guard !LocalDataStore.shared.isUsingVolatileFallback else {
            saveError = "Favorite teams cannot be saved while Fotty is using temporary storage. Restart Fotty and try again."
            return false
        }
        do {
            try operation()
            HapticManager.impact(.light)
            return true
        } catch {
            saveError = "The change wasn't saved. Your previous choices are kept; please try again."
            return false
        }
    }
}

struct SettingsTeamBadgeView: View {
    let teamName: String
    let size: CGFloat
    var badgeURL: URL? = nil
    var body: some View {
        TeamBadgeWindow(
            teamName: teamName,
            badgeURL: badgeURL,
            size: size,
            triggerSearch: true
        )
    }
}
