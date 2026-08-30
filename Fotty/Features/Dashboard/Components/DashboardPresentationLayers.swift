import SwiftUI
import SwiftData

struct DashboardPresentationLayers: ViewModifier {
    @Binding var selectedHighlightsMatch: FootballMatch?
    @Binding var showPlayer: Bool
    @Binding var showMultiPlayer: Bool
    
    let streamEvent: AnalyticalDataEngine.EventReference?
    let streamSessions: [StreamSession]
    let multiViewSlots: [MultiLiveSlot]
    
    let liveScoreService: LiveScoreService
    let socialCloudStore: SocialCloudStore
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showPlayer) {
                if let event = streamEvent {
                    LivePlayerView(
                        event: event,
                        providedSessions: streamSessions
                    )
                    .environment(liveScoreService)
                    .environmentObject(socialCloudStore)
                }
            }
            .fullScreenCover(isPresented: $showMultiPlayer) {
                if !multiViewSlots.isEmpty {
                    MultiLivePlayerView(slots: multiViewSlots)
                    .environment(liveScoreService)
                    .environmentObject(socialCloudStore)
                }
            }
            .fullScreenCover(item: $selectedHighlightsMatch) { match in
                NavigationStack {
                    MatchHubView(fixtureId: String(match.id), showModalDismissButton: true)
                        .environment(liveScoreService)
                        .environmentObject(socialCloudStore)
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
        socialCloudStore: SocialCloudStore
    ) -> some View {
        self.modifier(DashboardPresentationLayers(
            selectedHighlightsMatch: selectedHighlightsMatch,
            showPlayer: showPlayer,
            showMultiPlayer: showMultiPlayer,
            streamEvent: streamEvent,
            streamSessions: streamSessions,
            multiViewSlots: multiViewSlots,
            liveScoreService: liveScoreService,
            socialCloudStore: socialCloudStore
        ))
    }
}
