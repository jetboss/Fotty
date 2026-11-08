import XCTest
import AVFoundation
@testable import Fotty

@MainActor
final class LivePlayerRetryLifecycleTests: XCTestCase {
    func testWrongProgrammeSurvivesOnlyAnAdmittedRotationOfTheSameChannelAndStream() throws {
        let event = singleDiscoveryFixture(id: "sports-fixture:premier-league:rotation-\(UUID().uuidString)")
        let now = Date(), providerEvent = "event17"
        func choice(_ channel: Int, token: String, stream: String = "stream17", bound: Bool = true) throws -> StreamSession {
            let binding = try XCTUnwrap(StreamEventBinding(request: .init(event: event), providerCode: "flixstreams",
                providerEventID: providerEvent, streamID: stream, manifestRevision: "one",
                verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
            let url = try XCTUnwrap(URL(string: "https://free.flixnest.app/dlstreams/stream/dlstreams%3Achannel%3A\(channel).m3u8?t=\(token)"))
            XCTAssertTrue(FlixStreamsAddonClient.isAdmittedDelivery(url))
            return .init(matchID: event.id, playableURL: url, streamType: .hls, providerName: "FS1",
                createdAt: now, eventBinding: bound ? binding : nil)
        }
        let original = try choice(5, token: "old"), rotated = try choice(5, token: "new")
        LiveSourceHealthStore.recordMatchOutcome(.wrongProgramme, for: original.legacySource, fixtureID: event.id,
            watchID: UUID(), at: now, session: original)
        XCTAssertNotEqual(original.id, rotated.id)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: rotated, at: now), .wrongProgramme)
        XCTAssertNil(LivePlaybackSourcePolicy.admissionForMatchAlternative(rotated, request: .init(event: event), at: now))
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: try choice(6, token: "new"), at: now), .unknown)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: try choice(5, token: "new", stream: "anotherStream"), at: now), .unknown)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: try choice(5, token: "new", bound: false), at: now), .unknown)
        let exactAlias = try choice(5, token: "old", bound: false)
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: exactAlias, at: now), .wrongProgramme)
        let alternateHeaders = StreamSession(matchID: event.id, playableURL: exactAlias.playableURL, streamType: .hls,
            providerName: "FS1", requiredHeaders: ["Referer": "https://other.example"])
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: alternateHeaders, at: now), .unknown)
    }

    func testOnlyExplicitReportForCurrentSourceRecordsWrongProgramme() async throws {
        let model = try await makePlayer(delay: ControlledWebRetryDelay(), configureSingle: true)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        func observations() -> [FottyQualityRecord] {
            FottyQualityStore.shared.records().filter {
                $0.name == "programme_observation" && $0.details["attempt_id"] == attempt.uuidString
            }
        }
        XCTAssertTrue(observations().isEmpty, "A successful Web start cannot tell which programme was shown.")
        model.reportWrongMatch(for: UUID(), expectedAttempt: attempt)
        model.reportWrongMatch(for: source.id, expectedAttempt: UUID())
        XCTAssertTrue(observations().isEmpty)
        model.reportWrongMatch(for: source.id, expectedAttempt: attempt)
        let wrong = try XCTUnwrap(observations().first)
        XCTAssertEqual(wrong.details["programme_observation"], "viewer_reported_wrong")
        XCTAssertEqual(wrong.details["upstream_independence_evidence"], "unverified")
        XCTAssertEqual(wrong.details["live_event_delay_evidence"], "unmeasured")
        XCTAssertEqual(LiveSourceHealthStore.matchEvidence(for: source, fixtureID: model.event.id), .wrongProgramme)
    }

    func testSingleWebInitialMetricsRemainOnceWhenDecodedStagePrecedesRepeatedOwnerStarts() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay, markPlaying: false)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let before = try sourceHealthSnapshot(for: source)
        // The real bridge emits its decoded diagnostic before the first start
        // callback; interval.hasDecoded alone cannot identify a counted start.
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: attempt)
        model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: attempt, startupLatencyMs: 50)
        let firstRecord = try XCTUnwrap(decodedStartRecords(source: source.id, attempt: attempt).first)
        XCTAssertEqual(firstRecord.details["media_clock_evidence"], "unavailable_web")
        XCTAssertEqual(firstRecord.details["live_event_delay_evidence"], "unmeasured")
        XCTAssertEqual(firstRecord.details["programme_observation"], "unobserved")
        XCTAssertEqual(firstRecord.details["upstream_independence_evidence"], "unverified")
        XCTAssertNil(firstRecord.details["advertised_media_age_ms"])
        let firstHealth = try sourceHealthSnapshot(for: source)
        let firstData = UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1")
        XCTAssertEqual(firstHealth["successCount"] as? Int, (before["successCount"] as? Int ?? 0) + 1)
        XCTAssertEqual(firstHealth["startupSamples"] as? Int, (before["startupSamples"] as? Int ?? 0) + 1)
        for latency in stride(from: 1_000, through: 58_000, by: 3_000) {
            model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: attempt, startupLatencyMs: latency)
        }
        XCTAssertEqual(model.lastStartupLatencyMs, 50)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"), firstData,
                       "New decoded owners in one attempt must not refresh health counts, timestamp or latency")
        let starts = decodedStartRecords(source: source.id, attempt: attempt)
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(starts.first?.durationMilliseconds, 50)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
    }

    func testSingleWebReplacementOwnerStillCompletesRecoveryWithoutRecountingStartup() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup(); delay.advance() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let firstHealth = UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1")
        let retry = try await beginRetry(model, delay: delay)
        model.error = "Controlled recoverable document interruption"
        model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: attempt, startupLatencyMs: 58_000)
        delay.advance()
        await retry.value

        XCTAssertNil(model.error)
        XCTAssertNil(model.webRetryTask)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, source.id)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.lastStartupLatencyMs, 50)
        XCTAssertEqual(decodedStartRecords(source: source.id, attempt: attempt).count, 1)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"), firstHealth)
        XCTAssertEqual(model.autoFailoverCount, 0)
    }

    func testSingleWebStartDuringNativePreparationIsNotAnAdoptedHandoff() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay, markPlaying: false)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let before = try sourceHealthSnapshot(for: source)
        model.transition(to: .preparingNativeHandoff, phase: "Playing")
        model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: attempt, startupLatencyMs: 70)

        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertEqual(model.lastStartupLatencyMs, 70)
        XCTAssertEqual(decodedStartRecords(source: source.id, attempt: attempt).count, 1)
        XCTAssertFalse(FottyQualityStore.shared.records().contains {
            $0.name == "native_handoff" && $0.details["source_id"] == source.id.uuidString
                && $0.details["attempt_id"] == attempt.uuidString
        })
        let after = try sourceHealthSnapshot(for: source)
        XCTAssertEqual(after["successCount"] as? Int, (before["successCount"] as? Int ?? 0) + 1)
    }

    func testSingleWebSameSourceReloadOwnsOneNewInitialHealthAndLatencySample() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource), originalAttempt = model.loadRequestID
        let before = try sourceHealthSnapshot(for: source)
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        await model.loadTask?.value
        let newAttempt = model.loadRequestID
        XCTAssertNotEqual(newAttempt, originalAttempt)
        model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: originalAttempt, startupLatencyMs: 9_000)
        model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: newAttempt, startupLatencyMs: 90)
        model.handleWebEmbedPlaybackStarted(sourceID: source.id, requestID: newAttempt, startupLatencyMs: 900)
        let after = try sourceHealthSnapshot(for: source)
        XCTAssertEqual(after["successCount"] as? Int, (before["successCount"] as? Int ?? 0) + 1)
        XCTAssertEqual(after["startupSamples"] as? Int, (before["startupSamples"] as? Int ?? 0) + 1)
        XCTAssertEqual(after["totalStartupMs"] as? Int, (before["totalStartupMs"] as? Int ?? 0) + 90)
        XCTAssertEqual(model.lastStartupLatencyMs, 90)
        XCTAssertEqual(decodedStartRecords(source: source.id, attempt: originalAttempt).count, 1)
        XCTAssertEqual(decodedStartRecords(source: source.id, attempt: newAttempt).count, 1)
    }

    func testSingleWebStalePausedBackgroundAndRetiredCallbacksCannotRecountStarts() async throws {
        for rejection in ["stale", "paused", "background", "retired"] {
            let delay = ControlledWebRetryDelay()
            let model = try await makePlayer(delay: delay)
            defer { model.cleanup() }
            let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
            let before = UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1")
            switch rejection {
            case "paused": model.togglePlayPause()
            case "background": model.handleScenePhaseChange(.background)
            case "retired": model.cleanup()
            default: break
            }
            model.handleWebEmbedPlaybackStarted(sourceID: source.id,
                requestID: rejection == "stale" ? UUID() : attempt, startupLatencyMs: 58_000)
            XCTAssertEqual(decodedStartRecords(source: source.id, attempt: attempt).count, 1, rejection)
            XCTAssertEqual(model.lastStartupLatencyMs, 50, rejection)
            XCTAssertEqual(UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1"), before, rejection)
        }
    }

    func testSingleStartupEvidenceKeepsNativeHandoffDistinctWithoutASecondInitialSample() {
        var evidence = SinglePlaybackStartEvidence()
        let identity = FottyPlaybackIntervals.Identity(sourceID: UUID(), attemptID: UUID())
        XCTAssertEqual(evidence.admit(.initialStartup, identity: identity), .initialStartup)
        XCTAssertEqual(evidence.admit(.nativeHandoff, identity: identity), .nativeHandoff)
        XCTAssertEqual(evidence.admit(.nativeHandoff, identity: identity), .none)
        XCTAssertEqual(evidence.admit(.initialStartup, identity: identity), .none)
        XCTAssertEqual(evidence.admit(.resumedProgress, identity: identity), .none)
        let next = FottyPlaybackIntervals.Identity(sourceID: identity.sourceID, attemptID: UUID())
        XCTAssertEqual(evidence.admit(.initialStartup, identity: next), .initialStartup)
    }

    func testSingleResumedFirstProofCannotLaterBecomeArtificialStartupLatencyOrHealth() {
        var evidence = SinglePlaybackStartEvidence()
        let identity = FottyPlaybackIntervals.Identity(sourceID: UUID(), attemptID: UUID())
        XCTAssertEqual(evidence.admit(.resumedProgress, identity: identity), .resumedProgress)
        XCTAssertEqual(evidence.admit(.initialStartup, identity: identity), .none)
        XCTAssertEqual(evidence.admit(.resumedProgress, identity: identity), .none)
        XCTAssertEqual(evidence.admit(.nativeHandoff, identity: identity), .nativeHandoff)
        XCTAssertEqual(evidence.admit(.nativeHandoff, identity: identity), .none)
        let otherSource = FottyPlaybackIntervals.Identity(sourceID: UUID(), attemptID: identity.attemptID)
        XCTAssertEqual(evidence.admit(.initialStartup, identity: otherSource), .initialStartup)
    }

    private func decodedStartRecords(source: UUID, attempt: UUID) -> [FottyQualityRecord] {
        FottyQualityStore.shared.records().filter {
            $0.name == "decoded_progress" && $0.details["source_id"] == source.uuidString
                && $0.details["attempt_id"] == attempt.uuidString
        }
    }

    private func sourceHealthSnapshot(for source: StreamSource) throws -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: "fotty.live.sourceHealth.v1") else { return [:] }
        let snapshots = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let key = "web|\(LiveSourceHealthStore.providerFamily(for: source))|\(source.url.host?.lowercased() ?? "unknown-host")"
        return snapshots[key] ?? [:]
    }

    func testCSWatchWrapperWithNestedVideoURLUsesWebOwnerWithoutNativeValidation() async throws {
        var validations = 0
        let model = makeSourcePlayer(sessions: [csSession(web: true)]) { _, _ in
            validations += 1
            return .invalid("Must not validate HTML as native media")
        }
        defer { model.cleanup() }
        model.loadCurrentSource()
        await model.loadTask?.value

        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
        XCTAssertEqual(model.activeSource?.provider, "CS1")
        XCTAssertNil(model.player)
        XCTAssertEqual(validations, 0)
    }

    func testExhaustedInitialASSourcesWaitForOriginalDiscoveryAndStartLateCSWithoutAnotherTap() async throws {
        let (model, initial) = await exhaustedSingleDiscoveryPlayer()
        defer { model.cleanup() }
        let pendingAttempt = model.loadRequestID
        let failed = try XCTUnwrap(FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["source_id"] == model.activeSource?.id.uuidString
        }.max(by: { $0.timestamp < $1.timestamp }))
        let retiredAttempt = try XCTUnwrap(failed.details["attempt_id"].flatMap(UUID.init(uuidString:)))
        let failedSource = try XCTUnwrap(model.activeSource)
        XCTAssertNotEqual(pendingAttempt, retiredAttempt)

        // The failed source's late fatal callback cannot terminate the pending
        // lookup, or grant that rejected403 transport another attempt.
        model.handleSourceStartupFailure(failedSource, reason: "HTTP 403", expectedRequestID: retiredAttempt)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.error)
        XCTAssertTrue(discoveryRecords("terminal_failure", sources: initial).isEmpty)
        let cs = singleDiscoverySession(event: model.event, provider: "CS1", suffix: "late-cs", web: true)

        model.appendDiscoveredSingleSessions([cs], currentEvent: model.event)
        await model.loadTask?.value

        XCTAssertEqual(model.activeSource?.id, cs.id)
        XCTAssertNotEqual(model.loadRequestID, pendingAttempt)
        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
        XCTAssertNil(model.error)
        XCTAssertEqual(model.failedSourceIDs, Set(initial.map(\.id)))
        XCTAssertEqual(discoveryRecords("source_failure", sources: initial).count, 3,
            "Each rejectedAS delivery gets one attempt, never an access-control workaround")
        XCTAssertEqual(model.autoFailoverCount, 3)
        let csAttempt = model.loadRequestID
        model.handleSourceStartupFailure(failedSource, reason: "HTTP 403", expectedRequestID: retiredAttempt)
        XCTAssertEqual(model.activeSource?.id, cs.id)
        XCTAssertEqual(model.loadRequestID, csAttempt)
    }

    func testOwnedSingleDiscoveryContinuesAcrossNewExhaustedDeliveriesWithoutRepeatingFailedSources() async {
        let (model, initial) = await exhaustedSingleDiscoveryPlayer(count: 1,
            enabledProviders: ["plaviosports", "flixstreams", "communitysports"])
        defer { model.cleanup() }
        let rejectedNew = singleDiscoverySession(event: model.event, provider: "FS1", suffix: "new-fs", web: false)
        model.appendDiscoveredSingleSessions([rejectedNew], currentEvent: model.event)
        await model.loadTask?.value
        XCTAssertEqual(model.activeSource?.id, rejectedNew.id)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.isCheckingAdditionalSources)
        let pendingAttempt = model.loadRequestID
        model.appendDiscoveredSingleSessions(initial + [rejectedNew], currentEvent: model.event)
        XCTAssertEqual(model.loadRequestID, pendingAttempt, "A repeated snapshot cannot retry failed deliveries")
        let cs = singleDiscoverySession(event: model.event, provider: "CS1", suffix: "next-cs", web: true)

        model.appendDiscoveredSingleSessions([cs], currentEvent: model.event)
        await model.loadTask?.value

        XCTAssertEqual(model.activeSource?.id, cs.id)
        XCTAssertNotEqual(model.loadRequestID, pendingAttempt)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
        XCTAssertNil(model.error)
        XCTAssertEqual(model.failedSourceIDs, Set((initial + [rejectedNew]).map(\.id)))
        XCTAssertEqual(discoveryRecords("source_failure", sources: initial + [rejectedNew]).count, 2)
        XCTAssertEqual(model.autoFailoverCount, 2)
    }

    func testCompletingOriginalDiscoveryPublishesOneTerminalFailureAndLateAppendCannotReviveIt() async {
        let (model, initial) = await exhaustedSingleDiscoveryPlayer()
        defer { model.cleanup() }
        model.setSingleSourceDiscoveryActive(false)
        model.setSingleSourceDiscoveryActive(false)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isCheckingAdditionalSources)
        XCTAssertEqual(discoveryRecords("terminal_failure", sources: initial).count, 1)
        let terminalAttempt = model.loadRequestID, terminalSource = model.activeSource?.id
        let cs = singleDiscoverySession(event: model.event, provider: "CS1", suffix: "post-completion-cs", web: true)

        model.appendDiscoveredSingleSessions([cs], currentEvent: model.event)

        XCTAssertEqual(model.loadRequestID, terminalAttempt)
        XCTAssertEqual(model.activeSource?.id, terminalSource)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertEqual(discoveryRecords("terminal_failure", sources: initial).count, 1)
    }

    func testPendingSingleDiscoveryCannotOverridePauseCancelManualSelectionBackgroundOrRetirement() async throws {
        for action in ["pause", "cancel", "discovery-cancel", "manual", "background", "retire", "explicit-retry"] {
            let (model, initial) = await exhaustedSingleDiscoveryPlayer(count: 1)
            defer { model.cleanup() }
            let beforeFailures = discoveryRecords("source_failure", sources: initial).count
            switch action {
            case "pause": model.requestPauseFromRemoteCommand()
            case "cancel": model.cancelLoading()
            case "discovery-cancel": model.setSingleSourceDiscoveryActive(false, completed: false)
            case "manual":
                let manual = singleDiscoverySession(event: model.event, provider: "CS2", suffix: "manual-cs", web: true)
                model.appendDiscoveredSingleSessions([manual])
                model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == manual.id }))
                await model.loadTask?.value
            case "background":
                model.handleScenePhaseChange(.background)
                model.handleScenePhaseChange(.active)
                XCTAssertEqual(discoveryRecords("source_failure", sources: initial).count, beforeFailures,
                    "Foreground must not retry the rejected transport")
            case "retire": model.cleanup()
            default:
                model.retryCurrentSourceExplicitly()
                await model.loadTask?.value
            }
            let selected = model.activeSource?.id, attempt = model.loadRequestID, state = model.playbackState
            let late = singleDiscoverySession(event: model.event, provider: "CS1", suffix: "late-after-\(action)", web: true)

            model.appendDiscoveredSingleSessions([late], currentEvent: model.event)

            XCTAssertEqual(model.activeSource?.id, selected, action)
            XCTAssertEqual(model.loadRequestID, attempt, action)
            XCTAssertEqual(model.playbackState, state, action)
            if action == "pause" { XCTAssertFalse(model.userWantsPlayback) }
        }
    }

    func testPendingSingleDiscoveryRequiresFreshMatchingFixtureAndNewMatchingDelivery() async throws {
        for rejection in ["missing-current", "opponent", "date", "conflict", "finished", "foreign-session", "foreign-binding", "expired-binding"] {
            let (model, _) = await exhaustedSingleDiscoveryPlayer(count: 1)
            defer { model.cleanup() }
            let current = model.event, source = model.activeSource?.id, attempt = model.loadRequestID
            var admitted: EventReference? = current
            var candidateEvent = current
            var binding: StreamEventBinding?
            switch rejection {
            case "missing-current": admitted = nil
            case "opponent": admitted = singleDiscoveryFixture(away: "Arsenal", date: current.date)
            case "date": admitted = singleDiscoveryFixture(date: current.date.map { $0 + 60 })
            case "conflict": admitted = singleDiscoveryFixture(date: current.date, conflict: true)
            case "finished": admitted = singleDiscoveryFixture(date: current.date, status: .finished)
            case "foreign-session": candidateEvent = singleDiscoveryFixture(id: "sports-fixture:premier-league:another", date: current.date)
            default:
                let boundEvent = rejection == "foreign-binding"
                    ? singleDiscoveryFixture(away: "Arsenal", date: current.date) : current
                let now = Date(), verified = rejection == "expired-binding" ? now.addingTimeInterval(-100) : now
                binding = try XCTUnwrap(StreamEventBinding(request: .init(event: boundEvent), providerCode: "communitysports",
                    providerEventID: "nuvio_sport_pending", streamID: "nuvio_sport_pending", manifestRevision: "test",
                    verifiedAt: verified, expiresAt: verified.addingTimeInterval(90), at: verified))
            }
            let candidate = singleDiscoverySession(event: candidateEvent, provider: "CS1", suffix: rejection,
                web: true, binding: binding)

            model.appendDiscoveredSingleSessions([candidate], currentEvent: admitted)

            XCTAssertEqual(model.activeSource?.id, source, rejection)
            XCTAssertEqual(model.loadRequestID, attempt, rejection)
            XCTAssertTrue(model.isLoading, rejection)
            XCTAssertNil(model.error, rejection)
            model.setSingleSourceDiscoveryActive(false)
            XCTAssertEqual(model.playbackState, .failed, rejection)
        }
    }

    func testHardSecurityOrUnsupportedFailureCannotAcquireLateDiscoveryContinuationFromReasonText() async {
        for reason in [PlaybackPreparationDiagnostic.Reason.unsafeRedirect, .unsupportedContentType] {
            let event = singleDiscoveryFixture()
            let initial = singleDiscoverySession(event: event, provider: "AS1", suffix: "hard-rejection", web: false)
            let model = LivePlayerViewModel(event: event, providedSessions: [initial],
                prepareAudioSession: { .completed([]) }, validateNativeSource: { _, _ in
                    // A textual status is not a causal HTTP response receipt.
                    .invalid("HTTP 403: unsupported or untrusted source",
                        diagnostics: .init(stage: .contractValidation, reason: reason))
                })
            defer { model.cleanup() }
            model.didApplyLandscape = true
            XCTAssertTrue(model.configureSingleStreamRanking())
            model.setSingleSourceDiscoveryActive(true)
            model.loadCurrentSource()
            for _ in 0..<3 { await model.loadTask?.value }
            XCTAssertEqual(model.playbackState, .failed)
            XCTAssertNotNil(model.error)
            XCTAssertTrue(model.isCheckingAdditionalSources)
            let terminalAttempt = model.loadRequestID
            let cs = singleDiscoverySession(event: event, provider: "CS1", suffix: "late-after-hard-rejection", web: true)

            model.appendDiscoveredSingleSessions([cs], currentEvent: event)

            XCTAssertEqual(model.activeSource?.id, initial.id)
            XCTAssertEqual(model.loadRequestID, terminalAttempt)
            XCTAssertEqual(model.playbackState, .failed)
            XCTAssertEqual(discoveryRecords("terminal_failure", sources: [initial]).count, 1)
            XCTAssertTrue(discoveryRecords("source_failure", sources: [initial]).allSatisfy {
                $0.details["preparation_http_status"] == nil
            })
        }
    }

    func testTerminalSingleFailuresCannotAcquireRecoveryFromNetworkLossAndReturn() async throws {
        for failure in ["http403", "unsupported", "readiness"] {
            let delay = ControlledWebRetryDelay(), event = singleDiscoveryFixture()
            let initial = singleDiscoverySession(event: event, provider: "AS1", suffix: "terminal-network-\(failure)", web: false)
            var validations = 0
            let model = LivePlayerViewModel(event: event, providedSessions: [initial], ownsRemoteCommands: false,
                prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
                validateNativeSource: { _, _ in validations += 1; return .invalid("Terminal delivery cannot reload") },
                timing: controlledNetworkTiming(delay))
            defer { model.cleanup(); delay.advance() }
            model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
            let player = NativeBackgroundTransportSpyPlayer()
            model.player = player
            model.nativeStartupRetryAttemptsBySource[initial.id] = 1
            model.transition(to: .connecting(.native), phase: "Buffering...")
            model.handleSourceStartupFailure(initial.legacySource, reason: "Native readiness timeout.", expectedRequestID: model.loadRequestID,
                diagnosticDetails: terminalNetworkFailureDetails(failure))
            let message = try XCTUnwrap(model.error), attempt = model.loadRequestID
            XCTAssertEqual(model.playbackState, .failed)
            model.handleNetworkReachabilityChange(false)
            await drainNetworkRecoveryTasks()
            delay.advance()
            await drainNetworkRecoveryTasks()
            model.handleNetworkReachabilityChange(true)
            await model.loadTask?.value
            XCTAssertEqual(model.playbackState, .failed, failure)
            XCTAssertEqual(model.error, message, failure)
            XCTAssertEqual(model.loadRequestID, attempt, failure)
            XCTAssertFalse(model.pendingRetryAfterNetworkRestore, failure)
            XCTAssertEqual(delay.invocationCount, 0, failure)
            XCTAssertEqual(validations, 0, failure)
            XCTAssertEqual(player.playCount, 0, failure)
        }
    }

    func testQueuedNetworkLossCannotOverrideTerminalCancellationOrReplacement() async throws {
        for change in ["terminal", "cancel", "replacement"] {
            let delay = ControlledWebRetryDelay(), event = singleDiscoveryFixture()
            let initial = singleDiscoverySession(event: event, provider: "AS1", suffix: "queued-loss-\(change)", web: false)
            let replacement = singleDiscoverySession(event: event, provider: "CS1", suffix: "replacement-\(change)", web: true)
            var validations = 0
            let model = LivePlayerViewModel(event: event, providedSessions: [initial], ownsRemoteCommands: false,
                prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
                validateNativeSource: { _, _ in validations += 1; return .invalid("Revoked network owner cannot reload") },
                timing: controlledNetworkTiming(delay), currentMatchProviders: { ["plaviosports", "communitysports"] })
            defer { model.cleanup(); delay.advance() }
            model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
            let player = NativeBackgroundTransportSpyPlayer(); model.player = player
            model.transition(to: .playing(.native), phase: "Playing")
            model.handleNetworkReachabilityChange(false)
            await drainNetworkRecoveryTasks()
            XCTAssertEqual(delay.pendingCount, 1, "The original healthy owner must first own the queued delay")
            switch change {
            case "terminal":
                model.handleSourceStartupFailure(initial.legacySource, reason: "Current response denied access", expectedRequestID: model.loadRequestID,
                    diagnosticDetails: terminalNetworkFailureDetails("http403"))
                XCTAssertEqual(model.playbackState, .failed)
                XCTAssertNotNil(model.error)
            case "cancel": model.cancelLoading()
            default:
                model.appendDiscoveredSingleSessions([replacement])
                model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == replacement.id }))
                await model.loadTask?.value
            }
            let attempt = model.loadRequestID, state = model.playbackState, message = model.error, source = model.activeSource?.id
            delay.advance()
            await drainNetworkRecoveryTasks()
            model.handleNetworkReachabilityChange(true)
            await model.loadTask?.value
            XCTAssertEqual(model.loadRequestID, attempt, change)
            XCTAssertEqual(model.playbackState, state, change)
            XCTAssertEqual(model.error, message, change)
            XCTAssertEqual(model.activeSource?.id, source, change)
            XCTAssertFalse(model.pendingRetryAfterNetworkRestore, change)
            XCTAssertEqual(validations, 0, change)
            XCTAssertEqual(player.playCount, 0, change)
        }
    }

    func testHealthyNativeNetworkRecoveryStillPlaysTheSameOwnedItemOnce() async throws {
        let delay = ControlledWebRetryDelay(), event = singleDiscoveryFixture()
        let initial = singleDiscoverySession(event: event, provider: "AS1", suffix: "healthy-network", web: false)
        var validations = 0
        let model = LivePlayerViewModel(event: event, providedSessions: [initial], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in validations += 1; return .invalid("Healthy item must remain installed") },
            timing: controlledNetworkTiming(delay))
        defer { model.cleanup(); delay.advance() }
        model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
        let item = AVPlayerItem(asset: AVMutableComposition()), player = NativeBackgroundTransportSpyPlayer()
        player.replaceCurrentItem(with: item); model.player = player
        model.transition(to: .playing(.native), phase: "Playing")
        let attempt = model.loadRequestID
        model.handleNetworkReachabilityChange(false)
        await drainNetworkRecoveryTasks()
        XCTAssertEqual(delay.pendingCount, 1)
        delay.advance()
        await drainNetworkRecoveryTasks()
        XCTAssertTrue(model.pendingRetryAfterNetworkRestore)
        XCTAssertEqual(model.playbackState, .recovering(.native))
        model.handleNetworkReachabilityChange(true)
        await model.audioPreparationTask?.value
        XCTAssertNil(model.error)
        XCTAssertFalse(model.pendingRetryAfterNetworkRestore)
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.activeSource?.id, initial.id)
        XCTAssertEqual(player.playCount, 1)
        XCTAssertEqual(validations, 0)
    }

    func testDecodedMatchFailureSwitchesBeforeRetryWithoutHistoricalBackupEvidence() throws {
        let event = singleDiscoveryFixture()
        let first = singleDiscoverySession(event: event, provider: "AS1", suffix: "primary", web: false)
        let alternative = try freshBoundDiscoverySession(event: event, suffix: "independent-backup")
        let model = LivePlayerViewModel(event: event, providedSessions: [first, alternative], ownsRemoteCommands: false,
            currentMatchProviders: { ["plaviosports", "communitysports"] })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == first.id })
        let attempt = model.loadRequestID
        model.transition(to: .playing(.native), phase: "Playing")
        model.recordPlaybackStage(.decoded, sourceID: first.id, requestID: attempt)
        model.handleSourceStartupFailure(first.legacySource, reason: "Decode failure", expectedRequestID: attempt,
            diagnosticDetails: ["native_failure_trigger": NativePlaybackDiagnosticTrigger.failedToPlayToEnd.rawValue,
                "native_error_domain": "url", "native_error_code": String(URLError.cannotDecodeContentData.rawValue)])
        XCTAssertEqual(model.activeSource?.id, alternative.id)
        XCTAssertTrue(model.failedSourceIDs.contains(first.id))
        XCTAssertNil(model.nativeStartupRetryAttemptsBySource[first.id])
    }

    func testTypedInitialExhaustionContinuesToFreshBoundLateCSWithoutAnotherTap() async throws {
        for failure in ["readiness", "playback-start", "lease", "decode", "network"] {
            let (model, initial, retiredAttempt) = try typedSingleDiscoveryPlayer(failure)
            defer { model.cleanup() }
            let pendingAttempt = model.loadRequestID
            XCTAssertNotEqual(pendingAttempt, retiredAttempt, failure)
            model.handleSourceStartupFailure(initial.legacySource, reason: "Late old failure", expectedRequestID: retiredAttempt,
                diagnosticDetails: terminalNetworkFailureDetails("http403"))
            XCTAssertTrue(model.isLoading, failure)
            let cs = try freshBoundDiscoverySession(event: model.event, suffix: "late-after-\(failure)")
            model.appendDiscoveredSingleSessions([cs], currentEvent: model.event)
            await model.loadTask?.value
            XCTAssertEqual(model.activeSource?.id, cs.id, failure)
            XCTAssertNotEqual(model.loadRequestID, pendingAttempt, failure)
            XCTAssertEqual(model.playbackState, .connecting(.webEmbed), failure)
            XCTAssertNil(model.error, failure)
            XCTAssertEqual(model.failedSourceIDs, [initial.id], failure)
            let currentAttempt = model.loadRequestID
            model.appendDiscoveredSingleSessions([initial, cs], currentEvent: model.event)
            XCTAssertEqual(model.loadRequestID, currentAttempt, "Repeated snapshots cannot retry exhausted delivery: \(failure)")
        }
    }

    func testNonHTTPPendingDiscoveryRequiresFreshBoundLeaseAndCurrentFixture() throws {
        for rejection in ["unbound", "expired-binding", "expired-lease", "wrong-binding", "changed-kickoff", "finished"] {
            let (model, initial, _) = try typedSingleDiscoveryPlayer("readiness")
            defer { model.cleanup() }
            let current = model.event, attempt = model.loadRequestID
            let bindingEvent = rejection == "wrong-binding" ? singleDiscoveryFixture(away: "Arsenal", date: current.date) : current
            let verified = rejection == "expired-binding" ? Date().addingTimeInterval(-120) : Date()
            let candidate = try freshBoundDiscoverySession(event: bindingEvent, suffix: rejection, verified: verified,
                expiry: rejection == "expired-lease" ? Date().addingTimeInterval(-1) : nil, bound: rejection != "unbound")
            let admitted = rejection == "changed-kickoff" ? singleDiscoveryFixture(date: current.date.map { $0 + 60 })
                : rejection == "finished" ? singleDiscoveryFixture(date: current.date, status: .finished) : current
            model.appendDiscoveredSingleSessions([candidate], currentEvent: admitted)
            XCTAssertEqual(model.activeSource?.id, initial.id, rejection)
            XCTAssertEqual(model.loadRequestID, attempt, rejection)
            XCTAssertTrue(model.isLoading, rejection)
            XCTAssertNil(model.error, rejection)
            model.setSingleSourceDiscoveryActive(false)
            XCTAssertEqual(model.playbackState, .failed, rejection)
        }
    }

    func testNonHTTPPendingDiscoveryCannotOutliveCompletionPauseCancellationOrReplacement() async throws {
        for change in ["completion", "pause", "cancel", "replacement"] {
            let (model, _, _) = try typedSingleDiscoveryPlayer("readiness")
            defer { model.cleanup() }
            switch change {
            case "completion": model.setSingleSourceDiscoveryActive(false)
            case "pause": model.requestPauseFromRemoteCommand()
            case "cancel": model.cancelLoading()
            default:
                let manual = try freshBoundDiscoverySession(event: model.event, suffix: "manual-before-late")
                model.appendDiscoveredSingleSessions([manual])
                model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == manual.id }))
                await model.loadTask?.value
            }
            let attempt = model.loadRequestID, state = model.playbackState, source = model.activeSource?.id
            let late = try freshBoundDiscoverySession(event: model.event, suffix: "late-revoked-\(change)")
            model.appendDiscoveredSingleSessions([late], currentEvent: model.event)
            XCTAssertEqual(model.loadRequestID, attempt, change)
            XCTAssertEqual(model.playbackState, state, change)
            XCTAssertEqual(model.activeSource?.id, source, change)
        }
    }

    func testUnknownUnsafeIdentityAndUnsupportedFailuresCannotAcquireNonHTTPDiscoveryContinuation() throws {
        for failure in ["unknown", "unsafe", "identity", "unsupported"] {
            let (model, initial, _) = try typedSingleDiscoveryPlayer(failure)
            defer { model.cleanup() }
            XCTAssertEqual(model.playbackState, .failed, failure)
            XCTAssertNotNil(model.error, failure)
            let attempt = model.loadRequestID
            let late = try freshBoundDiscoverySession(event: model.event, suffix: "late-after-\(failure)")
            model.appendDiscoveredSingleSessions([late], currentEvent: model.event)
            XCTAssertEqual(model.loadRequestID, attempt, failure)
            XCTAssertEqual(model.activeSource?.id, initial.id, failure)
            XCTAssertEqual(model.playbackState, .failed, failure)
        }
    }

    private func controlledNetworkTiming(_ delay: ControlledWebRetryDelay) -> FottyAsyncTiming {
        .init(monotonicNow: { ProcessInfo.processInfo.systemUptime }, sleep: { duration in
            if duration == .seconds(2) { try await delay.wait() }
            else { try await Task.sleep(for: duration) }
        })
    }

    private func drainNetworkRecoveryTasks() async {
        for _ in 0..<40 { await Task.yield() }
    }

    private func terminalNetworkFailureDetails(_ failure: String) -> [String: String] {
        switch failure {
        case "http403": return PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .httpStatus, httpStatus: 403).qualityDetails
        case "unsupported": return PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .unsupportedContentType).qualityDetails
        default: return ["native_failure_trigger": NativePlaybackDiagnosticTrigger.readinessTimeout.rawValue]
        }
    }

    private func typedSingleDiscoveryPlayer(_ failure: String) throws -> (LivePlayerViewModel, StreamSession, UUID) {
        let event = singleDiscoveryFixture()
        let initial = failure == "lease"
            ? StreamSession(matchID: event.id, playableURL: URL(string: "https://media.example/expired-initial.m3u8")!,
                streamType: .hls, providerName: "AS1", expiryTime: Date().addingTimeInterval(-1))
            : singleDiscoverySession(event: event, provider: "AS1", suffix: "typed-\(failure)", web: false)
        let model = LivePlayerViewModel(event: event, providedSessions: [initial], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in XCTFail("The exhausted initial transport must not restart"); return .invalid("No") },
            currentMatchProviders: { ["plaviosports", "communitysports"] })
        model.didApplyLandscape = true; XCTAssertTrue(model.configureSingleStreamRanking())
        model.setSingleSourceDiscoveryActive(true)
        model.nativeStartupRetryAttemptsBySource[initial.id] = 1
        model.transition(to: .connecting(.native), phase: "Buffering...")
        let attempt = model.loadRequestID, details: [String: String]
        switch failure {
        case "playback-start": details = PlaybackPreparationDiagnostic(stage: .playbackStart, reason: .playbackStartTimeout).qualityDetails
        case "lease": details = PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: .leaseExpired).qualityDetails
        case "decode": details = ["native_failure_trigger": NativePlaybackDiagnosticTrigger.itemStatusFailed.rawValue,
            "native_error_domain": "avfoundation", "native_error_code": String(AVError.Code.decodeFailed.rawValue)]
        case "network": details = ["native_error_domain": "url", "native_error_code": String(URLError.timedOut.rawValue)]
        case "unknown": details = ["native_log_code": "-16839"]
        case "unsafe": details = PlaybackPreparationDiagnostic(stage: .urlPreparation, reason: .unsafeRedirect).qualityDetails
        case "identity": details = ["preparation_reason": "descriptor_fixture_changed"]
        case "unsupported": details = terminalNetworkFailureDetails("unsupported")
        default: details = terminalNetworkFailureDetails("readiness")
        }
        model.handleSourceStartupFailure(initial.legacySource, reason: "Native readiness timeout.", expectedRequestID: attempt, diagnosticDetails: details)
        if ["unknown", "unsafe", "identity", "unsupported"].contains(failure) {
            XCTAssertEqual(model.playbackState, .failed, failure)
        } else {
            XCTAssertTrue(model.isLoading, failure); XCTAssertNil(model.error, failure)
        }
        XCTAssertTrue(model.failedSourceIDs.contains(initial.id), failure)
        return (model, initial, attempt)
    }

    private func freshBoundDiscoverySession(event: EventReference, suffix: String, verified: Date = Date(),
        expiry: Date? = nil, bound: Bool = true) throws -> StreamSession {
        let binding = try XCTUnwrap(StreamEventBinding(request: .init(event: event), providerCode: "communitysports",
            providerEventID: "nuvio_sport_pending", streamID: "nuvio_sport_pending", manifestRevision: "test",
            verifiedAt: verified, expiresAt: verified.addingTimeInterval(90), at: verified))
        return StreamSession(matchID: event.id, playableURL: URL(string: "https://addon.example/watch/\(suffix)")!,
            streamType: .unknown, providerName: "CS1", requiredHeaders: ["X-Fotty-Web-Embed": "true"],
            expiryTime: expiry, createdAt: verified, eventBinding: bound ? binding : nil)
    }

    private func singleDiscoveryFixture(id: String = "sports-fixture:premier-league:pending-discovery",
        away: String = "Brighton", date: Int64? = nil, conflict: Bool = false,
        status: SportsFixtureCatalog.Status = .live) -> EventReference {
        let title = "Chelsea vs \(away)"
        let fixture = SportsFixtureMetadata(fixtureID: id, sport: "football", competitionID: "premier-league",
            competitionName: "Premier League", eventKind: .match, title: title, participants: [
                .init(id: "chelsea", name: "Chelsea"), .init(id: away.lowercased(), name: away)],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: Date(), verified: true)
        return EventReference(id: id, title: title, category: "football",
            date: date ?? Int64(Date().timeIntervalSince1970) - 60, poster: nil, popular: false,
            teams: .init(home: .init(name: "Chelsea", badge: nil), away: .init(name: away, badge: nil)),
            sources: [], hasCatalogIdentityConflict: conflict, sportsFixture: fixture, competitionID: "premier-league")
    }

    private func singleDiscoverySession(event: EventReference, provider: String, suffix: String, web: Bool,
        binding: StreamEventBinding? = nil) -> StreamSession {
        StreamSession(matchID: event.id,
            playableURL: URL(string: web ? "https://addon.example/watch/\(suffix)" : "https://media.example/\(suffix).m3u8")!,
            streamType: web ? .unknown : .hls, providerName: provider,
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:],
            createdAt: binding?.verifiedAt ?? Date(), eventBinding: binding)
    }

    private func exhaustedSingleDiscoveryPlayer(count: Int = 3,
        enabledProviders: Set<String> = ["plaviosports", "communitysports"]) async -> (LivePlayerViewModel, [StreamSession]) {
        let event = singleDiscoveryFixture()
        let initial = (1...count).map { singleDiscoverySession(event: event, provider: "AS\($0)", suffix: "as-\($0)", web: false) }
        let model = LivePlayerViewModel(event: event, providedSessions: initial, prepareAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in
                .invalid("HTTP 403", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 403))
            }, currentMatchProviders: { enabledProviders })
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.setSingleSourceDiscoveryActive(true)
        model.loadCurrentSource()
        for _ in 0..<(count + 2) { await model.loadTask?.value }
        XCTAssertEqual(model.failedSourceIDs, Set(initial.map(\.id)))
        XCTAssertEqual(discoveryRecords("source_failure", sources: initial).count, count)
        XCTAssertTrue(model.isLoading, "A still-owned lookup can supply an independent alternative")
        XCTAssertNil(model.error)
        XCTAssertTrue(discoveryRecords("terminal_failure", sources: initial).isEmpty)
        return (model, initial)
    }

    private func discoveryRecords(_ name: String, sources: [StreamSession]) -> [FottyQualityRecord] {
        let IDs = Set(sources.map { $0.id.uuidString })
        return FottyQualityStore.shared.records().filter {
            $0.name == name && $0.details["source_id"].map(IDs.contains) == true
        }
    }

    func testExpiredSingleFlixLeaseRenewsExactQueryTokenBeforeValidatingAnyMedia() async throws {
        let fixture = try expiredFlixDescriptorFixture()
        var renewals = 0, validated: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { url, _ in
                validated.append(url)
                return .invalid("Controlled rejection", diagnostics:
                    .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404))
            }, refreshSourceDescriptor: { selected, request in
                renewals += 1
                XCTAssertEqual(selected.id, fixture.old.id)
                XCTAssertEqual(request.matchID, fixture.event.id)
                return fixture.fresh
            })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        XCTAssertFalse(fixture.old.canRefresh, "Expiry renewal is independent of the separate stall capability")

        model.loadCurrentSource()
        await model.loadTask?.value

        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(validated, [fixture.fresh.playableURL])
        XCTAssertFalse(validated.contains(fixture.old.playableURL))
        XCTAssertEqual(model.activeSession?.id, fixture.old.id)
        XCTAssertEqual(model.activeSession?.providerName, "FS1")
        XCTAssertEqual(model.activeSession?.playableURL, fixture.fresh.playableURL)
        XCTAssertFalse(model.activeSession?.canRefresh ?? true)
        XCTAssertNil(model.player?.currentItem, "Injected rejection prevents all media requests")
    }

    func testUnavailableOrWrongRowFlixRenewalNeverValidatesExpiredLeaseAndKeepsTypedPrivateFailure() async throws {
        for wrongRow in [false, true] {
            let fixture = try expiredFlixDescriptorFixture()
            var renewals = 0, validations = 0
            let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
                prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
                validateNativeSource: { _, _ in validations += 1; return .invalid("Expired URL must not validate") },
                refreshSourceDescriptor: { _, _ in
                    renewals += 1
                    guard wrongRow else { return nil }
                    return StreamSession(matchID: fixture.event.id, playableURL: fixture.fresh.playableURL,
                        streamType: .hls, providerName: "FS1", qualityLabel: "Live video",
                        expiryTime: fixture.fresh.expiryTime, createdAt: fixture.fresh.createdAt,
                        eventBinding: fixture.fresh.eventBinding)
                })
            defer { model.cleanup() }
            model.didApplyLandscape = true
            XCTAssertTrue(model.configureSingleStreamRanking())

            model.loadCurrentSource()
            await model.loadTask?.value

            XCTAssertEqual(renewals, 1)
            XCTAssertEqual(validations, 0)
            XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
            XCTAssertEqual(model.playbackState, .failed)
            let failure = try XCTUnwrap(discoveryRecords("source_failure", sources: [fixture.old]).last)
            XCTAssertEqual(failure.details["preparation_stage"], PlaybackPreparationDiagnostic.Stage.urlPreparation.rawValue)
            XCTAssertEqual(failure.details["preparation_reason"], PlaybackPreparationDiagnostic.Reason.leaseExpired.rawValue)
            XCTAssertNil(failure.details["preparation_http_status"])
            for privateValue in ["old-private-token", "fresh-private-token", "free.flixnest.app", "https://"] {
                XCTAssertFalse(failure.details.description.contains(privateValue))
            }
        }
    }

    func testCancelledSingleFlixRenewalCannotAdoptOrValidateItsLateFreshResult() async throws {
        let fixture = try expiredFlixDescriptorFixture(), gate = ControlledWebRetryDelay()
        var validations = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in validations += 1; return .invalid("Cancelled") },
            refreshSourceDescriptor: { _, _ in try? await gate.wait(); return fixture.fresh })
        defer { gate.advance(); model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.loadCurrentSource()
        await gate.waitUntilSuspended()
        let abandoned = try XCTUnwrap(model.loadTask)

        model.cancelLoading()
        let cancelledAttempt = model.loadRequestID
        gate.advance()
        await abandoned.value

        XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.loadRequestID, cancelledAttempt)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
        XCTAssertEqual(model.playbackState, .failed)
    }

    func testNativeWatchTwoFlixLeaseDoesNotInvokeSingleDescriptorRenewal() async throws {
        let fixture = try expiredFlixDescriptorFixture()
        var renewals = 0
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.old], ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: { _, _ in .invalid("Controlled rejection", diagnostics:
                .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 404)) },
            refreshSourceDescriptor: { _, _ in renewals += 1; return fixture.fresh })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .native)))

        model.loadCurrentSource()
        await model.loadTask?.value

        XCTAssertEqual(renewals, 0)
        XCTAssertEqual(model.activeSession?.playableURL, fixture.old.playableURL)
    }

    /// Synthetic exact bindings exercise preparation ownership only. The
    /// injected validator rejects before any relay or AVPlayerItem requests media.
    private func expiredFlixDescriptorFixture() throws
        -> (event: EventReference, old: StreamSession, fresh: StreamSession) {
        let event = singleDiscoveryFixture(), request = StreamPlaybackRequest(event: event), now = Date()
        func binding(at clock: Date) throws -> StreamEventBinding {
            try XCTUnwrap(StreamEventBinding(request: request, providerCode: "flixstreams",
                providerEventID: "dlstreams:event:aaaaaaaaaaaa", streamID: "dlstreams:event:aaaaaaaaaaaa",
                manifestRevision: "test", verifiedAt: clock, expiresAt: clock.addingTimeInterval(90), at: clock))
        }
        let oldClock = now.addingTimeInterval(-120)
        let prefix = "https://free.flixnest.app/dlstreams/stream/dlstreams%3Achannel%3A870.m3u8?t="
        let old = StreamSession(matchID: event.id, playableURL: URL(string: prefix + "old-private-token")!,
            streamType: .hls, providerName: "FS1", qualityLabel: "Live video",
            expiryTime: oldClock.addingTimeInterval(90), canRefresh: false, createdAt: oldClock,
            eventBinding: try binding(at: oldClock))
        let delivered = StreamSession(matchID: event.id, playableURL: URL(string: prefix + "fresh-private-token")!,
            streamType: .hls, providerName: "FS1", qualityLabel: "Live video",
            expiryTime: now.addingTimeInterval(90), canRefresh: false, createdAt: now,
            eventBinding: try binding(at: now))
        return (event, old, try XCTUnwrap(old.renewingDelivery(from: delivered, for: request, at: now)))
    }

    func testLateCSValidationCannotReplaceSelectedStreamExSource() async throws {
        let delay = ControlledWebRetryDelay()
        let cs = csSession(web: false)
        let streamEx = StreamSession(
            matchID: "cs-lifecycle", playableURL: URL(string: "https://example.invalid/embed/game")!,
            streamType: .unknown, providerName: "StreamEx",
            requiredHeaders: ["X-Fotty-Web-Embed": "true"]
        )
        let model = makeSourcePlayer(sessions: [cs, streamEx]) { _, _ in
            try? await delay.wait()
            return .valid
        }
        defer { model.cleanup() }
        model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == cs.id }))
        await delay.waitUntilSuspended()
        let abandonedTask = try XCTUnwrap(model.loadTask)
        let abandonedPlayer = try XCTUnwrap(model.player)

        model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == streamEx.id }))
        await model.loadTask?.value
        let selectedAttempt = model.loadRequestID
        delay.advance()
        await abandonedTask.value

        XCTAssertEqual(model.activeSource?.id, streamEx.id)
        XCTAssertEqual(model.loadRequestID, selectedAttempt)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
        XCTAssertEqual(model.connectionPhase, "Starting Web Stream...")
        XCTAssertNil(model.player)
        XCTAssertNil(abandonedPlayer.currentItem)
        XCTAssertTrue(model.playerItemNotificationTokens.isEmpty)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
    }

    func testDismissedCSValidationCannotStartAnOrphanPlayer() async throws {
        let delay = ControlledWebRetryDelay()
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in
            try? await delay.wait()
            return .valid
        }
        model.loadCurrentSource()
        await delay.waitUntilSuspended()
        let abandonedTask = try XCTUnwrap(model.loadTask)
        let abandonedPlayer = try XCTUnwrap(model.player)
        model.cleanup()
        delay.advance()
        await abandonedTask.value

        XCTAssertNil(abandonedPlayer.currentItem)
        XCTAssertNil(model.player)
        XCTAssertEqual(model.playbackState, .idle)
        XCTAssertEqual(model.connectionPhase, "Idle")
        XCTAssertTrue(model.playerItemNotificationTokens.isEmpty)
    }

    func testPlaybackLabSourceRoundTripRejectsOldFailureEvenWhenSelectedSourceIDMatchesAgain() async throws {
        // A → B → A is stricter than an ordinary source switch: the first A's
        // callback has the current source ID but the wrong attempt. Both native
        // validations are held explicitly, so no item or provider request runs.
        let firstGate = ControlledWebRetryDelay(), returnGate = ControlledWebRetryDelay()
        let native = csSession(web: false), web = csSession(web: true)
        var validations = 0
        let model = makeSourcePlayer(sessions: [native, web]) { _, _ in
            validations += 1
            if validations == 1 {
                try? await firstGate.wait()
                return .invalid("HTTP 403", diagnostics:
                    .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 403))
            }
            try? await returnGate.wait()
            return .valid
        }
        defer { model.cleanup(); firstGate.advance(); returnGate.advance() }
        let nativeIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == native.id })
        let webIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == web.id })
        model.selectSourceManually(at: nativeIndex)
        await firstGate.waitUntilSuspended()
        let abandoned = try XCTUnwrap(model.loadTask), oldAttempt = model.loadRequestID
        model.selectSourceManually(at: webIndex)
        await model.loadTask?.value
        model.selectSourceManually(at: nativeIndex)
        await returnGate.waitUntilSuspended()
        let current = try XCTUnwrap(model.loadTask), currentAttempt = model.loadRequestID
        let currentPlayer = try XCTUnwrap(model.player)
        XCTAssertNotEqual(currentAttempt, oldAttempt)
        XCTAssertEqual(model.activeSource?.id, native.id)

        firstGate.advance()
        await abandoned.value

        XCTAssertEqual(model.loadRequestID, currentAttempt)
        XCTAssertEqual(model.activeSource?.id, native.id)
        XCTAssertTrue(model.player === currentPlayer, "Old validation cannot tear down the new attempt's owner")
        XCTAssertNil(currentPlayer.currentItem)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(validations, 2, "A retired 403 must not start a retry against the current attempt")
        XCTAssertTrue(FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["source_id"] == native.id.uuidString
        }.isEmpty)

        // Now retire the current A as well before its success arrives. Neither
        // old completion is permitted to create an orphan AVPlayerItem.
        model.selectSourceManually(at: webIndex)
        await model.loadTask?.value
        let finalAttempt = model.loadRequestID
        returnGate.advance()
        await current.value
        XCTAssertEqual(model.loadRequestID, finalAttempt)
        XCTAssertEqual(model.activeSource?.id, web.id)
        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertNil(model.player)
        XCTAssertNil(currentPlayer.currentItem)
    }

    func testDirectCSFailureRetriesNativeOnceAndNeverLoadsManifestInWebView() async {
        var validations = 0
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in
            validations += 1
            return .invalid("HTTP 503")
        }
        defer { model.cleanup() }
        model.loadCurrentSource()
        await model.loadTask?.value
        await model.loadTask?.value

        XCTAssertEqual(validations, 2)
        XCTAssertFalse(model.isUsingWebEmbed)
        XCTAssertTrue(model.forceWebEmbedSourceIDs.isEmpty)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.failedSourceIDs.count, 1)
    }

    func testPreItemContractFailureActuallyPublishesTypedReceiptWithoutChangingRetryPolicy() async throws {
        let session = csSession(web: false)
        let model = makeSourcePlayer(sessions: [session]) { _, _ in
            .invalid("HTTP 503", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 503))
        }
        defer { model.cleanup() }
        model.loadCurrentSource()
        await model.loadTask?.value
        await model.loadTask?.value
        let failures = FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["source_id"] == session.id.uuidString
        }
        XCTAssertEqual(failures.count, 2, "The existing native-once retry policy remains unchanged")
        XCTAssertEqual(Set(failures.compactMap { $0.details["attempt_id"] }).count, 2)
        for failure in failures {
            XCTAssertEqual(failure.details["preparation_stage"], "contract_validation")
            XCTAssertEqual(failure.details["preparation_reason"], "http_status")
            XCTAssertEqual(failure.details["preparation_http_status"], "503")
            XCTAssertEqual(failure.details["last_observed_stage"], "preparing")
            XCTAssertNil(failure.details["native_failure_trigger"])
            XCTAssertNil(failure.details["preparation_error_code"])
        }
        XCTAssertNil(model.player?.currentItem)
        XCTAssertEqual(model.lastFailureReason, "Stream Contract Failed: HTTP 503")
        XCTAssertFalse(model.isUsingWebEmbed)
        XCTAssertTrue(model.forceWebEmbedSourceIDs.isEmpty)
    }

    func testAbandonedPreItemFailureCannotPublishReceiptForNewSourceOrAttempt() async throws {
        let delay = ControlledWebRetryDelay()
        let old = csSession(web: false)
        let replacement = csSession(web: true)
        let model = makeSourcePlayer(sessions: [old, replacement]) { _, _ in
            try? await delay.wait()
            return .invalid("HTTP 503", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 503))
        }
        defer { model.cleanup() }
        model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == old.id }))
        await delay.waitUntilSuspended()
        let oldTask = try XCTUnwrap(model.loadTask)
        model.selectSourceManually(at: try XCTUnwrap(model.sessions.firstIndex { $0.id == replacement.id }))
        await model.loadTask?.value
        delay.advance()
        await oldTask.value
        XCTAssertTrue(FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["source_id"] == old.id.uuidString
        }.isEmpty)
        XCTAssertEqual(model.activeSource?.id, replacement.id)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
    }

    func testActualProxyPreparationRejectionPublishesReceiptBeforeAnyValidationOrItem() async throws {
        // This deliberately rejected fixture never starts the listener or makes
        // a provider request. It exercises the real preparation catch while
        // confirming that diagnostics do not relax destination admission.
        let session = StreamSession(matchID: "preparation-rejection",
            playableURL: URL(string: "https://127.0.0.1/forbidden.m3u8")!, streamType: .hls,
            providerName: "CS1", requiredHeaders: ["User-Agent": "Fixture"])
        var validations = 0
        let model = makeSourcePlayer(sessions: [session]) { _, _ in
            validations += 1
            return .valid
        }
        defer { model.cleanup() }
        model.loadCurrentSource()
        await model.loadTask?.value
        await model.loadTask?.value
        let failures = FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["source_id"] == session.id.uuidString
        }
        XCTAssertEqual(failures.count, 2)
        for failure in failures {
            XCTAssertEqual(failure.details["preparation_stage"], "url_preparation")
            XCTAssertEqual(failure.details["preparation_reason"], "proxy_startup")
            XCTAssertEqual(failure.details["preparation_error_domain"], "url")
            XCTAssertEqual(failure.details["preparation_error_code"], String(URLError.unsupportedURL.rawValue))
            XCTAssertNil(failure.details["native_failure_trigger"])
            XCTAssertNil(failure.details["preparation_http_status"])
            XCTAssertFalse(failure.details.description.contains("127.0.0.1"))
        }
        XCTAssertEqual(validations, 0)
        XCTAssertNil(model.player?.currentItem)
        XCTAssertNil(model.streamProxy)
        XCTAssertEqual(model.lastFailureReason, URLError(.unsupportedURL).localizedDescription)
    }

    func testFallbackHasOnlyOneWebPlaybackOwner() async {
        let source = StreamSession(
            matchID: "cs-lifecycle", playableURL: URL(string: "https://example.invalid/player")!,
            streamType: .unknown, providerName: "StreamEx"
        )
        var validations = 0
        let model = makeSourcePlayer(sessions: [source]) { _, _ in
            validations += 1
            return .invalid("Received HTML instead of Video")
        }
        defer { model.cleanup() }
        model.loadCurrentSource()
        await model.loadTask?.value
        await model.loadTask?.value

        XCTAssertEqual(validations, 1)
        XCTAssertTrue(model.isUsingWebEmbed)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
        XCTAssertNil(model.player)
    }

    func testSourceReloadClearsOldPictureInPictureRequest() async {
        let model = makeSourcePlayer(sessions: [csSession(web: true)]) { _, _ in .valid }
        defer { model.cleanup() }
        model.isPictureInPictureAvailable = true
        model.pictureInPictureRequestID = UUID()
        model.lastPictureInPictureRequestAt = Date()
        model.loadCurrentSource()
        await model.loadTask?.value

        XCTAssertFalse(model.isPictureInPictureAvailable)
        XCTAssertNil(model.pictureInPictureRequestID)
        XCTAssertNil(model.lastPictureInPictureRequestAt)
    }

    func testCSTrackingKeepsLabelFamilyAndOpaqueKeyWithoutRawTransportData() {
        let model = makeSourcePlayer(sessions: [csSession(web: true)]) { _, _ in .valid }
        defer { model.cleanup() }
        let details = model.playbackQualityDetails(["failure_kind": "startupTimeout"])

        XCTAssertEqual(details["source"], "CS1")
        XCTAssertEqual(details["source_family"], "communitysports")
        XCTAssertEqual(details["source_key"], "cs_000000000000000000000000")
        XCTAssertEqual(details["attempt_id"], model.loadRequestID.uuidString)
        XCTAssertEqual(details["mode"], "web_embed")
        XCTAssertNil(details["source_hint"])
        XCTAssertNil(details["referer"])
        XCTAssertFalse(details.values.contains { $0.contains("://") })
    }

    private func csSession(web: Bool) -> StreamSession {
        StreamSession(
            matchID: "cs-lifecycle",
            playableURL: URL(string: web
                ? "https://addon.example/watch?url=https%3A%2F%2Fvideo.example%2Fmaster.m3u8"
                : "https://addon.example/api/manifest?url=https%3A%2F%2Fembed.example%2Fembed%2Fgame")!,
            streamType: web ? .unknown : .hls, providerName: "CS1",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:],
            diagnosticMetadata: [
                "source_family": "communitysports", "source_hint": "upstream-private",
                // Synthetic attribution digest, not an authentication credential.
                "source_key": "cs_000000000000000000000000", "addon_version": "1.0",
                "referer": "https://private.example/never-log-this"
            ]
        )
    }

    private func makeSourcePlayer(
        sessions: [StreamSession],
        validation: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult
    ) -> LivePlayerViewModel {
        let event = AnalyticalDataEngine.EventReference(
            id: "cs-lifecycle", title: "Playback test", category: "football",
            date: Int64(Date().timeIntervalSince1970), poster: nil, popular: false,
            teams: nil, sources: nil
        )
        let model = LivePlayerViewModel(event: event, providedSessions: sessions,
                                       prepareAudioSession: { .completed([]) }, validateNativeSource: validation)
        model.didApplyLandscape = true
        return model
    }

    func testNativeVideoYieldsHitTestingWhilePlayerControlsAreVisible() {
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)

        view.capturesSurfaceTaps = true
        XCTAssertTrue(view.isUserInteractionEnabled)

        view.capturesSurfaceTaps = false
        XCTAssertFalse(view.isUserInteractionEnabled)
    }

    func testReassigningNativePlayerCallbacksDoesNotPublishDuringUIViewUpdate() {
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        var publicationCount = 0

        view.onReadyForDisplayChanged = { _ in publicationCount += 1 }
        view.onTimeControlStatusChanged = { _ in publicationCount += 1 }
        view.onPictureInPictureAvailabilityChanged = { _ in publicationCount += 1 }

        XCTAssertEqual(publicationCount, 0)
    }

    func testUninterruptedRecoveryReloadsExactlyOnce() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let originalAttempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        XCTAssertEqual(model.loadRequestID, originalAttempt)
        XCTAssertEqual(model.playbackState, .recovering(.webEmbed))
        XCTAssertEqual(delay.invocationCount, 1)

        delay.advance()
        await retry.value
        await model.loadTask?.value
        let reloadedAttempt = model.loadRequestID
        XCTAssertNotEqual(reloadedAttempt, originalAttempt)
        XCTAssertNil(model.webRetryTask)
        XCTAssertEqual(model.playbackState, .connecting(.webEmbed))
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertEqual(delay.pendingCount, 0)

        delay.advance()
        await Task.yield()
        XCTAssertEqual(model.loadRequestID, reloadedAttempt)
        XCTAssertEqual(delay.invocationCount, 1)
    }

    func testCleanupInvalidatesDelayedRetryAndOldBridgeCallbacks() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let oldAttempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.cleanup()
        let closedAttempt = model.loadRequestID
        XCTAssertNotEqual(closedAttempt, oldAttempt)
        XCTAssertNil(model.webRetryTask)
        model.handleWebEmbedPlaybackStarted(sourceID: source, requestID: oldAttempt, startupLatencyMs: 50)
        model.handleWebEmbedPlaybackRecovered(sourceID: source, requestID: oldAttempt)
        model.handleWebEmbedFailure(sourceID: source, requestID: oldAttempt, reason: "Playback stalled")
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, closedAttempt)
        XCTAssertEqual(model.playbackState, .idle)
        XCTAssertNil(model.player)
        XCTAssertFalse(model.pendingRetryAfterNetworkRestore)
    }

    func testExplicitPauseCancelsRetryAndLateStartedMessageCannotResumeIt() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.togglePlayPause()
        model.handleWebEmbedPlaybackStarted(sourceID: source, requestID: attempt, startupLatencyMs: 50)
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertTrue(model.isWebPlaybackUserPaused)
        XCTAssertEqual(model.webPlaybackCommand?.shouldPlay, false)
        XCTAssertNil(model.webRetryTask)
    }

    func testProviderPauseCancelsPendingRecovery() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.handleWebEmbedTransportState(.paused, sourceID: source, requestID: attempt)
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertTrue(model.isWebPlaybackUserPaused)
        XCTAssertNil(model.webRetryTask)
    }

    func testDecodedRecoveryKeepsSameAttemptWithoutReloading() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.handleWebEmbedPlaybackRecovered(sourceID: source, requestID: attempt)
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertNil(model.webRetryTask)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
    }

    func testLateStartupProgressCancelsPendingStartupRetry() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay, markPlaying: false)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay, reason: "Startup timeout")

        model.handleWebEmbedPlaybackStarted(sourceID: source, requestID: attempt, startupLatencyMs: 50)
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertNil(model.webRetryTask)
    }

    func testManualReloadOfSameSourceInvalidatesEarlierRetry() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let retry = try await beginRetry(model, delay: delay)
        let oldAttempt = model.loadRequestID

        model.loadCurrentSource(ignoringCircuitBreaker: true)
        await model.loadTask?.value
        let manualAttempt = model.loadRequestID
        delay.advance()
        await retry.value

        XCTAssertNotEqual(manualAttempt, oldAttempt)
        XCTAssertEqual(model.loadRequestID, manualAttempt)
        XCTAssertNil(model.webRetryTask)
    }

    func testSourceSelectionInvalidatesPendingRetry() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay, sessionCount: 2)
        defer { model.cleanup() }
        let retry = try await beginRetry(model, delay: delay)
        let selectedIndex = model.currentSourceIndex == 0 ? 1 : 0

        model.selectSourceManually(at: selectedIndex)
        await model.loadTask?.value
        let selectedAttempt = model.loadRequestID
        let selectedSource = model.activeSource?.id
        delay.advance()
        await retry.value

        XCTAssertEqual(model.currentSourceIndex, selectedIndex)
        XCTAssertEqual(model.activeSource?.id, selectedSource)
        XCTAssertEqual(model.loadRequestID, selectedAttempt)
        XCTAssertNil(model.webRetryTask)
    }

    func testBackgroundingCancelsRetryAndIgnoresLateProgress() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.handleScenePhaseChange(.background)
        await Task.yield()
        model.handleWebEmbedPlaybackRecovered(sourceID: source, requestID: attempt)
        model.handleWebEmbedTransportState(.playing, sourceID: source, requestID: attempt)
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .paused(.webEmbed))
        XCTAssertNil(model.webRetryTask)
        model.handleScenePhaseChange(.active)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
    }

    func testNetworkWaitCancelsRetryWithoutConsumingAnotherSource() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.isNetworkReachable = false
        model.handleWebEmbedFailure(sourceID: source, requestID: attempt, reason: "Network interrupted")
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.connectionPhase, "Waiting For Network")
        XCTAssertTrue(model.pendingRetryAfterNetworkRestore)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertNil(model.webRetryTask)
        model.handleNetworkReachabilityChange(true)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
    }

    func testRepeatedBridgeFailureDoesNotExhaustThePendingRetry() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.handleWebEmbedFailure(sourceID: source, requestID: attempt, reason: "Playback stalled again")
        model.handleWebEmbedFailure(sourceID: source, requestID: attempt, reason: "Startup timeout duplicate")
        XCTAssertEqual(delay.invocationCount, 1)
        XCTAssertEqual(delay.pendingCount, 1)
        XCTAssertEqual(model.webStallRetryAttemptsBySource[source], 1)
        XCTAssertNil(model.webStartupRetryAttemptsBySource[source])
        XCTAssertTrue(model.failedSourceIDs.isEmpty)

        delay.advance()
        await retry.value
        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.webRetryTask)
    }

    func testExplicitProviderRejectionCancelsInsteadOfExecutingPendingRetry() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.handleWebEmbedFailure(sourceID: source, requestID: attempt, reason: "Broadcast is unavailable")
        delay.advance()
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.webRetryTask)
    }

    func testStaleRecoveryCannotCancelTheCurrentAttemptRetry() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id)
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        model.handleWebEmbedPlaybackRecovered(sourceID: source, requestID: UUID())
        XCTAssertNotNil(model.webRetryTask)
        XCTAssertEqual(model.playbackState, .recovering(.webEmbed))
        delay.advance()
        await retry.value

        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.webRetryTask)
    }

    func testRejectedDelayReleasesItsOwnership() async throws {
        let delay = ControlledWebRetryDelay()
        let model = try await makePlayer(delay: delay)
        defer { model.cleanup() }
        let attempt = model.loadRequestID
        let retry = try await beginRetry(model, delay: delay)

        delay.advance(throwing: CancellationError())
        await retry.value

        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.webRetryTask)
    }

    private func beginRetry(
        _ model: LivePlayerViewModel,
        delay: ControlledWebRetryDelay,
        reason: String = "Playback stalled"
    ) async throws -> Task<Void, Never> {
        let source = try XCTUnwrap(model.activeSource?.id)
        model.handleWebEmbedFailure(sourceID: source, requestID: model.loadRequestID, reason: reason)
        let retry = try XCTUnwrap(model.webRetryTask)
        await delay.waitUntilSuspended()
        return retry
    }

    private func makePlayer(
        delay: ControlledWebRetryDelay,
        sessionCount: Int = 1,
        markPlaying: Bool = true,
        configureSingle: Bool = false
    ) async throws -> LivePlayerViewModel {
        let event = AnalyticalDataEngine.EventReference(
            id: "retry-lifecycle-\(UUID().uuidString)",
            title: "Retry Lifecycle Test",
            category: "football",
            date: Int64(Date().timeIntervalSince1970),
            poster: nil, popular: false, teams: nil, sources: nil
        )
        let sessions = try (0..<sessionCount).map { index in
            StreamSession(
                matchID: event.id,
                title: "Retry Test \(index)",
                playableURL: try XCTUnwrap(URL(string: "https://embed.st/embed/admin/fotty-retry-test/\(index + 1)")),
                streamType: .unknown,
                providerName: "StreamEx",
                requiredHeaders: ["X-Fotty-Nexus-Source": "admin", "X-Fotty-Web-Embed": "true"],
                qualityLabel: "Web"
            )
        }
        let model = LivePlayerViewModel(
            event: event,
            providedSessions: sessions,
            webRetryDelay: { try await delay.wait() },
            webBackgroundSuspensionDelay: {}
        )
        // This suite exercises the real owner without creating WebKit/AVPlayer
        // or changing window geometry. Web-source preparation performs no I/O.
        model.didApplyLandscape = true
        if configureSingle { XCTAssertTrue(model.configureSingleStreamRanking()) }
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        await model.loadTask?.value
        if markPlaying {
            model.handleWebEmbedPlaybackStarted(
                sourceID: try XCTUnwrap(model.activeSource?.id),
                requestID: model.loadRequestID,
                startupLatencyMs: 50
            )
        }
        return model
    }
}

/// Deliberately does not cooperate with task cancellation: advancing a cancelled
/// timer proves that the real owner's attempt/lifecycle guard prevents reloading.
@MainActor
private final class ControlledWebRetryDelay {
    private var pending: [CheckedContinuation<Void, Error>] = []
    private var readiness: [CheckedContinuation<Void, Never>] = []
    private(set) var invocationCount = 0
    var pendingCount: Int { pending.count }

    func wait() async throws {
        invocationCount += 1
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let waiters = readiness
            readiness.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilSuspended() async {
        guard pending.isEmpty else { return }
        await withCheckedContinuation { readiness.append($0) }
    }

    func advance(throwing error: Error? = nil) {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations {
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }
}

private final class NativeBackgroundTransportSpyPlayer: AVPlayer {
    private let countLock = NSLock()
    private var plays = 0
    private var pauses = 0
    var playCount: Int { countLock.lock(); defer { countLock.unlock() }; return plays }
    var pauseCount: Int { countLock.lock(); defer { countLock.unlock() }; return pauses }

    // Deliberately inert transport: no provider URL is loaded or decoded, and
    // the AVPlayer overrides may be called from outside the main actor.
    override func play() { countLock.lock(); defer { countLock.unlock() }; plays += 1 }
    override func pause() { countLock.lock(); defer { countLock.unlock() }; pauses += 1 }
}

extension LivePlayerRetryLifecycleTests {
    func testBackgroundPiPFatalItemRecordsImmediatelyAndRecoversOnceOnForeground() async throws {
        let validation = ControlledWebRetryDelay()
        var validations = 0
        let (model, player, item) = makeBackgroundNativePlayer { _, _ in
            validations += 1
            try? await validation.wait()
            return .invalid("Controlled cancelled preparation")
        }
        defer { model.cleanup(); validation.advance() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        let plays = player.playCount, pauses = player.pauseCount
        XCTAssertFalse(model.shouldResumeAfterForeground, "Healthy background PiP has no foreground resume request")

        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
        let failure = try XCTUnwrap(nativeFailureRecords(source: source.id, attempt: attempt).first)
        XCTAssertEqual(failure.details["reason_code"], "native_failure_backgrounded")
        XCTAssertEqual(failure.details["native_failure_trigger"], "failed_to_play_to_end")
        XCTAssertEqual(failure.details["native_error_domain"], "coremedia")
        XCTAssertEqual(failure.details["native_error_code"], "-12312")
        XCTAssertEqual(failure.details["native_hls_issue"], "segment_uri_changed")
        XCTAssertEqual(failure.details["playback_intent"], "true")
        XCTAssertEqual(failure.details["failure_kind"], "sourceFailure")
        XCTAssertFalse(failure.details.values.contains { $0.contains("://") })
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(player.playCount, plays, "A background receipt must not issue Play")
        XCTAssertEqual(player.pauseCount, pauses, "A background receipt must not mutate transport")
        XCTAssertNil(model.loadTask)
        XCTAssertEqual(validations, 0)
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)

        // A fatal item's subsequent paused KVO is not a system-control Pause.
        model.handleNativeTimeControlStatusChanged(.paused)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        model.handleScenePhaseChange(.active)
        let recovery = try XCTUnwrap(model.loadTask)
        await validation.waitUntilSuspended()
        let recoveryAttempt = model.loadRequestID
        XCTAssertNotEqual(recoveryAttempt, attempt)
        XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[source.id], 1)
        XCTAssertEqual(model.activeSource?.id, source.id, "Use the existing native-once retry before failover")
        XCTAssertEqual(validations, 1)
        XCTAssertEqual(nativeFailureRecords(source: source.id, attempt: attempt).count, 1,
                       "Foreground recovery must not duplicate the already recorded fatal observation")

        model.handleScenePhaseChange(.active)
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
        XCTAssertEqual(model.loadRequestID, recoveryAttempt)
        XCTAssertEqual(validations, 1)
        XCTAssertEqual(nativeFailureRecords(source: source.id, attempt: attempt).count, 1)
        model.cleanup(); validation.advance()
        await recovery.value
    }

    func testBackgroundNativeFailureNeverOverridesPauseBeforeOrAfterTheObservation() throws {
        for pauseBeforeFailure in [true, false] {
            var validations = 0
            let (model, player, item) = makeBackgroundNativePlayer { _, _ in
                validations += 1
                return .invalid("A paused fatal item must not reload")
            }
            defer { model.cleanup() }
            let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
            if pauseBeforeFailure { model.togglePlayPause() }
            model.handleNativeItemFailure(item, source: source, requestID: attempt,
                trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
            if !pauseBeforeFailure { model.togglePlayPause() }
            model.handleNativeTimeControlStatusChanged(.paused)
            let plays = player.playCount

            model.handleScenePhaseChange(.active)
            model.handleScenePhaseChange(.active)
            model.handleNativeItemFailure(item, source: source, requestID: attempt,
                trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())

            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertEqual(model.playbackState, .paused(.native))
            XCTAssertFalse(model.shouldResumeAfterForeground)
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertTrue(player.currentItem === item)
            XCTAssertNil(model.loadTask)
            XCTAssertEqual(player.playCount, plays)
            XCTAssertEqual(validations, 0)
            XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
            XCTAssertEqual(nativeFailureRecords(source: source.id, attempt: attempt).count, 1)
        }
    }

    func testBackgroundNativeFailureCannotRecoverAReplacedItemPlayerSourceAttemptOrRetiredSession() throws {
        for replacement in ["item", "player", "source-round-trip", "attempt", "cleanup"] {
            var validations = 0
            let (model, player, item) = makeBackgroundNativePlayer(sessionCount: 2) { _, _ in
                validations += 1
                return .invalid("A stale background failure must not reload")
            }
            defer { model.cleanup() }
            let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
            model.handleNativeItemFailure(item, source: source, requestID: attempt,
                trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
            switch replacement {
            case "item": player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
            case "player": model.player = NativeBackgroundTransportSpyPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
            case "source-round-trip":
                let index = model.currentSourceIndex
                model.currentSourceIndex = (index + 1) % model.sessions.count
                model.currentSourceIndex = index
            case "attempt": model.cancelLoading()
            default: model.cleanup()
            }
            let currentAttempt = model.loadRequestID, currentPlayer = model.player
            model.handleScenePhaseChange(.active)
            if replacement != "source-round-trip" {
                model.handleNativeItemFailure(item, source: source, requestID: attempt,
                    trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
            }
            XCTAssertEqual(model.loadRequestID, currentAttempt, replacement)
            XCTAssertTrue(model.player === currentPlayer, replacement)
            XCTAssertNil(model.loadTask, replacement)
            XCTAssertEqual(validations, 0, replacement)
            XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty, replacement)
            XCTAssertEqual(nativeFailureRecords(source: source.id, attempt: attempt).count, 1, replacement)
        }
    }

    func testRepeatedBackgroundFatalCallbacksAndForegroundEdgesDoNotDuplicateReceiptOrRecovery() throws {
        let (model, player, item) = makeBackgroundNativePlayer { _, _ in
            XCTFail("An offline item cannot start a native retry")
            return .invalid("Unexpected retry")
        }
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        model.isNetworkReachable = false
        for _ in 0..<3 {
            model.handleNativeItemFailure(item, source: source, requestID: attempt,
                trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
        }
        XCTAssertEqual(nativeFailureRecords(source: source.id, attempt: attempt).count, 1)
        model.handleScenePhaseChange(.active)
        XCTAssertTrue(model.pendingRetryAfterNetworkRestore)
        XCTAssertEqual(model.connectionPhase, "Waiting For Network")
        for _ in 0..<3 {
            model.handleScenePhaseChange(.active)
            model.handleNativeItemFailure(item, source: source, requestID: attempt,
                trigger: .failedToPlayToEnd, reportedError: backgroundNativeFailure())
        }
        XCTAssertEqual(nativeFailureRecords(source: source.id, attempt: attempt).count, 1)
        XCTAssertEqual(FottyQualityStore.shared.records().filter {
            $0.name == "network_interruption" && $0.details["source_id"] == source.id.uuidString
                && $0.details["attempt_id"] == attempt.uuidString
        }.count, 1)
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertNil(model.loadTask)
        XCTAssertTrue(model.nativeStartupRetryAttemptsBySource.isEmpty)
    }

    func testBackgroundNativeNonfatalErrorLogDoesNotInventAFailureReceipt() throws {
        let (model, _, item) = makeBackgroundNativePlayer { _, _ in .valid }
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource), attempt = model.loadRequestID
        XCTAssertNotEqual(item.status, .failed)
        model.handleNativeItemFailure(item, source: source, requestID: attempt,
            trigger: .errorLog, reportedError: backgroundNativeFailure())
        XCTAssertTrue(nativeFailureRecords(source: source.id, attempt: attempt).isEmpty)
        XCTAssertNil(model.lastFailureReason)
        XCTAssertNil(model.loadTask)
    }

    func testNativePiPCallbacksUseKnownBackgroundStateWhenTheirDetachedMarkerReportsFalse() {
        for callback in ["activity", "failure", "availability"] {
            let (model, player, item) = makeBackgroundNativePlayer(pipActive: callback != "availability") { _, _ in
                XCTFail("PiP ending in background must not reload")
                return .invalid("Unexpected retry")
            }
            defer { model.cleanup() }
            let attempt = model.loadRequestID, plays = player.playCount
            XCTAssertTrue(model.isPlaying)
            XCTAssertFalse(model.shouldResumeAfterForeground)
            switch callback {
            case "activity": model.handlePictureInPictureActivityChanged(false, isBackgrounded: false)
            case "failure": model.handlePictureInPictureFailure("Picture in Picture could not start.", isBackgrounded: false)
            default: model.handlePictureInPictureAvailabilityChanged(false, isBackgrounded: false)
            }
            XCTAssertEqual(model.playbackState, .paused(.native), callback)
            XCTAssertTrue(model.shouldResumeAfterForeground, callback)
            XCTAssertTrue(model.userWantsPlayback, callback)
            XCTAssertEqual(player.playCount, plays, callback)
            XCTAssertTrue(player.currentItem === item, callback)
            XCTAssertEqual(model.loadRequestID, attempt, callback)
            XCTAssertNil(model.loadTask, callback)
        }
    }

    func testNativePiPFalseBackgroundCallbackStillPreservesExplicitPause() {
        let (model, player, item) = makeBackgroundNativePlayer { _, _ in .valid }
        defer { model.cleanup() }
        model.togglePlayPause()
        let attempt = model.loadRequestID, plays = player.playCount
        model.handlePictureInPictureActivityChanged(false, isBackgrounded: false)
        model.handlePictureInPictureFailure("Picture in Picture could not start.", isBackgrounded: false)
        model.handlePictureInPictureAvailabilityChanged(false, isBackgrounded: false)
        model.handleScenePhaseChange(.active)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertFalse(model.shouldResumeAfterForeground)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(player.playCount, plays)
        XCTAssertNil(model.loadTask)
    }

    /// Empty local items plus explicit state are ownership/intent fixtures, not
    /// evidence of actual decoded video, OS PiP or background audio continuity.
    private func makeBackgroundNativePlayer(sessionCount: Int = 1, pipActive: Bool = true,
        validation: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult
    ) -> (LivePlayerViewModel, NativeBackgroundTransportSpyPlayer, AVPlayerItem) {
        let model = makeSourcePlayer(sessions: (0..<sessionCount).map { _ in csSession(web: false) }, validation: validation)
        let item = AVPlayerItem(asset: AVMutableComposition())
        let player = NativeBackgroundTransportSpyPlayer(playerItem: item)
        model.player = player
        model.transition(to: .playing(.native), phase: "Playing")
        model.isPictureInPictureAvailable = true
        if pipActive { model.handlePictureInPictureActivityChanged(true) }
        model.handleScenePhaseChange(.background)
        return (model, player, item)
    }

    private func backgroundNativeFailure() -> NSError {
        NSError(domain: "CoreMediaErrorDomain", code: -12312,
            userInfo: [NSLocalizedDescriptionKey: "Media entry URL not match previous playlist for media-sequence 42 https://private.example/never-log"])
    }

    private func nativeFailureRecords(source: UUID, attempt: UUID) -> [FottyQualityRecord] {
        FottyQualityStore.shared.records().filter {
            $0.name == "source_failure" && $0.details["source_id"] == source.uuidString
                && $0.details["attempt_id"] == attempt.uuidString
        }
    }

    func testNativeExplicitPauseSurvivesDelayedNetworkLossAndRestoration() async throws {
        var validations = 0
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in
            validations += 1
            return .invalid("A paused attempt must not reload")
        }
        defer { model.cleanup() }
        // No item or URL is opened: the real network owner would try to reload
        // this native source if it incorrectly changed the paused intent.
        model.player = AVPlayer()
        model.transition(to: .playing(.native), phase: "Playing")
        let attempt = model.loadRequestID
        model.handleNetworkReachabilityChange(false)
        model.togglePlayPause()

        try await Task.sleep(for: .milliseconds(2_100))
        model.handleNetworkReachabilityChange(true)
        await model.loadTask?.value

        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertFalse(model.pendingRetryAfterNetworkRestore)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(validations, 0)
    }

    func testNativeExplicitPauseCancelsStallValidationAndIgnoresLateFailure() async throws {
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in
            .invalid("A paused attempt must not reload")
        }
        defer { model.cleanup() }
        model.player = AVPlayer()
        model.transition(to: .playing(.native), phase: "Playing")
        let source = try XCTUnwrap(model.activeSource)
        let attempt = model.loadRequestID
        model.validateRecoverableStall(for: source, reason: "Playback stalled", requestID: attempt)
        let validation = try XCTUnwrap(model.stallValidationTask)
        model.validateRecoverableStall(for: source, reason: "Another AV error-log notification", requestID: attempt)
        XCTAssertEqual(model.stallValidationTask, validation)
        XCTAssertFalse(validation.isCancelled, "Repeated notifications cannot postpone recovery indefinitely")
        await Task.yield()

        model.togglePlayPause()
        XCTAssertTrue(validation.isCancelled)
        await validation.value
        model.handleSourceStartupFailure(source, reason: "Late stall failure", countsAsStall: true,
                                         expectedRequestID: attempt)
        model.handleNativeTimeControlStatusChanged(.playing)

        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertEqual(model.loadRequestID, attempt)
        XCTAssertTrue(model.failedSourceIDs.isEmpty)
        XCTAssertEqual(model.autoFailoverCount, 0)
        XCTAssertNil(model.loadTask)
    }

    func testNativeExplicitPlayRenewsIntentAfterPause() {
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in .valid }
        defer { model.cleanup() }
        model.player = AVPlayer()
        model.transition(to: .playing(.native), phase: "Playing")

        model.togglePlayPause()
        XCTAssertFalse(model.userWantsPlayback)
        model.togglePlayPause()
        model.handleNativeTimeControlStatusChanged(.playing)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))
    }

    func testNativePictureInPictureControlsUpdateExplicitIntent() {
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in .valid }
        defer { model.cleanup() }
        model.player = AVPlayer()
        model.transition(to: .playing(.native), phase: "Playing")
        model.handlePictureInPictureActivityChanged(true)

        model.handleNativeTimeControlStatusChanged(.paused)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .paused(.native))
        model.handleNativeTimeControlStatusChanged(.playing)

        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertEqual(model.playbackState, .playing(.native))
        XCTAssertEqual(model.connectionPhase, "PiP Active")
    }

    func testNativeBackgroundSuspensionPreservesPlayIntent() {
        let model = makeSourcePlayer(sessions: [csSession(web: false)]) { _, _ in .valid }
        defer { model.cleanup() }
        model.player = AVPlayer()
        model.transition(to: .playing(.native), phase: "Playing")

        model.handleScenePhaseChange(.background)
        model.handleNativeTimeControlStatusChanged(.paused)

        XCTAssertTrue(model.userWantsPlayback, "System suspension is not a user Pause")
        XCTAssertTrue(model.shouldResumeAfterForeground)
        XCTAssertEqual(model.playbackState, .paused(.native))
    }

    func testWatchTwoUninterruptedRetryExecutesOnceAndReleasesOwnership() async {
        let owner = MultiLiveWebRetryOwner()
        let delay = ControlledWebRetryDelay()
        let source = UUID()
        let attempt = UUID()
        var retryCount = 0
        let retry = owner.schedule(sourceID: source, attemptID: attempt,
            delay: { try await delay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: attempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await delay.waitUntilSuspended()
        XCTAssertTrue(owner.isPending)

        delay.advance()
        await retry.value
        delay.advance()
        await Task.yield()

        XCTAssertEqual(retryCount, 1)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoDecodedRecoveryCancelsUncooperativeRetry() async {
        let owner = MultiLiveWebRetryOwner()
        let delay = ControlledWebRetryDelay()
        let source = UUID()
        let attempt = UUID()
        var retryCount = 0
        let retry = owner.schedule(sourceID: source, attemptID: attempt,
            delay: { try await delay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: attempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await delay.waitUntilSuspended()

        owner.cancel() // The panel's decoded-progress/started callbacks do this.
        delay.advance()
        await retry.value

        XCTAssertTrue(retry.isCancelled)
        XCTAssertEqual(retryCount, 0)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoRetryRejectsRecoveredSameAttemptWithoutReloading() async {
        let owner = MultiLiveWebRetryOwner()
        let delay = ControlledWebRetryDelay()
        let source = UUID()
        let attempt = UUID()
        var isRecovering = true
        var retryCount = 0
        let retry = owner.schedule(sourceID: source, attemptID: attempt,
            delay: { try await delay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: attempt, isActive: true,
                      playbackMayStart: true, isRecovering: isRecovering)
            }, onRetry: { retryCount += 1 })
        await delay.waitUntilSuspended()

        isRecovering = false
        delay.advance()
        await retry.value

        XCTAssertEqual(retryCount, 0)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoRetryRejectsReselectedSameSourceWithNewAttempt() async {
        let owner = MultiLiveWebRetryOwner()
        let delay = ControlledWebRetryDelay()
        let source = UUID()
        let originalAttempt = UUID()
        var currentAttempt = originalAttempt
        var retryCount = 0
        let retry = owner.schedule(sourceID: source, attemptID: originalAttempt,
            delay: { try await delay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: currentAttempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await delay.waitUntilSuspended()

        currentAttempt = UUID()
        delay.advance()
        await retry.value

        XCTAssertEqual(retryCount, 0)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoRetryRejectsReplacedSource() async {
        let owner = MultiLiveWebRetryOwner()
        let delay = ControlledWebRetryDelay()
        let originalSource = UUID()
        let attempt = UUID()
        var currentSource = originalSource
        var retryCount = 0
        let retry = owner.schedule(sourceID: originalSource, attemptID: attempt,
            delay: { try await delay.wait() }, currentContext: {
                .init(sourceID: currentSource, attemptID: attempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await delay.waitUntilSuspended()

        currentSource = UUID()
        delay.advance()
        await retry.value

        XCTAssertEqual(retryCount, 0)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoRetryRequiresAnActivePanelAndPlaybackPermission() async {
        // onDisappear clears isActive; user Pause, background and network loss
        // independently revoke the panel's composed playbackMayStart permission.
        for contextFlags in [(isActive: false, mayStart: true), (isActive: true, mayStart: false)] {
            let owner = MultiLiveWebRetryOwner()
            let delay = ControlledWebRetryDelay()
            let source = UUID()
            let attempt = UUID()
            var retryCount = 0
            let retry = owner.schedule(sourceID: source, attemptID: attempt,
                delay: { try await delay.wait() }, currentContext: {
                    .init(sourceID: source, attemptID: attempt, isActive: contextFlags.isActive,
                          playbackMayStart: contextFlags.mayStart, isRecovering: true)
                }, onRetry: { retryCount += 1 })
            await delay.waitUntilSuspended()

            delay.advance()
            await retry.value

            XCTAssertEqual(retryCount, 0)
            XCTAssertFalse(owner.isPending)
        }
    }

    func testWatchTwoReplacedTimerCannotClearTheNewTimerOwnership() async {
        let owner = MultiLiveWebRetryOwner()
        let oldDelay = ControlledWebRetryDelay()
        let newDelay = ControlledWebRetryDelay()
        let source = UUID()
        let oldAttempt = UUID()
        let newAttempt = UUID()
        var retryCount = 0
        let oldRetry = owner.schedule(sourceID: source, attemptID: oldAttempt,
            delay: { try await oldDelay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: oldAttempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await oldDelay.waitUntilSuspended()
        let newRetry = owner.schedule(sourceID: source, attemptID: newAttempt,
            delay: { try await newDelay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: newAttempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await newDelay.waitUntilSuspended()

        oldDelay.advance()
        await oldRetry.value
        XCTAssertEqual(retryCount, 0)
        XCTAssertTrue(owner.isPending, "The abandoned timer cannot clear its replacement")
        newDelay.advance()
        await newRetry.value

        XCTAssertEqual(retryCount, 1)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoRejectedDelayReleasesOwnership() async {
        let owner = MultiLiveWebRetryOwner()
        let delay = ControlledWebRetryDelay()
        let source = UUID()
        let attempt = UUID()
        var retryCount = 0
        let retry = owner.schedule(sourceID: source, attemptID: attempt,
            delay: { try await delay.wait() }, currentContext: {
                .init(sourceID: source, attemptID: attempt, isActive: true,
                      playbackMayStart: true, isRecovering: true)
            }, onRetry: { retryCount += 1 })
        await delay.waitUntilSuspended()

        delay.advance(throwing: CancellationError())
        await retry.value

        XCTAssertEqual(retryCount, 0)
        XCTAssertFalse(owner.isPending)
    }

    func testWatchTwoAudioControlAvailabilityMatchesRoutingThroughFailureAndRecovery() {
        var viable: Set<String> = ["left", "right"]
        XCTAssertTrue(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "right", viableSlotIDs: viable))
        viable.remove("right")
        XCTAssertFalse(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "right", viableSlotIDs: viable))
        XCTAssertTrue(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "left", viableSlotIDs: viable))
        // A source retry alone does not make the failed pane viable again.
        XCTAssertFalse(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "right", viableSlotIDs: viable))
        viable.insert("right")
        XCTAssertTrue(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "right", viableSlotIDs: viable))
        XCTAssertFalse(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "unknown", viableSlotIDs: viable))
        XCTAssertFalse(MultiLiveAudioControlPolicy.canRequestAudio(slotID: "right", viableSlotIDs: []))
    }

    func testWatchTwoGoalAudioKeepsWorkingPanelWhenScoringPanelIsUnavailable() {
        XCTAssertFalse(MultiLiveGoalAudioPolicy.shouldFocus(
            slotID: "failed", currentAudioSlotID: "playing", viableSlotIDs: ["playing"],
            scoreIncreased: true
        ))
        XCTAssertTrue(MultiLiveGoalAudioPolicy.shouldFocus(
            slotID: "recovered", currentAudioSlotID: "playing", viableSlotIDs: ["playing", "recovered"],
            scoreIncreased: true
        ))
        XCTAssertFalse(MultiLiveGoalAudioPolicy.shouldFocus(
            slotID: "playing", currentAudioSlotID: "playing", viableSlotIDs: ["playing"],
            scoreIncreased: true
        ))
        XCTAssertFalse(MultiLiveGoalAudioPolicy.shouldFocus(
            slotID: "other", currentAudioSlotID: "playing", viableSlotIDs: ["playing", "other"],
            scoreIncreased: false
        ))
    }

    func testNativePiPRequestPublishesAfterUIViewUpdateAndHandlesLatestRequestOnce() async {
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        defer { view.dismantlePlaybackBinding() }
        var failureCount = 0
        view.onPictureInPictureFailure = { _ in failureCount += 1 }

        view.pictureInPictureRequestID = UUID()
        let latestRequest = UUID()
        view.pictureInPictureRequestID = latestRequest
        view.pictureInPictureRequestID = latestRequest
        XCTAssertEqual(failureCount, 0, "Setting UIView inputs must never publish synchronously")

        await drainNativePlayerMainQueue()
        // A surface without a player item cannot start PiP. Only the latest
        // request may report that failure; replaced/duplicate requests are inert.
        XCTAssertEqual(failureCount, 1)
        view.pictureInPictureRequestID = latestRequest
        await drainNativePlayerMainQueue()
        XCTAssertEqual(failureCount, 1)
    }

    func testClearingNativePiPRequestCancelsItsQueuedCommand() async {
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        defer { view.dismantlePlaybackBinding() }
        var failureCount = 0
        view.onPictureInPictureFailure = { _ in failureCount += 1 }

        view.pictureInPictureRequestID = UUID()
        view.pictureInPictureRequestID = nil
        await drainNativePlayerMainQueue()

        XCTAssertEqual(failureCount, 0)
    }

    func testDismantledNativeSurfaceCannotPublishQueuedObservationOrPiPRequest() async {
        let view = AVPlayerLayerView.PlayerUIView(frame: .zero)
        var publicationCount = 0
        view.onReadyForDisplayChanged = { _ in publicationCount += 1 }
        view.onTimeControlStatusChanged = { _ in publicationCount += 1 }
        view.onPictureInPictureAvailabilityChanged = { _ in publicationCount += 1 }
        view.onPictureInPictureActiveChanged = { _ in publicationCount += 1 }
        view.onPictureInPictureFailure = { _ in publicationCount += 1 }
        view.pictureInPictureRequestID = UUID()

        view.dismantlePlaybackBinding()
        await drainNativePlayerMainQueue()

        XCTAssertEqual(publicationCount, 0)
        XCTAssertNil(view.player)
        XCTAssertNil(view.pictureInPictureRequestID)
    }

    private func drainNativePlayerMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
