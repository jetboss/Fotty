import SwiftUI
import SwiftData
import AVFoundation
import UIKit

enum MediaAudioSession {
    private static var observerTokens: [NSObjectProtocol] = []
    private static var didInstallLifecycleObservers = false
    
    static func configureForPlaybackIfNeeded() {
        let session = AVAudioSession.sharedInstance()

        do {
            // The playback category already supports AirPlay and Bluetooth A2DP.
            // Passing those route options here produces AVAudioSession error -50 on
            // some iPadOS versions because they are intended for other categories.
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
        } catch {
            print("[MediaAudioSession] Failed to set playback category: \(error.localizedDescription)")
        }
    }

    static func installLifecycleObserversIfNeeded() {
        if Thread.isMainThread {
            installLifecycleObserversOnMainThreadIfNeeded()
        } else {
            DispatchQueue.main.async {
                installLifecycleObserversOnMainThreadIfNeeded()
            }
        }
    }
    
    private static func installLifecycleObserversOnMainThreadIfNeeded() {
        guard !didInstallLifecycleObservers else { return }
        didInstallLifecycleObservers = true
        
        let center = NotificationCenter.default
        
        observerTokens.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                configureForPlaybackIfNeeded()
            }
        )
        
        observerTokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { _ in
                configureForPlaybackIfNeeded()
            }
        )
        
        observerTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                configureForPlaybackIfNeeded()
            }
        )
        
        observerTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let interruptionType = AVAudioSession.InterruptionType(rawValue: rawType),
                      interruptionType == .ended else {
                    return
                }
                configureForPlaybackIfNeeded()
            }
        )
    }
}

@main
struct FottyApp: App {
    @AppStorage(FottyAppearance.storageKey) private var appearance = FottyAppearance.dark.rawValue
    @UIApplicationDelegateAdaptor(FottyAppDelegate.self) private var appDelegate
    @StateObject private var socialCloudStore = SocialCloudStore()
    @State private var liveScoreService = LiveScoreService.shared
    @State private var didConfigureMediaAudioSession = false
    @State private var didClearOrphanedLiveActivities = false
    
    private let sharedModelContainer: ModelContainer = LocalDataStore.shared.container

    #if DEBUG
    private enum UITestSurface: String {
        case matchCenter = "match-center"
        case player
    }

    private static var uiTestSurface: UITestSurface? {
        guard ProcessInfo.processInfo.environment["FOTTY_SURFACE_UI_TESTING"] == "1" else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        let key = "--fotty-ui-test-surface"
        guard let keyIndex = arguments.firstIndex(of: key),
              arguments.indices.contains(keyIndex + 1) else {
            return nil
        }
        return UITestSurface(rawValue: arguments[keyIndex + 1].lowercased())
    }

    @MainActor
    private static var uiTestEvent: AnalyticalDataEngine.EventReference {
        AnalyticalDataEngine.EventReference(
            id: "ui-test-chelsea-fulham",
            title: "Chelsea vs Fulham",
            category: "football",
            date: Int64(Date().addingTimeInterval(-20 * 60).timeIntervalSince1970),
            poster: nil,
            popular: true,
            teams: NexusATeams(
                home: NexusATeam(name: "Chelsea", badge: nil),
                away: NexusATeam(name: "Fulham", badge: nil)
            ),
            sources: [NexusASource(source: "admin", id: "ui-test-source")]
        )
    }
    #endif

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        switch Self.uiTestSurface {
        case .matchCenter:
            NavigationStack {
                MatchHubView(testEvent: Self.uiTestEvent, showModalDismissButton: true)
            }
        case .player:
            LivePlayerView(event: Self.uiTestEvent, providedSessions: [])
        case nil:
            MainTabView()
        }
        #else
        MainTabView()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            rootContent
                .preferredColorScheme(FottyAppearance.saved(appearance).colorScheme)
                .tint(FottyTheme.accentText)
                .environmentObject(socialCloudStore)
                .environment(liveScoreService)
                .onAppear {
                    if !didClearOrphanedLiveActivities {
                        didClearOrphanedLiveActivities = true
                        FottyLiveActivityController.shared.endAllOrphanedActivities()
                    }
                    guard !didConfigureMediaAudioSession else { return }
                    didConfigureMediaAudioSession = true
                    MediaAudioSession.installLifecycleObserversIfNeeded()
                    MediaAudioSession.configureForPlaybackIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
