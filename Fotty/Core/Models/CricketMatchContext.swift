import Foundation

/// Optional scorecard facts from the same admitted ICC fixture receipt. These
/// facts never establish fixture status, broadcast availability or playback.
struct CricketMatchContext: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case inPlay = "in-play", matchBreak = "break", inningsBreak = "innings-break"
        case stumps, lunch, tea, interrupted, delayed, finished, cancelled, postponed, scheduled

        var title: String {
            switch self {
            case .inPlay: "In play"
            case .matchBreak: "Break"
            case .inningsBreak: "Innings break"
            case .stumps: "Stumps"
            case .lunch: "Lunch"
            case .tea: "Tea"
            case .interrupted: "Interrupted"
            case .delayed: "Delayed"
            case .finished: "Finished"
            case .cancelled: "Cancelled"
            case .postponed: "Postponed"
            case .scheduled: "Scheduled"
            }
        }
    }

    struct Innings: Codable, Equatable, Identifiable, Sendable {
        let number: Int
        let teamID: String
        let runs: Int
        let wickets: Int
        var overs: String? = nil
        var id: Int { number }
    }

    let innings: [Innings]
    var currentInnings: Int? = nil
    var battingTeamID: String? = nil
    var bowlingTeamID: String? = nil
    var day: Int? = nil
    var session: Int? = nil
    /// Exact Test ordinal and scheduled end published with the enclosing ICC
    /// fixture. Neither field supplies a daily kickoff or a match result.
    var matchOrdinal: Int? = nil
    var matchEndsAt: String? = nil
    var phase: Phase? = nil
    var message: String? = nil
    var target: Int? = nil

    /// Validate the enclosing fixture's exact team identities. Preserve repeated
    /// Test batting teams as separate innings; never merge them by team alone.
    func validated(format: CricketFixtureCatalog.Format, homeTeamID: String, awayTeamID: String) -> Self? {
        let maximumInnings: Int
        let maximumOvers: Int
        switch format {
        case .test: maximumInnings = 4; maximumOvers = 500
        case .odi: maximumInnings = 2; maximumOvers = 50
        case .t20: maximumInnings = 2; maximumOvers = 20
        case .t10: maximumInnings = 2; maximumOvers = 10
        case .unknown: return nil
        }
        let teamIDs: Set<String> = [homeTeamID, awayTeamID]
        guard teamIDs.count == 2, teamIDs.allSatisfy({ Self.safeText($0, maximum: 100) }),
              !innings.isEmpty, innings.count <= maximumInnings,
              Set(innings.map(\.number)).count == innings.count,
              innings.map(\.number).sorted() == Array(1...innings.count),
              teamIDs.allSatisfy({ id in innings.filter { $0.teamID == id }.count <= (format == .test ? 2 : 1) }),
              innings.allSatisfy({ (1...maximumInnings).contains($0.number)
                  && teamIDs.contains($0.teamID) && (0...2_000).contains($0.runs)
                  && (0...10).contains($0.wickets)
                  && ($0.overs.map { Self.validOvers($0, maximum: maximumOvers) } ?? true) }),
              currentInnings.map({ $0 == innings.count }) ?? true,
              battingTeamID.map({ teamIDs.contains($0) }) ?? true,
              bowlingTeamID.map({ teamIDs.contains($0) }) ?? true,
              battingTeamID == nil || bowlingTeamID == nil || battingTeamID != bowlingTeamID,
              day.map({ format == .test && (1...6).contains($0) }) ?? true,
              session.map({ format == .test && (1...3).contains($0) }) ?? true,
              matchOrdinal.map({ format == .test && (1...99).contains($0) }) ?? true,
              matchEndsAt.map({ format == .test && Self.publishedEndDate($0) != nil }) ?? true,
              message.map({ Self.safeText($0, maximum: 200) }) ?? true,
              target.map({ (1...5_000).contains($0) }) ?? true,
              phase.map({ format == .test || ![.stumps, .lunch, .tea].contains($0) }) ?? true else { return nil }
        if let currentInnings, let battingTeamID,
           let current = innings.first(where: { $0.number == currentInnings }), current.teamID != battingTeamID { return nil }
        if target != nil {
            guard let currentInnings, innings.contains(where: { $0.number == currentInnings }) else { return nil }
        }
        return self
    }

    static func publishedEndDate(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$"#,
                          options: .regularExpression) != nil else { return nil }
        return CricketFixtureCatalog.date(value)
    }

    private static func validOvers(_ value: String, maximum: Int) -> Bool {
        let parts = value.split(separator: ".")
        guard value.range(of: #"^(?:0|[1-9][0-9]{0,2})(?:\.[0-5])?$"#, options: .regularExpression) != nil,
              let first = parts.first, let whole = Int(first), whole <= maximum else { return false }
        // Overs are completed overs plus balls, not a decimal fraction.
        return whole < maximum || parts.count == 1 || parts[1] == "0"
    }

    private static func safeText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.count <= maximum && value.utf8.count <= maximum * 4
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !value.contains("://") && !value.contains("<") && !value.contains(">")
    }
}

@MainActor
enum CricketMatchContextPolicy {
    /// The existing five-minute collector supplies snapshots, not ball-by-ball
    /// delivery. Older/held context disappears without changing fixture facts.
    static let freshness: TimeInterval = 10 * 60

    static func context(for event: EventReference, at now: Date = Date()) -> CricketMatchContext? {
        guard event.normalizedCategory == "cricket", !event.isBroadcastChannel, !event.hasCatalogIdentityConflict,
              let metadata = event.cricketFixture, metadata.verified,
              ["icc", "west-indies"].contains(metadata.competitionID),
              metadata.fixtureID.range(of: #"^icc:[0-9]{1,12}$"#, options: .regularExpression) != nil,
              event.id == CricketFixtureCatalog.fixtureIDPrefix + metadata.fixtureID,
              metadata.status == .live || metadata.status == .finished,
              (-300...freshness).contains(now.timeIntervalSince(metadata.observedAt)),
              let home = metadata.homeTeamID, let away = metadata.awayTeamID,
              let context = metadata.context?.validated(format: metadata.format, homeTeamID: home, awayTeamID: away) else { return nil }
        if let phase = context.phase {
            if metadata.status == .finished, phase != .finished { return nil }
            if metadata.status == .live, [.finished, .cancelled, .postponed, .scheduled].contains(phase) { return nil }
        }
        if let end = context.matchEndsAt.flatMap(CricketMatchContext.publishedEndDate) {
            guard let start = event.kickoffDate, end > start,
                  end.timeIntervalSince(start) <= 6 * 24 * 60 * 60 else { return nil }
        }
        return context
    }
}
