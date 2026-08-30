import Foundation

/// A presentation-only projection of the shared catalog. No fetching, stream
/// probing, or changes to persisted fixture/provider identities happen here.
@MainActor
struct HomeSportsDiscovery {
    static let allSports = "all-sports"
    private static let sportOrder = ["football", "basketball", "cricket", "baseball", "tennis", "hockey", "fight", "american-football"]

    @MainActor
    struct Item: Identifiable {
        enum Phase { case live, listedNow, upcoming, unconfirmed }
        let event: AnalyticalDataEngine.EventReference
        let phase: Phase
        let officialStatus: FootballMatch.MatchStatus?
        var now = Date()
        nonisolated var id: String { event.id }
        var sport: String { event.normalizedCategory }
        var canWatch: Bool { StreamPluginProviderMatching.hasActiveCatalogSource(event) }
        var isOnNow: Bool { phase == .live || phase == .listedNow }
        var actionTitle: String { MatchStartPolicy(event: event, now: now, status: officialStatus).title }

        var statusLabel: String {
            switch phase {
            case .live: return canWatch ? "Live" : "In play"
            case .listedNow: return "On now · listed start"
            case .upcoming: return event.kickoffDate?.arenaKickoffDetailLine() ?? "Time TBC"
            case .unconfirmed:
                if let officialStatus, !officialStatus.isUpcoming { return officialStatus.displayText }
                return event.kickoffDate == nil ? "Time TBC" : "Start unconfirmed"
            }
        }
    }

    @MainActor
    struct SportActivity: Identifiable {
        let id: String
        let onNow: Int
        let nextStart: Date?
        let channels: Int
        let unconfirmed: Int

        func summary(at now: Date, calendar: Calendar = .current) -> String {
            if onNow > 0 { return "\(onNow) on now" }
            if let nextStart {
                if calendar.isDate(nextStart, inSameDayAs: now) {
                    return nextStart.formatted(date: .omitted, time: .shortened)
                }
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                   calendar.isDate(nextStart, inSameDayAs: tomorrow) { return "Tomorrow" }
                return nextStart.formatted(.dateTime.month(.abbreviated).day())
            }
            if channels > 0 { return channels == 1 ? "1 channel" : "\(channels) channels" }
            return unconfirmed > 0 ? "Time TBC" : "Nothing listed"
        }
    }

    let now: Date
    let items: [Item]
    let channels: [AnalyticalDataEngine.EventReference]
    let activities: [SportActivity]

    init(
        events: [AnalyticalDataEngine.EventReference],
        now: Date = Date(),
        status: (AnalyticalDataEngine.EventReference) -> FootballMatch.MatchStatus? = { _ in nil }
    ) {
        self.now = now
        let unique = Self.uniqueEvents(events)
        let channelEvents = unique.filter(\.isBroadcastChannel)
        let eventItems: [Item] = unique.compactMap { event in
            guard !event.isBroadcastChannel else { return nil }
            let official = status(event)
            guard official?.isFinished != true, official != .cancelled else { return nil }
            let phase: Item.Phase
            if official?.isLive == true {
                phase = .live
            } else if let official, !official.isUpcoming {
                phase = .unconfirmed
            } else if let kickoff = event.kickoffDate, kickoff > now {
                phase = .upcoming
            } else {
                // Remove elapsed discovery windows without inventing results.
                if event.isPastEstimatedMatchWindow(at: now) { return nil }
                phase = official == nil
                    && StreamPluginProviderMatching.hasActiveCatalogSource(event)
                    && event.broadcastTiming(at: now) == .live ? .listedNow : .unconfirmed
            }
            return Item(event: event, phase: phase, officialStatus: official, now: now)
        }.sorted(by: Self.precedes)

        channels = channelEvents
        items = eventItems
        let categories = Set(unique.map(\.normalizedCategory)).union(["football"])
        activities = categories.map { category in
            let matches = eventItems.filter { $0.sport == category }
            return SportActivity(
                id: category,
                onNow: matches.filter(\.isOnNow).count,
                nextStart: matches.first { $0.phase == .upcoming }?.event.kickoffDate,
                channels: channelEvents.filter { $0.normalizedCategory == category }.count,
                unconfirmed: matches.filter { $0.phase == .unconfirmed }.count
            )
        }.sorted { lhs, rhs in
            // Fixed ties keep categories stable across provider order changes.
            func rank(_ activity: SportActivity) -> Int {
                if activity.onNow > 0 { return 0 }
                if let next = activity.nextStart, next <= now.addingTimeInterval(6 * 3600) { return 1 }
                if activity.channels > 0 { return 2 }
                if activity.nextStart != nil { return 3 }
                return 4
            }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            let order = Self.sportOrder
            let l = order.firstIndex(of: lhs.id) ?? order.count
            let r = order.firstIndex(of: rhs.id) ?? order.count
            return l == r ? lhs.id < rhs.id : l < r
        }
    }

    func scopedItems(sport: String) -> [Item] {
        sport == Self.allSports ? items : items.filter { $0.sport == sport }
    }

    /// A stopped or failed score poller must not keep promoting old in-play
    /// state on another sport's activity selector. Final/suspended schedule
    /// facts remain useful; stale live state falls back to labeled catalog time.
    static func recentStatus(
        _ status: FootballMatch.MatchStatus,
        refreshedAt: Date?,
        liveFeedAvailable: Bool,
        now: Date
    ) -> FootballMatch.MatchStatus? {
        guard status.isLive else { return status }
        guard liveFeedAvailable, let refreshedAt,
              (0...600).contains(now.timeIntervalSince(refreshedAt)) else { return nil }
        return status
    }

    /// At most three timely events; one per active sport before a second from
    /// the same sport. Distant fixtures and unknown timings live in the lineup.
    func featured(from items: [Item], diverse: Bool) -> [Item] {
        let eligible = items.filter {
            $0.isOnNow || ($0.phase == .upcoming && ($0.event.kickoffDate ?? .distantFuture) <= now.addingTimeInterval(6 * 3600))
        }
        guard diverse else { return Array(eligible.prefix(3)) }
        var sports = Set<String>()
        let representatives = eligible.filter { sports.insert($0.sport).inserted }.sorted { lhs, rhs in
            if lhs.isOnNow != rhs.isOnNow { return lhs.isOnNow }
            let l = Self.sportOrder.firstIndex(of: lhs.sport) ?? Self.sportOrder.count
            let r = Self.sportOrder.firstIndex(of: rhs.sport) ?? Self.sportOrder.count
            return l == r ? Self.precedes(lhs, rhs) : l < r
        }
        let first = Array(representatives.prefix(3))
        let ids = Set(first.map(\.id))
        return first + eligible.filter { !ids.contains($0.id) }.prefix(3 - first.count)
    }

    func later(from items: [Item], excluding featured: [Item], calendar: Calendar = .current) -> (title: String, items: [Item]) {
        let excluded = Set(featured.map(\.id))
        let future = items.filter { $0.phase == .upcoming && !excluded.contains($0.id) }
        let today = future.filter { item in
            item.event.kickoffDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        }
        return today.isEmpty ? ("Coming up", Array(future.prefix(2))) : ("Later today", Array(today.prefix(2)))
    }

    func visibleActivities(selectedSport: String) -> [SportActivity] {
        var visible = Array(activities.prefix(5))
        if selectedSport != Self.allSports, !visible.contains(where: { $0.id == selectedSport }),
           let selected = activities.first(where: { $0.id == selectedSport }) {
            if visible.count == 5 { visible.removeLast() }
            visible.append(selected)
        }
        return visible
    }

    private static func precedes(_ lhs: Item, _ rhs: Item) -> Bool {
        func rank(_ item: Item) -> Int { item.isOnNow ? 0 : (item.phase == .upcoming ? 1 : 2) }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        let left = lhs.event.kickoffDate ?? .distantFuture
        let right = rhs.event.kickoffDate ?? .distantFuture
        return left == right ? lhs.id < rhs.id : left < right
    }

    /// Conservative duplicates only: same ID, or exact start + sport + both
    /// names. No fuzzy club matching (doubleheaders and rematches must survive).
    /// Preserve a real catalog ID and union real sources; never synthesize URLs.
    static func uniqueEvents(_ events: [AnalyticalDataEngine.EventReference]) -> [AnalyticalDataEngine.EventReference] {
        func nameKey(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func identity(_ event: AnalyticalDataEngine.EventReference) -> String {
            guard !event.isBroadcastChannel, let kickoff = event.kickoffDate,
                  event.homeName != "Home", event.awayName != "Away",
                  !event.homeName.isEmpty, !event.awayName.isEmpty else { return "id:\(event.id)" }
            return "\(event.normalizedCategory)|\(Int64(kickoff.timeIntervalSince1970))|\(nameKey(event.homeName))|\(nameKey(event.awayName))"
        }
        var groups: [String: [AnalyticalDataEngine.EventReference]] = [:]
        var keysByID: [String: String] = [:]
        for event in events.sorted(by: { $0.id < $1.id }) {
            // Duplicate IDs normally carry the same metadata; keep all their
            // source descriptors in the same group, even if timing differs.
            let key = keysByID[event.id] ?? identity(event)
            keysByID[event.id] = key
            groups[key, default: []].append(event)
        }
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            var sourceIDs = Set<String>()
            let sources = group.flatMap { $0.sources ?? [] }.filter {
                sourceIDs.insert("\($0.source)|\($0.id)").inserted
            }
            return .init(id: first.id, title: first.title, category: first.category, date: first.date, poster: first.poster, popular: first.popular, teams: first.teams, sources: sources)
        }
    }
}
