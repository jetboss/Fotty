import XCTest
@testable import Fotty

final class LiveSourceHealthScopeTests: XCTestCase {
    func testEquallyReliableCSASAndTVUseMeasuredSpeedWithoutLosingAlternatives() throws {
        let saved = UserDefaults.standard.object(forKey: SinglePlaybackContinuityStore.storageKey)
        let language = UserDefaults.standard.object(forKey: CommentaryPreference.storageKey)
        defer {
            UserDefaults.standard.set(saved, forKey: SinglePlaybackContinuityStore.storageKey)
            UserDefaults.standard.set(language, forKey: CommentaryPreference.storageKey)
        }
        UserDefaults.standard.set(CommentaryPreference.english.rawValue, forKey: CommentaryPreference.storageKey)
        for winner in ["CS1", "AS1", "TV1"] {
            LiveSourceHealthStore.resetForTesting()
            let fixture = UUID().uuidString, now = Date()
            let sources = ["TV1", "AS1", "CS1"].map { provider in
                StreamSession(matchID: fixture, playableURL: URL(string: "https://neutral.test/" + UUID().uuidString + ".m3u8")!,
                              streamType: .hls, providerName: provider)
            }
            for source in sources {
                LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: source.providerName == winner ? 1000 : 7000)
                SinglePlaybackContinuityStore.record(source.legacySource, elapsed: 90, mediaAdvance: 90, stalls: 0, at: now)
            }
            for order in [sources, Array(sources.reversed())] {
                let ranked = LiveSourceHealthStore.rankedSingleStreamSessions(order)
                XCTAssertEqual(ranked.first?.providerName, winner)
                XCTAssertEqual(Set(ranked.map(\.id)), Set(sources.map(\.id)), "Ranking cannot remove alternatives")
            }
        }
    }

    func testNeutralReliabilityPrefersSustainedDeliveryUntilThatExactMatchFails() throws {
        let saved = UserDefaults.standard.object(forKey: SinglePlaybackContinuityStore.storageKey)
        defer { UserDefaults.standard.set(saved, forKey: SinglePlaybackContinuityStore.storageKey) }
        for stableProvider in ["CS1", "TV1"] {
            LiveSourceHealthStore.resetForTesting()
            let fixture = UUID().uuidString
            let stable = StreamSession(matchID: fixture, playableURL: URL(string: "https://stable.test/" + UUID().uuidString + ".m3u8")!,
                streamType: .hls, providerName: stableProvider)
            let fast = StreamSession(matchID: fixture, playableURL: URL(string: "https://fast.test/" + UUID().uuidString + ".m3u8")!,
                streamType: .hls, providerName: "AS1")
            LiveSourceHealthStore.recordSuccess(for: stable, startupLatencyMs: 6000)
            LiveSourceHealthStore.recordSuccess(for: fast, startupLatencyMs: 500)
            LiveSourceHealthStore.recordMatchOutcome(.decoded, for: fast.legacySource, fixtureID: fixture, watchID: UUID())
            SinglePlaybackContinuityStore.record(stable.legacySource, elapsed: 90, mediaAdvance: 90, stalls: 0)
            XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([fast, stable]).first?.id, stable.id)
            LiveSourceHealthStore.recordMatchOutcome(.stalled, for: stable.legacySource, fixtureID: fixture, watchID: UUID())
            XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([stable, fast]).first?.id, fast.id)
            XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([stable, fast]).count, 2)
        }
    }

    func testRepeatedFailuresOverridePriorStartsAndDoNotQualifyAliasedSiblings() throws {
        let fixture = "quality-fixture-" + UUID().uuidString
        func candidate(_ name: String, _ origin: String, _ path: String) -> StreamSession {
            .init(matchID: fixture, playableURL: URL(string: "https://\(origin)/\(path).m3u8")!,
                  streamType: .hls, providerName: name)
        }
        let failing = candidate("CS1", "shared.test", "failed")
        let sibling = candidate("CS2", "shared.test", "different")
        let backup = candidate("AS1", "backup.test", "working")
        let alias = candidate("FS1", "shared.test", "failed")
        let now = Date(), watch = UUID()
        try seedSnapshots([healthKey(failing): positiveSnapshot(count: 30, latency: 300, at: now,
            recent: [recentSample(latency: 300, at: now)])])
        LiveSourceHealthStore.recordMatchOutcome(.decoded, for: failing.legacySource, fixtureID: fixture, watchID: watch, at: now)
        LiveSourceHealthStore.recordMatchOutcome(.stalled, for: failing.legacySource, fixtureID: fixture, watchID: watch, at: now)
        LiveSourceHealthStore.recordMatchOutcome(.decoded, for: failing.legacySource, fixtureID: fixture, watchID: watch, at: now)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: failing.legacySource, fixtureID: fixture, at: now), .recentlyFailed)
        LiveSourceHealthStore.recordMatchOutcome(.failed, for: failing.legacySource, fixtureID: fixture, watchID: UUID(), at: now)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: failing.legacySource, fixtureID: fixture, at: now), .repeatedlyFailed)
        XCTAssertFalse(LiveSourceHealthStore.positiveRecoveryHistory(for: sibling.legacySource, fixtureID: fixture, at: now))
        XCTAssertTrue(LiveSourceHealthStore.positiveRecoveryHistory(for: sibling.legacySource, fixtureID: "other-fixture", at: now))
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([failing, backup, sibling], at: now).first?.id, backup.id)
        LiveSourceHealthStore.recordMatchOutcome(.wrongProgramme, for: failing.legacySource, fixtureID: fixture, watchID: UUID(), at: now)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: alias.legacySource, fixtureID: fixture, at: now), .wrongProgramme)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: sibling.legacySource, fixtureID: fixture, at: now), .unknown)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: failing.legacySource, fixtureID: fixture, at: now.addingTimeInterval(86_400)), .unknown)
    }

    @MainActor
    func testFullHoldWinsOverQuickStartOnlyForSameMatchAndLaterStallRevokesIt() throws {
        let fast = try rankedSession(provider: "CS1", path: "first.m3u8", native: true)
        let stable = try rankedSession(provider: "CS3", path: "backup.m3u8", native: true)
        XCTAssertEqual(fast.matchID, stable.matchID)
        let watch = UUID()
        func record(_ outcome: LiveSourceHealthStore.MatchOutcome, _ session: StreamSession) {
            LiveSourceHealthStore.recordMatchOutcome(outcome, for: session.legacySource,
                fixtureID: session.matchID, watchID: watch)
        }
        record(.decoded, fast); record(.sustained, stable)
        let event = EventReference(id: fast.matchID, title: "A vs B", category: "football", date: nil,
                                   poster: nil, popular: false, teams: nil)
        let model = LivePlayerViewModel(event: event, providedSessions: [fast, stable], ownsRemoteCommands: false)
        defer { model.cleanup() }
        XCTAssertTrue(model.configureSingleStreamRanking())
        XCTAssertEqual(model.activeSession?.id, stable.id)
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([fast, stable]).first?.id, stable.id)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: stable.legacySource, fixtureID: "different-match"), .unknown)
        record(.stalled, stable); record(.sustained, stable)
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([fast, stable]).first?.id, fast.id)
    }

    func testCurrentMatchFailureCannotUseCoarseHostSuccessToBypassDiscoveryGrace() throws {
        let direct = try rankedSession(provider: "CS1", path: "failed-direct.m3u8", native: true)
        let now = Date()
        try seedSnapshots([healthKey(direct): positiveSnapshot(count: 3, latency: 600, at: now,
            recent: [recentSample(latency: 600, at: now)])])
        XCTAssertTrue(StreamDiscoveryCoordinator.hasCurrentDirectEvidence(direct, at: now))
        LiveSourceHealthStore.recordMatchOutcome(.stalled, for: direct.legacySource,
            fixtureID: direct.matchID, watchID: UUID(), at: now)
        XCTAssertFalse(StreamDiscoveryCoordinator.hasCurrentDirectEvidence(direct, at: now))
    }

    func testKnownFastMatchRouteBeatsUnmeasuredPreferredLanguage() throws {
        let measured = try rankedSession(provider: "CS1", path: "measured-match.m3u8", native: true)
        let unmeasuredEnglish = try rankedSession(provider: "TV11", path: "english-match.m3u8", native: true)
        let now = Date()
        try seedSnapshots([healthKey(measured): positiveSnapshot(count: 1, latency: 1_250, at: now,
            recent: [recentSample(latency: 1_250, at: now)])])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([unmeasuredEnglish, measured], at: now).first?.id, measured.id)
    }

    @MainActor
    func testVerifiedSkyCSDeliveryCanOutrankUnprovenTVDeliveryWithoutLosingEnglishPreference() throws {
        let now = Date(), station = try XCTUnwrap(SportsTVStation.station(provider: "TV11"))
        let request = StreamPlaybackRequest(event: station.event)
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_sky_football", streamID: "nuvio_sport_sky_football",
            manifestRevision: "fixture", verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
        let cs = StreamSession(matchID: station.id, playableURL: URL(string: "https://media.example/sky-cs.m3u8")!,
            streamType: .hls, providerName: "CS1", eventBinding: binding)
        let tv = StreamSession(matchID: station.id, playableURL: URL(string: "https://media.example/sky-tv.m3u8")!,
            streamType: .hls, providerName: "TV11")
        let saved = UserDefaults.standard.object(forKey: CommentaryPreference.storageKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: CommentaryPreference.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: CommentaryPreference.storageKey) }
        }
        UserDefaults.standard.set(CommentaryPreference.english.rawValue, forKey: CommentaryPreference.storageKey)
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([tv, cs], at: now).first?.id, cs.id,
            "A cold Watch must prefer the compatible exact Sky alternate, not its known incompatible TV packaging")
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([tv, cs], at: now.addingTimeInterval(100)).first?.id, tv.id,
            "Expired channel authority cannot supply the language or cold preference")
        try seedSnapshots([healthKey(cs): positiveSnapshot(count: 1, latency: 1_000, at: now,
            recent: [recentSample(latency: 1_000, at: now)])])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([tv, cs], at: now).first?.id, cs.id)
        let unbound = StreamSession(matchID: "different-event", playableURL: cs.playableURL,
            streamType: .hls, providerName: "CS1")
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([tv, unbound], at: now).first?.id, tv.id,
            "A generic CS label must not inherit Sky's language or channel authority")
    }

    func testSingleStreamTVSuccessDoesNotMakeAnotherStationOnTheCDNProven() throws {
        let tnt = StreamSession(matchID: "sports-channel:tnt-sports-2",
            playableURL: URL(string: "https://shared.example/tnt.m3u8")!, streamType: .hls, providerName: "TV13")
        let sky = StreamSession(matchID: "sports-channel:sky-sports-football",
            playableURL: URL(string: "https://shared.example/sky.m3u8")!, streamType: .hls, providerName: "TV11")
        LiveSourceHealthStore.recordSuccess(for: tnt, startupLatencyMs: 1_000)
        XCTAssertTrue(LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: tnt.legacySource))
        XCTAssertFalse(LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: sky.legacySource),
            "TNT's success must not release Sky from the discovery grace before its alternate arrives")
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        XCTAssertEqual(saved[healthKey(tnt)]?["successCount"] as? Int, 1,
            "Legacy ranking retains its unchanged aggregate for other playback contexts")
        XCTAssertEqual(saved["single-tv|TV13|shared.example"]?["successCount"] as? Int, 1)
        XCTAssertNil(saved["single-tv|TV11|shared.example"])
    }

    private let healthKeys = ["fotty.live.sourceHealth.v1", "fotty.live.lastGoodProvider.v1"]
    private var originalHealth: [String: Any] = [:]
    override func setUp() {
        super.setUp()
        originalHealth = Dictionary(uniqueKeysWithValues: healthKeys.compactMap { key in
            UserDefaults.standard.object(forKey: key).map { (key, $0) }
        })
        LiveSourceHealthStore.resetForTesting()
    }

    override func tearDown() {
        LiveSourceHealthStore.resetForTesting()
        for (key, value) in originalHealth { UserDefaults.standard.set(value, forKey: key) }
        originalHealth = [:]
        super.tearDown()
    }

    func testMatchSpecificFailuresNeverHideAnotherFixtureOnSameFamilyAndHost() throws {
        let fixtureA = try session(matchID: "fixture-a", path: "fixture-a/1")
        let fixtureB = try session(matchID: "fixture-b", path: "fixture-b/1")
        let reasons = ["HTTP 403", "HTTP 404", "No streams", "Channel unavailable",
                       "Startup timeout: no decoded video", "Playback stalled", "Certificate error"]
        for reason in reasons {
            // Strings are intentionally insufficient evidence for a host outage,
            // including strings which happen to mention transport or trust.
            LiveSourceHealthStore.recordFailure(for: fixtureA, wasStall: true, reason: reason)
            LiveSourceHealthStore.recordFailure(for: fixtureA, wasStall: true, reason: reason)
            let candidates = LiveSourceHealthStore.automaticCandidates(
                in: [fixtureA.legacySource, fixtureB.legacySource], contextKey: "football|all")
            XCTAssertEqual(Set(candidates.map(\.id)), [fixtureA.id, fixtureB.id], reason)
            XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(fixtureB.legacySource), reason)
            XCTAssertNil(LiveSourceHealthStore.cooldownRemaining(for: fixtureB.legacySource), reason)
        }
    }

    func testRollingURLReusedByAnotherFixtureRemainsAnAutomaticCandidate() throws {
        let fixtureA = try session(matchID: "fixture-a", path: "rolling-channel")
        let fixtureB = try session(matchID: "fixture-b", path: "rolling-channel")
        XCTAssertEqual(fixtureA.playableURL, fixtureB.playableURL)
        LiveSourceHealthStore.recordFailure(for: fixtureA, wasStall: false, reason: "Broadcast missing")
        LiveSourceHealthStore.recordFailure(for: fixtureA, wasStall: false, reason: "Broadcast missing")
        let candidates = LiveSourceHealthStore.automaticCandidates(in: [fixtureB.legacySource])
        XCTAssertEqual(candidates.map(\.id), [fixtureB.id])
    }

    func testCurrentAttemptStillExcludesExhaustedSourceIDs() throws {
        let exhausted = try session(matchID: "fixture-a", path: "fixture-a/1").legacySource
        let current = try session(matchID: "fixture-a", path: "fixture-a/2").legacySource
        let remaining = try session(matchID: "fixture-a", path: "fixture-a/3").legacySource
        LiveSourceHealthStore.recordFailure(for: exhausted, wasStall: false, reason: "No streams")
        LiveSourceHealthStore.recordFailure(for: current, wasStall: false, reason: "No streams")
        let next = LivePlaybackSourcePolicy.nextAutomaticSource(
            in: [exhausted, current, remaining], after: current,
            excluding: [exhausted.id, current.id], contextKey: "football|all")
        XCTAssertEqual(next?.id, remaining.id)
        XCTAssertNil(LivePlaybackSourcePolicy.nextAutomaticSource(
            in: [exhausted, current], after: current,
            excluding: [exhausted.id, current.id], contextKey: "football|all"))
    }

    func testSingleWatchRecoveryGivesOtherSuppliersATurnBeforeSixFailingSiblings() throws {
        let first = try rankedSession(provider: "FS1", path: "one.m3u8", native: true).legacySource
        let sibling = try rankedSession(provider: "FS2", path: "two.m3u8", native: true).legacySource
        let alternative = try rankedSession(provider: "CS1", path: "three.m3u8", native: true).legacySource
        let laterSibling = try rankedSession(provider: "FS3", path: "four.m3u8", native: true).legacySource
        let candidates = [sibling, laterSibling, alternative]
        let result = LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: candidates, attempted: [first])
        XCTAssertEqual(result.map(\.id), [alternative.id, sibling.id, laterSibling.id])
        XCTAssertEqual(Set(result.map(\.id)), Set(candidates.map(\.id)), "No quality/language/delivery is removed")
        XCTAssertEqual(LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: candidates,
            attempted: [first, alternative], after: alternative).map(\.id), candidates.map(\.id))
        XCTAssertEqual(LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: [laterSibling, alternative],
            attempted: [first, sibling], after: sibling).map(\.id), [alternative.id, laterSibling.id],
            "Supplier rotation continues after both families have been visited")
        XCTAssertEqual(LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: candidates,
            attempted: [first, alternative], after: first).map(\.id), [alternative.id, sibling.id, laterSibling.id],
            "A tied attempt count gives the other supplier its next turn")
        XCTAssertEqual(LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: candidates,
            attempted: []).map(\.id), candidates.map(\.id), "Another fixture has no inherited penalty")
        XCTAssertEqual(LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: [sibling],
            attempted: [first]).first?.id, sibling.id, "One supplier still retains every usable fallback")
    }

    func testSingleRecoveryKeepsProvenSpeedBeforeFamilyRotationAndUnknownDirectBeforeWeb() throws {
        let fs = try rankedSession(provider: "FS1", path: "failed-fs.m3u8", native: true).legacySource
        let direct = try rankedSession(provider: "CS2", path: "direct-fallback.m3u8", native: true).legacySource
        let proven = try rankedSession(provider: "CS5", path: "proven-start.m3u8", native: true).legacySource
        let web = try rankedSession(provider: "Score808", path: "embed/web-fallback", native: false).legacySource
        let ordered = LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: [proven, direct, web],
            attempted: [fs], after: fs, hasMeasuredSuccess: { $0.id == proven.id })
        XCTAssertEqual(ordered.map(\.id), [proven.id, direct.id, web.id], "An independent untried family keeps its positive startup evidence")
        let unknown = LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: [web, direct],
            attempted: [fs, proven], after: proven, hasMeasuredSuccess: { _ in false })
        XCTAssertEqual(unknown.map(\.id), [direct.id, web.id], "An untried web family cannot jump ahead of native alternatives")
    }

    func testHistoricalFamilySuccessCannotDrainFailingSiblingsBeforeIndependentDirectSource() throws {
        let first = try rankedSession(provider: "FS1", path: "first-failed.m3u8", native: true).legacySource
        let sibling = try rankedSession(provider: "FS2", path: "second-same-host.m3u8", native: true).legacySource
        let alternative = try rankedSession(provider: "CS2", path: "independent.m3u8", native: true).legacySource
        let ordered = LivePlaybackSourcePolicy.singleStreamRecoveryOrder(ranked: [sibling, alternative],
            attempted: [first], after: first, hasMeasuredSuccess: { _ in true })
        XCTAssertEqual(ordered.map(\.id), [alternative.id, sibling.id], "Coarse positive host history cannot overrule this attempt's failure")
        XCTAssertEqual(Set(ordered.map(\.id)), Set([sibling.id, alternative.id]))
    }

    func testLegacyBroadCircuitsAreClearedWithoutDiscardingPositiveMemory() throws {
        let source = try session(matchID: "fixture-b", path: "fixture-b/1").legacySource
        let key = "web|communitysports|embed.example.test"
        let lastSuccess = Date().timeIntervalSince1970
        let legacy: [String: [String: Any]] = [key: [
            "successCount": 4, "failureCount": 8, "stallCount": 3,
            "totalStartupMs": 12_000, "startupSamples": 4, "lastSuccessAt": lastSuccess,
            "consecutiveFailures": 8, "lastFailureAt": lastSuccess, "lastFailureReason": "HTTP 404"
        ]]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: legacy),
                                  forKey: "fotty.live.sourceHealth.v1")
        UserDefaults.standard.set(["football|all": "communitysports"], forKey: "fotty.live.lastGoodProvider.v1")

        XCTAssertEqual(LiveSourceHealthStore.automaticCandidates(in: [source]).map(\.id), [source.id])
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let migrated = try XCTUnwrap(saved[key])
        XCTAssertEqual(migrated["successCount"] as? Int, 4)
        XCTAssertEqual(migrated["totalStartupMs"] as? Int, 12_000)
        XCTAssertEqual(migrated["startupSamples"] as? Int, 4)
        XCTAssertEqual(migrated["lastSuccessAt"] as? Double, lastSuccess)
        XCTAssertEqual(migrated["failureCount"] as? Int, 0)
        XCTAssertEqual(migrated["stallCount"] as? Int, 0)
        XCTAssertNil(migrated["consecutiveFailures"])
        XCTAssertNil(migrated["lastFailureAt"])
        XCTAssertNil(migrated["lastFailureReason"])
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey: "fotty.live.lastGoodProvider.v1") as? [String: String],
                       ["football|all": "communitysports"])
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)
        for _ in 0..<20 {
            XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
            XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        }
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1,
                       "The migrated encoded payload must become the cached identity")
    }

    func testUnchangedPayloadDecodesOnceAcrossRankingAndSourcePickerReads() throws {
        let source = try session(matchID: "fixture-a", path: "fixture-a/1").legacySource
        let sibling = try session(matchID: "fixture-a", path: "fixture-a/2", family: "hotel").legacySource
        let data = try healthPayload(family: "communitysports")
        UserDefaults.standard.set(data, forKey: "fotty.live.sourceHealth.v1")
        for _ in 0..<20 {
            XCTAssertEqual(LiveSourceHealthStore.ranked([sibling, source]).first?.id, source.id)
            XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
            XCTAssertNil(LiveSourceHealthStore.cooldownRemaining(for: source))
            LiveSourceHealthStore.recordFailure(for: source, wasStall: true, reason: "Attempt-local stall")
            XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
            _ = LiveSourceHealthStore.score(for: source)
        }
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)
        UserDefaults.standard.set(data, forKey: "fotty.live.sourceHealth.v1")
        _ = LiveSourceHealthStore.ranked([source])
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1,
                       "Writing identical bytes must not invalidate the decoded payload")
    }

    func testDirectDefaultsReplacementAndRemovalInvalidateCachedSuccesses() throws {
        let source = try session(matchID: "fixture-a", path: "fixture-a/1").legacySource
        let sibling = try session(matchID: "fixture-a", path: "fixture-a/2", family: "hotel").legacySource
        UserDefaults.standard.set(try healthPayload(family: "communitysports"), forKey: "fotty.live.sourceHealth.v1")
        XCTAssertEqual(LiveSourceHealthStore.ranked([sibling, source]).first?.id, source.id)
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)

        UserDefaults.standard.set(try healthPayload(family: "score808"), forKey: "fotty.live.sourceHealth.v1")
        XCTAssertEqual(LiveSourceHealthStore.ranked([source, sibling]).first?.id, sibling.id)
        XCTAssertFalse(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "hotel", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 2)

        UserDefaults.standard.removeObject(forKey: "fotty.live.sourceHealth.v1")
        XCTAssertFalse(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertFalse(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "hotel", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 2,
                       "Missing data invalidates the cache without invoking JSONDecoder")
    }

    func testMalformedPayloadIsCachedWithoutErasureAndChangedPayloadRecovers() throws {
        let source = try session(matchID: "fixture-a", path: "fixture-a/1").legacySource
        let malformed = Data("not-json".utf8)
        UserDefaults.standard.set(malformed, forKey: "fotty.live.sourceHealth.v1")
        for _ in 0..<20 {
            XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(source))
            XCTAssertFalse(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        }
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"), malformed)
        UserDefaults.standard.set(try healthPayload(family: "communitysports"), forKey: "fotty.live.sourceHealth.v1")
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 2)
    }

    func testRecordedSuccessRefreshesCacheWithoutRedecodingPersistedWrites() throws {
        let source = try session(matchID: "fixture-a", path: "fixture-a/1").legacySource
        let sibling = try session(matchID: "fixture-a", path: "fixture-a/2", family: "hotel").legacySource
        XCTAssertFalse(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        for _ in 0..<4 {
            LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: 3_000, contextKey: "football|all")
        }
        LiveSourceHealthStore.recordSuccess(for: sibling, startupLatencyMs: 3_000)
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "hotel", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.ranked([sibling, source], contextKey: "football|all").first?.id, source.id)
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 0)
        let persisted = try XCTUnwrap(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: [String: Any]])
        XCTAssertEqual(saved["web|communitysports|embed.example.test"]?["successCount"] as? Int, 4)
        XCTAssertEqual(saved["web|score808|embed.example.test"]?["successCount"] as? Int, 1)
    }

    func testResetClearsPayloadCacheAndDecodeCounter() throws {
        let data = try healthPayload(family: "communitysports")
        UserDefaults.standard.set(data, forKey: "fotty.live.sourceHealth.v1")
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)
        LiveSourceHealthStore.resetForTesting()
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 0)
        XCTAssertFalse(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        UserDefaults.standard.set(data, forKey: "fotty.live.sourceHealth.v1")
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)
    }

    func testConcurrentReadsShareOneQueueOwnedDecodedPayload() throws {
        UserDefaults.standard.set(try healthPayload(family: "communitysports"), forKey: "fotty.live.sourceHealth.v1")
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            _ = LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test")
        }
        XCTAssertTrue(LiveSourceHealthStore.hasRecentSuccess(forProviderFamily: "communitysports", host: "embed.example.test"))
        XCTAssertEqual(LiveSourceHealthStore.snapshotDecodeCountForTesting(), 1)
    }

    func testMeasuredSuccessStillRanksProviderWithoutFailurePenalties() throws {
        let proven = try session(matchID: "fixture-a", path: "fixture-a/1", family: "communitysports")
        let preferredOnTie = try session(matchID: "fixture-b", path: "fixture-b/1", family: "hotel")
        for _ in 0..<4 {
            LiveSourceHealthStore.recordSuccess(for: proven, startupLatencyMs: 3_000)
        }
        let scoreBefore = LiveSourceHealthStore.score(for: proven)
        LiveSourceHealthStore.recordFailure(for: proven, wasStall: true, reason: "Startup timeout")
        XCTAssertEqual(LiveSourceHealthStore.score(for: proven), scoreBefore)
        XCTAssertEqual(LiveSourceHealthStore.automaticCandidates(
            in: [preferredOnTie.legacySource, proven.legacySource]).first?.id, proven.id)
    }

    func testSingleStreamFastASBeatsHundredSlowLegacySuccessesAndSlowLastGood() throws {
        let fast = try rankedSession(provider: "AS1", path: "fast.m3u8", native: true)
        let slow = try rankedSession(provider: "Score808", path: "slow", native: false)
        let now = Date()
        try seedSnapshots([healthKey(slow): positiveSnapshot(count: 100, latency: 9_000, at: now)])
        UserDefaults.standard.set(["football|all": "communitysports"], forKey: "fotty.live.lastGoodProvider.v1")
        LiveSourceHealthStore.recordSuccess(for: fast, startupLatencyMs: 1_000)
        let ranked = LiveSourceHealthStore.rankedSingleStreamSessions([slow, fast], contextKey: "football|all", at: Date())
        XCTAssertEqual(ranked.map(\.id), [fast.id, slow.id])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSources([slow.legacySource, fast.legacySource],
            contextKey: "football|all").map(\.id), [fast.id, slow.id])
        XCTAssertEqual(LiveSourceHealthStore.rankedSessions([fast, slow], contextKey: "football|all").first?.id, slow.id,
            "Legacy/Multi ranking must retain its lifetime-count and last-good behavior")
    }

    func testSingleStreamConfidenceIsCappedAndOnlyBreaksSameStartupBucketTies() throws {
        let popular = try rankedSession(provider: "Score808", path: "popular", native: false)
        let quick = try rankedSession(provider: "AS1", path: "quick", native: false)
        let now = Date()
        try seedSnapshots([
            healthKey(popular): positiveSnapshot(count: 100, latency: 2_900, at: now,
                recent: (0..<12).map { _ in recentSample(latency: 2_900, at: now) }),
            healthKey(quick): positiveSnapshot(count: 1, latency: 1_000, at: now,
                recent: [recentSample(latency: 1_000, at: now)])
        ])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([popular, quick], at: now).first?.id, quick.id)
        try seedSnapshots([
            healthKey(popular): positiveSnapshot(count: 100, latency: 1_300, at: now,
                recent: (0..<12).map { _ in recentSample(latency: 1_300, at: now) }),
            healthKey(quick): positiveSnapshot(count: 1, latency: 1_000, at: now,
                recent: [recentSample(latency: 1_000, at: now)])
        ])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([quick, popular], at: now).first?.id, popular.id)
        try seedSnapshots([
            healthKey(popular): positiveSnapshot(count: 100, latency: 1_300, at: now,
                recent: (0..<12).map { _ in recentSample(latency: 1_300, at: now) }),
            healthKey(quick): positiveSnapshot(count: 3, latency: 1_000, at: now,
                recent: (0..<3).map { _ in recentSample(latency: 1_000, at: now) })
        ])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([quick, popular], at: now).first?.id, quick.id,
            "Three and twelve observations have equal capped confidence within the same bucket")
    }

    func testSingleStreamMedianIsNotDominatedByOneStartupOutlier() throws {
        let typical = try rankedSession(provider: "AS1", path: "typical", native: false)
        let slower = try rankedSession(provider: "Score808", path: "slower", native: false)
        let now = Date()
        try seedSnapshots([
            healthKey(typical): positiveSnapshot(count: 3, latency: 31_000, at: now,
                recent: [1_000, 1_100, 90_000].map { recentSample(latency: $0, at: now) }),
            healthKey(slower): positiveSnapshot(count: 4, latency: 3_000, at: now,
                recent: (0..<4).map { _ in recentSample(latency: 3_000, at: now) })
        ])
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([slower, typical], at: now).first?.id, typical.id)
    }

    func testSingleStreamStaleFutureAndCorruptHistoryCannotBoostUnknownWebAboveNative() throws {
        let stale = try rankedSession(provider: "Score808", path: "stale", native: false)
        let native = try rankedSession(provider: "AS1", path: "unknown.m3u8", native: true)
        let now = Date()
        let old = now.addingTimeInterval(-7 * 24 * 60 * 60 - 1)
        let future = now.addingTimeInterval(60)
        var corrupted = positiveSnapshot(count: -100, latency: 1_000, at: now, recent: [
            recentSample(latency: -1, at: now), recentSample(latency: Int.max, at: now),
            recentSample(latency: 1, at: future), recentSample(latency: 1, at: old)
        ])
        corrupted["totalStartupMs"] = Int.max
        corrupted["startupSamples"] = -1
        for snapshot in [positiveSnapshot(count: 100, latency: 1, at: old),
                         positiveSnapshot(count: 100, latency: 1, at: future), corrupted] {
            try seedSnapshots([healthKey(stale): snapshot])
            UserDefaults.standard.set(["football|all": "communitysports"], forKey: "fotty.live.lastGoodProvider.v1")
            XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([stale, native], contextKey: "football|all", at: now)
                .map(\.id), [native.id, stale.id])
        }
    }

    func testSingleStreamUnknownTiesUseActualDirectContractNotProviderOrLastGood() throws {
        let webAS = try rankedSession(provider: "AS1", path: "web", native: false)
        let nativeCS = try rankedSession(provider: "CS1", path: "native.m3u8", native: true)
        UserDefaults.standard.set(["football|all": "plaviosports"], forKey: "fotty.live.lastGoodProvider.v1")
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([webAS, nativeCS], contextKey: "football|all")
            .map(\.id), [nativeCS.id, webAS.id])
    }

    func testSingleStreamProvenFastWebBeatsUnknownNativeAndDoesNotFilterFailures() throws {
        let web = try rankedSession(provider: "Score808", path: "proven", native: false)
        let native = try rankedSession(provider: "AS1", path: "unknown.m3u8", native: true)
        LiveSourceHealthStore.recordSuccess(for: web, startupLatencyMs: 800)
        let before = LiveSourceHealthStore.rankedSingleStreamSessions([native, web]).map(\.id)
        XCTAssertEqual(before, [web.id, native.id])
        LiveSourceHealthStore.recordFailure(for: web, wasStall: true, reason: "Another fixture's missing broadcast")
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([native, web]).map(\.id), before)
        XCTAssertFalse(LiveSourceHealthStore.isTemporarilyUnavailable(web.legacySource))
    }

    func testSingleStreamEqualUnknownCandidatesKeepStableInputOrderWithoutFamilyPecking() throws {
        let streamEx = try session(matchID: "a", path: "a", family: "communitysports")
        let score808 = try session(matchID: "b", path: "b", family: "hotel")
        for _ in 0..<10 {
            XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([streamEx, score808]).map(\.id), [streamEx.id, score808.id])
            XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([score808, streamEx]).map(\.id), [score808.id, streamEx.id])
        }
        XCTAssertEqual(LiveSourceHealthStore.rankedSessions([streamEx, score808]).first?.id, score808.id,
            "The old Multi ranking still has its original family tie order")
    }

    func testSingleStreamMissingLatencyIsWeakPositiveEvidenceNotInventedSpeed() throws {
        let measured = try rankedSession(provider: "AS1", path: "measured", native: false)
        let unmeasured = try rankedSession(provider: "Score808", path: "decoded-no-timing", native: false)
        let unknown = try rankedSession(provider: "CS1", path: "unknown", native: false)
        LiveSourceHealthStore.recordSuccess(for: unmeasured, startupLatencyMs: nil)
        LiveSourceHealthStore.recordSuccess(for: measured, startupLatencyMs: 8_000)
        XCTAssertEqual(LiveSourceHealthStore.rankedSingleStreamSessions([unknown, unmeasured, measured]).map(\.id),
            [measured.id, unmeasured.id, unknown.id])
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        XCTAssertEqual((saved[healthKey(unmeasured)]?["recentStartupSamples"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(saved[healthKey(unmeasured)]?["startupSamples"] as? Int, 0)
    }

    func testSingleStreamRollingDecodedStartupSamplesStayBoundedWithoutChangingLegacyTotals() throws {
        let source = try rankedSession(provider: "AS1", path: "rolling.m3u8", native: true)
        for latency in 1_000..<1_015 { LiveSourceHealthStore.recordSuccess(for: source, startupLatencyMs: latency) }
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let snapshot = try XCTUnwrap(saved[healthKey(source)])
        let recent = try XCTUnwrap(snapshot["recentStartupSamples"] as? [[String: Any]])
        XCTAssertEqual(recent.count, 12)
        XCTAssertEqual(recent.compactMap { $0["latencyMs"] as? Int }, Array(1_003..<1_015))
        XCTAssertEqual(snapshot["successCount"] as? Int, 15)
        XCTAssertEqual(snapshot["startupSamples"] as? Int, 15)
        XCTAssertEqual(snapshot["totalStartupMs"] as? Int, (1_000..<1_015).reduce(0, +))
        XCTAssertEqual(Set(recent.flatMap(\.keys)), ["recordedAt", "latencyMs"])
    }

    private func rankedSession(provider: String, path: String, native: Bool) throws -> StreamSession {
        StreamSession(matchID: "ranking-fixture", playableURL: try XCTUnwrap(URL(string: "https://rank.example.test/\(path)")),
            streamType: native ? .hls : .unknown, providerName: provider,
            declaredPlaybackEndpoint: native ? .directMedia : .webPage)
    }

    private func healthKey(_ session: StreamSession) -> String {
        "web|\(LiveSourceHealthStore.providerFamily(for: session.legacySource))|\(session.playableURL.host!)"
    }

    private func seedSnapshots(_ values: [String: [String: Any]]) throws {
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
            forKey: "fotty.live.sourceHealth.v1")
    }

    private func recentSample(latency: Int, at date: Date) -> [String: Any] {
        ["recordedAt": date.timeIntervalSince1970, "latencyMs": latency]
    }

    private func positiveSnapshot(count: Int, latency: Int, at date: Date, recent: [[String: Any]]? = nil) -> [String: Any] {
        var value: [String: Any] = ["successCount": count, "failureCount": 0, "stallCount": 0,
            "totalStartupMs": count * latency, "startupSamples": count, "lastSuccessAt": date.timeIntervalSince1970]
        if let recent { value["recentStartupSamples"] = recent }
        return value
    }

    /// Owner decision 9 Nov 2026 (option A): a relaunch must not forget that a
    /// delivery just sustained this match. Jet started a cold CS1 ahead of a
    /// TV1 that had held the same fixture for 92 s, costing a 20 s timeout.
    func testSustainedMatchEvidenceSurvivesSimulatedRelaunch() throws {
        LiveSourceHealthStore.resetForTesting()
        defer { LiveSourceHealthStore.resetForTesting() }
        let fixture = "cricket-fixture:icc:\(UUID().uuidString)"
        let tv = StreamSession(matchID: fixture, playableURL: URL(string: "https://tv.example.test/willow.m3u8")!,
                               streamType: .hls, providerName: "TV1")
        let wrong = StreamSession(matchID: fixture, playableURL: URL(string: "https://cs.example.test/other.m3u8")!,
                                  streamType: .hls, providerName: "CS2")
        LiveSourceHealthStore.recordMatchOutcome(.decoded, for: tv.legacySource, fixtureID: fixture, watchID: UUID())
        LiveSourceHealthStore.recordMatchOutcome(.sustained, for: tv.legacySource, fixtureID: fixture, watchID: UUID())
        LiveSourceHealthStore.recordMatchOutcome(.wrongProgramme, for: wrong.legacySource, fixtureID: fixture, watchID: UUID())
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: tv), .sustained)

        LiveSourceHealthStore.reloadMatchEvidenceForTesting()

        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: tv), .sustained, "Sustained evidence survives a relaunch")
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: wrong), .wrongProgramme, "A wrong-programme report survives")
        XCTAssertFalse(LiveSourceHealthStore.sustainedMatchProviders(for: fixture).isEmpty,
                       "The resolver can hold the first choice for the provider that sustained this match")
        let other = StreamSession(matchID: "cricket-fixture:icc:other", playableURL: tv.playableURL,
                                  streamType: .hls, providerName: "TV1")
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: other), .unknown, "Evidence stays scoped to its fixture")
    }

    func testPersistedMatchEvidenceExpiresAfterSixHours() throws {
        LiveSourceHealthStore.resetForTesting()
        defer { LiveSourceHealthStore.resetForTesting() }
        let fixture = "sports-fixture:premier-league:\(UUID().uuidString)", now = Date()
        let old = StreamSession(matchID: fixture, playableURL: URL(string: "https://tv.example.test/old.m3u8")!,
                                streamType: .hls, providerName: "TV1")
        let recent = StreamSession(matchID: fixture, playableURL: URL(string: "https://tv.example.test/recent.m3u8")!,
                                   streamType: .hls, providerName: "TV2")
        LiveSourceHealthStore.recordMatchOutcome(.sustained, for: old.legacySource, fixtureID: fixture, watchID: UUID(),
                                                 at: now.addingTimeInterval(-6 * 3600 + 60))
        LiveSourceHealthStore.recordMatchOutcome(.sustained, for: recent.legacySource, fixtureID: fixture, watchID: UUID(),
                                                 at: now.addingTimeInterval(-60))
        LiveSourceHealthStore.reloadMatchEvidenceForTesting(at: now.addingTimeInterval(120))
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: old, at: now.addingTimeInterval(120)), .unknown,
                       "Evidence older than six hours is not restored")
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: recent, at: now.addingTimeInterval(120)), .sustained)
    }

    /// The main family is CS; "hotel" marks a Score808 sibling.
    private func session(matchID: String, path: String, family: String = "communitysports") throws -> StreamSession {
        StreamSession(matchID: matchID,
            playableURL: try XCTUnwrap(URL(string: "https://embed.example.test/embed/\(family)/\(path)")),
            streamType: .unknown, providerName: family == "hotel" ? "Score808" : "CS1")
    }

    private func healthPayload(family: String) throws -> Data {
        let payload: [String: [String: Any]] = ["web|\(family)|embed.example.test": [
            "successCount": 4, "failureCount": 0, "stallCount": 0,
            "totalStartupMs": 12_000, "startupSamples": 4,
            "lastSuccessAt": Date().timeIntervalSince1970
        ]]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}
