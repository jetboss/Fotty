import SwiftUI

/// Dense cinema row for Home rails and fixture lists.
struct LiveEventCard: View {
    let event: AnalyticalDataEngine.EventReference
    var onInfoTap: ((FootballMatch) -> Void)? = nil
    var onWatchTap: (() -> Void)? = nil
    var alternateActionTitle: String? = nil
    var onDetailsTap: (() -> Void)? = nil
    var onCheckStreams: (() -> Void)? = nil
    var isSaved = false
    var onSaveTap: (() -> Void)? = nil
    var grouped = false

    @Environment(LiveScoreService.self) private var scoreService
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var categoryFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var teamFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var detailedTeamFontSize: CGFloat = 15
    @State private var inlineContext = CatalogInlineContextState()

    var body: some View {
        let matchedFootball = event.normalizedCategory == "football"
            ? scoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil
        let score = event.normalizedCategory == "football" && !WatchingSpoilerProtection.shared.protects(event)
            ? scoreService.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil
        let now = Date()
        let status = MatchStartPolicy.currentStatus(for: event, scores: scoreService, now: now)
        let section = MatchdayEventStatePolicy.section(for: event, at: now, status: status)
        let isLive = section == .live && (onDetailsTap == nil
            || CricketActivityPresentationPolicy.activity(for: event, at: now)?.suppressesLiveBadge != true)
        let scoreCoverageAvailable = FootballDataPolicy.hasConfirmedLiveScoreCoverage(
            competition: matchedFootball?.competition
        )
        let categoryText = event.sportsFixture?.competitionName ?? event.cricketFixture?.competitionName
            ?? (event.isCPLFixture ? "Caribbean Premier League" : (matchedFootball?.competition.audienceFacingName ?? event.categoryDisplayName))
        let homeCrest = event.homeBadgeURL
            ?? matchedFootball.flatMap { $0.homeTeam.crest.flatMap { URL(string: $0) } }
            ?? (event.normalizedCategory == "football" ? TeamBrandService.shared.badgeURL(for: event.homeName, triggerSearch: false) : nil)
        let awayCrest = event.awayBadgeURL
            ?? matchedFootball.flatMap { $0.awayTeam.crest.flatMap { URL(string: $0) } }
            ?? (event.normalizedCategory == "football" ? TeamBrandService.shared.badgeURL(for: event.awayName, triggerSearch: false) : nil)

        VStack(alignment: .leading, spacing: 8) {
        MatchStartControls(event: event,
            status: status,
            onWatch: onWatchTap, alternateActionTitle: alternateActionTitle,
            onCheckStreams: onCheckStreams,
            showsReminder: onSaveTap != nil, rowActions: visibleMatchActions) {
            VStack(alignment: .leading, spacing: 7) {
                // The surrounding dashboard already identifies the sport. Only
                // show a more useful competition name; repeating "Football" on
                // every fixture adds noise and constrains Dynamic Type layouts.
                if categoryText.localizedCaseInsensitiveCompare(event.categoryDisplayName) != .orderedSame {
                    Text(categoryText)
                        .font(onDetailsTap == nil
                            ? .system(size: categoryFontSize, weight: .bold)
                            : .caption)
                        .foregroundStyle(FottyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }


                if event.isBroadcastChannel {
                    Label(event.title ?? "Cricket channel", systemImage: "tv")
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let fixture = event.sportsFixture, fixture.eventKind != .match {
                    Label(event.displayTitle, systemImage: SportIdentity.symbol(for: event.normalizedCategory))
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    teamRow(name: event.homeName, crest: homeCrest)
                    teamRow(name: event.awayName, crest: awayCrest)
                }
                if !event.isBroadcastChannel || (onWatchTap == nil && onDetailsTap != nil) {
                    HStack(alignment: .center, spacing: 8) {
                        if !event.isBroadcastChannel {
                            VStack(alignment: .leading, spacing: 3) {
                                scoreColumn(score: score, section: section,
                                    scoreCoverageAvailable: scoreCoverageAvailable, broadcastAvailable: onWatchTap != nil)
                            }
                        }
                        Spacer(minLength: 0)
                        if onWatchTap == nil, onDetailsTap != nil {
                            Button { inlineContext.toggle(for: event.id) } label: {
                                Label("Details", systemImage: inlineContext.isExpanded(for: event.id) ? "chevron.up" : "chevron.down")
                                    .labelStyle(.titleAndIcon)
                                    .font(FottyTheme.typeMeta)
                                    .foregroundStyle(FottyTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(FottyPressButtonStyle())
                            .accessibilityValue(inlineContext.isExpanded(for: event.id) ? "Expanded" : "Collapsed")
                            .accessibilityHint("Shows or hides schedule and broadcast information in this list")
                        } else if matchedFootball != nil, onInfoTap != nil {
                            Button {
                                if let match = matchedFootball { onInfoTap?(match) }
                            } label: {
                                Text("Details")
                                    .font(FottyTheme.typeMeta)
                                    .foregroundStyle(FottyTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(FottyPressButtonStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityActions {
                if let onSaveTap {
                    Button(saveTitle, action: onSaveTap)
                }
            }
        }
        if inlineContext.isExpanded(for: event.id), let onDetailsTap {
            CatalogInlineEventContext(event: event, status: status,
                canWatchHere: onWatchTap != nil, isChannelFallback: alternateActionTitle != nil,
                onMoreDetails: onDetailsTap)
        }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 76, alignment: .center)
        .onChange(of: event.id) { _, _ in inlineContext.reset() }
        .if(!grouped) { $0.bentoSurface(cornerRadius: FottyTheme.radiusMD) }
        .contextMenu {
            if let onSaveTap {
                Button(saveTitle, systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSaveTap)
                    .accessibilityIdentifier("match-save-\(event.id)")
            }
        }
        .overlay {
            if isLive && !grouped {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                    .strokeBorder(FottyTheme.accent.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private var saveTitle: String { isSaved ? "Remove from My Matchday" : "Save to My Matchday" }

    private var visibleMatchActions: CatalogMatchActionsMenu? {
        // Passive cards and one-action multi-select consumers supply no Details
        // callback. Keep them unchanged; active Matchday/channel rows already
        // provide the existing Details and Save/Remove operations.
        guard onDetailsTap != nil else { return nil }
        return CatalogMatchActionsMenu(eventID: event.id, eventTitle: event.displayTitle,
            isSaved: isSaved, canSave: onSaveTap != nil && !event.hasCatalogIdentityConflict,
            onSave: { onSaveTap?() }, onDetails: { inlineContext.toggle(for: event.id) },
            detailsExpanded: inlineContext.isExpanded(for: event.id))
    }

    private func teamRow(name: String, crest: URL?) -> some View {
        HStack(spacing: 8) {
            TeamBadgeWindow(teamName: name, badgeURL: crest, size: 27, glowEnabled: false, showsFrame: false)
            Text(MatchCardFormatting.denseTeamName(name))
                // Active browsing/planning rows follow the approved quieter
                // hierarchy. Passive/Watch Two cards retain their prior type.
                .font(.system(size: onDetailsTap == nil ? teamFontSize : detailedTeamFontSize,
                              weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(onDetailsTap != nil || typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("dashboard-team-name")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    @ViewBuilder
    private func scoreColumn(
        score: LiveScoreService.LiveScore?,
        section: MatchdayEventStatePolicy.Section,
        scoreCoverageAvailable: Bool,
        broadcastAvailable: Bool
    ) -> some View {
        let isLive = section == .live
        if let score {
            Text("\(score.homeGoals)–\(score.awayGoals)")
                .font(.fottyScaled(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(FottyTheme.textPrimary)
            Text(
                score.status.isLive && !isLive
                ? "Last checked score"
                : scoreService.scoreStatusQualifier.map {
                    "\(score.minute ?? score.status.displayText) · \($0)"
                } ?? (score.minute ?? score.status.displayText)
            )
                .font(FottyTheme.typeCaption)
                .foregroundStyle(isLive ? FottyTheme.accentText : FottyTheme.textSecondary)
        } else if onDetailsTap != nil,
                  let activity = CricketActivityPresentationPolicy.activity(for: event, at: Date()), activity.suppressesLiveBadge {
            Text(activity.title)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let label = Self.prominentStatusLabel(for: section, broadcastAvailable: broadcastAvailable) {
            Text(label)
                .font(isLive ? .fottyScaled(size: 12, weight: .black) : FottyTheme.typeMeta)
                .foregroundStyle(isLive && broadcastAvailable ? FottyTheme.accentText : FottyTheme.textSecondary)
            if isLive && scoreCoverageAvailable {
                Text(scoreService.isRefreshing ? "Updating score" : "Score unavailable")
                    .font(.fottyScaled(size: 9, weight: .medium))
                    .foregroundStyle(FottyTheme.textTertiary)
            } else if section == .listedNow {
                Text(timeLabel)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textTertiary)
            }
        } else {
            Text(timeLabel)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }

    static func broadcastActionLabel(isLive: Bool) -> String {
        isLive ? "Watch live" : "Watch"
    }

    /// Timing alone must never supply the same label as fresh official or
    /// verified fixture status, including on saved and search rows.
    static func prominentStatusLabel(
        for section: MatchdayEventStatePolicy.Section,
        broadcastAvailable: Bool
    ) -> String? {
        switch section {
        case .live: return broadcastAvailable ? "LIVE" : "IN PLAY"
        case .listedNow: return "Broadcast listed"
        default: return nil
        }
    }

    private func actionLabel(isLive: Bool) -> String {
        event.isBroadcastChannel ? "Open channel" : Self.broadcastActionLabel(isLive: isLive)
    }

    private var timeLabel: String {
        if event.isBroadcastChannel { return "CHANNEL" }
        guard let kickoff = event.kickoffDate else { return "Time TBC" }
        // The surrounding list already groups fixtures by day. Showing only
        // today's time prevents the date from squeezing team names in the dense
        // two-column iPad layout; non-today rows retain their date context.
        return kickoff.arenaKickoffDetailLine()
    }

}
