import SwiftUI

/// Compact, status-aware lead match card.
/// Width is measured from the *proposed* container size (overlay GeometryReader),
/// never from `UIScreen` — screen-width fallback overflows the iPad bento column.
struct HeroMatchCarousel: View {
    let events: [AnalyticalDataEngine.EventReference]
    let onWatch: (AnalyticalDataEngine.EventReference) -> Void
    var isSaved: (AnalyticalDataEngine.EventReference) -> Bool = { _ in false }
    var onToggleSaved: ((AnalyticalDataEngine.EventReference) -> Void)? = nil
    var compactHeight: Bool = false
    
    @State private var activeID: String?
    @Environment(LiveScoreService.self) private var scoreService
    
    private var heroHeight: CGFloat { compactHeight ? 190 : 216 }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { geo in
                        let pageWidth = max(geo.size.width, 1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(events) { event in
                                    heroCard(for: event)
                                        .frame(width: pageWidth, height: heroHeight)
                                        .id(event.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $activeID)
                        .frame(width: pageWidth, height: heroHeight)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
            
            if events.count > 1 {
                HStack(spacing: 5) {
                    ForEach(events) { event in
                        Rectangle()
                            .fill((activeID ?? events.first?.id) == event.id
                                  ? FottyTheme.accent
                                  : Color.white.opacity(0.18))
                            .frame(
                                width: (activeID ?? events.first?.id) == event.id ? 24 : 8,
                                height: 3
                            )
                            .animation(FottyTheme.springSnappy, value: activeID)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if activeID == nil {
                activeID = events.first?.id
            }
        }
    }
    
    @ViewBuilder
    private func heroCard(for event: AnalyticalDataEngine.EventReference) -> some View {
        let matchedFootball = event.normalizedCategory == "football"
            ? scoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil
        let score = event.normalizedCategory == "football"
            ? scoreService.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) : nil
        let isLive = HomeMatchPriority.isLive(event, scoreService: scoreService)
        let scoreCoverageAvailable = FootballDataPolicy.hasConfirmedLiveScoreCoverage(
            competition: matchedFootball?.competition
        )
        let homeColor = TeamColorResolver.resolve(teamName: event.homeName) ?? Color.gray
        let awayColor = TeamColorResolver.resolve(teamName: event.awayName) ?? Color.blue
        let homeCrest = event.homeBadgeURL
            ?? matchedFootball.flatMap { $0.homeTeam.crest.flatMap { URL(string: $0) } }
            ?? (event.normalizedCategory == "football" ? TeamBrandService.shared.badgeURL(for: event.homeName, triggerSearch: true) : nil)
        let awayCrest = event.awayBadgeURL
            ?? matchedFootball.flatMap { $0.awayTeam.crest.flatMap { URL(string: $0) } }
            ?? (event.normalizedCategory == "football" ? TeamBrandService.shared.badgeURL(for: event.awayName, triggerSearch: true) : nil)
        let competition = shortCompetition(
            matchedFootball?.competition.audienceFacingName
                ?? matchedFootball?.competition.name
                ?? (event.isCPLFixture ? "Caribbean Premier League" : event.categoryDisplayName)
        )
        
        ZStack {
            LinearGradient(
                colors: [
                    homeColor.opacity(0.28),
                    FottyTheme.background,
                    awayColor.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            FottyTheme.heroGradient
                .opacity(0.88)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(competition.uppercased())
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 8)

                    if let onToggleSaved {
                        Button {
                            onToggleSaved(event)
                        } label: {
                            Image(systemName: isSaved(event) ? "bookmark.fill" : "bookmark")
                                .font(.fottyScaled(size: 13, weight: .bold))
                                .foregroundStyle(isSaved(event) ? FottyTheme.accentText : FottyTheme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(FottyTheme.surfaceElevated.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSaved(event) ? "Remove from My Matchday" : "Save to My Matchday")
                    }
                    
                    if isLive {
                        Text(liveStatusLabel(score: score, scoreCoverageAvailable: scoreCoverageAvailable))
                            .font(.fottyScaled(size: 11, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(FottyTheme.textOnAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(FottyTheme.accent)
                    } else {
                        Text(event.broadcastTiming().rawValue)
                            .font(.fottyScaled(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }

                
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        heroTeam(name: event.homeName, crest: homeCrest)
                        heroTeam(name: event.awayName, crest: awayCrest)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 10) {
                        if let score {
                            Text("\(score.homeGoals)–\(score.awayGoals)")
                                .font(.fottyScaled(size: 32, weight: .black, design: .rounded))
                                .foregroundStyle(FottyTheme.textPrimary)
                                .monospacedDigit()
                        } else {
                            Text(isLive ? "Started \(kickoffTimeLabel(for: event))" : kickoffTimeLabel(for: event))
                                .font(.fottyScaled(size: isLive ? 14 : 20, weight: .black, design: .rounded))
                                .foregroundStyle(FottyTheme.textPrimary)
                        }

                    Button {
                        onWatch(event)
                    } label: {
                        Label(LiveEventCard.broadcastActionLabel(isLive: isLive), systemImage: "play.fill")
                            .font(FottyTheme.typeAction)
                            .foregroundStyle(FottyTheme.textOnAccent)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(FottyTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hero-watch-live")
                    .accessibilityLabel(LiveEventCard.broadcastActionLabel(isLive: isLive))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(FottyTheme.accent)
                .frame(width: 4)
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { onWatch(event) }
    }

    private func liveStatusLabel(
        score: LiveScoreService.LiveScore?,
        scoreCoverageAvailable: Bool
    ) -> String {
        if let minute = score?.minute { return "LIVE · \(minute)" }
        if score != nil { return "LIVE" }
        guard scoreCoverageAvailable else { return "LIVE" }
        return scoreService.isRefreshing ? "LIVE · UPDATING" : "LIVE · SCORE UNAVAILABLE"
    }
    
    private func heroTeam(name: String, crest: URL?) -> some View {
        HStack(spacing: 10) {
            FlagSquircleBadge(name: name, badgeURL: crest, size: 36, glowEnabled: false)
            Text(MatchCardFormatting.compactTeamName(name))
                .font(.fottyScaled(size: 15, weight: .bold))
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
    
    private func shortCompetition(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 28 { return trimmed }
        let replacements: [(String, String)] = [
            ("Campeonato Brasileiro Série A", "Brasileirão"),
            ("Campeonato Brasileiro Serie A", "Brasileirão"),
            ("UEFA Champions League", "Champions League"),
        ]
        for (long, short) in replacements where trimmed.localizedCaseInsensitiveContains(long) {
            return short
        }
        return String(trimmed.prefix(28))
    }
    
    private func kickoffTimeLabel(for event: AnalyticalDataEngine.EventReference) -> String {
        guard let date = event.kickoffDate else { return "TBD" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
