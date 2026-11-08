import Foundation
import AVFoundation

/// The native AVPlayer transport. It wraps the existing reviewed preparation
/// (`NativePlaybackPreparation.prepareDelivery` + `makeItem`) behind the
/// `StreamTransport` seam. The decoded-frame observation, KVO and teardown that
/// still live in `LivePlayerViewModel` migrate here in the next slices; this
/// first slice owns delivery + item construction and a minimal play/pause/stop.
@MainActor
final class NativeStreamTransport: StreamTransport {
    var kind: TransportKind { .native }

    private var player: AVPlayer?
    private var delivery: NativePlaybackPreparation.Delivery?

    func prepare(_ session: StreamSession) async throws -> PreparedPlayback {
        try Task.checkCancellation()
        let requiresRelay = session.requiresGuardedRelay == true || !session.requiredHeaders.isEmpty
        let delivery = try await NativePlaybackPreparation.prepareDelivery(
            url: session.playableURL,
            headers: session.requiredHeaders,
            cookies: [],
            requiresRelay: requiresRelay,
            originProfile: session.nativeOriginProfile,
            playlistProfile: session.nativePlaylistProfile
        )
        let item = NativePlaybackPreparation.makeItem(
            url: delivery.url,
            headers: session.requiredHeaders,
            session: session,
            evidence: session.mediaProbeEvidence
        )
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.delivery = delivery
        return PreparedPlayback(session: session, kind: .native)
    }

    func play(_ prepared: PreparedPlayback) async {
        player?.play()
    }

    func pause() async {
        player?.pause()
    }

    func stop() async {
        player?.pause()
        player = nil
        delivery?.discard()
        delivery = nil
    }
}
