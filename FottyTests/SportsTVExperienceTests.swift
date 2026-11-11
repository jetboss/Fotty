import XCTest
@testable import Fotty

@MainActor
final class SportsTVExperienceTests: XCTestCase {

    func testHomeOnAirListsOnlyChannelsThatOpenNowInTheTVTabOrder() throws {
        let suite = "FottyTests.OnAir.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = SportsTVLibrary(defaults: defaults)
        let ordered = library.sections(commentary: .english).flatMap(\.stations)
        let watchable = Set(ordered.suffix(3).map(\.id))
        let now = Date()
        func entries(sport: String? = nil, limit: Int = 2, canWatch: @escaping (SportsTVStation) -> Bool) -> [HomeOnAirPolicy.Entry] {
            HomeOnAirPolicy.entries(library: library, commentary: .english, snapshot: nil, sport: sport,
                                    at: now, limit: limit, canWatch: canWatch)
        }
        let open = entries { watchable.contains($0.id) }
        XCTAssertEqual(open.map(\.id), ordered.filter { watchable.contains($0.id) }.prefix(2).map(\.id),
                       "Home follows the TV tab's order and limit")
        XCTAssertTrue(open.allSatisfy { $0.programme == nil }, "No current guide means no programme claim")
        XCTAssertTrue(entries(canWatch: { _ in false }).isEmpty, "A channel that cannot open is never offered")
        let cricket = entries(sport: "cricket", limit: 20) { _ in true }
        XCTAssertFalse(cricket.isEmpty)
        XCTAssertTrue(cricket.allSatisfy(\.station.isCricket))
        XCTAssertTrue(entries(sport: "hockey", limit: 20) { _ in true }.isEmpty)
        XCTAssertTrue(entries(limit: 0) { _ in true }.isEmpty)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp(); suite = "Fotty.TVTests." + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite); defaults = nil; suite = nil; super.tearDown()
    }
    func testStationsRemainDistinctChannelsWithoutInventedMatchIdentity() throws {
        XCTAssertEqual(SportsTVStation.all.count, 25)
        XCTAssertEqual(SportsTVStation.configuredOriginCount, 11)
        let index = FixtureStreamDiscoveryIndex(); index.updateEnabledProviders(["reviewedtv"], revision: 1)
        for station in SportsTVStation.all where station.cricketChannel == nil {
            let event = station.event, request = StreamPlaybackRequest(event: event)
            XCTAssertTrue(event.isBroadcastChannel); XCTAssertNil(event.kickoffDate)
            XCTAssertNil(event.teams); XCTAssertNil(event.sportsFixture)
            XCTAssertEqual(SportsTVStation.identifying(request), station)
            XCTAssertEqual(CurrentEventBroadcastPolicy.currentEvent(for: event, in: [])?.id, station.id)
            XCTAssertEqual(RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [], at: now)?.matchID, event.id)
            XCTAssertTrue(MatchStartPolicy(event: event, now: now).timingAllowsPlayback)
            let playlistStation = station.provider != "CS-SkyMain"
            XCTAssertEqual(MatchStartPolicy(event: event, now: now, discoveryIndex: index).canAttemptPlayback, playlistStation)
            XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: event, in: [], at: now, discoveryIndex: index) != nil, playlistStation)
            XCTAssertEqual(Set(CuratedStreamSourceCatalog.discoveryPlan(for: request, enabledProviderCodes: ["reviewedtv", "communitysports"], at: now).optionalSources.map(\.providerCode)),
                !playlistStation ? ["communitysports"] : ["TV10", "TV11", "TV24"].contains(station.provider) ? ["communitysports", "reviewedtv"] : ["reviewedtv"])
            XCTAssertEqual(CuratedStreamSourceCatalog.discoveryPlan(for: request, enabledProviderCodes: ["reviewedtv"], at: now).optionalSources.map(\.providerCode), playlistStation ? ["reviewedtv"] : [])
        }
        index.updateEnabledProviders([], revision: 2)
        let disabled = try XCTUnwrap(SportsTVStation.station(provider: "TV2"))
        XCTAssertFalse(MatchStartPolicy(event: disabled.event, now: now, discoveryIndex: index).canAttemptPlayback)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: disabled.event, in: [], at: now, discoveryIndex: index))
    }
    func testCricketStationsHaveOneVisibleTVHomeAndKeepTheirExistingResolvers() throws {
        let library = SportsTVLibrary(defaults: defaults)
        let groups = library.sections(commentary: .english)
        let cricket = try XCTUnwrap(groups.first { $0.id == "Cricket channels" })
        XCTAssertEqual(cricket.stations.map(\.id), [CricketBroadcastChannel.willow.canonicalID,
            CricketBroadcastChannel.foxCricket.canonicalID, "sports-channel:sky-sports-cricket", "sports-channel:cricket-gold"])
        let IDs = groups.flatMap { $0.stations.map(\.id) }
        XCTAssertEqual(Set(IDs).count, SportsTVStation.all.count)
        XCTAssertEqual(IDs.count, Set(IDs).count, "No channel is repeated between Cricket and language sections")
        let index = FixtureStreamDiscoveryIndex(); index.updateEnabledProviders(["communitysports"], revision: 1)
        let fox = try XCTUnwrap(SportsTVStation.station(id: CricketBroadcastChannel.foxCricket.canonicalID))
        let request = StreamPlaybackRequest(event: fox.event)
        XCTAssertEqual(CricketBroadcastChannel.identifying(request: request), .foxCricket)
        XCTAssertNil(SportsTVStation.identifying(request), "Fox must use its canonical CS channel owner, not a fabricated playlist profile")
        XCTAssertTrue(MatchStartPolicy(event: fox.event, now: now, discoveryIndex: index).canAttemptPlayback)
        let plan = CuratedStreamSourceCatalog.discoveryPlan(for: request, enabledProviderCodes: ["reviewedtv", "communitysports"], at: now)
        XCTAssertEqual(plan.optionalSources.map(\.providerCode), ["communitysports"])
        index.updateEnabledProviders([], revision: 2)
        XCTAssertFalse(MatchStartPolicy(event: fox.event, now: now, discoveryIndex: index).canAttemptPlayback)
    }
    func testTVGroupingPreservesPersonalOrderAndAllLanguageChoicesWithoutDuplicates() throws {
        let library = SportsTVLibrary(defaults: defaults)
        let willow = CricketBroadcastChannel.willow.canonicalID, fox = CricketBroadcastChannel.foxCricket.canonicalID
        library.toggleFavourite(willow); library.recordPlayed(fox)
        for language in CommentaryPreference.allCases {
            let sections = library.sections(commentary: language)
            XCTAssertEqual(sections[0].id, "Favourites"); XCTAssertEqual(sections[0].stations.map(\.id), [willow])
            XCTAssertEqual(sections[1].id, "Recently watched"); XCTAssertEqual(sections[1].stations.map(\.id), [fox])
            let all = sections.flatMap { $0.stations.map(\.id) }
            XCTAssertEqual(all.count, SportsTVStation.all.count); XCTAssertEqual(Set(all).count, all.count)
        }
        XCTAssertEqual(defaults.stringArray(forKey: SportsTVLibrary.favouritesKey), [willow])
        XCTAssertEqual(defaults.stringArray(forKey: SportsTVLibrary.recentKey), [fox])
    }

    func testTVSearchAndFiltersNeverMutateLibraryOrLoseAllChannelReset() throws {
        let library = SportsTVLibrary(defaults: defaults)
        let willow = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        library.toggleFavourite(willow.id)
        func rows(_ filter: SportsTVLibrary.Filter, _ query: String = "") -> [SportsTVStation] {
            library.sections(commentary: .english, filter: filter, query: query, snapshot: nil, at: now).flatMap(\.stations)
        }
        XCTAssertEqual(rows(.favourites).map(\.id), [willow.id])
        XCTAssertEqual(rows(.all, " willow   cricket ").map(\.id), [willow.id])
        XCTAssertTrue(rows(.english).allSatisfy { $0.language == .english })
        XCTAssertTrue(rows(.all, "unlisted station").isEmpty)
        XCTAssertEqual(Set(rows(.all).map(\.id)), Set(SportsTVStation.all.map(\.id)))
        XCTAssertEqual(library.favourites, [willow.id])
        XCTAssertTrue(library.recent.isEmpty)
    }

    func testGuideProgressNeedsExplicitCurrentProgrammeBoundaries() {
        let entry = SportsTVGuidePolicy.Entry(id: "programme", title: "A v B", start: now,
            end: now.addingTimeInterval(3600), sport: "football")
        XCTAssertEqual(entry.progress(at: now), 0)
        XCTAssertEqual(entry.progress(at: now.addingTimeInterval(1800)), 0.5)
        XCTAssertNil(entry.progress(at: now.addingTimeInterval(-1)))
        XCTAssertNil(entry.progress(at: now.addingTimeInterval(3600)))
        let futureOnly = SportsTVGuidePolicy.Entry(id: "start-only", title: "C v D", start: now, end: nil, sport: "football")
        XCTAssertNil(futureOnly.progress(at: now.addingTimeInterval(30)))
    }

    func testWatchSourcesExposeStationIdentityWithoutPretendingUnknownQuality() {
        XCTAssertEqual(BroadcastSourcePresentation.watchTitle(provider: "TV1", number: 2), "Willow Cricket")
        XCTAssertEqual(BroadcastSourcePresentation.watchTitle(provider: "CS4", number: 3), "Broadcast 3")
        XCTAssertEqual(BroadcastSourcePresentation.watchDescription(provider: "CS4", qualityLabel: "English · HD"),
            "CS4 · Listed: English · HD")
        XCTAssertNil(BroadcastSourcePresentation.watchDescription(provider: "unreviewed", qualityLabel: "https://private.invalid/HD"))
        XCTAssertFalse((BroadcastSourcePresentation.watchDescription(provider: "TV1", qualityLabel: nil) ?? "").contains("Native"))
    }

    func testForgedStationTitleDateCategoryOrOpponentCannotBorrowAChannelBinding() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV2"))
        let valid = StreamPlaybackRequest(event: station.event)
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forChannelID: station.id))
        func binding(_ request: StreamPlaybackRequest, provider: String = "reviewedtv") -> StreamEventBinding? {
            .init(request: request, providerCode: provider, providerEventID: channel.streamID, streamID: channel.streamID,
                  manifestRevision: "test", verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now)
        }
        XCTAssertNotNil(binding(valid)); XCTAssertNil(binding(valid, provider: "communitysports"))
        for request in [StreamPlaybackRequest(matchID: valid.matchID, displayTitle: "Different station", homeTeam: valid.homeTeam, awayTeam: "", category: "other"),
                        .init(matchID: valid.matchID, displayTitle: valid.displayTitle, homeTeam: valid.homeTeam, awayTeam: "Arsenal", category: "other"),
                        .init(matchID: valid.matchID, displayTitle: valid.displayTitle, homeTeam: valid.homeTeam, awayTeam: "", category: "football"),
                        .init(matchID: valid.matchID, displayTitle: valid.displayTitle, homeTeam: valid.homeTeam, awayTeam: "", category: "other", kickoffDate: now)] {
            XCTAssertNil(SportsTVStation.identifying(request)); XCTAssertNil(binding(request))
        }
        let original = try XCTUnwrap(binding(valid))
        let other = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        XCTAssertFalse(original.matchesIdentity(request: StreamPlaybackRequest(event: other.event), providerCode: "reviewedtv"))
    }
    func testDisabledTVChannelStopsBeforeAnyPlaylistRequest() async throws {
        let client = ReviewedTVPlaylistClient(fetch: { _ in XCTFail("Disabled source must not fetch"); throw URLError(.cancelled) },
            validateDestination: { _ in XCTFail("Disabled source must not resolve an origin") })
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV2"))
        do { _ = try await client.resolve(for: StreamPlaybackRequest(event: station.event), now: now, isEnabled: { false }); XCTFail("Disabled") }
        catch { }
    }
    func testNormalStationLookupResolvesTheSelectedStationAndPreservesBinding() async throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let definition = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: station.provider))
        let playlist = Data(("#EXTM3U\n#EXTINF:-1 tvg-id=\"" + definition.playlistIdentifier
            + "\",ESPN 2 Latin America (1080p)\nhttps://barinaslive1.boldmss.com/test/espn2/index.m3u8\n").utf8)
        let client = ReviewedTVPlaylistClient(fetch: { req in
            (playlist, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
        }, validateDestination: { _ in })
        let request = StreamPlaybackRequest(event: station.event)
        let sessions = try await client.resolve(for: request, now: now, isEnabled: { true })
        XCTAssertEqual(sessions.count, 1); XCTAssertEqual(sessions.first?.providerName, "TV3")
        XCTAssertTrue(sessions.first?.requiresGuardedRelay == true)
        XCTAssertTrue(sessions.first?.eventBinding?.matches(request: request, providerCode: "reviewedtv", at: now) == true)
        XCTAssertNil(request.registryMatch, "Channel playback makes no fixture/programme claim")
    }

    func testLanguagePreferencesKeepUnknownAndOtherLanguagesAvailable() {
        XCTAssertEqual(CommentaryPreference.saved(in: defaults), .english)
        XCTAssertEqual(CommentaryPreference.any.preferenceRank(for: .spanish), 0)
        XCTAssertEqual(CommentaryPreference.english.preferenceRank(for: .english), 0)
        XCTAssertLessThan(CommentaryPreference.english.preferenceRank(for: nil), CommentaryPreference.english.preferenceRank(for: .spanish))
        defaults.set("unreviewed", forKey: CommentaryPreference.storageKey)
        XCTAssertEqual(CommentaryPreference.saved(in: defaults), .english)
        defaults.set(CommentaryPreference.any.rawValue, forKey: CommentaryPreference.storageKey)
        XCTAssertEqual(CommentaryPreference.saved(in: defaults), .any, "Preserve an explicit choice of any language")
    }
    func testEnglishStationsKeepTheirOwnIdentityAndGuardedDelivery() async throws {
        for provider in ["TV9"] {
            let station = try XCTUnwrap(SportsTVStation.station(provider: provider))
            let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: provider))
            XCTAssertEqual(station.language, .english)
            XCTAssertEqual(channel.markets, ["US"])
            let host = try XCTUnwrap(channel.allowedDeliveryHosts.first)
            let label = channel.displayName
            let query = channel.reviewedPlaylistQuery.map { "?" + $0 } ?? ""
            let delivery = URL(string: "https://\(host)/synthetic/index.m3u8\(query)")!
            let playlist = Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"\(channel.playlistIdentifier)\",\(label) (720p)\n\(delivery.absoluteString)\n".utf8)
            let client = ReviewedTVPlaylistClient(fetch: { request in
                (playlist, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
            }, validateDestination: { _ in })
            let request = StreamPlaybackRequest(event: station.event)
            let sessions = try await client.resolve(for: request, now: now, isEnabled: { true })
            let session = try XCTUnwrap(sessions.first)
            XCTAssertEqual(sessions.count, 1); XCTAssertEqual(session.providerName, provider)
            XCTAssertEqual(session.playableURL, delivery); XCTAssertTrue(session.requiresGuardedRelay == true)
            XCTAssertTrue(session.eventBinding?.matches(request: request, providerCode: "reviewedtv", at: now) == true)
            if let query = channel.reviewedPlaylistQuery {
                let base = "https://\(host)/synthetic/index.m3u8"
                for changed in [base, base + "?" + query + "&token=x", base + "?" + query + "&" + query,
                                base + "?" + query + "0", base + "?ads.xumo_channelId=00000000"] {
                    XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: changed)!, channel: channel))
                }
            }
            XCTAssertNil(request.registryMatch, "A channel is not proof of a fixture's programme")
            XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(delivery), "Never substitute an English station for main Willow")
            for invalid in ["http://\(host)/a.m3u8", "https://\(host):8443/a.m3u8", "https://\(host)/a.m3u8?token=x",
                            "https://child.\(host)/a.m3u8", "https://barinaslive1.boldmss.com/a.m3u8"] {
                XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: invalid)!, channel: channel))
            }
        }
        XCTAssertEqual(SportsTVStation.all.filter { $0.language == .spanish }.count, 7)
    }
    func testCoreEnglishChannelsUseTheirReviewedPlaylistAndPreservePublishedHeaders() async throws {
        for provider in (10...15).map({ "TV\($0)" }) {
            let station = try XCTUnwrap(SportsTVStation.station(provider: provider))
            let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: provider))
            XCTAssertEqual(station.language, .english)
            XCTAssertFalse(channel.markets.contains("UY"))
            let target = try coreDelivery(channel)
            let data = corePlaylist(channel, delivery: target)
            let client = ReviewedTVPlaylistClient(fetch: { request in
                XCTAssertEqual(request.url, ReviewedTVPlaylistClient.englishPlaylistURL)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain"])!)
            }, validateDestination: { _ in })
            let request = StreamPlaybackRequest(event: station.event)
            let sessions = try await client.resolve(for: request, now: now, isEnabled: { true })
            let selected = try XCTUnwrap(sessions.first)
            XCTAssertEqual(sessions.count, 1); XCTAssertEqual(selected.providerName, provider)
            XCTAssertEqual(selected.playableURL, target)
            XCTAssertEqual(selected.requiredHeaders, channel.playbackUserAgent.map { ["User-Agent": $0] } ?? [:])
            XCTAssertTrue(selected.requiresGuardedRelay == true)
            XCTAssertTrue(selected.eventBinding?.matches(request: request, providerCode: "reviewedtv", at: now) == true)
            XCTAssertEqual(selected.expiryTime, now.addingTimeInterval(90))
            XCTAssertNil(request.registryMatch)
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: data,
                playlistURL: ReviewedTVPlaylistClient.playlistURL, channel: channel))
        }
    }
    func testDiscoveredEnglishStationsUseOriginalFreshMetadataAndKeepTheirOwnBindings() async throws {
        for provider in ["TV17", "TV21", "TV22", "TV23", "TV24"] {
            let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: provider))
            let station = try XCTUnwrap(SportsTVStation.station(provider: provider))
            let target = try coreDelivery(channel), data = corePlaylist(channel, delivery: target)
            XCTAssertEqual(channel.commentaryLanguage, .english)
            XCTAssertEqual(channel.markets, ["TV17", "TV24"].contains(provider) ? ["US"] : provider == "TV23" ? ["AU"] : ["GB"])
            XCTAssertEqual(channel.playlistURL, ["TV17", "TV24"].contains(provider) ? ReviewedTVPlaylistClient.playlistURL : provider == "TV23" ? ReviewedTVPlaylistClient.australianPlaylistURL : ReviewedTVPlaylistClient.ukPlaylistURL)
            let client = ReviewedTVPlaylistClient(fetch: { query in
                XCTAssertEqual(query.url, channel.playlistURL)
                XCTAssertEqual(query.cachePolicy, .reloadIgnoringLocalCacheData)
                XCTAssertNil(query.value(forHTTPHeaderField: "Cookie"))
                XCTAssertNil(query.value(forHTTPHeaderField: "Authorization"))
                return (data, HTTPURLResponse(url: query.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain"])!)
            }, validateDestination: { _ in })
            let request = StreamPlaybackRequest(event: station.event)
            XCTAssertNil(CricketBroadcastChannel.identifying(request: request))
            let sessions = try await client.resolve(for: request, now: now, isEnabled: { true })
            let selected = try XCTUnwrap(sessions.first)
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(selected.providerName, provider)
            XCTAssertEqual(selected.matchID, station.id)
            XCTAssertEqual(selected.playableURL, target)
            XCTAssertTrue(selected.requiredHeaders.isEmpty)
            XCTAssertTrue(selected.requiresGuardedRelay == true)
            XCTAssertNil(selected.qualityLabel, "A listed pixel label is not measured playback quality")
            XCTAssertEqual(selected.eventBinding?.streamID, channel.streamID)
            XCTAssertEqual(selected.eventBinding?.providerEventID, channel.streamID)
            XCTAssertNil(request.registryMatch, "A channel makes no current-fixture programme claim")
            let renewed = await client.refreshedDescriptor(for: selected, request: request,
                now: now.addingTimeInterval(91), isEnabled: { true })
            XCTAssertEqual(renewed?.id, selected.id)
            XCTAssertEqual(renewed?.eventBinding?.streamID, channel.streamID)
            XCTAssertGreaterThan(try XCTUnwrap(renewed?.expiryTime), selected.expiryTime!)
            do {
                _ = try await client.resolve(for: request, now: now, isEnabled: { false })
                XCTFail("Disabled TV must not resolve the discovered channel")
            } catch { }
        }
    }

    func testDiscoveredStationContractRejectsWrongIdentityPathHeadersAndProvenance() throws {
        for provider in ["TV17", "TV21", "TV22", "TV23", "TV24"] {
            let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: provider))
            let target = try coreDelivery(channel), good = corePlaylist(channel, delivery: target)
            XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: good,
                playlistURL: channel.playlistURL, channel: channel), target)
            let host = try XCTUnwrap(target.host)
            for value in ["http://\(host)\(target.path)", "https://\(host)/another-channel/master.m3u8",
                          target.absoluteString + "?token=unreviewed", target.absoluteString + "#fragment",
                          "https://\(host):8443\(target.path)", "https://127.0.0.1\(target.path)"] {
                XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: value)!, channel: channel))
            }
            let text = String(decoding: good, as: UTF8.self)
            for mutation in [text.replacingOccurrences(of: channel.playlistIdentifier, with: "Willow.us@SD"),
                             text.replacingOccurrences(of: channel.displayName, with: "Willow Cricket"),
                             text.replacingOccurrences(of: target.absoluteString,
                                 with: "#EXTHTTP:{\"Authorization\":\"unreviewed\"}\n" + target.absoluteString),
                             text.replacingOccurrences(of: target.absoluteString,
                                 with: "#KODIPROP:inputstream.adaptive.license_key=unreviewed\n" + target.absoluteString)] {
                XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: Data(mutation.utf8),
                    playlistURL: channel.playlistURL, channel: channel))
            }
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: good,
                playlistURL: URL(string: "https://raw.githubusercontent.com/bugsfreeweb/LiveTVCollector/main/LiveTV/USA/LiveTV.m3u")!,
                channel: channel), "The discovery directory is not accepted playback provenance")
        }
        XCTAssertNil(SportsTVStation.station(provider: "TV16"), "Refused CBS media must not be offered")
        XCTAssertNil(SportsTVStation.station(provider: "TV18"), "Refused Fubo media must not be offered")
        XCTAssertNil(SportsTVStation.station(provider: "TV19"), "Refused Willow Sports media must not be offered")
        XCTAssertFalse(ReviewedTVPlaylistClient.supports(StreamPlaybackRequest(event:
            .init(id: "unassigned-cricket", title: "India vs Australia", category: "cricket", date: nil,
                poster: nil, popular: false, teams: nil)), at: now))
    }

    func testCoreEnglishContractsRejectChannelSubstitutionTokenChangesAndHeaderInstructions() throws {
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV10"))
        let target = try coreDelivery(channel), data = corePlaylist(channel, delivery: target)
        XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: data,
            playlistURL: channel.playlistURL, channel: channel), target)
        let host = try XCTUnwrap(target.host), path = try XCTUnwrap(channel.deliveryPath)
        for invalid in ["http://\(host)\(path)?token=" + String(repeating: "a", count: 48),
                        "https://\(host)\(path)", "https://\(host)\(path)?token=", "https://\(host)\(path)?token=short",
                        target.absoluteString + "&token=" + String(repeating: "a", count: 48),
                        target.absoluteString + "&other=x", target.absoluteString + "#fragment",
                        "https://\(host)/unreviewed/playlist.m3u8?token=" + String(repeating: "a", count: 48)] {
            XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: invalid)!, channel: channel))
        }
        for mutation in [String(decoding: data, as: UTF8.self).replacingOccurrences(of: channel.playlistIdentifier, with: "SkySp.Fball.uk"),
                         String(decoding: data, as: UTF8.self).replacingOccurrences(of: channel.displayName, with: "Sky Sports Football"),
                         String(decoding: data, as: UTF8.self).replacingOccurrences(of: "#EXTVLCOPT:http-user-agent=", with: "#EXTVLCOPT:http-referrer="),
                         String(decoding: data, as: UTF8.self).replacingOccurrences(of: "#EXTVLCOPT:http-user-agent=" + channel.playbackUserAgent! + "\n", with: ""),
                         String(decoding: data, as: UTF8.self).replacingOccurrences(of: target.absoluteString, with: "#EXTHTTP:{\"Authorization\":\"unreviewed\"}\n" + target.absoluteString)] {
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.delivery(from: Data(mutation.utf8),
                playlistURL: channel.playlistURL, channel: channel))
        }
    }
    private func coreDelivery(_ channel: ReviewedTVPlaylistClient.ChannelDefinition) throws -> URL {
        let host = try XCTUnwrap(channel.allowedDeliveryHosts.first), path = try XCTUnwrap(channel.deliveryPath)
        let query = channel.playbackUserAgent == nil ? "" : "?token=" + String(repeating: "a", count: 48)
        return try XCTUnwrap(URL(string: "https://\(host)\(path)\(query)"))
    }
    private func corePlaylist(_ channel: ReviewedTVPlaylistClient.ChannelDefinition, delivery: URL) -> Data {
        let header = channel.playbackUserAgent.map { "#EXTVLCOPT:http-user-agent=" + $0 + "\n" } ?? ""
        return Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"\(channel.playlistIdentifier)\",\(channel.displayName)\n\(header)\(delivery.absoluteString)\n".utf8)
    }
    func testEnglishUSStationsCannotBorrowUruguayProgrammeGuide() throws {
        for provider in ((9...15).map({ "TV\($0)" }) + ["TV17", "TV21", "TV22", "TV23", "TV24"]) {
            let station = try XCTUnwrap(SportsTVStation.station(provider: provider))
            let row = SportsTVGuideItem(id: "tv-guide:" + String(repeating: "a", count: 64), channelID: station.id,
                market: "UY", sport: "football", title: "Premier League", start: now.addingTimeInterval(600), observedAt: now,
                expiresAt: now.addingTimeInterval(3600))
            XCTAssertFalse(row.isValid(generatedAt: now))
        }
    }
    func testFavouritesAndRecentsAreBoundedLocalStationIDs() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV4"))
        defaults.set([station.id, station.id, "https://private.invalid/stream"], forKey: SportsTVLibrary.favouritesKey)
        defaults.set(SportsTVStation.all.map(\.id), forKey: SportsTVLibrary.recentKey)
        let library = SportsTVLibrary(defaults: defaults)
        XCTAssertEqual(library.recent.count, 6)
        XCTAssertEqual(library.favourites, [station.id]); library.toggleFavourite(station.id); XCTAssertTrue(library.favourites.isEmpty)
        defaults.removeObject(forKey: SportsTVLibrary.recentKey)
        let fresh = SportsTVLibrary(defaults: defaults)
        fresh.toggleFavourite(station.id); fresh.recordPlayed(station.id); fresh.recordPlayed(station.id)
        XCTAssertEqual(fresh.recent, [station.id]); fresh.recordPlayed("unreviewed"); XCTAssertEqual(fresh.recent.count, 1)
        for station in SportsTVStation.all { fresh.recordPlayed(station.id) }
        XCTAssertEqual(fresh.recent.count, 6)
        XCTAssertEqual(fresh.orderedStations.first?.id, station.id)
        XCTAssertFalse(defaults.dictionaryRepresentation().description.contains("private.invalid"))
        fresh.clearRecent()
        XCTAssertTrue(fresh.recent.isEmpty); XCTAssertEqual(fresh.favourites, [station.id])
        XCTAssertNil(defaults.object(forKey: SportsTVLibrary.recentKey))
    }
    func testOneDeliveryOriginIsNotSevenIndependentBackups() {
        let sessions = (2...8).map { session("TV\($0)", host: "shared.example", path: "\($0).m3u8") }
        XCTAssertEqual(SourceDeliveryDiversity.distinctOriginCount(sessions), 1)
        let other = session("AS1", host: "other.example", path: "live.m3u8")
        XCTAssertEqual(SourceDeliveryDiversity.distinctOriginCount(sessions + [other]), 2)
        let preferred = SourceDeliveryDiversity.prioritisingDifferentOrigin(sessions + [other], after: sessions[0].legacySource)
        XCTAssertEqual(preferred.first?.id, other.id)
        XCTAssertEqual(Set(preferred.map(\.id)), Set((sessions + [other]).map(\.id)))
    }
    func testContinuityNeedsAdvancingSustainedPlaybackWithNoStalls() {
        XCTAssertTrue(SinglePlaybackContinuityStore.qualifies(elapsed: 90, mediaAdvance: 89, stalls: 0))
        for values in [(89.0, 89.0, 0), (90, 2, 0), (90, 89, 1), (90, 1000, 0), (Double.nan, 89, 0)] {
            XCTAssertFalse(SinglePlaybackContinuityStore.qualifies(elapsed: values.0, mediaAdvance: values.1, stalls: values.2))
        }
        let stream = session("TV2", host: "shared.example", path: "channel.m3u8").legacySource
        SinglePlaybackContinuityStore.record(stream, elapsed: 90, mediaAdvance: 89, stalls: 0, at: now, defaults: defaults)
        XCTAssertTrue(SinglePlaybackContinuityStore.hasRecentHold(stream, at: now, defaults: defaults))
        XCTAssertFalse(SinglePlaybackContinuityStore.hasRecentHold(stream, at: now.addingTimeInterval(-1), defaults: defaults))
        XCTAssertFalse(SinglePlaybackContinuityStore.hasRecentHold(stream, at: now.addingTimeInterval(86401), defaults: defaults))
        XCTAssertFalse(String(data: defaults.data(forKey: SinglePlaybackContinuityStore.storageKey)!, encoding: .utf8)!.contains("shared.example"))
    }
    func testSpoilerModeOnlySuppressesTheRetainedWatchedMatch() {
        let protection = WatchingSpoilerProtection()
        let event = EventReference(id: "privacy-match", title: "Arsenal vs Chelsea", category: "football", date: Int64(now.timeIntervalSince1970), poster: nil, popular: false,
            teams: nil)
        protection.setActiveEvent(event); defaults.set(true, forKey: WatchingSpoilerProtection.preferenceKey)
        XCTAssertTrue(protection.protects(event, defaults: defaults))
        XCTAssertTrue(protection.suppressesGoal(home: "Arsenal", away: "Chelsea", kickoff: now, defaults: defaults))
        XCTAssertFalse(protection.suppressesGoal(home: "Liverpool", away: "Chelsea", kickoff: now, defaults: defaults))
        XCTAssertFalse(protection.suppressesGoal(home: "Arsenal", away: "Chelsea", kickoff: now.addingTimeInterval(86400), defaults: defaults))
        protection.setActiveEvent(nil)
        XCTAssertFalse(protection.suppressesGoal(home: "Arsenal", away: "Chelsea", kickoff: now, defaults: defaults))
    }
    func testDatedGuideWithoutAnEndNeverClaimsNowAndKeepsOriginalExpiry() throws {
        let row = guide(start: now.addingTimeInterval(600))
        XCTAssertTrue(row.isValid(generatedAt: now))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "guide-test", generatedAt: now,
            providers: [], broadcasts: [], links: [], tvGuide: [row])
        let station = try XCTUnwrap(SportsTVStation.station(id: row.channelID))
        let entries = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now)
        XCTAssertEqual(entries.count, 1); XCTAssertFalse(entries[0].isOnNow(at: row.start))
        XCTAssertTrue(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: row.expiresAt).isEmpty)
    }
    func testCurrentWillowGuideNeedsOneUnexpiredCorroboratedMatch() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let broadcast = BroadcastRegistrySnapshot.Broadcast(
            id: "br:" + String(repeating: "a", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "b", count: 64),
            streamID: "reviewed-tv:willow-main", resourceType: "tv", scope: "cricket",
            kind: .programme, sport: "cricket", title: "New Zealand vs. India",
            participants: ["New Zealand", "India"], start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(3600), format: .odi, matchOrdinal: 1,
            channelID: station.id, observedAt: now, expiresAt: now.addingTimeInterval(600),
            verification: .dated, issues: [])
        func link(_ state: BroadcastRegistrySnapshot.LinkState = .listed, expiry: TimeInterval = 120,
                  fixture: String = "cricket-fixture:icc:1", reason: String? = nil) -> BroadcastRegistrySnapshot.Link {
            .init(fixtureID: fixture, broadcastID: broadcast.id, providerCode: "reviewedtv",
                  state: state, matchMethod: .programme,
                  fixtureFingerprint: .init(fixtureID: fixture, sport: "cricket",
                      start: now.addingTimeInterval(-3600), participants: broadcast.participants,
                      format: .odi, matchOrdinal: 1), expiresAt: now.addingTimeInterval(expiry), reason: reason)
        }
        func entries(_ links: [BroadcastRegistrySnapshot.Link],
                     status: BroadcastRegistrySnapshot.CoverageStatus = .available,
                     lastSuccess: Date? = nil, providerExpiry: TimeInterval = 600,
                     elapsed: TimeInterval = 0) -> [SportsTVGuidePolicy.Entry] {
            let provider = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket",
                status: status, observedAt: now, lastSuccessAt: lastSuccess,
                expiresAt: now.addingTimeInterval(providerExpiry))
            let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "willow-guide-regression",
                generatedAt: now, providers: [provider], broadcasts: [broadcast], links: links)
            return SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now.addingTimeInterval(elapsed))
        }
        XCTAssertEqual(entries([link()]).map(\.title), [broadcast.title])
        XCTAssertTrue(entries([link()])[0].isOnNow(at: now))
        XCTAssertTrue(entries([]).isEmpty, "Fresh programme text alone cannot claim a completed match is on now")
        XCTAssertTrue(entries([link(.needsVerification, reason: "terminal-fixture")]).isEmpty)
        XCTAssertTrue(entries([link(.conflicting, reason: "time-conflict")]).isEmpty)
        XCTAssertTrue(entries([link(), link(fixture: "cricket-fixture:icc:2")]).isEmpty)
        XCTAssertTrue(entries([link()], elapsed: 120).isEmpty, "The programme interval cannot renew a fixture association")
        XCTAssertTrue(entries([link()], providerExpiry: 0).isEmpty)
        XCTAssertTrue(entries([link()], status: .failed).isEmpty)
        XCTAssertEqual(entries([link()], status: .failed, lastSuccess: now).count, 1,
                       "A temporary refresh failure preserves an accepted, unexpired association")
        XCTAssertTrue(entries([link()], status: .failed, lastSuccess: now, elapsed: 120).isEmpty)
        XCTAssertTrue(entries([link()], status: .empty).isEmpty)
    }

    func testSinglePlayerGuideRequiresExactStationIdentityNotFixtureTitle() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let channel = station.event
        XCTAssertEqual(SinglePlayerStationGuideProjection(event: channel, snapshot: nil, at: now)?.station.id, station.id)
        let fixture = EventReference(id: station.id, title: station.title, category: "cricket",
            date: Int64(now.timeIntervalSince1970), poster: nil, popular: false, teams: nil)
        XCTAssertNil(SinglePlayerStationGuideProjection(event: fixture, snapshot: nil, at: now),
            "A dated fixture cannot borrow a station guide even when its title and ID resemble the station")
        let unrelated = EventReference(id: "unrelated-fixture", title: station.title, category: "cricket",
            date: nil, poster: nil, popular: false, teams: nil)
        XCTAssertNil(SinglePlayerStationGuideProjection(event: unrelated, snapshot: nil, at: now))
    }
    func testSinglePlayerGuideKeepsExactStationNowNextAndOmitsStaleProgramme() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        func programme(_ id: String, channelID: String, start: Date, end: Date) -> BroadcastRegistrySnapshot.Broadcast {
            .init(id: id, providerCode: "reviewedtv", providerEventID: id, streamID: "reviewed-tv:willow",
                resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket",
                title: id, participants: ["Afghanistan", "Zimbabwe"], start: start, end: end,
                channelID: channelID, observedAt: now, expiresAt: now.addingTimeInterval(600),
                verification: .dated, issues: [])
        }
        let current = programme("current", channelID: station.id,
            start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800))
        let next = programme("next", channelID: station.id,
            start: now.addingTimeInterval(1800), end: now.addingTimeInterval(3600))
        let other = programme("other-station", channelID: "sports-channel:sky-sports-cricket",
            start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let provider = BroadcastRegistrySnapshot.Provider(providerCode: "reviewedtv", scope: "cricket", status: .available,
            observedAt: now, expiresAt: now.addingTimeInterval(600))
        let link = BroadcastRegistrySnapshot.Link(fixtureID: "cricket-fixture:icc:guide", broadcastID: current.id,
            providerCode: "reviewedtv", state: .listed, matchMethod: .programme,
            fixtureFingerprint: .init(fixtureID: "cricket-fixture:icc:guide", sport: "cricket",
                start: now.addingTimeInterval(-1800), participants: ["Afghanistan", "Zimbabwe"], format: .t20),
            expiresAt: now.addingTimeInterval(600))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "station-guide", generatedAt: now,
            providers: [provider], broadcasts: [other, next, current], links: [link])
        let projected = try XCTUnwrap(SinglePlayerStationGuideProjection(event: station.event, snapshot: snapshot, at: now))
        XCTAssertEqual(projected.current?.id, current.id)
        XCTAssertEqual(projected.next?.id, next.id)
        XCTAssertNil(station.event.cricketFixture, "Programme metadata must not turn channel viewing into a fixture")
        let expired = try XCTUnwrap(SinglePlayerStationGuideProjection(event: station.event, snapshot: snapshot,
            at: now.addingTimeInterval(601)))
        XCTAssertNil(expired.current); XCTAssertNil(expired.next)
    }
    func testSinglePlayerGuideNeverPromotesStartOnlyScheduleToNow() throws {
        let row = guide(start: now.addingTimeInterval(600))
        let station = try XCTUnwrap(SportsTVStation.station(id: row.channelID))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "station-schedule", generatedAt: now,
            providers: [], broadcasts: [], links: [], tvGuide: [row])
        let projected = try XCTUnwrap(SinglePlayerStationGuideProjection(event: station.event, snapshot: snapshot, at: now))
        XCTAssertNil(projected.current)
        XCTAssertEqual(projected.next?.id, row.id)
    }
    func testMalformedGuideDoesNotWithdrawValidBaseSnapshot() throws {
        let payload: [String: Any] = ["schemaVersion": 1, "revision": "base", "generatedAt": "2027-01-15T08:00:00.000Z",
            "providers": [], "broadcasts": [], "links": [], "tvGuide": "malformed"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let at = try XCTUnwrap(BroadcastRegistrySnapshot.date("2027-01-15T08:00:00.000Z"))
        let accepted = try BroadcastRegistrySnapshot.validated(from: data, at: at)
        XCTAssertNil(accepted.tvGuide); XCTAssertEqual(accepted.revision, "base")
    }
    func testMalformedGuideRowsQuarantineOnlyTheirIdentitiesAndSlots() throws {
        let intact = wireGuide("a", hour: 9)
        let duplicateID = wireGuide("b", hour: 10)
        let duplicateSlot = wireGuide("c", hour: 11)
        var badMarket = wireGuide("d", hour: 12)
        badMarket["market"] = "GB"
        let damagedID: [String: Any] = ["id": try XCTUnwrap(duplicateID["id"])]
        let damagedSlot: [String: Any] = ["id": 17, "channelID": try XCTUnwrap(duplicateSlot["channelID"]),
                                         "start": "2027-01-15T07:00:00-04:00", "title": false]
        var unknownField = wireGuide("e", hour: 13)
        unknownField["unexpected"] = "extra"
        var noZone = wireGuide("f", hour: 9)
        noZone["start"] = "2027-01-15T09:00:00"
        let rows: [Any] = [damagedSlot, duplicateID, NSNull(), 7, intact, badMarket, duplicateSlot, damagedID, unknownField, noZone]
        for order in [rows, Array(rows.reversed())] {
            let snapshot = try wireSnapshot(guide: order)
            XCTAssertEqual(snapshot.tvGuide?.map(\.id), [try XCTUnwrap(intact["id"] as? String)])
        }
    }

    func testCachedUpcomingTVGuideSurvivesRefreshFailureOnlyUntilItsOwnExpiry() throws {
        let snapshot = try wireSnapshot(guide: [wireGuide("a", hour: 13)])
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let fetched = snapshot.generatedAt
        func entries(_ elapsed: TimeInterval) -> [SportsTVGuidePolicy.Entry] {
            SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: fetched.addingTimeInterval(elapsed))
        }
        let stale = try XCTUnwrap(entries(BroadcastRegistrySnapshot.networkFreshness + 1).first)
        XCTAssertNil(stale.end)
        XCTAssertFalse(stale.isOnNow(at: stale.start))
        XCTAssertEqual(entries(4 * 3600 - 1).count, 1)
        XCTAssertTrue(entries(4 * 3600).isEmpty)
        XCTAssertTrue(entries(BroadcastRegistrySnapshot.retention + 1).isEmpty)
    }

    func testOverCapacityGuideIsOmittedWithoutDroppingBaseRegistry() throws {
        let snapshot = try wireSnapshot(guide: Array(repeating: NSNull(), count: 301))
        XCTAssertNil(snapshot.tvGuide)
        XCTAssertEqual(snapshot.revision, "base")
    }

    private func wireGuide(_ key: String, hour: Int) -> [String: Any] {
        ["id": "tv-guide:" + String(repeating: key, count: 64), "channelID": "sports-channel:espn2-latinamerica-south",
         "market": "UY", "sport": "baseball", "title": "Game",
         "start": String(format: "2027-01-15T%02d:00:00.000Z", hour),
         "observedAt": "2027-01-15T08:00:00.000Z", "expiresAt": "2027-01-15T12:00:00.000Z"]
    }

    private func wireSnapshot(guide: [Any]) throws -> BroadcastRegistrySnapshot {
        let timestamp = "2027-01-15T08:00:00.000Z"
        let payload: [String: Any] = ["schemaVersion": 1, "revision": "base", "generatedAt": timestamp,
                                     "providers": [], "broadcasts": [], "links": [], "tvGuide": guide]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try BroadcastRegistrySnapshot.validated(from: data, at: XCTUnwrap(BroadcastRegistrySnapshot.date(timestamp)))
    }

    func testActualBackendGuideWireFixturePassesTheNativeContract() throws {
        // Synthetic fixture emitted by the real backend assignment/snapshot
        // builders, not a playback or current-programme qualification receipt.
        let url = Bundle(for: Self.self).url(forResource: "reviewed-tv-guide-snapshot", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/reviewed-tv-guide-snapshot.json")
        let at = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-01T00:00:00.000Z"))
        let snapshot = try BroadcastRegistrySnapshot.validated(from: Data(contentsOf: url), at: at)
        XCTAssertEqual(Set(snapshot.providers.map(\.scope)), ["baseball", "hockey"])
        XCTAssertEqual(snapshot.tvGuide?.count, 2)
        XCTAssertEqual(snapshot.links.filter { $0.state == .listed }.count, 2)
        for broadcast in snapshot.broadcasts {
            XCTAssertEqual(broadcast.squad?.gender, .men)
            XCTAssertTrue(ReviewedTVPlaylistClient.supportsScheduledSport(broadcast))
        }
    }
    private func session(_ provider: String, host: String, path: String) -> StreamSession {
        .init(matchID: "test", playableURL: URL(string: "https://\(host)/\(path)")!, streamType: .hls, providerName: provider)
    }
    private func guide(start: Date) -> SportsTVGuideItem {
        .init(id: "tv-guide:" + String(repeating: "a", count: 64), channelID: "sports-channel:espn2-latinamerica-south", market: "UY", sport: "baseball",
            title: "MLB – World Series – Game #6 (if necessary)", start: start, observedAt: now, expiresAt: now.addingTimeInterval(4 * 3600))
    }
}
