import Foundation

/// Complete squad and public budget evidence required before offering a route.
public struct FPLTransferPlanContext {
    let picks: [FPLPick]
    let players: [FPLPlayer]
    let elementTypes: [FPLElementType]
    let gameSettings: FPLGameSettings?
    let budgetLimit: Int?

    var priceAssumption: String {
        picks.contains { $0.sellingPrice == nil }
            ? "Some selling prices are unavailable, so this estimate uses current player prices. Verify your bank in official FPL."
            : "Uses available selling prices and bank; verify both in official FPL before the deadline."
    }

    static func budgetLimit(picks: [FPLPick], players: [FPLPlayer], bank: Int?) -> Int? {
        guard let bank, !picks.isEmpty else { return nil }
        var budget = bank
        for pick in picks {
            guard let value = pick.sellingPrice ?? players.first(where: { $0.id == pick.element })?.nowCost else { return nil }
            budget += value
        }
        return budget
    }

    func validatedPicks(for transfers: [TransferRecommendation]) -> [FPLPick]? {
        guard budgetLimit != nil else { return nil }
        let outgoingIDs = transfers.map { $0.playerOut.player.id }
        let incomingIDs = transfers.map { $0.playerIn.player.id }
        guard Set(outgoingIDs).count == transfers.count,
              Set(incomingIDs).count == transfers.count,
              Set(outgoingIDs).isDisjoint(with: incomingIDs) else { return nil }
        var proposed = picks
        for transfer in transfers {
            guard let index = proposed.firstIndex(where: { $0.element == transfer.playerOut.player.id }),
                  let outgoing = players.first(where: { $0.id == proposed[index].element }),
                  let incoming = players.first(where: { $0.id == transfer.playerIn.player.id }),
                  incoming.elementType == outgoing.elementType,
                  !proposed.contains(where: { $0.element == incoming.id }) else { return nil }
            let oldPick = proposed[index]
            proposed[index] = FPLPick(element: incoming.id, position: oldPick.position,
                                      multiplier: oldPick.multiplier, isCaptain: oldPick.isCaptain,
                                      isViceCaptain: oldPick.isViceCaptain, elementType: incoming.elementType)
        }
        let report = FPLSquadValidator.validate(picks: proposed, players: players,
                                                elementTypes: elementTypes, gameSettings: gameSettings,
                                                budgetLimit: budgetLimit)
        return report.isValid ? proposed : nil
    }
}

public enum FPLPlannerEngine {
    public static func routes(
        recommendations: [TransferRecommendation],
        fixtures: [FPLFixture],
        startGameweek: Int,
        horizon: Int,
        freeTransfers: FPLFreeTransferEstimate?,
        gameweek: FPLGameweek?,
        context: FPLTransferPlanContext? = nil,
        events: [FPLGameweek]? = nil
    ) -> [FPLDraftRoute] {
        let weeks = FPLPlanningBounds.gameweeks(start: startGameweek, horizon: horizon, events: events)
        guard weeks.first == startGameweek,
              weeks == Array(startGameweek..<(startGameweek + weeks.count)) else { return [] }
        let horizon = weeks.count
        let freeCount = freeTransfers?.count ?? 0
        let freeTransferAssumption = freeTransfers.map { estimate in
            let noun = estimate.count == 1 ? "transfer" : "transfers"
            return "Point cost uses \(estimate.isExact ? "the available" : "an estimate of") \(estimate.count) free \(noun); confirm in official FPL."
        } ?? "Free transfers are unknown. Point cost assumes zero free transfers; confirm your count in official FPL."
        var results = [
            FPLDraftRoute(
                name: "Roll",
                transfers: [],
                hitCost: 0,
                projectedGain: 0,
                weeklyProjectedGain: Dictionary(
                    uniqueKeysWithValues: (startGameweek..<(startGameweek + max(1, horizon))).map { ($0, 0) }
                ),
                breakEvenGameweek: nil,
                modelVersion: FPLProjectionEngine.modelVersion,
                explanation: "Keep the squad and preserve flexibility. This is the baseline against which transfer routes are compared.",
                downside: "A flagged player or immediate fixture swing may go unaddressed, and prices can move before the next deadline.",
                verificationItems: [
                    "Check every selected player's latest availability flag.",
                    "Confirm the saved free-transfer count in official FPL."
                ]
            )
        ]

        if let context, let first = recommendations.first(where: { context.validatedPicks(for: [$0]) != nil }) {
            let weeklyGain = projectedGainByGameweek(
                recommendation: first,
                fixtures: fixtures,
                startGameweek: startGameweek,
                horizon: horizon
            )
            let hitCost = FPLTransferRules.estimatedHitCost(
                transferCount: 1,
                assumedFreeTransfers: freeCount,
                gameweek: gameweek
            )
            let netWeeklyGain = applying(hitCost: hitCost, to: weeklyGain, startGameweek: startGameweek)
            let gain = netWeeklyGain.values.reduce(0, +)
            results.append(
                FPLDraftRoute(
                    name: "One move",
                    transfers: [first],
                    hitCost: hitCost,
                    projectedGain: gain,
                    weeklyProjectedGain: netWeeklyGain,
                    breakEvenGameweek: breakEvenGameweek(
                        grossWeeklyGain: weeklyGain,
                        hitCost: hitCost
                    ),
                    modelVersion: FPLProjectionEngine.modelVersion,
                    explanation: "The strongest candidate from Fotty's current shortlist that passes full-squad checks with the available price estimate over \(horizon) gameweeks.",
                    downside: gain <= 4
                        ? "The modeled gain is narrow enough that one rotation, injury, or fixture change can erase it."
                        : "The incoming player's minutes, availability, and fixture assumptions can still change before the deadline.",
                    verificationItems: [
                        context.priceAssumption,
                        "Recheck both players' availability and likely minutes.",
                        freeTransferAssumption
                    ]
                )
            )
        }

        let pair = context.map { nonConflictingPair(recommendations, context: $0) } ?? []
        if pair.count == 2 {
            let cost = FPLTransferRules.estimatedHitCost(
                transferCount: 2,
                assumedFreeTransfers: freeCount,
                gameweek: gameweek
            )
            let grossWeekly = pair.reduce(into: [Int: Double]()) { result, recommendation in
                let gain = projectedGainByGameweek(
                    recommendation: recommendation,
                    fixtures: fixtures,
                    startGameweek: startGameweek,
                    horizon: horizon
                )
                for (gameweek, value) in gain {
                    result[gameweek, default: 0] += value
                }
            }
            let netWeekly = applying(hitCost: cost, to: grossWeekly, startGameweek: startGameweek)
            results.append(
                FPLDraftRoute(
                    name: "Two moves",
                    transfers: pair,
                    hitCost: cost,
                    projectedGain: netWeekly.values.reduce(0, +),
                    weeklyProjectedGain: netWeekly,
                    breakEvenGameweek: breakEvenGameweek(
                        grossWeeklyGain: grossWeekly,
                        hitCost: cost
                    ),
                    modelVersion: FPLProjectionEngine.modelVersion,
                    explanation: "Both moves pass combined budget, club quota and squad checks using available prices. The estimated point cost is deducted from the modeled gain.",
                    downside: cost > 0
                        ? "Verify the estimated point cost. If a hit is required, both incoming players must outperform the alternatives enough to recover it."
                        : "Two changes reduce flexibility and double the exposure to minutes or availability surprises.",
                    verificationItems: [
                        freeTransferAssumption,
                        context?.priceAssumption ?? "Verify both selling prices and the final bank.",
                        "Check club quota, formation, availability, and the deadline before confirming."
                    ]
                )
            )
        }
        return results
    }

    private static func projectedGainByGameweek(
        recommendation: TransferRecommendation,
        fixtures: [FPLFixture],
        startGameweek: Int,
        horizon: Int
    ) -> [Int: Double] {
        let outgoing = FPLProjectionEngine.project(
            player: recommendation.playerOut.player,
            fixtures: fixtures,
            startGameweek: startGameweek,
            horizon: horizon
        )
        let incoming = FPLProjectionEngine.project(
            player: recommendation.playerIn.player,
            fixtures: fixtures,
            startGameweek: startGameweek,
            horizon: horizon
        )
        return Dictionary(
            uniqueKeysWithValues: (startGameweek..<(startGameweek + max(1, horizon))).map { gameweek in
                let gain = (incoming.gameweekPoints[gameweek] ?? 0) - (outgoing.gameweekPoints[gameweek] ?? 0)
                return (gameweek, gain)
            }
        )
    }

    private static func applying(
        hitCost: Int,
        to weeklyGain: [Int: Double],
        startGameweek: Int
    ) -> [Int: Double] {
        var adjusted = weeklyGain
        adjusted[startGameweek, default: 0] -= Double(hitCost)
        return adjusted
    }

    private static func breakEvenGameweek(
        grossWeeklyGain: [Int: Double],
        hitCost: Int
    ) -> Int? {
        var cumulative = 0.0
        for gameweek in grossWeeklyGain.keys.sorted() {
            cumulative += grossWeeklyGain[gameweek] ?? 0
            if cumulative >= Double(hitCost) && cumulative > 0 {
                return gameweek
            }
        }
        return nil
    }

    private static func nonConflictingPair(_ recommendations: [TransferRecommendation], context: FPLTransferPlanContext) -> [TransferRecommendation] {
        for (index, first) in recommendations.enumerated() {
            for second in recommendations.dropFirst(index + 1) {
                if context.validatedPicks(for: [first, second]) != nil {
                    return [first, second]
                }
            }
        }
        return []
    }
}

public enum FPLSquadOptimizer {
    private struct Candidate {
        let score: PlayerScore
        let projectedPoints: Double
        let utility: Double
    }

    public static func generate(
        profiles: [FPLOptimizedSquad.Profile] = FPLOptimizedSquad.Profile.allCases,
        scores: [PlayerScore],
        fixtures: [FPLFixture],
        elementTypes: [FPLElementType],
        settings: FPLGameSettings?,
        startGameweek: Int,
        horizon: Int,
        budget: Int,
        lockedPlayerIDs: Set<Int> = [],
        excludedPlayerIDs: Set<Int> = [],
        events: [FPLGameweek]? = nil
    ) -> [FPLOptimizedSquad] {
        let weeks = FPLPlanningBounds.gameweeks(start: startGameweek, horizon: horizon, events: events)
        guard budget > 0, weeks.first == startGameweek,
              weeks == Array(startGameweek..<(startGameweek + weeks.count)) else { return [] }
        return profiles.compactMap { profile in
            optimize(
                profile: profile,
                scores: scores,
                fixtures: fixtures,
                elementTypes: elementTypes,
                settings: settings,
                startGameweek: startGameweek,
                horizon: weeks.count,
                budget: budget,
                lockedPlayerIDs: lockedPlayerIDs,
                excludedPlayerIDs: excludedPlayerIDs
            )
        }
    }

    private static func optimize(
        profile: FPLOptimizedSquad.Profile,
        scores: [PlayerScore],
        fixtures: [FPLFixture],
        elementTypes: [FPLElementType],
        settings: FPLGameSettings?,
        startGameweek: Int,
        horizon: Int,
        budget: Int,
        lockedPlayerIDs: Set<Int>,
        excludedPlayerIDs: Set<Int>
    ) -> FPLOptimizedSquad? {
        let eligible = scores.filter {
            !excludedPlayerIDs.contains($0.player.id)
                && $0.player.removed != true
                && $0.player.canSelect != false
                && $0.player.status != "u"
        }
        let candidates = eligible.map { score -> Candidate in
            let projection = FPLProjectionEngine.project(
                player: score.player,
                fixtures: fixtures,
                startGameweek: startGameweek,
                horizon: horizon
            ).total
            return Candidate(
                score: score,
                projectedPoints: projection,
                utility: utility(profile: profile, score: score, projection: projection)
            )
        }
        let byPosition = Dictionary(grouping: candidates, by: { $0.score.player.elementType })
        let required = Dictionary(uniqueKeysWithValues: elementTypes.compactMap { type in
            type.squadSelect.map { (type.id, $0) }
        })
        let quotas = required.isEmpty ? [1: 2, 2: 5, 3: 5, 4: 3] : required
        let teamLimit = settings?.squadTeamLimit ?? 3

        var selected = [Candidate]()
        var clubCounts = [Int: Int]()
        for position in 1...4 {
            let quota = quotas[position, default: 0]
            let locked = candidates.filter {
                lockedPlayerIDs.contains($0.score.player.id) && $0.score.player.elementType == position
            }
            for candidate in locked where !selected.contains(where: { $0.score.id == candidate.score.id }) {
                guard clubCounts[candidate.score.player.team, default: 0] < teamLimit else { return nil }
                selected.append(candidate)
                clubCounts[candidate.score.player.team, default: 0] += 1
            }
            guard locked.count <= quota else { return nil }

            let cheapest = (byPosition[position] ?? []).sorted {
                if $0.score.player.nowCost == $1.score.player.nowCost { return $0.utility > $1.utility }
                return $0.score.player.nowCost < $1.score.player.nowCost
            }
            for candidate in cheapest {
                if selected.filter({ $0.score.player.elementType == position }).count >= quota { break }
                if selected.contains(where: { $0.score.id == candidate.score.id }) { continue }
                if clubCounts[candidate.score.player.team, default: 0] >= teamLimit { continue }
                selected.append(candidate)
                clubCounts[candidate.score.player.team, default: 0] += 1
            }
            if selected.filter({ $0.score.player.elementType == position }).count != quota { return nil }
        }

        var totalCost = selected.reduce(0) { $0 + $1.score.player.nowCost }
        guard totalCost <= budget else { return nil }

        for _ in 0..<100 {
            var bestSwap: (index: Int, incoming: Candidate, gain: Double, cost: Int)?
            let selectedIDs = Set(selected.map { $0.score.id })
            for (index, outgoing) in selected.enumerated() {
                if lockedPlayerIDs.contains(outgoing.score.id) { continue }
                for incoming in byPosition[outgoing.score.player.elementType] ?? [] {
                    if selectedIDs.contains(incoming.score.id) { continue }
                    let costDelta = incoming.score.player.nowCost - outgoing.score.player.nowCost
                    if totalCost + costDelta > budget { continue }
                    var trialClubCounts = clubCounts
                    trialClubCounts[outgoing.score.player.team, default: 0] -= 1
                    trialClubCounts[incoming.score.player.team, default: 0] += 1
                    if trialClubCounts[incoming.score.player.team, default: 0] > teamLimit { continue }
                    let gain = incoming.utility - outgoing.utility
                    if gain <= 0 { continue }
                    if bestSwap == nil || gain > bestSwap!.gain {
                        bestSwap = (index, incoming, gain, costDelta)
                    }
                }
            }
            guard let bestSwap else { break }
            let outgoing = selected[bestSwap.index]
            clubCounts[outgoing.score.player.team, default: 0] -= 1
            clubCounts[bestSwap.incoming.score.player.team, default: 0] += 1
            selected[bestSwap.index] = bestSwap.incoming
            totalCost += bestSwap.cost
        }

        let ordered = orderSquad(selected)
        guard ordered.count == 15 else { return nil }
        let captainID = ordered.prefix(11)
            .filter { $0.score.player.elementType != 1 }
            .max { $0.projectedPoints < $1.projectedPoints }?
            .score.id
        let picks = ordered.enumerated().map { index, candidate in
            let isCaptain = candidate.score.id == captainID
            return FPLPick(
                element: candidate.score.id,
                position: index + 1,
                multiplier: isCaptain ? 2 : (index < 11 ? 1 : 0),
                isCaptain: isCaptain,
                isViceCaptain: false,
                elementType: candidate.score.player.elementType
            )
        }
        let captainIndex = picks.firstIndex(where: \.isCaptain) ?? 1
        let viceIndex = ordered.indices
            .filter { $0 < 11 && $0 != captainIndex }
            .max { ordered[$0].projectedPoints < ordered[$1].projectedPoints } ?? 0
        let finalized = picks.enumerated().map { index, pick in
            FPLPick(
                element: pick.element,
                position: pick.position,
                multiplier: pick.multiplier,
                isCaptain: pick.isCaptain,
                isViceCaptain: index == viceIndex,
                elementType: pick.elementType
            )
        }
        let validation = FPLSquadValidator.validate(
            picks: finalized,
            players: scores.map(\.player),
            elementTypes: elementTypes,
            gameSettings: settings,
            budgetLimit: budget
        )
        guard validation.isValid else { return nil }
        let projected = ordered.prefix(11).reduce(0.0) { total, candidate in
            total + candidate.projectedPoints
        } + ordered[captainIndex].projectedPoints
        return FPLOptimizedSquad(
            profile: profile,
            picks: finalized,
            projectedPoints: projected,
            cost: totalCost,
            validation: validation,
            explanation: "A legal constrained heuristic draft for a \(horizon)-gameweek \(profile.rawValue.lowercased()) profile; it is not a mathematical guarantee or an official FPL action."
        )
    }

    private static func utility(
        profile: FPLOptimizedSquad.Profile,
        score: PlayerScore,
        projection: Double
    ) -> Double {
        let ownership = Double(score.player.selectedByPercent) ?? 0
        switch profile {
        case .safe:
            return projection + score.minutesScore * 0.025 + ownership * 0.018
        case .balanced:
            return projection + score.compositeScore * 0.035
        case .aggressive:
            return projection + score.formScore * 0.025 + score.xGIScore * 0.025 + max(0, 15 - ownership) * 0.04
        }
    }

    private static func orderSquad(_ selected: [Candidate]) -> [Candidate] {
        let formations = [(3, 5, 2), (3, 4, 3), (4, 5, 1), (4, 4, 2), (4, 3, 3), (5, 4, 1), (5, 3, 2), (5, 2, 3)]
        let byPosition = Dictionary(grouping: selected, by: { $0.score.player.elementType })
            .mapValues { $0.sorted { $0.projectedPoints > $1.projectedPoints } }
        guard let goalkeeper = byPosition[1]?.first else { return [] }

        let bestFormation = formations.max { lhs, rhs in
            formationPoints(lhs, byPosition: byPosition) < formationPoints(rhs, byPosition: byPosition)
        } ?? (3, 4, 3)
        let starters = [goalkeeper]
            + Array((byPosition[2] ?? []).prefix(bestFormation.0))
            + Array((byPosition[3] ?? []).prefix(bestFormation.1))
            + Array((byPosition[4] ?? []).prefix(bestFormation.2))
        let starterIDs = Set(starters.map { $0.score.id })
        let benchGoalkeeper = (byPosition[1] ?? []).first { !starterIDs.contains($0.score.id) }
        let outfieldBench = selected
            .filter { !starterIDs.contains($0.score.id) && $0.score.player.elementType != 1 }
            .sorted { $0.projectedPoints > $1.projectedPoints }
        return starters + (benchGoalkeeper.map { [$0] } ?? []) + outfieldBench
    }

    private static func formationPoints(
        _ formation: (Int, Int, Int),
        byPosition: [Int: [Candidate]]
    ) -> Double {
        (byPosition[1]?.first?.projectedPoints ?? 0)
            + (byPosition[2] ?? []).prefix(formation.0).reduce(0) { $0 + $1.projectedPoints }
            + (byPosition[3] ?? []).prefix(formation.1).reduce(0) { $0 + $1.projectedPoints }
            + (byPosition[4] ?? []).prefix(formation.2).reduce(0) { $0 + $1.projectedPoints }
    }
}
