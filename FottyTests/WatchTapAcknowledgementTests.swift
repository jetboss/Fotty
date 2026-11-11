import XCTest
@testable import Fotty

/// Scene reservation and admission ordering, not physical first-frame or
/// decoded playback evidence. No test resolves or starts a media URL.
@MainActor
final class WatchTapAcknowledgementTests: XCTestCase {
    private func event(_ id: String = "watch-feedback", status: SportsFixtureCatalog.Status = .live,
                       conflict: Bool = false) -> EventReference {
        let now = Date(), fixtureID = "sports-fixture:premier-league:\(id)"
        let metadata = SportsFixtureMetadata(fixtureID: fixtureID, sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Arsenal vs Chelsea", participants: [.init(id: "arsenal", name: "Arsenal"),
                .init(id: "chelsea", name: "Chelsea")], squad: .init(gender: .men, ageGroup: "senior"),
            status: status, observedAt: now, verified: true)
        return .init(id: fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(-600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), hasCatalogIdentityConflict: conflict,
            sportsFixture: metadata, competitionID: metadata.competitionID)
    }

    private func cancelled(_ request: StreamPlaybackRequest) -> StreamResolutionOutcome {
        let diagnostics = StreamAttemptDiagnostics(attemptID: "watch-feedback-test", matchID: request.matchID,
            matchTitle: request.displayTitle, finalState: .failed, createdAt: Date(), completedAt: Date(),
            timeline: [], providerAttempts: [])
        return .failure(.init(category: .userCancelled, technicalMessage: "Controlled test cancellation",
            userMessage: "Cancelled", retryable: false, fallbackAllowed: false), diagnostics)
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The bounded Watch operation did not finish", file: file, line: line)
    }

    func testWatchReservesVisiblePendingStateBeforeAdmissionOrDiscoveryAndDeduplicatesTaps() async throws {
        let row = event()
        var admissions = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1
            return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { current in
            admissions += 1
            XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
            XCTAssertNotNil(owner.resolutionMessage)
            return current
        })
        XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
        XCTAssertNotNil(owner.resolutionMessage)
        XCTAssertEqual(admissions, 0, "Synchronous catalog admission must not precede acknowledgement")
        XCTAssertEqual(lookups, 0)
        owner.watchSingle(row, admission: { _ in XCTFail("A duplicate tap must reuse the pending owner"); return nil })
        try await waitFor { lookups == 1 && owner.pendingSingleEvent == nil }
        XCTAssertEqual(admissions, 1)
        XCTAssertEqual(lookups, 1)
        XCTAssertNil(owner.resolutionError)
    }

    func testCancelledPendingWatchDoesNotRunDelayedAdmissionOrDiscovery() async throws {
        let row = event("cancelled")
        var admissions = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { current in admissions += 1; return current })
        XCTAssertNotNil(owner.pendingSingleEvent)
        owner.cancelPendingSingleDiscovery()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(admissions, 0)
        XCTAssertEqual(lookups, 0)
        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.resolutionError)
        XCTAssertTrue(owner.panes.isEmpty)
    }

    func testExpiredWatchActionAcknowledgesThenRejectsVisiblyWithoutResolving() async throws {
        let row = event("expired")
        var lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { _ in XCTFail("Denied caller admission must not reach current-event resolution"); return nil },
            cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { _ in nil })
        XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
        XCTAssertNotNil(owner.resolutionMessage)
        try await waitFor { owner.resolutionError != nil }
        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertEqual(lookups, 0)
        XCTAssertTrue(owner.panes.isEmpty)
    }

    func testTerminalOrConflictingCurrentFixtureCannotStartAfterAcknowledgement() async throws {
        for current in [event("stopped", status: .finished), event("stopped", conflict: true)] {
            let row = event("stopped")
            var lookups = 0
            let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
                lookups += 1; return self.cancelled(request)
            }, currentSingleEvent: { _ in current }, cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.watchSingle(row, admission: { $0 })
            XCTAssertNotNil(owner.pendingSingleEvent)
            try await waitFor { owner.resolutionError != nil }
            XCTAssertEqual(lookups, 0)
            XCTAssertTrue(owner.panes.isEmpty)
        }
    }

    func testSupersedingWatchCannotPublishOrResolveTheEarlierTap() async throws {
        let first = event("first"), second = event("second")
        var admitted: [String] = [], resolved: [String] = []
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            resolved.append(request.matchID); return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(first, admission: { current in admitted.append(current.id); return current })
        owner.watchSingle(second, admission: { current in admitted.append(current.id); return current })
        XCTAssertEqual(owner.pendingSingleEvent?.id, second.id)
        try await waitFor { resolved == [second.id] && owner.pendingSingleEvent == nil }
        XCTAssertEqual(admitted, [second.id])
        XCTAssertNil(owner.resolutionError)
    }

    func testCancellationDuringAdmissionCannotPublishAStaleErrorOrReachDiscovery() async throws {
        let row = event("cancel-during-admission")
        var admissions = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { _ in XCTFail("Cancelled admission must not continue"); return nil }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { _ in
            admissions += 1
            owner.cancelPendingSingleDiscovery()
            return nil
        })
        try await waitFor { admissions == 1 }
        XCTAssertEqual(lookups, 0)
        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertNil(owner.resolutionError)
    }

    func testTVDefersCurrentCatalogReadUntilPendingFeedbackExists() async throws {
        let row = try XCTUnwrap(SportsTVStation.station(provider: "TV2")).event
        var catalogReads = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        SportsTVWatchPolicy.watch(row, using: owner, currentCatalog: {
            catalogReads += 1
            XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
            XCTAssertNotNil(owner.resolutionMessage)
            return []
        })
        XCTAssertEqual(catalogReads, 0)
        XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
        try await waitFor { lookups == 1 && owner.pendingSingleEvent == nil }
        XCTAssertEqual(catalogReads, 1)
    }
}
