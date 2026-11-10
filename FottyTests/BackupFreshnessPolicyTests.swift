import XCTest
@testable import Fotty

/// Player shrink slice 2: the backup-freshness policy is pure and testable
/// without a LivePlayerViewModel.
@MainActor
final class BackupFreshnessPolicyTests: XCTestCase {
    private let matchID = "sports-fixture:premier-league:backup-policy"

    private func session(_ provider: String, _ path: String, matchID: String? = nil,
                         expiry: Date? = nil, binding: StreamEventBinding? = nil) -> StreamSession {
        StreamSession(matchID: matchID ?? self.matchID, playableURL: URL(string: "https://media.example/\(path).m3u8")!,
                      streamType: .hls, providerName: provider, expiryTime: expiry,
                      createdAt: binding?.verifiedAt ?? Date(), eventBinding: binding)
    }

    private let allPlayable: (StreamSession) -> Bool = { _ in true }

    func testFreshLookupReplacesSameFamilyAroundAFixedPlayingIndex() throws {
        let staleBefore = session("CS2", "stale-before"), active = session("CS1", "active")
        let staleAfter = session("CS3", "stale-after"), other = session("AS1", "other-family")
        let freshA = session("CS4", "fresh-a"), freshB = session("CS5", "fresh-b")
        let duplicate = session("CS6", "active")
        let rebuilt = try XCTUnwrap(BackupFreshnessPolicy.replacingBackups(
            in: [staleBefore, active, staleAfter, other], with: [freshA, duplicate, freshB],
            active: active, matchID: matchID, isPlayable: allPlayable))
        XCTAssertEqual(rebuilt.map(\.id), [freshA.id, active.id, other.id, freshB.id],
                       "Stale CS refilled in place before the playing index, dropped after it, fresh appended")
        XCTAssertEqual(rebuilt.firstIndex { $0.id == active.id }, 1, "The playing session keeps its index")
        XCTAssertEqual(rebuilt.filter { $0.playableURL == active.playableURL }.count, 1, "No duplicate of the playing delivery")
    }

    func testNoUsableFreshChoiceChangesNothing() {
        let active = session("CS1", "active"), backup = session("CS2", "backup")
        let cases: [[StreamSession]] = [
            [],
            [session("CS3", "other-match", matchID: "sports-fixture:premier-league:other")],
            [session("CS3", "expired", expiry: Date().addingTimeInterval(-1))],
            [session("CS3", "active")],
        ]
        for fresh in cases {
            XCTAssertNil(BackupFreshnessPolicy.replacingBackups(in: [active, backup], with: fresh,
                active: active, matchID: matchID, isPlayable: allPlayable))
        }
        XCTAssertNil(BackupFreshnessPolicy.replacingBackups(in: [active, backup], with: [session("CS3", "fresh")],
            active: active, matchID: matchID, isPlayable: { _ in false }), "Inactive providers are not admitted")
    }

    func testRenewalCandidatesRespectExclusionsCapacityAndOrder() throws {
        let fixture = SportsFixtureMetadata(fixtureID: matchID, sport: "football", competitionID: "premier-league",
            competitionName: "Premier League", eventKind: .match, title: "Chelsea vs Brighton",
            participants: [.init(id: "chelsea", name: "Chelsea"), .init(id: "brighton", name: "Brighton")],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: Date(), verified: true)
        let event = EventReference(id: matchID, title: fixture.title, category: "football",
            date: Int64(Date().timeIntervalSince1970) - 600, poster: nil, popular: false,
            teams: .init(home: .init(name: "Chelsea", badge: nil), away: .init(name: "Brighton", badge: nil)), sportsFixture: fixture, competitionID: "premier-league")
        let old = Date().addingTimeInterval(-120)
        func binding(_ id: String, at time: Date) throws -> StreamEventBinding {
            try XCTUnwrap(StreamEventBinding(request: .init(event: event), providerCode: "communitysports",
                providerEventID: "nuvio_sport_\(id)", streamID: "nuvio_sport_\(id)", manifestRevision: "1",
                verifiedAt: time, expiresAt: time.addingTimeInterval(90), at: time))
        }
        let chosen = session("CS1", "chosen", binding: try binding("a", at: old))
        let failed = session("CS2", "failed", binding: try binding("b", at: old))
        let lapsedA = session("CS3", "lapsed-a", binding: try binding("c", at: old))
        let current = session("CS4", "current", binding: try binding("d", at: Date()))
        let lapsedB = session("CS5", "lapsed-b", binding: try binding("e", at: old))
        let lapsedC = session("CS6", "lapsed-c", binding: try binding("f", at: old))
        let all = [chosen, failed, lapsedA, current, lapsedB, lapsedC]
        let picked = BackupFreshnessPolicy.renewalCandidates(in: all, chosen: chosen.id, failed: [failed.id],
            alreadyRenewed: [], inFlight: [], capacity: 2, supportsRenewal: { _ in true })
        XCTAssertEqual(picked.map(\.id), [lapsedA.id, lapsedB.id], "Lapsed, in list order, capped at capacity")
        let afterInFlight = BackupFreshnessPolicy.renewalCandidates(in: all, chosen: chosen.id, failed: [failed.id],
            alreadyRenewed: [lapsedB.id], inFlight: [lapsedA.id], capacity: 1, supportsRenewal: { _ in true })
        XCTAssertEqual(afterInFlight.map(\.id), [lapsedC.id], "In-flight and already-renewed sources are skipped")
        XCTAssertTrue(BackupFreshnessPolicy.renewalCandidates(in: all, chosen: chosen.id, failed: [],
            alreadyRenewed: [], inFlight: [], capacity: 0, supportsRenewal: { _ in true }).isEmpty)
        XCTAssertTrue(BackupFreshnessPolicy.renewalCandidates(in: all, chosen: chosen.id, failed: [],
            alreadyRenewed: [], inFlight: [], capacity: 4, supportsRenewal: { _ in false }).isEmpty)
    }

    func testFamilyGroupsChoicesByProviderCode() {
        XCTAssertEqual(BackupFreshnessPolicy.family(session("CS1", "a")), BackupFreshnessPolicy.family(session("CS4", "b")))
        XCTAssertNotEqual(BackupFreshnessPolicy.family(session("CS1", "a")), BackupFreshnessPolicy.family(session("TV1", "c")))
    }
}
