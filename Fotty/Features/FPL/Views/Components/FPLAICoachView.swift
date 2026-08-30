import SwiftUI

public struct FPLAICoachView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @AppStorage("fotty.fpl.smartCoachConsent") private var smartCoachConsent = false

    private var inputText: String {
        get { viewModel.coachInputDraft }
        nonmutating set { viewModel.coachInputDraft = newValue }
    }
    private var isThinking: Bool { viewModel.isCoachThinking }
    @State private var isShowingHistory = false
    @State private var isShowingClearConfirmation = false
    private var statusMessage: String? {
        get { viewModel.coachStatusMessage }
        nonmutating set { viewModel.coachStatusMessage = newValue }
    }
    @State private var briefing: AIGameweekBriefing?
    @State private var profile = FPLCoachProfile.default
    @FocusState private var isComposerFocused: Bool

    private let prompts = [
        "Audit my whole squad for the next five gameweeks",
        "Should I roll or make a transfer?",
        "Who should I captain and why?",
        "How should I approach my selected rival?"
    ]

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    private var isCompactWidth: Bool { horizontalSizeClass == .compact }

    public var body: some View {
        VStack(spacing: 10) {
            header
            if !smartCoachConsent {
                consentCard
            } else {
                profileBar
            }
            messageStream
            if smartCoachConsent {
                composer
            }
        }
        .sheet(isPresented: $isShowingHistory) {
            FPLCoachHistorySheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Clear Smart Coach Chat?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Messages", role: .destructive) {
                viewModel.clearCoachHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the manager-and-season-scoped conversation stored on this device.")
        }
        .task {
            #if DEBUG
            if viewModel.usesAutomatedTestFixture {
                smartCoachConsent = true
            }
            #endif
            profile = viewModel.coachProfile
            await refreshBriefing()
        }
        .onChange(of: viewModel.picks?.picks) { _, _ in
            Task { await refreshBriefing() }
        }
        .onChange(of: smartCoachConsent) { _, enabled in
            if !enabled { viewModel.cancelCoachRequest() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(FottyTheme.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text("SMART FPL COACH")
                    .font(.headline.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(smartCoachConsent ? "DeepSeek + official FPL recheck" : "Cloud coach is off")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                Text("Advice: \(viewModel.squadSourceTitle). Points: published lineup.")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !viewModel.coachMessages.isEmpty {
                Button {
                    isShowingClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(FottyTheme.error)
                .accessibilityLabel("Clear coach chat")
            }
            Button {
                isShowingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(FottyTheme.accentText)
            .accessibilityLabel("Open coach history")
        }
        .padding(12)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Enable evidence-checked reasoning", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(FottyTheme.textPrimary)

            Text("When you ask a question, Fotty sends the question, up to six shortened recent coach messages, your public FPL manager ID, and a compact squad/plan snapshot to Fotty's Cloudflare Worker. The Worker refreshes public FPL evidence and sends it to DeepSeek. The DeepSeek credential stays on the server, and Fotty never submits team changes.")
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                smartCoachConsent = true
                statusMessage = "Smart Coach enabled. You can turn it off here at any time."
            } label: {
                Label("Enable Smart Coach", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .background(FottyTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var profileBar: some View {
        VStack(spacing: 8) {
            Group {
                if isCompactWidth || dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        profileControls
                    }
                } else {
                    HStack(spacing: 10) {
                        profileControls
                    }
                }
            }
            .onChange(of: profile) { _, newValue in
                viewModel.updateCoachProfile(newValue)
            }

            HStack {
                if let freshness = viewModel.primaryFreshness {
                    Label(
                        "\(freshness.source.rawValue) • \(freshness.shortAgeDescription)",
                        systemImage: freshness.source == .diskSnapshot ? "externaldrive.badge.exclamationmark" : "checkmark.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(freshness.source == .diskSnapshot ? FottyTheme.accentText : FottyTheme.textSecondary)
                }
                Spacer()
                Button("Disable cloud coach") {
                    viewModel.cancelCoachRequest()
                    smartCoachConsent = false
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(FottyTheme.textTertiary)
            }
        }
        .padding(10)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var profileControls: some View {
                Picker("Risk", selection: $profile.riskStyle) {
                    ForEach(FPLCoachProfile.RiskStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .tint(FottyTheme.accentText)

                Stepper("Plan ahead: \(profile.planningHorizon) gameweeks", value: $profile.planningHorizon, in: 1...8)
                    .font(.caption.weight(.bold))

                Toggle("Avoid points hits", isOn: $profile.avoidHits)
                    .font(.caption)
                    .toggleStyle(.switch)
    }

    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.coachMessages.isEmpty {
                        welcomeState
                    } else {
                        ForEach(viewModel.coachMessages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView().tint(FottyTheme.accentText)
                            Text("Refreshing official evidence and checking the full plan…")
                                .font(.subheadline)
                                .foregroundStyle(FottyTheme.textSecondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(FottyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.coachMessages.count) { _, _ in
                if let last = viewModel.coachMessages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 42))
                .foregroundStyle(FottyTheme.accentText)
            Text("Ask for a decision, not just a player name")
                .font(.headline.weight(.bold))
                .foregroundStyle(FottyTheme.textPrimary)
            Text(briefing?.topRecommendation ?? "The coach will check your squad, fixtures, rules, chips, live state and selected rival together.")
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button(prompt) { sendQuery(prompt) }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(FottyTheme.surface)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Ask about the whole decision…", text: $viewModel.coachInputDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .padding(11)
                    .background(FottyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit { sendCurrentInput() }
                Button(action: sendCurrentInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(canSend ? FottyTheme.accentText : FottyTheme.textTertiary)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send question")
            }
        }
        .padding(.bottom, isCompactWidth ? 6 : 10)
    }

    private var canSend: Bool {
        !isThinking && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func messageBubble(_ message: AICoachMessage) -> some View {
        let isUser = message.sender == .user
        HStack {
            if isUser { Spacer(minLength: 42) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if let card = message.coachCard, !isUser {
                    coachResponseCard(card)
                } else {
                    Text(LocalizedStringKey(message.text))
                        .font(.subheadline)
                        .foregroundStyle(isUser ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(isUser ? FottyTheme.accent : FottyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                HStack(spacing: 5) {
                    if let tag = message.tag {
                        Text(tag)
                            .font(.caption2.weight(.bold))
                    }
                    if let gameweek = message.gameweek {
                        Text("GW\(gameweek)").font(.caption2)
                    }
                }
                .foregroundStyle(FottyTheme.textTertiary)
            }
            if !isUser { Spacer(minLength: 24) }
        }
    }

    private func coachResponseCard(_ card: FPLCoachCardPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECOMMENDATION")
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.accentText)
                    Text(LocalizedStringKey(card.answer))
                        .font(FottyTheme.typeBody)
                        .foregroundStyle(FottyTheme.textPrimary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Text(card.confidence.capitalized)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
                    .accessibilityLabel("\(card.confidence.capitalized) confidence")
            }

            coachCardSection(
                title: "Evidence checked",
                symbol: "checkmark.shield.fill",
                items: card.evidence,
                color: FottyTheme.success
            )
            coachCardSection(
                title: "Downside and limits",
                symbol: "exclamationmark.triangle.fill",
                items: card.downside,
                color: FottyTheme.accentText
            )
            coachCardSection(
                title: "Verify before deadline",
                symbol: "checklist",
                items: card.verifyBeforeDeadline,
                color: FottyTheme.accentText
            )

            HStack(spacing: 6) {
                Text(card.source)
                Text("•")
                Text(card.officialDataStatus)
                if let verifiedAt = card.verifiedAt {
                    Text("•")
                    Text(verifiedAt, style: .relative)
                }
                if let usage = card.usage {
                    Text("•")
                    Text("\(usage.totalTokens) tokens")
                }
            }
            .font(FottyTheme.typeCaption)
            .foregroundStyle(FottyTheme.textTertiary)

            Button {
                viewModel.recordCoachDecision(card)
                statusMessage = "Recommendation saved to the Decision Journal."
            } label: {
                Label("Save to Decision Journal", systemImage: "bookmark.fill")
                    .font(FottyTheme.typeAction)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(FottyTheme.accentText)
            .accessibilityHint("Keeps this recommendation on this device for post-gameweek review")
        }
        .padding(14)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous)
                .strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fpl-coach-response")
    }

    @ViewBuilder
    private func coachCardSection(title: String, symbol: String, items: [String], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(color)
                ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func sendCurrentInput() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isThinking else { return }
        inputText = ""
        isComposerFocused = false
        sendQuery(query)
    }

    private func sendQuery(_ query: String) {
        guard smartCoachConsent, !isThinking else { return }
        isComposerFocused = false
        viewModel.sendCoachQuestion(query)
    }

    private func refreshBriefing() async {
        briefing = await FPLAICoachService.generateBriefing(
            managerName: viewModel.managerSummary?.name,
            currentGw: viewModel.currentGameweek,
            picks: viewModel.picks,
            scores: viewModel.playerScores,
            recs: viewModel.transferRecs,
            captains: viewModel.captainRecs,
            rivalGap: viewModel.rivalGapAnalysis
        )
    }
}

public struct FPLCoachHistorySheet: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var messages: [AICoachMessage] {
        let source = searchText.isEmpty
            ? viewModel.coachMessages
            : viewModel.coachMessages.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        return Array(source.reversed())
    }

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List(messages) { message in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(message.sender == .coach ? (message.tag ?? "Coach") : "You")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(message.sender == .coach ? FottyTheme.accentText : FottyTheme.textSecondary)
                        Spacer()
                        Text(message.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                    Text(LocalizedStringKey(message.coachCard?.answer ?? message.text))
                        .font(.subheadline)
                        .textSelection(.enabled)
                    if let card = message.coachCard {
                        Text("\(card.confidence.capitalized) confidence • \(card.source) • \(card.officialDataStatus)\(card.usage.map { " • \($0.totalTokens) tokens" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(FottyTheme.textTertiary)
                    }
                }
                .padding(.vertical, 5)
                .listRowBackground(FottyTheme.surface)
            }
            .searchable(text: $searchText, prompt: "Search coach history")
            .scrollContentBackground(.hidden)
            .background(FottyTheme.background)
            .navigationTitle("Coach History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
