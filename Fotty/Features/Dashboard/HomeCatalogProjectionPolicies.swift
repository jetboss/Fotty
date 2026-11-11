import Foundation

@MainActor
enum HomeSportSelectionPolicy {
    static func validatedSelection(_ selected: String, availableSports: [String]) -> String {
        guard selected != HomeSportsDiscovery.allSports, !availableSports.isEmpty else { return selected }
        return availableSports.contains(selected) ? selected : HomeSportsDiscovery.allSports
    }
}

enum HomeUpcomingPresentationPolicy {
    /// A personalized upcoming plan puts followed upcoming matches first. No
    /// match has carried a listed source since the shared catalog closed.
    static func availabilityRank(
        equalizeSelectedInterests: Bool,
        isFollowed: Bool,
        isUpcoming: Bool
    ) -> Int {
        equalizeSelectedInterests && isFollowed && isUpcoming ? 0 : 1
    }

    static func horizon(personalized: Bool) -> TimeInterval {
        personalized ? CatalogTimingPolicy.personalizedHomeUpcomingHorizon
            : CatalogTimingPolicy.standardHomeUpcomingHorizon
    }

    static func emptyMessage(sport: String?, personalized: Bool, hasCurrentEvents: Bool) -> String {
        let hours = Int(horizon(personalized: personalized) / 3_600)
        let window = hours >= 24 && hours.isMultiple(of: 24)
            ? "\(hours / 24) days" : "\(hours) hours"
        if let sport {
            return "No \(hasCurrentEvents ? "other " : "")\(sport) events are starting in the next \(window)."
        }
        if personalized {
            return hasCurrentEvents
                ? "No other matches from your interests are scheduled in the next \(window)."
                : "Nothing from your interests is scheduled in the next \(window)."
        }
        return "Nothing\(hasCurrentEvents ? " else" : "") is starting in the next \(window)."
    }
}

struct HomeSportActivityProjectionKey: Hashable {
    let selectedSport: String
    let selectedFootballLeague: String
    let selectedCricketFilter: String
    let showFollowedOnly: Bool
    let onlyShowSelectedInterests: Bool
    let selectionIdentity: SportsPersonalizationPolicy.SelectionIdentity
}

struct HomePersonalizationFactsKey: Hashable {
    let contentRevision: Int
    let scoreRevisionMilliseconds: Int64
    let selectionIdentity: SportsPersonalizationPolicy.SelectionIdentity
}

struct HomePersonalizationFacts: Equatable {
    let isFollowed: Bool
    let isMajorLeague: Bool
    let isCPL: Bool
}

@MainActor
enum HomeProjectionWorkPolicy {
    /// Actually suspend the actor so pending input/render work can run. A bare
    /// Task.yield may immediately resume the same job. The bounded one-ms pause
    /// is between unpublished stages/batches, never between visible mutations.
    static func checkpoint(isCurrent: () -> Bool) async -> Bool {
        do { try await Task.sleep(for: .milliseconds(1)) }
        catch { return false }
        return !Task.isCancelled && isCurrent()
    }
}

struct HomePersonalizationFactsCache {
    let key: HomePersonalizationFactsKey
    let facts: [String: HomePersonalizationFacts]

    func facts(matching currentKey: HomePersonalizationFactsKey) -> [String: HomePersonalizationFacts] {
        key == currentKey ? facts : [:]
    }

    /// Only for rows in the atomically published discovery packet. A pending
    /// raw catalog/score revision does not change those rows yet. Raw-event
    /// consumers must keep using the complete revision check above.
    func factsForPublishedProjection(selection: SportsPersonalizationPolicy.SelectionIdentity) -> [String: HomePersonalizationFacts] {
        key.selectionIdentity == selection ? facts : [:]
    }

    static func rebuilding(
        key: HomePersonalizationFactsKey,
        items: [HomeSportsDiscovery.Item],
        previous: HomePersonalizationFactsCache?,
        evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts
    ) -> Self {
        let reusable = previous?.facts(matching: key) ?? [:]
        var facts: [String: HomePersonalizationFacts] = [:]
        facts.reserveCapacity(items.count)
        for item in items { facts[item.id] = reusable[item.id] ?? evaluate(item) }
        return Self(key: key, facts: facts)
    }
}

struct HomeDiscoveryRankingKey: Hashable {
    let projectionRevision: Int
    let scope: HomeSportActivityProjectionKey
}

@MainActor
struct HomeDiscoveryRankingSnapshot {
    let key: HomeDiscoveryRankingKey
    let home: [HomeSportsDiscovery.Item]
    let lineup: [HomeSportsDiscovery.Item]

    func items(matching key: HomeDiscoveryRankingKey, home: Bool) -> [HomeSportsDiscovery.Item]? {
        self.key == key ? (home ? self.home : lineup) : nil
    }
}

