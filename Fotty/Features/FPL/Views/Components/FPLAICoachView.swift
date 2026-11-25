import SwiftUI

public struct FPLAICoachView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    private var promptsScrollWithConversation: Bool {
        dynamicTypeSize.isAccessibilitySize || isComposerFocused
    }

    public var body: some View {
        VStack(spacing: 10) {
            messageStream
            composer
                .layoutPriority(1)
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
                Text("Smart Coach")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(smartCoachConsent ? "Advice uses current FPL evidence" : "On-device help available • Cloud Coach off")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
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
                .buttonStyle(FottyPressButtonStyle())
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
            .buttonStyle(FottyPressButtonStyle())
            .foregroundStyle(FottyTheme.accentText)
            .accessibilityLabel("Open coach history")
        }
        .padding(12)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Enable cloud strategy advice", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(FottyTheme.textPrimary)

            Text("Cloud Coach sends your question, recent chat context, public manager ID and a compact squad snapshot to Fotty's service for DeepSeek processing. It never submits team changes.")
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
            .buttonStyle(FottyPressButtonStyle(cornerRadius: 10))
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
                        "\(freshness.source.displayName) • \(freshness.shortAgeDescription)",
                        systemImage: freshness.source == .diskSnapshot ? "externaldrive.badge.exclamationmark" : "checkmark.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(freshness.source == .diskSnapshot ? FottyTheme.accentText : FottyTheme.textSecondary)
                }
                Spacer()
                Button {
                    viewModel.cancelCoachRequest()
                    smartCoachConsent = false
                } label: {
                    Text("Disable cloud coach")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(FottyTheme.textTertiary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle())
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
                    header
                    if smartCoachConsent {
                        profileBar
                    } else {
                        consentCard
                    }
                    if promptsScrollWithConversation {
                        promptSuggestions
                    }
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
                            Text("Checking FPL data…")
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
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last, anchor: .bottom) }
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
            Text(briefing?.topRecommendation ?? "Ask about points, transfers, captaincy or your full squad.")
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
    }

    private var promptSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button { sendQuery(prompt) } label: {
                        Text(prompt)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minHeight: 44)
                            .background(FottyTheme.surface)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusXL))
                    .disabled(isThinking)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !promptsScrollWithConversation { promptSuggestions }
            HStack(spacing: 10) {
                TextField("Ask about the whole decision…", text: $viewModel.coachInputDraft, axis: .vertical)
                    .lineLimit(1...(dynamicTypeSize.isAccessibilitySize ? 2 : 4))
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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusXL))
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
                    coachResponseCard(card, recheckQuery: FPLCoachRecheck.question(for: message, in: viewModel.coachMessages))
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

    private func coachResponseCard(_ card: FPLCoachCardPayload, recheckQuery: String?) -> some View {
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
                Text(card.confidenceLabel)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
                    .accessibilityLabel(card.confidenceLabel)
            }

            coachCardSection(
                title: card.evidenceHeading,
                symbol: "doc.text.magnifyingglass",
                items: card.evidence,
                color: FottyTheme.success
            )
            coachCardSection(
                title: "Downside and limits",
                symbol: "exclamationmark.triangle.fill",
                items: card.downside,
                color: FottyTheme.accentText
            )

            Text(card.assuranceNote)
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            coachCardSection(
                title: "Verify before deadline",
                symbol: "checklist",
                items: card.verifyBeforeDeadline,
                color: FottyTheme.accentText
            )

            Text(evidenceSummary(for: card))
            .font(FottyTheme.typeCaption)
            .foregroundStyle(FottyTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

            if let recheckQuery {
                Button {
                    sendQuery(recheckQuery)
                } label: {
                    Label("Recheck with current evidence", systemImage: "arrow.clockwise")
                        .font(FottyTheme.typeAction)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isThinking)
                .accessibilityHint("Creates a new dated answer. The earlier answer remains historical.")
            }

            Button {
                if viewModel.recordCoachDecision(card) {
                    statusMessage = "Recommendation saved for GW\(viewModel.planningGameweek). Its original evidence date is retained."
                } else {
                    statusMessage = viewModel.coachStatusMessage ?? viewModel.draftErrorMessage ?? "Recommendation could not be saved. Refresh your team and try again."
                }
            } label: {
                Label("Save decision for GW\(viewModel.planningGameweek)", systemImage: "bookmark.fill")
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

    private func evidenceSummary(for card: FPLCoachCardPayload) -> String {
        var details = [card.source, card.officialDataStatus]
        if let verifiedAt = card.verifiedAt {
            details.append("Evidence fetched \(verifiedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let usage = card.usage { details.append("\(usage.totalTokens) tokens") }
        return details.joined(separator: " • ")
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
        guard !isThinking else { return }
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
                        Text("Historical answer • \(card.confidenceLabel) • \(card.source) • \(card.officialDataStatus)\(card.usage.map { " • \($0.totalTokens) tokens" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(FottyTheme.textTertiary)
                        if let query = FPLCoachRecheck.question(for: message, in: viewModel.coachMessages) {
                            Button("Recheck with current evidence") {
                                viewModel.sendCoachQuestion(query)
                                dismiss()
                            }
                            .disabled(viewModel.isCoachThinking)
                        }
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
