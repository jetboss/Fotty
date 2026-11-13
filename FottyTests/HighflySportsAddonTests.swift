import XCTest
@testable import Fotty

final class HighflySportsAddonTests: XCTestCase {
    private let kickoff = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!
    private func request() -> StreamPlaybackRequest {
        .init(matchID: "official-synthetic", displayTitle: "Arsenal vs Everton", homeTeam: "Arsenal",
              awayTeam: "Everton", category: "football", kickoffDate: kickoff)
    }
    private func row(id: String = "streamed:synthetic", name: String = "Arsenal vs Everton",
                     date: String = "10 Nov 2026 · 18:00 UTC") -> HighflySportsAddonClient.Row {
        .init(id: id, name: name, description: name + "\n" + date, releaseInfo: date, category: "football")
    }

    func testExactFixtureAndDuplicateRowsDoNotInventProgrammeIdentity() throws {
        let good = row()
        XCTAssertEqual(try HighflySportsAddonClient.select(request: request(), rows: [good, good], now: kickoff), good)
        for bad in [row(name: "Arsenal Women vs Everton Women"), row(name: "Sky Sports Premier League"),
                    row(date: "11 Nov 2026 · 18:00 UTC"), row(date: "10 Nov 2026 · 18:16 UTC"),
                    row(date: "10 Nov 2026 · 18:00"), row(id: "recap:synthetic")] {
            XCTAssertThrowsError(try HighflySportsAddonClient.select(request: request(), rows: [bad], now: kickoff))
        }
    }

    func testEveryScheduledSportUsesItsOwnHighflyCatalog() {
        for (category, catalog) in [("football", "sports_football"), ("cricket", "sports_cricket"),
                                    ("basketball", "sports_basketball"), ("baseball", "sports_baseball"),
                                    ("hockey", "sports_hockey"), ("american-football", "sports_american_football"),
                                    ("NFL", "sports_american_football"), ("NBA", "sports_basketball")] {
            XCTAssertTrue(HighflySportsAddonClient.supports(category: category), category)
            XCTAssertEqual(HighflySportsAddonClient.catalogID(forSport: category), catalog)
        }
        // No Fotty schedule exists to match these against.
        for category in ["rugby", "fight", "golf", "motorsport", "tennis", "darts", "other"] {
            XCTAssertFalse(HighflySportsAddonClient.supports(category: category), category)
        }
    }

    func testHockeyRowMatchesTheOfficialScheduleFixture() throws {
        let start = ISO8601DateFormatter().date(from: "2026-11-11T00:00:00Z")!
        let nhl = StreamPlaybackRequest(matchID: "sports-fixture:nhl:synthetic", displayTitle: "Montreal Canadiens vs Minnesota Wild",
            homeTeam: "Montreal Canadiens", awayTeam: "Minnesota Wild", category: "hockey", kickoffDate: start)
        let date = "11 Nov 2026 · 00:00 UTC", name = "Montreal Canadiens vs Minnesota Wild"
        let good = HighflySportsAddonClient.Row(id: "streamed:nhl", name: name, description: name + "\n" + date,
            releaseInfo: date, category: "hockey")
        XCTAssertEqual(try HighflySportsAddonClient.select(request: nhl, rows: [good], now: start), good)
        let swapped = HighflySportsAddonClient.Row(id: "streamed:other", name: "Ottawa Senators vs Washington Capitals",
            description: "Ottawa Senators vs Washington Capitals\n" + date, releaseInfo: date, category: "hockey")
        XCTAssertThrowsError(try HighflySportsAddonClient.select(request: nhl, rows: [swapped], now: start))
    }

    func testMalformedSiblingVetoIsLocalToItsIdentity() throws {
        let good = row()
        let malformed = HighflySportsAddonClient.Row(id: good.id, name: good.name, description: "LIVE",
                                                      releaseInfo: "LIVE", category: "football")
        XCTAssertThrowsError(try HighflySportsAddonClient.select(request: request(), rows: [good, malformed], now: kickoff))
        XCTAssertEqual(try HighflySportsAddonClient.select(request: request(), rows: [good, row(id: "streamed:other", name: "Unknown Channel")], now: kickoff), good)
        XCTAssertNil(HighflySportsAddonClient.identity(row(date: "30 Feb 2026 · 18:00 UTC")))
    }

    @MainActor
    func testTestDayUsesVerifiedOrdinalDayAndOriginalFixture() throws {
        let start = ISO8601DateFormatter().date(from: "2026-11-09T04:30:00Z")!
        let now = start.addingTimeInterval(86400)
        func fixture(day: Int, ordinal: Int, verified: Bool = true) -> StreamPlaybackRequest {
            let metadata = CricketFixtureMetadata(fixtureID: "synthetic-test", competitionID: "icc",
                competitionName: "Test Series", format: .test, status: .live, observedAt: now, verified: verified,
                context: .init(innings: [], day: day, matchOrdinal: ordinal))
            let event = EventReference(id: "cricket-fixture:synthetic-test", title: "Pakistan vs Sri Lanka", category: "cricket",
                date: Int64(start.timeIntervalSince1970 * 1000), poster: nil, popular: false,
                teams: .init(home: .init(name: "Pakistan", badge: nil), away: .init(name: "Sri Lanka", badge: nil)), cricketFixture: metadata)
            return .init(event: event)
        }
        let item = HighflySportsAddonClient.Row(id: "sf:test", name: "Pakistan vs Sri Lanka - 1st Test Day 2",
            description: "Pakistan vs Sri Lanka\n10 Nov 2026 · 05:00 UTC", releaseInfo: "10 Nov 2026 · 05:00 UTC", category: "cricket")
        XCTAssertEqual(try HighflySportsAddonClient.select(request: fixture(day: 2, ordinal: 1), rows: [item], now: now), item)
        for invalid in [fixture(day: 1, ordinal: 1), fixture(day: 2, ordinal: 2), fixture(day: 2, ordinal: 1, verified: false)] {
            XCTAssertThrowsError(try HighflySportsAddonClient.select(request: invalid, rows: [item], now: now))
        }
        XCTAssertThrowsError(try HighflySportsAddonClient.select(request: fixture(day: 2, ordinal: 1), rows: [item], now: now.addingTimeInterval(86400)))
    }

    func testAccountDeliveriesAreJudgedOnSafetyNotShape() {
        // Any link shape, query name or Highfly edge the paid add-on serves.
        for value in ["https://papacito.cfd/m3u/synthetic/index.m3u8?ft=synthetic-signature",
                      "https://papacito.cfd/m3u/synthetic/index.m3u8?token=synthetic-new-signature",
                      "https://testleaf.papacito.cfd/m3u/a/index.m3u8?ft=x&token=y",
                      "https://edge.example.net/live/stream.m3u8", "https://cdn.example.org/hls/master?sig=abc"] {
            XCTAssertNil(HighflySportsAddonClient.deliveryRejection(URL(string: value)!), value)
        }
        XCTAssertEqual(HighflySportsAddonClient.stableChoiceKey(URL(string: "https://papacito.cfd/m3u/s/i.m3u8?ft=a")!),
                       HighflySportsAddonClient.stableChoiceKey(URL(string: "https://papacito.cfd/m3u/s/i.m3u8?token=b")!))
        // Safety still refuses: plain HTTP, odd ports, private/IP hosts, sign-in in the link, replays.
        let refused: [(String, String)] = [
            ("http://papacito.cfd/m3u/a/index.m3u8?ft=x", "not_https"),
            ("https://papacito.cfd:8443/m3u/a/index.m3u8?ft=x", "unsafe_destination"),
            ("https://127.0.0.1/m3u/a/index.m3u8?ft=x", "unsafe_destination"),
            ("https://192.168.1.10/live.m3u8", "unsafe_destination"),
            ("https://router.local/live.m3u8", "unsafe_destination"),
            ("https://user:secret@papacito.cfd/live.m3u8", "credentials_in_link"),
            ("https://recaps.highfly.to/game/full.m3u8", "replay"),
            ("https://cdn.example.org/game/full.mp4", "not_live_media"),
            ("https://cdn.example.org/watch.html", "not_live_media")]
        for (value, reason) in refused {
            XCTAssertEqual(HighflySportsAddonClient.deliveryRejection(URL(string: value)!), reason, value)
        }
    }

    func testUnknownRowFieldsAreIgnoredButCredentialsAndDRMAreNot() throws {
        func decode(_ json: String) throws -> HighflySportsAddonClient.Delivery {
            try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(json.utf8))
        }
        let plain = try decode(#"{"url":"https://example.com/a","name":"HD","behaviorHints":{"notWebReady":true,"bingeGroup":"x"},"extra":1}"#)
        XCTAssertEqual(plain.url, "https://example.com/a")
        XCTAssertFalse(plain.requiresDRM)
        XCTAssertEqual(StreamDeliveryPolicy.requestHeaders(plain.requestedHeaders), [:])
        let referer = try decode(#"{"url":"https://example.com/a","behaviorHints":{"proxyHeaders":{"request":{"referer":"https://site.example/","X-Thing":"1"}}}}"#)
        XCTAssertEqual(StreamDeliveryPolicy.requestHeaders(referer.requestedHeaders), ["Referer": "https://site.example/"])
        let credential = try decode(#"{"url":"https://example.com/a","headers":{"Authorization":"synthetic"}}"#)
        XCTAssertNil(StreamDeliveryPolicy.requestHeaders(credential.requestedHeaders), "Sign-in material is never forwarded")
        XCTAssertTrue(try decode(#"{"url":"https://example.com/a","drm":"clearkey"}"#).requiresDRM)
        XCTAssertNil(try decode(#"{"externalUrl":"https://example.com/a"}"#).url)
    }

    func testCodesNormalizeOnlyForTheirOwnProvider() throws {
        let code = "00000000-0000-0000-0000-000000000000"
        XCTAssertEqual(try AccountSourceSetup.highfly.validatedLink(code).host, "premium.highfly.to")
        XCTAssertEqual(try AccountSourceSetup.highfly.validatedLink(code + ".0000000000000000").host, "sports.highfly.to")
        XCTAssertThrowsError(try AccountSourceSetup.highfly.validatedLink("https://pengu.uk/" + code + "/manifest.json"))
        XCTAssertThrowsError(try AccountSourceSetup.highfly.validatedLink("https://premium.highfly.to.evil.example/manifest.json"))
    }

    func testFreeAndPremiumResolveThroughSameIDMetadataAndGuardedRelay() async throws {
        for premium in [false, true] {
            let transport = HighflyTestTransport(premium: premium)
            let sessions = try await client(transport).resolve(for: request(), now: kickoff)
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions.first?.providerName, "HF1")
            XCTAssertEqual(sessions.first?.eventBinding?.resourceType, "sport")
            XCTAssertTrue(sessions.first?.requiresGuardedRelay == true)
            XCTAssertTrue(sessions.first?.canRefresh == true)
            XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(sessions[0]))
            let counts = await transport.counts()
            XCTAssertEqual(counts.meta, 1); XCTAssertEqual(counts.stream, 1)
        }
    }

    func testSearchHitSkipsThePlainListing() async throws {
        let transport = HighflyTestTransport()
        _ = try await client(transport).resolve(for: request(), now: kickoff)
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.allSatisfy { $0.contains("search=") }, "\(paths)")
    }

    func testSearchMissFindsTodaysGameInThePlainListing() async throws {
        let transport = HighflyTestTransport(mode: .searchOmitsLive)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.contains("sports_football.json"), "\(paths)")
    }

    func testGameInProgressIsFoundInTheLiveCatalog() async throws {
        let transport = HighflyTestTransport(mode: .liveCatalogOnly)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff.addingTimeInterval(600))
        XCTAssertEqual(sessions.count, 1)
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.contains("sports_live.json"), "\(paths)")
        let receipt = FottyQualityStore.shared.records().last { $0.name == "highfly_lookup" }
        XCTAssertEqual(receipt?.details["live_row_shape"], "parsed")
        XCTAssertEqual(receipt?.details["live_sport_rows"], "1")
        XCTAssertEqual(receipt?.details["live_categories"], "football")
        XCTAssertEqual(receipt?.details["live_rest_shape"], "parsed")
    }

    func testUndatedLiveRowMatchesOnlyWhileTheOfficialGameIsLive() async throws {
        let transport = HighflyTestTransport(mode: .undatedLiveRow)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff.addingTimeInterval(45 * 60))
        XCTAssertEqual(sessions.count, 1)
        for outside in [kickoff.addingTimeInterval(-60 * 60), kickoff.addingTimeInterval(3 * 3600)] {
            let early = HighflyTestTransport(mode: .undatedLiveRow)
            do { _ = try await client(early).resolve(for: request(), now: outside); XCTFail("Undated live row admitted outside the live window") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            let counts = await early.counts()
            XCTAssertEqual(counts.stream, 0)
        }
    }

    func testSecondLiveCatalogStartsAtItsOwnFirstPage() async throws {
        let transport = HighflyTestTransport(mode: .secondLiveCatalog)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff.addingTimeInterval(30 * 60))
        XCTAssertEqual(sessions.count, 1)
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.contains("sports_live_extra.json"), "\(paths)")
        XCTAssertFalse(paths.contains { $0.hasPrefix("skip=") && $0.contains("extra") }, "\(paths)")
    }

    func testListingFailureCannotDiscardALiveMatch() async throws {
        let transport = HighflyTestTransport(mode: .listingFailsAfterLive)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff.addingTimeInterval(30 * 60))
        XCTAssertEqual(sessions.count, 1)
        let paths = await transport.catalogs()
        XCTAssertFalse(paths.contains("sports_football.json"), "A live match skips the upcoming listing: \(paths)")
    }

    func testLiveCatalogFailureStillReadsTheListing() async throws {
        let transport = HighflyTestTransport(mode: .liveFailsListingMatches)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        let receipt = FottyQualityStore.shared.records().last { $0.name == "highfly_lookup" }
        XCTAssertEqual(receipt?.details["supplementary_failures"], "1")
    }

    func testOwnerStatusSummarisesOfferedAndUsedStreams() {
        func receipt(_ name: String, offered: Int, used: Int, reason: String?, build: String = "900") -> FottyQualityRecord {
            var details = ["addon_stream_entry_count": "\(offered)", "candidate_count": "\(used)"]
            if let reason { details["reason_code"] = reason }
            return FottyQualityRecord(id: UUID(), timestamp: Date(), category: .playback, name: name, outcome: .info,
                                      durationMilliseconds: nil, details: details, appVersion: "3.0.0", appBuild: build)
        }
        let rows = AccountSourceAdmissionSummary.rows(records: [
            receipt("highfly_delivery_admission", offered: 7, used: 5, reason: "replay"),
            receipt("highfly_delivery_admission", offered: 7, used: 5, reason: "replay"),
            receipt("highfly_delivery_admission", offered: 9, used: 1, reason: "host", build: "899"),
            receipt("penguplay_delivery_admission", offered: 2, used: 2, reason: nil)], build: "900")
        XCTAssertEqual(rows.map(\.name), ["Highfly", "PenguPlay"])
        XCTAssertEqual(rows[0].offered, 14); XCTAssertEqual(rows[0].used, 10)
        XCTAssertEqual(AccountSourceAdmissionSummary.label(rows[0].commonestReason ?? ""), "Replays, not live")
        XCTAssertNil(rows[1].commonestReason, "Nothing unused, nothing to explain")
    }

    func testEveryListingOfTheGameContributesStreams() async throws {
        let transport = HighflyTestTransport(mode: .twoListings)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        // Feed A: 1 stream. Feed B: 10 more plus one duplicate of feed A's.
        XCTAssertEqual(sessions.count, 11, "Two listings of one game are not a conflict, and no cap of 8 applies")
        XCTAssertEqual(Set(sessions.map(\.playableURL)).count, 11, "Duplicates across listings appear once")
        XCTAssertEqual(Set(sessions.compactMap { $0.eventBinding?.providerEventID }),
                       ["streamed:synthetic", "streamed:synthetic-feed-b"])
        let counts = await transport.counts()
        XCTAssertEqual(counts.stream, 2)
        let receipt = FottyQualityStore.shared.records().last { $0.name == "highfly_delivery_admission" }
        XCTAssertEqual(receipt?.details["listing_count"], "2")
        XCTAssertEqual(receipt?.details["used_count"], "11")
        XCTAssertEqual(receipt?.details["candidate_count"], "11")
    }

    func testSecondTeamSearchFailureKeepsTheFirstTeamsMatch() async throws {
        let transport = HighflyTestTransport(mode: .secondSearchFails)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1, "Arsenal's search found the game; Everton's failing search must not discard it")
        let receipt = FottyQualityStore.shared.records().last { $0.name == "highfly_lookup" }
        XCTAssertEqual(receipt?.details["supplementary_failures"], "1")
    }

    func testRowsInAnUnfamiliarLayoutStillMatchTheRightGame() async throws {
        let transport = HighflyTestTransport(mode: .looseRows)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.eventBinding?.providerEventID, "match:arsenal-everton-2026")
    }

    func testFailedDetailsReadFallsBackToTheMatchedRow() async throws {
        let transport = HighflyTestTransport(mode: .metaFails)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 1); XCTAssertEqual(counts.stream, 1)
    }

    func testRenamedManifestWithPlainResourcesStillWorks() async throws {
        let transport = HighflyTestTransport(mode: .looseManifest)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
    }

    func testBlankCategoryLiveRowUsesTheRequestedSportOnly() {
        let id = ReviewedSportsFixtureMatcher.RequestIdentity(sport: "football", pair: ["arsenal", "everton"], kickoff: kickoff)
        let live = HighflySportsAddonClient.liveKickoff(for: id, now: kickoff.addingTimeInterval(600))
        let blank = HighflySportsAddonClient.Row(id: "streamed:b", name: "Arsenal vs Everton",
            description: "Arsenal vs Everton\nLIVE", releaseInfo: "LIVE", category: "")
        XCTAssertEqual(HighflySportsAddonClient.identity(blank, liveKickoff: live, fallbackSport: "football")?.sport, "football")
        XCTAssertNil(HighflySportsAddonClient.identity(blank, liveKickoff: live), "No requested sport, no guess")
        let tennis = HighflySportsAddonClient.Row(id: "streamed:t", name: "Arsenal vs Everton",
            description: "Arsenal vs Everton\nLIVE", releaseInfo: "LIVE", category: "tennis")
        XCTAssertNil(HighflySportsAddonClient.identity(tennis, liveKickoff: live, fallbackSport: "football"),
                     "A stated different sport is never overridden")
    }

    func testUndatedLiveRowNeverStandsInForADifferentPairOrCricket() {
        let id = ReviewedSportsFixtureMatcher.RequestIdentity(sport: "football", pair: ["arsenal", "everton"], kickoff: kickoff)
        let live = HighflySportsAddonClient.liveKickoff(for: id, now: kickoff.addingTimeInterval(600))
        XCTAssertNotNil(live)
        let other = HighflySportsAddonClient.Row(id: "streamed:o", name: "Arsenal vs Chelsea", description: "Arsenal vs Chelsea\nLIVE",
                                                 releaseInfo: "LIVE", category: "football")
        XCTAssertNotEqual(HighflySportsAddonClient.identity(other, liveKickoff: live)?.pair, id.pair)
        let cricket = ReviewedSportsFixtureMatcher.RequestIdentity(sport: "cricket", pair: ["a", "b"], kickoff: kickoff)
        XCTAssertNil(HighflySportsAddonClient.liveKickoff(for: cricket, now: kickoff.addingTimeInterval(600)))
    }

    func testLiveRowRejectionNamesTheRuleNotTheTitle() {
        XCTAssertNil(HighflySportsAddonClient.identityRejection(row()))
        let undated = HighflySportsAddonClient.Row(id: "streamed:x", name: "Arsenal vs Everton", description: "Arsenal vs Everton",
                                                   releaseInfo: "LIVE", category: "football")
        XCTAssertEqual(HighflySportsAddonClient.identityRejection(undated), "live_without_window",
                       "A live row with no official live window is not guessed into a kickoff")
    }

    func testLiveLayoutNamesLineKindsNotText() {
        let live = HighflySportsAddonClient.Row(id: "streamed:x", name: "Arsenal vs Everton",
            description: "Arsenal vs Everton\nPremier League\n10 Nov 2026 · 18:00 UTC", releaseInfo: "LIVE", category: "football")
        XCTAssertEqual(HighflySportsAddonClient.layoutSummary([live]), "name.text.date-ri_live")
    }

    func testLiveCategorySummaryKeepsOnlyCategoryWords() {
        let rows = ["Soccer", "Soccer", "Live Now", "", "F1 🏎️"].map {
            HighflySportsAddonClient.Row(id: "streamed:x", name: "Secret Title", description: "", releaseInfo: "", category: $0)
        }
        XCTAssertEqual(HighflySportsAddonClient.categorySummary(rows), "soccer.blank.f1-.live-now")
    }

    func testPlainListingStillRequiresTheExactKickoff() async throws {
        let transport = HighflyTestTransport(mode: .listingOmitsLive)
        do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("A later meeting was admitted") }
        catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 0); XCTAssertEqual(counts.stream, 0)
        let paths = await transport.catalogs()
        XCTAssertEqual(paths.filter { !$0.contains("search=") }, ["sports_live.json", "sports_football.json"])
        let receipt = FottyQualityStore.shared.records().last { $0.name == "highfly_lookup" }
        XCTAssertEqual(receipt?.details["listing_span_h"], "96_96")
        XCTAssertEqual(receipt?.details["live_catalog"], "present")
    }

    func testSameSlotPairsNameHighflysTeamsForAliasWork() {
        let id = ReviewedSportsFixtureMatcher.RequestIdentity(sport: "football", pair: ["arsenal", "everton"], kickoff: kickoff)
        let rows = [row(id: "streamed:a", name: "Arsenal FC vs Everton FC"),
                    row(id: "streamed:b", name: "Chelsea vs Fulham", date: "10 Nov 2026 · 18:10 UTC"),
                    row(id: "streamed:c", name: "Leeds vs Spurs", date: "10 Nov 2026 · 19:00 UTC")]
        let parsed = rows.map { HighflySportsAddonClient.identity($0, fallbackSport: "football") }
        let pairs = ReviewedSportsFixtureMatcher.sameSlotPairs(for: id, parsed: parsed)
        XCTAssertFalse(pairs.contains { $0.contains("leeds") }, "An hour later is a different slot")
        XCTAssertTrue(pairs.contains { $0.contains("chelsea") && $0.contains(" v ") }, "\(pairs)")
        XCTAssertTrue(pairs.allSatisfy { $0.count <= 64 })
    }

    func testOwnerAccountSourceLeadsAutomaticChoice() {
        let names = ["AS1", "CS1", "Score808", "HF2", "LS1", "HF1"]
        let sources = names.map {
            StreamSession(matchID: "account-order", playableURL: URL(string: "https://example.invalid/\($0).m3u8")!,
                          streamType: .hls, providerName: $0).legacySource
        }
        let ranked = LiveSourceHealthStore.ranked(sources)
        XCTAssertEqual(ranked.prefix(2).map(\.provider), ["HF1", "HF2"], "The owner's paid source is the first choice")
        XCTAssertEqual(Set(ranked.dropFirst(2).map(\.provider)), ["AS1", "CS1", "Score808", "LS1"])
    }

    func testConflictingMetaNeverRequestsStream() async throws {
        let transport = HighflyTestTransport(mode: .conflictingMeta)
        do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("Conflict admitted") }
        catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        let counts = await transport.counts()
        XCTAssertEqual(counts.stream, 0)
    }

    func testOptOutAndChangedAccountDiscardInFlightResult() async throws {
        for mode in [HighflyTestTransport.Mode.disable, .changeAccount] {
            let transport = HighflyTestTransport(mode: mode)
            do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("Stale account admitted") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        }
    }

    func testOneRejectedDestinationDoesNotRemoveValidSibling() async throws {
        let transport = HighflyTestTransport(mode: .badSibling)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertFalse(sessions[0].playableURL.path.contains("rejected"))
    }

    func testTransportErrorsDoNotExposeConfiguredURL() async throws {
        let transport = HighflyTestTransport(mode: .transportError)
        do { _ = try await client(transport).resolve(for: request(), now: kickoff); XCTFail("Unexpected success") }
        catch { XCTAssertFalse(error.localizedDescription.contains("synthetic-account")) }
    }

    private func client(_ transport: HighflyTestTransport) -> HighflySportsAddonClient {
        HighflySportsAddonClient(configuration: { await transport.configuration() }, fetch: { try await transport.fetch($0) },
            enabled: { await transport.enabled() }, current: { $0 }, validate: { url in
                if url.path.contains("rejected") { throw CommunitySportsAddonError.unsafeResponse }
            })
    }
}

private actor HighflyTestTransport {
    enum Mode: Sendable { case normal, conflictingMeta, disable, changeAccount, badSibling, transportError, searchOmitsLive, listingOmitsLive, liveCatalogOnly, undatedLiveRow, secondLiveCatalog, listingFailsAfterLive, liveFailsListingMatches, secondSearchFails, looseRows, metaFails, looseManifest, twoListings }
    private let premium: Bool
    private let mode: Mode
    private var streamCount = 0
    private var metaCount = 0
    private var catalogPaths: [String] = []
    init(premium: Bool = false, mode: Mode = .normal) { self.premium = premium; self.mode = mode }
    func configuration() -> URL? {
        URL(string: "https://\(premium ? "premium" : "sports").highfly.to/\(mode == .changeAccount && streamCount > 0 ? "changed" : "synthetic-account")/manifest.json")!
    }
    func enabled() -> Bool { !(mode == .disable && streamCount > 0) }
    func counts() -> (meta: Int, stream: Int) { (metaCount, streamCount) }
    func catalogs() -> [String] { catalogPaths }
    func fetch(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        if mode == .transportError { throw NSError(domain: url.absoluteString, code: 1) }
        let row: [String: Any] = ["id": "streamed:synthetic", "type": "sport", "name": "Arsenal vs Everton",
            "description": "Arsenal vs Everton\n10 Nov 2026 · 18:00 UTC", "releaseInfo": "10 Nov 2026 · 18:00 UTC", "category": "football"]
        let body: [String: Any]
        func unavailable() -> (Data, HTTPURLResponse) {
            (Data("busy".utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"])!)
        }
        if mode == .secondSearchFails, url.absoluteString.contains("search=Everton") { return unavailable() }
        if mode == .metaFails, url.path.contains("/meta/") { metaCount += 1; return unavailable() }
        if mode == .looseManifest || mode == .looseRows, url.lastPathComponent == "manifest.json" {
            body = ["id": "highfly.renamed", "version": "2.0", "resources": ["catalog", "meta", "stream"].map { ["name": $0, "types": ["sport"]] },
                    "catalogs": [["id": "sports_football", "type": "sport", "name": "Football", "extra": ["genre"]]],
                    "behaviorHints": ["configurable": true]]
            return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
        }
        if mode == .looseRows, url.path.contains("/catalog/") || url.path.contains("/meta/") {
            // A new id scheme, three description lines with the date last, extra fields.
            let loose: [String: Any] = ["id": "match:arsenal-everton-2026", "type": "sport", "name": "Arsenal vs Everton",
                "description": "Arsenal vs Everton\nPremier League\n10 Nov 2026 · 18:00 UTC", "releaseInfo": "Matchday 11",
                "category": "football", "poster": "https://example.invalid/p.png", "links": []]
            if url.path.contains("/meta/") { metaCount += 1; body = ["meta": loose] }
            else { catalogPaths.append(url.lastPathComponent); body = ["metas": url.absoluteString.contains("skip=") ? [] : [loose]] }
            return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
        }
        if url.lastPathComponent == "manifest.json" {
            body = ["id": premium ? "community.sports.streamed.premium" : "community.sports.fly", "version": "1.3.0",
                "resources": ["catalog", "meta", "stream"].map { ["name": $0, "types": ["sport"], "idPrefixes": ["streamed:"]] },
                "catalogs": [["id": "sports_football", "type": "sport"], ["id": "sports_live", "type": "sport"]]
                    + (mode == .secondLiveCatalog ? [["id": "sports_live_extra", "type": "sport"]] : [])]
        } else if url.path.contains("/catalog/") {
            catalogPaths.append(url.lastPathComponent)
            var later = row
            later["id"] = "streamed:later"
            later["description"] = "Arsenal vs Everton\n14 Nov 2026 · 18:00 UTC"; later["releaseInfo"] = "14 Nov 2026 · 18:00 UTC"
            let searching = url.absoluteString.contains("search=")
            switch mode {
            case .twoListings:
                var second = row; second["id"] = "streamed:synthetic-feed-b"
                body = ["metas": url.absoluteString.contains("skip=") || !searching ? [] : [row, second]]
            case .secondLiveCatalog:
                // 100 unrelated rows then a short page in the first live
                // catalog; the match is on the second catalog's first page.
                let path = url.path
                if path.hasSuffix("/sports_live.json") {
                    body = ["metas": (0..<100).map { i -> [String: Any] in
                        var other = later; other["id"] = "streamed:filler\(i)"; return other }]
                } else if path.contains("/sports_live/skip=") {
                    body = ["metas": []]
                } else if path.hasSuffix("/sports_live_extra.json") {
                    var live = row
                    live["description"] = "Arsenal vs Everton\n🔴 Live now"; live["releaseInfo"] = "LIVE"
                    body = ["metas": [live]]
                } else {
                    body = ["metas": url.absoluteString.contains("skip=") ? [] : [later]]
                }
            case .liveFailsListingMatches:
                if url.lastPathComponent == "sports_live.json" {
                    return (Data("busy".utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/plain"])!)
                }
                body = ["metas": url.absoluteString.contains("skip=") ? [] : searching ? [later] : [later, row]]
            case .listingFailsAfterLive:
                if url.lastPathComponent == "sports_football.json" || url.path.contains("/sports_football/skip=") {
                    return (Data("busy".utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/plain"])!)
                }
                var live = row
                live["description"] = "Arsenal vs Everton\n🔴 Live now"; live["releaseInfo"] = "LIVE"
                body = ["metas": url.lastPathComponent == "sports_live.json" ? [live] : url.absoluteString.contains("skip=") ? [] : [later]]
            case .undatedLiveRow:
                var live = row
                live["description"] = "Arsenal vs Everton\n🔴 Live now"; live["releaseInfo"] = "LIVE"
                body = ["metas": url.lastPathComponent == "sports_live.json" ? [live] : url.absoluteString.contains("skip=") ? [] : [later]]
            case .liveCatalogOnly: body = ["metas": url.lastPathComponent == "sports_live.json" ? [row] : url.absoluteString.contains("skip=") ? [] : [later]]
            case .searchOmitsLive: body = ["metas": url.absoluteString.contains("skip=") || url.path.contains("sports_live") ? []
                : searching ? [later] : [later, row]]
            case .listingOmitsLive: body = ["metas": url.absoluteString.contains("skip=") ? [] : [later]]
            default: body = ["metas": url.absoluteString.contains("skip=") || !searching ? [] : [row]]
            }
        } else if url.path.contains("/meta/") {
            metaCount += 1
            var meta = row
            if [.undatedLiveRow, .secondLiveCatalog, .listingFailsAfterLive].contains(mode) { meta["description"] = "Arsenal vs Everton\n🔴 Live now"; meta["releaseInfo"] = "LIVE" }
            if mode == .conflictingMeta { meta["name"] = "Different fixture" }
            if mode == .twoListings, url.path.contains("feed-b") { meta["id"] = "streamed:synthetic-feed-b" }
            body = ["meta": meta]
        } else {
            streamCount += 1
            let key = premium ? "token" : "ft"
            var deliveries: [[String: Any]] = [["url": "https://sports.highfly.to/tip.m3u8"],
                ["url": "https://papacito.cfd/m3u/synthetic/index.m3u8?\(key)=synthetic", "behaviorHints": ["notWebReady": true]]]
            if mode == .twoListings, url.path.contains("feed-b") {
                deliveries = (1...10).map { ["url": "https://edge\($0).papacito.cfd/m3u/b\($0)/index.m3u8?\(key)=s"] }
                deliveries.append(["url": "https://papacito.cfd/m3u/synthetic/index.m3u8?\(key)=synthetic"])
            }
            if mode == .badSibling { deliveries.insert(["url": "https://papacito.cfd/m3u/rejected/index.m3u8?\(key)=synthetic"], at: 0) }
            body = ["streams": deliveries]
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
