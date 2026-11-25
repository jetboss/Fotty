import Foundation

/// The terminal result of one single-player Watch tap.
enum WatchOutcomeTerminal: String, CaseIterable, Codable, Sendable {
    case playing
    case noStreamFound = "no_stream_found"
    case failed
    case cancelled
}

/// Opaque, bounded labels for one Watch tap's competition. These are the
/// app's own classification buckets, never a fixture name, team or URL.
enum WatchOutcomeCompetition {
    static let tvChannel = "tv_channel"

    @MainActor
    static func labels(for event: EventReference) -> (competition: String, sport: String) {
        let sport = token(event.normalizedCategory) ?? "other"
        if event.isBroadcastChannel { return (tvChannel, sport) }
        if sport == "football" {
            switch AnalyticalDataEngine.footballLeagueClassification(for: event).tab {
            case .premierLeague: return ("premier-league", sport)
            case .championsLeague: return ("champions-league", sport)
            case .laLiga: return ("la-liga", sport)
            case .serieA: return ("serie-a", sport)
            case .bundesliga: return ("bundesliga", sport)
            case .ligue1: return ("ligue-1", sport)
            case .all, .other: break
            }
        }
        let explicit = event.cricketFixture?.competitionID ?? event.competitionID ?? event.sportsFixture?.competitionID
        return (explicit.flatMap(token) ?? "\(sport)-other", sport)
    }

    /// Lowercase slug only; anything else is dropped rather than repaired.
    static func token(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              value.range(of: #"^[a-z0-9][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    static func displayName(_ competition: String) -> String {
        switch competition {
        case "premier-league": return "Premier League"
        case "champions-league": return "Champions League"
        case "la-liga": return "La Liga"
        case "serie-a": return "Serie A"
        case "bundesliga": return "Bundesliga"
        case "ligue-1": return "Ligue 1"
        case tvChannel: return "TV channels"
        default:
            return competition.replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// Writes exactly one private `watch_outcome` quality record per single-player
/// Watch tap: competition, sport, the opaque source family that played or
/// last failed, tap-to-first-picture time, automatic failover and the terminal
/// outcome. The record carries no fixture, URL, header, account, watch or
/// attempt identifier, and recording never touches the network.
///
/// This is bookkeeping only; it never influences admission, ranking or playback.
@MainActor
final class WatchOutcomeRecorder {
    static let shared = WatchOutcomeRecorder()
    nonisolated static let recordName = "watch_outcome"
    static let maximumPending = 8

    private struct Pending {
        let competition: String
        let sport: String
        let tappedAt: TimeInterval
        let order: Int
        var failoverFamily: String?
        var failoverCount = 0
    }

    private let store: FottyQualityStore
    private let clock: () -> TimeInterval
    private var pending: [UUID: Pending] = [:]
    private var nextOrder = 0

    init(store: FottyQualityStore = .shared,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.clock = clock
    }

    var pendingCount: Int { pending.count }

    func isPending(_ watchID: UUID) -> Bool { pending[watchID] != nil }

    /// The tap. A second begin for the same Watch never restarts its clock.
    func begin(watchID: UUID, event: EventReference) {
        let labels = WatchOutcomeCompetition.labels(for: event)
        begin(watchID: watchID, competition: labels.competition, sport: labels.sport)
    }

    func begin(watchID: UUID, competition: String, sport: String) {
        guard pending[watchID] == nil else { return }
        if pending.count >= Self.maximumPending,
           let oldest = pending.min(by: { $0.value.order < $1.value.order })?.key {
            // An abandoned tap is a cancellation, not silently lost evidence.
            finish(watchID: oldest, .cancelled)
        }
        nextOrder += 1
        pending[watchID] = Pending(competition: WatchOutcomeCompetition.token(competition) ?? "other",
                                   sport: WatchOutcomeCompetition.token(sport) ?? "other",
                                   tappedAt: clock(), order: nextOrder)
    }

    /// The player changed source on its own before this Watch reached a picture.
    func failover(watchID: UUID, toFamily family: String?) {
        guard var value = pending[watchID] else { return }
        value.failoverCount += 1
        value.failoverFamily = family.flatMap(Self.family) ?? value.failoverFamily
        pending[watchID] = value
    }

    func picture(watchID: UUID, family: String?) {
        finish(watchID: watchID, .playing, family: family)
    }

    /// Writes the one record for this Watch. Later calls for it are ignored.
    func finish(watchID: UUID, _ terminal: WatchOutcomeTerminal, failureKind: String? = nil, family: String? = nil) {
        guard let value = pending.removeValue(forKey: watchID) else { return }
        let elapsed = max(0, clock() - value.tappedAt)
        var details = [
            "competition": value.competition,
            "sport": value.sport,
            "terminal_outcome": terminal.rawValue,
            "failover_count": String(min(value.failoverCount, 12)),
            "route": "single"
        ]
        if let family = family.flatMap(Self.family) { details["source_family"] = family }
        if let failover = value.failoverFamily { details["failover_family"] = failover }
        if terminal != .playing, let kind = failureKind.flatMap(WatchOutcomeCompetition.token) {
            details["failure_kind"] = kind
        }
        store.record(category: .playback, name: Self.recordName,
                     outcome: terminal == .playing ? .success : (terminal == .cancelled ? .info : .failure),
                     durationMilliseconds: terminal == .playing ? Int((elapsed * 1_000).rounded()) : nil,
                     details: details)
    }

    /// Source families are short opaque codes (HF, CS, AS, TV, score808 …).
    /// Anything URL-like, long or punctuated is refused rather than recorded.
    nonisolated static func family(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    static func family(for source: StreamSource?) -> String? {
        source.flatMap { family(LiveSourceHealthStore.providerFamily(for: $0)) }
    }
}

/// Per-competition Watch reliability over the retained private records.
struct WatchOutcomeSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let competition: String
        let taps: Int
        let pictures: Int
        let failovers: Int
        let medianMillisecondsToPicture: Int?

        var id: String { competition }
        var pictureShare: Double { taps == 0 ? 0 : Double(pictures) / Double(taps) }
    }

    let rows: [Row]
    var totalTaps: Int { rows.reduce(0) { $0 + $1.taps } }

    static func summarize(_ records: [FottyQualityRecord]) -> WatchOutcomeSummary {
        let outcomes = records.filter { $0.category == .playback && $0.name == WatchOutcomeRecorder.recordName }
        let grouped = Dictionary(grouping: outcomes) { $0.details["competition"] ?? "other" }
        let rows = grouped.map { competition, values -> Row in
            let playing = values.filter { $0.details["terminal_outcome"] == WatchOutcomeTerminal.playing.rawValue }
            return Row(competition: competition, taps: values.count, pictures: playing.count,
                       failovers: values.count { (Int($0.details["failover_count"] ?? "") ?? 0) > 0 },
                       medianMillisecondsToPicture: median(playing.compactMap(\.durationMilliseconds)))
        }
        return WatchOutcomeSummary(rows: rows.sorted {
            $0.taps != $1.taps ? $0.taps > $1.taps : $0.competition < $1.competition
        })
    }

    /// Lower median for even counts, matching `FottyQualityStore.summarize`.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}

extension FottyQualityStore {
    func watchOutcomeSummary() -> WatchOutcomeSummary { WatchOutcomeSummary.summarize(records()) }
}

extension WatchOutcomeRecorder {
    /// Discovery ended before any player mounted for this Watch.
    func finish(watchID: UUID, resolutionFailure category: StreamFailureCategory) {
        switch category {
        case .navigationCancelled, .duplicateRequestCancelled, .userCancelled, .backgroundedDuringResolution:
            finish(watchID: watchID, .cancelled, failureKind: category.rawValue)
        case .noProviderAvailable, .providerReturnedEmpty, .invalidMatchMapping:
            finish(watchID: watchID, .noStreamFound, failureKind: category.rawValue)
        default:
            finish(watchID: watchID, .failed, failureKind: category.rawValue)
        }
    }
}
