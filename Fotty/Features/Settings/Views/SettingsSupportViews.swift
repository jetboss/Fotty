import SwiftUI
import UIKit

enum FottyHelpContent {
    static let matchAlerts = "Match alerts are in-app updates for followed Premier League teams while Home or Matchday is open and refreshing. They are not background push alerts and won't reliably arrive while Fotty is closed or your device is locked."
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

struct FottyFeedbackReport {
    let area: String
    let expected: String
    let actual: String
    let version: String
    let device: String
    let system: String
    let date: Date
    var diagnostics: String? = nil

    var text: String {
        var sections = [
            "Fotty beta feedback",
            "Area: \(area)",
            "App: \(version)\nDevice: \(device)\nSystem: \(system)\nReport created: \(ISO8601DateFormatter().string(from: date))",
            "What I was doing / expected:\n\(expected.trimmingCharacters(in: .whitespacesAndNewlines))",
            "What happened instead:\n\(actual.trimmingCharacters(in: .whitespacesAndNewlines))"
        ]
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
                help("Your first matchday", "Home is the full catalog. Long-press a match or channel and choose Save to My Matchday, or follow a team, to build your personal list. Use the same menu to remove a saved match. Saving alone does not enable reminders. Fantasy planning stays in the FPL tab.")
                help("Watching and recovery", FottyHelpContent.playback)
                help("Score coverage", FottyHelpContent.scores)
                help("FPL points", FottyHelpContent.fplPoints)
                help("Plans aren't submitted transfers", FottyHelpContent.fplDrafts)
                help("Match alerts", FottyHelpContent.matchAlerts)
                help("Match start reminders", FottyHelpContent.matchReminders)
                help("Deadline reminders", FottyHelpContent.deadlineAlerts)
                help("Your data", "Preferences, saved matches and FPL drafts are stored on this device, not synced between devices. Smart Coach asks for consent before sending a question and minimized context to its online service.")
                NavigationLink {
                    FottyFeedbackView()
                } label: {
                    Label("Report a problem", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                        .frame(minHeight: 44)
                }
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
            Text(detail).font(.body).foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FottyFeedbackView: View {
    var initialArea: FottyFeedbackArea? = nil
    @AppStorage("fotty.feedback.area") private var area = FottyFeedbackArea.general.rawValue
    @AppStorage("fotty.feedback.expected") private var expected = ""
    @AppStorage("fotty.feedback.actual") private var actual = ""
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
            diagnostics: includeDiagnostics ? diagnosticText : nil
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
                Text("Include the match, approximate time or source number if useful. Don't include passwords, private stream links or anything you don't want to share.")
                    .font(.footnote)
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            feedbackSection("Review") {
                Toggle("Include on-device diagnostics", isOn: $includeDiagnostics)
                    .accessibilityIdentifier("feedback-diagnostics")
                Text("Optional: bounded playback/data outcomes and token counts. No manager IDs, match names, stream URLs, credentials or Coach messages are collected by these diagnostics.")
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

            feedbackSection("Send through TestFlight or share") {
                if !canShare {
                    Label("Complete both required fields to copy or share your report.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Button("Copy report for TestFlight") {
                    focusedField = nil
                    UIPasteboard.general.string = reportText
                    notice = "Report copied, not sent. Paste it into Fotty's Send Beta Feedback screen in TestFlight."
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
                Text(FottyHelpContent.testFlight)
                    .font(.callout)
                Text("Not using TestFlight? Share the report with the person who invited you. Copying or opening the share sheet does not confirm delivery.")
                    .font(.footnote)
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
            if expected.isEmpty && actual.isEmpty, let initialArea {
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
        .confirmationDialog("Clear your unsent feedback draft?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
            Button("Clear draft", role: .destructive) {
                expected = ""
                actual = ""
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

struct FottyFeedbackSheet: View {
    let area: FottyFeedbackArea
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            FottyFeedbackView(initialArea: area)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .fottyStandardSheetChrome()
    }
}
