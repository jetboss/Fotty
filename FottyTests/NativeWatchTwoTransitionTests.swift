import XCTest
import AVFoundation
@testable import Fotty

/// Ownership/intent regressions only. Local compositions and an injected audio
/// backend do not claim readiness, decoded video, or physical concurrency.
@MainActor
final class NativeWatchTwoTransitionTests: XCTestCase {
    func testMissingCapturedCandidateRejectsPreflightWithoutValidatingOrRetiringWorkingWeb() async throws {
        var validations = 0
        let model = try makeModel(validate: { _, _ in validations += 1; return .valid })
        defer { model.cleanup() }
        let source = model.activeSource?.id, request = model.loadRequestID
        let prepared = await model.prepareNativeWatchTwoCandidate()
        XCTAssertNil(prepared)
        XCTAssertEqual(validations, 0)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertTrue(model.shouldDisplayWebPlayback)
        XCTAssertFalse(model.isRetiringWebForNativeWatchTwo)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNil(model.player)
    }

    func testPreparedTokenCapturesExactOwnerIntentAndPreservesSourceIdentityWithoutPlaying() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        let original = try XCTUnwrap(model.activeSession)
        let prepared = try await makePrepared(model)
        defer { model.discardNativeWatchTwoCandidate(prepared) }

        XCTAssertEqual(prepared.modelID, model.remoteCommandOwnerID)
        XCTAssertEqual(prepared.sourceID, original.id)
        XCTAssertEqual(prepared.requestID, model.loadRequestID)
        XCTAssertEqual(prepared.intentID, model.nativeWatchTwoIntentID)
        XCTAssertEqual(prepared.wantsPlayback, model.userWantsPlayback)
        XCTAssertEqual(prepared.context, .watchTwo(engine: .web))
        XCTAssertEqual(prepared.session.providerName, original.providerName)
        XCTAssertEqual(prepared.session.title, original.title)
        XCTAssertEqual(prepared.session.qualityLabel, original.qualityLabel)
        XCTAssertEqual(model.sessions.map(\.id), [original.id])
        XCTAssertTrue(prepared.player === prepared.isolation.player)
        XCTAssertTrue(prepared.player.currentItem === prepared.item)
        XCTAssertTrue(prepared.player.isMuted)
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0)
        XCTAssertFalse(prepared.retirementBegan)
        XCTAssertFalse(prepared.webRetired)
        XCTAssertFalse(prepared.adopted)
        XCTAssertFalse(prepared.started)
    }

    func testCapturedCandidateValidationFailurePreservesOriginalWebWithoutRetiring() async throws {
        var validations = 0
        let model = try makeModel(validate: { _, _ in validations += 1; return .invalid("Offline rejection") })
        defer { model.cleanup() }
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        model.handleNativePlaybackCandidate(.init(url: try XCTUnwrap(URL(string: "https://example.invalid/rejected.m3u8")),
            headers: [:], cookies: []), sourceID: source, requestID: request)
        let prepared = await model.prepareNativeWatchTwoCandidate()
        XCTAssertNil(prepared)
        XCTAssertEqual(validations, 1)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertTrue(model.shouldDisplayWebPlayback)
        XCTAssertFalse(model.isRetiringWebForNativeWatchTwo)
        XCTAssertNil(model.player)
    }

    func testScopedWebCookiePreflightValidatesOwnedLocalRelayWithoutFlatteningCookiesOrRetiringWeb() async throws {
        var validations: [(URL, [String: String])] = []
        let model = try makeModel(validate: { url, headers in
            validations.append((url, headers))
            return .invalid("Offline validator stops before AVPlayer media preparation")
        })
        defer { model.cleanup() }
        // The relay deliberately rejects .invalid/.test destinations. This
        // admitted example domain is never resolved: only loopback ping runs,
        // and the injected validator rejects before an upstream media fetch.
        let candidateURL = try XCTUnwrap(URL(string: "https://media.example.com/live/cookie-owner.m3u8"))
        XCTAssertTrue(LocalStreamProxyPolicy.allowsDestination(candidateURL))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "scoped-preflight-test", .value: "synthetic-cookie-only",
            .domain: "media.example.com", .path: "/live/", .secure: "TRUE",
            .expires: Date().addingTimeInterval(3_600)
        ]))
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        let intent = model.nativeWatchTwoIntentID, choices = model.sessions.map(\.id)
        model.handleNativePlaybackCandidate(.init(url: candidateURL, headers: [:], cookies: [cookie]),
            sourceID: source, requestID: request)

        let prepared = await model.prepareNativeWatchTwoCandidate()

        XCTAssertNil(prepared)
        XCTAssertEqual(validations.count, 1)
        let validation = try XCTUnwrap(validations.first)
        XCTAssertEqual(validation.0.scheme, "http")
        XCTAssertEqual(validation.0.host, "127.0.0.1", "Cookie-bound delivery must be validated through the existing scoped relay")
        XCTAssertNotNil(validation.0.port)
        XCTAssertNil(validation.0.query, "The relay uses an owned capability, not an arbitrary URL query")
        let components = validation.0.pathComponents
        XCTAssertEqual(components.count, 4)
        if components.count == 4 {
            XCTAssertGreaterThanOrEqual(components[1].count, 32)
            XCTAssertEqual(components[2], "media")
            XCTAssertFalse(components[3].isEmpty)
        }
        XCTAssertTrue(validation.1.isEmpty, "The relay owns cookie scope; native validation must not flatten Cookie headers")
        XCTAssertFalse(validation.0.absoluteString.contains(cookie.name))
        XCTAssertFalse(validation.0.absoluteString.contains(cookie.value))
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.nativeWatchTwoIntentID, intent)
        XCTAssertEqual(model.sessions.map(\.id), choices)
        XCTAssertEqual(model.viewingPlaybackContext, .watchTwo(engine: .web))
        XCTAssertTrue(model.shouldDisplayWebPlayback)
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertFalse(model.isRetiringWebForNativeWatchTwo)
        XCTAssertNil(model.nativeHandoffSession)
        XCTAssertNil(model.player)
        XCTAssertEqual(model.nativeWatchTwoPreflightOutcome, .validationRejected)
    }

    func testStaleSourceRequestContextAndItemCannotRetireOrAdoptTheOriginalPreparedToken() async throws {
        for change in ["source", "request", "context", "item"] {
            let model = try makeModel(twoSources: true)
            defer { model.cleanup() }
            let prepared = try await makePrepared(model)
            defer { model.discardNativeWatchTwoCandidate(prepared) }
            XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
            XCTAssertTrue(model.nativeWatchTwoPreparationIsCurrent(prepared))
            switch change {
            case "source": model.currentSourceIndex = model.currentSourceIndex == 0 ? 1 : 0
            case "request": model.cancelLoading()
            case "context": model.setViewingPlaybackContext(.single)
            case "item": prepared.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
            default: XCTFail("Unknown regression case")
            }
            XCTAssertFalse(model.nativeWatchTwoPreparationIsCurrent(prepared), change)
            XCTAssertFalse(model.beginNativeWatchTwoRetirement(prepared), change)
            XCTAssertFalse(model.adoptNativeWatchTwoCandidate(prepared), change)
            XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0, change)
        }
    }

    func testInterveningPauseThenPlayInvalidatesPreparedIntentEvenWhenTheFinalBooleanMatches() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        let prepared = try await makePrepared(model)
        defer { model.discardNativeWatchTwoCandidate(prepared) }
        XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
        model.togglePlayPause()
        XCTAssertFalse(model.userWantsPlayback)
        model.togglePlayPause()
        XCTAssertTrue(model.userWantsPlayback)
        XCTAssertNotEqual(model.nativeWatchTwoIntentID, prepared.intentID)
        XCTAssertFalse(model.nativeWatchTwoPreparationIsCurrent(prepared))
        XCTAssertFalse(model.beginNativeWatchTwoRetirement(prepared))
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0)
    }

    func testOnlyActualExactWebTeardownCanAuthorizeNativeAdoptionNotManagedMuteReceipt() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        _ = model.revokeViewingAudioForTransfer()
        let source = try XCTUnwrap(model.activeSource?.id), request = model.loadRequestID
        let muteRequest = try XCTUnwrap(model.webAudioRevocationID)
        let prepared = try await makePrepared(model)
        defer { model.discardNativeWatchTwoCandidate(prepared) }
        XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
        XCTAssertTrue(model.beginNativeWatchTwoRetirement(prepared))
        XCTAssertFalse(model.shouldDisplayWebPlayback, "Retirement must remove the actual representable, not cover it")
        XCTAssertTrue(model.isUsingWebEmbed, "The original source identity remains until adoption")
        model.handleWebAudioRevocationAcknowledged(muteRequest, sourceID: source, requestID: request)
        XCTAssertFalse(prepared.webRetired, "A DOM mute receipt does not prove WK teardown")
        XCTAssertFalse(model.adoptNativeWatchTwoCandidate(prepared))
        model.handleWebPlaybackRetired(sourceID: UUID(), requestID: request)
        model.handleWebPlaybackRetired(sourceID: source, requestID: UUID())
        XCTAssertFalse(prepared.webRetired)
        model.handleWebPlaybackRetired(sourceID: source, requestID: request)
        let retired = await model.waitForNativeWatchTwoRetirement(prepared)
        XCTAssertTrue(retired)
        XCTAssertTrue(model.adoptNativeWatchTwoCandidate(prepared))
        XCTAssertEqual(model.activePlaybackEngine, .native)
        XCTAssertEqual(model.viewingPlaybackContext, .watchTwo(engine: .native))
        XCTAssertTrue(model.player === prepared.player)
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0, "Adoption is not Play")
        XCTAssertTrue(prepared.player.isMuted)
    }

    func testDeliberatelyPausedPaneRemainsPausedThroughoutNativeCommitAndStart() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        model.togglePlayPause()
        XCTAssertFalse(model.userWantsPlayback)
        let prepared = try await makePrepared(model)
        XCTAssertFalse(prepared.wantsPlayback)
        XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
        XCTAssertTrue(model.beginNativeWatchTwoRetirement(prepared))
        model.handleWebPlaybackRetired(sourceID: prepared.sourceID, requestID: prepared.requestID)
        XCTAssertTrue(model.adoptNativeWatchTwoCandidate(prepared))
        model.startNativeWatchTwoCandidate(prepared)
        model.releaseNativeWatchTwoAudioHold(prepared)
        XCTAssertTrue(prepared.started)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0)
        XCTAssertNil(model.loadTask, "Paused playback is not decoded by playing a hidden probe")
    }

    func testProviderPauseDeliveredBeforeActualTeardownRevokesPreparedIntentAndCannotBeOverridden() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        let prepared = try await makePrepared(model)
        defer { model.discardNativeWatchTwoCandidate(prepared) }
        XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
        XCTAssertTrue(model.beginNativeWatchTwoRetirement(prepared))
        model.handleWebEmbedTransportState(.paused, sourceID: prepared.sourceID, requestID: prepared.requestID)
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertNotEqual(model.nativeWatchTwoIntentID, prepared.intentID)
        XCTAssertFalse(model.nativeWatchTwoPreparationIsCurrent(prepared))
        model.handleWebPlaybackRetired(sourceID: prepared.sourceID, requestID: prepared.requestID)
        XCTAssertFalse(model.adoptNativeWatchTwoCandidate(prepared), "Late teardown cannot restore superseded Play intent")
        model.startNativeWatchTwoCandidate(prepared)
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0)
        XCTAssertFalse(prepared.started)
    }

    func testDiscardAfterAcknowledgedActualTeardownCannotMintANewLeaseForTheMissingWebView() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        _ = model.revokeViewingAudioForTransfer()
        XCTAssertNotNil(model.webAudioRevocationID)
        XCTAssertNotNil(model.captureWebAudioRevocationWaiter())
        let prepared = try await makePrepared(model)
        XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
        XCTAssertTrue(model.beginNativeWatchTwoRetirement(prepared))
        model.handleWebPlaybackRetired(sourceID: prepared.sourceID, requestID: prepared.requestID)
        XCTAssertTrue(prepared.webRetired)
        XCTAssertNil(model.captureWebAudioRevocationWaiter(), "Actual retirement settles the existing exact-owner lease")
        model.discardNativeWatchTwoCandidate(prepared)
        _ = model.revokeViewingAudioForTransfer()
        XCTAssertTrue(prepared.discarded)
        XCTAssertNil(model.captureWebAudioRevocationWaiter(), "There is no mounted Web owner capable of acknowledging a fresh lease")
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0)
    }

    func testAdoptedConnectingTokenSurvivesKeepingItsExactNativePlayerAsSingleView() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        let prepared = try await registerRetireAndAdopt(model)
        let source = model.activeSource?.id, request = model.loadRequestID
        XCTAssertEqual(model.playbackState, .connecting(.native))
        model.setViewingPlaybackContext(.single)
        XCTAssertEqual(model.viewingPlaybackContext, .single)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertTrue(model.player === prepared.player)
        XCTAssertTrue(model.player?.currentItem === prepared.item)
        XCTAssertTrue(model.nativeWatchTwoPreparationIsCurrent(prepared), "Presentation cannot abandon accepted native startup")
        model.startNativeWatchTwoCandidate(prepared)
        model.loadTask?.cancel()
        XCTAssertTrue(prepared.started)
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0,
            "The cancelled test task cannot start media after its fixture completes")
    }

    func testNativePairFailureKeepsCapturedNativeEndpointInsteadOfAutomaticallyReturningToWeb() async throws {
        let model = try makeModel()
        defer { model.cleanup() }
        let prepared = try await registerRetireAndAdopt(model)
        let source = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        model.transition(to: .playing(.native), phase: "Playing")
        model.handleSourceStartupFailure(source, reason: "Native pair item failed", expectedRequestID: request)
        XCTAssertEqual(model.playbackState, .failed)
        XCTAssertEqual(model.viewingPlaybackContext, .watchTwo(engine: .native))
        XCTAssertEqual(model.activePlaybackEngine, .native)
        XCTAssertEqual(model.activeSession?.playableURL, prepared.session.playableURL)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertFalse(model.forceWebEmbedSourceIDs.contains(source.id))
        XCTAssertFalse(model.shouldDisplayWebPlayback)
        XCTAssertEqual((prepared.player as? WatchTwoTransportSpyPlayer)?.playCount, 0)
    }

    func testExplicitRetryKeepsExactCapturedNativeRouteAndOriginalSourceChoices() async throws {
        let model = try makeModel(twoSources: true)
        defer { model.cleanup() }
        let originalChoices = model.sessions.map { ($0.id, $0.providerName, $0.qualityLabel) }
        let prepared = try await registerRetireAndAdopt(model)
        let oldRequest = model.loadRequestID
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        // Cancel synchronously before its task can create URL-backed media.
        model.loadTask?.cancel()
        XCTAssertNotEqual(model.loadRequestID, oldRequest)
        XCTAssertEqual(model.viewingPlaybackContext, .watchTwo(engine: .native))
        XCTAssertEqual(model.activeSession?.playableURL, prepared.session.playableURL)
        XCTAssertEqual(model.activePlaybackEngine, .native)
        XCTAssertEqual(model.sessions.map(\.id), originalChoices.map(\.0))
        XCTAssertEqual(model.sessions.map(\.providerName), originalChoices.map(\.1))
        XCTAssertEqual(model.sessions.map(\.qualityLabel), originalChoices.map(\.2))
        XCTAssertFalse(model.shouldDisplayWebPlayback)
    }

    func testForeignUnmutedAndUnisolatedCandidatesCannotRegister() async throws {
        let model = try makeModel(), foreign = try makeModel()
        defer { model.cleanup(); foreign.cleanup() }
        let foreignToken = try await makePrepared(foreign)
        defer { foreign.discardNativeWatchTwoCandidate(foreignToken) }
        XCTAssertFalse(model.registerNativeWatchTwoPreparation(foreignToken))
        let unmuted = try await makePrepared(model)
        defer { model.discardNativeWatchTwoCandidate(unmuted) }
        unmuted.player.isMuted = false
        XCTAssertFalse(model.registerNativeWatchTwoPreparation(unmuted))
        unmuted.player.isMuted = true
        let reconnected = await unmuted.isolation.request(disconnected: false).wait()
        XCTAssertTrue(reconnected)
        XCTAssertFalse(model.registerNativeWatchTwoPreparation(unmuted), "A satisfied reconnect is not disconnection permission")
    }

    private func registerRetireAndAdopt(_ model: LivePlayerViewModel) async throws -> PreparedNativeWatchTwoPlayback {
        let prepared = try await makePrepared(model)
        XCTAssertTrue(model.registerNativeWatchTwoPreparation(prepared))
        XCTAssertTrue(model.beginNativeWatchTwoRetirement(prepared))
        model.handleWebPlaybackRetired(sourceID: prepared.sourceID, requestID: prepared.requestID)
        XCTAssertTrue(model.adoptNativeWatchTwoCandidate(prepared))
        return prepared
    }

    private func makeModel(twoSources: Bool = false,
        validate: @escaping @MainActor (URL, [String: String]) async -> StreamContractValidator.ValidationResult = { _, _ in .valid }
    ) throws -> LivePlayerViewModel {
        let event = EventReference(id: "native-watch-two-transition", title: "Test Home vs Test Away",
            category: "football", date: 1_800_000_000, poster: nil, popular: false,
            teams: .init(home: .init(name: "Test Home", badge: nil), away: .init(name: "Test Away", badge: nil)))
        func session(_ index: Int) throws -> StreamSession {
            StreamSession(matchID: event.id, title: "Original Broadcast \(index)",
                playableURL: try XCTUnwrap(URL(string: "https://www.score808live.tv/embed/admin/native-watch-two/\(index)")),
                streamType: .unknown, providerName: "Score808",
                requiredHeaders: ["X-Fotty-Nexus-Source":"admin", "X-Fotty-Web-Embed":"true"],
                qualityLabel: "Source \(index)")
        }
        let sessions = try (twoSources ? [1, 2] : [1]).map(session)
        let model = LivePlayerViewModel(event: event, providedSessions: sessions, ownsRemoteCommands: false,
            prepareAudioSession: { .completed([]) }, configureAudioSession: { .completed([]) },
            validateNativeSource: validate, nativeAudioIsolationBackend: .init(isSupported: true, setDisconnected: { _, _ in true }))
        model.setViewingPlaybackContext(.watchTwo(engine: .web))
        // Establish the real started-attempt/lease state, then cancel the Web
        // preparation task synchronously before any actor yield or WK mount.
        model.loadCurrentSource(ignoringCircuitBreaker: true)
        model.loadTask?.cancel()
        model.loadTask = nil
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        model.isVideoReadyForDisplay = true
        return model
    }

    private func makePrepared(_ model: LivePlayerViewModel) async throws -> PreparedNativeWatchTwoPlayback {
        let original = try XCTUnwrap(model.activeSession)
        let native = StreamSession(id: original.id, matchID: original.matchID, title: original.title,
            playableURL: try XCTUnwrap(URL(string: "https://example.invalid/verified-watch-two.m3u8")),
            streamType: .hls, providerName: original.providerName, requiredHeaders: [:],
            qualityLabel: original.qualityLabel)
        let item = AVPlayerItem(asset: AVMutableComposition())
        let player = WatchTwoTransportSpyPlayer(playerItem: item)
        player.isMuted = true
        let isolation = NativePlayerAudioIsolation(player: player, item: item,
            backend: .init(isSupported: true, setDisconnected: { _, _ in true }))
        let disconnected = await isolation.request(disconnected: true).wait()
        XCTAssertTrue(disconnected)
        return PreparedNativeWatchTwoPlayback(model: model, session: native, player: player,
            item: item, isolation: isolation)
    }
}

private final class WatchTwoTransportSpyPlayer: AVPlayer {
    private let countLock = NSLock()
    private var plays = 0
    var playCount: Int {
        countLock.lock(); defer { countLock.unlock() }
        return plays
    }
    override func play() {
        countLock.lock(); defer { countLock.unlock() }
        plays += 1
    }
}
