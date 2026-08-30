import SwiftUI
import SwiftData

/// A personal matchday shortlist. Home discovers the full catalog; this screen
/// contains only matches the user saved or that involve a followed team.
struct ArenaDiscoveryView: View {
    let onBrowseHome: () -> Void

    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FollowedTeamItem.createdAt, order: .forward) private var followedTeams: [FollowedTeamItem]

    @State private var matchListViewModel = MatchListViewModel.shared
    @State private var myMatchdayStore = MyMatchdayStore.shared
    @State private var selectedCatalogEvent: AnalyticalDataEngine.EventReference?
    @State private var showsTeams = false
    @State private var navigation = MatchNavigationStore.shared
    @State private var remindedEventID: String?
    @State private var reminderStore = MatchReminderStore.shared

    @State private var showPlayer = false
    @State private var streamEvent: AnalyticalDataEngine.EventReference?
    @State private var streamSessions: [StreamSession] = []
    @State private var isFindingStream = false
    @State private var streamStatusMessage = "Looking for a playable stream..."
    @State private var streamTechnicalSummary: String?
    @State private var streamError: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var streamRequestID = UUID()

    init(onBrowseHome: @escaping () -> Void) {
        self.onBrowseHome = onBrowseHome
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()

                ScrollViewReader { proxy in
                 ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                        matchdayHeader
                            .id("matchday-top")

                        if let remindedEventID {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Your match reminder", systemImage: "bell.fill")
                                        .font(FottyTheme.typeAction)
                                        .foregroundStyle(FottyTheme.accentText)
                                    Spacer()
                                    Button("Dismiss") { self.remindedEventID = nil }
                                        .frame(minHeight: 44)
                                }
                                if let event = personalEvents.first(where: { $0.id == remindedEventID }) {
                                    personalMatchRow(event)
                                } else {
                                    Text("This match is no longer saved. Browse Home for the latest schedule.")
                                        .font(FottyTheme.typeMeta)
                                        .foregroundStyle(FottyTheme.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("matchday-reminder-target")
                        }

                        if let conflict = kickoffConflicts.first {
                            conflictBanner(conflict, additionalCount: max(kickoffConflicts.count - 1, 0))
                        }

                        matchdayContent

                        if !reminderStore.records.isEmpty {
                            Text("Reminders are opt-in, five minutes before the scheduled start. They can arrive with Fotty closed; schedule changes are checked when Fotty refreshes. Notification settings may silence or delay alerts.")
                                .font(FottyTheme.typeCaption)
                                .foregroundStyle(FottyTheme.textSecondary)
                        }

                        Spacer(minLength: 80)
                    }
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, FottyTheme.bentoInset)
                    .padding(.top, FottyTheme.spacingMD)
                }
                .refreshable {
                    await refreshMatchday()
                }
                .onChange(of: remindedEventID) { _, id in
                    if id != nil { proxy.scrollTo("matchday-top", anchor: .top) }
                }
                }

                if isFindingStream {
                    StreamResolutionOverlay(
                        statusMessage: streamStatusMessage,
                        subtitle: streamEvent.map(eventTitle(_:)),
                        technicalSummary: streamTechnicalSummary,
                        isMultiStream: false,
                        multiTitles: [],
                        onCancel: cancelStreamResolution
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Stream Not Available", isPresented: .init(
            get: { streamError != nil },
            set: { if !$0 { streamError = nil } }
        )) {
            Button("OK") { streamError = nil }
        } message: {
            Text(streamError ?? "")
        }
        .fullScreenCover(isPresented: $showsTeams) { TeamOnboardingView() }
        .sheet(item: $selectedCatalogEvent) { event in
            CatalogEventDetailsView(event: event)
                .environment(liveScoreService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: resetPlayerPresentation) {
            if let streamEvent {
                LivePlayerView(event: streamEvent, providedSessions: streamSessions)
                    .environment(liveScoreService)
            } else {
                FottyTheme.background.ignoresSafeArea()
            }
        }
        .task {
            matchListViewModel.configure(modelContext: modelContext)
            myMatchdayStore.pruneExpiredMatches()
            guard !AppRuntime.isAutomatedTesting else { return }

            liveScoreService.startPolling()
            await matchListViewModel.refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(90))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await matchListViewModel.refresh()
            }
        }
        .onDisappear {
            liveScoreService.stopPolling()
            cancelStreamResolution()
        }
        .onChange(of: navigation.pendingReminderID, initial: true) { _, id in
            guard let id else { return }
            remindedEventID = id
            navigation.pendingReminderID = nil
        }
    }

    private var matchdayHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("My Matchday")
                    .font(FottyTheme.typeScreenTitle)
                    .foregroundStyle(FottyTheme.textPrimary)

                Text("Your saved broadcasts and followed teams")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
            }

            HStack(spacing: 8) {
                summaryChip(
                    value: myMatchdayStore.savedMatches.count,
                    label: "Saved",
                    systemImage: "bookmark.fill"
                )
                summaryChip(
                    value: followedTeams.count,
                    label: "Following",
                    systemImage: "star.fill"
                )
                if !liveEvents.isEmpty {
                    summaryChip(
                        value: liveEvents.count,
                        label: "Live",
                        systemImage: "dot.radiowaves.left.and.right",
                        highlighted: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryChip(
        value: Int,
        label: String,
        systemImage: String,
        highlighted: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.fottyScaled(size: 10, weight: .bold))
            Text("\(value) \(label)")
                .font(FottyTheme.typeCaption)
                .fontWeight(.bold)
                .lineLimit(1)
        }
        .foregroundStyle(highlighted ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(highlighted ? FottyTheme.accent : FottyTheme.surface)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var matchdayContent: some View {
        if personalEvents.isEmpty {
            matchdayEmptyState
        } else {
            LazyVStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                matchdaySection(
                    title: "Live now",
                    subtitle: "Available from your shortlist",
                    events: liveEvents
                )
                matchdaySection(
                    title: "Next up",
                    subtitle: "Starting within six hours",
                    events: nextUpEvents
                )
                ForEach(laterDates, id: \.self) { day in
                    matchdaySection(
                        title: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        subtitle: "Later in your plan",
                        events: laterEvents.filter { $0.kickoffDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
                    )
                }
                matchdaySection(title: "Saved channels", subtitle: "Open a channel to see what is showing", events: personalEvents.filter(\.isBroadcastChannel))
                matchdaySection(title: "Time to be confirmed", subtitle: "Saved fixtures without a kickoff time", events: laterEvents.filter { $0.kickoffDate == nil && !$0.isBroadcastChannel })
                matchdaySection(
                    title: "Recent",
                    subtitle: "Kept briefly for matchday continuity",
                    events: recentEvents
                )
            }
        }
    }

    @ViewBuilder
    private func matchdaySection(
        title: String,
        subtitle: String,
        events: [AnalyticalDataEngine.EventReference]
    ) -> some View {
        let visibleEvents = events.filter { $0.id != remindedEventID }
        if !visibleEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                FottySectionHeader(title: title, count: visibleEvents.allSatisfy(\.isBroadcastChannel) ? nil : visibleEvents.count, subtitle: subtitle)

                ForEach(visibleEvents) { event in
                    personalMatchRow(event)
                }
            }
        }
    }

    private func personalMatchRow(_ event: AnalyticalDataEngine.EventReference) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(personalReason(for: event), systemImage: personalReasonIcon(for: event))
                .font(FottyTheme.typeCaption)
                .fontWeight(.bold)
                .foregroundStyle(FottyTheme.textTertiary)
                .padding(.horizontal, 4)

            LiveEventCard(
                event: event,
                onWatchTap: isPlaybackCandidate(event) ? { watchEvent(event) } : nil,
                onDetailsTap: { selectedCatalogEvent = event },
                isSaved: myMatchdayStore.contains(eventID: event.id),
                onSaveTap: { toggleSavedMatch(event) }
            )
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
            .accessibilityHint(
                isPlaybackCandidate(event)
                    ? "Opens the available broadcast"
                    : "Opens match information"
            )
        }
    }

    private var matchdayEmptyState: some View {
        let hasPreferences = !followedTeams.isEmpty
            || !myMatchdayStore.savedMatches.isEmpty
        return VStack(spacing: 8) {
          EmptyStateView(
            icon: hasPreferences ? "calendar.badge.clock" : "bookmark",
            title: hasPreferences ? "Nothing on your matchday yet" : "Build your matchday",
            message: hasPreferences
                ? "Your saved matches and followed teams do not have a current fixture in the live catalog. Pull to refresh or discover another match."
                : "Save a match or channel from Home, or follow a team. Your choices appear here without repeating the full schedule.",
            actionTitle: "Browse Home",
            action: onBrowseHome
          )
          if followedTeams.isEmpty {
              Button("Follow a team") { showsTeams = true }
                  .frame(minHeight: 44)
                  .accessibilityIdentifier("matchday-follow")
          }
        }
        .tint(FottyTheme.accentText)
        .frame(maxWidth: .infinity)
    }

    private func conflictBanner(_ conflict: MatchdayConflict, additionalCount: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.fottyScaled(size: 16, weight: .bold))
                .foregroundStyle(FottyTheme.accentText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Kickoff clash")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.textPrimary)

                Text(conflictMessage(conflict, additionalCount: additionalCount))
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(FottyTheme.spacingMD)
        .bentoSurface(cornerRadius: FottyTheme.radiusMD)
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        }
    }

    // MARK: - Personal catalog

    private var followedTeamKeys: Set<String> {
        Set(followedTeams.map(\.key))
    }

    private var savedEventIDs: Set<String> {
        Set(myMatchdayStore.savedMatches.map(\.id))
    }

    private var personalEvents: [AnalyticalDataEngine.EventReference] {
        let savedRecords = Dictionary(
            uniqueKeysWithValues: myMatchdayStore.savedMatches.map { ($0.id, $0) }
        )
        var byID: [String: AnalyticalDataEngine.EventReference] = [:]

        for event in matchListViewModel.matches where isEventPersonal(event) {
            if (event.sources?.isEmpty ?? true), !event.id.hasPrefix("cpl-2026-"), let saved = savedRecords[event.id] {
                byID[event.id] = saved.event
            } else {
                byID[event.id] = event
            }
        }

        for record in myMatchdayStore.savedMatches where byID[record.id] == nil {
            byID[record.id] = record.event
        }

        return byID.values.sorted(by: matchSort)
    }

    private var liveEvents: [AnalyticalDataEngine.EventReference] {
        personalEvents.filter {
            HomeMatchPriority.isLive($0, scoreService: liveScoreService)
                && !HomeMatchPriority.isFinished($0, scoreService: liveScoreService)
        }
    }

    private var nextUpEvents: [AnalyticalDataEngine.EventReference] {
        let cutoff = Date().addingTimeInterval(6 * 3600)
        return upcomingEvents.filter { event in
            guard let kickoff = event.kickoffDate else { return false }
            return kickoff <= cutoff
        }
    }

    private var laterEvents: [AnalyticalDataEngine.EventReference] {
        let nextIDs = Set(nextUpEvents.map(\.id))
        return upcomingEvents.filter { !nextIDs.contains($0.id) }
    }

    private var upcomingEvents: [AnalyticalDataEngine.EventReference] {
        let liveIDs = Set(liveEvents.map(\.id))
        let recentIDs = Set(recentEvents.map(\.id))
        return personalEvents.filter {
            !$0.isBroadcastChannel && !liveIDs.contains($0.id) && !recentIDs.contains($0.id)
        }
    }

    private var recentEvents: [AnalyticalDataEngine.EventReference] {
        return personalEvents.filter { event in
            HomeMatchPriority.isFinished(event, scoreService: liveScoreService)
        }
        .sorted { ($0.kickoffDate ?? .distantPast) > ($1.kickoffDate ?? .distantPast) }
    }

    private func isEventPersonal(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        savedEventIDs.contains(event.id) || isEventFollowed(event)
    }

    private func isEventFollowed(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        followedTeamKeys.contains(TeamFollowKey.make(name: event.homeName, category: event.normalizedCategory))
            || followedTeamKeys.contains(TeamFollowKey.make(name: event.awayName, category: event.normalizedCategory))
    }

    private func personalReason(for event: AnalyticalDataEngine.EventReference) -> String {
        let saved = savedEventIDs.contains(event.id)
        let followed = isEventFollowed(event)
        if saved && followed { return "Saved · Followed team" }
        if saved { return event.isBroadcastChannel ? "Saved channel" : "Saved match" }
        return "Followed team"
    }

    private func personalReasonIcon(for event: AnalyticalDataEngine.EventReference) -> String {
        return savedEventIDs.contains(event.id) ? "bookmark.fill" : "star.fill"
    }

    private func matchSort(
        _ lhs: AnalyticalDataEngine.EventReference,
        _ rhs: AnalyticalDataEngine.EventReference
    ) -> Bool {
        let lhsLive = HomeMatchPriority.isLive(lhs, scoreService: liveScoreService)
        let rhsLive = HomeMatchPriority.isLive(rhs, scoreService: liveScoreService)
        if lhsLive != rhsLive { return lhsLive }
        return (lhs.kickoffDate ?? .distantFuture) < (rhs.kickoffDate ?? .distantFuture)
    }

    // MARK: - Clash detection

    private var kickoffConflicts: [MatchdayConflict] {
        let now = Date().addingTimeInterval(-15 * 60)
        let candidates = personalEvents
            .filter { !HomeMatchPriority.isFinished($0, scoreService: liveScoreService) }
            .filter { ($0.kickoffDate ?? .distantPast) >= now }
            .sorted { ($0.kickoffDate ?? .distantFuture) < ($1.kickoffDate ?? .distantFuture) }

        var conflicts: [MatchdayConflict] = []
        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                guard let firstKickoff = candidates[firstIndex].kickoffDate,
                      let secondKickoff = candidates[secondIndex].kickoffDate else { continue }
                let gap = secondKickoff.timeIntervalSince(firstKickoff)
                guard let duration = candidates[firstIndex].estimatedMatchDuration else { continue }
                if gap >= duration { break }
                conflicts.append(
                    MatchdayConflict(
                        first: candidates[firstIndex],
                        second: candidates[secondIndex],
                        minutesApart: max(Int(gap / 60), 0)
                    )
                )
            }
        }
        return conflicts
    }

    private func conflictMessage(_ conflict: MatchdayConflict, additionalCount: Int) -> String {
        let timing: String
        if conflict.minutesApart == 0, let date = conflict.first.kickoffDate {
            timing = "both start \(date.formatted(date: .abbreviated, time: .shortened))"
        } else {
            timing = "start \(conflict.minutesApart) minutes apart"
        }
        let base = "\(eventTitle(conflict.first)) and \(eventTitle(conflict.second)) \(timing)."
        guard additionalCount > 0 else { return base + " You may need to choose which one to watch live." }
        return base + " \(additionalCount) more clash\(additionalCount == 1 ? "" : "es") detected."
    }

    // MARK: - Actions and playback

    private var laterDates: [Date] {
        Set(laterEvents.compactMap { $0.kickoffDate.map { Calendar.current.startOfDay(for: $0) } }).sorted()
    }

    private func refreshMatchday() async {
        async let catalogRefresh: Void = matchListViewModel.refresh()
        async let scoreRefresh: Void = liveScoreService.refresh(force: true)
        _ = await (catalogRefresh, scoreRefresh)
    }

    private func toggleSavedMatch(_ event: AnalyticalDataEngine.EventReference) {
        HapticManager.impact(.light)
        withAnimation(FottyTheme.springSnappy) {
            myMatchdayStore.toggle(event)
        }
    }

    private func openEvent(_ event: AnalyticalDataEngine.EventReference) {
        guard playbackTimingAllows(event) else { return }
        guard event.kickoffDate.map({ $0 <= Date() }) ?? true || isPlaybackCandidate(event) else { return }
        if isPlaybackCandidate(event) {
            watchEvent(event)
        } else {
            selectedCatalogEvent = event
        }
    }

    private func isPlaybackCandidate(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        event.sources?.contains { source in
            StreamPluginProviderMatching.isActiveCatalogSource(source)
        } == true
    }

    private func watchEvent(_ event: AnalyticalDataEngine.EventReference) {
        guard playbackTimingAllows(event) else { return }
        MatchPlaybackFeedback.shared.attempting(event.id)
        streamTask?.cancel()
        let requestID = UUID()
        streamRequestID = requestID
        isFindingStream = true
        streamEvent = event
        streamSessions = []
        streamError = nil
        streamStatusMessage = "Looking for a playable stream..."
        streamTechnicalSummary = nil

        streamTask = Task {
            let matchedEvent = await LiveStreamResolver.shared.catalogEvent(
                for: StreamPlaybackRequest(event: event)
            ) ?? event
            guard !Task.isCancelled, streamRequestID == requestID else { return }
            guard playbackTimingAllows(matchedEvent) else {
                isFindingStream = false
                MatchPlaybackFeedback.shared.notReady(event.id)
                return
            }
            let request = StreamPlaybackRequest(event: matchedEvent)

            await MainActor.run {
                guard streamRequestID == requestID else { return }
                streamEvent = matchedEvent
            }

            let outcome = await LiveStreamResolver.shared.resolvePlayback(for: request) { progress in
                await MainActor.run {
                    guard streamRequestID == requestID else { return }
                    streamStatusMessage = progress.userMessage
                    streamTechnicalSummary = progress.technicalMessage
                }
            }

            guard !Task.isCancelled, streamRequestID == requestID else {
                await LiveStreamResolver.shared.cancelAttempt(for: request)
                return
            }

            await MainActor.run {
                isFindingStream = false
                streamTechnicalSummary = nil
                switch outcome {
                case .success(let success):
                    let supportedSessions = success.sessions.filter(
                        StreamPluginProviderMatching.isActivePlayerSession
                    )
                    if supportedSessions.isEmpty {
                        MatchPlaybackFeedback.shared.notReady(event.id)
                    } else {
                        streamSessions = supportedSessions
                        showPlayer = true
                    }
                case .failure:
                    MatchPlaybackFeedback.shared.notReady(event.id)
                }
            }
        }
    }

    private func cancelStreamResolution() {
        streamTask?.cancel()
        let pendingEvent = streamEvent
        streamRequestID = UUID()
        isFindingStream = false
        streamStatusMessage = "Looking for a playable stream..."
        streamTechnicalSummary = nil
        if !showPlayer {
            streamEvent = nil
            streamSessions = []
        }
        if let pendingEvent {
            Task {
                await LiveStreamResolver.shared.cancelAttempt(
                    for: StreamPlaybackRequest(event: pendingEvent)
                )
            }
        }
    }

    private func playbackTimingAllows(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        MatchStartPolicy(event: event,
            status: MatchStartPolicy.currentStatus(for: event, scores: liveScoreService)).timingAllowsPlayback
    }

    private func resetPlayerPresentation() {
        streamEvent = nil
        streamSessions = []
        showPlayer = false
    }

    private func eventTitle(_ event: AnalyticalDataEngine.EventReference) -> String {
        event.displayTitle
    }
}

private struct MatchdayConflict: Identifiable {
    let first: AnalyticalDataEngine.EventReference
    let second: AnalyticalDataEngine.EventReference
    let minutesApart: Int

    var id: String { "\(first.id)|\(second.id)" }
}
