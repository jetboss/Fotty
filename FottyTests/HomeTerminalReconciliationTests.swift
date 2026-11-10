import XCTest
@testable import Fotty

@MainActor
final class HomeTerminalReconciliationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_648_600)
    private var kickoff: Date { now.addingTimeInterval(-2 * 3600) }

    private func sportsEvent(
        _ status: SportsFixtureCatalog.Status,
        verified: Bool = true,
        observedAt: Date? = nil,
        id: String = "sports-fixture:premier-league:560595"
    ) -> EventReference {
        let metadata = SportsFixtureMetadata(
            fixtureID: id, sport: "football", competitionID: "premier-league",
            competitionName: "Premier League", eventKind: .match,
            title: "Chelsea vs Bournemouth",
            participants: [.init(id: "chelsea", name: "Chelsea", role: "home"),
                           .init(id: "bournemouth", name: "Bournemouth", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status,
            observedAt: observedAt ?? now, verified: verified
        )
        return .init(id: id, title: metadata.title, category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Chelsea", badge: nil), away: .init(name: "Bournemouth", badge: nil)),
            sources: [.init(source: "delta", id: "current-provider")], sportsFixture: metadata,
            competitionID: metadata.competitionID)
    }

    private func cricketEvent(
        _ status: CricketFixtureCatalog.Status,
        verified: Bool = true,
        observedAt: Date? = nil
    ) -> EventReference {
        let metadata = CricketFixtureMetadata(fixtureID: "icc:270273", competitionID: "west-indies",
            competitionName: "West Indies internationals", format: .t20, status: status,
            observedAt: observedAt ?? now, verified: verified)
        return .init(id: "cricket-fixture:icc:270273", title: "India vs West Indies", category: "cricket",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "India", badge: nil), away: .init(name: "West Indies", badge: nil)),
            sources: [.init(source: "delta", id: "current-cricket-provider")], cricketFixture: metadata)
    }

    private func provider(
        id: String = "provider-chelsea-bournemouth",
        start: Date? = nil,
        title: String = "Chelsea vs Bournemouth",
        home: String = "Chelsea",
        away: String = "Bournemouth",
        competition: String? = nil,
        conflict: Bool = false,
        sources: [NexusASource] = [.init(source: "delta", id: "current-provider")]
    ) -> EventReference {
        .init(id: id, title: title, category: "football",
            date: Int64((start ?? kickoff).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
            sources: sources, hasCatalogIdentityConflict: conflict, competitionID: competition)
    }

    private func terminalSnapshot(_ status: SportsFixtureCatalog.Status) -> SportsFixtureCatalog.Snapshot {
        let stamp: (Date) -> String = { ISO8601DateFormatter().string(from: $0) }
        let fixture = SportsFixtureCatalog.Fixture(
            id: "sports-fixture:premier-league:560595", sport: "football", start: stamp(kickoff),
            status: status, eventKind: .match, title: "Chelsea vs Bournemouth",
            competitionId: "premier-league", competitionName: "Premier League",
            participants: [.init(id: "chelsea", name: "Chelsea", role: "home"),
                           .init(id: "bournemouth", name: "Bournemouth", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"),
            source: .init(name: "Official schedule", url: "https://www.football-data.org/", observedAt: stamp(now))
        )
        return .init(schemaVersion: 1, complete: true, checkedAt: stamp(now), revision: "terminal-receipt",
            sourceStatus: .verified, fixtures: [fixture], coverage: [
                .init(sport: "football", competitionId: "premier-league", competitionName: "Premier League",
                    status: .covered, checkedAt: stamp(now), fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)
            ])
    }

    func testExpiredLiveReceiptRetainsFixtureInNeutralHomeSectionAfterRefreshAndRestart() throws {
        let event = sportsEvent(.live, observedAt: now.addingTimeInterval(-1801))
        let initial = HomeSportsDiscovery(events: [event], now: now) { _ in .inPlay }
        XCTAssertEqual(initial.homeSections(from: initial.items, diverseUpcoming: false,
            featuredLiveLimit: 3).featuredLive.map(\.id), [event.id])
        // Reconstruct from retained catalog, just as both refresh and cold start
        // do when the live-score receipt is no longer usable.
        for _ in 0..<2 {
            let refreshed = HomeSportsDiscovery(events: [event], now: now)
            let sections = refreshed.homeSections(from: refreshed.items, diverseUpcoming: false,
                featuredLiveLimit: 3, followedTeamKeys: [TeamFollowKey.make(name: "Chelsea", category: "football")])
            XCTAssertTrue(sections.featuredLive.isEmpty)
            XCTAssertTrue(sections.upcoming.isEmpty)
            XCTAssertEqual(sections.awaitingStatus.map(\.id), [event.id])
            XCTAssertEqual(try XCTUnwrap(sections.awaitingStatus.first).phase, .unconfirmed)
        }
    }

    func testNeutralHomeRetentionExpiresWithoutDeclaringFinishedOrIncludingFutureFixtures() {
        let event = sportsEvent(.scheduled, observedAt: now.addingTimeInterval(-1801))
        for date in [kickoff.addingTimeInterval(-1), kickoff.addingTimeInterval(4 * 3600)] {
            let home = HomeSportsDiscovery(events: [event], now: date)
            XCTAssertTrue(home.homeSections(from: home.items, diverseUpcoming: false,
                featuredLiveLimit: 3).awaitingStatus.isEmpty)
        }
    }

    func testRecoveredStatusMovesRetainedMatchBackToLiveWithoutDuplicatingIt() {
        let event = sportsEvent(.live)
        let home = HomeSportsDiscovery(events: [event], now: now)
        let sections = home.homeSections(from: home.items, diverseUpcoming: false, featuredLiveLimit: 3)
        XCTAssertEqual(sections.featuredLive.map(\.id), [event.id])
        XCTAssertTrue(sections.awaitingStatus.isEmpty)
    }

    func testTerminalEvidenceRemovesNeutralRetainedFixtureToo() {
        let event = sportsEvent(.scheduled, observedAt: now.addingTimeInterval(-1801))
        for state in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let home = HomeSportsDiscovery(events: [event], now: now, terminalEvents: [sportsEvent(state)])
            XCTAssertTrue(home.items.isEmpty)
            XCTAssertTrue(home.homeSections(from: home.items, diverseUpcoming: false,
                featuredLiveLimit: 3).awaitingStatus.isEmpty)
        }
    }

    func testVerifiedSportsTerminalFactsWinAcrossHomeAndMatchdayEvenAfterLaterInPlayScoreReceipt() {
        for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let event = sportsEvent(terminal, observedAt: now.addingTimeInterval(-60))
            let acceptedScore = HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now,
                liveFeedAvailable: true, now: now)
            XCTAssertEqual(acceptedScore, .inPlay, "A late active score observation still cannot resurrect accepted terminal facts")
            let home = HomeSportsDiscovery(events: [event], now: now) { _ in acceptedScore }
            XCTAssertTrue(home.items.isEmpty)
            XCTAssertEqual(home.activities.first { $0.id == "football" }?.confirmedLive, 0)
            XCTAssertEqual(home.activities.first { $0.id == "football" }?.onNow, 0)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: acceptedScore), .recent)
            XCTAssertEqual(MatchdayEventStatePolicy.presentationLabel(for: event, at: now, status: acceptedScore),
                           terminal == .finished ? "Finished" : "Cancelled")
        }
    }

    func testVerifiedCricketTerminalFactsWinAcrossHomeAndMatchday() {
        for terminal in [CricketFixtureCatalog.Status.finished, .cancelled] {
            let event = cricketEvent(terminal)
            let home = HomeSportsDiscovery(events: [event], now: now) { _ in .inPlay }
            XCTAssertTrue(home.items.isEmpty)
            XCTAssertEqual(home.activities.first { $0.id == "cricket" }?.confirmedLive, 0)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: .inPlay), .recent)
        }
    }

    func testHeldOrUnverifiedTerminalFactsGainNoPrecedenceOrRegistryVeto() throws {
        for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let event = sportsEvent(terminal, verified: false)
            let home = HomeSportsDiscovery(events: [event], now: now, terminalEvents: [event]) { _ in .inPlay }
            XCTAssertEqual(try XCTUnwrap(home.items.first).phase, .live)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: .inPlay), .live)
            XCTAssertEqual(HomeSportsDiscovery(events: [provider()], now: now, terminalEvents: [event]) { _ in .inPlay }.items.count, 1)
        }
        for terminal in [CricketFixtureCatalog.Status.finished, .cancelled] {
            let event = cricketEvent(terminal, verified: false)
            XCTAssertEqual(HomeSportsDiscovery(events: [event], now: now, terminalEvents: [event]) { _ in .inPlay }.items.count, 1)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: .inPlay), .live)
            let action = MatchStartPolicy(event: event, now: now, status: .inPlay)
            XCTAssertFalse(action.isStopped)
            XCTAssertTrue(action.canAttemptPlayback)
            XCTAssertEqual(action.title, "Watch", "Held cricket metadata cannot label a playable current score Finished or Cancelled")
        }
    }

    func testFutureTerminalReceiptCannotVetoCurrentScoreOrRegistryIdentity() throws {
        let future = now.addingTimeInterval(301)
        for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let event = sportsEvent(terminal, observedAt: future)
            let home = HomeSportsDiscovery(events: [event], now: now, terminalEvents: [event]) { _ in .inPlay }
            XCTAssertEqual(try XCTUnwrap(home.items.first).phase, .live)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: .inPlay), .live)
            XCTAssertEqual(HomeSportsDiscovery(events: [provider()], now: now, terminalEvents: [event]) { _ in .inPlay }.items.count, 1)
        }
        for terminal in [CricketFixtureCatalog.Status.finished, .cancelled] {
            let event = cricketEvent(terminal, observedAt: future)
            XCTAssertEqual(HomeSportsDiscovery(events: [event], now: now, terminalEvents: [event]) { _ in .inPlay }.items.count, 1)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now, status: .inPlay), .live)
            let action = MatchStartPolicy(event: event, now: now, status: .inPlay)
            XCTAssertFalse(action.isStopped)
            XCTAssertTrue(action.canAttemptPlayback)
            XCTAssertEqual(action.title, "Watch", "A future cricket terminal receipt has no playback-label authority")
        }
    }

    func testAcceptedTerminalFactsDoNotExpireIntoLiveWhenAnotherScoreArrivesLater() {
        let later = now.addingTimeInterval(7 * 86400)
        for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let event = sportsEvent(terminal)
            XCTAssertTrue(HomeSportsDiscovery(events: [event], now: later) { _ in .inPlay }.items.isEmpty)
            XCTAssertTrue(HomeSportsDiscovery(events: [provider()], now: later, terminalEvents: [event]) { _ in .inPlay }.items.isEmpty)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: later, status: .inPlay), .recent)
        }
    }

    func testSeparateTerminalRegistryVetoesRecreatedRows() throws {
        for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let receipt = terminalSnapshot(terminal)
            let raw = provider()
            let terminalEvents = SportsFixtureCatalog.terminalEvents(from: receipt)
            XCTAssertEqual(terminalEvents.count, 1)
            // Both an old provider list and source-free score synthesis can
            // arrive after terminal projection removed the original row.
            for recreated in [raw, provider(id: "official-score-560595", competition: "premier-league", sources: [])] {
                XCTAssertNil(recreated.sportsFixture)
                XCTAssertEqual(HomeSportsDiscovery(events: [recreated], now: now) { _ in .inPlay }.items.count, 1)
                let home = HomeSportsDiscovery(events: [recreated], now: now, terminalEvents: terminalEvents) { _ in .inPlay }
                XCTAssertTrue(home.items.isEmpty)
                XCTAssertEqual(home.activities.first { $0.id == "football" }?.confirmedLive, 0)
            }
        }
    }

    func testTerminalRegistryVetoPreservesRematchesAndContradictoryCompetitionSquadOrIdentity() {
        let terminal = sportsEvent(.finished)
        let independent = [
            provider(id: "next-week", start: kickoff.addingTimeInterval(7 * 86400)),
            provider(id: "swapped-participants", home: "Bournemouth", away: "Chelsea"),
            provider(id: "other-league", competition: "champions-league"),
            provider(id: "cup", title: "FA Cup · Chelsea vs Bournemouth"),
            provider(id: "youth", title: "Chelsea U19 vs Bournemouth U19")
        ]
        for row in independent {
            XCTAssertEqual(HomeSportsDiscovery(events: [row], now: now, terminalEvents: [terminal]) { _ in .inPlay }.items.count, 1, row.id)
        }
        let conflict = provider(id: "conflict", conflict: true)
        XCTAssertTrue(HomeSportsDiscovery.uniqueEvents([conflict]).first?.hasCatalogIdentityConflict == true,
                      "A terminal registry must not erase the original identity quarantine")
        XCTAssertTrue(HomeSportsDiscovery(events: [conflict], now: now) { _ in .inPlay }.items.isEmpty)
        XCTAssertTrue(HomeSportsDiscovery(events: [conflict], now: now, terminalEvents: [terminal]) { _ in .inPlay }.items.isEmpty,
                      "Quarantined identities stay hidden independently of terminal matching")
    }

    func testAmbiguousTerminalRegistryIdentityIsNotSilentlySelected() {
        let first = sportsEvent(.finished)
        let other = sportsEvent(.cancelled, id: "sports-fixture:premier-league:another")
        XCTAssertEqual(HomeSportsDiscovery(events: [provider()], now: now, terminalEvents: [first, other]) { _ in .inPlay }.items.count, 1)
    }

    func testNonterminalScoreOrderingAndSourceFreeRowsRemainUnchanged() throws {
        let nonterminal = sportsEvent(.scheduled)
        let home = HomeSportsDiscovery(events: [nonterminal], now: now, terminalEvents: [nonterminal]) { _ in .inPlay }
        XCTAssertEqual(try XCTUnwrap(home.items.first).phase, .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: nonterminal, at: now, status: .inPlay), .live)
        let sourceFree = provider(id: "source-free", start: now.addingTimeInterval(3600), sources: [])
        let scheduled = try XCTUnwrap(HomeSportsDiscovery(events: [sourceFree], now: now, terminalEvents: [sportsEvent(.finished)]).items.first)
        XCTAssertEqual(scheduled.phase, .upcoming)
        XCTAssertFalse(scheduled.canWatch)
    }
}
