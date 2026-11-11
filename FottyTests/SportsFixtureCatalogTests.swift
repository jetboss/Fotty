import XCTest
@testable import Fotty

@MainActor
final class SportsFixtureCatalogTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-30T14:00:00Z")!
    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func fixture(_ nativeID: String = "1", sport: String = "basketball", competition: String = "nba",
                         status: SportsFixtureCatalog.Status = .scheduled, kind: SportsFixtureCatalog.EventKind = .match,
                         hours: Double = 1, observedAt: Date? = nil,
                         verification: SportsFixtureCatalog.Source.Verification? = nil) -> SportsFixtureCatalog.Fixture {
        let participants: [SportsFixtureCatalog.Participant] = kind == .match
            ? [.init(id: "boston", name: "Boston Celtics"), .init(id: "new-york", name: "New York Knicks")] : []
        return .init(id: "sports-fixture:\(competition):\(nativeID)", sport: sport,
            start: stamp(now.addingTimeInterval(hours * 3600)), status: status, eventKind: kind,
            title: kind == .match ? "Boston Celtics vs New York Knicks" : "Singapore Grand Prix · Qualifying",
            competitionId: competition, competitionName: competition.uppercased(), participants: participants,
            squad: .init(gender: .men, ageGroup: "senior"),
            source: .init(name: "Official schedule", url: "https://www.espn.com/nba/schedule",
                          observedAt: stamp(observedAt ?? now), verification: verification))
    }
    private func snapshot(_ rows: [SportsFixtureCatalog.Fixture], receipt: Date? = nil,
                          status: SportsFixtureCatalog.SourceStatus = .verified,
                          unavailable: [String] = [], laneReceipt: Date? = nil) -> SportsFixtureCatalog.Snapshot {
        let ids = Set(rows.map(\.competitionId)).union(unavailable).union(["nba"])
        let coverage = ids.sorted().map { id in
            SportsFixtureCatalog.Coverage(sport: rows.first { $0.competitionId == id }?.sport ?? "basketball",
                competitionId: id, competitionName: rows.first { $0.competitionId == id }?.competitionName ?? id.uppercased(),
                status: unavailable.contains(id) ? .unavailable : .covered,
                checkedAt: stamp(laneReceipt ?? receipt ?? now), fixtureCount: rows.filter { $0.competitionId == id }.count,
                pendingFixtureCount: 0, nextStart: nil)
        }
        return .init(schemaVersion: 1, complete: true, checkedAt: stamp(receipt ?? now), revision: "test-1",
                     sourceStatus: status, fixtures: rows, coverage: coverage)
    }
    private func provider(_ id: String = "provider", competition: String? = "nba", sport: String = "basketball",
                          hours: Double = 1, home: String = "Boston Celtics", title: String? = nil) -> EventReference {
        .init(id: id, title: title ?? "\(home) vs New York Knicks", category: sport,
            date: Int64(now.addingTimeInterval(hours * 3600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: "New York Knicks", badge: nil)), competitionID: competition)
    }

    func testValidatedReceiptAndOldJSONCompatibility() throws {
        let expected = snapshot([fixture()])
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(expected), now: now), expected)
        let old = try JSONDecoder().decode(EventReference.self, from: Data(#"{"id":"old","title":"A vs B","category":"basketball"}"#.utf8))
        XCTAssertNil(old.sportsFixture)
        XCTAssertNil(old.competitionID)
        let coverage = SportsFixtureCatalog.Coverage(sport: "rugby", competitionId: "unavailable-league",
            competitionName: "Unavailable League", status: .unsupported, checkedAt: nil,
            fixtureCount: 0, pendingFixtureCount: 3, nextStart: nil)
        let empty = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: stamp(now),
            revision: "empty-1", sourceStatus: .partial, fixtures: [], coverage: [coverage])
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(empty), now: now), empty)
    }

    func testForegroundPreflightCanFindLateSourcesBeforePlaybackWindowWithoutOfferingWatch() throws {
        let row = carabaoFixture(id: "preflight-only", hours: 1.0 / 3.0, status: .scheduled)
        let catalog = SportsFixtureCatalog.merging(into: [], snapshot: snapshot([row]), at: now)
        let event = try XCTUnwrap(catalog.first)
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: event, in: catalog,
            enabledProviderCodes: ["communitysports"], at: now))
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: event, in: catalog,
            enabledProviderCodes: ["communitysports"], at: now, phase: .preflight))
        XCTAssertFalse(MatchStartPolicy(event: event, now: now).canAttemptPlayback)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: catalog, at: now))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: event, in: catalog,
            enabledProviderCodes: ["communitysports"], at: now.addingTimeInterval(-3600), phase: .preflight))
    }

    func testCurrentExactDiscoveryCanOfferWatchButExpiresWithoutInventingCatalogSources() throws {
        let row = carabaoFixture(id: "discovered-choice", hours: -0.1, status: .live)
        let catalog = SportsFixtureCatalog.merging(into: [], snapshot: snapshot([row]), at: now)
        let event = try XCTUnwrap(catalog.first)
        let request = StreamPlaybackRequest(event: event)
        // Isolate fixed historical fixture time from other suites' real-time
        // candidate observations; do not reset the production clock fence.
        let index = FixtureStreamDiscoveryIndex()
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_cup", streamID: "nuvio_sport_cup", manifestRevision: "1",
            verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
        let session = StreamSession(matchID: request.matchID,
            playableURL: URL(string: "https://nuviosports.xyz/api/manifest.m3u8")!, streamType: .hls,
            providerName: "CS1").recordingEventBinding(binding, for: request, at: now)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: now))
        index.complete(ticket, sessions: [session], at: now)
        XCTAssertTrue(MatchStartPolicy(event: event, now: now, discoveryIndex: index).canAttemptPlayback)
        XCTAssertEqual(MatchStartPolicy(event: event, now: now, discoveryIndex: index).title, "Watch")
        XCTAssertNotNil(CurrentEventBroadcastPolicy.action(for: event, in: catalog, at: now, discoveryIndex: index))
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: catalog, at: now,
            useDiscoveryIndex: false, discoveryIndex: index))
        XCTAssertFalse(MatchStartPolicy(event: event, now: now.addingTimeInterval(60), discoveryIndex: index).canAttemptPlayback)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: catalog,
            at: now.addingTimeInterval(60), discoveryIndex: index))
    }

    func testExplicitRowMarkersAreOptionalButNullUnknownAndCoveredHeldFailClosed() throws {
        let valid = snapshot([fixture(verification: .verified)])
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(valid), now: now), valid)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        let rows = try XCTUnwrap(json["fixtures"] as? [[String: Any]])
        for marker: Any in [NSNull(), "future-status", "held"] {
            var row = rows[0]
            var source = try XCTUnwrap(row["source"] as? [String: Any])
            source["verification"] = marker; row["source"] = source; json["fixtures"] = [row]
            XCTAssertThrowsError(try SportsFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now))
        }
    }

    func testUnavailableCohortAdmitsVerifiedRowsWithoutRefreshingHeldFacts() throws {
        let previous = now.addingTimeInterval(-600)
        let oldRows = [fixture("one", hours: -1, observedAt: previous), fixture("two", observedAt: previous)]
        let candidateRows = [fixture("one", status: .live, hours: -1, verification: .verified),
                             fixture("two", observedAt: previous, verification: .held)]
        let candidate = snapshot(candidateRows, status: .partial, unavailable: ["nba"], laneReceipt: previous)
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(candidate), now: now), candidate)
        let accepted = SportsFixtureCatalog.accepting(candidate, over: snapshot(oldRows, receipt: previous))
        XCTAssertEqual(accepted.coverage.first?.checkedAt, stamp(previous))
        XCTAssertEqual(accepted.fixtures.first { $0.id == oldRows[1].id }?.source.observedAt, stamp(previous))
        let rows = SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: now)
        XCTAssertTrue(rows.first { $0.id == oldRows[0].id }?.sportsFixture?.isLive(at: now) == true)
        XCTAssertTrue(rows.first { $0.id == oldRows[1].id }?.sportsFixture?.verified == false)
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(accepted), now: now), accepted)
    }

    func testUnavailableExplicitReceiptExpiresAndWholeFailureDemotesEveryRow() throws {
        let current = fixture(verification: .verified)
        let accepted = snapshot([current], status: .partial, unavailable: ["nba"])
        let expiredAt = now.addingTimeInterval(SportsFixtureCatalog.statusFreshness + 1)
        let expired = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: expiredAt).first)
        XCTAssertFalse(expired.sportsFixture?.verified ?? true)
        XCTAssertNil(MatchStartPolicy(event: expired, now: expiredAt).upcomingStart)
        let failed = SportsFixtureCatalog.accepting(snapshot([], status: .partial, unavailable: ["nba"]), over: accepted)
        XCTAssertEqual(failed.fixtures.first?.source.verification, .held)
        XCTAssertEqual(failed.fixtures.first?.source.observedAt, current.source.observedAt)
        XCTAssertFalse(try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: failed, at: now).first).sportsFixture?.verified ?? true)
    }

    func testPerRowAdmissionRejectsReceiptReplaySchedulingChangesAndTerminalResurrection() {
        let previous = now.addingTimeInterval(-600)
        let live = fixture(status: .live, hours: -1, observedAt: previous, verification: .verified)
        let heldSnapshot = snapshot([live], receipt: previous)
        for next in [fixture(status: .scheduled, hours: -1, verification: .verified),
                     fixture(status: .live, hours: 2, verification: .verified),
                     fixture(status: .live, hours: -1, observedAt: previous.addingTimeInterval(-1), verification: .verified)] {
            let accepted = SportsFixtureCatalog.accepting(snapshot([next], status: .partial, unavailable: ["nba"], laneReceipt: previous), over: heldSnapshot)
            XCTAssertEqual(accepted.fixtures.first?.start, live.start)
            XCTAssertEqual(accepted.fixtures.first?.status, live.status)
            XCTAssertEqual(accepted.fixtures.first?.source.verification, .held)
        }
        let terminal = fixture(status: .finished, hours: -1, observedAt: previous, verification: .verified)
        let resurrected = SportsFixtureCatalog.accepting(snapshot([fixture(status: .live, hours: -1, verification: .verified)],
            status: .partial, unavailable: ["nba"], laneReceipt: previous), over: snapshot([terminal], receipt: previous))
        XCTAssertEqual(resurrected.fixtures.first?.status, .finished)
        for status in [SportsFixtureCatalog.Status.unknown, .postponed] {
            let rollback = SportsFixtureCatalog.accepting(snapshot([fixture(status: status, hours: -1, verification: .verified)],
                status: .partial, unavailable: ["nba"], laneReceipt: previous), over: snapshot([terminal], receipt: previous))
            XCTAssertEqual(rollback.fixtures.first?.status, .finished)
        }
    }

    func testIsolatedSchedulingCorrectionRequiresConfirmedNewerProofAndEmptyLaneCannotReplay() {
        let previous = now.addingTimeInterval(-600)
        let old = fixture(status: .live, hours: -1, observedAt: previous, verification: .verified)
        let next = fixture(hours: 2, verification: .verified)
        let corrected = SportsFixtureCatalog.Fixture(id: next.id, sport: next.sport, start: next.start,
            status: next.status, eventKind: next.eventKind, title: next.title, competitionId: next.competitionId,
            competitionName: next.competitionName, participants: next.participants, squad: next.squad,
            source: .init(name: next.source.name, url: next.source.url, observedAt: next.source.observedAt,
                correctionConfirmedAt: stamp(now.addingTimeInterval(-300)), verification: .verified))
        let admitted = SportsFixtureCatalog.accepting(snapshot([corrected], status: .partial, unavailable: ["nba"], laneReceipt: previous),
            over: snapshot([old], receipt: previous))
        XCTAssertEqual(admitted.fixtures.first?.start, corrected.start)
        XCTAssertEqual(admitted.fixtures.first?.source.verification, .verified)
        let empty = snapshot([], receipt: now)
        let replay = fixture(observedAt: previous, verification: .verified)
        XCTAssertTrue(SportsFixtureCatalog.accepting(snapshot([replay], status: .partial, unavailable: ["nba"], laneReceipt: previous),
            over: empty).fixtures.isEmpty)
    }

    func testUnverifiedFutureSportsStayUnconfirmedAcrossHomeMatchdayCountdownAndReminder() throws {
        for (sport, competition) in [("basketball", "nba"), ("baseball", "mlb"), ("hockey", "nhl"), ("motorsport", "f1")] {
            let kind: SportsFixtureCatalog.EventKind = sport == "motorsport" ? .session : .match
            let event = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: snapshot([
                fixture(sport: sport, competition: competition, kind: kind)], status: .partial, unavailable: [competition]), at: now).first)
            XCTAssertEqual(HomeSportsDiscovery(events: [event], now: now).items.first?.phase, .unconfirmed, sport)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now), .awaitingConfirmation, sport)
            XCTAssertNil(MatchStartPolicy(event: event, now: now).upcomingStart, sport)
            XCTAssertEqual(event.broadcastTiming(at: now), .available, sport)
            XCTAssertNil(MatchReminderRecord.make(event: event, now: now), sport)
        }
    }

    private func reviewedLeague(_ league: String, id: String = "one", hours: Double = 1,
                                status: SportsFixtureCatalog.Status = .scheduled) -> SportsFixtureCatalog.Fixture {
        let sport = league == "mlb" ? "baseball" : "hockey"
        let pair = league == "mlb" ? ("Atlanta Braves", "Los Angeles Dodgers") : ("Buffalo Sabres", "Minnesota Wild")
        return .init(id: "sports-fixture:\(league):\(id)", sport: sport, start: stamp(now.addingTimeInterval(hours * 3600)),
            status: status, eventKind: .match, title: "\(pair.0) vs \(pair.1)", competitionId: league, competitionName: league.uppercased(),
            participants: [.init(id: "home", name: pair.0, role: "home"), .init(id: "away", name: pair.1, role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"),
            source: .init(name: "Official schedule", url: "https://example.com/fixtures", observedAt: stamp(now)))
    }
    private func unmarkedProvider(_ row: SportsFixtureCatalog.Fixture, id: String = "plain-provider",
                                  seconds: Double = 0, competition: String? = nil, title: String? = nil) -> EventReference {
        .init(id: id, title: title ?? row.title, category: row.sport,
            date: Int64(row.kickoff!.addingTimeInterval(seconds).timeIntervalSince1970 * 1000), poster: nil, popular: false,
            teams: .init(home: .init(name: row.participants[0].name, badge: nil), away: .init(name: row.participants[1].name, badge: nil)), competitionID: competition)
    }

    private func arsenalFixture(id: String = "560593", competition: String = "premier-league",
                                start: Date? = nil, receipt: Date? = nil,
                                squad: SportsFixtureCatalog.Squad = .init(gender: .men, ageGroup: "senior")) -> SportsFixtureCatalog.Fixture {
        .init(id: "sports-fixture:\(competition):\(id)", sport: "football",
            start: stamp(start ?? now.addingTimeInterval(3600)), status: .scheduled, eventKind: .match,
            title: "Arsenal FC vs Leeds United FC", competitionId: competition,
            competitionName: competition == "premier-league" ? "Premier League" : competition == "fa-cup" ? "FA Cup" : "UEFA Champions League",
            participants: [.init(id: "football-data:57", name: "Arsenal FC", role: "home"),
                           .init(id: "football-data:341", name: "Leeds United FC", role: "away")],
            squad: squad, source: .init(name: "football-data.org", url: "https://www.football-data.org/",
                observedAt: stamp(receipt ?? now)))
    }

    private func arsenalProvider(_ row: SportsFixtureCatalog.Fixture, id: String = "ppv-arsenal-vs-leeds-united",
                                 seconds: Double = 0, competition: String? = nil,
                                 title: String = "Arsenal vs. Leeds United") -> EventReference {
        .init(id: id, title: title, category: "football",
            date: Int64(row.kickoff!.addingTimeInterval(seconds).timeIntervalSince1970 * 1000), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Leeds United", badge: nil)), competitionID: competition)
    }

    private func carabaoFixture(id: String = "test-liverpool-chelsea", competition: String = "carabao-cup",
                                hours: Double = -1, status: SportsFixtureCatalog.Status = .live,
                                squad: SportsFixtureCatalog.Squad = .init(gender: .men, ageGroup: "senior")) -> SportsFixtureCatalog.Fixture {
        .init(id: "sports-fixture:\(competition):\(id)", sport: "football", start: stamp(now.addingTimeInterval(hours * 3600)),
            status: status, eventKind: .match, title: "Liverpool vs Chelsea", competitionId: competition,
            competitionName: competition == "carabao-cup" ? "Carabao Cup" : "Premier League",
            participants: [.init(id: "test-liverpool", name: "Liverpool", role: "home"),
                           .init(id: "test-chelsea", name: "Chelsea", role: "away")],
            squad: squad, source: .init(name: "EFL", url: "https://www.efl.com/match-hub/",
                observedAt: stamp(now), verification: .verified))
    }

    func testCarabaoJoinRejectsWrongTimeSquadCompetitionHeldProofAndSamePairAmbiguity() {
        let row = carabaoFixture()
        for raw in [unmarkedProvider(row, seconds: 1), unmarkedProvider(row, seconds: 86_400),
                    unmarkedProvider(row, competition: "premier-league"),
                    unmarkedProvider(row, title: "Premier League · Liverpool vs Chelsea"),
                    unmarkedProvider(row, title: "FA Cup · Liverpool vs Chelsea"),
                    unmarkedProvider(row, id: "epl-liverpool-chelsea"),
                    unmarkedProvider(row, id: "ucl-liverpool-chelsea"),
                    unmarkedProvider(row, title: "Liverpool vs Chelsea Women"),
                    unmarkedProvider(row, title: "Liverpool vs Chelsea U19")] {
            let joined = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row]), at: now)
            XCTAssertEqual(joined.count, 2, raw.id + (raw.title ?? ""))
        }
        let raw = unmarkedProvider(row)
        let held = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row], status: .lastKnownGood), at: now)
        XCTAssertEqual(held.count, 2)
        for squad in [SportsFixtureCatalog.Squad(gender: .women, ageGroup: "senior"), .init(gender: .men, ageGroup: "u19")] {
            XCTAssertEqual(SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([carabaoFixture(squad: squad)]), at: now).count, 2)
        }
        let ambiguous = SportsFixtureCatalog.merging(into: [raw],
            snapshot: snapshot([row, carabaoFixture(id: "same-time-league", competition: "premier-league")]), at: now)
        XCTAssertEqual(ambiguous.count, 3)
    }

    func testUnmarkedFootballAdmissionRejectsConflictsHeldProofAndAmbiguousOfficialFixtures() {
        let row = arsenalFixture()
        let invalid = [arsenalProvider(row, seconds: 1), arsenalProvider(row, competition: "fa-cup"),
                       arsenalProvider(row, title: "FA Cup · Arsenal vs Leeds United"),
                       arsenalProvider(row, id: "fa-cup-arsenal-vs-leeds"),
                       arsenalProvider(row, id: "fa-cup-arsenal-vs-leeds", competition: "premier-league"),
                       arsenalProvider(row, title: "Arsenal vs Leeds United Women"),
                       arsenalProvider(row, title: "Arsenal vs Leeds United U19"),
                       arsenalProvider(row, id: "arsenal-u21-vs-leeds-u21")]
        for raw in invalid {
            let joined = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row]), at: now)
            XCTAssertEqual(joined.count, 2, raw.id + raw.title!)
        }
        let raw = arsenalProvider(row)
        let held = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row], status: .partial,
            unavailable: [row.competitionId]), at: now)
        XCTAssertEqual(held.count, 2)
        let second = arsenalFixture(id: "second")
        let ambiguous = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row, second]), at: now)
        XCTAssertEqual(ambiguous.count, 3)
        XCTAssertEqual(AnalyticalDataEngine.deduplicateMatches(ambiguous).count, 3,
                       "A presentation pass must not collapse distinct official fixture IDs after admission refused ambiguity")
        let crossCompetition = SportsFixtureCatalog.merging(into: [raw],
            snapshot: snapshot([row, arsenalFixture(id: "cup", competition: "champions-league")]), at: now)
        XCTAssertEqual(crossCompetition.count, 3)
        let sameTimeCup = SportsFixtureCatalog.merging(into: [raw],
            snapshot: snapshot([row, arsenalFixture(id: "cup", competition: "fa-cup")]), at: now)
        XCTAssertEqual(sameTimeCup.count, 3, "An unmarked record must never hide a same-time Premier League/cup conflict")
        for squad in [SportsFixtureCatalog.Squad(gender: .women, ageGroup: "senior"), .init(gender: .men, ageGroup: "u19")] {
            XCTAssertEqual(SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([arsenalFixture(squad: squad)]), at: now).count, 2)
        }
    }

    func testUnmarkedLeagueJoinRejectsWrongTimeExplicitLeagueQualifiersAndAmbiguity() {
        for league in ["mlb", "nhl"] {
            let row = reviewedLeague(league)
            for raw in [unmarkedProvider(row, seconds: 1), unmarkedProvider(row, competition: "other-league"),
                        unmarkedProvider(row, title: row.title + " Women"), unmarkedProvider(row, title: row.title + " U19"),
                        unmarkedProvider(row, title: (league == "mlb" ? "NPB " : "KHL ") + row.title)] {
                let catalog = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row]), at: now)
                XCTAssertEqual(catalog.count, 2)
            }
            let raw = unmarkedProvider(row)
            let doubleheader = SportsFixtureCatalog.merging(into: [raw],
                snapshot: snapshot([row, reviewedLeague(league, id: "second")]), at: now)
            XCTAssertEqual(doubleheader.count, 3)
            let held = SportsFixtureCatalog.merging(into: [raw], snapshot: snapshot([row], status: .partial, unavailable: [league]), at: now)
            XCTAssertEqual(held.count, 2, "A held official identity cannot authorize a new unmarked league join")
        }
    }

    func testProviderOnlyElapsedStartNeverBecomesVisibleLIVE() {
        let raw = provider(competition: nil, sport: "baseball", hours: -1)
        XCTAssertEqual(raw.broadcastTiming(at: now), .live, "Internal broadcast-window heuristic is not live evidence")
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: raw, at: now), .awaitingConfirmation)
        XCTAssertEqual(MatchdayEventStatePolicy.presentationLabel(for: raw, at: now), "Start unconfirmed")
        XCTAssertEqual(MatchdayEventStatePolicy.presentationLabel(for: raw, at: now.addingTimeInterval(24 * 3600)), "Start unconfirmed",
                       "An unknown baseball duration cannot establish an estimated final whistle")
    }

    func testHeldCricketFutureIsUnconfirmedInMatchdayAsWellAsHome() {
        let metadata = CricketFixtureMetadata(fixtureID: "cricket-fixture:icc:held", competitionID: "icc",
            competitionName: "ICC", format: .t20, status: .scheduled, observedAt: now, verified: false)
        let event = EventReference(id: metadata.fixtureID, title: "West Indies vs India", category: "cricket",
            date: Int64(now.addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "West Indies", badge: nil), away: .init(name: "India", badge: nil)), cricketFixture: metadata)
        XCTAssertEqual(HomeSportsDiscovery(events: [event], now: now).items.first?.phase, .unconfirmed)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: event, at: now), .awaitingConfirmation)
        XCTAssertEqual(MatchdayEventStatePolicy.presentationLabel(for: event, at: now), "Start unconfirmed")
    }

    func testMotorsportNormalizedAliasesExposeReviewedSearchVocabulary() {
        for category in ["motorsport", "motor-sports", "motorsports", "f1"] {
            let event = EventReference(id: "f1-spanish-grand-prix", title: "Spanish Grand Prix", category: category,
                date: Int64(now.addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil)
            let discovery = HomeSportsDiscovery(events: [event], now: now)
            XCTAssertEqual(HomeSportsSearch.results(in: discovery, query: "Formula One").map(\.id), [event.id], category)
            XCTAssertEqual(HomeSportsSearch.results(in: discovery, query: "Formula 1").map(\.id), [event.id], category)
            XCTAssertTrue(HomeSportsSearch.results(in: discovery, query: "NBA").isEmpty)
        }
    }

    func testMissingRowsTimezoneAndPlaceholderParticipantsAreRejected() throws {
        let payload = try JSONEncoder().encode(snapshot([fixture()]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        json["fixtures"] = []
        XCTAssertThrowsError(try SportsFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now))
        XCTAssertThrowsError(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(snapshot([fixture(), fixture()])), now: now))
        XCTAssertNil(SportsFixtureCatalog.date("2026-09-30T14:00:00"))
        let source = fixture()
        let bad = SportsFixtureCatalog.Fixture(id: source.id, sport: source.sport, start: source.start, status: source.status,
            eventKind: source.eventKind, title: source.title, competitionId: source.competitionId,
            competitionName: source.competitionName, participants: [.init(id: "a", name: "TBD"), .init(id: "b", name: "B")],
            squad: source.squad, source: source.source)
        XCTAssertThrowsError(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(snapshot([bad])), now: now))
    }

    func testReusedFixtureDateParserPreservesLegacyAcceptance() {
        let values = [
            "2026-09-30T14:00:00Z", "2026-09-30T14:00:00.123Z",
            "2026-09-30T10:00:00-04:00", "2026-10-01T03:30:00.987+13:30",
            "2026-09-30T14:00:00", "2026-09-30", "2026-09-30T14:00:00Z ",
            "", "invalidZ", "2026-09-30T14:00:00+99:99"
        ]
        func legacyDate(_ value: String) -> Date? {
            guard value.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        let expected = values.map(legacyDate)
        for _ in 0..<3 {
            for (index, value) in values.enumerated() {
                XCTAssertEqual(SportsFixtureCatalog.date(value), expected[index], value)
                XCTAssertEqual(CricketFixtureCatalog.date(value), expected[index], value)
            }
        }
    }

    func testReusedFixtureDateParserSupportsConcurrentValidation() {
        let inputs = ["2026-09-30T14:00:00Z", "2026-09-30T10:00:00-04:00",
                      "2026-09-30T14:00:00.125Z"]
        let expected = [now, now, now.addingTimeInterval(0.125)]
        DispatchQueue.concurrentPerform(iterations: 120) { iteration in
            let index = iteration % inputs.count
            XCTAssertEqual(SportsFixtureCatalog.date(inputs[index]), expected[index])
            XCTAssertEqual(CricketFixtureCatalog.date(inputs[index]), expected[index])
        }
    }

    func testBoundedISO8601ResultCachePreservesUncachedParsing() {
        let values = [
            "2026-09-30T14:00:00Z", "2026-09-30T14:00:01Z",
            "2026-09-30T14:00:00.125Z", "2026-09-30T14:00:00.250Z",
            "2026-09-30T10:00:00-04:00", "2026-10-01T03:30:00.987+13:30",
            "1970-01-01T00:00:00Z", "2000-02-29T23:59:59Z", "2100-02-29T00:00:00Z",
            "2026-09-30T14:00:00", "2026-09-30", "2026-09-30T14:00:00z",
            "2026-09-30T14:00:00Z ", " 2026-09-30T14:00:00Z",
            "", "invalidZ", "2026-09-30T14:00:00+99:99",
            "2026-09-30T14:00:00Z" + String(repeating: " ", count: 236),
            "2026-09-30T14:00:00Z" + String(repeating: " ", count: 237),
            String(repeating: "\u{2003}", count: 100) + "2026-09-30T14:00:00Z"
        ]
        let expected = uncachedCatalogISO8601Dates(values)
        for _ in 0..<4 {
            for (index, value) in values.enumerated() {
                XCTAssertEqual(CatalogISO8601DateParser.date(value), expected[index], value)
            }
        }
    }

    func testBoundedISO8601ResultCacheSupportsConcurrentChurn() {
        // More exact keys than the cache's count limit exercise misses and
        // eviction without making retention/eviction order part of the API.
        let values = (0..<600).map { index in
            String(format: "2026-10-01T00:%02d:%02dZ", index / 60, index % 60)
        } + ["invalidZ", "", "2026-09-30T14:00:00.125Z", "2026-09-30T10:00:00-04:00",
             "2026-09-30T14:00:00Z" + String(repeating: " ", count: 237)]
        let expected = uncachedCatalogISO8601Dates(values)
        DispatchQueue.concurrentPerform(iterations: values.count * 2) { iteration in
            let index = iteration % values.count
            XCTAssertEqual(CatalogISO8601DateParser.date(values[index]), expected[index])
        }
        for (index, value) in values.enumerated() {
            XCTAssertEqual(CatalogISO8601DateParser.date(value), expected[index], value)
        }
    }

    private func uncachedCatalogISO8601Dates(_ values: [String]) -> [Date?] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return values.map { fractional.date(from: $0) ?? wholeSeconds.date(from: $0) }
    }

    func testUnavailableAndOlderCompetitionKeepAcceptedFactsAndReceipt() throws {
        let oldTime = now.addingTimeInterval(-3600)
        let old = snapshot([fixture(observedAt: oldTime)], receipt: oldTime)
        let unavailable = snapshot([], status: .partial, unavailable: ["nba"])
        let kept = SportsFixtureCatalog.accepting(unavailable, over: old)
        XCTAssertEqual(kept.fixtures, old.fixtures)
        XCTAssertEqual(kept.coverage.first?.checkedAt, stamp(oldTime))
        XCTAssertEqual(kept.coverage.first?.status, .unavailable)
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(kept), now: now), kept)
        let replay = snapshot([], receipt: now, laneReceipt: oldTime.addingTimeInterval(-60))
        XCTAssertEqual(SportsFixtureCatalog.accepting(replay, over: old).fixtures, old.fixtures)
        XCTAssertEqual(SportsFixtureCatalog.accepting(replay, over: old).coverage.first?.checkedAt, stamp(oldTime))
        XCTAssertTrue(SportsFixtureCatalog.accepting(snapshot([]), over: old).fixtures.isEmpty)
    }

    func testFailedLaneDoesNotBlockAnIndependentSuccessfulCompetition() {
        let oldTime = now.addingTimeInterval(-3600)
        let old = snapshot([fixture(observedAt: oldTime)], receipt: oldTime)
        let fresh = fixture("2", sport: "hockey", competition: "nhl")
        let accepted = SportsFixtureCatalog.accepting(snapshot([fresh], status: .partial, unavailable: ["nba"]), over: old)
        XCTAssertEqual(Set(accepted.fixtures.map(\.competitionId)), ["nba", "nhl"])
        XCTAssertEqual(accepted.coverage.first { $0.competitionId == "nba" }?.checkedAt, stamp(oldTime))
        XCTAssertEqual(accepted.coverage.first { $0.competitionId == "nhl" }?.checkedAt, stamp(now))
    }

    func testOlderAggregateCannotBlockNewerReceiptForAnotherCompetition() {
        let later = now.addingTimeInterval(120)
        let oldNBA = fixture(observedAt: later)
        let oldNHL = fixture("2", sport: "hockey", competition: "nhl")
        let old = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: stamp(later),
            revision: "two-1", sourceStatus: .verified, fixtures: [oldNBA, oldNHL], coverage: [
                .init(sport: "basketball", competitionId: "nba", competitionName: "NBA", status: .covered,
                    checkedAt: stamp(later), fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil),
                .init(sport: "hockey", competitionId: "nhl", competitionName: "NHL", status: .covered,
                    checkedAt: stamp(now), fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)])
        let newerNHL = fixture("2", sport: "hockey", competition: "nhl", status: .postponed,
            observedAt: now.addingTimeInterval(60))
        let accepted = SportsFixtureCatalog.accepting(snapshot([newerNHL], receipt: now.addingTimeInterval(60),
            status: .partial, unavailable: ["nba"]), over: old)
        XCTAssertEqual(accepted.fixtures.first { $0.competitionId == "nhl" }?.status, .postponed)
        XCTAssertEqual(accepted.coverage.first { $0.competitionId == "nba" }?.checkedAt, stamp(later))
        XCTAssertEqual(accepted.checkedAt, stamp(later))
    }

    func testStableIDCannotChangeSquadOrRegressTerminalStatus() {
        let row = fixture()
        let changed = SportsFixtureCatalog.Fixture(id: row.id, sport: row.sport, start: row.start, status: row.status,
            eventKind: row.eventKind, title: row.title, competitionId: row.competitionId, competitionName: row.competitionName,
            participants: row.participants, squad: .init(gender: .women, ageGroup: "senior"), source: row.source)
        XCTAssertEqual(SportsFixtureCatalog.accepting(snapshot([changed]), over: snapshot([row])).fixtures, [row])
        let ended = fixture(status: .finished)
        XCTAssertEqual(SportsFixtureCatalog.accepting(snapshot([fixture(status: .live)]), over: snapshot([ended])).fixtures, [ended])
    }

    func testRepeatedServerCorrectionProofCanReachAnOfflineClientLater() throws {
        let oldTime = now.addingTimeInterval(-600)
        let oldRow = fixture(observedAt: oldTime)
        let changed = SportsFixtureCatalog.Fixture(id: oldRow.id, sport: oldRow.sport, start: oldRow.start,
            status: oldRow.status, eventKind: oldRow.eventKind, title: oldRow.title,
            competitionId: oldRow.competitionId, competitionName: oldRow.competitionName,
            participants: [.init(id: "different", name: "Different Team"), oldRow.participants[1]], squad: oldRow.squad,
            source: .init(name: oldRow.source.name, url: oldRow.source.url, observedAt: stamp(now),
                correctionConfirmedAt: stamp(now.addingTimeInterval(-300))))
        let candidate = snapshot([changed])
        XCTAssertEqual(try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(candidate), now: now), candidate)
        XCTAssertEqual(SportsFixtureCatalog.accepting(candidate, over: snapshot([oldRow], receipt: oldTime)).fixtures, [changed])
        let oldSaved = SavedMatchRecord(event: try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([oldRow], receipt: oldTime), at: now).first), savedAt: now)
        let current = SportsFixtureCatalog.merging(into: [], snapshot: candidate, at: now)
        XCTAssertNil(SavedMatchContinuityPolicy.currentEvent(for: oldSaved, in: current),
                     "A participant correction must not turn saved intent into another match")
    }

    func testParticipantLabelCorrectionPreservesStableSavedIdentity() throws {
        let oldTime = now.addingTimeInterval(-600)
        let oldRow = fixture(observedAt: oldTime)
        let renamed = SportsFixtureCatalog.Fixture(id: oldRow.id, sport: oldRow.sport, start: oldRow.start,
            status: oldRow.status, eventKind: oldRow.eventKind, title: "Boston vs New York Knicks",
            competitionId: oldRow.competitionId, competitionName: oldRow.competitionName,
            participants: [.init(id: oldRow.participants[0].id, name: "Boston"), oldRow.participants[1]], squad: oldRow.squad,
            source: .init(name: oldRow.source.name, url: oldRow.source.url, observedAt: stamp(now)))
        let accepted = SportsFixtureCatalog.accepting(snapshot([renamed]), over: snapshot([oldRow], receipt: oldTime))
        XCTAssertEqual(accepted.fixtures, [renamed])
        let oldEvent = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: snapshot([oldRow], receipt: oldTime), at: now).first)
        let current = SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: now)
        XCTAssertEqual(SavedMatchContinuityPolicy.currentEvent(for: SavedMatchRecord(event: oldEvent), in: current)?.homeName, "Boston")
    }

    func testCompetitionNameReceiptMismatchAndFutureCorrectionProofAreRejected() throws {
        let payload = try JSONEncoder().encode(snapshot([fixture()]))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        for mode in ["competitionName", "observedAt", "correctionConfirmedAt"] {
            var json = original
            var fixtures = try XCTUnwrap(json["fixtures"] as? [[String: Any]])
            if mode == "competitionName" { fixtures[0][mode] = "Another League" }
            else {
                var source = try XCTUnwrap(fixtures[0]["source"] as? [String: Any])
                source[mode] = stamp(now.addingTimeInterval(mode == "observedAt" ? -1 : 1))
                fixtures[0]["source"] = source
            }
            json["fixtures"] = fixtures
            XCTAssertThrowsError(try SportsFixtureCatalog.validatedSnapshot(from: JSONSerialization.data(withJSONObject: json), now: now))
        }
    }

    func testPlaybackFallbackRequiresCompetitionParticipantsSquadAndStart() throws {
        for candidate in [provider(competition: nil), provider(competition: "wnba"), provider(sport: "football"),
                          provider(hours: 2), provider(home: "Boston Celtics Women"),
                          provider(title: "NBA · Boston Celtics Under-19 vs New York Knicks Under-19")] {
            let rows = SportsFixtureCatalog.merging(into: [candidate], snapshot: snapshot([fixture()]), at: now)
            let scheduled = try XCTUnwrap(rows.first { $0.sportsFixture != nil })
            XCTAssertEqual(rows.count, 2)
            XCTAssertNil(CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: scheduled), in: [candidate]))
        }
    }

    func testReviewedNCAAFootballMatchesBareTitleAndExactNCAAPrefix() throws {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:college-football:123", sport: "american-football",
            competitionID: "college-football", competitionName: "NCAA Football", eventKind: .match,
            title: "Alabama Crimson Tide vs Georgia Bulldogs",
            participants: [.init(id: "alabama", name: "Alabama Crimson Tide", role: "home"),
                           .init(id: "georgia", name: "Georgia Bulldogs", role: "away")],
            squad: .init(gender: .men, ageGroup: "college"), status: .scheduled, observedAt: now, verified: true)
        let start = now.addingTimeInterval(3600)
        func candidate(title: String, competition: String = "college-football") -> EventReference {
            .init(id: "ncaa-provider", title: title, category: "american-football",
                date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "Alabama Crimson Tide", badge: nil),
                             away: .init(name: "Georgia Bulldogs", badge: nil)), competitionID: competition)
        }
        for title in [metadata.title, "NCAA Football · \(metadata.title)"] {
            XCTAssertTrue(SportsFixtureCatalog.providerMatches(candidate(title: title), fixture: metadata, kickoff: start))
        }
        for qualifier in ["Women", "Under-19", "U19", "Youth", "Reserves"] {
            XCTAssertFalse(SportsFixtureCatalog.providerMatches(candidate(title: "\(metadata.title) \(qualifier)"),
                fixture: metadata, kickoff: start))
        }
        XCTAssertFalse(SportsFixtureCatalog.providerMatches(candidate(title: metadata.title, competition: "nfl"),
            fixture: metadata, kickoff: start))
        XCTAssertFalse(SportsFixtureCatalog.providerMatches(candidate(title: "NFL · \(metadata.title)"),
            fixture: metadata, kickoff: start))
    }

    func testReviewedNCAAWomensBasketballUsesCompetitionCohortAndRejectsContradictions() {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:college-basketball-women:123", sport: "basketball",
            competitionID: "college-basketball-women", competitionName: "NCAA Division I Women's Basketball", eventKind: .match,
            title: "UConn Huskies vs South Carolina Gamecocks",
            participants: [.init(id: "uconn", name: "UConn Huskies", role: "home"),
                           .init(id: "south-carolina", name: "South Carolina Gamecocks", role: "away")],
            squad: .init(gender: .women, ageGroup: "college"), status: .scheduled, observedAt: now, verified: true)
        let start = now.addingTimeInterval(3600)
        func candidate(title: String, competition: String = "college-basketball-women") -> EventReference {
            .init(id: "ncaa-women-provider", title: title, category: "basketball",
                date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "UConn Huskies", badge: nil),
                             away: .init(name: "South Carolina Gamecocks", badge: nil)), competitionID: competition)
        }
        XCTAssertTrue(SportsFixtureCatalog.providerMatches(candidate(title: metadata.title), fixture: metadata, kickoff: start))
        for qualifier in ["Men", "Men's", "Under-19", "U19", "Youth", "Reserves"] {
            XCTAssertFalse(SportsFixtureCatalog.providerMatches(candidate(title: "\(metadata.title) \(qualifier)"),
                fixture: metadata, kickoff: start))
        }
        XCTAssertFalse(SportsFixtureCatalog.providerMatches(candidate(title: metadata.title, competition: "college-basketball-men"),
            fixture: metadata, kickoff: start))
        let unknownCohort = SportsFixtureMetadata(fixtureID: metadata.fixtureID, sport: metadata.sport,
            competitionID: metadata.competitionID, competitionName: metadata.competitionName, eventKind: metadata.eventKind,
            title: metadata.title, participants: metadata.participants, squad: .init(gender: .unknown, ageGroup: "unknown"),
            status: metadata.status, observedAt: metadata.observedAt, verified: metadata.verified)
        XCTAssertFalse(SportsFixtureCatalog.providerMatches(candidate(title: metadata.title), fixture: unknownCohort, kickoff: start))
    }

    func testSeniorFixturesRejectExplicitYouthAndCollegeCohorts() throws {
        let scheduled = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: snapshot([fixture()]), at: now).first)
        let metadata = try XCTUnwrap(scheduled.sportsFixture)
        for qualifier in ["Women", "Under-19", "U19", "Youth", "Reserves", "College"] {
            XCTAssertFalse(SportsFixtureCatalog.providerMatches(provider(title: "Boston Celtics vs New York Knicks \(qualifier)"),
                fixture: metadata, kickoff: scheduled.kickoffDate))
        }
    }

    func testNoStreamIsInventedFromScheduleOrUnrelatedBroadcast() throws {
        let row = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: snapshot([fixture(status: .live, hours: -1)]), at: now).first)
        XCTAssertTrue(row.sportsFixture?.isLive(at: now) == true)
        XCTAssertEqual(HomeSportsDiscovery(events: [row], now: now).items.first?.phase, .live)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now))
        XCTAssertFalse(MatchStartPolicy(event: row, now: now).canAttemptPlayback)
    }

    func testStaleLiveDoesNotAdvertiseLiveAndPostponedBlocksWatch() throws {
        let stale = fixture(status: .live, hours: -1, observedAt: now.addingTimeInterval(-1801))
        let row = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: snapshot([stale]), at: now).first)
        XCTAssertEqual(row.broadcastTiming(at: now), .available)
        XCTAssertEqual(HomeSportsDiscovery(events: [row], now: now).items.first?.phase, .unconfirmed)
        let postponed = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .postponed, hours: -1)]), at: now).first)
        XCTAssertFalse(MatchStartPolicy(event: postponed, now: now).canAttemptPlayback)
        XCTAssertEqual(MatchStartPolicy(event: postponed, now: now).title, "Postponed")
    }

    func testTypedSessionsTournamentsAndCardsRetainTitleWithoutAwayAcrossSave() throws {
        for kind in [SportsFixtureCatalog.EventKind.session, .tournament, .card] {
            let row = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
                snapshot: snapshot([fixture(sport: "motorsport", competition: "f1", kind: kind)]), at: now).first)
            XCTAssertEqual(row.displayTitle, "Singapore Grand Prix · Qualifying")
            XCTAssertEqual(row.homeName, row.displayTitle)
            XCTAssertEqual(row.awayName, "")
            XCTAssertFalse(HomeDiscoveryRow.showsTeamBadges(for: row))
            let saved = SavedMatchRecord(event: row, savedAt: now)
            let restored = try JSONDecoder().decode(SavedMatchRecord.self, from: JSONEncoder().encode(saved)).event
            XCTAssertEqual(restored.sportsFixture, row.sportsFixture)
            XCTAssertEqual(restored.displayTitle, row.displayTitle)
            XCTAssertEqual(restored.awayName, "")
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: restored, in: [restored], at: now))
        }
    }

    func testGenericCatalogLeavesDedicatedCricketAuthorityAlone() {
        let cricket = EventReference(id: "cricket-fixture:india-wi", title: "India vs West Indies", category: "cricket",
            date: Int64(now.timeIntervalSince1970), poster: nil, popular: false, teams: nil)
        let rows = SportsFixtureCatalog.merging(into: [cricket],
            snapshot: snapshot([fixture(sport: "cricket", competition: "icc")]), at: now)
        XCTAssertEqual(rows.map(\.id), [cricket.id])
    }

    func testSavedMLBAndNHLReceiveTerminalFactsFromTheSchedule() async throws {
        for (sport, competition, home, away) in [
            ("baseball", "mlb", "Seattle Mariners", "New York Yankees"),
            ("hockey", "nhl", "Edmonton Oilers", "Vancouver Canucks")
        ] {
            for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
                let suite = "Fotty.TerminalSportsJourney.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let store = MyMatchdayStore(defaults: defaults)
                var clock = now
                func official(_ status: SportsFixtureCatalog.Status) -> SportsFixtureCatalog.Fixture {
                    .init(id: "sports-fixture:\(competition):journey", sport: sport,
                        start: stamp(now.addingTimeInterval(-3600)), status: status, eventKind: .match,
                        title: "\(home) vs \(away)", competitionId: competition, competitionName: competition.uppercased(),
                        participants: [.init(id: "home", name: home), .init(id: "away", name: away)],
                        squad: .init(gender: .men, ageGroup: "senior"),
                        source: .init(name: "Official schedule", url: "https://example.com/fixtures", observedAt: stamp(clock)))
                }
                var receipt = snapshot([official(.live)], receipt: clock)
                let model = MatchListViewModel(refreshSports: { receipt }, now: { clock }, matchdayStore: store)
                await model.refresh()
                let live = try XCTUnwrap(model.matches.first)
                XCTAssertEqual(store.save(live), .saved)
                let savedAt = store.savedMatches.first?.savedAt
                XCTAssertEqual(MatchdayEventStatePolicy.section(for: live, at: clock), .live)

                clock = now.addingTimeInterval(60)
                receipt = snapshot([official(terminal)], receipt: clock)
                await model.refresh()
                XCTAssertTrue(model.matches.isEmpty, "Terminal facts must stay outside the playable catalog")
                let ended = try XCTUnwrap(store.savedMatches.first).event
                XCTAssertEqual(ended.sportsFixture?.status, terminal, "\(competition)")
                XCTAssertEqual(ended.sportsFixture?.observedAt, clock, "Saving must not rewrite the source receipt")
                XCTAssertEqual(store.savedMatches.first?.savedAt, savedAt)
                XCTAssertEqual(ended.teams?.home?.badge, live.teams?.home?.badge)
                XCTAssertEqual(ended.teams?.away?.badge, live.teams?.away?.badge)
                XCTAssertEqual(MatchdayEventStatePolicy.section(for: ended, at: clock), .recent)
                XCTAssertNil(CurrentEventBroadcastPolicy.action(for: ended, in: model.playbackCatalog, at: clock))
                XCTAssertEqual(MyMatchdayStore(defaults: defaults).savedMatches.first?.sportsFixture?.status, terminal)
            }
        }
    }

    func testMissingOrUnavailableSportsEvidenceDoesNotCancelASavedMatch() throws {
        let suite = "Fotty.MissingSportsSave.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MyMatchdayStore(defaults: defaults)
        let live = try XCTUnwrap(SportsFixtureCatalog.merging(into: [provider(hours: -1)],
            snapshot: snapshot([fixture(status: .live, hours: -1)]), at: now).first)
        XCTAssertEqual(store.save(live), .saved)
        let original = store.savedMatches
        let unavailable = snapshot([fixture(status: .finished, hours: -1)], status: .partial, unavailable: ["nba"])
        XCTAssertTrue(SportsFixtureCatalog.terminalEvents(from: unavailable).isEmpty)
        XCTAssertTrue(SportsFixtureCatalog.terminalEvents(from: snapshot([fixture(status: .finished)], status: .lastKnownGood)).isEmpty)
        store.reconcile(events: [], at: now.addingTimeInterval(60))
        XCTAssertEqual(store.savedMatches, original)
    }

    func testTerminalArtworkPreservesOnlyExactTeamIdentityAndExplicitNewBadgesWin() throws {
        let row = try XCTUnwrap(SportsFixtureCatalog.terminalEvents(from: snapshot([fixture(status: .finished, hours: -1)])).first)
        let old = SavedMatchRecord(id: row.id, title: row.title, category: row.category, date: row.date,
            poster: nil, popular: false, homeName: row.homeName, awayName: row.awayName,
            homeBadge: "old-home", awayBadge: "old-away", savedAt: now)
        let carried = SavedMatchRecord(event: row, savedAt: now, preservingArtworkFrom: old)
        XCTAssertEqual(carried.homeBadge, "old-home")
        XCTAssertEqual(carried.awayBadge, "old-away")
        let explicit = EventReference(id: row.id, title: row.title, category: row.category, date: row.date,
            poster: nil, popular: false,
            teams: .init(home: .init(name: row.homeName, badge: "new-home"), away: .init(name: row.awayName, badge: nil)), sportsFixture: row.sportsFixture, competitionID: row.competitionID)
        XCTAssertEqual(SavedMatchRecord(event: explicit, savedAt: now, preservingArtworkFrom: old).homeBadge, "new-home")
        let different = SavedMatchRecord(id: row.id, title: row.title, category: row.category, date: row.date,
            poster: nil, popular: false, homeName: "Different team", awayName: "Another team",
            homeBadge: "wrong-home", awayBadge: "wrong-away", savedAt: now)
        let rejected = SavedMatchRecord(event: row, savedAt: now, preservingArtworkFrom: different)
        XCTAssertNil(rejected.homeBadge)
        XCTAssertNil(rejected.awayBadge)
    }

    func testMatchdaySeparatesLiveFuturePostponedTerminalAndUnconfirmedStarts() throws {
        for (status, expected) in [
            (SportsFixtureCatalog.Status.live, MatchdayEventStatePolicy.Section.live),
            (.postponed, .timeToBeConfirmed), (.unknown, .awaitingConfirmation)
        ] {
            let row = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
                snapshot: snapshot([fixture(status: status, hours: -1)]), at: now).first)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: row, at: now), expected)
        }
        let future = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: snapshot([fixture()]), at: now).first)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: future, at: now), .upcoming)
        let stale = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .live, hours: -1, observedAt: now.addingTimeInterval(-1801))]), at: now).first)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: stale, at: now), .awaitingConfirmation)
        for status in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let ended = try XCTUnwrap(SportsFixtureCatalog.terminalEvents(from: snapshot([fixture(status: status, hours: -1)])).first)
            XCTAssertEqual(MatchdayEventStatePolicy.section(for: ended, at: now), .recent)
        }
        let noTime = EventReference(id: "unknown-time", title: "Boston Celtics vs New York Knicks", category: "basketball",
            date: nil, poster: nil, popular: false, teams: nil)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: noTime, at: now), .timeToBeConfirmed)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: provider(hours: -1), at: now), .awaitingConfirmation,
                       "Untyped provider timing is a broadcast listing, not verified live evidence")
    }

    func testVerifiedFootballTerminalFactsOutrankNonterminalScoreStatusWithoutChangingOtherCases() {
        func football(_ status: SportsFixtureCatalog.Status, verified: Bool = true) -> EventReference {
            let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:terminal", sport: "football",
                competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                title: "Bournemouth vs Liverpool",
                participants: [.init(id: "bournemouth", name: "Bournemouth", role: "home"),
                               .init(id: "liverpool", name: "Liverpool", role: "away")],
                squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: verified)
            return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
                date: Int64(now.addingTimeInterval(-2 * 3600).timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "Bournemouth", badge: nil), away: .init(name: "Liverpool", badge: nil)), sportsFixture: metadata, competitionID: metadata.competitionID)
        }
        for terminal in [SportsFixtureCatalog.Status.finished, .cancelled] {
            for score: FootballMatch.MatchStatus in [.inPlay, .paused, .scheduled, .timed, .postponed, .suspended] {
                // The real score freshness gate still admits an earlier in-play
                // value for up to ten minutes after this fixture receipt advances.
                let acceptedScore = HomeSportsDiscovery.recentStatus(score,
                    refreshedAt: now.addingTimeInterval(-60), liveFeedAvailable: true, now: now)
                XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(terminal), at: now, status: acceptedScore), .recent)
                let unverifiedSection: MatchdayEventStatePolicy.Section = score.isLive ? .live
                    : ((score == .postponed || score == .suspended) ? .timeToBeConfirmed : .awaitingConfirmation)
                XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(terminal, verified: false), at: now, status: acceptedScore),
                               unverifiedSection,
                               "Unverified terminal data must not acquire new precedence")
            }
        }
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(.live), at: now, status: .inPlay), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(.live), at: now), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(.scheduled), at: now, status: .inPlay), .live)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(.live), at: now, status: .scheduled), .awaitingConfirmation,
                       "This focused terminal fix does not rewrite nonterminal source ordering")
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: football(.postponed), at: now, status: .inPlay), .live)
    }

    func testLiveCardLabelsKeepVerifiedSportsFreshnessAndTerminalPrecedence() throws {
        let live = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .live, hours: -1)]), at: now).first)
        let confirmed = MatchdayEventStatePolicy.section(for: live, at: now)
        XCTAssertEqual(confirmed, .live)
        XCTAssertEqual(LiveEventCard.prominentStatusLabel(for: confirmed, broadcastAvailable: false), "IN PLAY")
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: live, in: [live], at: now),
                     "Confirmed in-play status must not invent a source")

        let stale = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .live, hours: -1, observedAt: now.addingTimeInterval(-1801))]), at: now).first)
        let unverified = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .live, hours: -1)], status: .lastKnownGood), at: now).first)
        for row in [stale, unverified] {
            let section = MatchdayEventStatePolicy.section(for: row, at: now)
            XCTAssertEqual(section, .awaitingConfirmation)
            XCTAssertNil(LiveEventCard.prominentStatusLabel(for: section, broadcastAvailable: true))
        }
        for status in [SportsFixtureCatalog.Status.finished, .cancelled] {
            let terminal = try XCTUnwrap(SportsFixtureCatalog.terminalEvents(from: snapshot([fixture(status: status, hours: -1)])).first)
            let section = MatchdayEventStatePolicy.section(for: terminal, at: now, status: .inPlay)
            XCTAssertEqual(section, .recent)
            XCTAssertNil(LiveEventCard.prominentStatusLabel(for: section, broadcastAvailable: true))
        }
    }

    func testSourceExpiryRetainsTerminalMetadataAndSameCountMutationsAdvanceSavedRevision() throws {
        let suite = "Fotty.SavedRevision.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MyMatchdayStore(defaults: defaults)
        let live = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .live, hours: -1)]), at: now).first)
        store.save(live)
        let before = store.contentRevision
        let ended = try XCTUnwrap(SportsFixtureCatalog.terminalEvents(from: snapshot([fixture(status: .finished, hours: -1)])).first)
        store.reconcile(events: [ended], at: now)
        XCTAssertGreaterThan(store.contentRevision, before, "Same ID/date/source-count changes must invalidate Matchday")
        XCTAssertEqual(store.savedMatches.first?.sportsFixture?.status, .finished)

        let expired = MyMatchdayStore(defaults: defaults)
        expired.reconcile(events: [], at: now.addingTimeInterval(40 * 3600))
        let row = try XCTUnwrap(expired.savedMatches.first).event
        XCTAssertEqual(row.sportsFixture?.status, .finished)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: row, at: now.addingTimeInterval(40 * 3600)), .recent)

        let postponed = try XCTUnwrap(SportsFixtureCatalog.merging(into: [],
            snapshot: snapshot([fixture(status: .postponed, hours: -40)]), at: now).first)
        expired.save(postponed)
        expired.reconcile(events: [], at: now)
        XCTAssertEqual(expired.savedMatches.first?.sportsFixture?.status, .postponed)
        XCTAssertEqual(MatchdayEventStatePolicy.section(for: try XCTUnwrap(expired.savedMatches.first).event, at: now), .timeToBeConfirmed)
    }

    func testHomeDedupDoesNotUndoExactCompetitionBoundary() {
        let nba = provider("nba", competition: "nba")
        let cup = provider("cup", competition: "nba-cup")
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([nba, cup]).count, 2)
        XCTAssertEqual(AnalyticalDataEngine.deduplicateMatches([nba, cup]).count, 2)
        XCTAssertEqual(AnalyticalDataEngine.normalizedCategoryKey("NFL"), "american-football")
        XCTAssertEqual(AnalyticalDataEngine.normalizedCategoryKey("F1"), "motorsport")
        XCTAssertEqual(AnalyticalDataEngine.normalizedCategoryKey("WTA"), "tennis")
    }

    func testScheduleRefreshReplacesOldProviderRowWithoutBorrowingSources() async {
        let model = MatchListViewModel(refreshSports: { self.snapshot([self.fixture()]) }, now: { self.now })
        model.matches = [provider()]
        await model.refresh()
        XCTAssertEqual(model.matches.count, 1)
    }

    func testHTTP503PreservesReceiptAcrossRelaunchAndRetriesAfterFiveMinutes() async throws {
        let suite = "Fotty.SportsFixtures.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let valid = snapshot([fixture(hours: 30)])
        let payload = try JSONEncoder().encode(valid)
        var status = 200
        var requests = 0
        let updater = SportsFixtureUpdater(defaults: defaults) { request in
            requests += 1
            return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let initial = await updater.refresh(now: now)
        XCTAssertEqual(initial, valid)
        status = 503
        let failedAt = now.addingTimeInterval(1)
        let failed = await updater.refresh(now: failedAt, force: true)
        XCTAssertEqual(failed, valid)
        XCTAssertEqual(SportsFixtureUpdater(defaults: defaults).cachedSnapshot(now: now), valid)
        _ = await updater.refresh(now: failedAt.addingTimeInterval(299))
        XCTAssertEqual(requests, 2)
        _ = await updater.refresh(now: failedAt.addingTimeInterval(300))
        XCTAssertEqual(requests, 3)
    }
}

@MainActor
final class StartingFixturePresentationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-01T19:54:00Z")!
    private let kickoff = ISO8601DateFormatter().date(from: "2026-11-01T19:45:00Z")!
    private let oldPublisherUpdate = ISO8601DateFormatter().date(from: "2026-11-01T01:32:01Z")!

    private func event(status: SportsFixtureCatalog.Status = .scheduled, verified: Bool = true,
                       identity: Date? = nil, publisherUpdate: Date? = nil, start: Date? = nil,
                       conflict: Bool = false) -> EventReference {
        let id = "sports-fixture:serie-a:558547"
        let metadata = SportsFixtureMetadata(fixtureID: id, sport: "football", competitionID: "serie-a",
            competitionName: "Serie A", eventKind: .match, title: "Juventus FC vs SSC Napoli",
            participants: [.init(id: "football-data:109", name: "Juventus FC", role: "home"),
                           .init(id: "football-data:113", name: "SSC Napoli", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status,
            observedAt: publisherUpdate ?? oldPublisherUpdate, verified: verified,
            identityObservedAt: identity ?? now.addingTimeInterval(-240))
        return .init(id: id, title: metadata.title, category: "football",
            date: Int64((start ?? kickoff).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Juventus FC", badge: nil), away: .init(name: "SSC Napoli", badge: nil)), hasCatalogIdentityConflict: conflict, sportsFixture: metadata, competitionID: "serie-a")
    }

    func testFreshScheduleWithOldPublisherUpdateRemainsStartingOnHomeWithoutInferringLive() throws {
        func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
        let receipt = now.addingTimeInterval(-240), identity = event()
        let row = SportsFixtureCatalog.Fixture(id: identity.id, sport: "football", start: stamp(kickoff),
            status: .scheduled, eventKind: .match, title: identity.displayTitle,
            competitionId: "serie-a", competitionName: "Serie A", participants: identity.sportsFixture!.participants,
            squad: identity.sportsFixture!.squad, source: .init(name: "football-data.org",
                url: "https://api.football-data.org/v4/matches", observedAt: stamp(receipt), updatedAt: stamp(oldPublisherUpdate)))
        let snapshot = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: stamp(receipt),
            revision: "starting-fixture", sourceStatus: .verified, fixtures: [row],
            coverage: [.init(sport: "football", competitionId: "serie-a", competitionName: "Serie A",
                status: .covered, checkedAt: stamp(receipt), fixtureCount: 1, pendingFixtureCount: 0, nextStart: row.start)])
        let validated = try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(snapshot), now: now)
        let projected = try XCTUnwrap(SportsFixtureCatalog.merging(into: [], snapshot: validated, at: now).first)
        XCTAssertEqual(projected.sportsFixture?.identityReceipt, receipt)
        XCTAssertEqual(projected.sportsFixture?.observedAt, oldPublisherUpdate)
        let home = HomeSportsDiscovery(events: [projected], now: now)
        let item = try XCTUnwrap(home.items.first)
        XCTAssertEqual(item.phase, .upcoming)
        XCTAssertTrue(item.isStarting)
        XCTAssertEqual(item.statusLabel, "Starting")
        XCTAssertEqual(item.prominentStatusLabel, "Starting")
        XCTAssertFalse(item.isOnNow)
        XCTAssertFalse(item.hasConfirmedLiveStatus)
        XCTAssertEqual(HomeDiscoveryRow.Presentation(item: item).statusLabel, "Starting")
        let sections = home.homeSections(from: home.items, diverseUpcoming: false, featuredLiveLimit: 3)
        XCTAssertEqual(sections.upcoming.map(\.id), [projected.id])
        XCTAssertTrue(sections.featuredLive.isEmpty)
        let football = try XCTUnwrap(home.activities.first { $0.id == "football" })
        XCTAssertEqual(football.confirmedLive, 0)
        XCTAssertEqual(football.onNow, 0)
        XCTAssertEqual(football.summary(at: now), "Starting")
        XCTAssertNil(football.nextStart, "The sport tile must not display an elapsed kickoff as its next match")
    }

    func testStartingLookupUsesFreshScheduledIdentityWithoutInventingAPlayableSource() throws {
        let row = event()
        let admitted = try XCTUnwrap(OptionalSourceLookupPolicy.event(for: row, in: [row],
            enabledProviderCodes: ["communitysports"], at: now))
        XCTAssertEqual(admitted.sportsFixture?.status, .scheduled)
        XCTAssertFalse(admitted.sportsFixture?.isLive(at: now) ?? true)
        let index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        let action = CurrentEventBroadcastPolicy.action(for: row, in: [row], at: now,
            discoveryIndex: index, catalogIndex: FixtureCatalogAvailabilityIndex())
        XCTAssertEqual(action?.evidence, .freshLookupOpportunity,
            "A started fixture offers a fresh lookup Watch, never a confirmed playable broadcast")
        XCTAssertFalse(action?.event.sportsFixture?.isLive(at: now) ?? true)
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row], enabledProviderCodes: [], at: now))
        let beforeKickoff = event(start: now.addingTimeInterval(60))
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: beforeKickoff, in: [beforeKickoff],
            enabledProviderCodes: ["communitysports"], at: now))
        let tooEarly = event(start: now.addingTimeInterval(MatchStartPolicy.playbackLead + 1))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: tooEarly, in: [tooEarly],
            enabledProviderCodes: ["communitysports"], at: now))
    }

    func testStartingVisibilityAndLookupExpireAndRespectHeldConflictAndTerminalFacts() throws {
        let invalid = [
            event(verified: false), event(conflict: true),
            event(identity: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness - 1), publisherUpdate: now),
            event(identity: now.addingTimeInterval(301), publisherUpdate: now),
            event(start: now.addingTimeInterval(-VerifiedFixtureStartingPolicy.grace))
        ] + [SportsFixtureCatalog.Status.finished, .cancelled, .postponed, .unknown].map { event(status: $0) }
        for row in invalid {
            XCTAssertFalse(VerifiedFixtureStartingPolicy.contains(row, at: now))
            let home = HomeSportsDiscovery(events: [row], now: now)
            XCTAssertTrue(home.featured(from: home.items, diverse: false).isEmpty)
            XCTAssertNil(OptionalSourceLookupPolicy.event(for: row, in: [row],
                enabledProviderCodes: ["communitysports"], at: now))
        }
        let starting = event(), finished = event(status: .finished, publisherUpdate: now)
        XCTAssertTrue(HomeSportsDiscovery(events: [starting], now: now, terminalEvents: [finished]).items.isEmpty)
        let boundary = event(identity: now.addingTimeInterval(-SportsFixtureCatalog.statusFreshness),
            start: now.addingTimeInterval(-VerifiedFixtureStartingPolicy.grace + 1))
        XCTAssertTrue(VerifiedFixtureStartingPolicy.contains(boundary, at: now))
    }

    func testFreshIdentityDoesNotRefreshLiveStatusOrOverrideCurrentTerminalEvidence() throws {
        let staleLive = event(status: .live)
        XCTAssertFalse(staleLive.sportsFixture?.isLive(at: now) ?? true)
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: staleLive, in: [staleLive],
            enabledProviderCodes: ["communitysports"], at: now))
        XCTAssertEqual(HomeSportsDiscovery(events: [staleLive], now: now).items.first?.phase, .unconfirmed)
        let freshLive = event(status: .live, publisherUpdate: now)
        XCTAssertTrue(freshLive.sportsFixture?.isLive(at: now) ?? false)
        XCTAssertEqual(HomeSportsDiscovery(events: [freshLive], now: now).items.first?.phase, .live)
        let starting = try XCTUnwrap(HomeSportsDiscovery(events: [event()], now: now).items.first)
        let future = try XCTUnwrap(HomeSportsDiscovery(events: [event(start: now.addingTimeInterval(600))], now: now).items.first)
        XCTAssertLessThan(CricketActivityPresentationPolicy.homePhaseRank(for: starting),
                          CricketActivityPresentationPolicy.homePhaseRank(for: future))
    }
}
