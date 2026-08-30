import Foundation

protocol LiveStreamingProvider {
    var name: String { get }
    var priority: Int { get }
    
    func findStreams(homeTeam: String, awayTeam: String) async throws -> [StreamSource]
    func fetchLiveEvents() async throws -> [EventReference]
}

enum LiveStreamingError: Error {
    case matchNotFound
    case noSourcesAvailable
}
