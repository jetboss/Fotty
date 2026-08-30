import SwiftUI

struct InsightsHubView: View {
    @StateObject var viewModel = InsightsViewModel()
    @State private var selectedMatch: FootballMatch?
    @AppStorage("fotty.insights.aiConsentAccepted") private var aiConsentAccepted = false
    @State private var showAIConsent = false

    @Environment(LiveScoreService.self) private var liveScoreService
    @EnvironmentObject private var socialCloudStore: SocialCloudStore

    private var aiConsentRequired: Bool {
        AppCapabilities.aiInsightsConsentRequired
    }

    private var canLoadInsights: Bool {
        !aiConsentRequired || aiConsentAccepted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .pitchBackground()
                    .ignoresSafeArea()

                if !canLoadInsights {
                    aiConsentRequiredView
                } else if viewModel.isLoading && viewModel.liveMatches.isEmpty {
                    FootballLoadingView(size: 50)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if liveScoreService.shouldShowScoreFeedNotice {
                                FootballQuotaBanner()
                            }
                            ForEach(viewModel.liveMatches) { match in
                                InsightMatchRow(match: match)
                                    .onTapGesture {
                                        selectedMatch = match
                                    }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        guard canLoadInsights else { return }
                        viewModel.refresh(using: liveScoreService, force: true)
                    }
                }
            }
            .navigationTitle("Match Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        guard canLoadInsights else {
                            showAIConsent = true
                            return
                        }
                        viewModel.refresh(using: liveScoreService, force: false)
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedMatch) { match in
                NavigationStack {
                    MatchHubView(fixtureId: match.hubNavigationFixtureId, showModalDismissButton: true)
                        .environment(liveScoreService)
                        .environmentObject(socialCloudStore)
                }
                .fottyStandardSheetChrome()
            }
            .sheet(isPresented: $showAIConsent) {
                AIDataConsentView(
                    onAccept: {
                        aiConsentAccepted = true
                        showAIConsent = false
                        viewModel.refresh(using: liveScoreService, force: false)
                    },
                    onDecline: {
                        showAIConsent = false
                    }
                )
                .interactiveDismissDisabled(aiConsentRequired && !aiConsentAccepted)
                .fottyStandardSheetChrome()
            }
            .onAppear {
                if aiConsentRequired && !aiConsentAccepted {
                    showAIConsent = true
                    return
                }
                viewModel.refresh(using: liveScoreService, force: false)
            }
        }
    }

    private var aiConsentRequiredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.blue)
            Text("AI Data Consent Required")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FottyTheme.textPrimary)
            Text("Insights processing uses external AI. Review and accept consent before loading match insights.")
                .font(.system(size: 13))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Review Consent") {
                showAIConsent = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.horizontal, 20)
    }
}

private struct AIDataConsentView: View {
    @Environment(\.dismiss) private var dismiss
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Insights Consent")
                    .font(.system(size: 24, weight: .bold))

                Text("When enabled, match insights may be processed by external AI services to generate summaries or tactical observations.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("By tapping Continue, you consent to sending relevant match and usage data for AI processing.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 10) {
                    Button("Continue") {
                        onAccept()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Not Now") {
                        onDecline()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .navigationTitle("Consent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct InsightMatchRow: View {
    let match: FootballMatch

    var body: some View {
        HStack {
            TeamIcon(url: match.homeTeam.crest, name: match.homeTeam.displayName)

            Spacer()

            VStack {
                Text("\(match.score.fullTime?.home ?? 0) - \(match.score.fullTime?.away ?? 0)")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(FottyTheme.accentText)
                Text(match.status.displayText)
                    .font(.caption2)
                    .foregroundColor(FottyTheme.textSecondary)
            }

            Spacer()

            TeamIcon(url: match.awayTeam.crest, name: match.awayTeam.displayName)
        }
        .padding()
        .background(FottyTheme.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(FottyTheme.border, lineWidth: 0.5)
        )
    }
}

struct TeamIcon: View {
    let url: String?
    let name: String

    var body: some View {
        VStack {
            if let urlString = url, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
            }
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(FottyTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 80)
    }
}
