import Foundation

/// Background and foreground decisions for the player (player shrink slice 5,
/// 9 Nov 2026). These rules were inline in `LivePlayerViewModel`; they are
/// unchanged and now testable without a player, scene or AVKit.
///
/// The orchestration that applies them (pausing, audio preparation, task
/// cancellation, transitions) stays in the view model: it touches about 107
/// of its members, 55 of them private, so a separate controller would need a
/// host interface nearly as wide as the view model itself.
enum PlaybackLifecyclePolicy {
    /// AVKit may report PiP after the scene backgrounds. A recent explicit PiP
    /// request keeps a foreground native player alive for this long.
    static let pictureInPictureRequestWindow: TimeInterval = 10

    struct PictureInPictureInputs: Equatable {
        var allowsViewingPiP: Bool
        var isPictureInPictureActive: Bool
        var isPictureInPictureAvailable: Bool
        var isUsingWebEmbed: Bool
        var isPlaying: Bool
        var hasError: Bool
        var isAppBackgrounded: Bool
        var hasCurrentItem: Bool
        /// Seconds since the last explicit PiP request, if any.
        var secondsSincePictureInPictureRequest: TimeInterval?
    }

    /// Whether native playback should stay alive for Picture in Picture rather
    /// than pause when the app leaves the foreground.
    static func keepsPlaybackAliveForPictureInPicture(_ inputs: PictureInPictureInputs) -> Bool {
        guard inputs.allowsViewingPiP else { return false }
        if inputs.isPictureInPictureActive { return true }
        guard inputs.isPictureInPictureAvailable, !inputs.isUsingWebEmbed,
              inputs.isPlaying, !inputs.hasError else { return false }
        // The scene can reach background before AVKit's PiP delegate callback.
        // Once a native player is PiP-capable, let AVKit own that transition
        // instead of pausing the underlying player during this callback race.
        if inputs.isAppBackgrounded { return inputs.hasCurrentItem }
        guard let age = inputs.secondsSincePictureInPictureRequest else { return false }
        return age < pictureInPictureRequestWindow
    }

    enum WebBackgroundAction: Equatable {
        /// WebKit PiP owns playback; neither suspend nor resume later.
        case keepPictureInPicture
        /// Playing: give a late WebKit PiP event a short grace, then suspend.
        case suspendAfterGrace
        /// Not playing: suspend the document now.
        case suspendNow
    }

    static func webBackgroundAction(isWebPictureInPictureActive: Bool, isPlaying: Bool) -> WebBackgroundAction {
        if isWebPictureInPictureActive { return .keepPictureInPicture }
        return isPlaying ? .suspendAfterGrace : .suspendNow
    }

    /// Native playback paused for background resumes on return only if the
    /// viewer still wants playback and it was playing, loading, starting, or
    /// already marked to resume.
    static func resumesNativeAfterForeground(userWantsPlayback: Bool, alreadyMarked: Bool,
                                             isPlaying: Bool, isLoading: Bool,
                                             hasPendingNativePlay: Bool) -> Bool {
        userWantsPlayback && (alreadyMarked || isPlaying || isLoading || hasPendingNativePlay)
    }
}
