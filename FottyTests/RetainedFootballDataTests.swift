import XCTest
@testable import Fotty

/// Public football payloads and saved-data compatibility remain supported after
/// the fantasy workspace and its planning engines leave the app target.
final class RetainedFootballDataTests: XCTestCase {
    func testSeasonIdentifierRollsAtTheJulyBoundary() throws {
        let formatter = ISO8601DateFormatter()
        let june = try XCTUnwrap(formatter.date(from: "2027-06-30T23:59:59Z"))
        let july = try XCTUnwrap(formatter.date(from: "2027-07-01T00:00:00Z"))
        XCTAssertEqual(FPLSeasonIdentifier.currentLabel(at: june), "2026-27")
        XCTAssertEqual(FPLSeasonIdentifier.currentLabel(at: july), "2027-28")
    }

    func testDiskSnapshotPolicyRejectsExpiredLiveAndWrongSeasonData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let liveEndpoint = "event/2/live/"
        let fresh = FPLDiskSnapshotEnvelope(
            version: FPLDiskSnapshotEnvelope.currentVersion,
            endpoint: liveEndpoint,
            savedAt: now.addingTimeInterval(-299),
            season: "2026-27",
            catalogFingerprint: "clubs-v1",
            payload: Data()
        )
        XCTAssertTrue(FPLDiskSnapshotPolicy.isUsable(
            fresh,
            endpoint: liveEndpoint,
            expectedSeason: "2026-27",
            expectedCatalogFingerprint: "clubs-v1",
            now: now
        ))

        let expired = FPLDiskSnapshotEnvelope(
            version: FPLDiskSnapshotEnvelope.currentVersion,
            endpoint: liveEndpoint,
            savedAt: now.addingTimeInterval(-301),
            season: "2026-27",
            catalogFingerprint: "clubs-v1",
            payload: Data()
        )
        XCTAssertFalse(FPLDiskSnapshotPolicy.isUsable(
            expired,
            endpoint: liveEndpoint,
            expectedSeason: "2026-27",
            expectedCatalogFingerprint: "clubs-v1",
            now: now
        ))
        XCTAssertFalse(FPLDiskSnapshotPolicy.isUsable(
            fresh,
            endpoint: liveEndpoint,
            expectedSeason: "2027-28",
            expectedCatalogFingerprint: "clubs-v1",
            now: now
        ))
        XCTAssertFalse(FPLDiskSnapshotPolicy.isUsable(
            fresh,
            endpoint: liveEndpoint,
            expectedSeason: "2026-27",
            expectedCatalogFingerprint: "clubs-v2",
            now: now
        ))
    }

    func testCurrentLeagueStandingsContractDecodesPlayerNameAndPaging() throws {
        let json = #"""
        {
          "league": {
            "id": 218027,
            "name": "Test Mini-League",
            "created": "2026-07-25T01:45:08.370030Z",
            "league_type": "x"
          },
          "standings": {
            "has_next": true,
            "page": 1,
            "results": [
              {
                "entry": 3253567,
                "entry_name": "Intekma",
                "event_total": 95,
                "last_rank": 0,
                "player_name": "Test Manager",
                "rank": 1,
                "rank_sort": 1,
                "total": 95,
                "club_badge_src": null
              }
            ]
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(FPLLeagueStandingsResponse.self, from: json)

        XCTAssertEqual(response.league.leagueType, "x")
        XCTAssertTrue(response.standings.hasNext)
        XCTAssertEqual(response.standings.page, 1)
        XCTAssertEqual(response.standings.results.first?.id, 3_253_567)
        XCTAssertEqual(response.standings.results.first?.managerName, "Test Manager")
    }

    func testLeagueSummaryIdentifiesPrivateMiniLeague() throws {
        let json = #"""
        {
          "id": 218027,
          "name": "Test Mini-League",
          "league_type": "x",
          "entry_rank": 4,
          "entry_last_rank": 6
        }
        """#.data(using: .utf8)!

        let league = try JSONDecoder().decode(FPLLeagueSummary.self, from: json)

        XCTAssertTrue(league.isPrivateMiniLeague)
        XCTAssertEqual(league.entryRank, 4)
    }

    func testPickDecodesSellingAndPurchasePrices() throws {
        let json = #"""
        {
          "element": 101,
          "position": 1,
          "multiplier": 2,
          "is_captain": true,
          "is_vice_captain": false,
          "purchase_price": 75,
          "selling_price": 77
        }
        """#.data(using: .utf8)!

        let pick = try JSONDecoder().decode(FPLPick.self, from: json)

        XCTAssertEqual(pick.purchasePrice, 75)
        XCTAssertEqual(pick.sellingPrice, 77)
    }

    func testCurrentBootstrapRulesAndProjectionFieldsDecode() throws {
        let bootstrap = try decodeBootstrap()

        XCTAssertEqual(bootstrap.gameSettings?.squadSize, 15)
        XCTAssertEqual(bootstrap.gameSettings?.maximumFreeTransfers, 5)
        XCTAssertEqual(bootstrap.chips?.first?.startEvent, 2)
        XCTAssertEqual(bootstrap.elements.first?.officialExpectedPointsNext, 5.4)
        XCTAssertEqual(bootstrap.elements.first?.priceChangeProjections?.first?.likelihood, 3)
    }

    func testOfficialEventLiveContractDecodesPlayedBonusAndDefensiveContribution() throws {
        let json = #"""
        {
          "elements": [{
            "id": 101,
            "stats": {
              "minutes": 90, "goals_scored": 1, "assists": 0,
              "clean_sheets": 1, "goals_conceded": 0,
              "yellow_cards": 0, "red_cards": 0, "saves": 0,
              "bonus": 3, "bps": 41, "defensive_contribution": 11,
              "total_points": 12, "played": true
            },
            "explain": [{"fixture": 1, "stats": [{"identifier": "minutes", "points": 2, "value": 90}]}],
            "modified": false
          }]
        }
        """#.data(using: .utf8)!

        let live = try JSONDecoder().decode(FPLEventLiveResponse.self, from: json)

        XCTAssertEqual(live.elements.first?.stats.totalPoints, 12)
        XCTAssertEqual(live.elements.first?.stats.bonus, 3)
        XCTAssertEqual(live.elements.first?.stats.defensiveContribution, 11)
        XCTAssertEqual(live.elements.first?.stats.played, true)
    }

    func testHalftimeAndSuspensionResumptionNeverAnnounceAnotherKickoff() {
        XCTAssertTrue(FootballMatchAlertTransitionPolicy.shouldAnnounceKickoff(from: .scheduled, to: .inPlay))
        XCTAssertTrue(FootballMatchAlertTransitionPolicy.shouldAnnounceKickoff(from: .timed, to: .inPlay))
        for prior: FootballMatch.MatchStatus in [.paused, .suspended, .inPlay, .finished, .postponed, .cancelled, .awarded] {
            XCTAssertFalse(
                FootballMatchAlertTransitionPolicy.shouldAnnounceKickoff(from: prior, to: .inPlay),
                "Unexpected kickoff from \(prior)"
            )
        }
    }

    @MainActor
    func testDecisionJournalPersistsUpdatesAndIsolatesManagers() throws {
        let suiteName = "FottyTests.RetainedDecisionJournal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = FPLDecisionJournalEntry(
            id: "captain-gw1",
            managerID: 42,
            gameweek: 1,
            kind: .captain,
            title: "Captain P13",
            rationale: "Best modeled route to points.",
            expectedOutcome: "Outscore the vice-captain.",
            source: "Smart Coach",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            FPLDecisionJournalStore.upsert(initial, managerID: 42, defaults: defaults),
            [initial]
        )
        XCTAssertTrue(FPLDecisionJournalStore.load(managerID: 7, defaults: defaults).isEmpty)

        var reviewed = initial
        reviewed.outcome = .worked
        reviewed.outcomeNote = "The reasoning held even though the margin was small."
        reviewed.updatedAt = Date(timeIntervalSince1970: 200)
        let loaded = FPLDecisionJournalStore.upsert(reviewed, managerID: 42, defaults: defaults)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.outcome, .worked)
        XCTAssertEqual(loaded.first?.outcomeNote, reviewed.outcomeNote)
        XCTAssertTrue(FPLDecisionJournalStore.remove(id: reviewed.id, managerID: 42, defaults: defaults).isEmpty)
    }

    @MainActor
    func testPlanningScenariosPersistByManagerAndRemainBounded() throws {
        let suiteName = "FottyTests.RetainedPlanningScenarios.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for index in 0..<14 {
            let scenario = FPLSavedScenario(
                id: "scenario-\(index)",
                managerID: 42,
                gameweek: 2,
                name: "Plan \(index)",
                routeName: "Roll",
                transfers: [],
                hitCost: 0,
                projectedGain: 0,
                weeklyProjectedGain: [2: 0, 3: 0],
                breakEvenGameweek: nil,
                modelVersion: "legacy-model-1",
                downside: "A price may move.",
                verificationItems: ["Verify free transfers."],
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            _ = FPLScenarioStore.upsert(scenario, defaults: defaults)
        }

        let saved = FPLScenarioStore.load(managerID: 42, defaults: defaults)
        XCTAssertEqual(saved.count, 12)
        XCTAssertEqual(saved.map(\.id), (2..<14).reversed().map { "scenario-\($0)" })
        XCTAssertEqual(saved.first?.name, "Plan 13")
        XCTAssertEqual(saved.first?.weeklyProjectedGain, [2: 0, 3: 0])
        XCTAssertEqual(saved.first?.modelVersion, "legacy-model-1")
        XCTAssertTrue(FPLScenarioStore.load(managerID: 7, defaults: defaults).isEmpty)
        XCTAssertEqual(FPLScenarioStore.remove(id: "scenario-13", managerID: 42, defaults: defaults).count, 11)
        XCTAssertEqual(FPLScenarioStore.load(managerID: 42, defaults: defaults).first?.id, "scenario-12")
    }

    private func decodeBootstrap() throws -> FPLBootstrapResponse {
        let positions = [1, 1] + Array(repeating: 2, count: 5) + Array(repeating: 3, count: 5) + Array(repeating: 4, count: 3)
        var players = [[String: Any]]()
        for (offset, position) in positions.enumerated() {
            let id = offset + 1
            var player: [String: Any] = [
                "id": id, "web_name": "P\(id)", "first_name": "Player", "second_name": "\(id)",
                "team": (offset % 5) + 1, "team_code": (offset % 5) + 1, "element_type": position,
                "now_cost": 50, "cost_change_event": 0, "cost_change_event_fall": 0,
                "selected_by_percent": "10.0", "form": "4.0", "points_per_game": "4.0",
                "total_points": 10, "event_points": 0, "minutes": 180, "goals_scored": 0,
                "assists": 0, "clean_sheets": 0, "goals_conceded": 0, "yellow_cards": 0,
                "red_cards": 0, "saves": 0, "bonus": 0, "bps": 0, "influence": "0.0",
                "creativity": "0.0", "threat": "0.0", "ict_index": "0.0", "starts": 2,
                "transfers_in_event": 0, "transfers_out_event": 0, "status": "a", "news": "",
                "can_select": true
            ]
            if id == 1 {
                player["ep_next"] = "5.4"
                player["price_change_projections"] = [["offset": 0, "projected_percent": "78.2", "likelihood": 3]]
            }
            players.append(player)
        }
        let teams: [[String: Any]] = (1...5).map {
            ["id": $0, "name": "Team \($0)", "short_name": "T\($0)", "code": $0]
        }
        let types: [[String: Any]] = [
            ["id": 1, "singular_name": "Goalkeeper", "singular_name_short": "GKP", "plural_name": "Goalkeepers", "plural_name_short": "GKP", "squad_select": 2, "squad_min_play": 1, "squad_max_play": 1],
            ["id": 2, "singular_name": "Defender", "singular_name_short": "DEF", "plural_name": "Defenders", "plural_name_short": "DEF", "squad_select": 5, "squad_min_play": 3, "squad_max_play": 5],
            ["id": 3, "singular_name": "Midfielder", "singular_name_short": "MID", "plural_name": "Midfielders", "plural_name_short": "MID", "squad_select": 5, "squad_min_play": 2, "squad_max_play": 5],
            ["id": 4, "singular_name": "Forward", "singular_name_short": "FWD", "plural_name": "Forwards", "plural_name_short": "FWD", "squad_select": 3, "squad_min_play": 1, "squad_max_play": 3]
        ]
        let root: [String: Any] = [
            "events": (1...2).map { week -> [String: Any] in
                let deadline = "2026-08-\(week == 1 ? "21" : "28")T17:30:00Z"
                return ["id": week, "name": "Gameweek \(week)",
                 "deadline_time": deadline,
                 "deadline_time_epoch": Int(ISO8601DateFormatter().date(from: deadline)!.timeIntervalSince1970),
                 "finished": false, "data_checked": false, "is_previous": false,
                 "is_current": week == 1, "is_next": week == 2]
            }, "elements": players, "teams": teams, "element_types": types, "total_players": 15,
            "game_settings": ["squad_squadplay": 11, "squad_squadsize": 15, "squad_team_limit": 3, "squad_total_spend": 1000, "max_extra_free_transfers": 4],
            "chips": [["id": 1, "name": "wildcard", "number": 1, "start_event": 2, "stop_event": 19, "chip_type": "transfer"]]
        ]
        return try JSONDecoder().decode(FPLBootstrapResponse.self, from: JSONSerialization.data(withJSONObject: root))
    }
}
