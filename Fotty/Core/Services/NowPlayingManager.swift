import Foundation
import MediaPlayer
import UIKit

@MainActor
public final class NowPlayingManager {
    public static let shared = NowPlayingManager()
    
    private var isConfigured = false
    private var playCommandHandler: (() -> Void)?
    private var pauseCommandHandler: (() -> Void)?
    private var toggleCommandHandler: (() -> Void)?
    
    private init() {}
    
    public func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.playCommandHandler = onPlay
        self.pauseCommandHandler = onPause
        self.toggleCommandHandler = onToggle

        setRemoteCommandsEnabled(true)
        
        guard !isConfigured else { return }
        isConfigured = true
        
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.playCommandHandler?()
            return .success
        }
        
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pauseCommandHandler?()
            return .success
        }
        
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggleCommandHandler?()
            return .success
        }
    }
    
    public func updateNowPlaying(
        title: String,
        subtitle: String,
        isPlaying: Bool,
        posterURL: URL? = nil
    ) {
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
    
    public func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        playCommandHandler = nil
        pauseCommandHandler = nil
        toggleCommandHandler = nil
        setRemoteCommandsEnabled(false)
    }

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
    }
}
