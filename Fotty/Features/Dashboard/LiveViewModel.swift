import SwiftUI

// MARK: - Live View Model

@MainActor
@Observable
class LiveViewModel {
    var events: [AnalyticalDataEngine.EventReference] = []
    var isLoading = true
    var error: String?
    
    var sportsTabs: [String] {
        let unique = Set(events.map(\.normalizedCategory))
        let preferredOrder = ["football", "basketball", "baseball", "hockey", "fight"]

        // Keep Football pinned so league tabs remain available even when
        // the current feed doesn't include football events.
        var ordered = ["football"]
        ordered.append(contentsOf: preferredOrder.filter { $0 != "football" && unique.contains($0) })

        let remaining = unique.subtracting(Set(ordered)).sorted { lhs, rhs in
            AnalyticalDataEngine.categoryDisplayName(for: lhs) < AnalyticalDataEngine.categoryDisplayName(for: rhs)
        }
        ordered.append(contentsOf: remaining)
        return ordered
    }
    
    // Legacy alias used by parts of the Live UI.
    var categories: [String] {
        sportsTabs
    }
    
    func loadAll() async {
        isLoading = true
        error = nil
        
        // Retry up to 3 times with backoff — upstream event providers can be slow on first hit.
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                let fetched = try await AnalyticalDataEngine.allLiveEvents()
                if !fetched.isEmpty || attempt == maxRetries {
                    let nearTerm = fetched.filter { $0.passesNearTermLiveListWindow() }
                    events = sortEvents(nearTerm)
                    isLoading = false
                    error = nil
                    return
                }
                // Empty result — retry after a short delay
                print("[LiveViewModel] Attempt \(attempt): got 0 events, retrying in 5s...")
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return
                }
                if attempt == maxRetries {
                    self.error = error.localizedDescription
                    isLoading = false
                    return
                }
                print("[LiveViewModel] Attempt \(attempt) failed: \(error.localizedDescription), retrying in 5s...")
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            }
        }
    }
    
    /// Auto-refresh events every 90 seconds. 
    /// Should be called from a .task block in the view to respect lifecycle.
    func startAutoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            
            do {
                let fetched = try await AnalyticalDataEngine.allLiveEvents()
                // Update events without setting isLoading to avoid jarring UI flashes
                let nearTerm = fetched.filter { $0.passesNearTermLiveListWindow() }
                self.events = sortEvents(nearTerm)
                print("[LiveViewModel] Auto-refreshed events at \(Date())")
            } catch {
                print("[LiveViewModel] Auto-refresh failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func sortEvents(_ input: [AnalyticalDataEngine.EventReference]) -> [AnalyticalDataEngine.EventReference] {
        input.sorted { lhs, rhs in
            let lhsPopular = lhs.popular ?? false
            let rhsPopular = rhs.popular ?? false
            if lhsPopular != rhsPopular {
                return lhsPopular && !rhsPopular
            }
            
            let lhsDate = lhs.kickoffDate ?? .distantFuture
            let rhsDate = rhs.kickoffDate ?? .distantFuture
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            
            return (lhs.title ?? "") < (rhs.title ?? "")
        }
    }

}
