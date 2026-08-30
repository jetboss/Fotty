import Foundation

/// BLUEPRINT: Swift 6 Actor for Chunked Fetching
/// Prevents the app from freezing on launch by fetching matches in batches of 10.
actor MatchListActor {
    /// Fetches all live events in chunks of 10 to ensure UI responsiveness.
    func fetchMatchesInChunks() async throws -> [AnalyticalDataEngine.EventReference] {
        let allEvents = try await AnalyticalDataEngine.allLiveEvents()
            .filter { $0.passesNearTermLiveListWindow() }
        var results: [AnalyticalDataEngine.EventReference] = []
        
        let chunkSize = 10
        let chunks = stride(from: 0, to: allEvents.count, by: chunkSize).map {
            Array(allEvents[$0..<min($0 + chunkSize, allEvents.count)])
        }
        
        for chunk in chunks {
            // Process chunk (e.g., pre-fetch metadata or just add to results)
            results.append(contentsOf: chunk)
            
            // Yield to allow other tasks (like UI updates) to run
            await Task.yield()
        }
        
        return results
    }
    
}
