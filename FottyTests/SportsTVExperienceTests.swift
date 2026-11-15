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
        let stationLabels = [2, 3].map { number in
            BroadcastSourcePresentation.accessibilityLabel(title: "Willow Cricket", provider: "TV1", number: number,
                                                          description: nil, action: "Switch")
        }
        XCTAssertEqual(stationLabels, ["Willow Cricket, Source 2, Switch", "Willow Cricket, Source 3, Switch"])
        XCTAssertEqual(BroadcastSourcePresentation.accessibilityLabel(title: "Broadcast 4", provider: "CS4",
            number: 4, description: nil, action: "Switch"), "Broadcast 4, Switch")
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
                    XCTAssertTrue(ReviewedTVPlaylistClient.admitsDelivery(URL(string: changed)!, channel: channel))
                }
            }
            XCTAssertNil(request.registryMatch, "A channel is not proof of a fixture's programme")
            XCTAssertThrowsError(try ReviewedTVPlaylistClient.willowDelivery(from: playlist, playlistURL: channel.playlistURL),
                                 "Station identity comes from the selected playlist entry, never a shared transport host")
            for invalid in ["http://\(host)/a.m3u8", "https://\(host):8443/a.m3u8",
                            "https://user:secret@\(host)/live", "https://127.0.0.1/live",
                            "https://\(host)/live?url=http://public.example/live"] {
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

    func testDiscoveredStationContractRejectsWrongIdentityUnsafeTransportAndCredentials() throws {
        for provider in ["TV17", "TV21", "TV22", "TV23", "TV24"] {
            let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: provider))
            let target = try coreDelivery(channel), good = corePlaylist(channel, delivery: target)
            XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: good,
                playlistURL: channel.playlistURL, channel: channel), target)
            let host = try XCTUnwrap(target.host)
            for value in ["http://\(host)\(target.path)", target.absoluteString + "#fragment",
                          "https://\(host):8443\(target.path)", "https://127.0.0.1\(target.path)",
                          "https://user:secret@\(host)\(target.path)", "https://\(host)/stream?url=https://127.0.0.1/live"] {
                XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: value)!, channel: channel))
            }
            for safe in ["https://new-cdn.example/stream", target.absoluteString + "?token=published"] {
                XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: corePlaylist(channel, delivery: URL(string: safe)!),
                    playlistURL: channel.playlistURL, channel: channel).absoluteString, safe)
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

    func testCoreEnglishContractsPreserveStationIdentityAndDefaultHeadersWithSafeAlternatives() throws {
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV10"))
        let target = try coreDelivery(channel), data = corePlaylist(channel, delivery: target)
        XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: data,
            playlistURL: channel.playlistURL, channel: channel), target)
        let host = try XCTUnwrap(target.host), path = try XCTUnwrap(channel.deliveryPath)
        for invalid in ["http://\(host)\(path)", "https://\(host):8443\(path)",
                        "https://127.0.0.1/live", "https://user:secret@\(host)\(path)",
                        target.absoluteString + "#fragment", "https://\(host)/stream?url=http://public.example/live"] {
            XCTAssertFalse(ReviewedTVPlaylistClient.admitsDelivery(URL(string: invalid)!, channel: channel))
        }
        for safe in ["https://\(host)\(path)", target.absoluteString + "&quality=published", "https://new-cdn.example/live"] {
            XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: corePlaylist(channel, delivery: URL(string: safe)!),
                playlistURL: channel.playlistURL, channel: channel).absoluteString, safe)
        }
        let defaulted = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "#EXTVLCOPT:http-user-agent=" + channel.playbackUserAgent! + "\n", with: "")
        XCTAssertEqual(try ReviewedTVPlaylistClient.delivery(from: Data(defaulted.utf8),
            playlistURL: channel.playlistURL, channel: channel), target,
            "An omitted optional directive retains the station's required default User-Agent")
        for mutation in [String(decoding: data, as: UTF8.self).replacingOccurrences(of: channel.playlistIdentifier, with: "SkySp.Fball.uk"),
                         String(decoding: data, as: UTF8.self).replacingOccurrences(of: channel.displayName, with: "Sky Sports Football"),
                         String(decoding: data, as: UTF8.self).replacingOccurrences(of: "#EXTVLCOPT:http-user-agent=", with: "#EXTVLCOPT:http-referrer="),
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
    func testCurrentProgrammeResolvesThroughExistingRegistryIdentityPolicy() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let start = now.addingTimeInterval(-3600), expiry = now.addingTimeInterval(600)
        let metadata = CricketFixtureMetadata(fixtureID: "icc:guide", competitionID: "icc", competitionName: "ICC",
            format: .odi, status: .live, observedAt: now, verified: true, matchOrdinal: 1)
        let fixture = EventReference(id: "cricket-fixture:icc:guide", title: "New Zealand vs India", category: "cricket",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "New Zealand", badge: nil), away: .init(name: "India", badge: nil)), cricketFixture: metadata)
        let broadcast = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "b", count: 64), streamID: "reviewed-tv:willow-main",
            resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket", title: fixture.displayTitle,
            participants: ["New Zealand", "India"], start: start, end: now.addingTimeInterval(3600), competitionID: "icc",
            format: .odi, matchOrdinal: 1, channelID: station.id, observedAt: now, expiresAt: expiry, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: fixture.id, broadcastID: broadcast.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .programme, fixtureFingerprint: .init(fixtureID: fixture.id, sport: "cricket",
                start: start, participants: broadcast.participants, competitionID: "icc", format: .odi, matchOrdinal: 1), expiresAt: expiry)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "current-fixture", generatedAt: now,
            providers: [.init(providerCode: "reviewedtv", scope: "cricket", status: .available, observedAt: now, expiresAt: expiry)],
            broadcasts: [broadcast], links: [link])
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertTrue(entry.isOnNow(at: now)); XCTAssertEqual(entry.fixtureID, fixture.id)
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now)?.id, fixture.id)
        let fox = try XCTUnwrap(SportsTVStation.station(provider: "CS-Fox"))
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: fox,
            snapshot: snapshot, catalog: [fixture], at: now), "An exact programme cannot transfer to another station")
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: expiry), "Programme duration cannot renew the association lease")
    }

    func testLinkedWillowPregameKeepsDirectChannelWhenFixtureWatchIsNotOffered() throws {
        let fixture = guideCricketFixture(start: now.addingTimeInterval(1800))
        let snapshot = try cricketGuideSnapshot(fixture, at: now, sourceStart: now,
            programmeEnd: now.addingTimeInterval(7200))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertTrue(entry.isOnNow(at: now), "Fresh explicitly linked coverage is already on air before official kickoff")
        let linked = try XCTUnwrap(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now))
        XCTAssertEqual(linked.id, fixture.id)
        XCTAssertEqual(linked.cricketFixture?.status, .scheduled, "Coverage never invents a live fixture status")

        let discovery = FixtureStreamDiscoveryIndex()
        discovery.updateEnabledProviders(["communitysports"], revision: 1)
        let catalog = FixtureCatalogAvailabilityIndex()
        XCTAssertFalse(SportsTVGuidePresentationPolicy.offersMatchWatch(linked, status: nil, at: now,
            discoveryIndex: discovery, catalogIndex: catalog),
            "Guide identity alone cannot enable the reviewed-TV early coverage route when only CS is enabled")
        XCTAssertTrue(SportsTVStation.canWatchNow(station, discoveryIndex: discovery),
            "The independent explicit Willow channel remains tunable without claiming the fixture is playing")
    }

    func testFutureGuideResolvesOnlyTheExplicitCurrentFixtureForSaveAndRemind() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600))
        let snapshot = try fixtureGuideSnapshot(fixture)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertEqual(entry.fixtureID, fixture.id)
        XCTAssertFalse(entry.isOnNow(at: now))
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now)?.id, fixture.id)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [], at: now), "An ID does not manufacture a missing fixture")
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture, fixture], at: now), "Ambiguous catalog ownership cannot silently pick a winner")
        XCTAssertTrue(snapshot.lookup(for: .init(event: fixture), enabledProviderCodes: ["reviewedtv"], at: now).isEmpty,
                      "A future Save/Remind identity must not alter the existing current-playback contract")
    }

    func testFiveDayGuideUsesAcceptedPlanningScheduleWithoutRenewingStatusOrEnablingWatch() throws {
        func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
        let start = now.addingTimeInterval(5 * 86400), receipt = now.addingTimeInterval(-45 * 60)
        let publisherUpdate = now.addingTimeInterval(-7 * 86400)
        let identity = guideFootballFixture(start: start), metadata = try XCTUnwrap(identity.sportsFixture)
        let row = SportsFixtureCatalog.Fixture(id: identity.id, sport: "football", start: stamp(start),
            status: .scheduled, eventKind: .match, title: identity.displayTitle,
            competitionId: metadata.competitionID, competitionName: metadata.competitionName,
            participants: metadata.participants, squad: metadata.squad,
            source: .init(name: "Accepted official schedule", url: "https://example.test/fixtures",
                observedAt: stamp(receipt), updatedAt: stamp(publisherUpdate), verification: .verified))
        let schedule = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true, checkedAt: stamp(receipt),
            revision: "five-day-guide", sourceStatus: .verified, fixtures: [row],
            coverage: [.init(sport: "football", competitionId: metadata.competitionID,
                competitionName: metadata.competitionName, status: .covered, checkedAt: stamp(receipt),
                fixtureCount: 1, pendingFixtureCount: 0, nextStart: row.start)])
        let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(schedule), now: now)
        let home = SportsFixtureCatalog.merging(into: [], snapshot: accepted, at: now)
        let planning = SportsSearchSchedule.events(sports: accepted, cricket: nil, at: now)
        XCTAssertTrue(home.isEmpty, "The existing Home catalog intentionally stops at 72 hours")
        let planned = try XCTUnwrap(planning.first)
        XCTAssertEqual(planning.count, 1)
        let snapshot = try fixtureGuideSnapshot(planned, sourceOffset: -600)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        let linked = try XCTUnwrap(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: home, planningCatalog: planning, at: now))
        XCTAssertEqual(linked.id, identity.id)
        XCTAssertEqual(linked.sportsFixture?.identityReceipt, receipt)
        XCTAssertEqual(linked.sportsFixture?.observedAt, publisherUpdate,
                       "Planning must not renew the stricter publisher-status clock")
        XCTAssertEqual(SavedMatchRecord(event: linked, savedAt: now).id, identity.id)
        XCTAssertEqual(MatchReminderRecord.make(event: linked, now: now)?.fireDate,
                       start.addingTimeInterval(-MatchStartPolicy.reminderLead))
        XCTAssertFalse(MatchStartPolicy(event: linked, now: now).timingAllowsPlayback)
        XCTAssertFalse(linked.sportsFixture?.isLive(at: now) ?? true)
        XCTAssertTrue(snapshot.lookup(for: .init(event: linked), enabledProviderCodes: ["reviewedtv"], at: now).isEmpty)
    }

    func testFutureGuideUsesExistingPlanningReceiptLifetimeForSportsAndCricket() throws {
        let start = now.addingTimeInterval(5 * 86400)
        for age in [45 * 60.0, 4 * 3600.0] {
            let receipt = now.addingTimeInterval(-age)
            let football = guideFootballFixture(start: start, observedAt: receipt)
            let cricket = guideCricketFixture(start: start, observedAt: receipt)
            for (fixture, snapshot, provider) in [
                (football, try fixtureGuideSnapshot(football), "TV3"),
                (cricket, try cricketGuideSnapshot(cricket, at: now, sourceStart: start), "TV1")
            ] {
                let station = try XCTUnwrap(SportsTVStation.station(provider: provider))
                let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
                for catalog in [[], [fixture]] {
                    let linked = try XCTUnwrap(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
                        snapshot: snapshot, catalog: catalog, planningCatalog: [fixture], at: now))
                    XCTAssertEqual(linked.sportsFixture?.identityReceipt ?? linked.cricketFixture?.observedAt, receipt)
                    XCTAssertFalse(MatchStartPolicy(event: linked, now: now).timingAllowsPlayback)
                }
            }
        }
    }

    func testFutureGuidePlanningRejectsExpiredUnverifiedAndConflictingFixtures() throws {
        let start = now.addingTimeInterval(5 * 86400), fixture = guideFootballFixture(start: start)
        let snapshot = try fixtureGuideSnapshot(fixture)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        let rejected = [guideFootballFixture(start: start, observedAt: now.addingTimeInterval(-SportsSearchSchedule.receiptFreshness - 1)),
            guideFootballFixture(start: start, observedAt: now.addingTimeInterval(301)),
            guideFootballFixture(start: start, verified: false),
            guideFootballFixture(start: start, conflict: true),
            guideFootballFixture(start: start, away: "Liverpool"),
            guideFootballFixture(start: start, status: .cancelled)]
        for candidate in rejected {
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
                snapshot: snapshot, catalog: [], planningCatalog: [candidate], at: now))
        }
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [], planningCatalog: [fixture, fixture], at: now),
            "Planning cannot choose between duplicate owners")
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [], planningCatalog: [fixture], at: now.addingTimeInterval(600)),
            "A valid future schedule cannot renew an expired registry link")

        let cricket = guideCricketFixture(start: start)
        let cricketSnapshot = try cricketGuideSnapshot(cricket, at: now, sourceStart: start)
        let willow = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let cricketEntry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: willow, snapshot: cricketSnapshot, at: now).first)
        for candidate in [guideCricketFixture(start: start, observedAt: now.addingTimeInterval(-SportsSearchSchedule.receiptFreshness - 1)),
                          guideCricketFixture(start: start, verified: false)] {
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: cricketEntry, station: willow,
                snapshot: cricketSnapshot, catalog: [], planningCatalog: [candidate], at: now))
        }
    }

    func testFutureGuidePlanningCannotShadowCurrentCatalogOwnershipOrVetoes() throws {
        let start = now.addingTimeInterval(3600), fixture = guideFootballFixture(start: start)
        let snapshot = try fixtureGuideSnapshot(fixture)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], planningCatalog: [fixture, fixture], at: now)?.id, fixture.id,
            "Overlapping planning rows must not duplicate a unique current owner")
        let rejectedCatalogs = [[fixture, fixture],
            [guideFootballFixture(start: start, away: "Liverpool")],
            [guideFootballFixture(start: start, conflict: true)],
            [guideFootballFixture(start: start, verified: false)],
            [guideFootballFixture(start: start, status: .finished)],
            [guideFootballFixture(start: start, status: .cancelled)],
            [guideFootballFixture(start: start, status: .postponed)]]
        for current in rejectedCatalogs {
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
                snapshot: snapshot, catalog: current, planningCatalog: [fixture], at: now),
                "A clean planning row must not rescue a rejected current identity")
        }
        let terminal = guideFootballFixture(start: start, status: .cancelled)
        let alias = EventReference(id: "provider:terminal-guide-alias", title: terminal.title, category: terminal.category,
            date: terminal.date, poster: nil, popular: false, teams: terminal.teams, sportsFixture: terminal.sportsFixture)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [alias], planningCatalog: [fixture], at: now),
            "A terminal canonical identity under a provider ID still vetoes supplemental planning")
    }

    func testPlanningCannotSupplyCurrentProgrammeOrRelaxCurrentFixtureFreshness() throws {
        let start = now.addingTimeInterval(-3600), fixture = guideCricketFixture(start: start, status: .live)
        let snapshot = try cricketGuideSnapshot(fixture, at: now, sourceStart: start,
            programmeEnd: now.addingTimeInterval(3600))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertTrue(entry.isOnNow(at: now))
        XCTAssertNotNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now))
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [], planningCatalog: [fixture], at: now),
            "Planning-only identity never authorizes a programme that has begun")
        let stale = guideCricketFixture(start: start, status: .live, observedAt: now.addingTimeInterval(-45 * 60))
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [stale], planningCatalog: [fixture], at: now),
            "Current programme matching retains its existing status freshness")
    }

    func testDetailedGuideDuplicatePreservesOriginalLinkedRowWithoutTransferringAuthority() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600)), base = try fixtureGuideSnapshot(guideFootballFixture(start: now.addingTimeInterval(3600)))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3")), broadcast = try XCTUnwrap(base.broadcasts.first)
        let link = try XCTUnwrap(base.links.first), start = try XCTUnwrap(fixture.kickoffDate)
        let detailed = SportsTVGuideItem(id: "detailed-schedule", channelID: station.id, market: "UY", sport: "football",
            title: "Premier League: " + broadcast.title + " — live coverage", start: start,
            observedAt: now, expiresAt: now.addingTimeInterval(7200))
        let generic = SportsTVGuideItem(id: "generic-schedule", channelID: station.id, market: "UY", sport: "football",
            title: "Football news", start: start.addingTimeInterval(1800), observedAt: now, expiresAt: detailed.expiresAt)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "detailed-duplicate", generatedAt: now,
            providers: base.providers, broadcasts: base.broadcasts, links: base.links, tvGuide: [detailed, generic])
        let fresh = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now)
        XCTAssertEqual(fresh.map(\.id), [broadcast.id, generic.id])
        let entry = try XCTUnwrap(fresh.first)
        XCTAssertEqual(entry.fixtureID, fixture.id)
        XCTAssertEqual(entry.title, broadcast.title, "The original associated row retains its own identity and text")
        XCTAssertNil(fresh.last?.fixtureID)
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now)?.id, fixture.id)

        let expiredAt = now.addingTimeInterval(600)
        let expired = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: expiredAt)
        XCTAssertEqual(expired.map(\.id), [detailed.id, generic.id])
        XCTAssertTrue(expired.allSatisfy { $0.fixtureID == nil }, "Longer guide expiry cannot inherit the expired match association")
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: expiredAt))
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: try XCTUnwrap(expired.first), station: station,
            snapshot: snapshot, catalog: [fixture], at: expiredAt))

        let conflict = BroadcastRegistrySnapshot.Link(fixtureID: link.fixtureID, broadcastID: link.broadcastID,
            providerCode: link.providerCode, state: .conflicting, matchMethod: link.matchMethod,
            fixtureFingerprint: link.fixtureFingerprint, expiresAt: link.expiresAt, reason: "time-conflict", startRelation: link.startRelation)
        let conflicted = copyGuideSnapshot(snapshot, links: [conflict])
        let rejected = SportsTVGuidePolicy.entries(for: station, snapshot: conflicted, at: now)
        XCTAssertEqual(rejected.map(\.id), [detailed.id, generic.id])
        XCTAssertTrue(rejected.allSatisfy { $0.fixtureID == nil })
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: conflicted, catalog: [fixture], at: now))
    }

    func testFutureGuideRejectsChangedDateTeamsSquadAndTerminalCatalogFacts() throws {
        let start = now.addingTimeInterval(3600), fixture = guideFootballFixture(start: now.addingTimeInterval(3600))
        let snapshot = try fixtureGuideSnapshot(fixture)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        let rejected = [guideFootballFixture(start: start.addingTimeInterval(60)),
            guideFootballFixture(start: start, away: "Liverpool"),
            guideFootballFixture(start: start, gender: .women),
            guideFootballFixture(start: start, status: .finished),
            guideFootballFixture(start: start, status: .cancelled),
            guideFootballFixture(start: start, status: .postponed),
            guideFootballFixture(start: start, observedAt: now.addingTimeInterval(-SportsSearchSchedule.receiptFreshness - 1))]
        for current in rejected {
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
                snapshot: snapshot, catalog: [current], at: now), "Changed or terminal fixture facts must invalidate the action")
        }
    }

    func testGuideActionRechecksExpiredAndChangedRegistryAssociations() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600)), snapshot = try fixtureGuideSnapshot(guideFootballFixture(start: now.addingTimeInterval(3600)))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now.addingTimeInterval(600)))
        let noLink = copyGuideSnapshot(snapshot, links: [])
        XCTAssertNil(SportsTVGuidePolicy.entries(for: station, snapshot: noLink, at: now).first?.fixtureID)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: noLink, catalog: [fixture], at: now), "Rendered identity cannot survive removal of its current link")
        let expiredLink = try XCTUnwrap(snapshot.links.first)
        let denied = BroadcastRegistrySnapshot.Link(fixtureID: expiredLink.fixtureID,
            broadcastID: expiredLink.broadcastID, providerCode: expiredLink.providerCode, state: .conflicting,
            matchMethod: expiredLink.matchMethod, fixtureFingerprint: expiredLink.fixtureFingerprint,
            expiresAt: expiredLink.expiresAt, reason: "time-conflict", startRelation: expiredLink.startRelation)
        let conflicted = copyGuideSnapshot(snapshot, links: [expiredLink, denied])
        XCTAssertNil(SportsTVGuidePolicy.entries(for: station, snapshot: conflicted, at: now).first?.fixtureID)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: conflicted, catalog: [fixture], at: now))
    }

    func testGuideDoesNotChooseBetweenMultipleCurrentFixtureLinks() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600)), snapshot = try fixtureGuideSnapshot(guideFootballFixture(start: now.addingTimeInterval(3600)))
        let original = try XCTUnwrap(snapshot.links.first), f = original.fixtureFingerprint
        let rival = BroadcastRegistrySnapshot.Link(fixtureID: "sports-fixture:premier-league:other",
            broadcastID: original.broadcastID, providerCode: original.providerCode, state: .listed,
            matchMethod: original.matchMethod,
            fixtureFingerprint: .init(fixtureID: "sports-fixture:premier-league:other", sport: f.sport,
                start: f.start, participants: f.participants, competitionID: f.competitionID, squad: f.squad),
            expiresAt: original.expiresAt, startRelation: original.startRelation)
        let ambiguous = copyGuideSnapshot(snapshot, links: [original, rival])
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: ambiguous, at: now).first)
        XCTAssertNil(entry.fixtureID)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: ambiguous, catalog: [fixture], at: now))
    }

    func testGenericTVScheduleNeverBorrowsFixtureIdentityFromItsTitle() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let row = SportsTVGuideItem(id: "schedule-only", channelID: station.id, market: "UY", sport: "football",
            title: fixture.displayTitle, start: try XCTUnwrap(fixture.kickoffDate), observedAt: now, expiresAt: now.addingTimeInterval(600))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "unlinked", generatedAt: now,
            providers: [], broadcasts: [], links: [], tvGuide: [row])
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertNil(entry.fixtureID)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now))
        XCTAssertEqual(station.event.id, station.id)
        XCTAssertNil(station.event.sportsFixture)
    }

    func testFixtureBindingKeepsProviderLeaseAndRetainedFailureRules() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600)), snapshot = try fixtureGuideSnapshot(guideFootballFixture(start: now.addingTimeInterval(3600)))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let provider = try XCTUnwrap(snapshot.providers.first)
        for status in [BroadcastRegistrySnapshot.CoverageStatus.empty, .failed, .unsupported] {
            let failed = BroadcastRegistrySnapshot.Provider(providerCode: provider.providerCode, scope: provider.scope,
                status: status, observedAt: now, expiresAt: provider.expiresAt)
            let changed = copyGuideSnapshot(snapshot, providers: [failed])
            XCTAssertNil(SportsTVGuidePolicy.entries(for: station, snapshot: changed, at: now).first?.fixtureID)
        }
        let retained = BroadcastRegistrySnapshot.Provider(providerCode: provider.providerCode, scope: provider.scope,
            status: .failed, observedAt: now, lastSuccessAt: now, expiresAt: provider.expiresAt)
        let changed = copyGuideSnapshot(snapshot, providers: [retained])
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: changed, at: now).first)
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: changed, catalog: [fixture], at: now)?.id, fixture.id)
    }

    func testGuideDayUsesLocalMidnightAndHalfOpenIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Port_of_Spain"))
        let clock = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-15T03:30:00Z"))
        let midnight = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-15T04:00:00Z"))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        func row(_ id: String, _ start: Date) -> SportsTVGuideItem {
            .init(id: id, channelID: station.id, market: "UY", sport: "football", title: id,
                  start: start, observedAt: clock, expiresAt: clock.addingTimeInterval(3600))
        }
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "day-boundary", generatedAt: clock,
            providers: [], broadcasts: [], links: [], tvGuide: [row("today", midnight.addingTimeInterval(-1)),
                row("tomorrow", midnight), row("after-tomorrow", midnight.addingTimeInterval(86400))])
        XCTAssertEqual(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: clock,
            day: .today, calendar: calendar).map(\.id), ["today"])
        XCTAssertEqual(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: clock,
            day: .tomorrow, calendar: calendar).map(\.id), ["tomorrow"])
    }

    func testTomorrowGuideUsesCalendarDayRatherThanTwentyFourHoursAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let clock = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-10-31T12:00:00Z"))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let lateTomorrow = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-02T04:30:00Z"))
        let row = SportsTVGuideItem(id: "dst", channelID: station.id, market: "UY", sport: "football", title: "Late programme",
            start: lateTomorrow, observedAt: clock, expiresAt: clock.addingTimeInterval(3600))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "dst", generatedAt: clock,
            providers: [], broadcasts: [], links: [], tvGuide: [row])
        XCTAssertEqual(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: clock,
            day: .tomorrow, calendar: calendar).map(\.id), ["dst"])
    }

    func testSportFiltersUseAdvertisedSportsAndPreserveStationOrder() throws {
        let library = SportsTVLibrary(defaults: defaults), ordered = library.sections(commentary: .english).flatMap(\.stations)
        let willow = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let sky = try XCTUnwrap(SportsTVStation.station(provider: "CS-SkyMain"))
        XCTAssertTrue(SportsTVGuidePolicy.matches(willow, sport: .cricket, snapshot: nil, at: now))
        XCTAssertFalse(SportsTVGuidePolicy.matches(willow, sport: .football, snapshot: nil, at: now))
        XCTAssertFalse(SportsTVGuidePolicy.matches(sky, sport: .football, snapshot: nil, at: now), "Station names cannot supply a sport")
        let row = SportsTVGuideItem(id: "sky-football", channelID: sky.id, market: "GB", sport: "football", title: "Football",
            start: now.addingTimeInterval(600), observedAt: now, expiresAt: now.addingTimeInterval(600))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "sports", generatedAt: now,
            providers: [], broadcasts: [], links: [], tvGuide: [row])
        XCTAssertTrue(SportsTVGuidePolicy.matches(sky, sport: .football, snapshot: snapshot, at: now))
        XCTAssertFalse(SportsTVGuidePolicy.matches(sky, sport: .cricket, snapshot: snapshot, at: now))
        XCTAssertEqual(ordered.filter { SportsTVGuidePolicy.matches($0, sport: .all, snapshot: snapshot, at: now) }, ordered)
        XCTAssertTrue(SportsTVGuidePolicy.entries(for: sky, snapshot: snapshot, at: now,
            day: .today, sport: .cricket).isEmpty)
        XCTAssertEqual(library.sections(commentary: .english).flatMap(\.stations), ordered)
    }

    func testNetworkFreshnessBoundaryWithdrawsFixtureAuthorityButKeepsUnexpiredSchedule() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600)), base = try fixtureGuideSnapshot(guideFootballFixture(start: now.addingTimeInterval(3600)))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3")), broadcast = try XCTUnwrap(base.broadcasts.first)
        let row = SportsTVGuideItem(id: "retained-schedule", channelID: station.id, market: "UY", sport: "football",
            title: broadcast.title, start: try XCTUnwrap(fixture.kickoffDate), observedAt: now, expiresAt: now.addingTimeInterval(3600))
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "network-boundary", generatedAt: now,
            providers: base.providers, broadcasts: base.broadcasts, links: base.links, tvGuide: [row])
        let edge = copyGuideSnapshot(snapshot, generatedAt: now.addingTimeInterval(-BroadcastRegistrySnapshot.networkFreshness))
        let current = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: edge, at: now).first)
        XCTAssertEqual(current.id, broadcast.id); XCTAssertEqual(current.fixtureID, fixture.id)
        let stale = copyGuideSnapshot(snapshot, generatedAt: now.addingTimeInterval(-BroadcastRegistrySnapshot.networkFreshness - 1))
        let retained = SportsTVGuidePolicy.entries(for: station, snapshot: stale, at: now)
        XCTAssertEqual(retained.map(\.id), [row.id]); XCTAssertNil(retained.first?.fixtureID)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: current, station: station,
            snapshot: stale, catalog: [fixture], at: now))
    }

    func testCurrentProgrammeCrossingLocalMidnightRemainsInToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Port_of_Spain"))
        let clock = try XCTUnwrap(BroadcastRegistrySnapshot.date("2026-11-15T04:15:00Z"))
        let start = clock.addingTimeInterval(-1800), end = clock.addingTimeInterval(1800)
        let fixture = guideCricketFixture(start: start, status: .live, observedAt: clock)
        let snapshot = try cricketGuideSnapshot(fixture, at: clock, sourceStart: start, programmeEnd: end)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let today = SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: clock, day: .today, calendar: calendar)
        XCTAssertEqual(today.count, 1); XCTAssertTrue(today[0].isOnNow(at: clock))
        XCTAssertEqual(today[0].fixtureID, fixture.id)
        XCTAssertFalse(calendar.isDate(start, inSameDayAs: clock), "The programme started yesterday locally")
        XCTAssertTrue(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: clock,
            day: .tomorrow, calendar: calendar).isEmpty)
    }

    func testFutureExactAssociationRetainsTimeBasisAndFormatFences() throws {
        let fixture = guideFootballFixture(start: now.addingTimeInterval(3600))
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        func resolved(_ offset: TimeInterval, basis: String? = nil, format: CricketFixtureCatalog.Format? = nil) throws -> EventReference? {
            let snapshot = try fixtureGuideSnapshot(fixture, method: .exact, sourceOffset: offset, startBasis: basis, broadcastFormat: format)
            let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
            return SportsTVGuidePolicy.linkedEvent(for: entry, station: station, snapshot: snapshot, catalog: [fixture], at: now)
        }
        XCTAssertEqual(try resolved(-900)?.id, fixture.id)
        XCTAssertEqual(try resolved(900)?.id, fixture.id)
        XCTAssertNil(try resolved(-901)); XCTAssertNil(try resolved(901))
        XCTAssertNil(try resolved(0, basis: "current-event"), "A derived source clock cannot become an explicit future schedule")
        XCTAssertNil(try resolved(0, format: .t20), "A football binding cannot accept contradictory source format")
    }

    func testFutureLimitedOversGuideRequiresCurrentFormatAndOrdinal() throws {
        let start = now.addingTimeInterval(3600), fixture = guideCricketFixture(start: now.addingTimeInterval(3600))
        let snapshot = try cricketGuideSnapshot(fixture, at: now, sourceStart: start)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now)?.id, fixture.id)
        for current in [guideCricketFixture(start: start, ordinal: 2), guideCricketFixture(start: start, ordinal: nil),
                        guideCricketFixture(start: start, format: .t20)] {
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
                snapshot: snapshot, catalog: [current], at: now))
        }
        for advertisedOrdinal in [2, 3] {
            let mismatch = try cricketGuideSnapshot(fixture, at: now, sourceStart: start, sourceOrdinal: advertisedOrdinal)
            let row = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: mismatch, at: now).first)
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: row, station: station,
                snapshot: mismatch, catalog: [fixture], at: now))
        }
    }

    func testFutureTestGuideRequiresExactDayOrdinalAndPublishedEnd() throws {
        let start = now.addingTimeInterval(3600), end = now.addingTimeInterval(5 * 86400)
        let fixture = guideCricketFixture(start: start, format: .test, ordinal: 3, day: 1, matchEnd: end)
        let snapshot = try cricketGuideSnapshot(fixture, at: now, sourceStart: start)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV1"))
        let entry = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: snapshot, at: now).first)
        XCTAssertEqual(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
            snapshot: snapshot, catalog: [fixture], at: now)?.id, fixture.id)
        let rejected = [guideCricketFixture(start: start, format: .test, ordinal: 3, day: 2, matchEnd: end),
            guideCricketFixture(start: start, format: .test, ordinal: 4, day: 1, matchEnd: end),
            guideCricketFixture(start: start, format: .test, ordinal: 3, day: 1, matchEnd: end.addingTimeInterval(1)),
            guideCricketFixture(start: start, format: .test, ordinal: nil, day: nil, matchEnd: nil)]
        for current in rejected {
            XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: entry, station: station,
                snapshot: snapshot, catalog: [current], at: now))
        }
        let wrongDay = try cricketGuideSnapshot(fixture, at: now, sourceStart: start, sourceDay: 2)
        let row = try XCTUnwrap(SportsTVGuidePolicy.entries(for: station, snapshot: wrongDay, at: now).first)
        XCTAssertNil(SportsTVGuidePolicy.linkedEvent(for: row, station: station,
            snapshot: wrongDay, catalog: [fixture], at: now))
    }

    private func guideCricketFixture(start: Date, format: CricketFixtureCatalog.Format = .odi,
                                     ordinal: Int? = 1, day: Int? = nil, matchEnd: Date? = nil,
                                     status: CricketFixtureCatalog.Status = .scheduled, observedAt: Date? = nil,
                                     verified: Bool = true) -> EventReference {
        let context: CricketMatchContext? = format == .test ? .init(innings: [.init(number: 1, teamID: "nz", runs: 0, wickets: 0)],
            day: day, matchOrdinal: ordinal, matchEndsAt: matchEnd.map { ISO8601DateFormatter().string(from: $0) }, phase: .scheduled) : nil
        let metadata = CricketFixtureMetadata(fixtureID: "icc:guide-cricket", competitionID: "icc", competitionName: "ICC",
            format: format, status: status, observedAt: observedAt ?? now, verified: verified, context: context,
            homeTeamID: "nz", awayTeamID: "india", matchOrdinal: ordinal)
        return EventReference(id: "cricket-fixture:icc:guide-cricket", title: "New Zealand vs India", category: "cricket",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "New Zealand", badge: nil), away: .init(name: "India", badge: nil)), cricketFixture: metadata)
    }

    private func cricketGuideSnapshot(_ fixture: EventReference, at clock: Date, sourceStart: Date,
                                      programmeEnd: Date? = nil, sourceOrdinal: Int? = nil,
                                      sourceDay: Int? = nil) throws -> BroadcastRegistrySnapshot {
        let metadata = try XCTUnwrap(fixture.cricketFixture), kickoff = try XCTUnwrap(fixture.kickoffDate)
        let ordinal = metadata.format == .test ? metadata.context?.matchOrdinal : metadata.matchOrdinal
        let expiry = clock.addingTimeInterval(600)
        let broadcast = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:programme:" + String(repeating: "b", count: 64), streamID: "reviewed-tv:willow-main",
            resourceType: "tv", scope: "cricket", kind: .programme, sport: "cricket", title: fixture.displayTitle,
            participants: ["New Zealand", "India"], start: sourceStart, end: programmeEnd ?? sourceStart.addingTimeInterval(3600),
            competitionID: metadata.competitionID, format: metadata.format, matchOrdinal: sourceOrdinal ?? ordinal,
            day: sourceDay ?? metadata.context?.day, channelID: CricketBroadcastChannel.willow.canonicalID,
            observedAt: clock, expiresAt: expiry, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: fixture.id, broadcastID: broadcast.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: .programme, fixtureFingerprint: .init(fixtureID: fixture.id, sport: "cricket", start: kickoff,
                participants: broadcast.participants, competitionID: metadata.competitionID, format: metadata.format,
                matchOrdinal: ordinal, day: metadata.context?.day,
                end: metadata.context?.matchEndsAt.flatMap(BroadcastRegistrySnapshot.date)), expiresAt: expiry)
        return BroadcastRegistrySnapshot(schemaVersion: 1, revision: "cricket-guide", generatedAt: clock,
            providers: [.init(providerCode: "reviewedtv", scope: "cricket", status: .available, observedAt: clock, expiresAt: expiry)],
            broadcasts: [broadcast], links: [link])
    }

    private func guideFootballFixture(start: Date, away: String = "Chelsea",
                                      gender: SportsFixtureCatalog.Squad.Gender = .men,
                                      status: SportsFixtureCatalog.Status = .scheduled,
                                      observedAt: Date? = nil, verified: Bool = true, conflict: Bool = false) -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:guide", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Arsenal vs " + away, participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "away", name: away)],
            squad: .init(gender: gender, ageGroup: "senior"), status: status, observedAt: observedAt ?? now, verified: verified)
        return EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: away, badge: nil)),
            hasCatalogIdentityConflict: conflict, sportsFixture: metadata)
    }

    private func fixtureGuideSnapshot(_ fixture: EventReference,
                                      method: BroadcastRegistrySnapshot.MatchMethod = .channelAssignment,
                                      sourceOffset: TimeInterval = 0, startBasis: String? = nil,
                                      broadcastFormat: CricketFixtureCatalog.Format? = nil) throws -> BroadcastRegistrySnapshot {
        let channel = try XCTUnwrap(ReviewedTVPlaylistClient.channel(forProviderName: "TV3")), metadata = try XCTUnwrap(fixture.sportsFixture)
        let start = try XCTUnwrap(fixture.kickoffDate), expiry = now.addingTimeInterval(600)
        let broadcast = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "f", count: 64), providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:assignment:" + String(repeating: "f", count: 64), streamID: channel.streamID,
            resourceType: "tv", scope: "football", kind: .event, sport: "football", title: metadata.title,
            participants: ["Arsenal", fixture.awayName], start: start.addingTimeInterval(sourceOffset), startBasis: startBasis,
            competitionID: metadata.competitionID, squad: metadata.squad, format: broadcastFormat, channelID: channel.channelID, stationMarket: "UY", observedAt: now, expiresAt: expiry,
            verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: fixture.id, broadcastID: broadcast.id, providerCode: "reviewedtv",
            state: .listed, matchMethod: method, fixtureFingerprint: .init(fixtureID: fixture.id,
                sport: "football", start: start, participants: broadcast.participants, competitionID: metadata.competitionID,
                squad: metadata.squad), expiresAt: expiry, startRelation: method == .channelAssignment ? "channel-coverage" : nil)
        return BroadcastRegistrySnapshot(schemaVersion: 1, revision: "future-fixture", generatedAt: now,
            providers: [.init(providerCode: "reviewedtv", scope: "football", status: .available,
                observedAt: now, expiresAt: expiry)], broadcasts: [broadcast], links: [link])
    }

    private func copyGuideSnapshot(_ snapshot: BroadcastRegistrySnapshot,
                                   links: [BroadcastRegistrySnapshot.Link]? = nil,
                                   providers: [BroadcastRegistrySnapshot.Provider]? = nil,
                                   generatedAt: Date? = nil) -> BroadcastRegistrySnapshot {
        .init(schemaVersion: snapshot.schemaVersion, revision: snapshot.revision, generatedAt: generatedAt ?? snapshot.generatedAt,
              providers: providers ?? snapshot.providers, broadcasts: snapshot.broadcasts,
              links: links ?? snapshot.links, tvGuide: snapshot.tvGuide)
    }

    private func session(_ provider: String, host: String, path: String) -> StreamSession {
        .init(matchID: "test", playableURL: URL(string: "https://\(host)/\(path)")!, streamType: .hls, providerName: provider)
    }
    private func guide(start: Date) -> SportsTVGuideItem {
        .init(id: "tv-guide:" + String(repeating: "a", count: 64), channelID: "sports-channel:espn2-latinamerica-south", market: "UY", sport: "baseball",
            title: "MLB – World Series – Game #6 (if necessary)", start: start, observedAt: now, expiresAt: now.addingTimeInterval(4 * 3600))
    }
}
