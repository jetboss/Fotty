import Foundation

/// Full Matchday is the personal schedule. A time window is an explicit filter,
/// not an implicit limit on which saved or followed matches are visible.
enum MatchdayViewMode: String, CaseIterable, Identifiable {
    case fullMatchday
    case timeWindow

    static let defaultMode = Self.fullMatchday
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullMatchday: return "Full Matchday"
        case .timeWindow: return "Time window"
        }
    }
}

/// A personal viewing window, not an estimate of a fixture's duration or finish.
enum ViewingPlanDuration: String, CaseIterable, Identifiable {
    case ninetyMinutes = "90-minutes"
    case twoHours = "2-hours"
    case evening = "evening"

    static let storageKey = "fotty.matchday.viewingWindow"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ninetyMinutes: return "90 min"
        case .twoHours: return "2 hours"
        // Keep the existing stored value and midnight boundary, but avoid
        // labelling a morning or afternoon selection as an evening.
        case .evening: return "Until midnight"
        }
    }

    static func saved(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .twoHours }

    func endDate(from start: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .ninetyMinutes: return start.addingTimeInterval(90 * 60)
        case .twoHours: return start.addingTimeInterval(2 * 3_600)
        case .evening:
            // Calendar arithmetic follows the user's local midnight across DST.
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))
                ?? start.addingTimeInterval(24 * 3_600)
        }
    }
}

/// Filters accepted presentation facts only. It never fetches, saves fixtures,
/// admits streams, renews receipts, schedules reminders or changes match status.
enum ViewingPlanPolicy {
    enum Phase: Equatable { case live, listed, upcoming, excluded }

    struct Candidate: Equatable {
        let id: String
        let start: Date?
        let phase: Phase
        var isChannel = false
        var hasIdentityConflict = false
    }

    struct Projection: Equatable {
        let currentIDs: [String]
        let upcomingIDs: [String]
        let windowStart: Date
        let windowEnd: Date
        let hasEnded: Bool
        var count: Int { currentIDs.count + upcomingIDs.count }
    }

    static func project(
        _ candidates: [Candidate], duration: ViewingPlanDuration,
        windowStart: Date, at now: Date, calendar: Calendar = .current
    ) -> Projection {
        let end = duration.endDate(from: windowStart, calendar: calendar)
        guard now < end else {
            return .init(currentIDs: [], upcomingIDs: [], windowStart: windowStart,
                         windowEnd: end, hasEnded: true)
        }

        // Identical repetitions are harmless; contradictory facts under one ID
        // are not a reason to guess which fixture belongs to a personal plan.
        let groups = Dictionary(grouping: candidates, by: \.id)
        let unique = groups.values.compactMap { group -> Candidate? in
            guard let first = group.first, !first.id.isEmpty,
                  group.allSatisfy({ $0 == first }), !first.isChannel,
                  !first.hasIdentityConflict else { return nil }
            return first
        }
        let current = unique.filter {
            switch $0.phase {
            case .live: return true // Accepted current live evidence, not kickoff inference.
            case .listed: return $0.start.map { $0 <= now } ?? false
            case .upcoming, .excluded: return false
            }
        }.sorted {
            if $0.phase != $1.phase { return $0.phase == .live }
            let left = $0.start ?? .distantPast, right = $1.start ?? .distantPast
            return left == right ? $0.id < $1.id : left < right
        }
        let upcoming = unique.filter {
            guard $0.phase == .upcoming, let start = $0.start else { return false }
            return start >= windowStart && start > now && start < end
        }.sorted {
            let left = $0.start ?? .distantFuture, right = $1.start ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
        return .init(currentIDs: current.map(\.id), upcomingIDs: upcoming.map(\.id),
                     windowStart: windowStart, windowEnd: end, hasEnded: false)
    }
}
