import Foundation

public struct PressConferenceReport: Identifiable, Sendable {
    public var id: String { "\(team)-\(player)" }
    public let manager: String
    public let team: String
    public let player: String
    public let keyQuotes: String
    public let injuryStatus: String
    public let startProbability: Int // 0 - 100%
    public let recommendedSubAction: String
}

public enum FPLPressConferenceService {
    
    /// Maps the current FPL element status/news fields into availability flags.
    /// It does not represent press-conference reporting or medical confirmation.
    public static func getLatestReports(scores: [PlayerScore]) -> [PressConferenceReport] {
        // Find players with official news, flags, or injury notes
        let flaggedPlayers = scores.filter { score in
            !score.player.news.isEmpty ||
            score.availabilityRisk != .available ||
            score.player.status != "a"
        }
        .sorted { left, right in
            // Prioritize high-scoring/high-ownership players
            left.compositeScore > right.compositeScore
        }
        
        if flaggedPlayers.isEmpty { return [] }
        
        return flaggedPlayers.prefix(6).map { score in
            let chance = score.player.chanceOfPlayingThisRound ?? (score.player.status == "a" ? 100 : (score.player.status == "d" ? 50 : 0))
            let statusLabel: String
            let action: String
            
            if chance == 0 || score.player.status == "i" {
                statusLabel = "Ruled Out (0%)"
                action = "Transfer out or bench immediately"
            } else if chance <= 50 || score.player.status == "d" {
                statusLabel = "Major Doubt (\(chance)%)"
                action = "Ensure strong first bench substitute is ready"
            } else if chance < 100 {
                statusLabel = "Minor Doubt (\(chance)%)"
                action = "Monitor latest team sheet; keep active vice-captain"
            } else {
                statusLabel = "Fit (100%)"
                action = "Available for selection"
            }
            
            let newsText = score.player.news.isEmpty ? "FPL currently marks this player as unavailable or doubtful without additional detail." : score.player.news
            
            return PressConferenceReport(
                manager: "FPL availability data",
                team: score.team.shortName,
                player: score.player.webName,
                keyQuotes: newsText,
                injuryStatus: statusLabel,
                startProbability: chance,
                recommendedSubAction: action
            )
        }
    }
}
