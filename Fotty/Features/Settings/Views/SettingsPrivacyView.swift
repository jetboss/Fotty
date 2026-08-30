import SwiftUI

struct SettingsPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: FottyTheme.spacingXL) {
                        SettingsSection(title: "On This Device") {
                            privacyDisclosureRow(
                                icon: "internaldrive.fill",
                                color: FottyTheme.success,
                                title: "Local profile and preferences",
                                detail: "Your profile, followed teams, saved matches, notification choices, local messages, FPL manager ID, drafts, and Coach history are stored on this device."
                            )
                            SettingsDivider()
                            privacyDisclosureRow(
                                icon: "icloud.slash.fill",
                                color: .gray,
                                title: "No account sync",
                                detail: "Cloud accounts and cross-device social sync are currently unavailable."
                            )
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
                        }

                        SettingsSection(title: "Network Use") {
                            privacyDisclosureRow(
                                icon: "network",
                                color: .blue,
                                title: "Football data",
                                detail: "Fotty contacts configured football-data services to load fixtures, scores, teams, and tables."
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

                        Text("Local diagnostic records are never uploaded automatically. Deleting Fotty removes its on-device data through iOS. You can revoke notifications in the Settings app and avoid Smart Coach whenever you do not want Coach data sent over the network.")
                            .font(.system(size: 11))
                            .foregroundStyle(FottyTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(FottyTheme.spacingMD)
                }
            }
            .navigationTitle("Privacy & Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fottyStandardSheetChrome()
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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
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

                    Text("Fotty stores at most 250 quality events for 14 days. These records never contain match names, manager IDs, stream URLs, credentials, or Coach prompts, and they are never uploaded automatically.")
                        .font(.footnote)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(FottyTheme.spacingMD)
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
            Text("This removes Fotty's local reliability records and cannot be undone.")
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(FottyTheme.textPrimary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(FottyTheme.textSecondary)
        }
        .font(.system(size: 14))
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 12)
    }

    private func refresh() {
        summary = FottyQualityStore.shared.summary()
        exportText = FottyQualityStore.shared.exportJSON()
    }
}
