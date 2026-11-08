import XCTest
@testable import Fotty

@MainActor
final class SportsSearchScheduleTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-29T14:00:00Z")!
    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func sportsFixture(_ id: String = "one", days: Double = 7,
                               status: SportsFixtureCatalog.Status = .scheduled,
                               verification: SportsFixtureCatalog.Source.Verification? = .verified,
                               home: String = "Arsenal", away: String = "Chelsea",
                               gender: SportsFixtureCatalog.Squad.Gender = .men,
                               ageGroup: String = "senior", observedAt: Date? = nil,
                               updatedAt: Date? = nil) -> SportsFixtureCatalog.Fixture {
        .init(id: "sports-fixture:premier-league:\(id)", sport: "football",
              start: stamp(now.addingTimeInterval(days * 86400)), status: status, eventKind: .match,
              title: "\(home) vs \(away)", competitionId: "premier-league", competitionName: "Premier League",
              participants: [.init(id: home.lowercased().replacingOccurrences(of: " ", with: "-"), name: home),
                             .init(id: away.lowercased().replacingOccurrences(of: " ", with: "-"), name: away)],
              squad: .init(gender: gender, ageGroup: ageGroup),
              source: .init(name: "Accepted official schedule", url: "https://example.test/fixtures",
                            observedAt: stamp(observedAt ?? now), updatedAt: updatedAt.map(stamp), verification: verification))
    }

    private func sportsSnapshot(_ fixtures: [SportsFixtureCatalog.Fixture],
                                status: SportsFixtureCatalog.SourceStatus = .verified,
                                receipt: Date? = nil, laneReceipt: Date? = nil,
                                coverage: SportsFixtureCatalog.Coverage.Status = .covered) -> SportsFixtureCatalog.Snapshot {
        .init(schemaVersion: 1, complete: true, checkedAt: stamp(receipt ?? now), revision: "sports-search",
              sourceStatus: status, fixtures: fixtures,
              coverage: [.init(sport: "football", competitionId: "premier-league", competitionName: "Premier League",
                               status: coverage, checkedAt: stamp(laneReceipt ?? receipt ?? now),
                               fixtureCount: fixtures.count, pendingFixtureCount: 0, nextStart: nil)])
    }

    private func cricketFixture(_ id: String = "cricket", days: Double = 8,
                                status: CricketFixtureCatalog.Status = .scheduled,
                                verification: CricketFixtureCatalog.Source.Verification? = .verified,
                                home: String = "West Indies", away: String = "India",
                                competition: String = "icc", observedAt: Date? = nil) -> CricketFixtureCatalog.Fixture {
        .init(id: id, start: stamp(now.addingTimeInterval(days * 86400)), format: .t20, status: status,
              competitionId: competition, competitionName: "ICC internationals",
              home: .init(id: "wi-\(id)", name: home), away: .init(id: "india-\(id)", name: away),
              source: .init(name: "Accepted official schedule", url: "https://example.test/cricket",
                            observedAt: stamp(observedAt ?? now), verification: verification))
    }

    private func cricketSnapshot(_ fixtures: [CricketFixtureCatalog.Fixture],
                                 status: CricketFixtureCatalog.SourceStatus = .verified,
                                 receipt: Date? = nil, laneReceipt: Date? = nil,
                                 coverage: CricketFixtureCatalog.Coverage.Status = .covered) -> CricketFixtureCatalog.Snapshot {
        let competitions = Set(fixtures.map(\.competitionId)).union(["icc"])
        return .init(schemaVersion: 1, complete: true, checkedAt: stamp(receipt ?? now), revision: "cricket-search",
                     sourceStatus: status, fixtures: fixtures,
                     coverage: competitions.sorted().map { competition in
                         .init(competitionId: competition, competitionName: "ICC internationals", status: coverage,
                               checkedAt: stamp(laneReceipt ?? receipt ?? now),
                               fixtureCount: fixtures.filter { $0.competitionId == competition }.count,
                               expectedFixtureCount: nil, nextStart: nil)
                     })
    }

    private func upcoming(_ row: SportsFixtureCatalog.Fixture) throws -> EventReference {
        try XCTUnwrap(SportsSearchSchedule.events(sports: sportsSnapshot([row]), cricket: nil, at: now).first)
    }

    func testAcceptedWeekAheadFixtureIsSearchableWithoutWideningHomeOrPromisingWatch() throws {
        let row = sportsFixture()
        let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(sportsSnapshot([row])), now: now)
        XCTAssertTrue(SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: now).isEmpty,
                      "The shared Home retention horizon remains three days")
        let scheduled = SportsSearchSchedule.events(sports: accepted, cricket: nil, at: now)
        let index = HomeSportsSearch.prepare(in: .init(events: [], now: now), scheduledEvents: scheduled) {
            $0.sportsFixture?.competitionName
        }
        let result = try XCTUnwrap(index.results(query: "Arsenal").first)
        guard case .fixture(let item) = result else { return XCTFail("Expected a planning fixture") }
        XCTAssertEqual(item.event.id, row.id)
        XCTAssertEqual(item.phase, .upcoming)
        XCTAssertFalse(item.canWatch)
        XCTAssertTrue(item.event.sources?.isEmpty == true)
        XCTAssertFalse(MatchStartPolicy(event: item.event, now: now).canAttemptPlayback)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: item.event, in: [], at: now))
        XCTAssertEqual(index.results(query: "Premier League").map(\.id), [row.id])
        XCTAssertEqual(CatalogTimingPolicy.retentionFutureHorizon, 72 * 3600)
    }

    func testSearchHorizonIncludesFourteenthDayButNeverPastOrFurtherFixtures() {
        let rows = [sportsFixture("past", days: -1), sportsFixture("now", days: 0),
                    sportsFixture("edge", days: 14), sportsFixture("beyond", days: 14 + 1.0 / 86400)]
        let events = SportsSearchSchedule.events(sports: sportsSnapshot(rows), cricket: nil, at: now)
        XCTAssertEqual(events.map(\.id), [rows[2].id])
    }

    func testCurrentEmptyScheduleDoesNotResurrectRemovedFixtures() {
        let previous = sportsSnapshot([sportsFixture()])
        XCTAssertEqual(SportsSearchSchedule.events(sports: previous, cricket: nil, at: now).count, 1)
        let accepted = SportsFixtureCatalog.accepting(sportsSnapshot([]), over: previous)
        XCTAssertTrue(SportsSearchSchedule.events(sports: accepted, cricket: nil, at: now).isEmpty)
        XCTAssertTrue(SportsSearchSchedule.events(sports: nil, cricket: nil, at: now).isEmpty)
    }

    func testSnapshotOrCompetitionReceiptExpiryDropsOnlySupplementalSearchRows() {
        let expired = now.addingTimeInterval(-24 * 3600 - 1)
        let future = now.addingTimeInterval(301)
        for receipt in [expired, future] {
            XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture()], receipt: receipt),
                                                      cricket: nil, at: now).isEmpty)
            XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture()], laneReceipt: receipt),
                                                      cricket: nil, at: now).isEmpty)
            XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
                cricket: cricketSnapshot([cricketFixture()], receipt: receipt), at: now).isEmpty)
            XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
                cricket: cricketSnapshot([cricketFixture()], laneReceipt: receipt), at: now).isEmpty)
            XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture(observedAt: receipt)]),
                                                      cricket: nil, at: now).isEmpty)
            XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
                cricket: cricketSnapshot([cricketFixture(observedAt: receipt)]), at: now).isEmpty,
                "A fresh aggregate/competition receipt cannot renew an old row observation")
        }
    }

    func testUnavailableLastKnownAndHeldSchedulesCannotAcquireSearchAuthority() {
        for status in [SportsFixtureCatalog.SourceStatus.unavailable, .lastKnownGood] {
            XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture()], status: status),
                                                      cricket: nil, at: now).isEmpty)
        }
        for status in [CricketFixtureCatalog.SourceStatus.unavailable, .lastKnownGood] {
            XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
                cricket: cricketSnapshot([cricketFixture()], status: status), at: now).isEmpty)
        }
        XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture(verification: .held)]),
                                                  cricket: nil, at: now).isEmpty)
        XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture()], status: .partial,
                                                  coverage: .unavailable), cricket: nil, at: now).isEmpty)
        XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
            cricket: cricketSnapshot([cricketFixture(verification: .held)]), at: now).isEmpty)
        XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
            cricket: cricketSnapshot([cricketFixture()], status: .partial, coverage: .unavailable), at: now).isEmpty)
    }

    func testFreshlyObservedUnchangedFutureFixtureDoesNotNeedANewPublisherChangeTimestamp() throws {
        let lastChange = now.addingTimeInterval(-7 * 86400)
        let row = sportsFixture(updatedAt: lastChange)
        let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(sportsSnapshot([row])), now: now)
        let found = try XCTUnwrap(SportsSearchSchedule.events(sports: accepted, cricket: nil, at: now).first)
        XCTAssertEqual(found.id, row.id)
        XCTAssertEqual(found.sportsFixture?.observedAt, lastChange,
                       "Search must preserve the original stricter LIVE-status metadata clock")
        XCTAssertFalse(found.sportsFixture?.isLive(at: now) ?? true)
        let index = HomeSportsSearch.prepare(in: .init(events: [], now: now), scheduledEvents: [found])
        XCTAssertEqual(index.results(query: "Arsenal").map(\.id), [row.id],
                       "A freshly rechecked unchanged fixture must survive the actual Search index")
        let stale = sportsFixture(observedAt: now.addingTimeInterval(-24 * 3600 - 1), updatedAt: lastChange)
        XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([stale]), cricket: nil, at: now).isEmpty,
                      "An unchanged publisher timestamp cannot excuse a stale source observation")
    }

    func testNonScheduledAndTerminalTombstonesAreNeverRecreatedAsUpcomingOrLive() {
        for status in [SportsFixtureCatalog.Status.live, .finished, .cancelled, .postponed, .unknown] {
            XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture(status: status)]),
                                                      cricket: nil, at: now).isEmpty, status.rawValue)
        }
        for status in [CricketFixtureCatalog.Status.live, .finished, .cancelled, .postponed, .unknown] {
            XCTAssertTrue(SportsSearchSchedule.events(sports: nil,
                cricket: cricketSnapshot([cricketFixture(status: status)]), at: now).isEmpty, status.rawValue)
        }
    }

    func testCricketAndFootballSquadsRemainDistinctAtTheSameKickoff() {
        let football = [sportsFixture("senior"),
                        sportsFixture("youth", home: "Arsenal U19", away: "Chelsea U19", ageGroup: "u19"),
                        sportsFixture("women", home: "Arsenal Women", away: "Chelsea Women", gender: .women)]
        let cricket = [cricketFixture("men"),
                       cricketFixture("women", home: "West Indies Women", away: "India Women")]
        let rows = SportsSearchSchedule.events(sports: sportsSnapshot(football), cricket: cricketSnapshot(cricket), at: now)
        XCTAssertEqual(rows.count, 5)
        let index = HomeSportsSearch.prepare(in: .init(events: [], now: now), scheduledEvents: rows)
        XCTAssertEqual(index.results(query: "Arsenal U19").map(\.id), [football[1].id])
        XCTAssertEqual(index.results(query: "West Indies Women").map(\.id), ["cricket-fixture:women"])
        XCTAssertEqual(rows.first { $0.id == football[2].id }?.sportsFixture?.squad.gender, .women)
    }

    func testCPLNeedsItsOwnFreshReceiptAndCannotBorrowAnICCCohort() {
        let fixtures: [CPLSchedule.Fixture] = [
            .init(1, stamp(now.addingTimeInterval(86400)), .trinbago, .guyana),
            .init(2, stamp(now.addingTimeInterval(7 * 86400)), .barbados, .saintLucia)
        ]
        let cricket = cricketSnapshot([cricketFixture("cpl-copy", days: 7, competition: "cpl")])
        XCTAssertTrue(SportsSearchSchedule.events(sports: nil, cricket: cricket, cpl: fixtures, at: now).isEmpty)
        for status in [CPLSchedule.SourceStatus.verified, .liveVerified] {
            let events = SportsSearchSchedule.events(sports: nil, cricket: cricket, cpl: fixtures,
                cplCheckedAt: now, cplSourceStatus: status, at: now)
            XCTAssertEqual(events.map(\.id), fixtures.map(\.id))
            XCTAssertTrue(events.allSatisfy { $0.sources?.isEmpty == true })
        }
        XCTAssertTrue(SportsSearchSchedule.events(sports: nil, cricket: nil, cpl: fixtures,
            cplCheckedAt: now, cplSourceStatus: .lastKnownGood, at: now).isEmpty)
        XCTAssertTrue(SportsSearchSchedule.events(sports: nil, cricket: nil, cpl: fixtures,
            cplCheckedAt: now.addingTimeInterval(-7201), cplSourceStatus: .verified, at: now).isEmpty)
    }

    func testSearchPreservesCurrentBroadcastAndDeduplicatesItsScheduleCopy() throws {
        let row = sportsFixture(days: 1)
        let scheduled = try upcoming(row)
        let broadcast = EventReference(id: scheduled.id, title: scheduled.title, category: scheduled.category,
            date: scheduled.date, poster: nil, popular: false, teams: scheduled.teams,
            sources: [.init(source: "delta", id: "current-broadcast")], sportsFixture: scheduled.sportsFixture,
            competitionID: scheduled.competitionID)
        let discovery = HomeSportsDiscovery(events: [broadcast], now: now)
        let index = HomeSportsSearch.prepare(in: discovery, scheduledEvents: [scheduled, scheduled])
        let results = index.results(query: "Arsenal")
        XCTAssertEqual(results.map(\.id), [broadcast.id])
        XCTAssertEqual(results.first?.event.sources?.map(\.id), ["current-broadcast"])
        XCTAssertEqual(discovery.items.count, 1, "Search must not mutate Home's projection")
    }

    func testSupplementRejectsSourcesChannelsAndConflictingIDs() throws {
        let row = try upcoming(sportsFixture())
        let sourceBearing = EventReference(id: row.id, title: row.title, category: row.category, date: row.date,
            poster: nil, popular: false, teams: row.teams, sources: [.init(source: "delta", id: "unreviewed")],
            sportsFixture: row.sportsFixture, competitionID: row.competitionID)
        let quarantined = EventReference(id: row.id, title: row.title, category: row.category, date: row.date,
            poster: nil, popular: false, teams: row.teams, sources: [], hasCatalogIdentityConflict: true,
            sportsFixture: row.sportsFixture, competitionID: row.competitionID)
        let channel = EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: -3_600_000,
            poster: nil, popular: false, teams: nil, sources: [.init(source: "delta", id: "willow")])
        let index = HomeSportsSearch.prepare(in: .init(events: [], now: now),
                                            scheduledEvents: [sourceBearing, quarantined, channel])
        XCTAssertTrue(index.results(query: "Arsenal").isEmpty)
        XCTAssertTrue(index.results(query: "Willow").isEmpty)
        let currentChannels = HomeSportsSearch.prepare(in: .init(events: [channel], now: now), scheduledEvents: [row])
        XCTAssertEqual(currentChannels.results(query: "Willow").map(\.id), [channel.id])
    }

    func testDuplicateScheduleRowsCollapseButContradictorySameIdentityIsQuarantined() throws {
        let row = sportsFixture()
        let repeated = SportsSearchSchedule.events(sports: sportsSnapshot([row, row]), cricket: nil, at: now)
        XCTAssertEqual(repeated.map(\.id), [row.id])
        let conflicting = sportsFixture(home: "Liverpool", away: "Everton")
        XCTAssertTrue(SportsSearchSchedule.events(sports: sportsSnapshot([row, conflicting]), cricket: nil, at: now).isEmpty)
        let one = try upcoming(row)
        let two = try upcoming(conflicting)
        let index = HomeSportsSearch.prepare(in: .init(events: [], now: now), scheduledEvents: [one, two])
        XCTAssertTrue(index.results(query: "Arsenal").isEmpty)
        XCTAssertTrue(index.results(query: "Liverpool").isEmpty)
    }

    func testSupplementalScheduleCannotRecreateFutureFixtureCancelledByCurrentScoreReceipt() async throws {
        let event = try upcoming(sportsFixture(days: 1))
        let score = EventReference(id: "score-123", title: "Arsenal FC vs Chelsea FC", category: "football",
            date: event.date, poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal FC", badge: nil), away: .init(name: "Chelsea FC", badge: nil)), sources: [])
        XCTAssertTrue(HomeSportsSearch.scoreIdentityMatches(event, score: score))
        for terminal in [FootballMatch.MatchStatus.cancelled, .finished] {
            let home = HomeSportsDiscovery(events: [event], now: now, status: { _ in terminal })
            XCTAssertTrue(home.items.isEmpty)
            let index = HomeSportsSearch.prepare(in: home, scheduledEvents: [event], status: { candidate in
                HomeSportsSearch.scoreIdentityMatches(candidate, score: score) ? terminal : nil
            })
            XCTAssertTrue(index.results(query: "Arsenal").isEmpty,
                          "A lagging scheduled snapshot must not undo Home's terminal veto")
            let cooperative = await HomeSportsSearch.prepareForQuery(in: home, query: "Arsenal", scheduledEvents: [event],
                status: { candidate in HomeSportsSearch.scoreIdentityMatches(candidate, score: score) ? terminal : nil },
                timing: .init(monotonicNow: { 0 }, sleep: { _ in }))
            XCTAssertTrue(try XCTUnwrap(cooperative).results(query: "Arsenal").isEmpty)
        }
    }

    func testSupplementalScoreVetoRequiresExactDatedPairAndSquad() throws {
        let event = try upcoming(sportsFixture(days: 1))
        func score(_ home: String = "Arsenal", _ away: String = "Chelsea", offset: TimeInterval = 0) -> EventReference {
            .init(id: "score-other", title: "\(home) vs \(away)", category: "football",
                  date: Int64(event.kickoffDate!.addingTimeInterval(offset).timeIntervalSince1970),
                  poster: nil, popular: false,
                  teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), sources: [])
        }
        XCTAssertTrue(HomeSportsSearch.scoreIdentityMatches(event, score: score(offset: 15 * 60)))
        for unrelated in [score(offset: 15 * 60 + 1), score(offset: 18 * 3600),
                          score("Arsenal U19", "Chelsea U19"), score("Arsenal Women", "Chelsea Women"),
                          score("Liverpool", "Everton")] {
            XCTAssertFalse(HomeSportsSearch.scoreIdentityMatches(event, score: unrelated))
            let index = HomeSportsSearch.prepare(in: .init(events: [], now: now), scheduledEvents: [event], status: { candidate in
                HomeSportsSearch.scoreIdentityMatches(candidate, score: unrelated) ? .cancelled : nil
            })
            XCTAssertEqual(index.results(query: "Arsenal").map(\.id), [event.id],
                           "Another day's fixture or another squad must not cancel this planning result")
        }
    }

    func testCooperativePreparationIncludesScheduleAndInvalidatesOnScheduleRevision() async throws {
        let schedule = SportsSearchSchedule.events(sports: sportsSnapshot([sportsFixture()]),
                                                  cricket: cricketSnapshot([cricketFixture()]), at: now)
        let discovery = HomeSportsDiscovery(events: [], now: now)
        let index = await HomeSportsSearch.prepareForQuery(in: discovery, query: "India", scheduledEvents: schedule,
            timing: .init(monotonicNow: { 0 }, sleep: { _ in }))
        let prepared = try XCTUnwrap(index)
        XCTAssertEqual(prepared.results(query: "India").map(\.id), ["cricket-fixture:cricket"])
        XCTAssertEqual(prepared.results(query: "Arsenal").map(\.id), ["sports-fixture:premier-league:one"])
        let previous = SportsSearchIndexKey(catalogRevision: 4, clockDate: now, scoreRevision: nil, scheduleRevision: 1)
        let next = SportsSearchIndexKey(catalogRevision: 4, clockDate: now, scoreRevision: nil, scheduleRevision: 2)
        XCTAssertNotEqual(previous, next, "A fixture-only refresh must invalidate Search even before Home republishes")
    }

    func testViewModelSearchReadsAcceptedSnapshotsWithoutFetchingOrChangingHome() async throws {
        var requests = 0, scheduleRequests = 0
        let accepted = sportsSnapshot([sportsFixture()])
        let model = MatchListViewModel(fetchSnapshot: {
            requests += 1
            return .init(events: [], checkedAt: self.now, source: "controlled", respondingFeeds: 1,
                         attemptedFeeds: 1, isPartial: false)
        }, refreshSports: { scheduleRequests += 1; return accepted }, now: { self.now })
        await model.refresh()
        XCTAssertTrue(model.matches.isEmpty)
        for _ in 0..<4 {
            let events = model.searchSchedule(at: now)
            XCTAssertEqual(events.map(\.id), accepted.fixtures.map(\.id))
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(scheduleRequests, 1, "Search is a presentation projection, not a new request owner")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertTrue(model.searchSchedule(at: now.addingTimeInterval(24 * 3600 + 1)).isEmpty,
                      "An index rebuild must evaluate current receipt age rather than its original clock")
    }

    func testViewModelRetainsHiddenIdentityConflictVetoWhenSupplementingSearch() async {
        let accepted = sportsSnapshot([sportsFixture()])
        let row = accepted.fixtures[0]
        let conflict = EventReference(id: row.id, title: row.title, category: row.sport,
            date: Int64(row.kickoff!.timeIntervalSince1970), poster: nil, popular: false, teams: nil,
            sources: [], hasCatalogIdentityConflict: true)
        let model = MatchListViewModel(fetchSnapshot: {
            .init(events: [conflict], checkedAt: self.now, source: "controlled", respondingFeeds: 1,
                  attemptedFeeds: 1, isPartial: false)
        }, refreshSports: { accepted }, now: { self.now })
        await model.refresh()
        XCTAssertEqual(model.identityConflicts.map(\.id), [row.id])
        XCTAssertTrue(model.searchSchedule(at: now).isEmpty,
                      "Home hiding a conflict must not permit Search to recreate the same ID")
    }
}
