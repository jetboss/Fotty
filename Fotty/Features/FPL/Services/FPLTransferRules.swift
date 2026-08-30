import Foundation

public enum FPLTransferRules {
    public static let maximumBankedFreeTransfers = 5
    public static let additionalTransferCost = 4

    public static func hasUnlimitedPreseasonTransfers(
        gameweek: FPLGameweek?,
        now: Date = Date()
    ) -> Bool {
        guard let gameweek, gameweek.id == 1 else { return false }
        return gameweek.isBeforeDeadline(at: now)
    }

    public static func estimatedHitCost(
        transferCount: Int,
        assumedFreeTransfers: Int,
        gameweek: FPLGameweek?,
        now: Date = Date()
    ) -> Int {
        guard transferCount > 0 else { return 0 }
        if hasUnlimitedPreseasonTransfers(gameweek: gameweek, now: now) {
            return 0
        }

        let boundedFreeTransfers = min(
            maximumBankedFreeTransfers,
            max(0, assumedFreeTransfers)
        )
        return max(0, transferCount - boundedFreeTransfers) * additionalTransferCost
    }
}
