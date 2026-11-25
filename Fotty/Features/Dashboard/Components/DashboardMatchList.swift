import SwiftUI

enum TwoMatchSelectionPolicy {
    static let limit = 2

    /// A lazy collection's prefix/count can revisit its predicate. Eligibility
    /// includes clock and score checks, so evaluate each row at most once.
    static func hasTwoCandidates<Events: Sequence>(
        in events: Events,
        where isCandidate: (Events.Element) -> Bool
    ) -> Bool {
        var count = 0
        for event in events where isCandidate(event) {
            count += 1
            if count == limit { return true }
        }
        return false
    }

    static func toggled(_ selectedIDs: [String], eventID: String) -> [String] {
        if selectedIDs.contains(eventID) {
            return selectedIDs.filter { $0 != eventID }
        }
        guard selectedIDs.count < limit else { return selectedIDs }
        return selectedIDs + [eventID]
    }

    static func position(of eventID: String, in selectedIDs: [String]) -> Int? {
        selectedIDs.firstIndex(of: eventID).map { $0 + 1 }
    }
}

struct DashboardMatchList: View {
    let title: String
    let events: [AnalyticalDataEngine.EventReference]
    @Binding var showFollowedOnly: Bool
    let hasFollowedTeams: Bool

    let isMultiSelectMode: Bool
    @Binding var selectedMultiEventIDs: [String]

    let onEventTap: (AnalyticalDataEngine.EventReference) -> Void
    let onInfoTap: (FootballMatch) -> Void
    let onAppearEvent: (AnalyticalDataEngine.EventReference) -> Void
    let canWatchEvent: (AnalyticalDataEngine.EventReference) -> Bool
    var alternateActionTitle: (AnalyticalDataEngine.EventReference) -> String? = { _ in nil }
    var isSavedEvent: (AnalyticalDataEngine.EventReference) -> Bool = { _ in false }
    var onToggleSaved: (AnalyticalDataEngine.EventReference) -> Void = { _ in }
    /// When false, force a single column (iPad bento left stack is too narrow for 2-up).
    var usesMultiColumnGrid: Bool = UIDevice.current.userInterfaceIdiom == .pad

    @Environment(LiveScoreService.self) private var scoreService
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.fottyStreamLookupBusy) private var streamLookupBusy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                FottySectionHeader(title: title, count: events.count)
                if hasFollowedTeams && !isMultiSelectMode {
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
                            .frame(minWidth: 44, minHeight: 44)
                            .background(showFollowedOnly ? FottyTheme.accent : FottyTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM, style: .continuous))
                    }
                    .buttonStyle(FottyPressButtonStyle())
                    .accessibilityLabel("Following filter")
                    .accessibilityValue(showFollowedOnly ? "Following only" : "All matches")
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
        if usesMultiColumnGrid && !typeSize.isAccessibilitySize {
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
        Group {
            if isMultiSelectMode {
                Button { onEventTap(event) } label: {
                    ZStack(alignment: .topTrailing) {
                        // Selection mode has one action. Do not nest the card's
                        // Details or Watch controls inside this button.
                        LiveEventCard(event: event)
                            .overlay {
                                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                                    .strokeBorder(
                                        selectedMultiEventIDs.contains(event.id)
                                            ? FottyTheme.accentText : FottyTheme.border,
                                        lineWidth: selectedMultiEventIDs.contains(event.id) ? 2 : 1
                                    )
                            }
                        multiSelectBadge(for: event)
                            .padding(8)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusMD))
                .disabled(streamLookupBusy)
                .accessibilityRepresentation {
                    // The visual card's countdown/Watch metadata must not
                    // override this mode's single selection action.
                    Button { onEventTap(event) } label: {
                        Text(event.title ?? "\(event.homeName) versus \(event.awayName)")
                    }
                    .disabled(streamLookupBusy)
                    .accessibilityValue(selectionAccessibilityValue(for: event))
                    .accessibilityAddTraits(selectedMultiEventIDs.contains(event.id) ? .isSelected : [])
                    .accessibilityHint("Selects or removes this match from the two-match view")
                    .accessibilityIdentifier("multiview-candidate-\(event.id)")
                }
            } else {
                LiveEventCard(
                    event: event,
                    onInfoTap: onInfoTap,
                    onWatchTap: canWatchEvent(event) ? { onEventTap(event) } : nil,
                    alternateActionTitle: alternateActionTitle(event),
                    onDetailsTap: !canWatchEvent(event) ? { onEventTap(event) } : nil,
                    isSaved: isSavedEvent(event),
                    onSaveTap: { onToggleSaved(event) }
                )
                .accessibilityHint(canWatchEvent(event) ? "Opens the available broadcast" : "Opens match information")
            }
        }
        .onAppear { onAppearEvent(event) }
    }

    @ViewBuilder
    private func multiSelectBadge(for event: AnalyticalDataEngine.EventReference) -> some View {
        if let position = TwoMatchSelectionPolicy.position(of: event.id, in: selectedMultiEventIDs) {
            Text("\(position)")
                .font(.fottyScaled(size: 13, weight: .bold))
                .foregroundStyle(FottyTheme.textOnAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(FottyTheme.accent))
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "plus")
                .font(.fottyScaled(size: 12, weight: .bold))
                .foregroundStyle(FottyTheme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(FottyTheme.surfaceElevated))
                .overlay(Circle().strokeBorder(FottyTheme.borderStrong, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    private func selectionAccessibilityValue(for event: AnalyticalDataEngine.EventReference) -> String {
        guard let position = TwoMatchSelectionPolicy.position(of: event.id, in: selectedMultiEventIDs) else {
            return "Not selected"
        }
        return position == 1 ? "Selected first" : "Selected second"
    }
}
