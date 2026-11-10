import XCTest
@testable import Fotty

@MainActor
final class ReviewedTVPlaylistClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let delivery = "https://tvsen5.aynaott.com/reviewed-willow/index.m3u8"

    func testExactPlaylistAndMainWillowIdentityAreRequired() throws {
        let good = playlist()
        XCTAssertEqual(try ReviewedTVPlaylistClient.willowDelivery(from: good,
            playlistURL: ReviewedTVPlaylistClient.playlistURL).absoluteString, delivery)
        for provenance in ["https://raw.githubusercontent.com/another/iptv/master/streams/us.m3u",
                           ReviewedTVPlaylistClient.playlistURL.absoluteString + "?unreviewed=1",
                           "http://raw.githubusercontent.com/iptv-org/iptv/master/streams/us.m3u"] {
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.willowDelivery(from: good, playlistURL: URL(string: provenance)!))
        }
        for id in ["WillowSports.us@SD", "Willow2.us@SD", "willow.us@SD"] {
            XCTAssertThrowsError(try parse(playlist(id: id)))
        }
        for label in ["Willow Sports (720p)", "Willow 2 (720p)", "Fox Cricket (720p)", "Willow (720p) [Geo-blocked]"] {
            XCTAssertThrowsError(try parse(playlist(label: label)))
        }
    }

    func testHTTPSOriginPortCredentialsQueryAndHLSPathRemainClosed() {
        for url in ["http://tvsen5.aynaott.com/a.m3u8", "https://tvsen7.aynaott.com/a.m3u8",
                    "https://child.tvsen5.aynaott.com/a.m3u8", "https://tvsen5.aynaott.com:8443/a.m3u8",
                    "https://user:password@tvsen5.aynaott.com/a.m3u8", "https://tvsen5.aynaott.com/a.m3u8?token=unreviewed",
                    "https://tvsen5.aynaott.com/a.m3u8#fragment", "https://tvsen5.aynaott.com/a.html",
                    "https://127.0.0.1/a.m3u8", "file:///a.m3u8"] {
            XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: url)!), url)
            XCTAssertThrowsError(try parse(playlist(url: url)))
        }
    }

    func testConflictingSameOriginDeliveriesAndHeaderInstructionsFailClosed() throws {
        let repeated = String(decoding: playlist(), as: UTF8.self)
        XCTAssertEqual(try parse(Data((repeated + String(repeated.dropFirst("#EXTM3U\n".count))).utf8)).absoluteString, delivery)
        let sibling = String(decoding: playlist(url: "https://tvsen5.aynaott.com/different/index.m3u8"), as: UTF8.self)
        XCTAssertThrowsError(try parse(Data((repeated + String(sibling.dropFirst("#EXTM3U\n".count))).utf8)))
        for directive in ["#EXTVLCOPT:http-user-agent=unreviewed", "#KODIPROP:inputstream.adaptive.license_key=unreviewed",
                          "#EXTHTTP:{\"Authorization\":\"unreviewed\"}"] {
            XCTAssertThrowsError(try parse(playlist(directive: directive)))
        }
        let duplicatedID = "#EXTM3U\n#EXTINF:-1 tvg-id=\"Willow.us@SD\" tvg-id=\"WillowSports.us@SD\",Willow (720p)\n" + delivery + "\n"
        XCTAssertThrowsError(try parse(Data(duplicatedID.utf8)))
    }

    func testUnrelatedChannelAndUnsupportedWillowFamiliesCannotSupplyTheSelectedChannel() throws {
        let other = "#EXTM3U\n#EXTINF:-1 tvg-id=\"WillowSports.us@SD\",Willow Sports\nhttps://other.example/sports.m3u8\n"
        let main = String(String(decoding: playlist(), as: UTF8.self).dropFirst("#EXTM3U\n".count))
        XCTAssertEqual(try parse(Data((other + main).utf8)).absoluteString, delivery)
        XCTAssertThrowsError(try parse(Data(other.utf8)))
        XCTAssertThrowsError(try parse(Data("<html>Sign in</html>".utf8)))
        XCTAssertThrowsError(try parse(Data([0xff, 0xfe])))
        XCTAssertThrowsError(try parse(Data(repeating: 65, count: ReviewedTVPlaylistClient.maximumBytes + 1)))
        XCTAssertThrowsError(try parse(Data(("#EXTM3U\n" + String(repeating: "#comment\n", count: 20_000)).utf8)))
    }

    func testMalformedUnrelatedPlaylistEntryCannotHideOrProvideWillow() throws {
        let good = String(decoding: playlist(), as: UTF8.self)
        let start = "#EXTM3U\n"
        let broken = "#EXTINF:-1 tvg-id=\"Other.us\",Other" + String(repeating: "x", count: 8193) + "\n"
        let impostor = "https://tvsen5.aynaott.com/other/index.m3u8\n"
        let row = String(good.dropFirst(start.count))
        for body in [broken + impostor + row, row + broken + impostor] {
            XCTAssertEqual(try parse(Data((start + body).utf8)).absoluteString, delivery)
        }
        let selected = "#EXTINF:-1 tvg-id=\"Willow.us@SD\",Willow\n"
        // A broken header must sever the pending selected station from the following URL.
        XCTAssertThrowsError(try parse(Data((start + selected + broken + impostor).utf8)))
        XCTAssertThrowsError(try parse(Data((start + row + selected + "#EXTVLCOPT:" + String(repeating: "x", count: 8193) + "\n" + impostor).utf8)))
    }

    func testTVIsDefaultOffAndFixtureLookupNeedsVerifiedProgrammeAuthority() throws {
        let tv = try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "reviewedtv"))
        XCTAssertFalse(tv.defaultEnabled)
        XCTAssertFalse(StreamPluginRegistry.isEnabledByDefault(providerCode: "reviewedtv"))
        for category in ["football", "cricket", "hockey", "basketball"] {
            XCTAssertFalse(tv.supportsDiscovery(category: category))
        }
        let willow = request()
        XCTAssertEqual(CuratedStreamSourceCatalog.discoveryPlan(for: willow, enabledProviderCodes: ["reviewedtv"], at: now)
            .optionalSources.map(\.providerCode), ["reviewedtv"])
        XCTAssertEqual(CuratedStreamSourceCatalog.discoveryPlan(for: willow,
            enabledProviderCodes: ["reviewedtv", "communitysports"], at: now).optionalSources.map(\.providerCode),
            ["communitysports", "reviewedtv"])
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: request(.foxCricket),
            enabledProviderCodes: ["reviewedtv"], at: now).optionalSources.isEmpty)
        let fixture = EventReference(id: "cricket-fixture:icc:reviewed", title: "India vs Australia", category: "cricket",
            date: Int64(now.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "India", badge: nil), away: .init(name: "Australia", badge: nil)))
        XCTAssertFalse(tv.supportsOptionalFixture(event: fixture))
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: .init(event: fixture),
            enabledProviderCodes: ["reviewedtv"], at: now).optionalSources.isEmpty)
        XCTAssertFalse(FixtureSourceCatalogCollector.lanes()
            .contains { $0.providerCode == "reviewedtv" })
        XCTAssertTrue(BroadcastRegistrySnapshot.providerCodes.contains("reviewedtv"))
        let index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders([], revision: 1)
        XCTAssertFalse(CricketChannelPlaybackPolicy.canResolve(willow.preferredEvent!, discoveryIndex: index))
        index.updateEnabledProviders(["reviewedtv"], revision: 2)
        XCTAssertTrue(CricketChannelPlaybackPolicy.canResolve(willow.preferredEvent!, discoveryIndex: index))
        XCTAssertFalse(CricketChannelPlaybackPolicy.canResolve(request(.foxCricket).preferredEvent!, discoveryIndex: index))
        index.updateEnabledProviders([], revision: 3, invalidating: "reviewedtv")
        XCTAssertFalse(CricketChannelPlaybackPolicy.canResolve(willow.preferredEvent!, discoveryIndex: index))
    }

    func testTVSessionHasItsOwnFamilyFiniteBindingAndGuardedRelayWithoutAProgrammeClaim() throws {
        let original = request()
        let session = try ReviewedTVPlaylistClient.session(for: original, delivery: URL(string: delivery)!, at: now)
        XCTAssertEqual(session.providerName, "TV1")
        XCTAssertEqual(StreamEventBinding.providerCode(forSessionProviderName: session.providerName), "reviewedtv")
        XCTAssertTrue(StreamPluginProviderMatching.matches(session.legacySource, code: "reviewedtv"))
        XCTAssertFalse(StreamPluginProviderMatching.matches(session.legacySource, code: "communitysports"))
        XCTAssertTrue(session.requiresGuardedRelay == true)
        XCTAssertTrue(session.canRefresh)
        XCTAssertEqual(session.requiredHeaders, [:])
        XCTAssertNil(session.qualityLabel, "A published label is not measured native quality or an adaptive ladder")
        let binding = try XCTUnwrap(session.eventBinding)
        XCTAssertNil(binding.kickoffDate)
        XCTAssertEqual(binding.expiresAt, now.addingTimeInterval(90))
        XCTAssertTrue(binding.matches(request: original, providerCode: "reviewedtv", at: now))
        XCTAssertFalse(binding.isCurrent(at: now.addingTimeInterval(90)))
        XCTAssertFalse(binding.matches(request: request(.foxCricket), providerCode: "reviewedtv", at: now))
        XCTAssertThrowsError(try ReviewedTVPlaylistClient.session(for: request(.foxCricket), delivery: URL(string: delivery)!, at: now))
        let forged = StreamPlaybackRequest(matchID: original.matchID, displayTitle: "India vs Australia", homeTeam: "India",
            awayTeam: "Australia", category: "cricket", kickoffDate: now)
        XCTAssertThrowsError(try ReviewedTVPlaylistClient.session(for: forged, delivery: URL(string: delivery)!, at: now))
        XCTAssertNil(StreamEventBinding(request: forged, providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:willow-main", streamID: "reviewed-tv:willow-main", manifestRevision: "1",
            verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
    }

    func testEveryWatchFetchesFreshPlaylistAndRevalidatesBothDestinations() async throws {
        let log = TVFetchLog()
        let first = playlist(), second = playlist(url: "https://tvsen5.aynaott.com/renewed/index.m3u8")
        let client = ReviewedTVPlaylistClient(fetch: { query in
            let count = await log.fetched(query)
            return (count == 1 ? first : second, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL,
                statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        let before = try await client.resolve(for: request(), now: now)
        let after = try await client.resolve(for: request(), now: now.addingTimeInterval(91))
        XCTAssertNotEqual(before.first?.playableURL, after.first?.playableURL)
        XCTAssertTrue(after.first?.eventBinding?.isCurrent(at: now.addingTimeInterval(91)) == true)
        let snapshot = await log.snapshot()
        XCTAssertEqual(snapshot.requests.count, 2)
        XCTAssertEqual(snapshot.destinations.count, 4)
        for query in snapshot.requests {
            XCTAssertEqual(query.url, ReviewedTVPlaylistClient.playlistURL)
            XCTAssertEqual(query.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertFalse(query.httpShouldHandleCookies)
            XCTAssertNil(query.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(query.value(forHTTPHeaderField: "Cookie"))
        }
    }

    func testReselectingTVAfterNinetySecondsReadsFreshDeliveryAndPreservesSelectedSourceIdentity() async throws {
        let log = TVFetchLog()
        let first = playlist(), next = playlist(url: "https://tvsen5.aynaott.com/renewed/index.m3u8")
        let client = ReviewedTVPlaylistClient(fetch: { query in
            let count = await log.fetched(query)
            return (count == 1 ? first : next, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL,
                statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        let request = request()
        let initialChoices = try await client.resolve(for: request, now: now)
        let initial = try XCTUnwrap(initialChoices.first)
        let reselectedAt = now.addingTimeInterval(91)
        XCTAssertFalse(try XCTUnwrap(initial.eventBinding).isCurrent(at: reselectedAt))
        let result = await client.refreshedDescriptor(for: initial, request: request,
            now: reselectedAt, isEnabled: { true })
        let renewed = try XCTUnwrap(result)
        XCTAssertEqual(renewed.id, initial.id)
        XCTAssertEqual(renewed.providerName, "TV1")
        XCTAssertEqual(renewed.eventBinding?.providerEventID, initial.eventBinding?.providerEventID)
        XCTAssertEqual(renewed.eventBinding?.streamID, initial.eventBinding?.streamID)
        XCTAssertNotEqual(renewed.playableURL, initial.playableURL)
        XCTAssertTrue(renewed.requiresGuardedRelay == true)
        XCTAssertEqual(initial.eventBinding?.expiresAt, now.addingTimeInterval(90), "Old authority is never extended")
        XCTAssertEqual(renewed.eventBinding?.expiresAt, reselectedAt.addingTimeInterval(90))
        XCTAssertTrue(renewed.eventBinding?.isCurrent(at: reselectedAt) == true)
        let state = await log.snapshot()
        XCTAssertEqual(state.requests.count, 2)
        XCTAssertEqual(state.destinations.count, 4)
    }

    func testTVRenewalHonoursCurrentOptInBeforeAndAfterFreshMetadata() async throws {
        let log = TVFetchLog(), enabled = TVEnablement()
        let data = playlist()
        let client = ReviewedTVPlaylistClient(fetch: { query in
            _ = await log.fetched(query)
            await enabled.set(false)
            return (data, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL,
                statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        let original = try ReviewedTVPlaylistClient.session(for: request(), delivery: URL(string: delivery)!, at: now)
        let later = now.addingTimeInterval(91)
        let off = await client.refreshedDescriptor(for: original, request: request(), now: later, isEnabled: { false })
        XCTAssertNil(off)
        let initiallyOff = await log.snapshot()
        XCTAssertTrue(initiallyOff.requests.isEmpty)
        await enabled.set(true)
        let revoked = await client.refreshedDescriptor(for: original, request: request(), now: later,
            isEnabled: { await enabled.value })
        XCTAssertNil(revoked)
        let state = await log.snapshot()
        XCTAssertEqual(state.requests.count, 1)
        XCTAssertEqual(original.eventBinding?.expiresAt, now.addingTimeInterval(90))
        let wrongChannel = await client.refreshedDescriptor(for: original, request: request(.foxCricket),
            now: later, isEnabled: { true })
        XCTAssertNil(wrongChannel)
        let final = await log.snapshot()
        XCTAssertEqual(final.requests.count, 1, "A different channel cannot reuse the old source binding")
    }

    func testBadResponseProvenanceAndUnsupportedRequestNeverYieldAPlayableSession() async {
        let data = playlist()
        for response in [HTTPURLResponse(url: URL(string: "https://other.example/us.m3u")!, statusCode: 200,
                                        httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!,
                         HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 302,
                                         httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!,
                         HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                                         httpVersion: nil, headerFields: ["Content-Type": "text/html"])!] {
            let client = ReviewedTVPlaylistClient(fetch: { _ in (data, response) }, validateDestination: { _ in })
            do { _ = try await client.resolve(for: request(), now: now); XCTFail("Unsafe response must not create a session") }
            catch { }
        }
        let log = TVFetchLog()
        let client = ReviewedTVPlaylistClient(fetch: { query in
            _ = await log.fetched(query)
            throw URLError(.badServerResponse)
        }, validateDestination: { await log.validated($0) })
        do { _ = try await client.resolve(for: request(.foxCricket), now: now); XCTFail("Fox is not admitted by this source") }
        catch { }
        let state = await log.snapshot()
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertTrue(state.destinations.isEmpty)
    }

    func testCurrentProgrammeAddsTV1ToTheExistingFixtureWatchPlanAndBindsTheFixture() async throws {
        let programme = programmeRequest(at: now), canonical = StreamPlaybackRequest(event: programme.preferredEvent!)
        let plan = CuratedStreamSourceCatalog.discoveryPlan(for: programme,
            enabledProviderCodes: ["reviewedtv"], at: now)
        XCTAssertEqual(plan.optionalSources.map(\.providerCode), ["reviewedtv"])
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: programme,
            enabledProviderCodes: [], at: now).optionalSources.isEmpty)
        XCTAssertFalse(ReviewedTVPlaylistClient.supports(canonical, at: now),
            "The same named fixture without a programme receipt cannot borrow Willow")
        let association = programme.registryMatch!
        let wire = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "tv-programme", generatedAt: now,
            providers: [association.provider], broadcasts: [association.broadcast], links: [association.link!])
        let admitted = try BroadcastRegistrySnapshot.validated(from: wire.encoded(), at: now)
        XCTAssertEqual(admitted.lookup(for: canonical, enabledProviderCodes: ["reviewedtv"], at: now).count, 1)
        let payload = playlist(), log = TVFetchLog()
        let client = ReviewedTVPlaylistClient(fetch: { query in
            _ = await log.fetched(query)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        let choices = try await client.resolve(for: programme, now: now,
            isEnabled: { true }, currentFixture: { _, _ in canonical })
        let choice = try XCTUnwrap(choices.first), binding = try XCTUnwrap(choice.eventBinding)
        XCTAssertEqual(choice.providerName, "TV1")
        XCTAssertEqual(choice.matchID, canonical.matchID)
        XCTAssertNotEqual(choice.matchID, CricketBroadcastChannel.willow.canonicalID)
        XCTAssertEqual(binding.providerEventID, programme.registryMatch?.broadcast.providerEventID)
        XCTAssertEqual(binding.streamID, ReviewedTVPlaylistClient.providerEventID)
        XCTAssertTrue(binding.usesRegistryAssociation)
        XCTAssertTrue(binding.matches(request: programme, providerCode: "reviewedtv", at: now))
        XCTAssertTrue(choice.requiresGuardedRelay == true)
        XCTAssertEqual(choice.expiryTime, now.addingTimeInterval(90))
        let observed = await log.snapshot()
        XCTAssertEqual(observed.requests.count, 1)
        XCTAssertEqual(observed.destinations.count, 2)
    }

    func testTVFixtureProgrammeRejectsWrongDayTeamsChannelRouteStalenessAndFutureOrEndedIntervals() throws {
        XCTAssertFalse(ReviewedTVPlaylistClient.isProgrammeID("reviewed-tv:programme:" + String(repeating: "b", count: 64) + "\n"))
        let good = programmeRequest(at: now), match = good.registryMatch!
        let payload = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "reviewed-tv-programme", generatedAt: now,
            providers: [match.provider], broadcasts: [match.broadcast], links: [match.link!])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any])
        for change in ["wrong_day", "wrong_teams", "wrong_channel", "wrong_stream", "wrong_id", "stale", "future", "ended", "unlisted"] {
            var body = original, records = body["broadcasts"] as! [[String: Any]], links = body["links"] as! [[String: Any]]
            switch change {
            case "wrong_day": records[0]["day"] = 3
            case "wrong_teams": records[0]["participants"] = ["South Africa Women", "Australia Women"]
            case "wrong_channel": records[0]["channelID"] = CricketBroadcastChannel.foxCricket.canonicalID
            case "wrong_stream": records[0]["streamID"] = "reviewed-tv:other-channel"
            case "wrong_id": records[0]["providerEventID"] = "reviewed-tv:programme:unverified"
            case "stale": records[0]["observedAt"] = stamp(now.addingTimeInterval(-601)); records[0]["expiresAt"] = stamp(now.addingTimeInterval(-1)); links[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
            case "future": records[0]["start"] = stamp(now.addingTimeInterval(60))
            case "ended": records[0]["end"] = stamp(now.addingTimeInterval(-1)); records[0]["expiresAt"] = stamp(now.addingTimeInterval(-1)); links[0]["expiresAt"] = stamp(now.addingTimeInterval(-1))
            default: links[0]["state"] = "needsVerification"
            }
            body["broadcasts"] = records; body["links"] = links
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { value in
                let raw = try value.singleValueContainer().decode(String.self)
                guard let date = BroadcastRegistrySnapshot.date(raw) else { throw BroadcastRegistrySnapshot.ValidationError.invalidRecord }
                return date
            }
            let decoded = try decoder.decode(BroadcastRegistrySnapshot.self, from: JSONSerialization.data(withJSONObject: body))
            let changed = BroadcastRegistryMatch(broadcast: decoded.broadcasts[0], link: decoded.links[0], provider: decoded.providers[0])
            let request = StreamPlaybackRequest(event: good.preferredEvent!).usingRegistryMatch(changed)
            XCTAssertFalse(ReviewedTVPlaylistClient.supports(request, at: now), change)
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.session(for: request, delivery: URL(string: delivery)!, at: now), change)
            XCTAssertTrue(decoded.lookup(for: request, enabledProviderCodes: ["reviewedtv"], at: now).isEmpty, change)
        }
    }

    func testProgrammeResolutionHonoursOptInAndCurrentFixtureAfterMetadataReturns() async throws {
        let programme = programmeRequest(at: now), canonical = StreamPlaybackRequest(event: programme.preferredEvent!)
        let payload = playlist(), log = TVFetchLog(), enabled = TVEnablement()
        let client = ReviewedTVPlaylistClient(fetch: { query in
            _ = await log.fetched(query)
            await enabled.set(false)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        do {
            _ = try await client.resolve(for: programme, now: now, isEnabled: { false }, currentFixture: { _, _ in canonical })
            XCTFail("A disabled provider cannot fetch its playlist")
        } catch { }
        let disabled = await log.snapshot(); XCTAssertTrue(disabled.requests.isEmpty)
        await enabled.set(true)
        do {
            _ = try await client.resolve(for: programme, now: now, isEnabled: { await enabled.value }, currentFixture: { _, _ in canonical })
            XCTFail("Revocation during metadata must discard the delivery")
        } catch { }
        let revoked = await log.snapshot(); XCTAssertEqual(revoked.requests.count, 1)

        let fixtureState = TVFixtureState(canonical)
        let changed = StreamPlaybackRequest(event: programmeRequest(at: now, day: 5).preferredEvent!)
        let changingClient = ReviewedTVPlaylistClient(fetch: { _ in
            await fixtureState.set(changed)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { _ in })
        do {
            _ = try await changingClient.resolve(for: programme, now: now, isEnabled: { true }, currentFixture: { _, _ in await fixtureState.value })
            XCTFail("An obsolete Test-day programme cannot bind the new official day")
        } catch { }
    }

    func testProgrammeRenewalRequiresCurrentSameProgrammeAndPreservesTheSelectedSourceIdentity() async throws {
        let initialRequest = programmeRequest(at: now), canonical = StreamPlaybackRequest(event: initialRequest.preferredEvent!)
        let initial = try ReviewedTVPlaylistClient.session(for: initialRequest, delivery: URL(string: delivery)!, at: now)
        let later = now.addingTimeInterval(91)
        let current = programmeRequest(at: later, fixture: initialRequest.preferredEvent,
            programmeStart: initialRequest.registryMatch!.broadcast.start!, programmeEnd: initialRequest.registryMatch!.broadcast.end!)
        let payload = playlist(url: "https://tvsen5.aynaott.com/fresh-programme/index.m3u8"), log = TVFetchLog()
        let client = ReviewedTVPlaylistClient(fetch: { query in
            _ = await log.fetched(query)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        let missing = await client.refreshedDescriptor(for: initial, request: canonical, now: later, isEnabled: { true },
            currentFixture: { _, _ in canonical }, programmeMatches: { _, _ in [] })
        XCTAssertNil(missing)
        let noAuthority = await log.snapshot(); XCTAssertTrue(noAuthority.requests.isEmpty)
        let renewal = await client.refreshedDescriptor(for: initial, request: canonical, now: later,
            isEnabled: { true }, currentFixture: { _, _ in canonical }, programmeMatches: { _, _ in [current.registryMatch!] })
        let renewed = try XCTUnwrap(renewal)
        XCTAssertEqual(renewed.id, initial.id)
        XCTAssertEqual(renewed.matchID, canonical.matchID)
        XCTAssertNotEqual(renewed.playableURL, initial.playableURL)
        XCTAssertEqual(renewed.eventBinding?.providerEventID, initial.eventBinding?.providerEventID)
        XCTAssertTrue(renewed.eventBinding?.matches(request: current, providerCode: "reviewedtv", at: later) == true)
        XCTAssertFalse(initial.eventBinding?.isCurrent(at: later) == true)
        let observed = await log.snapshot(); XCTAssertEqual(observed.requests.count, 1)
    }

    func testTeniesFootballRejectsSwappedStationAndUnexpectedHeaders() throws {
        let sky = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV25"))
        let tnt = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV26"))
        let path = try XCTUnwrap(sky.deliveryPath)
        let url = "https://cdnlivetv.tv" + path + "?token=" + String(repeating: "a", count: 64)
        func resolve(_ channel: ReviewedTVPlaylistClient.ChannelDefinition, headers: [String: String]) throws -> URL {
            let row: [String: Any] = ["name": "TENIES.SPACE Live TV", "title": "Sky Sports Premier League FHD UK",
                "url": url, "behaviorHints": ["notWebReady": false, "requestHeaders": headers] as [String: Any]]
            return try ReviewedTVPlaylistClient.delivery(from: JSONSerialization.data(withJSONObject: ["streams": [row]]),
                playlistURL: channel.playlistURL, channel: channel)
        }
        let headers = ["Origin": "https://cdnlivetv.tv", "Referer": "https://cdnlivetv.tv/"]
        XCTAssertEqual(try resolve(sky, headers: headers).absoluteString, url)
        XCTAssertThrowsError(try resolve(tnt, headers: headers))
        XCTAssertThrowsError(try resolve(sky, headers: headers.merging(["Cookie": "unexpected"]) { _, new in new }))
    }

    func testReviewedChannelDefinitionsKeepWillowStableAndESPNMarketsExplicit() throws {
        let definitions = ReviewedTVPlaylistClient.channels
        XCTAssertEqual(definitions.map(\.providerName), ((1...15).map { "TV\($0)" } + ["TV17", "TV21", "TV22", "TV23", "TV24", "TV25", "TV26"]))
        XCTAssertEqual(Set(definitions.map(\.playlistIdentifier)).count, 22)
        XCTAssertEqual(Set(definitions.map(\.channelID)).count, 22)
        XCTAssertEqual(definitions[0].playlistIdentifier, ReviewedTVPlaylistClient.channelIdentifier)
        XCTAssertEqual(definitions[0].streamID, ReviewedTVPlaylistClient.providerEventID)
        XCTAssertEqual(definitions[0].channelID, CricketBroadcastChannel.willow.canonicalID)
        let espn = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV2"))
        XCTAssertEqual(espn.playlistIdentifier, "ESPNLatinAmerica.us@South")
        XCTAssertEqual(espn.channelID, "sports-channel:espn-latinamerica-south")
        XCTAssertEqual(espn.streamID, "reviewed-tv:espn-latinamerica-south")
        XCTAssertEqual(espn.markets, ["UY", "PY", "BO", "PE"])
        XCTAssertFalse(espn.markets.contains("AR"))
        XCTAssertEqual(ReviewedTVPlaylistClient.channel(forChannelID: espn.channelID), espn)
        XCTAssertEqual(ReviewedTVPlaylistClient.channel(forStreamID: espn.streamID), espn)
        for name in ["TV0", "TV20", "TV50", "TV02", "tv2", "TV2 ", "FS2", "TV200"] {
            XCTAssertNil(ReviewedTVPlaylistClient.channel(forProviderName: name))
        }
        for definition in definitions {
            XCTAssertEqual(StreamEventBinding.providerCode(forSessionProviderName: definition.providerName), "reviewedtv")
        }
    }

    func testESPNParserRequiresExactChannelMarketLabelAndReviewedTransport() throws {
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV2"))
        let target = URL(string: "https://barinaslive1.boldmss.com/reviewed-espn/index.m3u8")!
        XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: espnPlaylist(),
            playlistURL: ReviewedTVPlaylistClient.playlistURL, channel: channel), target)
        XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(target), "The legacy no-channel API still admits only Willow")
        for id in ["ESPNLatinAmerica.us@Argentina", "ESPNLatinAmerica.us@Chile", "ESPNLatinAmerica.us@Colombia", "ESPN2LatinAmerica.us@South"] {
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: espnPlaylist(id: id),
                playlistURL: ReviewedTVPlaylistClient.playlistURL, channel: channel), id)
        }
        for label in ["ESPN 2 Latin America", "ESPN Latin America Argentina", "Willow", "ESPN Latin America (1080p) [Geo-blocked]"] {
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: espnPlaylist(label: label),
                playlistURL: ReviewedTVPlaylistClient.playlistURL, channel: channel), label)
        }
        for value in ["http://barinaslive1.boldmss.com/a.m3u8", "https://barinaslive1.boldmss.com:1936/a.m3u8",
                      "https://barinaslive1.boldmss.com/a.m3u8?token=unreviewed", "https://barinaslive1.boldmss.com/a.m3u8#fragment",
                      "https://user:password@barinaslive1.boldmss.com/a.m3u8", "https://child.barinaslive1.boldmss.com/a.m3u8",
                      "https://tvsen5.aynaott.com/a.m3u8", "https://127.0.0.1/a.m3u8", "https://barinaslive1.boldmss.com/a.html"] {
            let url = URL(string: value)!
            XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(url, channel: channel), value)
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: espnPlaylist(url: value),
                playlistURL: ReviewedTVPlaylistClient.playlistURL, channel: channel), value)
        }
        for directive in ["#EXTVLCOPT:http-user-agent=unreviewed", "#EXTHTTP:{\"Authorization\":\"unreviewed\"}",
                          "#KODIPROP:inputstream.adaptive.license_key=unreviewed"] {
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: espnPlaylist(directive: directive),
                playlistURL: ReviewedTVPlaylistClient.playlistURL, channel: channel))
        }
    }

    func testFootballNeedsExactCurrentTypedAssignmentAndDoesNotBorrowWillow() throws {
        let assigned = footballAssignment(at: now), canonical = StreamPlaybackRequest(event: assigned.preferredEvent!)
        XCTAssertTrue(ReviewedTVPlaylistClient.supports(assigned, at: now))
        XCTAssertFalse(ReviewedTVPlaylistClient.supports(canonical, at: now))
        XCTAssertThrowsError(try ReviewedTVPlaylistClient.session(for: canonical,
            delivery: URL(string: "https://barinaslive1.boldmss.com/reviewed-espn/index.m3u8")!, at: now))
        let session = try ReviewedTVPlaylistClient.session(for: assigned,
            delivery: URL(string: "https://barinaslive1.boldmss.com/reviewed-espn/index.m3u8")!, at: now)
        XCTAssertEqual(session.providerName, "TV2")
        XCTAssertEqual(session.eventBinding?.streamID, "reviewed-tv:espn-latinamerica-south")
        XCTAssertEqual(session.eventBinding?.providerEventID, assigned.registryMatch?.broadcast.providerEventID)
        XCTAssertEqual(session.expiryTime, now.addingTimeInterval(90))
        XCTAssertTrue(session.requiresGuardedRelay == true)
        XCTAssertTrue(session.requiredHeaders.isEmpty)
        XCTAssertNil(session.qualityLabel)
        XCTAssertFalse(ReviewedTVPlaylistClient.supports(footballAssignment(at: now, market: "AR"), at: now))
        XCTAssertFalse(ReviewedTVPlaylistClient.supports(footballAssignment(at: now, lead: 3_601), at: now))
        XCTAssertFalse(ReviewedTVPlaylistClient.supports(footballAssignment(at: now, lead: -1), at: now))
        XCTAssertFalse(ReviewedTVPlaylistClient.isAssignmentID("reviewed-tv:programme:" + String(repeating: "b", count: 64)))
        XCTAssertFalse(ReviewedTVPlaylistClient.isAssignmentID("reviewed-tv:assignment:" + String(repeating: "B", count: 64)))
        XCTAssertFalse(ReviewedTVPlaylistClient.isAssignmentID("reviewed-tv:assignment:" + String(repeating: "b", count: 64) + "\n"))
    }

    func testChannelTransportHelperRejectsUnknownNamesBeforeNetworkAndAlwaysReadsFreshMetadata() async throws {
        let log = TVFetchLog()
        let first = espnPlaylist(), next = espnPlaylist(url: "https://barinaslive1.boldmss.com/fresh-espn/index.m3u8")
        let client = ReviewedTVPlaylistClient(fetch: { query in
            let count = await log.fetched(query)
            return (count == 1 ? first : next, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL,
                statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        do { _ = try await client.channelDelivery(forProviderName: "TV999"); XCTFail("An unknown label must not fetch") } catch { }
        let unknown = await log.snapshot(); XCTAssertTrue(unknown.requests.isEmpty); XCTAssertTrue(unknown.destinations.isEmpty)
        let before = try await client.channelDelivery(forProviderName: "TV2")
        let after = try await client.channelDelivery(forProviderName: "TV2")
        XCTAssertNotEqual(before, after)
        let fetched = await log.snapshot(); XCTAssertEqual(fetched.requests.count, 2); XCTAssertEqual(fetched.destinations.count, 4)
        for request in fetched.requests {
            XCTAssertEqual(request.url, ReviewedTVPlaylistClient.playlistURL)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testChannelTransportHelperRejectsChangedResponseProvenanceAndRemovedSelectedEntry() async {
        let old = espnPlaylist()
        for response in [HTTPURLResponse(url: URL(string: "https://other.example/us.m3u")!, statusCode: 200,
                                        httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!,
                         HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 302,
                                        httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!,
                         HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                                        httpVersion: nil, headerFields: ["Content-Type": "text/html"])!] {
            let client = ReviewedTVPlaylistClient(fetch: { _ in (old, response) }, validateDestination: { _ in })
            do { _ = try await client.channelDelivery(forProviderName: "TV2"); XCTFail("Changed provenance must not yield a channel") } catch { }
        }
        let log = TVFetchLog()
        let client = ReviewedTVPlaylistClient(fetch: { query in
            let count = await log.fetched(query)
            return (count == 1 ? old : Data("#EXTM3U\n".utf8), HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL,
                statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { _ in })
        do { _ = try await client.channelDelivery(forProviderName: "TV2") } catch { XCTFail("First selected entry should resolve") }
        do { _ = try await client.channelDelivery(forProviderName: "TV2"); XCTFail("Removed entry cannot replay the old URL") } catch { }
    }

    func testCanonicalFixtureCollectsIndependentChannelsFromOneFreshPlaylist() async throws {
        let espn1 = footballAssignment(at: now), espn4 = footballAssignment(at: now, providerName: "TV5")
        let canonical = StreamPlaybackRequest(event: espn1.preferredEvent!)
        let payload = combinedPlaylist([espnPlaylist(), espnPlaylist(id: "ESPN4LatinAmerica.us@South", label: "ESPN 4 Latin America (1080p)",
            url: "https://barinaslive1.boldmss.com/reviewed-espn4/index.m3u8")])
        let log = TVFetchLog()
        let client = ReviewedTVPlaylistClient(fetch: { request in
            _ = await log.fetched(request)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        let result = try await client.resolve(for: canonical, now: now, isEnabled: { true },
            currentFixture: { _, _ in canonical }, programmeMatches: { _, _ in [espn4.registryMatch!, espn1.registryMatch!] })
        XCTAssertEqual(result.map(\.providerName), ["TV2", "TV5"])
        XCTAssertTrue(result.allSatisfy { $0.eventBinding?.matches(request: $0.providerName == "TV2" ? espn1 : espn4,
            providerCode: "reviewedtv", at: self.now) == true })
        let observed = await log.snapshot(); XCTAssertEqual(observed.requests.count, 1); XCTAssertEqual(observed.destinations.count, 3)
    }

    func testMissingSiblingAndConflictingSiblingDoNotEraseAnotherValidChannel() async throws {
        let good = footballAssignment(at: now), bad = footballAssignment(at: now, providerName: "TV3")
        let canonical = StreamPlaybackRequest(event: good.preferredEvent!)
        for sibling in [Data(), espnPlaylist(id: "ESPN2LatinAmerica.us@South", label: "ESPN 2 Latin America (1080p)",
            url: "https://barinaslive1.boldmss.com/reviewed-espn2/index.m3u8", directive: "#EXTHTTP:unreviewed")] {
            let payload = combinedPlaylist([espnPlaylist(), sibling])
            let client = ReviewedTVPlaylistClient(fetch: { _ in
                (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
            }, validateDestination: { _ in })
            let result = try await client.resolve(for: canonical, now: now, isEnabled: { true }, currentFixture: { _, _ in canonical },
                programmeMatches: { _, _ in [good.registryMatch!, bad.registryMatch!] })
            XCTAssertEqual(result.map(\.providerName), ["TV2"])
        }
    }

    func testSelectedESPNRenewalKeepsItsChannelAndCannotSubstituteAnotherAssignment() async throws {
        let original = footballAssignment(at: now), canonical = StreamPlaybackRequest(event: original.preferredEvent!)
        let initial = try ReviewedTVPlaylistClient.session(for: original,
            delivery: URL(string: "https://barinaslive1.boldmss.com/reviewed-espn/index.m3u8")!, at: now)
        let later = now.addingTimeInterval(91)
        let current = footballAssignment(at: later, fixture: original.preferredEvent)
        let sibling = footballAssignment(at: later, providerName: "TV3", fixture: original.preferredEvent)
        let payload = espnPlaylist(url: "https://barinaslive1.boldmss.com/fresh-espn/index.m3u8"), log = TVFetchLog()
        let client = ReviewedTVPlaylistClient(fetch: { request in
            _ = await log.fetched(request)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { _ in })
        let wrong = await client.refreshedDescriptor(for: initial, request: canonical, now: later,
            isEnabled: { true }, currentFixture: { _, _ in canonical }, programmeMatches: { _, _ in [sibling.registryMatch!] })
        XCTAssertNil(wrong)
        let untouched = await log.snapshot(); XCTAssertTrue(untouched.requests.isEmpty)
        let refreshed = await client.refreshedDescriptor(for: initial, request: canonical, now: later,
            isEnabled: { true }, currentFixture: { _, _ in canonical }, programmeMatches: { _, _ in [current.registryMatch!] })
        let next = try XCTUnwrap(refreshed)
        XCTAssertEqual(next.id, initial.id)
        XCTAssertEqual(next.providerName, "TV2")
        XCTAssertEqual(next.eventBinding?.streamID, initial.eventBinding?.streamID)
        XCTAssertNotEqual(next.playableURL, initial.playableURL)
    }

    func testFixtureOptOutDuringPlaylistDestinationPreflightStopsTheFetch() async throws {
        let assigned = footballAssignment(at: now), canonical = StreamPlaybackRequest(event: assigned.preferredEvent!)
        let log = TVFetchLog(), enabled = TVEnablement(), payload = espnPlaylist()
        await enabled.set(true)
        let client = ReviewedTVPlaylistClient(fetch: { request in
            _ = await log.fetched(request)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { url in
            await log.validated(url)
            if url == ReviewedTVPlaylistClient.playlistURL { await enabled.set(false) }
        })
        do {
            _ = try await client.resolve(for: assigned, now: now, isEnabled: { await enabled.value }, currentFixture: { _, _ in canonical })
            XCTFail("Opting out during destination preparation must stop the new metadata request")
        } catch { }
        let observed = await log.snapshot(); XCTAssertTrue(observed.requests.isEmpty)
    }

    func testOptOutAfterMetadataCannotPublishAnAlreadyResolvedChannel() async throws {
        let assigned = footballAssignment(at: now), canonical = StreamPlaybackRequest(event: assigned.preferredEvent!)
        let log = TVFetchLog(), enabled = TVEnablement(), payload = espnPlaylist()
        await enabled.set(true)
        let client = ReviewedTVPlaylistClient(fetch: { request in
            _ = await log.fetched(request)
            return (payload, HTTPURLResponse(url: ReviewedTVPlaylistClient.playlistURL, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { await log.validated($0) })
        do {
            _ = try await client.resolve(for: assigned, now: now, isEnabled: { await enabled.value }, currentFixture: { _, _ in
                let completed = await log.snapshot()
                if completed.destinations.count >= 2 { await enabled.set(false) }
                return canonical
            })
            XCTFail("An opt-out during the post-metadata fixture check must discard resolved choices")
        } catch { }
        let observed = await log.snapshot(); XCTAssertEqual(observed.requests.count, 1)
    }

    func testVerifiedEarlyCoverageOffersWatchWithoutMovingKickoffOrDeclaringLive() async throws {
        let squad = SportsFixtureCatalog.Squad(gender: .men, ageGroup: "senior")
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:tv-football", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "Arsenal vs Chelsea",
            participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")], squad: squad,
            status: .scheduled, observedAt: now, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(1800).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata)
        let request = footballAssignment(at: now, fixture: event, lead: 1800), match = try XCTUnwrap(request.registryMatch)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "early-coverage",
            generatedAt: now, providers: [match.provider], broadcasts: [match.broadcast], links: [try XCTUnwrap(match.link)])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(snapshot), suite = "TVEarlyCoverage." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let client = BroadcastRegistryClient(defaults: defaults, fetch: { req in
            (bytes, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        })
        let refreshed = await client.refresh(at: now, force: true)
        XCTAssertNotNil(refreshed)
        let index = FixtureStreamDiscoveryIndex(); index.updateEnabledProviders(["reviewedtv"], revision: 1)
        let policy = MatchStartPolicy(event: event, now: now, discoveryIndex: index, broadcastRegistry: client)
        XCTAssertTrue(policy.timingAllowsPlayback); XCTAssertNil(policy.upcomingStart)
        XCTAssertEqual(event.kickoffDate, now.addingTimeInterval(1800)); XCTAssertFalse(event.sportsFixture?.isLive(at: now) == true)
        index.updateEnabledProviders([], revision: 2)
        XCTAssertFalse(MatchStartPolicy(event: event, now: now, discoveryIndex: index, broadcastRegistry: client).timingAllowsPlayback)
    }

    func testScheduledMLBAndNHLGuideAssignmentsPreserveOfficialSquadAndUseTheExistingResolver() throws {
        for (sport, competition, names) in [("baseball", "mlb", ["Milwaukee Brewers", "Tampa Bay Rays"]),
            ("hockey", "nhl", ["New Jersey Devils", "Edmonton Oilers"])] {
        let squad = SportsFixtureCatalog.Squad(gender: .men, ageGroup: "senior")
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV3"))
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:\(competition):test", sport: sport,
            competitionID: competition, competitionName: competition.uppercased(), eventKind: .match, title: names.joined(separator: " vs "),
            participants: [.init(id: "a", name: names[0]), .init(id: "b", name: names[1])], squad: squad,
            status: .scheduled, observedAt: now, verified: true)
        let kickoff = now.addingTimeInterval(1_200), expiry = now.addingTimeInterval(600)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: sport,
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: names[0], badge: nil), away: .init(name: names[1], badge: nil)), sportsFixture: metadata)
        let broadcast = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "c", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:assignment:" + String(repeating: "c", count: 64), streamID: channel.streamID,
            resourceType: "tv", scope: sport, kind: .event, sport: sport, title: metadata.title,
            participants: names, start: now, competitionID: competition, squad: squad,
            channelID: channel.channelID, stationMarket: "UY", observedAt: now, expiresAt: expiry, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: broadcast.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .channelAssignment,
            fixtureFingerprint: .init(fixtureID: event.id, sport: sport, start: kickoff, participants: names,
                competitionID: competition, squad: squad), expiresAt: expiry, startRelation: "channel-coverage")
        let provider = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: sport, status: .partial,
            complete: false, observedAt: now, expiresAt: expiry)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "mlb-guide-test", generatedAt: now,
            providers: [provider], broadcasts: [broadcast], links: [link])
        let accepted = try BroadcastRegistrySnapshot.validated(from: snapshot.encoded(), at: now)
        let canonical = StreamPlaybackRequest(event: event)
        let match = try XCTUnwrap(accepted.lookup(for: canonical, enabledProviderCodes: ["reviewedtv"], at: now).first)
        XCTAssertTrue(match.admitsFreshIdentity(sport: sport, participants: names, start: now,
            providerEventID: broadcast.providerEventID, streamID: broadcast.streamID, at: now))
        let request = canonical.usingRegistryMatch(match)
        XCTAssertTrue(ReviewedTVPlaylistClient.supports(request, at: now))
        let session = try ReviewedTVPlaylistClient.session(for: request,
            delivery: URL(string: "https://barinaslive1.boldmss.com/test/espn2/index.m3u8")!, at: now)
        XCTAssertTrue(session.eventBinding?.matches(request: canonical, providerCode: "reviewedtv", at: now) == true)
        XCTAssertEqual(event.kickoffDate, kickoff)
        }
    }

    private func footballAssignment(at clock: Date, providerName: String = "TV2", fixture: EventReference? = nil,
                                    market: String = "UY", lead: TimeInterval = 1_200) -> StreamPlaybackRequest {
        let channel = ReviewedTVPlaylistClient.channel(forProviderName: providerName)!
        let squad = SportsFixtureCatalog.Squad(gender: .men, ageGroup: "senior")
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:tv-football", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "Arsenal vs Chelsea",
            participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")], squad: squad,
            status: .live, observedAt: clock, verified: true)
        let event = fixture ?? EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(clock.addingTimeInterval(-1_800).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata)
        let digit = String(providerName.dropFirst(2))
        let expiry = clock.addingTimeInterval(600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: digit, count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:assignment:" + String(repeating: digit, count: 64), streamID: channel.streamID,
            resourceType: "tv", scope: "football", kind: .event, sport: "football", title: "Arsenal vs Chelsea",
            participants: ["Arsenal", "Chelsea"], start: event.kickoffDate!.addingTimeInterval(-lead), competitionID: "premier-league",
            squad: squad, channelID: channel.channelID, stationMarket: market, observedAt: clock, expiresAt: expiry,
            verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .channelAssignment,
            fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: event.kickoffDate!, participants: ["Arsenal", "Chelsea"],
                competitionID: "premier-league", squad: squad), expiresAt: expiry, startRelation: "channel-coverage")
        let provider = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "football", status: .available,
            observedAt: clock, expiresAt: expiry)
        return StreamPlaybackRequest(event: event).usingRegistryMatch(.init(broadcast: record, link: link, provider: provider))
    }

    private func espnPlaylist(id: String = "ESPNLatinAmerica.us@South", label: String = "ESPN Latin America (1080p)",
                              url: String = "https://barinaslive1.boldmss.com/reviewed-espn/index.m3u8", directive: String? = nil) -> Data {
        playlist(id: id, label: label, url: url, directive: directive)
    }

    private func combinedPlaylist(_ rows: [Data]) -> Data {
        Data(("#EXTM3U\n" + rows.map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "#EXTM3U\n", with: "") }.joined()).utf8)
    }

    private func programmeRequest(at clock: Date, day: Int = 4, fixture: EventReference? = nil,
                                  programmeStart: Date? = nil, programmeEnd: Date? = nil) -> StreamPlaybackRequest {
        let start = clock.addingTimeInterval(-3 * 86_400), end = start.addingTimeInterval(5 * 86_400)
        let context = CricketMatchContext(innings: [.init(number: 1, teamID: "icc:1:7", runs: 300, wickets: 5)],
            currentInnings: 1, day: day, matchOrdinal: 3, matchEndsAt: stamp(end), phase: .inPlay)
        let metadata = CricketFixtureMetadata(fixtureID: "icc:269792", competitionID: "icc", competitionName: "ICC",
            format: .test, status: .live, observedAt: clock, verified: true, context: context,
            homeTeamID: "icc:1:7", awayTeamID: "icc:1:1")
        let event = fixture ?? EventReference(id: "cricket-fixture:icc:269792", title: "South Africa vs Australia", category: "cricket",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "South Africa", badge: nil), away: .init(name: "Australia", badge: nil)), cricketFixture: metadata)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "b", count: 64), streamID: ReviewedTVPlaylistClient.providerEventID,
            resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket", title: "South Africa vs Australia, 3rd Test Day 4",
            participants: ["South Africa", "Australia"], start: programmeStart ?? clock.addingTimeInterval(-3_600),
            end: programmeEnd ?? clock.addingTimeInterval(3_600), competitionID: "icc", format: .test, matchOrdinal: 3, day: day,
            channelID: CricketBroadcastChannel.willow.canonicalID, observedAt: clock, expiresAt: clock.addingTimeInterval(600), verification: .dated, issues: [])
        let fixtureContext = event.cricketFixture!.context!
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .programme, fixtureFingerprint: .init(fixtureID: event.id, sport: "cricket", start: event.kickoffDate!,
                participants: ["South Africa", "Australia"], competitionID: "icc", format: .test,
                matchOrdinal: fixtureContext.matchOrdinal, day: fixtureContext.day,
                end: fixtureContext.matchEndsAt.flatMap(BroadcastRegistrySnapshot.date)), expiresAt: record.expiresAt)
        let provider = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket", status: .available,
            observedAt: clock, expiresAt: record.expiresAt)
        return StreamPlaybackRequest(event: event).usingRegistryMatch(.init(broadcast: record, link: link, provider: provider))
    }

    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func request(_ channel: CricketBroadcastChannel = .willow) -> StreamPlaybackRequest {
        .init(event: CricketChannelCatalog.event(for: channel, in: []))
    }
    private func parse(_ data: Data) throws -> URL {
        try ReviewedTVPlaylistClient.willowDelivery(from: data, playlistURL: ReviewedTVPlaylistClient.playlistURL)
    }
    private func playlist(id: String = "Willow.us@SD", label: String = "Willow (720p)",
                          url: String? = nil, directive: String? = nil) -> Data {
        Data(("#EXTM3U\n#EXTINF:-1 tvg-id=\"\(id)\",\(label)\n"
            + (directive.map { $0 + "\n" } ?? "") + (url ?? delivery) + "\n").utf8)
    }
}

private actor TVFetchLog {
    private var requests: [URLRequest] = []
    private var destinations: [URL] = []
    func fetched(_ request: URLRequest) -> Int { requests.append(request); return requests.count }
    func validated(_ url: URL) { destinations.append(url) }
    func snapshot() -> (requests: [URLRequest], destinations: [URL]) { (requests, destinations) }
}

private actor TVEnablement {
    private(set) var value = false
    func set(_ value: Bool) { self.value = value }
}

private actor TVFixtureState {
    private(set) var value: StreamPlaybackRequest
    init(_ value: StreamPlaybackRequest) { self.value = value }
    func set(_ value: StreamPlaybackRequest) { self.value = value }
}
