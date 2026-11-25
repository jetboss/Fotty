import Foundation

/// Nullable, delayed football-data reporting, separate from Fotty's active
/// live-score feed. No timestamp is synthesized from a successful cache read.
struct UCLReportedScore: Codable, Equatable, Sendable {
    let home: Int
    let away: Int
    let publisherUpdatedAt: String
    var publisherDate: Date? { SportsFixtureCatalog.date(publisherUpdatedAt) }

    var isWellFormed: Bool {
        (0...99).contains(home) && (0...99).contains(away) && publisherDate != nil
    }

    func validated(sport: String, competitionID: String, kind: SportsFixtureCatalog.EventKind,
                   participants: [SportsFixtureCatalog.Participant], squad: SportsFixtureCatalog.Squad,
                   status: SportsFixtureCatalog.Status, sourceName: String, sourceUpdatedAt: String?) -> Self? {
        guard isWellFormed, sport == "football", competitionID == "champions-league", kind == .match,
              squad == .init(gender: .men, ageGroup: "senior"), status == .live || status == .finished,
              sourceName == "football-data.org", let sourceUpdatedAt,
              SportsFixtureCatalog.date(sourceUpdatedAt) == publisherDate,
              participants.count == 2, Set(participants.map(\.id)).count == 2,
              Set(participants.compactMap(\.role)) == ["home", "away"],
              participants.allSatisfy({ $0.id.range(of: #"^football-data:[1-9][0-9]{0,11}$"#,
                  options: .regularExpression) != nil }) else { return nil }
        return self
    }
}

@MainActor
enum UCLReportedScorePolicy {
    /// This bounds use of a retrieved fixture, not the publisher's delivery
    /// latency. Display retains the actual publisher time and delayed qualifier.
    static let receiptFreshness: TimeInterval = 30 * 60

    static func score(for event: EventReference, at now: Date = Date()) -> UCLReportedScore? {
        guard !event.hasCatalogIdentityConflict, event.normalizedCategory == "football",
              event.competitionID == "champions-league", let fixture = event.sportsFixture, fixture.verified,
              fixture.sport == "football", fixture.competitionID == "champions-league", fixture.eventKind == .match,
              fixture.fixtureID == event.id,
              fixture.fixtureID.range(of: #"^sports-fixture:champions-league:[1-9][0-9]{0,11}$"#,
                  options: .regularExpression) != nil,
              fixture.status == .live || fixture.status == .finished,
              fixture.squad == .init(gender: .men, ageGroup: "senior"),
              fixture.participants.count == 2, Set(fixture.participants.map(\.id)).count == 2,
              Set(fixture.participants.compactMap(\.role)) == ["home", "away"],
              fixture.participants.allSatisfy({ $0.id.range(of: #"^football-data:[1-9][0-9]{0,11}$"#,
                  options: .regularExpression) != nil }),
              let receivedAt = fixture.reportedScoreObservedAt,
              (-300...receiptFreshness).contains(now.timeIntervalSince(receivedAt)),
              let score = fixture.reportedScore, score.isWellFormed, let publishedAt = score.publisherDate,
              publishedAt <= now.addingTimeInterval(300), publishedAt <= receivedAt.addingTimeInterval(300),
              let kickoff = event.kickoffDate, kickoff <= now.addingTimeInterval(300),
              publishedAt >= kickoff.addingTimeInterval(-300),
              kickoff >= now.addingTimeInterval(-3 * 86_400) else { return nil }
        return score
    }
}
