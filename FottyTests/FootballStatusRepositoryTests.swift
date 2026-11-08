import XCTest
@testable import Fotty

/// Source receipts and explicit terminal facts are exercised without networking,
/// shared singleton injection, sleeps, provider quota or device mutation.
final class FootballStatusRepositoryTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_802_160_000)

    func testOfficialMapperCarriesRecentExplicitTerminalFactsWithoutInferringDisappearance() throws {
        let rows = try officialRows(at: instant)
        XCTAssertEqual(rows.map(\.fixture.id), ["900000001", "900000002", "900000003"])
        XCTAssertEqual(rows.map(\.fixture.status), [.live, .fullTime, .fullTime])
        XCTAssertTrue(rows.allSatisfy { $0.lastUpdated == instant && $0.fixture.lastUpdated == instant })
        XCTAssertTrue(OfficialFPLScoreProvider.mapLiveFixtures([], teams: try teams(), fetchedAt: instant).isEmpty)
    }

    func testOfficialLiveAndFinalArtworkUsesStableCodeNotSeasonalTeamID() throws {
        let rows = try officialRows(at: instant)
        XCTAssertEqual(rows.map(\.fixture.status), [.live, .fullTime, .fullTime])
        for row in rows {
            XCTAssertEqual(row.homeTeam.id, "1")
            XCTAssertEqual(row.awayTeam.id, "2")
            XCTAssertEqual(row.homeTeam.crestURL?.absoluteString,
                "https://resources.premierleague.com/premierleague/badges/100/t101.png")
            XCTAssertEqual(row.awayTeam.crestURL?.absoluteString,
                "https://resources.premierleague.com/premierleague/badges/100/t202.png")
        }
    }

    func testMatchingOfficialLiveAndFinalKeepScheduleIdentityAndOfficialArtwork() async throws {
        let clock = StatusTestClock(instant)
        let scheduled = hub(.scheduled, observedAt: instant,
            homeID: "schedule-home", awayID: "schedule-away")
        let official = StatusProviderProbe([
            .rows([try XCTUnwrap(officialRows(at: instant).first)]),
            .rows([try XCTUnwrap(officialRows(at: instant.addingTimeInterval(60), firstFinished: true).first)])
        ])
        let repo = repository(clock: clock, schedule: StatusScheduleProbe([[scheduled]]), official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        let liveSnapshot = try await repo.getLiveSnapshot()
        let live = try XCTUnwrap(liveSnapshot.matches.first)
        clock.advance(60)
        let finalSnapshot = try await repo.getLiveSnapshot()
        let final = try XCTUnwrap(finalSnapshot.matches.first)
        XCTAssertEqual(live.fixture.status, .live)
        XCTAssertEqual(final.fixture.status, .fullTime)
        for row in [live, final] {
            XCTAssertEqual(row.fixture.id, scheduled.fixture.id)
            XCTAssertEqual(row.fixture.utcDate, scheduled.fixture.utcDate)
            XCTAssertEqual(row.homeTeam.id, "schedule-home")
            XCTAssertEqual(row.awayTeam.id, "schedule-away")
            XCTAssertEqual(row.homeTeam.name, scheduled.homeTeam.name)
            XCTAssertEqual(row.homeTeam.shortName, scheduled.homeTeam.shortName)
            XCTAssertEqual(row.homeTeam.crestURL?.absoluteString,
                "https://resources.premierleague.com/premierleague/badges/100/t101.png")
            XCTAssertEqual(row.awayTeam.crestURL?.absoluteString,
                "https://resources.premierleague.com/premierleague/badges/100/t202.png")
        }
    }

    func testLiveObservationNeverOverwritesAuthoritativeScheduleCache() async throws {
        let clock = StatusTestClock(instant)
        let schedule = StatusScheduleProbe([[hub(.scheduled, observedAt: instant)]])
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)])])
        let repo = repository(clock: clock, schedule: schedule, official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        let live = try await repo.getLiveSnapshot()
        let after = try await repo.getScheduleSnapshot(dateRange: window)
        XCTAssertEqual(live.matches.first?.fixture.status, .live)
        XCTAssertEqual(after.matches.first?.fixture.status, .scheduled)
        XCTAssertEqual(after.observedAt, instant)
        XCTAssertEqual(schedule.calls, 1)
    }

    func testHealthyLiveToExplicitFinishedUpdatesTheSameScheduleIdentity() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([
            .rows([hub(.live, id: "900000001", observedAt: instant)]),
            .rows([hub(.fullTime, id: "900000001", observedAt: instant.addingTimeInterval(60))])
        ])
        let repo = repository(clock: clock,
            schedule: StatusScheduleProbe([[hub(.scheduled, id: "100", observedAt: instant)]]), official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        let live = try await repo.getLiveSnapshot()
        clock.advance(60)
        let finished = try await repo.getLiveSnapshot()
        XCTAssertEqual(live.matches.first?.fixture.id, "100")
        XCTAssertEqual(finished.matches.first?.fixture.id, "100")
        XCTAssertEqual(finished.matches.first?.fixture.status, .fullTime)
        XCTAssertEqual(finished.observedAt, clock.now)
        XCTAssertTrue(finished.refreshSucceeded)
    }

    func testSuccessfulEmptyRevokesActiveMembershipWithoutManufacturingFullTime() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)]), .rows([])])
        let repo = repository(clock: clock,
            schedule: StatusScheduleProbe([[hub(.scheduled, observedAt: instant)]]), official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        _ = try await repo.getLiveSnapshot()
        clock.advance(60)
        let empty = try await repo.getLiveSnapshot()
        let schedule = try await repo.getScheduleSnapshot(dateRange: window)
        XCTAssertTrue(empty.matches.isEmpty)
        XCTAssertTrue(empty.refreshSucceeded)
        XCTAssertEqual(empty.mode, .officialFPL)
        XCTAssertEqual(empty.observedAt, clock.now)
        XCTAssertEqual(schedule.matches.first?.fixture.status, .scheduled)
        let cached = try await repo.getLiveSnapshot()
        XCTAssertTrue(cached.matches.isEmpty)
        XCTAssertEqual(official.calls, 2)
    }

    func testFreshFinishedScheduleWinsAnOlderActiveCacheAndDoesNotRenewItsReceipt() async throws {
        let clock = StatusTestClock(instant)
        let pending = hub(.scheduled, id: "other", observedAt: instant,
            home: "Chelsea", away: "Bournemouth", kickoff: instant.addingTimeInterval(60))
        let schedule = StatusScheduleProbe([
            [hub(.scheduled, observedAt: instant), pending],
            [hub(.fullTime, observedAt: instant.addingTimeInterval(10)), pending]
        ])
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)])])
        let repo = repository(clock: clock, schedule: schedule, official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        _ = try await repo.getLiveSnapshot()
        clock.advance(10)
        await repo.invalidateScheduleListCache()
        let latestSchedule = try await repo.getScheduleSnapshot(dateRange: window)
        let cachedLive = try await repo.getLiveSnapshot()
        XCTAssertEqual(latestSchedule.matches.first?.fixture.status, .fullTime)
        XCTAssertEqual(cachedLive.matches.first?.fixture.status, .fullTime)
        XCTAssertEqual(cachedLive.observedAt, instant)
        XCTAssertEqual(official.calls, 1, "The terminal schedule fact must also beat the TTL-cached live row")
    }

    func testRepeatedAllSourceFailuresAndFailureCooldownRetainOriginalObservation() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)]), .failure(.serverError(502)), .failure(.serverError(502))])
        let primary = StatusProviderProbe([.failure(.serverError(502)), .failure(.serverError(502))])
        let fallback = StatusProviderProbe([.failure(.serverError(502)), .failure(.serverError(502))])
        let repo = repository(clock: clock, official: official, primary: primary, fallback: fallback)
        let first = try await repo.getLiveSnapshot()
        clock.advance(60)
        let failed = try await repo.getLiveSnapshot()
        clock.advance(30)
        let cooldown = try await repo.getLiveSnapshot()
        clock.advance(100)
        let failedAgain = try await repo.getLiveSnapshot()
        for snapshot in [failed, cooldown, failedAgain] {
            XCTAssertEqual(snapshot.observedAt, first.observedAt)
            XCTAssertEqual(snapshot.mode, .unavailable)
            XCTAssertFalse(snapshot.refreshSucceeded)
            XCTAssertEqual(snapshot.matches.first?.fixture.status, .live, "Retained data stays honest; failure is not full-time evidence")
        }
        XCTAssertEqual(official.calls, 3)
        XCTAssertEqual(primary.calls, 2)
        XCTAssertEqual(fallback.calls, 2)
    }

    func testSuccessfulRateLimitedFallbackCooldownStillPreservesSuccessfulReceipt() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.failure(.serverError(502))])
        let primary = StatusProviderProbe([.failure(.rateLimited)])
        let fallback = StatusProviderProbe([.rows([hub(.live, observedAt: instant.addingTimeInterval(-30))])])
        let repo = repository(clock: clock, official: official, primary: primary, fallback: fallback)
        let first = try await repo.getLiveSnapshot()
        clock.advance(60)
        let cached = try await repo.getLiveSnapshot()
        XCTAssertTrue(cached.refreshSucceeded)
        XCTAssertEqual(cached.mode, .quotaFallback)
        XCTAssertEqual(cached.observedAt, first.observedAt)
        XCTAssertEqual(cached.observedAt, instant.addingTimeInterval(-30))
        XCTAssertEqual(fallback.calls, 1)
    }

    func testRepeatedSuccessfulReplayCannotMakeExpiredSourceReceiptFresh() async throws {
        let clock = StatusTestClock(instant)
        let original = instant.addingTimeInterval(-601)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: original)]), .rows([hub(.live, observedAt: original)])])
        let repo = repository(clock: clock, official: official)
        let first = try await repo.getLiveSnapshot()
        clock.advance(60)
        let replay = try await repo.getLiveSnapshot()
        XCTAssertEqual(first.observedAt, original)
        XCTAssertEqual(replay.observedAt, original)
        XCTAssertTrue(replay.refreshSucceeded, "A successful resource read is distinct from whether its evidence is still current")
        XCTAssertGreaterThan(clock.now.timeIntervalSince(try XCTUnwrap(replay.observedAt)), 600)
    }

    func testFutureDatedLiveReceiptsAreRejectedInsteadOfCachedAsFresh() async throws {
        let clock = StatusTestClock(instant)
        let future = hub(.live, observedAt: instant.addingTimeInterval(1))
        let official = StatusProviderProbe([.rows([future])])
        let primary = StatusProviderProbe([.failure(.serverError(502))])
        let fallback = StatusProviderProbe([.failure(.serverError(502))])
        let repo = repository(clock: clock, official: official, primary: primary, fallback: fallback)
        do {
            _ = try await repo.getLiveSnapshot()
            XCTFail("No accepted cache may be created from a future source receipt")
        } catch { XCTAssertFalse(error is CancellationError) }
        let mode = await repo.currentLiveFeedMode()
        XCTAssertEqual(mode, .unavailable)
        XCTAssertEqual(primary.calls, 1)
    }

    func testFutureDatedScheduleIsRejectedAndDoesNotPoisonRecovery() async throws {
        let clock = StatusTestClock(instant)
        let schedule = StatusScheduleProbe([[hub(.live, observedAt: instant.addingTimeInterval(1))], [hub(.fullTime, observedAt: instant)]])
        let repo = repository(clock: clock, schedule: schedule, official: StatusProviderProbe([]))
        do {
            _ = try await repo.getScheduleSnapshot(dateRange: window)
            XCTFail("Future schedule receipts must not count as an observed fixture status")
        } catch {
            guard case FootballProviderError.staleData = error else {
                return XCTFail("Expected an invalid source receipt, got \(error)")
            }
        }
        let recovered = try await repo.getScheduleSnapshot(dateRange: window)
        XCTAssertEqual(recovered.matches.first?.fixture.status, .fullTime)
        XCTAssertEqual(schedule.calls, 2)
    }

    func testCancelledLiveReadDoesNotFallThroughOrAlterAcceptedCache() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)]), .cancelled])
        let primary = StatusProviderProbe([.rows([])])
        let fallback = StatusProviderProbe([.rows([])])
        let repo = repository(clock: clock, official: official, primary: primary, fallback: fallback)
        let first = try await repo.getLiveSnapshot()
        clock.advance(60)
        do {
            _ = try await repo.getLiveSnapshot()
            XCTFail("Transport cancellation must propagate")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
        XCTAssertEqual(primary.calls, 0)
        XCTAssertEqual(fallback.calls, 0)
        let mode = await repo.currentLiveFeedMode()
        XCTAssertEqual(mode, first.mode)
    }

    func testScheduleTTLReusePreservesItsOriginalSourceObservation() async throws {
        let clock = StatusTestClock(instant)
        let observed = instant.addingTimeInterval(-60)
        let schedule = StatusScheduleProbe([[hub(.scheduled, observedAt: observed)], [hub(.fullTime, observedAt: instant.addingTimeInterval(901))]])
        let repo = repository(clock: clock, schedule: schedule, official: StatusProviderProbe([]))
        let first = try await repo.getScheduleSnapshot(dateRange: window)
        clock.advance(899)
        let cached = try await repo.getScheduleSnapshot(dateRange: window)
        XCTAssertEqual(cached.observedAt, first.observedAt)
        XCTAssertEqual(cached.observedAt, observed)
        XCTAssertEqual(schedule.calls, 1)
        clock.advance(2)
        let expired = try await repo.getScheduleSnapshot(dateRange: window)
        XCTAssertEqual(expired.matches.first?.fixture.status, .fullTime)
        XCTAssertEqual(schedule.calls, 2)
    }

    func testAutomaticDetailsAdvancesLiveToExplicitFinalWithoutProviderRequests() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)]),
            .rows([hub(.fullTime, observedAt: instant.addingTimeInterval(60))])])
        let primary = StatusProviderProbe([])
        let repo = repository(clock: clock,
            schedule: StatusScheduleProbe([[hub(.scheduled, observedAt: instant)]]), official: official, primary: primary)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        _ = try await repo.getLiveSnapshot()
        let live = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        clock.advance(60)
        _ = try await repo.getLiveSnapshot()
        let final = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        XCTAssertEqual(live.match.fixture.status, .live)
        XCTAssertEqual(final.match.fixture.status, .fullTime)
        XCTAssertEqual(final.match.fixture.id, "100")
        XCTAssertEqual(final.match.lastUpdated, clock.now)
        XCTAssertEqual(primary.calls, 0, "Automatic Details must not spend a new provider request")
    }

    func testAutomaticDetailsSuccessfulEmptyRevokesOldRawLiveButPreservesContent() async throws {
        let clock = StatusTestClock(instant)
        let news = FottyTeamNewsItem(id: "story", teamName: "Sunderland", title: "Accepted team report", source: nil, url: nil, publishedAt: instant)
        let active = hub(.live, observedAt: instant, news: [news])
        let official = StatusProviderProbe([.rows([active]), .rows([])])
        let repo = repository(clock: clock, schedule: StatusScheduleProbe([[active]]), official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        _ = try await repo.getLiveSnapshot()
        clock.advance(60)
        _ = try await repo.getLiveSnapshot()
        let details = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        XCTAssertEqual(details.match.fixture.status, .unknown)
        XCTAssertEqual(details.match.lastUpdated, instant)
        XCTAssertEqual(details.match.teamNews.map(\.id), ["story"])
        XCTAssertEqual(details.match.score.away, 2)
        XCTAssertFalse(details.match.fixture.status.isFinished)
    }

    func testAutomaticDetailsFailedPollsCannotRetainLiveThroughHubCache() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)]), .failure(.serverError(502)), .failure(.serverError(502))])
        let repo = repository(clock: clock, official: official)
        _ = try await repo.getLiveSnapshot()
        let before = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        XCTAssertEqual(before.match.fixture.status, .live)
        clock.advance(60)
        _ = try await repo.getLiveSnapshot()
        let first = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        clock.advance(121)
        _ = try await repo.getLiveSnapshot()
        let repeated = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        for details in [first, repeated] {
            XCTAssertEqual(details.match.fixture.status, .unknown)
            XCTAssertEqual(details.match.lastUpdated, instant)
            XCTAssertEqual(details.match.score.away, 2)
            XCTAssertFalse(details.match.fixture.status.isFinished)
        }
    }

    func testAutomaticDetailsExpiresLiveBySourceReceiptWithoutARefreshAttempt() async throws {
        let clock = StatusTestClock(instant)
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant)])])
        let repo = repository(clock: clock, official: official)
        _ = try await repo.getLiveSnapshot()
        clock.advance(601)
        let expired = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        XCTAssertEqual(expired.match.fixture.status, .unknown)
        XCTAssertEqual(expired.match.lastUpdated, instant)
        XCTAssertEqual(official.calls, 1)
    }

    func testAutomaticFinalDetailsPreservesEarlierEnrichmentAndIdentity() async throws {
        let clock = StatusTestClock(instant)
        let news = FottyTeamNewsItem(id: "story", teamName: "Sunderland", title: "Accepted team report", source: nil, url: nil, publishedAt: instant)
        let pending = hub(.scheduled, id: "other", observedAt: instant,
            home: "Chelsea", away: "Bournemouth", kickoff: instant.addingTimeInterval(60))
        let schedule = StatusScheduleProbe([[hub(.scheduled, observedAt: instant), pending],
            [hub(.fullTime, observedAt: instant.addingTimeInterval(10)), pending]])
        let official = StatusProviderProbe([.rows([hub(.live, observedAt: instant, news: [news])])])
        let repo = repository(clock: clock, schedule: schedule, official: official)
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        _ = try await repo.getLiveSnapshot()
        clock.advance(10)
        await repo.invalidateScheduleListCache()
        _ = try await repo.getScheduleSnapshot(dateRange: window)
        let final = try await repo.matchHubSnapshot(fixtureId: "100", policy: .automatic)
        XCTAssertEqual(final.match.fixture.status, .fullTime)
        XCTAssertEqual(final.match.fixture.id, "100")
        XCTAssertEqual(final.match.teamNews.map(\.id), ["story"])
    }

    private var window: ClosedRange<Date> { instant.addingTimeInterval(-86400)...instant.addingTimeInterval(86400) }

    private func repository(clock: StatusTestClock, schedule: StatusScheduleProbe? = nil,
                            official: StatusProviderProbe, primary: StatusProviderProbe? = nil,
                            fallback: StatusProviderProbe? = nil) -> FootballRepository {
        let loader: (@Sendable (ClosedRange<Date>) async throws -> [MatchHubData])?
        if let schedule {
            loader = { range in try schedule.load(range) }
        } else {
            loader = nil
        }
        return FootballRepository(scheduleLoader: loader,
            primaryProvider: primary ?? StatusProviderProbe([]), officialFPLScoreProvider: official,
            footballDataProvider: fallback ?? StatusProviderProbe([]), now: { clock.now })
    }

    private func hub(_ status: FottyMatchStatus, id: String = "100", observedAt: Date,
                     home: String = "Sunderland", away: String = "Brighton", kickoff: Date? = nil,
                     news: [FottyTeamNewsItem] = [], homeID: String = "1", awayID: String = "2") -> MatchHubData {
        MatchHubData(fixture: FottyFixture(id: id, utcDate: kickoff ?? instant.addingTimeInterval(-3600),
            status: status, competition: .init(id: "39", name: "Premier League", country: "England", emblemURL: nil),
            venue: nil, matchday: 8, lastUpdated: observedAt),
            homeTeam: .init(id: homeID, name: home, shortName: nil, crestURL: nil, color: nil),
            awayTeam: .init(id: awayID, name: away, shortName: nil, crestURL: nil, color: nil),
            score: .init(home: 0, away: 2, aggregateHome: nil, aggregateAway: nil, periodScores: nil),
            events: [], homeLineup: nil, awayLineup: nil, statistics: [], teamNews: news,
            lastUpdated: observedAt, dataQuality: .official)
    }

    private func teams() throws -> [FPLTeam] {
        let json = """
        [{"id":1,"name":"Sunderland","short_name":"SUN","code":101,"strength":3,"strength_overall_home":3,"strength_overall_away":3,"strength_attack_home":3,"strength_attack_away":3,"strength_defence_home":3,"strength_defence_away":3},
         {"id":2,"name":"Brighton","short_name":"BHA","code":202,"strength":3,"strength_overall_home":3,"strength_overall_away":3,"strength_attack_home":3,"strength_attack_away":3,"strength_defence_home":3,"strength_defence_away":3}]
        """
        return try JSONDecoder().decode([FPLTeam].self, from: Data(json.utf8))
    }

    private func officialRows(at date: Date, firstFinished: Bool = false) throws -> [MatchHubData] {
        let formatter = ISO8601DateFormatter()
        func fixture(_ id: Int, started: Bool, finished: Bool, provisional: Bool, offset: TimeInterval) -> String {
            "{\"id\":\(id),\"event\":8,\"kickoff_time\":\"\(formatter.string(from: date.addingTimeInterval(offset)))\",\"team_h\":1,\"team_a\":2,\"team_h_score\":0,\"team_a_score\":2,\"team_h_difficulty\":3,\"team_a_difficulty\":3,\"started\":\(started),\"finished\":\(finished),\"finished_provisional\":\(provisional),\"minutes\":90}"
        }
        let json = "[" + [fixture(1, started: true, finished: firstFinished, provisional: firstFinished, offset: -3600),
            fixture(2, started: true, finished: false, provisional: true, offset: -7200),
            fixture(3, started: true, finished: true, provisional: true, offset: -86400),
            fixture(4, started: true, finished: true, provisional: true, offset: -4 * 86400),
            fixture(5, started: false, finished: true, provisional: true, offset: 3600),
            fixture(6, started: false, finished: false, provisional: false, offset: 3600)].joined(separator: ",") + "]"
        let fixtures = try JSONDecoder().decode([FPLFixture].self, from: Data(json.utf8))
        return OfficialFPLScoreProvider.mapLiveFixtures(fixtures, teams: try teams(), fetchedAt: date)
    }
}

private final class StatusTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(interval) }
}

private final class StatusScheduleProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [[MatchHubData]]
    private var count = 0
    init(_ replies: [[MatchHubData]]) { self.replies = replies }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func load(_ range: ClosedRange<Date>) throws -> [MatchHubData] {
        lock.lock(); defer { lock.unlock() }
        count += 1
        guard !replies.isEmpty else { throw FootballProviderError.serverError(599) }
        return replies.removeFirst().filter { range.contains($0.fixture.utcDate) }
    }
}

private final class StatusProviderProbe: FootballProvider, @unchecked Sendable {
    enum Reply { case rows([MatchHubData]), failure(FootballProviderError), cancelled }
    let name = "Deterministic football-status probe"
    private let lock = NSLock()
    private var replies: [Reply]
    private var count = 0
    init(_ replies: [Reply]) { self.replies = replies }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    private func next() throws -> [MatchHubData] {
        lock.lock()
        count += 1
        let reply = replies.isEmpty ? Reply.failure(.serverError(599)) : replies.removeFirst()
        lock.unlock()
        switch reply {
        case .rows(let rows): return rows
        case .failure(let error): throw error
        case .cancelled: throw URLError(.cancelled)
        }
    }
    func fetchLiveScores() async throws -> [MatchHubData] { try next() }
    func fetchFixtures(date: Date) async throws -> [FottyFixture] { throw FootballProviderError.unknown }
    func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData { throw FootballProviderError.unknown }
    func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData] { throw FootballProviderError.unknown }
    func fetchStandings(competitionId: String) async throws -> [FottyCompetition] { throw FootballProviderError.unknown }
    func fetchTeamForm(teamId: String) async throws -> [String] { throw FootballProviderError.unknown }
    func checkHealth() async -> Bool { false }
}
