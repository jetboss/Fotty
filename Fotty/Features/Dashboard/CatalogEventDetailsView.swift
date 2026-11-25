import SwiftUI

@MainActor
struct CatalogEventDetailsPresentation: Equatable {
    let title: String
    let message: String
    let symbol: String

    static func broadcast(for event: AnalyticalDataEngine.EventReference, now: Date = Date(),
                          status: FootballMatch.MatchStatus? = nil,
                          canWatchHere: Bool = false, isChannelFallback: Bool = false,
                          enabledProviderCodes: Set<String>? = nil,
                          discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
                          catalogIndex: FixtureCatalogAvailabilityIndex? = nil) -> Self {
        let policy = MatchStartPolicy(event: event, now: now, status: status, discoveryIndex: discoveryIndex)
        if event.hasCatalogIdentityConflict {
            return .init(title: "Listing needs an update", message: "The match identity couldn't be confirmed. Refresh the lineup before choosing a broadcast.", symbol: "exclamationmark.circle")
        }
        if policy.isStopped {
            return .init(title: policy.title, message: "This match is not available to watch from this listing.", symbol: "tv.slash")
        }
        if canWatchHere, isChannelFallback, policy.timingAllowsPlayback {
            return .init(title: "Cricket channel available",
                         message: "Choose Watch to open a cricket channel. The programme on air is not confirmed.", symbol: "tv")
        }
        if event.isBroadcastChannel, CricketChannelPlaybackPolicy.canResolve(event, discoveryIndex: discoveryIndex) {
            return .init(title: "Watch channel",
                         message: "Open the channel. Its current programme is not confirmed.", symbol: "tv")
        }
        if let lookup = FixtureSourceLookupPresentation.state(for: event, at: now, status: status,
            enabledProviderCodes: enabledProviderCodes, discoveryIndex: discoveryIndex, catalogIndex: catalogIndex) {
            return .init(title: lookup.detailsTitle,
                         message: lookup.detailsMessage(canWatchHere: canWatchHere && policy.canAttemptPlayback),
                         symbol: lookup.symbol)
        }
        let catalog = catalogIndex ?? (discoveryIndex == nil ? .shared : nil)
        let enabled = enabledProviderCodes ?? catalog?.enabledProviderCodes ?? []
        if let providers = catalog?.summary(for: StreamPlaybackRequest(event: event), at: now)?.providers {
            if providers.contains(where: { enabled.contains($0.providerCode) && $0.outcome == .listed }) {
                return .init(title: "Sources listed",
                             message: "An enabled source lists this match. Playback options can be checked closer to the scheduled start.",
                             symbol: "tv")
            }
            if providers.contains(where: { enabled.contains($0.providerCode) && $0.previouslyListed }) {
                return .init(title: "Source listings need rechecking",
                             message: "A source listed this match earlier. Availability will be checked again closer to the start.",
                             symbol: "arrow.clockwise")
            }
        }
        let message: String
        if event.isBroadcastChannel {
            message = "No supported source is listed for this channel. Its current programme is not confirmed."
        } else if policy.hasUnconfirmedFixtureStart || event.kickoffDate == nil {
            message = "No supported stream is listed. The scheduled start is not confirmed."
        } else if policy.upcomingStart != nil {
            message = "No supported stream is listed yet. You can check the lineup again closer to the scheduled start."
        } else {
            message = "No supported stream is listed right now. Refresh the lineup to check again."
        }
        return .init(title: "Broadcast not listed", message: message, symbol: "tv.slash")
    }
}

/// Row-local disclosure identity. Reusing a row for another event never carries
/// its expanded context across; ordinary redraws of the same event retain it.
struct CatalogInlineContextState: Equatable {
    private(set) var eventID: String?
    func isExpanded(for id: String) -> Bool { eventID == id }
    mutating func toggle(for id: String) { eventID = eventID == id ? nil : id }
    mutating func reset() { eventID = nil }
}

/// Secondary, read-only context. The surrounding row remains the sole owner of
/// Watch, Save and Remind; this view never starts discovery or changes consent.
struct CatalogInlineEventContext: View {
    let event: EventReference
    var status: FootballMatch.MatchStatus? = nil
    var now: Date? = nil
    var canWatchHere = false
    var isChannelFallback = false
    let onMoreDetails: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let now {
                content(at: now)
            } else if scenePhase == .active {
                TimelineView(MatchCountdownSchedule(kickoff: event.kickoffDate)) { context in
                    content(at: context.date)
                }
            } else {
                content(at: Date())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match-inline-context-\(event.id)")
    }

    private func content(at now: Date) -> some View {
        let policy = MatchStartPolicy(event: event, now: now, status: status)
        let broadcast = CatalogEventDetailsPresentation.broadcast(for: event, now: now, status: status,
            canWatchHere: canWatchHere, isChannelFallback: isChannelFallback)
        return VStack(alignment: .leading, spacing: 8) {
            if !event.isBroadcastChannel, !policy.hasUnconfirmedFixtureStart, let start = event.kickoffDate {
                Label {
                    Text(start, format: .dateTime.weekday(.wide).month(.abbreviated).day().year().hour().minute())
                        .fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: "calendar") }
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textPrimary)
                .accessibilityLabel("Scheduled start, \(start.formatted(date: .complete, time: .shortened))")
            }
            Label(broadcast.title, systemImage: broadcast.symbol)
                .font(FottyTheme.typeMeta.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(broadcast.message)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("More details", action: onMoreDetails)
                .font(FottyTheme.typeAction)
                .foregroundStyle(FottyTheme.accentText)
                .frame(minHeight: 44, alignment: .leading)
                .buttonStyle(FottyPressButtonStyle())
                .accessibilityHint("Opens the full match information and existing source options")
        }
    }
}

struct CatalogEventDetailsView: View {
    let event: AnalyticalDataEngine.EventReference
    var onWatch: (() -> Void)? = nil
    var alternateActionTitle: String? = nil
    var onCheckStreams: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(LiveScoreService.self) private var scoreService
    @State private var savedMatches: MyMatchdayStore
    @State private var saveError: String?

    @MainActor
    init(event: AnalyticalDataEngine.EventReference, onWatch: (() -> Void)? = nil,
         alternateActionTitle: String? = nil, onCheckStreams: (() -> Void)? = nil,
         savedMatches: MyMatchdayStore? = nil) {
        self.event = event
        self.onWatch = onWatch
        self.alternateActionTitle = alternateActionTitle
        self.onCheckStreams = onCheckStreams
        self._savedMatches = State(initialValue: savedMatches ?? .shared)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()

                ScrollView {
                  VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                    detailsHeader

                    VStack(alignment: .leading, spacing: 12) {
                        if event.isBroadcastChannel {
                            Label(event.title ?? "Cricket channel", systemImage: "tv")
                                .font(FottyTheme.typeSectionTitle)
                        } else if event.awayName == "Away", event.teams?.away?.name == nil {
                            Text(event.displayTitle)
                                .font(FottyTheme.typeSectionTitle)
                                .foregroundStyle(FottyTheme.textPrimary)
                        } else {
                            teamRow(name: event.homeName, crest: event.homeBadgeURL)
                            teamRow(name: event.awayName, crest: event.awayBadgeURL)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(FottyTheme.surface, in: RoundedRectangle(cornerRadius: 18))

                    // Keep the existing primary action beside the match it
                    // belongs to, before long provenance/help in a medium sheet.
                    if !event.hasCatalogIdentityConflict,
                       !event.isBroadcastChannel || onWatch != nil {
                        MatchStartControls(event: event,
                            status: MatchStartPolicy.currentStatus(for: event, scores: scoreService),
                            onWatch: onWatch, alternateActionTitle: alternateActionTitle,
                            onCheckStreams: onCheckStreams) {
                            EmptyView()
                        }
                    }

                    CurrentSportsMatchContextView(event: event)

                    if CPLSchedule.isManagedFixtureID(event.id) {
                        Text(CPLSchedule.sourceLabel + "\n" + CPLSchedule.sourceNote)
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(FottyTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if sharedLookupPresentation?.canWatch != false {
                            Label(broadcastPresentation.title, systemImage: broadcastPresentation.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FottyTheme.textPrimary)
                        }

                        Text(broadcastPresentation.message)
                            .font(.subheadline)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(FottyTheme.spacingMD)
                    .bentoSurface(cornerRadius: FottyTheme.radiusMD)

                    if !event.hasCatalogIdentityConflict {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                if let message = savedMatches.toggle(event).errorMessage { saveError = message }
                            } label: {
                                Label(isSaved ? "Remove from My Matchday" : "Save to My Matchday",
                                      systemImage: isSaved ? "bookmark.slash" : "bookmark")
                                    .font(FottyTheme.typeAction)
                                    .foregroundStyle(FottyTheme.accentText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(FottyPressButtonStyle())
                            .accessibilityHint(isSaved ? "Also cancels any start reminder for this match"
                                : "Saves without enabling a start reminder")
                            .accessibilityIdentifier("match-details-save")
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                // The sheet may be wide on iPad. Keep explanatory paragraphs
                // readable without constraining the surrounding app window.
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .navigationTitle(event.isBroadcastChannel ? "Channel details" : "Match details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(FottyTheme.accentText)
                }
            }
        }
        .alert("Couldn't update My Matchday", isPresented: .init(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var isSaved: Bool { savedMatches.contains(event: event) }

    @ViewBuilder private var detailsHeader: some View {
        if typeSize.isAccessibilitySize {
            stackedDetailsHeader
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    categoryLabel.fixedSize()
                    Spacer(minLength: 0)
                    statusBadge.fixedSize()
                }
                stackedDetailsHeader
            }
        }
    }

    private var stackedDetailsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryLabel
            statusBadge
        }
    }

    private var categoryLabel: some View {
        Text(event.categoryDisplayName)
            .font(.subheadline)
            .foregroundStyle(FottyTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(FottyTheme.typeMeta)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isLive ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(isLive ? FottyTheme.accent : FottyTheme.surfaceElevated)
            .clipShape(Capsule())
    }

    private var broadcastPresentation: CatalogEventDetailsPresentation {
        .broadcast(for: event, status: MatchStartPolicy.currentStatus(for: event, scores: scoreService),
                   canWatchHere: onWatch != nil, isChannelFallback: alternateActionTitle != nil)
    }

    private var sharedLookupPresentation: FixtureSourceLookupPresentation.State? {
        guard onCheckStreams != nil else { return nil }
        return FixtureSourceLookupPresentation.state(for: event,
            status: MatchStartPolicy.currentStatus(for: event, scores: scoreService))
    }

    private var isLive: Bool {
        if let activity = CricketActivityPresentationPolicy.activity(for: event, at: Date()) {
            return !activity.suppressesLiveBadge
        }
        return HomeMatchPriority.isLive(event, scoreService: scoreService)
    }

    private var statusLabel: String {
        if event.isBroadcastChannel { return "CHANNEL" }
        let policy = MatchStartPolicy(event: event, status: MatchStartPolicy.currentStatus(for: event, scores: scoreService))
        if policy.isStopped || policy.hasUnconfirmedFixtureStart { return policy.title }
        if let activity = CricketActivityPresentationPolicy.activity(for: event, at: Date()) { return activity.title }
        if isLive { return "IN PLAY" }
        guard let kickoff = event.kickoffDate else { return "SCHEDULED" }
        return kickoff.arenaKickoffDetailLine()
    }

    private func teamRow(name: String, crest: URL?) -> some View {
        HStack(spacing: 12) {
            FlagSquircleBadge(name: name, badgeURL: crest, size: 40, glowEnabled: false)
            Text(name)
                .font(.headline)
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

