import XCTest
@testable import Fotty

@MainActor
final class FootballScoreReceiptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_648_000)

    func testSuccessfulEmptyRevokesActiveScheduleWithoutInventingFinal() {
        let active = row(.live)
        let packet = FootballScoreSnapshotPolicy.project(schedule: [active],
            live: snapshot([], at: now), retainedTerminal: [:], at: now)
        XCTAssertEqual(packet.schedule.first?.status, .unknown)
        XCTAssertTrue(packet.terminal.isEmpty)
        XCTAssertTrue(packet.liveObservations.isEmpty)
    }

    func testFinalScheduleWinsContradictoryCurrentLivePoll() {
        let packet = FootballScoreSnapshotPolicy.project(schedule: [row(.fullTime)],
            live: snapshot([row(.live)], at: now), retainedTerminal: [:], at: now)
        XCTAssertEqual(packet.schedule.first?.status, .fullTime)
        XCTAssertEqual(packet.scores.first?.status, .fullTime)
        XCTAssertTrue(packet.liveObservations.isEmpty)
    }

    func testAcceptedFinalSurvivesLateActiveAndEmptyPolls() {
        let final = row(.fullTime)
        let first = FootballScoreSnapshotPolicy.project(schedule: [],
            live: snapshot([final], at: now), retainedTerminal: [:], at: now)
        for rows in [[row(.live)], []] {
            let next = FootballScoreSnapshotPolicy.project(schedule: [row(.live)],
                live: snapshot(rows, at: now), retainedTerminal: first.terminal, at: now)
            XCTAssertEqual(next.schedule.first?.status, .fullTime)
            XCTAssertEqual(next.scores.first?.status, .fullTime)
            XCTAssertTrue(next.liveObservations.isEmpty)
        }
    }

    func testFailedCachedPollCannotAuthorizeLiveEvenBeforeReceiptExpires() {
        let cached = FootballLiveSnapshot(matches: [row(.live)], observedAt: now,
            mode: .unavailable, refreshSucceeded: false)
        let packet = FootballScoreSnapshotPolicy.project(schedule: [row(.live)], live: cached,
            retainedTerminal: [:], at: now)
        XCTAssertEqual(packet.schedule.first?.status, .unknown)
        XCTAssertEqual(packet.scores.first?.status, .unknown)
        XCTAssertTrue(packet.liveObservations.isEmpty)
    }

    func testPerRowReceiptDoesNotBorrowNewerSnapshotOrAnotherMatchFreshness() {
        let old = row(.live, observed: now.addingTimeInterval(-601))
        let packet = FootballScoreSnapshotPolicy.project(schedule: [old],
            live: snapshot([old], at: now), retainedTerminal: [:], at: now)
        XCTAssertEqual(packet.schedule.first?.status, .unknown)
        XCTAssertTrue(packet.liveObservations.isEmpty)
    }

    func testFutureLiveAndHeldFinalGainNoAuthority() {
        let future = row(.live, observed: now.addingTimeInterval(1))
        let held = row(.fullTime, quality: .stale)
        let packet = FootballScoreSnapshotPolicy.project(schedule: [row(.scheduled)],
            live: snapshot([future, held], at: now), retainedTerminal: [:], at: now)
        XCTAssertTrue(packet.liveObservations.isEmpty)
        XCTAssertTrue(packet.terminal.isEmpty)
        XCTAssertTrue(packet.scores.allSatisfy { $0.status == .unknown })
        let futureFinal = row(.fullTime, observed: now.addingTimeInterval(301))
        let projected = FootballScoreSnapshotPolicy.project(schedule: [futureFinal], live: nil,
            retainedTerminal: [:], at: now)
        XCTAssertEqual(projected.schedule.first?.status, .unknown)
    }

    func testOtherCompetitionDoesNotInheritPremierLeagueActiveReceipt() {
        let other = row(.live, competition: "2001", name: "Champions League")
        let packet = FootballScoreSnapshotPolicy.project(schedule: [other],
            live: snapshot([other], at: now), retainedTerminal: [:], at: now)
        XCTAssertEqual(packet.schedule.first?.status, .unknown)
        XCTAssertTrue(packet.liveObservations.isEmpty)
    }

    func testExpiredTerminalRetentionIsBounded() {
        let old = row(.fullTime, kickoff: now.addingTimeInterval(-4 * 86_400))
        let packet = FootballScoreSnapshotPolicy.project(schedule: [], live: nil,
            retainedTerminal: [FootballScoreSnapshotPolicy.key(old): old], at: now)
        XCTAssertTrue(packet.terminal.isEmpty)
        XCTAssertTrue(packet.scores.isEmpty)
    }

    func testServiceLiveToFinishedUsesSameFactsInHomeMatchdayWatchAndScore() async throws {
        let clock = ReceiptClock(now)
        let feed = ReceiptProvider([.success([row(.live)]), .success([row(.fullTime, observed: now.addingTimeInterval(61))])])
        let service = service(clock: clock, feed: feed)
        await service.refresh()
        let event = event()
        XCTAssertEqual(MatchStartPolicy.currentStatus(for: event, scores: service, now: clock.read()), .inPlay)
        XCTAssertEqual(HomeSportsDiscovery(events: [event], now: clock.read()) {
            MatchStartPolicy.currentStatus(for: $0, scores: service, now: clock.read())
        }.items.first?.phase, .live)
        clock.advance(61)
        await service.refresh()
        let status = MatchStartPolicy.currentStatus(for: event, scores: service, now: clock.read())
        XCTAssertEqual(status, .finished)
        XCTAssertEqual(service.scoreForMatch(home: "Chelsea", away: "Bournemouth")?.status, .finished)
        XCTAssertTrue(HomeSportsDiscovery(events: [event], now: clock.read()) { _ in status }.items.isEmpty)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: clock.read(), status: status), .recent)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: [event], at: clock.read(), status: status))
        XCTAssertEqual(service.scheduleLastVerifiedAt, now, "A cached schedule read is not a new source receipt")
    }

    func testServiceHealthyEmptyClearsLiveScoreAndMinuteWithoutFalseFinal() async throws {
        let clock = ReceiptClock(now)
        let feed = ReceiptProvider([.success([row(.live)]), .success([])])
        let service = service(clock: clock, feed: feed)
        await service.refresh()
        XCTAssertNotNil(service.scoreForMatch(home: "Chelsea", away: "Bournemouth"))
        clock.advance(61)
        await service.refresh()
        XCTAssertNil(service.scoreForMatch(home: "Chelsea", away: "Bournemouth"))
        XCTAssertFalse(try XCTUnwrap(service.findMatch(home: "Chelsea", away: "Bournemouth")).status.isLive)
        XCTAssertFalse(try XCTUnwrap(service.findMatch(home: "Chelsea", away: "Bournemouth")).status.isFinished)
        XCTAssertEqual(service.liveObservedAt, clock.read())
    }

    func testServiceFailureAttemptsNeverRefreshCachedLiveReceipt() async throws {
        let clock = ReceiptClock(now)
        let feed = ReceiptProvider([.success([row(.live)]), .failure(FootballProviderError.serverError(503))])
        let service = service(clock: clock, feed: feed)
        await service.refresh()
        clock.advance(61)
        await service.refresh()
        XCTAssertEqual(service.feedMode, .unavailable)
        XCTAssertEqual(service.liveObservedAt, now)
        XCTAssertNil(service.scoreForMatch(home: "Chelsea", away: "Bournemouth"))
        clock.advance(700)
        await service.refresh()
        XCTAssertEqual(service.liveObservedAt, now)
        XCTAssertEqual(service.lastRefresh, clock.read(), "Publication clock is separate from accepted receipt")
        XCTAssertNil(service.scoreForMatch(home: "Chelsea", away: "Bournemouth"))
    }

    func testFirstUncachedPollUsesCompletionClockNotRequestStart() async throws {
        let clock = ReceiptClock(now)
        let observation = now.addingTimeInterval(2)
        let feed = ReceiptProvider([.success([row(.live, observed: observation)])], beforeFetch: { clock.advance(2) })
        let service = service(clock: clock, feed: feed)
        await service.refresh()
        let match = try XCTUnwrap(service.findMatch(home: "Chelsea", away: "Bournemouth"))
        XCTAssertEqual(service.currentStatus(for: match, at: clock.read()), .inPlay)
        XCTAssertEqual(service.liveObservedAt, observation)
        XCTAssertEqual(service.lastRefresh, observation)
        XCTAssertNotNil(service.scoreForMatch(home: "Chelsea", away: "Bournemouth"))
    }

    func testTemporaryUnknownDoesNotResetAlertBaselineToUpcomingOrZeroGoals() async throws {
        let clock = ReceiptClock(now)
        let feed = ReceiptProvider([.success([row(.live)]), .success([]),
            .success([row(.live, observed: now.addingTimeInterval(122))])])
        let service = service(clock: clock, feed: feed)
        await service.refresh()
        let start = now.addingTimeInterval(-7_200)
        let original = try XCTUnwrap(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start))
        clock.advance(61)
        await service.refresh()
        XCTAssertNil(service.scoreForMatch(home: "Chelsea", away: "Bournemouth"))
        XCTAssertEqual(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start), original)
        clock.advance(61)
        await service.refresh()
        let recovered = try XCTUnwrap(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start))
        XCTAssertEqual(recovered.homeGoals, original.homeGoals)
        XCTAssertEqual(recovered.status, original.status)
        XCTAssertFalse(FootballMatchAlertTransitionPolicy.shouldAnnounceKickoff(from: original.status, to: recovered.status))
    }

    func testCachedPreMatchScheduleDoesNotResetAcceptedLiveAlertBaseline() async throws {
        let clock = ReceiptClock(now)
        let feed = ReceiptProvider([.success([row(.live)]), .success([]),
            .success([row(.live, observed: now.addingTimeInterval(122))])])
        let service = service(clock: clock, feed: feed,
            scheduled: row(.scheduled, homeGoals: 0, awayGoals: 0))
        await service.refresh()
        let start = now.addingTimeInterval(-7_200)
        let original = try XCTUnwrap(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start))
        clock.advance(61)
        await service.refresh()
        XCTAssertEqual(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start), original)
        clock.advance(61)
        await service.refresh()
        XCTAssertEqual(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start), original)
    }

    func testBothEmptyFeedsRetainDatedAlertHistoryUntilExplicitFinal() async throws {
        let clock = ReceiptClock(now)
        let feed = ReceiptProvider([.success([row(.live)]), .success([]),
            .success([row(.fullTime, observed: now.addingTimeInterval(122))])])
        // A known empty schedule deliberately suppresses unnecessary live API
        // requests. Recover through the explicit schedule final, not a queued
        // live reply that the quiet-window policy correctly will not fetch.
        let scheduleFeed = ReceiptProvider([.success([row(.scheduled)]), .success([]),
            .success([row(.fullTime, observed: now.addingTimeInterval(122))]), .success([])])
        let failing = ReceiptProvider([.failure(FootballProviderError.serverError(503))])
        let repository = FootballRepository(scheduleLoader: { _ in try await scheduleFeed.fetchLiveScores() },
            primaryProvider: failing, officialFPLScoreProvider: feed, footballDataProvider: failing, now: { clock.read() })
        let service = LiveScoreService(repository: repository, now: { clock.read() })
        await service.refresh(force: true)
        let start = now.addingTimeInterval(-7_200)
        let original = try XCTUnwrap(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start))
        clock.advance(61)
        await service.refresh(force: true)
        XCTAssertEqual(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start), original)
        clock.advance(61)
        await service.refresh(force: true)
        XCTAssertEqual(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start)?.status, .finished)
        clock.advance(4 * 86_400)
        await service.refresh(force: true)
        XCTAssertNil(service.alertBaselineForTesting(home: "Chelsea", away: "Bournemouth", kickoff: start))
    }

    func testOnlyExactOfficialStableCodeCrestRouteGainsBadgePrecedence() throws {
        let official = try XCTUnwrap(URL(string: "https://resources.premierleague.com/premierleague/badges/100/t1.png"))
        let provider = try XCTUnwrap(URL(string: "https://example.invalid/unrelated-club.png"))
        XCTAssertTrue(FootballDataPolicy.isOfficialPremierLeagueCrestURL(official))
        XCTAssertEqual(HomeDiscoveryRow.Presentation.preferredBadgeURL(provider: provider,
            matched: official, sameOfficialFixture: true), official)
        XCTAssertEqual(HomeDiscoveryRow.Presentation.preferredBadgeURL(provider: provider,
            matched: official, sameOfficialFixture: false), provider)
        XCTAssertNil(HomeDiscoveryRow.Presentation.preferredBadgeURL(provider: nil,
            matched: official, sameOfficialFixture: false))
        for raw in ["http://resources.premierleague.com/premierleague/badges/100/t1.png",
                    "https://resources.premierleague.com.example.invalid/premierleague/badges/100/t1.png",
                    "https://resources.premierleague.com/premierleague/badges/100/t0.png",
                    "https://resources.premierleague.com/premierleague/badges/100/t1.png?team=other",
                    "https://resources.premierleague.com/unreviewed/t1.png"] {
            let candidate = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(FootballDataPolicy.isOfficialPremierLeagueCrestURL(candidate))
            XCTAssertEqual(HomeDiscoveryRow.Presentation.preferredBadgeURL(provider: provider,
                matched: candidate, sameOfficialFixture: true), provider)
        }
    }

    func testPresentationKeepsBothOfficialCrestsAfterLiveScoreArrives() async throws {
        let clock = ReceiptClock(now)
        let home = try XCTUnwrap(URL(string: "https://resources.premierleague.com/premierleague/badges/100/t8.png"))
        let away = try XCTUnwrap(URL(string: "https://resources.premierleague.com/premierleague/badges/100/t91.png"))
        let service = service(clock: clock, feed: ReceiptProvider([.success([
            row(.live, homeCrest: home, awayCrest: away)
        ])]))
        await service.refresh()
        let item = HomeSportsDiscovery.Item(event: badgeEvent(), phase: .live, officialStatus: .inPlay, now: now)
        let presentation = HomeDiscoveryRow.Presentation(item: item, scoreService: service)
        XCTAssertEqual(presentation.homeBadgeURL, home)
        XCTAssertEqual(presentation.awayBadgeURL, away)
        XCTAssertEqual(presentation.homeScore, 2)
        XCTAssertEqual(presentation.awayScore, 1)
    }

    func testPresentationDoesNotBorrowCrestAcrossDatedSquadOrIdentityConflict() async throws {
        let clock = ReceiptClock(now)
        let home = try XCTUnwrap(URL(string: "https://resources.premierleague.com/premierleague/badges/100/t8.png"))
        let service = service(clock: clock, feed: ReceiptProvider([.success([row(.live, homeCrest: home)])]))
        await service.refresh()
        for event in [badgeEvent(kickoff: now.addingTimeInterval(86_400)),
                      badgeEvent(home: "Chelsea U19"), badgeEvent(conflict: true)] {
            let item = HomeSportsDiscovery.Item(event: event, phase: .live, officialStatus: .inPlay, now: now)
            let presentation = HomeDiscoveryRow.Presentation(item: item, scoreService: service)
            XCTAssertNotEqual(presentation.homeBadgeURL, home,
                              "Official artwork must stay bound to its dated, unconflicted squad identity")
        }
    }

    func testOfficialArtworkGuardRespectsExplicitCompetitionAndTitleOnlySquads() {
        XCTAssertTrue(HomeDiscoveryRow.Presentation.permitsOfficialPremierLeagueArtwork(for: badgeEvent()))
        for event in [badgeEvent(competition: "champions-league"), badgeEvent(competition: "fa-cup"),
                      badgeEvent(title: "Chelsea U19 vs Bournemouth U19"),
                      badgeEvent(title: "Chelsea Women vs Bournemouth Women"),
                      badgeEvent(title: "FA Cup: Chelsea vs Bournemouth")] {
            XCTAssertFalse(HomeDiscoveryRow.Presentation.permitsOfficialPremierLeagueArtwork(for: event))
        }
        let fixture = SportsFixtureMetadata(fixtureID: "youth", sport: "football", competitionID: "premier-league",
            competitionName: "Premier League", eventKind: .match, title: "Chelsea vs Bournemouth",
            participants: [.init(id: "chelsea", name: "Chelsea"), .init(id: "bournemouth", name: "Bournemouth")],
            squad: .init(gender: .men, ageGroup: "u19"), status: .live, observedAt: now, verified: true)
        XCTAssertFalse(HomeDiscoveryRow.Presentation.permitsOfficialPremierLeagueArtwork(for: badgeEvent(fixture: fixture)))
        let senior = SportsFixtureMetadata(fixtureID: "different-provider-id", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Chelsea vs Bournemouth", participants: fixture.participants,
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: now, verified: true)
        XCTAssertTrue(HomeDiscoveryRow.Presentation.permitsOfficialPremierLeagueArtwork(for: badgeEvent(fixture: senior)),
                      "Matching reviewed scope must not require cross-provider numeric IDs to agree")
    }

    func testOfficialAbbreviationsReachHomeScoreMinuteAndArtworkWithoutMatchingScheduleMerge() async throws {
        let clock = ReceiptClock(now)
        let official = try palaceOfficialRow()
        // This deliberately unrelated schedule cannot fill in CRY/NFO's full
        // names during the repository merge and accidentally hide the defect.
        let service = service(clock: clock, feed: ReceiptProvider([.success([official])]),
            scheduled: row(.scheduled, kickoff: now.addingTimeInterval(60)))
        await service.refresh()
        let event = palaceEvent()
        let match = try XCTUnwrap(service.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate))
        XCTAssertEqual(match.homeTeam.displayName, "CRY", "Identity repair must not rewrite display labels")
        XCTAssertEqual(match.awayTeam.displayName, "NFO")
        XCTAssertEqual(match.homeTeam.matchingName, "Crystal Palace")
        XCTAssertEqual(match.awayTeam.matchingName, "Nott'm Forest")
        XCTAssertEqual(service.currentStatus(for: match, at: now), .inPlay)
        XCTAssertEqual(service.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate)?.minute, "45'")
        XCTAssertEqual(service.scores["crystal palace|nott'm forest"]?.minute, "45'")

        let discovery = HomeSportsDiscovery(events: [event], now: now) {
            MatchStartPolicy.currentStatus(for: $0, scores: service, now: now)
        }
        let item = try XCTUnwrap(discovery.items.first)
        XCTAssertEqual(item.phase, .live)
        let presentation = HomeDiscoveryRow.Presentation(item: item, scoreService: service)
        XCTAssertEqual(presentation.homeScore, 2)
        XCTAssertEqual(presentation.awayScore, 1)
        XCTAssertEqual(presentation.liveDetail, "45'")
        XCTAssertEqual(presentation.statusLabel, "2–1 · 45' · Official FPL")
        XCTAssertEqual(presentation.homeBadgeURL, official.homeTeam.crestURL)
        XCTAssertEqual(presentation.awayBadgeURL, official.awayTeam.crestURL)
    }

    func testOfficialAbbreviationIdentityDoesNotRenewOrBorrowExpiredLiveReceipt() async throws {
        let clock = ReceiptClock(now)
        let service = service(clock: clock, feed: ReceiptProvider([.success([try palaceOfficialRow()])]),
            scheduled: row(.scheduled, kickoff: now.addingTimeInterval(60)))
        await service.refresh()
        let event = palaceEvent()
        let match = try XCTUnwrap(service.findMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate))
        clock.advance(601)
        XCTAssertNil(service.currentStatus(for: match, at: clock.read()))
        XCTAssertNil(service.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate))

        let stale = self.service(clock: ReceiptClock(now),
            feed: ReceiptProvider([.success([try palaceOfficialRow(observed: now.addingTimeInterval(-601))])]),
            scheduled: row(.scheduled, kickoff: now.addingTimeInterval(60)))
        await stale.refresh()
        XCTAssertNil(stale.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate))
        XCTAssertFalse(try XCTUnwrap(stale.findMatch(home: event.homeName, away: event.awayName)).status.isLive)
    }

    func testOfficialAbbreviationIdentityRetainsDatedKickoffGuard() async throws {
        let service = service(clock: ReceiptClock(now), feed: ReceiptProvider([.success([try palaceOfficialRow()])]),
            scheduled: row(.scheduled, kickoff: now.addingTimeInterval(60)))
        await service.refresh()
        let kickoff = now.addingTimeInterval(-1_800)
        let requests: [Date?] = [nil, kickoff.addingTimeInterval(86_400), kickoff.addingTimeInterval(18 * 3_600 + 1)]
        for requested in requests {
            XCTAssertNil(service.findMatch(home: "Crystal Palace FC", away: "Nottingham Forest FC", near: requested))
            XCTAssertNil(service.scoreForMatch(home: "Crystal Palace FC", away: "Nottingham Forest FC", near: requested))
        }
        XCTAssertNil(service.scoreForMatch(home: "Nottingham Forest FC", away: "Crystal Palace FC", near: kickoff))
        XCTAssertNil(service.scoreForMatch(home: "Crystal Palace FC", away: "Chelsea", near: kickoff))
    }

    func testOfficialAbbreviationIdentityCannotLendSeniorScoreToQualifiedSquad() async throws {
        let service = service(clock: ReceiptClock(now), feed: ReceiptProvider([.success([try palaceOfficialRow()])]),
            scheduled: row(.scheduled, kickoff: now.addingTimeInterval(60)))
        await service.refresh()
        for suffix in ["Women", "U19", "Under 21", "Reserves", "Academy"] {
            let home = "Crystal Palace \(suffix)", away = "Nottingham Forest \(suffix)"
            XCTAssertNil(service.findMatch(home: home, away: away))
            XCTAssertNil(service.scoreForMatch(home: home, away: away, near: now.addingTimeInterval(-1_800)))
            XCTAssertNil(service.findMatch(home: home, away: "Nottingham Forest FC"))
            XCTAssertNil(service.findMatch(home: "Crystal Palace FC", away: away))
        }
    }

    func testFootballIdentityPrefersNonblankFullNameAndKeepsShortNameOnlyAsFallback() {
        XCTAssertEqual(FootballTeam(id: nil, name: " Crystal Palace\n", shortName: "CRY", tla: nil, crest: nil).matchingName,
                       "Crystal Palace")
        XCTAssertEqual(FootballTeam(id: nil, name: " \n", shortName: " CRY ", tla: nil, crest: nil).matchingName, "CRY")
        XCTAssertEqual(FootballTeam(id: nil, name: nil, shortName: nil, tla: nil, crest: nil).matchingName, "")
    }

    private func palaceOfficialRow(observed: Date? = nil) throws -> MatchHubData {
        let kickoff = ISO8601DateFormatter().string(from: now.addingTimeInterval(-1_800))
        let fixtureJSON = """
        [{"id":55,"event":6,"kickoff_time":"\(kickoff)","team_h":8,"team_a":18,"team_h_score":2,"team_a_score":1,"team_h_difficulty":3,"team_a_difficulty":3,"started":true,"finished":false,"finished_provisional":false,"minutes":45}]
        """
        let teamsJSON = """
        [{"id":8,"name":"Crystal Palace","short_name":"CRY","code":31,"strength":3,"strength_overall_home":3,"strength_overall_away":3,"strength_attack_home":3,"strength_attack_away":3,"strength_defence_home":3,"strength_defence_away":3},
         {"id":18,"name":"Nott'm Forest","short_name":"NFO","code":17,"strength":3,"strength_overall_home":3,"strength_overall_away":3,"strength_attack_home":3,"strength_attack_away":3,"strength_defence_home":3,"strength_defence_away":3}]
        """
        let fixtures = try JSONDecoder().decode([FPLFixture].self, from: Data(fixtureJSON.utf8))
        let teams = try JSONDecoder().decode([FPLTeam].self, from: Data(teamsJSON.utf8))
        return try XCTUnwrap(OfficialFPLScoreProvider.mapLiveFixtures(fixtures, teams: teams,
            fetchedAt: observed ?? now).first)
    }

    private func palaceEvent() -> EventReference {
        .init(id: "official-short-name-receipt-test", title: "Crystal Palace FC vs Nottingham Forest FC", category: "football",
            date: Int64(now.addingTimeInterval(-1_800).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Crystal Palace FC", badge: "https://example.invalid/wrong-home.png"),
                         away: .init(name: "Nottingham Forest FC", badge: "https://example.invalid/wrong-away.png")),
            sources: [.init(source: "delta", id: "unit-only")], competitionID: "premier-league")
    }

    private func badgeEvent(home: String = "Chelsea", kickoff: Date? = nil, conflict: Bool = false,
                            competition: String = "premier-league", title: String? = nil,
                            fixture: SportsFixtureMetadata? = nil) -> EventReference {
        .init(id: "badge-receipt-test", title: title ?? "\(home) vs Bournemouth", category: "football",
            date: Int64((kickoff ?? now.addingTimeInterval(-7_200)).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: "https://example.invalid/wrong-home.png"),
                         away: .init(name: "Bournemouth", badge: "https://example.invalid/wrong-away.png")),
            sources: [], hasCatalogIdentityConflict: conflict, sportsFixture: fixture, competitionID: competition)
    }

    private func service(clock: ReceiptClock, feed: ReceiptProvider, scheduled: MatchHubData? = nil) -> LiveScoreService {
        let scheduled = scheduled ?? row(.live)
        let failing = ReceiptProvider([.failure(FootballProviderError.serverError(503))])
        let repository = FootballRepository(scheduleLoader: { _ in [scheduled] }, primaryProvider: failing,
            officialFPLScoreProvider: feed, footballDataProvider: failing, now: { clock.read() })
        return LiveScoreService(repository: repository, now: { clock.read() })
    }
    private func snapshot(_ matches: [MatchHubData], at observation: Date) -> FootballLiveSnapshot {
        .init(matches: matches, observedAt: observation, mode: .officialFPL, refreshSucceeded: true)
    }
    private func row(_ status: FottyMatchStatus, observed: Date? = nil, quality: MatchHubData.DataQualityStatus = .official,
                     competition: String = "39", name: String = "Premier League", kickoff: Date? = nil,
                     homeGoals: Int = 2, awayGoals: Int = 1, homeCrest: URL? = nil, awayCrest: URL? = nil) -> MatchHubData {
        let observation = observed ?? now
        let fixture = FottyFixture(id: "900000010", utcDate: kickoff ?? now.addingTimeInterval(-7_200), status: status,
            competition: .init(id: competition, name: name, country: "England", emblemURL: nil),
            venue: nil, matchday: 8, lastUpdated: observation, elapsedMinutes: status.isLive ? 89 : nil)
        return .init(fixture: fixture,
            homeTeam: .init(id: "1", name: "Chelsea", shortName: nil, crestURL: homeCrest, color: nil),
            awayTeam: .init(id: "2", name: "Bournemouth", shortName: nil, crestURL: awayCrest, color: nil),
            score: .init(home: homeGoals, away: awayGoals, aggregateHome: nil, aggregateAway: nil, periodScores: nil), events: [], homeLineup: nil, awayLineup: nil, statistics: [], teamNews: [],
            lastUpdated: observation, dataQuality: quality)
    }
    private func event() -> EventReference {
        .init(id: "receipt-test", title: "Chelsea vs Bournemouth", category: "football",
            date: Int64(now.addingTimeInterval(-7_200).timeIntervalSince1970), poster: nil, popular: false, teams: nil,
            sources: [.init(source: "delta", id: "unit-only")])
    }
}

private final class ReceiptClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}
private final class ReceiptProvider: FootballProvider, @unchecked Sendable {
    let name = "offline-receipt-test"
    private let lock = NSLock()
    private var replies: [Result<[MatchHubData], Error>]
    private let beforeFetch: (() -> Void)?
    init(_ replies: [Result<[MatchHubData], Error>], beforeFetch: (() -> Void)? = nil) {
        self.replies = replies; self.beforeFetch = beforeFetch
    }
    private func next() throws -> [MatchHubData] {
        lock.lock(); defer { lock.unlock() }
        let result = replies.count > 1 ? replies.removeFirst() : replies[0]
        return try result.get()
    }
    func fetchLiveScores() async throws -> [MatchHubData] { beforeFetch?(); return try next() }
    func fetchFixtures(date: Date) async throws -> [FottyFixture] { [] }
    func fetchFixtureDetails(fixtureId: String) async throws -> MatchHubData { throw FootballProviderError.unknown }
    func fetchLeagueFixtures(leagueId: String, season: String) async throws -> [MatchHubData] { [] }
    func fetchStandings(competitionId: String) async throws -> [FottyCompetition] { [] }
    func fetchTeamForm(teamId: String) async throws -> [String] { [] }
    func checkHealth() async -> Bool { true }
}
