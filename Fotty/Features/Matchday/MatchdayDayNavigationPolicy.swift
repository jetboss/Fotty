import Foundation

/// Jump destinations are a projection of headings already rendered in Full
/// Matchday. This never creates a date, changes a filter or widens its catalog.
enum MatchdayDayNavigationPolicy {
    struct Section: Equatable {
        let id: String
        let title: String
    }

    struct Target: Identifiable, Equatable {
        let id: String
        let title: String
    }

    static func targets(sections: [Section]) -> [Target] {
        var seen = Set<String>()
        return sections.compactMap { section in
            let isCurrent = ["live", "listed", "next"].contains(section.id)
            let isDay: Bool
            if section.id.hasPrefix("day-"), let interval = Double(section.id.dropFirst(4)) {
                isDay = interval.isFinite
            } else { isDay = false }
            guard isCurrent || isDay, !section.title.isEmpty, seen.insert(section.id).inserted else { return nil }
            return Target(id: section.id, title: section.title)
        }
    }
}
