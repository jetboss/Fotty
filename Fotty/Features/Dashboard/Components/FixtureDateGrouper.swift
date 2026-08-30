import Foundation

struct FixtureDateSection: Identifiable {
    let id: String
    let title: String
    let events: [AnalyticalDataEngine.EventReference]
}

enum FixtureDateGrouper {
    private static let calendar = Calendar.current

    /// Today → Tomorrow → later future → Yesterday → older past.
    /// Preserves caller order within each day bucket.
    static func sections(from events: [AnalyticalDataEngine.EventReference]) -> [FixtureDateSection] {
        var orderedKeys: [String] = []
        var buckets: [String: [AnalyticalDataEngine.EventReference]] = [:]

        for event in events {
            let key = sectionKey(for: event.kickoffDate)
            if buckets[key] == nil {
                orderedKeys.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(event)
        }

        let sections = orderedKeys.compactMap { key -> FixtureDateSection? in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            return FixtureDateSection(
                id: key,
                title: sectionTitle(for: group.first?.kickoffDate),
                events: group
            )
        }

        return sections.sorted {
            sectionSortRank(for: $0.events.first?.kickoffDate)
                < sectionSortRank(for: $1.events.first?.kickoffDate)
        }
    }

    private static let sectionDateFormatterLock = NSLock()
    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        f.timeZone = .current
        return f
    }()

    private static func sectionKey(for date: Date?) -> String {
        guard let date else { return "unknown" }
        return "\(Int(calendar.startOfDay(for: date).timeIntervalSince1970))"
    }

    private static func sectionTitle(for date: Date?) -> String {
        guard let date else { return "Schedule TBD" }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        sectionDateFormatterLock.lock()
        defer { sectionDateFormatterLock.unlock() }
        return sectionDateFormatter.string(from: date)
    }

    private static func sectionSortRank(for date: Date?) -> Int {
        guard let date else { return 500 }
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        if start == today { return 0 }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), start == tomorrow {
            return 1
        }
        if start > today {
            return 10 + (calendar.dateComponents([.day], from: today, to: start).day ?? 0)
        }
        if calendar.isDateInYesterday(date) { return 200 }
        return 300 + (calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }
}

enum HomeMatchPriority {
    static let startingSoonWindow: TimeInterval = 6 * 3600
    static let multiViewPregameWindow: TimeInterval = 2 * 60

    @MainActor
    static func isLive(
        _ event: AnalyticalDataEngine.EventReference,
        scoreService: LiveScoreService
    ) -> Bool {
        // Prefer official scoreboard when we have a match (API-Football / cached).
        if event.normalizedCategory == "football",
           let status = scoreService.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)?.status {
            return status.isLive
        }
        // StreamEx/Nexus often lists club friendlies and smaller leagues that never match
        // the scoreboard API. If kickoff has started and we're still inside the match window,
        // treat it as live so it pins to the Live rail instead of burying mid-list.
        return event.broadcastTiming() == .live
    }

    @MainActor
    static func isFinished(
        _ event: AnalyticalDataEngine.EventReference,
        scoreService: LiveScoreService
    ) -> Bool {
        if event.normalizedCategory == "football",
           let status = scoreService.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)?.status {
            return status.isFinished
        }
        return event.isPastEstimatedMatchWindow()
    }

    static func isStartingSoon(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        guard !event.isBroadcastChannel, let kickoff = event.kickoffDate else { return false }
        let now = Date()
        return kickoff >= now.addingTimeInterval(-60)
            && kickoff <= now.addingTimeInterval(startingSoonWindow)
    }

    /// MultiView should be offered only when two broadcasts can reasonably be
    /// expected to start now. Catalog sources can be published many hours in
    /// advance, but their presence alone is not a promise that media is live.
    @MainActor
    static func isMultiViewTimingEligible(
        _ event: AnalyticalDataEngine.EventReference,
        scoreService: LiveScoreService,
        now: Date = Date()
    ) -> Bool {
        if isLive(event, scoreService: scoreService) { return true }
        guard let kickoff = event.kickoffDate else { return false }
        return kickoff > now && kickoff <= now.addingTimeInterval(multiViewPregameWindow)
    }

    @MainActor
    static func isElite(
        _ event: AnalyticalDataEngine.EventReference,
        scoreService: LiveScoreService
    ) -> Bool {
        guard event.normalizedCategory == "football" else { return false }
        if let match = scoreService.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) {
            return Config.Arena.discoveryIncludes(
                competitionId: match.competition.id,
                competitionName: match.competition.name,
                competitionCode: match.competition.code
            )
        }
        let officialMatch = scoreService.findMatch(
            home: event.homeName,
            away: event.awayName,
            near: event.kickoffDate,
            maximumKickoffDelta: 6 * 3_600
        )
        switch AnalyticalDataEngine.footballLeagueTab(for: event, officialMatch: officialMatch) {
        case .premierLeague, .championsLeague, .laLiga:
            return true
        default:
            return false
        }
    }

    @MainActor
    static func rank(
        _ event: AnalyticalDataEngine.EventReference,
        scoreService: LiveScoreService,
        isFollowed: Bool
    ) -> Int {
        let live = isLive(event, scoreService: scoreService)
        let finished = isFinished(event, scoreService: scoreService)
        let elite = isElite(event, scoreService: scoreService)
        let soon = !live && !finished && isStartingSoon(event)
        let followedBoost = isFollowed ? 0 : 2
        let eliteBoost = elite ? 0 : 3

        if live { return 0 + followedBoost + eliteBoost }
        if finished { return 400 + followedBoost }
        if soon { return 20 + followedBoost + eliteBoost }
        if let kickoff = event.kickoffDate, Calendar.current.isDateInToday(kickoff) {
            return 40 + followedBoost + eliteBoost
        }
        if let kickoff = event.kickoffDate, kickoff > Date() {
            return 60 + followedBoost + eliteBoost
        }
        return 300 + followedBoost
    }

    @MainActor
    static func prioritized(
        _ events: [AnalyticalDataEngine.EventReference],
        scoreService: LiveScoreService,
        isFollowed: (AnalyticalDataEngine.EventReference) -> Bool
    ) -> [AnalyticalDataEngine.EventReference] {
        events.sorted { lhs, rhs in
            let lr = rank(lhs, scoreService: scoreService, isFollowed: isFollowed(lhs))
            let rr = rank(rhs, scoreService: scoreService, isFollowed: isFollowed(rhs))
            if lr != rr { return lr < rr }
            return (lhs.kickoffDate ?? .distantFuture) < (rhs.kickoffDate ?? .distantFuture)
        }
    }

    /// Home is a discovery schedule, not a results archive. The shared catalog
    /// deliberately retains recent fixtures so My Matchday can show them under
    /// Recent, but Home must remove them as soon as they are known to be over.
    @MainActor
    static func homeScheduleCandidates(
        from events: [AnalyticalDataEngine.EventReference],
        excluding eventIDs: Set<String> = [],
        scoreService: LiveScoreService
    ) -> [AnalyticalDataEngine.EventReference] {
        events.filter { event in
            !eventIDs.contains(event.id)
                && !isFinished(event, scoreService: scoreService)
        }
    }

    @MainActor
    static func carouselCandidates(
        from events: [AnalyticalDataEngine.EventReference],
        scoreService: LiveScoreService,
        isFollowed: (AnalyticalDataEngine.EventReference) -> Bool,
        limit: Int = 3
    ) -> [AnalyticalDataEngine.EventReference] {
        let watchable = events.filter { !$0.isBroadcastChannel && !isFinished($0, scoreService: scoreService) }
        return Array(
            prioritized(watchable, scoreService: scoreService, isFollowed: isFollowed).prefix(limit)
        )
    }
}
