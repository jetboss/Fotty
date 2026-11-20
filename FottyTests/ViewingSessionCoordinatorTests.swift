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
            MatchListViewModel(refreshCricket: { self.cricketSnapshot() }, refreshSports: { self.sportsSnapshot() }, now: { self.now })
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

    func testAcceptedTerminalRefreshVetoesStaleWatchAndLateSingleChoices() async throws {
        for sport in ["football", "cricket"] {
            for cancelled in [false, true] {
                let official = OfficialTerminalGate(sport: sport, cancelled: cancelled)
                let catalog = official.makeCatalog()
                await catalog.refresh()
                let original = try XCTUnwrap(catalog.matches.first)
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
                XCTAssertTrue(catalog.matches.isEmpty)
                XCTAssertTrue(catalog.playbackCatalog.isEmpty, "Terminal admission facts must not become playable/UI rows")
                let terminal = try XCTUnwrap(CurrentEventBroadcastPolicy.currentEvent(for: original,
                    in: catalog.playbackAdmissionCatalog, at: official.now))
                XCTAssertEqual(terminal.id, original.id)
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
                    observedAt: now, verified: true)
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

    func testWatchTapThatFindsNoStreamWritesOnePrivateOutcomeRecord() async throws {
        let started = Date()
        let match = event("watch-outcome-none", home: "Chelsea", away: "Brighton",
            date: Int64(Date().timeIntervalSince1970) - 60, competition: "premier-league")
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { _, _ in
            self.discoveryFailure(for: match, category: .noProviderAvailable, retryable: false)
        }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        owner.watchSingle(match)
        await waitForSourceCheck { owner.resolutionError != nil }
        owner.stop() // A later cancellation cannot add a second record.

        let records = FottyQualityStore.shared.records().filter {
            $0.name == WatchOutcomeRecorder.recordName && $0.timestamp >= started
        }
        XCTAssertEqual(records.count, 1)
        let details = try XCTUnwrap(records.first?.details)
        XCTAssertEqual(details["terminal_outcome"], "no_stream_found")
        XCTAssertEqual(details["failure_kind"], "no_provider_available")
        XCTAssertEqual(details["competition"], "premier-league")
        XCTAssertEqual(details["sport"], "football")
        XCTAssertNil(details["watch_session_id"])
        XCTAssertNil(records.first?.durationMilliseconds)
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

    func testBrowsingDiscoveryFailureIsShownInlineWithItsMatchAndActions() async throws {
        let match = event("inline-discovery-failure", home: "Arsenal", away: "Spurs",
            date: Int64(Date().timeIntervalSince1970) - 60, competition: "premier-league")
        for (category, retryable) in [(StreamFailureCategory.providerTimeout, true), (.noProviderAvailable, false)] {
            let factory = ModelFactory()
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                discoverSinglePlayback: { _, _ in
                    self.discoveryFailure(for: match, category: category, retryable: retryable)
                }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.watchSingle(match)
            await waitForSourceCheck { owner.singleDiscoveryRecovery != nil }

            let failure = try XCTUnwrap(owner.inlineSingleDiscoveryFailure, "\(category)")
            XCTAssertEqual(failure.event.id, match.id)
            XCTAssertEqual(failure.message, owner.resolutionError)
            XCTAssertEqual(failure.canRetry, retryable)
            XCTAssertEqual(failure.canManageSources, category == .noProviderAvailable)

            if failure.canManageSources {
                owner.manageInlineDiscoverySources()
                XCTAssertTrue(owner.showsSourceSettings)
                XCTAssertNil(owner.inlineSingleDiscoveryFailure)
                XCTAssertNil(owner.resolutionError)
            } else {
                owner.dismissInlineDiscoveryFailure()
                XCTAssertNil(owner.inlineSingleDiscoveryFailure)
                XCTAssertNil(owner.resolutionError)
                XCTAssertFalse(owner.showsSourceSettings)
            }
        }
    }

    func testInlineDiscoveryFailureNeverReturnsAsAnAlertOverTheReopenedPlayer() async throws {
        let factory = ModelFactory()
        let match = event("inline-under-mini-player", date: Int64(Date().timeIntervalSince1970) - 60)
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { _, _ in
                self.discoveryFailure(for: match, category: .providerTimeout, retryable: true)
            }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        let retained = event("inline-retained")
        owner.open(event: retained, sessions: [session(for: retained)])
        owner.minimize()
        owner.watchSingle(match)
        await waitForSourceCheck { owner.singleDiscoveryRecovery != nil }
        XCTAssertNotNil(owner.inlineSingleDiscoveryFailure, "Behind the mini-player the tab owns the failure")

        owner.expand()

        XCTAssertTrue(owner.expanded)
        XCTAssertNil(owner.resolutionError, "Expanding must not turn the browsing failure into an alert")
        XCTAssertNil(owner.inlineSingleDiscoveryFailure)
        XCTAssertEqual(owner.primary?.event.id, retained.id)
    }

    func testDiscoveryFailureBehindAnExpandedPlayerKeepsTheShellAlert() async throws {
        let factory = ModelFactory()
        let match = event("expanded-alert-failure", date: Int64(Date().timeIntervalSince1970) - 60)
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            discoverSinglePlayback: { _, _ in
                self.discoveryFailure(for: match, category: .providerTimeout, retryable: true)
            }, currentSingleEvent: { $0 }, catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        let retained = event("expanded-retained")
        owner.open(event: retained, sessions: [session(for: retained)])
        XCTAssertTrue(owner.expanded)
        owner.watchSingle(match)
        await waitForSourceCheck { owner.singleDiscoveryRecovery != nil }

        XCTAssertNotNil(owner.resolutionError)
        XCTAssertNil(owner.inlineSingleDiscoveryFailure, "No tab is visible; the shell alert remains the owner")
        owner.dismissInlineDiscoveryFailure()
        XCTAssertNotNil(owner.resolutionError, "Inline dismissal must not consume an alert-owned failure")
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
                observedAt: now, verified: true)
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
              hasCatalogIdentityConflict: conflict, sportsFixture: fixture, competitionID: competition)
    }

    /// Watch Two admits a started, verified schedule fixture through the
    /// fresh-Watch path. These rows have no provider listing.
    private func pickerFixture(_ slug: String, home: String? = nil, away: String? = nil,
                               category: String = "football", at now: Date, conflict: Bool = false) -> EventReference {
        let home = home ?? "\(slug) home", away = away ?? "\(slug) away"
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:test-cup:\(slug)", sport: category,
            competitionID: "test-cup", competitionName: "Test Cup", eventKind: .match, title: "\(home) vs \(away)",
            participants: [.init(id: "\(slug)-home", name: home), .init(id: "\(slug)-away", name: away)],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: now, verified: true)
        return event(metadata.fixtureID, conflict: conflict, home: home, away: away, category: category,
            date: Int64(now.addingTimeInterval(-60).timeIntervalSince1970), competition: "test-cup", fixture: metadata)
    }

    private func pickerIndex() -> FixtureStreamDiscoveryIndex {
        let index = FixtureStreamDiscoveryIndex()
        index.updateEnabledProviders(["communitysports"], revision: 1)
        return index
    }

    private func session(for event: EventReference, web: Bool = false) -> StreamSession {
        // A direct-media suffix deliberately takes precedence over embed headers
        // in the real classifier. Web fixtures must use an actual embed-shaped
        // endpoint, not an .m3u8 carrying contradictory test metadata.
        let route = web ? "embed/prepared-\(event.id)" : "prepared-\(event.id).m3u8"
        return StreamSession(matchID: event.id, title: event.displayTitle,
            playableURL: URL(string: "https://example.invalid/\(route)")!,
            streamType: web ? .unknown : .hls, providerName: "Score808",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:])
    }

    private func coordinator(factory: ModelFactory,
                             handoffPublisher: SportsHandoffPublisher? = nil,
                             webAudioGate: WebAudioRevocationGate? = nil) -> ViewingSessionCoordinator {
        ViewingSessionCoordinator(handoffPublisher: handoffPublisher,
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
            _ = owner.panes
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

    private func sourceCheckFixture(_ id: String, date: Int64 = 1_800_000_000,
                                    conflict: Bool = false) -> EventReference {
        .init(id: id, title: "Zimbabwe vs Afghanistan", category: "cricket", date: date,
              poster: nil, popular: false,
              teams: .init(home: .init(name: "Zimbabwe", badge: nil),
                           away: .init(name: "Afghanistan", badge: nil)),
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

    func testSharedInitializerRetainsLegacyRankingWithoutSingleOptIn() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let left = event("legacy-ranking-left")
        let choices = seedSlowLegacyAndFastSingleHistory(for: left)
        let shared = LivePlayerViewModel(event: left, providedSessions: [choices.fast, choices.slow],
            ownsRemoteCommands: false, prepareAudioSession: { .completed([]) })
        defer { shared.cleanup() }
        XCTAssertEqual(shared.viewingPlaybackContext, .single,
                       "The initial context is not evidence that a shared model is a single-player destination")
        XCTAssertFalse(shared.usesSingleStreamRanking)
        XCTAssertEqual(shared.activeSession?.id, choices.slow.id)
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

    func testSingleRankingOptInRejectsAlreadyPreparingMountedOrRetiredOwners() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let match = event("ranking-owner-guards")
        let choices = seedSlowLegacyAndFastSingleHistory(for: match)
        for state in ["preparing", "mounted", "retired"] {
            let model = LivePlayerViewModel(event: match, providedSessions: [choices.fast, choices.slow],
                ownsRemoteCommands: false, prepareAudioSession: { .completed([]) })
            defer { model.cleanup() }
            switch state {
            case "preparing": model.sourceAttemptStartedAt = Date()
            case "mounted": model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            default: model.cleanup()
            }
            let attempt = model.loadRequestID, source = model.activeSession?.id
            XCTAssertFalse(model.configureSingleStreamRanking(), state)
            XCTAssertFalse(model.usesSingleStreamRanking, state)
            XCTAssertEqual(model.activeSession?.id, source, state)
            XCTAssertEqual(model.loadRequestID, attempt, state)
            XCTAssertNil(model.loadTask, state)
        }
    }

    func testRuntimeSingleFailoverExcludesCurrentAndExhaustedChoices() throws {
        let restore = preserveSourceRankingDefaults()
        defer { restore() }
        let match = event("ranking-failover", date: Int64(Date().timeIntervalSince1970) - 60)
        let originalMatches = MatchListViewModel.shared.matches
        MatchListViewModel.shared.matches = [match]
        defer { MatchListViewModel.shared.matches = originalMatches }
        let choices = seedSlowLegacyAndFastSingleHistory(for: match)
        let exhausted = rankingSession(for: match, provider: "CS1", host: "exhausted-ranking.example.invalid")
        let spare = rankingSession(for: match, provider: "Score808", host: "spare-ranking.example.invalid")
        LiveSourceHealthStore.recordSuccess(for: exhausted, startupLatencyMs: 900)
        LiveSourceHealthStore.recordSuccess(for: spare, startupLatencyMs: 7_000)
        let model = LivePlayerViewModel(event: match,
            providedSessions: [choices.slow, choices.fast, exhausted, spare],
            ownsRemoteCommands: false, prepareAudioSession: { .completed([]) },
            currentMatchProviders: { ["communitysports", "plaviosports", "score808"] })
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

        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] }) { current, phase in
            admissions += 1
            XCTAssertEqual(phase, admissions == 1 ? .offer : .completion)
            XCTAssertEqual(current.id, fixture.id)
            return fixture
        })
        XCTAssertEqual(owner.resolutionMessage, "Finding a broadcast…")
        await waitForSourceCheck { owner.primary != nil }

        XCTAssertEqual(primaryLookups, 0, "Independent CS discovery must not depend on a primary listing")
        XCTAssertEqual(admissions, 2, "Revalidate the current fixture and source opt-in after lookup")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.matchID, fixture.id)
        XCTAssertEqual(request.homeTeam, "Zimbabwe")
        XCTAssertEqual(request.awayTeam, "Afghanistan")
        XCTAssertEqual(request.kickoffDate, fixture.kickoffDate)
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
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] }) { _, _ in nil })
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
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] }) { _, _ in fixture })
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

    func testOptionalWatchRetryRechecksFixtureAndOpensOnlyFreshMatchingChoice() async throws {
        let factory = ModelFactory(), fixture = sourceCheckFixture("optional-retry")
        let fresh = StreamSession(matchID: fixture.id, title: "CS1",
            playableURL: URL(string: "https://example.invalid/fresh.m3u8")!,
            streamType: .hls, providerName: "CS1")
        var phases: [OptionalSourceLookupPolicy.Phase] = []
        var retries = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            rediscoverSinglePlayback: { request, _ in
                retries += 1
                XCTAssertEqual(request.matchID, fixture.id)
                XCTAssertEqual(request.kickoffDate, fixture.kickoffDate)
                return self.outcome(for: fixture, sessions: [fresh])
            }, cancelPlayback: { _ in })
        defer { owner.stop() }
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["communitysports"] },
            discover: { _, _ in self.outcome(for: fixture, sessions: []) }) { event, phase in
                phases.append(phase)
                return event
            })
        await waitForSourceCheck { owner.canRetrySingleDiscovery }
        XCTAssertEqual(owner.resolutionError, "No playable stream is available for this match right now.")
        XCTAssertNil(owner.primary)
        owner.retrySingleDiscovery()
        await waitForSourceCheck { owner.primary != nil }
        XCTAssertEqual(retries, 1)
        XCTAssertEqual(phases, [.offer, .completion, .offer, .completion])
        XCTAssertEqual(owner.primary?.model.sessions.map(\.id), [fresh.id])
        XCTAssertNil(owner.resolutionError)
    }

    func testOptionalWatchRetryAfterProviderFailureRejectsFixtureThatEnded() async {
        let fixture = sourceCheckFixture("optional-retry-terminal")
        var stillCurrent = true, refreshes = 0
        let owner = ViewingSessionCoordinator(rediscoverSinglePlayback: { _, _ in
            refreshes += 1
            return self.outcome(for: fixture, sessions: [])
        }, cancelPlayback: { _ in })
        defer { owner.stop() }
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["communitysports"] },
            discover: { _, _ in self.discoveryFailure(for: fixture, category: .providerTimeout, retryable: true) },
            currentEvent: { event, _ in stillCurrent ? event : nil }))
        await waitForSourceCheck { owner.canRetrySingleDiscovery }
        XCTAssertEqual(owner.resolutionError, "Discovery failed")
        stillCurrent = false
        owner.retrySingleDiscovery()
        await waitForSourceCheck { owner.resolutionMessage == nil }
        XCTAssertEqual(refreshes, 0)
        XCTAssertFalse(owner.canRetrySingleDiscovery)
        XCTAssertNil(owner.primary)
        XCTAssertEqual(owner.resolutionError, "This fixture could not be confirmed. Refresh the lineup before watching.")
    }

    func testOptionalSourceCheckRejectsDuplicateAndCannotCommitAfterCancellation() async throws {
        for stop in [false, true] {
            let factory = ModelFactory(), gate = ResolutionGate(), fixture = sourceCheckFixture("cancelled")
            let result = outcome(for: fixture, sessions: [session(for: fixture)])
            var cancellations = 0
            let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
                resolvePlayback: { await gate.resolve($0) }, cancelPlayback: { _ in cancellations += 1 })
            defer { gate.completeAll(result); owner.stop() }
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] }) { _, _ in fixture })
            XCTAssertFalse(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] }) { _, _ in fixture })
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
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] }) { _, _ in
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
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] },
            discover: { await gate.resolve($0, publish: $1) }) { event, phase in
                phases.append(phase)
                return event
            })
        XCTAssertEqual(owner.resolutionMessage, "Finding a broadcast…")
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
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] },
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
            XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] },
                discover: { await gate.resolve($0, publish: $1) }) { event, phase in
                    guard changed, phase == .completion else { return event }
                    if change == "revoked" { return nil }
                    if change == "rescheduled" { return self.sourceCheckFixture(event.id, date: 1_800_003_600) }
                    if change == "terminal" {
                        return EventReference(id: event.id, title: event.title, category: event.category, date: event.date,
                            poster: nil, popular: false, teams: event.teams,
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
        XCTAssertTrue(owner.checkOptionalSources(for: fixture, enabledProviders: { ["score808", "communitysports"] },
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
        var enabled: Set<String> = ["score808", "communitysports"]
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
        XCTAssertEqual(enabled, ["score808"])
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

    /// Jet337: a web retirement that timed out kept every later Watch muted.
    /// Once that exact surface reports retirement, the next Watch is audible
    /// without waiting again, even if no player was open when it arrived.
    func testLateWebRetirementAfterCloseDoesNotMuteTheNextWatch() async throws {
        let factory = ModelFactory()
        var oldOwner: UUID?
        var retired = false
        var captures = 0
        let owner = ViewingSessionCoordinator(captureWebAudioRevocation: { model in
            guard model.remoteCommandOwnerID == oldOwner else { return nil }
            captures += 1
            return { retired }
        }, makeModel: factory.make)
        defer { owner.stop() }
        let first = event("stale-web-old"), second = event("stale-web-muted"), third = event("stale-web-next")
        owner.open(event: first, sessions: [session(for: first)])
        oldOwner = try XCTUnwrap(owner.primary).model.remoteCommandOwnerID
        owner.open(event: second, sessions: [session(for: second)])
        let muted = try XCTUnwrap(owner.primary)
        try await XCTUnwrap(owner.audioTransferTask).value
        XCTAssertFalse(muted.model.isViewingAudioEnabled)
        owner.stop()

        retired = true
        owner.open(event: third, sessions: [session(for: third)])
        let next = try XCTUnwrap(owner.primary)
        if let transfer = owner.audioTransferTask { await transfer.value }
        XCTAssertTrue(next.model.isViewingAudioEnabled)
        XCTAssertTrue(next.model.ownsRemoteCommands)
        XCTAssertNil(owner.resolutionError)
        XCTAssertEqual(captures, 1, "The retired surface is waited on, never re-captured")

        let fourth = event("stale-web-after")
        owner.open(event: fourth, sessions: [session(for: fourth)])
        XCTAssertNil(owner.audioTransferTask, "A satisfied retirement is not waited on again")
        XCTAssertTrue(try XCTUnwrap(owner.primary).model.isViewingAudioEnabled)
    }

    func testReplacementSingleWaitsForOldWebMuteBeforeClaimingAudio() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { gate.finishAll(); owner.stop() }
        let first = event("single-web-old"), second = event("single-web-new")
        owner.open(event: first, sessions: [session(for: first, web: true)])
        let old = try XCTUnwrap(owner.primary)
        gate.requiredOwners = [old.model.remoteCommandOwnerID]

        owner.open(event: second, sessions: [session(for: second, web: true)])
        let next = try XCTUnwrap(owner.primary)
        XCTAssertFalse(next.model === old.model)
        XCTAssertTrue(old.model.isPlaybackSessionRetired)
        let transfer = try XCTUnwrap(owner.audioTransferTask)
        await waitFor { gate.tickets.first?.pendingCount == 1 }
        XCTAssertFalse(next.model.isViewingAudioEnabled, "The new owner stays muted until the old Web surface confirms")
        XCTAssertFalse(next.model.ownsRemoteCommands)

        gate.tickets[0].complete(true)
        await transfer.value
        XCTAssertTrue(next.model.isViewingAudioEnabled)
        XCTAssertTrue(next.model.ownsRemoteCommands)
        XCTAssertEqual(owner.audioID, next.id)
        XCTAssertNil(owner.resolutionError)
    }

    func testFailedOldWebMuteKeepsReplacementSingleMutedWithRetryAudio() async throws {
        let factory = ModelFactory(), gate = WebAudioRevocationGate()
        let owner = coordinator(factory: factory, webAudioGate: gate)
        defer { gate.finishAll(); owner.stop() }
        let first = event("single-web-failed-old"), second = event("single-web-failed-new")
        owner.open(event: first, sessions: [session(for: first, web: true)])
        gate.requiredOwners = [try XCTUnwrap(owner.primary).model.remoteCommandOwnerID]

        owner.open(event: second, sessions: [session(for: second, web: true)])
        let next = try XCTUnwrap(owner.primary)
        let transfer = try XCTUnwrap(owner.audioTransferTask)
        await waitFor { gate.tickets.first?.pendingCount == 1 }
        gate.tickets[0].complete(false)
        await transfer.value

        XCTAssertFalse(next.model.isViewingAudioEnabled, "A failed mute confirmation is never permission to unmute")
        XCTAssertFalse(next.model.isPlaybackSessionRetired, "Audio failure does not restart or retire the stream")
        XCTAssertTrue(owner.canRetrySingleAudio)
        XCTAssertNotNil(owner.resolutionError)
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
    }

    func testSameProviderIDWithChangedKickoffOutsideIdentityToleranceCreatesAFreshOwner() throws {
        let original = event("reused")
        for offset: Int64 in [901, 86_400] {
            let changed = event("reused", date: 1_800_000_000 + offset)
            try assertReplacement(original: original, requested: changed)
        }
    }

    func testSameProviderIDWithChangedCompetitionCreatesAFreshOwner() throws {
        let original = event("reused", competition: "premier-league")
        for competition in ["fa-cup", nil] as [String?] {
            let changed = event("reused", competition: competition)
            try assertReplacement(original: original, requested: changed)
        }
    }

    func testSameProviderIDWithFootballTitleOnlySquadChangeCreatesAFreshOwner() throws {
        let original = event("reused", home: "Liverpool", away: "Chelsea")
        for title in ["Liverpool vs Chelsea Women", "Liverpool vs Chelsea U21", "Liverpool vs Chelsea Reserves"] {
            let changed = event("reused", home: "Liverpool", away: "Chelsea", title: title)
            try assertReplacement(original: original, requested: changed)
        }
    }

    func testSameProviderIDWithCricketTitleOnlySquadChangeCreatesAFreshOwner() throws {
        let women = event("reused", home: "New Zealand", away: "South Africa",
                          title: "New Zealand vs South Africa Women", category: "cricket")
        let senior = event("reused", home: "New Zealand", away: "South Africa", category: "cricket")
        for (original, changed) in [(women, senior), (senior, women)] {
            try assertReplacement(original: original, requested: changed)
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
        }
    }

    private func assertReplacement(original: EventReference, requested: EventReference,
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

        owner.open(event: requested, sessions: [prepared])

        let replacement = try XCTUnwrap(owner.primary, file: file, line: line)
        XCTAssertNotEqual(replacement.id, retained.id, file: file, line: line)
        XCTAssertFalse(replacement.model === retained.model, file: file, line: line)
        XCTAssertTrue(retained.model.isPlaybackSessionRetired, file: file, line: line)
        XCTAssertNil(retained.model.player, file: file, line: line)
        XCTAssertEqual(factory.models.count, 2, file: file, line: line)
        XCTAssertEqual(replacement.model.activeSession?.id, prepared.id, file: file, line: line)
        XCTAssertEqual(replacement.event.homeName, requested.homeName, file: file, line: line)
        XCTAssertEqual(replacement.event.awayName, requested.awayName, file: file, line: line)
        XCTAssertEqual(replacement.event.kickoffDate, requested.kickoffDate, file: file, line: line)
        XCTAssertEqual(replacement.event.competitionID, requested.competitionID, file: file, line: line)
        XCTAssertFalse(replacement.model.didStartPlayback, file: file, line: line)
    }

    func testConfirmedHandoffOpensSinglePlayback() async throws {
        let factory = ModelFactory()
        let requested = event("single-handoff", date: Int64(Date().timeIntervalSince1970) - 60)
        let selected = session(for: requested)
        let prepared = outcome(for: requested, sessions: [selected])
        var resolutions = 0
        let owner = ViewingSessionCoordinator(makeModel: { factory.make(event: $0, sessions: $1) },
            resolvePlayback: { _ in resolutions += 1; return prepared },
            catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.incomingHandoff = try SportsHandoffIdentity.make(event: requested)
        owner.incomingEvent = requested

        owner.watchIncoming()
        await waitForSourceCheck { owner.primary?.event.id == requested.id }

        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(factory.models.count, 1)
        XCTAssertEqual(owner.panes.count, 1)
        XCTAssertEqual(owner.primary?.model.activeSession?.id, selected.id)
        XCTAssertEqual(owner.primary?.model.viewingPlaybackContext, .single)
        XCTAssertNil(owner.incomingEvent)
        XCTAssertNil(owner.incomingHandoff)
        XCTAssertNil(owner.resolutionError)
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

        XCTAssertTrue(owner.checkOptionalSources(for: match, enabledProviders: { ["score808", "communitysports"] }, currentEvent: { event, _ in event }))
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

    func testStopIsIdempotentAndRetiredModelsCannotRestartOnLaterPresentation() throws {
        let factory = ModelFactory()
        let owner = coordinator(factory: factory)
        let first = event("first")
        owner.open(event: first, sessions: [session(for: first)])
        let old = owner.panes.map(\.model)
        for model in old { installPausedLocalItem(on: model) }
        owner.showsContinuity = true
        owner.minimize()

        owner.stop()
        let retiredAttempts = old.map(\.loadRequestID)
        owner.stop()
        owner.expand()
        owner.minimize()
        owner.keepOnly(UUID())
        for model in old {
            // This call must stop at retirement before any URL, audio or monitor work.
            model.startPlaybackIfNeeded()
            model.setRemoteCommandOwnership(true)
        }

        XCTAssertFalse(owner.isActive)
        XCTAssertTrue(owner.panes.isEmpty)
        XCTAssertNil(owner.primaryID)
        XCTAssertNil(owner.audioID)
        XCTAssertFalse(owner.showsContinuity)
        XCTAssertEqual(factory.models.count, 1)
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
        owner.listen(to: UUID())
        owner.keepOnly(UUID())

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
                status: status, observedAt: now, verified: true)
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

            for status in [SportsFixtureCatalog.Status.finished, .cancelled, .postponed] {
                for id in [current.id, "stopped-other"] {
                    let away = id == current.id ? "Chelsea" : "Arsenal"
                    let stopped = event(id, home: "Liverpool", away: away, date: kickoff,
                        fixture: fixture(id: id, away: away, status: status))
                    XCTAssertTrue(stopped.sportsFixture?.verified == true)
                    XCTAssertTrue(MatchStartPolicy(event: stopped).isStopped,
                                  "The prepared event must carry accepted stopped-status evidence")

                    owner.open(event: stopped, sessions: [session(for: stopped)])

                    XCTAssertEqual(factory.models.count, 1, "A stopped prepared selection must not create another media owner")
                    XCTAssertEqual(owner.panes.map(\.id), [original.id])
                    XCTAssertTrue(owner.primary?.model === original.model)
                    XCTAssertEqual(owner.primaryID, original.id)
                    XCTAssertEqual(owner.audioID, original.id)
                    XCTAssertTrue(owner.isActive)
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
