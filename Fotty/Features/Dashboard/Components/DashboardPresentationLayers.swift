import SwiftUI
import SwiftData

struct DashboardPresentationLayers: ViewModifier {
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Binding var selectedHighlightsMatch: FootballMatch?
    @Binding var showPlayer: Bool
    @Binding var showMultiPlayer: Bool
    
    let streamEvent: AnalyticalDataEngine.EventReference?
    let streamSessions: [StreamSession]
    let multiViewSlots: [MultiLiveSlot]
    
    let liveScoreService: LiveScoreService
    let onMultiPlaybackUnavailable: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: showPlayer) { _, show in
                guard show else { return }
                if let event = streamEvent { viewing.open(event: event, sessions: streamSessions) }
                showPlayer = false
            }
            .onChange(of: showMultiPlayer) { _, show in
                guard show else { return }
                viewing.openMulti(slots: multiViewSlots)
                showMultiPlayer = false
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
        showMultiPlayer: Binding<Bool>,
        streamEvent: AnalyticalDataEngine.EventReference?,
        streamSessions: [StreamSession],
        multiViewSlots: [MultiLiveSlot],
        liveScoreService: LiveScoreService,
        onMultiPlaybackUnavailable: @escaping (String) -> Void
    ) -> some View {
        self.modifier(DashboardPresentationLayers(
            selectedHighlightsMatch: selectedHighlightsMatch,
            showPlayer: showPlayer,
            showMultiPlayer: showMultiPlayer,
            streamEvent: streamEvent,
            streamSessions: streamSessions,
            multiViewSlots: multiViewSlots,
            liveScoreService: liveScoreService,
            onMultiPlaybackUnavailable: onMultiPlaybackUnavailable
        ))
    }
}
