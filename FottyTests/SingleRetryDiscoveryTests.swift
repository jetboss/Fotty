import XCTest
import AVFoundation
@testable import Fotty

@MainActor
final class SingleRetryDiscoveryTests: XCTestCase {
    private final class Gate {
        var calls = 0
        var watchID: UUID?
        var publish: (@Sendable ([StreamSession]) async -> Void)?
        var continuation: CheckedContinuation<StreamResolutionOutcome, Never>?
        func resolve(_ request: StreamPlaybackRequest,
                     publish: @escaping @Sendable ([StreamSession]) async -> Void) async -> StreamResolutionOutcome {
            calls += 1
            watchID = request.watchID
            self.publish = publish
            return await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ result: StreamResolutionOutcome) {
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    private func event(_ id: String = "retry-fixture") -> EventReference {
        .init(id: id, title: "Home vs Away", category: "football",
            date: Int64(Date().addingTimeInterval(-600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Home", badge: nil), away: .init(name: "Away", badge: nil)),
            sources: [.init(source: "delta", id: "listed-" + id)])
    }
    private func session(_ event: EventReference, label: String = "StreamEx") -> StreamSession {
        .init(matchID: event.id, playableURL: URL(string: "https://example.invalid/\(label).m3u8")!,
            streamType: .hls, providerName: label)
    }
    private func outcome(_ event: EventReference, _ sessions: [StreamSession] = [], failure: Bool = false) -> StreamResolutionOutcome {
        let d = StreamAttemptDiagnostics(attemptID: "fresh-retry-test", matchID: event.id,
            matchTitle: event.displayTitle, finalState: failure ? .failed : .readyToPlay,
            createdAt: Date(), completedAt: Date(), timeline: [], providerAttempts: [])
        if failure {
            return .failure(.init(category: .providerReturnedEmpty, technicalMessage: "No admitted delivery",
                userMessage: "No broadcast available", retryable: true, fallbackAllowed: true), d)
        }
        return .success(.init(attemptID: "fresh-retry-test", sessions: sessions, diagnostics: d))
    }
    private func model(_ event: EventReference, _ sessions: [StreamSession]) -> LivePlayerViewModel {
        .init(event: event, providedSessions: sessions, ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) })
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Fresh discovery did not reach the expected bounded state")
    }

    func testNormalWatchCarriesItsIdentityIntoTheNewPlaybackOwner() async throws {
        let fixture = event(), gate = Gate()
        let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
            discoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { gate.finish(outcome(fixture)); owner.stop() }
        owner.watchSingle(fixture)
        XCTAssertEqual(owner.pendingSingleEvent?.id, fixture.id)
        try await waitFor { gate.publish != nil }
        let watchID = try XCTUnwrap(gate.watchID)
        await gate.publish?([session(fixture)])
        let model = try XCTUnwrap(owner.primary?.model)
        XCTAssertEqual(model.playbackCorrelation.sessionID, watchID)
    }

    func testRetryUsesFreshDiscoveryAndReplacesFailedOwnerOnlyWhenNewChoicesArrive() async throws {
        let fixture = event(), gate = Gate()
        var ordinaryLookups = 0
        let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
            discoverSinglePlayback: { _, _ in ordinaryLookups += 1; return self.outcome(fixture, failure: true) },
            rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { gate.finish(outcome(fixture)); owner.stop() }
        owner.open(event: fixture, sessions: [session(fixture)])
        let failed = try XCTUnwrap(owner.primary?.model)
        failed.error = "Previous delivery failed"
        XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
        XCTAssertNotNil(owner.singlePlaybackRetryMessage(for: failed))
        XCTAssertTrue(owner.primary?.model === failed)
        XCTAssertFalse(failed.isPlaybackSessionRetired)
        try await waitFor { gate.publish != nil }
        let fresh = session(fixture, label: "CS1")
        await gate.publish?([fresh])
        XCTAssertFalse(owner.primary?.model === failed)
        XCTAssertTrue(failed.isPlaybackSessionRetired)
        XCTAssertEqual(owner.primary?.model.sessions.map(\.id), [fresh.id])
        XCTAssertNil(owner.singlePlaybackRetryMessage(for: failed))
        XCTAssertEqual(ordinaryLookups, 0, "Retry must not select the ordinary cached discovery path")
        XCTAssertEqual(gate.calls, 1)
    }

    func testDuplicateRetrySharesOneLookupAndCancellationRejectsLateChoices() async throws {
        let fixture = event(), gate = Gate()
        let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
            rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
            currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { gate.finish(outcome(fixture)); owner.stop() }
        owner.open(event: fixture, sessions: [session(fixture)])
        let failed = try XCTUnwrap(owner.primary?.model)
        failed.error = "Previous delivery failed"
        XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
        XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
        try await waitFor { gate.publish != nil }
        XCTAssertEqual(gate.calls, 1)
        owner.cancelSinglePlaybackRetry(for: failed)
        await gate.publish?([session(fixture, label: "CS1")])
        gate.finish(outcome(fixture))
        XCTAssertTrue(owner.primary?.model === failed)
        XCTAssertEqual(failed.error, "Previous delivery failed")
        XCTAssertNil(owner.singlePlaybackRetryMessage(for: failed))
        XCTAssertNil(owner.resolutionError)
    }

    func testLateRetryCannotUndoBackgroundCancelledAttemptOrManualReplacement() async throws {
        for change in ["background", "cancel-attempt", "replacement"] {
            let fixture = event(), gate = Gate()
            let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
                rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { $0 }, cancelPlayback: { _ in })
            defer { gate.finish(outcome(fixture)); owner.stop() }
            owner.open(event: fixture, sessions: [session(fixture)])
            let failed = try XCTUnwrap(owner.primary?.model)
            failed.error = "Previous delivery failed"
            XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
            try await waitFor { gate.publish != nil }
            if change == "background" { failed.handleScenePhaseChange(.background) }
            else if change == "cancel-attempt" { failed.cancelLoading() }
            else {
                let replacement = event("different-fixture")
                owner.open(event: replacement, sessions: [session(replacement)])
            }
            let preserved = owner.primary?.model
            await gate.publish?([session(fixture, label: "CS1")])
            gate.finish(outcome(fixture))
            XCTAssertTrue(owner.primary?.model === preserved, change)
            XCTAssertNil(owner.resolutionMessage, change)
        }
    }

    func testCurrentAdmissionChangeVetoesFreshRetryBeforeOrAfterDiscovery() async throws {
        for duringLookup in [false, true] {
            let fixture = event(), gate = Gate()
            var admitted = duringLookup
            let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
                rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { admitted ? $0 : nil }, cancelPlayback: { _ in })
            defer { gate.finish(outcome(fixture)); owner.stop() }
            owner.open(event: fixture, sessions: [session(fixture)])
            let failed = try XCTUnwrap(owner.primary?.model)
            failed.error = "Previous delivery failed"
            XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
            if duringLookup {
                try await waitFor { gate.publish != nil }
                admitted = false
                await gate.publish?([session(fixture, label: "CS1")])
                gate.finish(outcome(fixture))
            }
            try await waitFor { owner.resolutionMessage == nil }
            XCTAssertTrue(owner.primary?.model === failed)
            XCTAssertFalse(failed.isPlaybackSessionRetired)
            XCTAssertEqual(gate.calls, duringLookup ? 1 : 0)
            XCTAssertNotNil(owner.resolutionError)
        }
    }

    func testHealthyRetiredOtherOwnerAndNonSingleContextCannotStartFreshRetry() throws {
        let fixture = event()
        var freshCalls = 0
        let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
            rediscoverSinglePlayback: { _, _ in freshCalls += 1; return self.outcome(fixture) },
            currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.open(event: fixture, sessions: [session(fixture)])
        let active = try XCTUnwrap(owner.primary?.model)
        XCTAssertFalse(owner.retrySinglePlaybackDiscovery(for: active))
        let foreign = model(fixture, [session(fixture)])
        defer { foreign.cleanup() }
        foreign.error = "Foreign failure"
        XCTAssertFalse(owner.retrySinglePlaybackDiscovery(for: foreign))
        active.error = "Failed"
        active.setViewingPlaybackContext(.watchTwo(engine: .native))
        XCTAssertFalse(owner.retrySinglePlaybackDiscovery(for: active))
        active.setViewingPlaybackContext(.single)
        active.cleanup()
        XCTAssertFalse(owner.retrySinglePlaybackDiscovery(for: active))
        XCTAssertEqual(freshCalls, 0)
    }

    func testRetrySupersedesOrdinaryDiscoveryAfterAnEarlyChoiceHasFailed() async throws {
        let fixture = event(), ordinary = Gate(), fresh = Gate()
        let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
            discoverSinglePlayback: { await ordinary.resolve($0, publish: $1) },
            rediscoverSinglePlayback: { await fresh.resolve($0, publish: $1) },
            currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { ordinary.finish(outcome(fixture)); fresh.finish(outcome(fixture)); owner.stop() }
        owner.watchSingle(fixture)
        try await waitFor { ordinary.publish != nil }
        await ordinary.publish?([session(fixture)])
        let failed = try XCTUnwrap(owner.primary?.model)
        failed.error = "Early unsupported choice failed while another lane is pending"
        XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
        XCTAssertNotNil(owner.singlePlaybackRetryMessage(for: failed))
        try await waitFor { fresh.publish != nil }
        let newChoice = session(fixture, label: "CS1")
        await fresh.publish?([newChoice])
        XCTAssertEqual(fresh.calls, 1)
        XCTAssertFalse(owner.primary?.model === failed)
        XCTAssertEqual(owner.primary?.model.sessions.map(\.id), [newChoice.id])
        await ordinary.publish?([session(fixture, label: "AS1")])
        XCTAssertEqual(owner.primary?.model.sessions.map(\.id), [newChoice.id], "Cancelled ordinary discovery cannot append to the fresh owner")
    }

    func testFailureOnlyCompletionCannotPublishAnAlertForChangedRetryOwnership() async throws {
        for background in [false, true] {
            let fixture = event(), gate = Gate()
            let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
                rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { $0 }, cancelPlayback: { _ in })
            defer { gate.finish(outcome(fixture)); owner.stop() }
            owner.open(event: fixture, sessions: [session(fixture)])
            let failed = try XCTUnwrap(owner.primary?.model)
            failed.error = "Original failure"
            XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
            try await waitFor { gate.publish != nil }
            if background { failed.handleScenePhaseChange(.background) }
            else { failed.cancelLoading() }
            // No partial choices: the final failure itself must recheck owner.
            gate.finish(outcome(fixture, failure: true))
            try await waitFor { owner.resolutionMessage == nil }
            XCTAssertNil(owner.resolutionError)
            XCTAssertFalse(owner.canRetrySingleDiscovery)
            XCTAssertTrue(owner.primary?.model === failed)
            XCTAssertEqual(failed.error, "Original failure")
        }
    }

    func testWatchReopensMountedOwnerWhileItsOriginalLateSourceLanesAreStillPending() async throws {
        let fixture = event(), ordinary = Gate()
        let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
            discoverSinglePlayback: { await ordinary.resolve($0, publish: $1) },
            currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { ordinary.finish(outcome(fixture)); owner.stop() }
        owner.watchSingle(fixture)
        try await waitFor { ordinary.publish != nil }
        await ordinary.publish?([session(fixture)])
        let retained = try XCTUnwrap(owner.primary?.model)
        let item = AVPlayerItem(asset: AVMutableComposition())
        retained.player = AVPlayer(playerItem: item)
        retained.transition(to: .paused(.native), phase: "Paused")
        let attempt = retained.loadRequestID
        owner.minimize()
        owner.watchSingle(fixture, admission: { $0 })
        XCTAssertNotNil(owner.resolutionMessage)
        try await waitFor { owner.expanded && owner.pendingSingleEvent == nil }
        XCTAssertTrue(owner.primary?.model === retained)
        XCTAssertTrue(retained.player?.currentItem === item)
        XCTAssertEqual(retained.loadRequestID, attempt)
        XCTAssertEqual(retained.playbackState, .paused(.native))
        XCTAssertEqual(ordinary.calls, 1)
    }

    func testAlertRetryAfterFreshLookupFailureKeepsProgressCancellationAndOwnerFences() async throws {
        for change in ["cancel", "background", "cancel-attempt"] {
            let fixture = event(), gate = Gate()
            let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
                rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { $0 }, cancelPlayback: { _ in })
            defer { gate.finish(outcome(fixture)); owner.stop() }
            owner.open(event: fixture, sessions: [session(fixture)])
            let failed = try XCTUnwrap(owner.primary?.model)
            failed.error = "Original failure"
            XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
            try await waitFor { gate.calls == 1 }
            gate.finish(outcome(fixture, failure: true))
            try await waitFor { owner.canRetrySingleDiscovery }
            owner.retrySingleDiscovery()
            XCTAssertNotNil(owner.singlePlaybackRetryMessage(for: failed), change)
            try await waitFor { gate.calls == 2 }
            if change == "cancel" { owner.cancelSinglePlaybackRetry(for: failed) }
            else if change == "background" { failed.handleScenePhaseChange(.background) }
            else { failed.cancelLoading() }
            await gate.publish?([session(fixture, label: "CS1")])
            gate.finish(outcome(fixture))
            try await waitFor { owner.resolutionMessage == nil }
            XCTAssertTrue(owner.primary?.model === failed, change)
            XCTAssertNil(owner.resolutionError, change)
            XCTAssertNil(owner.singlePlaybackRetryMessage(for: failed), change)
        }
    }

    func testObsoleteAlertRetryCannotGrantAFreshOwnerAfterAttemptOrBackgroundChanged() async throws {
        for background in [false, true] {
            let fixture = event(), gate = Gate()
            let owner = ViewingSessionCoordinator(makeModel: { self.model($0, $1) },
                rediscoverSinglePlayback: { await gate.resolve($0, publish: $1) },
                currentSingleEvent: { $0 }, cancelPlayback: { _ in })
            defer { gate.finish(outcome(fixture)); owner.stop() }
            owner.open(event: fixture, sessions: [session(fixture)])
            let failed = try XCTUnwrap(owner.primary?.model)
            failed.error = "Original failure"
            XCTAssertTrue(owner.retrySinglePlaybackDiscovery(for: failed))
            try await waitFor { gate.calls == 1 }
            gate.finish(outcome(fixture, failure: true))
            try await waitFor { owner.canRetrySingleDiscovery }
            if background { failed.handleScenePhaseChange(.background) }
            else { failed.cancelLoading() }
            owner.retrySingleDiscovery()
            XCTAssertEqual(gate.calls, 1)
            XCTAssertNil(owner.resolutionMessage)
            XCTAssertNil(owner.resolutionError)
            XCTAssertFalse(owner.canRetrySingleDiscovery)
            XCTAssertTrue(owner.primary?.model === failed)
        }
    }
}
