import Foundation
import XCTest

@testable import Fotty

@MainActor
final class CatalogRuntimeOwnershipTests: XCTestCase {
    func testPollingReleaseCannotCancelAnotherVisibleSurface() {
        let home = UUID(), matchday = UUID(), player = UUID()
        var demand = LiveScorePollingDemand()
        demand.update(owner: home, isActive: true)
        demand.update(owner: matchday, isActive: true)
        demand.update(owner: home, isActive: false)
        XCTAssertEqual(demand.owners, [matchday])
        demand.update(owner: player, isActive: true)
        demand.update(owner: matchday, isActive: false)
        XCTAssertEqual(demand.owners, [player])
        demand.update(owner: home, isActive: false)
        XCTAssertTrue(demand.isNeeded, "A hidden tab cannot revoke another consumer")
        demand.update(owner: player, isActive: false)
        XCTAssertFalse(demand.isNeeded)
    }

    func testPollingDemandIsIdempotentAcrossRapidSceneTransitions() {
        let home = UUID(), player = UUID()
        var demand = LiveScorePollingDemand()
        for _ in 0..<20 {
            demand.update(owner: home, isActive: true)
            demand.update(owner: home, isActive: true)
            demand.update(owner: player, isActive: true)
            demand.update(owner: home, isActive: false)
            XCTAssertEqual(demand.owners, [player])
            demand.update(owner: player, isActive: false)
            XCTAssertFalse(demand.isNeeded)
        }
    }

    func testBadgeFreshnessExpiresWithoutRecreatingService() async throws {
        let suite = "FottyTests.badge-freshness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var calls = 0
        let service = TeamBrandService(defaults: defaults, now: { now }, bootstrapRefresh: {
            calls += 1
            return 1
        })
        await service.bootstrapIfNeeded()
        XCTAssertEqual(calls, 1)
        now = now.addingTimeInterval(24 * 3_600 - 1)
        await service.bootstrapIfNeeded()
        XCTAssertEqual(calls, 1)
        now = now.addingTimeInterval(1)
        await service.bootstrapIfNeeded()
        XCTAssertEqual(calls, 2, "Resident app must recheck after its receipt expires")
    }

    func testFailedBadgeRefreshDoesNotRenewReceiptAndRetriesAfterBoundedDelay() async throws {
        let suite = "FottyTests.badge-retry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var calls = 0
        let service = TeamBrandService(defaults: defaults, now: { now }, bootstrapRefresh: {
            calls += 1
            return 0
        })
        await service.bootstrapIfNeeded()
        XCTAssertNil(defaults.object(forKey: "fotty.cache.teamBadges.lastRefresh"))
        await service.bootstrapIfNeeded()
        XCTAssertEqual(calls, 1)
        now = now.addingTimeInterval(120)
        await service.bootstrapIfNeeded()
        XCTAssertEqual(calls, 2)
    }

    func testFutureBadgeReceiptDoesNotSuppressRefresh() async throws {
        let suite = "FottyTests.badge-future.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(3_600), forKey: "fotty.cache.teamBadges.lastRefresh")
        var calls = 0
        let service = TeamBrandService(defaults: defaults, now: { now }, bootstrapRefresh: {
            calls += 1
            return 1
        })
        await service.bootstrapIfNeeded()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(defaults.object(forKey: "fotty.cache.teamBadges.lastRefresh") as? Date, now)
    }

    private func event(id: String = "same", title: String, category: String = "football") -> EventReference {
        .init(id: id, title: title, category: category, date: 1_800_003_600,
              poster: nil, popular: false, teams: nil, sources: [])
    }

    func testPreparedSearchNormalizesOnceAndPreservesLeagueDisambiguation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let football = event(title: "Chelsea vs Brighton")
        let cricket = event(id: "cpl-final", title: "Trinbago Knight Riders vs Barbados Royals", category: "cricket")
        var leagueEvaluations = 0
        let index = HomeSportsSearch.prepare(in: .init(events: [football, cricket], now: now)) { event in
            leagueEvaluations += 1
            return event.id == football.id ? "Premier League" : nil
        }
        let evaluationsAfterPreparation = leagueEvaluations
        XCTAssertEqual(index.results(query: "PREMIER LEAGUE").map(\.id), [football.id])
        XCTAssertEqual(index.results(query: "chelsea brighton").map(\.id), [football.id])
        XCTAssertEqual(index.results(query: "CPL").map(\.id), [cricket.id])
        XCTAssertTrue(index.results(query: " ").isEmpty)
        XCTAssertEqual(leagueEvaluations, evaluationsAfterPreparation, "Typing must not normalize the catalog again")
    }

    func testSearchInitialEmptyAndSameIDReplacementUseNewRevision() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = HomeSportsSearch.prepare(in: .init(events: [], now: now))
        XCTAssertTrue(empty.results(query: "Bogota").isEmpty)
        let original = HomeSportsSearch.prepare(in: .init(events: [event(title: "Internacional de Bogotá vs Example", category: "basketball")], now: now))
        XCTAssertEqual(original.results(query: "Bogota").map(\.id), ["same"])
        let replacement = HomeSportsSearch.prepare(in: .init(events: [event(title: "Chelsea vs Brighton")], now: now))
        XCTAssertTrue(replacement.results(query: "Bogota").isEmpty)
        XCTAssertEqual(replacement.results(query: "Chelsea").map(\.id), ["same"])
        XCTAssertNotEqual(SportsSearchIndexKey(catalogRevision: 1, clockDate: now, scoreRevision: nil),
                          SportsSearchIndexKey(catalogRevision: 2, clockDate: now, scoreRevision: nil))
    }

    func testSearchKeyInvalidatesClockAndScoreChanges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = SportsSearchIndexKey(catalogRevision: 1, clockDate: now, scoreRevision: now)
        XCTAssertNotEqual(initial, .init(catalogRevision: 1, clockDate: now.addingTimeInterval(60), scoreRevision: now))
        XCTAssertNotEqual(initial, .init(catalogRevision: 1, clockDate: now, scoreRevision: now.addingTimeInterval(1)))
    }

    func testSearchPreparationOwnerIgnoresNonemptyEditsButPreservesEveryIndexInvalidation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let index = SportsSearchIndexKey(catalogRevision: 1, clockDate: now, scoreRevision: now)
        let initial = SportsSearchPreparationKey(index: index, query: "A")
        XCTAssertTrue(initial.needsIndex)
        for query in ["Ar", "Arsenal", "Premier League", "zz-no-match"] {
            XCTAssertEqual(initial, .init(index: index, query: query),
                           "Typing must not cancel preparation of the same catalog")
        }
        for query in ["", " ", "\n\t"] {
            let empty = SportsSearchPreparationKey(index: index, query: query)
            XCTAssertFalse(empty.needsIndex)
            XCTAssertNotEqual(initial, empty, "Clearing the prompt cancels an unfinished preparation")
        }
        for changed in [
            SportsSearchIndexKey(catalogRevision: 2, clockDate: now, scoreRevision: now),
            .init(catalogRevision: 1, clockDate: now.addingTimeInterval(60), scoreRevision: now),
            .init(catalogRevision: 1, clockDate: now, scoreRevision: now.addingTimeInterval(1)),
            .init(catalogRevision: 1, clockDate: now, scoreRevision: nil)
        ] {
            XCTAssertNotEqual(initial, .init(index: changed, query: "A"))
        }
    }

    /// Compare the former query-owned cancellation pattern with the new owner
    /// key using exactly the same cooperative producer and edit points. Counts
    /// are deterministic evidence of avoided work, not SwiftUI/device latency.
    func testQueryIndependentOwnerAvoidsRepeatedColdNormalizationWhileTyping() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = (0..<96).map { offset in
            EventReference(id: "typing-\(offset)", title: "Arsenal vs Chelsea", category: "football",
                date: 1_800_003_600 + Int64(offset) * 60, poster: nil, popular: false, teams: nil, sources: [])
        }
        let discovery = HomeSportsDiscovery(events: rows, now: now)
        XCTAssertEqual(discovery.items.count, 96)
        let timing = FottyAsyncTiming(monotonicNow: { 0 }, sleep: { _ in })
        var legacyQuery = "A"
        var legacyClassifications = 0
        var legacyAttempts = 0
        var legacyIndex: HomeSportsSearch.Index?
        let edits = ["Ar", "Arsenal"]
        while legacyIndex == nil, legacyAttempts < 3 {
            let requestedQuery = legacyQuery
            let nextQuery = legacyAttempts < edits.count ? edits[legacyAttempts] : nil
            var attemptRows = 0
            legacyIndex = await HomeSportsSearch.prepareForQuery(in: discovery, query: requestedQuery,
                leagueName: { _ in
                    legacyClassifications += 1
                    attemptRows += 1
                    if attemptRows == 16, let nextQuery { legacyQuery = nextQuery }
                    return "Premier League"
                }, isCurrent: { legacyQuery == requestedQuery }, timing: timing)
            legacyAttempts += 1
        }
        let oldPrepared = try XCTUnwrap(legacyIndex)
        XCTAssertEqual(legacyAttempts, 3)
        XCTAssertEqual(legacyClassifications, 128)

        let indexKey = SportsSearchIndexKey(catalogRevision: 1, clockDate: now, scoreRevision: nil)
        var latestQuery = "A"
        let owner = SportsSearchPreparationKey(index: indexKey, query: latestQuery)
        var retainedClassifications = 0
        let retained = await HomeSportsSearch.prepareForQuery(in: discovery, query: latestQuery,
            leagueName: { _ in
                retainedClassifications += 1
                if retainedClassifications == 16 { latestQuery = "Ar" }
                if retainedClassifications == 32 { latestQuery = "Arsenal" }
                return "Premier League"
            }, isCurrent: { owner == .init(index: indexKey, query: latestQuery) }, timing: timing)
        let prepared = try XCTUnwrap(retained)
        XCTAssertEqual(retainedClassifications, 96, "Each row is normalized once despite two query edits")
        XCTAssertEqual(latestQuery, "Arsenal")
        XCTAssertEqual(prepared.results(query: latestQuery).map(\.id), rows.map(\.id))
        XCTAssertEqual(prepared.results(query: latestQuery).map(\.id), oldPrepared.results(query: legacyQuery).map(\.id))
        print("[SearchOwnerWork] rows=96 query_edits=2 legacy_attempts=\(legacyAttempts) legacy_rows=\(legacyClassifications) retained_attempts=1 retained_rows=\(retainedClassifications) avoided_rows=\(legacyClassifications - retainedClassifications)")
    }

    func testIndependentSearchPreparationStillDiscardsClearedOrReplacedOwners() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = (0..<32).map { offset in
            EventReference(id: "revoked-\(offset)", title: "Arsenal vs Chelsea", category: "football",
                date: 1_800_003_600 + Int64(offset) * 60, poster: nil, popular: false, teams: nil, sources: [])
        }
        let discovery = HomeSportsDiscovery(events: rows, now: now)
        let index = SportsSearchIndexKey(catalogRevision: 1, clockDate: now, scoreRevision: nil)
        let owner = SportsSearchPreparationKey(index: index, query: "Arsenal")
        for replacement in [
            SportsSearchPreparationKey(index: index, query: ""),
            .init(index: .init(catalogRevision: 2, clockDate: now, scoreRevision: nil), query: "Arsenal")
        ] {
            var current = owner
            var classifications = 0
            let result = await HomeSportsSearch.prepareForQuery(in: discovery, query: "Arsenal",
                leagueName: { _ in
                    classifications += 1
                    if classifications == 16 { current = replacement }
                    return "Premier League"
                }, isCurrent: { current == owner },
                timing: .init(monotonicNow: { 0 }, sleep: { _ in }))
            XCTAssertNil(result)
            XCTAssertEqual(classifications, 16, "Revocation stops at the existing sixteen-row checkpoint")
        }
    }

    func testCooperativeSearchPreparationMatchesSynchronousIndex() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let discovery = HomeSportsDiscovery(events: [
            event(id: "football", title: "Chelsea vs Brighton"),
            event(id: "cpl", title: "CPL · Trinbago Knight Riders vs Guyana Amazon Warriors", category: "cricket"),
            event(id: "basketball", title: "Internacional de Bogotá vs Example", category: "basketball"),
            .init(id: "willow", title: "Willow Cricket", category: "cricket", date: -3_600_000,
                  poster: nil, popular: false, teams: nil, sources: [])
        ], now: now)
        let league: (EventReference) -> String? = { $0.id == "football" ? "Premier League" : nil }
        let synchronous = HomeSportsSearch.prepare(in: discovery, leagueName: league)
        let prepared = await HomeSportsSearch.prepareForQuery(in: discovery, query: "football", leagueName: league)
        let cooperative = try XCTUnwrap(prepared)
        XCTAssertEqual(cooperative.entries.map(\.haystack), synchronous.entries.map(\.haystack))
        XCTAssertEqual(cooperative.entries.map(\.normalizedLeague), synchronous.entries.map(\.normalizedLeague))
        XCTAssertEqual(cooperative.exactFootballLeagues, synchronous.exactFootballLeagues)
        for query in ["PREMIER LEAGUE", "Chelsea Brighton", "CPL", "Bogota", "Willow channel", "zz-", " ", "---"] {
            XCTAssertEqual(cooperative.results(query: query).map(\.id), synchronous.results(query: query).map(\.id), query)
        }
    }

    func testEmptySearchQueryAvoidsCatalogPreparation() async {
        let discovery = HomeSportsDiscovery(events: [event(title: "Chelsea vs Brighton")])
        var evaluated = 0
        for query in ["", " ", "\n\t"] {
            let result = await HomeSportsSearch.prepareForQuery(in: discovery, query: query, leagueName: { _ in
                evaluated += 1
                return "Premier League"
            })
            XCTAssertNil(result)
        }
        XCTAssertEqual(evaluated, 0, "The empty Search prompt must not classify or normalize the lineup")
    }

    func testCooperativeSearchCancellationDiscardsUnpublishedIndex() async {
        let discovery = HomeSportsDiscovery(events: (0..<64).map {
            event(id: "row-\($0)", title: "Chelsea vs Brighton")
        })
        var evaluated = 0
        var owner: Task<HomeSportsSearch.Index?, Never>?
        owner = Task { @MainActor in
            await HomeSportsSearch.prepareForQuery(in: discovery, query: "Chelsea", leagueName: { _ in
                evaluated += 1
                owner?.cancel()
                return "Premier League"
            })
        }
        let result = await owner?.value
        XCTAssertNil(result ?? nil)
        XCTAssertEqual(evaluated, 1, "Cancellation must stop the partial index before a second row or publication")
    }

    func testCooperativeSearchRevisionChangeDiscardsUnpublishedIndex() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let requested = SportsSearchIndexKey(catalogRevision: 1, clockDate: now, scoreRevision: now)
        var current = requested
        var evaluated = 0
        let discovery = HomeSportsDiscovery(events: (0..<64).map {
            event(id: "row-\($0)", title: "Chelsea vs Brighton")
        }, now: now)
        let result = await HomeSportsSearch.prepareForQuery(in: discovery, query: "Chelsea", leagueName: { _ in
            evaluated += 1
            current = .init(catalogRevision: 2, clockDate: now, scoreRevision: now)
            return "Premier League"
        }, isCurrent: { current == requested })
        XCTAssertNil(result)
        XCTAssertEqual(evaluated, 1, "A replacement receipt cannot publish an index begun for the old revision")
    }

    func testScoreKickoffIndexParsesEachCurrentStringOnceIncludingMalformedDates() {
        let valid = "2027-01-15T20:00:00Z", fractional = "2027-01-15T20:00:00.123Z"
        var calls = 0
        var index = FootballKickoffDateIndex()
        let parse: (String) -> Date? = { raw in
            calls += 1
            return FootballNormalizer.parseISO8601Date(raw)
        }
        index.replace(dates: [valid, valid, fractional, "invalid"], parse: parse)
        XCTAssertEqual(calls, 3)
        for _ in 0..<20 {
            XCTAssertEqual(index.date(for: valid), FootballNormalizer.parseISO8601Date(valid))
            XCTAssertEqual(index.date(for: fractional), FootballNormalizer.parseISO8601Date(fractional))
            XCTAssertNil(index.date(for: "invalid"))
        }
        index.replace(dates: ["invalid", fractional, valid], parse: parse)
        XCTAssertEqual(calls, 3, "Unchanged score receipts must not reconstruct date formatters")
    }

    func testScoreKickoffIndexDropsRemovedDatesAndAcceptsSameFixtureCorrection() {
        let old = "2027-01-15T20:00:00Z", corrected = "2027-01-15T21:00:00Z"
        var index = FootballKickoffDateIndex()
        index.replace(dates: [old])
        XCTAssertNotNil(index.date(for: old))
        index.replace(dates: [corrected, "invalid"])
        XCTAssertNil(index.date(for: old), "A corrected fixture cannot retain its former kickoff")
        XCTAssertEqual(index.date(for: corrected), FootballNormalizer.parseISO8601Date(corrected))
        XCTAssertNil(index.date(for: "invalid"))
        index.replace(dates: [])
        XCTAssertNil(index.date(for: corrected))
    }

    func testPublishedDiscoveryFactsRemainPacketConsistentButRawEventsRequireNewReceipt() {
        let selection = SportsPersonalizationPolicy.prepareSelection(teams: [], leagues: [])
        let oldKey = HomePersonalizationFactsKey(contentRevision: 1, scoreRevisionMilliseconds: 1,
                                                selectionIdentity: selection.identity)
        let cached = HomePersonalizationFactsCache(key: oldKey,
            facts: ["same": .init(isFollowed: true, isMajorLeague: true, isCPL: false)])
        for pendingKey in [
            HomePersonalizationFactsKey(contentRevision: 2, scoreRevisionMilliseconds: 1, selectionIdentity: selection.identity),
            HomePersonalizationFactsKey(contentRevision: 1, scoreRevisionMilliseconds: 2, selectionIdentity: selection.identity)
        ] {
            XCTAssertTrue(cached.facts(matching: pendingKey).isEmpty,
                          "New raw fixture/source/score data must never consume ID-only old facts")
            XCTAssertEqual(cached.factsForPublishedProjection(selection: selection.identity), cached.facts,
                           "Unchanged published rows keep their own facts while the next packet is prepared")
        }
        let editedSelection = SportsPersonalizationPolicy.SelectionIdentity(
            teams: [.init(name: "Arsenal", category: "football")], competitions: [])
        XCTAssertTrue(cached.factsForPublishedProjection(selection: editedSelection).isEmpty,
                      "An interest edit invalidates published personalization immediately")
    }

    func testDiscoveryRankingSnapshotMatchesUncachedOrderAndInvalidatesEveryScopeAxis() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = HomeSportsDiscovery(events: [
            event(id: "football", title: "Arsenal vs Chelsea"),
            event(id: "cricket", title: "West Indies vs India", category: "cricket")
        ], now: now).items
        let ranked = HomeSportsDiscovery.prioritized(items) {
            .init(phase: $0.isOnNow ? 0 : 1, relevance: $0.sport == "cricket" ? 0 : 1,
                  available: $0.canWatch ? 0 : 1)
        }
        let selection = SportsPersonalizationPolicy.SelectionIdentity(teams: [], competitions: [])
        func scope(sport: String = "all-sports", league: String = "all", cricket: String = "all",
                   following: Bool = false, interests: Bool = false,
                   selected: SportsPersonalizationPolicy.SelectionIdentity? = nil) -> HomeSportActivityProjectionKey {
            .init(selectedSport: sport, selectedFootballLeague: league, selectedCricketFilter: cricket,
                  showFollowedOnly: following, onlyShowSelectedInterests: interests,
                  selectionIdentity: selected ?? selection)
        }
        let key = HomeDiscoveryRankingKey(projectionRevision: 1, scope: scope())
        let snapshot = HomeDiscoveryRankingSnapshot(key: key, home: ranked, lineup: items)
        XCTAssertEqual(snapshot.items(matching: key, home: true)?.map(\.id), ranked.map(\.id))
        XCTAssertEqual(snapshot.items(matching: key, home: false)?.map(\.id), items.map(\.id))
        XCTAssertNil(snapshot.items(matching: .init(projectionRevision: 2, scope: scope()), home: true),
                     "Clock/score/source/fixture changes advance the published projection, even with unchanged IDs")
        for edited in [scope(sport: "cricket"), scope(league: "premier-league"), scope(cricket: "cpl"),
                       scope(following: true), scope(interests: true),
                       scope(selected: .init(teams: [.init(name: "Chelsea", category: "football")], competitions: []))] {
            XCTAssertNil(snapshot.items(matching: .init(projectionRevision: 1, scope: edited), home: true))
        }
    }

    /// Bounded synthetic costs, not a frame-rate or device-readiness assertion.
    /// Keep generation outside the intervals, use the production decode/search
    /// helpers, and print raw milliseconds instead of imposing timing gates.
    func testCatalogDecodeAndProjectionMicrobenchmark() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let maximumPayloadBytes = 4 * 1_024 * 1_024
        let cases: [(name: String, rows: Int, targetBytes: Int?)] = [
            ("typical", 250, nil),
            ("near_ingestion_limit", 9_500, maximumPayloadBytes * 95 / 100)
        ]
        for benchmark in cases {
            let payload = try benchmarkPayload(rows: benchmark.rows, targetBytes: benchmark.targetBytes, now: now)
            XCTAssertLessThanOrEqual(payload.count, maximumPayloadBytes)
            for iteration in 1...3 {
                let decodeStart = DispatchTime.now().uptimeNanoseconds
                let decoded = try AnalyticalDataEngine.decodeMatches(from: payload)
                let decodeMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - decodeStart) / 1_000_000
                XCTAssertEqual(decoded.count, benchmark.rows)

                let projectionStart = DispatchTime.now().uptimeNanoseconds
                let catalog = AnalyticalDataEngine.deduplicateMatches(decoded)
                let dedupMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - projectionStart) / 1_000_000
                let discoveryStart = DispatchTime.now().uptimeNanoseconds
                let discovery = HomeSportsDiscovery(events: catalog, now: now)
                let discoveryMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - discoveryStart) / 1_000_000
                let searchStart = DispatchTime.now().uptimeNanoseconds
                let index = HomeSportsSearch.prepare(in: discovery)
                let matches = index.results(query: "Arsenal")
                let searchMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - searchStart) / 1_000_000
                let projectionMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - projectionStart) / 1_000_000
                XCTAssertEqual(discovery.items.count + discovery.channels.count, benchmark.rows)
                XCTAssertFalse(matches.isEmpty)
                print(String(format: "[CatalogMicrobenchmark] case=%@ rows=%d bytes=%d iteration=%d decode_ms=%.3f dedup_ms=%.3f discovery_ms=%.3f search_ms=%.3f discovery_search_ms=%.3f",
                             benchmark.name, benchmark.rows, payload.count, iteration,
                             decodeMilliseconds, dedupMilliseconds, discoveryMilliseconds,
                             searchMilliseconds, projectionMilliseconds))
            }
        }
    }

    /// Repeated provider rows exercise a different deduplication workload from
    /// the ingestion benchmark's unique IDs. Generation and assertions stay
    /// outside the measured intervals; the values are comparison receipts, not
    /// machine-dependent timing pass/fail thresholds or physical UI evidence.
    func testDuplicateHeavyHomeDeduplicationAndDiscoveryMicrobenchmark() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let copiesPerFixture = 4
        for uniqueRows in [250, 1_000] {
            let payload = try benchmarkPayload(rows: uniqueRows, targetBytes: nil, now: now)
            let originals = try AnalyticalDataEngine.decodeMatches(from: payload)
            let repeated = (0..<copiesPerFixture).flatMap { copy in
                originals.map { row in
                    EventReference(id: row.id, title: row.title, category: row.category,
                        date: row.date, poster: row.poster, popular: row.popular, teams: row.teams,
                        sources: [.init(source: "delta", id: "synthetic-\(row.id)-\(copy)")])
                }
            }
            let expectedIDs = originals.map(\.id)
            XCTAssertEqual(repeated.count, uniqueRows * copiesPerFixture)
            for iteration in 1...3 {
                let dedupStart = DispatchTime.now().uptimeNanoseconds
                let catalog = AnalyticalDataEngine.deduplicateMatches(repeated)
                let dedupMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - dedupStart) / 1_000_000
                let discoveryStart = DispatchTime.now().uptimeNanoseconds
                let discovery = HomeSportsDiscovery(events: catalog, now: now)
                let discoveryMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - discoveryStart) / 1_000_000

                XCTAssertEqual(catalog.map(\.id), expectedIDs, "Repeated rows must retain the first accepted position")
                XCTAssertTrue(catalog.allSatisfy { !$0.hasCatalogIdentityConflict })
                XCTAssertTrue(catalog.allSatisfy { $0.sources?.count == copiesPerFixture },
                              "Measurement cannot make distinct provider descriptors disappear")
                XCTAssertEqual(discovery.items.count + discovery.channels.count, uniqueRows)
                print(String(format: "[HomeDuplicateMicrobenchmark] input_rows=%d unique_rows=%d copies=%d iteration=%d dedup_ms=%.3f discovery_ms=%.3f",
                             repeated.count, uniqueRows, copiesPerFixture, iteration,
                             dedupMilliseconds, discoveryMilliseconds))
            }
        }
    }

    /// "Cold" here means a newly constructed value index, not a process cold
    /// start: shared identity helpers may already be warm. Query-independent
    /// classification is counted, making repeated normalization measurable
    /// without depending on a particular Mac's execution speed.
    func testColdSearchPreparationAndWarmQueriesMicrobenchmark() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let queries = ["a", "ar", "ars", "arse", "arsen", "arsena", "arsenal",
                       "Premier League", "CPL", "Yankees", "Alcaraz", "zz-no-match"]
        for rows in [250, 1_000] {
            let payload = try benchmarkPayload(rows: rows, targetBytes: nil, now: now)
            let events = try AnalyticalDataEngine.decodeMatches(from: payload)
            let discovery = HomeSportsDiscovery(events: events, now: now)
            let expectedFootballIDs = events.filter { $0.normalizedCategory == "football" }.map(\.id)
            XCTAssertEqual(discovery.items.count + discovery.channels.count, rows)
            for iteration in 1...3 {
                var classifications = 0
                let preparationStart = DispatchTime.now().uptimeNanoseconds
                let index = HomeSportsSearch.prepare(in: discovery) { row in
                    classifications += 1
                    return row.normalizedCategory == "football" ? "Premier League" : nil
                }
                let preparationMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - preparationStart) / 1_000_000
                let classificationsAfterPreparation = classifications
                let queryStart = DispatchTime.now().uptimeNanoseconds
                let results = queries.map { index.results(query: $0) }
                let queryMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - queryStart) / 1_000_000

                XCTAssertEqual(index.entries.count, rows)
                XCTAssertEqual(classificationsAfterPreparation, rows)
                XCTAssertEqual(classifications, classificationsAfterPreparation,
                               "A sequence of keystrokes must not reclassify the catalog")
                XCTAssertEqual(results[6].map(\.id), expectedFootballIDs)
                XCTAssertEqual(results[7].map(\.id), expectedFootballIDs)
                XCTAssertTrue(results.last?.isEmpty == true)
                print(String(format: "[SearchIndexMicrobenchmark] rows=%d queries=%d iteration=%d classifications=%d cold_index_ms=%.3f warm_queries_total_ms=%.3f result_count=%d",
                             rows, queries.count, iteration, classifications,
                             preparationMilliseconds, queryMilliseconds, results.reduce(0) { $0 + $1.count }))
            }
        }
    }

    func testIndexedCatalogDedupPreservesFirstPositionSourceOrderAndConflictQuarantine() {
        func row(_ id: String, _ title: String = "Arsenal vs Chelsea", at date: Int64 = 1_800_003_600,
                 sources: [NexusASource]? = nil) -> EventReference {
            .init(id: id, title: title, category: "football", date: date,
                  poster: nil, popular: false, teams: nil, sources: sources)
        }
        let first = row("same", sources: [.init(source: "delta", id: "one")])
        let other = row("other", "Liverpool vs Everton")
        let duplicate = row("same", sources: [.init(source: "delta", id: "one"), .init(source: "golf", id: "two")])
        let merged = AnalyticalDataEngine.deduplicateMatches([first, other, duplicate])
        XCTAssertEqual(merged.map(\.id), ["same", "other"])
        XCTAssertEqual(merged[0].sources?.map { "\($0.source)|\($0.id)" }, ["delta|one", "golf|two"])
        XCTAssertNil(merged[1].sources, "Nil source metadata must not become invented descriptors")

        for conflict in [row("same", "Arsenal vs Liverpool"), row("same", at: 1_800_007_200)] {
            let quarantined = AnalyticalDataEngine.deduplicateMatches([first, other, conflict, duplicate])
            XCTAssertEqual(quarantined.map(\.id), ["same", "other"])
            XCTAssertTrue(quarantined[0].hasCatalogIdentityConflict)
            XCTAssertTrue(quarantined[0].sources?.isEmpty == true,
                          "A later duplicate cannot restore streams to a quarantined ID")
        }
    }

    func testIndexedCatalogDedupPreservesCrossProviderFixtureMergeAndRealRematches() {
        func row(_ id: String, title: String = "Arsenal vs Chelsea", at date: Int64 = 1_800_003_600,
                 source: String? = nil) -> EventReference {
            .init(id: id, title: title, category: "football", date: date,
                  poster: nil, popular: false, teams: nil,
                  sources: source.map { [.init(source: "delta", id: $0)] })
        }
        let schedule = row("schedule")
        let provider = row("provider", source: "stream")
        let youth = row("youth-u19", title: "Arsenal U19 vs Chelsea U19", source: "youth")
        let rematch = row("rematch", at: 1_800_010_800, source: "later")
        let result = AnalyticalDataEngine.deduplicateMatches([schedule, youth, provider, rematch])
        XCTAssertEqual(result.map(\.id), ["provider", "youth-u19", "rematch"])
        XCTAssertEqual(result[0].sources?.map(\.id), ["stream"])
        XCTAssertEqual(result[1].sources?.map(\.id), ["youth"])
        XCTAssertEqual(result[2].kickoffDate, rematch.kickoffDate)
    }

    private func benchmarkPayload(rows: Int, targetBytes: Int?, now: Date) throws -> Data {
        let fixtures: [(sport: String, title: String)] = [
            ("football", "Arsenal vs Chelsea"),
            ("cricket", "West Indies vs India"),
            ("basketball", "Lakers vs Warriors"),
            ("baseball", "Yankees vs Red Sox"),
            ("hockey", "Rangers vs Panthers"),
            ("tennis", "Sinner vs Alcaraz")
        ]
        var objects: [[String: Any]] = (0..<rows).map { index in
            let fixture = fixtures[index % fixtures.count]
            return ["id": "benchmark-\(index)", "title": fixture.title, "category": fixture.sport,
                    "date": Int64(now.timeIntervalSince1970) + 3_600 + Int64(index) * 60,
                    "popular": index % 10 == 0, "sources": []]
        }
        if let targetBytes {
            // Unknown publisher metadata contributes bytes without changing
            // fixture identity. This stresses JSON ingestion, not huge labels.
            let overhead = try JSONSerialization.data(withJSONObject: objects).count
            let paddingBytes = max(0, (targetBytes - overhead) / max(1, rows) - 32)
            let padding = String(repeating: "x", count: paddingBytes)
            for index in objects.indices { objects[index]["benchmarkMetadata"] = padding }
        }
        return try JSONSerialization.data(withJSONObject: objects)
    }
}

final class BadgeDecodeSchedulingTests: XCTestCase {
    func testGlobalDecodeBudgetAndQueuedCancellationDoNotRunObsoleteWork() async throws {
        let scheduler = FottyImageDecodeScheduler(maximumConcurrentDecodes: 1)
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "First decode entered")
        let first = Task {
            await scheduler.perform { () -> Int? in
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return 1
            }
        }
        defer { gate.signal(); first.cancel() }
        await fulfillment(of: [started], timeout: 2)
        let neverStarted = expectation(description: "Cancelled queued decode")
        neverStarted.isInverted = true
        let queued = Task {
            await scheduler.perform { () -> Int? in
                neverStarted.fulfill()
                return 2
            }
        }
        for _ in 0..<200 {
            if await scheduler.queuedCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let active = await scheduler.activeCount
        let pending = await scheduler.queuedCount
        XCTAssertEqual(active, 1)
        XCTAssertEqual(pending, 1)
        queued.cancel()
        let cancelledValue = await queued.value
        XCTAssertNil(cancelledValue)
        let remaining = await scheduler.queuedCount
        XCTAssertEqual(remaining, 0)
        gate.signal()
        let firstValue = await first.value
        XCTAssertEqual(firstValue, 1)
        await fulfillment(of: [neverStarted], timeout: 0.05)
        let finalActive = await scheduler.activeCount
        XCTAssertEqual(finalActive, 0)
        let resumedValue = await scheduler.perform { 3 }
        XCTAssertEqual(resumedValue, 3, "Cancellation must not leak a scheduler permit")
    }

    func testAlreadyCancelledDecodeDoesNotExecute() async {
        let scheduler = FottyImageDecodeScheduler(maximumConcurrentDecodes: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await scheduler.perform { 42 }
        }
        let value = await task.value
        XCTAssertNil(value)
        let active = await scheduler.activeCount
        XCTAssertEqual(active, 0)
    }
}
