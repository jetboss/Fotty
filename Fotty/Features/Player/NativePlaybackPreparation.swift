import Foundation
import AVFoundation

/// Preparation owns delivery resources, never playback intent, audio activation,
/// view presentation or permission to replace an existing player. The caller
/// must recheck its exact source/request/intent after every suspension.
@MainActor
enum NativePlaybackPreparation {
    struct Delivery {
        let url: URL
        let proxy: LocalStreamProxy?
        func discard() { proxy?.stop() }
    }

    static func prepareDelivery(
        url: URL, headers: [String: String], cookies: [HTTPCookie], requiresRelay: Bool,
        originProfile: LocalStreamProxyOriginProfile? = nil,
        playlistProfile: LocalStreamProxyPlaylistProfile? = nil
    ) async throws -> Delivery {
        try Task.checkCancellation()
        guard requiresRelay else { return Delivery(url: url, proxy: nil) }
        let proxy = LocalStreamProxy(headers: headers, cookies: cookies, selectedMediaURL: url,
                                     originProfile: originProfile, playlistProfile: playlistProfile)
        var retained = false
        defer { if !retained { proxy.stop() } }
        do { try await proxy.start() }
        catch {
            throw PlaybackPreparationFailure(error,
                reason: error is CancellationError ? .cancelled : .proxyStartup,
                relayEvidence: proxy.lastFailureEvidence)
        }
        var ready = false
        for _ in 0..<5 {
            try Task.checkCancellation()
            if await proxy.ping() { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard ready, let localURL = proxy.playbackURL() else {
            throw PlaybackPreparationFailure(ProcessorError.proxyError, reason: .proxyHealthCheck,
                                             relayEvidence: proxy.lastFailureEvidence)
        }
        retained = true
        return Delivery(url: localURL, proxy: proxy)
    }

    static func prepareDelivery(for candidate: NativeWebPlaybackCandidate) async throws -> Delivery {
        try await prepareDelivery(url: candidate.url, headers: candidate.headers, cookies: candidate.cookies,
                                  requiresRelay: !candidate.headers.isEmpty || !candidate.cookies.isEmpty)
    }

    /// A response observation improves item configuration, not source admission
    /// or codec/PiP support. It cannot mint an exceptional origin/port grant.
    static func makeItem(url: URL, headers: [String: String], session: StreamSession,
                         evidence: StreamMediaProbeEvidence?) -> AVPlayerItem {
        let observed = session.recordingMediaProbe(evidence)
        let item = AVPlayerItem(asset: AVURLAsset(url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]))
        if observed.playbackContract.container != .mp4 {
            MediaAudioSession.configureNativeLivePlaybackItem(item)
            // Live HLS: let AVFoundation size the buffer from the playlist's
            // target duration. A fixed 12 s pushes startup and the live edge
            // further behind and counts against the startup deadline.
            item.preferredForwardBufferDuration = 0
        } else {
            item.preferredForwardBufferDuration = 12
        }
        return item
    }

    static func capturedSession(from selected: StreamSession, candidate: NativeWebPlaybackCandidate,
                                evidence: StreamMediaProbeEvidence?) -> StreamSession {
        // An opaque delivery isn't automatically HLS. The current response probe
        // can classify it; otherwise retain only an explicit path declaration.
        let declared: StreamType
        switch candidate.url.pathExtension.lowercased() {
        case "mp4": declared = .mp4
        case "m3u8": declared = .hls
        default: declared = .unknown
        }
        return StreamSession(id: selected.id, matchID: selected.matchID, title: selected.title,
            playableURL: candidate.url, streamType: declared, providerName: selected.providerName,
            requiredHeaders: candidate.headers, qualityLabel: selected.qualityLabel,
            expiryTime: selected.expiryTime, leaseID: selected.leaseID, canRefresh: true,
            validationStatus: .validated, diagnosticMetadata: selected.diagnosticMetadata.merging([
                "delivery": "native_web_handoff", "manifest_result": "captured_after_decoded_web_playback",
                "referer": candidate.headers["Referer"] ?? ""
            ]) { _, captured in captured }, createdAt: selected.createdAt,
            lastRefreshAt: selected.lastRefreshAt, activePeers: selected.activePeers,
            mediaProbeEvidence: evidence, declaredPlaybackEndpoint: .directMedia)
    }
}

/// Prepared media is paused and disconnected. Only the scene's atomic pair
/// transaction may consume it after BOTH original Web owners acknowledge teardown.
@MainActor
final class PreparedNativeWatchTwoPlayback {
    let modelID: UUID
    let sourceID: UUID
    let requestID: UUID
    let intentID: UUID
    let wantsPlayback: Bool
    let context: ViewingPlaybackContext
    let session: StreamSession
    let player: AVPlayer
    let item: AVPlayerItem
    let isolation: NativePlayerAudioIsolation
    let proxy: LocalStreamProxy?
    let delivery: NativeWebPlaybackCandidate?
    var retirementBegan = false
    var webRetired = false
    var adopted = false
    var started = false
    var discarded = false

    init(model: LivePlayerViewModel, session: StreamSession, player: AVPlayer,
         item: AVPlayerItem, isolation: NativePlayerAudioIsolation, proxy: LocalStreamProxy? = nil,
         delivery: NativeWebPlaybackCandidate? = nil) {
        modelID = model.remoteCommandOwnerID; sourceID = session.id; requestID = model.loadRequestID
        intentID = model.nativeWatchTwoIntentID; wantsPlayback = model.userWantsPlayback
        context = model.viewingPlaybackContext; self.session = session; self.player = player
        self.item = item; self.isolation = isolation; self.proxy = proxy; self.delivery = delivery
    }
}
