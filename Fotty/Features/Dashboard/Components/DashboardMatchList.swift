import SwiftUI

struct DashboardMatchList: View {
    let title: String
    let events: [AnalyticalDataEngine.EventReference]
    @Binding var showFollowedOnly: Bool
    let hasFollowedTeams: Bool

    let isMultiSelectMode: Bool
    @Binding var selectedMultiEventIDs: Set<String>

    let onEventTap: (AnalyticalDataEngine.EventReference) -> Void
    let onInfoTap: (FootballMatch) -> Void
    let onAppearEvent: (AnalyticalDataEngine.EventReference) -> Void
    let canWatchEvent: (AnalyticalDataEngine.EventReference) -> Bool
    var isSavedEvent: (AnalyticalDataEngine.EventReference) -> Bool = { _ in false }
    var onToggleSaved: (AnalyticalDataEngine.EventReference) -> Void = { _ in }
    /// When false, force a single column (iPad bento left stack is too narrow for 2-up).
    var usesMultiColumnGrid: Bool = UIDevice.current.userInterfaceIdiom == .pad

    @Environment(LiveScoreService.self) private var scoreService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isMultiSelectMode {
                HStack(spacing: 8) {
                    Image(systemName: "square.split.2x1")
                        .font(.fottyScaled(size: 12, weight: .semibold))
                        .foregroundStyle(FottyTheme.accentText)

                    Text("Select 2 matches (\(selectedMultiEventIDs.count)/2)")
                        .font(.fottyScaled(size: 13, weight: .semibold))
                        .foregroundStyle(FottyTheme.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: FottyTheme.radiusSM)
                        .fill(FottyTheme.surface)
                )
            }

            HStack(alignment: .center, spacing: 8) {
                FottySectionHeader(title: title, count: events.count)
                if hasFollowedTeams {
                    Button {
                        withAnimation(FottyTheme.springSnappy) {
                            showFollowedOnly.toggle()
                        }
                    } label: {
                        Text(showFollowedOnly ? "Following" : "All")
                            .font(FottyTheme.typeMeta)
                            .foregroundStyle(showFollowedOnly ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(showFollowedOnly ? FottyTheme.accent : FottyTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if shouldGroupByDate {
                groupedMatchList
            } else {
                legacyFlatList
            }
        }
    }

    private var shouldGroupByDate: Bool {
        events.count >= 2
    }

    struct CompetitionGroup {
        let name: String
        let iconUrl: URL?
        let category: String
        let events: [AnalyticalDataEngine.EventReference]
    }

    private func groupEventsByCompetition(_ events: [AnalyticalDataEngine.EventReference]) -> [CompetitionGroup] {
        var groups: [String: [AnalyticalDataEngine.EventReference]] = [:]
        var order: [String] = []

        for event in events {
            let matchedFootball = scoreService.findMatch(home: event.homeName, away: event.awayName)
            let compName = matchedFootball?.competition.audienceFacingName ?? event.categoryDisplayName

            if groups[compName] == nil {
                order.append(compName)
                groups[compName] = []
            }
            groups[compName]?.append(event)
        }

        return order.map { name in
            let eventsInGroup = groups[name] ?? []
            let matchedFootball = eventsInGroup.first.flatMap {
                scoreService.findMatch(home: $0.homeName, away: $0.awayName)
            }
            return CompetitionGroup(
                name: name,
                iconUrl: matchedFootball?.competition.emblemURL,
                category: eventsInGroup.first?.normalizedCategory ?? "football",
                events: eventsInGroup
            )
        }
    }

    private func competitionHeaderView(name: String, iconUrl: URL?, category: String) -> some View {
        HStack(spacing: 6) {
            if let iconUrl {
                CachedAsyncImage(url: iconUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "shield.fill")
                        .foregroundColor(FottyTheme.accentText)
                }
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            } else {
                Image(systemName: AnalyticalDataEngine.sportIconName(for: category))
                    .font(.fottyScaled(size: 10, weight: .bold))
                    .foregroundColor(FottyTheme.accentText)
                    .accessibilityHidden(true)
            }

            Text(name.uppercased())
                .font(.fottyScaled(size: 12, weight: .bold))
                .foregroundStyle(FottyTheme.textPrimary)
                .tracking(0.5)

            Spacer()
        }
        .padding(.top, 2)
    }

    private var padColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var groupedMatchList: some View {
        let sections = FixtureDateGrouper.sections(from: events)
        return LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title.uppercased())
                        .font(.fottyScaled(size: 12, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .tracking(1.2)

                    ForEach(groupEventsByCompetition(section.events), id: \.name) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            competitionHeaderView(
                                name: group.name,
                                iconUrl: group.iconUrl,
                                category: group.category
                            )

                            eventGrid(for: group.events)
                        }
                    }
                }
            }
        }
    }

    private var legacyFlatList: some View {
        let compGroups = groupEventsByCompetition(events)
        return LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(compGroups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 4) {
                    competitionHeaderView(
                        name: group.name,
                        iconUrl: group.iconUrl,
                        category: group.category
                    )
                    eventGrid(for: group.events)
                }
            }
        }
    }

    private struct EventGridPair: Identifiable {
        let id: String
        let events: [AnalyticalDataEngine.EventReference]
    }

    @ViewBuilder
    private func eventGrid(for events: [AnalyticalDataEngine.EventReference]) -> some View {
        if usesMultiColumnGrid {
            let pairs = stride(from: 0, to: events.count, by: 2).map { index -> EventGridPair in
                let sub = Array(events[index..<min(index + 2, events.count)])
                let compositeID = sub.map(\.id).joined(separator: "_")
                return EventGridPair(id: compositeID, events: sub)
            }
            ForEach(pairs) { pair in
                HStack(spacing: 8) {
                    ForEach(pair.events) { event in
                        eventRow(event)
                            .frame(maxWidth: .infinity)
                    }
                    if pair.events.count == 1 {
                        Spacer()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            ForEach(events) { event in
                eventRow(event)
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: AnalyticalDataEngine.EventReference) -> some View {
        ZStack(alignment: .bottomTrailing) {
            LiveEventCard(
                event: event,
                onInfoTap: onInfoTap,
                onWatchTap: !isMultiSelectMode && canWatchEvent(event)
                    ? { onEventTap(event) }
                    : nil,
                onDetailsTap: !isMultiSelectMode && !canWatchEvent(event)
                    ? { onEventTap(event) }
                    : nil,
                isSaved: isSavedEvent(event),
                onSaveTap: !isMultiSelectMode ? { onToggleSaved(event) } : nil
            )
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
            .onTapGesture {
                if isMultiSelectMode { onEventTap(event) }
            }
            .accessibilityHint(
                isMultiSelectMode
                    ? "Selects this match"
                    : (canWatchEvent(event) ? "Opens the available broadcast" : "Opens match information")
            )
            .onAppear { onAppearEvent(event) }

            if isMultiSelectMode {
                multiSelectBadge(for: event)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private func multiSelectBadge(for event: AnalyticalDataEngine.EventReference) -> some View {
        let isSelected = selectedMultiEventIDs.contains(event.id)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.fottyScaled(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? FottyTheme.accent : .white.opacity(0.8))
            .padding(3)
            .background(Circle().fill(.black.opacity(0.45)))
    }
}
