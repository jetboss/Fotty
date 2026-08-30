import SwiftUI
import SwiftData
import PhotosUI

struct SettingsScreen: View {
    @AppStorage(FottyAppearance.storageKey) private var appearance = FottyAppearance.dark.rawValue
    var onOpenFPL: (() -> Void)? = nil
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]
    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]

    @State private var isShowingEditProfile = false

    private var activeProfile: UserProfile? {
        profiles.first(where: { $0.id == "local-profile" }) ?? profiles.first
    }

    private var profileDisplayName: String {
        let value = activeProfile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Football Fan" : value
    }

    private var profileUsername: String {
        let value = activeProfile?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "fan" : value
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                FottyTheme.background.ignoresSafeArea()

                // Animated background pattern
                PitchPattern()
                    .opacity(0.08)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: FottyTheme.spacingLG) {
                        // Main Sections
                        VStack(spacing: FottyTheme.spacingLG) {
                            footballPreferencesSection
                            streamPluginsSection
                            notificationsSection
                            deadlineNotificationsSection
                            privacySection
                            supportSection
                            localProfileSection
                        }
                    }
                    .padding(FottyTheme.spacingMD)
                    .padding(.bottom, 24)
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .tint(FottyTheme.accentText)
            .sheet(isPresented: $isShowingEditProfile) {
                Group {
                    if let profile = activeProfile {
                        SettingsProfileEditView(profile: profile)
                    } else {
                        // Fallback for when no profile exists yet
                        NavigationStack {
                            ZStack {
                                FottyTheme.background.ignoresSafeArea()
                                VStack(spacing: 20) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 60))
                                        .foregroundStyle(FottyTheme.accentText)
                                    Text("No Profile Found")
                                        .font(.headline)
                                        .foregroundStyle(FottyTheme.textPrimary)
                                    Button("Create Local Profile") {
                                        let newProfile = UserProfile(id: "local-profile")
                                        modelContext.insert(newProfile)
                                        try? modelContext.save()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(FottyTheme.accentText)
                                }
                            }
                            .navigationTitle("Edit Profile")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { isShowingEditProfile = false }
                                }
                            }
                        }
                    }
                }
                .fottyStandardSheetChrome()
            }
            .onAppear {
                ensureProfileExists()
            }
        }
    }

    private func ensureProfileExists() {
        if profiles.isEmpty {
            let newProfile = UserProfile(id: "local-profile")
            modelContext.insert(newProfile)
            try? modelContext.save()
        }
    }

    // MARK: - Sections

    private var localProfileSection: some View {
        SettingsSection(title: "On this device") {
            SettingsRow(
                icon: "person.crop.circle",
                iconColor: FottyTheme.accentText,
                title: "Local profile",
                subtitle: "Optional name and avatar. Separate from your connected FPL team."
            ) { isShowingEditProfile = true }
        }
    }

    private var footballPreferencesSection: some View {
        SettingsSection(title: "Preferences") {
            NavigationLink {
                SettingsAppearanceView()
            } label: {
                SettingsRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: FottyTheme.accentText,
                    title: "Appearance",
                    subtitle: "Choose light, dark or your device setting",
                    value: FottyAppearance.saved(appearance).title
                )
            }
            .accessibilityIdentifier("settings-appearance")
            SettingsDivider()
            NavigationLink {
                SettingsManageFollowsView()
            } label: {
                SettingsRow(
                    icon: "star.fill",
                    iconColor: FottyTheme.accentText,
                    title: "Favorite Teams",
                    value: followedTeams.count == 1 ? "1 team" : "\(followedTeams.count) teams"
                )
            }
            SettingsDivider()
            NavigationLink {
                SettingsManageLeaguesView()
            } label: {
                SettingsRow(icon: "trophy.fill", iconColor: FottyTheme.accentText, title: "Favorite Leagues")
            }
        }
    }

    private var streamPluginsSection: some View {
        SettingsSection(title: "Playback") {
            NavigationLink {
                StreamPluginsSettingsView()
            } label: {
                SettingsRow(
                    icon: "puzzlepiece.extension.fill",
                    iconColor: FottyTheme.accentText,
                    title: "Broadcast Sources",
                    subtitle: "Manage the sources Fotty can use for playback"
                )
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: "Match updates") {
            VStack(alignment: .leading, spacing: 8) {
                Text("While using Fotty").font(.headline)
                Text("Updates for followed Premier League teams while Home or Matchday is open. Not background alerts.")
                DisclosureGroup("How match updates work") { Text(FottyHelpContent.matchAlerts) }
            }
            .font(.callout)
            .foregroundStyle(FottyTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(FottyTheme.spacingMD)
            SettingsDivider()
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
        }
    }

    private var deadlineNotificationsSection: some View {
        SettingsSection(title: "FPL deadline reminders") {
            Text("Scheduled on this device, even when Fotty is closed. Enable them from your FPL plan.")
                .font(.callout)
                .foregroundStyle(FottyTheme.textSecondary)
                .padding(FottyTheme.spacingMD)
            if let onOpenFPL {
                SettingsRow(icon: "calendar.badge.clock", iconColor: FottyTheme.accentText, title: "Open FPL plan", subtitle: "Team, squad and deadline reminders", action: onOpenFPL)
            }
            if NotificationManager.shared.permissionStatus == .notDetermined {
                SettingsRow(
                    icon: "bell.badge.fill",
                    iconColor: FottyTheme.accentText,
                    title: "Enable System Notifications",
                    value: "Optional",
                    showChevron: false
                ) {
                    Task {
                        _ = await NotificationManager.shared.requestPermission()
                    }
                }
                SettingsDivider()
            } else if NotificationManager.shared.permissionStatus == .denied {
                SettingsRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red,
                    title: "Notifications Denied",
                    value: "Fix in Settings",
                    showChevron: false
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                SettingsDivider()
            }

        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy & Security") {
            NavigationLink {
                SettingsPrivacyView()
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    iconColor: FottyTheme.success,
                    title: "Privacy & Local Data",
                    subtitle: "What stays on this device and what uses the network"
                )
            }
        }
    }

    private var supportSection: some View {
        SettingsSection(title: "Support & About") {
            NavigationLink {
                FottyHelpView()
            } label: {
                SettingsRow(icon: "questionmark.circle.fill", iconColor: .gray, title: "Fotty Help", subtitle: "How watching, Matchday, FPL and alerts work")
            }
            .accessibilityIdentifier("settings-help")
            SettingsDivider()
            NavigationLink {
                FottyFeedbackView()
            } label: {
                SettingsRow(icon: "megaphone.fill", iconColor: .blue, title: "Report a problem", subtitle: "Prepare a report for TestFlight or share it")
            }
            .accessibilityIdentifier("settings-feedback")
            SettingsDivider()
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: .gray,
                title: "App Version",
                value: appVersionDisplay,
                showChevron: false,
                action: nil
            )
        }
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "v\(version) (\(build))"
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
            Text("Choose how Fotty looks")
                .font(FottyTheme.typeSectionTitle)
                .foregroundStyle(FottyTheme.textPrimary)

            VStack(spacing: 12) {
                ForEach(FottyAppearance.allCases) { option in
                    appearanceChoice(option)
                }
            }

            Text("Your choice is saved on this device. The video player and football pitch keep their dark background in every mode.")
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    .font(.title2)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(FottyTheme.typeModuleTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(option == .dark ? "Fotty’s default appearance" : (option == .light ? "Warm, light surfaces" : "Follow your device’s light or dark setting"))
                        .font(FottyTheme.typeBody)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? FottyTheme.accentText : FottyTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(minHeight: 68)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD)
                    .strokeBorder(selected ? FottyTheme.accentText : FottyTheme.borderStrong, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appearance-\(option.rawValue)")
    }
}

// MARK: - Dedicated Profile Edit View
struct SettingsProfileEditView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                if let data = selectedImageData ?? profile.avatarImageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: profile.avatarSymbol ?? "person.crop.circle.fill")
                                        .resizable()
                                        .frame(width: 100, height: 100)
                                        .foregroundStyle(FottyTheme.textTertiary)
                                }

                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    Text("Change Photo")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(FottyTheme.accentText)
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 10)
                    }

                    Section {
                        TextField("Display Name", text: $displayName)
                            .foregroundStyle(FottyTheme.textPrimary)
                        TextField("Username", text: $username)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .textInputAutocapitalization(.never)
                        TextField("Bio", text: $bio, axis: .vertical)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .lineLimit(3...5)
                    } header: {
                        Text("Personal Information")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                    .listRowBackground(FottyTheme.surface.opacity(0.5))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.displayName = displayName.isEmpty ? "Football Fan" : displayName
                        profile.username = username.isEmpty ? nil : username
                        profile.bio = bio.isEmpty ? nil : bio
                        if let selectedImageData {
                            profile.avatarImageData = selectedImageData
                            profile.avatarImageUpdatedAt = Date()
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(FottyTheme.accentText)
                }
            }
            .onAppear {
                displayName = profile.displayName
                username = profile.username ?? ""
                bio = profile.bio ?? ""
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                    }
                }
            }
        }
        .fottyStandardSheetChrome()
    }
}
