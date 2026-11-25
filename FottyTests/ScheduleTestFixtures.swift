import Foundation
@testable import Fotty

/// Minimal verified schedules for tests that need Home's rows. Since the
/// shared catalog closed, Home's rows come only from these schedules.
enum ScheduleTestFixtures {
    static func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    /// A clock on a whole second: ISO 8601 receipts carry no fractional part.
    static func wholeSecond(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// A sports schedule with one NBA match per `ids` entry, checked at `checkedAt`.
    static func sports(kickoff: Date, checkedAt: Date, ids: [String] = ["continuity"],
                       status: SportsFixtureCatalog.SourceStatus = .verified) -> SportsFixtureCatalog.Snapshot {
        let fixtures = ids.map { id in
            SportsFixtureCatalog.Fixture(id: "sports-fixture:nba:\(id)", sport: "basketball",
                start: stamp(kickoff), status: .scheduled, eventKind: .match, title: "Boston Celtics vs New York Knicks",
                competitionId: "nba", competitionName: "NBA",
                participants: [.init(id: "boston", name: "Boston Celtics"), .init(id: "new-york", name: "New York Knicks")],
                squad: .init(gender: .men, ageGroup: "senior"),
                source: .init(name: "Official schedule", url: "https://www.espn.com/nba/schedule",
                              observedAt: stamp(checkedAt), verification: nil))
        }
        let coverage = SportsFixtureCatalog.Coverage(sport: "basketball", competitionId: "nba", competitionName: "NBA",
            status: .covered, checkedAt: stamp(checkedAt), fixtureCount: fixtures.count, pendingFixtureCount: 0, nextStart: nil)
        return .init(schemaVersion: 1, complete: true, checkedAt: stamp(checkedAt), revision: "test-\(ids.joined(separator: "-"))",
                     sourceStatus: status, fixtures: fixtures, coverage: [coverage])
    }

    static func cricket(checkedAt: Date, status: CricketFixtureCatalog.SourceStatus = .verified) -> CricketFixtureCatalog.Snapshot {
        .init(schemaVersion: 1, complete: true, checkedAt: stamp(checkedAt), revision: "test-cricket",
              sourceStatus: status, fixtures: [], coverage: [])
    }
}
