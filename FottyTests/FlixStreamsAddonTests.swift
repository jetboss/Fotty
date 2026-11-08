import XCTest
@testable import Fotty

final class FlixStreamsAddonTests: XCTestCase {
    private let fixtureID = "dlstreams:event:aaaaaaaaaaaa"
    private let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T14:00:00Z")!
    private let delivery = "https://free.flixnest.app/dlstreams/stream/dlstreams%3Achannel%3A870.m3u8?t=fixture-signature"
    private let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"

    func testManifestRequiresTheReviewedIdentityAndAdvertisedGenrePagination() throws {
        let manifest = try FlixStreamsAddonClient.validateManifest(data: data(manifestJSON()))
        XCTAssertEqual(manifest.id, "org.flixstreams.free")
        XCTAssertEqual(FlixStreamsAddonClient.manifestURL.absoluteString, "https://free.flixnest.app/manifest.json")
        var cases: [[String: Any]] = []
        var changed = manifestJSON(); changed["id"] = "another.addon"; cases.append(changed)
        changed = manifestJSON(); changed["version"] = "private/path"; cases.append(changed)
        changed = manifestJSON(); changed["resources"] = ["catalog", "stream"]; cases.append(changed)
        changed = manifestJSON(); changed["resources"] = ["catalog", "meta", "stream", "stream"]; cases.append(changed)
        changed = manifestJSON(); changed["behaviorHints"] = ["configurationRequired": true]; cases.append(changed)
        changed = manifestJSON(); changed["catalogs"] = [["id": "dlstreams-live", "type": "tv"]]; cases.append(changed)
        changed = manifestJSON(); changed["types"] = ["movie"]; cases.append(changed)
        for document in cases {
            XCTAssertThrowsError(try FlixStreamsAddonClient.validateManifest(data: data(document)))
        }
    }

    func testPLFixtureHasAnExplicitUTCKickoffWithoutInventingLiveState() {
        let value = entry()
        XCTAssertEqual(FlixStreamsAddonClient.explicitKickoff(for: value), kickoff)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [value]), .matched(value))
        XCTAssertTrue(FlixStreamsAddonClient.supports(category: "football"))
        XCTAssertTrue(FlixStreamsAddonClient.supports(category: "soccer"))
        XCTAssertTrue(FlixStreamsAddonClient.supports(category: "cricket"))
        XCTAssertFalse(FlixStreamsAddonClient.supports(category: "basketball"))
        XCTAssertFalse(FlixStreamsAddonClient.supports(category: "american-football"))
    }

    func testUCLAndSerieAFixturesUseTheSameExactTeamAndDateFence() {
        for competition in ["UEFA Champions League", "Europe - UEFA Champions League", "Italy - Serie A"] {
            let value = entry(name: "⚽ \(competition) : Arsenal vs Everton")
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [value]), .matched(value))
        }
        let actual = entry(name: "⚽ Italy - Serie A : Lazio 🇮🇹 vs Parma 🇮🇹", time: "18:45")
        let date = ISO8601DateFormatter().date(from: "2026-10-24T18:45:00Z")!
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(
            for: request(home: "Lazio", away: "Parma", kickoff: date), from: [actual]), .matched(actual))
    }

    func testLiteralReviewedOfficialLeagueLabelsDoNotAdmitSimilarlyNamedOtherCompetitions() {
        for label in ["France - Ligue 1", "Germany - Bundesliga", "Bundesliga", "Spain - La Liga"] {
            let value = entry(name: "⚽ \(label) : Arsenal vs Everton")
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [value]), .matched(value), label)
        }
        for label in ["France - Ligue 2", "France - Première Ligue", "England - Premier League 2", "Bundesliga 2",
                      "Germany - Bundesliga 2", "Unknown Competition"] {
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(),
                from: [entry(name: "⚽ \(label) : Arsenal vs Everton")]), .missing, label)
        }
    }

    @MainActor
    func testRegisteredLigueOneFixtureBindsFSSourceAndPreservesDateSquadAndLeagueVetoes() async throws {
        let clock = Date(), start = ISO8601DateFormatter().date(from: "2026-10-30T18:00:00Z")!
        let registered = registeredRequest(at: clock, home: "Le Havre", away: "PSG", competitionID: "ligue-1", fixtureKickoff: start)
        let definition = try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "flixstreams"))
        XCTAssertTrue(definition.supportsOptionalFixture(event: registered.preferredEvent!))
        XCTAssertEqual(CuratedStreamSourceCatalog.discoveryPlan(for: registered, enabledProviderCodes: ["flixstreams"], at: clock)
            .optionalSources.map(\.providerCode), ["flixstreams"])
        for competition in ["ligue-2", "premier-league-2", "bundesliga-2", "unknown"] {
            let other = registeredRequest(at: clock, home: "Le Havre", away: "PSG", competitionID: competition, fixtureKickoff: start)
            XCTAssertFalse(definition.supportsOptionalFixture(event: other.preferredEvent!))
        }
        var published = entryJSON(name: "⚽ France - Ligue 1 : Le Havre 🇫🇷 vs PSG 🇫🇷")
        published["description"] = entry(date: "2026-10-30", time: "18:00").description!
        published["videos"] = [["id": fixtureID, "title": "Live Stream", "released": "2026-10-30T18:00:00.000Z", "season": 1, "episode": 1]]
        let session = try fixtureSession(page0: [published], page80: [])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let client = FlixStreamsAddonClient(session: session)
        let choices = try await client.resolve(for: registered, now: clock)
        let binding = try XCTUnwrap(choices.first?.eventBinding)
        XCTAssertTrue(binding.matches(request: registered, providerCode: "flixstreams", at: clock))
        XCTAssertEqual(binding.kickoffDate, start)
        for conflict in ["date", "squad", "league"] {
            var changed = published
            if conflict == "date" {
                changed["description"] = entry(date: "2026-10-30", time: "18:01").description!
                changed["videos"] = [["id": fixtureID, "title": "Live Stream", "released": "2026-10-30T18:01:00.000Z", "season": 1, "episode": 1]]
            } else if conflict == "squad" {
                changed["name"] = "⚽ France - Ligue 1 : Le Havre Women vs PSG Women"
            } else { changed["name"] = "⚽ Germany - Bundesliga : Le Havre vs PSG" }
            FlixFixtureProtocol.setResponse(try .json(["metas": [changed]]), for: pagePath(0))
            do { _ = try await client.resolve(for: registered, now: clock); XCTFail("Changed \(conflict) cannot inherit the registered source") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == streamPath }.count, 1)
        }
    }

    func testCricketRequiresExplicitCategoryAndRetainsSquadQualifiers() {
        let value = entry(name: "🏏 Pro20 Cup '26 : Iinyathi 🇿🇦 vs Warriors 🇿🇦", category: "Cricket 🏏", time: "12:00")
        let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        let current = request(home: "Iinyathi", away: "Warriors", category: "cricket", kickoff: date)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: current, from: [value]), .matched(value))
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [value]), .missing)
        let contradiction = entry(name: "🏏 Women's T20 : West Indies vs Zimbabwe", category: "Cricket 🏏")
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(
            for: request(home: "West Indies", away: "Zimbabwe", category: "cricket"), from: [contradiction]), .missing)
        let women = entry(name: "🏏 Women's T20 : West Indies Women vs Zimbabwe Women", category: "Cricket 🏏")
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(
            for: request(home: "West Indies Women", away: "Zimbabwe Women", category: "cricket"), from: [women]), .matched(women))
    }

    func testOnlyExactReviewedFlagsAreRemovedAndUnexpectedControlsRemainFatal() {
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let wales = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
        for flag in [england, scotland, wales, "🇮🇹", "🇿🇦", "🇬🇧"] {
            let value = entry(name: "⚽ England - Premier League : Arsenal \(flag) vs Everton \(flag)")
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [value]), .matched(value))
        }
        for name in [
            "⚽ England - Premier League : Ars\u{200D}enal vs Everton",
            "⚽ England - Premier League : Arsenal\n vs Everton",
            "⚽ England - Premier League : Arsenal \u{E0067} vs Everton",
            "⚽ England - Premier League : Arsenal 🇽🇽 vs Everton",
            "⚽ England - Premier League : Ars🇬🇧enal vs Everton",
            "⚽ England - Premier League : Arsenal\t vs Everton"
        ] {
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [entry(name: name)]), .missing)
        }
    }

    func testDateMustRoundTripAndDescriptionMustHaveTheExactReviewedFourLines() {
        for (date, time) in [("2026-02-30", "14:00"), ("2026-10-24", "24:00"),
                             ("2026-10-24", "14:60"), ("2026-1-24", "14:00")] {
            XCTAssertNil(FlixStreamsAddonClient.explicitKickoff(for: entry(date: date, time: time)))
        }
        for description in [
            "Category: All Soccer Events ⚽\nDate: 2026-10-24\nTime: 14:00\nChannels: Example",
            "Category: All Soccer Events ⚽\nDate: 2026-10-24 (GMT)\nTime: 14:00\nChannels: Example",
            "Category: All Soccer Events ⚽\nDate: 2026-10-24 (UTC)\nTime: 14:00\nChannels: ",
            "Category: All Soccer Events ⚽\nDate: 2026-10-24 (UTC)\nTime: 14:00\nChannels: Example\nLIVE",
            "Category: All Soccer Events ⚽\r\nDate: 2026-10-24 (UTC)\r\nTime: 14:00\r\nChannels: Example"
        ] {
            XCTAssertNil(FlixStreamsAddonClient.explicitKickoff(for: entry(description: description)))
        }
    }

    func testNoWrongTeamDateSportYouthOrEditorialRowsCanMatch() {
        let names = [
            "⚽ England - Premier League : Arsenal vs Fulham",
            "⚽ England - Premier League : Arsenal W vs Everton W",
            "⚽ England - Premier League : Arsenal U19 vs Everton U19",
            "⚽ England - Premier League : Arsenal Reserves vs Everton Reserves",
            "⚽ England - Premier League : Xtra Time : Arsenal vs Everton",
            "⚽ England - Premier League : Arsenal vs Everton Watchalong",
            "⚽ England - Premier League : Arsenal vs Everton Highlights",
            "⚽ Unknown Competition : Arsenal vs Everton",
            "⚽ UEFA Champions League League Phase MD3 | Europe | 20 – 21 October 2026"
        ]
        for name in names {
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [entry(name: name)]), .missing)
        }
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [entry(date: "2026-10-23")]), .missing)
        let cricket = entry(name: "🏏 T20 : Arsenal vs Everton", category: "Cricket 🏏")
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [cricket]), .missing)
        let notFootball = request(category: "basketball")
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: notFootball, from: [entry()]), .missing)
        let noDate = StreamPlaybackRequest(matchID: "fixture", displayTitle: "Arsenal vs Everton",
            homeTeam: "Arsenal", awayTeam: "Everton", category: "football")
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: noDate, from: [entry()]), .missing)
    }

    func testKickoffToleranceAndSquadEquivalenceRemainOwnedByTheSharedMatcher() {
        for offset in [-900.0, 900.0] {
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(
                for: request(kickoff: kickoff.addingTimeInterval(offset)), from: [entry()]), .matched(entry()))
        }
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(
            for: request(kickoff: kickoff.addingTimeInterval(901)), from: [entry()]), .missing)
        let women = entry(name: "⚽ England - Premier League : Arsenal W vs Everton W")
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(
            for: request(home: "Arsenal Women", away: "Everton Women"), from: [women]), .matched(women))
    }

    func testMalformedSameIDAndDistinctMatchingIDsAreConflictsInEitherOrder() throws {
        let good = entry()
        let malformed = entry(hasMalformedIdentity: true)
        let wrong = entry(name: "⚽ England - Premier League : Chelsea vs Brighton")
        let second = entry(id: "dlstreams:event:bbbbbbbbbbbb")
        for sibling in [malformed, wrong, second] {
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [good, sibling]), .conflicting)
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [sibling, good]), .conflicting)
        }
        var malformedJSON = entryJSON(); malformedJSON["description"] = 17
        let decoded = try JSONDecoder().decode(FlixStreamsCatalogEntry.self, from: data(malformedJSON))
        XCTAssertEqual(decoded.id, fixtureID)
        XCTAssertTrue(decoded.hasMalformedIdentity)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [good, decoded]), .conflicting)
        var newAuthority = entryJSON(); newAuthority["cast"] = ["Arsenal", "Fulham"]
        let newDecoded = try JSONDecoder().decode(FlixStreamsCatalogEntry.self, from: data(newAuthority))
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [good, newDecoded]), .conflicting)
    }

    func testActualStremioHintAndVideoEnvelopeCorroboratesTheCatalogTargetAndUTCDate() throws {
        let decoded = try JSONDecoder().decode(FlixStreamsCatalogEntry.self, from: data(entryJSON()))
        XCTAssertFalse(decoded.hasMalformedIdentity)
        XCTAssertEqual(decoded.videoReleasedDate, kickoff)
        XCTAssertEqual(FlixStreamsAddonClient.explicitKickoff(for: decoded), kickoff)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [decoded]), .matched(decoded))
        var optional = entryJSON()
        optional.removeValue(forKey: "behaviorHints"); optional.removeValue(forKey: "videos")
        let noHints = try JSONDecoder().decode(FlixStreamsCatalogEntry.self, from: data(optional))
        XCTAssertFalse(noHints.hasMalformedIdentity)
        XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [noHints]), .matched(noHints))
    }

    func testHintVideoTargetDateTypeAndUnknownAuthorityConflictsAreRetainedAsVetoEvidence() throws {
        let good = try JSONDecoder().decode(FlixStreamsCatalogEntry.self, from: data(entryJSON()))
        var documents: [[String: Any]] = []
        var value = entryJSON()
        value["behaviorHints"] = ["defaultVideoId": "dlstreams:event:bbbbbbbbbbbb"]; documents.append(value)
        value = entryJSON(); value["behaviorHints"] = ["defaultVideoId": fixtureID, "requiresAuth": true]; documents.append(value)
        value = entryJSON(); value["behaviorHints"] = NSNull(); documents.append(value)
        value = entryJSON(); value["behaviorHints"] = ["defaultVideoId": 17]; documents.append(value)
        let videoChanges: [(String, Any)] = [
            ("id", "dlstreams:event:bbbbbbbbbbbb"),
            ("released", "2026-10-24T14:01:00.000Z"),
            ("released", "2026-10-25T14:00:00.000Z"),
            ("released", "2026-02-30T14:00:00.000Z"),
            ("released", NSNull()), ("season", "1"), ("episode", NSNull()),
            ("title", "Arsenal vs Fulham"), ("url", delivery)
        ]
        for (key, replacement) in videoChanges {
            value = entryJSON()
            var video = (value["videos"] as! [[String: Any]])[0]
            video[key] = replacement; value["videos"] = [video]; documents.append(value)
        }
        value = entryJSON(); value["videos"] = []; documents.append(value)
        value = entryJSON(); value["videos"] = NSNull(); documents.append(value)
        value = entryJSON(); value["videos"] = (value["videos"] as! [[String: Any]]) + (value["videos"] as! [[String: Any]])
        documents.append(value)
        for document in documents {
            let malformed = try JSONDecoder().decode(FlixStreamsCatalogEntry.self, from: data(document))
            XCTAssertEqual(malformed.id, fixtureID)
            XCTAssertNil(FlixStreamsAddonClient.explicitKickoff(for: malformed))
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [malformed]), .missing)
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [good, malformed]), .conflicting)
            XCTAssertEqual(FlixStreamsAddonClient.selectMatch(for: request(), from: [malformed, good]), .conflicting)
        }
    }

    @MainActor
    func testRegisteredLookupReadsFreshCatalogAndReturnsBoundPickerCompatibleDeliveries() async throws {
        let clock = Date(), session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let client = FlixStreamsAddonClient(session: session)
        let ordinary = try await client.resolve(for: request(), now: clock)
        XCTAssertNil(ordinary.first?.eventBinding, "The existing unregistered path is unchanged")
        let registered = registeredRequest(at: clock)
        let resolvedAt = clock.addingTimeInterval(1)
        let choices = try await client.resolve(for: registered, now: resolvedAt)
        let choice = try XCTUnwrap(choices.first), binding = try XCTUnwrap(choice.eventBinding)
        XCTAssertEqual(binding.providerCode, "flixstreams")
        XCTAssertEqual(binding.providerEventID, fixtureID)
        XCTAssertEqual(binding.streamID, fixtureID)
        XCTAssertTrue(binding.matches(request: registered, providerCode: "flixstreams", at: resolvedAt))
        XCTAssertTrue(StreamPluginProviderMatching.isActivePlayerSession(choice))
        XCTAssertEqual(binding.expiresAt, resolvedAt.addingTimeInterval(90))
        XCTAssertEqual(choice.playableURL, ordinary.first?.playableURL)
        XCTAssertNil(choice.expiryTime, "The opaque media token declares no expiry; a metadata TTL is not its lease")
        XCTAssertFalse(binding.isCurrent(at: resolvedAt.addingTimeInterval(90)))
        XCTAssertFalse(choice.hasExpiredMediaLease(at: resolvedAt.addingTimeInterval(90)),
                       "Failed metadata renewal alone must not expire an otherwise unknown media lease")
        XCTAssertTrue(choice.requiresGuardedRelay == true)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 6,
            "Registered metadata must not reuse a positive cached catalog")
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == streamPath }.count, 2)
    }

    @MainActor
    func testRegisteredLookupRejectsChangedDatePairAndLateSiblingBeforeRequestingStreams() async throws {
        for conflict in ["date", "pair", "sibling"] {
            let clock = Date(), session = try fixtureSession()
            defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
            let client = FlixStreamsAddonClient(session: session)
            _ = try await client.resolve(for: request(), now: clock)
            var changed = entryJSON()
            if conflict == "date" {
                changed["description"] = entry(time: "14:01").description!
                changed["videos"] = [["id": fixtureID, "title": "Live Stream", "released": "2026-10-24T14:01:00.000Z",
                                      "season": 1, "episode": 1]]
            } else if conflict == "pair" {
                changed["name"] = "⚽ England - Premier League : Arsenal vs Fulham"
            } else {
                changed["description"] = NSNull()
                FlixFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: pagePath(0))
            }
            FlixFixtureProtocol.setResponse(try .json(["metas": [changed]]), for: pagePath(80))
            do {
                _ = try await client.resolve(for: registeredRequest(at: clock), now: clock.addingTimeInterval(1))
                XCTFail("A changed registered identity must be rejected")
            } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
            XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 6)
            XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == streamPath }.count, 1,
                "A retained identity is never authority to request a changed source descriptor")
        }
    }

    @MainActor
    func testExpiredRegisteredListingCannotBindOrRequestADescriptor() async throws {
        let clock = Date(), session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let client = FlixStreamsAddonClient(session: session)
        do {
            _ = try await client.resolve(for: registeredRequest(at: clock, expiresAt: clock.addingTimeInterval(-1)), now: clock)
            XCTFail("Expired registry authority cannot resolve a stream")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertFalse(FlixFixtureProtocol.paths.contains(streamPath))
    }

    @MainActor
    func testRegisteredFlixReresolveFetchesFreshTokenAndRejectsNewHeaderContract() async throws {
        let clock = Date(), session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let client = FlixStreamsAddonClient(session: session)
        let scoped = registeredRequest(at: clock)
        let original = try await client.resolve(for: scoped, now: clock)
        let rotated = delivery.replacingOccurrences(of: "fixture-signature", with: "fresh-private-token")
        FlixFixtureProtocol.setResponse(try .json(["streams": [["url": rotated]]]), for: streamPath)

        let refreshed = try await client.resolve(for: scoped, now: clock.addingTimeInterval(10))

        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed[0].playableURL.absoluteString, rotated)
        XCTAssertTrue(refreshed[0].requiredHeaders.isEmpty)
        XCTAssertFalse(refreshed[0].canRefresh)
        XCTAssertNotNil(refreshed[0].eventBinding)
        XCTAssertTrue(LiveStreamResolver.isSameDescriptorChoice(refreshed[0], as: original[0]))
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 6,
            "Registered renewal must reread all pages, preserving conflicting sibling checks")
        FlixFixtureProtocol.setResponse(try .json(["streams": [["url": rotated,
            "behaviorHints": ["proxyHeaders": ["request": ["Authorization": "private-header"]]]]]]), for: streamPath)

        do {
            _ = try await client.resolve(for: scoped, now: clock.addingTimeInterval(11))
            XCTFail("A new header contract cannot become a fresh Flix delivery")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 1)) }
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == streamPath }.count, 3)
    }

    func testOnlyTheReviewedEncodedChannelRouteAndOneOpaqueTokenAreAdmitted() {
        XCTAssertTrue(FlixStreamsAddonClient.isAdmittedDelivery(URL(string: delivery)!))
        XCTAssertTrue(FlixStreamsAddonClient.isAdmittedDelivery(URL(string: delivery.replacingOccurrences(
            of: "free.flixnest.app/", with: "free.flixnest.app:443/"))!))
        let bad = [
            delivery.replacingOccurrences(of: "https:", with: "http:"),
            delivery.replacingOccurrences(of: "free.flixnest.app", with: "free.flixnest.app.evil.example"),
            delivery.replacingOccurrences(of: "free.flixnest.app", with: "user:secret@free.flixnest.app"),
            delivery.replacingOccurrences(of: "free.flixnest.app", with: "free.flixnest.app:8443"),
            delivery.replacingOccurrences(of: "%3A", with: ":"),
            delivery.replacingOccurrences(of: "%3A", with: "%253A"),
            delivery.replacingOccurrences(of: "%3A870", with: "%3A0"),
            delivery.replacingOccurrences(of: "%3A870", with: "%3A-1"),
            delivery.replacingOccurrences(of: "%3A870", with: "%3A0870"),
            delivery.replacingOccurrences(of: ".m3u8", with: ".mpd"),
            delivery.replacingOccurrences(of: "/dlstreams/stream/", with: "/api/dlstreams/"),
            delivery + "#player", delivery + "&token=extra", delivery + "&t=duplicate",
            delivery.replacingOccurrences(of: "?t=fixture-signature", with: "?t="),
            delivery.replacingOccurrences(of: "?t=fixture-signature", with: "?t=%0Ahidden"),
            delivery.replacingOccurrences(of: "?t=fixture-signature", with: "?t=%E2%80%8Bhidden"),
            delivery.replacingOccurrences(of: "?t=fixture-signature", with: "?t=" + String(repeating: "x", count: 4097))
        ]
        for value in bad { XCTAssertFalse(FlixStreamsAddonClient.isAdmittedDelivery(URL(string: value)!)) }
    }

    func testSessionsDeduplicateTheFullDeliveryAndNeverExposeItsToken() throws {
        let rows = (0..<8).map { ["url": delivery + String($0), "filename": "harmless.ts", "name": "Example", "title": "Channel"] }
        let decoded = try decodeStreams([rows[0]] + rows)
        let result = FlixStreamsAddonClient.makeSessions(from: decoded, request: request(), addOnVersion: "1.0.0")
        XCTAssertEqual(result.map(\.providerName), ["FS1", "FS2", "FS3", "FS4", "FS5", "FS6"])
        XCTAssertEqual(Set(result.map { $0.diagnosticMetadata["source_key"]! }).count, 6)
        for session in result {
            XCTAssertEqual(session.matchID, request().matchID)
            XCTAssertEqual(session.streamType, .hls)
            XCTAssertTrue(session.requiresLocalProxy)
            XCTAssertTrue(session.requiredHeaders.isEmpty)
            XCTAssertNil(session.nativeOriginProfile)
            XCTAssertNil(session.nativePlaylistProfile)
            XCTAssertEqual(session.diagnosticMetadata["source_family"], "flixstreams")
            XCTAssertEqual(session.diagnosticMetadata["source_key"]?.count, 27)
            XCTAssertFalse(session.diagnosticMetadata.description.contains("fixture-signature"))
            XCTAssertFalse(session.diagnosticMetadata.description.contains("free.flixnest.app"))
        }
    }

    func testUnsupportedStreamContractsAreNotConvertedToHeaderlessDeliveries() throws {
        let additions: [[String: Any]] = [
            ["externalUrl": delivery], ["infoHash": "hash"], ["drm": "clearkey"], ["licenseUrl": "https://example.invalid"],
            ["headers": ["Authorization": "secret"]], ["behaviorHints": ["proxyHeaders": ["request": [:]]]],
            ["behaviorHints": [:]], ["url": 17], ["filename": 17]
        ]
        for extra in additions {
            var row: [String: Any] = ["url": delivery]
            extra.forEach { row[$0.key] = $0.value }
            let result = FlixStreamsAddonClient.makeSessions(from: try decodeStreams([row]), request: request(), addOnVersion: "1.0.0")
            XCTAssertTrue(result.isEmpty)
        }
    }

    func testMetadataRoutesAreFixedAndDoNotAdmitConfigurationOrSearchPaths() {
        for path in ["/manifest.json", pagePath(0), pagePath(40), pagePath(80, genre: "cricket"),
                     streamPath, streamPath.replacingOccurrences(of: ":", with: "%3A")] {
            XCTAssertTrue(FlixStreamsAddonClient.isSafeMetadataURL(URL(string: "https://free.flixnest.app" + path)!))
        }
        for path in ["/encoded-user-config/manifest.json", "/configure", "/catalog/tv/dlstreams-live.json",
                     "/catalog/tv/essential-live-events/search=Arsenal.json", pagePath(0) + "?token=extra",
                     "/catalog/tv/essential-live-events/genre=soccer&skip=120.json", "/manifest.json#fragment"] {
            XCTAssertFalse(FlixStreamsAddonClient.isSafeMetadataURL(URL(string: "https://free.flixnest.app" + path)!))
        }
        XCTAssertFalse(FlixStreamsAddonClient.isSafeMetadataURL(URL(string: "http://free.flixnest.app/manifest.json")!))
        XCTAssertFalse(FlixStreamsAddonClient.isSafeMetadataURL(URL(string: "https://free.flixnest.app:8443/manifest.json")!))
    }

    func testBatchCatalogSharesCompleteGenreReadsWithoutEagerMetadataOrStreams() async throws {
        let secondID = "dlstreams:event:bbbbbbbbbbbb"
        let second = StreamPlaybackRequest(matchID: "second-football", displayTitle: "Chelsea vs Tottenham Hotspur",
            homeTeam: "Chelsea", awayTeam: "Tottenham Hotspur", category: "football", kickoffDate: kickoff)
        let cricket = request(home: "West Indies", away: "Zimbabwe", category: "cricket")
        let session = try fixtureSession(page80: [entryJSON(), entryJSON(id: secondID,
            name: "⚽ England - Premier League : Chelsea vs Tottenham Hotspur")])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let cricketID = "dlstreams:event:cccccccccccc"
        for skip in [0, 40, 80] {
            FlixFixtureProtocol.setResponse(try .json(["metas": skip == 80 ? [entryJSON(id: cricketID,
                name: "🏏 T20 International : West Indies vs Zimbabwe", category: "Cricket 🏏")] : []]),
                for: pagePath(skip, genre: "cricket"))
        }
        let client = FlixStreamsAddonClient(session: session)
        let requests = [request(), second, cricket, request(category: "basketball")]
        let rows = try await client.catalogMatches(for: requests, now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .listed, .listed, .unsupported])
        XCTAssertEqual(rows.prefix(3).map(\.providerEventID), [fixtureID, secondID, cricketID])
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 6)
        XCTAssertFalse(FlixFixtureProtocol.paths.contains { $0.hasPrefix("/meta/") || $0.hasPrefix("/stream/") })
        let readCount = FlixFixtureProtocol.paths.count
        _ = try await client.catalogMatches(for: requests, now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(FlixFixtureProtocol.paths.count, readCount, "The batch reuses existing bounded genre caches")
    }

    func testBatchCricketFailureRetainsCompleteFootballCatalog() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        FlixFixtureProtocol.setResponse(.status(503), for: pagePath(0, genre: "cricket"))
        let cricket = request(home: "West Indies", away: "Zimbabwe", category: "cricket")
        let rows = try await FlixStreamsAddonClient(session: session).catalogMatches(for: [request(), cricket], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.listed, .failed(.manifestUnreachable)])
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.contains("genre=soccer") }.count, 3)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.contains("genre=cricket") }.count, 1)
        XCTAssertFalse(FlixFixtureProtocol.paths.contains { $0.hasPrefix("/meta/") || $0.hasPrefix("/stream/") })
    }

    func testBatchFailedLaterFootballPageNeverPublishesEarlyHitOrErasesCricket() async throws {
        let session = try fixtureSession(page0: [entryJSON()])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        for skip in [0, 40, 80] {
            FlixFixtureProtocol.setResponse(try .json(["metas": skip == 80 ? [entryJSON(id: "dlstreams:event:cccccccccccc",
                name: "🏏 T20 International : West Indies vs Zimbabwe", category: "Cricket 🏏")] : []]),
                for: pagePath(skip, genre: "cricket"))
        }
        FlixFixtureProtocol.setResponse(.body(Data("not json".utf8)), for: pagePath(40))
        let cricket = request(home: "West Indies", away: "Zimbabwe", category: "cricket")
        let rows = try await FlixStreamsAddonClient(session: session).catalogMatches(for: [request(), cricket], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.failed(.manifestInvalid), .listed])
        XCTAssertNil(rows[0].providerEventID)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.contains("genre=cricket") }.count, 3)
        XCTAssertFalse(FlixFixtureProtocol.paths.contains(pagePath(80)), "Failed genre never claims page completeness")
    }

    func testBatchLaterPageConflictCannotBecomeListed() async throws {
        let session = try fixtureSession(page0: [entryJSON()], page80: [])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        var malformed = entryJSON(); malformed["description"] = NSNull()
        FlixFixtureProtocol.setResponse(try .json(["metas": [malformed]]), for: pagePath(80))
        let rows = try await FlixStreamsAddonClient(session: session).catalogMatches(for: [request()], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.conflicting])
        XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0), pagePath(40), pagePath(80)])
    }

    func testCancelledBatchStopsAtPendingPageWithoutPublishingOrContinuing() async throws {
        let gate = FlixFixtureGate("batch first page")
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        FlixFixtureProtocol.setResponse(.controlled(gate), for: pagePath(0))
        let client = FlixStreamsAddonClient(session: session), requests = [request()]
        let operation = Task { try await client.catalogMatches(for: requests, now: self.kickoff) }
        defer { operation.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        operation.cancel(); gate.respond(try .json(["metas": [entryJSON()]]))
        do { _ = try await operation.value; XCTFail("Cancelled batch cannot publish") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0)])
    }

    func testUnsupportedOrOversizedBatchDoesNotReadSource() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let client = FlixStreamsAddonClient(session: session)
        let rows = try await client.catalogMatches(for: [request(category: "basketball")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.unsupported])
        do { _ = try await client.catalogMatches(for: Array(repeating: request(), count: 257), now: kickoff); XCTFail("Bound") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
        XCTAssertTrue(FlixFixtureProtocol.paths.isEmpty)
    }

    func testRealResolveCompletesAllThreePagesWithoutUsingIgnoredSearch() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let result = try await FlixStreamsAddonClient(session: session).resolve(for: request())
        XCTAssertEqual(result.map(\.providerName), ["FS1"])
        XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0), pagePath(40), pagePath(80), streamPath])
        XCTAssertEqual(FlixFixtureProtocol.requests.map(\.timeoutInterval), [7, 7, 7, 7, 11])
        XCTAssertTrue(FlixFixtureProtocol.requests.allSatisfy { $0.url?.host == "free.flixnest.app" })
        XCTAssertFalse(FlixFixtureProtocol.paths.contains { $0.contains("search=") })
    }

    func testAnEarlyHitCannotHideAConflictingThirdPage() async throws {
        let session = try fixtureSession(page0: [entryJSON()], page80: [])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        var invalid = entryJSON(); invalid["description"] = NSNull()
        FlixFixtureProtocol.setResponse(try .json(["metas": [invalid]]), for: pagePath(80))
        do {
            _ = try await FlixStreamsAddonClient(session: session).resolve(for: request())
            XCTFail("Later same-ID malformed evidence must veto the early row")
        } catch { XCTAssertEqual(error as? CommunitySportsAddonError, .conflictingMatch) }
        XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0), pagePath(40), pagePath(80)])
    }

    func testCatalogAndMetadataByteBoundsFailBeforeAnyStreamLookup() async throws {
        for response: FlixFixtureProtocol.Response in [
            try .json(["metas": Array(repeating: entryJSON(), count: 41)]),
            .body(Data(repeating: 0x20, count: 512 * 1024 + 1))
        ] {
            let session = try fixtureSession()
            defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
            FlixFixtureProtocol.setResponse(response, for: pagePath(0))
            do { _ = try await FlixStreamsAddonClient(session: session).resolve(for: request()); XCTFail("Bound exceeded") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
            XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0)])
        }
    }

    func testAFailedLaterPageCannotTurnAnEarlyHitIntoAStreamRequest() async throws {
        let session = try fixtureSession(page0: [entryJSON()])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        FlixFixtureProtocol.setResponse(.status(503), for: pagePath(40))
        do { _ = try await FlixStreamsAddonClient(session: session).resolve(for: request()); XCTFail("Page failed") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .catalog)) }
        XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0), pagePath(40)])
    }

    func testMalformedStreamSiblingsAreIsolatedAndUnsupportedListsRemainAdmissionFailures() async throws {
        let documents: [([String: Any], Int)] = [
            (["streams": [NSNull(), ["url": 17], ["url": delivery, "drm": "clearkey"], ["url": delivery]]], 1),
            (["streams": [["url": delivery, "behaviorHints": ["proxyHeaders": ["request": NSNull()]]]]], 0)
        ]
        for (document, expected) in documents {
            let session = try fixtureSession(streams: .json(document))
            defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
            do {
                let result = try await FlixStreamsAddonClient(session: session).resolve(for: request())
                XCTAssertEqual(result.count, expected); XCTAssertGreaterThan(expected, 0)
            } catch {
                XCTAssertEqual(expected, 0)
                XCTAssertEqual(error as? CommunitySportsAddonError, .streamAdmissionRejected(entryCount: 1))
            }
        }
    }

    func testEmptyStreamsAndMalformedStreamDocumentsKeepDistinctStages() async throws {
        for document: [String: Any] in [["streams": []], ["streams": NSNull()], [:]] {
            let session = try fixtureSession(streams: .json(document))
            defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
            do { _ = try await FlixStreamsAddonClient(session: session).resolve(for: request()); XCTFail("Empty") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .streamEntriesEmpty) }
        }
        let session = try fixtureSession(streams: .json(["streams": "not-an-array"]))
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        do { _ = try await FlixStreamsAddonClient(session: session).resolve(for: request()); XCTFail("Malformed") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidJSON(stage: .streams)) }
    }

    func testPositiveAndNegativeCatalogTTLRemainBounded() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        let client = FlixStreamsAddonClient(session: session)
        _ = try await client.resolve(for: request(), now: start)
        _ = try await client.resolve(for: request(), now: start.addingTimeInterval(119))
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 3)
        _ = try await client.resolve(for: request(), now: start.addingTimeInterval(120))
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 6)

        FlixFixtureProtocol.reset()
        let negativeSession = try fixtureSession(page80: [])
        defer { negativeSession.invalidateAndCancel() }
        let negative = FlixStreamsAddonClient(session: negativeSession)
        for offset in [0.0, 14.0] {
            do { _ = try await negative.resolve(for: request(), now: start.addingTimeInterval(offset)); XCTFail("Missing") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 3)
        FlixFixtureProtocol.setResponse(try .json(["metas": [entryJSON()]]), for: pagePath(80))
        _ = try await negative.resolve(for: request(), now: start.addingTimeInterval(15))
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.hasPrefix("/catalog/") }.count, 6)
    }

    func testSoccerAndCricketCachesAreNotInterchangeable() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        for skip in [0, 40, 80] {
            FlixFixtureProtocol.setResponse(try .json(["metas": skip == 80 ? [
                entryJSON(name: "🏏 T20 International : West Indies vs Zimbabwe", category: "Cricket 🏏")
            ] : []]), for: pagePath(skip, genre: "cricket"))
        }
        let client = FlixStreamsAddonClient(session: session)
        _ = try await client.resolve(for: request())
        let result = try await client.resolve(for: request(home: "West Indies", away: "Zimbabwe", category: "cricket"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0.contains("genre=cricket") }.count, 3)
        XCTAssertEqual(FlixFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
    }

    func testCancelledCatalogDoesNotContinueToOtherPagesOrStreams() async throws {
        let gate = FlixFixtureGate("first catalog started")
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        FlixFixtureProtocol.setResponse(.controlled(gate), for: pagePath(0))
        let client = FlixStreamsAddonClient(session: session)
        let lookup = Task { try await client.resolve(for: request()) }
        defer { lookup.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        lookup.cancel()
        do { _ = try await lookup.value; XCTFail("Cancelled") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(FlixFixtureProtocol.paths, ["/manifest.json", pagePath(0)])
    }

    func testOlderCatalogCompletionCannotOverwriteANewerCachedSnapshot() async throws {
        let gate = FlixFixtureGate("older first page")
        let session = try fixtureSession(page80: [])
        defer { session.invalidateAndCancel(); FlixFixtureProtocol.reset() }
        FlixFixtureProtocol.setResponse(.controlled(gate), for: pagePath(0))
        let client = FlixStreamsAddonClient(session: session)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let older = Task { try await client.resolve(for: request(), now: start) }
        defer { older.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        let newerID = "dlstreams:event:bbbbbbbbbbbb"
        FlixFixtureProtocol.setResponse(try .json(["metas": [entryJSON(id: newerID)]]), for: pagePath(0))
        FlixFixtureProtocol.setResponse(try .json(["streams": [["url": delivery + "-new"]]]),
                                       for: "/stream/tv/" + newerID + ".json")
        let fresh = try await client.resolve(for: request(), now: start.addingTimeInterval(1))
        XCTAssertTrue(fresh[0].playableURL.absoluteString.hasSuffix("-new"))
        gate.respond(try .json(["metas": [entryJSON()]]))
        let old = try await older.value
        XCTAssertFalse(old[0].playableURL.absoluteString.hasSuffix("-new"))
        FlixFixtureProtocol.setResponse(.status(503), for: pagePath(0))
        let retained = try await client.resolve(for: request(), now: start.addingTimeInterval(2))
        XCTAssertTrue(retained[0].playableURL.absoluteString.hasSuffix("-new"))
    }

    func testConfigurationKeepsTheInheritedTimeoutPrivacyAndNoCookiePolicy() {
        let configuration = FlixStreamsAddonClient.makeConfiguration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 7)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 12)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
    }

    @MainActor
    func testPhysicalFlixDecodedVideoCanary() async throws {
        #if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
        try await ReviewedAddonPhysicalCanary.run(on: self, source: .flix)
        #else
        throw XCTSkip("Requires the explicit physical-device Flix flag; no native playback pass.")
        #endif
    }

    @MainActor
    func testPhysicalFlixSecondDecodedVideoCanary() async throws {
        #if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
        try await ReviewedAddonPhysicalCanary.run(on: self, source: .flix, flixVariant: 2)
        #else
        throw XCTSkip("Requires the explicit physical-device Flix flag; no native playback pass.")
        #endif
    }

    private var streamPath: String { "/stream/tv/" + fixtureID + ".json" }
    @MainActor
    private func registeredRequest(at clock: Date, expiresAt: Date? = nil, home: String = "Arsenal", away: String = "Everton",
                                   competitionID: String = "premier-league", fixtureKickoff: Date? = nil) -> StreamPlaybackRequest {
        let start = fixtureKickoff ?? kickoff
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:" + competitionID + ":arsenal-everton", sport: "football",
            competitionID: competitionID, competitionName: competitionID, eventKind: .match, title: home + " vs " + away,
            participants: [.init(id: "arsenal", name: home), .init(id: "everton", name: away)],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: clock, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), sources: [],
            sportsFixture: metadata)
        let expiry = expiresAt ?? clock.addingTimeInterval(600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "flixstreams",
            providerEventID: fixtureID, streamID: fixtureID, resourceType: "tv", scope: "football", kind: .event,
            sport: "football", title: metadata.title, participants: [home, away], start: start,
            competitionID: competitionID, squad: metadata.squad,
            observedAt: clock, expiresAt: expiry, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "flixstreams",
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: start,
                participants: [home, away], competitionID: competitionID, squad: metadata.squad), expiresAt: expiry)
        let provider = BroadcastRegistrySnapshot.Provider(providerCode: "flixstreams", scope: "football", status: .available,
            observedAt: clock, expiresAt: expiry)
        return StreamPlaybackRequest(event: event).usingRegistryMatch(.init(broadcast: record, link: link, provider: provider))
    }
    private func pagePath(_ skip: Int, genre: String = "soccer") -> String {
        "/catalog/tv/essential-live-events/genre=\(genre)" + (skip == 0 ? "" : "&skip=\(skip)") + ".json"
    }
    private func request(home: String = "Arsenal", away: String = "Everton", category: String = "football",
                         kickoff: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: "fotty-existing-fixture", displayTitle: "\(home) vs \(away)", homeTeam: home, awayTeam: away,
              category: category, kickoffDate: kickoff ?? self.kickoff)
    }
    private func entry(id: String? = nil, name: String? = nil, category: String = "All Soccer Events ⚽",
                       date: String = "2026-10-24", time: String = "14:00", description: String? = nil,
                       hasMalformedIdentity: Bool = false) -> FlixStreamsCatalogEntry {
        .init(id: id ?? fixtureID, name: name ?? "⚽ England - Premier League : Arsenal \(england) vs Everton \(england)",
              description: description ?? "Category: \(category)\nDate: \(date) (UTC)\nTime: \(time)\nChannels: Example Sports",
              genres: ["Live TV", "Sports", category], hasMalformedIdentity: hasMalformedIdentity)
    }
    private func entryJSON(id: String? = nil, name: String? = nil,
                           category: String = "All Soccer Events ⚽") -> [String: Any] {
        let value = entry(id: id, name: name, category: category)
        return ["id": value.id, "type": "tv", "name": value.name,
                "description": value.description!, "genres": value.genres!, "posterShape": "poster",
                "behaviorHints": ["defaultVideoId": value.id],
                "videos": [["id": value.id, "title": "Live Stream", "released": "2026-10-24T14:00:00.000Z",
                            "season": 1, "episode": 1]]]
    }
    private func manifestJSON() -> [String: Any] {
        ["id": "org.flixstreams.free", "version": "1.0.0", "types": ["tv"], "resources": ["stream", "catalog", "meta"],
         "catalogs": [["id": "essential-live-events", "type": "tv", "extra": [
            ["name": "genre", "isRequired": false, "options": ["soccer", "cricket"]],
            ["name": "search", "isRequired": false], ["name": "skip", "isRequired": false]
         ]]], "behaviorHints": ["configurationRequired": false]]
    }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func decodeStreams(_ rows: [[String: Any]]) throws -> [FlixStreamsStreamEntry] {
        rows.compactMap { try? JSONDecoder().decode(FlixStreamsStreamEntry.self, from: data($0)) }
    }
    private func fixtureSession(page0: [[String: Any]] = [], page80: [[String: Any]]? = nil,
                                streams: FlixFixtureProtocol.Response? = nil) throws -> URLSession {
        FlixFixtureProtocol.configure([
            "/manifest.json": try .json(manifestJSON()),
            pagePath(0): try .json(["metas": page0]),
            pagePath(40): try .json(["metas": []]),
            pagePath(80): try .json(["metas": page80 ?? [entryJSON()]]),
            streamPath: try streams ?? .json(["streams": [["url": delivery]]])
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlixFixtureProtocol.self]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

/// Every synthetic request terminates here; tests never contact a real source.
private final class FlixFixtureProtocol: URLProtocol {
    enum Response {
        case body(Data), failure(Error), status(Int), controlled(FlixFixtureGate)
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
        let value = Self.responses[request.url?.path ?? ""] ?? .failure(URLError(.fileDoesNotExist))
        Self.lock.unlock()
        complete(value)
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
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}

private final class FlixFixtureGate {
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((FlixFixtureProtocol.Response) -> Void)?
    private var pending: FlixFixtureProtocol.Response?
    init(_ name: String) { started = XCTestExpectation(description: name) }
    func start(_ completion: @escaping (FlixFixtureProtocol.Response) -> Void) {
        lock.lock(); let pending = self.pending; self.pending = nil
        if pending == nil { self.completion = completion }
        lock.unlock(); started.fulfill()
        if let pending { completion(pending) }
    }
    func respond(_ value: FlixFixtureProtocol.Response) {
        lock.lock(); let completion = self.completion; self.completion = nil
        if completion == nil { pending = value }
        lock.unlock(); completion?(value)
    }
}
