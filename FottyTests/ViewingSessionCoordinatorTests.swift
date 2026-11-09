import XCTest
import AVFoundation
@testable import Fotty

/// Prepared-choice and presentation ownership tests, not decoded playback proof.
/// Models are never started with the dummy URLs; items use local compositions.
@MainActor
final class ViewingSessionCoordinatorTests: XCTestCase {
    @MainActor private final class SingleDiscoveryGate {
        var publish: (@Sendable ([StreamSession]) async -> Void)?
        var finish: CheckedContinuation<StreamResolutionOutcome, Never>?
        func resolve(_ request: StreamPlaybackRequest,
                     publish: @escaping @Sendable ([StreamSession]) async -> Void) async -> StreamResolutionOutcome {
            self.publish = publish
            return await withCheckedContinuation { finish = $0 }
        }
        func complete(_ outcome: StreamResolutionOutcome) {
            let pending = finish; finish = nil; pending?.resume(returning: outcome)
        }
    }

    /// Real view-model refreshes keep terminal receipts when the primary
    /// catalog fails. The prepared source gate never requests media.
    @MainActor private final class OfficialTerminalGate {
        let sport: String
        let cancelled: Bool
        let kickoff: Date
        var now: Date
        var terminal = false

        init(sport: String, cancelled: Bool) {
            self.sport = sport
            self.cancelled = cancelled
            now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            kickoff = now.addingTimeInterval(-600)
        }

        private func stamp(_ value: Date) -> String { ISO8601DateFormatter().string(from: value) }

        func sportsSnapshot() -> SportsFixtureCatalog.Snapshot? {
            guard sport == "football" else { return nil }
            let checked = stamp(now)
            let row = SportsFixtureCatalog.Fixture(id: "sports-fixture:premier-league:terminal-admission",
                sport: sport, start: stamp(kickoff), status: terminal ? (cancelled ? .cancelled : .finished) : .live,
                eventKind: .match, title: "Arsenal FC vs Chelsea FC", competitionId: "premier-league",
                competitionName: "Premier League", participants: [
                    .init(id: "football-data:57", name: "Arsenal FC", role: "home"),
                    .init(id: "football-data:61", name: "Chelsea FC", role: "away")],
                squad: .init(gender: .men, ageGroup: "senior"),
                source: .init(name: "football-data.org", url: "https://www.football-data.org/",
                    observedAt: checked, verification: .verified))
            return .init(schemaVersion: 1, complete: true, checkedAt: checked,
                revision: "terminal-admission-\(terminal)", sourceStatus: .verified, fixtures: [row],
                coverage: [.init(sport: sport, competitionId: "premier-league", competitionName: "Premier League",
                    status: .covered, checkedAt: checked, fixtureCount: 1, pendingFixtureCount: 0, nextStart: nil)])
        }

        func cricketSnapshot() -> CricketFixtureCatalog.Snapshot? {
            guard sport == "cricket" else { return nil }
            let checked = stamp(now)
            let row = CricketFixtureCatalog.Fixture(id: "terminal-admission", start: stamp(kickoff), format: .odi,
                status: terminal ? (cancelled ? .cancelled : .finished) : .live,
                competitionId: "west-indies", competitionName: "West Indies tour of India",
                home: .init(id: "india-men", name: "India"), away: .init(id: "wi-men", name: "West Indies"),
                source: .init(name: "Official fixtures", url: "https://www.icc-cricket.com/fixtures-results",
                    observedAt: checked, verification: .verified))
            return .init(schemaVersion: 1, complete: true, checkedAt: checked,
                revision: "terminal-admission-\(terminal)", sourceStatus: .verified, fixtures: [row],
                coverage: [.init(competitionId: "west-indies", competitionName: "West Indies tour of India",
                    status: .covered, checkedAt: checked, fixtureCount: 1, expectedFixtureCount: 1, nextStart: nil)])
        }

        func makeCatalog() -> MatchListViewModel {
            MatchListViewModel(fetchSnapshot: {
                if self.terminal { throw URLError(.notConnectedToInternet) }
                let football = self.sport == "football"
                let provider = EventReference(id: "primary-terminal-admission",
                    title: football ? "Arsenal FC vs Chelsea FC" : "India vs West Indies", category: self.sport,
                    date: Int64(self.kickoff.timeIntervalSince1970), poster: nil, popular: false,
                    teams: .init(home: .init(name: football ? "Arsenal FC" : "India", badge: nil),
                        away: .init(name: football ? "Chelsea FC" : "West Indies", badge: nil)),
                    sources: [.init(source: "delta", id: "primary-terminal-admission")],
                    competitionID: football ? "premier-league" : nil)
                return .init(events: [provider], checkedAt: self.now, source: "controlled",
                    respondingFeeds: 1, attemptedFeeds: 1, isPartial: false)
            }, refreshCricket: { self.cricketSnapshot() }, refreshSports: { self.sportsSnapshot() }, now: { self.now })
        }

        func admitted(_ event: EventReference, in catalog: MatchListViewModel) -> EventReference? {
            guard let current = CurrentEventBroadcastPolicy.currentEvent(for: event,
                in: catalog.playbackAdmissionCatalog, at: now),
                MatchStartPolicy(event: current, now: now).timingAllowsPlayback else { return nil }
            return current
        }

        func finish() {
            now = now.addingTimeInterval(60)
            terminal = true
        }
    }

    func testAcceptedTerminalRefreshVetoesStaleWatchAndLateSingleChoicesDuringPrimaryFailure() async throws {
        for sport in ["football", "cricket"] {
            for cancelled in [false, true] {
                let official = OfficialTerminalGate(sport: sport, cancelled: cancelled)
                let catalog = official.makeCatalog()
                await catalog.refresh()
                let original = try XCTUnwrap(catalog.matches.first)
                XCTAssertTrue(MatchStartPolicy(event: original, now: official.now).canAttemptPlayback)
                let factory = ModelFactory(), sources = SingleDiscoveryGate()
                let choice = session(for: original)
                let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                    discoverSinglePlayback: { await sources.resolve($0, publish: $1) },
                    currentSingleEvent: { official.admitted($0, in: catalog) },
                    catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
                defer { sources.complete(outcome(for: original, sessions: [])); owner.stop() }
                owner.watchSingle(original)
                await waitForSourceCheck { sources.publish != nil }

                official.finish()
                await catalog.refresh()
                XCTAssertTrue(catalog.refreshFailed)
                XCTAssertTrue(catalog.matches.isEmpty)
                XCTAssertTrue(catalog.playbackCatalog.isEmpty, "Terminal admission facts must not become playable/UI rows")
                let terminal = try XCTUnwrap(CurrentEventBroadcastPolicy.currentEvent(for: original,
                    in: catalog.playbackAdmissionCatalog, at: official.now))
                XCTAssertEqual(terminal.id, original.id)
                XCTAssertTrue(terminal.sources?.isEmpty != false)
                XCTAssertNil(CurrentEventBroadcastPolicy.action(for: original, in: catalog.playbackAdmissionCatalog,
                    at: official.now, status: .inPlay), "The old sheet cannot keep Watch even while another score poll is live")
                XCTAssertEqual(CatalogEventDetailsPresentation.broadcast(for: terminal, now: official.now,
                    status: .inPlay).title, cancelled ? "Cancelled" : "Finished")

                await sources.publish?([choice])
                sources.complete(outcome(for: original, sessions: [choice]))
                await waitForSourceCheck { owner.resolutionMessage == nil }
                XCTAssertTrue(factory.models.isEmpty, "A late valid delivery cannot resurrect the accepted terminal fixture")
                XCTAssertFalse(owner.isActive)
            }
        }
    }

    func testAcceptedTerminalRefreshDoesNotStopOrReplaceAnAlreadyMountedSingle() async throws {
        for sport in ["football", "cricket"] {
            let official = OfficialTerminalGate(sport: sport, cancelled: false)
            let catalog = official.makeCatalog()
            await catalog.refresh()
            let original = try XCTUnwrap(catalog.matches.first)
            let factory = ModelFactory(), sources = SingleDiscoveryGate()
            let first = session(for: original)
            let later = StreamSession(matchID: original.id, playableURL: URL(string: "https://example.invalid/late.m3u8")!,
                streamType: .hls, providerName: "AS1")
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { await sources.resolve($0, publish: $1) },
                currentSingleEvent: { official.admitted($0, in: catalog) },
                catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { sources.complete(outcome(for: original, sessions: [])); owner.stop() }
            owner.watchSingle(original)
            await waitForSourceCheck { sources.publish != nil }
            await sources.publish?([first])
            let pane = try XCTUnwrap(owner.primary)
            let item = AVPlayerItem(asset: AVMutableComposition())
            pane.model.player = AVPlayer(playerItem: item)
            pane.model.transition(to: .playing(.native), phase: "Playing")
            let requestID = pane.model.loadRequestID
            let state = pane.model.playbackState
            XCTAssertTrue(pane.model.userWantsPlayback)

            official.finish()
            await catalog.refresh()
            await sources.publish?([first, later])
            sources.complete(outcome(for: original, sessions: [first, later]))
            await waitForSourceCheck { owner.resolutionMessage == nil }
            XCTAssertEqual(factory.models.count, 1)
            XCTAssertTrue(owner.primary?.model === pane.model)
            XCTAssertTrue(pane.model.player?.currentItem === item)
            XCTAssertEqual(pane.model.loadRequestID, requestID)
            XCTAssertEqual(pane.model.sessions.map(\.id), [first.id])
            XCTAssertEqual(pane.model.activeSession?.id, first.id)
            XCTAssertEqual(pane.model.playbackState, state)
            XCTAssertTrue(pane.model.userWantsPlayback)
            XCTAssertTrue(owner.isActive, "A discovery admission veto must not retire existing owner playback")
        }
    }

    func testLegacySavedProviderIdentityKeepsTerminalVetoAfterAliasExpiryAndClockAdvance() async throws {
        let official = OfficialTerminalGate(sport: "football", cancelled: false)
        let catalog = official.makeCatalog()
        await catalog.refresh()
        let canonical = try XCTUnwrap(catalog.matches.first)
        let oldProvider = EventReference(id: "primary-terminal-admission", title: canonical.title,
            category: canonical.category, date: canonical.date, poster: nil, popular: false,
            teams: canonical.teams, sources: canonical.sources)
        let saved = SavedMatchRecord(event: oldProvider, savedAt: official.now)
        let legacy = try XCTUnwrap(SavedMatchContinuityPolicy.currentEvent(for: saved, in: catalog.playbackCatalog))
        XCTAssertEqual(legacy.id, oldProvider.id)
        XCTAssertEqual(legacy.sportsFixture?.fixtureID, canonical.id)
        let liveAction = try XCTUnwrap(CurrentEventBroadcastPolicy.action(for: legacy,
            in: catalog.playbackAdmissionCatalog, at: official.now))
        XCTAssertEqual(liveAction.event.id, canonical.id,
            "The normal Watch route resolves the saved provider alias before entering single discovery")

        let factory = ModelFactory(), sources = SingleDiscoveryGate()
        let choice = session(for: liveAction.event)
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await sources.resolve($0, publish: $1) },
            currentSingleEvent: { official.admitted($0, in: catalog) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { sources.complete(outcome(for: liveAction.event, sessions: [])); owner.stop() }
        owner.watchSingle(liveAction.event)
        await waitForSourceCheck { sources.publish != nil }
        official.finish()
        await catalog.refresh()
        let terminal = try XCTUnwrap(catalog.playbackAdmissionCatalog.first)
        XCTAssertNotEqual(terminal.id, legacy.id)
        XCTAssertNil(terminal.sportsFixture?.providerEventIDs,
            "The accepted terminal projection need not retain an old provider alias")
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: legacy, in: catalog.playbackAdmissionCatalog,
            at: official.now, status: .inPlay))
        XCTAssertTrue(catalog.playbackCatalog.isEmpty)

        // Memoized terminal projection retains the accepted final fact; clock
        // ageing cannot turn a still-open old live/sourced object back to Watch.
        official.now = official.now.addingTimeInterval(SportsFixtureCatalog.statusFreshness + 1)
        XCTAssertNotNil(VerifiedFixtureTerminalPolicy.state(for: terminal, at: official.now))
        XCTAssertNil(CurrentEventBroadcastPolicy.action(for: legacy, in: catalog.playbackAdmissionCatalog,
            at: official.now, status: .inPlay))
        await sources.publish?([choice])
        sources.complete(outcome(for: liveAction.event, sessions: [choice]))
        await waitForSourceCheck { owner.resolutionMessage == nil }
        XCTAssertTrue(factory.models.isEmpty)
        XCTAssertFalse(owner.isActive)
    }

    func testIncrementalSingleDiscoveryAppendsWithoutChangingPausedOwnerOrItem() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let match = event("incremental", date: Int64(Date().timeIntervalSince1970) - 60)
        let first = session(for: match)
        let second = StreamSession(matchID: match.id, playableURL: URL(string: "https://example.invalid/alternate.m3u8")!,
            streamType: .hls, providerName: "AS1")
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
        owner.watchSingle(match)
        XCTAssertEqual(owner.pendingSingleEvent?.id, match.id, "Existing sport-aware inline feedback begins before discovery")
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?([first])
        let pane = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: pane.model)
        let requestID = pane.model.loadRequestID
        XCTAssertTrue(pane.model.isCheckingAdditionalSources)
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.pendingSingleEvent)
        pane.model.showSourceSelector = true
        owner.minimize()
        await gate.publish?([first, second, second])
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === pane.model)
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertEqual(pane.model.loadRequestID, requestID)
        XCTAssertEqual(pane.model.activeSession?.id, first.id)
        XCTAssertEqual(pane.model.sessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(pane.model.playbackState, .paused(.native))
        XCTAssertTrue(pane.model.showSourceSelector)
        XCTAssertFalse(owner.expanded)
        gate.complete(outcome(for: match, sessions: [first, second]))
        await waitForSourceCheck { !pane.model.isCheckingAdditionalSources }
        XCTAssertEqual(pane.model.sessions.count, 2)
    }

    func testStoppedSingleDiscoveryCannotPublishLateChoicesOrRevivePlayer() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let match = event("cancel-incremental", date: Int64(Date().timeIntervalSince1970) - 60)
        let choice = session(for: match)
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
        owner.watchSingle(match)
        await waitForSourceCheck { gate.publish != nil }
        owner.cancelPendingSingleDiscovery()
        await gate.publish?([choice])
        gate.complete(outcome(for: match, sessions: [choice]))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(factory.models.isEmpty)
        XCTAssertFalse(owner.isActive)
        XCTAssertNil(owner.resolutionMessage)
    }

    func testSingleDiscoveryRetryUsesExactEventAndPreservesRetainedPausedPlaybackOnFailure() async throws {
        let factory = ModelFactory()
        let match = event("retry-discovery", home: "Chelsea", away: "Brighton",
            date: Int64(Date().timeIntervalSince1970) - 60, competition: "premier-league")
        var requests: [StreamPlaybackRequest] = []
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { request, _ in
                requests.append(request)
                return self.discoveryFailure(for: match, category: .providerTimeout, retryable: true)
            }, rediscoverSinglePlayback: { request, _ in
                requests.append(request)
                return self.discoveryFailure(for: match, category: .providerTimeout, retryable: true)
            }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        let retained = event("retained-before-discovery")
        owner.open(event: retained, sessions: [session(for: retained)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        let attempt = original.model.loadRequestID
        owner.minimize()
        owner.watchSingle(match)
        await waitForSourceCheck { owner.singleDiscoveryRecovery != nil }
        XCTAssertEqual(owner.singleDiscoveryRecovery?.event.id, match.id)
        XCTAssertEqual(owner.singleDiscoveryRecovery?.category, .providerTimeout)
        XCTAssertTrue(owner.canRetrySingleDiscovery)
        XCTAssertFalse(owner.canManageSingleDiscoverySources)

        owner.retrySingleDiscovery()
        XCTAssertNil(owner.singleDiscoveryRecovery)
        XCTAssertEqual(owner.pendingSingleEvent?.id, match.id)
        await waitForSourceCheck { requests.count == 2 && owner.singleDiscoveryRecovery != nil }

        XCTAssertEqual(requests.map(\.matchID), [match.id, match.id])
        XCTAssertEqual(requests.map(\.kickoffDate), [match.kickoffDate, match.kickoffDate])
        XCTAssertEqual(requests.map(\.homeTeam), [match.homeName, match.homeName])
        XCTAssertEqual(requests.map(\.awayTeam), [match.awayName, match.awayName])
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(original.model.userWantsPlayback)
        XCTAssertFalse(owner.expanded)
    }

    func testSingleDiscoveryRetryRejectsCorrectedOrFinishedCurrentFixtureBeforeLookup() async throws {
        let now = Date(), kickoff = Int64(Date().timeIntervalSince1970) - 60
        for finished in [false, true] {
            let match = event("retry-current-\(finished)", home: "Chelsea", away: "Brighton", date: kickoff,
                competition: "premier-league")
            var current = match, discoveries = 0
            let factory = ModelFactory()
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { _, _ in
                    discoveries += 1
                    return self.discoveryFailure(for: match, category: .providerTimeout, retryable: true)
                }, currentSingleEvent: { _ in current }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.watchSingle(match)
            await waitForSourceCheck { owner.canRetrySingleDiscovery }
            if finished {
                let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:retry-finished",
                    sport: "football", competitionID: "premier-league", competitionName: "Premier League",
                    eventKind: .match, title: "Chelsea vs Brighton", participants: [
                        .init(id: "chelsea", name: "Chelsea"), .init(id: "brighton", name: "Brighton")],
                    squad: .init(gender: .men, ageGroup: "senior"), status: .finished,
                    observedAt: now, verified: true, providerObservedAt: now, providerEventIDs: [match.id])
                current = event(match.id, home: "Chelsea", away: "Brighton", date: kickoff,
                    competition: "premier-league", fixture: metadata)
                XCTAssertTrue(MatchStartPolicy(event: current).isStopped)
            } else {
                current = event(match.id, home: "Chelsea", away: "Arsenal", date: kickoff,
                    competition: "premier-league")
            }

            owner.retrySingleDiscovery()
            await waitForSourceCheck { owner.resolutionMessage == nil }

            XCTAssertEqual(discoveries, 1)
            XCTAssertNil(owner.singleDiscoveryRecovery)
            XCTAssertFalse(owner.canRetrySingleDiscovery)
            XCTAssertTrue(factory.models.isEmpty)
            XCTAssertFalse(owner.isActive)
        }
    }

    func testSingleDiscoveryRecoveryClearsOnDismissalAndEveryReplacementIncludingEqualMessage() async throws {
        let match = event("clear-discovery-recovery", date: Int64(Date().timeIntervalSince1970) - 60)
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { _, _ in
            self.discoveryFailure(for: match, category: .providerTimeout, retryable: true)
        }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        for replacement in [String?.some("Discovery failed"), nil, "Unrelated player error"] {
            owner.watchSingle(match)
            await waitForSourceCheck { owner.singleDiscoveryRecovery != nil }
            XCTAssertEqual(owner.resolutionError, "Discovery failed")

            owner.resolutionError = replacement
            owner.retrySingleDiscovery()

            XCTAssertNil(owner.singleDiscoveryRecovery)
            XCTAssertNil(owner.pendingSingleEvent)
            XCTAssertEqual(owner.resolutionError, replacement)
            XCTAssertFalse(owner.canRetrySingleDiscovery)
            XCTAssertFalse(owner.manageSingleDiscoverySources())
        }
    }

    func testOnlyNoProviderDiscoveryFailureOffersSourceManagementWithoutAutomaticRetry() async throws {
        let match = event("manage-discovery-sources", date: Int64(Date().timeIntervalSince1970) - 60)
        for (category, retryable) in [(StreamFailureCategory.noProviderAvailable, false),
                                      (.invalidMatchMapping, false), (.providerTimeout, true)] {
            var discoveries = 0
            let factory = ModelFactory()
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { _, _ in
                    discoveries += 1
                    return self.discoveryFailure(for: match, category: category, retryable: retryable)
                }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.watchSingle(match)
            await waitForSourceCheck { owner.singleDiscoveryRecovery != nil }
            XCTAssertEqual(owner.canRetrySingleDiscovery, retryable)
            XCTAssertEqual(owner.canManageSingleDiscoverySources, category == .noProviderAvailable)
            if !retryable {
                owner.retrySingleDiscovery()
                XCTAssertNil(owner.pendingSingleEvent)
            }

            XCTAssertEqual(owner.manageSingleDiscoverySources(), category == .noProviderAvailable)

            XCTAssertEqual(discoveries, 1)
            XCTAssertTrue(factory.models.isEmpty)
            XCTAssertFalse(owner.isActive)
            if category == .noProviderAvailable {
                XCTAssertNil(owner.resolutionError)
                XCTAssertNil(owner.singleDiscoveryRecovery)
            }
        }
    }

    func testCancelledLateAndMountedSingleFailuresNeverAttachRecoveryAlert() async throws {
        for action in ["cancel", "mounted", "navigation", "duplicate", "user", "background"] {
            let factory = ModelFactory(), gate = SingleDiscoveryGate()
            let match = event("silent-discovery-\(action)", date: Int64(Date().timeIntervalSince1970) - 60)
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { await gate.resolve($0, publish: $1) }, currentSingleEvent: { $0 },
                catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
            owner.watchSingle(match)
            await waitForSourceCheck { gate.publish != nil }
            if action == "cancel" { owner.cancelPendingSingleDiscovery() }
            if action == "mounted" { await gate.publish?([session(for: match)]) }
            let category: StreamFailureCategory = switch action {
            case "navigation": .navigationCancelled
            case "duplicate": .duplicateRequestCancelled
            case "user": .userCancelled
            case "background": .backgroundedDuringResolution
            default: .providerTimeout
            }
            gate.complete(discoveryFailure(for: match, category: category, retryable: true))
            await waitForSourceCheck { owner.resolutionMessage == nil }
            for _ in 0..<10 { await Task.yield() }

            XCTAssertNil(owner.resolutionError, action)
            XCTAssertNil(owner.singleDiscoveryRecovery, action)
            XCTAssertFalse(owner.canRetrySingleDiscovery, action)
            XCTAssertFalse(owner.canManageSingleDiscoverySources, action)
            XCTAssertEqual(factory.models.count, action == "mounted" ? 1 : 0)
        }
    }

    func testIncrementalSingleDiscoveryRejectsForeignMatchAndPreservesHeaderAlternatives() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let match = event("identity-incremental", date: Int64(Date().timeIntervalSince1970) - 60)
        let url = URL(string: "https://example.invalid/delivery.m3u8")!
        let first = StreamSession(matchID: match.id, playableURL: url, streamType: .hls, providerName: "AS1",
            requiredHeaders: ["Referer": "https://example.invalid/a"])
        let second = StreamSession(matchID: match.id, playableURL: url, streamType: .hls, providerName: "AS2",
            requiredHeaders: ["Referer": "https://example.invalid/b"])
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
        owner.watchSingle(match)
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?([session(for: event("another-match"))])
        XCTAssertFalse(owner.isActive)
        await gate.publish?([first])
        await gate.publish?([first, second])
        XCTAssertEqual(owner.primary?.model.sessions.map(\.id), [first.id, second.id])
        owner.stop()
        await gate.publish?([first, second])
        XCTAssertFalse(owner.isActive)
    }

    func testPendingSingleDiscoveryRejectsCorrectedIdentityBeforeFirstChoiceAndCompletion() async {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let kickoff = Int64(Date().timeIntervalSince1970) - 60
        let match = event("corrected-incremental", home: "Chelsea", away: "Brighton", date: kickoff,
            competition: "premier-league")
        let choice = session(for: match)
        var current = match
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { _ in current }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
        owner.watchSingle(match)
        await waitForSourceCheck { gate.publish != nil }
        current = event(match.id, home: "Chelsea", away: "Everton", date: kickoff,
            competition: "premier-league")
        await gate.publish?([choice])
        XCTAssertTrue(factory.models.isEmpty, "A same-ID participant correction must veto an old delivery before mounting")
        gate.complete(outcome(for: match, sessions: [choice]))
        await waitForSourceCheck { owner.resolutionMessage == nil }
        XCTAssertTrue(factory.models.isEmpty, "A terminal success cannot re-admit the stale discovery snapshot")
        XCTAssertFalse(owner.isActive)
        XCTAssertNotNil(owner.resolutionError)
    }

    func testPendingSingleDiscoveryRejectsChangedKickoffBeforeFirstChoiceAndCompletion() async {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let kickoff = Int64(Date().timeIntervalSince1970) - 60
        let match = event("rescheduled-incremental", home: "Chelsea", away: "Brighton", date: kickoff,
            competition: "premier-league")
        let choice = session(for: match)
        var current = match
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { _ in current }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
        owner.watchSingle(match)
        await waitForSourceCheck { gate.publish != nil }
        // Keep both dates in the playable window so the exact identity fence,
        // not merely a future-kickoff timing rejection, is exercised.
        current = event(match.id, home: "Chelsea", away: "Brighton", date: kickoff - 60,
            competition: "premier-league")
        await gate.publish?([choice])
        XCTAssertTrue(factory.models.isEmpty)
        gate.complete(outcome(for: match, sessions: [choice]))
        await waitForSourceCheck { owner.resolutionMessage == nil }
        XCTAssertTrue(factory.models.isEmpty)
        XCTAssertFalse(owner.isActive)
    }

    func testPendingSingleDiscoveryRejectsTerminalOrQuarantinedSnapshotBeforeMount() async {
        let now = Date(), kickoff = Int64(Date().timeIntervalSince1970) - 60
        for quarantined in [false, true] {
            let factory = ModelFactory(), gate = SingleDiscoveryGate()
            let match = event("veto-before-mount-\(quarantined)", home: "Chelsea", away: "Brighton", date: kickoff,
                competition: "premier-league")
            let stoppedFixture = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:stopped",
                sport: "football", competitionID: "premier-league", competitionName: "Premier League",
                eventKind: .match, title: "Chelsea vs Brighton", participants: [
                    .init(id: "chelsea", name: "Chelsea"), .init(id: "brighton", name: "Brighton")],
                squad: .init(gender: .men, ageGroup: "senior"), status: .finished,
                observedAt: now, verified: true, providerObservedAt: now, providerEventIDs: [match.id])
            let choice = session(for: match)
            var current = match
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { _ in current }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
            owner.watchSingle(match)
            await waitForSourceCheck { gate.publish != nil }
            current = event(match.id, conflict: quarantined, home: "Chelsea", away: "Brighton", date: kickoff,
                competition: "premier-league", fixture: quarantined ? nil : stoppedFixture)
            XCTAssertTrue(quarantined ? current.hasCatalogIdentityConflict : MatchStartPolicy(event: current).isStopped)
            await gate.publish?([choice])
            XCTAssertTrue(factory.models.isEmpty)
            gate.complete(outcome(for: match, sessions: [choice]))
            await waitForSourceCheck { owner.resolutionMessage == nil }
            XCTAssertTrue(factory.models.isEmpty)
            XCTAssertFalse(owner.isActive)
        }
    }

    func testLateCorrectedOrQuarantinedSnapshotCannotAppendOrRetirePausedOwner() async throws {
        for quarantined in [false, true] {
            let factory = ModelFactory(), gate = SingleDiscoveryGate()
            let kickoff = Int64(Date().timeIntervalSince1970) - 60
            let match = event("veto-after-mount-\(quarantined)", home: "Chelsea", away: "Brighton", date: kickoff,
                competition: "premier-league")
            let first = session(for: match)
            let second = StreamSession(matchID: match.id,
                playableURL: URL(string: "https://example.invalid/late-veto.m3u8")!, streamType: .hls, providerName: "AS1")
            var current = match
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { _ in current }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { gate.complete(outcome(for: match, sessions: [])); owner.stop() }
            owner.watchSingle(match)
            await waitForSourceCheck { gate.publish != nil }
            await gate.publish?([first])
            let pane = try XCTUnwrap(owner.primary)
            let item = installPausedLocalItem(on: pane.model)
            let attempt = pane.model.loadRequestID
            current = event(match.id, conflict: quarantined, home: "Chelsea",
                away: quarantined ? "Brighton" : "Everton", date: kickoff, competition: "premier-league")
            await gate.publish?([first, second])
            gate.complete(outcome(for: match, sessions: [first, second]))
            await waitForSourceCheck { !pane.model.isCheckingAdditionalSources }
            XCTAssertEqual(factory.models.count, 1)
            XCTAssertTrue(owner.primary?.model === pane.model)
            XCTAssertEqual(pane.model.sessions.map(\.id), [first.id])
            XCTAssertEqual(pane.model.activeSession?.id, first.id)
            XCTAssertEqual(pane.model.loadRequestID, attempt)
            XCTAssertTrue(pane.model.player?.currentItem === item)
            XCTAssertEqual(pane.model.playbackState, .paused(.native))
            XCTAssertFalse(pane.model.isPlaybackSessionRetired)
            XCTAssertFalse(pane.model.userWantsPlayback)
        }
    }

    @MainActor private final class ModelFactory {
        private(set) var models: [LivePlayerViewModel] = []

        func make(event: EventReference, sessions: [StreamSession]) -> LivePlayerViewModel {
            let model = LivePlayerViewModel(event: event, providedSessions: sessions,
                ownsRemoteCommands: false, prepareAudioSession: { .completed([]) })
            models.append(model)
            return model
        }
    }

    @MainActor private final class WebAudioRevocationGate {
        @MainActor final class Ticket {
            let ownerID: UUID
            private(set) var result: Bool?
            private(set) var pendingCount = 0
            private var pending: [CheckedContinuation<Bool, Never>] = []

            init(ownerID: UUID) { self.ownerID = ownerID }
            func wait() async -> Bool {
                if let result { return result }
                pendingCount += 1
                return await withCheckedContinuation { pending.append($0) }
            }
            func complete(_ result: Bool) {
                guard self.result == nil else { return }
                self.result = result
                let waiters = pending
                pending = []; pendingCount = 0
                waiters.forEach { $0.resume(returning: result) }
            }
        }

        var requiredOwners = Set<UUID>()
        private(set) var tickets: [Ticket] = []

        func capture(_ model: LivePlayerViewModel) -> (@MainActor () async -> Bool)? {
            guard requiredOwners.contains(model.remoteCommandOwnerID) else { return nil }
            let ticket = Ticket(ownerID: model.remoteCommandOwnerID)
            tickets.append(ticket)
            return { await ticket.wait() }
        }

        func finishAll() { tickets.forEach { $0.complete(false) } }
    }

    @MainActor private final class NativePairGate {
        var failedPreparationOwners = Set<UUID>()
        var heldPreparationOwners = Set<UUID>()
        var failedAdoptionOwners = Set<UUID>()
        private(set) var events: [String] = []
        private(set) var candidates: [PreparedNativeWatchTwoPlayback] = []
        private(set) var retirements: [UUID: WebAudioRevocationGate.Ticket] = [:]
        private var pending: [(UUID, PreparedNativeWatchTwoPlayback, CheckedContinuation<PreparedNativeWatchTwoPlayback?, Never>)] = []

        var operations: ViewingSessionCoordinator.NativeWatchTwoOperations {
            .init(prepare: { [self] model in
                events.append("prepare:\(model.event.id)")
                guard !failedPreparationOwners.contains(model.remoteCommandOwnerID), let selected = model.activeSession else { return nil }
                let item = AVPlayerItem(asset: AVMutableComposition()), player = AVPlayer()
                player.replaceCurrentItem(with: item)
                player.isMuted = true
                let isolation = NativePlayerAudioIsolation(player: player, item: item,
                    backend: .init(isSupported: true, setDisconnected: { _, _ in true }))
                let session = StreamSession(id: selected.id, matchID: selected.matchID, title: selected.title,
                    playableURL: URL(string: "https://example.invalid/atomic-\(model.event.id).m3u8")!,
                    streamType: .hls, providerName: selected.providerName, requiredHeaders: [:])
                let candidate = PreparedNativeWatchTwoPlayback(model: model, session: session,
                    player: player, item: item, isolation: isolation)
                candidates.append(candidate)
                if heldPreparationOwners.contains(model.remoteCommandOwnerID) {
                    return await withCheckedContinuation { pending.append((model.remoteCommandOwnerID, candidate, $0)) }
                }
                return candidate
            }, isCurrent: { model, candidate in
                !model.isPlaybackSessionRetired && model.remoteCommandOwnerID == candidate.modelID
                    && model.activeSource?.id == candidate.sourceID && model.loadRequestID == candidate.requestID
                    && model.userWantsPlayback == candidate.wantsPlayback
                    && model.nativeWatchTwoIntentID == candidate.intentID && model.viewingPlaybackContext == candidate.context
                    && !candidate.discarded
            }, beginRetirement: { [self] model, candidate in
                events.append("retire:\(model.event.id)")
                candidate.retirementBegan = true
                retirements[model.remoteCommandOwnerID] = .init(ownerID: model.remoteCommandOwnerID)
                return true
            }, waitForRetirement: { [self] model, candidate in
                guard let retirement = retirements[model.remoteCommandOwnerID] else { return false }
                let result = await retirement.wait()
                candidate.webRetired = result
                return result
            }, adopt: { [self] model, candidate in
                events.append("adopt:\(model.event.id)")
                guard !failedAdoptionOwners.contains(model.remoteCommandOwnerID) else { return false }
                XCTAssertTrue(candidates.allSatisfy(\.webRetired), "Neither native owner may adopt before both Web teardowns")
                candidate.adopted = true
                model.nativeHandoffSession = candidate.session
                model.player = candidate.player
                model.setViewingPlaybackContext(.watchTwo(engine: .native))
                model.transition(to: .paused(.native), phase: "Paused")
                return true
            }, start: { [self] model, candidate in
                events.append("start:\(model.event.id)")
                XCTAssertTrue(candidates.allSatisfy(\.adopted), "Both paused adoptions precede either native start")
                candidate.started = true
                model.transition(to: candidate.wantsPlayback ? .playing(.native) : .paused(.native),
                    phase: candidate.wantsPlayback ? "Playing" : "Paused")
            }, discard: { [self] model, candidate in
                guard !candidate.adopted else { return }
                events.append("discard:\(model.event.id)")
                candidate.discarded = true
                candidate.player.pause()
            }, releaseAudioHold: { [self] model, _ in
                events.append("release:\(model.event.id)")
                XCTAssertTrue(candidates.allSatisfy(\.started), "Both starts must be authorized before releasing audio holds")
            })
        }

        func completePreparation(ownerID: UUID) {
            let matching = pending.filter { $0.0 == ownerID }
            pending.removeAll { $0.0 == ownerID }
            matching.forEach { $0.2.resume(returning: $0.1) }
        }

        func hasPendingPreparation(ownerID: UUID) -> Bool { pending.contains { $0.0 == ownerID } }
        func finishAll() {
            let preparations = pending
            pending = []
            preparations.forEach { $0.2.resume(returning: nil) }
            retirements.values.forEach { $0.complete(false) }
        }
    }

    @MainActor private final class ResolutionGate {
        private(set) var requests: [StreamPlaybackRequest] = []
        private(set) var finishedResolutions = 0
        private var pending: [CheckedContinuation<StreamResolutionOutcome, Never>] = []
        func resolve(_ request: StreamPlaybackRequest) async -> StreamResolutionOutcome {
            requests.append(request)
            let result = await withCheckedContinuation { pending.append($0) }
            finishedResolutions += 1
            return result
        }
        func complete(_ outcome: StreamResolutionOutcome) {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume(returning: outcome)
        }
        func completeAll(_ outcome: StreamResolutionOutcome) {
            while !pending.isEmpty { complete(outcome) }
        }
    }

    @MainActor private final class RecordingHandoffPublisher: SportsHandoffActivityPublishing {
        private(set) var published: [SportsHandoffIdentity] = []
        private(set) var invalidations = 0
        func publish(identity: SportsHandoffIdentity, payload: Data) { published.append(identity) }
        func invalidate() { invalidations += 1 }
    }

    private func event(_ id: String, conflict: Bool = false, home: String? = nil,
                       away: String? = nil, title: String? = nil, category: String = "football",
                       date: Int64 = 1_800_000_000, competition: String? = nil,
                       fixture: SportsFixtureMetadata? = nil) -> EventReference {
        .init(id: id, title: title ?? "\(home ?? "\(id) home") vs \(away ?? "\(id) away")", category: category,
              date: date, poster: nil, popular: false,
              teams: .init(home: .init(name: home ?? "\(id) home", badge: nil),
                           away: .init(name: away ?? "\(id) away", badge: nil)),
              sources: [.init(source: "delta", id: "prepared-\(id)")],
              hasCatalogIdentityConflict: conflict, sportsFixture: fixture, competitionID: competition)
    }

    private func session(for event: EventReference, web: Bool = false) -> StreamSession {
        // A direct-media suffix deliberately takes precedence over embed headers
        // in the real classifier. Web fixtures must use an actual embed-shaped
        // endpoint, not an .m3u8 carrying contradictory test metadata.
        let route = web ? "embed/prepared-\(event.id)" : "prepared-\(event.id).m3u8"
        return StreamSession(matchID: event.id, title: event.displayTitle,
            playableURL: URL(string: "https://example.invalid/\(route)")!,
            streamType: web ? .unknown : .hls, providerName: "StreamEx",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:])
    }

    private func slot(_ event: EventReference, web: Bool = false) -> MultiLiveSlot {
        .init(event: event, sessions: [session(for: event, web: web)])
    }

    private func coordinator(factory: ModelFactory,
                             handoffPublisher: SportsHandoffPublisher? = nil,
                             webAudioGate: WebAudioRevocationGate? = nil,
                             nativePairGate: NativePairGate? = nil) -> ViewingSessionCoordinator {
        ViewingSessionCoordinator(handoffPublisher: handoffPublisher, nativeWatchTwo: nativePairGate?.operations,
            captureWebAudioRevocation: { model in
                if let webAudioGate { return webAudioGate.capture(model) }
                return model.captureWebAudioRevocationWaiter()
            },
            makeModel: { factory.make(event: $0, sessions: $1) })
    }

    private func outcome(for event: EventReference, sessions: [StreamSession], failed: Bool = false) -> StreamResolutionOutcome {
        let diagnostics = StreamAttemptDiagnostics(attemptID: "prepared-replacement", matchID: event.id,
            matchTitle: event.displayTitle, finalState: failed ? .failed : .readyToPlay,
            createdAt: Date(), completedAt: Date(), timeline: [], providerAttempts: [])
        if failed {
            return .failure(.init(category: .providerReturnedEmpty, technicalMessage: "Test resolution failed",
                userMessage: "No broadcast available", retryable: true, fallbackAllowed: true), diagnostics)
        }
        return .success(.init(attemptID: "prepared-replacement", sessions: sessions, diagnostics: diagnostics))
    }

    private func discoveryFailure(for event: EventReference, category: StreamFailureCategory,
                                  retryable: Bool) -> StreamResolutionOutcome {
        let diagnostics = StreamAttemptDiagnostics(attemptID: "single-discovery-failure", matchID: event.id,
            matchTitle: event.displayTitle, finalState: .failed, createdAt: Date(), completedAt: Date(),
            timeline: [], providerAttempts: [])
        return .failure(.init(category: category, technicalMessage: "Controlled discovery failure",
            userMessage: "Discovery failed", retryable: retryable, fallbackAllowed: false), diagnostics)
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("The bounded test owner did not reach its expected state", file: file, line: line)
    }

    @discardableResult
    private func installPausedLocalItem(on model: LivePlayerViewModel) -> AVPlayerItem {
        let item = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: item)
        model.transition(to: model.isUsingWebEmbed ? .playing(.webEmbed) : .playing(.native), phase: "Playing")
        model.togglePlayPause()
        XCTAssertEqual(model.playbackState, model.isUsingWebEmbed ? .paused(.webEmbed) : .paused(.native))
        XCTAssertFalse(model.userWantsPlayback)
        return item
    }

    private func isolatedLastLiveStore(enabled: Bool, now: Date) throws
        -> (store: LastLiveMatchStore, preferences: UserDefaults, domain: String) {
        let domain = "Fotty.ViewingSessionLastLiveTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        if enabled { preferences.set(true, forKey: LastLiveMatchStore.enablementKey) }
        return (LastLiveMatchStore(defaults: preferences, now: { now }), preferences, domain)
    }

    // These inject the existing guarded decoded callback to test capture wiring;
    // they do not claim decoded-media proof or start the dummy delivery URLs.
    func testLastLiveCaptureIsDefaultOffEvenAfterDecodedCallback() async throws {
        let now = Date(), factory = ModelFactory()
        let isolated = try isolatedLastLiveStore(enabled: false, now: now)
        let owner = ViewingSessionCoordinator(lastLiveStore: isolated.store,
            makeModel: { factory.make(event: $0, sessions: $1) })
        defer {
            owner.stop()
            isolated.preferences.removePersistentDomain(forName: isolated.domain)
        }
        let match = event("last-live-disabled", home: "Liverpool", away: "Chelsea",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        owner.open(event: match, sessions: [session(for: match)])
        let model = try XCTUnwrap(owner.primary?.model)
        let source = try XCTUnwrap(model.activeSource)
        model.transition(to: .playing(.native), phase: "Playing")
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: model.loadRequestID)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(model.hasConfirmedSinglePlayback)
        XCTAssertFalse(isolated.store.isEnabled)
        XCTAssertNil(isolated.store.record)
        XCTAssertNil(isolated.preferences.data(forKey: LastLiveMatchStore.storageKey))
        XCTAssertNil(model.player)
        XCTAssertNil(model.loadTask)
        XCTAssertFalse(model.didStartPlayback)
    }

    func testLastLiveCaptureRequiresDecodedCallbackRatherThanPreparedPlayingOrReady() async throws {
        let now = Date(), factory = ModelFactory()
        let isolated = try isolatedLastLiveStore(enabled: true, now: now)
        let owner = ViewingSessionCoordinator(lastLiveStore: isolated.store,
            makeModel: { factory.make(event: $0, sessions: $1) })
        defer {
            owner.stop()
            isolated.preferences.removePersistentDomain(forName: isolated.domain)
        }
        let match = event("last-live-confirmed", home: "Liverpool", away: "Chelsea",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        owner.open(event: match, sessions: [session(for: match)])
        let model = try XCTUnwrap(owner.primary?.model)
        let source = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        XCTAssertNil(isolated.store.record, "Preparing a selected source is not viewing")
        model.transition(to: .playing(.native), phase: "Playing")
        model.recordPlaybackStage(.mediaReady, sourceID: source.id, requestID: request)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(model.hasConfirmedSinglePlayback)
        XCTAssertNil(isolated.store.record, "Transport readiness and Playing alone cannot create history")
        XCTAssertNil(isolated.preferences.data(forKey: LastLiveMatchStore.storageKey))

        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        await waitFor { isolated.store.record?.eventID == match.id }

        XCTAssertNotNil(isolated.preferences.data(forKey: LastLiveMatchStore.storageKey))
        XCTAssertNil(model.player)
        XCTAssertNil(model.loadTask)
        XCTAssertFalse(model.didStartPlayback)
        XCTAssertEqual(factory.models.count, 1)
    }

    func testClearedLastLiveCaptureCannotReappearFromRenderMinimizeOrRetainedReopen() async throws {
        let now = Date(), factory = ModelFactory()
        let isolated = try isolatedLastLiveStore(enabled: true, now: now)
        let owner = ViewingSessionCoordinator(lastLiveStore: isolated.store,
            makeModel: { factory.make(event: $0, sessions: $1) })
        defer {
            owner.stop()
            isolated.preferences.removePersistentDomain(forName: isolated.domain)
        }
        let match = event("last-live-clear", home: "Liverpool", away: "Chelsea",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        owner.open(event: match, sessions: [session(for: match)])
        let pane = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: pane.model)
        let source = try XCTUnwrap(pane.model.activeSource), request = pane.model.loadRequestID
        pane.model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        await waitFor { isolated.store.record?.eventID == match.id }
        isolated.store.clear()

        for _ in 0..<3 {
            _ = owner.displayPanes
            _ = pane.model.hasConfirmedSinglePlayback
            owner.minimize()
            owner.expand()
            XCTAssertTrue(owner.reopenRetainedSingle(event: match, catalog: [match], status: .inPlay, now: now))
            await Task.yield()
        }
        // A repeated current callback also cannot recreate its consumed ticket.
        pane.model.recordPlaybackStage(.buffering, sourceID: source.id, requestID: request)
        await Task.yield()
        pane.model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertNil(isolated.store.record)
        XCTAssertNil(isolated.preferences.data(forKey: LastLiveMatchStore.storageKey))
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === pane.model)
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertEqual(pane.model.loadRequestID, request)
        XCTAssertEqual(pane.model.playbackState, .paused(.native))
    }

    func testStoppedLastLiveCaptureRejectsQueuedAndLateDecodedCallbacks() async throws {
        let now = Date(), factory = ModelFactory()
        let isolated = try isolatedLastLiveStore(enabled: true, now: now)
        let owner = ViewingSessionCoordinator(lastLiveStore: isolated.store,
            makeModel: { factory.make(event: $0, sessions: $1) })
        defer {
            owner.stop()
            isolated.preferences.removePersistentDomain(forName: isolated.domain)
        }
        let match = event("last-live-stop", home: "Liverpool", away: "Chelsea",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        owner.open(event: match, sessions: [session(for: match)])
        let model = try XCTUnwrap(owner.primary?.model)
        let source = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        // Stop before the observation continuation gets its next actor turn.
        owner.stop()
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(model.isPlaybackSessionRetired)
        XCTAssertFalse(owner.isActive)
        XCTAssertNil(isolated.store.record)
        XCTAssertNil(isolated.preferences.data(forKey: LastLiveMatchStore.storageKey))
    }

    func testReplacedLastLiveCaptureFencesOldOwnerAndRecordsOnlyCurrentDecodedCallback() async throws {
        let now = Date(), factory = ModelFactory()
        let isolated = try isolatedLastLiveStore(enabled: true, now: now)
        let owner = ViewingSessionCoordinator(lastLiveStore: isolated.store,
            makeModel: { factory.make(event: $0, sessions: $1) })
        defer {
            owner.stop()
            isolated.preferences.removePersistentDomain(forName: isolated.domain)
        }
        let first = event("last-live-old", home: "Liverpool", away: "Chelsea",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        let replacement = event("last-live-new", home: "Arsenal", away: "Everton",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        owner.open(event: first, sessions: [session(for: first)])
        let old = try XCTUnwrap(owner.primary?.model)
        let oldSource = try XCTUnwrap(old.activeSource), oldRequest = old.loadRequestID
        old.recordPlaybackStage(.decoded, sourceID: oldSource.id, requestID: oldRequest)
        owner.open(event: replacement, sessions: [session(for: replacement)])
        let current = try XCTUnwrap(owner.primary?.model)
        let currentSource = try XCTUnwrap(current.activeSource), currentRequest = current.loadRequestID
        old.recordPlaybackStage(.decoded, sourceID: oldSource.id, requestID: oldRequest)
        current.recordPlaybackStage(.mediaReady, sourceID: currentSource.id, requestID: currentRequest)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(old.isPlaybackSessionRetired)
        XCTAssertNil(isolated.store.record, "An old queued receipt cannot be attributed to its prepared replacement")

        current.recordPlaybackStage(.decoded, sourceID: currentSource.id, requestID: currentRequest)
        await waitFor { isolated.store.record?.eventID == replacement.id }
        old.recordPlaybackStage(.decoded, sourceID: oldSource.id, requestID: oldRequest)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(isolated.store.record?.eventID, replacement.id)
        XCTAssertTrue(owner.primary?.model === current)
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertNil(current.player)
        XCTAssertNil(current.loadTask)
        XCTAssertFalse(current.didStartPlayback)
    }

    func testRapidSinglePairSingleCannotCapturePairOnlyDecodedPlayback() async throws {
        let now = Date(), factory = ModelFactory()
        let isolated = try isolatedLastLiveStore(enabled: true, now: now)
        let owner = ViewingSessionCoordinator(lastLiveStore: isolated.store,
            makeModel: { factory.make(event: $0, sessions: $1) })
        defer {
            owner.stop()
            isolated.preferences.removePersistentDomain(forName: isolated.domain)
        }
        let first = event("last-live-pair-retained", home: "Liverpool", away: "Chelsea",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        let second = event("last-live-pair-other", home: "Arsenal", away: "Everton",
            date: Int64(now.timeIntervalSince1970) - 60, competition: "premier-league")
        owner.open(event: first, sessions: [session(for: first)])
        let retained = try XCTUnwrap(owner.primary)
        let source = try XCTUnwrap(retained.model.activeSource), request = retained.model.loadRequestID
        XCTAssertNil(isolated.store.record)

        // Complete every ownership change before the observation continuation
        // gets an actor turn. The only decoded receipt belongs to the pair.
        owner.openMulti(slots: [slot(first), slot(second)])
        XCTAssertTrue(owner.isTwo)
        XCTAssertTrue(owner.primary?.model === retained.model)
        retained.model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: request)
        XCTAssertFalse(retained.model.hasConfirmedSinglePlayback)
        owner.keepOnly(retained.id)
        XCTAssertFalse(owner.isTwo)
        XCTAssertTrue(owner.primary?.model === retained.model)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertNil(isolated.store.record, "A pair-only decoded receipt cannot confirm the cancelled single capture")
        XCTAssertNil(isolated.preferences.data(forKey: LastLiveMatchStore.storageKey))
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertNil(retained.model.player)
        XCTAssertNil(retained.model.loadTask)
        XCTAssertFalse(retained.model.didStartPlayback)
    }

    private func sourceCheckFixture(_ id: String, date: Int64 = 1_800_000_000,
                                    conflict: Bool = false) -> EventReference {
        .init(id: id, title: "Zimbabwe vs Afghanistan", category: "cricket", date: date,
              poster: nil, popular: false,
              teams: .init(home: .init(name: "Zimbabwe", badge: nil),
                           away: .init(name: "Afghanistan", badge: nil)), sources: [],
              hasCatalogIdentityConflict: conflict)
    }

    private func waitForSourceCheck(_ condition: () -> Bool,
                                    file: StaticString = #filePath, line: UInt = #line) async {
        // This route deliberately yields a feedback frame before doing work.
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The bounded optional-source check did not finish", file: file, line: line)
    }

    /// Ranking is local preference state. These integration units preserve the
    /// test host's previous values and never start the dummy media endpoints.
    private func preserveSourceRankingDefaults() -> () -> Void {
        let keys = ["fotty.live.sourceHealth.v1", "fotty.live.lastGoodProvider.v1"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        LiveSourceHealthStore.resetForTesting()
        return {
            LiveSourceHealthStore.resetForTesting()
            for (index, key) in keys.enumerated() {
                if let value = previous[index] { UserDefaults.standard.set(value, forKey: key) }
            }
        }
    }

    private func rankingSession(for event: EventReference, provider: String, host: String) -> StreamSession {
        .init(matchID: event.id, title: event.displayTitle,
              playableURL: URL(string: "https://\(host)/\(event.id).m3u8")!,
              streamType: .hls, providerName: provider, requiredHeaders: [:])
    }

    private func seedSlowLegacyAndFastSingleHistory(for event: EventReference)
        -> (slow: StreamSession, fast: StreamSession) {
        let slow = rankingSession(for: event, provider: "Score808", host: "slow-ranking.example.invalid")
        let fast = rankingSession(for: event, provider: "AS1", host: "fast-ranking.example.invalid")
        for _ in 0..<8 {
            LiveSourceHealthStore.recordSuccess(for: slow, startupLatencyMs: 18_000,
                contextKey: LiveSourceHealthStore.contextKey(for: event))
        }
        LiveSourceHealthStore.recordSuccess(for: fast, startupLatencyMs: 1_500)
        return (slow, fast)
    }

    func testSingleOpenExplicitlyChoosesFastASOverStrongSlowLegacyHistoryBeforeMount() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let match = event("single-ranking"), factory = ModelFactory()
        let choices = seedSlowLegacyAndFastSingleHistory(for: match)
        let candidates = [choices.fast, choices.slow]
        XCTAssertEqual(LiveSourceHealthStore.rankedSessions(candidates,
            contextKey: LiveSourceHealthStore.contextKey(for: match)).first?.id, choices.slow.id)
        let owner = coordinator(factory: factory)
        defer { owner.stop() }

        owner.open(event: match, sessions: candidates)

        let model = try XCTUnwrap(owner.primary?.model)
        XCTAssertTrue(model.usesSingleStreamRanking)
        XCTAssertEqual(model.viewingPlaybackContext, .single)
        XCTAssertEqual(model.activeSession?.id, choices.fast.id)
        XCTAssertEqual(model.sessions.map(\.id), [choices.slow.id, choices.fast.id],
                       "Single-source selection must not reorder the shared prepared choice array")
        XCTAssertFalse(model.didStartPlayback)
        XCTAssertNil(model.player)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.sourceAttemptStartedAt)
        XCTAssertEqual(factory.models.count, 1)
    }

    func testSharedInitializerAndWatchTwoOpenRetainLegacyRankingWithoutSingleOptIn() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let left = event("legacy-ranking-left"), right = event("legacy-ranking-right")
        let choices = seedSlowLegacyAndFastSingleHistory(for: left)
        let shared = LivePlayerViewModel(event: left, providedSessions: [choices.fast, choices.slow],
            ownsRemoteCommands: false, prepareAudioSession: { .completed([]) })
        defer { shared.cleanup() }
        XCTAssertEqual(shared.viewingPlaybackContext, .single,
                       "The initial context is not evidence that a shared model is a single-player destination")
        XCTAssertFalse(shared.usesSingleStreamRanking)
        XCTAssertEqual(shared.activeSession?.id, choices.slow.id)

        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let rightSlow = rankingSession(for: right, provider: "Score808", host: "slow-ranking.example.invalid")
        let rightFast = rankingSession(for: right, provider: "AS1", host: "fast-ranking.example.invalid")
        owner.openMulti(slots: [.init(event: left, sessions: [choices.fast, choices.slow]),
                                .init(event: right, sessions: [rightFast, rightSlow])])

        XCTAssertTrue(owner.isTwo)
        XCTAssertEqual(owner.panes.map { $0.model.activeSession?.id }, [choices.slow.id, rightSlow.id])
        for model in owner.panes.map(\.model) {
            XCTAssertFalse(model.usesSingleStreamRanking)
            XCTAssertEqual(model.viewingPlaybackContext, .watchTwo(engine: .native))
            XCTAssertFalse(model.configureSingleStreamRanking())
            XCTAssertNil(model.loadTask)
            XCTAssertFalse(model.didStartPlayback)
        }
    }

    func testRetainedManuallySelectedPausedSingleOwnerCannotBeRerankedOrRestarted() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let match = event("retained-ranking", date: Int64(Date().timeIntervalSince1970) - 60), factory = ModelFactory()
        let originalMatches = MatchListViewModel.shared.matches
        MatchListViewModel.shared.matches = [match]
        defer { MatchListViewModel.shared.matches = originalMatches }
        let choices = seedSlowLegacyAndFastSingleHistory(for: match)
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.open(event: match, sessions: [choices.fast, choices.slow])
        let original = try XCTUnwrap(owner.primary)
        let model = original.model
        let manualIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == choices.slow.id })

        // Exercise the real manual-selection bookkeeping synchronously. Its
        // queued native preparation is cancelled before any task can execute.
        model.selectSourceManually(at: manualIndex)
        model.loadTask?.cancel()
        model.loadTask = nil
        // Retire the cancelled preparation before mounting the stand-in for its finished item.
        model.transition(to: .idle)
        let item = installPausedLocalItem(on: model)
        let attempt = model.loadRequestID
        let sourceOrder = model.sessions.map(\.id)
        owner.minimize()

        XCTAssertFalse(model.configureSingleStreamRanking())
        owner.open(event: match, sessions: [choices.fast, choices.slow])

        XCTAssertTrue(owner.primary?.model === model)
        XCTAssertEqual(owner.primaryID, original.id)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertEqual(model.activeSession?.id, choices.slow.id)
        XCTAssertEqual(model.sessions.map(\.id), sourceOrder)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertNil(model.loadTask)
    }

    func testSingleRankingOptInRejectsAlreadyPreparingMountedRetiredOrWatchTwoOwners() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let match = event("ranking-owner-guards")
        let choices = seedSlowLegacyAndFastSingleHistory(for: match)
        for state in ["preparing", "mounted", "retired", "watch-two"] {
            let model = LivePlayerViewModel(event: match, providedSessions: [choices.fast, choices.slow],
                ownsRemoteCommands: false, prepareAudioSession: { .completed([]) })
            defer { model.cleanup() }
            switch state {
            case "preparing": model.sourceAttemptStartedAt = Date()
            case "mounted": model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            case "retired": model.cleanup()
            default: XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .native)))
            }
            let attempt = model.loadRequestID, source = model.activeSession?.id
            XCTAssertFalse(model.configureSingleStreamRanking(), state)
            XCTAssertFalse(model.usesSingleStreamRanking, state)
            XCTAssertEqual(model.activeSession?.id, source, state)
            XCTAssertEqual(model.loadRequestID, attempt, state)
            XCTAssertNil(model.loadTask, state)
        }
    }

    func testRuntimeSingleFailoverExcludesCurrentAndExhaustedChoicesButWatchTwoKeepsLegacyRanking() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let match = event("ranking-failover", date: Int64(Date().timeIntervalSince1970) - 60)
        let originalMatches = MatchListViewModel.shared.matches
        MatchListViewModel.shared.matches = [match]
        defer { MatchListViewModel.shared.matches = originalMatches }
        let choices = seedSlowLegacyAndFastSingleHistory(for: match)
        let exhausted = rankingSession(for: match, provider: "CS1", host: "exhausted-ranking.example.invalid")
        let spare = rankingSession(for: match, provider: "StreamEx", host: "spare-ranking.example.invalid")
        LiveSourceHealthStore.recordSuccess(for: exhausted, startupLatencyMs: 900)
        LiveSourceHealthStore.recordSuccess(for: spare, startupLatencyMs: 7_000)
        let model = LivePlayerViewModel(event: match,
            providedSessions: [choices.slow, choices.fast, exhausted, spare],
            ownsRemoteCommands: false, prepareAudioSession: { .completed([]) },
            currentMatchProviders: { ["communitysports", "plaviosports", "streamex", "score808"] })
        defer { model.cleanup() }
        XCTAssertTrue(model.configureSingleStreamRanking())
        XCTAssertEqual(model.activeSession?.id, exhausted.id)

        // Terminal explicit rejection owns the exhausted source. Cancel the
        // resulting queued preparation before it can touch a media endpoint.
        model.handleSourceStartupFailure(exhausted.legacySource,
            reason: "Provider reports this broadcast is unavailable", expectedRequestID: model.loadRequestID)
        model.loadTask?.cancel()
        model.loadTask = nil
        XCTAssertTrue(model.failedSourceIDs.contains(exhausted.id))
        XCTAssertEqual(model.activeSession?.id, choices.fast.id)
        let current = try XCTUnwrap(model.activeSource)
        XCTAssertEqual(model.nextPlayableSource(after: current)?.id, spare.id,
                       "The failed faster source and current source cannot be reconsidered")

        model.setViewingPlaybackContext(.watchTwo(engine: .native))
        XCTAssertEqual(model.nextPlayableSource(after: current)?.id, choices.slow.id,
                       "A promoted model must use legacy ranking while in Watch Two")
        XCTAssertTrue(model.failedSourceIDs.contains(exhausted.id))
        XCTAssertNil(model.loadTask)
    }

    func testOptionalSourceCheckResolvesSourceFreeFixtureWithoutPrimaryPreflight() async throws {
        let factory = ModelFactory(), fixture = sourceCheckFixture("official-fixture")
        var requests: [StreamPlaybackRequest] = [], admissions = 0, primaryLookups = 0
        let cs = StreamSession(matchID: fixture.id, title: "CS1",
            playableURL: URL(string: "https://example.invalid/cs.m3u8")!,
            streamType: .hls, providerName: "CS1", requiredHeaders: [:])
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { requests.append($0); return self.outcome(for: fixture, sessions: [cs]) },
            catalogEvent: { _ in primaryLookups += 1; return nil }, cancelPlayback: { _ in })
        defer { owner.stop() }

        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] }) { current, phase in
            admissions += 1
            XCTAssertEqual(phase, admissions == 1 ? .offer : .completion)
            XCTAssertEqual(current.id, fixture.id)
            return fixture
        })
        XCTAssertEqual(owner.resolutionMessage, "Opening broadcast…")
        await waitForSourceCheck { owner.primary != nil }

        XCTAssertEqual(primaryLookups, 0, "Independent CS discovery must not depend on a primary listing")
        XCTAssertEqual(admissions, 2, "Revalidate the current fixture and source opt-in after lookup")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.matchID, fixture.id)
        XCTAssertEqual(request.homeTeam, "Zimbabwe")
        XCTAssertEqual(request.awayTeam, "Afghanistan")
        XCTAssertEqual(request.kickoffDate, fixture.kickoffDate)
        XCTAssertTrue(request.preferredEvent?.sources?.isEmpty == true)
        XCTAssertEqual(owner.primary?.model.sessions.map(\.id), [cs.id])
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.resolutionError)
    }

    func testOptionalSourceCheckRejectsMissingCurrentFixtureBeforeLookup() async throws {
        let factory = ModelFactory(), fixture = sourceCheckFixture("missing")
        var resolves = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in resolves += 1; return self.outcome(for: fixture, sessions: []) },
            cancelPlayback: { _ in })
        defer { owner.stop() }
        let retained = event("retained")
        owner.open(event: retained, sessions: [session(for: retained)])
        let model = try XCTUnwrap(owner.primary?.model)
        let item = installPausedLocalItem(on: model)
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] }) { _, _ in nil })
        await waitForSourceCheck { owner.resolutionError != nil }
        XCTAssertEqual(resolves, 0)
        XCTAssertTrue(owner.primary?.model === model)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertFalse(model.userWantsPlayback)
    }

    func testOptionalSourceCheckFailureOrEmptyResultPreservesPausedOwner() async throws {
        for failed in [false, true] {
            let factory = ModelFactory(), fixture = sourceCheckFixture("unavailable")
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                resolvePlayback: { _ in self.outcome(for: fixture, sessions: [], failed: failed) },
                cancelPlayback: { _ in })
            defer { owner.stop() }
            let retained = event("retained")
            owner.open(event: retained, sessions: [session(for: retained)])
            let model = try XCTUnwrap(owner.primary?.model)
            let item = installPausedLocalItem(on: model), attempt = model.loadRequestID
            let source = model.activeSession?.id
            owner.minimize()
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] }) { _, _ in fixture })
            await waitForSourceCheck { owner.resolutionError != nil }
            XCTAssertTrue(owner.primary?.model === model)
            XCTAssertTrue(model.player?.currentItem === item)
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertEqual(model.activeSession?.id, source)
            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertFalse(owner.expanded)
            XCTAssertEqual(factory.models.count, 1)
        }
    }

    func testOptionalSourceCheckRejectsDuplicateAndCannotCommitAfterCancellation() async throws {
        for stop in [false, true] {
            let factory = ModelFactory(), gate = ResolutionGate(), fixture = sourceCheckFixture("cancelled")
            let result = outcome(for: fixture, sessions: [session(for: fixture)])
            var cancellations = 0
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                resolvePlayback: { await gate.resolve($0) }, cancelPlayback: { _ in cancellations += 1 })
            defer { gate.completeAll(result); owner.stop() }
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] }) { _, _ in fixture })
            XCTAssertFalse(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] }) { _, _ in fixture })
            await waitForSourceCheck { gate.requests.count == 1 }
            if stop { owner.stop() } else { owner.cancelOptionalSourceLookup() }
            gate.complete(result)
            await waitForSourceCheck { gate.finishedResolutions == 1 && cancellations == 1 }
            XCTAssertTrue(owner.panes.isEmpty)
            XCTAssertTrue(factory.models.isEmpty)
            XCTAssertNil(owner.resolutionMessage)
            XCTAssertNil(owner.resolutionError)
        }
    }

    func testOptionalSourceCheckRevalidatesMissingConflictingOrRescheduledFixtureAtCommit() async throws {
        for change in ["missing", "conflict", "rescheduled"] {
            let factory = ModelFactory(), gate = ResolutionGate(), fixture = sourceCheckFixture("changed")
            let result = outcome(for: fixture, sessions: [session(for: fixture)])
            var admission = 0
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                resolvePlayback: { await gate.resolve($0) }, cancelPlayback: { _ in })
            defer { gate.completeAll(result); owner.stop() }
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] }) { _, _ in
                admission += 1
                if admission == 1 { return fixture }
                if change == "missing" { return nil }
                return self.sourceCheckFixture(fixture.id,
                    date: change == "rescheduled" ? 1_800_003_600 : 1_800_000_000,
                    conflict: change == "conflict")
            })
            await waitForSourceCheck { gate.requests.count == 1 }
            gate.complete(result)
            await waitForSourceCheck { owner.resolutionError != nil }
            XCTAssertTrue(owner.panes.isEmpty)
            XCTAssertTrue(factory.models.isEmpty)
            XCTAssertEqual(admission, 2)
        }
    }

    func testCancellingOptionalSourceCheckWithoutLookupDoesNotTouchRetainedPlayer() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory), fixture = event("retained")
        defer { owner.stop() }
        owner.open(event: fixture, sessions: [session(for: fixture)])
        let model = try XCTUnwrap(owner.primary?.model)
        let item = installPausedLocalItem(on: model), attempt = model.loadRequestID
        owner.cancelOptionalSourceLookup()
        XCTAssertTrue(owner.primary?.model === model)
        XCTAssertTrue(model.player?.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.isPlaybackSessionRetired)
    }

    func testIncrementalOptionalWatchMountsFirstChoiceBeforeSlowCompletionAndPreservesPausedOwner() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate(), fixture = sourceCheckFixture("incremental-optional")
        let first = session(for: fixture)
        let second = StreamSession(matchID: fixture.id, playableURL: URL(string: "https://example.invalid/second-choice.m3u8")!,
            streamType: .hls, providerName: "CS2")
        var phases: [OptionalSourceLookupPolicy.Phase] = []
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in XCTFail("Incremental Watch must use the supplied discovery lane"); return self.outcome(for: fixture, sessions: []) },
            cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: fixture, sessions: [])); owner.stop() }
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] },
            discover: { await gate.resolve($0, publish: $1) }) { event, phase in
                phases.append(phase)
                return event
            })
        XCTAssertEqual(owner.resolutionMessage, "Opening broadcast…")
        XCTAssertFalse(owner.hasMountedOptionalSourceLookup(for: fixture))
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?([first])
        let pane = try XCTUnwrap(owner.primary)
        XCTAssertNotNil(gate.finish, "The first source must mount while the slow final outcome is still gated")
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertEqual(phases, [.offer, .completion])
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertTrue(pane.model.isCheckingAdditionalSources)
        XCTAssertTrue(owner.hasMountedOptionalSourceLookup(for: fixture))
        XCTAssertFalse(owner.hasMountedOptionalSourceLookup(for: sourceCheckFixture("unrelated")))
        let item = installPausedLocalItem(on: pane.model), attempt = pane.model.loadRequestID
        pane.model.showSourceSelector = true
        owner.minimize()
        owner.cancelOptionalSourceLookup()
        XCTAssertTrue(pane.model.isCheckingAdditionalSources,
            "Browsing disappearance cannot cancel scene-owned alternatives after the first source mounts")
        await gate.publish?([first, second, second])
        XCTAssertTrue(owner.primary?.model === pane.model)
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertEqual(pane.model.loadRequestID, attempt)
        XCTAssertEqual(pane.model.activeSession?.id, first.id)
        XCTAssertEqual(pane.model.sessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(pane.model.playbackState, .paused(.native))
        XCTAssertFalse(pane.model.userWantsPlayback)
        XCTAssertTrue(pane.model.showSourceSelector)
        XCTAssertFalse(owner.expanded)
        XCTAssertEqual(phases, [.offer, .completion, .completion])
        gate.complete(outcome(for: fixture, sessions: [first, second]))
        await waitForSourceCheck { !pane.model.isCheckingAdditionalSources }
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertNil(owner.resolutionError)
        XCTAssertFalse(owner.hasMountedOptionalSourceLookup(for: fixture), "A retained pane alone is not an active lookup owner")
    }

    func testIncrementalOptionalWatchLateFailureOrEmptyFinalCannotEraseMountedSource() async throws {
        for failed in [false, true] {
            let factory = ModelFactory(), gate = SingleDiscoveryGate(), fixture = sourceCheckFixture("late-optional-\(failed)")
            let first = session(for: fixture)
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) }, cancelPlayback: { _ in })
            defer { gate.complete(outcome(for: fixture, sessions: [])); owner.stop() }
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] },
                discover: { await gate.resolve($0, publish: $1) }, currentEvent: { event, _ in event }))
            await waitForSourceCheck { gate.publish != nil }
            await gate.publish?([first])
            let pane = try XCTUnwrap(owner.primary)
            let item = installPausedLocalItem(on: pane.model), attempt = pane.model.loadRequestID
            gate.complete(outcome(for: fixture, sessions: [], failed: failed))
            await waitForSourceCheck { !pane.model.isCheckingAdditionalSources }
            XCTAssertTrue(owner.primary?.model === pane.model)
            XCTAssertTrue(pane.model.player?.currentItem === item)
            XCTAssertEqual(pane.model.loadRequestID, attempt)
            XCTAssertEqual(pane.model.sessions.map(\.id), [first.id])
            XCTAssertFalse(pane.model.userWantsPlayback)
            XCTAssertNil(owner.resolutionError)
            XCTAssertEqual(factory.models.count, 1)
        }
    }

    func testIncrementalOptionalWatchCancellationAndChangedAdmissionCannotMountLateSources() async throws {
        for change in ["cancel", "stop", "revoked", "terminal", "rescheduled"] {
            let factory = ModelFactory(), gate = SingleDiscoveryGate(), fixture = sourceCheckFixture("optional-veto-\(change)")
            let choice = session(for: fixture)
            var changed = false
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) }, cancelPlayback: { _ in })
            defer { gate.complete(outcome(for: fixture, sessions: [])); owner.stop() }
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] },
                discover: { await gate.resolve($0, publish: $1) }) { event, phase in
                    guard changed, phase == .completion else { return event }
                    if change == "revoked" { return nil }
                    if change == "rescheduled" { return self.sourceCheckFixture(event.id, date: 1_800_003_600) }
                    if change == "terminal" {
                        return EventReference(id: event.id, title: event.title, category: event.category, date: event.date,
                            poster: nil, popular: false, teams: event.teams, sources: [],
                            cricketFixture: .init(fixtureID: "terminal", competitionID: "icc", competitionName: "ICC",
                                format: .odi, status: .finished, observedAt: Date(), verified: true))
                    }
                    return event
                })
            await waitForSourceCheck { gate.publish != nil }
            changed = true
            if change == "cancel" { owner.cancelOptionalSourceLookup() }
            if change == "stop" { owner.stop() }
            await gate.publish?([choice])
            gate.complete(outcome(for: fixture, sessions: [choice]))
            await waitForSourceCheck { owner.resolutionMessage == nil }
            XCTAssertTrue(factory.models.isEmpty, change)
            XCTAssertFalse(owner.isActive, change)
        }
    }

    func testIncrementalOptionalWatchRechecksAdmissionBeforeAppendingAndStopFencesMountedLateCallback() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate(), fixture = sourceCheckFixture("optional-mounted-veto")
        let first = session(for: fixture)
        let second = StreamSession(matchID: fixture.id, playableURL: URL(string: "https://example.invalid/after-veto.m3u8")!,
            streamType: .hls, providerName: "CS2")
        var enabled = true, completions = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: fixture, sessions: [])); owner.stop() }
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex", "communitysports"] },
            discover: { await gate.resolve($0, publish: $1) }) { event, phase in
                if phase == .completion { completions += 1 }
                return enabled ? event : nil
            })
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?([first])
        let pane = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: pane.model)
        enabled = false
        await gate.publish?([first, second])
        XCTAssertEqual(completions, 2)
        XCTAssertEqual(pane.model.sessions.map(\.id), [first.id])
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertNil(owner.resolutionError)
        owner.stop()
        enabled = true
        await gate.publish?([first, second])
        gate.complete(outcome(for: fixture, sessions: [first, second]))
        await waitForSourceCheck { owner.resolutionMessage == nil }
        XCTAssertFalse(owner.isActive)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertFalse(pane.model.isCheckingAdditionalSources)
    }

    func testIncrementalOptionalWatchFiltersRevokedFamilyAtCommitWhileEnabledSiblingCanPlay() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate(), fixture = sourceCheckFixture("optional-family-revoked")
        var enabled: Set<String> = ["streamex", "communitysports"]
        var revokeOnCompletion = true
        let cs = StreamSession(matchID: fixture.id, playableURL: URL(string: "https://example.invalid/revoked-cs.m3u8")!,
            streamType: .hls, providerName: "CS1")
        let csLater = StreamSession(matchID: fixture.id, playableURL: URL(string: "https://example.invalid/revoked-cs-later.m3u8")!,
            streamType: .hls, providerName: "CS2")
        let ordinary = session(for: fixture)
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: fixture, sessions: [])); owner.stop() }
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { enabled },
            discover: { await gate.resolve($0, publish: $1) }) { event, phase in
                if phase == .offer { XCTAssertTrue(enabled.contains("communitysports")) }
                if phase == .completion, revokeOnCompletion {
                    await Task.yield()
                    enabled.remove("communitysports")
                    revokeOnCompletion = false
                }
                return event
            })
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?([cs])
        XCTAssertTrue(factory.models.isEmpty, "An opt-in revoked during the async current-event check must veto that family")
        XCTAssertEqual(enabled, ["streamex"])
        await gate.publish?([cs, ordinary])
        let pane = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: pane.model), attempt = pane.model.loadRequestID
        XCTAssertEqual(pane.model.sessions.map(\.id), [ordinary.id])
        await gate.publish?([ordinary, csLater])
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertEqual(pane.model.loadRequestID, attempt)
        XCTAssertEqual(pane.model.sessions.map(\.id), [ordinary.id])
        gate.complete(outcome(for: fixture, sessions: [cs, ordinary, csLater]))
        await waitForSourceCheck { !pane.model.isCheckingAdditionalSources }
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertEqual(pane.model.activeSession?.id, ordinary.id)
        XCTAssertFalse(pane.model.userWantsPlayback)
        XCTAssertNil(owner.resolutionError)
    }

    func testIncrementalOptionalWatchAdmitsLegacyStreamExDisplayNameWithoutReenablingRevokedAddons() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate(), fixture = sourceCheckFixture("legacy-catalog-display-name")
        let streamEx = StreamSession(matchID: fixture.id,
            playableURL: URL(string: "https://example.invalid/catalog-display-name.m3u8")!, streamType: .hls,
            providerName: "StreamEx #1", requiredHeaders: ["X-Fotty-Nexus-Source": "delta"])
        let revoked = ["CS1", "AS1"].map { label in
            StreamSession(matchID: fixture.id, playableURL: URL(string: "https://example.invalid/\(label).m3u8")!,
                streamType: .hls, providerName: label, requiredHeaders: ["X-Fotty-Nexus-Source": "delta"])
        }
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: fixture, sessions: [])); owner.stop() }
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["streamex"] },
            discover: { await gate.resolve($0, publish: $1) }, currentEvent: { event, _ in event }))
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?(revoked + [streamEx])
        let pane = try XCTUnwrap(owner.primary)
        XCTAssertEqual(pane.model.sessions.map(\.id), [streamEx.id])
        XCTAssertEqual(pane.model.activeSession?.providerName, "StreamEx #1")
        XCTAssertEqual(pane.model.activeSession?.requiredHeaders["X-Fotty-Nexus-Source"], "delta")
        let item = installPausedLocalItem(on: pane.model)
        await gate.publish?(revoked + [streamEx])
        gate.complete(outcome(for: fixture, sessions: revoked + [streamEx]))
        await waitForSourceCheck { !pane.model.isCheckingAdditionalSources }
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertEqual(pane.model.sessions.map(\.id), [streamEx.id])
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertNil(owner.resolutionError)
    }

    func testWatchTwoPreparesCompatibleWebSourceWithoutReplacingPausedRetainedOwner() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("retained-web"), second = event("prepared-compatible-web")
        owner.open(event: first, sessions: [session(for: first, web: true)])
        let retained = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: retained.model)
        let player = retained.model.player, attempt = retained.model.loadRequestID
        let originalSource = retained.model.activeSession?.id
        let nativeChoice = session(for: second), webChoice = session(for: second, web: true)

        owner.openMulti(slots: [.init(event: second, sessions: [nativeChoice, webChoice]),
                               slot(first, web: true)])

        XCTAssertTrue(owner.isTwo)
        XCTAssertTrue(owner.panes[1].model === retained.model)
        XCTAssertEqual(owner.panes.map { $0.model.selectedPlaybackEngine }, [.web, .web])
        XCTAssertEqual(owner.panes[0].model.activeSession?.id, webChoice.id)
        XCTAssertEqual(owner.audioID, retained.id, "The retained original endpoint chooses the pair engine, not slot order")
        XCTAssertTrue(retained.model.player === player)
        XCTAssertTrue(retained.model.player?.currentItem === item)
        XCTAssertEqual(retained.model.loadRequestID, attempt)
        XCTAssertEqual(retained.model.activeSession?.id, originalSource)
        XCTAssertEqual(retained.model.playbackState, .paused(.webEmbed))
        XCTAssertFalse(retained.model.userWantsPlayback)
        XCTAssertFalse(owner.panes[0].model.didStartPlayback)
        XCTAssertNil(owner.panes[0].model.loadTask)
        XCTAssertFalse(owner.panes[0].model.networkPathObserver.isRunning)
        XCTAssertNil(owner.panes[0].model.player)
        XCTAssertNil(owner.resolutionError)
    }

    func testIncompatibleWatchTwoLeavesWorkingSingleSourceAndPauseUntouched() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("working-web"), second = event("native-only")
        owner.open(event: first, sessions: [session(for: first, web: true)])
        let retained = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: retained.model)
        let player = retained.model.player, attempt = retained.model.loadRequestID
        let source = retained.model.activeSession?.id
        owner.minimize()

        owner.openMulti(slots: [slot(first, web: true), slot(second)])

        XCTAssertEqual(owner.panes.map(\.id), [retained.id])
        XCTAssertEqual(owner.primaryID, retained.id)
        XCTAssertEqual(owner.audioID, retained.id)
        XCTAssertFalse(owner.expanded)
        XCTAssertFalse(retained.model.isPlaybackSessionRetired)
        XCTAssertTrue(retained.model.player === player)
        XCTAssertTrue(retained.model.player?.currentItem === item)
        XCTAssertEqual(retained.model.loadRequestID, attempt)
        XCTAssertEqual(retained.model.activeSession?.id, source)
        XCTAssertEqual(retained.model.playbackState, .paused(.webEmbed))
        XCTAssertFalse(retained.model.userWantsPlayback)
        XCTAssertTrue(retained.model.failedSourceIDs.isEmpty)
        XCTAssertEqual(owner.resolutionError,
            "These broadcasts use different players. Choose another source or watch this match on its own.")
        let rejected = try XCTUnwrap(factory.models.last)
        XCTAssertTrue(rejected.isPlaybackSessionRetired)
        XCTAssertFalse(rejected.didStartPlayback)
        XCTAssertNil(rejected.loadTask)
    }

    func testPreparedWatchTwoPairsAdmitOnlyMatchingOriginalEngines() {
        for web in [false, true] {
            let factory = ModelFactory(), owner = coordinator(factory: factory)
            defer { owner.stop() }
            owner.openMulti(slots: [slot(event("first"), web: web), slot(event("second"), web: web)])
            XCTAssertEqual(owner.panes.count, 2)
            XCTAssertTrue(owner.panes.allSatisfy { $0.model.selectedPlaybackEngine == (web ? .web : .native) })
            XCTAssertTrue(owner.panes.allSatisfy { !$0.model.didStartPlayback && $0.model.loadTask == nil })
            XCTAssertNil(owner.resolutionError)
        }
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("native")), slot(event("web"), web: true)])
        XCTAssertTrue(owner.panes.isEmpty)
        XCTAssertTrue(factory.models.allSatisfy { $0.isPlaybackSessionRetired && !$0.didStartPlayback })
        XCTAssertNotNil(owner.resolutionError)
    }

    func testIncompatibleReplacementPreservesBothPausedOwnersAndDisplayRoles() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("survivor-web"), web: true), slot(event("target-web"), web: true)])
        let survivor = owner.panes[0], target = owner.panes[1]
        let item = installPausedLocalItem(on: survivor.model)
        installPausedLocalItem(on: target.model)
        let ids = owner.panes.map(\.id), attempts = owner.panes.map { $0.model.loadRequestID }
        let sources = owner.panes.map { $0.model.activeSession?.id }
        owner.swap()
        let replacement = event("native-only-replacement")

        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: survivor.id,
            event: replacement, sessions: [session(for: replacement)]))

        XCTAssertEqual(owner.panes.map(\.id), ids)
        XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
        XCTAssertEqual(owner.panes.map { $0.model.activeSession?.id }, sources)
        XCTAssertEqual(owner.primaryID, survivor.id)
        XCTAssertEqual(owner.audioID, survivor.id)
        XCTAssertTrue(owner.swapped)
        XCTAssertTrue(survivor.model.player?.currentItem === item)
        XCTAssertTrue(owner.panes.allSatisfy { !$0.model.isPlaybackSessionRetired && !$0.model.userWantsPlayback })
        XCTAssertTrue(try XCTUnwrap(factory.models.last).isPlaybackSessionRetired)
        XCTAssertNotNil(owner.resolutionError)
    }

    func testCompatibleReplacementSelectsExistingWebEndpointBeforeMount() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("survivor"), web: true), slot(event("target"), web: true)])
        let survivor = owner.panes[0], target = owner.panes[1]
        let item = installPausedLocalItem(on: survivor.model), attempt = survivor.model.loadRequestID
        let replacement = event("replacement"), webChoice = session(for: replacement, web: true)

        XCTAssertTrue(owner.replacePreparedPane(target.id, preserving: survivor.id,
            event: replacement, sessions: [session(for: replacement), webChoice]))

        XCTAssertTrue(owner.panes[0].model === survivor.model)
        XCTAssertEqual(owner.panes[1].model.activeSession?.id, webChoice.id)
        XCTAssertEqual(owner.panes[1].model.selectedPlaybackEngine, .web)
        XCTAssertFalse(owner.panes[1].model.didStartPlayback)
        XCTAssertNil(owner.panes[1].model.loadTask)
        XCTAssertTrue(survivor.model.player?.currentItem === item)
        XCTAssertEqual(survivor.model.loadRequestID, attempt)
        XCTAssertFalse(survivor.model.userWantsPlayback)
        XCTAssertTrue(target.model.isPlaybackSessionRetired)
    }

    func testForcedWebFallbackCannotBeReadmittedAsNativePairOrDisplaceEitherOwner() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("forced-web-native-origin"), second = event("native-sibling")
        owner.openMulti(slots: [slot(first), slot(second)])
        let survivor = owner.panes[0], target = owner.panes[1]
        let sourceID = try XCTUnwrap(survivor.model.activeSource?.id)
        // Seed a retained fallback state from before the compatibility gate.
        // The original endpoint is native, but its actual surface is WebKit.
        survivor.model.forceWebEmbedSourceIDs.insert(sourceID)
        let firstItem = installPausedLocalItem(on: survivor.model)
        let secondItem = installPausedLocalItem(on: target.model)
        XCTAssertEqual(survivor.model.selectedPlaybackEngine, .native)
        XCTAssertEqual(survivor.model.activePlaybackEngine, .web)
        let ids = owner.panes.map(\.id), attempts = owner.panes.map { $0.model.loadRequestID }
        let sources = owner.panes.map { $0.model.activeSession?.id }
        owner.swap()
        let replacement = event("native-replacement")

        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: survivor.id,
            event: replacement, sessions: [session(for: replacement)]))
        owner.openMulti(slots: [slot(first), slot(second)])

        XCTAssertEqual(owner.panes.map(\.id), ids)
        XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
        XCTAssertEqual(owner.panes.map { $0.model.activeSession?.id }, sources)
        XCTAssertTrue(owner.swapped)
        XCTAssertEqual(owner.primaryID, survivor.id)
        XCTAssertEqual(owner.audioID, survivor.id)
        XCTAssertTrue(survivor.model.player?.currentItem === firstItem)
        XCTAssertTrue(target.model.player?.currentItem === secondItem)
        XCTAssertTrue(owner.panes.allSatisfy { !$0.model.isPlaybackSessionRetired && !$0.model.userWantsPlayback })
        XCTAssertTrue(survivor.model.forceWebEmbedSourceIDs.contains(sourceID))
        XCTAssertTrue(survivor.model.failedSourceIDs.isEmpty)
        XCTAssertNotNil(owner.resolutionError)
    }

    func testAdoptedOriginalWebRouteCannotChangeEngineWhilePiPOrFullscreenOwnsIt() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("adopted-web"), second = event("other-web")
        let web = session(for: first, web: true)
        owner.open(event: first, sessions: [web])
        let retained = try XCTUnwrap(owner.primary)
        retained.model.nativeHandoffSession = StreamSession(id: web.id, matchID: first.id,
            playableURL: URL(string: "https://example.invalid/adopted.m3u8")!,
            streamType: .hls, providerName: web.providerName)
        let item = installPausedLocalItem(on: retained.model)
        let attempt = retained.model.loadRequestID
        XCTAssertEqual(retained.model.selectedPlaybackEngine, .web)
        XCTAssertEqual(retained.model.activePlaybackEngine, .native)
        retained.model.isPictureInPictureActive = true
        owner.openMulti(slots: [slot(first, web: true), slot(second, web: true)])
        XCTAssertEqual(owner.panes.map(\.id), [retained.id])
        XCTAssertTrue(retained.model.isPictureInPictureActive)
        retained.model.isPictureInPictureActive = false
        retained.model.isVideoReadyForDisplay = true
        retained.model.beginNativeFullscreen()
        XCTAssertNotNil(retained.model.nativeFullscreen)
        owner.openMulti(slots: [slot(first, web: true), slot(second, web: true)])
        XCTAssertEqual(owner.panes.map(\.id), [retained.id])
        XCTAssertTrue(retained.model.player?.currentItem === item)
        XCTAssertEqual(retained.model.loadRequestID, attempt)
        XCTAssertEqual(retained.model.activePlaybackEngine, .native)
        XCTAssertFalse(retained.model.userWantsPlayback)
        XCTAssertNotNil(owner.resolutionError)
    }

    func testAdoptedNativeReturnsOnlyToItsOriginalWebRouteAndKeepsPauseForWatchTwo() async throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("adopted-original"), second = event("compatible-web")
        let originalWeb = session(for: first, web: true)
        owner.open(event: first, sessions: [originalWeb])
        let retained = try XCTUnwrap(owner.primary)
        retained.model.nativeHandoffSession = StreamSession(id: originalWeb.id, matchID: first.id,
            playableURL: URL(string: "https://example.invalid/adopted-original.m3u8")!,
            streamType: .hls, providerName: originalWeb.providerName)
        installPausedLocalItem(on: retained.model)
        retained.model.didApplyLandscape = true
        let previousAttempt = retained.model.loadRequestID

        owner.openMulti(slots: [slot(first, web: true), slot(second, web: true)])

        XCTAssertTrue(owner.isTwo)
        XCTAssertTrue(owner.panes[0].model === retained.model)
        XCTAssertEqual(retained.model.activeSession?.id, originalWeb.id)
        XCTAssertEqual(retained.model.activeSession?.playableURL, originalWeb.playableURL)
        XCTAssertEqual(retained.model.activePlaybackEngine, .web)
        XCTAssertNil(retained.model.nativeHandoffSession)
        XCTAssertFalse(retained.model.userWantsPlayback)
        XCTAssertEqual(retained.model.webPlaybackCommand?.shouldPlay, false)
        XCTAssertNotEqual(retained.model.loadRequestID, previousAttempt,
            "Only the deliberate engine transition may create a new attempt")
        if let loading = retained.model.loadTask { await loading.value }
        XCTAssertNil(retained.model.player)
        XCTAssertFalse(retained.model.userWantsPlayback)
        XCTAssertFalse(owner.panes[1].model.didStartPlayback)
        XCTAssertNil(owner.panes[1].model.loadTask)
        XCTAssertNil(owner.resolutionError)
    }

    func testDiagnosticRouteTracksSingleTwoReplacementAndKeepWithoutChangingAttempts() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("diagnostic-first"), second = event("diagnostic-second"), third = event("diagnostic-third")
        owner.open(event: first, sessions: [session(for: first)])
        let retained = try XCTUnwrap(owner.primary)
        let attempt = retained.model.loadRequestID
        XCTAssertEqual(retained.model.playbackQualityDetails()["route"], "single")
        owner.openMulti(slots: [slot(first), slot(second)])
        XCTAssertTrue(owner.panes.allSatisfy { $0.model.playbackQualityDetails()["route"] == "watch_two" })
        let replacementID = try XCTUnwrap(owner.panes.first(where: { $0.id != retained.id })?.id)
        XCTAssertTrue(owner.replacePreparedPane(replacementID, preserving: retained.id,
                                                event: third, sessions: [session(for: third)]))
        XCTAssertTrue(owner.panes.allSatisfy { $0.model.playbackQualityDetails()["route"] == "watch_two" })
        owner.keepOnly(retained.id)
        XCTAssertEqual(retained.model.playbackQualityDetails()["route"], "single")
        XCTAssertEqual(retained.model.loadRequestID, attempt)
        XCTAssertTrue(owner.primary?.model === retained.model)
    }

    func testRetainedAudioOwnerIsNotRevokedWhileAddingSecondPane() async throws {
        var activationCount = 0
        var models: [LivePlayerViewModel] = []
        let owner = ViewingSessionCoordinator(makeModel: { event, sessions in
            let model = LivePlayerViewModel(event: event, providedSessions: sessions,
                ownsRemoteCommands: false, prepareAudioSession: { activationCount += 1; return .completed([]) },
                configureAudioSession: { .completed([]) })
            models.append(model)
            return model
        })
        defer { owner.stop() }
        let first = event("retained-audio"), second = event("new-muted-pane")
        owner.open(event: first, sessions: [session(for: first)])
        let retained = try XCTUnwrap(owner.primary)
        let selected = try XCTUnwrap(retained.model.activeSession)
        retained.model.nativeHandoffSession = StreamSession(id: selected.id, matchID: selected.matchID,
            playableURL: URL(string: "https://example.invalid/adopted.m3u8")!, streamType: .hls,
            providerName: "StreamEx", requiredHeaders: [:])
        retained.model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        retained.model.transition(to: .playing(.native), phase: "Playing")
        let item = retained.model.player?.currentItem, attempt = retained.model.loadRequestID
        owner.openMulti(slots: [slot(first), slot(second)])
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(activationCount, 0, "An unchanged audible owner must not acquire audio again")
        XCTAssertNil(retained.model.nativeHandoffAudioClaimTask)
        XCTAssertTrue(retained.model.isViewingAudioEnabled)
        XCTAssertTrue(retained.model.player?.currentItem === item)
        XCTAssertEqual(retained.model.loadRequestID, attempt)
        XCTAssertEqual(models.count, 2)
        XCTAssertFalse(try XCTUnwrap(owner.panes.first { $0.id != retained.id }).model.isViewingAudioEnabled)
    }

    func testWebFocusWaitsForOldDecodedOwnerMuteWithoutChangingEitherPausedAttempt() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("web-mute-old"), web: true), slot(event("web-mute-new"), web: true)])
        let old = owner.panes[0], target = owner.panes[1]
        let oldItem = installPausedLocalItem(on: old.model), targetItem = installPausedLocalItem(on: target.model)
        let attempts = owner.panes.map { $0.model.loadRequestID }
        gate.requiredOwners = [old.model.remoteCommandOwnerID]

        owner.listen(to: target.id)

        let transfer = try XCTUnwrap(owner.audioTransferTask), ticket = try XCTUnwrap(gate.tickets.last)
        await waitFor { ticket.pendingCount == 1 }
        XCTAssertFalse(old.model.isViewingAudioEnabled)
        XCTAssertFalse(target.model.isViewingAudioEnabled, "SwiftUI must not unmute the target before the old WK owner ACK")
        XCTAssertFalse(target.model.ownsRemoteCommands)
        ticket.complete(true)
        await transfer.value

        XCTAssertTrue(target.model.isViewingAudioEnabled)
        XCTAssertTrue(target.model.ownsRemoteCommands)
        XCTAssertFalse(old.model.isViewingAudioEnabled)
        XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
        XCTAssertTrue(old.model.player?.currentItem === oldItem)
        XCTAssertTrue(target.model.player?.currentItem === targetItem)
        XCTAssertEqual(old.model.playbackState, .paused(.webEmbed))
        XCTAssertEqual(target.model.playbackState, .paused(.webEmbed))
        XCTAssertFalse(old.model.userWantsPlayback)
        XCTAssertFalse(target.model.userWantsPlayback)
    }

    func testFailedWebMuteAckLeavesBothMutedAndSameAudioActionCanRetry() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("web-failed-old"), web: true), slot(event("web-failed-target"), web: true)])
        let old = owner.panes[0], target = owner.panes[1]
        gate.requiredOwners = [old.model.remoteCommandOwnerID]
        owner.listen(to: target.id)
        let first = try XCTUnwrap(owner.audioTransferTask), failed = try XCTUnwrap(gate.tickets.last)
        await waitFor { failed.pendingCount == 1 }
        failed.complete(false)
        await first.value
        XCTAssertFalse(old.model.isViewingAudioEnabled)
        XCTAssertFalse(target.model.isViewingAudioEnabled)
        XCTAssertFalse(target.model.ownsRemoteCommands)
        XCTAssertTrue(owner.resolutionError?.contains("Tap Audio") == true)

        owner.listen(to: target.id)
        let retry = try XCTUnwrap(owner.audioTransferTask), replacement = try XCTUnwrap(gate.tickets.last)
        XCTAssertFalse(replacement === failed)
        await waitFor { replacement.pendingCount == 1 }
        replacement.complete(true)
        await retry.value
        XCTAssertTrue(target.model.isViewingAudioEnabled)
        XCTAssertNil(owner.resolutionError)
    }

    func testWebFocusReversalWaitsForEveryOldMuteAndNeverPromotesSupersededTarget() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("web-reversal-left"), web: true), slot(event("web-reversal-right"), web: true)])
        let left = owner.panes[0], right = owner.panes[1]
        gate.requiredOwners = [left.model.remoteCommandOwnerID, right.model.remoteCommandOwnerID]
        owner.listen(to: right.id)
        let oldTransfer = try XCTUnwrap(owner.audioTransferTask), leftMute = try XCTUnwrap(gate.tickets.last)
        await waitFor { leftMute.pendingCount == 1 }
        owner.listen(to: left.id)
        let currentTransfer = try XCTUnwrap(owner.audioTransferTask), rightMute = try XCTUnwrap(gate.tickets.last)
        leftMute.complete(true)
        await waitFor { rightMute.pendingCount == 1 }
        XCTAssertFalse(left.model.isViewingAudioEnabled, "A safe left mute alone cannot bypass the right mute")
        XCTAssertFalse(right.model.isViewingAudioEnabled)
        rightMute.complete(true)
        await oldTransfer.value
        await currentTransfer.value
        XCTAssertEqual(owner.audioID, left.id)
        XCTAssertTrue(left.model.isViewingAudioEnabled)
        XCTAssertFalse(right.model.isViewingAudioEnabled)
        XCTAssertFalse(right.model.ownsRemoteCommands)
    }

    func testSingleLateWebRetirementRestoresAudioWithoutReplacingTheNewPlayer() async throws {
        let factory = ModelFactory()
        var oldOwner: UUID?
        var retired = false
        let owner = ViewingSessionCoordinator(captureWebAudioRevocation: { model in
            guard model.remoteCommandOwnerID == oldOwner else { return nil }
            return { retired }
        }, makeModel: factory.make)
        defer { owner.stop() }
        let first = event("single-old-web"), second = event("single-replacement")
        owner.open(event: first, sessions: [session(for: first)])
        let old = try XCTUnwrap(owner.primary)
        oldOwner = old.model.remoteCommandOwnerID
        owner.open(event: second, sessions: [session(for: second)])
        let replacement = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: replacement.model)
        let attempt = replacement.model.loadRequestID
        let transfer = try XCTUnwrap(owner.audioTransferTask)
        await transfer.value
        XCTAssertFalse(replacement.model.isViewingAudioEnabled)
        XCTAssertNotNil(owner.resolutionError)
        retired = true
        old.model.onSingleWebAudioRetired?()
        let retry = try XCTUnwrap(owner.audioTransferTask)
        await retry.value
        XCTAssertTrue(replacement.model.isViewingAudioEnabled)
        XCTAssertTrue(replacement.model.ownsRemoteCommands)
        XCTAssertNil(owner.resolutionError)
        XCTAssertEqual(owner.primary?.id, replacement.id)
        XCTAssertTrue(replacement.model.player?.currentItem === item)
        XCTAssertEqual(replacement.model.loadRequestID, attempt)
        XCTAssertFalse(replacement.model.userWantsPlayback, "Restoring audio must not undo Pause")
        owner.stop()
        old.model.onSingleWebAudioRetired?()
        XCTAssertFalse(owner.isActive)
        XCTAssertNil(owner.audioTransferTask)
    }

    func testRemovedWebPaneStillRequiresItsCapturedRetirementAckBeforeSingleAudio() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("web-retired"), web: true), slot(event("web-survivor"), web: true)])
        let old = owner.panes[0], survivor = owner.panes[1]
        gate.requiredOwners = [old.model.remoteCommandOwnerID]
        owner.keepOnly(survivor.id)
        let transfer = try XCTUnwrap(owner.audioTransferTask), ticket = try XCTUnwrap(gate.tickets.last)
        await waitFor { ticket.pendingCount == 1 }
        XCTAssertTrue(old.model.isPlaybackSessionRetired)
        XCTAssertEqual(owner.panes.map(\.id), [survivor.id])
        XCTAssertFalse(survivor.model.isViewingAudioEnabled)
        ticket.complete(true)
        await transfer.value
        XCTAssertTrue(survivor.model.isViewingAudioEnabled)
        XCTAssertTrue(survivor.model.ownsRemoteCommands)
    }

    func testReplacementCannotUseTheSupersededWebMuteAckToPromoteItsNewTarget() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("web-replace-left"), web: true), slot(event("web-replace-right"), web: true)])
        let survivor = owner.panes[0], oldTarget = owner.panes[1]
        gate.requiredOwners = [survivor.model.remoteCommandOwnerID]
        owner.listen(to: oldTarget.id)
        let oldTransfer = try XCTUnwrap(owner.audioTransferTask), oldMute = try XCTUnwrap(gate.tickets.last)
        await waitFor { oldMute.pendingCount == 1 }
        let replacement = event("web-replace-new")
        XCTAssertTrue(owner.replacePreparedPane(oldTarget.id, preserving: survivor.id,
            event: replacement, sessions: [session(for: replacement, web: true)]))
        let currentTransfer = try XCTUnwrap(owner.audioTransferTask), currentMute = try XCTUnwrap(gate.tickets.last)
        let newTarget = try XCTUnwrap(owner.panes.first { $0.id != survivor.id })
        XCTAssertFalse(currentMute === oldMute)
        oldMute.complete(true)
        await oldTransfer.value
        await waitFor { currentMute.pendingCount == 1 }
        XCTAssertFalse(newTarget.model.isViewingAudioEnabled)
        XCTAssertTrue(oldTarget.model.isPlaybackSessionRetired)
        currentMute.complete(true)
        await currentTransfer.value
        XCTAssertTrue(newTarget.model.isViewingAudioEnabled)
        XCTAssertEqual(owner.audioID, newTarget.id)
    }

    func testStopRejectsLateWebMuteCompletionWithoutReclaimingAudioOrRemoteCommands() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { gate.finishAll() }
        owner.openMulti(slots: [slot(event("web-stop-left"), web: true), slot(event("web-stop-right"), web: true)])
        let old = owner.panes[0], target = owner.panes[1]
        gate.requiredOwners = [old.model.remoteCommandOwnerID]
        owner.listen(to: target.id)
        let transfer = try XCTUnwrap(owner.audioTransferTask), ticket = try XCTUnwrap(gate.tickets.last)
        await waitFor { ticket.pendingCount == 1 }
        owner.stop()
        ticket.complete(true)
        await transfer.value
        XCTAssertFalse(owner.isActive)
        XCTAssertNil(owner.audioID)
        XCTAssertFalse(old.model.isViewingAudioEnabled)
        XCTAssertFalse(target.model.isViewingAudioEnabled)
        XCTAssertFalse(old.model.ownsRemoteCommands)
        XCTAssertFalse(target.model.ownsRemoteCommands)
        XCTAssertNil(owner.resolutionError)
    }

    func testKeepingSameAudibleWebOwnerDoesNotWaitForMutedNewPaneOrReclaimItsAudio() throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { owner.stop(); gate.finishAll() }
        let first = event("web-same-audio"), second = event("web-new-muted")
        owner.open(event: first, sessions: [session(for: first, web: true)])
        let retained = try XCTUnwrap(owner.primary)
        gate.requiredOwners = [retained.model.remoteCommandOwnerID]
        owner.openMulti(slots: [slot(first, web: true), slot(second, web: true)])
        XCTAssertTrue(retained.model.isViewingAudioEnabled)
        XCTAssertFalse(owner.panes[1].model.isViewingAudioEnabled)
        XCTAssertNil(owner.audioTransferTask)
        XCTAssertTrue(gate.tickets.isEmpty, "An unchanged audible owner is not a new Web focus claim")
    }

    func testExplicitWebAudioPreflightFailureLeavesBothOriginalStreamsAndFocusUnchanged() async throws {
        for failedIndex in 0...1 {
            let factory = ModelFactory(), gate = NativePairGate()
            let owner = coordinator(factory: factory, nativePairGate: gate)
            defer { owner.stop(); gate.finishAll() }
            owner.openMulti(slots: [slot(event("atomic-fail-left"), web: true), slot(event("atomic-fail-right"), web: true)])
            let original = owner.panes, attempts = owner.panes.map { $0.model.loadRequestID }
            let states = original.map { $0.model.playbackState }, intents = original.map { $0.model.userWantsPlayback }
            let audioID = owner.audioID
            gate.failedPreparationOwners = [original[failedIndex].model.remoteCommandOwnerID]

            owner.selectAudio(to: original[1].id)
            let transfer = try XCTUnwrap(owner.nativePairTransferTask)
            await transfer.value

            XCTAssertEqual(owner.panes.map(\.id), original.map(\.id))
            XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
            XCTAssertEqual(owner.panes.map { $0.model.playbackState }, states)
            XCTAssertEqual(owner.panes.map { $0.model.userWantsPlayback }, intents)
            XCTAssertEqual(owner.audioID, audioID)
            XCTAssertTrue(original[0].model.isViewingAudioEnabled)
            XCTAssertFalse(original[1].model.isViewingAudioEnabled)
            XCTAssertFalse(gate.events.contains { $0.hasPrefix("retire:") || $0.hasPrefix("start:") })
            XCTAssertTrue(gate.candidates.allSatisfy(\.discarded))
            XCTAssertTrue(owner.resolutionError?.contains("unchanged") == true)
            XCTAssertNil(owner.resolutionMessage)
        }
    }

    func testAtomicWebAudioChangeRetiresBothBeforeAnyNativeStartAndPreservesLogicalLayout() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("atomic-left"), web: true), slot(event("atomic-right"), web: true)])
        owner.swap()
        let original = owner.panes, primaryID = owner.primaryID, oldAudioID = owner.audioID
        let attempts = original.map { $0.model.loadRequestID }, selected = original.map { $0.model.activeSource?.id }
        owner.selectAudio(to: original[1].id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.retirements.count == 2 }
        let left = try XCTUnwrap(gate.retirements[original[0].model.remoteCommandOwnerID])
        let right = try XCTUnwrap(gate.retirements[original[1].model.remoteCommandOwnerID])
        XCTAssertEqual(owner.audioID, oldAudioID, "Focus cannot move during paused preflight or Web retirement")
        XCTAssertFalse(gate.events.contains { $0.hasPrefix("adopt:") || $0.hasPrefix("start:") })
        right.complete(true)
        for _ in 0..<8 { await Task.yield() }
        XCTAssertFalse(gate.events.contains { $0.hasPrefix("adopt:") || $0.hasPrefix("start:") })
        left.complete(true)
        await transfer.value
        if let focus = owner.audioTransferTask { await focus.value }

        XCTAssertEqual(gate.events, ["prepare:atomic-left", "prepare:atomic-right", "retire:atomic-left", "retire:atomic-right",
            "adopt:atomic-left", "adopt:atomic-right", "start:atomic-left", "start:atomic-right", "release:atomic-left", "release:atomic-right"])
        XCTAssertEqual(owner.panes.map(\.id), original.map(\.id))
        XCTAssertEqual(owner.primaryID, primaryID)
        XCTAssertTrue(owner.swapped)
        XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
        XCTAssertEqual(owner.panes.map { $0.model.activeSource?.id }, selected)
        XCTAssertEqual(owner.audioID, original[1].id)
        XCTAssertFalse(original[0].model.isViewingAudioEnabled)
        XCTAssertTrue(original[1].model.isViewingAudioEnabled)
        XCTAssertTrue(owner.panes.allSatisfy { $0.model.activePlaybackEngine == .native })
        XCTAssertTrue(owner.panes.allSatisfy { $0.model.selectedPlaybackEngine == .web })
        XCTAssertEqual(factory.models.count, 2, "An atomic engine upgrade must not replace logical pane models")
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.resolutionError)
    }

    func testAtomicNativeUpgradePreservesPausedPaneIntentWithoutPlayingForFrameProof() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("atomic-playing"), web: true), slot(event("atomic-paused"), web: true)])
        let paused = owner.panes[1]
        installPausedLocalItem(on: paused.model)
        owner.selectAudio(to: paused.id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.retirements.count == 2 }
        gate.retirements.values.forEach { $0.complete(true) }
        await transfer.value
        if let focus = owner.audioTransferTask { await focus.value }
        XCTAssertEqual(paused.model.playbackState, .paused(.native))
        XCTAssertFalse(paused.model.userWantsPlayback)
        XCTAssertTrue(paused.model.isViewingAudioEnabled, "Audio focus itself is not a Play instruction")
        XCTAssertTrue(gate.candidates.first { $0.modelID == paused.model.remoteCommandOwnerID }?.started == true)
        XCTAssertTrue(gate.candidates.allSatisfy { $0.player.rate == 0 }, "This ownership unit never starts an actual decoder")
    }

    func testAtomicPreflightCancellationFromStopKeepReplacementSourceOrPauseRejectsLatePreparation() async throws {
        for action in ["stop", "keep", "replace", "source", "pause", "pause-play", "context"] {
            let factory = ModelFactory(), gate = NativePairGate()
            let owner = coordinator(factory: factory, nativePairGate: gate)
            defer { owner.stop(); gate.finishAll() }
            let first = event("atomic-cancel-left"), second = event("atomic-cancel-right")
            var firstSessions = [session(for: first, web: true)]
            firstSessions.append(StreamSession(matchID: first.id, title: "Other Web source",
                playableURL: URL(string: "https://example.invalid/embed/atomic-other")!, streamType: .unknown,
                providerName: "StreamEx", requiredHeaders: ["X-Fotty-Web-Embed": "true"]))
            owner.openMulti(slots: [.init(event: first, sessions: firstSessions), slot(second, web: true)])
            let original = owner.panes
            original[0].model.transition(to: .playing(.webEmbed), phase: "Playing")
            gate.heldPreparationOwners = [original[0].model.remoteCommandOwnerID]
            owner.selectAudio(to: original[1].id)
            let transfer = try XCTUnwrap(owner.nativePairTransferTask)
            await waitFor { gate.hasPendingPreparation(ownerID: original[0].model.remoteCommandOwnerID) }
            switch action {
            case "stop": owner.stop()
            case "keep": owner.keepOnly(original[0].id)
            case "replace":
                let replacement = event("atomic-cancel-replacement")
                XCTAssertTrue(owner.replacePreparedPane(original[1].id, preserving: original[0].id,
                    event: replacement, sessions: [session(for: replacement, web: true)]))
            case "source": original[0].model.currentSourceIndex = 1
            case "pause": original[0].model.togglePlayPause()
            case "pause-play":
                original[0].model.togglePlayPause()
                original[0].model.togglePlayPause()
            default: original[0].model.setViewingPlaybackContext(.single)
            }
            gate.completePreparation(ownerID: original[0].model.remoteCommandOwnerID)
            await transfer.value
            XCTAssertFalse(gate.events.contains { $0.hasPrefix("retire:") || $0.hasPrefix("adopt:") || $0.hasPrefix("start:") }, action)
            XCTAssertTrue(gate.candidates.allSatisfy(\.discarded), action)
            XCTAssertNil(owner.resolutionMessage, action)
            XCTAssertNil(owner.resolutionError, "Cancellation is not a provider failure: \(action)")
        }
    }

    func testSelectingOriginalAudioDuringPreflightCancelsUpgradeWithoutMovingFocus() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("atomic-reverse-left"), web: true), slot(event("atomic-reverse-right"), web: true)])
        let left = owner.panes[0], right = owner.panes[1]
        gate.heldPreparationOwners = [left.model.remoteCommandOwnerID]
        owner.selectAudio(to: right.id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.hasPendingPreparation(ownerID: left.model.remoteCommandOwnerID) }
        owner.selectAudio(to: right.id)
        XCTAssertEqual(gate.candidates.count, 1, "Repeated taps on the pending target do not create another preflight")
        owner.selectAudio(to: left.id)
        gate.completePreparation(ownerID: left.model.remoteCommandOwnerID)
        await transfer.value
        XCTAssertEqual(owner.audioID, left.id)
        XCTAssertTrue(left.model.isViewingAudioEnabled)
        XCTAssertFalse(right.model.isViewingAudioEnabled)
        XCTAssertFalse(gate.events.contains { $0.hasPrefix("retire:") || $0.hasPrefix("start:") })
        XCTAssertTrue(gate.candidates.allSatisfy(\.discarded))
    }

    func testBannerCancelResolutionCancelsPendingAtomicPreflightRatherThanOnlyHidingProgress() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("atomic-banner-left"), web: true), slot(event("atomic-banner-right"), web: true)])
        let original = owner.panes, attempts = owner.panes.map { $0.model.loadRequestID }
        let audioID = owner.audioID
        gate.heldPreparationOwners = [original[0].model.remoteCommandOwnerID]
        owner.selectAudio(to: original[1].id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.hasPendingPreparation(ownerID: original[0].model.remoteCommandOwnerID) }
        XCTAssertNotNil(owner.resolutionMessage)

        owner.cancelResolution() // The real transition-banner Cancel action.
        gate.completePreparation(ownerID: original[0].model.remoteCommandOwnerID)
        await transfer.value

        XCTAssertNil(owner.nativePairTransferTask)
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.resolutionError)
        XCTAssertEqual(owner.audioID, audioID)
        XCTAssertEqual(owner.panes.map(\.id), original.map(\.id))
        XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
        XCTAssertTrue(original[0].model.isViewingAudioEnabled)
        XCTAssertFalse(original[1].model.isViewingAudioEnabled)
        XCTAssertFalse(gate.events.contains { $0.hasPrefix("retire:") || $0.hasPrefix("adopt:") || $0.hasPrefix("start:") })
        XCTAssertTrue(gate.candidates.allSatisfy(\.discarded))
    }

    func testBannerCancelDuringAtomicRetirementCannotAdoptStartOrMoveAudioAfterLateAcknowledgements() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("atomic-banner-retiring-left"), web: true), slot(event("atomic-banner-retiring-right"), web: true)])
        let original = owner.panes, audioID = owner.audioID
        owner.selectAudio(to: original[1].id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.retirements.count == 2 }

        owner.cancelResolution()
        gate.retirements.values.forEach { $0.complete(true) }
        await transfer.value

        XCTAssertNil(owner.nativePairTransferTask)
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertEqual(owner.audioID, audioID)
        XCTAssertTrue(original.allSatisfy { !$0.model.isViewingAudioEnabled && !$0.model.ownsRemoteCommands })
        XCTAssertFalse(gate.events.contains { $0.hasPrefix("adopt:") || $0.hasPrefix("start:") || $0.hasPrefix("release:") })
        XCTAssertTrue(gate.candidates.allSatisfy(\.discarded), "Post-retirement cancellation is fail-closed, not a hidden Web restart")
    }

    func testFailedOrCancelledActualWebRetirementCannotAdoptOrStartEitherNativePane() async throws {
        for stop in [false, true] {
            let factory = ModelFactory(), gate = NativePairGate()
            let owner = coordinator(factory: factory, nativePairGate: gate)
            defer { owner.stop(); gate.finishAll() }
            owner.openMulti(slots: [slot(event("atomic-retire-left"), web: true), slot(event("atomic-retire-right"), web: true)])
            let original = owner.panes
            owner.selectAudio(to: original[1].id)
            let transfer = try XCTUnwrap(owner.nativePairTransferTask)
            await waitFor { gate.retirements.count == 2 }
            XCTAssertTrue(original.allSatisfy { !$0.model.isViewingAudioEnabled })
            if stop { owner.stop() }
            gate.retirements[original[0].model.remoteCommandOwnerID]?.complete(false)
            gate.retirements[original[1].model.remoteCommandOwnerID]?.complete(true)
            await transfer.value
            XCTAssertFalse(gate.events.contains { $0.hasPrefix("adopt:") || $0.hasPrefix("start:") })
            XCTAssertTrue(gate.candidates.allSatisfy(\.discarded))
            if stop {
                XCTAssertFalse(owner.isActive)
                XCTAssertNil(owner.resolutionError)
            } else {
                XCTAssertTrue(owner.resolutionError?.contains("retry") == true)
                XCTAssertEqual(owner.panes.map(\.id), original.map(\.id))
                XCTAssertTrue(original.allSatisfy { !$0.model.isViewingAudioEnabled })
            }
        }
    }

    func testPartialPausedAdoptionFailureNeverStartsOrReleasesEitherNativeCandidate() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("atomic-adopt-left"), web: true), slot(event("atomic-adopt-right"), web: true)])
        let original = owner.panes
        gate.failedAdoptionOwners = [original[1].model.remoteCommandOwnerID]
        owner.selectAudio(to: original[1].id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.retirements.count == 2 }
        gate.retirements.values.forEach { $0.complete(true) }
        await transfer.value
        XCTAssertFalse(gate.events.contains { $0.hasPrefix("start:") || $0.hasPrefix("release:") })
        XCTAssertTrue(original.allSatisfy { !$0.model.isViewingAudioEnabled })
        XCTAssertTrue(owner.resolutionError?.contains("retry") == true)
    }

    func testNativeUpgradedOriginalWebPairKeepsNativeEngineWhenRetainedOrReordered() async throws {
        let factory = ModelFactory(), gate = NativePairGate()
        let owner = coordinator(factory: factory, nativePairGate: gate)
        defer { owner.stop(); gate.finishAll() }
        let first = event("atomic-retain-left"), second = event("atomic-retain-right")
        owner.openMulti(slots: [slot(first, web: true), slot(second, web: true)])
        let original = owner.panes
        owner.selectAudio(to: original[1].id)
        let transfer = try XCTUnwrap(owner.nativePairTransferTask)
        await waitFor { gate.retirements.count == 2 }
        gate.retirements.values.forEach { $0.complete(true) }
        await transfer.value
        if let focus = owner.audioTransferTask { await focus.value }
        let attempts = owner.panes.map { $0.model.loadRequestID }
        owner.openMulti(slots: [slot(second, web: true), slot(first, web: true)])
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertTrue(owner.panes.allSatisfy { $0.model.activePlaybackEngine == .native })
        XCTAssertTrue(owner.panes.allSatisfy { $0.model.viewingPlaybackContext == .watchTwo(engine: .native) })
        XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, Array(attempts.reversed()))
        XCTAssertNil(owner.resolutionError)
        XCTAssertTrue(owner.panes[0].model === original[1].model)
        XCTAssertTrue(owner.panes[1].model === original[0].model)
    }

    func testWebAudioPromotionWaitsForLateNativeReconnectAndDisconnectAcknowledgement() async throws {
        let factory = ModelFactory(), gate = NativeAudioIsolationTestGate()
        let owner = coordinator(factory: factory)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("native-owner"), web: true), slot(event("web-target"), web: true)])
        let native = owner.panes[0], web = owner.panes[1]
        let item = try await installIsolatedAdoptedItem(on: native.model, gate: gate)
        let attempt = native.model.loadRequestID
        native.model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(native.model.activeSource?.id), requestID: attempt)
        await waitFor { gate.calls == [true, false] }
        owner.listen(to: web.id)
        let transfer = try XCTUnwrap(owner.audioTransferTask)
        XCTAssertFalse(web.model.isViewingAudioEnabled)
        XCTAssertTrue(native.model.player?.isMuted ?? false)
        gate.completeNext()
        await waitFor { gate.calls == [true, false, true] }
        XCTAssertFalse(web.model.isViewingAudioEnabled, "Late reconnect completion is not a native retirement ACK")
        gate.completeNext()
        await transfer.value
        XCTAssertTrue(web.model.isViewingAudioEnabled)
        XCTAssertTrue(web.model.ownsRemoteCommands)
        XCTAssertTrue(web.model.allowsViewingPiP)
        XCTAssertFalse(native.model.isViewingAudioEnabled)
        XCTAssertTrue(gate.disconnected)
        XCTAssertTrue(native.model.player?.currentItem === item)
        XCTAssertEqual(native.model.loadRequestID, attempt)
    }

    func testFocusReversalCannotPromoteSupersededWebTargetAfterNativeAck() async throws {
        let factory = ModelFactory(), gate = NativeAudioIsolationTestGate()
        let owner = coordinator(factory: factory)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("native-reversal"), web: true), slot(event("web-reversal"), web: true)])
        let native = owner.panes[0], web = owner.panes[1]
        _ = try await installIsolatedAdoptedItem(on: native.model, gate: gate)
        native.model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(native.model.activeSource?.id), requestID: native.model.loadRequestID)
        await waitFor { gate.calls == [true, false] }
        owner.listen(to: web.id)
        let oldTransfer = try XCTUnwrap(owner.audioTransferTask)
        owner.listen(to: native.id)
        let currentTransfer = try XCTUnwrap(owner.audioTransferTask)
        gate.completeNext()
        await waitFor { gate.calls == [true, false, true] }
        gate.completeNext()
        await oldTransfer.value
        await currentTransfer.value
        XCTAssertEqual(owner.audioID, native.id)
        XCTAssertFalse(web.model.isViewingAudioEnabled)
        XCTAssertFalse(web.model.ownsRemoteCommands)
        XCTAssertTrue(native.model.isViewingAudioEnabled)
        await waitFor { gate.calls == [true, false, true, false] }
        let claim = try XCTUnwrap(native.model.nativeHandoffAudioClaimTask)
        gate.completeNext()
        await claim.value
        XCTAssertFalse(web.model.isViewingAudioEnabled)
        XCTAssertEqual(native.model.player?.isMuted, AppRuntime.shouldMutePlaybackForTesting)
    }

    func testRemovingNativePanePreservesItsRetirementBarrierBeforeSingleWebPromotion() async throws {
        let factory = ModelFactory(), gate = NativeAudioIsolationTestGate()
        let owner = coordinator(factory: factory)
        defer { owner.stop(); gate.finishAll() }
        owner.openMulti(slots: [slot(event("removed-native"), web: true), slot(event("remaining-web"), web: true)])
        let native = owner.panes[0], web = owner.panes[1]
        _ = try await installIsolatedAdoptedItem(on: native.model, gate: gate)
        native.model.handleWebPlaybackRetired(sourceID: try XCTUnwrap(native.model.activeSource?.id), requestID: native.model.loadRequestID)
        await waitFor { gate.calls == [true, false] }
        owner.keepOnly(web.id)
        let transfer = try XCTUnwrap(owner.audioTransferTask)
        XCTAssertTrue(native.model.isPlaybackSessionRetired)
        XCTAssertNil(native.model.player)
        XCTAssertFalse(web.model.isViewingAudioEnabled)
        gate.completeNext()
        await waitFor { gate.calls == [true, false, true] }
        XCTAssertFalse(web.model.isViewingAudioEnabled)
        gate.completeNext()
        await transfer.value
        XCTAssertEqual(owner.panes.map(\.id), [web.id])
        XCTAssertTrue(web.model.isViewingAudioEnabled)
        XCTAssertTrue(gate.disconnected)
    }

    private func installIsolatedAdoptedItem(on model: LivePlayerViewModel, gate: NativeAudioIsolationTestGate) async throws -> AVPlayerItem {
        let selected = try XCTUnwrap(model.activeSession)
        let item = AVPlayerItem(asset: AVMutableComposition()), player = AVPlayer()
        player.replaceCurrentItem(with: item)
        let isolation = NativePlayerAudioIsolation(player: player, item: item, backend: gate.backend)
        let barrier = isolation.request(disconnected: true)
        await waitFor { gate.pendingCount == 1 }
        gate.completeNext()
        let prepared = await barrier.wait()
        XCTAssertTrue(prepared)
        model.nativeHandoffSession = StreamSession(id: selected.id, matchID: selected.matchID,
            playableURL: URL(string: "https://example.invalid/adopted.m3u8")!, streamType: .hls,
            providerName: selected.providerName, requiredHeaders: [:])
        model.holdNativeHandoffAudioUntilWebRetirement()
        model.player = player
        model.adoptNativeAudioIsolation(isolation)
        model.isVideoReadyForDisplay = true
        model.didApplyLandscape = true
        model.transition(to: .playing(.native), phase: "Playing")
        return item
    }

    func testReplacingMutedPanePreservesAudibleSurvivorAndSwappedDisplayOrder() throws {
        let factory = ModelFactory()
        let viewing = coordinator(factory: factory)
        defer { viewing.stop() }
        viewing.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let survivor = viewing.panes[0], previous = viewing.panes[1]
        let item = installPausedLocalItem(on: survivor.model)
        installPausedLocalItem(on: previous.model)
        let player = survivor.model.player, attempt = survivor.model.loadRequestID
        let source = survivor.model.activeSession?.id
        viewing.swap()
        let next = event("replacement")

        XCTAssertTrue(viewing.replacePreparedPane(previous.id, preserving: survivor.id, event: next, sessions: [session(for: next)]))

        let replacement = viewing.panes[1]
        XCTAssertTrue(viewing.swapped)
        XCTAssertEqual(viewing.displayPanes.map(\.id), [replacement.id, survivor.id])
        XCTAssertEqual(viewing.primaryID, survivor.id)
        XCTAssertEqual(viewing.audioID, survivor.id)
        XCTAssertTrue(viewing.panes[0].model === survivor.model)
        XCTAssertTrue(survivor.model.player === player)
        XCTAssertTrue(survivor.model.player?.currentItem === item)
        XCTAssertEqual(survivor.model.loadRequestID, attempt)
        XCTAssertEqual(survivor.model.activeSession?.id, source)
        XCTAssertEqual(survivor.model.playbackState, .paused(.native))
        XCTAssertFalse(survivor.model.userWantsPlayback)
        XCTAssertTrue(survivor.model.isViewingAudioEnabled)
        XCTAssertTrue(survivor.model.ownsRemoteCommands)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: survivor.model.remoteCommandOwnerID))
        XCTAssertFalse(replacement.model.isViewingAudioEnabled)
        XCTAssertFalse(replacement.model.allowsViewingPiP)
        XCTAssertFalse(replacement.model.ownsRemoteCommands)
        XCTAssertFalse(replacement.model.didStartPlayback)
        XCTAssertNil(replacement.model.player)
        XCTAssertTrue(previous.model.isPlaybackSessionRetired)
        XCTAssertNil(previous.model.player)
        XCTAssertEqual(factory.models.filter { !$0.isPlaybackSessionRetired }.count, 2,
                       "Only the retired target and its prepared replacement are changed; no third decoder starts")
    }

    func testReplacingAudioPrimaryTransfersOnlyItsRolesAndRetainsPausedSibling() throws {
        let factory = ModelFactory(), client = RecordingHandoffPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        let owner = coordinator(factory: factory, handoffPublisher: publisher)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let previous = owner.panes[0], survivor = owner.panes[1]
        installPausedLocalItem(on: previous.model)
        let item = installPausedLocalItem(on: survivor.model)
        let player = survivor.model.player, attempt = survivor.model.loadRequestID
        try publisher.offer(event: previous.event, now: Date(timeIntervalSince1970: 1_800_000_000))
        owner.swap()
        let next = event("replacement")

        XCTAssertTrue(owner.replacePreparedPane(previous.id, preserving: survivor.id, event: next, sessions: [session(for: next)]))

        let replacement = owner.panes[0]
        XCTAssertTrue(owner.swapped)
        XCTAssertEqual(owner.primaryID, replacement.id)
        XCTAssertEqual(owner.audioID, replacement.id)
        XCTAssertFalse(publisher.isOffering)
        XCTAssertTrue(replacement.model.isViewingAudioEnabled)
        XCTAssertTrue(replacement.model.allowsViewingPiP)
        XCTAssertTrue(replacement.model.ownsRemoteCommands)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: replacement.model.remoteCommandOwnerID))
        XCTAssertTrue(owner.panes[1].model === survivor.model)
        XCTAssertTrue(survivor.model.player === player)
        XCTAssertTrue(survivor.model.player?.currentItem === item)
        XCTAssertEqual(survivor.model.loadRequestID, attempt)
        XCTAssertEqual(survivor.model.playbackState, .paused(.native))
        XCTAssertFalse(survivor.model.userWantsPlayback)
        XCTAssertFalse(survivor.model.isViewingAudioEnabled)
        XCTAssertFalse(survivor.model.ownsRemoteCommands)
        XCTAssertFalse(survivor.model.allowsViewingPiP)
        XCTAssertTrue(previous.model.isPlaybackSessionRetired)
        previous.model.setRemoteCommandOwnership(true)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: replacement.model.remoteCommandOwnerID),
                      "A late retired target cannot reclaim audio or remote controls")
    }

    func testInvalidPreparedReplacementCannotMutateEitherPane() throws {
        let factory = ModelFactory(), next = event("replacement")
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let ids = owner.panes.map(\.id), primary = owner.panes[0], target = owner.panes[1]
        let item = installPausedLocalItem(on: primary.model)
        let attempt = primary.model.loadRequestID
        XCTAssertFalse(owner.replacePreparedPane(UUID(), preserving: primary.id, event: next, sessions: [session(for: next)]))
        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: UUID(), event: next, sessions: [session(for: next)]))
        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: primary.id, event: next, sessions: []))
        let conflict = event("conflict", conflict: true)
        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: primary.id, event: conflict, sessions: [session(for: conflict)]))
        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: primary.id, event: primary.event, sessions: primary.model.sessions))
        XCTAssertEqual(owner.panes.map(\.id), ids)
        XCTAssertEqual(owner.audioID, primary.id)
        XCTAssertEqual(primary.model.loadRequestID, attempt)
        XCTAssertTrue(primary.model.player?.currentItem === item)
        XCTAssertEqual(primary.model.playbackState, .paused(.native))
        XCTAssertFalse(target.model.isPlaybackSessionRetired)
        XCTAssertEqual(factory.models.count, 2)
    }

    func testTargetPiPOrFullscreenBlocksReplacementButSiblingPiPIsPreserved() throws {
        let factory = ModelFactory(), next = event("replacement")
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let survivor = owner.panes[0], target = owner.panes[1]
        installPausedLocalItem(on: target.model)
        target.model.isPictureInPictureActive = true
        owner.showMatchPicker(replacing: target.id)
        XCTAssertFalse(owner.showsSecondMatchPicker)
        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: survivor.id, event: next, sessions: [session(for: next)]))
        target.model.isPictureInPictureActive = false
        target.model.isVideoReadyForDisplay = true
        target.model.beginNativeFullscreen()
        XCTAssertNotNil(target.model.nativeFullscreen)
        XCTAssertFalse(owner.replacePreparedPane(target.id, preserving: survivor.id, event: next, sessions: [session(for: next)]))
        if let lease = target.model.nativeFullscreen { target.model.endNativeFullscreen(lease) }
        survivor.model.isPictureInPictureActive = true
        XCTAssertTrue(owner.replacePreparedPane(target.id, preserving: survivor.id, event: next, sessions: [session(for: next)]))
        XCTAssertTrue(survivor.model.isPictureInPictureActive)
        XCTAssertEqual(owner.audioID, survivor.id)
        XCTAssertTrue(survivor.model.ownsRemoteCommands)
        survivor.model.isPictureInPictureActive = false
    }

    func testCancelledOrSupersededReplacementCannotResurrectStoppedOrKeptPanes() async throws {
        for action in ["cancel", "keep", "stop"] {
            let factory = ModelFactory(), gate = ResolutionGate(), next = event("replacement")
            let result = outcome(for: next, sessions: [session(for: next)])
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                resolvePlayback: { await gate.resolve($0) }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { gate.completeAll(result); owner.stop() }
            owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
            let original = owner.panes
            owner.showMatchPicker(replacing: original[1].id)
            owner.chooseSecond(next)
            await waitFor { gate.requests.count == 1 }
            XCTAssertEqual(factory.models.count, 2, "Resolving may not start a third decoder")
            if action == "cancel" { owner.cancelResolution() }
            if action == "keep" { owner.keepOnly(original[0].id) }
            if action == "stop" { owner.stop() }
            gate.complete(result)
            await waitFor { gate.finishedResolutions == 1 }
            XCTAssertEqual(factory.models.count, 2)
            XCTAssertEqual(owner.panes.map(\.id), action == "stop" ? [] : action == "keep" ? [original[0].id] : original.map(\.id))
            XCTAssertNil(owner.resolutionMessage)
        }
    }

    func testLatestReplacementWinsAndRechecksPresentationAtCommit() async throws {
        let factory = ModelFactory(), gate = ResolutionGate()
        let first = event("requested-first"), latest = event("requested-latest")
        let firstResult = outcome(for: first, sessions: [session(for: first)])
        let latestResult = outcome(for: latest, sessions: [session(for: latest)])
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { await gate.resolve($0) }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.completeAll(latestResult); owner.stop() }
        owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let original = owner.panes
        owner.showMatchPicker(replacing: original[1].id); owner.chooseSecond(first)
        await waitFor { gate.requests.count == 1 }
        owner.showMatchPicker(replacing: original[1].id); owner.chooseSecond(latest)
        await waitFor { gate.requests.count == 2 }
        gate.complete(firstResult)
        await waitFor { gate.finishedResolutions == 1 }
        XCTAssertEqual(owner.panes.map(\.id), original.map(\.id))
        original[1].model.isPictureInPictureActive = true
        gate.complete(latestResult)
        await waitFor { owner.resolutionError != nil }
        XCTAssertEqual(owner.panes.map(\.id), original.map(\.id), "A new PiP presentation must be rechecked after asynchronous lookup")
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertNotNil(owner.resolutionError)
        original[1].model.isPictureInPictureActive = false
    }

    func testFailedOrEmptyResolutionLeavesBothPreparedOwnersUntouched() async throws {
        for failed in [false, true] {
            let factory = ModelFactory(), next = event("replacement")
            let result = outcome(for: next, sessions: [], failed: failed)
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                resolvePlayback: { _ in result }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
            let original = owner.panes
            let item = installPausedLocalItem(on: original[0].model)
            let attempt = original[0].model.loadRequestID
            owner.showMatchPicker(replacing: original[1].id); owner.chooseSecond(next)
            await waitFor { owner.resolutionError != nil }
            XCTAssertEqual(owner.panes.map(\.id), original.map(\.id))
            XCTAssertEqual(factory.models.count, 2)
            XCTAssertTrue(original[0].model.player?.currentItem === item)
            XCTAssertEqual(original[0].model.loadRequestID, attempt)
            XCTAssertFalse(original[0].model.userWantsPlayback)
            XCTAssertFalse(original[1].model.isPlaybackSessionRetired)
        }
    }

    func testFullCatalogPickerSearchFindsEventsBeyondOldLimitsAndFiltersSport() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
        let rows = (0..<520).map { event("fixture-\($0)", date: date) }
        let target = event("late-target", home: "Internacional de Bogotá", away: "New Example", category: "basketball", date: date)
        let prepared = await ViewingMatchPickerPolicy.prepare(events: rows + [target], catalog: rows + [target], excluding: [], now: now)
        let result = try XCTUnwrap(prepared)
        XCTAssertEqual(result.events.count, 521, "All eligible rows must remain discoverable, not just the first40 or first500")
        XCTAssertEqual(result.results(query: "Bogota").map(\.id), [target.id])
        XCTAssertEqual(result.results(query: "", sport: "basketball").map(\.id), [target.id])
        XCTAssertEqual(result.results(query: "fixture", sport: "football").count, 520)
        XCTAssertTrue(result.results(query: "Bogota", sport: "football").isEmpty)
    }

    func testPickerReusesExactFootballLeagueSearchClassification() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
        let premier = event("premier", home: "Chelsea", away: "Brighton", date: date)
        let other = event("other", home: "Example United", away: "Different Example", date: date)
        let result = await ViewingMatchPickerPolicy.prepare(events: [premier, other], catalog: [premier, other], excluding: [], now: now,
            leagueName: { $0.id == premier.id ? AnalyticalDataEngine.FootballLeagueTab.premierLeague.displayName : nil })
        XCTAssertEqual(try XCTUnwrap(result).results(query: "Premier League").map(\.id), [premier.id])
        XCTAssertEqual(try XCTUnwrap(result).results(query: "Chelsea Brighton").map(\.id), [premier.id])
    }

    func testCanonicalProviderAliasIsDuplicateExclusionNotMediaOwnerReuse() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
        let alias = event("plain-la-dodgers", home: "Atlanta Braves", away: "LA Dodgers", category: "baseball", date: date)
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:mlb:reviewed", sport: "baseball",
            competitionID: "mlb", competitionName: "MLB", eventKind: .match,
            title: "Atlanta Braves vs Los Angeles Dodgers",
            participants: [.init(id: "atlanta-braves", name: "Atlanta Braves"), .init(id: "los-angeles-dodgers", name: "Los Angeles Dodgers")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: now, verified: true,
            providerObservedAt: now, providerEventIDs: [alias.id])
        let canonical = event(metadata.fixtureID, home: "Atlanta Braves", away: "Los Angeles Dodgers", category: "baseball",
            date: date, competition: "mlb", fixture: metadata)
        XCTAssertFalse(ViewingSessionCoordinator.canReuse(alias, for: canonical), "Owner reuse must retain its strict same-ID contract")
        XCTAssertTrue(ViewingSessionCoordinator.representsSameFixture(alias, as: canonical))
        XCTAssertTrue(ViewingSessionCoordinator.representsSameFixture(canonical, as: alias))
        let tomorrow = event("tomorrow", home: alias.homeName, away: alias.awayName, category: "baseball", date: date + 86_400)
        let women = event("women", home: "Atlanta Braves Women", away: "LA Dodgers Women", category: "baseball", date: date)
        let wrongLeague = event("wrong-league", home: alias.homeName, away: alias.awayName, category: "baseball", date: date, competition: "npb")
        XCTAssertFalse(ViewingSessionCoordinator.representsSameFixture(tomorrow, as: canonical))
        XCTAssertFalse(ViewingSessionCoordinator.representsSameFixture(women, as: canonical))
        XCTAssertFalse(ViewingSessionCoordinator.representsSameFixture(wrongLeague, as: canonical))
        let other = event("other", category: "baseball", date: date)
        let prepared = await ViewingMatchPickerPolicy.prepare(events: [canonical, other], catalog: [canonical, other], excluding: [alias], now: now)
        XCTAssertEqual(try XCTUnwrap(prepared).events.map(\.id), [other.id])

        let factory = ModelFactory()
        var requests = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in requests += 1; return self.outcome(for: canonical, sessions: [self.session(for: canonical)]) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.open(event: alias, sessions: [session(for: alias)])
        owner.showMatchPicker(); owner.chooseSecond(canonical)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(owner.panes.count, 1)
        owner.openMulti(slots: [slot(alias), slot(other)])
        XCTAssertFalse(owner.replacePreparedPane(owner.panes[1].id, preserving: owner.panes[0].id,
            event: canonical, sessions: [session(for: canonical)]))
        XCTAssertEqual(factory.models.count, 2)
    }

    func testAcceptedTerminalReplacementCannotRetireCurrentTarget() {
        let factory = ModelFactory()
        let viewing = coordinator(factory: factory)
        defer { viewing.stop() }
        viewing.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let originals = viewing.panes
        let now = Date()
        for status in [SportsFixtureCatalog.Status.finished, .cancelled, .postponed] {
            let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:mlb:stopped", sport: "baseball",
                competitionID: "mlb", competitionName: "MLB", eventKind: .match,
                title: "Atlanta Braves vs Los Angeles Dodgers",
                participants: [.init(id: "atlanta-braves", name: "Atlanta Braves"), .init(id: "los-angeles-dodgers", name: "Los Angeles Dodgers")],
                squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: true,
                providerObservedAt: now, providerEventIDs: ["stopped"])
            let stopped = event("stopped", home: "Atlanta Braves", away: "Los Angeles Dodgers", category: "baseball",
                date: Int64(now.addingTimeInterval(-3_600).timeIntervalSince1970), competition: "mlb", fixture: metadata)
            XCTAssertTrue(MatchStartPolicy(event: stopped).isStopped)
            XCTAssertFalse(viewing.replacePreparedPane(originals[1].id, preserving: originals[0].id,
                event: stopped, sessions: [session(for: stopped)]))
        }
        XCTAssertEqual(viewing.panes.map(\.id), originals.map(\.id))
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertTrue(originals.allSatisfy { !$0.model.isPlaybackSessionRetired })
    }

    func testSuccessfulResolutionReplacesSelectedLogicalPaneAfterSwap() async throws {
        let factory = ModelFactory(), gate = ResolutionGate(), next = event("replacement")
        let result = outcome(for: next, sessions: [session(for: next)])
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { await gate.resolve($0) }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.completeAll(result); owner.stop() }
        owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let survivor = owner.panes[0], target = owner.panes[1]
        let item = installPausedLocalItem(on: survivor.model), attempt = survivor.model.loadRequestID
        owner.showMatchPicker(replacing: target.id); owner.chooseSecond(next)
        await waitFor { gate.requests.count == 1 }
        owner.swap()
        XCTAssertEqual(owner.panes.map(\.id), [survivor.id, target.id])
        gate.complete(result)
        await waitFor { owner.panes.last?.event.id == next.id }
        XCTAssertEqual(owner.displayPanes.map { $0.event.id }, [next.id, survivor.event.id])
        XCTAssertTrue(owner.panes[0].model === survivor.model)
        XCTAssertTrue(survivor.model.player?.currentItem === item)
        XCTAssertEqual(survivor.model.loadRequestID, attempt)
        XCTAssertEqual(survivor.model.playbackState, .paused(.native))
        XCTAssertEqual(owner.audioID, survivor.id)
        XCTAssertTrue(target.model.isPlaybackSessionRetired)
        XCTAssertEqual(factory.models.filter { !$0.isPlaybackSessionRetired }.count, 2)
    }

    func testPickerExcludesRetainedConflictAndUnavailableRowsAndCannotPublishStaleWork() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
        let retained = event("retained", date: date), valid = event("valid", date: date)
        let duplicate = event("duplicate", date: date), conflict = event("duplicate", conflict: true, date: date)
        let missing = EventReference(id: "unavailable", title: "Unavailable vs Other", category: "football", date: date,
            poster: nil, popular: false, teams: .init(home: .init(name: "Unavailable", badge: nil), away: .init(name: "Other", badge: nil)), sources: [])
        let rows = [retained, valid, duplicate, missing]
        let prepared = await ViewingMatchPickerPolicy.prepare(events: rows, catalog: rows + [conflict], excluding: [retained], now: now)
        XCTAssertEqual(try XCTUnwrap(prepared).events.map(\.id), [valid.id])
        var current = true, checkpoints = 0
        let stale = await ViewingMatchPickerPolicy.prepare(events: rows, catalog: rows, excluding: [], now: now,
            isCurrent: { current }, checkpoint: { checkpoints += 1; current = false; return true })
        XCTAssertNil(stale)
        XCTAssertEqual(checkpoints, 1)
        let cancelled = Task { await ViewingMatchPickerPolicy.prepare(events: rows, catalog: rows, excluding: [], now: now,
            checkpoint: { withUnsafeCurrentTask { $0?.cancel() }; return true }) }
        let cancelledResult = await cancelled.value
        XCTAssertNil(cancelledResult)
    }

    func testSourcePresentationUsesListedMetadataWithoutInventedCapabilitiesOrRawTitles() {
        XCTAssertNil(BroadcastSourcePresentation.description(qualityLabel: nil, currentMode: nil))
        XCTAssertNil(BroadcastSourcePresentation.description(qualityLabel: "auto", currentMode: nil))
        XCTAssertEqual(BroadcastSourcePresentation.description(qualityLabel: "English · HD", currentMode: nil), "Listed: English · HD")
        XCTAssertEqual(BroadcastSourcePresentation.description(qualityLabel: "French - 1080p", currentMode: .native), "Native player · Listed: French · Full HD")
        XCTAssertEqual(BroadcastSourcePresentation.description(qualityLabel: nil, currentMode: .webEmbed), "Web player")
        XCTAssertEqual(BroadcastSourcePresentation.description(qualityLabel: "provider-HD", currentMode: nil), "Listed: HD")
        for value in ["https://example.invalid/English-HD.m3u8", "user@example.invalid HD", String(repeating: "HD ", count: 100)] {
            XCTAssertTrue(BroadcastSourcePresentation.listedMetadata(value).isEmpty)
        }
        XCTAssertNil(BroadcastSourcePresentation.description(qualityLabel: "PIP supported reliable best live", currentMode: nil))
    }

    func testPreparedOpenClaimsOneOwnerWithoutStartingTransport() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        let match = event("first")
        let prepared = session(for: match)

        owner.open(event: match, sessions: [prepared])

        let pane = try XCTUnwrap(owner.primary)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(pane.model === factory.models[0])
        XCTAssertEqual(pane.event.id, match.id)
        XCTAssertEqual(pane.model.activeSession?.id, prepared.id)
        XCTAssertEqual(owner.panes.map(\.id), [pane.id])
        XCTAssertEqual(owner.primaryID, pane.id)
        XCTAssertEqual(owner.audioID, pane.id)
        XCTAssertTrue(owner.isActive)
        XCTAssertFalse(owner.isTwo)
        XCTAssertTrue(owner.expanded)
        XCTAssertTrue(pane.model.ownsRemoteCommands)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: pane.model.remoteCommandOwnerID))
        XCTAssertFalse(pane.model.didStartPlayback)
        XCTAssertFalse(pane.model.networkPathObserver.isRunning)
        XCTAssertNil(pane.model.loadTask)
        XCTAssertNil(pane.model.player)
    }

    func testMinimizeAndExpandPreserveModelAttemptItemSourceAndExplicitPause() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        let match = event("first")
        owner.open(event: match, sessions: [session(for: match)])
        let pane = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: pane.model)
        let attempt = pane.model.loadRequestID
        let source = pane.model.activeSession?.id
        let sessionID = pane.model.playbackCorrelation.sessionID

        for _ in 0..<10 {
            owner.minimize()
            XCTAssertFalse(owner.expanded)
            owner.expand()
            XCTAssertTrue(owner.expanded)
            XCTAssertEqual(owner.primary?.id, pane.id)
            XCTAssertTrue(owner.primary?.model === pane.model)
            XCTAssertEqual(pane.model.loadRequestID, attempt)
            XCTAssertEqual(pane.model.activeSession?.id, source)
            XCTAssertEqual(pane.model.playbackCorrelation.sessionID, sessionID)
            XCTAssertTrue(pane.model.player?.currentItem === item)
            XCTAssertEqual(pane.model.playbackState, .paused(.native))
            XCTAssertFalse(pane.model.userWantsPlayback)
            XCTAssertEqual(pane.model.player?.rate, 0)
            XCTAssertTrue(NowPlayingManager.shared.isOwned(by: pane.model.remoteCommandOwnerID))
        }
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertFalse(pane.model.didStartPlayback)
        XCTAssertFalse(pane.model.networkPathObserver.isRunning)
    }

    func testSameProviderIDWithChangedOpponentsCreatesAFreshOwner() throws {
        let original = event("reused", home: "Liverpool", away: "Chelsea")
        let changed = event("reused", home: "Liverpool", away: "Arsenal")
        try assertReplacement(original: original, requested: changed)
        try assertReplacement(original: original, requested: changed, inTwoMatches: true)
    }

    func testSameProviderIDWithChangedKickoffOutsideIdentityToleranceCreatesAFreshOwner() throws {
        let original = event("reused")
        for offset: Int64 in [901, 86_400] {
            let changed = event("reused", date: 1_800_000_000 + offset)
            try assertReplacement(original: original, requested: changed)
            try assertReplacement(original: original, requested: changed, inTwoMatches: true)
        }
    }

    func testSameProviderIDWithChangedCompetitionCreatesAFreshOwner() throws {
        let original = event("reused", competition: "premier-league")
        for competition in ["fa-cup", nil] as [String?] {
            let changed = event("reused", competition: competition)
            try assertReplacement(original: original, requested: changed)
            try assertReplacement(original: original, requested: changed, inTwoMatches: true)
        }
    }

    func testSameProviderIDWithFootballTitleOnlySquadChangeCreatesAFreshOwner() throws {
        let original = event("reused", home: "Liverpool", away: "Chelsea")
        for title in ["Liverpool vs Chelsea Women", "Liverpool vs Chelsea U21", "Liverpool vs Chelsea Reserves"] {
            let changed = event("reused", home: "Liverpool", away: "Chelsea", title: title)
            try assertReplacement(original: original, requested: changed)
            try assertReplacement(original: original, requested: changed, inTwoMatches: true)
        }
    }

    func testSameProviderIDWithCricketTitleOnlySquadChangeCreatesAFreshOwner() throws {
        let women = event("reused", home: "New Zealand", away: "South Africa",
                          title: "New Zealand vs South Africa Women", category: "cricket")
        let senior = event("reused", home: "New Zealand", away: "South Africa", category: "cricket")
        for (original, changed) in [(women, senior), (senior, women)] {
            try assertReplacement(original: original, requested: changed)
            try assertReplacement(original: original, requested: changed, inTwoMatches: true)
        }
    }

    func testSameProviderIDWithTypedSquadChangeCreatesAFreshOwner() throws {
        func fixture(gender: SportsFixtureCatalog.Squad.Gender, age: String) -> SportsFixtureMetadata {
            .init(fixtureID: "sports-fixture:premier-league:reused", sport: "football",
                  competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                  title: "Liverpool vs Chelsea", participants: [.init(id: "liverpool", name: "Liverpool"),
                    .init(id: "chelsea", name: "Chelsea")], squad: .init(gender: gender, ageGroup: age),
                  status: .live, observedAt: Date(timeIntervalSince1970: 1_800_000_000), verified: true)
        }
        let original = event("reused", home: "Liverpool", away: "Chelsea",
                             fixture: fixture(gender: .men, age: "senior"))
        for (gender, age) in [(SportsFixtureCatalog.Squad.Gender.women, "senior"), (.men, "u21")] {
            let changed = event("reused", home: "Liverpool", away: "Chelsea",
                                fixture: fixture(gender: gender, age: age))
            try assertReplacement(original: original, requested: changed)
            try assertReplacement(original: original, requested: changed, inTwoMatches: true)
        }
    }

    private func assertReplacement(original: EventReference, requested: EventReference,
                                   inTwoMatches: Bool = false,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.open(event: original, sessions: [session(for: original)])
        let retained = try XCTUnwrap(owner.primary, file: file, line: line)
        installPausedLocalItem(on: retained.model)
        owner.minimize()
        let prepared = session(for: requested)
        XCTAssertFalse(ViewingSessionCoordinator.canReuse(original, for: requested), file: file, line: line)

        if inTwoMatches {
            owner.openMulti(slots: [.init(event: requested, sessions: [prepared]), slot(event("second"))])
        } else {
            owner.open(event: requested, sessions: [prepared])
        }

        let replacement = try XCTUnwrap(owner.primary, file: file, line: line)
        XCTAssertNotEqual(replacement.id, retained.id, file: file, line: line)
        XCTAssertFalse(replacement.model === retained.model, file: file, line: line)
        XCTAssertTrue(retained.model.isPlaybackSessionRetired, file: file, line: line)
        XCTAssertNil(retained.model.player, file: file, line: line)
        XCTAssertEqual(factory.models.count, inTwoMatches ? 3 : 2, file: file, line: line)
        XCTAssertEqual(replacement.model.activeSession?.id, prepared.id, file: file, line: line)
        XCTAssertEqual(replacement.event.homeName, requested.homeName, file: file, line: line)
        XCTAssertEqual(replacement.event.awayName, requested.awayName, file: file, line: line)
        XCTAssertEqual(replacement.event.kickoffDate, requested.kickoffDate, file: file, line: line)
        XCTAssertEqual(replacement.event.competitionID, requested.competitionID, file: file, line: line)
        XCTAssertFalse(replacement.model.didStartPlayback, file: file, line: line)
    }

    func testOpeningAnotherPrimaryInvalidatesTheOldHandoffOffer() throws {
        let factory = ModelFactory()
        let client = RecordingHandoffPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        let owner = coordinator(factory: factory, handoffPublisher: publisher)
        defer { owner.stop() }
        let original = event("original"), replacement = event("replacement")
        owner.open(event: original, sessions: [session(for: original)])
        try publisher.offer(event: original, now: Date(timeIntervalSince1970: 1_800_000_000))
        let invalidations = client.invalidations

        owner.open(event: replacement, sessions: [session(for: replacement)])

        XCTAssertFalse(publisher.isOffering)
        XCTAssertNil(publisher.offeredIdentity)
        XCTAssertGreaterThan(client.invalidations, invalidations)
        XCTAssertEqual(client.published.map(\.eventID), [original.id])
        XCTAssertEqual(owner.primary?.event.id, replacement.id)
    }

    func testPresentationAudioAndSamePrimaryMultiChangesDoNotInvalidateHandoff() throws {
        let factory = ModelFactory()
        let client = RecordingHandoffPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        let owner = coordinator(factory: factory, handoffPublisher: publisher)
        defer { owner.stop() }
        let first = event("first"), second = event("second")
        owner.open(event: first, sessions: [session(for: first)])
        let primaryID = try XCTUnwrap(owner.primaryID)
        let offered = try publisher.offer(event: first, now: Date(timeIntervalSince1970: 1_800_000_000))
        let invalidations = client.invalidations

        owner.openMulti(slots: [slot(first), slot(second)])
        owner.minimize()
        owner.expand()
        owner.swap()
        owner.listen(to: owner.panes[1].id)

        XCTAssertEqual(owner.primaryID, primaryID)
        XCTAssertEqual(publisher.offeredIdentity, offered)
        XCTAssertTrue(publisher.isOffering)
        XCTAssertEqual(client.invalidations, invalidations)
        XCTAssertEqual(client.published.count, 1)
    }

    func testReplacingMultiPrimaryUnderTheSameProviderIDInvalidatesHandoff() throws {
        let factory = ModelFactory()
        let client = RecordingHandoffPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        let owner = coordinator(factory: factory, handoffPublisher: publisher)
        defer { owner.stop() }
        let original = event("reused", home: "Liverpool", away: "Chelsea")
        let changed = event("reused", home: "Liverpool", away: "Arsenal")
        owner.open(event: original, sessions: [session(for: original)])
        let previousPrimaryID = try XCTUnwrap(owner.primaryID)
        try publisher.offer(event: original, now: Date(timeIntervalSince1970: 1_800_000_000))
        let invalidations = client.invalidations

        owner.openMulti(slots: [slot(changed), slot(event("second"))])

        XCTAssertNotEqual(owner.primaryID, previousPrimaryID)
        XCTAssertEqual(owner.primary?.event.id, original.id, "The raw provider ID is reused, not the fixture identity")
        XCTAssertFalse(publisher.isOffering)
        XCTAssertNil(publisher.offeredIdentity)
        XCTAssertGreaterThan(client.invalidations, invalidations)
        XCTAssertEqual(client.published.count, 1)
    }

    func testReorderingOrKeepingAnotherPrimaryInvalidatesHandoff() throws {
        let factory = ModelFactory()
        let client = RecordingHandoffPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        let owner = coordinator(factory: factory, handoffPublisher: publisher)
        defer { owner.stop() }
        let first = event("first"), second = event("second")
        owner.openMulti(slots: [slot(first), slot(second)])
        let firstID = try XCTUnwrap(owner.primaryID)
        try publisher.offer(event: first, now: Date(timeIntervalSince1970: 1_800_000_000))

        owner.openMulti(slots: [slot(second), slot(first)])
        XCTAssertFalse(publisher.isOffering)
        XCTAssertNil(publisher.offeredIdentity)
        XCTAssertEqual(owner.primary?.event.id, second.id)
        try publisher.offer(event: second, now: Date(timeIntervalSince1970: 1_800_000_000))
        owner.keepOnly(firstID)

        XCTAssertFalse(publisher.isOffering)
        XCTAssertNil(publisher.offeredIdentity)
        XCTAssertEqual(owner.primary?.event.id, first.id)
        XCTAssertEqual(factory.models.count, 2, "Primary selection must reuse the surviving models")
        XCTAssertEqual(client.published.map(\.eventID), [first.id, second.id])
    }

    func testStopRevokesHandoffWithoutRepublishingItOnLaterPresentation() throws {
        let factory = ModelFactory()
        let client = RecordingHandoffPublisher()
        let publisher = SportsHandoffPublisher(client: client)
        let owner = coordinator(factory: factory, handoffPublisher: publisher)
        let match = event("first")
        owner.open(event: match, sessions: [session(for: match)])
        try publisher.offer(event: match, now: Date(timeIntervalSince1970: 1_800_000_000))
        owner.stop()
        owner.stop()
        owner.expand()
        owner.minimize()

        XCTAssertFalse(publisher.isOffering)
        XCTAssertNil(publisher.offeredIdentity)
        XCTAssertEqual(client.published.count, 1)
        XCTAssertFalse(owner.isActive)
    }

    func testRetainedSingleReopenPreservesPausedTransportWithoutResolverOrReplacement() throws {
        let factory = ModelFactory()
        var resolves = 0, catalogLookups = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in resolves += 1; preconditionFailure("Retained presentation never resolves streams") },
            catalogEvent: { _ in catalogLookups += 1; return nil })
        defer { owner.stop() }
        let match = event("retained-single", home: "Chelsea", away: "Brighton", competition: "premier-league")
        owner.open(event: match, sessions: [session(for: match)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        let player = original.model.player, attempt = original.model.loadRequestID
        let source = original.model.activeSource?.id, audioID = owner.audioID
        owner.minimize()
        let now = Date(timeIntervalSince1970: 1_800_000_060)
        XCTAssertTrue(owner.reopenRetainedSingle(event: match, catalog: [match], now: now))
        XCTAssertTrue(owner.reopenRetainedSingle(event: match, catalog: [match], now: now))
        XCTAssertEqual(resolves, 0); XCTAssertEqual(catalogLookups, 0)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.expanded)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertTrue(original.model.player === player)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertEqual(original.model.activeSource?.id, source)
        XCTAssertEqual(owner.audioID, audioID)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(original.model.userWantsPlayback)
    }

    func testRetainedSingleReopenRejectsChangedOrConflictingCurrentIdentityAndTerminalStatus() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let match = event("retained-single", home: "Chelsea", away: "Brighton", competition: "premier-league")
        owner.open(event: match, sessions: [session(for: match)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        owner.minimize()
        let now = Date(timeIntervalSince1970: 1_800_000_060)
        let changes = [
            event(match.id, conflict: true, home: "Chelsea", away: "Brighton", competition: "premier-league"),
            event(match.id, home: "Chelsea", away: "Arsenal", competition: "premier-league"),
            event(match.id, home: "Chelsea", away: "Brighton", date: 1_800_086_400, competition: "premier-league"),
            event(match.id, home: "Chelsea", away: "Brighton", competition: "champions-league"),
            event(match.id, home: "Chelsea U21", away: "Brighton U21", competition: "premier-league"),
            event("different-id", home: "Chelsea", away: "Brighton", competition: "premier-league")
        ]
        for current in changes {
            XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [current], now: now))
            XCTAssertFalse(owner.reopenRetainedSingle(event: current, catalog: [current], now: now))
        }
        XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [], now: now))
        XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [match, match], now: now))
        XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [match], status: .cancelled, now: now))
        XCTAssertFalse(owner.expanded)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertFalse(original.model.userWantsPlayback)
    }

    func testRetainedCricketChannelReopensDuringPrimaryOutageWithoutRestartingPausedPlayback() throws {
        let factory = ModelFactory()
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in preconditionFailure("Retained channel must not resolve again") },
            catalogEvent: { _ in preconditionFailure("Retained channel must not fetch the primary catalog") })
        defer { owner.stop() }
        let channel = CricketChannelCatalog.event(for: .willow, in: [])
        owner.open(event: channel, sessions: [session(for: channel)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        let player = original.model.player, attempt = original.model.loadRequestID
        owner.minimize()
        XCTAssertTrue(owner.reopenRetainedSingle(event: channel, catalog: []))
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertTrue(original.model.player === player)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(original.model.userWantsPlayback)
    }

    func testTVWatchReopensRetainedStationWithoutDiscoveryOrReplacingPausedTransport() async throws {
        let stations = [try XCTUnwrap(SportsTVStation.station(provider: "TV2")),
                        try XCTUnwrap(SportsTVStation.station(id: CricketBroadcastChannel.willow.canonicalID))]
        for station in stations {
            let factory = ModelFactory()
            var discoveries = 0
            let channel = station.event
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { _, _ in
                    discoveries += 1
                    return self.outcome(for: channel, sessions: [], failed: true)
                }, catalogEvent: { _ in XCTFail("TV reopen must not fetch a catalog"); return nil },
                cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.open(event: channel, sessions: [session(for: channel)])
            let original = try XCTUnwrap(owner.primary)
            let item = installPausedLocalItem(on: original.model)
            let player = original.model.player, attempt = original.model.loadRequestID
            let source = original.model.activeSource?.id, audioID = owner.audioID
            owner.minimize()

            SportsTVWatchPolicy.watch(channel, using: owner, catalog: [])

            XCTAssertEqual(owner.pendingSingleEvent?.id, channel.id)
            XCTAssertNotNil(owner.resolutionMessage)
            await waitForSourceCheck { owner.expanded && owner.pendingSingleEvent == nil }
            XCTAssertEqual(discoveries, 0)
            XCTAssertNil(owner.pendingSingleEvent)
            XCTAssertNil(owner.resolutionMessage)
            XCTAssertTrue(owner.expanded)
            XCTAssertEqual(factory.models.count, 1)
            XCTAssertTrue(owner.primary?.model === original.model)
            XCTAssertTrue(original.model.player === player)
            XCTAssertTrue(original.model.player?.currentItem === item)
            XCTAssertEqual(original.model.loadRequestID, attempt)
            XCTAssertEqual(original.model.activeSource?.id, source)
            XCTAssertEqual(owner.audioID, audioID)
            XCTAssertEqual(original.model.playbackState, .paused(.native))
            XCTAssertFalse(original.model.userWantsPlayback)
        }
    }

    func testTVWatchDiscoversDifferentOrFailedStationInsteadOfReusingItsPlayer() async throws {
        for failed in [false, true] {
            let factory = ModelFactory(), gate = SingleDiscoveryGate()
            let first = try XCTUnwrap(SportsTVStation.station(provider: "TV2")).event
            let alternate = try XCTUnwrap(SportsTVStation.station(provider: "TV3")).event
            let target = failed ? first : alternate
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { CurrentEventBroadcastPolicy.currentEvent(for: $0, in: []) },
                catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { gate.complete(outcome(for: target, sessions: [])); owner.stop() }
            owner.open(event: first, sessions: [session(for: first)])
            let original = try XCTUnwrap(owner.primary)
            _ = installPausedLocalItem(on: original.model)
            if failed { original.model.error = "Source unavailable" }
            owner.minimize()

            SportsTVWatchPolicy.watch(target, using: owner, catalog: [])

            XCTAssertEqual(owner.pendingSingleEvent?.id, target.id)
            XCTAssertNotNil(owner.resolutionMessage)
            await waitForSourceCheck { gate.publish != nil }
            await gate.publish?([session(for: target)])
            XCTAssertEqual(factory.models.count, 2)
            XCTAssertEqual(owner.primary?.event.id, target.id)
            XCTAssertFalse(owner.primary?.model === original.model)
            XCTAssertTrue(original.model.isPlaybackSessionRetired)
        }
    }

    func testTVWatchPendingCancellationRejectsLateChoicesAndPreservesRetainedPlayback() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let first = try XCTUnwrap(SportsTVStation.station(provider: "TV2")).event
        let target = try XCTUnwrap(SportsTVStation.station(provider: "TV3")).event
        let choice = session(for: target)
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { CurrentEventBroadcastPolicy.currentEvent(for: $0, in: []) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: target, sessions: [])); owner.stop() }
        owner.open(event: first, sessions: [session(for: first)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        let attempt = original.model.loadRequestID
        owner.minimize()
        SportsTVWatchPolicy.watch(target, using: owner, catalog: [])
        XCTAssertEqual(owner.pendingSingleEvent?.id, target.id, "The existing pending panel has immediate content")
        XCTAssertNotNil(owner.resolutionMessage)
        await waitForSourceCheck { gate.publish != nil }

        // Cancel, TV departure and backgrounding use this same bounded owner.
        owner.cancelPendingSingleDiscovery()
        await gate.publish?([choice])
        gate.complete(outcome(for: target, sessions: [choice]))
        for _ in 0..<10 { await Task.yield() }

        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.resolutionError)
        XCTAssertFalse(owner.expanded)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(original.model.userWantsPlayback)
    }

    func testTVDepartureCancellationKeepsMountedSingleDiscoveryAndPausedPlayer() async throws {
        let factory = ModelFactory(), gate = SingleDiscoveryGate()
        let channel = try XCTUnwrap(SportsTVStation.station(provider: "TV2")).event
        let first = session(for: channel)
        let second = StreamSession(matchID: channel.id, playableURL: URL(string: "https://example.invalid/alternate-tv.m3u8")!,
            streamType: .hls, providerName: "AS1")
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { CurrentEventBroadcastPolicy.currentEvent(for: $0, in: []) },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { gate.complete(outcome(for: channel, sessions: [])); owner.stop() }
        SportsTVWatchPolicy.watch(channel, using: owner, catalog: [])
        await waitForSourceCheck { gate.publish != nil }
        await gate.publish?([first])
        let pane = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: pane.model)
        let attempt = pane.model.loadRequestID
        owner.minimize()

        owner.cancelPendingSingleDiscovery()
        await gate.publish?([first, second])

        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertTrue(pane.model.isCheckingAdditionalSources)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === pane.model)
        XCTAssertTrue(pane.model.player?.currentItem === item)
        XCTAssertEqual(pane.model.loadRequestID, attempt)
        XCTAssertEqual(pane.model.sessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(pane.model.playbackState, .paused(.native))
        XCTAssertFalse(pane.model.userWantsPlayback)
        XCTAssertFalse(owner.expanded)
    }

    func testRetainedSingleReopenRejectsFailedAndRetiredModels() throws {
        let factory = ModelFactory(), owner = coordinator(factory: factory)
        defer { owner.stop() }
        let match = event("retained-single", home: "Chelsea", away: "Brighton")
        owner.open(event: match, sessions: [session(for: match)])
        let original = try XCTUnwrap(owner.primary)
        _ = installPausedLocalItem(on: original.model)
        owner.minimize()
        let now = Date(timeIntervalSince1970: 1_800_000_060)
        original.model.transition(to: .failed, phase: "Failed")
        XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [match], now: now))
        original.model.transition(to: .paused(.native), phase: "Paused")
        original.model.error = "Failed"
        XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [match], now: now))
        original.model.error = nil
        original.model.cleanup()
        XCTAssertFalse(owner.reopenRetainedSingle(event: match, catalog: [match], now: now))
        XCTAssertFalse(owner.expanded)
    }

    func testHomeAndMatchdayTryRetainedSingleBeforeFreshDiscovery() async throws {
        let factory = ModelFactory()
        let match = event("deferred-retained-watch", date: Int64(Date().addingTimeInterval(-600).timeIntervalSince1970))
        var discoveries = 0, admissions = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { _, _ in
                discoveries += 1
                return self.outcome(for: match, sessions: [], failed: true)
            }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.open(event: match, sessions: [session(for: match)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model), player = original.model.player
        let attempt = original.model.loadRequestID
        owner.minimize()
        owner.watchSingle(match, admission: { current in
            admissions += 1
            XCTAssertEqual(owner.pendingSingleEvent?.id, match.id)
            XCTAssertNotNil(owner.resolutionMessage)
            return current
        })
        XCTAssertNotNil(owner.pendingSingleEvent)
        XCTAssertEqual(admissions, 0)
        await waitForSourceCheck { owner.expanded && owner.pendingSingleEvent == nil }
        XCTAssertEqual(admissions, 1)
        XCTAssertEqual(discoveries, 0)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertTrue(original.model.player === player)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(original.model.userWantsPlayback)
    }

    func testRewatchingTheSamePreparedMatchKeepsItsOwnerAndPausedItem() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        let match = event("same")
        let firstSource = session(for: match)
        owner.open(event: match, sessions: [firstSource])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        let attempt = original.model.loadRequestID
        owner.minimize()

        // Another lookup can supply new ephemeral choices. Reopening the same
        // identity is presentation continuity, not an implicit source replacement.
        owner.open(event: match, sessions: [session(for: match)])

        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertEqual(owner.primaryID, original.id)
        XCTAssertEqual(owner.audioID, original.id)
        XCTAssertTrue(owner.expanded)
        XCTAssertEqual(original.model.activeSession?.id, firstSource.id)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(original.model.isPlaybackSessionRetired)
    }

    func testFreshPreparedSingleReplacesFailedErroredRetiredAndFailedItemOwners() throws {
        for failure in ["state", "error", "retired", "item"] {
            let factory = ModelFactory(), owner = coordinator(factory: factory)
            defer { owner.stop() }
            let match = event("fresh-single-\(failure)")
            let previousSource = session(for: match)
            owner.open(event: match, sessions: [previousSource])
            let original = try XCTUnwrap(owner.primary)
            _ = installPausedLocalItem(on: original.model)
            switch failure {
            case "state": original.model.transition(to: .failed, phase: "Failed")
            case "error": original.model.error = "The previous delivery failed."
            case "retired": original.model.cleanup()
            default:
                original.model.player = AVPlayer(playerItem:
                    FailedPreparedSingleItem(asset: AVMutableComposition()))
                XCTAssertEqual(original.model.player?.currentItem?.status, .failed)
            }
            owner.minimize()
            let fresh = session(for: match)

            owner.open(event: match, sessions: [fresh])

            let replacement = try XCTUnwrap(owner.primary)
            XCTAssertEqual(factory.models.count, 2, failure)
            XCTAssertFalse(replacement.model === original.model, failure)
            XCTAssertNotEqual(replacement.id, original.id, failure)
            XCTAssertTrue(original.model.isPlaybackSessionRetired, failure)
            XCTAssertNil(original.model.player, failure)
            XCTAssertEqual(replacement.model.sessions.map(\.id), [fresh.id], failure)
            XCTAssertEqual(replacement.model.activeSession?.id, fresh.id, failure)
            XCTAssertFalse(replacement.model.sessions.contains { $0.id == previousSource.id }, failure)
            XCTAssertFalse(replacement.model.isPlaybackSessionRetired, failure)
            XCTAssertNil(replacement.model.error, failure)
            XCTAssertEqual(owner.audioID, replacement.id, failure)
            XCTAssertTrue(owner.expanded, failure)
        }
    }

    func testOptionalSourceResolutionReplacesFailedRetainedSingleWithFreshChoices() async throws {
        let factory = ModelFactory()
        let match = event("fresh-optional-single", date: Int64(Date().timeIntervalSince1970) - 60)
        let fresh = session(for: match)
        let resolved = outcome(for: match, sessions: [fresh])
        var resolutions = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in resolutions += 1; return resolved },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.open(event: match, sessions: [session(for: match)])
        let original = try XCTUnwrap(owner.primary)
        _ = installPausedLocalItem(on: original.model)
        original.model.transition(to: .failed, phase: "Failed")
        original.model.error = "The previous delivery failed."
        owner.minimize()

        XCTAssertTrue(owner.checkOptionalSources(for: match, enabledProviders: { ["streamex", "communitysports"] }, currentEvent: { event, _ in event }))
        await waitForSourceCheck { resolutions == 1 && owner.resolutionMessage == nil }

        let replacement = try XCTUnwrap(owner.primary)
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertFalse(replacement.model === original.model)
        XCTAssertTrue(original.model.isPlaybackSessionRetired)
        XCTAssertEqual(replacement.model.sessions.map(\.id), [fresh.id])
        XCTAssertNil(replacement.model.error)
        XCTAssertNil(owner.resolutionError)
        XCTAssertTrue(owner.expanded)
    }

    func testFreshPreparedSinglePreservesHealthyInFlightOwners() throws {
        for state in [LivePlaybackState.idle, .connecting(.native), .preparingNativeHandoff, .recovering(.native)] {
            let factory = ModelFactory(), owner = coordinator(factory: factory)
            defer { owner.stop() }
            let match = event("healthy-in-flight-single")
            let originalSource = session(for: match)
            owner.open(event: match, sessions: [originalSource])
            let original = try XCTUnwrap(owner.primary)
            original.model.transition(to: state, phase: "Retained")
            let attempt = original.model.loadRequestID

            owner.open(event: match, sessions: [session(for: match)])

            XCTAssertEqual(factory.models.count, 1)
            XCTAssertTrue(owner.primary?.model === original.model)
            XCTAssertEqual(original.model.activeSession?.id, originalSource.id)
            XCTAssertEqual(original.model.loadRequestID, attempt)
            XCTAssertEqual(original.model.playbackState, state)
            XCTAssertFalse(original.model.isPlaybackSessionRetired)
        }
    }

    func testFreshPreparedSinglePreservesHealthyNativeFullscreenAndPictureInPicture() throws {
        for presentation in ["fullscreen", "pip"] {
            let factory = ModelFactory(), owner = coordinator(factory: factory)
            defer { owner.stop() }
            let match = event("healthy-single-\(presentation)")
            let originalSource = session(for: match)
            owner.open(event: match, sessions: [originalSource])
            let original = try XCTUnwrap(owner.primary)
            let item = installPausedLocalItem(on: original.model)
            let player = original.model.player, attempt = original.model.loadRequestID
            if presentation == "fullscreen" {
                original.model.isVideoReadyForDisplay = true
                original.model.beginNativeFullscreen()
                XCTAssertNotNil(original.model.nativeFullscreen)
            } else {
                original.model.isPictureInPictureActive = true
            }
            let fullscreen = original.model.nativeFullscreen

            owner.open(event: match, sessions: [session(for: match)])

            XCTAssertEqual(factory.models.count, 1)
            XCTAssertTrue(owner.primary?.model === original.model)
            XCTAssertTrue(original.model.player === player)
            XCTAssertTrue(original.model.player?.currentItem === item)
            XCTAssertEqual(original.model.activeSession?.id, originalSource.id)
            XCTAssertEqual(original.model.loadRequestID, attempt)
            XCTAssertEqual(original.model.playbackState, .paused(.native))
            XCTAssertFalse(original.model.userWantsPlayback)
            XCTAssertTrue(original.model.nativeFullscreen === fullscreen)
            XCTAssertEqual(original.model.isPictureInPictureActive, presentation == "pip")
            if let fullscreen { XCTAssertFalse(fullscreen.isRetired) }
            XCTAssertFalse(original.model.isPlaybackSessionRetired)
        }
    }

    func testTwoPreparedSelectionsKeepRequestedOrderAndReusePrimaryModel() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        let first = event("first"), second = event("second")
        owner.open(event: first, sessions: [session(for: first)])
        let original = try XCTUnwrap(owner.primary)
        let firstItem = installPausedLocalItem(on: original.model)
        let attempt = original.model.loadRequestID

        owner.openMulti(slots: [slot(first), slot(second)])

        XCTAssertEqual(factory.models.count, 2)
        XCTAssertEqual(factory.models.map(\.event.id), [first.id, second.id])
        XCTAssertEqual(owner.panes.map(\.event.id), [first.id, second.id])
        XCTAssertTrue(owner.panes[0].model === original.model)
        XCTAssertEqual(owner.primaryID, original.id)
        XCTAssertEqual(owner.audioID, original.id)
        XCTAssertTrue(owner.isTwo)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertTrue(original.model.player?.currentItem === firstItem)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
        XCTAssertFalse(owner.panes[1].model.ownsRemoteCommands)
        XCTAssertFalse(owner.panes[1].model.isViewingAudioEnabled)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: original.model.remoteCommandOwnerID))

        // Reverse prepared selection order without replacing either owner.
        owner.openMulti(slots: [slot(second), slot(first)])
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertEqual(owner.panes.map(\.event.id), [second.id, first.id])
        XCTAssertTrue(owner.panes[1].model === original.model)
        XCTAssertEqual(owner.primaryID, owner.panes[0].id)
        XCTAssertEqual(owner.audioID, original.id, "Selection order cannot silently change the chosen audio owner")
    }

    func testSwapChangesDisplayOrderOnlyAndKeepsBothAttemptsAndAudioFocus() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("left")), slot(event("right"))])
        let left = owner.panes[0], right = owner.panes[1]
        let leftItem = installPausedLocalItem(on: left.model)
        let rightItem = installPausedLocalItem(on: right.model)
        let leftAttempt = left.model.loadRequestID, rightAttempt = right.model.loadRequestID
        owner.listen(to: right.id)

        owner.swap()
        XCTAssertEqual(owner.displayPanes.map(\.id), [right.id, left.id])
        XCTAssertEqual(owner.panes.map(\.id), [left.id, right.id])
        XCTAssertEqual(owner.primaryID, left.id)
        XCTAssertEqual(owner.audioID, right.id)
        XCTAssertTrue(owner.displayPanes[0].model === right.model)
        XCTAssertTrue(owner.displayPanes[1].model === left.model)
        owner.swap()
        XCTAssertEqual(owner.displayPanes.map(\.id), [left.id, right.id])
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertEqual(left.model.loadRequestID, leftAttempt)
        XCTAssertEqual(right.model.loadRequestID, rightAttempt)
        XCTAssertTrue(left.model.player?.currentItem === leftItem)
        XCTAssertTrue(right.model.player?.currentItem === rightItem)
        XCTAssertEqual(left.model.playbackState, .paused(.native))
        XCTAssertEqual(right.model.playbackState, .paused(.native))
        XCTAssertFalse(left.model.isViewingAudioEnabled)
        XCTAssertTrue(right.model.isViewingAudioEnabled)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: right.model.remoteCommandOwnerID))
    }

    func testKeepingSecondaryRetiresPrimaryAndTransfersRemoteFocusWithoutRestart() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        owner.openMulti(slots: [slot(event("primary")), slot(event("secondary"))])
        let previous = owner.panes[0], survivor = owner.panes[1]
        installPausedLocalItem(on: previous.model)
        let item = installPausedLocalItem(on: survivor.model)
        let attempt = survivor.model.loadRequestID
        owner.swap()

        owner.keepOnly(survivor.id)

        XCTAssertEqual(owner.panes.map(\.id), [survivor.id])
        XCTAssertTrue(owner.primary?.model === survivor.model)
        XCTAssertEqual(owner.primaryID, survivor.id)
        XCTAssertEqual(owner.audioID, survivor.id)
        XCTAssertFalse(owner.isTwo)
        XCTAssertFalse(owner.swapped)
        XCTAssertTrue(owner.expanded)
        XCTAssertTrue(previous.model.isPlaybackSessionRetired)
        XCTAssertNil(previous.model.player)
        XCTAssertFalse(previous.model.ownsRemoteCommands)
        XCTAssertFalse(survivor.model.isPlaybackSessionRetired)
        XCTAssertTrue(survivor.model.ownsRemoteCommands)
        XCTAssertTrue(survivor.model.isViewingAudioEnabled)
        XCTAssertEqual(survivor.model.loadRequestID, attempt)
        XCTAssertTrue(survivor.model.player?.currentItem === item)
        XCTAssertEqual(survivor.model.playbackState, .paused(.native))
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: survivor.model.remoteCommandOwnerID))

        previous.model.cleanup()
        previous.model.setRemoteCommandOwnership(true)
        XCTAssertTrue(NowPlayingManager.shared.isOwned(by: survivor.model.remoteCommandOwnerID),
                      "Late retirement callbacks cannot reclaim the survivor's controls")
    }

    func testSecondaryNativeOrWebPiPClaimsAudioWithoutReplacingOwnersItemsOrAttempts() throws {
        for web in [false, true] {
            let factory = ModelFactory()
            let owner = coordinator(factory: factory)
            defer { owner.stop() }
            owner.openMulti(slots: [slot(event("primary"), web: web), slot(event("secondary"), web: web)])
            let primary = owner.panes[0], secondary = owner.panes[1]
            let primaryItem = installPausedLocalItem(on: primary.model)
            let secondaryItem = installPausedLocalItem(on: secondary.model)
            let attempts = owner.panes.map { $0.model.loadRequestID }
            let sources = owner.panes.map { $0.model.activeSession?.id }
            XCTAssertEqual(secondary.model.isUsingWebEmbed, web, "The fixture must enter its intended delivery mode before its PiP callback")
            XCTAssertEqual(owner.audioID, primary.id)
            XCTAssertFalse(secondary.model.allowsViewingPiP)

            if web {
                secondary.model.handleWebPictureInPictureActivityChanged(true,
                    sourceID: try XCTUnwrap(secondary.model.activeSource).id, requestID: secondary.model.loadRequestID)
            } else {
                // The secondary has no PiP/audio ownership yet, so its foreground
                // system callback performs no native audio preparation.
                secondary.model.handlePictureInPictureActivityChanged(true)
            }
            XCTAssertTrue(secondary.model.isPictureInPictureActive)
            XCTAssertEqual(secondary.model.isWebPictureInPictureActive, web)
            owner.reconcilePictureInPictureOwnership()

            XCTAssertEqual(owner.primaryID, primary.id, "PiP focus is not a different selected fixture")
            XCTAssertEqual(owner.audioID, secondary.id)
            XCTAssertTrue(owner.panes[0].model === primary.model)
            XCTAssertTrue(owner.panes[1].model === secondary.model)
            XCTAssertFalse(primary.model.ownsRemoteCommands)
            XCTAssertFalse(primary.model.isViewingAudioEnabled)
            XCTAssertFalse(primary.model.allowsViewingPiP)
            XCTAssertTrue(secondary.model.ownsRemoteCommands)
            XCTAssertTrue(secondary.model.isViewingAudioEnabled)
            XCTAssertTrue(secondary.model.allowsViewingPiP)
            XCTAssertTrue(NowPlayingManager.shared.isOwned(by: secondary.model.remoteCommandOwnerID))
            XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
            XCTAssertEqual(owner.panes.map { $0.model.activeSession?.id }, sources)
            XCTAssertTrue(primary.model.player?.currentItem === primaryItem)
            XCTAssertTrue(secondary.model.player?.currentItem === secondaryItem)
            XCTAssertEqual(primary.model.playbackState, web ? .paused(.webEmbed) : .paused(.native))
            XCTAssertEqual(secondary.model.playbackState, web ? .paused(.webEmbed) : .paused(.native))
            XCTAssertFalse(primary.model.userWantsPlayback)
            XCTAssertFalse(secondary.model.userWantsPlayback)
            XCTAssertNil(owner.resolutionError)
            XCTAssertEqual(factory.models.count, 2)
            XCTAssertFalse(primary.model.networkPathObserver.isRunning)
            XCTAssertFalse(secondary.model.networkPathObserver.isRunning)
        }
    }

    func testOverlappingPiPClaimsWaitForOldStopBeforeTransferringAudioWithoutAnAlert() throws {
        for web in [false, true] {
            let factory = ModelFactory()
            let owner = coordinator(factory: factory)
            defer { owner.stop() }
            owner.openMulti(slots: [slot(event("old"), web: web), slot(event("new"), web: web)])
            let old = owner.panes[0], next = owner.panes[1]
            let oldItem = installPausedLocalItem(on: old.model)
            let nextItem = installPausedLocalItem(on: next.model)
            let attempts = owner.panes.map { $0.model.loadRequestID }
            XCTAssertEqual(next.model.isUsingWebEmbed, web, "The fixture must enter its intended delivery mode before its PiP callback")
            // An already-running system PiP need only supply its observed flag.
            // Do not ask AVKit to start a real PiP session in this unit test.
            old.model.isPictureInPictureActive = true
            if web {
                next.model.handleWebPictureInPictureActivityChanged(true,
                    sourceID: try XCTUnwrap(next.model.activeSource).id, requestID: next.model.loadRequestID)
            } else { next.model.handlePictureInPictureActivityChanged(true) }
            XCTAssertTrue(next.model.isPictureInPictureActive)
            XCTAssertEqual(next.model.isWebPictureInPictureActive, web)

            for _ in 0..<3 { owner.reconcilePictureInPictureOwnership() }
            XCTAssertEqual(owner.audioID, old.id)
            XCTAssertTrue(NowPlayingManager.shared.isOwned(by: old.model.remoteCommandOwnerID))
            XCTAssertTrue(old.model.isViewingAudioEnabled)
            XCTAssertFalse(next.model.isViewingAudioEnabled)
            XCTAssertNil(owner.resolutionError, "Transient system overlap must not produce an audio-switch error")

            old.model.handlePictureInPictureActivityChanged(false)
            owner.reconcilePictureInPictureOwnership()

            XCTAssertEqual(owner.audioID, next.id)
            XCTAssertTrue(NowPlayingManager.shared.isOwned(by: next.model.remoteCommandOwnerID))
            XCTAssertFalse(old.model.isViewingAudioEnabled)
            XCTAssertTrue(next.model.isViewingAudioEnabled)
            XCTAssertEqual(owner.panes.map { $0.model.loadRequestID }, attempts)
            XCTAssertTrue(old.model.player?.currentItem === oldItem)
            XCTAssertTrue(next.model.player?.currentItem === nextItem)
            XCTAssertEqual(old.model.playbackState, web ? .paused(.webEmbed) : .paused(.native))
            XCTAssertEqual(next.model.playbackState, web ? .paused(.webEmbed) : .paused(.native))
            XCTAssertFalse(old.model.userWantsPlayback)
            XCTAssertFalse(next.model.userWantsPlayback)
            XCTAssertNil(owner.resolutionError)
            XCTAssertEqual(factory.models.count, 2)
        }
    }

    func testStopIsIdempotentAndRetiredModelsCannotRestartOnLaterPresentation() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        owner.openMulti(slots: [slot(event("first")), slot(event("second"))])
        let old = owner.panes.map(\.model)
        for model in old { installPausedLocalItem(on: model) }
        owner.showsSecondMatchPicker = true
        owner.showsContinuity = true
        owner.minimize()

        owner.stop()
        let retiredAttempts = old.map(\.loadRequestID)
        owner.stop()
        owner.expand()
        owner.minimize()
        owner.swap()
        owner.keepOnly(UUID())
        for model in old {
            // This call must stop at retirement before any URL, audio or monitor work.
            model.startPlaybackIfNeeded()
            model.setRemoteCommandOwnership(true)
        }

        XCTAssertFalse(owner.isActive)
        XCTAssertFalse(owner.isTwo)
        XCTAssertTrue(owner.panes.isEmpty)
        XCTAssertNil(owner.primaryID)
        XCTAssertNil(owner.audioID)
        XCTAssertFalse(owner.showsSecondMatchPicker)
        XCTAssertFalse(owner.showsContinuity)
        XCTAssertEqual(factory.models.count, 2)
        XCTAssertEqual(old.map(\.loadRequestID), retiredAttempts)
        for model in old {
            XCTAssertTrue(model.isPlaybackSessionRetired)
            XCTAssertEqual(model.playbackState, .idle)
            XCTAssertFalse(model.ownsRemoteCommands)
            XCTAssertFalse(model.didStartPlayback)
            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertNil(model.player)
            XCTAssertFalse(model.networkPathObserver.isRunning)
            XCTAssertFalse(NowPlayingManager.shared.isOwned(by: model.remoteCommandOwnerID))
        }
    }

    func testRejectedPreparedSelectionsDoNotRetireTheWorkingOwner() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        defer { owner.stop() }
        let match = event("current")
        owner.open(event: match, sessions: [session(for: match)])
        let original = try XCTUnwrap(owner.primary)
        let item = installPausedLocalItem(on: original.model)
        let attempt = original.model.loadRequestID
        let conflicting = event("conflicting", conflict: true)

        owner.open(event: event("empty"), sessions: [])
        owner.open(event: conflicting, sessions: [session(for: conflicting)])
        owner.openMulti(slots: [slot(match)])
        owner.openMulti(slots: [slot(match), slot(match)])
        owner.openMulti(slots: [slot(match), slot(conflicting)])
        owner.listen(to: UUID())
        owner.keepOnly(UUID())
        owner.swap()

        XCTAssertEqual(factory.models.count, 1)
        XCTAssertTrue(owner.primary?.model === original.model)
        XCTAssertEqual(owner.primaryID, original.id)
        XCTAssertEqual(owner.audioID, original.id)
        XCTAssertFalse(original.model.isPlaybackSessionRetired)
        XCTAssertEqual(original.model.loadRequestID, attempt)
        XCTAssertTrue(original.model.player?.currentItem === item)
        XCTAssertEqual(original.model.playbackState, .paused(.native))
    }

    func testAcceptedStoppedPreparedEventsCannotDisplaceOrReopenAnExistingViewingOwner() throws {
        let now = Date()
        let kickoff = Int64(now.addingTimeInterval(-3_600).timeIntervalSince1970)
        func fixture(id: String, away: String, status: SportsFixtureCatalog.Status) -> SportsFixtureMetadata {
            .init(fixtureID: "sports-fixture:premier-league:\(id)", sport: "football",
                competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
                title: "Liverpool vs \(away)", participants: [.init(id: "liverpool", name: "Liverpool"),
                    .init(id: away.lowercased(), name: away)], squad: .init(gender: .men, ageGroup: "senior"),
                status: status, observedAt: now, verified: true, providerObservedAt: now, providerEventIDs: [id])
        }

        for paused in [false, true] {
            let factory = ModelFactory()
            let owner = coordinator(factory: factory)
            defer { owner.stop() }
            let current = event("current", home: "Liverpool", away: "Chelsea", date: kickoff,
                fixture: fixture(id: "current", away: "Chelsea", status: .live))
            owner.open(event: current, sessions: [session(for: current)])
            let original = try XCTUnwrap(owner.primary)
            let item = AVPlayerItem(asset: AVMutableComposition())
            original.model.player = AVPlayer(playerItem: item)
            original.model.transition(to: .playing(.native), phase: "Playing")
            if paused { original.model.togglePlayPause() }
            let attempt = original.model.loadRequestID
            let source = original.model.activeSession?.id
            let state = original.model.playbackState
            let intent = original.model.userWantsPlayback
            owner.minimize()
            let other = event("other-active", home: "Leeds United", away: "Everton", date: kickoff)

            for status in [SportsFixtureCatalog.Status.finished, .cancelled, .postponed] {
                for id in [current.id, "stopped-other"] {
                    let away = id == current.id ? "Chelsea" : "Arsenal"
                    let stopped = event(id, home: "Liverpool", away: away, date: kickoff,
                        fixture: fixture(id: id, away: away, status: status))
                    XCTAssertTrue(stopped.sportsFixture?.verified == true)
                    XCTAssertTrue(MatchStartPolicy(event: stopped).isStopped,
                                  "The prepared event must carry accepted stopped-status evidence")

                    owner.open(event: stopped, sessions: [session(for: stopped)])
                    owner.openMulti(slots: [slot(stopped), slot(other)])
                    owner.openMulti(slots: [slot(other), slot(stopped)])

                    XCTAssertEqual(factory.models.count, 1, "A stopped prepared selection must not create another media owner")
                    XCTAssertEqual(owner.panes.map(\.id), [original.id])
                    XCTAssertTrue(owner.primary?.model === original.model)
                    XCTAssertEqual(owner.primaryID, original.id)
                    XCTAssertEqual(owner.audioID, original.id)
                    XCTAssertTrue(owner.isActive)
                    XCTAssertFalse(owner.isTwo)
                    XCTAssertFalse(owner.expanded, "A new terminal receipt must not reopen an already minimized viewing session")
                    XCTAssertFalse(original.model.isPlaybackSessionRetired,
                                   "Admission rejection is not authority to auto-stop existing in-place viewing")
                    XCTAssertEqual(original.model.loadRequestID, attempt)
                    XCTAssertEqual(original.model.activeSession?.id, source)
                    XCTAssertTrue(original.model.player?.currentItem === item)
                    XCTAssertEqual(original.model.playbackState, state)
                    XCTAssertEqual(original.model.userWantsPlayback, intent)
                    XCTAssertTrue(NowPlayingManager.shared.isOwned(by: original.model.remoteCommandOwnerID))
                }
            }
        }
    }
}

private final class FailedPreparedSingleItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .failed }
}
