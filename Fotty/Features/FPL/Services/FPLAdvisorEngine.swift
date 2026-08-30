import Foundation
import SwiftUI

// MARK: - Engine Output Structs

public struct PlayerScore: Identifiable, Sendable {
    public var id: Int { player.id }
    public let player: FPLPlayer
    public let team: FPLTeam
    public let compositeScore: Double
    public let formScore: Double
    public let fixtureScore: Double
    public let xGIScore: Double
    public let ictScore: Double
    public let valueScore: Double
    public let minutesScore: Double
    public let ownershipScore: Double
    public let xGRegressionState: XGRegressionState
    public let upcomingFixtures: [UpcomingFixture]
    public let priceChangeRisk: PriceRisk
    public let availabilityRisk: AvailabilityRisk
    
    public enum PriceRisk: String, Sendable {
        case rising, falling, stable
    }
    
    public enum AvailabilityRisk: String, Sendable {
        case available, doubtful, injured, suspended, unavailable
    }
    
    public enum XGRegressionState: String, Sendable {
        case dueForExplosion = "Goals below cumulative xG"
        case overperforming = "Overperforming xG (Regression Risk)"
        case expected = "Performing as Expected"
    }
}

public struct UpcomingFixture: Identifiable, Sendable {
    public var id: Int { gameweek }
    public let gameweek: Int
    public let opponent: FPLTeam
    public let isHome: Bool
    public let difficulty: Int // 1-5
}

public struct TransferRecommendation: Identifiable, Sendable {
    public var id: String { "\(playerOut.id)-\(playerIn.id)" }
    public let playerOut: PlayerScore
    public let playerIn: PlayerScore
    public let scoreUplift: Double
    public let costDelta: Int
    public let reason: String
}

public struct CaptainRecommendation: Identifiable, Sendable {
    public var id: Int { player.id }
    public let player: PlayerScore
    public let expectedPoints: Double
    public let selectionPercent: Double
    public let reason: String
}

public struct PriceChangeAlert: Identifiable, Sendable {
    public var id: Int { player.id }
    public let player: FPLPlayer
    public let team: FPLTeam
    public let isRising: Bool
    public let netTransfers: Int
    public let thresholdPercent: Int
    public let officialProjectedPercent: Double
    public let officialLikelihood: Int
    public let projectionOffset: Int
    public let isCalibrating: Bool
    public let reasoning: String
}

public struct TeamFixtureRow: Identifiable, Sendable {
    public var id: Int { team.id }
    public let team: FPLTeam
    public let fixtures: [UpcomingFixture?]
    public let avgDifficulty: Double
}

// MARK: - Mini-League Rival Gap Analysis

public struct RivalGapAnalysis: Sendable {
    public let rivalName: String
    public let gameweek: Int
    public let phase: FPLGameweekPhase
    public let myRank: Int
    public let rivalRank: Int
    public let myPoints: Int
    public let rivalPoints: Int
    public let pointDeficit: Int
    public let myGameweekPoints: Int
    public let rivalGameweekPoints: Int
    public let gameweekDeficit: Int
    public let strategyMode: StrategyMode
    public let myDifferentials: [PlayerScore]
    public let rivalThreats: [PlayerScore]
    public let sharedPlayers: [PlayerScore]
    public let myCaptainName: String?
    public let rivalCaptainName: String?
    public let myPlayersRemaining: Int
    public let rivalPlayersRemaining: Int
    public let myUniqueLivePoints: Int
    public let rivalUniqueLivePoints: Int
    public let hasOfficialLiveSnapshot: Bool
    public let tacticalAdvice: String

    /// Positive means your published unique players currently lead the rival's.
    public var uniquePlayerSwing: Int { myUniqueLivePoints - rivalUniqueLivePoints }
    
    public enum StrategyMode: String, Sendable {
        case catchUpMode = "CATCH-UP MODE"
        case protectionMode = "PROTECTION MODE"
        case neckAndNeck = "NECK-AND-NECK MODE"
    }
}

// MARK: - FPL Advisor Engine

public enum FPLAdvisorEngine {
    
    // Pro Weights (incorporating xGI)
    private static let weightForm = 0.30
    private static let weightFixtures = 0.25
    private static let weightXGI = 0.20
    private static let weightValue = 0.15
    private static let weightMinutes = 0.10
    private static let weightOwnership = 0.00
    
    private static func normalize(_ value: Double, minVal: Double, maxVal: Double) -> Double {
        guard maxVal > minVal else { return 50.0 }
        let norm = ((value - minVal) / (maxVal - minVal)) * 100.0
        return Swift.max(0.0, Swift.min(100.0, norm))
    }
    
    // MARK: - Score All Players
    
    public static func scoreAllPlayers(
        players: [FPLPlayer],
        teams: [FPLTeam],
        fixtures: [FPLFixture],
        events: [FPLGameweek]
    ) -> [PlayerScore] {
        let currentGwEvent = events.first(where: { $0.isCurrent })
        let nextGwEvent = events.first(where: { $0.isNext })
        
        let startGw: Int
        if let cur = currentGwEvent {
            startGw = cur.finished ? (nextGwEvent?.id ?? (cur.id + 1)) : cur.id
        } else {
            startGw = nextGwEvent?.id ?? 1
        }
        
        let activePlayers = players.filter { $0.status != "u" && $0.status != "n" }
        
        let forms = activePlayers.compactMap { Double($0.form) }
        let minForm = forms.min() ?? 0.0
        let maxForm = forms.max() ?? 1.0
        
        let xgis = activePlayers.map { $0.xGIValue }
        let minXGI = xgis.min() ?? 0.0
        let maxXGI = xgis.max() ?? 1.0
        
        let icts = activePlayers.compactMap { Double($0.ictIndex) }
        let minICT = icts.min() ?? 0.0
        let maxICT = icts.max() ?? 1.0
        
        let ppms = activePlayers.map { p -> Double in
            let ppg = Double(p.pointsPerGame) ?? 0.0
            let cost = Double(p.nowCost) / 10.0
            return cost > 0 ? ppg / cost : 0.0
        }
        let minPPM = ppms.min() ?? 0.0
        let maxPPM = ppms.max() ?? 0.1
        
        let finishedGws = max(1, events.filter { $0.finished }.count)
        let expectedMins = Double(finishedGws * 90)
        
        return activePlayers.compactMap { player in
            guard let team = teams.first(where: { $0.id == player.team }) else { return nil }
            
            // Upcoming fixtures (next 5)
            let teamFixtures = getTeamUpcomingFixtures(teamId: player.team, fixtures: fixtures, teams: teams, startGw: startGw, count: 5)
            
            // Form score
            let formVal = Double(player.form) ?? 0.0
            let formScore = normalize(formVal, minVal: minForm, maxVal: maxForm)
            
            // Fixture score (invert: FDR 1 -> 100, FDR 5 -> 0)
            let avgDiff = teamFixtures.isEmpty ? 3.0 : (Double(teamFixtures.map(\.difficulty).reduce(0, +)) / Double(teamFixtures.count))
            let fixtureScore = normalize(5.0 - avgDiff, minVal: 0.0, maxVal: 4.0)
            
            // xGI score
            let xgiScore = normalize(player.xGIValue, minVal: minXGI, maxVal: maxXGI)
            let ictVal = Double(player.ictIndex) ?? 0.0
            let ictScore = normalize(ictVal, minVal: minICT, maxVal: maxICT)
            
            // Value score
            let ppg = Double(player.pointsPerGame) ?? 0.0
            let cost = Double(player.nowCost) / 10.0
            let ppm = cost > 0 ? ppg / cost : 0.0
            let valueScore = normalize(ppm, minVal: minPPM, maxVal: maxPPM)
            
            // Minutes score
            let minRatio = Double(player.minutes) / expectedMins
            let minutesScore = normalize(minRatio, minVal: 0.0, maxVal: 1.0)
            
            // Ownership differential score
            let ownership = Double(player.selectedByPercent) ?? 0.0
            let ownershipScore: Double
            if ownership > 50 { ownershipScore = 30 }
            else if ownership > 30 { ownershipScore = 50 }
            else if ownership > 10 { ownershipScore = 70 }
            else { ownershipScore = 90 }
            
            // Only fields from the current official FPL response influence the score.
            let effectiveFormScore = formScore
            
            let baseComposite = (effectiveFormScore * weightForm) +
                                (fixtureScore * weightFixtures) +
                                (xgiScore * weightXGI) +
                                (valueScore * weightValue) +
                                (minutesScore * weightMinutes) +
                                (ownershipScore * weightOwnership)
            
            let composite = baseComposite
            
            // xG Regression state
            let actualGoals = Double(player.goalsScored)
            let xG = player.xGValue
            let regressionState: PlayerScore.XGRegressionState
            if xG > actualGoals + 1.2 {
                regressionState = .dueForExplosion
            } else if actualGoals > xG + 2.5 {
                regressionState = .overperforming
            } else {
                regressionState = .expected
            }
            
            let netTransfers = player.transfersInEvent - player.transfersOutEvent
            let priceRisk: PlayerScore.PriceRisk = netTransfers > 40000 ? .rising : (netTransfers < -40000 ? .falling : .stable)
            
            let availRisk: PlayerScore.AvailabilityRisk
            switch player.status {
            case "a": availRisk = .available
            case "d": availRisk = .doubtful
            case "i": availRisk = .injured
            case "s": availRisk = .suspended
            default: availRisk = .unavailable
            }
            
            return PlayerScore(
                player: player,
                team: team,
                compositeScore: (composite * 10).rounded() / 10.0,
                formScore: effectiveFormScore.rounded(),
                fixtureScore: fixtureScore.rounded(),
                xGIScore: xgiScore.rounded(),
                ictScore: ictScore.rounded(),
                valueScore: valueScore.rounded(),
                minutesScore: minutesScore.rounded(),
                ownershipScore: ownershipScore.rounded(),
                xGRegressionState: regressionState,
                upcomingFixtures: teamFixtures,
                priceChangeRisk: priceRisk,
                availabilityRisk: availRisk
            )
        }.sorted(by: { $0.compositeScore > $1.compositeScore })
    }
    
    // MARK: - Transfer Recommendations
    
    public static func getTransferRecommendations(
        picks: [FPLPick],
        allScores: [PlayerScore],
        bank: Int,
        maxCount: Int = 5
    ) -> [TransferRecommendation] {
        let myPlayerIds = Set(picks.map(\.element))
        var myTeamCounts: [Int: Int] = [:]
        
        let myScores = allScores.filter { myPlayerIds.contains($0.player.id) }
        for s in myScores {
            myTeamCounts[s.player.team, default: 0] += 1
        }
        
        var results: [TransferRecommendation] = []
        var seenOutIds = Set<Int>()
        var seenInIds = Set<Int>()
        
        // 1. Evaluate worst players across all positions (DEF, MID, FWD, GKP)
        for positionType in [2, 3, 4, 1] {
            let positionPlayers = myScores.filter { $0.player.elementType == positionType }
                .sorted(by: { $0.compositeScore < $1.compositeScore })
            
            for playerOut in positionPlayers {
                guard !seenOutIds.contains(playerOut.player.id) else { continue }
                
                let effectiveBudget = playerOut.player.nowCost + max(0, bank)
                let candidates = allScores.filter { s in
                    guard !myPlayerIds.contains(s.player.id) && !seenInIds.contains(s.player.id) else { return false }
                    guard s.player.elementType == positionType else { return false }
                    guard s.player.nowCost <= effectiveBudget else { return false }
                    guard s.player.status == "a" else { return false }
                    
                    let count = myTeamCounts[s.player.team, default: 0]
                    let effectiveCount = (s.player.team == playerOut.player.team) ? count - 1 : count
                    return effectiveCount < 3
                }
                
                guard let bestIn = candidates.first else { continue }
                let uplift = bestIn.compositeScore - playerOut.compositeScore
                guard uplift > 3.0 else { continue }
                
                let costDelta = playerOut.player.nowCost - bestIn.player.nowCost
                var reason = ""
                if playerOut.availabilityRisk != .available {
                    reason += "\(playerOut.player.webName) is \(playerOut.availabilityRisk.rawValue). "
                }
                if bestIn.xGRegressionState == .dueForExplosion {
                    reason += "\(bestIn.player.webName)'s cumulative xG is above their current goal total. "
                }
                if bestIn.fixtureScore > playerOut.fixtureScore + 15 {
                    reason += "\(bestIn.player.webName) has significantly better upcoming fixtures. "
                }
                if reason.isEmpty {
                    reason = "+\(String(format: "%.1f", uplift)) Fotty rating difference. \(bestIn.player.webName) costs \(bestIn.player.formattedCost)."
                }
                
                seenOutIds.insert(playerOut.player.id)
                seenInIds.insert(bestIn.player.id)
                
                results.append(TransferRecommendation(
                    playerOut: playerOut,
                    playerIn: bestIn,
                    scoreUplift: (uplift * 10).rounded() / 10.0,
                    costDelta: costDelta,
                    reason: reason.trimmingCharacters(in: .whitespaces)
                ))
                break // Found best upgrade for this position slot, move to next
            }
        }
        
        return Array(results.sorted(by: { $0.scoreUplift > $1.scoreUplift }).prefix(max(0, maxCount)))
    }
    
    // MARK: - Captain Recommendations
    
    public static func getCaptainRecommendations(
        picks: [FPLPick],
        allScores: [PlayerScore]
    ) -> [CaptainRecommendation] {
        let startingXI = Set(picks.filter { $0.position <= 11 }.map(\.element))
        let myCandidates = allScores.filter { startingXI.contains($0.player.id) }
            .sorted(by: { $0.compositeScore > $1.compositeScore })
        
        return myCandidates.prefix(5).enumerated().map { index, candidate in
            let ppg = Double(candidate.player.pointsPerGame) ?? 0.0
            let form = Double(candidate.player.form) ?? 0.0
            let fallback = (ppg * 0.55 + form * 0.45)
                * (candidate.fixtureScore > 70 ? 1.15 : (candidate.fixtureScore < 35 ? 0.85 : 1.0))
            let expPts = ((candidate.player.officialExpectedPointsNext ?? fallback) * 10).rounded() / 10.0
            
            let ownership = Double(candidate.player.selectedByPercent) ?? 0.0
            var reason = ""
            if index == 0 {
                reason = candidate.player.officialExpectedPointsNext == nil
                    ? "Top Fotty-modeled captain candidate. "
                    : "Top overall Fotty rating; the points estimate comes from FPL. "
                if candidate.fixtureScore > 70 { reason += "Favorable fixture ahead. " }
                if candidate.xGRegressionState == .dueForExplosion { reason += "Cumulative xG is above goals scored. " }
            } else {
                reason = "\(candidate.player.positionName) pick. Selected by \(Int(ownership))% of all managers."
            }
            
            return CaptainRecommendation(
                player: candidate,
                expectedPoints: expPts,
                selectionPercent: ownership,
                reason: reason.trimmingCharacters(in: .whitespaces)
            )
        }
    }
    
    // MARK: - Price Change Radar (Target Threshold)
    
    public static func getPriceAlerts(allScores: [PlayerScore]) -> [PriceChangeAlert] {
        allScores.compactMap { score in
            let player = score.player
            guard player.priceChangeCalibrating != true,
                  let projection = player.priceChangeProjections?.min(by: { $0.offset < $1.offset }),
                  projection.likelihood != 0 else { return nil }
            let netTransfers = player.transfersInEvent - player.transfersOutEvent
            let projected = projection.projectedPercentValue
            let likelihood = projection.likelihood
            return PriceChangeAlert(
                player: player,
                team: score.team,
                isRising: likelihood > 0,
                netTransfers: netTransfers,
                thresholdPercent: min(100, Int(abs(projected).rounded())),
                officialProjectedPercent: projected,
                officialLikelihood: likelihood,
                projectionOffset: projection.offset,
                isCalibrating: player.priceChangeCalibrating ?? false,
                reasoning: "Official FPL price projection \(String(format: "%.1f", projected))% with likelihood index \(likelihood) for offset \(projection.offset). This is guidance, not a guaranteed price change."
            )
        }.sorted { abs($0.officialLikelihood) > abs($1.officialLikelihood) }
    }
    
    // MARK: - Mini-League Rival Gap Analyzer
    
    public static func analyzeRivalGap(
        myEntry: FPLLeagueStandingEntry,
        rivalEntry: FPLLeagueStandingEntry,
        myPicks: [FPLPick],
        rivalPicks: [FPLPick],
        allScores: [PlayerScore],
        gameweek: Int = 0,
        phase: FPLGameweekPhase = .unavailable,
        eventLive: FPLEventLiveResponse? = nil,
        fixtures: [FPLFixture] = []
    ) -> RivalGapAnalysis {
        let myIds = Set(myPicks.map(\.element))
        let rivalIds = Set(rivalPicks.map(\.element))
        
        let diffMyIds = myIds.subtracting(rivalIds)
        let diffRivalIds = rivalIds.subtracting(myIds)
        let sharedIds = myIds.intersection(rivalIds)
        let playerByID = Dictionary(uniqueKeysWithValues: allScores.map { ($0.player.id, $0.player.webName) })
        let myCaptainName = myPicks.first(where: \.isCaptain).flatMap { playerByID[$0.element] }
        let rivalCaptainName = rivalPicks.first(where: \.isCaptain).flatMap { playerByID[$0.element] }
        
        let myDiffScores = allScores.filter { diffMyIds.contains($0.player.id) }
        let rivalThreatScores = allScores.filter { diffRivalIds.contains($0.player.id) }
        let sharedScores = allScores.filter { sharedIds.contains($0.player.id) }
        let scoresByID = Dictionary(uniqueKeysWithValues: allScores.map { ($0.player.id, $0) })
        let liveByID = Dictionary(uniqueKeysWithValues: (eventLive?.elements ?? []).map { ($0.id, $0.stats) })

        func activePicks(_ picks: [FPLPick]) -> [FPLPick] {
            picks.filter { $0.position <= 11 || $0.multiplier > 0 }
        }

        func hasFixtureRemaining(playerID: Int) -> Bool {
            guard gameweek > 0, let player = scoresByID[playerID]?.player else { return false }
            return fixtures.contains {
                $0.event == gameweek
                    && !$0.finished
                    && ($0.teamH == player.team || $0.teamA == player.team)
            }
        }

        func remainingCount(_ picks: [FPLPick]) -> Int {
            activePicks(picks).filter { hasFixtureRemaining(playerID: $0.element) }.count
        }

        func uniqueLivePoints(_ picks: [FPLPick], uniqueIDs: Set<Int>) -> Int {
            activePicks(picks).reduce(0) { total, pick in
                guard uniqueIDs.contains(pick.element), let stats = liveByID[pick.element] else { return total }
                return total + stats.totalPoints * max(0, pick.multiplier)
            }
        }
        
        let deficit = rivalEntry.total - myEntry.total
        
        let mode: RivalGapAnalysis.StrategyMode
        let advice: String
        
        if deficit > 30 {
            mode = .catchUpMode
            advice = "You trail by \(deficit) points. Compare high-upside unique players, but only take extra risk when the modeled upside justifies the downside and any transfer cost."
        } else if deficit < -30 {
            mode = .protectionMode
            advice = "You lead by \(abs(deficit)) points. Avoid unnecessary variance and identify which rival-owned players can materially reduce the gap."
        } else {
            mode = .neckAndNeck
            advice = "The gap is \(abs(deficit)) points. Let squad quality and the transfer horizon drive the move rather than forcing a differential."
        }
        
        return RivalGapAnalysis(
            rivalName: "\(rivalEntry.entryName) (\(rivalEntry.managerName))",
            gameweek: gameweek,
            phase: phase,
            myRank: myEntry.rank,
            rivalRank: rivalEntry.rank,
            myPoints: myEntry.total,
            rivalPoints: rivalEntry.total,
            pointDeficit: deficit,
            myGameweekPoints: myEntry.eventTotal,
            rivalGameweekPoints: rivalEntry.eventTotal,
            gameweekDeficit: rivalEntry.eventTotal - myEntry.eventTotal,
            strategyMode: mode,
            myDifferentials: myDiffScores,
            rivalThreats: rivalThreatScores,
            sharedPlayers: sharedScores,
            myCaptainName: myCaptainName,
            rivalCaptainName: rivalCaptainName,
            myPlayersRemaining: remainingCount(myPicks),
            rivalPlayersRemaining: remainingCount(rivalPicks),
            myUniqueLivePoints: uniqueLivePoints(myPicks, uniqueIDs: diffMyIds),
            rivalUniqueLivePoints: uniqueLivePoints(rivalPicks, uniqueIDs: diffRivalIds),
            hasOfficialLiveSnapshot: eventLive != nil,
            tacticalAdvice: advice
        )
    }
    
    // MARK: - Fixture Grid
    
    public static func buildFixtureGrid(
        teams: [FPLTeam],
        fixtures: [FPLFixture],
        events: [FPLGameweek],
        count: Int = 5
    ) -> [TeamFixtureRow] {
        let currentGwEvent = events.first(where: { $0.isCurrent })
        let nextGwEvent = events.first(where: { $0.isNext })
        
        let startGw: Int
        if let cur = currentGwEvent {
            startGw = cur.finished ? (nextGwEvent?.id ?? (cur.id + 1)) : cur.id
        } else {
            startGw = nextGwEvent?.id ?? 1
        }
        let gws = Array(startGw ..< startGw + count)
        
        return teams.map { team in
            let teamUpcoming = getTeamUpcomingFixtures(teamId: team.id, fixtures: fixtures, teams: teams, startGw: startGw, count: count)
            let fixtureCells = gws.map { gw in
                teamUpcoming.first(where: { $0.gameweek == gw })
            }
            
            let diffs = fixtureCells.compactMap { $0?.difficulty }
            let avgDiff = diffs.isEmpty ? 3.0 : (Double(diffs.reduce(0, +)) / Double(diffs.count))
            
            return TeamFixtureRow(
                team: team,
                fixtures: fixtureCells,
                avgDifficulty: (avgDiff * 10).rounded() / 10.0
            )
        }.sorted(by: { $0.avgDifficulty < $1.avgDifficulty })
    }
    
    // MARK: - Helper
    
    private static func getTeamUpcomingFixtures(
        teamId: Int,
        fixtures: [FPLFixture],
        teams: [FPLTeam],
        startGw: Int,
        count: Int
    ) -> [UpcomingFixture] {
        var results: [UpcomingFixture] = []
        for f in fixtures {
            guard let event = f.event, event >= startGw, event < startGw + count, !f.finished else { continue }
            if f.teamH == teamId {
                if let opp = teams.first(where: { $0.id == f.teamA }) {
                    results.append(UpcomingFixture(gameweek: event, opponent: opp, isHome: true, difficulty: f.teamHDifficulty))
                }
            } else if f.teamA == teamId {
                if let opp = teams.first(where: { $0.id == f.teamH }) {
                    results.append(UpcomingFixture(gameweek: event, opponent: opp, isHome: false, difficulty: f.teamADifficulty))
                }
            }
        }
        return results.sorted(by: { $0.gameweek < $1.gameweek })
    }
}
