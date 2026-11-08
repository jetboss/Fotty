import XCTest
@testable import Fotty

final class StreamVixSportsAddonTests: XCTestCase {
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-10-24T15:00:00Z")!
    private let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T16:30:00Z")!
    private let fixtureID = "tv:16-30-chelsea-vs-tottenham-hotspur-premier-league-24-10-20261024"
    private let pair = "Chelsea vs Tottenham Hotspur"
    private let header = "Saturday 24th October 2026 - Schedule Time UK GMT"
    private let delivery = "https://p7.streamhostingcdn.top/stream/870/index.m3u8?token=synthetic-signature&exp=1792864800"
    private let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"

    func testUnrelatedScheduleCategoryGrowthCannotDiscardReviewedFootball() throws {
        var groups: [String: Any] = ["All Soccer Events ⚽": [rawRow()]]
        for index in 0..<72 { groups["Unrelated category \(index)"] = [] }
        let rows = try StreamVixSportsAddonClient.originalFixtures(data: data([header: groups]))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kickoff, kickoff)
        XCTAssertEqual(rows.first?.competition, "England - Premier League")
        groups["All Soccer Events ⚽"] = "malformed"
        XCTAssertThrowsError(try StreamVixSportsAddonClient.originalFixtures(data: data([header: groups])))
        groups["All Soccer Events ⚽"] = Array(repeating: rawRow(), count: 601)
        XCTAssertThrowsError(try StreamVixSportsAddonClient.originalFixtures(data: data([header: groups])))
        groups["All Soccer Events ⚽"] = [rawRow()]
        groups["Unrelated large data"] = String(repeating: "x", count: 1_024 * 1_024)
        XCTAssertThrowsError(try StreamVixSportsAddonClient.originalFixtures(data: data([header: groups])))
    }

    func testNamedSimulcastProgrammeDoesNotInvalidateRealFixtures() throws {
        let rows = try StreamVixSportsAddonClient.originalFixtures(data: data(rawSchedule(rows: [
            rawRow(["event": "⚽ England - Premier League : Simulcast " + england]), rawRow()
        ])))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kickoff, kickoff)
        XCTAssertThrowsError(try StreamVixSportsAddonClient.originalFixtures(data: data(rawSchedule(rows: [
            rawRow(["event": "⚽ England - Premier League : Unresolved team"]), rawRow()
        ]))))
    }

    func testManifestRequiresFixedIdentityNamedResourcesAndBothReviewedGenres() throws {
        let manifest = try StreamVixSportsAddonClient.validateManifest(data: data(manifestJSON()))
        XCTAssertEqual(manifest.id, "org.prisonmike.streamvix")
        XCTAssertEqual(StreamVixSportsAddonClient.catalogID, "streamvix_eventi")
        XCTAssertEqual(StreamVixSportsAddonClient.manifestURL.absoluteString, "https://streamvix.hayd.uk/manifest.json")
        for mutation: [String: Any] in [
            ["id": "another.addon"], ["version": "https://private.invalid/value"], ["types": ["movie"]],
            ["resources": ["catalog", "stream"]], ["behaviorHints": ["configurationRequired": true]],
            ["catalogs": []],
            ["catalogs": [["id": "streamvix_eventi", "type": "tv", "extra": [["name": "genre", "isRequired": false,
                "options": ["Premier League", "Coppe"]]]]]],
            ["catalogs": [["id": "streamvix_eventi", "type": "tv", "extra": [["name": "genre", "isRequired": true,
                "options": ["Premier League"]]]]]]
        ] {
            XCTAssertThrowsError(try StreamVixSportsAddonClient.validateManifest(
                data: data(manifestJSON().merging(mutation, uniquingKeysWith: { _, new in new }))))
        }
    }

    func testBatchSharesOriginalAndOneCatalogPerReviewedLeagueWithoutMetaOrStreams() async throws {
        let secondPair = "Arsenal vs Everton", clPair = "Real Madrid vs Borussia Dortmund"
        let derived = utc("2026-10-24T14:30:00Z")
        let secondID = StreamVixSportsAddonClient.advertisedID(sourceTitle: "⏰ 16:30 : \(secondPair) - Premier League 24/10", derived: derived)
        let clID = StreamVixSportsAddonClient.advertisedID(sourceTitle: "⏰ 16:30 : \(clPair) - UEFA Champions League 24/10", derived: derived)
        let session = try fixtureSession(originals: .json(rawSchedule(rows: [rawRow(),
            rawRow(["event": "⚽ England - Premier League : " + secondPair]),
            rawRow(["event": "⚽ UEFA Champions League : " + clPair])])),
            catalog: .json(["metas": [entryJSON(), entryJSON(pair: secondPair, id: secondID)]]))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let clPath = "/catalog/tv/streamvix_eventi/genre=Coppe.json"
        StreamVixFixtureProtocol.setResponse(try .json(["metas": [entryJSON(pair: clPair, id: clID,
            category: "coppe", league: "UEFA Champions League")]]), for: clPath)
        let second = StreamPlaybackRequest(matchID: "second-pl", displayTitle: secondPair,
            homeTeam: "Arsenal", awayTeam: "Everton", category: "football", kickoffDate: kickoff)
        let cl = StreamPlaybackRequest(matchID: "ucl-fixture", displayTitle: clPair,
            homeTeam: "Real Madrid", awayTeam: "Borussia Dortmund", category: "football", kickoffDate: kickoff)
        let requests = [request(), second, cl, request(category: "cricket")]
        let client = StreamVixSportsAddonClient(session: session)
        let rows = try await client.catalogMatches(for: requests, now: fixedNow)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed, .listed, .unsupported])
        XCTAssertEqual(rows.prefix(3).map(\.providerEventID), [fixtureID, secondID, clID])
        XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath, clPath, catalogPath])
        _ = try await client.catalogMatches(for: requests, now: fixedNow.addingTimeInterval(1))
        XCTAssertEqual(StreamVixFixtureProtocol.paths.count, 4, "No per-match meta/stream reads while browsing")
    }

    func testBatchFailedReviewedLeagueCannotEraseOtherHealthyLeague() async throws {
        let clPair = "Real Madrid vs Borussia Dortmund"
        let clID = StreamVixSportsAddonClient.advertisedID(sourceTitle: "⏰ 16:30 : \(clPair) - UEFA Champions League 24/10",
            derived: utc("2026-10-24T14:30:00Z"))
        let clPath = "/catalog/tv/streamvix_eventi/genre=Coppe.json"
        let clRequest = StreamPlaybackRequest(matchID: "ucl-fixture", displayTitle: clPair, homeTeam: "Real Madrid",
            awayTeam: "Borussia Dortmund", category: "football", kickoffDate: kickoff)
        for failedPath in [clPath, catalogPath] {
            let session = try fixtureSession(originals: .json(rawSchedule(rows: [rawRow(),
                rawRow(["event": "⚽ UEFA Champions League : " + clPair])])) )
            defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
            StreamVixFixtureProtocol.setResponse(try .json(["metas": [entryJSON(pair: clPair, id: clID,
                category: "coppe", league: "UEFA Champions League")]]), for: clPath)
            StreamVixFixtureProtocol.setResponse(.status(503), for: failedPath)
            let rows = try await StreamVixSportsAddonClient(session: session).catalogMatches(for: [request(), clRequest], now: fixedNow)
            XCTAssertEqual(rows.map(\.outcome), failedPath == clPath
                ? [.listed, .failed(.manifestUnreachable)] : [.failed(.manifestUnreachable), .listed])
            XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath, clPath, catalogPath])
            XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
        }
    }

    func testBatchInvalidLeagueSchemaStaysTypedWithoutDiscardingHealthyLeague() async throws {
        let clPair = "Real Madrid vs Borussia Dortmund", clPath = "/catalog/tv/streamvix_eventi/genre=Coppe.json"
        let session = try fixtureSession(originals: .json(rawSchedule(rows: [rawRow(),
            rawRow(["event": "⚽ UEFA Champions League : " + clPair])])) )
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        StreamVixFixtureProtocol.setResponse(.body(Data("invalid JSON".utf8)), for: clPath)
        let cl = StreamPlaybackRequest(matchID: "ucl-fixture", displayTitle: clPair, homeTeam: "Real Madrid",
            awayTeam: "Borussia Dortmund", category: "football", kickoffDate: kickoff)
        let rows = try await StreamVixSportsAddonClient(session: session).catalogMatches(for: [request(), cl], now: fixedNow)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .failed(.manifestInvalid)])
        XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(where: { $0.contains("/meta/") || $0.contains("/stream/") }))
    }

    func testBatchCatalogConflictCannotBeHiddenByOriginalScheduleMatch() async throws {
        var malformed = entryJSON(); malformed["eventStart"] = NSNull()
        let session = try fixtureSession(catalog: .json(["metas": [entryJSON(), malformed]]))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let rows = try await StreamVixSportsAddonClient(session: session).catalogMatches(for: [request()], now: fixedNow)
        XCTAssertEqual(rows.map(\.outcome), [.conflicting])
        XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath, catalogPath])
    }

    func testCancelledOriginalBatchCannotPublishOrContinueToCatalog() async throws {
        let gate = StreamVixFixtureGate("batch original")
        let session = try fixtureSession(originals: .controlled(gate))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session), requests = [request()]
        let operation = Task { try await client.catalogMatches(for: requests, now: self.fixedNow) }
        defer { operation.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        operation.cancel(); gate.respond(try .json(rawSchedule()))
        do { _ = try await operation.value; XCTFail("Cancelled batch cannot publish") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath])
    }

    @MainActor
    func testBatchKeepsReviewedLeagueScopeAndRequestBoundWithoutReads() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session)
        let rows = try await client.catalogMatches(for: [officialRequest(competition: "la-liga"), request(category: "cricket")], now: fixedNow)
        XCTAssertEqual(rows.map(\.outcome), [.unsupported, .unsupported])
        do { _ = try await client.catalogMatches(for: Array(repeating: request(), count: 257), now: fixedNow); XCTFail("Bound") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
        XCTAssertTrue(StreamVixFixtureProtocol.paths.isEmpty)
    }

    func testObservedChelseaRawScheduleAndLiteralCatalogIDBridgeTheOriginalGMTKickoff() throws {
        let originals = try originals()
        XCTAssertEqual(originals.count, 1)
        XCTAssertEqual(originals.first?.kickoff, kickoff)
        XCTAssertEqual(originals.first?.competitionID, "premier-league")
        XCTAssertEqual(originals.first?.publishedTitle(derived: utc("2026-10-24T14:30:00Z")),
                       "⏰ 16:30 : Chelsea vs Tottenham Hotspur - Premier League 24/10")
        let row = try entry()
        XCTAssertFalse(row.hasMalformedIdentity)
        XCTAssertEqual(row.id, fixtureID)
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: originals), .matched(row))
        XCTAssertEqual(StreamVixSportsAddonClient.advertisedID(sourceTitle: originals[0].publishedTitle(derived: utc("2026-10-24T14:30:00Z"))!,
            derived: utc("2026-10-24T14:30:00Z")), fixtureID)
    }

    func testCorrectedUpstreamTimestampIsAcceptedButDisplayClockCannotExcuseAnotherOffset() throws {
        let originals = try originals()
        let corrected = try entry([
            "id": "tv:18-30-chelsea-vs-tottenham-hotspur-premier-league-24-10-20261024",
            "eventStart": "2026-10-24T16:30:00Z",
            "name": "Chelsea vs Tottenham Hotspur ⏰ 18:30 - 24/10",
            "description": "🔴 Inizio: 18:30 - Chelsea vs Tottenham Hotspur - Premier League - 24/10",
            "_originalName": "⏰ 18:30 : Chelsea vs Tottenham Hotspur - Premier League 24/10"
        ])
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [corrected], originals: originals), .matched(corrected))
        for timestamp in ["2026-10-24T15:30:00Z", "2026-10-24T18:30:00Z", "2026-10-24T14:31:00Z",
                          "2026-10-23T14:30:00Z", "2026-10-24T14:30:00+00:00", "2026-10-24T14:30:00.000Z"] {
            let row = try entry(["eventStart": timestamp])
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: originals), .missing, timestamp)
        }
    }

    func testCorrectedUTCMayDisplayNextRomeDayWithoutChangingTheOriginalFixtureDate() throws {
        let source = try originals(rows: [rawRow(["time": "23:30"])])
        let original = source[0]
        XCTAssertEqual(original.kickoff, utc("2026-10-24T23:30:00Z"))
        XCTAssertEqual(original.displayParts(derived: utc("2026-10-24T23:30:00Z"))?.dayMonth, "25/10")
        let title = "⏰ 01:30 : Chelsea vs Tottenham Hotspur - Premier League 25/10"
        let id = "tv:01-30-chelsea-vs-tottenham-hotspur-premier-league-25-10-20261024"
        XCTAssertEqual(StreamVixSportsAddonClient.advertisedID(sourceTitle: title, derived: utc("2026-10-24T23:30:00Z")), id)
        let row = try entry(["id": id, "eventStart": "2026-10-24T23:30:00Z",
            "name": "Chelsea vs Tottenham Hotspur ⏰ 01:30 - 25/10",
            "description": "🔴 Inizio: 01:30 - Chelsea vs Tottenham Hotspur - Premier League - 25/10",
            "_originalName": title])
        let requested = StreamPlaybackRequest(matchID: "existing-late-fixture", displayTitle: pair,
            homeTeam: "Chelsea", awayTeam: "Tottenham Hotspur", category: "football", kickoffDate: utc("2026-10-24T23:30:00Z"))
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: requested, from: [row], originals: source), .matched(row))
    }

    func testOptionalOriginalNameMayBeAbsentButWrongTargetAndTypeCannotCorroborate() throws {
        let originals = try originals()
        var without = entryJSON(); without.removeValue(forKey: "_originalName")
        let absent = try decodeEntry(without)
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [absent], originals: originals), .matched(absent))
        let good = try entry()
        for value: Any in [NSNull(), 1, ["not": "a string"], "⏰ 16:30 : Other vs Clubs - Premier League 24/10"] {
            let wrong = try entry(["_originalName": value])
            XCTAssertNotEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [wrong], originals: originals), .matched(wrong))
            for rows in [[good, wrong], [wrong, good]] {
                XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: rows, originals: originals), .conflicting)
            }
        }
    }

    func testOptionalCatalogGenreAndMetadataAbsenceCannotIntroduceConflictingIdentity() throws {
        let originals = try originals()
        for field in ["genre", "genres"] {
            let valid = try entry([field: ["premierleague"]])
            XCTAssertFalse(valid.hasMalformedIdentity)
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [valid], originals: originals), .matched(valid))
            for value: Any in [["coppe"], "premierleague", NSNull()] {
                let invalid = try entry([field: value])
                XCTAssertTrue(invalid.hasMalformedIdentity)
                XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [valid, invalid], originals: originals), .conflicting)
            }
        }
    }

    func testSameIDMalformedAndConflictingCatalogSiblingsVetoInBothOrders() throws {
        let good = try entry(), originals = try originals()
        for mutation: [String: Any] in [
            ["name": NSNull()], ["description": NSNull()], ["eventStart": NSNull()], ["category": "coppe"],
            ["_dynamic": false], ["_dynamic": "true"], ["type": "movie"],
            ["name": "Chelsea Women vs Tottenham Hotspur Women ⏰ 16:30 - 24/10"],
            ["eventStart": "2026-10-24T15:30:00Z"], ["released": "2026-10-24T16:30:00Z"],
            ["behaviorHints": NSNull()], ["videos": []]
        ] {
            let invalid = try entry(mutation)
            for rows in [[good, invalid], [invalid, good]] {
                XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: rows, originals: originals), .conflicting)
            }
        }
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [good, good], originals: originals), .matched(good))
    }

    func testOriginalMalformedTimeAndContradictoryDuplicateCannotDisappearBehindValidRow() throws {
        let row = try entry()
        for clock: Any in [NSNull(), "bad", "16:31", "18:30"] {
            let source = try originals(rows: [rawRow(), rawRow(["time": clock])])
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: source), .conflicting)
        }
    }

    func testTruncatedSlugCollisionCannotBorrowAnotherFullOriginalFixture() throws {
        let longHome = "A Football Club With An Extremely Long Distinct Official Name Beyond Sixty Characters"
        let firstPair = "\(longHome) vs First Opponent", secondPair = "\(longHome) vs Second Opponent"
        let first = try originals(rows: [rawRow(["event": "⚽ England - Premier League : " + firstPair])])[0]
        let second = try originals(rows: [rawRow(["event": "⚽ England - Premier League : " + secondPair])])[0]
        let id = StreamVixSportsAddonClient.advertisedID(sourceTitle: first.publishedTitle(derived: utc("2026-10-24T14:30:00Z"))!, derived: utc("2026-10-24T14:30:00Z"))
        XCTAssertEqual(id, StreamVixSportsAddonClient.advertisedID(sourceTitle: second.publishedTitle(derived: utc("2026-10-24T14:30:00Z"))!, derived: utc("2026-10-24T14:30:00Z")))
        let row = try decodeEntry(entryJSON(pair: firstPair, id: id))
        let requested = request(home: longHome, away: "First Opponent")
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: requested, from: [row], originals: [first]), .matched(row))
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: requested, from: [row], originals: [first, second]), .missing)
    }

    func testOriginalFullDateWeekdayAndGMTMarkerMustRemainExplicit() throws {
        let row = try entry()
        for day in ["Saturday 24th October - Schedule Time UK GMT", "Friday 24th October 2026 - Schedule Time UK GMT",
                    "Saturday 24th October 2026", "Saturday 24th October 2026 - Schedule Time UK BST",
                    "Saturday 24th October 2026 - Schedule Time Europe/Rome",
                    "Saturday 24rd October 2026 - Schedule Time UK GMT"] {
            XCTAssertThrowsError(try originals(day: day), day) {
                XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
            }
        }
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: []), .missing)
    }

    func testEquivalentOriginalCalendarSpellingsCannotHideAConflictingClock() throws {
        let abbreviated = "Saturday 24th Oct 2026 - Schedule Time UK GMT"
        let valid = try originals()
        let same = try originals(day: abbreviated)
        let row = try entry()
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: valid + same), .matched(row))
        let contradictory = try originals(day: abbreviated, rows: [rawRow(["time": "18:30"])])
        for source in [valid + contradictory, contradictory + valid] {
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: source), .conflicting)
        }
    }

    func testUEFAChampionsLeagueNeedsExactOriginalCompetitionAndCannotBorrowMixedCoppeLabel() throws {
        let originalRows = try originals(rows: [rawRow(["event": "⚽ UEFA Champions League : " + pair])])
        let original = originalRows[0]
        let id = StreamVixSportsAddonClient.advertisedID(sourceTitle: original.publishedTitle(derived: utc("2026-10-24T14:30:00Z"))!, derived: utc("2026-10-24T14:30:00Z"))
        let row = try decodeEntry(entryJSON(id: id, category: "coppe", league: "UEFA Champions League"))
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: originalRows), .matched(row))
        for competition in ["UEFA Europa League", "UEFA Conference League", "UEFA Youth League",
                            "UEFA Women's Champions League", "AFC Champions League", "Spain - Liga"] {
            let source = try originals(rows: [rawRow(["event": "⚽ " + competition + " : " + pair])])
            XCTAssertTrue(source.isEmpty, competition)
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: source), .missing, competition)
        }
        let wrongLeague = try decodeEntry(entryJSON(id: id, category: "coppe", league: "UEFA Europa League"))
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [wrongLeague], originals: originalRows), .missing)
    }

    @MainActor
    func testFullPairSquadAndOfficialCompetitionCannotBeChangedBySourceNames() throws {
        let row = try entry(), source = try originals()
        for requested in [request(home: "Chelsea Women", away: "Tottenham Hotspur Women"),
                          request(home: "Chelsea U19", away: "Tottenham Hotspur U19"),
                          request(home: "Chelsea", away: "Other Club"), request(category: "cricket")] {
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: requested, from: [row], originals: source), .missing)
        }
        let official = officialRequest(competition: "champions-league")
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: official, from: [row], originals: source), .conflicting)
        let changed = try entry(["name": "Other Team vs Tottenham Hotspur ⏰ 16:30 - 24/10"])
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [changed], originals: source), .missing)
    }

    func testOnlyReviewedStandaloneFlagsMayBeRemovedFromObservedIdentity() throws {
        let flaggedPair = "Chelsea \(england) vs Tottenham Hotspur \(england)"
        let source = try originals(rows: [rawRow(["event": "⚽ England - Premier League : " + flaggedPair])])
        let row = try decodeEntry(entryJSON(pair: flaggedPair))
        XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [row], originals: source), .matched(row))
        for badPair in ["Chelsea 🇿🇦 vs Tottenham Hotspur", "Chelsea\n vs Tottenham Hotspur",
                        "Chelsea vs Tottenham Hotspur Women", "Chelsea vs Tottenham Hotspur vs Other Club"] {
            let invalid = try decodeEntry(entryJSON(pair: badPair))
            XCTAssertEqual(StreamVixSportsAddonClient.selectMatch(for: request(), from: [invalid], originals: source), .missing)
        }
    }

    func testMetadataRoutesKeepExactOriginsGenrePathsLiteralIDsAndNoArbitraryManifest() {
        for value in [StreamVixSportsAddonClient.manifestURL.absoluteString,
                      StreamVixSportsAddonClient.originalScheduleURL.absoluteString,
                      "https://streamvix.hayd.uk/catalog/tv/streamvix_eventi/genre=Premier%20League.json",
                      "https://streamvix.hayd.uk/catalog/tv/streamvix_eventi/genre=Coppe.json",
                      "https://streamvix.hayd.uk/meta/tv/\(fixtureID).json",
                      "https://streamvix.hayd.uk/stream/tv/\(fixtureID).json"] {
            XCTAssertTrue(StreamVixSportsAddonClient.isSafeMetadataURL(URL(string: value)!), value)
        }
        for value in ["http://streamvix.hayd.uk/manifest.json", "https://streamvix.hayd.uk.evil.invalid/manifest.json",
                      "https://user@streamvix.hayd.uk/manifest.json", "https://streamvix.hayd.uk:8443/manifest.json",
                      "https://streamvix.hayd.uk/manifest.json?token=private", "https://streamvix.hayd.uk/manifest.json#other",
                      "https://streamvix.hayd.uk/catalog/tv/streamvix_eventi/genre=Cricket.json",
                      "https://streamvix.hayd.uk/meta/tv/arbitrary.json", "https://streamvix.hayd.uk/stream/tv/../private.json",
                      "https://raw.githubusercontent.com/another/repo/main/daddyliveSchedule.json"] {
            XCTAssertFalse(StreamVixSportsAddonClient.isSafeMetadataURL(URL(string: value)!), value)
        }
    }

    func testNativeDeliveryRequiresExactHTTPSOriginPathFreshSignedQueryAndNoCredentials() {
        XCTAssertTrue(StreamVixSportsAddonClient.isAdmittedDelivery(URL(string: delivery)!, now: fixedNow))
        for value in ["http://p7.streamhostingcdn.top/stream/870/index.m3u8?token=x&exp=1792864800",
                      delivery.replacingOccurrences(of: "p7.", with: "p8."),
                      delivery.replacingOccurrences(of: ".top/", with: ".top:8443/"),
                      delivery.replacingOccurrences(of: "https://", with: "https://user@"),
                      delivery.replacingOccurrences(of: "/870/", with: "/0/"),
                      delivery.replacingOccurrences(of: "/870/", with: "/%38%37%30/"),
                      delivery.replacingOccurrences(of: "index.m3u8", with: "child/index.m3u8"),
                      delivery.replacingOccurrences(of: "token=synthetic-signature", with: "token="),
                      delivery.replacingOccurrences(of: "token=synthetic-signature", with: "token=has%20space"),
                      delivery.replacingOccurrences(of: "token=synthetic-signature", with: "token=has%0Acontrol"),
                      delivery.replacingOccurrences(of: "1792864800", with: "1"),
                      delivery.replacingOccurrences(of: "1792864800", with: String(Int(fixedNow.timeIntervalSince1970))),
                      delivery + "&token=second", delivery + "&unknown=1", delivery + "#fragment",
                      "https://streamvix.hayd.uk/upcoming.html"] {
            XCTAssertFalse(StreamVixSportsAddonClient.isAdmittedDelivery(URL(string: value)!, now: fixedNow), value)
        }
    }

    func testSessionAdmissionPreservesTwoDistinctDeliveriesAndTheirOpaqueKeys() throws {
        let second = delivery.replacingOccurrences(of: "/870/", with: "/871/")
        let streams = try decodeStreams([streamJSON(), streamJSON(), streamJSON(url: second)])
        let sessions = StreamVixSportsAddonClient.makeSessions(from: streams, request: request(), addOnVersion: "1.0.0", now: fixedNow)
        XCTAssertEqual(sessions.map(\.providerName), ["SV1", "SV2"])
        XCTAssertEqual(sessions.map(\.playableURL), [URL(string: delivery)!, URL(string: second)!])
        for session in sessions {
            XCTAssertEqual(session.streamType, .hls)
            XCTAssertEqual(session.requiresGuardedRelay, true)
            XCTAssertTrue(session.requiredHeaders.isEmpty)
            XCTAssertNil(session.nativeOriginProfile)
            XCTAssertNil(session.nativePlaylistProfile)
            XCTAssertEqual(session.diagnosticMetadata["source_family"], "streamvix")
            XCTAssertEqual(session.expiryTime, Date(timeIntervalSince1970: 1_792_864_800))
            XCTAssertFalse(session.hasExpiredMediaLease(at: fixedNow))
            XCTAssertTrue(session.hasExpiredMediaLease(at: Date(timeIntervalSince1970: 1_792_864_800)))
            let key = try XCTUnwrap(session.diagnosticMetadata["source_key"])
            XCTAssertNotNil(key.range(of: #"^sv_[a-f0-9]{24}$"#, options: .regularExpression))
            XCTAssertFalse(key.contains("synthetic-signature"))
        }
        XCTAssertNotEqual(StreamVixSportsAddonClient.sourceKey(url: URL(string: delivery)!),
                          StreamVixSportsAddonClient.sourceKey(url: URL(string: second)!))
        let reversed = StreamVixSportsAddonClient.makeSessions(from: Array(streams.reversed()), request: request(), addOnVersion: "1.0.0", now: fixedNow)
        XCTAssertEqual(Set(sessions.compactMap { $0.diagnosticMetadata["source_key"] }),
                       Set(reversed.compactMap { $0.diagnosticMetadata["source_key"] }))
    }

    func testAdditionalHeadersDRMExternalPlayerAndMalformedRowsCannotBecomeNativeOptions() throws {
        for mutation: [String: Any] in [["externalUrl": "https://example.invalid/player"], ["behaviorHints": [:]],
                                       ["headers": ["Referer": "https://example.invalid/"]], ["drm": "widevine"],
                                       ["name": NSNull()], ["title": 1]] {
            let streams = try decodeStreams([streamJSON().merging(mutation, uniquingKeysWith: { _, new in new })])
            XCTAssertTrue(StreamVixSportsAddonClient.makeSessions(from: streams, request: request(), addOnVersion: "1.0.0", now: fixedNow).isEmpty)
        }
        let choices = (1...8).map { streamJSON(url: delivery.replacingOccurrences(of: "/870/", with: "/\($0)/")) }
        XCTAssertEqual(StreamVixSportsAddonClient.makeSessions(from: try decodeStreams(choices), request: request(),
            addOnVersion: "1.0.0", now: fixedNow).count, 6)
    }

    func testNormalResolutionUsesOnlyAdvertisedLiteralIDMetaAndStreamRoutes() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let sources = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow)
        XCTAssertEqual(sources.map(\.providerName), ["SV1"])
        let binding = try XCTUnwrap(sources.first?.eventBinding)
        XCTAssertEqual(binding.providerEventID, fixtureID)
        XCTAssertEqual(binding.streamID, fixtureID)
        XCTAssertTrue(binding.matches(request: request(), providerCode: "streamvix", at: fixedNow))
        XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath, catalogPath, metaPath, streamPath])
        XCTAssertEqual(StreamVixFixtureProtocol.requests.map(\.timeoutInterval), [7, 7, 7, 7, 11])
        XCTAssertFalse(StreamVixFixtureProtocol.paths.contains { $0.contains("search=") })
        XCTAssertEqual(Set(StreamVixFixtureProtocol.requests.compactMap { $0.url?.host }),
                       ["streamvix.hayd.uk", "raw.githubusercontent.com"])
    }

    @MainActor
    func testRegisteredResolutionSurvivesTheProductionResolverBindingGate() async throws {
        let clock = Date(), fixture = try registeredFixtureSession(at: clock)
        defer { fixture.session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: fixture.session)
        let published = expectation(description: "Exact registered SV delivery reaches the production publication gate")
        let choices = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: fixture.request,
            providerCode: "streamvix", associations: [fixture.association], resolve: { request in
                try await client.resolve(for: request, now: clock)
            }, onSession: { _ in published.fulfill() }, clock: { clock })
        await fulfillment(of: [published], timeout: 1)
        let selected = try XCTUnwrap(choices.first), binding = try XCTUnwrap(selected.eventBinding)
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(binding.providerEventID, fixture.id)
        XCTAssertEqual(binding.streamID, fixture.id)
        XCTAssertTrue(binding.matches(request: fixture.request, providerCode: "streamvix", at: clock))
        XCTAssertEqual(selected.expiryTime, fixture.expiry)
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }, ["/meta/tv/" + fixture.id + ".json"])
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }, ["/stream/tv/" + fixture.id + ".json"])
    }

    @MainActor
    func testRegisteredResolutionCannotPublishChangedMetadataOrAnExpiredMediaLease() async throws {
        for changedMetadata in [false, true] {
            let clock = Date(), fixture = try registeredFixtureSession(at: clock, mediaLifetime: 30)
            defer { fixture.session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
            if changedMetadata {
                var meta = fixture.meta; meta["id"] = fixture.id + "-different"
                StreamVixFixtureProtocol.setResponse(try .json(["meta": meta]), for: "/meta/tv/" + fixture.id + ".json")
            }
            let client = StreamVixSportsAddonClient(session: fixture.session)
            do {
                _ = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: fixture.request,
                    providerCode: "streamvix", associations: [fixture.association], resolve: { request in
                        try await client.resolve(for: request, now: clock)
                    }, clock: { changedMetadata ? clock : clock.addingTimeInterval(31) })
                XCTFail("Changed identity or expired delivery cannot reach the picker")
            } catch {
                XCTAssertEqual(error as? CommunitySportsAddonError, changedMetadata ? .conflictingMatch : .matchNotFound)
            }
            if changedMetadata { XCTAssertFalse(StreamVixFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") }) }
        }
    }

    @MainActor
    func testCancelledRegisteredResolutionCannotPublishALateDescriptor() async throws {
        let clock = Date(), fixture = try registeredFixtureSession(at: clock)
        let gate = StreamVixFixtureGate("registered descriptor cancellation")
        defer { fixture.session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        StreamVixFixtureProtocol.setResponse(.controlled(gate), for: "/stream/tv/" + fixture.id + ".json")
        let client = StreamVixSportsAddonClient(session: fixture.session)
        let published = expectation(description: "Cancelled registered descriptor cannot publish")
        published.isInverted = true
        let task = Task {
            try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: fixture.request,
                providerCode: "streamvix", associations: [fixture.association], resolve: { request in
                    try await client.resolve(for: request, now: clock)
                }, onSession: { _ in published.fulfill() }, clock: { clock })
        }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        task.cancel()
        gate.respond(try .json(["streams": [streamJSON(url: delivery.replacingOccurrences(of: "1792864800",
            with: String(Int(fixture.expiry.timeIntervalSince1970))))]]))
        do { _ = try await task.value; XCTFail("The cancelled owner cannot acquire the descriptor") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [published], timeout: 0.05)
    }

    func testConflictingCatalogOrMetadataCannotReachStreamLookup() async throws {
        for conflictInMeta in [false, true] {
            let session = try fixtureSession()
            defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
            let invalid = entryJSON().merging(["eventStart": "2026-10-24T15:30:00Z"], uniquingKeysWith: { _, new in new })
            if conflictInMeta {
                StreamVixFixtureProtocol.setResponse(try .json(["meta": invalid]), for: metaPath)
            } else {
                StreamVixFixtureProtocol.setResponse(try .json(["metas": [entryJSON(), invalid]]), for: catalogPath)
            }
            do { _ = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow); XCTFail("Conflicting facts") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(streamPath))
        }
    }

    func testMetadataMustRepeatLiteralCatalogIDWithoutInventingSiblingStreamRoute() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        StreamVixFixtureProtocol.setResponse(try .json(["meta": entryJSON().merging([
            "id": "tv:another-fixture-20261024"], uniquingKeysWith: { _, new in new })]), for: metaPath)
        do { _ = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow); XCTFail("Different effective identity") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(streamPath))
        XCTAssertFalse(StreamVixFixtureProtocol.paths.contains { $0.contains("another-fixture") })
    }

    func testUnsupportedSportMissingKickoffAndAbsentOriginalFixtureStopBeforeDiscovery() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session)
        for requested in [request(category: "cricket"), request(category: "basketball"),
                          StreamPlaybackRequest(matchID: "no-date", displayTitle: pair, homeTeam: "Chelsea",
                            awayTeam: "Tottenham Hotspur", category: "football")] {
            do { _ = try await client.resolve(for: requested, now: fixedNow); XCTFail("Unsupported request") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertTrue(StreamVixFixtureProtocol.paths.isEmpty)
        StreamVixFixtureProtocol.setResponse(try .json([:]), for: originalPath)
        do { _ = try await client.resolve(for: request(), now: fixedNow); XCTFail("Missing original") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath])
    }

    func testPositiveMetadataCachesExpireWhileMetaAndSignedDeliveriesAreNeverCached() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session)
        _ = try await client.resolve(for: request(), now: fixedNow)
        _ = try await client.resolve(for: request(), now: fixedNow.addingTimeInterval(119))
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == originalPath }.count, 1)
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == catalogPath }.count, 1)
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == metaPath }.count, 2)
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == streamPath }.count, 2)
        StreamVixFixtureProtocol.setResponse(.status(503), for: catalogPath)
        do { _ = try await client.resolve(for: request(), now: fixedNow.addingTimeInterval(120)); XCTFail("Expired catalog") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .catalog)) }
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == catalogPath }.count, 2)
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == streamPath }.count, 2)
    }

    func testEmptyOriginalScheduleCachesOnlyFifteenSecondsAndDoesNotBecomeCurrentOnFailure() async throws {
        let session = try fixtureSession(originals: .json([:]))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session)
        for age in [0.0, 14.0] {
            do { _ = try await client.resolve(for: request(), now: fixedNow.addingTimeInterval(age)); XCTFail("No original fixture") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == originalPath }.count, 1)
        StreamVixFixtureProtocol.setResponse(try .json(rawSchedule()), for: originalPath)
        _ = try await client.resolve(for: request(), now: fixedNow.addingTimeInterval(15))
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == originalPath }.count, 2)
    }

    func testCancellationWhileOriginalMetadataIsPendingCannotRequestCatalogMetaOrStreams() async throws {
        let gate = StreamVixFixtureGate("pending original metadata")
        let session = try fixtureSession(originals: .controlled(gate))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session)
        let requested = request(), now = fixedNow
        let task = Task { try await client.resolve(for: requested, now: now) }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        task.cancel()
        gate.respond(try .json(rawSchedule()))
        do { _ = try await task.value; XCTFail("Cancelled resolution") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json", originalPath])
        StreamVixFixtureProtocol.setResponse(try .json(rawSchedule()), for: originalPath)
        _ = try await client.resolve(for: request(), now: fixedNow.addingTimeInterval(1))
        XCTAssertEqual(StreamVixFixtureProtocol.paths.filter { $0 == originalPath }.count, 2,
                       "Cancelled completion must not refresh the accepted snapshot")
    }

    func testTokenExpiringDuringMetadataFetchIsRejectedUsingElapsedAdmissionTime() async throws {
        let gate = StreamVixFixtureGate("pending stream descriptor")
        let session = try fixtureSession(streams: .controlled(gate))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        let client = StreamVixSportsAddonClient(session: session)
        let now = fixedNow, requested = request()
        let expiry = String(Int(now.timeIntervalSince1970) + 1)
        let shortLived = delivery.replacingOccurrences(of: "1792864800", with: expiry)
        XCTAssertTrue(StreamVixSportsAddonClient.isAdmittedDelivery(URL(string: shortLived)!, now: now))
        let task = Task { try await client.resolve(for: requested, now: now) }
        defer { task.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        try await Task.sleep(for: .milliseconds(1_100))
        gate.respond(try .json(["streams": [streamJSON(url: shortLived)]]))
        do { _ = try await task.value; XCTFail("Expired during sequential lookup") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 1)) }
    }

    func testMetadataRedirectToAnotherHostOrPathIsRejectedBeforeFixtureUse() async throws {
        for target in ["https://another.invalid/manifest.json", "https://streamvix.hayd.uk/other.json",
                       "https://streamvix.hayd.uk/manifest.json?private=value"] {
            let session = try fixtureSession(manifest: .redirect(URL(string: target)!))
            defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
            do { _ = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow); XCTFail("Unsafe redirect") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .unsafeResponse) }
            XCTAssertEqual(StreamVixFixtureProtocol.paths, ["/manifest.json"])
        }
    }

    func testOversizeOriginalCatalogAndManifestFailBeforeAnyMediaRequest() async throws {
        for (path, size) in [("/manifest.json", 128 * 1024 + 1), (originalPath, 1024 * 1024 + 1),
                             (catalogPath, 512 * 1024 + 1)] {
            let session = try fixtureSession()
            defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
            StreamVixFixtureProtocol.setResponse(.body(Data(repeating: 0x20, count: size)), for: path)
            do { _ = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow); XCTFail("Oversize response") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
            XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(streamPath))
        }
    }

    func testOriginalAndCatalogRowLimitsFailClosedWithoutDroppingLaterEvidence() async throws {
        XCTAssertThrowsError(try StreamVixSportsAddonClient.originalFixtures(data: data(rawSchedule(rows:
            Array(repeating: rawRow(), count: 601)))))
        XCTAssertThrowsError(try StreamVixSportsAddonClient.originalFixtures(data: data(["bad-day": "not an object"])))
        let session = try fixtureSession(catalog: .json(["metas": Array(repeating: entryJSON(), count: 201)]))
        defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
        do { _ = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow); XCTFail("Catalog limit") }
        catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(metaPath))
        XCTAssertFalse(StreamVixFixtureProtocol.paths.contains(streamPath))
    }

    func testEmptyIncompatibleAndPastScanBoundaryStreamsRemainDistinctNonPasses() async throws {
        let responses: [(StreamVixFixtureProtocol.Response, CommunitySportsAddonError)] = [
            (try .json(["streams": []]), .streamEntriesEmpty),
            (try .json(["streams": [streamJSON(url: "https://streamvix.hayd.uk/upcoming.html")]]), .streamAdmissionRejected(entryCount: 1)),
            (try .json(["streams": Array<Any>(repeating: NSNull(), count: 100) + [streamJSON()]]), .streamAdmissionRejected(entryCount: 100))
        ]
        for (response, expected) in responses {
            let session = try fixtureSession(streams: response)
            defer { session.invalidateAndCancel(); StreamVixFixtureProtocol.reset() }
            do { _ = try await StreamVixSportsAddonClient(session: session).resolve(for: request(), now: fixedNow); XCTFail("No admitted delivery") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, expected) }
        }
    }

    private var originalPath: String { "/qwertyuiop8899/logo/main/daddyliveSchedule.json" }
    private var catalogPath: String { "/catalog/tv/streamvix_eventi/genre=Premier League.json" }
    private var metaPath: String { "/meta/tv/\(fixtureID).json" }
    private var streamPath: String { "/stream/tv/\(fixtureID).json" }

    private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func request(home: String = "Chelsea", away: String = "Tottenham Hotspur", category: String = "football") -> StreamPlaybackRequest {
        .init(matchID: "existing-reviewed-fixture", displayTitle: "\(home) vs \(away)", homeTeam: home,
              awayTeam: away, category: category, kickoffDate: kickoff)
    }
    @MainActor
    private func officialRequest(competition: String) -> StreamPlaybackRequest {
        let base = request()
        let event = EventReference(id: base.matchID, title: base.displayTitle, category: "football",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: base.homeTeam, badge: nil), away: .init(name: base.awayTeam, badge: nil)),
            sources: [], competitionID: competition)
        return .init(matchID: base.matchID, displayTitle: base.displayTitle, homeTeam: base.homeTeam,
                     awayTeam: base.awayTeam, category: base.category, kickoffDate: kickoff, preferredEvent: event)
    }
    private func manifestJSON() -> [String: Any] {
        ["id": "org.prisonmike.streamvix", "version": "1.0.0", "types": ["tv"], "resources": ["catalog", "meta", "stream"],
         "catalogs": [["id": "streamvix_eventi", "type": "tv", "extra": [["name": "genre", "isRequired": true,
            "options": ["Premier League", "Coppe"]]]]], "behaviorHints": ["configurationRequired": false]]
    }
    private func rawRow(_ changes: [String: Any] = [:]) -> [String: Any] {
        ["event": "⚽ England - Premier League : " + pair, "time": "16:30", "channels": []]
            .merging(changes, uniquingKeysWith: { _, new in new })
    }
    private func rawSchedule(day: String? = nil, rows: [[String: Any]]? = nil) -> [String: Any] {
        [day ?? header: ["All Soccer Events ⚽": rows ?? [rawRow()]]]
    }
    private func originals(day: String? = nil, rows: [[String: Any]]? = nil) throws -> [StreamVixOriginalFixture] {
        try StreamVixSportsAddonClient.originalFixtures(data: data(rawSchedule(day: day, rows: rows)))
    }
    private func entryJSON(pair requestedPair: String? = nil, id: String? = nil,
                           category: String = "premierleague", league: String = "Premier League") -> [String: Any] {
        let pair = requestedPair ?? self.pair
        return ["id": id ?? fixtureID, "type": "tv", "name": "\(pair) ⏰ 16:30 - 24/10",
                "description": "🔴 Inizio: 16:30 - \(pair) - \(league) - 24/10",
                "eventStart": "2026-10-24T14:30:00Z", "category": category, "_dynamic": true,
                "_originalName": "⏰ 16:30 : \(pair) - \(league) 24/10"]
    }
    private func entry(_ changes: [String: Any] = [:]) throws -> StreamVixCatalogEntry {
        try decodeEntry(entryJSON().merging(changes, uniquingKeysWith: { _, new in new }))
    }
    private func decodeEntry(_ value: [String: Any]) throws -> StreamVixCatalogEntry {
        try JSONDecoder().decode(StreamVixCatalogEntry.self, from: data(value))
    }
    private func streamJSON(url: String? = nil) -> [String: Any] {
        ["name": "StreamViX", "title": "HD", "url": url ?? delivery]
    }

    @MainActor
    private func registeredFixtureSession(at clock: Date, mediaLifetime: TimeInterval = 600) throws -> (
        session: URLSession, request: StreamPlaybackRequest, association: BroadcastRegistryMatch,
        id: String, expiry: Date, meta: [String: Any]
    ) {
        let start = Date(timeIntervalSince1970: floor(clock.timeIntervalSince1970 / 60) * 60 - 600)
        func text(_ format: String) -> String {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
            return formatter.string(from: start)
        }
        let original = StreamVixOriginalFixture(dayHeader: text("EEEE d MMMM yyyy ' - Schedule Time UK GMT'").replacingOccurrences(of: "  -", with: " -"),
            clock: text("HH:mm"), pairTitle: pair, competition: "England - Premier League", kickoff: start)
        let parts = try XCTUnwrap(original.displayParts(derived: start)), title = try XCTUnwrap(original.publishedTitle(derived: start))
        let id = StreamVixSportsAddonClient.advertisedID(sourceTitle: title, derived: start)
        let meta: [String: Any] = ["id": id, "type": "tv", "name": "\(pair) ⏰ \(parts.clock) - \(parts.dayMonth)",
            "description": "🔴 Inizio: \(parts.clock) - \(pair) - Premier League - \(parts.dayMonth)",
            "eventStart": ISO8601DateFormatter().string(from: start), "category": "premierleague", "_dynamic": true,
            "_originalName": title]
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:sv-regression", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: pair,
            participants: [.init(id: "chelsea", name: "Chelsea"), .init(id: "tottenham", name: "Tottenham Hotspur")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: clock, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: pair, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Chelsea", badge: nil), away: .init(name: "Tottenham Hotspur", badge: nil)),
            sources: [], sportsFixture: metadata, competitionID: "premier-league")
        let request = StreamPlaybackRequest(event: event), lease = clock.addingTimeInterval(600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "streamvix",
            providerEventID: id, streamID: id, resourceType: "tv", scope: "football", kind: .event, sport: "football",
            title: pair, participants: ["Chelsea", "Tottenham Hotspur"], start: start, competitionID: "premier-league",
            squad: metadata.squad, observedAt: clock, expiresAt: lease, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "streamvix",
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: start,
                participants: ["Chelsea", "Tottenham Hotspur"], competitionID: "premier-league", squad: metadata.squad), expiresAt: lease)
        let association = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: "streamvix",
            scope: "football", status: .available, observedAt: clock, expiresAt: lease))
        let expiry = Date(timeIntervalSince1970: floor(clock.timeIntervalSince1970 + mediaLifetime))
        let stream = streamJSON(url: delivery.replacingOccurrences(of: "1792864800", with: String(Int(expiry.timeIntervalSince1970))))
        let session = try fixtureSession(originals: .json([original.dayHeader: ["All Soccer Events ⚽": [[
            "event": "⚽ England - Premier League : " + pair, "time": original.clock, "channels": []]]]]),
            catalog: .json(["metas": [meta]]))
        StreamVixFixtureProtocol.setResponse(try .json(["meta": meta]), for: "/meta/tv/" + id + ".json")
        StreamVixFixtureProtocol.setResponse(try .json(["streams": [stream]]), for: "/stream/tv/" + id + ".json")
        return (session, request, association, id, expiry, meta)
    }
    private func decodeStreams(_ rows: [[String: Any]]) throws -> [StreamVixStreamEntry] {
        rows.compactMap { row in
            guard let bytes = try? data(row) else { return nil }
            return try? JSONDecoder().decode(StreamVixStreamEntry.self, from: bytes)
        }
    }
    private func fixtureSession(manifest: StreamVixFixtureProtocol.Response? = nil,
                                originals: StreamVixFixtureProtocol.Response? = nil,
                                catalog: StreamVixFixtureProtocol.Response? = nil,
                                streams: StreamVixFixtureProtocol.Response? = nil) throws -> URLSession {
        var meta = entryJSON(); meta.removeValue(forKey: "_originalName")
        StreamVixFixtureProtocol.configure([
            "/manifest.json": try manifest ?? .json(manifestJSON()),
            originalPath: try originals ?? .json(rawSchedule()),
            catalogPath: try catalog ?? .json(["metas": [entryJSON()]]),
            metaPath: try .json(["meta": meta]),
            streamPath: try streams ?? .json(["streams": [streamJSON()]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamVixFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

private final class StreamVixFixtureProtocol: URLProtocol {
    enum Response {
        case body(Data), status(Int), failure(Error), controlled(StreamVixFixtureGate), redirect(URL)
        static func json(_ object: [String: Any]) throws -> Response {
            .body(try JSONSerialization.data(withJSONObject: object))
        }
    }
    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var recorded: [URLRequest] = []
    private let stateLock = NSLock()
    private var stopped = false
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    static var paths: [String] { requests.map { $0.url?.path ?? "" } }
    static func configure(_ values: [String: Response]) {
        lock.lock(); responses = values; recorded = []; lock.unlock()
    }
    static func reset() { configure([:]) }
    static func setResponse(_ value: Response, for path: String) { lock.lock(); responses[path] = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let response = Self.responses[request.url?.path ?? ""] ?? .failure(URLError(.fileDoesNotExist))
        Self.lock.unlock()
        complete(response)
    }
    private func complete(_ value: Response) {
        stateLock.lock(); let active = !stopped; stateLock.unlock()
        guard active else { return }
        switch value {
        case .body(let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        case .status(let code):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .controlled(let gate): gate.start { [weak self] in self?.complete($0) }
        case .redirect(let target):
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}

private final class StreamVixFixtureGate {
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((StreamVixFixtureProtocol.Response) -> Void)?
    private var pending: StreamVixFixtureProtocol.Response?
    init(_ name: String) { started = XCTestExpectation(description: name) }
    func start(_ completion: @escaping (StreamVixFixtureProtocol.Response) -> Void) {
        lock.lock(); let pending = self.pending; self.pending = nil
        if pending == nil { self.completion = completion }
        lock.unlock(); started.fulfill()
        if let pending { completion(pending) }
    }
    func respond(_ value: StreamVixFixtureProtocol.Response) {
        lock.lock(); let completion = self.completion; self.completion = nil
        if completion == nil { pending = value }
        lock.unlock(); completion?(value)
    }
}
