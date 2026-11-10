import AVFoundation
import XCTest
@testable import Fotty

@MainActor
final class SinglePlaybackFeedbackContextTests: XCTestCase {
    private func model(title: String = "Liverpool vs Chelsea", provider: String = "AS1",
                       web: Bool = false, single: Bool = true) -> LivePlayerViewModel {
        let event = EventReference(id: "report-fixture", title: title, category: "football",
            date: Int64(Date().timeIntervalSince1970) - 60, poster: nil, popular: false, teams: nil, sources: [])
        let session = StreamSession(matchID: event.id,
            playableURL: URL(string: web ? "https://private.example/embed?token=private-secret" : "https://private.example/master.m3u8?token=private-secret")!,
            streamType: web ? .unknown : .hls, providerName: provider,
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true", "Authorization": "Bearer owner-secret"]
                : ["Authorization": "Bearer owner-secret"])
        let model = LivePlayerViewModel(event: event, providedSessions: [session], ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Preparing a report must not activate audio"); return .completed([]) })
        if single { XCTAssertTrue(model.configureSingleStreamRanking()) }
        return model
    }

    func testNormalSingleReportUsesCurrentTypedContextWithoutRequiringPlaybackFailure() throws {
        let model = model()
        defer { model.cleanup() }
        model.transition(to: .playing(.native), phase: "arbitrary provider phase must not be copied")
        let context = try XCTUnwrap(SinglePlaybackFeedbackContext.make(model: model))

        XCTAssertTrue(context.expected.contains("Liverpool vs Chelsea"))
        XCTAssertTrue(context.actual.contains("Source: AS1 (option 1)"))
        XCTAssertTrue(context.actual.contains("Player: Native"))
        XCTAssertTrue(context.actual.contains("State: Playing"))
        XCTAssertTrue(context.actual.contains("Last observed stage: preparing"))
        XCTAssertFalse(context.actual.contains("Failure category:"))
        XCTAssertFalse(context.actual.contains("arbitrary provider phase"))
        XCTAssertNil(model.loadTask)
        XCTAssertFalse(model.didStartPlayback)
    }

    func testReportCopiesNoTransportLinksCredentialsIdentifiersOrRawError() throws {
        let model = model()
        defer { model.cleanup() }
        model.error = "https://owner.invalid/failure?token=raw-secret Authorization: Bearer error-secret"
        let context = try XCTUnwrap(SinglePlaybackFeedbackContext.make(model: model))
        let output = context.expected + context.actual

        XCTAssertTrue(output.contains("Source unavailable"))
        XCTAssertTrue(output.contains("Failure category: unknown"))
        for forbidden in ["https://", "private.example", "private-secret", "owner-secret", "owner.invalid",
                          "raw-secret", "error-secret", "Authorization", model.loadRequestID.uuidString,
                          try XCTUnwrap(model.activeSource).id.uuidString] {
            XCTAssertFalse(output.contains(forbidden), forbidden)
        }
    }

    func testUntrustedMatchAndProviderStringsAreReplacedRatherThanCopied() throws {
        let model = model(title: "https://private.example/signed?token=secret", provider: "https://provider.example/token")
        defer { model.cleanup() }
        let context = try XCTUnwrap(SinglePlaybackFeedbackContext.make(model: model))

        XCTAssertTrue(context.expected.contains("the selected match"))
        XCTAssertTrue(context.actual.contains("Unknown source"))
        XCTAssertFalse(context.actual.contains("private.example"))
        XCTAssertFalse(context.actual.contains("provider.example"))
        XCTAssertFalse(context.actual.contains("token"))
    }

    func testReportPreparationPreservesPausedNativeItemAttemptAndFullscreen() throws {
        let model = model()
        defer { model.cleanup() }
        let item = ReadyFeedbackItem(asset: AVMutableComposition()), player = AVPlayer()
        player.replaceCurrentItem(with: item)
        model.player = player
        model.transition(to: .playing(.native), phase: "Playing")
        model.togglePlayPause()
        model.isVideoReadyForDisplay = true
        model.beginNativeFullscreen()
        let fullscreen = try XCTUnwrap(model.nativeFullscreen)
        let source = model.activeSource?.id, request = model.loadRequestID

        let context = try XCTUnwrap(SinglePlaybackFeedbackContext.make(model: model))
        let preserved = FottyFeedbackDraftSeed.resolved(existingExpected: "My unfinished report", existingActual: "",
            suggestedExpected: context.expected, suggestedActual: context.actual)

        XCTAssertEqual(preserved.expected, "My unfinished report")
        XCTAssertEqual(preserved.actual, "")
        XCTAssertTrue(context.actual.contains("State: Paused"))
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertTrue(model.nativeFullscreen === fullscreen)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.playbackState, .paused(.native))
        XCTAssertFalse(model.userWantsPlayback)
        XCTAssertEqual(player.rate, 0)
        XCTAssertNil(model.loadTask)
    }

    func testWebContextIsHonestAndDoesNotAlterPlaybackOwnership() throws {
        let model = model(web: true)
        defer { model.cleanup() }
        model.transition(to: .playing(.webEmbed), phase: "Playing")
        let request = model.loadRequestID, source = model.activeSource?.id, command = model.webPlaybackCommand?.id
        let context = try XCTUnwrap(SinglePlaybackFeedbackContext.make(model: model))

        XCTAssertTrue(context.actual.contains("Player: Web"))
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertEqual(model.activeSource?.id, source)
        XCTAssertEqual(model.webPlaybackCommand?.id, command)
        XCTAssertEqual(model.playbackState, .playing(.webEmbed))
        XCTAssertNil(model.loadTask)
    }

    func testPairSharedInitializerAndRetiredOwnersCannotSupplySingleReportContext() {
        let shared = model(single: false)
        defer { shared.cleanup() }
        XCTAssertNil(SinglePlaybackFeedbackContext.make(model: shared))
        let single = model()
        defer { single.cleanup() }
        single.setViewingPlaybackContext(.watchTwo(engine: .native))
        XCTAssertNil(SinglePlaybackFeedbackContext.make(model: single))
        single.cleanup()
        XCTAssertNil(SinglePlaybackFeedbackContext.make(model: single))
    }

    func testAnActiveLegacyProviderCannotSmuggleCredentialsThroughItsDisplayLabel() throws {
        let model = model(provider: "Score808 Authorization owner-secret")
        defer { model.cleanup() }
        let context = try XCTUnwrap(SinglePlaybackFeedbackContext.make(model: model))
        XCTAssertTrue(context.actual.contains("Unknown source"))
        XCTAssertFalse(context.actual.contains("Authorization"))
        XCTAssertFalse(context.actual.contains("owner-secret"))
    }
}

private final class ReadyFeedbackItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}
