import Foundation

/// A presentation-only projection of the shared catalog. No fetching, stream
/// probing, or changes to persisted fixture/provider identities happen here.
@MainActor
struct HomeSportsDiscovery {
    /// A deterministic clock for the isolated, in-memory UI journey only.
    static var automatedClockStart: Date? {
        #if DEBUG
        if AppRuntime.isAutomatedTesting,
           ProcessInfo.processInfo.environment["FOTTY_HOME_CLOCK_UI_TESTING"] == "1" {
            return Date(timeIntervalSince1970: 1_800_000_000)
        }
        #endif
        return nil
    }

    private static var automatedClockOffset: TimeInterval = 0
    static var automatedClockDate: Date? {
        automatedClockStart?.addingTimeInterval(automatedClockOffset)
    }

    #if DEBUG
    static func advanceAutomatedClock() {
        guard automatedClockStart != nil else { return }
        // Ephemeral process state, not UserDefaults. Returning to Home must not
        // rewind the test clock when its view-local @State is recreated.
        automatedClockOffset = 100 * 60
    }
    #endif
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
        var isStarting: Bool { phase == .upcoming && VerifiedFixtureStartingPolicy.contains(event, at: now) }
        var cricketActivity: CricketActivityPresentationPolicy.Activity? {
            phase == .live ? CricketActivityPresentationPolicy.activity(for: event, at: now) : nil
        }
        var hasConfirmedLiveStatus: Bool { phase == .live && cricketActivity?.suppressesLiveBadge != true }
        var prominentStatusLabel: String {
            if let activity = cricketActivity, activity.suppressesLiveBadge { return activity.title }
            switch phase {
            case .live: return "LIVE"
            case .listedNow: return canWatch ? "Broadcast listed" : "Listed start"
            case .upcoming: return isStarting ? "Starting" : "Upcoming"
            case .unconfirmed: return "Start unconfirmed"
            }
        }
        var actionTitle: String { MatchStartPolicy(event: event, now: now, status: officialStatus).title }

        var statusLabel: String {
            if let activity = cricketActivity, activity.suppressesLiveBadge { return activity.title }
            switch phase {
            case .live: return canWatch ? "Live" : "In play"
            // A provider listing or elapsed kickoff is not live-play evidence.
            // Keep the listed time; the spotlight separately names that status.
            case .listedNow: return event.kickoffDate?.arenaKickoffDetailLine() ?? "Scheduled"
            case .upcoming: return isStarting ? "Starting" : event.kickoffDate?.arenaKickoffDetailLine() ?? "Time TBC"
            case .unconfirmed:
                if event.cricketFixture?.status == .postponed { return "Postponed" }
                if event.sportsFixture?.status == .postponed { return "Postponed" }
                if let officialStatus, !officialStatus.isUpcoming { return officialStatus.displayText }
                return event.kickoffDate == nil ? "Time TBC" : "Start unconfirmed"
            }
        }
    }

    @MainActor
    struct SportActivity: Identifiable {
        let id: String
        let onNow: Int
        let confirmedLive: Int
        let nextStart: Date?
        let channels: Int
        let unconfirmed: Int
        var atStumps = 0
        var onBreak = 0
        var contextUnconfirmed = 0
        var starting = 0

        func summary(at now: Date, calendar: Calendar = .current) -> String {
            if confirmedLive > 0 { return "\(confirmedLive) live" }
            let listed = max(0, onNow - atStumps - onBreak - contextUnconfirmed)
            if listed > 0 { return "\(listed) listed" }
            if starting > 0 { return "Starting" }
            if contextUnconfirmed > 0 { return "Status unconfirmed" }
            if atStumps > 0, onBreak == 0 { return atStumps == 1 ? "Stumps" : "\(atStumps) at stumps" }
            if atStumps + onBreak > 0 { return atStumps + onBreak == 1 ? "On break" : "\(atStumps + onBreak) on break" }
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

    /// A precomputed presentation key. Expensive score/catalog matching must
    /// happen once per item before sorting, never from the sort comparator.
    struct PresentationPriority: Comparable {
        let phase: Int
        let relevance: Int
        let available: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.phase != rhs.phase { return lhs.phase < rhs.phase }
            if lhs.relevance != rhs.relevance { return lhs.relevance < rhs.relevance }
            return lhs.available < rhs.available
        }
    }

    @MainActor
    struct HomeSections {
        let featuredLive: [Item]
        let moreLive: [Item]
        let nextClub: Item?
        let upcoming: [Item]
        let awaitingStatus: [Item]

        var leadsWithUpcomingClub: Bool {
            nextClub != nil && featuredLive.first?.hasConfirmedLiveStatus != true
        }
        var spotlight: Item? { leadsWithUpcomingClub ? nextClub : featuredLive.first }
        var clubBelowSpotlight: Item? { leadsWithUpcomingClub ? nil : nextClub }
        var remainingFeatured: ArraySlice<Item> { featuredLive.dropFirst(leadsWithUpcomingClub ? 0 : 1) }
    }

    struct DisplayRow: Identifiable {
        struct ID: Hashable {
            let section: String
            let columns: Int
            let eventIDs: [String]
        }
        let id: ID
        let items: [Item]
        let index: Int
        let total: Int
    }

    /// A fixture ID identifies a match, not a multi-card row. Keep row identity
    /// stable on clock/score ticks, but replace it when its section, membership
    /// or column structure changes. Never reuse an upcoming pair as a live row.
    static func displayRows(_ items: [Item], columns: Int, section: String) -> [DisplayRow] {
        let rows = FottyLayoutPolicy.rows(items, columns: columns)
        return rows.enumerated().map { index, row in
            DisplayRow(id: .init(section: section, columns: max(1, columns), eventIDs: row.items.map(\.id)),
                       items: row.items, index: index, total: rows.count)
        }
    }

    static func nextClockDelay(events: [EventReference], now: Date) -> TimeInterval {
        // Minute cadence for the projection, with an exact wake at kickoff.
        // Per-second countdowns remain local to visible controls.
        let nextStart = events.compactMap { event -> TimeInterval? in
            guard !event.isBroadcastChannel, let start = event.kickoffDate else { return nil }
            let interval = start.timeIntervalSince(now)
            return interval > 0 ? interval : nil
        }.min() ?? 60
        return min(60, max(0.05, nextStart))
    }

    /// Audience defaults for the private beta. Explicit follows still matter,
    /// but an unrelated minor listing cannot displace Premier League or
    /// Champions League. This ranks presentation only and never changes catalog
    /// identity, source eligibility, or score coverage.
    static func relevanceRank(
        sport: String,
        footballLeague: AnalyticalDataEngine.FootballLeagueTab?,
        isFollowed: Bool,
        isCPL: Bool,
        isMajorLeague: Bool = false
    ) -> Int {
        if sport == "football" {
            switch footballLeague ?? .other {
            case .premierLeague: return isFollowed ? 0 : 1
            case .championsLeague: return isFollowed ? 0 : 2
            case .laLiga: return isFollowed ? 3 : 4
            case .serieA: return isFollowed ? 3 : 5
            case .bundesliga: return isFollowed ? 3 : 6
            case .ligue1: return isFollowed ? 3 : 7
            case .other, .all: return isFollowed ? 3 : 10
            }
        }
        if isCPL { return isFollowed ? 0 : 3 }
        if isFollowed { return 3 }
        if isMajorLeague { return 8 }
        return sport == "football" ? 10 : 9
    }

    let now: Date
    let items: [Item]
    let channels: [AnalyticalDataEngine.EventReference]
    let activities: [SportActivity]

    /// Playable catalogs intentionally omit terminal fixtures. Keep those
    /// accepted facts as a separate identity veto so another score/provider
    /// projection cannot recreate the same finished event as LIVE.
    @MainActor
    private struct TerminalEvidenceIndex {
        private struct Key: Hashable {
            let sport: String
            let kickoffBucket: Int64
        }
        private let byKickoff: [Key: [EventReference]]

        init(events: [EventReference], now: Date) {
            var rows: [Key: [EventReference]] = [:]
            var seen = Set<String>()
            for event in events {
                guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
                      VerifiedFixtureTerminalPolicy.state(for: event, at: now) != nil,
                      let start = event.kickoffDate, seen.insert(event.id).inserted else { continue }
                let key = Key(sport: event.normalizedCategory, kickoffBucket: Self.bucket(start))
                rows[key, default: []].append(event)
            }
            byKickoff = rows
        }

        func contains(_ event: EventReference) -> Bool {
            guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel,
                  let start = event.kickoffDate else { return false }
            let bucket = Self.bucket(start)
            let candidates = (-1...1).flatMap {
                byKickoff[Key(sport: event.normalizedCategory, kickoffBucket: bucket + Int64($0))] ?? []
            }.filter { terminal in
                guard terminal.kickoffDate.map({ abs($0.timeIntervalSince(start)) <= SportsFixtureCatalog.kickoffTolerance }) == true else { return false }
                if let fixture = terminal.sportsFixture {
                    // Reuse reviewed competition, participant, squad and dated
                    // provider admission. Roster membership alone is not enough.
                    return SportsFixtureCatalog.providerMatches(event, fixture: fixture,
                        kickoff: terminal.kickoffDate, allowUnmarkedLeague: true, admittingUnmarkedLeague: true)
                }
                if let fixture = terminal.cricketFixture, let current = event.cricketFixture {
                    return fixture.fixtureID == current.fixtureID && fixture.competitionID == current.competitionID
                }
                // Untyped cricket rows cannot borrow a result by loose names.
                // An exact ID still needs its original dated identity to agree.
                guard event.id == terminal.id else { return false }
                return CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: event), in: [terminal]) != nil
            }
            // Two accepted identities are a conflict, not permission to pick
            // whichever terminal row happens to arrive first.
            return candidates.count == 1
        }

        private static func bucket(_ date: Date) -> Int64 {
            Int64(floor(date.timeIntervalSince1970 / SportsFixtureCatalog.kickoffTolerance))
        }
    }

    init(
        events: [AnalyticalDataEngine.EventReference],
        now: Date = Date(),
        terminalEvents: [AnalyticalDataEngine.EventReference] = [],
        status: (AnalyticalDataEngine.EventReference) -> FootballMatch.MatchStatus? = { _ in nil }
    ) {
        self.now = now
        let terminalEvidence = TerminalEvidenceIndex(events: terminalEvents + events, now: now)
        // Evaluate accepted terminal identities before source-union projection
        // so deduplication cannot shed an original row's conflict quarantine.
        let activeEvents = events.filter { event in
            guard !event.isBroadcastChannel else { return true }
            if !event.hasCatalogIdentityConflict,
               VerifiedFixtureTerminalPolicy.state(for: event, at: now) != nil { return false }
            return !terminalEvidence.contains(event)
        }
        // Keep conflict tombstones in the catalog/resolver, but never turn
        // them into a visible Home match or a source-bearing channel.
        let unique = Self.uniqueEvents(activeEvents).filter { !$0.hasCatalogIdentityConflict }
        let channelEvents = unique.filter(\.isBroadcastChannel)
        let eventItems: [Item] = unique.compactMap { event in
            guard !event.isBroadcastChannel else { return nil }
            let official = status(event)
            guard official?.isFinished != true, official != .cancelled else { return nil }
            let phase: Item.Phase
            if let cricket = event.cricketFixture {
                if cricket.isLive(at: now) { phase = .live }
                else if cricket.verified, cricket.status == .scheduled,
                        let kickoff = event.kickoffDate, kickoff > now { phase = .upcoming }
                else { phase = .unconfirmed }
            } else if let fixture = event.sportsFixture, official == nil {
                if fixture.isLive(at: now) { phase = .live }
                else if fixture.verified, fixture.status == .scheduled, let kickoff = event.kickoffDate, kickoff > now { phase = .upcoming }
                else if VerifiedFixtureStartingPolicy.contains(event, at: now) { phase = .upcoming }
                else { phase = .unconfirmed }
            } else if official?.isLive == true {
                phase = .live
            } else if let official, !official.isUpcoming {
                phase = .unconfirmed
            } else if let kickoff = event.kickoffDate, kickoff > now {
                phase = .upcoming
            } else if VerifiedFixtureStartingPolicy.contains(event, at: now) {
                phase = .upcoming
            } else {
                // Remove elapsed discovery windows without inventing results.
                if event.isPastEstimatedMatchWindow(at: now) { return nil }
                // A trusted CPL kickoff that has passed belongs in "on now"
                // discovery even when the stream provider exposes only a
                // separate channel row. The status remains "listed start",
                // not an invented official live result.
                if event.isCPLFixture, event.kickoffDate.map({ $0 <= now }) == true {
                    phase = .listedNow
                } else {
                    phase = official == nil
                        && StreamPluginProviderMatching.hasActiveCatalogSource(event)
                        && event.broadcastTiming(at: now) == .live ? .listedNow : .unconfirmed
                }
            }
            return Item(event: event, phase: phase, officialStatus: official, now: now)
        }.sorted(by: Self.precedes)

        channels = channelEvents
        items = eventItems
        let categories = Set(events.map(\.normalizedCategory)).union(["football"])
        activities = Self.makeActivities(
            categories: categories,
            items: eventItems,
            channels: channelEvents,
            now: now
        )
    }

    /// Rebuild the compact sport summaries from the same already-filtered rows
    /// the destination will show. Keep every catalog sport represented so a
    /// restrictive preference says "Nothing listed" instead of hiding the way
    /// back to that sport.
    func activities(
        scopedItems: [Item],
        scopedChannels: [AnalyticalDataEngine.EventReference]
    ) -> [SportActivity] {
        Self.makeActivities(
            categories: Set(activities.map(\.id)),
            items: scopedItems,
            channels: scopedChannels,
            now: now
        )
    }

    private static func makeActivities(
        categories: Set<String>,
        items: [Item],
        channels: [AnalyticalDataEngine.EventReference],
        now: Date
    ) -> [SportActivity] {
        categories.map { category in
            let matches = items.filter { $0.sport == category }
            return SportActivity(
                id: category,
                onNow: matches.filter(\.isOnNow).count,
                confirmedLive: matches.filter(\.hasConfirmedLiveStatus).count,
                nextStart: matches.first { $0.phase == .upcoming && !$0.isStarting }?.event.kickoffDate,
                channels: channels.filter { $0.normalizedCategory == category }.count,
                unconfirmed: matches.filter { $0.phase == .unconfirmed }.count,
                atStumps: matches.filter { $0.cricketActivity?.state == .stumps }.count,
                onBreak: matches.filter { $0.cricketActivity?.state == .interval }.count,
                contextUnconfirmed: matches.filter { $0.cricketActivity?.state == .unconfirmed }.count,
                starting: matches.filter(\.isStarting).count
            )
        }.sorted { lhs, rhs in
            // Fixed ties keep categories stable across provider order changes.
            func rank(_ activity: SportActivity) -> Int {
                if activity.onNow > 0 { return 0 }
                if activity.starting > 0 { return 1 }
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

    static func prioritized(
        _ items: [Item],
        priority: (Item) -> PresentationPriority
    ) -> [Item] {
        let ranked = items.map { (item: $0, priority: priority($0)) }
        return ranked.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            let leftStart = lhs.item.event.kickoffDate ?? .distantFuture
            let rightStart = rhs.item.event.kickoffDate ?? .distantFuture
            return leftStart == rightStart ? lhs.item.id < rhs.item.id : leftStart < rightStart
        }.map(\.item)
    }

    /// Give the most relevant live events the limited prominent space on Home.
    /// Remaining live events stay directly reachable in the compact More Live
    /// disclosure, while the full lineup continues to contain every event.
    func homeSections(
        from items: [Item],
        diverseUpcoming: Bool,
        featuredLiveLimit: Int,
        upcomingHorizon: TimeInterval = CatalogTimingPolicy.standardHomeUpcomingHorizon,
        upcomingLimit: Int = 3,
        followedTeamKeys: Set<String> = []
    ) -> HomeSections {
        func followsClub(_ item: Item) -> Bool {
            guard !followedTeamKeys.isEmpty, item.sport == "football", !item.event.hasCatalogIdentityConflict else { return false }
            return [item.event.homeName, item.event.awayName].contains {
                followedTeamKeys.contains(TeamFollowKey.make(name: $0, category: item.sport))
            }
        }
        func priority(_ item: Item) -> Int {
            guard item.hasConfirmedLiveStatus else { return 4 }
            if followsClub(item) { return 0 }
            if item.sport == "football" { return 1 }
            return item.sport == "cricket" ? 2 : 3
        }
        let current = items.filter(\.isOnNow)
        var live = current
        if let leader = current.indices.min(by: { priority(current[$0]) < priority(current[$1]) }), leader != 0 {
            live.insert(live.remove(at: leader), at: 0)
        }
        let nextClub = followedTeamKeys.isEmpty ? nil : items.filter {
            $0.phase == .upcoming && followsClub($0) && ($0.event.kickoffDate ?? .distantPast) > now
        }.min { ($0.event.kickoffDate ?? .distantFuture) < ($1.event.kickoffDate ?? .distantFuture) }
        let upcoming = featured(
            from: items.filter { !$0.isOnNow && $0.id != nextClub?.id },
            diverse: diverseUpcoming,
            upcomingHorizon: upcomingHorizon,
            limit: upcomingLimit
        )
        let boundary = min(max(0, featuredLiveLimit), live.count)
        return HomeSections(
            featuredLive: Array(live[..<boundary]),
            moreLive: Array(live[boundary...]),
            nextClub: nextClub,
            upcoming: upcoming,
            // Losing live-status evidence must not remove a current fixture
            // from Home. This is neutral visibility, never LIVE or permission
            // to play. Terminal/conflict vetoes were applied before projection.
            awaitingStatus: items.filter {
                guard $0.phase == .unconfirmed, $0.sport == "football",
                      let start = $0.event.kickoffDate else { return false }
                return (0..<4 * 3600).contains(now.timeIntervalSince(start))
            }
        )
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

    /// A bounded set of timely events. The broad Home defaults to three events
    /// in six hours and can diversify sports; personalized Home supplies its
    /// explicit three-day horizon and device-specific limit instead.
    func featured(
        from items: [Item],
        diverse: Bool,
        upcomingHorizon: TimeInterval = CatalogTimingPolicy.standardHomeUpcomingHorizon,
        limit: Int = 3
    ) -> [Item] {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else { return [] }
        let eligible = items.filter {
            $0.isOnNow || ($0.phase == .upcoming
                && ($0.event.kickoffDate ?? .distantFuture) <= now.addingTimeInterval(upcomingHorizon))
        }
        guard diverse else { return Array(eligible.prefix(boundedLimit)) }
        var sports = Set<String>()
        let representatives = eligible.filter { sports.insert($0.sport).inserted }.sorted { lhs, rhs in
            if lhs.isOnNow != rhs.isOnNow { return lhs.isOnNow }
            let l = Self.sportOrder.firstIndex(of: lhs.sport) ?? Self.sportOrder.count
            let r = Self.sportOrder.firstIndex(of: rhs.sport) ?? Self.sportOrder.count
            return l == r ? Self.precedes(lhs, rhs) : l < r
        }
        let first = Array(representatives.prefix(boundedLimit))
        let ids = Set(first.map(\.id))
        return first + eligible.filter { !ids.contains($0.id) }.prefix(boundedLimit - first.count)
    }

    func later(
        from items: [Item],
        excluding featured: [Item],
        calendar: Calendar = .current,
        horizon: TimeInterval = CatalogTimingPolicy.standardHomeLaterHorizon
    ) -> (title: String, items: [Item]) {
        let excluded = Set(featured.map(\.id))
        let cutoff = now.addingTimeInterval(horizon)
        let future = items.filter {
            $0.phase == .upcoming
                && !excluded.contains($0.id)
                && ($0.event.kickoffDate ?? .distantFuture) <= cutoff
        }
        let today = future.filter { item in
            item.event.kickoffDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        }
        return today.isEmpty ? ("Coming up", Array(future.prefix(2))) : ("Later today", Array(today.prefix(2)))
    }

    static func visibleActivities(_ activities: [SportActivity], selectedSport: String) -> [SportActivity] {
        var visible = Array(activities.prefix(5))
        if selectedSport != Self.allSports, !visible.contains(where: { $0.id == selectedSport }),
           let selected = activities.first(where: { $0.id == selectedSport }) {
            if visible.count == 5 { visible.removeLast() }
            visible.append(selected)
        }
        return visible
    }

    func visibleActivities(selectedSport: String) -> [SportActivity] {
        Self.visibleActivities(activities, selectedSport: selectedSport)
    }

    private static func precedes(_ lhs: Item, _ rhs: Item) -> Bool {
        func rank(_ item: Item) -> Int { item.isOnNow ? 0 : (item.phase == .upcoming ? 1 : 2) }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        let left = lhs.event.kickoffDate ?? .distantFuture
        let right = rhs.event.kickoffDate ?? .distantFuture
        return left == right ? lhs.id < rhs.id : left < right
    }

    /// Use the catalog's exact identity policy here too: Home must not undo
    /// squad/competition fences, distinct official IDs or conflict quarantine
    /// after the coordinator's cooperative deduplication. Sorting only makes
    /// the representative deterministic when equally source-backed rows agree.
    static func uniqueEvents(_ events: [AnalyticalDataEngine.EventReference]) -> [AnalyticalDataEngine.EventReference] {
        AnalyticalDataEngine.deduplicateMatches(events.sorted { $0.id < $1.id })
    }
}

/// Mirrors the state that will remain after a sport tile is selected. Cricket's
/// subfilter and Home interests persist; the transient "Following only" filter
/// and football league selection apply only while their current sport remains
/// selected. Keeping this policy separate makes the tile promise testable.
@MainActor
struct HomeSportActivityScope {
    let selectedSport: String
    let selectedFootballLeague: AnalyticalDataEngine.FootballLeagueTab
    let selectedCricketFilter: CricketCatalogFilter
    let showFollowedOnly: Bool
    let restrictToHomeInterests: Bool

    func includes(
        _ item: HomeSportsDiscovery.Item,
        footballLeague: AnalyticalDataEngine.FootballLeagueTab?,
        isFollowed: Bool
    ) -> Bool {
        if item.sport == "football", selectedSport == "football",
           selectedFootballLeague != .all, footballLeague != selectedFootballLeague {
            return false
        }
        if item.sport == "cricket", !selectedCricketFilter.includes(item.event) {
            return false
        }
        if showFollowedOnly, selectedSport == item.sport, !isFollowed {
            return false
        }
        return !restrictToHomeInterests || isFollowed
    }

    func includes(channel: AnalyticalDataEngine.EventReference) -> Bool {
        if channel.normalizedCategory == "cricket", !selectedCricketFilter.includes(channel) {
            return false
        }
        if restrictToHomeInterests { return false }
        if showFollowedOnly, selectedSport == channel.normalizedCategory { return false }
        return true
    }
}
