import Foundation

/// Home presentation of a match that the fixture authority still calls live.
/// An explicit interval is not a new fixture status, a resumption prediction or
/// permission to stop/replace its broadcast. Existing source/timing gates stay put.
@MainActor
enum CricketActivityPresentationPolicy {
    enum State: Equatable { case inPlay, stumps, interval, ongoing, unconfirmed }
    struct Activity: Equatable {
        let state: State
        let title: String
        var suppressesLiveBadge: Bool { state != .inPlay }
    }

    static func activity(for event: EventReference, at now: Date) -> Activity? {
        guard event.normalizedCategory == "cricket", !event.isBroadcastChannel,
              let metadata = event.cricketFixture, metadata.isLive(at: now) else { return nil }
        // A Test's ongoing lifecycle spans play, intervals and overnight. Missing
        // phase evidence cannot turn that lifecycle into an active LIVE badge.
        let missingPhase = metadata.format == .test
            ? Activity(state: .ongoing, title: "Test in progress")
            : Activity(state: .unconfirmed, title: "Status unconfirmed")
        if metadata.context == nil { return metadata.format == .test ? missingPhase : nil }
        guard let context = CricketMatchContextPolicy.context(for: event, at: now), let phase = context.phase else {
            return missingPhase
        }
        switch phase {
        case .inPlay: return .init(state: .inPlay, title: phase.title)
        case .stumps: return .init(state: .stumps, title: phase.title)
        case .matchBreak, .inningsBreak, .lunch, .tea, .interrupted, .delayed:
            return .init(state: .interval, title: phase.title)
        case .finished, .cancelled, .postponed, .scheduled:
            // These phases cannot override the enclosing fixture's lifecycle.
            return missingPhase
        }
    }

    static func homePhaseRank(for item: HomeSportsDiscovery.Item, preservingLegacyOrder: Bool = false) -> Int {
        if preservingLegacyOrder { return item.isOnNow ? 0 : (item.phase == .upcoming ? 1 : 2) }
        if item.isOnNow { return item.cricketActivity?.suppressesLiveBadge == true ? 1 : 0 }
        if item.isStarting { return 1 }
        return item.phase == .upcoming ? 2 : 3
    }
}
