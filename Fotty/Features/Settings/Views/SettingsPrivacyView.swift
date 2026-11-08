import SwiftUI

struct SettingsPrivacyView: View {
    @State private var lastLiveStore = LastLiveMatchStore.shared

    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
                
            ScrollView {
                VStack(spacing: FottyTheme.spacingXL) {
                        SettingsSection(title: "On This Device") {
                            privacyDisclosureRow(
                                icon: "internaldrive.fill",
                                color: FottyTheme.success,
                                title: "Preferences and planning",
                                detail: "Followed teams, saved matches, notification choices, public FPL manager ID, local drafts, and Coach history are stored on this device."
                            )
                            SettingsDivider()
                            privacyDisclosureRow(
                                icon: "icloud",
                                color: .gray,
                                title: "Optional sports sync",
                                detail: "Sports continuity can sync sports interests, viewing-window choices and saved match identities through your Apple Account, only after you enable it. Reminders, viewing history and stream links are not included."
                            )
                            SettingsDivider()
                            NavigationLink {
                                SettingsPrivateBackupView()
                            } label: {
                                SettingsRow(
                                    icon: "lock.doc.fill",
                                    iconColor: FottyTheme.accentText,
                                    title: "Private Backup",
                                    subtitle: "Encrypted export and reviewed restore of your local setup"
                                )
                            }
                            .buttonStyle(SettingsRowButtonStyle())
                            .accessibilityIdentifier("settings-private-backup-link")
                            SettingsDivider()
                            NavigationLink {
                                SettingsQualityDiagnosticsView()
                            } label: {
                                SettingsRow(
                                    icon: "waveform.path.ecg.rectangle.fill",
                                    iconColor: .purple,
                                    title: "Quality & Diagnostics",
                                    subtitle: "Review or export private on-device reliability records"
                                )
                            }
                            .buttonStyle(SettingsRowButtonStyle())
                        }

                        SettingsSection(title: "Returning to a Match") {
                            SettingsToggleRow(
                                icon: "play.rectangle",
                                iconColor: FottyTheme.accentText,
                                title: "Remember last live match",
                                subtitle: "Keep one match locally for up to 36 hours. Not included in sports sync.",
                                isOn: $lastLiveStore.isEnabled
                            )
                            .accessibilityIdentifier("settings-remember-last-live")
                            if lastLiveStore.record != nil {
                                SettingsDivider()
                                SettingsRow(icon: "xmark.circle", iconColor: FottyTheme.textSecondary,
                                            title: "Forget last match") {
                                    lastLiveStore.clear()
                                }
                                .accessibilityIdentifier("settings-forget-last-live")
                            }
                        }

                        SettingsSection(title: "Network Use") {
                            NavigationLink {
                                SettingsCoachAccessView()
                            } label: {
                                SettingsRow(icon: "key.fill", iconColor: FottyTheme.accentText,
                                            title: "Coach Access", subtitle: "Manage this device's private invitation code")
                            }
                            .buttonStyle(SettingsRowButtonStyle())
                            SettingsDivider()
                            privacyDisclosureRow(
                                icon: "network",
                                color: .blue,
                                title: "Football data",
                                detail: "Fotty contacts configured football-data services to load fixtures, scores, teams, and tables. Football data provided by the Football-Data.org API."
                            )
                            SettingsDivider()
                            privacyDisclosureRow(
                                icon: "brain.head.profile.fill",
                                color: .purple,
                                title: "FPL Smart Coach",
                                detail: "Only when you send a Coach question, Fotty sends the question, an install ID, your public FPL manager ID, and bounded squad context through Fotty's Cloudflare Worker. Model questions may be processed by DeepSeek. Your FPL password is never requested."
                            )
                            SettingsDivider()
                            privacyDisclosureRow(
                                icon: "play.rectangle.fill",
                                color: FottyTheme.accentText,
                                title: "Playback providers",
                                detail: "When you choose Watch, the selected source may load a third-party player page governed by that provider's privacy terms."
                            )
                        }

                        SettingsSection(title: "Legal") {
                            SettingsRow(icon: "hand.raised.fill", iconColor: .green, title: "Privacy Policy") {
                                if let url = Config.privacyPolicyURL {
                                    UIApplication.shared.open(url)
                                }
                            }
                            SettingsDivider()
                            SettingsRow(icon: "doc.text.fill", iconColor: .blue, title: "Terms of Use") {
                                if let url = Config.termsOfUseURL {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }

                }
                .padding(FottyTheme.spacingMD)
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { lastLiveStore.pruneExpiredRecord() }
    }

    private func privacyDisclosureRow(
        icon: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: FottyTheme.spacingMD) {
            SettingsIcon(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(detail)
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 14)
    }
}

private struct SettingsQualityDiagnosticsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var summary = FottyQualitySummary.empty
    @State private var exportText = ""
    @State private var isShowingClearConfirmation = false

    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: FottyTheme.spacingLG) {
                    SettingsSection(title: "Playback Evidence") {
                        metricRow("Attempts", value: "\(summary.playbackAttempts)")
                        SettingsDivider()
                        metricRow("Proven starts", value: "\(summary.provenPlaybackStarts)")
                        SettingsDivider()
                        metricRow("Recovered in place", value: "\(summary.recoveredPlaybackEvents)")
                        SettingsDivider()
                        metricRow("Automatic switches", value: "\(summary.automaticFailovers)")
                        SettingsDivider()
                        metricRow("Resolution failures", value: "\(summary.resolutionFailures)")
                        SettingsDivider()
                        metricRow("Terminal failures", value: "\(summary.terminalPlaybackFailures)")
                        SettingsDivider()
                        metricRow("Native handoffs", value: "\(summary.nativeHandoffs)")
                        SettingsDivider()
                        metricRow(
                            "Median proven start",
                            value: summary.medianStartupMilliseconds.map { String(format: "%.1f s", Double($0) / 1_000) } ?? "No samples"
                        )
                    }

                    SettingsSection(title: "Data Integrity") {
                        metricRow("Football refresh failures", value: "\(summary.footballDataRefreshFailures)")
                        SettingsDivider()
                        metricRow("Match identity conflicts", value: "\(summary.matchIdentityConflicts)")
                        SettingsDivider()
                        metricRow("FPL refresh failures", value: "\(summary.fplRefreshFailures)")
                        SettingsDivider()
                        metricRow("Coach model requests", value: "\(summary.coachModelRequests)")
                    }

                    SettingsSection(title: "Your Controls") {
                        ShareLink(item: exportText) {
                            SettingsRow(
                                icon: "square.and.arrow.up.fill",
                                iconColor: .blue,
                                title: "Export Diagnostic Summary",
                                subtitle: "Share a redacted JSON copy",
                                showChevron: false,
                                action: nil
                            )
                        }
                        SettingsDivider()
                        SettingsRow(
                            icon: "trash.fill",
                            iconColor: .red,
                            title: "Clear Diagnostic History",
                            showChevron: false
                        ) {
                            isShowingClearConfirmation = true
                        }
                    }

                    Text("Fotty keeps at most 250 quality events and two small, dated performance summaries for up to 14 days. No match names, manager IDs, stream URLs, credentials, Coach prompts or raw diagnostic traces are included. Nothing is uploaded automatically.")
                        .font(.footnote)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(FottyTheme.spacingMD)
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Quality & Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .confirmationDialog(
            "Clear diagnostic history?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                FottyQualityStore.shared.clear()
                refresh()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes Fotty's local reliability records and performance summaries and cannot be undone.")
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        metricLayout {
            Text(title)
                .foregroundStyle(FottyTheme.textPrimary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .font(FottyTheme.typeBody)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 12)
    }

    private var metricLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    private func refresh() {
        summary = FottyQualityStore.shared.summary()
        exportText = FottyQualityStore.shared.exportJSON()
    }
}
