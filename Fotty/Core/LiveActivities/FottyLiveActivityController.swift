import Foundation
import os.log

enum FottyLiveActivityPolicy {
    /// A Live Activity is only honest when playback can continue outside Fotty.
    /// Web embeds cannot provide reliable background progress or score updates.
    static func shouldPresent(
        isWebEmbed: Bool,
        isPlaying: Bool,
        isLoading: Bool,
        hasError: Bool,
        supportsPictureInPicture: Bool,
        hasActivePictureInPicture: Bool,
        hasUsefulMatchState: Bool = true
    ) -> Bool {
        guard !isWebEmbed,
              isPlaying,
              !isLoading,
              !hasError,
              supportsPictureInPicture,
              hasUsefulMatchState else {
            return false
        }
        // Capability alone is not enough. Starting an Activity while ordinary
        // foreground playback is visible leaves a redundant system surface
        // behind if the process is later force-terminated. Present only after
        // AVKit confirms that PiP/background continuity is actually active.
        return hasActivePictureInPicture
    }
}

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
import UIKit

@MainActor
final class FottyLiveActivityController {
    static let shared = FottyLiveActivityController()

    private let logger = Logger(subsystem: "com.jelani.Fotty", category: "LiveActivity")
    private var activity: Activity<FottyMatchActivityAttributes>?

    private init() {}

    func startOrUpdate(
        event: AnalyticalDataEngine.EventReference,
        source: StreamSource?,
        matchStatus: String,
        scoreText: String?
    ) {
        guard #available(iOS 16.2, *),
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let state = contentState(
            source: source,
            matchStatus: matchStatus,
            scoreText: scoreText
        )
        let attributes = FottyMatchActivityAttributes(
            matchID: event.id,
            homeTeam: event.homeName,
            awayTeam: event.awayName,
            competition: event.categoryDisplayName
        )

        if let active = activeActivity(for: event.id) {
            activity = active
            Task {
                await active.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60)))
            }
            return
        }

        endActivities(
            Activity<FottyMatchActivityAttributes>.activities,
            phase: "Another match opened"
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60)),
                pushType: nil
            )
        } catch {
            logger.debug("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func end(event: AnalyticalDataEngine.EventReference, scoreText: String?) {
        guard #available(iOS 16.2, *) else { return }
        let matchingActivities = Activity<FottyMatchActivityAttributes>.activities.filter {
            $0.attributes.matchID == event.id
        }
        guard !matchingActivities.isEmpty else { return }
        activity = nil
        endActivities(matchingActivities, phase: "Playback closed", scoreText: scoreText)
    }

    /// A cold app launch cannot have a surviving local playback session. Clear
    /// anything ActivityKit retained after an earlier process termination.
    func endAllOrphanedActivities() {
        guard #available(iOS 16.2, *) else { return }
        activity = nil
        endActivities(
            Activity<FottyMatchActivityAttributes>.activities,
            phase: "Playback ended"
        )
    }

    private func endActivities(
        _ activities: [Activity<FottyMatchActivityAttributes>],
        phase: String,
        scoreText: String? = nil
    ) {
        guard !activities.isEmpty else { return }
        let finalState = FottyMatchActivityAttributes.ContentState(
            phase: phase,
            playbackState: "Closed",
            scoreText: sanitized(scoreText, fallback: "—"),
            providerName: "Fotty",
            isPlaying: false,
            isP2P: false,
            updatedAt: Date()
        )
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "End Fotty Live Activity")
        Task { @MainActor in
            for active in activities {
                await active.end(
                    ActivityContent(state: finalState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            }
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
    }

    private func activeActivity(for matchID: String) -> Activity<FottyMatchActivityAttributes>? {
        if let activity, activity.attributes.matchID == matchID {
            return activity
        }
        return Activity<FottyMatchActivityAttributes>.activities.first {
            $0.attributes.matchID == matchID
        }
    }

    private func contentState(
        source: StreamSource?,
        matchStatus: String,
        scoreText: String?
    ) -> FottyMatchActivityAttributes.ContentState {
        FottyMatchActivityAttributes.ContentState(
            phase: sanitized(matchStatus, fallback: "Match in progress"),
            playbackState: "Watching",
            scoreText: sanitized(scoreText, fallback: "—"),
            providerName: sanitized(source?.provider, fallback: "Fotty"),
            isPlaying: true,
            isP2P: isP2PSource(source),
            updatedAt: Date()
        )
    }

    private func isP2PSource(_ source: StreamSource?) -> Bool {
        guard let source else { return false }
        let url = source.url.absoluteString.lowercased()
        let provider = source.provider.lowercased()
        return provider.contains("p2p")
            || url.contains("acestream")
            || url.contains("p2p.pixel-invoice.com")
            || source.headers["X-Fotty-P2P"] == "true"
    }

    private func sanitized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(48))
    }
}
#else
@MainActor
final class FottyLiveActivityController {
    static let shared = FottyLiveActivityController()
    private init() {}

    func startOrUpdate(
        event: AnalyticalDataEngine.EventReference,
        source: StreamSource?,
        matchStatus: String,
        scoreText: String?
    ) {}

    func end(event: AnalyticalDataEngine.EventReference, scoreText: String?) {}
    func endAllOrphanedActivities() {}
}
#endif
