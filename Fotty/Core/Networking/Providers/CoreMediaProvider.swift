import Foundation

final class CoreMediaProvider: LiveStreamingProvider {
    let name = StringObfuscator.decode([0x17, 0x14, 0x16, 0x5, 0xA, 0x2C, 0xA, 0x32]) // "NexusA"
    let priority = 10
    
    func findStreams(homeTeam: String, awayTeam: String) async throws -> [StreamSource] {
        return try await AnalyticalDataEngine.findStreams_NexusAImplementation(
            homeTeam: homeTeam,
            awayTeam: awayTeam
        )
    }
    
    func fetchLiveEvents() async throws -> [EventReference] {
        // NexusA specific fetch logic is already in AnalyticalDataEngine
        return try await AnalyticalDataEngine.fetchLiveEvents_NexusAImplementation()
    }
}
