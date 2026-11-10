import XCTest
import UserNotifications
@testable import Fotty

@MainActor
final class MatchdayJourneyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func projectionKey(catalog: Int = 1, score: Int64 = 2, minute: Int64 = 3,
                               saved: Int = 4, teams: [String] = ["team"],
                               leagues: [String] = ["league"], clashes: Bool = false,
                               sports: [String] = [], registry: String? = nil, discovery: UInt64 = 0,
                               listing: UInt64 = 0, sources: Set<String> = []) -> MatchdayProjectionKey {
        .init(catalogRevision: catalog, scoreRevisionMilliseconds: score, minuteBucket: minute,
              savedRevision: saved, followedTeams: teams, followedLeagues: leagues,
              showKickoffClashes: clashes, followedSports: sports, registryRevision: registry,
              discoveryRevision: discovery, listingRevision: listing, enabledSources: sources)
    }

    func testMatchdayCheckpointRejectsEveryChangedRequestInputAndCancellation() async {
        let requested = projectionKey()
        let changed = [
            projectionKey(catalog: 9), projectionKey(score: 9), projectionKey(minute: 9),
            projectionKey(saved: 9), projectionKey(teams: ["replacement"]),
            projectionKey(leagues: ["replacement"]), projectionKey(clashes: true),
            projectionKey(sports: ["cricket"]), projectionKey(registry: "new-programme"),
            projectionKey(discovery: 1), projectionKey(listing: 1), projectionKey(sources: ["reviewedtv"])
        ]
        for current in changed {
            XCTAssertNotEqual(requested, current)
            let accepted = await HomeProjectionWorkPolicy.checkpoint { requested == current }
            XCTAssertFalse(accepted, "A superseded Matchday packet must not publish")
        }
        let cancelled = Task { @MainActor in
            await HomeProjectionWorkPolicy.checkpoint { requested == requested }
        }
        cancelled.cancel()
        let cancellationAccepted = await cancelled.value
        XCTAssertFalse(cancellationAccepted)
        let accepted = await HomeProjectionWorkPolicy.checkpoint { requested == requested }
        XCTAssertTrue(accepted)
        XCTAssertNotEqual(projectionKey(sports: ["cricket"]), projectionKey(sports: ["tennis"]),
                          "Same-count sport edits must invalidate the personal schedule")
    }

    private struct DisplayItem: Identifiable {
        let id: String
        let reason: String
        var isChannel = false
    }

    private func displaySections() -> [MatchdayDisplayLayout.Section<DisplayItem>] {
        [
            .init(id: "empty", title: "Empty", subtitle: nil, items: []),
            .init(id: "live", title: "Live now", subtitle: nil,
                  items: [.init(id: "a", reason: "Saved match"), .init(id: "reminder", reason: "Followed team"),
                          .init(id: "b", reason: "Saved match"), .init(id: "c", reason: "Saved match")]),
            .init(id: "next", title: "Next up", subtitle: "Explicit subtitle",
                  items: [.init(id: "d", reason: "Saved match"), .init(id: "e", reason: "Followed team")]),
            .init(id: "channels", title: "Saved channels", subtitle: nil,
                  items: [.init(id: "willow", reason: "Saved channel", isChannel: true)])
        ]
    }

    func testMatchdayFlattenedEntriesPreserveOrderReasonsCountsAndReminderExclusion() {
        let entries = MatchdayDisplayLayout.entries(
            sections: displaySections(), columns: 1, excluding: "reminder",
            reason: { $0.reason }, isChannel: { $0.isChannel }
        )
        var headings: [MatchdayDisplayLayout.Heading] = []
        var rows: [MatchdayDisplayLayout.Row<DisplayItem>] = []
        for entry in entries {
            switch entry {
            case .heading(let heading): headings.append(heading)
            case .fixtures(let row): rows.append(row)
            }
        }
        XCTAssertEqual(headings.map(\.title), ["Live now", "Next up", "Saved channels"])
        XCTAssertEqual(headings.map(\.count), [3, 2, nil])
        XCTAssertEqual(headings.map(\.subtitle), ["Saved match", "Explicit subtitle", "Saved channel"])
        XCTAssertEqual(headings.map(\.isFirstSection), [true, false, false])
        XCTAssertEqual(rows.flatMap(\.items).map(\.id), ["a", "b", "c", "d", "e", "willow"])
        XCTAssertEqual(rows.map(\.showsReason), [false, false, false, true, true, false])
        XCTAssertEqual(rows.map(\.isFirst), [true, false, false, true, false, true])
        XCTAssertEqual(rows.map(\.isLast), [false, false, true, false, true, true])
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }

    func testMatchdayFlattenedRowsRegroupColumnsWithoutReorderingOrIdentityCollision() {
        let narrow = MatchdayDisplayLayout.entries(
            sections: displaySections(), columns: 1, excluding: "reminder",
            reason: { $0.reason }, isChannel: { $0.isChannel }
        )
        let wide = MatchdayDisplayLayout.entries(
            sections: displaySections(), columns: 2, excluding: "reminder",
            reason: { $0.reason }, isChannel: { $0.isChannel }
        )
        let narrowRows = narrow.compactMap { entry -> MatchdayDisplayLayout.Row<DisplayItem>? in
            if case .fixtures(let row) = entry { return row }; return nil
        }
        let wideRows = wide.compactMap { entry -> MatchdayDisplayLayout.Row<DisplayItem>? in
            if case .fixtures(let row) = entry { return row }; return nil
        }
        XCTAssertEqual(wideRows.map { $0.items.map(\.id) }, [["a", "b"], ["c"], ["d", "e"], ["willow"]])
        XCTAssertEqual(wideRows.flatMap(\.items).map(\.id), narrowRows.flatMap(\.items).map(\.id))
        XCTAssertTrue(Set(narrowRows.map(\.id)).isDisjoint(with: wideRows.map(\.id)),
                      "Changing columns must not reuse an incompatible grid-row identity")
        XCTAssertEqual(Set(wide.map(\.id)).count, wide.count)
        let repeatWide = MatchdayDisplayLayout.entries(
            sections: displaySections(), columns: 2, excluding: "reminder",
            reason: { $0.reason }, isChannel: { $0.isChannel }
        )
        XCTAssertEqual(wide.map(\.id), repeatWide.map(\.id))

        let duplicateAcrossSections = MatchdayDisplayLayout.entries(
            sections: [.init(id: "live", title: "Live", subtitle: nil, items: [DisplayItem(id: "same", reason: "Saved")]),
                       .init(id: "recent", title: "Recent", subtitle: nil, items: [DisplayItem(id: "same", reason: "Saved")])],
            columns: 2, excluding: nil, reason: { $0.reason }, isChannel: { $0.isChannel }
        )
        XCTAssertEqual(Set(duplicateAcrossSections.map(\.id)).count, duplicateAcrossSections.count)

        func pairIDs(second: String, reason: String) -> [MatchdayDisplayLayout.ID] {
            MatchdayDisplayLayout.entries(
                sections: [.init(id: "live", title: "Live", subtitle: nil,
                                 items: [DisplayItem(id: "first", reason: reason), DisplayItem(id: second, reason: reason)])],
                columns: 2, excluding: nil, reason: { $0.reason }, isChannel: { $0.isChannel }
            ).compactMap { entry in
                if case .fixtures(let row) = entry { return row.id }; return nil
            }
        }
        XCTAssertNotEqual(pairIDs(second: "old-second", reason: "Saved"),
                          pairIDs(second: "new-second", reason: "Saved"))
        XCTAssertEqual(pairIDs(second: "second", reason: "Saved"),
                       pairIDs(second: "second", reason: "Following"),
                       "Reason/clock changes do not reset an unchanged ordered row membership")
    }

    private func event(_ id: String = "fixture", at start: Date?, source: String? = "delta",
                       home: String = "Home Club", away: String = "Away Club",
                       conflict: Bool = false) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: "\(home) vs \(away)", category: "football",
              date: start.map { Int64($0.timeIntervalSince1970) }, poster: nil, popular: nil,
              teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
              hasCatalogIdentityConflict: conflict)
    }

    private func channel(_ id: String, title: String, source: String = "delta",
                         conflict: Bool = false) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: title, category: "cricket", date: nil, poster: nil, popular: nil,
              teams: nil, hasCatalogIdentityConflict: conflict)
    }

    func testCardLiveLabelsRequireAcceptedRecentOfficialStatus() {
        let provider = event("official-status", at: now.addingTimeInterval(-60))
        let accepted = HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now.addingTimeInterval(-60),
                                                       liveFeedAvailable: true, now: now)
        let confirmed = MatchdayEventStatePolicy.section(for: provider, at: now, status: accepted)
        XCTAssertEqual(confirmed, .live)
        XCTAssertEqual(LiveEventCard.prominentStatusLabel(for: confirmed, broadcastAvailable: true), "LIVE")
        XCTAssertEqual(LiveEventCard.prominentStatusLabel(for: confirmed, broadcastAvailable: false), "IN PLAY")

        let unavailableCases: [(Date?, Bool)] = [(now.addingTimeInterval(-601), true), (now, false), (nil, true)]
        for (refreshedAt, available) in unavailableCases {
            let stale = HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: refreshedAt,
                                                        liveFeedAvailable: available, now: now)
            XCTAssertNil(stale)
            let section = MatchdayEventStatePolicy.section(for: provider, at: now, status: stale)
            XCTAssertEqual(section, .awaitingConfirmation)
            XCTAssertNil(LiveEventCard.prominentStatusLabel(for: section, broadcastAvailable: true))
        }
        for (status, expected) in [
            (FootballMatch.MatchStatus.scheduled, MatchdayEventStatePolicy.Section.awaitingConfirmation),
            (.finished, .recent), (.cancelled, .recent),
            (.postponed, .timeToBeConfirmed), (.suspended, .timeToBeConfirmed)
        ] {
            let section = MatchdayEventStatePolicy.section(for: provider, at: now, status: status)
            XCTAssertEqual(section, expected)
            XCTAssertNil(LiveEventCard.prominentStatusLabel(for: section, broadcastAvailable: true))
        }
    }

    func testCardLiveLabelsRespectVerifiedCricketFreshnessAndTerminalFacts() {
        func fixture(_ status: CricketFixtureCatalog.Status, observedAt: Date? = nil, verified: Bool = true) -> EventReference {
            let metadata = CricketFixtureMetadata(fixtureID: "cricket-fixture:card-status", competitionID: "cpl",
                competitionName: "Caribbean Premier League", format: .t20, status: status,
                observedAt: observedAt ?? now, verified: verified)
            return .init(id: metadata.fixtureID, title: "Trinbago Knight Riders vs Barbados Royals", category: "cricket",
                         date: Int64(now.addingTimeInterval(-60).timeIntervalSince1970), poster: nil, popular: nil,
                         teams: nil, cricketFixture: metadata)
        }
        let live = MatchdayEventStatePolicy.section(for: fixture(.live), at: now)
        XCTAssertEqual(live, .live)
        XCTAssertEqual(LiveEventCard.prominentStatusLabel(for: live, broadcastAvailable: true), "LIVE")
        for row in [fixture(.live, observedAt: now.addingTimeInterval(-1801)), fixture(.live, verified: false)] {
            let section = MatchdayEventStatePolicy.section(for: row, at: now)
            XCTAssertEqual(section, .awaitingConfirmation)
            XCTAssertNil(LiveEventCard.prominentStatusLabel(for: section, broadcastAvailable: true))
        }
        for status in [CricketFixtureCatalog.Status.finished, .cancelled] {
            let row = fixture(status)
            let section = MatchdayEventStatePolicy.section(for: row, at: now, status: .inPlay)
            XCTAssertEqual(section, .recent, "Verified terminal facts still outrank earlier score state")
            XCTAssertNil(LiveEventCard.prominentStatusLabel(for: section, broadcastAvailable: true))
            XCTAssertFalse(MatchStartPolicy(event: row, now: now).canAttemptPlayback)
        }
    }

    func testMatchdayPreparedSelectionPreservesFollowAdmissionAndLeagueReasonsForArbitraryIDs() {
        let teams = [
            FollowedTeamItem(key: "legacy-united", teamName: "Man Utd", sportCategory: "football"),
            FollowedTeamItem(key: "legacy-lakers", teamName: "Los Angeles Lakers", sportCategory: "football")
        ]
        let leagues = [
            FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball"),
            FollowedLeagueItem(id: "cpl", leagueName: "Caribbean Premier League", sportCategory: "cricket"),
            FollowedLeagueItem(id: "unknown", leagueName: "Unknown", sportCategory: "baseball")
        ]
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: teams, leagues: leagues)
        let legacyKeys = SportsPersonalizationPolicy.followedTeamKeys(teams)
        let cases: [(AnalyticalDataEngine.EventReference, Bool, String?)] = [
            (event("opaque-current", at: now, home: "Manchester United", away: "Chelsea"), true, nil),
            (personalEvent("opaque-saved", title: "LA Lakers vs Boston Celtics", sport: "basketball"), true, nil),
            (personalEvent("nba-unfamiliar-teams", title: "Example vs Another", sport: "basketball"), true, "NBA"),
            (personalEvent("opaque-cpl", title: "Trinbago Knight Riders vs Barbados Royals", sport: "cricket"), true, "Caribbean Premier League"),
            (personalEvent("cpl-2026-999", title: "CPL Final", sport: "cricket"), true, "Caribbean Premier League"),
            (personalEvent("cpl-news", title: "CPL news and interviews", sport: "cricket"), false, nil),
            (event("arbitrary-saved", at: now), false, nil),
            (event("conflict", at: now, home: "Manchester United", away: "Chelsea", conflict: true), false, nil),
            (channel("saved-channel", title: "Willow Cricket"), false, nil)
        ]
        for (fixture, expectedFollowed, expectedLeague) in cases {
            XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection), expectedFollowed, fixture.id)
            XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection),
                           SportsPersonalizationPolicy.isFollowed(event: fixture, teamKeys: legacyKeys, leagueItems: leagues), fixture.id)
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection), expectedLeague, fixture.id)
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection),
                           SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: leagues), fixture.id)
        }

        // A saved/provider ID does not cache a row's classification. The same ID
        // can carry different sport/team metadata in a later catalog revision.
        let first = personalEvent("nba-reused", title: "Example vs Another", sport: "basketball")
        let replacement = personalEvent("nba-reused", title: "India vs Australia", sport: "cricket")
        XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: first, in: selection), "NBA")
        XCTAssertNil(SportsPersonalizationPolicy.followedLeagueName(for: replacement, in: selection))
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: replacement, selection: selection))
    }

    func testMatchdayPreparedSelectionPreservesOfficialCompetitionPrecedenceAndUnknownLeagueFallback() {
        let fixture = event("mls-provider-marker", at: now, home: "Chelsea", away: "Arsenal")
        let official = FootballMatch(
            id: 101, apiFootballFixtureId: nil, utcDate: "2027-01-15T08:00:00Z", status: .scheduled,
            matchday: nil, stage: nil, group: nil,
            homeTeam: .init(id: 61, name: "Chelsea", shortName: "Chelsea", tla: "CHE", crest: nil),
            awayTeam: .init(id: 57, name: "Arsenal", shortName: "Arsenal", tla: "ARS", crest: nil),
            score: .init(winner: nil, duration: nil, fullTime: nil, halfTime: nil),
            competition: .init(id: 2021, name: "Premier League", code: "PL", emblem: nil, country: "England"),
            referees: nil, events: nil
        )
        let cases: [(FollowedLeagueItem, String?)] = [
            (.init(id: "premier-league", leagueName: "Premier League", sportCategory: "football"), "Premier League"),
            (.init(id: "mls", leagueName: "MLS", sportCategory: "football"), nil),
            (.init(id: "unrecognized", leagueName: "Unrecognized", sportCategory: "football"), nil)
        ]
        for (league, expected) in cases {
            let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [league])
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection, officialMatch: official), expected)
            XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: selection, officialMatch: official),
                           SportsPersonalizationPolicy.followedLeagueName(for: fixture, in: [league], officialMatch: official))
            XCTAssertEqual(SportsPersonalizationPolicy.isFollowed(event: fixture, selection: selection, officialMatch: official), expected != nil)
        }
    }

    func testMatchdayPreparedSelectionOwnsImmutableFullIdentityAcrossSameCountEdits() {
        let team = FollowedTeamItem(key: "united", teamName: "Manchester United", sportCategory: "football")
        let league = FollowedLeagueItem(id: "nba", leagueName: "NBA", sportCategory: "basketball")
        let original = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league])
        let united = event("saved-united", at: now, home: "Man Utd", away: "Chelsea")
        let cpl = personalEvent("saved-cpl", title: "Trinbago Knight Riders vs Barbados Royals", sport: "cricket")
        team.teamName = "Liverpool"
        team.sportCategory = "cricket"
        league.id = "cpl"
        league.leagueName = "Caribbean Premier League"
        league.sportCategory = "cricket"
        let changed = SportsPersonalizationPolicy.prepareSelection(teams: [team], leagues: [league])

        XCTAssertEqual(original.identity.teams.count, changed.identity.teams.count)
        XCTAssertEqual(original.identity.competitions.count, changed.identity.competitions.count)
        XCTAssertNotEqual(original.identity, changed.identity)
        XCTAssertEqual(original.identity.teams.first?.name, "Manchester United")
        XCTAssertEqual(original.identity.teams.first?.category, "football")
        XCTAssertEqual(original.leagueIDs, ["nba"])
        XCTAssertEqual(changed.leagueIDs, ["cpl"])
        XCTAssertTrue(SportsPersonalizationPolicy.isFollowed(event: united, selection: original))
        XCTAssertFalse(SportsPersonalizationPolicy.isFollowed(event: united, selection: changed))
        XCTAssertNil(SportsPersonalizationPolicy.followedLeagueName(for: cpl, in: original))
        XCTAssertEqual(SportsPersonalizationPolicy.followedLeagueName(for: cpl, in: changed), "Caribbean Premier League")
    }

    private func personalEvent(_ id: String, title: String, sport: String) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: title, category: sport, date: Int64(now.timeIntervalSince1970),
              poster: nil, popular: nil, teams: nil)
    }

    func testMatchdayAdmissionIndexPreservesAliasConflictsAndSavedFallbackSearch() {
        let fixture = event("home-away", at: now, home: "Alpha", away: "Beta")
        let alias = event("stored:home-away", at: now, home: "Other", away: "Team")
        let unrelated = event("other", at: now, home: "Gamma", away: "Delta")
        let catalog = [unrelated, fixture, alias]
        let indexed = CurrentEventBroadcastPolicy.IndexedCatalog(catalog, at: now)
        let candidates = indexed.candidates(for: fixture)
        XCTAssertEqual(candidates.map(\.id), [fixture.id, alias.id])
        XCTAssertNil(CurrentEventBroadcastPolicy.currentEvent(for: fixture, in: candidates, at: now))
        XCTAssertNil(CurrentEventBroadcastPolicy.currentEvent(for: fixture, in: catalog, at: now))
        let saved = event("old-publisher-key", at: now, home: "Alpha", away: "Beta")
        XCTAssertEqual(indexed.candidates(for: saved).map(\.id), catalog.map(\.id))
    }

    func testInactiveConflictingAndAmbiguousChannelsNeverWinPreference() throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first)
        let current = fixture.event()
        let willow = channel("willow", title: "Willow Cricket")
        let inactive = channel("fox", title: "Fox Cricket", source: "retired")
        let quarantined = channel("fox", title: "Fox Cricket", conflict: true)
        let duplicate = channel("fox", title: "Fox Cricket")
        for channels in [[inactive, willow], [quarantined, willow], [duplicate, duplicate, willow]] {
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: current,
                in: [current] + channels, at: fixture.kickoff))
        }
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: current,
            in: [current, channel("unknown", title: "Cricket News")], at: fixture.kickoff))
    }

    func testCPLFixtureWindowNeverProvesGenericStationProgramme() throws {
        let fixture = try XCTUnwrap(CPLSchedule.fixtures.first)
        let current = fixture.event()
        let fox = channel("fox", title: "Fox Cricket")
        let catalog = [current, fox]
        for offset: TimeInterval in [-121, -120, 0, 8 * 3600 - 1, 8 * 3600 + 1] {
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: current, in: catalog,
                at: fixture.kickoff.addingTimeInterval(offset)), "\(offset)")
        }
        let lookalike = AnalyticalDataEngine.EventReference(id: "unreviewed-cpl-row", title: current.title,
            category: current.category, date: current.date, poster: nil, popular: nil, teams: current.teams)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: lookalike,
            in: [lookalike, fox], at: fixture.kickoff))
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: current,
            in: catalog, at: fixture.kickoff, status: .postponed))
    }

    func testOmittedOldSavedIntentSurvivesRefreshAndRecreationWithoutOldSources() throws {
        let h = try JourneyHarness(now: now)
        defer { h.clean() }
        let old = event(at: Date().addingTimeInterval(-72 * 3600))
        h.matchday.save(old)
        let savedAt = try XCTUnwrap(h.matchday.savedMatches.first?.savedAt)
        h.matchday.reconcile(events: [], at: Date())
        let recreated = MyMatchdayStore(defaults: h.defaults)
        let record = try XCTUnwrap(recreated.savedMatches.first)
        XCTAssertEqual(record.id, old.id)
        XCTAssertEqual(record.savedAt, savedAt)
        XCTAssertEqual(record.event.kickoffDate, old.kickoffDate)
    }

    func testReschedulePreservesSavedIdentityAndReminderRouteThroughRecreation() async throws {
        let h = try JourneyHarness(now: now)
        defer { h.clean() }
        let original = event(at: now.addingTimeInterval(7200))
        _ = await h.reminders.enable(original)
        let savedAt = try XCTUnwrap(h.matchday.savedMatches.first?.savedAt)
        let notificationID = try XCTUnwrap(h.client.pending.values.first?.identifier)
        let changed = event(at: now.addingTimeInterval(10_800))
        h.matchday.reconcile(events: [changed], at: now)
        await h.reminders.reconcile(events: [changed])
        let recreated = MyMatchdayStore(defaults: h.defaults)
        let record = try XCTUnwrap(recreated.savedMatches.first)
        XCTAssertEqual(recreated.savedMatches.count, 1)
        XCTAssertEqual(record.id, original.id)
        XCTAssertEqual(record.savedAt, savedAt)
        XCTAssertEqual(record.previousDate, original.date)
        XCTAssertEqual(record.event.kickoffDate, changed.kickoffDate)
        XCTAssertEqual(h.reminders.records.first?.id, original.id)
        XCTAssertEqual(h.reminders.records.first?.fireDate, now.addingTimeInterval(10_500))
        XCTAssertEqual(h.client.pending.count, 1)
        XCTAssertEqual(h.client.pending.values.first?.identifier, notificationID)
        let adds = h.client.adds
        await h.reminders.reconcile(events: [changed])
        XCTAssertEqual(h.client.adds, adds)
    }

    func testFreshSourceWithdrawalClearsSavedAndReminderSnapshots() async throws {
        let h = try JourneyHarness(now: now)
        defer { h.clean() }
        let original = event(at: now.addingTimeInterval(7200))
        _ = await h.reminders.enable(original)
        let fresh = event(at: original.kickoffDate, source: nil)
        h.matchday.reconcile(events: [fresh], at: now)
        await h.reminders.reconcile(events: [fresh])
        let saved = try XCTUnwrap(h.matchday.savedMatches.first)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: saved.event, in: [fresh],
            at: try XCTUnwrap(fresh.kickoffDate)))
        XCTAssertEqual(h.client.pending.count, 1, "A withdrawn source is not a withdrawn reminder opt-in")
    }

    func testConflictingOrReusedIDsCannotReplaceSavedOrRemindedMatch() async throws {
        let h = try JourneyHarness(now: now)
        defer { h.clean() }
        let original = event(at: now.addingTimeInterval(7200))
        _ = await h.reminders.enable(original)
        let saved = try XCTUnwrap(h.matchday.savedMatches.first)
        let reminder = try XCTUnwrap(h.reminders.records.first)
        let changed = event(at: now.addingTimeInterval(10_800))
        let reused = event(at: now.addingTimeInterval(10_800), home: "Other Club")
        let quarantined = event(at: now.addingTimeInterval(10_800), conflict: true)
        for rows in [[changed, changed], [reused], [quarantined]] {
            h.matchday.reconcile(events: rows, at: now)
            await h.reminders.reconcile(events: rows)
            XCTAssertEqual(h.matchday.savedMatches.first, saved)
            XCTAssertEqual(h.reminders.records.first, reminder)
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: saved.event, in: rows,
                at: try XCTUnwrap(original.kickoffDate)))
        }
    }

    func testSourceOnlyRefreshDoesNotEraseDeliveredNotificationOrScheduleTwice() async throws {
        let h = try JourneyHarness(now: now)
        defer { h.clean() }
        let original = event(at: now.addingTimeInterval(900))
        _ = await h.reminders.enable(original)
        let request = try XCTUnwrap(h.client.pending.values.first)
        h.client.pending.removeValue(forKey: request.identifier)
        h.client.delivered[request.identifier] = request
        h.clock.now = now.addingTimeInterval(660)
        let fresh = event(at: original.kickoffDate, source: "echo")
        await h.reminders.reconcile(events: [fresh])
        XCTAssertNotNil(h.client.delivered[request.identifier])
        XCTAssertTrue(h.client.pending.isEmpty)
        XCTAssertEqual(h.client.adds, 1)
    }

    func testRestoreCancelsReminderOptInStillAwaitingAuthorization() async throws {
        let h = try JourneyHarness(now: now)
        defer { h.clean() }
        h.client.onStatus = { h.reminders.cancelAllForRestore() }
        let result = await h.reminders.enable(event(at: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(h.reminders.records.isEmpty)
        XCTAssertTrue(h.reminders.busyIDs.isEmpty)
        XCTAssertTrue(h.matchday.savedMatches.isEmpty)
        XCTAssertTrue(h.client.pending.isEmpty)
    }

    func testLegacySavedSnapshotWithoutRescheduleFieldStillDecodes() throws {
        let record = SavedMatchRecord(event: event(at: now))
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "previousDate")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SavedMatchRecord.self, from: legacy)
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertNil(decoded.previousDate)
    }

    /// Builds 261 and earlier decode `sources` as a required key. Saved
    /// matches reach them through sync, handoff and backup restore.
    func testSavedSnapshotKeepsTheSourcesKeyOlderBuildsRequire() throws {
        let record = SavedMatchRecord(event: event(at: now))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        XCTAssertEqual((object["sources"] as? [Any])?.count, 0)
        var old = object
        old["sources"] = [["source": "delta", "id": "old-route"]]
        let decoded = try JSONDecoder().decode(SavedMatchRecord.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded, record, "A stored route from an old build is ignored, not an error")
    }

    func testFailedMatchdayWritesNeverPublishAFalseSaveOrRemoval() throws {
        let suite = "FottyTests.MatchdayFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storageKey = "test.matchday.failure"
        let original = event(at: now.addingTimeInterval(7_200))
        let working = MyMatchdayStore(defaults: defaults, storageKey: storageKey)
        XCTAssertEqual(working.save(original), .saved)
        let savedData = try XCTUnwrap(defaults.data(forKey: storageKey))

        var removedIDs: [String] = []
        let failing = MyMatchdayStore(
            defaults: defaults,
            storageKey: storageKey,
            onRemove: { removedIDs.append($0) },
            persistenceWriter: { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        )
        let replacement = event("other", at: now.addingTimeInterval(10_800))

        guard case .failed(let addMessage) = failing.save(replacement) else {
            return XCTFail("A failed write must report failure")
        }
        XCTAssertTrue(addMessage.contains("previous saved list is unchanged"))
        XCTAssertEqual(failing.savedMatches.map(\.id), [original.id])
        XCTAssertEqual(defaults.data(forKey: storageKey), savedData)

        guard case .failed = failing.remove(eventID: original.id) else {
            return XCTFail("A failed removal must report failure")
        }
        XCTAssertEqual(failing.savedMatches.map(\.id), [original.id])
        XCTAssertEqual(defaults.data(forKey: storageKey), savedData)
        XCTAssertTrue(removedIDs.isEmpty, "A reminder must not be cancelled after a failed bookmark removal")
    }

    func testReminderIsRolledBackWhenItsRequiredMatchdaySaveFails() async throws {
        let suite = "FottyTests.MatchdayReminderFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = JourneyNotifications()
        let failingMatchday = MyMatchdayStore(
            defaults: defaults,
            persistenceWriter: { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        )
        let reminder = MatchReminderStore(
            defaults: defaults,
            client: client,
            matchday: failingMatchday,
            clock: { self.now }
        )

        let result = await reminder.enable(event(at: now.addingTimeInterval(7_200)))

        XCTAssertEqual(result, .failed)
        XCTAssertTrue(reminder.records.isEmpty)
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertTrue(failingMatchday.savedMatches.isEmpty)
    }
}

@MainActor
private final class JourneyClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private final class JourneyHarness {
    let suite = "FottyTests.MatchdayJourney.\(UUID().uuidString)"
    let defaults: UserDefaults
    let client = JourneyNotifications()
    let matchday: MyMatchdayStore
    let clock: JourneyClock
    let reminders: MatchReminderStore

    init(now: Date) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        matchday = MyMatchdayStore(defaults: defaults)
        clock = JourneyClock(now)
        let clock = self.clock
        reminders = MatchReminderStore(defaults: defaults, client: client, matchday: matchday, clock: { clock.now })
        let reminders = self.reminders
        matchday.onRemove = { [weak reminders] in reminders?.cancel($0) }
    }

    func clean() {
        client.onStatus = nil
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class JourneyNotifications: MatchReminderNotificationClient {
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: [String: UNNotificationRequest] = [:]
    var adds = 0
    var onStatus: (() -> Void)?
    func authorizationStatus() async -> UNAuthorizationStatus { onStatus?(); return .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func add(_ request: UNNotificationRequest) async throws {
        adds += 1
        pending[request.identifier] = request
    }
    func remove(_ identifiers: [String]) {
        for id in identifiers {
            pending.removeValue(forKey: id)
            delivered.removeValue(forKey: id)
        }
    }
}
