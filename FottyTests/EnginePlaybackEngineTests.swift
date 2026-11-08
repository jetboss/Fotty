import XCTest
@testable import Fotty

@MainActor
final class EnginePlaybackEngineTests: XCTestCase {
    private func session(_ url: String = "https://example.com/a.m3u8") -> StreamSession {
        StreamSession(matchID: "sports-fixture:premier-league:1",
                      playableURL: URL(string: url)!,
                      streamType: .hls,
                      providerName: "a")
    }

    private final class MockTransport: StreamTransport {
        enum Command: Equatable { case prepare(URL), play(URL), pause, stop }
        private(set) var commands: [Command] = []
        var throwsOnPrepare = false
        var kind: TransportKind { .native }

        func prepare(_ session: StreamSession) async throws -> PreparedPlayback {
            commands.append(.prepare(session.playableURL))
            if throwsOnPrepare { throw TransportFailure(category: .relayFailed, retryable: true) }
            return PreparedPlayback(session: session, kind: .native)
        }
        func play(_ prepared: PreparedPlayback) async { commands.append(.play(prepared.session.playableURL)) }
        func pause() async { commands.append(.pause) }
        func stop() async { commands.append(.stop) }
        func snapshot() -> [Command] { commands }
        func setThrowsOnPrepare(_ value: Bool) { throwsOnPrepare = value }
    }

    func testWatchPreparesAndPlays() async {
        let transport = MockTransport()
        let engine = PlaybackEngine(transport: transport)
        let state = await engine.watch(session())
        XCTAssertEqual(state, .playing)
        let commands = transport.snapshot()
        XCTAssertEqual(commands, [.prepare(URL(string: "https://example.com/a.m3u8")!),
                                  .play(URL(string: "https://example.com/a.m3u8")!)])
    }

    func testPrepareFailureReachesFailedState() async {
        let transport = MockTransport()
        transport.setThrowsOnPrepare(true)
        let engine = PlaybackEngine(transport: transport)
        let state = await engine.watch(session())
        XCTAssertEqual(state, .failed(reason: .init(category: .decodingFailed, retryable: true)))
    }

    func testPauseReturnsToIdle() async {
        let transport = MockTransport()
        let engine = PlaybackEngine(transport: transport)
        _ = await engine.watch(session())
        await engine.pause()
        let state = engine.state
        XCTAssertEqual(state, .idle)
    }

    func testStopReturnsToIdle() async {
        let transport = MockTransport()
        let engine = PlaybackEngine(transport: transport)
        _ = await engine.watch(session())
        await engine.stop()
        let state = engine.state
        XCTAssertEqual(state, .idle)
    }

    func testWatchFromPlayingIsIgnored() async {
        let transport = MockTransport()
        let engine = PlaybackEngine(transport: transport)
        _ = await engine.watch(session())
        let state = await engine.watch(session())
        XCTAssertEqual(state, .playing, "A second watch from .playing is an illegal transition")
    }
}
