import Foundation
import Observation

// MARK: - Fixture & Match Models

enum ArenaMatchStatus: String, Codable {
    case scheduled = "SCHEDULED"
    case live = "LIVE"
    case halftime = "HT"
    case fulltime = "FT"
    case postponed = "POSTPONED"
    case cancelled = "CANCELLED"
}

struct ArenaFixture: Identifiable, Codable {
    let id: String
    let homeTeam: ArenaTeam
    let awayTeam: ArenaTeam
    let status: ArenaMatchStatus
    let startTime: Date
    let score: ArenaMatchScore?
    let venue: String?
    let competition: String
    let matchMinute: Int?
}

struct ArenaTeam: Identifiable, Codable {
    let id: String
    let name: String
    let shortName: String
    let badgeURL: URL?
}

struct ArenaMatchScore: Codable {
    let home: Int
    let away: Int
}

struct ArenaMatchEvent: Identifiable, Codable {
    let id: String
    let minute: Int
    let type: EventType
    let teamId: String
    let playerName: String
    let detail: String?
    
    enum EventType: String, Codable {
        case goal = "GOAL"
        case redCard = "RED_CARD"
        case yellowCard = "YELLOW_CARD"
        case substitution = "SUB"
        case varDecision = "VAR"
        case other = "OTHER"
    }
}

// MARK: - Arena Specific Models

struct ArenaChatEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let username: String
    let text: String
    let timestamp: Date
    let avatarURL: URL?
    let isPinned: Bool
}

struct ArenaReaction: Identifiable, Codable {
    let id: String
    let emoji: String
    let count: Int
    let isSelectedByMe: Bool
}

struct ArenaPoll: Identifiable, Codable {
    let id: String
    let question: String
    let options: [PollOption]
    let totalVotes: Int
    let expiresAt: Date
    
    struct PollOption: Identifiable, Codable {
        let id: String
        let text: String
        let voteCount: Int
    }
}

// MARK: - Highlights Specific Models

struct HighlightItem: Identifiable, Codable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let videoURL: URL?
    let durationSeconds: Int
    let type: HighlightType
    
    enum HighlightType: String, Codable {
        case goal = "GOAL"
        case fullReplay = "FULL"
        case keyMoment = "KEY"
    }
}

struct ArenaMatchStory: Codable {
    let summary: String
    let keyTakeaway: String
}

// MARK: - My Matchday

/// A durable snapshot of a catalog event. This lives in UserDefaults rather
/// than SwiftData so saving a match does not require a schema migration for an
/// existing install.
struct SavedMatchRecord: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let category: String?
    let date: Int64?
    let poster: String?
    let popular: Bool?
    let homeName: String
    let awayName: String
    let homeBadge: String?
    let awayBadge: String?
    let sources: [SavedMatchSource]
    let savedAt: Date

    struct SavedMatchSource: Codable, Equatable {
        let source: String
        let id: String
    }

    @MainActor
    init(event: AnalyticalDataEngine.EventReference, savedAt: Date = Date()) {
        id = event.id
        title = event.title
        category = event.category
        date = event.date
        poster = event.poster
        popular = event.popular
        homeName = event.homeName
        awayName = event.awayName
        homeBadge = event.teams?.home?.badge
        awayBadge = event.teams?.away?.badge
        sources = (event.sources ?? []).map {
            SavedMatchSource(source: $0.source, id: $0.id)
        }
        self.savedAt = savedAt
    }

    @MainActor
    var event: AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(
            id: id,
            title: title ?? "\(homeName) vs \(awayName)",
            category: category,
            date: date,
            poster: poster,
            popular: popular,
            teams: NexusATeams(
                home: NexusATeam(name: homeName, badge: homeBadge),
                away: NexusATeam(name: awayName, badge: awayBadge)
            ),
            sources: sources.map { NexusASource(source: $0.source, id: $0.id) }
        )
    }
}

@MainActor
@Observable
final class MyMatchdayStore {
    static let shared: MyMatchdayStore = {
        #if DEBUG
        if AppRuntime.isAutomatedTesting,
           (ProcessInfo.processInfo.environment["FOTTY_CRICKET_UI_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["FOTTY_HOME_UI_TESTING"] == "1"),
           let defaults = UserDefaults(suiteName: "com.jelani.Fotty.CricketUITests") {
            defaults.removePersistentDomain(forName: "com.jelani.Fotty.CricketUITests")
            return MyMatchdayStore(defaults: defaults)
        }
        #endif
        return MyMatchdayStore(onRemove: { MatchReminderStore.shared.cancel($0) })
    }()

    private(set) var savedMatches: [SavedMatchRecord]

    private let defaults: UserDefaults
    private let storageKey: String
    var onRemove: ((String) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "fotty.my-matchday.saved-matches",
        onRemove: ((String) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.onRemove = onRemove
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedMatchRecord].self, from: data) {
            savedMatches = decoded
        } else {
            savedMatches = []
        }
        pruneExpiredMatches()
    }

    func contains(eventID: String) -> Bool {
        savedMatches.contains { $0.id == eventID }
    }

    func toggle(_ event: AnalyticalDataEngine.EventReference) {
        if contains(eventID: event.id) {
            remove(eventID: event.id)
        } else {
            save(event)
        }
    }

    func save(_ event: AnalyticalDataEngine.EventReference) {
        savedMatches.removeAll { $0.id == event.id }
        savedMatches.insert(SavedMatchRecord(event: event), at: 0)
        persist()
    }

    func remove(eventID: String) {
        // Removing a saved match revokes its explicit reminder too. Cancelling
        // the bell does the reverse intentionally: it leaves the bookmark alone.
        onRemove?(eventID)
        savedMatches.removeAll { $0.id == eventID }
        persist()
    }

    /// Keep completed selections long enough to make the matchday feel
    /// continuous, while preventing old stream URLs from accumulating forever.
    func pruneExpiredMatches(relativeTo now: Date = Date()) {
        let expiry = now.addingTimeInterval(-36 * 3600)
        let originalCount = savedMatches.count
        savedMatches.removeAll { record in
            guard !record.event.isBroadcastChannel, let rawDate = record.date, rawDate > 0 else { return false }
            let kickoff = rawDate > 10_000_000_000
                ? Date(timeIntervalSince1970: Double(rawDate) / 1000)
                : Date(timeIntervalSince1970: Double(rawDate))
            return kickoff < expiry
        }
        if savedMatches.count != originalCount {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedMatches) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
