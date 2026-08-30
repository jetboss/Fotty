import Foundation
import SwiftUI
import Combine

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var liveMatches: [FootballMatch] = []
    @Published var isLoading = false

    func refresh(using liveScoreService: LiveScoreService, force: Bool = false) {
        liveMatches = liveScoreService.cachedMatches.filter { $0.status.isLive }
        Task {
            isLoading = true
            await liveScoreService.refresh(force: force)
            liveMatches = liveScoreService.cachedMatches.filter { $0.status.isLive }
            isLoading = false
        }
    }
}
