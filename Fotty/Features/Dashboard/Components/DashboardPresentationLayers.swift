import SwiftUI
import SwiftData

struct DashboardPresentationLayers: ViewModifier {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Binding var selectedHighlightsMatch: FootballMatch?
    @Binding var showPlayer: Bool
    
    let streamEvent: AnalyticalDataEngine.EventReference?
    let streamSessions: [StreamSession]
    
    let liveScoreService: LiveScoreService
    
    func body(content: Content) -> some View {
        content
            .onChange(of: showPlayer) { _, show in
                guard show else { return }
                if let event = streamEvent { viewing.open(event: event, sessions: streamSessions) }
                showPlayer = false
            }
            .fullScreenCover(item: $selectedHighlightsMatch) { match in
                NavigationStack {
                    MatchHubView(fixtureId: String(match.id), showModalDismissButton: true)
                        .environment(liveScoreService)
                }
            }
    }
}

extension View {
    func dashboardPresentationLayers(
        selectedHighlightsMatch: Binding<FootballMatch?>,
        showPlayer: Binding<Bool>,
        streamEvent: AnalyticalDataEngine.EventReference?,
        streamSessions: [StreamSession],
        liveScoreService: LiveScoreService
    ) -> some View {
        self.modifier(DashboardPresentationLayers(
            selectedHighlightsMatch: selectedHighlightsMatch,
            showPlayer: showPlayer,
            streamEvent: streamEvent,
            streamSessions: streamSessions,
            liveScoreService: liveScoreService
        ))
    }
}
