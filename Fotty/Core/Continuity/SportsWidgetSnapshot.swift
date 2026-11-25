import Foundation

/// Shared between the sports widget and its containing app. No app models,
/// FPL, provider URLs, credentials or claimed playback success belong here.
struct SportsWidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.com.jelani.Fotty.sports"
    static let storageKey = "fotty.sports-widget.snapshot.v1"
    static let maximumBytes = 32 * 1024
    static let maximumMatches = 6
    static let freshness: TimeInterval = 30 * 60
    private static let supportedCategories: Set<String> = [
        "football", "cricket", "basketball", "baseball", "tennis", "hockey",
        "fight", "american-football", "motorsport", "golf", "rugby", "volleyball"
    ]

    enum Phase: String, Codable, Sendable { case scheduled, live, listed, unconfirmed, finished }
    struct Match: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let homeName: String
        let awayName: String
        let category: String
        let competition: String?
        let kickoff: Date?
        let phase: Phase
        let statusObservedAt: Date?
        let scoreText: String?
        let scoreObservedAt: Date?
        /// A bounded image basename in the sports App Group, never a URL/path.
        let homeBadgeFile: String?
        let awayBadgeFile: String?

        func effectivePhase(at now: Date) -> Phase {
            if phase == .finished { return .finished }
            if phase == .live {
                guard let statusObservedAt, (-5...SportsWidgetSnapshot.freshness).contains(now.timeIntervalSince(statusObservedAt)) else { return .unconfirmed }
                return .live
            }
            if phase == .scheduled, let kickoff, kickoff <= now { return .unconfirmed }
            return phase
        }
        func currentScore(at now: Date) -> String? {
            guard effectivePhase(at: now) == .live, let scoreObservedAt,
                  (-5...120).contains(now.timeIntervalSince(scoreObservedAt)) else { return nil }
            return scoreText
        }
        var deepLink: URL? {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%")
            guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return URL(string: "fotty://matchday/\(encoded)")
        }
    }

    let version: Int
    let createdAt: Date
    let matches: [Match]

    init(version: Int = 1, createdAt: Date = .init(), matches: [Match]) {
        self.version = version; self.createdAt = createdAt; self.matches = matches
    }

    var expiryDates: [Date] {
        let dates = matches.flatMap { match -> [Date] in
            [match.kickoff, match.statusObservedAt?.addingTimeInterval(Self.freshness + 1),
             match.scoreObservedAt?.addingTimeInterval(121)].compactMap { $0 }
        } + [createdAt.addingTimeInterval(Self.freshness + 1)]
        return Set(dates.filter { $0 > createdAt }).sorted()
    }
    var nextExpiry: Date? { expiryDates.first }

    func isFresh(at now: Date) -> Bool {
        (-5...Self.freshness).contains(now.timeIntervalSince(createdAt))
    }

    func validatedData() -> Data? {
        guard isValid(), let data = try? JSONEncoder().encode(self), data.count <= Self.maximumBytes else { return nil }
        return data
    }

    static func decode(_ data: Data) -> Self? {
        guard data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "createdAt", "matches"]),
              let rows = object["matches"] as? [[String: Any]], rows.count <= maximumMatches,
              rows.allSatisfy({ Set($0.keys).isSubset(of: ["id", "homeName", "awayName", "category", "competition", "kickoff", "phase", "statusObservedAt", "scoreText", "scoreObservedAt", "homeBadgeFile", "awayBadgeFile"]) }),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.isValid() else { return nil }
        return snapshot
    }

    private func isValid() -> Bool {
        guard version == 1, createdAt.timeIntervalSince1970.isFinite,
              matches.count <= Self.maximumMatches, Set(matches.map(\.id)).count == matches.count else { return false }
        return matches.allSatisfy { Self.isValidMatch($0, createdAt: createdAt) }
    }

    /// The producer can omit unsupported local rows without weakening the
    /// extension's all-or-nothing validation of received wire snapshots.
    static func isValidMatch(_ row: Match, createdAt: Date) -> Bool {
        createdAt.timeIntervalSince1970.isFinite
            && Self.text(row.id, maximum: 200) && Self.text(row.homeName, maximum: 160)
            && Self.text(row.awayName, maximum: 160, permitsEmpty: true) && supportedCategories.contains(row.category)
            && (row.competition.map { Self.text($0, maximum: 160) } ?? true)
            && (row.kickoff.map { $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 } ?? true)
            && (row.phase != .live || row.statusObservedAt != nil)
            && (row.statusObservedAt.map { $0.timeIntervalSince1970.isFinite && $0 <= createdAt.addingTimeInterval(5) } ?? true)
            && (row.scoreText.map { Self.text($0, maximum: 32) && row.scoreObservedAt != nil } ?? (row.scoreObservedAt == nil))
            && (row.scoreObservedAt.map { $0.timeIntervalSince1970.isFinite && $0 <= createdAt.addingTimeInterval(5) } ?? true)
            && (row.homeBadgeFile.map(Self.validBadgeFile) ?? true)
            && (row.awayBadgeFile.map(Self.validBadgeFile) ?? true)
    }

    private static func text(_ value: String, maximum: Int, permitsEmpty: Bool = false) -> Bool {
        value.count <= maximum && value.utf8.count <= maximum * 4
            && (permitsEmpty || !value.isEmpty) && !value.contains("://")
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func validBadgeFile(_ value: String) -> Bool {
        guard value.count <= 100, !value.isEmpty, !value.hasPrefix("."),
              value.range(of: #"^[A-Za-z0-9_-]+\.(?:png|jpg|jpeg)$"#, options: .regularExpression) != nil else { return false }
        return true
    }
    static func badgeURL(filename: String) -> URL? {
        guard validBadgeFile(filename), let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return directory.appendingPathComponent("SportsBadges", isDirectory: true).appendingPathComponent(filename, isDirectory: false)
    }
}
