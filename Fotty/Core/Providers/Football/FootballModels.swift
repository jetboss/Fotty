import Foundation
import SwiftUI
import Observation
import UserNotifications


// MARK: - Football Match Models

struct FootballMatchesResponse: Codable {
    let matches: [FootballMatch]
    let resultSet: FootballResultSet?
}

struct FootballResultSet: Codable {
    let count: Int?
    let competitions: String?
    let first: String?
    let last: String?
    let played: Int?
}

enum FootballMatchAlertTransitionPolicy {
    /// Only the real pre-match transition is kickoff. Returning from halftime,
    /// suspension or a provider correction must not announce another start.
    static func shouldAnnounceKickoff(
        from oldStatus: FootballMatch.MatchStatus,
        to newStatus: FootballMatch.MatchStatus
    ) -> Bool {
        oldStatus.isUpcoming && newStatus == .inPlay
    }
}

struct FootballMatch: Codable, Identifiable {
    let id: Int
    /// API-Football fixture id when the row came from API-Football or was merged from live.
    let apiFootballFixtureId: Int?
    let utcDate: String
    let status: MatchStatus
    let matchday: Int?
    let stage: String?
    let group: String?
    let homeTeam: FootballTeam
    let awayTeam: FootballTeam
    let score: MatchScore
    let competition: MatchCompetition
    let referees: [MatchReferee]?
    let events: [FootballMatchEvent]?
    
    enum MatchStatus: String, Codable {
        case scheduled = "SCHEDULED"
        case timed = "TIMED"
        case inPlay = "IN_PLAY"
        case paused = "PAUSED"
        case finished = "FINISHED"
        case suspended = "SUSPENDED"
        case postponed = "POSTPONED"
        case cancelled = "CANCELLED"
        case awarded = "AWARDED"
        
        var isLive: Bool {
            self == .inPlay || self == .paused
        }
        
        var isUpcoming: Bool {
            self == .scheduled || self == .timed
        }
        
        var isFinished: Bool {
            self == .finished || self == .awarded
        }
        
        var displayText: String {
            switch self {
            case .scheduled, .timed: return "Upcoming"
            case .inPlay: return "LIVE"
            case .paused: return "HT"
            case .finished: return "FT"
            case .suspended: return "Suspended"
            case .postponed: return "Postponed"
            case .cancelled: return "Cancelled"
            case .awarded: return "Awarded"
            }
        }
    }
    
    var hubNavigationFixtureId: String {
        if let api = apiFootballFixtureId { return String(api) }
        return String(id)
    }

    var matchDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: utcDate) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: utcDate)
    }
    
    var kickoffTime: String {
        guard let date = matchDate else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
    
    var matchDateFormatted: String {
        guard let date = matchDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

struct FootballTeam: Codable, Identifiable {
    let id: Int?
    let name: String?
    let shortName: String?
    let tla: String?
    let crest: String?
    
    var displayName: String {
        shortName ?? name ?? "Unknown Team"
    }

    /// Display abbreviations are not cross-provider identities (for example,
    /// CRY/NFO cannot match Crystal Palace/Nottingham Forest in the catalog).
    var matchingName: String {
        Self.matchingName(name: name, shortName: shortName)
    }

    static func matchingName(name: String?, shortName: String?) -> String {
        for candidate in [name, shortName] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
        }
        return ""
    }
}

struct MatchScore: Codable {
    let winner: String?
    let duration: String?
    let fullTime: ScoreDetail?
    let halfTime: ScoreDetail?
}

struct ScoreDetail: Codable {
    let home: Int?
    let away: Int?
}

struct MatchCompetition: Codable {
    let id: Int?
    let name: String?
    let code: String?
    let emblem: String?
    let country: String?
    
    var emblemURL: URL? {
        guard let emblem else { return nil }
        return URL(string: emblem)
    }
    
    /// Prefer this over `name` in UI when the feed supplies a country (avoids ambiguous "Premier League" labels).
    var audienceFacingName: String {
        LeagueDisplayFormatting.audienceFacing(leagueName: name, country: country)
    }
}

struct FootballMatchEvent: Codable, Identifiable {
    let id: Int
    let teamId: Int
    let minute: Int
    let extraMinute: Int?
    let type: EventType
    let player: String?
    let assist: String?
    let info: String?
    let sortOrder: Int
    
    enum EventType: String, Codable {
        case goal = "GOAL"
        case redCard = "RED_CARD"
        case yellowCard = "YELLOW_CARD"
        case substitution = "SUBSTITUTION"
        case varDecision = "VAR"
        case other = "OTHER"
        
        var icon: String {
            switch self {
            case .goal: return "⚽️"
            case .redCard: return "🟥"
            case .yellowCard: return "🟨"
            case .substitution: return "🔄"
            case .varDecision: return "🖥️"
            default: return "•"
            }
        }
    }
}

struct MatchReferee: Codable {
    let id: Int?
    let name: String?
    let nationality: String?
}

// MARK: - Football Pro (Sportmonks v3) Models

struct FootballProFixtureResponse: Decodable {
    let data: [FootballProFixture]
}

struct FootballProFixture: Decodable {
    let id: Int
    let name: String
    let participants: [FootballProParticipant]?
    let scores: [FootballProScore]?
    let state: FootballProState?
    let time: FootballProTime?
    let league: FootballProLeague?
    let events: [FootballProEvent]?
    
    struct FootballProState: Decodable {
        let id: Int
        let name: String
        let short_name: String
    }
    
    struct FootballProTime: Decodable {
        let minute: Int?
        let added_time: Int?
    }
}

struct FootballProParticipant: Decodable {
    let id: Int
    let name: String
    let image_path: URL?
    let meta: FootballProParticipantMeta?
    
    struct FootballProParticipantMeta: Decodable {
        let location: String // "home" or "away"
    }
}

struct FootballProScore: Decodable {
    let description: String 
    let score: FootballProScoreValue
    let participant_id: Int
    
    struct FootballProScoreValue: Decodable {
        let goals: Int
    }
}

struct FootballProLeague: Decodable {
    let id: Int
    let name: String
    let image_path: URL?
    let country: FootballProLeagueCountry?
    
    struct FootballProLeagueCountry: Decodable {
        let name: String?
    }
}

struct FootballProEvent: Decodable {
    let id: Int
    let fixture_id: Int
    let team_id: Int?
    let type_id: Int
    let player_id: Int?
    let related_player_id: Int?
    let player_name: String?
    let related_player_name: String?
    let minute: Int
    let extra_minute: Int?
    let sort_order: Int?
    let info: String?
    let type: FootballProEventType?
}

struct FootballProEventType: Decodable {
    let id: Int?
    let name: String?
    let code: String?
    let developer_name: String?
    
    var isGoal: Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("goal") || developer_name?.lowercased().contains("goal") == true
    }
    
    var isRedCard: Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("redcard") || developer_name?.lowercased().contains("redcard") == true
    }
}

// MARK: - Supported Leagues

enum League: String, CaseIterable, Identifiable {
    case premierLeague = "PL"
    case championsLeague = "CL"
    case laLiga = "PD"
    case serieA = "SA"
    case bundesliga = "BL1"
    case ligue1 = "FL1"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .premierLeague: return "Premier League"
        case .championsLeague: return "Champions League"
        case .laLiga: return "La Liga"
        case .serieA: return "Serie A"
        case .bundesliga: return "Bundesliga"
        case .ligue1: return "Ligue 1"
        }
    }
}

// MARK: - Live Score Service

enum FootballScheduleFreshnessPolicy {
    static let maximumAge: TimeInterval = 30 * 60

    static func isFresh(lastVerifiedAt: Date?, now: Date) -> Bool {
        guard let lastVerifiedAt else { return false }
        let age = now.timeIntervalSince(lastVerifiedAt)
        return age >= -5 * 60 && age <= maximumAge
    }

    static func showsRefreshProgress(isCheckingSchedule: Bool, lastVerifiedAt: Date?,
                                     refreshFailed: Bool, now: Date) -> Bool {
        isCheckingSchedule && (refreshFailed || !isFresh(lastVerifiedAt: lastVerifiedAt, now: now))
    }
}

/// Demand is owned by a visible surface, not by whichever tab disappears last.
/// Releasing one owner must never cancel another visible consumer's polling.
struct LiveScorePollingDemand {
    private(set) var owners: Set<UUID> = []
    var isNeeded: Bool { !owners.isEmpty }

    mutating func update(owner: UUID, isActive: Bool) {
        if isActive { owners.insert(owner) } else { owners.remove(owner) }
    }
}

/// The score index owns a bounded set of immutable provider date strings.
/// Retain valid and malformed results while a string remains in that index,
/// rather than creating ISO8601 formatters for every presentation lookup.
struct FootballKickoffDateIndex {
    private enum Entry { case valid(Date), invalid }
    private var entries: [String: Entry] = [:]

    mutating func replace(dates: [String], parse: (String) -> Date? = FootballNormalizer.parseISO8601Date) {
        var next: [String: Entry] = [:]
        next.reserveCapacity(dates.count)
        for raw in Set(dates) {
            if let existing = entries[raw] {
                next[raw] = existing
            } else if let date = parse(raw) {
                next[raw] = .valid(date)
            } else {
                next[raw] = .invalid
            }
        }
        entries = next
    }

    func date(for raw: String) -> Date? {
        guard case .valid(let date) = entries[raw] else { return nil }
        return date
    }
}

@MainActor
@Observable
class LiveScoreService {
    static let shared = LiveScoreService()
    
    struct LiveScore: Equatable {
        let homeGoals: Int
        let awayGoals: Int
        let status: FootballMatch.MatchStatus
        let minute: String? 
    }
    
    private(set) var scores: [String: LiveScore] = [:]
    private var liveMinuteByKey: [String: String] = [:]
    private(set) var cachedMatches: [FootballMatch] = []
    // Derived lookup state is an implementation detail, not observable UI state.
    // Dashboard view evaluation calls `findMatch` many times; tracking these cache
    // mutations causes SwiftUI to invalidate the view while it is still rendering.
    @ObservationIgnored private var directKeyIndex: [String: FootballMatch] = [:]
    @ObservationIgnored private var cleanKeyIndex: [String: FootballMatch] = [:]
    @ObservationIgnored private var matchLookupCache: [String: FootballMatch] = [:]
    @ObservationIgnored private var unmatchedLookupKeys: Set<String> = []
    @ObservationIgnored private var kickoffDateIndex = FootballKickoffDateIndex()
    private(set) var analysisMatches: [FootballMatch] = []
    private(set) var lastRefresh: Date?
    /// Original accepted observation, never the time of a retry/cache read.
    private(set) var liveObservedAt: Date?
    @ObservationIgnored private var liveObservationByIdentity: [String: Date] = [:]
    @ObservationIgnored private var acceptedTerminalRows: [String: MatchHubData] = [:]
    private struct AlertBaseline {
        let score: LiveScore
        let kickoff: Date
    }
    @ObservationIgnored private var alertBaselineByIdentity: [String: AlertBaseline] = [:]
    @ObservationIgnored private let repository: FootballRepository
    @ObservationIgnored private let currentDate: () -> Date
    private(set) var scheduleLastVerifiedAt: Date?
    private var isCheckingSchedule = false
    private(set) var scheduleRefreshFailed = false
    private(set) var isRefreshing = false
    private(set) var feedMode: LiveScoreFeedMode = .inactive
    var hasQuotaError: Bool { feedMode.isQuotaReserved }
    var isUsingDelayedScoreFallback: Bool { feedMode.usesDelayedData }
    var scoreStatusQualifier: String? { feedMode.statusQualifier }
    var shouldShowScoreFeedNotice: Bool { feedMode.usesDelayedData || feedMode == .unavailable }

    func showsFootballFixtureRefresh(at now: Date = Date()) -> Bool {
        FootballScheduleFreshnessPolicy.showsRefreshProgress(
            isCheckingSchedule: isCheckingSchedule,
            lastVerifiedAt: scheduleLastVerifiedAt,
            refreshFailed: scheduleRefreshFailed,
            now: now
        )
    }
    
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollingDemand = LiveScorePollingDemand()
    
    init(repository: FootballRepository = .shared, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.currentDate = now
    }
    
    func updatePollingDemand(owner: UUID, isActive: Bool) {
        pollingDemand.update(owner: owner, isActive: isActive)
        if pollingDemand.isNeeded { startPolling() } else { stopPolling() }
    }

    func releasePolling(owner: UUID) {
        updatePollingDemand(owner: owner, isActive: false)
    }

    private func startPolling() {
        guard !AppRuntime.isAutomatedTesting else { return }
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh(force: false)
                do {
                    let interval = feedMode == .officialFPL ? 60 : 240
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }
    
    private func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if force {
            await repository.invalidateLiveListCache()
            await repository.invalidateScheduleListCache()
        }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let now = currentDate()

        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let endDate = calendar.date(byAdding: .day, value: 4, to: now) ?? now

        var analysisData: [MatchHubData] = []
        var liveSnapshot: FootballLiveSnapshot?

        // Fetch/cache the schedule first so the repository can avoid a live API
        // request entirely when no covered competition is near kickoff.
        do {
            isCheckingSchedule = true
            defer { isCheckingSchedule = false }
            let snapshot = try await repository.getScheduleSnapshot(dateRange: startDate...endDate)
            guard !Task.isCancelled else { return }
            analysisData = snapshot.matches
            scheduleLastVerifiedAt = snapshot.observedAt
            scheduleRefreshFailed = false
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            print("[LiveScoreService] Failed to fetch schedule data: \(error)")
            if isRateLimited(error) {
                feedMode = .quotaFallback
            }
            // Never let an old schedule keep acting as current official evidence.
            // The independently refreshed stream catalog can remain visible.
            scheduleRefreshFailed = true
        }

        do {
            liveSnapshot = try await repository.getLiveSnapshot()
            guard !Task.isCancelled else { return }
            feedMode = liveSnapshot?.mode ?? .unavailable
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            print("[LiveScoreService] Failed to fetch live data: \(error)")
            feedMode = isRateLimited(error) ? .quotaFallback : .unavailable
        }

        // A source stamps its receipt after fetching. Comparing that receipt
        // with the request-start clock would reject every uncached live poll.
        let publicationDate = currentDate()
        let accepted = FootballScoreSnapshotPolicy.project(schedule: analysisData,
            live: liveSnapshot, retainedTerminal: acceptedTerminalRows, at: publicationDate)
        acceptedTerminalRows = accepted.terminal
        liveObservationByIdentity = accepted.liveObservations
        liveObservedAt = liveSnapshot?.observedAt
        let allAnalysisMatches = accepted.schedule.map { mapToLegacyFootballMatch($0.data, status: $0.status) }
        let allMatches = accepted.scores.map { mapToLegacyFootballMatch($0.data, status: $0.status) }
        let refreshedMinuteByKey = Self.minuteLabels(from: accepted.scores.filter { $0.status.isLive }.map(\.data))

        // 3. Update State & Notify
        self.cachedMatches = allMatches
        self.analysisMatches = allAnalysisMatches
        self.liveMinuteByKey = refreshedMinuteByKey
        self.matchLookupCache.removeAll(keepingCapacity: true)
        self.unmatchedLookupKeys.removeAll(keepingCapacity: true)
        // Index the schedule response as a scoreboard fallback, then let the
        // dedicated live response win when both contain the same fixture.
        self.rebuildMatchIndices(from: allAnalysisMatches + allMatches)
        self.lastRefresh = publicationDate

        // Keep scheduled/recently-finished schedule rows in the comparison set.
        // Otherwise a provider that removes a fixture from its `live` endpoint at
        // the final whistle can never produce Fotty's full-time notification.
        let rows = accepted.schedule + accepted.scores
        // A temporarily empty feed is not a new fixture identity or a reset of
        // its alert history. Bound retention by the same dated analysis window.
        alertBaselineByIdentity = alertBaselineByIdentity.filter {
            (-3 * 86_400...4 * 86_400).contains($0.value.kickoff.timeIntervalSince(publicationDate))
        }
        var notificationRowsByIdentity: [String: FootballScoreSnapshotPolicy.Row] = [:]
        for row in rows where row.status != .unknown
            && FootballDataPolicy.supportsLiveScores(competition: row.data.fixture.competition) {
            notificationRowsByIdentity[FootballScoreSnapshotPolicy.key(row.data)] = row
        }

        var newScores: [String: LiveScore] = [:]
        for (identity, row) in notificationRowsByIdentity {
            let match = mapToLegacyFootballMatch(row.data, status: row.status)
            let key = makeKey(home: match.homeTeam.matchingName, away: match.awayTeam.matchingName)
            let homeGoals = match.score.fullTime?.home ?? 0
            let awayGoals = match.score.fullTime?.away ?? 0

            newScores[key] = LiveScore(
                homeGoals: homeGoals,
                awayGoals: awayGoals,
                status: match.status,
                minute: liveMinuteByKey[key]
            )

            // --- Notification Logic ---
            if let baseline = alertBaselineByIdentity[identity] {
                let old = baseline.score
                // A cached pre-kickoff schedule can outlast a healthy empty or
                // failed live poll. It must not turn an observed match back into
                // a new kickoff/zero-goal notification baseline on recovery.
                if match.status.isUpcoming && !old.status.isUpcoming { continue }
                handleNotificationDiff(
                    for: match,
                    oldScore: old,
                    newHome: homeGoals,
                    newAway: awayGoals
                )
            }
            if let score = newScores[key] {
                alertBaselineByIdentity[identity] = AlertBaseline(score: score, kickoff: row.data.fixture.utcDate)
            }
        }
        self.scores = newScores
        await MatchReminderStore.shared.reconcile(events: []) {
            MatchStartPolicy.currentStatus(for: $0, scores: self)
        }
        print("[LiveScoreService] Refreshed \(allMatches.count) matches. Checked for alerts.")
    }
    
    private func isRateLimited(_ error: Error) -> Bool {
        guard let e = error as? FootballProviderError else { return false }
        if case .rateLimited = e { return true }
        return false
    }
    
    private func mapToLegacyFootballMatch(_ data: MatchHubData, status: FottyMatchStatus? = nil) -> FootballMatch {
        let fixture = data.fixture
        return FootballMatch(
            id: Int(fixture.id) ?? 0,
            apiFootballFixtureId: fixture.apiFootballFixtureId.flatMap(Int.init),
            utcDate: ISO8601DateFormatter().string(from: fixture.utcDate),
            status: mapMatchStatus(status ?? fixture.status),
            matchday: fixture.matchday,
            stage: nil,
            group: nil,
            homeTeam: FootballTeam(id: Int(data.homeTeam.id), name: data.homeTeam.name, shortName: data.homeTeam.shortName, tla: nil, crest: data.homeTeam.crestURL?.absoluteString),
            awayTeam: FootballTeam(id: Int(data.awayTeam.id), name: data.awayTeam.name, shortName: data.awayTeam.shortName, tla: nil, crest: data.awayTeam.crestURL?.absoluteString),
            score: MatchScore(
                winner: data.score.home > data.score.away ? "HOME_TEAM" : (data.score.away > data.score.home ? "AWAY_TEAM" : "DRAW"),
                duration: "REGULAR",
                fullTime: ScoreDetail(home: data.score.home, away: data.score.away),
                halfTime: nil
            ),
            competition: MatchCompetition(
                id: Int(fixture.competition.id),
                name: fixture.competition.name,
                code: nil,
                emblem: fixture.competition.emblemURL?.absoluteString,
                country: fixture.competition.country
            ),
            referees: nil,
            events: data.events.enumerated().map { (index, event) in
                FootballMatchEvent(
                    id: (Int(fixture.id) ?? 0) << 16 | index,
                    teamId: Int(event.teamId) ?? 0,
                    minute: event.minute,
                    extraMinute: event.extraMinute,
                    type: mapEventType(event.type),
                    player: event.player,
                    assist: event.assist,
                    info: event.detail,
                    sortOrder: index
                )
            }
        )
    }
    
    private func mapMatchStatus(_ status: FottyMatchStatus) -> FootballMatch.MatchStatus {
        switch status {
        case .scheduled, .preMatch: return .scheduled
        case .live, .extraTime, .penalties: return .inPlay
        case .halfTime: return .paused
        case .fullTime: return .finished
        case .postponed: return .postponed
        case .cancelled: return .cancelled
        case .abandoned: return .cancelled
        case .unknown: return .scheduled
        }
    }
    
    private func mapEventType(_ type: FottyEventType) -> FootballMatchEvent.EventType {
        switch type {
        case .goal, .penalty, .ownGoal: return .goal
        case .yellowCard: return .yellowCard
        case .redCard: return .redCard
        case .substitution: return .substitution
        case .varDecision: return .varDecision
        default: return .other
        }
    }
    
    private func handleNotificationDiff(
        for match: FootballMatch,
        oldScore: LiveScore,
        newHome: Int,
        newAway: Int
    ) {
        guard MatchAlertPreferences.allows(
            homeTeam: match.homeTeam.displayName,
            awayTeam: match.awayTeam.displayName
        ) else { return }

        // --- 1. Goal Alerts ---
        if UserDefaults.standard.bool(forKey: "settings.notif.goals"),
           !WatchingSpoilerProtection.shared.suppressesGoal(home: match.homeTeam.displayName,
               away: match.awayTeam.displayName, kickoff: match.matchDate) {
            if newHome > oldScore.homeGoals || newAway > oldScore.awayGoals {
                let isSpoiler = UserDefaults.standard.bool(forKey: "settings.spoiler.protection")
                let content = MatchAlertContent.make(
                    kind: .goal(home: newHome, away: newAway),
                    homeTeam: match.homeTeam.displayName,
                    awayTeam: match.awayTeam.displayName,
                    competition: match.competition.audienceFacingName,
                    spoilerProtected: isSpoiler
                )
                
                NotificationManager.shared.scheduleMatchAlert(
                    title: content.title,
                    body: content.body,
                    matchID: String(match.id)
                )
            }
        }
        
        // --- 2. Kickoff Alerts ---
        if UserDefaults.standard.bool(forKey: "settings.notif.kickoff") {
            if FootballMatchAlertTransitionPolicy.shouldAnnounceKickoff(
                from: oldScore.status,
                to: match.status
            ) {
                let content = MatchAlertContent.make(
                    kind: .kickoff,
                    homeTeam: match.homeTeam.displayName,
                    awayTeam: match.awayTeam.displayName,
                    competition: match.competition.audienceFacingName,
                    spoilerProtected: UserDefaults.standard.bool(forKey: "settings.spoiler.protection")
                )
                NotificationManager.shared.scheduleMatchAlert(
                    title: content.title,
                    body: content.body,
                    matchID: String(match.id)
                )
            }
        }
        
        // --- 3. Full-time Alerts ---
        if UserDefaults.standard.bool(forKey: "settings.notif.fulltime") {
            if match.status == .finished && oldScore.status != .finished {
                let content = MatchAlertContent.make(
                    kind: .fullTime(home: newHome, away: newAway),
                    homeTeam: match.homeTeam.displayName,
                    awayTeam: match.awayTeam.displayName,
                    competition: match.competition.audienceFacingName,
                    spoilerProtected: UserDefaults.standard.bool(forKey: "settings.spoiler.protection")
                )
                NotificationManager.shared.scheduleMatchAlert(
                    title: content.title,
                    body: content.body,
                    matchID: String(match.id)
                )
            }
        }
    }
    
    private static var cleanedNameCache: [String: String] = [:]
    private static let cleanNameLock = NSLock()

    private func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        Self.cleanNameLock.lock()
        if let cached = Self.cleanedNameCache[trimmed] {
            Self.cleanNameLock.unlock()
            return cached
        }
        Self.cleanNameLock.unlock()

        let result = FootballDataPolicy.normalizedTeamMatchKey(trimmed)

        Self.cleanNameLock.lock()
        Self.cleanedNameCache[trimmed] = result
        Self.cleanNameLock.unlock()
        return result
    }

    private func rebuildMatchIndices(from matches: [FootballMatch]) {
        var direct: [String: FootballMatch] = [:]
        var clean: [String: FootballMatch] = [:]
        for match in matches {
            let cleanHome = cleanName(match.homeTeam.matchingName)
            let cleanAway = cleanName(match.awayTeam.matchingName)
            guard !cleanHome.isEmpty && !cleanAway.isEmpty else { continue }
            let directKey = makeKey(home: match.homeTeam.matchingName, away: match.awayTeam.matchingName)
            direct[directKey] = match
            clean["\(cleanHome)|\(cleanAway)"] = match
        }
        self.directKeyIndex = direct
        self.cleanKeyIndex = clean
        kickoffDateIndex.replace(dates: matches.map(\.utcDate))
    }
    
    private func makeKey(home: String, away: String) -> String {
        return "\(home.lowercased().trimmingCharacters(in: .whitespaces))|\(away.lowercased().trimmingCharacters(in: .whitespaces))"
    }
    
    func findMatch(home: String, away: String) -> FootballMatch? {
        let key = makeKey(home: home, away: away)

        if let cached = matchLookupCache[key] {
            return cached
        }
        if unmatchedLookupKeys.contains(key) {
            return nil
        }
        
        if let direct = directKeyIndex[key] {
            matchLookupCache[key] = direct
            return direct
        }

        let cleanHome = cleanName(home)
        let cleanAway = cleanName(away)
        let cleanKey = "\(cleanHome)|\(cleanAway)"
        if let cleanMatch = cleanKeyIndex[cleanKey] {
            matchLookupCache[key] = cleanMatch
            return cleanMatch
        }

        // A partial-name fallback must still identify the same squad; a youth
        // or women's name containing the senior club key cannot borrow its score.
        if cleanHome.count >= 4 && cleanAway.count >= 4 {
            let homeSquad = CatalogPlaybackIdentity.footballSquadIdentity(teamName: home)
            let awaySquad = CatalogPlaybackIdentity.footballSquadIdentity(teamName: away)
            for (indexedKey, match) in cleanKeyIndex {
                let parts = indexedKey.split(separator: "|")
                if parts.count == 2 {
                    let idxHome = String(parts[0])
                    let idxAway = String(parts[1])
                    if (idxHome.contains(cleanHome) || cleanHome.contains(idxHome)) &&
                       (idxAway.contains(cleanAway) || cleanAway.contains(idxAway)) {
                        guard homeSquad == CatalogPlaybackIdentity.footballSquadIdentity(teamName: match.homeTeam.matchingName),
                              awaySquad == CatalogPlaybackIdentity.footballSquadIdentity(teamName: match.awayTeam.matchingName) else {
                            continue
                        }
                        matchLookupCache[key] = match
                        return match
                    }
                }
            }
        }

        unmatchedLookupKeys.insert(key)
        return nil
    }

    /// Team names alone are not a fixture identity: the same clubs can meet in
    /// different competitions within days. Player surfaces must also confirm
    /// that the schedule fixture is close to the catalog event's kickoff.
    func findMatch(
        home: String,
        away: String,
        near kickoff: Date?,
        maximumKickoffDelta: TimeInterval = 18 * 3_600
    ) -> FootballMatch? {
        guard let kickoff,
              let match = findMatch(home: home, away: away),
              let matchKickoff = kickoffDateIndex.date(for: match.utcDate),
              abs(matchKickoff.timeIntervalSince(kickoff)) <= maximumKickoffDelta else {
            return nil
        }
        return match
    }

    func currentStatus(for match: FootballMatch, at now: Date = Date()) -> FootballMatch.MatchStatus? {
        guard match.status.isLive else { return match.status }
        guard let kickoff = kickoffDateIndex.date(for: match.utcDate),
              FootballDataPolicy.supportsLiveScores(competition: match.competition) else { return nil }
        let key = "premier-league|" + FootballDataPolicy.canonicalFixtureMatchKey(
            homeTeam: match.homeTeam.matchingName, awayTeam: match.awayTeam.matchingName, kickoff: kickoff)
        return HomeSportsDiscovery.recentStatus(match.status, refreshedAt: liveObservationByIdentity[key],
            liveFeedAvailable: feedMode != .unavailable && feedMode != .inactive, now: now)
    }
    
    func scoreForMatch(home: String, away: String) -> LiveScore? {
        let key = makeKey(home: home, away: away)
        if let match = findMatch(home: home, away: away) {
            guard FootballDataPolicy.supportsLiveScores(competition: match.competition) else {
                return nil
            }
            guard match.status.isLive || match.status.isFinished || match.status == .suspended else {
                return nil
            }
            guard currentStatus(for: match, at: currentDate()) != nil else { return nil }
            let matchedKey = makeKey(
                home: match.homeTeam.matchingName,
                away: match.awayTeam.matchingName
            )
            return LiveScore(
                homeGoals: match.score.fullTime?.home ?? 0,
                awayGoals: match.score.fullTime?.away ?? 0,
                status: match.status,
                minute: liveMinuteByKey[matchedKey] ?? liveMinuteByKey[key]
            )
        }
        guard let score = scores[key], !score.status.isLive,
              score.status.isFinished || score.status == .suspended else {
            return nil
        }
        return score
    }

    func scoreForMatch(home: String, away: String, near kickoff: Date?) -> LiveScore? {
        guard let match = findMatch(home: home, away: away, near: kickoff),
              FootballDataPolicy.supportsLiveScores(competition: match.competition),
              match.status.isLive || match.status.isFinished || match.status == .suspended else {
            return nil
        }
        guard currentStatus(for: match, at: currentDate()) != nil else { return nil }
        let matchedKey = makeKey(
            home: match.homeTeam.matchingName,
            away: match.awayTeam.matchingName
        )
        return LiveScore(
            homeGoals: match.score.fullTime?.home ?? 0,
            awayGoals: match.score.fullTime?.away ?? 0,
            status: match.status,
            minute: liveMinuteByKey[matchedKey]
        )
    }

    private static func minuteLabels(from hubs: [MatchHubData]) -> [String: String] {
        var labels: [String: String] = [:]
        for hub in hubs {
            guard hub.fixture.status.isLive else { continue }
            let home = FootballTeam.matchingName(name: hub.homeTeam.name, shortName: hub.homeTeam.shortName)
            let away = FootballTeam.matchingName(name: hub.awayTeam.name, shortName: hub.awayTeam.shortName)
            let key = "\(home.lowercased())|\(away.lowercased())"
            if let label = formatLiveMinute(elapsed: hub.fixture.elapsedMinutes, extra: hub.fixture.extraMinutes) {
                labels[key] = label
            }
        }
        return labels
    }

    private static func formatLiveMinute(elapsed: Int?, extra: Int?) -> String? {
        guard let elapsed else { return nil }
        if let extra, extra > 0 { return "\(elapsed)+\(extra)'" }
        return "\(elapsed)'"
    }

    #if DEBUG
    /// Deterministic scoreboard state for unit tests. Production refresh remains
    /// the only caller that installs network data.
    func installScoreboardFixturesForTesting(
        _ matches: [FootballMatch],
        minuteLabels: [String: String] = [:]
    ) {
        stopPolling()
        cachedMatches = matches
        analysisMatches = []
        scheduleLastVerifiedAt = nil
        scheduleRefreshFailed = false
        liveObservedAt = currentDate()
        feedMode = matches.isEmpty ? .inactive : .officialFPL
        acceptedTerminalRows = [:]
        alertBaselineByIdentity = [:]
        liveObservationByIdentity = [:]
        for match in matches where match.status.isLive && FootballDataPolicy.supportsLiveScores(competition: match.competition) {
            if let kickoff = CatalogISO8601DateParser.date(match.utcDate) {
                let key = "premier-league|" + FootballDataPolicy.canonicalFixtureMatchKey(
                    homeTeam: match.homeTeam.matchingName, awayTeam: match.awayTeam.matchingName, kickoff: kickoff)
                liveObservationByIdentity[key] = currentDate()
            }
        }
        liveMinuteByKey = minuteLabels
        scores = [:]
        matchLookupCache.removeAll(keepingCapacity: true)
        unmatchedLookupKeys.removeAll(keepingCapacity: true)
        rebuildMatchIndices(from: matches)
    }

    func alertBaselineForTesting(home: String, away: String, kickoff: Date) -> LiveScore? {
        let key = "premier-league|" + FootballDataPolicy.canonicalFixtureMatchKey(
            homeTeam: home, awayTeam: away, kickoff: kickoff)
        return alertBaselineByIdentity[key]?.score
    }
    #endif
}
