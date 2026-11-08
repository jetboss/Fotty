import Foundation

protocol LiveStreamingProvider {
    var name: String { get }
    var priority: Int { get }
    
    func findStreams(homeTeam: String, awayTeam: String) async throws -> [StreamSource]
    func fetchLiveEvents() async throws -> [EventReference]
    @MainActor func fetchCatalogSnapshot() async throws -> LiveCatalogSnapshot
}

extension LiveStreamingProvider {
    @MainActor func fetchCatalogSnapshot() async throws -> LiveCatalogSnapshot {
        let events = try await fetchLiveEvents()
        return try LiveCatalogSnapshot.combine([.init(source: name, events: events)])
    }
}

enum LiveStreamingError: Error {
    case matchNotFound
    case noSourcesAvailable
}
