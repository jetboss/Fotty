import SwiftUI
import SwiftData

struct SettingsScreen: View {
    @AppStorage(SportsInterestPreferences.storageKey) private var followedSportsRaw = SportsInterestPreferences.emptyValue
    @Environment(\.fottyWideLayout) private var usesWideLayout
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(FottyAppearance.storageKey) private var appearance = FottyAppearance.dark.rawValue
    @AppStorage(MatchdayPreferences.showKickoffClashesKey)
    private var showKickoffClashes = MatchdayPreferences.defaultShowKickoffClashes
    var onOpenFPL: (() -> Void)? = nil
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showsOwnerStatus = false
    @AppStorage(SportsReminderBackgroundRefresh.preferenceKey) private var refreshRemindersInBackground = false
    @State private var reminderRefresh = SportsReminderBackgroundRefresh.shared

    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]
    @Query(sort: \FollowedLeagueItem.createdAt, order: .forward) private var followedLeagues: [FollowedLeagueItem]

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                FottyTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                        Text("Settings")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .frame(minHeight: 44, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        // Main Sections
                        VStack(spacing: FottyTheme.spacingLG) {
                            if LocalDataStore.shared.isUsingVolatileFallback {
                                LocalPersistenceWarning(
                                    detail: "Favorite teams, leagues and cached fixtures can't be saved right now. Matchday bookmarks are unaffected. Restart Fotty, then report the problem if it returns."
                                )
                            }
                            settingsColumns {
                                VStack(spacing: FottyTheme.spacingLG) {
                                    appearanceSection
                                    homePreferencesSection
                                    streamPluginsSection
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                VStack(spacing: FottyTheme.spacingLG) {
                                    privacySection
                                    supportSection
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                    .padding(FottyTheme.spacingMD)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(FottyTheme.accentText)
            .onAppear { NotificationManager.shared.checkPermissionStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { NotificationManager.shared.checkPermissionStatus() }
            }
            .sheet(isPresented: $showsOwnerStatus) {
                NavigationStack { FottyOwnerStatusView() }
                    .fottyStandardSheetChrome()
            }
        }
    }

    // MARK: - Sections

    // Changing only the layout preserves the same controls and destination state.
    private var settingsColumns: AnyLayout {
        usesWideLayout
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: FottyTheme.spacingLG))
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            NavigationLink {
                SettingsAppearanceView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: FottyTheme.accentText,
                    title: "Appearance",
                    value: FottyAppearance.saved(appearance).title
                )
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-appearance")
        }
    }

    private var homePreferencesSection: some View {
        SettingsSection(title: "Home & Matchday") {
            NavigationLink {
                SettingsManageLeaguesView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(
                    icon: "trophy.fill",
                    iconColor: FottyTheme.accentText,
                    title: "Home interests",
                    value: interestSelectionSummary
                )
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-interests")
            SettingsDivider()
            SettingsToggleRow(
                icon: "calendar.badge.exclamationmark",
                iconColor: FottyTheme.accentText,
                title: "Show kickoff clashes",
                subtitle: "Flag overlapping matches in My Matchday",
                isOn: $showKickoffClashes
            )
        }
    }

    private var notificationPermissionSummary: String {
        switch NotificationManager.shared.permissionStatus {
        case .authorized: return "Allowed"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporary"
        case .denied: return "Off in Settings"
        case .notDetermined: return "Not enabled"
        @unknown default: return "Review"
        }
    }

    private var notificationPreferences: some View {
        ScrollView {
            settingsColumns {
              VStack(spacing: FottyTheme.spacingLG) {
                SettingsSection(title: "System permission") {
                    SettingsRow(icon: "bell.badge.fill", iconColor: FottyTheme.accentText,
                                title: notificationPermissionSummary,
                                value: NotificationManager.shared.permissionStatus == .notDetermined ? "Enable" : "Manage",
                                valueRole: .action) {
                        if NotificationManager.shared.permissionStatus == .notDetermined {
                            Task { _ = await NotificationManager.shared.requestPermission() }
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
              VStack(spacing: FottyTheme.spacingLG) {
                notificationsSection
                SettingsSection(title: "Match reminders") {
                    SettingsToggleRow(icon: "clock.arrow.circlepath", iconColor: FottyTheme.accentText,
                        title: "Update reminders in background",
                        subtitle: "Check for changed or cancelled fixtures when iOS allows",
                        isOn: Binding(get: { refreshRemindersInBackground }, set: {
                            refreshRemindersInBackground = $0
                            reminderRefresh.setEnabled($0)
                        }))
                        .accessibilityIdentifier("sports-reminder-background-toggle")
                    if refreshRemindersInBackground {
                        Text(SportsReminderBackgroundRefresh.disclosure)
                            .font(.footnote).foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(FottyTheme.spacingMD)
                        if reminderRefresh.schedulingUnavailable {
                            Text("Background checks aren’t available right now. Opening Fotty still updates your reminders.")
                                .font(.subheadline).padding(FottyTheme.spacingMD)
                                .accessibilityIdentifier("sports-reminder-background-unavailable")
                        }
                    }
                }
                Text(FottyHelpContent.scheduledMatchReminders)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onOpenFPL {
                    SettingsSection(title: "FPL deadline reminders") {
                        SettingsRow(icon: "calendar.badge.clock", iconColor: FottyTheme.accentText,
                                    title: "Manage in FPL", action: onOpenFPL)
                    }
                }
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(FottyTheme.spacingMD)
            .frame(maxWidth: .infinity)
        }
        .background(FottyTheme.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings-notifications-screen")
    }

    private var streamPluginsSection: some View {
        SettingsSection(title: "Playback & alerts") {
            NavigationLink { SportsPlaybackPreferencesView().toolbar(.visible, for: .navigationBar) } label: {
                SettingsRow(icon: "play.rectangle", iconColor: FottyTheme.accentText,
                    title: "Playback preferences", keepsDisclosureInline: true)
            }
            .buttonStyle(SettingsRowButtonStyle())
            SettingsDivider()
            NavigationLink {
                StreamPluginsSettingsView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(
                    icon: "puzzlepiece.extension.fill",
                    iconColor: FottyTheme.accentText,
                    title: "Playback sources",
                    keepsDisclosureInline: true
                )
            }
            .buttonStyle(SettingsRowButtonStyle())
            SettingsDivider()
            NavigationLink {
                notificationPreferences
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(icon: "bell.fill", iconColor: FottyTheme.accentText,
                            title: "Notifications", value: notificationPermissionSummary)
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-notifications")
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: "In-app match updates") {
            SettingsToggleRow(icon: "flag.fill", iconColor: FottyTheme.success, title: "Kickoff Updates", isOn: $viewModel.notifKickoff)
            SettingsDivider()
            SettingsToggleRow(icon: "soccerball", iconColor: .red, title: "Goal Updates", isOn: $viewModel.notifGoals)
            SettingsDivider()
            SettingsToggleRow(icon: "timer", iconColor: FottyTheme.accentText, title: "Full-time Updates", isOn: $viewModel.notifFulltime)
            SettingsDivider()
            SettingsToggleRow(
                icon: "eye.slash.fill",
                iconColor: FottyTheme.accentText,
                title: "Spoiler-safe Match Alerts",
                subtitle: "Hide scores and result details in notifications",
                isOn: $viewModel.notificationSpoilerProtection
            )
            Text(FottyHelpContent.matchAlertSettingsScope)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FottyTheme.spacingMD)
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Your data") {
            NavigationLink { SettingsSportsContinuityView() } label: {
                SettingsRow(icon: "ipad.and.iphone", iconColor: FottyTheme.accentText,
                            title: "Sports continuity", keepsDisclosureInline: true)
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-sports-continuity")
            SettingsDivider()
            NavigationLink {
                SettingsPrivateBackupView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(icon: "lock.doc.fill", iconColor: FottyTheme.accentText,
                            title: "Backup & restore", keepsDisclosureInline: true)
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-backup")
            SettingsDivider()
            NavigationLink {
                SettingsPrivacyView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    iconColor: FottyTheme.success,
                    title: "Privacy",
                    keepsDisclosureInline: true
                )
            }
            .buttonStyle(SettingsRowButtonStyle())
        }
    }

    private var supportSection: some View {
        SettingsSection(title: "Support & About") {
            NavigationLink {
                FottyHelpView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(icon: "questionmark.circle.fill", iconColor: .gray, title: "Fotty Help",
                            keepsDisclosureInline: true)
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-help")
            SettingsDivider()
            NavigationLink {
                FottyFeedbackView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsRow(icon: "megaphone.fill", iconColor: .blue, title: "Report a Problem",
                            keepsDisclosureInline: true)
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings-feedback")
            SettingsDivider()
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: .gray,
                title: FottyBrand.displayName,
                value: appVersionDisplay,
                showChevron: false,
                action: nil
            )
            .onTapGesture(count: 7) { showsOwnerStatus = true }
        }
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "v\(version) (\(build))"
    }

    private var interestSelectionSummary: String {
        let count = followedTeams.count + followedLeagues.count + SportsInterestPreferences.canonicalIDs(from: followedSportsRaw).count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

}

// MARK: - Appearance

struct SettingsAppearanceView: View {
    @AppStorage(FottyAppearance.storageKey) private var appearance = FottyAppearance.dark.rawValue

    var body: some View {
        ScrollView {
            SettingsAppearanceOptions(appearance: $appearance)
        }
        .background(FottyTheme.background.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings-appearance-screen")
    }
}

/// The real choice content is separate from its scrolling/navigation container
/// so previews can verify it without UIKit's offscreen ScrollView limitations.
struct SettingsAppearanceOptions: View {
    @Binding var appearance: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 0) {
                ForEach(FottyAppearance.allCases) { option in
                    if option != FottyAppearance.allCases.first {
                        Divider().overlay(FottyTheme.border).padding(.leading, 64)
                    }
                    appearanceChoice(option)
                }
            }
            .background(FottyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .padding(FottyTheme.spacingMD)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private func appearanceChoice(_ option: FottyAppearance) -> some View {
        let selected = FottyAppearance.saved(appearance) == option
        return Button {
            appearance = option.rawValue
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option == .dark ? "moon.fill" : (option == .light ? "sun.max.fill" : "circle.lefthalf.filled"))
                    .font(.body)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(option.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(selected ? FottyTheme.accentText : FottyTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(minHeight: 56)
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
        }
        .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusMD))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appearance-\(option.rawValue)")
    }
}
