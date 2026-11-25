import AVFoundation
import XCTest
@testable import Fotty

/// Offline ownership tests. Injected validation rejects before an item can
/// request media; health assertions use the real decoded-success store.
@MainActor
final class SingleNativeFallbackPolicyTests: XCTestCase {
    func testFreshDecodedAlternativeUsesActualHealthAndAllowsBoundWebOrNilDeliveryExpiry() throws {
        let restore = preserveHealthDefaults(); defer { restore() }
        let fixture = try willowFixture()
        XCTAssertFalse(LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: fixture.cs.legacySource))
        XCTAssertTrue(eligible([fixture.tv, fixture.cs], fixture: fixture).isEmpty)
        LiveSourceHealthStore.recordSuccess(for: fixture.cs, startupLatencyMs: 3_643,
            contextKey: LiveSourceHealthStore.contextKey(for: fixture.event))
        XCTAssertTrue(LiveSourceHealthStore.hasFreshSingleStreamSuccess(for: fixture.cs.legacySource))
        XCTAssertEqual(eligible([fixture.tv, fixture.cs], fixture: fixture), [fixture.cs.id])

        let web = try session(event: fixture.event, provider: "CS2", now: fixture.now, web: true, expiry: nil)
        LiveSourceHealthStore.recordSuccess(for: web, startupLatencyMs: 2_000)
        XCTAssertEqual(eligible([fixture.tv, web], fixture: fixture), [web.id],
            "A proven admitted web choice or absent delivery-expiry field must not be discarded")
    }

    func testAlternativeEligibilityRequiresCurrentBindingDeliveryValidationIdentityAndPositiveEvidence() throws {
        let fixture = try willowFixture()
        for condition in ["current_source", "no_positive", "unbound", "unvalidated", "expired_binding", "expired_delivery", "wrong_event", "wrong_provider"] {
            let boundAt = condition == "expired_binding" ? fixture.now.addingTimeInterval(-120) : fixture.now
            let other = condition == "wrong_event"
                ? CricketChannelCatalog.event(for: .foxCricket, in: []) : fixture.event
            let candidate = try session(event: other, provider: condition == "wrong_provider" ? "AS1" : "CS1",
                now: boundAt, expiry: condition == "expired_delivery" ? fixture.now.addingTimeInterval(-1) : fixture.now.addingTimeInterval(90),
                validation: condition == "unvalidated" ? .pending : .validated, bound: condition != "unbound")
            let currentID = condition == "current_source" ? candidate.id : fixture.tv.id
            let result = LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(in: [candidate],
                for: fixture.event, after: currentID, failureKind: .startupTimeout, hasDecoded: false, at: fixture.now,
                hasPositivePlayback: { _ in condition != "no_positive" })
            XCTAssertTrue(result.isEmpty, condition)
        }
        for kind in [LivePlaybackFailureKind.accessDenied, .providerUnavailable, .unsupportedSource, .stalled, .network, .decodeFailure] {
            XCTAssertTrue(LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(in: [fixture.cs],
                for: fixture.event, after: fixture.tv.id, failureKind: kind, hasDecoded: false, at: fixture.now,
                hasPositivePlayback: { _ in true }).isEmpty, kind.rawValue)
        }
        XCTAssertTrue(LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(in: [fixture.cs],
            for: fixture.event, after: fixture.tv.id, failureKind: .startupTimeout, hasDecoded: true, at: fixture.now,
            hasPositivePlayback: { _ in true }).isEmpty)
    }

    func testAlternativeRejectsCorrectedOrTerminalFixtureEvenWithPositivePlayback() throws {
        let now = Date(), id = "sports-fixture:premier-league:native-fallback-" + UUID().uuidString
        let original = fixtureEvent(id: id, kickoff: now.addingTimeInterval(-600), status: .live, now: now)
        let alternative = try session(event: original, provider: "CS1", now: now, expiry: now.addingTimeInterval(90))
        XCTAssertEqual(LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(in: [alternative],
            for: original, after: UUID(), failureKind: .startupTimeout, hasDecoded: false, at: now,
            hasPositivePlayback: { _ in true }), [alternative.id])
        for event in [fixtureEvent(id: id, kickoff: now.addingTimeInterval(-540), status: .live, now: now),
            fixtureEvent(id: id, kickoff: now.addingTimeInterval(-600), status: .finished, now: now),
            fixtureEvent(id: id, kickoff: now.addingTimeInterval(-600), status: .cancelled, now: now),
            fixtureEvent(id: id, kickoff: now.addingTimeInterval(3_600), status: .scheduled, now: now),
            EventReference(id: original.id, title: original.title, category: original.category, date: original.date,
                poster: nil, popular: false, teams: original.teams, hasCatalogIdentityConflict: true,
                sportsFixture: original.sportsFixture)] {
            XCTAssertTrue(LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(in: [alternative],
                for: event, after: UUID(), failureKind: .startupTimeout, hasDecoded: false, at: now,
                hasPositivePlayback: { _ in true }).isEmpty)
        }
    }

    func testInitialTVReadinessTimeoutUsesAlreadyAdmittedDecodedCSBeforeRetryingTV() async throws {
        let restore = preserveHealthDefaults(); defer { restore() }
        let fixture = try willowFixture()
        LiveSourceHealthStore.recordSuccess(for: fixture.cs, startupLatencyMs: 3_643,
            contextKey: LiveSourceHealthStore.contextKey(for: fixture.event))
        var renewed: [UUID] = [], validated: [URL] = []
        let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.tv, fixture.cs], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Rejected validation cannot activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Rejected validation cannot configure audio"); return .completed([]) },
            validateNativeSource: { url, _ in validated.append(url); return Self.rejectedMedia },
            refreshSourceDescriptor: { selected, _ in renewed.append(selected.id); return selected })
        defer { model.cleanup() }
        model.didApplyLandscape = true
        XCTAssertTrue(model.configureSingleStreamRanking())
        model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == fixture.tv.id })
        model.transition(to: .connecting(.native), phase: "Buffering...")
        let attempt = model.loadRequestID
        model.handleSourceStartupFailure(fixture.tv.legacySource, reason: "Native readiness timeout.", expectedRequestID: attempt,
            diagnosticDetails: ["native_failure_trigger": NativePlaybackDiagnosticTrigger.readinessTimeout.rawValue])
        await model.loadTask?.value
        XCTAssertTrue(renewed.isEmpty, "Known decoded CS must get its turn before another TV descriptor retry")
        XCTAssertEqual(validated, [fixture.cs.playableURL])
        XCTAssertEqual(model.activeSession?.id, fixture.cs.id)
        XCTAssertTrue(model.failedSourceIDs.contains(fixture.tv.id))
        XCTAssertNil(model.nativeStartupRetryAttemptsBySource[fixture.tv.id], "Switching does not spend a retry that never ran")
        XCTAssertEqual(model.autoFailoverCount, 1)
        XCTAssertNotEqual(model.loadRequestID, attempt)
        XCTAssertNil(model.player?.currentItem)
    }

    func testMissingExpiredMismatchedOrAlreadyFailedAlternativePreservesTheSelectedTVRetry() async throws {
        let restore = preserveHealthDefaults(); defer { restore() }
        for condition in ["no_positive", "expired_binding", "wrong_event", "failed_alternative"] {
            let fixture = try willowFixture()
            let event = condition == "wrong_event" ? CricketChannelCatalog.event(for: .foxCricket, in: []) : fixture.event
            let alternative = try session(event: event, provider: "CS1",
                now: condition == "expired_binding" ? fixture.now.addingTimeInterval(-120) : fixture.now,
                expiry: fixture.now.addingTimeInterval(90))
            if condition != "no_positive" { LiveSourceHealthStore.recordSuccess(for: alternative, startupLatencyMs: 3_000) }
            var renewed: [UUID] = [], validated: [URL] = []
            weak var owner: LivePlayerViewModel?
            let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.tv, alternative], ownsRemoteCommands: false,
                prepareAudioSession: { XCTFail("Controlled cancellation cannot activate audio"); return .completed([]) },
                configureAudioSession: { XCTFail("Controlled cancellation cannot configure audio"); return .completed([]) },
                validateNativeSource: { url, _ in
                    validated.append(url); owner?.cancelLoading(); return Self.rejectedMedia
                }, refreshSourceDescriptor: { selected, _ in renewed.append(selected.id); return selected })
            defer { model.cleanup() }
            owner = model; model.didApplyLandscape = true
            XCTAssertTrue(model.configureSingleStreamRanking())
            if condition == "failed_alternative" {
                model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == alternative.id })
                model.transition(to: .connecting(.native), phase: "Buffering...")
                model.handleSourceStartupFailure(alternative.legacySource, reason: "Controlled rejection", expectedRequestID: model.loadRequestID,
                    diagnosticDetails: PlaybackPreparationDiagnostic(stage: .contractValidation, reason: .httpStatus, httpStatus: 403).qualityDetails)
                await model.loadTask?.value
                XCTAssertTrue(model.failedSourceIDs.contains(alternative.id))
                validated.removeAll(); renewed.removeAll()
            }
            model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == fixture.tv.id })
            model.error = nil
            model.transition(to: .connecting(.native), phase: "Buffering...")
            model.handleSourceStartupFailure(fixture.tv.legacySource, reason: "Native readiness timeout.", expectedRequestID: model.loadRequestID,
                diagnosticDetails: ["native_failure_trigger": NativePlaybackDiagnosticTrigger.readinessTimeout.rawValue])
            await model.loadTask?.value
            XCTAssertEqual(renewed, [fixture.tv.id], condition)
            XCTAssertEqual(validated, [fixture.tv.playableURL], condition)
            XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[fixture.tv.id], 1, condition)
            XCTAssertEqual(model.activeSession?.id, fixture.tv.id, condition)
        }
    }

    func testProvenAlternativeDoesNotChangeSharedOrNativeWatchTwoStartupRetry() async throws {
        let restore = preserveHealthDefaults(); defer { restore() }
        for context in ["shared", "watch_two"] {
            let fixture = try willowFixture()
            LiveSourceHealthStore.recordSuccess(for: fixture.cs, startupLatencyMs: 3_000)
            var validated: [URL] = [], renewals = 0
            weak var owner: LivePlayerViewModel?
            let model = LivePlayerViewModel(event: fixture.event, providedSessions: [fixture.tv, fixture.cs], ownsRemoteCommands: false,
                prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
                validateNativeSource: { url, _ in validated.append(url); owner?.cancelLoading(); return Self.rejectedMedia },
                refreshSourceDescriptor: { selected, _ in renewals += 1; return selected })
            defer { model.cleanup() }
            owner = model; model.didApplyLandscape = true
            if context == "watch_two" {
                XCTAssertTrue(model.configureSingleStreamRanking())
                XCTAssertTrue(model.prepareForViewingPlaybackContext(.watchTwo(engine: .native)))
            }
            model.currentSourceIndex = try XCTUnwrap(model.sessions.firstIndex { $0.id == fixture.tv.id })
            model.transition(to: .connecting(.native), phase: "Buffering...")
            model.handleSourceStartupFailure(fixture.tv.legacySource, reason: "Native readiness timeout.", expectedRequestID: model.loadRequestID,
                diagnosticDetails: ["native_failure_trigger": NativePlaybackDiagnosticTrigger.readinessTimeout.rawValue])
            await model.loadTask?.value
            XCTAssertEqual(validated, [fixture.tv.playableURL], context)
            XCTAssertEqual(renewals, 0, context)
            XCTAssertEqual(model.activeSession?.id, fixture.tv.id, context)
            XCTAssertEqual(model.nativeStartupRetryAttemptsBySource[fixture.tv.id], 1, context)
        }
    }

    private typealias Fixture = (event: EventReference, now: Date, tv: StreamSession, cs: StreamSession)

    private func willowFixture() throws -> Fixture {
        let now = Date(), event = CricketChannelCatalog.event(for: .willow, in: [])
        return (event, now, try session(event: event, provider: "TV1", now: now, expiry: now.addingTimeInterval(90)),
            try session(event: event, provider: "CS1", now: now, expiry: now.addingTimeInterval(90)))
    }

    private func session(event: EventReference, provider: String, now: Date, web: Bool = false,
                         expiry: Date?, validation: StreamValidationStatus = .validated, bound: Bool = true) throws -> StreamSession {
        let code = provider == "TV1" ? "reviewedtv" : "communitysports"
        let upstreamID = provider == "TV1" ? ReviewedTVPlaylistClient.providerEventID : "nuvio_sport_fallback"
        let binding = try XCTUnwrap(StreamEventBinding(request: StreamPlaybackRequest(event: event), providerCode: code,
            providerEventID: upstreamID, streamID: upstreamID, manifestRevision: "test",
            verifiedAt: now, expiresAt: now.addingTimeInterval(90), at: now))
        return StreamSession(matchID: event.id, playableURL: URL(string: "https://fallback-\(UUID().uuidString.lowercased()).example/\(web ? "watch" : "live.m3u8")")!,
            streamType: web ? .unknown : .hls, providerName: provider, requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:],
            expiryTime: expiry, canRefresh: true, validationStatus: validation, createdAt: now, eventBinding: bound ? binding : nil)
    }

    private func eligible(_ sessions: [StreamSession], fixture: Fixture) -> Set<UUID> {
        LivePlaybackSourcePolicy.provenAlternativesBeforeNativeStartupRetry(in: sessions, for: fixture.event,
            after: fixture.tv.id, failureKind: .startupTimeout, hasDecoded: false)
    }

    private func fixtureEvent(id: String, kickoff: Date, status: SportsFixtureCatalog.Status, now: Date) -> EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: id, sport: "football", competitionID: "premier-league",
            competitionName: "Premier League", eventKind: .match, title: "Arsenal vs Chelsea",
            participants: [.init(id: "arsenal", name: "Arsenal"), .init(id: "chelsea", name: "Chelsea")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: true)
        return .init(id: id, title: metadata.title, category: "football", date: Int64(kickoff.timeIntervalSince1970), poster: nil,
            popular: false, teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), sportsFixture: metadata)
    }

    private static var rejectedMedia: StreamContractValidator.ValidationResult {
        .invalid("Controlled rejection", diagnostics: .init(stage: .contractValidation, reason: .httpStatus, httpStatus: 403))
    }

    private func preserveHealthDefaults() -> () -> Void {
        let keys = ["fotty.live.sourceHealth.v1", "fotty.live.lastGoodProvider.v1"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        return {
            for (index, key) in keys.enumerated() {
                if let value = previous[index] { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
    }
}
