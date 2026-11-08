import Observation
import XCTest
@testable import Fotty

@MainActor
final class CatalogIncrementalPublicationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_633_600)

    private final class Gate<Value> {
        let entered = XCTestExpectation(description: "lane entered")
        private var continuation: CheckedContinuation<Value, Never>?
        private var releasedValue: Value?
        private var wasReleased = false
        func wait() async -> Value {
            if wasReleased { entered.fulfill(); return releasedValue! }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        func release(_ value: Value) {
            guard !wasReleased else { return }
            wasReleased = true
            releasedValue = .some(value)
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private func provider() -> LiveCatalogSnapshot {
        .init(events: [.init(id: "fast", title: "Arsenal vs Chelsea", category: "football",
              date: Int64(now.timeIntervalSince1970), poster: nil, popular: true, teams: nil,
              sources: [.init(source: "delta", id: "fast")])], checkedAt: now,
              source: "controlled", respondingFeeds: 1, attemptedFeeds: 1, isPartial: false)
    }

    private func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func cplSnapshot(receipt: Date? = nil, hours: Double = 1) -> CPLSchedule.Snapshot {
        .init(revision: "controlled-cpl", checkedAt: receipt ?? now,
              fixtures: [.init(1, stamp(now.addingTimeInterval(hours * 3600)), .trinbago, .guyana)],
              sourceStatus: .verified)
    }

    private func cricketSnapshot(receipt: Date? = nil,
                                 status: CricketFixtureCatalog.Status = .scheduled) -> CricketFixtureCatalog.Snapshot {
        let checked = stamp(receipt ?? now)
        let fixture = CricketFixtureCatalog.Fixture(id: "controlled-cricket", start: stamp(now.addingTimeInterval(3600)),
            format: .odi, status: status, competitionId: "west-indies", competitionName: "West Indies tour of India",
            home: .init(id: "india-men", name: "India"), away: .init(id: "wi-men", name: "West Indies"),
            source: .init(name: "Official fixtures", url: "https://www.icc-cricket.com/fixtures-results", observedAt: checked))
        return .init(schemaVersion: 1, complete: true, checkedAt: checked, revision: "controlled-cricket",
            sourceStatus: .verified, fixtures: [fixture], coverage: [.init(competitionId: "west-indies",
                competitionName: "West Indies tour of India", status: .covered, checkedAt: checked,
                fixtureCount: 1, expectedFixtureCount: 1, nextStart: nil)])
    }

    private func sportsSnapshot(receipt: Date? = nil,
                                status: SportsFixtureCatalog.Status = .scheduled,
                                unavailable: Bool = false, hours: Double = 1) -> SportsFixtureCatalog.Snapshot {
        let checked = stamp(receipt ?? now)
        let fixtures: [SportsFixtureCatalog.Fixture] = unavailable ? [] : [.init(id: "sports-fixture:nba:controlled",
            sport: "basketball", start: stamp(now.addingTimeInterval(hours * 3600)), status: status, eventKind: .match,
            title: "Boston Celtics vs New York Knicks", competitionId: "nba", competitionName: "NBA",
            participants: [.init(id: "boston", name: "Boston Celtics"), .init(id: "new-york", name: "New York Knicks")],
            squad: .init(gender: .men, ageGroup: "senior"),
            source: .init(name: "Official schedule", url: "https://www.espn.com/nba/schedule", observedAt: checked))]
        return .init(schemaVersion: 1, complete: true, checkedAt: checked, revision: "controlled-sports",
            sourceStatus: unavailable ? .partial : .verified, fixtures: fixtures,
            coverage: [.init(sport: "basketball", competitionId: "nba", competitionName: "NBA",
                status: unavailable ? .unavailable : .covered, checkedAt: checked,
                fixtureCount: fixtures.count, pendingFixtureCount: 0, nextStart: nil)])
    }

    func testAlreadyCompletedFixtureLanesJoinFirstProviderPublicationOnce() async {
        let delayedProvider = Gate<LiveCatalogSnapshot>()
        let fixtureFinished = XCTestExpectation(description: "all fixture lanes completed")
        fixtureFinished.expectedFulfillmentCount = 3
        let cpl = cplSnapshot(), cricket = cricketSnapshot(), sports = sportsSnapshot()
        let model = MatchListViewModel(fetchSnapshot: { await delayedProvider.wait() },
            refreshSchedule: { fixtureFinished.fulfill(); return cpl },
            refreshCricket: { fixtureFinished.fulfill(); return cricket },
            refreshSports: { fixtureFinished.fulfill(); return sports }, now: { self.now })
        let owner = Task { await model.refresh() }
        await fulfillment(of: [delayedProvider.entered, fixtureFinished], timeout: 2)
        XCTAssertTrue(model.matches.isEmpty, "Fixture evidence awaits a non-cancelled provider outcome")
        delayedProvider.release(provider())
        await owner.value
        XCTAssertEqual(model.contentRevision, 1, "Already completed receipts require one merged publication, not four")
        XCTAssertEqual(Set(model.matches.map(\.id)), ["fast", cpl.fixtures[0].id,
            "cricket-fixture:controlled-cricket", sports.fixtures[0].id])
        XCTAssertEqual(model.cplScheduleCheckedAt, cpl.checkedAt)
        XCTAssertEqual(model.cricketFixtureSnapshot, cricket)
        XCTAssertEqual(model.sportsFixtureSnapshot, sports)
        XCTAssertTrue(model.matches.filter { $0.id != "fast" }.allSatisfy { $0.sources?.isEmpty != false })
    }

    func testUnchangedFixtureReceiptsDoNotRepublishAcceptedProvider() async {
        var cplGate = Gate<CPLSchedule.Snapshot?>()
        var cricketGate = Gate<CricketFixtureCatalog.Snapshot?>()
        var sportsGate = Gate<SportsFixtureCatalog.Snapshot?>()
        let cpl = cplSnapshot(), cricket = cricketSnapshot(), sports = sportsSnapshot()
        cplGate.release(cpl); cricketGate.release(cricket); sportsGate.release(sports)
        let model = MatchListViewModel(fetchSnapshot: { self.provider() },
            refreshSchedule: { await cplGate.wait() }, refreshCricket: { await cricketGate.wait() },
            refreshSports: { await sportsGate.wait() }, now: { self.now })
        await model.refresh()
        let before = model.contentRevision
        cplGate = Gate(); cricketGate = Gate(); sportsGate = Gate()
        let published = XCTestExpectation(description: "fresh provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [published, cplGate.entered, cricketGate.entered, sportsGate.entered], timeout: 2)
        XCTAssertEqual(model.contentRevision, before + 1)
        cplGate.release(cpl); cricketGate.release(cricket); sportsGate.release(sports)
        await owner.value
        XCTAssertEqual(model.contentRevision, before + 1, "Receipt replay must not repeat merge, cache write and UI projection")
        XCTAssertEqual(model.cricketFixtureSnapshot, cricket)
        XCTAssertEqual(model.sportsFixtureSnapshot, sports)
    }

    func testRejectedFixtureReceiptsDoNotRepublishAcceptedProvider() async {
        var cplGate = Gate<CPLSchedule.Snapshot?>()
        var cricketGate = Gate<CricketFixtureCatalog.Snapshot?>()
        var sportsGate = Gate<SportsFixtureCatalog.Snapshot?>()
        let cpl = cplSnapshot(), cricket = cricketSnapshot(), sports = sportsSnapshot()
        cplGate.release(cpl); cricketGate.release(cricket); sportsGate.release(sports)
        let model = MatchListViewModel(fetchSnapshot: { self.provider() },
            refreshSchedule: { await cplGate.wait() }, refreshCricket: { await cricketGate.wait() },
            refreshSports: { await sportsGate.wait() }, now: { self.now })
        await model.refresh()
        let before = model.contentRevision
        cplGate = Gate(); cricketGate = Gate(); sportsGate = Gate()
        let published = XCTestExpectation(description: "fresh provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [published, cplGate.entered, cricketGate.entered, sportsGate.entered], timeout: 2)
        let older = now.addingTimeInterval(-60)
        cplGate.release(cplSnapshot(receipt: older, hours: 2))
        cricketGate.release(cricketSnapshot(receipt: older, status: .live))
        // An explicitly unavailable envelope cannot advance the accepted sports receipt.
        sportsGate.release(.init(schemaVersion: sports.schemaVersion, complete: sports.complete,
            checkedAt: stamp(older), revision: "rejected", sourceStatus: .unavailable,
            fixtures: sports.fixtures, coverage: sports.coverage))
        await owner.value
        XCTAssertEqual(model.contentRevision, before + 1)
        XCTAssertEqual(model.cplScheduleCheckedAt, cpl.checkedAt)
        XCTAssertEqual(model.cricketFixtureSnapshot, cricket)
        XCTAssertEqual(model.sportsFixtureSnapshot, sports)
    }

    func testNewerReceiptWithSameCPLFactsStillPublishes() async {
        var gate = Gate<CPLSchedule.Snapshot?>()
        gate.release(cplSnapshot())
        let model = MatchListViewModel(fetchSnapshot: { self.provider() },
            refreshSchedule: { await gate.wait() }, now: { self.now })
        await model.refresh()
        let before = model.contentRevision
        gate = Gate()
        let published = XCTestExpectation(description: "fresh provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [published, gate.entered], timeout: 2)
        let next = now.addingTimeInterval(60)
        gate.release(cplSnapshot(receipt: next))
        await owner.value
        XCTAssertEqual(model.contentRevision, before + 2)
        XCTAssertEqual(model.cplScheduleCheckedAt, next)
        XCTAssertEqual(model.matches.first { $0.isCPLFixture }?.kickoffDate, now.addingTimeInterval(3600))
    }

    func testChangedSameIDFixtureFactsPublishEvenWithSameRevision() async {
        var cplGate = Gate<CPLSchedule.Snapshot?>()
        var cricketGate = Gate<CricketFixtureCatalog.Snapshot?>()
        var sportsGate = Gate<SportsFixtureCatalog.Snapshot?>()
        cplGate.release(cplSnapshot()); cricketGate.release(cricketSnapshot()); sportsGate.release(sportsSnapshot())
        let model = MatchListViewModel(fetchSnapshot: { self.provider() },
            refreshSchedule: { await cplGate.wait() }, refreshCricket: { await cricketGate.wait() },
            refreshSports: { await sportsGate.wait() }, now: { self.now })
        await model.refresh()
        let before = model.contentRevision
        cplGate = Gate(); cricketGate = Gate(); sportsGate = Gate()
        let published = XCTestExpectation(description: "fresh provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [published, cplGate.entered, cricketGate.entered, sportsGate.entered], timeout: 2)
        let next = now.addingTimeInterval(60)
        cplGate.release(cplSnapshot(receipt: next, hours: 2))
        cricketGate.release(cricketSnapshot(receipt: next, status: .live))
        sportsGate.release(sportsSnapshot(receipt: next, status: .live))
        await owner.value
        XCTAssertEqual(model.contentRevision, before + 4, "Provider and each independently changed lane remain publishable")
        XCTAssertEqual(model.matches.first { $0.isCPLFixture }?.kickoffDate, now.addingTimeInterval(7200))
        XCTAssertEqual(model.matches.first { $0.cricketFixture != nil }?.cricketFixture?.status, .live)
        XCTAssertEqual(model.matches.first { $0.sportsFixture != nil }?.sportsFixture?.status, .live)
    }

    func testChangedCoverageDemotesFactsWithoutRenewingIndependentReceipt() async {
        var gate = Gate<SportsFixtureCatalog.Snapshot?>()
        let initial = sportsSnapshot()
        gate.release(initial)
        let model = MatchListViewModel(fetchSnapshot: { self.provider() },
            refreshSports: { await gate.wait() }, now: { self.now })
        await model.refresh()
        let before = model.contentRevision
        gate = Gate()
        let published = XCTestExpectation(description: "fresh provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [published, gate.entered], timeout: 2)
        gate.release(sportsSnapshot(receipt: now.addingTimeInterval(60), unavailable: true))
        await owner.value
        XCTAssertEqual(model.contentRevision, before + 2)
        XCTAssertEqual(model.sportsFixtureSnapshot?.coverage.first?.status, .unavailable)
        XCTAssertEqual(model.sportsFixtureSnapshot?.coverage.first?.checkedAt, initial.coverage.first?.checkedAt)
        XCTAssertEqual(model.sportsFixtureSnapshot?.fixtures.first?.source.observedAt, initial.fixtures.first?.source.observedAt)
        XCTAssertFalse(model.matches.first { $0.sportsFixture != nil }?.sportsFixture?.verified ?? true)
    }

    func testProviderPublishesBeforeSlowFixtureLaneFinishes() async {
        let slow = Gate<CPLSchedule.Snapshot?>()
        let model = MatchListViewModel(fetchSnapshot: { self.provider() }, refreshSchedule: { await slow.wait() }, now: { self.now })
        let published = XCTestExpectation(description: "provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [slow.entered, published], timeout: 2)
        XCTAssertEqual(model.matches.map(\.id), ["fast"])
        XCTAssertEqual(model.lastCatalogCheck, now)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.isRefreshing, "Refresh ownership remains coalesced while fixtures finish")
        slow.release(nil)
        await owner.value
        XCTAssertFalse(model.isRefreshing)
    }

    func testCancellationCannotAcceptLateFixtureReceipt() async {
        let slow = Gate<CPLSchedule.Snapshot?>()
        let model = MatchListViewModel(fetchSnapshot: { self.provider() }, refreshSchedule: { await slow.wait() }, now: { self.now })
        let published = XCTestExpectation(description: "provider published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [slow.entered, published], timeout: 2)
        owner.cancel()
        slow.release(.init(revision: "late", checkedAt: now, fixtures: CPLSchedule.fixtures, sourceStatus: .verified))
        await owner.value
        XCTAssertEqual(model.matches.map(\.id), ["fast"])
        XCTAssertNil(model.cplScheduleCheckedAt)
        XCTAssertFalse(model.isRefreshing)
    }

    func testIndependentFixturePublishesAfterProviderFailureWithoutWaitingForOtherLanes() async {
        let slow = Gate<SportsFixtureCatalog.Snapshot?>()
        let fixture = CPLSchedule.Fixture(1, ISO8601DateFormatter().string(from: now.addingTimeInterval(3600)), .trinbago, .guyana)
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.notConnectedToInternet) },
            refreshSchedule: { .init(revision: "independent", checkedAt: self.now, fixtures: [fixture], sourceStatus: .verified) },
            refreshSports: { await slow.wait() }, now: { self.now })
        let published = XCTestExpectation(description: "independent fixture published")
        withObservationTracking { _ = model.matches } onChange: { published.fulfill() }
        let owner = Task { await model.refresh() }
        await fulfillment(of: [slow.entered, published], timeout: 2)
        XCTAssertEqual(model.matches.map(\.id), [fixture.id])
        XCTAssertTrue(model.matches.allSatisfy { $0.sources?.isEmpty != false })
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.isRefreshing)
        XCTAssertTrue(model.refreshFailed)
        XCTAssertNil(model.lastCatalogCheck)
        slow.release(nil)
        await owner.value
    }

    /// Offline outage drill across the real VM/fixture/action/index policies.
    /// A bound candidate is metadata evidence here, never decoded playback.
    func testPrimaryOutageRetainsOfficialPremierLeagueDiscoveryThroughFoundAndExpiredCandidates() async throws {
        var clock = now
        let checked = stamp(now)
        let fixture = SportsFixtureCatalog.Fixture(id: "sports-fixture:premier-league:outage-drill",
            sport: "football", start: stamp(now.addingTimeInterval(-600)), status: .live, eventKind: .match,
            title: "Arsenal FC vs Chelsea FC", competitionId: "premier-league", competitionName: "Premier League",
            participants: [.init(id: "football-data:57", name: "Arsenal FC", role: "home"),
                           .init(id: "football-data:61", name: "Chelsea FC", role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"),
            source: .init(name: "football-data.org", url: "https://www.football-data.org/",
                          observedAt: checked, verification: .verified))
        let supplied = SportsFixtureCatalog.Snapshot(schemaVersion: 1, complete: true,
            checkedAt: checked, revision: "offline-outage-drill", sourceStatus: .verified, fixtures: [fixture],
            coverage: [.init(sport: "football", competitionId: "premier-league", competitionName: "Premier League",
                status: .covered, checkedAt: checked, fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)])
        let accepted = try SportsFixtureCatalog.validatedSnapshot(from: JSONEncoder().encode(supplied), now: now)
        var primaryFetches = 0, fixtureFetches = 0
        let model = MatchListViewModel(fetchSnapshot: {
            primaryFetches += 1
            throw URLError(.badServerResponse)
        }, refreshSports: {
            fixtureFetches += 1
            return fixtureFetches == 1 ? accepted : nil
        }, now: { clock })
        await model.refresh()
        let event = try XCTUnwrap(model.playbackCatalog.first { $0.id == fixture.id })
        XCTAssertEqual(model.matches.map(\.id), [fixture.id])
        XCTAssertEqual(event.sportsFixture?.status, .live)
        XCTAssertTrue(event.sportsFixture?.verified == true)
        XCTAssertTrue(event.sources?.isEmpty != false)
        XCTAssertTrue(model.refreshFailed)
        XCTAssertNil(model.lastCatalogCheck)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error, "The primary outage must not hide an accepted independent fixture behind an empty error screen")

        let index = FixtureStreamDiscoveryIndex()
        let enabled: Set<String> = ["plaviosports", "communitysports"]
        index.updateEnabledProviders(enabled, revision: 1)
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: event, in: model.playbackCatalog,
            enabledProviderCodes: enabled, at: clock))
        XCTAssertEqual(FixtureSourceLookupPresentation.state(for: event, at: clock, discoveryIndex: index)?.title,
                       "Check streams", "Enabled adapters offer a fresh check, never a claimed compatible broadcast")
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: model.playbackCatalog,
            at: clock, discoveryIndex: index))

        let request = StreamPlaybackRequest(event: event)
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
            providerEventID: "nuvio_sport_outage_drill", streamID: "nuvio_sport_outage_drill", manifestRevision: "1",
            verifiedAt: clock, expiresAt: clock.addingTimeInterval(300), at: clock))
        let candidate = StreamSession(matchID: event.id, playableURL: URL(string: "https://media.example/outage-drill.m3u8")!,
            streamType: .hls, providerName: "CS1", expiryTime: clock.addingTimeInterval(300), createdAt: clock,
            eventBinding: binding)
        let ticket = try XCTUnwrap(index.begin(for: request, providerCode: "communitysports", preflight: false, at: clock))
        index.complete(ticket, sessions: [candidate], at: clock)
        XCTAssertEqual(index.cachedSessions(for: request, providerCode: "communitysports", at: clock)?.map(\.id), [candidate.id])
        XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: event, in: model.playbackCatalog,
            at: clock, discoveryIndex: index)?.event.id, fixture.id)
        XCTAssertEqual(MatchStartPolicy(event: event, now: clock, discoveryIndex: index).title, "Watch")

        clock = now.addingTimeInterval(61)
        XCTAssertGreaterThan(binding.expiresAt, clock, "The shorter discovery cache must expire even while the binding remains current")
        XCTAssertGreaterThan(try XCTUnwrap(candidate.expiryTime), clock)
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: clock))
        XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: event, in: model.playbackCatalog,
            at: clock, discoveryIndex: index)?.evidence, .freshLookupOpportunity,
            "A new exact lookup stays available while the expired descriptor cannot be replayed")
        let recheck = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: event, at: clock, discoveryIndex: index))
        XCTAssertEqual(recheck.title, "Watch")
        XCTAssertTrue(recheck.previouslyFound)
        XCTAssertEqual(recheck.currentCandidateCount, 0)

        // Neither a repeated failed primary fetch nor a temporarily absent
        // official response authorizes clearing the already accepted snapshot.
        await model.refresh()
        let retained = try XCTUnwrap(model.playbackCatalog.first { $0.id == fixture.id })
        XCTAssertEqual(primaryFetches, 2)
        XCTAssertEqual(fixtureFetches, 2)
        XCTAssertEqual(model.sportsFixtureSnapshot, accepted)
        XCTAssertEqual(retained.sportsFixture, event.sportsFixture)
        XCTAssertTrue(model.identityConflicts.isEmpty)
        XCTAssertTrue(retained.sources?.isEmpty != false)
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: retained, in: model.playbackCatalog,
            enabledProviderCodes: enabled, at: clock))
        XCTAssertEqual(FixtureSourceLookupPresentation.state(for: retained, at: clock, discoveryIndex: index), recheck)
        let details = CatalogEventDetailsPresentation.broadcast(for: retained, now: clock,
            enabledProviderCodes: enabled, discoveryIndex: index)
        XCTAssertEqual(details.title, recheck.detailsTitle)
        XCTAssertTrue(details.message.contains("Choose Watch"))
        XCTAssertFalse(details.message.contains("Check streams"))
        XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: retained, in: model.playbackCatalog,
            at: clock, discoveryIndex: index)?.evidence, .freshLookupOpportunity)
        XCTAssertNil(index.cachedSessions(for: request, providerCode: "communitysports", at: clock))
    }

    func testProviderCancellationDoesNotAuthorizeAlreadyCompletedFixtures() async {
        let delayedProvider = Gate<LiveCatalogSnapshot>()
        let fixtureFinished = XCTestExpectation(description: "fixture completed")
        let model = MatchListViewModel(fetchSnapshot: {
            _ = await delayedProvider.wait()
            throw CancellationError()
        }, refreshSchedule: {
            fixtureFinished.fulfill()
            return .init(revision: "queued", checkedAt: self.now, fixtures: CPLSchedule.fixtures, sourceStatus: .verified)
        }, now: { self.now })
        let owner = Task { await model.refresh() }
        await fulfillment(of: [delayedProvider.entered, fixtureFinished], timeout: 2)
        delayedProvider.release(provider())
        await owner.value
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertNil(model.cplScheduleCheckedAt)
        XCTAssertFalse(model.refreshFailed)
    }
}

// Full fixture owner + real shared collector/index, with bounded fake source
// transports. Catalog evidence must never become a StreamSession or LIVE fact.
@MainActor
extension CatalogIncrementalPublicationTests {
    private final class SourceCatalogCallRecorder { var values: [String] = [] }
    private final class AdvancingCatalogClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        func next() -> Date {
            lock.lock(); defer { lock.unlock() }
            value = value.addingTimeInterval(1)
            return value
        }
    }

    func testSharedCatalogStartsQueuedSourcesUsingTheirActualAdvancingClock() async {
        let initial = now, sports = sportsSnapshot(), clock = AdvancingCatalogClock(now)
        let definitions = CuratedStreamSourceCatalog.all.filter { $0.provider != .reviewedTV }
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.cannotLoadFromNetwork) },
            refreshSports: { sports }, now: { initial })
        await model.refresh()
        let requests = model.sourceCatalogRequests(at: initial)
        let index = FixtureCatalogAvailabilityIndex(), calls = SourceCatalogCallRecorder()
        index.updateEnabledProviders(Set(definitions.map(\.providerCode)), revision: 1)
        let lanes = definitions.map { definition in
            FixtureSourceCatalogCollector.Lane(providerCode: definition.providerCode) { requests, startedAt in
                XCTAssertGreaterThan(startedAt, initial)
                await MainActor.run { calls.values.append(definition.providerCode) }
                return requests.map { .init(matchID: $0.matchID, outcome: .listed,
                    providerEventID: definition.providerCode + "_" + $0.matchID) }
            }
        }
        await FixtureSourceCatalogCollector.refresh(requests: requests, lanes: lanes, index: index,
            at: initial, clock: { clock.next() })
        XCTAssertEqual(Set(calls.values), Set(definitions.map(\.providerCode)))
        XCTAssertEqual(index.summary(for: requests[0], at: clock.next())?.listedProviderCount, 7)
    }

    func testSharedSourceCatalogKeepsOfficialRowsAndEveryEnabledSiblingDuringPrimaryFailure() async {
        let clock = now
        let definitions = CuratedStreamSourceCatalog.all.filter { $0.provider != .reviewedTV }
        let sports = sportsSnapshot(hours: -1.0 / 60)
        let cricket = cricketSnapshot()
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.cannotLoadFromNetwork) },
            refreshCricket: { cricket }, refreshSports: { sports }, now: { clock })
        await model.refresh()
        let requests = model.sourceCatalogRequests(at: clock)
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(model.refreshFailed)
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(Set(definitions.map(\.providerCode)), revision: 1)
        let calls = SourceCatalogCallRecorder()
        let lanes = definitions.map { definition in
            FixtureSourceCatalogCollector.Lane(providerCode: definition.providerCode) { requests, _ in
                await MainActor.run { calls.values.append(definition.providerCode) }
                if definition.providerCode == "streamex" { throw URLError(.cannotLoadFromNetwork) }
                return requests.map { .init(matchID: $0.matchID, outcome: .listed,
                    providerEventID: definition.providerCode + "_" + $0.matchID) }
            }
        }
        await FixtureSourceCatalogCollector.refresh(requests: requests, lanes: lanes, index: index, at: clock, clock: { clock })
        XCTAssertEqual(Set(calls.values), Set(definitions.map(\.providerCode)))
        XCTAssertEqual(calls.values.count, 7)
        let event = requests.first { $0.category == "basketball" }!.preferredEvent!
        let summary = index.summary(for: StreamPlaybackRequest(event: event), at: clock)
        XCTAssertEqual(summary?.listedProviderCount, 6)
        XCTAssertEqual(summary?.providers.first { $0.providerCode == "streamex" }?.outcome, .failed(.manifestUnreachable))
        XCTAssertNil(model.catalogNotice(at: clock, availabilityIndex: index),
            "One failed primary cannot produce a whole-catalog warning while enabled sibling catalogs respond")
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: model.playbackAdmissionCatalog,
            at: clock, discoveryIndex: FixtureStreamDiscoveryIndex()))
        XCTAssertNotNil(OptionalSourceLookupPolicy.event(for: event, in: model.playbackAdmissionCatalog,
            enabledProviderCodes: ["communitysports"], at: clock, catalogIndex: index))
        XCTAssertEqual(event.sportsFixture?.status, .scheduled, "Catalog matching cannot promote scheduled to LIVE")
        let details = CatalogEventDetailsPresentation.broadcast(for: event, now: clock,
            enabledProviderCodes: ["communitysports"], discoveryIndex: FixtureStreamDiscoveryIndex(), catalogIndex: index)
        XCTAssertEqual(details.title, "Broadcast listed")
        XCTAssertTrue(details.message.contains("Choose Watch to find and open"),
                      "A fresh exact listing permits a normal Watch attempt without claiming decoded playback")
    }

    func testSharedCatalogCancellationDoesNotSpendBudgetForNeverStartedSources() async {
        let clock = now
        let sports = sportsSnapshot()
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.cannotLoadFromNetwork) },
            refreshSports: { sports }, now: { clock })
        await model.refresh()
        let requests = model.sourceCatalogRequests(at: clock)
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports", "plaviosports", "flixstreams"], revision: 1)
        let first = Gate<[FixtureSourceCatalogMatch]>(), second = Gate<[FixtureSourceCatalogMatch]>()
        let lanes = [
            FixtureSourceCatalogCollector.Lane(providerCode: "communitysports") { _, _ in await first.wait() },
            FixtureSourceCatalogCollector.Lane(providerCode: "plaviosports") { _, _ in await second.wait() },
            FixtureSourceCatalogCollector.Lane(providerCode: "flixstreams") { _, _ in XCTFail("Queued provider must not start after cancellation"); return [] }
        ]
        let task = Task { await FixtureSourceCatalogCollector.refresh(requests: requests, lanes: lanes,
            index: index, at: clock, clock: { clock }) }
        await fulfillment(of: [first.entered, second.entered], timeout: 2)
        task.cancel(); first.release([]); second.release([])
        await task.value
        XCTAssertFalse(index.summary(for: requests[0], at: clock)?.providers.contains { $0.outcome == .checking } ?? false,
            "Cancelled started sources must not remain checking")
        let unused = index.begin(providerCode: "flixstreams", at: clock)
        XCTAssertNotNil(unused, "Never-started source must retain its automatic budget")
        if let unused { index.abandon(unused) }
    }

    func testSharedCatalogFutureListingUsesOfficialScheduleWithoutEnablingWatch() async {
        let clock = now
        let sports = sportsSnapshot(hours: 7 * 24)
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.cannotLoadFromNetwork) },
            refreshSports: { sports }, now: { clock })
        await model.refresh()
        let requests = model.sourceCatalogRequests(at: clock)
        XCTAssertEqual(requests.count, 1, "The shared catalog includes next-week planning beyond Home's compact window")
        let request = requests[0], index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        await FixtureSourceCatalogCollector.refresh(requests: requests,
            lanes: [.init(providerCode: "communitysports") { requests, _ in
                requests.map { .init(matchID: $0.matchID, outcome: .listed, providerEventID: "future_fixture") }
            }], index: index, at: clock, clock: { clock })
        let event = request.preferredEvent!
        XCTAssertEqual(index.summary(for: request, at: clock)?.listedProviderCount, 1)
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: [event], at: clock,
            discoveryIndex: FixtureStreamDiscoveryIndex()))
        XCTAssertNil(OptionalSourceLookupPolicy.event(for: event, in: [event],
            enabledProviderCodes: ["communitysports"], at: clock, catalogIndex: index))
        XCTAssertEqual(CatalogEventDetailsPresentation.broadcast(for: event, now: clock,
            enabledProviderCodes: ["communitysports"], discoveryIndex: FixtureStreamDiscoveryIndex(), catalogIndex: index).title,
            "Sources listed")
        XCTAssertEqual(CatalogEventDetailsPresentation.broadcast(for: event, now: clock.addingTimeInterval(121),
            enabledProviderCodes: ["communitysports"], discoveryIndex: FixtureStreamDiscoveryIndex(), catalogIndex: index).title,
            "Source listings need rechecking", "Expiry must not turn an earlier listing into a false absence")
    }
}

@MainActor
extension CatalogIncrementalPublicationTests {
    func testCloudListingReplacesDuplicateLocalFetchAndSuppressesPrimaryNoticeOnlyUntilSourceExpiry() async throws {
        let clock = now, event = exactListingFixture(), request = StreamPlaybackRequest(event: event)
        let snapshot = cloudCatalogSnapshot(for: request, expiry: clock.addingTimeInterval(30))
        let lane = try XCTUnwrap(FixtureSourceCatalogCollector.lanes(primaryMatches: [],
            primaryFailure: .manifestUnreachable, registrySnapshot: snapshot, requests: [request], at: clock)
            .first { $0.providerCode == "communitysports" })
        XCTAssertEqual(lane.origin, .cloud, "The existing ticket must import cloud facts without fetching its local adapter")
        let imported = try await lane.load([request], clock)
        XCTAssertEqual(imported.first?.outcome, .listed)
        XCTAssertEqual(imported.first?.evidenceObservedAt, clock)
        XCTAssertEqual(imported.first?.evidenceValidUntil, clock.addingTimeInterval(30))
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        await FixtureSourceCatalogCollector.refresh(requests: [request], lanes: [lane], index: index,
            at: clock, clock: { clock })
        let model = MatchListViewModel(fetchSnapshot: { throw URLError(.cannotLoadFromNetwork) },
            refreshSchedule: { nil }, refreshCricket: { nil }, refreshSports: { nil }, now: { clock })
        await model.refresh()
        XCTAssertTrue(model.refreshFailed, "A backup does not rewrite the failed primary receipt")
        XCTAssertNil(model.catalogNotice(at: clock, displaying: [event], availabilityIndex: index))
        XCTAssertEqual(index.summary(for: request, at: clock)?.listedProviderCount, 1)
        XCTAssertNotNil(model.catalogNotice(at: clock.addingTimeInterval(30), displaying: [event], availabilityIndex: index))
        XCTAssertEqual(index.summary(for: request, at: clock.addingTimeInterval(30))?.listedProviderCount, 0)
        let later = clock.addingTimeInterval(FixtureCatalogAvailabilityIndex.minimumRefreshInterval + 1)
        let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: later))
        index.complete(ticket, matches: imported, at: later)
        XCTAssertFalse(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: later),
            "Reimporting the same cached rows cannot renew their original lease")
    }

    func testCloudCompleteEmptyCatalogProvesOnlyItsCurrentOfficialScope() async throws {
        let clock = now, request = StreamPlaybackRequest(event: exactListingFixture())
        let snapshot = cloudCatalogSnapshot(for: request, status: .empty, includesBroadcast: false)
        let lane = try XCTUnwrap(FixtureSourceCatalogCollector.lanes(primaryMatches: [], primaryFailure: nil,
            registrySnapshot: snapshot, requests: [request], at: clock).first { $0.providerCode == "communitysports" })
        XCTAssertEqual(lane.origin, .cloud)
        let emptyRows = try await lane.load([request], clock)
        XCTAssertEqual(emptyRows.first?.outcome, .notListed)
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        await FixtureSourceCatalogCollector.refresh(requests: [request], lanes: [lane], index: index,
            at: clock, clock: { clock })
        XCTAssertTrue(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: clock),
            "An explicitly complete empty catalog is a checked listing, never a playback claim")
        XCTAssertEqual(index.summary(for: request, at: clock)?.listedProviderCount, 0)
        let wrongScope = cloudCatalogSnapshot(for: request, scope: "cricket", status: .empty, includesBroadcast: false)
        XCTAssertEqual(FixtureSourceCatalogCollector.lanes(primaryMatches: [], primaryFailure: nil,
            registrySnapshot: wrongScope, requests: [request], at: clock)
            .first { $0.providerCode == "communitysports" }?.origin, .local)
    }

    func testCloudConflictsWrongFingerprintAndGenericChannelCannotClaimCheckedFixture() async throws {
        let clock = now, request = StreamPlaybackRequest(event: exactListingFixture())
        for variant in ["conflicting", "needs-verification", "wrong-fingerprint", "channel"] {
            let snapshot = cloudCatalogSnapshot(for: request, variant: variant)
            let lane = try XCTUnwrap(FixtureSourceCatalogCollector.lanes(primaryMatches: [], primaryFailure: nil,
                registrySnapshot: snapshot, requests: [request], at: clock).first { $0.providerCode == "communitysports" })
            let rows = try await lane.load([request], clock)
            XCTAssertNotEqual(rows.first?.outcome, .listed, variant)
            XCTAssertNotEqual(rows.first?.outcome, .notListed, variant)
            let index = FixtureCatalogAvailabilityIndex()
            index.updateEnabledProviders(["communitysports"], revision: 1)
            await FixtureSourceCatalogCollector.refresh(requests: [request], lanes: [lane], index: index,
                at: clock, clock: { clock })
            XCTAssertFalse(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: clock), variant)
        }
    }

    func testCloudSnapshotNetworkExpiryAndDisableCannotBeRenewedByImport() async throws {
        let clock = now, request = StreamPlaybackRequest(event: exactListingFixture())
        let snapshot = cloudCatalogSnapshot(for: request,
            generatedAt: clock.addingTimeInterval(-BroadcastRegistrySnapshot.networkFreshness + 20))
        let lane = try XCTUnwrap(FixtureSourceCatalogCollector.lanes(primaryMatches: [], primaryFailure: nil,
            registrySnapshot: snapshot, requests: [request], at: clock).first { $0.providerCode == "communitysports" })
        let rows = try await lane.load([request], clock)
        XCTAssertEqual(rows.first?.evidenceValidUntil, clock.addingTimeInterval(20))
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        await FixtureSourceCatalogCollector.refresh(requests: [request], lanes: [lane], index: index,
            at: clock, clock: { clock })
        XCTAssertTrue(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: clock))
        XCTAssertFalse(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: clock.addingTimeInterval(20)))
        XCTAssertEqual(FixtureSourceCatalogCollector.lanes(primaryMatches: [], primaryFailure: nil,
            registrySnapshot: snapshot, requests: [request], at: clock.addingTimeInterval(20))
            .first { $0.providerCode == "communitysports" }?.origin, .local,
            "An old envelope restores bounded local fallback")
        let disabled = FixtureCatalogAvailabilityIndex()
        disabled.updateEnabledProviders([], revision: 1)
        await FixtureSourceCatalogCollector.refresh(requests: [request], lanes: [lane], index: disabled,
            at: clock, clock: { clock })
        XCTAssertEqual(disabled.retainedRecordCount, 0)
        XCTAssertFalse(disabled.hasRecentSuccessfulCatalogEvaluation(for: [request], at: clock))
    }

    func testOldCloudCohortReceiptRestoresLocalFallbackDespiteFreshEnvelope() {
        let clock = now, request = StreamPlaybackRequest(event: exactListingFixture())
        let old = clock.addingTimeInterval(-FixtureCatalogAvailabilityIndex.minimumRefreshInterval - 60)
        let snapshot = BroadcastRegistrySnapshot(schemaVersion: 1, revision: "old-cloud-cohort", generatedAt: clock,
            providers: [.init(providerCode: "communitysports", scope: "football", status: .available, complete: true,
                observedAt: old, expiresAt: clock.addingTimeInterval(600))], broadcasts: [], links: [])
        XCTAssertEqual(FixtureSourceCatalogCollector.lanes(primaryMatches: [], primaryFailure: nil,
            registrySnapshot: snapshot, requests: [request], at: clock)
            .first { $0.providerCode == "communitysports" }?.origin, .local)
    }

    func testNewCloudReceiptImportsAtSixtySecondsWithoutRenewingCachedEvidence() throws {
        let clock = now, request = StreamPlaybackRequest(event: exactListingFixture())
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        index.replaceFixtures([request], at: clock)
        let first = FixtureSourceCatalogMatch(matchID: request.matchID, outcome: .listed,
            providerEventID: "cloud-fixture", evidenceObservedAt: clock.addingTimeInterval(-120),
            evidenceValidUntil: clock.addingTimeInterval(600))
        let initial = try XCTUnwrap(index.beginCloudImport(providerCode: "communitysports", matches: [first],
            requests: [request], at: clock))
        index.complete(initial, matches: [first], at: clock)
        let secondAt = clock.addingTimeInterval(60)
        XCTAssertNil(index.beginCloudImport(providerCode: "communitysports", matches: [first],
            requests: [request], at: secondAt), "An unchanged source receipt does not produce another import")
        let newer = FixtureSourceCatalogMatch(matchID: request.matchID, outcome: .listed,
            providerEventID: "cloud-fixture", evidenceObservedAt: secondAt,
            evidenceValidUntil: clock.addingTimeInterval(660))
        let second = try XCTUnwrap(index.beginCloudImport(providerCode: "communitysports", matches: [newer],
            requests: [request], at: secondAt))
        index.complete(second, matches: [newer], at: secondAt)
        XCTAssertEqual(index.summary(for: request, at: secondAt)?.providers.first?.checkedAt, secondAt)
        XCTAssertTrue(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: clock.addingTimeInterval(300)),
            "A genuinely newer cloud observation must not be dropped behind a local 300-second reservation")
        let replayAt = clock.addingTimeInterval(301)
        XCTAssertNil(index.beginCloudImport(providerCode: "communitysports", matches: [first],
            requests: [request], at: replayAt))
        XCTAssertEqual(index.summary(for: request, at: replayAt)?.providers.first?.checkedAt, secondAt,
            "An older cloud replay must not overwrite a newer accepted observation")
    }

    func testCloudImportsDoNotSpendLocalRequestBudgetAndKeepRevocationCapacityBounds() throws {
        let clock = now, request = StreamPlaybackRequest(event: exactListingFixture())
        let index = FixtureCatalogAvailabilityIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        index.replaceFixtures([request], at: clock)
        let row = FixtureSourceCatalogMatch(matchID: request.matchID, outcome: .listed,
            providerEventID: "cloud-fixture", evidenceObservedAt: clock,
            evidenceValidUntil: clock.addingTimeInterval(200))
        let ticket = try XCTUnwrap(index.beginCloudImport(providerCode: "communitysports", matches: [row],
            requests: [request], at: clock))
        index.complete(ticket, matches: [row], at: clock)
        let fallbackAt = clock.addingTimeInterval(240)
        XCTAssertFalse(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: fallbackAt))
        let local = try XCTUnwrap(index.begin(providerCode: "communitysports", at: fallbackAt),
            "Cloud imports perform no HTTP and cannot consume the first local fallback opportunity")
        index.abandon(local)
        XCTAssertNil(index.begin(providerCode: "communitysports", at: fallbackAt.addingTimeInterval(1)),
            "The real local request still retains its original 300-second reservation")

        let later = clock.addingTimeInterval(241)
        let changed = FixtureSourceCatalogMatch(matchID: request.matchID, outcome: .notListed,
            evidenceObservedAt: later, evidenceValidUntil: later.addingTimeInterval(200))
        let revoked = try XCTUnwrap(index.beginCloudImport(providerCode: "communitysports", matches: [changed],
            requests: [request], at: later))
        index.updateEnabledProviders([], revision: 2)
        index.complete(revoked, matches: [changed], at: later)
        XCTAssertEqual(index.retainedRecordCount, 0, "Revocation fences an already pending cloud owner")
        XCTAssertNil(index.beginCloudImport(providerCode: "communitysports", matches: [changed],
            requests: [request], at: later))

        index.updateEnabledProviders(["communitysports"], revision: 3)
        XCTAssertNil(index.beginCloudImport(providerCode: "communitysports", matches: Array(repeating: changed, count: 257),
            requests: [request], at: later), "Cloud imports retain the bounded metadata inventory")
    }

    func testInvalidCloudEvidenceLeaseNeverBecomesRecentSuccessfulCatalog() throws {
        let request = StreamPlaybackRequest(event: exactListingFixture())
        for lease in [Date(timeIntervalSince1970: .infinity), now.addingTimeInterval(-1)] {
            let index = FixtureCatalogAvailabilityIndex()
            index.updateEnabledProviders(["communitysports"], revision: 1)
            index.replaceFixtures([request], at: now)
            let ticket = try XCTUnwrap(index.begin(providerCode: "communitysports", at: now))
            index.complete(ticket, matches: [.init(matchID: request.matchID, outcome: .listed,
                providerEventID: "cloud-fixture", evidenceObservedAt: now, evidenceValidUntil: lease)], at: now)
            XCTAssertFalse(index.hasRecentSuccessfulCatalogEvaluation(for: [request], at: now))
            XCTAssertEqual(index.summary(for: request, at: now)?.listedProviderCount, 0)
        }
    }

    private func cloudCatalogSnapshot(for request: StreamPlaybackRequest, scope: String = "football",
                                      status: BroadcastRegistrySnapshot.CoverageStatus = .available,
                                      includesBroadcast: Bool = true, variant: String = "listed",
                                      generatedAt: Date? = nil, expiry: Date? = nil) -> BroadcastRegistrySnapshot {
        let clock = now, expiry = expiry ?? now.addingTimeInterval(600), provider = "communitysports"
        let metadata = request.preferredEvent!.sportsFixture!
        let broadcast = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64),
            providerCode: provider, providerEventID: "cloud-football-fixture", streamID: "cloud-football-fixture",
            resourceType: "tv", scope: scope, kind: variant == "channel" ? .channel : .event,
            sport: "football", title: "Arsenal vs Chelsea", participants: variant == "channel" ? [] : ["Arsenal", "Chelsea"],
            start: variant == "channel" ? nil : request.kickoffDate, observedAt: clock, expiresAt: expiry,
            verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: request.matchID, broadcastID: broadcast.id, providerCode: provider,
            state: variant == "conflicting" ? .conflicting : variant == "needs-verification" ? .needsVerification : .listed,
            matchMethod: .exact, fixtureFingerprint: .init(fixtureID: request.matchID, sport: "football",
                start: request.kickoffDate!, participants: variant == "wrong-fingerprint" ? ["Liverpool", "Everton"] : ["Arsenal", "Chelsea"],
                competitionID: metadata.competitionID, squad: metadata.squad), expiresAt: expiry)
        return .init(schemaVersion: 1, revision: "cloud-catalog", generatedAt: generatedAt ?? clock,
            providers: [.init(providerCode: provider, scope: scope, status: status, complete: true,
                observedAt: clock, expiresAt: expiry)], broadcasts: includesBroadcast ? [broadcast] : [],
            links: includesBroadcast && variant != "channel" ? [link] : [])
    }

    func testOnlyFreshExactListedCatalogPermitsWatchWithoutRotatingDescriptorPreflight() throws {
        let event = exactListingFixture(), request = StreamPlaybackRequest(event: event)
        for outcome: FixtureSourceCatalogMatch.Outcome in [.listed, .needsVerification, .notListed,
            .conflicting, .unsupported, .failed(.manifestUnreachable)] {
            let catalog = FixtureCatalogAvailabilityIndex(), discovery = FixtureStreamDiscoveryIndex()
            catalog.updateEnabledProviders(["communitysports"], revision: 1)
            discovery.updateEnabledProviders(["communitysports"], revision: 1)
            catalog.replaceFixtures([request], at: now)
            let ticket = try XCTUnwrap(catalog.begin(providerCode: "communitysports", at: now))
            catalog.complete(ticket, matches: [.init(matchID: event.id, outcome: outcome,
                providerEventID: "exact_fixture")], at: now)
            let state = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: event, at: now,
                discoveryIndex: discovery, catalogIndex: catalog))
            XCTAssertEqual(state.canWatch, outcome == .listed)
            XCTAssertEqual(CurrentEventBroadcastPolicy.action(for: event, in: [event], at: now,
                discoveryIndex: discovery, catalogIndex: catalog)?.evidence, outcome == .listed ? .freshLookupOpportunity : nil)
            XCTAssertEqual(state.catalogListedProviderCount, outcome == .listed ? 1 : 0)
            XCTAssertEqual(state.detailsTitle, outcome == .listed ? "Broadcast listed" : "Broadcast unconfirmed")
            XCTAssertNil(discovery.summary(for: request, at: now), "A listing attempt must not require eager per-match descriptor work")
            let stale = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: event,
                at: now.addingTimeInterval(FixtureCatalogAvailabilityIndex.metadataLifetime),
                discoveryIndex: discovery, catalogIndex: catalog))
            XCTAssertFalse(stale.canWatch, "Expired listing/history must not grant Watch")
            XCTAssertNil(CurrentEventBroadcastPolicy.action(for: event, in: [event],
                at: now.addingTimeInterval(FixtureCatalogAvailabilityIndex.metadataLifetime),
                discoveryIndex: discovery, catalogIndex: catalog))
            catalog.updateEnabledProviders([], revision: 2)
            XCTAssertFalse(FixtureSourceLookupPresentation.state(for: event,
                at: now.addingTimeInterval(FixtureCatalogAvailabilityIndex.metadataLifetime + 1),
                discoveryIndex: discovery, catalogIndex: catalog)?.canWatch == true)
        }
    }

    func testNewerNegativeDescriptorVetoesOnlyItsOwnOlderListingEvenAfterDescriptorTTL() throws {
        let event = exactListingFixture(), request = StreamPlaybackRequest(event: event)
        let catalog = FixtureCatalogAvailabilityIndex(), discovery = FixtureStreamDiscoveryIndex()
        let enabled: Set<String> = ["communitysports", "plaviosports"]
        catalog.updateEnabledProviders(enabled, revision: 1)
        discovery.updateEnabledProviders(enabled, revision: 1)
        catalog.replaceFixtures([request], at: now)
        for code in enabled {
            let ticket = try XCTUnwrap(catalog.begin(providerCode: code, at: now))
            catalog.complete(ticket, matches: [.init(matchID: event.id, outcome: .listed,
                providerEventID: code + "_exact")], at: now)
        }
        let empty = try XCTUnwrap(discovery.begin(for: request, providerCode: "communitysports",
            preflight: false, at: now.addingTimeInterval(1)))
        discovery.complete(empty, sessions: [], at: now.addingTimeInterval(1))
        let sibling = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: event,
            at: now.addingTimeInterval(1), discoveryIndex: discovery, catalogIndex: catalog))
        XCTAssertTrue(sibling.canWatch)
        XCTAssertEqual(sibling.catalogListedProviderCount, 1, "One empty descriptor must not hide an independently listed sibling")
        let failed = try XCTUnwrap(discovery.begin(for: request, providerCode: "plaviosports",
            preflight: false, at: now.addingTimeInterval(2)))
        discovery.complete(failed, sessions: [], failure: StreamFailure(providerName: "AS1", category: .manifestUnreachable,
            technicalMessage: "Descriptor unavailable", userMessage: "Broadcast unconfirmed",
            retryable: true, fallbackAllowed: true), at: now.addingTimeInterval(2))
        for seconds in [2.0, 100.0] {
            let rejected = try XCTUnwrap(FixtureSourceLookupPresentation.state(for: event,
                at: now.addingTimeInterval(seconds), discoveryIndex: discovery, catalogIndex: catalog))
            XCTAssertTrue(rejected.canWatch)
            XCTAssertEqual(rejected.catalogListedProviderCount, 1)
            XCTAssertEqual(rejected.title, "Watch", "A transient fetch does not withdraw an exact unexpired listing")
        }
        let definitiveAt = now.addingTimeInterval(101)
        let definitive = try XCTUnwrap(discovery.begin(for: request, providerCode: "plaviosports", preflight: false, at: definitiveAt))
        discovery.complete(definitive, sessions: [], failure: LiveStreamResolver.communitySportsFailure(from: .conflictingMatch), at: definitiveAt)
        XCTAssertFalse(FixtureSourceLookupPresentation.state(for: event, at: definitiveAt,
            discoveryIndex: discovery, catalogIndex: catalog)?.canWatch == true)
        let renewedAt = now.addingTimeInterval(FixtureCatalogAvailabilityIndex.minimumRefreshInterval + 1)
        let renewed = try XCTUnwrap(catalog.begin(providerCode: "communitysports", at: renewedAt))
        catalog.complete(renewed, matches: [.init(matchID: event.id, outcome: .listed,
            providerEventID: "new_exact")], at: renewedAt)
        XCTAssertTrue(FixtureSourceLookupPresentation.state(for: event, at: renewedAt,
            discoveryIndex: discovery, catalogIndex: catalog)?.canWatch == true,
            "A genuinely newer exact catalog receipt permits another normal Watch attempt")
    }

    func testUnconfirmedFetchCannotExtendTheOriginalCatalogListingLifetime() throws {
        let event = exactListingFixture(), request = StreamPlaybackRequest(event: event)
        let catalog = FixtureCatalogAvailabilityIndex(), discovery = FixtureStreamDiscoveryIndex()
        catalog.updateEnabledProviders(["communitysports"], revision: 1)
        discovery.updateEnabledProviders(["communitysports"], revision: 1)
        catalog.replaceFixtures([request], at: now)
        let listing = try XCTUnwrap(catalog.begin(providerCode: "communitysports", at: now))
        catalog.complete(listing, matches: [.init(matchID: event.id, outcome: .listed, providerEventID: "exact_fixture")], at: now)
        let at = now.addingTimeInterval(20)
        let retry = try XCTUnwrap(discovery.begin(for: request, providerCode: "communitysports", preflight: false, at: at))
        discovery.complete(retry, sessions: [], failure: LiveStreamResolver.communitySportsFailure(from: .transportFailure(code: -1001, stage: .streams)), at: at)
        XCTAssertTrue(FixtureSourceLookupPresentation.state(for: event, at: at,
            discoveryIndex: discovery, catalogIndex: catalog)?.canWatch == true)
        XCTAssertFalse(FixtureSourceLookupPresentation.state(for: event,
            at: now.addingTimeInterval(FixtureCatalogAvailabilityIndex.metadataLifetime),
            discoveryIndex: discovery, catalogIndex: catalog)?.canWatch == true)
    }

    private func exactListingFixture() -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:arsenal-chelsea",
            sport: "football", competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Arsenal vs Chelsea", participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: now, verified: true)
        return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(-3600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)),
            sources: [], sportsFixture: metadata)
    }

    func testSharedPrimaryEvidenceDoesNotRefreshAnOmittedRetainedPartialRow() async {
        var clock = now, phase = 0
        let original = EventReference(id: "provider-celtics", title: "Boston Celtics vs New York Knicks", category: "NBA",
            date: Int64(now.addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil,
            sources: [.init(source: "delta", id: "provider-stream")])
        let sports = sportsSnapshot()
        let model = MatchListViewModel(fetchSnapshot: {
            .init(events: phase == 0 ? [original] : [], checkedAt: clock, source: "controlled-primary",
                  respondingFeeds: 1, attemptedFeeds: 3, isPartial: phase != 0)
        }, refreshSports: { sports }, now: { clock })
        await model.refresh()
        let requests = model.sourceCatalogRequests(at: clock)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(model.primarySourceCatalogEvidence(for: requests, at: clock).matches.first?.outcome, .listed)
        phase = 1; clock = now.addingTimeInterval(60)
        await model.refresh()
        XCTAssertFalse(model.matches.isEmpty, "Partial primary responses must preserve official browsing inventory")
        XCTAssertEqual(model.primarySourceCatalogEvidence(for: requests, at: clock).matches.first?.outcome, .notListed,
            "A current partial receipt cannot renew an omitted source listing")
    }
}
