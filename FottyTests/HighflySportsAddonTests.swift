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

    func testCatalogNameCannotContradictDescriptionParticipants() throws {
        let good = row()
        let conflicting = HighflySportsAddonClient.Row(id: good.id, name: "Chelsea vs Fulham",
            description: good.description, releaseInfo: good.releaseInfo, category: good.category)
        XCTAssertNotNil(ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: conflicting.name),
                        "The contradictory name explicitly identifies another pair")
        XCTAssertTrue(HighflySportsAddonClient.selectAll(request: request(), rows: [conflicting], now: kickoff).isEmpty,
                      "A matching description must not hide a different explicit pair in the catalog name")
        XCTAssertTrue(HighflySportsAddonClient.selectAll(request: request(), rows: [good, conflicting], now: kickoff).isEmpty,
                      "A same-ID sibling must retain the contradictory catalog evidence")
        for name in ["Premier League", "Live football", "", "Everton vs Arsenal"] {
            let generic = HighflySportsAddonClient.Row(id: good.id, name: name, description: good.description,
                releaseInfo: good.releaseInfo, category: good.category)
            XCTAssertEqual(HighflySportsAddonClient.selectAll(request: request(), rows: [generic], now: kickoff), [generic],
                           "A generic or missing name supplies no contradictory participant identity")
        }
    }

    func testCatalogNamesPreserveAliasesAndIndependentSquadEvidence() throws {
        let date = "10 Nov 2026 · 18:00 UTC"
        func listing(_ name: String, _ description: String) -> HighflySportsAddonClient.Row {
            .init(id: "streamed:synthetic", name: name, description: description + "\n" + date,
                  releaseInfo: date, category: "football")
        }
        XCTAssertNil(HighflySportsAddonClient.identity(listing("Arsenal vs Everton", "Live football")),
                     "A generic primary description must not acquire a new name-only fallback")
        let national = StreamPlaybackRequest(matchID: "national", displayTitle: "Turkey vs Georgia", homeTeam: "Turkey",
            awayTeam: "Georgia", category: "football", kickoffDate: kickoff)
        let alias = listing("Georgia vs Türkiye", "Turkey vs Georgia")
        XCTAssertEqual(HighflySportsAddonClient.selectAll(request: national, rows: [alias], now: kickoff), [alias])
        let women = StreamPlaybackRequest(matchID: "women", displayTitle: "Arsenal Women vs Everton Women",
            homeTeam: "Arsenal Women", awayTeam: "Everton Women", category: "football", kickoffDate: kickoff)
        for (name, description) in [("Arsenal Women vs Everton Women", "Arsenal vs Everton"),
                                    ("Arsenal vs Everton", "Everton Women vs Arsenal Women")] {
            let item = listing(name, description)
            XCTAssertEqual(HighflySportsAddonClient.selectAll(request: women, rows: [item], now: kickoff), [item])
            XCTAssertTrue(HighflySportsAddonClient.selectAll(request: request(), rows: [item], now: kickoff).isEmpty)
        }
        for (name, description) in [("Arsenal Women vs Everton Women", "Arsenal U21 vs Everton U21"),
                                    ("Arsenal U21 vs Everton U21", "Arsenal Women vs Everton Women")] {
            XCTAssertTrue(HighflySportsAddonClient.selectAll(request: women, rows: [listing(name, description)], now: kickoff).isEmpty)
        }
    }

    func testConflictingMetaDescriptionCannotDiscardACleanListingSibling() async throws {
        let transport = HighflyTestTransport(mode: .internalMetaConflictWithSibling)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.eventBinding?.providerEventID, "streamed:synthetic-feed-b")
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 2, "Both same-ID metadata rereads must be checked independently")
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
        // Safety still refuses: plain HTTP, odd ports, private/IP hosts, sign-in in the link.
        let refused: [(String, String)] = [
            ("http://papacito.cfd/m3u/a/index.m3u8?ft=x", "not_https"),
            ("https://papacito.cfd:8443/m3u/a/index.m3u8?ft=x", "unsafe_destination"),
            ("https://127.0.0.1/m3u/a/index.m3u8?ft=x", "unsafe_destination"),
            ("https://192.168.1.10/live.m3u8", "unsafe_destination"),
            ("https://router.local/live.m3u8", "unsafe_destination"),
            ("https://user:secret@papacito.cfd/live.m3u8", "credentials_in_link")]
        for (value, reason) in refused {
            XCTAssertEqual(HighflySportsAddonClient.deliveryRejection(URL(string: value)!), reason, value)
        }
    }

    func testQuerySelectedSiblingCannotReplaceTheChosenHighflyDeliveryDuringRenewal() async throws {
        let transport = HighflyTestTransport(mode: .querySelectedChannels)
        let resolver = client(transport)
        let original = try await resolver.resolve(for: request(), now: kickoff)
        XCTAssertEqual(original.map(\.providerName), ["HF1", "HF2"])
        XCTAssertEqual(original.map { $0.playableURL.query }, ["channel=one&ft=original", "channel=two&ft=original"],
                       "Initial admission must preserve both full query-selected deliveries")
        let first = try XCTUnwrap(original.first), second = try XCTUnwrap(original.last)
        XCTAssertEqual(first.diagnosticMetadata["source_key"], second.diagnosticMetadata["source_key"],
                       "Historical ranking keys remain unchanged")
        XCTAssertNotEqual(HighflySportsAddonClient.descriptorChoiceKey(first.playableURL, headers: first.requiredHeaders),
                          HighflySportsAddonClient.descriptorChoiceKey(second.playableURL, headers: second.requiredHeaders))

        // Only the other channel survives. Its display ordinal changes, while
        // listing, path and endpoint remain the same as the selected delivery.
        let refreshed = try await resolver.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(refreshed.count, 1)
        let sibling = try XCTUnwrap(refreshed.first)
        XCTAssertEqual(sibling.providerName, "HF1")
        XCTAssertEqual(sibling.playableURL.query, "channel=two&token=renewed")
        XCTAssertEqual(sibling.eventBinding?.providerEventID, first.eventBinding?.providerEventID)
        XCTAssertEqual(sibling.eventBinding?.streamID, first.eventBinding?.streamID)
        XCTAssertEqual(sibling.playableURL.path, first.playableURL.path)
        XCTAssertFalse(LiveStreamResolver.isSameDescriptorChoice(sibling, as: first),
                       "One surviving sibling must not pass unique-candidate renewal for another channel")
        XCTAssertTrue(LiveStreamResolver.isSameDescriptorChoice(sibling, as: second),
                      "The same channel still renews across reviewed credential rotation and display renumbering")
    }

    func testDescriptorChoiceKeyRotatesOnlyReviewedCredentialsAndRetainsRawSelectors() throws {
        func key(_ value: String, headers: [String: String] = [:]) throws -> String {
            HighflySportsAddonClient.descriptorChoiceKey(try XCTUnwrap(URL(string: value)), headers: headers)
        }
        for origin in ["https://papacito.cfd", "https://edge.papacito.cfd", "https://papacito.cfd:443"] {
            let base = origin + "/m3u/channel/index.m3u8"
            XCTAssertEqual(try key(base + "?ft=old"), try key(base + "?token=new"))
            XCTAssertEqual(try key(base + "?channel=one&ft=old"), try key(base + "?channel=one&token=new"))
        }
        for base in ["https://other.example/m3u/channel/index.m3u8", "https://evilpapacito.cfd/m3u/channel/index.m3u8",
                     "https://papacito.cfd.evil.example/m3u/channel/index.m3u8", "http://papacito.cfd/m3u/channel/index.m3u8",
                     "https://papacito.cfd:8443/m3u/channel/index.m3u8", "https://papacito.cfd/other/index.m3u8",
                     "https://papacito.cfd/m3u/channel/index%2Em3u8", "https://papacito.cfd/m3u/channel/index.m3u%38"] {
            XCTAssertNotEqual(try key(base + "?ft=old"), try key(base + "?token=new"), base)
        }
        let base = "https://papacito.cfd/m3u/channel/index.m3u8?"
        for (left, right) in [
            ("channel=one&ft=old", "channel=two&token=new"),
            ("source=one&ft=old", "source=two&token=new"),
            ("unknown=one&ft=old", "unknown=two&token=new"),
            ("Channel=one&ft=old", "channel=one&token=new"),
            ("%63hannel=one&ft=old", "channel=one&token=new"),
            ("channel=%6Fne&ft=old", "channel=one&token=new"),
            ("a=one&b=two&ft=old", "b=two&a=one&token=new"),
            ("channel=one&channel=two&ft=old", "channel=two&channel=one&token=new"),
            ("FT=old", "FT=new"), ("%66t=old", "%66t=new"),
            ("ft=old&ft=other", "ft=new&ft=other"),
            ("token=old&token=other", "token=new&token=other"),
            ("ft=old&token=other", "ft=new&token=other"), ("ft=", "token=")
        ] { XCTAssertNotEqual(try key(base + left), try key(base + right), left + " / " + right) }
        XCTAssertNotEqual(try key(base + "ft=old", headers: ["User-Agent": "Player A"]),
                          try key(base + "token=new", headers: ["User-Agent": "Player B"]))
    }

    func testUnknownRowFieldsAreIgnoredButCredentialsAndDRMAreNot() throws {
        func decode(_ json: String) throws -> HighflySportsAddonClient.Delivery {
            try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(json.utf8))
        }
        let plain = try decode(#"{"url":"https://example.com/a","name":"HD","behaviorHints":{"notWebReady":true,"bingeGroup":"x"},"extra":1}"#)
        XCTAssertEqual(plain.url, "https://example.com/a")
        XCTAssertFalse(plain.requiresDRM)
        XCTAssertEqual(plain.requestedHeaders.flatMap(StreamDeliveryPolicy.requestHeaders), [:])
        let referer = try decode(#"{"url":"https://example.com/a","behaviorHints":{"proxyHeaders":{"request":{"referer":"https://site.example/","X-Thing":"1"}}}}"#)
        XCTAssertEqual(referer.requestedHeaders.flatMap(StreamDeliveryPolicy.requestHeaders), ["Referer": "https://site.example/"])
        let credential = try decode(#"{"url":"https://example.com/a","headers":{"Authorization":"synthetic"}}"#)
        XCTAssertNil(credential.requestedHeaders.flatMap(StreamDeliveryPolicy.requestHeaders), "Sign-in material is never forwarded")
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
            XCTAssertEqual(sessions.first?.diagnosticMetadata["delivery_host"], "papacito.cfd")
            XCTAssertFalse(sessions.first?.diagnosticMetadata.values.contains { $0.contains("synthetic") || $0.contains("/") } ?? true)
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

    func testSecondTeamSearchTimeoutPreservesFirstTeamsExactMatch() async throws {
        let transport = HighflyTestTransport(mode: .secondTeamSearchTimesOut)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["HF1"])
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.contains("search=Arsenal.json"))
        XCTAssertTrue(paths.contains("search=Everton.json"))
        XCTAssertFalse(paths.contains("sports_live.json"))
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 1)
        XCTAssertEqual(counts.stream, 1)
    }

    func testBothTeamSearchTimeoutsStillFindMatchInLiveCatalog() async throws {
        let transport = HighflyTestTransport(mode: .teamSearchesTimeOut)
        let sessions = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["HF1"])
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.contains("search=Arsenal.json"))
        XCTAssertTrue(paths.contains("search=Everton.json"))
        XCTAssertTrue(paths.contains("sports_live.json"))
        XCTAssertFalse(paths.contains("sports_football.json"))
    }

    func testCancelledTeamSearchStopsBeforeFallbackOrStreamRequest() async throws {
        let transport = HighflyTestTransport(mode: .cancelTeamSearch)
        do {
            _ = try await client(transport).resolve(for: request(), now: kickoff)
            XCTFail("Cancelled lookup returned a stream")
        } catch is CancellationError {}
        let paths = await transport.catalogs()
        XCTAssertEqual(paths, ["search=Arsenal.json"])
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 0)
        XCTAssertEqual(counts.stream, 0)
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
        let receipt = FottyQualityStore.shared.records().last { $0.name == "stream_admission" && $0.details["source_family"] == "highfly" }
        XCTAssertEqual(receipt?.details["offered_count"], "13")
        XCTAssertEqual(receipt?.details["admitted_count"], "11")
        XCTAssertEqual(receipt?.details["admission_duplicate_count"], "1")
        XCTAssertEqual(receipt?.details["admission_no_url_count"], "1")
        XCTAssertEqual(receipt?.details["admission_reconciled"], "yes")
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
            let receipt = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "stream_admission" && $0.details["source_family"] == "highfly" })
            XCTAssertGreaterThan(Int(receipt.details["offered_count"] ?? "") ?? 0, 0)
            XCTAssertEqual(receipt.details["admitted_count"], "0", "The account changed after the list was read")
        }
    }

    func testHeaderVariantsRetainDistinctRenewalKeysAndMalformedSiblingIsCounted() async throws {
        let transport = HighflyTestTransport(mode: .headerVariants)
        let result = try await client(transport).resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.map(\.requiredHeaders), [["User-Agent": "Player A"], ["User-Agent": "Player B"]])
        XCTAssertEqual(Set(result.map(\.playableURL)).count, 1)
        XCTAssertEqual(Set(result.compactMap { $0.diagnosticMetadata["source_key"] }).count, 2)
        let receipt = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "stream_admission" && $0.details["source_family"] == "highfly" })
        XCTAssertEqual(receipt.details["offered_count"], "4")
        XCTAssertEqual(receipt.details["admitted_count"], "2")
        XCTAssertEqual(receipt.details["admission_malformed_headers_count"], "1")
        XCTAssertEqual(receipt.details["admission_duplicate_count"], "1")
        XCTAssertEqual(receipt.details["admission_reconciled"], "yes")
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

    func testProviderOwnedOpaqueDeliveryIsNotGuessedToBeANotice() async throws {
        let sessions = try await client(HighflyTestTransport(mode: .ownDomain)).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.requiresGuardedRelay == true })
        XCTAssertEqual(sessions.first?.playableURL.pathExtension, "php")
        // Safe to attempt is deliberately not decoded correct-programme proof.
    }

    func testOptionalNullsAndMalformedSiblingConserveEveryReturnedEntry() async throws {
        let sessions = try await client(HighflyTestTransport(mode: .nullableMetadata)).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 2)
        let receipt = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "stream_admission" && $0.details["source_family"] == "highfly" })
        XCTAssertEqual(receipt.details["offered_count"], "4")
        XCTAssertEqual(receipt.details["admitted_count"], "2")
        XCTAssertEqual(receipt.details["admission_no_url_count"], "2")
        XCTAssertEqual(receipt.details["admission_reconciled"], "yes")
    }

    func testSharedMetadataNullTolerancePreservesRealDRMAndHeaderConflicts() throws {
        for body in [#"{"url":"https://edge.example.com/play.php","drm":null,"behaviorHints":null}"#,
                     #"{"url":"https://edge.example.com/live","drm":false,"behaviorHints":{"proxyHeaders":null}}"#] {
            let row = try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(body.utf8))
            XCTAssertFalse(row.requiresDRM); XCTAssertEqual(row.requestedHeaders, [:])
        }
        for body in [#"{"licenseUrl":"https://example.com/license"}"#, #"{"drm":{"type":"widevine"}}"#, #"{"clearkey":{"key":"synthetic"}}"#] {
            XCTAssertTrue(try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(body.utf8)).requiresDRM)
        }
        let conflict = try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(#"{"headers":{"Referer":"https://one.example/"},"behaviorHints":{"requestHeaders":{"referer":"https://two.example/"}}}"#.utf8))
        XCTAssertNil(conflict.requestedHeaders)
        XCTAssertNil(StreamDeliveryPolicy.requestHeaders(["Referer":"http://127.0.0.1/"]))
        XCTAssertEqual(StreamDeliveryPolicy.requestHeaders(["Referer":"http://public.example.com/"]), ["Referer":"http://public.example.com/"])
    }

    func testDeliveryLabelsDecodeIndependentlyWithoutChangingAdmissionInputs() throws {
        func decode(_ json: String) throws -> HighflySportsAddonClient.Delivery {
            try JSONDecoder().decode(HighflySportsAddonClient.Delivery.self, from: Data(json.utf8))
        }
        let malformedName = try decode(#"{"url":"https://edge.example.com/live","name":12,"title":"Arsenal vs Everton"}"#)
        XCTAssertNil(malformedName.name)
        XCTAssertEqual(malformedName.title, "Arsenal vs Everton")
        XCTAssertEqual(malformedName.requestedHeaders, [:])
        let malformedTitle = try decode(#"{"url":"https://edge.example.com/live","name":"Arsenal vs Everton","title":["unexpected"]}"#)
        XCTAssertEqual(malformedTitle.name, "Arsenal vs Everton")
        XCTAssertNil(malformedTitle.title)
        for json in [#"{"url":"https://edge.example.com/live"}"#,
                     #"{"url":"https://edge.example.com/live","name":null,"title":null}"#] {
            let absent = try decode(json)
            XCTAssertNil(absent.name); XCTAssertNil(absent.title)
            XCTAssertEqual(absent.url, "https://edge.example.com/live")
            XCTAssertFalse(absent.requiresDRM)
        }
    }

    func testLookupReceiptsLinkEveryListingAndKeepRepeatedLookupsSeparate() async throws {
        let transport = HighflyTestTransport(mode: .twoListings), receipts = HighflyReceiptBox()
        let generation = UUID()
        let resolver = client(transport, generation: { _ in generation }, receiptSink: receipts.append)
        let first = try await resolver.resolve(for: request(), now: kickoff)
        let second = try await resolver.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        let records = receipts.values
        XCTAssertEqual(records.count, 2)
        XCTAssertNotEqual(records[0].lookupID, records[1].lookupID)
        XCTAssertEqual(records[0].configurationGeneration, generation)
        XCTAssertEqual(records[0].fixture, records[1].fixture)
        for (sessions, record) in [(first, records[0]), (second, records[1])] {
            XCTAssertEqual(record.readResponses, 2)
            XCTAssertEqual(record.unreadResponses, 0)
            XCTAssertEqual(record.observedEntries, 13)
            XCTAssertEqual(record.uniqueObservedContracts, 11)
            XCTAssertEqual(record.admitted, 11)
            XCTAssertEqual(record.dispositions["duplicate"], 1)
            XCTAssertEqual(record.dispositions["no_url"], 1)
            XCTAssertEqual(record.deliveries.count, 13)
            XCTAssertEqual(Set(record.deliveries.map(\.listing)).count, 2)
            XCTAssertEqual(Set(record.deliveries.compactMap(\.sourceID)), Set(sessions.map(\.id)))
            XCTAssertTrue(record.deliveries.filter { $0.disposition != "admitted" }.allSatisfy { $0.sourceID == nil })
            XCTAssertTrue(record.isReconciled)
            XCTAssertFalse(record.isTruncated)
            for session in sessions {
                let provenance = try XCTUnwrap(session.deliveryProvenance)
                XCTAssertEqual(provenance.lookupID, record.lookupID)
                XCTAssertEqual(provenance.configurationGeneration, generation)
                XCTAssertNil(session.deliveryTransportContext, "Discovery does not invent a prepared cookie snapshot")
                XCTAssertTrue(record.deliveries.contains { $0.listing == provenance.listing
                    && $0.contract == provenance.contract && $0.disposition == "admitted" && $0.sourceID == session.id })
            }
        }
    }

    func testDeliveryLabelContradictionIsRecordedWithoutReorderingOrRefusingStreams() async throws {
        let receipts = HighflyReceiptBox(), transport = HighflyTestTransport(mode: .metadataLabels)
        let result = try await client(transport, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.map(\.providerName), ["HF1", "HF2", "HF3"])
        XCTAssertEqual(result.map { $0.playableURL.lastPathComponent }, ["first.m3u8", "second.m3u8", "third.m3u8"])
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.deliveries.map(\.comparison), [.agrees, .contradicts, .noParseableTeams])
        XCTAssertEqual(receipt.deliveries.map(\.hasName), [true, true, false])
        XCTAssertEqual(receipt.deliveries.map(\.hasTitle), [true, true, false])
        XCTAssertEqual(receipt.deliveries.map(\.disposition), ["admitted", "admitted", "admitted"])
        let description = String(reflecting: receipt)
        for raw in ["Arsenal", "Everton", "Chelsea", "Fulham", "private-label-sentinel",
                    "edge.example.com", "synthetic-account", "private-token-sentinel", "streamed:synthetic"] {
            XCTAssertFalse(description.contains(raw), "Raw provider values must not enter typed receipts")
        }
    }

    func testPartialUnreadResponseDoesNotBecomeAnEmptyResponseOrHideSuccessfulSiblings() async throws {
        let receipts = HighflyReceiptBox(), transport = HighflyTestTransport(mode: .partialStreams)
        let result = try await client(transport, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.map(\.providerName), ["HF1"])
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.readResponses, 1)
        XCTAssertEqual(receipt.unreadResponses, 1)
        XCTAssertEqual(receipt.knownEmptyResponses, 0)
        XCTAssertEqual(receipt.observedEntries, 2)
        XCTAssertEqual(receipt.admitted, 1)
        XCTAssertEqual(receipt.completion, "partial")
        XCTAssertTrue(receipt.isReconciled)
    }

    func testDuplicateContractContradictionCannotBeHiddenByTheFirstAdmittedLabel() async throws {
        let receipts = HighflyReceiptBox(), generation = UUID()
        let result = try await client(HighflyTestTransport(mode: .contradictoryDuplicate),
            generation: { _ in generation }, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.map(\.providerName), ["HF1"], "Diagnostic comparison does not change deduplication or ordering")
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.deliveries.map(\.comparison), [.agrees, .contradicts])
        XCTAssertEqual(receipt.deliveries.map(\.disposition), ["admitted", "duplicate"])
        let session = try XCTUnwrap(result.first), provenance = try XCTUnwrap(session.deliveryProvenance)
        XCTAssertEqual(receipt.deliveries.first?.sourceID, session.id)
        XCTAssertNil(receipt.deliveries.last?.sourceID, "A duplicate observation is not the admitted origin")
        XCTAssertEqual(LiveSourceHealthStore.programmeCorrectness(for: session, scope: provenance.scope,
            configurationGeneration: generation, attemptID: nil, expiry: .boundary(kickoff.addingTimeInterval(3600)),
            at: provenance.observedAt.addingTimeInterval(1)), .unknown,
            "A duplicate delivery's contradictory metadata must not be lost behind first-listed agreement")
    }

    func testSourceReceiptIdentifiesAdmittedEntryRatherThanEarlierRejectedSameContract() async throws {
        let receipts = HighflyReceiptBox()
        let sessions = try await client(HighflyTestTransport(mode: .rejectedThenAdmittedContract),
            receiptSink: receipts.append).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["HF1"], "Origin accounting does not change admission or source order")
        let session = try XCTUnwrap(sessions.first), receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.deliveries.map(\.index), [0, 1, 2])
        XCTAssertEqual(receipt.deliveries.map(\.disposition), ["drm", "admitted", "duplicate"])
        XCTAssertEqual(receipt.deliveries.map(\.sourceID), [nil, session.id, nil])
        let contract = try XCTUnwrap(session.deliveryProvenance?.contract)
        XCTAssertTrue(receipt.deliveries.allSatisfy { $0.contract == contract },
            "The transport contracts deliberately match; only the admitted entry may name the returned session")
        XCTAssertEqual(receipt.admitted, 1)
        XCTAssertTrue(receipt.isReconciled)
    }

    func testKnownEmptyAndUnreadStreamResponsesHaveDifferentReceipts() async throws {
        for mode in [HighflyTestTransport.Mode.emptyStreams, .streamReadFails] {
            let receipts = HighflyReceiptBox()
            do {
                _ = try await client(HighflyTestTransport(mode: mode), receiptSink: receipts.append)
                    .resolve(for: request(), now: kickoff)
                XCTFail("Empty or unavailable response cannot produce playback")
            } catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            let receipt = try XCTUnwrap(receipts.values.last)
            XCTAssertEqual(receipt.observedEntries, 0)
            XCTAssertEqual(receipt.admitted, 0)
            XCTAssertEqual(receipt.readResponses, mode == .emptyStreams ? 1 : 0)
            XCTAssertEqual(receipt.unreadResponses, mode == .emptyStreams ? 0 : 1)
            XCTAssertEqual(receipt.knownEmptyResponses, mode == .emptyStreams ? 1 : 0)
        }
    }

    func testConflictingMetadataLeavesTheStreamResponseUnreadRatherThanKnownEmpty() async throws {
        let receipts = HighflyReceiptBox(), transport = HighflyTestTransport(mode: .conflictingMeta)
        do {
            _ = try await client(transport, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
            XCTFail("A conflicting listing cannot acquire stream authority")
        } catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.readResponses, 0)
        XCTAssertEqual(receipt.unreadResponses, 1)
        XCTAssertEqual(receipt.knownEmptyResponses, 0)
        XCTAssertEqual(receipt.observedEntries, 0)
        XCTAssertTrue(receipt.deliveries.isEmpty)
        XCTAssertFalse(receipt.isReconciled, "No stream response was observed")
        let requests = await transport.counts()
        XCTAssertEqual(requests.stream, 0)
    }

    func testScanLimitAccountsForEveryObservedTailWithoutInflatingUniqueContractCoverage() async throws {
        let receipts = HighflyReceiptBox()
        let sessions = try await client(HighflyTestTransport(mode: .streamScanLimit), receiptSink: receipts.append)
            .resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 100)
        XCTAssertTrue(sessions.allSatisfy { $0.deliveryProvenance != nil },
            "Diagnostic sample limits must not erase the listing association for admitted sessions")
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.observedEntries, 130)
        XCTAssertEqual(receipt.admitted, 100)
        XCTAssertEqual(receipt.dispositions["limit"], 30)
        XCTAssertTrue(receipt.isTruncated)
        XCTAssertLessThanOrEqual(receipt.deliveries.count, 64)
        XCTAssertLessThanOrEqual(receipt.uniqueObservedContracts, 64)
        XCTAssertTrue(receipt.isReconciled)
    }

    func testChangedGenerationWithdrawsProvisionalStreamsEvenWhenTheAccountLinkIsUnchanged() async throws {
        let receipts = HighflyReceiptBox(), epochs = HighflyGenerationSequence()
        let transport = HighflyTestTransport()
        let resolver = client(transport, generation: { _ in await epochs.next() }, receiptSink: receipts.append)
        do {
            _ = try await resolver.resolve(for: request(), now: kickoff)
            XCTFail("A changed configuration generation must invalidate the old lookup")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.observedEntries, 2)
        XCTAssertEqual(receipt.admitted, 0)
        XCTAssertEqual(receipt.dispositions["withdrawn"], 1)
        XCTAssertTrue(receipt.deliveries.allSatisfy { $0.disposition != "admitted" })
        XCTAssertTrue(receipt.isReconciled)
    }

    func testLaterLivePageFailureKeepsTheExactMatchFromTheFirstPage() async throws {
        let receipts = HighflyReceiptBox(), transport = HighflyTestTransport(mode: .liveSecondPageFails)
        let sessions = try await client(transport, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["HF1"])
        let paths = await transport.catalogs()
        XCTAssertTrue(paths.contains("skip=100.json"))
        XCTAssertFalse(paths.contains("sports_football.json"), "A failed later page does not erase the earlier live match")
        let receipt = try XCTUnwrap(receipts.values.last)
        XCTAssertEqual(receipt.completion, "partial")
        XCTAssertEqual(receipt.readResponses, 1)
        XCTAssertEqual(receipt.unreadResponses, 0, "An unread catalog page is not an unread stream response")
        XCTAssertEqual(receipt.admitted, 1)
        XCTAssertTrue(receipt.isReconciled)
    }

    func testLaterBrowsePageFailureKeepsTheExactMatchFromTheFirstPage() async throws {
        let receipts = HighflyReceiptBox(), transport = HighflyTestTransport(mode: .browseSecondPageFails)
        let sessions = try await client(transport, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.map(\.providerName), ["HF1"])
        XCTAssertEqual(receipts.values.last?.completion, "partial")
        let diagnostic = try XCTUnwrap(FottyQualityStore.shared.records().last { $0.name == "highfly_lookup" })
        XCTAssertEqual(diagnostic.details["supplementary_failures"], "1")
        XCTAssertNotEqual(diagnostic.details["listing_span_h"], "empty")
    }

    func testFailedLaterPageDoesNotUndoAConflictingDuplicateVeto() async throws {
        let transport = HighflyTestTransport(mode: .liveConflictThenPageFails)
        do {
            _ = try await client(transport).resolve(for: request(), now: kickoff)
            XCTFail("Retaining partial pages must retain their same-ID conflicts too")
        } catch { XCTAssertTrue(error is CommunitySportsAddonError) }
        let counts = await transport.counts()
        XCTAssertEqual(counts.stream, 0)
    }

    func testLaterPageCancellationDoesNotStartPlaybackFromEarlierRows() async throws {
        let transport = HighflyTestTransport(mode: .liveSecondPageCancelled)
        do {
            _ = try await client(transport).resolve(for: request(), now: kickoff)
            XCTFail("Cancellation is not a supplementary page failure")
        } catch { XCTAssertTrue(error is CancellationError) }
        let counts = await transport.counts()
        XCTAssertEqual(counts.stream, 0)
    }

    func testSearchFailureWithSuccessfulFallbackStillReportsPartialCoverage() async throws {
        let receipts = HighflyReceiptBox()
        let sessions = try await client(HighflyTestTransport(mode: .teamSearchesTimeOut), receiptSink: receipts.append)
            .resolve(for: request(), now: kickoff)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(receipts.values.last?.completion, "partial")
        XCTAssertEqual(receipts.values.last?.unreadResponses, 0)
    }

    func testFailedCatalogReadsDoNotEstablishAMissingFixture() async throws {
        for mode in [HighflyTestTransport.Mode.allCatalogReadsFail, .oneCatalogReadFailsWithoutMatch] {
            let receipts = HighflyReceiptBox(), transport = HighflyTestTransport(mode: mode)
            do {
                _ = try await client(transport, receiptSink: receipts.append).resolve(for: request(), now: kickoff)
                XCTFail("An incomplete catalog lookup cannot establish that this fixture is absent")
            } catch {
                let failure = try XCTUnwrap(error as? CommunitySportsAddonError)
                XCTAssertEqual(failure, .invalidResponse)
                XCTAssertEqual(LiveStreamResolver.communitySportsFailure(from: failure).category, .manifestInvalid,
                               "An unconfirmed lookup must not withdraw prior availability as a definitive miss")
            }
            let paths = await transport.catalogs()
            XCTAssertEqual(Set(paths), Set(["search=Arsenal.json", "search=Everton.json", "sports_live.json", "sports_football.json"]))
            let counts = await transport.counts()
            XCTAssertEqual(counts.meta, 0)
            XCTAssertEqual(counts.stream, 0)
            let receipt = try XCTUnwrap(receipts.values.last)
            XCTAssertEqual(receipt.completion, "failed")
            XCTAssertEqual(receipt.readResponses, 0)
            XCTAssertEqual(receipt.unreadResponses, 0, "An unread catalog is not an unread stream response")
            XCTAssertEqual(receipt.knownEmptyResponses, 0)
            XCTAssertEqual(receipt.admitted, 0)
            XCTAssertFalse(receipt.isReconciled,
                           "No stream response was observed, so admission accounting remains unknown")
        }
    }

    func testCompletedEmptyCatalogsRemainADefinitiveFixtureMiss() async throws {
        let transport = HighflyTestTransport(mode: .catalogsEmpty)
        do {
            _ = try await client(transport).resolve(for: request(), now: kickoff)
            XCTFail("A completed empty catalog cannot produce playback")
        } catch {
            let failure = try XCTUnwrap(error as? CommunitySportsAddonError)
            XCTAssertEqual(failure, .matchNotFound)
            let result = LiveStreamResolver.communitySportsFailure(from: failure)
            XCTAssertEqual(result.category, .providerReturnedEmpty)
            XCTAssertEqual(result.redactedMetadata["manifest_result"], "no_exact_fixture_match")
        }
        let paths = await transport.catalogs()
        XCTAssertEqual(Set(paths), Set(["search=Arsenal.json", "search=Everton.json", "sports_live.json", "sports_football.json"]))
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 0)
        XCTAssertEqual(counts.stream, 0)
    }

    func testIncompleteCatalogDoesNotSoftenAnObservedIdentityConflict() async throws {
        let transport = HighflyTestTransport(mode: .liveConflictThenPageFails)
        do {
            _ = try await client(transport).resolve(for: request(), now: kickoff)
            XCTFail("An unread later page cannot restore a conflicting identity")
        } catch {
            let failure = try XCTUnwrap(error as? CommunitySportsAddonError)
            XCTAssertEqual(failure, .matchNotFound, "Preserve the existing definitive rejection of the conflicting listing")
            XCTAssertEqual(LiveStreamResolver.communitySportsFailure(from: failure).category, .providerReturnedEmpty)
        }
        let counts = await transport.counts()
        XCTAssertEqual(counts.meta, 0)
        XCTAssertEqual(counts.stream, 0)
    }

    private func client(_ transport: HighflyTestTransport,
                        generation: HighflySportsAddonClient.Generation? = nil,
                        receiptSink: HighflySportsAddonClient.ReceiptSink? = nil) -> HighflySportsAddonClient {
        HighflySportsAddonClient(configuration: { await transport.configuration() }, fetch: { try await transport.fetch($0) },
            enabled: { await transport.enabled() }, current: { $0 }, validate: { url in
                if url.path.contains("rejected") { throw CommunitySportsAddonError.unsafeResponse }
            }, generation: generation, receiptSink: receiptSink)
    }
}

private final class HighflyReceiptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ProviderLookupReceipt] = []
    func append(_ receipt: ProviderLookupReceipt) { lock.lock(); defer { lock.unlock() }; stored.append(receipt) }
    var values: [ProviderLookupReceipt] { lock.lock(); defer { lock.unlock() }; return stored }
}

private actor HighflyGenerationSequence {
    private let initial = UUID(), changed = UUID()
    private var reads = 0
    func next() -> UUID { reads += 1; return reads <= 2 ? initial : changed }
}

private actor HighflyTestTransport {
    enum Mode: Sendable {
        case ownDomain, nullableMetadata, normal, conflictingMeta, disable, changeAccount, badSibling, transportError, headerVariants
        case searchOmitsLive, listingOmitsLive, liveCatalogOnly, undatedLiveRow, secondLiveCatalog
        case listingFailsAfterLive, liveFailsListingMatches, secondTeamSearchTimesOut, teamSearchesTimeOut, cancelTeamSearch
        case secondSearchFails, looseRows, metaFails, looseManifest, twoListings, querySelectedChannels, internalMetaConflictWithSibling
        case allCatalogReadsFail, oneCatalogReadFailsWithoutMatch, catalogsEmpty
        case liveSecondPageFails, browseSecondPageFails, liveConflictThenPageFails, liveSecondPageCancelled
        case metadataLabels, contradictoryDuplicate, rejectedThenAdmittedContract, partialStreams, emptyStreams, streamReadFails, streamScanLimit
    }
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
            case .allCatalogReadsFail:
                throw URLError(.timedOut)
            case .oneCatalogReadFailsWithoutMatch:
                if url.lastPathComponent == "search=Everton.json" { throw URLError(.timedOut) }
                body = ["metas": []]
            case .catalogsEmpty:
                body = ["metas": []]
            case .liveSecondPageFails, .browseSecondPageFails, .liveConflictThenPageFails, .liveSecondPageCancelled:
                let target = mode == .browseSecondPageFails ? "sports_football" : "sports_live"
                if url.path.contains("/" + target + "/skip=") {
                    if mode == .liveSecondPageCancelled { throw CancellationError() }
                    throw URLError(.timedOut)
                }
                if url.path.hasSuffix("/" + target + ".json") {
                    var page = (0..<99).map { i -> [String: Any] in
                        var other = later; other["id"] = "streamed:filler\(i)"; return other
                    }
                    if mode == .liveConflictThenPageFails {
                        var conflict = row; conflict["releaseInfo"] = "14 Nov 2026 · 18:00 UTC"
                        conflict["description"] = "Arsenal vs Everton\n14 Nov 2026 · 18:00 UTC"
                        page[0] = conflict
                    }
                    page.append(row)
                    body = ["metas": page]
                } else { body = ["metas": []] }
            case .secondTeamSearchTimesOut:
                if url.lastPathComponent == "search=Everton.json" { throw URLError(.timedOut) }
                body = ["metas": url.lastPathComponent == "search=Arsenal.json" ? [row] : []]
            case .teamSearchesTimeOut:
                if searching { throw URLError(.timedOut) }
                body = ["metas": url.lastPathComponent == "sports_live.json" ? [row] : []]
            case .cancelTeamSearch:
                throw CancellationError()
            case .twoListings, .partialStreams, .internalMetaConflictWithSibling:
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
            if [.twoListings, .partialStreams, .internalMetaConflictWithSibling].contains(mode), url.path.contains("feed-b") { meta["id"] = "streamed:synthetic-feed-b" }
            if mode == .internalMetaConflictWithSibling, !url.path.contains("feed-b") {
                meta["description"] = "Chelsea vs Fulham\n10 Nov 2026 · 18:00 UTC"
            }
            body = ["meta": meta]
        } else {
            streamCount += 1
            if mode == .streamReadFails || mode == .partialStreams && url.path.contains("feed-b") { return unavailable() }
            let key = premium ? "token" : "ft"
            var deliveries: [[String: Any]] = [["externalUrl": "https://sports.highfly.to/setup"],
                ["url": "https://papacito.cfd/m3u/synthetic/index.m3u8?\(key)=synthetic", "behaviorHints": ["notWebReady": true]]]
            if mode == .twoListings, url.path.contains("feed-b") {
                deliveries = (1...10).map { ["url": "https://edge\($0).papacito.cfd/m3u/b\($0)/index.m3u8?\(key)=s"] }
                deliveries.append(["url": "https://papacito.cfd/m3u/synthetic/index.m3u8?\(key)=synthetic"])
            }
            if mode == .querySelectedChannels {
                let base = "https://papacito.cfd/m3u/synthetic/index.m3u8"
                deliveries = streamCount == 1
                    ? [["url": base + "?channel=one&ft=original"], ["url": base + "?channel=two&ft=original"]]
                    : [["url": base + "?channel=two&token=renewed"]]
            }
            if mode == .emptyStreams { deliveries = [] }
            if mode == .metadataLabels {
                deliveries = [
                    ["url": "https://edge.example.com/first.m3u8?token=private-token-sentinel",
                     "name": "Arsenal vs Everton", "title": "private-label-sentinel"],
                    ["url": "https://edge.example.com/second.m3u8", "name": "Arsenal vs Everton", "title": "Chelsea vs Fulham"],
                    ["url": "https://edge.example.com/third.m3u8", "name": 12, "title": ["unreadable"]]]
            }
            if mode == .contradictoryDuplicate {
                deliveries = [
                    ["url": "https://edge.example.com/duplicate-label.m3u8", "name": "Arsenal vs Everton"],
                    ["url": "https://edge.example.com/duplicate-label.m3u8", "title": "Chelsea vs Fulham"]]
            }
            if mode == .rejectedThenAdmittedContract {
                let contractURL = "https://edge.example.com/same-contract.m3u8"
                deliveries = [["url": contractURL, "drm": true],
                              ["url": contractURL],
                              ["url": contractURL]]
            }
            if mode == .streamScanLimit {
                deliveries = (0..<130).map { ["url": "https://edge.example.com/route-\($0).m3u8"] }
            }
            if mode == .ownDomain { deliveries[0] = ["url": "https://sports.highfly.to/delivery.php", "behaviorHints": NSNull(), "drm": NSNull()] }
            if mode == .nullableMetadata { deliveries += [["url": "https://edge.example.com/live", "headers": NSNull(), "behaviorHints": ["proxyHeaders": NSNull()], "drm": false], ["url": 7]] }
            if mode == .headerVariants {
                let stream = "https://papacito.cfd/m3u/synthetic/index.m3u8?" + key + "=synthetic"
                deliveries = [["url": stream, "headers": ["User-Agent": "Player A"]],
                              ["url": stream, "behaviorHints": ["proxyHeaders": ["request": ["user-agent": "Player A"]]]],
                              ["url": stream, "headers": ["User-Agent": "Player B"]],
                              ["url": stream, "headers": ["Authorization": "private", "User-Agent": 12]]]
            }
            if mode == .badSibling { deliveries.insert(["url": "https://papacito.cfd/m3u/rejected/index.m3u8?\(key)=synthetic"], at: 0) }
            body = ["streams": deliveries]
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
