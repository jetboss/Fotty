import Foundation
import MediaPlayer
import UIKit
import os.log

private let nowPlayingCommandLogger = Logger(
    subsystem: "com.jelani.Fotty",
    category: "PlaybackLifecycle"
)

@MainActor
public final class NowPlayingManager {
    public static let shared = NowPlayingManager()
    
    private var isConfigured = false
    // Remote commands and metadata belong to the audible retained session.
    // Retiring an older pane must not clear its replacement's system controls.
    private(set) var remoteCommandOwnerID: UUID?
    private var playCommandHandler: (() -> Void)?
    private var pauseCommandHandler: (() -> Void)?
    private var toggleCommandHandler: (() -> Void)?
    
    private init() {}
    
    public func configureRemoteCommands(
        ownerID: UUID,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) {
        remoteCommandOwnerID = ownerID
        self.playCommandHandler = onPlay
        self.pauseCommandHandler = onPause
        self.toggleCommandHandler = onToggle

        setRemoteCommandsEnabled(true)
        
        guard !isConfigured else { return }
        isConfigured = true
        
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            nowPlayingCommandLogger.info("remote_command=play")
            self?.playCommandHandler?()
            return .success
        }
        
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            nowPlayingCommandLogger.info("remote_command=pause")
            self?.pauseCommandHandler?()
            return .success
        }
        
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            nowPlayingCommandLogger.info("remote_command=toggle")
            self?.toggleCommandHandler?()
            return .success
        }
    }
    
    public func updateNowPlaying(
        ownerID: UUID,
        title: String,
        subtitle: String,
        isPlaying: Bool,
        posterURL: URL? = nil
    ) {
        guard remoteCommandOwnerID == ownerID else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        if let appIcon = UIImage(named: "AppIcon") ?? UIImage(systemName: "play.tv.fill") {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 300, height: 300)) { _ in
                appIcon
            }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    public func clearNowPlaying(ownerID: UUID) {
        guard remoteCommandOwnerID == ownerID else { return }
        remoteCommandOwnerID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        playCommandHandler = nil
        pauseCommandHandler = nil
        toggleCommandHandler = nil
        setRemoteCommandsEnabled(false)
    }

    func isOwned(by ownerID: UUID) -> Bool {
        remoteCommandOwnerID == ownerID
    }

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
    }
}
