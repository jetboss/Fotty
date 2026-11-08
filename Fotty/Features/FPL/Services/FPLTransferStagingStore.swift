import Foundation

/// A comparison of planning inputs, independent of changing live multipliers.
struct FPLTransferStagingBaseline: Codable, Equatable {
    let picks: [FPLPick]
    let publishedPicks: [FPLPick]
    let publishedGameweek: Int?
    let targetGameweek: Int
    let budgetLimit: Int?

    init(picks: [FPLPick], publishedPicks: [FPLPick], publishedGameweek: Int?, targetGameweek: Int, budgetLimit: Int?) {
        self.picks = Self.normalized(picks)
        self.publishedPicks = Self.normalized(publishedPicks)
        self.publishedGameweek = publishedGameweek
        self.targetGameweek = targetGameweek
        self.budgetLimit = budgetLimit
    }

    static func normalized(_ picks: [FPLPick]) -> [FPLPick] {
        picks.sorted { $0.position < $1.position }.map {
            FPLPick(element: $0.element, position: $0.position,
                    multiplier: $0.position > 11 ? 0 : ($0.isCaptain ? 2 : 1),
                    isCaptain: $0.isCaptain, isViceCaptain: $0.isViceCaptain,
                    purchasePrice: $0.purchasePrice, sellingPrice: $0.sellingPrice,
                    elementType: $0.elementType)
        }
    }

    static func priced(_ picks: [FPLPick], using published: [FPLPick]) -> [FPLPick] {
        picks.map { pick in
            let current = published.first { $0.element == pick.element }
            return FPLPick(element: pick.element, position: pick.position, multiplier: pick.multiplier,
                           isCaptain: pick.isCaptain, isViceCaptain: pick.isViceCaptain,
                           purchasePrice: current?.purchasePrice, sellingPrice: current?.sellingPrice,
                           elementType: pick.elementType ?? current?.elementType)
        }
    }
}

/// Staging is recoverable working state, separate from the validated saved squad.
struct FPLTransferStagingState: Codable, Equatable {
    struct Checkpoint: Codable, Equatable {
        let baseline: FPLTransferStagingBaseline
        let picks: [FPLPick]
    }

    let managerID: Int
    let season: String
    private(set) var baseline: FPLTransferStagingBaseline
    private(set) var latestBaseline: FPLTransferStagingBaseline
    private(set) var picks: [FPLPick]
    private(set) var history: [Checkpoint] = []

    init(managerID: Int, season: String, baseline: FPLTransferStagingBaseline) {
        self.managerID = managerID
        self.season = season
        self.baseline = baseline
        self.latestBaseline = baseline
        self.picks = baseline.picks
    }

    var hasChanges: Bool { picks != baseline.picks }
    var hasConflict: Bool { baseline != latestBaseline }
    var canUndo: Bool { !history.isEmpty }

    mutating func synchronize(with latest: FPLTransferStagingBaseline) {
        latestBaseline = latest
        // Price/live refreshes must not erase the user's unfinished moves.
        if !hasChanges {
            baseline = latest
            picks = latest.picks
        }
    }

    mutating func stage(_ newPicks: [FPLPick]) {
        let normalized = FPLTransferStagingBaseline.normalized(
            FPLTransferStagingBaseline.priced(newPicks, using: baseline.picks))
        guard normalized != picks else { return }
        checkpoint()
        picks = normalized
    }

    mutating func reset() {
        guard picks != latestBaseline.picks || hasConflict else { return }
        checkpoint()
        baseline = latestBaseline
        picks = latestBaseline.picks
    }

    /// Keep the chosen squad, but value it against the newly acknowledged source.
    /// Final validation and saving still belong to `FPLAdvisorViewModel`.
    mutating func keepStagedPlan() {
        guard hasConflict else { return }
        checkpoint()
        picks = picks.map { pick in
            let current = latestBaseline.picks.first { $0.element == pick.element }
            return FPLPick(element: pick.element, position: pick.position,
                           multiplier: pick.multiplier, isCaptain: pick.isCaptain,
                           isViceCaptain: pick.isViceCaptain,
                           purchasePrice: current?.purchasePrice, sellingPrice: current?.sellingPrice,
                           elementType: current?.elementType ?? pick.elementType)
        }
        baseline = latestBaseline
    }

    mutating func undo() {
        guard let previous = history.popLast() else { return }
        baseline = previous.baseline
        picks = previous.picks
        // A restored old baseline remains a visible conflict with current data.
    }

    private mutating func checkpoint() {
        history.append(Checkpoint(baseline: baseline, picks: picks))
        history = Array(history.suffix(10))
    }
}

@MainActor
final class FPLTransferStagingStore {
    private let defaults: UserDefaults
    private let persists: Bool
    private var inMemory: [String: FPLTransferStagingState] = [:]

    init(defaults: UserDefaults, persists: Bool = true) {
        self.defaults = defaults
        self.persists = persists
    }

    func load(managerID: Int, season: String, baseline: FPLTransferStagingBaseline) -> FPLTransferStagingState {
        let key = Self.key(managerID: managerID, season: season)
        let stored: FPLTransferStagingState?
        if persists {
            stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FPLTransferStagingState.self, from: $0) }
        } else {
            stored = inMemory[key]
        }
        var state = stored.flatMap {
            $0.managerID == managerID && managerID > 0 && $0.season == season
                && $0.picks.count <= 15 && $0.history.count <= 10 ? $0 : nil
        } ?? FPLTransferStagingState(managerID: managerID, season: season, baseline: baseline)
        state.synchronize(with: baseline)
        return state
    }

    func save(_ state: FPLTransferStagingState) {
        guard state.managerID > 0 else { return }
        let key = Self.key(managerID: state.managerID, season: state.season)
        if persists, let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        } else if !persists {
            inMemory[key] = state
        }
    }

    static func key(managerID: Int, season: String) -> String {
        "fotty.fpl.\(season).manager.\(managerID).transferStaging"
    }
}
