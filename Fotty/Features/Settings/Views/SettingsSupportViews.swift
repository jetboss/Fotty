import SwiftUI
import UIKit

enum FottyHelpContent {
    static let productScope = "Home helps everyone discover and watch available live sport. My Matchday organizes saved broadcasts and followed teams. FPL is an optional power tool for people who want official-data planning and Coach support; it is never required to browse or watch."
    static let homePersonalization = "Home shows available broadcasts and upcoming fixtures for your current selection. If Only your interests is on, other teams and competitions are hidden. Use Home interests to change this, or Browse Sports to look beyond your selection. Open a future result in Search or choose Details in Matchday to save it and set a reminder. You can also long-press a match or channel and choose Save to My Matchday, or follow a team, to build your personal list. Use the same menu to remove a saved match. Saving alone does not enable reminders."
    static let matchAlerts = "Match alerts are in-app updates for followed Premier League teams while Home or Matchday is open and refreshing. They are not background push alerts and won't reliably arrive while Fotty is closed or your device is locked."
    static let matchAlertSettingsScope = "For followed Premier League teams, while Home or Matchday is open and refreshing. These are not background push alerts."
    static let scheduledMatchReminders = "Match start reminders are separate: tap Remind me beside a future match. They can arrive with Fotty closed, subject to your notification settings."
    static let deadlineAlerts = "FPL deadline reminders are separate scheduled notifications. Once enabled in FPL, they can arrive while Fotty is closed, subject to your device's notification settings."
    static let fplDrafts = "Fotty reads public FPL data. Lineup and transfer plans stay as drafts on this device. Confirm any real changes in official FPL before the deadline."
    static let scores = "Live scores currently cover the Premier League only. Other competitions can still have broadcasts. No score is expected for those competitions; a missing score doesn't mean the broadcast is broken."
    static let playback = "Starts in counts down to the scheduled start, not guaranteed stream availability. A listed source becomes tappable two minutes before the start. Watch checks the broadcast; if none is found, use the inline Retry. Channels remain available separately. During playback, use Try again or choose another numbered source if needed."
    static let matchReminders = "Tap Remind me beside a countdown for a notification five minutes before the scheduled start. This also saves the match to My Matchday. Saving or following alone does not enable start reminders. Tap the filled bell to cancel; removing a saved match also cancels its reminder. Reminders stay on this device, can arrive with Fotty closed, and respect notification settings. Fotty can only update changed or cancelled schedules when it refreshes; it cannot learn a last-minute change while closed. Inside the final five minutes, no late reminder is scheduled."
    static let fplPoints = "Official points are the published FPL total. Provisional totals estimate pending autosubs, captain changes or bonus and can change until FPL confirms the gameweek. Check the source and last-updated label before making a decision."
    static let testFlight = "Open TestFlight, select Fotty, then choose Send Beta Feedback and paste your report. For a visual issue, take a screenshot in the TestFlight-installed app and use Share Beta Feedback when offered."
}

enum FottyFeedbackArea: String, CaseIterable, Identifiable {
    case general = "General"
    case playback = "Playback"
    case fpl = "FPL & Coach"
    case matchday = "Home & Matchday"
    case notifications = "Notifications"
    var id: String { rawValue }
}

struct FottyFeedbackDraftSeed: Equatable {
    let expected: String
    let actual: String

    static func resolved(
        existingExpected: String,
        existingActual: String,
        suggestedExpected: String?,
        suggestedActual: String?
    ) -> Self {
        // A contextual report must never replace a tester's unfinished draft.
        guard existingExpected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              existingActual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(expected: existingExpected, actual: existingActual)
        }
        return .init(
            expected: suggestedExpected?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            actual: suggestedActual?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}

/// A reviewed, local classification; it never sends a report or replaces an
/// unfinished draft. Non-playback reports retain their existing behaviour.
enum PlaybackFeedbackIssue: String, CaseIterable, Identifiable {
    case unspecified = ""
    case cannotStart = "cannot-start"
    case buffering = "buffering"
    case noSound = "no-sound"
    case wrongMatch = "wrong-match"
    case controls = "controls"
    case other = "other"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unspecified: return "Choose a problem"
        case .cannotStart: return "Won’t start"
        case .buffering: return "Keeps buffering"
        case .noSound: return "No sound"
        case .wrongMatch: return "Wrong match"
        case .controls: return "Player controls"
        case .other: return "Something else"
        }
    }
    var suggestedActual: String? {
        switch self {
        case .unspecified, .other: return nil
        case .cannotStart: return "The selected broadcast did not start."
        case .buffering: return "The broadcast repeatedly stopped to buffer."
        case .noSound: return "The broadcast played without sound."
        case .wrongMatch: return "The source showed a different match."
        case .controls: return "A player control did not respond as expected."
        }
    }
    func seed(expected: String, actual: String) -> FottyFeedbackDraftSeed {
        FottyFeedbackDraftSeed.resolved(existingExpected: expected, existingActual: actual,
            suggestedExpected: suggestedActual == nil ? nil : "Watch the selected match with working video, sound and controls.",
            suggestedActual: suggestedActual)
    }
}

struct FottyFeedbackReport {
    let area: String
    let expected: String
    let actual: String
    let version: String
    let device: String
    let system: String
    let date: Date
    var diagnostics: String? = nil
    var playbackIssue: PlaybackFeedbackIssue? = nil

    var text: String {
        var sections = [
            "Fotty beta feedback",
            "Area: \(area)",
            "App: \(version)\nDevice: \(device)\nSystem: \(system)\nReport created: \(ISO8601DateFormatter().string(from: date))",
            "What I was doing / expected:\n\(expected.trimmingCharacters(in: .whitespacesAndNewlines))",
            "What happened instead:\n\(actual.trimmingCharacters(in: .whitespacesAndNewlines))"
        ]
        if area == FottyFeedbackArea.playback.rawValue,
           let playbackIssue, playbackIssue != .unspecified {
            sections.insert("Playback problem: \(playbackIssue.title)", at: 2)
        }
        if let diagnostics, !diagnostics.isEmpty {
            sections.append("Optional on-device diagnostics (included by the tester):\n\(diagnostics)")
        }
        return sections.joined(separator: "\n\n")
    }
}

struct FottyHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                help("What Fotty is for", FottyHelpContent.productScope)
                help("Your first matchday", FottyHelpContent.homePersonalization)
                help("Watching and recovery", FottyHelpContent.playback)
                help("Score coverage", FottyHelpContent.scores)
                help("FPL points", FottyHelpContent.fplPoints)
                help("Plans aren't submitted transfers", FottyHelpContent.fplDrafts)
                help("Match alerts", FottyHelpContent.matchAlerts)
                help("Match start reminders", FottyHelpContent.matchReminders)
                help("Deadline reminders", FottyHelpContent.deadlineAlerts)
                help("Your data", "Preferences and saved matches are stored on this device. Sports continuity can sync selected sports preferences and saved match identities only after you enable it. FPL drafts remain local. Smart Coach asks for consent before sending a question and minimized context to its online service.")
                NavigationLink {
                    FottyFeedbackView()
                } label: {
                    Label("Report a problem", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(FottyTheme.background)
        .navigationTitle("Fotty Help")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FottyTheme.accentText)
    }

    private func help(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(FottyTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FottyFeedbackView: View {
    var initialArea: FottyFeedbackArea? = nil
    var initialExpected: String? = nil
    var initialActual: String? = nil
    @AppStorage("fotty.feedback.area") private var area = FottyFeedbackArea.general.rawValue
    @AppStorage("fotty.feedback.expected") private var expected = ""
    @AppStorage("fotty.feedback.actual") private var actual = ""
    @AppStorage("fotty.feedback.playbackIssue") private var playbackIssueRaw = ""
    @AppStorage("fotty.feedback.lastPrepared") private var lastPrepared = 0.0
    @State private var includeDiagnostics = false
    @State private var diagnosticText = ""
    @State private var notice: String?
    @State private var showsClearConfirmation = false
    @State private var showsReportPreview = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case expected, actual }

    private var canShare: Bool {
        !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !actual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var reportText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return FottyFeedbackReport(
            area: area,
            expected: expected,
            actual: actual,
            version: "\(info["CFBundleShortVersionString"] as? String ?? "Unknown") (\(info["CFBundleVersion"] as? String ?? "Unknown"))",
            device: UIDevice.current.model,
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            date: Date(),
            diagnostics: includeDiagnostics ? diagnosticText : nil,
            playbackIssue: PlaybackFeedbackIssue(rawValue: playbackIssueRaw)
        ).text
    }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            feedbackSection("Describe the problem") {
                Text("Tell us where you got stuck. Your draft stays on this device until you copy or share it; nothing is sent automatically.")
                Picker("Area", selection: $area) {
                    ForEach(FottyFeedbackArea.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Problem area")
                .accessibilityValue(area)
                .accessibilityHint("Choose the part of Fotty this report is about")
                if area == FottyFeedbackArea.playback.rawValue {
                    Picker("Problem", selection: $playbackIssueRaw) {
                        ForEach(PlaybackFeedbackIssue.allCases) { issue in
                            Text(issue.title).tag(issue.rawValue)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("feedback-playback-problem")
                }
                Text("What were you doing or expecting? (Required)")
                    .font(.headline)
                TextField("For example: opening a saved match", text: $expected, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .expected)
                    .accessibilityLabel("What were you doing or expecting?")
                    .accessibilityIdentifier("feedback-expected")
                Text("What happened instead? (Required)")
                    .font(.headline)
                TextField("Describe what you saw", text: $actual, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .actual)
                    .accessibilityLabel("What happened instead?")
                    .accessibilityIdentifier("feedback-actual")
                Text("Include the match, time or source number if useful. Never include passwords or private links.")
                    .font(.footnote)
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            feedbackSection("Review") {
                Toggle("Include on-device diagnostics", isOn: $includeDiagnostics)
                    .accessibilityIdentifier("feedback-diagnostics")
                Text("Includes recent playback and data outcomes, plus dated scrolling and hang summaries when Apple provides them. No personal IDs, names, URLs, credentials, Coach messages or raw diagnostic traces.")
                    .font(.footnote)
                Button {
                    showsReportPreview.toggle()
                } label: {
                    HStack {
                        Text(showsReportPreview ? "Hide report preview" : "Preview what will be shared")
                        Image(systemName: showsReportPreview ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityValue(showsReportPreview ? "Expanded" : "Collapsed")
                if showsReportPreview {
                    Text(reportText).font(.footnote.monospaced()).textSelection(.enabled)
                }
            }

            feedbackSection("Send your report") {
                Text(FottyFeedbackDelivery.testFlightSteps)
                    .font(.callout)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !canShare {
                    Label("Complete both required fields to copy or share your report.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Button("Copy report") {
                    focusedField = nil
                    UIPasteboard.general.string = reportText
                    lastPrepared = Date().timeIntervalSince1970
                    notice = FottyFeedbackDelivery.copiedNotice
                }
                .disabled(!canShare)
                .foregroundStyle(canShare ? FottyTheme.accentText : FottyTheme.textTertiary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("feedback-copy")
                ShareLink(item: reportText) {
                    Label("Share report…", systemImage: "square.and.arrow.up")
                }
                .disabled(!canShare)
                .foregroundStyle(canShare ? FottyTheme.accentText : FottyTheme.textTertiary)
                .frame(minHeight: 44)
                Text("Or choose a recipient in Mail or Messages from the share sheet. Opening it does not send the report automatically.")
                    .font(.footnote)
                    .foregroundStyle(FottyTheme.textSecondary)
                if lastPrepared > 0 {
                    Label(
                        "Last copied \(Date(timeIntervalSince1970: lastPrepared).formatted(date: .abbreviated, time: .shortened)); delivery is still unconfirmed.",
                        systemImage: "doc.on.clipboard.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(FottyTheme.textSecondary)
                }
                if let notice {
                    Text(notice).font(.callout)
                        .accessibilityIdentifier("feedback-copy-status")
                }
            }

            Button("Clear this draft", role: .destructive) { showsClearConfirmation = true }
                .frame(minHeight: 44)
          }
          .foregroundStyle(FottyTheme.textPrimary)
          .padding(20)
          .frame(maxWidth: 700, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
        .background(FottyTheme.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FottyTheme.accentText)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            let wasEmpty = expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && actual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let seeded = FottyFeedbackDraftSeed.resolved(
                existingExpected: expected,
                existingActual: actual,
                suggestedExpected: initialExpected,
                suggestedActual: initialActual
            )
            expected = seeded.expected
            actual = seeded.actual
            if wasEmpty, let initialArea {
                area = initialArea.rawValue
            } else if FottyFeedbackArea(rawValue: area) == nil {
                area = FottyFeedbackArea.general.rawValue
            }
        }
        .onChange(of: includeDiagnostics) { _, enabled in
            diagnosticText = enabled ? FottyQualityStore.shared.exportJSON() : ""
            notice = nil
        }
        .onChange(of: expected) { _, _ in notice = nil }
        .onChange(of: actual) { _, _ in notice = nil }
        .onChange(of: area) { _, _ in notice = nil }
        .onChange(of: playbackIssueRaw) { _, raw in
            notice = nil
            guard area == FottyFeedbackArea.playback.rawValue,
                  let issue = PlaybackFeedbackIssue(rawValue: raw) else { return }
            let draft = issue.seed(expected: expected, actual: actual)
            expected = draft.expected
            actual = draft.actual
        }
        .confirmationDialog("Clear your unsent feedback draft?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
            Button("Clear draft", role: .destructive) {
                expected = ""
                actual = ""
                playbackIssueRaw = ""
                includeDiagnostics = false
                diagnosticText = ""
                notice = nil
                area = initialArea?.rawValue ?? FottyFeedbackArea.general.rawValue
            }
        }
    }

    private func feedbackSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .bentoSurface()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum FottyFeedbackDelivery {
    // There is no verified direct TestFlight feedback URL for this private
    // group. Keep the supported manual handoff explicit; copying is not sending.
    static let testFlightSteps = "For TestFlight: copy the report, open TestFlight, select Fotty, then choose Send Beta Feedback and paste it."
    static let copiedNotice = "Report copied, not sent. Open TestFlight → Fotty → Send Beta Feedback, then paste your report."
}

struct FottyFeedbackSheet: View {
    let area: FottyFeedbackArea
    var initialExpected: String? = nil
    var initialActual: String? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            FottyFeedbackView(
                initialArea: area,
                initialExpected: initialExpected,
                initialActual: initialActual
            )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .fottyStandardSheetChrome()
    }
}

/// Deliberately hidden from ordinary Settings. The owner can reveal it by
/// tapping the version row seven times; diagnostics never belong on Home.
struct FottyOwnerStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = FottyQualityStore.shared.ownerStatusSnapshot()
    @State private var watchOutcomes = FottyQualityStore.shared.watchOutcomeSummary()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                Text("This is local evidence from this device, not a promise that every fixture or provider is working. Missing evidence means unknown, not healthy.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsSection(title: "Release") {
                    statusRow("Installed", value: "v\(snapshot.appVersion) (\(snapshot.appBuild))")
                    SettingsDivider()
                    statusRow("Current-build events", value: "\(snapshot.currentBuildSummary.recordCount)")
                    SettingsDivider()
                    statusRow("Older-build events excluded", value: "\(snapshot.olderBuildRecordCount)")
                    SettingsDivider()
                    statusRow("Latest current-build evidence", value: formatted(snapshot.lastCurrentBuildRecordAt))
                }

                SettingsSection(title: "Priority match coverage") {
                    let coverage = PriorityBroadcastCoverage.evaluate(events: MatchListViewModel.shared.playbackAdmissionCatalog,
                        snapshot: BroadcastRegistryClient.shared.snapshot,
                        enabled: FixtureStreamDiscoveryIndex.shared.enabledProviderCodes, at: Date())
                    statusRow("Accepted fixtures · next 24h", value: "\(coverage.fixtureCount)")
                    SettingsDivider()
                    statusRow("Fresh source listings", value: "\(coverage.withListings) of \(coverage.fixtureCount)")
                    SettingsDivider()
                    statusRow("Multiple listed source families", value: "\(coverage.withMultipleFamilies)")
                    SettingsDivider()
                    statusRow("Configured TV delivery origins", value: "\(SportsTVStation.configuredOriginCount) across \(SportsTVStation.all.count) stations")
                    ForEach(Array(coverage.missingTitles.enumerated()), id: \.offset) { _, title in
                        SettingsDivider()
                        statusRow(title, value: "No verified listing")
                    }
                }

                SettingsSection(title: "Playback on this build") {
                    statusRow("Attempts", value: "\(snapshot.currentBuildSummary.playbackAttempts)")
                    SettingsDivider()
                    statusRow("Decoded starts", value: "\(snapshot.currentBuildSummary.provenPlaybackStarts)")
                    SettingsDivider()
                    statusRow("Recovered interruptions", value: "\(snapshot.currentBuildSummary.recoveredPlaybackEvents)")
                    SettingsDivider()
                    statusRow("Automatic source changes", value: "\(snapshot.currentBuildSummary.automaticFailovers)")
                    SettingsDivider()
                    statusRow("Resolution failures", value: "\(snapshot.currentBuildSummary.resolutionFailures)")
                    SettingsDivider()
                    statusRow("Terminal failures", value: "\(snapshot.currentBuildSummary.terminalPlaybackFailures)")
                    SettingsDivider()
                    statusRow("Median time to video", value: startupLabel)
                }

                SettingsSection(title: "Watch outcomes on this device") {
                    if watchOutcomes.rows.isEmpty {
                        statusRow("Watch taps", value: "None yet")
                    }
                    ForEach(Array(watchOutcomes.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { SettingsDivider() }
                        statusRow(WatchOutcomeCompetition.displayName(row.competition),
                                  value: WatchOutcomeSummaryText.value(for: row))
                    }
                }
                .accessibilityIdentifier("owner-status-watch-outcomes")

                SettingsSection(title: "Data and FPL on this build") {
                    statusRow("Football refresh failures", value: "\(snapshot.currentBuildSummary.footballDataRefreshFailures)")
                    SettingsDivider()
                    statusRow("Match identity conflicts", value: "\(snapshot.currentBuildSummary.matchIdentityConflicts)")
                    SettingsDivider()
                    statusRow("FPL refresh failures", value: "\(snapshot.currentBuildSummary.fplRefreshFailures)")
                    SettingsDivider()
                    statusRow("Paid Coach attempts recorded", value: "\(snapshot.currentBuildSummary.coachModelRequests)")
                }

                SettingsSection(title: "Apple performance reports") {
                    statusRow("Availability", value: performanceAvailability)
                    if let scroll = snapshot.performance.scroll {
                        SettingsDivider()
                        statusRow("Scroll window", value: performanceLabel(scroll))
                    }
                    if let hangs = snapshot.performance.hangs {
                        SettingsDivider()
                        statusRow("Hang window", value: performanceLabel(hangs))
                        SettingsDivider()
                        statusRow("Recorded hangs", value: "\(hangs.hangCount ?? 0)")
                    }
                }

                NavigationLink {
                    FottyFeedbackView()
                } label: {
                    Label("Prepare a full diagnostic report", systemImage: "doc.text.magnifyingglass")
                        .font(FottyTheme.typeAction)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(FottySecondaryButtonStyle())
                .accessibilityIdentifier("owner-status-report")
            }
            .padding(FottyTheme.spacingMD)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FottyTheme.background.ignoresSafeArea())
        .navigationTitle("Owner Status")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FottyTheme.accentText)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    snapshot = FottyQualityStore.shared.ownerStatusSnapshot()
                    watchOutcomes = FottyQualityStore.shared.watchOutcomeSummary()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh local evidence")
            }
        }
    }

    private var startupLabel: String {
        guard let milliseconds = snapshot.currentBuildSummary.medianStartupMilliseconds else { return "Not available" }
        return String(format: "%.1f s", Double(milliseconds) / 1_000)
    }

    private var performanceAvailability: String {
        snapshot.performance.availability == "available" ? "Received" : "Not available yet"
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "None yet" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func performanceLabel(_ sample: FottyPerformanceSample) -> String {
        let build = sample.reportedBuild.map { "build \($0)" } ?? "build unknown"
        return sample.includesMultipleVersions ? "Multiple builds" : build
    }

    private func statusRow(_ title: String, value: String) -> some View {
        SettingsRow(
            icon: "circle.fill",
            iconColor: FottyTheme.textTertiary,
            title: title,
            value: value,
            showChevron: false
        )
    }
}

/// Read-only text for one competition's private Watch outcomes.
enum WatchOutcomeSummaryText {
    static func value(for row: WatchOutcomeSummary.Row) -> String {
        let taps = row.taps == 1 ? "1 tap" : "\(row.taps) taps"
        let share = "\(Int((row.pictureShare * 100).rounded()))% picture"
        guard let median = row.medianMillisecondsToPicture else { return "\(taps) · \(share)" }
        return "\(taps) · \(share) · \(String(format: "%.1f s", Double(median) / 1_000))"
    }
}
