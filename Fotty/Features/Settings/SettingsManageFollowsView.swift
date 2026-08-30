import SwiftUI
import SwiftData

struct SettingsManageFollowsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FollowedTeamItem.teamName, order: .forward) private var followedTeams: [FollowedTeamItem]
    @State private var isShowingAddTeams = false
    @StateObject private var brandService = TeamBrandService.shared
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            
            VStack {
                if followedTeams.isEmpty {
                    VStack(spacing: FottyTheme.spacingLG) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 60))
                            .foregroundColor(FottyTheme.textTertiary)
                        
                        Text("No teams followed yet")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(FottyTheme.textPrimary)
                        
                        Text("Follow teams to add their fixtures to My Matchday. Match alerts are in-app updates, not background push notifications.")
                            .font(.system(size: 14))
                            .foregroundColor(FottyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 100)
                } else {
                    List {
                        ForEach(followedTeams) { team in
                            HStack(spacing: FottyTheme.spacingMD) {
                                SettingsTeamBadgeView(teamName: team.teamName, size: 40)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(team.teamName)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(FottyTheme.textPrimary)
                                    Text(team.sportCategory.capitalized)
                                        .font(.system(size: 12))
                                        .foregroundColor(FottyTheme.textSecondary)
                                }
                                
                                Spacer()

                                Button {
                                    team.alertsEnabled = !(team.alertsEnabled ?? true)
                                    try? modelContext.save()
                                    MatchAlertPreferences.synchronize(from: followedTeams)
                                } label: {
                                    Image(systemName: (team.alertsEnabled ?? true) ? "bell.fill" : "bell.slash.fill")
                                        .foregroundColor((team.alertsEnabled ?? true) ? FottyTheme.accentText : FottyTheme.textTertiary)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel((team.alertsEnabled ?? true) ? "Mute in-app updates for \(team.teamName)" : "Enable in-app updates for \(team.teamName)")
                                .accessibilityHint("Updates arrive while Home or Matchday is open and refreshing")

                                Button {
                                    deleteTeam(team)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(FottyTheme.error)
                                        .font(.system(size: 20))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
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
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Follow More Teams")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(FottyTheme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(FottyTheme.accentGradient)
                    .cornerRadius(FottyTheme.radiusMD)
                    .padding()
                }
            }
        }
        .navigationTitle("Favorite Teams")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingAddTeams) {
            TeamOnboardingView()
        }
    }
    
    private func deleteTeam(_ team: FollowedTeamItem) {
        modelContext.delete(team)
        try? modelContext.save()
        MatchAlertPreferences.synchronize(from: followedTeams.filter { $0.key != team.key })
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func deleteTeams(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(followedTeams[index])
        }
        try? modelContext.save()
        let removedKeys = Set(offsets.compactMap { followedTeams.indices.contains($0) ? followedTeams[$0].key : nil })
        MatchAlertPreferences.synchronize(from: followedTeams.filter { !removedKeys.contains($0.key) })
    }
}

struct SettingsTeamBadgeView: View {
    let teamName: String
    let size: CGFloat
    @StateObject private var brandService = TeamBrandService.shared
    
    var body: some View {
        AsyncImage(url: brandService.badgeURL(for: teamName, triggerSearch: true)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Circle()
                .fill(FottyTheme.surfaceElevated)
                .overlay(
                    Text(String(teamName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(FottyTheme.textSecondary)
                )
        }
        .frame(width: size, height: size)
    }
}
