import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

struct FottyMatchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var playbackState: String
        var scoreText: String
        var providerName: String
        var isPlaying: Bool
        var isP2P: Bool
        var updatedAt: Date
    }

    var matchID: String
    var homeTeam: String
    var awayTeam: String
    var competition: String
}
#endif
