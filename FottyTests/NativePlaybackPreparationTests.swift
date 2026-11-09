import XCTest
import AVFoundation
@testable import Fotty

@MainActor
final class NativePlaybackPreparationTests: XCTestCase {
    func testReviewedTVAdvancingWindowRenewsTheSelectedStationOnlyOnceWithoutManualRetry() async throws {
        let now = Date(), station = try XCTUnwrap(SportsTVStation.station(provider: "TV13"))
        let request = StreamPlaybackRequest(event: station.event)
        let binding = try XCTUnwrap(StreamEventBinding(request: request, providerCode: "reviewedtv",
            providerEventID: "reviewed-tv:tnt-sports-2", streamID: "reviewed-tv:tnt-sports-2", manifestRevision: "test",
            verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
        let old = StreamSession(matchID: station.id, playableURL: URL(string: "https://media.example/old.m3u8")!,
            streamType: .hls, providerName: "TV13", expiryTime: now.addingTimeInterval(90),
            canRefresh: true, eventBinding: binding)
        let delivered = StreamSession(matchID: station.id, playableURL: URL(string: "https://media.example/fresh.m3u8")!,
            streamType: .hls, providerName: "TV13", expiryTime: now.addingTimeInterval(90),
            canRefresh: true, eventBinding: binding)
        let fresh = try XCTUnwrap(old.renewingDelivery(from: delivered, for: request, at: now))
        var renewals = 0, validated: [URL] = []
        let model = LivePlayerViewModel(event: station.event, providedSessions: [old], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { url, _ in
                validated.append(url)
                return .invalid("Controlled terminal validation", diagnostics:
                    .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 403))
            },
            refreshSourceDescriptor: { selected, scoped in
                renewals += 1
                XCTAssertEqual(selected.providerName, "TV13")
                XCTAssertEqual(scoped.matchID, station.id)
                return fresh
            }, nativePlaylistIsNonAdvancing: { _ in false }, nativePlaylistIsAdvancing: { _ in true })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        let player = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        model.player = player
        model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: old.playableURL)
        model.transition(to: .playing(.native), phase: "Playing")
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
        model.handleSourceStartupFailure(source, reason: "Stalled.", countsAsStall: true,
            expectedRequestID: attempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
        await model.loadTask?.value
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(validated, [fresh.playableURL])
        XCTAssertEqual(model.activeSession?.providerName, "TV13")
        XCTAssertTrue(model.player === player)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
        let renewedAttempt = model.loadRequestID
        XCTAssertNotEqual(renewedAttempt, attempt)
        // Install an offline stand-in for recovered playback: this second stall
        // belongs to the new current attempt, rather than an old callback.
        player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: fresh.playableURL)
        model.error = nil
        model.transition(to: .playing(.native), phase: "Playing")
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: renewedAttempt)
        model.handleSourceStartupFailure(source, reason: "Stalled.", countsAsStall: true,
            expectedRequestID: renewedAttempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
        await model.loadTask?.value
        XCTAssertEqual(renewals, 1, "Current advancing proof cannot replenish the one automatic recovery budget")
        XCTAssertEqual(validated, [fresh.playableURL])
        XCTAssertEqual(model.loadRequestID, renewedAttempt)
        XCTAssertEqual(model.playbackState, .failed)
    }

    func testLateNativeFatalNotificationCannotRestartATerminalSinglePlayerAttempt() async throws {
        let fixture = try descriptorFixture()
        var renewals = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in XCTFail("A terminal attempt cannot prepare media"); return .invalid("No") },
            refreshSourceDescriptor: { _, _ in renewals += 1; return fixture.fresh })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        model.player = AVPlayer(playerItem: item)
        model.transition(to: .failed, phase: "Choose Broadcast Source")
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.handleNativeItemFailure(item, source: source, requestID: attempt, trigger: .failedToPlayToEnd,
            reportedError: NSError(domain: NSOSStatusErrorDomain, code: -12312))
        await model.loadTask?.value
        XCTAssertEqual(renewals, 0)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .failed)
    }

    func testVerifiedFrozenNativeWindowRenewsDescriptorOnceOnTheSamePlayer() async throws {
        let fixture = try descriptorFixture()
        var refreshes = 0, validated: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Rejected validation cannot activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Rejected validation cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in validated.append(url); return .invalid("Controlled terminal validation") },
            refreshSourceDescriptor: { _, _ in refreshes += 1; return fixture.fresh },
            nativePlaylistIsNonAdvancing: { _ in true })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        let player = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        model.player = player
        model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: fixture.old.playableURL)
        model.transition(to: .playing(.native), phase: "Playing")
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
        model.handleSourceStartupFailure(source, reason: "Frozen.", countsAsStall: true,
            expectedRequestID: attempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
        await model.loadTask?.value
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(validated, [fixture.fresh.playableURL])
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertTrue(model.player === player, "Recovery retains the current native player/presentation owner")
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
        // Repeated callbacks cannot create an unlimited descriptor retry loop.
        model.handleSourceStartupFailure(source, reason: "Frozen.", countsAsStall: true,
            expectedRequestID: attempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
        XCTAssertEqual(refreshes, 1)
    }

    func testFrozenWindowFailedRenewalNeverReplaysTheUnexpiredStalledDelivery() async throws {
        let fixture = try descriptorFixture()
        XCTAssertGreaterThan(fixture.old.expiryTime!, Date(), "This test must not rely on the old lease expiring")
        var refreshes = 0, validations = 0, freshLookups = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("No delivery can activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("No delivery can configure audio"); return .completed([]) },
            validateNativeSource: { _, _ in validations += 1; return .invalid("Old stalled URL must not be validated") },
            refreshSourceDescriptor: { _, _ in refreshes += 1; return nil },
            nativePlaylistIsNonAdvancing: { _ in true },
            freshMatchLookup: { _, _ in freshLookups += 1 })
        defer { model.cleanup() }
        model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
        model.player = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: fixture.old.playableURL)
        model.transition(to: .playing(.native), phase: "Playing")
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
        model.handleSourceStartupFailure(source, reason: "Frozen.", countsAsStall: true,
            expectedRequestID: attempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
        await model.loadTask?.value
        // After the one same-source renewal fails, a decoded match runs one
        // fresh lookup for other sources; an empty result ends honestly.
        for _ in 0..<200 where model.playbackState != .failed { await Task.yield() }
        XCTAssertEqual(freshLookups, 1)
        XCTAssertEqual(refreshes, 1); XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL,
            "Retained historical session data is not a renewed or replayed delivery")
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
    }

    func testObservedNativeWindowCannotRenewWithoutCurrentOwnerIdentityEvidenceOrBudget() async throws {
        for window in ["frozen", "advancing"] {
            let conditions = ["no_evidence", "no_decoded", "old_callback", "budget", "pause", "cancel", "background",
                "multi", "numeric_only", "http403", "unsupported", "invalid_identity", "finished", "cancelled"]
                + (window == "advancing" ? ["unsafe"] : [])
            for condition in conditions {
                let fixture = try descriptorFixture(); var refreshes = 0
                var event = fixture.event, session = fixture.old
                if condition == "invalid_identity" {
                    event = EventReference(id: fixture.event.id, title: fixture.event.title, category: fixture.event.category,
                        date: fixture.event.date.map { $0 + 60 }, poster: nil, popular: false, teams: fixture.event.teams, sources: [])
                }
                if condition == "finished" || condition == "cancelled" {
                    let registered = try registeredRecoveryFixture()
                    event = recoveryEvent(observedAt: registered.now, kickoff: registered.current.kickoffDate!,
                        status: condition == "finished" ? .finished : .cancelled)
                    session = registered.fresh
                    XCTAssertTrue(session.eventBinding!.matchesIdentity(request: StreamPlaybackRequest(event: event), providerCode: "communitysports"),
                        "Terminal status must be rejected even when the binding still identifies the same fixture")
                }
                let model = LivePlayerViewModel(event: event, providedSessions: [session], ownsRemoteCommands: false,
                    prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
                    validateNativeSource: { _, _ in XCTFail("No new validation is authorized"); return .invalid("No") },
                    refreshSourceDescriptor: { _, _ in refreshes += 1; return fixture.fresh },
                    nativePlaylistIsNonAdvancing: { _ in window == "frozen" && condition != "no_evidence" },
                    nativePlaylistIsAdvancing: { _ in window == "advancing" && condition != "no_evidence" })
                model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
                if condition == "multi" { XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .native))) }
                model.player = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
                model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: session.playableURL)
                model.transition(to: .playing(.native), phase: "Playing")
                let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
                if condition != "no_decoded" { model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt) }
                if condition == "budget" { model.nativeStartupRetryAttemptsBySource[source.id] = 1 }
                if condition == "pause" { model.requestPauseFromRemoteCommand() }
                if condition == "cancel" { model.cancelLoading() }
                if condition == "background" { model.handleScenePhaseChange(.background) }
                var details = condition == "numeric_only" ? ["native_log_code": "-12888"] : ["native_failure_trigger": "stall_timeout"]
                if condition == "http403" { details.merge(["native_error_domain": "http", "native_error_code": "403"]) { _, v in v } }
                if condition == "unsupported" {
                    details.merge(["native_error_domain": "url", "native_error_code": String(URLError.unsupportedURL.rawValue)]) { _, v in v }
                }
                if condition == "unsafe" { details.merge(["preparation_stage": "url_preparation", "preparation_reason": "unsafe_redirect"]) { _, v in v } }
                model.handleSourceStartupFailure(source, reason: "Stalled.", countsAsStall: true,
                    expectedRequestID: condition == "old_callback" ? UUID() : attempt, diagnosticDetails: details)
                await model.loadTask?.value
                XCTAssertEqual(refreshes, 0, "\(window): \(condition)")
                model.cleanup()
            }
        }
    }

    func testFrozenWindowExplicitRetryAndPickerReselectionRequireFreshDeliveryAfterFailedLookup() async throws {
        for explicitPath in ["retry", "picker"] {
            let fixture = try descriptorFixture(); var refreshes = 0, validated: [URL] = [], freshLookups = 0
            let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
                prepareAudioSession: { XCTFail("Controlled validation cannot activate audio"); return .completed([]) },
                configureAudioSession: { XCTFail("Controlled validation cannot configure audio"); return .completed([]) },
                validateNativeSource: { url, _ in validated.append(url); return .invalid("Controlled terminal validation") },
                refreshSourceDescriptor: { _, _ in refreshes += 1; return refreshes == 1 ? nil : fixture.fresh },
                nativePlaylistIsNonAdvancing: { _ in true }, currentMatchProviders: { ["communitysports"] },
                freshMatchLookup: { _, _ in freshLookups += 1 })
            model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
            let player = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
            model.player = player
            model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: fixture.old.playableURL)
            model.transition(to: .playing(.native), phase: "Playing")
            let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
            model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
            model.handleSourceStartupFailure(source, reason: "Frozen.", countsAsStall: true,
                expectedRequestID: attempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
            await model.loadTask?.value
            for _ in 0..<200 where model.playbackState != .failed { await Task.yield() }
            XCTAssertEqual(freshLookups, 1, "One fresh lookup before the terminal state: \(explicitPath)")
            XCTAssertEqual(refreshes, 1); XCTAssertTrue(validated.isEmpty)
            XCTAssertEqual(model.playbackState, .failed)
            if explicitPath == "retry" { model.retryCurrentSourceExplicitly() }
            else { model.selectSourceManually(at: 0) }
            await model.loadTask?.value
            XCTAssertEqual(refreshes, 2, "Each explicit gesture may reopen exactly one fresh lookup: \(explicitPath)")
            XCTAssertEqual(validated, [fixture.fresh.playableURL], "The unexpired frozen URL must never reach validation: \(explicitPath)")
            XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
            XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1,
                "A manual lookup does not add an automatic startup retry")
            XCTAssertTrue(model.player === player)
            model.cleanup()
        }
    }

    func testObservedNativeWindowLateRenewalCannotUndoPauseCancellationBackgroundOrReplacement() async throws {
        for window in ["frozen", "advancing"] {
            for interruption in ["pause", "cancel", "background", "replacement"] {
                let fixture = try descriptorFixture(), entered = expectation(description: "Descriptor suspended \(window) \(interruption)")
                var completion: CheckedContinuation<StreamSession?, Never>?, validations = 0, refreshes = 0
                let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
                    prepareAudioSession: { XCTFail("Revoked owner cannot activate audio"); return .completed([]) },
                    configureAudioSession: { XCTFail("Revoked owner cannot configure audio"); return .completed([]) },
                    validateNativeSource: { _, _ in validations += 1; return .invalid("Revoked") },
                    refreshSourceDescriptor: { _, _ in
                        refreshes += 1; entered.fulfill()
                        return await withCheckedContinuation { completion = $0 }
                    }, nativePlaylistIsNonAdvancing: { _ in window == "frozen" },
                    nativePlaylistIsAdvancing: { _ in window == "advancing" })
                defer { completion?.resume(returning: nil); model.cleanup() }
                model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
                model.player = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
                model.streamProxy = LocalStreamProxy(headers: [:], cookies: [], selectedMediaURL: fixture.old.playableURL)
                model.transition(to: .playing(.native), phase: "Playing")
                let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
                model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
                model.handleSourceStartupFailure(source, reason: "Stalled.", countsAsStall: true,
                    expectedRequestID: attempt, diagnosticDetails: ["native_failure_trigger": "stall_timeout"])
                let loading = try XCTUnwrap(model.loadTask)
                await fulfillment(of: [entered], timeout: 2)
                switch interruption {
                case "pause": model.requestPauseFromRemoteCommand()
                case "cancel": model.cancelLoading()
                case "background": model.handleScenePhaseChange(.background)
                default:
                    model.loadCurrentSource(ignoringCircuitBreaker: true)
                    await model.loadTask?.value
                }
                let currentAttempt = model.loadRequestID
                let pending = try XCTUnwrap(completion); completion = nil
                pending.resume(returning: fixture.fresh)
                await loading.value
                XCTAssertEqual(refreshes, 1); XCTAssertEqual(validations, 0, "\(window): \(interruption)")
                XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
                XCTAssertEqual(model.loadRequestID, currentAttempt)
                if interruption == "pause" { XCTAssertFalse(model.userWantsPlayback) }
                if interruption == "replacement" { XCTAssertNotEqual(currentAttempt, attempt) }
                XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
            }
        }
    }

    func testCSMatchRenewalAllowsItsMetadataWindowWithinOneNativeDeadline() throws {
        let session = try registeredRecoveryFixture().old
        func budget(_ context: ViewingPlaybackContext, _ renewing: Bool) -> NativePlaybackStartupDeadline.Budget {
            NativePlaybackStartupDeadline.budget(for: session, context: context, isNativeHandoff: false, renewingMatch: renewing)
        }
        XCTAssertEqual(budget(.single, true), .csMatchRenewal)
        XCTAssertEqual(budget(.single, false), .standard)
        XCTAssertEqual(budget(.watchTwo(engine: .native), true), .standard)
        let clock = NativePlaybackStartupDeadline(startedAt: 0, budget: budget(.single, true))
        XCTAssertGreaterThan(clock.remaining(at: CommunitySportsAddonClient.streamTransportDeadline) ?? 0, 0)
        XCTAssertEqual(clock.remaining(at: 32), 0)
    }

    func testRegisteredDescriptorRecoveryUsesFreshEquivalentReceiptWithoutChangingMountedEvent() async throws {
        let fixture = try registeredRecoveryFixture()
        let oldRequest = StreamPlaybackRequest(event: fixture.oldEvent)
        XCTAssertFalse(fixture.fresh.eventBinding!.matches(request: oldRequest, providerCode: "communitysports"),
            "The originally captured fixture receipt has genuinely expired")
        var validated: [URL] = [], observed: [Date] = []
        let model = LivePlayerViewModel(event: fixture.oldEvent, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Injected validation rejection cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Injected validation rejection cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validated.append(url)
                return .invalid("Controlled rejection", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, request in
                if let receipt = request.preferredEvent?.sportsFixture?.observedAt { observed.append(receipt) }
                return fixture.fresh
            }, currentDescriptorRecoveryRequest: { request in
                RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [fixture.current], at: fixture.now)
            })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        await model.loadTask?.value
        XCTAssertEqual(observed, [fixture.now])
        XCTAssertEqual(validated, [fixture.fresh.playableURL])
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertEqual(model.event.sportsFixture?.observedAt, fixture.oldEvent.sportsFixture?.observedAt,
            "Recovery does not mutate the mounted event or restart another owner")
        XCTAssertNil(model.player?.currentItem)
    }

    func testRegisteredRecoveryRejectsCorrectionsTerminalFactsAndLateChanges() async throws {
        let fixture = try registeredRecoveryFixture(), request = StreamPlaybackRequest(event: fixture.oldEvent)
        let accepted = RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [fixture.current], at: fixture.now)
        XCTAssertEqual(accepted?.preferredEvent?.sportsFixture?.observedAt, fixture.now)
        for current in [recoveryEvent(observedAt: fixture.now, kickoff: fixture.current.kickoffDate!.addingTimeInterval(60)),
            recoveryEvent(observedAt: fixture.now, kickoff: fixture.current.kickoffDate!, home: "Arsenal Women", gender: .women),
            recoveryEvent(observedAt: fixture.now, kickoff: fixture.current.kickoffDate!, home: "Liverpool"),
            recoveryEvent(observedAt: fixture.now, kickoff: fixture.current.kickoffDate!, status: .finished),
            recoveryEvent(observedAt: fixture.now, kickoff: fixture.current.kickoffDate!, status: .cancelled)] {
            XCTAssertNil(RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [current], at: fixture.now))
        }
        let entered = expectation(description: "registered recovery entered")
        var completion: CheckedContinuation<StreamSession?, Never>?, current = fixture.current, validations = 0
        let model = LivePlayerViewModel(event: fixture.oldEvent, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("A late terminal result cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("A late terminal result cannot configure audio"); return .completed([]) },
            validateNativeSource: { _, _ in validations += 1; return .invalid("Unexpected") },
            refreshSourceDescriptor: { _, _ in entered.fulfill(); return await withCheckedContinuation { completion = $0 } },
            currentDescriptorRecoveryRequest: { request in
                RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [current], at: fixture.now)
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let loading = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [entered], timeout: 2)
        current = recoveryEvent(observedAt: fixture.now, kickoff: fixture.current.kickoffDate!, status: .finished)
        let pending = completion; completion = nil; pending?.resume(returning: fixture.fresh)
        await loading.value
        XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
    }

    func testRegisteredTestRecoveryPreservesDayOrdinalAndWholeMatchPeriod() {
        let now = Date(), start = now.addingTimeInterval(-3 * 86_400), end = now.addingTimeInterval(2 * 86_400)
        func event(day: Int, ordinal: Int = 3, endDate: Date? = nil, observedAt: Date) -> EventReference {
            let context = CricketMatchContext(innings: [.init(number: 1, teamID: "icc:1:7", runs: 300, wickets: 5)],
                day: day, matchOrdinal: ordinal, matchEndsAt: ISO8601DateFormatter().string(from: endDate ?? end), phase: .inPlay)
            let metadata = CricketFixtureMetadata(fixtureID: "icc:269792", competitionID: "icc", competitionName: "ICC",
                format: .test, status: .live, observedAt: observedAt, verified: true, context: context,
                homeTeamID: "icc:1:7", awayTeamID: "icc:1:1")
            return .init(id: "cricket-fixture:icc:269792", title: "South Africa vs Australia", category: "cricket",
                date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
                teams: .init(home: .init(name: "South Africa", badge: nil), away: .init(name: "Australia", badge: nil)),
                sources: [], cricketFixture: metadata)
        }
        let old = event(day: 4, observedAt: now.addingTimeInterval(-1_900)), request = StreamPlaybackRequest(event: old)
        XCTAssertNotNil(RegisteredDescriptorRecoveryPolicy.currentRequest(for: request,
            in: [event(day: 4, observedAt: now)], at: now))
        for changed in [event(day: 5, observedAt: now), event(day: 4, ordinal: 2, observedAt: now),
            event(day: 4, endDate: end.addingTimeInterval(3_600), observedAt: now)] {
            XCTAssertNil(RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [changed], at: now))
        }
    }

    func testScheduledRecoveryUsesFreshIdentityWithoutRenewingLiveStatus() throws {
        let now = Date(), kickoff = now.addingTimeInterval(-600)
        let oldStatus = now.addingTimeInterval(-16 * 3_600)
        let scheduled = recoveryEvent(observedAt: oldStatus, kickoff: kickoff, status: .scheduled,
                                      identityObservedAt: now)
        let request = StreamPlaybackRequest(event: scheduled)
        XCTAssertNotNil(RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [scheduled], at: now))
        XCTAssertNotNil(LivePlaybackSourcePolicy.currentMatchForSwitch(scheduled, in: [scheduled], at: now))
        XCTAssertFalse(try XCTUnwrap(scheduled.sportsFixture).isLive(at: now))
        for current in [
            recoveryEvent(observedAt: oldStatus, kickoff: kickoff, status: .scheduled, identityObservedAt: oldStatus),
            recoveryEvent(observedAt: oldStatus, kickoff: kickoff, status: .live, identityObservedAt: now),
            recoveryEvent(observedAt: now, kickoff: kickoff, status: .finished, identityObservedAt: now),
            recoveryEvent(observedAt: now, kickoff: kickoff, status: .cancelled, identityObservedAt: now),
            recoveryEvent(observedAt: oldStatus, kickoff: kickoff.addingTimeInterval(60), status: .scheduled, identityObservedAt: now),
            recoveryEvent(observedAt: oldStatus, kickoff: kickoff, home: "Liverpool", status: .scheduled, identityObservedAt: now)
        ] {
            XCTAssertNil(RegisteredDescriptorRecoveryPolicy.currentRequest(for: request, in: [current], at: now))
            XCTAssertNil(LivePlaybackSourcePolicy.currentMatchForSwitch(scheduled, in: [current], at: now))
        }
    }

    private func recoveryEvent(observedAt: Date, kickoff: Date, home: String = "Arsenal",
                               gender: SportsFixtureCatalog.Squad.Gender = .men,
                               status: SportsFixtureCatalog.Status = .live, identityObservedAt: Date? = nil) -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:recovery", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match, title: "\(home) vs Chelsea",
            participants: [.init(id: home == "Liverpool" ? "liverpool" : "arsenal", name: home), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: gender, ageGroup: "senior"), status: status, observedAt: observedAt, verified: true,
            identityObservedAt: identityObservedAt)
        return .init(id: metadata.fixtureID, title: metadata.title, category: "football", date: Int64(kickoff.timeIntervalSince1970),
            poster: nil, popular: false, teams: .init(home: .init(name: home, badge: nil), away: .init(name: "Chelsea", badge: nil)),
            sources: [], sportsFixture: metadata)
    }

    private func registeredRecoveryFixture() throws -> (now: Date, oldEvent: EventReference, current: EventReference, old: StreamSession, fresh: StreamSession) {
        let now = Date(), oldTime = now.addingTimeInterval(-1_900), kickoff = now.addingTimeInterval(-3_600)
        let oldEvent = recoveryEvent(observedAt: oldTime, kickoff: kickoff), current = recoveryEvent(observedAt: now, kickoff: kickoff)
        func request(_ event: EventReference, observedAt: Date) -> StreamPlaybackRequest {
            let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "a", count: 64), providerCode: "communitysports",
                providerEventID: "nuvio_sport_recovery", streamID: "nuvio_sport_recovery", resourceType: "tv", scope: "football",
                kind: .event, sport: "football", title: "Arsenal vs Chelsea", participants: ["Arsenal", "Chelsea"], start: event.kickoffDate,
                observedAt: observedAt, expiresAt: observedAt.addingTimeInterval(14_400), verification: .dated, issues: [])
            let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "communitysports",
                state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: event.kickoffDate!,
                    participants: ["Arsenal", "Chelsea"], competitionID: "premier-league", squad: event.sportsFixture?.squad),
                expiresAt: observedAt.addingTimeInterval(600))
            let provider = BroadcastRegistrySnapshot.Provider(providerCode: "communitysports", scope: "football", status: .available,
                observedAt: observedAt, expiresAt: record.expiresAt)
            return StreamPlaybackRequest(event: event).usingRegistryMatch(.init(broadcast: record, link: link, provider: provider))
        }
        let oldRequest = request(oldEvent, observedAt: oldTime), currentRequest = request(current, observedAt: now)
        func binding(_ request: StreamPlaybackRequest, at date: Date) throws -> StreamEventBinding {
            try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports", providerEventID: "nuvio_sport_recovery",
                streamID: "nuvio_sport_recovery", manifestRevision: "test", verifiedAt: date, expiresAt: date.addingTimeInterval(90), at: date))
        }
        let old = StreamSession(matchID: oldEvent.id, playableURL: URL(string: "https://media.example/old-registry.m3u8")!, streamType: .hls,
            providerName: "CS3", qualityLabel: "HD", expiryTime: now.addingTimeInterval(-1), canRefresh: true,
            createdAt: oldTime, eventBinding: try binding(oldRequest, at: oldTime))
        let delivered = StreamSession(matchID: current.id, playableURL: URL(string: "https://media.example/new-registry.m3u8")!, streamType: .hls,
            providerName: "CS3", qualityLabel: "HD", expiryTime: now.addingTimeInterval(300), canRefresh: true,
            createdAt: now, eventBinding: try binding(currentRequest, at: now))
        return (now, oldEvent, current, old, try XCTUnwrap(old.renewingDelivery(from: delivered, for: currentRequest, at: now)))
    }

    func testSingleHandoffReadinessFailureCapturesTypedCandidateErrorAndItsRelayBeforeCleanup() throws {
        // Pure composition regression, not a simulated failed AVPlayerItem or
        // decoded-media pass. The production readiness branch captures these
        // same typed observations from its real candidate before cleanup.
        let url = URL(string: "https://media.example/master.m3u8")!
        let activeRelay = LocalStreamProxy(headers: ["Authorization": "active-private"], cookies: [], selectedMediaURL: url)
        let candidateRelay = LocalStreamProxy(headers: ["Authorization": "candidate-private"], cookies: [], selectedMediaURL: url)
        defer { activeRelay.stop(); candidateRelay.stop() }
        let error = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [
            NSLocalizedDescriptionKey: "private https://owner.invalid/stream?secret=value",
            NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -12971)
        ])
        let native = PlayerDiagnosticService().snapshot(error: error, trigger: .itemStatusFailed)
        let candidateDetails = candidateRelay.diagnosticDetails()
        let captured = NativeHandoffCandidateDiagnostic.details(itemStatus: .failed,
            native: native, candidateRelayDetails: candidateDetails)

        candidateRelay.stop()

        XCTAssertEqual(captured["native_item_status"], "failed")
        XCTAssertEqual(captured["native_failure_trigger"], "item_status_failed")
        XCTAssertEqual(captured["native_error_domain"], "avfoundation")
        XCTAssertEqual(captured["native_error_code"], "-11800")
        XCTAssertEqual(captured["native_underlying_domain"], "osstatus")
        XCTAssertEqual(captured["native_underlying_code"], "-12971")
        XCTAssertEqual(captured["relay_id"], candidateDetails["relay_id"])
        XCTAssertNotEqual(captured["relay_id"], activeRelay.diagnosticDetails()["relay_id"],
            "Candidate diagnostics must never borrow the active Web owner's unrelated relay")
        XCTAssertEqual(captured["relay_retained_request_count"], "0")
        XCTAssertNil(captured["relay_http_status"])
        for secret in ["active-private", "candidate-private", "owner.invalid", "secret=value", "https://"] {
            XCTAssertFalse(captured.description.contains(secret))
        }
    }

    func testSingleHandoffMissingNativeCauseAndReadinessTimeoutStayExplicitlyUnknown() {
        for (status, trigger, expectedStatus) in [(AVPlayerItem.Status.failed, NativePlaybackDiagnosticTrigger.itemStatusFailed, "failed"),
                                                 (.unknown, .readinessTimeout, "unknown")] {
            let details = NativeHandoffCandidateDiagnostic.details(itemStatus: status,
                native: PlayerDiagnosticService().snapshot(error: nil, trigger: trigger), candidateRelayDetails: [:])
            XCTAssertEqual(details, ["native_item_status": expectedStatus, "native_failure_trigger": trigger.rawValue])
            XCTAssertNil(details["native_error_code"], "An absent NSError cannot manufacture a cause")
            XCTAssertNil(details["relay_id"], "A direct candidate must not inherit the active owner's relay")
        }
    }

    func testSingleHandoffValidatesTheCookieScopedRelayAndPreservesWebOwnerOnRejection() async throws {
        let event = EventReference(id: "cookie-scoped-handoff", title: "Test Home vs Test Away",
            category: "football", date: 1_800_000_000, poster: nil, popular: false, teams: nil, sources: nil)
        let original = StreamSession(matchID: event.id, playableURL: URL(string: "https://embed.example/watch")!,
            streamType: .unknown, providerName: "StreamEx", requiredHeaders: ["X-Fotty-Web-Embed": "true"])
        var observedURL: URL?
        var observedHeaders: [String: String]?
        let model = LivePlayerViewModel(event: event, providedSessions: [original], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Rejected preflight must not activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Rejected preflight must not configure audio"); return .completed([]) },
            validateNativeSource: { url, headers in
                observedURL = url; observedHeaders = headers
                return .invalid("Controlled validation rejection")
            }, nativeAudioIsolationBackend: .init(isSupported: true, setDisconnected: { _, _ in
                XCTFail("Rejected preflight must not acquire native audio"); return false
            }))
        defer { model.cleanup() }
        model.didApplyLandscape = true
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        let request = model.loadRequestID
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "media.example", .path: "/live",
            .name: "fixture-session", .value: "private-fixture", .secure: "TRUE"]))
        model.handleNativePlaybackCandidate(.init(url: URL(string: "https://media.example/live/master.m3u8")!,
            headers: ["Referer": "https://embed.example/"], cookies: [cookie]), sourceID: original.id, requestID: request)
        XCTAssertTrue(model.canRequestNativePlaybackTransfer)
        model.requestNativePlaybackTransfer()
        let task = try XCTUnwrap(model.nativeHandoffTask)
        await task.value
        let validated = try XCTUnwrap(observedURL)
        XCTAssertEqual(validated.host, "127.0.0.1", "Probe must use the exact cookie-scoped delivery AVPlayer would receive")
        XCTAssertEqual(observedHeaders, [:], "Captured credentials stay in the scoped relay, not the loopback asset")
        XCTAssertNil(validated.query)
        XCTAssertFalse(validated.absoluteString.contains("private-fixture"))
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSession?.id, original.id)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertNil(model.nativeHandoffSession)
        XCTAssertNil(model.player)
        let finished = try XCTUnwrap(FottyQualityStore.shared.records().first {
            $0.details["attempt_id"] == request.uuidString
                && $0.details["diagnostic_phase"] == "candidate_finished"
        })
        XCTAssertNotNil(UUID(uuidString: finished.details["relay_id"] ?? ""))
        XCTAssertEqual(finished.details["relay_retained_request_count"], "0",
                       "An injected rejection is not an observed HTTP resource failure")
        XCTAssertNil(finished.details["relay_http_status"])
    }

    func testCapturedOpaqueMediaKeepsIdentityExpiryAndFreshObservationWithoutMintingTrust() throws {
        let selected = StreamSession(matchID: "preparation", playableURL: URL(string: "https://embed.example/watch")!,
            streamType: .unknown, providerName: "CS2", requiredHeaders: ["X-Fotty-Web-Embed": "true"],
            expiryTime: Date(timeIntervalSince1970: 2_000_000_000), leaseID: "fixture-lease",
            diagnosticMetadata: ["source_key": "fixture-source"], activePeers: 7)
        let candidate = NativeWebPlaybackCandidate(url: URL(string: "https://media.example/opaque")!,
                                                  headers: ["Referer": "https://embed.example/"])
        let evidence = StreamMediaProbeEvidence(contentType: "video/mp4", prefix: Data([0, 1, 2]))
        let captured = NativePlaybackPreparation.capturedSession(from: selected, candidate: candidate, evidence: evidence)
        XCTAssertEqual(captured.id, selected.id)
        XCTAssertEqual(captured.matchID, selected.matchID)
        XCTAssertEqual(captured.expiryTime, selected.expiryTime)
        XCTAssertEqual(captured.leaseID, selected.leaseID)
        XCTAssertEqual(captured.createdAt, selected.createdAt)
        XCTAssertEqual(captured.activePeers, 7)
        XCTAssertEqual(captured.playableURL, candidate.url)
        XCTAssertEqual(captured.requiredHeaders, candidate.headers)
        XCTAssertEqual(captured.streamType, .unknown, "Opaque paths must not invent a declaration")
        XCTAssertEqual(captured.playbackContract.container, .mp4)
        XCTAssertEqual(captured.playbackContract.endpoint, .directMedia)
        XCTAssertFalse(LivePlaybackSourcePolicy.isWebEmbed(captured))
        XCTAssertNil(captured.nativeOriginProfile)
        XCTAssertNil(captured.nativePlaylistProfile)
        XCTAssertEqual(captured.diagnosticMetadata["source_key"], "fixture-source")
    }

    func testItemFactoryUsesCurrentResponseFormatWithoutChangingPlayerOwnershipOrStartingMedia() {
        let url = URL(string: "https://media.example/master.m3u8")!
        let session = StreamSession(matchID: "preparation", playableURL: url, streamType: .hls, providerName: "Fixture")
        let currentMP4 = StreamMediaProbeEvidence(contentType: "video/mp4", prefix: Data([0, 1, 2]))
        let item = NativePlaybackPreparation.makeItem(url: url, headers: ["User-Agent": "Fixture"],
                                                    session: session, evidence: currentMP4)
        XCTAssertNil(item.error)
        XCTAssertEqual(item.status, .unknown)
        XCTAssertEqual(item.preferredForwardBufferDuration, 12, "Progressive mp4 keeps its deeper buffer")
        let live = NativePlaybackPreparation.makeItem(url: url, headers: [:], session: session, evidence: nil)
        XCTAssertEqual(live.preferredForwardBufferDuration, 0, "Live HLS uses AVFoundation's automatic buffer")
        XCTAssertTrue(live.canUseNetworkResourcesForLiveStreamingWhilePaused)
        XCTAssertEqual((item.asset as? AVURLAsset)?.url, url)
        XCTAssertEqual(session.streamType, .hls)
        XCTAssertNil(session.mediaProbeEvidence)
        // No AVPlayer is created, no item is attached, and no audio activation or
        // Play is performed by this factory. Ownership stays with the caller.
    }

    func testDirectPreparationDoesNotStartRelayAndHonorsCancellationBeforeReturningDelivery() async throws {
        let url = URL(string: "https://media.example/opaque.mp4")!
        let delivery = try await NativePlaybackPreparation.prepareDelivery(url: url, headers: [:], cookies: [], requiresRelay: false)
        XCTAssertEqual(delivery.url, url)
        XCTAssertNil(delivery.proxy)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativePlaybackPreparation.prepareDelivery(url: url, headers: [:], cookies: [], requiresRelay: false)
        }
        do { _ = try await task.value; XCTFail("Cancelled work cannot acquire delivery") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSingleDescriptorRefreshAdoptsSameSourceIdentityBeforeInjectedValidation() async throws {
        let fixture = try descriptorFixture()
        var refreshedIDs: [UUID] = [], validatedURLs: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Controlled rejection must not activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Controlled rejection must not configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validatedURLs.append(url)
                return .invalid("Controlled HTTP rejection",
                    diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { session, request in
                refreshedIDs.append(session.id)
                XCTAssertEqual(request.matchID, fixture.event.id)
                return fixture.fresh
            })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        await model.loadTask?.value
        XCTAssertEqual(refreshedIDs, [fixture.old.id])
        XCTAssertEqual(validatedURLs, [fixture.fresh.playableURL])
        XCTAssertEqual(model.activeSession?.id, fixture.old.id)
        XCTAssertEqual(model.activeSession?.providerName, fixture.old.providerName)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertEqual(model.lastFailureKind, .providerUnavailable)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertNil(model.player?.currentItem, "Injected rejection stops before an AVPlayerItem can request media")
    }

    func testPausedOrCancelledSingleDescriptorRefreshCannotAdoptOrValidateLateResult() async throws {
        for interruption in ["pause", "cancel"] {
            let fixture = try descriptorFixture()
            let entered = expectation(description: "\(interruption) descriptor refresh entered")
            var completion: CheckedContinuation<StreamSession?, Never>?
            var validations = 0
            let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
                prepareAudioSession: { XCTFail("Interrupted refresh must not activate audio"); return .completed([]) },
                configureAudioSession: { XCTFail("Interrupted refresh must not configure audio"); return .completed([]) },
                validateNativeSource: { _, _ in
                    validations += 1
                    return .invalid("Controlled HTTP rejection",
                        diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
                }, refreshSourceDescriptor: { _, _ in
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                })
            defer { completion?.resume(returning: nil); model.cleanup() }
            model.didApplyLandscape = true
            XCTAssertTrue(model.configureSingleStreamRanking())
            model.loadCurrentSource(ignoringCircuitBreaker: true)
            let loading = try XCTUnwrap(model.loadTask)
            await fulfillment(of: [entered], timeout: 2)
            guard let pending = completion else {
                model.cancelLoading()
                XCTFail("The injected descriptor lookup did not suspend")
                continue
            }
            if interruption == "pause" {
                model.requestPauseFromRemoteCommand()
                XCTAssertFalse(model.userWantsPlayback, "Explicit Pause must also own a connecting descriptor attempt")
                XCTAssertEqual(model.playbackState, .paused(.native))
            } else {
                model.cancelLoading()
            }
            completion = nil
            pending.resume(returning: fixture.fresh)
            await loading.value
            XCTAssertEqual(validations, 0, interruption)
            XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL, interruption)
            XCTAssertEqual(model.activeSession?.id, fixture.old.id, interruption)
            XCTAssertNil(model.player, interruption)
            if interruption == "pause" { XCTAssertEqual(model.playbackState, .paused(.native)) }
        }
    }

    func testKnownExpiredBoundDeliveryCannotReplayAfterDescriptorRefreshReturnsNil() async throws {
        let fixture = try descriptorFixture(expiredLease: true)
        var refreshes = 0, validations = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Expired delivery must not activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Expired delivery must not configure audio"); return .completed([]) },
            validateNativeSource: { _, _ in
                validations += 1
                return .invalid("Expired URL should never reach validation")
            }, refreshSourceDescriptor: { _, _ in refreshes += 1; return nil })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        await model.loadTask?.value
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
        XCTAssertEqual(model.activeSession?.eventBinding, fixture.old.eventBinding,
            "A failed lookup must not extend metadata authority or claim a fresh descriptor")
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertNil(model.player)
    }

    func testExplicitPlayAfterPausedDescriptorResultWasDiscardedReopensOnlyItsLookup() async throws {
        let fixture = try descriptorFixture()
        let entered = expectation(description: "first descriptor lookup suspended")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var lookups = 0, validations: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Injected rejection must not activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Injected rejection must not configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validations.append(url)
                return .invalid("Controlled HTTP rejection",
                    diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, _ in
                lookups += 1
                if lookups == 1 {
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                }
                return fixture.fresh
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.nativeStartupRetryAttemptsBySource[fixture.old.id] = 1
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let firstLoad = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [entered], timeout: 2)
        guard let pending = completion else {
            model.cancelLoading()
            return XCTFail("Descriptor lookup did not suspend")
        }
        model.requestPauseFromRemoteCommand()
        XCTAssertFalse(model.userWantsPlayback)
        completion = nil
        pending.resume(returning: fixture.fresh)
        await firstLoad.value
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
        XCTAssertTrue(validations.isEmpty)
        XCTAssertNil(model.player)

        model.requestPlayFromRemoteCommand()
        await model.loadTask?.value
        XCTAssertEqual(lookups, 2, "Explicit Play may reopen the discarded lookup without an automatic retry loop")
        XCTAssertEqual(validations, [fixture.fresh.playableURL])
        XCTAssertEqual(model.activeSession?.id, fixture.old.id)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[fixture.old.id], 1,
            "Resuming metadata must not replenish the automatic transport retry budget")
    }

    func testExplicitPlayWhilePausedDescriptorLookupStillWaitsReusesTheSameAttempt() async throws {
        let fixture = try descriptorFixture()
        let entered = expectation(description: "descriptor lookup waiting for explicit resume")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var lookups = 0, validations: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Pending descriptor cannot activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Pending descriptor cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validations.append(url)
                return .invalid("Controlled HTTP rejection",
                    diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, _ in
                lookups += 1
                entered.fulfill()
                return await withCheckedContinuation { completion = $0 }
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let loading = try XCTUnwrap(model.loadTask), attempt = model.loadRequestID
        await fulfillment(of: [entered], timeout: 2)
        guard let pending = completion else {
            model.cancelLoading()
            return XCTFail("Descriptor lookup did not suspend")
        }
        model.requestPauseFromRemoteCommand()
        XCTAssertFalse(model.userWantsPlayback)
        model.requestPlayFromRemoteCommand()
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .connecting(.native))
        XCTAssertEqual(lookups, 1)
        XCTAssertTrue(validations.isEmpty)
        XCTAssertNil(model.player)
        completion = nil
        pending.resume(returning: fixture.fresh)
        await loading.value
        XCTAssertEqual(lookups, 1)
        XCTAssertEqual(validations, [fixture.fresh.playableURL])
        XCTAssertEqual(model.activeSession?.id, fixture.old.id)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
    }

    func testBackgroundedDescriptorPreparationRestartsItsOwnerInsteadOfResumingRetiredItem() async throws {
        let fixture = try descriptorFixture()
        let entered = expectation(description: "descriptor preparation suspended before item replacement")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var lookups = 0, validatedURLs: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("No retired item may acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("No retired item may configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validatedURLs.append(url)
                return .invalid("Controlled rejection", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, _ in
                lookups += 1
                if lookups == 1 {
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                }
                return fixture.fresh
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        let retiredItem = AVPlayerItem(asset: AVMutableComposition())
        model.player = AVPlayer(playerItem: retiredItem)
        model.nativeStartupRetryAttemptsBySource[fixture.old.id] = 1
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let first = try XCTUnwrap(model.loadTask), firstAttempt = model.loadRequestID
        await fulfillment(of: [entered], timeout: 2)
        let pending = try XCTUnwrap(completion); completion = nil

        model.handleScenePhaseChange(.background)
        XCTAssertNil(model.player?.currentItem, "Its old relay was already retired before descriptor preparation")
        pending.resume(returning: fixture.fresh)
        await first.value
        XCTAssertTrue(validatedURLs.isEmpty)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)

        model.handleScenePhaseChange(.active)
        await model.loadTask?.value
        XCTAssertNotEqual(model.loadRequestID, firstAttempt)
        XCTAssertEqual(lookups, 2)
        XCTAssertEqual(validatedURLs, [fixture.fresh.playableURL], "Foreground must prepare a fresh item, not invoke native_resume on the old item")
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[fixture.old.id], 1, "Lifecycle re-entry cannot replenish transport retries")
        XCTAssertNil(model.player?.currentItem)
    }

    func testNativeLoadAlreadyBackgroundedDefersLookupAndRetiredItemUntilForeground() async throws {
        let fixture = try descriptorFixture()
        var lookups = 0, validatedURLs: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Retired item cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Retired item cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validatedURLs.append(url)
                return .invalid("Controlled rejection", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, _ in lookups += 1; return fixture.fresh })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.nativeStartupRetryAttemptsBySource[fixture.old.id] = 1
        model.handleScenePhaseChange(.background)
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let deferredAttempt = model.loadRequestID
        XCTAssertEqual(lookups, 0, "A load beginning in background cannot start descriptor negotiation")
        XCTAssertTrue(validatedURLs.isEmpty)
        XCTAssertNil(model.loadTask)
        XCTAssertNil(model.player?.currentItem)
        XCTAssertEqual(model.playbackState, .paused(.native))

        model.handleScenePhaseChange(.active)
        await model.loadTask?.value
        XCTAssertNotEqual(model.loadRequestID, deferredAttempt)
        XCTAssertEqual(lookups, 1)
        XCTAssertEqual(validatedURLs, [fixture.fresh.playableURL])
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[fixture.old.id], 1)
    }

    func testDeferredPreparationCannotReplayAnExpiredLeaseWhenFreshLookupReturnsNil() async throws {
        let fixture = try descriptorFixture(expiredLease: true)
        let entered = expectation(description: "expired lease negotiation is deferred")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var lookups = 0, validations = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Expired lease cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Expired lease cannot configure audio"); return .completed([]) },
            validateNativeSource: { _, _ in validations += 1; return .invalid("Expired URL cannot be validated") },
            refreshSourceDescriptor: { _, _ in
                lookups += 1
                if lookups == 1 {
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                }
                return nil
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let first = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [entered], timeout: 2)
        let pending = try XCTUnwrap(completion); completion = nil
        model.handleScenePhaseChange(.background)
        pending.resume(returning: fixture.fresh)
        await first.value
        model.handleScenePhaseChange(.active)
        await model.loadTask?.value
        XCTAssertEqual(lookups, 2)
        XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
        XCTAssertEqual(model.activeSession?.eventBinding, fixture.old.eventBinding)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertNil(model.player?.currentItem)
    }

    func testForegroundPreparationCannotBeOverwrittenByLateCancelledBackgroundLookup() async throws {
        let fixture = try descriptorFixture()
        let entered = expectation(description: "old descriptor still suspended on foreground")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var lookups = 0, validatedURLs: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Controlled rejection cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Controlled rejection cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validatedURLs.append(url)
                return .invalid("Controlled rejection", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, _ in
                lookups += 1
                if lookups == 1 {
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                }
                return fixture.fresh
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let oldLoad = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [entered], timeout: 2)
        let pending = try XCTUnwrap(completion); completion = nil
        model.handleScenePhaseChange(.background)
        model.handleScenePhaseChange(.active)
        let foregroundAttempt = model.loadRequestID
        await model.loadTask?.value
        XCTAssertEqual(validatedURLs, [fixture.fresh.playableURL])
        pending.resume(returning: fixture.old)
        await oldLoad.value
        XCTAssertEqual(model.loadRequestID, foregroundAttempt)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertEqual(validatedURLs, [fixture.fresh.playableURL])
        XCTAssertEqual(lookups, 2)
    }

    func testPauseKeepsDeferredNativePreparationPausedUntilExplicitPlay() async throws {
        let fixture = try descriptorFixture()
        let entered = expectation(description: "preparation deferred before Pause")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var lookups = 0, validations = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Deferred Pause cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Deferred Pause cannot configure audio"); return .completed([]) },
            validateNativeSource: { _, _ in
                validations += 1
                return .invalid("Controlled rejection", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { _, _ in
                lookups += 1
                if lookups == 1 {
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                }
                return fixture.fresh
            })
        defer { completion?.resume(returning: nil); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let loading = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [entered], timeout: 2)
        let pending = try XCTUnwrap(completion); completion = nil
        model.handleScenePhaseChange(.background)
        model.requestPauseFromRemoteCommand()
        XCTAssertFalse(model.userWantsPlayback)
        pending.resume(returning: fixture.fresh)
        await loading.value
        model.handleScenePhaseChange(.active)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(lookups, 1)
        XCTAssertEqual(validations, 0)
        model.requestPlayFromRemoteCommand()
        await model.loadTask?.value
        XCTAssertEqual(lookups, 2)
        XCTAssertEqual(validations, 1)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
    }

    func testCancellationOrRetirementRevokesDeferredPreparationBeforeLateCompletionAndForeground() async throws {
        for interruption in ["cancel", "retire"] {
            let fixture = try descriptorFixture()
            let entered = expectation(description: "\(interruption) deferred preparation")
            var completion: CheckedContinuation<StreamSession?, Never>?
            var lookups = 0, validations = 0
            let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
                prepareAudioSession: { XCTFail("Revoked preparation cannot acquire audio"); return .completed([]) },
                configureAudioSession: { XCTFail("Revoked preparation cannot configure audio"); return .completed([]) },
                validateNativeSource: { _, _ in validations += 1; return .invalid("No validation is allowed") },
                refreshSourceDescriptor: { _, _ in
                    lookups += 1
                    entered.fulfill()
                    return await withCheckedContinuation { completion = $0 }
                })
            defer { completion?.resume(returning: nil); model.cleanup() }
            model.didApplyLandscape = true
            XCTAssertTrue(model.configureSingleStreamRanking())
            model.loadCurrentSource(ignoringCircuitBreaker: true)
            let loading = try XCTUnwrap(model.loadTask)
            await fulfillment(of: [entered], timeout: 2)
            let pending = try XCTUnwrap(completion); completion = nil
            model.handleScenePhaseChange(.background)
            if interruption == "cancel" { model.cancelLoading() } else { model.cleanup() }
            let revokedAttempt = model.loadRequestID
            pending.resume(returning: fixture.fresh)
            await loading.value
            model.handleScenePhaseChange(.active)
            await Task.yield()
            XCTAssertEqual(model.loadRequestID, revokedAttempt, interruption)
            XCTAssertEqual(lookups, 1, interruption)
            XCTAssertEqual(validations, 0, interruption)
            XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL, interruption)
            XCTAssertNil(model.player?.currentItem, interruption)
        }
    }

    func testSourceReplacementRevokesDeferredDescriptorAndCannotAdoptItsLateResult() async throws {
        let fixture = try descriptorFixture()
        let replacement = StreamSession(matchID: fixture.event.id, playableURL: URL(string: "https://media.example/replacement.m3u8")!,
            streamType: .hls, providerName: "CS4")
        let entered = expectation(description: "descriptor deferred before source replacement")
        let validating = expectation(description: "replacement reaches its own validator")
        var completion: CheckedContinuation<StreamSession?, Never>?
        var validationCompletion: CheckedContinuation<StreamContractValidator.ValidationResult, Never>?
        var validatedURLs: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old, replacement], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Controlled rejection cannot acquire audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Controlled rejection cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in
                validatedURLs.append(url)
                validating.fulfill()
                return await withCheckedContinuation { validationCompletion = $0 }
            }, refreshSourceDescriptor: { _, _ in
                entered.fulfill()
                return await withCheckedContinuation { completion = $0 }
            }, currentMatchProviders: { ["communitysports"] })
        defer {
            completion?.resume(returning: nil)
            validationCompletion?.resume(returning: .invalid("Cancelled fixture"))
            model.cleanup()
        }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == fixture.old.id })
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        let loading = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [entered], timeout: 2)
        let pending = try XCTUnwrap(completion); completion = nil
        model.handleScenePhaseChange(.background)
        model.requestPauseFromRemoteCommand()
        model.handleScenePhaseChange(.active)
        model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == replacement.id }))
        let replacementLoad = try XCTUnwrap(model.loadTask)
        await fulfillment(of: [validating], timeout: 2)
        let validated = try XCTUnwrap(validationCompletion); validationCompletion = nil
        model.cancelLoading()
        let replacementAttempt = model.loadRequestID
        validated.resume(returning: .invalid("Cancelled fixture"))
        await replacementLoad.value
        pending.resume(returning: fixture.fresh)
        await loading.value
        XCTAssertEqual(model.loadRequestID, replacementAttempt)
        XCTAssertEqual(model.activeSession?.id, replacement.id)
        XCTAssertEqual(model.activeSession?.playableURL, replacement.playableURL)
        XCTAssertEqual(validatedURLs, [replacement.playableURL])
    }

    private func descriptorFixture(expiredLease: Bool = false) throws
        -> (event: EventReference, old: StreamSession, fresh: StreamSession) {
        let now = Date(), oldTime = Date().addingTimeInterval(-120)
        let event = EventReference(id: "descriptor-renewal-fixture", title: "Ipswich Town vs Liverpool",
            category: "football", date: Int64(now.addingTimeInterval(-600).timeIntervalSince1970),
            poster: nil, popular: false,
            teams: .init(home: .init(name: "Ipswich Town", badge: nil), away: .init(name: "Liverpool", badge: nil)),
            sources: [])
        let request = StreamPlaybackRequest(event: event)
        func binding(at time: Date) throws -> StreamEventBinding {
            try XCTUnwrap(StreamEventBinding(request: request, providerCode: "communitysports",
                providerEventID: "nuvio_sport_descriptor_fixture", streamID: "nuvio_sport_descriptor_fixture",
                manifestRevision: "1.2.0", verifiedAt: time, expiresAt: time.addingTimeInterval(90), at: time))
        }
        let old = StreamSession(matchID: event.id, playableURL: URL(string: "https://media.example/old.m3u8")!,
            streamType: .hls, providerName: "CS3", qualityLabel: "HD",
            expiryTime: now.addingTimeInterval(expiredLease ? -1 : 300), canRefresh: true,
            createdAt: oldTime, eventBinding: try binding(at: oldTime))
        let delivered = StreamSession(matchID: event.id, playableURL: URL(string: "https://media.example/fresh.m3u8")!,
            streamType: .hls, providerName: "CS3", qualityLabel: "HD", expiryTime: now.addingTimeInterval(300),
            canRefresh: true, createdAt: now, eventBinding: try binding(at: now))
        let fresh = try XCTUnwrap(old.renewingDelivery(from: delivered, for: request, at: now))
        return (event, old, fresh)
    }

    func testKnownExpiredUnboundMediaLeaseStopsBeforeNativeValidationOrAudio() async throws {
        let fixture = try descriptorFixture()
        let expired = StreamSession(matchID: fixture.event.id, playableURL: fixture.old.playableURL,
            streamType: .hls, providerName: "CS1", expiryTime: Date().addingTimeInterval(-1), canRefresh: false)
        var validations = 0, refreshes = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [expired], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Expired lease cannot activate audio"); return .completed([]) },
            validateNativeSource: { _, _ in validations += 1; return .valid },
            refreshSourceDescriptor: { _, _ in refreshes += 1; return nil })
        defer { model.cleanup() }
        model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource()
        await model.loadTask?.value
        XCTAssertEqual(validations, 0); XCTAssertEqual(refreshes, 0, "An absent binding grants no renewal authority")
        XCTAssertEqual(model.playbackState, .failed)
        let record = try XCTUnwrap(FottyQualityStore.shared.records().last {
            $0.name == "source_failure" && $0.details["source_id"] == expired.id.uuidString
        })
        XCTAssertEqual(record.details["preparation_reason"], "lease_expired")
    }

    func testSingleWatchDiagnosticBindingPrecedesAttemptsAndCannotBeRewrittenAfterStart() async throws {
        let fixture = try descriptorFixture(), watch = UUID()
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.fresh], ownsRemoteCommands: false,
            validateNativeSource: { _, _ in .invalid("Controlled rejection", diagnostics:
                .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 403)) })
        defer { model.cleanup() }
        model.didApplyLandscape = true; model.bindSingleWatchDiagnostics(watch)
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource(); await model.loadTask?.value
        model.bindSingleWatchDiagnostics(UUID())
        model.loadCurrentSource(ignoringCircuitBreaker: true); await model.loadTask?.value
        let attempts = FottyQualityStore.shared.records().filter {
            $0.name == "attempt_started" && $0.details["source_id"] == fixture.fresh.id.uuidString
        }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertTrue(attempts.allSatisfy { $0.details["watch_session_id"] == watch.uuidString })
        XCTAssertEqual(attempts.map { $0.details["attempt_number"] }, ["1", "2"])
    }

    func testNativeContinuityReceiptRequiresNinetySecondsOfOwnedDisplayedProgress() async throws {
        let fixture = try descriptorFixture(), clock = NativeContinuityClock(), watch = UUID()
        let model = await continuityModel(fixture: fixture, clock: clock, watch: watch)
        let player = try XCTUnwrap(model.player as? NativeContinuitySpyPlayer)
        defer { model.cleanup(); clock.release() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.observeSingleContinuity(source)
        for sample in 1...6 {
            try await waitForContinuity { clock.isWaiting }
            player.setMediaTime(Double(sample * 15)); clock.advance()
        }
        try await waitForContinuity { self.continuityRecords(attempt).count == 1 }
        let record = try XCTUnwrap(continuityRecords(attempt).first)
        XCTAssertEqual(record.outcome, .success)
        XCTAssertEqual(record.durationMilliseconds, 90_000)
        XCTAssertEqual(record.details["watch_session_id"], watch.uuidString)
        XCTAssertEqual(record.details["native_continuity_elapsed_ms"], "90000")
        XCTAssertEqual(record.details["native_continuity_media_advance_ms"], "90000")
        XCTAssertEqual(record.details["native_continuity_stalls"], "0")
        XCTAssertEqual(record.details["media_clock_evidence"], "unknown")
        XCTAssertEqual(record.details["live_event_delay_evidence"], "unmeasured")
        XCTAssertEqual(record.details["assignment_basis"], "provider_binding")
        XCTAssertEqual(record.details["programme_observation"], "unobserved",
            "Even sustained displayed media could be a subscription slate or the wrong match.")
        XCTAssertEqual(record.details["upstream_independence_evidence"], "unverified")
        XCTAssertNil(record.details["advertised_media_age_ms"])
        XCTAssertFalse(record.details.description.contains("https://"))
    }

    func testNativeContinuityCannotSurviveDisplayLossPauseBufferingBackgroundOrReplacedAttempt() async throws {
        for interruption in ["no_display", "display_blink", "pause", "buffering", "background", "cancel", "slow_clock"] {
            let fixture = try descriptorFixture(), clock = NativeContinuityClock()
            let model = await continuityModel(fixture: fixture, clock: clock, watch: UUID())
            let player = try XCTUnwrap(model.player as? NativeContinuitySpyPlayer)
            defer { model.cleanup(); clock.release() }
            let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
            if interruption == "no_display" { model.isVideoReadyForDisplay = false }
            model.observeSingleContinuity(source)
            if interruption != "no_display" {
                try await waitForContinuity { clock.isWaiting }
                switch interruption {
                case "display_blink": model.isVideoReadyForDisplay = false; model.isVideoReadyForDisplay = true
                case "pause": model.requestPauseFromRemoteCommand()
                case "buffering": model.handleNativeTimeControlStatusChanged(.waitingToPlayAtSpecifiedRate)
                case "background": model.handleScenePhaseChange(.background)
                case "cancel": model.cancelLoading()
                default: break
                }
                player.setMediaTime(interruption == "slow_clock" ? 10 : 90)
                clock.advance()
            }
            for _ in 0..<30 { await Task.yield() }
            XCTAssertTrue(continuityRecords(attempt).isEmpty, interruption)
            XCTAssertFalse(clock.isWaiting, "An invalid hold must not queue another interval: \(interruption)")
        }
    }

    private func continuityModel(fixture: (event: EventReference, old: StreamSession, fresh: StreamSession),
                                 clock: NativeContinuityClock, watch: UUID) async -> LivePlayerViewModel {
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.fresh], ownsRemoteCommands: false,
            timing: FottyAsyncTiming(monotonicNow: { clock.now }, sleep: { duration in
                if duration == .seconds(15) { try await clock.wait() }
                else { try await Task.sleep(for: duration) }
            }))
        model.bindSingleWatchDiagnostics(watch); model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        // Begin a genuine correlated Watch attempt. Substitute controlled decoded
        // output before asynchronous preparation can touch the test delivery.
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        model.loadTask?.cancel()
        await model.loadTask?.value
        model.player = NativeContinuitySpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        model.isVideoReadyForDisplay = true
        model.transition(to: .playing(.native), phase: "Playing")
        return model
    }

    private func continuityRecords(_ attempt: UUID) -> [FottyQualityRecord] {
        FottyQualityStore.shared.records().filter { $0.name == "native_continuity_90s" && $0.details["attempt_id"] == attempt.uuidString }
    }

    private func waitForContinuity(_ predicate: () -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(2)
        while !predicate(), ContinuousClock.now < end { await Task.yield() }
        XCTAssertTrue(predicate(), "Continuity observation did not reach its controlled interval")
    }

    func testFailedRelayPreparationCannotReturnAUsableCapability() async {
        do {
            _ = try await NativePlaybackPreparation.prepareDelivery(url: URL(string: "https://127.0.0.1/private")!,
                headers: ["Referer": "https://page.example/"], cookies: [], requiresRelay: true)
            XCTFail("An invalid destination must not become a prepared delivery")
        } catch let failure as PlaybackPreparationFailure {
            XCTAssertEqual(failure.qualityDetails["preparation_reason"], "proxy_startup")
        } catch { XCTFail("Expected typed relay preparation failure, got \(type(of: error))") }
    }
}

@MainActor
private final class NativeContinuityClock {
    var now: TimeInterval = 0
    private var pending: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { pending != nil }
    func wait() async throws { try await withCheckedThrowingContinuation { pending = $0 } }
    func advance() { now += 15; release() }
    func release() { let waiter = pending; pending = nil; waiter?.resume() }
}

private final class NativeContinuitySpyPlayer: AVPlayer {
    private let clockLock = NSLock()
    private var seconds: Double = 0
    func setMediaTime(_ value: Double) { clockLock.lock(); seconds = value; clockLock.unlock() }
    override func currentTime() -> CMTime {
        clockLock.lock(); defer { clockLock.unlock() }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
    override var timeControlStatus: AVPlayer.TimeControlStatus { .playing }
    override var rate: Float { get { 1 } set {} }
    override func play() {}
    override func pause() {}
}
