import SwiftUI

/// Dense cinema row for Home rails and fixture lists.
struct LiveEventCard: View {
    let event: AnalyticalDataEngine.EventReference
    var onInfoTap: ((FootballMatch) -> Void)? = nil
    var onWatchTap: (() -> Void)? = nil
    var onDetailsTap: (() -> Void)? = nil
    var isSaved = false
    var onSaveTap: (() -> Void)? = nil

    @Environment(LiveScoreService.self) private var scoreService
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var categoryFontSize: CGFloat = 10
    @ScaledMetric(relativeTo: .subheadline) private var teamFontSize: CGFloat = 15

    var body: some View {
        let matchedFootball = event.normalizedCategory == "football"
            ? scoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil
        let score = event.normalizedCategory == "football"
            ? scoreService.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil
        let isLive = isLiveMatch(score: score)
        let scoreCoverageAvailable = FootballDataPolicy.hasConfirmedLiveScoreCoverage(
            competition: matchedFootball?.competition
        )
        let categoryText = event.isCPLFixture ? "Caribbean Premier League" : (matchedFootball?.competition.audienceFacingName ?? event.categoryDisplayName)
        let homeCrest = event.homeBadgeURL
            ?? matchedFootball.flatMap { $0.homeTeam.crest.flatMap { URL(string: $0) } }
            ?? (event.normalizedCategory == "football" ? TeamBrandService.shared.badgeURL(for: event.homeName, triggerSearch: false) : nil)
        let awayCrest = event.awayBadgeURL
            ?? matchedFootball.flatMap { $0.awayTeam.crest.flatMap { URL(string: $0) } }
            ?? (event.normalizedCategory == "football" ? TeamBrandService.shared.badgeURL(for: event.awayName, triggerSearch: false) : nil)

        MatchStartControls(event: event,
            status: MatchStartPolicy.currentStatus(for: event, scores: scoreService),
            onWatch: onWatchTap, showsReminder: onSaveTap != nil) {
            VStack(alignment: .leading, spacing: 7) {
                // The surrounding dashboard already identifies the sport. Only
                // show a more useful competition name; repeating "Football" on
                // every fixture adds noise and constrains Dynamic Type layouts.
                if categoryText.localizedCaseInsensitiveCompare(event.categoryDisplayName) != .orderedSame {
                    Text(categoryText)
                        .font(.system(size: categoryFontSize, weight: .bold))
                        .foregroundStyle(FottyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }


                if event.isBroadcastChannel {
                    Label(event.title ?? "Cricket channel", systemImage: "tv")
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cricket channel")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                } else {
                    teamRow(name: event.homeName, crest: homeCrest)
                    teamRow(name: event.awayName, crest: awayCrest)
                }
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        scoreColumn(score: score, isLive: isLive,
                            scoreCoverageAvailable: scoreCoverageAvailable, broadcastAvailable: onWatchTap != nil)
                    }
                    Spacer(minLength: 0)
                    if onWatchTap == nil, event.kickoffDate == nil, let onDetailsTap {
                        Button(action: onDetailsTap) {
                            Label("Details", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .font(FottyTheme.typeMeta)
                                .foregroundStyle(FottyTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens match information")
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
                        .buttonStyle(.plain)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 76, alignment: .center)
        .bentoSurface(cornerRadius: FottyTheme.radiusMD)
        .contextMenu {
            if let onSaveTap {
                Button(saveTitle, systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSaveTap)
                    .accessibilityIdentifier("match-save-\(event.id)")
            }
        }
        .overlay {
            if isLive {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                    .strokeBorder(FottyTheme.accent.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private var saveTitle: String { isSaved ? "Remove from My Matchday" : "Save to My Matchday" }

    private func teamRow(name: String, crest: URL?) -> some View {
        HStack(spacing: 8) {
            FlagSquircleBadge(name: name, badgeURL: crest, size: 28, glowEnabled: false)
            Text(MatchCardFormatting.denseTeamName(name))
                .font(.system(size: teamFontSize, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
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
        isLive: Bool,
        scoreCoverageAvailable: Bool,
        broadcastAvailable: Bool
    ) -> some View {
        if let score {
            Text("\(score.homeGoals)–\(score.awayGoals)")
                .font(.fottyScaled(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(FottyTheme.textPrimary)
            Text(
                scoreService.scoreStatusQualifier.map {
                    "\(score.minute ?? score.status.displayText) · \($0)"
                } ?? (score.minute ?? score.status.displayText)
            )
                .font(FottyTheme.typeCaption)
                .foregroundStyle(score.status.isLive ? FottyTheme.accentText : FottyTheme.textSecondary)
        } else if isLive {
            Text(broadcastAvailable ? "LIVE" : "IN PLAY")
                .font(.fottyScaled(size: 12, weight: .black))
                .foregroundStyle(broadcastAvailable ? FottyTheme.accentText : FottyTheme.textSecondary)
            if scoreCoverageAvailable {
                Text(scoreService.isRefreshing ? "Updating score" : "Score unavailable")
                    .font(.fottyScaled(size: 9, weight: .medium))
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
        isLive ? "Watch live" : "Check streams"
    }

    private func actionLabel(isLive: Bool) -> String {
        event.isBroadcastChannel ? "Open channel" : Self.broadcastActionLabel(isLive: isLive)
    }

    private func isLiveMatch(score: LiveScoreService.LiveScore?) -> Bool {
        if let status = score?.status {
            return status.isLive
        }
        return event.broadcastTiming() == .live
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
