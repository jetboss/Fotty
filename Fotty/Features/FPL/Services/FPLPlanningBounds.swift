import Foundation

/// Planning never invents GW39 or silently assigns a future decision to the
/// live gameweek. Passing an empty official calendar means no current evidence.
public enum FPLPlanningBounds {
    public static func gameweeks(start: Int, horizon: Int, events: [FPLGameweek]? = nil) -> [Int] {
        guard (1...38).contains(start), horizon > 0 else { return [] }
        let requested = start...min(38, start + min(horizon, 38) - 1)
        guard let events else { return Array(requested) }
        let official = Set(events.map(\.id))
        // A gap is missing evidence, not permission to shift GW6 into the GW5
        // projection slot. Stop at the first absent official event.
        return Array(requested.prefix { official.contains($0) })
    }

    public static func targetGameweek(explicit: Int?, planningGameweek: Int, events: [FPLGameweek]) -> Int? {
        let target = explicit ?? planningGameweek
        return (1...38).contains(target) && events.contains { $0.id == target } ? target : nil
    }
}

/// One modeled starting budget for automatic and manual wildcard generation.
/// Public current prices are not the manager's authenticated selling prices.
public struct FPLWildcardBudget: Equatable, Sendable {
    public let amount: Int
    public let explanation: String

    public static func resolve(
        publishedPicks: FPLManagerPicks?, publishedGameweek: Int?, managerSummary: FPLManagerSummary?,
        players: [FPLPlayer], savedDraftBudgetLimit: Int?, draftBudgetLimit: Int?, settings: FPLGameSettings?
    ) -> Self {
        let historyBank = publishedPicks?.entryHistory.flatMap { history in
            publishedGameweek == nil || history.event == publishedGameweek ? history.bank : nil
        }
        let summaryBank = publishedGameweek.flatMap { week in
            managerSummary?.currentEvent == week ? managerSummary?.lastDeadlineBank : nil
        }
        let bank = historyBank ?? summaryBank
        if let publishedPicks,
           let amount = FPLTransferPlanContext.budgetLimit(picks: publishedPicks.picks, players: players, bank: bank),
           amount > 0 {
            return .init(amount: amount, explanation: publishedPicks.picks.contains { $0.sellingPrice == nil }
                ? "Budget estimates published squad value plus bank using current prices where selling prices are private. Verify affordability in official FPL."
                : "Budget uses the available published selling values and bank. Verify current affordability in official FPL.")
        }
        if let amount = [savedDraftBudgetLimit, draftBudgetLimit].compactMap({ $0 }).first(where: { $0 > 0 }) {
            return .init(amount: amount, explanation: "Uses the saved local planning budget. Current selling prices and bank are not verified; confirm them in official FPL.")
        }
        return .init(amount: max(1, settings?.squadTotalSpend ?? 1_000),
                     explanation: "Uses the initial-squad rule budget, not a verified manager balance. Confirm affordability in official FPL.")
    }
}

/// Every optimizer publication has a content identity, even when it replaces
/// three profiles with three changed profiles. User locks remain separate.
public enum FPLWildcardResultIdentity {
    public static func signature(_ squads: [FPLOptimizedSquad]) -> String {
        squads.map { squad in
            let picks = squad.picks.sorted { $0.position < $1.position }.map {
                "\($0.element):\($0.position):\($0.isCaptain):\($0.isViceCaptain)"
            }.joined(separator: ",")
            return "\(squad.profile.rawValue)|\(picks)|\(squad.cost)|\(squad.projectedPoints)|\(squad.validation.isValid)|\(squad.explanation)"
        }.joined(separator: ";")
    }
}

/// Local constrained output is retained for inspection, but cannot be saved as
/// current after its inputs change. Unconstrained output follows publication.
public struct FPLWildcardWorkingResult {
    private var generated: [FPLOptimizedSquad]?
    public private(set) var needsRefresh = false

    public init() {}

    public func displayedSquads(published: [FPLOptimizedSquad]) -> [FPLOptimizedSquad] {
        generated ?? published
    }

    public mutating func acceptGenerated(_ squads: [FPLOptimizedSquad]) {
        generated = squads
        needsRefresh = false
    }

    public mutating func sourceChanged(hasConstraints: Bool) {
        guard generated != nil else { return }
        if hasConstraints { needsRefresh = true }
        else { generated = nil; needsRefresh = false }
    }
}
