import XCTest
@testable import Fotty

/// Player shrink slice 4: one attempt fence with an explicit scope.
@MainActor
final class PlaybackAttemptTests: XCTestCase {
    private let request = UUID(), source = UUID(), playback = UUID(), audio = UUID()

    private func current(request: UUID? = nil, source: UUID?? = nil,
                         playback: UUID? = nil, audio: UUID? = nil) -> PlaybackAttempt.Current {
        .init(requestID: request ?? self.request, sourceID: source ?? self.source,
              playbackIntent: playback ?? self.playback, audioIntent: audio ?? self.audio)
    }

    func testRequestOnlyScopeIgnoresSourceAndIntents() {
        let attempt = PlaybackAttempt(capturing: current(), scope: [])
        XCTAssertTrue(attempt.isCurrent(in: current()))
        XCTAssertTrue(attempt.isCurrent(in: current(source: .some(UUID()), playback: UUID(), audio: UUID())))
        XCTAssertFalse(attempt.isCurrent(in: current(request: UUID())))
        XCTAssertEqual(attempt, PlaybackAttempt(requestID: request))
    }

    func testEachScopeComparesOnlyItsOwnPart() {
        let source = PlaybackAttempt(capturing: current(), scope: .source)
        XCTAssertFalse(source.isCurrent(in: current(source: .some(UUID()))))
        XCTAssertTrue(source.isCurrent(in: current(playback: UUID(), audio: UUID())))

        let playback = PlaybackAttempt(capturing: current(), scope: .playbackIntent)
        XCTAssertFalse(playback.isCurrent(in: current(playback: UUID())))
        XCTAssertTrue(playback.isCurrent(in: current(source: .some(UUID()), audio: UUID())))

        let audio = PlaybackAttempt(capturing: current(), scope: .audioIntent)
        XCTAssertFalse(audio.isCurrent(in: current(audio: UUID())))
        XCTAssertTrue(audio.isCurrent(in: current(source: .some(UUID()), playback: UUID())))

        let all = PlaybackAttempt(capturing: current(), scope: [.source, .playbackIntent, .audioIntent])
        XCTAssertTrue(all.isCurrent(in: current()))
        XCTAssertFalse(all.isCurrent(in: current(request: UUID())))
    }

    /// The inline checks compared optional source IDs, so a captured nil source
    /// stays current while there is still no source, and not after one appears.
    func testCapturedNilSourceMatchesOnlyNil() {
        let attempt = PlaybackAttempt(capturing: current(source: .some(nil)), scope: .source)
        XCTAssertNil(attempt.sourceID)
        XCTAssertTrue(attempt.isCurrent(in: current(source: .some(nil))))
        XCTAssertFalse(attempt.isCurrent(in: current()))
    }

    func testUncapturedPartsAreNotStored() {
        let attempt = PlaybackAttempt(capturing: current(), scope: .source)
        XCTAssertEqual(attempt.sourceID, source)
        XCTAssertNil(attempt.playbackIntent)
        XCTAssertNil(attempt.audioIntent)
        XCTAssertEqual(attempt, PlaybackAttempt(requestID: request, sourceID: source))
        XCTAssertNotEqual(attempt, PlaybackAttempt(requestID: request, sourceID: UUID()))
        XCTAssertNotEqual(attempt, PlaybackAttempt(requestID: request), "Scope is part of identity")
    }

    /// Slice 4b: work that captured its parts at different moments supplies
    /// them explicitly. Parts outside the scope are dropped, not compared.
    func testExplicitScopeKeepsOnlyScopedParts() {
        let startup = PlaybackAttempt(requestID: request, scope: [.source, .audioIntent],
            sourceID: source, playbackIntent: UUID(), audioIntent: audio)
        XCTAssertNil(startup.playbackIntent)
        XCTAssertEqual(startup, PlaybackAttempt(capturing: current(), scope: [.source, .audioIntent]))
        XCTAssertTrue(startup.isCurrent(in: current(playback: UUID())))
        XCTAssertFalse(startup.isCurrent(in: current(audio: UUID())))
        XCTAssertFalse(startup.isCurrent(in: current(source: .some(UUID()))))

        let seek = PlaybackAttempt(requestID: request, scope: .playbackIntent, sourceID: source, playbackIntent: playback)
        XCTAssertNil(seek.sourceID)
        XCTAssertTrue(seek.isCurrent(in: current(source: .some(UUID()))),
            "The Watch Two seek callback never fenced on source; its scope is kept")
        XCTAssertFalse(seek.isCurrent(in: current(playback: UUID())))
        XCTAssertEqual(PlaybackAttempt(requestID: request, scope: .source, sourceID: source),
                       PlaybackAttempt(requestID: request, sourceID: source))
    }

    /// On a real player model, source selection keeps the load request, so a
    /// request-only fence survives it and a source fence does not. Cancelling
    /// the load replaces the request and ends both.
    func testPlayerSourceChangeAndCancellationRespectScope() throws {
        let event = AnalyticalDataEngine.EventReference(id: "attempt-\(UUID().uuidString)", title: "Attempt Test",
            category: "football", date: Int64(Date().timeIntervalSince1970), poster: nil, popular: false,
            teams: nil, sources: nil)
        let sessions = try (0..<2).map { index in
            StreamSession(matchID: event.id, title: "Attempt \(index)",
                playableURL: try XCTUnwrap(URL(string: "https://example.com/attempt/\(index).m3u8")),
                streamType: .hls, providerName: "CS\(index + 1)", requiredHeaders: [:], qualityLabel: "HD")
        }
        let model = LivePlayerViewModel(event: event, providedSessions: sessions, ownsRemoteCommands: false)
        model.currentSourceIndex = 0
        let requestOnly = model.captureAttempt([])
        let sourceBound = model.captureAttempt(.source)
        XCTAssertTrue(model.isCurrent(requestOnly))
        XCTAssertTrue(model.isCurrent(sourceBound))

        model.currentSourceIndex = 1
        XCTAssertTrue(model.isCurrent(requestOnly))
        XCTAssertFalse(model.isCurrent(sourceBound))

        // Slice 4c shorthand for work handed a request and source.
        XCTAssertTrue(model.isCurrent(requestID: requestOnly.requestID))
        XCTAssertTrue(model.isCurrent(requestID: requestOnly.requestID, sourceID: sessions[1].id))
        XCTAssertFalse(model.isCurrent(requestID: requestOnly.requestID, sourceID: sessions[0].id))

        model.cancelLoading()
        XCTAssertFalse(model.isCurrent(requestOnly))
        XCTAssertFalse(model.isCurrent(requestID: requestOnly.requestID))
        XCTAssertTrue(model.isCurrent(model.captureAttempt([])), "A fresh capture is current")
    }
}
