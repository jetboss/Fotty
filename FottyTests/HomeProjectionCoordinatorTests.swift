import XCTest
@testable import Fotty

@MainActor
final class HomeProjectionCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func selection(_ name: String? = nil) -> SportsPersonalizationPolicy.PreparedSelection {
        SportsPersonalizationPolicy.prepareSelection(teams: name.map {
            [FollowedTeamItem(key: "football|\($0)", teamName: $0, sportCategory: "football")]
        } ?? [], leagues: [])
    }

    private func input(_ events: [EventReference], revision: Int = 1, score: Int64 = 1,
        date: Date? = nil, selected: SportsPersonalizationPolicy.PreparedSelection? = nil,
        terminal: [EventReference] = []) -> HomeProjectionInput {
        let prepared = selected ?? selection()
        return .init(key: .init(contentRevision: revision, scoreRevisionMilliseconds: score,
                clockDate: date ?? now, selectionIdentity: prepared.identity),
            selection: prepared, providerEvents: events, terminalEvents: terminal, officialChampionsLeague: [])
    }

    private func event(_ id: String = "same", title: String = "Chelsea vs Brighton",
        category: String = "football", start: Date? = nil) -> EventReference {
        .init(id: id, title: title, category: category,
            date: Int64((start ?? now.addingTimeInterval(3_600)).timeIntervalSince1970),
            poster: nil, popular: false, teams: nil, sources: [])
    }

    private func scope(_ base: HomeProjectionBase, sport: String? = nil) -> HomeProjectionScope {
        let selectedSport = sport ?? HomeSportsDiscovery.allSports
        let key = HomeSportActivityProjectionKey(selectedSport: selectedSport, selectedFootballLeague: "all",
            selectedCricketFilter: "all", showFollowedOnly: false, onlyShowSelectedInterests: false,
            selectionIdentity: base.selection.identity)
        let items = base.discovery.scopedItems(sport: selectedSport)
        let activities = base.discovery.activities(scopedItems: items, scopedChannels: [])
        return .init(ranking: .init(key: .init(projectionRevision: base.revision, scope: key), home: items, lineup: items),
            homeActivities: activities, lineupActivities: activities)
    }

    @discardableResult
    private func rebuild(_ coordinator: HomeProjectionCoordinator, _ input: HomeProjectionInput,
        status: (EventReference) -> FootballMatch.MatchStatus? = { _ in nil },
        isCurrent: () -> Bool = { true },
        deriveScope: ((HomeProjectionBase) -> HomeProjectionScope)? = nil,
        evaluateFacts: ((HomeSportsDiscovery.Item) -> HomePersonalizationFacts)? = nil,
        checkpoint: () async -> Bool = { true }) async -> Bool {
        await coordinator.rebuild(input: input, status: status, facts: { item, _ in
            evaluateFacts?(item) ?? .init(isFollowed: item.event.title?.contains("Chelsea") == true,
                isMajorLeague: false, isCPL: item.event.isCPLFixture)
        }, footballLeague: { $0.title?.contains("Chelsea") == true ? .premierLeague : .other },
        presentation: { .init(item: $0) }, isCurrent: isCurrent,
        deriveScope: { deriveScope?($0) ?? scope($0) }, checkpoint: checkpoint)
    }

    func testFirstEmptyCatalogPublishesOneCompletePacket() async throws {
        let coordinator = HomeProjectionCoordinator()
        XCTAssertNil(coordinator.packet)
        let published = await rebuild(coordinator, input([]))
        XCTAssertTrue(published)
        let packet = try XCTUnwrap(coordinator.packet)
        XCTAssertEqual(packet.base.revision, 1)
        XCTAssertEqual(packet.base.key, input([]).key)
        XCTAssertTrue(packet.base.discovery.items.isEmpty)
        XCTAssertTrue(packet.base.presentations.isEmpty)
        XCTAssertTrue(packet.base.footballLeagues.isEmpty)
        XCTAssertTrue(packet.base.factsCache.facts.isEmpty)
        XCTAssertTrue(packet.scope.ranking.home.isEmpty)
        XCTAssertEqual(packet.scope.ranking.key.projectionRevision, packet.base.revision)
    }

    func testSameIDCatalogReplacementRebuildsFactsRowsAndPresentations() async throws {
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input([event()]))
        let old = try XCTUnwrap(coordinator.packet)
        await rebuild(coordinator, input([event(title: "Arsenal vs Newcastle")], revision: 2))
        let replacement = try XCTUnwrap(coordinator.packet)
        XCTAssertEqual(replacement.base.revision, old.base.revision + 1)
        XCTAssertEqual(replacement.base.discovery.items.map(\.event.title), ["Arsenal vs Newcastle"])
        XCTAssertEqual(replacement.base.factsCache.facts["same"]?.isFollowed, false)
        XCTAssertEqual(replacement.base.footballLeagues["same"], .other)
        XCTAssertEqual(Set(replacement.base.presentations.keys), ["same"])
        XCTAssertEqual(replacement.scope.ranking.home.map(\.event.title), ["Arsenal vs Newcastle"])
    }

    func testSameKeyRetryCannotBeOverwrittenByOlderCompletion() async throws {
        let coordinator = HomeProjectionCoordinator()
        let gate = CheckpointGate(pauseAt: 6)
        let requested = input([event()])
        let older = Task { await self.rebuild(coordinator, requested, checkpoint: { await gate.checkpoint() }) }
        await gate.waitForPause()
        XCTAssertNil(coordinator.packet, "Prepared maps must remain invisible until the final packet")
        let retry = input([event(title: "Arsenal vs Newcastle")])
        let retryPublished = await rebuild(coordinator, retry)
        XCTAssertTrue(retryPublished)
        gate.release()
        let olderPublished = await older.value
        XCTAssertFalse(olderPublished, "Generation protection is required even when the exact key repeats")
        XCTAssertEqual(coordinator.packet?.base.revision, 1)
        XCTAssertEqual(coordinator.packet?.base.discovery.items.first?.event.title, "Arsenal vs Newcastle")
    }

    func testCancellationPreservesPreviouslyPublishedPacketAndStopsScopeDerivation() async throws {
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input([event()]))
        let accepted = try XCTUnwrap(coordinator.packet)
        let gate = CheckpointGate(pauseAt: 6)
        var derived = false
        let cancelled = Task {
            await self.rebuild(coordinator, self.input([self.event("new")], revision: 2),
                deriveScope: { base in derived = true; return self.scope(base) },
                checkpoint: { await gate.checkpoint() })
        }
        await gate.waitForPause()
        cancelled.cancel()
        gate.release()
        let published = await cancelled.value
        XCTAssertFalse(published)
        XCTAssertFalse(derived)
        XCTAssertEqual(coordinator.packet?.base.key, accepted.base.key)
        XCTAssertEqual(coordinator.packet?.base.revision, accepted.base.revision)
        XCTAssertEqual(coordinator.packet?.base.discovery.items.map(\.id), ["same"])
        XCTAssertEqual(coordinator.packet?.scope.ranking.home.map(\.id), ["same"])
    }

    func testAlreadyStaleOrCancelledEntryCannotRevokeCurrentPendingRequest() async {
        let coordinator = HomeProjectionCoordinator()
        let gate = CheckpointGate(pauseAt: 6)
        let current = Task {
            await self.rebuild(coordinator, self.input([self.event("current")], revision: 2),
                checkpoint: { await gate.checkpoint() })
        }
        await gate.waitForPause()
        let stalePublished = await rebuild(coordinator, input([event("stale")]), isCurrent: { false })
        XCTAssertFalse(stalePublished)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await self.rebuild(coordinator, self.input([self.event("cancelled")], revision: 3))
        }
        let cancelledPublished = await cancelled.value
        XCTAssertFalse(cancelledPublished)
        gate.release()
        let currentPublished = await current.value
        XCTAssertTrue(currentPublished)
        XCTAssertEqual(coordinator.packet?.base.discovery.items.map(\.id), ["current"])
        XCTAssertEqual(coordinator.packet?.base.key.contentRevision, 2)
    }

    func testEveryExactInputChangeRejectsSuspendedPacket() async {
        let requested = input([event()])
        let changes = [
            input([event()], revision: 2).key,
            input([event()], score: 2).key,
            input([event()], date: now.addingTimeInterval(1)).key,
            input([event()], selected: selection("Arsenal")).key
        ]
        for changedKey in changes {
            let coordinator = HomeProjectionCoordinator()
            let gate = CheckpointGate(pauseAt: 6)
            var current = requested.key
            let task = Task {
                await self.rebuild(coordinator, requested, isCurrent: { current == requested.key },
                    checkpoint: { await gate.checkpoint() })
            }
            await gate.waitForPause()
            current = changedKey
            gate.release()
            let published = await task.value
            XCTAssertFalse(published)
            XCTAssertNil(coordinator.packet)
        }
    }

    func testScopeEditDuringPreparationUsesLatestScopeWithoutPartialBasePublication() async throws {
        let coordinator = HomeProjectionCoordinator()
        let events = [event(), event("cricket", title: "India vs West Indies", category: "cricket")]
        await rebuild(coordinator, input(events))
        let gate = CheckpointGate(pauseAt: 6)
        var selectedSport = HomeSportsDiscovery.allSports
        let pending = Task {
            await self.rebuild(coordinator, self.input(events, revision: 2),
                deriveScope: { self.scope($0, sport: selectedSport) }, checkpoint: { await gate.checkpoint() })
        }
        await gate.waitForPause()
        selectedSport = "cricket"
        coordinator.refreshScope { self.scope($0, sport: selectedSport) }
        XCTAssertEqual(coordinator.packet?.base.revision, 1)
        XCTAssertEqual(coordinator.packet?.base.key.contentRevision, 1)
        XCTAssertEqual(Set(coordinator.packet?.base.presentations.keys ?? Dictionary<String, HomeDiscoveryRow.Presentation>().keys), ["same", "cricket"])
        XCTAssertEqual(coordinator.packet?.scope.ranking.home.map(\.id), ["cricket"])
        gate.release()
        let published = await pending.value
        XCTAssertTrue(published)
        let final = try XCTUnwrap(coordinator.packet)
        XCTAssertEqual(final.base.revision, 2)
        XCTAssertEqual(final.base.key.contentRevision, 2)
        XCTAssertEqual(final.scope.ranking.key.projectionRevision, final.base.revision)
        XCTAssertEqual(final.scope.ranking.key.scope.selectedSport, "cricket")
        XCTAssertEqual(final.scope.ranking.home.map(\.id), ["cricket"])
    }

    func testFactsReuseOnClockOnlyButInvalidateCatalogScoreAndSelection() async {
        let coordinator = HomeProjectionCoordinator()
        var evaluations = 0
        let evaluate: (HomeSportsDiscovery.Item) -> HomePersonalizationFacts = { _ in
            evaluations += 1
            return .init(isFollowed: false, isMajorLeague: false, isCPL: false)
        }
        await rebuild(coordinator, input([event()]), evaluateFacts: evaluate)
        await rebuild(coordinator, input([event()], date: now.addingTimeInterval(60)), evaluateFacts: evaluate)
        XCTAssertEqual(evaluations, 1)
        await rebuild(coordinator, input([event()], revision: 2), evaluateFacts: evaluate)
        XCTAssertEqual(evaluations, 2)
        await rebuild(coordinator, input([event()], revision: 2, score: 2), evaluateFacts: evaluate)
        XCTAssertEqual(evaluations, 3)
        await rebuild(coordinator, input([event()], revision: 2, score: 2, selected: selection("Chelsea")), evaluateFacts: evaluate)
        XCTAssertEqual(evaluations, 4)
    }

    func testNewTerminalReceiptSupersedesSuspendedLivePacket() async throws {
        let coordinator = HomeProjectionCoordinator()
        let start = now.addingTimeInterval(-3_600)
        let provider = event(title: "Chelsea vs Brighton", start: start)
        let gate = CheckpointGate(pauseAt: 6)
        let older = Task {
            await self.rebuild(coordinator, self.input([provider]), status: { _ in .inPlay },
                checkpoint: { await gate.checkpoint() })
        }
        await gate.waitForPause()
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:terminal",
            sport: "football", competitionID: "premier-league", competitionName: "Premier League",
            eventKind: .match, title: "Chelsea vs Brighton",
            participants: [.init(id: "chelsea", name: "Chelsea", role: "home"),
                           .init(id: "brighton", name: "Brighton", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .finished, observedAt: now, verified: true)
        let terminal = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false, teams: nil, sources: [],
            sportsFixture: metadata, competitionID: metadata.competitionID)
        await rebuild(coordinator, input([provider], revision: 2, score: 2, terminal: [terminal]), status: { _ in .inPlay })
        gate.release()
        let olderPublished = await older.value
        XCTAssertFalse(olderPublished)
        let packet = try XCTUnwrap(coordinator.packet)
        XCTAssertEqual(packet.base.key.contentRevision, 2)
        XCTAssertTrue(packet.base.discovery.items.isEmpty, "A fresh live score cannot resurrect an accepted terminal fixture")
        XCTAssertTrue(packet.base.presentations.isEmpty)
        XCTAssertTrue(packet.scope.ranking.home.isEmpty)
    }

    func testPreparationRetainsSixteenRowCheckpointBoundary() async throws {
        let coordinator = HomeProjectionCoordinator()
        var checkpoints = 0
        let rows = (0..<33).map { event("row-\($0)", title: "Team \($0) vs Other \($0)") }
        await rebuild(coordinator, input(rows), checkpoint: { checkpoints += 1; return true })
        XCTAssertEqual(checkpoints, 10, "Four stage boundaries, four bounded dedup checkpoints, and two completed sixteen-row presentation batches")
        XCTAssertEqual(coordinator.packet?.base.discovery.items.count, 33)
        XCTAssertEqual(coordinator.packet?.base.presentations.count, 33)
    }

    private func dedupRow(_ id: String, home: String = "Arsenal", away: String = "Leeds United",
        title: String? = nil, category: String = "football", offset: Int64 = 0,
        competition: String? = "premier-league", sources: [NexusASource]? = [],
        conflict: Bool = false, fixture: SportsFixtureMetadata? = nil) -> EventReference {
        .init(id: id, title: title ?? "\(home) vs \(away)", category: category,
            date: Int64(now.timeIntervalSince1970) + offset, poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
            sources: sources, hasCatalogIdentityConflict: conflict, sportsFixture: fixture,
            competitionID: competition)
    }

    private func assertCooperativeDedupEquivalent(_ rows: [EventReference],
        file: StaticString = #filePath, line: UInt = #line) async throws -> [EventReference] {
        let synchronous = AnalyticalDataEngine.deduplicateMatches(rows)
        let result = await AnalyticalDataEngine.deduplicateMatchesCooperatively(rows,
            isCurrent: { true }, checkpoint: { _ in true })
        let cooperative = try XCTUnwrap(result, file: file, line: line)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(cooperative), try encoder.encode(synchronous),
            "Both paths must preserve every identity, optional metadata field, source and order", file: file, line: line)
        return cooperative
    }

    func testCooperativeDedupMatchesSynchronousIdentityConflictsAliasesAndSourceMerges() async throws {
        let first = dedupRow("first", sources: [.init(source: "delta", id: "one")])
        let mirror = dedupRow("first", home: "Arsenal FC", away: "Leeds United FC",
            sources: [.init(source: "hotel", id: "two"), .init(source: "delta", id: "one")])
        let sourceBackedAlias = dedupRow("different-provider", home: "Arsenal FC", away: "Leeds United FC",
            sources: [.init(source: "golf", id: "three")])
        var scenarios: [[EventReference]] = [[], [first], [first, mirror, first],
            [dedupRow("schedule"), sourceBackedAlias], [sourceBackedAlias, dedupRow("schedule")],
            [dedupRow("nil", sources: nil), dedupRow("nil", sources: nil)],
            [dedupRow("empty", sources: nil), dedupRow("empty", sources: [])],
            [first, dedupRow(first.id, away: "Chelsea"), mirror],
            [first, dedupRow(first.id, offset: 1), mirror],
            [first, dedupRow(first.id, category: "basketball"), mirror],
            [dedupRow(first.id, conflict: true), first],
            [first, dedupRow(first.id, conflict: true), first],
            [first, dedupRow("different-competition", competition: "fa-cup")],
            [first, dedupRow("no-competition", competition: nil)],
            [first, dedupRow("later-doubleheader", offset: 3_600)],
            [first, dedupRow("reversed", home: "Leeds United", away: "Arsenal")],
            [dedupRow("channel-one", home: "Home", away: "Away", title: "Willow Cricket", category: "cricket", competition: nil),
             dedupRow("channel-two", home: "Home", away: "Away", title: "Willow Cricket", category: "cricket", competition: nil)]]
        for qualifier in ["Women", "W", "U19", "Under 21", "Reserves", "II", "B", "2"] {
            scenarios.append([first, dedupRow("squad-\(qualifier)", home: "Arsenal \(qualifier)", away: "Leeds United \(qualifier)")])
            scenarios.append([first, dedupRow(first.id, title: "Arsenal vs Leeds United \(qualifier)"), mirror])
        }
        for (sport, home, away) in [("cricket", "West Indies", "India"), ("basketball", "Lakers", "Warriors"),
                                    ("baseball", "Yankees", "Red Sox"), ("hockey", "Rangers", "Panthers"),
                                    ("tennis", "Sinner", "Alcaraz")] {
            scenarios.append([dedupRow("\(sport)-schedule", home: home, away: away, category: sport, competition: nil),
                dedupRow("\(sport)-provider", home: home, away: away, category: sport, competition: nil,
                    sources: [.init(source: "delta", id: sport)])])
        }
        for rows in scenarios {
            _ = try await assertCooperativeDedupEquivalent(rows)
            _ = try await assertCooperativeDedupEquivalent(Array(rows.reversed()))
        }
        let merged = try await assertCooperativeDedupEquivalent([first, mirror, first])
        XCTAssertEqual(merged.map(\.id), [first.id])
        XCTAssertEqual(merged.first?.sources?.map(\.id), ["one", "two"])
        let quarantined = try await assertCooperativeDedupEquivalent([first, dedupRow(first.id, away: "Chelsea"), mirror])
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertTrue(quarantined.first?.hasCatalogIdentityConflict == true)
        XCTAssertTrue(quarantined.first?.sources?.isEmpty == true)
    }

    func testCooperativeDedupRetainsDistinctOfficialIDsAndAcceptedMetadata() async throws {
        func metadata(_ id: String, status: SportsFixtureCatalog.Status) -> SportsFixtureMetadata {
            .init(fixtureID: "sports-fixture:premier-league:\(id)", sport: "football",
                competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                title: "Arsenal vs Leeds United", participants: [.init(id: "arsenal", name: "Arsenal"),
                    .init(id: "leeds", name: "Leeds United")], squad: .init(gender: .men, ageGroup: "senior"),
                status: status, observedAt: now, verified: true)
        }
        let accepted = metadata("one", status: .live), distinct = metadata("two", status: .finished)
        let one = dedupRow("official-one", fixture: accepted), two = dedupRow("official-two", fixture: distinct)
        let separate = try await assertCooperativeDedupEquivalent([one, two])
        XCTAssertEqual(separate.map(\.id), [one.id, two.id])
        XCTAssertEqual(separate.compactMap { $0.sportsFixture?.fixtureID }, [accepted.fixtureID, distinct.fixtureID])
        let provider = dedupRow("provider", sources: [.init(source: "delta", id: "provider")])
        let merged = try await assertCooperativeDedupEquivalent([one, provider])
        XCTAssertEqual(merged.map(\.id), [provider.id])
        XCTAssertEqual(merged.first?.sportsFixture?.fixtureID, accepted.fixtureID)
        XCTAssertEqual(merged.first?.sources?.map(\.id), ["provider"])
    }

    func testHomeAndProjectionRetainTitleOnlySquadsWithoutCombiningSources() async throws {
        let rows = [
            dedupRow("senior", offset: 3_600, sources: [.init(source: "delta", id: "senior-stream")]),
            dedupRow("youth", title: "Arsenal vs Leeds United U19", offset: 3_600,
                sources: [.init(source: "delta", id: "youth-stream")]),
            dedupRow("women", title: "Arsenal vs Leeds United Women", offset: 3_600,
                sources: [.init(source: "delta", id: "women-stream")]),
            dedupRow("reserves", title: "Arsenal vs Leeds United Reserves", offset: 3_600,
                sources: [.init(source: "delta", id: "reserve-stream")])
        ]
        let direct = HomeSportsDiscovery(events: rows, now: now)
        XCTAssertEqual(Set(direct.items.map(\.id)), Set(rows.map(\.id)))
        for row in rows {
            XCTAssertEqual(direct.items.first { $0.id == row.id }?.event.sources?.map(\.id), row.sources?.map(\.id))
        }
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input(rows))
        let projected = try XCTUnwrap(coordinator.packet).base.discovery
        XCTAssertEqual(Set(projected.items.map(\.id)), Set(rows.map(\.id)))
        for row in rows {
            XCTAssertEqual(projected.items.first { $0.id == row.id }?.event.sources?.map(\.id), row.sources?.map(\.id))
        }
    }

    func testHomeAndProjectionRetainDistinctOfficialFixtureIdentities() async throws {
        func official(_ nativeID: String) -> EventReference {
            let id = "sports-fixture:premier-league:\(nativeID)"
            let metadata = SportsFixtureMetadata(fixtureID: id, sport: "football",
                competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                title: "Arsenal vs Leeds United", participants: [.init(id: "arsenal", name: "Arsenal"),
                    .init(id: "leeds", name: "Leeds United")], squad: .init(gender: .men, ageGroup: "senior"),
                status: .scheduled, observedAt: now, verified: true)
            return dedupRow(id, offset: 3_600, sources: [.init(source: "delta", id: nativeID)], fixture: metadata)
        }
        let rows = [official("one"), official("two")]
        let direct = HomeSportsDiscovery(events: rows, now: now)
        XCTAssertEqual(Set(direct.items.map(\.id)), Set(rows.map(\.id)))
        XCTAssertEqual(Set(direct.items.compactMap { $0.event.sportsFixture?.fixtureID }), Set(rows.map(\.id)))
        XCTAssertTrue(direct.items.allSatisfy { $0.event.sources?.count == 1 })
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input(rows))
        let projected = try XCTUnwrap(coordinator.packet).base.discovery
        XCTAssertEqual(Set(projected.items.map(\.id)), Set(rows.map(\.id)))
        XCTAssertEqual(Set(projected.items.compactMap { $0.event.sportsFixture?.fixtureID }), Set(rows.map(\.id)))
        XCTAssertTrue(projected.items.allSatisfy { $0.event.sources?.count == 1 })
    }

    func testHomeAndProjectionStillMergeReviewedProviderAliasesAndEveryUniqueSource() async throws {
        let first = dedupRow("a", offset: 3_600,
            sources: [.init(source: "delta", id: "one"), .init(source: "golf", id: "two")])
        let alias = dedupRow("b", home: "Arsenal FC", away: "Leeds United FC", offset: 3_600,
            sources: [.init(source: "delta", id: "one"), .init(source: "hotel", id: "three")])
        let direct = HomeSportsDiscovery(events: [alias, first], now: now)
        XCTAssertEqual(direct.items.map(\.id), [first.id])
        XCTAssertEqual(Set(direct.items.first?.event.sources?.map(\.id) ?? []), ["one", "two", "three"])
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input([first, alias]))
        let projected = try XCTUnwrap(coordinator.packet).base.discovery
        XCTAssertEqual(projected.items.map(\.id), [first.id])
        XCTAssertEqual(Set(projected.items.first?.event.sources?.map(\.id) ?? []), ["one", "two", "three"])
    }

    func testHomeAndProjectionExcludeConflictingReusedIDWithoutDroppingQuarantine() async throws {
        let first = dedupRow("reused", offset: 3_600, sources: [.init(source: "delta", id: "one")])
        let changed = dedupRow(first.id, away: "Chelsea", offset: 3_600,
            sources: [.init(source: "hotel", id: "two")])
        let unique = HomeSportsDiscovery.uniqueEvents([first, changed])
        XCTAssertEqual(unique.count, 1)
        XCTAssertTrue(unique.first?.hasCatalogIdentityConflict == true)
        XCTAssertTrue(unique.first?.sources?.isEmpty == true)
        XCTAssertTrue(HomeSportsDiscovery(events: [first, changed], now: now).items.isEmpty)
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input([first, changed]))
        let packet = try XCTUnwrap(coordinator.packet)
        XCTAssertTrue(packet.base.discovery.items.isEmpty)
        XCTAssertTrue(packet.base.presentations.isEmpty)
        XCTAssertTrue(packet.scope.ranking.home.isEmpty)
    }

    func testCooperativeDedupCheckpointsBoundBothPassesToThirtyTwoRows() async throws {
        for count in [0, 1, 31, 32, 33, 70] {
            let rows = (0..<count).map { dedupRow("row-\($0)", offset: Int64($0)) }
            var checkpoints: [Int] = []
            let result = await AnalyticalDataEngine.deduplicateMatchesCooperatively(rows,
                isCurrent: { true }, checkpoint: { processed in checkpoints.append(processed); return true })
            XCTAssertEqual(result?.count, count)
            var previous = 0
            for processed in checkpoints {
                XCTAssertGreaterThan(processed, previous)
                XCTAssertLessThanOrEqual(processed - previous, 32)
                previous = processed
            }
            XCTAssertEqual(previous, count * 2)
            if count == 70 { XCTAssertEqual(checkpoints, [32, 64, 70, 102, 134, 140]) }
        }
        let repeated = (0..<70).map { _ in dedupRow("same-id") }
        var checkpoints: [Int] = []
        let merged = await AnalyticalDataEngine.deduplicateMatchesCooperatively(repeated,
            isCurrent: { true }, checkpoint: { checkpoints.append($0); return true })
        XCTAssertEqual(merged?.count, 1)
        XCTAssertEqual(checkpoints, [32, 64, 70, 71], "The second pass visits only accepted ID rows")
    }

    func testCooperativeDedupCancellationOrStaleGenerationRejectsEverySuspendedStage() async {
        let rows = (0..<40).map { dedupRow("row-\($0)", offset: Int64($0)) }
        for pauseAt in 1...4 {
            for cancel in [false, true] {
                let gate = CheckpointGate(pauseAt: pauseAt)
                var current = true
                let task = Task {
                    await AnalyticalDataEngine.deduplicateMatchesCooperatively(rows,
                        isCurrent: { current }, checkpoint: { _ in await gate.checkpoint() })
                }
                await gate.waitForPause()
                if cancel { task.cancel() } else { current = false }
                gate.release()
                let result = await task.value
                XCTAssertNil(result, "No partial result from dedup stage \(pauseAt) may escape")
            }
        }
        for rejectedCheckpoint in 1...4 {
            var calls = 0
            let result = await AnalyticalDataEngine.deduplicateMatchesCooperatively(rows,
                isCurrent: { true }, checkpoint: { _ in calls += 1; return calls != rejectedCheckpoint })
            XCTAssertNil(result)
            XCTAssertEqual(calls, rejectedCheckpoint)
        }
        var staleCheckpointCalls = 0
        let stale = await AnalyticalDataEngine.deduplicateMatchesCooperatively(rows, isCurrent: { false },
            checkpoint: { _ in staleCheckpointCalls += 1; return true })
        XCTAssertNil(stale)
        XCTAssertEqual(staleCheckpointCalls, 0)
    }

    func testCancelledDedupBatchCannotPublishPartialHomeMapsOrRevokeAcceptedPacket() async throws {
        let coordinator = HomeProjectionCoordinator()
        await rebuild(coordinator, input([event()]))
        let accepted = try XCTUnwrap(coordinator.packet)
        for pauseAt in 2...5 {
            let gate = CheckpointGate(pauseAt: pauseAt)
            var factsEvaluated = 0, scopeDerived = false
            let rows = (0..<40).map { event("new-\($0)", title: "Team \($0) vs Other \($0)") }
            let pending = Task {
                await self.rebuild(coordinator, self.input(rows, revision: 2),
                    deriveScope: { base in scopeDerived = true; return self.scope(base) },
                    evaluateFacts: { _ in factsEvaluated += 1; return .init(isFollowed: false, isMajorLeague: false, isCPL: false) },
                    checkpoint: { await gate.checkpoint() })
            }
            await gate.waitForPause()
            XCTAssertEqual(coordinator.packet?.base.key, accepted.base.key)
            XCTAssertEqual(coordinator.packet?.base.presentations.count, 1)
            pending.cancel()
            gate.release()
            let published = await pending.value
            XCTAssertFalse(published)
            XCTAssertEqual(factsEvaluated, 0)
            XCTAssertFalse(scopeDerived)
            XCTAssertEqual(coordinator.packet?.base.revision, accepted.base.revision)
            XCTAssertEqual(coordinator.packet?.base.discovery.items.map(\.id), ["same"])
            XCTAssertEqual(coordinator.packet?.scope.ranking.home.map(\.id), ["same"])
        }
    }

    /// Matches CatalogRuntimeOwnershipTests' synchronous duplicate-heavy
    /// workload: fixed clock, rotating six sports, distinct source per copy.
    /// This reports cooperation cost/work slices, not physical input hitch proof.
    func testCooperativeDuplicateHeavyHomeDeduplicationMicrobenchmark() async throws {
        let fixtures: [(sport: String, title: String)] = [("football", "Arsenal vs Chelsea"),
            ("cricket", "West Indies vs India"), ("basketball", "Lakers vs Warriors"),
            ("baseball", "Yankees vs Red Sox"), ("hockey", "Rangers vs Panthers"), ("tennis", "Sinner vs Alcaraz")]
        let objects: [[String: Any]] = (0..<1_000).map { index in
            let fixture = fixtures[index % fixtures.count]
            return ["id": "benchmark-\(index)", "title": fixture.title, "category": fixture.sport,
                "date": Int64(now.timeIntervalSince1970) + 3_600 + Int64(index) * 60,
                "popular": index % 10 == 0, "sources": []]
        }
        let originals = try AnalyticalDataEngine.decodeMatches(from: JSONSerialization.data(withJSONObject: objects))
        let repeated = (0..<4).flatMap { copy in
            originals.map { row in
                EventReference(id: row.id, title: row.title, category: row.category, date: row.date,
                    poster: row.poster, popular: row.popular, teams: row.teams,
                    sources: [.init(source: "delta", id: "synthetic-\(row.id)-\(copy)")])
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let expected = try encoder.encode(AnalyticalDataEngine.deduplicateMatches(repeated))
        for iteration in 1...3 {
            var checkpointCount = 0
            var maxWorkMilliseconds = 0.0
            let start = DispatchTime.now().uptimeNanoseconds
            var previousCheckpoint = start
            let result = await AnalyticalDataEngine.deduplicateMatchesCooperatively(repeated,
                isCurrent: { true }, checkpoint: { _ in
                    let entered = DispatchTime.now().uptimeNanoseconds
                    maxWorkMilliseconds = max(maxWorkMilliseconds, Double(entered - previousCheckpoint) / 1_000_000)
                    checkpointCount += 1
                    await Task.yield()
                    previousCheckpoint = DispatchTime.now().uptimeNanoseconds
                    return true
                })
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let catalog = try XCTUnwrap(result)
            XCTAssertEqual(try encoder.encode(catalog), expected)
            XCTAssertEqual(catalog.count, 1_000)
            XCTAssertTrue(catalog.allSatisfy { $0.sources?.count == 4 })
            XCTAssertEqual(checkpointCount, 157)
            print(String(format: "[HomeCooperativeDedupMicrobenchmark] input_rows=4000 unique_rows=1000 copies=4 iteration=%d total_ms=%.3f checkpoints=%d max_work_between_checkpoints_ms=%.3f",
                iteration, elapsed, checkpointCount, maxWorkMilliseconds))
        }
    }
}

/// Deterministic suspension: tests release exactly the owned preparation stage,
/// not a timing guess or a simulated production delay.
@MainActor
private final class CheckpointGate {
    private let pauseAt: Int
    private var calls = 0
    private var paused = false
    private var pauseObserver: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Bool, Never>?

    init(pauseAt: Int) { self.pauseAt = pauseAt }

    func checkpoint() async -> Bool {
        calls += 1
        guard calls == pauseAt else { return true }
        paused = true
        pauseObserver?.resume()
        pauseObserver = nil
        return await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitForPause() async {
        guard !paused else { return }
        await withCheckedContinuation { pauseObserver = $0 }
    }

    func release() {
        releaseContinuation?.resume(returning: true)
        releaseContinuation = nil
    }
}
