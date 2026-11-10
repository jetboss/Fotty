import XCTest
@testable import Fotty

@MainActor
final class CricketActivityPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ number: Int, phase: CricketMatchContext.Phase? = .inPlay,
                       offset: TimeInterval = 0, contextPresent: Bool = true,
                       homeID: String? = nil, format: CricketFixtureCatalog.Format = .test,
                       startOffset: TimeInterval = -3_600, source: Bool = false) -> EventReference {
        let home = "icc:home:\(number)", away = "icc:away:\(number)"
        let context = contextPresent ? CricketMatchContext(innings: [
            .init(number: 1, teamID: home, runs: 140, wickets: 4, overs: "47.0")
        ], currentInnings: 1, phase: phase) : nil
        let metadata = CricketFixtureMetadata(fixtureID: "icc:\(number)", competitionID: "icc", competitionName: "International cricket",
            format: format, status: .live, observedAt: now.addingTimeInterval(offset), verified: true,
            context: context, homeTeamID: homeID ?? home, awayTeamID: away)
        return .init(id: CricketFixtureCatalog.fixtureIDPrefix + metadata.fixtureID,
            title: "Team \(number) A vs Team \(number) B", category: "cricket",
            date: Int64(now.addingTimeInterval(startOffset).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Team \(number) A", badge: nil), away: .init(name: "Team \(number) B", badge: nil)),
            sources: source ? [.init(source: "delta", id: "route-\(number)")] : [], cricketFixture: metadata)
    }

    private func item(_ event: EventReference) throws -> HomeSportsDiscovery.Item {
        try XCTUnwrap(HomeSportsDiscovery(events: [event], now: now).items.first)
    }

    func testExplicitStumpsIsPresentedWithoutChangingFixturePhaseSourcesOrPlaybackTiming() throws {
        let original = event(1, phase: .stumps, startOffset: -2 * 86_400, source: true)
        let timing = MatchStartPolicy(event: original, now: now).timingAllowsPlayback
        let item = try item(original)

        XCTAssertEqual(item.phase, .live)
        XCTAssertTrue(item.isOnNow)
        XCTAssertFalse(item.hasConfirmedLiveStatus)
        XCTAssertEqual(item.prominentStatusLabel, "Stumps")
        XCTAssertEqual(item.statusLabel, "Stumps")
        XCTAssertEqual(item.event.cricketFixture, original.cricketFixture)
        XCTAssertEqual(item.event.sources?.map(\.id), original.sources?.map(\.id))
        XCTAssertEqual(MatchStartPolicy(event: item.event, now: now).timingAllowsPlayback, timing)
        XCTAssertNil(HomeDiscoveryRow.Presentation(item: item).liveDetail)
    }

    func testActualInPlayOutranksOlderFollowedStumpsWhileExplicitLegacyOrderingStaysUnchanged() throws {
        let stumps = try item(event(1, phase: .stumps, startOffset: -2 * 86_400))
        let active = try item(event(2, phase: .inPlay, startOffset: -1_000))
        func order(legacy: Bool) -> [String] {
            HomeSportsDiscovery.prioritized([stumps, active]) { row in
                .init(phase: CricketActivityPresentationPolicy.homePhaseRank(for: row, preservingLegacyOrder: legacy),
                      relevance: row.id == stumps.id ? 0 : 9, available: 0)
            }.map(\.id)
        }
        XCTAssertEqual(order(legacy: false), [active.id, stumps.id])
        XCTAssertEqual(order(legacy: true), [stumps.id, active.id])
        XCTAssertTrue(active.hasConfirmedLiveStatus)
        XCTAssertEqual(active.prominentStatusLabel, "LIVE")
    }

    func testSportTileCountsOnlyActivelyLiveWhenTwoTestsAreExplicitlyAtStumps() throws {
        let discovery = HomeSportsDiscovery(events: [event(1, phase: .stumps), event(2, phase: .stumps), event(3, phase: .inPlay)], now: now)
        let activity = try XCTUnwrap(discovery.activities.first { $0.id == "cricket" })
        XCTAssertEqual(activity.onNow, 3, "Ongoing fixtures remain discoverable")
        XCTAssertEqual(activity.confirmedLive, 1)
        XCTAssertEqual(activity.atStumps, 2)
        XCTAssertEqual(activity.summary(at: now), "1 live")
        XCTAssertTrue(discovery.items.allSatisfy { $0.phase == .live && $0.isOnNow })
    }

    func testOnlyStumpsSummaryDoesNotInventLiveListedOrTomorrowStart() throws {
        let discovery = HomeSportsDiscovery(events: [event(1, phase: .stumps), event(2, phase: .stumps)], now: now)
        let activity = try XCTUnwrap(discovery.activities.first { $0.id == "cricket" })
        XCTAssertEqual(activity.summary(at: now), "2 at stumps")
        XCTAssertEqual(activity.confirmedLive, 0)
        XCTAssertNil(activity.nextStart)
        XCTAssertFalse(activity.summary(at: now).contains("listed"))
        XCTAssertFalse(activity.summary(at: now).contains("Tomorrow"))
    }

    func testAllReviewedIntervalsUseTheirExplicitLabelAndNeverALiveBadge() throws {
        let phases: [CricketMatchContext.Phase] = [.matchBreak, .inningsBreak, .lunch, .tea, .interrupted, .delayed]
        for (index, phase) in phases.enumerated() {
            let item = try item(event(index + 1, phase: phase))
            XCTAssertEqual(item.statusLabel, phase.title)
            XCTAssertEqual(item.prominentStatusLabel, phase.title)
            XCTAssertFalse(item.hasConfirmedLiveStatus)
            XCTAssertEqual(item.phase, .live)
            XCTAssertTrue(item.isOnNow)
            XCTAssertNil(HomeDiscoveryRow.Presentation(item: item).liveDetail)
        }
        let discovery = HomeSportsDiscovery(events: [event(1, phase: .stumps), event(2, phase: .inningsBreak)], now: now)
        XCTAssertEqual(discovery.activities.first { $0.id == "cricket" }?.summary(at: now), "2 on break")
    }

    func testStaleContextCannotBePromotedToFreshLiveWithinLongerFixtureFreshness() throws {
        for phase in [CricketMatchContext.Phase.inPlay, .stumps] {
            let event = event(1, phase: phase, offset: -601)
            XCTAssertTrue(event.cricketFixture?.isLive(at: now) == true)
            XCTAssertNil(CricketMatchContextPolicy.context(for: event, at: now))
            let item = try item(event)
            XCTAssertEqual(item.phase, .live)
            XCTAssertTrue(item.isOnNow)
            XCTAssertFalse(item.hasConfirmedLiveStatus)
            XCTAssertEqual(item.statusLabel, "Test in progress")
            XCTAssertEqual(item.cricketActivity?.state, .ongoing)
            XCTAssertNil(HomeDiscoveryRow.Presentation(item: item).liveDetail)
            let activity = try XCTUnwrap(HomeSportsDiscovery(events: [event], now: now).activities.first { $0.id == "cricket" })
            XCTAssertEqual(activity.summary(at: now), "1 listed")
            XCTAssertEqual(activity.confirmedLive, 0)
        }
    }

    func testInvalidTeamFormatOrMissingPhaseCannotManufactureInPlayOrStumps() throws {
        for event in [event(1, phase: .inPlay, homeID: "foreign-team"),
                      event(2, phase: .stumps, format: .t20), event(3, phase: nil)] {
            let item = try item(event)
            XCTAssertFalse(item.hasConfirmedLiveStatus)
            XCTAssertEqual(item.statusLabel, event.cricketFixture?.format == .test ? "Test in progress" : "Status unconfirmed")
            XCTAssertEqual(CricketActivityPresentationPolicy.homePhaseRank(for: item), 1)
        }
    }

    func testContextFreshnessBoundaryIsRespectedWithoutRenewingTheFixtureReceipt() throws {
        let accepted = event(1, phase: .inPlay, offset: -600)
        XCTAssertTrue(try item(accepted).hasConfirmedLiveStatus)
        let expired = event(2, phase: .inPlay, offset: -601)
        XCTAssertFalse(try item(expired).hasConfirmedLiveStatus)
        XCTAssertEqual(expired.cricketFixture?.observedAt, now.addingTimeInterval(-601))
    }

    func testMissingTestContextRetainsLifecycleWithoutClaimingActivePlay() throws {
        let test = try item(event(1, contextPresent: false))
        XCTAssertEqual(test.cricketActivity?.state, .ongoing)
        XCTAssertEqual(test.phase, .live)
        XCTAssertTrue(test.isOnNow)
        XCTAssertFalse(test.hasConfirmedLiveStatus)
        XCTAssertEqual(test.prominentStatusLabel, "Test in progress")
        XCTAssertEqual(CricketActivityPresentationPolicy.homePhaseRank(for: test), 1)
        let shortFormat = try item(event(2, contextPresent: false, format: .t20))
        XCTAssertNil(shortFormat.cricketActivity)
        XCTAssertTrue(shortFormat.hasConfirmedLiveStatus)
    }

    func testNonCricketAndFuturePresentationKeepTheirExistingRelativeOrder() {
        let football = EventReference(id: "football", title: "Liverpool vs Chelsea", category: "football",
            date: Int64(now.timeIntervalSince1970) + 600, poster: nil, popular: false, teams: nil, sources: [])
        let live = HomeSportsDiscovery.Item(event: football, phase: .live, officialStatus: .inPlay, now: now)
        let future = HomeSportsDiscovery.Item(event: football, phase: .upcoming, officialStatus: nil, now: now)
        let held = HomeSportsDiscovery.Item(event: football, phase: .unconfirmed, officialStatus: nil, now: now)
        XCTAssertNil(live.cricketActivity)
        XCTAssertTrue(live.hasConfirmedLiveStatus)
        XCTAssertEqual(live.prominentStatusLabel, "LIVE")
        XCTAssertLessThan(CricketActivityPresentationPolicy.homePhaseRank(for: live), CricketActivityPresentationPolicy.homePhaseRank(for: future))
        XCTAssertLessThan(CricketActivityPresentationPolicy.homePhaseRank(for: future), CricketActivityPresentationPolicy.homePhaseRank(for: held))
    }
}
