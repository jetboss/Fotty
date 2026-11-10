import SwiftUI

/// A local return shortcut, separate from the current lineup and retained
/// mini-player. It contains event identity only; opening resolves sources afresh.
struct LastLiveMatchCard: View {
    let event: EventReference
    let actionTitle: String
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Back to your match")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(FottyTheme.textSecondary)
                .accessibilityLabel("Forget this match")
                .accessibilityIdentifier("last-live-dismiss")
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { matchIdentity; openButton }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        matchIdentity.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        openButton.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 12) { matchIdentity; openButton }
                }
            }
        }
        .padding(FottyTheme.spacingMD)
        .bentoSurface()
        .accessibilityIdentifier("last-live-card")
    }

    private var matchIdentity: some View {
        HStack(alignment: .center, spacing: 12) {
            if event.awayName.isEmpty || event.sportsFixture.map({ $0.eventKind != .match }) == true {
                SportEmblem(category: event.normalizedCategory, size: 32).accessibilityHidden(true)
            } else {
                HStack(spacing: 3) {
                    TeamBadgeWindow(teamName: event.homeName, badgeURL: event.homeBadgeURL, size: 32, triggerSearch: true)
                    TeamBadgeWindow(teamName: event.awayName, badgeURL: event.awayBadgeURL, size: 32, triggerSearch: true)
                }
                .accessibilityHidden(true)
            }
            Text(event.displayTitle)
                .font(.headline)
                .foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var openButton: some View {
        Button(action: onOpen) {
            Label(actionTitle, systemImage: "play.fill")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(FottyPrimaryButtonStyle())
        .accessibilityLabel("\(actionTitle): \(event.displayTitle)")
        .accessibilityIdentifier("last-live-open")
    }
}

/// Saving is secondary to Watch, but it must not require discovering a
/// long-press. Keep this native menu separate from the row's playback button.
struct CatalogMatchActionsMenu: View {
    let eventID: String
    let eventTitle: String
    let isSaved: Bool
    let canSave: Bool
    let onSave: () -> Void
    var onDetails: (() -> Void)? = nil
    var detailsExpanded: Bool? = nil

    var body: some View {
        Menu {
            if let onDetails {
                Button(detailsExpanded == true ? "Hide match details" : "Match details",
                       systemImage: "info.circle", action: onDetails)
            }
            if canSave {
                Button(isSaved ? "Remove from My Matchday" : "Save to My Matchday",
                       systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSave)
                    .accessibilityIdentifier("home-save-\(eventID)")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // The secondary menu must not inherit Watch's amber tint or add a
        // platform menu chevron beside the explicit ellipsis.
        .tint(FottyTheme.textSecondary)
        .menuIndicator(.hidden)
        .accessibilityLabel("More options for \(eventTitle)")
        .accessibilityValue(isSaved ? "Saved in My Matchday" : "Not saved")
        .accessibilityIdentifier("match-more-\(eventID)")
    }
}

private struct CatalogSavedStateLabel: View {
    let eventID: String
    var body: some View {
        Label("Saved", systemImage: "checkmark.circle")
            .font(FottyTheme.typeCaption)
            .foregroundStyle(FottyTheme.textSecondary)
            .accessibilityLabel("Saved in My Matchday")
            .accessibilityIdentifier("match-saved-\(eventID)")
    }
}

/// Keep a full heading and its real action readable at narrow widths. Native
/// fitting chooses a stacked presentation before either label is compressed;
/// accessibility text always uses that same leading-aligned reading order.
struct CatalogAdaptiveHeading<Title: View, Actions: View>: View {
    let title: Title
    let actions: Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    init(@ViewBuilder title: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.title = title()
        self.actions = actions()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        title.fixedSize(horizontal: true, vertical: true)
                        Spacer(minLength: 8)
                        actions.fixedSize(horizontal: true, vertical: true)
                    }
                    stacked
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            title.fixedSize(horizontal: false, vertical: true)
            actions.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Home's bounded overview is the only two-column editorial composition. The
/// complete catalog remains in the surrounding flattened lazy stack; neither
/// column creates another scroll view or eagerly renders all matches.
struct HomeOverviewLayout: Layout {
    var spacing: CGFloat = 20

    static func columnWidths(in width: CGFloat, spacing: CGFloat = 20) -> (primary: CGFloat, secondary: CGFloat) {
        let available = max(0, width.isFinite ? width - spacing : 0)
        return (available * 1.55 / 2.55, available / 2.55)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 1_000
        let widths = Self.columnWidths(in: width, spacing: spacing)
        let heights = subviews.prefix(2).enumerated().map { index, subview in
            subview.sizeThatFits(.init(width: index == 0 ? widths.primary : widths.secondary, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.columnWidths(in: bounds.width, spacing: spacing)
        for (index, subview) in subviews.prefix(2).enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + (index == 0 ? 0 : widths.primary + spacing), y: bounds.minY),
                          anchor: .topLeading,
                          proposal: .init(width: index == 0 ? widths.primary : widths.secondary, height: nil))
        }
    }
}

/// One section surface, assembled from independently identified lazy rows. The
/// first/last corners group matches without losing their explicit separators.
struct HomeMatchGroupShape: Shape {
    var isFirst: Bool
    var isLast: Bool

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: isFirst ? FottyTheme.radiusLG : 0,
                               bottomLeadingRadius: isLast ? FottyTheme.radiusLG : 0,
                               bottomTrailingRadius: isLast ? FottyTheme.radiusLG : 0,
                               topTrailingRadius: isFirst ? FottyTheme.radiusLG : 0,
                               style: .continuous).path(in: rect)
    }
}

/// A small, fully measured grid: every cell uses the tallest tile's height,
/// including the final row. Text scaling changes column capacity, not identity.
struct SportTileGridLayout: Layout {
    var minimumTileWidth: CGFloat
    var spacing: CGFloat = 6
    var maximumColumns: Int? = nil
    var balancesRows = false

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
        let measuredCapacity = floor((width + spacing) / (minimumTileWidth + spacing))
        let capacity = min(measuredCapacity, CGFloat(maximumColumns ?? max(1, count)))
        var columns = count == 0 ? 0 : Int(max(1, min(CGFloat(count), capacity)))
        if balancesRows, columns > 0, count > columns {
            let rows = (count + columns - 1) / columns
            columns = (count + rows - 1) / rows
        }
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
    /// Precomputed from the same filters as the destination rows. Tests and
    /// standalone previews can omit it to use the discovery's full catalog.
    var activities: [HomeSportsDiscovery.SportActivity]? = nil
    var expanded = false
    var onMore: () -> Void = {}
    var showsMoreLink = true
    /// The iPad Home overview has a useful bounded secondary column, not the
    /// whole window. Its tiles keep the compact three-column composition.
    var compactPresentation = false
    // Explicit for size-specific previews/tests; Catalyst can report the iPad idiom.
    var isPad = UIDevice.current.userInterfaceIdiom == .pad
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var minimumTileWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .subheadline) private var minimumTabletTileWidth: CGFloat = 142

    static func showsAllSports(expanded: Bool, regularWidth: Bool, isPad: Bool) -> Bool {
        expanded || regularWidth || isPad
    }

    var body: some View {
        let availableActivities = activities ?? discovery.activities
        let showAll = Self.showsAllSports(expanded: expanded, regularWidth: horizontalSizeClass == .regular, isPad: isPad)
        let visible = showAll ? availableActivities
            : HomeSportsDiscovery.visibleActivities(availableActivities, selectedSport: selectedSport)
        let roomyTiles = !compactPresentation && (isPad || horizontalSizeClass == .regular)
        VStack(alignment: .leading, spacing: 4) {
            SportTileGridLayout(minimumTileWidth: roomyTiles ? minimumTabletTileWidth : minimumTileWidth,
                                spacing: 8,
                                maximumColumns: typeSize.isAccessibilitySize ? 1 : (roomyTiles ? nil : 3),
                                balancesRows: roomyTiles) {
                tile(id: HomeSportsDiscovery.allSports, title: "All sports", summary: "Now & next")
                ForEach(visible) { activity in
                    tile(id: activity.id, title: AnalyticalDataEngine.categoryDisplayName(for: activity.id), summary: activity.summary(at: discovery.now))
                }
            }
            .frame(maxWidth: .infinity)
            if showsMoreLink, !showAll, availableActivities.count > visible.count {
                let hidden = availableActivities.filter { activity in !visible.contains { $0.id == activity.id } }
                let onNow = hidden.reduce(0) { $0 + $1.onNow }
                let confirmedLive = hidden.reduce(0) { $0 + $1.confirmedLive }
                let upcoming = hidden.filter { $0.nextStart != nil }.count
                Button(action: onMore) {
                    HStack(spacing: 5) {
                        Text("More sports")
                        if confirmedLive > 0 { Text("· \(confirmedLive) live") }
                        else if onNow > 0 { Text("· \(onNow) listed") }
                        else if upcoming > 0 { Text("· \(upcoming) coming up") }
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle())
                .accessibilityIdentifier("home-more-sports")
                .accessibilityHint("Shows activity and filters for every listed sport")
            }
        }
    }

    private func tile(id: String, title: String, summary: String) -> some View {
        let selected = selectedSport == id
        let isTabletLayout = !compactPresentation && (isPad || horizontalSizeClass == .regular)
        return Button { selectedSport = id } label: {
            VStack(alignment: .center, spacing: isTabletLayout ? 3 : 2) {
                SportEmblem(category: id, size: isTabletLayout ? 34 : 28, isActive: selected)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.tileForeground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-sport-color-\(id)-title")
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-sport-color-\(id)-summary")
            }
            .frame(maxWidth: .infinity, minHeight: isTabletLayout ? 80 : 70, maxHeight: .infinity, alignment: .top)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, isTabletLayout ? 9 : 2)
            .background(Self.tileBackground(selected: selected))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(selected ? FottyTheme.accentText : FottyTheme.borderStrong, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(FottyPressButtonStyle(cornerRadius: 15))
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityHint("Filters the Home lineup")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home-sport-\(id)")
    }
}

/// Compact, labeled actions; a fixture never becomes a poster-sized tap target.
struct HomeDiscoveryRow: View {
    struct Presentation: Equatable {
        let competitionLabel: String
        let statusLabel: String
        let homeScore: Int?
        let awayScore: Int?
        let liveDetail: String?
        let homeBadgeURL: URL?
        let awayBadgeURL: URL?
        let homeBrandURL: URL?
        let awayBrandURL: URL?

        @MainActor
        init(item: HomeSportsDiscovery.Item) {
            competitionLabel = item.event.sportsFixture?.competitionName ?? item.event.cplCompetitionLabel
            statusLabel = item.statusLabel
            homeScore = nil
            awayScore = nil
            liveDetail = item.hasConfirmedLiveStatus ? "LIVE" : nil
            homeBadgeURL = item.event.homeBadgeURL
            awayBadgeURL = item.event.awayBadgeURL
            homeBrandURL = TeamBrandService.shared.badgeURL(for: item.event.homeName)
            awayBrandURL = TeamBrandService.shared.badgeURL(for: item.event.awayName)
        }

        @MainActor
        init(item: HomeSportsDiscovery.Item, scoreService: LiveScoreService) {
            let match = item.sport == "football" && !item.event.hasCatalogIdentityConflict
                ? scoreService.findMatch(
                    home: item.event.homeName,
                    away: item.event.awayName,
                    near: item.event.kickoffDate
                )
                : nil
            if let fixture = item.event.sportsFixture {
                competitionLabel = fixture.competitionName
            } else if item.event.isCPLFixture || item.event.cricketFixture != nil {
                competitionLabel = item.event.cplCompetitionLabel
            } else if let match {
                competitionLabel = match.competition.audienceFacingName
            } else {
                competitionLabel = item.event.categoryDisplayName
            }
            if !WatchingSpoilerProtection.shared.protects(item.event), item.phase == .live, item.sport == "football",
               let score = scoreService.scoreForMatch(
                    home: item.event.homeName,
                    away: item.event.awayName,
                    near: item.event.kickoffDate
               ), score.status.isLive {
                let qualifier = scoreService.scoreStatusQualifier.map { " · \($0)" } ?? ""
                statusLabel = "\(score.homeGoals)–\(score.awayGoals) · \(score.minute ?? score.status.displayText)\(qualifier)"
                homeScore = score.homeGoals
                awayScore = score.awayGoals
                liveDetail = score.minute ?? score.status.displayText
            } else {
                statusLabel = item.statusLabel
                homeScore = nil
                awayScore = nil
                liveDetail = item.hasConfirmedLiveStatus ? "LIVE" : nil
            }
            // The official bootstrap binds stable badge codes to named clubs.
            // Do not let a conflicting listing/cache crest replace that artwork
            // once the same dated PL fixture has been accepted by the score lane.
            let officialArtworkMatches = !item.event.hasCatalogIdentityConflict && match.map { match in
                Self.permitsOfficialPremierLeagueArtwork(for: item.event)
                    && FootballDataPolicy.supportsLiveScores(competition: match.competition)
                    && FootballDataPolicy.normalizedTeamMatchKey(match.homeTeam.matchingName)
                        == FootballDataPolicy.normalizedTeamMatchKey(item.event.homeName)
                    && FootballDataPolicy.normalizedTeamMatchKey(match.awayTeam.matchingName)
                        == FootballDataPolicy.normalizedTeamMatchKey(item.event.awayName)
                    && item.event.kickoffDate.flatMap { kickoff in
                        match.matchDate.map { abs($0.timeIntervalSince(kickoff)) <= 15 * 60 }
                    } == true
            } == true
            homeBadgeURL = Self.preferredBadgeURL(provider: item.event.homeBadgeURL,
                matched: match?.homeTeam.crest.flatMap(URL.init(string:)), sameOfficialFixture: officialArtworkMatches)
            awayBadgeURL = Self.preferredBadgeURL(provider: item.event.awayBadgeURL,
                matched: match?.awayTeam.crest.flatMap(URL.init(string:)), sameOfficialFixture: officialArtworkMatches)
            homeBrandURL = TeamBrandService.shared.badgeURL(for: item.event.homeName)
            awayBrandURL = TeamBrandService.shared.badgeURL(for: item.event.awayName)
        }

        static func preferredBadgeURL(provider: URL?, matched: URL?, sameOfficialFixture: Bool) -> URL? {
            if FootballDataPolicy.isOfficialPremierLeagueCrestURL(matched) {
                return sameOfficialFixture ? matched : provider
            }
            return provider ?? matched
        }

        @MainActor
        static func permitsOfficialPremierLeagueArtwork(for event: EventReference) -> Bool {
            guard event.normalizedCategory == "football", !event.hasCatalogIdentityConflict,
                  CatalogPlaybackIdentity.footballSquadIdentity(for: event).isEmpty else { return false }
            if let competition = event.competitionID?.lowercased(),
               !["premier-league", "premierleague", "pl", "39", "2021"].contains(competition) { return false }
            if let fixture = event.sportsFixture {
                guard fixture.sport == "football", fixture.eventKind == .match else { return false }
            }
            return AnalyticalDataEngine.footballLeagueClassification(for: event).tab == .premierLeague
        }
    }

    let item: HomeSportsDiscovery.Item
    let presentation: Presentation
    /// Nil in production: visible controls use their own live timeline instead
    /// of the timestamp captured when the catalog projection was created.
    let now: Date?
    let isSaved: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    var alternateActionTitle: String? = nil
    var onDetails: (() -> Void)? = nil
    var onCheckStreams: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.fottyStreamLookupBusy) private var streamLookupBusy
    @State private var inlineContext = CatalogInlineContextState()

    init(
        item: HomeSportsDiscovery.Item,
        presentation: Presentation? = nil,
        now: Date? = nil,
        isSaved: Bool,
        onOpen: @escaping () -> Void,
        onSave: @escaping () -> Void,
        alternateActionTitle: String? = nil,
        onDetails: (() -> Void)? = nil,
        onCheckStreams: (() -> Void)? = nil
    ) {
        self.item = item
        self.presentation = presentation ?? Presentation(item: item)
        self.now = now
        self.isSaved = isSaved
        self.onOpen = onOpen
        self.onSave = onSave
        self.alternateActionTitle = alternateActionTitle
        self.onDetails = onDetails
        self.onCheckStreams = onCheckStreams
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        MatchStartControls(event: item.event, status: item.officialStatus, now: now, onWatch: onOpen,
            alternateActionTitle: alternateActionTitle, onCheckStreams: onCheckStreams) {
            eventInformation
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(HomeRowSecondaryActions(event: item.event, isSaved: isSaved, saveTitle: saveTitle,
                    onSave: onSave, detailsExpanded: inlineContext.isExpanded(for: item.id), onDetails: inlineDetailsAction))
        }
        if inlineContext.isExpanded(for: item.id), let onDetails {
            CatalogInlineEventContext(event: item.event, status: item.officialStatus, now: now,
                canWatchHere: true, isChannelFallback: alternateActionTitle != nil, onMoreDetails: onDetails)
        }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onChange(of: item.id) { _, _ in inlineContext.reset() }
        .contextMenu {
            if let inlineDetailsAction {
                Button(inlineContext.isExpanded(for: item.id) ? "Hide match details" : "Match details",
                       systemImage: "info.circle", action: inlineDetailsAction)
            }
            if !item.event.hasCatalogIdentityConflict {
                Button(saveTitle, systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSave)
                    .accessibilityIdentifier("home-save-\(item.id)")
            }
        }
    }

    private var saveTitle: String { isSaved ? "Remove from My Matchday" : "Save to My Matchday" }

    private var inlineDetailsAction: (() -> Void)? {
        guard onDetails != nil else { return nil }
        return { inlineContext.toggle(for: item.id) }
    }

    @ViewBuilder
    private var eventInformation: some View {
        if MatchStartPolicy(event: item.event, now: now ?? Date(), status: item.officialStatus).canAttemptPlayback
            || alternateActionTitle != nil {
            Button(action: onOpen) {
                eventText.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the broadcast. Touch and hold for match details and saving.")
            .accessibilityIdentifier(item.isOnNow ? "home-watch-now" : "home-event-\(item.id)")
            .disabled(streamLookupBusy)
        } else if let inlineDetailsAction {
            Button(action: inlineDetailsAction) {
                eventText
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle())
            .accessibilityValue(inlineContext.isExpanded(for: item.id) ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides schedule and broadcast information in this list")
            .accessibilityIdentifier("home-event-\(item.id)")
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
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .accessibilityIdentifier("dashboard-event-competition")
            if !Self.showsTeamBadges(for: item.event) {
                Label(item.event.displayTitle, systemImage: item.event.isBroadcastChannel ? "tv" : SportIdentity.symbol(for: item.sport))
                    .font(FottyTheme.typeBody.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                teamLine(name: item.event.homeName, badge: presentation.homeBadgeURL, brand: presentation.homeBrandURL)
                teamLine(name: item.event.awayName, badge: presentation.awayBadgeURL, brand: presentation.awayBrandURL)
            }
            Text(presentation.statusLabel)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(item.isOnNow ? FottyTheme.accentText : FottyTheme.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dashboard-event-status")
            if isSaved { CatalogSavedStateLabel(eventID: item.id) }
        }
        .frame(minHeight: typeSize.isAccessibilitySize ? 0 : 78, alignment: .leading)
    }

    static func showsTeamBadges(for event: AnalyticalDataEngine.EventReference) -> Bool {
        guard !event.isBroadcastChannel else { return false }
        let names = [event.homeName, event.awayName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return names.allSatisfy { !$0.isEmpty && $0 != "home" && $0 != "away" }
    }

    private func teamLine(name: String, badge: URL?, brand: URL?) -> some View {
        HStack(spacing: 8) {
            // Reuse the provider/catalog badge cache, including NBA/MLB branding.
            // Missing artwork keeps a named initials fallback, never a made-up crest.
            TeamBadgeWindow(teamName: name, badgeURL: badge, brandURL: brand,
                            brandLookupResolved: true, size: 27, glowEnabled: false,
                            showsFrame: false)
                .accessibilityHidden(true)
            Text(MatchCardFormatting.denseTeamName(name))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dashboard-team-name")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityIdentifier("dashboard-team-name")
    }

    private var competitionLabel: String {
        presentation.competitionLabel
    }
}

/// The single leading live event on Home. This is deliberately information-led
/// rather than poster artwork: real badges, verified score/status when present,
/// and one explicit playback action. Its football stadium is decoration, never
/// a live broadcast frame or evidence that a match is being shown.
struct HomeLiveSpotlight: View {
    let item: HomeSportsDiscovery.Item
    let presentation: HomeDiscoveryRow.Presentation
    let now: Date?
    let isSaved: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    var alternateActionTitle: String? = nil
    var onDetails: (() -> Void)? = nil
    var onCheckStreams: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fottyPendingWatchEventID) private var pendingWatchEventID
    private var openingWatch: Bool { pendingWatchEventID == item.event.id }
    @Environment(\.fottyStreamLookupBusy) private var streamLookupBusy
    @State private var feedback = MatchPlaybackFeedback.shared
    @ScaledMetric(relativeTo: .title3) private var scoreSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text(liveLabel)
                        .accessibilityIdentifier("home-live-heading")
                } icon: {
                    // Status words carry the meaning. The matching symbol is
                    // decorative, not a second VoiceOver stop for “Tv”.
                    Image(systemName: item.cricketActivity?.symbol ?? (item.hasConfirmedLiveStatus ? "circle.fill" : "tv"))
                        .accessibilityHidden(true)
                }
                    .accessibilityElement(children: .contain)
                    .font(.fottyScaled(size: 12, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(item.hasConfirmedLiveStatus ? FottyTheme.error : FottyTheme.textPrimary)
                Spacer(minLength: 8)
                Text(presentation.competitionLabel)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.trailing)
            }

            if let fixture = item.event.sportsFixture, fixture.eventKind != .match {
                Label(item.event.displayTitle, systemImage: SportIdentity.symbol(for: item.sport))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    team(name: item.event.homeName, badge: presentation.homeBadgeURL,
                         brand: presentation.homeBrandURL)
                    scoreLockup
                    team(name: item.event.awayName, badge: presentation.awayBadgeURL,
                         brand: presentation.awayBrandURL)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    team(name: item.event.homeName, badge: presentation.homeBadgeURL,
                         brand: presentation.homeBrandURL)
                        .frame(maxWidth: .infinity)
                    scoreLockup
                        .frame(minWidth: 74)
                    team(name: item.event.awayName, badge: presentation.awayBadgeURL,
                         brand: presentation.awayBrandURL)
                        .frame(maxWidth: .infinity)
                }
            }

            Divider().overlay(FottyTheme.border)

            if typeSize.isAccessibilitySize {
                stackedFooter
            } else {
                // Measure the actual ideal groups before choosing a row. Saved
                // and time must not squeeze Watch into an unreadable capsule.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        footerInformation.fixedSize(horizontal: true, vertical: true)
                        Spacer(minLength: 8)
                        footerActions.fixedSize(horizontal: true, vertical: true)
                    }
                    stackedFooter
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            spotlightBackground
        }
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusXL, style: .continuous)
                .strokeBorder(FottyTheme.borderStrong, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusXL, style: .continuous))
        .contextMenu {
            Button(saveTitle, systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSave)
                .accessibilityIdentifier("home-save-\(item.id)")
        }
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier(item.isOnNow ? "home-watch-now" : "home-event-\(item.id)")
    }

    private var footerInformation: some View {
        VStack(alignment: .leading, spacing: 3) {
            if isSaved { CatalogSavedStateLabel(eventID: item.id) }
            if let footerStatus {
                Text(footerStatus)
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-live-footer-status")
            }
        }
    }

    private var stackedFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            footerInformation
            footerActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                footerMenu.fixedSize(horizontal: true, vertical: true)
                footerWatchButton.fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                footerMenu
                footerWatchButton
            }
        }
    }

    @ViewBuilder
    private var footerMenu: some View {
        if !item.event.hasCatalogIdentityConflict || onDetails != nil {
            CatalogMatchActionsMenu(eventID: item.id, eventTitle: item.event.displayTitle,
                                    isSaved: isSaved, canSave: !item.event.hasCatalogIdentityConflict,
                                    onSave: onSave, onDetails: onDetails)
        }
    }

    @ViewBuilder
    private var footerWatchButton: some View {
        if canAttemptPlayback {
            Button(action: openIfStillEligible) {
                PendingWatchLabel(title: actionTitle, symbol: isRetry ? "arrow.clockwise" : "play.fill", isPending: openingWatch)
                .font(FottyTheme.typeAction)
                .foregroundStyle(FottyTheme.textOnAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(FottyTheme.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .disabled(streamLookupBusy)
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
            .accessibilityLabel("\(actionTitle) \(item.event.displayTitle)")
            .accessibilityValue(openingWatch ? "Opening broadcast" : "")
            .accessibilityHint("Finds an available broadcast and opens the player.")
            .accessibilityIdentifier("match-start-play-\(item.id)")
        } else if onCheckStreams != nil,
                  let lookup = FixtureSourceLookupPresentation.state(for: item.event,
                    at: HomeSportsDiscovery.automatedClockDate ?? Date(), status: item.officialStatus) {
            if lookup.canTriggerLookup {
                Button {
                    guard FixtureSourceLookupPresentation.state(for: item.event,
                        at: HomeSportsDiscovery.automatedClockDate ?? Date(),
                        status: item.officialStatus)?.canTriggerLookup == true else { return }
                    onCheckStreams?()
                } label: {
                    PendingWatchLabel(title: lookup.title, symbol: lookup.symbol, isPending: openingWatch)
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(FottyTheme.accent, in: Capsule())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
                .disabled(streamLookupBusy)
                .accessibilityLabel(lookup.accessibilityLabel(matchTitle: item.event.displayTitle))
                .accessibilityValue(openingWatch ? "Opening broadcast" : "")
                .accessibilityHint(lookup.accessibilityHint)
                .accessibilityIdentifier("match-start-check-streams-\(item.id)")
            } else {
                HStack(spacing: 6) {
                    if lookup.isChecking { ProgressView().controlSize(.small) }
                    Text(lookup.statusTitle).fixedSize(horizontal: false, vertical: true)
                }
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lookup.accessibilityLabel(matchTitle: item.event.displayTitle))
                .accessibilityHint(lookup.accessibilityHint)
                .accessibilityIdentifier("match-start-source-status-\(item.id)")
            }
        }
    }

    @ViewBuilder
    private var spotlightBackground: some View {
        if item.sport == "football", !reduceTransparency {
            // The existing named asset is bundled and cached by the platform.
            // Measure only this decoration; it does not propose a new card size
            // or publish geometry while Home scrolls.
            GeometryReader { geometry in
                ZStack {
                    FottyTheme.surface
                    Image("stadium_football")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .saturation(0.28)
                        .opacity(0.55)
                    LinearGradient(
                        colors: [FottyTheme.surface.opacity(0.32), FottyTheme.surface.opacity(0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusXL, style: .continuous))
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: FottyTheme.radiusXL, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(FottyTheme.surface) : AnyShapeStyle(.regularMaterial))
                .overlay {
                    LinearGradient(
                        colors: [FottyTheme.accent.opacity(0.09), .clear],
                        startPoint: .topTrailing,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusXL, style: .continuous))
                }
        }
    }

    private var currentPolicy: MatchStartPolicy {
        MatchStartPolicy(event: item.event, now: now ?? Date(), status: item.officialStatus)
    }

    private var canAttemptPlayback: Bool {
        (currentPolicy.canAttemptPlayback || (alternateActionTitle != nil && currentPolicy.timingAllowsPlayback))
    }

    private var isRetry: Bool {
        feedback.notReadyIDs.contains(item.id) && currentPolicy.canAttemptPlayback
    }

    private var actionTitle: String {
        alternateActionTitle ?? (isRetry ? "Retry" : "Watch")
    }

    private var liveLabel: String {
        let prefix = item.prominentStatusLabel
        guard item.hasConfirmedLiveStatus, let detail = presentation.liveDetail,
              detail.localizedCaseInsensitiveCompare("LIVE") != .orderedSame else { return prefix }
        return "\(prefix) · \(detail)"
    }

    private var footerStatus: String? {
        if presentation.homeScore != nil, presentation.awayScore != nil {
            return item.event.kickoffDate?.arenaKickoffDetailLine() ?? item.event.categoryDisplayName
        }
        // The live heading and score lockup already expose the live state.
        // Keep this footer for additional information, not a third copy.
        if presentation.statusLabel.localizedCaseInsensitiveCompare(item.prominentStatusLabel) == .orderedSame { return nil }
        return item.hasConfirmedLiveStatus ? nil : presentation.statusLabel
    }

    private var scoreLockup: some View {
        VStack(spacing: 3) {
            if let home = presentation.homeScore, let away = presentation.awayScore {
                Text("\(home) – \(away)")
                    .font(.system(size: scoreSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FottyTheme.textPrimary)
            } else {
                Text("VS")
                    .font(.fottyScaled(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            if let detail = presentation.liveDetail {
                Text(detail)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func team(name: String, badge: URL?, brand: URL?) -> some View {
        VStack(spacing: 6) {
            TeamBadgeWindow(
                teamName: name,
                badgeURL: badge,
                brandURL: brand,
                brandLookupResolved: true,
                size: badgeSize,
                glowEnabled: false,
                showsFrame: false
            )
            Text(MatchCardFormatting.denseTeamName(name))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    private func openIfStillEligible() {
        let policy = MatchStartPolicy(event: item.event, status: item.officialStatus)
        guard policy.canAttemptPlayback || (alternateActionTitle != nil && policy.timingAllowsPlayback) else { return }
        onOpen()
    }

    private var saveTitle: String { isSaved ? "Remove from My Matchday" : "Save to My Matchday" }
}

/// Transparent, compact schedule row used by Up Next and later groups. It keeps
/// the same MatchStartControls owner for watch/reminder policy while replacing
/// the old two-line card treatment with paired team identity.
struct HomeScheduleRow: View {
    let item: HomeSportsDiscovery.Item
    let presentation: HomeDiscoveryRow.Presentation
    let now: Date?
    let isSaved: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    var alternateActionTitle: String? = nil
    var onDetails: (() -> Void)? = nil
    var onCheckStreams: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.fottyStreamLookupBusy) private var streamLookupBusy
    // Paired badges and the options menu must leave enough room for both team
    // names. Narrow windows put Watch below instead of squeezing the names.
    @ScaledMetric(relativeTo: .subheadline) private var minimumInformationWidth: CGFloat = 300
    @State private var inlineContext = CatalogInlineContextState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        MatchStartControls(
            event: item.event,
            status: item.officialStatus,
            now: now,
            onWatch: onOpen,
            alternateActionTitle: alternateActionTitle,
            onCheckStreams: onCheckStreams,
            compact: true,
            minimumInformationWidth: minimumInformationWidth,
            rowActions: Optional<CatalogMatchActionsMenu>.none
        ) {
            eventInformation
                .modifier(HomeRowSecondaryActions(event: item.event, isSaved: isSaved, saveTitle: saveTitle,
                    onSave: onSave, detailsExpanded: inlineContext.isExpanded(for: item.id), onDetails: inlineDetailsAction))
        }
        if inlineContext.isExpanded(for: item.id), let onDetails {
            CatalogInlineEventContext(event: item.event, status: item.officialStatus, now: now,
                canWatchHere: true, isChannelFallback: alternateActionTitle != nil, onMoreDetails: onDetails)
        }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onChange(of: item.id) { _, _ in inlineContext.reset() }
        .contextMenu {
            if let inlineDetailsAction {
                Button(inlineContext.isExpanded(for: item.id) ? "Hide match details" : "Match details",
                       systemImage: "info.circle", action: inlineDetailsAction)
            }
            if !item.event.hasCatalogIdentityConflict {
                Button(saveTitle, systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onSave)
                    .accessibilityIdentifier("home-save-\(item.id)")
            }
        }
    }

    private var inlineDetailsAction: (() -> Void)? {
        guard onDetails != nil else { return nil }
        return { inlineContext.toggle(for: item.id) }
    }

    @ViewBuilder
    private var eventInformation: some View {
        if currentPolicy.canAttemptPlayback || alternateActionTitle != nil {
            Button(action: onOpen) { compactInformation }
                .buttonStyle(FottyPressButtonStyle())
                .disabled(streamLookupBusy)
                .accessibilityHint("Opens the broadcast. Touch and hold for match details and saving.")
                .accessibilityIdentifier(item.isOnNow ? "home-watch-now" : "home-event-\(item.id)")
        } else if let inlineDetailsAction {
            Button(action: inlineDetailsAction) {
                compactInformation
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle())
            .accessibilityValue(inlineContext.isExpanded(for: item.id) ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides schedule and broadcast information in this list")
            .accessibilityIdentifier("home-event-\(item.id)")
        } else {
            compactInformation
                .accessibilityHint("Long-press to save to My Matchday.")
                .accessibilityIdentifier("home-event-\(item.id)")
        }
    }

    private var compactInformation: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            identityArtwork
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                matchIdentity
                // Future countdowns belong below the names; current rows must
                // still retain their score/confirmed-vs-listed qualifier.
                Text(competitionAndStatus)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(item.hasConfirmedLiveStatus ? FottyTheme.error : FottyTheme.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if isSaved { CatalogSavedStateLabel(eventID: item.id) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var matchIdentity: some View {
        if HomeDiscoveryRow.showsTeamBadges(for: item.event) {
            ViewThatFits(in: .horizontal) {
                Text("\(MatchCardFormatting.denseTeamName(item.event.homeName)) · \(MatchCardFormatting.denseTeamName(item.event.awayName))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: true, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    teamName(item.event.homeName)
                    teamName(item.event.awayName)
                }
            }
        } else {
            Text(item.event.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func teamName(_ name: String) -> some View {
        Text(MatchCardFormatting.denseTeamName(name))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FottyTheme.textPrimary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var competitionAndStatus: String {
        if item.isOnNow {
            let status = item.hasConfirmedLiveStatus ? presentation.statusLabel : item.prominentStatusLabel
            return "\(presentation.competitionLabel) · \(status)"
        }
        // During the two-minute Watch window the button replaces the countdown,
        // so retain its exact scheduled start as secondary information.
        if currentPolicy.canAttemptPlayback || alternateActionTitle != nil {
            return "\(presentation.competitionLabel) · \(presentation.statusLabel)"
        }
        return presentation.competitionLabel
    }

    @ViewBuilder
    private var identityArtwork: some View {
        if HomeDiscoveryRow.showsTeamBadges(for: item.event) {
            HStack(spacing: 2) {
                pairedBadge(name: item.event.homeName, badge: presentation.homeBadgeURL,
                            brand: presentation.homeBrandURL)
                pairedBadge(name: item.event.awayName, badge: presentation.awayBadgeURL,
                            brand: presentation.awayBrandURL)
            }
        } else {
            SportEmblem(category: item.sport, size: 30)
        }
    }

    private func pairedBadge(name: String, badge: URL?, brand: URL?) -> some View {
        TeamBadgeWindow(
            teamName: name,
            badgeURL: badge,
            brandURL: brand,
            brandLookupResolved: true,
            size: 30,
            glowEnabled: false,
            showsFrame: false
        )
        .accessibilityHidden(true)
    }

    private var currentPolicy: MatchStartPolicy {
        MatchStartPolicy(event: item.event, now: now ?? Date(), status: item.officialStatus)
    }

    private var saveTitle: String { isSaved ? "Remove from My Matchday" : "Save to My Matchday" }
}

/// Home's "On air now": channels that open right now, each with its own
/// Watch. Tapping Watch shows "Opening…" at once, like the TV tab.
struct HomeOnAirSection: View {
    let entries: [HomeOnAirPolicy.Entry]
    let columns: Int
    let pendingEventID: String?
    let onWatch: (EventReference) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let count = typeSize.isAccessibilitySize ? 1 : max(1, min(columns, entries.count))
        VStack(alignment: .leading, spacing: 8) {
            Text("On air now")
                .font(FottyTheme.typeSectionTitle)
                .foregroundStyle(FottyTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home-on-air-heading")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count),
                      alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in card(entry) }
            }
        }
        .accessibilityIdentifier("home-on-air")
    }

    private func card(_ entry: HomeOnAirPolicy.Entry) -> some View {
        let event = entry.station.event
        let opening = pendingEventID == event.id
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.station.title)
                    .font(.headline)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // Only a programme the guide currently confirms is named.
                if let line = entry.programme.map({ "Now · \($0)" })
                    ?? (entry.station.language == .any ? nil : entry.station.language.title) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(entry.programme == nil ? FottyTheme.textSecondary : FottyTheme.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { onWatch(event) } label: {
                Label {
                    Text(opening ? "Opening…" : "Watch")
                } icon: {
                    if opening { ProgressView().controlSize(.small).tint(FottyTheme.textOnAccent) }
                    else { Image(systemName: "play.fill") }
                }
                .font(FottyTheme.typeAction)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(FottyTheme.accent)
            .foregroundStyle(FottyTheme.textOnAccent)
            .disabled(pendingEventID != nil)
            .accessibilityLabel("Watch \(entry.station.title)")
            .accessibilityValue(opening ? "Opening broadcast" : (entry.programme ?? ""))
            .accessibilityIdentifier("home-on-air-watch-\(entry.station.id)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surface, in: .rect(cornerRadius: FottyTheme.radiusLG))
    }
}


/// Home rows show one visible action. Details and Save stay reachable through
/// the row's long-press menu and these VoiceOver actions.
private struct HomeRowSecondaryActions: ViewModifier {
    let event: EventReference
    let isSaved: Bool
    let saveTitle: String
    let onSave: () -> Void
    let detailsExpanded: Bool
    let onDetails: (() -> Void)?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let onDetails {
                Button(detailsExpanded ? "Hide match details" : "Match details", action: onDetails)
            }
            if !event.hasCatalogIdentityConflict {
                Button(saveTitle, action: onSave)
            }
        }
    }
}
