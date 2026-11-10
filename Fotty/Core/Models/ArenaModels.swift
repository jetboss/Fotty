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
    /// Retained across relaunch so a reschedule remains visible to the owner.
    let previousDate: Int64?
    let sportsFixture: SportsFixtureMetadata?
    let competitionID: String?
    /// Optional for compatibility with saved records written before the cricket
    /// service. Keep the original receipt: saving must never refresh live facts.
    let cricketFixture: CricketFixtureMetadata?

    struct SavedMatchSource: Codable, Equatable {
        let source: String
        let id: String
    }

    init(
        id: String,
        title: String?,
        category: String?,
        date: Int64?,
        poster: String?,
        popular: Bool?,
        homeName: String,
        awayName: String,
        homeBadge: String?,
        awayBadge: String?,
        sources: [SavedMatchSource],
        savedAt: Date,
        previousDate: Int64? = nil,
        sportsFixture: SportsFixtureMetadata? = nil,
        competitionID: String? = nil,
        cricketFixture: CricketFixtureMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.date = date
        self.poster = poster
        self.popular = popular
        self.homeName = homeName
        self.awayName = awayName
        self.homeBadge = homeBadge
        self.awayBadge = awayBadge
        self.sources = sources
        self.savedAt = savedAt
        self.previousDate = previousDate
        self.sportsFixture = sportsFixture
        self.competitionID = competitionID ?? sportsFixture?.competitionID
        self.cricketFixture = cricketFixture
    }

    @MainActor
    init(event: AnalyticalDataEngine.EventReference, savedAt: Date = Date(), previousDate: Int64? = nil,
         preservingArtworkFrom previous: SavedMatchRecord? = nil) {
        id = event.id
        title = event.title
        category = event.category
        date = event.date
        poster = event.poster
        popular = event.popular
        homeName = event.homeName
        awayName = event.awayName
        homeBadge = event.teams?.home?.badge
            ?? (previous?.id == event.id && previous?.homeName == event.homeName ? previous?.homeBadge : nil)
        awayBadge = event.teams?.away?.badge
            ?? (previous?.id == event.id && previous?.awayName == event.awayName ? previous?.awayBadge : nil)
        sources = (event.sources ?? []).map {
            SavedMatchSource(source: $0.source, id: $0.id)
        }
        self.savedAt = savedAt
        self.previousDate = previousDate
        sportsFixture = event.sportsFixture
        competitionID = event.competitionID
        cricketFixture = event.cricketFixture
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
            sources: sources.map { NexusASource(source: $0.source, id: $0.id) },
            cricketFixture: cricketFixture, sportsFixture: sportsFixture, competitionID: competitionID
        )
    }
}

enum BrowsingStateKey {
    static let homeSport = "fotty.home.selectedSport"
    static let homeFootballLeague = "fotty.home.selectedFootballLeague"
    static let homeCricketFilter = "fotty.home.selectedCricketFilter"
    static let homeFollowingOnly = "fotty.home.followingOnly"
    static let homeScrollOffset = "fotty.home.scrollOffset"
    static let homeFullLineupScrollOffset = "fotty.home.fullLineupScrollOffset"
    static let searchQuery = "fotty.search.query"
    static let searchScrollOffset = "fotty.search.scrollOffset"
    static let matchdayScrollOffset = "fotty.matchday.scrollOffset"
}

/// Optional in-app hints, independent of saved matches and notification consent.
enum MatchdayPreferences {
    static let showKickoffClashesKey = "fotty.matchday.showKickoffClashes"
    static let defaultShowKickoffClashes = false

    static func showsKickoffClashes(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showKickoffClashesKey) as? Bool ?? defaultShowKickoffClashes
    }
}

/// Persistent Home curation is intentionally separate from SceneStorage browsing
/// filters. Teams and competitions remain the source of truth; this preference
/// only decides whether Home applies those saved interests.
enum HomeInterestPreferences {
    static let onlyShowSelectedKey = "fotty.home.onlyShowSelectedInterests"

    static func isActive(enabled: Bool, selectedInterestCount: Int) -> Bool {
        enabled && selectedInterestCount > 0
    }

    static func shouldInclude(
        isFollowed: Bool,
        enabled: Bool,
        selectedInterestCount: Int
    ) -> Bool {
        !isActive(enabled: enabled, selectedInterestCount: selectedInterestCount) || isFollowed
    }
}

@MainActor
@Observable
final class MyMatchdayStore {
    enum MutationResult: Equatable {
        case saved
        case removed
        case unchanged
        case failed(String)

        var errorMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    typealias PersistenceWriter = (_ data: Data, _ key: String, _ defaults: UserDefaults) throws -> Void

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
    /// Projection invalidation must include same-ID status/artwork/source edits,
    /// not just list length or the number of descriptors.
    private(set) var contentRevision = 0
    private(set) var persistenceErrorMessage: String?

    private let defaults: UserDefaults
    private let storageKey: String
    private let persistenceWriter: PersistenceWriter
    var onRemove: ((String) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "fotty.my-matchday.saved-matches",
        onRemove: ((String) -> Void)? = nil,
        persistenceWriter: @escaping PersistenceWriter = MyMatchdayStore.verifiedWrite
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.onRemove = onRemove
        self.persistenceWriter = persistenceWriter
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedMatchRecord].self, from: data) {
            savedMatches = decoded
        } else {
            savedMatches = []
        }
        // An old kickoff is not cancellation evidence: a fresh schedule may
        // reveal a postponement after a provider omitted the event for days.
        clearExpiredSources()
    }

    func contains(eventID: String) -> Bool {
        savedMatches.contains { $0.id == eventID }
    }

    /// Explicit merge receipts connect a provider bookmark to its canonical
    /// fixture without rewriting the user's opaque bookmark/reminder ID.
    func records(for event: AnalyticalDataEngine.EventReference) -> [SavedMatchRecord] {
        savedMatches.filter { SavedMatchContinuityPolicy.corresponds($0, to: event) }
    }

    func record(for event: AnalyticalDataEngine.EventReference) -> SavedMatchRecord? {
        records(for: event).min { $0.savedAt < $1.savedAt }
    }

    func contains(event: AnalyticalDataEngine.EventReference) -> Bool {
        record(for: event) != nil
    }

    @discardableResult
    func toggle(_ event: AnalyticalDataEngine.EventReference) -> MutationResult {
        let existing = records(for: event)
        if !existing.isEmpty {
            let ids = Set(existing.map(\.id))
            guard commit(savedMatches.filter { !ids.contains($0.id) }) else {
                return .failed(persistenceErrorMessage ?? Self.saveFailure)
            }
            // Explicit user removal revokes every corresponding reminder;
            // passive reconciliation never erases duplicate legacy bookmarks.
            var reminderIDs = ids
            reminderIDs.insert(event.id)
            for saved in existing {
                if let fixture = saved.sportsFixture {
                    reminderIDs.insert(fixture.fixtureID)
                }
            }
            if let fixture = event.sportsFixture {
                reminderIDs.insert(fixture.fixtureID)
            }
            reminderIDs.forEach { onRemove?($0) }
            return .removed
        } else {
            return save(event)
        }
    }

    @discardableResult
    func save(_ event: AnalyticalDataEngine.EventReference) -> MutationResult {
        guard !event.hasCatalogIdentityConflict else {
            return .failed("This listing has conflicting identity data and was not saved. Refresh the lineup and try again.")
        }
        let related = records(for: event)
        if !related.isEmpty, related.allSatisfy({ $0.id != event.id }) {
            let relatedIDs = Set(related.map(\.id))
            let candidate = savedMatches.map { saved -> SavedMatchRecord in
                guard relatedIDs.contains(saved.id),
                      let current = SavedMatchContinuityPolicy.currentEvent(for: saved, in: [event]) else { return saved }
                return SavedMatchRecord(event: current, savedAt: saved.savedAt,
                    previousDate: saved.event.kickoffDate == current.kickoffDate ? saved.previousDate : saved.date)
            }
            guard candidate != savedMatches else { return .unchanged }
            return commit(candidate) ? .saved : .failed(persistenceErrorMessage ?? Self.saveFailure)
        }
        let previous = savedMatches.first { $0.id == event.id }
        var candidate = savedMatches.filter { $0.id != event.id }
        candidate.insert(SavedMatchRecord(event: event, savedAt: previous?.savedAt ?? Date(),
                                          previousDate: previous?.previousDate), at: 0)
        return commit(candidate) ? .saved : .failed(persistenceErrorMessage ?? Self.saveFailure)
    }

    /// A missing/partial feed never deletes a bookmark. An explicit fresh row
    /// replaces its sources, including an empty list; stale sources are not
    /// carried forward as though the new listing still advertised them.
    func reconcile(events: [AnalyticalDataEngine.EventReference], at now: Date = .init()) {
        let original = savedMatches
        var candidate = savedMatches.map { record in
            guard let current = SavedMatchContinuityPolicy.currentEvent(for: record, in: events) else { return record }
            let changedDate = record.event.kickoffDate != current.kickoffDate
            let verifiedTerminal = current.sportsFixture.map {
                $0.verified && ($0.status == .finished || $0.status == .cancelled)
            } ?? current.cricketFixture.map {
                $0.verified && ($0.status == .finished || $0.status == .cancelled)
            } ?? false
            return SavedMatchRecord(event: current, savedAt: record.savedAt,
                                    previousDate: changedDate ? record.date : record.previousDate,
                                    preservingArtworkFrom: verifiedTerminal ? record : nil)
        }
        candidate = removingExpiredSources(from: candidate, relativeTo: now)
        if candidate != original { _ = commit(candidate) }
    }

    @discardableResult
    func remove(eventID: String) -> MutationResult {
        guard let saved = savedMatches.first(where: { $0.id == eventID }) else { return .unchanged }
        // Removing a saved match revokes its explicit reminder too. Cancelling
        // the bell does the reverse intentionally: it leaves the bookmark alone.
        let candidate = savedMatches.filter { $0.id != eventID }
        guard commit(candidate) else { return .failed(persistenceErrorMessage ?? Self.saveFailure) }
        var reminderIDs: Set<String> = [eventID]
        if let fixture = saved.sportsFixture {
            reminderIDs.insert(fixture.fixtureID)
        }
        reminderIDs.forEach { onRemove?($0) }
        return .removed
    }

    /// Restore only already-validated, source-free snapshots. Existing match
    /// reminders are handled separately so a backup never re-enables alerts.
    @discardableResult
    func replaceForRestore(_ records: [SavedMatchRecord], relativeTo now: Date = Date()) -> MutationResult {
        var seen = Set<String>()
        let candidate = removingExpiredSources(from: records
            .sorted { $0.savedAt > $1.savedAt }
            .filter { seen.insert($0.id).inserted }, relativeTo: now)
        guard candidate != savedMatches else { return .unchanged }
        return commit(candidate) ? .saved : .failed(persistenceErrorMessage ?? Self.saveFailure)
    }

    /// Keep completed selections long enough to make the matchday feel
    /// continuous, while preventing old stream URLs from accumulating forever.
    func pruneExpiredMatches(relativeTo now: Date = Date()) {
        let expiry = now.addingTimeInterval(-36 * 3600)
        let candidate = savedMatches.filter { record in
            guard !record.event.isBroadcastChannel, let rawDate = record.date, rawDate > 0 else { return true }
            let kickoff = rawDate > 10_000_000_000
                ? Date(timeIntervalSince1970: Double(rawDate) / 1000)
                : Date(timeIntervalSince1970: Double(rawDate))
            return kickoff >= expiry
        }
        if candidate != savedMatches { _ = commit(candidate) }
    }

    private func clearExpiredSources(relativeTo now: Date = .init()) {
        let candidate = removingExpiredSources(from: savedMatches, relativeTo: now)
        if candidate != savedMatches { _ = commit(candidate) }
    }

    private func removingExpiredSources(
        from records: [SavedMatchRecord], relativeTo now: Date
    ) -> [SavedMatchRecord] {
        let cutoff = now.addingTimeInterval(-36 * 3600)
        return records.map { record in
            guard !record.event.isBroadcastChannel, !record.sources.isEmpty,
                  let start = record.event.kickoffDate, start < cutoff else { return record }
            return SavedMatchRecord(id: record.id, title: record.title, category: record.category,
                                    date: record.date, poster: record.poster, popular: record.popular,
                                    homeName: record.homeName, awayName: record.awayName,
                                    homeBadge: record.homeBadge, awayBadge: record.awayBadge,
                                    sources: [], savedAt: record.savedAt, previousDate: record.previousDate,
                                    sportsFixture: record.sportsFixture, competitionID: record.competitionID,
                                    cricketFixture: record.cricketFixture)
        }
    }

    private func commit(_ candidate: [SavedMatchRecord]) -> Bool {
        do {
            let data = try JSONEncoder().encode(candidate)
            try persistenceWriter(data, storageKey, defaults)
            savedMatches = candidate
            contentRevision &+= 1
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceErrorMessage = Self.saveFailure
            return false
        }
    }

    private static let saveFailure = "The Matchday change could not be saved. Your previous saved list is unchanged; free some storage and try again."

    nonisolated private static func verifiedWrite(_ data: Data, _ key: String, _ defaults: UserDefaults) throws {
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
