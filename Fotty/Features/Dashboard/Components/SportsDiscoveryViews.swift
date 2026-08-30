import SwiftUI

/// A small, fully measured grid: every cell uses the tallest tile's height,
/// including the final row. Text scaling changes column capacity, not identity.
struct SportTileGridLayout: Layout {
    var minimumTileWidth: CGFloat
    var spacing: CGFloat = 6

    struct Metrics {
        let width: CGFloat
        let columns: Int
        let count: Int
        let spacing: CGFloat
        var tileHeight: CGFloat = 0

        var tileWidth: CGFloat { columns == 0 ? 0 : max(0, width - CGFloat(columns - 1) * spacing) / CGFloat(columns) }
        var rows: Int { columns == 0 ? 0 : (count + columns - 1) / columns }
        var size: CGSize { CGSize(width: width, height: CGFloat(rows) * tileHeight + CGFloat(max(0, rows - 1)) * spacing) }

        func origin(at index: Int) -> CGPoint {
            guard columns > 0 else { return .zero }
            return CGPoint(x: CGFloat(index % columns) * (tileWidth + spacing), y: CGFloat(index / columns) * (tileHeight + spacing))
        }
    }

    func metrics(width proposedWidth: CGFloat?, count: Int) -> Metrics {
        let width = proposedWidth.flatMap { $0.isFinite ? max(0, $0) : nil } ?? minimumTileWidth
        let capacity = floor((width + spacing) / (minimumTileWidth + spacing))
        let columns = count == 0 ? 0 : Int(max(1, min(CGFloat(count), capacity)))
        return Metrics(width: width, columns: columns, count: count, spacing: spacing)
    }

    private func measured(width: CGFloat?, subviews: Subviews) -> Metrics {
        var grid = metrics(width: width, count: subviews.count)
        grid.tileHeight = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: grid.tileWidth, height: nil)).height
        }.max() ?? 0
        return grid
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measured(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = measured(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let origin = grid.origin(at: index)
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: grid.tileWidth, height: grid.tileHeight)
            )
        }
    }
}

struct SportActivityGrid: View {
    static var tileForeground: Color { FottyTheme.textPrimary }
    static func tileBackground(selected: Bool) -> Color {
        selected ? FottyTheme.accent.opacity(0.12) : FottyTheme.surface
    }

    let discovery: HomeSportsDiscovery
    @Binding var selectedSport: String
    var expanded = false
    var onMore: () -> Void = {}
    // Explicit for size-specific previews/tests; Catalyst can report the iPad idiom.
    var isPad = UIDevice.current.userInterfaceIdiom == .pad
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .subheadline) private var minimumTileWidth: CGFloat = 94

    static func showsAllSports(expanded: Bool, regularWidth: Bool, isPad: Bool) -> Bool {
        expanded || regularWidth || isPad
    }

    var body: some View {
        let showAll = Self.showsAllSports(expanded: expanded, regularWidth: horizontalSizeClass == .regular, isPad: isPad)
        let visible = showAll ? discovery.activities : discovery.visibleActivities(selectedSport: selectedSport)
        VStack(alignment: .leading, spacing: 4) {
            SportTileGridLayout(minimumTileWidth: minimumTileWidth) {
                tile(id: HomeSportsDiscovery.allSports, title: "All sports", summary: "Now & next")
                ForEach(visible) { activity in
                    tile(id: activity.id, title: AnalyticalDataEngine.categoryDisplayName(for: activity.id), summary: activity.summary(at: discovery.now))
                }
            }
            .frame(maxWidth: .infinity)
            if !showAll, discovery.activities.count > visible.count {
                let hidden = discovery.activities.filter { activity in !visible.contains { $0.id == activity.id } }
                let onNow = hidden.reduce(0) { $0 + $1.onNow }
                let upcoming = hidden.filter { $0.nextStart != nil }.count
                Button(action: onMore) {
                    HStack(spacing: 5) {
                        Text("More sports")
                        if onNow > 0 { Text("· \(onNow) on now") }
                        else if upcoming > 0 { Text("· \(upcoming) coming up") }
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-more-sports")
                .accessibilityHint("Shows activity and filters for every listed sport")
            }
        }
    }

    private func tile(id: String, title: String, summary: String) -> some View {
        let selected = selectedSport == id
        return Button { selectedSport = id } label: {
            VStack(alignment: .leading, spacing: 5) {
                SportEmblem(category: id, size: 26)
                    .padding(.bottom, 2)
                Text(title)
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(Self.tileForeground)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-sport-color-\(id)-title")
                Text(summary)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(Self.tileForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-sport-color-\(id)-summary")
            }
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Self.tileBackground(selected: selected))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? FottyTheme.accentText : FottyTheme.borderStrong, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityHint("Filters the Home lineup")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home-sport-\(id)")
    }
}

/// Compact, labeled actions; a fixture never becomes a poster-sized tap target.
struct HomeDiscoveryRow: View {
    let item: HomeSportsDiscovery.Item
    let isSaved: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    @Environment(LiveScoreService.self) private var scoreService

    var body: some View {
        MatchStartControls(event: item.event, status: item.officialStatus, onWatch: onOpen) {
            eventInformation
                .accessibilityAction(named: Text(saveTitle), onSave)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button(saveTitle, systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSave)
                .accessibilityIdentifier("home-save-\(item.id)")
        }
    }

    private var saveTitle: String { isSaved ? "Remove from My Matchday" : "Save to My Matchday" }

    @ViewBuilder
    private var eventInformation: some View {
        if MatchStartPolicy(event: item.event, status: item.officialStatus).canAttemptPlayback {
            Button(action: onOpen) {
                eventText.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the listed broadcast. Availability depends on the source. Long-press to save to My Matchday.")
            .accessibilityIdentifier(item.isOnNow ? "home-watch-now" : "home-event-\(item.id)")
        } else {
            // A future fixture is readable information, not a disabled
            // button. Do not dim team names/badges along with playback.
            eventText.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Long-press to save to My Matchday without a reminder.")
                .accessibilityIdentifier("home-event-\(item.id)")
        }
    }

    private var eventText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(competitionLabel)
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textSecondary)
            if !Self.showsTeamBadges(for: item.event) {
                Label(item.event.displayTitle, systemImage: item.event.isBroadcastChannel ? "tv" : SportIdentity.symbol(for: item.sport))
                    .font(FottyTheme.typeBody.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
            } else {
                teamLine(name: item.event.homeName, badge: item.event.homeBadgeURL ?? matchedFootball?.homeTeam.crest.flatMap(URL.init(string:)))
                teamLine(name: item.event.awayName, badge: item.event.awayBadgeURL ?? matchedFootball?.awayTeam.crest.flatMap(URL.init(string:)))
            }
            Text(scoreLabel ?? item.statusLabel)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(item.isOnNow ? FottyTheme.accentText : FottyTheme.textSecondary)
            if item.id.hasPrefix("cpl-2026-") {
                Text(CPLSchedule.sourceLabel)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var matchedFootball: FootballMatch? {
        guard item.sport == "football" else { return nil }
        return scoreService.findMatch(home: item.event.homeName, away: item.event.awayName, near: item.event.kickoffDate)
    }

    static func showsTeamBadges(for event: AnalyticalDataEngine.EventReference) -> Bool {
        guard !event.isBroadcastChannel else { return false }
        let names = [event.homeName, event.awayName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return names.allSatisfy { !$0.isEmpty && $0 != "home" && $0 != "away" }
    }

    private func teamLine(name: String, badge: URL?) -> some View {
        HStack(spacing: 8) {
            // Reuse the provider/catalog badge cache, including NBA/MLB branding.
            // Missing artwork keeps a named initials fallback, never a made-up crest.
            FlagSquircleBadge(name: name, badgeURL: badge, size: 28, glowEnabled: false)
                .accessibilityHidden(true)
            Text(MatchCardFormatting.denseTeamName(name))
                .font(FottyTheme.typeBody.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    private var competitionLabel: String {
        if item.event.isCPLFixture { return "Cricket · CPL" }
        if item.sport == "football", let match = scoreService.findMatch(home: item.event.homeName, away: item.event.awayName, near: item.event.kickoffDate) {
            return "Football · \(match.competition.audienceFacingName)"
        }
        return item.event.categoryDisplayName
    }

    private var scoreLabel: String? {
        guard item.phase == .live, item.sport == "football",
              let score = scoreService.scoreForMatch(home: item.event.homeName, away: item.event.awayName, near: item.event.kickoffDate),
              score.status.isLive else { return nil }
        let qualifier = scoreService.scoreStatusQualifier.map { " · \($0)" } ?? ""
        return "\(score.homeGoals)–\(score.awayGoals) · \(score.minute ?? score.status.displayText)\(qualifier)"
    }
}
